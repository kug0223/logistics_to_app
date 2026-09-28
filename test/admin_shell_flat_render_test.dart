import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/screens/business_admin/admin_contract_management_screen.dart';
import 'package:ALfit/screens/business_admin/admin_contract_reads.dart';
import 'package:ALfit/screens/common/settings_screen.dart';
import 'package:ALfit/screens/super_admin/system_settings_screen.dart';
import 'package:ALfit/widgets/common/app_page_scaffold.dart';
import 'package:ALfit/widgets/common/gradient_scaffold.dart';

/// [R7-P1-6 P16-M·P16-A] 관리자 shell 전환을 **실제 위젯으로** 확인한다.
///
///   `settings_screen` 은 역할이 공유하는 화면이다 — 관리자는 `관리`, USER 는
///   `설정` 으로 같은 파일을 본다. 그래서 shell 을 통째로 바꾸면 지원자 쪽
///   레이아웃까지 바뀐다(P2 소유). 역할별로 무엇이 그려지는지 여기서 본다.
///
///   범위: **shell 과 상단 프로필 블록**이다. 각 메뉴 항목의 목적지·권한 게이트는
///   기존 증거(P1-4 목적지·R5 권한)를 재사용하고 여기서 다시 판정하지 않는다.

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
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async =>
      _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

class _RoleProvider extends UserProvider {
  _RoleProvider(this._role, {this.subAdminAdminMode = false});

