// [E1-AVAIL] 일정 화면이 ① 가능일 조회 실패를 0 일로 말하지 않고,
//   ② 확정 근무와 가능일을 다른 형태로 보여 준다.
//
// ── A. ERROR ≠ ZERO ───────────────────────────────────────────────────
//   `_loadAvailability` 가 catch 에서 `debugPrint` 만 하고
//   `_availabilityDates` 를 `{}` 로 남겼다. 그래서 조회가 실패하면
//   `근무 가능일 0일 등록됨` + 미등록 안내가 떠서, 등록해 둔 사람에게
//   **등록을 다시 하라**고 말했다. 더 나쁜 것은 그 상태로 수정에 들어가면
//   `_editingDates` 가 빈 세트로 시작해 **저장 한 번에 전부 지워진다**는
//   점이다(저장은 `dates` 전체를 덮어쓰는 계약이다).
//
//   같은 화면의 초대 지역은 이미 `InviteRegionPreference.unknown()` 으로
//   ERROR 와 OFF 를 가른다([R2.3] §8). 같은 자를 가능일에도 쓴다.
//
// ── B. 확정 ≠ 가능일 ──────────────────────────────────────────────────
//   확정 #1565C0 원 7px vs 가능일 #2196F3 원 7px — 다른 마커 쌍은 전부
//   형태(별) 또는 색상환(주황·회색)으로 갈리는데 이 둘만 어느 축으로도
//   갈리지 않았다. 게다가 가능일은 마커 배열 **마지막**이라 3개가 차면
//   조용히 사라졌다.
//
//   이제 가능일은 날짜 셀의 **윤곽선**이다 — 마커 슬롯을 쓰지 않으므로
//   탈락하지 않고, "채워짐 = 약속 / 윤곽 = 의향" 위계가 선다.
//   구별의 축은 색이 아니라 형태다.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/invite_region_preference.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/models/core/worker_availability_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/my_schedule_reads.dart';
import 'package:ALfit/screens/user/my_schedule_screen.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/utils/format_helper.dart';

import 'support/visible_text.dart';

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

const _kUid = 'u1';

class _P extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: _kUid,
        username: _kUid,
        name: 'QA 지원자',
        email: '$_kUid@alfit.local',
        role: UserRole.USER,
        homeRegion: const UserRegion(province: '경기도', city: '평택시'),
        accountStatus: 'active',
      );
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

// [AV-DATE-ANCHOR 2026-10-27] 미래 날짜를 '오늘+N' 으로 만들면 월말에 다음 달로 넘어간다.
//   달력은 오늘이 든 달을 열고 바깥 날짜를 그리지 않는다(outsideDaysVisible: false) — 그래서
//   10-27 + 5 = 11-01 의 윤곽선이 화면 밖으로 빠져 AV-25 가 날짜에 따라 실패했다.
//   미래 날짜는 **다음 달(KST)의 고정 날짜**에 묶는다(언제나 미래, 서로 같은 달).
//   과거 날짜(음수)는 그대로 오늘 기준이다. 윤곽선·마커는 그 달로 실제 이동(달력 화살표)한 뒤 센다.
DateTime get _kstToday {
  final k = FormatHelper.toKstDate(DateTime.now());
  return DateTime(k.year, k.month, k.day);
}
DateTime _monthDay(int monthOffset, int day) =>
    DateTime(_kstToday.year, _kstToday.month + monthOffset, day);
DateTime _dayAhead(int d) =>
    d >= 0 ? _monthDay(1, 1 + d) : _kstToday.add(Duration(days: d));
String _key(int d) => WorkerAvailabilityModel.dateKeyFrom(_dayAhead(d));
String _monthKey(int monthOffset, int day) =>
    WorkerAvailabilityModel.dateKeyFrom(_monthDay(monthOffset, day));

