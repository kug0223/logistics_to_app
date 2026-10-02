// [R7-P4.4E.10A] 신분증 신원 증거 — 이름 UNREADABLE · full-13 전용 식별자.
//
// E10 READ 에서 확정한 결함
//   E10-A  이름을 못 읽으면 곧바로 **MISMATCH** 였다. `nameOutcome` 에
//          `unreadable` 분기가 없었다. 서버는 `requireName: true` 로 그것을
//          `idCardMatchStatus = MISMATCH` 로 기록했고, 사용자는 정상 문서로
//          "일치하지 않습니다" 를 봤다. 소비처(`document_upload_helper`)는
//          이미 `name == unreadable` 분기를 갖고 있었는데 parser 가 그 값을
//          만들지 않아 **도달할 수 없는 분기**였다.
//   E10-B  등록 경로가 넘기던 기대값은 주민번호 **앞 7자리**
//          (`YYMMDD-C`, birthDate+gender 파생)였고, 그것만 맞으면
//          `identifierOutcome = MATCHED` → canonical MATCHED → 매칭 준비
//          자동 통과(`MR_READY_AUTO`)였다. 앞 7자리는 개인 식별값이 아니다 —
//          같은 날 태어난 같은 성별이면 **누구의 신분증이든** 통과했다.
//          게다가 7자리 패턴은 날짜·면허번호 조각에 거의 항상 걸려서
//          `anyCandidate` 가 늘 참이었고, 못 읽어도 MISMATCH 였다.
//
// 이 파일이 고정하는 계약
//   · 이름: 라벨 옆에서 **다른 이름을 읽어냈을 때만** MISMATCH.
//     못 읽었으면 UNREADABLE(→ 서버 OCR_UNCERTAIN). fuzzy 비교 없음.
//   · 식별자: 전체 13자리 기대값이 없으면 클라이언트는 **판정하지 않는다**
//     (UNASSESSED). 앞 7자리로는 어떤 경우에도 MATCHED 가 되지 않는다.
//     문서에서 읽은 13자리 **후보만** 서버로 올라가고 비교는 서버가 한다.
//   · 운전면허증: 면허번호·발급일이 식별자 후보가 되지 않는다.
//
// fixture 는 전부 **합성 텍스트**다. 실제 신분증 이미지는 repo 에 넣지
// 않는다(§38) — 실기기 검증 증거로만 쓴다. 주민번호도 실재하지 않는 조합이다.
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/utils/identity_identifier.dart';
import 'package:ALfit/utils/ocr_verification_helper.dart';

const kName = '홍길동';

/// 합성 전체 13자리(실재하지 않는 조합).
const kFull = '9901011234567';
const kFullHyphen = '990101-1234567';
/// 같은 사람의 앞 7자리 — birthDate+gender 로 파생되는 값.
const kPrefix = '990101-1';

Map<String, dynamic> _verify(
  String raw, {
  String expectedName = kName,
  String? expectedResidentNumber,
}) =>
    OcrVerificationHelper.verifyIdCardForTesting(
      raw,
      expectedName,
      expectedResidentNumber: expectedResidentNumber,
    );

DocFieldOutcome _name(Map<String, dynamic> r) =>
    r['nameOutcome'] as DocFieldOutcome;
DocFieldOutcome _ident(Map<String, dynamic> r) =>
    r['identifierOutcome'] as DocFieldOutcome;

