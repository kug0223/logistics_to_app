import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// [COMMON-TEXT-LAYOUT.28] 화면에 보이는 글자 기준 찾기.
///   이름·라벨은 줄바꿈 제어용 보이지 않는 문자(WORD JOINER·ZWSP·NBSP)를 품는다(TextLayout).
///   find.textContaining 은 그 문자까지 비교하므로, 보이는 글자로 바꿔 비교한다.
String visibleText(String s) =>
    s.replaceAll('\u2060', '').replaceAll('\u200B', '').replaceAll('\u00A0', ' ');

/// [impl_21] `skipOffstage` 는 `find.text(…, skipOffstage:)` 와 같은 뜻(기본 true) — 정확 finder 를 그대로 옮겨 쓸 수 있게.
Finder findVisibleText(String text, {bool skipOffstage = true}) => find.byWidgetPredicate((w) {
      if (w is! Text) return false;
      final s = w.data ?? w.textSpan?.toPlainText();
      return s != null && visibleText(s) == text;
    }, skipOffstage: skipOffstage);

Finder findVisibleTextContaining(String part, {bool skipOffstage = true}) => find.byWidgetPredicate((w) {
      if (w is! Text) return false;
      final s = w.data ?? w.textSpan?.toPlainText();
      return s != null && visibleText(s).contains(part);
    }, skipOffstage: skipOffstage);
