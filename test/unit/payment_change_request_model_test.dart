// test/unit/payment_change_request_model_test.dart
// PaymentChangeRequestModel 순수 Dart getter 단위 테스트
//
// fromFirestore/fromMap은 Timestamp 의존 → 생략.
// const 생성자를 직접 사용하여 Firebase 없이 검증.

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/payment_change_request_model.dart';

PaymentChangeRequestModel _make({
  String status = PaymentChangeRequestModel.statusPending,
  String currentType = 'weekly',
  String requestedType = 'monthly',
}) {
  return PaymentChangeRequestModel(
    id: 'pcr-001',
    applicationId: 'app-001',
    businessId: 'biz-001',
    businessName: '테스트 사업장',
    workerId: 'uid-001',
    workerName: '홍길동',
    currentPayScheduleType: currentType,
    requestedPayScheduleType: requestedType,
    effectiveFrom: '2026-07-01',
    status: status,
    createdAt: DateTime(2026, 6, 25),
  );
}

void main() {
  // ══════════════════════════════════════════════════════
  // 상태 Boolean getter
  // ══════════════════════════════════════════════════════
  group('PaymentChangeRequestModel: 상태 getter', () {
    test('PENDING → isPending=true만', () {
      final m = _make(status: PaymentChangeRequestModel.statusPending);
      expect(m.isPending,  isTrue);
      expect(m.isApproved, isFalse);
      expect(m.isRejected, isFalse);
    });

    test('APPROVED → isApproved=true만', () {
      final m = _make(status: PaymentChangeRequestModel.statusApproved);
      expect(m.isPending,  isFalse);
      expect(m.isApproved, isTrue);
      expect(m.isRejected, isFalse);
    });

    test('REJECTED → isRejected=true만', () {
      final m = _make(status: PaymentChangeRequestModel.statusRejected);
      expect(m.isPending,  isFalse);
      expect(m.isApproved, isFalse);
      expect(m.isRejected, isTrue);
    });
  });

  // ══════════════════════════════════════════════════════
  // statusLabel
  // ══════════════════════════════════════════════════════
  group('PaymentChangeRequestModel: statusLabel', () {
    test('PENDING → 처리 대기', () {
      expect(_make(status: PaymentChangeRequestModel.statusPending).statusLabel, equals('처리 대기'));
    });

    test('APPROVED → 승인', () {
      expect(_make(status: PaymentChangeRequestModel.statusApproved).statusLabel, equals('승인'));
    });

    test('REJECTED → 거절', () {
      expect(_make(status: PaymentChangeRequestModel.statusRejected).statusLabel, equals('거절'));
    });

    test('알 수 없는 status → status 문자열 그대로', () {
      expect(_make(status: 'UNKNOWN').statusLabel, equals('UNKNOWN'));
    });
  });

  // ══════════════════════════════════════════════════════
  // scheduleTypeLabel (static)
  // ══════════════════════════════════════════════════════
  group('PaymentChangeRequestModel.scheduleTypeLabel (static)', () {
    test('same_day → 당일', () {
      expect(PaymentChangeRequestModel.scheduleTypeLabel('same_day'), equals('당일'));
    });

    test('next_day → 익일', () {
      expect(PaymentChangeRequestModel.scheduleTypeLabel('next_day'), equals('익일'));
    });

    test('weekly → 주급', () {
      expect(PaymentChangeRequestModel.scheduleTypeLabel('weekly'), equals('주급'));
    });

    test('monthly → 월급', () {
      expect(PaymentChangeRequestModel.scheduleTypeLabel('monthly'), equals('월급'));
    });

    test('알 수 없는 값 → 그대로 반환', () {
      expect(PaymentChangeRequestModel.scheduleTypeLabel('unknown'), equals('unknown'));
    });
  });

  // ══════════════════════════════════════════════════════
  // changeDescription
  // ══════════════════════════════════════════════════════
  group('PaymentChangeRequestModel: changeDescription', () {
    test('weekly → monthly = "주급 → 월급"', () {
      final m = _make(currentType: 'weekly', requestedType: 'monthly');
      expect(m.changeDescription, equals('주급 → 월급'));
    });

    test('same_day → next_day = "당일 → 익일"', () {
      final m = _make(currentType: 'same_day', requestedType: 'next_day');
      expect(m.changeDescription, equals('당일 → 익일'));
    });

    test('monthly → weekly = "월급 → 주급"', () {
      final m = _make(currentType: 'monthly', requestedType: 'weekly');
      expect(m.changeDescription, equals('월급 → 주급'));
    });

    test('동일 타입 → "당일 → 당일" (변경 없음 요청)', () {
      final m = _make(currentType: 'same_day', requestedType: 'same_day');
      expect(m.changeDescription, equals('당일 → 당일'));
    });
  });

  // ══════════════════════════════════════════════════════
  // 상태 상수
  // ══════════════════════════════════════════════════════
  group('PaymentChangeRequestModel: 상태 상수', () {
    test('상수 값 검증', () {
      expect(PaymentChangeRequestModel.statusPending,  equals('PENDING'));
      expect(PaymentChangeRequestModel.statusApproved, equals('APPROVED'));
      expect(PaymentChangeRequestModel.statusRejected, equals('REJECTED'));
    });
  });
}
