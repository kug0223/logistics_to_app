import 'package:flutter/material.dart';
import '../../../../utils/responsive_helper.dart';
import 'to_section_container.dart';
import '../../../../theme/app_colors.dart';

/// TO 제목 입력 섹션
/// create_to_screen, edit_to_screen에서 공통으로 사용
class TOTitleSection extends StatelessWidget {
  final TextEditingController titleController;
  final String? Function(String?)? validator;

  const TOTitleSection({
    super.key,
    required this.titleController,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TOSectionContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '공고 제목',
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          TextFormField(
            controller: titleController,
            style: ResponsiveHelper.bodyStyle(context),
            decoration: InputDecoration(
              hintText: '예: 분류작업, 피킹업무',
              hintStyle: ResponsiveHelper.smallStyle(
                context,
                color: AppColors.grey400,
              ),
              prefixIcon: Icon(
                Icons.title,
                color: theme.primaryColor,
                size: ResponsiveHelper.iconSize(context, 24),
              ),
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
            validator: validator ??
                (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '공고 제목을 입력해주세요';
                  }
                  if (value.trim().length < 2) {
                    return '제목은 최소 2자 이상이어야 합니다';
                  }
                  if (value.trim().length > 100) {
                    return '제목은 100자 이내여야 합니다';
                  }
                  return null;
                },
          ),
        ],
      ),
    );
  }
}
