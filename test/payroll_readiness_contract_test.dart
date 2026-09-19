// [PII-DOC-R1.6] PAYROLL READINESS
//
// 이 파일이 고정하는 것:
//
//   PR   지급 준비 판정이 읽는 것과 읽지 않는 것, 그리고 통과 순서.
//   ID   신분 상태가 이미 수행된 근무의 지급을 막지 않는다.
//   FW   임금 확정과 지급 준비는 다른 일이다 — NOT READY여도 금액은 남는다.
//   ST   확정 뒤 계좌가 바뀌면 이체 직전에 막는다.
//   RF   금액을 건드리지 않고 지급 스냅샷만 갱신하는 경로가 있다.
//   SP   세 readiness 를 하나로 합치지 않는다.
//   UI   문구는 하지 않은 확인을 주장하지 않는다.

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
const _planPath = 'lib/utils/transfer_export_plan.dart';
const _wageScreen = 'lib/screens/user/wage_detail_screen.dart';

void main() {
  final rawCf = _src(_cfPath);
  final helper = _codeOf(_sliceOf(rawCf,
      'function srvResolvePayrollReadiness(', '\n}'));
  final wage = _codeOf(_sliceOf(rawCf,
      'export const callableConfirmFinalWage = onCall(',
      'export const callableCancelFinalConfirmation'));
  final refresh = _codeOf(_sliceOf(rawCf,
      'export const callableRefreshWagePaymentSnapshot = onCall(', '\n);'));
  final xfer = _codeOf(_sliceOf(rawCf,
      'export const callableMarkTransferredBatch = onCall(', '\n);'));
  final stale = _codeOf(_sliceOf(rawCf,
      'function srvWageSnapshotStaleReason(', '\n}'));

  // ── PR. 판정 ────────────────────────────────────────────────────
  group('PR — 지급 준비 판정', () {
    test('01 현재 계좌·현재 통장사본·현재 버전을 읽는다 (§5)', () {
      expect(helper, contains('u["bankName"]'));
      expect(helper, contains('u["accountNumber"]'));
      expect(helper, contains('u["accountHolder"]'));
      expect(helper, contains('srvResolveBankbookMatch(userData)'));
      expect(helper, contains('srvDocumentVersionsOf(u)'));
    });

    test('02 PR5·PR6 — 없는 것이 먼저다', () {
      // 보낼 곳이 없으면 그 다음은 볼 것도 없다.
      final iAcc = helper.indexOf('PR_MISSING_BANK_ACCOUNT');
      final iBb = helper.indexOf('PR_MISSING_BANKBOOK');
      final iAuto = helper.indexOf('PR_READY_AUTO');
      final iManual = helper.indexOf('PR_READY_MANUAL');
      expect(iAcc, greaterThan(-1));
      expect(iAcc < iBb, true);
      expect(iBb < iAuto, true, reason: '통장사본 없음이 자동 통과보다 먼저');
      expect(iAuto < iManual, true, reason: 'PR1 — 자동이 사람보다 먼저');
    });

    test('03 §8 — 없는 지급정보를 사람 검토로 되살리지 않는다', () {
      // manualOk 판정이 MISSING 분기보다 **뒤**에 있어야 한다.
      final iMissing = helper.indexOf('PR_MISSING_BANK_ACCOUNT');
      final iManualOk = helper.indexOf('if (manualOk)');
      expect(iManualOk, greaterThan(iMissing));
    });

    test('04 PR1 — 자동 MATCHED면 사람 검토 없이 통과한다 (§14)', () {
      expect(_flat(helper), contains(
          'if (auto.status === DOC_MATCH_MATCHED) { return {...base, '
          'ready: true, state: PR_READY_AUTO, reason: null, '
          'source: PAY_SOURCE_AUTO}; }'));
    });

    test('05 PR2·PR3 — 자동이 못 하면 사람 검토가 fallback이다', () {
      expect(helper, contains('manualDec === REVIEW_OK && !manualStale'));
      expect(_flat(helper), contains('state: PR_READY_MANUAL'));
    });

    test('06 PR7·PR8 — 낡은 근거는 통과가 아니다', () {
      expect(helper, contains('rBbV !== versions.bankbook'));
      expect(helper, contains('rAcV !== versions.account'));
      expect(helper, contains('PR_STALE_AUTO_MATCH'));
      expect(helper, contains('PR_STALE_MANUAL_REVIEW'));
    });

    test('07 PR4 — 원인을 bool 하나로 뭉개지 않는다 (§10)', () {
      for (final s in [
        'PR_MISSING_BANK_ACCOUNT', 'PR_MISSING_BANKBOOK',
        'PR_BANK_MISMATCH', 'PR_BANK_OCR_UNCERTAIN', 'PR_BANK_UNASSESSED',
        'PR_STALE_AUTO_MATCH', 'PR_STALE_MANUAL_REVIEW',
      ]) {
        expect(helper, contains(s), reason: s);
      }
    });

    test('08 §9 — 사람 판정이 자동 판정을 덮어쓰지 않는다', () {
      // 이 helper 는 읽기만 한다 — 어떤 쓰기도 하지 않는다.
      for (final w in ['.update(', '.set(', 'FieldValue']) {
        expect(helper, isNot(contains(w)), reason: w);
      }
    });

    test('09 §7 — assurance 를 올리지 않는다', () {
      // 주석에는 "쓰지 않는다"는 설명이 남아 있다 — 코드에 없어야 한다.
      final code = _codeOf(rawCf);
      for (final banned in [
        'SERVER_VERIFIED', 'BANK_VERIFIED', '계좌 인증 완료',
        '금융기관 확인 완료',
      ]) {
        expect(code, isNot(contains(banned)), reason: banned);
      }
    });

    test('10 §41 — 사람 fallback 은 사업장 범위를 벗어나지 않는다', () {
      // 호출자가 이 사업장의 검토 문서를 넘긴다.
      expect(wage, contains('srvBizReviewId(businessId, uid)'));
      expect(refresh, contains('srvBizReviewId(businessId, u)'));
    });
  });

  // ── ID. 신분 독립 ───────────────────────────────────────────────
  group('ID — 지급 준비는 신분 상태를 읽지 않는다 (§6)', () {
    test('11 helper 가 신분 축을 읽지 않는다', () {
      for (final f in [
        'idCard', 'idDocumentVersion', 'srvResolveMatchingReadiness',
        'passVerifiedAt', 'srvIsForeignIdentity', 'idDecision',
      ]) {
        expect(helper, isNot(contains(f)), reason: f);
      }
    });

    test('12 급여 확정도 Matching Readiness 를 끌어오지 않는다', () {
      expect(wage, contains('srvResolvePayrollReadiness('));
      expect(wage, isNot(contains('srvResolveMatchingReadiness')));
    });
  });

  // ── FW. 금액과 지급 준비의 분리 ─────────────────────────────────
  group('FW — 임금 확정 ≠ 이체 준비 (§11)', () {
    test('13 FW3 — NOT READY 여도 확정 자체를 실패시키지 않는다', () {
      // 준비 안 됨은 throw 가 아니라 기록이다.
      expect(_flat(wage), contains('updateData["wageAccountReviewRequired"] = true'));
      expect(wage, isNot(contains('지급 준비가 되지 않아 마감할 수 없습니다')));
    });

    test('14 FW3 — 사유를 남긴다 (§31)', () {
      expect(_flat(wage),
          contains('updateData["wageAccountReadinessReason"] = payReadiness?.state'));
    });

    test('15 FW1·FW2 — READY 면 스냅샷과 근거 버전을 기록한다 (§12)', () {
      for (final f in [
        'wageAccountBankName', 'wageAccountNumberEncrypted',
        'wageAccountHolder', 'wageAccountSnapshotAt',
        'wageAccountSourceBankAccountVersion',
        'wageAccountSourceBankbookDocumentVersion',
        'wagePaymentReadinessSource',
      ]) {
        expect(wage, contains(f), reason: f);
      }
      expect(wage, contains('PAY_SOURCE_AUTO'));
    });

    test('16 §13 — NOT READY 면 이전 스냅샷을 지운다', () {
      final block = _flat(_sliceOf(_codeOf(rawCf),
          'if (!hasFullAccount) {', '} else {'));
      for (final f in [
        'wageAccountBankName', 'wageAccountNumberEncrypted',
        'wageAccountHolder', 'wageAccountSnapshotAt',
        'wageAccountSourceBankAccountVersion',
        'wageAccountSourceBankbookDocumentVersion',
        'wagePaymentReadinessSource',
      ]) {
        expect(block, contains('"$f"'), reason: '$f 를 지워야 이체가 열리지 않는다');
      }
      expect(block, contains('FieldValue.delete()'));
    });

    test('17 금액을 0으로 만들지 않는다', () {
      final b = _flat(_sliceOf(_codeOf(rawCf),
          'if (!hasFullAccount) {', '} else {'));
      for (final f in ['finalWage', 'netWage', 'wageDetail']) {
        expect(b, isNot(contains(f)), reason: f);
      }
    });
  });

  // ── ST. 이체 직전 낡음 ──────────────────────────────────────────
  group('ST — 확정 이후 계좌가 바뀌면 막는다 (§16·§17)', () {
    test('18 PF1 — 근거 버전과 현재 버전을 비교한다', () {
      expect(stale, contains('wageAccountSourceBankAccountVersion'));
      expect(stale, contains('wageAccountSourceBankbookDocumentVersion'));
      expect(stale, contains('srvDocumentVersionsOf(user'));
      expect(stale, contains('XFER_STALE_PAYMENT_SNAPSHOT'));
    });

    test('19 근거가 없으면 알 수 없음이다 — 통과로 바꾸지 않는다', () {
      expect(stale, contains('XFER_SNAPSHOT_PROVENANCE_UNKNOWN'));
      expect(_flat(stale), contains(
          'if (typeof srcAcc !== "number" || typeof srcBb !== "number") '
          '{ return XFER_SNAPSHOT_PROVENANCE_UNKNOWN; }'));
    });

    test('20 §18 — 현재 계좌를 이체 원본으로 쓰지 않는다', () {
      // 이체 CF 는 users 문서를 버전 판정에만 쓴다.
      expect(xfer, contains('srvWageSnapshotStaleReason('));
      for (final f in [
        'wageAccountBankName: ', 'd.bankName', 'u["bankName"]',
      ]) {
        expect(xfer, isNot(contains(f)), reason: '$f — 돈은 스냅샷으로만 나간다');
      }
    });

    test('21 판정과 이체가 같은 트랜잭션 안이다', () {
      final tx = _sliceOf(xfer, 'await db.runTransaction(', 'tx.update(snap.ref');
      expect(tx, contains('tx.get(db.collection("users")'));
      expect(tx, contains('srvWageSnapshotStaleReason('));
    });

    test('22 §19 — 이미 이체된 건은 다시 열지 않는다', () {
      final i = xfer.indexOf('alreadyTransferred.push(id)');
      final j = xfer.indexOf('srvWageSnapshotStaleReason(');
      expect(i, greaterThan(-1));
      expect(i < j, true, reason: '멱등 통과가 낡음 판정보다 먼저다');
    });

    test('23 §42 — 단건도 같은 CF 를 쓴다', () {
      final svc = _src('lib/services/payroll_payment_service.dart');
      expect(svc, contains('callableMarkTransferredBatch'));
      expect(_codeOf(svc), isNot(contains('callableMarkTransferredSingle')));
    });
  });

  // ── RF. 스냅샷 갱신 ─────────────────────────────────────────────
  group('RF — 금액을 건드리지 않고 스냅샷만 갱신한다 (§20·§21)', () {
    test('24 PF2 — 갱신 writer 가 존재한다', () {
      expect(rawCf, contains('callableRefreshWagePaymentSnapshot'));
      expect(refresh, contains('srvResolvePayrollReadiness('));
    });

    test('25 전제조건: 확정됨 · 미이체 · READY', () {
      expect(refresh, contains('d.wageStatus !== "confirmed"'));
      expect(refresh, contains('d.wageStatus === "transferred"'));
      expect(refresh, contains('if (!pr.ready)'));
    });

    test('26 §21 — 금액·근태·시간·계산을 건드리지 않는다', () {
      for (final f in [
        'finalWage', 'netWage', 'wageDetail', 'wageStatus:',
        'checkInAt', 'checkOutAt', 'workMinutes',
      ]) {
        expect(refresh, isNot(contains(f)), reason: f);
      }
    });

    test('27 갱신하면 차단 표시와 사유를 함께 지운다', () {
      expect(_flat(refresh), contains(
          'wageAccountReviewRequired: admin.firestore.FieldValue.delete()'));
      expect(_flat(refresh), contains(
          'wageAccountReadinessReason: admin.firestore.FieldValue.delete()'));
      expect(refresh, contains('wageAccountSourceBankAccountVersion: pr.accountVersion'));
    });

    test('28 §26 — canManageWage 권한이다', () {
      expect(refresh, contains('perms.canManageWage'));
      expect(refresh, isNot(contains('canManageWorkers')));
      expect(refresh, isNot(contains('canManageTo')));
    });

    test('29 §29 — PARTIAL 을 성공으로 숨기지 않는다', () {
      expect(_flat(refresh), contains('return {success: true, refreshed, skipped}'));
      expect(refresh, contains('skipped[id] = pr.state'),
          reason: '건너뛴 이유를 그대로 돌려준다');
    });

    test('30 §27 — 준비 완료가 통장사본 열람 권한을 열지 않는다', () {
      expect(refresh, isNot(contains('getSignedUrl')));
      expect(refresh, isNot(contains('callableGetBankbookSignedUrl')));
    });
  });

  // ── SP. 세 readiness 분리 ───────────────────────────────────────
  group('SP — 세 판정을 합치지 않는다 (§4·§30)', () {
    test('31 helper 셋이 서로를 부르지 않는다', () {
      final mr = _codeOf(
          _sliceOf(rawCf, 'function srvResolveMatchingReadiness(', '\n}'));
      final onb = _codeOf(_sliceOf(rawCf,
          'function srvMissingApplicantPayoutRegistration(', '\n}'));
      final blockReason = _codeOf(
          _sliceOf(rawCf, 'function srvWageAccountBlockReason(', '\n}'));
      expect(helper, isNot(contains('srvResolveMatchingReadiness')));
      expect(helper, isNot(contains('srvMissingApplicantPayoutRegistration')));
      expect(mr, isNot(contains('srvResolvePayrollReadiness')));
      expect(onb, isNot(contains('srvResolvePayrollReadiness')));
      // §30 — 이체 guard 는 finalized 스냅샷만 본다
      expect(blockReason, contains('wageAccountSnapshotVersion'));
      expect(blockReason, isNot(contains('srvResolvePayrollReadiness')));
    });

    test('32 §15 — 지원 단계 게이트는 그대로다', () {
      final apply = _codeOf(_sliceOf(rawCf,
          'export const callableApplyToTO = onCall(', '\n);'));
      expect(apply, contains('srvMissingApplicantPayoutRegistration(userData)'));
      expect(apply, isNot(contains('srvResolvePayrollReadiness')));
    });

    test('33 §5 — legacy bankVerificationStatus 를 쓰지 않는다', () {
      expect(helper, isNot(contains('bankVerificationStatus')));
    });
  });

  // ── UI. 문구 ────────────────────────────────────────────────────
  group('UI — 하지 않은 확인을 주장하지 않는다 (§44)', () {
    test('34 새 차단 코드가 "확인 필요"로 뭉개지지 않는다', () {
      final plan = _src(_planPath);
      expect(plan, contains("stalePaymentSnapshot = 'stalePaymentSnapshot'"));
      expect(plan, contains("snapshotProvenanceUnknown = 'snapshotProvenanceUnknown'"));
      expect(plan, contains('확정 이후 계좌가 변경됨'));
    });

    test('35 §22 — 사유별로 근로자가 할 일이 다르다', () {
      final plan = _src(_planPath);
      expect(plan, contains('급여계좌를 등록해주세요.'));
      expect(plan, contains('통장사본을 등록해주세요.'));
      expect(plan, contains('등록한 계좌와 통장사본이 다릅니다. 다시 등록해주세요.'));
    });

    test('36 근로자가 지급 보류를 볼 수 있다', () {
      final s = _src(_wageScreen);
      expect(s, contains('wageAccountReviewRequired == true'));
      expect(s, contains('지급정보 확인 필요'));
      expect(s, contains('급여 금액은 그대로 확정되어 있습니다'));
      expect(s, contains('PayrollReadinessReason.workerActionOf'));
    });

    test('37 금지 표현이 없다', () {
      for (final p in [_planPath, _wageScreen]) {
        final s = _src(p);
        for (final banned in [
          '계좌 인증 완료', '은행 검증 완료', '금융기관 확인 완료', '신뢰도',
        ]) {
          expect(s, isNot(contains(banned)), reason: '$p 에 "$banned"');
        }
      }
    });

    test('38 스냅샷 provenance 필드는 클라이언트가 쓰지 않는다', () {
      final m = _src('lib/models/core/attendance_model.dart');
      final toMap = _sliceOf(m, 'Map<String, dynamic> toMap()', '\n  }');
      for (final f in [
        'wageAccountReadinessReason',
        'wageAccountSourceBankAccountVersion',
        'wageAccountSourceBankbookDocumentVersion',
        'wagePaymentReadinessSource',
      ]) {
        expect(toMap, isNot(contains("'$f'")), reason: f);
      }
      expect(m, contains("map['wageAccountReadinessReason']"));
    });
  });
}
