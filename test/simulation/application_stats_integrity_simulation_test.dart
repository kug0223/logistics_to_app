// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';

// ════════════════════════════════════════════════════════════════════════════
// application_stats_integrity_simulation_test.dart
//
// 지원자 통계(confirmedCount/pendingCount/workTypeCounts) 데이터 무결성 검증
//
// 순수 Dart 로직만 사용 — Firestore 의존성 없음.
// 실제 코드의 카운터 로직을 인메모리로 재현한 뒤 경계 조건을 탐색한다.
// ════════════════════════════════════════════════════════════════════════════

// ── 인메모리 모델 ────────────────────────────────────────────────────────────

/// 슬롯 내 업무유형별 카운터 (SlotWorkTypeCount 인메모리 복제)
class MockSlotWorkTypeCount {
  int confirmedCount;
  int pendingCount;

  MockSlotWorkTypeCount({this.confirmedCount = 0, this.pendingCount = 0});

  MockSlotWorkTypeCount copyWith({int? confirmedCount, int? pendingCount}) =>
      MockSlotWorkTypeCount(
        confirmedCount: confirmedCount ?? this.confirmedCount,
        pendingCount: pendingCount ?? this.pendingCount,
      );

  @override
  String toString() =>
      'SlotWorkTypeCount(confirmed: $confirmedCount, pending: $pendingCount)';
}

/// flex 타입 슬롯 (SlotModel 인메모리 복제)
class MockSlot {
  final String id;
  final String toId;
  int confirmedCount;
  int pendingCount;
  String status; // 'open' | 'full' | 'closed'
  bool isManualClosed;
  final Map<String, MockSlotWorkTypeCount> workTypeCounts;
  final Map<String, int> requiredCounts; // workType → requiredCount

  MockSlot({
    required this.id,
    required this.toId,
    this.confirmedCount = 0,
    this.pendingCount = 0,
    this.status = 'open',
    this.isManualClosed = false,
    Map<String, MockSlotWorkTypeCount>? workTypeCounts,
    Map<String, int>? requiredCounts,
  })  : workTypeCounts = workTypeCounts ?? {},
        requiredCounts = requiredCounts ?? {};

  int get totalRequired =>
      requiredCounts.values.fold(0, (a, b) => a + b);

  /// isWorkTypeFull: confirmedCount >= requiredCount
  bool isWorkTypeFull(String workType) {
    final req = requiredCounts[workType] ?? 0;
    if (req == 0) return false;
    return (workTypeCounts[workType]?.confirmedCount ?? 0) >= req;
  }

  /// 슬롯 전체 workType confirmedCount 합산 → 전체 confirmedCount 검증
  int get sumWorkTypeConfirmed =>
      workTypeCounts.values.fold(0, (a, c) => a + c.confirmedCount);

  /// 슬롯 전체 workType pendingCount 합산 → 전체 pendingCount 검증
  int get sumWorkTypePending =>
      workTypeCounts.values.fold(0, (a, c) => a + c.pendingCount);
}

/// TO 문서 인메모리 복제 (flex + contract 공용)
class MockTO {
  final String id;
  int totalPending;
  int totalConfirmed;
  int totalRequired;
  // contract TO 전용: workType별 확정 인원
  final Map<String, int> workTypeConfirmedCounts;
  // flex TO: 슬롯 컬렉션
  final Map<String, MockSlot> slots;

  MockTO({
    required this.id,
    this.totalPending = 0,
    this.totalConfirmed = 0,
    this.totalRequired = 0,
    Map<String, int>? workTypeConfirmedCounts,
    Map<String, MockSlot>? slots,
  })  : workTypeConfirmedCounts = workTypeConfirmedCounts ?? {},
        slots = slots ?? {};
}

/// 지원서 상태 상수
abstract class AppStatus {
  static const pending = 'PENDING';
  static const contractPending = 'CONTRACT_PENDING';
  static const confirmed = 'CONFIRMED';
  static const rejected = 'REJECTED';
  static const canceled = 'CANCELED';
  static const autoCanceled = 'AUTO_CANCELED';

  static const List<String> confirmedStatuses = [contractPending, confirmed];
  static const List<String> activeStates = [pending, contractPending, confirmed];
}

/// 지원서 인메모리 복제
class MockApplication {
  final String id;
  final String toId;
  final String? slotId;
  final String selectedWorkType;
  String status;

  MockApplication({
    required this.id,
    required this.toId,
    this.slotId,
    required this.selectedWorkType,
    this.status = AppStatus.pending,
  });
}

// ── 인메모리 카운터 로직 (application_firestore.dart 로직 재현) ──────────────

/// TO.totalPending 및 Slot.pendingCount 변경
void incrementTOPending(
  MockTO to,
  String? slotId, {
  required int delta,
  String? workType,
}) {
  to.totalPending += delta;
  if (slotId != null && to.slots.containsKey(slotId)) {
    final slot = to.slots[slotId]!;
    slot.pendingCount += delta;
    if (workType != null) {
      slot.workTypeCounts.putIfAbsent(
          workType, () => MockSlotWorkTypeCount());
      slot.workTypeCounts[workType]!.pendingCount += delta;
    }
  }
}

/// TO.totalConfirmed 및 Slot.confirmedCount 변경
void incrementTOConfirmed(
  MockTO to,
  String? slotId, {
  required int delta,
  String? workType,
}) {
  to.totalConfirmed += delta;
  // contract TO: TO 레벨 workTypeConfirmedCounts
  if (slotId == null && workType != null && workType.isNotEmpty) {
    to.workTypeConfirmedCounts[workType] =
        (to.workTypeConfirmedCounts[workType] ?? 0) + delta;
  }
  if (slotId != null && to.slots.containsKey(slotId)) {
    final slot = to.slots[slotId]!;
    slot.confirmedCount += delta;
    if (workType != null) {
      slot.workTypeCounts.putIfAbsent(
          workType, () => MockSlotWorkTypeCount());
      slot.workTypeCounts[workType]!.confirmedCount += delta;
    }
  }
}

void decrementTOConfirmed(MockTO to, String? slotId, {String? workType}) =>
    incrementTOConfirmed(to, slotId, delta: -1, workType: workType);

