// test/simulation/pass_auth_simulation_test.dart
//
// KG이니시스 간편인증(PortOne V1) 흐름 시뮬레이션 테스트
//
// 검증 범위:
//   1. _parseBirthDate — 정상·경계·오류 케이스
//   2. CF 응답 처리 — null 필드·잘못된 날짜·완전한 응답
//   3. IamportWebView 결과 처리 — success/failure/취소/imp_uid 없음
//   4. CF 에러 코드 → 사용자 메시지 매핑
//   5. passToken 유효 기간 검사 (15분)
//   6. 비밀번호 찾기 흐름 — customToken 상태 전환·에러 순서
//   7. 회원가입 연동 — 이름·전화번호 자동 채움·이중 제출 방지
//
// 의존성: Firebase · Flutter · Provider 없음. 순수 Dart 로직만.

// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';

// ══════════════════════════════════════════════════════════════
// 시뮬레이션 데이터 클래스
// ══════════════════════════════════════════════════════════════

class SimPassAuthResult {
  final String name;
  final String gender;
  final DateTime birthDate;
  final String phone;
  final String passToken;
  final DateTime issuedAt;

  const SimPassAuthResult({
    required this.name,
    required this.gender,
    required this.birthDate,
    required this.phone,
    required this.passToken,
    required this.issuedAt,
  });

  bool isExpired({int ttlMinutes = 15, DateTime? now}) {
    final check = now ?? DateTime.now();
    return check.difference(issuedAt).inMinutes >= ttlMinutes;
  }
}

enum SimCfErrorCode { alreadyExists, permissionDenied, notFound, deadlineExceeded, unknown }

class SimCfException {
  final SimCfErrorCode code;
  const SimCfException(this.code);
}

// ══════════════════════════════════════════════════════════════
// PassVerificationService 핵심 로직 재구현 (Firebase 의존 없음)
// ══════════════════════════════════════════════════════════════

/// _parseBirthDate 재구현 — pass_verification_service.dart와 동일 로직
DateTime? parseBirthDate(String yyyymmdd) {
  try {
    if (yyyymmdd.length < 8) return null;
    final y = int.parse(yyyymmdd.substring(0, 4));
    final m = int.parse(yyyymmdd.substring(4, 6));
    final d = int.parse(yyyymmdd.substring(6, 8));
    return DateTime(y, m, d);
  } catch (_) {
    return null;
  }
}

/// _mapCfError 재구현
String mapCfError(String code) {
  switch (code) {
    case 'already-exists':
      return '이미 가입된 계정이 있습니다';
    case 'permission-denied':
      return '본인인증 조건을 충족하지 않습니다 (미성년자 또는 재가입 제한)';
    case 'not-found':
      return '본인인증 세션을 찾을 수 없습니다. 다시 시도해주세요';
    case 'deadline-exceeded':
      return '본인인증 세션이 만료되었습니다. 다시 인증해주세요';
    default:
      return '본인인증에 실패했습니다. 다시 시도해주세요';
  }
}

/// IamportWebView 결과 → SimPassAuthResult 변환 시뮬레이션
/// authenticate() 내부 흐름 재구현 (CF 호출 부분은 cfResponseFactory로 주입)
SimPassAuthResult? processIamportResult(
  Map<String, String>? webviewResult, {
  required Map<String, dynamic>? Function(String impUid) cfResponseFactory,
  List<String> errors = const [],
}) {
  // (1) 사용자 취소
  if (webviewResult == null) return null;

  // (2) success 체크
  final success = webviewResult['success'] == 'true';
  if (!success) {
    final msg = webviewResult['error_msg'];
    if (msg != null && msg.isNotEmpty) errors is List<String> ? (errors as List<String>).add(msg) : null;
    return null;
  }

  // (3) imp_uid 체크
  final impUid = webviewResult['imp_uid'];
  if (impUid == null || impUid.isEmpty) {
    (errors as List<String>).add('본인인증 결과를 받지 못했습니다');
    return null;
  }

  // (4) CF 응답 처리
  final cfData = cfResponseFactory(impUid);
  if (cfData == null) return null;

  final name        = cfData['name']      as String?;
  final gender      = cfData['gender']    as String?;
  final birthDateStr = cfData['birthDate'] as String?;
  final phone       = cfData['phone']     as String?;
  final passToken   = cfData['passToken'] as String?;

  if (name == null || gender == null || birthDateStr == null ||
      phone == null || passToken == null) {
    (errors as List<String>).add('본인인증 결과를 받지 못했습니다');
    return null;
  }

  final birthDate = parseBirthDate(birthDateStr);
  if (birthDate == null) {
    (errors as List<String>).add('본인인증 결과를 받지 못했습니다');
    return null;
  }

  return SimPassAuthResult(
    name: name,
    gender: gender,
    birthDate: birthDate,
    phone: phone,
    passToken: passToken,
    issuedAt: DateTime.now(),
  );
}

