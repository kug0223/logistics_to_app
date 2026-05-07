import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// Models
import '../../../models/core/to_model.dart';
import '../../../models/core/work_detail_model.dart';
import '../../../models/core/application_model.dart';

// Services
import '../../../services/firestore_service.dart';

// Utils
import '../../../utils/responsive_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/navigation_helper.dart';
import '../../../utils/toast_helper.dart';

// Theme
import '../../../theme/app_colors.dart';
import '../../common/loading_button.dart';

// Widgets
import '../../work_type_icon.dart';

// Screens
import '../../../screens/common/job_posting_screen.dart';
import '../../dialogs/apply/apply_work_dialog.dart';

/// 지원자용 TO 카드 위젯
/// 
/// 디자인 원칙:
/// - 접힌 상태: 핵심 정보만 (배지, 사업장, 제목, 지역, 날짜, 급여)
/// - 펼친 상태: 업무 목록 + 상세보기/지원하기 버튼
/// - 왼쪽 컬러바: 단기(파랑) / 장기(보라) 구분
class UserTOCard extends StatefulWidget {
  final TOModel to;
  final bool isSelected;
  final VoidCallback onTap;
  final List<ApplicationModel> myApplications;
  final VoidCallback onApplySuccess;

  const UserTOCard({
    super.key,
    required this.to,
    required this.isSelected,
    required this.onTap,
    required this.myApplications,
    required this.onApplySuccess,
  });

  @override
  State<UserTOCard> createState() => _UserTOCardState();
}

class _UserTOCardState extends State<UserTOCard> {
  final FirestoreService _firestoreService = FirestoreService();
  List<WorkDetailModel> _workDetails = [];
  bool _isLoadingWorkDetails = false;

  // 날짜별 workDetails 캐시 (toId → workDetails)
  final Map<String, List<WorkDetailModel>> _workDetailsCache = {};

  @override
  void didUpdateWidget(UserTOCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isSelected && !oldWidget.isSelected) {
      _loadWorkDetails();
    }