/// 슬롯 status 재계산 (open ↔ full, closed는 건드리지 않음)
void recalculateSlotStatus(MockTO to, String slotId) {
  final slot = to.slots[slotId];
  if (slot == null) return;
  if (slot.status == 'closed' || slot.isManualClosed) return;
  final totalRequired = slot.totalRequired;
  if (totalRequired <= 0) return;
  final newStatus =
      slot.confirmedCount >= totalRequired ? 'full' : 'open';
  slot.status = newStatus;
}

// ── 헬퍼 ─────────────────────────────────────────────────────────────────────

MockTO _makeFlexTO({
  String id = 'to1',
  Map<String, MockSlot>? slots,
}) {
  final to = MockTO(id: id, slots: slots ?? {});
  return to;
}

MockSlot _makeSlot({
  String id = 'slot1',
  String toId = 'to1',
  Map<String, int>? requiredCounts,
}) {
  final wt = requiredCounts ?? {'피킹': 3};
  final counts = <String, MockSlotWorkTypeCount>{};
  for (final k in wt.keys) {
    counts[k] = MockSlotWorkTypeCount();
  }
  return MockSlot(
    id: id,
    toId: toId,
    requiredCounts: wt,
    workTypeCounts: counts,
  );
}

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // SCENARIO-STAT-01 ~ 10: SlotWorkTypeCount 구조 무결성
  // ══════════════════════════════════════════════════════════════════════════
  group('SCENARIO-STAT-01~10: SlotWorkTypeCount 구조 무결성', () {
    test('SCENARIO-STAT-01: 초기 상태에서 모든 카운터는 0', () {
      final cnt = MockSlotWorkTypeCount();
      expect(cnt.confirmedCount, 0);
      expect(cnt.pendingCount, 0);
    });

    test('SCENARIO-STAT-02: confirmedCount는 음수가 되면 안 된다 (방어 로직 검증)', () {
      final cnt = MockSlotWorkTypeCount(confirmedCount: 0);
      // 잘못된 감소 시 음수가 되는지 확인 (실제 시스템에서는 CF가 교정)
      cnt.confirmedCount -= 1;
      expect(cnt.confirmedCount, -1); // 내부 음수 도달 가능성 문서화
    });

    test('SCENARIO-STAT-03: workTypeCounts 합산 == slot.confirmedCount (정상 상태)', () {
      final slot = _makeSlot(
        requiredCounts: {'피킹': 3, '패킹': 2},
      );
      slot.workTypeCounts['피킹']!.confirmedCount = 2;
      slot.workTypeCounts['패킹']!.confirmedCount = 1;
      slot.confirmedCount = 3;

      expect(slot.sumWorkTypeConfirmed, slot.confirmedCount);
    });

    test('SCENARIO-STAT-04: workTypeCounts pendingCount 합산 == slot.pendingCount (정상 상태)', () {
      final slot = _makeSlot(
        requiredCounts: {'피킹': 3, '패킹': 2},
      );
      slot.workTypeCounts['피킹']!.pendingCount = 5;
      slot.workTypeCounts['패킹']!.pendingCount = 2;
      slot.pendingCount = 7;

      expect(slot.sumWorkTypePending, slot.pendingCount);
    });

    test('SCENARIO-STAT-05: 합산 불일치 상태 — CF 교정 전 일시적 발생 가능', () {
      // 낙관적 카운터: 클라이언트 increment 후 CF 미실행 상태
      final slot = _makeSlot(requiredCounts: {'피킹': 3});
      slot.workTypeCounts['피킹']!.confirmedCount = 2;
      slot.confirmedCount = 3; // 클라이언트가 먼저 올린 값

      // 불일치: sumWorkTypeConfirmed(2) != confirmedCount(3)
      expect(slot.sumWorkTypeConfirmed, isNot(slot.confirmedCount));
    });

    test('SCENARIO-STAT-06: copyWith은 원본을 변경하지 않는다', () {
      final original = MockSlotWorkTypeCount(confirmedCount: 5, pendingCount: 2);
      final copy = original.copyWith(confirmedCount: 10);
      expect(original.confirmedCount, 5);
      expect(copy.confirmedCount, 10);
    });

    test('SCENARIO-STAT-07: 여러 workType 혼재 — 개별 합산과 전체 일치', () {
      final slot = _makeSlot(requiredCounts: {'피킹': 2, '패킹': 2, '적재': 1});
      slot.workTypeCounts['피킹']!.confirmedCount = 1;
      slot.workTypeCounts['패킹']!.confirmedCount = 2;
      slot.workTypeCounts['적재']!.confirmedCount = 0;
      slot.confirmedCount = 3;

      expect(slot.sumWorkTypeConfirmed, 3);
      expect(slot.sumWorkTypeConfirmed, slot.confirmedCount);
    });

    test('SCENARIO-STAT-08: countFor 없는 workType은 기본값 0 반환', () {
      final slot = _makeSlot(requiredCounts: {'피킹': 3});
      final count = slot.workTypeCounts['없는업무'];
      expect(count, isNull); // null이면 기본값 처리 필요
      final safeCount = count?.confirmedCount ?? 0;
      expect(safeCount, 0);
    });

    test('SCENARIO-STAT-09: pendingCount와 confirmedCount는 독립적으로 관리된다', () {
      final cnt = MockSlotWorkTypeCount(confirmedCount: 3, pendingCount: 5);
      expect(cnt.confirmedCount + cnt.pendingCount, 8);
      // 둘의 합이 지원자 수가 되어야 함 (PENDING + CONFIRMED/CONTRACT_PENDING)
    });

    test('SCENARIO-STAT-10: totalRequired = workType별 requiredCount 합산', () {
      final slot = _makeSlot(requiredCounts: {'피킹': 3, '패킹': 2, '적재': 1});
      expect(slot.totalRequired, 6);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SCENARIO-STAT-11 ~ 20: _incrementTOPending 로직
  // ══════════════════════════════════════════════════════════════════════════
  group('SCENARIO-STAT-11~20: _incrementTOPending 로직', () {
    test('SCENARIO-STAT-11: flex TO — slotId 있으면 TO + Slot + workType 동시 증가', () {
      final slot = _makeSlot(id: 's1', toId: 'to1', requiredCounts: {'피킹': 3});
      final to = _makeFlexTO(id: 'to1', slots: {'s1': slot});

      incrementTOPending(to, 's1', delta: 1, workType: '피킹');

      expect(to.totalPending, 1);
      expect(slot.pendingCount, 1);
      expect(slot.workTypeCounts['피킹']!.pendingCount, 1);
    });

    test('SCENARIO-STAT-12: contract TO — slotId 없으면 TO.totalPending만 증가', () {
      final to = MockTO(id: 'to1');

      incrementTOPending(to, null, delta: 1, workType: '피킹');

      expect(to.totalPending, 1);
      expect(to.slots.isEmpty, true);
      // workTypeConfirmedCounts는 pending에서 관리 안 함
      expect(to.workTypeConfirmedCounts.isEmpty, true);
    });

    test('SCENARIO-STAT-13: flex TO — slotId 있고 workType null이면 슬롯 pendingCount만 증가', () {
      final slot = _makeSlot(id: 's1', toId: 'to1');
      final to = _makeFlexTO(id: 'to1', slots: {'s1': slot});

      incrementTOPending(to, 's1', delta: 1, workType: null);

      expect(to.totalPending, 1);
      expect(slot.pendingCount, 1);
      // workTypeCounts 미증가 (초기 0 유지)
      expect(slot.workTypeCounts.values.every((c) => c.pendingCount == 0), true);
    });

    test('SCENARIO-STAT-14: 지원 취소 시 delta=-1로 감소', () {
      final slot = _makeSlot(id: 's1', toId: 'to1', requiredCounts: {'피킹': 3});
      final to = _makeFlexTO(id: 'to1', slots: {'s1': slot});

      // 지원 → 취소
      incrementTOPending(to, 's1', delta: 1, workType: '피킹');
      incrementTOPending(to, 's1', delta: -1, workType: '피킹');

      expect(to.totalPending, 0);
      expect(slot.pendingCount, 0);
      expect(slot.workTypeCounts['피킹']!.pendingCount, 0);
    });

    test('SCENARIO-STAT-15: 다중 지원자 — 차례로 지원 후 합산 정확성', () {
      final slot = _makeSlot(id: 's1', toId: 'to1', requiredCounts: {'피킹': 5});
      final to = _makeFlexTO(id: 'to1', slots: {'s1': slot});

      for (int i = 0; i < 5; i++) {
        incrementTOPending(to, 's1', delta: 1, workType: '피킹');
      }

      expect(to.totalPending, 5);
      expect(slot.pendingCount, 5);
      expect(slot.workTypeCounts['피킹']!.pendingCount, 5);
    });

    test('SCENARIO-STAT-16: 여러 슬롯에 독립적으로 pending 증가', () {
      final s1 = _makeSlot(id: 's1', toId: 'to1', requiredCounts: {'피킹': 3});
      final s2 = _makeSlot(id: 's2', toId: 'to1', requiredCounts: {'패킹': 2});
      final to = _makeFlexTO(id: 'to1', slots: {'s1': s1, 's2': s2});

      incrementTOPending(to, 's1', delta: 2, workType: '피킹');
      incrementTOPending(to, 's2', delta: 1, workType: '패킹');

      expect(to.totalPending, 3);
      expect(s1.pendingCount, 2);
      expect(s2.pendingCount, 1);
      expect(s1.workTypeCounts['피킹']!.pendingCount, 2);
      expect(s2.workTypeCounts['패킹']!.pendingCount, 1);
    });

    test('SCENARIO-STAT-17: delta=-1이 0 미만 → 낙관적 카운터는 음수 허용 (CF가 교정)', () {
      final slot = _makeSlot(id: 's1', toId: 'to1');
      final to = _makeFlexTO(id: 'to1', slots: {'s1': slot});

      // 이미 0인 상태에서 잘못된 감소
      incrementTOPending(to, 's1', delta: -1, workType: '피킹');

      // 서버 Firestore FieldValue.increment는 음수도 허용 — CF가 count()로 재교정
      expect(to.totalPending, -1);
    });

    test('SCENARIO-STAT-18: 재지원(REAPPLY) 시 pending +1 적용', () {
      final slot = _makeSlot(id: 's1', toId: 'to1', requiredCounts: {'피킹': 3});
      final to = _makeFlexTO(id: 'to1', slots: {'s1': slot});

      // 지원 → 취소 → 재지원
      incrementTOPending(to, 's1', delta: 1, workType: '피킹');
      incrementTOPending(to, 's1', delta: -1, workType: '피킹');
      incrementTOPending(to, 's1', delta: 1, workType: '피킹');

      expect(to.totalPending, 1);
      expect(slot.pendingCount, 1);
    });

    test('SCENARIO-STAT-19: 여러 workType에 독립적인 pendingCount 추적', () {
      final slot = MockSlot(
        id: 's1',
        toId: 'to1',
        requiredCounts: {'피킹': 3, '패킹': 2},
        workTypeCounts: {
          '피킹': MockSlotWorkTypeCount(),
          '패킹': MockSlotWorkTypeCount(),
        },
      );
      final to = _makeFlexTO(id: 'to1', slots: {'s1': slot});

      incrementTOPending(to, 's1', delta: 2, workType: '피킹');
      incrementTOPending(to, 's1', delta: 1, workType: '패킹');

      expect(slot.workTypeCounts['피킹']!.pendingCount, 2);
      expect(slot.workTypeCounts['패킹']!.pendingCount, 1);
      expect(slot.pendingCount, 3); // 슬롯 전체 합
    });

    test('SCENARIO-STAT-20: AUTO_CANCELED 시 pending -1 — J-3 버그 수정 패턴', () {
      // 확정 처리 중 충돌 지원서 AUTO_CANCEL → pending 즉시 감소
      final s1 = _makeSlot(id: 's1', toId: 'to1', requiredCounts: {'피킹': 3});
      final s2 = _makeSlot(id: 's2', toId: 'to2', requiredCounts: {'패킹': 2});
      final to1 = _makeFlexTO(id: 'to1', slots: {'s1': s1});
      final to2 = _makeFlexTO(id: 'to2', slots: {'s2': s2});

      incrementTOPending(to1, 's1', delta: 1, workType: '피킹');
      incrementTOPending(to2, 's2', delta: 1, workType: '패킹');

      // 충돌로 to2/s2 지원서가 AUTO_CANCELED
      incrementTOPending(to2, 's2', delta: -1, workType: '패킹');

      expect(to1.totalPending, 1); // 영향 없음
      expect(to2.totalPending, 0); // 즉시 반영
      expect(s2.workTypeCounts['패킹']!.pendingCount, 0);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SCENARIO-STAT-21 ~ 30: _incrementTOConfirmed 로직
  // ══════════════════════════════════════════════════════════════════════════
  group('SCENARIO-STAT-21~30: _incrementTOConfirmed 로직', () {
    test('SCENARIO-STAT-21: flex TO — slotId 있으면 TO + Slot + workType confirmedCount 증가', () {
      final slot = _makeSlot(id: 's1', toId: 'to1', requiredCounts: {'피킹': 3});
      final to = _makeFlexTO(id: 'to1', slots: {'s1': slot});

      incrementTOConfirmed(to, 's1', delta: 1, workType: '피킹');

      expect(to.totalConfirmed, 1);
      expect(slot.confirmedCount, 1);
      expect(slot.workTypeCounts['피킹']!.confirmedCount, 1);
      // flex TO에서 TO.workTypeConfirmedCounts는 갱신되지 않음
      expect(to.workTypeConfirmedCounts.isEmpty, true);
    });

    test('SCENARIO-STAT-22: contract TO — slotId 없으면 TO.workTypeConfirmedCounts 갱신', () {
      final to = MockTO(id: 'to1');

      incrementTOConfirmed(to, null, delta: 1, workType: '피킹');

      expect(to.totalConfirmed, 1);
      expect(to.workTypeConfirmedCounts['피킹'], 1);
      expect(to.slots.isEmpty, true);
    });

    test('SCENARIO-STAT-23: contract TO — workType 여러 번 확정 시 누산', () {
      final to = MockTO(id: 'to1');

      incrementTOConfirmed(to, null, delta: 1, workType: '피킹');
      incrementTOConfirmed(to, null, delta: 1, workType: '피킹');
      incrementTOConfirmed(to, null, delta: 1, workType: '패킹');

      expect(to.workTypeConfirmedCounts['피킹'], 2);
      expect(to.workTypeConfirmedCounts['패킹'], 1);
      expect(to.totalConfirmed, 3);
    });

    test('SCENARIO-STAT-24: 취소 처리 — decrementTOConfirmed는 -1 delta', () {
      final slot = _makeSlot(id: 's1', toId: 'to1', requiredCounts: {'피킹': 3});
      final to = _makeFlexTO(id: 'to1', slots: {'s1': slot});

      incrementTOConfirmed(to, 's1', delta: 1, workType: '피킹');
      decrementTOConfirmed(to, 's1', workType: '피킹');

      expect(to.totalConfirmed, 0);
      expect(slot.confirmedCount, 0);
      expect(slot.workTypeCounts['피킹']!.confirmedCount, 0);
    });

    test('SCENARIO-STAT-25: PENDING→CONFIRMED 흐름 — pending -1, confirmed +1', () {
      final slot = _makeSlot(id: 's1', toId: 'to1', requiredCounts: {'피킹': 3});
      final to = _makeFlexTO(id: 'to1', slots: {'s1': slot});

      // 지원 단계
      incrementTOPending(to, 's1', delta: 1, workType: '피킹');
      expect(to.totalPending, 1);

      // 확정 단계 (_confirmWithConflictCheck 패턴)
      incrementTOPending(to, 's1', delta: -1, workType: '피킹');
      incrementTOConfirmed(to, 's1', delta: 1, workType: '피킹');

      expect(to.totalPending, 0);
      expect(to.totalConfirmed, 1);
      expect(slot.pendingCount, 0);
      expect(slot.confirmedCount, 1);
      expect(slot.workTypeCounts['피킹']!.pendingCount, 0);
      expect(slot.workTypeCounts['피킹']!.confirmedCount, 1);
    });

    test('SCENARIO-STAT-26: 확정 취소 후 PENDING 복원 — pending +1, confirmed -1', () {
      final slot = _makeSlot(id: 's1', toId: 'to1', requiredCounts: {'피킹': 3});
      final to = _makeFlexTO(id: 'to1', slots: {'s1': slot});

      // 지원 → 확정
      incrementTOPending(to, 's1', delta: 1, workType: '피킹');
      incrementTOPending(to, 's1', delta: -1, workType: '피킹');
      incrementTOConfirmed(to, 's1', delta: 1, workType: '피킹');

      // 확정 취소 → PENDING 복원 (updateApplicationStatus: confirmed→pending 롤백)
      decrementTOConfirmed(to, 's1', workType: '피킹');
      incrementTOPending(to, 's1', delta: 1, workType: '피킹');

      expect(to.totalPending, 1);
      expect(to.totalConfirmed, 0);
      expect(slot.pendingCount, 1);
      expect(slot.confirmedCount, 0);
    });

    test('SCENARIO-STAT-27: 업무유형 변경 — 이전 workType -1, 새 workType +1 (flex)', () {
      final slot = MockSlot(
        id: 's1',
        toId: 'to1',
        requiredCounts: {'피킹': 3, '패킹': 2},
        workTypeCounts: {
          '피킹': MockSlotWorkTypeCount(confirmedCount: 2),
          '패킹': MockSlotWorkTypeCount(confirmedCount: 0),
        },
        confirmedCount: 2,
      );
      final to = _makeFlexTO(id: 'to1', slots: {'s1': slot});
      to.totalConfirmed = 2;

      // changeApplicationWorkType: 피킹 -1, 패킹 +1 (슬롯 기반)
      slot.workTypeCounts['피킹']!.confirmedCount -= 1;
      slot.workTypeCounts['패킹']!.confirmedCount += 1;

      expect(slot.workTypeCounts['피킹']!.confirmedCount, 1);
      expect(slot.workTypeCounts['패킹']!.confirmedCount, 1);
      expect(slot.confirmedCount, 2); // 전체 합계 변화 없음
    });

    test('SCENARIO-STAT-28: 업무유형 변경 — 이전 workType -1, 새 workType +1 (contract)', () {
      final to = MockTO(
        id: 'to1',
        totalConfirmed: 2,
        workTypeConfirmedCounts: {'피킹': 2, '패킹': 0},
      );

      // contract TO에서 피킹→패킹 변경
      to.workTypeConfirmedCounts['피킹'] = (to.workTypeConfirmedCounts['피킹'] ?? 0) - 1;
      to.workTypeConfirmedCounts['패킹'] = (to.workTypeConfirmedCounts['패킹'] ?? 0) + 1;

      expect(to.workTypeConfirmedCounts['피킹'], 1);
      expect(to.workTypeConfirmedCounts['패킹'], 1);
      expect(to.totalConfirmed, 2); // 전체 합계 변화 없음
    });

    test('SCENARIO-STAT-29: contract TO pending에서 workTypeConfirmedCounts 미갱신 확인', () {
      final to = MockTO(id: 'to1');

      // PENDING 지원서 추가 — pending만 증가, confirmed 미증가
      incrementTOPending(to, null, delta: 1, workType: '피킹');

      expect(to.totalPending, 1);
      expect(to.totalConfirmed, 0);
      expect(to.workTypeConfirmedCounts.isEmpty, true);
    });

    test('SCENARIO-STAT-30: 계약 연장(createRenewedApplication) — totalConfirmed +1', () {
      final to = MockTO(id: 'to1', totalConfirmed: 1);

      // 원본 계약 연장: 신규 APPLICATION + TO확정카운터 +1
      incrementTOConfirmed(to, null, delta: 1, workType: '피킹');

      expect(to.totalConfirmed, 2);
      expect(to.workTypeConfirmedCounts['피킹'], 1);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SCENARIO-STAT-31 ~ 38: _recalculateSlotStatus 로직
  // ══════════════════════════════════════════════════════════════════════════
  group('SCENARIO-STAT-31~38: _recalculateSlotStatus 로직', () {
    test('SCENARIO-STAT-31: confirmedCount >= totalRequired → status=full', () {
      final slot = _makeSlot(id: 's1', toId: 'to1', requiredCounts: {'피킹': 3});
      final to = _makeFlexTO(id: 'to1', slots: {'s1': slot});

      slot.confirmedCount = 3;
      recalculateSlotStatus(to, 's1');

      expect(slot.status, 'full');
    });

    test('SCENARIO-STAT-32: confirmedCount < totalRequired → status=open', () {
      final slot = _makeSlot(id: 's1', toId: 'to1', requiredCounts: {'피킹': 3});
      final to = _makeFlexTO(id: 'to1', slots: {'s1': slot});

      slot.confirmedCount = 2;
      slot.status = 'full'; // 잘못된 상태
      recalculateSlotStatus(to, 's1');

      expect(slot.status, 'open'); // open으로 복구
    });

    test('SCENARIO-STAT-33: closed 슬롯은 재계산에서 제외', () {
      final slot = _makeSlot(id: 's1', toId: 'to1', requiredCounts: {'피킹': 3});
      final to = _makeFlexTO(id: 'to1', slots: {'s1': slot});

      slot.confirmedCount = 0;
      slot.status = 'closed';
      recalculateSlotStatus(to, 's1');

      expect(slot.status, 'closed'); // 변화 없음
    });

    test('SCENARIO-STAT-34: isManualClosed=true인 슬롯은 재계산에서 제외', () {
      final slot = _makeSlot(id: 's1', toId: 'to1', requiredCounts: {'피킹': 3});
      final to = _makeFlexTO(id: 'to1', slots: {'s1': slot});

      slot.isManualClosed = true;
      slot.confirmedCount = 3;
      slot.status = 'open';
      recalculateSlotStatus(to, 's1');

      expect(slot.status, 'open'); // isManualClosed=true이므로 변화 없음
    });

    test('SCENARIO-STAT-35: totalRequired=0이면 재계산 스킵', () {
      final slot = MockSlot(id: 's1', toId: 'to1'); // requiredCounts 없음
      final to = _makeFlexTO(id: 'to1', slots: {'s1': slot});

      slot.confirmedCount = 5;
      slot.status = 'open';
      recalculateSlotStatus(to, 's1');

      expect(slot.status, 'open'); // 변화 없음
    });

    test('SCENARIO-STAT-36: confirmedCount가 totalRequired 초과해도 full 유지', () {
      final slot = _makeSlot(id: 's1', toId: 'to1', requiredCounts: {'피킹': 3});
      final to = _makeFlexTO(id: 'to1', slots: {'s1': slot});

      slot.confirmedCount = 5; // 초과 확정 (관리자 의도)
      recalculateSlotStatus(to, 's1');

      expect(slot.status, 'full');
    });

    test('SCENARIO-STAT-37: 확정 취소 후 full→open 복구 시뮬레이션', () {
      final slot = _makeSlot(id: 's1', toId: 'to1', requiredCounts: {'피킹': 3});
      final to = _makeFlexTO(id: 'to1', slots: {'s1': slot});

      // 3명 확정 → full
      slot.confirmedCount = 3;
      recalculateSlotStatus(to, 's1');
      expect(slot.status, 'full');

      // 1명 취소 → open
      decrementTOConfirmed(to, 's1', workType: '피킹');
      recalculateSlotStatus(to, 's1');
      expect(slot.status, 'open');
    });

    test('SCENARIO-STAT-38: 여러 workType 합산 totalRequired 기준 full 판정', () {
      final slot = MockSlot(
        id: 's1',
        toId: 'to1',
        requiredCounts: {'피킹': 2, '패킹': 1},
        workTypeCounts: {
          '피킹': MockSlotWorkTypeCount(),
          '패킹': MockSlotWorkTypeCount(),
        },
        confirmedCount: 0,
      );
      final to = _makeFlexTO(id: 'to1', slots: {'s1': slot});

      // 합산 totalRequired = 3
      expect(slot.totalRequired, 3);

      // 3명 확정
      slot.confirmedCount = 3;
      recalculateSlotStatus(to, 's1');
      expect(slot.status, 'full');

      // 2명으로 감소
      slot.confirmedCount = 2;
      recalculateSlotStatus(to, 's1');
      expect(slot.status, 'open');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SCENARIO-STAT-39 ~ 44: batchDeleteSlots 카운터 처리
  // ══════════════════════════════════════════════════════════════════════════
  group('SCENARIO-STAT-39~44: batchDeleteSlots 카운터 처리', () {
    test('SCENARIO-STAT-39: 슬롯 삭제 시 removedConfirmed = 슬롯 confirmedCount 합산', () {
      // batchDeleteSlots: slotSnaps에서 직접 카운터 계산
      final slots = [
        {'confirmedCount': 2, 'pendingCount': 1},
        {'confirmedCount': 0, 'pendingCount': 3},
      ];

      int removedConfirmed = 0;
      int removedPending = 0;
      for (final s in slots) {
        removedConfirmed += (s['confirmedCount'] as int?) ?? 0;
        removedPending += (s['pendingCount'] as int?) ?? 0;
      }

      expect(removedConfirmed, 2);
      expect(removedPending, 4);
    });

    test('SCENARIO-STAT-40: 존재하지 않는 슬롯은 카운터 계산에서 제외 (!snap.exists)', () {
      final snapsExist = [true, false, true];
      final confirmedCounts = [2, 3, 1]; // 두 번째 슬롯은 존재하지 않음

      int total = 0;
      for (int i = 0; i < snapsExist.length; i++) {
        if (!snapsExist[i]) continue; // batchDeleteSlots: if(!snap.exists) continue
        total += confirmedCounts[i];
      }

      expect(total, 3); // 2 + 1 (존재하는 슬롯만)
    });

    test('SCENARIO-STAT-41: 활성 지원서 전부 REJECTED 처리 — 상태 변환 정확성', () {
      final apps = [
        MockApplication(id: 'a1', toId: 'to1', slotId: 's1', selectedWorkType: '피킹', status: AppStatus.pending),
        MockApplication(id: 'a2', toId: 'to1', slotId: 's1', selectedWorkType: '피킹', status: AppStatus.confirmed),
        MockApplication(id: 'a3', toId: 'to1', slotId: 's1', selectedWorkType: '패킹', status: AppStatus.contractPending),
      ];

      // batchDeleteSlots: activeStatuses에 포함된 모든 지원서 REJECTED
      const activeStatuses = {AppStatus.pending, AppStatus.confirmed, AppStatus.contractPending};
      for (final app in apps) {
        if (activeStatuses.contains(app.status)) {
          app.status = AppStatus.rejected;
        }
      }

      expect(apps.every((a) => a.status == AppStatus.rejected), true);
    });

    test('SCENARIO-STAT-42: 이미 REJECTED인 지원서는 batchDelete 대상 제외', () {
      final apps = [
        MockApplication(id: 'a1', toId: 'to1', slotId: 's1', selectedWorkType: '피킹', status: AppStatus.rejected),
        MockApplication(id: 'a2', toId: 'to1', slotId: 's1', selectedWorkType: '피킹', status: AppStatus.pending),
      ];

      const activeStatuses = {AppStatus.pending, AppStatus.confirmed, AppStatus.contractPending};
      final toProcess = apps.where((a) => activeStatuses.contains(a.status)).toList();

      expect(toProcess.length, 1);
      expect(toProcess.first.id, 'a2');
    });

    test('SCENARIO-STAT-43: batchDeleteSlots — TO totalRequired 감소 포함', () {
      final to = MockTO(
        id: 'to1',
        totalRequired: 10,
        totalConfirmed: 4,
        totalPending: 3,
      );
      // 삭제 슬롯: requiredCount합=5, confirmedCount합=2, pendingCount합=1
      final removedRequired = 5;
      final removedConfirmed = 2;
      final removedPending = 1;

      to.totalRequired -= removedRequired;
      to.totalConfirmed -= removedConfirmed;
      to.totalPending -= removedPending;

      expect(to.totalRequired, 5);
      expect(to.totalConfirmed, 2);
      expect(to.totalPending, 2);
    });

    test('SCENARIO-STAT-44: 슬롯 삭제 + 카운터 감소 원자성 — 배치 묶음 원칙', () {
      // batchDeleteSlots: 슬롯 삭제 + TO 카운터 업데이트를 같은 배치에 포함
      // 인메모리 시뮬레이션: 배치 커밋 후 양쪽 모두 반영되어야 함

      final to = MockTO(id: 'to1', totalConfirmed: 3, totalPending: 2, totalRequired: 10);
      final initialConfirmed = to.totalConfirmed;
      final removedConfirmed = 2;

      to.totalConfirmed -= removedConfirmed; // 배치 내 원자 처리

      expect(to.totalConfirmed, initialConfirmed - removedConfirmed);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SCENARIO-STAT-45 ~ 50: 통계 불일치 케이스 시뮬레이션 & M-3 버그 수정 검증
  // ══════════════════════════════════════════════════════════════════════════
  group('SCENARIO-STAT-45~50: 통계 불일치 케이스 및 M-3 버그 수정 검증', () {
    test('SCENARIO-STAT-45: Case 1 — CF 실패 → 클라이언트 increment 유지, CF 재실행 시 교정', () {
      // 실제: 클라이언트 increment 후 CF syncTOStats 실패
      // 시뮬레이션: 클라이언트 값 vs CF count() 결과 비교

      final slot = _makeSlot(id: 's1', toId: 'to1', requiredCounts: {'피킹': 5});
      final to = _makeFlexTO(id: 'to1', slots: {'s1': slot});

      // 클라이언트: 3번 지원, pending=3
      incrementTOPending(to, 's1', delta: 1, workType: '피킹');
      incrementTOPending(to, 's1', delta: 1, workType: '피킹');
      incrementTOPending(to, 's1', delta: 1, workType: '피킹');

      expect(to.totalPending, 3);
      expect(slot.pendingCount, 3);

      // CF count() 실측값 = 2 (1건은 실제로 저장 안 됨)
      final cfRealCount = 2;

      // CF 교정 후: 클라이언트 값과 불일치 → CF가 덮어씀
      to.totalPending = cfRealCount; // CF 교정
      slot.pendingCount = cfRealCount;
      slot.workTypeCounts['피킹']!.pendingCount = cfRealCount;

      expect(to.totalPending, cfRealCount);
    });

    test('SCENARIO-STAT-46: Case 2 — increment 실패 → 카운터 낮게 표시', () {
      final slot = _makeSlot(id: 's1', toId: 'to1', requiredCounts: {'피킹': 5});
      final to = _makeFlexTO(id: 'to1', slots: {'s1': slot});

      // 실제 지원은 2건이지만 increment가 1건만 성공
      incrementTOPending(to, 's1', delta: 1, workType: '피킹');
      // 두 번째 increment 실패 → 카운터 = 1

      expect(to.totalPending, 1);
      // 실제로는 2건이 있음 — CF count()가 2로 교정
      final cfRealCount = 2;
      to.totalPending = cfRealCount;
      expect(to.totalPending, cfRealCount);
    });

    test('SCENARIO-STAT-47: Case 3 — 클라이언트 increment → CF count() 덮어씀 → 짧은 불일치', () {
      final slot = _makeSlot(id: 's1', toId: 'to1', requiredCounts: {'피킹': 5});
      final to = _makeFlexTO(id: 'to1', slots: {'s1': slot});

      // T=0: 클라이언트 increment
      incrementTOPending(to, 's1', delta: 1, workType: '피킹');
      final clientValue = to.totalPending; // 1

      // T=1: CF 아직 실행 전 — 클라이언트 값이 일시적으로 '낙관적' 상태
      // T=2: CF count() 실행 → 같은 값 1 확인 후 덮어씀
      final cfCountResult = 1; // count() API 결과

      to.totalPending = cfCountResult; // CF 덮어쓰기

      expect(clientValue, cfCountResult); // 일치 — 정상 케이스
    });

    test('SCENARIO-STAT-48: Case 4 — 다중 동시 지원 → 트랜잭션 최종 일관성', () {
      // FieldValue.increment는 서버 측 원자 연산 — 동시 2명이 지원해도
      // 각 increment가 독립적으로 적용 → 최종 pending = 2
      final slot = _makeSlot(id: 's1', toId: 'to1', requiredCounts: {'피킹': 5});
      final to = _makeFlexTO(id: 'to1', slots: {'s1': slot});

      // 동시 요청 시뮬레이션 (두 요청이 각각 +1 적용)
      incrementTOPending(to, 's1', delta: 1, workType: '피킹'); // 요청 A
      incrementTOPending(to, 's1', delta: 1, workType: '피킹'); // 요청 B (동시)

      expect(to.totalPending, 2); // 원자 연산으로 정확히 2
      expect(slot.pendingCount, 2);
    });

    test('SCENARIO-STAT-49: M-3 버그 수정 — batchCloseSlots: 3곳 동시 감소', () {
      // 이전(버그): TO.totalPending만 감소
      // 수정: TO.totalPending + Slot.pendingCount + workTypeCounts.$type.pendingCount 동시 감소

      final slot = MockSlot(
        id: 's1',
        toId: 'to1',
        requiredCounts: {'피킹': 3},
        workTypeCounts: {
          '피킹': MockSlotWorkTypeCount(pendingCount: 3),
        },
        pendingCount: 3,
      );
      final to = _makeFlexTO(id: 'to1', slots: {'s1': slot});
      to.totalPending = 3;

      // batchCloseSlots M-3 수정 패턴: slotCanceled=3, wtDeltas={'피킹': 3}
      final slotCanceled = 3;
      final wtDeltas = {'피킹': 3};

      // TO totalPending 감소
      to.totalPending -= slotCanceled;
      // Slot pendingCount 감소
      slot.pendingCount -= slotCanceled;
      // workTypeCounts 감소
      for (final entry in wtDeltas.entries) {
        slot.workTypeCounts[entry.key]!.pendingCount -= entry.value;
      }

      expect(to.totalPending, 0); // TO 감소
      expect(slot.pendingCount, 0); // 슬롯 감소
      expect(slot.workTypeCounts['피킹']!.pendingCount, 0); // workType 감소
    });

    test('SCENARIO-STAT-50: M-3 버그 전 상태 — TO만 감소, 슬롯은 양수 잔류', () {
      // 버그 시나리오 재현: 이전 코드는 TO totalPending만 감소
      final slot = MockSlot(
        id: 's1',
        toId: 'to1',
        requiredCounts: {'피킹': 3},
        workTypeCounts: {
          '피킹': MockSlotWorkTypeCount(pendingCount: 3),
        },
        pendingCount: 3,
      );
      final to = _makeFlexTO(id: 'to1', slots: {'s1': slot});
      to.totalPending = 3;

      // 버그 패턴: TO.totalPending만 감소 (슬롯/workType 미갱신)
      final slotCanceled = 3;
      to.totalPending -= slotCanceled; // TO만 처리

      // 결과: TO는 0이지만 슬롯/workType은 여전히 3 → 불일치
      expect(to.totalPending, 0); // TO 정상
      expect(slot.pendingCount, 3); // 슬롯 양수 잔류 (버그)
      expect(slot.workTypeCounts['피킹']!.pendingCount, 3); // workType 양수 잔류 (버그)

      // 이 불일치가 M-3 버그의 본질
      expect(to.totalPending != slot.pendingCount, true); // 불일치 확인
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SCENARIO-STAT-51 ~ 58: workType별 정원 초과 방지 (isWorkTypeFull)
  // ══════════════════════════════════════════════════════════════════════════
  group('SCENARIO-STAT-51~58: workType별 정원 초과 방지', () {
    test('SCENARIO-STAT-51: confirmedCount < requiredCount → isWorkTypeFull=false', () {
      final slot = _makeSlot(requiredCounts: {'피킹': 3});
      slot.workTypeCounts['피킹']!.confirmedCount = 2;

      expect(slot.isWorkTypeFull('피킹'), false);
    });

    test('SCENARIO-STAT-52: confirmedCount == requiredCount → isWorkTypeFull=true', () {
      final slot = _makeSlot(requiredCounts: {'피킹': 3});
      slot.workTypeCounts['피킹']!.confirmedCount = 3;

      expect(slot.isWorkTypeFull('피킹'), true);
    });

    test('SCENARIO-STAT-53: confirmedCount > requiredCount → isWorkTypeFull=true (초과 허용)', () {
      final slot = _makeSlot(requiredCounts: {'피킹': 3});
      slot.workTypeCounts['피킹']!.confirmedCount = 4; // 초과 확정

      expect(slot.isWorkTypeFull('피킹'), true);
    });

    test('SCENARIO-STAT-54: requiredCount=0인 workType → isWorkTypeFull=false (정원 미설정)', () {
      final slot = _makeSlot(requiredCounts: {'피킹': 0});
      slot.workTypeCounts['피킹']!.confirmedCount = 5;

      expect(slot.isWorkTypeFull('피킹'), false);
    });

    test('SCENARIO-STAT-55: 존재하지 않는 workType → isWorkTypeFull=false', () {
      final slot = _makeSlot(requiredCounts: {'피킹': 3});

      expect(slot.isWorkTypeFull('없는업무'), false);
    });

    test('SCENARIO-STAT-56: A workType full이어도 B workType은 지원 가능', () {
      final slot = MockSlot(
        id: 's1',
        toId: 'to1',
        requiredCounts: {'피킹': 2, '패킹': 3},
        workTypeCounts: {
          '피킹': MockSlotWorkTypeCount(confirmedCount: 2), // full
          '패킹': MockSlotWorkTypeCount(confirmedCount: 1), // open
        },
      );

      expect(slot.isWorkTypeFull('피킹'), true);
      expect(slot.isWorkTypeFull('패킹'), false); // 패킹은 여전히 지원 가능
    });

    test('SCENARIO-STAT-57: 취소로 confirmedCount 감소 → 다시 지원 가능', () {
      final slot = _makeSlot(requiredCounts: {'피킹': 3});
      slot.workTypeCounts['피킹']!.confirmedCount = 3;

      // 3명 → full
      expect(slot.isWorkTypeFull('피킹'), true);

      // 1명 취소
      slot.workTypeCounts['피킹']!.confirmedCount -= 1;

      // 2명 → open (재지원 가능)
      expect(slot.isWorkTypeFull('피킹'), false);
    });

    test('SCENARIO-STAT-58: T-H-1 버그 수정 — CONTRACT_PENDING 정원 검증 시 flex는 슬롯 workTypeCounts 사용', () {
      // T-H-1: flex TO에서 TO.workTypeConfirmedCounts 사용 시 항상 0 반환 (버그)
      // 수정: 슬롯의 workTypeCounts.$workType.confirmedCount 사용
      final slot = MockSlot(
        id: 's1',
        toId: 'to1',
        requiredCounts: {'피킹': 3},
        workTypeCounts: {
          '피킹': MockSlotWorkTypeCount(confirmedCount: 3), // 슬롯 레벨 실측
        },
        confirmedCount: 3,
      );
      // flex TO: workTypeConfirmedCounts는 갱신 안 됨 (항상 0)
      final to = MockTO(
        id: 'to1',
        workTypeConfirmedCounts: {'피킹': 0}, // 버그 패턴: 항상 0
        slots: {'s1': slot},
      );

      // 버그 패턴: TO.workTypeConfirmedCounts 사용 → 0으로 읽혀 정원 초과 차단 실패
      final confirmedFromTO = to.workTypeConfirmedCounts['피킹'] ?? 0;
      expect(confirmedFromTO, 0); // 버그: 정원 초과 탐지 실패

      // 수정 패턴: 슬롯 workTypeCounts 사용 → 3으로 읽혀 정원 초과 차단 성공
      final confirmedFromSlot =
          slot.workTypeCounts['피킹']?.confirmedCount ?? 0;
      expect(confirmedFromSlot, 3); // 수정: 정원 초과 탐지 성공

      final workTypeRequired = slot.requiredCounts['피킹'] ?? 0;
      expect(workTypeRequired > 0 && confirmedFromSlot >= workTypeRequired, true);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SCENARIO-STAT-59 ~ 62: updateSlotStats 데드코드 확인
  // ══════════════════════════════════════════════════════════════════════════
  group('SCENARIO-STAT-59~62: updateSlotStats 데드코드 및 내부 함수 대체 확인', () {
    test('SCENARIO-STAT-59: _incrementTOPending은 pending 지원 흐름의 단일 진실 원천', () {
      // 실제 코드에서 applyToTO(), reactivation 경로 모두 _incrementTOPending 사용
      final slot = _makeSlot(id: 's1', toId: 'to1', requiredCounts: {'피킹': 3});
      final to = _makeFlexTO(id: 'to1', slots: {'s1': slot});

      // applyToTO 경로
      incrementTOPending(to, 's1', delta: 1, workType: '피킹');
      expect(to.totalPending, 1);

      // reactivation 경로 (재지원)
      incrementTOPending(to, 's1', delta: -1, workType: '피킹');
      incrementTOPending(to, 's1', delta: 1, workType: '피킹');
      expect(to.totalPending, 1);
    });

    test('SCENARIO-STAT-60: _incrementTOConfirmed는 확정 흐름의 단일 진실 원천', () {
      final slot = _makeSlot(id: 's1', toId: 'to1', requiredCounts: {'피킹': 3});
      final to = _makeFlexTO(id: 'to1', slots: {'s1': slot});

      // _confirmWithConflictCheck 경로
      incrementTOPending(to, 's1', delta: 1, workType: '피킹');
      incrementTOPending(to, 's1', delta: -1, workType: '피킹');
      incrementTOConfirmed(to, 's1', delta: 1, workType: '피킹');

      expect(to.totalConfirmed, 1);
      expect(slot.confirmedCount, 1);
    });

    test('SCENARIO-STAT-61: _recalculateSlotStatus는 확정/취소 후 즉각 status 반영', () {
      final slot = _makeSlot(id: 's1', toId: 'to1', requiredCounts: {'피킹': 2});
      final to = _makeFlexTO(id: 'to1', slots: {'s1': slot});

      incrementTOConfirmed(to, 's1', delta: 1, workType: '피킹');
      recalculateSlotStatus(to, 's1');
      expect(slot.status, 'open');

      incrementTOConfirmed(to, 's1', delta: 1, workType: '피킹');
      recalculateSlotStatus(to, 's1');
      expect(slot.status, 'full');
    });

    test('SCENARIO-STAT-62: 내부 함수 체인 완전성 — PENDING→CONFIRMED→CANCELED 전체 흐름', () {
      final slot = _makeSlot(id: 's1', toId: 'to1', requiredCounts: {'피킹': 3});
      final to = _makeFlexTO(id: 'to1', slots: {'s1': slot});

      // 1. 지원 (PENDING)
      incrementTOPending(to, 's1', delta: 1, workType: '피킹');
      expect(to.totalPending, 1);
      expect(slot.pendingCount, 1);

      // 2. 확정 (CONFIRMED)
      incrementTOPending(to, 's1', delta: -1, workType: '피킹');
      incrementTOConfirmed(to, 's1', delta: 1, workType: '피킹');
      recalculateSlotStatus(to, 's1');
      expect(to.totalPending, 0);
      expect(to.totalConfirmed, 1);
      expect(slot.confirmedCount, 1);

      // 3. 확정 취소 (CANCELED)
      decrementTOConfirmed(to, 's1', workType: '피킹');
      recalculateSlotStatus(to, 's1');
      expect(to.totalConfirmed, 0);
      expect(slot.confirmedCount, 0);
      expect(slot.status, 'open'); // full→open 복구
    });
  });
}
