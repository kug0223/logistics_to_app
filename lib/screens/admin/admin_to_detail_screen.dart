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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  /// ✅ NEW: 지원자 + WorkDetails 동시 로드
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final results = await Future.wait([
        _firestoreService.getApplicantsWithUserInfo(widget.to.id),
        _firestoreService.getWorkDetails(widget.to.id),
      ]);

      setState(() {
        _applicants = results[0] as List<Map<String, dynamic>>;
        _workDetails = results[1] as List<WorkDetailModel>;
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('TO 상세'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          _buildWorkDetailsSection(), // ✅ NEW
          const SizedBox(height: 16),
          Expanded(
            child: _buildApplicantsList(),
          ),
        ],
      ),
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
            '${dateFormat.format(widget.to.date)} ($koreanWeekday) | ${widget.to.startTime} ~ ${widget.to.endTime}',
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
                  '💼 업무 상세',
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
}