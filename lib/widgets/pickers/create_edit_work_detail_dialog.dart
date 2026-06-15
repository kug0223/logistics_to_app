import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/core/business_work_type_model.dart';
import '../../utils/toast_helper.dart';
import '../../utils/labor_standards.dart';
import '../../utils/responsive_helper.dart';
import '../../models/work_detail_input.dart';
import '../../models/core/insurance_rate_model.dart';
import '../work_type_icon.dart';
import '../../utils/format_helper.dart';
import '../../models/core/work_detail_data.dart';
import '../../theme/app_colors.dart';
import '../dialogs/styled_dialog.dart';
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
    int breakMinutes = 0;
    String? payScheduleType;
    int? payScheduleDay;
    String? payScheduleTime;
    String taxDeductionType = InsuranceRateModel.typeNone;
    final wageController = TextEditingController();
    final countController = TextEditingController();
    final baseHourlyWageController = TextEditingController();
    final descriptionController = TextEditingController();

    return showDialog<WorkDetailInput>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            insetPadding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 16),
              vertical: AppDialogSize.insetV,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * AppDialogSize.maxHeightRatio,
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

                          // 급여 지급 일정
                          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                          _buildPayScheduleSection(
                            context, theme,
                            payScheduleType, payScheduleDay, payScheduleTime,
                            setDialogState,
                            (t) { payScheduleType = t; payScheduleDay = null; },
                            (d) { payScheduleDay = d; },
                            (t) { payScheduleTime = t; },
                          ),

                          // 공제 방식
                          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                          _buildTaxDeductionSection(
                            context, theme,
                            taxDeductionType,
                            setDialogState,
                            (v) { taxDeductionType = v; },
                          ),

                          // 필요 인원
                          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                          _buildCountSection(
                            context,
                            theme,
                            countController,
                          ),

                          // 업무 설명 (선택)
                          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                          _buildDescriptionField(context, theme, descriptionController),
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
                    breakMinutes,
                    baseHourlyWageController,
                    payScheduleType,
                    payScheduleDay,
                    payScheduleTime,
                    taxDeductionType,
                    descriptionController,
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
    int breakMinutes = work.breakMinutes;
    String? payScheduleType = work.payScheduleType;
    int? payScheduleDay = work.payScheduleDay;
    String? payScheduleTime = work.payScheduleTime;
    String taxDeductionType = work.taxDeductionType;
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
    final descriptionController = TextEditingController(
      text: work.description ?? '',
    );

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            insetPadding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 16),
              vertical: AppDialogSize.insetV,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * AppDialogSize.maxHeightRatio,
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
                          // 급여 지급 일정
                          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                          _buildPayScheduleSection(
                            context, theme,
                            payScheduleType, payScheduleDay, payScheduleTime,
                            setDialogState,
                            (t) { payScheduleType = t; payScheduleDay = null; },
                            (d) { payScheduleDay = d; },
                            (t) { payScheduleTime = t; },
                          ),

                          // 공제 방식
                          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                          _buildTaxDeductionSection(
                            context, theme,
                            taxDeductionType,
                            setDialogState,
                            (v) { taxDeductionType = v; },
                          ),

                          SizedBox(height: ResponsiveHelper.spacing(context, 24)),

                          // 필요 인원
                          _buildEditCountSection(
                            context,
                            theme,
                            countController,
                            currentCount,
                          ),

                          // 업무 설명 (선택)
                          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                          _buildDescriptionField(context, theme, descriptionController),
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
                    breakMinutes,
                    baseHourlyWageController,
                    payScheduleType,
                    payScheduleDay,
                    payScheduleTime,
                    taxDeductionType,
                    descriptionController,
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
    int breakMinutes,
    TextEditingController baseHourlyWageController,
    String? payScheduleType,
    int? payScheduleDay,
    String? payScheduleTime,
    String taxDeductionType,
    TextEditingController descriptionController,
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
                  onTap: () async {
                    final wage = int.tryParse(wageController.text.replaceAll(',', ''));
                    final count = int.tryParse(countController.text);

                    if (wage == null || wage <= 0 || count == null || count <= 0) {
                      ToastHelper.showError('유효한 금액(0원 초과)과 인원(1명 이상)을 입력하세요');
                      return;
                    }

                    if (currentCount > 0 && count < currentCount) {
                      if (!context.mounted) return;
                      final proceed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('모집인원 축소 경고'),
                          content: Text(
                            '현재 확정 인원($currentCount명)보다 적게 설정합니다.\n'
                            '이미 확정된 인원이 초과 상태가 됩니다. 계속하시겠습니까?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('취소'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text(
                                '저장',
                                style: TextStyle(color: Colors.orange[700]),
                              ),
                            ),
                          ],
                        ),
                      );
                      if (proceed != true) return;
                      if (!context.mounted) return;
                    }

                    if (selectedWageType == 'daily' && shiftType == null) {
                      ToastHelper.showError('일급제는 근무 시간대(주간/석간/야간)를 선택해주세요');
                      return;
                    }

                    if (payScheduleType == null) {
                      ToastHelper.showError('급여 지급 일정을 선택해주세요');
                      return;
                    }

                    if ((payScheduleType == 'weekly' || payScheduleType == 'monthly') &&
                        payScheduleDay == null) {
                      ToastHelper.showError(
                        payScheduleType == 'weekly' ? '지급 요일을 선택해주세요' : '지급 날짜를 선택해주세요',
                      );
                      return;
                    }

                    // 최저임금 위반 경고
                    final minWage = WageCalculator.currentMinimumWage;
                    if (selectedWageType == 'hourly' && wage < minWage) {
                      if (!context.mounted) return;
                      final proceed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('최저임금 미달 경고'),
                          content: Text(
                            '입력한 시급(${FormatHelper.formatNumber(wage)}원)이\n'
                            '최저임금(${FormatHelper.formatNumber(minWage)}원)보다 낮습니다.\n\n'
                            '최저임금법 위반 시 3년 이하 징역 또는 2천만 원 이하 벌금이 부과됩니다.\n'
                            '그래도 저장하시겠습니까?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('수정하기'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text('저장', style: TextStyle(color: Colors.red[700])),
                            ),
                          ],
                        ),
                      );
                      if (proceed != true) return;
                      if (!context.mounted) return;
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
                      'breakMinutes': breakMinutes,
                      'baseHourlyWage': int.tryParse(
                        baseHourlyWageController.text.replaceAll(',', ''),
                      ),
                      'payScheduleType': payScheduleType,
                      if (payScheduleDay != null) 'payScheduleDay': payScheduleDay,
                      if (payScheduleTime != null) 'payScheduleTime': payScheduleTime,
                      'taxDeductionType': taxDeductionType,
                      if (descriptionController.text.trim().isNotEmpty)
                        'description': descriptionController.text.trim(),
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
                if (selected != null && context.mounted) {
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
                if (selected != null && context.mounted) {
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
    int initialIndex;
    if (currentValue != null) {
      initialIndex = times.indexOf(currentValue);
      if (initialIndex < 0) initialIndex = 0;
    } else {
      // 값이 없을 때 현재 시각 기준 가장 가까운 30분 단위로 초기화 (00:00 방지)
      final now = DateTime.now();
      final roundedMinute = (now.minute / 30).round() * 30;
      final hour = roundedMinute >= 60 ? (now.hour + 1) % 24 : now.hour;
      final minute = roundedMinute >= 60 ? 0 : roundedMinute;
      final nowStr = '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
      initialIndex = times.indexOf(nowStr);
      if (initialIndex < 0) initialIndex = 16; // 없으면 08:00
    }
    String selectedTime = times[initialIndex];

    return showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
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
                        style: ResponsiveHelper.subtitleStyle(context).copyWith(
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

  /// ✨ 업무 설명 섹션 (선택 사항)
  static Widget _buildDescriptionField(
    BuildContext context,
    ThemeData theme,
    TextEditingController controller,
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
                Icons.description_outlined,
                size: ResponsiveHelper.iconSize(context, 18),
                color: AppColors.infoDark,
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            Text(
              '업무 설명 (선택)',
              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        TextFormField(
          controller: controller,
          maxLines: 3,
          maxLength: 200,
          style: ResponsiveHelper.bodyStyle(context),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.grey50,
            hintText: '업무에 대한 간단한 설명을 입력하세요',
            hintStyle: ResponsiveHelper.bodyStyle(context, color: AppColors.grey400),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.primaryColor, width: 2),
            ),
            counterStyle: ResponsiveHelper.smallStyle(context, color: AppColors.grey400),
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
    int breakMinutes,
    TextEditingController baseHourlyWageController,
    String? payScheduleType,
    int? payScheduleDay,
    String? payScheduleTime,
    String taxDeductionType,
    TextEditingController descriptionController,
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

                    // 최저시급 미만 하드 차단 (시급제 직접 비교, 일급제는 환산시급 비교)
                    final minWage = WageCalculator.currentMinimumWage;
                    if (selectedWageType == 'hourly' && wage < minWage) {
                      ToastHelper.showError(
                        '시급이 최저시급(${FormatHelper.formatNumber(minWage)}원) 미만입니다.\n최저시급 이상으로 입력해주세요.');
                      return;
                    }
                    if (selectedWageType == 'daily') {
                      // 시작~종료 분 계산 (자정 경계 처리)
                      int toMin(String t) {
                        final p = t.split(':');
                        return int.parse(p[0]) * 60 + int.parse(p[1]);
                      }
                      int sMin = toMin(startTime), eMin = toMin(endTime);
                      if (eMin <= sMin) eMin += 1440;
                      final workMins = (eMin - sMin - breakMinutes).clamp(0, 9999);
                      if (workMins > 0) {
                        final hourlyEquiv = (wage * 60 / workMins).round();
                        if (hourlyEquiv < minWage) {
                          ToastHelper.showError(
                            '환산시급(${FormatHelper.formatNumber(hourlyEquiv)}원)이 최저시급(${FormatHelper.formatNumber(minWage)}원) 미만입니다.\n일급을 올려주세요.');
                          return;
                        }
                      }
                    }

                    if (count == null || count <= 0) {
                      ToastHelper.showError('유효한 인원 수를 입력해주세요');
                      return;
                    }

                    // 시작 = 종료 (0분 근무) 차단
                    if (startTime == endTime) {
                      ToastHelper.showError('시작 시간과 종료 시간이 같을 수 없습니다');
                      return;
                    }

                    if (selectedWageType == 'daily' && shiftType == null) {
                      ToastHelper.showError('일급제는 근무 시간대(주간/석간/야간)를 선택해주세요');
                      return;
                    }

                    if (payScheduleType == null) {
                      ToastHelper.showError('급여 지급 일정을 선택해주세요');
                      return;
                    }

                    if ((payScheduleType == 'weekly' || payScheduleType == 'monthly') &&
                        payScheduleDay == null) {
                      ToastHelper.showError(
                        payScheduleType == 'weekly' ? '지급 요일을 선택해주세요' : '지급 날짜를 선택해주세요',
                      );
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
                        breakMinutes: breakMinutes,
                        baseHourlyWage: int.tryParse(
                          baseHourlyWageController.text.replaceAll(',', ''),
                        ),
                        payScheduleType: payScheduleType,
                        payScheduleDay: payScheduleDay,
                        payScheduleTime: payScheduleTime,
                        taxDeductionType: taxDeductionType,
                        description: descriptionController.text.trim().isEmpty
                            ? null
                            : descriptionController.text.trim(),
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

  // ── 급여 지급 일정 섹션 ──────────────────────────────────────────

  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  static Widget _buildPayScheduleSection(
    BuildContext context,
    ThemeData theme,
    String? payScheduleType,
    int? payScheduleDay,
    String? payScheduleTime,
    StateSetter setDialogState,
    Function(String) onTypeChanged,
    Function(int) onDayChanged,
    Function(String?) onTimeChanged,
  ) {
    final types = [
      ('same_day', '당일', Icons.wb_sunny_outlined),
      ('next_day', '익일', Icons.brightness_3),
      ('weekly',   '주급', Icons.date_range),
      ('monthly',  '월급', Icons.calendar_month),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 헤더
        Row(
          children: [
            Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
              decoration: BoxDecoration(
                color: AppColors.successDark.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.account_balance_wallet_outlined,
                  size: ResponsiveHelper.iconSize(context, 18),
                  color: AppColors.successDark),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            Text('급여 지급 일정',
                style: ResponsiveHelper.subtitleStyle(context)
                    .copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),

        // 유형 버튼 4개
        Row(
          children: types.map((t) {
            final (value, label, icon) = t;
            final isSelected = payScheduleType == value;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                    right: value != 'monthly'
                        ? ResponsiveHelper.spacing(context, 6)
                        : 0),
                child: GestureDetector(
                  onTap: () => setDialogState(() => onTypeChanged(value)),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                        vertical: ResponsiveHelper.spacing(context, 12)),
                    decoration: BoxDecoration(
                      gradient: isSelected
                          ? LinearGradient(colors: [
                              AppColors.successDark,
                              AppColors.successDark.withValues(alpha: 0.8),
                            ])
                          : null,
                      color: isSelected ? null : Colors.white,
                      border: Border.all(
                        color: isSelected ? AppColors.successDark : AppColors.grey300,
                        width: isSelected ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: isSelected
                          ? [BoxShadow(
                              color: AppColors.successDark.withValues(alpha: 0.3),
                              blurRadius: 6, offset: const Offset(0, 3))]
                          : null,
                    ),
                    child: Column(
                      children: [
                        Icon(icon,
                            size: ResponsiveHelper.iconSize(context, 18),
                            color: isSelected ? Colors.white : AppColors.grey500),
                        SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                        Text(label,
                            style: ResponsiveHelper.smallStyle(context).copyWith(
                              color: isSelected ? Colors.white : AppColors.grey700,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            )),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        // 주급: 요일 선택
        if (payScheduleType == 'weekly') ...[
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          Text('지급 요일',
              style: ResponsiveHelper.bodyStyle(context)
                  .copyWith(fontWeight: FontWeight.w600, color: AppColors.grey700)),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Row(
            children: List.generate(7, (i) {
              final day = i + 1; // 1=월 ~ 7=일
              final isSelected = payScheduleDay == day;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                      right: i < 6 ? ResponsiveHelper.spacing(context, 4) : 0),
                  child: GestureDetector(
                    onTap: () => setDialogState(() => onDayChanged(day)),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                          vertical: ResponsiveHelper.spacing(context, 10)),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.successDark : Colors.white,
                        border: Border.all(
                          color: isSelected ? AppColors.successDark : AppColors.grey300,
                          width: isSelected ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_weekdays[i],
                          textAlign: TextAlign.center,
                          style: ResponsiveHelper.smallStyle(context).copyWith(
                            color: isSelected ? Colors.white : AppColors.grey700,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          )),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],

        // 월급: 날짜 선택 (피커)
        if (payScheduleType == 'monthly') ...[
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          Text('지급일',
              style: ResponsiveHelper.bodyStyle(context)
                  .copyWith(fontWeight: FontWeight.w600, color: AppColors.grey700)),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          GestureDetector(
            onTap: () async {
              final selected = await _showMonthlyDatePicker(context, theme, payScheduleDay);
              if (selected != null) setDialogState(() => onDayChanged(selected));
            },
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 16),
                vertical: ResponsiveHelper.spacing(context, 14),
              ),
              decoration: BoxDecoration(
                color: AppColors.grey50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: payScheduleDay != null ? AppColors.successDark : AppColors.grey300,
                  width: payScheduleDay != null ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.event,
                      color: payScheduleDay != null ? AppColors.successDark : AppColors.grey400,
                      size: ResponsiveHelper.iconSize(context, 20)),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                  Expanded(
                    child: Text(
                      payScheduleDay != null
                          ? (payScheduleDay == 31 ? '매월 말일' : '매월 $payScheduleDay일')
                          : '날짜를 선택하세요',
                      style: payScheduleDay != null
                          ? ResponsiveHelper.bodyStyle(context)
                              .copyWith(fontWeight: FontWeight.bold)
                          : ResponsiveHelper.bodyStyle(context)
                              .copyWith(color: AppColors.grey400),
                    ),
                  ),
                  Icon(Icons.expand_more,
                      color: payScheduleDay != null ? AppColors.successDark : AppColors.grey400,
                      size: ResponsiveHelper.iconSize(context, 20)),
                ],
              ),
            ),
          ),
        ],

        // 입금 예정 시간 (공통, 선택)
        if (payScheduleType != null) ...[
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          GestureDetector(
            onTap: () async {
              final selected =
                  await _showTimePickerSheet(context, theme, payScheduleTime, '입금 예정 시간');
              if (selected != null) setDialogState(() => onTimeChanged(selected));
            },
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 16),
                vertical: ResponsiveHelper.spacing(context, 12),
              ),
              decoration: BoxDecoration(
                color: AppColors.grey50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: payScheduleTime != null
                      ? AppColors.successDark
                      : AppColors.grey200,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.access_time,
                      size: ResponsiveHelper.iconSize(context, 18),
                      color: payScheduleTime != null
                          ? AppColors.successDark
                          : AppColors.grey400),
                  SizedBox(width: ResponsiveHelper.spacing(context, 10)),
                  Expanded(
                    child: Text(
                      payScheduleTime != null
                          ? '입금 예정 $payScheduleTime'
                          : '입금 예정 시간 선택 (선택사항)',
                      style: ResponsiveHelper.smallStyle(context).copyWith(
                        color: payScheduleTime != null
                            ? AppColors.grey800
                            : AppColors.grey400,
                        fontWeight: payScheduleTime != null
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (payScheduleTime != null)
                    GestureDetector(
                      onTap: () => setDialogState(() => onTimeChanged(null)),
                      child: Icon(Icons.close,
                          size: ResponsiveHelper.iconSize(context, 16),
                          color: AppColors.grey400),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  static Future<int?> _showMonthlyDatePicker(
    BuildContext context,
    ThemeData theme,
    int? current,
  ) async {
    // 1~30 + 말일(31)
    final items = [
      ...List.generate(30, (i) => i + 1),
      31,
    ];
    final labels = [...List.generate(30, (i) => '${i + 1}일'), '말일'];
    int initialIndex = current != null ? items.indexOf(current) : 0;
    if (initialIndex < 0) initialIndex = 0;
    int selected = items[initialIndex];

    return showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: 320,
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: AppColors.grey300,
                    borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('지급일 선택',
                        style: ResponsiveHelper.subtitleStyle(context).copyWith(fontWeight: FontWeight.bold)),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, selected),
                      child: Text('확인',
                          style: TextStyle(
                              color: theme.primaryColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: AppColors.grey200),
              Expanded(
                child: CupertinoPicker(
                  scrollController:
                      FixedExtentScrollController(initialItem: initialIndex),
                  itemExtent: 48,
                  selectionOverlay: CupertinoPickerDefaultSelectionOverlay(
                      background: theme.primaryColor.withValues(alpha: 0.08)),
                  onSelectedItemChanged: (i) => selected = items[i],
                  children: labels
                      .map((l) => Center(
                            child: Text(l,
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w500)),
                          ))
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 무급 휴게시간 섹션
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('무급 휴게시간', style: ResponsiveHelper.subtitleStyle(context).copyWith(fontWeight: FontWeight.bold)),
                Text('임금에서 공제되는 시간', style: ResponsiveHelper.captionStyle(context).copyWith(color: AppColors.grey500)),
              ],
            ),
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

  /// 공제 방식 선택 섹션
  static Widget _buildTaxDeductionSection(
    BuildContext context,
    ThemeData theme,
    String taxDeductionType,
    StateSetter setDialogState,
    void Function(String) onChanged,
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
                Icons.account_balance_outlined,
                size: ResponsiveHelper.iconSize(context, 18),
                color: theme.primaryColor,
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '공제 방식',
                  style: ResponsiveHelper.subtitleStyle(context)
                      .copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  '임금에서 차감할 세금·보험 방식',
                  style: ResponsiveHelper.captionStyle(context)
                      .copyWith(color: AppColors.grey500),
                ),
              ],
            ),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        ...InsuranceRateModel.allTypes.map((type) {
          final isSelected = taxDeductionType == type;
          return GestureDetector(
            onTap: () => setDialogState(() => onChanged(type)),
            child: Container(
              margin: EdgeInsets.only(
                  bottom: ResponsiveHelper.spacing(context, 8)),
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 14),
                vertical: ResponsiveHelper.spacing(context, 12),
              ),
              decoration: BoxDecoration(
                color: isSelected
                    ? theme.primaryColor.withValues(alpha: 0.08)
                    : Colors.white,
                border: Border.all(
                  color: isSelected ? theme.primaryColor : AppColors.grey300,
                  width: isSelected ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    isSelected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: ResponsiveHelper.iconSize(context, 20),
                    color: isSelected ? theme.primaryColor : AppColors.grey400,
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 10)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          InsuranceRateModel.typeLabel(type),
                          style: ResponsiveHelper.bodyStyle(context).copyWith(
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? theme.primaryColor
                                : AppColors.grey800,
                          ),
                        ),
                        SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                        Text(
                          InsuranceRateModel.typeDescription(type),
                          style: ResponsiveHelper.captionStyle(context)
                              .copyWith(color: AppColors.grey500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
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
