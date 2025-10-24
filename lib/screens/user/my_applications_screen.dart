import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/application_model.dart';
import '../../models/to_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../widgets/loading_widget.dart';
import '../../utils/toast_helper.dart';
import 'package:intl/intl.dart';

/// 내 지원 내역 화면 - 신버전
class MyApplicationsScreen extends StatefulWidget {
  const MyApplicationsScreen({super.key});

  @override
  State<MyApplicationsScreen> createState() => _MyApplicationsScreenState();
}

class _MyApplicationsScreenState extends State<MyApplicationsScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  List<_ApplicationWithTO> _applications = [];
  bool _isLoading = true;
  String _selectedFilter = 'ALL'; // ALL, PENDING, CONFIRMED, REJECTED, CANCELED

  @override
  void initState() {
    super.initState();
    _loadApplications();
  }

  /// 내 지원 내역 + TO 정보 함께 로드
  Future<void> _loadApplications() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;

      if (uid == null) {
        ToastHelper.showError('로그인이 필요합니다.');
        return;
      }

      // 내 지원 내역 조회
      final applications = await _firestoreService.getMyApplications(uid);
      print('✅ 조회된 지원 내역: ${applications.length}개');

      // 각 지원서에 대한 TO 정보 가져오기
      List<_ApplicationWithTO> appWithTOs = [];
      for (var app in applications) {
        final to = await _firestoreService.getTO(app.toId);
        if (to != null) {
          appWithTOs.add(_ApplicationWithTO(
            application: app,
            to: to,
          ));
        }
      }

      // 최신순 정렬
      appWithTOs.sort((a, b) => b.application.appliedAt.compareTo(a.application.appliedAt));

      setState(() {
        _applications = appWithTOs;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ 지원 내역 로드 실패: $e');
      ToastHelper.showError('지원 내역을 불러오는데 실패했습니다.');
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 필터링된 지원 목록
  List<_ApplicationWithTO> get _filteredApplications {
    if (_selectedFilter == 'ALL') {
      return _applications;
    }
    return _applications.where((item) => item.application.status == _selectedFilter).toList();
  }

  /// 지원 취소
  Future<void> _cancelApplication(String applicationId) async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final uid = userProvider.currentUser?.uid;

    if (uid == null) {
      ToastHelper.showError('로그인이 필요합니다.');
      return;
    }

    // 확인 다이얼로그
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('지원 취소'),
        content: const Text('정말 지원을 취소하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('아니오'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('취소하기'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // 취소 처리
    final success = await _firestoreService.cancelApplication(applicationId, uid);
    if (success && mounted) {
      ToastHelper.showSuccess('지원이 취소되었습니다.');
      _loadApplications();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('내 지원 내역'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadApplications,
          ),
        ],
      ),
      body: Column(
        children: [
          // 필터
          _buildFilterSection(),
          
          // 지원 목록
          Expanded(
            child: _isLoading
                ? const LoadingWidget(message: '지원 내역을 불러오는 중...')
                : _filteredApplications.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadApplications,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredApplications.length,
                          itemBuilder: (context, index) {
                            final item = _filteredApplications[index];
                            return _buildApplicationCard(item);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  /// 필터 섹션
  Widget _buildFilterSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[100],
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildFilterChip('전체', 'ALL'),
            const SizedBox(width: 8),
            _buildFilterChip('대기중', 'PENDING'),
            const SizedBox(width: 8),
            _buildFilterChip('확정', 'CONFIRMED'),
            const SizedBox(width: 8),
            _buildFilterChip('거절', 'REJECTED'),
            const SizedBox(width: 8),
            _buildFilterChip('취소', 'CANCELED'),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        setState(() {
          _selectedFilter = value;
        });
      },
      backgroundColor: Colors.white,
      selectedColor: Colors.blue[100],
      checkmarkColor: Colors.blue[700],
      labelStyle: TextStyle(
        color: isSelected ? Colors.blue[900] : Colors.grey[700],
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  /// 빈 상태
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.assignment_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            _selectedFilter == 'ALL' ? '지원 내역이 없습니다' : '해당 상태의 지원이 없습니다',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'TO에 지원해보세요!',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  /// ✅ 지원서 카드 (업무유형 + 금액 표시)
  Widget _buildApplicationCard(_ApplicationWithTO item) {
    final app = item.application;
    final to = item.to;
    final dateFormat = DateFormat('yyyy년 M월 d일');

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1행: 사업장명 + 상태 배지
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    to.businessName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _buildStatusBadge(app.status),
              ],
            ),
            
            const SizedBox(height: 8),
            
            // TO 제목
            Text(
              to.title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.grey[800],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            
            const Divider(height: 20),
            
            // 날짜 정보
            _buildInfoRow(
              Icons.calendar_today,
              '근무일',
              '${dateFormat.format(to.date)} (${to.weekday})',
            ),
            const SizedBox(height: 8),
            
            // 시간 정보
            _buildInfoRow(
              Icons.access_time,
              '근무시간',
              to.timeRange,
            ),
            const SizedBox(height: 8),
            
            // ✅ 업무유형 + 금액
            _buildInfoRow(
              Icons.work_outline,
              '지원 업무',
              '${app.selectedWorkType} | ${app.formattedWage}',
            ),
            
            // ✅ 업무유형 변경 이력 표시
            if (app.isWorkTypeChanged) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.orange[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '업무 변경: ${app.originalWorkType} → ${app.selectedWorkType}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange[900],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            const SizedBox(height: 12),
            
            // 지원 날짜
            Text(
              '지원일: ${DateFormat('yyyy.MM.dd HH:mm').format(app.appliedAt)}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            
            // 취소 버튼 (대기중일 때만)
            if (app.status == 'PENDING') ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _cancelApplication(app.id),
                  icon: const Icon(Icons.cancel_outlined, size: 18),
                  label: const Text('지원 취소'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 정보 행
  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey[700],
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  /// 상태 배지
  Widget _buildStatusBadge(String status) {
    Color bgColor;
    Color textColor;
    String text;

    switch (status) {
      case 'PENDING':
        bgColor = Colors.orange.shade50;
        textColor = Colors.orange.shade700;
        text = '대기중';
        break;
      case 'CONFIRMED':
        bgColor = Colors.green.shade50;
        textColor = Colors.green.shade700;
        text = '확정';
        break;
      case 'REJECTED':
        bgColor = Colors.red.shade50;
        textColor = Colors.red.shade700;
        text = '거절';
        break;
      case 'CANCELED':
        bgColor = Colors.grey.shade100;
        textColor = Colors.grey.shade600;
        text = '취소';
        break;
      default:
        bgColor = Colors.grey.shade100;
        textColor = Colors.grey.shade600;
        text = '알 수 없음';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: textColor.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );
  }
}

/// 지원서 + TO 정보
class _ApplicationWithTO {
  final ApplicationModel application;
  final TOModel to;

  _ApplicationWithTO({
    required this.application,
    required this.to,
  });
}