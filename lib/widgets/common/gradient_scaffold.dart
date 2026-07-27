// lib/widgets/common/gradient_scaffold.dart
//
// 지원자 화면 공통 레이아웃
// - 파란 그라디언트 헤더 + 상단 32px 곡선 콘텐츠 영역
// - 홈화면·내 스케줄·공고 찾기와 동일한 디자인 언어

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/navigation_helper.dart';
import '../../screens/common/notification_screen.dart';
import '../../screens/user/user_contracts_screen.dart';
import '../../providers/user_provider.dart';
import 'notification_badge.dart';

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
  /// 우상단 새로고침 버튼 콜백 — null이면 버튼 미표시
  final VoidCallback? onRefresh;
  /// FloatingActionButton (선택)
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  /// 우상단 알림 벨 아이콘 표시 여부 (기본 true)
  final bool showNotificationBell;
  /// 우상단 홈 아이콘 표시 여부 (기본 true) — 홈 화면 자체에서는 false로 설정
  final bool showHomeButton;
  /// 미서명 계약서 노란 바 표시 여부 (기본 true) — 계약서 화면·목록 화면은 false로 설정
  final bool showPendingContractBar;

  const GradientScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.headerContent,
    this.headerBottom,
    this.contentColor = AppColors.grey50,
    this.onBack,
    this.onRefresh,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.showNotificationBell = true,
    this.showHomeButton = true,
    this.showPendingContractBar = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      bottomNavigationBar: _buildPendingContractBar(context),
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
                    if (showHomeButton) ...[
                      _buildHomeButton(context),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    ],
                    if (showNotificationBell) _buildNotificationBell(context),
                    if (onRefresh != null) ...[
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                      _buildRefreshButton(context),
                    ],
                    if (actions != null) ...[
                      if (showHomeButton || showNotificationBell || onRefresh != null)
                        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                      ...actions!,
                    ],
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
                  clipBehavior: Clip.antiAlias,
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

  Widget? _buildPendingContractBar(BuildContext context) {
    if (!showPendingContractBar) return null;
    UserProvider? userProvider;
    try {
      userProvider = Provider.of<UserProvider>(context);
    } catch (_) {
      return null;
    }
    if (!userProvider.isUser || !userProvider.hasPendingContract) return null;
    final count = userProvider.pendingContractCount;
    return SafeArea(
      top: false,
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const UserContractsScreen()),
        ),
        child: Container(
          width: double.infinity,
          color: const Color(0xFFFFF3CD),
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 16),
            vertical: ResponsiveHelper.spacing(context, 12),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Color(0xFF856404), size: 18),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Expanded(
                child: Text(
                  '미서명 계약서 $count건이 있습니다. 탭하여 확인하세요.',
                  style: ResponsiveHelper.smallStyle(context).copyWith(
                    color: const Color(0xFF664D03),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: Color(0xFF856404), size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHomeButton(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(12),
      child: Semantics(
        label: '홈으로',
        button: true,
        child: InkWell(
          onTap: () => NavigationHelper.goHome(context),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
            child: Icon(Icons.home_outlined,
                color: Colors.white,
                size: ResponsiveHelper.iconSize(context, 24)),
          ),
        ),
      ),
    );
  }

  Widget _buildRefreshButton(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(12),
      child: Semantics(
        label: '새로고침',
        button: true,
        child: InkWell(
          onTap: onRefresh,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
            child: Icon(Icons.refresh,
                color: Colors.white,
                size: ResponsiveHelper.iconSize(context, 24)),
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationBell(BuildContext context) {
    return NotificationBadge(
      child: Material(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        child: Semantics(
          label: '알림',
          button: true,
          child: InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationScreen()),
            ),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
              child: Icon(Icons.notifications_outlined,
                  color: Colors.white,
                  size: ResponsiveHelper.iconSize(context, 24)),
            ),
          ),
        ),
      ),
    );
  }
}
