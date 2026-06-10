import 'package:flutter/material.dart';

// Models
import '../../../models/core/to_model.dart';
import '../../../utils/close_state_utils.dart';
import '../../../models/ui/admin_to_list_ui_models.dart';
import '../../../models/core/work_detail_data.dart';

// Helper
import '../../../utils/toast_helper.dart';

// Services
import '../../../services/firestore_service.dart';

// Utils
import '../../../utils/responsive_helper.dart';
import '../../../utils/navigation_helper.dart';
import '../../../utils/format_helper.dart';

// Widgets
import '../../../theme/app_colors.dart';
import '../../common/loading_widget.dart';

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
import 'admin_to_item_card.dart';
import 'admin_work_detail.dart';
import '../../../screens/common/job_posting_screen.dart';
import '../../pickers/date_picker_bottom_sheet.dart';
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
  });

  @override
  State<TOGroupCard> createState() => _TOGroupCardState();
}

class _TOGroupCardState extends State<TOGroupCard> {
 @override
  Widget build(BuildContext context) {
    final masterTO = widget.groupItem.masterTO;
    final theme = Theme.of(context);
    
    // flex TO이고 날짜 필터가 있으면 해당 날짜 슬롯만, 아니면 전체
    final targetTOs = (widget.selectedDate != null && !widget.groupItem.isLongTerm)
        ? widget.groupItem.groupTOs.where((toItem) =>
            DateUtils.isSameDay(toItem.slot?.date ?? toItem.to.date, widget.selectedDate!)).toList()
        : widget.groupItem.groupTOs;

    // 전체 통계 계산
    int totalConfirmed = 0;
    int totalPending = 0;
    int totalRequired = 0;

    // groupTOs가 아직 로드 안 됐으면 groupItem에서 통계 사용
    if (targetTOs.isEmpty) {
      totalConfirmed = widget.groupItem.totalConfirmed;
      totalPending = widget.groupItem.totalPending;
      totalRequired = widget.groupItem.totalRequired;
    } else {
      // 헤더 배지는 항상 슬롯 레벨 집계 사용 (펼치기 전후 숫자 일관성 유지)
      for (var toItem in targetTOs) {
        totalConfirmed += toItem.confirmedCount;
        totalPending += toItem.pendingCount;
        totalRequired += toItem.totalRequired;
      }
    }
    
    // 인원 충족 여부 — targetTOs 기준 (날짜 필터 반영)
    final isFull = targetTOs.isEmpty
        ? widget.groupItem.isFull
        : targetTOs.every((toItem) => toItem.resolvedIsFull);

    // ✅ 전체 마감 여부 (WorkDetail 실제 상태 + isTimeExpired 포함)
    final isMultiSlotCollapsed = widget.groupItem.groupTOs.isEmpty &&
        !masterTO.isLongTerm && masterTO.totalSlots > 1;

    // 멀티슬롯 collapsed: HOURS_BEFORE 타입은 rangeEnd(마지막 슬롯 날짜)로
    // 마지막 슬롯의 모든 업무 마감시간이 지났는지 계산.
    // 마지막 슬롯이 만료됐으면 앞 슬롯들도 이미 만료된 것이므로 전체 마감.
    final now = DateTime.now();

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

    final isDimmed = widget.isAnyExpanded && !widget.isExpanded;

    final cardContent = Container(
      margin: EdgeInsets.only(
        bottom: ResponsiveHelper.spacing(context, 12),
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
                color: widget.isExpanded ? theme.primaryColor : AppColors.grey200,
                width: widget.isExpanded ? 1.5 : 1,
              ),
            ),
            child: Material(
          color: Colors.transparent,
          child: Column(
            children: [
              // ✨ 헤더 (클릭 가능)
              InkWell(
                onTap: widget.onToggleExpand,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(widget.isExpanded ? 0 : 16),
                  bottomRight: Radius.circular(widget.isExpanded ? 0 : 16),
                ),
                child: Padding(
                  padding: ResponsiveHelper.cardPadding(context),
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
                          
                          // 등록시간 (리스트 모드만)
                          if (widget.displayMode == TOCardDisplayMode.list) ...[
                            Text(
                              _getCreatedAtText(widget.groupItem.createdAt),
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
                      
                      SizedBox(height: ResponsiveHelper.spacing(context, 6)),

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

                      SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                      
                      // ✨ 셋째 줄: 날짜 + 인원현황 (핵심 정보만!)
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
                          
                          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                          
                          // ✨ 인원 현황 (핵심!)
                          _buildPersonnelBadge(
                            context,
                            confirmed: totalConfirmed,
                            required: totalRequired,
                            pending: totalPending,
                            isFull: isFull,
                          ),
                        ],
                      ),
                      
                      // 고정 공고 계약 기간
                      if (masterTO.isLongTerm && masterTO.contractPeriodLabel.isNotEmpty) ...[
                        Padding(
                          padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 6)),
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
                            padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 8)),
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
                          final now = DateTime.now();
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
                              top: ResponsiveHelper.spacing(context, 8),
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
                      
                      // ✨ 상태 표시 (마감/예약/모집중) - targetTOs 기준
                      SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                      _buildStatusBadge(context, allClosed: allClosed, targetTOs: targetTOs),

                      // 펼침 힌트
                      SizedBox(height: ResponsiveHelper.spacing(context, 4)),
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
              
              // 펼쳐진 경우: flex 다중 슬롯 목록 (리스트 모드 전용)
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                clipBehavior: Clip.hardEdge,
                child: widget.displayMode == TOCardDisplayMode.list &&
                        widget.isExpanded && !widget.groupItem.isLongTerm && widget.groupItem.groupTOs.length > 1
                    ? Column(
                        children: [
                          Divider(height: 1, color: AppColors.grey200),
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.grey50,
                              borderRadius: BorderRadius.only(
                                bottomLeft: Radius.circular(16),
                                bottomRight: Radius.circular(16),
                              ),
                            ),
                            child: Padding(
                              padding: ResponsiveHelper.cardPadding(context),
                              child: widget.isGroupLoading
                                  // ✨ 로딩 중 스피너
                                  ? Padding(
                                      padding: EdgeInsets.all(
                                        ResponsiveHelper.spacing(context, 24),
                                      ),
                                      child: const LoadingWidget(message: '불러오는 중...'),
                                    )
                                  // ✨ 로드 완료 - TO 목록 표시
                                  : Builder(builder: (context) {
                                      final filteredTOs = _getFilteredGroupTOs();
                                      final anyExpanded = filteredTOs.any((ti) =>
                                          widget.expandedTOs.contains(ti.slot?.id ?? ti.to.id));
                                      return Column(
                                        children: filteredTOs.map((toItem) {
                                          final itemKey = toItem.slot?.id ?? toItem.to.id;
                                          final isThisExpanded = widget.expandedTOs.contains(itemKey);
                                          return AnimatedOpacity(
                                            opacity: anyExpanded && !isThisExpanded ? 0.45 : 1.0,
                                            duration: const Duration(milliseconds: 200),
                                            child: TOItemCard(
                                              toItem: toItem,
                                              groupItem: widget.groupItem,
                                              firestoreService: widget.firestoreService,
                                              dialogs: widget.dialogs,
                                              onChanged: widget.onChanged,
                                              isExpanded: isThisExpanded,
                                              onToggleExpand: () => widget.onToggleTOExpand(itemKey),
                                              isLoading: widget.loadingTOs.contains(itemKey),
                                              onLocalStatsChanged: () => setState(() {}),
                                              onAffectedTOsChanged: widget.onAffectedTOsChanged,
                                            ),
                                          );
                                        }).toList(),
                                      );
                                    }),
                            ),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
              
              // 펼쳐진 경우: 단건 슬롯 or 장기 TO 업무 상세 (캘린더 모드 포함)
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                clipBehavior: Clip.hardEdge,
                child: widget.isExpanded && (widget.groupItem.isLongTerm ||
                        widget.groupItem.groupTOs.length <= 1 ||
                        widget.displayMode == TOCardDisplayMode.calendar)
                    ? Column(
                        children: [
                          Divider(height: 1, color: AppColors.grey200),
                          Container(
                            padding: ResponsiveHelper.cardPadding(context),
                            decoration: BoxDecoration(
                              color: AppColors.grey50,
                              borderRadius: BorderRadius.only(
                                bottomLeft: Radius.circular(16),
                                bottomRight: Radius.circular(16),
                              ),
                            ),
                            child: _isSingleTOLoading()
                                // ✨ 로딩 중 스피너
                                ? Padding(
                                    padding: EdgeInsets.all(
                                      ResponsiveHelper.spacing(context, 24),
                                    ),
                                    child: const LoadingWidget(message: '업무 정보 불러오는 중...'),
                                  )
                                // ✨ 로드 완료 - 업무 상세 표시
                                : Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // 단기 단일슬롯: 슬롯 날짜 + 개별 제목 (있는 경우)
                                      if (!widget.groupItem.isLongTerm &&
                                          widget.groupItem.groupTOs.isNotEmpty) ...[
                                        Builder(builder: (context) {
                                          final toItem = widget.groupItem.groupTOs.first;
                                          final slot = toItem.slot;
                                          final slotTitle = slot?.title;
                                          if (slotTitle == null || slotTitle.isEmpty) {
                                            return const SizedBox.shrink();
                                          }
                                          return Padding(
                                            padding: EdgeInsets.only(
                                              bottom: ResponsiveHelper.spacing(context, 12),
                                            ),
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
                                                      FormatHelper.formatDate(slot!.date),
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
                                      ],
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
                                            style: ResponsiveHelper.subtitleStyle(context).copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: ResponsiveHelper.spacing(context, 12)),

                                      // 업무 목록 (단건 TO: singleTO.workDetails 사용)
                                      ..._getSingleTOWorkDetails().map((work) {
                                        final stats = _getSingleTOStats(work.id);
                                        final confirmed = stats?['confirmed'] ?? 0;
                                        final pending = stats?['pending'] ?? 0;

                                        return WorkDetailRow(
                                          work: work,
                                          confirmedCount: confirmed,
                                          pendingCount: pending,
                                          toItem: _getSingleTOItem(),
                                          firestoreService: widget.firestoreService,
                                          onChanged: widget.onChanged,
                                          onLocalStatsChanged: () => setState(() {}),
                                          onAffectedTOsChanged: widget.onAffectedTOsChanged,  // 🔥 추가
                                        );
                                      }),
                                    ],
                                  ),
                          ),
                        ],
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
  // ✨ 새로운 간소화된 위젯들
  // ═══════════════════════════════════════════════════════════════
  /// 등록일 텍스트
  String _getCreatedAtText(DateTime created) {
    final now = DateTime.now();
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

  /// ✨ 상태 배지 (마감/예약/모집중) - targetTOs 기준
  Widget _buildStatusBadge(BuildContext context, {
    required bool allClosed,
    required List<TOItem> targetTOs,
  }) {
    // 1. 마감됨
    if (allClosed) {
      return _buildClosedBadge(context);
    }
    
    // ✅ targetTOs가 비어있으면 groupItem에서 상태 판단
    if (targetTOs.isEmpty) {
      if (widget.groupItem.isPendingPublish) {
        return _buildScheduledBadge(context, widget.groupItem.publishAt);
      }
      return _buildRecruitingBadge(context);
    }
    
    // 2. 모집중 (하나라도 실제 공개된 TO가 있으면)
    final hasPublished = targetTOs.any((toItem) => toItem.to.isPublished);
    if (hasPublished) {
      return _buildRecruitingBadge(context);
    }

    // 3. 예약 (예약 공개 대기 중인 TO가 있으면)
    final pendingTO = targetTOs.where((toItem) => toItem.to.isPendingPublish).firstOrNull;
    if (pendingTO != null) {
      return _buildScheduledBadge(context, pendingTO.to.publishAt);
    }

    // 4. 미공개 (모두 미공개 저장 상태)
    return _buildDraftBadge(context);
  }

  /// ✨ 예약 배지 (오픈 예정)
  Widget _buildScheduledBadge(BuildContext context, DateTime? publishAt) {
    final displayText = publishAt != null
        ? '${FormatHelper.formatDateTime(publishAt)} 오픈'
        : '예약';
    
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      decoration: BoxDecoration(
        color: AppColors.scheduledBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.schedule,
            size: ResponsiveHelper.iconSize(context, 12),
            color: AppColors.scheduledDark,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Text(
            displayText,
            style: ResponsiveHelper.smallStyle(
              context,
              color: AppColors.scheduledDark,
            ),
          ),
        ],
      ),
    );
  }

  /// ✨ 모집중 배지
  Widget _buildRecruitingBadge(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      decoration: BoxDecoration(
        color: AppColors.successBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.campaign,
            size: ResponsiveHelper.iconSize(context, 12),
            color: AppColors.successDark,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Text(
            '모집중',
            style: ResponsiveHelper.smallStyle(
              context,
              color: AppColors.successDark,
            ),
          ),
        ],
      ),
    );
  }

  /// ✨ 미공개 배지
  Widget _buildDraftBadge(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      decoration: BoxDecoration(
        color: AppColors.grey100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.visibility_off_outlined,
            size: ResponsiveHelper.iconSize(context, 12),
            color: AppColors.grey500,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Text(
            '미공개',
            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
          ),
        ],
      ),
    );
  }

