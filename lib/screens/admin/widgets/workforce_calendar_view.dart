import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/core/to_model.dart';
import '../../../models/core/application_model.dart';
import '../../../services/firestore_service.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../utils/format_helper.dart';
import '../dialogs/work_applicants_dialog.dart';
import '../../../utils/toast_helper.dart';

/// 인력 관리 - 캘린더 뷰
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
    _loadData();
  }

  /// 데이터 로드
  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        Future(() async {
          // 진행중 + 마감 TO 모두 가져오기
          final active = await _firestoreService.getActiveTOsByBusinessId(widget.businessId);
          final closed = await _firestoreService.getClosedTOsByBusinessId(widget.businessId);
          return [...active, ...closed];
        }),
        _firestoreService.getLongTermApplicationsByBusiness(widget.businessId),
      ]);

      final toList = results[0] as List<TOModel>;
      final apps = results[1] as List<ApplicationModel>;

      // 그룹 TO 시간 범위 계산
      final groupTOs = toList.where((to) => to.isGrouped && to.groupId != null).toList();
      if (groupTOs.isNotEmpty) {
        await Future.wait(
          groupTOs.map((to) => _calculateTimeRange(to)),
        );
      }

      setState(() {
        _allTOs = toList;
        _longTermApplications = apps.where((app) => app.status == 'CONFIRMED').toList();
        _isLoading = false;
      });

      print('✅ 캘린더 데이터 로드: TO ${toList.length}개, 장기 ${apps.length}개');
    } catch (e) {
      print('❌ 데이터 로드 실패: $e');
      setState(() => _isLoading = false);
    }
  }

  /// 그룹 TO 시간 범위 계산
  Future<void> _calculateTimeRange(TOModel to) async {
    try {
      final timeRange = await _firestoreService.calculateGroupTimeRange(to.groupId!);
      if (timeRange.isNotEmpty) {
        to.setTimeRange(timeRange['minStart']!, timeRange['maxEnd']!);
      }
    } catch (e) {
      print('시간 범위 계산 실패: $e');
    }
  }

  /// 특정 날짜의 TO 목록
  List<TOModel> _getTOsForDay(DateTime day) {
    return _allTOs.where((to) {
      if (to.isLongTerm) {
        // 장기 TO: startDate ~ endDate 범위 확인
        if (to.startDate == null || to.endDate == null) return false;
        final isInRange = !day.isBefore(to.startDate!) && !day.isAfter(to.endDate!);
        if (!isInRange) return false;

        // workDays 확인
        if (to.workDays != null && to.workDays!.isNotEmpty) {
          final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
          final dayOfWeek = weekdays[day.weekday - 1];
          return to.workDays!.contains(dayOfWeek);
        }
        return true;
      } else {
        // 단기 TO: 날짜 일치
        return DateUtils.isSameDay(to.date, day);
      }
    }).toList();
  }

  /// 장기 근무자가 해당 날짜에 근무하는지
  bool _isWorkingOnDate(ApplicationModel app, DateTime date) {
    if (app.workDays == null || app.workDays!.isEmpty) return true;
    
    final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final dayOfWeek = weekdays[date.weekday - 1];
    return app.workDays!.contains(dayOfWeek);
  }

  /// 캘린더 이벤트 마커
  List<dynamic> _getEventsForDay(DateTime day) {
    final events = <String>[];
    
    // 단기 TO 확인
    final hasSingleTO = _allTOs.any((to) => 
      !to.isLongTerm && DateUtils.isSameDay(to.date, day)
    );
    
    // 장기 TO 확인
    final hasLongTO = _getTOsForDay(day).any((to) => to.isLongTerm);
    
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

        // 선택한 날짜 표시
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
      
      // 높이 조정
      daysOfWeekHeight: 40,
      rowHeight: 48,

      selectedDayPredicate: (day) => DateUtils.isSameDay(_selectedDay, day),
      
      onDaySelected: (selectedDay, focusedDay) {
        setState(() {
          _selectedDay = selectedDay;
          _focusedDay = focusedDay;
        });
      },

      onPageChanged: (focusedDay) {
        _focusedDay = focusedDay;
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
          color: Colors.blue[300],
          shape: BoxShape.circle,
        ),
        selectedDecoration: BoxDecoration(
          color: Colors.blue[700],
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
    Color statusColor = Colors.blue;

    if (isPast) {
      statusText = '과거 기록';
      statusColor = Colors.grey;
    } else if (isToday) {
      statusText = '오늘';
      statusColor = Colors.green;
    } else {
      statusText = '예정';
      statusColor = Colors.blue;
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
          // 단기 TO 섹션
          if (dayTOs.where((to) => !to.isLongTerm).isNotEmpty) ...[
            _buildSectionHeader('📦 단기 TO', dayTOs.where((to) => !to.isLongTerm).length),
            const SizedBox(height: 12),
            ...dayTOs.where((to) => !to.isLongTerm).map((to) => _buildTOCard(to)),
            const SizedBox(height: 24),
          ],

          // 장기 TO 섹션
          if (dayTOs.where((to) => to.isLongTerm).isNotEmpty) ...[
            _buildSectionHeader('⭐ 장기 TO', dayTOs.where((to) => to.isLongTerm).length),
            const SizedBox(height: 12),
            ...dayTOs.where((to) => to.isLongTerm).map((to) => _buildTOCard(to)),
            const SizedBox(height: 24),
          ],

          // 고정 근무자 섹션
          if (longTermWorkers.isNotEmpty) ...[
            _buildSectionHeader('👷 고정 근무 출근 예정', longTermWorkers.length),
            const SizedBox(height: 12),
            _buildLongTermWorkersCard(longTermWorkers),
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
            fontSize: 16,
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

  /// TO 카드
  Widget _buildTOCard(TOModel to) {
    final fillRate = to.totalRequired > 0
        ? (to.totalConfirmed / to.totalRequired * 100).toInt()
        : 0;

    Color statusColor;
    if (fillRate >= 100) {
      statusColor = Colors.green;
    } else if (fillRate >= 50) {
      statusColor = Colors.orange;
    } else {
      statusColor = Colors.red;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: InkWell(
        onTap: () => _showApplicantsDialog(to),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 제목
              Text(
                to.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
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
                    '${to.totalConfirmed}/${to.totalRequired}명',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: to.totalRequired > 0
                            ? to.totalConfirmed / to.totalRequired
                            : 0,
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                        minHeight: 8,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 고정 근무자 카드
  Widget _buildLongTermWorkersCard(List<ApplicationModel> workers) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '총 ${workers.length}명 출근 예정',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<String>>(
              future: _getUserNames(workers),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const CircularProgressIndicator();
                }
                
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: snapshot.data!.map((name) {
                    return Chip(
                      label: Text(name),
                      backgroundColor: Colors.blue[50],
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 사용자 이름 조회
  Future<List<String>> _getUserNames(List<ApplicationModel> apps) async {
    final names = <String>[];
    
    for (var app in apps) {
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(app.uid)
            .get();
        
        if (userDoc.exists) {
          names.add(userDoc.data()?['name'] ?? '이름없음');
        } else {
          names.add('이름없음');
        }
      } catch (e) {
        names.add('이름없음');
      }
    }
    
    return names;
  }

  /// 지원자 관리 다이얼로그
  void _showApplicantsDialog(TOModel to) {
    // TODO: TO 전체 지원자 관리 기능 구현 필요
    // 현재는 업무별로만 관리 가능
    ToastHelper.showInfo('TO를 클릭하여 업무별 지원자를 관리하세요');
  }
}