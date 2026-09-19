// [PII-DOC-R1.5.3] 지원·재배치 게이트 parity 잔여분
//
// 이 파일이 고정하는 것:
//
//   RA   confirmed reassignment 수락에 payment prerequisite 없음.
//   FP   외국인 지원 — client 와 server 가 같은 PASS 규칙을 쓴다.
//   HM   Home 이 급여계좌를 "지원 준비"로 말하지 않는다.
//   DZ   아무도 쓰지 않는 bankVerificationStatus 로 할 일을 만들지 않는다.
//   JN   단계별 Identity / Payment journey 계약.

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
const _homePath = 'lib/screens/user/user_home_screen.dart';
const _postingPath = 'lib/screens/common/job_posting_screen.dart';
const _gatePath = 'lib/screens/user/apply_prerequisites_screen.dart';

const _payFields = [
  'bankName',
  'accountNumber',
  'accountHolder',
  'bankbookImagePath',
  'bankbookImageUrl',
  'isBankbookVerified',
  'bankVerificationStatus',
];

void main() {
  final rawCf = _src(_cfPath);
  final reassign = _codeOf(_sliceOf(rawCf,
      'export const callableAcceptConfirmedReassignment = onCall(', '\n);'));
  final apply =
      _codeOf(_sliceOf(rawCf, 'export const callableApplyToTO = onCall(', '\n);'));
  final home = _src(_homePath);
  final posting = _src(_postingPath);

  // ── RA. 재배치 수락 ──────────────────────────────────────────────
  group('RA — confirmed reassignment 수락에 payment prerequisite 없음', () {
    test('01 R2 — 계좌·통장 요구가 사라졌다', () {
      for (final f in _payFields) {
        expect(reassign, isNot(contains(RegExp('u\\.$f\\b'))), reason: f);
      }
      expect(reassign, isNot(contains('통장 정보 등록이 필요합니다')));
      expect(reassign, isNot(contains('통장사본 등록이 필요합니다')));
    });

    test('02 R3 — 계좌 판정·correction 상태도 읽지 않는다', () {
      for (final f in [
        'bankbookMatchStatus', 'bankbookDocumentState', 'bankDecision',
        'srvResolveBankbookMatch', 'bankAccountVersion', 'wageAccount',
      ]) {
        expect(reassign, isNot(contains(f)), reason: f);
      }
    });

    test('03 R1 — 신원 문턱은 그대로다', () {
      expect(reassign, contains('srvIsForeignIdentity(u)'));
      expect(reassign, contains('u.passVerifiedAt'));
      expect(reassign, contains('u.isIdVerified !== true'));
      expect(reassign, contains('u.accountStatus'));
      expect(reassign, contains('u.isBlacklisted'));
      expect(reassign, contains('u.restrictedUntil'));
    });

    test('04 R4 — proposal·좌석·정원·겹침 guard 는 그대로다', () {
      for (final m in [
        'CR_SUPERSEDED',
        'crDocConsent',
        '근로계약서가 발행되어 기존 근무가 유지됩니다',
      ]) {
        expect(reassign, contains(m), reason: m);
      }
    });

    test('05 §12 — 좌석 이동 mutation 은 재설계하지 않았다', () {
      // source 해제 + target 확정이 한 트랜잭션에 남아 있다.
      expect(reassign, contains('db.runTransaction'));
      expect(_flat(reassign), contains('FieldValue.increment('));
    });
  });

  // ── FP. 외국인 지원 parity ───────────────────────────────────────
  group('FP — 외국인 지원의 client / server PASS 규칙이 같다', () {
    final blockReason =
        _codeOf(_sliceOf(posting, 'void _checkApplyEligibility()', '\n  }'));
    final gate = _codeOf(
        _sliceOf(_src(_gatePath), 'bool meetsApplyPrerequisites(', '\n}'));

    test('06 F1 — server 는 외국인에게 PASS 를 요구하지 않는다', () {
      expect(apply, contains('!isForeignApplicant && !userData["passVerifiedAt"]'));
    });

    test('07 F1 — 공고 상세 차단 사유도 외국인을 면제한다', () {
      expect(blockReason, contains('!user.isForeign && !user.isPassVerified'));
      // 국적 무관 일괄 차단이 남아 있으면 안 된다.
      expect(blockReason, isNot(contains(RegExp(r'else if \(!user\.isPassVerified\)'))));
    });

    test('08 F1 — canonical 게이트도 같은 조건이다', () {
      expect(gate, contains('!user.isForeign && !user.isPassVerified'));
    });

    test('09 F2·F3 — 내국인 PASS 요구는 세 곳 모두 유지', () {
      expect(apply, contains('본인인증 후 지원할 수 있습니다'));
      expect(blockReason, contains('본인인증이 필요합니다'));
      expect(gate, contains('isPassVerified'));
    });

    test('10 isForeign 은 신원 증거에서 파생된다 — dead field 재도입 금지', () {
      final model = _src('lib/models/core/user_model.dart');
      expect(model,
          contains('bool get isForeign => foreignIdentityFingerprint != null'));
      expect(model, isNot(contains("map['isForeign']")));
      expect(model, isNot(contains('"isForeign"')));
    });
  });

  // ── HM. Home ────────────────────────────────────────────────────
  group('HM — Home 이 급여계좌를 지원 조건으로 말하지 않는다', () {
    final card = _sliceOf(home, 'Widget _buildReadinessCard(', '\n  }');

    test('11 H1 — 옛 문구가 사라졌다', () {
      expect(home, isNot(contains('급여계좌를 등록하면 지원 준비가 완료돼요')));
      expect(home, isNot(contains('신분증과 급여계좌를 등록해주세요')));
      expect(home, isNot(contains('급여계좌 정보를 다시 확인해주세요')));
    });

    test('12 H3 — 지원 준비 카드가 검수 상태를 읽지 않는다', () {
      // [PII-DOC-R1.5.4] 원래는 "급여정보를 읽지 않는다"였다. 급여정보
      //   등록은 실제 지원 조건으로 복구됐으므로 카드가 읽는 것이 맞다.
      //   이 테스트가 지키는 것은 **검수 상태로 할 일을 만들지 않는다**이다.
      for (final f in [
        'hasWageDocumentsReady', 'bankVerificationStatus', 'bankDecision',
        'bankbookMatchStatus',
      ]) {
        expect(_codeOf(card), isNot(contains(f)), reason: f);
      }
    });

    test('13 지원 전에 실제로 필요한 것만 남았다', () {
      expect(_codeOf(card), contains('user.hasIdDocument'));
      expect(_codeOf(card),
          contains('user.hasBankAccount && user.hasBankbookDocument'));
    });
  });

  // ── DZ. dead field ──────────────────────────────────────────────
  group('DZ — 아무도 쓰지 않는 상태로 할 일을 만들지 않는다', () {
    test('14 H2 — Home 에 bankVerificationStatus reader 가 없다', () {
      expect(_codeOf(home), isNot(contains('bankVerificationStatus')));
    });

    test('15 서버에 bankVerificationStatus writer 가 없다', () {
      // 남은 것은 legacy 정리용 delete 뿐이다.
      final writes = _codeOf(rawCf)
          .split('\n')
          .where((l) => l.contains('bankVerificationStatus:'))
          .where((l) => !l.contains('FieldValue.delete'))
          .toList();
      expect(writes, isEmpty,
          reason: 'delete 외의 쓰기가 생기면 이 필드는 다시 살아난 것이다');
    });

    test('16 서류관리 화면이 그 값으로 오류 배지를 띄우지 않는다', () {
      final docs = _codeOf(_sliceOf(
          _src('lib/screens/common/document_management_screen.dart'),
          'Widget _buildUserDocuments(', '\n  }'));
      expect(docs, isNot(contains('bankVerificationStatus')));
      expect(docs, isNot(contains('isError:')));
      // 급여정보는 "근무 후 지급"을 위한 것으로 설명한다
      expect(docs, contains('근무 후 급여 지급을 위해 필요해요'));
    });
  });

  // ── JN. 단계별 journey 계약 ─────────────────────────────────────
  //
  // [PII-DOC-R1.5.4] 17·18 은 원래 "지원·확정도 payment-independent"를
  //   고정했다. 그 전제가 철회되어 지원·초대 수락은 onboarding 등록을
  //   요구하는 쪽으로 돌아갔다. 상세 계약은
  //   test/applicant_onboarding_readiness_contract_test.dart.
  //   이 group 에 남는 것은 **재배치는 여전히 payment-independent**라는
  //   R1.5.3 의 결론과 급여 경계다.
  group('JN — 재배치는 payment-independent, 급여만 payment 요구', () {
    test('17 지원 = onboarding 등록 필요', () {
      expect(apply, contains('srvMissingApplicantPayoutRegistration(userData)'));
    });

    test('18 초대 수락 = 같은 onboarding contract + Matching Readiness', () {
      final accept = _codeOf(_sliceOf(rawCf,
          'export const callableAcceptTOInvitation = onCall(', '\n);'));
      expect(accept, contains('srvResolveMatchingReadiness('));
      expect(accept,
          contains('srvMissingApplicantPayoutRegistration(freshUserData)'));
    });

    test('19 재배치 = 기존 약속 변경 — payment 불필요', () {
      for (final f in _payFields) {
        expect(reassign, isNot(contains(RegExp('u\\.$f\\b'))), reason: f);
      }
    });

    test('20 급여 = 지급 준비 — payment 필요 (변화 없음)', () {
      final xfer = _codeOf(
          _sliceOf(rawCf, 'function srvWageAccountBlockReason(', '\n}'));
      for (final f in ['wageAccountBankName', 'wageAccountNumberEncrypted',
        'wageAccountHolder', 'wageAccountSnapshotAt']) {
        expect(xfer, contains(f), reason: f);
      }
      final wage = _flat(_codeOf(_sliceOf(rawCf,
          'export const callableConfirmFinalWage = onCall(',
          'export const callableCancelFinalConfirmation')));
      // [PII-DOC-R1.6] 급여가 쓰는 판정이 Payroll Readiness로 바뀌었다.
      expect(wage, contains('srvResolvePayrollReadiness('));
    });

    test('21 계좌 presence 판정처가 늘어나지 않았다', () {
      // [PII-DOC-R1.5.4] onboarding 판정 helper 하나가 추가됐다.
      //   지원·초대 수락은 그 helper 를 부를 뿐 직접 필드를 보지 않는다.
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
            'srvMissingApplicantPayoutRegistration',
            // [PII-DOC-R1.6] 지급 시점 판정이 추가됐다. 지원 판정과
            //   별개의 helper이고, 둘 다 자기 질문에만 답한다.
            'srvResolvePayrollReadiness',
            'callableUpdateBankAccount',
          }),
          reason: '실제 발견: ${owners.toSet()}');
    });
  });
}
