// test/unit/business_model_test.dart
// BusinessModel 순수 Dart getter 단위 테스트
//
// fromFirestore/fromMap은 Timestamp 의존 → 생략.
// 생성자를 직접 사용하여 Firebase 없이 검증.

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/business_model.dart';

BusinessModel _make({
  String businessNumber = '1234567890',
  String ownerId = 'uid-owner',
  List<String>? adminIds,
  DateTime? deactivatedAt,
}) {
  return BusinessModel(
    id: 'biz-001',
    businessNumber: businessNumber,
    name: '테스트 사업장',
    category: '물류',
    subCategory: '창고',
    address: '서울시 강남구',
    ownerId: ownerId,
    adminIds: adminIds,
    createdAt: DateTime(2026, 1, 1),
    deactivatedAt: deactivatedAt,
  );
}

void main() {
  // ══════════════════════════════════════════════════════
  // formattedBusinessNumber
  // ══════════════════════════════════════════════════════
  group('BusinessModel: formattedBusinessNumber', () {
    test('10자리 → XXX-XX-XXXXX 형식', () {
      final m = _make(businessNumber: '1234567890');
      expect(m.formattedBusinessNumber, equals('123-45-67890'));
    });

    test('다른 10자리 숫자', () {
      final m = _make(businessNumber: '9876543210');
      expect(m.formattedBusinessNumber, equals('987-65-43210'));
    });

    test('10자리 미만 → 그대로 반환', () {
      final m = _make(businessNumber: '12345');
      expect(m.formattedBusinessNumber, equals('12345'));
    });

    test('10자리 초과 → 그대로 반환', () {
      final m = _make(businessNumber: '12345678901');
      expect(m.formattedBusinessNumber, equals('12345678901'));
    });

    test('빈 문자열 → 빈 문자열 반환', () {
      final m = _make(businessNumber: '');
      expect(m.formattedBusinessNumber, equals(''));
    });
  });

  // ══════════════════════════════════════════════════════
  // isDeactivated
  // ══════════════════════════════════════════════════════
  group('BusinessModel: isDeactivated', () {
    test('deactivatedAt=null → false', () {
      expect(_make(deactivatedAt: null).isDeactivated, isFalse);
    });

    test('deactivatedAt 과거 날짜 → true', () {
      expect(_make(deactivatedAt: DateTime(2020, 1, 1)).isDeactivated, isTrue);
    });

    test('deactivatedAt 미래 날짜도 → true (null 여부만 체크)', () {
      expect(_make(deactivatedAt: DateTime(2099, 12, 31)).isDeactivated, isTrue);
    });
  });

  // ══════════════════════════════════════════════════════
  // adminIds 초기화 로직
  // ══════════════════════════════════════════════════════
  group('BusinessModel: adminIds 초기화', () {
    test('adminIds=null → [ownerId]', () {
      final m = _make(ownerId: 'uid-owner', adminIds: null);
      expect(m.adminIds, equals(['uid-owner']));
    });

    test('adminIds=[] (빈 리스트) → [ownerId]', () {
      final m = _make(ownerId: 'uid-owner', adminIds: []);
      expect(m.adminIds, equals(['uid-owner']));
    });

    test('adminIds 값 있음 → 그대로 사용', () {
      final m = _make(
        ownerId: 'uid-owner',
        adminIds: ['uid-admin1', 'uid-admin2'],
      );
      expect(m.adminIds, equals(['uid-admin1', 'uid-admin2']));
    });

    test('adminIds에 ownerId가 없어도 그대로 사용', () {
      final m = _make(
        ownerId: 'uid-owner',
        adminIds: ['uid-other'],
      );
      expect(m.adminIds, equals(['uid-other']));
    });
  });
}
