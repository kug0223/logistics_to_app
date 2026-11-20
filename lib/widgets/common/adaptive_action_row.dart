import 'package:flutter/material.dart';

import '../../utils/text_layout.dart';

/// [COMMON-TEXT-LAYOUT.28] 안내(아이콘·문구) + 행동 버튼 한 줄.
///
///   폭이 넉넉하면 지금처럼 한 줄(안내 왼쪽 · 버튼 오른쪽). 영역 폭이 [minRowWidth](글자 배율 1.0 기준)
///   × 사용자 글자 배율보다 좁으면 안내를 위에, 버튼을 그 아래 오른쪽에 둔다 — 두 글자 모두 줄이지
///   않는다. 예전에는 둘이 한 줄을 나눠 '요청 가능 / 6명', 버튼 '계약서 일괄작 / 성' 처럼 갈렸다.
///   표시만 — 버튼이 무엇을 하는지는 [actions] 를 준 쪽이 정한다.
class AdaptiveActionRow extends StatelessWidget {
  final Widget leading;
  final List<Widget> actions;
  final double minRowWidth;
  final double gap;

  const AdaptiveActionRow({
    super.key,
    required this.leading,
    required this.actions,
    required this.minRowWidth,
    this.gap = 8,
  });

  @override
  Widget build(BuildContext context) {
    final buttons = Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < actions.length; i++) ...[
        if (i > 0) SizedBox(width: gap),
        actions[i],
      ],
    ]);
    return LayoutBuilder(builder: (context, c) {
      if (!c.hasBoundedWidth || TextLayout.fits(context, c.maxWidth, minRowWidth)) {
        return Row(children: [
          Expanded(child: leading),
          if (actions.isNotEmpty) ...[SizedBox(width: gap), buttons],
        ]);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          if (actions.isNotEmpty) ...[
            SizedBox(height: gap),
            // [DU1-B2] 쌓인 배치에서도 버튼 묶음이 한 줄 Row 라 버튼이 여럿이면 넘쳤다(긴 명단 320dp·2.0, 11px).
            //   버튼을 줄이지 않고 오른쪽 정렬 Wrap 으로 다음 줄에 둔다. 한 줄 배치(위)는 그대로.
            Wrap(
              alignment: WrapAlignment.end,
              spacing: gap,
              runSpacing: gap,
              children: actions,
            ),
          ],
        ],
      );
    });
  }
}
