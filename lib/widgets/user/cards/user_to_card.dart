import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/core/to_model.dart';
import '../../../models/core/work_detail_model.dart';
import '../../../models/core/application_model.dart';
import '../../../models/core/slot_model.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/navigation_helper.dart';
import '../../../utils/toast_helper.dart';
import '../../../theme/app_colors.dart';
import '../../../providers/user_provider.dart';
import '../../work_type_icon.dart';
import '../../common/tax_deduction_badge.dart';
import '../../common/loading_widget.dart';
import '../../../screens/common/job_posting_screen.dart';
import '../../dialogs/apply/apply_work_dialog.dart';

/// 지원자용 TO 카드
///
/// 접힌 상태: 급여·날짜+시간·위치·모집현황 한눈에
/// 펼친 상태:
///   - flex TO → 날짜별 슬롯 목록 (슬롯별 지원 버튼)
///   - contract TO → 공고 설명 + 업무 목록
///
/// 카드 상호 비활성화: isAnyOtherExpanded=true 시 반투명 처리
class UserTOCard extends StatefulWidget {
  const UserTOCard({
    super.key,
    required this.to,
    required this.isSelected,
    required this.onTap,
    required this.myApplications,
    required this.onApplySuccess,
    required this.onFetchWorkDetails,
    this.workDetails,
    this.slots,
    this.onFetchSlots,
    this.isAnyOtherExpanded = false,
  });

  final TOModel to;
  final bool isSelected;
  final VoidCallback onTap;
  final List<ApplicationModel> myApplications;
  final VoidCallback onApplySuccess;

  // contract TO용
  final List<WorkDetailModel>? workDetails;
  final Future<List<WorkDetailModel>> Function(String toId) onFetchWorkDetails;

  // flex TO용 슬롯
  final List<SlotModel>? slots;
  final Future<List<SlotModel>> Function(String toId)? onFetchSlots;

  // 다른 카드가 펼쳐진 상태 → 반투명 처리
  final bool isAnyOtherExpanded;

  @override
  State<UserTOCard> createState() => _UserTOCardState();
}

class _UserTOCardState extends State<UserTOCard> {
  bool _isFetching = false;
  bool _isFetchingSlots = false;
  bool _isApplyLoading = false;

  // 빌드마다 재계산 방지 — myApplications/to 변경 시에만 갱신
  late bool _cachedHasApplied;
  late String _cachedTimeAgo;

  List<WorkDetailModel> get _workDetails => widget.workDetails ?? const [];
  bool get _showLoading => _isFetching && _workDetails.isEmpty;
  bool get _showSlotsLoading => _isFetchingSlots && (widget.slots == null || widget.slots!.isEmpty);

  @override
  void initState() {
    super.initState();
    _cachedHasApplied = _computeHasApplied();
    _cachedTimeAgo    = _computeTimeAgo();
  }

  bool _computeHasApplied() => widget.myApplications.any((app) {
        if (AppStatus.inactiveStates.contains(app.status)) return false;
        if (app.isLongTermApplication && app.isTerminationApproved) return false;
        if (app.toId?.isNotEmpty == true) return app.toId == widget.to.id;
        return _legacyMatch(app);
      });

