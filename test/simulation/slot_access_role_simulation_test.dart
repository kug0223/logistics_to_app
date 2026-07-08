// test/simulation/slot_access_role_simulation_test.dart
//
// SlotModel 상태/마감 로직과 역할별 TO 접근 권한 시나리오 시뮬레이션 테스트
//
// 검증 범위:
//   1.  SlotModel.isEffectivelyClosed — isClosed / isFull / isDatePast / workDetails 분기
//   2.  WorkDetailData.isTimeExpired — applicationDeadline 유무
//   3.  SlotModel.isWorkTypeFull(workType) — workTypeCounts 기반 정원 충족 여부
//   4.  visibleFrom 예약 공개 — null/미래/과거 비교
//   5.  applicationDeadline 계산 — HOURS_BEFORE / FIXED_TIME 타입
//   6.  역할별 탭 접근 권한 (BUSINESS_ADMIN / SUB_ADMIN / USER)
//   7.  TO 삭제 권한 (canDelete) — BUSINESS_ADMIN/SUPER_ADMIN vs SUB_ADMIN/USER
//   8.  effectiveBusinessId 패턴 — 역할별 반환값
//   9.  can() 함수 — 역할·permissions 분기
//  10.  isAdminOf 보안 규칙 null 방어 시뮬레이션
//  11.  whereIn 복합쿼리 PERMISSION_DENIED 방어 로직
//  12.  USER TO 목록 조회 제한 (limit / isPublished 조건)
//
// Firebase 의존성 없음 — 순수 Dart 로직만 검증
//
// 실행: flutter test test/simulation/slot_access_role_simulation_test.dart

import 'package:flutter_test/flutter_test.dart';

// ══════════════════════════════════════════════════════════════════════════════
// 1. 경량 모델 정의 (Firebase 미사용)
// ══════════════════════════════════════════════════════════════════════════════

/// SlotStatus 상수 (실제 SlotStatus 클래스 재현)
abstract class _SlotStatus {
  static const String open   = 'open';
  static const String full   = 'full';
  static const String closed = 'closed';
}

/// workDetail 경량 모델 (WorkDetailData 핵심 필드 재현)
class _WorkDetail {
  final String workType;
  final int requiredCount;
  final bool isManualClosed;
  final DateTime? applicationDeadline;

  const _WorkDetail({
    required this.workType,
    this.requiredCount = 3,
    this.isManualClosed = false,
    this.applicationDeadline,
  });

  /// WorkDetailData.isClosed 재현
  bool get isClosed => isManualClosed;

  /// WorkDetailData.isTimeExpired 재현
  bool get isTimeExpired =>
      applicationDeadline != null && DateTime.now().isAfter(applicationDeadline!);
}

/// 슬롯 내 업무유형별 지원 현황
class _WorkTypeCount {
  final int confirmedCount;
  final int pendingCount;
  const _WorkTypeCount({this.confirmedCount = 0, this.pendingCount = 0});
}

/// SlotModel 경량 재현
class _Slot {
  final String id;
  final DateTime date;
  final String status;
  final bool isManualClosed;
  final DateTime? applicationDeadline;
  final DateTime? visibleFrom;
  final List<_WorkDetail> workDetails;
  final Map<String, _WorkTypeCount> workTypeCounts;

  const _Slot({
    required this.id,
    required this.date,
    this.status = _SlotStatus.open,
    this.isManualClosed = false,
    this.applicationDeadline,
    this.visibleFrom,
    this.workDetails = const [],
    this.workTypeCounts = const {},
  });

  bool get isOpen   => status == _SlotStatus.open;
  bool get isFull   => status == _SlotStatus.full;
  bool get isClosed => status == _SlotStatus.closed;

  /// SlotModel.isDatePast 재현
  bool get isDatePast {
    final today = DateTime.now();
    return DateTime(date.year, date.month, date.day)
        .isBefore(DateTime(today.year, today.month, today.day));
  }

  /// SlotModel.isDeadlinePassed 재현 (workDetails 없는 구 슬롯 폴백)
  bool get isDeadlinePassed {
    if (applicationDeadline == null) return false;
    return DateTime.now().isAfter(applicationDeadline!);
  }

  /// SlotModel.isEffectivelyClosed 재현
  bool get isEffectivelyClosed =>
      isClosed ||
      isFull ||
      isDatePast ||
      (workDetails.isNotEmpty
          ? workDetails.every((wd) => wd.isClosed || wd.isTimeExpired)
          : isDeadlinePassed);

  /// SlotModel.isWorkTypeFull(workType) 재현
  bool isWorkTypeFull(String workType) {
    final detail = workDetails.where((d) => d.workType == workType).firstOrNull;
    if (detail == null || detail.requiredCount == 0) return false;
    final count = workTypeCounts[workType] ?? const _WorkTypeCount();
    return count.confirmedCount >= detail.requiredCount;
  }

