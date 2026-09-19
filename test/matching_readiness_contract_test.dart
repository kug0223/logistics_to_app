// [PII-DOC-R1.5] 근무 확정 readiness
//
// 이 파일이 고정하는 것:
//
//   MR   자동 MATCHED면 사람 검토 없이 확정 가능. 사람 검토는 fallback으로 남는다.
//   BI   급여계좌 상태는 근무 확정을 막지 않는다. (PD-3)
//   CE   CONFIRMED를 새로 만드는 모든 entry point가 같은 판정을 쓴다.
//   MO   NOT_READY면 좌석·카운터·상태가 하나도 바뀌지 않는다.
//   PR   급여 경로 동작은 R1.5 이전과 같다.
//
// 판정 자체의 truth table은 test/unit/matching_readiness_test.dart.

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

String _sliceOf(String raw, String from, String to) {
  final a = raw.indexOf(from);
  if (a < 0) throw StateError('$from 를 찾지 못함');
  final b = raw.indexOf(to, a + from.length);
  if (b < 0) throw StateError('$to 를 찾지 못함');
  return raw.substring(a, b);
}

const _cfPath = 'functions/src/index.ts';
const _dtoPath = 'lib/services/applicant_document_review_service.dart';
const _detailPath = 'lib/widgets/dialogs/worker_detail_dialog.dart';

