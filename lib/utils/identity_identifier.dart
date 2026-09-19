// lib/utils/identity_identifier.dart
//
// [PII-DOC-R1.2] 신분증 대조에 쓰는 **기대 식별번호**와 대조 결과의 어휘.
//
// 이전에는 기대값 계산이 화면(document_management_screen) 안에 있었고
// 국적 개념이 없었다. 그래서 두 모집단이 정반대로 깨졌다:
//
//   V3 외국인    birthDate·gender가 null → 기대값 null → **비교를 건너뛰고**
//                `isResidentNumberValid`의 기본값 true가 그대로 올라갔다.
//                검사하지 않은 사실이 "일치"가 됐다.
//
//   레거시 외국인 users에는 내국인식 1~4로 환산돼 저장되는데 기대값을 만들 때
//                다시 1~4를 찍었다. 등록증에는 5~8이 적혀 있으므로 항상 불일치.
//
// 두 버그의 뿌리는 같다 — **비교 기준을 만드는 규칙이 한 곳에 없었다.**
// 여기가 그 한 곳이다.

import '../models/core/user_model.dart';

/// 한 항목(이름·식별번호)을 대조한 결과.
///
/// `MATCHED`가 아닌 것을 전부 "불일치"로 뭉뚱그리지 않는다 — 관리자도
/// 사용자도 그 셋에 대해 해야 할 일이 다르다.
enum DocFieldOutcome {
  /// 비교를 수행했고 일치했다.
  matched,

  /// 비교를 수행했고 달랐다.
  mismatch,

  /// 비교는 시도했으나 서류에서 그 값을 **읽지 못했다**.
  /// 불일치가 아니다 — 무엇인지 모르는 것이다.
  unreadable,

  /// 비교 자체를 하지 못했다. 기준이 없거나 관측이 없다.
  /// `UNASSESSED ≠ MISMATCH`, `UNASSESSED ≠ MATCHED`.
  unassessed,
}

extension DocFieldOutcomeWire on DocFieldOutcome {
  /// 서버로 보내는 값. 서버 `SrvDocFieldOutcome`과 **같은 문자열**이어야 한다.
  String get wire => switch (this) {
        DocFieldOutcome.matched => 'MATCHED',
        DocFieldOutcome.mismatch => 'MISMATCH',
        DocFieldOutcome.unreadable => 'UNREADABLE',
        DocFieldOutcome.unassessed => 'UNASSESSED',
      };
}

/// 신분증 대조 기준 — 기대 식별번호 앞 7자리.
class ExpectedIdentifier {
  /// `"YYMMDD-G"` 형식. 비교할 수 없으면 null.
  final String? prefix;

  /// 비교 기준이 존재하는가. false면 결과는 [DocFieldOutcome.unassessed]다.
  bool get assessable => prefix != null;

  const ExpectedIdentifier(this.prefix);

  static const ExpectedIdentifier none = ExpectedIdentifier(null);
}

/// 저장된 신원 정보에서 기대 식별번호 앞 7자리를 만든다.
///
/// 성별코드 규칙 (공적 규칙):
///
/// ```
///            1900년대생   2000년대생
///   내국인    남 1 / 여 2   남 3 / 여 4
///   외국인    남 5 / 여 6   남 7 / 여 8
/// ```
///
/// `users.gender` / `users.birthDate`는 **내국인식으로 환산된 값**이다
/// (register_screen이 외국인등록번호를 `-4` 이동해 파싱한다). 그래서 외국인은
/// 같은 규칙으로 1~4를 구한 뒤 `+4`를 되돌린다 — 같은 변환을 화면마다
/// 복사하지 않기 위해 여기서만 한다.
///
/// [isForeign]은 호출자가 canonical predicate(`UserModel.isForeign` — 파생
/// getter)로 판정해 넘긴다. Firestore의 `isForeign` 필드는 writer가 없으므로
/// 절대 쓰지 않는다. [PII-DOC-R1.1]
ExpectedIdentifier expectedIdentifierFrom({
  required DateTime? birthDate,
  required String? gender,
  required bool isForeign,
}) {
  // 기준이 없으면 만들어내지 않는다. 임의 계산은 거짓 불일치를 낳는다.
  if (birthDate == null || gender == null || gender.isEmpty) {
    return ExpectedIdentifier.none;
  }
  final yy = (birthDate.year % 100).toString().padLeft(2, '0');
  final mm = birthDate.month.toString().padLeft(2, '0');
  final dd = birthDate.day.toString().padLeft(2, '0');

  final isMale = gender == '남성';
  // 내국인 기준 코드 — 저장된 gender/birthDate가 이 형태로 환산돼 있다.
  final nativeCode = birthDate.year >= 2000 ? (isMale ? 3 : 4) : (isMale ? 1 : 2);
  // 외국인은 같은 세기·성별의 코드가 +4다.
  final code = isForeign ? nativeCode + 4 : nativeCode;

  return ExpectedIdentifier('$yy$mm$dd-$code');
}

/// [UserModel]에서 바로 만드는 편의 래퍼.
ExpectedIdentifier expectedIdentifierForUser(UserModel user) =>
    expectedIdentifierFrom(
      birthDate: user.birthDate,
      gender: user.gender,
      // 파생 getter — foreignIdentityFingerprint / foreignIdNumber 기반.
      isForeign: user.isForeign,
    );
