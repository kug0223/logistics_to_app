import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Models
import '../../../models/core/work_detail_model.dart';
import '../../../models/core/application_model.dart';
import '../../../models/ui/admin_to_list_ui_models.dart';

// Services
import '../../../services/firestore_service.dart';

// Controllers
import '../../../controllers/workforce_controller.dart';

// Providers
import '../../../providers/user_provider.dart';

// Utils
import '../../../utils/toast_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/navigation_helper.dart';

// Widgets
import '../../../widgets/common/loading_widget.dart';
import '../../../theme/app_colors.dart';

// Screens
import '../../common/job_posting_screen.dart';
import '../to_management/edit_to_screen.dart';

// Dialogs
import '../dialogs/to_list_dialogs.dart';
import '../dialogs/attendance_status_dialog.dart';
import '../dialogs/fixed_worker_management_dialog.dart';
import '../dialogs/close_management_dialog.dart';
import '../dialogs/confirmed_list_dialog.dart';
import '../dialogs/work_detail_management_dialog.dart';

// Local Widgets
import '../../../widgets/admin/cards/admin_work_detail.dart';

/// 인력 관리 - 캘린더 뷰
class WorkforceCalendarView extends StatefulWidget {
  const WorkforceCalendarView({super.key});

  @override
  State<WorkforceCalendarView> createState() => _WorkforceCalendarViewState();
}

class _WorkforceCalendarViewState extends State<WorkforceCalendarView> {
  final FirestoreService _firestoreService = FirestoreService();
  late TOListDialogs _dialogs;

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  // 캘린더 슬롯 카드 펼침 상태
  final Map<String, bool> _expandedSlots = {};
  final Set<String> _loadingSlots = {};

  String _slotKey(TOGroupItem g, TOItem t) => '${g.id}_${t.slot?.id ?? t.to.id}';

  // 인원현황 관련
  bool _hasConfirmedWorkers = false;
  bool _isCheckingWorkers = false;

