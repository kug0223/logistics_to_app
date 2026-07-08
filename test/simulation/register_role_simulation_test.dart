// test/simulation/register_role_simulation_test.dart
//
// register_screen.dart의 회원 유형(USER vs BUSINESS_ADMIN) 분기 처리 시뮬레이션
//
// 테스트 대상 로직:
//   1. 사업자등록번호 checksum 검증 (_isValidBusinessNumber)
//   2. USER vs BUSINESS_ADMIN signUp 파라미터 구성
//   3. _handleRoleSelection 유효성 검사 분기
//   4. 사업장 등록 다이얼로그 분기 (_showBusinessRegistrationDialog)
//   5. _isSubmitting 가드 (중복 실행 방지)
//   6. 통합 시나리오
//
// Flutter 의존성 없이 순수 Dart 로직만 검증한다.

// flutter_test를 사용하나 Widget/Flutter API는 전혀 사용하지 않으며,
// 모든 테스트 대상 로직은 순수 Dart 함수로 구현되어 있다.
import 'package:flutter_test/flutter_test.dart';

// ══════════════════════════════════════════════════════════════════════════════
// 테스트 대상 로직 — register_screen.dart에서 추출한 순수 함수
// ══════════════════════════════════════════════════════════════════════════════

/// UserRole enum (user_model.dart 원본과 동일)
enum UserRole { SUPER_ADMIN, BUSINESS_ADMIN, USER }

