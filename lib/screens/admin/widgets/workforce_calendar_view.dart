import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';

// Models
import '../../../models/core/to_model.dart';
import '../../../models/core/work_detail_model.dart';
import '../../../models/ui/admin_to_list_ui_models.dart';

// Services
import '../../../services/firestore_service.dart';

// Utils
import '../../../utils/toast_helper.dart';

// Widgets
import '../../../widgets/common/loading_widget.dart';

// Dialogs
import '../dialogs/to_list_dialogs.dart';

// Local Widgets
import 'to_group_card.dart';

/// 인력 관리 - 캘린더 뷰 (리팩토링 완료)
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

  /// 데이터 로드 (ListView와 동일한 로직)
  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // 진행중 + 마감 TO 모두 가져오기
      final active = await _firestoreService.getActiveTOs();
      final closed = await _firestoreService.getClosedTOs();
      final allTOs = [...active, ...closed];

      List<TOGroupItem> groupItems = [];
      
      for (var masterTO in allTOs) {
        if (masterTO.isGrouped && masterTO.groupId != null) {
          final groupTOs = await _firestoreService.getTOsByGroup(masterTO.groupId!);
          final toIds = groupTOs.map((to) => to.id).toList();
          
          final batchResults = await Future.wait([
            _firestoreService.getWorkDetailsBatch(toIds, forceRefresh: true),
            _firestoreService.calculateGroupTimeRange(masterTO.groupId!, forceRefresh: true),
          ]);
          
          final workDetailsMap = batchResults[0] as Map<String, List<WorkDetailModel>>;
          final timeRange = batchResults[1] as Map<String, String>;
          final applicationsMap = await _firestoreService.getApplicationsByTOIds(toIds);

          List<TOItem> toItems = [];
          for (var to in groupTOs) {
            final toWorkDetails = workDetailsMap[to.id] ?? [];
            final apps = applicationsMap[to.id] ?? [];

            int confirmed = apps.where((a) => a.status == 'CONFIRMED').length;
            int pending = apps.where((a) => a.status == 'PENDING').length;
            
            int totalRequired = 0;
            for (var work in toWorkDetails) {
              totalRequired += work.requiredCount;
            }
            
            Map<String, Map<String, int>> workStats = {};
            for (var work in toWorkDetails) {
              final workApps = apps.where((a) => a.selectedWorkType == work.workType);
              workStats[work.workType] = {
                'confirmed': workApps.where((a) => a.status == 'CONFIRMED').length,
                'pending': workApps.where((a) => a.status == 'PENDING').length,
              };
            }

            toItems.add(TOItem(
              to: to,
              workDetails: toWorkDetails,
              confirmedCount: confirmed,
              pendingCount: pending,
              totalRequired: totalRequired,
              workDetailStats: workStats,
            ));
          }
          
          masterTO.setTimeRange(timeRange['minStart']!, timeRange['maxEnd']!);
          
          groupItems.add(TOGroupItem(
            masterTO: masterTO,
            groupTOs: toItems,
            isGrouped: true,
          ));
          
        } else {
          final workDetails = await _firestoreService.getWorkDetails(
            masterTO.id,
            forceRefresh: true
          );
          
          if (workDetails.isNotEmpty) {
            String? minStart;
            String? maxEnd;
            
            for (var work in workDetails) {
              if (minStart == null || work.startTime.compareTo(minStart) < 0) {
                minStart = work.startTime;
              }
              if (maxEnd == null || work.endTime.compareTo(maxEnd) > 0) {
                maxEnd = work.endTime;
              }
            }
            
            if (minStart != null && maxEnd != null) {
              masterTO.setTimeRange(minStart, maxEnd);
            }
          }
          
          final apps = await _firestoreService.getApplicationsByTO(
            masterTO.businessId,
            masterTO.title,
            masterTO.date,
          );
          
          Map<String, Map<String, int>> workStats = {};
          for (var work in workDetails) {
            final workApps = apps.where((a) => a.selectedWorkType == work.workType);            
            workStats[work.workType] = {
              'confirmed': workApps.where((a) => a.status == 'CONFIRMED').length,
              'pending': workApps.where((a) => a.status == 'PENDING').length,
            };
          }
          
          int totalConfirmed = 0;
          int totalPending = 0;
          for (var stats in workStats.values) {
            totalConfirmed += stats['confirmed'] as int;
            totalPending += stats['pending'] as int;
          }
          
          int totalRequired = 0;
          for (var work in workDetails) {
            totalRequired += work.requiredCount;
          }
          
          groupItems.add(TOGroupItem(
            masterTO: masterTO.copyWith(totalRequired: totalRequired),
            groupTOs: [
              TOItem(
                to: masterTO.copyWith(totalRequired: totalRequired),
                workDetails: workDetails,
                confirmedCount: totalConfirmed,
                pendingCount: totalPending,
                totalRequired: totalRequired,
                workDetailStats: workStats,
              ),
            ],
            isGrouped: false,
          ));
        }
      }

      setState(() {
        _allGroupItems = groupItems;
        _isLoading = false;
      });

      print('✅ 캘린더 데이터 로드: ${groupItems.length}개 그룹');
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
        // 그룹 TO: 그룹 내 TO 중 하나라도 해당 날짜면 표시
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

  /// 캘린더 위젯
  Widget _buildCalendar() {
    return TableCalendar(
      locale: 'ko_KR',
      firstDay: DateTime.utc(2024, 1, 1),
      lastDay: DateTime.utc(2050, 12, 31),
      focusedDay: _focusedDay,
      calendarFormat: CalendarFormat.month,
      
      daysOfWeekHeight: 40,
      rowHeight: 48,

      selectedDayPredicate: (day) => DateUtils.isSameDay(_selectedDay, day),
      
      onDaySelected: (selectedDay, focusedDay) {
        setState(() {
          _selectedDay = selectedDay;
          _focusedDay = focusedDay;
          // 날짜 변경 시 토글 초기화
          _expandedGroups.clear();
          _expandedTOs.clear();
        });
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

          return Positioned(
            bottom: 4,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasLong)
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.blue,
                    ),
                  ),
                if (hasSingle)
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.orange,
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

      headerStyle: const HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
      ),
    );
  }

  /// 날짜 헤더
  Widget _buildDateHeader() {
    final isToday = DateUtils.isSameDay(_selectedDay, DateTime.now());
    final isPast = _selectedDay!.isBefore(DateTime.now()) && !isToday;

    String statusText = '';
    Color statusColor = Theme.of(context).primaryColor;

    if (isPast) {
      statusText = '과거 기록';
      statusColor = Colors.grey;
    } else if (isToday) {
      statusText = '오늘';
      statusColor = Colors.green;
    } else {
      statusText = '예정';
      statusColor = Theme.of(context).primaryColor;
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      color: statusColor.withOpacity(0.1),
      child: Row(
        children: [
          Icon(Icons.event, color: statusColor, size: 20),
          const SizedBox(width: 8),
          Text(
            DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(_selectedDay!),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: statusColor,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              statusText,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 선택한 날짜의 TO 목록 (Sliver 버전)
  Widget _buildSliverDayTOList() {
    if (_selectedDay == null) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Text(
            '날짜를 선택해주세요',
            style: TextStyle(
              fontSize: 16,
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
              Icon(Icons.event_busy, size: 80, color: Colors.grey[300]),
              const SizedBox(height: 16),
              Text(
                '이 날짜에 등록된 TO가 없습니다',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final groupItem = dayGroupItems[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
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
                onToggleTOExpand: _handleTOToggle,
              ),
            );
          },
          childCount: dayGroupItems.length,
        ),
      ),
    );
  }

  /// 그룹 토글 핸들러
  void _handleGroupToggle(TOGroupItem groupItem) {
    setState(() {
      final key = groupItem.masterTO.groupId ?? groupItem.masterTO.id;
      if (_expandedGroups.contains(key)) {
        _expandedGroups.remove(key);
        _expandedTOs.clear();
      } else {
        _expandedGroups.clear();
        _expandedTOs.clear();
        _expandedGroups.add(key);
      }
    });
  }

  /// TO 토글 핸들러
  void _handleTOToggle(String toId) {
    setState(() {
      if (_expandedTOs.contains(toId)) {
        _expandedTOs.remove(toId);
      } else {
        _expandedTOs.clear();
        _expandedTOs.add(toId);
      }
    });
  }
}