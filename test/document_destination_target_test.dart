// [R7-P2-1 후속 H6-D] 보완 카드의 **목적지 본문**과 대상 일치.
//
//   홈 카드는 "{사업장}에서 {서류} 재등록을 요청했어요" 라고 말하고
//   `DocumentManagementScreen()` 을 **인자 없이** 푸시한다(요청 키·사업장·
//   서류 종류를 넘기지 않는다). 그래서 물어야 할 것은 하나다:
//   목적지가 그 요청의 대상을 다시 찾아 주는가.
//
//   기존 홈 하네스(`user_home_content_render_test.dart`)의 fake
//   `FirebaseOptions` 에는 `storageBucket` 이 없어서 목적지가 본문 빌드
//   전에 `[firebase_storage/no-bucket]` 으로 깨졌다 — 그래서 거기서는
//   route 푸시만 셀 수 있었다. 여기서는 버킷을 채워 **본문을 실제로
//   렌더**한다. 버킷 부재는 하네스 설정 문제이지 제품 결함이 아니다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/common/document_management_screen.dart';
import 'package:ALfit/services/payroll_correction_service.dart';

class _FakeApp extends Fake
    with MockPlatformInterfaceMixin
    implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(
        apiKey: 'k',
        appId: 'a',
        messagingSenderId: 's',
        projectId: 'p',
        // ← 홈 하네스와 다른 단 하나. 목적지는 `StorageService()` 를
        //   **필드로** 만들고 그 안에서 `FirebaseStorage.instance` 를
        //   잡으므로, 버킷이 없으면 본문 빌드 전에 깨진다.
        storageBucket: 'p.appspot.com',
      );
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

class _UserDouble extends UserProvider {
  _UserDouble({this.registered = false});

