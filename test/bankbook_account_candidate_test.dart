// [R7-P4.4E.9A] 통장사본 계좌번호 판정 — 후보 수집 · 문맥 분류 · expected 대조.
//
// E9 READ 에서 재현된 두 결함
//   E9-A  계좌번호 정규식이 **세 그룹 고정**이라 구분자가 셋인 계좌번호
//         (`010-123456-01-017`)는 어떤 패턴에도 맞지 않았다. 그런데
//         `계좌번호` 라벨이 있는 줄에서는 greedy 패턴이 `010-123456-01` 까지
//         잘라 읽고 "읽었다" 를 세워, 결과가 UNREADABLE 이 아니라 **MISMATCH**
//         였다 → 정상 서류·정상 입력으로 "일치하지 않습니다 / 인식: 확인 불가".
//         (라벨이 **있을 때 더 나빴다** — 없으면 UNREADABLE.)
//   E9-B  휴대전화 `010-1234-5678` 도 그 패턴에 맞아 같은 플래그를 세웠다.
//         계좌를 못 읽었는데 MISMATCH → `OCR 실패 != MISMATCH` 위반.
//
// 이 파일이 고정하는 계약
//   · 계좌를 **명확히 읽고** expected 와 같으면 MATCHED
//   · 계좌를 **명확히 읽고** 다르면 MISMATCH
//   · 쓸 수 있는 계좌 후보를 하나도 못 모으면 **UNREADABLE**(서버에서
//     OCR_UNCERTAIN) — 전화번호·날짜를 봤다는 사실이 MISMATCH 근거가 되지 않는다
//   · expected 와 숫자가 정확히 같은 후보는 **가장 강한 증거**다
//   · OCR 글자를 고쳐 쓰지 않는다(O→0 복원 금지) — 확신 없으면 못 읽은 것
//
// fixture 는 전부 **합성 레이아웃**이다. 실제 사용자 통장 원본은 repo 에 넣지
// 않는다(실기기 검증 증거로만 쓴다). 계좌번호도 실재하지 않는 조합이다.
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/utils/identity_identifier.dart';
import 'package:ALfit/utils/ocr_verification_helper.dart';

/// 합성 계좌번호(실재하지 않는 조합).
const kAcct4Seg = '010-123456-01-017';
const kAcct3Seg = '110-1234-567890';
const kHolder = '홍길동';

DocFieldOutcome _acct(String raw, String expected) =>
    OcrVerificationHelper.evaluateAccount(
      rawText: raw,
      expectedAccountNumber: expected,
    ).outcome;

Map<String, dynamic> _verify(
  String raw, {
  String expectedName = kHolder,
  String? expectedAccountNumber,
  String? expectedBankName,
}) =>
    OcrVerificationHelper.verifyBankbookForTesting(
      raw,
      expectedName,
      expectedAccountNumber: expectedAccountNumber,
      expectedBankName: expectedBankName,
    );

