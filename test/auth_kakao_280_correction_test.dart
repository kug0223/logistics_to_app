// [ALFIT-AUTH-KAKAO-ONBOARDING.1 · 판정280 교정 · 앱] 삭제 재확인 · 삭제 재개 · 선택 동의 · 닫힌 입구 · 아이디 찾기.
//
//   K280-G   blacklisted + deleting → 삭제 복구(일반 홈 0 · 세션 유지) — 서버 판정 순서(삭제중 > 블랙)와 같다
//   K280-E   DELETION_RECOVERY 토큰 처리 실패를 삼키지 않는다
//   K280-D   KG 삭제 재확인: requestId → KG → verify(account_deletion) → 같은 삭제 파이프라인 · 취소/실패/만료/재시도
//   K280-W   탈퇴 화면(확인창 → 본인확인 → 완료 true) · 재개 화면(비밀번호 칸 0)
//   K280-C   미완료 세션 선택약관 true→false 를 서버에 그대로 보낸다
//   K280-F   아이디 찾기 providerAccounts → '카카오로 가입' 행
//   K280-S   소스 계약 — reauthMethod 분기 · 공유 파이프라인 · providerUnlink 범위 · 닫힌 PASS 입구 정리
//   실제 KG/카카오/서버 = PENDING VERIFICATION(모의 응답만).
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ALfit/models/core/legal_terms_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/screens/auth/signup/signup_flow_controller.dart';
import 'package:ALfit/screens/common/deletion_reauth_screen.dart';
import 'package:ALfit/services/auth/deletion_reauth_api.dart';
import 'package:ALfit/services/auth/kakao_auth_service.dart';
import 'package:ALfit/services/auth/kakao_entry.dart';
import 'package:ALfit/services/auth/login_gate.dart';
import 'package:ALfit/services/auth/signup_api.dart';
import 'package:ALfit/services/auth_service.dart';
import 'package:ALfit/services/pass_verification_service.dart';
import 'package:ALfit/theme/role_theme.dart';

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

class _DelApi implements DeletionReauthApi {
  final log = <String>[];
  Object? startError;
  Object? verifyError;
  @override
  Future<DeletionReauthTicket> start() async {
    log.add('start');
    if (startError != null) throw startError!;
    return DeletionReauthTicket(requestId: 'del_req_${log.length}');
  }

  @override
  Future<DateTime?> verify(String impUid) async {
    log.add('verify:$impUid');
    if (verifyError != null) throw verifyError!;
    return DateTime.now().add(const Duration(minutes: 10));
  }
}

class _Gw implements LoginProviderGateway {
  @override
  LoginProviderKind get kind => LoginProviderKind.kakao;
  @override
  bool get isConfigured => true;
  @override
  Future<ProviderLoginResult> login() async => const ProviderLoginResult.success('at');
  @override
  Future<void> logout() async {}
  @override
  Future<void> unlink() async {}
}

class _RecApi implements SignupApi {
  final records = <Map<String, dynamic>>[];
  @override
  Future<AuthKakaoResult> authKakao({required String accessToken, String? role}) async =>
      const AuthKakaoDeletionRecovery('del-token');
  @override
  Future<SignupSession> recordConsent(SignupSession s, Map<String, dynamic> consentRecord) async {
    records.add(consentRecord);
    return SignupSession.tryFrom(
        {'sessionId': s.sessionId, 'secret': 'x', 'state': 'consented', 'role': s.role})!;
  }

  @override
  Future<SignupSession> setPurpose(SignupSession s, {required String role}) async =>
      SignupSession.tryFrom({'sessionId': s.sessionId, 'secret': 'x', 'state': 'purpose_selected', 'role': role})!;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('부르지 않는다');
}

EffectiveLegalTerms _terms() => EffectiveLegalTerms(
      items: const [
        LegalTermsItem(id: 'service', title: '서비스 이용약관', content: '본문', isRequired: true, version: '3'),
        LegalTermsItem(id: 'marketing', title: '혜택 알림 받기', content: '본문', isRequired: false, order: 1, version: '1'),
      ],
      upcoming: const [],
      serverNow: DateTime(2026, 11, 25),
    );