  String _computeTimeAgo() {
    final diff = DateTime.now().difference(widget.to.createdAt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    return '${diff.inDays}일 전';
  }

  // ── 위젯 업데이트 ────────────────────────────────────

  @override
  void didUpdateWidget(UserTOCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 지원 목록 또는 TO가 바뀌면 캐시 갱신
    // identical 비교 외 length도 확인 — 같은 List 객체에 항목이 추가/제거된 경우 포착
    if (!identical(widget.myApplications, oldWidget.myApplications) ||
        widget.myApplications.length != oldWidget.myApplications.length ||
        widget.to.id != oldWidget.to.id) {
      _cachedHasApplied = _computeHasApplied();
    }
    if (widget.to.createdAt != oldWidget.to.createdAt) {
      _cachedTimeAgo = _computeTimeAgo();
    }
    if (widget.isSelected && !oldWidget.isSelected) {
      if (widget.to.isFlexType) {
        if (widget.slots == null) _fetchSlots();
      } else {
        if (widget.workDetails == null) _fetch();
      }
    }
    // 부모 캐시에서 데이터가 들어옴 → 로딩 종료
    if (widget.workDetails != null && oldWidget.workDetails == null && _isFetching) {
      setState(() => _isFetching = false);
    }
    if (widget.slots != null && oldWidget.slots == null && _isFetchingSlots) {
      setState(() => _isFetchingSlots = false);
    }
  }

  Future<List<WorkDetailModel>> _fetch() async {
    if (_isFetching) return widget.workDetails ?? const [];
    setState(() => _isFetching = true);
    try {
      return await widget.onFetchWorkDetails(widget.to.id);
    } finally {
      if (mounted) setState(() => _isFetching = false);
    }
  }

  Future<List<SlotModel>> _fetchSlots() async {
    if (widget.onFetchSlots == null) return [];
    if (_isFetchingSlots) return widget.slots ?? [];
    setState(() => _isFetchingSlots = true);
    try {
      return await widget.onFetchSlots!(widget.to.id);
    } finally {
      if (mounted) setState(() => _isFetchingSlots = false);
    }
  }

  // ── 지원 상태 ─────────────────────────────────────────

  bool get _hasApplied => _cachedHasApplied;

  bool _legacyMatch(ApplicationModel app) {
    final to = widget.to;
    if (app.businessId != to.businessId || app.toTitle != to.title) return false;
    if (to.isLongTerm) return true;
    return app.workDate.year == to.date.year &&
        app.workDate.month == to.date.month &&
        app.workDate.day == to.date.day;
  }

  bool _hasAppliedForSlot(SlotModel slot) {
    final slotDate = DateTime(slot.date.year, slot.date.month, slot.date.day);
    return widget.myApplications.any((app) {
      if (AppStatus.inactiveStates.contains(app.status)) return false;
      if (app.isLongTermApplication && app.isTerminationApproved) return false;
      if (app.toId?.isNotEmpty == true && app.toId != widget.to.id) return false;
      // slotId가 있으면 정확히 슬롯 단위로 매칭, 없으면 날짜 폴백 (레거시 지원서)
      if (app.slotId?.isNotEmpty == true) return app.slotId == slot.id;
      final appDate = DateTime(app.workDate.year, app.workDate.month, app.workDate.day);
      return appDate == slotDate;
    });
  }

  ApplicationModel? _appForWork(WorkDetailModel work) {
    try {
      return widget.myApplications.firstWhere((app) {
        if (app.selectedWorkType != work.workType || app.startTime != work.startTime) {
          return false;
        }
        if (AppStatus.inactiveStates.contains(app.status)) return false;
        if (app.isLongTermApplication && app.isTerminationApproved) return false;
        if (app.toId?.isNotEmpty == true) return app.toId == widget.to.id;
        return _legacyMatch(app);
      });
    } catch (_) {
      return null;
    }
  }

  // ── 마감 임박 ─────────────────────────────────────────

  bool get _isUrgent {
    // contract TO: TO 레벨 applicationDeadline 기준
    if (!widget.to.isFlexType) return widget.to.isDeadlineUrgent;
    // flex TO: 로드된 슬롯 중 24시간 내 마감 슬롯 존재 여부
    final slots = widget.slots;
    if (slots == null) return false;
    final now = DateTime.now();
    return slots.any((s) {
      if (s.isEffectivelyClosed) return false;
      final dl = s.applicationDeadline;
      if (dl == null) return false;
      final diff = dl.difference(now);
      return diff.inSeconds > 0 && diff.inHours <= 24;
    });
  }

  // ── 표시 문자열 ───────────────────────────────────────

  String get _dateText {
    final to = widget.to;
    if (to.isLongTerm && to.startDate != null && to.endDate != null) {
      return '${FormatHelper.formatDateCompact(to.startDate!)} ~ '
          '${FormatHelper.formatDateCompact(to.endDate!)}';
    }
    return FormatHelper.formatDateCompact(to.date);
  }

  String get _wageLabel =>
      widget.to.wageType != null
          ? FormatHelper.getWageTypeLabel(widget.to.wageType!)
          : '급여';

  String get _wageAmount {
    final to = widget.to;
    if (to.maxWage == null) return '-';
    if (to.minWage == to.maxWage) return FormatHelper.formatWage(to.maxWage!);
    return '~${FormatHelper.formatNumber(to.maxWage!)}원';
  }

  String get _location => FormatHelper.formatLocation(
        address: widget.to.businessAddress,
        city: widget.to.businessCity,
        district: widget.to.businessDistrict,
      );

  String get _timeAgo => _cachedTimeAgo;

  String? get _workHint {
    final list = widget.to.workDetails;
    if (list.isEmpty) return null;
    if (list.length == 1) return list.first.workType;
    return '${list.first.workType} 외 ${list.length - 1}개';
  }

  String? get _recruitText {
    final req = widget.to.totalRequired;
    if (req <= 0) return null;
    return '${widget.to.totalConfirmed}/$req명';
  }

  // ── Build ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final to = widget.to;
    final barColor = to.isLongTerm ? AppColors.longTerm : AppColors.shortTerm;

    return AnimatedOpacity(
      opacity: widget.isAnyOtherExpanded ? 0.5 : 1.0,
      duration: const Duration(milliseconds: 200),
      child: Card(
        margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
        elevation: widget.isSelected ? 3 : 1,
        shadowColor: Colors.black12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: widget.isSelected ? theme.primaryColor : AppColors.border,
            width: widget.isSelected ? 1.5 : 0.8,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // 왼쪽 컬러바
            Positioned(
              left: 0, top: 0, bottom: 0,
              child: Container(
                width: ResponsiveHelper.spacing(context, 5),
                color: barColor,
              ),
            ),
            Padding(
              padding: EdgeInsets.only(left: ResponsiveHelper.spacing(context, 5)),
              child: InkWell(
                onTap: widget.onTap,
                child: Container(
                  color: widget.isSelected
                      ? theme.primaryColor.withValues(alpha: 0.02)
                      : Colors.white,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 접힌 영역
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          ResponsiveHelper.spacing(context, 12),
                          ResponsiveHelper.spacing(context, 12),
                          ResponsiveHelper.spacing(context, 12),
                          0,
                        ),
                        child: _buildCollapsed(context, theme),
                      ),
                      // 펼치기 바
                      _buildExpandBar(context),
                      // 펼친 영역
                      AnimatedSize(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeInOutCubic,
                        alignment: Alignment.topCenter,
                        clipBehavior: Clip.antiAlias,
                        child: widget.isSelected
                            ? TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0.0, end: 1.0),
                                duration: const Duration(milliseconds: 180),
                                curve: Curves.easeIn,
                                builder: (context, opacity, child) =>
                                    Opacity(opacity: opacity, child: child!),
                                child: Column(children: [
                                  Divider(height: 1, color: AppColors.grey100),
                                  _buildExpanded(context),
                                ]),
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
    );
  }

  // ── 접힌 상태 ──────────────────────────────────────────

  Widget _buildCollapsed(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTopRow(context, theme),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        Text(
          widget.to.title,
          style: ResponsiveHelper.titleStyle(context).copyWith(
            fontWeight: FontWeight.bold,
            height: 1.3,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        _buildDateTimeRow(context),
        SizedBox(height: ResponsiveHelper.spacing(context, 5)),
        _buildBusinessRow(context),
        SizedBox(height: ResponsiveHelper.spacing(context, 10)),
        Container(height: 1, color: AppColors.grey100),
        SizedBox(height: ResponsiveHelper.spacing(context, 10)),
        _buildWageRow(context),
        SizedBox(height: ResponsiveHelper.spacing(context, 10)),
        _buildActionRow(context, theme),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
      ],
    );
  }

  Widget _buildTopRow(BuildContext context, ThemeData theme) {
    return Row(
      children: [
        _typeBadge(context),
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        Icon(Icons.location_on,
            size: ResponsiveHelper.iconSize(context, 13),
            color: theme.primaryColor),
        SizedBox(width: ResponsiveHelper.spacing(context, 3)),
        Expanded(
          child: Text(
            _location.isNotEmpty ? _location : '위치 미정',
            style: ResponsiveHelper.smallStyle(context).copyWith(
              fontWeight: FontWeight.w600,
              color: theme.primaryColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        ..._statusBadgeWidgets(context),
        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
        _buildFavoriteButton(context),
      ],
    );
  }

  Widget _buildFavoriteButton(BuildContext context) {
    return Selector<UserProvider, bool>(
      selector: (_, p) => p.isFavoriteTo(widget.to.id),
      builder: (ctx, isFav, _) => GestureDetector(
        onTap: () => ctx.read<UserProvider>().toggleFavoriteTo(widget.to.id),
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: ResponsiveHelper.spacing(context, 36),
          height: ResponsiveHelper.spacing(context, 36),
          child: Center(
            child: Icon(
              isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              size: ResponsiveHelper.iconSize(context, 18),
              color: isFav ? AppColors.error : AppColors.grey300,
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _statusBadgeWidgets(BuildContext context) {
    return [
      if (_hasApplied) ...[
        SizedBox(width: ResponsiveHelper.spacing(context, 6)),
        _pill(context, '지원완료', AppColors.success, Colors.white),
      ],
      if (_isUrgent) ...[
        SizedBox(width: ResponsiveHelper.spacing(context, 6)),
        _pill(context, '마감임박', AppColors.warningDark, Colors.white),
      ],
    ];
  }

  Widget _buildDateTimeRow(BuildContext context) {
    final timeRange = widget.to.timeRange;
    final showTime = !timeRange.startsWith('--');

    return Row(
      children: [
        Icon(Icons.calendar_today,
            size: ResponsiveHelper.iconSize(context, 13),
            color: AppColors.grey500),
        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
        Text(
          _dateText,
          style: ResponsiveHelper.smallStyle(context,
              color: AppColors.grey700, fontWeight: FontWeight.w500),
        ),
        if (showTime) ...[
          _divider(context),
          Icon(Icons.schedule,
              size: ResponsiveHelper.iconSize(context, 13),
              color: AppColors.grey500),
          SizedBox(width: ResponsiveHelper.spacing(context, 3)),
          Flexible(
            child: Text(
              timeRange,
              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        if (widget.to.isLongTerm && widget.to.workDays.isNotEmpty) ...[
          _divider(context),
          Flexible(
            child: Text(
              widget.to.workDaysLabel,
              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBusinessRow(BuildContext context) => Row(
        children: [
          Icon(Icons.store_outlined,
              size: ResponsiveHelper.iconSize(context, 13),
              color: AppColors.grey400),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Expanded(
            child: Text(
              widget.to.businessName,
              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            _timeAgo,
            style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey400),
          ),
        ],
      );

  Widget _buildWageRow(BuildContext context) {
    final hint = _workHint;
    final recruit = _recruitText;
    return Row(
      children: [
        _pill(context, _wageLabel, AppColors.successBg, AppColors.successDark,
            border: AppColors.successLight),
        SizedBox(width: ResponsiveHelper.spacing(context, 6)),
        Text(
          _wageAmount,
          style: ResponsiveHelper.subtitleStyle(context).copyWith(
            color: AppColors.successDark,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (hint != null) ...[
          _divider(context),
          Expanded(
            child: Text(
              hint,
              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ] else
          const Spacer(),
        if (recruit != null) ...[
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          Icon(Icons.people_outline,
              size: ResponsiveHelper.iconSize(context, 13),
              color: AppColors.grey500),
          SizedBox(width: ResponsiveHelper.spacing(context, 3)),
          Text(
            recruit,
            style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey600),
          ),
        ],
      ],
    );
  }

  Widget _buildActionRow(BuildContext context, ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _actionBtn(context,
            label: '상세보기',
            icon: Icons.article_outlined,
            onTap: _goToDetail,
            primary: false),
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        _isApplyLoading
            ? _loadingBtn(context, theme)
            : _actionBtn(context,
                label: _hasApplied ? '지원관리' : '지원하기',
                icon: _hasApplied ? Icons.manage_accounts_outlined : Icons.send,
                onTap: _openApplyDialog,
                primary: !_hasApplied),
      ],
    );
  }

  Widget _buildExpandBar(BuildContext context) {
    final label = widget.isSelected
        ? '접기'
        : widget.to.isFlexType
            ? '날짜 선택'
            : '업무 상세';

    return Container(
      color: AppColors.grey50,
      padding: EdgeInsets.symmetric(
          vertical: ResponsiveHelper.spacing(context, 5)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey400),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 3)),
          Icon(
            widget.isSelected
                ? Icons.keyboard_arrow_up
                : Icons.keyboard_arrow_down,
            size: ResponsiveHelper.iconSize(context, 16),
            color: AppColors.grey400,
          ),
        ],
      ),
    );
  }

  // ── 펼친 상태 ──────────────────────────────────────────

  Widget _buildExpanded(BuildContext context) {
    final isPending = widget.to.isPendingPublish;

    return Padding(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isPending) ...[
            _pendingNotice(context),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          ],
          if (widget.to.description?.isNotEmpty == true) ...[
            _descriptionPreview(context),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          ],
          // flex TO: 날짜-슬롯 목록 / contract TO: 업무 목록
          if (widget.to.isFlexType)
            _buildFlexSlotList(context)
          else
            Opacity(
              opacity: isPending ? 0.4 : 1.0,
              child: _buildWorkList(context),
            ),
        ],
      ),
    );
  }

  // ── flex TO 날짜-슬롯 목록 ─────────────────────────────

  Widget _buildFlexSlotList(BuildContext context) {
    if (_showSlotsLoading) {
      return Padding(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
        child: const LoadingWidget(),
      );
    }

    // null = 아직 fetch 안 됨 / 빈 리스트 = fetch 완료 후 슬롯 없음
    if (widget.slots == null) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 8)),
        child: Text(
          '날짜 정보를 불러오는 중...',
          style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
        ),
      );
    }
    if (widget.slots!.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 8)),
        child: Text(
          '등록된 날짜가 없습니다',
          style: ResponsiveHelper.smallStyle(context, color: AppColors.grey400),
        ),
      );
    }

    final slots = widget.slots!;
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.calendar_month_outlined,
                size: ResponsiveHelper.iconSize(context, 14),
                color: AppColors.grey600),
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            Text(
              '날짜별 근무',
              style: ResponsiveHelper.smallStyle(context,
                  color: AppColors.grey700, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Text(
              '${slots.length}개 날짜',
              style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey400),
            ),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 10)),
        ...slots.map((slot) => _buildSlotRow(context, slot, now)),
      ],
    );
  }

  Widget _buildSlotRow(BuildContext context, SlotModel slot, DateTime now) {
    final isPending = slot.visibleFrom != null && slot.visibleFrom!.isAfter(now);
    // 모델 단일 진실 소스 사용 — wd.isClosed(수동마감) + slot.applicationDeadline 모두 포함
    final isEffectivelyClosed = slot.isEffectivelyClosed;
    final isDisabled = isPending || isEffectivelyClosed;

    final hasApplied = _hasAppliedForSlot(slot);

    // 배지 우선순위: 지원완료 > 예약(visibleFrom 미래) > 충족 > 마감 > 모집중
    // isFull을 isEffectivelyClosed보다 먼저 체크: slot.isFull은 isEffectivelyClosed에
    // 포함되지만 '충족'과 '마감'을 구분 표시하기 위해 별도 처리.
    // TO 레벨 isManualClosed는 all_to_list_screen 필터에서 이미 제외되므로 여기서 불필요.
    String statusLabel;
    Color statusBg;
    Color statusFg;
    if (hasApplied) {
      statusLabel = '지원완료';
      statusBg = AppColors.infoBg;
      statusFg = AppColors.info;
    } else if (isPending) {
      statusLabel = '예약';
      statusBg = AppColors.warningBg;
      statusFg = AppColors.warningDark;
    } else if (slot.isFull) {
      statusLabel = '충족';
      statusBg = AppColors.grey100;
      statusFg = AppColors.grey500;
    } else if (isEffectivelyClosed) {
      statusLabel = '마감';
      statusBg = AppColors.grey100;
      statusFg = AppColors.grey500;
    } else {
      statusLabel = '모집중';
      statusBg = AppColors.successBg;
      statusFg = AppColors.successDark;
    }

    // 업무 힌트 (슬롯 자체 workDetails 사용)
    final workHint = slot.workDetails.isEmpty
        ? null
        : slot.workDetails.length == 1
            ? slot.workDetails.first.workType
            : '${slot.workDetails.first.workType} 외 ${slot.workDetails.length - 1}개';

    final slotDate = slot.date;
    final dateLabel = '${slotDate.month}월 ${slotDate.day}일';
    final semanticDesc = isDisabled
        ? '$dateLabel 슬롯, 마감됨'
        : hasApplied
            ? '$dateLabel 슬롯, 지원 완료, 상세 보기'
            : '$dateLabel 슬롯, 지원 가능, 공고 상세 보기';

    return Semantics(
      label: semanticDesc,
      button: !(isDisabled && !hasApplied),
      enabled: !(isDisabled && !hasApplied),
      child: GestureDetector(
      // 마감된 슬롯은 상세 진입 불가 (지원완료 상태는 확인 가능하도록 허용)
      onTap: (isDisabled && !hasApplied) ? null : () => _goToDetailForSlot(slot),
      child: Opacity(
      opacity: (isDisabled && !hasApplied) ? 0.55 : 1.0,
      child: Container(
        margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 10),
          vertical: ResponsiveHelper.spacing(context, 9),
        ),
        decoration: BoxDecoration(
          color: hasApplied
              ? AppColors.infoBg
              : isDisabled
                  ? AppColors.grey50
                  : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: hasApplied
                ? AppColors.infoLight
                : isDisabled
                    ? AppColors.grey200
                    : AppColors.grey300,
          ),
        ),
        child: Row(
          children: [
            // 날짜 배지
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 7),
                vertical: ResponsiveHelper.spacing(context, 3),
              ),
              decoration: BoxDecoration(
                color: AppColors.shortTermBg,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.shortTermLight),
              ),
              child: Text(
                FormatHelper.formatDateCompact(slot.date),
                style: ResponsiveHelper.tinyStyle(context,
                    color: AppColors.shortTermDark,
                    fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            // 업무 힌트
            Expanded(
              child: workHint != null
                  ? Text(
                      workHint,
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.grey600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : const SizedBox.shrink(),
            ),
            // 상태 칩
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            _statusChip(context, statusLabel, statusBg, statusFg),
            // 지원 버튼 (마감 아닐 때만)
            if (!isDisabled) ...[
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              _slotApplyBtn(context, slot, hasApplied),
            ],
          ],
        ),
      ),
    ), // Opacity
    ), // GestureDetector
    ); // Semantics
  }

  Widget _slotApplyBtn(BuildContext context, SlotModel slot, bool hasApplied) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => _openApplyDialogForSlot(slot),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 10),
          vertical: ResponsiveHelper.spacing(context, 5),
        ),
        decoration: BoxDecoration(
          color: hasApplied
              ? Colors.transparent
              : theme.primaryColor,
          borderRadius: BorderRadius.circular(6),
          border: hasApplied
              ? Border.all(color: AppColors.info)
              : null,
        ),
        child: Text(
          hasApplied ? '지원관리' : '지원하기',
          style: ResponsiveHelper.tinyStyle(context,
              color: hasApplied ? AppColors.info : Colors.white,
              fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _statusChip(BuildContext context, String label, Color bg, Color fg) =>
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 72),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 6),
            vertical: ResponsiveHelper.spacing(context, 3),
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(label,
              style: ResponsiveHelper.tinyStyle(context,
                  color: fg, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
              maxLines: 1),
        ),
      );

  // ── contract TO 업무 목록 ──────────────────────────────

  Widget _pendingNotice(BuildContext context) => Container(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
        decoration: BoxDecoration(
          color: AppColors.warningBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.warningLight),
        ),
        child: Row(
          children: [
            Icon(Icons.schedule,
                size: ResponsiveHelper.iconSize(context, 16),
                color: AppColors.warningDark),
            SizedBox(width: ResponsiveHelper.spacing(context, 10)),
            Expanded(
              child: Text(
                widget.to.publishAtDisplay != null
                    ? '${widget.to.publishAtDisplay}에 오픈됩니다'
                    : '곧 오픈 예정입니다',
                style: ResponsiveHelper.smallStyle(context,
                    color: AppColors.warningDark, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );

  Widget _descriptionPreview(BuildContext context) => Container(
        width: double.infinity,
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
        decoration: BoxDecoration(
          color: AppColors.grey50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.grey200),
        ),
        child: Text(
          widget.to.description!,
          style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      );

  Widget _buildWorkList(BuildContext context) {
    if (_showLoading) {
      return Padding(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
        child: const LoadingWidget(),
      );
    }
    if (_workDetails.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(
            vertical: ResponsiveHelper.spacing(context, 8)),
        child: Text('업무 목록을 불러오는 중...',
            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500)),
      );
    }

    final dups = _workDetails
        .map((w) => w.workType)
        .fold<Map<String, int>>({}, (m, t) {
          m[t] = (m[t] ?? 0) + 1;
          return m;
        })
        .entries
        .where((e) => e.value > 1)
        .map((e) => e.key)
        .toSet();

    return Column(
      children: _workDetails
          .map((work) => _WorkItem(
                work: work,
                application: _appForWork(work),
                to: widget.to,
                showTimeLabel: dups.contains(work.workType),
              ))
          .toList(),
    );
  }

  // ── 공통 소위젯 ───────────────────────────────────────

  Widget _typeBadge(BuildContext context) {
    final long = widget.to.isLongTerm;
    return _pill(
      context,
      long ? '고정' : '단기',
      long ? AppColors.longTermBg : AppColors.shortTermBg,
      long ? AppColors.longTermDark : AppColors.shortTermDark,
      border: long ? AppColors.longTermLight : AppColors.shortTermLight,
    );
  }

  Widget _pill(
    BuildContext context,
    String label,
    Color bg,
    Color text, {
    Color? border,
  }) =>
      Container(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 7),
          vertical: ResponsiveHelper.spacing(context, 3),
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(4),
          border: border != null ? Border.all(color: border) : null,
        ),
        child: Text(
          label,
          style: ResponsiveHelper.tinyStyle(context,
              color: text, fontWeight: FontWeight.bold),
        ),
      );

  Widget _divider(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 7)),
        child: Container(width: 1, height: 11, color: AppColors.grey200),
      );

  Widget _actionBtn(
    BuildContext context, {
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    bool primary = true,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 14),
          vertical: ResponsiveHelper.spacing(context, 8),
        ),
        decoration: BoxDecoration(
          color: primary ? theme.primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: primary ? null : Border.all(color: AppColors.grey300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: ResponsiveHelper.iconSize(context, 13),
                color: primary ? Colors.white : AppColors.grey700),
            SizedBox(width: ResponsiveHelper.spacing(context, 5)),
            Text(
              label,
              style: ResponsiveHelper.smallStyle(context,
                  color: primary ? Colors.white : AppColors.grey700,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loadingBtn(BuildContext context, ThemeData theme) => Container(
        height: ResponsiveHelper.spacing(context, 34),
        width: ResponsiveHelper.spacing(context, 84),
        decoration: BoxDecoration(
          color: theme.primaryColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: SizedBox(
            width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          ),
        ),
      );

  // ── Navigation ────────────────────────────────────────

  Future<void> _goToDetail() async {
    // flex TO는 슬롯 데이터 기반이지만 상세 화면은 마스터 workDetails 사용
    var details = _workDetails;
    if (details.isEmpty && !widget.to.isFlexType) {
      setState(() => _isApplyLoading = true);
      await _fetch();
      if (!mounted) return;
      setState(() => _isApplyLoading = false);
      details = _workDetails;
      if (details.isEmpty) return;
    } else if (details.isEmpty && widget.to.isFlexType) {
      // flex TO: 마스터 TO workDetails (슬롯 없어도 이동 가능)
      details = widget.to.workDetails;
    }
    if (!mounted) return;
    final result = await NavigationHelper.push<bool>(
      context,
      destination: JobPostingScreen(to: widget.to, workDetails: details),
    );
    if (result == true && mounted) widget.onApplySuccess();
  }

  /// 하단 "지원하기" 버튼 — flex TO면 전체 슬롯 다이얼로그, contract TO면 단일 다이얼로그
  Future<void> _openApplyDialog() async {
    if (_isApplyLoading) return; // 연타 방지
    if (widget.to.isFlexType) {
      await _openApplyDialogAllSlots();
      return;
    }
    // contract / single-date TO
    final List<WorkDetailModel> workDetails;
    if (_workDetails.isEmpty) {
      setState(() => _isApplyLoading = true);
      try {
        workDetails = await _fetch();
      } catch (e) {
        if (mounted) {
          setState(() => _isApplyLoading = false);
          ToastHelper.showError('근무 정보를 불러오는데 실패했습니다.');
        }
        return;
      } finally {
        // mounted 체크 없이 조기 리턴하면 _isApplyLoading이 true로 고착됨 — finally로 항상 리셋
        if (mounted) setState(() => _isApplyLoading = false);
      }
      if (!mounted) return;
      if (workDetails.isEmpty) return;
    } else {
      workDetails = _workDetails;
    }
    if (!mounted) return;

    final result = await ApplyWorkDialog.show(
      context: context,
      to: widget.to,
      workDetails: workDetails,
      businessName: widget.to.businessName,
      myApplications: widget.myApplications,
    );
    // result == null: 스와이프 닫기 → 변경 여부 불명이므로 안전하게 갱신
    // result.hasChanges == false: 닫기 버튼으로 닫고 변경 없음 → 갱신 생략
    if (result?.hasChanges != false && mounted) {
      widget.onApplySuccess();
    }
  }

  /// flex TO: 모든 오픈 슬롯을 GroupTO 형식으로 다이얼로그 오픈
  Future<void> _openApplyDialogAllSlots() async {
    // 슬롯 미로드 시 먼저 fetch — 반환값을 직접 사용(widget rebuild 대기 불필요)
    final List<SlotModel> slots;
    if (widget.slots == null) {
      setState(() => _isApplyLoading = true);
      try {
        slots = await _fetchSlots();
      } catch (e) {
        if (mounted) {
          setState(() => _isApplyLoading = false);
          ToastHelper.showError('슬롯 정보를 불러오는데 실패했습니다.');
        }
        return;
      } finally {
        if (mounted) setState(() => _isApplyLoading = false);
      }
      if (!mounted) return;
    } else {
      slots = widget.slots!;
    }
    if (slots.isEmpty) return;

    final now = DateTime.now();
    final groupTOsByDate = <DateTime, TOModel>{};
    final groupWorkDetailsByDate = <DateTime, List<WorkDetailData>>{};
    final groupSlotIdsByDate = <DateTime, String>{};

    for (final slot in slots) {
      if (slot.isEffectivelyClosed) continue;
      if (slot.visibleFrom != null && slot.visibleFrom!.isAfter(now)) continue;
      // 모든 업무의 지원 마감이 경과한 슬롯 제외
      if (slot.workDetails.isNotEmpty &&
          slot.workDetails.every((wd) => wd.isTimeExpired)) { continue; }
      final dateKey = DateTime(slot.date.year, slot.date.month, slot.date.day);
      groupTOsByDate[dateKey] = widget.to.copyWith(rangeStart: slot.date);
      // runtimeFull: 슬롯의 workTypeCounts 기반으로 업무별 정원 충족 여부 주입
      groupWorkDetailsByDate[dateKey] = slot.workDetails.map((wd) =>
          slot.isWorkTypeFull(wd.workType)
              ? wd.copyWith(runtimeFull: true)
              : wd).toList();
      groupSlotIdsByDate[dateKey] = slot.id;
    }

    if (!mounted) return;
    if (groupTOsByDate.isEmpty) return;

    final result = await ApplyWorkDialog.show(
      context: context,
      to: widget.to,
      workDetails: widget.to.workDetails,
      groupTOsByDate: groupTOsByDate,
      groupWorkDetailsByDate: groupWorkDetailsByDate,
      groupSlotIdsByDate: groupSlotIdsByDate,
      businessName: widget.to.businessName,
      myApplications: widget.myApplications,
    );
    if (result?.hasChanges != false && mounted) {
      widget.onApplySuccess();
    }
  }

  /// 슬롯 행 탭 → 해당 날짜 공고 상세 화면
  Future<void> _goToDetailForSlot(SlotModel slot) async {
    final slotTO = widget.to.copyWith(rangeStart: slot.date);
    final required = slot.workDetails.fold(0, (sum, wd) => sum + wd.requiredCount);
    final result = await NavigationHelper.push<bool>(
      context,
      destination: JobPostingScreen(
        to: slotTO,
        workDetails: slot.workDetails,
        slotDate: slot.date,
        slotTotalRequired: required,
        slotConfirmedCount: slot.confirmedCount,
        slotPendingCount: slot.pendingCount,
      ),
    );
    // 공고 상세에서 지원한 경우 부모(AllTOListScreen) 지원 목록 갱신
    if (result == true && mounted) widget.onApplySuccess();
  }

  /// 슬롯 행의 "지원하기" → 해당 날짜 단일 슬롯 다이얼로그
  Future<void> _openApplyDialogForSlot(SlotModel slot) async {
    if (_isApplyLoading || !mounted) return;
    final slotTO = widget.to.copyWith(rangeStart: slot.date);
    final annotatedDetails = slot.workDetails.map((wd) =>
        slot.isWorkTypeFull(wd.workType)
            ? wd.copyWith(runtimeFull: true)
            : wd).toList();
    final result = await ApplyWorkDialog.show(
      context: context,
      to: slotTO,
      workDetails: annotatedDetails,
      slotId: slot.id,
      businessName: widget.to.businessName,
      myApplications: widget.myApplications,
    );
    if (result?.hasChanges == true && mounted) {
      widget.onApplySuccess();
    }
  }
}

// ══════════════════════════════════════════════════════════
// 업무 아이템 위젯 (contract TO 펼친 상태 전용)
// ══════════════════════════════════════════════════════════

class _WorkItem extends StatelessWidget {
  const _WorkItem({
    required this.work,
    required this.application,
    required this.to,
    required this.showTimeLabel,
  });

  final WorkDetailModel work;
  final ApplicationModel? application;
  final TOModel to;
  final bool showTimeLabel;

  @override
  Widget build(BuildContext context) {
    final hasApplied = application != null && application!.id.isNotEmpty;
    final isConfirmed = AppStatus.confirmedStatuses.contains(application?.status);
    final isClosed = !hasApplied && (work.isClosed || work.isTimeExpired || work.isFull);

    return Opacity(
      opacity: isClosed ? 0.5 : 1.0,
      child: Container(
        margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 11)),
        decoration: BoxDecoration(
          color: isConfirmed
              ? AppColors.successBg
              : hasApplied
                  ? AppColors.infoBg
                  : AppColors.grey50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isConfirmed
                ? AppColors.successLight
                : hasApplied
                    ? AppColors.infoLight
                    : AppColors.grey200,
          ),
        ),
        child: Row(
          children: [
            WorkTypeIcon.buildWithBackground(
              iconString: work.workTypeIcon,
              iconColor: work.workTypeColor,
              backgroundColor: work.workTypeBackgroundColor,
              containerSize: ResponsiveHelper.spacing(context, 36),
              size: ResponsiveHelper.iconSize(context, 18),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 10)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(work.workType,
                      style: ResponsiveHelper.bodyStyle(context)
                          .copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  SizedBox(height: ResponsiveHelper.spacing(context, 3)),
                  _infoRow(context),
                ],
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            _statusBadge(context, hasApplied, isConfirmed),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(BuildContext context) {
    return Wrap(
      spacing: ResponsiveHelper.spacing(context, 8),
      runSpacing: ResponsiveHelper.spacing(context, 4),
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (showTimeLabel)
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 5),
              vertical: ResponsiveHelper.spacing(context, 2),
            ),
            decoration: BoxDecoration(
              color: AppColors.infoBg,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('${work.startTime}~${work.endTime}',
                style: ResponsiveHelper.tinyStyle(context,
                    color: AppColors.info, fontWeight: FontWeight.bold)),
          )
        else
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.access_time,
                  size: ResponsiveHelper.iconSize(context, 12),
                  color: AppColors.grey500),
              SizedBox(width: ResponsiveHelper.spacing(context, 3)),
              Text('${work.startTime}~${work.endTime}',
                  style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey600)),
            ],
          ),
        Text(
          FormatHelper.formatWage(work.wage),
          style: ResponsiveHelper.smallStyle(context).copyWith(
            color: AppColors.successDark,
            fontWeight: FontWeight.bold,
          ),
        ),
        TaxDeductionBadge.chip(taxDeductionType: work.taxDeductionType),
      ],
    );
  }

  // _WorkItem은 _buildWorkList 전용 — contract TO (!isFlexType) 에서만 호출됨.
  // contract TO는 isLongTerm=true이므로 아래 !isLongTerm 분기는 단기 단일날짜 레거시 TO 대응용.
  Widget _statusBadge(BuildContext context, bool hasApplied, bool isConfirmed) {
    if (hasApplied) {
      return _chip(context,
          isConfirmed ? '확정' : '대기중',
          isConfirmed ? AppColors.success : AppColors.info,
          Colors.white);
    }
    if (to.isLongTerm) {
      // contract TO: TO 레벨 마감(수동/게시만료) → 업무별 마감 순으로 판단
      if (to.isManualClosed || to.isDeadlinePassed) {
        return _chip(context, '마감', AppColors.grey400, Colors.white);
      }
      if (work.isFull) return _chip(context, '마감', AppColors.grey400, Colors.white);
      if (work.isEmergencyOpen) return _chip(context, '긴급', AppColors.error, Colors.white);
      return _chip(context, '모집중', AppColors.successBg, AppColors.successDark);
    }
    // 단기 단일날짜 레거시 TO: 업무 레벨 상태만 체크
    if (work.isClosed || work.isTimeExpired || work.isFull) {
      return _chip(context, '마감', AppColors.grey400, Colors.white);
    }
    if (work.isEmergencyOpen) return _chip(context, '긴급', AppColors.error, Colors.white);
    return _chip(context, '모집중', AppColors.successBg, AppColors.successDark);
  }

  Widget _chip(BuildContext context, String label, Color bg, Color text) =>
      Container(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 8),
          vertical: ResponsiveHelper.spacing(context, 4),
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label,
            style: ResponsiveHelper.tinyStyle(context,
                color: text, fontWeight: FontWeight.bold)),
      );
}
