// test/simulation/to_management_flow_simulation_test.dart
//
// 관리자 TO(공고) 등록/수정/삭제 및 상태 흐름 시나리오 시뮬레이션 테스트
//
// 검증 범위:
//   1. TOStatus 상수 및 isClosed 판단 로직
//   2. _syncTOCascadeStatus 로직 (슬롯 상태 → TO 상태 동기화)
//   3. MAX_ACTIVE_TO_LIMIT 체크
//   4. createTO 비공개→공개 단계 순서 (flex 즉시공개)
//   5. 4가지 edit_to_screen 모드
//   6. batchCloseSlots 순서 (A-001: 슬롯 마감 먼저 → PENDING 취소)
//   7. batchReopenSlots (full 슬롯 재오픈 차단)
//   8. CloseStateUtils.isToItemClosed() 판단 우선순위
//   9. TO update 불변 필드 보호 (CLOSED/EXPIRED 상태)
//  10. updateSlotsDeadlines 마감시간 재계산
//
// Firebase 의존성 없음 — 순수 Dart 로직만 검증
//
// 실행: flutter test test/simulation/to_management_flow_simulation_test.dart

import 'package:flutter_test/flutter_test.dart';

// ══════════════════════════════════════════════════════════════════════════════
// 테스트용 경량 상수 (TOStatus, TOType, SlotStatus 재현)
// ══════════════════════════════════════════════════════════════════════════════

abstract class _TOStatus {
  static const String active    = 'ACTIVE';
  static const String closed    = 'CLOSED';
  static const String full      = 'FULL';
  static const String expired   = 'EXPIRED';
  static const String scheduled = 'SCHEDULED';
  static const String draft     = 'DRAFT';

  static const List<String> openStates   = [active, full, scheduled];
  static const List<String> closedStates = [closed, expired];
}

abstract class _TOType {
  static const String flex     = 'flex';
  static const String contract = 'contract';
}

abstract class _SlotStatus {
  static const String open   = 'open';
  static const String full   = 'full';
  static const String closed = 'closed';
}

// ══════════════════════════════════════════════════════════════════════════════
// 테스트용 경량 모델
// ══════════════════════════════════════════════════════════════════════════════

/// WorkDetailData 핵심 필드 재현
class _WorkDetail {
  final String workType;
  final int requiredCount;
  final String startTime;
  final String endTime;
  final bool isManualClosed;
  final DateTime? closedAt;
  final DateTime? applicationDeadline;

  const _WorkDetail({
    required this.workType,
    this.requiredCount = 1,
    this.startTime = '09:00',
    this.endTime = '18:00',
    this.isManualClosed = false,
    this.closedAt,
    this.applicationDeadline,
  });

  bool get isClosed => isManualClosed || closedAt != null;
  bool get isTimeExpired =>
      applicationDeadline != null && DateTime.now().isAfter(applicationDeadline!);

  _WorkDetail copyWith({
    String? workType,
    int? requiredCount,
    String? startTime,
    String? endTime,
    bool? isManualClosed,
    DateTime? closedAt,
    DateTime? applicationDeadline,
  }) {
    return _WorkDetail(
      workType: workType ?? this.workType,
      requiredCount: requiredCount ?? this.requiredCount,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      isManualClosed: isManualClosed ?? this.isManualClosed,
      closedAt: closedAt ?? this.closedAt,
      applicationDeadline: applicationDeadline ?? this.applicationDeadline,
    );
  }
}

/// SlotModel 핵심 필드 재현
class _Slot {
  final String id;
  final String toId;
  final DateTime date;
  final String status;
  final bool isManualClosed;
  final String? closedBy;
  final DateTime? closedAt;
  final String? reopenedBy;
  final DateTime? reopenedAt;
  final int confirmedCount;
  final int pendingCount;
  final List<_WorkDetail> workDetails;

  const _Slot({
    required this.id,
    required this.toId,
    required this.date,
    this.status = _SlotStatus.open,
    this.isManualClosed = false,
    this.closedBy,
    this.closedAt,
    this.reopenedBy,
    this.reopenedAt,
    this.confirmedCount = 0,
    this.pendingCount = 0,
    this.workDetails = const [],
  });

  int get totalRequired =>
      workDetails.fold(0, (acc, d) => acc + d.requiredCount);

  bool get isFull =>
      totalRequired > 0 && confirmedCount >= totalRequired;

  bool get isOpen => status == _SlotStatus.open;
  bool get isClosed => status == _SlotStatus.closed;
  bool get isFullStatus => status == _SlotStatus.full;

  _Slot copyWith({
    String? status,
    bool? isManualClosed,
    String? closedBy,
    DateTime? closedAt,
    String? reopenedBy,
    DateTime? reopenedAt,
    int? confirmedCount,
  }) {
    return _Slot(
      id: id,
      toId: toId,
      date: date,
      status: status ?? this.status,
      isManualClosed: isManualClosed ?? this.isManualClosed,
      closedBy: closedBy ?? this.closedBy,
      closedAt: closedAt ?? this.closedAt,
      reopenedBy: reopenedBy ?? this.reopenedBy,
      reopenedAt: reopenedAt ?? this.reopenedAt,
      confirmedCount: confirmedCount ?? this.confirmedCount,
      pendingCount: pendingCount,
      workDetails: workDetails,
    );
  }
}

/// TOModel 핵심 필드 재현
class _TOModel {
  final String id;
  final String type;
  final String status;
  final bool isManualClosed;
  final bool isPublished;
  final int totalRequired;
  final int totalConfirmed;
  final int totalPending;
  final DateTime? applicationDeadline;
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final int? postingDurationDays;
  final DateTime? publishAt;
  final DateTime createdAt;

  const _TOModel({
    required this.id,
    this.type = _TOType.flex,
    this.status = _TOStatus.active,
    this.isManualClosed = false,
    this.isPublished = true,
    this.totalRequired = 0,
    this.totalConfirmed = 0,
    this.totalPending = 0,
    this.applicationDeadline,
    this.rangeStart,
    this.rangeEnd,
    this.postingDurationDays,
    this.publishAt,
    required this.createdAt,
  });

  bool get isFlexType     => type == _TOType.flex;
  bool get isContractType => type == _TOType.contract;

  bool get isFull => totalRequired > 0 && totalConfirmed >= totalRequired;

  bool get isDeadlinePassed {
    if (applicationDeadline == null) return false;
    return DateTime.now().isAfter(applicationDeadline!);
  }

  DateTime? get postingExpiryDate {
    if (postingDurationDays == null) return null;
    final base = publishAt ?? createdAt;
    return base.add(Duration(days: postingDurationDays!));
  }

  bool get isPostingExpired {
    final d = postingExpiryDate;
    if (d == null) return false;
    final now = DateTime.now();
    final today  = DateTime(now.year, now.month, now.day);
    final expiry = DateTime(d.year, d.month, d.day);
    return today.isAfter(expiry);
  }

  bool get isClosed =>
      isManualClosed ||
      isFull ||
      status == _TOStatus.closed ||
      status == _TOStatus.expired ||
      (isContractType && (isPostingExpired || isDeadlinePassed));

  _TOModel copyWith({
    String? status,
    bool? isManualClosed,
    bool? isPublished,
    int? totalRequired,
    int? totalConfirmed,
  }) {
    return _TOModel(
      id: id,
      type: type,
      status: status ?? this.status,
      isManualClosed: isManualClosed ?? this.isManualClosed,
      isPublished: isPublished ?? this.isPublished,
      totalRequired: totalRequired ?? this.totalRequired,
      totalConfirmed: totalConfirmed ?? this.totalConfirmed,
      totalPending: totalPending,
      applicationDeadline: applicationDeadline,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      postingDurationDays: postingDurationDays,
      publishAt: publishAt,
      createdAt: createdAt,
    );
  }
}

/// TOItem (CloseStateUtils 테스트용 — 슬롯 단위 아이템)
class _TOItem {
  final _TOModel to;
  final _Slot? slot;
  final List<_WorkDetail> workDetails;
  final int confirmedCount;
  final int totalRequired;
  final bool isWorkDetailLoaded;

  const _TOItem({
    required this.to,
    this.slot,
    this.workDetails = const [],
    required this.confirmedCount,
    required this.totalRequired,
    this.isWorkDetailLoaded = false,
  });
}

// ══════════════════════════════════════════════════════════════════════════════
// 순수 로직 함수 (프로덕션 로직 재현)
// ══════════════════════════════════════════════════════════════════════════════

// ── 1. isClosed 판단 ─────────────────────────────────────────────────────────

bool _isToModelClosed(_TOModel to) => to.isClosed;

// ── 2. _syncTOCascadeStatus (슬롯 상태 → TO 상태 동기화) ─────────────────────

/// 슬롯 일괄 마감/재오픈 후 TO 상태를 동기화.
/// - open/full 슬롯 있음 + TO가 CLOSED → TO를 ACTIVE로
/// - open/full 슬롯 없음 + TO가 openState → TO를 CLOSED로
/// - contract TO는 슬롯 없음 → no-op
Map<String, String>? _syncTOCascadeStatus({
  required String currentStatus,
  required List<_Slot> slots,
}) {
  if (slots.isEmpty) return null; // contract TO or no slots → no-op

  final hasOpenSlot = slots.any(
    (s) => s.status == _SlotStatus.open || s.status == _SlotStatus.full,
  );

  if (!hasOpenSlot && _TOStatus.openStates.contains(currentStatus)) {
    return {'status': _TOStatus.closed};
  }
  if (hasOpenSlot && currentStatus == _TOStatus.closed) {
    return {'status': _TOStatus.active, 'isManualClosed': 'false'};
  }
  return null; // 변경 없음
}

