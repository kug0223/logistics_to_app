// lib/widgets/common/app_search_bar.dart

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/text_layout.dart';

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

  /// [DU432] 안내 글 최대 줄 수 — null(기본)이면 예전 경로 그대로다(hintText · 한 줄 · 말줄임 · 칸 세로 여백 0).
  ///   값을 주면 다음처럼 바뀐다.
  ///   - 안내를 낱말 사이에서만(keepWords) 그 줄 수까지 바꾸고, 화면 읽기는 원문(semanticsLabel)이다.
  ///   - 글꼴 · 줄 높이는 기본 안내와 같다.
  ///   - 칸 위아래 여백을 두어 두 줄 안내가 칸 가장자리에 붙지 않게 한다.
  ///   - 입력 중에는 안내 높이를 붙잡지 않는다(maintainHintSize false). 입력 글자가 아이콘과 같은 높이에 오고 칸이 보통 높이로 돌아온다.
  final int? hintMaxLines;

  const AppSearchBar({
    super.key,
    required this.controller,
    required this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.padding,
    this.backgroundColor,
    this.hintMaxLines,
  });

  void _handleClear() {
    controller.clear();
    onClear?.call();
    onChanged?.call('');
  }

  @override
  Widget build(BuildContext context) {
    final hintStyle = ResponsiveHelper.bodyStyle(context, color: AppColors.textTertiary);
    final multiLineHint = hintMaxLines != null;
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
          hintText: multiLineHint ? null : hintText,
          // [DU432] InputDecorator 는 hintText 에 bodyLarge 위로 hintStyle 을 덧씌운다 — hint 위젯에도 같은 덧씌움을 줘 글꼴 · 줄 높이를 맞춘다.
          hint: multiLineHint
              ? Text(
                  TextLayout.keepWords(hintText),
                  semanticsLabel: hintText,
                  maxLines: hintMaxLines,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge?.merge(hintStyle) ?? hintStyle,
                )
              : null,
          maintainHintSize: !multiLineHint,
          // [DU342] 안내 글자 grey400(1.88) → textTertiary(DU326 로그인 안내와 같다), 아이콘 grey400 → grey600
          hintStyle: hintStyle,
          prefixIcon: const Icon(Icons.search, color: AppColors.grey600),
          // X버튼만 ValueListenableBuilder로 격리 — 키 입력마다 전체 rebuild 방지
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, value, __) => value.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18, color: AppColors.grey600),
                    onPressed: _handleClear,
                  )
                : const SizedBox.shrink(),
          ),
          filled: true,
          fillColor: AppColors.grey50,
          // [DU432] 여러 줄 안내일 때만 세로 여백 — 한 줄 칸(48)은 그대로이고, 두 줄 안내는 위아래로 띄운다.
          contentPadding: EdgeInsets.symmetric(vertical: multiLineHint ? ResponsiveHelper.spacing(context, 10) : 0, horizontal: 12),
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
