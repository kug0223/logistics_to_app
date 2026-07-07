// test/unit/work_type_model_test.dart
// WorkTypeModel 순수 Dart getter 단위 테스트
//
// fromFirestore/fromMap은 Timestamp 의존 → 생략.
// 생성자를 직접 사용하여 Firebase 없이 검증.

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/work_type_model.dart';

WorkTypeModel _make({
  String difficulty = '보통',
  String physicalDemand = '보통',
}) {
  return WorkTypeModel(
    name: '피킹',
    code: 'PICKING',
    difficulty: difficulty,
    physicalDemand: physicalDemand,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
    createdBy: 'uid-admin',
  );
}

void main() {
  // ══════════════════════════════════════════════════════
  // difficultyIcon
  // ══════════════════════════════════════════════════════
  group('WorkTypeModel: difficultyIcon', () {
    test('쉬움 → 😊', () {
      expect(_make(difficulty: '쉬움').difficultyIcon, equals('😊'));
    });

    test('어려움 → 😰', () {
      expect(_make(difficulty: '어려움').difficultyIcon, equals('😰'));
    });

    test('보통 → 😐 (기본값)', () {
      expect(_make(difficulty: '보통').difficultyIcon, equals('😐'));
    });

    test('알 수 없는 값 → 😐 (default case)', () {
      expect(_make(difficulty: '매우어려움').difficultyIcon, equals('😐'));
    });
  });

  // ══════════════════════════════════════════════════════
  // physicalDemandIcon
  // ══════════════════════════════════════════════════════
  group('WorkTypeModel: physicalDemandIcon', () {
    test('낮음 → 💚', () {
      expect(_make(physicalDemand: '낮음').physicalDemandIcon, equals('💚'));
    });

    test('높음 → 💪', () {
      expect(_make(physicalDemand: '높음').physicalDemandIcon, equals('💪'));
    });

    test('보통 → 💛 (기본값)', () {
      expect(_make(physicalDemand: '보통').physicalDemandIcon, equals('💛'));
    });

    test('알 수 없는 값 → 💛 (default case)', () {
      expect(_make(physicalDemand: '매우낮음').physicalDemandIcon, equals('💛'));
    });
  });

  // ══════════════════════════════════════════════════════
  // 기본 필드 값 확인
  // ══════════════════════════════════════════════════════
  group('WorkTypeModel: 기본 필드', () {
    test('difficulty 기본값 = "보통"', () {
      final m = WorkTypeModel(
        name: '패킹',
        code: 'PACKING',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        createdBy: 'uid-admin',
      );
      expect(m.difficulty, equals('보통'));
    });

    test('physicalDemand 기본값 = "보통"', () {
      final m = WorkTypeModel(
        name: '패킹',
        code: 'PACKING',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        createdBy: 'uid-admin',
      );
      expect(m.physicalDemand, equals('보통'));
    });

    test('isActive 기본값 = true', () {
      expect(_make().isActive, isTrue);
    });

    test('displayOrder 기본값 = 0', () {
      expect(_make().displayOrder, equals(0));
    });
  });
}
