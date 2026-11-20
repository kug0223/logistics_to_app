import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/common/adaptive_action_row.dart';
import 'package:ALfit/widgets/common/app_page_scaffold.dart';
import 'package:ALfit/widgets/common/count_chip.dart';

import 'support/visible_text.dart';

/// [COMMON-TEXT-LAYOUT.28] 좁은 폭·큰 글자 공통 표시 계약 — 글자를 줄이지 않고 배치를 바꾼다.
///   폭만 줄인 경우와 사용자가 글자를 키운 경우를 따로 본다.

Future<void> _pump(WidgetTester t, Widget child,
    {double width = 393, double scale = 1.0}) async {
  t.view.physicalSize = Size(width, 800);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    builder: (ctx, c) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: c!),
    home: child,
  ));
  await t.pump();
}

/// 그려진 글자 줄 수 — 실제 레이아웃 결과.
int _lines(WidgetTester t, Finder text) {
  // semanticsLabel 을 준 Text 는 Semantics 로 감싸진다(.29) — 글자 배치는 안쪽 RichText 에서 본다.
  final p = t.renderObject<RenderParagraph>(
      find.descendant(of: text, matching: find.byType(RichText), matchRoot: true).first);
  final len = p.text.toPlainText().length;
  final boxes = p.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: len));
  return boxes.map((b) => b.top.round()).toSet().length;
}

