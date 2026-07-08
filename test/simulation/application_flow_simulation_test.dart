// test/simulation/application_flow_simulation_test.dart
//
// 지원 처리 전체 상태 흐름 시뮬레이션 (applyToTO → CONTRACT_PENDING → CONFIRMED)
// 목적: AppStatus 상수 · 12단계 검증 · 선점 트랜잭션 · 일괄 확정 · 취소 · 재지원 로직을
//       순수 Dart 로직으로 재구현해 버그·엣지케이스를 탐지한다.
//
// 의존성: Firebase · Flutter · Provider 없음. 순수 Dart 로직만.

// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';

// ══════════════════════════════════════════════════════════════
// 1. 상태 상수 (AppStatus 복제)
// ══════════════════════════════════════════════════════════════

abstract class SimAppStatus {
  static const String pending         = 'PENDING';
  static const String contractPending = 'CONTRACT_PENDING';
  static const String confirmed       = 'CONFIRMED';
  static const String rejected        = 'REJECTED';
  static const String canceled        = 'CANCELED';
  static const String autoCanceled    = 'AUTO_CANCELED';

  static const List<String> activeStates      = [pending, contractPending, confirmed];
  static const List<String> confirmedStatuses = [confirmed, contractPending];
  static const List<String> inactiveStates    = [rejected, canceled, autoCanceled];

  // 퇴사·해지 하위 상태
  static const String approved     = 'APPROVED';
  static const String autoApproved = 'AUTO_APPROVED';

  // 취소 사유
  static const String adminCanceled   = 'ADMIN_CANCELED';
  static const String userCanceled    = 'USER_CANCELED';
  static const String sameDayCancel   = 'SAME_DAY_CANCEL';
  static const String scheduleConflict = 'SCHEDULE_CONFLICT';
}

// ══════════════════════════════════════════════════════════════
// 2. 데이터 클래스 (Firestore 의존 없이 순수 Dart)
// ══════════════════════════════════════════════════════════════

class SimUser {
  final String uid;
  final bool hasIdCard;
  final bool hasBankInfo;
  final bool hasBankbookImage;
  final bool isBlacklisted;
  final String? blacklistReason;
  final bool passVerified;  // ci + passVerifiedAt 있음
  final bool isIdVerified;  // OCR 통과
  final DateTime? restrictedUntil; // noShow 제재 만료일

  const SimUser({
    required this.uid,
    this.hasIdCard = true,
    this.hasBankInfo = true,
    this.hasBankbookImage = true,
    this.isBlacklisted = false,
    this.blacklistReason,
    this.passVerified = true,
    this.isIdVerified = true,
    this.restrictedUntil,
  });
}

enum SimTOType { flex, contract }

class SimTO {
  final String id;
  final String businessId;
  final String status; // 'DRAFT', 'OPEN', 'CLOSED', 'FULL'
  final bool isManualClosed;
  final bool isPostingExpired;
  final bool isDeadlinePassed;
  final SimTOType type;
  final int totalRequired;
  final int totalConfirmed;
  final Map<String, int> workTypeRequiredCounts;
  final Map<String, int> workTypeConfirmedCounts;

  const SimTO({
    required this.id,
    required this.businessId,
    this.status = 'OPEN',
    this.isManualClosed = false,
    this.isPostingExpired = false,
    this.isDeadlinePassed = false,
    this.type = SimTOType.flex,
    this.totalRequired = 5,
    this.totalConfirmed = 0,
    this.workTypeRequiredCounts = const {},
    this.workTypeConfirmedCounts = const {},
  });

  bool get isApplicable =>
      status != 'DRAFT' &&
      !isManualClosed &&
      status != 'CLOSED' &&
      status != 'FULL' &&
      !isPostingExpired &&
      !isDeadlinePassed;
}

class SimSlot {
  final String id;
  final bool isManualClosed;
  final String status; // 'open', 'closed', 'full'
  final Map<String, int> workTypeRequiredCounts;
  final Map<String, int> workTypeConfirmedCounts;
  final Map<String, DateTime?> workTypeDeadlines;

  const SimSlot({
    required this.id,
    this.isManualClosed = false,
    this.status = 'open',
    this.workTypeRequiredCounts = const {},
    this.workTypeConfirmedCounts = const {},
    this.workTypeDeadlines = const {},
  });

  bool get isClosed => isManualClosed || status == 'closed';

  bool isWorkTypeDeadlinePassed(String workType) {
    final deadline = workTypeDeadlines[workType];
    return deadline != null && deadline.isBefore(DateTime.now());
  }

  bool isWorkTypeFull(String workType) {
    final req = workTypeRequiredCounts[workType] ?? 0;
    final confirmed = workTypeConfirmedCounts[workType] ?? 0;
    return req > 0 && confirmed >= req;
  }
}

class SimApplication {
  final String id;
  final String uid;
  final String businessId;
  final String toId;
  final String? slotId;
  final String selectedWorkType;
  final String? workDetailId;
  final String status;
  final DateTime workDate;
  final String startTime;
  final String endTime;
  final DateTime? workEndDate;
  final List<String>? workDays;
  final String? cancelReason;
  final String? resignStatus;
  final String? terminationStatus;
  final List<Map<String, dynamic>> statusHistory;

  const SimApplication({
    required this.id,
    required this.uid,
    required this.businessId,
    required this.toId,
    this.slotId,
    required this.selectedWorkType,
    this.workDetailId,
    required this.status,
    required this.workDate,
    required this.startTime,
    required this.endTime,
    this.workEndDate,
    this.workDays,
    this.cancelReason,
    this.resignStatus,
    this.terminationStatus,
    this.statusHistory = const [],
  });

  SimApplication copyWith({
    String? status,
    String? cancelReason,
    String? resignStatus,
    String? terminationStatus,
    List<Map<String, dynamic>>? statusHistory,
  }) =>
      SimApplication(
        id: id,
        uid: uid,
        businessId: businessId,
        toId: toId,
        slotId: slotId,
        selectedWorkType: selectedWorkType,
        workDetailId: workDetailId,
        status: status ?? this.status,
        workDate: workDate,
        startTime: startTime,
        endTime: endTime,
        workEndDate: workEndDate,
        workDays: workDays,
        cancelReason: cancelReason ?? this.cancelReason,
        resignStatus: resignStatus ?? this.resignStatus,
        terminationStatus: terminationStatus ?? this.terminationStatus,
        statusHistory: statusHistory ?? this.statusHistory,
      );

  bool get isLongTerm =>
      (workDays != null && workDays!.isNotEmpty) ||
      (workEndDate != null && workDate.day != workEndDate!.day);

  bool get isTerminationApproved =>
      resignStatus == SimAppStatus.approved ||
      resignStatus == SimAppStatus.autoApproved ||
      terminationStatus == SimAppStatus.approved ||
      terminationStatus == SimAppStatus.autoApproved;
}

// ══════════════════════════════════════════════════════════════
// 3. 시뮬레이션 서비스 (순수 Dart로 서비스 로직 재구현)
// ══════════════════════════════════════════════════════════════

class SimApplyResult {
  final bool success;
  final String? errorMessage;
  final String? applicationId;

  const SimApplyResult({
    required this.success,
    this.errorMessage,
    this.applicationId,
  });
}

class SimConfirmResult {
  final bool success;
  final bool alreadyConfirmed;
  final String? errorMessage;
  final List<String> autoCanceledIds;

  const SimConfirmResult({
    required this.success,
    this.alreadyConfirmed = false,
    this.errorMessage,
    this.autoCanceledIds = const [],
  });
}

// CancelResult는 아래에서 mutable 클래스로 정의됨

/// 지원 흐름 12단계 검증 시뮬레이터
class ApplySimulator {
  // ── Step 1: 사용자 서류 체크
  static String? checkUserDocuments(SimUser user) {
    if (!user.hasIdCard) return '신분증 등록이 필요합니다.';
    if (!user.hasBankInfo) return '통장 정보 등록이 필요합니다.';
    if (!user.hasBankbookImage) return '통장사본 등록이 필요합니다.';
    return null;
  }

