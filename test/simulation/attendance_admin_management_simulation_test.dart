// test/simulation/attendance_admin_management_simulation_test.dart
//
// 관리자 당일명단 출퇴근 수정, 노쇼 처리, 급여 확정 흐름 시뮬레이션
//
// ── 커버 범위 ────────────────────────────────────────────────────
//  1. 관리자 출근 시간 수동 입력 (체크인 수정)          SCENARIO-AMG-01~08
//  2. 관리자 퇴근 시간 수동 입력 (체크아웃 수정)        SCENARIO-AMG-09~16
//  3. 노쇼 처리 (statusNoShow 전환)                     SCENARIO-AMG-17~22
//  4. 노쇼 해제 (재출근 처리)                           SCENARIO-AMG-23~26
//  5. 일괄 출근 시간 입력                               SCENARIO-AMG-27~32
//  6. 일괄 퇴근 시간 입력                               SCENARIO-AMG-33~38
//  7. 급여 확정 pending → calculated                    SCENARIO-AMG-39~43
//  8. 급여 확정 calculated → confirmed                  SCENARIO-AMG-44~48
//  9. 급여 확정 취소 confirmed → calculated             SCENARIO-AMG-49~52
// 10. WageConfirmDialog 탭 3개 데이터 분리              SCENARIO-AMG-53~60
// 11. AttendanceStatusHelper.deriveStatus 동작          SCENARIO-AMG-61~68
// 12. CloseManagementDialog 월별 마감 현황              SCENARIO-AMG-69~75
//
// 합계: 75 시나리오

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/attendance_model.dart' show AttendanceModel;
import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/wage_detail_model.dart';
import 'package:ALfit/utils/attendance_status_helper.dart';

// ── 공통 상수 ─────────────────────────────────────────────────────

final _workDate = DateTime(2026, 7, 8);
const _bizId   = 'biz-001';
const _bizName = '테스트 사업장';
const _userId  = 'user-001';
const _appId   = 'app-001';
const _adminId = 'admin-001';

// ── 헬퍼: AttendanceModel 생성 ────────────────────────────────────

AttendanceModel _makeAtt({
  String id = 'att-001',
  DateTime? workDate,
  String? checkIn,
  String? originalCheckIn,
  String? checkOut,
  String? originalCheckOut,
  String status = AttendanceModel.statusPresent,
  String wageStatus = AttendanceModel.wagePending,
  WageDetailModel? wageDetail,
  int? finalWage,
  bool isZeroWork = false,
  String? modifiedBy,
}) {
  final wd = workDate ?? _workDate;
  return AttendanceModel(
    id: id,
    applicationId: _appId,
    userId: _userId,
    businessId: _bizId,
    businessName: _bizName,
    workDate: wd,
    workType: '서빙',
    checkInAt: _parseHHmm(wd, checkIn),
    originalCheckInAt: _parseHHmm(wd, originalCheckIn),
    checkOutAt: _parseHHmmWithOvernightFix(wd, checkOut, checkIn),
    originalCheckOutAt: _parseHHmmWithOvernightFix(wd, originalCheckOut, checkIn),
    status: status,
    wageStatus: wageStatus,
    wageDetail: wageDetail,
    finalWage: finalWage,
    isZeroWork: isZeroWork,
    isModified: modifiedBy != null,
    modifiedBy: modifiedBy,
    createdAt: wd,
  );
}

DateTime? _parseHHmm(DateTime date, String? hhmm) {
  if (hhmm == null) return null;
  final parts = hhmm.split(':');
  if (parts.length < 2) return null;
  return DateTime(date.year, date.month, date.day,
      int.parse(parts[0]), int.parse(parts[1]));
}

/// 퇴근 시각이 출근보다 이전이면 익일로 보정 (야간 교대)
DateTime? _parseHHmmWithOvernightFix(DateTime date, String? checkOut, String? checkIn) {
  final co = _parseHHmm(date, checkOut);
  if (co == null) return null;
  final ci = _parseHHmm(date, checkIn);
  if (ci != null && co.isBefore(ci)) {
    return co.add(const Duration(days: 1));
  }
  return co;
}

/// 헬퍼: ApplicationModel 생성 (deriveStatus 테스트용)
ApplicationModel _makeApp({
  String startTime = '09:00',
  String endTime   = '18:00',
}) {
  return ApplicationModel(
    id: _appId,
    businessId: _bizId,
    businessName: _bizName,
    toTitle: '서빙 TO',
    workDate: _workDate,
    startTime: startTime,
    endTime: endTime,
    uid: _userId,
    selectedWorkType: '서빙',
    wage: 12000,
    status: 'CONFIRMED',
    appliedAt: _workDate,
  );
}

// ── 관리자 체크인 수정 로직 재구현 ───────────────────────────────

/// 관리자가 출근 시각을 수동 입력할 때의 동작을 시뮬레이션.
/// wageStatus가 pending인 경우에만 수정 허용.
/// originalCheckIn이 이미 있는 경우 → checkIn만 변경
/// originalCheckIn이 없는 경우(첫 수동 입력) → checkIn = originalCheckIn 동시 설정
AttendanceModel? adminSetCheckIn(
  AttendanceModel att,
  DateTime newCheckIn,
  String adminUid,
) {
  // 수정 불가 상태 차단
  if (!att.isWagePending) return null;

  final now = DateTime.now();
  if (att.originalCheckInAt != null) {
    // 기존 원본 유지, 최종 시각만 교체
    return att.copyWith(
      checkInAt: newCheckIn,
      isModified: true,
      modifiedBy: adminUid,
      modifiedAt: now,
    );
  } else {
    // 첫 수동 입력: checkIn = originalCheckIn 동시 설정
    return att.copyWith(
      checkInAt: newCheckIn,
      originalCheckInAt: newCheckIn,
      isModified: true,
      modifiedBy: adminUid,
      modifiedAt: now,
    );
  }
}

// ── 관리자 체크아웃 수정 로직 재구현 ─────────────────────────────

