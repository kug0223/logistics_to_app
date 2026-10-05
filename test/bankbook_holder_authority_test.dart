// [R7-P4.4E.9C.1] 라벨에서 읽은 예금주가 문서 아무 곳의 등장에 밀렸다
//
// E9C READ 가 재현한 결함.
//
//   예금주: 김철수        ← 라벨에서 **명확히 읽은** 값
//   ...
//   홍길동                ← 메모·담당자·안내문 어디든
//   expectedName = 홍길동
//
// 예전 판정 순서는 문서 전체 substring 검사를 라벨 판정보다 앞에 두었다.
//
//   if (cleanedOcr.contains(expected)) → MATCHED      ← 먼저
//   else if (labeled && name != null)  → MISMATCH
//
// 그래서 위 입력이 MATCHED 가 됐다. 그 MATCHED 는 서버에서
// `bankbookMatchStatus = MATCHED` → `PR_READY_AUTO` → 급여 확정 시 계좌
// snapshot → 이체 대상까지 이어진다. 돈이 걸린 false-ready 다.
//
// 이 파일이 고정하는 계약 (MODEL B — HOLDER SUPPORTING-ONLY 유지)
//
//   STRONG labeled holder  >  WEAK whole-document occurrence
//
//   · 라벨('예금주'·'계좌주') 옆에서 읽었으면 **그 값이 결론을 소유한다**
//   · 라벨 근거가 없을 때만 문서 전체 등장을 weak positive 로 쓴다
//   · 기대 이름이 문서에 없다는 사실은 MISMATCH 가 아니라 UNREADABLE
//   · 예금주를 못 읽은 것은 여전히 불일치가 아니다(INV-3)
//   · 외국인(expectedName 없음)은 판정하지 않는다 — 음차 matching 없음
//
// fixture 는 전부 **합성 레이아웃**이다. 실제 통장 원본은 repo 에 넣지 않는다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/utils/identity_identifier.dart';
import 'package:ALfit/utils/ocr_verification_helper.dart';

/// 합성 값(실재하지 않는 조합).
const kExpected = '홍길동';
const kOther = '김철수';
const kAcct = '010-123456-01-017';

Map<String, dynamic> _v(
  String raw, {
  String expectedName = kExpected,
  String? expectedAccountNumber,
}) =>
    OcrVerificationHelper.verifyBankbookForTesting(
      raw,
      expectedName,
      expectedAccountNumber: expectedAccountNumber,
    );

DocFieldOutcome _holder(String raw, {String expectedName = kExpected}) =>
    _v(raw, expectedName: expectedName)['holderOutcome'] as DocFieldOutcome;

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('소스를 찾지 못했다: $p');
  return f.readAsStringSync();
}

/// 주석을 지운 코드만 — 주석 문구가 바뀌어도 깨지지 않게.
String _codeOf(String path) {
  final out = StringBuffer();
  for (final line in _src(path).split('\n')) {
    final t = line.trimLeft();
    if (t.startsWith('//') || t.startsWith('*') || t.startsWith('/*')) continue;
    out.writeln(line);
  }
  return out.toString();
}

const _ocr = 'lib/utils/ocr_verification_helper.dart';
const _cf = 'functions/src/index.ts';

String _between(String code, String from, String to) {
  final a = code.indexOf(from);
  expect(a, greaterThan(-1), reason: '앵커를 찾지 못했다: $from');
  final b = code.indexOf(to, a);
  expect(b, greaterThan(a), reason: '앵커를 찾지 못했다: $to');
  return code.substring(a, b);
}

