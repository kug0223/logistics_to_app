// [PII-DOC-R1.5.2] 지원 단계의 급여 prerequisite 분리
//
// 이 파일이 고정하는 것:
//
//   AS   callableApplyToTO 는 계좌·통장사본을 요구하지 않는다.
//   AK   신원 축과 general integrity 는 그대로 유지된다.
//   CP   client apply eligibility == server apply eligibility.
//   XJ   Cross-Journey 계약: 지원·확정은 payment-independent, 급여만 REQUIRED.
//
// 배경: 지원 = 관심, 확정 = 약속. 지급은 근무가 끝난 뒤의 일이다.
//   R1.5가 확정에서, R1.5.1이 초대 수락에서 지급 요구를 걷어냈고,
//   이 Phase가 지원에서 걷어낸다.

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

const _bankFields = [
  'bankName',
  'accountNumber',
  'accountHolder',
  'bankbookImagePath',
  'bankbookImageUrl',
];

void main() {
  final rawCf = _src(_cfPath);
  final apply =
      _codeOf(_sliceOf(rawCf, 'export const callableApplyToTO = onCall(', '\n);'));
  final gateSrc = _src(_gatePath);
  final posting = _src(_postingPath);

  // ── AS. 서버가 지원 단계에서 지급을 묻지 않는다 ──────────────────
  group('AS — callableApplyToTO 에 payment prerequisite 없음', () {
    test('01 A2 — 계좌 3필드를 읽지 않는다', () {
      for (final f in ['bankName', 'accountNumber', 'accountHolder']) {
        expect(apply, isNot(contains('userData["$f"]')), reason: f);
      }
      expect(apply, isNot(contains('통장 정보 등록이 필요합니다')));
    });

    test('02 A2 — 통장사본을 읽지 않는다', () {
      for (final f in ['bankbookImagePath', 'bankbookImageUrl']) {
        expect(apply, isNot(contains('userData["$f"]')), reason: f);
      }
      expect(apply, isNot(contains('통장사본 등록이 필요합니다')));
    });

    test('03 A4 — 계좌 판정 상태도 읽지 않는다', () {
      // MISMATCH·OCR_UNCERTAIN·correction 진행 중이어도 지원 자체는 가능하다.
      for (final f in [
        'bankbookMatchStatus', 'bankbookDocumentState', 'bankVerificationStatus',
        'bankDecision', 'srvResolveBankbookMatch', 'bankAccountVersion',
        'documentCorrectionRequests',
      ]) {
        expect(apply, isNot(contains(f)), reason: f);
      }
    });

    test('04 §7 — Application 에 계좌 snapshot 을 쓰지 않는다', () {
      // Application = 관심 당시 근무조건 snapshot 이지 payment profile 이 아니다.
      for (final f in [..._bankFields, 'wageAccount']) {
        expect(apply, isNot(contains(f)), reason: '$f 를 지원서에 박지 않는다');
      }
    });

    test('05 급여계좌 snapshot 의 canonical writer 는 그대로다', () {
      final wage = _flat(_codeOf(_sliceOf(rawCf,
          'export const callableConfirmFinalWage = onCall(',
          'export const callableCancelFinalConfirmation')));
      expect(wage, contains('wageAccountBankName'));
      expect(wage, contains('wageAccountSnapshotVersion'));
    });
  });

  // ── AK. 남겨 둔 것 ──────────────────────────────────────────────
  group('AK — 신원·무결성 prerequisite 는 유지된다', () {
    test('06 A5 — 신분 축은 그대로다 (§4: 이번에 판단하지 않는다)', () {
      expect(apply, contains('userData["idCardImagePath"]'));
      expect(apply, contains('신분증 등록이 필요합니다'));
      expect(apply, contains('srvIsForeignIdentity(userData)'));
      expect(apply, contains('userData["passVerifiedAt"]'));
      expect(apply, contains('slotId && userData["isIdVerified"] !== true'));
    });

    test('07 A6 — 계정 상태·블랙리스트·제재는 그대로다', () {
      expect(apply, contains('userData["isBlacklisted"] === true'));
      expect(apply, contains('userData["accountStatus"] !== "active"'));
      expect(apply, contains('restrictedUntil'));
    });

    test('08 A7 — 공고 상태·마감·정원·겹침은 그대로다', () {
      for (final m in [
        '마감된 공고입니다',
        '지원 마감된 공고입니다',
        '모집 인원이 마감되었습니다',
        '확정된 근무가 있어 지원할 수 없습니다',
        '관리자로 등록된 사업장의 공고에는 지원할 수 없습니다',
      ]) {
        expect(apply, contains(m), reason: m);
      }
    });

    test('09 동의는 그대로 요구한다', () {
      expect(apply, contains('소득신고 목적 신분증 열람에 동의해야 지원할 수 있습니다'));
      expect(apply, contains('resolveDocumentAccessConsentVersion'));
    });
  });

  // ── CP. 앱과 서버가 같은 답을 한다 ───────────────────────────────
  group('CP — client / server apply eligibility parity', () {
    final gate = _codeOf(
        _sliceOf(gateSrc, 'bool meetsApplyPrerequisites(', '\n}'));

    test('10 canonical 게이트가 계좌를 묻지 않는다', () {
      for (final f in ['hasBankAccount', 'hasBankbookDocument',
        'bankName', 'accountNumber', 'bankbookImage']) {
        expect(gate, isNot(contains(f)), reason: f);
      }
    });

    test('11 canonical 게이트의 신원 조건은 서버와 같다', () {
      expect(gate, contains('user.isBlacklisted'));
      expect(gate, contains('user.isRestricted'));
      expect(gate, contains('!user.isForeign && !user.isPassVerified'));
      expect(gate, contains('user.hasIdDocument'));
      expect(gate, contains('isFlexType && !user.isIdVerified'));
    });

    test('12 전제조건 화면이 계좌로 버튼을 잠그지 않는다', () {
      final state = _codeOf(_sliceOf(gateSrc,
          'class _ApplyPrerequisitesScreenState', 'bool meetsApplyPrerequisites('));
      for (final f in ['_accountReady', '_bankbookReady',
        'hasBankAccount', 'hasBankbookDocument']) {
        expect(state, isNot(contains(f)), reason: f);
      }
      expect(state, isNot(contains('계좌 정보 등록이 필요합니다')));
      expect(state, isNot(contains('통장사본 등록이 필요합니다')));
    });

    test('13 공고 상세의 차단 사유에서 계좌가 빠졌다', () {
      final block = _codeOf(
          _sliceOf(posting, 'void _checkApplyEligibility()', '\n  }'));
      expect(block, isNot(contains('통장 정보 등록이 필요합니다')));
      expect(block, isNot(contains('통장사본 등록이 필요합니다')));
      expect(block, isNot(contains('hasBankbookDocument')));
      expect(block, isNot(contains('user.bankName')));
      // 신원 사유는 남는다
      expect(block, contains('신분증 등록이 필요합니다'));
    });

    test('14 지원 준비 시트가 급여정보를 지원 조건으로 말하지 않는다', () {
      final sheet = _codeOf(_sliceOf(posting,
          'void _showDocumentReadinessSheet(', '\n  }'));
      expect(sheet, isNot(contains("'급여정보'")));
      expect(sheet, isNot(contains('hasWage')));
      expect(sheet, contains("'신분 확인'"));
    });

    test('15 지원 제출 경로 어디에도 계좌 차단이 남지 않았다', () {
      // callableApplyToTO 로 수렴하는 세 제출 지점 + 그 위의 래퍼.
      for (final p in [
        'lib/services/firestore/application_firestore.dart',
        'lib/widgets/dialogs/apply/apply_work_dialog.dart',
        'lib/widgets/dialogs/apply/multi_apply_confirm_sheet.dart',
        'lib/widgets/dialogs/apply/longterm_apply_sheet.dart',
      ]) {
        final s = _codeOf(_src(p));
        for (final f in ['hasBankAccount', 'hasBankbookDocument',
          '통장 정보 등록이 필요합니다', '통장사본 등록이 필요합니다']) {
          expect(s, isNot(contains(f)), reason: '$p 에 $f');
        }
      }
    });

    test('16 초대 수락도 같은 게이트를 쓰므로 함께 열린다', () {
      // R1.5.1 은 서버만 열었고, 이 게이트가 앱에서 막고 있었다.
      for (final p in [
        'lib/screens/user/my_applications_screen.dart',
        'lib/screens/common/job_posting_screen.dart',
      ]) {
        expect(_src(p), contains('meetsApplyPrerequisites('),
            reason: '$p 는 canonical 게이트를 통해 수락한다');
      }
    });
  });

  // ── XJ. Cross-Journey 계약 (§20) ────────────────────────────────
  group('XJ — 단계별 Identity / Payment 계약', () {
    test('17 지원: Identity 요구, Payment 불요', () {
      expect(apply, contains('신분증 등록이 필요합니다'));
      for (final f in _bankFields) {
        expect(apply, isNot(contains('userData["$f"]')), reason: f);
      }
    });

    test('18 확정·초대수락: Matching Readiness, Payment 불요', () {
      final confirmGate = _flat(_codeOf(
          _sliceOf(rawCf, 'const confirmReviewGate =', '};')));
      final accept = _codeOf(_sliceOf(rawCf,
          'export const callableAcceptTOInvitation = onCall(', '\n);'));
      expect(confirmGate, contains('srvResolveMatchingReadiness('));
      expect(accept, contains('srvResolveMatchingReadiness('));
      for (final f in _bankFields) {
        expect(accept, isNot(contains('freshUserData.$f')), reason: f);
      }
    });

    test('19 급여: Payment 요구 — 이번 Phase 에서 바뀌지 않았다', () {
      final xfer = _codeOf(
          _sliceOf(rawCf, 'function srvWageAccountBlockReason(', '\n}'));
      expect(xfer, contains('wageAccountBankName'));
      expect(xfer, contains('wageAccountNumberEncrypted'));
      expect(xfer, contains('wageAccountHolder'));
      expect(xfer, contains('wageAccountSnapshotAt'));
    });

    test('20 급여 CF 는 지원 게이트를 빌려 쓰지 않는다', () {
      final wage = _flat(_codeOf(_sliceOf(rawCf,
          'export const callableConfirmFinalWage = onCall(',
          'export const callableCancelFinalConfirmation')));
      expect(wage, contains('srvResolveReviewReadiness('));
      expect(wage, isNot(contains('meetsApplyPrerequisites')));
    });
  });

  // ── §16 경계 기록 ────────────────────────────────────────────────
  group('경계 — 이번 Phase 가 건드리지 않은 곳', () {
    test('21 재배치 수락도 R1.5.3 에서 함께 열렸다', () {
      // R1.5.2 시점에는 [FOLLOWUP-REASSIGNMENT-PAYROLL-PREREQUISITE] 로
      // 남겨 두고 사실만 고정했다. R1.5.3 이 같은 논리로 닫았다.
      // 상세 계약은 test/gate_parity_residual_contract_test.dart.
      final re = _codeOf(_sliceOf(rawCf,
          'export const callableAcceptConfirmedReassignment = onCall(', '\n);'));
      expect(re, isNot(contains('통장 정보 등록이 필요합니다')));
      expect(re, isNot(contains('통장사본 등록이 필요합니다')));
    });

    test('22 신분증 지원 prerequisite 는 그대로다 (§4)', () {
      expect(apply, contains('신분증 등록이 필요합니다'));
      expect(_codeOf(_sliceOf(gateSrc, 'bool meetsApplyPrerequisites(', '\n}')),
          contains('user.hasIdDocument'));
    });
  });
}
