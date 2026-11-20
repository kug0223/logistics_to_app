import 'package:flutter/material.dart';

import '../../utils/responsive_helper.dart';

/// [COMMON-TEXT-LAYOUT.28] 상태 문구 + 건수 + (누를 수 있으면) 화살표 — **한 단위**.
///
///   칩 안에서는 줄을 바꾸지 않는다('퇴근미확인 3 / ›' 처럼 화살표만 내려가지 않게). 공간이 모자라면
///   부모 `Wrap` 이 칩 전체를 다음 줄로 보낸다. 글자를 줄이지 않는다.
///   누르는 영역은 글자보다 넓게(위아래 여백) 둔다. 표시만 — 무엇을 열지는 [onTap] 을 준 쪽이 정한다.
class CountChip extends StatelessWidget {
  final String label;
  final Color color;

  /// [DU427] 바탕 — 주면 그 색(앱 기준 상태 짝의 Bg 토큰), 없으면 예전처럼 글자색 12%.
  final Color? background;
  final VoidCallback? onTap;

  const CountChip({
    super.key,
    required this.label,
    required this.color,
    this.background,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 6),
        vertical: ResponsiveHelper.spacing(context, 2),
      ),
      decoration: BoxDecoration(
        color: background ?? color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      // [.29] 화면 읽기는 '›' 를 읽지 않고 문구만 — 누를 수 있다는 것은 버튼 역할로 알린다.
      child: Text(onTap != null ? '$label ›' : label,
          semanticsLabel: label,
          softWrap: false,
          style: ResponsiveHelper.tinyStyle(context, color: color, fontWeight: FontWeight.w600)),
    );
    if (onTap == null) return chip;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: chip),
      ),
    );
  }
}