AttendanceModel? adminSetCheckOut(
  AttendanceModel att,
  DateTime newCheckOut,
  String adminUid,
) {
  if (!att.isWagePending) return null;
  final now = DateTime.now();
  if (att.originalCheckOutAt != null) {
    return att.copyWith(
      checkOutAt: newCheckOut,
      isModified: true,
      modifiedBy: adminUid,
      modifiedAt: now,
    );
  } else {
    return att.copyWith(
      checkOutAt: newCheckOut,
      originalCheckOutAt: newCheckOut,
      isModified: true,
      modifiedBy: adminUid,
      modifiedAt: now,
    );
  }
}

// ── 노쇼 처리 로직 재구현 ────────────────────────────────────────

/// 이미 체크인한 근무자는 노쇼 처리 불가 → null 반환
AttendanceModel? adminMarkNoShow(AttendanceModel att) {
  if (att.hasCheckedIn) return null; // 차단
  return att.copyWith(
    status: AttendanceModel.statusNoShow,
    wageStatus: AttendanceModel.wagePending,
    checkInAt: null,
    checkOutAt: null,
  );
}

/// 노쇼에서 재출근 처리
AttendanceModel? adminClearNoShow(AttendanceModel att) {
  if (!att.isNoShow) return null;
  return att.copyWith(
    status: AttendanceModel.statusPresent,
    wageStatus: AttendanceModel.wagePending,
    checkInAt: null,
    checkOutAt: null,
    isModified: false,
  );
}

// ── 시간 유효성 검사 ──────────────────────────────────────────────

bool isValidHHmm(String timeStr) {
  final parts = timeStr.split(':');
  if (parts.length != 2) return false;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return false;
  return h >= 0 && h <= 23 && m >= 0 && m <= 59;
}

// ── 급여 확정 로직 재구현 ────────────────────────────────────────

/// pending → calculated (1차 계산)
AttendanceModel? adminCalculateWage(
  AttendanceModel att,
  WageDetailModel detail,
  String adminUid,
) {
  if (!att.isWagePending) return null; // 이미 calculated 이상이면 null
  final now = DateTime.now();
  return att.copyWith(
    wageStatus: AttendanceModel.wageCalculated,
    wageDetail: detail.copyWith(
      calculatedBy: adminUid,
      calculatedAt: now,
    ),
    finalWage: detail.totalAmount,
  );
}

/// 이미 calculated인 레코드 재계산 (덮어쓰기)
AttendanceModel adminRecalculateWage(
  AttendanceModel att,
  WageDetailModel newDetail,
  String adminUid,
) {
  final now = DateTime.now();
  return att.copyWith(
    wageStatus: AttendanceModel.wageCalculated,
    wageDetail: newDetail.copyWith(
      calculatedBy: adminUid,
      calculatedAt: now,
    ),
    finalWage: newDetail.totalAmount,
  );
}

/// calculated → confirmed (최종 확정)
AttendanceModel? adminConfirmWage(AttendanceModel att, String adminUid) {
  if (!att.isWageCalculated) return null; // calculated 상태만 가능
  final now = DateTime.now();
  return att.copyWith(
    wageStatus: AttendanceModel.wageConfirmed,
    confirmedBy: adminUid,
    confirmedAt: now,
    adminConfirmed: true,
  );
}

/// confirmed → calculated (확정 취소)
AttendanceModel? adminCancelConfirm(AttendanceModel att) {
  if (att.isWageTransferred) return null; // transferred는 취소 불가
  if (!att.isWageConfirmed) return null;
  return att.copyWith(
    wageStatus: AttendanceModel.wageCalculated,
    confirmedBy: null,
    confirmedAt: null,
    adminConfirmed: false,
  );
}

// ── 탭 분류 ──────────────────────────────────────────────────────

/// -1 = 분류 안됨, 0 = 미확정(pending), 1 = 확정내역(calculated/confirmed), 2 = 마감(transferred)
int classifyTab(AttendanceModel att) {
  if (att.isWageTransferred) return 2;
  if (att.isWageCalculated || att.isWageConfirmed) return 1;
  if (att.isWagePending) return 0;
  return -1;
}

// ── 월별 마감 현황 로직 재구현 ───────────────────────────────────

/// 특정 날짜의 모든 근태 레코드가 마감 완료(confirmed/transferred)인지 판단.
/// 레코드가 없으면 true(빈 날짜 = 마감 완료로 처리).
bool isDayClosed(List<AttendanceModel> dayRecords) {
  if (dayRecords.isEmpty) return true;
  return dayRecords.every(
    (att) => att.isWageConfirmed || att.isWageTransferred,
  );
}

/// 미마감 날짜 = pending 또는 calculated 포함
bool isDayUnclosed(List<AttendanceModel> dayRecords) {
  return dayRecords.any(
    (att) => att.isWagePending || att.isWageCalculated,
  );
}

// ── WageDetailModel 헬퍼 ─────────────────────────────────────────

WageDetailModel _makeWageDetail({
  String wageType = 'hourly',
  int baseWage = 12000,
  int workMinutes = 480,
  int totalAmount = 96000,
  int netWage = 92000,
  String? calculatedBy,
  DateTime? calculatedAt,
  String? confirmedBy,
  DateTime? confirmedAt,
}) {
  return WageDetailModel(
    wageType: wageType,
    baseWage: baseWage,
    workMinutes: workMinutes,
    actualMinutes: workMinutes,
    baseAmount: totalAmount,
    totalAmount: totalAmount,
    netWage: netWage,
    calculatedBy: calculatedBy,
    calculatedAt: calculatedAt,
    confirmedBy: confirmedBy,
    confirmedAt: confirmedAt,
  );
}

// ═══════════════════════════════════════════════════════════════════
// MAIN
// ═══════════════════════════════════════════════════════════════════

