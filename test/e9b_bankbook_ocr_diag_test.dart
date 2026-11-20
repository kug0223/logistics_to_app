// [E9B-DIAG] 통장 OCR 진단 진입점 — 판정 동일성·마스킹·격리.
//
// 모든 입력은 **합성 레이아웃·합성 숫자**다. 실제 통장 원본·원문은 넣지 않는다.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/utils/identity_identifier.dart';
import 'package:ALfit/utils/ocr_verification_helper.dart';

import '../test_driver/e9b_bankbook_ocr_diag_main.dart';

// 합성 값 — 실재하지 않는 조합.
const kName = '홍길동';
const kAcct4 = '123-456789-01-234'; // 4구간 14자리
const kLife = '010-1111-2222'; // 평생계좌(휴대전화 형태)

/// IBK 표지 **형태만** 흉내 낸 합성 OCR 텍스트(라벨과 값이 다른 줄로 나뉘는 경우).
const kSplitLayout = '''
$kName
계좌번호
$kAcct4
[평생계좌] $kLife
예금종류
가나급여통장
신규일
2010.01.01
IBK고객센터
1599-0000(1599-1111)
중소기업은행''';

/// 라벨과 값이 같은 줄에 붙은 경우.
const kInlineLayout = '''
$kName
계좌번호 $kAcct4
[평생계좌] $kLife
IBK고객센터 1599-0000(1599-1111)
중소기업은행''';

List<String> _digitsOf(String s) => [s.replaceAll(RegExp(r'\D'), '')];

