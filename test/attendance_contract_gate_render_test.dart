// [CONTRACT-BEFORE-CHECKIN] 출근 화면 — 계약 동의 전에는 출근 버튼이 닫힌다 (2026-10-25 사용자 지시)
//
//   "관리자가 확정 시 바로 지원자에게 계약서를 보내게 하고 있고, 지원자는 그 계약서를
//    동의 안하면 출근버튼 비활성화로 진행되어야해"
//
//   판정은 지원서 status 가 아니라 화면이 **새로 읽은 계약 문서**다(서버 callableCheckIn 과 같은 식).
//   직접 지원(CONTRACT_PENDING)과 초대 수락(계약 전 CONFIRMED)을 같은 기준으로 본다.
//
//   CG-1  계약 없음                       → 닫힘 · '아직 근로계약서를 받지 않았어요'
//   CG-2  사업주 서명 대기                → 닫힘 · '사업주 서명을 기다리고 있어요'
//   CG-3  근로자 동의 대기(발송됨)         → 닫힘 · 동의 CTA · 결근 가능 안내(R1)
//   CG-4  양측 서명 완료                  → 열림
//   CG-5  번들 계약(applicationIds 로만 묶임) 완료 → 열림
//   음성 대조(완료 계약인데 이 근무의 동의가 아님 → 닫힘):
//   CG-6  무효(voided)만 있음 · CG-7 다른 지원서 · CG-8 다른 사람 · CG-9 다른 사업장
//   CG-10 completed 인데 근로자 서명 시각 없음
//   CG-11 읽기 실패 → 닫힘 · '확인하지 못했어요' · 다시 시도 → 새로 읽어 완료면 열림(호출 수 2)
//   CG-12 초대 수락(CONFIRMED) + 계약 없음 → 닫힘 / 같은 초대 + 완료 → 열림
//   CG-13 화면을 다시 읽을 때마다 계약도 다시 읽는다(캐시 없음) — 동의 대기 → 완료로 바뀌면 열린다
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/visible_text.dart'; // [DU255] keepWords 문구는 보이는 글자로 찾는다
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_model.dart' show AttendanceRules;
import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/attendance_check_reads.dart';
import 'package:ALfit/screens/user/attendance_check_screen.dart';
import 'package:ALfit/widgets/common/loading_button.dart';

import 'support/checkin_contract_fixture.dart';

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

DateTime _kst(int y, int mo, int d, [int h = 0, int mi = 0]) =>
    DateTime.utc(y, mo, d, h, mi).subtract(const Duration(hours: 9));

/// 직접 지원 확정(CONTRACT_PENDING) 또는 초대 수락(CONFIRMED) — 근무 20:00~21:00, 지금 20:00
ApplicationModel _work({String status = AppStatus.contractPending}) =>
    ApplicationModel(
      id: 'app1',
      toId: 'to1',
      uid: 'u1',
      businessId: 'biz1',
      businessName: 'QA 사업장',
      toTitle: '당일 QA',
      status: status,
      selectedWorkType: 'QA 분류',
      startTime: '20:00',
      endTime: '21:00',
      wage: 12000,
      workDate: _kst(2026, 10, 17),
      appliedAt: _kst(2026, 10, 17, 17, 57),
      attendancePolicySnapshot: const AttendanceRules(),
    );

class _Reads {
  _Reads(this.app, this.next);
  final ApplicationModel app;

  /// 호출마다 다음 응답을 낸다(마지막 것을 반복). Exception 이면 throw.
  final List<Object> next;
  int contractCalls = 0;

  AttendanceCheckReads build() => AttendanceCheckReads(
        myApplications: (uid) async => [app],
        todayAttendance: (
                {required String userId,
                required String applicationId}) async =>
            null as AttendanceModel?,
        myContracts: (uid) async {
          final r = next[contractCalls < next.length ? contractCalls : next.length - 1];
          contractCalls++;
          if (r is Exception) throw r;
          return r as List<EmploymentContractModel>;
        },
      );
}

Future<void> _pump(WidgetTester tester, _Reads reads) async {
  tester.view.physicalSize = const Size(390, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final now = _kst(2026, 10, 17, 20, 0);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _P()),
        ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
          home: AttendanceCheckScreen(reads: reads.build(), clock: () => now)),
    ),
  );
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

LoadingButton _btn(WidgetTester tester) => tester.widget<LoadingButton>(
    find.ancestor(of: findVisibleText('출근하기'), matching: find.byType(LoadingButton)));

