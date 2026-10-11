// [R7-REVIEW-ELIGIBILITY-REVOCATION-PATCH.2 §5·§6] 클라이언트 쪽 계약.
//
//   서버 경계(Rules·onReviewCreated)는 격리 에뮬레이터 하네스
//   `scripts/r7-rer2-emu-contract.js` 가 실제 요청으로 측정한다(62/62).
//   여기서 보는 것은 **클라이언트가 그 상태를 어떻게 읽고 무엇을 말하는가**다:
//
//     1. 보류 필드 왕복 — Firestore 문서 · CF 직렬화 Map · 레거시(필드 부재)
//     2. 보류 필드는 toMap 으로 흘러나가지 않는다(서버 전용)
//     3. 안내 문구가 내부 상태가 아니라 복구 경로를 말한다
//     4. 리뷰 작성 진입 4곳이 폼을 열기 전에 보류를 본다
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:ALfit/models/core/review_request_model.dart';
import 'package:ALfit/services/monthly_review_service.dart';

/// 최소 DocumentSnapshot — 이 저장소 관례대로 외부 fake 패키지를 들이지 않는다.
/// `noSuchMethod` 가 나머지 인터페이스를 받는다.
class _Snap implements DocumentSnapshot<Map<String, dynamic>> {
  _Snap(this._data, this.id);
  final Map<String, dynamic>? _data;
  @override
  final String id;
  @override
  Map<String, dynamic>? data() => _data;
  @override
  bool get exists => _data != null;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('테스트가 쓰지 않는 멤버: ${invocation.memberName}');
}

