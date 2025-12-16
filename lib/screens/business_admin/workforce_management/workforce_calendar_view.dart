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

// Providers
import '../../../providers/user_provider.dart';

// Utils
import '../../../utils/toast_helper.dart';
import '../../../utils/responsive_helper.dart';

// Widgets
import '../../../widgets/common/loading_widget.dart';
import '../../../theme/app_colors.dart';

// Dialogs
import '../dialogs/to_list_dialogs.dart';
import '../dialogs/attendance_status_dialog.dart';
import '../dialogs/fixed_worker_management_dialog.dart';

// Local Widgets
import '../../../widgets/admin/cards/admin_to_group_card.dart';

/// 인력 관리 - 캘린더 뷰 (business_admin_home_screen 스타일 통일)
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

  List<TOGroupItem> _allGroupItems = [];
  bool _isLoading = true;

  // 이중 토글 상태
  final Set<String> _expandedGroups = {};
  final Set<String> _expandedTOs = {};
  
  // ✨ Lazy Loading 상태
  final Set<String> _loadingGroups = {};
  final Set<String> _loadingTOs = {};
  
  // ⭐ 인원현황 관련
  bool _hasConfirmedWorkers = false;
  bool _isCheckingWorkers = false;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _dialogs = TOListDialogs(
      context: context,
      firestoreService: _firestoreService,
      onChanged: _loadData,
    );
    _loadData();
  }

  /// ✨ 데이터 로드 (Lazy Loading - 겉 카드만)
  Future<void> _loadData() async {
    // ✅ Phase 3: 새로고침 시 목록 캐시 무효화
    _firestoreService.invalidateListCache();
    
    setState(() => _isLoading = true);

    try {
      // ✨ 겉 카드만 로드 (진행중 + 마감 모두)
      final groupItems = await _firestoreService.getTOGroupItemsLight(
        activeOnly: false,
        closedOnly: false,
      );

      setState(() {
        _allGroupItems = groupItems;
        // ⭐ 아직 로딩 끝내지 않음
      });

      print('✅ [Lazy] 캘린더 초기 로드 완료: ${groupItems.length}개 카드');
      
      // ⭐ 선택된 날짜의 그룹 상세 로드 (로딩 상태 유지)
      if (_selectedDay != null) {
        await _loadGroupDetailsForDay(_selectedDay!);
        _checkConfirmedWorkers(_selectedDay!);
      }
      
      // ⭐ 모든 로드 완료 후 로딩 종료
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('❌ 데이터 로드 실패: $e');
      setState(() => _isLoading = false);
      ToastHelper.showError('데이터를 불러오는데 실패했습니다.');
    }
  }

  /// 특정 날짜의 TO 그룹 목록
  List<TOGroupItem> _getGroupItemsForDay(DateTime day) {
    return _allGroupItems.where((groupItem) {
      final masterTO = groupItem.masterTO;
      
      if (masterTO.isLongTerm) {
        // 장기 TO: startDate ~ endDate 범위 확인
        if (masterTO.startDate == null || masterTO.endDate == null) return false;
        final isInRange = !day.isBefore(masterTO.startDate!) && !day.isAfter(masterTO.endDate!);
        if (!isInRange) return false;

        // workDays 확인
        if (masterTO.workDays != null && masterTO.workDays!.isNotEmpty) {
          final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
          final dayOfWeek = weekdays[day.weekday - 1];
          return masterTO.workDays!.contains(dayOfWeek);
        }
        return true;
      } else if (groupItem.isGrouped) {
      // ⭐ 그룹 상세 로드 전: masterTO의 그룹 기간으로 범위 확인
      if (!groupItem.isGroupDetailLoaded) {
        final masterTO = groupItem.masterTO;
        if (masterTO.startDate != null && masterTO.endDate != null) {
          return !day.isBefore(masterTO.startDate!) && !day.isAfter(masterTO.endDate!);
        }
        // startDate/endDate 없으면 masterTO.date만 확인 (fallback)
        return DateUtils.isSameDay(masterTO.date, day);
      }
      
      // 그룹 상세 로드 후: 그룹 내 TO 중 하나라도 해당 날짜면 표시
      return groupItem.groupTOs.any((toItem) => 
        DateUtils.isSameDay(toItem.to.date, day)
      );
    } else {
        // 단일 TO: 날짜 일치
        return DateUtils.isSameDay(masterTO.date, day);
      }
    }).toList();
  }

  /// 캘린더 이벤트 마커
  List<dynamic> _getEventsForDay(DateTime day) {
    final events = <String>[];
    
    final dayGroupItems = _getGroupItemsForDay(day);
    
    // 장기 TO 확인
    final hasLongTO = dayGroupItems.any((item) => item.masterTO.isLongTerm);
    
    // 단기 TO 확인
    final hasSingleTO = dayGroupItems.any((item) => !item.masterTO.isLongTerm);
    
    if (hasLongTO) events.add('long');
    if (hasSingleTO) events.add('single');
    
    return events;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const LoadingWidget(message: 'TO 목록을 불러오는 중...');
    }

    return CustomScrollView(
      slivers: [
        // 캘린더
        SliverToBoxAdapter(
          child: _buildCalendar(),
        ),
        // ✨ 범례 - 세련된 디자인
        SliverToBoxAdapter(
          child: _buildLegendSection(),
        ),

        const SliverToBoxAdapter(
          child: Divider(height: 1),
        ),

        // 선택한 날짜 헤더
        if (_selectedDay != null)
          SliverToBoxAdapter(
            child: _buildDateHeader(),
          ),

        const SliverToBoxAdapter(
          child: Divider(height: 1),
        ),

        // 선택한 날짜의 TO 목록
        _buildSliverDayTOList(),
      ],
    );
  }

  /// ✨ 범례 섹션 - 그라데이션 박스
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
            theme.primaryColor.withOpacity(0.05),
            theme.primaryColor.withOpacity(0.02),
          ],
        ),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: ResponsiveHelper.spacing(context, 20),
        runSpacing: ResponsiveHelper.spacing(context, 8),
        children: [
          _buildLegendItem(theme.primaryColor, '단기 진행중', isLongTerm: false),
          _buildLegendItem(AppColors.longTerm, '장기 진행중', isLongTerm: false),  // ✅ 보라색 + 원형
          _buildLegendItem(Colors.grey[400]!, '과거/마감', isLongTerm: false),
        ],
      ),
    );
  }

  /// 캘린더 위젯
  Widget _buildCalendar() {
    return TableCalendar(
      locale: 'ko_KR',
      firstDay: DateTime.utc(2024, 1, 1),
      lastDay: DateTime.utc(2050, 12, 31),
      focusedDay: _focusedDay,
      calendarFormat: CalendarFormat.month,
      
      daysOfWeekHeight: 30,
      rowHeight: 40,

      selectedDayPredicate: (day) => DateUtils.isSameDay(_selectedDay, day),
      
      onDaySelected: (selectedDay, focusedDay) {
        setState(() {
          _selectedDay = selectedDay;
          _focusedDay = focusedDay;
          // 날짜 변경 시 토글 초기화
          _expandedGroups.clear();
          _expandedTOs.clear();
        });
        // ⭐ 해당 날짜의 그룹 TO 상세 로드
        _loadGroupDetailsForDay(selectedDay);
        // ⭐ 확정 인원 체크
        _checkConfirmedWorkers(selectedDay);
      },

      onPageChanged: (focusedDay) {
        setState(() {
          _focusedDay = focusedDay;
        });
      },

      // 이벤트 마커
      eventLoader: _getEventsForDay,

      calendarBuilders: CalendarBuilders(
        markerBuilder: (context, date, events) {
          if (events.isEmpty) return null;

          final hasLong = events.contains('long');
          final hasSingle = events.contains('single');
          
          // ⭐ 날짜가 지났거나 마감된 공고인지 확인
          final dayGroupItems = _getGroupItemsForDay(date);
          final isPastOrClosed = date.isBefore(DateTime.now().subtract(const Duration(days: 1))) ||
              dayGroupItems.every((item) => item.masterTO.isManualClosed);

          // ⭐ 회색 또는 기본 색상
          final Color shortColor = isPastOrClosed ? Colors.grey[400]! : Theme.of(context).primaryColor;
          final Color longColor = isPastOrClosed ? Colors.grey[400]! : AppColors.longTerm;  // ✅ 보라색

          return Positioned(
            bottom: 3,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ⭐ 단기 TO: 원형
                if (hasSingle)
                  Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: shortColor,
                    ),
                  ),
                // ⭐ 장기 TO: 원형 (단기와 동일)
                if (hasLong)
                  Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: longColor,
                    ),
                  ),
              ],
            ),
          );
        },
      ),

      calendarStyle: CalendarStyle(
        markersMaxCount: 2,
        todayDecoration: BoxDecoration(
          color: Theme.of(context).primaryColor.withOpacity(0.5),
          shape: BoxShape.circle,
        ),
        selectedDecoration: BoxDecoration(
          color: Theme.of(context).primaryColor,
          shape: BoxShape.circle,
        ),
      ),

      headerStyle: HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
        titleTextStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        headerPadding: EdgeInsets.symmetric(vertical: 8),
      ),
    );
  }

  /// ✨ 날짜 헤더 - 간결한 디자인 + 고정근무 버튼
  Widget _buildDateHeader() {
    final theme = Theme.of(context);
    
    // 날짜 포맷: "25년 12월 15일(월)"
    final year = _selectedDay!.year.toString().substring(2);
    final month = _selectedDay!.month;
    final day = _selectedDay!.day;
    final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final weekday = weekdays[_selectedDay!.weekday - 1];
    final dateStr = '$year/$month/$day($weekday)';

    return Container(
      padding: EdgeInsets.symmetric(
        vertical: ResponsiveHelper.spacing(context, 14),
        horizontal: ResponsiveHelper.spacing(context, 16),
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.primaryColor.withOpacity(0.12),
            theme.primaryColor.withOpacity(0.06),
          ],
        ),
        border: Border(
          bottom: BorderSide(
            color: theme.primaryColor.withOpacity(0.3),
            width: 1.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // 날짜 아이콘
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
            decoration: BoxDecoration(
              color: theme.primaryColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.event,
              color: theme.primaryColor,
              size: ResponsiveHelper.iconSize(context, 20),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          
          // 날짜 텍스트
          Text(
            dateStr,
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              fontWeight: FontWeight.bold,
              color: theme.primaryColor,
            ),
          ),
          
          const Spacer(),
          
          // ✨ 당일명단 버튼 (기존 유지)
          Container(
            decoration: BoxDecoration(
              gradient: _hasConfirmedWorkers
                  ? LinearGradient(
                      colors: [
                        theme.primaryColor,
                        theme.primaryColor.withOpacity(0.85),
                      ],
                    )
                  : null,
              color: _hasConfirmedWorkers ? null : Colors.grey[300],
              borderRadius: BorderRadius.circular(12),
              boxShadow: _hasConfirmedWorkers
                  ? [
                      BoxShadow(
                        color: theme.primaryColor.withOpacity(0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _hasConfirmedWorkers ? _showAttendancePopup : null,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 14),
                    vertical: ResponsiveHelper.spacing(context, 10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.how_to_reg,
                        size: ResponsiveHelper.iconSize(context, 18),
                        color: _hasConfirmedWorkers ? Colors.white : Colors.grey[600],
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                      Text(
                        '당일명단',
                        style: ResponsiveHelper.smallStyle(context).copyWith(
                          color: _hasConfirmedWorkers ? Colors.white : Colors.grey[600],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          
          // ✨ 고정근무 버튼 (신규 추가)
          Container(
            decoration: BoxDecoration(
              color: AppColors.longTermLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.longTerm.withOpacity(0.3)),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _openFixedWorkerManagement,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 14),
                    vertical: ResponsiveHelper.spacing(context, 10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.settings,
                        size: ResponsiveHelper.iconSize(context, 18),
                        color: AppColors.longTermDark,
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                      Text(
                        '고정관리',
                        style: ResponsiveHelper.smallStyle(context).copyWith(
                          color: AppColors.longTermDark,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 고정근무 관리 다이얼로그 열기
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

      final businessIds = businesses.map((b) => b.id).toList();

      showDialog(
        context: context,
        builder: (context) => FixedWorkerManagementDialog(
          businessIds: businessIds,
          onChanged: () {
            _loadData();
          },
        ),
      );
    } catch (e) {
      print('❌ 사업장 조회 실패: $e');
      ToastHelper.showError('사업장 정보를 불러올 수 없습니다');
    }
  }

  /// 선택한 날짜의 TO 목록 (Sliver 버전)
  Widget _buildSliverDayTOList() {
    if (_selectedDay == null) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Text(
            '날짜를 선택해주세요',
            style: ResponsiveHelper.subtitleStyle(
              context,
              color: Colors.grey[600],
            ),
          ),
        ),
      );
    }

    final dayGroupItems = _getGroupItemsForDay(_selectedDay!);

    if (dayGroupItems.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.event_busy, 
                size: ResponsiveHelper.iconSize(context, 80), 
                color: Colors.grey[300]
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              Text(
                '이 날짜에 등록된 TO가 없습니다',
                style: ResponsiveHelper.subtitleStyle(
                  context,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: ResponsiveHelper.cardPadding(context),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final groupItem = dayGroupItems[index];
            return Padding(
              padding: EdgeInsets.only(
                bottom: ResponsiveHelper.spacing(context, 16),
              ),
              child: TOGroupCard(
                groupItem: groupItem,
                firestoreService: _firestoreService,
                dialogs: _dialogs,
                allGroupItems: _allGroupItems,
                onChanged: _loadData,
                isExpanded: _expandedGroups.contains(
                  groupItem.masterTO.groupId ?? groupItem.masterTO.id
                ),
                expandedTOs: _expandedTOs,
                onToggleExpand: () => _handleGroupToggle(groupItem),
                onToggleTOExpand: (toId) async {
                  // toId로 해당 TOItem 찾기
                  final toItem = groupItem.groupTOs.firstWhere(
                    (item) => item.to.id == toId,
                    orElse: () => groupItem.groupTOs.first,
                  );
                  await _handleTOToggle(toItem);
                },
                selectedDate: _selectedDay,
                // ✨ 로딩 상태 전달
                isGroupLoading: _loadingGroups.contains(
                  groupItem.masterTO.groupId ?? groupItem.masterTO.id
                ),
                loadingTOs: _loadingTOs,
                onAffectedTOsChanged: _refreshAffectedTOs,  // 🔥 추가
              ),
            );
          },
          childCount: dayGroupItems.length,
        ),
      ),
    );
  }

  /// ✨ 그룹 카드 펼침 핸들러 (Lazy Loading)
  Future<void> _handleGroupToggle(TOGroupItem groupItem) async {
    final key = groupItem.masterTO.groupId ?? groupItem.masterTO.id;
    
    // 이미 펼쳐져 있으면 접기만
    if (_expandedGroups.contains(key)) {
      setState(() {
        _expandedGroups.remove(key);
        _expandedTOs.clear();
      });
      return;
    }
    
    // 다른 그룹 접기
    setState(() {
      _expandedGroups.clear();
      _expandedTOs.clear();
    });
    
    // 그룹 TO이고 아직 상세 로드 안됐으면 로드
    if (groupItem.needsGroupDetailLoad) {
      setState(() => _loadingGroups.add(key));
      
      try {
        final toItems = await _firestoreService.loadGroupTOsLight(
          groupItem.masterTO.groupId!
        );
        groupItem.setGroupTOs(toItems);
      } catch (e) {
        print('❌ 그룹 상세 로드 실패: $e');
        ToastHelper.showError('데이터를 불러오는데 실패했습니다.');
      }
      
      setState(() => _loadingGroups.remove(key));
    }
    
    // ✨ 단일 TO인 경우: WorkDetails 로드 필요
    if (!groupItem.isGrouped && groupItem.groupTOs.isNotEmpty) {
      final toItem = groupItem.groupTOs.first;
      if (toItem.needsWorkDetailLoad) {
        setState(() => _loadingTOs.add(toItem.to.id));
        
        try {
          final result = await _firestoreService.loadTOWorkDetails(toItem.to);
          toItem.setWorkDetails(
            result['workDetails'] as List<WorkDetailModel>,
            result['workStats'] as Map<String, Map<String, int>>,
          );
        } catch (e) {
          print('❌ TO 상세 로드 실패: $e');
          ToastHelper.showError('데이터를 불러오는데 실패했습니다.');
        }
        
        setState(() => _loadingTOs.remove(toItem.to.id));
      }
    }
    
    // 펼치기
    setState(() => _expandedGroups.add(key));
  }

  /// ✨ TO 카드 펼침 핸들러 (Lazy Loading)
  Future<void> _handleTOToggle(TOItem toItem) async {
    final key = toItem.to.id;
    
    // 이미 펼쳐져 있으면 접기만
    if (_expandedTOs.contains(key)) {
      setState(() => _expandedTOs.remove(key));
      return;
    }
    
    // 다른 TO 접기
    setState(() => _expandedTOs.clear());
    
    // 아직 WorkDetails 로드 안됐으면 로드
    if (toItem.needsWorkDetailLoad) {
      setState(() => _loadingTOs.add(key));
      
      try {
        final result = await _firestoreService.loadTOWorkDetails(toItem.to);
        toItem.setWorkDetails(
          result['workDetails'] as List<WorkDetailModel>,
          result['workStats'] as Map<String, Map<String, int>>,
        );
      } catch (e) {
        print('❌ TO 상세 로드 실패: $e');
        ToastHelper.showError('데이터를 불러오는데 실패했습니다.');
      }
      
      setState(() => _loadingTOs.remove(key));
    }
    
    // 펼치기
    setState(() => _expandedTOs.add(key));
  }
  /// 🔥 영향받은 TO들만 개별 새로고침 (카드 접힘 상태 유지)
  Future<void> _refreshAffectedTOs(Set<String> affectedTOIds) async {
    if (affectedTOIds.isEmpty) return;
    
    print('🔄 영향받은 TO ${affectedTOIds.length}개 새로고침: $affectedTOIds');
    
    // ✅ 갱신된 그룹 마스터 ID 추적 (중복 갱신 방지)
    final Set<String> updatedGroupIds = {};
    
    for (var toId in affectedTOIds) {
      bool found = false;
      
      // 1. 모든 그룹에서 해당 TO 찾기
      for (var groupItem in _allGroupItems) {
        final toItem = groupItem.groupTOs.cast<TOItem?>().firstWhere(
          (item) => item?.to.id == toId,
          orElse: () => null,
        );
        
        if (toItem != null) {
          found = true;
          try {
            // ✅ 캐시 무효화
            _firestoreService.clearCache(toId: toId);
            
            // ✅ TO 문서 직접 조회 (Increment된 정확한 값)
            final toDoc = await _firestoreService.getTO(toId);
            if (toDoc != null) {
              // 겉 카드 통계 즉시 업데이트
              toItem.updateOuterStats(
                confirmed: toDoc.totalConfirmed,
                pending: toDoc.totalPending,
                required: toDoc.totalRequired,
              );
              print('✅ TO $toId 겉 통계 갱신: 확정=${toDoc.totalConfirmed}, 대기=${toDoc.totalPending}');
            }
            
            // 펼쳐진 상태면 WorkDetails도 새로고침
            if (_expandedTOs.contains(toId)) {
              final result = await _firestoreService.loadTOWorkDetails(toItem.to);
              toItem.setWorkDetails(
                result['workDetails'] as List<WorkDetailModel>,
                result['workStats'] as Map<String, Map<String, int>>,
              );
              print('✅ TO $toId WorkDetails도 갱신');
            }
          } catch (e) {
            print('❌ TO $toId 새로고침 실패: $e');
          }
          break;  // 찾았으면 다음 toId로
        }
      }
      
      // 2. ✅ 찾지 못했으면 그룹 마스터 갱신 (그룹이 접혀있는 경우)
      if (!found) {
        try {
          final toDoc = await _firestoreService.getTO(toId);
          if (toDoc != null && toDoc.groupId != null) {
            final groupId = toDoc.groupId!;
            
            // 이미 갱신한 그룹이면 스킵
            if (updatedGroupIds.contains(groupId)) continue;
            
            // 그룹 마스터 찾기
            for (var groupItem in _allGroupItems) {
              if (groupItem.masterTO.groupId == groupId) {
                // 마스터 TO 다시 조회
                final masterDoc = await _firestoreService.getTO(groupItem.masterTO.id);
                if (masterDoc != null && groupItem.groupTOs.isNotEmpty) {
                  groupItem.groupTOs.first.updateOuterStats(
                    confirmed: masterDoc.groupTotalConfirmed ?? masterDoc.totalConfirmed,
                    pending: masterDoc.groupTotalPending ?? masterDoc.totalPending,
                    required: masterDoc.groupTotalRequired ?? masterDoc.totalRequired,
                  );
                  updatedGroupIds.add(groupId);
                  print('✅ 그룹 마스터 ${groupItem.masterTO.id} 통계 갱신: 대기=${masterDoc.groupTotalPending}');
                }
                break;
              }
            }
          }
        } catch (e) {
          print('❌ 그룹 마스터 갱신 실패: $e');
        }
      }
    }
    
    // UI 갱신
    if (mounted) setState(() {});
  }


  /// ✨ 범례 아이템 - 세련된 스타일
  Widget _buildLegendItem(Color color, String label, {required bool isLongTerm}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 10),
        vertical: ResponsiveHelper.spacing(context, 6),
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          isLongTerm
              ? Icon(Icons.star, size: 12, color: color)
              : Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          Text(
            label,
            style: ResponsiveHelper.tinyStyle(
              context,
              color: Colors.grey[800],
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
  /// ⭐ 선택된 날짜의 그룹 TO 상세 자동 로드
  Future<void> _loadGroupDetailsForDay(DateTime day) async {
    final dayGroupItems = _getGroupItemsForDay(day);
    
    for (var groupItem in dayGroupItems) {
      // 그룹 TO이고 상세 로드 안 됐으면 로드
      if (groupItem.isGrouped && !groupItem.isGroupDetailLoaded) {
        final key = groupItem.masterTO.groupId ?? groupItem.masterTO.id;
        
        setState(() => _loadingGroups.add(key));
        
        try {
          final toItems = await _firestoreService.loadGroupTOsLight(
            groupItem.masterTO.groupId!
          );
          groupItem.setGroupTOs(toItems);
        } catch (e) {
          print('❌ 그룹 상세 로드 실패: $e');
        }
        
        if (mounted) {
          setState(() => _loadingGroups.remove(key));
        }
      }
    }
  }

  /// ⭐ 확정 인원 체크 (모든 관리 사업장)
  Future<void> _checkConfirmedWorkers(DateTime date) async {
    setState(() => _isCheckingWorkers = true);

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;

      if (uid == null) {
        print('   ❌ UID가 null');
        setState(() {
          _hasConfirmedWorkers = false;
          _isCheckingWorkers = false;
        });
        return;
      }

      // ⭐ 관리자의 모든 사업장 조회
      final businesses = await _firestoreService.getMyBusiness(uid);
      print('   📋 관리 사업장: ${businesses.length}개');
      
      if (businesses.isEmpty) {
        print('   ❌ 사업장 없음');
        setState(() {
          _hasConfirmedWorkers = false;
          _isCheckingWorkers = false;
        });
        return;
      }

      // ⭐ 모든 사업장에서 확정자 체크
      bool hasConfirmed = false;
      for (final business in businesses) {
        print('');
        print('   🏢 사업장: ${business.name} (${business.id})');
        final confirmedWorkers = await _getConfirmedWorkersForDate(date, business.id);
        print('   ✅ 최종 확정 근무자: ${confirmedWorkers.length}명');
        
        if (confirmedWorkers.isNotEmpty) {
          hasConfirmed = true;
          for (final worker in confirmedWorkers) {
            print('      - ${worker.uid}: ${worker.selectedWorkType} (${worker.isLongTermApplication ? "장기" : "단기"})');
          }
          break;
        }
      }

      print('');
      print('═══════════════════════════════════════════════════════');
      print('🎯 [당일명단] 결과: hasConfirmedWorkers = $hasConfirmed');
      print('═══════════════════════════════════════════════════════');
      print('');

      setState(() {
        _hasConfirmedWorkers = hasConfirmed;
        _isCheckingWorkers = false;
      });
    } catch (e) {
      print('❌ 확정 인원 체크 실패: $e');
      setState(() {
        _hasConfirmedWorkers = false;
        _isCheckingWorkers = false;
      });
    }
  }
  /// ⭐ 해당 날짜의 확정 근무자 조회
  Future<List<ApplicationModel>> _getConfirmedWorkersForDate(
    DateTime date,
    String businessId,
  ) async {
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

      // 단기 + 장기 필터링
      final result = <ApplicationModel>[];
      
      for (final app in allConfirmed) {
        // ✅ 진짜 장기인지 판단: workDays가 있어야 장기
        final isReallyLongTerm = app.workDays != null && app.workDays!.isNotEmpty;
        
        // 단기 근무 (workDays가 없으면 단기)
        if (!isReallyLongTerm) {
          if (DateUtils.isSameDay(app.workDate, dateStart)) {
            result.add(app);
          }
          continue;
        }
        
        // 장기 근무
        if (app.workEndDate == null) continue;

        // 기간 체크 (시간 제거하고 날짜만 비교)
        final workDateOnly = DateTime(app.workDate.year, app.workDate.month, app.workDate.day);
        final workEndDateOnly = DateTime(app.workEndDate!.year, app.workEndDate!.month, app.workEndDate!.day);
        
        if (dateStart.isBefore(workDateOnly) || dateStart.isAfter(workEndDateOnly)) {
          continue;
        }

        // 요일 체크
        final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
        final dayWeekday = weekdays[date.weekday - 1];
        
        if (app.workDays!.contains(dayWeekday)) {
          result.add(app);
        }
      }

      return result;
    } catch (e) {
      print('❌ 확정 근무자 조회 실패: $e');
      return [];
    }
  }

  /// ⭐ 인원현황 팝업 표시
  Future<void> _showAttendancePopup() async {
    if (_selectedDay == null) return;

    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final uid = userProvider.currentUser?.uid;

    if (uid == null) {
      ToastHelper.showError('로그인 정보를 찾을 수 없습니다');
      return;
    }

    try {
      // ⭐ 관리자의 모든 사업장 조회
      final businesses = await _firestoreService.getMyBusiness(uid);

      if (businesses.isEmpty) {
        ToastHelper.showError('등록된 사업장이 없습니다');
        return;
      }

      final businessIds = businesses.map((b) => b.id).toList();
      final currentBusinessId = userProvider.currentUser?.businessId;

      final hasChanges = await showDialog<bool>(
        context: context,
        builder: (context) => AttendanceStatusDialog(
          date: _selectedDay!,
          businessIds: businessIds,
          initialBusinessId: currentBusinessId,
        ),
      );
      
      // ✅ 변경 사항 있으면 데이터 새로고침
      if (hasChanges == true && mounted) {
        await _loadData();
      }
    } catch (e) {
      print('❌ 사업장 조회 실패: $e');
      ToastHelper.showError('사업장 정보를 불러올 수 없습니다');
    }
  }
}