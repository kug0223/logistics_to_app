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
  /// asSliver=true일 때 화면 중앙 대신 상단 기준으로 배치
  final bool topAligned;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconColor,
    this.action,
    this.asSliver = false,
    this.topAligned = false,
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
            // grey600(#757575) — 빈 상태 메인 메시지는 사용자가 읽어야 할 정보.
            // 아이콘·부제목이 연한 것과 달리 제목만 한 단계 진하게 처리.
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              color: AppColors.grey600,
              fontWeight: FontWeight.w600,
            ),
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
      if (topAligned) {
        // 필터 칩 아래 ~44px 지점에서 빈 상태 시작 — 화면 중앙 정렬 없이 상단 기준 배치
        // inner padding(32) + this top(12) = ~44px → 필터에서 아이콘까지 자연스러운 여백
        return SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(
              top: ResponsiveHelper.spacing(context, 12),
            ),
            child: inner,
          ),
        );
      }
      // hasScrollBody: false → 남은 viewport를 정확히 채움 (스크롤 오버플로 없음)
      // Center가 남은 영역 안에서 콘텐츠를 수직 중앙 정렬
      // 홈 인디케이터(SafeArea bottom) 영역은 하단 패딩으로 보호
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom,
          ),
          child: Center(child: inner),
        ),
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
