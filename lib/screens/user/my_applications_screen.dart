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
import '../../utils/responsive_helper.dart';  // ⭐ 추가


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
                          padding: ResponsiveHelper.cardPadding(context),
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
      padding: EdgeInsets.symmetric(
        vertical: ResponsiveHelper.spacing(context, 12),
      ),
      color: Colors.grey[100],
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
          },
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 16),
          ),
          child: Row(
            children: [
              _buildFilterChip('전체', 'ALL'),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              _buildFilterChip('대기중', 'PENDING'),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              _buildFilterChip('확정', 'CONFIRMED'),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              _buildFilterChip('거절', 'REJECTED'),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              _buildFilterChip('취소', 'CANCELED'),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
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
          size: ResponsiveHelper.iconSize(context, 16),
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
        labelStyle: ResponsiveHelper.smallStyle(context).copyWith(
          color: isSelected ? color[900] : Colors.grey[700],
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 6),
          vertical: ResponsiveHelper.spacing(context, 6),
        ),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
            size: ResponsiveHelper.iconSize(context, 80),
            color: Colors.grey[400],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          Text(
            _selectedFilter == 'ALL' ? '지원 내역이 없습니다' : '해당 상태의 지원이 없습니다',
            style: ResponsiveHelper.titleStyle(
              context,
              color: Colors.grey[600],
            ).copyWith(fontWeight: FontWeight.w500),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Text(
            'TO에 지원해보세요!',
            style: ResponsiveHelper.bodyStyle(
              context,
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
    
    final isConfirmed = app.status == 'CONFIRMED';

    return Card(
      margin: EdgeInsets.only(
        bottom: ResponsiveHelper.spacing(context, 16),
      ),
      elevation: isConfirmed ? 4 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isConfirmed ? Colors.green[300]! : Colors.transparent,
          width: isConfirmed ? 2 : 0,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: isConfirmed
              ? LinearGradient(
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
          padding: ResponsiveHelper.cardPadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 확정 배너
              if (isConfirmed) ...[
                _buildConfirmedBanner(),
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
              ],
              
              // 1행: 사업장명 + 상태 배지
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      to.businessName,
                      style: ResponsiveHelper.titleStyle(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _buildStatusBadge(app.status),
                ],
              ),
              
              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              
              // TO 제목
              Text(
                to.title,
                style: ResponsiveHelper.subtitleStyle(
                  context,
                  color: Colors.grey[800],
                ).copyWith(fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              
              // 장기 공고 정보 표시
              if (app.isLongTermApplication) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 10),
                    vertical: ResponsiveHelper.spacing(context, 6),
                  ),
                  decoration: BoxDecoration(
                    color: Colors.purple[50],
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.purple[200]!),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.calendar_month, 
                        size: ResponsiveHelper.iconSize(context, 16), 
                        color: Colors.purple[700]
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                      Text(
                        app.workPeriodDisplay,
                        style: ResponsiveHelper.smallStyle(
                          context,
                          color: Colors.purple[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (app.workDaysDisplay != null) ...[
                        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                        Text(
                          '•',
                          style: TextStyle(color: Colors.purple[400]),
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                        Text(
                          app.workDaysDisplay!,
                          style: ResponsiveHelper.smallStyle(
                            context,
                            color: Colors.purple[600],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),
              
              // 날짜 정보
              _buildInfoRow(
                Icons.calendar_today,
                '근무일',
                '${dateFormat.format(to.date)} (${to.weekday})',
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              
              // 시간 정보
              _buildInfoRow(
                Icons.access_time,
                '근무시간',
                to.timeRange,
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              
              // 업무유형 + 금액
              _buildInfoRow(
                Icons.work_outline,
                '지원 업무',
                '${app.selectedWorkType} | ${app.formattedWage}',
              ),
              
              // 업무유형 변경 이력 표시
              if (app.isWorkTypeChanged) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                Container(
                  padding: ResponsiveHelper.cardPadding(context),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline, 
                        size: ResponsiveHelper.iconSize(context, 16), 
                        color: Colors.orange[700]
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                      Expanded(
                        child: Text(
                          '업무 변경: ${app.originalWorkType} → ${app.selectedWorkType}',
                          style: ResponsiveHelper.smallStyle(
                            context,
                            color: Colors.orange[900],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),
              
              // 지원 날짜
              Text(
                '지원일: ${DateFormat('yyyy.MM.dd HH:mm').format(app.appliedAt)}',
                style: ResponsiveHelper.smallStyle(
                  context,
                  color: Colors.grey[600],
                ),
              ),
              
              // 자동 취소 상세 정보
              if (app.status == 'AUTO_CANCELED' && app.conflictingBusiness != null) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                _buildConflictInfoCard(app),
              ],
              
              // 취소 버튼 (대기중일 때만)
              if (app.status == 'PENDING') ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _cancelApplication(app.id),
                    icon: Icon(
                      Icons.cancel_outlined, 
                      size: ResponsiveHelper.iconSize(context, 18)
                    ),
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
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 10),
      ),
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
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 6)),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.3),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              Icons.check_circle,
              size: ResponsiveHelper.iconSize(context, 20),
              color: Colors.white,
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '✨ 확정된 근무입니다',
                  style: ResponsiveHelper.bodyStyle(
                    context,
                    color: Colors.white,
                  ).copyWith(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                Text(
                  '근무 당일 출퇴근 체크를 잊지 마세요!',
                  style: ResponsiveHelper.tinyStyle(
                    context,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.arrow_forward_ios,
            size: ResponsiveHelper.iconSize(context, 16),
            color: Colors.white,
          ),
        ],
      ),
    );
  }

  /// 자동 취소 충돌 정보 카드
  Widget _buildConflictInfoCard(ApplicationModel app) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
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
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 6)),
                decoration: BoxDecoration(
                  color: Colors.orange[100],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  Icons.schedule_outlined,
                  size: ResponsiveHelper.iconSize(context, 18),
                  color: Colors.orange[700],
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Expanded(
                child: Text(
                  '시간 충돌로 자동 취소됨',
                  style: ResponsiveHelper.bodyStyle(
                    context,
                    color: Colors.orange[800],
                  ).copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 10)),
          
          // 충돌한 공고 정보
          Container(
            padding: ResponsiveHelper.cardPadding(context),
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
                    Icon(
                      Icons.business, 
                      size: ResponsiveHelper.iconSize(context, 14), 
                      color: Colors.grey[600]
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                    Expanded(
                      child: Text(
                        app.conflictingBusiness!,
                        style: ResponsiveHelper.smallStyle(
                          context,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                Row(
                  children: [
                    Icon(
                      Icons.access_time, 
                      size: ResponsiveHelper.iconSize(context, 14), 
                      color: Colors.grey[600]
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                    Text(
                      app.conflictingTime ?? '시간 정보 없음',
                      style: ResponsiveHelper.smallStyle(
                        context,
                        color: Colors.grey[700],
                      ),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 8),
                        vertical: ResponsiveHelper.spacing(context, 2),
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.green[200]!),
                      ),
                      child: Text(
                        '확정됨',
                        style: ResponsiveHelper.tinyStyle(
                          context,
                          color: Colors.green[700],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 10)),
          
          // 안내 문구
          Row(
            children: [
              Icon(
                Icons.info_outline, 
                size: ResponsiveHelper.iconSize(context, 14), 
                color: Colors.orange[600]
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              Expanded(
                child: Text(
                  '위 근무가 확정되어 자동으로 취소되었습니다.',
                  style: ResponsiveHelper.smallStyle(
                    context,
                    color: Colors.grey[700],
                  ),
                ),
              ),
            ],
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          
          // 재지원 안내
          Container(
            padding: ResponsiveHelper.cardPadding(context),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.touch_app, 
                  size: ResponsiveHelper.iconSize(context, 14), 
                  color: Colors.blue[700]
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                Expanded(
                  child: Text(
                    '다른 시간대 공고에는 다시 지원 가능합니다',
                    style: ResponsiveHelper.smallStyle(
                      context,
                      color: Colors.blue[800],
                      fontWeight: FontWeight.w500,
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
        Icon(
          icon, 
          size: ResponsiveHelper.iconSize(context, 16), 
          color: Colors.grey[600]
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        Text(
          '$label: ',
          style: ResponsiveHelper.bodyStyle(
            context,
            color: Colors.grey[700],
          ).copyWith(fontWeight: FontWeight.w600),
        ),
        Expanded(
          child: Text(
            value,
            style: ResponsiveHelper.bodyStyle(
              context,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  /// 상태 배지
  Widget _buildStatusBadge(String status) {
    switch (status) {
      case 'PENDING':
        return StyledBadge(
          label: '대기중',
          backgroundColor: Colors.orange.shade50,
          textColor: Colors.orange.shade700,
          fontSize: ResponsiveHelper.getFontSize(context, 12),
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 12),
            vertical: ResponsiveHelper.spacing(context, 6),
          ),
        );
      case 'CONFIRMED':
        return StyledBadge(
          label: '확정',
          backgroundColor: Colors.green.shade50,
          textColor: Colors.green.shade700,
          fontSize: ResponsiveHelper.getFontSize(context, 12),
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 12),
            vertical: ResponsiveHelper.spacing(context, 6),
          ),
        );
      case 'REJECTED':
        return StyledBadge(
          label: '거절',
          backgroundColor: Colors.red.shade50,
          textColor: Colors.red.shade700,
          fontSize: ResponsiveHelper.getFontSize(context, 12),
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 12),
            vertical: ResponsiveHelper.spacing(context, 6),
          ),
        );
      case 'CANCELED':
        return StyledBadge(
          label: '취소',
          backgroundColor: Colors.grey.shade100,
          textColor: Colors.grey.shade600,
          fontSize: ResponsiveHelper.getFontSize(context, 12),
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 12),
            vertical: ResponsiveHelper.spacing(context, 6),
          ),
        );
      case 'AUTO_CANCELED':
        return StyledBadge(
          label: '자동 취소',
          backgroundColor: Colors.orange.shade50,
          textColor: Colors.orange.shade700,
          fontSize: ResponsiveHelper.getFontSize(context, 12),
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 12),
            vertical: ResponsiveHelper.spacing(context, 6),
          ),
        );
      default:
        return StyledBadge(
          label: '알 수 없음',
          backgroundColor: Colors.grey.shade100,
          textColor: Colors.grey.shade600,
          fontSize: ResponsiveHelper.getFontSize(context, 12),
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 12),
            vertical: ResponsiveHelper.spacing(context, 6),
          ),
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