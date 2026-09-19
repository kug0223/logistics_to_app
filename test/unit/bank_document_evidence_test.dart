// test/unit/bank_document_evidence_test.dart
//
// [PII-DOC-R1.3] 통장사본 근거 truth table.
//
//   이전 규칙은 `isValid = isNameValid`였고 실제 성공/경고는
//   `confidence >= 0.6`이 결정했다. 계좌번호는 분자 하나였을 뿐이다.
//   지금 계좌 불일치가 걸리는 것은 호출부가 은행명을 안 넘겨 분모가 2라서이고,
//   은행명을 넣는 순간 2/3 = 0.67로 다시 통과한다. 구조가 막은 게 아니다.
//
//   여기서 고정하는 것은 **점수가 아니라 항목의 의미가 결과를 정한다**는 것.

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/utils/identity_identifier.dart';
import 'package:ALfit/utils/ocr_verification_helper.dart';

Map<String, dynamic> run(
  String raw,
  String? expectedName, {
  String? account,
  String? bank,
}) =>
    OcrVerificationHelper.verifyBankbookForTesting(
      raw,
      expectedName ?? '',
      expectedAccountNumber: account,
      expectedBankName: bank,
    );

DocFieldOutcome acc(Map<String, dynamic> r) =>
    r['accountOutcome'] as DocFieldOutcome;
DocFieldOutcome holder(Map<String, dynamic> r) =>
    r['holderOutcome'] as DocFieldOutcome;
DocFieldOutcome bank(Map<String, dynamic> r) =>
    r['bankOutcome'] as DocFieldOutcome;
bool ok(Map<String, dynamic> r) => r['isDocumentConsistent'] == true;

const _good = '''
국민은행
예금주 홍길동
계좌번호: 288-910548-10807
''';

