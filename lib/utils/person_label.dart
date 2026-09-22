// lib/utils/person_label.dart
//
// [R7-PRE1A.1] 사업장 안에서 사람을 가리키는 번호의 **표기**.
//
// 번호 자체는 서버가 준다(businesses/{bizId}/persons/{uid}.personNo).
// 여기는 그것을 사람이 읽는 모양으로 바꾸는 한 곳이다 — 목록, 확인 문구,
// Excel 컬럼, PDF, 파일명이 전부 이 함수를 지난다.
//
// 한 곳에 모으는 이유: 접두사나 자릿수를 바꾸는 순간, 화면에는 새 표기가
// 나가고 지난달 Excel 에는 옛 표기가 남는 식으로 갈라지기 때문이다.
// 같은 사람이 두 표기로 보이면 번호를 만든 이유가 없어진다.

class PersonLabel {
  PersonLabel._();

  /// 표기 접두사. 번호의 의미는 "이 사업장에서 몇 번째로 관계가 생긴 사람인가"다.
  static const String prefix = 'W';

  /// 최소 자릿수. 넘어가면 자연스럽게 늘어난다(999 → 1000).
  static const int minDigits = 3;

  /// `14` → `W-014`. 번호가 없으면 null — 빈 문자열이 아니다.
  ///
  /// null 과 '' 를 구분한다: 호출부가 "번호 칸을 비운다"와 "번호가 빈 문자열이다"를
  /// 다르게 다뤄야 하고, 특히 파일명에서는 후자가 `_이름_...` 같은 모양을 만든다.
  static String? of(int? personNo) {
    if (personNo == null || personNo <= 0) return null;
    return '$prefix-${personNo.toString().padLeft(minDigits, '0')}';
  }

  /// 이름 아래 한 줄로 쓰는 보조 문구 — `W-014 · 30대`.
  ///
  /// badge 가 아니라 secondary text 다. 번호는 상태가 아니라 참고정보이고,
  /// badge 로 만들면 "처리할 일"처럼 읽힌다.
  static String secondary(int? personNo, [String? extra]) {
    final label = of(personNo);
    final rest = (extra ?? '').trim();
    if (label == null) return rest;
    if (rest.isEmpty) return label;
    return '$label · $rest';
  }

  /// 파일명에 쓸 조각. 번호가 없으면 빈 문자열이라 앞뒤 구분자가 붙지 않는다.
  static String filePart(int? personNo) {
    final label = of(personNo);
    return label == null ? '' : '${label}_';
  }

  /// 파일명에서 쓸 수 없는 문자를 없앤다.
  ///
  /// 사업장명·사람 이름이 그대로 파일명에 들어간다. Windows 는 `\ / : * ? " < > |`
  /// 를 거부하고, 공유 시트를 지나면서 조용히 깨지는 경우도 있다.
  /// 이름을 바꾸는 것이 아니라 **파일명만** 안전하게 만든다.
  static String safeFileName(String raw) {
    final cleaned = raw
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    // 끝의 마침표·공백은 Windows 가 잘라 낸다 — 미리 없앤다.
    final trimmed = cleaned.replaceAll(RegExp(r'[. ]+$'), '');
    return trimmed.isEmpty ? '이름없음' : trimmed;
  }

  /// Excel 시트 이름 제약: 31자, `: \ / ? * [ ]` 불가, 앞뒤 작은따옴표 불가.
  ///
  /// 사업장명을 시트 이름으로 쓰는 곳이 있다. 규칙을 어기면 파일이 열리지
  /// 않거나 시트가 통째로 사라진다 — 내보내기가 성공한 것처럼 보이면서.
  static String safeSheetName(String raw) {
    var s = raw.replaceAll(RegExp(r"[:\\/?*\[\]]"), '_').trim();
    s = s.replaceAll(RegExp(r"^'+|'+$"), '');
    if (s.length > 31) s = s.substring(0, 31);
    return s.isEmpty ? '시트' : s;
  }
}
