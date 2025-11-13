import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Models
import '../../../models/core/to_model.dart';
import '../../../models/core/work_detail_model.dart';
import '../../../models/core/application_model.dart';
import '../../../models/ui/admin_to_list_ui_models.dart';

// Services
import '../../../services/firestore_service.dart';

// Providers
import '../../../providers/user_provider.dart';  // ⭐ 추가

// Utils
import '../../../utils/toast_helper.dart';

// Widgets
import '../../../widgets/common/loading_widget.dart';

// Dialogs
import '../dialogs/to_list_dialogs.dart';
import '../dialogs/attendance_status_dialog.dart';

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
    // ⭐ 초기 날짜의 확정 인원 체크
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkConfirmedWorkers(_selectedDay!);
    });
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
        // ⭐ 범례 추가!
        SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            color: Colors.grey[50],
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 16,
              runSpacing: 8,
              children: [
                _buildLegendItem(Theme.of(context).primaryColor, '단기 진행중', isLongTerm: false),
                _buildLegendItem(Colors.amber[700]!, '장기 진행중', isLongTerm: true),
                _buildLegendItem(Colors.grey[400]!, '과거/마감', isLongTerm: false),
              ],
            ),
          ),
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
          final Color longColor = isPastOrClosed ? Colors.grey[400]! : Colors.amber[700]!;

          return Positioned(
            bottom: 4,
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
                // ⭐ 장기 TO: 별표
                if (hasLong)
                  Icon(
                    Icons.star,
                    size: 10,
                    color: longColor,
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
          
          // ⭐ 인원현황 버튼 추가
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _hasConfirmedWorkers ? _showAttendancePopup : null,
            icon: const Icon(Icons.groups, size: 18),
            label: const Text('인원현황'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _hasConfirmedWorkers ? Colors.blue : Colors.grey,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              textStyle: const TextStyle(fontSize: 13),
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

  /// 범례 아이템
  Widget _buildLegendItem(Color color, String label, {required bool isLongTerm}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        isLongTerm
            ? Icon(Icons.star, size: 10, color: color)
            : Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[700],
          ),
        ),
      ],
    );
  }
  /// ⭐ 확정 인원 체크
  Future<void> _checkConfirmedWorkers(DateTime date) async {
    setState(() => _isCheckingWorkers = true);

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final businessId = userProvider.currentUser?.businessId;

      if (businessId == null) {
        setState(() {
          _hasConfirmedWorkers = false;
          _isCheckingWorkers = false;
        });
        return;
      }

      final confirmedWorkers = await _getConfirmedWorkersForDate(date, businessId);

      setState(() {
        _hasConfirmedWorkers = confirmedWorkers.isNotEmpty;
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
      final result = allConfirmed.where((app) {
        // 단기 근무
        if (!app.isLongTermApplication) {
          return DateUtils.isSameDay(app.workDate, dateStart);
        }
        
        // 장기 근무
        if (app.workEndDate == null) return false;

        // 기간 체크
        if (dateStart.isBefore(app.workDate) || dateStart.isAfter(app.workEndDate!)) {
          return false;
        }

        // 요일 체크
        if (app.workDays == null || app.workDays!.isEmpty) {
          return true; // 매일 근무
        }

        final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
        final dayWeekday = weekdays[date.weekday - 1];

        return app.workDays!.contains(dayWeekday);
      }).toList();

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

      await showDialog(
        context: context,
        builder: (context) => AttendanceStatusDialog(
          date: _selectedDay!,
          businessIds: businessIds,
          initialBusinessId: currentBusinessId,
        ),
      );
    } catch (e) {
      print('❌ 사업장 조회 실패: $e');
      ToastHelper.showError('사업장 정보를 불러올 수 없습니다');
    }
  }
}