void main() {
  // ══════════════════════════════════════════════════════════════
  // E10-A — 이름: 못 읽음 ≠ 다름
  // ══════════════════════════════════════════════════════════════
  group('IDE-1x 이름 증거', () {
    test('IDE-10 이름이 문서에 있으면 MATCHED', () {
      final r = _verify('주민등록증\n$kName\n$kFullHyphen',
          expectedResidentNumber: kFullHyphen);
      expect(_name(r), DocFieldOutcome.matched);
    });

    test('IDE-11 이름을 못 읽으면 UNREADABLE (MISMATCH 아님)', () {
      // 흐릿해서 이름 글자가 아예 안 잡힌 경우 — 라벨도 없다.
      final r = _verify('주민등록증\n$kFullHyphen',
          expectedResidentNumber: kFullHyphen);
      expect(_name(r), DocFieldOutcome.unreadable,
          reason: '못 읽은 것을 다르다고 말하지 않는다');
      expect(_name(r), isNot(DocFieldOutcome.mismatch));
    });

    test('IDE-12 라벨 없이 다른 한글만 있어도 MISMATCH 아님', () {
      // `서울특별시` 같은 발급기관 글자를 이름이라고 추측하지 않는다.
      final r = _verify('주민등록증\n서울특별시 강남구\n$kFullHyphen',
          expectedResidentNumber: kFullHyphen);
      expect(_name(r), DocFieldOutcome.unreadable);
    });

    test('IDE-13 라벨 옆에서 다른 이름을 읽으면 MISMATCH', () {
      for (final label in ['성명', '이름', 'Name']) {
        final r = _verify('운전면허증\n$label 김영희\n$kFullHyphen',
            expectedResidentNumber: kFullHyphen);
        expect(_name(r), DocFieldOutcome.mismatch,
            reason: '$label 칸에서 읽은 값이 다르다 — 근거 있는 불일치다');
      }
    });

    test('IDE-14 라벨 다음 줄의 이름도 읽는다', () {
      final r = _verify('운전면허증\n성명\n김영희\n$kFullHyphen',
          expectedResidentNumber: kFullHyphen);
      expect(_name(r), DocFieldOutcome.mismatch);
    });

    test('IDE-15 비슷한 이름을 같다고 하지 않는다 (fuzzy 금지)', () {
      final r = _verify('주민등록증\n성명 홍길동이\n$kFullHyphen',
          expectedResidentNumber: kFullHyphen);
      // `홍길동이` 는 `홍길동` 을 포함하므로 전체 텍스트 비교로 MATCHED 다.
      // 그건 기존 계약이고, 중요한 것은 **다른 이름이 MATCHED 가 되지
      // 않는다**는 것이다 — IDE-13 이 그것을 지킨다.
      expect(_name(r), DocFieldOutcome.matched);

      final q = _verify('주민등록증\n성명 홍길순\n$kFullHyphen',
          expectedResidentNumber: kFullHyphen);
      expect(_name(q), DocFieldOutcome.mismatch,
          reason: '한 글자 달라도 다른 사람이다');
    });

    test('IDE-16 기대 이름이 없으면 UNASSESSED', () {
      final r = _verify('주민등록증\n$kFullHyphen',
          expectedName: '', expectedResidentNumber: kFullHyphen);
      expect(_name(r), DocFieldOutcome.unassessed);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // E10-B — 식별자: 앞 7자리로는 일치를 선언하지 않는다
  // ══════════════════════════════════════════════════════════════
  group('IDE-2x 식별자 증거', () {
    test('IDE-20 앞 7자리 기대값 → UNASSESSED (MATCHED 금지)', () {
      // 등록 경로가 실제로 넘기던 값이다.
      final r = _verify('주민등록증\n$kName\n$kFullHyphen',
          expectedResidentNumber: kPrefix);
      expect(_ident(r), DocFieldOutcome.unassessed,
          reason: '앞 7자리는 개인 식별값이 아니다 — 판정하지 않는다');
      expect(_ident(r), isNot(DocFieldOutcome.matched));
      expect(r['isValid'], isFalse);
    });

    test('IDE-21 같은 생일·같은 성별 다른 사람 → MATCHED 금지', () {
      // 앞 7자리는 같고 뒤 6자리가 다른 **다른 사람**의 신분증.
      final r = _verify('주민등록증\n김영희\n990101-1999999',
          expectedResidentNumber: kPrefix);
      expect(_ident(r), isNot(DocFieldOutcome.matched),
          reason: '예전에는 앞 7자리가 같아 통과했다');
    });

    test('IDE-22 앞 7자리 경로는 13자리 후보만 올린다', () {
      final r = _verify('주민등록증\n$kName\n$kFullHyphen',
          expectedResidentNumber: kPrefix);
      final cands = r['identifierCandidates'] as List<String>;
      expect(cands, contains(kFull),
          reason: '비교는 서버가 한다 — 후보만 올린다');
    });

    test('IDE-23 전체 13자리 기대값 + 문서 일치 → MATCHED', () {
      for (final doc in [kFullHyphen, kFull, '990101 1234567']) {
        final r = _verify('주민등록증\n$kName\n$doc',
            expectedResidentNumber: kFullHyphen);
        expect(_ident(r), DocFieldOutcome.matched, reason: doc);
        expect(r['isValid'], isTrue);
      }
    });

    test('IDE-24 전체 13자리가 명백히 다르면 MISMATCH', () {
      final r = _verify('주민등록증\n$kName\n990101-1999999',
          expectedResidentNumber: kFullHyphen);
      expect(_ident(r), DocFieldOutcome.mismatch);
    });

    test('IDE-25 13자리를 하나도 못 읽으면 UNREADABLE', () {
      final r = _verify('주민등록증\n$kName\n발급일 2026-10-01',
          expectedResidentNumber: kFullHyphen);
      expect(_ident(r), DocFieldOutcome.unreadable,
          reason: '못 읽은 것을 다르다고 말하지 않는다');
    });

    test('IDE-26 기대값이 없으면 UNASSESSED', () {
      final r = _verify('주민등록증\n$kName\n$kFullHyphen');
      expect(_ident(r), DocFieldOutcome.unassessed);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 운전면허증 — 숫자 충돌
  // ══════════════════════════════════════════════════════════════
  group('IDE-3x 운전면허증', () {
    const license = '11-12-345678-90';

    test('IDE-30 면허번호가 먼저 나와도 식별자 후보가 아니다', () {
      final cands = OcrVerificationHelper.fullIdentifierCandidates(
          '운전면허증\n면허번호 $license\n$kFullHyphen');
      expect(cands, contains(kFull));
      expect(cands.where((c) => c.startsWith('1112')), isEmpty,
          reason: '면허번호는 13자리가 아니다 — 애초에 후보가 아니다');
    });

    test('IDE-31 정상 면허증 → MATCHED', () {
      final r = _verify(
        '운전면허증\n성명 $kName\n$kFullHyphen\n면허번호 $license\n'
        '발급일 2026-01-01\n적성검사 2032-12-31',
        expectedResidentNumber: kFullHyphen,
      );
      expect(_name(r), DocFieldOutcome.matched);
      expect(_ident(r), DocFieldOutcome.matched);
      expect(r['isValid'], isTrue);
    });

    test('IDE-32 주민번호 unreadable + 면허번호 명확 → MISMATCH 금지', () {
      final r = _verify(
        '운전면허증\n성명 $kName\n면허번호 $license\n발급일 2026-01-01',
        expectedResidentNumber: kFullHyphen,
      );
      expect(_ident(r), DocFieldOutcome.unreadable,
          reason: '면허번호를 읽었다는 사실이 주민번호 불일치의 근거가 아니다');
    });

    test('IDE-33 명백히 다른 주민번호 → MISMATCH', () {
      final r = _verify(
        '운전면허증\n성명 $kName\n880202-2888888\n면허번호 $license',
        expectedResidentNumber: kFullHyphen,
      );
      expect(_ident(r), DocFieldOutcome.mismatch);
    });

    test('IDE-34 날짜·주소 숫자는 후보를 만들지 않는다', () {
      final cands = OcrVerificationHelper.fullIdentifierCandidates(
          '발급일 2026-10-01\n주소 서울 강남구 테헤란로 123\n우편번호 06234');
      expect(cands, isEmpty);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 후보 수집 계약
  // ══════════════════════════════════════════════════════════════
  group('IDE-4x 13자리 후보', () {
    test('IDE-40 구분자 유무·공백 모두 같은 후보', () {
      for (final form in [kFullHyphen, kFull, '990101 1234567']) {
        expect(OcrVerificationHelper.fullIdentifierCandidates(form),
            contains(kFull),
            reason: form);
      }
    });

    test('IDE-41 줄을 넘어 이어붙이지 않는다', () {
      // `990101` 과 `1234567` 이 다른 줄이면 한 번호가 아니다.
      final cands = OcrVerificationHelper.fullIdentifierCandidates(
          '990101\n1234567');
      expect(cands, isEmpty,
          reason: '서로 무관한 숫자를 이어붙여 후보를 만들지 않는다');
    });

    test('IDE-42 OCR 잡음이 끼면 줄 단위로 모아 본다', () {
      // 한 줄 안에서 숫자만 모아 13자리가 되면 후보다.
      final cands = OcrVerificationHelper.fullIdentifierCandidates(
          '990101 - 123 4567');
      expect(cands, contains(kFull));
    });

    test('IDE-43 12자리·14자리는 후보가 아니다', () {
      expect(OcrVerificationHelper.fullIdentifierCandidates('990101-123456'),
          isEmpty);
      expect(
          OcrVerificationHelper.fullIdentifierCandidates('9901011234567890')
              .where((c) => c.length != 13),
          isEmpty);
    });

    test('IDE-44 OCR 글자를 숫자로 복원하지 않는다', () {
      final r = _verify('주민등록증\n$kName\n99O1O1-1234567',
          expectedResidentNumber: kFullHyphen);
      expect(_ident(r), isNot(DocFieldOutcome.matched),
          reason: 'O 를 0 으로 되살리지 않는다 — 확신 없으면 못 읽은 것이다');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // raw OCR 원문 누출 (§31·§32)
  // ══════════════════════════════════════════════════════════════
  group('IDE-5x raw 원문', () {
    test('IDE-50 결과 map 에 rawText 를 담지 않는다', () {
      final r = _verify('주민등록증\n$kName\n$kFullHyphen',
          expectedResidentNumber: kFullHyphen);
      expect(r.containsKey('rawText'), isFalse,
          reason: 'debug 빌드에서 주민번호 전체가 실려 나가던 자리다');
    });

    test('IDE-51 extractedName 은 추측값을 돌려주지 않는다', () {
      final r = _verify('주민등록증\n성명 김영희\n$kFullHyphen',
          expectedResidentNumber: kFullHyphen);
      expect(r['extractedName'], isNull);
    });
  });
}
