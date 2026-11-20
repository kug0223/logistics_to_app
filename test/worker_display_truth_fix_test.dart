// [DEVICE-MISMATCH-FIX] 근로자 화면 — 근태 결말·종료 시각이 지원서 상태보다 먼저다.
//
// DEV 실측(10-20, xZah): RUBE 출퇴근 완료·급여 pending / Zdn7 10:00~11:00 근태 없음 /
//   6HB9 급여 확정 / QAvG·Zujr·XNjJ CONTRACT_PENDING + NO_SHOW.
//   DEVICE(원본 APK) 오표시: 일정 `확정 근무 6일`(5개 날짜 6건), 상세 `실근무 1h`(근태
//   없음), 수입 예상 24,000 = 6HB9 + **Zdn7**(일 안 함, RUBE 는 빠짐), 일정 카드
//   RUBE `근무 완료`·노쇼 계약대기 `계약 진행 중`.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/utils/calendar_helper.dart';
import 'package:ALfit/widgets/calendar/schedule_card.dart';

DateTime _kst(int y, int mo, int d, [int h = 0, int mi = 0]) =>
    DateTime.utc(y, mo, d, h, mi).subtract(const Duration(hours: 9));

ApplicationModel _app(
  String id, {
  required DateTime workDate,
  String status = AppStatus.confirmed,
  String start = '10:00',
  String end = '11:00',
  int wage = 12000,
}) =>
    ApplicationModel(
      id: id,
      toId: 'to_$id',
      uid: 'u1',
      businessId: 'biz1',
      businessName: '골든패스 사업장',
      toTitle: 'QA',
      status: status,
      selectedWorkType: 'QA 분류',
      startTime: start,
      endTime: end,
      wage: wage,
      wageType: 'hourly',
      workDate: workDate,
      appliedAt: workDate.subtract(const Duration(days: 3)),
    );

AttendanceModel _att(
  String appId, {
  required DateTime workDate,
  String status = AttendanceModel.statusPresent,
  DateTime? checkIn,
  DateTime? checkOut,
  String wageStatus = 'pending',
  int? finalWage,
}) =>
    AttendanceModel(
      id: 'att-$appId',
      applicationId: appId,
      userId: 'u1',
      businessId: 'biz1',
      businessName: '골든패스 사업장',
      workDate: workDate,
      workType: 'QA 분류',
      checkInAt: checkIn,
      checkOutAt: checkOut,
      status: status,
      wageStatus: wageStatus,
      finalWage: finalWage,
      createdAt: workDate,
    );

class _FakeApp extends Fake
    with MockPlatformInterfaceMixin
    implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(
      apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp(
          {String? name, FirebaseOptions? options}) async =>
      _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

class _P extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
      uid: 'u1',
      username: 'u1',
      name: '김근로',
      email: 'u1@alfit.local',
      role: UserRole.USER);
}