  /// 두 서류를 이미 올려 둔 계정인가. 재등록 요청은 **이 상태에서** 온다.
  final bool registered;

  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '김근로',
        email: 'u1@alfit.local',
        role: UserRole.USER,
        accountStatus: 'active',
        isIdVerified: registered,
        idCardImagePath: registered ? 'id_cards/u1/id.jpg' : null,
        bankName: registered ? '국민은행' : null,
        accountNumber: registered ? '123456789012' : null,
        accountHolder: registered ? '김근로' : null,
        bankbookImagePath: registered ? 'bankbooks/u1/bb.jpg' : null,
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

Future<void> _pumpDestination(
  WidgetTester tester, {
  bool registered = false,
  Size size = const Size(390, 3000),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ChangeNotifierProvider<UserProvider>.value(
      value: _UserDouble(registered: registered),
      child: MaterialApp(
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const DocumentManagementScreen(),
      ),
    ),
  );
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

List<String> _visibleTexts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data)
    .whereType<String>()
    .toList();

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    FirebasePlatform.instance = _FakeCore();
  });

  testWidgets('DDT-1 (H6-D) 버킷을 채우면 목적지 본문이 실제로 렌더된다',
      (tester) async {
    await _pumpDestination(tester);

    // 여기부터는 route 푸시가 아니라 **내용**을 본다.
    expect(find.text('내 서류 관리'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 카드가 말할 수 있는 두 서류축이 **둘 다** 이 화면에 있다.
    expect(find.text('신분증'), findsOneWidget);
    expect(find.text('급여 계좌'), findsOneWidget);
    expect(find.text('신분증 등록하기'), findsOneWidget);
    expect(find.text('급여정보 등록하기'), findsOneWidget);
  });

  testWidgets('DDT-2 (H6-D) 목적지는 보완 요청을 읽지 않는다 — 요청 문맥이 없다',
      (tester) async {
    await _pumpDestination(tester);

    // 홈 카드가 말한 문맥(사업장·요청·나머지 건수)이 목적지에는 **없다.**
    //   `DocumentManagementScreen()` 은 인자가 0개이고, 이 화면의 읽기는
    //   `_loadUserDocuments`(provider) + `_loadTaxIdentity` 뿐이다 —
    //   보완 요청 컬렉션을 읽지 않는다.
    expect(find.textContaining('재등록을 요청'), findsNothing);
    expect(find.textContaining('A 물류센터'), findsNothing);
    expect(find.textContaining('외 '), findsNothing);

    // 목적지도 "왜 필요한가"를 말하지만, 그것은 **이 화면의 상설 설명**이다
    //   ('근무 후 급여 지급을 위해 필요해요'). 특정 요청에서 온 문맥이 아니다 —
    //   요청이 있든 없든 같은 문장이 선다. 둘을 같은 것으로 세지 않는다.
    expect(find.text('근무 후 급여 지급을 위해 필요해요'), findsOneWidget);
  });

  testWidgets('DDT-3 (H6-D) 이미 올린 계정에도 다시 올릴 길이 있다 — 문맥만 없다',
      (tester) async {
    // 재등록 요청은 **이미 올린 서류를 다시 올려 달라**는 것이다.
    //   그 상태에서 목적지가 무엇을 말하는지가 대상 일치의 핵심이다.
    await _pumpDestination(tester, registered: true);
    expect(tester.takeException(), isNull);

    final texts = _visibleTexts(tester);

    // 상태 어휘는 **'제출 완료'** 다 — 심사 통과가 아니라 제출 사실을 말한다
    //   (승인/검증 표현을 쓰지 않는 정책과 일치한다).
    expect(find.text('제출 완료'), findsNWidgets(2)); // 신분증 · 급여 계좌
    expect(find.text('미등록'), findsNothing);

    // 행동은 도달 가능하다 — 두 축 모두 다시 올릴 버튼이 상설로 있다.
    expect(find.text('다시 등록하기'), findsOneWidget); // 신분증
    expect(find.text('계좌 변경하기'), findsOneWidget); // 급여 계좌

    // ── 관찰(이번에 고치지 않음): 빠진 것은 **행동**이 아니라 **문맥**이다.
    //    '다시 등록하기' 는 요청이 있든 없든 똑같이 서 있는 상설 버튼이라,
    //    "어느 사업장이 무엇을 왜 다시 요청했는지" 는 홈 카드에만 있다.
    //    카드를 지나치면(또는 그 조회가 실패하면) 되돌아볼 곳이 없다.
    //    owner 는 이 화면이고, 이번 diff 범위(H6-E 실패 표면)가 아니다.
    expect(texts.where((t) => t.contains('요청')), isEmpty);
  });

  testWidgets('DDT-4 (H6-D) 320dp × 2.0 에서도 두 서류축 본문이 선다',
      (tester) async {
    await _pumpDestination(tester,
        size: const Size(320, 4000), textScale: 2.0);

    expect(tester.takeException(), isNull);
    expect(find.text('신분증'), findsOneWidget);
    expect(find.text('급여 계좌'), findsOneWidget);
  });

  test('DDT-5 (H6-D) 두 사업장의 보완 요청 두 건이 동시에 열릴 수 있다', () {
    // CF `callableGetMyDocumentCorrections` 는 workerUid + status=OPEN 만
    //   걸고 businessId 로 좁히지 않는다(limit 20, bizIds 를 Set 으로 모은다).
    //   즉 A·B 두 사업장이 각각 열어 둘 수 있다.
    final surface = DocumentCorrectionSurface.loaded([
      const DocumentCorrectionTask(
        requestId: 'a1',
        businessId: 'bizA',
        businessName: 'A 물류센터',
        documentType: 'ID_CARD',
        sourceDomain: 'APPLICATION',
      ),
      const DocumentCorrectionTask(
        requestId: 'b1',
        businessId: 'bizB',
        businessName: 'B 마트',
        documentType: 'BANKBOOK',
        sourceDomain: 'PAYROLL',
        payrollReadinessState: 'BANKBOOK_MISSING',
      ),
    ]);

    // 카드가 고르는 하나는 **지급(PAYROLL) 쪽**이다 — 돈이 걸린 것 먼저.
    expect(surface.primary!.requestId, 'b1');
    expect(surface.primary!.documentType, 'BANKBOOK');
    expect(surface.tasks.length - 1, 1); // 카드 문구의 '외 1건'

    // ── 대상 일치 판정:
    //    A 카드를 눌러 B 의 기본값이 열리는 위험은 **구조적으로 없다.**
    //    목적지는 계정 스코프 화면 하나이고(인자 0개), 신분증·통장사본을
    //    둘 다 담으며(DDT-1), 두 서류는 계정당 1개다. 사업장이 달라도
    //    고쳐야 할 파일은 같은 한 개다.
    //    남는 결손은 강조·목록이다: '외 1건' 의 나머지가 무엇인지 목적지에서
    //    확인할 수 없고(DDT-2), 재등록 요청 상태도 구별되지 않는다(DDT-3).
    expect(surface.tasks.first.documentType, 'ID_CARD');
    expect(surface.tasks.map((t) => t.businessId).toSet().length, 2);
  });
}