void main() {
  group('E9B-DIAG-1 판정 동일성 — 진단은 production 함수 결과를 그대로 낸다', () {
    for (final (label, text) in [('split', kSplitLayout), ('inline', kInlineLayout)]) {
      test('$label: collectAccountCandidates 와 진단 후보 분류가 같다', () {
        final c = OcrVerificationHelper.collectAccountCandidates(text);
        final d = OcrVerificationHelper.diagnoseBankbookText(text);
        expect(d.candidates.where((x) => x.usable).map((x) => x.digits).toList(),
            c.usableAccountCandidates);
        expect(d.candidates.where((x) => !x.usable).map((x) => x.digits).toList(),
            c.rejectedNonAccountCandidates);
      });

      test('$label: production 판정 = verifyBankbookForTesting(은행명 미전달)', () {
        for (final expected in [kAcct4, kLife, '999-999999-99-999']) {
          final d = OcrVerificationHelper.diagnoseBankbookText(text,
              expectedName: kName, expectedAccountNumber: expected);
          final v = OcrVerificationHelper.verifyBankbookForTesting(text, kName,
              expectedAccountNumber: expected);
          for (final k in ['isDocumentConsistent', 'accountOutcome', 'holderOutcome', 'bankOutcome']) {
            expect(d.production[k], v[k], reason: '$label/$expected/$k');
          }
        }
      });
    }
  });

  group('E9B-DIAG-2 합성 IBK 형태 — 후보 분류', () {
    test('4구간 계좌는 계좌 후보, 구간 3-6-2-3', () {
      final d = OcrVerificationHelper.diagnoseBankbookText(kSplitLayout);
      final c = d.candidates.firstWhere((x) => x.digits == _digitsOf(kAcct4).first);
      expect(c.usable, isTrue);
      expect(c.shape, '3-6-2-3');
    });

    test('010 평생계좌는 계좌 라벨이 붙어 계좌 후보다 — 010 접두만으로 버리지 않는다', () {
      final d = OcrVerificationHelper.diagnoseBankbookText(kSplitLayout);
      final c = d.candidates.firstWhere((x) => x.digits == _digitsOf(kLife).first);
      expect(c.positiveLabel, isTrue);
      expect(c.usable, isTrue);
    });

    test('고객센터 대표번호(8자리)는 비계좌다', () {
      for (final text in [kSplitLayout, kInlineLayout]) {
        final d = OcrVerificationHelper.diagnoseBankbookText(text);
        final eight = d.candidates.where((x) => x.digits.length == 8).toList();
        expect(eight, isNotEmpty);
        expect(eight.every((x) => !x.usable), isTrue);
      }
    });

    test('은행은 canonical 이름으로 인식된다(중소기업은행 → 목록 이름)', () {
      final d = OcrVerificationHelper.diagnoseBankbookText(kSplitLayout);
      expect(d.canonicalBank, isNotNull);
    });

    test('최종 판정 — 4구간·평생계좌 입력은 MATCHED, 다른 계좌는 MISMATCH, 계좌 미입력은 OCR_UNCERTAIN', () {
      String v(String? acct) => e9bVerdictOf(OcrVerificationHelper.diagnoseBankbookText(
              kSplitLayout, expectedName: kName, expectedAccountNumber: acct)
          .production);
      expect(v(kAcct4), 'MATCHED');
      expect(v(kLife), 'MATCHED');
      expect(v('999-999999-99-999'), 'MISMATCH');
      expect(v(null), 'OCR_UNCERTAIN');
    });

    test('은행은 보조 근거 — 계좌·예금주가 맞으면 은행이 달라도 MATCHED, 은행 필드만 MISMATCH', () {
      // [PD-3] 은행명은 성공 조건이 아니다(production `isDocumentConsistent`).
      final d = OcrVerificationHelper.diagnoseBankbookText(kSplitLayout,
          expectedName: kName, expectedAccountNumber: kAcct4, expectedBankName: '신한은행');
      expect(e9bVerdictOf(d.production), 'MATCHED');
      expect(d.withBank!['bankOutcome'], DocFieldOutcome.mismatch);
      expect(e9bVerdictOf(d.withBank!, includeBank: true), 'MATCHED');
      // 계좌가 다를 때는 은행 불일치도 불일치 근거로 센다(등록 화면 bkHadMismatch 와 같다)
      final d2 = OcrVerificationHelper.diagnoseBankbookText(kSplitLayout,
          expectedAccountNumber: '999-999999-99-999', expectedBankName: '신한은행');
      expect(e9bVerdictOf(d2.withBank!, includeBank: true), 'MISMATCH');
    });
  });

  group('E9B-DIAG-3 마스킹 — 요약에 숫자·이름·입력값이 없다', () {
    test('요약 줄에 후보 숫자·입력 계좌·예금주가 나오지 않는다', () {
      final d = OcrVerificationHelper.diagnoseBankbookText(kSplitLayout,
          expectedName: kName, expectedAccountNumber: kAcct4, expectedBankName: '기업은행');
      final lines = E9bDiagReport.from(d,
              expectedAccountNumber: kAcct4, expectedBankName: '기업은행')
          .lines
          .join('\n');
      expect(lines, isNot(contains(kName)));
      for (final c in d.candidates) {
        expect(lines, isNot(contains(c.digits)), reason: '후보 숫자 노출');
      }
      // 연속 숫자 5자리 이상이 없다(구간 길이·개수만 있다)
      expect(RegExp(r'\d{5,}').hasMatch(lines), isFalse);
      expect(lines, contains('입력 계좌와 같음 예'));
    });
  });

  group('E9B-DIAG-4 격리 — 서버·업로드 경로에 닿지 않는다', () {
    final src = File('test_driver/e9b_bankbook_ocr_diag_main.dart').readAsStringSync();
    final code = src.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

    test('Firebase·callable·Storage·서류 등록 흐름을 import/호출하지 않는다', () {
      for (final bad in [
        'firebase', 'cloud_firestore', 'cloud_functions', 'httpsCallable',
        'FirebaseStorage', 'FirebaseAuth', 'Firestore', 'document_upload_helper',
        'document_management_screen', 'callableMarkBankbookVerified',
        'callableUpdateBankAccount', 'storage_service', 'user_provider',
        'debugPrint', 'print(',
      ]) {
        expect(code, isNot(contains(bad)), reason: bad);
      }
    });

    test('release·profile 에서는 진단이 꺼진다', () {
      expect(code, contains('E9bDiagApp(enabled: kDebugMode)'));
    });

    test('lib/ 어디에서도 진단 진입점을 import 하지 않는다', () {
      final hits = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => f.readAsStringSync().contains('e9b_bankbook_ocr_diag'))
          .map((f) => f.path)
          .toList();
      expect(hits, isEmpty);
    });

    test('서류 등록 흐름은 진단 함수를 부르지 않는다', () {
      for (final p in ['lib/utils/document_upload_helper.dart', 'lib/screens/common/document_management_screen.dart']) {
        expect(File(p).readAsStringSync(), isNot(contains('diagnoseBankbookText')), reason: p);
      }
    });
  });

  group('E9B-DIAG-5 화면 — 입력 가림·임시 파일 삭제·로그 무출력', () {
    testWidgets('실행하면 요약만 보이고, 선택 사본은 지워지고, 로그에 입력·숫자가 없다', (t) async {
      final logs = <String>[];
      final orig = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) { if (m != null) logs.add(m); };
      try {

      late File tmp;
      await t.runAsync(() async {
        tmp = File('${Directory.systemTemp.path}/e9b_diag_${DateTime.now().microsecondsSinceEpoch}.jpg');
        await tmp.writeAsBytes(const [0]);
      });

      await t.pumpWidget(MaterialApp(
        home: E9bDiagScreen(
          picker: () async => tmp.path,
          recognize: (_) async => (text: kSplitLayout, recognized: null),
        ),
      ));
      await t.enterText(find.byKey(const Key('e9b-account')), kAcct4);
      await t.enterText(find.byKey(const Key('e9b-holder')), kName);
      expect(t.widget<TextField>(find.byKey(const Key('e9b-account'))).obscureText, isTrue);
      expect(t.widget<TextField>(find.byKey(const Key('e9b-holder'))).obscureText, isTrue);

      await t.runAsync(() async {
        await t.tap(find.byKey(const Key('e9b-run')));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await t.pump();

      final shown = t.widgetList<Text>(find.byKey(const Key('e9b-line')))
          .map((w) => w.data ?? '').join('\n');
      expect(shown, contains('최종 판정(서류 등록 화면과 같은 인자): MATCHED'));
      expect(shown, isNot(contains(kName)));
      expect(RegExp(r'\d{5,}').hasMatch(shown), isFalse);

      final exists = await t.runAsync(() => tmp.exists());
      expect(exists, isFalse, reason: 'image_picker 사본은 남기지 않는다');

      final joined = logs.join('\n');
      expect(joined, isNot(contains(kName)));
      expect(RegExp(r'\d{5,}').hasMatch(joined), isFalse,
          reason: '로그에 숫자 원문이 없다(판정 wire 만)');

      await t.tap(find.byKey(const Key('e9b-clear')));
      await t.pump();
      expect(find.byKey(const Key('e9b-line')), findsNothing);
      } finally {
        debugPrint = orig; // 테스트 본문 안에서 되돌린다(프레임워크 불변식)
      }
    });

    testWidgets('디버그가 아니면 진단 화면을 열지 않는다', (t) async {
      await t.pumpWidget(const E9bDiagApp(enabled: false));
      expect(find.text('진단은 디버그 빌드에서만 동작합니다'), findsOneWidget);
      expect(find.byType(E9bDiagScreen), findsNothing);
    });
  });

  test('kDebugMode 는 테스트에서 true — 진입점 게이트가 디버그에서만 열린다는 전제', () {
    expect(kDebugMode, isTrue);
  });
}
