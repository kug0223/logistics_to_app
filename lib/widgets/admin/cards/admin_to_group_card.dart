import 'package:flutter/material.dart';

// Models
import '../../../models/core/to_model.dart';
import '../../../utils/close_state_utils.dart';
import '../../../models/ui/admin_to_list_ui_models.dart';
import '../../../models/core/work_detail_data.dart';

// Helper
import '../../../utils/dialog_helper.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/slot_status_util.dart';

// Services
import '../../../services/firestore_service.dart';

// Utils
import '../../../utils/responsive_helper.dart';
import '../../../utils/navigation_helper.dart';
import '../../../utils/format_helper.dart';

// Widgets
import '../../../theme/app_colors.dart';
import '../../common/loading_widget.dart';
import '../../common/slot_status_badge.dart';

// Screens
import '../../../screens/business_admin/to_management/edit_to_screen.dart';

// Dialogs
import '../../../screens/business_admin/dialogs/confirmed_list_dialog.dart';
import '../../../screens/business_admin/dialogs/to_list_dialogs.dart';
import '../../../screens/business_admin/dialogs/slot_batch_select_dialog.dart';
import '../../common/app_menu_sheet.dart';

// Providers
import 'package:provider/provider.dart';
import '../../../providers/user_provider.dart';
import '../../../widgets/dialogs/styled_dialog.dart';

// Local Widgets
import 'admin_work_detail.dart';
import 'to_capacity_ring.dart';
import '../../../screens/common/job_posting_screen.dart';
import '../../../screens/business_admin/dialogs/work_detail_management_dialog.dart';

enum TOCardDisplayMode { list, calendar }

/// 공고 그룹 카드 — 날짜 미선택 리스트 뷰에서 공고 전체를 표시하는 메인 카드.
///
/// ## TOItemCard와의 역할 분리
/// - TOGroupCard(이 클래스): 날짜 범위/N일 배지/등록시간/마감 카운트다운 등 풍부한 그룹 정보.
///   리스트 뷰에서 전체 공고를 훑어보는 용도. 다중 슬롯 서브네비게이션 포함.
/// - TOItemCard: 날짜가 이미 선택된 캘린더 뷰에서 특정 슬롯 하나를 compact하게 표시.
///
/// ## [TOCardDisplayMode.calendar] 존재 이유
/// 캘린더 뷰에서 TOGroupCard를 직접 사용하는 경우가 없어도, 추후 확장 또는
/// 업무상세 메뉴([manageWorkDetails]) 등 일부 액션 경로에서 calendar 분기가 사용될 수 있어 보존.
/// 단, 캘린더 뷰의 카드 자체는 TOItemCard를 사용해야 함 — TOItemCard 클래스 주석 참고.
class TOGroupCard extends StatefulWidget {
  final TOGroupItem groupItem;
  final FirestoreService firestoreService;
  final TOListDialogs dialogs;
  final VoidCallback onChanged;
  final bool isExpanded;
  final Set<String> expandedTOs;
  final VoidCallback onToggleExpand;
  final Function(String toId) onToggleTOExpand;
  final DateTime? selectedDate;
  
  // ✨ Lazy Loading 상태
  final bool isGroupLoading;      // 그룹 로딩 중
  final Set<String> loadingTOs;   // 로딩 중인 TO 목록
  final void Function(Set<String> affectedTOIds)? onAffectedTOsChanged;
  /// 리스트에서 다른 카드가 하나라도 펼쳐진 상태인지 (dimming용)
  final bool isAnyExpanded;
  final TOCardDisplayMode displayMode;
  /// 캘린더 단기 슬롯 모드: 해당 날짜 특정 슬롯
  final TOItem? calendarSlot;
  /// 아코디언 — 현재 활성화된 그룹 카드 ID. 다른 카드 ID이면 칩 선택 초기화
  final String? activeGroupKey;
  /// 다중 슬롯 카드에서 날짜 칩을 선택할 때 부모에 활성화 신호 전달
  final void Function(String groupId)? onGroupActivated;
  /// 다중 슬롯 카드에서 날짜 칩이 해제될 때 부모에 비활성화 신호 전달
  final VoidCallback? onGroupDeactivated;

  const TOGroupCard({
    super.key,
    required this.groupItem,
    required this.firestoreService,
    required this.dialogs,
    required this.onChanged,
    required this.isExpanded,
    required this.expandedTOs,
    required this.onToggleExpand,
    required this.onToggleTOExpand,
    this.selectedDate,
    this.isGroupLoading = false,
    this.loadingTOs = const <String>{},
    this.onAffectedTOsChanged,
    this.isAnyExpanded = false,
    this.displayMode = TOCardDisplayMode.list,
    this.calendarSlot,
    this.activeGroupKey,
    this.onGroupActivated,
    this.onGroupDeactivated,
  });

  @override
  State<TOGroupCard> createState() => _TOGroupCardState();
}

class _TOGroupCardState extends State<TOGroupCard> {
  bool _isExtending = false;

  // build() 내 O(N) 집계 캐시 — didUpdateWidget에서 갱신
  late List<TOItem> _targetTOs;
  late int _totalConfirmed;
  late int _totalPending;
  late int _totalRequired;
  late bool _isFull;
  DateTime _buildNow = DateTime.now();

  // 날짜 칩 선택 상태 (다중 슬롯 뷰)
  DateTime? _selectedChipDate;

  void _updateGroupCache() {
    _buildNow = DateTime.now();
    final g = widget.groupItem;
    _targetTOs = (widget.selectedDate != null && !g.isLongTerm)
        ? g.groupTOs.where((t) =>
            DateUtils.isSameDay(t.slot?.date ?? t.to.date, widget.selectedDate!)).toList()
        : g.groupTOs;

    if (_targetTOs.isEmpty) {
      _totalConfirmed = g.totalConfirmed;
      _totalPending   = g.totalPending;
      _totalRequired  = g.totalRequired;
      _isFull = g.isFull;
    } else {
      int c = 0, p = 0, r = 0;
      for (final t in _targetTOs) { c += t.confirmedCount; p += t.pendingCount; r += t.totalRequired; }
      _totalConfirmed = c;
      _totalPending   = p;
      _totalRequired  = r;
      _isFull = _targetTOs.every((t) => t.resolvedIsFull);
    }
  }

  @override
  void initState() {
    super.initState();
    _updateGroupCache();
  }

