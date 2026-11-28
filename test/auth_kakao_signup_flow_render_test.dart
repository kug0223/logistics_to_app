// [ALFIT-AUTH-KAKAO-ONBOARDING.1 · 구현1 · 앱] 시작 · 가입 마법사 · 두 역할 · 서류 입구 렌더 시험(모의 서버 응답).
//
//   AKR-START  시작 화면: 카카오 주 행동 · 아이디 로그인 보조 · 키 없음 = '준비 중'(누를 수 없음)
//   AKR-ENTRY  카카오 결과 갈래: 가입 필요 → 마법사 / 두 역할 → 시트 → 고른 역할로 다시 묻기 / 취소 → 조용히 / 실패 → 안내
//   AKR-FLOW   목적 → 동의 → 본인확인(취소 · 실패 · 서버 확인 중 · 마침 구분) → 완료(로그인)
//   AKR-RESUME 서버 세션 상태로 재개(cert_issued → 본인확인 · committed → 완료 · 토큰 재시도 같은 UID)
//   AKR-EXIST  같은 CI·역할(IDENTITY_ROLE_TAKEN) → 이미 가입 안내(연결 0 · 로그인 0)
//   AKR-DOC    국적 미확정 서류 입구 시트 · 외국인등록증 정보 화면(번호 저장/표시 0)
//   AKR-WIDE   320dp · 글자 2.0 에서 넘침 0
//   실제 카카오 SDK · KG 창 · 서버 = PENDING VERIFICATION. 캡처는 DU1_VQ_PHASE 가 있을 때만 쓴다.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/legal_terms_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/auth/auth_start_screen.dart';
import 'package:ALfit/screens/auth/signup/signup_flow_controller.dart';
import 'package:ALfit/screens/auth/signup/signup_flow_screen.dart';
import 'package:ALfit/screens/common/foreign_id_document_screen.dart';
import 'package:ALfit/services/auth/kakao_auth_service.dart';
import 'package:ALfit/services/auth/signup_api.dart';
import 'package:ALfit/services/pass_verification_service.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/widgets/auth/provider_account_card.dart';
import 'package:ALfit/widgets/auth/role_login_choice_sheet.dart';
import 'package:ALfit/widgets/common/id_document_kind_sheet.dart';

import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart';