void main() {
  group('A — 계좌번호 outcome', () {
    test('A1 expected 있음 + 같음 → MATCHED', () {
      final r = run(_good, '홍길동', account: '288-910548-10807');
      expect(acc(r), DocFieldOutcome.matched);
    });

    test('A1b 하이픈·공백 표기 차이는 제거하고 비교한다', () {
      final r = run('국민은행\n예금주 홍길동\n계좌번호: 288-910548-10807\n',
          '홍길동', account: '288 910548 10807');
      expect(acc(r), DocFieldOutcome.matched);
    });

    test('A2 expected 있음 + 다름 → MISMATCH', () {
      final r = run(_good, '홍길동', account: '111-222222-33333');
      expect(acc(r), DocFieldOutcome.mismatch,
          reason: '계좌번호처럼 보이는 숫자열을 읽었는데 다르다');
    });

    test('A3 expected 있음 + 계좌번호를 못 읽음 → UNREADABLE', () {
      // 계좌번호 패턴이 전혀 없는 문서.
      final r = run('국민은행\n예금주 홍길동\n', '홍길동',
          account: '288-910548-10807');
      expect(acc(r), DocFieldOutcome.unreadable);
      expect(acc(r), isNot(DocFieldOutcome.mismatch),
          reason: '못 읽은 것을 "다르다"고 말할 근거가 없다');
    });

    test('A4 expected 없음 → UNASSESSED (절대 MATCHED 아님)', () {
      final r = run(_good, '홍길동');
      expect(acc(r), DocFieldOutcome.unassessed);
      expect(acc(r), isNot(DocFieldOutcome.matched));
    });

    test('부분 일치를 일치로 보지 않는다', () {
      // 앞자리만 같은 다른 계좌
      final r = run(_good, '홍길동', account: '288-910548-10800');
      expect(acc(r), DocFieldOutcome.mismatch);
    });
  });

  group('H — 예금주 outcome', () {
    test('H1 expected 있음 + 문서에 있음 → MATCHED', () {
      final r = run(_good, '홍길동', account: '288-910548-10807');
      expect(holder(r), DocFieldOutcome.matched);
    });

    test('H2 expected 있음 + 다른 예금주를 읽음 → MISMATCH', () {
      final r = run('국민은행\n예금주 김철수\n계좌번호: 288-910548-10807\n',
          '홍길동', account: '288-910548-10807');
      expect(holder(r), DocFieldOutcome.mismatch);
    });

    test('H3 expected 있음 + 예금주를 못 읽음 → UNREADABLE', () {
      final r = run('국민은행\n계좌번호: 288-910548-10807\n', '홍길동',
          account: '288-910548-10807');
      expect(holder(r), DocFieldOutcome.unreadable);
      expect(holder(r), isNot(DocFieldOutcome.mismatch));
    });

    test('H4 expected 없음(외국인) → UNASSESSED', () {
      final r = run(_good, null, account: '288-910548-10807');
      expect(holder(r), DocFieldOutcome.unassessed);
      expect(holder(r), isNot(DocFieldOutcome.mismatch),
          reason: '확인한 것이 없으면 불일치도 아니다');
    });

    test('음차·번역 추측을 하지 않는다', () {
      // 영문 예금주 문서 + 한글 기대 이름.
      //   한글 추출기는 라틴 문자 예금주를 읽지 못한다 → UNREADABLE.
      //   음차로 억지 일치시키지도, 못 읽은 것을 불일치라 하지도 않는다.
      final r = run('KOOKMIN BANK\n예금주 NGUYEN VAN A\n계좌번호: 288-910548-10807\n',
          '응우옌반아', account: '288-910548-10807');
      expect(holder(r), DocFieldOutcome.unreadable);
      expect(holder(r), isNot(DocFieldOutcome.matched));
    });

    test('추측으로 집어온 이름은 불일치 근거가 아니다', () {
      // 첫 줄 "국민은행"이 2~5자 한글이라 Step 2가 예금주로 집어 온다.
      //   라벨 근거가 없으므로 MISMATCH로 올리면 안 된다.
      final r = run('국민은행\n계좌번호: 288-910548-10807\n', '홍길동',
          account: '288-910548-10807');
      expect(holder(r), DocFieldOutcome.unreadable,
          reason: '은행명을 예금주로 오인해 거짓 불일치를 만들지 않는다');
    });
  });

  group('C — 종합 판정', () {
    test('C1 account MATCH + holder MATCH → 성공', () {
      final r = run(_good, '홍길동', account: '288-910548-10807');
      expect(ok(r), isTrue);
    });

    test('C2 account MATCH + holder UNREADABLE → 성공 (전체 실패 아님)', () {
      final r = run('국민은행\n계좌번호: 288-910548-10807\n', '홍길동',
          account: '288-910548-10807');
      expect(holder(r), DocFieldOutcome.unreadable);
      expect(ok(r), isTrue, reason: '예금주는 supporting evidence다');
    });

    test('C3 account MATCH + holder UNASSESSED → 성공 (MISMATCH 아님)', () {
      final r = run(_good, null, account: '288-910548-10807');
      expect(holder(r), DocFieldOutcome.unassessed);
      expect(ok(r), isTrue);
    });

    test('C4 account MISMATCH + holder MATCH + bank MATCH → 반드시 실패', () {
      // 이전 규칙이라면 2/3 = 0.67 ≥ 0.6 으로 **성공**이 됐다.
      final r = run(_good, '홍길동',
          account: '111-222222-33333', bank: '국민은행');
      expect(acc(r), DocFieldOutcome.mismatch);
      expect(holder(r), DocFieldOutcome.matched);
      expect(bank(r), DocFieldOutcome.matched);
      expect(r['confidence'] as double, greaterThanOrEqualTo(0.6),
          reason: '점수는 높다 — 그래도 실패여야 한다');
      expect(ok(r), isFalse, reason: 'INV-2: 점수가 정오를 정하지 않는다');
    });

    test('C5 account UNREADABLE → 성공 금지', () {
      final r = run('국민은행\n예금주 홍길동\n', '홍길동',
          account: '288-910548-10807');
      expect(ok(r), isFalse);
    });

    test('C6 account UNASSESSED → 성공 금지', () {
      final r = run(_good, '홍길동');
      expect(ok(r), isFalse, reason: 'INV-1: 비교하지 않음 ≠ 일치');
    });

    test('C7 holder MISMATCH + account MATCH → 실패(경고)', () {
      final r = run('국민은행\n예금주 김철수\n계좌번호: 288-910548-10807\n',
          '홍길동', account: '288-910548-10807');
      expect(acc(r), DocFieldOutcome.matched);
      expect(holder(r), DocFieldOutcome.mismatch);
      expect(ok(r), isFalse);
    });

    test('은행명은 성공 조건에 참여하지 않는다 (PD-3)', () {
      // 은행명 불일치여도 계좌·예금주가 맞으면 문서는 일치다.
      final r = run('신한은행\n예금주 홍길동\n계좌번호: 288-910548-10807\n',
          '홍길동', account: '288-910548-10807', bank: '국민은행');
      expect(bank(r), isNot(DocFieldOutcome.matched));
      expect(ok(r), isTrue);
    });
  });

  group('F — 외국인 regression', () {
    test('예금주 기준 없음 + 계좌 일치 → 가짜 불일치 없음', () {
      final r = run('KOOKMIN BANK\n288-910548-10807\n', null,
          account: '288-910548-10807');
      expect(acc(r), DocFieldOutcome.matched,
          reason: '계좌번호 정합성은 보존된다');
      expect(holder(r), DocFieldOutcome.unassessed);
      expect(ok(r), isTrue, reason: '외국인 전원을 실패로 만들지 않는다');
    });
  });

  group('N — 내국인 regression', () {
    test('정상 통장 → 성공', () {
      final r = run(_good, '홍길동', account: '288-910548-10807');
      expect(ok(r), isTrue);
    });

    test('계좌 불일치 → 반드시 경고', () {
      final r = run(_good, '홍길동', account: '999-999999-99999');
      expect(ok(r), isFalse);
    });
  });

  group('confidence', () {
    test('판정에 쓰이지 않는다 — 1.0이어도 계좌가 없으면 실패', () {
      final r = run(_good, '홍길동');   // account expected 없음
      expect(acc(r), DocFieldOutcome.unassessed);
      expect(ok(r), isFalse);
    });

    test('평가한 항목만 분모에 들어간다', () {
      final r = run(_good, '홍길동', account: '288-910548-10807');
      // holder MATCHED + account MATCHED, bank UNASSESSED → 2/2
      expect(r['confidence'], 1.0);
    });
  });
}
