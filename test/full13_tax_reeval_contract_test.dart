// [FULL13-REEVAL] 세무 등록 때 **현재 업로드 신분증**으로 전체 13자리 대조를 다시 한다
//
// 이 파일이 고정하는 것(앱 쪽 — 서버 판정은 에뮬레이터 실핸들러 시험이 본다):
//
//   INV-1  13자리 기대값 경로가 서버용 후보를 돌려준다 — 판정은 서버가 한다
//   INV-2  앞 7자리만 같으면 일치가 아니다
//   INV-3  올라간 신분증이 있으면 그 사진을 읽고, 근거를 그 버전에 묶는다
//   INV-4  판정하지 못했으면(시간 초과·인식 오류) 근거를 보내지 않는다
//   INV-5  입력이 바뀌거나 제출하면 근거를 버린다

import 'dart:io';

import 'package:ALfit/services/foreign_id_ocr_service.dart';
import 'package:ALfit/utils/document_upload_helper.dart';
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

const _sheetPath = 'lib/screens/common/document_management_screen.dart';
const _svcPath = 'lib/services/tax_identity_service.dart';

// 합성 값 — 실존 여부와 무관한 시험용 구조(1990-01-01 남성).
const _entered = '9001011000001';
const _sameFront7 = '9001011999999';

Map<String, dynamic> _run(String rawText) =>
    OcrVerificationHelper.verifyIdCardForTesting(
      rawText,
      '홍길동',
      expectedResidentNumber: _entered,
    );

