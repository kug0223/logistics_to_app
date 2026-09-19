// [PII-DOC-R1.4] canonical document match state
//
// 이 파일이 고정하는 것:
//
//   INV-1  자동판정 / 사람판정 / 보완요청은 다른 축이다 — 섞지 않는다.
//   INV-2  다섯 상태의 의미와 우선순위.
//   INV-3  클라이언트는 근거만 보낸다. canonical status writer는 서버다.
//   INV-4  MATCHED가 보증 수준을 과장하지 않는다 — SERVER_VERIFIED 없음.
//   INV-5  ID는 문서 버전, 통장은 문서+계좌 **두 축**에 묶인다.
//   INV-6  이번 Phase에서 확정/급여 게이트 동작은 **변하지 않는다**.

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
const _rulesPath = 'firestore.rules';
const _matchPath = 'lib/utils/document_match.dart';
const _userModelPath = 'lib/models/core/user_model.dart';

void main() {
  final rawCf = _src(_cfPath);
  final cf = _codeOf(rawCf);
  final evaluator = _codeOf(
      _sliceOf(rawCf, 'function srvEvaluateMatchStatus(', '\n}'));
  final idResolver =
      _codeOf(_sliceOf(rawCf, 'function srvResolveIdCardMatch(', '\n}'));
  final bankResolver =
      _codeOf(_sliceOf(rawCf, 'function srvResolveBankbookMatch(', '\n}'));

  group('INV-2 — 다섯 상태와 우선순위', () {
    test('01 다섯 상태가 서버에 존재한다', () {
      for (final v in [
        'MISSING', 'UNASSESSED', 'MATCHED', 'MISMATCH', 'OCR_UNCERTAIN',
      ]) {
        expect(cf, contains('DOC_MATCH_${v == 'OCR_UNCERTAIN' ? 'OCR_UNCERTAIN' : v} = "$v"'),
            reason: '서버 상태 $v');
      }
    });

    test('02 우선순위: MISMATCH > OCR_UNCERTAIN > UNASSESSED > MATCHED', () {
      final iMismatch = evaluator.indexOf('return DOC_MATCH_MISMATCH');
      final iUncertain = evaluator.indexOf('return DOC_MATCH_OCR_UNCERTAIN');
      final iUnassessedTail = evaluator.lastIndexOf('return DOC_MATCH_UNASSESSED');
      final iMatched = evaluator.indexOf('return DOC_MATCH_MATCHED');
      expect(iMismatch, greaterThan(0));
      expect(iMismatch, lessThan(iUncertain),
          reason: '명백한 불일치를 인식 실패로 숨기지 않는다');
      expect(iUncertain, lessThan(iMatched));
      expect(iMatched, lessThan(iUnassessedTail),
          reason: '마지막 분기는 UNASSESSED — 통과로 새지 않는다');
    });

    test('03 overridden은 판정에 쓰이지 않는다', () {
      // 사용자가 경고를 넘긴 행위 기록이지 문서 사실이 아니다.
      expect(evaluator, isNot(contains('overridden')),
          reason: '여섯 번째 상태로 만들지 않는다');
    });

    test('04 통장은 이름 일치를 필수로 하지 않는다 (PD-2)', () {
      expect(evaluator, contains('opts.requireName'));
      final flat = _flat(evaluator);
      expect(flat, contains('if (opts.requireName && name === DOC_FIELD_UNREADABLE)'));
      expect(flat, contains('(!opts.requireName || name === DOC_FIELD_MATCHED)'));
      // 그러나 명백한 불일치는 이름이라도 veto한다.
      expect(flat,
          contains('name === DOC_FIELD_MISMATCH || identifier === DOC_FIELD_MISMATCH'));
    });

    test('05 신분증은 requireName: true, 통장은 false', () {
      expect(_flat(cf),
          contains('srvEvaluateMatchStatus(idDoc.evidence, {requireName: true})'));
      expect(_flat(cf),
          contains('srvEvaluateMatchStatus(bbDoc.evidence, {requireName: false})'));
    });

    test('06 MISSING은 evaluator가 아니라 resolver가 정한다', () {
      expect(evaluator, isNot(contains('DOC_MATCH_MISSING')),
          reason: '문서 존재 여부는 근거가 아니라 문서의 문제다');
      expect(idResolver, contains('return SRV_DOC_MATCH_MISSING'));
      expect(bankResolver, contains('return SRV_DOC_MATCH_MISSING'));
    });
  });

  group('INV-3 — 클라이언트는 상태를 지정할 수 없다', () {
    test('07 writer 요청 스키마에 status가 없다', () {
      for (final name in [
        'callableMarkIdCardVerified', 'callableMarkBankbookVerified',
      ]) {
        final body = _sliceOf(rawCf, 'export const $name = onCall(', '\n);');
        final d = body.substring(body.indexOf('request.data as {'),
            body.indexOf('};', body.indexOf('request.data as {')));
        expect(d.toLowerCase().contains('matchstatus'), isFalse, reason: name);
        expect(d.toLowerCase().contains('assurance'), isFalse, reason: name);
      }
    });

    test('08 rules가 canonical 필드 직접 write를 막는다', () {
      final rules = _src(_rulesPath);
      for (final f in [
        'idCardMatchStatus', 'idCardMatchEvidenceSource',
        'idCardMatchAssurance', 'idCardMatchDocumentVersion',
        'idCardMatchEvaluatedAt',
        'bankbookMatchStatus', 'bankbookMatchEvidenceSource',
        'bankbookMatchAssurance', 'bankbookMatchDocumentVersion',
        'bankbookMatchAccountVersion', 'bankbookMatchEvaluatedAt',
      ]) {
        expect(rules, contains("'$f'"), reason: '$f denylist 누락');
      }
      // 가입 시점 주입도 막는다.
      expect(rules,
          contains("request.resource.data.get('idCardMatchStatus', null) == null"));
      expect(rules,
          contains("request.resource.data.get('bankbookMatchStatus', null) == null"));
    });

    test('09 toMap에 canonical 필드가 없다', () {
      final um = _codeOf(_src(_userModelPath));
      final toMap = _sliceOf(um, 'Map<String, dynamic> toMap()', '\n  UserModel copyWith');
      for (final f in [
        'idCardMatchStatus', 'bankbookMatchStatus',
        'idCardMatchDocumentVersion', 'bankbookMatchAccountVersion',
        'idDocumentVersion', 'bankAccountVersion',
      ]) {
        expect(toMap, isNot(contains("'$f'")),
            reason: '$f 가 toMap에 실리면 rules가 정상 업데이트를 막는다');
      }
      // 읽기는 있어야 한다.
      expect(um, contains("idCardMatchStatus: map['idCardMatchStatus']"));
    });
  });

  group('INV-4 — 보증 수준을 과장하지 않는다', () {
    test('10 SERVER_VERIFIED가 어디에도 없다', () {
      expect(cf, isNot(contains('SERVER_VERIFIED')));
      expect(_codeOf(_src(_matchPath)), isNot(contains('SERVER_VERIFIED')));
    });

    test('11 현재 가능한 조합은 CLIENT_OCR / CLIENT_EVIDENCE 하나', () {
      expect(cf, contains('MATCH_SOURCE_CLIENT_OCR = "CLIENT_OCR"'));
      expect(cf, contains('MATCH_ASSURANCE_CLIENT_EVIDENCE = "CLIENT_EVIDENCE"'));
      expect(_flat(cf),
          contains('idCardMatchEvidenceSource: MATCH_SOURCE_CLIENT_OCR'));
      expect(_flat(cf),
          contains('bankbookMatchAssurance: MATCH_ASSURANCE_CLIENT_EVIDENCE'));
    });

    test('12 화면 문구가 금융/공적 인증을 주장하지 않는다', () {
      final m = _codeOf(_src(_matchPath));
      expect(m, contains("'서류 정보 일치'"));
      expect(m, contains("'급여계좌 정보 일치'"));
      for (final banned in [
        '신분증 인증 완료', '계좌 인증 완료', '금융기관 검증 완료', '본인 명의 인증 완료',
      ]) {
        expect(m, isNot(contains(banned)));
      }
    });
  });

  group('INV-5 — 버전 결속', () {
    test('13 ID는 문서 버전 하나', () {
      expect(_flat(idResolver),
          contains('const isStale = evaluatedAt !== current;'));
      expect(idResolver, contains('idCardMatchDocumentVersion'));
      expect(idResolver, contains('idDocumentVersion'));
    });

    test('14 통장은 문서 + 계좌 두 축', () {
      expect(_flat(bankResolver),
          contains('const isStale = evBb !== curBb || evAcc !== curAcc;'));
      expect(bankResolver, contains('bankbookMatchDocumentVersion'));
      expect(bankResolver, contains('bankbookMatchAccountVersion'));
      expect(bankResolver, contains('bankAccountVersion'));
    });

    test('15 generic matchedAtVersion 하나로 표현하지 않는다', () {
      // 설명 주석(JSDoc)에는 이유가 적혀 있다 — 필드로 쓰이지 않았는지 본다.
      expect(cf, isNot(contains('matchedAtVersion:')));
      expect(cf, isNot(contains('"matchedAtVersion"')));
      expect(_codeOf(_src(_matchPath)), isNot(contains('matchedAtVersion')));
    });

    test('16 낡으면 UNASSESSED — MATCHED로 읽히지 않는다', () {
      for (final r in [idResolver, bankResolver]) {
        expect(_flat(r),
            contains('status: isStale ? DOC_MATCH_UNASSESSED : stored'));
      }
    });

    test('17 writer가 버전과 판정을 같은 트랜잭션에서 쓴다', () {
      final flat = _flat(cf);
      // increment(1)은 결과값을 모른다 — 직접 계산해 한 커밋에 담는다.
      expect(flat, contains('idDocumentVersion: nextV'));
      expect(flat, contains('idCardMatchDocumentVersion: nextV'));
      expect(flat, contains('bankbookDocumentVersion: nextBb'));
      expect(flat, contains('bankbookMatchDocumentVersion: nextBb'));
      expect(flat, contains('bankbookMatchAccountVersion: curAcc'));
      expect(flat, isNot(contains(
          'idDocumentVersion: admin.firestore.FieldValue.increment(1)')));
    });

    test('18 계좌 변경·문서 삭제가 낡은 판정을 남기지 않는다', () {
      final upd = _flat(_codeOf(_sliceOf(rawCf,
          'export const callableUpdateBankAccount = onCall(', '\n);')));
      expect(upd, contains('bankbookMatchStatus: admin.firestore.FieldValue.delete()'));
      final delId = _flat(_codeOf(_sliceOf(rawCf,
          'export const callableDeleteIdCard = onCall(', '\n);')));
      expect(delId, contains('idCardMatchStatus: admin.firestore.FieldValue.delete()'));
      final delBank = _flat(_codeOf(_sliceOf(rawCf,
          'export const callableDeleteBankInfo = onCall(', '\n);')));
      expect(delBank,
          contains('bankbookMatchStatus: admin.firestore.FieldValue.delete()'));
    });
  });

  group('INV-1 — 세 축을 섞지 않는다', () {
    test('19 사람 판정 값이 match status에 들어가지 않는다', () {
      for (final body in [evaluator, idResolver, bankResolver]) {
        for (final v in [
          'MANUAL_APPROVED', 'MANUAL_REJECTED', 'REUPLOAD_REQUIRED',
          'REVIEWED_OK',
        ]) {
          expect(body, isNot(contains(v)), reason: '$v 는 사람 판정 축이다');
        }
      }
    });

    test('20 사람 review writer가 match status를 건드리지 않는다', () {
      final review = _flat(_codeOf(_sliceOf(rawCf,
          'export const callableReviewUserDocument = onCall(', '\n);')));
      expect(review, isNot(contains('idCardMatchStatus')));
      expect(review, isNot(contains('bankbookMatchStatus')));

      final bizReview = _flat(_codeOf(_sliceOf(rawCf,
          'export const callableReviewApplicantDocument = onCall(', '\n);')));
      expect(bizReview, isNot(contains('MatchStatus')));
    });

    test('21 correction writer가 match status를 건드리지 않는다', () {
      final corr = _flat(_codeOf(_sliceOf(rawCf,
          'export const callableRequestDocumentCorrection = onCall(', '\n);')));
      expect(corr, isNot(contains('MatchStatus')));
      final resub = _flat(_codeOf(
          _sliceOf(rawCf, 'async function srvMarkCorrectionsResubmitted(', '\n}')));
      expect(resub, isNot(contains('MatchStatus')));
    });

    test('22 match resolver가 correction/review를 읽지 않는다', () {
      for (final r in [idResolver, bankResolver]) {
        expect(r, isNot(contains('DOC_CORRECTION_COL')));
        expect(r, isNot(contains('BIZ_DOC_REVIEW_COL')));
      }
    });
  });

  group('INV-6 — 게이트 동작 변화 없음', () {
    test('23 확정 게이트는 여전히 사람 검토만 읽는다', () {
      final readiness = _flat(_codeOf(
          _sliceOf(rawCf, 'function srvResolveReviewReadiness(', '\n}')));
      // [PII-DOC-R1.5] 이 helper 자체는 여전히 사람 검토만 읽는다 —
      //   확정은 새 srvResolveMatchingReadiness로 옮겨갔고, 여기 남은 소비자는
      //   급여 경로다(R1.6 전까지).
      expect(readiness, isNot(contains('MatchStatus')));
      expect(readiness, contains('idDec === REVIEW_OK && !idStale'));
      expect(readiness, contains('bankDec === REVIEW_OK && !bankStale'));
    });

    test('24 급여 확정도 같은 helper를 그대로 쓴다', () {
      final confirm = _flat(_codeOf(_sliceOf(rawCf,
          'export const callableConfirmFinalWage = onCall(',
          'export const callableCancelFinalConfirmation')));
      expect(confirm, contains('srvResolveReviewReadiness('));
      expect(confirm, isNot(contains('MatchStatus')));
    });

    test('25 확정 게이트가 canonical match를 읽는다 (R1.5에서 연결)', () {
      // R1.4 시점에는 "아직 연결하지 않았다"가 고정 대상이었다.
      //   R1.5가 그 연결이고, 연결 방식은 matching_readiness_contract_test가
      //   따로 고정한다. 여기서는 급여 경로가 그대로인지만 확인한다.
      final confirmApp = _flat(_codeOf(_sliceOf(rawCf,
          'export const callableConfirmApplication = onCall(', '\n);')));
      expect(confirmApp, contains('srvResolveMatchingReadiness('));
      final wage = _flat(_codeOf(_sliceOf(rawCf,
          'export const callableConfirmFinalWage = onCall(',
          'export const callableCancelFinalConfirmation')));
      expect(wage, isNot(contains('srvResolveMatchingReadiness')),
          reason: '급여는 아직 R1.6 전이다');
    });

    test('26 자동 판정은 표시 전용 DTO로만 나간다', () {
      final dto = _flat(_codeOf(_sliceOf(rawCf,
          'export const callableGetApplicantDocumentReview = onCall(', '\n);')));
      expect(dto, contains('autoMatch: { idCard: srvResolveIdCardMatch(u),'));
      // readiness는 여전히 사람 검토 결과다.
      expect(dto, contains('readiness: {'));
    });
  });

  group('레거시 — 거짓 판정을 승격하지 않는다', () {
    test('27 v1 근거는 UNASSESSED', () {
      expect(_flat(evaluator),
          contains('if (!ev || ev["selfCheckVersion"] !== 2) return DOC_MATCH_UNASSESSED;'));
    });

    test('28 평가 기록이 없는 기존 사용자는 UNASSESSED', () {
      for (final r in [idResolver, bankResolver]) {
        expect(_flat(r), contains('if (!stored) {'));
        expect(_flat(r), contains('status: DOC_MATCH_UNASSESSED, storedStatus: null'));
      }
    });

    test('29 문서가 없으면 다른 필드보다 MISSING이 우선', () {
      for (final r in [idResolver, bankResolver]) {
        final iHasDoc = r.indexOf('hasDoc');
        final iStored = r.indexOf('stored');
        expect(iHasDoc, greaterThan(0));
        expect(iHasDoc, lessThan(iStored),
            reason: '삭제 후 잔존 필드가 MATCHED로 읽히면 안 된다');
      }
    });
  });

  group('보안 — 새 민감정보 없음', () {
    test('30 계좌 fingerprint·서버 암호화 도입 없음', () {
      expect(cf, isNot(contains('accountNumberFingerprint')));
      expect(cf, isNot(contains('computeAccountFingerprint')));
    });

    test('31 raw OCR text / 전체 식별번호를 저장하지 않는다', () {
      final idWriter = _flat(_codeOf(_sliceOf(rawCf,
          'export const callableMarkIdCardVerified = onCall(', '\n);')));
      expect(idWriter, isNot(contains('rawText')));
      expect(idWriter, isNot(contains('foreignIdRaw')));
      final bbWriter = _flat(_codeOf(_sliceOf(rawCf,
          'export const callableMarkBankbookVerified = onCall(', '\n);')));
      expect(bbWriter, isNot(contains('rawText')));
      expect(bbWriter, isNot(contains('accountNumberPlain')));
    });
  });
}