void main() {
  final rawCf = _src(_cfPath);
  final cf = _codeOf(rawCf);
  final helper = _codeOf(
      _sliceOf(rawCf, 'function srvResolveMatchingReadiness(', '\n}'));

  group('MR — 판정이 읽는 것과 읽지 않는 것', () {
    test('01 신분 확인만 읽는다', () {
      expect(helper, contains('srvResolveIdCardMatch(userData)'));
      expect(helper, contains('idDecision'));
      expect(helper, contains('reviewedIdDocumentVersion'));
    });

    test('02 급여계좌를 읽지 않는다 (PD-3)', () {
      for (final banned in [
        'bankbookMatchStatus', 'bankAccountVersion', 'bankDecision',
        'bankbookDocumentVersion', 'reviewedBankbookDocumentVersion',
        'reviewedBankAccountVersion', 'wageAccount',
        'srvResolveBankbookMatch',
      ]) {
        expect(helper, isNot(contains(banned)),
            reason: '$banned 는 확정 readiness의 책임이 아니다');
      }
    });

    test('03 원인을 bool 하나로 뭉개지 않는다', () {
      for (final s in [
        'READY_AUTO', 'READY_MANUAL', 'ID_MISSING', 'ID_MISMATCH',
        'ID_OCR_UNCERTAIN', 'ID_UNASSESSED',
      ]) {
        expect(cf, contains('= "$s"'), reason: '상태 $s');
      }
      expect(helper, contains('state:'));
      expect(helper, contains('reason:'));
    });

    test('04 통과 순서: MISSING → 자동 → 사람 fallback', () {
      final iMissing = helper.indexOf('DOC_MATCH_MISSING');
      final iAuto = helper.indexOf('DOC_MATCH_MATCHED');
      final iManual = helper.indexOf('if (manualOk)');
      expect(iMissing, greaterThan(0));
      expect(iMissing, lessThan(iAuto),
          reason: '문서가 없으면 사람 검토가 남아 있어도 통과시키지 않는다');
      expect(iAuto, lessThan(iManual));
    });

    test('05 사람 검토가 낡으면 fallback이 아니다', () {
      expect(_flat(helper),
          contains('const manualOk = manualDec === REVIEW_OK && !manualStale;'));
    });

    test('06 감사 근거를 남긴다 — 왜 통과했는가', () {
      expect(helper, contains('autoMatchStatus: auto.status'));
      expect(helper, contains('manualDecision: manualDec'));
      final gate = _flat(_codeOf(
          _sliceOf(rawCf, 'const confirmReviewGate =', '};')));
      expect(gate, contains('matchingReadinessState: readiness.state'));
      expect(gate, contains('matchingAutoMatchStatus: readiness.autoMatchStatus'));
    });

    test('07 assurance를 과장하지 않는다', () {
      // 자동 통과가 진위 인증이라는 주장으로 번지지 않게 한다.
      expect(rawCf, contains('SERVER_VERIFIED로 올리지 않는다'));
      expect(cf, isNot(contains('SERVER_VERIFIED')));
    });
  });

  group('CE — 모든 CONFIRMED entry point가 같은 판정', () {
    test('08 직접 확정이 새 helper를 쓴다', () {
      final gate = _flat(_codeOf(
          _sliceOf(rawCf, 'const confirmReviewGate =', '};')));
      expect(gate,
          contains('srvResolveMatchingReadiness(workerSnap.data(), reviewSnap.data())'));
      // 옛 helper는 더 이상 확정을 막지 않는다.
      expect(gate, isNot(contains('srvResolveReviewReadiness')));
    });

    test('09 초대 수락도 같은 helper를 쓴다', () {
      final accept = _flat(_codeOf(_sliceOf(rawCf,
          'export const callableAcceptTOInvitation = onCall(', '\n);')));
      expect(accept, contains('srvResolveMatchingReadiness(freshUserData,'));
      expect(accept, contains('acceptReadiness.ready'));
    });

    test('10 초대 수락이 게이트를 우회하지 않는다', () {
      // R1.2에서 이 경로만 빠져 있었다 — entry point가 우회하면 게이트가 아니다.
      final accept = _codeOf(_sliceOf(rawCf,
          'export const callableAcceptTOInvitation = onCall(', '\n);'));
      expect(accept, contains('BIZ_DOC_REVIEW_COL'));
      expect(accept, contains('srvBizReviewId('));
    });

    test('11 재배치·계약서명·갱신은 재검증하지 않는다 (의도)', () {
      // 이미 확정된 관계를 옮기거나 완료하는 것이지 새 약속이 아니다.
      // 여기서 재검증하면 문서가 낡았다는 이유로 정상 업무가 막힌다.
      for (final entry in [
        'export const callableAcceptConfirmedReassignment = onCall(',
        'export const callableFinalizeWorkerSignature = onCall(',
      ]) {
        final body = _codeOf(_sliceOf(rawCf, entry, '\n);'));
        expect(body, isNot(contains('srvResolveMatchingReadiness')),
            reason: '$entry — 기존 확정의 연장이다');
      }
    });
  });

  group('BI — 급여계좌가 확정을 막지 않는다', () {
    test('12 확정 게이트가 통장 판정을 읽지 않는다', () {
      final gate = _flat(_codeOf(
          _sliceOf(rawCf, 'const confirmReviewGate =', '};')));
      expect(gate, isNot(contains('bankDecision')));
      expect(gate, isNot(contains('bankStale')));
      expect(gate, isNot(contains('bankbookMatch')));
    });

    test('13 초대 수락 게이트도 마찬가지', () {
      final slice = _flat(_codeOf(_sliceOf(rawCf,
          'const acceptReviewSnap = await tx.get(', 'acceptReadiness.reason')));
      expect(slice, isNot(contains('bankDecision')));
      expect(slice, isNot(contains('bankbookMatch')));
    });

    test('15 확정 차단 사유는 matchingReason 하나다', () {
      final d = _flat(_codeOf(_src(_detailPath)));
      expect(d, contains('if (!r.matchingReady && r.matchingReason != null)'));
      expect(d, contains('급여정보는 지급 전까지 확인하면 됩니다'));
      // 옛 문장(사람 검토 기반 reason)은 확정 사유로 쓰지 않는다.
      expect(d, isNot(contains('if (!r.ready && r.reason != null)')));
    });
  });

  group('MO — NOT_READY면 아무것도 바뀌지 않는다', () {
    test('16 직접 확정: 게이트가 트랜잭션보다 앞에 있다', () {
      final body = _codeOf(_sliceOf(rawCf,
          'export const callableConfirmApplication = onCall(',
          '// ── 1. 트랜잭션'));
      expect(body, contains('await confirmReviewGate();'));
      // 좌석·카운터를 건드리는 트랜잭션은 그 뒤에 온다.
      final iGate = rawCf.indexOf('await confirmReviewGate();');
      final iTx = rawCf.indexOf('// ── 1. 트랜잭션', iGate);
      expect(iTx, greaterThan(iGate));
    });

    test('17 초대 수락: 게이트가 좌석 확보보다 앞에 있다', () {
      final accept = _src(_cfPath);
      final iGate = accept.indexOf('const acceptReadiness =');
      final iSeat = accept.indexOf('srvCollectSeatCommitOverlap(tx, {', iGate);
      expect(iGate, greaterThan(0));
      expect(iSeat, greaterThan(iGate),
          reason: '좌석을 잡은 뒤 막으면 되돌릴 것이 생긴다');
    });

    test('18 게이트는 throw로 끝난다 — 부분 적용 없음', () {
      expect(_flat(helper), isNot(contains('tx.update')));
      expect(_flat(helper), isNot(contains('.set(')));
    });
  });

  group('PR — 급여 동작 변화 없음', () {
    test('19 급여 확정은 옛 helper를 그대로 쓴다', () {
      final wage = _flat(_codeOf(_sliceOf(rawCf,
          'export const callableConfirmFinalWage = onCall(',
          'export const callableCancelFinalConfirmation')));
      // [PII-DOC-R1.6] 급여는 이제 Payroll Readiness를 쓴다. 이 테스트가
      //   지키는 것은 **신분 판정이 급여를 열지 않는다**이고 그대로다.
      expect(wage, contains('srvResolvePayrollReadiness('));
      expect(wage, isNot(contains('srvResolveMatchingReadiness')),
          reason: '자동 신분 MATCHED가 급여를 새로 열면 안 된다');
      expect(wage, contains('payReadinessByUid'));
      expect(wage, contains('wageAccountReviewRequired'));
    });

    test('20 옛 helper는 삭제되지 않았다', () {
      expect(cf, contains('function srvResolveReviewReadiness('));
      expect(cf, contains('BIZ_DOC_REVIEW_COL'),
          reason: '사람 검토 컬렉션은 fallback·급여·legacy에서 아직 필요하다');
    });

    test('21 DTO가 기존 readiness 의미를 덮어쓰지 않는다', () {
      final dto = _flat(_codeOf(_sliceOf(rawCf,
          'export const callableGetApplicantDocumentReview = onCall(', '\n);')));
      expect(dto, contains('readiness: {'));
      expect(dto, contains('matchingReadiness: srvResolveMatchingReadiness(u, reviewSnap.data())'));
    });

    test('22 클라이언트도 두 값을 따로 담는다', () {
      final dto = _codeOf(_src(_dtoPath));
      expect(dto, contains('final bool ready;'));
      expect(dto, contains('final bool matchingReady;'));
      expect(dto, contains("matchingReady: mr['ready'] == true"));
    });
  });

  group('민감정보 — 자동 통과가 접근 권한을 열지 않는다', () {
    test('23 MATCHED가 신분증 원본을 자동으로 열지 않는다', () {
      final url = _flat(_codeOf(_sliceOf(rawCf,
          'export const callableGetApplicantDocumentUrl = onCall(', '\n);')));
      expect(url, isNot(contains('MatchStatus')));
      expect(url, isNot(contains('srvResolveMatchingReadiness')));
      final signed = _flat(_codeOf(_sliceOf(rawCf,
          'export const callableGetIdCardSignedUrl = onCall(', '\n);')));
      expect(signed, isNot(contains('MatchStatus')));
    });

    test('24 CONFIRMED auto-grant는 이번에 건드리지 않았다 (PII-B4 유지)', () {
      expect(cf, contains('async function ensureIdCardGrantForConfirmedApplication('));
      final grant = _flat(_codeOf(_sliceOf(rawCf,
          'async function ensureIdCardGrantForConfirmedApplication(', '\n}')));
      expect(grant, isNot(contains('MatchStatus')));
    });
  });

  // ═══════════════════════════════════════════════════════════
  // [PII-DOC-R1.5.1] 초대 수락 parity
  //
  //   R1.5는 확정 게이트를 신분 확인으로 좁혔지만, 초대 수락에는 그보다
  //   앞선 계좌·통장 prerequisite가 남아 있었다. 그래서 같은 신규 약속이
  //   어느 버튼을 눌렀느냐에 따라 다른 규칙을 따랐다.
  // ═══════════════════════════════════════════════════════════
  // [PII-DOC-R1.5.4] 이 group 은 R1.5.1 의 "초대 수락에 지급 prerequisite
  //   없음"을 고정하고 있었다. 그 근거였던 R1.5.2 의 "지원 = payment 무관"
  //   전제가 제품정책 오류로 철회되어, 초대 수락은 지원과 같은 Applicant
  //   Onboarding Readiness 를 다시 요구한다.
  //   이 group 이 지키는 것은 원래부터 **두 경로가 같은 규칙을 쓴다**였고
  //   그 부분은 그대로다. onboarding 계약 본문은
  //   test/applicant_onboarding_readiness_contract_test.dart.
  group('초대 수락과 직접 확정이 같은 규칙을 쓴다', () {
    final accept = _codeOf(_sliceOf(rawCf,
        'export const callableAcceptTOInvitation = onCall(', '\n);'));

    test('26 계좌 presence 를 직접 보지 않고 canonical helper 를 쓴다', () {
      for (final direct in [
        'freshUserData.bankName',
        'freshUserData.accountNumber',
        'freshUserData.accountHolder',
        'freshUserData.bankbookImagePath',
        'freshUserData.bankbookImageUrl',
      ]) {
        expect(accept, isNot(contains(direct)),
            reason: '$direct — 지원과 같은 판정처를 써야 비대칭이 안 생긴다');
      }
      expect(accept,
          contains('srvMissingApplicantPayoutRegistration(freshUserData)'));
    });

    test('27 검수·판정 상태는 여전히 읽지 않는다', () {
      for (final gone in [
        'bankVerificationStatus', 'isBankbookVerified',
        'bankbookDocumentState', 'bankbookMatchStatus', 'bankDecision',
        'wageAccount',
      ]) {
        expect(accept, isNot(contains(gone)), reason: gone);
      }
    });

    test('28 T2 — 신원 prerequisite는 그대로 유지된다', () {
      // 제거한 것은 지급 축이지 신원 축이 아니다.
      expect(accept, contains('srvIsForeignIdentity(freshUserData)'));
      expect(accept, contains('freshUserData.passVerifiedAt'));
      expect(accept, contains('freshUserData.idCardImagePath'));
      expect(accept, contains('freshUserData.isIdVerified !== true'));
      expect(accept, contains('srvResolveMatchingReadiness(freshUserData,'));
    });

    test('29 general integrity 검사도 그대로다', () {
      for (final kept in [
        'accountStatus', 'restrictedUntil', 'isBlacklisted',
        'acceptDocConsentGiven', 'srvCollectSeatCommitOverlap',
      ]) {
        expect(accept, contains(kept), reason: kept);
      }
    });

    test('30 T3·T4 — 두 경로가 같은 판정 하나만 쓴다', () {
      // 확정 게이트와 초대 게이트가 같은 helper를 부르므로 BANK MISSING /
      // BANK MISMATCH에서 결과가 갈릴 수 없다.
      final gate = _flat(_codeOf(
          _sliceOf(rawCf, 'const confirmReviewGate =', '};')));
      expect(gate, contains('srvResolveMatchingReadiness('));
      expect(_flat(accept), contains('srvResolveMatchingReadiness('));
      // 그리고 그 helper는 통장을 읽지 않는다 (위 02에서 고정).
    });

    test('31 T9 — 경계는 그대로: 재배치·서명·갱신은 재검증하지 않는다', () {
      for (final entry in [
        'export const callableAcceptConfirmedReassignment = onCall(',
        'export const callableFinalizeWorkerSignature = onCall(',
      ]) {
        final body = _codeOf(_sliceOf(rawCf, entry, '\n);'));
        expect(body, isNot(contains('srvResolveMatchingReadiness')),
            reason: '$entry — 기존 확정의 이동·완성이다');
      }
      final renewal = _codeOf(
          _sliceOf(rawCf, 'async function processContractRenewalChecks(', '\n}'));
      expect(renewal, isNot(contains('srvResolveMatchingReadiness')));
    });

    test('32 T8 — 급여 CF semantics 무변경', () {
      final wage = _flat(_codeOf(_sliceOf(rawCf,
          'export const callableConfirmFinalWage = onCall(',
          'export const callableCancelFinalConfirmation')));
      expect(wage, contains('srvResolvePayrollReadiness('));
      expect(wage, isNot(contains('srvResolveMatchingReadiness')));
    });

    test('33 지원과 초대 수락이 같은 onboarding contract 를 쓴다', () {
      final apply = _codeOf(_sliceOf(rawCf,
          'export const callableApplyToTO = onCall(', '\n);'));
      expect(apply, contains('srvMissingApplicantPayoutRegistration(userData)'));
      expect(accept,
          contains('srvMissingApplicantPayoutRegistration(freshUserData)'));
    });

    test('34 클라이언트도 두 경로가 같은 게이트를 지난다', () {
      // R1.5.1 은 CTA 빌드만 보고 "클라이언트 변경 불필요"라고 판단했는데,
      // 수락 **동작**이 meetsApplyPrerequisites 를 지난다는 것을 놓쳤다.
      // 그 함수가 지원과 초대 수락 공통 게이트라는 사실이 여기서 중요하다.
      final gate = _codeOf(_sliceOf(
          _src('lib/screens/user/apply_prerequisites_screen.dart'),
          'bool meetsApplyPrerequisites(', '\n}'));
      expect(gate, contains('hasBankAccount'));
      expect(gate, contains('hasBankbookDocument'));

      final s = _src('lib/screens/common/job_posting_screen.dart');
      final act = _flat(_codeOf(
          _sliceOf(s, 'Future<void> _acceptInviteFromDetail(', '\n  }')));
      expect(act, contains('meetsApplyPrerequisites('));
      expect(_src('lib/screens/user/my_applications_screen.dart'),
          contains('meetsApplyPrerequisites('));
    });
  });

  group('문구', () {
    test('25 자동 일치를 "인증 완료"라 하지 않는다', () {
      final dto = _codeOf(_src(_dtoPath));
      expect(dto, contains("return '서류 정보 일치';"));
      for (final banned in ['신분증 인증 완료', '계좌 인증 완료', '금융기관 검증']) {
        expect(dto, isNot(contains(banned)));
        expect(_codeOf(_src(_detailPath)), isNot(contains(banned)));
      }
    });
  });
}
