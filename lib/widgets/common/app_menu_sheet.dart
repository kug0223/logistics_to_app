import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';
import '../dialogs/styled_dialog.dart';

// ─────────────────────────────────────────────────────────
// AppMenuSheetItem — 바텀시트 메뉴 항목 하나를 정의
// ─────────────────────────────────────────────────────────

class AppMenuSheetItem {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool isDanger;

  const AppMenuSheetItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.isDanger = false,
  });
}

// ─────────────────────────────────────────────────────────
// AppMenuSheet — 공통 바텀시트 액션 메뉴
//
// 사용 예:
//   AppMenuSheet.show(
//     context: context,
//     headerTitle: '홍길동',
//     headerSubtitle: '냉동분류  18:00~22:30',
//     headerAvatarLetter: '홍',
//     headerAvatarColor: theme.primaryColor,
//     itemGroups: [
//       [
//         AppMenuSheetItem(icon: Icons.person_outline, label: '상세보기',
//             color: theme.primaryColor, onTap: () { ... }),
//       ],
//       [
//         AppMenuSheetItem(icon: Icons.login, label: '출근 처리',
//             color: AppColors.success, onTap: () { ... }),
//         AppMenuSheetItem(icon: Icons.person_off_outlined, label: '노쇼 처리',
//             color: AppColors.error, isDanger: true, onTap: () { ... }),
//       ],
//     ],
//   );
//
// itemGroups: 2D 리스트. 각 그룹 사이에 구분선이 자동으로 삽입됨.
// ─────────────────────────────────────────────────────────

class AppMenuSheet {
  AppMenuSheet._();

  static Future<void> show({
    required BuildContext context,
    String? headerTitle,
    String? headerSubtitle,
    String? headerAvatarLetter,
    Color? headerAvatarColor,
    required List<List<AppMenuSheetItem>> itemGroups,
  }) {
    return showModalBottomSheet(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _AppMenuSheetContent(
        headerTitle: headerTitle,
        headerSubtitle: headerSubtitle,
        headerAvatarLetter: headerAvatarLetter,
        headerAvatarColor: headerAvatarColor,
        itemGroups: itemGroups,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 내부 위젯
// ─────────────────────────────────────────────────────────

class _AppMenuSheetContent extends StatelessWidget {
  final String? headerTitle;
  final String? headerSubtitle;
  final String? headerAvatarLetter;
  final Color? headerAvatarColor;
  final List<List<AppMenuSheetItem>> itemGroups;

  const _AppMenuSheetContent({
    this.headerTitle,
    this.headerSubtitle,
    this.headerAvatarLetter,
    this.headerAvatarColor,
    required this.itemGroups,
  });

  @override
  Widget build(BuildContext context) {
    final hasHeader = headerTitle != null || headerSubtitle != null;

    final maxHeight = MediaQuery.sizeOf(context).height * AppDialogSize.subSheetHeightRatio;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 핸들바 (고정)
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.grey300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            // 헤더 (고정, 선택)
            if (hasHeader) ...[
              _Header(
                title: headerTitle,
                subtitle: headerSubtitle,
                avatarLetter: headerAvatarLetter,
                avatarColor: headerAvatarColor ?? Theme.of(context).primaryColor,
              ),
              const SizedBox(height: 16),
              Divider(height: 1, color: AppColors.grey100),
              const SizedBox(height: 8),
            ],

            // 스크롤 가능한 메뉴 목록
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int i = 0; i < itemGroups.length; i++) ...[
                      if (i > 0) ...[
                        const SizedBox(height: 4),
                        Divider(height: 1, color: AppColors.grey100, indent: 20, endIndent: 20),
                        const SizedBox(height: 4),
                      ],
                      for (final item in itemGroups[i])
                        _MenuItem(item: item),
                    ],
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 헤더 위젯
// ─────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final String? avatarLetter;
  final Color avatarColor;

  const _Header({
    this.title,
    this.subtitle,
    this.avatarLetter,
    required this.avatarColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Container(
            width: ResponsiveHelper.spacing(context, 48),
            height: ResponsiveHelper.spacing(context, 48),
            decoration: BoxDecoration(
              color: avatarColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                avatarLetter?.isNotEmpty == true ? avatarLetter! : '?',
                style: ResponsiveHelper.subtitleStyle(context).copyWith(
                  color: avatarColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Text(
                    title!,
                    style: ResponsiveHelper.subtitleStyle(context).copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 개별 메뉴 항목 위젯
// ─────────────────────────────────────────────────────────

class _MenuItem extends StatelessWidget {
  final AppMenuSheetItem item;

  const _MenuItem({required this.item});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.pop(context);
          // pop이 완료된 다음 프레임에서 실행해야 바텀시트 dispose 중
          // InheritedElement._dependents 정리가 끝나 assertion 에러를 피할 수 있음
          WidgetsBinding.instance.addPostFrameCallback((_) => item.onTap());
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            children: [
              Container(
                width: ResponsiveHelper.spacing(context, 44),
                height: ResponsiveHelper.spacing(context, 44),
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(item.icon, color: item.color, size: ResponsiveHelper.iconSize(context, 22)),
              ),
              const SizedBox(width: 16),
              Text(
                item.label,
                style: ResponsiveHelper.bodyStyle(context,
                  color: item.isDanger ? AppColors.error : AppColors.grey800,
                ).copyWith(fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              Icon(Icons.chevron_right, color: AppColors.grey300, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
