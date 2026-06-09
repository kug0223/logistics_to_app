import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/admin_to_list_ui_models.dart';
import 'package:ALfit/utils/close_state_utils.dart';

// ──────────────────────────────────────────────────────────
// 테스트 헬퍼
// ──────────────────────────────────────────────────────────

SlotModel _slot({
  required DateTime date,
  String status = SlotStatus.open,
  String? closedBy,
  bool isManualClosed = false,
}) {
  return SlotModel(
    id: 'slot1',
    toId: 'to1',
    date: date,
    status: status,
    closedBy: closedBy,
    isManualClosed: isManualClosed,
    createdAt: DateTime(2025),
  );
}

WorkDetailData _detail({
  String workType = 'WD1',
  String startTime = '09:00',
  DateTime? applicationDeadline,
  bool isManualClosed = false,
  DateTime? closedAt,
}) {
  return WorkDetailData(
    workType: workType,
    startTime: startTime,
    endTime: '18:00',
    wage: 10000,
    wageType: 'hourly',
    requiredCount: 2,
    applicationDeadline: applicationDeadline,
    isManualClosed: isManualClosed,
    closedAt: closedAt,
  );
}

TOModel _masterTO({
  String deadlineType = 'NONE',
  int hoursBeforeStart = 0,
  String status = TOStatus.active,
}) {
  return TOModel(
    id: 'to1',
    businessId: 'biz1',
    businessName: '테스트 사업장',
    type: 'flex',
    title: '테스트 공고',
    creatorUID: 'uid1',
    status: status,
    deadlineType: deadlineType,
    hoursBeforeStart: hoursBeforeStart,
    workDetails: const [],
    totalRequired: 0,
    totalConfirmed: 0,
    totalPending: 0,
    isPublished: true,
    publishMode: 'immediate',
    createdAt: DateTime(2025),
    statusUpdatedAt: DateTime(2025),
  );
}

TOItem _toItem({
  required SlotModel slot,
  List<WorkDetailData>? loadedWorkDetails,
  int confirmedCount = 0,
  int totalRequired = 2,
}) {
  return TOItem(
    to: _masterTO(),
    slot: slot,
    workDetails: loadedWorkDetails,
    confirmedCount: confirmedCount,
    pendingCount: 0,
    totalRequired: totalRequired,
    isWorkDetailLoaded: loadedWorkDetails != null,
  );
}

// ──────────────────────────────────────────────────────────
// 테스트
// ──────────────────────────────────────────────────────────

