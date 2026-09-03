// lib/widgets/common/app_page_scaffold.dart
//
// ALfit flat screen foundation — role-independent minimal scaffold.
// ADMIN flat header 표준. GradientScaffold의 신규 ADMIN 화면 대안.
//
// 설계 원칙:
// - Business-agnostic: 도메인 파라미터 없음
// - 홈/알림 버튼은 actions 파라미터로 caller가 전달 (재사용·테스트 용이)
// - AppBar(elevation:0, white) + 1px grey200 divider

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class AppPageScaffold extends StatelessWidget {
  const AppPageScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
    this.bottom,
    this.backgroundColor,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.resizeToAvoidBottomInset = true,
  });

  final String title;
  final Widget body;

  /// AppBar 우상단 액션 목록 (홈·알림·새로고침 등 caller가 전달)
  final List<Widget> actions;

  /// AppBar 하단 위젯 — TabBar 등 PreferredSizeWidget.
  /// 전달 시 내부에서 1px grey200 divider가 자동으로 아래에 추가됨.
  /// null이면 AppBar 아래 1px divider만 표시.
  final PreferredSizeWidget? bottom;

  /// 화면 배경색 (기본: AppColors.background = grey100)
  final Color? backgroundColor;

  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final bool resizeToAvoidBottomInset;

  static const _titleStyle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
    letterSpacing: -0.5,
  );

  @override
  Widget build(BuildContext context) {
    PreferredSizeWidget effectiveBottom;
    if (bottom != null) {
      effectiveBottom = _BottomWithDivider(content: bottom!);
    } else {
      effectiveBottom = const _SingleDivider();
    }

    return Scaffold(
      backgroundColor: backgroundColor ?? AppColors.background,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Text(title, style: _titleStyle),
        actions: actions.isEmpty
            ? null
            : [...actions, const SizedBox(width: 4)],
        bottom: effectiveBottom,
      ),
      body: body,
    );
  }
}

/// AppBar bottom이 없을 때 표시되는 1px 구분선
class _SingleDivider extends StatelessWidget implements PreferredSizeWidget {
  const _SingleDivider();

  @override
  Size get preferredSize => const Size.fromHeight(1);

  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: AppColors.grey200);
}

/// TabBar 등 PreferredSizeWidget 아래에 1px 구분선을 추가하는 래퍼
class _BottomWithDivider extends StatelessWidget implements PreferredSizeWidget {
  const _BottomWithDivider({required this.content});

  final PreferredSizeWidget content;

  @override
  Size get preferredSize => Size.fromHeight(content.preferredSize.height + 1);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        content,
        Container(height: 1, color: AppColors.grey200),
      ],
    );
  }
}