  final UserRole _role;
  final bool subAdminAdminMode;

  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '김의관',
        email: 'u1@alfit.local',
        role: _role,
        managedBusinessIds: _role == UserRole.BUSINESS_ADMIN ? const ['biz1'] : const [],
        subAdminBusinessIds:
            _role == UserRole.USER && subAdminAdminMode ? const ['biz1'] : const [],
      );

  @override
  bool get isAdminMode => subAdminAdminMode;

  // 역할 판정은 private 필드를 보는 getter 들도 있다 — 함께 맞춘다.
  @override
  bool get isSuperAdmin => _role == UserRole.SUPER_ADMIN;

  @override
  bool get isBusinessAdmin => _role == UserRole.BUSINESS_ADMIN;

  @override
  bool get isSubAdmin => _role == UserRole.USER && subAdminAdminMode;

  @override
  bool get subAdminPermissionsLoaded => true;

  @override
  PermissionCheck checkCurrentBusiness(
          bool Function(MemberPermissions p) check) =>
      PermissionCheck.allowed;

  @override
  bool can(bool Function(MemberPermissions p) check) => true;
}

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  required UserProvider provider,
  Size size = const Size(390, 900),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(value: provider),
        ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: home,
      ),
    ),
  );
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// [R7-P1-6 P16-C] 계약 화면의 읽기 경계 — 실패/정상을 골라 넣는다.
AdminContractReads _contractReads({
  Object? listError,
  Object? unsentError,
  List<EmploymentContractModel> items = const [],
  List<ApplicationModel> unsent = const [],
}) =>
    AdminContractReads(
      contractsPaged: (
        businessId, {
        ContractStatus? statusFilter,
        String? startAfterId,
      }) async {
        if (listError != null) throw listError;
        return (items: items, lastDocId: null, hasMore: false);
      },
      unsentApplications: (businessId) async {
        if (unsentError != null) throw unsentError;
        return unsent;
      },
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('ASF-1 관리자는 flat admin shell 로 관리 탭을 본다', (tester) async {
    await _pump(tester, const SettingsScreen(),
        provider: _RoleProvider(UserRole.BUSINESS_ADMIN));

    expect(tester.takeException(), isNull);
    expect(find.byType(AppPageScaffold), findsOneWidget);
    expect(find.byType(GradientScaffold), findsNothing);
    expect(find.text('관리'), findsWidgets);
    // 프로필 블록이 사라지지 않았다 — body 최상단 카드로 내려왔다.
    expect(find.text('김의관'), findsWidgets);
  });

  testWidgets('ASF-2 USER 의 설정은 지원자 공통 레이아웃 그대로다', (tester) async {
    await _pump(tester, const SettingsScreen(),
        provider: _RoleProvider(UserRole.USER));

    expect(tester.takeException(), isNull);
    // 이 화면은 역할이 공유한다 — 지원자 쪽은 P2 소유이므로 바꾸지 않았다.
    expect(find.byType(GradientScaffold), findsOneWidget);
    expect(find.byType(AppPageScaffold), findsNothing);
    expect(find.text('설정'), findsWidgets);
  });

  testWidgets('ASF-3 SubAdmin 은 모드에 따라 두 shell 을 오간다', (tester) async {
    // 사용자 모드 — 지원자 레이아웃
    await _pump(tester, const SettingsScreen(),
        provider: _RoleProvider(UserRole.USER, subAdminAdminMode: false));
    expect(find.byType(GradientScaffold), findsOneWidget);

    // 관리 모드 — flat admin shell
    await _pump(tester, const SettingsScreen(),
        provider: _RoleProvider(UserRole.USER, subAdminAdminMode: true));
    expect(tester.takeException(), isNull);
    expect(find.byType(AppPageScaffold), findsOneWidget);
    expect(find.text('관리'), findsWidgets);
  });

  testWidgets('ASF-4 320dp·배율 1.3 에서 프로필 카드와 목록이 함께 보인다',
      (tester) async {
    await _pump(tester, const SettingsScreen(),
        provider: _RoleProvider(UserRole.BUSINESS_ADMIN),
        size: const Size(320, 800),
        textScale: 1.3);

    expect(tester.takeException(), isNull);
    expect(find.text('김의관'), findsWidgets);
    // 목록이 잘리지 않고 스크롤 가능하다.
    expect(find.byType(ListView), findsWidgets);
    await tester.drag(find.byType(ListView).first, const Offset(0, -200));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ASF-5 super-admin 시스템 설정도 flat shell 이다 (shell 범위)',
      (tester) async {
    await _pump(tester, const SystemSettingsScreen(),
        provider: _RoleProvider(UserRole.SUPER_ADMIN));

    expect(tester.takeException(), isNull);
    expect(find.byType(AppPageScaffold), findsOneWidget);
    expect(find.byType(GradientScaffold), findsNothing);
    expect(find.text('시스템 설정'), findsWidgets);
  });

  testWidgets('ASF-6 super-admin 시스템 설정 320dp·배율 2.0', (tester) async {
    await _pump(tester, const SystemSettingsScreen(),
        provider: _RoleProvider(UserRole.SUPER_ADMIN),
        size: const Size(320, 900),
        textScale: 2.0);

    expect(tester.takeException(), isNull);
    expect(find.text('시스템 설정'), findsWidgets);
  });
// ══════════════════════════════════════════════════════════
  // [R7-P1-6 P16-C] 계약 목록 — 조회 실패를 완료로 말하지 않는다
  //   조회가 실제로 실패하는 경로를 그대로 쓴다(주입 없이 Firestore 없음).
  // ══════════════════════════════════════════════════════════

  testWidgets('ACM-1 계약서 목록 조회 실패는 "없습니다"가 아니다', (tester) async {
    await _pump(
        tester,
        AdminContractManagementScreen(
            businessId: 'biz1',
            businessName: '강남 물류센터',
            reads: _contractReads(listError: StateError('contract list down'))),
        provider: _RoleProvider(UserRole.BUSINESS_ADMIN));

    tester.takeException(); // 조회 실패 자체가 이 테스트의 조건이다
    expect(find.text('계약서 목록을 불러오지 못했습니다'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
    expect(find.text('계약서가 없습니다'), findsNothing);
  });

  testWidgets('ACM-2 미발송 탭 실패를 "모두 발송했다"로 말하지 않는다',
      (tester) async {
    await _pump(
        tester,
        AdminContractManagementScreen(
            businessId: 'biz1',
            initialTab: 1,
            reads: _contractReads(unsentError: StateError('unsent down'))),
        provider: _RoleProvider(UserRole.BUSINESS_ADMIN));

    tester.takeException();
    expect(find.text('미발송 계약서를 확인하지 못했습니다'), findsOneWidget);
    // 완료 주장(체크 아이콘 + '미발송 계약서 없음')이 나오지 않는다.
    expect(find.text('미발송 계약서 없음'), findsNothing);
    expect(find.byIcon(Icons.check_circle_outline), findsNothing);
  });

  testWidgets('ACM-3 320dp·배율 1.3 에서 실패 상태와 재시도가 접근 가능하다',
      (tester) async {
    await _pump(
        tester,
        AdminContractManagementScreen(
            businessId: 'biz1',
            businessName: '서울특별시 강남구 제1물류센터 야간운영팀',
            reads: _contractReads(listError: StateError('contract list down'))),
        provider: _RoleProvider(UserRole.BUSINESS_ADMIN),
        size: const Size(320, 700),
        textScale: 1.3);

    tester.takeException();
    expect(find.text('계약서 목록을 불러오지 못했습니다'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
  });
testWidgets('ACM-4 정상 0건은 실패와 다른 문구다', (tester) async {
    await _pump(
        tester,
        AdminContractManagementScreen(
            businessId: 'biz1', initialTab: 1, reads: _contractReads()),
        provider: _RoleProvider(UserRole.BUSINESS_ADMIN));

    expect(tester.takeException(), isNull);
    expect(find.text('미발송 계약서 없음'), findsOneWidget);
    expect(find.text('미발송 계약서를 확인하지 못했습니다'), findsNothing);
  });
}
