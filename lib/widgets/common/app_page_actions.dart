// lib/widgets/common/app_page_actions.dart
//
// [R7-P3-4] flat shell(`AppPageScaffold`)의 우상단 표준 액션.
//
// `GradientScaffold` 는 새로고침·홈·알림 버튼을 **스스로** 그렸다. flat shell 은
// 그것들을 caller 가 `actions` 로 넘기는 구조여서, 전환할 때마다 같은 세 버튼을
// 손으로 다시 쓰게 된다(관리자 화면들이 이미 그렇게 하고 있다).
// 여기서 한 벌로 만든다 — 인라인 재작성을 늘리지 않기 위해서다.
//
// 바꾸지 않은 것:
//   · 새로고침은 **우상단 버튼**이다. 당겨서 새로고침으로 의미를 바꾸지 않는다.
//   · 알림은 `NotificationScreen`, 홈은 `NavigationHelper.goHome` — 목적지 동일.
//   · 알림 벨은 `NotificationBadge` 로 감싼다(읽지 않은 수 표시 유지).
//
// 기존 flat 화면의 인라인 actions 는 건드리지 않는다 — 이 파일은 새 소비자만 쓴다.
import 'package:flutter/material.dart';

import '../../screens/common/notification_screen.dart';
import '../../theme/app_colors.dart';
import '../../utils/navigation_helper.dart';
import 'notification_badge.dart';

/// flat AppBar 에 올릴 표준 액션 목록.
///
/// [onRefresh] 가 null 이면 새로고침 버튼을 만들지 않는다 —
/// `GradientScaffold.onRefresh == null` 과 같은 뜻이다.
List<Widget> appPageActions(
  BuildContext context, {
  VoidCallback? onRefresh,
  bool showHomeButton = true,
  bool showNotificationBell = true,
}) {
  return [
    if (onRefresh != null)
      IconButton(
        icon: const Icon(Icons.refresh),
        onPressed: onRefresh,
        color: AppColors.textSecondary,
        tooltip: '새로고침',
      ),
    if (showHomeButton)
      IconButton(
        icon: const Icon(Icons.home_outlined),
        onPressed: () => NavigationHelper.goHome(context),
        color: AppColors.textSecondary,
        tooltip: '홈으로',
      ),
    if (showNotificationBell)
      NotificationBadge(
        child: IconButton(
          icon: const Icon(Icons.notifications_outlined),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NotificationScreen()),
          ),
          color: AppColors.textSecondary,
          tooltip: '알림',
        ),
      ),
  ];
}