String _src(String p) => File(p).readAsStringSync();

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  group('K280-G 차단 + 탈퇴중', () {
    test('K280-G1 블랙이어도 탈퇴중이면 삭제 복구(세션 유지) — 지도 · 모델 경로 둘 다', () {
      final v = LoginGate.fromMap({'isBlacklisted': true, 'accountStatus': 'deleting'});
      expect(v.kind, LoginGateKind.deleting);
      expect(v.signsOut, isFalse);
      final m = UserModel(uid: 'u', username: '', name: 'n', email: '', role: UserRole.USER,
          isBlacklisted: true, accountStatus: 'deleting');
      expect(LoginGate.fromUser(m).kind, LoginGateKind.deleting);
      // 탈퇴중이 아니면 차단 그대로
      expect(LoginGate.fromMap({'isBlacklisted': true}).kind, LoginGateKind.blacklisted);
    });
    test('K280-G2 deleting 은 일반 홈이 아니라 재개 화면 — provider 가 currentUser 를 세우지 않는다(소스)', () {
      final up = _src('lib/providers/user_provider.dart');
      final at = up.indexOf("if (_currentUser?.accountStatus == 'deleting') {");
      expect(at, greaterThan(0));
      final block = up.substring(at, up.indexOf('return;', at));
      expect(block, contains('_currentUser = null;'));
      expect(block, contains('_deletionRecovery = DeletionRecoveryState.required;'));
      // LoginGate 판정은 그 뒤 — deleting 이 차단 판정에 먼저 걸리지 않는다
      expect(up.indexOf('LoginGate.fromUser(_currentUser!)'), greaterThan(at));
    });
  });

  group('K280-E 토큰 실패를 삼키지 않는다', () {
    test('K280-E1 DELETION_RECOVERY 토큰 로그인 실패 → EntryFailed(사유)', () async {
      final e = KakaoEntry(gateway: _Gw(), api: _RecApi(), onToken: (_) async => '세션을 열지 못했어요');
      final out = await e.start();
      expect(out, isA<EntryFailed>());
      expect((out as EntryFailed).message, '세션을 열지 못했어요');
      final ok = KakaoEntry(gateway: _Gw(), api: _RecApi(), onToken: (_) async => null);
      expect(await ok.start(), isA<EntryDeletionRecovery>());
    });
  });

  group('K280-D KG 삭제 재확인 컨트롤러', () {
    DeletionReauthController mk(_DelApi api, List<String> log,
            {List<String?>? pipelineResults, PassLaunchOutcome Function(String id)? kg, WithdrawPrecheck? pre}) =>
        DeletionReauthController(
          api: api,
          precheck: pre,
          kgLauncher: (id) async {
            log.add('kg:$id');
            return kg?.call(id) ?? const PassLaunchOutcome.returned('imp_del');
          },
          pipeline: () async {
            log.add('pipeline');
            final r = pipelineResults == null || pipelineResults.isEmpty ? null : pipelineResults.removeAt(0);
            return r;
          },
        );

    test('K280-D1 정상: 서버 requestId 로 KG → verify(account_deletion) → 같은 삭제 파이프라인 → 완료', () async {
      final api = _DelApi();
      final log = <String>[];
      final c = mk(api, log);
      await c.run();
      expect(api.log, ['start', 'verify:imp_del']);
      expect(log, ['kg:del_req_1', 'pipeline']);
      expect(c.phase, DeletionReauthPhase.done);
    });
    test('K280-D2 KG 취소 → 증명 · 삭제 0', () async {
      final api = _DelApi();
      final log = <String>[];
      final c = mk(api, log, kg: (_) => const PassLaunchOutcome.canceled());
      await c.run();
      expect(c.phase, DeletionReauthPhase.canceled);
      expect(api.log, ['start']);
      expect(log.contains('pipeline'), isFalse);
    });
    test('K280-D3 다른 사람 KG(IDENTITY_MISMATCH) → 실패 · 삭제 0', () async {
      final api = _DelApi()..verifyError = const SignupApiException(code: 'permission-denied', reason: 'IDENTITY_MISMATCH');
      final log = <String>[];
      final c = mk(api, log);
      await c.run();
      expect(c.phase, DeletionReauthPhase.failed);
      expect(c.message, SignupCopy.reasonMessage('IDENTITY_MISMATCH'));
      expect(log.contains('pipeline'), isFalse);
    });
    test('K280-D4 증명 만료(DELETION_REAUTH_REQUIRED) → 만료 · 다음 시도는 본인확인부터', () async {
      final api = _DelApi();
      final log = <String>[];
      final c = mk(api, log, pipelineResults: [kDeletionReauthExpiredMessage, null]);
      await c.run();
      expect(c.phase, DeletionReauthPhase.expired);
      expect(c.proofAlive, isFalse);
      await c.run();
      expect(api.log.where((e) => e == 'start').length, 2);
      expect(c.phase, DeletionReauthPhase.done);
    });
    test('K280-D5 삭제 단계 실패 + 증명 유효 → 다음 시도는 삭제만(KG 재요구 0)', () async {
      final api = _DelApi();
      final log = <String>[];
      final c = mk(api, log, pipelineResults: ['탈퇴가 완료되지 않았습니다. 데이터 정리를 마치려면 다시 시도해 주세요.', null]);
      await c.run();
      expect(c.phase, DeletionReauthPhase.failed);
      expect(c.proofAlive, isTrue);
      await c.run();
      expect(api.log.where((e) => e == 'start').length, 1);
      expect(log.where((e) => e == 'pipeline').length, 2);
      expect(c.phase, DeletionReauthPhase.done);
    });
    test('K280-D6 탈퇴 차단 사유가 있으면 KG(유료) 전에 멈춘다', () async {
      final api = _DelApi();
      final log = <String>[];
      final c = mk(api, log, pre: () async => '미서명 계약서(1건)를 먼저 서명해주세요.');
      await c.run();
      expect(c.phase, DeletionReauthPhase.failed);
      expect(api.log, isEmpty);
      expect(log, isEmpty);
    });
  });

  group('K280-W 화면', () {
    Future<void> pump(WidgetTester t, Widget home) async {
      t.view.physicalSize = const Size(392, 820);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(theme: RoleTheme.workerTheme, home: home));
      await t.pumpAndSettle();
    }

    testWidgets('K280-W1 탈퇴: 확인창 → 본인확인 → 같은 파이프라인 → true 로 닫힘', (t) async {
      final api = _DelApi();
      var piped = 0;
      bool? popped;
      await pump(
          t,
          Builder(
            builder: (ctx) => Scaffold(
              body: TextButton(
                onPressed: () async => popped = await Navigator.of(ctx).push<bool>(MaterialPageRoute(
                  builder: (_) => DeletionReauthScreen(
                    intent: DeletionReauthIntent.withdraw,
                    api: api,
                    precheck: () async => null,
                    kgLauncher: (id) async => const PassLaunchOutcome.returned('imp_w'),
                    pipeline: () async {
                      piped++;
                      return null;
                    },
                  ),
                )),
                child: const Text('open'),
              ),
            ),
          ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(findVisibleText('본인확인하고 탈퇴하기'), findsOneWidget);
      expect(find.byType(TextField), findsNothing, reason: '비밀번호 칸 0');
      await t.tap(findVisibleText('본인확인하고 탈퇴하기'));
      await t.pumpAndSettle();
      expect(find.text('탈퇴하기'), findsOneWidget); // 확인창
      await t.tap(find.text('탈퇴하기'));
      await t.pumpAndSettle();
      expect(api.log, ['start', 'verify:imp_w']);
      expect(piped, 1);
      expect(popped, isTrue);
    });

    testWidgets('K280-W2 재개(users 문서 없음 포함): 비밀번호 칸 0 · 완료 뒤 onDone', (t) async {
      var done = 0;
      await pump(
          t,
          DeletionReauthScreen(
            intent: DeletionReauthIntent.resume,
            api: _DelApi(),
            kgLauncher: (id) async => const PassLaunchOutcome.returned('imp_r'),
            pipeline: () async => null,
            onDone: () async => done++,
            onSignOut: () async {},
          ));
      expect(findVisibleText('계정 삭제를 마무리하고 있어요'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(findVisibleText('로그아웃'), findsOneWidget);
      await t.tap(findVisibleText('본인확인하고 마무리하기'));
      await t.pumpAndSettle();
      expect(done, 1);
    });
  });

  group('K280-C 선택 동의 마지막 선택', () {
    test('K280-C1 미완료 세션에서 선택 true→false → 보이는 모든 항목의 현재 bool 을 그대로 보낸다', () async {
      final api = _RecApi();
      final c = SignupFlowController(
        api: api,
        session: SignupSession.tryFrom({'sessionId': 's', 'secret': 'x', 'state': 'purpose_selected', 'role': 'USER'})!,
        termsLoader: () async => _terms(),
        onToken: (t, {required bool switchAccount}) async => null,
      );
      await c.loadTerms();
      c.setChoice('service', true);
      c.setChoice('marketing', true);
      await c.submitConsent();
      // 다시 동의 화면으로 와서 선택 항목을 끈다
      c.backToPurpose();
      await c.submitPurpose();
      c.setChoice('marketing', false);
      await c.submitConsent();
      expect(api.records.length, 2);
      expect(api.records.first['marketing'], {'agreed': true, 'version': '1'});
      expect(api.records.last['marketing'], {'agreed': false, 'version': '1'});
      expect(api.records.last['service'], {'agreed': true, 'version': '3'});
      c.dispose();
    });
  });

  group('K280-F 아이디 찾기', () {
    test('K280-F1 providerAccounts(kakao) → 카카오로 가입 행 · 다른 provider 무시 · 빈 아이디 무시', () {
      final r = AuthService.parseFindUsernameResponse({
        'accounts': [
          {'username': 'qa_user', 'role': 'USER'},
          {'username': '', 'role': 'USER'},
        ],
        'providerAccounts': [
          {'provider': 'kakao', 'role': 'BUSINESS_ADMIN'},
          {'provider': 'email', 'role': 'USER'},
        ],
      });
      expect(r, [
        {'username': 'qa_user', 'role': 'USER'},
        {'username': '', 'role': 'BUSINESS_ADMIN', 'provider': 'kakao'},
      ]);
      expect(AuthService.parseFindUsernameResponse({'providerAccounts': [{'provider': 'kakao', 'role': 'USER'}]}).single['provider'],
          'kakao');
      expect(AuthService.parseFindUsernameResponse(null), isEmpty);
    });
    test('K280-F2 시트가 카카오 행을 아이디로 마스킹하지 않고 카카오 로그인으로 잇는다(소스)', () {
      final l = _src('lib/screens/auth/login_screen.dart');
      expect(l, contains("isKakao ? '카카오로 가입' : maskUsername(username)"));
      expect(l, contains("? '카카오로 가입하셨어요'"));
      expect(l, contains("child: Text('카카오로 로그인하기',"));
      expect(l, contains('_goKakaoStart();'));
    });
  });

  group('K280-S 소스 계약', () {
    test('K280-S1 재개 화면은 서버 reauthMethod(없으면 비밀번호 없는 계정)로 KG 화면을 고른다', () {
      final m = _src('lib/main.dart');
      final s = m.substring(m.indexOf('class _DeletionRecoveryScreenState'),
          m.indexOf('class _HomeRegionRecoveryScreen extends StatefulWidget'));
      expect(s, contains('bool _kakaoKg = AuthService().currentUser?.email == null;'));
      expect(s, contains("setState(() => _kakaoKg = m == 'kakao_kg');"));
      expect(s, contains('intent: DeletionReauthIntent.resume,'));
      // 비밀번호 재개는 그대로(옛 QA)
      expect(s, contains('final err = await AuthService().deleteAccountWithPassword(pw);'));
    });
    test('K280-S2 두 탈퇴 경로가 같은 파이프라인 · KG 경로에 비밀번호 대용 0', () {
      final a = _src('lib/services/auth_service.dart');
      final pw = a.substring(a.indexOf('Future<String?> deleteAccountWithPassword(String password) async {'),
          a.indexOf('Future<String?> deleteAccountAfterKgProof() async {'));
      expect(pw.indexOf('reauthenticateWithCredential'), lessThan(pw.indexOf('return await _runDeletionPipeline();')));
      final kg = a.substring(a.indexOf('Future<String?> deleteAccountAfterKgProof() async {'),
          a.indexOf('Future<String?> _runDeletionPipeline() async {'));
      expect(kg, contains('return _runDeletionPipeline();'));
      expect(kg, isNot(contains('EmailAuthProvider')));
      final pipe = a.substring(a.indexOf('Future<String?> _runDeletionPipeline() async {'));
      expect(pipe.indexOf('callableDeleteAccountPreData'), lessThan(pipe.indexOf('callableDeleteAccountApplications')));
      expect(pipe.indexOf('callableDeleteAccountApplications'), lessThan(pipe.indexOf('callableDeleteAccountFinal')));
    });
    test('K280-S3 카카오 unlink 는 서버 providerUnlink == ALLOWED 일 때만', () {
      final a = _src('lib/services/auth_service.dart');
      expect(a, contains("if (providerUnlink == 'ALLOWED') {"));
      expect('providerUnlinkHook'.allMatches(a).length, greaterThanOrEqualTo(2));
      final k = _src('lib/services/auth/kakao_auth_service.dart');
      expect(k, contains('AuthService.providerUnlinkHook = instance.unlink;'));
      // unlink 를 직접 부르는 화면은 없다
      for (final f in [
        'lib/screens/common/deletion_reauth_screen.dart',
        'lib/screens/common/settings_screen.dart',
        'lib/screens/user/user_settings_screen.dart',
        'lib/main.dart',
      ]) {
        expect(_src(f).contains('.unlink('), isFalse, reason: f);
      }
    });
    test('K280-S4 설정 탈퇴 두 입구가 카카오 계정을 KG 화면으로 보낸다', () {
      for (final f in ['lib/screens/common/settings_screen.dart', 'lib/screens/user/user_settings_screen.dart']) {
        final s = _src(f);
        expect(s, contains('currentUser?.isProviderAccount == true'), reason: f);
        expect(s, contains('const DeletionReauthScreen(intent: DeletionReauthIntent.withdraw)'), reason: f);
      }
    });
    test('K280-S5 닫힌 PASS 입구: KG 창을 열기 전에 멈춘다 · 프로필 재인증 숨김 · 비밀번호 찾기 PASS 제거', () {
      expect(PassVerificationService.closedLegacyPurposes, {'register', 'reauth', 'resetPassword'});
      final p = _src('lib/services/pass_verification_service.dart');
      final auth = p.substring(p.indexOf('static Future<PassAuthResult?> authenticate({'));
      expect(auth.indexOf('if (closedLegacyPurposes.contains(purpose)) {'),
          lessThan(auth.indexOf('navigatorKey.currentState')));
      final pe = _src('lib/screens/common/profile_edit_screen.dart');
      expect(pe, contains("final canReauth = PassVerificationService.closedLegacyPurposes.contains('reauth')"));
      final l = _src('lib/screens/auth/login_screen.dart')
          .split('\n')
          .where((x) => !x.trimLeft().startsWith('//'))
          .join('\n');
      expect(l.contains('resetPasswordWithPass'), isFalse);
      expect(l.contains('PassAuthButton('), isFalse);
      expect(l, contains('kLegacyPassResetClosedMessage'));
    });
  });
}