bool _open(WidgetTester t) => _btn(t).onPressed != null;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  final app = _work();

  testWidgets('CG-1 계약 없음 → 닫힘', (t) async {
    final r = _Reads(app, [<EmploymentContractModel>[]]);
    await _pump(t, r);
    expect(findVisibleText('출근하기'), findsOneWidget, reason: '버튼은 비활성으로 보인다(사라지지 않는다)');
    expect(_open(t), isFalse);
    expect(find.text('아직 근로계약서를 받지 않았어요'), findsOneWidget);
    expect(findVisibleText('계약서 확인하고 동의하기'), findsNothing);
    expect(r.contractCalls, 1);
  });

  testWidgets('CG-2 사업주 서명 대기 → 닫힘', (t) async {
    await _pump(t, _Reads(app, [[checkInContractFor(app, status: ContractStatus.pendingEmployer)]]));
    expect(_open(t), isFalse);
    expect(find.text('사업주 서명을 기다리고 있어요'), findsOneWidget);
    expect(findVisibleText('계약서 확인하고 동의하기'), findsNothing);
  });

  testWidgets('CG-3 근로자 동의 대기 → 닫힘 · 동의 CTA · 결근 안내', (t) async {
    await _pump(t, _Reads(app, [[checkInContractFor(app, status: ContractStatus.pendingWorker)]]));
    expect(_open(t), isFalse);
    expect(find.text('근로계약서에 동의해야 출근할 수 있어요'), findsOneWidget);
    expect(findVisibleText('계약서 확인하고 동의하기'), findsOneWidget);
    expect(find.textContaining('결근 처리될 수 있어요'), findsOneWidget);
  });

  testWidgets('CG-4 양측 서명 완료 → 열림', (t) async {
    await _pump(t, _Reads(app, [[checkInContractFor(app)]]));
    expect(_open(t), isTrue);
    expect(find.byKey(const ValueKey('checkin-contract-gate')), findsNothing);
  });

  testWidgets('CG-5 번들 계약(applicationIds) 완료 → 열림', (t) async {
    await _pump(t, _Reads(app, [[checkInContractFor(app, bundled: true)]]));
    expect(_open(t), isTrue);
  });

  final negatives = <String, EmploymentContractModel>{
    'CG-6 무효만': checkInContractFor(app, status: ContractStatus.voided),
    'CG-7 다른 지원서': checkInContractFor(app, applicationId: 'other_app'),
    'CG-8 다른 사람': checkInContractFor(app, workerId: 'u2'),
    'CG-9 다른 사업장': checkInContractFor(app, businessId: 'biz2'),
    'CG-10 근로자 서명 시각 없음': checkInContractFor(app, workerSigned: false),
  };
  negatives.forEach((name, c) {
    testWidgets('$name → 닫힘(음성 대조)', (t) async {
      await _pump(t, _Reads(app, [[c]]));
      expect(_open(t), isFalse, reason: '$name 계약은 이 근무의 동의가 아니다');
      expect(find.text('아직 근로계약서를 받지 않았어요'), findsOneWidget);
    });
  });

  testWidgets('CG-11 읽기 실패 → 닫힘 · 다시 시도로 새로 읽으면 열림', (t) async {
    final r = _Reads(app, [Exception('unavailable'), [checkInContractFor(app)]]);
    await _pump(t, r);
    expect(_open(t), isFalse, reason: '모름은 동의가 아니다');
    expect(find.text('계약서 상태를 확인하지 못했어요'), findsOneWidget);
    expect(findVisibleText('근무 정보를 불러오지 못했습니다'), findsNothing,
        reason: '계약 읽기 실패가 근무 목록 실패로 번지지 않는다');
    expect(r.contractCalls, 1);
    await t.tap(findVisibleText('다시 시도'));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(r.contractCalls, 2);
    expect(_open(t), isTrue);
  });

  final inv = _work(status: AppStatus.confirmed);
  testWidgets('CG-12a 초대 수락(CONFIRMED) + 계약 없음 → 닫힘', (t) async {
    await _pump(t, _Reads(inv, [<EmploymentContractModel>[]]));
    expect(_open(t), isFalse, reason: '초대 수락 CONFIRMED 는 계약 전이다 — status 로 동의를 추정하지 않는다');
    expect(find.text('아직 근로계약서를 받지 않았어요'), findsOneWidget);
  });
  testWidgets('CG-12b 초대 수락(CONFIRMED) + 동의 대기 → 닫힘 · CTA', (t) async {
    await _pump(t, _Reads(inv, [[checkInContractFor(inv, status: ContractStatus.pendingWorker)]]));
    expect(_open(t), isFalse);
    expect(findVisibleText('계약서 확인하고 동의하기'), findsOneWidget);
  });
  testWidgets('CG-12c 초대 수락(CONFIRMED) + 양측 서명 완료 → 열림', (t) async {
    await _pump(t, _Reads(inv, [[checkInContractFor(inv)]]));
    expect(_open(t), isTrue);
  });

  testWidgets('CG-13 다시 읽을 때마다 계약도 새로 읽는다 — 대기 → 완료', (t) async {
    final r = _Reads(app, [
      [checkInContractFor(app, status: ContractStatus.pendingWorker)],
      [checkInContractFor(app)],
    ]);
    await _pump(t, r);
    expect(_open(t), isFalse);
    // 당겨서 새로고침 — 화면의 RefreshIndicator.onRefresh(_loadTodayWorks) 를 그대로 부른다
    final refresh = t.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh();
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await refresh;
    expect(r.contractCalls, 2);
    expect(_open(t), isTrue);
  });
}
