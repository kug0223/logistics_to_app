// [R7-P3-3] 행동 **직전**에 화면이 무엇을 말하는가 — 세 경계.
//
//  P33-D  권한이 처음부터 없는 서브관리자의 계약 진입 (F4)
//  P33-X1 동명이인 계정의 블랙리스트·제재 해제 확인창 (F7)
//  P33-X2 TO 한도의 단위·적용 시점 (F6)
//
// 쓰기는 한 번도 실행하지 않는다 — 확인창을 여는 데까지만 간다.
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
import 'package:ALfit/screens/super_admin/all_users_reads.dart';
import 'package:ALfit/screens/super_admin/all_users_screen.dart';
import 'package:ALfit/screens/super_admin/to_limit_reads.dart';
import 'package:ALfit/screens/super_admin/to_limit_settings_screen.dart';

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

// ════════════════════════════════════════════════════════════════════════════
// P33-D — 계약 권한이 처음부터 없는 서브관리자
// ════════════════════════════════════════════════════════════════════════════

/// 근로자 관리는 되고 계약은 안 되는 **정상** 서브관리자.
class _SubAdmin extends UserProvider {
  _SubAdmin({required this.contract, this.member = true});
  final bool contract;

  /// false 면 이 사업장과 관계가 없는 진입이다.
  final bool member;

  MemberPermissions get _perms => MemberPermissions(
        canManageTo: true,
        canManageWorkers: true,
        canManageWage: false,
        canManageContract: contract,
      );

