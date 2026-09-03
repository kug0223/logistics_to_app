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
import '../../utils/wage_calculator.dart';
import '../app_select_field.dart';
import '../../utils/dialog_helper.dart';

// ============================================================
// 🎨 업무 추가 다이얼로그 (세련된 디자인)
// ============================================================

class WorkDetailDialog {
  /// ✨ 업무 추가 다이얼로그 표시
  static Future<WorkDetailInput?> showAddDialog({
    required BuildContext context,
    required List<BusinessWorkTypeModel> businessWorkTypes,
  }) {
    return Navigator.of(context, rootNavigator: true).push<WorkDetailInput>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _WorkDetailEditorScreen(
          isEdit: false,
          businessWorkTypes: businessWorkTypes,
        ),
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
  }) {
    return Navigator.of(context, rootNavigator: true).push<Map<String, dynamic>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _WorkDetailEditorScreen(
          isEdit: true,
          businessWorkTypes: businessWorkTypes ?? const [],
          existingWork: work,
          currentCount: currentCount,
        ),
      ),
    );
  }

  /// ✨ 수정 헤더
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
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 6)),
              decoration: BoxDecoration(
                color: AppColors.grey100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.people,
                size: ResponsiveHelper.iconSize(context, 18),
                color: AppColors.grey500,
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

  // ============================================================
  // 🎨 UI 섹션 빌더들
  // ============================================================

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
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 6)),
              decoration: BoxDecoration(
                color: AppColors.grey100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.category,
                size: ResponsiveHelper.iconSize(context, 18),
                color: AppColors.grey500,
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
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 6)),
              decoration: BoxDecoration(
                color: AppColors.grey100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.payments,
                size: ResponsiveHelper.iconSize(context, 18),
                color: AppColors.grey500,
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
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 6)),
              decoration: BoxDecoration(
                color: AppColors.grey100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.schedule,
                size: ResponsiveHelper.iconSize(context, 18),
                color: AppColors.grey500,
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
            // 시작/종료 시간 — 2열 수평 레이아웃
            Row(
              children: [
                Expanded(
                  child: _buildTimePickerTile(
                    context: context,
                    theme: theme,
                    value: startTime,
                    hintText: '시작 시간',
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
                ),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 8),
                  ),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    color: theme.primaryColor,
                    size: ResponsiveHelper.iconSize(context, 18),
                  ),
                ),
                Expanded(
                  child: _buildTimePickerTile(
                    context: context,
                    theme: theme,
                    value: endTime,
                    hintText: '종료 시간',
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
                ),
              ],
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
            horizontal: ResponsiveHelper.spacing(context, 10),
            vertical: ResponsiveHelper.spacing(context, 11),
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
                size: ResponsiveHelper.iconSize(context, 16),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              Expanded(
                child: Text(
                  value ?? hintText,
                  style: hasValue
                      ? ResponsiveHelper.smallStyle(context).copyWith(
                          fontWeight: FontWeight.bold,
                        )
                      : ResponsiveHelper.smallStyle(context).copyWith(
                          color: AppColors.grey400,
                        ),
                ),
              ),
              Icon(
                Icons.expand_more,
                color: hasValue ? theme.primaryColor : AppColors.grey400,
                size: ResponsiveHelper.iconSize(context, 16),
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

    // builder 내부에서 외부 context로 InheritedWidget 조회 시 _dependents 잘못 등록 방지 —
    // showModalBottomSheet 호출 전에 스타일을 미리 캡처해 builder 내부에서 재사용한다.
    final capturedTitleStyle = ResponsiveHelper.subtitleStyle(context)
        .copyWith(fontWeight: FontWeight.bold);
    final capturedConfirmStyle = ResponsiveHelper.bodyStyle(context,
            color: theme.primaryColor)
        .copyWith(fontWeight: FontWeight.bold);
    final capturedItemStyle = ResponsiveHelper.subtitleStyle(context)
        .copyWith(fontWeight: FontWeight.w500);
    final safeBottom = MediaQuery.of(context).padding.bottom;

    return showModalBottomSheet<String>(
      context: context,
      // useSafeArea:true + backgroundColor:transparent 조합 시 홈 인디케이터 높이만큼
      // 흰 컨테이너 아래 투명 갭 발생 → 수동 padding으로 대응
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          constraints: BoxConstraints(maxHeight: 280 + safeBottom),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: AppColors.grey300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title, style: capturedTitleStyle),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, selectedTime),
                      child: Text('확인', style: capturedConfirmStyle),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.grey200),
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
                          child: Text(t, style: capturedItemStyle),
                        ),
                      )
                      .toList(),
                ),
              ),
              SizedBox(height: safeBottom),
            ],
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
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 6)),
              decoration: BoxDecoration(
                color: AppColors.grey100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.currency_exchange,
                size: ResponsiveHelper.iconSize(context, 18),
                color: AppColors.grey500,
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
          SizedBox(height: ResponsiveHelper.spacing(context, 6)),
          Row(
            children: [
              Icon(Icons.info_outline,
                  size: ResponsiveHelper.iconSize(context, 13),
                  color: AppColors.grey400),
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
              Text(
                '${DateTime.now().year}년 최저시급 ${LaborStandards.formatCurrencyWithUnit(LaborStandards.currentMinimumWage)}',
                style: ResponsiveHelper.captionStyle(context,
                    color: AppColors.grey500),
              ),
            ],
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

              // [Phase 6] 8시간 초과 일급 힌트 — 절대 금지 표현 없음
              final showLongShiftHint = workMins > 480;
              final excessMins = workMins - 480;

              String fmtMinsLocal(int m) {
                final h = m ~/ 60;
                final rem = m % 60;
                if (h == 0) return '$rem분';
                if (rem == 0) return '$h시간';
                return '$h시간 $rem분';
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
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
                  ),
                  if (showLongShiftHint) ...[
                    SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.warningBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.warningLight),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '계약 유급시간 ${fmtMinsLocal(workMins)}  ·  '
                            '8시간 초과 예정 ${fmtMinsLocal(excessMins)}',
                            style: ResponsiveHelper.captionStyle(context),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '일급은 위 계약시간 전체의 지급액으로 사용됩니다. '
                            '8시간 초과 구간의 추가 지급분을 포함한 금액을 입력해 주세요.',
                            style: ResponsiveHelper.captionStyle(context),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
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
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 6)),
              decoration: BoxDecoration(
                color: AppColors.grey100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.people,
                size: ResponsiveHelper.iconSize(context, 18),
                color: AppColors.grey500,
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

  /// ✨ 업무 설명 섹션 — V1 비노출, schema/data 보존 (v2 재노출 예비)
  // ignore: unused_element
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
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 6)),
              decoration: BoxDecoration(
                color: AppColors.grey100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.description_outlined,
                size: ResponsiveHelper.iconSize(context, 18),
                color: AppColors.grey500,
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
          maxLines: 2,
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
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 6)),
              decoration: BoxDecoration(
                color: AppColors.grey100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.calculate_outlined,
                  size: ResponsiveHelper.iconSize(context, 18),
                  color: AppColors.grey500),
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
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 6)),
              decoration: BoxDecoration(
                color: AppColors.grey100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.nights_stay_outlined, size: ResponsiveHelper.iconSize(context, 18), color: AppColors.grey500),
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
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 6)),
              decoration: BoxDecoration(
                color: AppColors.grey100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.account_balance_wallet_outlined,
                  size: ResponsiveHelper.iconSize(context, 18),
                  color: AppColors.grey500),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            Text('급여 지급 일정',
                style: ResponsiveHelper.subtitleStyle(context)
                    .copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),

        // 유형 칩 4개 — compact segmented
        Row(
          children: types.map((t) {
            final (value, label, icon) = t;
            final isSelected = payScheduleType == value;
            final isLast = value == 'monthly';
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                    right: isLast ? 0 : ResponsiveHelper.spacing(context, 5)),
                child: GestureDetector(
                  onTap: () => setDialogState(() => onTypeChanged(value)),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                        vertical: ResponsiveHelper.spacing(context, 8)),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.successDark : Colors.white,
                      border: Border.all(
                        color: isSelected ? AppColors.successDark : AppColors.grey300,
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon,
                            size: ResponsiveHelper.iconSize(context, 14),
                            color: isSelected ? Colors.white : AppColors.grey500),
                        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
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
              if (selected != null && context.mounted) setDialogState(() => onDayChanged(selected));
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
              if (selected != null && context.mounted) setDialogState(() => onTimeChanged(selected));
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

    // builder 내부에서 외부 context로 InheritedWidget 조회 시 _dependents 잘못 등록 방지
    final capturedTitleStyle = ResponsiveHelper.subtitleStyle(context)
        .copyWith(fontWeight: FontWeight.bold);
    final capturedConfirmStyle = ResponsiveHelper.bodyStyle(context,
            color: theme.primaryColor)
        .copyWith(fontWeight: FontWeight.bold);
    final capturedItemStyle = ResponsiveHelper.subtitleStyle(context)
        .copyWith(fontWeight: FontWeight.w500);
    final safeBottom = MediaQuery.of(context).padding.bottom;

    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        constraints: BoxConstraints(maxHeight: 340 + safeBottom),
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
                  Text('지급일 선택', style: capturedTitleStyle),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, selected),
                    child: Text('확인', style: capturedConfirmStyle),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.grey200),
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
                          child: Text(l, style: capturedItemStyle),
                        ))
                    .toList(),
              ),
            ),
            SizedBox(height: safeBottom),
          ],
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
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 6)),
              decoration: BoxDecoration(
                color: AppColors.grey100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.coffee, size: ResponsiveHelper.iconSize(context, 18), color: AppColors.grey500),
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
                    padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 10)),
                    decoration: BoxDecoration(
                      color: isSelected ? theme.primaryColor : Colors.white,
                      border: Border.all(color: isSelected ? theme.primaryColor : AppColors.grey300, width: isSelected ? 2 : 1),
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
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 6)),
              decoration: BoxDecoration(
                color: AppColors.grey100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.account_balance_outlined,
                size: ResponsiveHelper.iconSize(context, 18),
                color: AppColors.grey500,
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
                  bottom: ResponsiveHelper.spacing(context, 6)),
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 12),
                vertical: ResponsiveHelper.spacing(context, 8),
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

  /// ✨ 급여 타입 선택 버튼 — compact segmented tab
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
          vertical: ResponsiveHelper.spacing(context, 9),
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.primaryColor
              : Colors.white,
          border: Border.all(
            color: isSelected ? theme.primaryColor : AppColors.grey300,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : AppColors.grey500,
              size: ResponsiveHelper.iconSize(context, 16),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 5)),
            Text(
              label,
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                color: isSelected ? Colors.white : AppColors.grey700,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 🎨 업무 상세 편집 화면 (Full-Screen, white-base)
// showAddDialog / showEditDialog 에서 Navigator.push로 진입
// ============================================================

class _WorkDetailEditorScreen extends StatefulWidget {
  final bool isEdit;
  final List<BusinessWorkTypeModel> businessWorkTypes;
  final WorkDetailData? existingWork;
  final int currentCount;

  const _WorkDetailEditorScreen({
    required this.isEdit,
    required this.businessWorkTypes,
    this.existingWork,
    this.currentCount = 0,
  });

  @override
  State<_WorkDetailEditorScreen> createState() =>
      _WorkDetailEditorScreenState();
}

class _WorkDetailEditorScreenState extends State<_WorkDetailEditorScreen> {
  // ── State ──────────────────────────────────────────────────
  BusinessWorkTypeModel? _selectedWorkType;
  String _selectedWageType = 'hourly';
  String? _startTime;
  String? _endTime;
  String? _shiftType;
  bool _nightAllowanceApplied = true;
  bool _nightIncluded = false;
  int _breakMinutes = 0;
  String? _payScheduleType;
  int? _payScheduleDay;
  String? _payScheduleTime;
  String _taxDeductionType = InsuranceRateModel.typeNone;

  // 미저장 변경 추적
  bool _isDirty = false;

  // baseHourlyWage stale 추적 — wage 변경 후 baseHourly 재입력 없으면 stale
  bool _baseHourlyIsStale = false;

  late final TextEditingController _wageController;
  late final TextEditingController _countController;
  late final TextEditingController _baseHourlyWageController;
  late final TextEditingController _descriptionController;

  // Section GlobalKeys (scroll-to-first-error)
  final _keyWorkType    = GlobalKey();
  final _keyWage        = GlobalKey();
  final _keyTime        = GlobalKey();
  final _keyBreak       = GlobalKey();
  final _keyBaseHourly  = GlobalKey();
  final _keyNight       = GlobalKey();
  final _keyDeduction   = GlobalKey();
  final _keyPaySchedule = GlobalKey();
  final _keyCount       = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.isEdit && widget.existingWork != null) {
      final w = widget.existingWork!;
      _selectedWageType = w.wageType;
      _startTime = w.startTime;
      _endTime = w.endTime;
      _shiftType = w.shiftType;
      _nightAllowanceApplied = w.nightAllowanceApplied;
      _nightIncluded = w.nightIncluded;
      _breakMinutes = w.breakMinutes;
      _payScheduleType = w.payScheduleType;
      _payScheduleDay = w.payScheduleDay;
      _payScheduleTime = w.payScheduleTime;
      _taxDeductionType = w.taxDeductionType;
      _wageController =
          TextEditingController(text: FormatHelper.formatNumber(w.wage));
      _countController =
          TextEditingController(text: w.requiredCount.toString());
      _baseHourlyWageController = TextEditingController(
        text: w.baseHourlyWage != null
            ? FormatHelper.formatNumber(w.baseHourlyWage!)
            : '',
      );
      _descriptionController =
          TextEditingController(text: w.description ?? '');
      if (widget.businessWorkTypes.isNotEmpty) {
        _selectedWorkType = widget.businessWorkTypes.firstWhere(
          (wt) => wt.name == w.workType,
          orElse: () => widget.businessWorkTypes.first,
        );
      }
    } else {
      _wageController = TextEditingController();
      _countController = TextEditingController();
      _baseHourlyWageController = TextEditingController();
      _descriptionController = TextEditingController();
    }

    // _isDirty 리스너 — 텍스트 필드 변경 시 마킹
    for (final c in [
      _wageController,
      _countController,
      _baseHourlyWageController,
      _descriptionController,
    ]) {
      c.addListener(_markDirty);
    }

    // wage 변경 시 기존 baseHourlyWage stale 처리
    _wageController.addListener(_onWageChangedForBaseHourly);
    // baseHourlyWage 재입력 시 stale 해제
    _baseHourlyWageController.addListener(_onBaseHourlyChanged);
  }

  void _markDirty() {
    if (!_isDirty) setState(() => _isDirty = true);
  }

  /// wage 텍스트 변경 시: 기존 baseHourlyWage를 stale로 표시.
  /// 매 keystroke마다 controller를 clear하지 않고 flag만 세움 → UX 보존.
  void _onWageChangedForBaseHourly() {
    if (!_baseHourlyIsStale &&
        _baseHourlyWageController.text.isNotEmpty) {
      _baseHourlyIsStale = true; // setState 불필요 — save-time only
    }
  }

  /// baseHourlyWage 직접 편집 시: stale 해제 (사용자가 새로 입력한 값).
  void _onBaseHourlyChanged() {
    if (_baseHourlyIsStale) _baseHourlyIsStale = false;
  }

  /// baseHourlyWage 의존 필드(start/end/break/wageType) 변경 시 stale 값 제거.
  void _clearBaseHourlyIfStale() {
    if (_baseHourlyWageController.text.isNotEmpty) {
      _baseHourlyWageController.text = '';
    }
    _baseHourlyIsStale = false; // 이미 clear됐으므로 flag 초기화
  }

  @override
  void dispose() {
    _wageController.removeListener(_onWageChangedForBaseHourly);
    _baseHourlyWageController.removeListener(_onBaseHourlyChanged);
    for (final c in [
      _wageController,
      _countController,
      _baseHourlyWageController,
      _descriptionController,
    ]) {
      c.removeListener(_markDirty);
      c.dispose();
    }
    super.dispose();
  }

  // ── 닫기 (미저장 확인 포함) ─────────────────────────────────
  Future<void> _handleClose() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_isDirty) {
      Navigator.of(context).pop();
      return;
    }
    if (!mounted) return;
    final confirmed = await DialogHelper.showConfirm(
      context,
      title: '작성 중인 내용을 취소할까요?',
      message: '입력한 내용은 저장되지 않습니다.',
      confirmText: '취소',
      cancelText: '계속 작성',
      confirmColor: AppColors.errorDark,
    );
    if (!mounted) return;
    if (confirmed) Navigator.of(context).pop();
  }

  void _scrollToFirstError(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: 0.0,
    );
  }

  // ── Build ───────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = widget.isEdit
        ? '${widget.existingWork?.workType ?? ''} 수정'
        : '업무 추가';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleClose();
      },
      child: Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.textPrimary),
          onPressed: _handleClose,
        ),
        title: Text(
          title,
          style: ResponsiveHelper.subtitleStyle(context).copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.grey100),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: _buildCTA(theme),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        children: [
          // ① 업무 유형
          // [4H.0B-IDENTITY-LOCK] isEdit=true 시 workType picker 비활성 — 변경 시 workDetailId 파괴
          // businessWorkTypes.isEmpty fallback은 기존 그대로 유지
          KeyedSubtree(
            key: _keyWorkType,
            child: !widget.isEdit && widget.businessWorkTypes.isNotEmpty
                ? WorkDetailDialog._buildWorkTypeSection(
                    context,
                    theme,
                    widget.businessWorkTypes,
                    _selectedWorkType,
                    setState,
                    (wt) { _selectedWorkType = wt; _isDirty = true; },
                  )
                : WorkDetailDialog._buildEditWarningCard(context),
          ),
          const SizedBox(height: 20),

          // ② 급여 타입
          WorkDetailDialog._buildWageTypeSection(
            context,
            theme,
            _selectedWageType,
            setState,
            (type) {
              _selectedWageType = type;
              _isDirty = true;
              if (type != 'daily') {
                _shiftType = null;
                _nightIncluded = false;
              }
              // daily→hourly 전환 시 stale baseHourlyWage 제거
              _clearBaseHourlyIfStale();
            },
          ),
          const SizedBox(height: 20),

          // ③ 급여 금액
          KeyedSubtree(
            key: _keyWage,
            child: WorkDetailDialog._buildWageSection(
              context,
              theme,
              _selectedWageType,
              _wageController,
              _startTime,
              _endTime,
              _breakMinutes,
            ),
          ),
          const SizedBox(height: 20),

          // ④ 필요 인원
          KeyedSubtree(
            key: _keyCount,
            child: widget.isEdit
                ? WorkDetailDialog._buildEditCountSection(
                    context,
                    theme,
                    _countController,
                    widget.currentCount,
                  )
                : WorkDetailDialog._buildCountSection(
                    context,
                    theme,
                    _countController,
                  ),
          ),
          const SizedBox(height: 20),

          // ⑤ 근무 시간
          KeyedSubtree(
            key: _keyTime,
            child: WorkDetailDialog._buildTimeSection(
              context,
              theme,
              _startTime,
              _endTime,
              _breakMinutes,
              setState,
              (t) {
                if (t != null) {
                  _startTime = t;
                  _isDirty = true;
                  _clearBaseHourlyIfStale();
                }
              },
              (t) {
                if (t != null) {
                  _endTime = t;
                  _isDirty = true;
                  _clearBaseHourlyIfStale();
                }
              },
            ),
          ),
          const SizedBox(height: 20),

          // ⑥ 휴게시간
          KeyedSubtree(
            key: _keyBreak,
            child: WorkDetailDialog._buildBreakMinutesSection(
              context,
              theme,
              _breakMinutes,
              setState,
              (v) {
                _breakMinutes = v;
                _isDirty = true;
                _clearBaseHourlyIfStale();
              },
            ),
          ),
          const SizedBox(height: 20),

          // ⑦ 통상시급 (일급제)
          if (_selectedWageType == 'daily') ...[
            KeyedSubtree(
              key: _keyBaseHourly,
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _wageController,
                builder: (ctx, __, ___) =>
                    WorkDetailDialog._buildBaseHourlyWageSection(
                  ctx,
                  theme,
                  _wageController,
                  _baseHourlyWageController,
                  _startTime,
                  _endTime,
                  _breakMinutes,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],

          // ⑧ 야간수당
          KeyedSubtree(
            key: _keyNight,
            child: WorkDetailDialog._buildShiftAndNightSection(
              context,
              theme,
              _selectedWageType,
              _shiftType,
              _nightAllowanceApplied,
              _nightIncluded,
              setState,
              (v) { _shiftType = v; _isDirty = true; },
              (v) {
                _nightAllowanceApplied = v;
                _isDirty = true;
                if (!v) _nightIncluded = false;
              },
              (v) { _nightIncluded = v; _isDirty = true; },
            ),
          ),
          const SizedBox(height: 20),

          // ⑨ 공제 방식
          KeyedSubtree(
            key: _keyDeduction,
            child: WorkDetailDialog._buildTaxDeductionSection(
              context,
              theme,
              _taxDeductionType,
              setState,
              (v) { _taxDeductionType = v; _isDirty = true; },
            ),
          ),
          const SizedBox(height: 20),

          // ⑩ 급여 지급 일정
          KeyedSubtree(
            key: _keyPaySchedule,
            child: WorkDetailDialog._buildPayScheduleSection(
              context,
              theme,
              _payScheduleType,
              _payScheduleDay,
              _payScheduleTime,
              setState,
              (t) { _payScheduleType = t; _payScheduleDay = null; _isDirty = true; },
              (d) { _payScheduleDay = d; _isDirty = true; },
              (t) { _payScheduleTime = t; _isDirty = true; },
            ),
          ),
          // ⑪ 업무 설명 — V1 비노출 (schema/data 유지, 입력 UI hidden)
          // TODO(v2): WorkDetailData.description 사용자 노출 경로 추가 시 복원
        ],
      ),
    ),   // Scaffold
    );   // PopScope
  }

  // ── Sticky CTA ──────────────────────────────────────────────
  Widget _buildCTA(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.primaryColor,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Text(
            widget.isEdit ? '저장' : '업무 추가',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
        ),
      ),
    );
  }

  // ── Validation & Save ───────────────────────────────────────
  Future<void> _save() async {
    FocusManager.instance.primaryFocus?.unfocus();

    if (widget.isEdit) {
      // ── Edit mode ──
      final wage = int.tryParse(_wageController.text.replaceAll(',', ''));
      final count = int.tryParse(_countController.text);

      if (wage == null || wage <= 0 || count == null || count <= 0) {
        _scrollToFirstError(_keyWage);
        ToastHelper.showError('유효한 금액(0원 초과)과 인원(1명 이상)을 입력하세요');
        return;
      }

      if (widget.currentCount > 0 && count < widget.currentCount) {
        if (!mounted) return;
        final proceed = await DialogHelper.showConfirm(
          context,
          title: '모집인원 축소 경고',
          message: '현재 확정 인원(${widget.currentCount}명)보다 적게 설정합니다.\n'
              '이미 확정된 인원이 초과 상태가 됩니다. 계속하시겠습니까?',
          confirmText: '저장',
          confirmColor: AppColors.warning,
          icon: Icons.warning_amber,
          iconColor: AppColors.warning,
        );
        if (!proceed) return;
        if (!mounted) return;
      }

      if (_selectedWageType == 'daily' && _shiftType == null) {
        _scrollToFirstError(_keyNight);
        ToastHelper.showError('일급제는 근무 시간대(주간/석간/야간)를 선택해주세요');
        return;
      }

      if (_payScheduleType == null) {
        _scrollToFirstError(_keyPaySchedule);
        ToastHelper.showError('급여 지급 일정을 선택해주세요');
        return;
      }

      if ((_payScheduleType == 'weekly' || _payScheduleType == 'monthly') &&
          _payScheduleDay == null) {
        _scrollToFirstError(_keyPaySchedule);
        ToastHelper.showError(
          _payScheduleType == 'weekly' ? '지급 요일을 선택해주세요' : '지급 날짜를 선택해주세요',
        );
        return;
      }

      // 최저임금 위반 경고 (edit: confirm dialog, hourly + daily 동일 convention)
      final minWage = WageCalculator.currentMinimumWage;
      if (_selectedWageType == 'hourly' && wage < minWage) {
        if (!mounted) return;
        final proceed = await DialogHelper.showConfirm(
          context,
          title: '최저임금 미달 경고',
          message: '입력한 시급(${FormatHelper.formatNumber(wage)}원)이\n'
              '최저임금(${FormatHelper.formatNumber(minWage)}원)보다 낮습니다.\n\n'
              '최저임금법 위반 시 3년 이하 징역 또는 2천만 원 이하 벌금이 부과됩니다.\n'
              '그래도 저장하시겠습니까?',
          confirmText: '저장',
          cancelText: '수정하기',
          confirmColor: AppColors.errorDark,
          icon: Icons.warning_amber,
          iconColor: AppColors.errorDark,
        );
        if (!proceed) return;
        if (!mounted) return;
      }
      if (_selectedWageType == 'daily' &&
          _startTime != null && _endTime != null) {
        int toMin(String t) {
          final p = t.split(':');
          return int.parse(p[0]) * 60 + int.parse(p[1]);
        }
        int sMin = toMin(_startTime!), eMin = toMin(_endTime!);
        if (eMin <= sMin) eMin += 1440;
        final workMins = (eMin - sMin - _breakMinutes).clamp(0, 9999);
        if (workMins > 0) {
          final hourlyEquiv = (wage * 60 / workMins).round();
          if (hourlyEquiv < minWage) {
            if (!mounted) return;
            final proceed = await DialogHelper.showConfirm(
              context,
              title: '최저임금 미달 경고',
              message: '환산시급(${FormatHelper.formatNumber(hourlyEquiv)}원)이\n'
                  '최저임금(${FormatHelper.formatNumber(minWage)}원)보다 낮습니다.\n\n'
                  '최저임금법 위반 시 3년 이하 징역 또는 2천만 원 이하 벌금이 부과됩니다.\n'
                  '그래도 저장하시겠습니까?',
              confirmText: '저장',
              cancelText: '수정하기',
              confirmColor: AppColors.errorDark,
              icon: Icons.warning_amber,
              iconColor: AppColors.errorDark,
            );
            if (!proceed) return;
            if (!mounted) return;
          }
        }
      }

      // stale baseHourlyWage → null (새 계산 기준 불일치 방지)
      final editBaseHourly = _baseHourlyIsStale
          ? null
          : int.tryParse(_baseHourlyWageController.text.replaceAll(',', ''));

      // manual baseHourlyWage 최저임금 미달 경고 (OPTION A: confirm dialog)
      if (_selectedWageType == 'daily' &&
          editBaseHourly != null &&
          editBaseHourly < WageCalculator.currentMinimumWage) {
        if (!mounted) return;
        final proceed = await DialogHelper.showConfirm(
          context,
          title: '통상시급 최저임금 미달 경고',
          message: '수동 입력한 통상시급(${FormatHelper.formatNumber(editBaseHourly)}원)이\n'
              '최저임금(${FormatHelper.formatNumber(WageCalculator.currentMinimumWage)}원)보다 낮습니다.\n\n'
              '야간수당 계산 기준에 사용됩니다. 그래도 저장하시겠습니까?',
          confirmText: '저장',
          cancelText: '수정하기',
          confirmColor: AppColors.errorDark,
          icon: Icons.warning_amber,
          iconColor: AppColors.errorDark,
        );
        if (!proceed) return;
        if (!mounted) return;
      }

      Navigator.of(context).pop(<String, dynamic>{
        if (_selectedWorkType != null) ...{
          'workType': _selectedWorkType!.name,
          'workTypeIcon': _selectedWorkType!.icon,
          'workTypeColor': _selectedWorkType!.color,
          'workTypeBackgroundColor': _selectedWorkType!.backgroundColor,
        },
        'wage': wage,
        'wageType': _selectedWageType,
        'requiredCount': count,
        'startTime': _startTime,
        'endTime': _endTime,
        if (_shiftType != null) 'shiftType': _shiftType,
        'nightAllowanceApplied': _nightAllowanceApplied,
        'nightIncluded': _nightIncluded,
        'breakMinutes': _breakMinutes,
        'baseHourlyWage': editBaseHourly,
        'payScheduleType': _payScheduleType,
        if (_payScheduleDay != null) 'payScheduleDay': _payScheduleDay,
        if (_payScheduleTime != null) 'payScheduleTime': _payScheduleTime,
        'taxDeductionType': _taxDeductionType,
        if (_descriptionController.text.trim().isNotEmpty)
          'description': _descriptionController.text.trim(),
      });
    } else {
      // ── Add mode ──
      if (_selectedWorkType == null) {
        _scrollToFirstError(_keyWorkType);
        ToastHelper.showError('업무 유형을 선택해주세요');
        return;
      }
      if (_startTime == null || _endTime == null) {
        _scrollToFirstError(_keyTime);
        ToastHelper.showError('근무 시간을 설정해주세요');
        return;
      }
      if (_wageController.text.isEmpty) {
        _scrollToFirstError(_keyWage);
        ToastHelper.showError('급여를 입력해주세요');
        return;
      }
      if (_countController.text.isEmpty) {
        _scrollToFirstError(_keyCount);
        ToastHelper.showError('모집 인원을 입력해주세요');
        return;
      }

      final wage = int.tryParse(_wageController.text.replaceAll(',', ''));
      final count = int.tryParse(_countController.text);

      if (wage == null || wage <= 0) {
        _scrollToFirstError(_keyWage);
        ToastHelper.showError('유효한 급여를 입력해주세요');
        return;
      }

      // 최저시급 검증 (add: hard block)
      final minWage = WageCalculator.currentMinimumWage;
      if (_selectedWageType == 'hourly' && wage < minWage) {
        _scrollToFirstError(_keyWage);
        ToastHelper.showError(
          '시급이 최저시급(${FormatHelper.formatNumber(minWage)}원) 미만입니다.\n최저시급 이상으로 입력해주세요.');
        return;
      }
      if (_selectedWageType == 'daily') {
        int toMin(String t) {
          final p = t.split(':');
          return int.parse(p[0]) * 60 + int.parse(p[1]);
        }
        int sMin = toMin(_startTime!), eMin = toMin(_endTime!);
        if (eMin <= sMin) eMin += 1440;
        final workMins = (eMin - sMin - _breakMinutes).clamp(0, 9999);
        if (workMins > 0) {
          final hourlyEquiv = (wage * 60 / workMins).round();
          if (hourlyEquiv < minWage) {
            _scrollToFirstError(_keyWage);
            ToastHelper.showError(
              '환산시급(${FormatHelper.formatNumber(hourlyEquiv)}원)이 최저시급(${FormatHelper.formatNumber(minWage)}원) 미만입니다.\n일급을 올려주세요.');
            return;
          }
        }
      }

      if (count == null || count <= 0) {
        _scrollToFirstError(_keyCount);
        ToastHelper.showError('유효한 인원 수를 입력해주세요');
        return;
      }

      if (_startTime == _endTime) {
        _scrollToFirstError(_keyTime);
        ToastHelper.showError('시작 시간과 종료 시간이 같을 수 없습니다');
        return;
      }

      if (_selectedWageType == 'daily' && _shiftType == null) {
        _scrollToFirstError(_keyNight);
        ToastHelper.showError('일급제는 근무 시간대(주간/석간/야간)를 선택해주세요');
        return;
      }

      if (_payScheduleType == null) {
        _scrollToFirstError(_keyPaySchedule);
        ToastHelper.showError('급여 지급 일정을 선택해주세요');
        return;
      }

      if ((_payScheduleType == 'weekly' || _payScheduleType == 'monthly') &&
          _payScheduleDay == null) {
        _scrollToFirstError(_keyPaySchedule);
        ToastHelper.showError(
          _payScheduleType == 'weekly' ? '지급 요일을 선택해주세요' : '지급 날짜를 선택해주세요',
        );
        return;
      }

      // stale baseHourlyWage → null (wage 변경 후 재입력 없으면 auto-calc 사용)
      final addBaseHourly = _baseHourlyIsStale
          ? null
          : int.tryParse(_baseHourlyWageController.text.replaceAll(',', ''));

      // manual baseHourlyWage 최저임금 미달 경고 (OPTION A: confirm dialog)
      if (_selectedWageType == 'daily' &&
          addBaseHourly != null &&
          addBaseHourly < minWage) {
        if (!mounted) return;
        final proceed = await DialogHelper.showConfirm(
          context,
          title: '통상시급 최저임금 미달 경고',
          message: '수동 입력한 통상시급(${FormatHelper.formatNumber(addBaseHourly)}원)이\n'
              '최저임금(${FormatHelper.formatNumber(minWage)}원)보다 낮습니다.\n\n'
              '야간수당 계산 기준에 사용됩니다. 그래도 저장하시겠습니까?',
          confirmText: '저장',
          cancelText: '수정하기',
          confirmColor: AppColors.errorDark,
          icon: Icons.warning_amber,
          iconColor: AppColors.errorDark,
        );
        if (!proceed) return;
        if (!mounted) return;
      }

      Navigator.of(context).pop(
        WorkDetailInput(
          workType: _selectedWorkType!.name,
          workTypeIcon: _selectedWorkType!.icon,
          workTypeColor: _selectedWorkType!.color ?? '#FFFFFF',
          workTypeBackgroundColor: _selectedWorkType!.backgroundColor,
          wage: wage,
          requiredCount: count,
          startTime: _startTime!,
          endTime: _endTime!,
          wageType: _selectedWageType,
          shiftType: _shiftType,
          nightAllowanceApplied: _nightAllowanceApplied,
          nightIncluded: _nightIncluded,
          breakMinutes: _breakMinutes,
          baseHourlyWage: addBaseHourly,
          payScheduleType: _payScheduleType,
          payScheduleDay: _payScheduleDay,
          payScheduleTime: _payScheduleTime,
          taxDeductionType: _taxDeductionType,
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
        ),
      );
    }
  }
}