  /// visibleFrom 기준 공개 여부 (null → 즉시 공개)
  bool get isPublishedByVisibleFrom {
    if (visibleFrom == null) return true;
    return !visibleFrom!.isAfter(DateTime.now());
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 2. 역할 / 권한 모델 (UserProvider 로직 재현)
// ══════════════════════════════════════════════════════════════════════════════

enum _UserRole { SUPER_ADMIN, BUSINESS_ADMIN, USER }

class _MemberPermissions {
  final bool canManageTo;
  final bool canManageWorkers;
  final bool canManageWage;
  final bool canManageContract;

  const _MemberPermissions({
    this.canManageTo       = false,
    this.canManageWorkers  = false,
    this.canManageWage     = false,
    this.canManageContract = false,
  });

  static const _MemberPermissions none = _MemberPermissions();
  static const _MemberPermissions all  = _MemberPermissions(
    canManageTo:       true,
    canManageWorkers:  true,
    canManageWage:     true,
    canManageContract: true,
  );
}

class _User {
  final String uid;
  final _UserRole role;
  final String? businessId;   // BUSINESS_ADMIN 자신의 사업장
  final String? subAdminOf;   // SUB_ADMIN 소속 사업장

  const _User({
    required this.uid,
    required this.role,
    this.businessId,
    this.subAdminOf,
  });

  bool get isSuperAdmin    => role == _UserRole.SUPER_ADMIN;
  bool get isBusinessAdmin => role == _UserRole.BUSINESS_ADMIN;
  bool get isUser          => role == _UserRole.USER;
  bool get isSubAdmin      => role == _UserRole.USER && subAdminOf != null;
}

/// UserProvider의 effectiveBusinessId / can() 재현
class _UserContext {
  final _User user;
  final _MemberPermissions? memberPermissions; // 로드 전 null 가능

  const _UserContext({required this.user, this.memberPermissions});

  /// effectiveBusinessId 재현
  String? get effectiveBusinessId {
    if (user.isBusinessAdmin) return user.businessId;
    if (user.isSubAdmin) return user.subAdminOf;
    return null;
  }

  /// can() 재현
  bool can(bool Function(_MemberPermissions p) check) {
    if (user.isBusinessAdmin) return true;
    if (memberPermissions != null) return check(memberPermissions!);
    return false;
  }

  /// TO 삭제 권한 (admin_to_group_card canDelete 재현)
  bool get canDelete => user.isBusinessAdmin || user.isSuperAdmin;

  /// 하위 관리자 여부
  bool get isSubAdmin => user.isSubAdmin;
}

// ══════════════════════════════════════════════════════════════════════════════
// 3. Firestore 보안 규칙 시뮬레이션
// ══════════════════════════════════════════════════════════════════════════════

/// Firestore business 도큐먼트 경량 재현
class _Business {
  final String id;
  final String ownerId;
  final List<String> adminIds;

  const _Business({
    required this.id,
    required this.ownerId,
    this.adminIds = const [],
  });
}

/// isAdminOf(businessId) 보안 규칙 재현
/// businessId == null || businessId == '' → early return false
bool _isAdminOf({
  required String? businessId,
  required String? requestUid,
  required List<_Business> businesses,
}) {
  if (businessId == null || businessId.isEmpty) return false;
  if (requestUid == null) return false;
  final biz = businesses.where((b) => b.id == businessId).firstOrNull;
  if (biz == null) return false;
  return biz.ownerId == requestUid || biz.adminIds.contains(requestUid);
}

/// whereIn 쿼리에서 filters.businessId 반환값 시뮬레이션
/// Firebase 버그: whereIn 복합쿼리에서 request.query.filters.businessId == null
String? _simulateWhereInFilterBusinessId({required bool isWhereInQuery}) {
  // whereIn 쿼리: Firebase가 단일 필터 추출 불가 → null 반환
  if (isWhereInQuery) return null;
  return 'biz-001';
}

/// USER TO 목록 조회 검증 (Firestore 규칙 재현)
({bool allowed, String? reason}) _validateUserToQuery({
  required int limit,
  required bool hasIsPublishedFilter,
  required bool isPublishedValue,
}) {
  if (limit > 50) {
    return (allowed: false, reason: 'limit > 50: 덤프 방지 거부');
  }
  if (!hasIsPublishedFilter) {
    return (allowed: false, reason: 'isPublished 필터 누락');
  }
  if (!isPublishedValue) {
    return (allowed: false, reason: 'isPublished=false 조회 불가');
  }
  return (allowed: true, reason: null);
}

// ══════════════════════════════════════════════════════════════════════════════
// 4. applicationDeadline 계산 헬퍼 (updateSlotsDeadlines 재현)
// ══════════════════════════════════════════════════════════════════════════════

enum _DeadlineType { HOURS_BEFORE, FIXED_TIME }

DateTime? _calcDeadline({
  required _DeadlineType type,
  required DateTime? workStart,
  int? hoursBeforeStart,
  DateTime? fixedDeadline,
}) {
  switch (type) {
    case _DeadlineType.HOURS_BEFORE:
      if (workStart == null || hoursBeforeStart == null) return null;
      return workStart.subtract(Duration(hours: hoursBeforeStart));
    case _DeadlineType.FIXED_TIME:
      return fixedDeadline;
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 5. 홈 화면 탭 접근 검사 (business_admin_home_screen 재현)
// ══════════════════════════════════════════════════════════════════════════════

/// 탭 가시성 계산 (business_admin_home_screen 탭 표시 조건 재현)
class _TabVisibility {
  final bool showToRegister;     // 공고 등록 탭
  final bool showToManage;       // 공고 관리 탭 (canManageTo OR canManageWorkers)
  final bool showWage;           // 급여 관리 탭
  final bool showContract;       // 계약서 관리 탭
  final bool showStats;          // 통계 탭

  const _TabVisibility({
    required this.showToRegister,
    required this.showToManage,
    required this.showWage,
    required this.showContract,
    required this.showStats,
  });

  factory _TabVisibility.fromContext(_UserContext ctx) {
    final isSubAdmin = ctx.isSubAdmin;
    return _TabVisibility(
      showToRegister: !isSubAdmin || ctx.can((p) => p.canManageTo),
      showToManage:   !isSubAdmin ||
                      ctx.can((p) => p.canManageTo) ||
                      ctx.can((p) => p.canManageWorkers),
      showWage:       !isSubAdmin || ctx.can((p) => p.canManageWage),
      showContract:   !isSubAdmin || ctx.can((p) => p.canManageContract),
      showStats:      !isSubAdmin || ctx.can((p) => p.canManageWage),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 테스트 데이터 팩토리
// ══════════════════════════════════════════════════════════════════════════════

_Slot _makeSlot({
  String status = _SlotStatus.open,
  DateTime? date,
  bool isManualClosed = false,
  DateTime? applicationDeadline,
  DateTime? visibleFrom,
  List<_WorkDetail> workDetails = const [],
  Map<String, _WorkTypeCount> workTypeCounts = const {},
}) =>
    _Slot(
      id: 'slot-001',
      date: date ?? DateTime(2099, 12, 31),
      status: status,
      isManualClosed: isManualClosed,
      applicationDeadline: applicationDeadline,
      visibleFrom: visibleFrom,
      workDetails: workDetails,
      workTypeCounts: workTypeCounts,
    );

_WorkDetail _makeDetail({
  String workType = '피킹',
  int requiredCount = 3,
  bool isManualClosed = false,
  DateTime? applicationDeadline,
}) =>
    _WorkDetail(
      workType: workType,
      requiredCount: requiredCount,
      isManualClosed: isManualClosed,
      applicationDeadline: applicationDeadline,
    );

_UserContext _businessAdminCtx({String bizId = 'biz-001'}) => _UserContext(
      user: _User(uid: 'uid-admin', role: _UserRole.BUSINESS_ADMIN, businessId: bizId),
      memberPermissions: null,
    );

_UserContext _superAdminCtx() => _UserContext(
      user: _User(uid: 'uid-super', role: _UserRole.SUPER_ADMIN),
      memberPermissions: null,
    );

_UserContext _subAdminCtx({
  _MemberPermissions? permissions,
  bool loaded = true,
}) =>
    _UserContext(
      user: _User(uid: 'uid-sub', role: _UserRole.USER, subAdminOf: 'biz-001'),
      memberPermissions: loaded ? (permissions ?? _MemberPermissions.none) : null,
    );

_UserContext _userCtx() => _UserContext(
      user: _User(uid: 'uid-user', role: _UserRole.USER),
      memberPermissions: null,
    );

// ══════════════════════════════════════════════════════════════════════════════
// MAIN
// ══════════════════════════════════════════════════════════════════════════════

void main() {
  // ────────────────────────────────────────────────────────────────────────────
  // GROUP A: SlotModel.isEffectivelyClosed
  // ────────────────────────────────────────────────────────────────────────────
  group('SCENARIO-SLT-A: isEffectivelyClosed', () {
    test('SCENARIO-SLT-A01: status=closed → isEffectivelyClosed=true', () {
      final slot = _makeSlot(status: _SlotStatus.closed);
      expect(slot.isEffectivelyClosed, isTrue);
    });

    test('SCENARIO-SLT-A02: status=full → isEffectivelyClosed=true', () {
      final slot = _makeSlot(status: _SlotStatus.full);
      expect(slot.isEffectivelyClosed, isTrue);
    });

    test('SCENARIO-SLT-A03: 날짜 경과(isDatePast=true) → isEffectivelyClosed=true', () {
      final slot = _makeSlot(date: DateTime(2020, 1, 1));
      expect(slot.isDatePast,          isTrue);
      expect(slot.isEffectivelyClosed, isTrue);
    });

    test('SCENARIO-SLT-A04: 미래 날짜 + open + workDetails 없음 + deadline 없음 → false', () {
      final slot = _makeSlot(
        status: _SlotStatus.open,
        date: DateTime(2099, 12, 31),
        workDetails: [],
        applicationDeadline: null,
      );
      expect(slot.isEffectivelyClosed, isFalse);
    });

    test('SCENARIO-SLT-A05: workDetails 있고 전체 isManualClosed → true', () {
      final slot = _makeSlot(
        date: DateTime(2099, 12, 31),
        workDetails: [
          _makeDetail(isManualClosed: true),
          _makeDetail(workType: '패킹', isManualClosed: true),
        ],
      );
      expect(slot.isEffectivelyClosed, isTrue);
    });

    test('SCENARIO-SLT-A06: workDetails 있고 일부만 isManualClosed → false', () {
      final slot = _makeSlot(
        date: DateTime(2099, 12, 31),
        workDetails: [
          _makeDetail(isManualClosed: true),
          _makeDetail(workType: '패킹', isManualClosed: false),
        ],
      );
      expect(slot.isEffectivelyClosed, isFalse);
    });

    test('SCENARIO-SLT-A07: workDetails 있고 전체 isTimeExpired → true', () {
      final past = DateTime(2020, 1, 1);
      final slot = _makeSlot(
        date: DateTime(2099, 12, 31),
        workDetails: [
          _makeDetail(applicationDeadline: past),
          _makeDetail(workType: '패킹', applicationDeadline: past),
        ],
      );
      expect(slot.isEffectivelyClosed, isTrue);
    });

    test('SCENARIO-SLT-A08: workDetails 있고 일부만 isTimeExpired → false', () {
      final past   = DateTime(2020, 1, 1);
      final future = DateTime(2099, 12, 31);
      final slot = _makeSlot(
        date: future,
        workDetails: [
          _makeDetail(applicationDeadline: past),
          _makeDetail(workType: '패킹', applicationDeadline: future),
        ],
      );
      expect(slot.isEffectivelyClosed, isFalse);
    });

    test('SCENARIO-SLT-A09: workDetails 있고 혼합(isClosed+isTimeExpired) → true', () {
      final past = DateTime(2020, 1, 1);
      final slot = _makeSlot(
        date: DateTime(2099, 12, 31),
        workDetails: [
          _makeDetail(isManualClosed: true),
          _makeDetail(workType: '패킹', applicationDeadline: past),
        ],
      );
      expect(slot.isEffectivelyClosed, isTrue);
    });

    test('SCENARIO-SLT-A10: workDetails 없고 applicationDeadline 과거 → isDeadlinePassed → true', () {
      final slot = _makeSlot(
        date: DateTime(2099, 12, 31),
        workDetails: [],
        applicationDeadline: DateTime(2020, 1, 1),
      );
      expect(slot.isDeadlinePassed,    isTrue);
      expect(slot.isEffectivelyClosed, isTrue);
    });

    test('SCENARIO-SLT-A11: workDetails 없고 applicationDeadline 없음 → false', () {
      final slot = _makeSlot(
        date: DateTime(2099, 12, 31),
        workDetails: [],
        applicationDeadline: null,
      );
      expect(slot.isDeadlinePassed,    isFalse);
      expect(slot.isEffectivelyClosed, isFalse);
    });

    test('SCENARIO-SLT-A12: workDetails 없고 applicationDeadline 미래 → false', () {
      final slot = _makeSlot(
        date: DateTime(2099, 12, 31),
        workDetails: [],
        applicationDeadline: DateTime(2099, 11, 30),
      );
      expect(slot.isDeadlinePassed,    isFalse);
      expect(slot.isEffectivelyClosed, isFalse);
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // GROUP B: WorkDetailData.isTimeExpired
  // ────────────────────────────────────────────────────────────────────────────
  group('SCENARIO-SLT-B: WorkDetail.isTimeExpired', () {
    test('SCENARIO-SLT-B01: applicationDeadline == null → isTimeExpired=false', () {
      final d = _makeDetail(applicationDeadline: null);
      expect(d.isTimeExpired, isFalse);
    });

    test('SCENARIO-SLT-B02: applicationDeadline 과거 → isTimeExpired=true', () {
      final d = _makeDetail(applicationDeadline: DateTime(2020, 6, 1, 9, 0));
      expect(d.isTimeExpired, isTrue);
    });

    test('SCENARIO-SLT-B03: applicationDeadline 미래 → isTimeExpired=false', () {
      final d = _makeDetail(applicationDeadline: DateTime(2099, 12, 31, 23, 59));
      expect(d.isTimeExpired, isFalse);
    });

    test('SCENARIO-SLT-B04: isManualClosed=true → isClosed=true (isTimeExpired 무관)', () {
      final d = _makeDetail(isManualClosed: true, applicationDeadline: null);
      expect(d.isClosed,      isTrue);
      expect(d.isTimeExpired, isFalse);
    });

    test('SCENARIO-SLT-B05: isClosed=false + isTimeExpired=false → 모두 false (정상 모집중)', () {
      final d = _makeDetail(
        isManualClosed:    false,
        applicationDeadline: DateTime(2099, 1, 1),
      );
      expect(d.isClosed,      isFalse);
      expect(d.isTimeExpired, isFalse);
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // GROUP C: SlotModel.isWorkTypeFull
  // ────────────────────────────────────────────────────────────────────────────
  group('SCENARIO-SLT-C: isWorkTypeFull', () {
    test('SCENARIO-SLT-C01: workDetails에 해당 workType 없으면 false', () {
      final slot = _makeSlot(workDetails: [_makeDetail(workType: '피킹')]);
      expect(slot.isWorkTypeFull('패킹'), isFalse);
    });

    test('SCENARIO-SLT-C02: requiredCount=0 → false (인원 제한 없음)', () {
      final slot = _makeSlot(
        workDetails: [_makeDetail(workType: '피킹', requiredCount: 0)],
        workTypeCounts: {'피킹': const _WorkTypeCount(confirmedCount: 5)},
      );
      expect(slot.isWorkTypeFull('피킹'), isFalse);
    });

    test('SCENARIO-SLT-C03: confirmedCount < requiredCount → false', () {
      final slot = _makeSlot(
        workDetails: [_makeDetail(workType: '피킹', requiredCount: 3)],
        workTypeCounts: {'피킹': const _WorkTypeCount(confirmedCount: 2)},
      );
      expect(slot.isWorkTypeFull('피킹'), isFalse);
    });

    test('SCENARIO-SLT-C04: confirmedCount == requiredCount → true (정확히 충족)', () {
      final slot = _makeSlot(
        workDetails: [_makeDetail(workType: '피킹', requiredCount: 3)],
        workTypeCounts: {'피킹': const _WorkTypeCount(confirmedCount: 3)},
      );
      expect(slot.isWorkTypeFull('피킹'), isTrue);
    });

    test('SCENARIO-SLT-C05: confirmedCount > requiredCount → true (초과 확정)', () {
      final slot = _makeSlot(
        workDetails: [_makeDetail(workType: '피킹', requiredCount: 3)],
        workTypeCounts: {'피킹': const _WorkTypeCount(confirmedCount: 5)},
      );
      expect(slot.isWorkTypeFull('피킹'), isTrue);
    });

    test('SCENARIO-SLT-C06: workTypeCounts에 해당 key 없으면 confirmedCount=0 → false', () {
      final slot = _makeSlot(
        workDetails: [_makeDetail(workType: '피킹', requiredCount: 3)],
        workTypeCounts: {}, // 카운트 없음
      );
      expect(slot.isWorkTypeFull('피킹'), isFalse);
    });

    test('SCENARIO-SLT-C07: 복수 workType 중 하나만 충족 → 해당 workType만 true', () {
      final slot = _makeSlot(
        workDetails: [
          _makeDetail(workType: '피킹', requiredCount: 3),
          _makeDetail(workType: '패킹', requiredCount: 2),
        ],
        workTypeCounts: {
          '피킹': const _WorkTypeCount(confirmedCount: 3),
          '패킹': const _WorkTypeCount(confirmedCount: 1),
        },
      );
      expect(slot.isWorkTypeFull('피킹'), isTrue);
      expect(slot.isWorkTypeFull('패킹'), isFalse);
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // GROUP D: visibleFrom 예약 공개
  // ────────────────────────────────────────────────────────────────────────────
  group('SCENARIO-SLT-D: visibleFrom 예약 공개', () {
    test('SCENARIO-SLT-D01: visibleFrom == null → 즉시 공개', () {
      final slot = _makeSlot(visibleFrom: null);
      expect(slot.isPublishedByVisibleFrom, isTrue);
    });

    test('SCENARIO-SLT-D02: visibleFrom 미래 → 미공개', () {
      final slot = _makeSlot(visibleFrom: DateTime(2099, 12, 31));
      expect(slot.isPublishedByVisibleFrom, isFalse);
    });

    test('SCENARIO-SLT-D03: visibleFrom 과거 → 공개', () {
      final slot = _makeSlot(visibleFrom: DateTime(2020, 1, 1));
      expect(slot.isPublishedByVisibleFrom, isTrue);
    });

    test('SCENARIO-SLT-D04: visibleFrom = 근무일 - 3일 (publishDaysBefore=3) 공개 시각 계산', () {
      final workDate = DateTime(2099, 8, 10);
      const publishDaysBefore = 3;
      const publishTime = '09:00';
      final parts = publishTime.split(':');
      final expected = DateTime(
        workDate.year,
        workDate.month,
        workDate.day - publishDaysBefore,
        int.parse(parts[0]),
        int.parse(parts[1]),
      );
      // 계산 결과가 workDate - 3일 09:00 임을 검증
      expect(expected, equals(DateTime(2099, 8, 7, 9, 0)));
    });

    test('SCENARIO-SLT-D05: visibleFrom 정각과 현재 시각이 같으면 공개 (isAfter 아님)', () {
      // isAfter는 strictly later → 같은 시각이면 공개(not after)
      final now = DateTime.now();
      final slot = _makeSlot(visibleFrom: now.subtract(const Duration(milliseconds: 1)));
      expect(slot.isPublishedByVisibleFrom, isTrue);
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // GROUP E: applicationDeadline 계산 (HOURS_BEFORE / FIXED_TIME)
  // ────────────────────────────────────────────────────────────────────────────
  group('SCENARIO-SLT-E: applicationDeadline 계산', () {
    test('SCENARIO-SLT-E01: HOURS_BEFORE 2시간 전 계산', () {
      final workStart = DateTime(2099, 8, 10, 9, 0);
      final result = _calcDeadline(
        type: _DeadlineType.HOURS_BEFORE,
        workStart: workStart,
        hoursBeforeStart: 2,
      );
      expect(result, equals(DateTime(2099, 8, 10, 7, 0)));
    });

    test('SCENARIO-SLT-E02: HOURS_BEFORE 0시간 전 → 근무 시작 시각과 동일', () {
      final workStart = DateTime(2099, 8, 10, 9, 0);
      final result = _calcDeadline(
        type: _DeadlineType.HOURS_BEFORE,
        workStart: workStart,
        hoursBeforeStart: 0,
      );
      expect(result, equals(workStart));
    });

    test('SCENARIO-SLT-E03: HOURS_BEFORE workStart=null → null 반환', () {
      final result = _calcDeadline(
        type: _DeadlineType.HOURS_BEFORE,
        workStart: null,
        hoursBeforeStart: 2,
      );
      expect(result, isNull);
    });

    test('SCENARIO-SLT-E04: HOURS_BEFORE hoursBeforeStart=null → null 반환', () {
      final result = _calcDeadline(
        type: _DeadlineType.HOURS_BEFORE,
        workStart: DateTime(2099, 8, 10, 9, 0),
        hoursBeforeStart: null,
      );
      expect(result, isNull);
    });

    test('SCENARIO-SLT-E05: FIXED_TIME → fixedDeadline 그대로 반환', () {
      final fixed = DateTime(2099, 8, 9, 18, 0);
      final result = _calcDeadline(
        type: _DeadlineType.FIXED_TIME,
        workStart: DateTime(2099, 8, 10, 9, 0),
        fixedDeadline: fixed,
      );
      expect(result, equals(fixed));
    });

    test('SCENARIO-SLT-E06: FIXED_TIME fixedDeadline=null → null 반환', () {
      final result = _calcDeadline(
        type: _DeadlineType.FIXED_TIME,
        workStart: DateTime(2099, 8, 10, 9, 0),
        fixedDeadline: null,
      );
      expect(result, isNull);
    });

    test('SCENARIO-SLT-E07: HOURS_BEFORE 24시간 전 계산 (자정 넘김)', () {
      final workStart = DateTime(2099, 8, 10, 6, 0); // 08/10 06:00
      final result = _calcDeadline(
        type: _DeadlineType.HOURS_BEFORE,
        workStart: workStart,
        hoursBeforeStart: 24,
      );
      expect(result, equals(DateTime(2099, 8, 9, 6, 0))); // 08/09 06:00
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // GROUP F: 역할별 탭 접근 권한
  // ────────────────────────────────────────────────────────────────────────────
  group('SCENARIO-SLT-F: 역할별 탭 접근 권한', () {
    test('SCENARIO-SLT-F01: BUSINESS_ADMIN → 모든 탭 접근 가능', () {
      final tabs = _TabVisibility.fromContext(_businessAdminCtx());
      expect(tabs.showToRegister, isTrue);
      expect(tabs.showToManage,   isTrue);
      expect(tabs.showWage,       isTrue);
      expect(tabs.showContract,   isTrue);
      expect(tabs.showStats,      isTrue);
    });

    test('SCENARIO-SLT-F02: SUB_ADMIN 권한 없음 → 모든 탭 접근 불가', () {
      final tabs = _TabVisibility.fromContext(
        _subAdminCtx(permissions: _MemberPermissions.none),
      );
      expect(tabs.showToRegister, isFalse);
      expect(tabs.showToManage,   isFalse);
      expect(tabs.showWage,       isFalse);
      expect(tabs.showContract,   isFalse);
      expect(tabs.showStats,      isFalse);
    });

    test('SCENARIO-SLT-F03: SUB_ADMIN canManageTo=true → 공고 등록/관리 탭 접근 가능', () {
      final tabs = _TabVisibility.fromContext(
        _subAdminCtx(permissions: const _MemberPermissions(canManageTo: true)),
      );
      expect(tabs.showToRegister, isTrue);
      expect(tabs.showToManage,   isTrue);
      expect(tabs.showWage,       isFalse);
      expect(tabs.showContract,   isFalse);
    });

    test('SCENARIO-SLT-F04: SUB_ADMIN canManageWorkers=true → 공고 관리 탭만 접근 (등록 불가)', () {
      final tabs = _TabVisibility.fromContext(
        _subAdminCtx(permissions: const _MemberPermissions(canManageWorkers: true)),
      );
      expect(tabs.showToRegister, isFalse);
      expect(tabs.showToManage,   isTrue);  // canManageWorkers도 공고관리 탭 허용
      expect(tabs.showWage,       isFalse);
    });

    test('SCENARIO-SLT-F05: SUB_ADMIN canManageWage=true → 급여·통계 탭 접근 가능', () {
      final tabs = _TabVisibility.fromContext(
        _subAdminCtx(permissions: const _MemberPermissions(canManageWage: true)),
      );
      expect(tabs.showWage,  isTrue);
      expect(tabs.showStats, isTrue);
      expect(tabs.showToRegister, isFalse);
    });

    test('SCENARIO-SLT-F06: SUB_ADMIN canManageContract=true → 계약서 탭만 접근', () {
      final tabs = _TabVisibility.fromContext(
        _subAdminCtx(permissions: const _MemberPermissions(canManageContract: true)),
      );
      expect(tabs.showContract,   isTrue);
      expect(tabs.showToRegister, isFalse);
      expect(tabs.showWage,       isFalse);
    });

    test('SCENARIO-SLT-F07: SUB_ADMIN 전체 권한 → BUSINESS_ADMIN과 동일하게 모두 접근', () {
      final tabs = _TabVisibility.fromContext(
        _subAdminCtx(permissions: _MemberPermissions.all),
      );
      expect(tabs.showToRegister, isTrue);
      expect(tabs.showToManage,   isTrue);
      expect(tabs.showWage,       isTrue);
      expect(tabs.showContract,   isTrue);
      expect(tabs.showStats,      isTrue);
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // GROUP G: TO 삭제 권한 (canDelete)
  // ────────────────────────────────────────────────────────────────────────────
  group('SCENARIO-SLT-G: TO 삭제 권한 (canDelete)', () {
    test('SCENARIO-SLT-G01: BUSINESS_ADMIN → canDelete=true', () {
      expect(_businessAdminCtx().canDelete, isTrue);
    });

    test('SCENARIO-SLT-G02: SUPER_ADMIN → canDelete=true', () {
      expect(_superAdminCtx().canDelete, isTrue);
    });

    test('SCENARIO-SLT-G03: SUB_ADMIN canManageTo=true → canDelete=false (SUB_ADMIN 삭제 불가)', () {
      final ctx = _subAdminCtx(
        permissions: const _MemberPermissions(canManageTo: true),
      );
      expect(ctx.canDelete, isFalse);
    });

    test('SCENARIO-SLT-G04: SUB_ADMIN 전체 권한 → canDelete=false', () {
      final ctx = _subAdminCtx(permissions: _MemberPermissions.all);
      expect(ctx.canDelete, isFalse);
    });

    test('SCENARIO-SLT-G05: USER(subAdminOf 없음) → canDelete=false', () {
      expect(_userCtx().canDelete, isFalse);
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // GROUP H: effectiveBusinessId 패턴
  // ────────────────────────────────────────────────────────────────────────────
  group('SCENARIO-SLT-H: effectiveBusinessId', () {
    test('SCENARIO-SLT-H01: BUSINESS_ADMIN → user.businessId 반환', () {
      expect(_businessAdminCtx(bizId: 'biz-123').effectiveBusinessId, equals('biz-123'));
    });

    test('SCENARIO-SLT-H02: BUSINESS_ADMIN businessId=null → null 반환', () {
      final ctx = _UserContext(
        user: _User(uid: 'uid', role: _UserRole.BUSINESS_ADMIN, businessId: null),
      );
      expect(ctx.effectiveBusinessId, isNull);
    });

    test('SCENARIO-SLT-H03: SUB_ADMIN → user.subAdminOf 반환', () {
      final ctx = _subAdminCtx();
      expect(ctx.effectiveBusinessId, equals('biz-001'));
    });

    test('SCENARIO-SLT-H04: USER(일반) → null 반환', () {
      expect(_userCtx().effectiveBusinessId, isNull);
    });

    test('SCENARIO-SLT-H05: SUPER_ADMIN → null 반환 (전체 접근, businessId 불필요)', () {
      expect(_superAdminCtx().effectiveBusinessId, isNull);
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // GROUP I: can() 함수
  // ────────────────────────────────────────────────────────────────────────────
  group('SCENARIO-SLT-I: can() 함수', () {
    test('SCENARIO-SLT-I01: BUSINESS_ADMIN → 항상 true (memberPermissions 무관)', () {
      final ctx = _businessAdminCtx();
      expect(ctx.can((p) => p.canManageTo),       isTrue);
      expect(ctx.can((p) => p.canManageWorkers),  isTrue);
      expect(ctx.can((p) => p.canManageWage),     isTrue);
      expect(ctx.can((p) => p.canManageContract), isTrue);
    });

    test('SCENARIO-SLT-I02: SUB_ADMIN + memberPermissions 로드됨 + canManageTo=true → true', () {
      final ctx = _subAdminCtx(permissions: const _MemberPermissions(canManageTo: true));
      expect(ctx.can((p) => p.canManageTo),      isTrue);
      expect(ctx.can((p) => p.canManageWorkers), isFalse);
    });

    test('SCENARIO-SLT-I03: SUB_ADMIN + memberPermissions=null (로드 전) → false', () {
      final ctx = _subAdminCtx(loaded: false);
      expect(ctx.can((p) => p.canManageTo), isFalse);
    });

    test('SCENARIO-SLT-I04: SUB_ADMIN + memberPermissions=none → 모두 false', () {
      final ctx = _subAdminCtx(permissions: _MemberPermissions.none);
      expect(ctx.can((p) => p.canManageTo),       isFalse);
      expect(ctx.can((p) => p.canManageWorkers),  isFalse);
      expect(ctx.can((p) => p.canManageWage),     isFalse);
      expect(ctx.can((p) => p.canManageContract), isFalse);
    });

    test('SCENARIO-SLT-I05: USER(isUser=true) → false', () {
      final ctx = _userCtx();
      expect(ctx.can((p) => p.canManageTo), isFalse);
    });

    test('SCENARIO-SLT-I06: SUB_ADMIN + 전체 권한 → 모두 true', () {
      final ctx = _subAdminCtx(permissions: _MemberPermissions.all);
      expect(ctx.can((p) => p.canManageTo),       isTrue);
      expect(ctx.can((p) => p.canManageWorkers),  isTrue);
      expect(ctx.can((p) => p.canManageWage),     isTrue);
      expect(ctx.can((p) => p.canManageContract), isTrue);
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // GROUP J: isAdminOf 보안 규칙 null 방어
  // ────────────────────────────────────────────────────────────────────────────
  group('SCENARIO-SLT-J: isAdminOf null 방어', () {
    final businesses = [
      const _Business(
        id: 'biz-001',
        ownerId: 'owner-uid',
        adminIds: ['admin-uid'],
      ),
    ];

    test('SCENARIO-SLT-J01: businessId=null → early return false', () {
      expect(
        _isAdminOf(businessId: null, requestUid: 'owner-uid', businesses: businesses),
        isFalse,
      );
    });

    test('SCENARIO-SLT-J02: businessId 빈 문자열 → early return false', () {
      expect(
        _isAdminOf(businessId: '', requestUid: 'owner-uid', businesses: businesses),
        isFalse,
      );
    });

    test('SCENARIO-SLT-J03: businessId 정상 + ownerId 일치 → true', () {
      expect(
        _isAdminOf(businessId: 'biz-001', requestUid: 'owner-uid', businesses: businesses),
        isTrue,
      );
    });

    test('SCENARIO-SLT-J04: businessId 정상 + adminIds 포함 → true', () {
      expect(
        _isAdminOf(businessId: 'biz-001', requestUid: 'admin-uid', businesses: businesses),
        isTrue,
      );
    });

    test('SCENARIO-SLT-J05: businessId 정상 + 해당 없는 uid → false', () {
      expect(
        _isAdminOf(businessId: 'biz-001', requestUid: 'random-uid', businesses: businesses),
        isFalse,
      );
    });

    test('SCENARIO-SLT-J06: 존재하지 않는 businessId → false', () {
      expect(
        _isAdminOf(businessId: 'biz-999', requestUid: 'owner-uid', businesses: businesses),
        isFalse,
      );
    });

    test('SCENARIO-SLT-J07: requestUid=null → false', () {
      expect(
        _isAdminOf(businessId: 'biz-001', requestUid: null, businesses: businesses),
        isFalse,
      );
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // GROUP K: whereIn 복합쿼리 PERMISSION_DENIED 방어
  // ────────────────────────────────────────────────────────────────────────────
  group('SCENARIO-SLT-K: whereIn 쿼리 PERMISSION_DENIED 방어', () {
    final businesses = [
      const _Business(id: 'biz-001', ownerId: 'owner-uid'),
    ];

    test('SCENARIO-SLT-K01: whereIn 쿼리 → filters.businessId == null → isAdminOf false → PERMISSION_DENIED', () {
      final filteredBusinessId = _simulateWhereInFilterBusinessId(isWhereInQuery: true);
      expect(filteredBusinessId, isNull);

      final allowed = _isAdminOf(
        businessId: filteredBusinessId,
        requestUid: 'owner-uid',
        businesses: businesses,
      );
      expect(allowed, isFalse, reason: 'whereIn 쿼리에서 businessId가 null이므로 PERMISSION_DENIED');
    });

    test('SCENARIO-SLT-K02: 단건 isEqualTo 쿼리 → filters.businessId 정상 → isAdminOf true → 허용', () {
      final filteredBusinessId = _simulateWhereInFilterBusinessId(isWhereInQuery: false);
      expect(filteredBusinessId, equals('biz-001'));

      final allowed = _isAdminOf(
        businessId: filteredBusinessId,
        requestUid: 'owner-uid',
        businesses: businesses,
      );
      expect(allowed, isTrue, reason: '단건 쿼리에서 businessId 추출 성공 → 허용');
    });

    test('SCENARIO-SLT-K03: whereIn 쿼리 → 클라이언트 필터링으로 전환 시 전체 결과 병합 가능', () {
      // 2개 사업장의 TO를 각각 단건 쿼리 후 클라이언트에서 병합
      final resultsBiz1 = ['to-001', 'to-002'];
      final resultsBiz2 = ['to-003'];
      final merged = [...resultsBiz1, ...resultsBiz2];
      expect(merged, hasLength(3));
      expect(merged, containsAll(['to-001', 'to-002', 'to-003']));
    });

    test('SCENARIO-SLT-K04: whereIn → isEqualTo 병렬 전환 후 중복 없음 검증', () {
      final allResults = ['to-001', 'to-002', 'to-001']; // 중복 포함
      final deduped    = allResults.toSet().toList();
      expect(deduped, hasLength(2));
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // GROUP L: USER TO 목록 조회 제한
  // ────────────────────────────────────────────────────────────────────────────
  group('SCENARIO-SLT-L: USER TO 조회 제한', () {
    test('SCENARIO-SLT-L01: limit=10, isPublished=true → 허용', () {
      final result = _validateUserToQuery(
        limit: 10,
        hasIsPublishedFilter: true,
        isPublishedValue: true,
      );
      expect(result.allowed, isTrue);
    });

    test('SCENARIO-SLT-L02: limit=50 (경계값) → 허용', () {
      final result = _validateUserToQuery(
        limit: 50,
        hasIsPublishedFilter: true,
        isPublishedValue: true,
      );
      expect(result.allowed, isTrue);
    });

    test('SCENARIO-SLT-L03: limit=51 → 거부 (덤프 방지)', () {
      final result = _validateUserToQuery(
        limit: 51,
        hasIsPublishedFilter: true,
        isPublishedValue: true,
      );
      expect(result.allowed, isFalse);
      expect(result.reason, contains('limit > 50'));
    });

    test('SCENARIO-SLT-L04: limit=100 → 거부', () {
      final result = _validateUserToQuery(
        limit: 100,
        hasIsPublishedFilter: true,
        isPublishedValue: true,
      );
      expect(result.allowed, isFalse);
    });

    test('SCENARIO-SLT-L05: isPublished 필터 없음 → 거부', () {
      final result = _validateUserToQuery(
        limit: 20,
        hasIsPublishedFilter: false,
        isPublishedValue: true,
      );
      expect(result.allowed, isFalse);
      expect(result.reason, contains('isPublished 필터 누락'));
    });

    test('SCENARIO-SLT-L06: isPublished=false 조건 → 거부 (비공개 TO 조회 불가)', () {
      final result = _validateUserToQuery(
        limit: 20,
        hasIsPublishedFilter: true,
        isPublishedValue: false,
      );
      expect(result.allowed, isFalse);
      expect(result.reason, contains('isPublished=false'));
    });

    test('SCENARIO-SLT-L07: limit=0 → 허용 (0개 조회는 안전)', () {
      final result = _validateUserToQuery(
        limit: 0,
        hasIsPublishedFilter: true,
        isPublishedValue: true,
      );
      expect(result.allowed, isTrue);
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // GROUP M: 복합 시나리오 (End-to-End)
  // ────────────────────────────────────────────────────────────────────────────
  group('SCENARIO-SLT-M: 복합 E2E 시나리오', () {
    test('SCENARIO-SLT-M01: 수동마감 슬롯에서 workType별 충족 여부는 무의미 (슬롯 자체 마감)', () {
      final slot = _makeSlot(
        status: _SlotStatus.closed,
        workDetails: [_makeDetail(workType: '피킹', requiredCount: 3)],
        workTypeCounts: {'피킹': const _WorkTypeCount(confirmedCount: 1)},
      );
      // 슬롯 자체가 마감 → isEffectivelyClosed=true
      expect(slot.isEffectivelyClosed, isTrue);
      // workTypeFull은 확정 인원 기준 → 아직 미충족
      expect(slot.isWorkTypeFull('피킹'), isFalse);
    });

    test('SCENARIO-SLT-M02: workDetails 있고 deadline 경과 + 미래 날짜 → isEffectivelyClosed 판단', () {
      // workDetails 있음 → isDeadlinePassed(slot 레벨) 무시, workDetail별 isTimeExpired 적용
      final past = DateTime(2020, 1, 1);
      final slot = _makeSlot(
        date: DateTime(2099, 12, 31), // 미래 날짜
        workDetails: [_makeDetail(applicationDeadline: past)],
        applicationDeadline: DateTime(2099, 12, 30), // 슬롯 레벨 deadline은 미래
      );
      // workDetails 있음 → workDetail.isTimeExpired 체크
      // workDetail.applicationDeadline=past → isTimeExpired=true → all expired → true
      expect(slot.isEffectivelyClosed, isTrue);
    });

    test('SCENARIO-SLT-M03: SUB_ADMIN canManageTo=true이지만 TO 삭제는 불가 → 편집만 가능', () {
      final ctx = _subAdminCtx(
        permissions: const _MemberPermissions(canManageTo: true),
      );
      // 공고 등록/관리 탭 접근 가능
      expect(ctx.can((p) => p.canManageTo), isTrue);
      // 하지만 삭제는 BUSINESS_ADMIN/SUPER_ADMIN만
      expect(ctx.canDelete, isFalse);
    });

    test('SCENARIO-SLT-M04: SUPER_ADMIN은 effectiveBusinessId=null이지만 삭제 가능', () {
      final ctx = _superAdminCtx();
      expect(ctx.effectiveBusinessId, isNull);
      expect(ctx.canDelete,           isTrue);
    });

    test('SCENARIO-SLT-M05: isAdminOf null guard → whereIn 버그 재현', () {
      // Firebase whereIn 쿼리에서 filters.businessId == null이 반환됨
      // isAdminOf(null) → early return false
      final businesses = [const _Business(id: 'biz-001', ownerId: 'uid')];
      final nullBizId  = _simulateWhereInFilterBusinessId(isWhereInQuery: true);
      expect(nullBizId, isNull);
      expect(
        _isAdminOf(businessId: nullBizId, requestUid: 'uid', businesses: businesses),
        isFalse,
        reason: '버그 재현: whereIn → null → PERMISSION_DENIED',
      );
    });

    test('SCENARIO-SLT-M06: 예약 공개 슬롯 + 마감 조건 없음 → 미공개 상태로 유지', () {
      // visibleFrom=미래 → 미공개, 하지만 isEffectivelyClosed 판단과는 독립
      final slot = _makeSlot(
        date: DateTime(2099, 12, 31),
        visibleFrom: DateTime(2099, 12, 30), // 미래
        status: _SlotStatus.open,
      );
      expect(slot.isPublishedByVisibleFrom, isFalse); // 아직 공개 안 됨
      expect(slot.isEffectivelyClosed,       isFalse); // 마감도 아님
    });

    test('SCENARIO-SLT-M07: 복수 workType 모두 충족 → 슬롯 수동마감 아니어도 운영상 full', () {
      final slot = _makeSlot(
        date: DateTime(2099, 12, 31),
        workDetails: [
          _makeDetail(workType: '피킹', requiredCount: 2),
          _makeDetail(workType: '패킹', requiredCount: 3),
        ],
        workTypeCounts: {
          '피킹': const _WorkTypeCount(confirmedCount: 2),
          '패킹': const _WorkTypeCount(confirmedCount: 3),
        },
      );
      expect(slot.isWorkTypeFull('피킹'), isTrue);
      expect(slot.isWorkTypeFull('패킹'), isTrue);
      // SlotModel status는 CF가 갱신하므로 런타임엔 open일 수 있음
      expect(slot.isEffectivelyClosed, isFalse); // status=open 이면 false
    });

    test('SCENARIO-SLT-M08: BUSINESS_ADMIN → can() 항상 true (권한 로드 전에도)', () {
      // BUSINESS_ADMIN은 memberPermissions=null이어도 can() → true
      final ctx = _UserContext(
        user: _User(uid: 'uid', role: _UserRole.BUSINESS_ADMIN, businessId: 'biz-001'),
        memberPermissions: null, // 미로드
      );
      expect(ctx.can((p) => p.canManageTo), isTrue);
    });

    test('SCENARIO-SLT-M09: USER TO 조회 — limit=50 + isPublished=true 경계값 허용', () {
      final r = _validateUserToQuery(
        limit: 50,
        hasIsPublishedFilter: true,
        isPublishedValue: true,
      );
      expect(r.allowed, isTrue);
      expect(r.reason, isNull);
    });

    test('SCENARIO-SLT-M10: applicationDeadline HOURS_BEFORE → isTimeExpired 판단', () {
      final workStart = DateTime.now().add(const Duration(hours: 1));
      final deadline  = _calcDeadline(
        type: _DeadlineType.HOURS_BEFORE,
        workStart: workStart,
        hoursBeforeStart: 2,
      );
      // deadline = now - 1시간 → 과거
      expect(deadline, isNotNull);
      final isExpired = DateTime.now().isAfter(deadline!);
      expect(isExpired, isTrue,
          reason: '근무 시작 1시간 후인데 2시간 전 마감 → 이미 마감');
    });
  });
}
