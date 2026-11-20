// ignore_for_file: depend_on_referenced_packages
// [DU338] 낱말 안 줄바꿈 판정기(공용) — 소급 감사 6 §4 · 보완기록 6 §2 '판정기 보강'.
//
//   이전 판정식(DU335–337 시험 안 `_avoidable`)은 앞 줄에 공백이 있던 **후보 경계만** 보고, 낱말 폭을 배치된
//   selection box 합으로 쟀다. 이 판정기는 다음처럼 바꾼다.
//   - 줄이 바뀐 **모든** 경계를 본다. 경계 양쪽이 같은 낱말 안이면(사이에 공백 · 개행 · ZWSP 없음) '낱말 안 끊김'이다.
//   - 그 낱말의 **독립 한 줄 폭**을 같은 글꼴 · 스타일 · textScaler · 방향 · locale 의 TextPainter 로 잰다(배율을 두 번 곱하지 않는다).
//     - 한 줄 폭 ≤ 문단 폭(+0.5) → 그 낱말은 한 줄에 들어갈 수 있었다 → **피할 수 있는 끊김**(avoidable)
//     - 한 줄 폭 > 문단 폭 → 같은 크기 · 폭 · 원문으로는 낱말 안 분절이 불가피하다 → **강제 끊김**(forced). 공백 없는 긴 낱말이
//       여러 줄로 계속 갈리면 그 경계를 모두 forced 로 센다.
//   - 낱말 경계: 일반 공백 · 탭 · 개행 · ZERO WIDTH SPACE(U+200B, TextLayout 이 일부러 넣는 줄바꿈 자리).
//     NBSP(U+00A0)와 WORD JOINER(U+2060)는 붙이는 문자라 낱말 안으로 본다.
//   - 결과마다 낱말 · 한 줄 폭 · 문단 폭을 남긴다(기록용).
import 'package:flutter/rendering.dart';

import 'visible_text.dart';

class WordBreak {
  final String word; // 보이는 글자(표시 제어 문자 제거)
  final String at; // 줄이 바뀐 자리 'ab|c'
  final double wordWidth; // 독립 한 줄 폭
  final double paraWidth; // 문단 폭
  final bool forced;
  const WordBreak(this.word, this.at, this.wordWidth, this.paraWidth, this.forced);

  @override
  String toString() =>
      '${forced ? 'forced' : 'avoidable'}(${visibleText(at)} 낱말=${visibleText(word)} 한줄=${wordWidth.toStringAsFixed(1)} 문단=${paraWidth.toStringAsFixed(1)})';
}

bool _isBoundary(String ch) => ch == ' ' || ch == '\n' || ch == '\t' || ch == '​' || ch == '\r';

/// [rp] 안의 낱말 안 줄바꿈 전부. avoidable/forced 는 [WordBreak.forced] 로 나뉜다.
List<WordBreak> wordBreaks(RenderParagraph rp) {
  final plain = rp.text.toPlainText();
  final out = <WordBreak>[];
  if (plain.isEmpty) return out;
  final paraWidth = rp.constraints.hasBoundedWidth ? rp.constraints.maxWidth : rp.size.width;
  final style = rp.text.style;
  final widthCache = <String, double>{};
  double oneLine(String word) => widthCache.putIfAbsent(word, () {
        final tp = TextPainter(
          text: TextSpan(text: word, style: style),
          textDirection: rp.textDirection,
          textScaler: rp.textScaler,
          locale: rp.locale,
          strutStyle: rp.strutStyle,
          maxLines: 1,
        )..layout();
        final w = tp.width;
        tp.dispose();
        return w;
      });

  double? lastTop;
  var lastIdx = -1;
  for (var i = 0; i < plain.length; i++) {
    final ch = plain[i];
    if (ch == '\n') {
      lastTop = null; // 개행 뒤 새 줄은 끊김이 아니다
      lastIdx = i;
      continue;
    }
    final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (bx.isEmpty) continue; // 폭 0 표시 제어 문자 등
    final top = bx.first.top;
    if (lastTop != null && top > lastTop + 1) {
      // 줄이 바뀌었다 — 직전 보이는 글자(lastIdx)와 이 글자 사이에 경계 문자가 없으면 낱말 안이다
      var crossesBoundary = false;
      for (var k = lastIdx + 1; k < i; k++) {
        if (_isBoundary(plain[k])) crossesBoundary = true;
      }
      if (lastIdx >= 0 && _isBoundary(plain[lastIdx])) crossesBoundary = true;
      if (_isBoundary(ch)) crossesBoundary = true;
      if (!crossesBoundary && lastIdx >= 0) {
        var s = i, e = i;
        while (s > 0 && !_isBoundary(plain[s - 1])) {
          s--;
        }
        while (e < plain.length && !_isBoundary(plain[e])) {
          e++;
        }
        final word = plain.substring(s, e);
        final w = oneLine(word);
        final from = (i - 6).clamp(s, i);
        final to = (i + 2).clamp(i, e);
        out.add(WordBreak(word, '${plain.substring(from, i)}|${plain.substring(i, to)}', w, paraWidth, w > paraWidth + 0.5));
      }
    }
    if (lastTop == null || top > lastTop + 1) lastTop = top;
    lastIdx = i;
  }
  return out;
}
