// 첫 사용자 계약 작성 안내 정렬 (CONTRACT-CONTENT-5.8)
//
// canonical rule:
//   제품이 약속하는 것 == 제품이 실제로 하는 것
//
// 5.7 감사에서 유형 선택 화면이 reference core에서 이미 제거된 조항들
// (4대보험·주휴·연차·퇴직급여·수습·5인 분기·임금명세서)을 체크리스트로
// 약속하고 있었다. default_clause_send_safe_test는 조항 *데이터*만 지키므로
// UI copy는 사각지대였다. 이 파일이 그 경계를 지킨다.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/contract_template_model.dart';
import 'package:ALfit/widgets/dialogs/contract_template_type_selector_sheet.dart';

/// 유형 선택 화면이 약속해서는 안 되는 문구.
/// 모두 5.3/5.5에서 reference default에서 제거된 주제다.
const _staleLegalPromises = <String>[
  '4대보험',
  '주휴수당',
  '연차유급휴가',
  '퇴직급여',
  '수습기간',
  '5인 이상/미만',
  '임금명세서',
  '기간제법',
  '무기계약',
  '산재보험',
];

Future<String> _renderText(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .join('\n');
}

String _source(String relativePath) {
  final f = File(relativePath);
  expect(f.existsSync(), true, reason: '$relativePath 를 찾지 못함');
  return f.readAsStringSync();
}

/// 사용자에게 보이는 문구만 추출한다.
///
/// 소스 전체를 훑으면 "이런 표현은 쓰지 않는다"고 적어둔 **주석**까지
/// 금지어로 걸린다. 주석 줄을 제거한 뒤 문자열 리터럴만 모아
/// 실제 copy를 대상으로 검사한다.
String _copyOf(String relativePath) {
  final withoutComments = _source(relativePath)
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');
  return RegExp(r"'(?:[^'\\\n]|\\.)*'")
      .allMatches(withoutComments)
      .map((m) => m.group(0)!)
      .join('\n');
}

