import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/application_model.dart';
import '../../models/to_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../widgets/loading_widget.dart';
import '../../utils/toast_helper.dart';
import 'package:intl/intl.dart';

/// 내 지원 내역 화면
class MyApplicationsScreen extends StatefulWidget {
  const MyApplicationsScreen({Key? key}) : super(key: key);

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
            child: const Text('예', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // 로딩 다이얼로그 표시
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
                Text('취소 중...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final success = await _firestoreService.cancelApplication(applicationId, uid);
      
      if (mounted) {
        Navigator.pop(context); // 로딩 다이얼로그 닫기
      }

      if (success) {
        ToastHelper.showSuccess('지원이 취소되었습니다.');
        _loadApplications(); // 목록 새로고침
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // 로딩 다이얼로그 닫기
      }
      print('❌ 취소 실패: $e');
      ToastHelper.showError('취소 중 오류가 발생했습니다.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('내 지원 내역'),
        elevation: 0,
        backgroundColor: Colors.blue[700],
      ),
      body: Column(
        children: [
          // 상태 필터 버튼
          _buildFilterBar(),
          
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
                            return _buildApplicationCard(_filteredApplications[index]);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  /// 상태 필터 바
  Widget _buildFilterBar() {
    return Container(
      color: Colors.grey[100],
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildFilterChip('전체', 'ALL'),
            const SizedBox(width: 8),
            _buildFilterChip('대기 중', 'PENDING'),
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

  /// 필터 칩
  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedFilter = value;
        });
      },
      selectedColor: Colors.blue[100],
      checkmarkColor: Colors.blue[800],
      labelStyle: TextStyle(
        color: isSelected ? Colors.blue[800] : Colors.grey[700],
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  /// 빈 상태 위젯
  Widget _buildEmptyState() {
    String message;
    switch (_selectedFilter) {
      case 'PENDING':
        message = '대기 중인 지원이 없습니다.';
        break;
      case 'CONFIRMED':
        message = '확정된 지원이 없습니다.';
        break;
      case 'REJECTED':
        message = '거절된 지원이 없습니다.';
        break;
      case 'CANCELED':
        message = '취소된 지원이 없습니다.';
        break;
      default:
        message = '아직 지원한 TO가 없습니다.\n센터에서 TO를 찾아보세요!';
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  /// 요일 한글 변환
  String _getKoreanWeekday(DateTime date) {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    return weekdays[date.weekday - 1];
  }

  /// 지원 카드
  Widget _buildApplicationCard(_ApplicationWithTO item) {
    final app = item.application;
    final to = item.to;
    final dateFormat = DateFormat('M월 d일');
    final timeFormat = DateFormat('HH:mm');
    final koreanWeekday = _getKoreanWeekday(to.date);

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
            // 상태 배지
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Color(app.statusColor),
                    borderRadius: BorderRadius.circular(20),
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
                const Spacer(),
                Text(
                  '지원일: ${timeFormat.format(app.appliedAt)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 12),

            // TO 정보
            Row(
              children: [
                Icon(Icons.business, color: Colors.blue[700], size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    to.centerName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            Row(
              children: [
                Icon(Icons.calendar_today, color: Colors.grey[600], size: 16),
                const SizedBox(width: 8),
                Text(
                  '${dateFormat.format(to.date)} ($koreanWeekday)',
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 4),

            Row(
              children: [
                Icon(Icons.access_time, color: Colors.grey[600], size: 16),
                const SizedBox(width: 8),
                Text(
                  '${to.startTime} ~ ${to.endTime}',
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 4),

            Row(
              children: [
                Icon(Icons.work_outline, color: Colors.grey[600], size: 16),
                const SizedBox(width: 8),
                Text(
                  to.workType,
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 4),

            Row(
              children: [
                Icon(Icons.people, color: Colors.grey[600], size: 16),
                const SizedBox(width: 8),
                Text(
                  '모집: ${to.currentCount}/${to.requiredCount}명',
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),

            // 확정 정보 (확정된 경우만)
            if (app.status == 'CONFIRMED' && app.confirmedAt != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green[700], size: 16),
                    const SizedBox(width: 8),
                    Text(
                      '확정일: ${timeFormat.format(app.confirmedAt!)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green[700],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // 취소 버튼 (대기 중인 경우만)
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
}

/// 지원서 + TO 정보를 함께 담는 클래스
class _ApplicationWithTO {
  final ApplicationModel application;
  final TOModel to;

  _ApplicationWithTO({
    required this.application,
    required this.to,
  });
}