// ─────────────────────────────────────────────────────────────────────────────
// 1. 사업자등록번호 checksum 검증
//    register_screen.dart: _isValidBusinessNumber()
// ─────────────────────────────────────────────────────────────────────────────
bool isValidBusinessNumber(String num) {
  if (num.length != 10) return false;
  try {
    final d = num.split('').map(int.parse).toList();
    const w = [1, 3, 7, 1, 3, 7, 1, 3, 5];
    int sum = 0;
    for (int i = 0; i < 9; i++) {
      sum += d[i] * w[i];
    }
    sum += (d[8] * 5) ~/ 10;
    final checkDigit = (10 - (sum % 10)) % 10;
    return checkDigit == d[9];
  } catch (_) {
    return false;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. signUp 파라미터 구성 로직
//    register_screen.dart: _registerUser() 내 business 필드 결정
// ─────────────────────────────────────────────────────────────────────────────

/// businessNumber 파라미터 결정
/// BUSINESS_ADMIN이고 대시 제거 후 비어있지 않으면 반환, 그 외 null
String? resolveBusinessNumber({
  required UserRole role,
  required String controllerText,
}) {
  if (role == UserRole.BUSINESS_ADMIN &&
      controllerText.replaceAll('-', '').isNotEmpty) {
    return controllerText.replaceAll('-', '');
  }
  return null;
}

/// businessName 파라미터 결정
/// BUSINESS_ADMIN이고 trim 후 비어있지 않으면 반환, 그 외 null
String? resolveBusinessName({
  required UserRole role,
  required String controllerText,
}) {
  if (role == UserRole.BUSINESS_ADMIN && controllerText.trim().isNotEmpty) {
    return controllerText.trim();
  }
  return null;
}

/// ceoName 파라미터 결정
/// BUSINESS_ADMIN이고 trim 후 비어있지 않으면 반환, 그 외 null
String? resolveCeoName({
  required UserRole role,
  required String controllerText,
}) {
  if (role == UserRole.BUSINESS_ADMIN && controllerText.trim().isNotEmpty) {
    return controllerText.trim();
  }
  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. _handleRoleSelection 유효성 검사 결과
// ─────────────────────────────────────────────────────────────────────────────
enum HandleRoleResult { pass, invalidLength, invalidChecksum, alreadySubmitting }

HandleRoleResult validateForRoleSelection({
  required UserRole role,
  required String businessNumberRaw,
  required bool isSubmitting,
}) {
  if (isSubmitting) return HandleRoleResult.alreadySubmitting;
  if (role == UserRole.BUSINESS_ADMIN) {
    final bizNum = businessNumberRaw.replaceAll('-', '');
    if (bizNum.isNotEmpty) {
      if (bizNum.length != 10) return HandleRoleResult.invalidLength;
      if (!isValidBusinessNumber(bizNum)) return HandleRoleResult.invalidChecksum;
    }
  }
  return HandleRoleResult.pass;
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. 사업장 등록 다이얼로그 분기
//    _showBusinessRegistrationDialog 로직
// ─────────────────────────────────────────────────────────────────────────────
enum BusinessDialogType { warningNoLicense, selectRegistration }
enum BusinessDialogAction { registerUser, registerUserAndNavigate, cancel }

/// 라이선스 유무에 따라 표시할 다이얼로그 종류 결정
BusinessDialogType determineBusinessDialog({required bool hasLicense}) {
  return hasLicense
      ? BusinessDialogType.selectRegistration
      : BusinessDialogType.warningNoLicense;
}

/// 경고 다이얼로그(라이선스 없음)에서 사용자 선택 처리
/// chooseLater=true → '나중에 등록' → registerUser
/// chooseLater=false → '돌아가기' → cancel
BusinessDialogAction handleWarningDialog({required bool chooseLater}) {
  return chooseLater ? BusinessDialogAction.registerUser : BusinessDialogAction.cancel;
}

/// 선택 다이얼로그(라이선스 있음)에서 사용자 선택 처리
/// chooseNow=true → '지금 등록' → registerUserAndNavigate
/// chooseNow=false → '나중에' → registerUser
BusinessDialogAction handleSelectDialog({required bool chooseNow}) {
  return chooseNow
      ? BusinessDialogAction.registerUserAndNavigate
      : BusinessDialogAction.registerUser;
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. _isSubmitting 가드 시뮬레이터
// ─────────────────────────────────────────────────────────────────────────────
class SubmitGuardSimulator {
  bool isSubmitting = false;
  int registerCallCount = 0;
  bool finallyRan = false;

  /// _handleRoleSelection → _registerUser 흐름 시뮬레이션
  void handleSubmit(UserRole role) {
    if (isSubmitting) return;
    isSubmitting = true;
    try {
      registerCallCount++;
    } finally {
      isSubmitting = false;
      finallyRan = true;
    }
  }

  /// 예외 발생 시뮬레이션 (finally 동작 확인)
  void handleSubmitWithException(UserRole role) {
    if (isSubmitting) return;
    isSubmitting = true;
    try {
      throw Exception('네트워크 오류');
    } catch (_) {
      // 오류 처리 (Toast 표시 등)
    } finally {
      isSubmitting = false;
      finallyRan = true;
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// main
// ══════════════════════════════════════════════════════════════════════════════
void main() {
  // ════════════════════════════════════════════════════════════════
  // Group 1. 사업자등록번호 checksum 검증 (SCENARIO-ROLE-01 ~ 20)
  // ════════════════════════════════════════════════════════════════
  group('Group 1. 사업자등록번호 checksum 검증', () {
    // ── 유효한 번호 ───────────────────────────────────────────────
    test('SCENARIO-ROLE-01: 2208162517 → 유효', () {
      // 검증: sum=83, += 0, checkDigit=7, d[9]=7
      expect(isValidBusinessNumber('2208162517'), isTrue);
    });

    test('SCENARIO-ROLE-02: 1234567891 → 유효', () {
      // 검증: sum=165, += 4, checkDigit=1, d[9]=1
      expect(isValidBusinessNumber('1234567891'), isTrue);
    });

    test('SCENARIO-ROLE-03: 1012345672 → 유효', () {
      // 검증: sum=105, += 3, checkDigit=2, d[9]=2
      expect(isValidBusinessNumber('1012345672'), isTrue);
    });

    test('SCENARIO-ROLE-04: 3333333336 → 유효', () {
      // 검증: sum=93, += 1, checkDigit=6, d[9]=6
      expect(isValidBusinessNumber('3333333336'), isTrue);
    });

    test('SCENARIO-ROLE-05: 0000000000 → 유효 (sum=0, checkDigit=0)', () {
      // 검증: sum=0, += 0, checkDigit=(10-0)%10=0, d[9]=0
      expect(isValidBusinessNumber('0000000000'), isTrue);
    });

    test('SCENARIO-ROLE-06: 1111111119 → 유효', () {
      // 검증: sum=31, += 0, checkDigit=9, d[9]=9
      expect(isValidBusinessNumber('1111111119'), isTrue);
    });

    test('SCENARIO-ROLE-07: 4444444444 → 유효', () {
      // 검증: sum=124, += 2, checkDigit=4, d[9]=4
      expect(isValidBusinessNumber('4444444444'), isTrue);
    });

    test('SCENARIO-ROLE-08: 0000000015 → 유효 (d[8]=1, 가중치=5)', () {
      // 검증: sum=5, += 0, checkDigit=5, d[9]=5
      expect(isValidBusinessNumber('0000000015'), isTrue);
    });

    // ── 길이 오류 ─────────────────────────────────────────────────
    test('SCENARIO-ROLE-09: 9자리 → 길이 불일치 false', () {
      expect(isValidBusinessNumber('220816251'), isFalse);
    });

    test('SCENARIO-ROLE-10: 11자리 → 길이 불일치 false', () {
      expect(isValidBusinessNumber('22081625170'), isFalse);
    });

    test('SCENARIO-ROLE-11: 빈 문자열 → false', () {
      expect(isValidBusinessNumber(''), isFalse);
    });

    test('SCENARIO-ROLE-12: 1자리 → false', () {
      expect(isValidBusinessNumber('1'), isFalse);
    });

    test('SCENARIO-ROLE-13: 20자리 → false', () {
      expect(isValidBusinessNumber('12345678901234567890'), isFalse);
    });

    // ── 체크섬 불일치 ─────────────────────────────────────────────
    test('SCENARIO-ROLE-14: 1234567890 → 체크섬 불일치 (체크=1, 마지막=0)', () {
      expect(isValidBusinessNumber('1234567890'), isFalse);
    });

    test('SCENARIO-ROLE-15: 9999999999 → 체크섬 불일치 (체크=7, 마지막=9)', () {
      expect(isValidBusinessNumber('9999999999'), isFalse);
    });

    test('SCENARIO-ROLE-16: 1111111111 → 체크섬 불일치 (체크=9, 마지막=1)', () {
      expect(isValidBusinessNumber('1111111111'), isFalse);
    });

    test('SCENARIO-ROLE-17: 유효 번호 마지막 자리 +1 → false', () {
      // 2208162517(유효) → 2208162518(무효)
      expect(isValidBusinessNumber('2208162518'), isFalse);
    });

    test('SCENARIO-ROLE-18: 유효 번호 마지막 자리 -1 → false', () {
      // 2208162517(유효) → 2208162516(무효)
      expect(isValidBusinessNumber('2208162516'), isFalse);
    });

    // ── 숫자 외 입력 ──────────────────────────────────────────────
    test('SCENARIO-ROLE-19: 알파벳 포함 → false (parse 예외 처리)', () {
      expect(isValidBusinessNumber('ABCDEFGHIJ'), isFalse);
    });

    test('SCENARIO-ROLE-20: 대시 포함 (미제거) → false (길이 != 10)', () {
      // 대시 제거 없이 바로 전달하면 길이 초과
      expect(isValidBusinessNumber('220-81-62517'), isFalse);
    });
  });

  // ════════════════════════════════════════════════════════════════
  // Group 2. USER 역할 — signUp 파라미터 구성 (SCENARIO-ROLE-21 ~ 27)
  // ════════════════════════════════════════════════════════════════
  group('Group 2. USER 역할 - signUp 파라미터 구성', () {
    test('SCENARIO-ROLE-21: USER + businessNumber 비어있음 → null', () {
      expect(
        resolveBusinessNumber(role: UserRole.USER, controllerText: ''),
        isNull,
      );
    });

    test('SCENARIO-ROLE-22: USER + businessNumber 10자리 있어도 → null (role=USER)', () {
      expect(
        resolveBusinessNumber(role: UserRole.USER, controllerText: '2208162517'),
        isNull,
      );
    });

    test('SCENARIO-ROLE-23: USER + businessName 있어도 → null', () {
      expect(
        resolveBusinessName(role: UserRole.USER, controllerText: '알핏 주식회사'),
        isNull,
      );
    });

    test('SCENARIO-ROLE-24: USER + ceoName 있어도 → null', () {
      expect(
        resolveCeoName(role: UserRole.USER, controllerText: '홍길동'),
        isNull,
      );
    });

    test('SCENARIO-ROLE-25: USER + businessNumber 대시 포함 → null (role=USER)', () {
      expect(
        resolveBusinessNumber(role: UserRole.USER, controllerText: '220-81-62517'),
        isNull,
      );
    });

    test('SCENARIO-ROLE-26: USER + businessName 공백만 → null', () {
      expect(
        resolveBusinessName(role: UserRole.USER, controllerText: '   '),
        isNull,
      );
    });

    test('SCENARIO-ROLE-27: USER + ceoName 빈 문자열 → null', () {
      expect(
        resolveCeoName(role: UserRole.USER, controllerText: ''),
        isNull,
      );
    });
  });

  // ════════════════════════════════════════════════════════════════
  // Group 3. BUSINESS_ADMIN — signUp 파라미터 구성 (SCENARIO-ROLE-28 ~ 38)
  // ════════════════════════════════════════════════════════════════
  group('Group 3. BUSINESS_ADMIN 역할 - signUp 파라미터 구성', () {
    test('SCENARIO-ROLE-28: BUSINESS_ADMIN + businessNumber 10자리 → 그대로 반환', () {
      expect(
        resolveBusinessNumber(
            role: UserRole.BUSINESS_ADMIN, controllerText: '2208162517'),
        equals('2208162517'),
      );
    });

    test('SCENARIO-ROLE-29: BUSINESS_ADMIN + 대시 포함 번호 → 대시 제거 후 반환', () {
      expect(
        resolveBusinessNumber(
            role: UserRole.BUSINESS_ADMIN, controllerText: '220-81-62517'),
        equals('2208162517'),
      );
    });

    test('SCENARIO-ROLE-30: BUSINESS_ADMIN + businessNumber 빈 문자열 → null', () {
      expect(
        resolveBusinessNumber(role: UserRole.BUSINESS_ADMIN, controllerText: ''),
        isNull,
      );
    });

    test('SCENARIO-ROLE-31: BUSINESS_ADMIN + 대시만 있는 입력 → null (대시 제거 후 empty)', () {
      expect(
        resolveBusinessNumber(role: UserRole.BUSINESS_ADMIN, controllerText: '---'),
        isNull,
      );
    });

    test('SCENARIO-ROLE-32: BUSINESS_ADMIN + businessName 있음 → trim 후 반환', () {
      expect(
        resolveBusinessName(
            role: UserRole.BUSINESS_ADMIN, controllerText: '  알핏 주식회사  '),
        equals('알핏 주식회사'),
      );
    });

    test('SCENARIO-ROLE-33: BUSINESS_ADMIN + businessName 빈 문자열 → null', () {
      expect(
        resolveBusinessName(role: UserRole.BUSINESS_ADMIN, controllerText: ''),
        isNull,
      );
    });

    test('SCENARIO-ROLE-34: BUSINESS_ADMIN + businessName 공백만 → null', () {
      expect(
        resolveBusinessName(role: UserRole.BUSINESS_ADMIN, controllerText: '   '),
        isNull,
      );
    });

    test('SCENARIO-ROLE-35: BUSINESS_ADMIN + ceoName 있음 → trim 후 반환', () {
      expect(
        resolveCeoName(
            role: UserRole.BUSINESS_ADMIN, controllerText: ' 홍길동 '),
        equals('홍길동'),
      );
    });

    test('SCENARIO-ROLE-36: BUSINESS_ADMIN + ceoName 빈 문자열 → null', () {
      expect(
        resolveCeoName(role: UserRole.BUSINESS_ADMIN, controllerText: ''),
        isNull,
      );
    });

    test('SCENARIO-ROLE-37: BUSINESS_ADMIN + 모든 필드 있음 → 모두 비null 반환', () {
      final bizNum = resolveBusinessNumber(
          role: UserRole.BUSINESS_ADMIN, controllerText: '2208162517');
      final bizName = resolveBusinessName(
          role: UserRole.BUSINESS_ADMIN, controllerText: '알핏 주식회사');
      final ceoName = resolveCeoName(
          role: UserRole.BUSINESS_ADMIN, controllerText: '홍길동');

      expect(bizNum, equals('2208162517'));
      expect(bizName, equals('알핏 주식회사'));
      expect(ceoName, equals('홍길동'));
    });

    test('SCENARIO-ROLE-38: BUSINESS_ADMIN + 모든 필드 없음 → 모두 null', () {
      final bizNum = resolveBusinessNumber(
          role: UserRole.BUSINESS_ADMIN, controllerText: '');
      final bizName = resolveBusinessName(
          role: UserRole.BUSINESS_ADMIN, controllerText: '');
      final ceoName = resolveCeoName(
          role: UserRole.BUSINESS_ADMIN, controllerText: '');

      expect(bizNum, isNull);
      expect(bizName, isNull);
      expect(ceoName, isNull);
    });
  });

  // ════════════════════════════════════════════════════════════════
  // Group 4. _handleRoleSelection 유효성 검사 분기 (SCENARIO-ROLE-39 ~ 48)
  // ════════════════════════════════════════════════════════════════
  group('Group 4. _handleRoleSelection 유효성 검사 분기', () {
    test('SCENARIO-ROLE-39: BUSINESS_ADMIN + bizNum 비어있음 → pass (선택사항)', () {
      expect(
        validateForRoleSelection(
          role: UserRole.BUSINESS_ADMIN,
          businessNumberRaw: '',
          isSubmitting: false,
        ),
        equals(HandleRoleResult.pass),
      );
    });

    test('SCENARIO-ROLE-40: BUSINESS_ADMIN + 유효 10자리 → pass', () {
      expect(
        validateForRoleSelection(
          role: UserRole.BUSINESS_ADMIN,
          businessNumberRaw: '2208162517',
          isSubmitting: false,
        ),
        equals(HandleRoleResult.pass),
      );
    });

    test('SCENARIO-ROLE-41: BUSINESS_ADMIN + 9자리 입력 → invalidLength', () {
      expect(
        validateForRoleSelection(
          role: UserRole.BUSINESS_ADMIN,
          businessNumberRaw: '220816251',
          isSubmitting: false,
        ),
        equals(HandleRoleResult.invalidLength),
      );
    });

    test('SCENARIO-ROLE-42: BUSINESS_ADMIN + 11자리 입력 → invalidLength', () {
      expect(
        validateForRoleSelection(
          role: UserRole.BUSINESS_ADMIN,
          businessNumberRaw: '22081625170',
          isSubmitting: false,
        ),
        equals(HandleRoleResult.invalidLength),
      );
    });

    test('SCENARIO-ROLE-43: BUSINESS_ADMIN + 10자리지만 체크섬 불일치 → invalidChecksum', () {
      expect(
        validateForRoleSelection(
          role: UserRole.BUSINESS_ADMIN,
          businessNumberRaw: '1234567890',
          isSubmitting: false,
        ),
        equals(HandleRoleResult.invalidChecksum),
      );
    });

    test('SCENARIO-ROLE-44: USER + 무효 번호 있어도 → pass (USER는 검사 안 함)', () {
      expect(
        validateForRoleSelection(
          role: UserRole.USER,
          businessNumberRaw: '1234567890',
          isSubmitting: false,
        ),
        equals(HandleRoleResult.pass),
      );
    });

    test('SCENARIO-ROLE-45: isSubmitting=true + USER → alreadySubmitting', () {
      expect(
        validateForRoleSelection(
          role: UserRole.USER,
          businessNumberRaw: '',
          isSubmitting: true,
        ),
        equals(HandleRoleResult.alreadySubmitting),
      );
    });

    test('SCENARIO-ROLE-46: isSubmitting=true + BUSINESS_ADMIN → alreadySubmitting (검사 전에 차단)', () {
      expect(
        validateForRoleSelection(
          role: UserRole.BUSINESS_ADMIN,
          businessNumberRaw: '2208162517',
          isSubmitting: true,
        ),
        equals(HandleRoleResult.alreadySubmitting),
      );
    });

    test('SCENARIO-ROLE-47: BUSINESS_ADMIN + 대시 포함 유효번호 → pass (대시 제거 후 10자리)', () {
      expect(
        validateForRoleSelection(
          role: UserRole.BUSINESS_ADMIN,
          businessNumberRaw: '220-81-62517',
          isSubmitting: false,
        ),
        equals(HandleRoleResult.pass),
      );
    });

    test('SCENARIO-ROLE-48: BUSINESS_ADMIN + 대시만 → pass (제거 후 empty, 선택사항)', () {
      expect(
        validateForRoleSelection(
          role: UserRole.BUSINESS_ADMIN,
          businessNumberRaw: '---',
          isSubmitting: false,
        ),
        equals(HandleRoleResult.pass),
      );
    });
  });

  // ════════════════════════════════════════════════════════════════
  // Group 5. 사업장 등록 다이얼로그 분기 (SCENARIO-ROLE-49 ~ 56)
  // ════════════════════════════════════════════════════════════════
  group('Group 5. 사업장 등록 다이얼로그 분기', () {
    test('SCENARIO-ROLE-49: 사업자등록증 없음 → warningNoLicense 다이얼로그', () {
      expect(
        determineBusinessDialog(hasLicense: false),
        equals(BusinessDialogType.warningNoLicense),
      );
    });

    test('SCENARIO-ROLE-50: 사업자등록증 있음 → selectRegistration 다이얼로그', () {
      expect(
        determineBusinessDialog(hasLicense: true),
        equals(BusinessDialogType.selectRegistration),
      );
    });

    test('SCENARIO-ROLE-51: 경고 다이얼로그 — 나중에 선택 → registerUser 호출', () {
      expect(
        handleWarningDialog(chooseLater: true),
        equals(BusinessDialogAction.registerUser),
      );
    });

    test('SCENARIO-ROLE-52: 경고 다이얼로그 — 돌아가기 선택 → cancel', () {
      expect(
        handleWarningDialog(chooseLater: false),
        equals(BusinessDialogAction.cancel),
      );
    });

    test('SCENARIO-ROLE-53: 선택 다이얼로그 — 지금 등록 → registerUserAndNavigate', () {
      expect(
        handleSelectDialog(chooseNow: true),
        equals(BusinessDialogAction.registerUserAndNavigate),
      );
    });

    test('SCENARIO-ROLE-54: 선택 다이얼로그 — 나중에 → registerUser', () {
      expect(
        handleSelectDialog(chooseNow: false),
        equals(BusinessDialogAction.registerUser),
      );
    });

    test('SCENARIO-ROLE-55: 라이선스 없음 전체 플로우 — 나중에 등록', () {
      // 라이선스 없음 → 경고 다이얼로그
      final dialogType = determineBusinessDialog(hasLicense: false);
      expect(dialogType, equals(BusinessDialogType.warningNoLicense));
      // 나중에 선택 → registerUser
      final action = handleWarningDialog(chooseLater: true);
      expect(action, equals(BusinessDialogAction.registerUser));
    });

    test('SCENARIO-ROLE-56: 라이선스 있음 전체 플로우 — 지금 등록', () {
      // 라이선스 있음 → 선택 다이얼로그
      final dialogType = determineBusinessDialog(hasLicense: true);
      expect(dialogType, equals(BusinessDialogType.selectRegistration));
      // 지금 등록 선택 → navigate
      final action = handleSelectDialog(chooseNow: true);
      expect(action, equals(BusinessDialogAction.registerUserAndNavigate));
    });
  });

  // ════════════════════════════════════════════════════════════════
  // Group 6. _isSubmitting 가드 (SCENARIO-ROLE-57 ~ 62)
  // ════════════════════════════════════════════════════════════════
  group('Group 6. _isSubmitting 가드 (중복 실행 방지)', () {
    test('SCENARIO-ROLE-57: isSubmitting=false → 등록 진행 (count=1)', () {
      final sim = SubmitGuardSimulator();
      sim.handleSubmit(UserRole.USER);
      expect(sim.registerCallCount, equals(1));
    });

    test('SCENARIO-ROLE-58: isSubmitting=true 상태에서 호출 → 즉시 return (count=0)', () {
      final sim = SubmitGuardSimulator();
      sim.isSubmitting = true;
      sim.handleSubmit(UserRole.USER);
      expect(sim.registerCallCount, equals(0));
    });

    test('SCENARIO-ROLE-59: 정상 완료 후 isSubmitting=false 복원', () {
      final sim = SubmitGuardSimulator();
      sim.handleSubmit(UserRole.USER);
      expect(sim.isSubmitting, isFalse);
    });

    test('SCENARIO-ROLE-60: 예외 발생 시에도 finally에서 isSubmitting=false', () {
      final sim = SubmitGuardSimulator();
      sim.handleSubmitWithException(UserRole.USER);
      expect(sim.isSubmitting, isFalse);
    });

    test('SCENARIO-ROLE-61: BUSINESS_ADMIN + isSubmitting=true → 무시 (count=0)', () {
      final sim = SubmitGuardSimulator();
      sim.isSubmitting = true;
      sim.handleSubmit(UserRole.BUSINESS_ADMIN);
      expect(sim.registerCallCount, equals(0));
    });

    test('SCENARIO-ROLE-62: 순차 호출 2회 → 각 완료 후 재실행 가능 (count=2)', () {
      final sim = SubmitGuardSimulator();
      sim.handleSubmit(UserRole.USER);
      sim.handleSubmit(UserRole.USER);
      expect(sim.registerCallCount, equals(2));
    });
  });

  // ════════════════════════════════════════════════════════════════
  // Group 7. 통합 시나리오 (SCENARIO-ROLE-63 ~ 70)
  // ════════════════════════════════════════════════════════════════
  group('Group 7. 통합 시나리오', () {
    test('SCENARIO-ROLE-63: USER 등록 전체 — 파라미터 null + 검사 pass', () {
      // USER는 사업자 정보 없이 등록
      final result = validateForRoleSelection(
        role: UserRole.USER,
        businessNumberRaw: '',
        isSubmitting: false,
      );
      expect(result, equals(HandleRoleResult.pass));

      final bizNum = resolveBusinessNumber(
          role: UserRole.USER, controllerText: '');
      final bizName = resolveBusinessName(
          role: UserRole.USER, controllerText: '');
      final ceoName = resolveCeoName(role: UserRole.USER, controllerText: '');
      expect(bizNum, isNull);
      expect(bizName, isNull);
      expect(ceoName, isNull);
    });

    test('SCENARIO-ROLE-64: BUSINESS_ADMIN + 사업자번호 없이 라이선스 있음 → pass + selectRegistration', () {
      final result = validateForRoleSelection(
        role: UserRole.BUSINESS_ADMIN,
        businessNumberRaw: '',
        isSubmitting: false,
      );
      expect(result, equals(HandleRoleResult.pass));

      final dialog = determineBusinessDialog(hasLicense: true);
      expect(dialog, equals(BusinessDialogType.selectRegistration));
    });

    test('SCENARIO-ROLE-65: BUSINESS_ADMIN + 유효 번호 + 라이선스 + 지금 등록 → navigate', () {
      final validationResult = validateForRoleSelection(
        role: UserRole.BUSINESS_ADMIN,
        businessNumberRaw: '1234567891',
        isSubmitting: false,
      );
      expect(validationResult, equals(HandleRoleResult.pass));

      expect(isValidBusinessNumber('1234567891'), isTrue);

      final dialogType = determineBusinessDialog(hasLicense: true);
      expect(dialogType, equals(BusinessDialogType.selectRegistration));

      final action = handleSelectDialog(chooseNow: true);
      expect(action, equals(BusinessDialogAction.registerUserAndNavigate));
    });

    test('SCENARIO-ROLE-66: BUSINESS_ADMIN + 무효 번호 → invalidChecksum (등록 중단)', () {
      final result = validateForRoleSelection(
        role: UserRole.BUSINESS_ADMIN,
        businessNumberRaw: '1234567890',
        isSubmitting: false,
      );
      expect(result, equals(HandleRoleResult.invalidChecksum));
      // invalidChecksum이면 다이얼로그를 표시하지 않음
    });

    test('SCENARIO-ROLE-67: BUSINESS_ADMIN + 9자리 번호 → invalidLength (등록 중단)', () {
      final result = validateForRoleSelection(
        role: UserRole.BUSINESS_ADMIN,
        businessNumberRaw: '123456789',
        isSubmitting: false,
      );
      expect(result, equals(HandleRoleResult.invalidLength));
    });

    test('SCENARIO-ROLE-68: BUSINESS_ADMIN + 모든 필드 입력 + 유효 번호 → 파라미터 모두 비null', () {
      final bizNum = resolveBusinessNumber(
          role: UserRole.BUSINESS_ADMIN, controllerText: '2208162517');
      final bizName = resolveBusinessName(
          role: UserRole.BUSINESS_ADMIN, controllerText: '알핏주식회사');
      final ceoName = resolveCeoName(
          role: UserRole.BUSINESS_ADMIN, controllerText: '김의관');

      expect(bizNum, isNotNull);
      expect(bizName, isNotNull);
      expect(ceoName, isNotNull);

      // 번호는 checksum도 통과
      expect(isValidBusinessNumber(bizNum!), isTrue);
    });

    test('SCENARIO-ROLE-69: BUSINESS_ADMIN + 전부 빈 입력 + 라이선스 없음 → warningNoLicense', () {
      final result = validateForRoleSelection(
        role: UserRole.BUSINESS_ADMIN,
        businessNumberRaw: '',
        isSubmitting: false,
      );
      expect(result, equals(HandleRoleResult.pass));

      final dialog = determineBusinessDialog(hasLicense: false);
      expect(dialog, equals(BusinessDialogType.warningNoLicense));

      // 경고 다이얼로그에서 나중에 선택하면 registerUser 호출
      final action = handleWarningDialog(chooseLater: true);
      expect(action, equals(BusinessDialogAction.registerUser));
    });

    test('SCENARIO-ROLE-70: isSubmitting=true 상태에서 유효 번호도 알수 없음 (제출 차단 최우선)', () {
      final result = validateForRoleSelection(
        role: UserRole.BUSINESS_ADMIN,
        businessNumberRaw: '2208162517', // 유효한 번호
        isSubmitting: true,              // 하지만 이미 제출 중
      );
      // isSubmitting 체크가 최우선 — 번호 검증은 실행되지 않음
      expect(result, equals(HandleRoleResult.alreadySubmitting));
    });
  });
}