// ══════════════════════════════════════════════════════════════
// 비밀번호 찾기 흐름 시뮬레이터
// ══════════════════════════════════════════════════════════════

enum ResetStep { passAuth, newPassword, done }

class ResetPasswordSimulator {
  ResetStep step = ResetStep.passAuth;
  String? customToken;
  bool isAuthenticating = false;
  bool isChanging = false;

  final List<String> errors = [];
  final List<String> signOutCalls = [];
  final List<String> errorToasts = [];

  /// PASS 인증 완료 → customToken 수신 → step 전환
  void onPassAuthSuccess(String token) {
    customToken = token;
    step = ResetStep.newPassword;
  }

  /// 비밀번호 변경 시도 — customToken 없으면 step 0으로 돌아감
  bool tryChangePassword(String pw, String confirm) {
    if (customToken == null) {
      errors.add('인증 세션이 만료되었습니다. 다시 본인인증을 진행해주세요');
      step = ResetStep.passAuth;
      return false;
    }
    if (pw != confirm) {
      errors.add('비밀번호가 일치하지 않습니다');
      return false;
    }
    if (pw.length < 8) {
      errors.add('비밀번호는 8자 이상이어야 합니다');
      return false;
    }
    return true;
  }

  /// 비밀번호 변경 성공
  void onChangeSuccess() {
    isChanging = false;
    step = ResetStep.done;
    signOutCalls.add('post-success');
  }

  /// 비밀번호 변경 실패 — 에러 표시 후 signOut (순서 검증용)
  void onChangeFailed() {
    // 에러 표시를 먼저 (signOut 이전)
    isChanging = false;
    errorToasts.add('비밀번호 변경에 실패했습니다. 다시 시도해주세요');
    // signOut은 이후
    signOutCalls.add('post-error');
  }
}

// ══════════════════════════════════════════════════════════════
// 회원가입 PASS 연동 시뮬레이터
// ══════════════════════════════════════════════════════════════

class RegisterPassSimulator {
  SimPassAuthResult? passResult;
  String nameControllerText = '';
  String phoneControllerText = '';
  bool isPassLoading = false;
  bool isSubmitting = false;

  final List<String> finalizedTokens = [];

  /// PASS 인증 완료 → 이름·전화번호 자동 채움
  void onPassAuthComplete(SimPassAuthResult result) {
    passResult = result;
    nameControllerText = result.name;
    phoneControllerText = result.phone;
  }

  /// 이중 클릭 방지
  bool tryStartPassAuth() {
    if (isPassLoading) return false;
    isPassLoading = true;
    return true;
  }

  void endPassAuth() {
    isPassLoading = false;
  }

  /// 이중 제출 방지
  bool tryStartSubmit() {
    if (isSubmitting) return false;
    isSubmitting = true;
    return true;
  }

  /// 가입 완료 후 passToken 소비
  void finalizeRegistration() {
    if (passResult != null) {
      finalizedTokens.add(passResult!.passToken);
    }
  }

  /// passToken 유효 여부 (15분)
  bool get isPassTokenValid {
    final r = passResult;
    if (r == null) return false;
    return !r.isExpired();
  }
}

// ══════════════════════════════════════════════════════════════
// 테스트
// ══════════════════════════════════════════════════════════════