void main() {
  // ── F-01 ────────────────────────────────────────────────────────
  group('F-01 유형 선택 화면이 없는 조항을 약속하지 않는다', () {
    for (final purpose in ContractTemplateTypePurpose.values) {
      testWidgets('FUG-01 $purpose 에 stale 법률 약속 없음', (tester) async {
        final text = await _renderText(
          tester,
          ContractTemplateTypeSelectorSheet(purpose: purpose),
        );
        for (final promise in _staleLegalPromises) {
          expect(text.contains(promise), false,
              reason: '$purpose 시트에 "$promise" 약속이 남아 있음');
        }
      });
    }

    testWidgets('FUG-02 두 근무 형태를 모두 선택할 수 있다', (tester) async {
      final text = await _renderText(
        tester,
        const ContractTemplateTypeSelectorSheet(
          purpose: ContractTemplateTypePurpose.defaultCreation,
        ),
      );
      expect(text.contains(ContractTemplateType.label(ContractTemplateType.daily)),
          true);
      expect(
          text.contains(ContractTemplateType.label(ContractTemplateType.period)),
          true);
    });

    test('FUG-03 화면에서 제거된 위젯이 되살아나지 않았다', () {
      // 하드코딩 체크리스트를 들고 있던 두 벌의 시트는 공유 위젯으로 대체됐다.
      final list =
          _source('lib/screens/business_admin/contract_template_list_screen.dart');
      final dialog = _source(
          'lib/widgets/dialogs/contract_template_selector_dialog.dart');
      expect(list.contains('_TypeSelectorSheet'), false);
      expect(list.contains('_TypeCard'), false);
      expect(dialog.contains('_TypeSelectorSheetInline'), false);

      // 문구 검사는 주석을 제외한 실제 copy만 대상으로 한다 —
      // "왜 제거했는지" 설명하는 주석까지 금지어로 걸리면 안 된다.
      final listCopy =
          _copyOf('lib/screens/business_admin/contract_template_list_screen.dart');
      final dialogCopy =
          _copyOf('lib/widgets/dialogs/contract_template_selector_dialog.dart');
      for (final promise in _staleLegalPromises) {
        expect(listCopy.contains(promise), false,
            reason: 'list screen copy에 "$promise" 문구가 남아 있음');
        expect(dialogCopy.contains(promise), false,
            reason: 'selector dialog copy에 "$promise" 문구가 남아 있음');
      }
    });
  });

  // ── F-02 ────────────────────────────────────────────────────────
  group('F-02 같은 선택의 실제 효과를 경로별로 정확히 설명한다', () {
    testWidgets('FUG-10 default 경로는 기본 조항을 불러온다고 말한다', (tester) async {
      final text = await _renderText(
        tester,
        const ContractTemplateTypeSelectorSheet(
          purpose: ContractTemplateTypePurpose.defaultCreation,
        ),
      );
      expect(text.contains('기본 조항'), true);
      // 이 경로에서 유형은 분류가 아니라 로드될 조항을 결정한다.
      expect(text.contains('목록에서 구분'), false);
    });

    testWidgets('FUG-11 import 경로는 내용이 바뀌지 않는다고 말한다', (tester) async {
      final text = await _renderText(
        tester,
        const ContractTemplateTypeSelectorSheet(
          purpose: ContractTemplateTypePurpose.importClassification,
        ),
      );
      expect(text.contains('가져온 내용은 바뀌지 않으며'), true);
      expect(text.contains('목록에서 구분'), true);
      // 붙여넣은 조항이 default를 대체하므로 기본 조항을 약속하면 안 된다.
      expect(text.contains('기본 조항'), false);
    });

    testWidgets('FUG-12 blank 경로는 비어 있는 상태로 시작한다고 말한다', (tester) async {
      final text = await _renderText(
        tester,
        const ContractTemplateTypeSelectorSheet(
          purpose: ContractTemplateTypePurpose.blankClassification,
        ),
      );
      expect(text.contains('비어 있는 상태'), true);
      expect(text.contains('목록에서 구분'), true);
      expect(text.contains('기본 조항'), false);
    });

    testWidgets('FUG-13 default와 classification이 같은 설명을 공유하지 않는다',
        (tester) async {
      final byPurpose = <ContractTemplateTypePurpose, String>{};
      for (final p in ContractTemplateTypePurpose.values) {
        byPurpose[p] =
            await _renderText(tester, ContractTemplateTypeSelectorSheet(purpose: p));
      }
      final def = byPurpose[ContractTemplateTypePurpose.defaultCreation]!;
      final imp = byPurpose[ContractTemplateTypePurpose.importClassification]!;
      final blank = byPurpose[ContractTemplateTypePurpose.blankClassification]!;

      expect(def == imp, false, reason: 'default와 import 설명이 동일함');
      expect(def == blank, false, reason: 'default와 blank 설명이 동일함');
      // import/blank는 분류라는 점은 같지만 시작 상태 설명이 달라야 한다.
      expect(imp == blank, false, reason: 'import와 blank 설명이 동일함');
    });

    test('FUG-14 blank 경로는 실제로 기본 조항을 로드하지 않는다', () {
      // copy가 "비어 있는 상태로 시작"이라고 말하는 근거를 코드에서 확인한다.
      final list =
          _source('lib/screens/business_admin/contract_template_list_screen.dart');
      expect(list.contains('initialArticles: []'), true,
          reason: 'blank 경로가 빈 조항으로 편집기를 열지 않으면 copy가 거짓이 된다');
    });
  });

  // ── F-03 / F-04 (static verification — §27) ─────────────────────
  // 두 화면 모두 FirebaseFirestore.instance를 즉시 보유하는 서비스를 필드로
  // 들고 있어 widget test가 불가능하다. test 전용 public API를 새로 열지
  // 않고 소스 문자열로 검증한다.
  group('F-03 공고 사전조건이 템플릿의 목적을 설명한다', () {
    late final String src = _copyOf(
        'lib/screens/business_admin/to_management/create_to_screen.dart');

    test('FUG-20 재사용 의미가 드러난다', () {
      expect(src.contains('이후 계약에도 계속 사용할 수 있어요'), true);
    });

    test('FUG-21 "등록된 계약서 템플릿이 없습니다" 단독 안내가 사라졌다', () {
      expect(src.contains("'등록된 계약서 템플릿이 없습니다.'"), false);
    });

    test('FUG-22 CTA가 목적지가 아니라 행동을 가리킨다', () {
      expect(src.contains("'템플릿 만들기'"), true);
    });

    test('FUG-23 법적 보증 표현을 추가하지 않았다', () {
      // §14 — prerequisite에서 금지된 표현
      for (final banned in ['안전한 계약', '필수 조항', '자동 완성']) {
        expect(src.contains(banned), false, reason: '"$banned" 표현이 추가됨');
      }
    });
  });

  group('F-04 편집기가 재사용 가치를 고지한다', () {
    late final String src = _copyOf(
        'lib/screens/business_admin/contract_template_edit_screen.dart');

    test('FUG-30 재사용 안내가 존재한다', () {
      expect(src.contains('다시 불러와 사용할 수 있어요'), true);
    });

    test('FUG-31 자동 적용이라고 말하지 않는다', () {
      // 실제 동작은 SelectorDialog에서 관리자가 직접 고르는 것이다.
      for (final banned in ['자동 적용', '자동으로 적용']) {
        expect(src.contains(banned), false, reason: '"$banned" 표현이 사용됨');
      }
    });

    test('FUG-32 조항 추가 안내가 법률 체크리스트가 아니다', () {
      expect(src.contains('조항을 추가하거나 수정할 수 있어요'), true);
      // §20 — 구체 법률 항목 나열 금지
      for (final topic in ['주휴', '4대보험', '연차', '퇴직급여', '해고예고']) {
        expect(src.contains(topic), false,
            reason: '편집기 안내에 "$topic" 항목이 나열됨');
      }
    });
  });

  // ── 책임 경계 ────────────────────────────────────────────────────
  group('책임 경계 — disclaimer를 추가하지 않았다', () {
    test('FUG-40 면책 문구 없음', () {
      const banned = [
        'ALfit은 책임지지',
        '법률 책임은',
        '면책',
      ];
      for (final path in [
        'lib/widgets/dialogs/contract_template_type_selector_sheet.dart',
        'lib/widgets/dialogs/contract_template_selector_dialog.dart',
        'lib/screens/business_admin/contract_template_edit_screen.dart',
        'lib/screens/business_admin/contract_template_list_screen.dart',
      ]) {
        final src = _copyOf(path);
        for (final b in banned) {
          expect(src.contains(b), false, reason: '$path 에 "$b" 추가됨');
        }
      }
    });
  });
}
