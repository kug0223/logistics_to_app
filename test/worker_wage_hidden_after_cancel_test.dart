// [HB3-VISIBILITY 2026-11-25] 관리자 '마감 취소' 뒤 근무자에게 급여 금액이 보이지 않는다.
//
//   마감 취소(callableCancelFinalConfirmation)는 wageStatus 를 confirmed → calculated 로
//   되돌리고 finalWage·wageDetail 은 재마감용으로 남긴다. 관리자 확인창은
//   "지원자에게 급여가 숨겨집니다"라고 안내한다. 근무자 화면은 확정·이체 완료 건만
//   금액·내역을 보여야 한다(AttendanceModel.displayWage / displayWageDetail).
//
//   HC-1 급여 상세 — 마감 취소(calculated) 건: 남은 finalWage·세부 내역 0 · '예상 급여'(지원서 기준) · '정산 중'
//   HC-2 급여 상세 — 같은 금액의 confirmed 건: 금액·세부 내역 보임(대조)
//   HC-3 수입 상세 행 — 마감 취소 건: 남은 finalWage 0 · '정산 중' · 예상 금액
//   HC-4 수입 상세 행 — confirmed 건: 확정 금액 · '지급 예정'(대조)
//   HC-5 모델 — displayWage/displayWageDetail 은 confirmed·transferred 만
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
import 'package:ALfit/models/core/wage_detail_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/income_detail_reads.dart';
import 'package:ALfit/screens/user/income_detail_screen.dart';
import 'package:ALfit/screens/user/wage_detail_screen.dart';

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

DateTime _kstMidnight(int m, int d) => DateTime.utc(2026, m, d - 1, 15).toLocal();
DateTime _kstAt(int m, int d, int h, [int min = 0]) => DateTime.utc(2026, m, d, h - 9, min).toLocal();

// 지원서 기준 예상 금액 = 20:00–21:00 · 시급 12,000 = 12,000원.
ApplicationModel _app(String id, int day) => ApplicationModel(
      id: id,
      businessId: 'b1',
      businessName: '골든패스 테스트 사업장',
      toTitle: 'QA',
      workDate: _kstMidnight(10, day),
      startTime: '20:00',
      endTime: '21:00',
      uid: 'u1',
      selectedWorkType: 'QA 분류',
      wage: 12000,
      wageType: 'hourly',
      // [impl_39 · AUD-3 M3 픽스처 갱신] 수입 상세의 예상 금액은 이제 약속 휴게를 뺀 하루 예상(휴게 모름 = 확인 필요)이다 —
      //   서버가 지원 시 적는 약속 휴게 0 을 실제처럼 준다(기대 12,000원 그대로).
      breakMinutes: 0,
      status: 'CONFIRMED',
      appliedAt: _kstMidnight(10, 1),
    );

// 관리자 계산·확정 값(취소 뒤에도 문서에 남는 값) = 108,715원 · 기본급 120,000원.
WageDetailModel _wd() => WageDetailModel(
      wageType: 'hourly',
      baseWage: 12000,
      workMinutes: 600,
      baseAmount: 120000,
      totalAmount: 120000,
      incomeTaxDeduction: 11285,
      netWage: 108715,
    );

AttendanceModel _att(String appId, int day, String wageStatus) => AttendanceModel(
      id: '${appId}_att',
      applicationId: appId,
      userId: 'u1',
      businessId: 'b1',
      businessName: '골든패스 테스트 사업장',
      workDate: _kstMidnight(10, day),
      workType: 'QA 분류',
      status: AttendanceModel.statusPresent,
      wageStatus: wageStatus,
      adminConfirmed: true,
      finalWage: 108715,
      wageDetail: _wd(),
      checkInAt: _kstAt(10, day, 20),
      checkOutAt: _kstAt(10, day, 21),
      createdAt: _kstMidnight(10, day),
    );

final _aCancel = _app('acancel', 17);
final _tCancel = _att('acancel', 17, AttendanceModel.wageCalculated); // 마감 취소 뒤 상태
final _aOk = _app('aok', 16);
final _tOk = _att('aok', 16, AttendanceModel.wageConfirmed);

List<String> _allTexts(WidgetTester t) => t.widgetList<Text>(find.byType(Text)).map((x) => x.data ?? '').toList();

