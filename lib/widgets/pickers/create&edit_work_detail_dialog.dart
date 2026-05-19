import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/core/business_work_type_model.dart';
import '../../utils/toast_helper.dart';
import '../../utils/labor_standards.dart';
import '../../utils/responsive_helper.dart';
import '../../models/work_detail_input.dart';
import '../work_type_icon.dart';
import '../../utils/format_helper.dart';
import '../../models/core/work_detail_data.dart';
import '../../theme/app_colors.dart';
import '../../utils/wage_calculator.dart';
import '../app_select_field.dart';

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
    String? shiftType;
    bool nightAllowanceApplied = true;
    bool nightIncluded = false;
    bool weeklyHolidayIncluded = false;
    int? scheduledDaysPerWeek;
    int breakMinutes = 0;
    final wageController = TextEditingController();
    final countController = TextEditingController();
    final baseHourlyWageController = TextEditingController();

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
                            (newType) {
                              selectedWageType = newType;
                              if (newType != 'daily') {
                                shiftType = null;
                                nightIncluded = false;
                              }
                            },
                          ),
                          SizedBox(height: ResponsiveHelper.spacing(context, 24)),

                          // 야간수당 설정 (모든 급여 유형)
                          _buildShiftAndNightSection(
                            context, theme,
                            selectedWageType, shiftType,
                            nightAllowanceApplied, nightIncluded,
                            setDialogState,
                            (v) { shiftType = v; },
                            (v) { nightAllowanceApplied = v; if (!v) { nightIncluded = false; } },
                            (v) { nightIncluded = v; },
                          ),
                          SizedBox(height: ResponsiveHelper.spacing(context, 24)),

                          // 주휴수당 정책
                          _buildWeeklyHolidaySection(
                            context, theme,
                            weeklyHolidayIncluded,
                            scheduledDaysPerWeek,
                            setDialogState,
                            (v) { weeklyHolidayIncluded = v; if (!v) scheduledDaysPerWeek = null; },
                            (v) { scheduledDaysPerWeek = v; },
                          ),
                          SizedBox(height: ResponsiveHelper.spacing(context, 24)),

                          // 휴게시간
                          _buildBreakMinutesSection(
                            context, theme, breakMinutes, setDialogState,
                            (v) { breakMinutes = v; },
                          ),
                          SizedBox(height: ResponsiveHelper.spacing(context, 24)),

                          // 근무 시간
                          _buildTimeSection(
                            context,
                            theme,
                            startTime,
                            endTime,
                            breakMinutes,
                            setDialogState,
                            (newTime) {
                              startTime = newTime;
                            },
                            (newTime) {
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
                            startTime,
                            endTime,
                            breakMinutes,
                          ),
                          if (selectedWageType == 'daily') ...[
                            SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                            ValueListenableBuilder<TextEditingValue>(
                              valueListenable: wageController,
                              builder: (_, __, ___) => _buildBaseHourlyWageSection(
                                context, theme,
                                wageController, baseHourlyWageController,
                                startTime, endTime, breakMinutes,
                              ),
                            ),
                          ],
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
                    shiftType,
                    nightAllowanceApplied,
                    nightIncluded,
                    weeklyHolidayIncluded,
                    scheduledDaysPerWeek,
                    breakMinutes,
                    baseHourlyWageController,
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
    required WorkDetailData work,
    List<BusinessWorkTypeModel>? businessWorkTypes,
    int currentCount = 0,
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
    String? shiftType = work.shiftType;
    bool nightAllowanceApplied = work.nightAllowanceApplied;
    bool nightIncluded = work.nightIncluded;
    bool weeklyHolidayIncluded = work.weeklyHolidayIncluded;
    int? scheduledDaysPerWeek = work.scheduledDaysPerWeek;
    int breakMinutes = work.breakMinutes;
    final wageController = TextEditingController(
      text: FormatHelper.formatNumber(work.wage),
    );
    final countController = TextEditingController(
      text: work.requiredCount.toString(),
    );
    final baseHourlyWageController = TextEditingController(
      text: work.baseHourlyWage != null
          ? FormatHelper.formatNumber(work.baseHourlyWage!)
          : '',
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
                              if (newType != 'daily') {
                                shiftType = null;
                                nightIncluded = false;
                              }
                            },
                          ),
                          SizedBox(height: ResponsiveHelper.spacing(context, 24)),

                          // 야간수당 설정 (모든 급여 유형)
                          _buildShiftAndNightSection(
                            context, theme,
                            selectedWageType, shiftType,
                            nightAllowanceApplied, nightIncluded,
                            setDialogState,
                            (v) { shiftType = v; },
                            (v) { nightAllowanceApplied = v; if (!v) { nightIncluded = false; } },
                            (v) { nightIncluded = v; },
                          ),
                          SizedBox(height: ResponsiveHelper.spacing(context, 24)),

                          // 주휴수당 정책
                          _buildWeeklyHolidaySection(
                            context, theme,
                            weeklyHolidayIncluded,
                            scheduledDaysPerWeek,
                            setDialogState,
                            (v) { weeklyHolidayIncluded = v; if (!v) scheduledDaysPerWeek = null; },
                            (v) { scheduledDaysPerWeek = v; },
                          ),
                          SizedBox(height: ResponsiveHelper.spacing(context, 24)),

                          // 휴게시간
                          _buildBreakMinutesSection(
                            context, theme, breakMinutes, setDialogState,
                            (v) { breakMinutes = v; },
                          ),
                          SizedBox(height: ResponsiveHelper.spacing(context, 24)),

                          // 근무 시간
                          _buildTimeSection(
                            context,
                            theme,
                            startTime,
                            endTime,
                            breakMinutes,
                            setDialogState,
                            (newTime) {
                              if (newTime != null) startTime = newTime;
                            },
                            (newTime) {
                              if (newTime != null) endTime = newTime;
                            },
                          ),
                          SizedBox(height: ResponsiveHelper.spacing(context, 24)),

                          // 급여 입력
                          _buildWageSection(
                            context,
                            theme,
                            selectedWageType,
                            wageController,
                            startTime,
                            endTime,
                            breakMinutes,
                          ),
                          if (selectedWageType == 'daily') ...[
                            SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                            ValueListenableBuilder<TextEditingValue>(
                              valueListenable: wageController,
                              builder: (_, __, ___) => _buildBaseHourlyWageSection(
                                context, theme,
                                wageController, baseHourlyWageController,
                                startTime, endTime, breakMinutes,
                              ),
                            ),
                          ],
                          SizedBox(height: ResponsiveHelper.spacing(context, 24)),

                          // 필요 인원
                          _buildEditCountSection(
                            context,
                            theme,
                            countController,
                            currentCount,
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // ✨ 액션 버튼들
                  _buildEditActionButtons(
                    context,
                    theme,
                    currentCount,
                    startTime,
                    endTime,
                    wageController,
                    countController,
                    selectedWageType,
                    selectedWorkType,
                    shiftType,
                    nightAllowanceApplied,
                    nightIncluded,
                    weeklyHolidayIncluded,
                    scheduledDaysPerWeek,
                    breakMinutes,
                    baseHourlyWageController,
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
            theme.primaryColor.withValues(alpha: 0.8),
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
              color: Colors.white.withValues(alpha: 0.2),
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
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
          Material(
            color: Colors.white.withValues(alpha: 0.2),
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
        border: Border.all(color: AppColors.warningLight),
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
                color: AppColors.purple.withValues(alpha: 0.1),
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
    );
  }

  /// ✨ 수정 액션 버튼들
  static Widget _buildEditActionButtons(
    BuildContext context,
    ThemeData theme,
    int currentCount,
    String startTime,
    String endTime,
    TextEditingController wageController,
    TextEditingController countController,
    String selectedWageType,
    BusinessWorkTypeModel? selectedWorkType,
    String? shiftType,
    bool nightAllowanceApplied,
    bool nightIncluded,
    bool weeklyHolidayIncluded,
    int? scheduledDaysPerWeek,
    int breakMinutes,
    TextEditingController baseHourlyWageController,
  ) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: AppColors.grey200),
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
                side: BorderSide(color: AppColors.grey300),
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
                    theme.primaryColor.withValues(alpha: 0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: theme.primaryColor.withValues(alpha: 0.4),
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

                    if (count < currentCount) {
                      ToastHelper.showError(
                        '필요 인원은 확정 인원($currentCount명)보다 작을 수 없습니다'
                      );
                      return;
                    }

                    if (selectedWageType == 'daily' && shiftType == null) {
                      ToastHelper.showError('일급제는 근무 시간대(주간/석간/야간)를 선택해주세요');
                      return;
                    }

                    Navigator.pop(context, {
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
                      if (shiftType != null) 'shiftType': shiftType,
                      'nightAllowanceApplied': nightAllowanceApplied,
                      'nightIncluded': nightIncluded,
                      'weeklyHolidayIncluded': weeklyHolidayIncluded,
                      if (scheduledDaysPerWeek != null) 'scheduledDaysPerWeek': scheduledDaysPerWeek,
                      'breakMinutes': breakMinutes,
                      'baseHourlyWage': int.tryParse(
                        baseHourlyWageController.text.replaceAll(',', ''),
                      ),
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
            theme.primaryColor.withValues(alpha: 0.8),
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
              color: Colors.white.withValues(alpha: 0.2),
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
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
          Material(
            color: Colors.white.withValues(alpha: 0.2),
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
                color: theme.primaryColor.withValues(alpha: 0.1),
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
        AppSelectField<BusinessWorkTypeModel>(
          value: selectedWorkType,
          hintText: '업무를 선택하세요',
          sheetTitle: '업무 유형 선택',
          items: businessWorkTypes,
          labelOf: (wt) => wt.name,
          leadingOf: (wt) => Container(
            width: ResponsiveHelper.iconSize(context, 36),
            height: ResponsiveHelper.iconSize(context, 36),
            decoration: BoxDecoration(
              color: FormatHelper.parseColor(wt.backgroundColor ?? '#2196F3'),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: FormatHelper.parseColor(wt.color ?? '#FFFFFF')
                      .withValues(alpha: 0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: WorkTypeIcon.build(
                wt,
                size: ResponsiveHelper.iconSize(context, 16),
              ),
            ),
          ),
          onChanged: (wt) => setDialogState(() => onWorkTypeChanged(wt)),
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
                color: AppColors.success.withValues(alpha: 0.1),
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

  /// ✨ 근무 시간 섹션 — 바텀시트 스크롤 피커
  static Widget _buildTimeSection(
    BuildContext context,
    ThemeData theme,
    String? startTime,
    String? endTime,
    int breakMinutes,
    StateSetter setDialogState,
    Function(String?) onStartTimeChanged,
    Function(String?) onEndTimeChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.1),
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
        Column(
          children: [
            _buildTimePickerTile(
              context: context,
              theme: theme,
              value: startTime,
              hintText: '시작 시간 선택',
              prefixIcon: Icons.play_arrow,
              onTap: () async {
                final selected = await _showTimePickerSheet(
                  context, theme, startTime, '시작 시간',
                );
                if (selected != null) {
                  setDialogState(() => onStartTimeChanged(selected));
                }
              },
            ),
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
            _buildTimePickerTile(
              context: context,
              theme: theme,
              value: endTime,
              hintText: '종료 시간 선택',
              prefixIcon: Icons.stop,
              onTap: () async {
                final selected = await _showTimePickerSheet(
                  context, theme, endTime, '종료 시간',
                );
                if (selected != null) {
                  setDialogState(() => onEndTimeChanged(selected));
                }
              },
            ),
            // 총 근무시간 요약
            if (startTime != null && endTime != null) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 10)),
              Builder(builder: (_) {
                int toMins(String t) {
                  final p = t.split(':');
                  return int.parse(p[0]) * 60 + int.parse(p[1]);
                }
                int s = toMins(startTime);
                int e = toMins(endTime);
                if (e <= s) e += 1440;
                final total = (e - s - breakMinutes).clamp(0, 1440);
                final h = total ~/ 60;
                final m = total % 60;
                final timeStr = h > 0
                    ? (m > 0 ? '$h시간 $m분' : '$h시간')
                    : '$m분';
                final breakNote = breakMinutes > 0
                    ? ' (휴게 $breakMinutes분 제외)'
                    : '';
                return Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 14),
                    vertical: ResponsiveHelper.spacing(context, 10),
                  ),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: theme.primaryColor.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.timer_outlined,
                          size: ResponsiveHelper.iconSize(context, 16),
                          color: theme.primaryColor),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                      Text(
                        '총 $timeStr 근무$breakNote',
                        style: ResponsiveHelper.smallStyle(context).copyWith(
                          color: theme.primaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ],
    );
  }

  /// 시간 선택 타일 — 탭하면 바텀시트 피커 열림
  static Widget _buildTimePickerTile({
    required BuildContext context,
    required ThemeData theme,
    required String? value,
    required String hintText,
    required IconData prefixIcon,
    required VoidCallback onTap,
  }) {
    final hasValue = value != null;
    return Material(
      color: AppColors.grey50,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 16),
            vertical: ResponsiveHelper.spacing(context, 14),
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasValue ? theme.primaryColor : AppColors.grey300,
              width: hasValue ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                prefixIcon,
                color: hasValue ? theme.primaryColor : AppColors.grey400,
                size: ResponsiveHelper.iconSize(context, 20),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Expanded(
                child: Text(
                  value ?? hintText,
                  style: hasValue
                      ? ResponsiveHelper.bodyStyle(context).copyWith(
                          fontWeight: FontWeight.bold,
                        )
                      : ResponsiveHelper.bodyStyle(context).copyWith(
                          color: AppColors.grey400,
                        ),
                ),
              ),
              Icon(
                Icons.expand_more,
                color: hasValue ? theme.primaryColor : AppColors.grey400,
                size: ResponsiveHelper.iconSize(context, 20),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 바텀시트 스크롤 피커 — 시간 선택
  static Future<String?> _showTimePickerSheet(
    BuildContext context,
    ThemeData theme,
    String? currentValue,
    String title,
  ) async {
    final times = FormatHelper.generateTimeList();
    int initialIndex = currentValue != null ? times.indexOf(currentValue) : 0;
    if (initialIndex < 0) initialIndex = 0;
    String selectedTime = times[initialIndex];

    return await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: SizedBox(
            height: 320,
            child: Column(
              children: [
                // 핸들바
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 4),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.grey300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // 타이틀 + 확인
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            Navigator.pop(ctx, selectedTime),
                        child: Text(
                          '확인',
                          style: TextStyle(
                            color: theme.primaryColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: AppColors.grey200),
                // 스크롤 피커
                Expanded(
                  child: CupertinoPicker(
                    scrollController: FixedExtentScrollController(
                      initialItem: initialIndex,
                    ),
                    itemExtent: 48,
                    selectionOverlay: CupertinoPickerDefaultSelectionOverlay(
                      background: theme.primaryColor.withValues(alpha: 0.08),
                    ),
                    onSelectedItemChanged: (i) {
                      selectedTime = times[i];
                    },
                    children: times
                        .map(
                          (t) => Center(
                            child: Text(
                              t,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// ✨ 급여 입력 섹션
  static Widget _buildWageSection(
    BuildContext context,
    ThemeData theme,
    String selectedWageType,
    TextEditingController wageController,
    String? startTime,
    String? endTime,
    int breakMinutes,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
              decoration: BoxDecoration(
                color: AppColors.amber.withValues(alpha: 0.1),
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
        if (selectedWageType == 'hourly') ...[
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Container(
            padding: ResponsiveHelper.cardPadding(context),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.infoBg, AppColors.infoExtraLight],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    size: ResponsiveHelper.iconSize(context, 16),
                    color: AppColors.infoDark),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Expanded(
                  child: Text(
                    '${DateTime.now().year}년 최저시급: ${LaborStandards.formatCurrencyWithUnit(LaborStandards.currentMinimumWage)}',
                    style: ResponsiveHelper.smallStyle(context,
                        color: AppColors.infoDeep),
                  ),
                ),
              ],
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: wageController,
            builder: (context, value, _) {
              final wage = int.tryParse(value.text.replaceAll(',', ''));
              final minWage = WageCalculator.currentMinimumWage;
              if (wage == null || wage <= 0 || wage >= minWage) {
                return const SizedBox.shrink();
              }
              return Column(children: [
                SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                Container(
                  padding: ResponsiveHelper.cardPadding(context),
                  decoration: BoxDecoration(
                    color: AppColors.warningBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.warningLight),
                  ),
                  child: Row(children: [
                    Icon(Icons.warning_amber_rounded,
                        size: ResponsiveHelper.iconSize(context, 16),
                        color: AppColors.warningDark),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    Expanded(
                      child: Text(
                        '최저시급(${LaborStandards.formatCurrencyWithUnit(minWage)})보다 낮습니다. 실제 지급 시 법적 문제가 발생할 수 있습니다.',
                        style: ResponsiveHelper.smallStyle(context,
                            color: AppColors.warningDeep),
                      ),
                    ),
                  ]),
                ),
              ]);
            },
          ),
        ],
        // 일급: 환산시급 최저임금 충족 여부
        if (selectedWageType == 'daily' &&
            startTime != null &&
            endTime != null) ...[
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: wageController,
            builder: (context, value, _) {
              final wage = int.tryParse(value.text.replaceAll(',', ''));
              if (wage == null || wage <= 0) return const SizedBox.shrink();

              int toMins(String t) {
                final p = t.split(':');
                return int.parse(p[0]) * 60 + int.parse(p[1]);
              }
              int s = toMins(startTime);
              int e = toMins(endTime);
              if (e <= s) e += 1440;
              final workMins = (e - s - breakMinutes).clamp(1, 1440);
              final hourlyEquiv = (wage * 60 / workMins).round();
              final minWage = WageCalculator.currentMinimumWage;
              final isMet = hourlyEquiv >= minWage;

              return Container(
                padding: ResponsiveHelper.cardPadding(context),
                decoration: BoxDecoration(
                  color: isMet ? AppColors.infoBg : AppColors.warningBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isMet
                        ? AppColors.infoLight
                        : AppColors.warningLight,
                  ),
                ),
                child: Row(children: [
                  Icon(
                    isMet
                        ? Icons.check_circle_outline
                        : Icons.warning_amber_rounded,
                    size: ResponsiveHelper.iconSize(context, 16),
                    color: isMet ? AppColors.infoDark : AppColors.warningDark,
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  Expanded(
                    child: Text(
                      isMet
                          ? '환산시급 ${FormatHelper.formatNumber(hourlyEquiv)}원 — 최저시급 충족'
                          : '환산시급 ${FormatHelper.formatNumber(hourlyEquiv)}원 — 최저시급(${FormatHelper.formatNumber(minWage)}원) 미달',
                      style: ResponsiveHelper.smallStyle(context,
                          color: isMet
                              ? AppColors.infoDeep
                              : AppColors.warningDeep),
                    ),
                  ),
                ]),
              );
            },
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
                color: AppColors.purple.withValues(alpha: 0.1),
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
    String? shiftType,
    bool nightAllowanceApplied,
    bool nightIncluded,
    bool weeklyHolidayIncluded,
    int? scheduledDaysPerWeek,
    int breakMinutes,
    TextEditingController baseHourlyWageController,
  ) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: AppColors.grey200),
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
                side: BorderSide(color: AppColors.grey300),
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
                    theme.primaryColor.withValues(alpha: 0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: theme.primaryColor.withValues(alpha: 0.4),
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

                    if (selectedWageType == 'daily' && shiftType == null) {
                      ToastHelper.showError('일급제는 근무 시간대(주간/석간/야간)를 선택해주세요');
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
                        shiftType: shiftType,
                        nightAllowanceApplied: nightAllowanceApplied,
                        nightIncluded: nightIncluded,
                        weeklyHolidayIncluded: weeklyHolidayIncluded,
                        scheduledDaysPerWeek: scheduledDaysPerWeek,
                        breakMinutes: breakMinutes,
                        baseHourlyWage: int.tryParse(
                          baseHourlyWageController.text.replaceAll(',', ''),
                        ),
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

  /// 일급제 통상시급 섹션 — 연장·야간 계산 기준 시급 입력
  /// wageType == 'daily' 일 때만 호출할 것
  static Widget _buildBaseHourlyWageSection(
    BuildContext context,
    ThemeData theme,
    TextEditingController wageController,
    TextEditingController baseHourlyWageController,
    String? startTime,
    String? endTime,
    int breakMinutes,
  ) {
    final dailyWage =
        int.tryParse(wageController.text.replaceAll(',', '')) ?? 0;
    final hasWageAndTimes =
        dailyWage > 0 && startTime != null && endTime != null;
    final minimumWage = WageCalculator.currentMinimumWage;
    final rawOrdinaryHourly = hasWageAndTimes
        ? WageCalculator.computeOrdinaryHourlyWage(
            scheduledStart: startTime,
            scheduledEnd: endTime,
            breakMinutes: breakMinutes,
            dailyWage: dailyWage,
          )
        : null;
    // 통상임금 < 최저임금이면 최저임금 기준으로 표시
    final effectiveOrdinaryHourly = rawOrdinaryHourly != null
        ? (rawOrdinaryHourly < minimumWage ? minimumWage : rawOrdinaryHourly)
        : null;
    final isUsingMinimumWage =
        rawOrdinaryHourly != null && rawOrdinaryHourly < minimumWage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
              decoration: BoxDecoration(
                color: AppColors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.calculate_outlined,
                  size: ResponsiveHelper.iconSize(context, 18),
                  color: AppColors.amberDark),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '통상시급',
                    style: ResponsiveHelper.subtitleStyle(context)
                        .copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '연장·야간 계산 기준',
                    style: ResponsiveHelper.smallStyle(
                        context, color: AppColors.grey500),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        if (!hasWageAndTimes) ...[
          Container(
            padding: ResponsiveHelper.cardPadding(context),
            decoration: BoxDecoration(
              color: AppColors.infoBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.infoLight),
            ),
            child: Row(children: [
              Icon(Icons.info_outline,
                  size: ResponsiveHelper.iconSize(context, 16),
                  color: AppColors.infoDark),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Expanded(
                child: Text(
                  '일급과 근무 시간을 먼저 입력하면\n통상임금이 자동 계산됩니다.',
                  style: ResponsiveHelper.smallStyle(context,
                      color: AppColors.infoDeep),
                ),
              ),
            ]),
          ),
        ] else ...[
          TextFormField(
            controller: baseHourlyWageController,
            keyboardType: TextInputType.number,
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              fontWeight: FontWeight.bold,
              fontSize: ResponsiveHelper.getFontSize(context, 16),
            ),
            inputFormatters: [NumberInputFormatter()],
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.grey50,
              hintText: effectiveOrdinaryHourly != null
                  ? '미입력 시 통상임금기준(${FormatHelper.formatNumber(effectiveOrdinaryHourly)}원)'
                  : '통상시급을 입력하세요',
              hintStyle: ResponsiveHelper.smallStyle(
                  context, color: AppColors.grey400),
              suffixText: '원/시간',
              suffixStyle: ResponsiveHelper.bodyStyle(context).copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.amberDark,
              ),
              prefixIcon: Icon(Icons.calculate_outlined,
                  color: theme.primaryColor,
                  size: ResponsiveHelper.iconSize(context, 24)),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.grey300)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.grey300)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      BorderSide(color: theme.primaryColor, width: 2)),
            ),
          ),
          if (effectiveOrdinaryHourly != null) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            Container(
              padding: ResponsiveHelper.cardPadding(context),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: [AppColors.infoBg, AppColors.infoExtraLight]),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Icon(Icons.info_outline,
                    size: ResponsiveHelper.iconSize(context, 16),
                    color: AppColors.infoDark),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Expanded(
                  child: Text(
                    isUsingMinimumWage
                        ? '당해년도 최저임금 기준: ${FormatHelper.formatNumber(effectiveOrdinaryHourly)}원/시간'
                        : '통상시급 기준: ${FormatHelper.formatNumber(effectiveOrdinaryHourly)}원/시간',
                    style: ResponsiveHelper.smallStyle(context,
                        color: AppColors.infoDeep),
                  ),
                ),
              ]),
            ),
          ],
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: baseHourlyWageController,
            builder: (context, value, _) {
              final entered = int.tryParse(value.text.replaceAll(',', ''));
              if (entered == null ||
                  entered <= 0 ||
                  effectiveOrdinaryHourly == null ||
                  entered >= effectiveOrdinaryHourly) {
                return const SizedBox.shrink();
              }
              return Column(children: [
                SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                Container(
                  padding: ResponsiveHelper.cardPadding(context),
                  decoration: BoxDecoration(
                    color: AppColors.warningBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.warningLight),
                  ),
                  child: Row(children: [
                    Icon(Icons.warning_amber_rounded,
                        size: ResponsiveHelper.iconSize(context, 16),
                        color: AppColors.warningDark),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    Expanded(
                      child: Text(
                        '입력한 통상시급(${FormatHelper.formatNumber(entered)}원)이 기준(${FormatHelper.formatNumber(effectiveOrdinaryHourly)}원)보다 낮습니다. 수당 미달 분쟁 소지가 있습니다.',
                        style: ResponsiveHelper.smallStyle(context,
                            color: AppColors.warningDeep),
                      ),
                    ),
                  ]),
                ),
              ]);
            },
          ),
        ],
      ],
    );
  }

  /// 주휴수당 정책 섹션
  static Widget _buildWeeklyHolidaySection(
    BuildContext context,
    ThemeData theme,
    bool weeklyHolidayIncluded,
    int? scheduledDaysPerWeek,
    StateSetter setDialogState,
    Function(bool) onIncludedChanged,
    Function(int?) onScheduledDaysChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.event_available_outlined,
                  size: ResponsiveHelper.iconSize(context, 18),
                  color: AppColors.successDark),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('주휴수당 정책',
                      style: ResponsiveHelper.subtitleStyle(context)
                          .copyWith(fontWeight: FontWeight.bold)),
                  Text(
                    weeklyHolidayIncluded
                        ? '주 15h 이상 & 소정근로일 개근 시 급여 확정 때 별도 지급'
                        : '시급/일급에 주휴수당 포함됨',
                    style: ResponsiveHelper.smallStyle(context,
                        color: AppColors.grey500),
                  ),
                ],
              ),
            ),
            Switch(
              value: weeklyHolidayIncluded,
              onChanged: (v) => setDialogState(() => onIncludedChanged(v)),
              activeThumbColor: AppColors.successDark,
            ),
          ],
        ),
        // 주휴 별도지급 활성화 시 소정근로일 수 선택
        if (weeklyHolidayIncluded) ...[
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          Row(
            children: [
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
              Text(
                '소정근로일 수',
                style: ResponsiveHelper.bodyStyle(context)
                    .copyWith(fontWeight: FontWeight.w600, color: AppColors.grey700),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Text(
                '(주 기준 계약 근무일)',
                style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Row(
            children: List.generate(7, (i) {
              final day = i + 1;
              final isSelected = scheduledDaysPerWeek == day;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: day < 7 ? ResponsiveHelper.spacing(context, 6) : 0,
                  ),
                  child: GestureDetector(
                    onTap: () => setDialogState(() =>
                        onScheduledDaysChanged(isSelected ? null : day)),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        vertical: ResponsiveHelper.spacing(context, 10),
                      ),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.successDark : Colors.white,
                        border: Border.all(
                          color: isSelected ? AppColors.successDark : AppColors.grey300,
                          width: isSelected ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${day}일', // ignore: unnecessary_brace_in_string_interps
                        textAlign: TextAlign.center,
                        style: ResponsiveHelper.smallStyle(context).copyWith(
                          color: isSelected ? Colors.white : AppColors.grey700,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }

  /// 야간수당 설정 섹션
  ///
  /// - 야간수당 적용 ON/OFF 토글 (모든 급여 유형)
  /// - 일급 + 야간수당 적용 ON: 근무시간대(주간/석간/야간) 칩 + 야간포함 여부 토글
  static Widget _buildShiftAndNightSection(
    BuildContext context,
    ThemeData theme,
    String wageType,
    String? shiftType,
    bool nightAllowanceApplied,
    bool nightIncluded,
    StateSetter setDialogState,
    Function(String?) onShiftChanged,
    Function(bool) onNightAllowanceChanged,
    Function(bool) onNightIncludedChanged,
  ) {
    const shifts = ['주간', '석간', '야간'];
    final showDailyOptions = nightAllowanceApplied && wageType == 'daily';
    final showNightIncluded = showDailyOptions && (shiftType == '석간' || shiftType == '야간');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 야간수당 적용 헤더 + 토글 ──────────────────────
        Row(
          children: [
            Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
              decoration: BoxDecoration(
                color: AppColors.infoDark.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.nights_stay_outlined, size: ResponsiveHelper.iconSize(context, 18), color: AppColors.infoDark),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('야간수당 설정', style: ResponsiveHelper.subtitleStyle(context).copyWith(fontWeight: FontWeight.bold)),
                  Text('22:00~06:00 구간 0.5배 가산', style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500)),
                ],
              ),
            ),
            Switch(
              value: nightAllowanceApplied,
              onChanged: (v) => setDialogState(() => onNightAllowanceChanged(v)),
              activeThumbColor: theme.primaryColor,
            ),
          ],
        ),

        // ── 일급 전용: 근무시간대 + 야간포함 ──────────────
        if (showDailyOptions) ...[
          SizedBox(height: ResponsiveHelper.spacing(context, 14)),
          Text('근무 시간대', style: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.w600, color: AppColors.grey700)),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Row(
            children: shifts.map((s) {
              final isSelected = shiftType == s;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: s != '야간' ? ResponsiveHelper.spacing(context, 8) : 0),
                  child: GestureDetector(
                    onTap: () => setDialogState(() {
                      onShiftChanged(s);
                      // 석간/야간 선택 시 야간수당 일급 포함 자동 ON
                      // (일급에 야간수당이 포함된 것이 일반적이므로 기본값 true)
                      if (s == '주간') {
                        onNightIncludedChanged(false);
                      } else {
                        onNightIncludedChanged(true);
                      }
                    }),
                    child: Container(
                      padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 11)),
                      decoration: BoxDecoration(
                        color: isSelected ? theme.primaryColor : Colors.white,
                        border: Border.all(color: isSelected ? theme.primaryColor : AppColors.grey300, width: isSelected ? 2 : 1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        s,
                        textAlign: TextAlign.center,
                        style: ResponsiveHelper.bodyStyle(context).copyWith(
                          color: isSelected ? Colors.white : AppColors.grey700,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          if (showNightIncluded) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 10)),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 14),
                vertical: ResponsiveHelper.spacing(context, 8),
              ),
              decoration: BoxDecoration(
                color: AppColors.grey50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.grey200),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('야간수당 일급 포함', style: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.w600)),
                        SizedBox(height: 2),
                        Text('일급에 야간수당 이미 포함 시 ON\n(초과분에만 추가 적용)', style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500)),
                      ],
                    ),
                  ),
                  Switch(
                    value: nightIncluded,
                    onChanged: (v) => setDialogState(() => onNightIncludedChanged(v)),
                    activeThumbColor: theme.primaryColor,
                  ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }

  /// 휴게시간 섹션
  static Widget _buildBreakMinutesSection(
    BuildContext context,
    ThemeData theme,
    int breakMinutes,
    StateSetter setDialogState,
    Function(int) onChanged,
  ) {
    const presets = [0, 30, 60, 90];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
              decoration: BoxDecoration(
                color: AppColors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.coffee, size: ResponsiveHelper.iconSize(context, 18), color: AppColors.amberDark),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            Text('휴게시간', style: ResponsiveHelper.subtitleStyle(context).copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        Row(
          children: presets.map((min) {
            final isSelected = breakMinutes == min;
            final label = min == 0 ? '없음' : '$min분';
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: min != 90 ? ResponsiveHelper.spacing(context, 8) : 0),
                child: GestureDetector(
                  onTap: () => setDialogState(() => onChanged(min)),
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 12)),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.amberDark : Colors.white,
                      border: Border.all(color: isSelected ? AppColors.amberDark : AppColors.grey300, width: isSelected ? 2 : 1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: ResponsiveHelper.smallStyle(context).copyWith(
                        color: isSelected ? Colors.white : AppColors.grey700,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
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
                    theme.primaryColor.withValues(alpha: 0.8),
                  ],
                )
              : null,
          color: isSelected ? null : Colors.white,
          border: Border.all(
            color: isSelected 
                ? theme.primaryColor
                : AppColors.grey300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: theme.primaryColor.withValues(alpha: 0.3),
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