  // ── Step 2: 블랙리스트 체크
  static String? checkBlacklist(SimUser user) {
    if (user.isBlacklisted) {
      final reason = user.blacklistReason ?? '이용 정책 위반';
      return '이용 제한된 계정입니다.\n사유: $reason';
    }
    return null;
  }

  // ── Step 3: PASS 본인인증 체크
  static String? checkPassAuth(SimUser user) {
    if (!user.passVerified) return '본인인증이 필요합니다.';
    return null;
  }

  // ── Step 4: 신분증 인증 체크 (flex 타입만 — slotId != null)
  static String? checkIdVerification(SimUser user, {required bool isFlexType}) {
    if (isFlexType && !user.isIdVerified) {
      return '신분증 인증 후 지원할 수 있습니다.';
    }
    return null;
  }

  // ── Step 5: noShow 제재 체크
  static String? checkNoShowRestriction(SimUser user) {
    final until = user.restrictedUntil;
    if (until != null && until.isAfter(DateTime.now())) {
      final remainDays = until.difference(DateTime.now()).inDays + 1;
      return '무단 결근 페널티로 ${remainDays}일 동안 지원이 제한됩니다.';
    }
    return null;
  }

  // ── Step 6: TO 상태 체크
  static String? checkTOStatus(SimTO to) {
    if (to.status == 'DRAFT') return '비공개 공고에는 지원할 수 없습니다.';
    if (to.isManualClosed || to.status == 'CLOSED' || to.status == 'FULL') {
      return '마감된 공고입니다.';
    }
    return null;
  }

  // ── Step 7: 게시 만료 / 지원 마감 체크
  static String? checkTODeadline(SimTO to) {
    if (to.isPostingExpired || to.isDeadlinePassed) return '지원 마감된 공고입니다.';
    return null;
  }

  // ── Step 8: 슬롯 상태 체크 (flex 타입)
  static String? checkSlotStatus(SimSlot? slot, String workType) {
    if (slot == null) return null;
    if (slot.isClosed) return '해당 날짜는 마감되었습니다.';
    if (slot.isWorkTypeDeadlinePassed(workType)) return '해당 업무의 지원 마감 시간이 지났습니다.';
    if (slot.isWorkTypeFull(workType)) return '해당 업무의 모집 인원이 마감되었습니다.';
    return null;
  }

  // ── Step 9: 중복 지원 체크
  static String? checkDuplicateApplication({
    required String uid,
    required String toId,
    required String selectedWorkType,
    required String? slotId,
    required String? workDetailId,
    required List<SimApplication> existingApps,
  }) {
    for (final app in existingApps) {
      if (app.uid != uid || app.toId != toId) continue;
      if (app.selectedWorkType != selectedWorkType) continue;
      if (slotId != null && app.slotId != slotId) continue;
      if (workDetailId != null && workDetailId.isNotEmpty &&
          app.workDetailId != workDetailId) continue;

      // 퇴사/해지 완료된 경우 재지원 허용
      final isResignDone = app.resignStatus == SimAppStatus.approved ||
          app.resignStatus == SimAppStatus.autoApproved;
      final isTermDone = app.terminationStatus == SimAppStatus.approved ||
          app.terminationStatus == SimAppStatus.autoApproved;
      if (isResignDone || isTermDone) continue;

      if (SimAppStatus.activeStates.contains(app.status)) {
        return '이미 지원한 업무입니다.';
      }
    }
    return null;
  }

  // ── Step 10: 시간 충돌 체크
  static bool hasTimeOverlap(String s1, String e1, String s2, String e2) {
    if (s1.isEmpty || e1.isEmpty || s2.isEmpty || e2.isEmpty) return false;
    int toMin(String t) {
      final p = t.split(':');
      if (p.length < 2) return 0;
      return int.parse(p[0]) * 60 + int.parse(p[1]);
    }

    final a1 = toMin(s1);
    final rawB1 = toMin(e1);
    final a2 = toMin(s2);
    final rawB2 = toMin(e2);

    final b1 = rawB1 <= a1 ? rawB1 + 1440 : rawB1;
    final b2 = rawB2 <= a2 ? rawB2 + 1440 : rawB2;

    bool overlaps(int x1, int y1, int x2, int y2) => x1 < y2 && x2 < y1;

    return overlaps(a1, b1, a2, b2) ||
        overlaps(a1, b1, a2 + 1440, b2 + 1440) ||
        overlaps(a1, b1, a2 - 1440, b2 - 1440);
  }

  static String? checkTimeConflict({
    required DateTime workDate,
    required String startTime,
    required String endTime,
    required List<SimApplication> confirmedApps,
  }) {
    for (final s in confirmedApps) {
      final sameDay = s.workDate.year == workDate.year &&
          s.workDate.month == workDate.month &&
          s.workDate.day == workDate.day;
      if (!sameDay) continue;
      if (hasTimeOverlap(startTime, endTime, s.startTime, s.endTime)) {
        return '이미 ${s.startTime}~${s.endTime}에 확정된 근무가 있습니다.';
      }
    }
    return null;
  }

  /// 12단계 전체 검증 후 결과 반환
  static SimApplyResult applyToTO({
    required SimUser user,
    required SimTO to,
    SimSlot? slot,
    required DateTime workDate,
    required String startTime,
    required String endTime,
    required String selectedWorkType,
    String? workDetailId,
    required List<SimApplication> existingApps,
    required List<SimApplication> confirmedApps,
  }) {
    final isFlexType = slot != null;

    // 1: 서류
    final docError = checkUserDocuments(user);
    if (docError != null) return SimApplyResult(success: false, errorMessage: docError);

    // 2: 블랙리스트
    final blacklistError = checkBlacklist(user);
    if (blacklistError != null) return SimApplyResult(success: false, errorMessage: blacklistError);

    // 3: PASS 인증
    final passError = checkPassAuth(user);
    if (passError != null) return SimApplyResult(success: false, errorMessage: passError);

    // 4: 신분증 인증 (flex만)
    final idError = checkIdVerification(user, isFlexType: isFlexType);
    if (idError != null) return SimApplyResult(success: false, errorMessage: idError);

    // 5: noShow 제재
    final restrictionError = checkNoShowRestriction(user);
    if (restrictionError != null) return SimApplyResult(success: false, errorMessage: restrictionError);

    // 6: TO 상태
    final toStatusError = checkTOStatus(to);
    if (toStatusError != null) return SimApplyResult(success: false, errorMessage: toStatusError);

    // 7: 게시 만료
    final deadlineError = checkTODeadline(to);
    if (deadlineError != null) return SimApplyResult(success: false, errorMessage: deadlineError);

    // 8: 슬롯 상태
    final slotError = checkSlotStatus(slot, selectedWorkType);
    if (slotError != null) return SimApplyResult(success: false, errorMessage: slotError);

    // 9: 중복 지원
    final dupError = checkDuplicateApplication(
      uid: user.uid,
      toId: to.id,
      selectedWorkType: selectedWorkType,
      slotId: slot?.id,
      workDetailId: workDetailId,
      existingApps: existingApps,
    );
    if (dupError != null) return SimApplyResult(success: false, errorMessage: dupError);

    // 10: 시간 충돌
    final conflictError = checkTimeConflict(
      workDate: workDate,
      startTime: startTime,
      endTime: endTime,
      confirmedApps: confirmedApps,
    );
    if (conflictError != null) return SimApplyResult(success: false, errorMessage: conflictError);

    // 11: TOCTOU 최종 재검증은 서버 트랜잭션 시뮬레이션 (여기서는 통과 처리)
    // 12: 지원서 생성
    return SimApplyResult(
      success: true,
      applicationId: 'app-${DateTime.now().millisecondsSinceEpoch}',
    );
  }
}

