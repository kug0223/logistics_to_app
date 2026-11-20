import 'package:flutter/widgets.dart';

import '../../utils/text_layout.dart';

/// [DU364] 원문 보존 낱말 조판 글 — `data` 는 **원문 그대로**(화면 찾기 · 낭독 기준), 그릴 때만 낱말 단위로 줄을 바꾼다.
///
/// 글 자체에 WJ 를 넣는 `Text(TextLayout.keepWords(s))` 는 원문으로 찾는 곳(`find.text` 등)을 0개로 만들고
/// '보이지 않아야 한다'(findsNothing) 단언을 늘 참으로 만든다. 안쪽에 Text 를 하나 더 두면 Text 위젯 대상 찾기가
/// 2개를 센다(DU357 r1 · r2). 그래서 Text 는 이것 하나이고, [Text.build] 가 만든 RichText 의 글만 바꾼다.
///
/// - 정렬 · 줄 수 · 넘침 · 줄바꿈 허용 · 스타일은 [Text.build] 결과 그대로 쓴다.
/// - 낭독은 원문이다(Semantics label = data). 별도 semanticsLabel 은 받지 않는다.
/// - 선택 영역 안 등 RichText 가 아닌 구조면 원문 그대로 둔다(조판 없음).
/// - 첫 소비자: 공용 토스트(toast_helper). 전역 교체는 하지 않는다 — 소비자를 하나씩 정한다.
class KeepWordsText extends Text {
  const KeepWordsText(
    super.data, {
    super.key,
    super.style,
    super.textAlign,
    super.softWrap,
    super.overflow,
    super.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    final base = super.build(context);
    if (base is! RichText || base.text is! TextSpan) return base;
    final span = base.text as TextSpan;
    return Semantics(
      label: data,
      child: ExcludeSemantics(
        child: RichText(
          text: TextSpan(style: span.style, text: TextLayout.keepWords(data!), locale: span.locale),
          textAlign: base.textAlign,
          textDirection: base.textDirection,
          softWrap: base.softWrap,
          overflow: base.overflow,
          textScaler: base.textScaler,
          maxLines: base.maxLines,
          locale: base.locale,
          strutStyle: base.strutStyle,
          textWidthBasis: base.textWidthBasis,
          textHeightBehavior: base.textHeightBehavior,
          selectionColor: base.selectionColor,
        ),
      ),
    );
  }
}
