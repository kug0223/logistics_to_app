import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';

/// 텍스트 + 카운트 배지로 구성된 탭 라벨 공통 위젯
///
/// TabBar의 Tab(child: AppTabLabel(...)) 형태로 사용
/// count가 null이면 배지 없이 텍스트만 표시
class AppTabLabel extends StatelessWidget {
  final String label;

  /// null이면 배지 미표시
  final int? count;

  /// null이면 theme.primaryColor 사용
  final Color? badgeColor;

  /// true면 배지가 solid red로 강조 (예: 미완료 항목이 있을 때)
  final bool urgent;

  /// count 뒤에 붙는 접미사 (예: "+" — 더 많은 항목이 있음을 표시)
  final String countSuffix;

  const AppTabLabel({
    super.key,
    required this.label,
    this.count,
    this.badgeColor,
    this.urgent = false,
    this.countSuffix = '',
  });

  @override
  Widget build(BuildContext context) {
    if (count == null && !urgent) {
      return Text(label);
    }

    final effectiveColor = badgeColor ?? Theme.of(context).primaryColor;
    final displayCount = count ?? 0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // [R7-P1-3] 라벨도 좁은 폭에서 양보해야 한다.
        //   배지는 Flexible + FittedBox 였지만 라벨은 고정이어서, 320dp·글자배율
        //   1.3 에서 이 Row 가 4.9px 넘쳤다(탭 3개 동시, 실측). 배율을 끄거나
        //   글자를 축소해 덮지 않고, 프로젝트 규칙대로 Row 안에서 양보시킨다.
        //   숫자 배지는 그대로 보인다 — 눌러야 할 것이 가려지지 않는다.
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 3)),
        // Flexible: 좁은 화면(320dp 등)에서 배지가 Row 범위를 초과하지 않도록 압축
        Flexible(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 3),
              vertical: ResponsiveHelper.spacing(context, 2),
            ),
            decoration: BoxDecoration(
              color: urgent
                  ? AppColors.error
                  : effectiveColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            // FittedBox: 배지 공간이 좁을 때 count 숫자를 스케일다운 (overflow 방지)
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '$displayCount$countSuffix',
                style: ResponsiveHelper.tinyStyle(
                  context,
                  color: urgent ? Colors.white : effectiveColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
