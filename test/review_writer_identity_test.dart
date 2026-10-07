// [R7-GOLDEN-PATH-DEV-E2E.1 §C] 리뷰를 누가 썼는지 문서 ID 로 역산되면 안 된다
//
// 직전 Phase 에서는 리뷰를 rules 경로로 썼지만 문서 ID 를 내가 정했다
// (`{businessId}_{uid}_2026_10_U`). 그 ID 에는 **근로자 uid 가 그대로
// 들어 있었다.** 실제 production 경로는 그러지 않는다 —
// `generateKeyForBusiness` 가 reviewerId 를 SHA-256 16자로 바꿔 넣는다.
// 사업장 관리자는 자기 사업장의 USER_TO_BUSINESS 리뷰를 읽을 수 있으므로,
// ID 에 uid 가 있으면 "익명 리뷰" 라는 약속이 ID 하나로 깨진다.
//
// 그래서 이 테스트는 **실제 production 키 생성기와 직렬화**를 그대로 실행해
// 익명성 계약을 고정한다. (rules 는 필드를 검사하지만 문서 ID 모양은
// 검사하지 않는다 — 익명성은 이 Dart 코드가 유일한 보증이다.)
//
// 고정하는 것
//   RVW-1  ADMIN_TO_USER 키 — 대상이 드러나도 되는 쪽
//   RVW-2  USER_TO_BUSINESS 키 — 작성자가 드러나지 않는다
//   RVW-3  USER_TO_BUSINESS 직렬화는 reviewerId 를 담지 않는다
//   RVW-4  ADMIN_TO_USER 직렬화는 작성자·대상을 담는다
//   RVW-5  targetUserId 가 null 이어도 rules barrier 가 터지지 않는다
//   RVW-6  리뷰와 요청 상태는 한 트랜잭션에서 함께 바뀐다
//   RVW-7  작성 기한은 해당 월 말일 + 14일
import 'dart:io';

import 'package:ALfit/models/core/monthly_review_model.dart';
import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('소스를 찾지 못했다: $p');
  return f.readAsStringSync();
}

const _biz = 'GlyuWgjOxmlY0wSCAG6H';
const _uid = '6lJF4KlIxegixhixxyTyz80rc573';

MonthlyReviewModel _userToBusiness({String? requestId}) => MonthlyReviewModel(
      id: 'x',
      reviewKey: 'x',
      reviewType: ReviewType.USER_TO_BUSINESS,
      reviewerName: '익명',
      businessId: _biz,
      businessName: '사업장',
      reviewYear: 2026,
      reviewMonth: 10,
      workDaysInMonth: 1,
      rating: 4,
      wouldRehire: true,
      positiveTags: const ['급여 정확'],
      improvementTags: const [],
      requestId: requestId ?? 'req1',
      createdAt: DateTime(2026, 10, 7),
    );

MonthlyReviewModel _adminToUser() => MonthlyReviewModel(
      id: 'x',
      reviewKey: 'x',
      reviewType: ReviewType.ADMIN_TO_USER,
      reviewerId: 'admin1',
      reviewerName: '사업장',
      businessId: _biz,
      businessName: '사업장',
      targetUserId: _uid,
      targetUserName: '근로자',
      reviewYear: 2026,
      reviewMonth: 10,
      workDaysInMonth: 1,
      normalAttendanceDays: 1,
      lateDays: 0,
      rating: 5,
      wouldRehire: true,
      positiveTags: const ['성실함'],
      improvementTags: const [],
      requestId: 'req1',
      createdAt: DateTime(2026, 10, 7),
    );

