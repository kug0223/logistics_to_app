// [DU364] KeepWordsText 계약 시험(소급 12 §3 pilot) — 생성기 work/du364-keep-words-text/mk.py.
//   K-1 원문 찾기(find.text · textContaining) 1개 · 없는 글 0개  K-2 Text 위젯은 하나(findVisibleText 1개)  K-3 낭독 원문
//   K-4 그린 글은 낱말 조판(WJ) · 좁은 폭에서 피할 수 있는 끊김 0 · 보이는 글은 원문  K-5 줄바꿈 유지  K-6 스타일 · 정렬 · 줄 수 · 넘침 전달
//   K-7 선택 영역 안(RichText 아닌 구조)이면 원문 그대로  K-8 토스트(첫 소비자)가 KeepWordsText 를 쓴다(정적).
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/widgets/common/keep_words_text.dart';

import 'support/du1_vq_capture.dart';
import 'support/du_word_break.dart';
import 'support/visible_text.dart';

const _msg = '약관 동의 기록에 실패했습니다. 다시 로그인하여 재시도해주세요.';

Widget _host(Widget child, {double w = 200, double scale = 1.0}) => MaterialApp(
      debugShowCheckedModeBanner: false,
      builder: (ctx, c) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: c!),
      home: Scaffold(body: Center(child: SizedBox(width: w, child: child))),
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('K-1 · K-2 원문 찾기 1개 · Text 하나 · 없는 글 0개', (t) async {
    await t.pumpWidget(_host(const KeepWordsText(_msg, style: TextStyle(fontSize: 14))));
    expect(find.text(_msg), findsOneWidget);
    expect(find.textContaining('다시 로그인하여'), findsOneWidget);
    expect(findVisibleText(_msg), findsOneWidget, reason: 'Text 위젯 대상 찾기가 하나만 센다');
    expect(find.byWidgetPredicate((w) => w is Text), findsOneWidget); // [수리 1/3] byType 은 정확한 형만 센다(하위 클래스 제외)
    expect(find.text('다른 글'), findsNothing);
    expect(find.text(_msg.replaceAll(' ', '\u2060')), findsNothing);
  });

  testWidgets('K-3 낭독은 원문', (t) async {
    final h = t.ensureSemantics();
    await t.pumpWidget(_host(const KeepWordsText(_msg)));
    expect(find.bySemanticsLabel(_msg), findsOneWidget);
    h.dispose();
  });

  testWidgets('K-4 그린 글은 낱말 조판 · 좁은 폭 끊김 0 · 보이는 글은 원문', (t) async {
    await t.runAsync(vqLoadFonts);
    await t.pumpWidget(_host(const KeepWordsText(_msg, style: TextStyle(fontFamily: 'NotoSansKR', fontSize: 14)), w: 140, scale: 2.0));
    final rp = t.renderObject<RenderParagraph>(find.byType(RichText).first);
    final plain = rp.text.toPlainText();
    expect(plain.contains('\u2060'), isTrue);
    expect(visibleText(plain), _msg);
    final breaks = wordBreaks(rp).where((b) => !b.forced).toList();
    expect(breaks, isEmpty, reason: '$breaks');
  });

  testWidgets('K-5 줄바꿈 유지', (t) async {
    await t.pumpWidget(_host(const KeepWordsText('첫 줄입니다\n둘째 줄입니다'), w: 400));
    final rp = t.renderObject<RenderParagraph>(find.byType(RichText).first);
    expect(visibleText(rp.text.toPlainText()), '첫 줄입니다\n둘째 줄입니다');
    final boxes = rp.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: rp.text.toPlainText().length));
    expect(boxes.map((b) => b.top.round()).toSet().length, 2);
  });

  testWidgets('K-6 스타일 · 정렬 · 줄 수 · 넘침 전달', (t) async {
    await t.pumpWidget(_host(
        const KeepWordsText(_msg,
            style: TextStyle(fontSize: 13, color: Color(0xFF112233), fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis),
        w: 120));
    final rt = t.widget<RichText>(find.byType(RichText).first);
    final st = (rt.text as TextSpan).style!;
    expect(st.fontSize, 13);
    expect(st.color, const Color(0xFF112233));
    expect(st.fontWeight, FontWeight.w500);
    expect(rt.textAlign, TextAlign.center);
    expect(rt.maxLines, 2);
    expect(rt.overflow, TextOverflow.ellipsis);
  });

  testWidgets('K-7 선택 영역 안이면 원문 그대로(조판 없음 · 오류 없음)', (t) async {
    await t.pumpWidget(_host(const SelectionArea(child: KeepWordsText(_msg))));
    expect(t.takeException(), isNull);
    expect(find.text(_msg), findsOneWidget);
    final rts = find.byType(RichText).evaluate().map((e) => (e.widget as RichText).text.toPlainText()).toList();
    expect(rts.any((s) => s == _msg), isTrue, reason: '$rts');
    expect(rts.any((s) => s.contains('\u2060')), isFalse);
  });

  test('K-8 토스트(첫 소비자)가 KeepWordsText 를 쓴다(정적)', () {
    final src = File('lib/utils/toast_helper.dart').readAsStringSync();
    expect(src.contains('KeepWordsText('), isTrue);
    expect(src.contains('class _ToastMessageText'), isFalse);
  });
}
