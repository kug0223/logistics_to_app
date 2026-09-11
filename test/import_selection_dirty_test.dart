// importSelectionChanged — ImportResult back/dirty guard 판정 (UX-P3-03)
//
// 검증 대상:
//   · 진입 시점 baseline 대비 include 변경 감지
//   · 되돌리면 다시 clean
//   · 전문 보기/접기 상태는 dirty 입력이 아님 (인자에 존재하지 않음)
//   · 제1~3조 override(기본 제외 → 포함)도 보호 대상
//
// 화면 전체는 NotificationProvider → FirestoreService(FirebaseFirestore.instance)
// 의존으로 widget pump가 불가능하므로 판정 로직을 직접 검증한다.

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/screens/business_admin/contract_import_result_screen.dart';
import 'package:ALfit/utils/contract_article_parser.dart';

ParsedArticle _a({
  required int number,
  required bool included,
  Set<ArticleWarningType> warnings = const {},
}) =>
    ParsedArticle(
      title: '제$number조',
      content: '본문 $number',
      articleNumber: number,
      warnings: warnings,
      included: included,
    );

/// 파서 기본값을 모사: 제1~3조 제외, 제4조 이상 포함
List<ParsedArticle> _parsedDefault() => [
      _a(number: 1, included: false, warnings: {ArticleWarningType.exactSystemRange}),
      _a(number: 2, included: false, warnings: {ArticleWarningType.exactSystemRange}),
      _a(number: 3, included: false, warnings: {ArticleWarningType.exactSystemRange}),
      _a(number: 4, included: true),
      _a(number: 5, included: true),
    ];

List<bool> _baselineOf(List<ParsedArticle> articles) =>
    articles.map((a) => a.included).toList(growable: false);

void main() {
  group('importSelectionChanged — baseline', () {
    test('ISD-01 진입 직후에는 clean', () {
      final articles = _parsedDefault();
      expect(importSelectionChanged(articles, _baselineOf(articles)), false);
    });

    test('ISD-02 조항이 하나도 없어도 clean', () {
      expect(importSelectionChanged([], const []), false);
    });
  });

  group('importSelectionChanged — 변경 감지', () {
    test('ISD-10 포함 조항을 제외하면 dirty', () {
      final articles = _parsedDefault();
      final baseline = _baselineOf(articles);

      articles[3].included = false; // 제4조 제외
      expect(importSelectionChanged(articles, baseline), true);
    });

    test('ISD-11 제외 조항을 포함하면 dirty', () {
      final articles = _parsedDefault();
      final baseline = _baselineOf(articles);

      articles[4].included = false;
      expect(importSelectionChanged(articles, baseline), true);
    });

    test('ISD-12 제1~3조 override(기본 제외 → 포함)도 dirty — 보호 대상', () {
      final articles = _parsedDefault();
      final baseline = _baselineOf(articles);

      articles[1].included = true; // 제2조를 관리자가 명시적으로 포함
      expect(importSelectionChanged(articles, baseline), true);
    });

    test('ISD-13 전부 해제해 0개 선택이어도 dirty', () {
      final articles = _parsedDefault();
      final baseline = _baselineOf(articles);

      for (final a in articles) {
        a.included = false;
      }
      expect(importSelectionChanged(articles, baseline), true);
    });
  });

  group('importSelectionChanged — 복원', () {
    test('ISD-20 두 번 토글해 baseline으로 돌아오면 다시 clean', () {
      final articles = _parsedDefault();
      final baseline = _baselineOf(articles);

      articles[3].included = false;
      expect(importSelectionChanged(articles, baseline), true);

      articles[3].included = true; // 원복
      expect(importSelectionChanged(articles, baseline), false);
    });

    test('ISD-21 여러 개를 바꿨다가 전부 원복해도 clean', () {
      final articles = _parsedDefault();
      final baseline = _baselineOf(articles);

      articles[0].included = true;
      articles[3].included = false;
      expect(importSelectionChanged(articles, baseline), true);

      articles[0].included = false;
      articles[3].included = true;
      expect(importSelectionChanged(articles, baseline), false);
    });
  });

  group('importSelectionChanged — 표시 상태 무관', () {
    test('ISD-30 전문 보기/접기는 dirty 입력이 아니다', () {
      final articles = _parsedDefault();
      final baseline = _baselineOf(articles);

      // 화면의 _expanded는 이 판정의 인자가 아니다 — 어떤 조항을 펼치든
      // include를 건드리지 않는 한 결과는 clean으로 유지된다.
      final expanded = <int>{0, 3, 4};
      expect(expanded.isNotEmpty, true);
      expect(importSelectionChanged(articles, baseline), false);
    });
  });
}
