import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// [COMMON-TEXT-LAYOUT.28] 화면에 보이는 글자 기준 찾기.
///   이름·라벨은 줄바꿈 제어용 보이지 않는 문자(WORD JOINER·ZWSP·NBSP)를 품는다(TextLayout).
///   find.textContaining 은 그 문자까지 비교하므로, 보이는 글자로 바꿔 비교한다.
String visibleText(String s) =>
    s.replaceAll('\u2060', '').replaceAll('\u200B', '').replaceAll('\u00A0', ' ');

Finder findVisibleText(String text) => find.byWidgetPredicate((w) {
      if (w is! Text) return false;
      final s = w.data ?? w.textSpan?.toPlainText();
      return s != null && visibleText(s) == text;
    });

Finder findVisibleTextContaining(String part) => find.byWidgetPredicate((w) {
      if (w is! Text) return false;
      final s = w.data ?? w.textSpan?.toPlainText();
      return s != null && visibleText(s).contains(part);
    });
