// [AUD-3 M3 · impl_39] 근로자 월 예정 수입(예상수입 · 근무 예정)이 하루 예상 helper 와 같은 계산을 쓴다.
//   근무별 원 단위 반올림 금액의 합 · 계산 불가 근무(약속 휴게 모름 · 종료=시작 · 누락 단가 · 월급 · 유형 모름)는
//   합계에서 빼고 건수로 말한다 · 월급을 근무일마다 더하지 않는다.
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/income_detail_reads.dart';
import 'package:ALfit/screens/user/income_detail_screen.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/calendar_helper.dart';
import 'package:ALfit/utils/expected_daily_wage.dart';
import 'package:ALfit/utils/text_layout.dart';

class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

class _UserDouble extends UserProvider {
  @override
  UserModel? get currentUser =>
      UserModel(uid: 'u1', username: 'u1', name: '김근로', email: 'u1@alfit.local', role: UserRole.USER, accountStatus: 'active');
  @override
  bool get isUser => true;
  @override
  bool get isSubAdmin => false;
  @override
  bool get isBusinessAdmin => false;
  @override
  bool get isSuperAdmin => false;
  @override
  bool get isAdminMode => false;
  @override
  bool get permissionsLoaded => true;
}

/// 다음 달(KST) 10일 정오 — 아직 오지 않은 근무(isScheduledIncome = true).
DateTime _nextMonthDay(int day) {
  final k = DateTime.now().toUtc().add(const Duration(hours: 9));
  final m = DateTime.utc(k.year, k.month + 1, day, 3); // KST 12:00
  return m.toLocal();
}

ApplicationModel _app(String id,
    {String? wageType = 'hourly',
    int wage = 11000,
    String start = '09:00',
    String end = '11:00',
    int? brk = 0,
    DateTime? workDate,
    String type = AppType.shortTerm,
    List<String>? workDays,
    DateTime? workEndDate}) {
  final d = workDate ?? DateTime(2026, 7, 10);
  return ApplicationModel.fromMap({
    'uid': 'u1',
    'businessId': 'b1',
    'businessName': 'QA 사업장',
    'status': AppStatus.confirmed,
    'type': type,
    'workDate': Timestamp.fromDate(d),
    'appliedAt': Timestamp.fromDate(d),
    'startTime': start,
    'endTime': end,
    'wage': wage,
    if (wageType != null) 'wageType': wageType,
    if (brk != null) 'breakMinutes': brk,
    if (workDays != null) 'workDays': workDays,
    if (workEndDate != null) 'workEndDate': Timestamp.fromDate(workEndDate),
    'selectedWorkType': '분류',
  }, id);
}

/// 변경 전 계산(비교표 근거 · 시험 안에서만) — 휴게 미차감 · 종료 ≤ 시작이면 +1,440 · 시급 외는 wage 그대로.
int _oldShift(ApplicationModel app) {
  if (app.wageType == 'hourly') {
    int toMin(String t) {
      final p = t.split(':');
      return int.parse(p[0]) * 60 + int.parse(p[1]);
    }
    final s = toMin(app.startTime);
    var e = toMin(app.endTime);
    if (e <= s) e += 1440;
    return (app.wage * (e - s) / 60.0).round();
  }
  return app.wage;
}

