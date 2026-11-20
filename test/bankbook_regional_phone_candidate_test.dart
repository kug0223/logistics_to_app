// [R7-P4.4E.9A.2] 라벨 없는 10·11자리 지역 유선번호가 계좌 후보가 됐다
//
// E9B 진단 준비 중 합성 입력으로 재현한 결함.
//
//   통장 표지의 `계좌관리점  가나다역 02-1234-5678` 은 OCR 에서 라벨과 값이
//   다른 줄로 나뉘기 쉽다. 그 줄엔 계좌 라벨도 비계좌 라벨도 없다.
//   `_looksLikePhone` 은 형태로는 01x 휴대전화·8자리 대표번호·9자리 02 만
//   전화로 봤다. 그래서 10자리 `02-1234-5678` · `031-123-4567` 와
//   11자리 `031-1234-5678` 은 **계좌 후보(usable)** 가 됐다.
//
//   결과 두 가지:
//     · 사용자가 지점 전화번호를 계좌로 입력하면 MATCHED — 문서는 그 값을
//       계좌라고 말하지 않았다(E9A.1 과 같은 계열의 거짓 일치).
//     · 계좌번호를 못 읽은 사진에서 UNREADABLE 이 아니라 MISMATCH.
//
// 지키는 것:
//   · 계좌 라벨이 붙은 숫자는 전화처럼 생겨도 계좌 후보다(라벨 > 형태).
//   · 010 평생계좌(계좌 라벨 동반)는 계좌 후보다.
//   · 14자리 IBK 형 계좌(`0xx-xxxxxx-xx-xxx`)는 앞자리가 지역번호와 같아도 계좌 후보다.
//
// 형태 한계(보고 대상): 라벨 없이 구분자도 없는 10·11자리 지역번호형 숫자는
//   전화와 계좌를 형태로 구별할 수 없다. 이 경우 계좌 후보로 쓰지 않는다 —
//   거짓 MATCHED 대신 UNREADABLE 쪽으로 기운다.
//
// fixture 는 전부 **합성 값**이다.
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/utils/identity_identifier.dart';
import 'package:ALfit/utils/ocr_verification_helper.dart';

const kAcct = '123-456789-01-234';

/// IBK 표지 형태의 합성 레이아웃 — 라벨과 값이 다른 줄.
String layout({bool withAccount = true, String branch = '02-1234-5678'}) => [
      '홍길동',
      '계좌번호',
      if (withAccount) kAcct,
      '예금종류',
      '가나급여통장',
      '계좌관리점',
      '가나다역 $branch',
      '중소기업은행',
    ].join('\n');

DocFieldOutcome acct(String text, String expected) =>
    OcrVerificationHelper.evaluateAccount(
            rawText: text, expectedAccountNumber: expected)
        .outcome;

bool usable(String text, String digits) => OcrVerificationHelper
    .collectAccountCandidates(text)
    .usableAccountCandidates
    .contains(digits.replaceAll(RegExp(r'\D'), ''));

void main() {
  group('RP-FAIL 결함 재현', () {
    for (final branch in ['02-1234-5678', '031-123-4567', '031-1234-5678']) {
      test('RP-1 라벨 없는 지점번호 $branch 를 계좌로 입력해도 MATCHED 가 아니다', () {
        expect(acct(layout(branch: branch), branch),
            isNot(DocFieldOutcome.matched));
      });

      test('RP-2 계좌를 못 읽고 지점번호($branch)만 있으면 UNREADABLE', () {
        expect(acct(layout(withAccount: false, branch: branch), kAcct),
            DocFieldOutcome.unreadable);
      });

      test('RP-3 지점번호 $branch 는 계좌 후보가 아니다', () {
        expect(usable(layout(branch: branch), branch), isFalse);
      });
    }
  });

  group('RP-KEEP 보존', () {
    test('KEEP-1 4구간 계좌는 그대로 MATCHED (지점번호가 함께 있어도)', () {
      expect(acct(layout(), kAcct), DocFieldOutcome.matched);
    });

    test('KEEP-2 010 평생계좌(라벨 동반)는 계좌 후보이고 MATCHED', () {
      const t = '계좌번호\n123-456789-01-234\n[평생계좌] 010-1111-2222';
      expect(usable(t, '010-1111-2222'), isTrue);
      expect(acct(t, '010-1111-2222'), DocFieldOutcome.matched);
    });

    test('KEEP-3 계좌 라벨이 같은 줄에 있으면 지역번호형도 계좌 후보다(라벨 > 형태)', () {
      const t = '계좌번호 031-123-4567';
      expect(usable(t, '031-123-4567'), isTrue);
      expect(acct(t, '031-123-4567'), DocFieldOutcome.matched);
    });

    test('KEEP-4 14자리 IBK 형 계좌는 앞자리가 031 이어도 계좌 후보', () {
      const t = '홍길동\n031-123456-01-011\n중소기업은행';
      expect(usable(t, '031-123456-01-011'), isTrue);
      expect(acct(t, '031-123456-01-011'), DocFieldOutcome.matched);
    });

    test('KEEP-5 라벨 없는 휴대전화는 여전히 비계좌', () {
      expect(usable('담당 010-1234-5678', '010-1234-5678'), isFalse);
    });

    test('KEEP-6 비계좌 라벨이 붙은 유선번호는 여전히 비계좌', () {
      expect(usable('지점 전화 031-123-4567', '031-123-4567'), isFalse);
      expect(usable('TEL 02-1234-5678', '02-1234-5678'), isFalse);
    });

    test('KEEP-7 일반 계좌형(12·13자리)은 영향 없다', () {
      for (final a in ['110-123-456789', '301-1234-5678-91', '1002-456-789012']) {
        expect(usable('홍길동\n$a', a), isTrue, reason: a);
      }
    });
  });

  group('RP-LIMIT 형태 한계 — 구분 불가하면 MATCHED 를 만들지 않는다', () {
    test('LIMIT-1 라벨·구분자 없는 10자리 02 숫자는 계좌 후보로 쓰지 않는다', () {
      expect(usable('가나다역 0212345678', '0212345678'), isFalse);
      expect(acct('가나다역 0212345678', '0212345678'), DocFieldOutcome.unreadable);
    });

    test('LIMIT-2 같은 숫자라도 계좌 라벨이 있으면 계좌다', () {
      expect(acct('계좌번호 0212345678', '0212345678'), DocFieldOutcome.matched);
    });
  });

  test('RP-SAME 진단 함수와 등록 경로가 같은 후보 판정을 쓴다', () {
    final text = layout();
    final d = OcrVerificationHelper.diagnoseBankbookText(text);
    final c = OcrVerificationHelper.collectAccountCandidates(text);
    expect(d.candidates.where((x) => x.usable).map((x) => x.digits).toList(),
        c.usableAccountCandidates);
  });
}
