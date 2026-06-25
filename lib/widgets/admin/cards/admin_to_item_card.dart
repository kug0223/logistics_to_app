import 'package:flutter/material.dart';

// Models
import '../../../models/ui/admin_to_list_ui_models.dart';
import '../../../models/core/work_detail_data.dart';
// Widgets
import '../../common/app_menu_sheet.dart';

// Helper
import '../../../utils/toast_helper.dart';

// Services
import '../../../services/firestore_service.dart';

// Utils
import '../../../utils/responsive_helper.dart';
import '../../../utils/navigation_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/close_state_utils.dart';
import '../../../utils/slot_status_util.dart';

// Theme
import '../../../theme/app_colors.dart';

// Common Widgets
import '../../common/loading_widget.dart';
import '../../common/slot_status_badge.dart';

// Screens
import '../../../screens/business_admin/to_management/edit_to_screen.dart';
import '../../../screens/common/job_posting_screen.dart';

// Dialogs
import '../../../screens/business_admin/dialogs/confirmed_list_dialog.dart';
import '../../../screens/business_admin/dialogs/work_detail_management_dialog.dart';
import '../../../screens/business_admin/dialogs/to_list_dialogs.dart';

// Local Widgets
import 'admin_work_detail.dart';

/// 슬롯 단위 TO 카드 — 날짜가 이미 선택된 컨텍스트(캘린더 뷰)에 특화.
///
/// ## TOGroupCard와의 역할 분리
/// - TOGroupCard: 날짜 미선택 리스트 뷰에서 공고 그룹 전체를 표시. 날짜 범위/N일 배지/등록시간 등 포함.
/// - TOItemCard(이 클래스): 날짜가 이미 결정된 상황에서 해당 날짜의 특정 슬롯 하나를 표시.
///   날짜 배지를 헤더 첫 번째에 강조. compact 레이아웃으로 하루에 여러 장 나열에 적합.
///
/// ## 캘린더 뷰에서 TOGroupCard 대신 이것을 써야 하는 이유
/// 1. [dateOverride]: 고정 TO는 슬롯 날짜가 없으므로, 사용자가 선택한 날짜를 날짜 배지에 표시.
///    TOGroupCard에는 이 기능이 없어 고정 TO가 캘린더에서 날짜를 올바로 표시하지 못함.
/// 2. 슬롯 단위 정밀 통계: [toItem.resolveStats()]로 해당 슬롯의 인원만 반영.
/// 3. compact 레이아웃: 날짜 범위/N일/등록시간 같은 리스트 전용 정보를 제거해 캘린더에 적합.
///
/// ⚠️ TOGroupCard의 [TOCardDisplayMode.calendar]가 있어도 이 카드를 대체할 수 없음. 위 이유 참고.
class TOItemCard extends StatefulWidget {
  final TOItem toItem;
  final TOGroupItem groupItem;
  final FirestoreService firestoreService;
  final TOListDialogs dialogs;
  final VoidCallback onChanged;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final bool isLoading;
  final VoidCallback? onLocalStatsChanged;
  final void Function(Set<String> affectedTOIds)? onAffectedTOsChanged;
  /// 캘린더 모드: 슬롯 날짜 대신 표시할 날짜 (고정 TO에 선택된 날짜 표시용)
  final DateTime? dateOverride;
  /// false면 좌측 그룹 연결선을 숨김 (캘린더 모드 등 독립 카드 표시 시)
  final bool showConnector;

  const TOItemCard({
    super.key,
    required this.toItem,
    required this.groupItem,
    required this.firestoreService,
    required this.dialogs,
    required this.onChanged,
    required this.isExpanded,
    required this.onToggleExpand,
    this.isLoading = false,
    this.onLocalStatsChanged,
    this.onAffectedTOsChanged,
    this.dateOverride,
    this.showConnector = true,
  });

  @override
  State<TOItemCard> createState() => _TOItemCardState();
}

