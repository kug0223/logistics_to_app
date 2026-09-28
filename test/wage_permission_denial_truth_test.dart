// [R7-P3-2 P32-D] `canManageWorkers` 는 있고 `canManageWage` 는 없는 서브관리자가
// 급여에서 막혔을 때 **화면에 무엇이 남는가**.
//
// 같은 앱이 "권한 없음"을 세 가지로 말한다:
//   · 계약 관리 — 화면이 열리고 `접근 권한이 없습니다` + **담당자 안내**
//   · 급여      — 토스트 한 줄 + `return`. 화면 전환도 담당자 안내도 없다
//   · 팀원 관리 — 메뉴 자체가 없다(`isBusinessAdmin` 게이트, 권한 이양 설계)
//
// 여기서는 **렌더할 수 있는 쪽(계약)** 을 실제로 세워 대조 기준을 만든다.
// 권한을 부여·해제하지 않는다 — fake provider 의 현재 상태만 읽는다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/admin_contract_management_screen.dart';
import 'package:ALfit/screens/business_admin/admin_contract_reads.dart';

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

const kBiz = 'biz1';

/// 근로자 관리는 되고 급여·계약은 안 되는 서브관리자.
class _SubAdmin extends UserProvider {
  _SubAdmin({required bool contract}) : _contract = contract;
  bool _contract;

  /// 권한을 **부여/해제하지 않는다** — 관리자가 회수한 상황을 재현할 때만
  /// 이 provider 의 현재 상태를 바꾸고 알린다.
  void revokeContract() {
    _contract = false;
    notifyListeners();
  }

  MemberPermissions get _perms => MemberPermissions(
        canManageTo: true,
        canManageWorkers: true,
        canManageWage: false, // 이 축이 이 셀의 주제다
        canManageContract: _contract,
      );

  @override
  UserModel? get currentUser => UserModel(
        uid: 'sub1',
        username: 'sub1',
        name: '이대리',
        email: 'sub1@alfit.local',
        role: UserRole.USER,
        subAdminBusinessIds: const [kBiz],
        createdAt: DateTime(2026, 1, 1),
      );
  @override
  bool get isSubAdmin => true;
  @override
  bool get isBusinessAdmin => false;
  @override
  bool get isSuperAdmin => false;
  @override
  bool get isAdminMode => true;
  @override
  bool get permissionsLoaded => true;
  @override
  String? get selectedSubAdminBusinessId => kBiz;
  @override
  MemberPermissions? permissionsForBusiness(String businessId) => _perms;
  @override
  PermissionCheck checkCurrentBusiness(
          bool Function(MemberPermissions p) check) =>
      check(_perms) ? PermissionCheck.allowed : PermissionCheck.denied;
  @override
  bool can(bool Function(MemberPermissions p) check) => check(_perms);
  @override
  bool canForBusiness(
          String businessId, bool Function(MemberPermissions p) check) =>
      check(_perms);
  @override
  VoidCallback watchBusinessPermissions(String businessId) => () {};
}

AdminContractReads _reads() => AdminContractReads(
      contractsPaged: (businessId, {startAfterId, statusFilter}) async =>
          (items: <EmploymentContractModel>[], lastDocId: null, hasMore: false),
      unsentApplications: (businessId) async => <ApplicationModel>[],
    );


late _SubAdmin gProvider;

/// 실제 navigation 구조 그대로 — 계약 화면을 **route 로 민다**.
/// 그래야 "권한이 없으면 화면이 닫힌다" 가 관찰 가능한 사실이 된다.
Future<void> _pushContract(
  WidgetTester tester, {
  required bool contract,
  Size size = const Size(390, 1400),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  gProvider = _SubAdmin(contract: contract);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(value: gProvider),
        ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.push(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) => AdminContractManagementScreen(
                      businessId: kBiz,
                      businessName: '강남 물류센터',
                      reads: _reads(),
                    ),
                  ),
                ),
                child: const Text('계약 관리 열기'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('계약 관리 열기'));
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  // [R7-P3-3 P33-D] 이 자리에는 원래 "처음부터 권한이 없으면 화면이 **말없이**
  //   닫힌다" 는 사실이 고정돼 있었다. P3-3 에서 그 무안내 종료를 고쳤으므로
  //   기대값을 새 정상 동작으로 옮긴다 — 재현 테스트를 지우지 않고 갱신한다.
  //   같은 사건의 상세 검증은 `action_context_truth_test.dart` (ACX-1~5) 에 있다.
  testWidgets('[WPD-1] 처음부터 계약 권한이 없으면 화면이 남아 이유와 담당자를 말한다',
      (tester) async {
    await _pushContract(tester, contract: false);

    // 더 이상 말없이 사라지지 않는다.
    expect(find.text('계약 관리 열기'), findsNothing);
    expect(find.text('접근 권한이 없습니다'), findsOneWidget);
    expect(find.text('계약 관리 권한이 있는 관리자에게 문의하세요.'), findsOneWidget);
  });

  testWidgets('[WPD-2] 권한이 있으면 화면이 열린다 (양성 대조)', (tester) async {
    await _pushContract(tester, contract: true);

    expect(find.text('계약 관리 열기'), findsNothing); // 앞 화면을 덮었다
    expect(find.text('접근 권한이 없습니다'), findsNothing);
  });

  testWidgets('[WPD-3] 머무는 중 회수되면 그때는 이유와 담당자를 말한다', (tester) async {
    await _pushContract(tester, contract: true);
    expect(find.text('접근 권한이 없습니다'), findsNothing);

    // 관리자가 권한을 거둬들인 상황 — provider 상태만 바꾸고 알린다.
    gProvider.revokeContract();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // "계약이 없다"가 아니라 "볼 수 없다"이고, 다음에 누구에게 갈지 말한다.
    expect(find.text('접근 권한이 없습니다'), findsOneWidget);
    expect(find.text('계약 관리 권한이 있는 관리자에게 문의하세요.'), findsOneWidget);
  });

  testWidgets('[WPD-4] 320dp x 2.0 — 회수 안내가 잘리지 않는다', (tester) async {
    await _pushContract(tester,
        contract: true, size: const Size(320, 2000), textScale: 2.0);
    gProvider.revokeContract();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(tester.takeException(), isNull);
    expect(find.text('접근 권한이 없습니다'), findsOneWidget);
    expect(find.text('계약 관리 권한이 있는 관리자에게 문의하세요.'), findsOneWidget);
  });
}