// ── 3. MAX_ACTIVE_TO_LIMIT 체크 ──────────────────────────────────────────────

/// 활성 TO 수 제한 초과 여부 (fail-open: countError 시 0으로 처리)
({bool blocked, String? reason}) _checkActiveTOLimit({
  required int? activeCount, // null = 조회 실패 (fail-open)
  required int limit,
  required bool isSuperAdmin,
  required bool isDraft,
}) {
  if (isDraft) return (blocked: false, reason: null);
  if (isSuperAdmin) return (blocked: false, reason: null);
  final count = activeCount ?? 0; // fail-open
  if (count >= limit) {
    return (blocked: true, reason: 'MAX_ACTIVE_TO_LIMIT:$limit');
  }
  return (blocked: false, reason: null);
}

// ── 4. createTO 비공개→공개 단계 (flex 즉시공개) ─────────────────────────────

/// flex TO 생성 시 비공개→공개 전환 순서 시뮬레이션.
/// 반환값: 생성 이벤트 로그 리스트
List<String> _simulateFlexTOCreate({
  required bool isFlexImmediate,
  required bool slotCreateFails,
  required List<DateTime> dates,
}) {
  final log = <String>[];

  if (!isFlexImmediate || dates.isEmpty) {
    log.add('create_to:isPublished=false_skip_defer');
    return log;
  }

  // 1단계: isPublished=false, status=SCHEDULED로 TO 문서 생성
  log.add('step1:create_to:isPublished=false:status=SCHEDULED');

  // 2단계: 슬롯 생성
  if (slotCreateFails) {
    log.add('step2:slot_create_failed');
    log.add('rollback:delete_partial_slots');
    log.add('rollback:delete_to_document');
    return log;
  }
  log.add('step2:create_slots:count=${dates.length}');

  // 3단계: isPublished=true, status=ACTIVE로 전환
  log.add('step3:update_to:isPublished=true:status=ACTIVE');

  return log;
}

// ── 5. edit_to_screen 모드 판단 ───────────────────────────────────────────────

enum _EditMode { to, slot, batchSlots, newSlotDate }

_EditMode _resolveEditMode({
  required bool isSlotMode,
  required bool isBatchMode,
  required bool isNewSlot,
}) {
  if (isNewSlot)    return _EditMode.newSlotDate;
  if (isBatchMode)  return _EditMode.batchSlots;
  if (isSlotMode)   return _EditMode.slot;
  return _EditMode.to;
}

// ── 6. batchCloseSlots 실행 순서 (A-001) ────────────────────────────────────

/// 슬롯 일괄 마감 순서 시뮬레이션.
/// 반환: 실행 이벤트 로그 (순서가 핵심)
List<String> _simulateBatchCloseSlots({
  required List<String> slotIds,
  required Map<String, List<String>> pendingAppsBySlot, // slotId → pendingAppIds
  List<String>? failingCancelSlots, // cancelBatch 실패 슬롯
}) {
  final log = <String>[];

  if (slotIds.isEmpty) {
    log.add('noop:no_slots');
    return log;
  }

  // [A-001] 슬롯 closed 먼저 (신규 지원 차단)
  for (final slotId in slotIds) {
    log.add('close_slot:$slotId:status=closed:isManualClosed=true');
  }

  // 슬롯 마감 완료 후 PENDING 지원 취소 (per-slot try-catch)
  for (final slotId in slotIds) {
    final apps = pendingAppsBySlot[slotId] ?? [];
    if (apps.isEmpty) continue;

    if (failingCancelSlots != null && failingCancelSlots.contains(slotId)) {
      log.add('cancel_pending:$slotId:FAILED:continue');
      continue; // 실패 시 전체 중단하지 않고 다음 슬롯으로 계속
    }

    for (final appId in apps) {
      log.add('cancel_pending_app:$appId:status=rejected');
    }
  }

  log.add('sync_to_cascade_status');
  return log;
}

// ── 7. batchReopenSlots (full 슬롯 재오픈 차단) ──────────────────────────────

/// 슬롯 재오픈 시 확정 인원 기준으로 상태 결정.
String _resolveReopenStatus({
  required int confirmedCount,
  required int totalRequired,
}) {
  if (totalRequired > 0 && confirmedCount >= totalRequired) {
    return _SlotStatus.full; // 인원 충족 → 재오픈 차단 (full 유지)
  }
  return _SlotStatus.open;
}

List<Map<String, dynamic>> _simulateBatchReopenSlots({
  required List<_Slot> slots,
  required String reopenedBy,
}) {
  final results = <Map<String, dynamic>>[];
  for (final slot in slots) {
    final newStatus = _resolveReopenStatus(
      confirmedCount: slot.confirmedCount,
      totalRequired: slot.totalRequired,
    );
    results.add({
      'slotId': slot.id,
      'status': newStatus,
      'isManualClosed': false,
      'reopenedBy': reopenedBy,
      'closedBy': null,
      'closedAt': null,
    });
  }
  return results;
}

// ── 8. CloseStateUtils.isToItemClosed() 판단 우선순위 ─────────────────────────

/// CloseStateUtils.isToItemClosed 재현 (우선순위 1~6)
bool _isToItemClosed(
  _TOItem item,
  DateTime now,
) {
  final slot = item.slot;
  if (slot == null) return false; // 슬롯 없음 → 열림

  final today = DateTime(now.year, now.month, now.day);

  // 0. TO 레벨 수동마감 (우선순위 최상위)
  if (item.to.isManualClosed) return true;

  // 1. 날짜 경과
  if (DateTime(slot.date.year, slot.date.month, slot.date.day).isBefore(today)) {
    return true;
  }

  // 2. 관리자 직접 마감 (closedBy 설정)
  if (slot.closedBy != null) return true;

  // 3. 인원 충족 (localConfirmed/Required 우선, 없으면 toItem 값)
  final confirmed = item.confirmedCount;
  final required  = item.totalRequired;
  if (required > 0 && confirmed >= required) return true;
  if (slot.isFull) return true;

  // 4. 업무상세 기반 판단
  final details = item.isWorkDetailLoaded && item.workDetails.isNotEmpty
      ? item.workDetails
      : slot.workDetails;

  if (details.isEmpty) return false; // 업무상세 없음 → 열림

  return details.every((d) => _isWorkDetailClosed(d, now));
}

bool _isWorkDetailClosed(_WorkDetail d, DateTime now) {
  if (d.isManualClosed || d.closedAt != null) return true;
  if (d.applicationDeadline != null && now.isAfter(d.applicationDeadline!)) return true;
  return false;
}

// ── 9. TO update 불변 필드 보호 ───────────────────────────────────────────────

const _immutableFieldsOnClosed = [
  'workDetailId',
  'totalRequired',
  'startDate',
  'endDate',
  'workDays',
  'workTypeIds',
];

/// CLOSED/EXPIRED 상태에서 불변 필드 변경 시 차단
String? _validateTOUpdate({
  required String currentStatus,
  required Map<String, dynamic> updates,
  required int? currentTotalConfirmed,
}) {
  final isTerminated = currentStatus == _TOStatus.closed ||
      currentStatus == _TOStatus.expired;

  if (!isTerminated) return null; // 열린 상태 → 제한 없음

  for (final field in _immutableFieldsOnClosed) {
    if (updates.containsKey(field)) {
      return 'IMMUTABLE_FIELD:$field:status=$currentStatus';
    }
  }

  // totalRequired 변경 시 추가 조건 체크
  if (updates.containsKey('totalRequired')) {
    final newVal = updates['totalRequired'] as int?;
    if (newVal == null || newVal == 0) {
      return 'IMMUTABLE_FIELD:totalRequired:must_be_positive';
    }
    if (currentTotalConfirmed != null && newVal < currentTotalConfirmed) {
      return 'IMMUTABLE_FIELD:totalRequired:below_confirmed:$currentTotalConfirmed';
    }
  }

  return null;
}

// ── 10. updateSlotsDeadlines 마감시간 재계산 ──────────────────────────────────

/// 단일 슬롯의 workDetail별 마감시간 재계산
List<_WorkDetail> _recalculateSlotDeadlines({
  required _Slot slot,
  required List<_WorkDetail> newWorkDetails,
  required String deadlineType,
  required int hoursBeforeStart,
  DateTime? fixedDeadline,
}) {
  return newWorkDetails.map((newDef) {
    DateTime? deadline;
    if (deadlineType == 'HOURS_BEFORE') {
      final parts = newDef.startTime.split(':');
      if (parts.length >= 2) {
        final h = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        if (h != null && m != null) {
          deadline = DateTime(
            slot.date.year,
            slot.date.month,
            slot.date.day,
            h,
            m,
          ).subtract(Duration(hours: hoursBeforeStart));
        }
      }
    } else if (deadlineType == 'FIXED_TIME' && fixedDeadline != null) {
      deadline = fixedDeadline;
    }

    // 기존 슬롯에 같은 workType 있으면 기존 상태 유지
    final existing = slot.workDetails
        .where((d) => d.workType == newDef.workType)
        .firstOrNull;

    if (existing == null) {
      return newDef.copyWith(applicationDeadline: deadline);
    }
    return existing.copyWith(
      startTime: newDef.startTime,
      endTime: newDef.endTime,
      applicationDeadline: deadline,
    );
  }).toList();
}