  @override
  void didUpdateWidget(TOGroupCard old) {
    super.didUpdateWidget(old);
    if (!identical(widget.groupItem, old.groupItem) ||
        widget.selectedDate != old.selectedDate) {
      _updateGroupCache();
    } else {
      _buildNow = DateTime.now();
    }
    // 다른 카드가 활성화되면 날짜 칩 선택 초기화
    if (widget.activeGroupKey != old.activeGroupKey &&
        widget.activeGroupKey != widget.groupItem.id &&
        _selectedChipDate != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedChipDate = null);
      });
    }
  }

  Future<void> _handleExtend(BuildContext context, TOModel masterTO) async {
    final selected = await DialogHelper.showSheet<int>(
      context,
      builder: (ctx) => _ExtendDaysSheet(masterTO: masterTO),
    );
    if (selected == null) return;
    if (!mounted) return;
    setState(() => _isExtending = true);
    try {
      await widget.firestoreService.extendTOPosting(masterTO.id, selected);
      if (!mounted) return;
      ToastHelper.showSuccess('공고가 $selected일 연장되었습니다.');
      widget.onChanged();
    } on Exception catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      if (msg.contains('MAX_ACTIVE_TO_LIMIT')) {
        final limit = msg.split(':').last.trim();
        ToastHelper.showError('활성 공고 한도($limit개)를 초과하여 연장할 수 없습니다.');
      } else {
        ToastHelper.showError('연장 실패: $msg');
      }
    } finally {
      if (mounted) setState(() => _isExtending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final masterTO = widget.groupItem.masterTO;
    final theme = Theme.of(context);

    // 캐시된 집계값 사용 — didUpdateWidget에서 갱신됨
    final targetTOs      = _targetTOs;
    final totalConfirmed = _totalConfirmed;
    final totalPending   = _totalPending;
    final totalRequired  = _totalRequired;
    final isFull         = _isFull;
    final now            = _buildNow;

    // 다중 슬롯 새 레이아웃 여부 — 항상 표시 (접힘 없음)
    final isMultiSlot = widget.displayMode == TOCardDisplayMode.list &&
        !widget.groupItem.isLongTerm &&
        widget.groupItem.groupTOs.length > 1;

    // ✅ 전체 마감 여부 (WorkDetail 실제 상태 + isTimeExpired 포함)
    final isMultiSlotCollapsed = widget.groupItem.groupTOs.isEmpty &&
        !masterTO.isLongTerm && masterTO.totalSlots > 1;

    // 슬롯 미로드 상태에서 HOURS_BEFORE 타입 폴백 (마지막 슬롯 기준 마감 여부)
    bool multiSlotTimeExpired = false;
    if (isMultiSlotCollapsed &&
        masterTO.deadlineType == 'HOURS_BEFORE' &&
        (masterTO.hoursBeforeStart ?? 0) > 0) {
      final lastDate = masterTO.rangeEnd;
      if (lastDate != null && masterTO.workDetails.isNotEmpty) {
        multiSlotTimeExpired = masterTO.workDetails.every((d) {
          final parts = d.startTime.split(':');
          if (parts.length != 2) return false;
          final deadline = DateTime(lastDate.year, lastDate.month, lastDate.day,
              int.parse(parts[0]), int.parse(parts[1]))
              .subtract(Duration(hours: masterTO.hoursBeforeStart!));
          return now.isAfter(deadline);
        });
      }
    }

    // 전체 마감 여부 — TOModel.isClosed가 contract 게시만료 포함한 단일 판단
    final allClosed = targetTOs.isEmpty
        ? (widget.groupItem.isClosed || multiSlotTimeExpired)
        : targetTOs.every(
            (toItem) => CloseStateUtils.isToItemClosed(toItem, masterTO, now),
          );

    // ✨ 컬러바 색상 결정 (장기: 보라, 단기: 초록)
    Color statusBarColor;
    if (allClosed) {
      statusBarColor = AppColors.grey400;
    } else {
      statusBarColor = widget.groupItem.isLongTerm ? AppColors.longTerm : AppColors.shortTerm;
    }

    // 이 카드가 활성 상태인지 — 단건 펼침 OR activeGroupKey가 이 카드를 가리킴
    // _selectedChipDate 조건 제거: 접기를 해도 activeGroupKey가 유지되어야 함(버그 3 수정)
    final isThisGroupActive = widget.isExpanded ||
        widget.activeGroupKey == widget.groupItem.id;
    final isDimmed = widget.isAnyExpanded && !isThisGroupActive;

    final cardContent = Container(
      margin: EdgeInsets.only(
        bottom: ResponsiveHelper.spacing(context, 4),
      ),
      child: Stack(
        children: [
          // ✅ 메인 카드
          Container(
            margin: const EdgeInsets.only(left: 4),  // 좌측 컬러바 공간
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
              border: Border.all(
                color: (isMultiSlot || widget.isExpanded) ? theme.primaryColor : AppColors.grey200,
                width: (isMultiSlot || widget.isExpanded) ? 1.5 : 1,
              ),
            ),
            child: Material(
          color: Colors.transparent,
          child: Column(
            children: [
              // ✨ 헤더 (클릭 가능)
              InkWell(
                // multiSlot: 비활성(isDimmed)→활성화, 활성→날짜패널 접기
                onTap: isMultiSlot
                    ? (isDimmed
                        ? () => widget.onGroupActivated?.call(widget.groupItem.id)
                        : () => setState(() => _selectedChipDate = null))
                    : widget.onToggleExpand,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(widget.isExpanded ? 0 : 16),
                  bottomRight: Radius.circular(widget.isExpanded ? 0 : 16),
                ),
                child: Padding(
                  padding: ResponsiveHelper.symmetricPadding(context, horizontal: 12, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ✨ 첫째 줄: 배지 + 사업장 + 등록시간 + 메뉴
                      Row(
                        children: [
                          // 장기/단기 텍스트 배지 (맨 앞)
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: ResponsiveHelper.spacing(context, 8),
                              vertical: ResponsiveHelper.spacing(context, 3),
                            ),
                            decoration: BoxDecoration(
                              color: widget.groupItem.isLongTerm 
                                  ? AppColors.longTermBg 
                                  : AppColors.shortTermBg,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: widget.groupItem.isLongTerm 
                                    ? AppColors.longTermLight 
                                    : AppColors.shortTermLight,
                              ),
                            ),
                            child: Text(
                              widget.groupItem.isLongTerm ? '고정' : '단기',
                              style: ResponsiveHelper.smallStyle(
                                context,
                                color: widget.groupItem.isLongTerm 
                                    ? AppColors.longTermDark 
                                    : AppColors.shortTermDark,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          
                          // 플렉스 TO: 날짜 슬롯 수 뱃지 (리스트 모드만)
                          if (!widget.groupItem.isLongTerm &&
                              widget.displayMode == TOCardDisplayMode.list) ...[
                            Builder(builder: (context) {
                              final effectiveCount = widget.groupItem.isGroupDetailLoaded &&
                                      widget.groupItem.groupTOs.isNotEmpty
                                  ? widget.groupItem.groupTOs.length
                                  : masterTO.totalSlots;
                              if (effectiveCount < 1) return const SizedBox.shrink();
                              return Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: ResponsiveHelper.spacing(context, 6),
                                      vertical: ResponsiveHelper.spacing(context, 3),
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.infoBg,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: AppColors.infoLight),
                                    ),
                                    child: Text(
                                      '$effectiveCount일',
                                      style: ResponsiveHelper.smallStyle(
                                        context,
                                        color: AppColors.infoDark,
                                      ).copyWith(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              );
                            }),
                          ],

                          SizedBox(width: ResponsiveHelper.spacing(context, 8)),

                          // 사업장명
                          Expanded(
                            child: Text(
                              widget.groupItem.businessName,
                              style: ResponsiveHelper.smallStyle(
                                context,
                                color: AppColors.grey600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          
                          // 등록시간 (리스트 모드, 단건/고정만)
                          if (widget.displayMode == TOCardDisplayMode.list && !isMultiSlot) ...[
                            Text(
                              _getCreatedAtText(widget.groupItem.createdAt, now),
                              style: ResponsiveHelper.tinyStyle(
                                context,
                                color: AppColors.grey500,
                              ),
                            ),
                            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                          ],
                          
                          // 메뉴 버튼
                          _buildSingleTOMenu(context),
                        ],
                      ),
                      
                      SizedBox(height: ResponsiveHelper.spacing(context, 4)),

                      // ✨ 둘째 줄: 제목 (크게 강조!)
                      Text(
                        widget.groupItem.groupName,
                        style: ResponsiveHelper.titleStyle(context).copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),

                      SizedBox(height: ResponsiveHelper.spacing(context, 6)),

                      // ✨ 셋째 줄: 날짜 + 상태배지(multiSlot 인라인) / 인원현황(단건)
                      Row(
                        children: [
                          // 날짜 정보
                          Expanded(
                            child: Row(
                              children: [
                                Icon(
                                  Icons.event,
                                  size: ResponsiveHelper.iconSize(context, 14),
                                  color: AppColors.grey500,
                                ),
                                SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                                Expanded(
                                  child: Text(
                                    _getDateText(masterTO),
                                    style: ResponsiveHelper.bodyStyle(
                                      context,
                                      color: AppColors.grey700,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          SizedBox(width: ResponsiveHelper.spacing(context, 8)),

                          // multiSlot: 상태 배지 인라인 / 단건: 인원 현황 배지
                          if (isMultiSlot)
                            _buildStatusBadge(context,
                                allClosed: allClosed, targetTOs: targetTOs)
                          else
                            _buildPersonnelBadge(
                              context,
                              confirmed: totalConfirmed,
                              required: totalRequired,
                              pending: totalPending,
                              isFull: isFull,
                            ),
                        ],
                      ),

                      // multiSlot: 링 차트 + 통계 (헤더 흰 영역 안)
                      if (isMultiSlot) ...[
                        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                        _buildMultiSlotRingRow(context),
                      ],
                      
                      // 고정 공고 계약 기간
                      if (masterTO.isLongTerm && masterTO.contractPeriodLabel.isNotEmpty) ...[
                        Padding(
                          padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 4)),
                          child: Row(
                            children: [
                              Icon(
                                Icons.assignment_outlined,
                                size: ResponsiveHelper.iconSize(context, 13),
                                color: AppColors.longTermDark,
                              ),
                              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                              Text(
                                '계약 ${masterTO.contractPeriodLabel}',
                                style: ResponsiveHelper.smallStyle(
                                  context,
                                  color: AppColors.longTermDark,
                                ).copyWith(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // 장기공고 게시 마감일
                      if (masterTO.isLongTerm && !allClosed) ...[
                        Builder(builder: (context) {
                          final expiry = masterTO.formattedPostingExpiry;
                          if (expiry == null) return const SizedBox.shrink(); // 무기한
                          final isPast = masterTO.isPostingExpired;
                          return Padding(
                            padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 6)),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.calendar_month_outlined,
                                  size: ResponsiveHelper.iconSize(context, 14),
                                  color: isPast ? AppColors.grey500 : AppColors.warningDark,
                                ),
                                SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                                Text(
                                  '공고마감 $expiry',
                                  style: ResponsiveHelper.smallStyle(
                                    context,
                                    color: isPast ? AppColors.grey500 : AppColors.warningDark,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],

                      // 단기 단일슬롯 공고: 지원 마감시간
                      if (!masterTO.isLongTerm && !allClosed) ...[
                        Builder(builder: (context) {
                          final deadline = _getEarliestDeadline();
                          if (deadline == null) return const SizedBox.shrink();
                          final isPast = deadline.isBefore(now);
                          final remaining = deadline.difference(now);
                          final isSoon = !isPast && remaining.inHours < 2;
                          final label = isPast
                              ? '지원마감 ${FormatHelper.formatTime(deadline)}'
                              : isSoon
                                  ? '마감까지 ${_formatRemaining(remaining)}'
                                  : '지원마감 ${FormatHelper.formatTime(deadline)}';
                          return Padding(
                            padding: EdgeInsets.only(
                              top: ResponsiveHelper.spacing(context, 6),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.timer_off_outlined,
                                  size: ResponsiveHelper.iconSize(context, 14),
                                  color: isPast ? AppColors.grey500 : AppColors.warningDark,
                                ),
                                SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                                Text(
                                  label,
                                  style: ResponsiveHelper.smallStyle(
                                    context,
                                    color: isPast ? AppColors.grey500 : AppColors.warningDark,
                                  ),
                                ),
                                if (isSoon) ...[
                                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                                  _buildUrgentBadge(context),
                                ],
                              ],
                            ),
                          );
                        }),
                      ],
                      
                      // 장기 TO 게시만료 — 연장하기 버튼
                      if (masterTO.isPostingExpiredAndExtendable) ...[
                        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                        GestureDetector(
                          onTap: _isExtending
                              ? null
                              : () => _handleExtend(context, masterTO),
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: ResponsiveHelper.spacing(context, 12),
                              vertical: ResponsiveHelper.spacing(context, 5),
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context).primaryColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_isExtending)
                                  SizedBox(
                                    width: ResponsiveHelper.iconSize(context, 12),
                                    height: ResponsiveHelper.iconSize(context, 12),
                                    child: const CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: Colors.white,
                                    ),
                                  )
                                else
                                  Icon(
                                    Icons.refresh,
                                    size: ResponsiveHelper.iconSize(context, 13),
                                    color: Colors.white,
                                  ),
                                SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                                Text(
                                  '연장하기',
                                  style: ResponsiveHelper.smallStyle(context).copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],

                      // ✨ 상태 표시 — multiSlot은 날짜 옆 인라인 처리, 단건/고정만 여기서 표시
                      if (!isMultiSlot) ...[
                        SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                        _buildStatusBadge(context, allClosed: allClosed, targetTOs: targetTOs),
                      ],

                      // 펼침 힌트 — multiSlot은 항상 표시이므로 불필요
                      if (!isMultiSlot) ...[
                        SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                        Center(
                          child: Icon(
                            widget.isExpanded
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            size: ResponsiveHelper.iconSize(context, 20),
                            color: AppColors.grey400,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              
              // 펼쳐진 영역
              // multiSlot: 항상 표시 (접힘 없음)
              // 단건/고정: 기존 AnimatedSize 접힘 유지
              if (isMultiSlot)
                _buildMultiSlotSection(context, theme)
              else
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOutCubic,
                  alignment: Alignment.topCenter,
                  clipBehavior: Clip.antiAlias,
                  child: widget.isExpanded
                      ? TweenAnimationBuilder<double>(
                          key: ValueKey(widget.isExpanded),
                          tween: Tween(begin: 0.0, end: 1.0),
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeIn,
                          builder: (context, opacity, child) =>
                              Opacity(opacity: opacity, child: child!),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Divider(height: 1, color: AppColors.grey200),
                              Container(
                                decoration: BoxDecoration(
                                  color: AppColors.grey50,
                                  borderRadius: const BorderRadius.only(
                                    bottomLeft: Radius.circular(16),
                                    bottomRight: Radius.circular(16),
                                  ),
                                ),
                                child: Padding(
                                  padding: ResponsiveHelper.symmetricPadding(
                                      context, horizontal: 12, vertical: 10),
                                  child: _buildExpandedBodyContent(context, theme),
                                ),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
            ],
          ),
        ),
          ),
          // ✅ 좌측 컬러바 (Stack으로 위에 덮기)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 4,
              decoration: BoxDecoration(
                color: statusBarColor,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
        );
    if (!widget.isAnyExpanded) return cardContent;
    return AnimatedOpacity(
      opacity: isDimmed ? 0.45 : 1.0,
      duration: const Duration(milliseconds: 220),
      child: AnimatedScale(
        scale: isDimmed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 220),
        alignment: Alignment.topCenter,
        child: cardContent,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 펼침 영역 콘텐츠 (통합)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildExpandedBodyContent(BuildContext context, ThemeData theme) {
    // 로딩 중
    if (widget.isGroupLoading || _isSingleTOLoading()) {
      return Padding(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 24)),
        child: const LoadingWidget(message: '불러오는 중...'),
      );
    }

    // 다중 슬롯 flex TO (리스트 모드)
    final isMultiSlot = widget.displayMode == TOCardDisplayMode.list &&
        !widget.groupItem.isLongTerm &&
        widget.groupItem.groupTOs.length > 1;

    if (isMultiSlot) {
      return _buildMultiSlotLayout(context, theme, _getFilteredGroupTOs());
    }

    // 단건 슬롯 / 장기 / 캘린더 — 업무 상세
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 단기 단일슬롯: 슬롯 개별 제목 (있는 경우)
        if (!widget.groupItem.isLongTerm &&
            widget.groupItem.groupTOs.isNotEmpty)
          Builder(builder: (context) {
            final toItem = widget.groupItem.groupTOs.first;
            final slotTitle = toItem.slot?.title;
            if (slotTitle == null || slotTitle.isEmpty) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: EdgeInsets.only(
                  bottom: ResponsiveHelper.spacing(context, 12)),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 10),
                  vertical: ResponsiveHelper.spacing(context, 8),
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.grey200),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 8),
                        vertical: ResponsiveHelper.spacing(context, 4),
                      ),
                      decoration: BoxDecoration(
                        color: theme.primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        FormatHelper.formatDate(toItem.slot!.date),
                        style: ResponsiveHelper.smallStyle(
                          context,
                          color: theme.primaryColor,
                        ).copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 10)),
                    Expanded(
                      child: Text(
                        slotTitle,
                        style: ResponsiveHelper.bodyStyle(context).copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        // 업무 상세 헤더
        Row(
          children: [
            Icon(
              Icons.assignment,
              size: ResponsiveHelper.iconSize(context, 16),
              color: theme.primaryColor,
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            Text(
              '업무 상세',
              style: ResponsiveHelper.subtitleStyle(context)
                  .copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        // 업무 목록
        ..._getSingleTOWorkDetails().map((work) {
          final stats = _getSingleTOStats(work.id);
          return WorkDetailRow(
            work: work,
            confirmedCount: stats?['confirmed'] ?? 0,
            pendingCount: stats?['pending'] ?? 0,
            toItem: _getSingleTOItem(),
            firestoreService: widget.firestoreService,
            onChanged: widget.onChanged,
            onLocalStatsChanged: () => setState(() {}),
            onAffectedTOsChanged: widget.onAffectedTOsChanged,
          );
        }),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 다중 슬롯 레이아웃 — 링 차트 + 날짜 칩 + 당일 패널
  // ═══════════════════════════════════════════════════════════════

  /// multiSlot 카드 하단 섹션 — 접힘 없이 항상 표시
  Widget _buildMultiSlotSection(BuildContext context, ThemeData theme) {
    if (widget.isGroupLoading) {
      return Padding(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 24)),
        child: const LoadingWidget(message: '불러오는 중...'),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 1, color: AppColors.grey200),
        Container(
          decoration: const BoxDecoration(
            color: AppColors.grey50,
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
          ),
          child: Padding(
            padding: ResponsiveHelper.symmetricPadding(
                context, horizontal: 12, vertical: 10),
            child: _buildMultiSlotLayout(context, theme, _getFilteredGroupTOs()),
          ),
        ),
      ],
    );
  }

  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];
  String _weekdayLabel(DateTime d) => _weekdays[d.weekday - 1];

  /// 링 차트 + 확정/대기/미충원 통계 — 카드 헤더(흰 영역) 안에 표시
  Widget _buildMultiSlotRingRow(BuildContext context) {
    final c = _totalConfirmed, p = _totalPending, r = _totalRequired;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        TOCapacityRing(confirmed: c, pending: p, total: r),
        SizedBox(width: ResponsiveHelper.spacing(context, 16)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatRow(context, '확정', c, AppColors.success),
              SizedBox(height: ResponsiveHelper.spacing(context, 5)),
              _buildStatRow(context, '대기', p, AppColors.warning),
              SizedBox(height: ResponsiveHelper.spacing(context, 5)),
              _buildStatRow(context, '미충원', (r - c - p).clamp(0, r), AppColors.grey400),
            ],
          ),
        ),
      ],
    );
  }

  /// 칩 상태 색상 — 마감(회색) / 예약(앰버) / 진행중(primary)
  Color _chipStatusColor(ThemeData theme, TOItem item) {
    if (CloseStateUtils.isToItemClosed(item, widget.groupItem.masterTO, _buildNow)) {
      return AppColors.grey400;
    }
    final slotDate = item.slot?.date;
    if (slotDate != null) {
      final today = DateTime(_buildNow.year, _buildNow.month, _buildNow.day);
      if (DateTime(slotDate.year, slotDate.month, slotDate.day).isAfter(today)) {
        return AppColors.warning;
      }
    }
    return theme.primaryColor;
  }

  /// 날짜 칩 + 당일 패널 (링/통계는 카드 헤더로 이동됨)
  Widget _buildMultiSlotLayout(
      BuildContext context, ThemeData theme, List<TOItem> filteredTOs) {
    final selected = _selectedChipDate == null
        ? null
        : filteredTOs.cast<TOItem?>().firstWhere(
            (ti) =>
                ti!.slot?.date != null &&
                DateUtils.isSameDay(ti.slot!.date, _selectedChipDate!),
            orElse: () => null,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 날짜별 현황 헤더
        Row(
          children: [
            Icon(Icons.calendar_month, size: 13, color: AppColors.grey600),
            const SizedBox(width: 4),
            Text(
              '날짜별 현황',
              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey700)
                  .copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        // 가로 스크롤 날짜 칩
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: filteredTOs.map((ti) {
              final isSelected = ti.slot?.date != null &&
                  _selectedChipDate != null &&
                  DateUtils.isSameDay(ti.slot!.date, _selectedChipDate!);
              return _buildDateChip(context, theme, ti, isSelected);
            }).toList(),
          ),
        ),
        // 선택 날짜 슬롯 패널
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: selected == null
              ? const SizedBox.shrink()
              : _buildDayPanel(context, theme, selected),
        ),
      ],
    );
  }

  Widget _buildStatRow(BuildContext context, String label, int count, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          '$label ',
          style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
        ),
        Text(
          '$count명',
          style:
              ResponsiveHelper.smallStyle(context).copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  /// 날짜 칩 하나 (상태 탭 + 날짜 + 미니바 + 인원)
  Widget _buildDateChip(
      BuildContext context, ThemeData theme, TOItem ti, bool isSelected) {
    final slotDate = ti.slot?.date;
    final stats = ti.resolveStats();
    final statusColor = _chipStatusColor(theme, ti);

    return GestureDetector(
      onTap: () => _onChipTap(ti),
      child: Container(
        width: 62,
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: isSelected ? statusColor.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? statusColor : AppColors.grey200,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Stack(
          children: [
            // 상단 상태 색상 탭
            Positioned(
              top: 0,
              left: 6,
              right: 6,
              child: Container(
                height: 3,
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(2)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 11, 6, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (slotDate != null) ...[
                    Text(
                      _weekdayLabel(slotDate),
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.grey500, height: 1.2),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${slotDate.month}/${slotDate.day}',
                      style: ResponsiveHelper.smallStyle(context)
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                  ] else
                    Text('?', style: ResponsiveHelper.smallStyle(context)),
                  const SizedBox(height: 5),
                  _buildChipMiniBar(stats.confirmed, stats.pending, stats.required),
                  const SizedBox(height: 4),
                  Text(
                    '${stats.confirmed}/${stats.required}',
                    style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.grey600,
                        fontWeight: FontWeight.w600,
                        height: 1.2),
                  ),
                  if (stats.pending > 0)
                    Container(
                      margin: const EdgeInsets.only(top: 3),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '+${stats.pending}대기',
                        style: const TextStyle(
                            fontSize: 8,
                            color: AppColors.warning,
                            fontWeight: FontWeight.w800,
                            height: 1.2),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 확정(녹)/대기(앰버)/미충원(회) 3-레이어 수평 미니 바
  Widget _buildChipMiniBar(int confirmed, int pending, int required) {
    if (required <= 0) return const SizedBox(height: 3, width: 50);
    final confirmedF = (confirmed / required).clamp(0.0, 1.0);
    final pendingF = ((confirmed + pending) / required).clamp(0.0, 1.0);
    const w = 50.0;
    return SizedBox(
      height: 3,
      width: w,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.grey200,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (pendingF > 0)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: w * pendingF,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.warning,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          if (confirmedF > 0)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: w * confirmedF,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.success,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 선택된 날짜의 슬롯 상세 패널
  Widget _buildDayPanel(BuildContext context, ThemeData theme, TOItem toItem) {
    final itemKey = toItem.slot?.id ?? toItem.to.id;
    final isLoading = widget.loadingTOs.contains(itemKey);
    final workDetails = toItem.workDetails;

    return Container(
      margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 10)),
      decoration: BoxDecoration(
        color: AppColors.grey50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.grey200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 업무 상세 목록
          if (isLoading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: LoadingWidget(message: '불러오는 중...'),
            )
          else if (workDetails.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              child: Text(
                toItem.needsWorkDetailLoad ? '데이터 불러오는 중...' : '업무 상세 없음',
                style:
                    ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: workDetails.map((work) {
                  final stats = toItem.workDetailStats?[work.id];
                  return WorkDetailRow(
                    work: work,
                    confirmedCount: stats?['confirmed'] ?? 0,
                    pendingCount: stats?['pending'] ?? 0,
                    toItem: toItem,
                    firestoreService: widget.firestoreService,
                    onChanged: widget.onChanged,
                    onLocalStatsChanged: () => setState(() {}),
                    onAffectedTOsChanged: widget.onAffectedTOsChanged,
                  );
                }).toList(),
              ),
            ),
          // 명단 보기 버튼
          const Divider(height: 1, color: AppColors.grey200),
          InkWell(
            onTap: () => _showSlotRoster(context, toItem),
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline, size: 15, color: theme.primaryColor),
                  const SizedBox(width: 6),
                  Text(
                    '당일 명단 전체 보기',
                    style: ResponsiveHelper.smallStyle(context,
                            color: theme.primaryColor)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 날짜 칩 탭 핸들러
  void _onChipTap(TOItem toItem) {
    final slotDate = toItem.slot?.date;
    if (slotDate == null) return;

    final alreadySelected = _selectedChipDate != null &&
        DateUtils.isSameDay(_selectedChipDate!, slotDate);

    setState(() => _selectedChipDate = alreadySelected ? null : slotDate);

    if (alreadySelected) {
      // 칩 해제 → 부모에 비활성화 신호
      widget.onGroupDeactivated?.call();
    } else {
      // 아코디언: 이 카드가 활성화됨을 부모에 알림
      widget.onGroupActivated?.call(widget.groupItem.id);
      // 업무 상세 미로드 시 로드 트리거
      final itemKey = toItem.slot?.id ?? toItem.to.id;
      if (toItem.needsWorkDetailLoad &&
          !widget.loadingTOs.contains(itemKey) &&
          !widget.expandedTOs.contains(itemKey)) {
        widget.onToggleTOExpand(itemKey);
      }
    }
  }

  /// 당일 확정명단 다이얼로그 표시
  Future<void> _showSlotRoster(BuildContext context, TOItem toItem) async {
    if (!toItem.isWorkDetailLoaded || toItem.workDetails.isEmpty) {
      if (!mounted) return;
      showDialog(
        context: this.context,
        barrierDismissible: false,
        builder: (_) => const Center(child: LoadingWidget()),
      );
      try {
        final effectiveSlot = toItem.slot;
        final result = effectiveSlot != null
            ? await widget.firestoreService.loadTOWorkDetails(
                toItem.to,
                slotId: effectiveSlot.id,
                slotWorkDetails: effectiveSlot.workDetails,
              )
            : await widget.firestoreService.loadTOWorkDetails(toItem.to);
        toItem.setWorkDetails(
          result['workDetails'] as List<WorkDetailData>,
          result['workStats'] as Map<String, Map<String, int>>,
        );
      } catch (e) {
        if (mounted) {
          Navigator.pop(this.context);
          ToastHelper.showError('명단을 불러오는데 실패했습니다.');
        }
        return;
      }
      if (mounted) Navigator.pop(this.context);
    }
    if (!mounted) return;
    ConfirmedListDialog(
      context: this.context,
      toItem: toItem,
      firestoreService: widget.firestoreService,
      slotId: toItem.slot?.id,
      onLocalStatsChanged: () {
        if (mounted) setState(() {});
      },
    ).show();
  }

  // ═══════════════════════════════════════════════════════════════
  // ✨ 새로운 간소화된 위젯들
  // ═══════════════════════════════════════════════════════════════
  /// 등록일 텍스트
  String _getCreatedAtText(DateTime created, DateTime now) {
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

  /// 날짜 텍스트 생성
  String _getDateText(TOModel masterTO) {
    // 캘린더 슬롯 모드: 해당 슬롯 날짜만 표시
    if (widget.calendarSlot != null) {
      final date = widget.calendarSlot!.slot?.date ?? masterTO.rangeStart ?? DateTime.now();
      return FormatHelper.formatDate(date);
    }
    if (masterTO.isLongTerm) {
      return FormatHelper.formatWorkPeriod(
        startDate: masterTO.rangeStart ?? masterTO.createdAt,
        endDate: masterTO.endDate,
        isLongTerm: true,
        workDays: masterTO.workDays.isEmpty ? null : masterTO.workDays,
      );
    }
    // flex TO: 로드된 슬롯 수 우선, 없으면 totalSlots 사용
    final int count = widget.groupItem.isGroupDetailLoaded && widget.groupItem.groupTOs.isNotEmpty
        ? widget.groupItem.groupTOs.length
        : masterTO.totalSlots;

    // 슬롯 날짜 우선 사용 (rangeStart가 null인 기존 데이터 호환)
    final DateTime dateToShow;
    if (widget.groupItem.isGroupDetailLoaded && widget.groupItem.groupTOs.isNotEmpty) {
      final firstSlot = widget.groupItem.groupTOs.first;
      dateToShow = firstSlot.slot?.date ?? masterTO.rangeStart ?? masterTO.createdAt;
    } else {
      dateToShow = masterTO.rangeStart ?? masterTO.createdAt;
    }

    if (count <= 1) {
      return FormatHelper.formatDate(dateToShow);
    }
    return '${FormatHelper.formatDate(dateToShow)} 외 ${count - 1}일';
  }
/// ✨ 인원 현황 배지 (핵심 정보)
  Widget _buildPersonnelBadge(
    BuildContext context, {
    required int confirmed,
    required int required,
    required int pending,
    required bool isFull,
  }) {
    return PersonnelBadge(
      confirmed: confirmed,
      required: required,
      pending: pending,
      isFull: isFull,
    );
  }

  /// 그룹 카드 상태 배지
  ///
  /// allClosed 계산 책임은 호출자에 있음:
  ///   - 슬롯 미로드: groupItem.isClosed (TOGroupItem getter — isManualClosed 포함)
  ///   - 슬롯 로드됨: CloseStateUtils.isToItemClosed 전체 판단
  /// 상태 분류 자체는 SlotStatusUtil.groupStatus에 위임.
  Widget _buildStatusBadge(BuildContext context, {
    required bool allClosed,
    required List<TOItem> targetTOs,
  }) {
    final status = SlotStatusUtil.groupStatus(
      allClosed: allClosed,
      masterTO: widget.groupItem.masterTO,
      targetTOs: targetTOs,
    );
    final scheduledAt = SlotStatusUtil.groupScheduledAt(
      masterTO: widget.groupItem.masterTO,
      targetTOs: targetTOs,
    );
    return SlotStatusBadge(status: status, scheduledAt: scheduledAt);
  }

  Widget _buildUrgentBadge(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 6),
        vertical: ResponsiveHelper.spacing(context, 2),
      ),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '마감임박',
        style: ResponsiveHelper.tinyStyle(
          context,
          color: AppColors.warningDark,
        ).copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 메뉴 관련 (기존 유지)
  // ═══════════════════════════════════════════════════════════════

  /// 단일 TO 메뉴
  Widget _buildSingleTOMenu(BuildContext context) {
    return IconButton(
      icon: Icon(
        Icons.more_vert,
        size: ResponsiveHelper.iconSize(context, 20),
        color: AppColors.grey600,
      ),
      padding: EdgeInsets.zero,
      tooltip: '메뉴',
      onPressed: () => _showSingleTOMenuSheet(context),
    );
  }

  void _showSingleTOMenuSheet(BuildContext context) {
    if (widget.displayMode == TOCardDisplayMode.calendar) {
      _showCalendarMenuSheet(context);
      return;
    }
    final isContract = widget.groupItem.masterTO.isContractType;
    final isClosed = widget.groupItem.isClosed;
    final isManualClosed = widget.groupItem.isManualClosed;
    final up = context.read<UserProvider>();
    final user = up.currentUser;
    final canDelete = user?.isBusinessAdmin == true || user?.isSuperAdmin == true || up.can((p) => p.canManageTo);
    // TO-02: 쓰기 작업 항목은 canManageTo 권한 있을 때만 표시
    final canManageTo = up.can((p) => p.canManageTo);
    AppMenuSheet.show(
      context: context,
      itemGroups: [
        // 공고 상세보기 (contract 전용)
        if (isContract)
          [
            AppMenuSheetItem(
              icon: Icons.visibility,
              label: '공고 상세보기',
              color: AppColors.info,
              onTap: () => _handleSingleTOMenuAction(context, 'preview'),
            ),
          ],
        // 수정 (canManageTo)
        if (canManageTo)
          [
            AppMenuSheetItem(
              icon: isContract ? Icons.edit : Icons.edit_calendar,
              label: isContract ? '수정' : '일괄수정',
              color: AppColors.warning,
              onTap: () => _handleSingleTOMenuAction(context, isContract ? 'edit' : 'batchEdit'),
            ),
          ],
        // 마감 / 재오픈 (canManageTo)
        // [REG-UI02-01] isContract=true && isClosed=true && !isManualClosed 케이스에서 빈 itemGroup 방지
        if (canManageTo && (isClosed ? (!isContract || isManualClosed) : true))
          [
            if (isClosed) ...[
              if (isContract && isManualClosed)
                AppMenuSheetItem(
                  icon: Icons.lock_open,
                  label: '재오픈',
                  color: AppColors.success,
                  onTap: () => _handleSingleTOMenuAction(context, 'reopen'),
                ),
              if (!isContract)
                AppMenuSheetItem(
                  icon: Icons.lock_open,
                  label: '일괄재오픈',
                  color: AppColors.success,
                  onTap: () => _handleSingleTOMenuAction(context, 'batchReopen'),
                ),
            ] else ...[
              AppMenuSheetItem(
                icon: Icons.lock_outline,
                label: isContract ? '마감' : '일괄마감',
                color: AppColors.warning,
                onTap: () => _handleSingleTOMenuAction(context, isContract ? 'close' : 'batchClose'),
              ),
            ],
          ],
        // 확정명단 (읽기 전용 — 항상 표시) / 카드 제목 변경 (canManageTo)
        [
          AppMenuSheetItem(
            icon: Icons.check_circle_outline,
            label: '전체 확정명단',
            color: AppColors.success,
            onTap: () => _handleSingleTOMenuAction(context, 'confirmedList'),
          ),
          if (canManageTo)
            AppMenuSheetItem(
              icon: Icons.drive_file_rename_outline,
              label: '카드 제목 변경',
              color: AppColors.purple,
              onTap: () => _handleSingleTOMenuAction(context, 'renameCard'),
            ),
        ],
        // 삭제 (BUSINESS_ADMIN 이상만)
        if (canDelete)
          [
            AppMenuSheetItem(
              icon: Icons.delete,
              label: isContract ? '삭제' : '일괄삭제',
              color: AppColors.error,
              isDanger: true,
              onTap: () => _handleSingleTOMenuAction(context, isContract ? 'delete' : 'batchDelete'),
            ),
          ],
      ],
    );
  }

  /// 캘린더 모드 메뉴
  void _showCalendarMenuSheet(BuildContext context) {
    final theme = Theme.of(context);
    final isContract = widget.groupItem.masterTO.isContractType;
    final isClosed = widget.groupItem.isClosed;
    final isManualClosed = widget.groupItem.isManualClosed;
    final up = context.read<UserProvider>();
    final user = up.currentUser;
    final canDelete = user?.isBusinessAdmin == true || user?.isSuperAdmin == true || up.can((p) => p.canManageTo);
    // TO-02: 쓰기 작업 항목은 canManageTo 권한 있을 때만 표시
    final canManageTo = up.can((p) => p.canManageTo);

    if (isContract) {
      AppMenuSheet.show(
        context: context,
        itemGroups: [
          [
            AppMenuSheetItem(
              icon: Icons.visibility,
              label: '공고 상세보기',
              color: AppColors.info,
              onTap: () => _handleSingleTOMenuAction(context, 'preview'),
            ),
          ],
          if (canManageTo)
            [
              AppMenuSheetItem(
                icon: Icons.edit,
                label: '수정',
                color: AppColors.warning,
                onTap: () => _handleSingleTOMenuAction(context, 'edit'),
              ),
            ],
          // UI-02: 시간만료(isClosed=true, isManualClosed=false) 시 빈 그룹 제외
          if (canManageTo && ((isClosed && isManualClosed) || !isClosed))
            [
              if (isClosed && isManualClosed)
                AppMenuSheetItem(
                  icon: Icons.lock_open,
                  label: '재오픈',
                  color: AppColors.success,
                  onTap: () => _handleSingleTOMenuAction(context, 'reopen'),
                )
              else if (!isClosed)
                AppMenuSheetItem(
                  icon: Icons.lock_outline,
                  label: '마감',
                  color: AppColors.warning,
                  onTap: () => _handleSingleTOMenuAction(context, 'close'),
                ),
            ],
          [
            AppMenuSheetItem(
              icon: Icons.check_circle_outline,
              label: '전체 확정명단',
              color: AppColors.success,
              onTap: () => _handleSingleTOMenuAction(context, 'confirmedList'),
            ),
          ],
          if (canDelete)
            [
              AppMenuSheetItem(
                icon: Icons.delete,
                label: '삭제',
                color: AppColors.error,
                isDanger: true,
                onTap: () => _handleSingleTOMenuAction(context, 'delete'),
              ),
            ],
        ],
      );
    } else {
      // 단기 슬롯: calendarSlot 기준
      AppMenuSheet.show(
        context: context,
        itemGroups: [
          [
            AppMenuSheetItem(
              icon: Icons.visibility,
              label: '공고 상세보기',
              color: AppColors.info,
              onTap: () => _handleSingleTOMenuAction(context, 'preview'),
            ),
          ],
          if (canManageTo)
            [
              AppMenuSheetItem(
                icon: Icons.edit,
                label: '수정',
                color: AppColors.warning,
                onTap: () => _handleSingleTOMenuAction(context, 'edit'),
              ),
              if (canDelete)
                AppMenuSheetItem(
                  icon: Icons.delete,
                  label: '삭제',
                  color: AppColors.error,
                  isDanger: true,
                  onTap: () => _handleSingleTOMenuAction(context, 'delete'),
                ),
            ],
          [
            AppMenuSheetItem(
              icon: Icons.check_circle_outline,
              label: '확정명단',
              color: AppColors.success,
              onTap: () => _handleSingleTOMenuAction(context, 'confirmedList'),
            ),
            if (canManageTo)
              AppMenuSheetItem(
                icon: Icons.assignment_turned_in,
                label: '업무별 마감',
                color: theme.primaryColor,
                onTap: () => _handleSingleTOMenuAction(context, 'manageWorkDetails'),
              ),
          ],
        ],
      );
    }
  }

  /// 단일 TO 메뉴 액션
  Future<void> _handleSingleTOMenuAction(
      BuildContext context, String value) async {
    final masterTO = widget.groupItem.masterTO;

    switch (value) {
      case 'preview':
        if (widget.calendarSlot != null) {
          // 캘린더 단기 슬롯: 슬롯 기준 미리보기
          final calSlot = widget.calendarSlot!;
          final workDetails = _getSingleTOWorkDetails();
          if (workDetails.isEmpty && calSlot.needsWorkDetailLoad) {
            // 이 mounted 체크는 첫 await 이전이라 비동기 갭 보호 효과 없음 — 실질 보호는 1077/1081/1083행
            if (!mounted) return;
            showDialog(context: this.context, barrierDismissible: false,
                builder: (_) => const Center(child: LoadingWidget()));
            try {
              final result = await widget.firestoreService.loadTOWorkDetails(
                calSlot.to, slotId: calSlot.slot?.id, slotWorkDetails: calSlot.slot?.workDetails,
              );
              calSlot.setWorkDetails(
                result['workDetails'] as List<WorkDetailData>,
                result['workStats'] as Map<String, Map<String, int>>,
              );
            } catch (e) {
              if (mounted) {
                Navigator.pop(this.context);
                ToastHelper.showError('데이터를 불러오는데 실패했습니다.');
              }
              return;
            }
            if (mounted) Navigator.pop(this.context);
          }
          if (!mounted) return;
          final resolvedStats = calSlot.resolveStats();
          Navigator.push(this.context, MaterialPageRoute(
            builder: (_) => JobPostingScreen(
              to: calSlot.to,
              workDetails: calSlot.workDetails.isNotEmpty ? calSlot.workDetails : masterTO.workDetails,
              mode: TODetailMode.adminPreview,
              slotDate: calSlot.slot?.date,
              slotTotalRequired: resolvedStats.required,
              slotConfirmedCount: resolvedStats.confirmed,
              slotPendingCount: resolvedStats.pending,
              workDetailStats: calSlot.workDetailStats,
            ),
          ));
        } else {
          // contract TO: workDetails는 masterTO 문서에 직접 포함됨
          Navigator.push(
            this.context,
            MaterialPageRoute(
              builder: (_) => JobPostingScreen(
                to: masterTO,
                workDetails: masterTO.workDetails,
                mode: TODetailMode.adminPreview,
                slotTotalRequired: masterTO.totalRequired,
                slotConfirmedCount: masterTO.totalConfirmed,
                slotPendingCount: masterTO.totalPending,
                workDetailStats: widget.groupItem.workDetailStats,
              ),
            ),
          );
        }
        break;

      case 'edit':
        if (widget.calendarSlot != null) {
          // 캘린더 단기 슬롯: 슬롯 단위 수정
          await NavigationHelper.push<bool>(
            context,
            destination: AdminEditTOScreen(to: masterTO, slot: widget.calendarSlot!.slot),
            onReturn: (result) {
              if (result == true && mounted) {
                widget.firestoreService.clearCache(toId: masterTO.id);
                widget.onChanged();
              }
            },
          );
        } else {
          await NavigationHelper.push<bool>(
            context,
            destination: AdminEditTOScreen(to: masterTO),
            onReturn: (result) {
              if (result == true && mounted) {
                widget.firestoreService.clearCache();
                widget.onChanged();
              }
            },
          );
        }
        break;

      case 'batchEdit':
        final editSlots = await SlotBatchSelectDialog.show(
          context: context,
          to: masterTO,
          firestoreService: widget.firestoreService,
          title: '일괄수정 날짜 선택',
          confirmLabel: '수정',
        );
        if (editSlots == null || editSlots.isEmpty || !mounted) return;
        await NavigationHelper.push<bool>(
          this.context,
          destination: AdminEditTOScreen(to: masterTO, batchSlots: editSlots),
          onReturn: (result) {
            if (result == true && mounted) {
              widget.firestoreService.clearCache(toId: masterTO.id);
              widget.onChanged();
            }
          },
        );
        break;

      case 'batchClose':
        // uid는 await 이전에 캡처 (async gap 후 context 접근 방지)
        final closeUid = context.read<UserProvider>().currentUser?.uid ?? 'UNKNOWN';
        final closeSlots = await SlotBatchSelectDialog.show(
          context: context,
          to: masterTO,
          firestoreService: widget.firestoreService,
          title: '일괄마감 날짜 선택',
          confirmLabel: '마감',
          openOnly: true,
        );
        if (closeSlots == null || closeSlots.isEmpty || !mounted) return;
        final confirmed = await showDialog<bool>(
          context: this.context,
          builder: (dialogCtx) => StyledDialog(
            title: '일괄 마감',
            subtitle: '선택한 ${closeSlots.length}개 날짜를 마감하시겠습니까?',
            icon: Icons.lock_outline,
            headerColor: AppColors.warning,
            content: const SizedBox.shrink(),
            actions: [
              StyledDialogButton.cancel(
                  onPressed: () => Navigator.pop(dialogCtx, false)),
              StyledDialogButton.primary(
                text: '마감',
                backgroundColor: AppColors.warning,
                onPressed: () => Navigator.pop(dialogCtx, true),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
        try {
          await widget.firestoreService.batchCloseSlots(
            toId: masterTO.id,
            businessId: masterTO.businessId,
            slotIds: closeSlots.map((s) => s.id).toList(),
            closedBy: closeUid,
          );
          widget.firestoreService.clearCache(toId: masterTO.id);
          widget.onChanged();
          if (mounted) ToastHelper.showSuccess('${closeSlots.length}개 날짜가 마감되었습니다');
        } catch (e) {
          if (mounted) ToastHelper.showError('마감 처리에 실패했습니다');
        }
        break;

      case 'batchReopen':
        final reopenSlots = await SlotBatchSelectDialog.show(
          context: context,
          to: masterTO,
          firestoreService: widget.firestoreService,
          title: '일괄재오픈 날짜 선택',
          confirmLabel: '재오픈',
          closedAndReopenable: true,
        );
        if (reopenSlots == null || reopenSlots.isEmpty || !mounted) return;
        final reopenConfirmed = await showDialog<bool>(
          context: this.context,
          builder: (dialogCtx) => StyledDialog(
            title: '일괄 재오픈',
            subtitle: '선택한 ${reopenSlots.length}개 날짜를 재오픈하시겠습니까?',
            icon: Icons.lock_open,
            headerColor: AppColors.success,
            content: const SizedBox.shrink(),
            actions: [
              StyledDialogButton.cancel(
                  onPressed: () => Navigator.pop(dialogCtx, false)),
              StyledDialogButton.primary(
                text: '재오픈',
                onPressed: () => Navigator.pop(dialogCtx, true),
              ),
            ],
          ),
        );
        if (reopenConfirmed != true || !mounted) return;
        try {
          await widget.firestoreService.batchReopenSlots(
            toId: masterTO.id,
            slotIds: reopenSlots.map((s) => s.id).toList(),
            businessId: masterTO.businessId,
          );
          widget.firestoreService.clearCache(toId: masterTO.id);
          widget.onChanged();
          if (mounted) ToastHelper.showSuccess('${reopenSlots.length}개 날짜가 재오픈되었습니다');
        } catch (e) {
          if (mounted) ToastHelper.showError('재오픈 처리에 실패했습니다');
        }
        break;

      case 'batchDelete':
        final deleteSlots = await SlotBatchSelectDialog.show(
          context: context,
          to: masterTO,
          firestoreService: widget.firestoreService,
          title: '일괄삭제 날짜 선택',
          confirmLabel: '삭제',
        );
        if (deleteSlots == null || deleteSlots.isEmpty || !mounted) return;

        // 전체 슬롯 수 확인 — 마지막 날짜 삭제 시 공고 자체가 삭제됨을 안내
        final allSlots = await widget.firestoreService.getSlots(masterTO.id);
        if (!mounted) return;
        final deletesAll = deleteSlots.length >= allSlots.length;

        final deleteConfirmed = await showDialog<bool>(
          context: this.context,
          builder: (dialogCtx) => StyledDialog(
            title: '일괄 삭제',
            subtitle: deletesAll
                ? '모든 날짜를 삭제하면 공고 자체도 삭제됩니다.\n이 작업은 되돌릴 수 없습니다.'
                : '선택한 ${deleteSlots.length}개 날짜를 삭제하시겠습니까?\n이 작업은 되돌릴 수 없습니다.',
            icon: Icons.delete_forever,
            headerColor: AppColors.error,
            content: const SizedBox.shrink(),
            actions: [
              StyledDialogButton.cancel(
                  onPressed: () => Navigator.pop(dialogCtx, false)),
              StyledDialogButton.danger(
                text: '삭제',
                onPressed: () => Navigator.pop(dialogCtx, true),
              ),
            ],
          ),
        );
        if (deleteConfirmed != true || !mounted) return;
        try {
          await widget.firestoreService.batchDeleteSlots(
            toId: masterTO.id,
            businessId: masterTO.businessId,
            slotIds: deleteSlots.map((s) => s.id).toList(),
          );
          if (!mounted) return;
          if (deletesAll) {
            // 슬롯을 모두 삭제했으니 TO 문서도 삭제 (지원서·알림 포함)
            await widget.firestoreService.deleteTO(masterTO.id);
            if (mounted) ToastHelper.showSuccess('공고가 삭제되었습니다');
          } else {
            widget.firestoreService.clearCache(toId: masterTO.id);
            if (mounted) ToastHelper.showSuccess('${deleteSlots.length}개 날짜가 삭제되었습니다');
          }
          widget.onChanged();
        } catch (e) {
          if (mounted) ToastHelper.showError('삭제 처리에 실패했습니다');
        }
        break;

      case 'close':
        widget.dialogs.showCloseTODialog(masterTO);
        break;

      case 'reopen':
        widget.dialogs.showReopenTODialog(masterTO);
        break;

      case 'delete':
        // 캘린더 단기 슬롯: 해당 슬롯만 삭제
        if (widget.calendarSlot != null) {
          widget.dialogs.showDeleteTODialog(widget.calendarSlot!);
          break;
        }
        // Contract TO는 groupTOs가 비어있으므로 masterTO로 합성 TOItem 사용
        final deleteTarget = widget.groupItem.groupTOs.isNotEmpty
            ? widget.groupItem.groupTOs.first
            : TOItem(
                to: widget.groupItem.masterTO,
                confirmedCount: widget.groupItem.totalConfirmed,
                pendingCount: widget.groupItem.totalPending,
                totalRequired: widget.groupItem.totalRequired,
              );
        widget.dialogs.showDeleteTODialog(deleteTarget);
        break;

      case 'confirmedList':
        // 캘린더 슬롯 모드: 해당 슬롯 기준
        final TOItem toItemForConfirmed;
        if (widget.calendarSlot != null) {
          toItemForConfirmed = widget.calendarSlot!;
        } else if (widget.groupItem.groupTOs.isEmpty) {
          // Contract TO: groupItem의 workDetailStats를 공유 참조로 전달
          // → 확정명단에서 취소 시 in-place 갱신이 카드 확장 영역에도 즉시 반영됨
          toItemForConfirmed = TOItem(
            to: widget.groupItem.masterTO,
            confirmedCount: widget.groupItem.totalConfirmed,
            pendingCount: widget.groupItem.totalPending,
            totalRequired: widget.groupItem.totalRequired,
            workDetails: widget.groupItem.masterTO.workDetails,
            workDetailStats: widget.groupItem.workDetailStats,
            isWorkDetailLoaded: widget.groupItem.isWorkDetailLoaded,
          );
        } else {
          final selected = await _selectTOItem(this.context);
          if (selected == null || !mounted) return;
          toItemForConfirmed = selected;
        }

        if (!toItemForConfirmed.isWorkDetailLoaded || toItemForConfirmed.workDetails.isEmpty) {
          showDialog(
            context: this.context,
            barrierDismissible: false,
            builder: (_) => const Center(child: LoadingWidget()),
          );
          try {
            // toItemForConfirmed.slot 우선 사용 (리스트 뷰 날짜 선택 경로),
            // 없을 때만 calendarSlot 폴백 (캘린더 뷰 직접 탭 경로)
            final effectiveSlot = toItemForConfirmed.slot ?? widget.calendarSlot?.slot;
            final result = effectiveSlot != null
                ? await widget.firestoreService.loadTOWorkDetails(
                    toItemForConfirmed.to,
                    slotId: effectiveSlot.id,
                    slotWorkDetails: effectiveSlot.workDetails,
                  )
                : await widget.firestoreService.loadTOWorkDetails(toItemForConfirmed.to);
            toItemForConfirmed.setWorkDetails(
              result['workDetails'] as List<WorkDetailData>,
              result['workStats'] as Map<String, Map<String, int>>,
            );
          } catch (e) {
            if (mounted) {
              Navigator.pop(this.context);
              ToastHelper.showError('데이터를 불러오는데 실패했습니다.');
            }
            return;
          }
          if (mounted) Navigator.pop(this.context);
        }

        if (!mounted) return;
        ConfirmedListDialog(
          context: this.context,
          toItem: toItemForConfirmed,
          firestoreService: widget.firestoreService,
          slotId: toItemForConfirmed.slot?.id ?? widget.calendarSlot?.slot?.id,
          onLocalStatsChanged: () {
            if (mounted) setState(() {});
          },
        ).show();

      case 'renameCard':
        final currentTitle = masterTO.groupTitle ?? masterTO.title;
        final controller = TextEditingController(text: currentTitle);
        final newTitle = await showDialog<String>(
          context: this.context,
          barrierDismissible: false,
          builder: (ctx) => StyledDialog(
            title: '카드 제목 변경',
            subtitle: '공고 카드에 표시될 제목을 설정합니다',
            icon: Icons.drive_file_rename_outline,
            headerColor: AppColors.purple,
            content: StyledDialogTextField(
              controller: controller,
              labelText: '카드 제목',
              hintText: masterTO.title,
              prefixIcon: Icons.title,
              autofocus: true,
              onFieldSubmitted: (_) {
                FocusManager.instance.primaryFocus?.unfocus();
                Navigator.pop(ctx, controller.text.trim());
              },
            ),
            actions: [
              StyledDialogButton.cancel(
                onPressed: () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  Navigator.pop(ctx);
                },
              ),
              StyledDialogButton.primary(
                text: '저장',
                backgroundColor: AppColors.purple,
                onPressed: () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  Navigator.pop(ctx, controller.text.trim());
                },
              ),
            ],
          ),
        );
        WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
        if (newTitle == null || !mounted) return;
        try {
          await widget.firestoreService.updateTO(masterTO.id, {
            'groupTitle': newTitle.isNotEmpty ? newTitle : null,
          });
          widget.onChanged();
          if (mounted) ToastHelper.showSuccess('카드 제목이 변경되었습니다');
        } catch (e) {
          if (mounted) ToastHelper.showError('제목 변경에 실패했습니다');
        }
        break;

      case 'manageWorkDetails':
        // 캘린더 단기 슬롯: 업무별 마감 관리
        final toItemForManage = _getSingleTOItem();
        if (!toItemForManage.isWorkDetailLoaded || toItemForManage.workDetails.isEmpty) {
          if (!mounted) return;
          showDialog(context: this.context, barrierDismissible: false,
              builder: (_) => const Center(child: LoadingWidget()));
          try {
            final calSlotForManage = widget.calendarSlot;
            final result = calSlotForManage != null
                ? await widget.firestoreService.loadTOWorkDetails(
                    toItemForManage.to,
                    slotId: calSlotForManage.slot?.id,
                    slotWorkDetails: calSlotForManage.slot?.workDetails,
                  )
                : await widget.firestoreService.loadTOWorkDetails(toItemForManage.to);
            toItemForManage.setWorkDetails(
              result['workDetails'] as List<WorkDetailData>,
              result['workStats'] as Map<String, Map<String, int>>,
            );
          } catch (e) {
            if (mounted) {
              Navigator.pop(this.context);
              ToastHelper.showError('데이터를 불러오는데 실패했습니다.');
            }
            return;
          }
          if (mounted) Navigator.pop(this.context);
        }
        if (!mounted) return;
        WorkDetailManagementDialog(
          context: this.context,
          toItem: toItemForManage,
          firestoreService: widget.firestoreService,
          onComplete: widget.onChanged,
          onLocalStatsChanged: () {
            if (mounted) setState(() {});
          },
        ).show();
        break;
    }
  }

  /// 다중 슬롯 플렉스 TO에서 날짜 선택 다이얼로그
  /// 슬롯이 1개면 바로 반환, 여러 개면 날짜 선택 시트 표시
  Future<TOItem?> _selectTOItem(BuildContext context) async {
    final slots = widget.groupItem.groupTOs;
    if (slots.isEmpty) return null;
    if (slots.length == 1) return slots.first;

    return DialogHelper.showSheet<TOItem>(
      context,
      builder: (ctx) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 핸들바
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.grey300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // 헤더
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    '날짜 선택',
                    style: ResponsiveHelper.subtitleStyle(ctx).copyWith(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Text(
                    '총 ${slots.length}일',
                    style: ResponsiveHelper.smallStyle(ctx, color: AppColors.grey500),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Divider(height: 1, color: AppColors.grey100),
            const SizedBox(height: 4),

            // 날짜 목록
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final toItem in slots)
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => Navigator.pop(ctx, toItem),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            child: Row(
                              children: [
                                Container(
                                  width: ResponsiveHelper.spacing(ctx, 44),
                                  height: ResponsiveHelper.spacing(ctx, 44),
                                  decoration: BoxDecoration(
                                    color: Theme.of(ctx).primaryColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(
                                    Icons.event,
                                    color: Theme.of(ctx).primaryColor,
                                    size: ResponsiveHelper.iconSize(ctx, 22),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        FormatHelper.formatDate(toItem.slot?.date ?? toItem.to.date),
                                        style: ResponsiveHelper.bodyStyle(ctx).copyWith(fontWeight: FontWeight.w600),
                                      ),
                                      if (toItem.pendingCount > 0)
                                        Text(
                                          '대기 ${toItem.pendingCount}명',
                                          style: ResponsiveHelper.tinyStyle(ctx, color: AppColors.warningDark),
                                        ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: ResponsiveHelper.spacing(ctx, 8),
                                    vertical: ResponsiveHelper.spacing(ctx, 3),
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.infoBg,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '${toItem.confirmedCount}/${toItem.totalRequired}',
                                    style: ResponsiveHelper.smallStyle(ctx, color: AppColors.infoDark)
                                        .copyWith(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.chevron_right, color: AppColors.grey300, size: 20),
                              ],
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 단건 TO 로딩 중 여부
  bool _isSingleTOLoading() {
    if (widget.isGroupLoading) return true;
    // 캘린더 모드: isGroupLoading으로만 판단
    if (widget.calendarSlot != null) return false;
    if (widget.groupItem.groupTOs.isNotEmpty) {
      return widget.loadingTOs.contains(widget.groupItem.groupTOs.first.to.id);
    }
    return widget.loadingTOs.contains(widget.groupItem.id);
  }

  /// 단건 TO의 workDetails — 마감시간을 TO 설정으로 계산해 채워 반환
  List<WorkDetailData> _getSingleTOWorkDetails() {
    // 캘린더 슬롯 모드: 해당 슬롯의 workDetails 우선 사용
    if (widget.calendarSlot != null) {
      final calSlot = widget.calendarSlot!;
      final to = widget.groupItem.masterTO;
      final details = calSlot.slot?.workDetails.isNotEmpty == true
          ? calSlot.slot!.workDetails
          : calSlot.workDetails.isNotEmpty
              ? calSlot.workDetails
              : to.workDetails;
      final refDate = calSlot.slot?.date ?? to.rangeStart ?? DateTime.now();
      if (to.deadlineType != 'HOURS_BEFORE' || (to.hoursBeforeStart ?? 0) <= 0) {
        return details;
      }
      return details.map((d) {
        if (d.applicationDeadline != null) return d;
        final parts = d.startTime.split(':');
        if (parts.length != 2) return d;
        final deadline = DateTime(
          refDate.year, refDate.month, refDate.day,
          int.parse(parts[0]), int.parse(parts[1]),
        ).subtract(Duration(hours: to.hoursBeforeStart!));
        return d.copyWith(applicationDeadline: deadline);
      }).toList();
    }

    final to = widget.groupItem.masterTO;
    List<WorkDetailData> details;
    DateTime refDate;

    if (widget.groupItem.groupTOs.isNotEmpty) {
      final firstSlot = widget.groupItem.groupTOs.first;
      // slot.workDetails(SlotModel — loadGroupTOsLight에서 로드됨) 우선,
      // 없으면 TOItem._workDetails(loadWorkDetails에서 로드됨),
      // 그것도 없으면 마스터 TO 템플릿
      final slotWorkDetails = firstSlot.slot?.workDetails ?? [];
      details = slotWorkDetails.isNotEmpty
          ? slotWorkDetails
          : firstSlot.workDetails.isNotEmpty
              ? firstSlot.workDetails
              : to.workDetails;
      // 슬롯의 실제 날짜 사용, 없으면 마스터 TO 기준
      refDate = firstSlot.slot?.date ?? to.rangeStart ?? DateTime.now();
    } else {
      details = to.workDetails;
      if (!to.isFlexType) return details;
      refDate = to.rangeStart ?? DateTime.now();
    }

    // applicationDeadline이 없으면 TO 설정으로 계산 (기존 데이터 호환)
    if (to.deadlineType != 'HOURS_BEFORE' || (to.hoursBeforeStart ?? 0) <= 0) {
      return details;
    }
    return details.map((d) {
      if (d.applicationDeadline != null) return d;
      final parts = d.startTime.split(':');
      if (parts.length != 2) return d;
      final deadline = DateTime(
        refDate.year, refDate.month, refDate.day,
        int.parse(parts[0]), int.parse(parts[1]),
      ).subtract(Duration(hours: to.hoursBeforeStart!));
      return d.copyWith(applicationDeadline: deadline);
    }).toList();
  }

  /// 남은 시간을 "X시간 Y분" 또는 "Y분" 형태로 반환
  String _formatRemaining(Duration remaining) {
    if (remaining.isNegative) return '0분';
    final h = remaining.inHours;
    final m = remaining.inMinutes.remainder(60);
    if (h >= 1) return '$h시간 $m분';
    return '$m분';
  }

  /// 단기 단일슬롯 공고의 가장 이른 지원 마감시간 반환
  /// 슬롯이 2개 이상이면 null (슬롯별로 달라서 헤더에 표시 의미 없음)
  DateTime? _getEarliestDeadline() {
    final to = widget.groupItem.masterTO;
    if (to.isLongTerm) return null;
    // 캘린더 슬롯 모드: 이 슬롯 하나만 표시하므로 effectiveCount 검사 불필요
    if (widget.calendarSlot == null) {
      final effectiveCount = widget.groupItem.isGroupDetailLoaded &&
              widget.groupItem.groupTOs.isNotEmpty
          ? widget.groupItem.groupTOs.length
          : to.totalSlots;
      if (effectiveCount > 1) return null;
    }
    final workDetails = _getSingleTOWorkDetails();
    DateTime? earliest;
    for (final d in workDetails) {
      if (d.applicationDeadline == null) continue;
      if (earliest == null || d.applicationDeadline!.isBefore(earliest)) {
        earliest = d.applicationDeadline;
      }
    }
    return earliest;
  }

  /// 단건 TO의 work별 통계
  Map<String, int>? _getSingleTOStats(String workId) {
    if (widget.calendarSlot != null) {
      return widget.calendarSlot!.workDetailStats?[workId];
    }
    if (widget.groupItem.groupTOs.isNotEmpty) {
      return widget.groupItem.groupTOs.first.workDetailStats?[workId];
    }
    return widget.groupItem.workDetailStats?[workId];
  }

  /// WorkDetailRow에 전달할 TOItem 반환 (단건 TO는 합성 TOItem 생성)
  TOItem _getSingleTOItem() {
    if (widget.calendarSlot != null) return widget.calendarSlot!;
    if (widget.groupItem.groupTOs.isNotEmpty) {
      return widget.groupItem.groupTOs.first;
    }
    return TOItem(
      to: widget.groupItem.masterTO,
      confirmedCount: widget.groupItem.totalConfirmed,
      pendingCount: widget.groupItem.totalPending,
      totalRequired: widget.groupItem.totalRequired,
      workDetailStats: widget.groupItem.workDetailStats,
      isWorkDetailLoaded: widget.groupItem.isWorkDetailLoaded,
    );
  }

  /// 선택된 날짜에 해당하는 TO만 필터링
  List<TOItem> _getFilteredGroupTOs() {
    // selectedDate가 null이면 전체 표시 (리스트 뷰)
    if (widget.selectedDate == null) {
      return widget.groupItem.groupTOs;
    }
    
    // selectedDate가 있으면 해당 날짜 TO만 필터링 (캘린더 뷰)
    return widget.groupItem.groupTOs.where((toItem) {
      return DateUtils.isSameDay(toItem.slot?.date ?? toItem.to.date, widget.selectedDate!);
    }).toList();
  }
}

/// 인원 현황 배지 — 리스트/캘린더 뷰 공용
/// 게시기간 연장 일수 선택 바텀시트
class _ExtendDaysSheet extends StatelessWidget {
  final TOModel masterTO;
  const _ExtendDaysSheet({required this.masterTO});

  static const _options = [3, 5, 7, 10];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final end = masterTO.endDate;
    final now = DateTime.now();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 20),
        ResponsiveHelper.spacing(context, 20),
        ResponsiveHelper.spacing(context, 20),
        ResponsiveHelper.spacing(context, 24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '연장 기간 선택',
            style: ResponsiveHelper.titleStyle(context).copyWith(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
          Text(
            end != null ? '계약 종료일: ${FormatHelper.formatDate(end)}' : '',
            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          Builder(
            builder: (ctx) {
              final allDisabled = end != null &&
                  _options.every((d) => now.add(Duration(days: d)).isAfter(end));
              if (allDisabled) {
                return Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: ResponsiveHelper.spacing(context, 8),
                  ),
                  child: Text(
                    '계약 종료일까지 남은 기간이 짧아 선택 가능한 연장 기간이 없습니다.',
                    style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                  ),
                );
              }
              return Wrap(
                spacing: ResponsiveHelper.spacing(context, 10),
                runSpacing: ResponsiveHelper.spacing(context, 10),
                children: _options.map((days) {
                  final expiryDate = now.add(Duration(days: days));
                  final disabled = end != null && expiryDate.isAfter(end);
                  return GestureDetector(
                    onTap: disabled ? null : () => Navigator.of(context).pop(days),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 18),
                        vertical: ResponsiveHelper.spacing(context, 10),
                      ),
                      decoration: BoxDecoration(
                        color: disabled ? AppColors.grey100 : theme.primaryColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: disabled ? AppColors.grey300 : theme.primaryColor,
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '$days일',
                            style: ResponsiveHelper.bodyStyle(context).copyWith(
                              fontWeight: FontWeight.bold,
                              color: disabled ? AppColors.grey400 : theme.primaryColor,
                            ),
                          ),
                          if (!disabled && end != null)
                            Text(
                              '~${expiryDate.month}/${expiryDate.day}',
                              style: ResponsiveHelper.smallStyle(
                                context,
                                color: AppColors.grey600,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class PersonnelBadge extends StatelessWidget {
  final int confirmed;
  final int required;
  final int pending;
  final bool isFull;

  const PersonnelBadge({
    super.key,
    required this.confirmed,
    required this.required,
    required this.pending,
    required this.isFull,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 10),
        vertical: ResponsiveHelper.spacing(context, 6),
      ),
      decoration: BoxDecoration(
        color: isFull ? AppColors.successBg : AppColors.infoBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isFull ? AppColors.successLight : AppColors.infoLight,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isFull ? Icons.check_circle : Icons.people,
            size: ResponsiveHelper.iconSize(context, 14),
            color: isFull ? AppColors.successDark : AppColors.infoDark,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Text(
            // [S3-1 수정] CF syncTOStats 교정 전 낙관적 increment가 음수가 되는
            // 짧은 타이밍에 '-1/5' 형태로 표시되는 현상 방지
            required == 0 ? '미설정' : '${confirmed < 0 ? 0 : confirmed}/$required',
            style: ResponsiveHelper.bodyStyle(
              context,
              color: isFull ? AppColors.successDark : AppColors.infoDark,
            ).copyWith(fontWeight: FontWeight.bold),
          ),
          if (pending > 0)
            Text(
              ' +$pending',
              style: ResponsiveHelper.smallStyle(
                context,
                color: AppColors.warningDark,
              ),
            ),
        ],
      ),
    );
  }
}