// [POSTING-V2-02F.1] 관리자 탭 상단 사업장 scope 표시 문구.
//
// scope는 "이 탭에서 공고·근무를 조회할 수 있는 사업장 범위"다.
// 다음 셋과 구별한다:
//   · Filter                — 그 범위 중 현재 목록을 좁힌 조건 (필터 버튼 뱃지가 표현)
//   · effectiveBusinessId   — Home context / CreateTO 시작점 (범위가 아니다)
//   · 공고가 실제 존재하는 사업장 집합 — 데이터 분포일 뿐 권한 범위가 아니다
//
// 이전에는 두 가지가 섞여 있었다.
//   BUSINESS_ADMIN : 로드된 공고의 사업장 이름 집합 크기로 범위를 판정해,
//                    A/B/C를 관리해도 공고가 A에만 있으면 'A 사업장'이 됐다.
//                    공고가 B에 생기는 순간 '전체 사업장'으로 바뀌어,
//                    권한이 아니라 데이터 분포에 따라 문구가 흔들렸다.
//   SUB_ADMIN      : effectiveBusinessId 한 곳만 표시해, A/B 배정 관리자가
//                    A·B 공고가 섞인 목록 위에서 'A 사업장'을 봤다.
//                    Home에서 사업장을 바꾸면 같은 목록의 이름표만 갈렸다.
//
// 판정은 businessIds 목록 하나로만 한다 — 전부 메모리 값이라 조회가 없다.

/// 관리자 탭 scope chip 문구를 만든다.
///
/// [isSuperAdmin]            SUPER_ADMIN 여부. 가장 먼저 판정한다.
/// [isSubAdmin]              SUB_ADMIN 여부.
/// [managedBusinessIds]      BUSINESS_ADMIN이 관리하는 사업장 전체.
/// [subAdminBusinessIds]     SUB_ADMIN이 배정받은 사업장 전체.
/// [subAdminBusinessNames]   bizId → 이름 (UserProvider 캐시). 단일 배정에서만 쓴다.
/// [loadedBusinessNames]     마지막 성공 로드에서 확보한 사업장 이름.
///                           BUSINESS_ADMIN 단일 사업장의 이름 source다.
///                           **범위 판정에는 쓰지 않는다.**
///
/// 반환이 빈 문자열이면 chip을 표시하지 않는다.
String resolveAdminBusinessScopeLabel({
  required bool isSuperAdmin,
  required bool isSubAdmin,
  required List<String> managedBusinessIds,
  required List<String> subAdminBusinessIds,
  required Map<String, String> subAdminBusinessNames,
  required List<String> loadedBusinessNames,
}) {
  // SUPER_ADMIN은 businessIds 목록으로 범위가 정해지지 않는다 —
  // WorkforceController.load()가 businessIds = null을 보내 서버가 전체를 조회한다.
  // 그래서 managedBusinessIds가 비어 있어도 "범위 없음"이 아니라 "전체"다.
  // 역할 판정을 가장 먼저 두어 일반 관리자의 진짜 빈 범위와 섞이지 않게 한다.
  if (isSuperAdmin) return '전체 사업장';

  final ids = isSubAdmin ? subAdminBusinessIds : managedBusinessIds;

  // 정상 진입에서는 도달하지 않는다(범위가 없으면 탭 자체가 없다).
  // 새 에러 표면을 만들지 않고 chip만 숨긴다.
  if (ids.isEmpty) return '';

  if (ids.length >= 2) {
    // SUB_ADMIN에게 '전체 사업장'은 쓰지 않는다 — 회사 전체(owner 범위)로 읽힌다.
    // 배정 사업장은 owner 사업장의 부분집합이다.
    return isSubAdmin ? '담당 사업장 ${ids.length}곳' : '전체 사업장';
  }

  // 단일 사업장 — 이름을 이미 알고 있으면 이름으로 말한다.
  if (isSubAdmin) {
    final name = subAdminBusinessNames[ids.first];
    if (name != null && name.isNotEmpty) return name;
    return '내 사업장';
  }

  final known = loadedBusinessNames.where((n) => n.isNotEmpty).toSet();
  if (known.length == 1) return known.first;
  // 이름 미확보(공고 0건 등) — businessId 원문을 노출하지 않는다.
  return '내 사업장';
}
