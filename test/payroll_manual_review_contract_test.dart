// [PII-DOC-R1.6.1A] 지급 문맥의 통장사본 수동 확인 도달성
//
// 이 파일이 고정하는 것:
//
//   RE   BANK_UNASSESSED / OCR_UNCERTAIN 에 실행 가능한 회복 경로가 있다.
//   AP   지원서(applicationId)에 의존하지 않는다.
//   PM   권한은 canManageWage 이고, 원본 접근은 목적·버전에 묶인다.
//   TR   판정은 현재 버전에만 기록된다 — 낡은 판정은 현재가 되지 않는다.
//   DE   REUPLOAD_REQUIRED 가 막다른 길이 아니다.
//   IV   자동 판정 truth·임금·과거 지급은 바뀌지 않는다.

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
const _dashPath =
    'lib/screens/business_admin/payroll/payroll_payment_dashboard_screen.dart';
const _svcPath = 'lib/services/payroll_readiness_service.dart';

void main() {
  final rawCf = _src(_cfPath);
  final review = _codeOf(_sliceOf(rawCf,
      'export const callableReviewPayrollBankDocument = onCall(', '\n);'));
  final url = _codeOf(_sliceOf(rawCf,
      'export const callableGetPayrollBankbookUrl = onCall(', '\n);'));
  final authz = _codeOf(_sliceOf(rawCf,
      'async function srvAssertPayrollDocumentAccess(', '\n}'));
  final purpose = _codeOf(_sliceOf(rawCf,
      'async function srvAssertCurrentPayrollPurpose(', '\n}'));
  final dash = _src(_dashPath);
  final svc = _src(_svcPath);

  // ── RE. 도달성 ──────────────────────────────────────────────────
  group('RE — 수동 fallback 에 실행 가능한 경로가 있다 (§1)', () {
    test('01 MR1·MR2 — 두 상태가 CTA 조건에 들어간다', () {
      final g = _codeOf(_sliceOf(svc, 'bool get needsManualReview =>', ';'));
      expect(g, contains('BANK_OCR_UNCERTAIN'));
      expect(g, contains('BANK_UNASSESSED'));
      expect(g, contains('STALE_MANUAL_REVIEW'));
    });

    test('02 화면이 그 조건으로 CTA 를 켠다', () {
      final f = _codeOf(_sliceOf(dash, 'bool _needsManualReview(', '\n  }'));
      expect(f, contains('info.needsManualReview'));
      expect(f, contains('!info.ready'));
      expect(dash, contains('onReviewBankDocument'));
      expect(_codeOf(dash), contains("'통장사본 확인'"));
    });

    test('03 CTA 가 켜지면 상태 문구는 빠진다 — 둘이 겹치지 않는다', () {
      final w = _codeOf(_sliceOf(dash, 'String? _payrollWaitLabel(', '\n  }'));
      expect(w, contains('if (_needsManualReview(recs)) return null;'));
    });

    test('04 §10 금지 문구가 없다', () {
      final code = _codeOf(dash);
      expect(code, isNot(contains("'계좌 인증'")));
      expect(code, isNot(contains("'은행 확인'")));
      for (final banned in ['계좌 인증 완료', '금융기관 확인 완료', '은행 검증 완료']) {
        expect(_src(_dashPath), isNot(contains(banned)), reason: banned);
      }
    });
  });

  // ── AP. 지원서 비의존 ───────────────────────────────────────────
  group('AP — 지원서에 의존하지 않는다 (§6)', () {
    test('05 두 CF 모두 applicationId 를 요구하지 않는다', () {
      for (final body in [review, url]) {
        expect(body, isNot(contains('applicationId')));
        expect(body, isNot(contains('srvApplicantReviewAccessBlock')));
      }
    });

    test('06 인가는 실제 급여 관계로 한다', () {
      expect(purpose, contains('collection("attendance")'));
      expect(purpose, contains('"businessId", "==", businessId'));
      expect(purpose, contains('"userId", "==", workerUid'));
      expect(review, contains('srvAssertCurrentPayrollPurpose('));
      expect(url, contains('srvAssertCurrentPayrollPurpose('));
    });

    test('07 §5 — 검토 truth 컬렉션을 새로 만들지 않았다', () {
      expect(review, contains('BIZ_DOC_REVIEW_COL'));
      expect(review, contains('srvBizReviewId(businessId, targetUid)'));
      expect(rawCf, isNot(contains('payrollBankReviews')));
    });

    test('08 §19 — 사업장 범위를 벗어나지 않는다', () {
      expect(review, contains('srvBizReviewId(businessId, targetUid)'));
      // 판정은 이 사업장 문서에만 쓰인다.
      expect(review, isNot(contains('collectionGroup')));
    });
  });

  // ── PM. 권한·목적·버전 ──────────────────────────────────────────
  group('PM — 권한과 원본 접근 (§7·§8·§9)', () {
    test('09 MR3 — canManageWage 필수', () {
      expect(authz, contains('perms.canManageWage !== true'));
      expect(authz, isNot(contains('canManageWorkers')));
      expect(authz, isNot(contains('canManageTo')));
      expect(review, contains('srvAssertPayrollDocumentAccess('));
      expect(url, contains('srvAssertPayrollDocumentAccess('));
    });

    test('10 §8 — 원본은 현재 버전일 때만 열린다', () {
      expect(url, contains('expectedBankbookVersion !== cur.bankbook'));
      expect(url, contains('srvIsOwnedStoragePath(storagePath, targetUid)'));
      expect(url, contains('60 * 60 * 1000'));
    });

    test('11 목적이 감사 로그에 남는다', () {
      expect(url, contains('bankbook_access_logs'));
      expect(url, contains('PAYROLL_REVIEW'));
      expect(url, contains('bankbookDocumentVersion'));
    });

    test('12 §9 — 화면이 평소에 원본을 들고 있지 않는다', () {
      // 목록 조회(projection)는 URL 을 돌려주지 않는다.
      final batch = _codeOf(_sliceOf(rawCf,
          'export const callableGetPayrollReadinessBatch = onCall(', '\n);'));
      expect(batch, isNot(contains('signedUrl')));
      expect(batch, isNot(contains('bankbookImagePath')));
      // 클라이언트는 버튼을 눌렀을 때만 호출한다.
      final f = _codeOf(
          _sliceOf(dash, 'Future<void> _reviewBankDocument(', '\n  }'));
      expect(f, contains('PayrollReadinessService.bankbookUrl('));
    });

    test('13 §12 — 이 판단에 신분증은 오지 않는다', () {
      for (final f in ['idCard', 'residentNumber', 'ciHash', 'foreignId']) {
        expect(url, isNot(contains(f)), reason: f);
        expect(review, isNot(contains(f)), reason: f);
      }
    });
  });

  // ── TR. 버전 ────────────────────────────────────────────────────
  group('TR — 낡은 판정은 현재가 되지 않는다 (§14·§18)', () {
    test('14 MR8 — 제출 시점에 버전을 다시 확인한다', () {
      expect(review, contains('cur.bankbook !== expectedBankbookVersion'));
      expect(review, contains('cur.account !== expectedAccountVersion'));
      expect(review, contains('db.runTransaction'));
      expect(_flat(review), contains('throw new HttpsError("aborted"'));
    });

    test('15 MR4 — 정확히 현재 버전에 bound 된다', () {
      expect(review, contains('reviewedBankbookDocumentVersion: cur.bankbook'));
      expect(review, contains('reviewedBankAccountVersion: cur.account'));
      // 그 값이 Payroll Readiness 의 manual 판정 기준과 같다.
      final pr = _codeOf(
          _sliceOf(rawCf, 'function srvResolvePayrollReadiness(', '\n}'));
      expect(pr, contains('reviewedBankbookDocumentVersion'));
      expect(pr, contains('reviewedBankAccountVersion'));
    });

    test('16 §13 — 기존 decision enum 만 쓴다', () {
      expect(review, contains('REVIEW_DECISIONS.includes(decision)'));
      expect(review, contains('REVIEW_REUPLOAD_REQUIRED'));
    });

    test('17 클라이언트도 두 버전을 함께 보낸다', () {
      final f = _codeOf(
          _sliceOf(dash, 'Future<void> _reviewBankDocument(', '\n  }'));
      expect(f, contains('expectedBankbookVersion: info.bankbookVersion'));
      expect(f, contains('expectedAccountVersion: info.accountVersion'));
      expect(f, contains("e.code == 'aborted'"));
    });
  });

  // ── DE. dead-end 방지 ───────────────────────────────────────────
  group('DE — 관리자 판정이 막다른 길이 아니다 (§15·§21)', () {
    test('18 MR6 — REUPLOAD_REQUIRED 가 근로자 할 일을 연다', () {
      expect(review, contains('decision === REVIEW_REUPLOAD_REQUIRED'));
      expect(review, contains('srvPayrollCorrectionId('));
      expect(review, contains('CORRECTION_DOMAIN_PAYROLL'));
      expect(review, contains('CORRECTION_OPEN'));
    });

    test('19 §21 — 그 전에는 자동으로 근로자 Task 를 만들지 않는다', () {
      final states = _codeOf(_sliceOf(rawCf,
          'const PAYROLL_CORRECTION_STATES = [', '];'));
      expect(states, isNot(contains('PR_BANK_UNASSESSED')));
      expect(states, isNot(contains('PR_BANK_OCR_UNCERTAIN')));
    });

    test('20 확인 완료면 열린 지급 보완 요청을 닫는다', () {
      expect(review, contains('CORRECTION_RESOLVED'));
    });

    test('21 MR9 — READY_MANUAL 이후 스냅샷 회복 경로가 있다', () {
      // 검토가 이체를 직접 열지 않는다 — 스냅샷 writer 를 거친다.
      expect(review, isNot(contains('wageStatus')));
      expect(review, isNot(contains('transferred')));
      expect(rawCf, contains('callableRefreshWagePaymentSnapshot'));
      expect(dash, contains('_refreshSnapshots('));
    });
  });

  // ── IV. 불변 ────────────────────────────────────────────────────
  group('IV — 바꾸지 않는 것 (§14·§17·§20·§28)', () {
    test('22 MR5 — 자동 판정 truth 를 덮어쓰지 않는다', () {
      for (final f in ['bankbookMatchStatus', 'bankbookMatchAssurance',
        'bankbookMatchEvidenceSource']) {
        expect(review, isNot(contains(f)), reason: f);
      }
    });

    test('23 §17 — 임금·근태를 건드리지 않는다', () {
      for (final f in ['finalWage', 'netWage', 'wageDetail', 'attendance")']) {
        expect(review, isNot(contains(f)), reason: f);
      }
    });

    test('24 §20 — 이미 이체된 건에는 CTA 를 만들지 않는다', () {
      final f = _codeOf(_sliceOf(dash, 'bool _needsManualReview(', '\n  }'));
      expect(f, contains('AttendanceModel.wageTransferred'));
    });

    test('25 §28 — R1.6.1 회복 경로가 그대로다', () {
      final states = _codeOf(_sliceOf(rawCf,
          'const PAYROLL_CORRECTION_STATES = [', '];'));
      for (final s in ['PR_MISSING_BANK_ACCOUNT', 'PR_MISSING_BANKBOOK',
        'PR_BANK_MISMATCH']) {
        expect(states, contains(s), reason: s);
      }
      final actorBlock = _codeOf(
          _sliceOf(rawCf, 'function srvPayrollActorForBlock(', '\n}'));
      expect(actorBlock, contains('PAY_ACTOR_MANAGER_REFRESH'));
      expect(dash, contains("'지급정보 갱신'"));
    });

    test('26 이체 원본은 여전히 스냅샷이다', () {
      final xfer = _codeOf(_sliceOf(rawCf,
          'export const callableMarkTransferredBatch = onCall(', '\n);'));
      expect(xfer, contains('srvWageAccountBlockReason('));
      expect(xfer, contains('srvWageSnapshotStaleReason('));
      expect(xfer, isNot(contains('u["bankName"]')));
    });
  });

  // ── PS. 목적 범위 [PII-DOC-R1.6.1B] ─────────────────────────────
  //
  //   권한은 필요조건이지 충분조건이 아니다. 과거에 하루 일하고 급여도
  //   받아 간 사람의 **현재** 통장사본을 언제든 열 수 있으면, 권한이
  //   맞아도 볼 이유가 없는 것을 본 것이다.
  group('PS — 접근에는 현재 지급 목적이 필요하다', () {
    test('27 P2·§6 — 과거 근태 존재만으로 열리지 않는다', () {
      // 목적 판정이 반드시 지급 상태를 본다.
      expect(purpose, contains('"wageStatus", "==", "confirmed"'));
      expect(purpose, contains('d.wageStatus !== "confirmed"'));
      // 옛 helper(상태 무관)는 사라졌다.
      expect(rawCf, isNot(contains('srvHasPayrollRelationship')));
    });

    test('28 §7 — 이체 완료 건은 목적이 되지 않는다', () {
      // confirmed 만 통과하므로 transferred 는 자동으로 제외된다.
      expect(purpose, isNot(contains('"transferred"')));
      expect(_flat(purpose), contains('if (d.wageStatus !== "confirmed") throw deny();'));
    });

    test('29 §8 — 화면이 보는 행과 서버가 허용하는 이유가 같다', () {
      expect(purpose, contains('attendanceId'));
      expect(purpose, contains('d.businessId !== businessId || d.userId !== workerUid'));
      final f = _codeOf(
          _sliceOf(dash, 'Future<void> _reviewBankDocument(', '\n  }'));
      expect(f, contains('attendanceId: target.id'));
      expect(f, contains('AttendanceModel.wageConfirmed'));
    });

    test('30 §14 — 열람과 판정이 같은 목적 helper 를 쓴다', () {
      expect(url, contains('srvAssertCurrentPayrollPurpose(businessId, targetUid, attendanceId)'));
      expect(review, contains('srvAssertCurrentPayrollPurpose(businessId, targetUid, attendanceId)'));
    });

    test('31 P4·§16 — 다른 사업장 건은 목적이 되지 않는다', () {
      expect(purpose, contains('d.businessId !== businessId'));
    });

    test('32 §9 — 권한을 먼저 보고 목적을 나중에 본다', () {
      for (final body in [url, review]) {
        final a = body.indexOf('srvAssertPayrollDocumentAccess(');
        final b = body.indexOf('srvAssertCurrentPayrollPurpose(');
        expect(a, greaterThan(-1));
        expect(b, greaterThan(a),
            reason: '권한 없는 호출자에게 목적 존재 여부를 알려주지 않는다');
      }
    });

    test('33 §6 — 존재 여부가 응답으로 새지 않는다', () {
      // 없는 건 · 남의 건 · 이체된 건이 모두 같은 답을 받는다.
      expect(purpose, contains('const deny = ()'));
      final denies = RegExp(r'throw deny\(\)').allMatches(purpose).length;
      expect(denies, greaterThanOrEqualTo(4));
    });

    test('34 §13 — 감사 로그가 목적 건을 남긴다', () {
      expect(url, contains('attendanceId: purposeAttId'));
      expect(url, contains('purpose: "PAYROLL_REVIEW"'));
    });

    test('35 §12 — Signed URL 은 여전히 1시간이다', () {
      expect(url, contains('60 * 60 * 1000'));
      expect(url, isNot(contains('makePublic')));
    });

    test('36 §20 — 정상 미지급 회복 경로는 막히지 않는다', () {
      // 미지급 confirmed 가 있으면 목적이 성립한다.
      expect(purpose, contains('q.docs[0].id'));
      expect(purpose, isNot(contains('isIdVerified')));
      expect(purpose, isNot(contains('applicationId')));
    });
  });
}
