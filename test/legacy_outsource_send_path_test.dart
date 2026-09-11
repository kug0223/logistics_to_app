// legacy outsource 신규 사용 경로 차단 (CONTRACT-CONTENT-5.11)
//
// canonical policy:
//   LEGACY_OUTSOURCE_POLICY = READ_COMPATIBILITY_ONLY
//     조회·편집 = 허용
//     신규 계약 선택 / 복사 / 다른 사업장 복사 = 금지
//     기존 저장 데이터 삭제·변환 = 하지 않음
//
// 5.10 감사에서 확인된 실제 위험은 _outsourceArticles(runtime dead literal)이
// 아니라 이미 Firestore에 저장된 legacy 템플릿이었다. 신규 생성 UI가 outsource를
// 막아도 복사 경로가 우회로로 남아 있었고, 계약 선택 다이얼로그에서 골라
// 그대로 발송할 수 있었다. 이 파일은 그 경로들이 다시 열리지 않게 지킨다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/contract_template_model.dart';

ContractTemplateModel _t(String type, {String id = 't', String name = '이름'}) =>
    ContractTemplateModel(
      id: id,
      businessId: 'biz1',
      name: name,
      templateType: type,
      articles: ContractTemplateModel.defaultArticlesFor(type),
      createdAt: DateTime(2026, 1, 1),
    );

String _source(String relativePath) {
  final f = File(relativePath);
  expect(f.existsSync(), true, reason: '$relativePath 를 찾지 못함');
  return f.readAsStringSync();
}

