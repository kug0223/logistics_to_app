// [app_impl_9 · 인증 문구 2026-11-26] 가입·로그인 정리 목록(STATUS §7 · X0/X1 · BL285-01) — 문구·표시만.
//
//   AC-1  본인확인 수단 문구 — 시작 화면·본인확인 단계에 '휴대폰 본인확인' 0 · '간편인증으로 본인확인' · 320/2.0 넘침 0
//   AC-2  사유 없는 오류의 원인 계층 — not-found/unimplemented(기능 없음·업데이트 안내) · unavailable(연결) · resource-exhausted · 기타
//   AC-3  시작 화면 지난 안내 — 카카오 실패 안내가 아이디 로그인을 열 때 지워지고, 돌아와도 남지 않는다
//   AC-4  KG 실패 구분 — 창 자체 실패(failed/unavailable) ↔ 창 뒤 서버 결과 읽기 실패(PORTONE_UNAVAILABLE) ↔ 서버 설정 없음
//   캡처는 DU1_VQ_PHASE 가 있을 때만(→ records/work/auth-kakao-1/screens_5).
// ignore_for_file: depend_on_referenced_packages
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/auth/auth_start_screen.dart';
import 'package:ALfit/screens/auth/signup/signup_flow_controller.dart';
import 'package:ALfit/screens/auth/signup/signup_identity_step.dart';
import 'package:ALfit/services/auth/kakao_auth_service.dart';
import 'package:ALfit/services/auth/signup_api.dart';
import 'package:ALfit/services/pass_verification_service.dart';
import 'package:ALfit/theme/role_theme.dart';

import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart';

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

/// 카카오 로그인 대역 — 토큰을 주고, 서버 쪽은 [_Api] 가 정한다.
class _Gw implements LoginProviderGateway {
  @override
  LoginProviderKind get kind => LoginProviderKind.values.first;
  @override
  bool get isConfigured => true;
  @override
  Future<ProviderLoginResult> login() async => const ProviderLoginResult.success('kakao-token');
  @override
  Future<void> logout() async {}
  @override
  Future<void> unlink() async {}
}

/// 서버 대역 — callableAuthKakao 가 없을 때(not-found · 사유 없음)를 재현한다.
class _Api implements SignupApi {
  _Api({this.kakaoError, this.verifyError});
  final SignupApiException? kakaoError;
  final SignupApiException? verifyError;
  @override
  Future<AuthKakaoResult> authKakao({required String accessToken, String? role}) async {
    if (kakaoError != null) throw kakaoError!;
    throw StateError('부르지 않는다');
  }