ApplicationModel _app({
  required String id,
  required String status,
  required int dayOffset,
  bool longTerm = false,
}) =>
    ApplicationModel(
      id: id,
      toId: 'to1',
      uid: _kUid,
      businessId: 'biz1',
      businessName: 'QA 사업장',
      toTitle: 'QA 공고',
      status: status,
      selectedWorkType: 'QA 분류',
      startTime: '10:00',
      endTime: '11:00',
      wage: 53000,
      workDate: _dayAhead(dayOffset),
      appliedAt: DateTime.now().subtract(const Duration(days: 2)),
      applicationType: longTerm ? AppType.longTerm : AppType.shortTerm,
      workEndDate: longTerm ? _dayAhead(dayOffset + 20) : null,
      workDays: longTerm ? const ['월', '화', '수', '목', '금', '토', '일'] : null,
    );

/// 조회 횟수를 세어 재시도를 관찰한다.
class _AvailLog {
  int calls = 0;
}

MyScheduleReads _reads({
  List<String> dates = const [],
  Object? availError,
  int failTimes = 0,
  List<ApplicationModel> apps = const [],
  InviteRegionPreference pref = const InviteRegionPreference(),
  _AvailLog? log,
  Future<WorkerAvailabilityModel?>? availGate,
}) =>
    MyScheduleReads(
      myApplications: (uid) async => apps,
      myMonthlyAttendances: (
              {required String userId,
              required int year,
              required int month}) async =>
          const <AttendanceModel>[],
      myAvailability: (uid) {
        final n = log == null ? 0 : log.calls++;
        if (availGate != null) return availGate;
        if (availError != null && (failTimes == 0 || n < failTimes)) {
          return Future.error(availError);
        }
        return Future.value(dates.isEmpty
            ? null
            : WorkerAvailabilityModel(uid: uid, dates: dates, city: '평택시'));
      },
      invitePreference: (uid) async => pref,
    );

