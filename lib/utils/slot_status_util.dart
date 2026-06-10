import '../models/core/slot_model.dart';
import '../models/core/to_model.dart';
import '../models/ui/admin_to_list_ui_models.dart';

enum SlotDisplayStatus { draft, closed, scheduled, recruiting }

/// 슬롯/TO 상태 표시 계산 — 단일 진실 소스
///
/// 모든 배지 위젯은 이 유틸리티를 통해 상태를 계산해야 한다.
class SlotStatusUtil {
  SlotStatusUtil._();

  // ──────────────────────────────────────────────────────
  // 개별 슬롯 상태
  // ──────────────────────────────────────────────────────

  /// 슬롯 하나의 표시 상태 계산
  static SlotDisplayStatus slotStatus(SlotModel slot, TOModel to) {
    // 1. 미공개 (TO가 draft 상태)
    if (!to.isPublished && to.status == TOStatus.draft) {
      return SlotDisplayStatus.draft;
    }
    // 2. 마감 (날짜경과 / 수동마감 / 인원충족 / 업무마감)
    if (slot.isEffectivelyClosed) return SlotDisplayStatus.closed;
    // 3. 슬롯 레벨 예약 공개 대기
    final now = DateTime.now();
    if (slot.visibleFrom != null && slot.visibleFrom!.isAfter(now)) {
      return SlotDisplayStatus.scheduled;
    }
    // 4. TO 레벨 예약 공개 대기
    if (to.isPendingPublish) return SlotDisplayStatus.scheduled;
    // 5. 모집중
    return SlotDisplayStatus.recruiting;
  }

  /// 슬롯의 예약 배지에 표시할 시각 (슬롯 visibleFrom 우선, 없으면 TO publishAt)
  static DateTime? slotScheduledAt(SlotModel slot, TOModel to) {
    final now = DateTime.now();
    if (slot.visibleFrom != null && slot.visibleFrom!.isAfter(now)) {
      return slot.visibleFrom;
    }
    return to.publishAt;
  }

  // ──────────────────────────────────────────────────────
  // 그룹(TO 묶음) 상태 — admin_to_group_card 전용
  // ──────────────────────────────────────────────────────

  /// 그룹 카드 표시 상태 계산
  static SlotDisplayStatus groupStatus({
    required bool allClosed,
    required TOModel masterTO,
    required List<TOItem> targetTOs,
  }) {
    // 1. 전체 마감
    if (allClosed) return SlotDisplayStatus.closed;

    // contract TO: targetTOs가 없으므로 masterTO로 판단
    if (targetTOs.isEmpty) {
      if (masterTO.status == TOStatus.draft) return SlotDisplayStatus.draft;
      if (masterTO.isPendingPublish) return SlotDisplayStatus.scheduled;
      return SlotDisplayStatus.recruiting;
    }

    // 2. 공개된 TO가 있으면 슬롯 visibleFrom 기준 판단
    final now = DateTime.now();
    final publishedTOs = targetTOs.where((ti) => ti.to.isPublished).toList();
    if (publishedTOs.isNotEmpty) {
      final allSlotScheduled = publishedTOs.every((ti) =>
          ti.slot?.visibleFrom != null && ti.slot!.visibleFrom!.isAfter(now));
      return allSlotScheduled
          ? SlotDisplayStatus.scheduled
          : SlotDisplayStatus.recruiting;
    }

    // 3. TO 레벨 예약 공개 대기
    if (targetTOs.any((ti) => ti.to.isPendingPublish)) {
      return SlotDisplayStatus.scheduled;
    }

    // 4. 미공개
    return SlotDisplayStatus.draft;
  }

  /// 그룹 예약 배지에 표시할 시각
  static DateTime? groupScheduledAt({
    required TOModel masterTO,
    required List<TOItem> targetTOs,
  }) {
    if (targetTOs.isEmpty) return masterTO.publishAt;

    final now = DateTime.now();
    // 공개된 슬롯들의 가장 이른 미래 visibleFrom
    final slotEarliest = targetTOs
        .where((ti) => ti.to.isPublished)
        .map((ti) => ti.slot?.visibleFrom)
        .whereType<DateTime>()
        .where((vf) => vf.isAfter(now))
        .fold<DateTime?>(null, (e, vf) => e == null || vf.isBefore(e) ? vf : e);
    if (slotEarliest != null) return slotEarliest;

    // TO 레벨 예약
    return targetTOs
        .where((ti) => ti.to.isPendingPublish)
        .map((ti) => ti.to.publishAt)
        .whereType<DateTime>()
        .fold<DateTime?>(null, (e, vf) => e == null || vf.isBefore(e) ? vf : e);
  }
}