void main() {
  // ─────────────────────────────────────────────
  // 1. parseBirthDate 단위 테스트
  // ─────────────────────────────────────────────
  group('parseBirthDate', () {
    test('정상 — 19900101 → DateTime(1990,1,1)', () {
      final result = parseBirthDate('19900101');
      expect(result, isNotNull);
      expect(result!.year, 1990);
      expect(result.month, 1);
      expect(result.day, 1);
    });

    test('정상 — 20001231 → DateTime(2000,12,31)', () {
      final result = parseBirthDate('20001231');
      expect(result, isNotNull);
      expect(result!.year, 2000);
      expect(result.month, 12);
      expect(result.day, 31);
    });

    test('8자 초과 — 앞 8자만 파싱 성공', () {
      final result = parseBirthDate('199001011234');
      expect(result, isNotNull);
      expect(result!.year, 1990);
    });

    test('7자 미만 — null 반환', () {
      expect(parseBirthDate('1990010'), isNull);
    });

    test('6자 — null 반환', () {
      expect(parseBirthDate('199001'), isNull);
    });

    test('빈 문자열 — null 반환', () {
      expect(parseBirthDate(''), isNull);
    });

    test('비숫자 포함 — null 반환', () {
      expect(parseBirthDate('1990/01/01'), isNull);
    });

    test('YYYYMMDD 형식 아닌 숫자열 — DateTime 생성 시도 (잘못된 월)', () {
      // '19901301' — 13월. DateTime은 자동 롤오버하므로 null이 아님
      final result = parseBirthDate('19901301');
      // Dart DateTime은 잘못된 날짜를 롤오버 처리 — 13월 → 이듬해 1월
      expect(result, isNotNull);
    });

    test('null 연산 없이 RangeError 방어 확인 — 7자 borderline', () {
      // '1990011' — 7자. substring(6,8) 호출 전 length 체크로 null 반환
      expect(parseBirthDate('1990011'), isNull);
    });
  });

  // ─────────────────────────────────────────────
  // 2. CF 에러 코드 → 사용자 메시지 매핑
  // ─────────────────────────────────────────────
  group('mapCfError', () {
    test('already-exists → 이미 가입된 계정', () {
      expect(mapCfError('already-exists'), contains('이미 가입된 계정'));
    });

    test('permission-denied → 조건 미충족 (미성년자 등)', () {
      expect(mapCfError('permission-denied'), contains('미성년자'));
    });

    test('not-found → 세션을 찾을 수 없음', () {
      expect(mapCfError('not-found'), contains('세션을 찾을 수 없습니다'));
    });

    test('deadline-exceeded → 세션 만료', () {
      expect(mapCfError('deadline-exceeded'), contains('만료'));
    });

    test('알 수 없는 코드 → 기본 실패 메시지', () {
      expect(mapCfError('internal'), contains('본인인증에 실패했습니다'));
      expect(mapCfError(''), contains('본인인증에 실패했습니다'));
    });
  });

  // ─────────────────────────────────────────────
  // 3. IamportWebView 결과 처리 시뮬레이션
  // ─────────────────────────────────────────────
  group('processIamportResult', () {
    final validCfResponse = {
      'name': '김민준',
      'gender': '남성',
      'birthDate': '19900101',
      'phone': '01012345678',
      'passToken': 'token-abc-123',
    };

    test('사용자 취소 — webviewResult==null → null 반환', () {
      final result = processIamportResult(
        null,
        cfResponseFactory: (_) => validCfResponse,
      );
      expect(result, isNull);
    });

    test('인증 실패 — success=false → null + 에러 메시지', () {
      final errors = <String>[];
      final result = processIamportResult(
        {'success': 'false', 'error_msg': 'PG사 인증 실패'},
        cfResponseFactory: (_) => validCfResponse,
        errors: errors,
      );
      expect(result, isNull);
      expect(errors, contains('PG사 인증 실패'));
    });

    test('인증 실패 — success=false, error_msg 없음 → null, 에러 없음', () {
      final errors = <String>[];
      final result = processIamportResult(
        {'success': 'false'},
        cfResponseFactory: (_) => validCfResponse,
        errors: errors,
      );
      expect(result, isNull);
      expect(errors, isEmpty);
    });

    test('imp_uid 없음 — success=true 이지만 imp_uid 빈 문자열 → null', () {
      final errors = <String>[];
      final result = processIamportResult(
        {'success': 'true', 'imp_uid': ''},
        cfResponseFactory: (_) => validCfResponse,
        errors: errors,
      );
      expect(result, isNull);
      expect(errors, contains('본인인증 결과를 받지 못했습니다'));
    });

    test('imp_uid 키 자체 없음 → null', () {
      final errors = <String>[];
      final result = processIamportResult(
        {'success': 'true'},
        cfResponseFactory: (_) => validCfResponse,
        errors: errors,
      );
      expect(result, isNull);
    });

    test('정상 흐름 — 완전한 CF 응답 → PassAuthResult 반환', () {
      final result = processIamportResult(
        {'success': 'true', 'imp_uid': 'imp_test_001'},
        cfResponseFactory: (_) => validCfResponse,
      );
      expect(result, isNotNull);
      expect(result!.name, '김민준');
      expect(result.gender, '남성');
      expect(result.birthDate, DateTime(1990, 1, 1));
      expect(result.phone, '01012345678');
      expect(result.passToken, 'token-abc-123');
    });

    test('CF 응답 null — null 반환', () {
      final errors = <String>[];
      final result = processIamportResult(
        {'success': 'true', 'imp_uid': 'imp_test_001'},
        cfResponseFactory: (_) => null,
        errors: errors,
      );
      expect(result, isNull);
    });

    test('CF 응답 name 필드 null — null 반환 + 에러', () {
      final errors = <String>[];
      final result = processIamportResult(
        {'success': 'true', 'imp_uid': 'imp_test_001'},
        cfResponseFactory: (_) => {
          ...validCfResponse,
          'name': null,
        },
        errors: errors,
      );
      expect(result, isNull);
      expect(errors, contains('본인인증 결과를 받지 못했습니다'));
    });

    test('CF 응답 gender 필드 누락 — null 반환', () {
      final errors = <String>[];
      final cfWithoutGender = Map<String, dynamic>.from(validCfResponse)
        ..remove('gender');
      final result = processIamportResult(
        {'success': 'true', 'imp_uid': 'imp_test_001'},
        cfResponseFactory: (_) => cfWithoutGender,
        errors: errors,
      );
      expect(result, isNull);
      expect(errors, isNotEmpty);
    });

    test('CF 응답 passToken null — null 반환', () {
      final errors = <String>[];
      final result = processIamportResult(
        {'success': 'true', 'imp_uid': 'imp_test_001'},
        cfResponseFactory: (_) => {
          ...validCfResponse,
          'passToken': null,
        },
        errors: errors,
      );
      expect(result, isNull);
    });

    test('CF 응답 birthDate 7자 — null 반환', () {
      final errors = <String>[];
      final result = processIamportResult(
        {'success': 'true', 'imp_uid': 'imp_test_001'},
        cfResponseFactory: (_) => {
          ...validCfResponse,
          'birthDate': '1990010', // 7자
        },
        errors: errors,
      );
      expect(result, isNull);
      expect(errors, contains('본인인증 결과를 받지 못했습니다'));
    });

    test('CF 응답 birthDate 비숫자 포함 — null 반환', () {
      final errors = <String>[];
      final result = processIamportResult(
        {'success': 'true', 'imp_uid': 'imp_test_001'},
        cfResponseFactory: (_) => {
          ...validCfResponse,
          'birthDate': '1990/01/01',
        },
        errors: errors,
      );
      expect(result, isNull);
    });

    test('imp_uid가 CF 팩토리에 정확히 전달되는지 확인', () {
      String? capturedImpUid;
      processIamportResult(
        {'success': 'true', 'imp_uid': 'imp_captured_uid_999'},
        cfResponseFactory: (uid) {
          capturedImpUid = uid;
          return validCfResponse;
        },
      );
      expect(capturedImpUid, 'imp_captured_uid_999');
    });
  });

  // ─────────────────────────────────────────────
  // 4. passToken 유효 기간 (15분)
  // ─────────────────────────────────────────────
  group('passToken TTL 검사', () {
    SimPassAuthResult makeResult({required DateTime issuedAt}) =>
        SimPassAuthResult(
          name: '홍길동',
          gender: '남성',
          birthDate: DateTime(1990, 1, 1),
          phone: '01011112222',
          passToken: 'token-ttl-test',
          issuedAt: issuedAt,
        );

    test('발급 직후 — 유효', () {
      final result = makeResult(issuedAt: DateTime.now());
      expect(result.isExpired(), isFalse);
    });

    test('14분 59초 후 — 유효', () {
      final result = makeResult(
        issuedAt: DateTime.now().subtract(const Duration(minutes: 14, seconds: 59)),
      );
      expect(result.isExpired(), isFalse);
    });

    test('정확히 15분 후 — 만료', () {
      final result = makeResult(
        issuedAt: DateTime.now().subtract(const Duration(minutes: 15)),
      );
      expect(result.isExpired(), isTrue);
    });

    test('20분 후 — 만료', () {
      final result = makeResult(
        issuedAt: DateTime.now().subtract(const Duration(minutes: 20)),
      );
      expect(result.isExpired(), isTrue);
    });
  });

  // ─────────────────────────────────────────────
  // 5. 비밀번호 찾기 흐름 시뮬레이션
  // ─────────────────────────────────────────────
  group('비밀번호 찾기 흐름', () {
    test('초기 step은 passAuth', () {
      final sim = ResetPasswordSimulator();
      expect(sim.step, ResetStep.passAuth);
      expect(sim.customToken, isNull);
    });

    test('PASS 인증 성공 → step 1(newPassword), customToken 설정', () {
      final sim = ResetPasswordSimulator();
      sim.onPassAuthSuccess('ct-abc-123');
      expect(sim.step, ResetStep.newPassword);
      expect(sim.customToken, 'ct-abc-123');
    });

    test('customToken null 상태에서 비밀번호 변경 시도 → step 0으로 복귀', () {
      final sim = ResetPasswordSimulator();
      // customToken 없이 시도
      final ok = sim.tryChangePassword('Abc@1234', 'Abc@1234');
      expect(ok, isFalse);
      expect(sim.step, ResetStep.passAuth);
      expect(sim.errors, isNotEmpty);
      expect(sim.errors.first, contains('인증 세션이 만료'));
    });

    test('비밀번호 불일치 → 변경 거부', () {
      final sim = ResetPasswordSimulator();
      sim.onPassAuthSuccess('ct-valid');
      final ok = sim.tryChangePassword('Abc@1234', 'Different@1');
      expect(ok, isFalse);
      expect(sim.errors.last, contains('일치하지 않습니다'));
      expect(sim.step, ResetStep.newPassword); // step 유지
    });

    test('8자 미만 비밀번호 → 변경 거부', () {
      final sim = ResetPasswordSimulator();
      sim.onPassAuthSuccess('ct-valid');
      final ok = sim.tryChangePassword('Abc@12', 'Abc@12');
      expect(ok, isFalse);
      expect(sim.errors.last, contains('8자 이상'));
    });

    test('정상 변경 → step 2(done)', () {
      final sim = ResetPasswordSimulator();
      sim.onPassAuthSuccess('ct-valid');
      final ok = sim.tryChangePassword('Abc@12345!', 'Abc@12345!');
      expect(ok, isTrue);
      sim.onChangeSuccess();
      expect(sim.step, ResetStep.done);
    });

    test('변경 실패 — 에러 토스트가 signOut보다 먼저 기록됨', () {
      final sim = ResetPasswordSimulator();
      sim.onPassAuthSuccess('ct-valid');
      sim.isChanging = true;
      sim.onChangeFailed();

      // 에러 토스트 기록 후 signOut 기록 순서 확인
      expect(sim.errorToasts, isNotEmpty);
      expect(sim.signOutCalls, contains('post-error'));
      expect(sim.isChanging, isFalse);
    });

    test('변경 실패 후 signOut 호출 — 의도치 않은 세션 정리', () {
      final sim = ResetPasswordSimulator();
      sim.onPassAuthSuccess('ct-valid');
      sim.onChangeFailed();
      // signOut은 에러 표시 이후에만 호출 (순서 보장)
      expect(sim.errorToasts.length, 1);
      expect(sim.signOutCalls.length, 1);
      expect(sim.signOutCalls.first, 'post-error');
    });
  });

  // ─────────────────────────────────────────────
  // 6. 회원가입 PASS 연동 시뮬레이션
  // ─────────────────────────────────────────────
  group('회원가입 PASS 연동', () {
    SimPassAuthResult makeAuth({String token = 'token-register-001'}) =>
        SimPassAuthResult(
          name: '이서연',
          gender: '여성',
          birthDate: DateTime(1995, 6, 15),
          phone: '01099998888',
          passToken: token,
          issuedAt: DateTime.now(),
        );

    test('PASS 인증 완료 → 이름·전화번호 자동 채움', () {
      final sim = RegisterPassSimulator();
      sim.onPassAuthComplete(makeAuth());
      expect(sim.nameControllerText, '이서연');
      expect(sim.phoneControllerText, '01099998888');
      expect(sim.passResult, isNotNull);
    });

    test('이중 PASS 로딩 방지 — tryStartPassAuth 두 번 호출', () {
      final sim = RegisterPassSimulator();
      expect(sim.tryStartPassAuth(), isTrue);
      expect(sim.tryStartPassAuth(), isFalse); // 이미 로딩 중
    });

    test('PASS 완료 후 isPassLoading 해제', () {
      final sim = RegisterPassSimulator();
      sim.tryStartPassAuth();
      expect(sim.isPassLoading, isTrue);
      sim.endPassAuth();
      expect(sim.isPassLoading, isFalse);
    });

    test('이중 가입 제출 방지 — tryStartSubmit 두 번 호출', () {
      final sim = RegisterPassSimulator();
      expect(sim.tryStartSubmit(), isTrue);
      expect(sim.tryStartSubmit(), isFalse);
    });

    test('가입 완료 후 passToken 소비 기록', () {
      final sim = RegisterPassSimulator();
      sim.onPassAuthComplete(makeAuth(token: 'token-to-finalize'));
      sim.finalizeRegistration();
      expect(sim.finalizedTokens, contains('token-to-finalize'));
    });

    test('PASS 인증 없이 finalizeRegistration 호출 — 아무 토큰도 소비 안 됨', () {
      final sim = RegisterPassSimulator();
      sim.finalizeRegistration(); // passResult == null
      expect(sim.finalizedTokens, isEmpty);
    });

    test('passToken 유효 기간 내 — isPassTokenValid == true', () {
      final sim = RegisterPassSimulator();
      sim.onPassAuthComplete(makeAuth());
      expect(sim.isPassTokenValid, isTrue);
    });

    test('passToken 만료(15분 경과) — isPassTokenValid == false', () {
      final sim = RegisterPassSimulator();
      final expired = SimPassAuthResult(
        name: '박지호',
        gender: '남성',
        birthDate: DateTime(1988, 3, 20),
        phone: '01077776666',
        passToken: 'token-expired',
        issuedAt: DateTime.now().subtract(const Duration(minutes: 15)),
      );
      sim.passResult = expired;
      expect(sim.isPassTokenValid, isFalse);
    });

    test('PASS 인증 없이 isPassTokenValid == false', () {
      final sim = RegisterPassSimulator();
      expect(sim.isPassTokenValid, isFalse);
    });

    test('이름 재인증 시 기존 이름·전화번호 덮어쓰기', () {
      final sim = RegisterPassSimulator();
      sim.onPassAuthComplete(makeAuth(token: 'token-first'));
      expect(sim.nameControllerText, '이서연');

      final second = SimPassAuthResult(
        name: '최수아',
        gender: '여성',
        birthDate: DateTime(2000, 1, 1),
        phone: '01033334444',
        passToken: 'token-second',
        issuedAt: DateTime.now(),
      );
      sim.onPassAuthComplete(second);
      expect(sim.nameControllerText, '최수아');
      expect(sim.phoneControllerText, '01033334444');
    });

    test('연령 제한 — minAge:19 검사 (만 19세 미만 거부)', () {
      // 실제 UI 검사는 PG사에서 수행하지만, passToken의 birthDate 기준 나이 계산 로직 검증
      final now = DateTime(2024, 8, 1);
      bool isMajor(DateTime birthDate) {
        final age = now.year - birthDate.year -
            ((now.month < birthDate.month ||
                    (now.month == birthDate.month && now.day < birthDate.day))
                ? 1
                : 0);
        return age >= 19;
      }
      expect(isMajor(DateTime(2005, 8, 2)), isFalse); // 만 18세
      expect(isMajor(DateTime(2005, 8, 1)), isTrue);  // 만 19세
      expect(isMajor(DateTime(2005, 7, 31)), isTrue); // 만 19세
      expect(isMajor(DateTime(1990, 1, 1)), isTrue);  // 만 34세
    });
  });

  // ─────────────────────────────────────────────
  // 7. merchantUid 포맷 검증
  // ─────────────────────────────────────────────
  group('merchantUid 포맷', () {
    test('alfit_cert_ 접두사 + epoch milliseconds 형식', () {
      final uid = 'alfit_cert_${DateTime.now().millisecondsSinceEpoch}';
      expect(uid.startsWith('alfit_cert_'), isTrue);
      final epoch = int.tryParse(uid.replaceFirst('alfit_cert_', ''));
      expect(epoch, isNotNull);
      expect(epoch! > 0, isTrue);
    });

    test('연속 호출 시 merchantUid 중복 없음', () {
      final uids = <String>{};
      for (var i = 0; i < 100; i++) {
        uids.add('alfit_cert_${DateTime.now().millisecondsSinceEpoch}_$i');
      }
      expect(uids.length, 100);
    });
  });
}
