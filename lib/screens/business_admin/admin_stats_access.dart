import '../../providers/user_provider.dart';

/// [ADMIN-STATS-CLOSEOUT] 통계(연간·월 상세·Excel)는 **조회 대상 사업장마다** 급여 권한으로 연다.
///
///   설정 메뉴는 '현재 사업장' 권한으로 보이지만 고를 수 있는 사업장은 배정된 전부다.
///   급여 권한이 없는 사업장은 서버가 금액 필드를 빼고 주므로, 화면이 그걸 0원·'미확정'으로
///   그렸다(LOCAL 재현). 화면은 불러오기·내보내기 직전마다 이 판정을 다시 본다.
///   확인하지 못한 상태(unknown·error)는 허용이 아니다. 서버 권한 검사를 대신하지 않는다.
class AdminStatsAccess {
  AdminStatsAccess._();

  static PermissionCheck check(UserProvider up, List<String> businessIds) {
    if (businessIds.isEmpty) return PermissionCheck.denied;
    var result = PermissionCheck.allowed;
    for (final id in businessIds) {
      final c = up.checkForBusiness(id, (p) => p.canManageWage);
      if (c == PermissionCheck.denied) return PermissionCheck.denied;
      if (c != PermissionCheck.allowed) result = c;
    }
    return result;
  }

  static String title(PermissionCheck c) => c == PermissionCheck.denied
      ? '이 사업장의 급여 관리 권한이 없어요'
      : '권한을 확인하지 못했어요';

  static String subtitle(PermissionCheck c) => c == PermissionCheck.denied
      ? '통계와 엑셀은 급여 관리 권한이 있는 사업장에서만 볼 수 있어요.'
      : '잠시 후 다시 시도해 주세요.';
}
