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

// Controllers
import '../../../controllers/workforce_controller.dart';

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
import '../../../screens/business_admin/to_management/create_to_screen.dart'; // [REPOST-R1]

// Dialogs
import '../../../screens/business_admin/dialogs/day_applicants_dialog.dart';
import '../../../screens/business_admin/dialogs/work_applicants_dialog.dart';
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
  /// [POSTING-V2-01B] 이 공고의 슬롯/상세 조회가 실패한 상태.
  /// true면 펼침 영역을 '슬롯 없음'이 아니라 error로 표시한다.
  final bool hasGroupDetailError;
  /// [POSTING-V2-01B] 슬롯/상세 재조회 — 부모가 canonical load 경로를 넘긴다.
  final VoidCallback? onRetryGroupDetail;
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
    this.hasGroupDetailError = false,
    this.onRetryGroupDetail,
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
      // [SYSTEM-INTEGRATION-R2.4 §9] 헤더와 날짜 칩이 같은 source를 쓴다.
      //
      //   헤더는 슬롯 문서의 denormalized 카운터(`slot.confirmedCount` /
      //   `slot.pendingCount`)를 더했고, 같은 카드의 날짜 칩과 업무 행은
      //   `resolveStats()`(지원서 집계)를 썼다. 한 카드 안에서 두 수치가
      //   갈라질 수 있었다.
      //
      //   특히 `slot.pendingCount`는 초대 발송 시 +1 되었다가 syncTOStats가
      //   PENDING만 세어 다시 내리는 값이라, 관리자에게 보여 줄 `대기`의
      //   truth가 아니다. `resolveStats()`는 이미 통계 실패를 알고
      //   (`workDetailStatsFailed`) 그때만 슬롯 카운터로 폴백한다.
      int c = 0, p = 0, r = 0;
      for (final t in _targetTOs) {
        final s = t.resolveStats();
        c += s.confirmed;
        p += s.pending;
        r += s.required;
      }
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

    // [POSTING-V2-03S.1] 좌측 컬러바 제거.
    //   한 요소가 타입(단기=info / 고정=teal)과 lifecycle(마감=grey)을 겸해,
    //   같은 자리에서 말하는 축이 상태 전이 중에 바뀌었다. 타입은 1행의
    //   `단기`/`고정` 텍스트 배지가, 상태는 SlotStatusBadge가 각각 맡는다.
    //
    //   shadow도 뺐다 — Home이 flat으로 간 이유(AH-V2-05C)와 같다.
    //   반복 목록 카드이므로 경계는 border 하나로 충분하고, chrome이 세 겹일
    //   이유가 없다. 카드 사이 간격은 목록이 소유한다(listPadding).
    final cardContent = Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
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
                // [POSTING-V2-03R.1] 아래에 액션 바가 항상 붙으므로 헤더의
                //   하단 모서리는 더 이상 카드의 모서리가 아니다.
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
                child: Padding(
                  padding: ResponsiveHelper.symmetricPadding(context, horizontal: 12, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // [POSTING-V2-03R.1] 첫째 줄: 타입 + 사업장 + 메뉴
                      //   `N시간 전`(createdAt)을 뺐다 — 더 이상 정렬 기준도
                      //   운영 판단 정보도 아니고, 사업장명의 폭만 먹었다.
                      //   슬롯 수 배지도 뺐다 — 아래 `남은 N일`과 같은 말을
                      //   두 번 하는 데다, 그쪽은 끝난 날짜를 세지 않는다.
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

                          // 메뉴 버튼
                          _buildSingleTOMenu(context),
                        ],
                      ),

                      SizedBox(height: ResponsiveHelper.spacing(context, 2)),

                      // [POSTING-V2-03R.1] 둘째 줄: 언제 — 목록 스캔의 1차 축.
                      //   03Q.1이 목록을 근무 날짜순으로 바꾼 뒤, 관리자가 카드에서
                      //   가장 먼저 찾아야 하는 값이 여기다. 관리용 제목에 있던
                      //   시각적 1순위를 이 줄로 옮겼다.
                      _buildWhenLine(
                        context,
                        masterTO: masterTO,
                        allClosed: allClosed,
                        targetTOs: targetTOs,
                      ),

                      SizedBox(height: ResponsiveHelper.spacing(context, 5)),

                      // [POSTING-V2-03R.1] 셋째 줄: 어떤 일 / 얼마나 남았나
                      _buildWorkLine(context, masterTO: masterTO, now: now),

                      // [POSTING-V2-03R.1] 넷째 줄: 관리용 카드명 — 보조 정보.
                      //   관리자가 붙이는 식별값이라 지우지 않지만, 실제 업무명보다
                      //   앞선 공고 정체성으로 쓰지 않는다.
                      ..._buildManagedTitleLine(context),

                      SizedBox(height: ResponsiveHelper.spacing(context, 6)),

                      // [POSTING-V2-03R.1] 다섯째 줄: 인원 — 세 variant 동일 언어.
                      //   `필요 R`을 항상 숫자로 말한다. 이전에는 FLEX 다중과
                      //   CONTRACT가 확정/대기/미충원 점 세 개만 보여줘서,
                      //   정작 "몇 명 필요한가"에 직답이 없었다.
                      _buildStaffingLine(
                        context,
                        confirmed: totalConfirmed,
                        required: totalRequired,
                        pending: totalPending,
                        isFull: isFull,
                      ),

                      // 고정 공고: 공고 마감일 (계약기간은 _buildWorkLine으로 이동)
                      if (masterTO.isLongTerm) ...[
                        _buildLongTermMeta(context, masterTO, allClosed),
                      ],

                      // 단기 단일슬롯 공고: 지원 마감시간
                      if (!masterTO.isLongTerm && !allClosed) ...[
                        _buildDeadlineMeta(context, now),
                      ],
                    ],
                  ),
                ),
              ),

              // [POSTING-V2-03R.1] 액션 바 — 헤더 InkWell **바깥**이다.
              //   안에 두면 CTA 탭이 카드 펼침과 함께 걸린다(double trigger).
              _buildActionBar(context),

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

    // [POSTING-V2-01B] 슬롯 조회 실패 — TO 템플릿 workDetails를 실제 현황처럼
    // 보여주면 조회 장애가 정상 데이터로 둔갑한다. 이 카드 범위만 error로 표시.
    if (widget.hasGroupDetailError) {
      return _buildDetailErrorBox(
        context,
        message: '근무 일정을 불러오지 못했습니다',
        onRetry: widget.onRetryGroupDetail,
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
            // [POSTING-V2-01B] 통계 조회 실패 여부 — 0으로 표시하지 않기 위해
            statsFailed: _singleTOStatsFailed(),
            onRetryStats: () => _retrySingleTOStats(),
          );
        }),
      ],
    );
  }

  /// [POSTING-V2-01B] 단건/장기 카드의 통계 조회 실패 여부.
  /// _getSingleTOStats와 같은 우선순위로 source를 고른다.
  bool _singleTOStatsFailed() {
    if (widget.calendarSlot != null) {
      return widget.calendarSlot!.workDetailStatsFailed;
    }
    if (widget.groupItem.groupTOs.isNotEmpty) {
      return widget.groupItem.groupTOs.first.workDetailStatsFailed;
    }
    return widget.groupItem.workDetailStatsFailed;
  }

  /// [POSTING-V2-01B] 단건/장기 카드 통계 재조회.
  /// 기존 loadTOWorkDetails를 그대로 재사용한다 — 신규 API 없음.
  Future<void> _retrySingleTOStats() async {
    final target = widget.calendarSlot ??
        (widget.groupItem.groupTOs.isNotEmpty
            ? widget.groupItem.groupTOs.first
            : null);
    if (target != null) {
      await _retryWorkDetailStats(target);
      return;
    }
    // groupTOs가 없는 단건/장기 TO — 통계는 TOGroupItem에 저장된다
    final group = widget.groupItem;
    setState(() => group.resetWorkDetailStats());
    try {
      final result =
          await widget.firestoreService.loadTOWorkDetails(group.masterTO);
      group.setWorkDetailStats(
        result['workStats'] as Map<String, Map<String, int>>,
        statsFailed: result['statsFailed'] == true,
      );
    } catch (e) {
      debugPrint('❌ 업무 통계 재조회 실패: $e');
      group.markWorkDetailStatsFailed();
    }
    if (mounted) setState(() {});
  }

  /// [POSTING-V2-01B] 슬롯 단위 통계 재조회.
  Future<void> _retryWorkDetailStats(TOItem item) async {
    setState(() => item.resetWorkDetailLoad());
    try {
      final result = await widget.firestoreService.loadTOWorkDetails(
        item.to,
        slotId: item.slot?.id,
        slotWorkDetails: item.slot?.workDetails,
      );
      item.setWorkDetails(
        result['workDetails'] as List<WorkDetailData>,
        result['workStats'] as Map<String, Map<String, int>>,
        statsFailed: result['statsFailed'] == true,
      );
    } catch (e) {
      debugPrint('❌ 업무 통계 재조회 실패: $e');
      item.markWorkDetailStatsFailed();
    }
    if (mounted) setState(() {});
  }

  /// [POSTING-V2-01B] 카드 내부 조회 실패 표시 — 기존 톤/spacing 재사용.
  /// root 전체를 ERROR로 올리지 않고 실패한 범위만 표시한다.
  Widget _buildDetailErrorBox(
    BuildContext context, {
    required String message,
    VoidCallback? onRetry,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: ResponsiveHelper.spacing(context, 16),
        horizontal: ResponsiveHelper.spacing(context, 8),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded,
              size: ResponsiveHelper.iconSize(context, 16),
              color: AppColors.grey500),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(
              message,
              style: ResponsiveHelper.smallStyle(context,
                  color: AppColors.grey600),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 8)),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text('재시도',
                  style: ResponsiveHelper.smallStyle(context,
                          color: Theme.of(context).primaryColor)
                      .copyWith(fontWeight: FontWeight.w600)),
            ),
        ],
      ),
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
                          fontSize: 12, color: AppColors.grey500, height: 1.2),
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
                        fontSize: 12,
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
                            fontSize: 12,
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
                    // [POSTING-V2-01B] 이 슬롯의 통계 조회 실패 여부
                    statsFailed: toItem.workDetailStatsFailed,
                    onRetryStats: () => _retryWorkDetailStats(toItem),
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
    if (hasChanges == true && mounted) {
      widget.onChanged();
      // [POSTING-V2-02B.2] 확정·거절·초대·좌석 반납은 Home 인력 현황에 영향을 준다
      WorkforceController.notifyDataChanged(
        origin: AdminMutationOrigin.jobs,
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // [POSTING-V2-03R.1] collapsed 정보 구조
  //
  // 카드가 답해야 하는 순서: 언제 → 어떤 일/어디 → 인원 → 모집 상태 → 다음 행동.
  // 모든 요약은 **priority date의 실제 데이터**에서 나온다. 값을 하나로 확정할
  // 수 없으면 대표값을 지어내지 않고 "N개"라고 말하거나 생략한다 —
  // 첫 workDetail을 대표로 쓰면 나머지가 없는 것처럼 보인다.
  // ═══════════════════════════════════════════════════════════════

  /// 요약의 재료가 되는 workDetails. priority date 기준이다.
  List<WorkDetailData> _collapsedWorkDetails(TOModel masterTO) {
    final calSlot = widget.calendarSlot;
    if (calSlot != null) {
      final slotDetails = calSlot.slot?.workDetails ?? const <WorkDetailData>[];
      if (slotDetails.isNotEmpty) return slotDetails;
      return calSlot.workDetails.isNotEmpty
          ? calSlot.workDetails
          : masterTO.workDetails;
    }
    if (masterTO.isLongTerm) return masterTO.workDetails;

    // FLEX — priority date의 슬롯. 그 슬롯을 못 찾으면 다른 날짜의 업무를
    //   이 날짜의 것처럼 보여주지 않는다.
    final slot = widget.groupItem.operationalSlot;
    if (slot == null) return const [];
    final slotDetails = slot.slot?.workDetails ?? const <WorkDetailData>[];
    return slotDetails.isNotEmpty ? slotDetails : slot.workDetails;
  }

  /// collapsed 날짜 문구. 모르면 null.
  String? _collapsedDateText(TOModel masterTO) {
    // 캘린더 모드는 이미 날짜가 선택된 문맥이다.
    final calSlot = widget.calendarSlot;
    if (calSlot != null) {
      final date = calSlot.slot?.date;
      return date == null ? null : FormatHelper.formatDate(date);
    }
    if (masterTO.isLongTerm) {
      final start = masterTO.rangeStart;
      // rangeStart가 없으면 createdAt으로 대체하지 않는다 — 등록일은 근무일이 아니다.
      if (start == null) return null;
      return FormatHelper.formatWorkPeriod(
        startDate: start,
        endDate: masterTO.rangeEnd,
        isLongTerm: true,
        workDays: masterTO.workDays.isEmpty ? null : masterTO.workDays,
      );
    }
    // FLEX — controller가 정렬에 쓴 그 날짜를 그대로 쓴다.
    final date = widget.groupItem.operationalDate;
    return date == null ? null : FormatHelper.formatDate(date);
  }

  /// collapsed 시간 문구. 하나로 확정되지 않으면 개수로 말한다.
  String? _collapsedTimeText(TOModel masterTO) =>
      collapsedTimeSummary(_collapsedWorkDetails(masterTO));

  /// collapsed 업무 문구. 여러 업무를 하나로 대표하지 않는다.
  String? _collapsedWorkText(TOModel masterTO) =>
      collapsedWorkSummary(_collapsedWorkDetails(masterTO));

  /// FLEX 남은 운영 날짜 수. 종료된 날짜는 세지 않는다.
  String? _collapsedRemainingText(TOModel masterTO, DateTime now) {
    if (masterTO.isLongTerm) {
      final label = masterTO.contractPeriodLabel;
      return label.isEmpty ? null : '계약 $label';
    }
    if (widget.calendarSlot != null) return null;
    // 슬롯을 못 읽었으면 개수를 주장하지 않는다.
    if (!widget.groupItem.isGroupDetailLoaded) return null;
    final open = widget.groupItem.openSlotCount(now);
    return open <= 0 ? null : '남은 $open일';
  }

  /// [4] 언제 — 날짜·시간 + 모집 상태.
  ///
  /// Wrap을 쓴다: 상태 배지가 길어도(`9/20 14:00 공개 예정`) 날짜를 0폭으로
  /// 밀어내지 못하고 다음 줄로 내려간다.
  Widget _buildWhenLine(
    BuildContext context, {
    required TOModel masterTO,
    required bool allClosed,
    required List<TOItem> targetTOs,
  }) {
    final date = _collapsedDateText(masterTO);
    final time = _collapsedTimeText(masterTO);
    final String label;
    if (date == null) {
      // ERROR != UNKNOWN — 조회 실패를 '미정'으로 덮지 않는다.
      label = widget.hasGroupDetailError ? '근무일 확인 필요' : '근무일 미정';
    } else {
      label = time == null ? date : '$date · $time';
    }
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: ResponsiveHelper.spacing(context, 8),
      runSpacing: ResponsiveHelper.spacing(context, 4),
      children: [
        Text(
          label,
          style: ResponsiveHelper.subtitleStyle(
            context,
            color: date == null ? AppColors.grey500 : AppColors.textPrimary,
          ).copyWith(height: 1.25),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        _buildStatusBadge(
            context, allClosed: allClosed, targetTOs: targetTOs),
      ],
    );
  }

  /// [5] 어떤 일 · 얼마나 남았나.
  Widget _buildWorkLine(
    BuildContext context, {
    required TOModel masterTO,
    required DateTime now,
  }) {
    final parts = <String>[];
    final work = _collapsedWorkText(masterTO);
    if (work != null) parts.add(work);
    final remaining = _collapsedRemainingText(masterTO, now);
    if (remaining != null) parts.add(remaining);
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(
      parts.join(' · '),
      style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey700),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// [6] 관리용 카드명 — 보조 정보.
  ///
  /// 지우지 않는다(관리자가 붙인 식별값이다). 다만 실제 업무명과 같은 말이면
  /// 한 줄을 낭비할 뿐이므로 생략한다.
  List<Widget> _buildManagedTitleLine(BuildContext context) {
    final name = widget.groupItem.groupName;
    if (name.isEmpty) return const [];
    if (name == _collapsedWorkText(widget.groupItem.masterTO)) return const [];
    return [
      SizedBox(height: ResponsiveHelper.spacing(context, 2)),
      Text(
        name,
        // [POSTING-V2-03S.1] grey500 → grey600. 위계는 그대로 secondary지만
        //   흰 배경 위 13px grey500은 읽히지 않는 수준이었다. 크기·굵기는 유지.
        style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ];
  }

  /// [7] 인원 — 세 variant 공통 언어.
  ///
  /// `확정`과 `대기`를 합치지 않는다. 지원은 관심이고 확정은 약속이라,
  /// 둘을 더한 숫자는 채워지지 않은 자리를 채워진 것처럼 보이게 한다.
  /// `미충원`(required-confirmed-pending)은 여기서 쓰지 않는다 — 그 정의를
  /// 이번 IA에서 확대하지 않기 위해 원천 상태 셋만 말한다.
  Widget _buildStaffingLine(
    BuildContext context, {
    required int confirmed,
    required int required,
    required int pending,
    required bool isFull,
  }) {
    // CF syncTOStats 교정 전 낙관적 increment가 음수로 보이는 순간 방어
    final safeConfirmed = confirmed < 0 ? 0 : confirmed;
    final base = ResponsiveHelper.bodyStyle(context, color: AppColors.grey700);
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(style: base, children: [
        TextSpan(
          text: '확정 $safeConfirmed',
          style: base.copyWith(
            fontWeight: FontWeight.bold,
            color: isFull ? AppColors.successDark : AppColors.textPrimary,
          ),
        ),
        TextSpan(
          text: required == 0 ? ' / 필요 미설정' : ' / 필요 $required',
        ),
        const TextSpan(text: '  ·  '),
        TextSpan(
          text: '대기 $pending',
          style: base.copyWith(
            color: pending > 0 ? AppColors.warningDark : AppColors.grey500,
          ),
        ),
      ]),
    );
  }

  /// [8] 액션 바 — collapsed에서 발견 가능한 유일한 운영 CTA.
  ///
  /// 역할 분담: 카드 본체 tap = 더 보기 / `지원 현황` = 지원자 처리 / `⋮` = 관리.
  /// 이 바는 헤더 InkWell 바깥에 있어 CTA가 펼침과 함께 걸리지 않는다.
  Widget _buildActionBar(BuildContext context) {
    final target = _applicantTarget();
    return Container(
      // [POSTING-V2-03S.1] 카드 안의 separator는 한 tone만 쓴다.
      //   아래 expanded divider와 같은 grey200 — 이유 없이 두 회색이 섞여 있었다.
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.grey200)),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              // target이 없으면 어디로 갈지 확정할 수 없다 — 임의의 업무/날짜로
              //   들어가는 대신 기존 펼침 선택 흐름으로 넘긴다.
              onTap: target == null
                  ? widget.onToggleExpand
                  : () => _openApplicants(context, target),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(widget.isExpanded ? 0 : 16),
              ),
              child: Padding(
                padding: ResponsiveHelper.symmetricPadding(context,
                    horizontal: 12, vertical: 9),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.people_outline,
                        size: ResponsiveHelper.iconSize(context, 15),
                        color: Theme.of(context).primaryColor),
                    SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                    Flexible(
                      child: Text(
                        '지원 현황',
                        style: ResponsiveHelper.smallStyle(context,
                                color: Theme.of(context).primaryColor)
                            .copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          InkWell(
            onTap: widget.onToggleExpand,
            borderRadius: BorderRadius.only(
              bottomRight: Radius.circular(widget.isExpanded ? 0 : 16),
            ),
            child: Padding(
              padding: ResponsiveHelper.symmetricPadding(context,
                  horizontal: 14, vertical: 9),
              child: Icon(
                widget.isExpanded
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                size: ResponsiveHelper.iconSize(context, 20),
                color: AppColors.grey400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// `지원 현황`이 열 대상. 하나로 확정할 수 없으면 null.
  _ApplicantTarget? _applicantTarget() {
    final calSlot = widget.calendarSlot;
    if (calSlot != null) {
      return calSlot.slot?.date == null ? null : _ApplicantTarget.slot(calSlot);
    }

    if (!widget.groupItem.masterTO.isLongTerm) {
      // FLEX — 카드에 보이는 그 날짜의 명단으로 간다.
      final slot = widget.groupItem.operationalSlot;
      return slot == null ? null : _ApplicantTarget.slot(slot);
    }

    // CONTRACT — 날짜 명단이라는 개념이 없다. 업무가 하나뿐일 때만 확정된다.
    final details = _collapsedWorkDetails(widget.groupItem.masterTO);
    if (details.length != 1) return null;
    return _ApplicantTarget.work(_getSingleTOItem(), details.first);
  }

  Future<void> _openApplicants(
      BuildContext context, _ApplicantTarget target) async {
    final slot = target.slot;
    if (slot != null) {
      // 기존 canonical 경로 — 날짜 명단(DayApplicantsDialog)
      await _showSlotRoster(context, slot);
      return;
    }
    final item = target.toItem!;
    final work = target.work!;
    final result = await showDialog<WorkApplicantsDialogResult>(
      context: context,
      builder: (_) => WorkApplicantsDialog(
        toItem: item,
        work: work,
        onChanged: widget.onChanged,
        // [POSTING-V2-02G.1] 권한은 이 공고가 속한 사업장 기준 — WorkDetailRow와 동일.
        targetPermissions: context
            .read<UserProvider>()
            .permissionsForBusiness(item.to.businessId),
      ),
    );
    if (result != null && result.hasChanges && mounted) {
      setState(() {});
      widget.onChanged();
      WorkforceController.notifyDataChanged(origin: AdminMutationOrigin.jobs);
      if (result.affectedTOIds.isNotEmpty) {
        widget.onAffectedTOsChanged?.call(result.affectedTOIds);
      }
    }
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

    // [4I.1] closed 상태일 때 종료 원인에 따라 contextual 레이블 전달
    //   FULL       → '모집 완료' (인원 충족, 관리자 종료 아님)
    //   isManualClosed → '종료'  (관리자 직접 종료)
    //   TIME_EXPIRED   → '지원 마감' (applicationDeadline/근무시간 경과)
    //   POSTING_EXPIRED→ '공고 만료' (게시기간 경과)
    //   기타(legacy)   → null → '마감' fallback
    // [POSTING-V2-03S.1] FULL은 라벨뿐 아니라 색·아이콘도 달라야 하므로
    //   recruitmentComplete로 함께 넘긴다.
    final isRecruitmentComplete =
        status == SlotDisplayStatus.closed && widget.groupItem.isFull;
    String? closedLabel;
    if (status == SlotDisplayStatus.closed) {
      final to = widget.groupItem.masterTO;
      if (widget.groupItem.isFull) {
        closedLabel = SlotStatusBadge.recruitmentCompleteLabel;
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
      recruitmentComplete: isRecruitmentComplete,
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
    // [POSTING-V2-02G.1] 대상 사업장 기준 — 서버 guard와 같은 단위.
    final canDelete = user?.isBusinessAdmin == true || user?.isSuperAdmin == true ||
        up.canForBusiness(widget.groupItem.businessId, (p) => p.canManageTo);
    // [POSTING-V2-01C.2] 삭제는 미공개(DRAFT) 공고 정리 수단으로만 남긴다.
    // 공개된 공고는 수정 / 종료 / 재오픈 / 다시 모집 lifecycle로 운영하고 기록을 남긴다.
    // 서버(callableDeleteTO/Slots)는 relation-zero면 어떤 status든 허용하지만,
    // 클라이언트는 의도적으로 더 좁게 노출한다 — ACTIVE에 지원자가 없다고 해서
    // 삭제를 권할 이유가 없고, 잘못 낸 공고의 정상 해결책은 수정 또는 종료다.
    // 최종 가능 여부는 서버가 판정한다 (DRAFT에도 초대가 붙어 있을 수 있다).
    final isDraft = widget.groupItem.masterTO.status == TOStatus.draft;
    // TO-02: 쓰기 작업 항목은 canManageTo 권한 있을 때만 표시
    final canManageTo =
        up.canForBusiness(widget.groupItem.businessId, (p) => p.canManageTo);
    // [REPOST-GAPFIX] WHITELIST / FAIL-CLOSED:
    // 알려진 정상 모집 종료 상태만 명시 허용. 알 수 없는 미래 closedReason은 기본 비표시.
    final repostReasonCode = widget.groupItem.closedReasonCode;
    final canRepost = canManageTo &&
        isClosed &&
        (isManualClosed ||
            isFull ||
            repostReasonCode == 'POSTING_EXPIRED' ||
            repostReasonCode == 'TIME_EXPIRED' ||
            repostReasonCode == 'ALL_SLOTS_EXPIRED' ||
            repostReasonCode == 'ALL_WORKDETAILS_CLOSED' ||
            repostReasonCode == 'ALL_CHILDREN_CLOSED');
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
            // CONTRACT TIME_EXPIRED / POSTING_EXPIRED: 재오픈 HIDE (다시 모집하기 사용)
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
        // [REPOST-GAPFIX] 다시 모집하기 — WHITELIST/FAIL-CLOSED (canRepost 조건 참조)
        if (canRepost)
          [
            AppMenuSheetItem(
              icon: Icons.replay,
              label: '다시 모집하기',
              color: AppColors.info,
              onTap: () => _handleSingleTOMenuAction(context, 'repost'),
            ),
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
        // [POSTING-V2-01C.2] 삭제 — 미공개(DRAFT) 공고에서만 노출
        // 공개 이후(SCHEDULED/ACTIVE/FULL/CLOSED/EXPIRED)에는 메뉴 자체가 없다.
        if (canDelete && isDraft)
          [
            AppMenuSheetItem(
              icon: Icons.delete,
              label: isContract ? '미공개 공고 삭제' : '날짜 일괄삭제',
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
    // [POSTING-V2-02G.1] 대상 사업장 기준 — 서버 guard와 같은 단위.
    final canDelete = user?.isBusinessAdmin == true || user?.isSuperAdmin == true ||
        up.canForBusiness(widget.groupItem.businessId, (p) => p.canManageTo);
    // TO-02: 쓰기 작업 항목은 canManageTo 권한 있을 때만 표시
    final canManageTo =
        up.canForBusiness(widget.groupItem.businessId, (p) => p.canManageTo);

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
  /// [POSTING-V2-02B.2] 초대 성공 시 이 카드만 갱신한다.
  ///
  /// 초대는 slot.pendingCount / workDetailCounts.pendingCount / TO.totalPending을
  /// 올리므로 카드의 '대기' 수치가 바뀐다. InviteWorkerDialog는 이미 성공 시
  /// `Navigator.pop(context, true)`를 반환하는데 그동안 호출부가 무시하고 있었다.
  ///
  /// Home에는 알리지 않는다 — Home 인력 현황은 confirmed 기준이고
  /// 지원 검토 건수는 PENDING 기준이라 초대(INVITED)로 바뀌지 않는다.
  Future<void> _showInviteWorkerDialog(BuildContext context) async {
    final masterTO = widget.groupItem.masterTO;
    final invited = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => InviteWorkerDialog(
        groupItem: widget.groupItem,
        businessId: masterTO.businessId,
        businessName: widget.groupItem.businessName,
      ),
    );
    if (invited == true && mounted) widget.onChanged();
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
                // [POSTING-V2-01B] 통계 실패를 0으로 확정하지 않는다
                statsFailed: result['statsFailed'] == true,
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
        final editSelection = await SlotBatchSelectDialog.show(
          context: context,
          to: masterTO,
          firestoreService: widget.firestoreService,
          title: '일괄수정 날짜 선택',
          confirmLabel: '수정',
          openOnly: true, // [4H.0C-CLOSED-02] 마감된 슬롯 선택 방지
        );
        if (editSelection == null || editSelection.isEmpty || !mounted) return;
        final editSlots = editSelection.slots;
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
        final closeSelection = await SlotBatchSelectDialog.show(
          context: context,
          to: masterTO,
          firestoreService: widget.firestoreService,
          title: '종료할 날짜 선택',
          confirmLabel: '종료',
          openOnly: true,
        );
        if (closeSelection == null || closeSelection.isEmpty || !mounted) return;
        final closeSlots = closeSelection.slots;
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
            // [POSTING-V2-02B.2] 날짜 종료는 Home 인력 현황의 대상 날짜를 줄인다
            WorkforceController.notifyDataChanged(
              origin: AdminMutationOrigin.jobs,
            );
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
        final reopenSelection = await SlotBatchSelectDialog.show(
          context: context,
          to: masterTO,
          firestoreService: widget.firestoreService,
          // [4I.1] "종료한 날짜 재오픈" copy
          title: '다시 열 날짜 선택',
          confirmLabel: '다시 열기',
          closedAndReopenable: true,
        );
        if (reopenSelection == null || reopenSelection.isEmpty || !mounted) {
          return;
        }
        final reopenSlots = reopenSelection.slots;
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
            // [POSTING-V2-02B.2] 날짜 재오픈은 Home 인력 현황의 대상 날짜를 늘린다
            WorkforceController.notifyDataChanged(
              origin: AdminMutationOrigin.jobs,
            );
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
        // [POSTING-V2-03M.1] 해석하지 못한 슬롯도 복구 항목으로 함께 고른다.
        //   서버는 slotId만 알면 지울 수 있는데, 이전에는 목록에서 조용히
        //   빠져 있어 그 날짜를 가진 미공개 공고를 정리할 방법이 없었다.
        final deleteSelection = await SlotBatchSelectDialog.show(
          context: context,
          to: masterTO,
          firestoreService: widget.firestoreService,
          title: '일괄삭제 날짜 선택',
          confirmLabel: '삭제',
          includeMalformed: true,
        );
        if (deleteSelection == null || deleteSelection.isEmpty || !mounted) {
          return;
        }
        final deleteSlotIds = deleteSelection.slotIds;
        final hasMalformedSelected = deleteSelection.malformedSlotIds.isNotEmpty;

        // [POSTING-V2-03L.1] 여기서 "전부 삭제인가"를 계산하지 않는다.
        //   이전에는 전체 날짜 수를 읽어 선택 수와 비교한 뒤, 그 boolean으로
        //   공고 삭제까지 따로 호출했다. 확인 다이얼로그를 사이에 두고 그 값이
        //   낡을 수 있었고 — 그 사이 다른 관리자가 날짜를 추가하면 남아 있는
        //   날짜째로 공고가 지워졌다 — 서버는 남은 날짜를 확인하지 않았다.
        //   이제 클라이언트가 보내는 의도는 "이 날짜들을 지워라" 하나뿐이고,
        //   마지막 날짜였는지는 서버가 canonical slot 문서로 판정한다.
        //   [BACKLOG-BATCH-DELETE-DELETESALL-DERIVED-FROM-COUNT] 해소.
        final deleteConfirmed = await showDialog<bool>(
          context: this.context,
          barrierDismissible: false,
          builder: (dialogCtx) => StyledDialog(
            title: '날짜 삭제',
            // [POSTING-V2-03M.1] 날짜를 읽을 수 없는 항목이 섞이면 '날짜'라고
            //   부를 수 없다 — '항목'으로 말한다.
            subtitle: hasMalformedSelected
                ? '선택한 ${deleteSlotIds.length}개 항목을 삭제하시겠습니까?'
                : '선택한 ${deleteSlotIds.length}개 날짜를 삭제하시겠습니까?',
            icon: Icons.delete_forever,
            headerColor: AppColors.error,
            // [POSTING-V2-01C.2] 서버 계약(relation-zero only)과 같은 말을 한다.
            // 옛 문구는 '자동 취소'를 전제했지만 이제 관계가 있으면 삭제 자체가 거부된다.
            // [POSTING-V2-03L.1] 결과를 단정하지 않는 조건부 문구다 — 저장 직전
            //   다른 관리자가 날짜를 더해도 거짓말이 되지 않는다.
            content: StyledDialogInfoCard.warning(
              '삭제한 날짜는 복구할 수 없습니다.\n'
              '지원·초대·근무 기록이 있는 날짜는 삭제할 수 없습니다.\n\n'
              '${hasMalformedSelected ? '날짜 정보를 확인할 수 없는 항목이 포함되어 있습니다.\n' : ''}'
              '삭제 후 남은 날짜가 없으면 미공개 공고도 함께 삭제됩니다.',
            ),
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
          final result = await widget.firestoreService.batchDeleteSlots(
            toId: masterTO.id,
            businessId: masterTO.businessId,
            slotIds: deleteSlotIds,
          );
          if (!mounted) return;
          widget.firestoreService.clearCache(toId: masterTO.id);
          widget.onChanged();
          // [POSTING-V2-02B.2] Workforce 신호는 보내지 않는다. 이 경로는
          //   DRAFT(미공개) 공고 전용이라 확정 근무자가 없고, Home 인력 현황의
          //   truth가 바뀌지 않는다. 종료·재오픈이 신호를 보내는 것은 그쪽이
          //   공개 공고를 다루기 때문이다 — 같은 이유로 여기서는 보내지 않는다.
          // 결과는 서버가 말해 준다 — 추론하지 않는다.
          //
          // [POSTING-V2-03L.1] 여기까지 왔다는 것은 mutation이 통째로
          //   성공했다는 뜻이다. 마지막 날짜를 지우는 요청에서 공고 관계가
          //   막으면 서버가 날짜 삭제까지 되돌리고 예외를 던지므로,
          //   "날짜는 지워졌는데 공고는 남았다"는 중간 상태가 없다.
          if (result['postingDeleted'] == true) {
            ToastHelper.showSuccess('공고가 삭제되었습니다');
          } else {
            final deleted =
                (result['deletedSlotCount'] as num?)?.toInt() ??
                    deleteSlotIds.length;
            // [POSTING-V2-03M.1] 복구 항목이 섞였으면 '날짜'로 부르지 않는다.
            ToastHelper.showSuccess(hasMalformedSelected
                ? '$deleted개 항목이 삭제되었습니다'
                : '$deleted개 날짜가 삭제되었습니다');
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

      case 'repost':
        // [REPOST-R1] CLOSED TO에서 다시 모집하기 — initialTO prefill, sourceToId 없음 (독립 신규 공고)
        await NavigationHelper.push<bool>(
          context,
          useRootNavigator: true,
          destination: AdminCreateTOScreen(
            initialBusinessId: masterTO.businessId,
            initialTO: masterTO,
          ),
          // [POSTING-V2-02B.2] CreateTO는 성공 시 popWithChange(true)를 반환하는데
          //   그동안 호출부가 결과를 받지 않아 새 공고가 목록에 나타나지 않았다.
          //   onChanged는 result == true일 때만 호출된다.
          onChanged: () {
            if (!mounted) return;
            widget.onChanged();
            // 새 공고는 Home 인력 현황·첫 공고 준비에도 영향을 준다
            WorkforceController.notifyDataChanged(
              origin: AdminMutationOrigin.jobs,
            );
          },
        );
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
          }, expectedEditRevision: masterTO.editRevision);
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
              // [POSTING-V2-01B] 통계 실패를 0으로 확정하지 않는다
              statsFailed: result['statsFailed'] == true,
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
  /// 고정 공고: 공고 마감일 한 줄
  ///
  /// [POSTING-V2-03R.1] 계약기간(`계약 3개월`)은 업무 줄로 옮겼다 — 타입별
  ///   domain detail도 공통 축과 같은 위치에서 읽히는 편이 낫다.
  ///   Row의 Text에 flex 보호가 없어 좁은 폭에서 overflow할 수 있었다.
  Widget _buildLongTermMeta(BuildContext context, TOModel masterTO, bool allClosed) {
    final expiry = !allClosed ? masterTO.formattedPostingExpiry : null;
    if (expiry == null) return const SizedBox.shrink();
    final isPast = masterTO.isPostingExpired;
    final color = isPast ? AppColors.grey500 : AppColors.warningDark;
    return Padding(
      padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 4)),
      child: Row(
        children: [
          Icon(Icons.calendar_month_outlined,
              size: ResponsiveHelper.iconSize(context, 13), color: color),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Flexible(
            child: Text('지원 마감 $expiry',
                style: ResponsiveHelper.smallStyle(context, color: color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
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
    // [POSTING-V2-03R.1] 마감 문구 + '마감임박' 배지가 좁은 폭에서 겹치지
    //   않도록 Flexible로 감싼다. 배지는 짧으므로 문구 쪽이 줄어든다.
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
          Flexible(
            child: Text(
              label,
              style: ResponsiveHelper.smallStyle(
                context,
                color: isPast ? AppColors.grey500 : AppColors.warningDark,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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

// [DECOMMISSIONED] _ExtendDaysSheet 제거됨 — 게시기간 연장 기능 종료
// 다시 모집하기 → AdminCreateTOScreen(initialTO) → NEW TO ID

// ════════════════════════════════════════════════════════════════════════
// [POSTING-V2-03R.1] collapsed 요약 — 순수 함수
//
// 규칙 하나다: **하나로 확정되지 않으면 대표값을 고르지 않는다.** 첫
// workDetail을 대표로 쓰면 나머지 업무·시간대가 없는 것처럼 보이고, 관리자는
// 카드만 보고 운영을 판단한다. 잘못된 하나보다 "N개"가, 알 수 없으면 생략이 낫다.
// ════════════════════════════════════════════════════════════════════════

/// 업무 요약. 업무가 없으면 null.
@visibleForTesting
String? collapsedWorkSummary(List<WorkDetailData> details) {
  final types = <String>{};
  for (final detail in details) {
    if (detail.workType.isEmpty) continue;
    types.add(detail.workType);
  }
  if (types.isEmpty) return null;
  if (types.length == 1) return types.first;
  return '업무 ${types.length}개';
}

/// 시간 요약. 시간대를 알 수 없으면 null.
@visibleForTesting
String? collapsedTimeSummary(List<WorkDetailData> details) {
  final ranges = <String>{};
  for (final detail in details) {
    if (detail.startTime.isEmpty || detail.endTime.isEmpty) continue;
    ranges.add('${detail.startTime}–${detail.endTime}');
  }
  if (ranges.isEmpty) return null;
  if (ranges.length == 1) return ranges.first;
  return '시간대 ${ranges.length}개';
}

/// [POSTING-V2-03R.1] `지원 현황` CTA가 열 대상.
///
/// 두 경우뿐이다: 날짜가 정해진 슬롯(FLEX·캘린더) 또는 업무가 하나뿐인
/// 고정 공고. 어느 쪽으로도 확정되지 않으면 target 자체를 만들지 않는다 —
/// 임의의 첫 업무·첫 날짜를 고르면 카드에 보이는 것과 다른 곳이 열린다.
class _ApplicantTarget {
  final TOItem? slot;
  final TOItem? toItem;
  final WorkDetailData? work;

  const _ApplicantTarget.slot(TOItem this.slot)
      : toItem = null,
        work = null;

  const _ApplicantTarget.work(TOItem this.toItem, WorkDetailData this.work)
      : slot = null;
}

/// 인원 현황 배지 — 리스트/캘린더 뷰 공용
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
