// [ALFIT-AUTH-KAKAO-ONBOARDING.1 · 구현1 · 앱] 순수 판정 · 응답 판독 · 국적 unknown reader 계약.
//
//   AKA-G*  LoginGate(카카오 · 자동 복원) = 아이디 로그인 판정(AS signIn)과 같은 결과 · 같은 문구
//   AKA-P*  callableAuthKakao / 세션 / 완료 응답 판독 — 빠진 값은 성공으로 접지 않는다
//   AKA-C*  문구 금지어('인증 완료/검증 완료/취업자격/진위') 0
//   AKA-U*  nationality unknown reader — isForeign · 서류 기대값 · 성별 폴백 · 홈 PASS 회복 · copyWith 보존
//   AKA-S*  소스 계약 — 옛 가입 입구 닫힘 · 서류 종류 먼저 · 비밀번호 탈퇴 흉내 0
//   실제 카카오/KG/서버 = PENDING VERIFICATION(모의 응답만).
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/services/auth/login_gate.dart';
import 'package:ALfit/services/auth/signup_api.dart';
import 'package:ALfit/services/auth_service.dart';
import 'package:ALfit/utils/identity_identifier.dart';
import 'package:ALfit/screens/auth/signup/signup_flow_controller.dart';
import 'package:ALfit/screens/common/foreign_id_document_screen.dart';

UserModel _u({
  String? nationalityStatus,
  List<String>? authProviders,
  String? signupSource,
  String? gender = '남성',
  DateTime? birthDate,
  String? fingerprint,
  DateTime? passVerifiedAt,
  UserRole role = UserRole.USER,
}) =>
    UserModel(
      uid: 'u1',
      username: '',
      name: '홍길동',
      email: '',
      role: role,
      gender: gender,
      birthDate: birthDate ?? DateTime(1990, 3, 4),
      foreignIdentityFingerprint: fingerprint,
      passVerifiedAt: passVerifiedAt,
      nationalityStatus: nationalityStatus,
      authProviders: authProviders,
      signupSource: signupSource,
    );

