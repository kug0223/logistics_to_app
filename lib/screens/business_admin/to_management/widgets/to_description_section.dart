import 'package:flutter/material.dart';
import '../../../../utils/responsive_helper.dart';
import 'to_section_container.dart';
import '../../../../theme/app_colors.dart';

/// ✨ TO 설명 입력 섹션
/// create_to_screen, edit_to_screen에서 공통으로 사용
class TODescriptionSection extends StatelessWidget {
  final TextEditingController controller;
  final String? labelText;
  final String? hintText;
  final int maxLines;

  const TODescriptionSection({
    super.key,
    required this.controller,
    this.labelText,
    this.hintText,
    this.maxLines = 5,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TOSectionContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            labelText ?? '상세 설명 (선택)',
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          TextFormField(
            controller: controller,
            maxLines: maxLines,
            style: ResponsiveHelper.bodyStyle(context),
            decoration: InputDecoration(
              hintText: hintText ?? '추가 안내사항을 입력하세요',
              hintStyle: ResponsiveHelper.smallStyle(
                context,
                color: AppColors.grey400,
              ),
              alignLabelWithHint: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.grey300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.grey300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: theme.primaryColor, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
