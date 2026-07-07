// test/unit/payroll_summary_model_test.dart
// PayrollSummaryModel / PayrollWorkerSummary 순수 Dart getter 단위 테스트
//
// fromFirestore는 Timestamp 의존 → 생략.
// const 생성자와 empty() 팩토리를 사용하여 Firebase 없이 검증.

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/payroll_summary_model.dart';

PayrollSummaryModel _make({
  int confirmedCount = 0,
  int pendingCount = 0,
  int totalPayout = 0,
  Map<String, PayrollWorkerSummary> workers = const {},
}) {
  return PayrollSummaryModel(
    id: 'biz-001_2026-06',
    businessId: 'biz-001',
    yearMonth: '2026-06',
    year: 2026,
    month: 6,
    totalPayout: totalPayout,
    confirmedCount: confirmedCount,
    workerCount: workers.length,
    pendingCount: pendingCount,
    workers: workers,
    updatedAt: DateTime(2026, 6, 30),
  );
}

void main() {
  // ══════════════════════════════════════════════════════
  // isEmpty
  // ══════════════════════════════════════════════════════
  group('PayrollSummaryModel: isEmpty', () {
    test('confirmedCount=0, pendingCount=0 → true', () {
      expect(_make().isEmpty, isTrue);
    });

    test('confirmedCount=1 → false', () {
      expect(_make(confirmedCount: 1).isEmpty, isFalse);
    });

    test('pendingCount=1 → false', () {
      expect(_make(pendingCount: 1).isEmpty, isFalse);
    });

    test('둘 다 있음 → false', () {
      expect(_make(confirmedCount: 3, pendingCount: 2).isEmpty, isFalse);
    });
  });

  // ══════════════════════════════════════════════════════
  // formattedTotalPayout
  // ══════════════════════════════════════════════════════
  group('PayrollSummaryModel: formattedTotalPayout', () {
    test('0원 → "-"', () {
      expect(_make(totalPayout: 0).formattedTotalPayout, equals('-'));
    });

    test('100000원 → "100,000원"', () {
      expect(_make(totalPayout: 100000).formattedTotalPayout, equals('100,000원'));
    });

    test('1234567원 → "1,234,567원"', () {
      expect(_make(totalPayout: 1234567).formattedTotalPayout, equals('1,234,567원'));
    });

    test('999원 → "999원" (천단위 없음)', () {
      expect(_make(totalPayout: 999).formattedTotalPayout, equals('999원'));
    });

    test('1000원 → "1,000원"', () {
      expect(_make(totalPayout: 1000).formattedTotalPayout, equals('1,000원'));
    });
  });

  // ══════════════════════════════════════════════════════
  // sortedWorkers
  // ══════════════════════════════════════════════════════
  group('PayrollSummaryModel: sortedWorkers', () {
    test('빈 workers → 빈 리스트', () {
      expect(_make(workers: {}).sortedWorkers, isEmpty);
    });

    test('1명 → 그대로 반환', () {
      final workers = {
        'uid-001': const PayrollWorkerSummary(
          workerId: 'uid-001',
          name: '홍길동',
          totalPayout: 300000,
          workDays: 3,
        ),
      };
      final sorted = _make(workers: workers).sortedWorkers;
      expect(sorted.length, equals(1));
      expect(sorted.first.name, equals('홍길동'));
    });

    test('여러 명 → totalPayout 내림차순 정렬', () {
      final workers = {
        'uid-001': const PayrollWorkerSummary(
          workerId: 'uid-001', name: '낮은급여', totalPayout: 100000, workDays: 1,
        ),
        'uid-002': const PayrollWorkerSummary(
          workerId: 'uid-002', name: '높은급여', totalPayout: 500000, workDays: 5,
        ),
        'uid-003': const PayrollWorkerSummary(
          workerId: 'uid-003', name: '중간급여', totalPayout: 300000, workDays: 3,
        ),
      };
      final sorted = _make(workers: workers).sortedWorkers;
      expect(sorted.map((w) => w.name).toList(),
          equals(['높은급여', '중간급여', '낮은급여']));
    });
  });

  // ══════════════════════════════════════════════════════
  // empty() 팩토리
  // ══════════════════════════════════════════════════════
  group('PayrollSummaryModel.empty()', () {
    test('empty() → isEmpty=true', () {
      final m = PayrollSummaryModel.empty(
        businessId: 'biz-001',
        year: 2026,
        month: 6,
      );
      expect(m.isEmpty, isTrue);
    });

    test('empty() id 형식 = "{businessId}_YYYY-MM"', () {
      final m = PayrollSummaryModel.empty(
        businessId: 'biz-001',
        year: 2026,
        month: 6,
      );
      expect(m.id, equals('biz-001_2026-06'));
    });

    test('empty() 1자리 월 → 2자리 패딩', () {
      final m = PayrollSummaryModel.empty(
        businessId: 'biz-001',
        year: 2026,
        month: 1,
      );
      expect(m.id, equals('biz-001_2026-01'));
      expect(m.yearMonth, equals('2026-01'));
    });

    test('empty() totalPayout=0', () {
      final m = PayrollSummaryModel.empty(
        businessId: 'biz-001',
        year: 2026,
        month: 6,
      );
      expect(m.totalPayout, equals(0));
      expect(m.formattedTotalPayout, equals('-'));
    });
  });

  // ══════════════════════════════════════════════════════
  // PayrollWorkerSummary
  // ══════════════════════════════════════════════════════
  group('PayrollWorkerSummary', () {
    test('필드 접근', () {
      const w = PayrollWorkerSummary(
        workerId: 'uid-001',
        name: '홍길동',
        totalPayout: 450000,
        workDays: 5,
      );
      expect(w.workerId, equals('uid-001'));
      expect(w.name, equals('홍길동'));
      expect(w.totalPayout, equals(450000));
      expect(w.workDays, equals(5));
    });
  });
}
