// test/simulation/payroll_payment_flow_simulation_test.dart
//
// 급여 이체 상태기계 + PayrollSummaryModel 집계 정합성 시뮬레이션 테스트
//
// 커버 범위:
//   A. PayrollSummaryModel 모델 검증 (생성자·getter·포맷터)
//   B. wageStatus 4단계 상수 검증
//   C. wageStatus 상태 전이 (pending→calculated→confirmed→transferred)
//   D. 이체 취소 (cancelTransfer) 상태 검증
//   E. 단건 이체 전제조건 검증 (상태 체크 로직)
//   F. 일괄 이체 WriteBatch 청크 분할 (450건 단위)
//   G. 중간정산 요청 (InterimSettlementRequestModel)
//   H. 월별 필터링 (yearMonth 기반)
//   I. CSV Injection 방어 (generateTransferCsv + _sanitizeCsvField)
//   J. 퀵필터 로직 (연체·오늘마감·계좌없음)
//   K. PayrollWorkerSummary 집계
//
// Firebase 의존성 없음 — 순수 모델/로직 검증
// (fromFirestore 미호출, DateTime 기반 copyWith/생성자만 사용)
//
// 실행: flutter test test/simulation/payroll_payment_flow_simulation_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/wage_detail_model.dart';
import 'package:ALfit/models/core/payroll_summary_model.dart';
import 'package:ALfit/models/core/interim_settlement_request_model.dart';
import 'package:ALfit/services/payroll_payment_service.dart';

// ── 공통 날짜 기준 ────────────────────────────────────────────────────────────
final _baseDate = DateTime(2026, 7, 1);

// ── 헬퍼: 최소 AttendanceModel 생성 ─────────────────────────────────────────
AttendanceModel _makeAttendance({
  String id = 'att-001',
  String userId = 'user-001',
  String businessId = 'biz-001',
  String businessName = '테스트 사업장',
  String wageStatus = AttendanceModel.wagePending,
  bool isZeroWork = false,
  String? yearMonth = '2026-07',
  DateTime? workDate,
  WageDetailModel? wageDetail,
  int? finalWage,
  DateTime? transferDate,
  String? transferNote,
  String? transferredBy,
  DateTime? paymentDueDate,
}) {
  return AttendanceModel(
    id: id,
    applicationId: 'app-001',
    userId: userId,
    businessId: businessId,
    businessName: businessName,
    workDate: workDate ?? _baseDate,
    workType: 'full',
    status: AttendanceModel.statusPresent,
    createdAt: DateTime(2026, 7, 1, 9, 0),
    wageStatus: wageStatus,
    isZeroWork: isZeroWork,
    yearMonth: yearMonth,
    wageDetail: wageDetail,
    finalWage: finalWage,
    transferDate: transferDate,
    transferNote: transferNote,
    transferredBy: transferredBy,
    paymentDueDate: paymentDueDate,
  );
}

// ── 헬퍼: 최소 WageDetailModel 생성 ─────────────────────────────────────────
WageDetailModel _makeWageDetail({
  int totalAmount = 100000,
  int netWage = 95000,
  DateTime? calculatedAt,
  DateTime? confirmedAt,
  int payScheduleDay = 25,
  String payScheduleType = 'monthly',
}) {
  return WageDetailModel(
    wageType: 'hourly',
    baseWage: 10000,
    totalAmount: totalAmount,
    netWage: netWage,
    calculatedAt: calculatedAt,
    confirmedAt: confirmedAt,
    payScheduleDay: payScheduleDay,
    payScheduleType: payScheduleType,
  );
}

// ── 헬퍼: InterimSettlementRequestModel 생성 ─────────────────────────────────
InterimSettlementRequestModel _makeSettlementRequest({
  String id = 'settle-001',
  String status = InterimSettlementRequestModel.statusPending,
  List<String> attendanceIds = const ['att-001', 'att-002'],
  int requestedAmount = 200000,
  int netAmount = 190000,
  String? processedBy,
  DateTime? processedAt,
  String? rejectReason,
}) {
  return InterimSettlementRequestModel(
    id: id,
    applicationId: 'app-001',
    businessId: 'biz-001',
    businessName: '테스트 사업장',
    workerId: 'user-001',
    workerName: '홍길동',
    periodStart: DateTime(2026, 7, 1),
    periodEnd: DateTime(2026, 7, 15),
    attendanceIds: attendanceIds,
    requestedAmount: requestedAmount,
    netAmount: netAmount,
    status: status,
    processedBy: processedBy,
    processedAt: processedAt,
    rejectReason: rejectReason,
    createdAt: DateTime(2026, 7, 15, 10, 0),
  );
}

// ── 헬퍼: 배치 청크 분할 (markTransferredBatch 로직과 동일) ───────────────────
List<List<String>> _splitIntoBatches(List<String> ids, {int chunkSize = 450}) {
  final result = <List<String>>[];
  for (int i = 0; i < ids.length; i += chunkSize) {
    result.add(ids.skip(i).take(chunkSize).toList());
  }
  return result;
}

// ── 헬퍼: 집계 로직 (PayrollSummaryModel Firestore 쓰기 전 집계 시뮬레이션) ────
int _computeTotalPayout(List<AttendanceModel> records) {
  return records
      .where((r) =>
          r.wageStatus == AttendanceModel.wageConfirmed ||
          r.wageStatus == AttendanceModel.wageTransferred)
      .fold(0, (acc, r) => acc + (r.wageDetail?.effectiveNetWage ?? 0));
}

int _computePendingCount(List<AttendanceModel> records) {
  return records
      .where((r) =>
          r.wageStatus == AttendanceModel.wagePending ||
          r.wageStatus == AttendanceModel.wageCalculated)
      .length;
}

int _computeNotTransferredCount(List<AttendanceModel> records) {
  return records
      .where((r) => r.wageStatus == AttendanceModel.wageConfirmed)
      .length;
}

int _computeWorkerCount(List<AttendanceModel> records) {
  return records.map((r) => r.userId).toSet().length;
}

// ── 헬퍼: 퀵필터 로직 (dashboard 동일 구현) ──────────────────────────────────
bool _isOverdue(List<AttendanceModel> recs, DateTime today) {
  final dates = recs
      .where((r) => r.paymentDueDate != null)
      .map((r) => DateTime(
            r.paymentDueDate!.year,
            r.paymentDueDate!.month,
            r.paymentDueDate!.day,
          ))
      .toList()
    ..sort();
  if (dates.isEmpty) return false;
  return dates.first.isBefore(today);
}

bool _isDueToday(List<AttendanceModel> recs, DateTime today) {
  final dates = recs
      .where((r) => r.paymentDueDate != null)
      .map((r) => DateTime(
            r.paymentDueDate!.year,
            r.paymentDueDate!.month,
            r.paymentDueDate!.day,
          ))
      .toList()
    ..sort();
  if (dates.isEmpty) return false;
  return dates.first == today;
}

