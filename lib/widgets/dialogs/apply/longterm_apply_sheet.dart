// lib/widgets/dialogs/apply/longterm_apply_sheet.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../models/core/to_model.dart';
import '../../../models/core/work_detail_model.dart';
import '../../../models/core/application_model.dart';
import '../../../providers/user_provider.dart';
import '../../../services/firestore_service.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/dialog_helper.dart';
import '../../../theme/app_colors.dart';
import '../../work_type_icon.dart';
import 'apply_work_dialog.dart' show ApplyDialogResult;

/// 장기공고 전용 지원 바텀시트
///
/// 희망 시작일 선택 → 계약 예정 기간 확인 → 단일 지원 액션.
/// 계약 종료일 계산은 [TOModel.computeContractEndDate] 재사용.
class LongTermApplySheet extends StatefulWidget {
  final TOModel to;
  final List<WorkDetailModel> selectedWorks;
  final String businessName;
  final List<ApplicationModel> myApplications;

  const LongTermApplySheet({
    super.key,
    required this.to,
    required this.selectedWorks,
    required this.businessName,
    required this.myApplications,
  });

  static Future<ApplyDialogResult?> show({
    required BuildContext context,
    required TOModel to,
    required List<WorkDetailModel> selectedWorks,
    required String businessName,
    List<ApplicationModel>? myApplications,
  }) {
    return DialogHelper.showSheet<ApplyDialogResult>(
      context,
      isScrollControlled: true,
      builder: (context) => LongTermApplySheet(
        to: to,
        selectedWorks: selectedWorks,
        businessName: businessName,
        myApplications: myApplications ?? [],
      ),
    );
  }

  @override
  State<LongTermApplySheet> createState() => _LongTermApplySheetState();
}

class _LongTermApplySheetState extends State<LongTermApplySheet> {
  static final _dateFmt = DateFormat('M월 d일(E)', 'ko_KR');

  late final FirestoreService _firestoreService;
  String? _currentUserId;

  DateTime? _desiredStartDate;
  DateTime? _focusedDay;
  bool _isSubmitting = false;
  bool _isLoadingConflicts = true;
  Set<DateTime> _confirmedDatesInRange = {};

  // ─── 계산 프로퍼티 ─────────────────────────────────────

  /// custom 장기공고 여부 (고정 기간, 달력 없음)
  bool get _isCustom => widget.to.contractPeriodType == 'custom';

  /// 신규 정책 적용 여부 (workStartAvailableFrom/Until 존재)
  bool get _isNewPolicy => widget.to.hasWorkStartAvailableRange;

  DateTime get _calendarFirstDay {
    if (_isNewPolicy) {
      // 신규: 근무 시작 가능기간 첫날이 속한 달의 1일
      final from = widget.to.workStartAvailableFrom!;
      return DateTime(from.year, from.month, 1);
    }
    // legacy: 기존 TO.date(=rangeStart) 기준
    final d = widget.to.date;
    return DateTime(d.year, d.month, 1);
  }

  DateTime? get _calendarLastDayNullable {
    if (_isNewPolicy) return widget.to.workStartAvailableUntil;
    // legacy: null (제한 없음 — TO가 CLOSED되면 자연 차단)
    return null;
  }

  // TableCalendar에 lastDay로 전달할 non-null 값 (null이면 먼 미래로 fallback)
  DateTime get _calendarLastDay =>
      _calendarLastDayNullable ?? DateTime(DateTime.now().year + 5, 12, 31);

  DateTime get _selectableStartDate {
    final today = DateTime.now();
    // 당일 지원 불가 — 최소 KST 내일부터
    final tomorrow = FormatHelper.toKstDate(today).add(const Duration(days: 1));
    if (_isNewPolicy) {
      final from = FormatHelper.toKstDate(widget.to.workStartAvailableFrom!);
      return tomorrow.isAfter(from) ? tomorrow : from;
    }
    // legacy: rangeStart(=TO.date) 기준
    final toStart = FormatHelper.toKstDate(widget.to.date);
    return tomorrow.isAfter(toStart) ? tomorrow : toStart;
  }

  /// 선택한 시작일 기준 계약 종료일 — TOModel.computeContractEndDate 재사용
  DateTime get _effectiveEndDate {
    if (widget.to.hasPresetPeriod && _desiredStartDate != null) {
      return widget.to.computeContractEndDate(_desiredStartDate!);
    }
    // custom: 고정 종료일
    return widget.to.rangeEnd ?? widget.to.date;
  }