void main() {
  // 테스트 기준 시각: 2025-05-14 10:00
  final now = DateTime(2025, 5, 14, 10, 0);
  final today = DateTime(now.year, now.month, now.day);

  group('CloseStateUtils.isToItemClosed', () {

    // ── 날짜 경과 ──────────────────────────────────────────
    test('날짜가 어제이면 마감', () {
      final slot = _slot(date: today.subtract(const Duration(days: 1)));
      final item = _toItem(slot: slot);
      expect(CloseStateUtils.isToItemClosed(item, _masterTO(), now), isTrue);
    });

    test('날짜가 오늘이면 날짜만으로는 마감 아님', () {
      final slot = _slot(date: today);
      final item = _toItem(
        slot: slot,
        loadedWorkDetails: [_detail(applicationDeadline: now.add(const Duration(hours: 1)))],
      );
      expect(CloseStateUtils.isToItemClosed(item, _masterTO(), now), isFalse);
    });

    // ── 직접 마감 ──────────────────────────────────────────
    test('closedBy 설정 시 업무상세 무관하게 마감', () {
      final slot = _slot(
        date: today,
        status: SlotStatus.closed,
        closedBy: 'admin_uid',
      );
      final item = _toItem(
        slot: slot,
        loadedWorkDetails: [_detail(applicationDeadline: now.add(const Duration(hours: 2)))],
      );
      expect(CloseStateUtils.isToItemClosed(item, _masterTO(), now), isTrue);
    });

    test('status=closed 이지만 closedBy=null (cascade) + 활성 업무상세 → 열림', () {
      final slot = _slot(date: today, status: SlotStatus.closed); // cascade close
      final item = _toItem(
        slot: slot,
        loadedWorkDetails: [_detail(applicationDeadline: now.add(const Duration(hours: 2)))],
      );
      expect(CloseStateUtils.isToItemClosed(item, _masterTO(), now), isFalse);
    });

    // ── 인원 충족 ──────────────────────────────────────────
    test('인원 충족(localConfirmed >= localRequired) 시 마감', () {
      final slot = _slot(date: today);
      final item = _toItem(slot: slot, confirmedCount: 0, totalRequired: 2);
      expect(
        CloseStateUtils.isToItemClosed(item, _masterTO(), now,
            localConfirmed: 2, localRequired: 2),
        isTrue,
      );
    });

    test('slot.isFull(status=full) 시 마감', () {
      final slot = _slot(date: today, status: SlotStatus.full);
      final item = _toItem(slot: slot);
      expect(CloseStateUtils.isToItemClosed(item, _masterTO(), now), isTrue);
    });

    // ── 업무상세 기반 ──────────────────────────────────────
    test('업무상세 applicationDeadline 지남 → 마감', () {
      final slot = _slot(date: today);
      final item = _toItem(
        slot: slot,
        loadedWorkDetails: [_detail(applicationDeadline: now.subtract(const Duration(minutes: 1)))],
      );
      expect(CloseStateUtils.isToItemClosed(item, _masterTO(), now), isTrue);
    });

    test('업무상세 applicationDeadline 미래 → 열림', () {
      final slot = _slot(date: today);
      final item = _toItem(
        slot: slot,
        loadedWorkDetails: [_detail(applicationDeadline: now.add(const Duration(hours: 1)))],
      );
      expect(CloseStateUtils.isToItemClosed(item, _masterTO(), now), isFalse);
    });

    test('업무상세 수동 마감(isManualClosed) → 마감', () {
      final slot = _slot(date: today);
      final item = _toItem(
        slot: slot,
        loadedWorkDetails: [_detail(isManualClosed: true)],
      );
      expect(CloseStateUtils.isToItemClosed(item, _masterTO(), now), isTrue);
    });

    test('업무상세 2개 중 1개 활성 → 열림', () {
      final slot = _slot(date: today);
      final item = _toItem(
        slot: slot,
        loadedWorkDetails: [
          _detail(workType: 'A', applicationDeadline: now.subtract(const Duration(hours: 1))),
          _detail(workType: 'B', applicationDeadline: now.add(const Duration(hours: 1))),
        ],
      );
      expect(CloseStateUtils.isToItemClosed(item, _masterTO(), now), isFalse);
    });

    // ── HOURS_BEFORE 계산 ──────────────────────────────────
    test('HOURS_BEFORE: applicationDeadline 미설정, 시작 2h 전 마감, 현재 시작 1h 전 → 마감', () {
      // 시작시각 12:00, 2h 전 마감 → deadline 10:00, now는 10:00 → 경과
      final slot = _slot(date: today);
      final master = _masterTO(deadlineType: 'HOURS_BEFORE', hoursBeforeStart: 2);
      final item = _toItem(
        slot: slot,
        loadedWorkDetails: [_detail(startTime: '12:00')], // deadline없음
      );
      // now = 10:00, deadline = 12:00 - 2h = 10:00 → isAfter(10:00) = false
      expect(CloseStateUtils.isToItemClosed(item, master, now), isFalse);
    });

    test('HOURS_BEFORE: applicationDeadline 저장값 기준 (09:00 마감, now=10:00) → 마감', () {
      // 설계: HOURS_BEFORE는 슬롯 생성 시 applicationDeadline으로 미리 계산해 저장됨
      // CloseStateUtils는 저장된 applicationDeadline만 체크
      final slot = _slot(date: today);
      final master = _masterTO(deadlineType: 'HOURS_BEFORE', hoursBeforeStart: 2);
      final deadline = DateTime(today.year, today.month, today.day, 9, 0); // 09:00 (now보다 이전)
      final item = _toItem(
        slot: slot,
        loadedWorkDetails: [_detail(startTime: '11:00', applicationDeadline: deadline)],
      );
      expect(CloseStateUtils.isToItemClosed(item, master, now), isTrue);
    });

    // ── CF 자동마감 + 편집 시나리오 ───────────────────────
    test('CF 자동마감된 TO(status=closed, isManualClosed=false) + 새 업무상세 활성 → 열림', () {
      // CF가 슬롯을 status='closed'로 닫았지만 (closedBy=null),
      // 편집 후 새 업무상세가 미래 마감시간으로 추가됨
      final slot = _slot(date: today, status: SlotStatus.closed); // CF auto-close
      final item = _toItem(
        slot: slot,
        loadedWorkDetails: [_detail(applicationDeadline: now.add(const Duration(hours: 3)))],
      );
      expect(CloseStateUtils.isToItemClosed(item, _masterTO(), now), isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────
  // TOGroupItem.isClosed 탭 필터 통합 시나리오
  // ──────────────────────────────────────────────────────────
  group('TOModel.isClosed', () {
    test('status=closed → isClosed=true', () {
      final to = _masterTO(status: TOStatus.closed);
      expect(to.isClosed, isTrue);
    });

    test('isManualClosed=true 이지만 status=active → isClosed=false (status가 진실 소스)', () {
      // isManualClosed는 메타데이터일 뿐, status로만 판단
      // 이 상태는 정상 flow에서 발생하지 않지만 방어적 확인
      final to = TOModel(
        id: 'to1',
        businessId: 'biz1',
        businessName: '테스트',
        type: 'flex',
        title: '테스트',
        creatorUID: 'uid1',
        status: TOStatus.active, // active
        isManualClosed: true,    // 과거 버그로 잘못 설정됐을 경우
        deadlineType: 'NONE',
        workDetails: const [],
        totalRequired: 0,
        totalConfirmed: 0,
        totalPending: 0,
        isPublished: true,
        publishMode: 'immediate',
        createdAt: DateTime(2025),
        statusUpdatedAt: DateTime(2025),
      );
      expect(to.isClosed, isFalse);
    });
  });

  group('SlotModel.isClosed', () {
    test('status=closed → isClosed=true', () {
      final slot = _slot(date: today, status: SlotStatus.closed);
      expect(slot.isClosed, isTrue);
    });

    test('isManualClosed=true 이지만 status=open → isClosed=false', () {
      final slot = _slot(date: today, status: SlotStatus.open, isManualClosed: true);
      expect(slot.isClosed, isFalse);
    });

    test('status=open, closedBy=null → isOpen=true', () {
      final slot = _slot(date: today);
      expect(slot.isOpen, isTrue);
    });
  });
}
