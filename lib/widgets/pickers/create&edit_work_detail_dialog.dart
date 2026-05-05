import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/core/business_work_type_model.dart';
import '../../utils/toast_helper.dart';
import '../../utils/labor_standards.dart';
import '../../utils/responsive_helper.dart';
import '../../models/work_detail_input.dart'; 
import '../work_type_icon.dart';
import '../../utils/format_helper.dart';
import '../../models/core/work_detail_model.dart';
import '../../theme/app_colors.dart';

// ============================================================
// 🎨 업무 추가 다이얼로그 (세련된 디자인)
// ============================================================

class WorkDetailDialog {
  /// ✨ 업무 추가 다이얼로그 표시
  static Future<WorkDetailInput?> showAddDialog({
    required BuildContext context,
    required List<BusinessWorkTypeModel> businessWorkTypes,
  }) async {
    final theme = Theme.of(context);
    
    BusinessWorkTypeModel? selectedWorkType;
    String selectedWageType = 'hourly';
    String? startTime;
    String? endTime;
    final wageController = TextEditingController();
    final countController = TextEditingController();

    return await showDialog<WorkDetailInput>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Container(
              constraints: BoxConstraints(
                maxWidth: 500,
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ✨ 세련된 헤더
                  _buildHeader(context, theme),
                  
                  // ✨ 메인 컨텐츠
                  Flexible(
                    child: SingleChildScrollView(
                      padding: ResponsiveHelper.cardPadding(context),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 업무 유형 선택
                          _buildWorkTypeSection(
                            context,
                            theme,
                            businessWorkTypes,
                            selectedWorkType,
                            setDialogState,
                            (newWorkType) {  // ⭐ 콜백 함수 추가
                              selectedWorkType = newWorkType;
                            },
                          ),
                          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                          
                          // 급여 타입 선택
                          _buildWageTypeSection(
                            context,
                            theme,
                            selectedWageType,
                            setDialogState,
                            (newType) {  // ⭐ 콜백 함수 추가
                              selectedWageType = newType;
                            },
                          ),
                          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                          
                          // 근무 시간
                          _buildTimeSection(
                            context,
                            theme,
                            startTime,
                            endTime,
                            setDialogState,
                            (newTime) {  // ⭐ 시작 시간 콜백
                              startTime = newTime;
                            },
                            (newTime) {  // ⭐ 종료 시간 콜백
                              endTime = newTime;
                            },
                          ),
                          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                          
                          // 급여 입력
                          _buildWageSection(
                            context,
                            theme,
                            selectedWageType,
                            wageController,
                          ),
                          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                          
                          // 필요 인원
                          _buildCountSection(
                            context,
                            theme,
                            countController,
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // ✨ 액션 버튼들
                  _buildActionButtons(
                    context,
                    theme,
                    selectedWorkType,
                    startTime,
                    endTime,
                    wageController,
                    countController,
                    selectedWageType,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
  /// ✨ 업무 수정 다이얼로그 표시
  /// [businessWorkTypes] 전달 시 업무 유형 변경 가능 (TO 생성 시)
  static Future<Map<String, dynamic>?> showEditDialog({
    required BuildContext context,
    required WorkDetailModel work,
    List<BusinessWorkTypeModel>? businessWorkTypes,
  }) async {
    final theme = Theme.of(context);
    
    // ✅ 업무 유형 선택 (businessWorkTypes가 있을 때만 변경 가능)
    BusinessWorkTypeModel? selectedWorkType;
    if (businessWorkTypes != null && businessWorkTypes.isNotEmpty) {
      selectedWorkType = businessWorkTypes.firstWhere(
        (wt) => wt.name == work.workType,
        orElse: () => businessWorkTypes.first,
      );
    }
    
    String selectedWageType = work.wageType;
    String startTime = work.startTime;
    String endTime = work.endTime;
    final wageController = TextEditingController(
      text: FormatHelper.formatNumber(work.wage),
    );
    final countController = TextEditingController(
      text: work.requiredCount.toString(),
    );

    return await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Container(
              constraints: BoxConstraints(
                maxWidth: 500,
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ✨ 헤더
                  _buildEditHeader(context, theme, work.workType),
                  
                  // ✨ 메인 컨텐츠
                  Flexible(
                    child: SingleChildScrollView(
                      padding: ResponsiveHelper.cardPadding(context),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 업무 유형 (변경 가능/불가)
                          if (businessWorkTypes != null && businessWorkTypes.isNotEmpty)
                            _buildWorkTypeSection(
                              context,
                              theme,
                              businessWorkTypes,
                              selectedWorkType,
                              setDialogState,
                              (newWorkType) {
                                selectedWorkType = newWorkType;
                              },
                            )
                          else
                            _buildEditWarningCard(context),
                          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                          
                          // 급여 타입 선택
                          _buildWageTypeSection(
                            context,
                            theme,
                            selectedWageType,
                            setDialogState,
                            (newType) {
                              selectedWageType = newType;
                            },
                          ),
                          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                          
                          // 근무 시간
                          _buildTimeSection(
                            context,
                            theme,
                            startTime,
                            endTime,
                            setDialogState,
                            (newTime) {
                              startTime = newTime ?? startTime;
                            },
                            (newTime) {
                              endTime = newTime ?? endTime;
                            },
                          ),
                          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                          
                          // 급여 입력
                          _buildWageSection(
                            context,
                            theme,
                            selectedWageType,
                            wageController,
                          ),
                          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                          
                          // 필요 인원
                          _buildEditCountSection(
                            context,
                            theme,
                            countController,
                            work.currentCount,
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // ✨ 액션 버튼들
                  _buildEditActionButtons(
                    context,
                    theme,
                    work,
                    startTime,
                    endTime,
                    wageController,
                    countController,
                    selectedWageType,
                    selectedWorkType,  // ✅ 추가
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// ✨ 수정 헤더
  static Widget _buildEditHeader(BuildContext context, ThemeData theme, String workType) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.primaryColor,
            theme.primaryColor.withOpacity(0.8),
          ],
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.edit_note,
              color: Colors.white,
              size: ResponsiveHelper.iconSize(context, 24),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 16)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$workType 수정',
                  style: ResponsiveHelper.titleStyle(context).copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                Text(
                  '업무 정보를 수정합니다',
                  style: ResponsiveHelper.smallStyle(context).copyWith(
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ],
            ),
          ),
          Material(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: () => Navigator.pop(context),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
                child: Icon(
                  Icons.close,
                  color: Colors.white,
                  size: ResponsiveHelper.iconSize(context, 20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ⚠️ 업무유형 변경 불가 안내 카드
  static Widget _buildEditWarningCard(BuildContext context) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warningLight!),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: AppColors.warningDark,
            size: ResponsiveHelper.iconSize(context, 20),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '업무유형 변경 불가',
                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.warningDeep,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                Text(
                  '업무유형을 변경하려면 삭제 후 재등록해주세요.\n지원자가 있는 경우 지원이 자동 취소됩니다.',
                  style: ResponsiveHelper.smallStyle(context).copyWith(
                    color: AppColors.warningDark,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// ✨ 수정용 인원 섹션 (현재 확정 인원 표시)
  static Widget _buildEditCountSection(
    BuildContext context,
    ThemeData theme,
    TextEditingController countController,
    int currentCount,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.people,
                size: ResponsiveHelper.iconSize(context, 18),
                color: AppColors.purpleDark,
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            Text(
              '필요 인원',
              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        TextFormField(
          controller: countController,
          keyboardType: TextInputType.number,
          style: ResponsiveHelper.bodyStyle(context).copyWith(
            fontWeight: FontWeight.bold,
            fontSize: ResponsiveHelper.getFontSize(context, 16),
          ),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.grey50,
            hintText: '필요한 인원 수를 입력하세요',
            hintStyle: ResponsiveHelper.bodyStyle(
              context,
              color: AppColors.grey400,
            ),
            suffixText: '명',
            suffixStyle: ResponsiveHelper.bodyStyle(context).copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.purpleDark,
            ),
            helperText: currentCount > 0
                ? '현재 $currentCount명 확정됨 (최소 $currentCount명 이상)'
                : null,
            helperStyle: ResponsiveHelper.smallStyle(context).copyWith(
              color: AppColors.warningDark,
            ),
            prefixIcon: Icon(
              Icons.group_add,
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
        ),
      ],
    );
  }

  /// ✨ 수정 액션 버튼들
  static Widget _buildEditActionButtons(
    BuildContext context,
    ThemeData theme,
    WorkDetailModel work,
    String startTime,
    String endTime,
    TextEditingController wageController,
    TextEditingController countController,
    String selectedWageType,
    BusinessWorkTypeModel? selectedWorkType,
  ) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: AppColors.grey200!),
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.symmetric(
                  vertical: ResponsiveHelper.spacing(context, 16),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                side: BorderSide(color: AppColors.grey300!),
              ),
              child: Text(
                '취소',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Expanded(
            flex: 2,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.primaryColor,
                    theme.primaryColor.withOpacity(0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: theme.primaryColor.withOpacity(0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    final wage = int.tryParse(wageController.text.replaceAll(',', ''));
                    final count = int.tryParse(countController.text);

                    if (wage == null || count == null) {
                      ToastHelper.showError('금액과 인원을 입력하세요');
                      return;
                    }

                    if (count < work.currentCount) {
                      ToastHelper.showError(
                        '필요 인원은 확정 인원(${work.currentCount}명)보다 작을 수 없습니다'
                      );
                      return;
                    }

                    Navigator.pop(context, {
                      // 업무 유형 (변경된 경우)
                      if (selectedWorkType != null) ...{
                        'workType': selectedWorkType.name,
                        'workTypeIcon': selectedWorkType.icon,
                        'workTypeColor': selectedWorkType.color,
                        'workTypeBackgroundColor': selectedWorkType.backgroundColor,
                      },
                      'wage': wage,
                      'wageType': selectedWageType,
                      'requiredCount': count,
                      'startTime': startTime,
                      'endTime': endTime,
                    });
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: ResponsiveHelper.spacing(context, 16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.save,
                          color: Colors.white,
                          size: ResponsiveHelper.iconSize(context, 20),
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                        Text(
                          '저장',
                          style: ResponsiveHelper.bodyStyle(context).copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: ResponsiveHelper.getFontSize(context, 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 🎨 UI 섹션 빌더들
  // ============================================================

  /// ✨ 세련된 헤더
  static Widget _buildHeader(BuildContext context, ThemeData theme) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.primaryColor,
            theme.primaryColor.withOpacity(0.8),
          ],
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.work_outline,
              color: Colors.white,
              size: ResponsiveHelper.iconSize(context, 24),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 16)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '업무 추가',
                  style: ResponsiveHelper.titleStyle(context).copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                Text(
                  '새로운 업무를 추가하세요',
                  style: ResponsiveHelper.smallStyle(context).copyWith(
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ],
            ),
          ),
          Material(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: () => Navigator.pop(context),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
                child: Icon(
                  Icons.close,
                  color: Colors.white,
                  size: ResponsiveHelper.iconSize(context, 20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ✨ 업무 유형 선택 섹션 (콜백 추가)
  static Widget _buildWorkTypeSection(
    BuildContext context,
    ThemeData theme,
    List<BusinessWorkTypeModel> businessWorkTypes,
    BusinessWorkTypeModel? selectedWorkType,
    StateSetter setDialogState,
    Function(BusinessWorkTypeModel?) onWorkTypeChanged,  // ⭐ 콜백 추가
  ) {
    return Column(
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
                Icons.category,
                size: ResponsiveHelper.iconSize(context, 18),
                color: theme.primaryColor,
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            Text(
              '업무 유형',
              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        Container(
          decoration: BoxDecoration(
            color: AppColors.grey50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selectedWorkType != null 
                  ? theme.primaryColor 
                  : AppColors.grey300!,
              width: selectedWorkType != null ? 2 : 1,
            ),
          ),
          child: DropdownButtonFormField<BusinessWorkTypeModel>(
            isExpanded: true,
            initialValue: selectedWorkType,
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding: ResponsiveHelper.cardPadding(context),
              hintText: '업무를 선택하세요',
              hintStyle: ResponsiveHelper.bodyStyle(
                context,
                color: AppColors.grey400,
              ),
            ),
            items: businessWorkTypes.map((workType) {
              return DropdownMenuItem<BusinessWorkTypeModel>(
                value: workType,
                child: Row(
                  children: [
                    Container(
                      width: ResponsiveHelper.iconSize(context, 36),
                      height: ResponsiveHelper.iconSize(context, 36),
                      decoration: BoxDecoration(
                        color: FormatHelper.parseColor(
                          workType.backgroundColor ?? '#2196F3'
                        ),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: FormatHelper.parseColor(
                              workType.color ?? '#FFFFFF'
                            ).withOpacity(0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Center(
                        child: WorkTypeIcon.buildFromString(
                          workType.icon,
                          color: workType.color != null 
                              ? FormatHelper.parseColor(workType.color!)
                              : Colors.white,
                          size: ResponsiveHelper.iconSize(context, 16),
                        ),
                      ),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                    Flexible(
                      child: Text(
                        workType.name,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: ResponsiveHelper.bodyStyle(context).copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
            onChanged: (value) {
              setDialogState(() => onWorkTypeChanged(value));  // ⭐ 콜백 호출
            },
          ),
        ),
      ],
    );
  }

  /// ✨ 급여 타입 선택 섹션 (수정됨)
  static Widget _buildWageTypeSection(
    BuildContext context,
    ThemeData theme,
    String selectedWageType,
    StateSetter setDialogState,
    Function(String) onWageTypeChanged,  // ⭐ 콜백 추가
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.payments,
                size: ResponsiveHelper.iconSize(context, 18),
                color: AppColors.successDark,
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            Text(
              '급여 타입',
              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        Row(
          children: [
            Expanded(
              child: _buildWageTypeButton(
                context: context,
                theme: theme,
                label: '시급',
                value: 'hourly',
                icon: Icons.access_time,
                selectedValue: selectedWageType,
                onTap: () {
                  setDialogState(() {
                    onWageTypeChanged('hourly');
                  });
                },
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Expanded(
              child: _buildWageTypeButton(
                context: context,
                theme: theme,
                label: '일급',
                value: 'daily',
                icon: Icons.today,
                selectedValue: selectedWageType,
                onTap: () {
                  setDialogState(() {
                    onWageTypeChanged('daily');
                  });
                },
              ),
            ),
            // 🔥 월급 버튼 제거됨
          ],
        ),
      ],
    );
  }

  /// ✨ 근무 시간 섹션 (레이아웃 개선 + 콜백)
  static Widget _buildTimeSection(
    BuildContext context,
    ThemeData theme,
    String? startTime,
    String? endTime,
    StateSetter setDialogState,
    Function(String?) onStartTimeChanged,  // ⭐ 콜백 추가
    Function(String?) onEndTimeChanged,    // ⭐ 콜백 추가
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.schedule,
                size: ResponsiveHelper.iconSize(context, 18),
                color: AppColors.infoDark,
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            Text(
              '근무 시간',
              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        
        // ✅ 세로 레이아웃으로 변경 (공간 확보)
        Column(
          children: [
            // 시작 시간
            Container(
              decoration: BoxDecoration(
                color: AppColors.grey50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: startTime != null 
                      ? theme.primaryColor 
                      : AppColors.grey300!,
                  width: startTime != null ? 2 : 1,
                ),
              ),
              child: DropdownButtonFormField<String>(
                initialValue: startTime,
                isExpanded: true,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 16),
                    vertical: ResponsiveHelper.spacing(context, 12),
                  ),
                  hintText: '시작 시간 선택',
                  hintStyle: ResponsiveHelper.smallStyle(
                    context,
                    color: AppColors.grey400,
                  ),
                  prefixIcon: Icon(
                    Icons.play_arrow,
                    color: theme.primaryColor,
                    size: ResponsiveHelper.iconSize(context, 20),
                  ),
                ),
                style: ResponsiveHelper.bodyStyle(context),
                items: FormatHelper.generateTimeList().map((time) {
                  return DropdownMenuItem(
                    value: time,
                    child: Text(time),
                  );
                }).toList(),
                onChanged: (value) => setDialogState(() => onStartTimeChanged(value)),  // ⭐ 콜백 호출
              ),
            ),
            
            // 화살표
            Padding(
              padding: EdgeInsets.symmetric(
                vertical: ResponsiveHelper.spacing(context, 8),
              ),
              child: Icon(
                Icons.arrow_downward,
                color: theme.primaryColor,
                size: ResponsiveHelper.iconSize(context, 20),
              ),
            ),
            
            // 종료 시간
            Container(
              decoration: BoxDecoration(
                color: AppColors.grey50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: endTime != null 
                      ? theme.primaryColor 
                      : AppColors.grey300!,
                  width: endTime != null ? 2 : 1,
                ),
              ),
              child: DropdownButtonFormField<String>(
                initialValue: endTime,
                isExpanded: true,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 16),
                    vertical: ResponsiveHelper.spacing(context, 12),
                  ),
                  hintText: '종료 시간 선택',
                  hintStyle: ResponsiveHelper.smallStyle(
                    context,
                    color: AppColors.grey400,
                  ),
                  prefixIcon: Icon(
                    Icons.stop,
                    color: theme.primaryColor,
                    size: ResponsiveHelper.iconSize(context, 20),
                  ),
                ),
                style: ResponsiveHelper.bodyStyle(context),
                items: FormatHelper.generateTimeList().map((time) {
                  return DropdownMenuItem(
                    value: time,
                    child: Text(time),
                  );
                }).toList(),
                onChanged: (value) => setDialogState(() => onEndTimeChanged(value)),  // ⭐ 콜백 호출
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// ✨ 급여 입력 섹션
  static Widget _buildWageSection(
    BuildContext context,
    ThemeData theme,
    String selectedWageType,
    TextEditingController wageController,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.currency_exchange,
                size: ResponsiveHelper.iconSize(context, 18),
                color: AppColors.amberDark,
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            Text(
              _getWageLabelFromType(selectedWageType),
              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        TextFormField(
          controller: wageController,
          keyboardType: TextInputType.number,
          style: ResponsiveHelper.bodyStyle(context).copyWith(
            fontWeight: FontWeight.bold,
            fontSize: ResponsiveHelper.getFontSize(context, 16),
          ),
          inputFormatters: [
            NumberInputFormatter(),
          ],
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.grey50,
            hintText: '금액을 입력하세요',
            hintStyle: ResponsiveHelper.bodyStyle(
              context,
              color: AppColors.grey400,
            ),
            suffixText: '원',
            suffixStyle: ResponsiveHelper.bodyStyle(context).copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.successDark,
            ),
            prefixIcon: Icon(
              Icons.attach_money,
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
        ),
        if (selectedWageType == 'hourly') ...[
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Container(
            padding: ResponsiveHelper.cardPadding(context),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.infoBg!,
                  AppColors.infoExtraLight!,
                ],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: ResponsiveHelper.iconSize(context, 16),
                  color: AppColors.infoDark,
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Expanded(
                  child: Text(
                    '2025년 최저시급: ${LaborStandards.formatCurrencyWithUnit(LaborStandards.currentMinimumWage)}',
                    style: ResponsiveHelper.smallStyle(
                      context,
                      color: AppColors.infoDeep,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// ✨ 필요 인원 섹션
  static Widget _buildCountSection(
    BuildContext context,
    ThemeData theme,
    TextEditingController countController,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.people,
                size: ResponsiveHelper.iconSize(context, 18),
                color: AppColors.purpleDark,
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            Text(
              '필요 인원',
              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        TextFormField(
          controller: countController,
          keyboardType: TextInputType.number,
          style: ResponsiveHelper.bodyStyle(context).copyWith(
            fontWeight: FontWeight.bold,
            fontSize: ResponsiveHelper.getFontSize(context, 16),
          ),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.grey50,
            hintText: '필요한 인원 수를 입력하세요',
            hintStyle: ResponsiveHelper.bodyStyle(
              context,
              color: AppColors.grey400,
            ),
            suffixText: '명',
            suffixStyle: ResponsiveHelper.bodyStyle(context).copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.purpleDark,
            ),
            prefixIcon: Icon(
              Icons.group_add,
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
        ),
      ],
    );
  }

  /// ✨ 액션 버튼들
  static Widget _buildActionButtons(
    BuildContext context,
    ThemeData theme,
    BusinessWorkTypeModel? selectedWorkType,
    String? startTime,
    String? endTime,
    TextEditingController wageController,
    TextEditingController countController,
    String selectedWageType,
  ) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: AppColors.grey200!),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.symmetric(
                  vertical: ResponsiveHelper.spacing(context, 16),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                side: BorderSide(color: AppColors.grey300!),
              ),
              child: Text(
                '취소',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Expanded(
            flex: 2,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.primaryColor,
                    theme.primaryColor.withOpacity(0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: theme.primaryColor.withOpacity(0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    if (selectedWorkType == null ||
                        startTime == null ||
                        endTime == null ||
                        wageController.text.isEmpty ||
                        countController.text.isEmpty) {
                      ToastHelper.showError('모든 정보를 입력해주세요');
                      return;
                    }

                    final wage = int.tryParse(wageController.text.replaceAll(',', ''));
                    final count = int.tryParse(countController.text);

                    if (wage == null || wage <= 0) {
                      ToastHelper.showError('유효한 급여를 입력해주세요');
                      return;
                    }

                    if (count == null || count <= 0) {
                      ToastHelper.showError('유효한 인원 수를 입력해주세요');
                      return;
                    }

                    Navigator.pop(
                      context,
                      WorkDetailInput(
                        workType: selectedWorkType.name,
                        workTypeIcon: selectedWorkType.icon,
                        workTypeColor: selectedWorkType.color ?? '#FFFFFF',
                        workTypeBackgroundColor: selectedWorkType.backgroundColor,
                        wage: wage,
                        requiredCount: count,
                        startTime: startTime,
                        endTime: endTime,
                        wageType: selectedWageType,
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: ResponsiveHelper.spacing(context, 16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_circle_outline,
                          color: Colors.white,
                          size: ResponsiveHelper.iconSize(context, 20),
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                        Text(
                          '업무 추가',
                          style: ResponsiveHelper.bodyStyle(context).copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: ResponsiveHelper.getFontSize(context, 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 🛠️ 헬퍼 함수들
  // ============================================================

  /// 급여 타입에 따른 라벨 반환
  static String _getWageLabelFromType(String wageType) {
    switch (wageType) {
      case 'hourly':
        return '시급';
      case 'daily':
        return '일급';
      case 'monthly':
        return '월급';
      default:
        return '급여';
    }
  }

  /// ✨ 급여 타입 선택 버튼
  static Widget _buildWageTypeButton({
    required BuildContext context,
    required ThemeData theme,
    required String label,
    required String value,
    required IconData icon,
    required String selectedValue,
    required VoidCallback onTap,
  }) {
    final isSelected = value == selectedValue;
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: ResponsiveHelper.spacing(context, 14),
        ),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.primaryColor,
                    theme.primaryColor.withOpacity(0.8),
                  ],
                )
              : null,
          color: isSelected ? null : Colors.white,
          border: Border.all(
            color: isSelected 
                ? theme.primaryColor
                : AppColors.grey300!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: theme.primaryColor.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : AppColors.grey600,
              size: ResponsiveHelper.iconSize(context, 20),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
            Text(
              label,
              style: ResponsiveHelper.smallStyle(context).copyWith(
                color: isSelected ? Colors.white : AppColors.grey700,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
