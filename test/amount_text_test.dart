// [AMOUNT-LAYOUT.34] 공통 금액 부품 AmountText — 말줄임·근삿값 없음, 쉼표 뒤 줄바꿈, 사용자 배율 유지,
//   기본 크기 조정은 하한까지만.
//   AT-1 크기 조정 없는 기본형 · AT-2 하한 있는 형: 폭이 넉넉하면 기본 크기 그대로
//   AT-3 폭이 모자라면 한 줄이 될 때까지만 낮추고, 하한 아래로는 안 내려간다 · AT-4 사용자 배율은 곱한 채로
//   AT-5 하한에서도 길면 쉼표 뒤 줄바꿈(말줄임 없음) · AT-6 접근성 이름은 원문
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/visible_text.dart';
import 'package:ALfit/widgets/common/amount_text.dart';

const _font = 'NotoSansKR';
const _big = '1,322,099,341원';

Future<void> _loadFont() async {
  final loader = FontLoader(_font);
  for (final f in const ['Regular', 'Bold']) {
    loader.addFont(rootBundle
        .load('assets/fonts/NotoSansKR-$f.ttf')
        .then((b) => ByteData.sublistView(b.buffer.asUint8List())));
  }
  await loader.load();
}

Future<void> _pump(WidgetTester t, Widget child, {double width = 400, double scale = 1.0}) async {
  t.view.physicalSize = const Size(800, 600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: ThemeData(fontFamily: _font),
    builder: (ctx, c) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: c!),
    home: Scaffold(body: Align(alignment: Alignment.topLeft, child: SizedBox(width: width, child: child))),
  ));
}

double _fontSizeOf(WidgetTester t) => t.widget<Text>(findVisibleText(_big)).style!.fontSize!;
RenderParagraph _para(WidgetTester t) => t.renderObject<RenderParagraph>(
    find.descendant(of: findVisibleText(_big), matching: find.byType(RichText)).first);

void main() {
  setUpAll(_loadFont);
  const style = TextStyle(fontSize: 22, fontWeight: FontWeight.w800);

  testWidgets('AT-1 기본형은 크기를 바꾸지 않는다', (t) async {
    await _pump(t, const AmountText(_big, style: style), width: 120);
    expect(_fontSizeOf(t), 22);
    expect(t.widget<Text>(findVisibleText(_big)).overflow, isNot(TextOverflow.ellipsis));
  });

  testWidgets('AT-2 하한 있는 형 — 폭이 넉넉하면 기본 크기 그대로', (t) async {
    await _pump(t, const AmountText(_big, style: style, minFontSize: 19), width: 400);
    expect(_fontSizeOf(t), 22);
    expect(_para(t).getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 1)), hasLength(1));
  });

  testWidgets('AT-3 폭이 모자라면 한 줄이 될 때까지만 낮추고 하한 아래로 내려가지 않는다', (t) async {
    // 실제로 그린 한 줄 폭(상속 스타일 포함)으로 경계를 잡는다 — 21 은 안 되고 20 은 되는 폭.
    Future<double> widthAt(double size) async {
      await _pump(t, AmountText(_big, style: style.copyWith(fontSize: size)), width: 2000);
      return _para(t).getMaxIntrinsicWidth(double.infinity);
    }
    final w = (await widthAt(20) + await widthAt(21)) / 2;
    await _pump(t, const AmountText(_big, style: style, minFontSize: 19), width: w);
    expect(_fontSizeOf(t), 20);
    expect(_para(t).size.height, lessThan(20 * 2.0), reason: '한 줄');

    await _pump(t, const AmountText(_big, style: style, minFontSize: 19), width: 60);
    expect(_fontSizeOf(t), 19, reason: '하한 아래로 내려가지 않는다');
  });

  testWidgets('AT-4 사용자 배율은 곱한 채로 — 2.0 에서 렌더 크기는 하한×2 이상', (t) async {
    await _pump(t, const AmountText(_big, style: style, minFontSize: 19), width: 60, scale: 2.0);
    expect(_fontSizeOf(t), 19);
    final rp = _para(t);
    expect(rp.textScaler.scale(19), closeTo(38, 0.01));
  });

  testWidgets('AT-5 하한에서도 길면 쉼표 뒤에서 줄바꿈 — 말줄임 없음', (t) async {
    await _pump(t, const AmountText(_big, style: style, minFontSize: 19), width: 150);
    final rp = _para(t);
    expect(rp.didExceedMaxLines, isFalse);
    final shown = t.widget<Text>(findVisibleText(_big)).data!;
    // 줄 첫 글자 위치마다 앞 글자가 쉼표(또는 줄바꿈 표시 문자 뒤의 쉼표)다.
    final boxes = rp.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: shown.length));
    final lines = boxes.map((b) => b.top.round()).toSet();
    expect(lines.length, greaterThan(1), reason: '좁은 폭이라 여러 줄');
    for (var i = 1; i < shown.length; i++) {
      final prevTop = rp.getOffsetForCaret(TextPosition(offset: i - 1), Rect.zero).dy;
      final top = rp.getOffsetForCaret(TextPosition(offset: i), Rect.zero).dy;
      if (top > prevTop + 1 && shown[i] != '​') {
        final before = shown.substring(0, i).replaceAll('⁠', '').replaceAll('​', '');
        expect(before.endsWith(','), isTrue, reason: '줄이 바뀐 자리 앞이 쉼표가 아니다: ${visibleText(shown.substring(0, i))}');
      }
    }
  });

  testWidgets('AT-6 접근성 이름은 원문 금액 한 번', (t) async {
    final h = t.ensureSemantics();
    await _pump(t, const AmountText(_big, style: style, minFontSize: 19), width: 150);
    expect(find.bySemanticsLabel(_big), findsOneWidget);
    h.dispose();
  });
}