void main() {
  group('M3-1 근무 1회 금액 = 하루 예상 helper (변경 전 → 후)', () {
    final cases = <(String, ApplicationModel, int?)>[
      ('시급 2시간 · 휴게 0', _app('a'), 22000),
      ('시급 9시간 체류 · 휴게 60 → 8시간', _app('b', start: '09:00', end: '18:00', brk: 60), 88000),
      ('시급 종료=시작 → 계산 불가(24시간 아님)', _app('c', start: '09:00', end: '09:00'), null),
      ('시급 약속 휴게 모름 → 계산 불가(0 으로 채우지 않음)', _app('d', brk: null), null),
      ('시급 야간 22–06 · 휴게 60 → 7시간', _app('e', wage: 10000, start: '22:00', end: '06:00', brk: 60), 70000),
      ('일급 100,000 → 그대로', _app('f', wageType: 'daily', wage: 100000), 100000),
      ('일급 누락 단가(0) → 계산 불가', _app('g', wageType: 'daily', wage: 0), null),
      ('월급 → 근무 1회 금액 없음', _app('h', wageType: 'monthly', wage: 2500000), null),
      ('유형 모름(레거시 null) → 근무 1회 금액 없음', _app('i', wageType: null, wage: 100000), null),
      ('반올림 — 10,001 × 7분 = 1,166.78 → 1,167', _app('j', wage: 10001, start: '09:00', end: '09:07'), 1167),
    ];
    for (final (name, app, expected) in cases) {
      test(name, () {
        expect(CalendarHelper.expectedShiftWage(app), expected);
        // ignore: avoid_print
        print('M3_COMPARE | $name | before=${_oldShift(app)} | after=${expected ?? '확인 필요'}');
      });
    }
  });

  group('M3-2 월 합계 — 근무별 반올림 합 · 계산 불가는 건수로', () {
    test('단기 3건: 22,000 + 88,000 + 휴게 모름 → 합계 110,000 · 확인 필요 1건', () {
      final r = CalendarHelper.getTotalIncomeDetail(
          [_app('a'), _app('b', start: '09:00', end: '18:00', brk: 60), _app('d', brk: null)], DateTime(2026, 7, 15));
      expect(r.total, 110000);
      expect(r.unknownShifts, 1);
      expect(CalendarHelper.getTotalIncome(
          [_app('a'), _app('b', start: '09:00', end: '18:00', brk: 60), _app('d', brk: null)], DateTime(2026, 7, 15)),
          110000, reason: '예전 진입점도 같은 합계');
    });

    test('장기 월급 — 근무일마다 월급을 더하지 않는다(예전 2,500,000 × 근무일수)', () {
      final lt = _app('m',
          wageType: 'monthly',
          wage: 2500000,
          type: AppType.longTerm,
          workDate: DateTime(2026, 7, 1),
          workDays: const ['월', '화', '수', '목', '금'],
          workEndDate: DateTime(2026, 12, 31));
      final r = CalendarHelper.getTotalIncomeDetail([lt], DateTime(2026, 7, 15));
      expect(r.total, 0);
      expect(r.unknownShifts, greaterThan(15), reason: '7월 평일 근무일수만큼 확인 필요');
      // ignore: avoid_print
      print('M3_COMPARE | 장기 월급 7월 | before=${2500000 * r.unknownShifts} | after=합계 0 · 확인 필요 ${r.unknownShifts}건');
    });

    test('장기 시급 — 근무일수 × 근무 1회 예상(휴게 차감)', () {
      final lt = _app('n',
          wage: 10000,
          start: '09:00',
          end: '18:00',
          brk: 60,
          type: AppType.longTerm,
          workDate: DateTime(2026, 7, 1),
          workDays: const ['월'],
          workEndDate: DateTime(2026, 12, 31));
      final r = CalendarHelper.getTotalIncomeDetail([lt], DateTime(2026, 7, 15));
      expect(r.unknownShifts, 0);
      expect(r.total % 80000, 0, reason: '근무 1회 80,000(8시간) 의 배수');
      expect(r.total, greaterThan(0));
    });
  });

  group('M3-5 부분합 표기', () {
    test('모두 계산 가능 · 일부만 · 하나도 없음', () {
      expect(ExpectedWageText.partialTotal(110000, 0), '110,000원');
      expect(ExpectedWageText.partialTotal(110000, 1), '110,000원 + 확인 필요');
      expect(ExpectedWageText.partialTotal(0, 3), '확인 필요', reason: "계산 불가만 있으면 '0원' 이 아니다");
      expect(ExpectedWageText.partialTotal(0, 0), '0원', reason: '정말 0 이면 0원');
    });
  });

  group('M3-3 화면 연결(원문 보조)', () {
    String code(String p) => File(p).readAsStringSync();
    test('홈 · 수입 상세는 같은 근무 1회 함수를 쓰고 옛 환산 함수가 없다', () {
      final home = code('lib/screens/user/user_home_screen.dart');
      final inc = code('lib/screens/user/income_detail_screen.dart');
      final sched = code('lib/screens/user/my_schedule_screen.dart');
      expect(home.contains('CalendarHelper.expectedShiftWage(a)'), isTrue);
      expect(home.contains('_scheduledDailyWage'), isFalse);
      expect(home.contains("label: '금액 확인 필요'"), isTrue);
      expect(inc.contains('CalendarHelper.expectedShiftWage(a)'), isTrue);
      expect(inc.contains('_dailyWageOf'), isFalse);
      expect(sched.contains('CalendarHelper.getTotalIncomeDetail('), isTrue);
      expect(sched.contains("'금액 확인 필요 \$_cachedIncomeUnknown건 · 예상수입에 넣지 않았어요'"), isTrue);
      expect(home.contains('ExpectedWageText.partialTotal(wageScheduled, scheduledUnknown)'), isTrue);
      expect(home.contains('ExpectedWageText.partialTotal(wageTotal, scheduledUnknown)'), isTrue);
      expect(inc.contains('_amountOrUnknown(wageTotal, unknownShifts: valueUnknown)'), isTrue);
      expect(inc.contains('ExpectedWageText.partialTotal(amount, unknownShifts)'), isTrue);
      expect(sched.contains('_cachedTotalIncome, _cachedIncomeUnknown + (_applications.length >= 200 ? 1 : 0))'), isTrue);
    });
  });

  group('M3-4 수입 상세 화면', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));
    setUpAll(() async {
      FirebasePlatform.instance = _FakeCore();
      await Firebase.initializeApp();
      await initializeDateFormatting('ko_KR', null);
      await initializeDateFormatting('ko', null);
    });

    for (final v in const [(id: 'W', w: 390.0, h: 2400.0, s: 1.0), (id: 'N', w: 320.0, h: 3200.0, s: 2.0)]) {
      testWidgets('M3-4-${v.id} 근무 예정 22,000원 + 금액 확인 필요 1건 · 그 행 금액은 \'0원\' 이 아니다', (t) async {
        final d = _nextMonthDay(10);
        final k = DateTime.now().toUtc().add(const Duration(hours: 9));
        final nm = DateTime.utc(k.year, k.month + 1, 1);
        final apps = [
          _app('ok', workDate: d),
          _app('unk', workDate: _nextMonthDay(12), brk: null),
        ];
        final overflows = <String>[];
        final prev = FlutterError.onError;
        FlutterError.onError = (e) {
          final m = e.exceptionAsString();
          if (m.contains('overflowed')) {
            final where = e.toString().split('\n').where((l) => l.contains('lib/')).take(1).join();
            overflows.add('${m.split('\n').first} @ ${where.trim()}');
          } else {
            prev?.call(e);
          }
        };
        t.view.physicalSize = Size(v.w, v.h);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        await t.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<UserProvider>(create: (_) => _UserDouble()),
            ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
          ],
          child: MaterialApp(
            theme: RoleTheme.workerTheme,
            builder: (ctx, c) =>
                MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: c!),
            home: IncomeDetailScreen(
              initialYear: nm.year,
              initialMonth: nm.month,
              reads: IncomeDetailReads(
                myApplications: (uid) async => apps,
                myMonthlyAttendances: ({required String userId, required int year, required int month}) async =>
                    const <AttendanceModel>[],
              ),
            ),
          ),
        ));
        for (var i = 0; i < 20; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        FlutterError.onError = prev;
        final texts = t
            .widgetList<Text>(find.byType(Text, skipOffstage: false))
            .map((x) => TextLayout.plain(x.data ?? x.textSpan?.toPlainText() ?? ''))
            .toList();
        expect(texts, contains('22,000원'), reason: '근무 예정 = 계산 가능한 근무만');
        expect(texts, contains('금액 확인 필요'));
        expect(texts, contains('1건'));
        expect(texts.where((s) => s == '금액 확인 필요').length, greaterThanOrEqualTo(2),
            reason: '요약 행 이름 + 휴게 모름 근무 행의 금액 자리');
        expect(texts.contains('44,000원'), isFalse, reason: '휴게 모름을 0 으로 채워 22,000 을 더했다');
        // [판정296] 근무 예정 · 예상 수입은 부분합을 전체처럼 말하지 않는다.
        expect(texts.where((x) => x == '22,000원 + 확인 필요').length, 2, reason: '근무 예정 + 예상 수입 · $texts');
        if (v.id == 'W') {
          expect(overflows, isEmpty, reason: overflows.join(' | '));
        } else {
          // 320×640@2.0 의 요약 행(_incomeRow: 라벨 + Spacer + 값)과 근무 내역 행 넘침은 **기존**이다 — before 사본에서
          //   같은 화면(계산 가능한 근무 2건)이 4건 넘쳤다(impl_39 logs/ovf_diag_before.log). DU 트랙 종료로 배치 교정은
          //   BACKLOG(AUD-4 ⑤) 로 올리고, 여기서는 기록만 한다.
          // ignore: avoid_print
          print('M3_N_OVERFLOWS=${overflows.length} ${overflows.join(' | ')}');
        }
      });
    }
  });
}