Future<void> _pump(
  WidgetTester t, {
  required MyScheduleReads reads,
  Size size = const Size(390, 1800),
  double textScale = 1.0,
  int frames = 25,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(const SizedBox.shrink());
  await t.pump(const Duration(milliseconds: 50));
  await t.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _P()),
        ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: MyScheduleScreen(reads: reads),
      ),
    ),
  );
  for (var i = 0; i < frames; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// 달력 머리의 화살표(크기 24)로 달을 옮긴다 — 실제 UI 계약(onPageChanged)을 탄다.
Future<void> _goMonth(WidgetTester t, int delta) async {
  final icon = delta > 0 ? Icons.chevron_right : Icons.chevron_left;
  for (var i = 0; i < delta.abs(); i++) {
    await t.tap(find.byWidgetPredicate((w) => w is Icon && w.icon == icon && w.size == 24));
    for (var j = 0; j < 8; j++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }
}

/// 그 날짜가 든 달로 옮긴다(오늘의 KST 달 기준).
Future<void> _showMonthOf(WidgetTester t, DateTime d) =>
    _goMonth(t, (d.year - _kstToday.year) * 12 + (d.month - _kstToday.month));

// [DU311 B5] 배너 안내는 keepWords 로 그린다 — 보이는 글자로 비교해야 _kZero 의 있음·없음 단언이 의미를 잃지 않는다.
List<String> _texts(WidgetTester t) => t
    .widgetList<Text>(find.byType(Text))
    .map((w) => visibleText(w.data ?? ''))
    .where((s) => s.isNotEmpty)
    .toList();

bool _has(WidgetTester t, String s) => _texts(t).contains(s);
String _joined(WidgetTester t) => _texts(t).join('\n');

/// 가능일 윤곽선 — 채움 없이 `AppColors.info` 테두리를 가진 원.
Iterable<Container> _outlines(WidgetTester t) =>
    t.widgetList<Container>(find.byType(Container)).where((c) {
      final d = c.decoration;
      if (d is! BoxDecoration) return false;
      if (d.shape != BoxShape.circle) return false;
      if (d.color != null) return false;
      final b = d.border;
      return b is Border && b.top.width == 1.5;
    });

/// 캘린더 셀 안의 윤곽선만(범례 항목 제외) — 셀 윤곽선은 margin 1 을 가진다.
Iterable<Container> _cellOutlines(WidgetTester t) =>
    _outlines(t).where((c) => c.margin == const EdgeInsets.all(1));

/// 확정/대기 마커 점 — 채워진 7px 원.
Iterable<Container> _filledDots(WidgetTester t) =>
    t.widgetList<Container>(find.byType(Container)).where((c) {
      final d = c.decoration;
      if (d is! BoxDecoration) return false;
      return d.shape == BoxShape.circle &&
          d.color != null &&
          c.constraints?.maxWidth == 7;
    });

const _kLoading = '근무 가능일을 확인하고 있어요';
const _kFailed = '등록한 근무 가능일을 불러오지 못했어요';
const _kRetry = '다시 시도';
const _kZero = '가능일을 등록하면 그 날 새 공고 알림을 받고, '
    "'초대 받을 지역'까지 설정하면 사업장의 근무 제안도 받을 수 있어요.";

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    initializeDateFormatting('ko');
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  group('[AV-A] 읽기 전 · 못 읽음 · 0일을 가른다', () {
    testWidgets('AV-1 [BLOCKER] 조회 실패를 "0일 등록됨"으로 말하지 않는다',
        (t) async {
      await _pump(t,
          reads: _reads(availError: StateError('가능일 조회 실패(테스트)')));
      expect(_has(t, _kFailed), isTrue);
      expect(_joined(t).contains('0일 등록됨'), isFalse);
      expect(_joined(t).contains(_kZero), isFalse,
          reason: '못 읽은 것을 미등록으로 보고 등록을 권하면 안 된다');
    });

    testWidgets('AV-2 조회 실패에는 다시 시도할 길이 있다', (t) async {
      final log = _AvailLog();
      await _pump(t,
          reads: _reads(
              availError: StateError('실패'),
              failTimes: 1,
              dates: [_key(3), _key(5)],
              log: log));
      expect(_has(t, _kRetry), isTrue);
      await t.tap(find.text(_kRetry));
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(_has(t, '근무 가능일 2일 등록됨'), isTrue,
          reason: '재시도가 성공하면 실제 등록 수를 말한다');
      expect(_has(t, _kFailed), isFalse);
    });

    testWidgets('AV-3 읽기 전은 0 일이 아니다 (LOADING)', (t) async {
      final gate = Completer<WorkerAvailabilityModel?>();
      await _pump(t, reads: _reads(availGate: gate.future), frames: 3);
      expect(_has(t, _kLoading), isTrue);
      expect(_joined(t).contains('0일 등록됨'), isFalse);
      expect(_joined(t).contains(_kZero), isFalse);
      gate.complete(null);
      for (var i = 0; i < 15; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    });

    testWidgets('AV-4 정상 0일은 등록 안내를 그대로 보여 준다', (t) async {
      await _pump(t, reads: _reads());
      expect(_joined(t).contains(_kZero), isTrue);
      expect(_has(t, _kFailed), isFalse);
      expect(_has(t, _kLoading), isFalse);
    });

    testWidgets('AV-5 정상 N일은 등록 수를 말한다', (t) async {
      await _pump(t, reads: _reads(dates: [_key(3), _key(5), _key(7)]));
      expect(_has(t, '근무 가능일 3일 등록됨'), isTrue);
      expect(_has(t, _kFailed), isFalse);
    });

    testWidgets('AV-6 초대 지역 상태와 독립이다', (t) async {
      // 가능일은 읽혔고 초대 설정만 못 읽은 경우 — 숫자는 사실대로 말한다.
      await _pump(t,
          reads: _reads(
              dates: [_key(3)],
              pref: const InviteRegionPreference.unknown()));
      expect(_has(t, '근무 가능일 1일 등록됨'), isTrue);
      expect(_joined(t).contains('초대 설정은 확인하지 못했어요'), isTrue);
      expect(_has(t, _kFailed), isFalse,
          reason: '초대 설정 실패가 가능일 실패로 번지지 않는다');
    });

    testWidgets('AV-7 가능일 실패가 초대 지역 계약을 덮지 않는다', (t) async {
      await _pump(t,
          reads: _reads(
              availError: StateError('실패'),
              pref: const InviteRegionPreference(enabled: false)));
      expect(_has(t, _kFailed), isTrue);
      // 초대 지역 행은 그대로 자기 상태를 말한다.
      expect(_joined(t).contains('초대'), isTrue);
    });
  });

  group('[AV-B] 못 읽은 상태로 덮어쓰지 않는다', () {
    testWidgets('AV-8 [BLOCKER] 조회 실패 중에는 수정에 들어가지 않는다',
        (t) async {
      await _pump(t, reads: _reads(availError: StateError('실패')));
      // 수정 진입 CTA 는 있지만, 눌러도 빈 선택 상태로 시작하지 않는다.
      final cta = find.text('가능일 설정');
      if (cta.evaluate().isNotEmpty) {
        await t.tap(cta.first);
        for (var i = 0; i < 10; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
      }
      expect(_has(t, '근무 가능일 선택'), isFalse,
          reason: '기존 값을 모르는 채 수정에 들어가면 저장 한 번에 지워진다');
      expect(_has(t, _kFailed), isTrue);
    });

    testWidgets('AV-9 정상 조회 후에는 수정에 들어간다', (t) async {
      await _pump(t, reads: _reads(dates: [_key(3)]));
      final cta = find.text('가능일 설정');
      expect(cta.evaluate(), isNotEmpty);
      await t.tap(cta.first);
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(_has(t, '근무 가능일 선택'), isTrue);
    });
  });

  group('[AV-F] 표시·수정·저장 수량이 같다 (E1-DATE)', () {
    // DEV 반례: 원본 2일 중 하나가 과거. 서버는 과거를 떨어내므로 실제로
    //   저장되는 것은 1일인데, 화면은 `2일 등록됨` · `2일 저장` 이라고 했다.
    testWidgets('AV-22 [반례] 과거 1일 + 미래 1일 → 배너는 1일', (t) async {
      await _pump(t, reads: _reads(dates: [_key(-3), _key(5)]));
      expect(_has(t, '근무 가능일 1일 등록됨'), isTrue,
          reason: '지난 날짜를 지금 등록된 가능일로 세지 않는다');
      expect(_has(t, '근무 가능일 2일 등록됨'), isFalse);
    });

    testWidgets('AV-23 [반례] 그 상태로 수정하면 버튼도 "1일 저장"', (t) async {
      await _pump(t, reads: _reads(dates: [_key(-3), _key(5)]));
      await t.tap(find.text('가능일 설정').first);
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(_has(t, '근무 가능일 선택'), isTrue);
      expect(_has(t, '1일 저장'), isTrue,
          reason: '버튼의 수는 실제 저장될 수여야 한다');
      expect(_has(t, '2일 저장'), isFalse);
    });

    testWidgets('AV-24 과거 날짜는 달력에서 가능일로 강조하지 않는다', (t) async {
      await _pump(t, reads: _reads(dates: [_key(-3)]));
      await _showMonthOf(t, _dayAhead(-3)); // [AV-DATE-ANCHOR] 과거 날짜가 든 달에서도 강조하지 않는다
      expect(_cellOutlines(t), isEmpty,
          reason: '지난 가능일을 현재 유효한 의향처럼 보이게 하지 않는다');
      // 그렇다고 "등록이 없다" 와 같은 상태는 아니다 — 유효 0일로 말한다.
      expect(_has(t, _kFailed), isFalse);
    });

    testWidgets('AV-25 미래 날짜만 있으면 그대로 센다 — 같은 달', (t) async {
      await _pump(t, reads: _reads(dates: [_monthKey(1, 3), _monthKey(1, 5)]));
      expect(_has(t, '근무 가능일 2일 등록됨'), isTrue);
      await _goMonth(t, 1);
      expect(_cellOutlines(t).length, 2, reason: '같은 달의 두 가능일이 그 달 화면에 둘 다 보인다');
    });

    testWidgets('AV-25b 미래 날짜가 달 경계를 넘으면 각 달에서 하나씩 보인다', (t) async {
      // 예: 10-27 기준 다음 달 28일 + 그다음 달 2일. 배너는 두 달을 합쳐 센다.
      await _pump(t, reads: _reads(dates: [_monthKey(1, 28), _monthKey(2, 2)]));
      expect(_has(t, '근무 가능일 2일 등록됨'), isTrue);
      expect(_cellOutlines(t), isEmpty, reason: '이번 달 화면에는 다른 달 날짜를 그리지 않는다');
      await _goMonth(t, 1);
      expect(_cellOutlines(t).length, 1, reason: '다음 달 화면 — 28일만');
      await _goMonth(t, 1);
      expect(_cellOutlines(t).length, 1, reason: '그다음 달 화면 — 2일만');
    });
  });

  group('[AV-C] 확정 근무와 가능일은 다른 형태다', () {
    testWidgets('AV-10 가능일만 있는 날짜는 윤곽선으로 표시된다', (t) async {
      await _pump(t, reads: _reads(dates: [_key(3)]));
      await _showMonthOf(t, _dayAhead(3)); // [AV-DATE-ANCHOR] 그 날짜가 든 달을 보고 센다
      expect(_cellOutlines(t).length, greaterThanOrEqualTo(1));
    });

    testWidgets('AV-11 확정 근무만 있는 날짜는 채워진 마커다 (윤곽선 아님)',
        (t) async {
      await _pump(t,
          reads: _reads(
              apps: [_app(id: 'a1', status: AppStatus.confirmed, dayOffset: 3)]));
      await _showMonthOf(t, _dayAhead(3)); // [AV-DATE-ANCHOR] 그 날짜가 든 달을 보고 센다
      expect(_filledDots(t).length, greaterThanOrEqualTo(1));
      expect(_cellOutlines(t), isEmpty,
          reason: '확정 근무를 가능일처럼 윤곽선으로 그리지 않는다');
    });

    testWidgets('AV-12 같은 날 확정 + 가능일이면 둘 다 보인다', (t) async {
      await _pump(t,
          reads: _reads(
              dates: [_key(3)],
              apps: [
                _app(id: 'a1', status: AppStatus.confirmed, dayOffset: 3)
              ]));
      await _showMonthOf(t, _dayAhead(3)); // [AV-DATE-ANCHOR] 그 날짜가 든 달을 보고 센다
      expect(_cellOutlines(t).length, greaterThanOrEqualTo(1));
      expect(_filledDots(t).length, greaterThanOrEqualTo(1),
          reason: '한 상태를 숨겨 다른 상태를 강조하지 않는다');
    });

    testWidgets('AV-13 가능일 + 대기도 둘 다 보인다', (t) async {
      await _pump(t,
          reads: _reads(
              dates: [_key(3)],
              apps: [_app(id: 'a1', status: AppStatus.pending, dayOffset: 3)]));
      await _showMonthOf(t, _dayAhead(3)); // [AV-DATE-ANCHOR] 그 날짜가 든 달을 보고 센다
      expect(_cellOutlines(t).length, greaterThanOrEqualTo(1));
      expect(_filledDots(t).length, greaterThanOrEqualTo(1));
    });

    testWidgets('AV-14 [회귀] 마커가 3개여도 가능일 윤곽선은 남는다', (t) async {
      // 단기 확정 + 장기 확정(별) + 단기 대기 = 마커 3개.
      //   예전에는 가능일이 마커 배열 마지막이라 여기서 조용히 사라졌다.
      await _pump(t,
          reads: _reads(
            dates: [_key(3)],
            apps: [
              _app(id: 'a1', status: AppStatus.confirmed, dayOffset: 3),
              _app(
                  id: 'a2',
                  status: AppStatus.confirmed,
                  dayOffset: 3,
                  longTerm: true),
              _app(id: 'a3', status: AppStatus.pending, dayOffset: 3),
            ],
          ));
      await _showMonthOf(t, _dayAhead(3)); // [AV-DATE-ANCHOR] 그 날짜가 든 달을 보고 센다
      expect(_cellOutlines(t).length, greaterThanOrEqualTo(1),
          reason: '마커 3개 제한에 가능일이 밀려나지 않는다');
    });

    testWidgets('AV-15 가능일이 없으면 윤곽선도 없다', (t) async {
      await _pump(t,
          reads: _reads(
              apps: [_app(id: 'a1', status: AppStatus.confirmed, dayOffset: 3)]));
      await _showMonthOf(t, _dayAhead(3)); // [AV-DATE-ANCHOR] 그 날짜가 든 달을 보고 센다
      expect(_cellOutlines(t), isEmpty);
    });

    testWidgets('AV-16 조회 실패 시 가능일 윤곽선을 그리지 않는다', (t) async {
      await _pump(t, reads: _reads(availError: StateError('실패')));
      expect(_cellOutlines(t), isEmpty,
          reason: '모르는 것을 "가능일 있음"으로도 그리지 않는다');
      expect(_has(t, _kFailed), isTrue);
    });
  });

  group('[AV-D] 범례·배율·폭', () {
    testWidgets('AV-17 범례의 가능일 항목이 셀과 같은 윤곽 형태다', (t) async {
      await _pump(t, reads: _reads(dates: [_key(3)]));
      expect(_has(t, '근무 가능일'), isTrue,
          reason: "'가능' 한 글자는 무엇이 가능한지 모호하다");
      // 범례 항목은 셀 윤곽선과 달리 margin 이 없다 — 둘 다 존재해야 한다.
      final legend = _outlines(t).where((c) => c.margin == null);
      expect(legend.length, greaterThanOrEqualTo(1));
    });

    testWidgets('AV-18 320dp 배율 1.0 에서 넘치지 않는다', (t) async {
      await _pump(t,
          reads: _reads(dates: [_key(3)]),
          size: const Size(320, 1800));
      await _showMonthOf(t, _dayAhead(3)); // [AV-DATE-ANCHOR] 그 날짜가 든 달을 보고 센다
      expect(t.takeException(), isNull);
    });

    testWidgets('AV-19 320dp 배율 2.0 에서 넘치지 않는다', (t) async {
      await _pump(t,
          reads: _reads(dates: [_key(3)]),
          size: const Size(320, 2600),
          textScale: 2.0);
      await _showMonthOf(t, _dayAhead(3)); // [AV-DATE-ANCHOR] 그 날짜가 든 달을 보고 센다
      expect(t.takeException(), isNull);
    });

    testWidgets('AV-20 411dp 배율 1.3 에서 넘치지 않는다', (t) async {
      await _pump(t,
          reads: _reads(dates: [_key(3)]),
          size: const Size(411, 2000),
          textScale: 1.3);
      await _showMonthOf(t, _dayAhead(3)); // [AV-DATE-ANCHOR] 그 날짜가 든 달을 보고 센다
      expect(t.takeException(), isNull);
    });
  });

  group('[AV-E] 소스 계약', () {
    test('AV-21 가능일은 마커 배열에 들어가지 않는다', () {
      final src = File('lib/widgets/calendar/schedule_calendar.dart')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
      expect(src.contains('markers.add(_availabilityDot())'), isFalse,
          reason: '마커 슬롯을 쓰면 3개 제한에서 다시 탈락한다');
      expect(src.contains('_availabilityDot'), isFalse);
      expect(src.contains('IgnorePointer'), isTrue,
          reason: '윤곽선이 날짜 탭 영역을 가리면 안 된다');
    });
  });
}