class _TOItemCardState extends State<TOItemCard> {
  @override
  Widget build(BuildContext context) {
    final to = widget.toItem.to;
    final theme = Theme.of(context);
    
    final (:confirmed, :pending, :required) = widget.toItem.resolveStats();
    final isFull = widget.toItem.resolvedIsFull;
    
    // 전체 마감 여부 — contract TO(slot=null)는 TO 레벨 isClosed 직접 사용
    final allClosed = widget.toItem.slot == null
        ? widget.toItem.to.isClosed
        : CloseStateUtils.isToItemClosed(
            widget.toItem,
            widget.groupItem.masterTO,
            DateTime.now(),
            localConfirmed: confirmed,
            localRequired: required,
          );
    // 상태별 컬러 (장기/단기 구분)
    Color statusColor;
    if (allClosed) {
      statusColor = AppColors.grey400;
    } else if (isFull) {
      statusColor = AppColors.success;
    } else {
      statusColor = widget.toItem.to.isLongTerm ? AppColors.longTerm : AppColors.shortTerm;
    }

    return Container(
      margin: EdgeInsets.only(
        bottom: ResponsiveHelper.spacing(context, 8),
      ),
      child: Stack(
        children: [
          // ✨ 메인 카드
          Container(
            margin: EdgeInsets.only(left: widget.showConnector ? 16 : 0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: widget.isExpanded
                  ? Border.all(color: theme.primaryColor, width: 1.5)
                  : Border.all(color: AppColors.grey200, width: 1),
            ),
            child: Material(
              color: Colors.transparent,
              child: Column(
                children: [
                  // ✨ 헤더 (클릭 가능)
                  InkWell(
                    onTap: widget.onToggleExpand,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                      bottomLeft: Radius.circular(widget.isExpanded ? 0 : 12),
                      bottomRight: Radius.circular(widget.isExpanded ? 0 : 12),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ✨ 1줄: 날짜 + [고정/단기 배지] + 제목
                          Row(
                            children: [
                              // 날짜 배지
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
                                  FormatHelper.formatDate(widget.dateOverride ?? widget.toItem.slot?.date ?? to.date),
                                  style: ResponsiveHelper.smallStyle(
                                    context,
                                    color: theme.primaryColor,
                                  ).copyWith(fontWeight: FontWeight.bold),
                                ),
                              ),
                              // 고정/단기 타입 배지 (캘린더 독립 카드에서만 표시)
                              if (!widget.showConnector) ...[
                                SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: ResponsiveHelper.spacing(context, 6),
                                    vertical: ResponsiveHelper.spacing(context, 3),
                                  ),
                                  decoration: BoxDecoration(
                                    color: widget.groupItem.isLongTerm
                                        ? AppColors.longTermBg
                                        : AppColors.shortTermBg,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: widget.groupItem.isLongTerm
                                          ? AppColors.longTermLight
                                          : AppColors.shortTermLight,
                                    ),
                                  ),
                                  child: Text(
                                    widget.groupItem.isLongTerm ? '고정' : '단기',
                                    style: ResponsiveHelper.tinyStyle(
                                      context,
                                      color: widget.groupItem.isLongTerm
                                          ? AppColors.longTermDark
                                          : AppColors.shortTermDark,
                                    ).copyWith(fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                              // 제목 (슬롯 개별 제목 우선, 없으면 마스터 TO 제목)
                              Expanded(
                                child: Text(
                                  widget.toItem.slot?.title ?? to.title,
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
                          
                          // 사업장명 (캘린더 독립 카드에서만 표시)
                          if (!widget.showConnector && widget.groupItem.businessName.isNotEmpty) ...[
                            SizedBox(height: ResponsiveHelper.spacing(context, 3)),
                            Row(
                              children: [
                                Icon(
                                  Icons.store_outlined,
                                  size: ResponsiveHelper.iconSize(context, 11),
                                  color: AppColors.grey500,
                                ),
                                SizedBox(width: ResponsiveHelper.spacing(context, 3)),
                                Flexible(
                                  child: Text(
                                    widget.groupItem.businessName,
                                    style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey600),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],

                          // 계약기간 + 근무요일 (캘린더 고정 카드에서만 표시)
                          if (!widget.showConnector && widget.groupItem.isLongTerm) ...[
                            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                            // 계약 기간 (프리셋이면 "계약 1개월", custom이면 생략)
                            if (to.contractPeriodLabel.isNotEmpty)
                              Row(
                                children: [
                                  Icon(
                                    Icons.assignment_outlined,
                                    size: ResponsiveHelper.iconSize(context, 12),
                                    color: AppColors.longTermDark,
                                  ),
                                  SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                                  Text(
                                    '계약 ${to.contractPeriodLabel}',
                                    style: ResponsiveHelper.smallStyle(context, color: AppColors.longTermDark)
                                        .copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            // 근무 일정 (시작일 ~ 종료일 · 요일)
                            SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                            Text(
                              FormatHelper.formatWorkPeriod(
                                startDate: to.rangeStart ?? to.createdAt,
                                endDate: to.endDate,
                                isLongTerm: true,
                                workDays: to.workDays.isEmpty ? null : to.workDays,
                              ),
                              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                            ),
                          ],

                          SizedBox(height: ResponsiveHelper.spacing(context, 8)),

                          // ✨ 2줄: 인원 + 마감 + 메뉴 + 펼침
                          Row(
                            children: [
                              // 인원 현황
                              _buildPersonnelInfo(
                                context,
                                confirmed: confirmed,
                                required: required,
                                pending: pending,
                                isFull: isFull,
                              ),
                              
                              Spacer(),
                              
                              // 상태 배지 (마감/예약/모집중)
                              _buildStatusBadge(context, allClosed: allClosed),
                              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                              
                              // 메뉴 버튼
                              _buildPopupMenu(context),
                              
                              // 펼침 아이콘
                              Icon(
                                widget.isExpanded 
                                    ? Icons.keyboard_arrow_up 
                                    : Icons.keyboard_arrow_down,
                                size: ResponsiveHelper.iconSize(context, 20),
                                color: AppColors.grey500,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // ✨ 펼쳐진 경우: 업무 상세 (애니메이션 적용)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    clipBehavior: Clip.hardEdge,
                    alignment: Alignment.topCenter,
                    child: widget.isExpanded
                        ? Column(
                            children: [
                              Divider(height: 1, color: AppColors.grey200),
                              Container(
                                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
                                decoration: BoxDecoration(
                                  color: AppColors.grey50,
                                  borderRadius: BorderRadius.only(
                                    bottomLeft: Radius.circular(12),
                                    bottomRight: Radius.circular(12),
                                  ),
                                ),
                                child: widget.isLoading
                                    // ✨ 로딩 중 스피너
                                    ? Padding(
                                        padding: EdgeInsets.all(
                                          ResponsiveHelper.spacing(context, 16),
                                        ),
                                        child: const LoadingWidget(message: '업무 정보 불러오는 중...'),
                                      )
                                    // ✨ 로드 완료 - 업무 상세 표시
                                    : Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // 업무 상세 헤더
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.assignment,
                                                size: ResponsiveHelper.iconSize(context, 14),
                                                color: theme.primaryColor,
                                              ),
                                              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                                              Text(
                                                '업무 상세',
                                                style: ResponsiveHelper.bodyStyle(context).copyWith(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                          SizedBox(height: ResponsiveHelper.spacing(context, 10)),
                                          
                                          // 업무 목록
                                          ...widget.toItem.workDetails.map((work) {
                                            final stats = widget.toItem.workDetailStats?[work.id];
                                            final workConfirmed = stats?['confirmed'] ?? 0;
                                            final workPending = stats?['pending'] ?? 0;

                                            return WorkDetailRow(
                                              work: work,
                                              confirmedCount: workConfirmed,
                                              pendingCount: workPending,
                                              toItem: widget.toItem,
                                              firestoreService: widget.firestoreService,
                                              onChanged: widget.onChanged,
                                              onLocalStatsChanged: () {
                                                setState(() {});
                                                widget.onLocalStatsChanged?.call();
                                              },
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
          
          // ✨ 좌측 연결선 (그룹 카드 내부에서만 표시)
          if (widget.showConnector) Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Column(
              children: [
                // 상단 여백
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                // 연결 점
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                // 연결선 (남은 공간 전체)
                Expanded(
                  child: Container(
                    width: 2,
                    color: widget.isExpanded ? statusColor : AppColors.grey300,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ✨ 간소화된 위젯들
  // ═══════════════════════════════════════════════════════════════

  /// ✨ 인원 현황 (텍스트 + 상태별 색상)
  Widget _buildPersonnelInfo(
    BuildContext context, {
    required int confirmed,
    required int required,
    required int pending,
    required bool isFull,
  }) {
    // 상태별 색상: 충족=초록, 진행중=파랑
    final statusColor = isFull ? AppColors.successDark : AppColors.infoDark;
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isFull ? Icons.check_circle : Icons.people_outline,
          size: ResponsiveHelper.iconSize(context, 14),
          color: statusColor,
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
        Text(
          '$confirmed/$required',
          style: ResponsiveHelper.bodyStyle(
            context,
            color: statusColor,
          ).copyWith(fontWeight: FontWeight.bold),
        ),
        if (pending > 0) ...[
          Text(
            ' +$pending',
            style: ResponsiveHelper.smallStyle(
              context,
              color: AppColors.warningDark,
            ),
          ),
        ],
      ],
    );
  }
  /// 슬롯 단위 상태 배지
  ///
  /// - allClosed=true → closed (CloseStateUtils 판단 결과를 호출자가 전달)
  /// - slot != null (flex TO) → SlotStatusUtil.slotStatus 위임
  /// - slot == null (contract TO, allClosed=false):
  ///     allClosed 계산이 이미 to.isClosed를 사용했으므로 여기서 to.isClosed=true 진입은
  ///     이론상 불가 — defensive 체크로만 유지
  Widget _buildStatusBadge(BuildContext context, {required bool allClosed}) {
    final slot = widget.toItem.slot;
    final to = widget.toItem.to;
    final status = allClosed
        ? SlotDisplayStatus.closed
        : slot != null
            ? SlotStatusUtil.slotStatus(slot, to)
            : (to.isClosed
              ? SlotDisplayStatus.closed
              : to.isPendingPublish
                  ? SlotDisplayStatus.scheduled
                  : SlotDisplayStatus.recruiting);
    final scheduledAt = slot != null
        ? SlotStatusUtil.slotScheduledAt(slot, to)
        : to.publishAt;
    return SlotStatusBadge(status: status, scheduledAt: scheduledAt, compact: true);
  }

  /// 팝업 메뉴
  Widget _buildPopupMenu(BuildContext context) {
    return IconButton(
      icon: Icon(
        Icons.more_vert,
        size: ResponsiveHelper.iconSize(context, 18),
        color: AppColors.grey600,
      ),
      padding: EdgeInsets.zero,
      tooltip: '메뉴',
      onPressed: () => _showMenuSheet(context),
    );
  }

  void _showMenuSheet(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    AppMenuSheet.show(
      context: context,
      itemGroups: [
        [
          AppMenuSheetItem(
            icon: Icons.visibility,
            label: '공고 상세보기',
            color: AppColors.info,
            onTap: () => _handleMenuAction(context, 'preview'),
          ),
        ],
        [
          AppMenuSheetItem(
            icon: Icons.edit,
            label: '수정',
            color: AppColors.warning,
            onTap: () => _handleMenuAction(context, 'edit'),
          ),
          AppMenuSheetItem(
            icon: Icons.delete,
            label: '삭제',
            color: AppColors.error,
            isDanger: true,
            onTap: () => _handleMenuAction(context, 'delete'),
          ),
        ],
        [
          AppMenuSheetItem(
            icon: Icons.check_circle_outline,
            label: '확정명단',
            color: AppColors.success,
            onTap: () => _handleMenuAction(context, 'confirmedList'),
          ),
          AppMenuSheetItem(
            icon: Icons.assignment_turned_in,
            label: '업무별 마감',
            color: primaryColor,
            onTap: () => _handleMenuAction(context, 'manageWorkDetails'),
          ),
        ],
      ],
    );
  }

  /// 메뉴 액션 처리
  Future<void> _handleMenuAction(BuildContext context, String value) async {
    switch (value) {
      case 'preview':
        if (!widget.toItem.isWorkDetailLoaded || widget.toItem.workDetails.isEmpty) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => const Center(child: LoadingWidget()),
          );
          try {
            final result = await widget.firestoreService.loadTOWorkDetails(widget.toItem.to, slotId: widget.toItem.slot?.id, slotWorkDetails: widget.toItem.slot?.workDetails);
            widget.toItem.setWorkDetails(
              result['workDetails'] as List<WorkDetailData>,
              result['workStats'] as Map<String, Map<String, int>>,
            );
          } catch (e) {
            if (!mounted) return;
            Navigator.pop(this.context);
            ToastHelper.showError('데이터를 불러오는데 실패했습니다.');
            return;
          }
          if (!mounted) return;
          Navigator.pop(this.context);
        }
        if (!mounted) return;
        final resolvedStats = widget.toItem.resolveStats();
        Navigator.push(
          this.context,
          MaterialPageRoute(
            builder: (_) => JobPostingScreen(
              to: widget.toItem.to,
              workDetails: widget.toItem.workDetails,
              mode: TODetailMode.adminPreview,
              slotDate: widget.toItem.slot?.date,
              slotTotalRequired: resolvedStats.required,
              slotConfirmedCount: resolvedStats.confirmed,
              slotPendingCount: resolvedStats.pending,
              workDetailStats: widget.toItem.workDetailStats,
            ),
          ),
        );
        break;

      case 'edit':
        await NavigationHelper.push<bool>(
          context,
          destination: AdminEditTOScreen(
            to: widget.toItem.to,
            slot: widget.toItem.slot,
          ),
          onReturn: (result) {
            if (result == true && mounted) {
              widget.firestoreService.clearCache(toId: widget.toItem.to.id);
              widget.onChanged();
            }
          },
        );
        break;

      case 'delete':
        widget.dialogs.showDeleteTODialog(widget.toItem);
        break;

      case 'confirmedList':
        if (!widget.toItem.isWorkDetailLoaded || widget.toItem.workDetails.isEmpty) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => const Center(child: LoadingWidget()),
          );
          try {
            final result = await widget.firestoreService.loadTOWorkDetails(widget.toItem.to, slotId: widget.toItem.slot?.id, slotWorkDetails: widget.toItem.slot?.workDetails);
            widget.toItem.setWorkDetails(
              result['workDetails'] as List<WorkDetailData>,
              result['workStats'] as Map<String, Map<String, int>>,
            );
          } catch (e) {
            if (!mounted) return;
            Navigator.pop(this.context);
            ToastHelper.showError('데이터를 불러오는데 실패했습니다.');
            return;
          }
          if (!mounted) return;
          Navigator.pop(this.context);
        }
        if (!mounted) return;
        ConfirmedListDialog(
          context: this.context,
          toItem: widget.toItem,
          firestoreService: widget.firestoreService,
          slotId: widget.toItem.slot?.id,
          onLocalStatsChanged: () {
            if (mounted) setState(() {});
            widget.onLocalStatsChanged?.call();
          },
        ).show();
        break;

      case 'manageWorkDetails':
        if (!widget.toItem.isWorkDetailLoaded || widget.toItem.workDetails.isEmpty) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => const Center(child: LoadingWidget()),
          );
          try {
            final result = await widget.firestoreService.loadTOWorkDetails(widget.toItem.to, slotId: widget.toItem.slot?.id, slotWorkDetails: widget.toItem.slot?.workDetails);
            widget.toItem.setWorkDetails(
              result['workDetails'] as List<WorkDetailData>,
              result['workStats'] as Map<String, Map<String, int>>,
            );
          } catch (e) {
            if (!mounted) return;
            Navigator.pop(this.context);
            ToastHelper.showError('데이터를 불러오는데 실패했습니다.');
            return;
          }
          if (!mounted) return;
          Navigator.pop(this.context);
        }
        if (!mounted) return;
        WorkDetailManagementDialog(
          context: this.context,
          toItem: widget.toItem,
          firestoreService: widget.firestoreService,
          onComplete: widget.onChanged,
          onLocalStatsChanged: () {
            if (mounted) setState(() {});
            widget.onLocalStatsChanged?.call();
          },
        ).show();
        break;
    }
  }
}