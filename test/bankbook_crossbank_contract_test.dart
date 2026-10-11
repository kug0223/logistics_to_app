// [R7-BANKBOOK-VERIFIER-CROSSBANK.1] 금융기관별 통장사본 Verifier — **합성 텍스트**.
//
// ── 이 테스트가 말하는 것과 말하지 않는 것 ──────────────────────────
//   말한다  : 합성 OCR 텍스트를 넣었을 때 판정(MATCHED/MISMATCH/UNREADABLE/
//             UNASSESSED)이 기대와 같은가. 은행 별칭이 **다른 기관을 합치지
//             않는가**. 숫자 오인식(전화·고객센터·날짜·고객번호)을 계좌로
//             보지 않는가.
//   말하지 않는다 : 실제 발급 문서의 레이아웃·실제 OCR 인식률. 그것은
//             DEVICE 단계이며 이 파일의 어떤 셀도 그것을 증명하지 않는다.
//
// ── 구조는 그대로다 ─────────────────────────────────────────────────
//   Verifier(입력값 ↔ 문서 대조) 구조와 MODEL B(HOLDER SUPPORTING-ONLY)를
//   유지한다. 새 예금주 라벨이나 퍼지 매칭을 추가하지 않는다 — 실제 이미지
//   근거가 없는 확장은 오판을 늘릴 뿐이다.
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/utils/identity_identifier.dart';
import 'package:ALfit/utils/ocr_verification_helper.dart';

Map<String, dynamic> _verify(
  String raw, {
  String name = '김근로',
  String? account,
  String? bank,
}) =>
    OcrVerificationHelper.verifyBankbookForTesting(
      raw,
      name,
      expectedAccountNumber: account,
      expectedBankName: bank,
    );

DocFieldOutcome _acc(Map<String, dynamic> r) =>
    r['accountOutcome'] as DocFieldOutcome;
DocFieldOutcome _bank(Map<String, dynamic> r) =>
    r['bankOutcome'] as DocFieldOutcome;
DocFieldOutcome _holder(Map<String, dynamic> r) =>
    r['holderOutcome'] as DocFieldOutcome;

