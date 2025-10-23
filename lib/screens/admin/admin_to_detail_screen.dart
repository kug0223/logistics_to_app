import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/to_model.dart';
import '../../models/application_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../widgets/loading_widget.dart';
import '../../utils/toast_helper.dart';
import 'package:intl/intl.dart';

/// 관리자 TO 상세 화면 (지원자 관리)
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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadApplicants();
  }

  /// 지원자 목록 로드
  Future<void> _loadApplicants() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final applicants = await _firestoreService.getApplicantsWithUserInfo(widget.to.id);
      
      setState(() {
        _applicants = applicants;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ 지원자 로드 실패: $e');
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
        _loadApplicants(); // 목록 새로고침
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
        Navigator.pop(context);
      }

      if (success) {
        _loadApplicants();
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
      }
      print('❌ 거절 실패: $e');
    }
  }

  /// 요일 한글 변환
  String _getKoreanWeekday(DateTime date) {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    return weekdays[date.weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TO 상세 - 지원자 관리'),
        backgroundColor: Colors.purple[700],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // TO 정보
            _buildTOInfo(),
            
            // 지원자 목록
            _buildApplicantsList(),
          ],
        ),
      ),
    );
  }

  /// TO 정보
  Widget _buildTOInfo() {
    final dateFormat = DateFormat('M월 d일');
    final koreanWeekday = _getKoreanWeekday(widget.to.date);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.purple[700]!, Colors.purple[500]!],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.to.businessName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${dateFormat.format(widget.to.date)} ($koreanWeekday) | ${widget.to.startTime} ~ ${widget.to.endTime}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${widget.to.workType} | 모집: ${widget.to.requiredCount}명',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 14,
            ),
          ),
        ],
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
    final canceled = _applicants.where((a) => a['application'].status == 'CANCELED').toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 대기 중
          if (pending.isNotEmpty) ...[
            _buildSectionTitle('⏳ 대기 중', pending.length, Colors.orange),
            ...pending.map((applicant) => _buildApplicantCard(applicant)),
            const SizedBox(height: 16),
          ],

          // 확정
          if (confirmed.isNotEmpty) ...[
            _buildSectionTitle('✅ 확정', confirmed.length, Colors.green),
            ...confirmed.map((applicant) => _buildApplicantCard(applicant)),
            const SizedBox(height: 16),
          ],

          // 거절
          if (rejected.isNotEmpty) ...[
            _buildSectionTitle('❌ 거절', rejected.length, Colors.red),
            ...rejected.map((applicant) => _buildApplicantCard(applicant)),
            const SizedBox(height: 16),
          ],

          // 취소
          if (canceled.isNotEmpty) ...[
            _buildSectionTitle('🚫 취소', canceled.length, Colors.grey),
            ...canceled.map((applicant) => _buildApplicantCard(applicant)),
          ],
        ],
      ),
    );
  }

  /// 섹션 타이틀
  Widget _buildSectionTitle(String title, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
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
      ),
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