// test/unit/interim_settlement_request_model_test.dart
// InterimSettlementRequestModel getter / label 단위 테스트
//
// fromFirestore/fromMap은 Timestamp 의존 → 생략.
// 생성자에서 직접 DateTime을 받으므로 Firebase 없이 테스트 가능.

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/interim_settlement_request_model.dart';

InterimSettlementRequestModel _make({
  String status = InterimSettlementRequestModel.statusPending,
  List<String> attendanceIds = const [],
  DateTime? periodStart,
  DateTime? periodEnd,
}) {
  final now = DateTime(2026, 6, 1);
  return InterimSettlementRequestModel(
    id: 'isr-001',
    applicationId: 'app-001',
    businessId: 'biz-001',
    businessName: '테스트 사업장',
    workerId: 'uid-001',
    workerName: '홍길동',
    periodStart: periodStart ?? DateTime(2026, 5, 1),
    periodEnd: periodEnd ?? DateTime(2026, 5, 15),
    attendanceIds: attendanceIds,
    requestedAmount: 500000,
    netAmount: 480000,
    status: status,
    createdAt: now,
  );
}

void main() {
  // ══════════════════════════════════════════════════════
  // 상태 Boolean getter
  // ══════════════════════════════════════════════════════
  group('InterimSettlementRequestModel: 상태 getter', () {
    test('PENDING 상태', () {
      final m = _make(status: InterimSettlementRequestModel.statusPending);
      expect(m.isPending,   isTrue);
      expect(m.isApproved,  isFalse);
      expect(m.isRejected,  isFalse);
      expect(m.isProcessed, isFalse);
    });

    test('APPROVED 상태', () {
      final m = _make(status: InterimSettlementRequestModel.statusApproved);
      expect(m.isPending,   isFalse);
      expect(m.isApproved,  isTrue);
      expect(m.isRejected,  isFalse);
      expect(m.isProcessed, isFalse);
    });

    test('REJECTED 상태', () {
      final m = _make(status: InterimSettlementRequestModel.statusRejected);
      expect(m.isPending,   isFalse);
      expect(m.isApproved,  isFalse);
      expect(m.isRejected,  isTrue);
      expect(m.isProcessed, isFalse);
    });

    test('PROCESSED 상태', () {
      final m = _make(status: InterimSettlementRequestModel.statusProcessed);
      expect(m.isPending,   isFalse);
      expect(m.isApproved,  isFalse);
      expect(m.isRejected,  isFalse);
      expect(m.isProcessed, isTrue);
    });
  });

  // ══════════════════════════════════════════════════════
  // statusLabel
  // ══════════════════════════════════════════════════════
  group('InterimSettlementRequestModel: statusLabel', () {
    test('PENDING → 처리 대기', () {
      expect(_make(status: InterimSettlementRequestModel.statusPending).statusLabel, equals('처리 대기'));
    });

    test('APPROVED → 승인 (이체 대기)', () {
      expect(_make(status: InterimSettlementRequestModel.statusApproved).statusLabel, equals('승인 (이체 대기)'));
    });

    test('REJECTED → 거절', () {
      expect(_make(status: InterimSettlementRequestModel.statusRejected).statusLabel, equals('거절'));
    });

    test('PROCESSED → 정산 완료', () {
      expect(_make(status: InterimSettlementRequestModel.statusProcessed).statusLabel, equals('정산 완료'));
    });

    test('알 수 없는 status → status 문자열 그대로 반환', () {
      expect(_make(status: 'UNKNOWN_STATE').statusLabel, equals('UNKNOWN_STATE'));
    });
  });

  // ══════════════════════════════════════════════════════
  // periodLabel
  // ══════════════════════════════════════════════════════
  group('InterimSettlementRequestModel: periodLabel', () {
    test('같은 달 5/1 ~ 5/15 → "5/1 ~ 5/15"', () {
      final m = _make(
        periodStart: DateTime(2026, 5, 1),
        periodEnd: DateTime(2026, 5, 15),
      );
      expect(m.periodLabel, equals('5/1 ~ 5/15'));
    });

    test('달 넘김 5/25 ~ 6/5 → "5/25 ~ 6/5"', () {
      final m = _make(
        periodStart: DateTime(2026, 5, 25),
        periodEnd: DateTime(2026, 6, 5),
      );
      expect(m.periodLabel, equals('5/25 ~ 6/5'));
    });

    test('연도 넘김 12/28 ~ 1/3 → "12/28 ~ 1/3"', () {
      final m = _make(
        periodStart: DateTime(2026, 12, 28),
        periodEnd: DateTime(2027, 1, 3),
      );
      expect(m.periodLabel, equals('12/28 ~ 1/3'));
    });

    test('1일 정산 1/1 ~ 1/1 → "1/1 ~ 1/1"', () {
      final day = DateTime(2026, 1, 1);
      final m = _make(periodStart: day, periodEnd: day);
      expect(m.periodLabel, equals('1/1 ~ 1/1'));
    });
  });

  // ══════════════════════════════════════════════════════
  // recordCount
  // ══════════════════════════════════════════════════════
  group('InterimSettlementRequestModel: recordCount', () {
    test('attendanceIds 비어있음 → 0', () {
      expect(_make(attendanceIds: []).recordCount, equals(0));
    });

    test('attendanceIds 1개 → 1', () {
      expect(_make(attendanceIds: ['att-001']).recordCount, equals(1));
    });

    test('attendanceIds 여러 개 → 건수 반환', () {
      expect(_make(attendanceIds: ['a', 'b', 'c', 'd', 'e']).recordCount, equals(5));
    });
  });

  // ══════════════════════════════════════════════════════
  // 상수값 검증
  // ══════════════════════════════════════════════════════
  group('InterimSettlementRequestModel: 상태 상수', () {
    test('상태 상수 값 검증', () {
      expect(InterimSettlementRequestModel.statusPending,   equals('PENDING'));
      expect(InterimSettlementRequestModel.statusApproved,  equals('APPROVED'));
      expect(InterimSettlementRequestModel.statusRejected,  equals('REJECTED'));
      expect(InterimSettlementRequestModel.statusProcessed, equals('PROCESSED'));
    });
  });
}
