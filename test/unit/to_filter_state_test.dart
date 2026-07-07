// test/unit/to_filter_state_test.dart
// TOFilterState 순수 Dart getter / 상태 관리 단위 테스트
//
// Firebase 의존 없음. flutter/material.dart의 DateTimeRange 사용.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/to_filter_state.dart';

void main() {
  // ══════════════════════════════════════════════════════
  // hasFilters
  // ══════════════════════════════════════════════════════
  group('TOFilterState: hasFilters', () {
    test('모든 필터 없음 → false', () {
      expect(const TOFilterState().hasFilters, isFalse);
    });

    test('city만 있음 → true', () {
      expect(const TOFilterState(city: '서울').hasFilters, isTrue);
    });

    test('district만 있음 → true', () {
      expect(const TOFilterState(district: '강남구').hasFilters, isTrue);
    });

    test('type만 있음 → true', () {
      expect(const TOFilterState(type: 'flex').hasFilters, isTrue);
    });

    test('dateRange만 있음 → true', () {
      final range = DateTimeRange(
        start: DateTime(2026, 6, 1),
        end: DateTime(2026, 6, 30),
      );
      expect(TOFilterState(dateRange: range).hasFilters, isTrue);
    });

    test('keyword만 있음 → true', () {
      expect(const TOFilterState(keyword: '피킹').hasFilters, isTrue);
    });

    test('showFavoritesOnly=true → true', () {
      expect(const TOFilterState(showFavoritesOnly: true).hasFilters, isTrue);
    });

    test('sortBy만 변경 → false (정렬은 필터 아님)', () {
      expect(const TOFilterState(sortBy: 'wage').hasFilters, isFalse);
    });
  });

  // ══════════════════════════════════════════════════════
  // activeCount
  // ══════════════════════════════════════════════════════
  group('TOFilterState: activeCount', () {
    test('필터 없음 → 0', () {
      expect(const TOFilterState().activeCount, equals(0));
    });

    test('city만 → 1', () {
      expect(const TOFilterState(city: '서울').activeCount, equals(1));
    });

    test('city + district → 2', () {
      expect(const TOFilterState(city: '서울', district: '강남구').activeCount, equals(2));
    });

    test('city + type + keyword → 3', () {
      expect(const TOFilterState(city: '서울', type: 'flex', keyword: '피킹').activeCount, equals(3));
    });

    test('showFavoritesOnly=true + city → 2', () {
      expect(
        const TOFilterState(city: '서울', showFavoritesOnly: true).activeCount,
        equals(2),
      );
    });

    test('모든 필터 활성 → 6', () {
      final range = DateTimeRange(
        start: DateTime(2026, 6, 1),
        end: DateTime(2026, 6, 30),
      );
      expect(
        TOFilterState(
          city: '서울',
          district: '강남구',
          type: 'flex',
          dateRange: range,
          keyword: '피킹',
          showFavoritesOnly: true,
        ).activeCount,
        equals(6),
      );
    });

    test('sortBy 변경은 카운트에 미포함', () {
      expect(const TOFilterState(sortBy: 'wage').activeCount, equals(0));
    });
  });

  // ══════════════════════════════════════════════════════
  // copyWith — 값 변경
  // ══════════════════════════════════════════════════════
  group('TOFilterState: copyWith 값 변경', () {
    test('city 변경', () {
      final original = const TOFilterState(city: '서울');
      final updated = original.copyWith(city: '경기');
      expect(updated.city, equals('경기'));
      expect(updated.district, isNull);
    });

    test('keyword 추가', () {
      final original = const TOFilterState(city: '서울');
      final updated = original.copyWith(keyword: '피킹');
      expect(updated.city, equals('서울')); // 기존값 유지
      expect(updated.keyword, equals('피킹'));
    });

    test('showFavoritesOnly 변경', () {
      final updated = const TOFilterState().copyWith(showFavoritesOnly: true);
      expect(updated.showFavoritesOnly, isTrue);
    });

    test('값 변경 없이 copyWith() 호출 → 동일값', () {
      const original = TOFilterState(city: '서울', type: 'flex');
      final copy = original.copyWith();
      expect(copy.city, equals('서울'));
      expect(copy.type, equals('flex'));
    });
  });

  // ══════════════════════════════════════════════════════
  // copyWith — 명시적 제거 플래그
  // ══════════════════════════════════════════════════════
  group('TOFilterState: copyWith 명시적 제거', () {
    test('clearCity=true → city=null', () {
      final original = const TOFilterState(city: '서울', district: '강남구');
      final updated = original.copyWith(clearCity: true);
      expect(updated.city, isNull);
      expect(updated.district, equals('강남구')); // 다른 필드 유지
    });

    test('clearDistrict=true → district=null', () {
      final original = const TOFilterState(city: '서울', district: '강남구');
      final updated = original.copyWith(clearDistrict: true);
      expect(updated.district, isNull);
      expect(updated.city, equals('서울'));
    });

    test('clearType=true → type=null', () {
      final updated = const TOFilterState(type: 'flex').copyWith(clearType: true);
      expect(updated.type, isNull);
    });

    test('clearKeyword=true → keyword=null', () {
      final updated = const TOFilterState(keyword: '피킹').copyWith(clearKeyword: true);
      expect(updated.keyword, isNull);
    });

    test('clearDateRange=true → dateRange=null', () {
      final range = DateTimeRange(
        start: DateTime(2026, 6, 1),
        end: DateTime(2026, 6, 30),
      );
      final updated = TOFilterState(dateRange: range).copyWith(clearDateRange: true);
      expect(updated.dateRange, isNull);
    });

    test('clearCity=true이면서 city 동시 전달 → null (제거 우선)', () {
      // clearCity ? null : city ?? this.city → null
      final updated = const TOFilterState(city: '서울').copyWith(
        city: '경기',
        clearCity: true,
      );
      expect(updated.city, isNull);
    });
  });

  // ══════════════════════════════════════════════════════
  // clearRegion
  // ══════════════════════════════════════════════════════
  group('TOFilterState: clearRegion', () {
    test('city + district 동시 제거', () {
      final original = const TOFilterState(
        city: '서울',
        district: '강남구',
        type: 'flex',
      );
      final cleared = original.clearRegion();
      expect(cleared.city, isNull);
      expect(cleared.district, isNull);
      expect(cleared.type, equals('flex')); // 다른 필터 유지
    });

    test('city/district 없어도 오류 없음', () {
      final cleared = const TOFilterState(keyword: '피킹').clearRegion();
      expect(cleared.city, isNull);
      expect(cleared.district, isNull);
      expect(cleared.keyword, equals('피킹'));
    });
  });

  // ══════════════════════════════════════════════════════
  // == 연산자 (등가 비교)
  // ══════════════════════════════════════════════════════
  group('TOFilterState: == 연산자', () {
    test('동일 값 → equal', () {
      const a = TOFilterState(city: '서울', type: 'flex');
      const b = TOFilterState(city: '서울', type: 'flex');
      expect(a, equals(b));
    });

    test('city 다름 → not equal', () {
      const a = TOFilterState(city: '서울');
      const b = TOFilterState(city: '경기');
      expect(a, isNot(equals(b)));
    });

    test('모든 필드 동일 (빈 상태) → equal', () {
      expect(const TOFilterState(), equals(const TOFilterState()));
    });

    test('showFavoritesOnly 다름 → not equal', () {
      const a = TOFilterState(showFavoritesOnly: true);
      const b = TOFilterState(showFavoritesOnly: false);
      expect(a, isNot(equals(b)));
    });

    test('identical → equal', () {
      const a = TOFilterState(city: '서울');
      expect(a, equals(a));
    });
  });
}
