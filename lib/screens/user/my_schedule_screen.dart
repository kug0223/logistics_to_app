import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/core/application_model.dart';
import '../../models/core/schedule_change_request_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../utils/toast_helper.dart';
import '../../utils/calendar_helper.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/calendar/schedule_calendar.dart';
import '../../widgets/calendar/monthly_stats_card.dart';
import '../../widgets/calendar/schedule_card.dart';
import '../../widgets/dialogs/long_term_work_management_dialog.dart';
import 'dialogs/my_requests_dialog.dart';



/// 내 근무 스케줄 화면 (캘린더 뷰)
class MyScheduleScreen extends StatefulWidget {
  const MyScheduleScreen({super.key});

  @override
  State<MyScheduleScreen> createState() => _MyScheduleScreenState();
}

class _MyScheduleScreenState extends State<MyScheduleScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  
  // 캘린더 상태
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  
  // 데이터
  List<ApplicationModel> _applications = [];
  bool _isLoading = true;
  String _selectedFilter = 'ALL'; // ALL, CONFIRMED, PENDING
  // ⭐ 추가
  int _pendingRequestCount = 0;
  
  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _loadApplications();
  }
  
  /// 지원 내역 로드
  Future<void> _loadApplications() async {
    setState(() => _isLoading = true);
    
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;
      
      if (uid == null) {
        ToastHelper.showError('로그인이 필요합니다.');
        return;
      }
      
      final applications = await _firestoreService.getMyApplications(uid);
      
      setState(() {
        _applications = applications;
        _isLoading = false;
      });
      
      print('✅ 지원 내역 로드 완료: ${applications.length}개');
    } catch (e) {
      print('❌ 지원 내역 로드 실패: $e');
      setState(() => _isLoading = false);
      ToastHelper.showError('데이터를 불러오는데 실패했습니다.');
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('내 스케줄'),
        actions: [
        // 알림 아이콘
        FutureBuilder<int>(
          future: _getPendingRequestCount(),
          builder: (context, snapshot) {
            final count = snapshot.data ?? 0;
            return Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications),
                  onPressed: _showMyRequestsDialog,
                  tooltip: '내 알림',
                ),
                if (count > 0)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        _buildFilterButton(),
        IconButton(
          icon: const Icon(Icons.work),
          onPressed: _showLongTermWorkManagement,
          tooltip: '고정근무 관리',
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _loadApplications,
        ),
      ],
      ),
      body: _isLoading
          ? const LoadingWidget(message: '일정을 불러오는 중...')
          : CustomScrollView(
              slivers: [
                // 캘린더
                SliverToBoxAdapter(
                  child: ScheduleCalendar(
                    focusedDay: _focusedDay,
                    selectedDay: _selectedDay,
                    applications: _applications,
                    selectedFilter: _selectedFilter,
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
                    
                  ),
                ),
          
                
                // Divider
                const SliverToBoxAdapter(
                  child: Divider(height: 1),
                ),
                
                // 월별 통계
                SliverToBoxAdapter(
                  child: MonthlyStatsCard(
                    applications: _applications,
                    focusedDay: _focusedDay,
                  ),
                ),
                // 🔥 Legend (범례) 추가 - 반응형
                SliverToBoxAdapter(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isSmall = constraints.maxWidth < 400;
                      final isVerySmall = constraints.maxWidth < 350;
                      
                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                        color: Colors.grey[50],
                        child: Wrap(  // ⭐ Row → Wrap 변경 (자동 줄바꿈)
                          alignment: WrapAlignment.center,
                          spacing: isVerySmall ? 6 : (isSmall ? 8 : 12),
                          runSpacing: 4,  // 줄바꿈 시 간격
                          children: [
                            _buildLegendItem(Colors.green[600]!, '단기 확정', isLongTerm: false, isSmall: isVerySmall),
                            _buildLegendItem(Colors.green[400]!, '고정 확정', isLongTerm: true, isSmall: isVerySmall),
                            _buildLegendItem(Colors.grey[400]!, '휴무일', isLongTerm: true, isSmall: isVerySmall),
                            _buildLegendItem(Colors.orange[600]!, '단기 대기', isLongTerm: false, isSmall: isVerySmall),
                            _buildLegendItem(Colors.orange[400]!, '고정 대기', isLongTerm: true, isSmall: isVerySmall),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                
                // Divider
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
                
                // Divider
                const SliverToBoxAdapter(
                  child: Divider(height: 1),
                ),
                
                // 일정 리스트
                _buildSliverScheduleList(),
              ],
            ),
    );
  }

  /// Sliver 일정 리스트
  Widget _buildSliverScheduleList() {
    if (_selectedDay == null) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.touch_app, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  '날짜를 선택해주세요',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  '캘린더에서 날짜를 클릭하면\n일정을 확인할 수 있습니다',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }
    
    final events = CalendarHelper.getEventsForDay(
      _selectedDay!,
      _applications,
      _selectedFilter,
    );
    
    if (events.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.event_busy, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  '이 날짜에는 일정이 없습니다',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  '다른 날짜를 선택해보세요',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }
    
    // 상태별 정렬
    events.sort((a, b) {
      final aOrder = _getStatusOrder(a.status);
      final bOrder = _getStatusOrder(b.status);
      return aOrder.compareTo(bOrder);
    });
    
    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            return ScheduleCard(
              application: events[index],
              onChanged: _loadApplications,  // ⭐ 추가!
              selectedDay: _selectedDay,
            );
          },
          childCount: events.length,
        ),
      ),
    );
  }

  /// 상태별 정렬 순서
  int _getStatusOrder(String status) {
    switch (status) {
      case 'CONFIRMED':
        return 1;
      case 'PENDING':
        return 2;
      case 'REJECTED':
        return 3;
      case 'CANCELED':
        return 4;
      case 'AUTO_CANCELED':
        return 5;
      default:
        return 6;
    }
  }
  
  /// 필터 버튼
  Widget _buildFilterButton() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.filter_list),
      onSelected: (value) {
        setState(() {
          _selectedFilter = value;
        });
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'ALL',
          child: Row(
            children: [
              Icon(
                Icons.list_alt,
                color: _selectedFilter == 'ALL' ? Colors.blue : Colors.grey,
              ),
              const SizedBox(width: 8),
              const Text('전체 보기'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'CONFIRMED',
          child: Row(
            children: [
              Icon(
                Icons.check_circle,
                color: _selectedFilter == 'CONFIRMED' ? Colors.green : Colors.grey,
              ),
              const SizedBox(width: 8),
              const Text('확정만 보기'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'PENDING',
          child: Row(
            children: [
              Icon(
                Icons.schedule,
                color: _selectedFilter == 'PENDING' ? Colors.orange : Colors.grey,
              ),
              const SizedBox(width: 8),
              const Text('대기만 보기'),
            ],
          ),
        ),
      ],
    );
  }
  /// Legend 아이템
  Widget _buildLegendItem(Color color, String label, {required bool isLongTerm, bool isSmall = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isLongTerm)
          Icon(Icons.star, size: isSmall ? 6 : 8, color: color)
        else
          Container(
            width: isSmall ? 5 : 7,
            height: isSmall ? 5 : 7,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
        SizedBox(width: isSmall ? 3 : 4),
        Text(
          label,
          style: TextStyle(fontSize: isSmall ? 9 : 11),
        ),
      ],
    );
  }
  /// 고정근무 관리 다이얼로그 표시
  void _showLongTermWorkManagement() {
    showDialog(
      context: context,
      builder: (context) => LongTermWorkManagementDialog(
        applications: _applications,
        onChanged: () {
          _loadApplications();
        },
      ),
    );
  }
  /// ⭐ 대기중인 요청 개수 조회
  Future<int> _getPendingRequestCount() async {
    final userProvider = context.read<UserProvider>();
    final uid = userProvider.currentUser?.uid;
    
    if (uid == null) return 0;
    
    try {
      final requests = await _firestoreService.getMyScheduleChangeRequests(uid);
      final pending = requests.where((r) => 
        r.isPending && r.isAdminRequest
      ).length;
      
      return pending;
    } catch (e) {
      print('❌ 대기중인 요청 개수 조회 실패: $e');
      return 0;
    }
  }

  /// ⭐ 내 요청 목록 다이얼로그
  Future<void> _showMyRequestsDialog() async {
    final userProvider = context.read<UserProvider>();
    final uid = userProvider.currentUser?.uid;
    
    if (uid == null) {
      ToastHelper.showError('사용자 정보를 찾을 수 없습니다');
      return;
    }
    
    showDialog(
      context: context,
      builder: (context) => MyRequestsDialog(
        applicantUid: uid,
        onChanged: () {
          setState(() {});
          _loadApplications();
        },
      ),
    );
  }
}