void main() {
  // ── 판정 기준 ────────────────────────────────────────────────────
  group('LOS-0x 신규 사용 가능 분류 판정', () {
    test('LOS-01 daily / period 는 신규 사용 가능', () {
      expect(
          ContractTemplateType.isSupportedForNewUse(ContractTemplateType.daily),
          true);
      expect(
          ContractTemplateType.isSupportedForNewUse(ContractTemplateType.period),
          true);
    });

    test('LOS-02 outsource 는 신규 사용 불가', () {
      expect(
          ContractTemplateType.isSupportedForNewUse(
              ContractTemplateType.outsource),
          false);
    });

    test('LOS-03 알 수 없는 값은 신규 사용 불가 (fail-closed)', () {
      // 미래에 다른 legacy 값이 들어와도 신규 사용으로 새지 않는다.
      for (final unknown in const ['', 'unknown', 'freelance', 'DAILY']) {
        expect(ContractTemplateType.isSupportedForNewUse(unknown), false,
            reason: '"$unknown" 이 신규 사용 가능으로 판정됨');
      }
    });

    test('LOS-04 모델 getter가 같은 기준을 쓴다', () {
      expect(_t(ContractTemplateType.daily).isSupportedForNewUse, true);
      expect(_t(ContractTemplateType.period).isSupportedForNewUse, true);
      expect(_t(ContractTemplateType.outsource).isSupportedForNewUse, false);
    });
  });

  // ── §21 Selector 후보 ────────────────────────────────────────────
  group('LOS-1x 신규 계약 선택 후보', () {
    test('LOS-10 daily / period 는 후보에 포함된다', () {
      final out = ContractTemplateModel.selectableForNewContract([
        _t(ContractTemplateType.daily, id: 'd'),
        _t(ContractTemplateType.period, id: 'p'),
      ]);
      expect(out.map((t) => t.id).toList(), ['d', 'p']);
    });

    test('LOS-11 outsource 는 후보에서 제외된다', () {
      final out = ContractTemplateModel.selectableForNewContract([
        _t(ContractTemplateType.outsource, id: 'o'),
      ]);
      expect(out, isEmpty);
    });

    test('LOS-12 혼합 목록은 daily/period만 남는다', () {
      final out = ContractTemplateModel.selectableForNewContract([
        _t(ContractTemplateType.daily, id: 'd'),
        _t(ContractTemplateType.outsource, id: 'o'),
        _t(ContractTemplateType.period, id: 'p'),
      ]);
      expect(out.map((t) => t.id).toList(), ['d', 'p']);
    });

    test('LOS-13 순서를 바꾸지 않는다', () {
      final out = ContractTemplateModel.selectableForNewContract([
        _t(ContractTemplateType.period, id: 'p1'),
        _t(ContractTemplateType.daily, id: 'd1'),
        _t(ContractTemplateType.outsource, id: 'o1'),
        _t(ContractTemplateType.daily, id: 'd2'),
      ]);
      expect(out.map((t) => t.id).toList(), ['p1', 'd1', 'd2']);
    });
  });

  // ── §22 outsource-only empty ─────────────────────────────────────
  group('LOS-2x outsource만 있는 사업장', () {
    test('LOS-20 후보 0개가 되어 기존 empty flow로 이어진다', () {
      final out = ContractTemplateModel.selectableForNewContract([
        _t(ContractTemplateType.outsource, id: 'o1'),
        _t(ContractTemplateType.outsource, id: 'o2'),
      ]);
      expect(out, isEmpty);
    });

    test('LOS-21 SelectorDialog가 빈 후보에서 dead-end가 아니다', () {
      // 후보가 비면 _buildEmpty가 세 가지 시작 경로를 제공해야 한다.
      final src =
          _source('lib/widgets/dialogs/contract_template_selector_dialog.dart');
      expect(src.contains('_startImportFromEmpty'), true);
      expect(src.contains('_startDefaultFromEmpty'), true);
      expect(src.contains("'빈 계약서로 진행'"), true);
    });
  });

  // ── §23 readiness ────────────────────────────────────────────────
  group('LOS-3x 공고 사전조건 readiness', () {
    // readiness는 SelectorDialog 후보와 같은 기준을 써야 한다.
    // 다르면 "준비 완료"인데 고를 템플릿이 0개인 dead-end가 생긴다.
    bool ready(List<String> types) =>
        ContractTemplateModel.selectableForNewContract(
                types.map((t) => _t(t)).toList())
            .isNotEmpty;

    test('LOS-30 [] → not ready', () => expect(ready([]), false));
    test('LOS-31 [outsource] → not ready',
        () => expect(ready([ContractTemplateType.outsource]), false));
    test('LOS-32 [daily] → ready',
        () => expect(ready([ContractTemplateType.daily]), true));
    test('LOS-33 [period] → ready',
        () => expect(ready([ContractTemplateType.period]), true));
    test('LOS-34 [outsource, daily] → ready', () {
      expect(
          ready([ContractTemplateType.outsource, ContractTemplateType.daily]),
          true);
    });

    test('LOS-35 CreateTO가 isNotEmpty 단독 판정을 쓰지 않는다', () {
      final src = _source(
          'lib/screens/business_admin/to_management/create_to_screen.dart');
      expect(src.contains('_contractTemplatesReady = allTemplates.isNotEmpty'),
          false,
          reason: 'legacy 템플릿만 있어도 준비 완료로 판정되던 코드가 남아 있음');
      expect(src.contains('selectableForNewContract(allTemplates)'), true);
    });
  });

  // ── §24 / §25 복사 차단 ──────────────────────────────────────────
  group('LOS-4x 복사·다른 사업장 복사', () {
    // ContractTemplateService는 FirebaseFirestore.instance를 필드로 즉시
    // 보유해 단위 테스트로 생성할 수 없다. test 전용 API를 열지 않고
    // 가드 존재와 호출 지점을 소스로 검증한다(5.8에서 쓴 방식과 동일).
    late final String svc = _source('lib/services/contract_template_service.dart');

    test('LOS-40 복사 가드가 존재한다', () {
      expect(svc.contains('_assertCopyable'), true);
      expect(svc.contains('isSupportedForNewUse'), true);
    });

    test('LOS-41 duplicateTemplate 이 가드를 호출한다', () {
      final i = svc.indexOf('Future<ContractTemplateModel> duplicateTemplate(');
      expect(i, greaterThan(-1));
      final body = svc.substring(i, i + 400);
      expect(body.contains('_assertCopyable(source)'), true,
          reason: 'duplicateTemplate 이 가드 없이 복사함');
    });

    test('LOS-42 duplicateTemplateTo 가 가드를 호출한다', () {
      final i = svc.indexOf('Future<ContractTemplateModel> duplicateTemplateTo(');
      expect(i, greaterThan(-1));
      final body = svc.substring(i, i + 500);
      expect(body.contains('_assertCopyable(source)'), true,
          reason: 'cross-business copy 가 가드 없이 복사함');
    });

    test('LOS-43 UI가 legacy 카드에서 복사 버튼을 감춘다', () {
      final src = _source(
          'lib/screens/business_admin/contract_template_list_screen.dart');
      expect(src.contains('if (template.isSupportedForNewUse)'), true);
    });

    test('LOS-44 다른 사업장 복사 후보에서 legacy가 제외된다', () {
      final src = _source(
          'lib/screens/business_admin/contract_template_list_screen.dart');
      expect(src.contains('selectableForNewContract(tpls)'), true);
    });
  });

  // ── §26 읽기·편집 호환 ───────────────────────────────────────────
  group('LOS-5x legacy 읽기·편집 호환 유지', () {
    test('LOS-50 outsource 기본 조항 세트가 그대로 남아 있다', () {
      // [§19] dead literal은 이번에 손대지 않는다 — 기존 문서 호환 기준.
      final arts = ContractTemplateModel
          .defaultArticlesFor(ContractTemplateType.outsource);
      expect(arts.length, 7);
      expect(arts.first.title, '제4조 (원천징수 및 세금 처리)');
      expect(arts.last.title, '제10조 (기타)');
    });

    test('LOS-51 outsource 상수와 label이 유지된다', () {
      expect(ContractTemplateType.outsource, 'outsource');
      expect(ContractTemplateType.label(ContractTemplateType.outsource), '기타');
    });

    test('LOS-52 저장된 outsource 문서를 모델로 읽을 수 있다', () {
      final t = _t(ContractTemplateType.outsource, id: 'legacy1', name: '구 위탁');
      expect(t.templateType, ContractTemplateType.outsource);
      expect(t.articles.length, 7);
      expect(t.name, '구 위탁');
    });

    test('LOS-53 편집·저장해도 templateType이 보존된다', () {
      // 편집 화면은 copyWith(templateType: _templateType)로 저장하며,
      // _templateType은 widget.template.templateType에서 온다.
      final t = _t(ContractTemplateType.outsource, id: 'legacy1');
      final edited = t.copyWith(
        name: '구 위탁 (수정)',
        articles: [const ContractArticle(title: '제4조 (수정)', content: '내용')],
      );
      expect(edited.templateType, ContractTemplateType.outsource,
          reason: 'daily/period로 자동 변환되면 안 된다');
    });

    test('LOS-54 편집 화면이 저장본 articles를 우선한다', () {
      // legacy 문서를 열 때 defaultArticlesFor가 저장본을 덮어쓰면
      // 관리자 데이터가 소실된다.
      final src = _source(
          'lib/screens/business_admin/contract_template_edit_screen.dart');
      // 주석에도 defaultArticlesFor가 등장하므로 실제 할당문만 본다.
      final start = src.indexOf('final sourceArticles =');
      expect(start, greaterThan(-1), reason: 'sourceArticles 할당문을 찾지 못함');
      final stmt = src.substring(start, src.indexOf(';', start));
      final i = stmt.indexOf('widget.template?.articles');
      final j = stmt.indexOf('defaultArticlesFor');
      expect(i, greaterThan(-1), reason: '저장본을 우선 참조하지 않음');
      expect(j, greaterThan(i),
          reason: '저장본보다 기본 조항이 우선 적용되고 있음');
    });

    test('LOS-55 목록 화면이 legacy를 계속 표시한다', () {
      // 목록에는 templateType 필터가 없어야 한다 — 조회는 막지 않는다.
      final svc = _source('lib/services/contract_template_service.dart');
      expect(svc.contains("where('templateType'"), false,
          reason: 'getTemplates가 분류로 필터링하면 legacy 문서가 목록에서 사라진다');
    });
  });

  // ── 범위 불변식 ──────────────────────────────────────────────────
  group('LOS-6x 이번 Phase 범위 밖을 건드리지 않았다', () {
    test('LOS-60 active reference core가 그대로다', () {
      expect(
          ContractTemplateModel.defaultArticlesFor(ContractTemplateType.daily)
              .length,
          3);
      expect(
          ContractTemplateModel.defaultArticlesFor(ContractTemplateType.period)
              .length,
          3);
    });

    test('LOS-61 범용 placeholder/checkbox 차단을 추가하지 않았다', () {
      // [§20] outsource보다 범위가 넓고 관리자 custom content에 영향을 준다.
      for (final path in const [
        'lib/services/contract_template_service.dart',
        'lib/screens/contract/contract_sign_screen.dart',
      ]) {
        final src = _source(path);
        expect(src.contains('unresolvedContent'), false);
        expect(src.contains('hasUnfilledPlaceholder'), false);
      }
    });
  });
}
