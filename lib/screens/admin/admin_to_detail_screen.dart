import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/to_model.dart';
import '../../models/application_model.dart';
import '../../models/work_detail_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../widgets/loading_widget.dart';
import '../../utils/toast_helper.dart';

/// 관리자 TO 상세 화면 (지원자 관리) - 신버전
class AdminTODetailScreen extends StatefulWidget {
  final TOModel to;

  const AdminTODetailScreen({
    Key? key,
    required this.to,
  }) : super(key: key);

  @override
  State<AdminTODetailScreen> createState() => _AdminTODetailScreenState();
}

class _AdminTODetailScreenState extends State<AdminTODetailScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  
  List<Map<String, dynamic>> _applicants = [];
  List<WorkDetailModel> _workDetails = []; // ✅ NEW
  bool _isLoading = true;

  // ✅ NEW Phase 2: 그룹 관련 상태 변수 추가 (여기에 추가!)
  List<TOModel> _groupTOs = []; // 같은 그룹의 다른 TO들
  int _groupTotalApplicants = 0; // 그룹 전체 지원자 수
  // ✅ NEW Phase 2.5: 하이브리드 지원자 표시
  List<Map<String, dynamic>> _groupApplicants = []; // 그룹 전체 지원자
  int _selectedTabIndex = 0; // 0: 이 TO, 1: 그룹 전체

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  /// ✅ MODIFIED Phase 2: 지원자 + WorkDetails + 그룹 정보 동시 로드
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 기본 데이터 로드 (지원자 + WorkDetails)
      final results = await Future.wait([
        _firestoreService.getApplicantsWithUserInfo(widget.to.id),
        _firestoreService.getWorkDetails(widget.to.id),
      ]);

      final applicants = results[0] as List<Map<String, dynamic>>;
      final workDetails = results[1] as List<WorkDetailModel>;

      // 그룹 정보가 있으면 추가 로드
      List<TOModel> groupTOs = [];
      int groupTotalApplicants = 0;
      List<Map<String, dynamic>> groupApplicants = []; // ✅ NEW

      if (widget.to.groupId != null) {
        // 같은 그룹의 TO들 조회
        groupTOs = await _firestoreService.getTOsByGroup(widget.to.groupId!);
        
        // ✅ NEW: 그룹 전체 지원자 상세 정보 조회
        final groupApplications = await _firestoreService.getApplicationsByGroup(widget.to.groupId!);
        groupTotalApplicants = groupApplications.length;
        
        // 각 지원자의 사용자 정보 + 지원한 TO 정보 가져오기
        for (var app in groupApplications) {
          final userDoc = await _firestoreService.getUser(app.uid);
          final toDoc = await _firestoreService.getTO(app.toId);
          
          if (userDoc != null && toDoc != null) {
            groupApplicants.add({
              'applicationId': app.id,
              'application': app,
              'userName': userDoc.name,
              'userEmail': userDoc.email,
              'userPhone': userDoc.phone ?? '',
              'toTitle': toDoc.title,
              'toDate': toDoc.date,
            });
          }
        }
        
        // 지원 시간 기준 정렬 (최신순)
        groupApplicants.sort((a, b) {
          final aApp = a['application'] as ApplicationModel;
          final bApp = b['application'] as ApplicationModel;
          return bApp.appliedAt.compareTo(aApp.appliedAt);
        });
        
        print('✅ 그룹 TO 개수: ${groupTOs.length}');
        print('✅ 그룹 전체 지원자: $groupTotalApplicants명');
      }

      setState(() {
        _applicants = applicants;
        _workDetails = workDetails;
        _groupTOs = groupTOs;
        _groupTotalApplicants = groupTotalApplicants;
        _groupApplicants = groupApplicants; // ✅ NEW
        _isLoading = false;
      });
    } catch (e) {
      print('❌ 데이터 로드 실패: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 지원자 승인
  Future<void> _confirmApplicant(String applicationId) async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final adminUID = userProvider.currentUser?.uid;

    if (adminUID == null) {
      ToastHelper.showError('관리자 정보를 찾을 수 없습니다.');
      return;
    }

    // 확인 다이얼로그
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('지원자 승인'),
        content: const Text('이 지원자를 승인하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('승인', style: TextStyle(color: Colors.green)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // 로딩 다이얼로그
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('승인 중...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final success = await _firestoreService.confirmApplicant(applicationId, adminUID);
      
      if (mounted) {
        Navigator.pop(context); // 로딩 다이얼로그 닫기
      }

      if (success) {
        _loadData(); // 목록 새로고침
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
      }
      print('❌ 승인 실패: $e');
    }
  }

  /// 지원자 거절
  Future<void> _rejectApplicant(String applicationId) async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final adminUID = userProvider.currentUser?.uid;

    if (adminUID == null) {
      ToastHelper.showError('관리자 정보를 찾을 수 없습니다.');
      return;
    }

    // 확인 다이얼로그
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('지원자 거절'),
        content: const Text('이 지원자를 거절하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('거절', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // 로딩 다이얼로그
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('거절 중...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final success = await _firestoreService.rejectApplicant(applicationId, adminUID);
      
      if (mounted) {
        Navigator.pop(context); // 로딩 다이얼로그 닫기
      }

      if (success) {
        _loadData(); // 목록 새로고침
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
      }
      print('❌ 거절 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: LoadingWidget(message: 'TO 정보를 불러오는 중...'),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('TO 상세'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          children: [
            // 헤더
            _buildHeader(),
            const SizedBox(height: 16),

            // WorkDetails 섹션
            _buildWorkDetailsSection(),
            const SizedBox(height: 16),

            // 그룹 TO 목록
            _buildGroupTOsSection(),
            const SizedBox(height: 16),

            // ✅ NEW Phase 2.5: 탭이 있는 지원자 섹션
            _buildApplicantsSection(),
            
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  /// ✅ NEW Phase 2.5: 탭이 있는 지원자 섹션
  Widget _buildApplicantsSection() {
    // 그룹이 없거나 TO가 1개만 있으면 기존 방식 (탭 없음)
    if (!widget.to.isGrouped || _groupTOs.length <= 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '📋 지원자 목록 (${_applicants.length}명)',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildApplicantsList(),
        ],
      );
    }

    // ✅ 그룹이 있고 TO가 2개 이상이면 탭 UI
    return Column(
      children: [
        // 탭 헤더
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              // "이 TO" 탭
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedTabIndex = 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _selectedTabIndex == 0 ? Colors.blue[700] : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '이 TO (${_applicants.length}명)',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _selectedTabIndex == 0 ? Colors.white : Colors.grey[700],
                      ),
                    ),
                  ),
                ),
              ),
              // "그룹 전체" 탭
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedTabIndex = 1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _selectedTabIndex == 1 ? Colors.blue[700] : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '그룹 전체 (${_groupApplicants.length}명)',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _selectedTabIndex == 1 ? Colors.white : Colors.grey[700],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 탭 내용
        if (_selectedTabIndex == 0)
          _buildApplicantsList()
        else
          _buildGroupApplicantsList(),
      ],
    );
  }

  /// 헤더 (TO 기본 정보)
  Widget _buildHeader() {
    final dateFormat = DateFormat('yyyy-MM-dd (E)', 'ko_KR');
    final weekdayMap = {
      'Mon': '월',
      'Tue': '화',
      'Wed': '수',
      'Thu': '목',
      'Fri': '금',
      'Sat': '토',
      'Sun': '일',
    };
    final koreanWeekday = weekdayMap[DateFormat('E').format(widget.to.date)] ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue[700]!, Colors.blue[500]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ NEW Phase 2: 그룹 정보 표시 (여기에 추가!)
          if (widget.to.isGrouped) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.link, color: Colors.white, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    '그룹: ${widget.to.groupName ?? "연결됨"}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          // 사업장명
          Text(
            widget.to.businessName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          
          // ✅ 제목
          Text(
            widget.to.title,
            style: TextStyle(
              color: Colors.white.withOpacity(0.95),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          
          // 날짜 + 시간
          Text(
            '${dateFormat.format(widget.to.date)} | ${widget.to.startTime} ~ ${widget.to.endTime}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          
          // ✅ 전체 모집 인원
          Text(
            '전체 모집: ${widget.to.totalRequired}명 | 확정: ${widget.to.totalConfirmed}명',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  /// ✅ NEW: WorkDetails 섹션
  Widget _buildWorkDetailsSection() {
    if (_workDetails.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.orange[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange[200]!),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange[700], size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '업무 상세 정보가 없습니다',
                  style: TextStyle(
                    color: Colors.orange[900],
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.blue[50],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.work_outline, color: Colors.blue[700], size: 20),
                const SizedBox(width: 8),
                Text(
                  '업무 상세',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[900],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._workDetails.map((detail) {
              final isFull = detail.isFull;
              final progressColor = isFull ? Colors.green : Colors.blue;
              
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isFull ? Colors.green[200]! : Colors.blue[200]!,
                    ),
                  ),
                  child: Row(
                    children: [
                      // 업무 유형
                      Expanded(
                        flex: 2,
                        child: Text(
                          detail.workType,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      
                      // 금액
                      Expanded(
                        flex: 2,
                        child: Text(
                          detail.formattedWage,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.blue[700],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      
                      // 인원 (확정/필요)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: progressColor[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          detail.countInfo,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: progressColor[700],
                          ),
                        ),
                      ),
                      
                      // 마감 표시
                      if (isFull) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green[600],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            '마감',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  /// 지원자 목록
  Widget _buildApplicantsList() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(50),
        child: LoadingWidget(message: '지원자 목록을 불러오는 중...'),
      );
    }

    if (_applicants.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(50),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person_off_outlined, size: 60, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                '아직 지원자가 없습니다',
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

    // 상태별로 분류
    final pending = _applicants.where((a) => a['application'].status == 'PENDING').toList();
    final confirmed = _applicants.where((a) => a['application'].status == 'CONFIRMED').toList();
    final rejected = _applicants.where((a) => a['application'].status == 'REJECTED').toList();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        // 통계 헤더
        _buildStatisticsRow(pending.length, confirmed.length, rejected.length),
        const SizedBox(height: 16),

        // 대기 중
        if (pending.isNotEmpty) ...[
          _buildSectionHeader('⏳ 대기 중', Colors.orange, pending.length),
          const SizedBox(height: 8),
          ...pending.map((applicant) => _buildApplicantCard(applicant)),
          const SizedBox(height: 24),
        ],

        // 확정
        if (confirmed.isNotEmpty) ...[
          _buildSectionHeader('✅ 확정', Colors.green, confirmed.length),
          const SizedBox(height: 8),
          ...confirmed.map((applicant) => _buildApplicantCard(applicant)),
          const SizedBox(height: 24),
        ],

        // 거절
        if (rejected.isNotEmpty) ...[
          _buildSectionHeader('❌ 거절', Colors.red, rejected.length),
          const SizedBox(height: 8),
          ...rejected.map((applicant) => _buildApplicantCard(applicant)),
        ],
      ],
    );
  }

  /// 통계 요약 행
  Widget _buildStatisticsRow(int pending, int confirmed, int rejected) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('대기 중', pending, Colors.orange),
          Container(width: 1, height: 30, color: Colors.grey[300]),
          _buildStatItem('확정', confirmed, Colors.green),
          Container(width: 1, height: 30, color: Colors.grey[300]),
          _buildStatItem('거절', rejected, Colors.red),
        ],
      ),
    );
  }

  /// 통계 항목
  Widget _buildStatItem(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$count',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  /// 섹션 헤더
  Widget _buildSectionHeader(String title, Color color, int count) {
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$count명',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  /// 지원자 카드
  Widget _buildApplicantCard(Map<String, dynamic> applicant) {
    final app = applicant['application'] as ApplicationModel;
    final userName = applicant['userName'] as String;
    final userEmail = applicant['userEmail'] as String;
    final timeFormat = DateFormat('HH:mm');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 이름 + 상태 배지
            Row(
              children: [
                Expanded(
                  child: Text(
                    userName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Color(app.statusColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    app.statusText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // ✅ 선택한 업무 유형 + 금액
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.work, size: 16, color: Colors.blue[700]),
                  const SizedBox(width: 8),
                  Text(
                    app.selectedWorkType,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue[900],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    app.formattedWage,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[700],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // 이메일
            Row(
              children: [
                Icon(Icons.email, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Text(
                  userEmail,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),

            // 지원 일시
            Row(
              children: [
                Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Text(
                  '지원: ${timeFormat.format(app.appliedAt)}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),

            // 확정 일시 (확정/거절인 경우)
            if (app.confirmedAt != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.check_circle, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Text(
                    '처리: ${timeFormat.format(app.confirmedAt!)}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ],

            // 버튼 (대기 중인 경우만)
            if (app.status == 'PENDING') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _rejectApplicant(applicant['applicationId']),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('거절'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _confirmApplicant(applicant['applicationId']),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('승인'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
  // ✅ NEW Phase 2: 그룹 TO 목록 위젯 추가 (여기에 추가!)
  /// 같은 그룹의 TO 목록
  Widget _buildGroupTOsSection() {
    // 그룹이 없으면 표시 안 함
    if (!widget.to.isGrouped || _groupTOs.isEmpty) {
      return const SizedBox.shrink();
    }

    // 현재 TO 제외
    final otherTOs = _groupTOs.where((to) => to.id != widget.to.id).toList();

    if (otherTOs.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.green[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green[200]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더
            Row(
              children: [
                Icon(Icons.group_work, color: Colors.green[700], size: 20),
                const SizedBox(width: 8),
                Text(
                  '🔗 연결된 TO (${otherTOs.length}개)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[900],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '그룹 전체 지원자: $_groupTotalApplicants명',
              style: TextStyle(
                fontSize: 13,
                color: Colors.green[700],
              ),
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),

            // TO 목록
            ...otherTOs.map((to) {
              final dateFormat = DateFormat('MM/dd');
              final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
              final weekday = weekdays[to.date.weekday - 1];

              return FutureBuilder<List<WorkDetailModel>>(
                future: _firestoreService.getWorkDetails(to.id),
                builder: (context, snapshot) {
                  // WorkDetails 조회해서 시간 범위 계산
                  String timeRange = '~';
                  if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                    final workDetails = snapshot.data!;
                    final startTimes = workDetails.map((w) => w.startTime).toList();
                    final endTimes = workDetails.map((w) => w.endTime).toList();
                    startTimes.sort();
                    endTimes.sort();
                    timeRange = '${startTimes.first} ~ ${endTimes.last}';
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green[200]!),
                      ),
                      child: Row(
                        children: [
                          // 날짜
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green[100],
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${dateFormat.format(to.date)}\n($weekday)',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.green[800],
                                height: 1.2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),

                          // TO 정보
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  to.title,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '$timeRange | ${to.totalConfirmed}/${to.totalRequired}명',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // 상태 표시
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: to.isFull ? Colors.green[100] : Colors.blue[100],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              to.isFull ? '마감' : '모집중',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: to.isFull ? Colors.green[700] : Colors.blue[700],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            }).toList(),
          ],
        ),
      ),
    );
  }
  /// ✅ NEW Phase 2.5: 이 TO 지원자 목록
  Widget _buildThisTOApplicantsList() {
    if (_applicants.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(50),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person_off_outlined, size: 60, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                '아직 지원자가 없습니다',
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

    // 상태별로 분류
    final pending = _applicants.where((a) => a['application'].status == 'PENDING').toList();
    final confirmed = _applicants.where((a) => a['application'].status == 'CONFIRMED').toList();
    final rejected = _applicants.where((a) => a['application'].status == 'REJECTED').toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // 통계 헤더
          _buildStatisticsRow(pending.length, confirmed.length, rejected.length),
          const SizedBox(height: 16),

          // 대기 중
          if (pending.isNotEmpty) ...[
            _buildSectionHeader('⏳ 대기 중', Colors.orange, pending.length),
            const SizedBox(height: 8),
            ...pending.map((applicant) => _buildApplicantCard(applicant)),
            const SizedBox(height: 24),
          ],

          // 확정
          if (confirmed.isNotEmpty) ...[
            _buildSectionHeader('✅ 확정', Colors.green, confirmed.length),
            const SizedBox(height: 8),
            ...confirmed.map((applicant) => _buildApplicantCard(applicant)),
            const SizedBox(height: 24),
          ],

          // 거절
          if (rejected.isNotEmpty) ...[
            _buildSectionHeader('❌ 거절', Colors.red, rejected.length),
            const SizedBox(height: 8),
            ...rejected.map((applicant) => _buildApplicantCard(applicant)),
          ],
        ],
      ),
    );
  }
  // ✅ NEW Phase 2.5: 그룹 전체 지원자 목록
  Widget _buildGroupApplicantsList() {
    if (_groupApplicants.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(50),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.people_outlined, size: 60, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                '그룹 전체 지원자가 없습니다',
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

    // 상태별로 분류
    final pending = _groupApplicants.where((a) => a['application'].status == 'PENDING').toList();
    final confirmed = _groupApplicants.where((a) => a['application'].status == 'CONFIRMED').toList();
    final rejected = _groupApplicants.where((a) => a['application'].status == 'REJECTED').toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // 통계 헤더
          _buildStatisticsRow(pending.length, confirmed.length, rejected.length),
          const SizedBox(height: 16),

          // 대기 중
          if (pending.isNotEmpty) ...[
            _buildSectionHeader('⏳ 대기 중', Colors.orange, pending.length),
            const SizedBox(height: 8),
            ...pending.map((applicant) => _buildGroupApplicantCard(applicant)),
            const SizedBox(height: 24),
          ],

          // 확정
          if (confirmed.isNotEmpty) ...[
            _buildSectionHeader('✅ 확정', Colors.green, confirmed.length),
            const SizedBox(height: 8),
            ...confirmed.map((applicant) => _buildGroupApplicantCard(applicant)),
            const SizedBox(height: 24),
          ],

          // 거절
          if (rejected.isNotEmpty) ...[
            _buildSectionHeader('❌ 거절', Colors.red, rejected.length),
            const SizedBox(height: 8),
            ...rejected.map((applicant) => _buildGroupApplicantCard(applicant)),
          ],
        ],
      ),
    );
  }

  /// ✅ NEW Phase 2.5: 그룹 지원자 카드 (TO 정보 포함)
  Widget _buildGroupApplicantCard(Map<String, dynamic> applicant) {
    final app = applicant['application'] as ApplicationModel;
    final userName = applicant['userName'] as String;
    final userEmail = applicant['userEmail'] as String;
    final userPhone = applicant['userPhone'] as String;
    final toTitle = applicant['toTitle'] as String;
    final toDate = applicant['toDate'] as DateTime;
    final dateFormat = DateFormat('MM/dd');
    final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final weekday = weekdays[toDate.weekday - 1];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 이름 + 상태 배지
            Row(
              children: [
                Expanded(
                  child: Text(
                    userName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Color(app.statusColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    app.statusText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ✅ 지원한 TO 정보 (그룹 카드만 표시)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.event, size: 16, color: Colors.blue[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          toTitle,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue[900],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${dateFormat.format(toDate)} ($weekday)',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 선택한 업무 유형 + 금액
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.work_outline, size: 16, color: Colors.green[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${app.selectedWorkType} - ${app.formattedWage}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.green[900],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // 이메일, 전화번호, 지원일시
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.email_outlined, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        userEmail,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (userPhone.isNotEmpty) ...[
                  Row(
                    children: [
                      Icon(Icons.phone_outlined, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 6),
                      Text(
                        userPhone,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
                Row(
                  children: [
                    Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 6),
                    Text(
                      '지원일시: ${DateFormat('yyyy-MM-dd HH:mm').format(app.appliedAt)}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // 버튼 (대기 중인 경우만)
            if (app.status == 'PENDING') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _rejectApplicant(applicant['applicationId']),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('거절'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _confirmApplicant(applicant['applicationId']),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('승인'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}