// [DOCUMENT-VERIFICATION-INTEGRITY-R1.2] 확정 전 지원자 서류 검토
//
// 이 파일이 고정하는 것:
//
//   1. 검토 목적 열람은 **그 목적을 적은 동의**가 있어야 한다. v2는
//      "근무 확정 시 소득신고·급여처리 목적"만 동의했으므로 조용히 올리지 않는다.
//
//   2. 검토 자격은 canManageTo AND canManageWage다. 하나만으로 열면
//      업무 권한자 전원에게 통장이 보이거나, 채용과 무관한 급여 담당자가
//      지원자 신분증을 보게 된다.
//
//   3. 자격이 없으면 계좌 원문은 **DTO에 실리지 않는다**. UI 숨김은
//      이미 나간 값을 되돌리지 못한다.
//
//   4. 검토의 scope는 지원서가 아니라 사업장 × 근로자 × 문서 버전이다.
//      같은 사람이 세 번 지원했다고 같은 신분증을 세 번 볼 이유가 없다.
//      대신 문서가 바뀌면 그 판단은 즉시 낡는다.
//
//   5. 동의는 지원서 단위다 — 검토 재사용과 다른 축이다.
//
//   6. 확정은 현재 검토가 유효할 때만 된다. 경고만 띄우면
//      "미검토 확정 → 근무 → 급여 → 그때 첫 확인"이 그대로 남는다.
//
//   7. 확정하는 사람이 서류를 본 사람일 필요는 없다.
//
//   8. 지급 계좌는 확인한 그 계좌여야 한다. 바뀌었으면 스냅샷하지 않되
//      금액을 0으로 만들지 않는다.
//
//   9. 재등록 요청은 거절이 아니다 — 신뢰도에 닿지 않는다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

String _callableBody(String raw, String name) {
  final start = raw.indexOf('export const $name = onCall(');
  if (start < 0) throw StateError('$name 을 찾지 못함');
  final end = raw.indexOf('\n);', start);
  if (end < 0) throw StateError('$name 본문 끝을 찾지 못함');
  return raw.substring(start, end);
}

/// 선언 [from]부터 다음 선언 [to] 직전까지.
String _sliceOf(String raw, String from, String to) {
  final a = raw.indexOf(from);
  if (a < 0) throw StateError('$from 를 찾지 못함');
  final b = raw.indexOf(to, a + from.length);
  if (b < 0) throw StateError('$to 를 찾지 못함');
  return raw.substring(a, b);
}

const _cf = 'functions/src/index.ts';
const _rules = 'firestore.rules';
const _consent = 'lib/widgets/dialogs/apply/document_access_consent.dart';
const _reviewSvc = 'lib/services/applicant_document_review_service.dart';
const _dialog = 'lib/widgets/dialogs/worker_detail_dialog.dart';

