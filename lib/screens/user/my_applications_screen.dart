import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/gestures.dart';
import '../../models/core/application_model.dart';
import '../../models/core/to_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/styled_container.dart';
import '../../utils/toast_helper.dart';
import 'package:intl/intl.dart';
import '../../utils/dialog_helper.dart';


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

      // ✅ 병렬로 TO 정보 가져오기 (최적화!)
      final futures = applications.map((app) async {
        final to = await _firestoreService.getTOByApplication(app);
        if (to != null) {
          return _ApplicationWithTO(
            application: app,
            to: to,
          );
        }
        return null;
      }).toList();

      final results = await Future.wait(futures);
      final appWithTOs = results.whereType<_ApplicationWithTO>().toList();

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

    final confirmed = await DialogHelper.showCancelConfirm(
      context,
      title: '지원 취소',
      message: '정말 지원을 취소하시겠습니까?',
    );

    if (!confirmed) return;

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
      padding: const EdgeInsets.symmetric(vertical: 12),
      color: Colors.grey[100],
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse, // ⭐ 마우스 드래그 활성화
          },
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
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
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    
    // 상태별 아이콘 및 색상
    IconData icon;
    MaterialColor color;
    
    switch (value) {
      case 'ALL':
        icon = Icons.list_alt;
        color = Colors.blue;
        break;
      case 'PENDING':
        icon = Icons.schedule;
        color = Colors.orange;
        break;
      case 'CONFIRMED':
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case 'REJECTED':
        icon = Icons.cancel;
        color = Colors.red;
        break;
      case 'CANCELED':
        icon = Icons.remove_circle_outline;
        color = Colors.grey;
        break;
      default:
        icon = Icons.help_outline;
        color = Colors.grey;
    }
    
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      child: FilterChip(
        avatar: Icon(
          icon,
          size: 16, // ⭐ 18 → 16으로 축소
          color: isSelected ? color[700] : color[400],
        ),
        label: Text(label),
        selected: isSelected,
        onSelected: (_) {
          setState(() {
            _selectedFilter = value;
          });
        },
        backgroundColor: Colors.white,
        selectedColor: color[50],
        side: BorderSide(
          color: isSelected ? color[300]! : Colors.grey[300]!,
          width: isSelected ? 2 : 1,
        ),
        checkmarkColor: color[700],
        labelStyle: TextStyle(
          color: isSelected ? color[900] : Colors.grey[700],
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontSize: 13, // ⭐ 폰트 크기 명시
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6), // ⭐ 8 → 6으로 축소
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, // ⭐ 추가
        elevation: isSelected ? 2 : 0,
        shadowColor: color[200],
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
    
    // ⭐ Phase 4-2: 확정 여부 확인
    final isConfirmed = app.status == 'CONFIRMED';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: isConfirmed ? 4 : 2, // ⭐ 확정되면 그림자 강화
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isConfirmed ? Colors.green[300]! : Colors.transparent,
          width: isConfirmed ? 2 : 0, // ⭐ 확정되면 테두리
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: isConfirmed
              ? LinearGradient( // ⭐ 확정되면 그라데이션 배경
                  colors: [
                    Colors.green[50]!,
                    Colors.white,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ⭐ Phase 4-2: 확정 배너
              if (isConfirmed) ...[
                _buildConfirmedBanner(),
                const SizedBox(height: 12),
              ],
              
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
              
              // ⭐ Phase 1-B: 장기 공고 정보 표시
              if (app.isLongTermApplication) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.purple[50],
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.purple[200]!),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_month, size: 16, color: Colors.purple[700]),
                      const SizedBox(width: 6),
                      Text(
                        app.workPeriodDisplay,  // "11/1~11/30"
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.purple[700],
                        ),
                      ),
                      if (app.workDaysDisplay != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          '•',
                          style: TextStyle(color: Colors.purple[400]),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          app.workDaysDisplay!,  // "주 5일 (월~금)"
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.purple[600],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              
              const SizedBox(height: 12),
              
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
              
              // ⭐ Phase 4: 자동 취소 상세 정보
              if (app.status == 'AUTO_CANCELED' && app.conflictingBusiness != null) ...[
                const SizedBox(height: 12),
                _buildConflictInfoCard(app),
              ],
              
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
      ),
    );
  }
  /// Phase 4-2: 확정 근무 배너
  Widget _buildConfirmedBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green[400]!, Colors.green[600]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.green[200]!,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.3),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.check_circle,
              size: 20,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '✨ 확정된 근무입니다',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  '근무 당일 출퇴근 체크를 잊지 마세요!',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.arrow_forward_ios,
            size: 16,
            color: Colors.white,
          ),
        ],
      ),
    );
  }
  /// 자동 취소 충돌 정보 카드
  Widget _buildConflictInfoCard(ApplicationModel app) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange[200]!, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.orange[100],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  Icons.schedule_outlined,
                  size: 18,
                  color: Colors.orange[700],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '시간 충돌로 자동 취소됨',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange[800],
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 10),
          
          // 충돌한 공고 정보
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.orange[100]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.business, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        app.conflictingBusiness!,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 6),
                    Text(
                      app.conflictingTime ?? '시간 정보 없음',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.green[200]!),
                      ),
                      child: Text(
                        '확정됨',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.green[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 10),
          
          // 안내 문구
          Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: Colors.orange[600]),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '위 근무가 확정되어 자동으로 취소되었습니다.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[700],
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 8),
          
          // 재지원 안내
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(Icons.touch_app, size: 14, color: Colors.blue[700]),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '다른 시간대 공고에는 다시 지원 가능합니다',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.blue[800],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
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
    // ⭐ 수정: StyledBadge 사용
    switch (status) {
      case 'PENDING':
        return StyledBadge(
          label: '대기중',
          backgroundColor: Colors.orange.shade50,
          textColor: Colors.orange.shade700,
          fontSize: 12,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        );
      case 'CONFIRMED':
        return StyledBadge(
          label: '확정',
          backgroundColor: Colors.green.shade50,
          textColor: Colors.green.shade700,
          fontSize: 12,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        );
      case 'REJECTED':
        return StyledBadge(
          label: '거절',
          backgroundColor: Colors.red.shade50,
          textColor: Colors.red.shade700,
          fontSize: 12,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        );
      case 'CANCELED':
        return StyledBadge(
          label: '취소',
          backgroundColor: Colors.grey.shade100,
          textColor: Colors.grey.shade600,
          fontSize: 12,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        );
      case 'AUTO_CANCELED':  // ⭐ 추가
        return StyledBadge(
          label: '자동 취소',
          backgroundColor: Colors.orange.shade50,
          textColor: Colors.orange.shade700,
          fontSize: 12,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        );
      default:
        return StyledBadge(
          label: '알 수 없음',
          backgroundColor: Colors.grey.shade100,
          textColor: Colors.grey.shade600,
          fontSize: 12,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        );
    }
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