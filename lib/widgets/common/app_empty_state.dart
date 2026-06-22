// lib/widgets/common/app_empty_state.dart
//
// 앱 전체 공통 빈 상태 위젯
// ─────────────────────────────────────────
// 사용법:
//   AppEmptyState(
//     icon: Icons.inbox_outlined,
//     title: '데이터가 없습니다',
//     subtitle: '새로운 항목을 추가해보세요',     // 선택
//     action: TextButton(...),                   // 선택
//   )
//
// 표준값:
//   - 아이콘 크기: 56 (전체 공통)
//   - 아이콘 색상: AppColors.grey300 (기본)
//   - 제목: subtitleStyle + grey500
//   - 부제목: smallStyle + grey400

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';

class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? iconColor;
  final Widget? action;
  /// Sliver 환경에서 사용할 때 true (SliverFillRemaining 래핑)
  final bool asSliver;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconColor,
    this.action,
    this.asSliver = false,
  });

  @override
  Widget build(BuildContext context) {
    final inner = Padding(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 32)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: ResponsiveHelper.iconSize(context, 56),
            color: iconColor ?? AppColors.grey300,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          Text(
            title,
            style: ResponsiveHelper.subtitleStyle(context)
                .copyWith(color: AppColors.grey500),
            textAlign: TextAlign.center,
          ),
          if (subtitle case final subtitle? when subtitle.isNotEmpty) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            Text(
              subtitle,
              style: ResponsiveHelper.smallStyle(context,
                  color: AppColors.grey400),
              textAlign: TextAlign.center,
            ),
          ],
          if (action != null) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            action!,
          ],
        ],
      ),
    );

    if (asSliver) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: inner),
      );
    }

    // 가로 모드처럼 공간이 좁을 때 overflow 방지:
    // 공간이 충분하면 Center로 중앙 정렬, 부족하면 스크롤
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: inner),
          ),
        );
      },
    );
  }
}