/// 슬롯 레벨 마감시간 = 업무상세 중 가장 이른 마감
DateTime? _slotDeadlineFromDetails(List<_WorkDetail> details) {
  final deadlines = details
      .where((d) => d.applicationDeadline != null)
      .map((d) => d.applicationDeadline!);
  if (deadlines.isEmpty) return null;
  return deadlines.reduce((a, b) => a.isBefore(b) ? a : b);
}

// ══════════════════════════════════════════════════════════════════════════════
// main
// ══════════════════════════════════════════════════════════════════════════════

void main() {
  final _now = DateTime.now();

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 1: TOStatus 상수 및 상태 그룹 검증
  // ──────────────────────────────────────────────────────────────────────────
  group('SCENARIO-TOM-01: TOStatus 상수 및 상태 그룹', () {
    test('SCENARIO-TOM-01-001: openStates = [ACTIVE, FULL, SCHEDULED]', () {
      expect(_TOStatus.openStates, containsAll(['ACTIVE', 'FULL', 'SCHEDULED']));
      expect(_TOStatus.openStates.length, 3);
    });

    test('SCENARIO-TOM-01-002: closedStates = [CLOSED, EXPIRED]', () {
      expect(_TOStatus.closedStates, containsAll(['CLOSED', 'EXPIRED']));
      expect(_TOStatus.closedStates.length, 2);
    });

    test('SCENARIO-TOM-01-003: ACTIVE는 openStates에 포함됨', () {
      expect(_TOStatus.openStates.contains(_TOStatus.active), isTrue);
    });

    test('SCENARIO-TOM-01-004: FULL은 openStates에 포함됨 (인원 충족이지만 open)', () {
      expect(_TOStatus.openStates.contains(_TOStatus.full), isTrue);
    });

    test('SCENARIO-TOM-01-005: SCHEDULED는 openStates에 포함됨', () {
      expect(_TOStatus.openStates.contains(_TOStatus.scheduled), isTrue);
    });

    test('SCENARIO-TOM-01-006: CLOSED는 closedStates에 포함됨', () {
      expect(_TOStatus.closedStates.contains(_TOStatus.closed), isTrue);
    });

    test('SCENARIO-TOM-01-007: EXPIRED는 closedStates에 포함됨', () {
      expect(_TOStatus.closedStates.contains(_TOStatus.expired), isTrue);
    });

    test('SCENARIO-TOM-01-008: DRAFT는 openStates/closedStates 어디에도 없음', () {
      expect(_TOStatus.openStates.contains(_TOStatus.draft), isFalse);
      expect(_TOStatus.closedStates.contains(_TOStatus.draft), isFalse);
    });

    test('SCENARIO-TOM-01-009: openStates와 closedStates는 교집합 없음', () {
      final intersection = _TOStatus.openStates
          .where((s) => _TOStatus.closedStates.contains(s))
          .toList();
      expect(intersection, isEmpty);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 2: TOModel.isClosed 판단 로직
  // ──────────────────────────────────────────────────────────────────────────
  group('SCENARIO-TOM-02: TOModel.isClosed 판단', () {
    test('SCENARIO-TOM-02-001: isManualClosed=true → isClosed=true (status 무관)', () {
      final to = _TOModel(
        id: 'to-1',
        status: _TOStatus.active,
        isManualClosed: true,
        createdAt: _now,
      );
      expect(_isToModelClosed(to), isTrue);
    });

    test('SCENARIO-TOM-02-002: isFull(confirmed>=required) → isClosed=true', () {
      final to = _TOModel(
        id: 'to-2',
        status: _TOStatus.full,
        totalRequired: 5,
        totalConfirmed: 5,
        createdAt: _now,
      );
      expect(to.isFull, isTrue);
      expect(_isToModelClosed(to), isTrue);
    });

    test('SCENARIO-TOM-02-003: confirmed > required (초과) → isFull=true', () {
      final to = _TOModel(
        id: 'to-3',
        status: _TOStatus.active,
        totalRequired: 3,
        totalConfirmed: 5,
        createdAt: _now,
      );
      expect(to.isFull, isTrue);
      expect(_isToModelClosed(to), isTrue);
    });

    test('SCENARIO-TOM-02-004: totalRequired=0 → isFull=false (인원 제한 없음)', () {
      final to = _TOModel(
        id: 'to-4',
        status: _TOStatus.active,
        totalRequired: 0,
        totalConfirmed: 100,
        createdAt: _now,
      );
      expect(to.isFull, isFalse);
    });

    test('SCENARIO-TOM-02-005: status=CLOSED → isClosed=true', () {
      final to = _TOModel(
        id: 'to-5',
        status: _TOStatus.closed,
        createdAt: _now,
      );
      expect(_isToModelClosed(to), isTrue);
    });

    test('SCENARIO-TOM-02-006: status=EXPIRED → isClosed=true', () {
      final to = _TOModel(
        id: 'to-6',
        status: _TOStatus.expired,
        createdAt: _now,
      );
      expect(_isToModelClosed(to), isTrue);
    });

    test('SCENARIO-TOM-02-007: status=ACTIVE, isManualClosed=false, 인원 미충족 → isClosed=false', () {
      final to = _TOModel(
        id: 'to-7',
        status: _TOStatus.active,
        totalRequired: 5,
        totalConfirmed: 3,
        createdAt: _now,
      );
      expect(_isToModelClosed(to), isFalse);
    });

    test('SCENARIO-TOM-02-008: contract TO + applicationDeadline 경과 → isClosed=true', () {
      final pastDeadline = _now.subtract(const Duration(hours: 1));
      final to = _TOModel(
        id: 'to-8',
        type: _TOType.contract,
        status: _TOStatus.active,
        applicationDeadline: pastDeadline,
        createdAt: _now.subtract(const Duration(days: 7)),
      );
      expect(to.isDeadlinePassed, isTrue);
      expect(_isToModelClosed(to), isTrue);
    });

    test('SCENARIO-TOM-02-009: contract TO + applicationDeadline 미경과 → isClosed=false', () {
      final futureDeadline = _now.add(const Duration(hours: 2));
      final to = _TOModel(
        id: 'to-9',
        type: _TOType.contract,
        status: _TOStatus.active,
        applicationDeadline: futureDeadline,
        createdAt: _now,
      );
      expect(to.isDeadlinePassed, isFalse);
      expect(_isToModelClosed(to), isFalse);
    });

    test('SCENARIO-TOM-02-010: flex TO + applicationDeadline 경과해도 isClosed에 미영향', () {
      final pastDeadline = _now.subtract(const Duration(hours: 1));
      final to = _TOModel(
        id: 'to-10',
        type: _TOType.flex,
        status: _TOStatus.active,
        applicationDeadline: pastDeadline,
        createdAt: _now,
      );
      // flex TO는 isDeadlinePassed가 isClosed 조건에 미포함
      expect(_isToModelClosed(to), isFalse);
    });

    test('SCENARIO-TOM-02-011: contract TO + postingDurationDays 경과 → isPostingExpired=true', () {
      final to = _TOModel(
        id: 'to-11',
        type: _TOType.contract,
        status: _TOStatus.active,
        postingDurationDays: 3,
        createdAt: _now.subtract(const Duration(days: 10)),
      );
      expect(to.isPostingExpired, isTrue);
      expect(_isToModelClosed(to), isTrue);
    });

    test('SCENARIO-TOM-02-012: contract TO + postingDurationDays 미경과 → isPostingExpired=false', () {
      final to = _TOModel(
        id: 'to-12',
        type: _TOType.contract,
        status: _TOStatus.active,
        postingDurationDays: 30,
        createdAt: _now,
      );
      expect(to.isPostingExpired, isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 3: _syncTOCascadeStatus 로직
  // ──────────────────────────────────────────────────────────────────────────
  group('SCENARIO-TOM-03: _syncTOCascadeStatus 슬롯→TO 상태 동기화', () {
    test('SCENARIO-TOM-03-001: 모든 슬롯 closed + TO가 ACTIVE → TO를 CLOSED로', () {
      final slots = [
        _Slot(id: 's1', toId: 'to-1', date: _now, status: _SlotStatus.closed),
        _Slot(id: 's2', toId: 'to-1', date: _now.add(const Duration(days: 1)), status: _SlotStatus.closed),
      ];
      final result = _syncTOCascadeStatus(
        currentStatus: _TOStatus.active,
        slots: slots,
      );
      expect(result, isNotNull);
      expect(result!['status'], _TOStatus.closed);
    });

    test('SCENARIO-TOM-03-002: open 슬롯 하나라도 있음 + TO가 CLOSED → TO를 ACTIVE로', () {
      final slots = [
        _Slot(id: 's1', toId: 'to-1', date: _now, status: _SlotStatus.closed),
        _Slot(id: 's2', toId: 'to-1', date: _now.add(const Duration(days: 1)), status: _SlotStatus.open),
      ];
      final result = _syncTOCascadeStatus(
        currentStatus: _TOStatus.closed,
        slots: slots,
      );
      expect(result, isNotNull);
      expect(result!['status'], _TOStatus.active);
    });

    test('SCENARIO-TOM-03-003: full 슬롯만 남은 경우 + TO가 ACTIVE → 변경 없음 (full은 open 카운트에 포함)', () {
      final slots = [
        _Slot(id: 's1', toId: 'to-1', date: _now, status: _SlotStatus.full),
      ];
      // full 슬롯이 있으면 hasOpenSlot=true → TO가 ACTIVE면 변경 없음
      final result = _syncTOCascadeStatus(
        currentStatus: _TOStatus.active,
        slots: slots,
      );
      expect(result, isNull);
    });

    test('SCENARIO-TOM-03-004: full 슬롯만 남은 경우 + TO가 CLOSED → ACTIVE로 복구', () {
      final slots = [
        _Slot(id: 's1', toId: 'to-1', date: _now, status: _SlotStatus.full),
      ];
      final result = _syncTOCascadeStatus(
        currentStatus: _TOStatus.closed,
        slots: slots,
      );
      expect(result, isNotNull);
      expect(result!['status'], _TOStatus.active);
    });

    test('SCENARIO-TOM-03-005: 슬롯 없음(contract TO) → no-op', () {
      final result = _syncTOCascadeStatus(
        currentStatus: _TOStatus.active,
        slots: [],
      );
      expect(result, isNull);
    });

    test('SCENARIO-TOM-03-006: TO가 이미 CLOSED + 슬롯도 모두 closed → 변경 없음', () {
      final slots = [
        _Slot(id: 's1', toId: 'to-1', date: _now, status: _SlotStatus.closed),
      ];
      final result = _syncTOCascadeStatus(
        currentStatus: _TOStatus.closed,
        slots: slots,
      );
      expect(result, isNull);
    });

    test('SCENARIO-TOM-03-007: SCHEDULED 상태 + 슬롯 없음 → no-op', () {
      final result = _syncTOCascadeStatus(
        currentStatus: _TOStatus.scheduled,
        slots: [],
      );
      expect(result, isNull);
    });

    test('SCENARIO-TOM-03-008: ACTIVE TO + open/closed 혼재 → 변경 없음 (hasOpenSlot=true)', () {
      final slots = [
        _Slot(id: 's1', toId: 'to-1', date: _now, status: _SlotStatus.open),
        _Slot(id: 's2', toId: 'to-1', date: _now.add(const Duration(days: 1)), status: _SlotStatus.closed),
      ];
      final result = _syncTOCascadeStatus(
        currentStatus: _TOStatus.active,
        slots: slots,
      );
      expect(result, isNull);
    });

    test('SCENARIO-TOM-03-009: 재오픈 후 isManualClosed도 false로 초기화됨', () {
      final slots = [
        _Slot(id: 's1', toId: 'to-1', date: _now, status: _SlotStatus.open),
      ];
      final result = _syncTOCascadeStatus(
        currentStatus: _TOStatus.closed,
        slots: slots,
      );
      expect(result, isNotNull);
      expect(result!['isManualClosed'], 'false');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 4: MAX_ACTIVE_TO_LIMIT 체크
  // ──────────────────────────────────────────────────────────────────────────
  group('SCENARIO-TOM-04: MAX_ACTIVE_TO_LIMIT 체크', () {
    test('SCENARIO-TOM-04-001: activeCount < limit → 생성 허용', () {
      final result = _checkActiveTOLimit(
        activeCount: 2,
        limit: 4,
        isSuperAdmin: false,
        isDraft: false,
      );
      expect(result.blocked, isFalse);
    });

    test('SCENARIO-TOM-04-002: activeCount == limit → 차단', () {
      final result = _checkActiveTOLimit(
        activeCount: 4,
        limit: 4,
        isSuperAdmin: false,
        isDraft: false,
      );
      expect(result.blocked, isTrue);
      expect(result.reason, contains('MAX_ACTIVE_TO_LIMIT:4'));
    });

    test('SCENARIO-TOM-04-003: activeCount > limit → 차단', () {
      final result = _checkActiveTOLimit(
        activeCount: 10,
        limit: 4,
        isSuperAdmin: false,
        isDraft: false,
      );
      expect(result.blocked, isTrue);
    });

    test('SCENARIO-TOM-04-004: activeCount == null (조회 실패) → fail-open (0으로 처리) → 허용', () {
      final result = _checkActiveTOLimit(
        activeCount: null, // 조회 실패
        limit: 4,
        isSuperAdmin: false,
        isDraft: false,
      );
      expect(result.blocked, isFalse); // fail-open
    });

    test('SCENARIO-TOM-04-005: SUPER_ADMIN → 제한 미적용 (항상 허용)', () {
      final result = _checkActiveTOLimit(
        activeCount: 100,
        limit: 4,
        isSuperAdmin: true,
        isDraft: false,
      );
      expect(result.blocked, isFalse);
    });

    test('SCENARIO-TOM-04-006: isDraft=true → 제한 미적용 (draft 저장은 제한 없음)', () {
      final result = _checkActiveTOLimit(
        activeCount: 100,
        limit: 4,
        isSuperAdmin: false,
        isDraft: true,
      );
      expect(result.blocked, isFalse);
    });

    test('SCENARIO-TOM-04-007: limit=0일 때 activeCount=0 → 차단 (0>=0)', () {
      final result = _checkActiveTOLimit(
        activeCount: 0,
        limit: 0,
        isSuperAdmin: false,
        isDraft: false,
      );
      expect(result.blocked, isTrue);
    });

    test('SCENARIO-TOM-04-008: 오류 메시지에 실제 limit 값 포함됨', () {
      final result = _checkActiveTOLimit(
        activeCount: 5,
        limit: 3,
        isSuperAdmin: false,
        isDraft: false,
      );
      expect(result.reason, 'MAX_ACTIVE_TO_LIMIT:3');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 5: createTO 비공개→공개 단계 순서 (flex 즉시공개)
  // ──────────────────────────────────────────────────────────────────────────
  group('SCENARIO-TOM-05: createTO 비공개→공개 순서 (flex 즉시공개)', () {
    test('SCENARIO-TOM-05-001: 정상 흐름 — 1)비공개TO 2)슬롯생성 3)공개전환 순서', () {
      final log = _simulateFlexTOCreate(
        isFlexImmediate: true,
        slotCreateFails: false,
        dates: [_now.add(const Duration(days: 1))],
      );
      final step1Idx = log.indexWhere((e) => e.contains('step1') && e.contains('isPublished=false'));
      final step2Idx = log.indexWhere((e) => e.contains('step2:create_slots'));
      final step3Idx = log.indexWhere((e) => e.contains('step3') && e.contains('isPublished=true'));

      expect(step1Idx, lessThan(step2Idx),  reason: '슬롯 생성 전 TO 먼저 비공개로 생성되어야 함');
      expect(step2Idx, lessThan(step3Idx),  reason: '슬롯 생성 완료 후 공개 전환되어야 함');
    });

    test('SCENARIO-TOM-05-002: 1단계 — isPublished=false, status=SCHEDULED로 TO 생성', () {
      final log = _simulateFlexTOCreate(
        isFlexImmediate: true,
        slotCreateFails: false,
        dates: [_now.add(const Duration(days: 1))],
      );
      expect(log.any((e) => e.contains('isPublished=false') && e.contains('SCHEDULED')), isTrue);
    });

    test('SCENARIO-TOM-05-003: 3단계 — isPublished=true, status=ACTIVE로 전환', () {
      final log = _simulateFlexTOCreate(
        isFlexImmediate: true,
        slotCreateFails: false,
        dates: [_now.add(const Duration(days: 1))],
      );
      expect(log.any((e) => e.contains('isPublished=true') && e.contains('ACTIVE')), isTrue);
    });

    test('SCENARIO-TOM-05-004: 슬롯 생성 실패 → TO 문서 롤백 삭제됨', () {
      final log = _simulateFlexTOCreate(
        isFlexImmediate: true,
        slotCreateFails: true,
        dates: [_now.add(const Duration(days: 1))],
      );
      expect(log.any((e) => e.contains('rollback:delete_to_document')), isTrue);
    });

    test('SCENARIO-TOM-05-005: 슬롯 생성 실패 → 부분 슬롯도 롤백 삭제됨', () {
      final log = _simulateFlexTOCreate(
        isFlexImmediate: true,
        slotCreateFails: true,
        dates: [_now.add(const Duration(days: 1))],
      );
      expect(log.any((e) => e.contains('rollback:delete_partial_slots')), isTrue);
    });

    test('SCENARIO-TOM-05-006: 슬롯 생성 실패 시 3단계(공개 전환) 실행되지 않음', () {
      final log = _simulateFlexTOCreate(
        isFlexImmediate: true,
        slotCreateFails: true,
        dates: [_now.add(const Duration(days: 1))],
      );
      expect(log.any((e) => e.contains('step3')), isFalse);
    });

    test('SCENARIO-TOM-05-007: 날짜가 3개이면 슬롯 3개 생성 로그', () {
      final log = _simulateFlexTOCreate(
        isFlexImmediate: true,
        slotCreateFails: false,
        dates: List.generate(3, (i) => _now.add(Duration(days: i + 1))),
      );
      expect(log.any((e) => e.contains('count=3')), isTrue);
    });

    test('SCENARIO-TOM-05-008: draft 모드 / scheduled 모드는 비공개→공개 전환 로직 불필요', () {
      // isFlexImmediate=false이면 defer 로직 실행 안 함
      final log = _simulateFlexTOCreate(
        isFlexImmediate: false,
        slotCreateFails: false,
        dates: [_now.add(const Duration(days: 1))],
      );
      expect(log.any((e) => e.contains('step1')), isFalse);
      expect(log.any((e) => e.contains('step3')), isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 6: edit_to_screen 4가지 모드
  // ──────────────────────────────────────────────────────────────────────────
  group('SCENARIO-TOM-06: edit_to_screen 4가지 모드 판단', () {
    test('SCENARIO-TOM-06-001: isSlotMode=false, isBatchMode=false, isNewSlot=false → to 모드 (전체 업데이트)', () {
      final mode = _resolveEditMode(
        isSlotMode: false,
        isBatchMode: false,
        isNewSlot: false,
      );
      expect(mode, _EditMode.to);
    });

    test('SCENARIO-TOM-06-002: isSlotMode=true → slot 모드 (단일 슬롯 수정)', () {
      final mode = _resolveEditMode(
        isSlotMode: true,
        isBatchMode: false,
        isNewSlot: false,
      );
      expect(mode, _EditMode.slot);
    });

    test('SCENARIO-TOM-06-003: isBatchMode=true → batchSlots 모드 (슬롯 일괄 수정)', () {
      final mode = _resolveEditMode(
        isSlotMode: false,
        isBatchMode: true,
        isNewSlot: false,
      );
      expect(mode, _EditMode.batchSlots);
    });

    test('SCENARIO-TOM-06-004: isNewSlot=true → newSlotDate 모드 (새 날짜 슬롯 추가)', () {
      final mode = _resolveEditMode(
        isSlotMode: false,
        isBatchMode: false,
        isNewSlot: true,
      );
      expect(mode, _EditMode.newSlotDate);
    });

    test('SCENARIO-TOM-06-005: isNewSlot=true + isSlotMode=true → newSlotDate 우선', () {
      final mode = _resolveEditMode(
        isSlotMode: true,
        isBatchMode: false,
        isNewSlot: true,
      );
      expect(mode, _EditMode.newSlotDate);
    });

    test('SCENARIO-TOM-06-006: isNewSlot=true + isBatchMode=true → newSlotDate 우선', () {
      final mode = _resolveEditMode(
        isSlotMode: false,
        isBatchMode: true,
        isNewSlot: true,
      );
      expect(mode, _EditMode.newSlotDate);
    });

    test('SCENARIO-TOM-06-007: isBatchMode=true + isSlotMode=true → batchSlots 우선 (isNewSlot=false)', () {
      final mode = _resolveEditMode(
        isSlotMode: true,
        isBatchMode: true,
        isNewSlot: false,
      );
      expect(mode, _EditMode.batchSlots);
    });

    test('SCENARIO-TOM-06-008: to 모드는 4가지 중 기본값 (모든 플래그 false)', () {
      final mode = _resolveEditMode(
        isSlotMode: false,
        isBatchMode: false,
        isNewSlot: false,
      );
      expect(mode, _EditMode.to);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 7: batchCloseSlots 순서 (A-001)
  // ──────────────────────────────────────────────────────────────────────────
  group('SCENARIO-TOM-07: batchCloseSlots 순서 — 슬롯 마감 먼저 → PENDING 취소', () {
    test('SCENARIO-TOM-07-001: 슬롯 마감 이벤트가 PENDING 취소 이벤트보다 먼저 발생', () {
      final log = _simulateBatchCloseSlots(
        slotIds: ['s1'],
        pendingAppsBySlot: {'s1': ['app1', 'app2']},
      );
      final closeIdx  = log.indexWhere((e) => e.contains('close_slot:s1'));
      final cancelIdx = log.indexWhere((e) => e.contains('cancel_pending_app:app1'));
      expect(closeIdx, lessThan(cancelIdx),
          reason: '[A-001] 슬롯 마감(신규 지원 차단) 후 PENDING 취소 처리해야 함');
    });

    test('SCENARIO-TOM-07-002: 슬롯 마감 → 슬롯 status=closed, isManualClosed=true 설정', () {
      final log = _simulateBatchCloseSlots(
        slotIds: ['s1'],
        pendingAppsBySlot: {},
      );
      expect(log.any((e) =>
          e.contains('close_slot:s1') &&
          e.contains('status=closed') &&
          e.contains('isManualClosed=true')), isTrue);
    });

    test('SCENARIO-TOM-07-003: PENDING 앱 없는 슬롯 → 취소 이벤트 없음', () {
      final log = _simulateBatchCloseSlots(
        slotIds: ['s1'],
        pendingAppsBySlot: {}, // 없음
      );
      expect(log.any((e) => e.contains('cancel_pending_app')), isFalse);
    });

    test('SCENARIO-TOM-07-004: 특정 슬롯 cancelBatch 실패 → 해당 슬롯 건너뜀, 다른 슬롯은 계속 처리', () {
      final log = _simulateBatchCloseSlots(
        slotIds: ['s1', 's2'],
        pendingAppsBySlot: {
          's1': ['app1'],
          's2': ['app2'],
        },
        failingCancelSlots: ['s1'], // s1 실패
      );
      // s1: FAILED:continue 로그
      expect(log.any((e) => e.contains('cancel_pending:s1:FAILED:continue')), isTrue);
      // s2: 정상 처리됨
      expect(log.any((e) => e.contains('cancel_pending_app:app2')), isTrue);
    });

    test('SCENARIO-TOM-07-005: 모든 슬롯 닫힌 후 _syncTOCascadeStatus 호출', () {
      final log = _simulateBatchCloseSlots(
        slotIds: ['s1'],
        pendingAppsBySlot: {},
      );
      final syncIdx  = log.indexWhere((e) => e.contains('sync_to_cascade_status'));
      final closeIdx = log.indexWhere((e) => e.contains('close_slot'));
      expect(closeIdx, lessThan(syncIdx),
          reason: '슬롯 마감 완료 후 TO 상태 동기화 실행');
    });

    test('SCENARIO-TOM-07-006: 역순(PENDING 취소 → 슬롯 마감) 시나리오 — A-001 위반', () {
      // 역순이면 취소~마감 사이 신규 PENDING이 잔류 가능 (안전하지 않음)
      // 올바른 순서: 슬롯 마감 → PENDING 취소
      final log = _simulateBatchCloseSlots(
        slotIds: ['s1'],
        pendingAppsBySlot: {'s1': ['app1']},
      );
      final closeIdx  = log.indexWhere((e) => e.contains('close_slot'));
      final cancelIdx = log.indexWhere((e) => e.contains('cancel_pending_app'));
      // 올바른 순서 확인 (close < cancel)
      expect(closeIdx, isNot(-1));
      expect(cancelIdx, isNot(-1));
      expect(closeIdx, lessThan(cancelIdx));
    });

    test('SCENARIO-TOM-07-007: 빈 slotIds → noop', () {
      final log = _simulateBatchCloseSlots(
        slotIds: [],
        pendingAppsBySlot: {},
      );
      expect(log, contains('noop:no_slots'));
    });

    test('SCENARIO-TOM-07-008: 다수 슬롯 모두 정상 처리', () {
      final log = _simulateBatchCloseSlots(
        slotIds: ['s1', 's2', 's3'],
        pendingAppsBySlot: {
          's1': ['app1'],
          's2': ['app2', 'app3'],
          's3': [],
        },
      );
      // 3개 슬롯 모두 closed
      expect(log.where((e) => e.contains('close_slot')).length, 3);
      // 3개 pending app 취소
      expect(log.where((e) => e.contains('cancel_pending_app')).length, 3);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 8: batchReopenSlots (full 슬롯 재오픈 차단)
  // ──────────────────────────────────────────────────────────────────────────
  group('SCENARIO-TOM-08: batchReopenSlots — full 슬롯 재오픈 차단', () {
    test('SCENARIO-TOM-08-001: confirmed < required → status=open으로 재오픈', () {
      final status = _resolveReopenStatus(confirmedCount: 2, totalRequired: 5);
      expect(status, _SlotStatus.open);
    });

    test('SCENARIO-TOM-08-002: confirmed == required → status=full (재오픈 차단)', () {
      final status = _resolveReopenStatus(confirmedCount: 5, totalRequired: 5);
      expect(status, _SlotStatus.full);
    });

    test('SCENARIO-TOM-08-003: confirmed > required → status=full (초과 시에도 차단)', () {
      final status = _resolveReopenStatus(confirmedCount: 7, totalRequired: 5);
      expect(status, _SlotStatus.full);
    });

    test('SCENARIO-TOM-08-004: totalRequired=0 → status=open (인원 제한 없음 → 항상 open)', () {
      final status = _resolveReopenStatus(confirmedCount: 0, totalRequired: 0);
      expect(status, _SlotStatus.open);
    });

    test('SCENARIO-TOM-08-005: 재오픈 시 isManualClosed=false, closedBy=null 설정', () {
      final slot = _Slot(
        id: 's1',
        toId: 'to-1',
        date: _now.add(const Duration(days: 1)),
        status: _SlotStatus.closed,
        isManualClosed: true,
        closedBy: 'admin-001',
        workDetails: [_WorkDetail(workType: '피킹', requiredCount: 3)],
        confirmedCount: 1,
      );
      final results = _simulateBatchReopenSlots(
        slots: [slot],
        reopenedBy: 'admin-002',
      );
      expect(results.first['isManualClosed'], isFalse);
      expect(results.first['closedBy'], isNull);
    });

    test('SCENARIO-TOM-08-006: 재오픈 시 reopenedBy에 관리자 UID 기록됨', () {
      final slot = _Slot(
        id: 's1',
        toId: 'to-1',
        date: _now.add(const Duration(days: 1)),
        status: _SlotStatus.closed,
        workDetails: [_WorkDetail(workType: '피킹', requiredCount: 3)],
        confirmedCount: 1,
      );
      final results = _simulateBatchReopenSlots(
        slots: [slot],
        reopenedBy: 'admin-uid-123',
      );
      expect(results.first['reopenedBy'], 'admin-uid-123');
    });

    test('SCENARIO-TOM-08-007: 혼합 슬롯 (full 1개 + 미충족 1개) → full 유지 + open 복구', () {
      final fullSlot = _Slot(
        id: 's1',
        toId: 'to-1',
        date: _now.add(const Duration(days: 1)),
        status: _SlotStatus.closed,
        workDetails: [_WorkDetail(workType: '피킹', requiredCount: 3)],
        confirmedCount: 3, // == required → full
      );
      final notFullSlot = _Slot(
        id: 's2',
        toId: 'to-1',
        date: _now.add(const Duration(days: 2)),
        status: _SlotStatus.closed,
        workDetails: [_WorkDetail(workType: '패킹', requiredCount: 5)],
        confirmedCount: 2, // < required → open
      );
      final results = _simulateBatchReopenSlots(
        slots: [fullSlot, notFullSlot],
        reopenedBy: 'admin',
      );
      expect(results[0]['status'], _SlotStatus.full);
      expect(results[1]['status'], _SlotStatus.open);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 9: CloseStateUtils.isToItemClosed() 판단 우선순위
  // ──────────────────────────────────────────────────────────────────────────
  group('SCENARIO-TOM-09: isToItemClosed() 판단 우선순위', () {
    // 기준 TO (isManualClosed=false)
    final baseTO = _TOModel(id: 'to-1', createdAt: _now);

    test('SCENARIO-TOM-09-001: slot=null → false (슬롯 없음 = 열림 처리)', () {
      final item = _TOItem(
        to: baseTO,
        slot: null,
        confirmedCount: 0,
        totalRequired: 0,
      );
      expect(_isToItemClosed(item, _now), isFalse);
    });

    test('SCENARIO-TOM-09-002: TO 레벨 isManualClosed=true → 즉시 true (최상위 우선순위)', () {
      final manualClosedTO = baseTO.copyWith(isManualClosed: true);
      final slot = _Slot(
        id: 's1',
        toId: 'to-1',
        date: _now.add(const Duration(days: 1)), // 미래 날짜
        status: _SlotStatus.open,
      );
      final item = _TOItem(
        to: manualClosedTO,
        slot: slot,
        confirmedCount: 0,
        totalRequired: 10,
      );
      expect(_isToItemClosed(item, _now), isTrue);
    });

    test('SCENARIO-TOM-09-003: 날짜 경과(isDatePast=true) → true (우선순위 1)', () {
      final pastSlot = _Slot(
        id: 's1',
        toId: 'to-1',
        date: _now.subtract(const Duration(days: 1)), // 어제
      );
      final item = _TOItem(
        to: baseTO,
        slot: pastSlot,
        confirmedCount: 0,
        totalRequired: 0,
      );
      expect(_isToItemClosed(item, _now), isTrue);
    });

    test('SCENARIO-TOM-09-004: closedBy 설정됨(관리자 직접 마감) → true (우선순위 2)', () {
      final slot = _Slot(
        id: 's1',
        toId: 'to-1',
        date: _now.add(const Duration(days: 1)),
        closedBy: 'admin-001', // 직접 마감
      );
      final item = _TOItem(
        to: baseTO,
        slot: slot,
        confirmedCount: 0,
        totalRequired: 0,
      );
      expect(_isToItemClosed(item, _now), isTrue);
    });

    test('SCENARIO-TOM-09-005: confirmed >= required(인원 충족) → true (우선순위 3)', () {
      final slot = _Slot(
        id: 's1',
        toId: 'to-1',
        date: _now.add(const Duration(days: 1)),
        workDetails: [_WorkDetail(workType: '피킹', requiredCount: 5)],
        confirmedCount: 5,
      );
      final item = _TOItem(
        to: baseTO,
        slot: slot,
        confirmedCount: 5,
        totalRequired: 5,
      );
      expect(_isToItemClosed(item, _now), isTrue);
    });

    test('SCENARIO-TOM-09-006: 모든 workDetail isManualClosed=true → true (우선순위 4)', () {
      final slot = _Slot(
        id: 's1',
        toId: 'to-1',
        date: _now.add(const Duration(days: 1)),
        workDetails: [
          _WorkDetail(workType: '피킹', isManualClosed: true),
          _WorkDetail(workType: '패킹', isManualClosed: true),
        ],
      );
      final item = _TOItem(
        to: baseTO,
        slot: slot,
        workDetails: slot.workDetails,
        confirmedCount: 0,
        totalRequired: 2,
        isWorkDetailLoaded: true,
      );
      expect(_isToItemClosed(item, _now), isTrue);
    });

    test('SCENARIO-TOM-09-007: workDetail 일부만 마감 → false (모두 마감이어야 함)', () {
      final slot = _Slot(
        id: 's1',
        toId: 'to-1',
        date: _now.add(const Duration(days: 1)),
        workDetails: [
          _WorkDetail(workType: '피킹', isManualClosed: true),
          _WorkDetail(workType: '패킹', isManualClosed: false),
        ],
      );
      final item = _TOItem(
        to: baseTO,
        slot: slot,
        workDetails: slot.workDetails,
        confirmedCount: 0,
        totalRequired: 2,
        isWorkDetailLoaded: true,
      );
      expect(_isToItemClosed(item, _now), isFalse);
    });

    test('SCENARIO-TOM-09-008: workDetail 없음 → false (열림 처리)', () {
      final slot = _Slot(
        id: 's1',
        toId: 'to-1',
        date: _now.add(const Duration(days: 1)),
        workDetails: [],
      );
      final item = _TOItem(
        to: baseTO,
        slot: slot,
        workDetails: [],
        confirmedCount: 0,
        totalRequired: 0,
        isWorkDetailLoaded: true,
      );
      expect(_isToItemClosed(item, _now), isFalse);
    });

    test('SCENARIO-TOM-09-009: applicationDeadline 경과된 workDetail → 해당 업무 마감', () {
      final pastDeadline = _now.subtract(const Duration(minutes: 30));
      final slot = _Slot(
        id: 's1',
        toId: 'to-1',
        date: _now.add(const Duration(hours: 5)),
        workDetails: [
          _WorkDetail(
            workType: '피킹',
            applicationDeadline: pastDeadline, // 마감 시간 경과
          ),
        ],
      );
      final item = _TOItem(
        to: baseTO,
        slot: slot,
        workDetails: slot.workDetails,
        confirmedCount: 0,
        totalRequired: 1,
        isWorkDetailLoaded: true,
      );
      expect(_isToItemClosed(item, _now), isTrue);
    });

    test('SCENARIO-TOM-09-010: applicationDeadline 미경과된 workDetail → 열림', () {
      final futureDeadline = _now.add(const Duration(hours: 2));
      final slot = _Slot(
        id: 's1',
        toId: 'to-1',
        date: _now.add(const Duration(hours: 8)),
        workDetails: [
          _WorkDetail(
            workType: '피킹',
            applicationDeadline: futureDeadline, // 미경과
          ),
        ],
      );
      final item = _TOItem(
        to: baseTO,
        slot: slot,
        workDetails: slot.workDetails,
        confirmedCount: 0,
        totalRequired: 1,
        isWorkDetailLoaded: true,
      );
      expect(_isToItemClosed(item, _now), isFalse);
    });

    test('SCENARIO-TOM-09-011: TO isManualClosed=true는 날짜 경과보다 우선 → 항상 true', () {
      final manualClosedTO = baseTO.copyWith(isManualClosed: true);
      final futureSlot = _Slot(
        id: 's1',
        toId: 'to-1',
        date: _now.add(const Duration(days: 30)), // 미래
      );
      final item = _TOItem(
        to: manualClosedTO,
        slot: futureSlot,
        confirmedCount: 0,
        totalRequired: 0,
      );
      expect(_isToItemClosed(item, _now), isTrue);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 10: TO update 불변 필드 보호 (CLOSED/EXPIRED 상태)
  // ──────────────────────────────────────────────────────────────────────────
  group('SCENARIO-TOM-10: TO update 불변 필드 보호', () {
    test('SCENARIO-TOM-10-001: ACTIVE 상태 → 모든 필드 수정 허용', () {
      final err = _validateTOUpdate(
        currentStatus: _TOStatus.active,
        updates: {'totalRequired': 10, 'workDays': ['월', '화']},
        currentTotalConfirmed: 3,
      );
      expect(err, isNull);
    });

    test('SCENARIO-TOM-10-002: CLOSED 상태에서 workDetailId 수정 → 차단', () {
      final err = _validateTOUpdate(
        currentStatus: _TOStatus.closed,
        updates: {'workDetailId': 'new-wd-id'},
        currentTotalConfirmed: 0,
      );
      expect(err, contains('IMMUTABLE_FIELD:workDetailId'));
    });

    test('SCENARIO-TOM-10-003: CLOSED 상태에서 totalRequired 수정 → 차단', () {
      final err = _validateTOUpdate(
        currentStatus: _TOStatus.closed,
        updates: {'totalRequired': 5},
        currentTotalConfirmed: 0,
      );
      expect(err, contains('IMMUTABLE_FIELD:totalRequired'));
    });

    test('SCENARIO-TOM-10-004: EXPIRED 상태에서 startDate 수정 → 차단', () {
      final err = _validateTOUpdate(
        currentStatus: _TOStatus.expired,
        updates: {'startDate': '2026-08-01'},
        currentTotalConfirmed: 0,
      );
      expect(err, contains('IMMUTABLE_FIELD:startDate'));
    });

    test('SCENARIO-TOM-10-005: CLOSED 상태에서 endDate 수정 → 차단', () {
      final err = _validateTOUpdate(
        currentStatus: _TOStatus.closed,
        updates: {'endDate': '2026-12-31'},
        currentTotalConfirmed: 0,
      );
      expect(err, contains('IMMUTABLE_FIELD:endDate'));
    });

    test('SCENARIO-TOM-10-006: CLOSED 상태에서 workDays 수정 → 차단', () {
      final err = _validateTOUpdate(
        currentStatus: _TOStatus.closed,
        updates: {'workDays': ['월', '수', '금']},
        currentTotalConfirmed: 0,
      );
      expect(err, contains('IMMUTABLE_FIELD:workDays'));
    });

    test('SCENARIO-TOM-10-007: CLOSED 상태에서 workTypeIds 수정 → 차단', () {
      final err = _validateTOUpdate(
        currentStatus: _TOStatus.closed,
        updates: {'workTypeIds': ['type-1', 'type-2']},
        currentTotalConfirmed: 0,
      );
      expect(err, contains('IMMUTABLE_FIELD:workTypeIds'));
    });

    test('SCENARIO-TOM-10-008: CLOSED 상태에서 title 수정 → 허용 (불변 필드 아님)', () {
      final err = _validateTOUpdate(
        currentStatus: _TOStatus.closed,
        updates: {'title': '수정된 제목'},
        currentTotalConfirmed: 0,
      );
      expect(err, isNull);
    });

    test('SCENARIO-TOM-10-009: CLOSED 상태에서 description 수정 → 허용', () {
      final err = _validateTOUpdate(
        currentStatus: _TOStatus.closed,
        updates: {'description': '수정된 설명'},
        currentTotalConfirmed: 0,
      );
      expect(err, isNull);
    });

    test('SCENARIO-TOM-10-010: FULL 상태 (open state) → 불변 필드 제한 없음', () {
      // FULL은 openStates에 포함 → 수정 허용
      final err = _validateTOUpdate(
        currentStatus: _TOStatus.full,
        updates: {'totalRequired': 10},
        currentTotalConfirmed: 5,
      );
      expect(err, isNull);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 11: updateSlotsDeadlines 마감시간 재계산
  // ──────────────────────────────────────────────────────────────────────────
  group('SCENARIO-TOM-11: updateSlotsDeadlines — 마감시간 재계산', () {
    test('SCENARIO-TOM-11-001: HOURS_BEFORE 방식 — startTime 기준 hoursBeforeStart 전', () {
      final slot = _Slot(
        id: 's1',
        toId: 'to-1',
        date: DateTime(2026, 8, 10),
        workDetails: [_WorkDetail(workType: '피킹', startTime: '09:00')],
      );
      final newDetails = [
        _WorkDetail(workType: '피킹', startTime: '09:00', endTime: '18:00'),
      ];
      final result = _recalculateSlotDeadlines(
        slot: slot,
        newWorkDetails: newDetails,
        deadlineType: 'HOURS_BEFORE',
        hoursBeforeStart: 2,
      );
      // 09:00 - 2시간 = 07:00
      expect(result.first.applicationDeadline, DateTime(2026, 8, 10, 7, 0));
    });

    test('SCENARIO-TOM-11-002: hoursBeforeStart=3 → startTime - 3시간', () {
      final slot = _Slot(
        id: 's1',
        toId: 'to-1',
        date: DateTime(2026, 8, 10),
        workDetails: [_WorkDetail(workType: '피킹', startTime: '14:00')],
      );
      final newDetails = [
        _WorkDetail(workType: '피킹', startTime: '14:00', endTime: '22:00'),
      ];
      final result = _recalculateSlotDeadlines(
        slot: slot,
        newWorkDetails: newDetails,
        deadlineType: 'HOURS_BEFORE',
        hoursBeforeStart: 3,
      );
      expect(result.first.applicationDeadline, DateTime(2026, 8, 10, 11, 0));
    });

    test('SCENARIO-TOM-11-003: FIXED_TIME 방식 → fixedDeadline 그대로 사용', () {
      final fixedDeadline = DateTime(2026, 8, 9, 23, 59);
      final slot = _Slot(
        id: 's1',
        toId: 'to-1',
        date: DateTime(2026, 8, 10),
        workDetails: [_WorkDetail(workType: '피킹')],
      );
      final newDetails = [
        _WorkDetail(workType: '피킹', startTime: '09:00', endTime: '18:00'),
      ];
      final result = _recalculateSlotDeadlines(
        slot: slot,
        newWorkDetails: newDetails,
        deadlineType: 'FIXED_TIME',
        hoursBeforeStart: 2,
        fixedDeadline: fixedDeadline,
      );
      expect(result.first.applicationDeadline, fixedDeadline);
    });

    test('SCENARIO-TOM-11-004: 슬롯 레벨 마감 = 업무상세 중 가장 이른 마감', () {
      final detail1 = _WorkDetail(
        workType: '피킹',
        applicationDeadline: DateTime(2026, 8, 10, 7, 0),
      );
      final detail2 = _WorkDetail(
        workType: '패킹',
        applicationDeadline: DateTime(2026, 8, 10, 6, 0), // 더 이른 마감
      );
      final slotDeadline = _slotDeadlineFromDetails([detail1, detail2]);
      expect(slotDeadline, DateTime(2026, 8, 10, 6, 0));
    });

    test('SCENARIO-TOM-11-005: 마감시간 없는 업무상세 → 슬롯 레벨 마감도 null', () {
      final detail = _WorkDetail(workType: '피킹');
      final slotDeadline = _slotDeadlineFromDetails([detail]);
      expect(slotDeadline, isNull);
    });

    test('SCENARIO-TOM-11-006: 기존 슬롯에 같은 workType 있으면 기존 상태(isManualClosed) 유지', () {
      final slot = _Slot(
        id: 's1',
        toId: 'to-1',
        date: DateTime(2026, 8, 10),
        workDetails: [
          _WorkDetail(workType: '피킹', startTime: '09:00', isManualClosed: true),
        ],
      );
      final newDetails = [
        _WorkDetail(workType: '피킹', startTime: '10:00', endTime: '18:00'),
      ];
      final result = _recalculateSlotDeadlines(
        slot: slot,
        newWorkDetails: newDetails,
        deadlineType: 'HOURS_BEFORE',
        hoursBeforeStart: 2,
      );
      // 기존 isManualClosed=true 유지
      expect(result.first.isManualClosed, isTrue);
      // 시작 시간은 새 값으로 갱신
      expect(result.first.startTime, '10:00');
    });

    test('SCENARIO-TOM-11-007: 새로운 workType → 기존 상태 없이 newDef 기준으로 생성', () {
      final slot = _Slot(
        id: 's1',
        toId: 'to-1',
        date: DateTime(2026, 8, 10),
        workDetails: [], // 기존 workDetail 없음
      );
      final newDetails = [
        _WorkDetail(workType: '청소', startTime: '08:00', endTime: '14:00'),
      ];
      final result = _recalculateSlotDeadlines(
        slot: slot,
        newWorkDetails: newDetails,
        deadlineType: 'HOURS_BEFORE',
        hoursBeforeStart: 2,
      );
      // 08:00 - 2시간 = 06:00
      expect(result.first.applicationDeadline, DateTime(2026, 8, 10, 6, 0));
      expect(result.first.isManualClosed, isFalse);
    });

    test('SCENARIO-TOM-11-008: 자정 넘어가는 경우 — 시작 02:00, 2시간 전 = 전날 22:00', () {
      final slot = _Slot(
        id: 's1',
        toId: 'to-1',
        date: DateTime(2026, 8, 10),
        workDetails: [],
      );
      final newDetails = [
        _WorkDetail(workType: '야간', startTime: '02:00', endTime: '10:00'),
      ];
      final result = _recalculateSlotDeadlines(
        slot: slot,
        newWorkDetails: newDetails,
        deadlineType: 'HOURS_BEFORE',
        hoursBeforeStart: 2,
      );
      // 2026-08-10 02:00 - 2h = 2026-08-10 00:00
      expect(result.first.applicationDeadline, DateTime(2026, 8, 10, 0, 0));
    });

    test('SCENARIO-TOM-11-009: 업무상세 2개일 때 각각 독립적으로 마감 계산됨', () {
      final slot = _Slot(
        id: 's1',
        toId: 'to-1',
        date: DateTime(2026, 8, 10),
        workDetails: [],
      );
      final newDetails = [
        _WorkDetail(workType: '피킹', startTime: '09:00', endTime: '18:00'),
        _WorkDetail(workType: '패킹', startTime: '14:00', endTime: '22:00'),
      ];
      final result = _recalculateSlotDeadlines(
        slot: slot,
        newWorkDetails: newDetails,
        deadlineType: 'HOURS_BEFORE',
        hoursBeforeStart: 2,
      );
      expect(result[0].applicationDeadline, DateTime(2026, 8, 10, 7, 0));  // 09:00 - 2h
      expect(result[1].applicationDeadline, DateTime(2026, 8, 10, 12, 0)); // 14:00 - 2h
    });

    test('SCENARIO-TOM-11-010: 슬롯 레벨 마감 = 두 업무 중 더 이른 것 (피킹 07:00 < 패킹 12:00)', () {
      final detail1 = _WorkDetail(
        workType: '피킹',
        applicationDeadline: DateTime(2026, 8, 10, 7, 0),
      );
      final detail2 = _WorkDetail(
        workType: '패킹',
        applicationDeadline: DateTime(2026, 8, 10, 12, 0),
      );
      final slotDeadline = _slotDeadlineFromDetails([detail1, detail2]);
      expect(slotDeadline, DateTime(2026, 8, 10, 7, 0));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 12: 복합 시나리오 — 실제 운영 흐름 통합 검증
  // ──────────────────────────────────────────────────────────────────────────
  group('SCENARIO-TOM-12: 복합 시나리오 — 실제 운영 흐름', () {
    test('SCENARIO-TOM-12-001: flex TO 생성 → 슬롯 마감 → TO 자동 CLOSED 전이', () {
      // 슬롯 2개 모두 closed → syncCascadeStatus → TO CLOSED
      final slots = [
        _Slot(id: 's1', toId: 'to-1', date: _now.add(const Duration(days: 1)),
              status: _SlotStatus.closed),
        _Slot(id: 's2', toId: 'to-1', date: _now.add(const Duration(days: 2)),
              status: _SlotStatus.closed),
      ];
      final result = _syncTOCascadeStatus(
        currentStatus: _TOStatus.active,
        slots: slots,
      );
      expect(result?['status'], _TOStatus.closed);
    });

    test('SCENARIO-TOM-12-002: CLOSED TO → 슬롯 재오픈 → TO 자동 ACTIVE 복구', () {
      final slots = [
        _Slot(id: 's1', toId: 'to-1', date: _now.add(const Duration(days: 1)),
              status: _SlotStatus.open),
      ];
      final result = _syncTOCascadeStatus(
        currentStatus: _TOStatus.closed,
        slots: slots,
      );
      expect(result?['status'], _TOStatus.active);
    });

    test('SCENARIO-TOM-12-003: 활성 제한 초과 + 슈퍼관리자 → 허용', () {
      final limitResult = _checkActiveTOLimit(
        activeCount: 100,
        limit: 4,
        isSuperAdmin: true,
        isDraft: false,
      );
      expect(limitResult.blocked, isFalse);
    });

    test('SCENARIO-TOM-12-004: flex 즉시공개 TO 생성 정상 흐름 — 3단계 완료', () {
      final log = _simulateFlexTOCreate(
        isFlexImmediate: true,
        slotCreateFails: false,
        dates: List.generate(3, (i) => _now.add(Duration(days: i + 1))),
      );
      // 세 단계 모두 정상 완료
      expect(log.any((e) => e.contains('step1')), isTrue);
      expect(log.any((e) => e.contains('step2')), isTrue);
      expect(log.any((e) => e.contains('step3')), isTrue);
      expect(log.any((e) => e.contains('rollback')), isFalse);
    });

    test('SCENARIO-TOM-12-005: batchCloseSlots 후 TO 자동 CLOSED — 순서 보장', () {
      final closeLog = _simulateBatchCloseSlots(
        slotIds: ['s1', 's2'],
        pendingAppsBySlot: {'s1': ['app1'], 's2': ['app2']},
      );
      // 1. 슬롯 마감 → 2. PENDING 취소 → 3. cascade sync
      final s1CloseIdx = closeLog.indexWhere((e) => e.contains('close_slot:s1'));
      final s2CloseIdx = closeLog.indexWhere((e) => e.contains('close_slot:s2'));
      final app1CancelIdx = closeLog.indexWhere((e) => e.contains('cancel_pending_app:app1'));
      final syncIdx = closeLog.indexWhere((e) => e.contains('sync_to_cascade_status'));

      expect(s1CloseIdx, lessThan(app1CancelIdx));
      expect(s2CloseIdx, lessThan(app1CancelIdx));
      expect(app1CancelIdx, lessThan(syncIdx));
    });

    test('SCENARIO-TOM-12-006: CLOSED TO + 불변 필드 수정 시도 → 차단 + 허용 필드는 통과', () {
      // workTypeIds → 차단
      final err1 = _validateTOUpdate(
        currentStatus: _TOStatus.closed,
        updates: {'workTypeIds': ['type-1']},
        currentTotalConfirmed: 0,
      );
      expect(err1, isNotNull);

      // title → 허용
      final err2 = _validateTOUpdate(
        currentStatus: _TOStatus.closed,
        updates: {'title': '새 제목'},
        currentTotalConfirmed: 0,
      );
      expect(err2, isNull);
    });

    test('SCENARIO-TOM-12-007: 인원 충족(isFull=true) → isClosed=true, TO 마감 탭에 표시됨', () {
      final to = _TOModel(
        id: 'to-full',
        status: _TOStatus.full,
        totalRequired: 10,
        totalConfirmed: 10,
        createdAt: _now,
      );
      expect(to.isFull, isTrue);
      expect(to.isClosed, isTrue);
    });

    test('SCENARIO-TOM-12-008: batchReopenSlots — full 슬롯은 open으로 안 됨, 나머지는 open됨', () {
      final slots = [
        _Slot(id: 's1', toId: 'to-1',
              date: _now.add(const Duration(days: 1)),
              status: _SlotStatus.closed,
              workDetails: [_WorkDetail(workType: '피킹', requiredCount: 5)],
              confirmedCount: 5), // full
        _Slot(id: 's2', toId: 'to-1',
              date: _now.add(const Duration(days: 2)),
              status: _SlotStatus.closed,
              workDetails: [_WorkDetail(workType: '패킹', requiredCount: 3)],
              confirmedCount: 1), // 미충족
      ];
      final results = _simulateBatchReopenSlots(slots: slots, reopenedBy: 'admin');
      // s1: full 유지
      expect(results.firstWhere((r) => r['slotId'] == 's1')['status'], _SlotStatus.full);
      // s2: open으로 복구
      expect(results.firstWhere((r) => r['slotId'] == 's2')['status'], _SlotStatus.open);
    });

    test('SCENARIO-TOM-12-009: isToItemClosed — TO isManualClosed가 날짜 미래여도 최우선 마감', () {
      final closedTO = _TOModel(
        id: 'to-1',
        isManualClosed: true,
        createdAt: _now,
      );
      // 슬롯 날짜가 30일 후이고 workDetail 마감도 없지만
      // TO 레벨 isManualClosed=true → 즉시 마감
      final slot = _Slot(
        id: 's1',
        toId: 'to-1',
        date: _now.add(const Duration(days: 30)),
        workDetails: [
          _WorkDetail(
            workType: '피킹',
            applicationDeadline: _now.add(const Duration(hours: 24)),
          ),
        ],
      );
      final item = _TOItem(
        to: closedTO,
        slot: slot,
        workDetails: slot.workDetails,
        confirmedCount: 0,
        totalRequired: 5,
        isWorkDetailLoaded: true,
      );
      expect(_isToItemClosed(item, _now), isTrue);
    });

    test('SCENARIO-TOM-12-010: updateSlotsDeadlines — 마감시간 변경 시 모든 슬롯 재계산', () {
      // 슬롯 3개, 모두 같은 workType, startTime 변경 → 각각 독립 계산
      final slots = List.generate(3, (i) => _Slot(
        id: 's$i',
        toId: 'to-1',
        date: DateTime(2026, 8, 10 + i),
        workDetails: [_WorkDetail(workType: '피킹', startTime: '09:00')],
      ));
      final newDetails = [
        _WorkDetail(workType: '피킹', startTime: '11:00', endTime: '20:00'),
      ];
      for (final slot in slots) {
        final result = _recalculateSlotDeadlines(
          slot: slot,
          newWorkDetails: newDetails,
          deadlineType: 'HOURS_BEFORE',
          hoursBeforeStart: 2,
        );
        // 11:00 - 2h = 09:00, 날짜는 각 슬롯의 날짜
        expect(result.first.applicationDeadline?.hour, 9);
        expect(result.first.applicationDeadline?.minute, 0);
      }
    });
  });
}
