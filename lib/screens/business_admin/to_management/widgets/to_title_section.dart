import 'package:flutter/material.dart';
import '../../../../utils/responsive_helper.dart';
import 'to_section_container.dart';
import '';
import '../../../../theme/app_colors.dart';

// 위젯 파일 위치: lib/screens/business_admin/to_management/widgets/

/// ✨ TO 제목 입력 섹션
/// create_to_screen, edit_to_screen에서 공통으로 사용
class TOTitleSection extends StatelessWidget {
  final TextEditingController titleController;
  final TextEditingController? groupNameController;
  final bool isGroupTO;
  final bool showGroupNameInput;
  final String? Function(String?)? validator;

  const TOTitleSection({
    super.key,
    required this.titleController,
    this.groupNameController,
    this.isGroupTO = false,
    this.showGroupNameInput = true,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TOSectionContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 섹션 헤더 (edit_to_screen 스타일)
          Text(
            'TO 제목',
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          
          // TO 제목 입력
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
                borderSide: BorderSide(color: AppColors.grey300!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.grey300!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: theme.primaryColor, width: 2),
              ),
            ),
            validator: validator ?? (value) {
              if (value == null || value.trim().isEmpty) {
                return 'TO 제목을 입력해주세요';
              }
              return null;
            },
          ),
          
          // 그룹명 입력 (create에서만 사용) - 항상 표시, 비활성화 상태 지원
          if (showGroupNameInput && groupNameController != null) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 20)),
            _buildGroupNameInput(context, theme, enabled: isGroupTO),
          ],
        ],
      ),
    );
  }

  Widget _buildGroupNameInput(BuildContext context, ThemeData theme, {required bool enabled}) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: Container(
        padding: ResponsiveHelper.cardPadding(context),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: enabled
                ? [
                    theme.primaryColor.withOpacity(0.1),
                    theme.primaryColor.withOpacity(0.05),
                  ]
                : [
                    Colors.grey.withOpacity(0.1),
                    Colors.grey.withOpacity(0.05),
                  ],
          ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: enabled 
              ? theme.primaryColor.withOpacity(0.3)
              : Colors.grey.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.link,
                  size: ResponsiveHelper.iconSize(context, 18),
                  color: enabled ? theme.primaryColor : Colors.grey,
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Text(
                enabled ? '그룹 TO' : '그룹 TO (2일 이상 선택 시 활성화)',
                style: ResponsiveHelper.subtitleStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                  color: enabled ? theme.primaryColor : Colors.grey,
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            TextFormField(
              controller: groupNameController,
              enabled: enabled,
              style: ResponsiveHelper.bodyStyle(context),
              decoration: InputDecoration(
                labelText: '그룹명 (선택)',
                labelStyle: ResponsiveHelper.bodyStyle(context),
                hintText: '비워두면 자동으로 생성됩니다',
                hintStyle: ResponsiveHelper.smallStyle(
                  context,
                  color: AppColors.grey400,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.white,
                helperText: '비워두면 자동으로 생성됩니다',
                helperStyle: ResponsiveHelper.smallStyle(
                  context,
                  color: AppColors.grey600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