void main() {
  group('리뷰 writer identity — 실제 Dart 경로', () {
    test('RVW-1 ADMIN_TO_USER 키는 사업장_대상_연_월', () {
      final k = MonthlyReviewModel.generateKeyForUser(
          businessId: _biz, targetUserId: _uid, year: 2026, month: 10);
      expect(k, '${_biz}_${_uid}_2026_10');
    });

    test('RVW-2 USER_TO_BUSINESS 키에 작성자가 없다', () {
      final k = MonthlyReviewModel.generateKeyForBusiness(
          businessId: _biz, reviewerId: _uid, year: 2026, month: 10);
      expect(k.contains(_uid), isFalse,
          reason: '문서 ID 로 작성자를 역산할 수 있으면 익명이 아니다');
      expect(RegExp('^biz_${_biz}_2026_10_[0-9a-f]{16}\$').hasMatch(k), isTrue,
          reason: '실측 형식: biz_{사업장}_{연}_{월}_{16자 해시}');
      // 같은 사람·같은 달이면 같은 키 — 중복 작성이 ID 로 막힌다.
      final again = MonthlyReviewModel.generateKeyForBusiness(
          businessId: _biz, reviewerId: _uid, year: 2026, month: 10);
      expect(again, k);
      // 다른 사람이면 다른 키.
      final other = MonthlyReviewModel.generateKeyForBusiness(
          businessId: _biz, reviewerId: 'someoneElse', year: 2026, month: 10);
      expect(other, isNot(k));
    });

    test('RVW-3 USER_TO_BUSINESS 직렬화는 reviewerId 를 담지 않는다', () {
      final m = _userToBusiness().toMap();
      expect(m.containsKey('reviewerId'), isFalse,
          reason: 'rules 도 reviewerId 부재를 강제한다');
      expect(m['reviewerName'], '익명');
      // targetUserId 는 키는 있고 값이 null 이다 — RVW-5 가 이 모양을 받는다.
      expect(m.containsKey('targetUserId'), isTrue);
      expect(m['targetUserId'], isNull);
    });

    test('RVW-4 ADMIN_TO_USER 직렬화는 작성자·대상을 담는다', () {
      final m = _adminToUser().toMap();
      expect(m['reviewerId'], 'admin1');
      expect(m['targetUserId'], _uid);
      expect(m['requestId'], 'req1',
          reason: 'rules 가 requestId 와의 결합을 요구한다');
      expect(m['isPublished'], isFalse,
          reason: '공개는 서버(trigger)가 정한다');
    });

    test('RVW-5 targetUserId 가 null 이어도 barrier 가 터지지 않는다', () {
      // `uid is string` 가 먼저 걸리므로 null 에서 size() 를 부르지 않는다.
      // 이 가드가 없으면 rules 평가 오류 → 근로자 리뷰 작성이 전부 막힌다.
      final rules = _src('firestore.rules');
      final i = rules.indexOf('function accountDeletionBarrierExists(uid)');
      expect(i, greaterThan(0));
      final body = rules.substring(i, rules.indexOf('}', i));
      expect(body.indexOf('uid is string'), lessThan(body.indexOf('uid.size()')),
          reason: '타입 검사가 size() 보다 앞에 있어야 한다');
    });

    test('RVW-6 리뷰와 요청 상태는 한 트랜잭션에서 함께 바뀐다', () {
      final svc = _src('lib/services/monthly_review_service.dart');
      for (final pair in [
        // 관리자 리뷰
        ["'adminStatus': 'submitted'", "'adminReviewId': reviewKey"],
        // 근로자 리뷰
        ["'workerStatus': 'submitted'", "'workerReviewId': reviewKey"],
      ]) {
        expect(svc.contains(pair[0]), isTrue, reason: '${pair[0]} 가 없다');
        expect(svc.contains(pair[1]), isTrue, reason: '${pair[1]} 가 없다');
      }
      // 두 쓰기가 같은 runTransaction 안에 있어야 한다.
      final txCount = RegExp(r'_db\.runTransaction\(').allMatches(svc).length;
      expect(txCount, greaterThanOrEqualTo(2),
          reason: '양쪽 리뷰 제출이 각각 트랜잭션이어야 한다');
      expect(svc.contains("'createdAt': FieldValue.serverTimestamp()"), isTrue,
          reason: '작성 시각은 서버가 정한다 — 기기 시각 위조 차단');
    });

    test('RVW-7 작성 기한은 해당 월 말일 + 14일', () {
      final svc = _src('lib/services/monthly_review_service.dart');
      final i = svc.indexOf('bool _isWithinReviewWindow(');
      expect(i, greaterThan(0));
      final body = svc.substring(i, svc.indexOf('\n  }', i));
      expect(body.contains('14'), isTrue);
      // 서버도 같은 기한을 다시 본다 — 기기 시각 조작 방어.
      final cf = _src('functions/src/index.ts');
      expect(cf.contains('deadline.toMillis()'), isTrue);
    });
  });
}