void main() {
  group('TextLayout 문자열 규칙', () {
    test('TL-1 keepWords — 낱말 안에는 줄바꿈 기회가 없다(공백에서만)', () {
      final s = TextLayout.keepWords('급여 확정 근무');
      expect(s.replaceAll('\u2060', ''), '급여 확정 근무');
      expect(s.split(' ').every((w) => w.length > 2), isTrue);
    });

    test('TL-2 identity — 띄어쓰기 없는 긴 이름은 가운데 한 곳에서만 끊을 수 있다', () {
      final s = TextLayout.identity('남궁아리아나크리스티나합성근로자');
      expect(s.replaceAll('\u2060', '').replaceAll('\u200B', ''), '남궁아리아나크리스티나합성근로자');
      expect('\u200B'.allMatches(s).length, 1);
      final before = s.split('\u200B').first.replaceAll('\u2060', '');
      expect(before.length, 8, reason: '16자 → 8 / 8');
      expect(TextLayout.identity('김둘').contains('\u200B'), isFalse, reason: '짧은 이름은 끊지 않는다');
    });

    test('TL-3 range·joinParts — 시간 범위는 ~ 뒤에서만, 머리말은 구분점 뒤에서만', () {
      // [.29] '~' 뒤 공백 하나만 줄바꿈 기회 — 앞 덩어리('09:00 ~')·뒤 덩어리('13:00') 안은 묶인다.
      final r = TextLayout.range('09:00', '13:00');
      expect(visibleText(r), '09:00 ~ 13:00');
      expect(' '.allMatches(r).length, 1);
      expect(r.split(' ').first, TextLayout.unit('09:00 ~'));
      final j = TextLayout.joinParts('2026년 10월 29일 (목) · 공고 1개 · 업무 3개');
      expect(visibleText(j), '2026년 10월 29일 (목) · 공고 1개 · 업무 3개');
      // 조각 안 글자 사이는 모두 WORD JOINER — 기기에서 NBSP 만으로는 '공고 1 / 개' 로 갈렸다.
      expect(j.split(' ')[1].startsWith('공\u2060고'), isTrue);
      // 일반 공백(줄바꿈 기회)은 구분점 바로 뒤에만 남는다.
      expect(' '.allMatches(j).length, 2);
      expect(j.contains('·\u00A0'), isFalse);
    });
  });

  group('TextLayout.fits — 글자 배율을 곱해 판단', () {
    testWidgets('TL-4 같은 폭에서 글자 2.0 이면 들어가지 않는다고 본다(더 일찍 전환)', (t) async {
      late bool at1, at2;
      await _pump(t, Builder(builder: (c) {
        at1 = TextLayout.fits(c, 300, 200);
        return const SizedBox();
      }));
      await _pump(t, Builder(builder: (c) {
        at2 = TextLayout.fits(c, 300, 200);
        return const SizedBox();
      }), scale: 2.0);
      expect(at1, isTrue);
      expect(at2, isFalse);
    });
  });

  group('AdaptiveActionRow', () {
    Widget row() => Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: AdaptiveActionRow(
              minRowWidth: 300,
              leading: const Text('계약서 미작성 6명'),
              actions: [TextButton(onPressed: () {}, child: const Text('계약서 일괄작성', softWrap: false))],
            ),
          ),
        );

    testWidgets('AR-1 넓으면 한 줄(안내와 버튼이 같은 높이)', (t) async {
      await _pump(t, row(), width: 393);
      final a = t.getCenter(find.text('계약서 미작성 6명'));
      final b = t.getCenter(find.text('계약서 일괄작성'));
      expect((a.dy - b.dy).abs(), lessThan(4));
      expect(t.takeException(), isNull);
    });

    testWidgets('AR-2 폭만 줄이면(320, 글자 1.0) 버튼이 아래 줄 — 버튼 이름은 한 줄', (t) async {
      await _pump(t, row(), width: 300);
      final a = t.getCenter(find.text('계약서 미작성 6명'));
      final b = t.getCenter(find.text('계약서 일괄작성'));
      expect(b.dy, greaterThan(a.dy + 10));
      expect(_lines(t, find.text('계약서 일괄작성')), 1);
      expect(t.takeException(), isNull);
    });

    testWidgets('AR-3 넓어도 글자 2.0 이면 아래 줄로 — 글자를 줄이지 않는다', (t) async {
      await _pump(t, row(), width: 393, scale: 2.0);
      final a = t.getCenter(find.text('계약서 미작성 6명'));
      final b = t.getCenter(find.text('계약서 일괄작성'));
      expect(b.dy, greaterThan(a.dy + 10));
      expect(find.byType(FittedBox), findsNothing);
      expect(t.takeException(), isNull);
    });
  });

  group('CountChip', () {
    testWidgets('CC-1 글자·건수·화살표 한 단위 — 좁은 칸에서도 칩 안에서 줄을 바꾸지 않는다', (t) async {
      await _pump(t, Scaffold(
        body: SizedBox(
          width: 140,
          child: Wrap(children: [
            CountChip(label: '퇴근미확인 3', color: Colors.grey, onTap: () {}),
            CountChip(label: '확인필요 2', color: Colors.purple, onTap: () {}),
          ]),
        ),
      ), scale: 1.3);
      expect(_lines(t, find.text('퇴근미확인 3 ›')), 1);
      expect(_lines(t, find.text('확인필요 2 ›')), 1);
      final a = t.getTopLeft(find.text('퇴근미확인 3 ›'));
      final b = t.getTopLeft(find.text('확인필요 2 ›'));
      expect(b.dy, greaterThan(a.dy), reason: '모자라면 칩 전체가 다음 줄');
    });

    testWidgets('CC-2 누를 수 없으면 화살표가 없다', (t) async {
      await _pump(t, const Scaffold(body: CountChip(label: '결근 1', color: Colors.red)));
      expect(find.text('결근 1'), findsOneWidget);
      expect(find.text('결근 1 ›'), findsNothing);
    });
  });

  group('AppPageScaffold 제목', () {
    Widget page(String title) => AppPageScaffold(
          title: title,
          actions: [
            IconButton(onPressed: () {}, icon: const Icon(Icons.refresh)),
            IconButton(onPressed: () {}, icon: const Icon(Icons.home)),
            IconButton(onPressed: () {}, icon: const Icon(Icons.notifications)),
          ],
          body: const SizedBox(),
        );

    testWidgets('AS-1 짧은 제목은 예전과 같다(한 줄·기본 높이)', (t) async {
      await _pump(t, page('통계'), width: 393);
      expect(t.widget<Text>(find.text('통계')).maxLines, 1);
      expect(t.getSize(find.byType(AppBar)).height, lessThan(kToolbarHeight + 2));
    });

    testWidgets('AS-2 넘치는 제목(320·액션 3)은 툴바 아래 전체 폭 줄로 — 줄이지 않는다', (t) async {
      await _pump(t, page('급여 지급 현황'), width: 300, scale: 1.3);
      final text = t.widget<Text>(findVisibleText('급여 지급 현황'));
      expect(text.maxLines, 2);
      // 두 줄일 때 낱말 안에서 끊지 않는다(기기: '급여 지 / 급 현황').
      expect(text.data!.split(' ').first, '급\u2060여');
      // 두 줄일 때 낱말 안에서 끊지 않는다(기기: '급여 지 / 급 현황').
      expect(text.data!.split(' ').first, '급\u2060여');
      expect(find.byType(FittedBox), findsNothing);
      expect(_lines(t, findVisibleText('급여 지급 현황')), lessThanOrEqualTo(2));
      expect(t.getSize(find.byType(AppBar)).height, greaterThan(kToolbarHeight));
      // 툴바(아이콘 줄) 아래, 화면 왼쪽 여백부터 — 툴바 안 84dp 자리에 갇히지 않는다(기기: '급여 / 지급 …').
      final title = t.getRect(findVisibleText('급여 지급 현황'));
      expect(title.top, greaterThanOrEqualTo(kToolbarHeight - 1));
      expect(title.left, lessThanOrEqualTo(NavigationToolbar.kMiddleSpacing + 1));
      expect(_lines(t, findVisibleText('급여 지급 현황')), 1, reason: '300dp 전체 폭이면 한 줄');
      expect(t.takeException(), isNull);
    });
  });
}
