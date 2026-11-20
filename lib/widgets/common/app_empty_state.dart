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
//   - 아이콘 색상: AppColors.grey300 (기본, 장식)
//   - 제목: subtitleStyle + textSecondary(#60646F) w600  [DU248] 이전 grey600 — 화면 바탕 위 4.3 으로 읽기 기준 미달
//   - 부제목: smallStyle + textTertiary(#686C77)        [DU248] 이전 grey400 — 화면 바탕 위 1.75

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/text_layout.dart';

class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? iconColor;
  /// [DU231 F7] 부제목 글자색. 사용자가 읽고 따라야 하는 안내 부제(공고 탭 상태 화면)는 호출자가 textSecondary 를 고른다.
  ///   [DU248] null 이면 textTertiary(#686C77, 화면 바탕 4.90·흰 5.25) — 이전 기본 grey400(1.75)은 읽히지 않았다(사용자 11-10 앱 전체 결정).
  final Color? subtitleColor;
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
    this.subtitleColor,
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
          // [UI-BALANCE.38] 좁은 폭·큰 글자에서 '못했습 / 니다.' 처럼 음절 단위로 끊겼다(.33·.34 기기).
          //   제목·부제목은 낱말 사이에서만 줄을 바꾼다(표시만 — 화면 읽기는 원문). 글자 크기·여백·문구는 그대로.
          Text(
            TextLayout.keepWords(title),
            semanticsLabel: title,
            // 빈 상태 메인 메시지는 사용자가 읽어야 할 정보 — 부제목보다 한 단계 진하게.
            // [DU248] grey600(#757575, 화면 바탕 4.3) → textSecondary(#60646F, 5.52). 사용자 11-10 '권장방향으로 진행'.
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          if (subtitle case final subtitle? when subtitle.isNotEmpty) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            Text(
              TextLayout.keepWords(subtitle),
              semanticsLabel: subtitle,
              style: ResponsiveHelper.smallStyle(context,
                  color: subtitleColor ?? AppColors.textTertiary), // [DU248] 이전 grey400
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