void main() {
  group('INV-1·2 — 13자리 기대값 경로', () {
    test('01 같은 13자리 → MATCHED, 서버용 후보에 그 값', () {
      final r = _run('주민등록증\n홍길동\n900101-1000001\n');
      expect(r['identifierOutcome'], DocFieldOutcome.matched);
      expect(r['identifierCandidates'], [_entered]);
    });

    test('02 앞 7자리만 같고 뒤 6자리 다름 → MISMATCH(일치 아님)', () {
      final r = _run('주민등록증\n홍길동\n900101-1999999\n');
      expect(r['identifierOutcome'], DocFieldOutcome.mismatch);
      expect(r['identifierCandidates'], [_sameFront7],
          reason: '서버가 같은 후보로 다시 판정한다 — 앱 판정을 믿지 않는다');
    });

    test('03 번호를 못 읽음 → UNREADABLE, 후보 없음', () {
      final r = _run('주민등록증\n홍길동\n');
      expect(r['identifierOutcome'], DocFieldOutcome.unreadable);
      expect(r['identifierCandidates'], isEmpty);
    });

    test('04 구조가 아닌 13자리(성별코드 9)는 후보가 아니다', () {
      final r = _run('주민등록증\n홍길동\n900101-9000001\n');
      expect(r['identifierOutcome'], DocFieldOutcome.unreadable);
      expect(r['identifierCandidates'], isEmpty);
    });
  });

  group('INV-3 — 현재 업로드 신분증', () {
    final sheet = _codeOf(_src(_sheetPath));
    final cmp = _flat(_sliceOf(sheet,
        'Future<void> _compareWithIdCard() async {', '\n  }'));

    test('05 올라간 신분증이 있으면 새 사진을 고르지 않고 그 파일을 받는다', () {
      expect(cmp, contains('image = uploaded ? await _downloadUploadedIdCard()'));
      final dl = _flat(_sliceOf(sheet,
          'Future<File?> _downloadUploadedIdCard() async {', '\n  }'));
      expect(dl, contains('final path = widget.user.idCardImagePath!;'));
      expect(dl, contains('FirebaseStorage.instance.ref(path)'));
      expect(dl, contains('getTemporaryDirectory()'));
      // [FULL13-REEVAL.2] 쓰기 도중 실패하면 반쯤 쓴 파일을 지운다.
      expect(dl, contains('await file.delete();'));
    });

    test('06 근거는 현재 문서 버전에 묶는다', () {
      expect(cmp, contains('idDocumentVersion: widget.user.idDocumentVersion!'));
      expect(cmp, contains("result['identifierCandidates']"));
    });

    test('07 받은 임시 파일도 지운다', () {
      expect(cmp, contains('await image?.delete();'));
    });

    test('08 제출 때 아직 대조하지 않았으면 먼저 대조한다', () {
      final sub = _flat(_sliceOf(sheet, 'Future<void> _submit() async {', '\n  }'));
      expect(sub, contains('_hasUploadedIdCard && _evidence == null'));
      expect(sub, contains('await _compareWithIdCard();'));
      expect(sub, contains('documentEvidence: evidence'));
    });
  });

  group('INV-4 — 판정 못 함 ≠ 못 읽음', () {
    test('09 시간 초과·오류 결과에는 근거가 없다', () {
      final sheet = _codeOf(_src(_sheetPath));
      final cmp = _flat(_sliceOf(sheet,
          'Future<void> _compareWithIdCard() async {', '\n  }'));
      expect(cmp, contains("final assessed = result.containsKey('identifierOutcome');"));
      expect(cmp, contains('_evidence = (uploaded && assessed)'));
    });

    test('10 근거가 없으면 payload 에 키가 없다', () {
      final svc = _flat(_codeOf(_src(_svcPath)));
      expect(svc, contains(
          "if (documentEvidence != null) 'documentEvidence': documentEvidence.toWire(),"));
    });
  });

  group('INV-6 — 외국인 가입: 직접 입력 · 판정 안 함 ≠ 못 읽음 (FULL13-REEVAL.2)', () {
    final fr = _codeOf(_src('lib/screens/auth/foreign_register_screen.dart'));

    test('13 OCR 번호로 입력 칸을 채우지 않는다', () {
      expect(fr, isNot(contains('_rawForeignIdCtrl.text = result.foreignIdRaw')));
      expect(fr, isNot(contains('_rawForeignIdCtrl.text =')));
    });

    test('14 업로드 판정 세 곳 모두 같은 근거 함수를 쓴다', () {
      expect('_markSelfCheck()'.allMatches(fr).length, 4, reason: '정의 1 + 호출 3');
      expect(fr, isNot(contains("'selfCheck': DocumentPickResult.unassessedSelfCheck()")));
    });

    test('15 수집 OFF → 무판정(후보 전송 없음)', () {
      final m = DocumentPickResult.foreignSignupSelfCheck(
          collectionEnabled: false, ocrAttempted: true, ocrThrew: false,
          ocrForeignIdRaw: '9001015000001');
      expect(m.containsKey('identifierCandidates'), isFalse);
      expect(m['identifier'], 'UNASSESSED');
    });

    test('16 수집 ON + OCR 이 번호를 읽음 → 그 번호를 후보로, 이름은 UNASSESSED', () {
      final m = DocumentPickResult.foreignSignupSelfCheck(
          collectionEnabled: true, ocrAttempted: true, ocrThrew: false,
          ocrForeignIdRaw: '900101-5000001');
      expect(m['identifierCandidates'], ['9001015000001']);
      expect(m['name'], 'UNASSESSED');
      expect(m['identifier'], 'UNASSESSED', reason: '판정은 서버가 한다');
    });

    test('17 OCR 이 돌았지만 번호 없음 → 빈 후보(못 읽음) / 예외 → ocrFailed / 안 돌림 → 키 없음', () {
      final unread = DocumentPickResult.foreignSignupSelfCheck(
          collectionEnabled: true, ocrAttempted: true, ocrThrew: false);
      expect(unread['identifierCandidates'], isEmpty);
      final threw = DocumentPickResult.foreignSignupSelfCheck(
          collectionEnabled: true, ocrAttempted: true, ocrThrew: true);
      expect(threw['ocrFailed'], isTrue);
      expect(threw.containsKey('identifierCandidates'), isFalse);
      final none = DocumentPickResult.foreignSignupSelfCheck(
          collectionEnabled: true, ocrAttempted: false, ocrThrew: false);
      expect(none.containsKey('identifierCandidates'), isFalse);
      expect(none['ocrFailed'], isFalse);
    });

    test('18 국내 업로드: 판독했으면 빈 후보라도 키를 보내고, 판독 안 한 결과(통장 등)는 키가 없다', () {
      const read = DocumentPickResult(path: 'x', identifierCandidates: <String>[]);
      expect(read.selfCheck.containsKey('identifierCandidates'), isTrue);
      const notRead = DocumentPickResult(path: 'x');
      expect(notRead.selfCheck.containsKey('identifierCandidates'), isFalse);
    });
  });

  group('INV-7 — 외국인 이름 직접 입력 ↔ OCR 이름 (FULL13-REEVAL.3)', () {
    ForeignIdOcrResult ocr(String? n, {String src = 'LATIN_REGION'}) => ForeignIdOcrResult(
        legalName: n, legalNameFailed: n == null, legalNameOcrSource: n == null ? 'NONE' : src);
    DocFieldOutcome cmp(String typed, ForeignIdOcrResult? o) =>
        ForeignIdOcrService.compareTypedLegalName(typed, o);

    test('19 대소문자·연속 공백·앞뒤 공백 → 기존 정규화로 같다', () {
      expect(cmp('  nguyen   van an ', ocr('NGUYEN VAN AN')), DocFieldOutcome.matched);
    });
    test('20 기존 발음부호 치환은 그대로(새 규칙 아님)', () {
      expect(cmp('NGUYEN VAN AN', ocr('NGUYỄN VAN AN')), cmp('NGUYEN VAN AN', ocr('NGUYEN VAN AN')),
          reason: '_diacriticMap 에 있으면 같고, 없으면 다르다 — 표를 새로 넓히지 않는다');
    });
    test('21 이름 순서 바꿈·토큰 생략·한 글자 다름 → 일치 아님', () {
      expect(cmp('VAN AN NGUYEN', ocr('NGUYEN VAN AN')), DocFieldOutcome.mismatch);
      expect(cmp('NGUYEN AN', ocr('NGUYEN VAN AN')), DocFieldOutcome.mismatch);
      expect(cmp('NGUYEN VAN AM', ocr('NGUYEN VAN AN')), DocFieldOutcome.mismatch);
      expect(cmp('NGUYENVANAN', ocr('NGUYEN VAN AN')), DocFieldOutcome.mismatch, reason: '공백 제거는 기존 정규화가 아니다');
    });
    test('21b [DOC-RACE.6] 이름 영역의 다른 출처 표기(EXPECTED_LINES·NAME_ANCHOR)도 다르면 MISMATCH', () {
      // 기기 실측(Pixel 5 에뮬레이터, 합성 등록증)에서 실제 출처는 LATIN_REGION_EXPECTED_LINES 였다.
      for (final src in ['LATIN_REGION_EXPECTED_LINES', 'LATIN_REGION_NAME_ANCHOR']) {
        expect(cmp('NGUYEN VAN BINH', ocr('NGUYEN VAN AN', src: src)), DocFieldOutcome.mismatch, reason: src);
        expect(cmp('nguyen van an', ocr('NGUYEN VAN AN', src: src)), DocFieldOutcome.matched, reason: src);
      }
    });
    test('22 못 읽음·낮은 신뢰 OCR 과 다름 → UNREADABLE, 입력 없음 → UNASSESSED', () {
      expect(cmp('NGUYEN VAN AN', ocr(null)), DocFieldOutcome.unreadable);
      expect(cmp('NGUYEN VAN AN', null), DocFieldOutcome.unreadable);
      expect(cmp('NGUYEN VAN AN', ocr('NGUYEN VAM AN', src: 'FULL_OCR')), DocFieldOutcome.unreadable);
      expect(cmp('', ocr('NGUYEN VAN AN')), DocFieldOutcome.unassessed);
    });
    test('23 가입 화면: OCR 이름으로 입력 칸을 채우지 않는다', () {
      final fr = _codeOf(_src('lib/screens/auth/foreign_register_screen.dart'));
      expect(fr, isNot(contains('_legalNameCtrl.text = result.legalName')));
      expect(fr, isNot(contains('_legalNameCtrl.text =')));
    });
  });

  group('INV-5 — 근거 수명', () {
    final sheet = _codeOf(_src(_sheetPath));

    test('11 입력이 바뀌면 근거를 버린다', () {
      final fn = _flat(_sliceOf(sheet, 'onChanged: (v) {', '},'));
      expect(fn, contains('_evidence = null;'));
    });

    test('12 제출 후 근거를 버린다', () {
      final sub = _flat(_sliceOf(sheet, 'Future<void> _submit() async {', '\n  }'));
      expect(sub, contains('_backCtrl.clear(); _evidence = null;'));
    });
  });
}
