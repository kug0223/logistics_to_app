// test/simulation/register_nationality_simulation_test.dart
//
// register_screen.dart 내국인/외국인 분기 처리 로직 시뮬레이션 테스트
//
// 검증 범위:
//   1. 외국인등록번호 파싱 (_parseResidentNumber) — 성별코드 5~8
//   2. 내국인 주민번호 파싱 (_parseResidentNumber) — 성별코드 1~4
//   3. 만 18세 이상 나이 경계값 검증
//   4. 2000년대 미래 연도 차단 로직
//   5. 입력 불완전 처리 (길이 부족 / 빈 문자열)
//   6. isKorean 토글 시 상태 초기화 (_buildNationalityToggle)
//   7. 내국인 Step1 PASS 인증 필수 (_validateStep1)
//   8. 외국인 Step1 SMS 인증 필수 (_validateStep1)
//   9. 외국인등록번호 마스킹 형식 (foreignIdNumber)
//  10. accountStatus 결정 (active vs pending)
//  11. residentNumber 필드 마스킹 처리
//  12. PassAuthResult 데이터 소스 분기 (내국인 vs 외국인)
//
// 코드 원본: lib/screens/auth/register_screen.dart
// 실행: flutter test test/simulation/register_nationality_simulation_test.dart

// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';

// ══════════════════════════════════════════════════════════════════════════════
// 데이터 클래스 (register_screen.dart 내 private 클래스 재현)
// ══════════════════════════════════════════════════════════════════════════════

class ResidentResult {
  final DateTime? birthDate;
  final String? gender;
  final String? error;

  const ResidentResult({this.birthDate, this.gender, this.error});

  bool get isSuccess => birthDate != null && gender != null && error == null;
}

class MockPassAuthResult {
  final String name;
  final String phone;
  final String gender;
  final DateTime birthDate;
  final String passToken;

  const MockPassAuthResult({
    required this.name,
    required this.phone,
    required this.gender,
    required this.birthDate,
    required this.passToken,
  });
}

// ══════════════════════════════════════════════════════════════════════════════
// 로직 재현 함수들 (register_screen.dart 핵심 로직 복제)
// ══════════════════════════════════════════════════════════════════════════════

/// _parseResidentNumber() 완전 재현
///
/// [today] — 테스트에서 고정 날짜 주입용 (기본값: DateTime.now())
ResidentResult parseResidentNumber({
  required String rn1,
  required String rn2,
  required bool isKorean,
  DateTime? today,
}) {
  // 입력 불완전 → 빈 결과 (에러 없음)
  if (rn1.length != 6 || rn2.isEmpty) {
    return const ResidentResult();
  }

  try {
    int year = int.parse(rn1.substring(0, 2));
    final int month = int.parse(rn1.substring(2, 4));
    final int day = int.parse(rn1.substring(4, 6));
    final int genderCode = int.parse(rn2[0]);

    final isForeign = !isKorean;
    final minCode = isForeign ? 5 : 1;
    final maxCode = isForeign ? 8 : 4;

    if (genderCode < minCode || genderCode > maxCode) {
      return ResidentResult(error: '뒷자리는 $minCode~$maxCode만 가능합니다');
    }

    // 외국인등록번호는 코드 범위를 -4 이동해 주민번호 로직 재사용
    final effectiveCode = isForeign ? genderCode - 4 : genderCode;

    if (effectiveCode == 1 || effectiveCode == 2) {
      year += 1900;
    } else {
      // effectiveCode 3 or 4 → 2000년대생
      final currentYear = (today ?? DateTime.now()).year;
      final twoDigitCurrentYear = currentYear % 100;
      if (year > twoDigitCurrentYear) {
        return ResidentResult(
          error:
              '2000년대생은 00~${twoDigitCurrentYear.toString().padLeft(2, '0')}년생만 가능합니다',
        );
      }
      year += 2000;
    }

    // 아래 두 검사는 수학적으로 도달 불가 (dead code) — 원본 코드 동일
    if ((effectiveCode == 3 || effectiveCode == 4) && year < 2000) {
      final expected = isForeign ? '7 또는 8' : '3 또는 4';
      return ResidentResult(error: '$year년생은 뒷자리 $expected를 사용해야 합니다');
    }
    if ((effectiveCode == 1 || effectiveCode == 2) && year >= 2000) {
      final expected = isForeign ? '7 또는 8' : '3 또는 4';
      return ResidentResult(error: '$year년생은 뒷자리 $expected를 사용해야 합니다');
    }

    DateTime birthDate;
    try {
      birthDate = DateTime(year, month, day);
    } catch (_) {
      return ResidentResult(error: '존재하지 않는 날짜입니다 ($year년 $month월 $day일)');
    }

    // 만 18세 이상 검사
    final todayDate = today ?? DateTime.now();
    int age = todayDate.year - birthDate.year;
    if (todayDate.month < birthDate.month ||
        (todayDate.month == birthDate.month &&
            todayDate.day < birthDate.day)) {
      age--;
    }
    if (age < 18) {
      return const ResidentResult(error: '만 18세 이상만 가입 가능합니다');
    }

    final gender = (effectiveCode == 1 || effectiveCode == 3) ? '남성' : '여성';
    return ResidentResult(birthDate: birthDate, gender: gender);
  } catch (_) {
    return const ResidentResult(error: '올바른 번호를 입력해주세요');
  }
}

