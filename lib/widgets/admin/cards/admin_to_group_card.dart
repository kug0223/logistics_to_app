import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

// Models
import '../../../models/core/business_model.dart';
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
import '../../common/common_widgets.dart';

// Screens
import '../../../screens/business_admin/to_management/edit_to_screen.dart';

// Dialogs
import '../../../screens/business_admin/dialogs/day_applicants_dialog.dart';
import '../../../screens/business_admin/dialogs/to_list_dialogs.dart';
import '../../../screens/business_admin/dialogs/slot_batch_select_dialog.dart';
import '../../../screens/business_admin/dialogs/invite_worker_dialog.dart';
import '../../common/app_menu_sheet.dart';

// Providers
import 'package:provider/provider.dart';
import '../../../providers/user_provider.dart';
import '../../../widgets/dialogs/styled_dialog.dart';

// Local Widgets
import 'admin_work_detail.dart';
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
  /// 리스트 맨 마지막 카드 여부 — 날짜 칩 펼침 시 자동 스크롤 적용
  final bool isLastCard;

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
    this.isLastCard = false,
  });

  @override
  State<TOGroupCard> createState() => _TOGroupCardState();
}

class _TOGroupCardState extends State<TOGroupCard> {
  bool _isExtending = false;
  /// [4I.1] Close/Reopen/Delete 중복 실행 방어 — 연타 보호
  bool _isLifecycleActionRunning = false;

  // build() 내 O(N) 집계 캐시 — didUpdateWidget에서 갱신
  late List<TOItem> _targetTOs;
  late int _totalConfirmed;
  late int _totalPending;
  late int _totalRequired;
  late bool _isFull;
  DateTime _buildNow = DateTime.now();
  // [PERF-2] _getEarliestDeadline() 결과 캐시 — build()마다 workDetails 순회 방지
  // _updateGroupCache() 호출 시 갱신 (groupItem/selectedDate/calendarSlot 변경 시)
  DateTime? _cachedEarliestDeadline;

