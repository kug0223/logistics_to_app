// [PII-DOC-R1.3] 통장사본 — 점수가 아니라 항목의 의미가 결과를 정한다
//
// 이 파일이 고정하는 것:
//
//   INV-1  계좌번호를 비교하지 않음 ≠ 계좌번호 일치
//   INV-2  계좌번호 불일치 → confidence가 아무리 높아도 SUCCESS 금지
//   INV-3  예금주를 못 읽음 ≠ 예금주 불일치
//   INV-4  화면의 성공/경고 = 서버로 가는 evidence
//   INV-5  document consistency ≠ 금융기관 인증
//
// 판정 결과 자체의 truth table은 test/unit/bank_document_evidence_test.dart.
// 여기서는 **누가 무엇을 보고 분기하는지**를 소스에서 고정한다.

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

const _ocrPath = 'lib/utils/ocr_verification_helper.dart';
const _pickPath = 'lib/utils/document_upload_helper.dart';
const _cfPath = 'functions/src/index.ts';

void main() {
  final ocrRaw = _src(_ocrPath);
  final ocr = _codeOf(ocrRaw);
  final pickRaw = _src(_pickPath);
  final pick = _codeOf(pickRaw);
  // 통장 분기만 — 주석 제거 전 원본에서 잘라야 경계 마커가 살아 있다.
  final bankBranch = _codeOf(_sliceOf(pickRaw,
      'Future<DocumentPickResult?> pickAndVerifyBankbook(',
      'pickAndVerifyBusinessLicense('));
  // 통장 판정 구간만 잘라 본다 — 신분증 구간과 섞이지 않게.
  final bankFn = _codeOf(_sliceOf(ocrRaw,
      'static Map<String, dynamic> _verifyBankbookFromText(',
      'static Map<String, dynamic> verifyBankbookForTesting('));

  group('INV-1 — 비교하지 않음 ≠ 일치', () {
    test('01 "기본값 true"가 사라졌다', () {
      // `bool isAccountValid = true;` 가 신분증 R1-B3와 같은 함정이었다.
      expect(bankFn, isNot(contains('bool isAccountValid = true;')));
      expect(bankFn,
          contains('DocFieldOutcome accountOutcome = DocFieldOutcome.unassessed;'));
    });

    test('02 expected가 없으면 UNASSESSED로 남는다', () {
      // 기대값이 있을 때만 if 블록에 들어가고, 그 밖에서는 초기값이 UNASSESSED다.
      expect(bankFn,
          contains("if (expectedAccountNumber != null && expectedAccountNumber.isNotEmpty) {"));
      expect(_flat(bankFn),
          contains('final isAccountValid = accountOutcome == DocFieldOutcome.matched;'));
    });

    test('03 예금주도 같은 규칙', () {
      expect(_flat(bankFn),
          contains('if (expectedName == null || expectedName.isEmpty) '
              '{ holderOutcome = DocFieldOutcome.unassessed;'));
    });
  });

  group('INV-2 — 점수가 정오를 정하지 않는다', () {
    test('04 성공 조건이 계좌 MATCHED를 필수로 한다', () {
      expect(
          _flat(bankFn),
          contains('final isDocumentConsistent = '
              'accountOutcome == DocFieldOutcome.matched && '
              'holderOutcome != DocFieldOutcome.mismatch;'));
    });

    test('05 옛 규칙이 사라졌다', () {
      expect(bankFn, isNot(contains('final isValid = isNameValid;')),
          reason: '예금주만 맞으면 통과하던 규칙');
    });

    test('06 화면 분기가 confidence를 보지 않는다', () {
      // 통장 분기에서 confidence 임계값이 사라져야 한다.
      expect(bankBranch, contains("result['isDocumentConsistent'] == true"));
      expect(bankBranch, isNot(contains("result['confidence'] >= 0.6")),
          reason: '점수 임계값이 성공을 결정하면 안 된다');
    });

    test('07 confidence는 남아 있되 판정에 쓰이지 않는다', () {
      expect(bankFn, contains('final confidence = assessed == 0 ? 0.0 :'));
      // 평가한 항목만 분모 — UNASSESSED가 분모를 부풀리지 않는다.
      expect(_flat(bankFn),
          contains('if (o == DocFieldOutcome.unassessed) continue;'));
    });

    test('08 은행명은 성공 조건에 참여하지 않는다 (PD-3)', () {
      final decision = _sliceOf(bankFn,
          'final isDocumentConsistent =', ';');
      expect(decision, isNot(contains('bankOutcome')));
    });
  });

  group('INV-3 — 못 읽음 ≠ 불일치', () {
    test('09 계좌: 후보를 읽었는지로 MISMATCH/UNREADABLE을 가른다', () {
      expect(bankFn, contains('bool sawAccountCandidate = false;'));
      expect(
          _flat(bankFn),
          contains('accountOutcome = sawAccountCandidate '
              '? DocFieldOutcome.mismatch : DocFieldOutcome.unreadable;'));
    });

    test('10 예금주: 라벨로 읽은 경우만 MISMATCH', () {
      // Step 2(첫 줄)·Step 3(블록)은 추측이다 — "국민은행"을 예금주로 집어 온다.
      expect(ocr, contains('({String? name, bool labeled})'));
      expect(_flat(bankFn), contains('holderRead.labeled &&'));
      expect(bankFn, contains('holderOutcome = DocFieldOutcome.unreadable;'));
    });

    test('11 추측 경로는 labeled: false로 표시된다', () {
      final ext = _sliceOf(ocrRaw,
          'static ({String? name, bool labeled}) _extractAccountHolder(',
          'static String? _extractBankName(');
      expect('labeled: true'.allMatches(ext).length, 3,
          reason: '라벨 근거가 있는 세 경로');
      expect('labeled: false'.allMatches(ext).length, 3,
          reason: '첫 줄 추측 · 블록 추측 · 못 찾음');
    });

    test('12 화면이 셋을 구분해 말한다', () {
      expect(pick, contains('입력한 계좌번호와 통장사본의 계좌번호가 일치하지 않습니다'));
      expect(pick, contains('통장사본에서 계좌번호를 정확히 읽지 못했습니다'));
      expect(pick, contains('등록된 계좌번호가 없어 통장사본과 대조하지 못했습니다'));
      expect(pick, contains('등록된 이름과 통장사본의 예금주명이 일치하지 않습니다'));
      // 못 읽은 예금주를 실패 사유로 말하지 않는다.
      expect(pick, isNot(contains('• 예금주명이 일치하지 않습니다')));
    });

    test('13 불일치가 없었던 제출은 강행이 아니다', () {
      expect(pick, contains('overridden: bkHadMismatch'));
    });
  });

  group('INV-4 — 화면 결과 = 저장 evidence', () {
    test('14 화면이 판정을 다시 계산하지 않는다', () {
      expect(bankBranch, contains("result['holderOutcome'] as DocFieldOutcome?"));
      expect(bankBranch, contains("result['accountOutcome'] as DocFieldOutcome?"));
      // R1.2에서 화면이 직접 매핑하던 코드는 사라져야 한다.
      expect(bankBranch, isNot(contains("result['isNameValid'] == true")));
      expect(bankBranch, isNot(contains("result['isAccountValid'] == true")));
    });

    test('15 서버로 가는 근거가 같은 값이다', () {
      expect('nameOutcome: bkName'.allMatches(bankBranch).length, 2);
      expect('identifierOutcome: bkIdent'.allMatches(bankBranch).length, 2);
    });

    test('16 R1.2 payload 계약을 그대로 쓴다', () {
      final sc = _sliceOf(_src(_pickPath),
          'Map<String, dynamic> get selfCheck =>', '};');
      expect(sc, contains("'selfCheckVersion': 2"));
      expect(sc, contains("'name': nameOutcome.wire"));
      expect(sc, contains("'identifier': identifierOutcome.wire"));
      // legacy bool을 다시 붙이지 않는다.
      expect(sc, isNot(contains('nameMatched')));
      expect(sc, isNot(contains('identifierMatched')));
    });

    test('17 서버 generic helper를 통장 때문에 바꾸지 않았다', () {
      final cf = _codeOf(_src(_cfPath));
      final fn = _flat(_codeOf(
          _sliceOf(_src(_cfPath), 'function srvComputeDocumentState(', '\n}')));
      // 통장 전용 분기가 생기면 신분증과 규칙이 갈라진다.
      expect(fn, isNot(contains('bankbook')));
      expect(fn, isNot(contains('BANKBOOK')));
      expect(fn, contains('nameOutcome === DOC_FIELD_MATCHED && '
          'identifierOutcome === DOC_FIELD_MATCHED'));
      expect(cf, isNot(contains('documentMatchStatus')),
          reason: 'canonical state는 R1.4다');
    });
  });

  group('INV-5 — 이름이 금융 인증을 주장하지 않는다', () {
    test('18 isValid → isDocumentConsistent', () {
      expect(bankFn, contains("'isDocumentConsistent': isDocumentConsistent"));
      expect(bankFn, isNot(contains("'isValid': isValid")));
    });

    test('19 금융 인증 표현이 없다', () {
      for (final banned in ['실명인증', '실명 인증', '계좌 인증 완료', '금융기관 검증']) {
        expect(pick, isNot(contains(banned)));
        expect(ocr, isNot(contains(banned)));
      }
    });
  });

  group('범위 — 이번에 건드리지 않은 것', () {
    test('20 은행명 DB를 확장하지 않았다', () {
      final banks = _sliceOf(ocrRaw, 'final banks = [', '];');
      expect("'".allMatches(banks).length ~/ 2, lessThanOrEqualTo(30),
          reason: '은행 목록 확장은 BACKLOG');
    });

    test('21 계좌 fingerprint·서버 암호화 도입 없음', () {
      final cf = _codeOf(_src(_cfPath));
      expect(cf, isNot(contains('accountNumberFingerprint')));
      // [PII-B4-R1.1] 원래는 'ENCRYPT_KEY' 문자열 자체를 금지했는데,
      //   "서버에 ENCRYPT_KEY가 없어 복호화할 수 없다"는 설명 주석이
      //   그 문자열을 포함한다. 지켜야 할 것은 **키를 서버로 들여오지
      //   않는 것**이므로 실제 사용 형태로 고정한다.
      expect(cf, isNot(contains('process.env.ENCRYPT_KEY')));
      expect(cf, isNot(contains('defineSecret("ENCRYPT_KEY")')));
      expect(pick, isNot(contains('fingerprint')));
    });

    test('22 계좌번호를 로그에 남기지 않는다', () {
      final logs = RegExp(r'debugPrint\([^)]*\)').allMatches(ocr);
      for (final m in logs) {
        final t = m.group(0)!;
        expect(t.contains('expectedAccountNumber'), isFalse, reason: t);
        expect(t.contains('extractedAccountNumber'), isFalse, reason: t);
        expect(t.contains('rawText}'), isFalse, reason: t);
      }
    });

    test('23 신분증 경로는 이번에 바뀌지 않았다', () {
      final idFn = _codeOf(_sliceOf(ocrRaw,
          'static Map<String, dynamic> _verifyIdCardFromText(',
          'static Map<String, dynamic> verifyIdCardForTesting('));
      expect(idFn, contains('bool isResidentNumberValid = false;'));
      expect(idFn, contains('final isValid = nameOutcome == DocFieldOutcome.matched'));
    });
  });
}