void main() {
  group('AKA-G LoginGate', () {
    final now = DateTime(2026, 11, 25, 12);
    test('AKA-G1 이용 차단 — 아이디 로그인 문구와 같다 · 세션 정리', () {
      final v = LoginGate.fromMap({'isBlacklisted': true, 'blacklistReason': '반복 노쇼'}, now: now);
      expect(v.kind, LoginGateKind.blacklisted);
      expect(v.signsOut, isTrue);
      expect(v.message, '계정 이용 차단 상태라 해제 전까지 로그인할 수 없어요.\n사유: 반복 노쇼\n고객센터에 문의해주세요.');
      // 사유 없으면 기본 사유(signIn 과 같다)
      expect(LoginGate.fromMap({'isBlacklisted': true}, now: now).message, contains('사유: 이용 정책 위반'));
    });
    test('AKA-G2 옛 가입 미완료 → 세션 유지(복구 화면) · 거절 → 문구', () {
      expect(LoginGate.fromMap({'accountStatus': 'pending'}, now: now).kind, LoginGateKind.incompleteLegacy);
      expect(LoginGate.fromMap({'accountStatus': 'registration_pending'}, now: now).signsOut, isFalse);
      final r = LoginGate.fromMap({'accountStatus': 'rejected', 'rejectionReason': 'X'}, now: now);
      expect(r.kind, LoginGateKind.rejected);
      expect(r.message, '가입이 거절되었습니다.\n사유: X');
      expect(LoginGate.fromMap({'accountStatus': 'rejected'}, now: now).message,
          '가입이 거절되었습니다.\n고객센터에 문의해주세요.');
    });
    test('AKA-G3 기간 제한 — 아직이면 restrictionLoginMessage, 지났으면 통과 · Timestamp 아니면 제한 없음', () {
      final until = DateTime(2026, 11, 26, 9);
      final v = LoginGate.fromMap(
          {'restrictedUntil': Timestamp.fromDate(until), 'restrictionSource': 'auto'}, now: now);
      expect(v.kind, LoginGateKind.restricted);
      expect(v.message, AuthService.restrictionLoginMessage(until, 'auto'));
      expect(LoginGate.fromMap({'restrictedUntil': Timestamp.fromDate(DateTime(2026, 11, 1))}, now: now).allowed,
          isTrue);
      expect(LoginGate.fromMap({'restrictedUntil': '2099-01-01'}, now: now).allowed, isTrue);
    });
    test('AKA-G4 탈퇴 진행 중(deleting)은 막지 않고 삭제 재개로 — 세션 유지', () {
      final v = LoginGate.fromMap({'accountStatus': 'deleting'}, now: now);
      expect(v.kind, LoginGateKind.deleting);
      expect(v.signsOut, isFalse);
    });
    test('AKA-G5 모델 경로(자동 복원)도 같은 판정', () {
      final m = UserModel(
          uid: 'a', username: 'a', name: 'a', email: '', role: UserRole.USER,
          isBlacklisted: true, blacklistReason: 'R');
      expect(LoginGate.fromUser(m, now: now).kind, LoginGateKind.blacklisted);
      expect(LoginGate.fromUser(_u(), now: now).allowed, isTrue);
    });
    test('AKA-G6 signIn 본문은 그대로 — LoginGate 문구가 signIn 리터럴과 같다(소스 대조)', () {
      final src = File('lib/services/auth_service.dart').readAsStringSync();
      expect(src, contains(r"throw Exception('계정 이용 차단 상태라 해제 전까지 로그인할 수 없어요.\n사유: $reason\n고객센터에 문의해주세요.');"));
      final gate = File('lib/services/auth/login_gate.dart').readAsStringSync();
      expect(gate, contains(r"'계정 이용 차단 상태라 해제 전까지 로그인할 수 없어요.\n사유: $reason\n고객센터에 문의해주세요.'"));
    });
  });

  group('AKA-P 응답 판독', () {
    test('AKA-P1 TOKEN · ROLE_SELECTION · SIGNUP_REQUIRED · DELETION_RECOVERY', () {
      final t = parseAuthKakaoResult({'status': 'TOKEN', 'uid': 'u1', 'role': 'USER', 'customToken': 'ct'});
      expect(t, isA<AuthKakaoToken>());
      final r = parseAuthKakaoResult({
        'status': 'ROLE_SELECTION_REQUIRED',
        'roles': [
          {'role': 'USER', 'uid': 'a'},
          'BUSINESS_ADMIN'
        ]
      });
      expect((r as AuthKakaoRoleSelection).roles, ['USER', 'BUSINESS_ADMIN']);
      final s = parseAuthKakaoResult({
        'status': 'SIGNUP_REQUIRED',
        'session': {'sessionId': 's1', 'secret': 'x', 'state': 'cert_issued', 'role': 'USER'}
      });
      expect((s as AuthKakaoSignupRequired).session.state, SignupSessionState.certIssued);
      expect(parseAuthKakaoResult({'status': 'DELETION_RECOVERY', 'customToken': 'c'}),
          isA<AuthKakaoDeletionRecovery>());
    });
    test('AKA-P2 빠진 값 · 모르는 상태는 성공으로 접지 않는다', () {
      expect(() => parseAuthKakaoResult({'status': 'TOKEN', 'uid': 'u1'}), throwsA(isA<SignupApiException>()));
      expect(() => parseAuthKakaoResult({'status': 'ROLE_SELECTION_REQUIRED', 'roles': ['USER']}),
          throwsA(isA<SignupApiException>()));
      expect(() => parseAuthKakaoResult({'status': 'SIGNUP_REQUIRED', 'session': {'sessionId': 's'}}),
          throwsA(isA<SignupApiException>()));
      expect(() => parseAuthKakaoResult({'status': 'WHAT'}), throwsA(isA<SignupApiException>()));
      try {
        parseAuthKakaoResult({'status': 'ACCOUNT_DELETED'});
        fail('throw 해야 한다');
      } on SignupApiException catch (e) {
        expect(e.reason, 'ACCOUNT_DELETED');
      }
      expect(() => parseCompleteResult({'status': 'COMMITTED'}), throwsA(isA<SignupApiException>()));
      expect(parseCompleteResult({'uid': 'u', 'role': 'USER'}).customToken, isNull);
    });
    test('AKA-P5 server_api_1 정렬 — ROLE_NOT_LINKED · SessionView pass/expiresAtMs · 계정 상태 reason 문구', () {
      final r = parseAuthKakaoResult({'status': 'ROLE_NOT_LINKED', 'roles': ['USER']});
      expect((r as AuthKakaoRoleNotLinked).roles, ['USER']);
      final s = SignupSession.tryFrom({
        'sessionId': 's', 'secret': 'x', 'state': 'pass_verified', 'role': 'USER', 'expiresAtMs': 1764000000000,
        'pass': {'name': '김알핏', 'birthDate': '19900304', 'phoneMasked': '010-****-1234'},
      })!;
      expect(s.pass!.name, '김알핏');
      expect(s.expiresAt, DateTime.fromMillisecondsSinceEpoch(1764000000000));
      final c = SignupFlowController(api: _NoApi(), session: s, onToken: (t, {required bool switchAccount}) async => null);
      expect(c.kgPhase, KgPhase.verified);
      expect(c.verification!.phoneMasked, '010-****-1234');
      c.dispose();
      // 카카오 로그인 거절 문구 = 아이디 로그인 차단 문구
      expect(SignupCopy.reasonMessage('ACCOUNT_BLACKLISTED', details: {'blacklistReason': '반복 노쇼'}),
          LoginGate.fromMap({'isBlacklisted': true, 'blacklistReason': '반복 노쇼'}).message);
      final until = DateTime(2099, 1, 2, 3);
      expect(
          SignupCopy.reasonMessage('ACCOUNT_RESTRICTED',
              details: {'restrictedUntilMs': until.millisecondsSinceEpoch, 'restrictionSource': 'manual'}),
          AuthService.restrictionLoginMessage(until, 'manual'));
      expect(SignupCopy.reasonMessage('REREGISTER_COOLDOWN', details: {'canReregisterAtMs': 1764000000000}),
          contains('부터 다시 가입할 수 있어요'));
    });
    test('AKA-P3 세션 secret 은 toString 에 나오지 않는다', () {
      final s = SignupSession.tryFrom({'sessionId': 's1', 'secret': 'TOPSECRET', 'state': 'started'})!;
      expect(s.toString(), isNot(contains('TOPSECRET')));
    });
    test('AKA-P4 서버 상태 → 화면 단계(재개)', () {
      SignupSession s(String st, {String? role, String purpose = 'signup'}) =>
          SignupSession.tryFrom({'sessionId': 'i', 'secret': 'x', 'state': st, 'role': role, 'purpose': purpose})!;
      expect(SignupFlowController.stepFor(s('started')), SignupStep.purpose);
      expect(SignupFlowController.stepFor(s('started', role: 'USER', purpose: 'add_role')), SignupStep.consent);
      expect(SignupFlowController.stepFor(s('purpose_selected')), SignupStep.consent);
      expect(SignupFlowController.stepFor(s('consented')), SignupStep.identity);
      expect(SignupFlowController.stepFor(s('cert_issued')), SignupStep.identity);
      expect(SignupFlowController.stepFor(s('pass_verified')), SignupStep.identity);
      expect(SignupFlowController.stepFor(s('committed')), SignupStep.complete);
      expect(SignupFlowController.stepFor(s('blocked_existing')), SignupStep.existingAccount);
      expect(SignupFlowController.stepFor(s('expired')), SignupStep.blocked);
    });
  });

  group('AKA-C 문구', () {
    const forbidden = ['인증 완료', '검증 완료', '취업자격', '진위', '본인인증 완료'];
    test('AKA-C1 reason 문구 · 새 화면 소스에 금지어 0', () {
      const reasons = [
        'KAKAO_NOT_CONFIGURED', 'KAKAO_TOKEN_INVALID', 'SESSION_EXPIRED', 'TERMS_VERSION_STALE',
        'CERT_ATTEMPTS_EXCEEDED', 'IMP_UID_BOUND_ELSEWHERE', 'PASS_RESULT_STALE', 'REREGISTER_BLACKLISTED',
        'REREGISTER_COOLDOWN', 'IDENTITY_ROLE_TAKEN', 'SUBJECT_IDENTITY_MISMATCH', 'LINK_CONFLICT',
        'AUTH_PROVISION_RETRY', 'ACCOUNT_DELETED', 'NATIONALITY_UNCONFIRMED', 'FOREIGN_ID_BIRTHDATE_MISMATCH',
      ];
      for (final r in reasons) {
        final m = SignupCopy.reasonMessage(r);
        for (final f in forbidden) {
          expect(m.contains(f), isFalse, reason: '$r: $m');
        }
      }
      final files = [
        ...Directory('lib/screens/auth/signup').listSync().whereType<File>(),
        File('lib/screens/auth/auth_start_screen.dart'),
        File('lib/screens/common/foreign_id_document_screen.dart'),
        File('lib/widgets/common/id_document_kind_sheet.dart'),
        File('lib/widgets/auth/provider_account_card.dart'),
        File('lib/widgets/auth/role_login_choice_sheet.dart'),
      ];
      for (final f in files) {
        // 주석 줄은 빼고 본다(설계 설명에 금지어를 '쓰지 않는다' 고 적은 줄)
        final code = f.readAsLinesSync().where((l) => !l.trimLeft().startsWith('//')).join('\n');
        for (final w in forbidden) {
          expect(code.contains(w), isFalse, reason: '${f.path} 에 "$w"');
        }
      }
    });
    test('AKA-C2 IDENTITY_ROLE_TAKEN 안내 = 처음 가입한 카카오로 로그인(연결 0)', () {
      expect(SignupCopy.reasonMessage('IDENTITY_ROLE_TAKEN'), contains('처음 가입한 카카오 계정'));
    });
  });

  group('AKA-U 국적 unknown reader', () {
    test('AKA-U1 unknown 은 isForeign false 이지만 미확정으로 따로 읽힌다 · foreign 은 true', () {
      final unk = _u(nationalityStatus: 'unknown', signupSource: 'kakao_v1', authProviders: ['kakao']);
      expect(unk.isForeign, isFalse);
      expect(unk.isNationalityUnconfirmed, isTrue);
      expect(_u(nationalityStatus: 'foreign').isForeign, isTrue);
      expect(_u(nationalityStatus: 'domestic').isNationalityUnconfirmed, isFalse);
      // 옛 계정(필드 없음) 결과 불변
      expect(_u().isForeign, isFalse);
      expect(_u(fingerprint: 'fp').isForeign, isTrue);
      expect(_u().isProviderAccount, isFalse);
    });
    test('AKA-U2 fromMap 이 서버 필드를 읽고 형식이 다르면 없는 것으로 · copyWith 보존 · toMap 미출력', () {
      final m = UserModel.fromMap({
        'username': '', 'email': '', 'name': 'n', 'role': 'USER',
        'nationalityStatus': 'unknown', 'authProviders': ['kakao', 3], 'signupSource': 'kakao_v1',
      }, 'u');
      expect(m.isNationalityUnconfirmed, isTrue);
      expect(m.authProviders, ['kakao']);
      expect(m.copyWith(name: 'x').isNationalityUnconfirmed, isTrue);
      expect(m.copyWith(name: 'x').authProviders, ['kakao']);
      final bad = UserModel.fromMap({'username': 'a', 'email': '', 'name': 'n', 'role': 'USER',
        'nationalityStatus': 5, 'authProviders': 'kakao'}, 'u');
      expect(bad.nationalityStatus, isNull);
      expect(bad.authProviders, isEmpty);
      final map = m.toMap();
      expect(map.containsKey('nationalityStatus'), isFalse);
      expect(map.containsKey('authProviders'), isFalse);
      expect(map.containsKey('signupSource'), isFalse);
    });
    test('AKA-U3 성별 미상 문자열은 여성 코드로 만들지 않는다(identity_identifier:105 폴백 차단)', () {
      final b = DateTime(1990, 3, 4);
      expect(expectedIdentifierFrom(birthDate: b, gender: 'unknown', isForeign: false).prefix, isNull);
      expect(expectedIdentifierFrom(birthDate: b, gender: 'F', isForeign: false).prefix, isNull);
      expect(expectedIdentifierFrom(birthDate: b, gender: '여성', isForeign: false).prefix, '900304-2');
      expect(expectedIdentifierFrom(birthDate: b, gender: '남성', isForeign: true).prefix, '900304-5');
      // KG 가 성별을 안 주면(키 없음) 기대값 없음 — 기존 guard
      expect(expectedIdentifierForUser(_u(gender: null, nationalityStatus: 'unknown')).prefix, isNull);
    });
    test('AKA-U4 홈 PASS 회복 배너: 새 계정은 passVerifiedAt 이 빠져도 옛 재인증으로 보내지 않는다', () {
      expect(_u(signupSource: 'kakao_v1', authProviders: ['kakao']).needsPassAuthRecovery, isFalse);
      expect(_u(nationalityStatus: 'unknown', signupSource: 'kakao_v1', passVerifiedAt: DateTime(2026)).needsPassAuthRecovery,
          isFalse);
      // 옛 아이디 계정은 그대로
      expect(_u().needsPassAuthRecovery, isTrue);
    });
    test('AKA-U5 외국인등록번호 앱 1차 형식(서버가 다시 본다)', () {
      expect(foreignIdFormatProblem('900304512345'), isNotNull);
      expect(foreignIdFormatProblem('9003041234567'), isNotNull); // 7번째 1 → 등록증 아님
      expect(foreignIdFormatProblem('9003045234567'), isNull);
    });
  });

  group('AKA-S 소스 계약', () {
    String src(String p) => File(p).readAsStringSync();
    test('AKA-S1 시작 화면이 AuthWrapper 의 로그아웃 상태 화면 · 옛 가입 입구(RegisterScreen) 0', () {
      final main = src('lib/main.dart');
      expect(main, contains('return const AuthStartScreen();'));
      expect(main.contains('return const LoginScreen();'), isFalse);
      final login = src('lib/screens/auth/login_screen.dart');
      expect(login.contains('RegisterScreen()'), isFalse);
      expect(login.contains("import 'register_screen.dart'"), isFalse);
      final start = src('lib/screens/auth/auth_start_screen.dart');
      expect(start.contains('RegisterScreen'), isFalse);
      expect(start.contains('ForeignRegisterScreen'), isFalse);
    });
    test('AKA-S2 서류 입구: 국적 미확정이면 종류 선택이 OCR(pickAndVerifyIdCard)보다 먼저', () {
      final d = src('lib/screens/common/document_management_screen.dart');
      final fn = d.substring(d.indexOf('Future<void> _uploadIdCard() async {'));
      final a = fn.indexOf('user.isNationalityUnconfirmed');
      final b = fn.indexOf('showIdDocumentKindSheet');
      final c = fn.indexOf('DocumentUploadHelper.pickAndVerifyIdCard');
      expect(a, greaterThan(0));
      expect(b, greaterThan(a));
      expect(c, greaterThan(b));
      expect(fn.indexOf("if (documentKind != null) 'documentKind': documentKind"), greaterThan(c));
      // 외국인등록증은 옛 가입 함수가 아니라 새 writer
      final f = src('lib/screens/common/foreign_id_document_screen.dart');
      expect(f, contains("'callableRegisterForeignIdDocument'"));
      final fCode = f.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
      expect(fCode.contains('callableFinalizeForeignIdentity'), isFalse);
    });
    test('AKA-S3 카카오 계정 탈퇴를 비밀번호 재인증으로 흉내 내지 않는다', () {
      final a = src('lib/services/auth_service.dart');
      final fn = a.substring(a.indexOf('Future<String?> deleteAccountWithPassword'));
      expect(fn.indexOf('if (user.email == null)'), lessThan(fn.indexOf('EmailAuthProvider.credential')));
    });
    test('AKA-S4 카카오 SDK 정확 고정 · manifest scheme 은 문자열 리소스(자리표시) · 금지 파일 무관', () {
      final pub = src('pubspec.yaml');
      expect(RegExp(r'^\s+kakao_flutter_sdk_user: 1\.10\.0\s*$', multiLine: true).hasMatch(pub), isTrue);
      final mf = src('android/app/src/main/AndroidManifest.xml');
      expect(mf, contains('com.kakao.sdk.flutter.AuthCodeCustomTabsActivity'));
      expect(mf, contains('android:scheme="@string/kakao_scheme"'));
      // [판정281 차수 · 키 설정 반영] 네이티브 앱 키가 두 설정 위치에 같은 값으로 있는지만 본다 — 값은 출력하지 않는다
      //   (실패 메시지에도 bool 만 나오게 isTrue 로 단언).
      final cfg = src('android/app/src/main/res/values/kakao_config.xml');
      final scheme = RegExp(r'name="kakao_scheme"[^>]*>([^<]+)<').firstMatch(cfg)?.group(1) ?? '';
      final dartKey = RegExp(r"kKakaoNativeAppKey = '([^']*)'")
              .firstMatch(src('lib/config/kakao_config.dart'))
              ?.group(1) ??
          '';
      expect(dartKey.isNotEmpty, isTrue, reason: 'Dart 쪽 키 자리 비어 있음');
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(dartKey), isTrue, reason: '네이티브 앱 키 형식(32 hex) 아님');
      expect(scheme == 'kakao$dartKey', isTrue, reason: 'manifest scheme 과 Dart 키가 다르다');
      expect(cfg.contains('pending'), isFalse, reason: '자리표시가 남았다');
      expect(src('lib/services/auth/kakao_auth_service.dart'),
          contains("String.fromEnvironment('KAKAO_NATIVE_APP_KEY', defaultValue: kKakaoNativeAppKey)"));
    });
    test('AKA-S5 UID 전환 = 기존 signOut 전체 경로 뒤 새 토큰', () {
      final up = src('lib/providers/user_provider.dart');
      final fn = up.substring(up.indexOf('Future<bool> switchAccountWithCustomToken'));
      expect(fn.indexOf('await signOut();'), lessThan(fn.indexOf('signInWithCustomToken(customToken)')));
      // 자동 복원 판정
      expect(up, contains('LoginGate.fromUser(_currentUser!)'));
    });
  });
}

/// 부르면 실패하는 서버 대역(판독만 보는 시험용).
class _NoApi implements SignupApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('서버 호출 0 이어야 한다');
}
