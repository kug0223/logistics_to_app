import '../models/core/to_model.dart';
import '../models/core/work_detail_data.dart';
import '../models/ui/admin_to_list_ui_models.dart';

/// 마감 상태 판단 — 단일 진실 소스
///
/// TOGroupItem.isClosed / admin_to_group_card / admin_to_item_card 모두 이 함수를 사용.
/// 이 파일 하나만 수정하면 모든 레이어에 반영됨.
///
/// 판단 우선순위:
///   1. 날짜 경과 → 마감
///   2. 관리자 직접 마감 (slot.closedBy != null) → 마감
///   3. 인원 충족 → 마감
///   4. 업무상세 전부 마감 → 마감
///   5. 업무상세 없음 → 열림
class CloseStateUtils {

  /// 슬롯 단위 마감 여부 (카드 배지, 탭 필터 공용)
  ///
  /// [toItem]      — 판단 대상 슬롯
  /// [masterTO]    — 하위 호환 유지용 (내부에서 미사용 — applicationDeadline이 항상 저장됨)
  /// [now]         — 현재 시각 (테스트 주입 가능)
  /// [localConfirmed] / [localRequired] — 카드에서 집계한 인원 (null이면 toItem 값 사용)
  static bool isToItemClosed(
    TOItem toItem,
    TOModel masterTO,
    DateTime now, {
    int? localConfirmed,
    int? localRequired,
  }) {
    final slot = toItem.slot;
    final today = DateTime(now.year, now.month, now.day);

    // 슬롯 없음 → 판단 불가 → 열림 처리
    if (slot == null) return false;

    // 0. TO 레벨 수동마감 — CF 슬롯 갱신 전(최대 30분)에도 즉시 마감 반영
    if (masterTO.isManualClosed) return true;

    // 1. 날짜 경과
    if (DateTime(slot.date.year, slot.date.month, slot.date.day).isBefore(today)) return true;

    // 2. 관리자 직접 마감 (closedBy 설정)
    if (slot.closedBy != null) return true;

    // 3. 인원 충족 (로컬 집계 우선, 없으면 toItem 값)
    final confirmed = localConfirmed ?? toItem.confirmedCount;
    final required  = localRequired  ?? toItem.totalRequired;
    if (required > 0 && confirmed >= required) return true;
    if (slot.isFull) return true;

    // 4. 업무상세 기반 판단
    final details = _effectiveDetails(toItem);
    if (details.isEmpty) return false;

    return details.every((d) => _isDetailClosed(d, now));
  }

  /// 업무상세 단위 마감 여부 — now를 주입받아 DateTime.now() 호출 없이 판단
  static bool _isDetailClosed(WorkDetailData d, DateTime now) {
    // 수동 마감
    if (d.isManualClosed || d.closedAt != null) return true;

    // 마감 시간 경과 — applicationDeadline은 슬롯 생성·수정 시 항상 저장됨
    if (d.applicationDeadline != null && now.isAfter(d.applicationDeadline!)) return true;

    return false;
  }

  /// 사용할 업무상세 결정 (로드된 것 우선, 없으면 슬롯 내장)
  static List<WorkDetailData> _effectiveDetails(TOItem toItem) {
    if (toItem.isWorkDetailLoaded && toItem.workDetails.isNotEmpty) {
      return toItem.workDetails;
    }
    final slotDetails = toItem.slot?.workDetails ?? [];
    return slotDetails.isNotEmpty ? slotDetails : toItem.workDetails;
  }
}
