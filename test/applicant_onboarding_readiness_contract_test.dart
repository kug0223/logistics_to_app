// [PII-DOC-R1.5.4] APPLICANT ONBOARDING READINESS
//
// 이 파일이 고정하는 것:
//
//   ON   지원 전에 급여계좌·통장사본이 **등록**돼 있어야 한다.
//   NR   등록이지 검수가 아니다 — 관리자 승인은 지원 조건이 아니다.
//   IV   초대 수락도 같은 contract 를 지난다 (우회로 없음).
//   CP   client 와 server 의 지원 자격 판정이 같다.
//   KP   R1.5.3 에서 고친 것들은 되돌리지 않는다.
//   JN   세 readiness 는 서로 다른 질문이고 합치지 않는다.
//
// 이 파일은 test/apply_payroll_separation_contract_test.dart 를 대체한다.
//   그 파일은 "지원 = 관심이므로 payment 불필요"라는 R1.5.2 의 전제를
//   고정하고 있었고, 그 전제가 제품정책 오류로 철회됐다.

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
const _gatePath = 'lib/screens/user/apply_prerequisites_screen.dart';
const _postingPath = 'lib/screens/common/job_posting_screen.dart';
const _homePath = 'lib/screens/user/user_home_screen.dart';

void main() {
  final rawCf = _src(_cfPath);
  final apply =
      _codeOf(_sliceOf(rawCf, 'export const callableApplyToTO = onCall(', '\n);'));
  final accept = _codeOf(_sliceOf(rawCf,
      'export const callableAcceptTOInvitation = onCall(', '\n);'));
  final helper = _codeOf(_sliceOf(rawCf,
      'function srvMissingApplicantPayoutRegistration(', '\n}'));
  final gateSrc = _src(_gatePath);
  final posting = _src(_postingPath);

  // ── ON. 서버 onboarding gate ────────────────────────────────────
  group('ON — 지원 전 급여계좌·통장사본 등록 필수', () {
    test('01 O2 — 계좌 3필드가 없으면 지원 불가', () {
      expect(helper, contains('d["bankName"]'));
      expect(helper, contains('d["accountNumber"]'));
      expect(helper, contains('d["accountHolder"]'));
      expect(helper, contains('ONB_MISSING_BANK_ACCOUNT'));
    });

    test('02 O3 — 통장사본이 없으면 지원 불가 (path 또는 url)', () {
      expect(helper, contains('d["bankbookImagePath"]'));
      expect(helper, contains('d["bankbookImageUrl"]'));
      expect(helper, contains('ONB_MISSING_BANKBOOK'));
    });

    test('03 callableApplyToTO 가 이 판정을 쓰고 거부한다', () {
      expect(apply, contains('srvMissingApplicantPayoutRegistration(userData)'));
      expect(_flat(apply), contains(
          'if (applyOnbMissing) { throw new HttpsError( "failed-precondition", '
          'srvPayoutRegistrationMessage(applyOnbMissing)); }'));
    });

    test('04 문구는 무엇을 등록해야 하는지 말한다', () {
      final msg = _codeOf(
          _sliceOf(rawCf, 'function srvPayoutRegistrationMessage(', '\n}'));
      expect(msg, contains('통장사본 등록이 필요합니다'));
      expect(msg, contains('통장 정보 등록이 필요합니다'));
    });

    test('05 계좌 presence 를 판정하는 곳은 한 군데다', () {
      // 같은 질문을 두 곳에서 다르게 답하지 않는다.
      final owners = <String>[];
      final lines = _codeOf(rawCf).split('\n');
      var cur = '<top>';
      for (final l in lines) {
        final m = RegExp(r'^(?:export const|async function|function) (\w+)')
            .firstMatch(l);
        if (m != null) cur = m.group(1)!;
        if (RegExp(r'^\s*if\s*\(').hasMatch(l) &&
            RegExp(r'\b(bankName|accountNumber|accountHolder|bankbookImagePath|bankbookImageUrl)\b')
                .hasMatch(l)) {
          owners.add(cur);
        }
      }
      expect(
          owners.toSet(),
          equals({
            'srvMissingApplicantPayoutRegistration', // onboarding 판정
            'callableUpdateBankAccount', // 계좌 등록 자체의 입력 검증
          }),
          reason: '실제 발견: ${owners.toSet()}');
    });
  });

  // ── NR. 등록 ≠ 검수 ────────────────────────────────────────────
  group('NR — 등록이지 관리자 검수가 아니다', () {
    test('06 판정이 사람 검토 상태를 읽지 않는다', () {
      for (final f in [
        'businessApplicantDocumentReviews', 'bankDecision', 'REVIEWED_OK',
        'reviewedBankbookDocumentVersion', 'reviewedBankAccountVersion',
      ]) {
        expect(helper, isNot(contains(f)), reason: f);
      }
    });

    test('07 §5 — canonical match state 를 새 지원 조건으로 쓰지 않는다', () {
      // MISMATCH / OCR_UNCERTAIN 으로 지원을 막는 것은 별도 정책 판단이다.
      for (final f in [
        'bankbookMatchStatus', 'srvResolveBankbookMatch', 'DOC_MATCH_MATCHED',
        'bankbookDocumentState', 'documentCorrectionRequests',
      ]) {
        expect(helper, isNot(contains(f)), reason: f);
      }
      expect(apply, isNot(contains('bankbookMatchStatus')));
      expect(accept, isNot(contains('bankbookMatchStatus')));
    });

    test('08 §11 — writer 없는 bankVerificationStatus 를 되살리지 않는다', () {
      expect(helper, isNot(contains('bankVerificationStatus')));
      expect(apply, isNot(contains('bankVerificationStatus')));
      expect(_codeOf(_src(_homePath)), isNot(contains('bankVerificationStatus')));
      final writes = _codeOf(rawCf)
          .split('\n')
          .where((l) => l.contains('bankVerificationStatus:'))
          .where((l) => !l.contains('FieldValue.delete'))
          .toList();
      expect(writes, isEmpty);
    });

    test('09 §12 — 금융 검증을 주장하는 표현이 없다', () {
      for (final p in [_postingPath, _gatePath, _homePath,
        'lib/screens/common/document_management_screen.dart']) {
        final s = _src(p);
        for (final banned in [
          '계좌 인증 완료', '금융기관 확인 완료', '본인 명의 인증 완료', '신뢰도',
        ]) {
          expect(s, isNot(contains(banned)), reason: '$p 에 "$banned"');
        }
      }
    });
  });

  // ── IV. 초대 수락 ───────────────────────────────────────────────
  group('IV — 초대 수락도 onboarding contract 를 지난다', () {
    test('10 I2·I3 — 같은 helper 를 쓴다', () {
      expect(accept,
          contains('srvMissingApplicantPayoutRegistration(freshUserData)'));
      expect(_flat(accept), contains('if (acceptOnbMissing) {'));
    });

    test('11 좌석을 잡기 전에 본다 — 실패 시 변화 0', () {
      final onb = accept.indexOf('srvMissingApplicantPayoutRegistration(');
      final seat =
          accept.indexOf('totalConfirmed: admin.firestore.FieldValue.increment(1)');
      expect(onb, greaterThan(-1));
      expect(seat, greaterThan(-1));
      expect(onb < seat, true, reason: 'INVITED·좌석·카운터가 그대로여야 한다');
    });

    test('12 §13 — Matching Readiness 와 섞지 않는다', () {
      // 확정 판정은 여전히 신분만 본다.
      final mr = _codeOf(
          _sliceOf(rawCf, 'function srvResolveMatchingReadiness(', '\n}'));
      for (final f in ['bankName', 'bankbook', 'srvMissingApplicantPayoutRegistration']) {
        expect(mr, isNot(contains(f)), reason: f);
      }
      expect(accept, contains('srvResolveMatchingReadiness('));
    });

    test('13 §15 — 직접 확정에는 중복 payment gate 를 넣지 않았다', () {
      final gate = _flat(_codeOf(
          _sliceOf(rawCf, 'const confirmReviewGate =', '};')));
      expect(gate, contains('srvResolveMatchingReadiness('));
      expect(gate, isNot(contains('srvMissingApplicantPayoutRegistration')));
    });
  });

  // ── CP. client / server parity ──────────────────────────────────
  group('CP — 앱과 서버가 같은 답을 한다', () {
    final gate = _codeOf(
        _sliceOf(gateSrc, 'bool meetsApplyPrerequisites(', '\n}'));
    final blockReason =
        _codeOf(_sliceOf(posting, 'void _checkApplyEligibility()', '\n  }'));

    test('14 canonical 게이트가 계좌·통장사본을 요구한다', () {
      expect(gate, contains('!user.hasBankAccount'));
      expect(gate, contains('!user.hasBankbookDocument'));
    });

    test('15 공고 상세 차단 사유도 같다', () {
      expect(blockReason, contains('!user.hasBankAccount'));
      expect(blockReason, contains('통장 정보 등록이 필요합니다'));
      expect(blockReason, contains('!user.hasBankbookDocument'));
      expect(blockReason, contains('통장사본 등록이 필요합니다'));
    });

    test('16 계좌 판정은 3필드 getter 하나로 통일됐다', () {
      // 예전에는 여기서 accountHolder 를 빼고 봐서, 예금주명만 비었을 때
      // 버튼이 정상으로 보이고 탭한 뒤에야 막혔다.
      expect(blockReason, isNot(contains('user.bankName == null')));
      final model = _src('lib/models/core/user_model.dart');
      expect(_flat(model), contains('bool get hasBankAccount'));
      expect(_flat(_sliceOf(model, 'bool get hasBankAccount', ';')),
          contains('accountHolder'));
    });

    test('17 전제조건 화면이 두 항목을 다시 보여주고 잠근다', () {
      final state = _codeOf(_sliceOf(gateSrc,
          'class _ApplyPrerequisitesScreenState', 'bool meetsApplyPrerequisites('));
      expect(state, contains('_accountReady'));
      expect(state, contains('_bankbookReady'));
      expect(state, contains("'계좌 정보 등록'"));
      expect(state, contains("'통장사본 등록'"));
    });

    test('18 §18 — 지원 제출 경로는 모두 canonical 게이트를 지난다', () {
      for (final p in [
        'lib/screens/common/job_posting_screen.dart',
        'lib/widgets/dialogs/apply/apply_work_dialog.dart',
        'lib/screens/user/my_applications_screen.dart',
      ]) {
        expect(_src(p), contains('meetsApplyPrerequisites('), reason: p);
      }
    });

    test('19 지원 준비 시트가 급여정보를 다시 말한다', () {
      final sheet = _codeOf(_sliceOf(posting,
          'void _showDocumentReadinessSheet(', '\n  }'));
      expect(sheet, contains("'급여정보'"));
      expect(sheet, contains('user.hasBankAccount && user.hasBankbookDocument'));
    });
  });

  // ── KP. R1.5.3 유지 ─────────────────────────────────────────────
  group('KP — R1.5.3 에서 고친 것은 되돌리지 않는다', () {
    test('20 §8 — 외국인 PASS parity 유지', () {
      expect(apply, contains('!isForeignApplicant && !userData["passVerifiedAt"]'));
      expect(_codeOf(_sliceOf(posting, 'void _checkApplyEligibility()', '\n  }')),
          contains('!user.isForeign && !user.isPassVerified'));
      expect(_codeOf(_sliceOf(gateSrc, 'bool meetsApplyPrerequisites(', '\n}')),
          contains('!user.isForeign && !user.isPassVerified'));
    });

    test('21 §16·§22 — 재배치 수락은 payment-independent 로 남는다', () {
      final re = _codeOf(_sliceOf(rawCf,
          'export const callableAcceptConfirmedReassignment = onCall(', '\n);'));
      expect(re, isNot(contains('통장 정보 등록이 필요합니다')));
      expect(re, isNot(contains('통장사본 등록이 필요합니다')));
      expect(re, isNot(contains('srvMissingApplicantPayoutRegistration')));
      // 신원 문턱은 그대로
      expect(re, contains('u.isIdVerified !== true'));
    });

    test('22 §12 — 서류관리의 legacy "확인 완료" 배지를 되살리지 않았다', () {
      final docs = _codeOf(_sliceOf(
          _src('lib/screens/common/document_management_screen.dart'),
          'Widget _buildUserDocuments(', '\n  }'));
      expect(docs, isNot(contains('bankVerificationStatus')));
      expect(docs, isNot(contains('isError:')));
    });
  });

  // ── JN. 세 readiness 분리 (§2) ──────────────────────────────────
  group('JN — 세 readiness 는 서로 다른 질문이다', () {
    test('23 helper 세 개가 각각 존재하고 서로를 부르지 않는다', () {
      final onb = helper;
      final mr = _codeOf(
          _sliceOf(rawCf, 'function srvResolveMatchingReadiness(', '\n}'));
      final xfer = _codeOf(
          _sliceOf(rawCf, 'function srvWageAccountBlockReason(', '\n}'));
      expect(onb, isNot(contains('srvResolveMatchingReadiness')));
      expect(mr, isNot(contains('srvMissingApplicantPayoutRegistration')));
      expect(xfer, isNot(contains('srvMissingApplicantPayoutRegistration')));
      expect(xfer, isNot(contains('srvResolveMatchingReadiness')));
    });

    test('24 §17 — 급여 동작은 이번에 바뀌지 않았다', () {
      final xfer = _codeOf(
          _sliceOf(rawCf, 'function srvWageAccountBlockReason(', '\n}'));
      for (final f in ['wageAccountBankName', 'wageAccountNumberEncrypted',
        'wageAccountHolder', 'wageAccountSnapshotAt']) {
        expect(xfer, contains(f), reason: f);
      }
      final wage = _flat(_codeOf(_sliceOf(rawCf,
          'export const callableConfirmFinalWage = onCall(',
          'export const callableCancelFinalConfirmation')));
      expect(wage, contains('srvResolveReviewReadiness('));
      expect(wage, isNot(contains('srvMissingApplicantPayoutRegistration')));
    });

    test('25 onboarding 통과가 payroll ready 를 뜻하지 않는다', () {
      // 지원 시점 등록 여부와 지급 시점 snapshot 완전성은 다른 필드를 본다.
      expect(helper, isNot(contains('wageAccount')));
    });
  });

  // ── §23 Home ────────────────────────────────────────────────────
  group('HM — Home onboarding truth', () {
    final card = _sliceOf(_src(_homePath), 'Widget _buildReadinessCard(', '\n  }');

    test('26 신분증 + 급여정보 두 축을 본다', () {
      expect(_codeOf(card), contains('user.hasIdDocument'));
      expect(_codeOf(card),
          contains('user.hasBankAccount && user.hasBankbookDocument'));
      expect(_codeOf(card), contains('completed == 2'));
    });

    test('27 §10 — 하나만 하면 끝나는 것처럼 말하지 않는다', () {
      expect(card, contains('지원 전에 신분증과 급여정보를 등록해주세요'));
      expect(card, contains('계좌와 통장사본을 등록하면 지원 준비가 완료돼요'));
      expect(card, contains('신분증을 등록하면 지원 준비가 완료돼요'));
    });

    test('28 등록 여부만 본다 — 검수 상태는 읽지 않는다', () {
      for (final f in ['bankVerificationStatus', 'bankDecision',
        'bankbookMatchStatus', 'hasWageDocumentsReady']) {
        expect(_codeOf(card), isNot(contains(f)), reason: f);
      }
    });
  });
}
