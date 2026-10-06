// lib/widgets/common/viewport_fill_surface.dart
//
// [BOTTOM-SURFACE-FILL] 전폭 섹션 면으로 구성된 스크롤 화면에서, 내용이
// 뷰포트보다 짧을 때 남는 공간의 주인을 정한다.
//
// 문제: `SingleChildScrollView`의 자식은 내용 높이만큼만 자리를 차지한다.
// 그 아래 남은 영역에는 아무것도 그려지지 않으므로 `Scaffold.backgroundColor`
// (회색)가 드러난다. 화면이 카드-온-회색 구성이면 그것이 정상적인 캔버스지만,
// 전폭 흰 섹션 구성에서는 "흰 면이 중간에 끊기고 그 아래 빈 슬롯이 있다"처럼
// 읽힌다. **내용이 없는 것과 자리가 비어 있는 것은 다른 말이다.**
//
// 해법: 스크롤 자식에게 뷰포트 높이를 **최솟값으로만** 준다. 내용이 짧으면
// 면이 뷰포트 끝까지 이어지고, 길면 아무 영향이 없다(상한을 주지 않는다).
//
// 쓰지 않은 것: 고정 높이 봉투 · 화면 높이별 분기 · Scaffold 축소 ·
// 하단 바 끌어올리기 · `IntrinsicHeight`(스크롤 본문 전체에 intrinsic 패스를
// 추가하는 비용을 피한다).
//
// 다른 화면 대부분은 `Expanded`로 본문을 채우므로 이 위젯이 필요 없다.
// 스크롤이 필요하면서 면이 전폭인 화면에만 쓴다.

import 'package:flutter/material.dart';

class ViewportFillSurface extends StatelessWidget {
  const ViewportFillSurface({
    super.key,
    required this.child,
    this.color = Colors.white,
    this.physics,
  });

  /// 스크롤 본문. 내용이 짧으면 뷰포트 높이까지 늘어난다.
  final Widget child;

  /// 남은 영역에 이어 붙일 면 색 — 섹션 면과 같은 색을 쓴다.
  final Color color;

  /// 호출부의 스크롤 동작을 그대로 통과시킨다. 봉투가 기본값을 들고 있으면
  /// 적용하는 화면의 스크롤 성질이 조용히 바뀐다 — null 이면 기존과 같다.
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, viewport) => SingleChildScrollView(
        physics: physics,
        child: ConstrainedBox(
          // 최솟값만 준다 — 긴 내용은 그대로 넘어가 스크롤된다.
          constraints: BoxConstraints(minHeight: viewport.maxHeight),
          // alignment를 주지 않는다. 그래야 Container가 제약을 그대로
          // 자식에게 넘기고, 자식이 minHeight까지 자라며 색이 그 전체를
          // 덮는다. alignment를 주면 자식이 내용 높이로 줄어든다.
          child: Container(color: color, child: child),
        ),
      ),
    );
  }
}
