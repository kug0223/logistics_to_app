import 'package:flutter/material.dart';
import '../../../../models/work_detail_input.dart';
import '../../../../models/core/work_detail_model.dart';
import '../../../../utils/responsive_helper.dart';
import 'to_section_container.dart';
import 'to_work_detail_card.dart';
import '';
import '../../../../theme/app_colors.dart';

/// ✨ TO 업무 상세 섹션
/// create_to_screen, edit_to_screen에서 공통으로 사용
class TOWorkDetailsSection extends StatelessWidget {
  /// WorkDetailInput 리스트 (create용)
  final List<WorkDetailInput>? workDetailInputs;
  
  /// WorkDetailModel 리스트 (edit용)
  final List<WorkDetailModel>? workDetailModels;
  
  /// 업무 추가 콜백
  final VoidCallback onAddWork;
  
  /// 업무 삭제 콜백 (index 기반 - create용)
  final void Function(int index)? onRemoveWorkByIndex;
  
  /// 업무 수정 콜백 (index 기반 - create용)
  final void Function(int index)? onEditWorkByIndex;
  
  /// 업무 수정 콜백 (WorkDetailModel - edit용)
  final void Function(WorkDetailModel work)? onEditWork;
  
  /// 업무 삭제 콜백 (WorkDetailModel - edit용)
  final void Function(WorkDetailModel work)? onDeleteWork;
  
  /// 업무 유형 없음 경고 표시
  final bool showNoWorkTypeWarning;

  const TOWorkDetailsSection({
    super.key,
    this.workDetailInputs,
    this.workDetailModels,
    required this.onAddWork,
    this.onRemoveWorkByIndex,
    this.onEditWorkByIndex,
    this.onEditWork,
    this.onDeleteWork,
    this.showNoWorkTypeWarning = false,
  }) : assert(
         workDetailInputs != null || workDetailModels != null,
         'Either workDetailInputs or workDetailModels must be provided',
       );

  int get _workCount {
    if (workDetailInputs != null) return workDetailInputs!.length;
    if (workDetailModels != null) return workDetailModels!.length;
    return 0;
  }

  bool get _isEmpty {
    if (workDetailInputs != null) return workDetailInputs!.isEmpty;
    if (workDetailModels != null) return workDetailModels!.isEmpty;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TOSectionContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '업무 목록 ($_workCount개)',
                style: ResponsiveHelper.subtitleStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              _buildAddButton(context, theme),
            ],
          ),
          
          // 업무 유형 없음 경고
          if (showNoWorkTypeWarning) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            _buildNoWorkTypeWarning(context),
          ],
          
          // 빈 상태
          if (_isEmpty && !showNoWorkTypeWarning) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 24)),
            _buildEmptyState(context),
          ],
          
          // 업무 카드 목록
          if (!_isEmpty) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            _buildWorkDetailCards(context),
          ],
        ],
      ),
    );
  }

  Widget _buildAddButton(BuildContext context, ThemeData theme) {
    return Material(
      color: AppColors.successBg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onAddWork,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 16),
            vertical: ResponsiveHelper.spacing(context, 10),
          ),
          child: Row(
            children: [
              Icon(
                Icons.add_circle_outline,
                size: ResponsiveHelper.iconSize(context, 18),
                color: AppColors.successDark,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Text(
                '업무 추가',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  color: AppColors.successDark,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoWorkTypeWarning(BuildContext context) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.warningLight!,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber,
            color: AppColors.warningDark,
            size: ResponsiveHelper.iconSize(context, 20),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Expanded(
            child: Text(
              '업무 유형을 먼저 등록해주세요',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                color: Colors.orange[900],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        children: [
          Icon(
            Icons.work_outline,
            size: ResponsiveHelper.iconSize(context, 48),
            color: AppColors.grey400,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          Text(
            '등록된 업무가 없습니다',
            style: ResponsiveHelper.bodyStyle(
              context,
              color: AppColors.grey600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkDetailCards(BuildContext context) {
    // WorkDetailInput 리스트 (create 모드)
    if (workDetailInputs != null) {
      return Column(
        children: workDetailInputs!.asMap().entries.map((entry) {
          final index = entry.key;
          final detail = entry.value;
          return TOWorkDetailCard.fromInput(
            detail: detail,
            onEdit: onEditWorkByIndex != null
                ? () => onEditWorkByIndex!(index)
                : null,
            onDelete: onRemoveWorkByIndex != null 
                ? () => onRemoveWorkByIndex!(index)
                : null,
          );
        }).toList(),
      );
    }
    
    // WorkDetailModel 리스트 (edit 모드)
    if (workDetailModels != null) {
      return Column(
        children: workDetailModels!.map((work) {
          return TOWorkDetailCard.fromModel(
            work: work,
            onEdit: onEditWork != null ? () => onEditWork!(work) : null,
            onDelete: onDeleteWork != null ? () => onDeleteWork!(work) : null,
          );
        }).toList(),
      );
    }
    
    return const SizedBox.shrink();
  }
}
