import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import '../../../models/core/to_model.dart';
import '../../../models/core/application_model.dart';
import '../../../services/firestore_service.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../utils/format_helper.dart';

/// 캘린더 뷰 - 전체 TO 이력 표시
class WorkforceCalendarView extends StatefulWidget {
  final String businessId;

  const WorkforceCalendarView({
    super.key,
    required this.businessId,
  });

  @override
  State<WorkforceCalendarView> createState() => _WorkforceCalendarViewState();
}

class _WorkforceCalendarViewState extends State<WorkforceCalendarView> {
  final FirestoreService _firestoreService = FirestoreService();
  
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  
  List<TOModel> _allTOs = [];
  List<ApplicationModel> _longTermApplications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _loadAllTOs();
  }

  /// 모든 TO 로드 (과거 포함)
  Future<void> _loadAllTOs() async {
    setState(() => _isLoading = true);

    try {
      // 활성 TO 조회
      final activeTOs = await _firestoreService.getActiveTOsByBusinessId(
        widget.businessId,
      );
      
      // 마감된 TO 조회
      final closedTOs = await _firestoreService.getClosedTOsByBusinessId(
        widget.businessId,
      );

      // 고정 근무자 조회
      final longTermApps = await _firestoreService
          .getLongTermApplicationsByBusiness(widget.businessId);

      setState(() {
        _allTOs = [...activeTOs, ...closedTOs];
        _longTermApplications = longTermApps;
        _isLoading = false;
      });

      print('✅ 전체 TO: ${_allTOs.length}개, 고정근무: ${longTermApps.length}명');
    } catch (e) {
      print('❌ TO 로드 실패: $e');
      setState(() => _isLoading = false);
    }
  }

  /// 특정 날짜의 TO 가져오기
  List<TOModel> _getTOsForDay(DateTime day) {
    return _allTOs.where((to) {
      return to.date.year == day.year &&
          to.date.month == day.month &&
          to.date.day == day.day;
    }).toList();
  }

  /// 특정 날짜의 고정 근무자 수
  int _getLongTermWorkersForDay(DateTime day) {
    return _longTermApplications.where((app) {
      if (app.status != 'CONFIRMED') return false;
      return _isWorkingOnDate(app, day);
    }).length;
  }

  /// 장기 근무가 특정 날짜에 근무하는지 확인
  bool _isWorkingOnDate(ApplicationModel app, DateTime targetDate) {
    if (!app.isLongTermApplication) {
      return _isSameDay(app.workDate, targetDate);
    }

    final endDate = app.actualResignDate ?? app.workEndDate;
    if (endDate == null) return false;

    final isInRange = !targetDate.isBefore(app.workDate) &&
        !targetDate.isAfter(endDate);

    if (!isInRange) return false;

    if (app.workDays == null || app.workDays!.isEmpty) {
      return true;
    }

    final targetDayKorean = _getKoreanDayOfWeek(targetDate);
    return app.workDays!.contains(targetDayKorean);
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  String _getKoreanDayOfWeek(DateTime date) {
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    return days[date.weekday - 1];
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
        
        // 선택한 날짜 표시
        if (_selectedDay != null)
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              color: Colors.blue[50],
              child: Row(
                children: [
                  Icon(Icons.event, color: Colors.blue[700], size: 20),
                  const SizedBox(width: 8),
                  Text(
                    DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(_selectedDay!),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[900],
                    ),
                  ),
                ],
              ),
            ),
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
      
      // 🔥 높이 조정 추가
      daysOfWeekHeight: 40,
      rowHeight: 48,
      
      headerStyle: HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
        titleTextFormatter: (date, locale) {
          return DateFormat.yMMMM('ko_KR').format(date);
        },
        titleTextStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      
      selectedDayPredicate: (day) {
        return isSameDay(_selectedDay, day);
      },
      
      onDaySelected: (selectedDay, focusedDay) {
        setState(() {
          _selectedDay = selectedDay;
          _focusedDay = focusedDay;
        });
      },
      
      onPageChanged: (focusedDay) {
        setState(() {
          _focusedDay = focusedDay;
        });
      },
      
      // 날짜별 마커
      calendarBuilders: CalendarBuilders(
        markerBuilder: (context, date, events) {
          final tos = _getTOsForDay(date);
          final longTermCount = _getLongTermWorkersForDay(date);
          
          if (tos.isEmpty && longTermCount == 0) {
            return const SizedBox.shrink();
          }

          int totalRequired = tos.fold(0, (sum, to) => sum + to.totalRequired);
          totalRequired += longTermCount;

          // 지난 날짜 여부
          final today = DateTime.now();
          final isPast = date.isBefore(DateTime(today.year, today.month, today.day));

          return Positioned(
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: isPast ? Colors.grey[400] : Colors.blue[600],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$totalRequired',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        },
      ),
      
      calendarStyle: CalendarStyle(
        markersMaxCount: 1,
        todayDecoration: BoxDecoration(
          color: Colors.blue[300],
          shape: BoxShape.circle,
        ),
        selectedDecoration: BoxDecoration(
          color: Colors.blue[700],
          shape: BoxShape.circle,
        ),
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

    final dayTOs = _getTOsForDay(_selectedDay!);
    final longTermWorkers = _longTermApplications.where((app) {
      return app.status == 'CONFIRMED' && _isWorkingOnDate(app, _selectedDay!);
    }).toList();

    if (dayTOs.isEmpty && longTermWorkers.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.event_busy, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                '이 날짜에는 TO가 없습니다',
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
        delegate: SliverChildListDelegate([
          // 고정 근무자 섹션
          if (longTermWorkers.isNotEmpty) ...[
            _buildSectionHeader('👷 고정 근무 출근 예정', longTermWorkers.length),
            const SizedBox(height: 12),
            _buildLongTermWorkersCard(longTermWorkers),
            const SizedBox(height: 24),
          ],

          // TO 섹션
          if (dayTOs.isNotEmpty) ...[
            _buildSectionHeader('📦 TO 목록', dayTOs.length),
            const SizedBox(height: 12),
            ...dayTOs.map((to) => _buildTOCard(to)),
          ],
        ]),
      ),
    );
  }

  /// 섹션 헤더
  Widget _buildSectionHeader(String title, int count) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.blue[100],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.blue[900],
            ),
          ),
        ),
      ],
    );
  }

  /// 고정 근무자 카드
  Widget _buildLongTermWorkersCard(List<ApplicationModel> workers) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.people, color: Colors.green[700], size: 20),
                const SizedBox(width: 8),
                Text(
                  '총 ${workers.length}명 출근',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: workers.take(10).map((app) {
                return Chip(
                  avatar: const Icon(Icons.person, size: 16),
                  label: Text(
                    '${app.selectedWorkType}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  backgroundColor: Colors.green[50],
                );
              }).toList(),
            ),
            if (workers.length > 10)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '외 ${workers.length - 10}명',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// TO 카드
  Widget _buildTOCard(TOModel to) {
    // 지난 TO 여부
    final today = DateTime.now();
    final isPast = to.date.isBefore(DateTime(today.year, today.month, today.day));
    
    // 마감 여부
    final isClosed = to.isManualClosed;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더
            Row(
              children: [
                Expanded(
                  child: Text(
                    to.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isPast ? Colors.grey[600] : Colors.black,
                    ),
                  ),
                ),
                if (to.groupId != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.blue[300]!),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.folder, size: 12, color: Colors.blue[700]),
                        const SizedBox(width: 4),
                        Text(
                          '그룹',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[900],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

           // 시간
            Row(
              children: [
                Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Text(
                  to.displayTimeRange.isNotEmpty 
                      ? to.displayTimeRange 
                      : '${to.startTime} ~ ${to.endTime}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 인원 현황
            Row(
              children: [
                Text(
                  '인원: ${to.totalConfirmed}/${to.totalRequired}명',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isPast ? Colors.grey[600] : Colors.blue[700],
                  ),
                ),
                const Spacer(),
                if (isClosed)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.red[300]!),
                    ),
                    child: Text(
                      '마감',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.red[900],
                      ),
                    ),
                  ),
                if (isPast && !isClosed)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '완료',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[700],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}