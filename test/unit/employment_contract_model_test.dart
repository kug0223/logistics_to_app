// test/unit/employment_contract_model_test.dart
// ContractStatus enum 및 ContractStatusX extension 단위 테스트
//
// EmploymentContractModel 전체는 Timestamp/Firestore 의존 → 생략.
// ContractStatus enum + extension만 순수 Dart 로직으로 검증.

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/employment_contract_model.dart';

void main() {
  // ══════════════════════════════════════════════════════
  // ContractStatusX.value
  // ══════════════════════════════════════════════════════
  group('ContractStatusX.value', () {
    test('pendingEmployer → "pending_employer"', () {
      expect(ContractStatus.pendingEmployer.value, equals('pending_employer'));
    });

    test('pendingWorker → "pending_worker"', () {
      expect(ContractStatus.pendingWorker.value, equals('pending_worker'));
    });

    test('completed → "completed"', () {
      expect(ContractStatus.completed.value, equals('completed'));
    });

    test('voided → "voided"', () {
      expect(ContractStatus.voided.value, equals('voided'));
    });

    test('모든 enum에 value가 있음 (빠짐 없음)', () {
      for (final s in ContractStatus.values) {
        expect(s.value, isNotEmpty);
      }
    });
  });

  // ══════════════════════════════════════════════════════
  // ContractStatusX.label
  // ══════════════════════════════════════════════════════
  group('ContractStatusX.label', () {
    test('pendingEmployer → "사업주 서명 대기"', () {
      expect(ContractStatus.pendingEmployer.label, equals('사업주 서명 대기'));
    });

    test('pendingWorker → "근무자 서명 대기"', () {
      expect(ContractStatus.pendingWorker.label, equals('근무자 서명 대기'));
    });

    test('completed → "계약 완료"', () {
      expect(ContractStatus.completed.label, equals('계약 완료'));
    });

    test('voided → "무효"', () {
      expect(ContractStatus.voided.label, equals('무효'));
    });

    test('모든 enum에 label이 있음 (빠짐 없음)', () {
      for (final s in ContractStatus.values) {
        expect(s.label, isNotEmpty);
      }
    });
  });

  // ══════════════════════════════════════════════════════
  // ContractStatusX.fromString
  // ══════════════════════════════════════════════════════
  group('ContractStatusX.fromString', () {
    test('"pending_employer" → pendingEmployer', () {
      expect(
        ContractStatusX.fromString('pending_employer'),
        equals(ContractStatus.pendingEmployer),
      );
    });

    test('"pending_worker" → pendingWorker', () {
      expect(
        ContractStatusX.fromString('pending_worker'),
        equals(ContractStatus.pendingWorker),
      );
    });

    test('"completed" → completed', () {
      expect(
        ContractStatusX.fromString('completed'),
        equals(ContractStatus.completed),
      );
    });

    test('"voided" → voided', () {
      expect(
        ContractStatusX.fromString('voided'),
        equals(ContractStatus.voided),
      );
    });

    test('알 수 없는 문자열 → pendingEmployer (기본값)', () {
      expect(
        ContractStatusX.fromString('unknown_status'),
        equals(ContractStatus.pendingEmployer),
      );
    });

    test('빈 문자열 → pendingEmployer (기본값)', () {
      expect(
        ContractStatusX.fromString(''),
        equals(ContractStatus.pendingEmployer),
      );
    });

    test('대소문자 구분 — "Completed" → pendingEmployer (기본값)', () {
      expect(
        ContractStatusX.fromString('Completed'),
        equals(ContractStatus.pendingEmployer),
      );
    });

    test('value → fromString 라운드트립 — 모든 enum', () {
      for (final s in ContractStatus.values) {
        expect(ContractStatusX.fromString(s.value), equals(s));
      }
    });
  });

  // ══════════════════════════════════════════════════════
  // ContractStatus enum 기본 속성
  // ══════════════════════════════════════════════════════
  group('ContractStatus 기본 속성', () {
    test('values 목록 4개', () {
      expect(ContractStatus.values.length, equals(4));
    });

    test('name 확인', () {
      expect(ContractStatus.pendingEmployer.name, equals('pendingEmployer'));
      expect(ContractStatus.pendingWorker.name, equals('pendingWorker'));
      expect(ContractStatus.completed.name, equals('completed'));
      expect(ContractStatus.voided.name, equals('voided'));
    });
  });
}
