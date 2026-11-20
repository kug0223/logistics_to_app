// lib/widgets/common/amount_text.dart
//
// [AMOUNT-LAYOUT.34] 공통 금액 표시 — 큰 금액(억 단위)을 자르거나(…) 근삿값으로 바꾸지 않고 읽히게 한다.
// ─────────────────────────────────────────
// 사용법:
//   AmountText.total('1,322,099,341원', style: ...)  // 총액·요약 — 전용 한 줄 권장
//   AmountText.list('205,925,891원', style: ...)     // 목록 행 금액
//   AmountText('50,000원', style: ...)               // 크기 조정 없이 줄바꿈 규칙만
//
// 규칙(공통):
//   - 줄을 바꿔야 하면 쉼표 뒤에서만([TextLayout.amount]) — '1,322,099,' / '341원'.
//   - 접근성 이름은 원문 금액.
//   - 사용자 글자 배율(TextScaler)은 그대로 곱한다. 무효화하지 않는다.
//   - [minFontSize] 가 있으면 받은 폭에서 한 줄이 되도록 **기본 크기만** 1 씩, 하한까지만 낮춘다
//     (total 은 기본의 약 85%, list 는 기본 −2). 하한에서도 길면 그 크기로 쉼표 뒤 줄바꿈.
// 배치(정보 순서·한 줄을 줄지 여부)는 각 화면이 정한다.

import 'package:flutter/material.dart';

import '../../utils/text_layout.dart';

class AmountText extends StatelessWidget {
  const AmountText(
    this.amount, {
    super.key,
    required this.style,
    this.minFontSize,
    this.textAlign = TextAlign.start,
  });

  /// 총액·요약 — 기본 크기의 약 85% 까지 조정.
  factory AmountText.total(String amount,
          {Key? key, required TextStyle style, TextAlign textAlign = TextAlign.start}) =>
      AmountText(amount,
          key: key,
          style: style,
          textAlign: textAlign,
          minFontSize: ((style.fontSize ?? 14) * 0.85).roundToDouble());

  /// 목록 행 금액 — 기본 크기 −2 까지 조정.
  factory AmountText.list(String amount,
          {Key? key, required TextStyle style, TextAlign textAlign = TextAlign.start}) =>
      AmountText(amount,
          key: key,
          style: style,
          textAlign: textAlign,
          minFontSize: (style.fontSize ?? 14) - 2);

  /// 원문 금액('1,322,099,341원') — 접근성 이름으로도 쓴다.
  final String amount;
  final TextStyle style;

  /// 기본 크기의 하한. null 이면 크기를 바꾸지 않는다(줄바꿈 규칙만).
  final double? minFontSize;
  final TextAlign textAlign;

  Text _text(double? size) => Text(
        TextLayout.amount(amount),
        semanticsLabel: amount,
        textAlign: textAlign,
        style: size == null ? style : style.copyWith(fontSize: size),
      );

  @override
  Widget build(BuildContext context) {
    final floor = minFontSize;
    final base = style.fontSize;
    if (floor == null || base == null || floor >= base) return _text(null);
    final scaler = MediaQuery.textScalerOf(context);
    // 잴 때도 그릴 때와 같은 글꼴로 — Text 는 상속 스타일(DefaultTextStyle: 글꼴·자간)을 합쳐 그린다.
    final drawn = DefaultTextStyle.of(context).style.merge(style);
    //   재는 글자도 그리는 글자(줄바꿈 표시 문자 포함) 그대로.
    final shown = TextLayout.amount(amount);
    return LayoutBuilder(builder: (context, c) {
      bool oneLine(double size) {
        final tp = TextPainter(
          text: TextSpan(text: shown, style: drawn.copyWith(fontSize: size)),
          textScaler: scaler,
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        final w = tp.width;
        tp.dispose();
        return w <= c.maxWidth;
      }

      var size = base;
      while (size > floor && !oneLine(size)) {
        size = (size - 1).clamp(floor, base);
      }
      return _text(size);
    });
  }
}