    if (!widget.isSelected && oldWidget.isSelected) {
      _workDetails = [];
    }
  }

  /// 현재 업무 개수
  int get _currentWorkCount {
    // workDetails 로드됐으면 그거 사용
    if (_workDetails.isNotEmpty) {
      return _workDetails.length;
    }
    // 아니면 TOModel의 workDetailCount 사용
    return widget.to.workDetailCount > 0 ? widget.to.workDetailCount : 1;
  }
  /// 업무 상세 로드
  Future<void> _loadWorkDetails() async {
    // 캐시에 있으면 바로 사용
    if (_workDetailsCache.containsKey(widget.to.id)) {
      setState(() {
        _workDetails = _workDetailsCache[widget.to.id]!;
      });
      return;
    }
    
    if (_workDetails.isNotEmpty) return;
    
    setState(() => _isLoadingWorkDetails = true);
    
    try {
      final workDetails = await _firestoreService.getWorkDetails(widget.to.id);
      
      if (mounted) {
        // 캐시에 저장
        _workDetailsCache[widget.to.id] = workDetails;
        
        setState(() {
          _workDetails = workDetails;
          _isLoadingWorkDetails = false;
        });
      }
    } catch (e) {
      debugPrint('❌ 업무 로드 실패: $e');
      if (mounted) {
        setState(() => _isLoadingWorkDetails = false);
      }
    }
  }

  //// 내가 해당 TO에 지원했는지 확인
  bool get _hasAppliedToTO {
    return widget.myApplications.any((app) {
      final isActive = app.status != 'CANCELED' &&
                       app.status != 'REJECTED' &&
                       app.status != 'AUTO_CANCELED';

      if (!isActive) return false;

      if (app.isLongTermApplication) {
        if (app.resignStatus == 'APPROVED' || app.resignStatus == 'AUTO_APPROVED' ||
            app.terminationStatus == 'APPROVED' || app.terminationStatus == 'AUTO_APPROVED') {
          return false;
        }
      }

      if (app.toId != null && app.toId!.isNotEmpty) {
        return app.toId == widget.to.id;
      }

      final businessMatch = app.businessId == widget.to.businessId;
      final titleMatch = app.toTitle == widget.to.title;

      if (widget.to.isLongTerm) {
        return businessMatch && titleMatch;
      }

      final dateMatch = app.workDate.year == widget.to.date.year &&
                        app.workDate.month == widget.to.date.month &&
                        app.workDate.day == widget.to.date.day;
      return dateMatch && businessMatch && titleMatch;
    });
  }

  /// 내가 해당 업무에 지원했는지 확인
  bool _hasAppliedToWork(String workType) {
    final targetDate = widget.to.date;

    return widget.myApplications.any((app) {
      final dateMatch = app.workDate.year == targetDate.year &&
                        app.workDate.month == targetDate.month &&
                        app.workDate.day == targetDate.day;
      final businessMatch = app.businessId == widget.to.businessId;
      final titleMatch = app.toTitle == widget.to.title;
      final workTypeMatch = app.selectedWorkType == workType;
      final isActive = app.status != 'CANCELED' && 
                       app.status != 'REJECTED' &&
                       app.status != 'AUTO_CANCELED';
      
      if (!isActive) return false;
      
      // 🔥 장기공고: 퇴사/해지 완료된 경우 미지원 취급
      if (app.isLongTermApplication) {
        if (app.resignStatus == 'APPROVED' || app.resignStatus == 'AUTO_APPROVED' ||
            app.terminationStatus == 'APPROVED' || app.terminationStatus == 'AUTO_APPROVED') {
          return false;
        }
      }
      
      return dateMatch && businessMatch && titleMatch && workTypeMatch;
    });
  }
  ApplicationModel? _getApplicationForWork(String workType) {
    final targetTO = widget.to;
    
    try {
      return widget.myApplications.firstWhere(
        (app) {
          final workTypeMatch = app.selectedWorkType == workType;
          final isActive = app.status != 'CANCELED' && 
                           app.status != 'REJECTED' &&
                           app.status != 'AUTO_CANCELED';
          
          if (!workTypeMatch || !isActive) return false;
          
          // 🔥 장기공고: 퇴사/해지 완료된 경우 미지원 취급
          if (app.isLongTermApplication) {
            if (app.resignStatus == 'APPROVED' || app.resignStatus == 'AUTO_APPROVED' ||
                app.terminationStatus == 'APPROVED' || app.terminationStatus == 'AUTO_APPROVED') {
              return false;
            }
          }
          
          // ✅ toId가 있으면 정확히 매칭 (신규 데이터)
          if (app.toId != null && app.toId!.isNotEmpty) {
            return app.toId == targetTO.id;
          }
          
          // ✅ toId 없으면 기존 로직 (레거시 데이터 호환)
          final dateMatch = app.workDate.year == targetTO.date.year &&
                            app.workDate.month == targetTO.date.month &&
                            app.workDate.day == targetTO.date.day;
          final businessMatch = app.businessId == targetTO.businessId;
          final titleMatch = app.toTitle == targetTO.title;
          return dateMatch && businessMatch && titleMatch;
        },
      );
    } catch (e) {
      return null;
    }
  }
  /// 급여 타입 라벨
  String _getWageTypeLabel() {
    // TOModel에서 직접 가져오기
    if (widget.to.wageType != null) {
      return FormatHelper.getWageTypeLabel(widget.to.wageType!);
    }
    // fallback: workDetails에서
    if (_workDetails.isNotEmpty) {
      return FormatHelper.getWageTypeLabel(_workDetails.first.wageType);
    }
    return '급여';
  }

  /// 급여 금액만 (타입 제외)
  String _getWageAmount() {
    // TOModel에서 직접 가져오기
    if (widget.to.maxWage != null) {
      if (widget.to.minWage == widget.to.maxWage) {
        return FormatHelper.formatWage(widget.to.maxWage!);
      }
      return '~${FormatHelper.formatNumber(widget.to.maxWage!)}원';
    }
    
    // fallback: workDetails에서
    if (_workDetails.isNotEmpty) {
      final wages = _workDetails.map((w) => w.wage).toList();
      final minWage = wages.reduce((a, b) => a < b ? a : b);
      final maxWage = wages.reduce((a, b) => a > b ? a : b);
      
      if (minWage == maxWage) {
        return FormatHelper.formatWage(maxWage);
      }
      return '~${FormatHelper.formatNumber(maxWage)}원';
    }
    
    return '-';
  }


  /// 지역 텍스트 (시/구 + 동)
  String _getLocationText() {
    return FormatHelper.formatLocation(
      address: widget.to.businessAddress,
      city: widget.to.businessCity,
      district: widget.to.businessDistrict,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLongTerm = widget.to.isLongTerm;
    final barColor = isLongTerm ? AppColors.longTerm : AppColors.shortTerm;
    
    // ✅ 예약 공개 대기 중인지 확인
    final isPendingPublish = widget.to.isPendingPublish;
    
    return Opacity(
      opacity: isPendingPublish ? 0.6 : 1.0,
      child: Card(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
      elevation: widget.isSelected ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: widget.isSelected 
              ? theme.primaryColor 
              : AppColors.border,
          width: widget.isSelected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // 🎨 왼쪽 컬러바 (Stack으로 전체 높이 차지)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: ResponsiveHelper.spacing(context, 6),
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
            ),
          ),
          
          // 본문 (컬러바 너비만큼 padding)
          Padding(
            padding: EdgeInsets.only(left: ResponsiveHelper.spacing(context, 6)),
            child: InkWell(
              onTap: widget.onTap,
              child: Container(
                decoration: BoxDecoration(
                  color: widget.isSelected
                      ? theme.primaryColor.withValues(alpha: 0.03)
                      : Colors.white,
                ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ═══════════════════════════════════════════════════
                      // 접힌 상태 (항상 표시)
                      // ═══════════════════════════════════════════════════
                      Padding(
                        padding: ResponsiveHelper.cardPadding(context),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1️⃣ 배지 + 위치
                            _buildBadgeAndLocation(context),
                            
                            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                            
                            // 2️⃣ 제목 (2줄까지)
                            _buildTitle(context),
                            
                            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                            
                            // 3️⃣ 날짜
                            _buildDateRow(context),
                            
                            SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                            
                            // 4️⃣ 사업장 + 등록시간
                            _buildBusinessAndTime(context),
                            
                            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                            
                            // 5️⃣ 급여 + 업무 개수
                            _buildWageAndWorkCount(context),
                          ],
                        ),
                      ),
                      
                      // 펼침 아이콘
                      _buildExpandIcon(context),
                      
                      // ═══════════════════════════════════════════════════
                      // 펼친 상태 (애니메이션 적용)
                      // ═══════════════════════════════════════════════════
                      AnimatedSize(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        clipBehavior: Clip.hardEdge,
                        child: widget.isSelected
                            ? Column(
                                children: [
                                  Divider(height: 1, color: AppColors.border),
                                  _buildExpandedContent(context),
                                ],
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );    // ✅ Opacity 닫기
  }

  /// 1️⃣ 배지 + 위치
  Widget _buildBadgeAndLocation(BuildContext context) {
    final theme = Theme.of(context);
    final locationText = _getLocationText();
    
    return Row(
      children: [
        // 단기/장기 배지
        _buildJobTypeBadge(context),
        
        SizedBox(width: ResponsiveHelper.spacing(context, 10)),
        
        // 위치 (강조)
        Icon(
          Icons.location_on,
          size: ResponsiveHelper.iconSize(context, 16),
          color: theme.primaryColor,
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
        Expanded(
          child: Text(
            locationText.isNotEmpty ? locationText : '위치 미정',
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              fontWeight: FontWeight.w600,
              color: theme.primaryColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        
        // 지원완료 배지 (지원했으면)
        if (_hasAppliedToTO) ...[
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          _buildAppliedBadge(context),
        ],
      ],
    );
  }
  /// 오픈 대기 버튼 (예약 공개 대기 중)
  Widget _buildPendingButton(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: ResponsiveHelper.spacing(context, 12),
      ),
      decoration: BoxDecoration(
        color: AppColors.grey200,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.lock_outline,
            size: ResponsiveHelper.iconSize(context, 18),
            color: AppColors.grey500,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          Text(
            '오픈 후 지원가능',
            style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey500),
          ),
        ],
      ),
    );
  }

  /// 단기/장기 배지
  Widget _buildJobTypeBadge(BuildContext context) {
    final isLongTerm = widget.to.isLongTerm;
    
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 10),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      decoration: BoxDecoration(
        color: isLongTerm ? AppColors.longTermBg : AppColors.shortTermBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isLongTerm ? AppColors.longTermLight : AppColors.shortTermLight,
        ),
      ),
      child: Text(
        isLongTerm ? '고정' : '단기',
        style: ResponsiveHelper.smallStyle(
          context,
          color: isLongTerm ? AppColors.longTermDark : AppColors.shortTermDark,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// 지원완료 배지
  Widget _buildAppliedBadge(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 3),
      ),
      decoration: BoxDecoration(
        color: AppColors.successBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.successLight),
      ),
      child: Text(
        '지원완료',
        style: ResponsiveHelper.tinyStyle(
          context,
          color: AppColors.successDark,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// 2️⃣ 제목 (2줄까지)
  Widget _buildTitle(BuildContext context) {
    return Text(
      widget.to.title,
      style: ResponsiveHelper.titleStyle(context).copyWith(
        fontWeight: FontWeight.bold,
        height: 1.3,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// 3️⃣ 날짜
  Widget _buildDateRow(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.calendar_today,
          size: ResponsiveHelper.iconSize(context, 16),
          color: AppColors.grey600,
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
        Expanded(
          child: Text(
            _getDateText(),
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
  
  /// 4️⃣ 사업장 + 등록시간
  Widget _buildBusinessAndTime(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.business_outlined,
          size: ResponsiveHelper.iconSize(context, 14),
          color: AppColors.grey500,
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
        Expanded(
          child: Text(
            widget.to.businessName,
            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // 등록시간 (우측)
        Text(
          _getTimeAgo(),
          style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500),
        ),
      ],
    );
  }
  
  /// 등록시간 포맷 (몇 분/시간/일 전)
  String _getTimeAgo() {
    final createdAt = widget.to.createdAt;
    final now = DateTime.now();
    final diff = now.difference(createdAt);
    
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}분전';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}시간전';
    } else {
      return '${diff.inDays}일전';
    }
  }
  
  /// 날짜 텍스트 포맷
  String _getDateText() {
    final to = widget.to;
    
    // 장기 공고
    if (to.isLongTerm && to.startDate != null && to.endDate != null) {
      final start = DateFormat('M/d(E)', 'ko_KR').format(to.startDate!);
      final end = DateFormat('M/d(E)', 'ko_KR').format(to.endDate!);
      final workDaysLabel = to.workDays != null && to.workDays!.isNotEmpty
          ? ' · ${to.workDaysLabel}'
          : '';
      return '$start~$end$workDaysLabel';
    }
    
    // 단일 TO
    return DateFormat('M/d(E)', 'ko_KR').format(to.date);
  }

  /// 4️⃣ 급여 + 업무 개수 + 버튼
  Widget _buildWageAndWorkCount(BuildContext context) {
    return Row(
      children: [
        // 급여타입 배지
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 6),
            vertical: ResponsiveHelper.spacing(context, 2),
          ),
          decoration: BoxDecoration(
            color: AppColors.successBg,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AppColors.successLight),
          ),
          child: Text(
            _getWageTypeLabel(),
            style: ResponsiveHelper.tinyStyle(
              context,
              color: AppColors.successDark,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 6)),
        // 금액
        Text(
          _getWageAmount(),
          style: ResponsiveHelper.subtitleStyle(context).copyWith(
            color: AppColors.successDark,
            fontWeight: FontWeight.bold,
          ),
        ),
        
        if (_workDetails.isNotEmpty) ...[
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Icon(
            Icons.work_outline,
            size: ResponsiveHelper.iconSize(context, 16),
            color: AppColors.grey600,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Text(
            '$_currentWorkCount개',
            style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey700),
          ),
        ],
        
        const Spacer(),
        
        // 상세 버튼
        _buildMiniButton(
          context,
          icon: Icons.info_outline,
          label: '상세',
          onTap: _goToJobPosting,
          isPrimary: false,
        ),
        
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        
        // 지원 버튼
        _buildMiniButton(
          context,
          icon: _hasAppliedToTO ? Icons.settings : Icons.send,
          label: _hasAppliedToTO ? '지원관리' : '지원하기',
          onTap: _openApplyDialog,
          isPrimary: !_hasAppliedToTO,
        ),
      ],
    );
  }

  /// 미니 버튼
  Widget _buildMiniButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool isPrimary = true,
  }) {
    final theme = Theme.of(context);
    final isDisabled = onTap == null;
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 10),
          vertical: ResponsiveHelper.spacing(context, 6),
        ),
        decoration: BoxDecoration(
          color: isDisabled 
              ? AppColors.grey200
              : isPrimary 
                  ? theme.primaryColor 
                  : AppColors.grey100,
          borderRadius: BorderRadius.circular(6),
          border: isPrimary || isDisabled
              ? null 
              : Border.all(color: AppColors.grey300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: ResponsiveHelper.iconSize(context, 14),
              color: isDisabled
                  ? AppColors.grey500
                  : isPrimary 
                      ? Colors.white 
                      : AppColors.grey700,
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 4)),
            Text(
              label,
              style: ResponsiveHelper.smallStyle(
                context,
                color: isDisabled
                    ? AppColors.grey500
                    : isPrimary 
                        ? Colors.white 
                        : AppColors.grey700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 펼침 아이콘
  Widget _buildExpandIcon(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: ResponsiveHelper.spacing(context, 8),
        ),
        child: Icon(
          widget.isSelected 
              ? Icons.keyboard_arrow_up 
              : Icons.keyboard_arrow_down,
          size: ResponsiveHelper.iconSize(context, 20),
          color: AppColors.grey500,
        ),
      ),
    );
  }

  /// 펼친 상태 컨텐츠
  Widget _buildExpandedContent(BuildContext context) {
    final isPendingPublish = widget.to.isPendingPublish;

    return Padding(
      padding: ResponsiveHelper.cardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isPendingPublish) ...[
            _buildPendingPublishNotice(context, widget.to),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          ],

          Opacity(
            opacity: isPendingPublish ? 0.4 : 1.0,
            child: _buildWorkDetailsList(context),
          ),
        ],
      ),
    );
  }
  /// ✅ 예약 공개 대기 메시지
  Widget _buildPendingPublishNotice(BuildContext context, TOModel to) {
    final publishAt = to.publishAt;
    final displayText = publishAt != null 
        ? '${publishAt.month}/${publishAt.day} ${publishAt.hour.toString().padLeft(2, '0')}:${publishAt.minute.toString().padLeft(2, '0')}에 오픈됩니다'
        : '곧 오픈 예정입니다';
    
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warningLight),
      ),
      child: Row(
        children: [
          Icon(
            Icons.schedule,
            size: ResponsiveHelper.iconSize(context, 18),
            color: AppColors.warningDark,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 10)),
          Expanded(
            child: Text(
              displayText,
              style: ResponsiveHelper.bodyStyle(context, color: AppColors.warningDark).copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 업무 목록
  Widget _buildWorkDetailsList(BuildContext context) {
    // ✅ 로딩 중이어도 이전 데이터 있으면 그대로 표시 + 오버레이 로딩
    if (_isLoadingWorkDetails && _workDetails.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
          child: SizedBox(
            width: ResponsiveHelper.spacing(context, 24),
            height: ResponsiveHelper.spacing(context, 24),
            child: const CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_workDetails.isEmpty) {
      return Text(
        '업무 정보가 없습니다',
        style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey500),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _workDetails.map((work) {
        final application = _getApplicationForWork(work.workType);
        return _buildWorkDetailItem(context, work, application);
      }).toList(),
    );
  }

  /// 업무 상세 아이템
  Widget _buildWorkDetailItem(
    BuildContext context, 
    WorkDetailModel work, 
    ApplicationModel? application,
  ) {
    final hasApplied = application != null && application.id.isNotEmpty;
    final isConfirmed = application?.status == 'CONFIRMED';
    
    // ✅ 마감 여부 판단 (지원하지 않은 경우만 비활성화)
    final isClosed = !hasApplied && (work.isClosed || work.isTimeExpired || work.isFull);
    
    return Opacity(
      opacity: isClosed ? 0.5 : 1.0,
      child: Container(
        margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
        padding: ResponsiveHelper.cardPadding(context),
        decoration: BoxDecoration(
          color: isConfirmed 
              ? AppColors.successBg 
              : (hasApplied ? AppColors.infoBg : AppColors.grey100),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isConfirmed 
                ? AppColors.successLight 
                : (hasApplied ? AppColors.infoLight : AppColors.grey300),
          ),
        ),
      child: Row(
        children: [
          // 업무 아이콘
          WorkTypeIcon.buildWithBackground(
            iconString: work.workTypeIcon,
            iconColor: work.workTypeColor,
            backgroundColor: work.workTypeBackgroundColor,
            containerSize: ResponsiveHelper.spacing(context, 36),
            size: ResponsiveHelper.iconSize(context, 18),
          ),
          
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          
          // 업무 정보
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 업무명
                Text(
                  work.workType,
                  style: ResponsiveHelper.subtitleStyle(context).copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                // 시간 + 급여
                Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      size: ResponsiveHelper.iconSize(context, 12),
                      color: AppColors.grey500,
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 3)),
                    Text(
                      '${work.startTime}~${work.endTime}',
                      style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    // 급여타입 배지
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
                        FormatHelper.getWageTypeLabel(work.wageType),
                        style: ResponsiveHelper.tinyStyle(
                          context,
                          color: AppColors.successDark,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                    // 금액
                    Text(
                      FormatHelper.formatWage(work.wage),
                      style: ResponsiveHelper.smallStyle(context).copyWith(
                        color: AppColors.successDark,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // 상태 배지
          _buildWorkStatusBadge(context, work, application),
        ],
      ),
      ),  // ✅ Container 닫기
    );    // ✅ Opacity 닫기
  }
  /// 업무 상태 배지
  Widget _buildWorkStatusBadge(
    BuildContext context, 
    WorkDetailModel work, 
    ApplicationModel? application,
  ) {
    // ✅ 확정/대기 구분
    if (application != null) {
      if (application.status == 'CONFIRMED') {
        return _buildStatusChip(context, '확정', AppColors.success, Colors.white);
      }
      return _buildStatusChip(context, '대기중', AppColors.info, Colors.white);
    }
    
    // ✅ 장기 공고: TO의 applicationDeadline 기준
    if (widget.to.isLongTerm) {
      if (widget.to.isManualClosed) {
        return _buildStatusChip(context, '마감', AppColors.grey500, Colors.white);
      }
      if (widget.to.isDeadlinePassed) {
        return _buildStatusChip(context, '마감', AppColors.grey500, Colors.white);
      }
      if (work.isFull) {
        return _buildStatusChip(context, '마감', AppColors.grey500, Colors.white);
      }
      // 긴급모집
      if (work.isEmergencyOpen) {
        return _buildStatusChip(context, '긴급', AppColors.error, Colors.white);
      }
      return _buildStatusChip(context, '모집중', AppColors.successBg, AppColors.successDark);
    }
    
    // ✅ 단기 공고: WorkDetail 기준
    if (work.isClosed || work.isTimeExpired || work.isFull) {
      return _buildStatusChip(context, '마감', AppColors.grey500, Colors.white);
    }
    
    // 긴급모집
    if (work.isEmergencyOpen) {
      return _buildStatusChip(context, '긴급', AppColors.error, Colors.white);
    }
    
    // 모집중
    return _buildStatusChip(context, '모집중', AppColors.successBg, AppColors.successDark);
  }

  Widget _buildStatusChip(
    BuildContext context,
    String label,
    Color bgColor,
    Color textColor,
  ) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: ResponsiveHelper.tinyStyle(
          context,
          color: textColor,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
  

  /// 상세보기 화면 이동
  void _goToJobPosting() async {
    List<WorkDetailModel> workDetailsToPass = _workDetails;

    if (workDetailsToPass.isEmpty) {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      try {
        workDetailsToPass = await _firestoreService.getWorkDetails(widget.to.id);
      } catch (e) {
        if (mounted) Navigator.pop(context);
        ToastHelper.showError('데이터를 불러오는데 실패했습니다');
        return;
      }

      if (mounted) Navigator.pop(context);
    }

    if (!mounted) return;
    NavigationHelper.push(
      context,
      destination: JobPostingScreen(
        to: widget.to,
        workDetails: workDetailsToPass,
      ),
    );
  }

  /// 지원 다이얼로그 열기
  void _openApplyDialog() async {
    if (_workDetails.isEmpty) {
      await _loadWorkDetails();
    }

    if (_workDetails.isEmpty) return;

    final result = await ApplyWorkDialog.show(
      context: context,
      to: widget.to,
      workDetails: _workDetails,
      businessName: widget.to.businessName,
    );

    if (result?.hasChanges == true && mounted) {
      _workDetailsCache.clear();
      widget.onApplySuccess();
      setState(() {});
    }
  }
}