void main() {
  final suspendedAt = DateTime(2026, 10, 8, 14, 30);

  Map<String, dynamic> baseDoc({DateTime? suspended}) => {
        'requestKey': 'biz1_w1_2026_10',
        'businessId': 'biz1',
        'businessName': '사업장',
        'workerId': 'w1',
        'workerName': '근무자',
        'reviewYear': 2026,
        'reviewMonth': 10,
        'deadline': Timestamp.fromDate(DateTime(2026, 10, 24)),
        'adminStatus': 'pending',
        'workerStatus': 'pending',
        'adminReviewId': null,
        'workerReviewId': null,
        'isPublished': false,
        'publishedAt': null,
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 10)),
        if (suspended != null)
          'eligibilitySuspendedAt': Timestamp.fromDate(suspended),
      };

  ReviewRequestModel fromStore(Map<String, dynamic> data) =>
      ReviewRequestModel.fromFirestore(_Snap(data, 'biz1_w1_2026_10'));

  group('[RER-C1] 보류 필드 왕복', () {
    test('RER-C1-01 Firestore 문서의 보류 시각을 읽는다', () {
      final m = fromStore(baseDoc(suspended: suspendedAt));
      expect(m.eligibilitySuspendedAt, isNotNull);
      expect(m.isEligibilitySuspended, isTrue);
    });

    test('RER-C1-02 필드가 없는 레거시 문서는 보류가 아니다', () async {
      final m = fromStore(baseDoc());
      expect(m.eligibilitySuspendedAt, isNull);
      expect(m.isEligibilitySuspended, isFalse);
    });

    test('RER-C1-03 CF 직렬화 Map({_seconds})에서도 읽는다', () {
      final m = ReviewRequestModel.tryFromMap({
        ...baseDoc(),
        'deadline': {'_seconds': 1792000000, '_nanoseconds': 0},
        'createdAt': {'_seconds': 1791000000, '_nanoseconds': 0},
        'eligibilitySuspendedAt': {
          '_seconds': suspendedAt.millisecondsSinceEpoch ~/ 1000,
          '_nanoseconds': 0,
        },
      }, 'biz1_w1_2026_10');
      expect(m, isNotNull);
      expect(m!.isEligibilitySuspended, isTrue);
    });

    test('RER-C1-04 CF Map 에 필드가 없으면 보류 아님 — 레거시 호환', () {
      final m = ReviewRequestModel.tryFromMap({
        ...baseDoc(),
        'deadline': {'_seconds': 1792000000, '_nanoseconds': 0},
        'createdAt': {'_seconds': 1791000000, '_nanoseconds': 0},
      }, 'biz1_w1_2026_10');
      expect(m, isNotNull);
      expect(m!.isEligibilitySuspended, isFalse);
    });

    test('RER-C1-05 보류는 제출 상태·기한과 독립된 축이다', () async {
      final m = fromStore({
        ...baseDoc(suspended: suspendedAt),
        'adminStatus': 'submitted',
      });
      // 관리자는 이미 제출했고 기한도 남았는데 보류다 — 세 축이 섞이지 않는다.
      expect(m.adminStatus, ReviewPartyStatus.submitted);
      expect(m.workerPending, isTrue);
      expect(m.isEligibilitySuspended, isTrue);
    });
  });

  group('[RER-C2] 보류 필드는 서버 전용', () {
    test('RER-C2-01 toMap 에 보류 필드가 없다', () async {
      final m = fromStore(baseDoc(suspended: suspendedAt));
      expect(m.isEligibilitySuspended, isTrue);
      expect(m.toMap().containsKey('eligibilitySuspendedAt'), isFalse,
          reason: 'toMap 으로 흘러나가면 클라이언트가 보류를 지우는 쓰기가 만들어진다');
    });

    test('RER-C2-02 toMap 은 기존 필드를 그대로 유지한다(회귀)', () async {
      final m = fromStore(baseDoc(suspended: suspendedAt));
      expect(
          m.toMap().keys.toSet(),
          {
            'requestKey', 'businessId', 'businessName', 'workerId',
            'workerName', 'reviewYear', 'reviewMonth', 'deadline',
            'adminStatus', 'workerStatus', 'adminReviewId', 'workerReviewId',
            'isPublished', 'publishedAt', 'createdAt',
          });
    });
  });

  group('[RER-C3] 안내 문구', () {
    const msg = MonthlyReviewService.eligibilitySuspendedMessage;

    test('RER-C3-01 복구 경로를 말한다', () {
      expect(msg, contains('확정'));
      expect(msg, contains('다시 작성'));
    });

    test('RER-C3-02 내부 Firestore 상태를 노출하지 않는다', () {
      for (final forbidden in const [
        'eligibilitySuspendedAt', 'wageStatus', 'calculated',
        'review_requests', 'attendance', 'PERMISSION', 'null',
      ]) {
        expect(msg.contains(forbidden), isFalse,
            reason: '"$forbidden" 는 사용자에게 보여줄 말이 아니다');
      }
    });

    test('RER-C3-03 영구 차단으로 읽히는 말을 쓰지 않는다', () {
      for (final forbidden in const ['영구', '불가능', '취소되었습니다', '삭제']) {
        expect(msg.contains(forbidden), isFalse);
      }
    });
  });

  group('[RER-C4] 리뷰 작성 진입이 보류를 본다', () {
    // 진입 4곳 — 어느 하나라도 빠지면 빈 폼이 열리고, 제출 단계에서야
    // 실패한다. 서버가 canonical 경계이므로 데이터가 오염되지는 않지만
    // 사용자는 다 써 놓고 거부당한다.
    const entries = {
      'lib/screens/common/notification_screen.dart':
          '오래된 알림 deep link',
      'lib/screens/user/my_applications_screen.dart': '내 지원 → 사업장 리뷰',
      'lib/screens/business_admin/admin_review_list_screen.dart':
          '관리자 리뷰 목록',
      'lib/widgets/dialogs/worker_detail_dialog.dart': '근무자 상세 → 리뷰',
    };

    entries.forEach((relPath, label) {
      test('RER-C4 $label 이 보류를 확인한다', () {
        final src = File(relPath).readAsStringSync();
        expect(src.contains('isEligibilitySuspended'), isTrue,
            reason: '$relPath 에 보류 확인이 없다');
        expect(src.contains('eligibilitySuspendedMessage'), isTrue,
            reason: '$relPath 가 복구 가능한 안내를 쓰지 않는다');
      });
    });

    test('RER-C4-06 구버전 앱 경로 — Rules 거부를 복구 안내로 바꾼다', () {
      // 보류 필드를 모르는 구버전 앱은 폼을 열고 제출 단계에서 거부된다.
      // 신규 앱은 그 거부의 원인을 확인해 "실패했습니다" 대신 복구 경로를
      // 말한다. 두 작성 경로 모두에 그 분기가 있어야 한다.
      final src = File('lib/services/monthly_review_service.dart')
          .readAsStringSync();
      expect('_isEligibilitySuspended'.allMatches(src).length,
          greaterThanOrEqualTo(3),
          reason: '정의 1 + 관리자·지원자 경로 2');
    });

    test('RER-C4-05 서비스 양쪽 작성 경로가 요청을 읽고 보류를 거른다', () {
      final src = File('lib/services/monthly_review_service.dart')
          .readAsStringSync();
      // 두 경로(createReviewForUser·createReviewForBusiness) 각각 1회.
      expect(
          'review_eligibility_suspended'.allMatches(src).length,
          greaterThanOrEqualTo(2),
          reason: '관리자·지원자 두 작성 경로 모두에 선행 검사가 있어야 한다');
      // Rules 거부의 원인을 확인하는 경로도 양쪽에 있다.
      expect("e.code == 'permission-denied'".allMatches(src).length, 2);
    });
  });
}
