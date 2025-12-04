import 'package:flutter/material.dart';

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

// Theme
import '../../../theme/app_colors.dart';

// Widgets
import '../../work_type_icon.dart';

// Screens
import '../../../screens/common/job_posting_screen.dart';
import '../../../screens/user/dialogs/apply_dialog.dart';

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
  
  // 그룹 날짜 선택용
  List<TOModel> _groupTOs = [];
  TOModel? _selectedDateTO;
  bool _isLoadingGroupTOs = false;
  
  // 날짜별 workDetails 캐시 (toId → workDetails)
  final Map<String, List<WorkDetailModel>> _workDetailsCache = {};

  @override
  void didUpdateWidget(UserTOCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 선택 상태가 변경되면
    if (widget.isSelected && !oldWidget.isSelected) {
      // 그룹 TO면 날짜 목록 로드, 아니면 업무 로드
      if (_isGroupTO) {
        _loadGroupTOs();
      } else {
        _loadWorkDetails();
      }
    }
    
    // 접히면 선택 초기화
    if (!widget.isSelected && oldWidget.isSelected) {
      _selectedDateTO = null;
      _workDetails = [];
    }
  }

  /// 그룹 TO 여부
  bool get _isGroupTO => widget.to.groupId != null && !widget.to.isLongTerm;

  /// 업무 개수 표시 여부
  bool get _shouldShowWorkCount {
    // 그룹 단기 TO: 날짜 선택 후에만 표시
    if (_isGroupTO) {
      return _selectedDateTO != null && _workDetails.isNotEmpty;
    }
    // 장기 공고 또는 단일 TO: 항상 표시
    return true;
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

  /// 그룹 TO 날짜 목록 로드
  Future<void> _loadGroupTOs() async {
    if (widget.to.groupId == null) return;
    
    // 이미 로드됐으면 선택만 다시
    if (_groupTOs.isNotEmpty) {
      _autoSelectDate();
      return;
    }
    
    setState(() => _isLoadingGroupTOs = true);
    
    try {
      final groupTOs = await _firestoreService.getTOsByGroup(widget.to.groupId!);
      
      if (mounted) {
        setState(() {
          _groupTOs = groupTOs..sort((a, b) => a.date.compareTo(b.date));
          _isLoadingGroupTOs = false;
        });
        
        _autoSelectDate();
      }
    } catch (e) {
      debugPrint('❌ 그룹 TO 로드 실패: $e');
      if (mounted) {
        setState(() => _isLoadingGroupTOs = false);
      }
    }
  }
  /// 오늘 기준 가장 가까운 날짜 자동 선택
  void _autoSelectDate() {
    if (_groupTOs.isEmpty) return;
    
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    
    // 오늘 이후 날짜 중 가장 가까운 것
    final futureTO = _groupTOs.cast<TOModel?>().firstWhere(
      (to) => !to!.date.isBefore(todayOnly),
      orElse: () => null,
    );
    
    // 있으면 그거, 없으면 마지막 날짜 (과거 공고)
    _selectDate(futureTO ?? _groupTOs.last);
  }

  /// 날짜 선택
  Future<void> _selectDate(TOModel to) async {
    // 캐시에 있으면 바로 사용
    if (_workDetailsCache.containsKey(to.id)) {
      setState(() {
        _selectedDateTO = to;
        _workDetails = _workDetailsCache[to.id]!;
      });
      return;
    }
    
    // 캐시에 없으면 조회
    setState(() {
      _selectedDateTO = to;
      _workDetails = [];
      _isLoadingWorkDetails = true;
    });
    
    try {
      final workDetails = await _firestoreService.getWorkDetails(to.id);
      
      if (mounted) {
        // 캐시에 저장
        _workDetailsCache[to.id] = workDetails;
        
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
  

  /// 내가 해당 TO에 지원했는지 확인
  bool get _hasAppliedToTO {
    return widget.myApplications.any((app) {
      final dateMatch = app.workDate.year == widget.to.date.year &&
                        app.workDate.month == widget.to.date.month &&
                        app.workDate.day == widget.to.date.day;
      final businessMatch = app.businessId == widget.to.businessId;
      final titleMatch = app.toTitle == widget.to.title;
      final isActive = app.status != 'CANCELED' && 
                       app.status != 'REJECTED' &&
                       app.status != 'AUTO_CANCELED';
      return dateMatch && businessMatch && titleMatch && isActive;
    });
  }

  /// 내가 해당 업무에 지원했는지 확인
  bool _hasAppliedToWork(String workType) {
    return widget.myApplications.any((app) {
      final dateMatch = app.workDate.year == widget.to.date.year &&
                        app.workDate.month == widget.to.date.month &&
                        app.workDate.day == widget.to.date.day;
      final businessMatch = app.businessId == widget.to.businessId;
      final titleMatch = app.toTitle == widget.to.title;
      final workTypeMatch = app.selectedWorkType == workType;
      final isActive = app.status != 'CANCELED' && 
                       app.status != 'REJECTED' &&
                       app.status != 'AUTO_CANCELED';
      return dateMatch && businessMatch && titleMatch && workTypeMatch && isActive;
    });
  }
  /// 급여 타입 라벨
  String _getWageTypeLabel() {
    // TOModel에서 직접 가져오기
    if (widget.to.wageType != null) {
      return FormatHelper.getWageTypeLabel(widget.to.wageType!);
    }
    // fallback: workDetails에서
    if (_workDetails.isNotEmpty) {
      return FormatHelper.getWageTypeLabel(_workDetails.first.wageType ?? 'hourly');
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

  /// 급여 범위 계산 (workDetails에서)
  String _getWageRange() {
    if (_workDetails.isEmpty) {
      // workDetails 로드 전에는 TO의 정보 사용
      return FormatHelper.formatWageWithType(
        widget.to.totalRequired > 0 ? 10030 : 0, // 기본값
        'hourly',
      );
    }
    
    final wages = _workDetails.map((w) => w.wage).toList();
    final minWage = wages.reduce((a, b) => a < b ? a : b);
    final maxWage = wages.reduce((a, b) => a > b ? a : b);
    
    // wageType은 첫 번째 workDetail에서 가져옴 (보통 동일)
    final wageType = _workDetails.first.wageType ?? 'hourly';
    
    return FormatHelper.formatWageRange(minWage, maxWage, wageType);
  }

  String _getWorkPeriodText() {
    final startDate = widget.to.startDate ?? widget.to.date;
    final endDate = widget.to.endDate;
    final isLongTerm = widget.to.isLongTerm;
    final isGrouped = widget.to.groupId != null && endDate != null;
    
    // 날짜 부분
    String dateText;
    if (isLongTerm) {
      // 장기: 시작~끝 또는 시작~ 장기
      if (endDate != null) {
        dateText = '${FormatHelper.formatDateCompact(startDate)}~${FormatHelper.formatDateCompact(endDate)}';
      } else {
        dateText = '${FormatHelper.formatDateCompact(startDate)}~ 장기';
      }
    } else if (isGrouped) {
      // 그룹 단기: 시작~끝 표시
      dateText = '${FormatHelper.formatDateCompact(startDate)}~${FormatHelper.formatDateCompact(endDate!)}';
    } else {
      // 단일 단기: 날짜 하나만
      dateText = FormatHelper.formatDateCompact(widget.to.date);
    }
    
    // 요일 부분 (장기일 때만)
    if (isLongTerm && widget.to.workDays != null && widget.to.workDays!.isNotEmpty) {
      final workDaysText = FormatHelper.formatWorkDays(widget.to.workDays);
      return '$dateText · $workDaysText';
    }
    
    return dateText;
  }

  /// 지역 텍스트 (시/구 + 동)
  String _getLocationText() {
    return FormatHelper.formatLocation(
      address: widget.to.businessAddress,
      city: widget.to.businessCity,
      district: widget.to.businessDistrict,
    );
  }
  /// 등록일 텍스트
  String _getCreatedAtText() {
    final now = DateTime.now();
    final created = widget.to.createdAt;
    final diff = now.difference(created);
    
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}분 전';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}시간 전';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}일 전';
    } else {
      return '${created.month}/${created.day}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLongTerm = widget.to.isLongTerm;
    final barColor = isLongTerm ? AppColors.longTerm : AppColors.shortTerm;
    
    return Card(
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
      child: IntrinsicHeight(
        child: Row(
          children: [
            // 🎨 왼쪽 컬러바
            Container(
              width: ResponsiveHelper.spacing(context, 6),
              decoration: BoxDecoration(
                color: barColor,
              ),
            ),
            
            // 본문
            Expanded(
              child: InkWell(
                onTap: widget.onTap,
                child: Container(
                  decoration: BoxDecoration(
                    color: widget.isSelected
                        ? theme.primaryColor.withOpacity(0.03)
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
                            // 1️⃣ 첫 줄: 배지 + 사업장명
                            _buildFirstRow(context),
                            
                            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                            
                            // 2️⃣ 제목 (2줄까지)
                            _buildTitle(context),
                            
                            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                            
                            // 3️⃣ 지역 + 날짜
                            _buildLocationAndDate(context),
                            
                            SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                            
                            // 4️⃣ 급여 + 업무 개수
                            _buildWageAndWorkCount(context),
                          ],
                        ),
                      ),
                      
                      // 펼침 아이콘
                      _buildExpandIcon(context),
                      
                      // ═══════════════════════════════════════════════════
                      // 펼친 상태
                      // ═══════════════════════════════════════════════════
                      if (widget.isSelected) ...[
                        Divider(height: 1, color: AppColors.border),
                        _buildExpandedContent(context),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 1️⃣ 첫 줄: 배지 + 사업장명
  Widget _buildFirstRow(BuildContext context) {
    return Row(
      children: [
        // 단기/장기 배지
        _buildJobTypeBadge(context),
        
        SizedBox(width: ResponsiveHelper.spacing(context, 10)),
        
        // 사업장명 (1줄, 넘치면 말줄임)
        Expanded(
          child: Text(
            widget.to.businessName,
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              fontWeight: FontWeight.w600,
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

  /// 3️⃣ 지역 + 날짜 (두 줄)
  Widget _buildLocationAndDate(BuildContext context) {
    final locationText = _getLocationText();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 지역 + 등록일
        Row(
          children: [
            Icon(
              Icons.location_on_outlined,
              size: ResponsiveHelper.iconSize(context, 16),
              color: AppColors.grey600,
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 4)),
            Expanded(
              child: Text(
                locationText.isNotEmpty ? locationText : '-',
                style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey700),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 등록일
            Text(
              _getCreatedAtText(),
              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
            ),
          ],
        ),
        
        SizedBox(height: ResponsiveHelper.spacing(context, 4)),
        
        // 날짜
        Row(
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: ResponsiveHelper.iconSize(context, 16),
              color: AppColors.grey600,
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 4)),
            Expanded(
              child: Text(
                _getWorkPeriodText(),
                style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey700),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 4️⃣ 급여 + 업무 개수 + 버튼
  Widget _buildWageAndWorkCount(BuildContext context) {
    final theme = Theme.of(context);
    final workCount = widget.to.workDetailCount > 0
        ? widget.to.workDetailCount
        : _workDetails.isNotEmpty 
            ? _workDetails.length 
            : 1;
    
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
        
        // 업무 개수 (그룹 TO에서 날짜 선택 시 또는 단일/장기 TO)
        if (_shouldShowWorkCount) ...[
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Icon(
            Icons.work_outline,
            size: ResponsiveHelper.iconSize(context, 16),
            color: AppColors.grey600,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Text(
            '${_currentWorkCount}개',
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
          icon: _hasAppliedToTO ? Icons.check : Icons.send,
          label: _hasAppliedToTO ? '완료' : '지원',
          onTap: _hasAppliedToTO ? null : _openApplyDialog,
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
    return Padding(
      padding: ResponsiveHelper.cardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 그룹 TO면 날짜 선택 UI 표시
          if (_isGroupTO) ...[
            _buildDateSelector(context),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          ],
          
          // 업무 목록
          _buildWorkDetailsList(context),
        ],
      ),
    );
  }

  /// 날짜 선택 UI
  Widget _buildDateSelector(BuildContext context) {
    final theme = Theme.of(context);
    
    // 로딩 중
    if (_isLoadingGroupTOs) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
          child: SizedBox(
            width: ResponsiveHelper.spacing(context, 20),
            height: ResponsiveHelper.spacing(context, 20),
            child: const CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    
    // 날짜 없음
    if (_groupTOs.isEmpty) {
      return Text(
        '날짜 정보를 불러올 수 없습니다',
        style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
      );
    }
    
    // 5일 이하: Wrap, 6일 이상: 가로 스크롤
    if (_groupTOs.length <= 5) {
      return Wrap(
        spacing: ResponsiveHelper.spacing(context, 8),
        runSpacing: ResponsiveHelper.spacing(context, 8),
        children: _groupTOs.map((to) => _buildDateChip(context, to)).toList(),
      );
    } else {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _groupTOs.map((to) => Padding(
            padding: EdgeInsets.only(right: ResponsiveHelper.spacing(context, 8)),
            child: _buildDateChip(context, to),
          )).toList(),
        ),
      );
    }
  }

  /// 날짜 칩
  Widget _buildDateChip(BuildContext context, TOModel to) {
    final theme = Theme.of(context);
    final isSelected = _selectedDateTO?.id == to.id;
    final dayOfWeek = _getDayOfWeek(to.date);
    final dayColor = _getDayColor(to.date, isSelected);
    
    return GestureDetector(
      onTap: () => _selectDate(to),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 10),
          vertical: ResponsiveHelper.spacing(context, 6),
        ),
        decoration: BoxDecoration(
          color: isSelected ? theme.primaryColor : AppColors.grey100,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? theme.primaryColor : AppColors.grey300,
          ),
        ),
        child: Text(
          '${to.date.month}/${to.date.day}($dayOfWeek)',
          style: ResponsiveHelper.smallStyle(
            context,
            color: isSelected ? Colors.white : dayColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// 요일별 색상
  Color _getDayColor(DateTime date, bool isSelected) {
    if (isSelected) return Colors.white;
    
    switch (date.weekday) {
      case 6: // 토요일
        return Colors.blue;
      case 7: // 일요일
        return Colors.red;
      default:
        return AppColors.grey700;
    }
  }

  /// 요일 텍스트
  String _getDayOfWeek(DateTime date) {
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    return days[date.weekday - 1];
  }

  /// 업무 목록
  Widget _buildWorkDetailsList(BuildContext context) {
    if (_isLoadingWorkDetails) {
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
        final hasApplied = _hasAppliedToWork(work.workType);
        return _buildWorkDetailItem(context, work, hasApplied);
      }).toList(),
    );
  }

  /// 업무 상세 아이템
  Widget _buildWorkDetailItem(
    BuildContext context, 
    WorkDetailModel work, 
    bool hasApplied,
  ) {
    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: hasApplied ? AppColors.successBg : AppColors.grey100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasApplied ? AppColors.successLight : AppColors.grey300,
        ),
      ),
      child: Row(
        children: [
          // 업무 아이콘
          WorkTypeIcon.buildWithBackground(
            iconString: work.workTypeIcon ?? 'work',
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
                        FormatHelper.getWageTypeLabel(work.wageType ?? 'hourly'),
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
          _buildWorkStatusBadge(context, work, hasApplied),
        ],
      ),
    );
  }
  /// 업무 상태 배지
  Widget _buildWorkStatusBadge(
    BuildContext context, 
    WorkDetailModel work, 
    bool hasApplied,
  ) {
    // 지원완료 우선
    if (hasApplied) {
      return _buildStatusChip(context, '지원완료', AppColors.success, Colors.white);
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
  

  /// 버튼들
  Widget _buildActionButtons(BuildContext context) {
    final theme = Theme.of(context);
    
    return Row(
      children: [
        // 상세보기 버튼
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _goToJobPosting,
            icon: Icon(
              Icons.info_outline,
              size: ResponsiveHelper.iconSize(context, 18),
            ),
            label: Text(
              '상세보기',
              style: ResponsiveHelper.bodyStyle(context),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.primaryColor,
              side: BorderSide(color: theme.primaryColor),
              padding: EdgeInsets.symmetric(
                vertical: ResponsiveHelper.spacing(context, 12),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        
        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
        
        // 지원하기 버튼
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _hasAppliedToTO ? null : _openApplyDialog,
            icon: Icon(
              _hasAppliedToTO ? Icons.check : Icons.send,
              size: ResponsiveHelper.iconSize(context, 18),
            ),
            label: Text(
              _hasAppliedToTO ? '지원완료' : '지원하기',
              style: ResponsiveHelper.bodyStyle(context, color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _hasAppliedToTO 
                  ? AppColors.grey400 
                  : theme.primaryColor,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.grey400,
              disabledForegroundColor: Colors.white,
              padding: EdgeInsets.symmetric(
                vertical: ResponsiveHelper.spacing(context, 12),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ],
    );
  }
  /// 상단 작은 버튼들
  Widget _buildCompactActionButtons(BuildContext context) {
    final theme = Theme.of(context);
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // 상세보기 (아이콘만)
        InkWell(
          onTap: _goToJobPosting,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
            decoration: BoxDecoration(
              color: AppColors.grey100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.grey300),
            ),
            child: Icon(
              Icons.info_outline,
              size: ResponsiveHelper.iconSize(context, 18),
              color: AppColors.grey700,
            ),
          ),
        ),
        
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        
        // 지원하기 버튼
        InkWell(
          onTap: _hasAppliedToTO ? null : _openApplyDialog,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 14),
              vertical: ResponsiveHelper.spacing(context, 8),
            ),
            decoration: BoxDecoration(
              color: _hasAppliedToTO ? AppColors.grey300 : theme.primaryColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _hasAppliedToTO ? Icons.check : Icons.send,
                  size: ResponsiveHelper.iconSize(context, 16),
                  color: Colors.white,
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                Text(
                  _hasAppliedToTO ? '지원완료' : '지원하기',
                  style: ResponsiveHelper.smallStyle(
                    context,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 상세보기 화면 이동
  void _goToJobPosting() {
    NavigationHelper.push(
      context,
      destination: JobPostingScreen(
        to: widget.to,
        workDetails: _workDetails,
      ),
    );
  }

  /// 지원 다이얼로그 열기
  void _openApplyDialog() async {
    // workDetails가 없으면 리턴
    if (_workDetails.isEmpty) return;
    
    // 첫 번째 업무로 지원 (TODO: 업무 선택 UI 추가 필요)
    final result = await ApplyDialog.show(
      context: context,
      work: _workDetails.first,
      to: widget.to,
      onSuccess: () {
        // 캐시 클리어 후 콜백
        _workDetailsCache.clear();
        widget.onApplySuccess();
        if (mounted) {
          setState(() {});
        }
      },
    );
    
    if (result == true && mounted) {
      setState(() {});
    }
  }
}