  @override
  Future<String> prepareCertification(SignupSession s) async => 'req-1';
  @override
  Future<PassSignupVerification> verifyPass(SignupSession s, {required String impUid}) async {
    if (verifyError != null) throw verifyError!;
    throw StateError('부르지 않는다');
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw StateError('부르지 않는다: ${i.memberName}');
}

class _Up extends UserProvider {
  @override
  bool get isAdminMode => false;
}

SignupSession _consented() =>
    SignupSession.tryFrom({'sessionId': 's1', 'secret': 'x', 'state': 'consented', 'role': 'USER'})!;

final _cap = GlobalKey();

Future<void> _pumpStart(WidgetTester t, SignupApi api, {double width = 360, double scale = 1.0, double height = 800}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(RepaintBoundary(
    key: _cap,
    child: ChangeNotifierProvider<UserProvider>.value(
      value: _Up(),
      child: MaterialApp(
        theme: RoleTheme.workerTheme,
        debugShowCheckedModeBanner: false,
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: AuthStartScreen(gateway: _Gw(), api: api),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

Future<void> _shot(WidgetTester t, String id, Map<String, Object?> cond) async {
  await vqCapture(t, _cap, id, conditions: {...cond, 'kind': 'LOCAL widget render(모의 서버 · 실기기 아님)'});
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    SharedPreferences.setMockInitialValues({});
    if (vqEnabled) await vqLoadFonts();
  });

  group('AC-1 본인확인 수단 문구', () {
    for (final (w, sc) in const [(360.0, 1.0), (320.0, 2.0)]) {
      testWidgets('AC-1a 시작 화면 ${w.toInt()}/$sc — 휴대폰 본인확인 0 · 간편인증 · 넘침 0', (t) async {
        await _pumpStart(t, _Api(), width: w, scale: sc, height: sc > 1 ? 1400 : 800);
        expect(t.takeException(), isNull);
        expect(findVisibleTextContaining('휴대폰 본인확인'), findsNothing);
        expect(findVisibleText('카카오 계정으로 간편하게 시작해요. 처음 한 번만 간편인증으로 본인확인을 해요.'), findsOneWidget);
        expect(find.bySemanticsLabel('카카오 계정으로 간편하게 시작해요. 처음 한 번만 간편인증으로 본인확인을 해요.'), findsOneWidget);
        await _shot(t, 'AC1_start_${w.toInt()}x$sc', {'w': w, 'scale': sc});
      });
    }

    testWidgets('AC-1b 본인확인 단계 320/2.0 — 제목 본인확인 · 휴대폰 번호 확인 문구 0 · 넘침 0', (t) async {
      t.view.physicalSize = const Size(320, 1600);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final c = SignupFlowController(
          api: _Api(), session: _consented(), onToken: (tok, {required bool switchAccount}) async => null);
      await t.pumpWidget(RepaintBoundary(
        key: _cap,
        child: MaterialApp(
          theme: RoleTheme.workerTheme,
          debugShowCheckedModeBanner: false,
          builder: (ctx, child) => MediaQuery(
            data: MediaQuery.of(ctx).copyWith(textScaler: const TextScaler.linear(2.0)),
            child: child!,
          ),
          home: Scaffold(body: SingleChildScrollView(child: SignupIdentityStep(controller: c))),
        ),
      ));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(findVisibleText('본인확인'), findsOneWidget, reason: '단계 제목');
      expect(findVisibleTextContaining('휴대폰'), findsNothing, reason: '수단을 휴대폰으로 단정하지 않는다');
      expect(findVisibleText('간편인증으로 본인 명의를 확인해요. 확인한 정보로 계정을 만들어요.'), findsOneWidget);
      for (final bad in ['인증 완료', '검증 완료', '진위', '취업자격']) {
        expect(findVisibleTextContaining(bad), findsNothing, reason: bad);
      }
      await _shot(t, 'AC1_identity_step_320x2.0', {'w': 320, 'scale': 2.0});
    });
  });

  group('AC-2 사유 없는 오류의 원인 계층', () {
    test('AC-2a 코드별 안내', () {
      String m(String code) => SignupCopy.reasonMessage(null, code: code);
      const missing = '지금은 이 기능을 쓸 수 없어요. 잠시 후 다시 시도해 주세요. 계속되면 앱을 최신 버전으로 업데이트해 주세요.';
      expect(m('not-found'), missing);
      expect(m('unimplemented'), missing);
      expect(m('unavailable'), '연결이 원활하지 않아요. 네트워크를 확인하고 잠시 후 다시 시도해 주세요.');
      expect(m('deadline-exceeded'), m('unavailable'));
      expect(m('resource-exhausted'), '요청이 많아요. 잠시 후 다시 시도해 주세요.');
      expect(m('internal'), '처리하지 못했어요. 잠시 후 다시 시도해 주세요.');
      // 사유가 있으면 사유가 이긴다(서버가 not-found 로 보낸 세션 만료 등).
      expect(SignupCopy.reasonMessage('SESSION_EXPIRED', code: 'not-found'), '가입 진행 시간이 지났어요. 카카오로 다시 시작해 주세요.');
    });

    testWidgets('AC-2b 카카오 시작 — 서버 함수 없음(not-found) 안내가 시작 화면에 뜬다', (t) async {
      await _pumpStart(t, _Api(kakaoError: const SignupApiException(code: 'not-found')));
      await t.tap(findVisibleText('카카오로 시작하기'));
      await t.pumpAndSettle();
      expect(findVisibleText('지금은 이 기능을 쓸 수 없어요. 잠시 후 다시 시도해 주세요. 계속되면 앱을 최신 버전으로 업데이트해 주세요.'),
          findsOneWidget);
      expect(findVisibleText('처리하지 못했어요. 잠시 후 다시 시도해 주세요.'), findsNothing);
    });
  });

  group('AC-3 시작 화면 지난 안내', () {
    testWidgets('AC-3a 카카오 실패 안내 → 아이디 로그인 열기 → 돌아오기 → 안내 0', (t) async {
      await _pumpStart(t, _Api(kakaoError: const SignupApiException(code: 'unavailable')), height: 1000);
      await t.tap(findVisibleText('카카오로 시작하기'));
      await t.pumpAndSettle();
      const msg = '연결이 원활하지 않아요. 네트워크를 확인하고 잠시 후 다시 시도해 주세요.';
      expect(findVisibleText(msg), findsOneWidget);
      await t.tap(findVisibleText('아이디로 로그인'));
      await t.pumpAndSettle();
      // 아이디 로그인 화면에서 뒤로(그 화면의 '회원가입' 도 시작 화면으로 pop 한다)
      final nav = t.state<NavigatorState>(find.byType(Navigator).first);
      nav.pop();
      await t.pumpAndSettle();
      expect(find.byType(AuthStartScreen), findsOneWidget);
      expect(findVisibleText(msg), findsNothing, reason: '지난 안내가 남지 않는다');
    });
  });

  group('AC-4 KG 실패 구분', () {
    Future<SignupFlowController> run(PassLaunchOutcome launch, {SignupApiException? verifyError}) async {
      final c = SignupFlowController(
        api: _Api(verifyError: verifyError),
        session: _consented(),
        onToken: (tok, {required bool switchAccount}) async => null,
        kgLauncher: (id) async => launch,
      );
      await c.startIdentity();
      return c;
    }

    test('AC-4a 창 자체 실패 → 창 문제 안내', () async {
      for (final o in const [PassLaunchOutcome.failed('x'), PassLaunchOutcome.unavailable()]) {
        final c = await run(o);
        expect(c.kgPhase, KgPhase.failed);
        expect(c.message, '본인확인 창에서 문제가 생겼어요. 다시 시도해 주세요.');
      }
    });
    test('AC-4b 창은 끝났고 서버가 결과를 못 읽음(PORTONE_UNAVAILABLE) → 결과 받기 실패 안내', () async {
      final c = await run(const PassLaunchOutcome.returned('imp_1'),
          verifyError: const SignupApiException(code: 'unavailable', reason: 'PORTONE_UNAVAILABLE'));
      expect(c.kgPhase, KgPhase.failed);
      expect(c.message, '본인확인 결과를 받아 오지 못했어요. 잠시 후 본인확인을 다시 해 주세요.');
      expect(c.message, isNot(contains('창')));
    });
    test('AC-4c 서버 설정 없음(PORTONE_NOT_CONFIGURED) · CI 미수신(KG_CI_MISSING)', () async {
      final c = await run(const PassLaunchOutcome.returned('imp_2'),
          verifyError: const SignupApiException(code: 'internal', reason: 'PORTONE_NOT_CONFIGURED'));
      expect(c.message, '지금은 본인확인을 진행할 수 없어요. 잠시 후 다시 시도해 주세요.');
      final d = await run(const PassLaunchOutcome.returned('imp_3'),
          verifyError: const SignupApiException(code: 'failed-precondition', reason: 'KG_CI_MISSING'));
      expect(d.message, '고른 인증 방법으로는 본인확인 정보를 받지 못했어요. 다른 인증 방법으로 다시 시도해 주세요.');
      expect(d.message, isNot(contains('휴대폰')));
    });
  });
}
