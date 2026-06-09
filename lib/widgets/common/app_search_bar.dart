// lib/widgets/common/app_search_bar.dart

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';

/// 앱 전체 공통 검색바
/// StatelessWidget + ValueListenableBuilder — 키 입력마다 X버튼만 재빌드
class AppSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;
  final EdgeInsets? padding;
  final Color? backgroundColor;

  const AppSearchBar({
    super.key,
    required this.controller,
    required this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.padding,
    this.backgroundColor,
  });

  void _handleClear() {
    controller.clear();
    onClear?.call();
    onChanged?.call('');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: backgroundColor ?? Colors.white,
      padding: padding ??
          EdgeInsets.fromLTRB(
            ResponsiveHelper.spacing(context, 12),
            ResponsiveHelper.spacing(context, 8),
            ResponsiveHelper.spacing(context, 12),
            ResponsiveHelper.spacing(context, 8),
          ),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: ResponsiveHelper.bodyStyle(context, color: AppColors.grey400),
          prefixIcon: const Icon(Icons.search, color: AppColors.grey400),
          // X버튼만 ValueListenableBuilder로 격리 — 키 입력마다 전체 rebuild 방지
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, value, __) => value.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18, color: AppColors.grey400),
                    onPressed: _handleClear,
                  )
                : const SizedBox.shrink(),
          ),
          filled: true,
          fillColor: AppColors.grey50,
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.4),
                width: 1),
          ),
        ),
        textInputAction: TextInputAction.search,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
      ),
    );
  }
}