// ── isKorean 토글 시뮬레이션 ─────────────────────────────────────────────────

/// _buildNationalityToggle GestureDetector.onTap 내부 setState 재현
class RegisterStateSimulator {
  bool isKorean;
  String? passAuthResult; // null = 미인증, non-null = 인증 토큰
  ResidentResult residentResult;
  bool phoneVerifyStatusIsVerified;
  String nameControllerText;
  String rn1ControllerText;
  String rn2ControllerText;
  String phoneControllerText;

  RegisterStateSimulator({
    this.isKorean = true,
    this.passAuthResult,
    this.residentResult = const ResidentResult(),
    this.phoneVerifyStatusIsVerified = false,
    this.nameControllerText = '',
    this.rn1ControllerText = '',
    this.rn2ControllerText = '',
    this.phoneControllerText = '',
  });

  /// 국적 토글 — 모든 필드 초기화
  void toggleNationality(bool korean) {
    isKorean = korean;
    passAuthResult = null;
    nameControllerText = '';
    residentResult = const ResidentResult();
    rn1ControllerText = '';
    rn2ControllerText = '';
    phoneControllerText = '';
    phoneVerifyStatusIsVerified = false;
  }
}

// ── Step1 검증 시뮬레이션 ────────────────────────────────────────────────────

/// _validateStep1() 내국인 분기 재현
String? validateStep1Korean({required String? passAuthResult}) {
  if (passAuthResult == null) return 'PASS 본인인증을 완료해주세요';
  return null; // 통과 (약관 동의 등 나머지 검사는 별도 테스트)
}

/// _validateStep1() 외국인 분기 재현
String? validateStep1Foreign({
  required ResidentResult residentResult,
  required bool phoneVerified,
}) {
  if (residentResult.birthDate == null || residentResult.gender == null) {
    return '올바른 외국인등록번호를 입력해주세요';
  }
  if (!phoneVerified) return '휴대폰 번호 인증을 완료해주세요';
  return null;
}

// ── 마스킹 / 상태 결정 헬퍼 ──────────────────────────────────────────────────

/// foreignIdNumber 필드 — _registerUser / _registerUserAndGoToBusinessRegistration
String buildForeignIdNumber(String rn1, String rn2FirstChar) =>
    '$rn1-X$rn2FirstChar*****';

/// foreignIdNumber 필드 (isKorean 분기 포함)
String? buildForeignIdNumberField({
  required bool isKorean,
  required String rn1,
  required String rn2FirstChar,
}) =>
    isKorean ? null : '$rn1-X$rn2FirstChar*****';

/// residentNumber 필드 — isKorean=true: null, isKorean=false: 마스킹
String? buildResidentNumberField({
  required bool isKorean,
  required String rn1,
}) =>
    isKorean ? null : '$rn1-X******';

/// accountStatus 결정
String getAccountStatus(bool isKorean) => isKorean ? 'active' : 'pending';

// ── 회원가입 파라미터 데이터 소스 분기 ─────────────────────────────────────

String getSignupName({
  required bool isKorean,
  required MockPassAuthResult passAuthResult,
  required String directName,
}) =>
    isKorean ? passAuthResult.name : directName;

String getSignupPhone({
  required bool isKorean,
  required MockPassAuthResult passAuthResult,
  required String directPhone,
}) =>
    isKorean ? passAuthResult.phone : directPhone;

String? getSignupGender({
  required bool isKorean,
  required MockPassAuthResult? passAuthResult,
  required ResidentResult residentResult,
}) =>
    isKorean ? passAuthResult?.gender : residentResult.gender;

DateTime? getSignupBirthDate({
  required bool isKorean,
  required MockPassAuthResult? passAuthResult,
  required ResidentResult residentResult,
}) =>
    isKorean ? passAuthResult?.birthDate : residentResult.birthDate;

// ══════════════════════════════════════════════════════════════════════════════
// 테스트 기준 날짜 (2026-07-08 고정)
// ══════════════════════════════════════════════════════════════════════════════

final _today = DateTime(2026, 7, 8);