class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options =>
      const FirebaseOptions(apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

/// 로그인 결과만 흉내 내는 provider — Firebase 호출 0.
class _P extends UserProvider {
  _P();
  bool signInOk = true;
  final List<String> tokens = [];
  String? _err;
  @override
  String? get error => _err;
  @override
  void clearError() {
    _err = null;
    notifyListeners();
  }

  void setError(String e) {
    _err = e;
    notifyListeners();
  }

  @override
  bool get needsDeletionRecovery => false;
  @override
  Future<bool> signInWithCustomToken(String customToken) async {
    tokens.add(customToken);
    if (!signInOk) _err = '로그인하지 못했어요.';
    return signInOk;
  }
}

class _Gateway implements LoginProviderGateway {
  _Gateway({this.configured = true});
  final bool configured;
  ProviderLoginResult result = const ProviderLoginResult.success('kakao-at');
  int calls = 0;
  @override
  LoginProviderKind get kind => LoginProviderKind.kakao;
  @override
  bool get isConfigured => configured;
  @override
  Future<ProviderLoginResult> login() async {
    calls++;
    return result;
  }

  @override
  Future<void> logout() async {}
  @override
  Future<void> unlink() async {}
}

SignupSession _sess(String state, {String? role, String purpose = 'signup'}) => SignupSession.tryFrom(
    {'sessionId': 'kakao_app_1', 'secret': 'sec', 'state': state, 'role': role, 'purpose': purpose})!;

class _Api implements SignupApi {
  final List<String> log = [];
  List<AuthKakaoResult Function(String? role)> authQueue = [];
  Completer<PassSignupVerification>? verifyGate;
  Object? verifyError;
  Object? completeError;
  CompleteSignupResult completeResult =
      const CompleteSignupResult(uid: 'newUid', role: 'USER', customToken: 'ct-new');
  Object? finalizeError;
  CompleteSignupResult finalizeResult =
      const CompleteSignupResult(uid: 'newUid', role: 'USER', customToken: 'ct-final');

  @override
  Future<AuthKakaoResult> authKakao({required String accessToken, String? role}) async {
    log.add('authKakao:$accessToken:${role ?? '-'}');
    return authQueue.removeAt(0)(role);
  }

  @override
  Future<SignupSession> getSession(SignupSession s) async => s;
  @override
  Future<SignupSession> startAddRole({required String role}) async {
    log.add('startAddRole:$role');
    return _sess('started', role: role, purpose: 'add_role');
  }

  @override
  Future<SignupSession> setPurpose(SignupSession s, {required String role}) async {
    log.add('setPurpose:$role');
    return _sess('purpose_selected', role: role, purpose: s.purpose);
  }

  @override
  Future<SignupSession> recordConsent(SignupSession s, Map<String, dynamic> consentRecord) async {
    log.add('consent:${consentRecord.keys.join(',')}');
    return _sess('consented', role: s.role, purpose: s.purpose);
  }

  @override
  Future<String> prepareCertification(SignupSession s) async {
    log.add('prepare');
    return 'alfit_cert_server_1';
  }

  @override
  Future<PassSignupVerification> verifyPass(SignupSession s, {required String impUid}) async {
    log.add('verify:$impUid');
    if (verifyError != null) throw verifyError!;
    if (verifyGate != null) return verifyGate!.future;
    return const PassSignupVerification(name: '김알핏', birthDate: '19900304', phoneMasked: '010-****-1234');
  }

  @override
  Future<CompleteSignupResult> completeSignup(SignupSession s) async {
    log.add('complete');
    if (completeError != null) throw completeError!;
    return completeResult;
  }

  @override
  Future<CompleteSignupResult> finalizeAuth(SignupSession s) async {
    log.add('finalize');
    if (finalizeError != null) throw finalizeError!;
    return finalizeResult;
  }

  @override
  Future<void> cancel(SignupSession s) async => log.add('cancel');
}

EffectiveLegalTerms _terms() => EffectiveLegalTerms(
      items: const [
        LegalTermsItem(id: 'service', title: '서비스 이용약관', content: '본문', isRequired: true, order: 0, version: '3'),
        LegalTermsItem(id: 'privacy', title: '개인정보 수집 · 이용 동의', content: '본문', isRequired: true, order: 1, version: '2'),
        LegalTermsItem(id: 'marketing', title: '혜택 알림 받기', content: '본문', isRequired: false, order: 2, version: '1'),
      ],
      upcoming: const [],
      serverNow: DateTime(2026, 11, 25),
    );

final _cap = GlobalKey();

Future<void> _pump(WidgetTester t, Widget child,
    {UserProvider? provider, Size size = const Size(392, 820), double scale = 1.0}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
    value: provider ?? _P(),
    child: RepaintBoundary(
      key: _cap,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: RoleTheme.workerTheme,
        builder: (ctx, w) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)),
          child: w!,
        ),
        home: child,
      ),
    ),
  ));
  await t.pumpAndSettle();
}

/// '약관 전체 동의' → 동의 안 한 항목 본문이 차례로 열린다 → 각각 '동의하고 닫기'(짧은 본문은 바로 활성).
Future<void> _agreeAll(WidgetTester t, {Set<String> refuse = const {}}) async {
  await t.tap(findVisibleText('약관 전체 동의'));
  await t.pumpAndSettle();
  for (var i = 0; i < 3; i++) {
    if (findVisibleText('동의하고 닫기').evaluate().isEmpty) break;
    final title = t.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? '').firstWhere(
        (d) => refuse.any((r) => visibleText(d).contains(r)), orElse: () => '');
    if (title.isNotEmpty) {
      await t.tap(findVisibleText('동의하지 않고 닫기'));
    } else {
      await t.tap(findVisibleText('동의하고 닫기'));
    }
    await t.pumpAndSettle();
  }
}

Future<void> _shot(WidgetTester t, String id) async {
  await t.pump(const Duration(milliseconds: 400));
  await vqCapture(t, _cap, id, conditions: {'w': 392, 'scale': 1.0, 'kind': 'LOCAL widget render (모의 응답)'});
}

