// test/unit/identity_identifier_test.dart
//
// [PII-DOC-R1.2] 기대 식별번호 생성 — 내국인/외국인 성별코드.
//
//   두 모집단이 정반대로 깨져 있었다:
//     V3 외국인    기준이 없어 비교를 건너뛰고 기본값 true가 올라감
//     레거시 외국인 내국인 코드(1~4)를 찍어 등록증(5~8)과 항상 불일치
//
//   규칙을 한 곳에 모았으니, 그 한 곳을 여기서 고정한다.

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/utils/identity_identifier.dart';

ExpectedIdentifier of({
  DateTime? birth,
  String? gender,
  required bool foreign,
}) =>
    expectedIdentifierFrom(
        birthDate: birth, gender: gender, isForeign: foreign);

void main() {
  group('N — 내국인 (regression)', () {
    test('N1 1900년대생 남/여 → 1 / 2', () {
      expect(of(birth: DateTime(1990, 1, 1), gender: '남성', foreign: false).prefix,
          '900101-1');
      expect(of(birth: DateTime(1990, 1, 1), gender: '여성', foreign: false).prefix,
          '900101-2');
    });

    test('N2 2000년대생 남/여 → 3 / 4', () {
      expect(of(birth: DateTime(2001, 12, 31), gender: '남성', foreign: false).prefix,
          '011231-3');
      expect(of(birth: DateTime(2001, 12, 31), gender: '여성', foreign: false).prefix,
          '011231-4');
    });

    test('N3 기존 포맷 유지 — YYMMDD-G, 0 패딩', () {
      expect(of(birth: DateTime(2005, 3, 7), gender: '남성', foreign: false).prefix,
          '050307-3');
    });
  });

  group('F — 외국인', () {
    test('F5 1900년대생 남/여 → 5 / 6', () {
      expect(of(birth: DateTime(1990, 1, 1), gender: '남성', foreign: true).prefix,
          '900101-5');
      expect(of(birth: DateTime(1990, 1, 1), gender: '여성', foreign: true).prefix,
          '900101-6');
    });

    test('F6 2000년대생 남/여 → 7 / 8', () {
      expect(of(birth: DateTime(2001, 12, 31), gender: '남성', foreign: true).prefix,
          '011231-7');
      expect(of(birth: DateTime(2001, 12, 31), gender: '여성', foreign: true).prefix,
          '011231-8');
    });

    test('외국인에게 내국인 코드(1~4)를 절대 만들지 않는다', () {
      for (final b in [DateTime(1985, 6, 15), DateTime(2003, 2, 2)]) {
        for (final g in ['남성', '여성']) {
          final code = of(birth: b, gender: g, foreign: true).prefix!.split('-')[1];
          expect(int.parse(code), inInclusiveRange(5, 8),
              reason: '$b/$g → $code — 등록증에는 5~8이 적혀 있다');
        }
      }
    });

    test('같은 사람의 내국인 코드 + 4 = 외국인 코드', () {
      for (final b in [DateTime(1970, 1, 1), DateTime(2010, 9, 9)]) {
        for (final g in ['남성', '여성']) {
          final n = int.parse(of(birth: b, gender: g, foreign: false).prefix!.split('-')[1]);
          final f = int.parse(of(birth: b, gender: g, foreign: true).prefix!.split('-')[1]);
          expect(f, n + 4);
        }
      }
    });
  });

  group('UNASSESSED — 기준이 없으면 만들어내지 않는다', () {
    test('birthDate 없음 → 비교 불가', () {
      final e = of(birth: null, gender: '남성', foreign: true);
      expect(e.prefix, isNull);
      expect(e.assessable, isFalse);
    });

    test('gender 없음 → 비교 불가 (V3 외국인의 실제 상태였다)', () {
      final e = of(birth: DateTime(1990, 1, 1), gender: null, foreign: true);
      expect(e.prefix, isNull);
      expect(e.assessable, isFalse);
    });

    test('gender 빈 문자열도 기준이 아니다', () {
      expect(of(birth: DateTime(1990, 1, 1), gender: '', foreign: true).assessable,
          isFalse);
    });

    test('기준이 없을 때 임의 기본값을 만들지 않는다', () {
      // 예전에는 여기서 화면이 null을 받고, OCR helper가 그 null을
      // "검사 안 함 → 통과"로 바꿨다.
      expect(of(birth: null, gender: null, foreign: false).prefix, isNull);
      expect(of(birth: null, gender: null, foreign: true).prefix, isNull);
    });
  });

  group('wire 어휘', () {
    test('서버와 같은 문자열을 쓴다', () {
      expect(DocFieldOutcome.matched.wire, 'MATCHED');
      expect(DocFieldOutcome.mismatch.wire, 'MISMATCH');
      expect(DocFieldOutcome.unreadable.wire, 'UNREADABLE');
      expect(DocFieldOutcome.unassessed.wire, 'UNASSESSED');
    });

    test('네 값이 서로 다르다 — 하나로 뭉뚱그려지지 않는다', () {
      final all = DocFieldOutcome.values.map((e) => e.wire).toSet();
      expect(all.length, DocFieldOutcome.values.length);
    });
  });
}
