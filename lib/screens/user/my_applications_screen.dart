import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../models/core/application_model.dart';
import '../../models/core/to_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/work_type_icon.dart';
import '../../utils/toast_helper.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/format_helper.dart';
import '../../theme/app_colors.dart';

/// 내 지원 내역 화면 (리팩토링 버전)
class MyApplicationsScreen extends StatefulWidget {
  const MyApplicationsScreen({super.key});

  @override
  State<MyApplicationsScreen> createState() => _MyApplicationsScreenState();
}

class _MyApplicationsScreenState extends State<MyApplicationsScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  List<_ApplicationWithTO> _applications = [];
  bool _isLoading = true;
  String _selectedFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    _loadApplications();
  }

  Future<void> _loadApplications() async {
    setState(() => _isLoading = true);

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;

      if (uid == null) {
        ToastHelper.showError('로그인이 필요합니다.');
        return;
      }

      // ✅ 1. 만료된 PENDING 자동 처리 (병렬 실행 - 메인 로직과 동시)
      //       실패해도 무관하므로 await 없이 시작만 해도 되지만,
      //       정확한 목록을 위해 먼저 완료 후 조회
      await _firestoreService.autoExpirePendingApplications(uid);

      // ✅ 2. 최신 지원 내역 조회
      final applications = await _firestoreService.getMyApplications(uid);

      // ✅ 3. TO 정보 병렬 조회
      final futures = applications.map((app) async {
        final to = await _firestoreService.getTOByApplication(app);
        if (to != null) {
          return _ApplicationWithTO(application: app, to: to);
        }
        return null;
      }).toList();

      final results = await Future.wait(futures);
      final appWithTOs = results.whereType<_ApplicationWithTO>().toList();
      appWithTOs.sort(
          (a, b) => b.application.appliedAt.compareTo(a.application.appliedAt));

      if (mounted) {
        setState(() {
          _applications = appWithTOs;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ 지원 내역 로드 실패: $e');
      if (mounted) {
        ToastHelper.showError('지원 내역을 불러오는데 실패했습니다.');
        setState(() => _isLoading = false);
      }
    }
  }

  List<_ApplicationWithTO> get _filteredApplications {
    if (_selectedFilter == 'ALL') return _applications;
    return _applications.where((item) {
      final status = item.application.status;
      if (_selectedFilter == 'CANCELED') {
        return status == 'CANCELED' || status == 'AUTO_CANCELED';
      }
      return status == _selectedFilter;
    }).toList();
  }

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

    final success = await _firestoreService.cancelApplication(applicationId, uid);
    if (success && mounted) {
      ToastHelper.showSuccess('지원이 취소되었습니다.');
      _loadApplications();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('내 지원 내역'),
        backgroundColor: theme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadApplications,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterSection(),
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
                            return _buildApplicationCard(_filteredApplications[index]);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 필터 섹션
  // ═══════════════════════════════════════════════════════════

  Widget _buildFilterSection() {
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: ResponsiveHelper.spacing(context, 12),
      ),
      color: AppColors.grey100,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 16),
          ),
          child: Row(
            children: [
              _buildFilterChip('전체', 'ALL', Icons.list_alt, AppColors.info),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              _buildFilterChip('대기중', 'PENDING', Icons.schedule, AppColors.warning),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              _buildFilterChip('확정', 'CONFIRMED', Icons.check_circle, AppColors.success),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              _buildFilterChip('거절', 'REJECTED', Icons.cancel, AppColors.error),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              _buildFilterChip('취소', 'CANCELED', Icons.remove_circle_outline, AppColors.grey500),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, IconData icon, Color color) {
    final isSelected = _selectedFilter == value;

    return FilterChip(
      avatar: Icon(
        icon,
        size: ResponsiveHelper.iconSize(context, 16),
        color: isSelected ? color : AppColors.grey500,
      ),
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _selectedFilter = value),
      backgroundColor: Colors.white,
      selectedColor: color.withValues(alpha: 0.15),
      side: BorderSide(
        color: isSelected ? color : AppColors.grey300,
        width: isSelected ? 1.5 : 1,
      ),
      checkmarkColor: color,
      labelStyle: ResponsiveHelper.smallStyle(context).copyWith(
        color: isSelected ? color : AppColors.grey700,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 6),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 빈 상태
  // ═══════════════════════════════════════════════════════════

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.assignment_outlined,
            size: ResponsiveHelper.iconSize(context, 80),
            color: AppColors.grey400,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          Text(
            _selectedFilter == 'ALL' ? '지원 내역이 없습니다' : '해당 상태의 지원이 없습니다',
            style: ResponsiveHelper.titleStyle(context, color: AppColors.grey600),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Text(
            'TO에 지원해보세요!',
            style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey500),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 지원서 카드 (간소화된 디자인)
  // ═══════════════════════════════════════════════════════════

  Widget _buildApplicationCard(_ApplicationWithTO item) {
    final app = item.application;
    final to = item.to;
    final statusInfo = _getStatusInfo(app.status);

    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: statusInfo.color.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.grey300.withValues(alpha: 0.5),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            // TODO: 상세 다이얼로그 열기
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: ResponsiveHelper.cardPadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1줄: 사업장명 + 상태 배지
                _buildCardHeader(app, to, statusInfo),
                
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                
                // 2줄: TO 제목
                Text(
                  to.title,
                  style: ResponsiveHelper.subtitleStyle(context).copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                
                SizedBox(height: ResponsiveHelper.spacing(context, 10)),
                
                // 3줄: 근무일 · 근무시간
                _buildDateTimeRow(app, to),
                
                SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                
                // 4줄: 업무유형 · 급여
                _buildWorkWageRow(app),
                
                // 지원일
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                Text(
                  '지원일: ${DateFormat('yyyy.MM.dd HH:mm').format(app.appliedAt)}',
                  style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500),
                ),
                
                // 자동 취소인 경우 충돌 정보
                if (app.status == 'AUTO_CANCELED' && app.conflictingBusiness != null)
                  _buildAutoCanceledInfo(app),
                
                // 대기 중인 경우 취소 버튼
                if (app.status == 'PENDING')
                  _buildCancelButton(app),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardHeader(ApplicationModel app, TOModel to, _StatusInfo statusInfo) {
    return Row(
      children: [
        Icon(
          Icons.business,
          size: ResponsiveHelper.iconSize(context, 16),
          color: AppColors.grey600,
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 6)),
        Expanded(
          child: Text(
            to.businessName,
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        _buildStatusBadge(statusInfo),
      ],
    );
  }

  Widget _buildDateTimeRow(ApplicationModel app, TOModel to) {
    // ✅ 근무시간은 ApplicationModel에서 가져옴!
    final timeDisplay = (app.startTime.isNotEmpty && app.endTime.isNotEmpty)
        ? '${app.startTime} ~ ${app.endTime}'
        : '--:-- ~ --:--';
    
    return Row(
      children: [
        // 근무일
        Icon(
          Icons.calendar_today,
          size: ResponsiveHelper.iconSize(context, 14),
          color: AppColors.grey500,
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
        Text(
          FormatHelper.formatDateLong(app.workDate),
          style: ResponsiveHelper.smallStyle(context, color: AppColors.grey700),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
        // 근무시간
        Icon(
          Icons.access_time,
          size: ResponsiveHelper.iconSize(context, 14),
          color: AppColors.grey500,
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
        Text(
          timeDisplay,
          style: ResponsiveHelper.smallStyle(context, color: AppColors.grey700),
        ),
      ],
    );
  }

  Widget _buildWorkWageRow(ApplicationModel app) {
    return Row(
      children: [
        // 업무유형 아이콘
        if (app.workTypeIcon != null)
          WorkTypeIcon.buildWithBackground(
            iconString: app.workTypeIcon!,
            iconColor: app.workTypeColor,
            backgroundColor: app.workTypeBackgroundColor,
            size: ResponsiveHelper.iconSize(context, 14),
            containerSize: ResponsiveHelper.spacing(context, 24),
          )
        else
          Icon(
            Icons.work_outline,
            size: ResponsiveHelper.iconSize(context, 14),
            color: AppColors.grey500,
          ),
        SizedBox(width: ResponsiveHelper.spacing(context, 6)),
        Text(
          app.selectedWorkType,
          style: ResponsiveHelper.smallStyle(context, color: AppColors.grey700),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
        // 급여
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 8),
            vertical: ResponsiveHelper.spacing(context, 2),
          ),
          decoration: BoxDecoration(
            color: AppColors.successBg,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            app.formattedWage,
            style: ResponsiveHelper.smallStyle(
              context,
              color: AppColors.successDark,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(_StatusInfo statusInfo) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 10),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      decoration: BoxDecoration(
        color: statusInfo.bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        statusInfo.label,
        style: ResponsiveHelper.tinyStyle(
          context,
          color: statusInfo.color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// 자동 취소 충돌 정보 (간소화)
  Widget _buildAutoCanceledInfo(ApplicationModel app) {
    return Container(
      margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 10)),
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warningLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                size: ResponsiveHelper.iconSize(context, 16),
                color: AppColors.warningDark,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              Text(
                '시간 충돌로 자동 취소됨',
                style: ResponsiveHelper.smallStyle(
                  context,
                  color: AppColors.warningDark,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 6)),
          // 충돌 공고 정보 (한 줄로 간소화)
          Row(
            children: [
              Icon(
                Icons.business,
                size: ResponsiveHelper.iconSize(context, 12),
                color: AppColors.grey600,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
              Expanded(
                child: Text(
                  '${app.conflictingBusiness ?? ''} · ${app.conflictingTime ?? ''}',
                  style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 6),
                  vertical: ResponsiveHelper.spacing(context, 2),
                ),
                decoration: BoxDecoration(
                  color: AppColors.successBg,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '확정됨',
                  style: ResponsiveHelper.tinyStyle(
                    context,
                    color: AppColors.successDark,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 취소 버튼
  Widget _buildCancelButton(ApplicationModel app) {
    return Container(
      margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 10)),
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _cancelApplication(app.id),
        icon: Icon(
          Icons.close,
          size: ResponsiveHelper.iconSize(context, 16),
        ),
        label: Text(
          '지원 취소',
          style: ResponsiveHelper.smallStyle(context),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.error,
          side: const BorderSide(color: AppColors.error),
          padding: EdgeInsets.symmetric(
            vertical: ResponsiveHelper.spacing(context, 8),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 상태 정보 헬퍼
  // ═══════════════════════════════════════════════════════════

  _StatusInfo _getStatusInfo(String status) {
    switch (status) {
      case 'CONFIRMED':
        return _StatusInfo(
          label: '확정',
          color: AppColors.successDark,
          bgColor: AppColors.successBg,
        );
      case 'PENDING':
        return _StatusInfo(
          label: '대기중',
          color: AppColors.warningDark,
          bgColor: AppColors.warningBg,
        );
      case 'REJECTED':
        return _StatusInfo(
          label: '거절',
          color: AppColors.errorDark,
          bgColor: AppColors.errorBg,
        );
      case 'CANCELED':
        return _StatusInfo(
          label: '취소',
          color: AppColors.grey600,
          bgColor: AppColors.grey200,
        );
      case 'AUTO_CANCELED':
        return _StatusInfo(
          label: '자동 취소',
          color: AppColors.warningDark,
          bgColor: AppColors.warningBg,
        );
      default:
        return _StatusInfo(
          label: '알 수 없음',
          color: AppColors.grey600,
          bgColor: AppColors.grey200,
        );
    }
  }
}

// ═══════════════════════════════════════════════════════════
// 데이터 클래스
// ═══════════════════════════════════════════════════════════

class _ApplicationWithTO {
  final ApplicationModel application;
  final TOModel to;

  _ApplicationWithTO({
    required this.application,
    required this.to,
  });
}

class _StatusInfo {
  final String label;
  final Color color;
  final Color bgColor;

  _StatusInfo({
    required this.label,
    required this.color,
    required this.bgColor,
  });
}
