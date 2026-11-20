// [SIM-WORKER-WAGE-VIEW] 근로자 월 근무 내역 · 급여 상세 — 날짜·상태·지급 예정일.
//
// 근거(설치 앱 1.0.21+25, 기기 TZ=GMT, DEV 6HB9 confirmed+STALE_MANUAL_REVIEW):
//   · 목록 행·상세 머리글이 KST 10/17 근무를 **10/16** 으로 그렸다
//   · 상세 실제 출퇴근이 KST 20:00/21:00 을 **11:00/12:00** 으로 그렸다
//   · 같은 건을 목록은 '지급 예정', 상세는 '지급정보 확인 필요'라고 했다
//   · NO_SHOW 0원 근무가 목록에서 '지급 예정'이었다
//   · 지급 예정일(10/18)이 근로자 화면 어디에도 없었다
//
// 픽스처는 저장 원장과 같은 **절대 시각**이다:
//   workDate       = KST 자정 instant (2026-10-16T15:00Z = KST 10/17 00:00)
//   checkIn/Out    = 실제 시각 Timestamp (2026-10-17T11:00Z = KST 20:00)
//   paymentDueDate = 서버 srvCalculatePaymentDueDate 가 만든 **KST 달력일의
//                    UTC 자정** (2026-10-18T00:00Z, DEV 실측값과 같은 모양)
//
// 이 파일은 KST 기본 환경과 `TZ=UTC` 양쪽에서 통과해야 한다:
//   flutter test test/worker_wage_date_status_test.dart
//   TZ=UTC flutter test test/worker_wage_date_status_test.dart
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
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/income_detail_reads.dart';
import 'package:ALfit/screens/user/income_detail_screen.dart';
import 'package:ALfit/screens/user/wage_detail_screen.dart';

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

/// KST 달력일 d 의 KST 자정 instant — 저장소의 workDate 관례.
///
/// `Timestamp.toDate()` 는 **기기 local** DateTime 을 돌려준다. 픽스처도 같은
/// 모양으로 만든다 — utc 플래그 DateTime 을 주면 모든 기기에서 GMT 기기처럼
/// 보여 KST 기기의 실제 동작을 재현하지 못한다.
DateTime _kstMidnight(int m, int d) =>
    DateTime.utc(2026, m, d - 1, 15).toLocal();

/// KST 벽시계 → 절대 시각(기기 local).
DateTime _kstAt(int m, int d, int h, [int min = 0]) =>
    DateTime.utc(2026, m, d, h - 9, min).toLocal();

/// 서버가 쓴 지급 예정일 — KST 달력일의 UTC 자정, 읽으면 기기 local.
DateTime _due(int m, int d) => DateTime.utc(2026, m, d).toLocal();

ApplicationModel _app(String id, int day,
        {String start = '20:00', String end = '21:00'}) =>
    ApplicationModel(
      id: id,
      businessId: 'b1',
      businessName: '골든패스 테스트 사업장',
      toTitle: 'QA',
      workDate: _kstMidnight(10, day),
      startTime: start,
      endTime: end,
      uid: 'u1',
      selectedWorkType: 'QA 분류',
      wage: 12000,
      wageType: 'hourly',
      status: 'CONFIRMED',
      appliedAt: _kstMidnight(10, 1),
    );

AttendanceModel _att(
  String appId,
  int day, {
  required String status,
  required String wageStatus,
  required int finalWage,
  bool? reviewRequired,
  String? readinessReason,
  DateTime? checkIn,
  DateTime? checkOut,
  DateTime? paymentDueDate,
}) =>
    AttendanceModel(
      id: '${appId}_att',
      applicationId: appId,
      userId: 'u1',
      businessId: 'b1',
      businessName: '골든패스 테스트 사업장',
      workDate: _kstMidnight(10, day),
      workType: 'QA 분류',
      status: status,
      wageStatus: wageStatus,
      adminConfirmed: true,
      finalWage: finalWage,
      checkInAt: checkIn,
      checkOutAt: checkOut,
      paymentDueDate: paymentDueDate,
      wageAccountReviewRequired: reviewRequired,
      wageAccountReadinessReason: readinessReason,
      createdAt: _kstMidnight(10, day),
    );

