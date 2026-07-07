// test/unit/schedule_change_request_model_test.dart
// ScheduleChangeRequestModel 순수 Dart getter 단위 테스트
//
// fromFirestore/fromMap은 Timestamp 의존 → 생략.
// 생성자를 직접 사용하여 Firebase 없이 검증.

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/schedule_change_request_model.dart';

ScheduleChangeRequestModel _make({
  RequestType requestType = RequestType.LEAVE,
  RequesterType requestedBy = RequesterType.APPLICANT,
  RequestStatus status = RequestStatus.PENDING,
}) {
  return ScheduleChangeRequestModel(
    id: 'scr-001',
    businessId: 'biz-001',
    applicationId: 'app-001',
    applicantUid: 'uid-001',
    applicantName: '홍길동',
    targetDate: DateTime(2026, 6, 10),
    requestType: requestType,
    requestedBy: requestedBy,
    requestedByUid: 'uid-001',
    requestedAt: DateTime(2026, 6, 9, 10, 0),
    status: status,
  );
}

void main() {
  // ══════════════════════════════════════════════════════
  // 상태 Boolean getter
  // ══════════════════════════════════════════════════════
  group('ScheduleChangeRequestModel: 상태 getter', () {
    test('PENDING → isPending=true만', () {
      final m = _make(status: RequestStatus.PENDING);
      expect(m.isPending,  isTrue);
      expect(m.isApproved, isFalse);
      expect(m.isRejected, isFalse);
      expect(m.isCanceled, isFalse);
    });

    test('APPROVED → isApproved=true만', () {
      final m = _make(status: RequestStatus.APPROVED);
      expect(m.isPending,  isFalse);
      expect(m.isApproved, isTrue);
      expect(m.isRejected, isFalse);
      expect(m.isCanceled, isFalse);
    });

    test('REJECTED → isRejected=true만', () {
      final m = _make(status: RequestStatus.REJECTED);
      expect(m.isPending,  isFalse);
      expect(m.isApproved, isFalse);
      expect(m.isRejected, isTrue);
      expect(m.isCanceled, isFalse);
    });

    test('CANCELED → isCanceled=true만', () {
      final m = _make(status: RequestStatus.CANCELED);
      expect(m.isPending,  isFalse);
      expect(m.isApproved, isFalse);
      expect(m.isRejected, isFalse);
      expect(m.isCanceled, isTrue);
    });
  });

  // ══════════════════════════════════════════════════════
  // 요청 타입 getter
  // ══════════════════════════════════════════════════════
  group('ScheduleChangeRequestModel: requestType getter', () {
    test('LEAVE → isLeaveRequest=true, 나머지=false', () {
      final m = _make(requestType: RequestType.LEAVE);
      expect(m.isLeaveRequest,     isTrue);
      expect(m.isNoWorkRequest,    isFalse);
      expect(m.isExtraWorkRequest, isFalse);
    });

    test('NO_WORK → isNoWorkRequest=true만', () {
      final m = _make(requestType: RequestType.NO_WORK);
      expect(m.isLeaveRequest,     isFalse);
      expect(m.isNoWorkRequest,    isTrue);
      expect(m.isExtraWorkRequest, isFalse);
    });

    test('EXTRA_WORK → isExtraWorkRequest=true만', () {
      final m = _make(requestType: RequestType.EXTRA_WORK);
      expect(m.isLeaveRequest,     isFalse);
      expect(m.isNoWorkRequest,    isFalse);
      expect(m.isExtraWorkRequest, isTrue);
    });

    test('CANCEL_LEAVE → 모두 false (전용 getter 없음)', () {
      final m = _make(requestType: RequestType.CANCEL_LEAVE);
      expect(m.isLeaveRequest,     isFalse);
      expect(m.isNoWorkRequest,    isFalse);
      expect(m.isExtraWorkRequest, isFalse);
    });
  });

  // ══════════════════════════════════════════════════════
  // 요청자 타입 getter
  // ══════════════════════════════════════════════════════
  group('ScheduleChangeRequestModel: requestedBy getter', () {
    test('APPLICANT → isApplicantRequest=true, isAdminRequest=false', () {
      final m = _make(requestedBy: RequesterType.APPLICANT);
      expect(m.isApplicantRequest, isTrue);
      expect(m.isAdminRequest,     isFalse);
    });

    test('ADMIN → isAdminRequest=true, isApplicantRequest=false', () {
      final m = _make(requestedBy: RequesterType.ADMIN);
      expect(m.isApplicantRequest, isFalse);
      expect(m.isAdminRequest,     isTrue);
    });
  });

  // ══════════════════════════════════════════════════════
  // requestTypeLabel
  // ══════════════════════════════════════════════════════
  group('ScheduleChangeRequestModel: requestTypeLabel', () {
    test('LEAVE → 휴무 요청', () {
      expect(_make(requestType: RequestType.LEAVE).requestTypeLabel, equals('휴무 요청'));
    });

    test('NO_WORK → 미출근 요청', () {
      expect(_make(requestType: RequestType.NO_WORK).requestTypeLabel, equals('미출근 요청'));
    });

    test('EXTRA_WORK → 추가 근무 요청', () {
      expect(_make(requestType: RequestType.EXTRA_WORK).requestTypeLabel, equals('추가 근무 요청'));
    });

    test('CANCEL_LEAVE → 휴무 취소 요청', () {
      expect(_make(requestType: RequestType.CANCEL_LEAVE).requestTypeLabel, equals('휴무 취소 요청'));
    });

    test('CANCEL_EXTRA → 추가근무 취소 요청', () {
      expect(_make(requestType: RequestType.CANCEL_EXTRA).requestTypeLabel, equals('추가근무 취소 요청'));
    });
  });

  // ══════════════════════════════════════════════════════
  // statusLabel
  // ══════════════════════════════════════════════════════
  group('ScheduleChangeRequestModel: statusLabel', () {
    test('PENDING → 대기중', () {
      expect(_make(status: RequestStatus.PENDING).statusLabel, equals('대기중'));
    });

    test('APPROVED → 승인됨', () {
      expect(_make(status: RequestStatus.APPROVED).statusLabel, equals('승인됨'));
    });

    test('REJECTED → 거절됨', () {
      expect(_make(status: RequestStatus.REJECTED).statusLabel, equals('거절됨'));
    });

    test('CANCELED → 취소됨', () {
      expect(_make(status: RequestStatus.CANCELED).statusLabel, equals('취소됨'));
    });
  });
}
