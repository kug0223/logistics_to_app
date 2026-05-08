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
import '../../widgets/calendar/schedule_card.dart';
import '../../widgets/dialogs/long_term_work_management_dialog.dart';
import 'dialogs/my_requests_dialog.dart';
import '../../models/core/id_card_access_request_model.dart';
import '../../models/core/attendance_model.dart';
import 'all_to_list_screen.dart';
import '../../theme/app_colors.dart';

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

      if (!mounted) return;
      setState(() {
        _applications = applications;
        _pendingIdCardRequests = idCardRequests;
        _pendingTerminations = terminations;
        _attendances = attendances;
        _isLoading = false;
      });
      
      debugPrint('✅ 지원 내역 로드 완료: ${applications.length}개');
      debugPrint('🔔 신분증 요청: ${idCardRequests.length}건, 계약해지: ${terminations.length}건');
    } catch (e) {
      debugPrint('❌ 지원 내역 로드 실패: $e');
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
      debugPrint('❌ 월별 출근 기록 로드 실패: $e');
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
              theme.primaryColor.withValues(alpha: 0.85),
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
                    color: AppColors.grey50,
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
                          color: Colors.white.withValues(alpha: 0.2),
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
                  color: Colors.white.withValues(alpha: 0.2),
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
                  color: Colors.white.withValues(alpha: 0.2),
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
                  color: Colors.white.withValues(alpha: 0.2),
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
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }

  /// ✨ 컨텐츠 영역 (스크롤 가능)
  Widget _buildContent() {
    // 이번 달 통계 계산
    final thisMonth = CalendarHelper.getThisMonthApplications(_applications, _focusedDay);
    final confirmedCount = CalendarHelper.getConfirmedCount(thisMonth);
    final pendingCount = CalendarHelper.getPendingCount(thisMonth);
    final totalIncome = CalendarHelper.getTotalIncome(thisMonth);
    
    return CustomScrollView(
      slivers: [
        // 1. 캘린더
        SliverToBoxAdapter(
          child: Container(
            margin: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
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
                  _loadMonthlyAttendances(focusedDay);
                },
              ),
            ),
          ),
        ),
        
        // 2. 범례 (캘린더 바로 아래) - 간소화
        SliverToBoxAdapter(
          child: Container(
            margin: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 16),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 12),
              vertical: ResponsiveHelper.spacing(context, 8),
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildCompactLegendItem(AppColors.successMedium, '확정', false),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                _buildCompactLegendItem(AppColors.successFaded, '고정', true),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                _buildCompactLegendItem(AppColors.warningMedium, '대기', false),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                _buildCompactLegendItem(AppColors.grey400, '휴무', true),
              ],
            ),
          ),
        ),
        
        // 3. 통계 2줄 (일수 + 금액)
        SliverToBoxAdapter(
          child: Container(
            margin: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 16),
              vertical: ResponsiveHelper.spacing(context, 8),
            ),
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                // 첫째 줄: 대기 → 확정 → 실근무 (일수)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildCompactStatItem(
                      icon: Icons.schedule,
                      label: '대기',
                      value: '$pendingCount건',
                      color: Colors.orange,
                    ),
                    Container(width: 1, height: 24, color: AppColors.grey200),
                    _buildCompactStatItem(
                      icon: Icons.check_circle,
                      label: '확정',
                      value: '$confirmedCount일',
                      color: Colors.green,
                    ),
                    Container(width: 1, height: 24, color: AppColors.grey200),
                    _buildCompactStatItem(
                      icon: Icons.directions_run,
                      label: '실근무',
                      value: '${CalendarHelper.getActualWorkDays(_attendances, _focusedDay)}일',
                      color: Colors.teal,
                    ),
                  ],
                ),
                // 구분선
                Padding(
                  padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 8)),
                  child: Divider(height: 1, color: AppColors.grey200),
                ),
                // 둘째 줄: 예상수입 → 확정수입 (금액)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildCompactStatItem(
                      icon: Icons.payments,
                      label: '예상수입',
                      value: '${NumberFormat('#,###').format(totalIncome)}원',
                      color: Colors.blue,
                    ),
                    Container(width: 1, height: 24, color: AppColors.grey200),
                    _buildCompactStatItem(
                      icon: Icons.paid,
                      label: '확정수입',
                      value: '${NumberFormat('#,###').format(CalendarHelper.getConfirmedIncome(_attendances, _focusedDay))}원',
                      color: Colors.green,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        
        // 4. 선택한 날짜 헤더
        if (_selectedDay != null)
          SliverToBoxAdapter(
            child: Container(
              margin: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 16),
                vertical: ResponsiveHelper.spacing(context, 4),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 12),
                vertical: ResponsiveHelper.spacing(context, 10),
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).primaryColor.withValues(alpha: 0.1),
                    Theme.of(context).primaryColor.withValues(alpha: 0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.event,
                    color: Theme.of(context).primaryColor,
                    size: ResponsiveHelper.iconSize(context, 18),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  Text(
                    DateFormat('M월 d일 (E)', 'ko_KR').format(_selectedDay!),
                    style: ResponsiveHelper.bodyStyle(
                      context,
                      color: Theme.of(context).primaryColor,
                    ).copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        
        // 5. 일정 리스트
        _buildSliverScheduleList(),
        
        // 하단 여백
        SliverToBoxAdapter(
          child: SizedBox(height: ResponsiveHelper.spacing(context, 16)),
        ),
      ],
    );
  }
  
  /// 컴팩트 범례 아이템
  Widget _buildCompactLegendItem(Color color, String label, bool isLongTerm) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isLongTerm)
          Icon(Icons.star, size: 10, color: color)
        else
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
        SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.grey600,
          ),
        ),
      ],
    );
  }
  
  /// 컴팩트 통계 아이템
  Widget _buildCompactStatItem({
    required IconData icon,
    required String label,
    required String value,
    required MaterialColor color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color[600]),
        SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: AppColors.grey500,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: color[700],
              ),
            ),
          ],
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
                  color: AppColors.grey400,
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                Text(
                  '날짜를 선택해주세요',
                  style: ResponsiveHelper.subtitleStyle(
                    context,
                    color: AppColors.grey700,
                  ).copyWith(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                Text(
                  '캘린더에서 날짜를 클릭하면\n일정을 확인할 수 있습니다',
                  style: ResponsiveHelper.bodyStyle(
                    context,
                    color: AppColors.grey500,
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
      // 오늘 이후인지 확인
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final selectedDayOnly = DateTime(_selectedDay!.year, _selectedDay!.month, _selectedDay!.day);
      final isFutureOrToday = !selectedDayOnly.isBefore(today);
      
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
                  isFutureOrToday ? Icons.work_outline : Icons.event_busy,
                  size: ResponsiveHelper.iconSize(context, 64),
                  color: isFutureOrToday 
                      ? Theme.of(context).primaryColor.withValues(alpha: 0.5)
                      : AppColors.grey400,
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                Text(
                  isFutureOrToday 
                      ? '이 날짜에 등록된 일정이 없습니다'
                      : '기록이 없습니다',
                  style: ResponsiveHelper.subtitleStyle(
                    context,
                    color: AppColors.grey700,
                  ).copyWith(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                Text(
                  isFutureOrToday 
                      ? '새로운 공고에 지원해보세요!'
                      : '과거 날짜입니다',
                  style: ResponsiveHelper.bodyStyle(
                    context,
                    color: AppColors.grey500,
                  ),
                  textAlign: TextAlign.center,
                ),
                // 미래/오늘이면 지원 버튼 표시
                if (isFutureOrToday) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AllTOListScreen(),
                        ),
                      );
                    },
                    icon: Icon(Icons.search, size: ResponsiveHelper.iconSize(context, 18)),
                    label: Text(
                      '공고 보러가기',
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 24),
                        vertical: ResponsiveHelper.spacing(context, 12),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
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
            final app = events[index];
            // 해당 application의 attendance 찾기
            final attendance = _attendances.firstWhere(
              (att) => att.applicationId == app.id && 
                       _selectedDay != null &&
                       att.workDate.year == _selectedDay!.year &&
                       att.workDate.month == _selectedDay!.month &&
                       att.workDate.day == _selectedDay!.day,
              orElse: () => AttendanceModel(
                id: '',
                applicationId: '',
                userId: '',
                businessId: '',
                businessName: '',
                workDate: DateTime.now(),
                workType: '',
                status: 'absent',
                createdAt: DateTime.now(),
              ),
            );
            
            return ScheduleCard(
              application: app,
              attendance: attendance.id.isNotEmpty ? attendance : null,
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
            color: AppColors.grey700,
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
      debugPrint('❌ 대기중인 요청 개수 조회 실패: $e');
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
