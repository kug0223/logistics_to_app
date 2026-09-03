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
            labelText ?? '공통 안내 (선택)',
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
          Text(
            '모든 업무에 공통으로 안내할 내용을 입력하세요',
            style: ResponsiveHelper.captionStyle(context).copyWith(
              color: AppColors.grey500,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          TextFormField(
            controller: controller,
            maxLines: maxLines,
            maxLength: 500,
            style: ResponsiveHelper.bodyStyle(context),
            decoration: InputDecoration(
              hintText: hintText ?? '준비물, 복장, 출입·집합 안내 등을 입력하세요',
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
