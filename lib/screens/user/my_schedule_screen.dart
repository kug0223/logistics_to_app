import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/core/application_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../utils/toast_helper.dart';
import '../../utils/calendar_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/calendar/schedule_calendar.dart';
import '../../widgets/user/cards/monthly_stats_card.dart';
import '../../widgets/calendar/schedule_card.dart';
import '../../widgets/dialogs/long_term_work_management_dialog.dart';
import 'dialogs/my_requests_dialog.dart';
import '../../models/core/id_card_access_request_model.dart';
import '../../models/core/attendance_model.dart';

/// ✨ 내 근무 스케줄 화면 (홈 화면 디자인 통일)
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

  // 🔔 알림 관련
  List<IdCardAccessRequestModel> _pendingIdCardRequests = [];
  List<ApplicationModel> _pendingTerminations = [];
  
  // 📊 출근 기록 (통계용)
  List<AttendanceModel> _attendances = [];
  
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
      
      // 병렬 로딩
      final results = await Future.wait([
        _firestoreService.getMyApplications(uid),
        _firestoreService.getPendingIdCardRequestsForUser(uid),
        _firestoreService.getMyTerminationRequests(uid),
        _firestoreService.getMyMonthlyAttendances(
          userId: uid,
          year: _focusedDay.year,
          month: _focusedDay.month,
        ),
      ]);
      
      final applications = results[0] as List<ApplicationModel>;
      final idCardRequests = results[1] as List<IdCardAccessRequestModel>;
      final terminations = results[2] as List<ApplicationModel>;
      final attendances = results[3] as List<AttendanceModel>;
      
      setState(() {
        _applications = applications;
        _pendingIdCardRequests = idCardRequests;
        _pendingTerminations = terminations;
        _attendances = attendances;
        _isLoading = false;
      });
      
      print('✅ 지원 내역 로드 완료: ${applications.length}개');
      print('🔔 신분증 요청: ${idCardRequests.length}건, 계약해지: ${terminations.length}건');
      
      print('✅ 지원 내역 로드 완료: ${applications.length}개');
    } catch (e) {
      print('❌ 지원 내역 로드 실패: $e');
      setState(() => _isLoading = false);
      ToastHelper.showError('데이터를 불러오는데 실패했습니다.');
    }
  }
  /// 월별 출근 기록만 로드 (월 변경 시)
  Future<void> _loadMonthlyAttendances(DateTime focusedDay) async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final uid = userProvider.currentUser?.uid;
    
    if (uid == null) return;
    
    try {
      final attendances = await _firestoreService.getMyMonthlyAttendances(
        userId: uid,
        year: focusedDay.year,
        month: focusedDay.month,
      );
      
      if (mounted) {
        setState(() {
          _attendances = attendances;
        });
      }
    } catch (e) {
      print('❌ 월별 출근 기록 로드 실패: $e');
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      // AppBar 제거 - 전체 화면 사용
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.primaryColor,
              theme.primaryColor.withOpacity(0.85),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ✨ 상단 헤더 영역 (그라데이션)
              _buildHeader(theme),
              
              // ✨ 하단 컨텐츠 영역 (둥근 흰색 카드)
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(32),
                      topRight: Radius.circular(32),
                    ),
                  ),
                  child: _isLoading
                      ? const LoadingWidget(message: '일정을 불러오는 중...')
                      : _buildContent(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// ✨ 상단 헤더 (그라데이션 영역)
  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 첫 번째 줄: 뒤로가기 + 제목 + 액션들
          Row(
            children: [
              // 뒤로가기 버튼
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              
              // 제목
              Expanded(
                child: Text(
                  '내 스케줄',
                  style: ResponsiveHelper.titleStyle(context).copyWith(
                    color: Colors.white,
                    fontSize: ResponsiveHelper.titleStyle(context).fontSize! * 1.3,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              
              // 알림 아이콘 (배지 포함)
              FutureBuilder<int>(
                future: _getPendingRequestCount(),
                builder: (context, snapshot) {
                  final count = snapshot.data ?? 0;
                  return Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.notifications_outlined, color: Colors.white),
                          onPressed: _showMyRequestsDialog,
                          tooltip: '내 알림',
                        ),
                      ),
                      if (count > 0)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 4)),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            constraints: BoxConstraints(
                              minWidth: ResponsiveHelper.spacing(context, 18),
                              minHeight: ResponsiveHelper.spacing(context, 18),
                            ),
                            child: Text(
                              '$count',
                              style: ResponsiveHelper.tinyStyle(
                                context,
                                color: Colors.white,
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
              
              // 고정근무 관리
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.work_outline, color: Colors.white),
                  onPressed: _showLongTermWorkManagement,
                  tooltip: '고정근무 관리',
                ),
              ),
              
              // 필터 버튼
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: PopupMenuButton<String>(
                  icon: const Icon(Icons.filter_list, color: Colors.white),
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
                            color: _selectedFilter == 'ALL' ? theme.primaryColor : Colors.grey,
                          ),
                          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
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
                          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
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
                          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                          const Text('대기만 보기'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              // 새로고침
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  onPressed: _loadApplications,
                  tooltip: '새로고침',
                ),
              ),
            ],
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          
          // 두 번째 줄: 현재 월 표시
          Text(
            DateFormat('yyyy년 M월', 'ko_KR').format(_focusedDay),
            style: ResponsiveHelper.bodyStyle(
              context,
              color: Colors.white.withOpacity(0.9),
            ),
          ),
        ],
      ),
    );
  }

  /// ✨ 컨텐츠 영역 (스크롤 가능)
  Widget _buildContent() {
    return CustomScrollView(
      slivers: [
        // 캘린더
        SliverToBoxAdapter(
          child: Container(
            margin: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
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
                  // 월이 바뀌면 해당 월의 출근 기록 다시 로드
                  _loadMonthlyAttendances(focusedDay);
                },
              ),
            ),
          ),
        ),
        
        // 월별 통계 카드
        SliverToBoxAdapter(
          child: Container(
            margin: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 16),
              vertical: ResponsiveHelper.spacing(context, 8),
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: MonthlyStatsCard(
              applications: _applications,
              attendances: _attendances,
              focusedDay: _focusedDay,
            ),
          ),
        ),
        
        // 범례 (Legend)
        SliverToBoxAdapter(
          child: Container(
            margin: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 16),
              vertical: ResponsiveHelper.spacing(context, 8),
            ),
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isSmall = constraints.maxWidth < 400;
                final isVerySmall = constraints.maxWidth < 350;
                
                return Wrap(
                  alignment: WrapAlignment.center,
                  spacing: isVerySmall ? 6 : (isSmall ? 8 : 12),
                  runSpacing: 4,
                  children: [
                    _buildLegendItem(Colors.green[600]!, '단기 확정', isLongTerm: false, isSmall: isVerySmall),
                    _buildLegendItem(Colors.green[400]!, '고정 확정', isLongTerm: true, isSmall: isVerySmall),
                    _buildLegendItem(Colors.grey[400]!, '휴무일', isLongTerm: true, isSmall: isVerySmall),
                    _buildLegendItem(Colors.orange[600]!, '단기 대기', isLongTerm: false, isSmall: isVerySmall),
                    _buildLegendItem(Colors.orange[400]!, '고정 대기', isLongTerm: true, isSmall: isVerySmall),
                  ],
                );
              },
            ),
          ),
        ),
        
        // 선택한 날짜 헤더
        if (_selectedDay != null)
          SliverToBoxAdapter(
            child: Container(
              margin: EdgeInsets.only(
                left: ResponsiveHelper.spacing(context, 16),
                right: ResponsiveHelper.spacing(context, 16),
                top: ResponsiveHelper.spacing(context, 8),
              ),
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).primaryColor.withOpacity(0.1),
                    Theme.of(context).primaryColor.withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.event,
                    color: Theme.of(context).primaryColor,
                    size: ResponsiveHelper.iconSize(context, 20),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  Text(
                    DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(_selectedDay!),
                    style: ResponsiveHelper.subtitleStyle(
                      context,
                      color: Theme.of(context).primaryColor,
                    ).copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        
        // 일정 리스트
        _buildSliverScheduleList(),
        
        // 하단 여백
        SliverToBoxAdapter(
          child: SizedBox(height: ResponsiveHelper.spacing(context, 16)),
        ),
      ],
    );
  }

  /// Sliver 일정 리스트
  Widget _buildSliverScheduleList() {
    if (_selectedDay == null) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 32)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.touch_app,
                  size: ResponsiveHelper.iconSize(context, 64),
                  color: Colors.grey[400],
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                Text(
                  '날짜를 선택해주세요',
                  style: ResponsiveHelper.subtitleStyle(
                    context,
                    color: Colors.grey[700],
                  ).copyWith(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                Text(
                  '캘린더에서 날짜를 클릭하면\n일정을 확인할 수 있습니다',
                  style: ResponsiveHelper.bodyStyle(
                    context,
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
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 32)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.event_busy,
                  size: ResponsiveHelper.iconSize(context, 64),
                  color: Colors.grey[400],
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                Text(
                  '이 날짜에는 일정이 없습니다',
                  style: ResponsiveHelper.subtitleStyle(
                    context,
                    color: Colors.grey[700],
                  ).copyWith(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                Text(
                  '다른 날짜를 선택해보세요',
                  style: ResponsiveHelper.bodyStyle(
                    context,
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
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            return ScheduleCard(
              application: events[index],
              onChanged: _loadApplications,
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
          style: TextStyle(
            fontSize: isSmall ? 9 : 11,
            color: Colors.grey[700],
          ),
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

  /// 대기중인 요청 개수 조회
  /// 스케줄 변경 요청 + 신분증 요청 + 계약해지 요청
  Future<int> _getPendingRequestCount() async {
    final userProvider = context.read<UserProvider>();
    final uid = userProvider.currentUser?.uid;
    
    if (uid == null) return 0;
    
    try {
      final requests = await _firestoreService.getMyScheduleChangeRequests(uid);
      final scheduleRequests = requests.where((r) => 
        r.isPending && r.isAdminRequest
      ).length;
      
      // ✅ 신분증 요청 + 계약해지 요청도 포함
      final total = scheduleRequests + 
                    _pendingIdCardRequests.length + 
                    _pendingTerminations.length;
      
      return total;
    } catch (e) {
      print('❌ 대기중인 요청 개수 조회 실패: $e');
      return _pendingIdCardRequests.length + _pendingTerminations.length;
    }
  }

  /// 내 요청 목록 다이얼로그
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