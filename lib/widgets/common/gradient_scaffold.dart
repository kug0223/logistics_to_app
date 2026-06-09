// lib/widgets/common/gradient_scaffold.dart
//
// 지원자 화면 공통 레이아웃
// - 파란 그라디언트 헤더 + 상단 32px 곡선 콘텐츠 영역
// - 홈화면·내 스케줄·공고 찾기와 동일한 디자인 언어

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';

class GradientScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;
  /// 제목 행 아래, 흰 곡선 컨테이너 위에 표시 — 파란 배경 영역 (프로필 등)
  final Widget? headerContent;
  /// 헤더 아래, 흰 곡선 컨테이너 위에 표시 (TabBar 등) — Deprecated, headerContent 권장
  final PreferredSizeWidget? headerBottom;
  /// 콘텐츠 영역 배경색 (기본 grey50)
  final Color contentColor;

  /// 뒤로가기 버튼 콜백 — null이면 Navigator.pop() 기본 동작
  final VoidCallback? onBack;
  /// FloatingActionButton (선택)
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;

  const GradientScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.headerContent,
    this.headerBottom,
    this.contentColor = AppColors.grey50,
    this.onBack,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.primaryColor,
              theme.primaryColor.withValues(alpha: 0.85),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── 파란 헤더 영역
              // ── 제목 행
              Padding(
                padding: EdgeInsets.fromLTRB(
                  ResponsiveHelper.spacing(context, 4),
                  ResponsiveHelper.spacing(context, 8),
                  ResponsiveHelper.spacing(context, 12),
                  (headerContent != null || headerBottom != null)
                      ? ResponsiveHelper.spacing(context, 4)
                      : ResponsiveHelper.spacing(context, 16),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: onBack ?? () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Text(
                        title,
                        style: ResponsiveHelper.titleStyle(context).copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (actions != null) ...actions!,
                  ],
                ),
              ),

              // ── 파란 배경 영역 추가 콘텐츠 (프로필 카드 등)
              if (headerContent != null) headerContent!,

              // ── TabBar 등 (레거시 호환)
              if (headerBottom != null) headerBottom!,

              // ── 곡선 콘텐츠 영역
              Expanded(
                child: Container(
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(
                    color: contentColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(32),
                      topRight: Radius.circular(32),
                    ),
                  ),
                  child: body,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
