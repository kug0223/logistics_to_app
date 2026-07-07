// test/unit/id_card_access_request_model_test.dart
// IdCardAccessRequestModel 순수 Dart getter 단위 테스트
//
// fromFirestore/fromMap은 Timestamp 의존 → 생략.
// 생성자를 직접 사용하여 Firebase 없이 검증.
// 시간 의존 getter는 미래/과거 고정 날짜로 side-effect 없이 검증.

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/id_card_access_request_model.dart';

IdCardAccessRequestModel _make({
  IdCardAccessStatus status = IdCardAccessStatus.pending,
  IdCardAccessReason reason = IdCardAccessReason.incomeTax,
  String? customReason,
  DateTime? expiresAt,
}) {
  return IdCardAccessRequestModel(
    id: 'icar-001',
    requesterId: 'uid-admin',
    requesterName: '관리자',
    requesterBusinessId: 'biz-001',
    requesterBusinessName: '테스트 사업장',
    targetUserId: 'uid-worker',
    targetUserName: '홍길동',
    reason: reason,
    customReason: customReason,
    status: status,
    requestedAt: DateTime(2026, 6, 1, 10, 0),
    expiresAt: expiresAt,
  );
}

void main() {
  // ══════════════════════════════════════════════════════
  // isPending
  // ══════════════════════════════════════════════════════
  group('IdCardAccessRequestModel: isPending', () {
    test('pending → true', () {
      expect(_make(status: IdCardAccessStatus.pending).isPending, isTrue);
    });

    test('approved → false', () {
      expect(_make(status: IdCardAccessStatus.approved).isPending, isFalse);
    });

    test('rejected → false', () {
      expect(_make(status: IdCardAccessStatus.rejected).isPending, isFalse);
    });

    test('expired → false', () {
      expect(_make(status: IdCardAccessStatus.expired).isPending, isFalse);
    });
  });

  // ══════════════════════════════════════════════════════
  // isExpired (expiresAt 기반)
  // ══════════════════════════════════════════════════════
  group('IdCardAccessRequestModel: isExpired', () {
    test('expiresAt=null → false', () {
      expect(_make(expiresAt: null).isExpired, isFalse);
    });

    test('expiresAt 과거 → true', () {
      expect(_make(expiresAt: DateTime(2020, 1, 1)).isExpired, isTrue);
    });

    test('expiresAt 미래 → false', () {
      expect(_make(expiresAt: DateTime(2099, 12, 31)).isExpired, isFalse);
    });
  });

  // ══════════════════════════════════════════════════════
  // isValidAccess
  // ══════════════════════════════════════════════════════
  group('IdCardAccessRequestModel: isValidAccess', () {
    test('approved + expiresAt 미래 → true', () {
      final m = _make(
        status: IdCardAccessStatus.approved,
        expiresAt: DateTime(2099, 12, 31),
      );
      expect(m.isValidAccess, isTrue);
    });

    test('approved + expiresAt 과거 → false (만료)', () {
      final m = _make(
        status: IdCardAccessStatus.approved,
        expiresAt: DateTime(2020, 1, 1),
      );
      expect(m.isValidAccess, isFalse);
    });

    test('approved + expiresAt=null → false', () {
      final m = _make(status: IdCardAccessStatus.approved, expiresAt: null);
      expect(m.isValidAccess, isFalse);
    });

    test('pending + expiresAt 미래 → false (승인 아님)', () {
      final m = _make(
        status: IdCardAccessStatus.pending,
        expiresAt: DateTime(2099, 12, 31),
      );
      expect(m.isValidAccess, isFalse);
    });

    test('rejected + expiresAt 미래 → false', () {
      final m = _make(
        status: IdCardAccessStatus.rejected,
        expiresAt: DateTime(2099, 12, 31),
      );
      expect(m.isValidAccess, isFalse);
    });
  });

  // ══════════════════════════════════════════════════════
  // reasonText
  // ══════════════════════════════════════════════════════
  group('IdCardAccessRequestModel: reasonText', () {
    test('incomeTax → 소득세 신고', () {
      expect(_make(reason: IdCardAccessReason.incomeTax).reasonText, equals('소득세 신고'));
    });

    test('laborContract → 근로계약서 작성', () {
      expect(_make(reason: IdCardAccessReason.laborContract).reasonText, equals('근로계약서 작성'));
    });

    test('insurance → 4대보험 신고', () {
      expect(_make(reason: IdCardAccessReason.insurance).reasonText, equals('4대보험 신고'));
    });

    test('identityVerify → 본인 확인', () {
      expect(_make(reason: IdCardAccessReason.identityVerify).reasonText, equals('본인 확인'));
    });

    test('other + customReason → customReason 반환', () {
      final m = _make(reason: IdCardAccessReason.other, customReason: '직접 입력 사유');
      expect(m.reasonText, equals('직접 입력 사유'));
    });

    test('other + customReason=null → "기타"', () {
      final m = _make(reason: IdCardAccessReason.other);
      expect(m.reasonText, equals('기타'));
    });
  });

  // ══════════════════════════════════════════════════════
  // statusText
  // ══════════════════════════════════════════════════════
  group('IdCardAccessRequestModel: statusText', () {
    test('pending → 승인 대기', () {
      expect(_make(status: IdCardAccessStatus.pending).statusText, equals('승인 대기'));
    });

    test('approved + 미래 expiresAt → 승인됨', () {
      final m = _make(
        status: IdCardAccessStatus.approved,
        expiresAt: DateTime(2099, 12, 31),
      );
      expect(m.statusText, equals('승인됨'));
    });

    test('approved + 과거 expiresAt → 만료됨 (isExpired=true)', () {
      final m = _make(
        status: IdCardAccessStatus.approved,
        expiresAt: DateTime(2020, 1, 1),
      );
      expect(m.statusText, equals('만료됨'));
    });

    test('rejected → 거절됨', () {
      expect(_make(status: IdCardAccessStatus.rejected).statusText, equals('거절됨'));
    });

    test('expired → 만료됨', () {
      expect(_make(status: IdCardAccessStatus.expired).statusText, equals('만료됨'));
    });
  });
}
