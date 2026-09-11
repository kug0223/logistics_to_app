// ImportArticleCard — 가져온 조항 검수 카드 (UX-P2-06)
//
// 검증 대상:
//   · 기본 compact scan (본문 2줄) 유지
//   · 넘치는 조항만 [전문 보기] 노출 → 펼치면 전문, 접으면 2줄 복귀
//   · 전문 보기/접기 탭이 include 상태를 바꾸지 않을 것 (interaction 분리)
//   · 여러 조항 동시 펼침 허용 (아코디언 아님)
//   · system-range / likely-duplicate / PII / excluded 조항도 모두 펼침 가능
//
// 화면 전체는 NotificationProvider에 의존하므로 카드만 단독으로 pump한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/screens/business_admin/contract_import_result_screen.dart';
import 'package:ALfit/utils/contract_article_parser.dart';

/// 2줄을 확실히 넘기는 본문
const _longBody =
    '1일 8시간을 초과하는 근로에 대하여는 통상임금의 100분의 50 이상을 가산하여 지급한다. '
    '야간근로(22시부터 익일 06시까지)에 대하여도 동일하게 가산하며, '
    '휴일근로의 경우 8시간 이내는 100분의 50, 8시간을 초과한 부분은 100분의 100을 가산한다. '
    '연장·야간·휴일근로가 중복되는 경우 각각의 가산수당을 합산하여 지급한다.';

/// 2줄 안에 들어가는 짧은 본문
const _shortBody = '현장 내 사진 촬영을 금지한다.';

ParsedArticle _article({
  String title = '제4조 (연장·야간근로 수당)',
  String content = _longBody,
  int number = 4,
  Set<ArticleWarningType> warnings = const {},
  bool included = true,
}) =>
    ParsedArticle(
      title: title,
      content: content,
      articleNumber: number,
      warnings: warnings,
      included: included,
    );

/// 카드 한 장을 상태와 함께 pump. 콜백 호출 횟수를 기록한다.
Future<_Harness> _pumpCard(
  WidgetTester tester, {
  required ParsedArticle article,
}) async {
  final harness = _Harness(article: article);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (ctx, setState) => ImportArticleCard(
            article: harness.article,
            index: 0,
            expanded: harness.expanded,
            onToggle: () => setState(() {
              harness.includeToggleCount++;
              harness.article.included = !harness.article.included;
            }),
            onToggleExpand: () => setState(() {
              harness.expandToggleCount++;
              harness.expanded = !harness.expanded;
            }),
          ),
        ),
      ),
    ),
  );
  return harness;
}

class _Harness {
  final ParsedArticle article;
  bool expanded = false;
  int includeToggleCount = 0;
  int expandToggleCount = 0;
  _Harness({required this.article});
}

/// 본문 Text 위젯(제목/칩 제외)을 찾는다.
Text _bodyText(WidgetTester tester, String content) =>
    tester.widget<Text>(find.text(content));

