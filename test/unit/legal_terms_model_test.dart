// test/unit/legal_terms_model_test.dart
// LegalTerms / LegalTermsItem 순수 Dart 로직 단위 테스트
//
// fromFirestore는 Timestamp 의존 → 생략.
// const 생성자와 copyWith만 검증.

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/legal_terms_model.dart';

LegalTermsItem _item({
  String id = 'terms-001',
  String title = '서비스 이용약관',
  bool isRequired = true,
  bool isActive = true,
  int order = 1,
}) {
  return LegalTermsItem(
    id: id,
    title: title,
    content: '내용',
    isRequired: isRequired,
    isActive: isActive,
    order: order,
  );
}

void main() {
  // ══════════════════════════════════════════════════════
  // LegalTermsItem.copyWith
  // ══════════════════════════════════════════════════════
  group('LegalTermsItem: copyWith', () {
    test('title 변경', () {
      final item = _item(title: '원본 제목');
      final copy = item.copyWith(title: '새 제목');
      expect(copy.title, equals('새 제목'));
      expect(copy.id, equals(item.id)); // 변경 안 됨
    });

    test('isRequired 변경', () {
      final item = _item(isRequired: true);
      final copy = item.copyWith(isRequired: false);
      expect(copy.isRequired, isFalse);
    });

    test('isActive 변경', () {
      final item = _item(isActive: true);
      final copy = item.copyWith(isActive: false);
      expect(copy.isActive, isFalse);
    });

    test('order 변경', () {
      final item = _item(order: 1);
      final copy = item.copyWith(order: 5);
      expect(copy.order, equals(5));
    });

    test('copyWith() 인자 없음 → 동일 값 유지', () {
      final item = _item(title: '원본', isRequired: true, order: 3);
      final copy = item.copyWith();
      expect(copy.title, equals('원본'));
      expect(copy.isRequired, isTrue);
      expect(copy.order, equals(3));
    });

    test('id는 copyWith로 변경 불가 (항상 원본 유지)', () {
      final item = _item(id: 'fixed-id');
      final copy = item.copyWith(title: '다른 제목');
      expect(copy.id, equals('fixed-id'));
    });
  });

  // ══════════════════════════════════════════════════════
  // LegalTerms.activeItems
  // ══════════════════════════════════════════════════════
  group('LegalTerms: activeItems', () {
    test('빈 items → 빈 리스트', () {
      const terms = LegalTerms(items: []);
      expect(terms.activeItems, isEmpty);
    });

    test('모두 active → 전체 반환', () {
      final terms = LegalTerms(items: [
        _item(id: 'a', isActive: true, order: 2),
        _item(id: 'b', isActive: true, order: 1),
      ]);
      expect(terms.activeItems.length, equals(2));
    });

    test('비활성 항목 제외', () {
      final terms = LegalTerms(items: [
        _item(id: 'active', isActive: true, order: 1),
        _item(id: 'inactive', isActive: false, order: 2),
      ]);
      final active = terms.activeItems;
      expect(active.length, equals(1));
      expect(active.first.id, equals('active'));
    });

    test('order 오름차순 정렬', () {
      final terms = LegalTerms(items: [
        _item(id: 'c', isActive: true, order: 3),
        _item(id: 'a', isActive: true, order: 1),
        _item(id: 'b', isActive: true, order: 2),
      ]);
      final sorted = terms.activeItems.map((t) => t.id).toList();
      expect(sorted, equals(['a', 'b', 'c']));
    });

    test('활성 항목만 order 정렬 (비활성 무시)', () {
      final terms = LegalTerms(items: [
        _item(id: 'second', isActive: true, order: 2),
        _item(id: 'hidden', isActive: false, order: 1),
        _item(id: 'first', isActive: true, order: 3),
      ]);
      final sorted = terms.activeItems.map((t) => t.id).toList();
      expect(sorted, equals(['second', 'first']));
    });
  });

  // ══════════════════════════════════════════════════════
  // LegalTerms.defaultTerms()
  // ══════════════════════════════════════════════════════
  group('LegalTerms.defaultTerms()', () {
    test('5개 항목 생성', () {
      final terms = LegalTerms.defaultTerms();
      expect(terms.items.length, equals(5));
    });

    test('마케팅 동의 항목은 isRequired=false', () {
      final terms = LegalTerms.defaultTerms();
      final marketing = terms.items.firstWhere((t) => t.id == 'marketing_consent');
      expect(marketing.isRequired, isFalse);
    });

    test('나머지 4개 항목은 isRequired=true', () {
      final terms = LegalTerms.defaultTerms();
      final required = terms.items.where((t) => t.id != 'marketing_consent').toList();
      expect(required.every((t) => t.isRequired), isTrue);
    });

    test('모든 항목 isActive=true (기본값)', () {
      final terms = LegalTerms.defaultTerms();
      expect(terms.items.every((t) => t.isActive), isTrue);
    });

    test('id 목록 확인', () {
      final terms = LegalTerms.defaultTerms();
      final ids = terms.items.map((t) => t.id).toList();
      expect(ids, containsAll([
        'service_terms',
        'privacy_policy',
        'privacy_third_party',
        'location_terms',
        'marketing_consent',
      ]));
    });

    test('activeItems = 5개 (모두 활성)', () {
      final terms = LegalTerms.defaultTerms();
      expect(terms.activeItems.length, equals(5));
    });

    test('activeItems는 order 오름차순 (1~5)', () {
      final terms = LegalTerms.defaultTerms();
      final orders = terms.activeItems.map((t) => t.order).toList();
      expect(orders, equals([1, 2, 3, 4, 5]));
    });
  });

  // ══════════════════════════════════════════════════════
  // LegalTermsItem 기본값
  // ══════════════════════════════════════════════════════
  group('LegalTermsItem: 기본값', () {
    test('isActive 기본값 = true', () {
      const item = LegalTermsItem(
        id: 'test',
        title: '테스트',
        content: '내용',
        isRequired: true,
      );
      expect(item.isActive, isTrue);
    });

    test('version 기본값 = "1.0"', () {
      const item = LegalTermsItem(
        id: 'test',
        title: '테스트',
        content: '내용',
        isRequired: true,
      );
      expect(item.version, equals('1.0'));
    });

    test('order 기본값 = 0', () {
      const item = LegalTermsItem(
        id: 'test',
        title: '테스트',
        content: '내용',
        isRequired: true,
      );
      expect(item.order, equals(0));
    });
  });
}