  /// ✨ 마감 배지 (간소화)
  Widget _buildClosedBadge(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      decoration: BoxDecoration(
        color: AppColors.grey100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock,
            size: ResponsiveHelper.iconSize(context, 12),
            color: AppColors.grey600,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Text(
            '마감',
            style: ResponsiveHelper.smallStyle(
              context,
              color: AppColors.grey600,
            ),
          ),
        ],
      ),
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
        // 날짜 추가 (flex 전용)
        if (!isContract)
          [
            AppMenuSheetItem(
              icon: Icons.event_available,
              label: '날짜 추가',
              color: AppColors.info,
              onTap: () => _handleSingleTOMenuAction(context, 'addSlot'),
            ),
          ],
        // 수정
        [
          AppMenuSheetItem(
            icon: isContract ? Icons.edit : Icons.edit_calendar,
            label: isContract ? '수정' : '일괄수정',
            color: AppColors.warning,
            onTap: () => _handleSingleTOMenuAction(context, isContract ? 'edit' : 'batchEdit'),
          ),
        ],
        // 마감 / 재오픈
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
            if (!isContract)
              AppMenuSheetItem(
                icon: Icons.lock_open,
                label: '일괄재오픈',
                color: AppColors.success,
                onTap: () => _handleSingleTOMenuAction(context, 'batchReopen'),
              ),
          ],
        ],
        // 확정명단 / 카드 제목 변경
        [
          AppMenuSheetItem(
            icon: Icons.check_circle_outline,
            label: '전체 확정명단',
            color: AppColors.success,
            onTap: () => _handleSingleTOMenuAction(context, 'confirmedList'),
          ),
          AppMenuSheetItem(
            icon: Icons.drive_file_rename_outline,
            label: '카드 제목 변경',
            color: AppColors.purple,
            onTap: () => _handleSingleTOMenuAction(context, 'renameCard'),
          ),
        ],
        // 삭제
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
          [
            AppMenuSheetItem(
              icon: Icons.edit,
              label: '수정',
              color: AppColors.warning,
              onTap: () => _handleSingleTOMenuAction(context, 'edit'),
            ),
          ],
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
          [
            AppMenuSheetItem(
              icon: Icons.edit,
              label: '수정',
              color: AppColors.warning,
              onTap: () => _handleSingleTOMenuAction(context, 'edit'),
            ),
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
              if (mounted) Navigator.pop(this.context);
              ToastHelper.showError('데이터를 불러오는데 실패했습니다.');
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

      case 'addSlot':
        final existingSlots = await widget.firestoreService.getSlots(masterTO.id);
        if (!mounted) return;
        final takenDates = existingSlots
            .map((s) => DateTime(s.date.year, s.date.month, s.date.day))
            .toSet();
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        // initialDate는 takenDates에 없는 첫 번째 날짜로 설정
        DateTime initialDate = today;
        final lastDate = today.add(const Duration(days: 365));
        while (takenDates.contains(initialDate) && initialDate.isBefore(lastDate)) {
          initialDate = initialDate.add(const Duration(days: 1));
        }
        if (takenDates.contains(initialDate)) {
          ToastHelper.showError('추가 가능한 날짜가 없습니다');
          return;
        }
        final picked = await DatePickerBottomSheet.show(
          context: this.context,
          initialDate: initialDate,
          title: '근무 날짜 선택',
          minDate: today,
          maxDate: today.add(const Duration(days: 365)),
          disabledDates: takenDates.toList(),
        );
        if (picked == null || !mounted) return;
        await NavigationHelper.push<bool>(
          this.context,
          destination: AdminEditTOScreen(to: masterTO, newSlotDate: picked),
          onReturn: (result) {
            if (result == true) {
              widget.firestoreService.clearCache(toId: masterTO.id);
              widget.onChanged();
            }
          },
        );
        break;

      case 'edit':
        if (widget.calendarSlot != null) {
          // 캘린더 단기 슬롯: 슬롯 단위 수정
          await NavigationHelper.push<bool>(
            context,
            destination: AdminEditTOScreen(to: masterTO, slot: widget.calendarSlot!.slot),
            onReturn: (result) {
              if (result == true) {
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
              if (result == true) {
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
            if (result == true) {
              widget.firestoreService.clearCache(toId: masterTO.id);
              widget.onChanged();
            }
          },
        );
        break;

      case 'batchClose':
        // uid는 await 이전에 캡처 (async gap 후 context 접근 방지)
        final closeUid = context.read<UserProvider>().currentUser?.uid ?? '';
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
            slotIds: closeSlots.map((s) => s.id).toList(),
            closedBy: closeUid,
          );
          widget.firestoreService.clearCache(toId: masterTO.id);
          widget.onChanged();
          ToastHelper.showSuccess('${closeSlots.length}개 날짜가 마감되었습니다');
        } catch (e) {
          ToastHelper.showError('마감 처리에 실패했습니다');
        }
        break;

      case 'batchReopen':
        final reopenUid = context.read<UserProvider>().currentUser?.uid ?? '';
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
            reopenedBy: reopenUid,
          );
          widget.firestoreService.clearCache(toId: masterTO.id);
          widget.onChanged();
          ToastHelper.showSuccess('${reopenSlots.length}개 날짜가 재오픈되었습니다');
        } catch (e) {
          ToastHelper.showError('재오픈 처리에 실패했습니다');
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
            slotIds: deleteSlots.map((s) => s.id).toList(),
            removedRequired: deleteSlots.fold<int>(0, (s, slot) => s + slot.totalRequired),
            removedConfirmed: deleteSlots.fold<int>(0, (s, slot) => s + slot.confirmedCount),
            removedPending: deleteSlots.fold<int>(0, (s, slot) => s + slot.pendingCount),
          );
          if (!mounted) return;
          if (deletesAll) {
            // 슬롯을 모두 삭제했으니 TO 문서도 삭제 (지원서·알림 포함)
            await widget.firestoreService.deleteTO(masterTO.id);
          } else {
            widget.firestoreService.clearCache(toId: masterTO.id);
            ToastHelper.showSuccess('${deleteSlots.length}개 날짜가 삭제되었습니다');
          }
          widget.onChanged();
        } catch (e) {
          ToastHelper.showError('삭제 처리에 실패했습니다');
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
          // Contract TO: masterTO로 합성 TOItem 사용
          toItemForConfirmed = TOItem(
            to: widget.groupItem.masterTO,
            confirmedCount: widget.groupItem.totalConfirmed,
            pendingCount: widget.groupItem.totalPending,
            totalRequired: widget.groupItem.totalRequired,
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
            final calSlotForLoad = widget.calendarSlot;
            final result = calSlotForLoad != null
                ? await widget.firestoreService.loadTOWorkDetails(
                    toItemForConfirmed.to,
                    slotId: calSlotForLoad.slot?.id,
                    slotWorkDetails: calSlotForLoad.slot?.workDetails,
                  )
                : await widget.firestoreService.loadTOWorkDetails(toItemForConfirmed.to);
            toItemForConfirmed.setWorkDetails(
              result['workDetails'] as List<WorkDetailData>,
              result['workStats'] as Map<String, Map<String, int>>,
            );
          } catch (e) {
            if (mounted) Navigator.pop(this.context);
            ToastHelper.showError('데이터를 불러오는데 실패했습니다.');
            return;
          }
          if (mounted) Navigator.pop(this.context);
        }

        if (!mounted) return;
        ConfirmedListDialog(
          context: this.context,
          toItem: toItemForConfirmed,
          firestoreService: widget.firestoreService,
          slotId: widget.calendarSlot?.slot?.id,
          onLocalStatsChanged: () {
            if (mounted) setState(() {});
          },
        ).show();

      case 'renameCard':
        final currentTitle = masterTO.groupTitle ?? masterTO.title;
        final controller = TextEditingController(text: currentTitle);
        final newTitle = await showDialog<String>(
          context: this.context,
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
              onFieldSubmitted: (_) => Navigator.pop(ctx, controller.text.trim()),
            ),
            actions: [
              StyledDialogButton.cancel(
                onPressed: () => Navigator.pop(ctx),
              ),
              StyledDialogButton.primary(
                text: '저장',
                backgroundColor: AppColors.purple,
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              ),
            ],
          ),
        );
        controller.dispose();
        if (newTitle == null || !mounted) return;
        try {
          await widget.firestoreService.updateTO(masterTO.id, {
            'groupTitle': newTitle.isNotEmpty ? newTitle : null,
          });
          widget.onChanged();
          ToastHelper.showSuccess('카드 제목이 변경되었습니다');
        } catch (e) {
          ToastHelper.showError('제목 변경에 실패했습니다');
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
            if (mounted) Navigator.pop(this.context);
            ToastHelper.showError('데이터를 불러오는데 실패했습니다.');
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

    return await showModalBottomSheet<TOItem>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
                child: Text(
                  '날짜를 선택하세요',
                  style: ResponsiveHelper.subtitleStyle(context).copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: slots.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final toItem = slots[i];
                    final confirmed = toItem.confirmedCount;
                    final required = toItem.totalRequired;
                    final pending = toItem.pendingCount;
                    return ListTile(
                      leading: Icon(
                        Icons.event,
                        color: Theme.of(context).primaryColor,
                        size: ResponsiveHelper.iconSize(context, 20),
                      ),
                      title: Text(
                        FormatHelper.formatDate(toItem.slot?.date ?? toItem.to.date),
                        style: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.w600),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$confirmed/$required',
                            style: ResponsiveHelper.bodyStyle(context, color: AppColors.infoDark)
                                .copyWith(fontWeight: FontWeight.bold),
                          ),
                          if (pending > 0)
                            Text(
                              ' +$pending',
                              style: ResponsiveHelper.smallStyle(context, color: AppColors.warningDark),
                            ),
                          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                          Icon(Icons.chevron_right, size: ResponsiveHelper.iconSize(context, 18), color: AppColors.grey400),
                        ],
                      ),
                      onTap: () => Navigator.pop(ctx, toItem),
                    );
                  },
                ),
              ),
            ],
          ),
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
            required == 0 ? '미설정' : '$confirmed/$required',
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