// [APPROVE-REJECT-REASON] 지원 검토 승인 거절 사유 — 문장 매핑(단위) + 화면 catch 계약(구조).
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/utils/approve_review_error_message.dart';

FirebaseFunctionsException _e(String code, [String? message, dynamic details]) =>
    FirebaseFunctionsException(code: code, message: message ?? '', details: details);

void main() {
  group('AR 문장 매핑', () {
    test('AR-1 신분증 미등록 — 근로자가 등록해야 한다고 말한다, 다시 읽지 않는다', () {
      final r = ApproveReviewError.of(_e('failed-precondition', '신분증이 등록되어 있지 않습니다.'), canSetUp: true);
      expect(r.message, ApproveReviewError.idMissingText);
      expect(r.message, contains('근로자가'));
      expect(r.reload, isFalse);
    });
    test('AR-2 신분증 변경 — 관리자가 지원자 상세에서 확인해야 한다고 말한다', () {
      final r = ApproveReviewError.of(_e('failed-precondition', '신분증이 변경되어 다시 확인해야 합니다.'), canSetUp: true);
      expect(r.message, ApproveReviewError.idChangedText);
      expect(r.message, contains('지원자 상세에서'));
      expect(r.reload, isFalse);
    });
    test('AR-3 그 밖의 서버 판정 사유(불일치 등)는 서버 문장 그대로 — 확정 경로와 같다', () {
      const m = '등록된 신원정보와 신분증이 일치하지 않습니다. 지원자 상세에서 신분증을 확인해주세요.';
      expect(ApproveReviewError.of(_e('failed-precondition', m), canSetUp: true).message, m);
    });
    test('AR-4 POSTING_NOT_READY 코드는 접두어를 내보내지 않는다', () {
      final r = ApproveReviewError.of(
          _e('failed-precondition', 'POSTING_NOT_READY:NO_EMPLOYER_SEAL 계약 준비가 안 됐습니다.'), canSetUp: true);
      expect(r.message, isNot(contains('POSTING_NOT_READY')));
      expect(r.message, isNot(contains('NO_EMPLOYER_SEAL')));
    });
    test('AR-5 응답을 못 들은 코드 — 일반 문구 + 목록 다시 읽기, 서버 원문·details 는 쓰지 않는다', () {
      for (final c in ['deadline-exceeded', 'unavailable', 'cancelled', 'internal', 'unknown']) {
        final r = ApproveReviewError.of(_e(c, 'Error: at /srv/functions/lib/index.js:21900 stack', {'path': 'users/x'}), canSetUp: true);
        expect(r.message, ApproveReviewError.genericText, reason: c);
        expect(r.reload, isTrue, reason: c);
      }
    });
    test('AR-6 권한 거절·없는 지원서·모르는 예외', () {
      expect(ApproveReviewError.of(_e('permission-denied', '해당 사업장에 대한 권한이 없습니다.'), canSetUp: true).message,
          '이 사업장의 공고 관리 권한이 없습니다.');
      expect(ApproveReviewError.of(_e('not-found', 'x'), canSetUp: true).reload, isTrue);
      final other = ApproveReviewError.of(StateError('boom /tmp/a.dart'), canSetUp: true);
      expect(other.message, ApproveReviewError.genericText);
      expect(other.reload, isTrue);
      expect(ApproveReviewError.of(_e('invalid-argument', 'raw'), canSetUp: true).message, ApproveReviewError.genericText);
    });
    test('AR-7 서버 판정 문구가 서버 원문과 같다(이 매핑의 열쇠)', () {
      final src = File('functions/src/index.ts').readAsStringSync();
      expect(src.contains('reason: "${ApproveReviewError.serverIdMissing}"'), isTrue);
      expect(src.contains('"${ApproveReviewError.serverIdChanged}"'), isTrue);
    });
  });

  group('AR 화면 catch 계약', () {
    final src = File('lib/screens/business_admin/support_review_queue_screen.dart').readAsStringSync();
    final start = src.indexOf('Future<void> _approveApp(');
    final body = src.substring(start, src.indexOf('Future<void> _rejectApp(', start));
    final catchBlock = body.substring(body.indexOf('} catch (e) {'));
    test('AR-8 거절이면 행을 지우지 않는다 — 제거는 성공 분기에만 있다', () {
      expect(catchBlock.contains('removeWhere'), isFalse);
      expect(body.indexOf('_apps.removeWhere') < body.indexOf('} catch (e) {'), isTrue);
    });
    test('AR-9 로딩 해제 · 다시 읽기는 응답을 못 들은 경우만 · 확인창은 성공 분기 앞', () {
      expect(catchBlock.contains('_isActing = false;'), isTrue);
      expect(catchBlock.contains('if (err.reload) await _load();'), isTrue);
      expect(catchBlock.contains('ToastHelper.showError(err.message);'), isTrue);
      expect(catchBlock.contains("'확정 중 오류가 발생했습니다. 다시 시도해주세요.'"), isFalse,
          reason: '일반 문구는 매퍼가 정한다');
      expect(body.indexOf("title: '확정 확인'") < body.indexOf('updateApplicationStatus('), isTrue);
    });
  });
}
