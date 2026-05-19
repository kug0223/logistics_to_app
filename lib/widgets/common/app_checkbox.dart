import 'package:flutter/material.dart';
import '../../utils/responsive_helper.dart';
import '../../theme/app_colors.dart';

/// 앱 공통 체크박스 위젯
///
/// 모든 다이얼로그·화면의 선택 UI에서 일관된 아이콘 스타일을 제공.
/// - 선택됨: [Icons.check_circle_rounded] (활성 색상)
/// - 미선택: [Icons.radio_button_unchecked] (grey300)
/// - 비활성: [Icons.radio_button_unchecked] (grey200)
///
/// [onTap]이 null이면 GestureDetector 없이 Icon만 반환 — 부모 InkWell이
/// 행 전체를 처리하는 경우(리스트 아이템 등) 사용.
class AppCheckbox extends StatelessWidget {
  final bool value;

  /// null이면 부모 위젯의 탭 이벤트에 위임 (Icon만 렌더)
  final VoidCallback? onTap;

  /// 기본값: ResponsiveHelper.iconSize(context, 22)
  final double? size;

  /// 선택 상태 색상. 기본: Theme.primaryColor
  final Color? activeColor;

  /// false이면 회색 처리, onTap 무시
  final bool enabled;

  const AppCheckbox({
    super.key,
    required this.value,
    this.onTap,
    this.size,
    this.activeColor,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = value
        ? (activeColor ?? Theme.of(context).primaryColor)
        : (enabled ? AppColors.grey300 : AppColors.grey200);

    final icon = Icon(
      value ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
      size: size ?? ResponsiveHelper.iconSize(context, 22),
      color: effectiveColor,
    );

    if (onTap == null) return icon;

    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: icon,
    );
  }
}
