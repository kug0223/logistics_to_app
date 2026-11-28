// [ALFIT-AUTH-KAKAO-ONBOARDING.1 · 판정278 C278-3 · 시험 공용] users/{userId} 문서의 클라이언트 create 규칙.
//
//   판정278 로 rules 의 users create 는 `allow create: if false;`(전면 거부)가 됐다. 예전 시험들은
//   "create 때 서버 전용 필드 X 를 주입할 수 없다" 를 `request.resource.data.get('X', null) == null`
//   문구로 고정했다. 전면 거부는 그 조건들보다 **강한** 같은 결론이다 — 의도(클라 create 로 서버 전용
//   필드를 심을 수 없다)를 유지하면서, 규칙이 다시 열리면(전면 거부가 아니게 되면) 옛 필드 조건을
//   그대로 요구한다. 검증을 약하게 하지 않는다.

/// users/{userId} 블록의 첫 `allow create:` 문장(세미콜론까지). 없으면 StateError.
String usersCreateRule(String rules) {
  final m = rules.indexOf('match /users/{userId} {');
  if (m < 0) throw StateError('match /users/{userId} 를 찾지 못함');
  final a = rules.indexOf('allow create:', m);
  if (a < 0) throw StateError('users create 규칙을 찾지 못함');
  final b = rules.indexOf(';', a);
  return rules.substring(a, b + 1);
}

/// 클라이언트 users create 가 전면 거부인가.
bool usersCreateClosed(String rules) =>
    usersCreateRule(rules).replaceAll(RegExp(r'\s+'), ' ').trim() == 'allow create: if false;';

/// create 로 [field] 를 심을 수 없는가 — 전면 거부이거나, 열려 있다면 옛 null 조건이 있어야 한다.
bool usersCreateDeniesField(String rules, String field) =>
    usersCreateClosed(rules) ||
    rules.contains("request.resource.data.get('$field', null) == null");

/// 주석 줄을 빼고 공백을 한 칸으로 접은 rules 본문(조건 사이에 설명 주석이 끼어도 같은 문장으로 읽는다).
String rulesCodeFlat(String raw) => raw
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n')
    .replaceAll(RegExp(r'\s+'), ' ');
