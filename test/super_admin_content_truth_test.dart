// [R7-P3-2 P32-X1 / P32-X2] 슈퍼관리자 두 화면의 **내용**을 실제로 렌더한다.
//
// 지금까지 이 두 화면은 소스 원문만 읽은 CODE only 였다. 여기서는 production
// 위젯을 SUPER_ADMIN 조건으로 세우고, 표본 값을 넣어 본문이 무엇을 말하는지 잰다.
// 쓰기(블랙리스트·제재 해제·한도 저장)는 **한 번도 호출하지 않는다.**
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
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

// ── 표본 ────────────────────────────────────────────────────────────────────
// 이름이 **같고** 아이디가 다른 두 계정 + 사업장명이 있는 관리자 / 없는 지원자.
Map<String, dynamic> _row({
  required String uid,
  required String username,
  required String name,
  required String role,
  String? businessName,
}) =>
    {
      'uid': uid,
      'username': username,
      'name': name,
      'email': '$username@alfit.local',
      'role': role,
      if (businessName != null) 'businessName': businessName,
      'createdAt': DateTime(2026, 1, 1).millisecondsSinceEpoch,
    };

final _sameNamePair = [
  _row(uid: 'u1', username: 'minsu01', name: '김민수', role: 'USER'),
  _row(uid: 'u2', username: 'minsu77', name: '김민수', role: 'USER'),
  _row(
      uid: 'b1',
      username: 'bizminsu',
      name: '김민수',
      role: 'BUSINESS_ADMIN',
      businessName: '강남 물류센터'),
];