void main() {
  group('ImportArticleCard — 기본 밀도', () {
    testWidgets('IAC-01 접힌 상태 본문은 2줄로 제한된다', (tester) async {
      await _pumpCard(tester, article: _article());
      expect(_bodyText(tester, _longBody).maxLines, 2);
      expect(_bodyText(tester, _longBody).overflow, TextOverflow.ellipsis);
    });

    testWidgets('IAC-02 긴 본문에는 [전문 보기]가 노출된다', (tester) async {
      await _pumpCard(tester, article: _article());
      expect(find.text('전문 보기'), findsOneWidget);
      expect(find.text('접기'), findsNothing);
    });

    testWidgets('IAC-03 2줄 안에 들어가는 본문에는 컨트롤이 없다', (tester) async {
      await _pumpCard(tester, article: _article(content: _shortBody));
      expect(find.text('전문 보기'), findsNothing);
      expect(find.text('접기'), findsNothing);
    });

    testWidgets('IAC-04 본문이 비어 있으면 컨트롤이 없다', (tester) async {
      await _pumpCard(tester, article: _article(content: ''));
      expect(find.text('전문 보기'), findsNothing);
    });
  });

  group('ImportArticleCard — 펼침/접기', () {
    testWidgets('IAC-10 전문 보기 → 본문 maxLines 해제', (tester) async {
      await _pumpCard(tester, article: _article());
      await tester.tap(find.text('전문 보기'));
      await tester.pump();

      expect(_bodyText(tester, _longBody).maxLines, isNull);
      expect(find.text('접기'), findsOneWidget);
      expect(find.text('전문 보기'), findsNothing);
    });

    testWidgets('IAC-11 접기 → 다시 2줄로 복귀', (tester) async {
      await _pumpCard(tester, article: _article());
      await tester.tap(find.text('전문 보기'));
      await tester.pump();
      await tester.tap(find.text('접기'));
      await tester.pump();

      expect(_bodyText(tester, _longBody).maxLines, 2);
      expect(find.text('전문 보기'), findsOneWidget);
    });
  });

  group('ImportArticleCard — interaction 분리 (핵심)', () {
    testWidgets('IAC-20 전문 보기 탭은 include 상태를 바꾸지 않는다', (tester) async {
      final h = await _pumpCard(tester, article: _article(included: true));

      await tester.tap(find.text('전문 보기'));
      await tester.pump();

      expect(h.article.included, true, reason: 'include 상태 불변이어야 함');
      expect(h.includeToggleCount, 0, reason: 'onToggle이 호출되면 안 됨');
      expect(h.expandToggleCount, 1);
    });

    testWidgets('IAC-21 접기 탭도 include 상태를 바꾸지 않는다', (tester) async {
      final h = await _pumpCard(tester, article: _article(included: true));
      await tester.tap(find.text('전문 보기'));
      await tester.pump();

      await tester.tap(find.text('접기'));
      await tester.pump();

      expect(h.article.included, true);
      expect(h.includeToggleCount, 0);
    });

    testWidgets('IAC-22 카드 본체 탭은 여전히 include를 토글한다', (tester) async {
      final h = await _pumpCard(tester, article: _article(included: true));

      await tester.tap(find.text('제4조 (연장·야간근로 수당)'));
      await tester.pump();

      expect(h.includeToggleCount, 1);
      expect(h.article.included, false);
    });

    testWidgets('IAC-23 include 토글이 펼침 상태를 접지 않는다', (tester) async {
      final h = await _pumpCard(tester, article: _article(included: true));
      await tester.tap(find.text('전문 보기'));
      await tester.pump();

      await tester.tap(find.text('제4조 (연장·야간근로 수당)'));
      await tester.pump();

      expect(h.expanded, true, reason: '펼침 유지');
      expect(find.text('접기'), findsOneWidget);
      expect(h.article.included, false);
    });
  });

  group('ImportArticleCard — 경고 유형별 펼침 가능', () {
    testWidgets('IAC-30 제1~3조(기본 제외)도 전문 확인 가능', (tester) async {
      final h = await _pumpCard(
        tester,
        article: _article(
          title: '제2조 (근무 조건)',
          number: 2,
          warnings: const {ArticleWarningType.exactSystemRange},
          included: false, // 파서 기본값
        ),
      );

      expect(find.text('전문 보기'), findsOneWidget);
      await tester.tap(find.text('전문 보기'));
      await tester.pump();

      expect(_bodyText(tester, _longBody).maxLines, isNull);
      expect(h.article.included, false, reason: '기본 제외 상태 유지');
      // 기존 안내 문구는 그대로 남아야 한다
      expect(find.text('ALfit에서 자동 작성되는 항목과 겹칩니다.'), findsOneWidget);
    });

    testWidgets('IAC-31 likelyDuplicate 조항도 펼침 가능', (tester) async {
      await _pumpCard(
        tester,
        article: _article(
          warnings: const {ArticleWarningType.likelyDuplicate},
        ),
      );
      await tester.tap(find.text('전문 보기'));
      await tester.pump();
      expect(_bodyText(tester, _longBody).maxLines, isNull);
    });

    testWidgets('IAC-32 PII 경고 조항도 펼침 가능 (마스킹 없음)', (tester) async {
      const body = '$_longBody 담당자 연락처는 010-1234-5678 이다.';
      await _pumpCard(
        tester,
        article: _article(
          content: body,
          warnings: const {ArticleWarningType.piiDetected},
        ),
      );
      await tester.tap(find.text('전문 보기'));
      await tester.pump();

      // 원문 그대로 — 자동 마스킹/삭제를 추가하지 않는다
      expect(find.text(body), findsOneWidget);
      expect(_bodyText(tester, body).maxLines, isNull);
    });

    testWidgets('IAC-33 제외된 조항도 펼칠 수 있다', (tester) async {
      await _pumpCard(tester, article: _article(included: false));
      expect(find.text('전문 보기'), findsOneWidget);
      await tester.tap(find.text('전문 보기'));
      await tester.pump();
      expect(_bodyText(tester, _longBody).maxLines, isNull);
    });
  });

  group('ImportArticleCard — 다중 펼침', () {
    testWidgets('IAC-40 두 조항을 동시에 펼칠 수 있다 (아코디언 아님)', (tester) async {
      final expanded = <int>{};
      final articles = [
        _article(title: '제4조 (연장·야간근로 수당)'),
        _article(title: '제8조 (비밀유지)'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (ctx, setState) => ListView(
                children: articles
                    .asMap()
                    .entries
                    .map((e) => ImportArticleCard(
                          article: e.value,
                          index: e.key,
                          expanded: expanded.contains(e.key),
                          onToggle: () {},
                          onToggleExpand: () => setState(() {
                            if (!expanded.remove(e.key)) expanded.add(e.key);
                          }),
                        ))
                    .toList(),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('전문 보기').first);
      await tester.pump();
      await tester.tap(find.text('전문 보기').first); // 남은 하나
      await tester.pump();

      expect(expanded, {0, 1});
      expect(find.text('접기'), findsNWidgets(2));
      expect(find.text('전문 보기'), findsNothing);
    });
  });
}
