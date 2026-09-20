// [PII-B4-R1.4] 전체 13자리 대조 — 비교자이지 추출기가 아니다
//
// 이 파일이 고정하는 것:
//
//   INV-1  기대값 길이가 비교 범위를 정한다 (자유 추출 금지)
//   INV-2  다른 숫자군(면허번호 등)을 세무 번호로 집어 오지 않는다
//   INV-3  네 가지 결과를 구분한다 — 실패는 불일치가 아니다
//   INV-4  추출된 번호는 저장·전송되지 않는다
//   INV-5  등록된 번호를 화면에 되돌려 보여주지 않는다

import 'dart:io';

import 'package:ALfit/utils/identity_identifier.dart';
import 'package:ALfit/utils/ocr_verification_helper.dart';
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
const _sheetPath = 'lib/screens/common/document_management_screen.dart';
const _pickPath = 'lib/utils/document_upload_helper.dart';

/// 실제 판정 로직을 그대로 태운다 (ML Kit 없이).
DocFieldOutcome _outcome(String rawText, String expected) =>
    OcrVerificationHelper.verifyIdCardForTesting(
      rawText,
      '홍길동',
      expectedResidentNumber: expected,
    )['identifierOutcome'] as DocFieldOutcome;

void main() {
  final ocrRaw = _src(_ocrPath);
  final ocr = _codeOf(ocrRaw);

  group('INV-1 — 기대값이 비교 범위를 정한다 (§30)', () {
    test('01 13자리 기대값이면 13자리 패턴을 쓴다', () {
      final fn = _flat(_codeOf(_sliceOf(ocrRaw,
          'static Map<String, dynamic> _verifyIdCardFromText(',
          'static Map<String, dynamic> verifyIdCardForTesting(')));
      expect(fn, contains('final wantsFull = cleanedExpectedRN.length == 13;'));
      expect(fn, contains(r"RegExp(r'(\d{6})[-\s]?(\d{7})')"));
      // 7자리 기대값 경로는 그대로 남는다.
      expect(fn, contains(r"RegExp(r'(\d{6})[-\s]?(\d)')"));
    });

    test('02 O1 — 신분증에 그 번호가 보이면 MATCHED', () {
      const rrn = '9001011234567';
      expect(_outcome('홍길동\n900101-1234567\n서울시', rrn),
          DocFieldOutcome.matched);
    });

    test('03 O2 — 다른 번호가 보이면 MISMATCH', () {
      expect(_outcome('홍길동\n900101-7654321\n서울시', '9001011234567'),
          DocFieldOutcome.mismatch);
    });

    test('04 O3 — 번호 자체를 못 읽으면 UNREADABLE', () {
      expect(_outcome('홍길동\n주민등록증\n서울시', '9001011234567'),
          DocFieldOutcome.unreadable);
    });

    test('05 O4 — 기대값이 없으면 UNASSESSED', () {
      final r = OcrVerificationHelper.verifyIdCardForTesting(
          '홍길동\n900101-1234567', '홍길동');
      expect(r['identifierOutcome'], DocFieldOutcome.unassessed);
    });

    test('06 구분자가 없어도 같은 값으로 읽는다', () {
      expect(_outcome('홍길동 9001011234567', '9001011234567'),
          DocFieldOutcome.matched);
    });

    test('07 줄 안에 잡음이 섞여도 같은 줄이면 찾는다 (§31)', () {
      expect(_outcome('홍길동\n900101 - 123 4567\n서울', '9001011234567'),
          DocFieldOutcome.matched);
    });
  });

  group('INV-2 — 다른 숫자군을 집어 오지 않는다 (§31)', () {
    test('08 O5 — 면허번호가 있어도 세무 번호로 읽지 않는다', () {
      // 운전면허증: 이름 / 주민번호 / 면허번호(2-2-6-2)
      const text = '홍길동\n900101-1234567\n11-22-333333-44\n경기지방경찰청';
      expect(_outcome(text, '9001011234567'), DocFieldOutcome.matched);
      // 기대값이 다르면 면허번호를 대신 고르지 않는다 — MISMATCH다.
      expect(_outcome(text, '9001019999999'), DocFieldOutcome.mismatch);
    });

    test('09 면허번호만 있는 문서는 UNREADABLE이지 MISMATCH가 아니다', () {
      expect(_outcome('홍길동\n11-22-333333-44', '9001011234567'),
          DocFieldOutcome.unreadable);
    });

    test('10 any-match다 — 앞에 다른 숫자가 있어도 뒤를 본다', () {
      expect(_outcome('010-1234-5678\n900101-1234567', '9001011234567'),
          DocFieldOutcome.matched);
    });
  });

  group('INV-3 — 실패는 불일치가 아니다 (§16·§33)', () {
    test('11 네 가지 어휘가 그대로다', () {
      expect(DocFieldOutcome.values.length, 4);
      expect(DocFieldOutcome.matched.wire, 'MATCHED');
      expect(DocFieldOutcome.mismatch.wire, 'MISMATCH');
      expect(DocFieldOutcome.unreadable.wire, 'UNREADABLE');
      expect(DocFieldOutcome.unassessed.wire, 'UNASSESSED');
    });

    test('12 모르는 값은 UNASSESSED로 떨어진다', () {
      expect(docFieldOutcomeFromWire(null), DocFieldOutcome.unassessed);
      expect(docFieldOutcomeFromWire('PASSED'), DocFieldOutcome.unassessed);
      expect(docFieldOutcomeFromWire('MISMATCH'), DocFieldOutcome.mismatch);
    });

    test('13 OCR 예외는 불일치로 승격되지 않는다', () {
      final sheet = _codeOf(_src(_sheetPath));
      final fn = _flat(_sliceOf(sheet,
          'Future<void> _compareWithIdCard() async {', '\n  }'));
      expect(fn, contains('catch (e) {'));
      expect(fn, contains('_match = DocFieldOutcome.unassessed'));
      expect(fn, isNot(contains('DocFieldOutcome.mismatch;')));
    });

    test('14 입력이 바뀌면 이전 판정을 버린다', () {
      final sheet = _codeOf(_src(_sheetPath));
      final fn = _flat(_sliceOf(sheet, 'onChanged: (v) {', '},'));
      expect(fn, contains('setState(() => _match = DocFieldOutcome.unassessed);'));
    });
  });

  group('INV-4 — 추출값은 남지 않는다 (§55)', () {
    test('15 rawText는 릴리스에서 비어 있다', () {
      expect(ocr, contains("'rawText': kDebugMode ? rawText : ''"));
    });

    test('16 로그에 번호를 담지 않는다', () {
      final logs = RegExp(r'debugPrint\([^)]*\)').allMatches(ocr);
      for (final m in logs) {
        final t = m.group(0)!;
        expect(t.contains('expectedResidentNumber'), isFalse, reason: t);
        expect(t.contains('extractedResidentNumber'), isFalse, reason: t);
        expect(t.contains('cleanedExpectedRN'), isFalse, reason: t);
        expect(t.contains('rawText}'), isFalse, reason: t);
      }
    });

    test('17 서버로 가는 것은 판정 어휘뿐이다', () {
      final sc = _flat(_sliceOf(_src(_pickPath),
          'Map<String, dynamic> get selfCheck =>', '};'));
      expect(sc, contains("'identifier': identifierOutcome.wire"));
      expect(sc, isNot(contains('extractedResidentNumber')));
      // 등록 payload도 같다.
      final svc = _codeOf(_src('lib/services/tax_identity_service.dart'));
      final submit = _flat(_sliceOf(svc, 'await _fn.httpsCallable(name).call({', '});'));
      expect(submit, contains("'documentMatch': documentMatch.wire"));
      expect(submit, contains("'rawIdentifier': rawIdentifier"));
    });

    test('18 대조용 임시 파일을 지운다', () {
      final sheet = _codeOf(_src(_sheetPath));
      final fn = _sliceOf(sheet,
          'Future<void> _compareWithIdCard() async {', '\n  }');
      expect(fn, contains('await image?.delete();'));
    });
  });

  group('INV-5 — 되돌려 보여주지 않는다 (§27·§29)', () {
    final sheet = _codeOf(_src(_sheetPath));

    test('19 제출 후 입력값을 지운다', () {
      final fn = _flat(_sliceOf(sheet, 'Future<void> _submit() async {', '\n  }'));
      expect(fn, contains('_frontCtrl.clear();'));
      expect(fn, contains('_backCtrl.clear();'));
    });

    test('20 복사·붙여넣기 메뉴를 열지 않는다', () {
      expect(sheet, contains('enableInteractiveSelection: false'));
      expect(sheet, isNot(contains('Clipboard.setData')));
    });

    test('21 등록 후 번호를 표시하지 않는다고 말한다', () {
      expect(sheet, contains("Text('등록된 번호는 표시되지 않습니다'"));
      expect(sheet, contains('등록한 번호는 화면에 다시 표시되지 않습니다'));
    });

    test('22 뒷자리는 가린 채 입력한다', () {
      final fld = _flat(_sliceOf(sheet, "_digitField(_backCtrl, 7, '뒤 7자리'", ')'));
      expect(fld, contains('obscure: true'));
    });

    test('23 금지 표현이 없다 (§37)', () {
      for (final banned in [
        '주민등록번호 인증 완료', '신분증 인증 완료', '정부 인증',
        '취업자격 인증', '실명인증',
      ]) {
        expect(sheet, isNot(contains(banned)), reason: banned);
        expect(ocr, isNot(contains(banned)), reason: banned);
      }
    });
  });
}
