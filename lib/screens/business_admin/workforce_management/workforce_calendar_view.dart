import 'package:flutter/material.dart';
import '../../../widgets/calendar/app_calendar.dart';
import 'package:provider/provider.dart';
// Models
import '../../../models/core/business_model.dart';
import '../../../models/core/work_detail_data.dart';
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

// Widgets
import '../../../widgets/common/loading_widget.dart';
import '../../../theme/app_colors.dart';

// Dialogs
import '../dialogs/to_list_dialogs.dart';
import '../dialogs/attendance_status_dialog.dart';
import '../dialogs/fixed_worker_management_dialog.dart';
import '../dialogs/close_management_dialog.dart';

// Cards
import '../../../widgets/admin/cards/admin_to_item_card.dart';

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

  // 고정 TO용 synthetic TOItem 캐시 (reload 시 초기화)
  final Map<String, TOItem> _contractTOItems = {};

  String _slotKey(TOGroupItem g, TOItem t) => '${g.id}_${t.slot?.id ?? t.to.id}';

  /// SubAdmin 포함 관리 가능한 사업장 목록 (getMyBusiness가 빈 배열이면 subAdminOf로 fallback)
  Future<List<BusinessModel>> _getAdminBusinesses() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final uid = userProvider.currentUser?.uid;
    if (uid == null) return [];
    var businesses = await _firestoreService.getMyBusiness(uid);
    if (businesses.isEmpty) {
      final bizId = userProvider.currentUser?.businessId;
      if (bizId != null) {
        final biz = await _firestoreService.getBusinessById(bizId);
        if (biz != null) businesses = [biz];
      }
    }
    return businesses;
  }

  // 인원현황 관련 (당일명단 버튼은 항상 활성화)

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
    setState(() {
      _expandedSlots.clear();
      _contractTOItems.clear();
    });
    context.read<WorkforceController>().reload(context).then((_) {
      if (_selectedDay != null && mounted) {
        _loadGroupDetailsForDay(_selectedDay!);
      }
    });
  }

  /// 고정 TO의 synthetic TOItem을 가져오거나 새로 생성 (rebuild마다 재생성 방지)
  TOItem _getOrCreateContractTOItem(TOGroupItem groupItem) {
    return _contractTOItems.putIfAbsent(groupItem.id, () => TOItem(
      to: groupItem.masterTO,
      confirmedCount: groupItem.totalConfirmed,
      pendingCount: groupItem.totalPending,
      totalRequired: groupItem.totalRequired,
      workDetailStats: groupItem.workDetailStats,
      isWorkDetailLoaded: groupItem.isWorkDetailLoaded,
    ));
  }

  /// 특정 날짜의 TO 그룹 목록
  List<TOGroupItem> _getGroupItemsForDay(DateTime day) {
    final allItems = context.read<WorkforceController>().items;
    return allItems.where((groupItem) {
      if (groupItem.isLongTerm) {
        final to = groupItem.masterTO;

        // Timestamp → DateTime 변환 시 시간 정보가 포함되므로 날짜 단위로 정규화
        final start = groupItem.startDate;
        final startDay = DateTime(start.year, start.month, start.day);
        // day에 시간 정보가 포함될 수 있으므로 날짜만 추출하여 비교
        final dayOnly = DateTime(day.year, day.month, day.day);
        if (dayOnly.isBefore(startDay)) return false;

        // 종료일: rangeEnd 우선, 없으면 게시 만료일(postingExpiryDate) 사용
        // createdAt으로 폴백하면 생성일 이후 날짜가 모두 제외되므로 직접 체크
        final effectiveEnd = to.rangeEnd ?? to.postingExpiryDate;
        if (effectiveEnd != null) {
          final endDay = DateTime(effectiveEnd.year, effectiveEnd.month, effectiveEnd.day);
          if (dayOnly.isAfter(endDay)) return false;
        }

        final workDays = to.workDays;
        if (workDays.isNotEmpty) {
          return workDays.contains(FormatHelper.weekday(day));
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
        }
      });
    }

    final bottomPadding = MediaQuery.paddingOf(context).bottom;

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
        // 하단 시스템 UI(홈 인디케이터 / 제스처 바) 여백
        if (bottomPadding > 0)
          SliverPadding(padding: EdgeInsets.only(bottom: bottomPadding)),
      ],
    );
  }

  Widget _buildLegendSection() {
    final theme = Theme.of(context);
    return Column(
      children: [
        const Divider(height: 1, thickness: 1, color: AppColors.grey100),
        Padding(
          padding: EdgeInsets.symmetric(
            vertical: ResponsiveHelper.spacing(context, 10),
            horizontal: ResponsiveHelper.spacing(context, 16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegendItem(theme.primaryColor, '단기 진행중'),
              SizedBox(width: ResponsiveHelper.spacing(context, 20)),
              _buildLegendItem(AppColors.longTerm, '장기 진행중'),
              SizedBox(width: ResponsiveHelper.spacing(context, 20)),
              _buildLegendItem(AppColors.grey400, '과거/마감'),
            ],
          ),
        ),
        Container(height: 8, color: AppColors.grey100),
      ],
    );
  }

  Widget _buildCalendar() {
    final theme = Theme.of(context);

    // 카드 효과 없이 풀너비 플랫 스타일 — 지원자 캘린더와 통일
    return ColoredBox(
      color: Colors.white,
      child: AppCalendar(
          focusedDay: _focusedDay,
          selectedDay: _selectedDay,
          onDaySelected: (selectedDay, focusedDay) {
            setState(() {
              _selectedDay = selectedDay;
              _focusedDay = focusedDay;
              _expandedSlots.clear();
            });
            _loadGroupDetailsForDay(selectedDay);
          },
          onPageChanged: (focusedDay) => setState(() => _focusedDay = focusedDay),
          eventLoader: _getEventsForDay,
          markerBuilder: (context, date, events) {
            if (events.isEmpty) return null;

            final hasLong = events.contains('long');
            final hasSingle = events.contains('single');

            final dayGroupItems = _getGroupItemsForDay(date);
            final isPastOrClosed = date.isBefore(
                    DateTime.now().subtract(const Duration(days: 1))) ||
                dayGroupItems.every((item) => item.isClosed);

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
    );
  }

  Widget _buildDateHeader() {
    final theme = Theme.of(context);

    final month = _selectedDay!.month;
    final day = _selectedDay!.day;
    final dateStr = '$month월 $day일(${FormatHelper.weekday(_selectedDay!)})';

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
                child: _buildActionButton(
                  icon: Icons.how_to_reg,
                  label: '당일명단',
                  isEnabled: true,
                  backgroundColor: theme.primaryColor.withValues(alpha: 0.1),
                  foregroundColor: theme.primaryColor,
                  borderColor: theme.primaryColor.withValues(alpha: 0.35),
                  onTap: _showAttendancePopup,
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
    try {
      final businesses = await _getAdminBusinesses();
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
    final businesses = await _getAdminBusinesses();
    if (!mounted) return;
    if (businesses.isEmpty) {
      ToastHelper.showWarning('등록된 사업장이 없습니다');
      return;
    }

    final hasChanges = await showDialog<bool>(
      context: context,
      builder: (context) => CloseManagementDialog(
        initialMonth: _focusedDay,
        businessIds: businesses.map((b) => b.id).toList(),
      ),
    );

    if (hasChanges == true && mounted) {
      _reload(); // 마감 변경 후 데이터 재로드
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

    // ⚠️ 캘린더 뷰는 TOGroupCard가 아닌 TOItemCard를 사용한다.
    // 이유: 날짜가 이미 선택된 상태에서 슬롯 하나씩 표시하는 compact 카드가 적합하며,
    // 고정 TO의 dateOverride(선택된 날짜를 날짜 배지에 표시) 기능이 TOGroupCard에 없음.
    // TOItemCard/TOGroupCard 클래스 주석 참고. 이 결정을 되돌리지 말 것.
    final List<Widget> cards = [];
    for (final groupItem in dayGroupItems) {
      if (groupItem.isLongTerm) {
        final key = groupItem.id;
        cards.add(TOItemCard(
          toItem: _getOrCreateContractTOItem(groupItem),
          groupItem: groupItem,
          dateOverride: _selectedDay, // 고정 TO: 슬롯 날짜 없으므로 선택된 날짜를 전달
          showConnector: false,
          firestoreService: _firestoreService,
          dialogs: _dialogs,
          onChanged: _reload,
          isExpanded: _expandedSlots[key] == true,
          onToggleExpand: () => _handleGroupToggle(groupItem),
          isLoading: _loadingSlots.contains(key),
        ));
      } else {
        final isLoadingGroup = controller.isGroupLoading(groupItem.id);
        if (isLoadingGroup || !groupItem.isGroupDetailLoaded) {
          cards.add(_buildFlexSlotLoadingCard(groupItem));
        } else {
          final matchingSlots = groupItem.groupTOs
              .where((t) => DateUtils.isSameDay(t.slot?.date, _selectedDay))
              .toList();
          for (final slot in matchingSlots) {
            final key = _slotKey(groupItem, slot);
            cards.add(TOItemCard(
              toItem: slot,
              groupItem: groupItem,
              showConnector: false,
              firestoreService: _firestoreService,
              dialogs: _dialogs,
              onChanged: _reload,
              isExpanded: _expandedSlots[key] == true,
              onToggleExpand: () => _handleSlotGroupToggle(groupItem, slot, key),
              isLoading: _loadingSlots.contains(key),
            ));
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
                size: ResponsiveHelper.iconSize(context, 56),
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
          const LoadingWidget(),
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

  /// 고정 TO 카드 펼치기/접기 + 업무상세 로드
  Future<void> _handleGroupToggle(TOGroupItem groupItem) async {
    final key = groupItem.id;
    if (_expandedSlots[key] == true) {
      setState(() => _expandedSlots[key] = false);
      return;
    }
    setState(() {
      _expandedSlots.clear();
      _expandedSlots[key] = true;
    });
    if (!groupItem.isWorkDetailLoaded) {
      setState(() => _loadingSlots.add(key));
      try {
        final result = await _firestoreService.loadTOWorkDetails(groupItem.masterTO);
        final details = result['workDetails'] as List<WorkDetailData>;
        final stats = result['workStats'] as Map<String, Map<String, int>>;
        groupItem.setWorkDetailStats(stats);
        // 캐시된 synthetic TOItem에도 로드된 workDetails + stats 반영
        _contractTOItems[key]?.setWorkDetails(details, stats);
      } catch (e) {
        debugPrint('❌ 고정근무 업무 상세 로드 실패: $e');
      }
      if (mounted) setState(() => _loadingSlots.remove(key));
    } else {
      // groupItem.isWorkDetailLoaded = true이지만 캐시된 TOItem은 workDetails가 없을 수 있음
      // (위젯 재생성 시 _contractTOItems가 초기화되므로)
      final cachedItem = _contractTOItems[key];
      if (cachedItem != null && cachedItem.workDetails.isEmpty) {
        setState(() => _loadingSlots.add(key));
        try {
          final result = await _firestoreService.loadTOWorkDetails(groupItem.masterTO);
          final details = result['workDetails'] as List<WorkDetailData>;
          final stats = result['workStats'] as Map<String, Map<String, int>>;
          groupItem.setWorkDetailStats(stats);
          cachedItem.setWorkDetails(details, stats);
        } catch (e) {
          debugPrint('❌ 고정근무 업무 상세 로드 실패 (재시도): $e');
        }
        if (mounted) setState(() => _loadingSlots.remove(key));
      }
    }
  }

  /// 단기 슬롯 카드 펼치기/접기 + 업무상세 로드
  Future<void> _handleSlotGroupToggle(TOGroupItem groupItem, TOItem slot, String key) async {
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
          result['workDetails'] as List<WorkDetailData>,
          result['workStats'] as Map<String, Map<String, int>>,
        );
      } catch (e) {
        debugPrint('❌ 슬롯 업무 상세 로드 실패: $e');
      }
      if (mounted) setState(() => _loadingSlots.remove(key));
    }
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 5)),
        Text(
          label,
          style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey600),
        ),
      ],
    );
  }

  Future<void> _loadGroupDetailsForDay(DateTime day) async {
    final controller = context.read<WorkforceController>();
    final dayGroupItems = _getGroupItemsForDay(day);

    await Future.wait(
      dayGroupItems
          .where((g) => !g.isLongTerm && !g.isGroupDetailLoaded)
          .map((g) => controller.loadGroupDetails(context, g)),
    );
  }

  Future<void> _showAttendancePopup() async {
    if (_selectedDay == null) return;

    final userProvider = Provider.of<UserProvider>(context, listen: false);

    try {
      final businesses = await _getAdminBusinesses();
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
