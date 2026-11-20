import 'package:characters/characters.dart';
import 'dart:ui' show SemanticsAction, SemanticsFlag;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/common/adaptive_action_row.dart';
import 'package:ALfit/widgets/common/app_page_scaffold.dart';
import 'package:ALfit/widgets/common/count_chip.dart';

import 'support/visible_text.dart';

/// [TEXT-LAYOUT-CONSUMER.29] 표시용 줄바꿈 문자(WORD JOINER U+2060 · ZWSP U+200B · NBSP U+00A0)는
///   **화면 글자에만** 있다. 원문 복원·접근성 이름·문자 단위(grapheme) 보존·긴 토큰 넘침을 본다.

Future<void> _pump(WidgetTester t, Widget child, {double width = 320, double scale = 1.0}) async {
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

void main() {
  group('원문 복원', () {
    const samples = [
      '공고 1개',
      '계약서 미작성 6명',
      '남궁아리아나크리스티나합성근로자',
      'QA은행 ENCl-****-ocal',
      '급여 지급 현황',
    ];
    test('TB-1 plain(규칙(원문)) == 원문 — keepWords·identity', () {
      for (final s in samples) {
        expect(TextLayout.plain(TextLayout.keepWords(s)), s);
        expect(TextLayout.plain(TextLayout.identity(s)), s);
      }
    });
    test('TB-2 range·joinParts 도 원문 글자로 돌아온다', () {
      expect(TextLayout.plain(TextLayout.range('09:00', '13:00')), '09:00 ~ 13:00');
      const head = '2026년 10월 29일 (목) · 공고 1개 · 업무 3개';
      expect(TextLayout.plain(TextLayout.joinParts(head)), head);
    });
    test('TB-3 보이는 글자 비교는 내용 차이를 숨기지 않는다(건수·이름이 다르면 다르다)', () {
      expect(visibleText(TextLayout.keepWords('계약서 미작성 2명')), isNot('계약서 미작성 3명'));
      expect(visibleText(TextLayout.identity('합성 다건')), isNot('합성 다견'));
      expect(visibleText(TextLayout.keepWords('51,251원')), '51,251원');
    });
  });

  group('문자 단위(grapheme) 보존 — 사용자 이름에 이모지·결합 문자가 와도', () {
    const name = '김👨‍👩‍👧é아라🇰🇷나다라마바';
    test('TB-4 identity 는 grapheme 사이에만 넣는다 — 이모지·국기·결합 문자가 쪼개지지 않는다', () {
      final out = TextLayout.identity(name);
      final kept = out.characters
          .where((g) => g != '⁠' && g != '​')
          .toList();
      expect(kept, name.characters.toList());
      // UTF-16 짝이 깨진 글자(외톨이 surrogate)가 없다.
      final units = out.codeUnits;
      for (var i = 0; i < units.length; i++) {
        final u = units[i];
        if (u >= 0xD800 && u <= 0xDBFF) {
          expect(i + 1 < units.length && units[i + 1] >= 0xDC00 && units[i + 1] <= 0xDFFF, isTrue);
          i++;
        } else {
          expect(u >= 0xDC00 && u <= 0xDFFF, isFalse, reason: '외톨이 low surrogate @$i');
        }
      }
      expect(TextLayout.plain(out), name);
    });
  });

  group('접근성 이름은 원문', () {
    testWidgets('TB-5 앱바 제목(툴바 아래 줄)의 semantics 이름 = 원문', (t) async {
      final h = t.ensureSemantics();
      await _pump(t, AppPageScaffold(
        title: '급여 지급 현황',
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: () {}, icon: const Icon(Icons.home)),
          IconButton(onPressed: () {}, icon: const Icon(Icons.notifications)),
        ],
        body: const SizedBox(),
      ), width: 300, scale: 1.3);
      expect(find.bySemanticsLabel('급여 지급 현황'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('⁠')), findsNothing);
      h.dispose();
    });

    testWidgets('TB-6 CountChip — 이름은 원문(›·보이지 않는 문자 없음), 누를 수 있으면 버튼·탭 행동', (t) async {
      final h = t.ensureSemantics();
      var taps = 0;
      await _pump(t, Scaffold(body: Wrap(children: [
        CountChip(label: '퇴근미확인 3', color: Colors.grey, onTap: () => taps++),
        const CountChip(label: '결근 1', color: Colors.red),
      ])));
      final tappable = t.getSemantics(find.byType(CountChip).first);
      expect(tappable.label, '퇴근미확인 3');
      expect(tappable.hasFlag(SemanticsFlag.isButton), isTrue);
      expect(tappable.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      await t.tap(find.byType(CountChip).first);
      expect(taps, 1);
      final plain = t.getSemantics(find.bySemanticsLabel('결근 1'));
      expect(plain.label, '결근 1');
      expect(plain.hasFlag(SemanticsFlag.isButton), isFalse);
      expect(find.bySemanticsLabel(RegExp('›')), findsNothing);
      h.dispose();
    });

    testWidgets('TB-7 AdaptiveActionRow 를 쌓아도 버튼 역할·활성·행동이 남는다', (t) async {
      final h = t.ensureSemantics();
      await _pump(t, Scaffold(body: Padding(
        padding: const EdgeInsets.all(16),
        child: AdaptiveActionRow(
          minRowWidth: 300,
          leading: Text(TextLayout.keepWords('요청 가능 6명'), semanticsLabel: '요청 가능 6명'),
          actions: [
            TextButton(onPressed: () {}, child: const Text('신분증 요청')),
            const TextButton(onPressed: null, child: Text('계약서 일괄작성')),
          ],
        ),
      )), width: 300);
      expect(find.bySemanticsLabel('요청 가능 6명'), findsOneWidget);
      final on = t.getSemantics(find.widgetWithText(TextButton, '신분증 요청'));
      expect(on.hasFlag(SemanticsFlag.isButton), isTrue);
      expect(on.hasFlag(SemanticsFlag.isEnabled), isTrue);
      expect(on.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      final off = t.getSemantics(find.widgetWithText(TextButton, '계약서 일괄작성'));
      expect(off.hasFlag(SemanticsFlag.isEnabled), isFalse);
      h.dispose();
    });
  });

  group('긴 토큰 — 칸 밖으로 나가지 않고 전부 보인다', () {
    for (final s in [1.0, 2.0]) {
      testWidgets('TB-8 320dp × $s — 띄어쓰기 없는 긴 이름·긴 낱말, 좁은 칸에서도 넘침 0·글자 전부', (t) async {
        const longName = '남궁아리아나크리스티나합성근로자';
        const longWord = 'ENCl-****-ocal-0000-1111-2222';
        await _pump(t, Scaffold(body: Center(child: SizedBox(width: 96, child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(TextLayout.identity(longName), semanticsLabel: longName),
            Text(TextLayout.keepWords(longWord), semanticsLabel: longWord),
          ],
        )))), scale: s);
        expect(t.takeException(), isNull);
        for (final f in [findVisibleText(longName), findVisibleText(longWord)]) {
          // semanticsLabel 을 준 Text 는 Semantics 로 감싸진다 — 글자 배치는 안쪽 RichText 에서 본다.
          final p = t.renderObject<RenderParagraph>(find.descendant(of: f, matching: find.byType(RichText)));
          expect(p.didExceedMaxLines, isFalse);
          expect(p.size.width, lessThanOrEqualTo(96.0 + 0.01), reason: '칸 폭을 넘지 않는다');
        }
      });
    }
  });
}