void main() {
  // ══════════════════════════════════════════════════════════════
  // P1 — segment 개수에 고정되지 않는다
  // ══════════════════════════════════════════════════════════════
  group('BAC-1x segment 형태', () {
    const forms = <String, String>{
      '3-seg 짧은뒤': '123-456789-01',
      '3-seg 정상': '110-1234-567890',
      '3-seg 4+6+6': '1100-123456-123456',
      '4-seg': '010-123456-01-017',
      '4-seg 공백': '010 123456 01 017',
      '구분자 없음': '01012345601017',
      '5-seg stress': '010-12-3456-01-017',
    };

    for (final e in forms.entries) {
      test('BAC-10 ${e.key} — 라벨 있음 → MATCHED', () {
        expect(
          _acct('IBK기업은행\n계좌번호 ${e.value}\n예금주 $kHolder', e.value),
          DocFieldOutcome.matched,
          reason: '${e.key} 를 읽지 못하면 정상 사용자가 막힌다',
        );
      });

      test('BAC-11 ${e.key} — 라벨 없음 → MATCHED', () {
        // 라벨이 있을 때 더 나빠지던 것이 E9-A 의 핵심 증상이었다.
        expect(
          _acct('IBK기업은행\n${e.value}\n$kHolder', e.value),
          DocFieldOutcome.matched,
        );
      });
    }

    test('BAC-12 구분자 표기가 달라도 digits 로 비교한다', () {
      // 입력은 하이픈, 서류는 공백 — normalization 후 같다.
      expect(
        _acct('계좌번호 010 123456 01 017', '010-123456-01-017'),
        DocFieldOutcome.matched,
      );
      expect(
        _acct('계좌번호 01012345601017', '010-123456-01-017'),
        DocFieldOutcome.matched,
      );
    });
  });

  // ══════════════════════════════════════════════════════════════
  // P4 — 못 읽은 것을 다르다고 말하지 않는다 (E9-B)
  // ══════════════════════════════════════════════════════════════
  group('BAC-2x UNREADABLE vs MISMATCH', () {
    test('BAC-20 휴대전화만 있음 → UNREADABLE', () {
      expect(
        _acct('IBK기업은행\n연락처 010-1234-5678', kAcct4Seg),
        DocFieldOutcome.unreadable,
        reason: '전화번호를 봤다는 사실은 계좌번호를 읽었다는 뜻이 아니다',
      );
    });

    test('BAC-21 지역전화만 있음 → UNREADABLE', () {
      for (final tel in [
        '대표전화 02-1234-5678',
        '지점 전화 031-123-4567',
        'TEL 051-222-3333',
      ]) {
        expect(_acct('IBK기업은행\n$tel', kAcct4Seg),
            DocFieldOutcome.unreadable,
            reason: '$tel → 전화 문맥');
      }
    });

    test('BAC-22 고객센터 대표번호만 있음 → UNREADABLE', () {
      expect(
        _acct('IBK기업은행\n고객센터 1588-2588\n인터넷뱅킹 안내', kAcct4Seg),
        DocFieldOutcome.unreadable,
        reason: '통장 표지에는 계좌번호가 없는 경우가 많다',
      );
    });

    test('BAC-23 날짜만 있음 → UNREADABLE', () {
      for (final d in ['개설일 2026-10-01', '발행 2026.10.01', '2026/10/01']) {
        expect(_acct('IBK기업은행\n$d', kAcct4Seg),
            DocFieldOutcome.unreadable, reason: d);
      }
    });

    test('BAC-24 아무 숫자열도 없음 → UNREADABLE', () {
      expect(_acct('IBK기업은행', kAcct4Seg), DocFieldOutcome.unreadable);
    });

    test('BAC-25 명백히 다른 계좌 → MISMATCH', () {
      expect(
        _acct('계좌번호 110-9999-888888', kAcct3Seg),
        DocFieldOutcome.mismatch,
        reason: '읽었고 다르다 — 근거 있는 불일치다',
      );
    });

    test('BAC-26 비교 기준이 없으면 UNASSESSED', () {
      expect(_acct('계좌번호 110-1234-567890', ''),
          DocFieldOutcome.unassessed);
      expect(
        OcrVerificationHelper.evaluateAccount(
          rawText: '계좌번호 110-1234-567890',
          expectedAccountNumber: null,
        ).outcome,
        DocFieldOutcome.unassessed,
      );
    });
  });

  // ══════════════════════════════════════════════════════════════
  // P2·P3 — expected exact match 가 가장 강하다
  // ══════════════════════════════════════════════════════════════
  group('BAC-3x 후보 우선순위', () {
    test('BAC-30 고객센터 번호가 먼저 나와도 실제 계좌를 고른다', () {
      final raw = 'IBK기업은행\n고객센터 1588-2588\n'
          '계좌번호 $kAcct4Seg\n예금주 $kHolder';
      expect(_acct(raw, kAcct4Seg), DocFieldOutcome.matched);
    });

    test('BAC-31 날짜 + 고객번호 + 계좌번호 → 계좌번호', () {
      final raw = 'IBK기업은행\n개설일 2026-10-01\n'
          '고객센터 1588-2588\n계좌번호 $kAcct4Seg';
      expect(_acct(raw, kAcct4Seg), DocFieldOutcome.matched);
    });

    test('BAC-32 여러 숫자 중 expected 와 정확히 같은 후보가 이긴다', () {
      final raw = 'IBK기업은행\n평생계좌 010-999999-01-017\n'
          '계좌번호 $kAcct4Seg\n고객센터 1566-2566';
      expect(_acct(raw, kAcct4Seg), DocFieldOutcome.matched);
    });

    test('BAC-33 전화 문맥이어도 expected 와 숫자가 같으면 그 계좌다', () {
      // 입력값과 숫자가 똑같다면 형태 추정보다 입력값이 강하다.
      expect(
        _acct('IBK기업은행\n문의 010-1234-5678', '010-1234-5678'),
        DocFieldOutcome.matched,
      );
    });

    test('BAC-34 계좌 라벨이 있으면 전화 형태 추정을 이긴다', () {
      // `010` 접두 단독으로 전화라고 정하지 않는다.
      final probe = OcrVerificationHelper.collectAccountCandidates(
          '계좌번호 010-1234-5678');
      expect(probe.usable, contains('01012345678'),
          reason: '계좌 라벨이 붙은 숫자를 전화로 버리지 않는다');
    });

    test('BAC-35 라벨 없는 불확실 숫자는 MISMATCH 로 부풀리지 않는다', () {
      // 라벨 없는 11자리 `010…` 은 전화로 분류되어 후보에서 빠진다
      // → 계좌 후보 0건 → UNREADABLE.
      expect(
        _acct('IBK기업은행\n010-1234-5678', kAcct4Seg),
        DocFieldOutcome.unreadable,
      );
    });
  });

  // ══════════════════════════════════════════════════════════════
  // P1 — fuzzy 복원 금지
  // ══════════════════════════════════════════════════════════════
  group('BAC-4x 글자를 고쳐 쓰지 않는다', () {
    test('BAC-40 O/I/B 오인식을 숫자로 복원하지 않는다', () {
      // `O10-123456-O1-017` 을 `010-…-01-…` 로 되살리지 않는다.
      expect(
        _acct('계좌번호 O10-123456-O1-017', kAcct4Seg),
        isNot(DocFieldOutcome.matched),
        reason: '확신 없으면 읽지 못한 것이다 — 숫자를 만들어내지 않는다',
      );
    });
  });

  // ══════════════════════════════════════════════════════════════
  // P5 — 은행 alias canonicalization (supporting-only)
  // ══════════════════════════════════════════════════════════════
  group('BAC-5x 은행 alias', () {
    for (final alias in [
      'IBK기업은행',
      '기업은행',
      '중소기업은행',
      'IBK',
      'IBK Industrial Bank of Korea',
    ]) {
      test('BAC-50 $alias → IBK기업은행', () {
        expect(OcrVerificationHelper.canonicalBankOf(alias), 'IBK기업은행');
      });
    }

    test('BAC-51 긴 alias 가 짧은 것을 가로채지 않는다', () {
      expect(OcrVerificationHelper.canonicalBankOf('중소기업은행'), 'IBK기업은행');
      expect(OcrVerificationHelper.canonicalBankOf('KB국민은행'), 'KB국민은행');
      expect(OcrVerificationHelper.canonicalBankOf('NH농협은행'), 'NH농협은행');
    });

    test('BAC-52 중소기업은행 서류 + IBK기업은행 선택 → bank MISMATCH 아님', () {
      final r = _verify(
        '중소기업은행\n계좌번호 $kAcct4Seg\n예금주 $kHolder',
        expectedAccountNumber: kAcct4Seg,
        expectedBankName: 'IBK기업은행',
      );
      expect(r['bankOutcome'], DocFieldOutcome.matched);
    });

    test('BAC-53 은행은 성공 조건이 아니다 (supporting-only)', () {
      // 은행을 못 읽어도 계좌·예금주가 맞으면 일치다.
      final r = _verify(
        '계좌번호 $kAcct4Seg\n예금주 $kHolder',
        expectedAccountNumber: kAcct4Seg,
        expectedBankName: 'IBK기업은행',
      );
      expect(r['bankOutcome'], isNot(DocFieldOutcome.matched));
      expect(r['isDocumentConsistent'], isTrue,
          reason: '은행명 인식은 계좌 소유 확인이 아니다');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 종합 판정 · holder 회귀 · invariant
  // ══════════════════════════════════════════════════════════════
  group('BAC-6x 종합 판정', () {
    test('BAC-60 정상 통장(4-seg) → isDocumentConsistent', () {
      final r = _verify(
        'IBK기업은행\n계좌번호 $kAcct4Seg\n예금주 $kHolder',
        expectedAccountNumber: kAcct4Seg,
        expectedBankName: 'IBK기업은행',
      );
      expect(r['accountOutcome'], DocFieldOutcome.matched);
      expect(r['holderOutcome'], DocFieldOutcome.matched);
      expect(r['isDocumentConsistent'], isTrue,
          reason: 'E9-A 이전에는 이 정상 서류가 MISMATCH 였다');
    });

    test('BAC-61 holder UNREADABLE 은 실패 사유가 아니다', () {
      final r = _verify(
        'IBK기업은행\n계좌번호 $kAcct4Seg',
        expectedAccountNumber: kAcct4Seg,
        expectedBankName: 'IBK기업은행',
      );
      expect(r['holderOutcome'], DocFieldOutcome.unreadable);
      expect(r['isDocumentConsistent'], isTrue,
          reason: '예금주를 못 읽은 것을 불일치로 부풀리지 않는다');
    });

    test('BAC-62 holder MISMATCH 는 veto 다', () {
      final r = _verify(
        'IBK기업은행\n계좌번호 $kAcct4Seg\n예금주 김영희',
        expectedAccountNumber: kAcct4Seg,
        expectedBankName: 'IBK기업은행',
      );
      expect(r['holderOutcome'], DocFieldOutcome.mismatch);
      expect(r['isDocumentConsistent'], isFalse);
    });

    test('BAC-63 account UNREADABLE 은 자동 성공이 아니다', () {
      final r = _verify(
        'IBK기업은행\n고객센터 1588-2588\n예금주 $kHolder',
        expectedAccountNumber: kAcct4Seg,
        expectedBankName: 'IBK기업은행',
      );
      expect(r['accountOutcome'], DocFieldOutcome.unreadable);
      expect(r['isDocumentConsistent'], isFalse);
    });

    test('BAC-64 confidence 는 판정에 영향이 없다', () {
      // 계좌 UNREADABLE + 예금주·은행 MATCHED → confidence 2/3 이지만 실패다.
      final r = _verify(
        'IBK기업은행\n고객센터 1588-2588\n예금주 $kHolder',
        expectedAccountNumber: kAcct4Seg,
        expectedBankName: 'IBK기업은행',
      );
      expect((r['confidence'] as double), greaterThan(0.6));
      expect(r['isDocumentConsistent'], isFalse,
          reason: 'confidence 가 business truth 를 정하지 않는다');
    });
  });
}