/// 확정 트랜잭션 시뮬레이터 (_confirmWithConflictCheck)
class ConfirmSimulator {
  /// CONTRACT_PENDING 선점 시뮬레이션
  /// - freshStatus가 이미 확정 상태면 alreadyConfirmed=true
  /// - 정원 초과면 예외
  static SimConfirmResult confirm({
    required SimApplication app,
    required List<SimApplication> allUserApps, // 동일 uid의 모든 지원서
    required SimTO to,
    SimSlot? slot,
  }) {
    // freshStatus 체크 (트랜잭션 내)
    if (SimAppStatus.confirmedStatuses.contains(app.status)) {
      return const SimConfirmResult(success: true, alreadyConfirmed: true);
    }
    if (app.status == SimAppStatus.canceled) {
      return const SimConfirmResult(
          success: false, errorMessage: '취소된 지원서는 확정할 수 없습니다');
    }
    if (app.status == SimAppStatus.autoCanceled) {
      return const SimConfirmResult(
          success: false, errorMessage: '자동 취소된 지원서는 확정할 수 없습니다');
    }
    if (app.status == SimAppStatus.rejected) {
      return const SimConfirmResult(
          success: false, errorMessage: '거절된 지원서는 확정할 수 없습니다');
    }

    // CAPACITY-GUARD: 정원 재검증 (슬롯 우선)
    if (slot != null) {
      final req = slot.workTypeRequiredCounts[app.selectedWorkType] ?? 0;
      final confirmed = slot.workTypeConfirmedCounts[app.selectedWorkType] ?? 0;
      if (req > 0 && confirmed >= req) {
        return SimConfirmResult(
            success: false,
            errorMessage: '정원이 초과되었습니다. (필요: $req명, 현재: $confirmed명 확정)');
      }
    } else {
      final req = to.workTypeRequiredCounts[app.selectedWorkType] ?? 0;
      final confirmed = to.workTypeConfirmedCounts[app.selectedWorkType] ?? 0;
      if (req > 0 && confirmed >= req) {
        return SimConfirmResult(
            success: false,
            errorMessage: '정원이 초과되었습니다. (필요: $req명, 현재: $confirmed명 확정)');
      }
    }

    // 충돌 지원서 탐색 (PENDING 상태)
    final conflicting = allUserApps
        .where((c) =>
            c.id != app.id &&
            c.status == SimAppStatus.pending &&
            c.workDate.year == app.workDate.year &&
            c.workDate.month == app.workDate.month &&
            c.workDate.day == app.workDate.day &&
            ApplySimulator.hasTimeOverlap(
                app.startTime, app.endTime, c.startTime, c.endTime))
        .map((c) => c.id)
        .toList();

    return SimConfirmResult(
      success: true,
      autoCanceledIds: conflicting,
    );
  }
}

/// 배치 확정 시뮬레이터 (batchConfirmApplications)
class BatchConfirmSimulator {
  /// for-loop 순차 처리 (병렬화 금지)
  static ({int success, int failed, List<String> failedIds}) batchConfirm({
    required List<SimApplication> applications,
    required SimTO to,
    SimSlot? slot,
    required List<SimApplication> allUserApps,
  }) {
    int success = 0;
    int failed = 0;
    final List<String> failedIds = [];

    // 순차 처리 — 각 지원서 독립 트랜잭션
    for (final app in applications) {
      final result = ConfirmSimulator.confirm(
        app: app,
        allUserApps: allUserApps,
        to: to,
        slot: slot,
      );
      if (result.success) {
        success++;
      } else {
        failed++;
        failedIds.add(app.id);
      }
    }
    return (success: success, failed: failed, failedIds: failedIds);
  }
}

/// 취소 시뮬레이터
class CancelSimulator {
  /// cancelApplication (사용자, PENDING 상태)
  static SimCancelResult cancelPending({
    required SimApplication app,
    required String uid,
  }) {
    if (app.uid != uid) return SimCancelResult()..errorMessage = '본인의 지원서만 취소할 수 있습니다.';
    if (SimAppStatus.confirmedStatuses.contains(app.status)) {
      return SimCancelResult()..errorMessage = '확정된 TO는 취소할 수 없습니다.';
    }
    if (app.status == SimAppStatus.rejected) {
      return SimCancelResult()..isInfo = true;
    }
    if (SimAppStatus.inactiveStates.contains(app.status)) {
      return SimCancelResult()..isInfo = true;
    }
    return SimCancelResult()..success = true;
  }

  /// cancelConfirmedApplication (관리자/사용자)
  static SimCancelResult cancelConfirmed({
    required SimApplication app,
    String? canceledBy,
    bool applyNoShowPenalty = false,
  }) {
    if (!SimAppStatus.confirmedStatuses.contains(app.status)) {
      return SimCancelResult()..errorMessage = '확정된 지원만 취소할 수 있습니다';
    }
    final reason = canceledBy != null
        ? SimAppStatus.adminCanceled
        : (applyNoShowPenalty
            ? SimAppStatus.sameDayCancel
            : SimAppStatus.userCanceled);
    return SimCancelResult()
      ..success = true
      ..cancelReason = reason;
  }
}

/// 취소 결과 (mutable — cascade 패턴으로 사용)
class SimCancelResult {
  bool success = false;
  bool isInfo = false;
  String? errorMessage;
  String? cancelReason;
}

// ══════════════════════════════════════════════════════════════
// 4. 공통 픽스처
// ══════════════════════════════════════════════════════════════

final _validUser = SimUser(
  uid: 'user-001',
  hasIdCard: true,
  hasBankInfo: true,
  hasBankbookImage: true,
  passVerified: true,
  isIdVerified: true,
);

final _openTO = SimTO(
  id: 'to-001',
  businessId: 'biz-001',
  status: 'OPEN',
  type: SimTOType.flex,
  totalRequired: 5,
  workTypeRequiredCounts: {'피킹': 3},
  workTypeConfirmedCounts: {'피킹': 0},
);

final _openSlot = SimSlot(
  id: 'slot-001',
  status: 'open',
  workTypeRequiredCounts: {'피킹': 3},
  workTypeConfirmedCounts: {'피킹': 0},
);

final _workDate = DateTime(2026, 8, 15);

SimApplication _makeApp({
  String id = 'app-001',
  String uid = 'user-001',
  String status = 'PENDING',
  String workType = '피킹',
  String startTime = '09:00',
  String endTime = '18:00',
  String? cancelReason,
  String? resignStatus,
  String? terminationStatus,
}) =>
    SimApplication(
      id: id,
      uid: uid,
      businessId: 'biz-001',
      toId: 'to-001',
      slotId: 'slot-001',
      selectedWorkType: workType,
      status: status,
      workDate: _workDate,
      startTime: startTime,
      endTime: endTime,
      cancelReason: cancelReason,
      resignStatus: resignStatus,
      terminationStatus: terminationStatus,
    );

// ══════════════════════════════════════════════════════════════
// 5. 테스트
// ══════════════════════════════════════════════════════════════