void main() {
  final rawCf = _codeOf(_src(_cf));
  final cf = _flat(rawCf);
  final readiness = _flat(_sliceOf(rawCf,
      'function srvResolveReviewReadiness(', 'async function srvCanReviewApplicantDocuments('));
  final canReview = _flat(_sliceOf(rawCf,
      'async function srvCanReviewApplicantDocuments(',
      'function srvApplicantReviewAccessBlock('));
  final accessBlock = _flat(_sliceOf(rawCf,
      'function srvApplicantReviewAccessBlock(',
      'async function srvMarkCorrectionsResubmitted('));
  final getReview =
      _flat(_callableBody(rawCf, 'callableGetApplicantDocumentReview'));
  final getUrl = _flat(_callableBody(rawCf, 'callableGetApplicantDocumentUrl'));
  final review = _flat(_callableBody(rawCf, 'callableReviewApplicantDocument'));
  final correction =
      _flat(_callableBody(rawCf, 'callableRequestDocumentCorrection'));
  final giveConsent =
      _flat(_callableBody(rawCf, 'callableGiveApplicationDocumentConsent'));
  final confirmApp = _flat(_callableBody(rawCf, 'callableConfirmApplication'));
  final confirmWage = _flat(_callableBody(rawCf, 'callableConfirmFinalWage'));
  final markId = _flat(_callableBody(rawCf, 'callableMarkIdCardVerified'));
  final markBank = _flat(_callableBody(rawCf, 'callableMarkBankbookVerified'));
  final updateBank = _flat(_callableBody(rawCf, 'callableUpdateBankAccount'));
  final rules = _flat(_src(_rules));

  group('R1.2-01 — 검토 열람은 v3 동의를 요구한다', () {
    test('v3 상수와 allowlist', () {
      expect(cf, contains('const DOCUMENT_ACCESS_CONSENT_V3 = "2026-09-18-v3"'));
      expect(cf, contains('DOCUMENT_ACCESS_CONSENT_V3,'));
    });

    test('v2 이하는 검토 목적 열람에서 막힌다', () {
      expect(
        accessBlock,
        contains('appData["documentAccessConsentVersion"] !== '
            'DOCUMENT_ACCESS_CONSENT_V3'),
      );
    });

    test('동의 문구가 채용 검토 목적을 명시한다', () {
      final c = _flat(_codeOf(_src(_consent)));
      expect(c, contains("static const String version = '2026-09-18-v3'"));
      expect(c, contains('지원자 확인 및 채용 검토'));
      expect(c, contains('지원 검토 중'));
      expect(c, contains('거절·취소·만료되면'));
    });

    test('재동의는 v3만 받고 그 지원서에만 적용된다', () {
      expect(giveConsent,
          contains('documentAccessConsentVersion !== DOCUMENT_ACCESS_CONSENT_V3'));
      expect(giveConsent, contains('본인의 지원서만 처리할 수 있습니다'));
      // 새 지원서를 만들지 않는다 — 기존 문서를 갱신한다.
      expect(giveConsent.contains('.add('), isFalse);
    });
  });

  group('R1.2-02 — 검토 자격은 두 권한 모두', () {
    test('canManageTo AND canManageWage', () {
      expect(canReview,
          contains('perms.canManageTo === true && perms.canManageWage === true'));
    });

    test('세 열람·검토 경로가 같은 helper를 쓴다', () {
      for (final body in [getUrl, review, correction]) {
        expect(body, contains('srvCanReviewApplicantDocuments(callerUid, businessId)'));
      }
    });
  });

  group('R1.2-03 — 민감 필드는 DTO에서 뺀다', () {
    test('자격이 없으면 bank 키 자체가 없다', () {
      expect(getReview, contains('...(canSeeDocs ? { bank: {'));
      expect(getReview, contains('} : {}),'));
    });

    test('경로를 클라이언트에서 받지 않는다', () {
      final d = getUrl.substring(getUrl.indexOf('request.data as {'),
          getUrl.indexOf('};', getUrl.indexOf('request.data as {')));
      expect(d.toLowerCase().contains('path'), isFalse);
      expect(getUrl, contains('srvIsOwnedStoragePath(storagePath, targetUid)'));
    });
  });

  group('R1.2-04 — 검토 scope와 낡음', () {
    test('검토 문서 키는 사업장 × 근로자', () {
      expect(cf, contains('function srvBizReviewId(businessId: string, workerUid: string)'));
      expect(cf, contains(r'return `${businessId}_${workerUid}`;'));
    });

    test('낡음 판정은 버전 비교 하나다', () {
      expect(readiness, contains('rIdV !== cur.id'));
      expect(readiness,
          contains('rBbV !== cur.bankbook || rAcV !== cur.account'));
    });

    test('미검토와 낡음을 구분한다', () {
      expect(readiness, contains('idStale'));
      expect(readiness, contains('bankStale'));
      expect(readiness, contains('REVIEW_NOT_REVIEWED'));
    });

    test('검토는 본 버전을 그대로 기록한다', () {
      expect(review, contains('patch["reviewedIdDocumentVersion"] = cur.id;'));
      expect(review,
          contains('patch["reviewedBankbookDocumentVersion"] = cur.bankbook;'));
      expect(review, contains('patch["reviewedBankAccountVersion"] = cur.account;'));
    });

    test('본 적 없는 버전은 승인되지 않는다', () {
      expect(review, contains('curVersion !== expectedVersion'));
      expect(review, contains('서류가 변경되었습니다'));
      expect(review, contains('cur.account !== expectedAccountVersion'));
    });

    test('문서 제출·계좌 변경이 버전을 올린다', () {
      // [PII-DOC-R1.4] 제출 경로의 버전 증가가 increment(1)에서 트랜잭션 내
      //   직접 계산으로 바뀌었다. increment는 결과값을 알려주지 않아 자동
      //   정합성 판정을 **그 버전에** 묶을 수 없기 때문이다.
      //   고정하려던 불변식("제출·계좌 변경은 버전을 올린다")은 그대로다.
      expect(markId, contains('idDocumentVersion: nextV'));
      expect(markId, contains('idCardMatchDocumentVersion: nextV'),
          reason: '판정과 버전이 같은 커밋에 있어야 한다');
      expect(markBank, contains('bankbookDocumentVersion: nextBb'));
      expect(markBank, contains('bankbookMatchDocumentVersion: nextBb'));
      // 계좌 변경은 증가만 하면 되므로 기존 방식 그대로다.
      expect(updateBank,
          contains('bankAccountVersion: admin.firestore.FieldValue.increment(1)'));
      expect(updateBank,
          contains('bankbookDocumentVersion: admin.firestore.FieldValue.increment(1)'));
    });
  });

  group('R1.2-05 — 동의는 지원서 단위', () {
    test('열람 판정이 그 지원서의 동의를 본다', () {
      expect(accessBlock, contains('appData["documentAccessConsentGiven"] !== true'));
      expect(accessBlock, contains('appData["businessId"] !== businessId'));
      expect(accessBlock, contains('appData["uid"] !== targetUid'));
    });

    test('검토 상태는 사업장×근로자, 동의는 지원서 — 축이 다르다', () {
      expect(getReview, contains('srvBizReviewId(businessId, workerUid)'));
      expect(getReview, contains('srvApplicantReviewAccessBlock(appData'));
    });
  });

  group('R1.2-06 — 확정 게이트', () {
    test('PENDING 확정은 현재 서류 판정이 유효해야 한다', () {
      // [PII-DOC-R1.5] 게이트가 읽는 것이 "사람이 두 서류를 다 봤는가"에서
      //   "신분 확인이 현재 유효한가"로 바뀌었다. 자동 정합성이 MATCHED면
      //   사람 검토 없이 통과하고, 급여계좌는 확정을 막지 않는다.
      //   고정하려던 불변식("확정은 현재 유효한 판정을 요구한다")은 그대로다.
      expect(confirmApp,
          contains('srvResolveMatchingReadiness(workerSnap.data(), reviewSnap.data())'));
      expect(confirmApp, contains('if (!readiness.ready)'));
      expect(confirmApp, contains('지원자 신분증 확인이 필요합니다'));
    });

    test('경고만 띄우고 통과시키지 않는다', () {
      expect(confirmApp, contains('throw new HttpsError( "failed-precondition"'));
    });

    test('확정하는 사람에게 canManageWage를 요구하지 않는다', () {
      // 게이트가 보는 것은 검토 문서이지 호출자의 급여 권한이 아니다.
      final gate = confirmApp.substring(
          confirmApp.indexOf('const confirmReviewGate'),
          confirmApp.indexOf('let alreadyConfirmed'));
      expect(gate.contains('canManageWage'), isFalse);
    });

    test('확정에 검토 provenance가 남는다', () {
      expect(confirmApp, contains('documentReviewIdVersion: versions.id'));
      expect(confirmApp, contains('documentReviewBankAccountVersion: versions.account'));
      expect(confirmApp, contains('...(confirmReviewProvenance ?? {})'));
    });
  });

  group('R1.2-07 — 지급 계좌 연속성', () {
    test('스냅샷 전에 현재 검토를 읽는다', () {
      expect(confirmWage, contains('srvResolveReviewReadiness('));
      expect(confirmWage,
          contains('readiness.bankDecision === REVIEW_OK && !readiness.bankStale'));
    });

    test('검토가 낡으면 계좌를 싣지 않는다', () {
      expect(confirmWage, contains('if (bankReviewOkByUid.get(s.id) !== true) return;'));
    });

    test('금액을 0으로 만들지 않고 재확인으로 표시한다', () {
      expect(confirmWage, contains('updateData["wageAccountReviewRequired"] = true;'));
      // 금액 관련 필드를 이 경로에서 건드리지 않는다.
      expect(confirmWage.contains('finalWage: 0'), isFalse);
    });
  });

  group('R1.2-08 — 재등록 요청은 거절이 아니다', () {
    test('지원서 상태를 바꾸지 않는다', () {
      expect(correction.contains('status: "REJECTED"'), isFalse);
      expect(correction.contains('status: "CANCELED"'), isFalse);
      expect(correction.contains('noShow'), isFalse);
      expect(correction.contains('restrictedUntil'), isFalse);
    });

    test('열린 요청은 결정적 id로 하나만', () {
      expect(correction, contains(r'const reqId = `${businessId}_${targetUid}_${documentType}`;'));
      expect(correction, contains('CORRECTION_LIVE.includes('));
    });

    test('재업로드가 요청을 RESUBMITTED로 넘긴다', () {
      expect(cf, contains('async function srvMarkCorrectionsResubmitted('));
      expect(markId, contains('srvMarkCorrectionsResubmitted(callerUid, DOC_TYPE_ID)'));
      expect(markBank,
          contains('srvMarkCorrectionsResubmitted(callerUid, DOC_TYPE_BANKBOOK)'));
    });

    test('알림 payload에 민감정보가 없다', () {
      final data = correction.substring(correction.indexOf('data: {'),
          correction.indexOf('},', correction.indexOf('data: {')));
      expect(data.contains('accountNumber'), isFalse);
      expect(data.contains('storagePath'), isFalse);
      expect(data.contains('bankName'), isFalse);
    });
  });

  group('R1.2-09 — 클라이언트', () {
    test('낡음을 화면이 다시 계산하지 않는다', () {
      final s = _flat(_codeOf(_src(_reviewSvc)));
      expect(s, contains('r[\'idStale\'] == true'));
      expect(s, contains('r[\'bankStale\'] == true'));
      // 버전 비교 로직이 클라이언트에 복제되지 않았다.
      expect(s.contains('reviewedIdDocumentVersion'), isFalse);
    });

    test("'확인 완료'는 사업장 확인이지 진위 보증이 아니다", () {
      final s = _flat(_codeOf(_src(_reviewSvc)));
      expect(s, contains("'서류 확인 완료'"));
      expect(s, contains("'계좌·통장 확인 완료'"));
      expect(s.contains('본인인증 완료'), isFalse);
      expect(s.contains('진위'), isFalse);
    });

    test('본 버전을 그대로 보낸다', () {
      final d = _flat(_codeOf(_src(_dialog)));
      expect(d, contains('expectedVersion: isId ? r.idVersion : r.bankbookVersion'));
      expect(d, contains('expectedAccountVersion: isId ? null : r.accountVersion'));
    });

    test('기존 화면을 확장했다 — 새 대형 화면을 만들지 않았다', () {
      final d = _flat(_codeOf(_src(_dialog)));
      expect(d, contains('_buildApplicantDocumentReviewSection'));
      expect(d, contains("title: '서류 확인'"));
    });

    test('동의 버전 문자열이 한 곳에서만 나온다', () {
      final sheet = _flat(_codeOf(
          _src('lib/widgets/dialogs/confirmed_reassignment_sheet.dart')));
      expect(sheet, contains('DocumentAccessConsent.version'));
      expect(sheet.contains("'2026-09-12-v2'"), isFalse);
    });
  });

  group('R1.2-10 — rules', () {
    test('검토·요청·감사로그는 CF 전용', () {
      expect(rules, contains(
          'match /businessApplicantDocumentReviews/{reviewId} { allow read, write: if false;'));
      expect(rules, contains(
          'match /documentCorrectionRequests/{requestId} { allow read, write: if false;'));
      expect(rules, contains(
          'match /applicant_document_access_logs/{logId} { allow read, write: if false;'));
    });

    test('문서 버전은 클라이언트가 쓸 수 없다', () {
      expect(rules, contains("'idDocumentVersion', 'bankbookDocumentVersion',"));
      expect(rules, contains("'bankAccountVersion',"));
    });
  });
}