  /// 이미 지원한 공고인지 확인 (PENDING / CONFIRMED)
  bool get _hasActiveApplication {
    return widget.myApplications.any((app) =>
        app.toId == widget.to.id &&
        (app.status == AppStatus.pending ||
            AppStatus.confirmedStatuses.contains(app.status)));
  }

  bool _isSelectable(DateTime day) {
    final dayOnly = DateTime.utc(day.year, day.month, day.day);
    if (dayOnly.isBefore(_selectableStartDate)) return false;
    if (dayOnly.isAfter(_calendarLastDay)) return false;

    final workDays = widget.to.workDays;
    if (workDays.isNotEmpty &&
        !workDays.contains(FormatHelper.weekday(day))) {
      return false;
    }
    for (final conflictDate in _confirmedDatesInRange) {
      if (!conflictDate.isBefore(dayOnly)) return false;
    }
    return true;
  }

  // ─── 생명주기 ─────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _firestoreService = FirestoreService();
    _focusedDay = _selectableStartDate;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _currentUserId = context.read<UserProvider>().currentUser?.uid;
      _loadConflicts();
    });
  }

  Future<void> _loadConflicts() async {
    if (!mounted) return;

    // custom: 날짜 선택 없음 — 캘린더 표시 안 함. 충돌 체크 생략.
    if (_isCustom) {
      if (mounted) setState(() => _isLoadingConflicts = false);
      return;
    }

    try {
      final allConfirmed =
          await _firestoreService.getMyConfirmedApplicationsForConflictCheck();
      final workDays = widget.to.workDays;
      final wStart = widget.selectedWorks.isNotEmpty
          ? widget.selectedWorks.first.startTime
          : '';
      final wEnd = widget.selectedWorks.isNotEmpty
          ? widget.selectedWorks.first.endTime
          : '';

      final confirmed = <DateTime>{};
      // 신규 정책: workStartAvailableFrom 부터 workStartAvailableUntil 까지
      // legacy: TO.date(=rangeStart) 부터 캘린더 마지막날까지
      var cursor = _isNewPolicy
          ? widget.to.workStartAvailableFrom!
          : widget.to.date;
      final endDate = _calendarLastDay; // null 시 먼 미래(+5년)로 fallback 완료
      while (!cursor.isAfter(endDate)) {
        final dow = FormatHelper.weekday(cursor);
        if (workDays.isEmpty || workDays.contains(dow)) {
          for (final app in allConfirmed) {
            if (app.isWorkingOnDate(cursor) &&
                ApplicationModel.hasTimeOverlap(
                    wStart, wEnd, app.startTime, app.endTime)) {
              confirmed.add(FormatHelper.toKstDate(cursor));
              break;
            }
          }
        }
        cursor = cursor.add(const Duration(days: 1));
      }

      if (mounted) {
        setState(() {
          _confirmedDatesInRange = confirmed;
          _isLoadingConflicts = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingConflicts = false);
    }
  }

  // ─── 지원 액션 ────────────────────────────────────────

  Future<void> _apply() async {
    // custom: desiredStartDate 선택 없이 즉시 지원 가능
    // preset: 반드시 desiredStartDate 선택 후 지원
    if (!_isCustom && _desiredStartDate == null) return;
    if (_isSubmitting) return;
    if (_currentUserId == null) {
      ToastHelper.showError('로그인이 필요합니다');
      return;
    }

    // custom: workDate = rangeStart, desiredStartDate = null, workEndDate = rangeEnd
    // preset: workDate = TO.date (legacy anchor), desiredStartDate = 선택일, workEndDate = computeContractEndDate
    final DateTime effectiveWorkDate;
    final DateTime? effectiveDesiredStart;
    final DateTime effectiveWorkEndDate;

    if (_isCustom) {
      if (widget.to.rangeStart == null || widget.to.rangeEnd == null) {
        ToastHelper.showError('공고 기간 정보가 없습니다. 관리자에게 문의하세요.');
        return;
      }
      effectiveWorkDate = widget.to.rangeStart!;
      effectiveDesiredStart = null;
      effectiveWorkEndDate = widget.to.rangeEnd!;
    } else {
      effectiveWorkDate = widget.to.date;
      effectiveDesiredStart = _desiredStartDate;
      effectiveWorkEndDate = _effectiveEndDate;
    }

    setState(() => _isSubmitting = true);

    try {
      int appliedCount = 0;
      for (final work in widget.selectedWorks) {
        final success = await _firestoreService.applyToTOWithWorkType(
          uid: _currentUserId!,
          businessId: widget.to.businessId,
          businessName: widget.to.businessName,
          toTitle: widget.to.title,
          workDate: effectiveWorkDate,
          selectedWorkType: work.workType,
          workDetailId: work.id,
          wage: work.wage,
          wageType: work.wageType,
          workTypeIcon: work.workTypeIcon,
          workTypeColor: work.workTypeColor,
          workTypeBackgroundColor: work.workTypeBackgroundColor,
          startTime: work.startTime,
          endTime: work.endTime,
          workEndDate: effectiveWorkEndDate,
          workDays: widget.to.workDays,
          type: widget.to.type,
          toId: widget.to.id,
          slotId: null,
          desiredStartDate: effectiveDesiredStart,
        );
        if (success) appliedCount++;
      }

      if (!mounted) return;
      Navigator.pop(
        context,
        ApplyDialogResult(
            hasChanges: appliedCount > 0, appliedCount: appliedCount),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ToastHelper.showError('지원 처리 중 오류가 발생했습니다');
      }
    }
  }

  // ─── 빌드 ────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_hasActiveApplication) return _buildAlreadyApplied(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildSheetHeader(context),
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              ResponsiveHelper.spacing(context, 16),
              ResponsiveHelper.spacing(context, 4),
              ResponsiveHelper.spacing(context, 16),
              ResponsiveHelper.spacing(context, 8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isCustom) ...[
                  // ── custom: 관리자가 날짜 직접 지정 ──────────────
                  Padding(
                    padding: EdgeInsets.only(
                      top: ResponsiveHelper.spacing(context, 12),
                      bottom: ResponsiveHelper.spacing(context, 10),
                    ),
                    child: Text(
                      '근무 예정 기간',
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.grey600, fontWeight: FontWeight.w600),
                    ),
                  ),
                  _buildCustomPeriodCard(context),
                ] else ...[
                  // ── preset: 희망 시작일 선택 ─────────────────────
                  Padding(
                    padding: EdgeInsets.only(
                      top: ResponsiveHelper.spacing(context, 12),
                      bottom: ResponsiveHelper.spacing(context, 10),
                    ),
                    child: Text(
                      '희망 시작일',
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.grey600, fontWeight: FontWeight.w600),
                    ),
                  ),
                  // 날짜 미선택: 캘린더 / 날짜 선택 후: 컴팩트 칩 + 계약 기간
                  if (_desiredStartDate == null)
                    _buildCalendar(context)
                  else ...[
                    _buildSelectedDateChip(context),
                    SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                    _buildPeriodCard(context),
                  ],
                ],
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                // ── 선택 업무 ──
                _buildWorkSummary(context),
                SizedBox(height: ResponsiveHelper.spacing(context, 10)),
                // ── 안내문 ──
                _buildInfoMessage(context),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              ],
            ),
          ),
        ),
        _buildCTA(context),
      ],
    );
  }

  // ─── custom 전용: 고정 기간 카드 ─────────────────────────

  Widget _buildCustomPeriodCard(BuildContext context) {
    final rangeStart = widget.to.rangeStart;
    final rangeEnd = widget.to.rangeEnd;
    if (rangeStart == null || rangeEnd == null) {
      return Container(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
        decoration: BoxDecoration(
          color: AppColors.grey100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '기간 정보를 불러올 수 없습니다.',
          style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
        ),
      );
    }

    final startStr = _dateFmt.format(rangeStart);
    final endStr = _dateFmt.format(rangeEnd);
    final periodLabel = widget.to.contractPeriodLabel;
    final workDaysLabel = widget.to.workDaysLabel;

    return Container(
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 14),
        ResponsiveHelper.spacing(context, 12),
        ResponsiveHelper.spacing(context, 14),
        ResponsiveHelper.spacing(context, 12),
      ),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.infoLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lock_outline,
                size: ResponsiveHelper.iconSize(context, 14),
                color: AppColors.infoDark,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              Expanded(
                child: Text(
                  '관리자가 지정한 고정 기간이에요',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.infoDark, fontWeight: FontWeight.w600),
                ),
              ),
              if (periodLabel.isNotEmpty)
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 8),
                    vertical: ResponsiveHelper.spacing(context, 3),
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.infoDark,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    periodLabel,
                    style: ResponsiveHelper.tinyStyle(context,
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Text(
            '$startStr → $endStr',
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              color: AppColors.grey800,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (workDaysLabel.isNotEmpty) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
            Text(
              workDaysLabel,
              style: ResponsiveHelper.tinyStyle(context,
                  color: AppColors.grey600),
            ),
          ],
        ],
      ),
    );
  }

  // ─── 공통 바텀시트 Shell ──────────────────────────────
  // White + drag handle + title + close

  Widget _buildSheetHeader(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Drag handle
        Container(
          margin: EdgeInsets.only(
            top: ResponsiveHelper.spacing(context, 10),
            bottom: ResponsiveHelper.spacing(context, 2),
          ),
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.grey300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        // Title row
        Padding(
          padding: EdgeInsets.fromLTRB(
            ResponsiveHelper.spacing(context, 20),
            ResponsiveHelper.spacing(context, 10),
            ResponsiveHelper.spacing(context, 12),
            ResponsiveHelper.spacing(context, 10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '장기 계약 지원',
                      style: ResponsiveHelper.subtitleStyle(context)
                          .copyWith(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                    Text(
                      widget.businessName,
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.grey500),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.close,
                    color: AppColors.grey500,
                    size: ResponsiveHelper.iconSize(context, 22)),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }

  // ─── 캘린더 (날짜 미선택 상태) ──────────────────────

  Widget _buildCalendar(BuildContext context) {
    if (_isLoadingConflicts) {
      return SizedBox(
        height: ResponsiveHelper.spacing(context, 200),
        child: const Center(
          child: CircularProgressIndicator(
            color: AppColors.infoDark,
            strokeWidth: 2,
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.grey200),
      ),
      child: Column(
        children: [
          TableCalendar(
            locale: 'ko_KR',
            firstDay: _calendarFirstDay,
            lastDay: _calendarLastDay,
            focusedDay: _focusedDay ?? _selectableStartDate,
            calendarFormat: CalendarFormat.month,
            daysOfWeekHeight: ResponsiveHelper.spacing(context, 28),
            rowHeight: ResponsiveHelper.spacing(context, 42),
            selectedDayPredicate: (day) =>
                _desiredStartDate != null &&
                DateUtils.isSameDay(_desiredStartDate, day),
            enabledDayPredicate: (day) => _isSelectable(day),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _desiredStartDate = selectedDay;
                _focusedDay = focusedDay;
              });
            },
            onPageChanged: (focusedDay) {
              setState(() => _focusedDay = focusedDay);
            },
            headerStyle: HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              titleTextStyle: ResponsiveHelper.subtitleStyle(context)
                  .copyWith(fontWeight: FontWeight.bold),
              leftChevronIcon: Icon(Icons.chevron_left,
                  color: AppColors.grey600,
                  size: ResponsiveHelper.iconSize(context, 20)),
              rightChevronIcon: Icon(Icons.chevron_right,
                  color: AppColors.grey600,
                  size: ResponsiveHelper.iconSize(context, 20)),
            ),
            daysOfWeekStyle: DaysOfWeekStyle(
              weekdayStyle: ResponsiveHelper.smallStyle(context,
                  color: AppColors.grey600),
              weekendStyle: ResponsiveHelper.smallStyle(context,
                  color: AppColors.error),
            ),
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (ctx, day, _) =>
                  _buildDayCell(ctx, day, selectable: true),
              outsideBuilder: (ctx, day, _) =>
                  _buildDayCell(ctx, day, isOutside: true),
              todayBuilder: (ctx, day, _) =>
                  _buildDayCell(ctx, day,
                      isToday: true, selectable: _isSelectable(day)),
              selectedBuilder: (ctx, day, _) =>
                  _buildDayCell(ctx, day, isSelected: true),
              disabledBuilder: (ctx, day, _) => _buildDayCell(ctx, day),
            ),
          ),
          // 범례
          Padding(
            padding: EdgeInsets.fromLTRB(
              0,
              0,
              0,
              ResponsiveHelper.spacing(context, 10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendDot(context, AppColors.infoDark, '선택됨'),
                SizedBox(width: ResponsiveHelper.spacing(context, 16)),
                _buildLegendDot(context, AppColors.infoBg, '선택가능',
                    bordered: true),
                SizedBox(width: ResponsiveHelper.spacing(context, 16)),
                _buildLegendDot(context, AppColors.grey200, '선택불가'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayCell(
    BuildContext context,
    DateTime day, {
    bool selectable = false,
    bool isOutside = false,
    bool isToday = false,
    bool isSelected = false,
  }) {
    Color bgColor;
    Color textColor;
    Border? border;

    if (isSelected) {
      bgColor = AppColors.infoDark;
      textColor = Colors.white;
      border = Border.all(color: AppColors.infoDark, width: 2);
    } else if (isOutside) {
      bgColor = Colors.transparent;
      textColor = AppColors.grey300;
    } else if (selectable) {
      bgColor = AppColors.infoBg;
      textColor = AppColors.infoDark;
      // today 여부와 무관하게 동일 스타일 — border 없음
    } else {
      bgColor = Colors.transparent;
      textColor = AppColors.grey400;
      // today 여부와 무관하게 동일 스타일 — border 없음
    }

    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
        border: border,
      ),
      child: Center(
        child: Text(
          '${day.day}',
          style: ResponsiveHelper.smallStyle(context, color: textColor).copyWith(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildLegendDot(BuildContext context, Color color, String label,
      {bool bordered = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: ResponsiveHelper.spacing(context, 10),
          height: ResponsiveHelper.spacing(context, 10),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: bordered
                ? Border.all(color: AppColors.infoDark, width: 1)
                : null,
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
        Text(
          label,
          style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500),
        ),
      ],
    );
  }

  // ─── 선택한 날짜 컴팩트 칩 (날짜 선택 후) ─────────────

  Widget _buildSelectedDateChip(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 14),
        vertical: ResponsiveHelper.spacing(context, 12),
      ),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.infoLight),
      ),
      child: Row(
        children: [
          Icon(
            Icons.calendar_today_outlined,
            size: ResponsiveHelper.iconSize(context, 18),
            color: AppColors.infoDark,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '희망 시작일',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.infoDark),
                ),
                Text(
                  _dateFmt.format(_desiredStartDate!),
                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                    color: AppColors.infoDark,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _desiredStartDate = null),
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 10),
                vertical: ResponsiveHelper.spacing(context, 6),
              ),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              '변경',
              style: ResponsiveHelper.smallStyle(context,
                  color: AppColors.infoDark, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 근무 예정 기간 카드 ──────────────────────────────
  // 세로선 제거 · infoBg 배경 · 날짜 한 줄 표시

  Widget _buildPeriodCard(BuildContext context) {
    if (_desiredStartDate == null) return const SizedBox.shrink();
    final endDate = _effectiveEndDate;
    final startStr = _dateFmt.format(_desiredStartDate!);
    final endStr = _dateFmt.format(endDate);
    final periodLabel = widget.to.contractPeriodLabel;
    final workDaysLabel = widget.to.workDaysLabel;

    return Container(
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 14),
        ResponsiveHelper.spacing(context, 12),
        ResponsiveHelper.spacing(context, 14),
        ResponsiveHelper.spacing(context, 12),
      ),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.infoLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 첫 줄: 라벨 + 배지
          Row(
            children: [
              Text(
                '근무 예정 기간',
                style: ResponsiveHelper.tinyStyle(context,
                    color: AppColors.infoDark, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              if (periodLabel.isNotEmpty)
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 8),
                    vertical: ResponsiveHelper.spacing(context, 3),
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.infoDark,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    periodLabel,
                    style: ResponsiveHelper.tinyStyle(context,
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 6)),
          // 둘째 줄: 날짜 한 줄
          Text(
            '$startStr → $endStr',
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              color: AppColors.grey800,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (workDaysLabel.isNotEmpty) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
            Text(
              workDaysLabel,
              style: ResponsiveHelper.tinyStyle(context,
                  color: AppColors.grey600),
            ),
          ],
        ],
      ),
    );
  }

  // ─── 업무 summary (읽기 전용) ─────────────────────────

  Widget _buildWorkSummary(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '선택한 업무',
          style: ResponsiveHelper.smallStyle(context,
              color: AppColors.grey600, fontWeight: FontWeight.w600),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        ...widget.selectedWorks.map((work) => _buildWorkCard(context, work)),
      ],
    );
  }

  Widget _buildWorkCard(BuildContext context, WorkDetailModel work) {
    final wageColor = work.wageType == 'daily'
        ? AppColors.warningDark
        : work.wageType == 'hourly'
            ? AppColors.successDark
            : AppColors.grey600;

    return Container(
      margin:
          EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: AppColors.grey50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.grey200),
      ),
      child: Row(
        children: [
          WorkTypeIcon.buildWithBackground(
            iconString: work.workTypeIcon,
            iconColor: work.workTypeColor,
            backgroundColor: work.workTypeBackgroundColor,
            size: ResponsiveHelper.spacing(context, 16),
            containerSize: ResponsiveHelper.spacing(context, 32),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  work.workType,
                  style: ResponsiveHelper.bodyStyle(context)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                Text(
                  work.timeRange,
                  style: ResponsiveHelper.smallStyle(context,
                      color: AppColors.grey600),
                ),
              ],
            ),
          ),
          Text(
            '${work.wageType == 'hourly' ? '시급' : work.wageType == 'daily' ? '일급' : '월급'} ${FormatHelper.formatNumber(work.wage)}원',
            style: ResponsiveHelper.bodyStyle(context, color: wageColor)
                .copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  // ─── 안내 메시지 ──────────────────────────────────────

  Widget _buildInfoMessage(BuildContext context) {
    final message = _isCustom
        ? '관리자가 지정한 기간으로 계약이 진행돼요.\n'
            '근무 시작 후 계약 종료는 퇴사 요청을 이용해주세요.'
        : '선택한 시작일을 기준으로 계약 기간이 자동 계산돼요.\n'
            '근무 시작 후 계약 종료는 퇴사 요청을 이용해주세요.';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline,
            size: ResponsiveHelper.iconSize(context, 14),
            color: AppColors.grey400),
        SizedBox(width: ResponsiveHelper.spacing(context, 6)),
        Expanded(
          child: Text(
            message,
            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
          ),
        ),
      ],
    );
  }

  // ─── CTA 영역 ─────────────────────────────────────────

  Widget _buildCTA(BuildContext context) {
    // custom: 날짜 선택 없이 즉시 지원 가능
    // preset: 희망 시작일 선택 후 지원 가능
    final bool canApply;
    final String ctaLabel;
    if (_isCustom) {
      canApply = !_isSubmitting;
      ctaLabel = '이 조건으로 지원하기';
    } else {
      canApply =
          _desiredStartDate != null && !_isSubmitting && !_isLoadingConflicts;
      ctaLabel = _desiredStartDate != null
          ? '이 조건으로 지원하기'
          : '희망 시작일을 선택해주세요';
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          ResponsiveHelper.spacing(context, 16),
          ResponsiveHelper.spacing(context, 8),
          ResponsiveHelper.spacing(context, 16),
          ResponsiveHelper.spacing(context, 16),
        ),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: canApply ? _apply : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.infoDark,
              disabledBackgroundColor: AppColors.grey200,
              padding: EdgeInsets.symmetric(
                  vertical: ResponsiveHelper.spacing(context, 16)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : Text(
                    ctaLabel,
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      color: canApply ? Colors.white : AppColors.grey400,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  // ─── 이미 지원됨 상태 ─────────────────────────────────

  Widget _buildAlreadyApplied(BuildContext context) {
    final existing = widget.myApplications
        .where((app) =>
            app.toId == widget.to.id &&
            (app.status == AppStatus.pending ||
                AppStatus.confirmedStatuses.contains(app.status)))
        .toList();
    final isConfirmed = existing.isNotEmpty &&
        AppStatus.confirmedStatuses.contains(existing.first.status);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildSheetHeader(context),
        Padding(
          padding: EdgeInsets.fromLTRB(
            ResponsiveHelper.spacing(context, 24),
            ResponsiveHelper.spacing(context, 28),
            ResponsiveHelper.spacing(context, 24),
            ResponsiveHelper.spacing(context, 12),
          ),
          child: Column(
            children: [
              Icon(
                isConfirmed
                    ? Icons.check_circle
                    : Icons.assignment_turned_in_outlined,
                size: ResponsiveHelper.iconSize(context, 52),
                color: isConfirmed ? AppColors.success : AppColors.warning,
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),
              Text(
                isConfirmed ? '이미 확정된 공고입니다' : '이미 지원한 공고입니다',
                style: ResponsiveHelper.subtitleStyle(context)
                    .copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 6)),
              Text(
                isConfirmed
                    ? '내 스케줄에서 확정 근무를 확인하세요'
                    : '지원을 취소하거나 상태를 확인하려면 내 스케줄을 이용하세요',
                style: ResponsiveHelper.bodyStyle(context,
                    color: AppColors.grey500),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 28)),
              SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                          vertical: ResponsiveHelper.spacing(context, 14)),
                      side: BorderSide(color: AppColors.grey300),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      '확인',
                      style: ResponsiveHelper.bodyStyle(context,
                          color: AppColors.grey600,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