void main() {
  group('§2 은행 별칭 — 다른 기관을 합치지 않는다', () {
    // 같은 기관의 표기 변형은 하나로 모인다.
    const sameInstitution = <String, List<String>>{
      'IBK기업은행': [
        'IBK기업은행', '중소기업은행', '기업은행', 'IBK',
        'Industrial Bank of Korea',
      ],
      'KB국민은행': ['KB국민은행', '국민은행'],
      '하나은행': ['하나은행', 'KEB하나은행'],
      'SC제일은행': ['SC제일은행', '제일은행'],
      '케이뱅크': ['케이뱅크', 'K뱅크'],
      '새마을금고': ['새마을금고', 'MG새마을금고'],
      '우체국': ['우체국', '우체국예금'],
      // 브랜드 변경 — DGB대구은행이 iM뱅크가 됐다. 같은 기관이다.
      '대구은행': ['대구은행', 'DGB대구은행', 'iM뱅크'],
    };
    sameInstitution.forEach((canonical, aliases) {
      for (final a in aliases) {
        test('$a → $canonical', () {
          expect(OcrVerificationHelper.canonicalBankOf('입금은행 $a 예금주'),
              canonical);
        });
      }
    });

    test('bare 농협은 어떤 기관으로도 읽지 않는다 (지역농축협 ≠ NH농협은행)', () {
      // 소스 주석의 결정을 계약으로 고정한다: 단위조합을 은행으로 승격하지 않는다.
      expect(OcrVerificationHelper.canonicalBankOf('○○지역농축협 통장'), isNull);
      expect(OcrVerificationHelper.canonicalBankOf('단위농협 조합원'), isNull);
      expect(OcrVerificationHelper.canonicalBankOf('NH농협은행'), 'NH농협은행');
      expect(OcrVerificationHelper.canonicalBankOf('농협은행'), 'NH농협은행');
    });

    test('[현상 고정] 수협은 bare 별칭이 있어 단위조합도 수협은행으로 읽힌다', () {
      // 농협은 bare `농협` 을 **의도적으로 제외**해 단위조합을 은행으로
      // 승격하지 않는다. 수협에는 같은 보호가 없다(`'수협'` 별칭 존재).
      //
      //   이것을 결함으로 단정하지 않는다 — 은행 축은 성공 판정에 관여하지
      //   않으므로(위 셀) 사용자를 막지도, 통과시키지도 않는다. 다만 두
      //   기관을 같은 규칙으로 다루지 않는다는 **현재 상태**를 고정해 둔다.
      //   바꾸려면 실제 단위수협 발급 문서 근거가 필요하다.
      expect(OcrVerificationHelper.canonicalBankOf('○○수협 조합'), '수협은행');
      expect(OcrVerificationHelper.canonicalBankOf('○○지역농축협'), isNull);
    });

    test('서로 다른 은행이 섞여도 가장 긴 별칭이 이긴다', () {
      // '기업은행'(4) vs '중소기업은행'(6) — 둘 다 IBK라 결론이 같아야 한다.
      expect(OcrVerificationHelper.canonicalBankOf('중소기업은행 기업은행'),
          'IBK기업은행');
    });

    test('안내 문구의 다른 은행 이름이 발급기관을 바꾸지 않는다 — 판정 축에서 제외', () {
      // 통장 뒷면 안내에 타행 이름이 있어도 **은행 축은 성공 판정에 관여하지
      // 않는다**(isDocumentConsistent = 계좌 + 예금주). 그래서 오인식이
      // 사용자를 막지 못한다는 것을 계약으로 고정한다.
      final r = _verify(
        'KB국민은행\n예금주 김근로\n계좌번호 123-456-789012\n'
        '타행 이체 수수료 안내: 우리은행 신한은행',
        account: '123456789012',
        bank: 'KB국민은행',
      );
      expect(r['isDocumentConsistent'], isTrue,
          reason: '계좌·예금주가 맞으면 은행 오인식이 실패를 만들지 않는다');
    });
  });

  group('§2 미등록 기관 — 못 읽는 것이 오판보다 낫다', () {
    // 선택 목록에는 있으나 별칭 사전에 없는 기관들. 은행 축이 UNREADABLE 로
    // 떨어지고, 그것이 실패 사유가 되지 않아야 한다.
    for (final text in ['○○신협 조합', '씨티은행', 'KDB산업은행', 'OO저축은행',
      'KB증권 CMA']) {
      test('$text — 은행은 못 읽되 계좌가 맞으면 통과', () {
        final r = _verify(
          '$text\n예금주 김근로\n계좌번호 110-234-567890',
          account: '110234567890',
          bank: '신협',
        );
        expect(_acc(r), DocFieldOutcome.matched);
        expect(r['isDocumentConsistent'], isTrue,
            reason: '별칭 사전에 없는 기관이라고 사용자를 막지 않는다');
      });
    }
  });

  group('§4 계좌번호 — 다른 숫자를 계좌로 보지 않는다', () {
    test('고객센터 번호는 계좌가 아니다', () {
      final r = _verify(
        '신한은행\n고객센터 1577-8000\n예금주 김근로',
        account: '110234567890',
        bank: '신한은행',
      );
      expect(_acc(r), DocFieldOutcome.unreadable,
          reason: '읽지 못한 것이다 — 다르다고 말하면 사용자가 할 일이 달라진다');
      expect(_acc(r), isNot(DocFieldOutcome.mismatch));
    });

    test('개설일자는 계좌가 아니다', () {
      final r = _verify(
        'KB국민은행\n개설일 2024-03-15\n예금주 김근로',
        account: '110234567890',
      );
      expect(_acc(r), DocFieldOutcome.unreadable);
    });

    test('하이픈·공백 표기 차이는 같은 계좌다', () {
      for (final shown in ['123-456-789012', '123 456 789012', '123456789012']) {
        final r = _verify(
          'IBK기업은행\n계좌번호 $shown\n예금주 김근로',
          account: '123456789012',
          bank: 'IBK기업은행',
        );
        expect(_acc(r), DocFieldOutcome.matched, reason: '표기: $shown');
      }
    });

    test('다른 계좌가 적혀 있으면 불일치다 — 일부 일치로 통과시키지 않는다', () {
      final r = _verify(
        '우리은행\n계좌번호 1002-456-789012\n예금주 김근로',
        account: '1002456789999',
        bank: '우리은행',
      );
      expect(_acc(r), DocFieldOutcome.mismatch);
      expect(r['isDocumentConsistent'], isFalse);
    });

    test('기준이 없으면 비교하지 않았다고 말한다', () {
      final r = _verify('하나은행\n계좌번호 123-456-789012\n예금주 김근로');
      expect(_acc(r), DocFieldOutcome.unassessed,
          reason: '등록된 계좌가 없으면 대조 자체를 못 한 것이다');
      expect(r['isDocumentConsistent'], isFalse);
    });
  });

  group('§4 예금주 — MODEL B HOLDER SUPPORTING-ONLY', () {
    test('라벨 옆 이름이 결론을 소유한다 — 문서 다른 곳의 등장이 뒤집지 못한다', () {
      final r = _verify(
        'KB국민은행\n예금주 이영희\n계좌번호 110-234-567890\n'
        '담당자 김근로 귀하',
        account: '110234567890',
      );
      expect(_holder(r), DocFieldOutcome.mismatch,
          reason: '라벨 근거가 이영희면 김근로가 다른 곳에 있어도 불일치다');
      expect(r['isDocumentConsistent'], isFalse);
    });

    test('예금주를 못 읽은 것은 타인 계좌가 아니다', () {
      final r = _verify(
        '카카오뱅크\n계좌번호 3333-01-1234567',
        account: '3333011234567',
        bank: '카카오뱅크',
      );
      expect(_holder(r), isNot(DocFieldOutcome.mismatch));
      expect(r['isDocumentConsistent'], isTrue,
          reason: '예금주 미인식은 실패 사유가 아니다(supporting-only)');
    });
  });

  group('§4 인터넷은행·상호금융 계좌 형식', () {
    const cases = <String, List<String>>{
      '카카오뱅크': ['3333-01-1234567', '3333011234567'],
      '토스뱅크': ['1000-1234-5678', '100012345678'],
      '케이뱅크': ['100-123-456789', '100123456789'],
      '새마을금고': ['9003-1234-5678-9', '9003123456789'],
      '우체국': ['012345-02-123456', '01234502123456'],
      '수협은행': ['1010-1234-5678', '101012345678'],
    };
    cases.forEach((bank, forms) {
      final digits = forms.last;
      for (final shown in forms) {
        test('$bank $shown', () {
          final r = _verify(
            '$bank\n예금주 김근로\n계좌번호 $shown',
            account: digits,
            bank: bank,
          );
          expect(_acc(r), DocFieldOutcome.matched);
          expect(_bank(r), DocFieldOutcome.matched);
        });
      }
    });
  });

  group('§4 잘린·저해상도 문서 — 읽지 못함으로 떨어진다', () {
    test('계좌번호 일부만 보이면 UNREADABLE', () {
      final r = _verify(
        'IBK기업은행\n예금주 김근로\n계좌번호 123-456-',
        account: '123456789012',
        bank: 'IBK기업은행',
      );
      expect(_acc(r), DocFieldOutcome.unreadable);
    });

    test('빈 텍스트는 아무것도 주장하지 않는다', () {
      final r = _verify('', account: '123456789012', bank: 'KB국민은행');
      expect(_acc(r), DocFieldOutcome.unreadable);
      expect(_bank(r), isNot(DocFieldOutcome.matched));
      expect(r['isDocumentConsistent'], isFalse);
    });
  });
}
