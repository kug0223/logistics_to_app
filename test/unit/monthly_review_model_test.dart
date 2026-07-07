// test/unit/monthly_review_model_test.dart
// MonthlyReviewModel 순수 Dart getter 및 정적 메서드 단위 테스트
//
// fromFirestore는 Timestamp 의존 → 생략.
// const 생성자를 직접 사용하여 Firebase 없이 검증.

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/monthly_review_model.dart';

MonthlyReviewModel _make({
  int workDaysInMonth = 20,
  int normalAttendanceDays = 0,
  int rating = 3,
  int reviewYear = 2026,
  int reviewMonth = 6,
}) {
  return MonthlyReviewModel(
    id: 'key-001',
    reviewKey: 'key-001',
    reviewType: ReviewType.ADMIN_TO_USER,
    reviewerName: '관리자',
    businessId: 'biz-001',
    businessName: '테스트 사업장',
    reviewYear: reviewYear,
    reviewMonth: reviewMonth,
    workDaysInMonth: workDaysInMonth,
    normalAttendanceDays: normalAttendanceDays,
    rating: rating,
    createdAt: DateTime(2026, 6, 30),
  );
}

void main() {
  // ══════════════════════════════════════════════════════
  // attendanceRate
  // ══════════════════════════════════════════════════════
  group('MonthlyReviewModel: attendanceRate', () {
    test('workDaysInMonth=0 → 0 (ZeroDivision 방지)', () {
      expect(_make(workDaysInMonth: 0).attendanceRate, equals(0.0));
    });

    test('normalAttendanceDays=0 → 0.0', () {
      expect(_make(workDaysInMonth: 20, normalAttendanceDays: 0).attendanceRate, equals(0.0));
    });

    test('10 / 20 → 50.0', () {
      expect(_make(workDaysInMonth: 20, normalAttendanceDays: 10).attendanceRate, equals(50.0));
    });

    test('20 / 20 → 100.0', () {
      expect(_make(workDaysInMonth: 20, normalAttendanceDays: 20).attendanceRate, equals(100.0));
    });

    test('1 / 3 → 33.33... (부동소수점)', () {
      final rate = _make(workDaysInMonth: 3, normalAttendanceDays: 1).attendanceRate;
      expect(rate, closeTo(33.333, 0.001));
    });
  });

  // ══════════════════════════════════════════════════════
  // ratingText
  // ══════════════════════════════════════════════════════
  group('MonthlyReviewModel: ratingText', () {
    test('5 → "최고"', () {
      expect(_make(rating: 5).ratingText, equals('최고'));
    });

    test('4 → "좋음"', () {
      expect(_make(rating: 4).ratingText, equals('좋음'));
    });

    test('3 → "보통"', () {
      expect(_make(rating: 3).ratingText, equals('보통'));
    });

    test('2 → "미흡"', () {
      expect(_make(rating: 2).ratingText, equals('미흡'));
    });

    test('1 → "불량"', () {
      expect(_make(rating: 1).ratingText, equals('불량'));
    });

    test('0 → "" (기본값)', () {
      expect(_make(rating: 0).ratingText, equals(''));
    });

    test('6 → "" (범위 초과 → 기본값)', () {
      expect(_make(rating: 6).ratingText, equals(''));
    });
  });

  // ══════════════════════════════════════════════════════
  // periodText
  // ══════════════════════════════════════════════════════
  group('MonthlyReviewModel: periodText', () {
    test('2026년 6월', () {
      expect(_make(reviewYear: 2026, reviewMonth: 6).periodText, equals('2026년 6월'));
    });

    test('1월 (한 자리 월)', () {
      expect(_make(reviewYear: 2026, reviewMonth: 1).periodText, equals('2026년 1월'));
    });

    test('12월', () {
      expect(_make(reviewYear: 2025, reviewMonth: 12).periodText, equals('2025년 12월'));
    });
  });

  // ══════════════════════════════════════════════════════
  // generateKeyForUser (static)
  // ══════════════════════════════════════════════════════
  group('MonthlyReviewModel.generateKeyForUser', () {
    test('형식: businessId_targetUserId_year_month', () {
      final key = MonthlyReviewModel.generateKeyForUser(
        businessId: 'biz-001',
        targetUserId: 'uid-worker',
        year: 2026,
        month: 6,
      );
      expect(key, equals('biz-001_uid-worker_2026_6'));
    });

    test('1월은 패딩 없이 그대로', () {
      final key = MonthlyReviewModel.generateKeyForUser(
        businessId: 'biz-001',
        targetUserId: 'uid-worker',
        year: 2026,
        month: 1,
      );
      expect(key, equals('biz-001_uid-worker_2026_1'));
    });
  });

  // ══════════════════════════════════════════════════════
  // generateKeyForBusiness (static)
  // ══════════════════════════════════════════════════════
  group('MonthlyReviewModel.generateKeyForBusiness', () {
    test('형식: businessId_reviewerId_year_month_biz', () {
      final key = MonthlyReviewModel.generateKeyForBusiness(
        businessId: 'biz-001',
        reviewerId: 'uid-reviewer',
        year: 2026,
        month: 6,
      );
      expect(key, equals('biz-001_uid-reviewer_2026_6_biz'));
    });

    test('12월 포함', () {
      final key = MonthlyReviewModel.generateKeyForBusiness(
        businessId: 'biz-001',
        reviewerId: 'uid-reviewer',
        year: 2025,
        month: 12,
      );
      expect(key, equals('biz-001_uid-reviewer_2025_12_biz'));
    });
  });

  // ══════════════════════════════════════════════════════
  // ReviewType enum 값
  // ══════════════════════════════════════════════════════
  group('ReviewType', () {
    test('ADMIN_TO_USER name', () {
      expect(ReviewType.ADMIN_TO_USER.name, equals('ADMIN_TO_USER'));
    });

    test('USER_TO_BUSINESS name', () {
      expect(ReviewType.USER_TO_BUSINESS.name, equals('USER_TO_BUSINESS'));
    });
  });
}