// ── 네 가지 건 ─────────────────────────────────────────────────
// 6HB9 — confirmed + 계좌 재확인(STALE_MANUAL_REVIEW), 지급 예정일 10/18.
final _a6hb9 = _app('a6hb9', 17);
final _t6hb9 = _att('a6hb9', 17,
    status: AttendanceModel.statusPresent,
    wageStatus: AttendanceModel.wageConfirmed,
    finalWage: 12000,
    reviewRequired: true,
    readinessReason: 'STALE_MANUAL_REVIEW',
    checkIn: _kstAt(10, 17, 20),
    checkOut: _kstAt(10, 17, 21),
    paymentDueDate: _due(10, 18));

// NO_SHOW — 근태 상태가 노쇼, 금액 0원, 급여 단계는 confirmed.
final _aNoShow = _app('anoshow', 13);
final _tNoShow = _att('anoshow', 13,
    status: AttendanceModel.statusNoShow,
    wageStatus: AttendanceModel.wageConfirmed,
    finalWage: 0);

// 정상 confirmed — 계좌 문제 없음.
final _aOk = _app('aok', 14);
final _tOk = _att('aok', 14,
    status: AttendanceModel.statusPresent,
    wageStatus: AttendanceModel.wageConfirmed,
    finalWage: 12000,
    checkIn: _kstAt(10, 14, 20),
    checkOut: _kstAt(10, 14, 21),
    paymentDueDate: _due(10, 15));

// transferred — 기존 의미 그대로.
final _aXfer = _app('axfer', 15);
final _tXfer = _att('axfer', 15,
    status: AttendanceModel.statusPresent,
    wageStatus: AttendanceModel.wageTransferred,
    finalWage: 12000,
    checkIn: _kstAt(10, 15, 20),
    checkOut: _kstAt(10, 15, 21),
    paymentDueDate: _due(10, 16));

// 정상 근무인데 금액이 0원 — 노쇼로 분류하면 안 된다.
final _aZero = _app('azero', 16);
final _tZero = _att('azero', 16,
    status: AttendanceModel.statusPresent,
    wageStatus: AttendanceModel.wageConfirmed,
    finalWage: 0,
    checkIn: _kstAt(10, 16, 20),
    checkOut: _kstAt(10, 16, 21),
    paymentDueDate: _due(10, 17));

IncomeDetailReads _reads() => IncomeDetailReads(
      myApplications: (uid) async =>
          [_a6hb9, _aNoShow, _aOk, _aXfer, _aZero],
      myMonthlyAttendances: (
              {required String userId,
              required int year,
              required int month}) async =>
          (year == 2026 && month == 10)
              ? [_t6hb9, _tNoShow, _tOk, _tXfer, _tZero]
              : const <AttendanceModel>[],
    );

Future<void> _pumpIncome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(430, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>(create: (_) => _P()),
      ChangeNotifierProvider<NotificationProvider>(
          create: (_) => NotificationProvider()),
    ],
    child: MaterialApp(
      home: IncomeDetailScreen(
          initialYear: 2026, initialMonth: 10, reads: _reads()),
    ),
  ));
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpDetail(
    WidgetTester tester, ApplicationModel app, AttendanceModel att) async {
  tester.view.physicalSize = const Size(430, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: WageDetailScreen(application: app, attendance: att),
  ));
  await tester.pump();
}

/// 목록에서 그 날짜 행 안의 텍스트들.
List<String> _rowTexts(WidgetTester tester, String dateLabel) {
  final date = find.text(dateLabel);
  expect(date, findsOneWidget, reason: '행 날짜 "$dateLabel" 이 있어야 한다');
  final row = find.ancestor(of: date, matching: find.byType(InkWell)).first;
  return tester
      .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
      .map((t) => t.data ?? '')
      .toList();
}