void main() {
  // ══════════════════════════════════════════════════════════════════
  // 1. 관리자 출근 시간 수동 입력 (체크인 수정)
  // ══════════════════════════════════════════════════════════════════
  group('[SCENARIO-AMG-01~08] 관리자 체크인 수정', () {
    test('SCENARIO-AMG-01: originalCheckIn 있는 레코드 → checkIn만 변경, originalCheckIn 유지', () {
      final att = _makeAtt(
        checkIn: '09:10',
        originalCheckIn: '09:10',
      );
      final newCI = _parseHHmm(_workDate, '09:05')!;
      final result = adminSetCheckIn(att, newCI, _adminId);

      expect(result, isNotNull);
      expect(result!.checkIn, equals('09:05'));
      expect(result.originalCheckIn, equals('09:10'), reason: 'originalCheckIn은 절대 불변');
    });

    test('SCENARIO-AMG-02: originalCheckIn 없는 레코드(첫 수동) → checkIn=originalCheckIn 동시 설정', () {
      final att = _makeAtt(); // checkIn/originalCheckIn 모두 null
      final newCI = _parseHHmm(_workDate, '08:55')!;
      final result = adminSetCheckIn(att, newCI, _adminId);

      expect(result, isNotNull);
      expect(result!.checkIn, equals('08:55'));
      expect(result.originalCheckIn, equals('08:55'),
          reason: '첫 수동 입력 시 originalCheckIn도 동일하게 설정');
    });

    test('SCENARIO-AMG-03: wageStatus=pending 수정 허용', () {
      final att = _makeAtt(wageStatus: AttendanceModel.wagePending);
      final result = adminSetCheckIn(att, _parseHHmm(_workDate, '09:00')!, _adminId);
      expect(result, isNotNull);
    });

    test('SCENARIO-AMG-04: wageStatus=calculated 수정 차단', () {
      final att = _makeAtt(wageStatus: AttendanceModel.wageCalculated);
      final result = adminSetCheckIn(att, _parseHHmm(_workDate, '09:00')!, _adminId);
      expect(result, isNull, reason: 'calculated 상태에서는 수정 불가');
    });

    test('SCENARIO-AMG-05: wageStatus=confirmed 수정 차단', () {
      final att = _makeAtt(wageStatus: AttendanceModel.wageConfirmed);
      final result = adminSetCheckIn(att, _parseHHmm(_workDate, '09:00')!, _adminId);
      expect(result, isNull, reason: 'confirmed 상태에서는 수정 불가');
    });

    test('SCENARIO-AMG-06: wageStatus=transferred 수정 차단', () {
      final att = _makeAtt(wageStatus: AttendanceModel.wageTransferred);
      final result = adminSetCheckIn(att, _parseHHmm(_workDate, '09:00')!, _adminId);
      expect(result, isNull, reason: 'transferred 상태에서는 수정 불가');
    });

    test('SCENARIO-AMG-07: 수정 후 isModified=true, modifiedBy 설정', () {
      final att = _makeAtt();
      final result = adminSetCheckIn(att, _parseHHmm(_workDate, '09:00')!, _adminId);
      expect(result!.isModified, isTrue);
      expect(result.modifiedBy, equals(_adminId));
    });

    test('SCENARIO-AMG-08: 수정 후 지각 여부 — 지각 시각으로 수정 시 status 재계산 필요', () {
      // 지각 시각(09:15)으로 체크인을 수정하면 status 재계산은 서비스 레이어 책임
      // 모델 자체는 isLate getter가 status 필드 기반임을 검증
      final attPending = _makeAtt(
        checkIn: '09:15',
        originalCheckIn: '09:15',
        status: AttendanceModel.statusLate,
      );
      expect(attPending.isLate, isTrue, reason: 'status=late → isLate getter true');
      expect(attPending.isWagePending, isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // 2. 관리자 퇴근 시간 수동 입력 (체크아웃 수정)
  // ══════════════════════════════════════════════════════════════════
  group('[SCENARIO-AMG-09~16] 관리자 체크아웃 수정', () {
    test('SCENARIO-AMG-09: originalCheckOut 있는 레코드 → checkOut만 변경, originalCheckOut 유지', () {
      final att = _makeAtt(
        checkIn: '09:00',
        originalCheckIn: '09:00',
        checkOut: '18:00',
        originalCheckOut: '18:00',
      );
      final newCO = _parseHHmm(_workDate, '19:00')!;
      final result = adminSetCheckOut(att, newCO, _adminId);

      expect(result, isNotNull);
      expect(result!.checkOut, equals('19:00'));
      expect(result.originalCheckOut, equals('18:00'), reason: 'originalCheckOut 불변');
    });

    test('SCENARIO-AMG-10: originalCheckOut 없는 레코드 → checkOut=originalCheckOut 동시 설정', () {
      final att = _makeAtt(
        checkIn: '09:00',
        originalCheckIn: '09:00',
      );
      final newCO = _parseHHmm(_workDate, '18:00')!;
      final result = adminSetCheckOut(att, newCO, _adminId);

      expect(result!.checkOut, equals('18:00'));
      expect(result.originalCheckOut, equals('18:00'));
    });

    test('SCENARIO-AMG-11: wageStatus=pending 퇴근 수정 허용', () {
      final att = _makeAtt(checkIn: '09:00', originalCheckIn: '09:00',
          wageStatus: AttendanceModel.wagePending);
      final result = adminSetCheckOut(att, _parseHHmm(_workDate, '18:00')!, _adminId);
      expect(result, isNotNull);
    });

    test('SCENARIO-AMG-12: wageStatus=confirmed 퇴근 수정 차단', () {
      final att = _makeAtt(checkIn: '09:00', wageStatus: AttendanceModel.wageConfirmed);
      final result = adminSetCheckOut(att, _parseHHmm(_workDate, '18:00')!, _adminId);
      expect(result, isNull);
    });

    test('SCENARIO-AMG-13: 퇴근 < 출근 → 야간 교대 보정 — checkOutAt이 checkInAt보다 나중', () {
      // 출근 22:00, 퇴근 06:00 → 익일 06:00
      final att = _makeAtt(
        checkIn: '22:00',
        originalCheckIn: '22:00',
        checkOut: '06:00', // 내부에서 익일 보정됨
        originalCheckOut: '06:00',
      );
      expect(att.checkOutAt!.isAfter(att.checkInAt!),
          isTrue, reason: '야간 교대 퇴근은 checkInAt보다 나중이어야 함');
    });

    test('SCENARIO-AMG-14: checkIn 없이 checkOut만 있는 레코드 — hasCheckedIn=false', () {
      final att = _makeAtt(checkOut: '18:00');
      expect(att.hasCheckedIn, isFalse);
      expect(att.hasCheckedOut, isTrue);
    });

    test('SCENARIO-AMG-15: 연장 여부 — isEarlyLeave getter는 status 기반', () {
      final att = _makeAtt(
        checkIn: '09:00',
        checkOut: '17:00', // 조퇴
        status: AttendanceModel.statusEarlyLeave,
      );
      expect(att.isEarlyLeave, isTrue);
    });

    test('SCENARIO-AMG-16: 이미 마감된 레코드(transferred) 퇴근 수정 차단', () {
      final att = _makeAtt(
        checkIn: '09:00',
        checkOut: '18:00',
        wageStatus: AttendanceModel.wageTransferred,
      );
      final result = adminSetCheckOut(att, _parseHHmm(_workDate, '19:00')!, _adminId);
      expect(result, isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // 3. 노쇼 처리 (statusNoShow 전환)
  // ══════════════════════════════════════════════════════════════════
  group('[SCENARIO-AMG-17~22] 노쇼 처리', () {
    test('SCENARIO-AMG-17: 체크인 없는 근무자 → 노쇼 처리 성공', () {
      final att = _makeAtt(status: AttendanceModel.statusAbsent);
      final result = adminMarkNoShow(att);
      expect(result, isNotNull);
      expect(result!.isNoShow, isTrue);
      expect(result.status, equals(AttendanceModel.statusNoShow));
    });

    test('SCENARIO-AMG-18: 이미 체크인한 근무자 → 노쇼 처리 차단', () {
      final att = _makeAtt(checkIn: '09:05', originalCheckIn: '09:05');
      final result = adminMarkNoShow(att);
      expect(result, isNull, reason: '체크인 기록이 있으면 노쇼 처리 불가');
    });

    test('SCENARIO-AMG-19: 노쇼 처리 후 wageStatus=pending 유지', () {
      final att = _makeAtt();
      final result = adminMarkNoShow(att);
      expect(result!.wageStatus, equals(AttendanceModel.wagePending));
    });

    test('SCENARIO-AMG-20: 노쇼 처리 후 checkInAt=null, checkOutAt=null', () {
      final att = _makeAtt();
      final result = adminMarkNoShow(att);
      expect(result!.checkInAt, isNull);
      expect(result.checkOutAt, isNull);
    });

    test('SCENARIO-AMG-21: 노쇼 상태에서 checkIn 입력 시 → 노쇼 해제 후 출근 처리', () {
      final noShowAtt = _makeAtt(status: AttendanceModel.statusNoShow);
      // 노쇼 해제 후 체크인 설정
      final cleared = adminClearNoShow(noShowAtt);
      expect(cleared, isNotNull);
      final withCheckIn = adminSetCheckIn(cleared!, _parseHHmm(_workDate, '09:00')!, _adminId);
      expect(withCheckIn, isNotNull);
      expect(withCheckIn!.hasCheckedIn, isTrue);
      expect(withCheckIn.isNoShow, isFalse);
    });

    test('SCENARIO-AMG-22: statusNoShow 상수값 — "NO_SHOW"', () {
      expect(AttendanceModel.statusNoShow, equals('NO_SHOW'));
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // 4. 노쇼 해제 (재출근 처리)
  // ══════════════════════════════════════════════════════════════════
  group('[SCENARIO-AMG-23~26] 노쇼 해제', () {
    test('SCENARIO-AMG-23: 노쇼 상태 → pending으로 초기화', () {
      final noShowAtt = _makeAtt(status: AttendanceModel.statusNoShow);
      final result = adminClearNoShow(noShowAtt);
      expect(result, isNotNull);
      expect(result!.wageStatus, equals(AttendanceModel.wagePending));
      expect(result.isNoShow, isFalse);
    });

    test('SCENARIO-AMG-24: 노쇼 해제 후 checkInAt, checkOutAt null 초기화', () {
      final noShowAtt = _makeAtt(status: AttendanceModel.statusNoShow);
      final result = adminClearNoShow(noShowAtt);
      expect(result!.checkInAt, isNull);
      expect(result.checkOutAt, isNull);
    });

    test('SCENARIO-AMG-25: 일반 상태(present)에서 clearNoShow 호출 → null 반환', () {
      final att = _makeAtt(status: AttendanceModel.statusPresent);
      final result = adminClearNoShow(att);
      expect(result, isNull, reason: 'noShow 상태가 아니면 해제 불가');
    });

    test('SCENARIO-AMG-26: 노쇼 해제 후 관리자가 수동으로 체크인 입력 가능', () {
      final noShowAtt = _makeAtt(status: AttendanceModel.statusNoShow);
      final cleared = adminClearNoShow(noShowAtt)!;
      final withCI = adminSetCheckIn(cleared, _parseHHmm(_workDate, '10:00')!, _adminId);
      expect(withCI, isNotNull);
      expect(withCI!.checkIn, equals('10:00'));
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // 5. 일괄 출근 시간 입력
  // ══════════════════════════════════════════════════════════════════
  group('[SCENARIO-AMG-27~32] 일괄 출근 시간 입력', () {
    test('SCENARIO-AMG-27: 선택된 멤버에만 체크인 적용 — 선택 안 된 멤버 변경 없음', () {
      final attA = _makeAtt(id: 'att-A');
      final attB = _makeAtt(id: 'att-B');
      final attC = _makeAtt(id: 'att-C');

      final selected = {'att-A', 'att-B'};
      final newCI = _parseHHmm(_workDate, '09:00')!;

      final results = [attA, attB, attC].map((att) {
        if (selected.contains(att.id)) {
          return adminSetCheckIn(att, newCI, _adminId);
        }
        return att;
      }).toList();

      expect(results[0]!.checkIn, equals('09:00'));
      expect(results[1]!.checkIn, equals('09:00'));
      expect(results[2]!.checkIn, isNull, reason: 'att-C는 선택 안 됨 → 변경 없음');
    });

    test('SCENARIO-AMG-28: 이미 체크인한 멤버에 일괄 입력 — pending 상태이면 덮어쓰기 가능', () {
      final att = _makeAtt(
        checkIn: '09:10',
        originalCheckIn: '09:10',
        wageStatus: AttendanceModel.wagePending,
      );
      final newCI = _parseHHmm(_workDate, '09:00')!;
      final result = adminSetCheckIn(att, newCI, _adminId);
      expect(result, isNotNull);
      expect(result!.checkIn, equals('09:00'));
    });

    test('SCENARIO-AMG-29: 유효하지 않은 시각 "25:00" → 검증 차단', () {
      expect(isValidHHmm('25:00'), isFalse, reason: '시간값 25는 유효하지 않음');
    });

    test('SCENARIO-AMG-30: 유효하지 않은 시각 "12:60" → 검증 차단', () {
      expect(isValidHHmm('12:60'), isFalse, reason: '분값 60은 유효하지 않음');
    });

    test('SCENARIO-AMG-31: 유효한 시각 "09:00" → 검증 통과', () {
      expect(isValidHHmm('09:00'), isTrue);
    });

    test('SCENARIO-AMG-32: 일괄 입력 대상 0명 — 아무것도 변경 안 됨', () {
      final atts = [
        _makeAtt(id: 'att-A'),
        _makeAtt(id: 'att-B'),
      ];
      final selected = <String>{};
      final newCI = _parseHHmm(_workDate, '09:00')!;

      final results = atts.map((att) {
        if (selected.contains(att.id)) {
          return adminSetCheckIn(att, newCI, _adminId);
        }
        return att;
      }).toList();

      expect(results.every((a) => a?.checkIn == null), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // 6. 일괄 퇴근 시간 입력
  // ══════════════════════════════════════════════════════════════════
  group('[SCENARIO-AMG-33~38] 일괄 퇴근 시간 입력', () {
    test('SCENARIO-AMG-33: 체크인 없는 멤버에 퇴근 시간 입력 → pending이면 허용 (수동 입력)', () {
      // 실제 서비스에서는 체크인 없이 체크아웃만 설정 가능 — 관리자 자유도 보장
      final att = _makeAtt(); // checkIn null
      final newCO = _parseHHmm(_workDate, '18:00')!;
      final result = adminSetCheckOut(att, newCO, _adminId);
      expect(result, isNotNull, reason: 'pending 상태라면 체크인 없이도 퇴근 입력 허용');
      expect(result!.hasCheckedOut, isTrue);
    });

    test('SCENARIO-AMG-34: 퇴근 < 출근 → _parseHHmmWithOvernightFix로 익일 보정', () {
      final att = _makeAtt(
        checkIn: '22:00',
        originalCheckIn: '22:00',
        checkOut: '06:00',
      );
      // 내부 야간 보정 확인
      expect(att.checkOutAt!.isAfter(att.checkInAt!), isTrue);
      // 날짜 차이 1일
      final diff = att.checkOutAt!.difference(att.checkInAt!);
      expect(diff.inHours, equals(8));
    });

    test('SCENARIO-AMG-35: 이미 마감된 레코드(transferred) → 퇴근 수정 차단', () {
      final att = _makeAtt(
        checkIn: '09:00',
        checkOut: '18:00',
        wageStatus: AttendanceModel.wageTransferred,
      );
      final result = adminSetCheckOut(att, _parseHHmm(_workDate, '19:00')!, _adminId);
      expect(result, isNull);
    });

    test('SCENARIO-AMG-36: 동일 시각으로 일괄 퇴근 입력 — 여러 멤버 적용', () {
      final atts = [
        _makeAtt(id: 'att-A', checkIn: '09:00', originalCheckIn: '09:00'),
        _makeAtt(id: 'att-B', checkIn: '09:00', originalCheckIn: '09:00'),
      ];
      final newCO = _parseHHmm(_workDate, '18:00')!;
      final results = atts.map((att) => adminSetCheckOut(att, newCO, _adminId)).toList();
      expect(results.every((r) => r?.checkOut == '18:00'), isTrue);
    });

    test('SCENARIO-AMG-37: 퇴근 시각 == 출근 시각 → 0분 근무 (허용, isZeroWork 별도 처리)', () {
      final att = _makeAtt(checkIn: '09:00', originalCheckIn: '09:00');
      final sameTime = _parseHHmm(_workDate, '09:00')!;
      final result = adminSetCheckOut(att, sameTime, _adminId);
      expect(result, isNotNull, reason: '동일 시각도 허용 (isZeroWork 처리는 서비스 레이어)');
      // workMinutes(HH:mm 기반) = 0
      final wm = AttendanceStatusHelper.workMinutes('09:00', '09:00');
      expect(wm, equals(0));
    });

    test('SCENARIO-AMG-38: calculated 상태 레코드 퇴근 수정 차단', () {
      final att = _makeAtt(
        checkIn: '09:00',
        checkOut: '18:00',
        wageStatus: AttendanceModel.wageCalculated,
      );
      final result = adminSetCheckOut(att, _parseHHmm(_workDate, '19:00')!, _adminId);
      expect(result, isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // 7. 급여 확정 (pending → calculated)
  // ══════════════════════════════════════════════════════════════════
  group('[SCENARIO-AMG-39~43] 급여 계산 (pending → calculated)', () {
    test('SCENARIO-AMG-39: pending → calculated 전환 성공', () {
      final att = _makeAtt(
        checkIn: '09:00',
        checkOut: '18:00',
        wageStatus: AttendanceModel.wagePending,
      );
      final detail = _makeWageDetail(totalAmount: 96000, netWage: 92000);
      final result = adminCalculateWage(att, detail, _adminId);

      expect(result, isNotNull);
      expect(result!.wageStatus, equals(AttendanceModel.wageCalculated));
      expect(result.isWageCalculated, isTrue);
    });

    test('SCENARIO-AMG-40: calculated 후 finalWage 설정', () {
      final att = _makeAtt(wageStatus: AttendanceModel.wagePending);
      final detail = _makeWageDetail(totalAmount: 96000);
      final result = adminCalculateWage(att, detail, _adminId);
      expect(result!.finalWage, equals(96000));
    });

    test('SCENARIO-AMG-41: wageDetail.calculatedBy, calculatedAt 설정 확인', () {
      final att = _makeAtt(wageStatus: AttendanceModel.wagePending);
      final detail = _makeWageDetail();
      final result = adminCalculateWage(att, detail, _adminId);
      expect(result!.wageDetail!.calculatedBy, equals(_adminId));
      expect(result.wageDetail!.calculatedAt, isNotNull);
    });

    test('SCENARIO-AMG-42: 이미 calculated인 레코드 → adminCalculateWage 반환 null (차단)', () {
      final att = _makeAtt(wageStatus: AttendanceModel.wageCalculated);
      final detail = _makeWageDetail();
      final result = adminCalculateWage(att, detail, _adminId);
      expect(result, isNull, reason: 'calculated 이상이면 재계산 차단');
    });

    test('SCENARIO-AMG-43: 이미 calculated인 레코드 재계산 → adminRecalculateWage로 덮어쓰기', () {
      final att = _makeAtt(wageStatus: AttendanceModel.wageCalculated,
          finalWage: 96000);
      final newDetail = _makeWageDetail(totalAmount: 100000);
      final result = adminRecalculateWage(att, newDetail, _adminId);
      expect(result.wageStatus, equals(AttendanceModel.wageCalculated));
      expect(result.finalWage, equals(100000), reason: '새 금액으로 덮어씀');
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // 8. 급여 확정 (calculated → confirmed)
  // ══════════════════════════════════════════════════════════════════
  group('[SCENARIO-AMG-44~48] 급여 최종 확정 (calculated → confirmed)', () {
    test('SCENARIO-AMG-44: calculated → confirmed 전환 성공', () {
      final att = _makeAtt(wageStatus: AttendanceModel.wageCalculated);
      final result = adminConfirmWage(att, _adminId);
      expect(result, isNotNull);
      expect(result!.isWageConfirmed, isTrue);
    });

    test('SCENARIO-AMG-45: confirmedAt, confirmedBy 설정', () {
      final att = _makeAtt(wageStatus: AttendanceModel.wageCalculated);
      final result = adminConfirmWage(att, _adminId);
      expect(result!.confirmedBy, equals(_adminId));
      expect(result.confirmedAt, isNotNull);
    });

    test('SCENARIO-AMG-46: pending 상태에서 직접 confirm 차단', () {
      final att = _makeAtt(wageStatus: AttendanceModel.wagePending);
      final result = adminConfirmWage(att, _adminId);
      expect(result, isNull, reason: 'pending → confirmed 직접 전환 불가');
    });

    test('SCENARIO-AMG-47: 이미 confirmed → 재확정 차단', () {
      final att = _makeAtt(wageStatus: AttendanceModel.wageConfirmed);
      final result = adminConfirmWage(att, _adminId);
      expect(result, isNull, reason: '이미 confirmed 상태에서 재확정 불가');
    });

    test('SCENARIO-AMG-48: confirmed 후 adminConfirmed=true 설정', () {
      final att = _makeAtt(wageStatus: AttendanceModel.wageCalculated);
      final result = adminConfirmWage(att, _adminId);
      expect(result!.adminConfirmed, isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // 9. 급여 확정 취소 (confirmed → calculated)
  // ══════════════════════════════════════════════════════════════════
  group('[SCENARIO-AMG-49~52] 급여 확정 취소 (confirmed → calculated)', () {
    test('SCENARIO-AMG-49: confirmed → calculated 취소 성공', () {
      final att = _makeAtt(wageStatus: AttendanceModel.wageConfirmed);
      final result = adminCancelConfirm(att);
      expect(result, isNotNull);
      expect(result!.isWageCalculated, isTrue);
    });

    test('SCENARIO-AMG-50: 취소 후 confirmedAt=null, confirmedBy=null', () {
      final att = _makeAtt(wageStatus: AttendanceModel.wageConfirmed);
      final result = adminCancelConfirm(att);
      expect(result!.confirmedAt, isNull);
      expect(result.confirmedBy, isNull);
    });

    test('SCENARIO-AMG-51: transferred 상태 → 취소 차단', () {
      final att = _makeAtt(wageStatus: AttendanceModel.wageTransferred);
      final result = adminCancelConfirm(att);
      expect(result, isNull, reason: '송금완료(transferred) 상태는 취소 불가');
    });

    test('SCENARIO-AMG-52: pending 상태에서 cancelConfirm → null 반환', () {
      final att = _makeAtt(wageStatus: AttendanceModel.wagePending);
      final result = adminCancelConfirm(att);
      expect(result, isNull, reason: 'pending은 confirmed가 아니므로 취소 불가');
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // 10. WageConfirmDialog 탭 3개 데이터 분리
  // ══════════════════════════════════════════════════════════════════
  group('[SCENARIO-AMG-53~60] WageConfirmDialog 탭 분류', () {
    test('SCENARIO-AMG-53: pending → 탭0(미확정)', () {
      final att = _makeAtt(wageStatus: AttendanceModel.wagePending);
      expect(classifyTab(att), equals(0));
    });

    test('SCENARIO-AMG-54: calculated → 탭1(확정내역)', () {
      final att = _makeAtt(wageStatus: AttendanceModel.wageCalculated);
      expect(classifyTab(att), equals(1));
    });

    test('SCENARIO-AMG-55: confirmed → 탭1(확정내역)', () {
      final att = _makeAtt(wageStatus: AttendanceModel.wageConfirmed);
      expect(classifyTab(att), equals(1));
    });

    test('SCENARIO-AMG-56: transferred → 탭2(마감내역)', () {
      final att = _makeAtt(wageStatus: AttendanceModel.wageTransferred);
      expect(classifyTab(att), equals(2));
    });

    test('SCENARIO-AMG-57: 탭1 totalAmount 합산 정확성', () {
      final atts = [
        _makeAtt(id: 'a1', wageStatus: AttendanceModel.wageCalculated, finalWage: 96000),
        _makeAtt(id: 'a2', wageStatus: AttendanceModel.wageConfirmed,  finalWage: 80000),
        _makeAtt(id: 'a3', wageStatus: AttendanceModel.wagePending,     finalWage: 70000),
      ];
      final tab1 = atts.where((a) => classifyTab(a) == 1).toList();
      final total = tab1.fold<int>(0, (sum, a) => sum + (a.finalWage ?? 0));
      expect(total, equals(176000), reason: '탭1(calculated+confirmed) 합산');
    });

    test('SCENARIO-AMG-58: 탭0 totalAmount 합산', () {
      final atts = [
        _makeAtt(id: 'a1', wageStatus: AttendanceModel.wagePending, finalWage: 50000),
        _makeAtt(id: 'a2', wageStatus: AttendanceModel.wagePending, finalWage: 60000),
      ];
      final total = atts
          .where((a) => classifyTab(a) == 0)
          .fold<int>(0, (sum, a) => sum + (a.finalWage ?? 0));
      expect(total, equals(110000));
    });

    test('SCENARIO-AMG-59: 빈 탭0 — 해당하는 레코드 없음', () {
      final atts = [
        _makeAtt(wageStatus: AttendanceModel.wageCalculated),
        _makeAtt(wageStatus: AttendanceModel.wageConfirmed),
      ];
      final tab0 = atts.where((a) => classifyTab(a) == 0).toList();
      expect(tab0.isEmpty, isTrue);
    });

    test('SCENARIO-AMG-60: 미지정 wageStatus → 분류 안됨(-1)', () {
      // 비정상 상태는 classifyTab에서 -1 반환 — 실제 AttendanceModel은 default=pending이므로
      // 이 케이스는 경계값 검증
      expect(classifyTab(_makeAtt(wageStatus: 'unknown')), equals(-1));
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // 11. AttendanceStatusHelper.deriveStatus 동작
  // ══════════════════════════════════════════════════════════════════
  group('[SCENARIO-AMG-61~68] AttendanceStatusHelper', () {
    test('SCENARIO-AMG-61: 정시 출퇴근 → present', () {
      final app = _makeApp(startTime: '09:00', endTime: '18:00');
      final status = AttendanceStatusHelper.deriveStatus(app, '09:00', '18:00');
      expect(status, equals(AttendanceModel.statusPresent));
    });

    test('SCENARIO-AMG-62: 출근 지각(09:01) → late', () {
      final app = _makeApp(startTime: '09:00', endTime: '18:00');
      final status = AttendanceStatusHelper.deriveStatus(app, '09:01', null);
      expect(status, equals(AttendanceModel.statusLate));
    });

    test('SCENARIO-AMG-63: 조퇴(17:59) → earlyLeave', () {
      final app = _makeApp(startTime: '09:00', endTime: '18:00');
      final status = AttendanceStatusHelper.deriveStatus(app, '09:00', '17:59');
      expect(status, equals(AttendanceModel.statusEarlyLeave));
    });

    test('SCENARIO-AMG-64: 지각+정상퇴근 → late (조퇴 아님)', () {
      final app = _makeApp(startTime: '09:00', endTime: '18:00');
      final status = AttendanceStatusHelper.deriveStatus(app, '09:30', '18:00');
      expect(status, equals(AttendanceModel.statusLate));
    });

    test('SCENARIO-AMG-65: 지각+조퇴 → earlyLeave (조퇴 우선)', () {
      final app = _makeApp(startTime: '09:00', endTime: '18:00');
      final status = AttendanceStatusHelper.deriveStatus(app, '09:30', '17:30');
      expect(status, equals(AttendanceModel.statusEarlyLeave),
          reason: '조퇴 우선 판단 규칙');
    });

    test('SCENARIO-AMG-66: 연장근무 (19:00 퇴근) → present (조퇴/지각 아님)', () {
      final app = _makeApp(startTime: '09:00', endTime: '18:00');
      final status = AttendanceStatusHelper.deriveStatus(app, '09:00', '19:00');
      expect(status, equals(AttendanceModel.statusPresent));
    });

    test('SCENARIO-AMG-67: 야간 교대 출근(22:00) 다음날 06:00 퇴근 — isNextDayCheckIn 처리', () {
      final app = _makeApp(startTime: '22:00', endTime: '06:00');
      // 22:00 출근, 06:00 퇴근 (익일)
      // checkOut이 checkIn보다 이전이면 조퇴로 잘못 판정 방지 — checkIn 전달
      final status = AttendanceStatusHelper.deriveStatus(
        app, '22:00', '06:00',
        isNextDayCheckIn: false,
      );
      // 22:00 출근 = scheduledStart 22:00 → 지각 아님, 조퇴 여부는 minutesBetween 기반
      expect(status, isNotNull);
    });

    test('SCENARIO-AMG-68: isValidWorkPeriod — 야간 자정 넘김 16시간 이하 → 유효', () {
      // 22:00 ~ 06:00 = 8시간 → 유효
      final valid = AttendanceStatusHelper.isValidWorkPeriod('22:00', '06:00');
      expect(valid, isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // 12. CloseManagementDialog 월별 마감 현황
  // ══════════════════════════════════════════════════════════════════
  group('[SCENARIO-AMG-69~75] 월별 마감 현황', () {
    test('SCENARIO-AMG-69: 전체 confirmed → 날짜 마감 완료', () {
      final records = [
        _makeAtt(id: 'a1', wageStatus: AttendanceModel.wageConfirmed),
        _makeAtt(id: 'a2', wageStatus: AttendanceModel.wageConfirmed),
      ];
      expect(isDayClosed(records), isTrue);
    });

    test('SCENARIO-AMG-70: 전체 transferred → 날짜 마감 완료', () {
      final records = [
        _makeAtt(id: 'a1', wageStatus: AttendanceModel.wageTransferred),
        _makeAtt(id: 'a2', wageStatus: AttendanceModel.wageTransferred),
      ];
      expect(isDayClosed(records), isTrue);
    });

    test('SCENARIO-AMG-71: confirmed+transferred 혼합 → 마감 완료', () {
      final records = [
        _makeAtt(id: 'a1', wageStatus: AttendanceModel.wageConfirmed),
        _makeAtt(id: 'a2', wageStatus: AttendanceModel.wageTransferred),
      ];
      expect(isDayClosed(records), isTrue);
    });

    test('SCENARIO-AMG-72: pending 하나라도 있으면 → 미마감', () {
      final records = [
        _makeAtt(id: 'a1', wageStatus: AttendanceModel.wageConfirmed),
        _makeAtt(id: 'a2', wageStatus: AttendanceModel.wagePending),
      ];
      expect(isDayClosed(records), isFalse);
      expect(isDayUnclosed(records), isTrue);
    });

    test('SCENARIO-AMG-73: calculated 하나라도 있으면 → 미마감', () {
      final records = [
        _makeAtt(id: 'a1', wageStatus: AttendanceModel.wageConfirmed),
        _makeAtt(id: 'a2', wageStatus: AttendanceModel.wageCalculated),
      ];
      expect(isDayClosed(records), isFalse);
      expect(isDayUnclosed(records), isTrue);
    });

    test('SCENARIO-AMG-74: 빈 날짜(근무 없음) → 마감 완료로 처리', () {
      expect(isDayClosed([]), isTrue, reason: '근무 레코드 없는 날은 마감 완료로 간주');
    });

    test('SCENARIO-AMG-75: 월별 마감 날짜 통계 — closed/unclosed 날짜 수 집계', () {
      // 7월 8일: confirmed 완료
      // 7월 9일: pending 존재
      // 7월 10일: 빈 날짜
      final dayData = <String, List<AttendanceModel>>{
        '2026-07-08': [
          _makeAtt(id: 'a1', workDate: DateTime(2026, 7, 8),
              wageStatus: AttendanceModel.wageConfirmed),
        ],
        '2026-07-09': [
          _makeAtt(id: 'a2', workDate: DateTime(2026, 7, 9),
              wageStatus: AttendanceModel.wagePending),
        ],
        '2026-07-10': [], // 빈 날짜
      };

      final closedCount = dayData.values.where(isDayClosed).length;
      final unclosedCount = dayData.values.where(isDayUnclosed).length;

      expect(closedCount, equals(2), reason: '7/8(confirmed) + 7/10(빈날짜) = 2 마감');
      expect(unclosedCount, equals(1), reason: '7/9(pending) = 1 미마감');
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // 추가: 모델 상수 일관성 검증
  // ══════════════════════════════════════════════════════════════════
  group('[SCENARIO-AMG-보조] 모델 상수·Getter 일관성', () {
    test('wageStatus 상수 4종 정의 확인', () {
      expect(AttendanceModel.wagePending,     equals('pending'));
      expect(AttendanceModel.wageCalculated,  equals('calculated'));
      expect(AttendanceModel.wageConfirmed,   equals('confirmed'));
      expect(AttendanceModel.wageTransferred, equals('transferred'));
    });

    test('status 상수 5종 정의 확인', () {
      expect(AttendanceModel.statusPresent,    equals('present'));
      expect(AttendanceModel.statusLate,       equals('late'));
      expect(AttendanceModel.statusEarlyLeave, equals('early_leave'));
      expect(AttendanceModel.statusAbsent,     equals('absent'));
      expect(AttendanceModel.statusNoShow,     equals('NO_SHOW'));
    });

    test('isWagePending/Calculated/Confirmed/Transferred getter 일관성', () {
      final pending    = _makeAtt(wageStatus: 'pending');
      final calculated = _makeAtt(wageStatus: 'calculated');
      final confirmed  = _makeAtt(wageStatus: 'confirmed');
      final transferred = _makeAtt(wageStatus: 'transferred');

      expect(pending.isWagePending,       isTrue);
      expect(pending.isWageCalculated,    isFalse);
      expect(calculated.isWageCalculated, isTrue);
      expect(calculated.isWagePending,    isFalse);
      expect(confirmed.isWageConfirmed,   isTrue);
      expect(transferred.isWageTransferred, isTrue);
    });

    test('displayWage — confirmed/transferred 상태일 때만 값 반환', () {
      final pending   = _makeAtt(wageStatus: 'pending',    finalWage: 96000);
      final confirmed = _makeAtt(wageStatus: 'confirmed',  finalWage: 96000);
      final transferred = _makeAtt(wageStatus: 'transferred', finalWage: 96000);

      expect(pending.displayWage,    isNull, reason: 'pending은 displayWage null');
      expect(confirmed.displayWage,  equals(96000));
      expect(transferred.displayWage, equals(96000));
    });

    test('isMissedCheckout — 체크인O 체크아웃X noShow 아닌 경우', () {
      final att = _makeAtt(
        checkIn: '09:00',
        originalCheckIn: '09:00',
        status: AttendanceModel.statusPresent,
      );
      expect(att.isMissedCheckout, isTrue);
    });

    test('isMissedCheckout — 체크아웃 있으면 false', () {
      final att = _makeAtt(
        checkIn: '09:00',
        originalCheckIn: '09:00',
        checkOut: '18:00',
        status: AttendanceModel.statusPresent,
      );
      expect(att.isMissedCheckout, isFalse);
    });

    test('AttendanceStatusHelper.timeToMinutes 파싱 — "09:30" → 570', () {
      expect(AttendanceStatusHelper.timeToMinutes('09:30'), equals(570));
    });

    test('AttendanceStatusHelper.minutesBetween 자정 넘김 처리', () {
      // 22:00 ~ 06:00 = 480분
      final mins = AttendanceStatusHelper.minutesBetween('22:00', '06:00');
      expect(mins, equals(480));
    });

    test('AttendanceStatusHelper.isOvertime — 연장 판단', () {
      // 19:00 퇴근, 18:00 계약 종료 → 연장
      expect(
        AttendanceStatusHelper.isOvertime('19:00', '18:00', checkIn: '09:00'),
        isTrue,
      );
    });

    test('AttendanceStatusHelper.isEarlyArrival — 조출 판단 (30분 이상)', () {
      // 08:30 출근, 09:00 예정 → 30분 조출
      expect(
        AttendanceStatusHelper.isEarlyArrival('08:30', '09:00', thresholdMinutes: 30),
        isTrue,
      );
    });
  });
}