Widget _flow(_Api api, SignupSession s,
        {KgLauncher? kg, SignupTokenSink? sink, List<String>? sinkLog}) =>
    SignupFlowScreen(
      session: s,
      api: api,
      termsLoader: () async => _terms(),
      kgLauncher: kg ?? (id) async => PassLaunchOutcome.returned('imp_$id'),
      tokenSink: sink ??
          (token, {required bool switchAccount}) async {
            sinkLog?.add('$token:$switchAccount');
            return null;
          },
    );

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    if (vqEnabled) await vqLoadFonts();
  });

  group('AKR-START', () {
    testWidgets('AKR-START-1 카카오 주 행동 · 아이디 로그인 보조 · 옛 회원가입 0', (t) async {
      await _pump(t, AuthStartScreen(gateway: _Gateway(), api: _Api()));
      expect(findVisibleText('카카오로 시작하기'), findsOneWidget);
      expect(findVisibleText('아이디로 로그인'), findsOneWidget);
      expect(findVisibleText('회원가입'), findsNothing);
      await _shot(t, 'S01_start');
    });
    testWidgets('AKR-START-2 키 없음 → 준비 중(눌러도 아무 일 없음) · 아이디 로그인 안내', (t) async {
      final gw = _Gateway(configured: false);
      await _pump(t, AuthStartScreen(gateway: gw, api: _Api()));
      expect(findVisibleText(KakaoLoginButtonLabels.notConfigured), findsOneWidget);
      await t.tap(findVisibleText(KakaoLoginButtonLabels.notConfigured));
      await t.pumpAndSettle();
      expect(gw.calls, 0);
      expect(findVisibleText('지금은 기존 아이디 계정으로만 로그인할 수 있어요.'), findsOneWidget);
      await _shot(t, 'S02_start_not_configured');
    });
    testWidgets('AKR-START-3 자동 복원에서 정리된 사유를 시작 화면이 말한다(K7)', (t) async {
      final p = _P()..setError('계정 이용 차단 상태라 해제 전까지 로그인할 수 없어요.\n사유: 반복 노쇼\n고객센터에 문의해주세요.');
      await _pump(t, AuthStartScreen(gateway: _Gateway(), api: _Api()), provider: p);
      expect(findVisibleTextContaining('계정 이용 차단'), findsOneWidget);
    });
  });

  group('AKR-ENTRY', () {
    testWidgets('AKR-ENTRY-1 연결 계정 TOKEN → custom token 로그인', (t) async {
      final api = _Api()
        ..authQueue = [(_) => const AuthKakaoToken(uid: 'u1', role: 'USER', customToken: 'ct1')];
      final p = _P();
      await _pump(t, AuthStartScreen(gateway: _Gateway(), api: api), provider: p);
      await t.tap(findVisibleText('카카오로 시작하기'));
      await t.pumpAndSettle();
      expect(api.log, ['authKakao:kakao-at:-']);
      expect(p.tokens, ['ct1']);
    });
    testWidgets('AKR-ENTRY-2 두 역할 → 시트 → 고른 역할로 같은 토큰 재질의 → 로그인', (t) async {
      final api = _Api()
        ..authQueue = [
          (_) => const AuthKakaoRoleSelection(['USER', 'BUSINESS_ADMIN']),
          (role) => AuthKakaoToken(uid: 'u-$role', role: role, customToken: 'ct-$role'),
        ];
      final p = _P();
      await _pump(t, AuthStartScreen(gateway: _Gateway(), api: api), provider: p);
      await t.tap(findVisibleText('카카오로 시작하기'));
      await t.pump(); await t.pump(const Duration(milliseconds: 600));
      expect(find.byType(RoleLoginChoiceSheet), findsOneWidget);
      await _shot(t, 'S03_role_choice_sheet');
      await t.tap(findVisibleText('사업주로 들어가기'));
      await t.pumpAndSettle();
      expect(api.log, ['authKakao:kakao-at:-', 'authKakao:kakao-at:BUSINESS_ADMIN']);
      expect(p.tokens, ['ct-BUSINESS_ADMIN']);
    });
    testWidgets('AKR-ENTRY-3 시트를 닫으면 로그인 0', (t) async {
      final api = _Api()..authQueue = [(_) => const AuthKakaoRoleSelection(['USER', 'BUSINESS_ADMIN'])];
      final p = _P();
      await _pump(t, AuthStartScreen(gateway: _Gateway(), api: api), provider: p);
      await t.tap(findVisibleText('카카오로 시작하기'));
      await t.pump(); await t.pump(const Duration(milliseconds: 600));
      await t.tapAt(const Offset(10, 10));
      await t.pump(); await t.pump(const Duration(milliseconds: 600));
      expect(p.tokens, isEmpty);
    });
    testWidgets('AKR-ENTRY-4 가입 필요 → 마법사(서버 세션 상태로) · 취소 → 조용히 · 실패 → 안내', (t) async {
      final api = _Api()..authQueue = [(_) => AuthKakaoSignupRequired(_sess('started'))];
      SignupSession? opened;
      final gw = _Gateway();
      await _pump(
          t,
          AuthStartScreen(
            gateway: gw,
            api: api,
            signupScreenBuilder: (s, a) {
              opened = s;
              return const Scaffold(body: Text('WIZARD'));
            },
          ));
      await t.tap(findVisibleText('카카오로 시작하기'));
      await t.pumpAndSettle();
      expect(findVisibleText('WIZARD'), findsOneWidget);
      expect(opened!.state, SignupSessionState.started);
      t.state<NavigatorState>(find.byType(Navigator)).pop();
      await t.pumpAndSettle();
      gw.result = const ProviderLoginResult.canceled();
      await t.tap(findVisibleText('카카오로 시작하기'));
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.info_outline), findsNothing);
      gw.result = const ProviderLoginResult.success('kakao-at');
      api.authQueue = [
        (_) => throw const SignupApiException(code: 'permission-denied', reason: 'KAKAO_APP_MISMATCH')
      ];
      await t.tap(findVisibleText('카카오로 시작하기'));
      await t.pumpAndSettle();
      expect(findVisibleText(SignupCopy.reasonMessage('KAKAO_APP_MISMATCH')), findsOneWidget);
    });
  });

  group('AKR-FLOW', () {
    testWidgets('AKR-FLOW-1 목적 → 동의 → 본인확인(마침) → 완료 · 토큰 1회 · 서버 requestId 로 KG', (t) async {
      final api = _Api();
      final sink = <String>[];
      final kgIds = <String>[];
      await _pump(
          t,
          _flow(api, _sess('started'), sinkLog: sink, kg: (id) async {
            kgIds.add(id);
            return PassLaunchOutcome.returned('imp_1');
          }));
      expect(findVisibleText('알핏을 어떻게 쓰실 건가요?'), findsOneWidget);
      expect(findVisibleText('일할게요'), findsOneWidget);
      expect(findVisibleText('사람을 구할게요'), findsOneWidget);
      await t.tap(findVisibleText('일할게요'));
      await t.pumpAndSettle();
      await _shot(t, 'S04_purpose');
      await t.tap(findVisibleText('다음'));
      await t.pumpAndSettle();
      expect(findVisibleText('서비스 이용 약관에 동의해 주세요'), findsOneWidget);
      // 필수 미동의면 다음 버튼 비활성
      final btn = find.ancestor(of: findVisibleText('동의하고 계속'), matching: find.byType(ElevatedButton));
      expect(t.widget<ElevatedButton>(btn).onPressed, isNull);
      await _agreeAll(t);
      await _shot(t, 'S05_consent');
      await t.tap(btn);
      await t.pumpAndSettle();
      // [app_impl_9 · 인증 문구 2026-11-26] 단계 제목 '휴대폰 본인확인' → '본인확인'(KG 통합 간편인증 · BL285-01).
      expect(findVisibleText('본인확인'), findsWidgets);
      expect(findVisibleTextContaining('휴대폰 본인확인'), findsNothing);
      await _shot(t, 'S06_identity_idle');
      await t.tap(findVisibleText('간편인증으로 본인확인 하기'));
      await t.pumpAndSettle();
      expect(kgIds, ['alfit_cert_server_1']);
      expect(findVisibleText('본인확인을 마쳤어요'), findsOneWidget);
      expect(findVisibleText('김알핏'), findsOneWidget);
      await _shot(t, 'S10_identity_verified');
      await t.tap(findVisibleText('가입 마치기'));
      await t.pumpAndSettle();
      expect(findVisibleText('가입을 마쳤어요'), findsOneWidget);
      // [대표 결정 2026-11-25] 완료 화면에 '시작 준비' 목록이 없다 — 준비 안내는 홈 카드가 한다.
      expect(findVisibleText('시작 준비'), findsNothing);
      expect(findVisibleText('신분증 또는 외국인등록증 등록'), findsNothing);
      expect(findVisibleText('홈으로 이동하고 있어요.'), findsOneWidget);
      await _shot(t, 'S12_complete_user');
      expect(api.log, [
        'setPurpose:USER',
        'consent:service,privacy,marketing',
        'prepare',
        'verify:imp_1',
        'complete',
      ]);
      expect(sink, ['ct-new:false']);
    });

    testWidgets('AKR-FLOW-1b 전체 동의 = 본문 열람 뒤 동의(거절한 선택 항목은 체크 안 됨 · 필수 충족이면 진행)', (t) async {
      final api = _Api();
      await _pump(t, _flow(api, _sess('purpose_selected', role: 'USER')));
      await _agreeAll(t, refuse: {'혜택 알림 받기'});
      expect(findVisibleText('서비스 이용 약관에 동의해 주세요'), findsOneWidget);
      await t.tap(findVisibleText('동의하고 계속'));
      await t.pumpAndSettle();
      expect(api.log.single, 'consent:service,privacy,marketing');
      expect(findVisibleText('간편인증으로 본인확인 하기'), findsOneWidget);
    });

    testWidgets('AKR-FLOW-2 KG 취소(중립) · 실패(주의) · 서버 확인 중(진행) 구분', (t) async {
      final api = _Api();
      var mode = 'cancel';
      await _pump(
          t,
          _flow(api, _sess('consented', role: 'USER'), kg: (id) async {
            if (mode == 'cancel') return const PassLaunchOutcome.canceled();
            if (mode == 'fail') return const PassLaunchOutcome.failed('x');
            return const PassLaunchOutcome.returned('imp_9');
          }));
      await t.tap(findVisibleText('간편인증으로 본인확인 하기'));
      await t.pumpAndSettle();
      expect(findVisibleText('본인확인을 취소했어요'), findsOneWidget);
      expect(findVisibleText('본인확인 다시 하기'), findsOneWidget);
      expect(api.log.where((e) => e.startsWith('verify')), isEmpty);
      await _shot(t, 'S07_identity_canceled');

      mode = 'fail';
      await t.tap(findVisibleText('본인확인 다시 하기'));
      await t.pumpAndSettle();
      expect(findVisibleText('본인확인을 마치지 못했어요'), findsOneWidget);
      await _shot(t, 'S08_identity_failed');

      mode = 'ok';
      api.verifyGate = Completer();
      await t.tap(findVisibleText('본인확인 다시 하기'));
      await t.pump();
      await t.pump();
      expect(findVisibleText('확인 결과를 받고 있어요'), findsOneWidget);
      expect(findVisibleText('본인확인을 마쳤어요'), findsNothing);
      expect(t.widget<ElevatedButton>(find.byType(ElevatedButton).last).onPressed, isNull);
      await vqCapture(t, _cap, 'S09_identity_verifying', conditions: {'w': 392, 'scale': 1.0});
      api.verifyGate!.complete(const PassSignupVerification(name: '김알핏'));
      await t.pumpAndSettle();
      expect(findVisibleText('본인확인을 마쳤어요'), findsOneWidget);
    });

    testWidgets('AKR-FLOW-3 서버 확인 실패(다른 세션 imp_uid) → 실패 안내 · 완료 버튼 없음', (t) async {
      final api = _Api()
        ..verifyError = const SignupApiException(code: 'permission-denied', reason: 'IMP_UID_BOUND_ELSEWHERE');
      await _pump(t, _flow(api, _sess('cert_issued', role: 'USER')));
      await t.tap(findVisibleText('간편인증으로 본인확인 하기'));
      await t.pumpAndSettle();
      expect(findVisibleText(SignupCopy.reasonMessage('IMP_UID_BOUND_ELSEWHERE')), findsOneWidget);
      expect(findVisibleText('가입 마치기'), findsNothing);
    });

    testWidgets('AKR-FLOW-4 약관 시행본이 바뀌면(TERMS_VERSION_STALE) 동의 단계로 · 고른 것 초기화', (t) async {
      final api = _Api()
        ..completeError = const SignupApiException(code: 'failed-precondition', reason: 'TERMS_VERSION_STALE');
      await _pump(t, _flow(api, _sess('pass_verified', role: 'USER')));
      expect(findVisibleText('가입 마치기'), findsOneWidget);
      await t.tap(findVisibleText('가입 마치기'));
      await t.pumpAndSettle();
      expect(findVisibleText('서비스 이용 약관에 동의해 주세요'), findsOneWidget);
      expect(findVisibleText(SignupCopy.reasonMessage('TERMS_VERSION_STALE')), findsOneWidget);
    });

    testWidgets('AKR-FLOW-5 사업주 완료 → 완료 화면에 준비 목록 없음(준비는 홈 공고 준비 카드)', (t) async {
      final api = _Api()..completeResult = const CompleteSignupResult(uid: 'a1', role: 'BUSINESS_ADMIN', customToken: 'c');
      final sink = <String>[];
      await _pump(t, _flow(api, _sess('pass_verified', role: 'BUSINESS_ADMIN'), sinkLog: sink));
      await t.tap(findVisibleText('가입 마치기'));
      await t.pumpAndSettle();
      expect(sink, ['c:false']);
      expect(findVisibleText('사업장 등록'), findsNothing);
      await _shot(t, 'S14_complete_admin');
    });

    testWidgets('AKR-FLOW-6 가입 완료 + 로그인 → 마법사가 스스로 닫혀 바로 홈(완료 화면 대기 0)', (t) async {
      final api = _Api();
      await _pump(
          t,
          Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(
                      builder: (_) => _flow(api, _sess('pass_verified', role: 'USER')))),
                  child: const Text('HOME_ROOT'),
                ),
              ),
            ),
          ));
      await t.tap(find.text('HOME_ROOT'));
      await t.pumpAndSettle();
      await t.tap(findVisibleText('가입 마치기'));
      await t.pumpAndSettle();
      expect(find.text('HOME_ROOT'), findsOneWidget);
      expect(find.byType(SignupFlowScreen), findsNothing);
    });

    testWidgets('AKR-FLOW-7 로그인 준비 실패면 완료 화면에 머문다(다시 시도 · 자동 닫힘 0)', (t) async {
      final api = _Api()
        ..completeResult = const CompleteSignupResult(uid: 'newUid', role: 'USER')
        ..finalizeError = const SignupApiException(code: 'unavailable', reason: 'AUTH_PROVISION_RETRY');
      await _pump(
          t,
          Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(
                      builder: (_) => _flow(api, _sess('pass_verified', role: 'USER')))),
                  child: const Text('HOME_ROOT'),
                ),
              ),
            ),
          ));
      await t.tap(find.text('HOME_ROOT'));
      await t.pumpAndSettle();
      await t.tap(findVisibleText('가입 마치기'));
      await t.pumpAndSettle();
      expect(find.byType(SignupFlowScreen), findsOneWidget);
      expect(findVisibleText('가입은 저장됐어요'), findsOneWidget);
      expect(findVisibleText('다시 시도'), findsOneWidget);
    });
  });

  group('AKR-RESUME', () {
    testWidgets('AKR-RESUME-1 cert_issued 로 재개 → 바로 본인확인 단계(목적·동의 다시 안 함)', (t) async {
      final api = _Api();
      await _pump(t, _flow(api, _sess('cert_issued', role: 'USER')));
      expect(findVisibleText('간편인증으로 본인확인 하기'), findsOneWidget);
      expect(findVisibleTextContaining('남은 단계 1'), findsOneWidget);
      expect(api.log, isEmpty);
    });
    testWidgets('AKR-RESUME-2 커밋 뒤 토큰 없음/Auth 실패 → 가입은 저장 · 다시 시도 → 같은 UID 토큰', (t) async {
      final api = _Api()
        ..completeResult = const CompleteSignupResult(uid: 'newUid', role: 'USER')
        ..finalizeError = const SignupApiException(code: 'unavailable', reason: 'AUTH_PROVISION_RETRY');
      final sink = <String>[];
      await _pump(t, _flow(api, _sess('pass_verified', role: 'USER'), sinkLog: sink));
      await t.tap(findVisibleText('가입 마치기'));
      await t.pumpAndSettle();
      expect(findVisibleText('가입은 저장됐어요'), findsOneWidget);
      expect(findVisibleText('다시 시도'), findsOneWidget);
      expect(sink, isEmpty);
      await _shot(t, 'S13_complete_auth_pending');
      api.finalizeError = null;
      await t.tap(findVisibleText('다시 시도'));
      await t.pumpAndSettle();
      expect(sink, ['ct-final:false']);
      expect(findVisibleText('시작하기'), findsOneWidget);
      expect(api.log.where((e) => e == 'complete').length, 1); // 커밋 재실행 0
    });
    testWidgets('AKR-RESUME-3 committed 세션으로 재개 → 완료 화면에서 토큰만 다시 받기', (t) async {
      final api = _Api();
      final c = SignupFlowController(
        api: api,
        session: _sess('committed', role: 'USER'),
        onToken: (t, {required bool switchAccount}) async => null,
      );
      expect(c.step, SignupStep.complete);
      await c.retryAuth();
      expect(api.log, ['finalize']);
      expect(c.signedIn, isTrue);
      c.dispose();
    });
    testWidgets('AKR-RESUME-4 역할 추가 세션 → 동의부터 · 완료 때 계정 전환(switchAccount=true)', (t) async {
      final api = _Api();
      final sink = <String>[];
      await _pump(t, _flow(api, _sess('started', role: 'BUSINESS_ADMIN', purpose: 'add_role'), sinkLog: sink));
      expect(findVisibleText('역할 추가'), findsOneWidget);
      expect(findVisibleText('서비스 이용 약관에 동의해 주세요'), findsOneWidget);
      await _agreeAll(t);
      await t.tap(findVisibleText('동의하고 계속'));
      await t.pumpAndSettle();
      await t.tap(findVisibleText('간편인증으로 본인확인 하기'));
      await t.pumpAndSettle();
      await t.tap(findVisibleText('가입 마치기'));
      await t.pumpAndSettle();
      expect(sink, ['ct-new:true']);
      expect(api.log.contains('setPurpose:BUSINESS_ADMIN'), isFalse);
    });
  });

  group('AKR-EXIST', () {
    testWidgets('AKR-EXIST-1 같은 CI·역할 → 이미 가입 안내 · 로그인 0 · 위험색 0', (t) async {
      final api = _Api()
        ..completeError = const SignupApiException(code: 'already-exists', reason: 'IDENTITY_ROLE_TAKEN');
      final sink = <String>[];
      await _pump(t, _flow(api, _sess('pass_verified', role: 'USER'), sinkLog: sink));
      await t.tap(findVisibleText('가입 마치기'));
      await t.pumpAndSettle();
      expect(findVisibleText('이미 가입된 계정이 있어요'), findsOneWidget);
      expect(findVisibleText('처음 가입한 카카오 계정으로 로그인해 주세요'), findsOneWidget);
      expect(findVisibleText('처음 화면으로'), findsOneWidget);
      expect(sink, isEmpty);
      await _shot(t, 'S11_existing_account');
    });
    testWidgets('AKR-EXIST-2 재가입 제한 → 가입 이어갈 수 없음 안내', (t) async {
      final api = _Api()
        ..completeError = const SignupApiException(code: 'permission-denied', reason: 'REREGISTER_COOLDOWN');
      await _pump(t, _flow(api, _sess('pass_verified', role: 'USER')));
      await t.tap(findVisibleText('가입 마치기'));
      await t.pumpAndSettle();
      expect(findVisibleText('지금은 가입을 이어갈 수 없어요'), findsOneWidget);
      expect(findVisibleTextContaining('재가입 제한 기간'), findsOneWidget);
    });
  });

  group('AKR-DOC', () {
    testWidgets('AKR-DOC-1 국적 미확정 서류 입구 — 두 서류 같은 틀 · 고른 값 반환', (t) async {
      String? picked;
      await _pump(
          t,
          Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async => picked = await showIdDocumentKindSheet(ctx),
                  child: const Text('open'),
                ),
              ),
            ),
          ));
      await t.tap(findVisibleText('open'));
      await t.pumpAndSettle();
      expect(findVisibleText('주민등록증 · 운전면허증'), findsOneWidget);
      expect(findVisibleText('외국인등록증'), findsOneWidget);
      await _shot(t, 'S15_id_document_kind_sheet');
      await t.tap(findVisibleText('외국인등록증'));
      await t.pumpAndSettle();
      expect(picked, IdDocumentKindSheet.foreignRegistration);
    });
    testWidgets('AKR-DOC-2 외국인등록증 정보 — 형식 확인 · 서버 거절 안내 · payload 키', (t) async {
      final sent = <Map<String, dynamic>>[];
      await _pump(
          t,
          ForeignIdDocumentScreen(registrar: (p) async {
            sent.add(p);
            return SignupCopy.reasonMessage('FOREIGN_ID_BIRTHDATE_MISMATCH');
          }));
      await _shot(t, 'S16_foreign_id_document');
      await t.tap(findVisibleText('다음 · 사진 올리기'));
      await t.pumpAndSettle();
      expect(findVisibleText('외국인등록번호 13자리를 입력해 주세요'), findsOneWidget);
      expect(sent, isEmpty);
      await t.enterText(find.byType(TextFormField).at(0), '9003045234567');
      await t.enterText(find.byType(TextFormField).at(1), 'NGUYEN VAN AN');
      await t.tap(findVisibleText('다음 · 사진 올리기'));
      await t.pumpAndSettle();
      expect(sent.single.keys.toSet(), {'rawForeignId', 'legalName'});
      expect(findVisibleText(SignupCopy.reasonMessage('FOREIGN_ID_BIRTHDATE_MISMATCH')), findsOneWidget);
      // 번호는 화면에 평문으로 다시 보이지 않는다
      expect(findVisibleText('9003045234567'), findsNothing);
    });
    testWidgets('AKR-DOC-3 카카오 계정 보안 칸 — 비밀번호 대신 로그인 수단 · 다른 역할 추가', (t) async {
      final api = _Api();
      final u = UserModel(
          uid: 'u1', username: '', name: '김알핏', email: '', role: UserRole.USER,
          authProviders: const ['kakao'], signupSource: 'kakao_v1', nationalityStatus: 'unknown');
      await _pump(t, Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: ProviderAccountCard(user: u, api: api))));
      expect(findVisibleText('카카오로 로그인해요'), findsOneWidget);
      expect(findVisibleText('사업주 계정 추가'), findsOneWidget);
      await _shot(t, 'S17_provider_account_card');
    });
  });

  group('AKR-WIDE', () {
    for (final s in const [SignupStep.purpose, SignupStep.consent, SignupStep.identity, SignupStep.complete]) {
      testWidgets('AKR-WIDE ${s.name} 320dp · 글자 2.0 넘침 0', (t) async {
        final state = switch (s) {
          SignupStep.purpose => 'started',
          SignupStep.consent => 'purpose_selected',
          SignupStep.identity => 'pass_verified',
          _ => 'committed',
        };
        await _pump(t, _flow(_Api(), _sess(state, role: 'BUSINESS_ADMIN')),
            size: const Size(320, 640), scale: 2.0);
        expect(t.takeException(), isNull);
      });
    }
    testWidgets('AKR-WIDE start 320dp · 글자 2.0 넘침 0', (t) async {
      await _pump(t, AuthStartScreen(gateway: _Gateway(configured: false), api: _Api()),
          size: const Size(320, 640), scale: 2.0);
      expect(t.takeException(), isNull);
    });
  });
}

/// 버튼 문구 상수(시험 가독용).
class KakaoLoginButtonLabels {
  static const notConfigured = '카카오 로그인 준비 중';
}