  // 컨트롤러 로딩 완료 후 그룹 상세 로드 트리거 여부
  bool _groupDetailsTriggered = false;

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
    _focusedDay = DateTime.now();
    _dialogs = TOListDialogs(
      context: context,
      firestoreService: _firestoreService,
      onChanged: _reload,
    );
  }

  void _reload() {
    setState(() => _expandedSlots.clear());
    context.read<WorkforceController>().reload(context).then((_) {
      if (_selectedDay != null && mounted) {
        _loadGroupDetailsForDay(_selectedDay!);
        _checkConfirmedWorkers(_selectedDay!);
      }
    });
  }

  /// 특정 날짜의 TO 그룹 목록
  List<TOGroupItem> _getGroupItemsForDay(DateTime day) {
    final allItems = context.read<WorkforceController>().items;
    return allItems.where((groupItem) {
      if (groupItem.isLongTerm) {
        final isInRange = !day.isBefore(groupItem.startDate) &&
            !day.isAfter(groupItem.endDate);
        if (!isInRange) return false;
        final workDays = groupItem.masterTO.workDays;
        if (workDays.isNotEmpty) {
          const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
          return workDays.contains(weekdays[day.weekday - 1]);
        }
        return true;
      } else {
        if (groupItem.hasSlotDates) {
          return groupItem.slotDates.any((d) => DateUtils.isSameDay(d, day));
        }
        return DateUtils.isSameDay(groupItem.startDate, day);
      }
    }).toList();
  }

  /// 캘린더 이벤트 마커
  List<dynamic> _getEventsForDay(DateTime day) {
    final events = <String>[];
    final dayGroupItems = _getGroupItemsForDay(day);
    if (dayGroupItems.any((item) => item.isLongTerm)) events.add('long');
    if (dayGroupItems.any((item) => !item.isLongTerm)) events.add('single');
    return events;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<WorkforceController>();

    if (controller.isLoading) {
      _groupDetailsTriggered = false; // 다음 로딩 완료 시 재트리거
      return const LoadingWidget(message: '공고 목록을 불러오는 중...');
    }

    // 컨트롤러 로딩 완료 직후 한 번만 그룹 상세 로드
    // (initState postFrameCallback 시점에 아직 로딩 중이었던 경우 대비)
    if (!_groupDetailsTriggered && _selectedDay != null) {
      _groupDetailsTriggered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedDay != null) {
          _loadGroupDetailsForDay(_selectedDay!);
          _checkConfirmedWorkers(_selectedDay!);
        }
      });
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildCalendar()),
        SliverToBoxAdapter(child: _buildLegendSection()),
        if (_selectedDay != null) ...[
          const SliverToBoxAdapter(child: Divider(height: 1)),
          SliverToBoxAdapter(child: _buildDateHeader()),
        ],
        const SliverToBoxAdapter(child: Divider(height: 1)),
        _buildSliverDayTOList(),
      ],
    );
  }

  Widget _buildLegendSection() {
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.symmetric(
        vertical: ResponsiveHelper.spacing(context, 12),
        horizontal: ResponsiveHelper.spacing(context, 16),
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.primaryColor.withValues(alpha: 0.05),
            theme.primaryColor.withValues(alpha: 0.02),
          ],
        ),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: ResponsiveHelper.spacing(context, 20),
        runSpacing: ResponsiveHelper.spacing(context, 8),
        children: [
          _buildLegendItem(theme.primaryColor, '단기 진행중'),
          _buildLegendItem(AppColors.longTerm, '장기 진행중'),
          _buildLegendItem(AppColors.grey400, '과거/마감'),
        ],
      ),
    );
  }

  Widget _buildCalendar() {
    final theme = Theme.of(context);

    return Container(
      margin: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 12),
        ResponsiveHelper.spacing(context, 12),
        ResponsiveHelper.spacing(context, 12),
        0,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: TableCalendar(
          locale: 'ko_KR',
          firstDay: DateTime.utc(2024, 1, 1),
          lastDay: DateTime.utc(2050, 12, 31),
          focusedDay: _focusedDay,
          calendarFormat: CalendarFormat.month,
          daysOfWeekHeight: 32,
          rowHeight: 44,
          selectedDayPredicate: (day) => DateUtils.isSameDay(_selectedDay, day),
          onDaySelected: (selectedDay, focusedDay) {
            setState(() {
              _selectedDay = selectedDay;
              _focusedDay = focusedDay;
              _expandedSlots.clear();
            });
            _loadGroupDetailsForDay(selectedDay);
            _checkConfirmedWorkers(selectedDay);
          },
          onPageChanged: (focusedDay) {
            setState(() => _focusedDay = focusedDay);
          },
          eventLoader: _getEventsForDay,
          calendarBuilders: CalendarBuilders(
            defaultBuilder: (context, day, focusedDay) {
              final today = DateTime(
                  DateTime.now().year, DateTime.now().month, DateTime.now().day);
              if (!day.isBefore(today)) return null;
              final isWeekend = day.weekday == DateTime.saturday ||
                  day.weekday == DateTime.sunday;
              return Center(
                child: Text(
                  '${day.day}',
                  style: TextStyle(
                    color:
                        isWeekend ? Colors.red.shade200 : AppColors.grey400,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              );
            },
            markerBuilder: (context, date, events) {
              if (events.isEmpty) return null;

              final hasLong = events.contains('long');
              final hasSingle = events.contains('single');

              final dayGroupItems = _getGroupItemsForDay(date);
              final isPastOrClosed = date.isBefore(
                      DateTime.now().subtract(const Duration(days: 1))) ||
                  dayGroupItems.every((item) => item.isManualClosed);

              final Color shortColor =
                  isPastOrClosed ? AppColors.grey400 : theme.primaryColor;
              final Color longColor =
                  isPastOrClosed ? AppColors.grey400 : AppColors.longTerm;

              return Positioned(
                bottom: 4,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasSingle)
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                            shape: BoxShape.circle, color: shortColor),
                      ),
                    if (hasLong)
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                            shape: BoxShape.circle, color: longColor),
                      ),
                  ],
                ),
              );
            },
          ),
          daysOfWeekStyle: DaysOfWeekStyle(
            weekdayStyle: ResponsiveHelper.smallStyle(context).copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.grey600,
            ),
            weekendStyle: ResponsiveHelper.smallStyle(context).copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.grey500,
            ),
          ),
          calendarStyle: CalendarStyle(
            outsideDaysVisible: false,
            markersMaxCount: 2,
            weekendTextStyle: TextStyle(
              color: Colors.red.shade400,
              fontWeight: FontWeight.w500,
            ),
            todayDecoration: BoxDecoration(
              color: theme.primaryColor.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            todayTextStyle: TextStyle(
              color: theme.primaryColor,
              fontWeight: FontWeight.bold,
            ),
            selectedDecoration: BoxDecoration(
              color: theme.primaryColor,
              shape: BoxShape.circle,
            ),
            selectedTextStyle: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          headerStyle: HeaderStyle(
            formatButtonVisible: false,
            titleCentered: true,
            titleTextStyle: ResponsiveHelper.subtitleStyle(context).copyWith(
              fontWeight: FontWeight.bold,
            ),
            headerPadding: EdgeInsets.symmetric(
              vertical: ResponsiveHelper.spacing(context, 12),
              horizontal: ResponsiveHelper.spacing(context, 8),
            ),
            leftChevronIcon: Icon(Icons.chevron_left,
                color: theme.primaryColor, size: 24),
            rightChevronIcon: Icon(Icons.chevron_right,
                color: theme.primaryColor, size: 24),
          ),
        ),
      ),
    );
  }

  Widget _buildDateHeader() {
    final theme = Theme.of(context);

    final month = _selectedDay!.month;
    final day = _selectedDay!.day;
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final weekday = weekdays[_selectedDay!.weekday - 1];
    final dateStr = '$month월 $day일($weekday)';

    return Container(
      padding: EdgeInsets.symmetric(
        vertical: ResponsiveHelper.spacing(context, 12),
        horizontal: ResponsiveHelper.spacing(context, 16),
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.primaryColor.withValues(alpha: 0.12),
            theme.primaryColor.withValues(alpha: 0.06),
          ],
        ),
        border: Border(
          bottom: BorderSide(
            color: theme.primaryColor.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.event,
                  color: theme.primaryColor,
                  size: ResponsiveHelper.iconSize(context, 16)),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              Text(
                dateStr,
                style: ResponsiveHelper.smallStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.primaryColor,
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 10)),
          Row(
            children: [
              Expanded(
                child: _isCheckingWorkers
                    ? _buildActionButton(
                        icon: Icons.how_to_reg,
                        label: '확인중...',
                        isEnabled: false,
                        backgroundColor: AppColors.grey100,
                        foregroundColor: AppColors.grey400,
                        borderColor: AppColors.grey200,
                        onTap: null,
                      )
                    : _buildActionButton(
                        icon: Icons.how_to_reg,
                        label: '당일명단',
                        isEnabled: _hasConfirmedWorkers,
                        backgroundColor: _hasConfirmedWorkers
                            ? theme.primaryColor.withValues(alpha: 0.1)
                            : AppColors.grey100,
                        foregroundColor: _hasConfirmedWorkers
                            ? theme.primaryColor
                            : AppColors.grey400,
                        borderColor: _hasConfirmedWorkers
                            ? theme.primaryColor.withValues(alpha: 0.35)
                            : AppColors.grey200,
                        onTap: _hasConfirmedWorkers ? _showAttendancePopup : null,
                      ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.settings,
                  label: '고정관리',
                  isEnabled: true,
                  backgroundColor: AppColors.longTermLight,
                  foregroundColor: AppColors.longTermDark,
                  borderColor: AppColors.longTerm.withValues(alpha: 0.3),
                  onTap: _openFixedWorkerManagement,
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.lock_outline,
                  label: '마감관리',
                  isEnabled: true,
                  backgroundColor: AppColors.warningBg,
                  foregroundColor: AppColors.warningDark,
                  borderColor: AppColors.warning.withValues(alpha: 0.35),
                  onTap: _openCloseManagement,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required bool isEnabled,
    Color? backgroundColor,
    required Color? foregroundColor,
    Color? borderColor,
    VoidCallback? onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: borderColor != null ? Border.all(color: borderColor) : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 8),
              vertical: ResponsiveHelper.spacing(context, 10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: ResponsiveHelper.iconSize(context, 16),
                    color: foregroundColor),
                SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                Flexible(
                  child: Text(
                    label,
                    style: ResponsiveHelper.smallStyle(context).copyWith(
                      color: foregroundColor,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openFixedWorkerManagement() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final uid = userProvider.currentUser?.uid;

    if (uid == null) {
      ToastHelper.showWarning('로그인 정보를 찾을 수 없습니다');
      return;
    }

    try {
      final businesses = await _firestoreService.getMyBusiness(uid);
      if (businesses.isEmpty) {
        ToastHelper.showWarning('등록된 사업장이 없습니다');
        return;
      }
      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => FixedWorkerManagementDialog(
          businessIds: businesses.map((b) => b.id).toList(),
          focusDate: _selectedDay,
          onChanged: _reload,
        ),
      );
    } catch (e) {
      debugPrint('❌ 사업장 조회 실패: $e');
      ToastHelper.showError('사업장 정보를 불러올 수 없습니다');
    }
  }

  void _openCloseManagement() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final uid = userProvider.currentUser?.uid;

    if (uid == null) {
      ToastHelper.showWarning('로그인 정보를 찾을 수 없습니다');
      return;
    }

    final businesses = await _firestoreService.getMyBusiness(uid);
    if (businesses.isEmpty) {
      ToastHelper.showWarning('등록된 사업장이 없습니다');
      return;
    }

    if (!mounted) return;

    final hasChanges = await showDialog<bool>(
      context: context,
      builder: (context) => CloseManagementDialog(
        initialMonth: _focusedDay,
        businessIds: businesses.map((b) => b.id).toList(),
      ),
    );

    if (hasChanges == true && mounted) {
      setState(() {});
    }
  }

  Widget _buildSliverDayTOList() {
    if (_selectedDay == null) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Text(
            '날짜를 선택해주세요',
            style: ResponsiveHelper.subtitleStyle(context, color: AppColors.grey600),
          ),
        ),
      );
    }

    final dayGroupItems = _getGroupItemsForDay(_selectedDay!);
    final controller = context.read<WorkforceController>();

    if (dayGroupItems.isEmpty) {
      return _buildEmptyDaySliver();
    }

    final List<Widget> cards = [];
    for (final groupItem in dayGroupItems) {
      if (groupItem.isLongTerm) {
        cards.add(_buildContractDayCard(groupItem));
      } else {
        final isLoadingGroup = controller.isGroupLoading(groupItem.id);
        if (isLoadingGroup || !groupItem.isGroupDetailLoaded) {
          cards.add(_buildFlexSlotLoadingCard(groupItem));
        } else {
          final matchingSlots = groupItem.groupTOs
              .where((t) => DateUtils.isSameDay(t.slot?.date, _selectedDay))
              .toList();
          for (final slot in matchingSlots) {
            cards.add(_buildFlexSlotDayCard(groupItem, slot));
          }
        }
      }
    }

    if (cards.isEmpty) return _buildEmptyDaySliver();

    return SliverPadding(
      padding: ResponsiveHelper.cardPadding(context),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          for (final card in cards)
            Padding(
              padding: EdgeInsets.only(
                  bottom: ResponsiveHelper.spacing(context, 16)),
              child: card,
            ),
        ]),
      ),
    );
  }

  Widget _buildEmptyDaySliver() {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy,
                size: ResponsiveHelper.iconSize(context, 80),
                color: AppColors.grey300),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Text(
              '이 날짜에 등록된 TO가 없습니다',
              style: ResponsiveHelper.subtitleStyle(context,
                  color: AppColors.grey600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlexSlotLoadingCard(TOGroupItem groupItem) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.grey200),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: theme.primaryColor),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 10)),
          Expanded(
            child: Text(
              groupItem.title,
              style: ResponsiveHelper.bodyStyle(context)
                  .copyWith(color: AppColors.grey600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlexSlotDayCard(TOGroupItem groupItem, TOItem slot) {
    final theme = Theme.of(context);
    final key = _slotKey(groupItem, slot);
    final isExpanded = _expandedSlots[key] == true;
    final isLoading = _loadingSlots.contains(key);

    int confirmed = slot.confirmedCount;
    int pending = slot.pendingCount;
    int required = slot.totalRequired;
    if (slot.isWorkDetailLoaded && slot.workDetails.isNotEmpty) {
      confirmed = 0;
      pending = 0;
      required = 0;
      for (final work in slot.workDetails) {
        final stats = slot.workDetailStats?[work.id];
        confirmed += stats?['confirmed'] ?? 0;
        pending += stats?['pending'] ?? 0;
        required += work.requiredCount;
      }
    }
    final isFull = required > 0 && confirmed >= required;
    final isManualClosed = slot.slot?.isManualClosed == true;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isExpanded ? theme.primaryColor : AppColors.grey200,
          width: isExpanded ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          children: [
            InkWell(
              onTap: () => _handleSlotToggle(groupItem, slot, key),
              borderRadius: BorderRadius.vertical(
                top: const Radius.circular(16),
                bottom: Radius.circular(isExpanded ? 0 : 16),
              ),
              child: Padding(
                padding:
                    EdgeInsets.all(ResponsiveHelper.spacing(context, 14)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: ResponsiveHelper.spacing(context, 8),
                            vertical: ResponsiveHelper.spacing(context, 3),
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.shortTermBg,
                            borderRadius: BorderRadius.circular(6),
                            border:
                                Border.all(color: AppColors.shortTermLight),
                          ),
                          child: Text(
                            '단기',
                            style: ResponsiveHelper.tinyStyle(context,
                                    color: AppColors.shortTermDark)
                                .copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                        Expanded(
                          child: Text(
                            slot.slot?.title ?? groupItem.title,
                            style: ResponsiveHelper.bodyStyle(context)
                                .copyWith(fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 3)),
                    Text(groupItem.businessName,
                        style: ResponsiveHelper.tinyStyle(context,
                            color: AppColors.grey500)),
                    SizedBox(height: ResponsiveHelper.spacing(context, 10)),
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: ResponsiveHelper.spacing(context, 8),
                            vertical: ResponsiveHelper.spacing(context, 4),
                          ),
                          decoration: BoxDecoration(
                            color: theme.primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            FormatHelper.formatDate(
                                slot.slot?.date ?? _selectedDay!),
                            style: ResponsiveHelper.smallStyle(context,
                                    color: theme.primaryColor)
                                .copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        SizedBox(
                            width: ResponsiveHelper.spacing(context, 10)),
                        Text(
                          '확정 $confirmed/$required',
                          style: ResponsiveHelper.smallStyle(context)
                              .copyWith(color: AppColors.grey700),
                        ),
                        if (pending > 0) ...[
                          SizedBox(
                              width: ResponsiveHelper.spacing(context, 6)),
                          Text('+$pending 대기',
                              style: ResponsiveHelper.tinyStyle(context,
                                  color: AppColors.warning)),
                        ],
                        const Spacer(),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: ResponsiveHelper.spacing(context, 8),
                            vertical: ResponsiveHelper.spacing(context, 3),
                          ),
                          decoration: BoxDecoration(
                            color: (isManualClosed || isFull)
                                ? AppColors.grey100
                                : AppColors.shortTermBg,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            isManualClosed
                                ? '마감'
                                : (isFull ? '인원충족' : '모집중'),
                            style: ResponsiveHelper.tinyStyle(
                              context,
                              color: (isManualClosed || isFull)
                                  ? AppColors.grey500
                                  : AppColors.shortTermDark,
                            ).copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        _buildSlotPopupMenu(groupItem, slot),
                        Icon(
                          isExpanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          size: ResponsiveHelper.iconSize(context, 20),
                          color: AppColors.grey500,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              clipBehavior: Clip.hardEdge,
              alignment: Alignment.topCenter,
              child: isExpanded
                  ? Column(
                      children: [
                        Divider(height: 1, color: AppColors.grey200),
                        Container(
                          padding: EdgeInsets.all(
                              ResponsiveHelper.spacing(context, 12)),
                          decoration: const BoxDecoration(
                            color: AppColors.grey50,
                            borderRadius: BorderRadius.vertical(
                                bottom: Radius.circular(16)),
                          ),
                          child: isLoading
                              ? Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(
                                        ResponsiveHelper.spacing(context, 16)),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: theme.primaryColor),
                                        ),
                                        SizedBox(
                                            width: ResponsiveHelper.spacing(
                                                context, 8)),
                                        Text('업무 정보 불러오는 중...',
                                            style: ResponsiveHelper.smallStyle(
                                                context,
                                                color: AppColors.grey500)),
                                      ],
                                    ),
                                  ),
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.assignment,
                                            size: ResponsiveHelper.iconSize(
                                                context, 14),
                                            color: theme.primaryColor),
                                        SizedBox(
                                            width: ResponsiveHelper.spacing(
                                                context, 6)),
                                        Text('업무 상세',
                                            style: ResponsiveHelper.bodyStyle(
                                                    context)
                                                .copyWith(
                                                    fontWeight:
                                                        FontWeight.bold)),
                                      ],
                                    ),
                                    SizedBox(
                                        height: ResponsiveHelper.spacing(
                                            context, 10)),
                                    if (slot.workDetails.isEmpty)
                                      Padding(
                                        padding: EdgeInsets.symmetric(
                                            vertical: ResponsiveHelper.spacing(
                                                context, 8)),
                                        child: Text(
                                          '등록된 업무 상세가 없습니다.',
                                          style: ResponsiveHelper.smallStyle(
                                              context,
                                              color: AppColors.grey500),
                                        ),
                                      )
                                    else
                                      ...slot.workDetails.map((work) {
                                        final stats =
                                            slot.workDetailStats?[work.id];
                                        return WorkDetailRow(
                                          work: work,
                                          confirmedCount:
                                              stats?['confirmed'] ?? 0,
                                          pendingCount:
                                              stats?['pending'] ?? 0,
                                          toItem: slot,
                                          firestoreService: _firestoreService,
                                          onChanged: _reload,
                                        );
                                      }),
                                  ],
                                ),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleSlotToggle(
      TOGroupItem groupItem, TOItem slot, String key) async {
    if (_expandedSlots[key] == true) {
      setState(() => _expandedSlots[key] = false);
      return;
    }
    setState(() {
      _expandedSlots.clear();
      _expandedSlots[key] = true;
    });
    if (slot.needsWorkDetailLoad) {
      setState(() => _loadingSlots.add(key));
      try {
        final result = await _firestoreService.loadTOWorkDetails(
          slot.to,
          slotId: slot.slot?.id,
          slotWorkDetails: slot.slot?.workDetails,
        );
        slot.setWorkDetails(
          result['workDetails'] as List<WorkDetailModel>,
          result['workStats'] as Map<String, Map<String, int>>,
        );
      } catch (e) {
        debugPrint('❌ 슬롯 업무 상세 로드 실패: $e');
      }
      if (mounted) setState(() => _loadingSlots.remove(key));
    }
  }

  Widget _buildSlotPopupMenu(TOGroupItem groupItem, TOItem slot) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert,
          size: ResponsiveHelper.iconSize(context, 18), color: AppColors.grey600),
      padding: EdgeInsets.zero,
      tooltip: '메뉴',
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (value) => _handleSlotMenuAction(value, groupItem, slot),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'preview',
          child: Row(children: [
            Icon(Icons.visibility, size: 18, color: AppColors.info),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            const Text('공고 상세보기'),
          ]),
        ),
        PopupMenuItem(
          value: 'edit',
          child: Row(children: [
            Icon(Icons.edit, size: 18, color: AppColors.warning),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            const Text('수정'),
          ]),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(children: [
            Icon(Icons.delete, size: 18, color: AppColors.error),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            const Text('삭제'),
          ]),
        ),
        PopupMenuItem(
          value: 'confirmedList',
          child: Row(children: [
            Icon(Icons.check_circle_outline, size: 18, color: AppColors.success),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            const Text('확정명단'),
          ]),
        ),
        PopupMenuItem(
          value: 'manageWorkDetails',
          child: Row(children: [
            Icon(Icons.assignment_turned_in, size: 18, color: AppColors.purple),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            const Text('업무별 마감'),
          ]),
        ),
      ],
    );
  }

  Future<void> _handleSlotMenuAction(
      String value, TOGroupItem groupItem, TOItem slot) async {
    Future<void> ensureWorkDetailsLoaded() async {
      if (slot.isWorkDetailLoaded && slot.workDetails.isNotEmpty) return;
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      try {
        final result = await _firestoreService.loadTOWorkDetails(
          slot.to,
          slotId: slot.slot?.id,
          slotWorkDetails: slot.slot?.workDetails,
        );
        slot.setWorkDetails(
          result['workDetails'] as List<WorkDetailModel>,
          result['workStats'] as Map<String, Map<String, int>>,
        );
      } catch (e) {
        if (mounted) Navigator.pop(context);
        ToastHelper.showError('데이터를 불러오는데 실패했습니다.');
        rethrow;
      }
      if (mounted) Navigator.pop(context);
    }

    switch (value) {
      case 'preview':
        try {
          await ensureWorkDetailsLoaded();
        } catch (_) {
          return;
        }
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => JobPostingScreen(
              to: slot.to,
              workDetails: slot.workDetails,
              mode: TODetailMode.adminPreview,
            ),
          ),
        );
        break;

      case 'edit':
        await NavigationHelper.push<bool>(
          context,
          destination: AdminEditTOScreen(to: slot.to, slot: slot.slot),
          onReturn: (result) {
            if (result == true) {
              _firestoreService.clearCache(toId: slot.to.id);
              _reload();
            }
          },
        );
        break;

      case 'delete':
        _dialogs.showDeleteTODialog(slot);
        break;

      case 'confirmedList':
        try {
          await ensureWorkDetailsLoaded();
        } catch (_) {
          return;
        }
        if (!mounted) return;
        ConfirmedListDialog(
          context: context,
          toItem: slot,
          firestoreService: _firestoreService,
          slotId: slot.slot?.id,
          onLocalStatsChanged: () {
            if (mounted) _reload();
          },
        ).show();
        break;

      case 'manageWorkDetails':
        try {
          await ensureWorkDetailsLoaded();
        } catch (_) {
          return;
        }
        if (!mounted) return;
        WorkDetailManagementDialog(
          context: context,
          toItem: slot,
          firestoreService: _firestoreService,
          onComplete: _reload,
          onLocalStatsChanged: () {
            if (mounted) _reload();
          },
        ).show();
        break;
    }
  }

  Widget _buildContractDayCard(TOGroupItem groupItem) {
    final to = groupItem.masterTO;
    final start = to.rangeStart;
    final end = to.rangeEnd;
    final periodStr = (start != null && end != null)
        ? '${start.month}/${start.day} ~ ${end.month}/${end.day}'
        : '-';
    final workDays = to.workDays;
    final workDaysStr = workDays.isEmpty ? '매일' : workDays.join(' · ');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.teal.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: AppColors.teal.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 16),
              vertical: ResponsiveHelper.spacing(context, 12),
            ),
            decoration: BoxDecoration(
              color: AppColors.teal,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 6)),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.repeat,
                      color: Colors.white,
                      size: ResponsiveHelper.iconSize(context, 16)),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 10)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        groupItem.title,
                        style: ResponsiveHelper.bodyStyle(context).copyWith(
                            color: Colors.white, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        groupItem.businessName,
                        style: ResponsiveHelper.tinyStyle(context)
                            .copyWith(color: Colors.white.withValues(alpha: 0.8)),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 8),
                    vertical: ResponsiveHelper.spacing(context, 3),
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '계약직',
                    style: ResponsiveHelper.tinyStyle(context).copyWith(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 14)),
            child: Column(
              children: [
                Row(
                  children: [
                    _buildContractInfoChip(
                        icon: Icons.date_range_outlined,
                        label: periodStr,
                        color: AppColors.tealDark),
                    SizedBox(width: ResponsiveHelper.spacing(context, 10)),
                    _buildContractInfoChip(
                        icon: Icons.calendar_today_outlined,
                        label: workDaysStr,
                        color: AppColors.tealDark),
                  ],
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        _openFixedWorkerManagementForTO(groupItem),
                    icon: Icon(Icons.manage_accounts_outlined,
                        size: ResponsiveHelper.iconSize(context, 16),
                        color: AppColors.teal),
                    label: Text(
                      '이날 근무 현황 보기',
                      style: ResponsiveHelper.smallStyle(context).copyWith(
                          color: AppColors.teal, fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                          color: AppColors.teal.withValues(alpha: 0.5)),
                      padding: EdgeInsets.symmetric(
                          vertical: ResponsiveHelper.spacing(context, 10)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContractInfoChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 10),
        vertical: ResponsiveHelper.spacing(context, 6),
      ),
      decoration: BoxDecoration(
        color: AppColors.tealBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.teal.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Text(
            label,
            style: ResponsiveHelper.tinyStyle(context, color: color)
                .copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  void _openFixedWorkerManagementForTO(TOGroupItem groupItem) {
    showDialog(
      context: context,
      builder: (context) => FixedWorkerManagementDialog(
        businessIds: [groupItem.businessId],
        focusDate: _selectedDay,
        onChanged: _reload,
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 10),
        vertical: ResponsiveHelper.spacing(context, 6),
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          Text(
            label,
            style: ResponsiveHelper.tinyStyle(context,
                color: AppColors.grey800, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Future<void> _loadGroupDetailsForDay(DateTime day) async {
    final controller = context.read<WorkforceController>();
    final dayGroupItems = _getGroupItemsForDay(day);

    for (final groupItem in dayGroupItems) {
      if (!groupItem.isLongTerm && !groupItem.isGroupDetailLoaded) {
        await controller.loadGroupDetails(context, groupItem);
      }
    }
  }

  Future<void> _checkConfirmedWorkers(DateTime date) async {
    setState(() => _isCheckingWorkers = true);

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;

      if (uid == null) {
        setState(() {
          _hasConfirmedWorkers = false;
          _isCheckingWorkers = false;
        });
        return;
      }

      final businesses = await _firestoreService.getMyBusiness(uid);
      if (businesses.isEmpty) {
        setState(() {
          _hasConfirmedWorkers = false;
          _isCheckingWorkers = false;
        });
        return;
      }

      bool hasConfirmed = false;
      for (final business in businesses) {
        final confirmedWorkers =
            await _getConfirmedWorkersForDate(date, business.id);
        if (confirmedWorkers.isNotEmpty) {
          hasConfirmed = true;
          break;
        }
      }

      setState(() {
        _hasConfirmedWorkers = hasConfirmed;
        _isCheckingWorkers = false;
      });
    } catch (e) {
      debugPrint('❌ 확정 인원 체크 실패: $e');
      setState(() {
        _hasConfirmedWorkers = false;
        _isCheckingWorkers = false;
      });
    }
  }

  Future<List<ApplicationModel>> _getConfirmedWorkersForDate(
      DateTime date, String businessId) async {
    final dateStart = DateTime(date.year, date.month, date.day);

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('status', isEqualTo: 'CONFIRMED')
          .get();

      final allConfirmed = snapshot.docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .toList();

      final result = <ApplicationModel>[];

      for (final app in allConfirmed) {
        final isReallyLongTerm =
            app.workDays != null && app.workDays!.isNotEmpty;

        if (!isReallyLongTerm) {
          if (DateUtils.isSameDay(app.workDate, dateStart)) result.add(app);
          continue;
        }

        final endDate = app.actualResignDate ?? app.workEndDate;
        if (endDate == null) continue;

        DateTime effectiveStartDate = app.desiredStartDate ?? app.workDate;
        if (app.confirmedAt != null && app.desiredStartDate == null) {
          final confirmedDate = DateTime(app.confirmedAt!.year,
              app.confirmedAt!.month, app.confirmedAt!.day);
          if (confirmedDate.isAfter(app.workDate)) {
            effectiveStartDate = confirmedDate;
          }
        }

        final startDateOnly = DateTime(effectiveStartDate.year,
            effectiveStartDate.month, effectiveStartDate.day);
        final endDateOnly =
            DateTime(endDate.year, endDate.month, endDate.day);

        if (dateStart.isBefore(startDateOnly) ||
            dateStart.isAfter(endDateOnly)) {
          continue;
        }

        if (app.leaveDates != null && app.leaveDates!.isNotEmpty) {
          final isLeaveDay = app.leaveDates!.any((leaveDate) =>
              leaveDate.year == dateStart.year &&
              leaveDate.month == dateStart.month &&
              leaveDate.day == dateStart.day);
          if (isLeaveDay) continue;
        }

        const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
        final dayWeekday = weekdays[date.weekday - 1];
        if (app.workDays!.contains(dayWeekday)) result.add(app);
      }

      return result;
    } catch (e) {
      debugPrint('❌ 확정 근무자 조회 실패: $e');
      return [];
    }
  }

  Future<void> _showAttendancePopup() async {
    if (_selectedDay == null) return;

    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final uid = userProvider.currentUser?.uid;

    if (uid == null) {
      ToastHelper.showError('로그인 정보를 찾을 수 없습니다');
      return;
    }

    try {
      final businesses = await _firestoreService.getMyBusiness(uid);
      if (businesses.isEmpty) {
        ToastHelper.showError('등록된 사업장이 없습니다');
        return;
      }

      final businessIds = businesses.map((b) => b.id).toList();
      final currentBusinessId = userProvider.currentUser?.businessId;

      if (!mounted) return;
      final hasChanges = await showDialog<bool>(
        context: context,
        builder: (context) => AttendanceStatusDialog(
          date: _selectedDay!,
          businessIds: businessIds,
          initialBusinessId: currentBusinessId,
        ),
      );

      if (hasChanges == true && mounted) {
        _reload();
      }
    } catch (e) {
      debugPrint('❌ 사업장 조회 실패: $e');
      ToastHelper.showError('사업장 정보를 불러올 수 없습니다');
    }
  }
}