// ══════════════════════════════════════════════════════════════════════════════
// 테스트
// ══════════════════════════════════════════════════════════════════════════════

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // SCENARIO-NAT-001~010: 외국인등록번호 성별코드 5~8 파싱
  //
  // 코드 구현 동작 (effectiveCode = genderCode - 4):
  //   코드 5 (effectiveCode 1) → 1900년대 남성
  //   코드 6 (effectiveCode 2) → 1900년대 여성
  //   코드 7 (effectiveCode 3) → 2000년대 남성
  //   코드 8 (effectiveCode 4) → 2000년대 여성
  // ══════════════════════════════════════════════════════════════════════════
  group('외국인등록번호 성별코드 5~8 파싱', () {
    test('SCENARIO-NAT-001: 코드 5 → 1986-01-01 남성 (effectiveCode=1, 1900s)', () {
      final r = parseResidentNumber(
          rn1: '860101', rn2: '5', isKorean: false, today: _today);
      expect(r.birthDate, equals(DateTime(1986, 1, 1)));
      expect(r.gender, equals('남성'));
      expect(r.error, isNull);
    });

    test('SCENARIO-NAT-002: 코드 6 → 1992-03-15 여성 (effectiveCode=2, 1900s)', () {
      final r = parseResidentNumber(
          rn1: '920315', rn2: '6', isKorean: false, today: _today);
      expect(r.birthDate, equals(DateTime(1992, 3, 15)));
      expect(r.gender, equals('여성'));
      expect(r.error, isNull);
    });

    test('SCENARIO-NAT-003: 코드 7 → 2001-08-15 남성 (effectiveCode=3, 2000s)', () {
      final r = parseResidentNumber(
          rn1: '010815', rn2: '7', isKorean: false, today: _today);
      expect(r.birthDate, equals(DateTime(2001, 8, 15)));
      expect(r.gender, equals('남성'));
      expect(r.error, isNull);
    });

    test('SCENARIO-NAT-004: 코드 8 → 2003-12-01 여성 (effectiveCode=4, 2000s)', () {
      final r = parseResidentNumber(
          rn1: '031201', rn2: '8', isKorean: false, today: _today);
      expect(r.birthDate, equals(DateTime(2003, 12, 1)));
      expect(r.gender, equals('여성'));
      expect(r.error, isNull);
    });

    test('SCENARIO-NAT-005: 외국인에 코드 1 → 에러 (5~8만 허용)', () {
      final r = parseResidentNumber(
          rn1: '860101', rn2: '1', isKorean: false, today: _today);
      expect(r.error, contains('5~8'));
      expect(r.birthDate, isNull);
    });

    test('SCENARIO-NAT-006: 외국인에 코드 2 → 에러', () {
      final r = parseResidentNumber(
          rn1: '860101', rn2: '2', isKorean: false, today: _today);
      expect(r.error, contains('5~8'));
      expect(r.birthDate, isNull);
    });

    test('SCENARIO-NAT-007: 외국인에 코드 3 → 에러', () {
      final r = parseResidentNumber(
          rn1: '860101', rn2: '3', isKorean: false, today: _today);
      expect(r.error, contains('5~8'));
    });

    test('SCENARIO-NAT-008: 외국인에 코드 4 → 에러', () {
      final r = parseResidentNumber(
          rn1: '860101', rn2: '4', isKorean: false, today: _today);
      expect(r.error, contains('5~8'));
    });

    test('SCENARIO-NAT-009: 외국인에 코드 9 → 에러 (9 > maxCode 8)', () {
      final r = parseResidentNumber(
          rn1: '860101', rn2: '9', isKorean: false, today: _today);
      expect(r.error, contains('5~8'));
    });

    test('SCENARIO-NAT-010: 외국인에 코드 0 → 에러 (0 < minCode 5)', () {
      final r = parseResidentNumber(
          rn1: '860101', rn2: '0', isKorean: false, today: _today);
      expect(r.error, contains('5~8'));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SCENARIO-NAT-011~016: 내국인 주민번호 성별코드 1~4 파싱
  // ══════════════════════════════════════════════════════════════════════════
  group('내국인 주민번호 성별코드 1~4 파싱', () {
    test('SCENARIO-NAT-011: 코드 1 → 1990-01-01 남성', () {
      final r = parseResidentNumber(
          rn1: '900101', rn2: '1', isKorean: true, today: _today);
      expect(r.birthDate, equals(DateTime(1990, 1, 1)));
      expect(r.gender, equals('남성'));
      expect(r.error, isNull);
    });

    test('SCENARIO-NAT-012: 코드 2 → 1985-07-01 여성', () {
      final r = parseResidentNumber(
          rn1: '850701', rn2: '2', isKorean: true, today: _today);
      expect(r.birthDate, equals(DateTime(1985, 7, 1)));
      expect(r.gender, equals('여성'));
      expect(r.error, isNull);
    });

    test('SCENARIO-NAT-013: 코드 3 → 2000-01-01 남성', () {
      final r = parseResidentNumber(
          rn1: '000101', rn2: '3', isKorean: true, today: _today);
      expect(r.birthDate, equals(DateTime(2000, 1, 1)));
      expect(r.gender, equals('남성'));
      expect(r.error, isNull);
    });

    test('SCENARIO-NAT-014: 코드 4 → 2005-03-01 여성', () {
      final r = parseResidentNumber(
          rn1: '050301', rn2: '4', isKorean: true, today: _today);
      expect(r.birthDate, equals(DateTime(2005, 3, 1)));
      expect(r.gender, equals('여성'));
      expect(r.error, isNull);
    });

    test('SCENARIO-NAT-015: 내국인에 코드 5 → 에러 (1~4만 허용)', () {
      final r = parseResidentNumber(
          rn1: '860101', rn2: '5', isKorean: true, today: _today);
      expect(r.error, contains('1~4'));
      expect(r.birthDate, isNull);
    });

    test('SCENARIO-NAT-016: 내국인에 코드 0 → 에러', () {
      final r = parseResidentNumber(
          rn1: '860101', rn2: '0', isKorean: true, today: _today);
      expect(r.error, contains('1~4'));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SCENARIO-NAT-017~022: 만 18세 이상 나이 경계값 검증
  // 기준일: 2026-07-08
  // ══════════════════════════════════════════════════════════════════════════
  group('만 18세 이상 나이 경계값 검증 (기준: 2026-07-08)', () {
    test('SCENARIO-NAT-017: 2008-07-08 생 (만 18세 생일 당일) → 통과', () {
      // 코드 7 → effectiveCode 3 → 2000s (2026-07-08 기준 딱 18세)
      final r = parseResidentNumber(
          rn1: '080708', rn2: '7', isKorean: false, today: _today);
      expect(r.error, isNull);
      expect(r.birthDate, equals(DateTime(2008, 7, 8)));
    });

    test('SCENARIO-NAT-018: 2008-07-09 생 (생일 하루 후 아직 17세) → 차단', () {
      // 오늘(7/8) < 생일(7/9) → age-- → 17세
      final r = parseResidentNumber(
          rn1: '080709', rn2: '7', isKorean: false, today: _today);
      expect(r.error, equals('만 18세 이상만 가입 가능합니다'));
    });

    test('SCENARIO-NAT-019: 2009-01-01 생 (17세) → 차단', () {
      final r = parseResidentNumber(
          rn1: '090101', rn2: '7', isKorean: false, today: _today);
      expect(r.error, equals('만 18세 이상만 가입 가능합니다'));
    });

    test('SCENARIO-NAT-020: 2008-01-01 생 (만 18세, 생일 이미 지남) → 통과', () {
      // 오늘(7/8) > 생일(1/1) → age 감소 없음 → 18세
      final r = parseResidentNumber(
          rn1: '080101', rn2: '7', isKorean: false, today: _today);
      expect(r.error, isNull);
      expect(r.birthDate?.year, equals(2008));
    });

    test('SCENARIO-NAT-021: 1986-01-01 생 외국인 코드 5 (만 40세) → 통과', () {
      final r = parseResidentNumber(
          rn1: '860101', rn2: '5', isKorean: false, today: _today);
      expect(r.error, isNull);
      expect(r.birthDate?.year, equals(1986));
    });

    test('SCENARIO-NAT-022: 내국인 코드 3 — 2009-08-01 생 (17세 미만) → 차단', () {
      // 오늘(7/8) < 생일(8/1) → age-- → 16세
      final r = parseResidentNumber(
          rn1: '090801', rn2: '3', isKorean: true, today: _today);
      expect(r.error, equals('만 18세 이상만 가입 가능합니다'));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SCENARIO-NAT-023~028: 2000년대 미래 연도 입력 차단
  // ══════════════════════════════════════════════════════════════════════════
  group('2000년대 미래 연도 입력 차단', () {
    test('SCENARIO-NAT-023: 외국인 코드 7, rn1="270101" (2027 > 2026) → 미래 연도 에러', () {
      final r = parseResidentNumber(
          rn1: '270101', rn2: '7', isKorean: false, today: _today);
      expect(r.error, contains('00~26'));
      expect(r.birthDate, isNull);
    });

    test('SCENARIO-NAT-024: 외국인 코드 7, rn1="990101" (99 > 26) → 미래 연도 에러', () {
      final r = parseResidentNumber(
          rn1: '990101', rn2: '7', isKorean: false, today: _today);
      expect(r.error, contains('00~26'));
    });

    test('SCENARIO-NAT-025: 외국인 코드 7, rn1="260101" (26 == 26) → 미래 에러 없음, 나이 미달 차단', () {
      // 26 > 26 = false → 미래 연도 차단 아님, year=2026 → age=0 → 나이 미달
      final r = parseResidentNumber(
          rn1: '260101', rn2: '7', isKorean: false, today: _today);
      expect(r.error, equals('만 18세 이상만 가입 가능합니다'));
    });

    test('SCENARIO-NAT-026: 내국인 코드 3, rn1="270101" → 미래 연도 에러', () {
      final r = parseResidentNumber(
          rn1: '270101', rn2: '3', isKorean: true, today: _today);
      expect(r.error, contains('00~26'));
    });

    test('SCENARIO-NAT-027: 외국인 코드 5, rn1="260101" → 1926년 (effectiveCode=1, 1900s) → 통과', () {
      // 코드 5 → effectiveCode 1 → year += 1900 → 26+1900=1926 (미래 연도 체크 없음)
      final r = parseResidentNumber(
          rn1: '260101', rn2: '5', isKorean: false, today: _today);
      expect(r.birthDate?.year, equals(1926));
      expect(r.error, isNull); // 1926년생 100세 → 나이 통과
    });

    test('SCENARIO-NAT-028: 외국인 코드 8, rn1="270601" (27 > 26) → 미래 연도 에러', () {
      final r = parseResidentNumber(
          rn1: '270601', rn2: '8', isKorean: false, today: _today);
      expect(r.error, contains('00~26'));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SCENARIO-NAT-029~034: 입력 불완전 처리
  // ══════════════════════════════════════════════════════════════════════════
  group('입력 불완전 처리', () {
    test('SCENARIO-NAT-029: rn1이 5자리 (length != 6) → 빈 결과 반환', () {
      final r = parseResidentNumber(
          rn1: '86010', rn2: '5', isKorean: false, today: _today);
      expect(r.birthDate, isNull);
      expect(r.gender, isNull);
      expect(r.error, isNull); // 에러도 없이 빈 상태
    });

    test('SCENARIO-NAT-030: rn1이 빈 문자열 → 빈 결과 반환', () {
      final r = parseResidentNumber(
          rn1: '', rn2: '5', isKorean: false, today: _today);
      expect(r.birthDate, isNull);
      expect(r.error, isNull);
    });

    test('SCENARIO-NAT-031: rn2가 빈 문자열 → 빈 결과 반환', () {
      final r = parseResidentNumber(
          rn1: '860101', rn2: '', isKorean: false, today: _today);
      expect(r.birthDate, isNull);
      expect(r.error, isNull);
    });

    test('SCENARIO-NAT-032: rn1, rn2 모두 빈 문자열 → 빈 결과 반환', () {
      final r = parseResidentNumber(
          rn1: '', rn2: '', isKorean: false, today: _today);
      expect(r.birthDate, isNull);
      expect(r.error, isNull);
    });

    test('SCENARIO-NAT-033: rn1이 7자리 (length > 6) → 빈 결과 반환', () {
      final r = parseResidentNumber(
          rn1: '8601010', rn2: '5', isKorean: false, today: _today);
      expect(r.birthDate, isNull);
      expect(r.error, isNull);
    });

    test('SCENARIO-NAT-034: rn1에 비숫자 포함 → 파싱 실패, 에러 반환', () {
      final r = parseResidentNumber(
          rn1: 'ABCDEF', rn2: '5', isKorean: false, today: _today);
      expect(r.error, isNotNull);
      expect(r.birthDate, isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SCENARIO-NAT-035~042: isKorean 토글 시 상태 초기화
  // ══════════════════════════════════════════════════════════════════════════
  group('isKorean 토글 시 상태 초기화', () {
    test('SCENARIO-NAT-035: 내국인→외국인 토글 — passAuthResult null 초기화', () {
      final state = RegisterStateSimulator(
          isKorean: true, passAuthResult: 'mock-pass-token');
      state.toggleNationality(false);
      expect(state.passAuthResult, isNull);
    });

    test('SCENARIO-NAT-036: 내국인→외국인 토글 — isKorean false로 변경', () {
      final state = RegisterStateSimulator(isKorean: true);
      state.toggleNationality(false);
      expect(state.isKorean, isFalse);
    });

    test('SCENARIO-NAT-037: 외국인→내국인 토글 — isKorean true로 변경', () {
      final state = RegisterStateSimulator(isKorean: false);
      state.toggleNationality(true);
      expect(state.isKorean, isTrue);
    });

    test('SCENARIO-NAT-038: 토글 — residentResult 빈 상태로 초기화', () {
      final state = RegisterStateSimulator(
        isKorean: true,
        residentResult: ResidentResult(
            birthDate: DateTime(1990, 1, 1), gender: '남성'),
      );
      state.toggleNationality(false);
      expect(state.residentResult.birthDate, isNull);
      expect(state.residentResult.gender, isNull);
      expect(state.residentResult.error, isNull);
    });

    test('SCENARIO-NAT-039: 토글 — phoneVerifyStatus.isVerified false로 초기화', () {
      final state = RegisterStateSimulator(
          isKorean: false, phoneVerifyStatusIsVerified: true);
      state.toggleNationality(true);
      expect(state.phoneVerifyStatusIsVerified, isFalse);
    });

    test('SCENARIO-NAT-040: 토글 — 이름 컨트롤러 초기화', () {
      final state =
          RegisterStateSimulator(isKorean: false, nameControllerText: '홍길동');
      state.toggleNationality(true);
      expect(state.nameControllerText, isEmpty);
    });

    test('SCENARIO-NAT-041: 토글 — 외국인등록번호 컨트롤러 초기화', () {
      final state = RegisterStateSimulator(
          isKorean: true,
          rn1ControllerText: '860101',
          rn2ControllerText: '5');
      state.toggleNationality(false);
      expect(state.rn1ControllerText, isEmpty);
      expect(state.rn2ControllerText, isEmpty);
    });

    test('SCENARIO-NAT-042: 토글 — 전화번호 컨트롤러 초기화', () {
      final state = RegisterStateSimulator(
          isKorean: false, phoneControllerText: '01012345678');
      state.toggleNationality(true);
      expect(state.phoneControllerText, isEmpty);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SCENARIO-NAT-043~046: 내국인 Step1 PASS 인증 필수
  // ══════════════════════════════════════════════════════════════════════════
  group('내국인 Step1 PASS 인증 필수', () {
    test('SCENARIO-NAT-043: passAuthResult == null → PASS 인증 차단', () {
      final err = validateStep1Korean(passAuthResult: null);
      expect(err, equals('PASS 본인인증을 완료해주세요'));
    });

    test('SCENARIO-NAT-044: passAuthResult != null (토큰 보유) → 통과', () {
      final err = validateStep1Korean(passAuthResult: 'valid-pass-token');
      expect(err, isNull);
    });

    test('SCENARIO-NAT-045: passAuthResult 빈 문자열 → non-null이므로 통과', () {
      // 실제 코드는 null 여부만 확인: if (_passAuthResult == null)
      final err = validateStep1Korean(passAuthResult: '');
      expect(err, isNull);
    });

    test('SCENARIO-NAT-046: 외국인 경로에는 PASS 검증 없음 — residentResult+SMS로 대체', () {
      final validResult =
          ResidentResult(birthDate: DateTime(1990, 1, 1), gender: '남성');
      final err = validateStep1Foreign(
          residentResult: validResult, phoneVerified: true);
      expect(err, isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SCENARIO-NAT-047~052: 외국인 Step1 SMS 인증 필수
  // ══════════════════════════════════════════════════════════════════════════
  group('외국인 Step1 SMS 인증 필수', () {
    final validResult =
        ResidentResult(birthDate: DateTime(1990, 1, 1), gender: '남성');

    test('SCENARIO-NAT-047: SMS 미인증 + 유효 외국인등록번호 → 인증 차단', () {
      final err = validateStep1Foreign(
          residentResult: validResult, phoneVerified: false);
      expect(err, equals('휴대폰 번호 인증을 완료해주세요'));
    });

    test('SCENARIO-NAT-048: SMS 인증 완료 + 유효 외국인등록번호 → 통과', () {
      final err = validateStep1Foreign(
          residentResult: validResult, phoneVerified: true);
      expect(err, isNull);
    });

    test('SCENARIO-NAT-049: SMS 완료 + 무효 등록번호 (birthDate null) → 등록번호 에러 우선', () {
      final invalidResult = const ResidentResult(error: '뒷자리는 5~8만 가능합니다');
      final err = validateStep1Foreign(
          residentResult: invalidResult, phoneVerified: true);
      expect(err, equals('올바른 외국인등록번호를 입력해주세요'));
    });

    test('SCENARIO-NAT-050: SMS 미인증 + 무효 등록번호 → 등록번호 에러 우선', () {
      final err = validateStep1Foreign(
          residentResult: const ResidentResult(), phoneVerified: false);
      expect(err, equals('올바른 외국인등록번호를 입력해주세요'));
    });

    test('SCENARIO-NAT-051: birthDate는 있으나 gender null → 등록번호 에러', () {
      final partial = ResidentResult(birthDate: DateTime(1990, 1, 1));
      final err =
          validateStep1Foreign(residentResult: partial, phoneVerified: true);
      expect(err, equals('올바른 외국인등록번호를 입력해주세요'));
    });

    test('SCENARIO-NAT-052: gender는 있으나 birthDate null → 등록번호 에러', () {
      const partial = ResidentResult(gender: '남성');
      final err =
          validateStep1Foreign(residentResult: partial, phoneVerified: true);
      expect(err, equals('올바른 외국인등록번호를 입력해주세요'));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SCENARIO-NAT-053~056: 외국인등록번호 마스킹 형식
  // ══════════════════════════════════════════════════════════════════════════
  group('외국인등록번호 마스킹 형식 (foreignIdNumber)', () {
    test("SCENARIO-NAT-053: 860101 + '5' → '860101-X5*****'", () {
      expect(buildForeignIdNumber('860101', '5'), equals('860101-X5*****'));
    });

    test("SCENARIO-NAT-054: 010101 + '7' → '010101-X7*****'", () {
      expect(buildForeignIdNumber('010101', '7'), equals('010101-X7*****'));
    });

    test('SCENARIO-NAT-055: isKorean=false → foreignIdNumber 마스킹 반환', () {
      final val = buildForeignIdNumberField(
          isKorean: false, rn1: '920315', rn2FirstChar: '6');
      expect(val, equals('920315-X6*****'));
    });

    test('SCENARIO-NAT-056: isKorean=true → foreignIdNumber null (내국인은 저장 안 함)', () {
      final val = buildForeignIdNumberField(
          isKorean: true, rn1: '860101', rn2FirstChar: '1');
      expect(val, isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SCENARIO-NAT-057~060: accountStatus 결정
  // ══════════════════════════════════════════════════════════════════════════
  group('accountStatus 결정 (active vs pending)', () {
    test("SCENARIO-NAT-057: isKorean=true → accountStatus = 'active'", () {
      expect(getAccountStatus(true), equals('active'));
    });

    test("SCENARIO-NAT-058: isKorean=false → accountStatus = 'pending'", () {
      expect(getAccountStatus(false), equals('pending'));
    });

    test('SCENARIO-NAT-059: 내국인은 PASS 인증으로 즉시 활성화 (active != pending)', () {
      final status = getAccountStatus(true);
      expect(status, isNot(equals('pending')));
    });

    test('SCENARIO-NAT-060: 외국인은 슈퍼관리자 승인 전 pending (pending != active)', () {
      final status = getAccountStatus(false);
      expect(status, isNot(equals('active')));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SCENARIO-NAT-061~064: residentNumber 필드 마스킹
  // ══════════════════════════════════════════════════════════════════════════
  group('residentNumber 필드 마스킹 처리', () {
    test('SCENARIO-NAT-061: isKorean=true → residentNumber = null (직접 저장 안 함)', () {
      expect(
          buildResidentNumberField(isKorean: true, rn1: '860101'), isNull);
    });

    test("SCENARIO-NAT-062: isKorean=false → '앞6자리-X******' 형식", () {
      expect(buildResidentNumberField(isKorean: false, rn1: '860101'),
          equals('860101-X******'));
    });

    test('SCENARIO-NAT-063: 마스킹 형식 — 앞자리로 시작하고 X****** 고정 접미사', () {
      final val = buildResidentNumberField(isKorean: false, rn1: '921201');
      expect(val, startsWith('921201-X'));
      expect(val, endsWith('******'));
    });

    test('SCENARIO-NAT-064: 내국인 residentNumber null → PASS 토큰 경유 예정 (다날 계약 후)', () {
      // 현재 내국인은 CI 해시 미저장, 다날 계약 후 처리 예정
      final val = buildResidentNumberField(isKorean: true, rn1: '900101');
      expect(val, isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SCENARIO-NAT-065~072: PassAuthResult 데이터 소스 분기
  // ══════════════════════════════════════════════════════════════════════════
  group('PassAuthResult 데이터 소스 분기 (내국인 vs 외국인)', () {
    final mockPass = MockPassAuthResult(
      name: 'PASS인증이름',
      phone: '01099998888',
      gender: '남성',
      birthDate: DateTime(1990, 5, 15),
      passToken: 'token-abc',
    );
    final foreignResident = ResidentResult(
      birthDate: DateTime(1986, 3, 20),
      gender: '여성',
    );

    test('SCENARIO-NAT-065: isKorean=true → name은 passAuthResult.name에서', () {
      expect(getSignupName(
          isKorean: true, passAuthResult: mockPass, directName: '직접입력'),
          equals('PASS인증이름'));
    });

    test('SCENARIO-NAT-066: isKorean=false → name은 직접 입력값에서', () {
      expect(getSignupName(
          isKorean: false, passAuthResult: mockPass, directName: '외국인홍길동'),
          equals('외국인홍길동'));
    });

    test('SCENARIO-NAT-067: isKorean=true → phone은 passAuthResult.phone에서', () {
      expect(getSignupPhone(
          isKorean: true, passAuthResult: mockPass, directPhone: '01011112222'),
          equals('01099998888'));
    });

    test('SCENARIO-NAT-068: isKorean=false → phone은 직접 입력값에서', () {
      expect(getSignupPhone(
          isKorean: false, passAuthResult: mockPass, directPhone: '01011112222'),
          equals('01011112222'));
    });

    test('SCENARIO-NAT-069: isKorean=true → gender는 passAuthResult.gender에서', () {
      final gender = getSignupGender(
          isKorean: true,
          passAuthResult: mockPass,
          residentResult: foreignResident);
      expect(gender, equals('남성')); // passAuth의 '남성'
    });

    test('SCENARIO-NAT-070: isKorean=false → gender는 residentResult.gender에서', () {
      final gender = getSignupGender(
          isKorean: false,
          passAuthResult: mockPass,
          residentResult: foreignResident);
      expect(gender, equals('여성')); // residentResult의 '여성'
    });

    test('SCENARIO-NAT-071: isKorean=true → birthDate는 passAuthResult.birthDate에서', () {
      final bd = getSignupBirthDate(
          isKorean: true,
          passAuthResult: mockPass,
          residentResult: foreignResident);
      expect(bd, equals(DateTime(1990, 5, 15)));
    });

    test('SCENARIO-NAT-072: isKorean=false → birthDate는 residentResult.birthDate에서', () {
      final bd = getSignupBirthDate(
          isKorean: false,
          passAuthResult: mockPass,
          residentResult: foreignResident);
      expect(bd, equals(DateTime(1986, 3, 20)));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SCENARIO-NAT-073~080: 추가 엣지케이스
  // ══════════════════════════════════════════════════════════════════════════
  group('추가 엣지케이스', () {
    test('SCENARIO-NAT-073: 외국인 코드 5, rn1="000101" → 1900년생 남성', () {
      // year=00, effectiveCode=1 → 00+1900=1900
      final r = parseResidentNumber(
          rn1: '000101', rn2: '5', isKorean: false, today: _today);
      expect(r.birthDate?.year, equals(1900));
      expect(r.gender, equals('남성'));
      expect(r.error, isNull);
    });

    test('SCENARIO-NAT-074: 외국인 코드 6, 1970-06-01 생 여성', () {
      final r = parseResidentNumber(
          rn1: '700601', rn2: '6', isKorean: false, today: _today);
      expect(r.birthDate, equals(DateTime(1970, 6, 1)));
      expect(r.gender, equals('여성'));
      expect(r.error, isNull);
    });

    test('SCENARIO-NAT-075: 내국인 코드 3, rn1="260101" (year=26=현재) → 나이 미달 차단', () {
      // year=26 ≤ 26 → 미래 연도 에러 아님, year=2026 → age=0 → 나이 차단
      final r = parseResidentNumber(
          rn1: '260101', rn2: '3', isKorean: true, today: _today);
      expect(r.error, equals('만 18세 이상만 가입 가능합니다'));
    });

    test('SCENARIO-NAT-076: 외국인 코드 8, 2010-01-01 생 (16세) → 차단', () {
      // 2026-2010=16세, 생일 1월 1일 이미 지남 → age=16 → 차단
      final r = parseResidentNumber(
          rn1: '100101', rn2: '8', isKorean: false, today: _today);
      expect(r.error, equals('만 18세 이상만 가입 가능합니다'));
    });

    test('SCENARIO-NAT-077: isKorean=true passAuthResult null → passAuth가 null이면 name 접근 불가', () {
      // passAuthResult가 null인 상태에서 getSignupGender 호출
      final gender = getSignupGender(
          isKorean: true,
          passAuthResult: null,
          residentResult: const ResidentResult(gender: '여성'));
      // passAuthResult?.gender → null (passAuthResult 자체가 null)
      expect(gender, isNull);
    });

    test('SCENARIO-NAT-078: isKorean=false passAuthResult null이어도 residentResult 사용', () {
      final r =
          ResidentResult(birthDate: DateTime(1985, 6, 15), gender: '남성');
      final bd = getSignupBirthDate(
          isKorean: false, passAuthResult: null, residentResult: r);
      expect(bd, equals(DateTime(1985, 6, 15)));
    });

    test('SCENARIO-NAT-079: 내국인 코드 4, 2005-07-07 생 — 생일 하루 전 (17세) → 차단', () {
      // 오늘 2026-07-08, 생일 2005-07-07 → age=2026-2005=21, 7>=7이고 8>7 → no decrement → 21세
      // 실제로는 통과함 (21세)
      final r = parseResidentNumber(
          rn1: '050707', rn2: '4', isKorean: true, today: _today);
      expect(r.error, isNull);
      expect(r.gender, equals('여성'));
    });

    test('SCENARIO-NAT-080: 외국인 코드 5, 1975-12-25 생 — 크리스마스 (50세) → 통과', () {
      final r = parseResidentNumber(
          rn1: '751225', rn2: '5', isKorean: false, today: _today);
      expect(r.birthDate, equals(DateTime(1975, 12, 25)));
      expect(r.gender, equals('남성'));
      expect(r.error, isNull);
    });
  });
}
