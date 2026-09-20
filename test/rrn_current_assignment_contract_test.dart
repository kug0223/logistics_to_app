// [PII-B4-R1.4.1] 지금 유효한 주민등록번호를 거부하지 않는다
//
// 이 파일이 고정하는 것:
//
//   INV-1  구 검증부호는 hard gate가 아니다
//   INV-2  hard gate는 구조와 본인인증 일치까지다
//   INV-3  구 검증부호 결과는 근거로만 남는다
//   INV-4  검증부호를 뺐다고 "검증된 번호"가 되지 않는다
//
// 2020년 10월 부여체계 개편으로 뒤 6자리가 임의번호가 됐다.
// 그러므로 구 검증부호는 현재 유효한 모든 번호에 성립하는 규칙이 아니다.

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

/// 구 규칙 검증부호 — 서버 구현과 같은 식.
int _legacyCheck(String front12) {
  const w = [2, 3, 4, 5, 6, 7, 8, 9, 2, 3, 4, 5];
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    sum += int.parse(front12[i]) * w[i];
  }
  return (11 - (sum % 11)) % 10;
}

void main() {
  final cfRaw = _src(_cfPath);
  final cf = _codeOf(cfRaw);
  final validate = _flat(_codeOf(_sliceOf(cfRaw,
      'async function srvValidateKoreanTaxIdentifierOrThrow(', '\n}')));

  group('INV-1 — 구 검증부호는 더 이상 막지 않는다 (§2·§5)', () {
    test('01 검증 경로에 검증부호 호출이 없다', () {
      expect(validate, isNot(contains('LegacyChecksumOk')),
          reason: '등록 가부를 정하는 자리에 있으면 안 된다');
      // R1.4의 거부 분기가 사라졌다.
      expect(cf, isNot(contains('srvKoreanRrnChecksumOk')));
      expect(cf, isNot(contains(
          '주민등록번호를 다시 확인해주세요. 입력한 번호가 올바르지 않습니다.')));
    });

    test('02 이름이 legacy임을 말한다', () {
      expect(cf, contains('function srvKoreanRrnLegacyChecksumOk('));
    });

    test('03 어떤 throw도 검증부호를 근거로 하지 않는다', () {
      // 함수 정의 바깥에서 검증부호가 조건으로 쓰이지 않는다.
      final uses = 'srvKoreanRrnLegacyChecksumOk('.allMatches(cf).length;
      expect(uses, 3, reason: '정의 1 + register 기록 1 + update 기록 1');
      expect(cf, isNot(contains('if (!srvKoreanRrnLegacyChecksumOk')));
    });
  });

  group('INV-2 — hard gate 범위 (§4)', () {
    test('04 구조 검증이 따로 있다', () {
      expect(validate, contains('srvKoreanRrnStructureError(normalized)'));
      final s = _flat(_codeOf(_sliceOf(cfRaw,
          'function srvKoreanRrnStructureError(', '\n}')));
      // 내국인 성별·세기 코드 1~4.
      expect(s, contains('if (code < 1 || code > 4)'));
      expect(s, contains('mm < 1 || mm > 12 || dd < 1 || dd > 31'));
      // 실재하는 날짜인지까지 본다 — 2월 30일을 통과시키지 않는다.
      expect(s, contains('d.getUTCMonth() + 1 !== mm || d.getUTCDate() !== dd'));
    });

    test('05 본인인증 앞 7자리 대조가 남아 있다', () {
      expect(validate,
          contains('srvKoreanRrnMatchesPassIdentity(normalized, userData)'));
    });

    test('06 길이·숫자 정규화가 앞단에 있다', () {
      expect(validate, contains('srvNormalizeTaxIdentifier('));
      expect(validate, contains('주민등록번호 13자리를 입력해주세요.'));
    });

    test('07 D-C5 — 실재하지 않는 날짜는 구조에서 걸린다', () {
      // 0230 = 2월 30일. 서버 규칙을 그대로 재현해 확인한다.
      bool structureOk(String n) {
        final mm = int.parse(n.substring(2, 4));
        final dd = int.parse(n.substring(4, 6));
        final code = int.parse(n[6]);
        if (code < 1 || code > 4) return false;
        if (mm < 1 || mm > 12 || dd < 1 || dd > 31) return false;
        final year = (code == 3 || code == 4)
            ? 2000 + int.parse(n.substring(0, 2))
            : 1900 + int.parse(n.substring(0, 2));
        final d = DateTime.utc(year, mm, dd);
        return d.month == mm && d.day == dd;
      }

      expect(structureOk('9002301234567'), isFalse, reason: '2월 30일');
      expect(structureOk('9013011234567'), isFalse, reason: '13월');
      expect(structureOk('9001015234567'), isFalse, reason: '외국인 코드 5');
      expect(structureOk('9001011234567'), isTrue);
      expect(structureOk('0002293234567'), isTrue, reason: '2000년은 윤년');
    });
  });

  group('INV-3 — 검증부호는 근거로만 남는다 (§5)', () {
    test('08 등록·수정이 결과를 기록한다', () {
      expect(cf, contains(
          'legacyChecksumOk: srvKoreanRrnLegacyChecksumOk(normalized)'));
      expect('legacyChecksumOk:'.allMatches(cf).length, 2,
          reason: 'register + update');
    });

    test('09 D-C1/D-C2 — 두 형태가 모두 구조 검증을 통과한다', () {
      // 구 규칙과 맞아떨어지는 번호.
      const front = '900101112345';
      final old = '$front${_legacyCheck(front)}';
      // 뒤가 임의번호라 구 규칙과 어긋나는 번호 — 지금은 정상이다.
      final modern = '$front${(_legacyCheck(front) + 1) % 10}';
      expect(old == modern, isFalse);
      // 둘 다 구조는 같다: 같은 앞 7자리.
      expect(old.substring(0, 7), modern.substring(0, 7));
      // 서버는 이 둘을 구분하지 않는다 — 구분하는 코드가 없다.
      expect(cf, isNot(contains('if (!srvKoreanRrnLegacyChecksumOk')));
    });

    test('10 상태 응답에 검증부호를 노출하지 않는다', () {
      final st = _flat(_codeOf(_sliceOf(cfRaw,
          'export const callableGetTaxIdentityStatus',
          'export const callableGetTaxIdentityNumber')));
      expect(st, isNot(contains('legacyChecksumOk')));
    });
  });

  group('INV-4 — 신뢰를 올리지 않는다 (§8)', () {
    test('11 금지 표현이 없다', () {
      for (final banned in [
        '주민등록번호 인증 완료', '정부 인증', '공인 인증',
        '실명인증', '검증 완료',
      ]) {
        expect(cf, isNot(contains(banned)), reason: banned);
      }
    });

    test('12 OCR 판정 승격 규칙은 그대로다 (§7)', () {
      final block = _flat(_codeOf(_sliceOf(cfRaw,
          'function srvHasCurrentTaxDocumentMismatch(', '\n}')));
      // MISMATCH만 막는다.
      expect(block, contains('tax["documentMatchOutcome"] !== DOC_FIELD_MISMATCH'));
      expect(block, isNot(contains('DOC_FIELD_UNREADABLE')));
      expect(block, isNot(contains('DOC_FIELD_UNASSESSED')));
    });
  });
}