void main() {
  // ══════════════════════════════════════════════════════════════
  // D — 국내 합성 fixture (행동)
  // ══════════════════════════════════════════════════════════════
  group('BHA-D 라벨 증거가 결론을 소유한다', () {
    test('D1 라벨 예금주가 기대와 같다 → MATCHED', () {
      expect(_holder('IBK기업은행\n계좌번호 $kAcct\n예금주 $kExpected'),
          DocFieldOutcome.matched);
    });

    test('D2 라벨 예금주가 기대와 다르다 → MISMATCH', () {
      expect(_holder('IBK기업은행\n계좌번호 $kAcct\n예금주 $kOther'),
          DocFieldOutcome.mismatch);
    });

    test('D3 라벨은 있는데 이름을 못 읽었다 → UNREADABLE', () {
      // 라벨 뒤가 비어 있으면 candidate 가 없다. 다르다고 말하지 않는다.
      expect(_holder('IBK기업은행\n예금주:\n계좌번호 $kAcct'),
          DocFieldOutcome.unreadable);
    });

    test('D4 [BLOCKER 회귀] 다른 곳의 기대 이름이 라벨 불일치를 뒤집지 못한다', () {
      // 이 셀이 이번 Phase 의 존재 이유다.
      final raw = 'IBK기업은행\n'
          '예금주: $kOther\n'
          '계좌번호 $kAcct\n'
          '담당자 $kExpected\n'
          '메모 $kExpected 님 감사합니다';
      final r = _v(raw, expectedAccountNumber: kAcct);
      expect(r['holderOutcome'], DocFieldOutcome.mismatch,
          reason: '라벨에서 $kOther 를 읽었다 — 문서 다른 곳의 $kExpected 는 '
              '그 사실을 뒤집는 증거가 아니다');
      expect(r['accountOutcome'], DocFieldOutcome.matched);
      expect(r['isDocumentConsistent'], isFalse,
          reason: '계좌가 맞아도 예금주 불일치는 veto 다');
    });

    test('D5 여러 한글 이름 — 라벨 쪽이 결론이다', () {
      expect(
          _holder('예금주: $kOther\n담당자: $kExpected\n계좌번호 $kAcct'),
          DocFieldOutcome.mismatch);
      expect(
          _holder('예금주: $kExpected\n담당자: $kOther\n계좌번호 $kAcct'),
          DocFieldOutcome.matched);
    });

    test('D6 공백 변형 — 현재 normalization 범위를 그대로 고정한다', () {
      // `예 금 주` 는 라벨 검색(`line.contains('예금주')`)에 걸리지 않는다.
      //   → labeled == false → weak fallback 경로로 간다.
      //   `_cleanText` 가 공백을 제거하므로 전체 문서에는 이름이 있다.
      // 새 fuzzy normalization 을 추가하지 않고 이 동작을 고정한다.
      expect(_holder('예 금 주 : 홍 길 동\n계좌번호 $kAcct'),
          DocFieldOutcome.matched);
    });

    test('D7 라벨이 전혀 없고 기대 이름이 문서에 있다 → weak positive MATCHED', () {
      // false MISMATCH 완화 장치가 살아 있음을 증명한다.
      expect(_holder('$kExpected\n$kAcct\nIBK기업은행'),
          DocFieldOutcome.matched);
    });

    test('D8 라벨이 없고 기대 이름도 없다 → UNREADABLE (MISMATCH 금지)', () {
      expect(_holder('$kOther\n$kAcct'), DocFieldOutcome.unreadable,
          reason: '추측 경로로 불일치를 선언하지 않는다');
    });

    test('D9 기대 이름이 비어 있으면 판정하지 않는다 → UNASSESSED', () {
      expect(
          _holder('예금주 $kOther\n계좌번호 $kAcct', expectedName: ''),
          DocFieldOutcome.unassessed,
          reason: '문서에 이름이 있어도 비교 기준이 없으면 판정이 아니다');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // ORD — 순서가 다시 뒤집히지 않게
  // ══════════════════════════════════════════════════════════════
  group('BHA-ORD 증거 등급이 코드 순서다', () {
    test('ORD-01 labeled 분기가 whole-document substring 보다 앞이다', () {
      final body = _between(_codeOf(_ocr),
          'final DocFieldOutcome holderOutcome;', 'final isNameValid =');
      final labeledAt = body.indexOf('holderRead.labeled &&');
      final substringAt = body.indexOf('cleanedOcr.contains(_cleanText(expectedName))');
      expect(labeledAt, greaterThan(-1));
      expect(substringAt, greaterThan(-1));
      expect(labeledAt, lessThan(substringAt),
          reason: 'substring 이 먼저면 라벨 불일치가 다시 묻힌다');
    });

    test('ORD-02 labeled 분기가 같으면 MATCHED·다르면 MISMATCH 를 **스스로** 정한다', () {
      final body = _between(_codeOf(_ocr),
          'final DocFieldOutcome holderOutcome;', 'final isNameValid =');
      expect(
          body.contains(
              '_cleanText(extractedName) == _cleanText(expectedName)'),
          isTrue);
      expect(body.contains('? DocFieldOutcome.matched'), isTrue);
      expect(body.contains(': DocFieldOutcome.mismatch'), isTrue);
    });

    test('ORD-03 판정을 상수로 무력화하지 않았다', () {
      final body = _between(_codeOf(_ocr),
          'final DocFieldOutcome holderOutcome;', 'final isNameValid =');
      for (final cheat in ['false &&', '&& false', 'true ||', '|| true']) {
        expect(body.contains(cheat), isFalse, reason: '판정에 $cheat');
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // F — 외국인 동작 무변경
  // ══════════════════════════════════════════════════════════════
  group('BHA-F 외국인은 예금주를 판정하지 않는다', () {
    // 실제 production 은 `expectedName = null` 을 넘긴다. 테스트 진입점이
    //   non-null 이라 동일 분기를 타는 빈 문자열로 행동을 증명하고,
    //   null 경로와 호출부는 소스로 고정한다.
    test('F1 라틴 예금주 일치해도 판정 없음', () {
      expect(_holder('IBK BANK\nHOLDER JOHN SMITH\n$kAcct', expectedName: ''),
          DocFieldOutcome.unassessed);
    });

    test('F2 대소문자·공백 변형도 판정 없음', () {
      expect(_holder('ibk bank\nholder  john   smith\n$kAcct', expectedName: ''),
          DocFieldOutcome.unassessed);
    });

    test('F3 다른 라틴 예금주도 MISMATCH 가 아니다', () {
      expect(_holder('IBK BANK\nHOLDER JANE DOE\n$kAcct', expectedName: ''),
          DocFieldOutcome.unassessed);
    });

    test('F4 한글/라틴 표기 혼재도 음차 matching 하지 않는다', () {
      expect(
          _holder('예금주 KIM CHUL SOO\n계좌번호 $kAcct', expectedName: ''),
          DocFieldOutcome.unassessed);
    });

    test('F5 못 읽어도 판정 없음', () {
      expect(_holder('IBK BANK\n$kAcct', expectedName: ''),
          DocFieldOutcome.unassessed);
    });

    test('F6 null 경로와 호출부가 그대로다', () {
      final body = _between(_codeOf(_ocr),
          'final DocFieldOutcome holderOutcome;', 'final isNameValid =');
      expect(body.contains('expectedName == null || expectedName.isEmpty'),
          isTrue);
      final screen = _src('lib/screens/common/document_management_screen.dart');
      expect(screen.contains('user.isForeign ? null : user.name'), isTrue,
          reason: '외국인에게 legalName/accountHolder 를 주입하지 않는다');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // V — 버전/freshness 무변경
  // ══════════════════════════════════════════════════════════════
  group('BHA-V 증거 freshness 축이 그대로다', () {
    test('V1 계좌 변경이 통장 증거를 초기화한다', () {
      final code = _codeOf(_cf);
      final body = _between(
          code, 'export const callableUpdateBankAccount = onCall(', '\n);\n');
      expect(body.contains('bankAccountVersion: admin.firestore.FieldValue.increment(1)'),
          isTrue);
      expect(body.contains('bankbookMatchStatus: admin.firestore.FieldValue.delete()'),
          isTrue);
      expect(body.contains('bankbookImagePath: admin.firestore.FieldValue.delete()'),
          isTrue);
    });

    test('V2 통장 재업로드가 문서 버전을 올린다', () {
      final code = _codeOf(_cf);
      expect(code.contains('bankbookDocumentVersion'), isTrue);
      final body = _between(
          code, 'export const callableMarkBankbookVerified = onCall(', '\n);\n');
      expect(body.contains('bankbookMatchStatus'), isTrue);
      expect(body.contains('bankbookMatchAccountVersion'), isTrue);
    });

    test('V3 낡은 판정은 현재 계좌를 통과시키지 못한다', () {
      final code = _codeOf(_cf);
      final body = _between(
          code, 'function srvResolveBankbookMatch(', '\n}\n');
      expect(body.contains('const isStale = evBb !== curBb || evAcc !== curAcc'),
          isTrue);
      expect(body.contains('status: isStale ? DOC_MATCH_UNASSESSED : stored'),
          isTrue);
    });

    test('V4 클라이언트 resolver 도 같은 두 축을 본다', () {
      final dm = _codeOf('lib/utils/document_match.dart');
      final body = _between(dm, 'DocumentMatchSnapshot resolveBankbookMatch(', '\n}\n');
      expect(body.contains('bankbookMatchDocumentVersion'), isTrue);
      expect(body.contains('bankbookMatchAccountVersion'), isTrue);
      expect(body.contains('DocumentMatchStatus.unassessed'), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // DS — downstream 계약 (서버 매핑 · 급여)
  // ══════════════════════════════════════════════════════════════
  group('BHA-DS 예금주 불일치는 끝까지 veto 다', () {
    test('DS-01 서버가 MISMATCH 를 가장 먼저 본다', () {
      final body = _between(_codeOf(_cf),
          'function srvEvaluateMatchStatus(', '\n}\n');
      expect(
          body.contains(
              'if (name === DOC_FIELD_MISMATCH || identifier === DOC_FIELD_MISMATCH)'),
          isTrue,
          reason: 'MISMATCH > OCR_UNCERTAIN > UNASSESSED > MATCHED 순서');
      expect(body.contains('return DOC_MATCH_MISMATCH'), isTrue);
    });

    test('DS-02 급여 준비가 MISMATCH 를 차단한다', () {
      final body = _between(_codeOf(_cf),
          'function srvResolvePayrollReadiness(', '\n}\n');
      expect(body.contains('auto.status === DOC_MATCH_MISMATCH'), isTrue);
      expect(body.contains('PR_BANK_MISMATCH'), isTrue);
      // UNREADABLE 은 여전히 차단 사유다(계좌 축). 예금주 UNREADABLE 은
      //   requireName:false 때문에 MATCHED 로 수렴한다 — MODEL B 유지.
      expect(body.contains('PR_READY_AUTO'), isTrue);
    });

    test('DS-03 통장은 이름 일치를 MATCHED 의 필수 조건으로 요구하지 않는다', () {
      final code = _codeOf(_cf);
      expect(code.contains('requireName: false'), isTrue,
          reason: 'MODEL B — 이번 Phase 에서 바꾸지 않는다');
      expect(code.contains('requireName: true'), isTrue,
          reason: '신분증 축은 그대로 true 다');
    });

    test('DS-04 OCR 실패는 OCR_UNCERTAIN 이다', () {
      final body = _between(_codeOf(_cf),
          'function srvEvaluateMatchStatus(', '\n}\n');
      expect(body.contains('if (ev["ocrFailed"] === true) return DOC_MATCH_OCR_UNCERTAIN'),
          isTrue);
    });

    test('DS-05 상태 어휘를 늘리지 않았다', () {
      final code = _codeOf(_cf);
      for (final s in [
        'DOC_MATCH_MISSING', 'DOC_MATCH_UNASSESSED', 'DOC_MATCH_MATCHED',
        'DOC_MATCH_MISMATCH', 'DOC_MATCH_OCR_UNCERTAIN',
      ]) {
        expect(code.contains(s), isTrue);
      }
      expect(DocFieldOutcome.values.length, 4,
          reason: 'MATCHED/MISMATCH/UNREADABLE/UNASSESSED — 다섯 번째를 만들지 않는다');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // KEEP — 이번 Phase 가 건드리지 않은 축
  // ══════════════════════════════════════════════════════════════
  group('BHA-KEEP 범위 밖 무변경', () {
    test('KEEP-01 E9A 계좌 parser 가 그대로다', () {
      final ocr = _codeOf(_ocr);
      expect(ocr.contains('accountMinDigits'), isTrue);
      expect(ocr.contains('accountMaxDigits'), isTrue);
      expect(ocr.contains('_accountPositiveLabels'), isTrue);
      expect(ocr.contains('_accountNegativeLabels'), isTrue);
      // 구분자 넷 계좌 · 전화번호 배제가 살아 있다.
      expect(
          _v('IBK기업은행\n계좌번호 $kAcct\n예금주 $kExpected',
              expectedAccountNumber: kAcct)['accountOutcome'],
          DocFieldOutcome.matched);
      expect(
          _v('IBK기업은행\n연락처 010-1234-5678',
              expectedAccountNumber: kAcct)['accountOutcome'],
          DocFieldOutcome.unreadable,
          reason: '전화번호를 읽은 것은 계좌를 읽은 것이 아니다');
      // 자릿수 경계 — 짧은 숫자는 계좌 후보가 아니다. 이 값이 내려가면
      //   창구번호·전표번호가 후보로 올라와 UNREADABLE 이 MISMATCH 로 바뀐다.
      expect(OcrVerificationHelper.accountMinDigits, 9);
      expect(OcrVerificationHelper.accountMaxDigits, 20);
      expect(
          _v('IBK기업은행\n창구 1234\n예금주 $kExpected',
              expectedAccountNumber: kAcct)['accountOutcome'],
          DocFieldOutcome.unreadable,
          reason: '네 자리 숫자를 계좌 후보로 세지 않는다');
    });

    test('KEEP-02 은행명은 supporting-only 이고 성공 조건이 아니다', () {
      final ocr = _codeOf(_ocr);
      expect(ocr.contains('final isBankValid = bankOutcome != DocFieldOutcome.mismatch'),
          isTrue);
      expect(
          ocr.contains('final isDocumentConsistent = accountOutcome == DocFieldOutcome.matched &&'),
          isTrue);
      expect(ocr.contains('holderOutcome != DocFieldOutcome.mismatch'), isTrue);
    });

    test('KEEP-03 라벨 사전을 넓히지 않았다', () {
      final ext = _between(_src(_ocr),
          'static ({String? name, bool labeled}) _extractAccountHolder(',
          'static String? _extractBankName(');
      expect(ext.contains("line.contains('예금주') || line.contains('계좌주')"),
          isTrue);
      for (final notYet in ['성명', '고객명', 'ACCOUNT HOLDER']) {
        expect(ext.contains(notYet), isFalse,
            reason: '$notYet 추가는 실기기 증거가 필요한 별도 CORRECTION 이다');
      }
    });

    test('KEEP-04 추출 로직 자체는 바뀌지 않았다 — 라벨 경로 3 / 추측 경로 3', () {
      final ext = _between(_src(_ocr),
          'static ({String? name, bool labeled}) _extractAccountHolder(',
          'static String? _extractBankName(');
      expect('labeled: true'.allMatches(ext).length, 3);
      expect('labeled: false'.allMatches(ext).length, 3);
    });

    test('KEEP-05 사람 검토 fallback 이 그대로다', () {
      final code = _codeOf(_cf);
      expect(code.contains('bankDecision'), isTrue);
      expect(code.contains('REVIEW_OK'), isTrue);
      final body = _between(code,
          'function srvResolvePayrollReadiness(', '\n}\n');
      expect(body.contains('manualOk'), isTrue);
      expect(body.contains('PR_READY_MANUAL'), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // OVR — 강행 기록
  // ══════════════════════════════════════════════════════════════
  group('BHA-OVR 강행은 실제 불일치가 있을 때만', () {
    test('OVR-01 불일치 세 축 중 하나라도 있을 때만 overridden 이다', () {
      final pick = _src('lib/utils/document_upload_helper.dart');
      expect(
          pick.contains('final bkHadMismatch = bkIdent == DocFieldOutcome.mismatch ||'),
          isTrue);
      expect(pick.contains('bkName == DocFieldOutcome.mismatch ||'), isTrue);
    });

    test('OVR-02 못 읽은 예금주를 실패 사유로 말하지 않는다', () {
      final pick = _src('lib/utils/document_upload_helper.dart');
      expect(
          pick.contains('등록된 이름과 통장사본의 예금주명이 일치하지 않습니다'),
          isTrue);
      expect(pick.contains('• 예금주명이 일치하지 않습니다'), isFalse);
    });
  });
}