bool _hasNoAccount(String uid, Map<String, Map<String, String>> bankCache) {
  return (bankCache[uid]?['bankName'] ?? '').isEmpty;
}

// ── 헬퍼: 근무자별 집계 ───────────────────────────────────────────────────────
Map<String, int> _computeWorkerTotalPayout(List<AttendanceModel> records) {
  final result = <String, int>{};
  for (final r in records.where((r) =>
      !r.isZeroWork &&
      (r.wageStatus == AttendanceModel.wageConfirmed ||
          r.wageStatus == AttendanceModel.wageTransferred))) {
    result[r.userId] =
        (result[r.userId] ?? 0) + (r.wageDetail?.effectiveNetWage ?? 0);
  }
  return result;
}

Map<String, int> _computeWorkerWorkDays(List<AttendanceModel> records) {
  final result = <String, int>{};
  for (final r in records.where((r) => !r.isZeroWork)) {
    result[r.userId] = (result[r.userId] ?? 0) + 1;
  }
  return result;
}

// ══════════════════════════════════════════════════════════════════════════════
// 테스트
// ══════════════════════════════════════════════════════════════════════════════

void main() {
  // ────────────────────────────────────────────────────────────────────────────
  // A. PayrollSummaryModel 모델 검증
  // ────────────────────────────────────────────────────────────────────────────
  group('SCENARIO-PAY-A: PayrollSummaryModel 모델 검증', () {
    test('SCENARIO-PAY-A01: empty factory — 모든 집계 필드가 0으로 초기화', () {
      final model = PayrollSummaryModel.empty(
        businessId: 'biz-001',
        year: 2026,
        month: 7,
      );
      expect(model.totalPayout, 0);
      expect(model.confirmedCount, 0);
      expect(model.workerCount, 0);
      expect(model.pendingCount, 0);
      expect(model.notTransferredCount, 0);
      expect(model.workers, isEmpty);
    });

    test('SCENARIO-PAY-A02: empty factory — id/yearMonth 형식 검증', () {
      final model = PayrollSummaryModel.empty(
        businessId: 'biz-001',
        year: 2026,
        month: 7,
      );
      expect(model.id, 'biz-001_2026-07');
      expect(model.yearMonth, '2026-07');
      expect(model.year, 2026);
      expect(model.month, 7);
    });

    test('SCENARIO-PAY-A03: empty factory — 한 자리 월은 0 패딩 적용 (2월)', () {
      final model = PayrollSummaryModel.empty(
        businessId: 'biz-001',
        year: 2026,
        month: 2,
      );
      expect(model.id, 'biz-001_2026-02');
      expect(model.yearMonth, '2026-02');
    });

    test('SCENARIO-PAY-A04: isEmpty getter — confirmedCount=0 AND pendingCount=0 → true', () {
      final model = PayrollSummaryModel.empty(
        businessId: 'biz-001',
        year: 2026,
        month: 7,
      );
      expect(model.isEmpty, isTrue);
    });

    test('SCENARIO-PAY-A05: isEmpty getter — confirmedCount>0 → false', () {
      final model = PayrollSummaryModel(
        id: 'biz-001_2026-07',
        businessId: 'biz-001',
        yearMonth: '2026-07',
        year: 2026,
        month: 7,
        totalPayout: 500000,
        confirmedCount: 3,
        workerCount: 2,
        workers: {},
        updatedAt: DateTime(2026, 7, 31),
      );
      expect(model.isEmpty, isFalse);
    });

    test('SCENARIO-PAY-A06: isEmpty getter — pendingCount>0만 있어도 false', () {
      final model = PayrollSummaryModel(
        id: 'biz-001_2026-07',
        businessId: 'biz-001',
        yearMonth: '2026-07',
        year: 2026,
        month: 7,
        totalPayout: 0,
        confirmedCount: 0,
        workerCount: 1,
        pendingCount: 5,
        workers: {},
        updatedAt: DateTime(2026, 7, 31),
      );
      expect(model.isEmpty, isFalse);
    });

    test('SCENARIO-PAY-A07: formattedTotalPayout — 0일 때 "-" 반환', () {
      final model = PayrollSummaryModel.empty(
        businessId: 'biz-001',
        year: 2026,
        month: 7,
      );
      expect(model.formattedTotalPayout, '-');
    });

    test('SCENARIO-PAY-A08: formattedTotalPayout — 1234567 → "1,234,567원"', () {
      final model = PayrollSummaryModel(
        id: 'biz-001_2026-07',
        businessId: 'biz-001',
        yearMonth: '2026-07',
        year: 2026,
        month: 7,
        totalPayout: 1234567,
        confirmedCount: 1,
        workerCount: 1,
        workers: {},
        updatedAt: DateTime(2026, 7, 31),
      );
      expect(model.formattedTotalPayout, '1,234,567원');
    });

    test('SCENARIO-PAY-A09: sortedWorkers — totalPayout 내림차순 정렬', () {
      final w1 = PayrollWorkerSummary(
          workerId: 'u1', name: '홍길동', totalPayout: 300000, workDays: 3);
      final w2 = PayrollWorkerSummary(
          workerId: 'u2', name: '김철수', totalPayout: 500000, workDays: 5);
      final w3 = PayrollWorkerSummary(
          workerId: 'u3', name: '이영희', totalPayout: 100000, workDays: 1);
      final model = PayrollSummaryModel(
        id: 'biz-001_2026-07',
        businessId: 'biz-001',
        yearMonth: '2026-07',
        year: 2026,
        month: 7,
        totalPayout: 900000,
        confirmedCount: 9,
        workerCount: 3,
        workers: {'u1': w1, 'u2': w2, 'u3': w3},
        updatedAt: DateTime(2026, 7, 31),
      );
      final sorted = model.sortedWorkers;
      expect(sorted[0].workerId, 'u2'); // 500000
      expect(sorted[1].workerId, 'u1'); // 300000
      expect(sorted[2].workerId, 'u3'); // 100000
    });

    test('SCENARIO-PAY-A10: notTransferredCount 필드 — wageConfirmed 건수 보유', () {
      final model = PayrollSummaryModel(
        id: 'biz-001_2026-07',
        businessId: 'biz-001',
        yearMonth: '2026-07',
        year: 2026,
        month: 7,
        totalPayout: 200000,
        confirmedCount: 5,
        workerCount: 2,
        pendingCount: 2,
        notTransferredCount: 3,
        workers: {},
        updatedAt: DateTime(2026, 7, 31),
      );
      expect(model.notTransferredCount, 3);
      expect(model.pendingCount, 2);
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // B. wageStatus 상수 검증
  // ────────────────────────────────────────────────────────────────────────────
  group('SCENARIO-PAY-B: wageStatus 상수 검증', () {
    test('SCENARIO-PAY-B01: wagePending = "pending"', () {
      expect(AttendanceModel.wagePending, 'pending');
    });

    test('SCENARIO-PAY-B02: wageCalculated = "calculated"', () {
      expect(AttendanceModel.wageCalculated, 'calculated');
    });

    test('SCENARIO-PAY-B03: wageConfirmed = "confirmed"', () {
      expect(AttendanceModel.wageConfirmed, 'confirmed');
    });

    test('SCENARIO-PAY-B04: wageTransferred = "transferred"', () {
      expect(AttendanceModel.wageTransferred, 'transferred');
    });

    test('SCENARIO-PAY-B05: AttendanceModel 기본 wageStatus = "pending"', () {
      final att = _makeAttendance();
      expect(att.wageStatus, AttendanceModel.wagePending);
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // C. wageStatus 4단계 상태 전이
  // ────────────────────────────────────────────────────────────────────────────
  group('SCENARIO-PAY-C: wageStatus 상태 전이 및 getter', () {
    test('SCENARIO-PAY-C01: pending → calculated (copyWith)', () {
      final att = _makeAttendance(wageStatus: AttendanceModel.wagePending);
      final next = att.copyWith(wageStatus: AttendanceModel.wageCalculated);
      expect(next.wageStatus, AttendanceModel.wageCalculated);
      expect(next.isWageCalculated, isTrue);
      expect(next.isWagePending, isFalse);
    });

    test('SCENARIO-PAY-C02: calculated → confirmed (copyWith)', () {
      final att = _makeAttendance(wageStatus: AttendanceModel.wageCalculated);
      final next = att.copyWith(wageStatus: AttendanceModel.wageConfirmed);
      expect(next.wageStatus, AttendanceModel.wageConfirmed);
      expect(next.isWageConfirmed, isTrue);
      expect(next.isWageCalculated, isFalse);
    });

    test('SCENARIO-PAY-C03: confirmed → transferred (copyWith)', () {
      final att = _makeAttendance(wageStatus: AttendanceModel.wageConfirmed);
      final transferred = att.copyWith(
        wageStatus: AttendanceModel.wageTransferred,
        transferDate: DateTime(2026, 7, 25),
        transferredBy: 'admin-001',
      );
      expect(transferred.wageStatus, AttendanceModel.wageTransferred);
      expect(transferred.isWageTransferred, isTrue);
      expect(transferred.transferredBy, 'admin-001');
    });

    test('SCENARIO-PAY-C04: isWagePending getter — pending 상태에서만 true', () {
      expect(_makeAttendance(wageStatus: AttendanceModel.wagePending).isWagePending, isTrue);
      expect(_makeAttendance(wageStatus: AttendanceModel.wageCalculated).isWagePending, isFalse);
      expect(_makeAttendance(wageStatus: AttendanceModel.wageConfirmed).isWagePending, isFalse);
      expect(_makeAttendance(wageStatus: AttendanceModel.wageTransferred).isWagePending, isFalse);
    });

    test('SCENARIO-PAY-C05: wageStatusLabel — 4단계 레이블 매핑', () {
      expect(_makeAttendance(wageStatus: AttendanceModel.wagePending).wageStatusLabel, '미계산');
      expect(_makeAttendance(wageStatus: AttendanceModel.wageCalculated).wageStatusLabel, '검토중');
      expect(_makeAttendance(wageStatus: AttendanceModel.wageConfirmed).wageStatusLabel, '확정');
      expect(_makeAttendance(wageStatus: AttendanceModel.wageTransferred).wageStatusLabel, '송금완료');
    });

    test('SCENARIO-PAY-C06: displayWage — confirmed 상태에서만 finalWage 반환', () {
      final att = _makeAttendance(
        wageStatus: AttendanceModel.wageConfirmed,
        finalWage: 95000,
      );
      expect(att.displayWage, 95000);
    });

    test('SCENARIO-PAY-C07: displayWage — transferred 상태에서도 finalWage 반환', () {
      final att = _makeAttendance(
        wageStatus: AttendanceModel.wageTransferred,
        finalWage: 95000,
      );
      expect(att.displayWage, 95000);
    });

    test('SCENARIO-PAY-C08: displayWage — pending/calculated 상태에서 null 반환', () {
      expect(_makeAttendance(wageStatus: AttendanceModel.wagePending, finalWage: 95000).displayWage, isNull);
      expect(_makeAttendance(wageStatus: AttendanceModel.wageCalculated, finalWage: 95000).displayWage, isNull);
    });

    test('SCENARIO-PAY-C09: confirmed→calculated 재계산 요청 — wageStatus 리셋', () {
      final confirmed = _makeAttendance(wageStatus: AttendanceModel.wageConfirmed);
      // 관리자가 재계산 요청 시 calculated로 되돌림
      final recalc = confirmed.copyWith(wageStatus: AttendanceModel.wageCalculated);
      expect(recalc.isWageCalculated, isTrue);
      expect(recalc.isWageConfirmed, isFalse);
    });

    test('SCENARIO-PAY-C10: transferred 상태에서 기존 transferDate 유지 확인', () {
      final transferDate = DateTime(2026, 7, 25, 14, 0);
      final att = _makeAttendance(
        wageStatus: AttendanceModel.wageTransferred,
        transferDate: transferDate,
        transferredBy: 'admin-001',
      );
      expect(att.transferDate, transferDate);
      expect(att.transferredBy, 'admin-001');
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // D. 이체 취소 상태 검증 (cancelTransfer 로직 시뮬레이션)
  // ────────────────────────────────────────────────────────────────────────────
  group('SCENARIO-PAY-D: 이체 취소 상태 검증', () {
    test('SCENARIO-PAY-D01: transferred → confirmed 역전환 (copyWith 시뮬레이션)', () {
      final transferred = _makeAttendance(
        wageStatus: AttendanceModel.wageTransferred,
        transferDate: DateTime(2026, 7, 25),
        transferredBy: 'admin-001',
        finalWage: 95000,
      );
      // cancelTransfer 후 상태 시뮬레이션
      final cancelled = transferred.copyWith(
        wageStatus: AttendanceModel.wageConfirmed,
      );
      expect(cancelled.wageStatus, AttendanceModel.wageConfirmed);
      expect(cancelled.isWageConfirmed, isTrue);
    });

    test('SCENARIO-PAY-D02: 이체 취소 후 finalWage 유지 — 급여 금액 보존', () {
      final transferred = _makeAttendance(
        wageStatus: AttendanceModel.wageTransferred,
        finalWage: 95000,
      );
      final cancelled = transferred.copyWith(wageStatus: AttendanceModel.wageConfirmed);
      expect(cancelled.finalWage, 95000);
    });

    test('SCENARIO-PAY-D03: 이체 취소 후 wageDetail 유지 — 계산 데이터 보존', () {
      final wageDetail = _makeWageDetail(totalAmount: 100000, netWage: 95000);
      final transferred = _makeAttendance(
        wageStatus: AttendanceModel.wageTransferred,
        wageDetail: wageDetail,
      );
      final cancelled = transferred.copyWith(wageStatus: AttendanceModel.wageConfirmed);
      expect(cancelled.wageDetail?.totalAmount, 100000);
      expect(cancelled.wageDetail?.netWage, 95000);
    });

    test('SCENARIO-PAY-D04: 이미 confirmed 상태에서 취소 시도 — 상태 전이 안 일어남', () {
      final confirmed = _makeAttendance(wageStatus: AttendanceModel.wageConfirmed);
      // cancelTransfer 서비스는 wageTransferred가 아니면 Exception 발생
      // 모델 레벨: 이미 confirmed이면 상태 변경이 의미 없음을 검증
      expect(confirmed.isWageTransferred, isFalse);
      expect(() {
        if (confirmed.wageStatus != AttendanceModel.wageTransferred) {
          throw Exception('이체 완료 상태가 아닙니다 (현재: ${confirmed.wageStatus})');
        }
      }, throwsException);
    });

    test('SCENARIO-PAY-D05: 이미 cancelled(confirmed) 상태에서 중복 취소 방어', () {
      // wageTransferred가 아닌 경우 모두 취소 불가
      final alreadyCancelled = _makeAttendance(wageStatus: AttendanceModel.wageConfirmed);
      bool wouldThrow = false;
      if (alreadyCancelled.wageStatus != AttendanceModel.wageTransferred) {
        wouldThrow = true;
      }
      expect(wouldThrow, isTrue);
    });

    test('SCENARIO-PAY-D06: notTransferredCount 재집계 — 취소 후 confirmed 수 증가', () {
      // 이체 취소 전: confirmed=2, transferred=3
      final records = [
        _makeAttendance(id: 'att-1', wageStatus: AttendanceModel.wageConfirmed),
        _makeAttendance(id: 'att-2', wageStatus: AttendanceModel.wageConfirmed),
        _makeAttendance(id: 'att-3', wageStatus: AttendanceModel.wageTransferred),
        _makeAttendance(id: 'att-4', wageStatus: AttendanceModel.wageTransferred),
        _makeAttendance(id: 'att-5', wageStatus: AttendanceModel.wageTransferred),
      ];
      expect(_computeNotTransferredCount(records), 2);

      // 이체 취소 후: att-3을 confirmed로
      final updated = records.map((r) {
        if (r.id == 'att-3') return r.copyWith(wageStatus: AttendanceModel.wageConfirmed);
        return r;
      }).toList();
      expect(_computeNotTransferredCount(updated), 3);
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // E. 단건 이체 전제조건 검증
  // ────────────────────────────────────────────────────────────────────────────
  group('SCENARIO-PAY-E: 단건 이체 상태 전제조건 검증', () {
    test('SCENARIO-PAY-E01: confirmed 상태만 이체 가능 — 상태 체크 통과', () {
      final att = _makeAttendance(wageStatus: AttendanceModel.wageConfirmed);
      // markTransferred 내부 로직: wageConfirmed가 아니면 throw
      expect(att.wageStatus, AttendanceModel.wageConfirmed);
      // 상태 체크 통과 = 예외 없음
      String? error;
      if (att.wageStatus != AttendanceModel.wageConfirmed) {
        error = '확정된 급여만 이체 처리할 수 있습니다.';
      }
      expect(error, isNull);
    });

    test('SCENARIO-PAY-E02: pending 상태 → 이체 불가 (에러 발생 경로)', () {
      final att = _makeAttendance(wageStatus: AttendanceModel.wagePending);
      String? error;
      if (att.wageStatus != AttendanceModel.wageConfirmed) {
        error = '확정된 급여만 이체 처리할 수 있습니다. (현재 상태: ${att.wageStatus})';
      }
      expect(error, isNotNull);
      expect(error, contains('pending'));
    });

    test('SCENARIO-PAY-E03: calculated 상태 → 이체 불가', () {
      final att = _makeAttendance(wageStatus: AttendanceModel.wageCalculated);
      String? error;
      if (att.wageStatus != AttendanceModel.wageConfirmed) {
        error = '확정된 급여만 이체 처리할 수 있습니다. (현재 상태: ${att.wageStatus})';
      }
      expect(error, isNotNull);
      expect(error, contains('calculated'));
    });

    test('SCENARIO-PAY-E04: transferred 상태 → 중복 이체 불가', () {
      final att = _makeAttendance(wageStatus: AttendanceModel.wageTransferred);
      String? error;
      if (att.wageStatus != AttendanceModel.wageConfirmed) {
        error = '확정된 급여만 이체 처리할 수 있습니다. (현재 상태: ${att.wageStatus})';
      }
      expect(error, isNotNull);
      expect(error, contains('transferred'));
    });

    test('SCENARIO-PAY-E05: 이체 완료 후 transferredBy + wageTransferred 설정', () {
      final att = _makeAttendance(wageStatus: AttendanceModel.wageConfirmed);
      final transferred = att.copyWith(
        wageStatus: AttendanceModel.wageTransferred,
        transferDate: DateTime(2026, 7, 25),
        transferredBy: 'admin-001',
        transferNote: '7월 급여',
      );
      expect(transferred.isWageTransferred, isTrue);
      expect(transferred.transferredBy, 'admin-001');
      expect(transferred.transferNote, '7월 급여');
      expect(transferred.transferDate, isNotNull);
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // F. 일괄 이체 WriteBatch 청크 분할 (450건 단위)
  // ────────────────────────────────────────────────────────────────────────────
  group('SCENARIO-PAY-F: 일괄 이체 WriteBatch 청크 분할', () {
    test('SCENARIO-PAY-F01: 0건 → 청크 0개', () {
      final batches = _splitIntoBatches([]);
      expect(batches.length, 0);
    });

    test('SCENARIO-PAY-F02: 1건 → 청크 1개 (크기 1)', () {
      final ids = List.generate(1, (i) => 'att-$i');
      final batches = _splitIntoBatches(ids);
      expect(batches.length, 1);
      expect(batches[0].length, 1);
    });

    test('SCENARIO-PAY-F03: 450건 정확히 → 청크 1개', () {
      final ids = List.generate(450, (i) => 'att-$i');
      final batches = _splitIntoBatches(ids);
      expect(batches.length, 1);
      expect(batches[0].length, 450);
    });

    test('SCENARIO-PAY-F04: 451건 → 청크 2개 (450 + 1)', () {
      final ids = List.generate(451, (i) => 'att-$i');
      final batches = _splitIntoBatches(ids);
      expect(batches.length, 2);
      expect(batches[0].length, 450);
      expect(batches[1].length, 1);
    });

    test('SCENARIO-PAY-F05: 500건 → 청크 2개 (450 + 50)', () {
      final ids = List.generate(500, (i) => 'att-$i');
      final batches = _splitIntoBatches(ids);
      expect(batches.length, 2);
      expect(batches[0].length, 450);
      expect(batches[1].length, 50);
    });

    test('SCENARIO-PAY-F06: 900건 → 청크 2개 (450 + 450)', () {
      final ids = List.generate(900, (i) => 'att-$i');
      final batches = _splitIntoBatches(ids);
      expect(batches.length, 2);
      expect(batches[0].length, 450);
      expect(batches[1].length, 450);
    });

    test('SCENARIO-PAY-F07: 901건 → 청크 3개 (450 + 450 + 1)', () {
      final ids = List.generate(901, (i) => 'att-$i');
      final batches = _splitIntoBatches(ids);
      expect(batches.length, 3);
      expect(batches[0].length, 450);
      expect(batches[1].length, 450);
      expect(batches[2].length, 1);
    });

    test('SCENARIO-PAY-F08: 청크 내 ID 순서 보존 — 전체 IDs와 일치', () {
      final ids = List.generate(500, (i) => 'att-${i.toString().padLeft(3, '0')}');
      final batches = _splitIntoBatches(ids);
      final reconstructed = batches.expand((b) => b).toList();
      expect(reconstructed, equals(ids));
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // G. 중간정산 요청 (InterimSettlementRequestModel)
  // ────────────────────────────────────────────────────────────────────────────
  group('SCENARIO-PAY-G: 중간정산 요청 모델 및 상태 전이', () {
    test('SCENARIO-PAY-G01: isPending getter — PENDING 상태에서 true', () {
      final req = _makeSettlementRequest(status: InterimSettlementRequestModel.statusPending);
      expect(req.isPending, isTrue);
      expect(req.isApproved, isFalse);
      expect(req.isRejected, isFalse);
      expect(req.isProcessed, isFalse);
    });

    test('SCENARIO-PAY-G02: statusLabel — PENDING → "처리 대기"', () {
      final req = _makeSettlementRequest(status: InterimSettlementRequestModel.statusPending);
      expect(req.statusLabel, '처리 대기');
    });

    test('SCENARIO-PAY-G03: statusLabel — APPROVED → "승인 (이체 대기)"', () {
      final req = _makeSettlementRequest(status: InterimSettlementRequestModel.statusApproved);
      expect(req.statusLabel, '승인 (이체 대기)');
    });

    test('SCENARIO-PAY-G04: statusLabel — REJECTED → "거절"', () {
      final req = _makeSettlementRequest(status: InterimSettlementRequestModel.statusRejected);
      expect(req.statusLabel, '거절');
    });

    test('SCENARIO-PAY-G05: statusLabel — PROCESSED → "정산 완료"', () {
      final req = _makeSettlementRequest(status: InterimSettlementRequestModel.statusProcessed);
      expect(req.statusLabel, '정산 완료');
    });

    test('SCENARIO-PAY-G06: periodLabel 형식 검증 (5/1 ~ 5/15)', () {
      final req = InterimSettlementRequestModel(
        id: 'settle-001',
        applicationId: 'app-001',
        businessId: 'biz-001',
        businessName: '테스트 사업장',
        workerId: 'user-001',
        workerName: '홍길동',
        periodStart: DateTime(2026, 5, 1),
        periodEnd: DateTime(2026, 5, 15),
        attendanceIds: ['att-001'],
        requestedAmount: 100000,
        netAmount: 95000,
        status: InterimSettlementRequestModel.statusPending,
        createdAt: DateTime(2026, 5, 15, 10, 0),
      );
      expect(req.periodLabel, '5/1 ~ 5/15');
    });

    test('SCENARIO-PAY-G07: recordCount = attendanceIds.length', () {
      final req = _makeSettlementRequest(attendanceIds: ['att-1', 'att-2', 'att-3']);
      expect(req.recordCount, 3);
    });

    test('SCENARIO-PAY-G08: rejected → attendance 상태 변경 없음 (모델 검증)', () {
      final req = _makeSettlementRequest(status: InterimSettlementRequestModel.statusRejected);
      // rejected 시 attendanceIds는 그대로 유지
      expect(req.attendanceIds, hasLength(2));
      expect(req.isRejected, isTrue);
    });

    test('SCENARIO-PAY-G09: 승인 후 attendanceIds의 출근기록 → wageTransferred 일괄 처리 시뮬레이션', () {
      final attendances = [
        _makeAttendance(id: 'att-1', wageStatus: AttendanceModel.wageConfirmed),
        _makeAttendance(id: 'att-2', wageStatus: AttendanceModel.wageConfirmed),
      ];
      final req = _makeSettlementRequest(attendanceIds: ['att-1', 'att-2']);

      // 승인: wageConfirmed → wageTransferred 일괄 전환
      final processedAttendances = attendances.map((a) {
        if (req.attendanceIds.contains(a.id)) {
          return a.copyWith(wageStatus: AttendanceModel.wageTransferred);
        }
        return a;
      }).toList();

      expect(processedAttendances.every((a) => a.isWageTransferred), isTrue);
    });

    test('SCENARIO-PAY-G10: 이미 transferred인 attendance 중복 정산 방어 (skipMarkTransferred 로직)', () {
      final attendances = [
        _makeAttendance(id: 'att-1', wageStatus: AttendanceModel.wageTransferred),
        _makeAttendance(id: 'att-2', wageStatus: AttendanceModel.wageTransferred),
      ];
      // approveInterimSettlement 내부: allTransferred → skipMarkTransferred=true
      final allTransferred = attendances.every((a) => a.isWageTransferred);
      expect(allTransferred, isTrue); // 중복 이체 건너뜀 경로로 진입
    });

    test('SCENARIO-PAY-G11: wageConfirmed만 이체 대상 — wagePending 제외 로직', () {
      final attendances = [
        _makeAttendance(id: 'att-1', wageStatus: AttendanceModel.wageConfirmed),
        _makeAttendance(id: 'att-2', wageStatus: AttendanceModel.wagePending),
        _makeAttendance(id: 'att-3', wageStatus: AttendanceModel.wageConfirmed),
      ];
      // approveInterimSettlement: wageConfirmed만 idsToTransfer에 포함
      final idsToTransfer = attendances
          .where((a) => a.wageStatus == AttendanceModel.wageConfirmed)
          .map((a) => a.id)
          .toList();
      expect(idsToTransfer, containsAll(['att-1', 'att-3']));
      expect(idsToTransfer, isNot(contains('att-2')));
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // H. 월별 필터링
  // ────────────────────────────────────────────────────────────────────────────
  group('SCENARIO-PAY-H: 월별 필터링 (yearMonth 기반)', () {
    test('SCENARIO-PAY-H01: 7월 attendance만 필터링', () {
      final records = [
        _makeAttendance(id: 'att-1', yearMonth: '2026-07'),
        _makeAttendance(id: 'att-2', yearMonth: '2026-07'),
        _makeAttendance(id: 'att-3', yearMonth: '2026-06'),
        _makeAttendance(id: 'att-4', yearMonth: '2026-08'),
      ];
      final july = records.where((r) => r.yearMonth == '2026-07').toList();
      expect(july.length, 2);
      expect(july.map((r) => r.id), containsAll(['att-1', 'att-2']));
    });

    test('SCENARIO-PAY-H02: 이전 달(6월) attendance 제외', () {
      final records = [
        _makeAttendance(id: 'att-1', yearMonth: '2026-06'),
        _makeAttendance(id: 'att-2', yearMonth: '2026-07'),
      ];
      final july = records.where((r) => r.yearMonth == '2026-07').toList();
      expect(july.length, 1);
      expect(july.first.id, 'att-2');
    });

    test('SCENARIO-PAY-H03: 다음 달(8월) attendance 제외', () {
      final records = [
        _makeAttendance(id: 'att-1', yearMonth: '2026-08'),
        _makeAttendance(id: 'att-2', yearMonth: '2026-07'),
      ];
      final july = records.where((r) => r.yearMonth == '2026-07').toList();
      expect(july.length, 1);
      expect(july.first.id, 'att-2');
    });

    test('SCENARIO-PAY-H04: 빈 달 → 결과 0건', () {
      final records = [
        _makeAttendance(id: 'att-1', yearMonth: '2026-06'),
        _makeAttendance(id: 'att-2', yearMonth: '2026-08'),
      ];
      final july = records.where((r) => r.yearMonth == '2026-07').toList();
      expect(july, isEmpty);
    });

    test('SCENARIO-PAY-H05: yearMonth=null인 attendance — 7월 필터에서 제외', () {
      final records = [
        _makeAttendance(id: 'att-1', yearMonth: null),
        _makeAttendance(id: 'att-2', yearMonth: '2026-07'),
      ];
      final july = records.where((r) => r.yearMonth == '2026-07').toList();
      expect(july.length, 1);
      expect(july.first.id, 'att-2');
    });

    test('SCENARIO-PAY-H06: workDate 기반 필터링 (getPayrollRecords 쿼리 시뮬레이션)', () {
      final monthStart = DateTime(2026, 7, 1);
      final monthEnd = DateTime(2026, 8, 1);

      final records = [
        _makeAttendance(id: 'att-1', workDate: DateTime(2026, 7, 1)),
        _makeAttendance(id: 'att-2', workDate: DateTime(2026, 7, 31)),
        _makeAttendance(id: 'att-3', workDate: DateTime(2026, 6, 30)),
        _makeAttendance(id: 'att-4', workDate: DateTime(2026, 8, 1)),
      ];
      final july = records.where((r) =>
          !r.workDate.isBefore(monthStart) && r.workDate.isBefore(monthEnd)).toList();
      expect(july.length, 2);
      expect(july.map((r) => r.id), containsAll(['att-1', 'att-2']));
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // I. CSV Injection 방어
  // ────────────────────────────────────────────────────────────────────────────
  group('SCENARIO-PAY-I: CSV Injection 방어 (generateTransferCsv)', () {
    TransferRow _makeRow({
      String workerName = '홍길동',
      String bankName = '국민은행',
      String accountNumber = '123-456-789',
      String accountHolder = '홍길동',
      int netAmount = 95000,
      String memo = '7월 급여',
    }) {
      return TransferRow(
        workerName: workerName,
        bankName: bankName,
        accountNumber: accountNumber,
        accountHolder: accountHolder,
        netAmount: netAmount,
        memo: memo,
      );
    }

    test('SCENARIO-PAY-I01: 이름에 "=SUM(A1)" 포함 시 작은따옴표 접두어 적용', () {
      final csv = PayrollPaymentService.generateTransferCsv(
          [_makeRow(workerName: '=SUM(A1)')]);
      expect(csv, contains("'=SUM(A1)"));
    });

    test('SCENARIO-PAY-I02: 이름이 "+" 시작 시 작은따옴표 접두어', () {
      final csv = PayrollPaymentService.generateTransferCsv(
          [_makeRow(workerName: '+홍길동')]);
      expect(csv, contains("'+홍길동"));
    });

    test('SCENARIO-PAY-I03: 이름이 "-" 시작 시 작은따옴표 접두어', () {
      final csv = PayrollPaymentService.generateTransferCsv(
          [_makeRow(workerName: '-홍길동')]);
      expect(csv, contains("'-홍길동"));
    });

    test('SCENARIO-PAY-I04: 이름이 "@" 시작 시 작은따옴표 접두어', () {
      final csv = PayrollPaymentService.generateTransferCsv(
          [_makeRow(workerName: '@홍길동')]);
      expect(csv, contains("'@홍길동"));
    });

    test('SCENARIO-PAY-I05: 일반 이름 → 변경 없음', () {
      final csv = PayrollPaymentService.generateTransferCsv(
          [_makeRow(workerName: '홍길동')]);
      expect(csv, contains('"홍길동"'));
      expect(csv, isNot(contains("'홍길동")));
    });

    test('SCENARIO-PAY-I06: 빈 이름 → 빈 문자열 (접두어 없음)', () {
      final csv = PayrollPaymentService.generateTransferCsv(
          [_makeRow(workerName: '')]);
      // 빈 문자열은 접두어 없이 그대로
      expect(csv, contains('""'));
    });

    test('SCENARIO-PAY-I07: 메모에 "=" 포함 시 접두어 적용', () {
      final csv = PayrollPaymentService.generateTransferCsv(
          [_makeRow(memo: '=CMD()')]);
      expect(csv, contains("'=CMD()"));
    });

    test('SCENARIO-PAY-I08: CSV 헤더 행 포함 검증', () {
      final csv = PayrollPaymentService.generateTransferCsv([]);
      expect(csv, startsWith('이름,은행명,계좌번호,예금주,이체금액,메모'));
    });

    test('SCENARIO-PAY-I09: 복수 행 CSV — 모든 행 포함', () {
      final rows = [
        _makeRow(workerName: '홍길동', netAmount: 100000),
        _makeRow(workerName: '김철수', netAmount: 200000),
      ];
      final csv = PayrollPaymentService.generateTransferCsv(rows);
      expect(csv, contains('홍길동'));
      expect(csv, contains('김철수'));
      expect(csv, contains('100000'));
      expect(csv, contains('200000'));
    });

    test('SCENARIO-PAY-I10: 은행명에 "+" 포함 시 접두어 적용', () {
      final csv = PayrollPaymentService.generateTransferCsv(
          [_makeRow(bankName: '+카카오뱅크')]);
      expect(csv, contains("'+카카오뱅크"));
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // J. 퀵필터 로직
  // ────────────────────────────────────────────────────────────────────────────
  group('SCENARIO-PAY-J: 퀵필터 로직 (연체·오늘마감·계좌없음)', () {
    final today = DateTime(2026, 7, 8); // 고정 기준일

    test('SCENARIO-PAY-J01: 연체 필터 — paymentDueDate < today AND confirmed', () {
      final recs = [
        _makeAttendance(
          id: 'att-1',
          wageStatus: AttendanceModel.wageConfirmed,
          paymentDueDate: DateTime(2026, 7, 5), // 3일 전 = 연체
        ),
      ];
      expect(_isOverdue(recs, today), isTrue);
    });

    test('SCENARIO-PAY-J02: 오늘마감 필터 — paymentDueDate == today', () {
      final recs = [
        _makeAttendance(
          id: 'att-1',
          wageStatus: AttendanceModel.wageConfirmed,
          paymentDueDate: DateTime(2026, 7, 8, 23, 59), // 오늘 23:59
        ),
      ];
      expect(_isDueToday(recs, today), isTrue);
      expect(_isOverdue(recs, today), isFalse);
    });

    test('SCENARIO-PAY-J03: 미래 마감 → 연체/오늘마감 필터 모두 false', () {
      final recs = [
        _makeAttendance(
          id: 'att-1',
          wageStatus: AttendanceModel.wageConfirmed,
          paymentDueDate: DateTime(2026, 7, 25), // 17일 후
        ),
      ];
      expect(_isOverdue(recs, today), isFalse);
      expect(_isDueToday(recs, today), isFalse);
    });

    test('SCENARIO-PAY-J04: paymentDueDate=null → 연체/오늘마감 필터 false', () {
      final recs = [
        _makeAttendance(
          id: 'att-1',
          wageStatus: AttendanceModel.wageConfirmed,
        ),
      ];
      expect(_isOverdue(recs, today), isFalse);
      expect(_isDueToday(recs, today), isFalse);
    });

    test('SCENARIO-PAY-J05: 계좌없음 필터 — bankName 빈 문자열 → true', () {
      final bankCache = <String, Map<String, String>>{
        'user-001': {'bankName': '', 'accountNumber': ''},
      };
      expect(_hasNoAccount('user-001', bankCache), isTrue);
    });

    test('SCENARIO-PAY-J06: 계좌있음 — bankName 비어있지 않으면 false', () {
      final bankCache = <String, Map<String, String>>{
        'user-001': {'bankName': '국민은행', 'accountNumber': '123-456'},
      };
      expect(_hasNoAccount('user-001', bankCache), isFalse);
    });

    test('SCENARIO-PAY-J07: 계좌없음 필터 — bankCache에 uid 없음 → true', () {
      final bankCache = <String, Map<String, String>>{};
      expect(_hasNoAccount('user-999', bankCache), isTrue);
    });

    test('SCENARIO-PAY-J08: 연체 AND 계좌없음 조합 필터', () {
      final bankCache = <String, Map<String, String>>{
        'user-001': {'bankName': ''},
      };
      final recs = [
        _makeAttendance(
          id: 'att-1',
          userId: 'user-001',
          wageStatus: AttendanceModel.wageConfirmed,
          paymentDueDate: DateTime(2026, 7, 5),
        ),
      ];
      final isOverdueAndNoAccount =
          _isOverdue(recs, today) && _hasNoAccount('user-001', bankCache);
      expect(isOverdueAndNoAccount, isTrue);
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // K. 집계 정합성 (PayrollSummaryModel 집계 로직)
  // ────────────────────────────────────────────────────────────────────────────
  group('SCENARIO-PAY-K: 집계 정합성 검증', () {
    test('SCENARIO-PAY-K01: 빈 리스트 → totalPayout=0, 모든 카운트=0', () {
      final records = <AttendanceModel>[];
      expect(_computeTotalPayout(records), 0);
      expect(_computePendingCount(records), 0);
      expect(_computeNotTransferredCount(records), 0);
      expect(_computeWorkerCount(records), 0);
    });

    test('SCENARIO-PAY-K02: pending N건 → pendingCount=N, totalPayout=0', () {
      final records = List.generate(
        5,
        (i) => _makeAttendance(
          id: 'att-$i',
          wageStatus: AttendanceModel.wagePending,
          wageDetail: _makeWageDetail(netWage: 95000),
        ),
      );
      expect(_computePendingCount(records), 5);
      expect(_computeTotalPayout(records), 0); // pending은 totalPayout 미포함
    });

    test('SCENARIO-PAY-K03: calculated M건 → pendingCount에 포함', () {
      final records = [
        _makeAttendance(id: 'att-1', wageStatus: AttendanceModel.wagePending),
        _makeAttendance(id: 'att-2', wageStatus: AttendanceModel.wageCalculated),
        _makeAttendance(id: 'att-3', wageStatus: AttendanceModel.wageCalculated),
      ];
      expect(_computePendingCount(records), 3); // pending + calculated 합산
    });

    test('SCENARIO-PAY-K04: confirmed + transferred 혼합 → 각 카운트 정확', () {
      final wd = _makeWageDetail(netWage: 90000, calculatedAt: DateTime(2026, 7, 10));
      final records = [
        _makeAttendance(id: 'att-1', wageStatus: AttendanceModel.wagePending),
        _makeAttendance(id: 'att-2', wageStatus: AttendanceModel.wageCalculated),
        _makeAttendance(id: 'att-3', wageStatus: AttendanceModel.wageConfirmed, wageDetail: wd),
        _makeAttendance(id: 'att-4', wageStatus: AttendanceModel.wageConfirmed, wageDetail: wd),
        _makeAttendance(id: 'att-5', wageStatus: AttendanceModel.wageTransferred, wageDetail: wd),
      ];
      expect(_computePendingCount(records), 2);        // pending + calculated
      expect(_computeNotTransferredCount(records), 2); // confirmed만
      expect(_computeTotalPayout(records), 270000);    // confirmed(2)+transferred(1) = 3×90000
    });

    test('SCENARIO-PAY-K05: transferred 건 → notTransferredCount에서 제외', () {
      final records = [
        _makeAttendance(id: 'att-1', wageStatus: AttendanceModel.wageConfirmed),
        _makeAttendance(id: 'att-2', wageStatus: AttendanceModel.wageTransferred),
        _makeAttendance(id: 'att-3', wageStatus: AttendanceModel.wageTransferred),
      ];
      expect(_computeNotTransferredCount(records), 1);
    });

    test('SCENARIO-PAY-K06: workerCount 중복 제거 — 동일 userId 여러 건', () {
      final records = [
        _makeAttendance(id: 'att-1', userId: 'user-001'),
        _makeAttendance(id: 'att-2', userId: 'user-001'),
        _makeAttendance(id: 'att-3', userId: 'user-002'),
      ];
      expect(_computeWorkerCount(records), 2); // user-001 중복 제거
    });

    test('SCENARIO-PAY-K07: totalPayout = confirmed+transferred의 effectiveNetWage 합산', () {
      final wd1 = _makeWageDetail(
          netWage: 100000, calculatedAt: DateTime(2026, 7, 10));
      final wd2 = _makeWageDetail(
          netWage: 200000, calculatedAt: DateTime(2026, 7, 10));
      final records = [
        _makeAttendance(id: 'att-1', wageStatus: AttendanceModel.wageConfirmed, wageDetail: wd1),
        _makeAttendance(id: 'att-2', wageStatus: AttendanceModel.wageTransferred, wageDetail: wd2),
        _makeAttendance(id: 'att-3', wageStatus: AttendanceModel.wagePending, wageDetail: wd1),
      ];
      expect(_computeTotalPayout(records), 300000); // 100000 + 200000, pending 제외
    });

    test('SCENARIO-PAY-K08: 근무자별 totalPayout 집계', () {
      final wd = _makeWageDetail(netWage: 50000, calculatedAt: DateTime(2026, 7, 10));
      final records = [
        _makeAttendance(id: 'att-1', userId: 'user-001', wageStatus: AttendanceModel.wageConfirmed, wageDetail: wd),
        _makeAttendance(id: 'att-2', userId: 'user-001', wageStatus: AttendanceModel.wageConfirmed, wageDetail: wd),
        _makeAttendance(id: 'att-3', userId: 'user-002', wageStatus: AttendanceModel.wageConfirmed, wageDetail: wd),
      ];
      final payoutByWorker = _computeWorkerTotalPayout(records);
      expect(payoutByWorker['user-001'], 100000); // 2건 × 50000
      expect(payoutByWorker['user-002'], 50000);
    });

    test('SCENARIO-PAY-K09: isZeroWork=true → 근무일수 집계 제외', () {
      final records = [
        _makeAttendance(id: 'att-1', userId: 'user-001', isZeroWork: false),
        _makeAttendance(id: 'att-2', userId: 'user-001', isZeroWork: true),  // 제외
        _makeAttendance(id: 'att-3', userId: 'user-001', isZeroWork: false),
      ];
      final workDays = _computeWorkerWorkDays(records);
      expect(workDays['user-001'], 2); // isZeroWork=true 제외
    });

    test('SCENARIO-PAY-K10: PayrollWorkerSummary fromMap — 필드 파싱', () {
      final w = PayrollWorkerSummary.fromMap('user-001', {
        'name': '홍길동',
        'totalPayout': 300000,
        'workDays': 5,
      });
      expect(w.workerId, 'user-001');
      expect(w.name, '홍길동');
      expect(w.totalPayout, 300000);
      expect(w.workDays, 5);
    });

    test('SCENARIO-PAY-K11: PayrollWorkerSummary tryFromMap — 손상 데이터 null 반환 (크래시 방지)', () {
      // name 필드에 int(123) 전달 → "as String?" 캐스팅 실패 → tryFromMap이 null 반환
      // 목적: 손상 문서 1건이 목록 전체를 크래시시키지 않음을 확인
      final w = PayrollWorkerSummary.tryFromMap('user-001', {
        'name': 123, // int → String? 캐스팅 실패 → try-catch에서 null 반환
        'totalPayout': 300000,
        'workDays': 5,
      });
      expect(w, isNull); // tryFromMap은 실패 시 null 반환 — 크래시 방지 동작 확인
    });

    test('SCENARIO-PAY-K12: PayrollWorkerSummary tryFromMap — 정상 데이터는 null 아님', () {
      final w = PayrollWorkerSummary.tryFromMap('user-001', {
        'name': '홍길동',
        'totalPayout': 300000,
        'workDays': 5,
      });
      expect(w, isNotNull);
      expect(w!.name, '홍길동');
      expect(w.totalPayout, 300000);
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // PayrollSummaryModel 집계 통합 시나리오
  // ────────────────────────────────────────────────────────────────────────────
  group('SCENARIO-PAY-L: PayrollSummaryModel 집계 통합 시나리오', () {
    test('SCENARIO-PAY-L01: 50건 혼합 → 집계 정합성 전체 검증', () {
      // pending 10, calculated 5, confirmed 20, transferred 15
      final wd = _makeWageDetail(netWage: 100000, calculatedAt: DateTime(2026, 7, 10));
      final records = [
        ...List.generate(10, (i) => _makeAttendance(
            id: 'p-$i', userId: 'user-${i % 3}', wageStatus: AttendanceModel.wagePending)),
        ...List.generate(5, (i) => _makeAttendance(
            id: 'c-$i', userId: 'user-${i % 2}', wageStatus: AttendanceModel.wageCalculated)),
        ...List.generate(20, (i) => _makeAttendance(
            id: 'cf-$i', userId: 'user-${i % 4}', wageStatus: AttendanceModel.wageConfirmed, wageDetail: wd)),
        ...List.generate(15, (i) => _makeAttendance(
            id: 't-$i', userId: 'user-${i % 5}', wageStatus: AttendanceModel.wageTransferred, wageDetail: wd)),
      ];

      expect(records.length, 50);
      expect(_computePendingCount(records), 15);         // pending+calculated
      expect(_computeNotTransferredCount(records), 20);  // confirmed만
      expect(_computeTotalPayout(records), 3500000);     // (20+15)×100000
    });

    test('SCENARIO-PAY-L02: 전체 transferred → notTransferredCount=0', () {
      final wd = _makeWageDetail(netWage: 80000, calculatedAt: DateTime(2026, 7, 10));
      final records = List.generate(
        10,
        (i) => _makeAttendance(
            id: 'att-$i', wageStatus: AttendanceModel.wageTransferred, wageDetail: wd),
      );
      expect(_computeNotTransferredCount(records), 0);
      expect(_computeTotalPayout(records), 800000);
    });

    test('SCENARIO-PAY-L03: 전체 pending → totalPayout=0, notTransferredCount=0', () {
      final records = List.generate(
        5,
        (i) => _makeAttendance(id: 'att-$i', wageStatus: AttendanceModel.wagePending),
      );
      expect(_computeTotalPayout(records), 0);
      expect(_computeNotTransferredCount(records), 0);
      expect(_computePendingCount(records), 5);
    });
  });
}