  // 날짜 칩 선택 상태 (다중 슬롯 뷰)
  DateTime? _selectedChipDate;
  final GlobalKey _panelBottomKey = GlobalKey();
  final GlobalKey _expandedBottomKey = GlobalKey();
  Timer? _scrollTimer;

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
    // [PERF-2] 마감시간 캐시 갱신
    _cachedEarliestDeadline = _computeEarliestDeadline();
  }

  /// [PERF-2] _getEarliestDeadline() 순수 계산 로직 — _updateGroupCache()에서만 호출
  DateTime? _computeEarliestDeadline() {
    final to = widget.groupItem.masterTO;
    if (to.isLongTerm) return null;
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

  @override
  void initState() {
    super.initState();
    _updateGroupCache();
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    super.dispose();
  }

  // [4I.1] CF 에러 → 사용자 메시지 변환 헬퍼
  // FirebaseFunctionsException의 message(서버 반환 문자열)를 우선 사용.
  // 서버 메시지가 없으면 fallback 사용.
  String _cfErrorMessage(Object error, {required String fallback}) {
    if (error is FirebaseFunctionsException) {
      final msg = error.message;
      if (msg != null && msg.isNotEmpty) return msg;
    }
    return fallback;
  }

  @override
  void didUpdateWidget(TOGroupCard old) {
    super.didUpdateWidget(old);
    if (!identical(widget.groupItem, old.groupItem) ||
        widget.selectedDate != old.selectedDate ||
        widget.calendarSlot != old.calendarSlot) {
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
    // 카드 접힐 때 날짜 칩 선택 초기화 (multiSlot 접힘 지원)
    if (old.isExpanded && !widget.isExpanded && _selectedChipDate != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedChipDate = null);
      });
    }
    // 마지막 카드 펼침 시 자동 스크롤 (모든 카드 타입)
    if (!old.isExpanded && widget.isExpanded && widget.isLastCard) {
      _scrollTimer?.cancel();
      _scrollTimer = Timer(const Duration(milliseconds: 350), () {
        if (!mounted) return;
        final ctx = _expandedBottomKey.currentContext;
        if (ctx == null) return;
        // ignore: use_build_context_synchronously
        Scrollable.ensureVisible(ctx,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut);
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
          final h = int.tryParse(parts[0]);
          final m = int.tryParse(parts[1]);
          if (h == null || m == null) return false;
          final deadline = DateTime(lastDate.year, lastDate.month, lastDate.day, h, m)
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
                color: AppColors.grey200,
                width: 1,
              ),
            ),
            child: Material(
          color: Colors.transparent,
          child: Column(
            children: [
              // ✨ 헤더 (클릭 가능)
              InkWell(
                // multiSlot: 비활성(isDimmed)→활성화, 활성→날짜패널 접기
                onTap: widget.onToggleExpand,
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
                            _buildSlotCountBadge(context, masterTO),
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

                          // multiSlot: 상태배지 인라인 / 단기 단건: 인원배지 / 고정: 도트 행에서 별도 표시
                          if (isMultiSlot) ...[
                            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                            _buildStatusBadge(context, allClosed: allClosed, targetTOs: targetTOs),
                          ] else if (!masterTO.isLongTerm) ...[
                            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                            _buildPersonnelBadge(
                              context,
                              confirmed: totalConfirmed,
                              required: totalRequired,
                              pending: totalPending,
                              isFull: isFull,
                            ),
                          ],
                        ],
                      ),

                      // multiSlot: 확정/대기/미충원 도트 요약 (collapsed summary)
                      if (isMultiSlot) ...[
                        SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                        Row(
                          children: [
                            Flexible(fit: FlexFit.loose, child: _buildDot(context, AppColors.success, '확정 $totalConfirmed')),
                            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                            Flexible(fit: FlexFit.loose, child: _buildDot(context, AppColors.warning, '대기 $totalPending')),
                            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                            Flexible(
                              fit: FlexFit.loose,
                              child: _buildDot(context, AppColors.grey400,
                                  '미충원 ${(totalRequired - totalConfirmed - totalPending).clamp(0, totalRequired)}'),
                            ),
                          ],
                        ),
                      ],
                      
                      // 고정 공고: 계약기간 + 공고마감 한 줄
                      if (masterTO.isLongTerm) ...[
                        _buildLongTermMeta(context, masterTO, allClosed),
                      ],

                      // 단기 단일슬롯 공고: 지원 마감시간
                      if (!masterTO.isLongTerm && !allClosed) ...[
                        _buildDeadlineMeta(context, now),
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

                      // 고정: 확정/대기/미충원 도트 + 모집중 칩 한 줄
                      if (masterTO.isLongTerm && !isMultiSlot) ...[
                        SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                        Row(
                          children: [
                            // Flexible: 3자리 숫자 등 긴 라벨 시 Row overflow 방지
                            Flexible(fit: FlexFit.loose, child: _buildDot(context, AppColors.success, '확정 $totalConfirmed')),
                            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                            Flexible(fit: FlexFit.loose, child: _buildDot(context, AppColors.warning, '대기 $totalPending')),
                            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                            Flexible(
                              fit: FlexFit.loose,
                              child: _buildDot(context, AppColors.grey400,
                                  '미충원 ${(totalRequired - totalConfirmed - totalPending).clamp(0, totalRequired)}'),
                            ),
                            const Spacer(),
                            _buildStatusBadge(context, allClosed: allClosed, targetTOs: targetTOs),
                          ],
                        ),
                      ],
                      // 단기 단건: 기존 상태 칩 유지
                      if (!masterTO.isLongTerm && !isMultiSlot) ...[
                        SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                        _buildStatusBadge(context, allClosed: allClosed, targetTOs: targetTOs),
                      ],

                      // 펼침 힌트 — 모든 카드 타입 표시
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
                  ),
                ),
              ),
              
              // 펼쳐진 영역 — 모든 카드 타입 통일 (multiSlot 포함)
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
                              const Divider(height: 1, color: AppColors.grey200),
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
                                  child: isMultiSlot
                                      ? (widget.isGroupLoading
                                          ? Padding(
                                              padding: EdgeInsets.all(
                                                  ResponsiveHelper.spacing(context, 24)),
                                              child: const LoadingWidget(message: '불러오는 중...'),
                                            )
                                          : _buildMultiSlotLayout(
                                              context, theme, _getFilteredGroupTOs()))
                                      : _buildExpandedBodyContent(context, theme),
                                ),
                              ),
                              SizedBox(key: _expandedBottomKey, height: 0),
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
    // [PERF-1] 항상 같은 위젯 타입 유지 — isAnyExpanded 전환 시 RenderObject 재생성 방지.
    // Dimming 제거: 모든 카드 정상 opacity 유지.
    // 이유: 관리자가 펼친 카드 외에도 다른 공고를 동시에 scan해야 함.
    // Accordion(한 번에 하나만 펼침)은 유지 — opacity 감소만 제거.
    return AnimatedOpacity(
      opacity: 1.0,
      duration: const Duration(milliseconds: 220),
      child: AnimatedScale(
        scale: 1.0,
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

    // 단건 슬롯 / 장기 / 캘린더 — 업무 상세
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 단기 단일슬롯: 슬롯 개별 제목 (있는 경우)
        if (!widget.groupItem.isLongTerm &&
            widget.groupItem.groupTOs.isNotEmpty)
          _buildSingleSlotTitle(context, theme),
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
  // 다중 슬롯 레이아웃 — 날짜 칩 + 당일 패널
  // ═══════════════════════════════════════════════════════════════

  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];
  String _weekdayLabel(DateTime d) => _weekdays[d.weekday - 1];

  /// 칩 상태 색상 — 마감(회색) / 예약(앰버) / 진행중(primary)
  Color _chipStatusColor(ThemeData theme, TOItem item) {
    if (CloseStateUtils.isToItemClosed(item, widget.groupItem.masterTO, _buildNow)) {
      return AppColors.grey400;
    }
    final slotDate = item.slot?.date;
    if (slotDate != null) {
      // [TZ-FIX] KST calendar date 기준 비교 — device timezone 무관
      final today = FormatHelper.toKstDate(_buildNow);
      if (FormatHelper.toKstDate(slotDate).isAfter(today)) {
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
          // 명단 보기 버튼 — _panelBottomKey: 칩 탭 시 이 위젯이 화면에 보이도록 스크롤
          const Divider(height: 1, color: AppColors.grey200),
          InkWell(
            key: _panelBottomKey,
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
      // 마지막 카드일 때만 패널 하단이 보이도록 스크롤
      if (widget.isLastCard) {
        _scrollTimer?.cancel();
        _scrollTimer = Timer(const Duration(milliseconds: 280), () {
          if (!mounted) return;
          final ctx = _panelBottomKey.currentContext;
          if (ctx == null) return;
          // ignore: use_build_context_synchronously
          Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        });
      }
    }
  }

  /// 당일 명단 다이얼로그 — DayApplicantsDialog를 해당 공고로 필터링해 표시
  Future<void> _showSlotRoster(BuildContext context, TOItem toItem) async {
    final date = toItem.slot?.date ?? _selectedChipDate;
    if (date == null || !mounted) return;
    final masterTO = widget.groupItem.masterTO;

    // DayApplicantsDialog 계약/신분증 기능을 위해 사업장 정보 로드
    // 실패 시 businesses:[] 로 열림 — 계약서·신분증 기능 비활성되므로 로그 필수
    BusinessModel? biz;
    try {
      biz = await widget.firestoreService.getBusinessById(masterTO.businessId);
    } catch (e) {
      debugPrint('⚠️ DayApplicantsDialog 사업장 정보 로드 실패 (${masterTO.businessId}): $e');
    }
    if (!mounted) return;

    final hasChanges = await showDialog<bool>(
      context: this.context,
      barrierDismissible: false,
      builder: (_) => DayApplicantsDialog(
        date: date,
        businessIds: [masterTO.businessId],
        businesses: biz != null ? [biz] : const [],
        filterToId: masterTO.id,
      ),
    );
    if (hasChanges == true && mounted) widget.onChanged();
  }

  // ═══════════════════════════════════════════════════════════════
  // ✨ 새로운 간소화된 위젯들
  // ═══════════════════════════════════════════════════════════════
  /// 등록일 텍스트
  String _getCreatedAtText(DateTime created, DateTime now) {
    final diff = now.difference(created);
    if (diff.isNegative) return '방금 전';
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
  Widget _buildDot(BuildContext context, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 3)),
        // Flexible: 외부에서 Flexible로 감싸면 bounded constraint 전달 → ellipsis 동작
        Flexible(
          child: Text(
            label,
            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }

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

    // [4I.1] closed 상태일 때 종료 원인에 따라 contextual 레이블 전달
    //   FULL       → '모집 완료' (인원 충족, 관리자 종료 아님)
    //   isManualClosed → '종료'  (관리자 직접 종료)
    //   TIME_EXPIRED   → '지원 마감' (applicationDeadline/근무시간 경과)
    //   POSTING_EXPIRED→ '공고 만료' (게시기간 경과)
    //   기타(legacy)   → null → '마감' fallback
    String? closedLabel;
    if (status == SlotDisplayStatus.closed) {
      final to = widget.groupItem.masterTO;
      if (widget.groupItem.isFull) {
        closedLabel = '모집 완료';
      } else if (to.isManualClosed) {
        closedLabel = '종료';
      } else if (widget.groupItem.closedReasonCode == 'TIME_EXPIRED') {
        closedLabel = '지원 마감';
      } else if (widget.groupItem.closedReasonCode == 'POSTING_EXPIRED') {
        closedLabel = '공고 만료';
      }
    }

    return SlotStatusBadge(
      status: status,
      scheduledAt: scheduledAt,
      closedLabel: closedLabel,
    );
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
    final isFull = widget.groupItem.isFull; // [4I.1A] FULL guard용
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
              label: '지원자 화면 미리보기',
              color: AppColors.info,
              onTap: () => _handleSingleTOMenuAction(context, 'preview'),
            ),
          ],
        // 수정 (canManageTo) — [4H.0B-CLOSED-01] isClosed 시 Edit 숨김 (재오픈 후 수정)
        if (canManageTo && !isClosed)
          [
            AppMenuSheetItem(
              icon: isContract ? Icons.edit : Icons.edit_calendar,
              label: isContract ? '수정' : '일괄수정',
              color: AppColors.warning,
              onTap: () => _handleSingleTOMenuAction(context, isContract ? 'edit' : 'batchEdit'),
            ),
          ],
        // [4I.1] 마감 / 재오픈 — lifecycle semantics 기반 정확한 분기
        // CONTRACT
        //   !isClosed → 공고 종료
        //   isManualClosed=true → 공고 재오픈 (callableUpdateTO)
        //   TIME_EXPIRED/POSTING_EXPIRED → 재오픈 HIDE (badge로 상태 전달)
        // FLEX
        //   !isClosed → 일괄 종료
        //   isManualClosed=true(TO level) → 공고 재오픈 (callableUpdateTO)
        //   !isManualClosed && hasReopenableManualSlots → 종료한 날짜 재오픈 (callableReopenSlots)
        //   FULL / TIME_EXPIRED / eligible slots 없음 → HIDE
        if (canManageTo) ...[
          if (isContract) ...[
            if (!isClosed)
              [
                AppMenuSheetItem(
                  icon: Icons.lock_outline,
                  label: '공고 종료',
                  color: AppColors.warning,
                  onTap: () => _handleSingleTOMenuAction(context, 'close'),
                ),
              ],
            if (isClosed && isManualClosed)
              [
                AppMenuSheetItem(
                  icon: Icons.lock_open,
                  label: '공고 재오픈',
                  color: AppColors.success,
                  onTap: () => _handleSingleTOMenuAction(context, 'reopen'),
                ),
              ],
            // CONTRACT TIME_EXPIRED / POSTING_EXPIRED: 재오픈 HIDE (연장하기 버튼 별도 존재)
          ] else ...[
            // FLEX
            if (!isClosed)
              [
                AppMenuSheetItem(
                  icon: Icons.lock_outline,
                  label: '일괄 종료',
                  color: AppColors.warning,
                  onTap: () => _handleSingleTOMenuAction(context, 'batchClose'),
                ),
              ],
            if (isClosed && isManualClosed)
              [
                AppMenuSheetItem(
                  icon: Icons.lock_open,
                  label: '공고 재오픈',
                  color: AppColors.success,
                  onTap: () => _handleSingleTOMenuAction(context, 'reopen'),
                ),
              ],
            // FLEX: slot 수동 종료된 eligible date 존재 시에만 표시
            // [4I.1A] FULL guard 추가 — FULL 상태에서는 서버가 차단하므로 메뉴도 숨김
            if (isClosed && !isManualClosed && !isFull &&
                widget.groupItem.hasReopenableManualSlots)
              [
                AppMenuSheetItem(
                  icon: Icons.lock_open,
                  label: '종료한 날짜 재오픈',
                  color: AppColors.success,
                  onTap: () => _handleSingleTOMenuAction(context, 'batchReopen'),
                ),
              ],
            // FULL / TIME_EXPIRED / eligible 없음: 재오픈 HIDE
          ],
        ],
        if (canManageTo)
          [
            AppMenuSheetItem(
              icon: Icons.drive_file_rename_outline,
              label: '관리용 카드명 변경',
              color: AppColors.purple,
              onTap: () => _handleSingleTOMenuAction(context, 'renameCard'),
            ),
          ],
        // 근로자 초대 / 보낸 초대 관리 (canManageTo)
        if (canManageTo)
          [
            AppMenuSheetItem(
              icon: Icons.person_add_outlined,
              label: '인력 초대',
              color: AppColors.success,
              onTap: () => _showInviteWorkerDialog(context),
            ),
            AppMenuSheetItem(
              icon: Icons.mail_outline,
              label: '보낸 초대 관리',
              color: AppColors.info,
              onTap: () => _showSentInvitesSheet(context),
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
              label: '지원자 화면 미리보기',
              color: AppColors.info,
              onTap: () => _handleSingleTOMenuAction(context, 'preview'),
            ),
          ],
          // [4H.0B-CLOSED-02] 캘린더 뷰 contract TO — isClosed 시 수정 숨김 (재오픈 후 수정)
          if (canManageTo && !isClosed)
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
                  label: '공고 종료',
                  color: AppColors.warning,
                  onTap: () => _handleSingleTOMenuAction(context, 'close'),
                ),
            ],
          if (canManageTo)
            [
              AppMenuSheetItem(
                icon: Icons.person_add_outlined,
                label: '인력 초대',
                color: AppColors.success,
                onTap: () => _showInviteWorkerDialog(context),
              ),
              AppMenuSheetItem(
                icon: Icons.mail_outline,
                label: '보낸 초대 관리',
                color: AppColors.info,
                onTap: () => _showSentInvitesSheet(context),
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
              label: '지원자 화면 미리보기',
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
          if (canManageTo)
            [
              AppMenuSheetItem(
                icon: Icons.person_add_outlined,
                label: '인력 초대',
                color: AppColors.success,
                onTap: () => _showInviteWorkerDialog(context),
              ),
              AppMenuSheetItem(
                icon: Icons.mail_outline,
                label: '보낸 초대 관리',
                color: AppColors.info,
                onTap: () => _showSentInvitesSheet(context),
              ),
            ],
          if (canManageTo)
            [
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

  /// 인력 초대 다이얼로그 (일반 모드 — TO 카드 메뉴 진입)
  void _showInviteWorkerDialog(BuildContext context) {
    final masterTO = widget.groupItem.masterTO;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => InviteWorkerDialog(
        groupItem: widget.groupItem,
        businessId: masterTO.businessId,
        businessName: widget.groupItem.businessName,
      ),
    );
  }

  /// 보낸 초대 관리 바텀시트 — INVITED 상태 지원서 목록 + 취소 버튼
  Future<void> _showSentInvitesSheet(BuildContext context) async {
    final toId = widget.groupItem.masterTO.id;
    final businessId = widget.groupItem.masterTO.businessId;
    if (toId.isEmpty || businessId.isEmpty) return;

    await DialogHelper.showSheet<void>(
      context,
      isScrollControlled: true,
      builder: (ctx) => _SentInvitesSheet(toId: toId, businessId: businessId),
    );
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
            final rootNav = Navigator.of(context, rootNavigator: true);
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
              if (mounted) ToastHelper.showError('데이터를 불러오는데 실패했습니다.');
              return;
            } finally {
              if (rootNav.mounted && rootNav.canPop()) rootNav.pop();
            }
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
          // [4H.0C-CLOSED-03] 슬롯 레벨 마감 체크 — TO 레벨 가드는 1301줄에서 처리됨
          if (widget.calendarSlot!.slot?.isClosed == true) {
            ToastHelper.showError('종료된 날짜는 수정할 수 없습니다. 먼저 재오픈해주세요.');
            return;
          }
          // 캘린더 단기 슬롯: 슬롯 단위 수정
          await NavigationHelper.push<bool>(
            context,
            useRootNavigator: true,
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
            useRootNavigator: true,
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
          openOnly: true, // [4H.0C-CLOSED-02] 마감된 슬롯 선택 방지
        );
        if (editSlots == null || editSlots.isEmpty || !mounted) return;
        await NavigationHelper.push<bool>(
          this.context,
          useRootNavigator: true,
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
        // [4I.1] 로딩 guard — 연타 방지
        if (_isLifecycleActionRunning) return;
        // uid는 await 이전에 캡처 (async gap 후 context 접근 방지)
        final closeUid = context.read<UserProvider>().currentUser?.uid ?? 'UNKNOWN';
        final closeSlots = await SlotBatchSelectDialog.show(
          context: context,
          to: masterTO,
          firestoreService: widget.firestoreService,
          title: '종료할 날짜 선택',
          confirmLabel: '종료',
          openOnly: true,
        );
        if (closeSlots == null || closeSlots.isEmpty || !mounted) return;
        final confirmed = await showDialog<bool>(
          context: this.context,
          barrierDismissible: false,
          builder: (dialogCtx) => StyledDialog(
            title: '날짜 종료',
            subtitle: '선택한 ${closeSlots.length}개 날짜를 종료할까요?',
            icon: Icons.lock_outline,
            headerColor: AppColors.warning,
            // [4I.1] PENDING 거절 영향 명시 + 재오픈 가능 안내
            content: StyledDialogInfoCard.warning(
              '종료한 날짜는 신규 지원을 받지 않으며, 대기 중인 지원자는 거절 처리됩니다.\n'
              '확정된 근무 기록은 유지됩니다.\n\n'
              '근무 전 날짜는 종료 후 다시 열 수 있습니다.',
            ),
            actions: [
              StyledDialogButton.cancel(
                  onPressed: () => Navigator.pop(dialogCtx, false)),
              StyledDialogButton.primary(
                text: '종료',
                backgroundColor: AppColors.warning,
                onPressed: () => Navigator.pop(dialogCtx, true),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
        setState(() => _isLifecycleActionRunning = true);
        try {
          await widget.firestoreService.batchCloseSlots(
            toId: masterTO.id,
            businessId: masterTO.businessId,
            slotIds: closeSlots.map((s) => s.id).toList(),
            closedBy: closeUid,
          );
          widget.firestoreService.clearCache(toId: masterTO.id);
          if (mounted) {
            widget.onChanged();
            ToastHelper.showSuccess('${closeSlots.length}개 날짜가 종료되었습니다');
          }
        } catch (e) {
          if (mounted) {
            final msg = _cfErrorMessage(e, fallback: '종료 처리에 실패했습니다');
            ToastHelper.showError(msg);
          }
        } finally {
          if (mounted) setState(() => _isLifecycleActionRunning = false);
        }
        break;

      case 'batchReopen':
        // [4I.1] 로딩 guard — 연타 방지
        if (_isLifecycleActionRunning) return;
        final reopenSlots = await SlotBatchSelectDialog.show(
          context: context,
          to: masterTO,
          firestoreService: widget.firestoreService,
          // [4I.1] "종료한 날짜 재오픈" copy
          title: '다시 열 날짜 선택',
          confirmLabel: '다시 열기',
          closedAndReopenable: true,
        );
        if (reopenSlots == null || reopenSlots.isEmpty || !mounted) return;
        final reopenConfirmed = await showDialog<bool>(
          context: this.context,
          barrierDismissible: false,
          builder: (dialogCtx) => StyledDialog(
            // [4I.1] 제목/설명 copy 업데이트
            title: '날짜 다시 열기',
            subtitle: '종료한 ${reopenSlots.length}개 날짜를 다시 열까요?',
            icon: Icons.lock_open,
            headerColor: AppColors.success,
            content: StyledDialogInfoCard.info(
              '선택한 날짜가 모집 중으로 전환됩니다.\n'
              '이미 거절된 지원자는 재지원이 필요합니다.',
            ),
            actions: [
              StyledDialogButton.cancel(
                  onPressed: () => Navigator.pop(dialogCtx, false)),
              StyledDialogButton.primary(
                text: '다시 열기',
                onPressed: () => Navigator.pop(dialogCtx, true),
              ),
            ],
          ),
        );
        if (reopenConfirmed != true || !mounted) return;
        setState(() => _isLifecycleActionRunning = true);
        try {
          final result = await widget.firestoreService.batchReopenSlots(
            toId: masterTO.id,
            slotIds: reopenSlots.map((s) => s.id).toList(),
            businessId: masterTO.businessId,
          );
          widget.firestoreService.clearCache(toId: masterTO.id);
          if (mounted) {
            widget.onChanged();
            // [4I.1] Partial success UX — CF 응답 reopenedCount 비교
            final requestedCount = reopenSlots.length;
            final reopenedCount =
                result.containsKey('reopenedCount')
                    ? (result['reopenedCount'] as int? ?? requestedCount)
                    : requestedCount;
            if (reopenedCount < requestedCount) {
              ToastHelper.showWarning(
                '$requestedCount개 중 $reopenedCount개 날짜를 다시 열었습니다.',
              );
            } else {
              ToastHelper.showSuccess('$reopenedCount개 날짜를 다시 열었습니다.');
            }
          }
        } catch (e) {
          if (mounted) {
            final msg = _cfErrorMessage(e, fallback: '날짜 재오픈에 실패했습니다');
            ToastHelper.showError(msg);
          }
        } finally {
          if (mounted) setState(() => _isLifecycleActionRunning = false);
        }
        break;

      case 'batchDelete':
        // [4I.1] 로딩 guard — 연타 방지
        if (_isLifecycleActionRunning) return;
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
          barrierDismissible: false,
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
        setState(() => _isLifecycleActionRunning = true);
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
            if (mounted) {
              widget.onChanged();
              ToastHelper.showSuccess('공고가 삭제되었습니다');
            }
          } else {
            widget.firestoreService.clearCache(toId: masterTO.id);
            if (mounted) {
              widget.onChanged();
              ToastHelper.showSuccess('${deleteSlots.length}개 날짜가 삭제되었습니다');
            }
          }
        } catch (e) {
          if (mounted) {
            final msg = _cfErrorMessage(e, fallback: '삭제 처리에 실패했습니다');
            ToastHelper.showError(msg);
          }
        } finally {
          if (mounted) setState(() => _isLifecycleActionRunning = false);
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

      case 'renameCard':
        final currentTitle = masterTO.groupTitle ?? masterTO.title;
        final controller = TextEditingController(text: currentTitle);
        final newTitle = await showDialog<String>(
          context: this.context,
          barrierDismissible: false,
          builder: (ctx) => StyledDialog(
            title: '관리용 카드명 변경',
            subtitle: '공고 카드에 표시될 관리용 이름을 설정합니다',
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
          final rootNav = Navigator.of(context, rootNavigator: true);
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
            if (mounted) ToastHelper.showError('데이터를 불러오는데 실패했습니다.');
            return;
          } finally {
            if (rootNav.mounted && rootNav.canPop()) rootNav.pop();
          }
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

  /// 단건 TO 로딩 중 여부
  bool _isSingleTOLoading() {
    if (widget.isGroupLoading) return true;
    // 캘린더 모드: isGroupLoading으로만 판단
    if (widget.calendarSlot != null) return false;
    if (widget.groupItem.groupTOs.isNotEmpty) {
      final firstTO = widget.groupItem.groupTOs.first;
      return widget.loadingTOs.contains(firstTO.slot?.id ?? firstTO.to.id);
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
        final h = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        if (h == null || m == null) return d;
        final deadline = DateTime(refDate.year, refDate.month, refDate.day, h, m)
            .subtract(Duration(hours: to.hoursBeforeStart!));
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
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h == null || m == null) return d;
      final deadline = DateTime(refDate.year, refDate.month, refDate.day, h, m)
          .subtract(Duration(hours: to.hoursBeforeStart!));
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

  /// 단기 단일슬롯 공고의 가장 이른 지원 마감시간 반환 (캐시 사용)
  /// 실제 계산은 _computeEarliestDeadline() — _updateGroupCache()에서 갱신됨
  DateTime? _getEarliestDeadline() => _cachedEarliestDeadline;

  // ─── [PERF-3] Builder → private helper 메서드 ────────────────────────────

  /// 플렉스 TO: 날짜 슬롯 수 뱃지 (리스트 모드만)
  Widget _buildSlotCountBadge(BuildContext context, TOModel masterTO) {
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
  }

  /// 고정 공고: 계약기간 + 공고마감 한 줄
  Widget _buildLongTermMeta(BuildContext context, TOModel masterTO, bool allClosed) {
    final hasContract = masterTO.contractPeriodLabel.isNotEmpty;
    final expiry = !allClosed ? masterTO.formattedPostingExpiry : null;
    final hasExpiry = expiry != null;
    if (!hasContract && !hasExpiry) return const SizedBox.shrink();
    final isPast = masterTO.isPostingExpired;
    return Padding(
      padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 4)),
      child: Row(
        children: [
          if (hasContract) ...[
            Icon(Icons.assignment_outlined,
                size: ResponsiveHelper.iconSize(context, 13),
                color: AppColors.longTermDark),
            SizedBox(width: ResponsiveHelper.spacing(context, 4)),
            Text('계약 ${masterTO.contractPeriodLabel}',
                style: ResponsiveHelper.smallStyle(context,
                        color: AppColors.longTermDark)
                    .copyWith(fontWeight: FontWeight.w600)),
          ],
          if (hasContract && hasExpiry) ...[
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Text('·',
                style: ResponsiveHelper.smallStyle(context,
                    color: AppColors.grey400)),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          ],
          if (hasExpiry) ...[
            Icon(Icons.calendar_month_outlined,
                size: ResponsiveHelper.iconSize(context, 13),
                color: isPast ? AppColors.grey500 : AppColors.warningDark),
            SizedBox(width: ResponsiveHelper.spacing(context, 4)),
            Text('지원 마감 $expiry',
                style: ResponsiveHelper.smallStyle(context,
                    color: isPast ? AppColors.grey500 : AppColors.warningDark)),
          ],
        ],
      ),
    );
  }

  /// 단기 단일슬롯 공고: 지원 마감시간 표시
  Widget _buildDeadlineMeta(BuildContext context, DateTime now) {
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
      padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 6)),
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
  }

  /// 단기 단일슬롯: 슬롯 개별 제목 (있는 경우)
  Widget _buildSingleSlotTitle(BuildContext context, ThemeData theme) {
    final toItem = widget.groupItem.groupTOs.first;
    final slotTitle = toItem.slot?.title;
    if (slotTitle == null || slotTitle.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
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
  }

  // ─────────────────────────────────────────────────────────────────────────

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

// ────────────────────────────────────────────────────────────────────────────
// 보낸 초대 관리 바텀시트
// ────────────────────────────────────────────────────────────────────────────

class _SentInvitesSheet extends StatefulWidget {
  final String toId;
  final String businessId;

  const _SentInvitesSheet({required this.toId, required this.businessId});

  @override
  State<_SentInvitesSheet> createState() => _SentInvitesSheetState();
}

class _SentInvitesSheetState extends State<_SentInvitesSheet> {
  // ─── 포맷터 캐싱 (itemBuilder 항목마다 재생성 방지) ──────────
  static final _expiryFmt = DateFormat('MM/dd HH:mm');

  bool _isLoading = true;
  List<Map<String, dynamic>> _invites = [];
  String? _cancelingId;

  @override
  void initState() {
    super.initState();
    _loadInvites();
  }

  Future<void> _loadInvites() async {
    // [BUG-07 수정] Firestore 직접 list → CF 경유 (SuperAdmin 전용 규칙 우회)
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetApplicationsByBiz');
      final result = await callable.call<Map<String, dynamic>>({
        'businessId': widget.businessId,
        'toId': widget.toId,
        'status': 'INVITED',
        'limit': 100,
      });

      if (!mounted) return;
      final raw = (result.data['applications'] as List? ?? [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();

      setState(() {
        _invites = raw;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ToastHelper.showError('초대 목록을 불러오지 못했습니다.');
    }
  }

  Future<void> _cancelInvite(String applicationId) async {
    final confirmed = await DialogHelper.showDangerConfirm(
      context,
      title: '초대 취소',
      message: '이 근로자의 초대를 취소하시겠습니까?',
      confirmText: '취소하기',
    );
    if (!confirmed) return;

    setState(() => _cancelingId = applicationId);
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableCancelTOInvitation');
      await callable.call({'applicationId': applicationId});

      if (!mounted) return;
      ToastHelper.showSuccess('초대가 취소되었습니다.');
      setState(() {
        _invites.removeWhere((inv) => inv['id'] == applicationId);
        _cancelingId = null;
      });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() => _cancelingId = null);
      ToastHelper.showError(e.message ?? '초대 취소에 실패했습니다.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _cancelingId = null);
      ToastHelper.showError('초대 취소에 실패했습니다.');
    }
  }

  String _formatExpiry(dynamic expiresAt) {
    if (expiresAt == null) return '';
    try {
      DateTime dt;
      if (expiresAt is Timestamp) {
        dt = expiresAt.toDate().toLocal();
      } else if (expiresAt is Map) {
        // CF serializeFirestoreData → {_seconds, _nanoseconds}
        final seconds = (expiresAt['_seconds'] as num?)?.toInt() ?? 0;
        dt = DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true).toLocal();
      } else {
        return '';
      }
      return '만료: ${_expiryFmt.format(dt)}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: 20,
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Row(
            children: [
              Icon(Icons.mail_outline, color: AppColors.info, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '보낸 초대 관리',
                  style: ResponsiveHelper.bodyStyle(context)
                      .copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              if (!_isLoading)
                Text(
                  '${_invites.length}건',
                  style: ResponsiveHelper.smallStyle(
                    context,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '수락 대기 중인 초대 목록입니다. 만료 전 취소할 수 있습니다.',
            style: ResponsiveHelper.smallStyle(
              context,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),

          // 본문
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_invites.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  '대기 중인 초대가 없습니다.',
                  style: ResponsiveHelper.bodyStyle(
                    context,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.45,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _invites.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) {
                  final inv = _invites[i];
                  final appId = inv['id'] as String? ?? '';
                  final uid = inv['uid'] as String? ?? '';
                  final workerName = inv['applicantName'] as String? ?? uid; // [BUG-02 수정] CF 저장 필드명 applicantName
                  final expiryLabel = _formatExpiry(inv['inviteExpiresAt']);
                  final isCanceling = _cancelingId == appId;

                  return Container(
                    decoration: CommonWidgets.compactCardDecoration(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                workerName,
                                style: ResponsiveHelper.bodyStyle(context)
                                    .copyWith(fontWeight: FontWeight.w600),
                              ),
                              if (expiryLabel.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  expiryLabel,
                                  style: ResponsiveHelper.smallStyle(
                                    context,
                                    color: AppColors.warning,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        isCanceling
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : TextButton(
                                onPressed: () => _cancelInvite(appId),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.error,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(
                                  '취소',
                                  style: ResponsiveHelper.smallStyle(
                                    context,
                                    color: AppColors.error,
                                  ).copyWith(fontWeight: FontWeight.bold),
                                ),
                              ),
                      ],
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
