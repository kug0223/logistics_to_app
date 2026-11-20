import 'package:flutter/material.dart';

/// [DU361] 여러 줄 글 옆 아이콘을 **첫 줄 가운데**에 둔다 — `Row(crossAxisAlignment: CrossAxisAlignment.start)` 안에서 쓴다.
///
/// 큰 글자(320 · 2.0)에서 글이 여러 줄이 되면 아이콘이 글 덩어리 가운데(Row 기본)나 첫 줄 맨 위(고정 크기 + start)에
/// 놓여 어느 줄의 표시인지 흐렸다. 첫 줄 높이는 옆 글과 같은 스타일([textStyle] 을 DefaultTextStyle 에 병합) · 글자 배율로
/// 잰 한 줄 높이다. 아이콘 크기는 바꾸지 않는다(배율에 따라 키우는 규칙을 만들지 않음). 줄 높이가 아이콘보다 작으면
/// 아이콘 크기 상자 그대로라 한 줄 글 배치는 전과 같다.
class FirstLineIcon extends StatelessWidget {
  const FirstLineIcon(
    this.icon, {
    super.key,
    required this.size,
    this.color,
    this.textStyle,
  });

  final IconData icon;
  final double size;
  final Color? color;

  /// 옆 글의 스타일(글자 크기 · 높이). null 이면 DefaultTextStyle 만 쓴다.
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(textStyle);
    final tp = TextPainter(
      text: TextSpan(text: '가', style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final lineHeight = tp.height;
    tp.dispose();
    final box = lineHeight > size ? lineHeight : size;
    return SizedBox(
      width: size,
      height: box,
      child: Center(child: Icon(icon, size: size, color: color)),
    );
  }
}
