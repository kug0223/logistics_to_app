// test/unit/payment_due_date_calculator_test.dart
// PaymentDueDateCalculator 단위 테스트 — 지급예정일 계산 검증
//
// 커버 범위:
//   - same_day / next_day / null 타입
//   - weekly: 당일=목표요일, 이후 요일, 이전 요일(→다음주)
//   - monthly: 이번달, 이미 지남(→다음달), 말일 초과(→말일 클램프)
//   - 2월 31일 처리, 12월→1월 연도 이월
//   - isDueOnOrBefore: reference 파라미터 기반 검증

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/utils/payment_due_date_calculator.dart';

void main() {
  // ══════════════════════════════════════════════════════
  // same_day
  // ══════════════════════════════════════════════════════
  group('PaymentDueDateCalculator — same_day', () {
    test('근무일 당일 반환', () {
      final result = PaymentDueDateCalculator.calculate(
        payScheduleType: 'same_day',
        payScheduleDay: null,
        workDate: DateTime(2026, 6, 1),
      );
      expect(result, equals(DateTime(2026, 6, 1)));
    });

    test('월말일도 당일 반환', () {
      final result = PaymentDueDateCalculator.calculate(
        payScheduleType: 'same_day',
        payScheduleDay: null,
        workDate: DateTime(2026, 6, 30),
      );
      expect(result, equals(DateTime(2026, 6, 30)));
    });
  });

  // ══════════════════════════════════════════════════════
  // next_day
  // ══════════════════════════════════════════════════════
  group('PaymentDueDateCalculator — next_day', () {
    test('근무일 + 1일', () {
      final result = PaymentDueDateCalculator.calculate(
        payScheduleType: 'next_day',
        payScheduleDay: null,
        workDate: DateTime(2026, 6, 1),
      );
      expect(result, equals(DateTime(2026, 6, 2)));
    });

    test('월말일 → 다음달 1일', () {
      final result = PaymentDueDateCalculator.calculate(
        payScheduleType: 'next_day',
        payScheduleDay: null,
        workDate: DateTime(2026, 6, 30),
      );
      expect(result, equals(DateTime(2026, 7, 1)));
    });

    test('12월 31일 → 다음해 1월 1일', () {
      final result = PaymentDueDateCalculator.calculate(
        payScheduleType: 'next_day',
        payScheduleDay: null,
        workDate: DateTime(2026, 12, 31),
      );
      expect(result, equals(DateTime(2027, 1, 1)));
    });
  });

  // ══════════════════════════════════════════════════════
  // weekly — 요일 계산 (Dart weekday: 1=월 … 7=일)
  // ══════════════════════════════════════════════════════
  group('PaymentDueDateCalculator — weekly', () {
    // 2026-06-01은 월요일 (weekday=1)
    // 2026-06-05는 금요일 (weekday=5)

    test('근무일이 목표 요일과 동일 → 당일', () {
      // 2026-06-05(금), 목표 5(금) → 당일
      final result = PaymentDueDateCalculator.calculate(
        payScheduleType: 'weekly',
        payScheduleDay: 5,
        workDate: DateTime(2026, 6, 5),
      );
      expect(result, equals(DateTime(2026, 6, 5)));
    });

    test('근무일(월) 이후 금요일', () {
      // 2026-06-01(월), 목표 5(금) → 2026-06-05
      final result = PaymentDueDateCalculator.calculate(
        payScheduleType: 'weekly',
        payScheduleDay: 5,
        workDate: DateTime(2026, 6, 1),
      );
      expect(result, equals(DateTime(2026, 6, 5)));
    });

    test('근무일(금) 이후 수요일 → 다음주 수요일', () {
      // 2026-06-05(금), 목표 3(수) → diff=(3-5)%7=5 → +5일=2026-06-10(수)
      final result = PaymentDueDateCalculator.calculate(
        payScheduleType: 'weekly',
        payScheduleDay: 3,
        workDate: DateTime(2026, 6, 5),
      );
      expect(result, equals(DateTime(2026, 6, 10)));
    });

    test('목표 요일 null → 기본 금요일(5) 사용', () {
      // 2026-06-01(월), payScheduleDay=null → 기본 금요일
      final result = PaymentDueDateCalculator.calculate(
        payScheduleType: 'weekly',
        payScheduleDay: null,
        workDate: DateTime(2026, 6, 1),
      );
      // 금요일=5, 월요일에서 +4일 = 2026-06-05
      expect(result, equals(DateTime(2026, 6, 5)));
    });

    test('주말 넘김: 근무일(목) → 다음주 월요일', () {
      // 2026-06-04(목, weekday=4), 목표 1(월) → diff=(1-4)%7=4 → +4일=2026-06-08(월)
      final result = PaymentDueDateCalculator.calculate(
        payScheduleType: 'weekly',
        payScheduleDay: 1,
        workDate: DateTime(2026, 6, 4),
      );
      expect(result, equals(DateTime(2026, 6, 8)));
    });
  });

  // ══════════════════════════════════════════════════════
  // monthly — 월 지급일 계산
  // ══════════════════════════════════════════════════════
  group('PaymentDueDateCalculator — monthly', () {
    test('이번달 지급일 아직 안 지남 → 이번달', () {
      // workDate 2026-06-01, 목표일 25 → 2026-06-25
      final result = PaymentDueDateCalculator.calculate(
        payScheduleType: 'monthly',
        payScheduleDay: 25,
        workDate: DateTime(2026, 6, 1),
      );
      expect(result, equals(DateTime(2026, 6, 25)));
    });

    test('이번달 지급일 당일 → 이번달', () {
      final result = PaymentDueDateCalculator.calculate(
        payScheduleType: 'monthly',
        payScheduleDay: 25,
        workDate: DateTime(2026, 6, 25),
      );
      expect(result, equals(DateTime(2026, 6, 25)));
    });

    test('이미 지급일 지남 → 다음달', () {
      // workDate 2026-06-26, 목표일 25 → 이미 지남 → 2026-07-25
      final result = PaymentDueDateCalculator.calculate(
        payScheduleType: 'monthly',
        payScheduleDay: 25,
        workDate: DateTime(2026, 6, 26),
      );
      expect(result, equals(DateTime(2026, 7, 25)));
    });

    test('12월 지급일 지남 → 다음해 1월', () {
      // workDate 2026-12-26, 목표일 25 → 2027-01-25
      final result = PaymentDueDateCalculator.calculate(
        payScheduleType: 'monthly',
        payScheduleDay: 25,
        workDate: DateTime(2026, 12, 26),
      );
      expect(result, equals(DateTime(2027, 1, 25)));
    });

    test('2월 30일 → 2월 말일(28일)로 클램프', () {
      // workDate 2026-02-01, 목표일 30 → 2026-02-28 (2026년은 평년)
      final result = PaymentDueDateCalculator.calculate(
        payScheduleType: 'monthly',
        payScheduleDay: 30,
        workDate: DateTime(2026, 2, 1),
      );
      expect(result, equals(DateTime(2026, 2, 28)));
    });

    test('31일 목표, 6월(30일) → 30일로 클램프', () {
      final result = PaymentDueDateCalculator.calculate(
        payScheduleType: 'monthly',
        payScheduleDay: 31,
        workDate: DateTime(2026, 6, 1),
      );
      expect(result, equals(DateTime(2026, 6, 30)));
    });

    test('payScheduleDay=null → 기본 25일 사용', () {
      final result = PaymentDueDateCalculator.calculate(
        payScheduleType: 'monthly',
        payScheduleDay: null,
        workDate: DateTime(2026, 6, 1),
      );
      expect(result, equals(DateTime(2026, 6, 25)));
    });
  });

  // ══════════════════════════════════════════════════════
  // 미설정 (null / 기타 타입)
  // ══════════════════════════════════════════════════════
  group('PaymentDueDateCalculator — 미설정', () {
    test('null 타입 → null 반환', () {
      expect(
        PaymentDueDateCalculator.calculate(
          payScheduleType: null, payScheduleDay: null,
          workDate: DateTime(2026, 6, 1),
        ),
        isNull,
      );
    });

    test('알 수 없는 타입 → null 반환', () {
      expect(
        PaymentDueDateCalculator.calculate(
          payScheduleType: 'unknown', payScheduleDay: null,
          workDate: DateTime(2026, 6, 1),
        ),
        isNull,
      );
    });
  });

  // ══════════════════════════════════════════════════════
  // isDueOnOrBefore — reference 기반 검증
  // ══════════════════════════════════════════════════════
  group('PaymentDueDateCalculator.isDueOnOrBefore', () {
    final ref = DateTime(2026, 6, 25);

    test('지급일 < reference → true', () {
      expect(
        PaymentDueDateCalculator.isDueOnOrBefore(
          DateTime(2026, 6, 24), reference: ref,
        ),
        isTrue,
      );
    });

    test('지급일 == reference → true (당일 포함)', () {
      expect(
        PaymentDueDateCalculator.isDueOnOrBefore(
          DateTime(2026, 6, 25), reference: ref,
        ),
        isTrue,
      );
    });

    test('지급일 > reference → false', () {
      expect(
        PaymentDueDateCalculator.isDueOnOrBefore(
          DateTime(2026, 6, 26), reference: ref,
        ),
        isFalse,
      );
    });

    test('null 지급일 → false', () {
      expect(
        PaymentDueDateCalculator.isDueOnOrBefore(null, reference: ref),
        isFalse,
      );
    });
  });

  // ══════════════════════════════════════════════════════
  // label / sortOrder 헬퍼
  // ══════════════════════════════════════════════════════
  group('PaymentDueDateCalculator 헬퍼', () {
    test('label 반환', () {
      expect(PaymentDueDateCalculator.label('same_day'), equals('당일'));
      expect(PaymentDueDateCalculator.label('next_day'), equals('익일'));
      expect(PaymentDueDateCalculator.label('weekly'), equals('주급'));
      expect(PaymentDueDateCalculator.label('monthly'), equals('월급'));
      expect(PaymentDueDateCalculator.label(null), equals('미설정'));
    });

    test('sortOrder: same_day < next_day < weekly < monthly < 미설정', () {
      final orders = ['same_day', 'next_day', 'weekly', 'monthly', null]
          .map(PaymentDueDateCalculator.sortOrder)
          .toList();
      // 오름차순 정렬 확인
      for (var i = 0; i < orders.length - 1; i++) {
        expect(orders[i], lessThan(orders[i + 1]));
      }
    });
  });
}