Future<void> _pumpUsers(
  WidgetTester tester, {
  required AllUsersReads reads,
  Size size = const Size(390, 1600),
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
        home: AllUsersScreen(reads: reads),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _pumpLimit(
  WidgetTester tester, {
  required ToLimitReads reads,
  Size size = const Size(390, 1600),
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
        home: TOLimitSettingsScreen(reads: reads),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  // ══ P32-X1 — 문의 대상 식별 ═══════════════════════════════════════════════

  testWidgets('[SAU-1] 목록에서는 동명이인이 갈리지 않는다 — @아이디가 없다',
      (tester) async {
    await _pumpUsers(tester,
        reads: AllUsersReads(allUsersRaw: () async => _sameNamePair));

    // 같은 이름이 세 번.
    expect(find.text('김민수'), findsNWidgets(3));

    // 목록 카드가 보여주는 것은 이름 · 역할 배지 · (있으면)연락처 · 근무일수뿐이다.
    // **`@아이디` 는 목록에 없다.** 연락처가 없는 표본이면 지원자 둘은
    // 화면상 완전히 같아 보인다 — 이름만으로 문의 대상을 고를 수 없다.
    expect(find.textContaining('@minsu'), findsNothing);
    expect(find.text('지원자'), findsNWidgets(2)); // 역할 배지도 둘이 같다
    expect(find.text('사업장관리자'), findsOneWidget);
  });

  testWidgets('[SAU-2] 카드를 열어야 @아이디가 나온다 — 사업체명은 관리자에게만',
      (tester) async {
    await _pumpUsers(tester,
        reads: AllUsersReads(allUsersRaw: () async => _sameNamePair));

    // 첫 번째 김민수(지원자) 카드를 실제로 탭한다.
    await tester.tap(find.text('김민수').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 상세 시트에서 비로소 식별자가 보인다.
    expect(find.text('@minsu01 · 지원자'), findsOneWidget);

    // 지원자에게는 `businessName` 자체가 없으므로 사업체명 행이 없다.
    expect(find.text('사업체명'), findsNothing);
    expect(find.text('강남 물류센터'), findsNothing);
  });

  testWidgets('[SAU-2b] 관리자 카드를 열면 사업체명이 문맥으로 붙는다 (양성 대조)',
      (tester) async {
    await _pumpUsers(tester,
        reads: AllUsersReads(allUsersRaw: () async => _sameNamePair));

    await tester.tap(find.text('김민수').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('@bizminsu · 사업장관리자'), findsOneWidget);
    expect(find.text('사업체명'), findsOneWidget);
    expect(find.text('강남 물류센터'), findsOneWidget);
  });

  testWidgets('[SAU-3] 조회 실패를 "대상 없음"이라고 말하지 않는다', (tester) async {
    await _pumpUsers(tester,
        reads: AllUsersReads(
            allUsersRaw: () async => throw Exception('unavailable')));

    expect(find.text('사용자 목록을 불러오지 못했습니다'), findsOneWidget);
    expect(find.text('해당하는 사용자가 없다는 뜻이 아닙니다.'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
    // 이 문구가 남아 있으면 문의 대상이 없다고 단정한 것이다.
    expect(find.text('해당하는 사용자가 없습니다'), findsNothing);
  });

  testWidgets('[SAU-4] 정말 비었을 때는 여전히 "없습니다" 라고 말한다 (양성 대조)',
      (tester) async {
    await _pumpUsers(tester,
        reads: AllUsersReads(allUsersRaw: () async => const []));

    expect(find.text('해당하는 사용자가 없습니다'), findsOneWidget);
    expect(find.text('사용자 목록을 불러오지 못했습니다'), findsNothing);
  });

  testWidgets('[SAU-5] 320dp × 2.0 — 이름·식별자가 예외 없이 그려진다', (tester) async {
    await _pumpUsers(tester,
        reads: AllUsersReads(allUsersRaw: () async => _sameNamePair),
        size: const Size(320, 2400),
        textScale: 2.0);

    expect(tester.takeException(), isNull);
    expect(find.text('김민수'), findsNWidgets(3));
    expect(find.textContaining('@minsu'), findsNothing);
  });

  // ══ P32-X2 — TO 한도의 의미 ════════════════════════════════════════════════

  // 사업장 **2개**를 가진 오너 + 개별 한도 3 — 사업장 수와 한도를 섞을 수 없게 한다.
  final adminRows = <Map<String, dynamic>>[
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
      // maxActiveTOs 없음 → 전역값을 쓴다
    },
  ];

  ToLimitReads _okLimit() => ToLimitReads(
        globalConfigRaw: () async => {'maxActiveTOPerBusiness': 7},
        businessAdminsRaw: () async => adminRows,
      );

  testWidgets('[TOL-1] 전역/개별 구분과 draft 예외를 본문이 말한다', (tester) async {
    await _pumpLimit(tester, reads: _okLimit());

    expect(find.text('현재 기본 한도: 7개'), findsOneWidget);
    expect(
        find.textContaining('관리자별 개별 한도가 설정되지 않은 경우 이 값이 적용됩니다.'),
        findsOneWidget);
    expect(find.textContaining('draft 상태로는 제한 없이 저장 가능합니다.'),
        findsOneWidget);
  });

  testWidgets('[TOL-2] 사업장 수와 한도가 각각 다른 수로 나란히 뜬다', (tester) async {
    await _pumpLimit(tester, reads: _okLimit());
    await tester.tap(find.text('관리자별 한도'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 개별 한도가 있는 관리자: 사업장 2개인데 한도는 3개다 — 다른 수다.
    expect(find.text('2개 사업장 관리 중'), findsOneWidget);
    expect(find.text('개별 3개'), findsOneWidget);

    // 개별 한도가 없는 관리자: 사업장이 1개면 그 줄 자체가 없고(>1 조건),
    // 한도는 전역값을 쓴다고만 말한다.
    expect(find.text('1개 사업장 관리 중'), findsNothing);
    expect(find.text('전역 7개'), findsOneWidget);

    // 화면 어디에도 **현재 활성 공고 수**는 없다 — 남은 여유를 알 수 없다.
    // (자료가 reader 에 없다. 새 집계를 이 단계에서 만들지 않는다.)
  });

  testWidgets('[TOL-3] 전역값 조회 실패를 확정 숫자로 말하지 않는다', (tester) async {
    await _pumpLimit(tester,
        reads: ToLimitReads(
          globalConfigRaw: () async => throw Exception('unavailable'),
          businessAdminsRaw: () async => adminRows,
        ));

    // 예전에는 실패해도 `현재 기본 한도: 4개` 가 남고 입력칸에 4 가 채워졌다.
    expect(find.textContaining('현재 기본 한도:'), findsNothing);
    expect(find.textContaining('현재 기본 한도를 불러오지 못했습니다.'), findsOneWidget);
    expect(find.textContaining('지금 값을 저장하면 실제 설정을 덮어씁니다.'),
        findsOneWidget);

    // 입력칸이 추측값으로 미리 채워져 있지 않다.
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller?.text, '');
  });

  testWidgets('[TOL-4] 관리자 목록 조회 실패를 "관리자 없음"이라고 말하지 않는다',
      (tester) async {
    await _pumpLimit(tester,
        reads: ToLimitReads(
          globalConfigRaw: () async => {'maxActiveTOPerBusiness': 7},
          businessAdminsRaw: () async => throw Exception('unavailable'),
        ));
    await tester.tap(find.text('관리자별 한도'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('관리자 목록을 불러오지 못했습니다'), findsOneWidget);
    expect(find.text('등록된 관리자가 없다는 뜻이 아닙니다.'), findsOneWidget);
    expect(find.text('등록된 사업장 관리자가 없습니다'), findsNothing);
  });

  testWidgets('[TOL-5] 정말 비었을 때는 여전히 "없습니다" 라고 말한다 (양성 대조)',
      (tester) async {
    await _pumpLimit(tester,
        reads: ToLimitReads(
          globalConfigRaw: () async => {'maxActiveTOPerBusiness': 7},
          businessAdminsRaw: () async => const [],
        ));
    await tester.tap(find.text('관리자별 한도'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('등록된 사업장 관리자가 없습니다'), findsOneWidget);
    expect(find.text('관리자 목록을 불러오지 못했습니다'), findsNothing);
  });

  testWidgets('[TOL-6] 320dp × 2.0 — 한도 수치와 저장 행동이 예외 없이 그려진다',
      (tester) async {
    await _pumpLimit(tester,
        reads: _okLimit(),
        size: const Size(320, 2600),
        textScale: 2.0);

    expect(tester.takeException(), isNull);
    expect(find.text('현재 기본 한도: 7개'), findsOneWidget);
    expect(find.text('저장'), findsWidgets);
  });
}