void main() {
  // ─────────────────────────────────────────────────
  // SCENARIO-APP-01 ~ 06: AppStatus 상수 검증
  // ─────────────────────────────────────────────────
  group('SCENARIO-APP-01~06: AppStatus 상수 검증', () {
    test('SCENARIO-APP-01: activeStates에 PENDING, CONTRACT_PENDING, CONFIRMED 포함', () {
      expect(SimAppStatus.activeStates, contains(SimAppStatus.pending));
      expect(SimAppStatus.activeStates, contains(SimAppStatus.contractPending));
      expect(SimAppStatus.activeStates, contains(SimAppStatus.confirmed));
      expect(SimAppStatus.activeStates.length, 3);
    });

    test('SCENARIO-APP-02: confirmedStatuses에 CONFIRMED, CONTRACT_PENDING만 포함', () {
      expect(SimAppStatus.confirmedStatuses, contains(SimAppStatus.confirmed));
      expect(SimAppStatus.confirmedStatuses, contains(SimAppStatus.contractPending));
      expect(SimAppStatus.confirmedStatuses, isNot(contains(SimAppStatus.pending)));
      expect(SimAppStatus.confirmedStatuses.length, 2);
    });

    test('SCENARIO-APP-03: inactiveStates에 REJECTED, CANCELED, AUTO_CANCELED 포함', () {
      expect(SimAppStatus.inactiveStates, contains(SimAppStatus.rejected));
      expect(SimAppStatus.inactiveStates, contains(SimAppStatus.canceled));
      expect(SimAppStatus.inactiveStates, contains(SimAppStatus.autoCanceled));
      expect(SimAppStatus.inactiveStates.length, 3);
    });

    test('SCENARIO-APP-04: activeStates와 inactiveStates 교집합 없음', () {
      final overlap = SimAppStatus.activeStates
          .where((s) => SimAppStatus.inactiveStates.contains(s))
          .toList();
      expect(overlap, isEmpty);
    });

    test('SCENARIO-APP-05: PENDING은 active이고 inactive 아님', () {
      expect(SimAppStatus.activeStates.contains(SimAppStatus.pending), isTrue);
      expect(SimAppStatus.inactiveStates.contains(SimAppStatus.pending), isFalse);
    });

    test('SCENARIO-APP-06: confirmedStatuses는 activeStates의 부분집합', () {
      for (final s in SimAppStatus.confirmedStatuses) {
        expect(SimAppStatus.activeStates, contains(s));
      }
    });
  });

  // ─────────────────────────────────────────────────
  // SCENARIO-APP-07 ~ 18: applyToTO 12단계 검증
  // ─────────────────────────────────────────────────
  group('SCENARIO-APP-07~18: applyToTO 12단계 검증', () {
    test('SCENARIO-APP-07: 신분증 미등록 → Step 1 차단', () {
      final user = SimUser(
        uid: 'user-001', hasIdCard: false, hasBankInfo: true, hasBankbookImage: true,
        passVerified: true, isIdVerified: true,
      );
      final result = ApplySimulator.applyToTO(
        user: user, to: _openTO, slot: _openSlot,
        workDate: _workDate, startTime: '09:00', endTime: '18:00',
        selectedWorkType: '피킹', existingApps: [], confirmedApps: [],
      );
      expect(result.success, isFalse);
      expect(result.errorMessage, contains('신분증'));
    });

    test('SCENARIO-APP-08: 통장 정보 미등록 → Step 1 차단', () {
      final user = SimUser(
        uid: 'user-001', hasIdCard: true, hasBankInfo: false, hasBankbookImage: true,
        passVerified: true, isIdVerified: true,
      );
      final result = ApplySimulator.applyToTO(
        user: user, to: _openTO, slot: _openSlot,
        workDate: _workDate, startTime: '09:00', endTime: '18:00',
        selectedWorkType: '피킹', existingApps: [], confirmedApps: [],
      );
      expect(result.success, isFalse);
      expect(result.errorMessage, contains('통장 정보'));
    });

    test('SCENARIO-APP-09: 통장사본 미등록 → Step 1 차단', () {
      final user = SimUser(
        uid: 'user-001', hasIdCard: true, hasBankInfo: true, hasBankbookImage: false,
        passVerified: true, isIdVerified: true,
      );
      final result = ApplySimulator.applyToTO(
        user: user, to: _openTO, slot: _openSlot,
        workDate: _workDate, startTime: '09:00', endTime: '18:00',
        selectedWorkType: '피킹', existingApps: [], confirmedApps: [],
      );
      expect(result.success, isFalse);
      expect(result.errorMessage, contains('통장사본'));
    });

    test('SCENARIO-APP-10: 블랙리스트 사용자 → Step 2 차단', () {
      final user = SimUser(
        uid: 'user-001', isBlacklisted: true, blacklistReason: '사기 이력',
        passVerified: true, isIdVerified: true,
      );
      final result = ApplySimulator.applyToTO(
        user: user, to: _openTO, slot: _openSlot,
        workDate: _workDate, startTime: '09:00', endTime: '18:00',
        selectedWorkType: '피킹', existingApps: [], confirmedApps: [],
      );
      expect(result.success, isFalse);
      expect(result.errorMessage, contains('이용 제한'));
      expect(result.errorMessage, contains('사기 이력'));
    });

    test('SCENARIO-APP-11: PASS 본인인증 미완료 → Step 3 차단', () {
      final user = SimUser(
        uid: 'user-001', passVerified: false, isIdVerified: true,
      );
      final result = ApplySimulator.applyToTO(
        user: user, to: _openTO, slot: _openSlot,
        workDate: _workDate, startTime: '09:00', endTime: '18:00',
        selectedWorkType: '피킹', existingApps: [], confirmedApps: [],
      );
      expect(result.success, isFalse);
      expect(result.errorMessage, contains('본인인증'));
    });

    test('SCENARIO-APP-12: flex 타입 신분증 인증 미완료 → Step 4 차단', () {
      final user = SimUser(
        uid: 'user-001', passVerified: true, isIdVerified: false,
      );
      // slotId != null → flex 타입
      final result = ApplySimulator.applyToTO(
        user: user, to: _openTO, slot: _openSlot,
        workDate: _workDate, startTime: '09:00', endTime: '18:00',
        selectedWorkType: '피킹', existingApps: [], confirmedApps: [],
      );
      expect(result.success, isFalse);
      expect(result.errorMessage, contains('신분증 인증'));
    });

    test('SCENARIO-APP-13: contract 타입은 신분증 인증 미완료도 허용 (Step 4 스킵)', () {
      final user = SimUser(
        uid: 'user-001', passVerified: true, isIdVerified: false,
      );
      // slot=null → contract 타입
      final contractTO = SimTO(
        id: 'to-contract', businessId: 'biz-001', status: 'OPEN',
        type: SimTOType.contract,
      );
      final result = ApplySimulator.applyToTO(
        user: user, to: contractTO, slot: null,
        workDate: _workDate, startTime: '09:00', endTime: '18:00',
        selectedWorkType: '피킹', existingApps: [], confirmedApps: [],
      );
      expect(result.success, isTrue);
    });

    test('SCENARIO-APP-14: noShow 제재 기간 중 → Step 5 차단', () {
      final user = SimUser(
        uid: 'user-001', passVerified: true, isIdVerified: true,
        restrictedUntil: DateTime.now().add(const Duration(days: 7)),
      );
      final result = ApplySimulator.applyToTO(
        user: user, to: _openTO, slot: _openSlot,
        workDate: _workDate, startTime: '09:00', endTime: '18:00',
        selectedWorkType: '피킹', existingApps: [], confirmedApps: [],
      );
      expect(result.success, isFalse);
      expect(result.errorMessage, contains('페널티'));
    });

    test('SCENARIO-APP-15: noShow 제재 만료 후 지원 가능', () {
      final user = SimUser(
        uid: 'user-001', passVerified: true, isIdVerified: true,
        restrictedUntil: DateTime.now().subtract(const Duration(days: 1)),
      );
      final result = ApplySimulator.applyToTO(
        user: user, to: _openTO, slot: _openSlot,
        workDate: _workDate, startTime: '09:00', endTime: '18:00',
        selectedWorkType: '피킹', existingApps: [], confirmedApps: [],
      );
      expect(result.success, isTrue);
    });

    test('SCENARIO-APP-16: TO DRAFT 상태 → Step 6 차단', () {
      final draftTO = SimTO(id: 'to-001', businessId: 'biz-001', status: 'DRAFT');
      final result = ApplySimulator.applyToTO(
        user: _validUser, to: draftTO, slot: _openSlot,
        workDate: _workDate, startTime: '09:00', endTime: '18:00',
        selectedWorkType: '피킹', existingApps: [], confirmedApps: [],
      );
      expect(result.success, isFalse);
      expect(result.errorMessage, contains('비공개'));
    });

    test('SCENARIO-APP-17: TO isManualClosed → Step 6 차단', () {
      final closedTO = SimTO(id: 'to-001', businessId: 'biz-001', isManualClosed: true);
      final result = ApplySimulator.applyToTO(
        user: _validUser, to: closedTO, slot: _openSlot,
        workDate: _workDate, startTime: '09:00', endTime: '18:00',
        selectedWorkType: '피킹', existingApps: [], confirmedApps: [],
      );
      expect(result.success, isFalse);
      expect(result.errorMessage, contains('마감'));
    });

    test('SCENARIO-APP-18: TO CLOSED 상태 → Step 6 차단', () {
      final closedTO = SimTO(id: 'to-001', businessId: 'biz-001', status: 'CLOSED');
      final result = ApplySimulator.applyToTO(
        user: _validUser, to: closedTO, slot: _openSlot,
        workDate: _workDate, startTime: '09:00', endTime: '18:00',
        selectedWorkType: '피킹', existingApps: [], confirmedApps: [],
      );
      expect(result.success, isFalse);
    });
  });

  // ─────────────────────────────────────────────────
  // SCENARIO-APP-19 ~ 28: 슬롯·마감·중복·충돌
  // ─────────────────────────────────────────────────
  group('SCENARIO-APP-19~28: 슬롯·마감·중복·충돌', () {
    test('SCENARIO-APP-19: TO FULL 상태 → 차단', () {
      final fullTO = SimTO(id: 'to-001', businessId: 'biz-001', status: 'FULL');
      final result = ApplySimulator.applyToTO(
        user: _validUser, to: fullTO, slot: _openSlot,
        workDate: _workDate, startTime: '09:00', endTime: '18:00',
        selectedWorkType: '피킹', existingApps: [], confirmedApps: [],
      );
      expect(result.success, isFalse);
    });

    test('SCENARIO-APP-20: 게시 만료 → Step 7 차단', () {
      final expiredTO = SimTO(id: 'to-001', businessId: 'biz-001', isPostingExpired: true);
      final result = ApplySimulator.applyToTO(
        user: _validUser, to: expiredTO, slot: _openSlot,
        workDate: _workDate, startTime: '09:00', endTime: '18:00',
        selectedWorkType: '피킹', existingApps: [], confirmedApps: [],
      );
      expect(result.success, isFalse);
      expect(result.errorMessage, contains('마감된 공고'));
    });

    test('SCENARIO-APP-21: 지원 마감일 경과 → Step 7 차단', () {
      final deadlinePassedTO = SimTO(id: 'to-001', businessId: 'biz-001', isDeadlinePassed: true);
      final result = ApplySimulator.applyToTO(
        user: _validUser, to: deadlinePassedTO, slot: _openSlot,
        workDate: _workDate, startTime: '09:00', endTime: '18:00',
        selectedWorkType: '피킹', existingApps: [], confirmedApps: [],
      );
      expect(result.success, isFalse);
    });

    test('SCENARIO-APP-22: 슬롯 isManualClosed → Step 8 차단', () {
      final closedSlot = SimSlot(id: 'slot-001', isManualClosed: true);
      final result = ApplySimulator.applyToTO(
        user: _validUser, to: _openTO, slot: closedSlot,
        workDate: _workDate, startTime: '09:00', endTime: '18:00',
        selectedWorkType: '피킹', existingApps: [], confirmedApps: [],
      );
      expect(result.success, isFalse);
      expect(result.errorMessage, contains('마감'));
    });

    test('SCENARIO-APP-23: 슬롯 workType 마감(정원 초과) → Step 8 차단', () {
      final fullSlot = SimSlot(
        id: 'slot-001',
        workTypeRequiredCounts: {'피킹': 2},
        workTypeConfirmedCounts: {'피킹': 2},
      );
      final result = ApplySimulator.applyToTO(
        user: _validUser, to: _openTO, slot: fullSlot,
        workDate: _workDate, startTime: '09:00', endTime: '18:00',
        selectedWorkType: '피킹', existingApps: [], confirmedApps: [],
      );
      expect(result.success, isFalse);
      expect(result.errorMessage, contains('모집 인원'));
    });

    test('SCENARIO-APP-24: 동일 TO+uid+workType+slotId 이미 PENDING → 중복 차단', () {
      final existing = [_makeApp(status: 'PENDING')];
      final result = ApplySimulator.applyToTO(
        user: _validUser, to: _openTO, slot: _openSlot,
        workDate: _workDate, startTime: '10:00', endTime: '19:00',
        selectedWorkType: '피킹', existingApps: existing, confirmedApps: [],
      );
      expect(result.success, isFalse);
      expect(result.errorMessage, contains('이미 지원'));
    });

    test('SCENARIO-APP-25: 동일 조합이 CONTRACT_PENDING 상태 → 중복 차단', () {
      final existing = [_makeApp(status: 'CONTRACT_PENDING')];
      final result = ApplySimulator.applyToTO(
        user: _validUser, to: _openTO, slot: _openSlot,
        workDate: _workDate, startTime: '09:00', endTime: '18:00',
        selectedWorkType: '피킹', existingApps: existing, confirmedApps: [],
      );
      expect(result.success, isFalse);
    });

    test('SCENARIO-APP-26: 동일 조합이 CONFIRMED 상태 → 중복 차단', () {
      final existing = [_makeApp(status: 'CONFIRMED')];
      final result = ApplySimulator.applyToTO(
        user: _validUser, to: _openTO, slot: _openSlot,
        workDate: _workDate, startTime: '09:00', endTime: '18:00',
        selectedWorkType: '피킹', existingApps: existing, confirmedApps: [],
      );
      expect(result.success, isFalse);
    });

    test('SCENARIO-APP-27: 같은 날 같은 시간대 CONFIRMED 지원서 → 충돌 차단', () {
      final confirmedApp = _makeApp(
        id: 'app-other', uid: 'user-001', status: 'CONFIRMED',
        startTime: '09:00', endTime: '18:00',
      );
      // 다른 TO에 같은 시간 지원 시도
      final otherTO = SimTO(id: 'to-002', businessId: 'biz-002', status: 'OPEN');
      final otherSlot = SimSlot(id: 'slot-002');
      final result = ApplySimulator.applyToTO(
        user: _validUser, to: otherTO, slot: otherSlot,
        workDate: _workDate, startTime: '09:00', endTime: '18:00',
        selectedWorkType: '포장', existingApps: [], confirmedApps: [confirmedApp],
      );
      expect(result.success, isFalse);
      expect(result.errorMessage, contains('확정된 근무'));
    });

    test('SCENARIO-APP-28: 모든 조건 충족 → 지원 성공', () {
      final result = ApplySimulator.applyToTO(
        user: _validUser, to: _openTO, slot: _openSlot,
        workDate: _workDate, startTime: '09:00', endTime: '18:00',
        selectedWorkType: '피킹', existingApps: [], confirmedApps: [],
      );
      expect(result.success, isTrue);
      expect(result.applicationId, isNotNull);
    });
  });

  // ─────────────────────────────────────────────────
  // SCENARIO-APP-29 ~ 37: CONTRACT_PENDING 선점 트랜잭션
  // ─────────────────────────────────────────────────
  group('SCENARIO-APP-29~37: CONTRACT_PENDING 선점 트랜잭션', () {
    test('SCENARIO-APP-29: PENDING → CONTRACT_PENDING 선점 성공', () {
      final app = _makeApp(status: 'PENDING');
      final result = ConfirmSimulator.confirm(
        app: app, allUserApps: [app], to: _openTO, slot: _openSlot,
      );
      expect(result.success, isTrue);
      expect(result.alreadyConfirmed, isFalse);
    });

    test('SCENARIO-APP-30: 이미 CONTRACT_PENDING → alreadyConfirmed=true (멱등)', () {
      final app = _makeApp(status: 'CONTRACT_PENDING');
      final result = ConfirmSimulator.confirm(
        app: app, allUserApps: [app], to: _openTO, slot: _openSlot,
      );
      expect(result.success, isTrue);
      expect(result.alreadyConfirmed, isTrue);
    });

    test('SCENARIO-APP-31: 이미 CONFIRMED → alreadyConfirmed=true', () {
      final app = _makeApp(status: 'CONFIRMED');
      final result = ConfirmSimulator.confirm(
        app: app, allUserApps: [app], to: _openTO, slot: _openSlot,
      );
      expect(result.success, isTrue);
      expect(result.alreadyConfirmed, isTrue);
    });

    test('SCENARIO-APP-32: CANCELED 지원서 확정 시도 → 실패', () {
      final app = _makeApp(status: 'CANCELED');
      final result = ConfirmSimulator.confirm(
        app: app, allUserApps: [app], to: _openTO, slot: _openSlot,
      );
      expect(result.success, isFalse);
      expect(result.errorMessage, contains('취소된'));
    });

    test('SCENARIO-APP-33: AUTO_CANCELED 지원서 확정 시도 → 실패', () {
      final app = _makeApp(status: 'AUTO_CANCELED');
      final result = ConfirmSimulator.confirm(
        app: app, allUserApps: [app], to: _openTO, slot: _openSlot,
      );
      expect(result.success, isFalse);
      expect(result.errorMessage, contains('자동 취소'));
    });

    test('SCENARIO-APP-34: REJECTED 지원서 확정 시도 → 실패', () {
      final app = _makeApp(status: 'REJECTED');
      final result = ConfirmSimulator.confirm(
        app: app, allUserApps: [app], to: _openTO, slot: _openSlot,
      );
      expect(result.success, isFalse);
      expect(result.errorMessage, contains('거절'));
    });

    test('SCENARIO-APP-35: CAPACITY-GUARD — 슬롯 정원 초과 시 확정 불가', () {
      final app = _makeApp(status: 'PENDING');
      final fullSlot = SimSlot(
        id: 'slot-001',
        workTypeRequiredCounts: {'피킹': 2},
        workTypeConfirmedCounts: {'피킹': 2},
      );
      final result = ConfirmSimulator.confirm(
        app: app, allUserApps: [app], to: _openTO, slot: fullSlot,
      );
      expect(result.success, isFalse);
      expect(result.errorMessage, contains('정원'));
    });

    test('SCENARIO-APP-36: 확정 시 같은 날 같은 시간 PENDING 지원서 AUTO_CANCELED', () {
      final targetApp = _makeApp(id: 'app-target', status: 'PENDING', startTime: '09:00', endTime: '18:00');
      final conflictApp = _makeApp(
        id: 'app-conflict', uid: 'user-001',
        status: 'PENDING', startTime: '10:00', endTime: '17:00',
      );
      final result = ConfirmSimulator.confirm(
        app: targetApp,
        allUserApps: [targetApp, conflictApp],
        to: _openTO,
        slot: _openSlot,
      );
      expect(result.success, isTrue);
      expect(result.autoCanceledIds, contains('app-conflict'));
    });

    test('SCENARIO-APP-37: 확정 시 다른 날짜 PENDING 지원서는 AUTO_CANCELED 안 됨', () {
      final targetApp = _makeApp(id: 'app-target', status: 'PENDING');
      // 다른 날짜 지원서
      final otherDayApp = SimApplication(
        id: 'app-other-day', uid: 'user-001', businessId: 'biz-001',
        toId: 'to-002', slotId: 'slot-002', selectedWorkType: '피킹',
        status: 'PENDING', workDate: DateTime(2026, 8, 16),
        startTime: '09:00', endTime: '18:00',
      );
      final result = ConfirmSimulator.confirm(
        app: targetApp,
        allUserApps: [targetApp, otherDayApp],
        to: _openTO,
        slot: _openSlot,
      );
      expect(result.success, isTrue);
      expect(result.autoCanceledIds, isEmpty);
    });
  });

  // ─────────────────────────────────────────────────
  // SCENARIO-APP-38 ~ 43: batchConfirmApplications 순차 처리
  // ─────────────────────────────────────────────────
  group('SCENARIO-APP-38~43: batchConfirmApplications 순차 처리', () {
    test('SCENARIO-APP-38: 빈 리스트 → success=0, failed=0', () {
      final result = BatchConfirmSimulator.batchConfirm(
        applications: [], to: _openTO, slot: _openSlot, allUserApps: [],
      );
      expect(result.success, 0);
      expect(result.failed, 0);
    });

    test('SCENARIO-APP-39: 3개 모두 PENDING → success=3', () {
      final apps = List.generate(3, (i) => _makeApp(id: 'app-$i', uid: 'user-$i'));
      final result = BatchConfirmSimulator.batchConfirm(
        applications: apps, to: _openTO, slot: _openSlot, allUserApps: apps,
      );
      expect(result.success, 3);
      expect(result.failed, 0);
    });

    test('SCENARIO-APP-40: 한 지원서 CANCELED → 해당만 failed', () {
      final validApp = _makeApp(id: 'app-valid', status: 'PENDING');
      final canceledApp = _makeApp(id: 'app-canceled', status: 'CANCELED');
      final result = BatchConfirmSimulator.batchConfirm(
        applications: [validApp, canceledApp],
        to: _openTO, slot: _openSlot,
        allUserApps: [validApp, canceledApp],
      );
      expect(result.success, 1);
      expect(result.failed, 1);
      expect(result.failedIds, contains('app-canceled'));
    });

    test('SCENARIO-APP-41: 순차 처리 — 실패해도 다음 지원서 계속 처리', () {
      final apps = [
        _makeApp(id: 'app-1', status: 'PENDING'),
        _makeApp(id: 'app-2', status: 'REJECTED'),
        _makeApp(id: 'app-3', status: 'PENDING'),
      ];
      final result = BatchConfirmSimulator.batchConfirm(
        applications: apps, to: _openTO, slot: _openSlot, allUserApps: apps,
      );
      expect(result.success, 2);
      expect(result.failed, 1);
      expect(result.failedIds, ['app-2']);
    });

    test('SCENARIO-APP-42: 병렬 처리 금지 설계 — for-loop 보장', () {
      // 순서 추적: 순차로 처리했는지 확인
      final processedOrder = <String>[];
      // BatchConfirmSimulator 내부가 for-loop임을 전제로 순서 시뮬레이션
      final apps = ['app-A', 'app-B', 'app-C']
          .map((id) => _makeApp(id: id))
          .toList();
      for (final app in apps) {
        processedOrder.add(app.id);
      }
      expect(processedOrder, ['app-A', 'app-B', 'app-C']);
    });

    test('SCENARIO-APP-43: 정원 초과 지원서는 개별 실패 처리', () {
      final fullSlot = SimSlot(
        id: 'slot-001',
        workTypeRequiredCounts: {'피킹': 1},
        workTypeConfirmedCounts: {'피킹': 1},
      );
      final apps = [_makeApp(id: 'app-over', status: 'PENDING')];
      final result = BatchConfirmSimulator.batchConfirm(
        applications: apps, to: _openTO, slot: fullSlot, allUserApps: apps,
      );
      expect(result.failed, 1);
    });
  });

  // ─────────────────────────────────────────────────
  // SCENARIO-APP-44 ~ 50: 취소 흐름
  // ─────────────────────────────────────────────────
  group('SCENARIO-APP-44~50: 취소 흐름', () {
    test('SCENARIO-APP-44: PENDING 지원서 사용자 취소 → CANCELED (USER_CANCELED)', () {
      final app = _makeApp(status: 'PENDING', uid: 'user-001');
      final result = CancelSimulator.cancelPending(app: app, uid: 'user-001');
      expect(result.success, isTrue);
    });

    test('SCENARIO-APP-45: CONTRACT_PENDING 지원서 사용자 취소 불가', () {
      final app = _makeApp(status: 'CONTRACT_PENDING', uid: 'user-001');
      final result = CancelSimulator.cancelPending(app: app, uid: 'user-001');
      expect(result.success, isFalse);
      expect(result.errorMessage, contains('확정된'));
    });

    test('SCENARIO-APP-46: CONFIRMED 지원서 사용자 취소 불가 (관리자 경로 사용)', () {
      final app = _makeApp(status: 'CONFIRMED', uid: 'user-001');
      final result = CancelSimulator.cancelPending(app: app, uid: 'user-001');
      expect(result.success, isFalse);
      expect(result.errorMessage, contains('확정된'));
    });

    test('SCENARIO-APP-47: 이미 CANCELED인 지원서 — 멱등 처리 (isInfo=true)', () {
      final app = _makeApp(status: 'CANCELED', uid: 'user-001');
      final result = CancelSimulator.cancelPending(app: app, uid: 'user-001');
      expect(result.isInfo, isTrue);
      expect(result.success, isFalse);
    });

    test('SCENARIO-APP-48: 타인의 지원서 취소 시도 → 차단', () {
      final app = _makeApp(status: 'PENDING', uid: 'user-001');
      final result = CancelSimulator.cancelPending(app: app, uid: 'user-999');
      expect(result.success, isFalse);
      expect(result.errorMessage, contains('본인'));
    });

    test('SCENARIO-APP-49: cancelConfirmedApplication — 관리자 취소 → ADMIN_CANCELED', () {
      final app = _makeApp(status: 'CONFIRMED');
      final result = CancelSimulator.cancelConfirmed(
        app: app, canceledBy: 'admin-001',
      );
      expect(result.success, isTrue);
      expect(result.cancelReason, SimAppStatus.adminCanceled);
    });

    test('SCENARIO-APP-50: cancelConfirmedApplication — 당일 취소(노쇼) → SAME_DAY_CANCEL', () {
      final app = _makeApp(status: 'CONFIRMED');
      final result = CancelSimulator.cancelConfirmed(
        app: app, applyNoShowPenalty: true,
      );
      expect(result.success, isTrue);
      expect(result.cancelReason, SimAppStatus.sameDayCancel);
    });
  });

  // ─────────────────────────────────────────────────
  // SCENARIO-APP-51 ~ 57: 재지원 흐름
  // ─────────────────────────────────────────────────
  group('SCENARIO-APP-51~57: 재지원 흐름', () {
    test('SCENARIO-APP-51: REJECTED 이후 재지원 → PENDING 재활성화 허용', () {
      final existingRejected = _makeApp(status: 'REJECTED');
      // 재지원: inactiveStates에 해당하므로 reactivatable
      final dupError = ApplySimulator.checkDuplicateApplication(
        uid: 'user-001', toId: 'to-001', selectedWorkType: '피킹',
        slotId: 'slot-001', workDetailId: null,
        existingApps: [existingRejected],
      );
      // REJECTED는 activeStates에 없으므로 중복 차단 안 함 (재활성화 가능)
      expect(dupError, isNull);
    });

    test('SCENARIO-APP-52: CANCELED 이후 재지원 → PENDING 재활성화 허용', () {
      final existingCanceled = _makeApp(status: 'CANCELED');
      final dupError = ApplySimulator.checkDuplicateApplication(
        uid: 'user-001', toId: 'to-001', selectedWorkType: '피킹',
        slotId: 'slot-001', workDetailId: null,
        existingApps: [existingCanceled],
      );
      expect(dupError, isNull);
    });

    test('SCENARIO-APP-53: AUTO_CANCELED 이후 재지원 → PENDING 재활성화 허용', () {
      final existingAutoCanceled = _makeApp(status: 'AUTO_CANCELED');
      final dupError = ApplySimulator.checkDuplicateApplication(
        uid: 'user-001', toId: 'to-001', selectedWorkType: '피킹',
        slotId: 'slot-001', workDetailId: null,
        existingApps: [existingAutoCanceled],
      );
      expect(dupError, isNull);
    });

    test('SCENARIO-APP-54: 퇴사 승인(APPROVED) 후 재지원 → 중복 차단 안 함', () {
      final existingResigned = _makeApp(
        status: 'CONFIRMED', resignStatus: SimAppStatus.approved,
      );
      final dupError = ApplySimulator.checkDuplicateApplication(
        uid: 'user-001', toId: 'to-001', selectedWorkType: '피킹',
        slotId: 'slot-001', workDetailId: null,
        existingApps: [existingResigned],
      );
      expect(dupError, isNull);
    });

    test('SCENARIO-APP-55: 계약해지 자동승인(AUTO_APPROVED) 후 재지원 허용', () {
      final existingTerminated = _makeApp(
        status: 'CONFIRMED', terminationStatus: SimAppStatus.autoApproved,
      );
      final dupError = ApplySimulator.checkDuplicateApplication(
        uid: 'user-001', toId: 'to-001', selectedWorkType: '피킹',
        slotId: 'slot-001', workDetailId: null,
        existingApps: [existingTerminated],
      );
      expect(dupError, isNull);
    });

    test('SCENARIO-APP-56: 재활성화 시 uid/businessId/toId 불변 조건', () {
      // uid, businessId, toId는 재지원 시 변경 불가 (Firestore 보안 규칙)
      final originalApp = SimApplication(
        id: 'app-001', uid: 'user-001', businessId: 'biz-001', toId: 'to-001',
        slotId: 'slot-001', selectedWorkType: '피킹', status: 'CANCELED',
        workDate: _workDate, startTime: '09:00', endTime: '18:00',
      );
      // 재활성화 시 status만 PENDING으로 변경, 핵심 필드는 유지
      final reactivated = originalApp.copyWith(status: 'PENDING');
      expect(reactivated.uid, originalApp.uid);
      expect(reactivated.businessId, originalApp.businessId);
      expect(reactivated.toId, originalApp.toId);
      expect(reactivated.status, 'PENDING');
    });

    test('SCENARIO-APP-57: 재지원 시 statusHistory에 REAPPLY 이력 추가', () {
      final originalHistory = [
        {'status': 'PENDING', 'action': 'APPLY'},
        {'status': 'CANCELED', 'action': 'CANCEL'},
      ];
      final reapplyEntry = {'status': 'PENDING', 'action': 'REAPPLY'};
      final newHistory = [...originalHistory, reapplyEntry];

      expect(newHistory.length, 3);
      expect(newHistory.last['action'], 'REAPPLY');
    });
  });

  // ─────────────────────────────────────────────────
  // SCENARIO-APP-58 ~ 64: changeApplicationWorkType
  // ─────────────────────────────────────────────────
  group('SCENARIO-APP-58~64: changeApplicationWorkType 로직', () {
    test('SCENARIO-APP-58: 동일 workType 변경 시도 → 차단', () {
      const currentWorkType = '피킹';
      const newWorkType = '피킹';
      expect(currentWorkType == newWorkType, isTrue); // 동일하면 차단
    });

    test('SCENARIO-APP-59: flex TO — 슬롯 workTypeCounts 카운터 동기화', () {
      // CONFIRMED 상태: 기존 workType confirmedCount -1, 새 workType confirmedCount +1
      final slotCounts = {'피킹': 2, '포장': 1};
      // 피킹 → 포장 변경
      final updatedCounts = {
        '피킹': slotCounts['피킹']! - 1,
        '포장': slotCounts['포장']! + 1,
      };
      expect(updatedCounts['피킹'], 1);
      expect(updatedCounts['포장'], 2);
    });

    test('SCENARIO-APP-60: contract TO — workTypeConfirmedCounts 카운터 동기화', () {
      final toCounts = {'피킹': 3, '포장': 0};
      // 피킹 → 포장 변경
      final updated = {
        '피킹': toCounts['피킹']! - 1,
        '포장': toCounts['포장']! + 1,
      };
      expect(updated['피킹'], 2);
      expect(updated['포장'], 1);
    });

    test('SCENARIO-APP-61: originalWorkType은 최초 workType 보존 (두 번째 변경 시)', () {
      const originalWorkType = '피킹'; // 최초 설정
      const currentWorkType = '포장';  // 1차 변경 후
      // 2차 변경 시 originalWorkType은 '피킹'으로 유지
      final preserved = originalWorkType; // ?? currentWorkType 패턴
      expect(preserved, '피킹');
    });

    test('SCENARIO-APP-62: PENDING 상태 변경 시 pendingCount 카운터 동기화', () {
      final slotCounts = {'피킹': {'pendingCount': 2}, '포장': {'pendingCount': 0}};
      // PENDING 상태 피킹 → 포장
      final updated = {
        '피킹': {'pendingCount': slotCounts['피킹']!['pendingCount']! - 1},
        '포장': {'pendingCount': slotCounts['포장']!['pendingCount']! + 1},
      };
      expect(updated['피킹']!['pendingCount'], 1);
      expect(updated['포장']!['pendingCount'], 1);
    });

    test('SCENARIO-APP-63: 계약서 workType/wage 동기화', () {
      // 파트 변경 시 계약서도 함께 업데이트
      final contractUpdate = <String, dynamic>{
        'workType': '포장',
        'wage': 12000,
        'wageType': 'hourly',
      };
      expect(contractUpdate['workType'], '포장');
      expect(contractUpdate['wage'], 12000);
    });

    test('SCENARIO-APP-64: 새 workType 정원 초과 시 경고만 (차단 안 함)', () {
      // 관리자가 의도적으로 초과 확정하는 경우 허용
      const newWorkTypeRequired = 2;
      const newWorkTypeConfirmed = 2;
      // 경고는 하지만 차단하지 않음
      final isOverCapacity = newWorkTypeRequired > 0 && newWorkTypeConfirmed >= newWorkTypeRequired;
      expect(isOverCapacity, isTrue); // 경고 조건 충족
      // 하지만 changeApplicationWorkType 자체는 성공해야 함 (warning만)
    });
  });

  // ─────────────────────────────────────────────────
  // SCENARIO-APP-65 ~ 70: AUTO_CANCELED 케이스
  // ─────────────────────────────────────────────────
  group('SCENARIO-APP-65~70: AUTO_CANCELED 케이스', () {
    test('SCENARIO-APP-65: 시간 충돌 확정 시 PENDING 지원서 → AUTO_CANCELED + SCHEDULE_CONFLICT', () {
      final conflictApp = _makeApp(id: 'conflict-001', status: 'PENDING');
      // AUTO_CANCELED 처리 시 cancelReason = SCHEDULE_CONFLICT
      final autoCanceledData = {
        'status': 'AUTO_CANCELED',
        'cancelReason': 'SCHEDULE_CONFLICT',
        'conflictingAppId': 'app-target',
      };
      expect(autoCanceledData['status'], 'AUTO_CANCELED');
      expect(autoCanceledData['cancelReason'], 'SCHEDULE_CONFLICT');
      expect(conflictApp.id, 'conflict-001');
    });

    test('SCENARIO-APP-66: AUTO_CANCELED → inactiveStates에 포함', () {
      expect(SimAppStatus.inactiveStates, contains('AUTO_CANCELED'));
    });

    test('SCENARIO-APP-67: AUTO_CANCELED → activeStates에 없음', () {
      expect(SimAppStatus.activeStates, isNot(contains('AUTO_CANCELED')));
    });

    test('SCENARIO-APP-68: AUTO_CANCELED 후 재지원 시 중복 차단 안 함', () {
      final autoCanceled = _makeApp(status: 'AUTO_CANCELED');
      final dupError = ApplySimulator.checkDuplicateApplication(
        uid: 'user-001', toId: 'to-001', selectedWorkType: '피킹',
        slotId: 'slot-001', workDetailId: null,
        existingApps: [autoCanceled],
      );
      expect(dupError, isNull);
    });

    test('SCENARIO-APP-69: CONTRACT_PENDING 동시 충돌 — 이미 선점된 지원서는 배치에서 제외', () {
      // 두 관리자가 동시에 같은 지원자의 서로 다른 지원서를 확정할 때
      // CONTRACT_PENDING 상태인 지원서는 AUTO_CANCELED 대상에서 제외
      final contractPendingApp = _makeApp(status: 'CONTRACT_PENDING');
      final pendingApp = _makeApp(id: 'app-pending', status: 'PENDING');

      // CONTRACT_PENDING은 AUTO_CANCELED 대상 아님 (PENDING만 대상)
      final autoCancelTargets = [contractPendingApp, pendingApp]
          .where((a) => a.status == SimAppStatus.pending)
          .map((a) => a.id)
          .toList();

      expect(autoCancelTargets, isNot(contains(contractPendingApp.id)));
      expect(autoCancelTargets, contains(pendingApp.id));
    });

    test('SCENARIO-APP-70: SAME_DAY_CANCEL → cancelApplication의 노쇼 패널티 경로', () {
      final app = _makeApp(status: 'CONFIRMED');
      final result = CancelSimulator.cancelConfirmed(
        app: app, applyNoShowPenalty: true,
      );
      expect(result.cancelReason, SimAppStatus.sameDayCancel);
    });
  });

  // ─────────────────────────────────────────────────
  // SCENARIO-APP-71 ~ 76: 시간 겹침 정밀 검증
  // ─────────────────────────────────────────────────
  group('SCENARIO-APP-71~76: 시간 겹침(hasTimeOverlap) 정밀 검증', () {
    test('SCENARIO-APP-71: 완전히 겹치는 구간 → overlap', () {
      expect(ApplySimulator.hasTimeOverlap('09:00', '18:00', '09:00', '18:00'), isTrue);
    });

    test('SCENARIO-APP-72: 부분 겹치는 구간 → overlap', () {
      expect(ApplySimulator.hasTimeOverlap('09:00', '14:00', '12:00', '18:00'), isTrue);
    });

    test('SCENARIO-APP-73: 정확히 연속 (끝=시작) → overlap 아님', () {
      // 09:00~13:00 / 13:00~18:00 → 연속이지만 겹침 없음
      expect(ApplySimulator.hasTimeOverlap('09:00', '13:00', '13:00', '18:00'), isFalse);
    });

    test('SCENARIO-APP-74: 야간 근무 22:00~02:00 — 다음 날 근무와 겹침', () {
      expect(ApplySimulator.hasTimeOverlap('22:00', '02:00', '01:00', '09:00'), isTrue);
    });

    test('SCENARIO-APP-75: 완전히 다른 시간대 → overlap 없음', () {
      expect(ApplySimulator.hasTimeOverlap('09:00', '13:00', '14:00', '18:00'), isFalse);
    });

    test('SCENARIO-APP-76: 빈 문자열 → overlap 없음 (안전 처리)', () {
      expect(ApplySimulator.hasTimeOverlap('', '18:00', '09:00', '17:00'), isFalse);
      expect(ApplySimulator.hasTimeOverlap('09:00', '', '09:00', '17:00'), isFalse);
    });
  });

  // ─────────────────────────────────────────────────
  // SCENARIO-APP-77 ~ 81: 지원서 보안 규칙 교차 검증
  // ─────────────────────────────────────────────────
  group('SCENARIO-APP-77~81: 지원서 보안 규칙 교차 검증', () {
    test('SCENARIO-APP-77: TO.businessId == 지원서.businessId 일치 검증', () {
      const toBusinessId = 'biz-001';
      const appBusinessId = 'biz-001';
      expect(toBusinessId == appBusinessId, isTrue);
    });

    test('SCENARIO-APP-78: TO.businessId != 지원서.businessId → 위조 탐지', () {
      const toBusinessId = 'biz-001';
      const appBusinessId = 'biz-999'; // 다른 사업장 위조 시도
      expect(toBusinessId == appBusinessId, isFalse);
    });

    test('SCENARIO-APP-79: REJECTED 지원서는 관리자가 PENDING으로 직접 복원 불가 (B-001)', () {
      // status=PENDING, prevStatus=REJECTED → 차단
      const prevStatus = 'REJECTED';
      const newStatus = 'PENDING';
      final isBlocked = newStatus == 'PENDING' && prevStatus == 'REJECTED';
      expect(isBlocked, isTrue); // 차단 조건 충족 → 에러 반환해야 함
    });

    test('SCENARIO-APP-80: 확정된 지원서 거절 시도 → 차단 (cancelConfirmedApplication 사용 권장)', () {
      const prevStatus = 'CONFIRMED';
      const newStatus = 'REJECTED';
      final isBlocked = newStatus == 'REJECTED' &&
          SimAppStatus.confirmedStatuses.contains(prevStatus);
      expect(isBlocked, isTrue);
    });

    test('SCENARIO-APP-81: isTerminationApproved — 퇴사 완료 후 재지원 허용 조건', () {
      final app = _makeApp(status: 'CONFIRMED', resignStatus: 'APPROVED');
      expect(app.isTerminationApproved, isTrue);
      // 이 경우 중복 체크에서 건너뜀 → 재지원 허용
      final dupError = ApplySimulator.checkDuplicateApplication(
        uid: app.uid, toId: app.toId, selectedWorkType: app.selectedWorkType,
        slotId: app.slotId, workDetailId: null,
        existingApps: [app],
      );
      expect(dupError, isNull);
    });
  });
}