  @override
  UserModel? get currentUser => UserModel(
        uid: 'sub1',
        username: 'sub1',
        name: '이대리',
        email: 'sub1@alfit.local',
        role: UserRole.USER,
        subAdminBusinessIds: member ? const [kBiz] : const ['other'],
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

AdminContractReads _contractReads() => AdminContractReads(
      contractsPaged: (businessId, {startAfterId, statusFilter}) async =>
          (items: <EmploymentContractModel>[], lastDocId: null, hasMore: false),
      unsentApplications: (businessId) async => <ApplicationModel>[],
    );

Future<void> _pushContract(
  WidgetTester tester, {
  required bool contract,
  bool member = true,
  Size size = const Size(390, 1400),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(
            create: (_) => _SubAdmin(contract: contract, member: member)),
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
                      reads: _contractReads(),
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

// ════════════════════════════════════════════════════════════════════════════
// P33-X1 — 동명이인
// ════════════════════════════════════════════════════════════════════════════

class _Super extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'sa1',
        username: 'sa1',
        name: '운영자',
        email: 'sa@alfit.local',
        role: UserRole.SUPER_ADMIN,
        createdAt: DateTime(2026, 1, 1),
      );
  @override
  bool get isSuperAdmin => true;
  @override
  bool get isBusinessAdmin => false;
  @override
  bool get isSubAdmin => false;
  @override
  bool get isAdminMode => true;
  @override
  bool get permissionsLoaded => true;
}

/// 이름은 같고 아이디·상태가 다른 두 계정.
final _sameName = <Map<String, dynamic>>[
  {
    'uid': 'u1',
    'username': 'minsu01',
    'name': '김민수',
    'email': 'minsu01@alfit.local',
    'role': 'USER',
    'isBlacklisted': true,
    'createdAt': DateTime(2026, 1, 1).millisecondsSinceEpoch,
  },
  {
    'uid': 'u2',
    'username': 'minsu77',
    'name': '김민수',
    'email': 'minsu77@alfit.local',
    'role': 'USER',
    'isBlacklisted': false,
    'createdAt': DateTime(2026, 1, 1).millisecondsSinceEpoch,
  },
];

Future<void> _pumpUsers(
  WidgetTester tester, {
  Size size = const Size(390, 1800),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    ChangeNotifierProvider<UserProvider>(
      create: (_) => _Super(),
      child: MaterialApp(
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: AllUsersScreen(
          reads: AllUsersReads(allUsersRaw: () async => _sameName),
        ),
      ),
    ),
  );
  await tester.pump();
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

// ════════════════════════════════════════════════════════════════════════════
// P33-X2 — TO 한도
// ════════════════════════════════════════════════════════════════════════════

final _adminRows = <Map<String, dynamic>>[
  // 사업장 2개인데 한도는 3 — 두 수가 다르다.
  {
    'uid': 'a1',
    'name': '박사장',
    'businessName': '강남 물류센터',
    'managedBizCount': 2,
    'maxActiveTOs': 3,
  },
  {
    'uid': 'a2',
    'name': '최사장',
    'businessName': '성수 창고',
    'managedBizCount': 1,
  },
];

Future<void> _pumpLimit(
  WidgetTester tester, {
  bool failGlobal = false,
  Size size = const Size(390, 1800),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    ChangeNotifierProvider<UserProvider>(
      create: (_) => _Super(),
      child: MaterialApp(
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: TOLimitSettingsScreen(
          reads: ToLimitReads(
            globalConfigRaw: () async {
              if (failGlobal) throw Exception('unavailable');
              return {'maxActiveTOPerBusiness': 7};
            },
            businessAdminsRaw: () async => _adminRows,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  // ══ P33-D ═════════════════════════════════════════════════════════════════

  testWidgets('[ACX-1] 처음부터 계약 권한이 없어도 화면이 남아 이유와 담당자를 말한다',
      (tester) async {
    await _pushContract(tester, contract: false);

    // 예전에는 여기서 말없이 닫혔다.
    expect(find.text('계약 관리 열기'), findsNothing);
    expect(find.text('접근 권한이 없습니다'), findsOneWidget);
    expect(find.text('계약 관리 권한이 있는 관리자에게 문의하세요.'), findsOneWidget);
  });

  testWidgets('[ACX-2] 금지된 계약 내용은 한 줄도 열리지 않는다', (tester) async {
    await _pushContract(tester, contract: false);

    // 목록·검색 같은 본문 장치가 없다.
    expect(find.byType(TextField), findsNothing);
    expect(find.text('이름 또는 업무로 검색'), findsNothing);
    expect(find.text('근무자 이름으로 검색'), findsNothing);
  });

  testWidgets('[ACX-3] 권한이 있으면 본문이 열린다 (양성 대조)', (tester) async {
    await _pushContract(tester, contract: true);

    expect(find.text('접근 권한이 없습니다'), findsNothing);
    expect(find.text('권한을 확인하지 못했습니다'), findsNothing);
    expect(find.byType(TextField), findsWidgets); // 검색창이 살아 있다
  });

  testWidgets('[ACX-4] 이 사업장과 관계가 없는 진입은 여전히 닫힌다', (tester) async {
    await _pushContract(tester, contract: true, member: false);

    // 머물 이유가 없다 — 앞 화면으로 돌아온다.
    expect(find.text('계약 관리 열기'), findsOneWidget);
    expect(find.text('접근 권한이 없습니다'), findsNothing);
  });

  testWidgets('[ACX-5] 320dp × 2.0 — 거부 안내가 잘리지 않는다', (tester) async {
    await _pushContract(tester,
        contract: false, size: const Size(320, 2000), textScale: 2.0);

    expect(tester.takeException(), isNull);
    expect(find.text('접근 권한이 없습니다'), findsOneWidget);
    expect(find.text('계약 관리 권한이 있는 관리자에게 문의하세요.'), findsOneWidget);
  });

  // ══ P33-X1 ═══════════════════════════════════════════════════════════════

  testWidgets('[ACX-6] 블랙리스트 해제 확인창이 대상의 @아이디를 말한다', (tester) async {
    await _pumpUsers(tester);

    // 블랙리스트 상태인 쪽(minsu01)을 고른다.
    await tester.tap(find.text('김민수').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('@minsu01 · 지원자'), findsOneWidget);

    await tester.tap(find.text('블랙리스트 해제'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 상세 시트는 닫혔다 — 그런데도 대상이 그대로 보인다.
    expect(find.textContaining('@minsu01'), findsOneWidget);
    expect(find.textContaining('이 계정의 블랙리스트를 해제하시겠습니까?'),
        findsOneWidget);
    // 쓰기는 하지 않는다 — 확인창을 여는 데까지만.
  });

  testWidgets('[ACX-7] 다른 동명이인을 고르면 확인창의 @아이디도 달라진다', (tester) async {
    await _pumpUsers(tester);

    // 블랙리스트가 아닌 쪽(minsu77) — 등록 경로(사유 입력)로 간다.
    await tester.tap(find.text('김민수').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('@minsu77 · 지원자'), findsOneWidget);

    await tester.tap(find.text('블랙리스트 등록'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 사유 입력창에도 대상이 붙는다 — 제목만으로는 누구인지 알 수 없었다.
    expect(find.textContaining('@minsu77'), findsOneWidget);
    expect(find.textContaining('@minsu01'), findsNothing);
  });

  testWidgets('[ACX-8] 320dp × 2.0 — 확인창의 식별자가 잘리지 않는다', (tester) async {
    await _pumpUsers(tester,
        size: const Size(320, 2400), textScale: 2.0);

    await tester.tap(find.text('김민수').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('블랙리스트 해제'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.textContaining('@minsu01'), findsOneWidget);
  });

  // ══ P33-X2 ═══════════════════════════════════════════════════════════════

  testWidgets('[ACX-9] 전역 탭이 단위와 적용 시점을 말한다', (tester) async {
    await _pumpLimit(tester);

    expect(find.textContaining('한도는 한 관리자 계정이 동시에 진행 중인 공고 수입니다.'),
        findsOneWidget);
    expect(find.textContaining('사업장 수가 아닙니다'), findsOneWidget);
    expect(
        find.textContaining('새 공고를 등록할 때만 적용되고, 이미 등록된 공고는 닫히지 않습니다.'),
        findsOneWidget);
    // 기존 문구는 그대로 남는다.
    expect(find.textContaining('draft 상태로는 제한 없이 저장 가능합니다.'),
        findsOneWidget);
  });

  testWidgets('[ACX-10] 관리자별 탭도 사업장 수와 한도를 갈라 말한다', (tester) async {
    await _pumpLimit(tester);
    await tester.tap(find.text('관리자별 한도'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 두 수가 나란히 있는 바로 그 목록 앞에서 단위를 못박는다.
    expect(find.textContaining('한도는 동시에 진행 중인 공고 수입니다 — 사업장 수가 아닙니다.'),
        findsOneWidget);
    expect(find.text('2개 사업장 관리 중'), findsOneWidget);
    expect(find.text('개별 3개'), findsOneWidget);
    expect(find.text('전역 7개'), findsOneWidget);
  });

  testWidgets('[ACX-11] 전역값을 모르는 상태에서 가짜 기본값이 저장되지 않는다',
      (tester) async {
    await _pumpLimit(tester, failGlobal: true);

    // P3-2 에서 고친 상태가 그대로다 — 숫자를 말하지 않는다.
    expect(find.textContaining('현재 기본 한도:'), findsNothing);
    expect(find.textContaining('현재 기본 한도를 불러오지 못했습니다.'), findsOneWidget);

    // 입력칸은 비어 있고, 그 상태로 저장을 눌러도 값이 만들어지지 않는다.
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller?.text, '');
    await tester.tap(find.text('저장').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // 저장 경로는 `int.tryParse` 로 막힌다 — 자동으로 4가 들어가지 않는다.
    expect(field.controller?.text, '');
  });

  testWidgets('[ACX-12] 320dp × 2.0 — 단위 설명이 예외 없이 그려진다', (tester) async {
    await _pumpLimit(tester, size: const Size(320, 2800), textScale: 2.0);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('사업장 수가 아닙니다'), findsOneWidget);
    expect(find.text('현재 기본 한도: 7개'), findsOneWidget);
  });
}