List<String> _allTexts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR');
  });

  // 시간대 이름은 Windows 에서 캐시돼 TZ 를 바꿔도 그대로다 — offset 으로 표시한다.
  final tz = 'UTC+${DateTime(2026, 10, 17).timeZoneOffset.inHours}';

  testWidgets('WD-1 [$tz] 목록 — 근무일은 KST, 상태는 상세와 같은 판정', (t) async {
    await _pumpIncome(t);

    final r6 = _rowTexts(t, '10/17(토)');
    expect(r6, contains('12,000원'));
    expect(r6, contains('지급정보 확인 필요'),
        reason: '계좌 재확인이 필요한 확정 건을 목록만 지급 예정이라고 하면 안 된다');
    expect(r6, isNot(contains('지급 예정')));

    final rNo = _rowTexts(t, '10/13(화)');
    expect(rNo, contains('0원'));
    expect(rNo, contains('노쇼 처리됨'));
    expect(rNo, isNot(contains('지급 예정')),
        reason: '노쇼로 0원이 된 근무는 지급될 돈이 아니다');

    expect(_rowTexts(t, '10/14(수)'), contains('지급 예정'));
    expect(_rowTexts(t, '10/15(목)'), contains('이체 처리 완료'));

    final rZero = _rowTexts(t, '10/16(금)');
    expect(rZero, contains('지급 예정'),
        reason: '금액 0원만으로 정상 근무를 노쇼로 분류하지 않는다');
    expect(rZero, isNot(contains('노쇼 처리됨')));

    // 하루 밀린 날짜가 남아 있지 않다.
    expect(find.text('10/12(월)'), findsNothing);
  });

  testWidgets('WD-2 [$tz] 상세 6HB9 — 머리글·출퇴근 KST, 지급 예정일 10/18, 이체 완료로 읽히지 않음',
      (t) async {
    await _pumpDetail(t, _a6hb9, _t6hb9);
    final texts = _allTexts(t);

    expect(texts, contains('10월 17일(토)'));
    expect(texts, contains('10월 급여 상세'));
    expect(texts, contains('20:00 ~ 21:00'));
    expect(find.text('20:00'), findsOneWidget, reason: '실제 출근 = KST 20:00');
    expect(find.text('21:00'), findsOneWidget, reason: '실제 퇴근 = KST 21:00');
    expect(texts.where((s) => s.contains('11:00') || s.contains('12:00')),
        isEmpty);

    expect(texts, contains('지급정보 확인 필요'));
    expect(texts, contains('지급 예정일'));
    expect(texts, contains('10월 18일(일)'));
    for (final s in texts) {
      expect(s, isNot(contains('이체 처리 완료')));
      expect(s, isNot(contains('지급 완료')));
      expect(s, isNot(contains('입금')));
    }
  });

  testWidgets('WD-3 [$tz] 상세 — 노쇼는 지급 예정일·지급 예정을 말하지 않는다', (t) async {
    await _pumpDetail(t, _aNoShow, _tNoShow);
    final texts = _allTexts(t);
    expect(texts, contains('10월 13일(화)'));
    expect(texts, contains('노쇼 처리됨'));
    expect(texts, isNot(contains('지급 예정')));
    expect(texts, isNot(contains('지급 예정일')));
  });

  testWidgets('WD-4 [$tz] 상세 — 정상 확정은 지급 예정 + 예정일, 이체 완료는 그대로', (t) async {
    await _pumpDetail(t, _aOk, _tOk);
    var texts = _allTexts(t);
    expect(texts, contains('지급 예정'));
    expect(texts, contains('10월 15일(목)'));

    await _pumpDetail(t, _aXfer, _tXfer);
    texts = _allTexts(t);
    expect(texts, contains('이체 처리 완료'));
    expect(texts, isNot(contains('지급 예정일')),
        reason: '이체가 끝난 건에 "예정"을 다시 말하지 않는다');
  });

  testWidgets('WD-5 [$tz] 상세 — 자정을 넘는 퇴근은 KST 다음날로 표시', (t) async {
    final app = _app('anight', 17, start: '23:30', end: '08:30');
    final att = _att('anight', 17,
        status: AttendanceModel.statusPresent,
        wageStatus: AttendanceModel.wageCalculated,
        finalWage: 108000,
        checkIn: _kstAt(10, 17, 23, 30),
        checkOut: _kstAt(10, 18, 8, 30));
    await _pumpDetail(t, app, att);
    expect(find.text('23:30'), findsOneWidget);
    expect(find.text('10/18 08:30'), findsOneWidget);
  });
}