Future<String> _cardStatus(WidgetTester t, ApplicationModel app,
    {AttendanceModel? att}) async {
  t.view.physicalSize = const Size(411, 900);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
    create: (_) => _P(),
    child: MaterialApp(
        home: Scaffold(body: ScheduleCard(application: app, attendance: att))),
  ));
  await t.pump();
  return t
      .widgetList<Text>(find.byType(Text))
      .map((w) => w.data ?? '')
      .join(' | ');
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ko');
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  // 10-20 14:58 KST — 기기 관찰 시각.
  final now = _kst(2026, 10, 20, 14, 58);
  final d20 = _kst(2026, 10, 20);

  group('종료 시각 — ApplicationModel.shiftEndInstant', () {
    test('WD-1 10:00~11:00 은 그날 11:00 KST 에 끝난다', () {
      final a = _app('zdn7', workDate: d20);
      expect(a.shiftEndInstant, _kst(2026, 10, 20, 11));
      expect(a.hasShiftEndedAt(_kst(2026, 10, 20, 10, 59)), isFalse);
      expect(a.hasShiftEndedAt(_kst(2026, 10, 20, 11)), isTrue);
    });

    test('WD-2 자정을 넘기는 23:00~07:00 은 다음 날 07:00 에 끝난다', () {
      final a = _app('n', workDate: d20, start: '23:00', end: '07:00');
      expect(a.shiftEndInstant, _kst(2026, 10, 21, 7));
      expect(a.hasShiftEndedAt(_kst(2026, 10, 21, 6, 59)), isFalse);
    });

    test('WD-3 시각을 못 읽으면 끝났다고 단정하지 않는다', () {
      final a = _app('x', workDate: d20, start: '', end: '');
      expect(a.shiftEndInstant, isNull);
      expect(a.hasShiftEndedAt(now), isFalse);
    });
  });

  group('예상수입 — 끝난 미출근 근무는 벌 예정이 아니다', () {
    final zdn7 = _app('zdn7', workDate: d20);
    final rube = _app('rube', workDate: d20, start: '13:00', end: '14:00');
    final later = _app('later', workDate: d20, start: '20:00', end: '21:00');
    final atts = [
      _att('rube',
          workDate: d20,
          checkIn: _kst(2026, 10, 20, 12, 36),
          checkOut: _kst(2026, 10, 20, 14, 0)),
    ];

    test('WI-1 [DEV 재현 Zdn7] now 를 주면 종료된 미출근은 제외', () {
      expect(CalendarHelper.isScheduledIncome(zdn7, atts, now: now), isFalse);
    });

    test('WI-2 아직 오지 않은 근무는 그대로 예정', () {
      expect(CalendarHelper.isScheduledIncome(later, atts, now: now), isTrue);
    });

    test('WI-3 출근한 근무는 예정이 아니다(기존 규칙 유지)', () {
      expect(CalendarHelper.isScheduledIncome(rube, atts, now: now), isFalse);
    });

    test('WI-4 now 를 주지 않는 호출부는 예전과 같다(하위 호환)', () {
      expect(CalendarHelper.isScheduledIncome(zdn7, atts), isTrue);
    });

    test('WI-5 월 합계 — 남는 것은 아직 오지 않은 근무뿐', () {
      final total = CalendarHelper.getTotalIncome([zdn7, rube, later], d20,
          attendances: atts, now: now);
      expect(total, 12000);
    });
  });

  group('일정 카드 상태 배지', () {
    final past = _kst(2026, 10, 12);

    testWidgets('SC-1 [DEV 재현] CONTRACT_PENDING + NO_SHOW → 노쇼', (t) async {
      final s = await _cardStatus(
          t, _app('zujr', workDate: past, status: AppStatus.contractPending),
          att: _att('zujr', workDate: past, status: AttendanceModel.statusNoShow));
      expect(s, contains('노쇼'));
      expect(s, isNot(contains('계약 진행 중')));
    });

    testWidgets('SC-2 [DEV 재현 Zdn7] 확정 · 근태 없음 · 시간 종료 → 출근 기록 없음',
        (t) async {
      final s = await _cardStatus(t, _app('zdn7', workDate: past));
      expect(s, contains('출근 기록 없음'));
      expect(s, isNot(contains('확정 ')));
    });

    testWidgets('SC-3 [DEV 재현 RUBE] 퇴근 완료 · 급여 pending → 정산 중', (t) async {
      final s = await _cardStatus(t, _app('rube', workDate: past),
          att: _att('rube',
              workDate: past,
              checkIn: past.add(const Duration(hours: 13)),
              checkOut: past.add(const Duration(hours: 14))));
      expect(s, contains('정산 중'));
      expect(s, isNot(contains('근무 완료')));
    });

    testWidgets('SC-4 아직 오지 않은 확정 근무는 그대로 확정', (t) async {
      final s = await _cardStatus(t, _app('f', workDate: _kst(2099, 1, 5)));
      expect(s, contains('확정'));
      expect(s, isNot(contains('출근 기록 없음')));
    });
  });

  group('문구 단위 — 소스 고정', () {
    String src(String p) => File(p).readAsStringSync();

    test('SP-1 일정 요약 확정 근무는 건 단위(같은 날 두 근무 = 2건)', () {
      final s = src('lib/screens/user/my_schedule_screen.dart');
      expect(s.contains("'\$_cachedConfirmedCount건'"), isTrue);
      expect(s.contains("'\$_cachedConfirmedCount일'"), isFalse);
    });

    test('SP-2 일정 상세의 시간은 예정 시간이라고 말한다', () {
      final s = src('lib/widgets/dialogs/schedule_detail_dialog.dart');
      expect(s.contains("'· 예정 \$_netTime'"), isTrue);
      expect(s.contains("'· 실근무 \$_netTime'"), isFalse);
    });

    test('SP-3 수입 상세 — 일했고 급여 확정 전인 행은 정산 중', () {
      final s = src('lib/screens/user/income_detail_screen.dart');
      expect(s.contains("'정산 중'"), isTrue);
      expect(s.contains("statusLabel = app == null ? '근무 완료 · 금액 확인 필요' : '근무 완료'"),
          isFalse);
    });

    test('SP-4 수입 상세 — 출근 기록 없이 끝난 근무 행은 근무 예정 금액을 말하지 않는다', () {
      final s = src('lib/screens/user/income_detail_screen.dart');
      final i = s.indexOf("statusLabel = '출근 기록 없음'");
      expect(i, greaterThan(-1));
      final j = s.indexOf("statusLabel = '근무 예정'");
      expect(i < j, isTrue, reason: '종료 판정이 근무 예정 분기보다 먼저다');
      expect(s.substring(i - 400, i).contains('app.hasShiftEndedAt('), isTrue);
    });
  });
}