List<String> _rowTexts(WidgetTester t, String dateLabel) {
  final date = find.text(dateLabel);
  expect(date, findsOneWidget, reason: '행 날짜 "$dateLabel" 이 있어야 한다');
  final row = find.ancestor(of: date, matching: find.byType(InkWell)).first;
  return t.widgetList<Text>(find.descendant(of: row, matching: find.byType(Text))).map((x) => x.data ?? '').toList();
}

Future<void> _pumpDetail(WidgetTester t, ApplicationModel app, AttendanceModel att) async {
  t.view.physicalSize = const Size(430, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: WageDetailScreen(application: app, attendance: att)));
  await t.pump();
}

Future<void> _pumpIncome(WidgetTester t) async {
  t.view.physicalSize = const Size(430, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final reads = IncomeDetailReads(
    myApplications: (uid) async => [_aCancel, _aOk],
    myMonthlyAttendances: ({required String userId, required int year, required int month}) async =>
        (year == 2026 && month == 10) ? [_tCancel, _tOk] : const <AttendanceModel>[],
  );
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>(create: (_) => _P()),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
    ],
    child: MaterialApp(home: IncomeDetailScreen(initialYear: 2026, initialMonth: 10, reads: reads)),
  ));
  for (var i = 0; i < 25; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR');
  });

  testWidgets('HC-1 급여 상세 — 마감 취소(calculated) 건은 남은 금액·세부 내역을 보이지 않는다', (t) async {
    await _pumpDetail(t, _aCancel, _tCancel);
    final texts = _allTexts(t);
    expect(texts.where((x) => x.contains('108,715')), isEmpty, reason: '취소된 확정 금액(finalWage)이 보이면 안 된다 · $texts');
    expect(texts.where((x) => x.contains('120,000')), isEmpty, reason: '취소된 계산 내역(기본급)이 보이면 안 된다');
    expect(texts, isNot(contains('기본급')), reason: '세부 내역 모드가 아니어야 한다');
    expect(texts, contains('예상 급여'), reason: '확정 전 금액은 지원서 기준 예상 금액이라고 말한다');
    expect(texts, contains('12,000원'), reason: '예상 금액 = 20:00–21:00 × 12,000');
    expect(texts, contains('정산 중'), reason: '상태 = 정산 중(금액 확정 전)');
    expect(texts, isNot(contains('급여 계산 완료')));
  });

  testWidgets('HC-2 급여 상세 — confirmed 건은 금액·세부 내역을 보인다(대조)', (t) async {
    await _pumpDetail(t, _aOk, _tOk);
    final texts = _allTexts(t);
    expect(texts.where((x) => x.contains('108,715')), isNotEmpty, reason: '확정 실수령액이 보여야 한다 · $texts');
    expect(texts, contains('기본급'));
    expect(texts, isNot(contains('예상 급여')));
  });

  testWidgets('HC-3/4 수입 상세 — 마감 취소 행은 금액 숨김 · confirmed 행은 확정 금액', (t) async {
    await _pumpIncome(t);
    final cancel = _rowTexts(t, '10/17(토)');
    expect(cancel.where((x) => x.contains('108,715')), isEmpty, reason: '취소된 확정 금액이 행에 보이면 안 된다 · $cancel');
    expect(cancel, contains('정산 중'));
    expect(cancel, contains('12,000원'), reason: '확정 전 행은 예상 금액(다른 정산 중 행과 같은 규칙)');
    final ok = _rowTexts(t, '10/16(금)');
    expect(ok.where((x) => x.contains('108,715')), isNotEmpty, reason: '확정 행은 확정 금액 · $ok');
    expect(ok, contains('지급 예정'));
  });

  test('HC-5 모델 — displayWage/displayWageDetail 은 confirmed·transferred 만', () {
    for (final s in [AttendanceModel.wagePending, AttendanceModel.wageCalculated]) {
      final a = _att('x', 10, s);
      expect(a.finalWage, 108715, reason: '문서에는 남아 있다(재마감용)');
      expect(a.displayWage, isNull, reason: '$s 는 근무자에게 금액 없음');
      expect(a.displayWageDetail, isNull, reason: '$s 는 근무자에게 내역 없음');
    }
    for (final s in [AttendanceModel.wageConfirmed, AttendanceModel.wageTransferred]) {
      final a = _att('x', 10, s);
      expect(a.displayWage, 108715);
      expect(a.displayWageDetail, isNotNull);
    }
  });
}
