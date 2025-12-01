import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// Models
import '../../../models/ui/admin_to_list_ui_models.dart';

// Services
import '../../../services/firestore_service.dart';

// Utils
import '../../../utils/responsive_helper.dart';
import '../../../utils/navigation_helper.dart';
import '../../../utils/format_helper.dart';

// Widgets
import '../../../theme/app_colors.dart';

// Screens
import '../../../screens/business_admin/to_management/edit_to_screen.dart';
import '../../../screens/common/job_posting_screen.dart';

// Dialogs
import '../../../screens/business_admin/dialogs/confirmed_list_dialog.dart';
import '../../../screens/business_admin/dialogs/work_detail_management_dialog.dart';
import '../../../screens/business_admin/dialogs/to_list_dialogs.dart';

// Local Widgets
import 'admin_to_item_card.dart';
import 'admin_work_detail.dart';

/// ✨ TO 그룹 카드 (개선된 디자인 - 한눈에 들어오는 UI)
/// 
/// 개선 사항:
/// - 좌측 상태 컬러바 추가
/// - 정보 계층 명확화 (제목 강조)
/// - 태그/배지 최소화
/// - 핵심 정보만 표시 (날짜 + 인원)
class TOGroupCard extends StatefulWidget {
  final TOGroupItem groupItem;
  final FirestoreService firestoreService;
  final TOListDialogs dialogs;
  final List<TOGroupItem> allGroupItems;
  final VoidCallback onChanged;
  final bool isExpanded;
  final Set<String> expandedTOs;
  final VoidCallback onToggleExpand;
  final Function(String toId) onToggleTOExpand;
  final DateTime? selectedDate;
  
  // ✨ Lazy Loading 상태
  final bool isGroupLoading;      // 그룹 로딩 중
  final Set<String> loadingTOs;   // 로딩 중인 TO 목록

  const TOGroupCard({
    super.key,
    required this.groupItem,
    required this.firestoreService,
    required this.dialogs,
    required this.allGroupItems,
    required this.onChanged,
    required this.isExpanded,
    required this.expandedTOs,
    required this.onToggleExpand,
    required this.onToggleTOExpand,
    this.selectedDate,
    this.isGroupLoading = false,
    this.loadingTOs = const {},
  });

  @override
  State<TOGroupCard> createState() => _TOGroupCardState();
}

class _TOGroupCardState extends State<TOGroupCard> {
  @override
  Widget build(BuildContext context) {
    final masterTO = widget.groupItem.masterTO;
    final theme = Theme.of(context);
    
    // 전체 통계 계산
    int totalConfirmed = 0;
    int totalPending = 0;
    int totalRequired = 0;
    
    for (var toItem in widget.groupItem.groupTOs) {
      totalConfirmed += toItem.confirmedCount;
      totalPending += toItem.pendingCount;
      totalRequired += toItem.totalRequired;
    }
    
    // 인원 충족 여부 (workDetails 로드 안됐으면 TO 문서 기준)
    final isFull = widget.groupItem.groupTOs.isEmpty 
        ? false 
        : widget.groupItem.groupTOs.every((toItem) {
            // workDetails 로드 안됐으면 TO 문서의 통계 사용
            if (!toItem.isWorkDetailLoaded || toItem.workDetails.isEmpty) {
              return toItem.confirmedCount >= toItem.totalRequired && toItem.totalRequired > 0;
            }
            return toItem.workDetails.every((work) {
              final stats = toItem.workDetailStats?[work.workType];
              final confirmed = stats?['confirmed'] ?? 0;
              return confirmed >= work.requiredCount;
            });
          });

    // 전체 마감 여부
    final allClosed = widget.groupItem.groupTOs.isEmpty
        ? false
        : widget.groupItem.groupTOs.every((toItem) {
            // 장기공고: applicationDeadline 기준으로 판단 (WorkDetails 로드 여부 상관없이)
            if (toItem.to.isLongTerm) {
              return toItem.to.isManualClosed || toItem.to.isDeadlinePassed;
            }
            
            // 단기공고: workDetails 로드 안됐으면 TO 문서의 마감 상태 사용
            if (!toItem.isWorkDetailLoaded || toItem.workDetails.isEmpty) {
              return toItem.to.isClosed;
            }
            return toItem.workDetails.every((work) =>
                work.isClosed || work.isTimeExpired || work.isFull);
          });
    // ✨ 상태별 컬러바 색상 결정
    Color statusBarColor;
    if (allClosed) {
      statusBarColor = AppColors.grey400;
    } else if (isFull) {
      statusBarColor = AppColors.success;
    } else {
      statusBarColor = theme.primaryColor;
    }

    return Container(
      margin: EdgeInsets.only(
        bottom: ResponsiveHelper.spacing(context, 12),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ✨ 좌측 상태 컬러바
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: statusBarColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            
            // ✨ 메인 카드
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
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
                              // ✨ 첫째 줄: 사업장 + 타입 아이콘 + 메뉴
                              Row(
                                children: [
                                  // 사업장 아이콘
                                  Icon(
                                    Icons.business,
                                    size: ResponsiveHelper.iconSize(context, 14),
                                    color: AppColors.grey500,
                                  ),
                                  SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                                  // 사업장명
                                  Expanded(
                                    child: Text(
                                      masterTO.businessName,
                                      style: ResponsiveHelper.smallStyle(
                                        context,
                                        color: AppColors.grey600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  
                                  // 그룹/단일 표시 (아이콘만)
                                  if (widget.groupItem.isGrouped)
                                    _buildMiniIconBadge(
                                      context,
                                      icon: Icons.folder,
                                      color: AppColors.successDark,
                                      bgColor: AppColors.successBg,
                                    ),
                                  
                                  SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                                  
                                  // 장기/단기 아이콘
                                  _buildMiniIconBadge(
                                    context,
                                    icon: masterTO.isLongTerm 
                                        ? Icons.calendar_month 
                                        : Icons.today,
                                    color: masterTO.isLongTerm 
                                        ? AppColors.purpleDark 
                                        : AppColors.infoDark,
                                    bgColor: masterTO.isLongTerm 
                                        ? AppColors.purpleBg 
                                        : AppColors.infoBg,
                                  ),
                                  
                                  SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                                  
                                  // 메뉴 버튼
                                  widget.groupItem.isGrouped
                                      ? _buildGroupTOMenu(context)
                                      : _buildSingleTOMenu(context),
                                ],
                              ),
                              
                              SizedBox(height: ResponsiveHelper.spacing(context, 10)),
                              
                              // ✨ 둘째 줄: 제목 (크게 강조!)
                              Text(
                                masterTO.groupName ?? masterTO.title,
                                style: ResponsiveHelper.titleStyle(context).copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                  height: 1.3,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              
                              SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                              
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
                              
                              // ✨ 예약 공개 표시 (있는 경우만)
                              if (!widget.groupItem.isGrouped && masterTO.isPendingPublish) ...[
                                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                                _buildScheduledInfo(context, masterTO),
                              ],
                              
                              // ✨ 장기공고 마감일시 표시 (장기공고인 경우)
                              if (masterTO.isLongTerm && !allClosed) ...[
                                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.timer_outlined,
                                      size: ResponsiveHelper.iconSize(context, 14),
                                      color: masterTO.isDeadlinePassed 
                                          ? AppColors.grey500 
                                          : AppColors.warningDark,
                                    ),
                                    SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                                    Text(
                                      '지원마감 ${masterTO.formattedDeadline}',
                                      style: ResponsiveHelper.smallStyle(
                                        context,
                                        color: masterTO.isDeadlinePassed 
                                            ? AppColors.grey500 
                                            : AppColors.warningDark,
                                      ),
                                    ),
                                    if (masterTO.isDeadlineSoon && !masterTO.isDeadlinePassed) ...[
                                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                                      Container(
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
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                              
                              // ✨ 상태 표시 (마감된 경우만)
                              if (allClosed) ...[
                                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                                _buildClosedBadge(context),
                              ],
                              
                              // 펼침 힌트
                              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
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
                      
                      // ✨ 펼쳐진 경우: 그룹 TO 목록
                      if (widget.isExpanded && widget.groupItem.isGrouped) ...[
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
                                ? Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(
                                        ResponsiveHelper.spacing(context, 24),
                                      ),
                                      child: Column(
                                        children: [
                                          SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: theme.primaryColor,
                                            ),
                                          ),
                                          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                                          Text(
                                            '불러오는 중...',
                                            style: ResponsiveHelper.smallStyle(context).copyWith(
                                              color: AppColors.grey500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                // ✨ 로드 완료 - TO 목록 표시
                                : Column(
                                    children: _getFilteredGroupTOs().map((toItem) {
                                      return TOItemCard(
                                        toItem: toItem,
                                        groupItem: widget.groupItem,
                                        firestoreService: widget.firestoreService,
                                        dialogs: widget.dialogs,
                                        onChanged: widget.onChanged,
                                        isExpanded: widget.expandedTOs.contains(toItem.to.id),
                                        onToggleExpand: () => widget.onToggleTOExpand(toItem.to.id),
                                        isLoading: widget.loadingTOs.contains(toItem.to.id),  // ✨ 추가
                                      );
                                    }).toList(),
                                  ),
                          ),
                        ),
                      ],
                      
                      // ✨ 펼쳐진 경우: 단일 TO 업무 상세
                      if (widget.isExpanded && !widget.groupItem.isGrouped) ...[
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
                          child: widget.loadingTOs.contains(widget.groupItem.groupTOs.first.to.id)
                              // ✨ 로딩 중 스피너
                              ? Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(
                                      ResponsiveHelper.spacing(context, 24),
                                    ),
                                    child: Column(
                                      children: [
                                        SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: theme.primaryColor,
                                          ),
                                        ),
                                        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                                        Text(
                                          '업무 정보 불러오는 중...',
                                          style: ResponsiveHelper.smallStyle(context).copyWith(
                                            color: AppColors.grey500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
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
                              
                              // 업무 목록
                              ...widget.groupItem.groupTOs.first.workDetails.map((work) {
                                final stats = widget.groupItem.groupTOs.first
                                    .workDetailStats?[work.workType];
                                final confirmed = stats?['confirmed'] ?? 0;
                                final pending = stats?['pending'] ?? 0;

                                return WorkDetailRow(
                                  work: work,
                                  confirmedCount: confirmed,
                                  pendingCount: pending,
                                  toItem: widget.groupItem.groupTOs.first,
                                  firestoreService: widget.firestoreService,
                                  onChanged: widget.onChanged,
                                );
                              }),
                            ],
                          ),
                        ),
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

  // ═══════════════════════════════════════════════════════════════
  // ✨ 새로운 간소화된 위젯들
  // ═══════════════════════════════════════════════════════════════

  /// 날짜 텍스트 생성
  String _getDateText(dynamic masterTO) {
    if (masterTO.isLongTerm) {
      return masterTO.longTermPeriodWithDays;
    } else if (widget.groupItem.isGrouped) {
      final count = widget.groupItem.groupTOs.length;
      return '${FormatHelper.formatDate(masterTO.date)} 외 ${count - 1}일';
    } else {
      return FormatHelper.formatDate(masterTO.date);
    }
  }

  /// ✨ 미니 아이콘 배지 (타입, 그룹 표시용)
  Widget _buildMiniIconBadge(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 5)),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(
        icon,
        size: ResponsiveHelper.iconSize(context, 12),
        color: color,
      ),
    );
  }

  /// ✨ 인원 현황 배지 (핵심 정보)
  Widget _buildPersonnelBadge(
    BuildContext context, {
    required int confirmed,
    required int required,
    required int pending,
    required bool isFull,
  }) {
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
          width: 1,
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
            '$confirmed/$required',
            style: ResponsiveHelper.bodyStyle(
              context,
              color: isFull ? AppColors.successDark : AppColors.infoDark,
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
      ),
    );
  }

  /// ✨ 예약 공개 정보 (간소화)
  Widget _buildScheduledInfo(BuildContext context, dynamic masterTO) {
    return Row(
      children: [
        Icon(
          Icons.visibility_off,
          size: ResponsiveHelper.iconSize(context, 12),
          color: AppColors.warningDark,
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
        Text(
          '예약 공개: ${masterTO.publishAtDisplay ?? ''}',
          style: ResponsiveHelper.smallStyle(
            context,
            color: AppColors.warningDark,
          ),
        ),
      ],
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
            '마감됨',
            style: ResponsiveHelper.smallStyle(
              context,
              color: AppColors.grey600,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 메뉴 관련 (기존 유지)
  // ═══════════════════════════════════════════════════════════════

  /// 단일 TO 메뉴
  Widget _buildSingleTOMenu(BuildContext context) {
    final masterTO = widget.groupItem.masterTO;

    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert,
        size: ResponsiveHelper.iconSize(context, 20),
        color: AppColors.grey600,
      ),
      padding: EdgeInsets.zero,
      tooltip: '메뉴',
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      onSelected: (value) => _handleSingleTOMenuAction(context, value),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'preview',
          child: Row(
            children: [
              Icon(
                Icons.visibility,
                size: ResponsiveHelper.iconSize(context, 18),
                color: AppColors.info,  
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              const Text('공고 미리보기'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(
                Icons.edit,
                size: ResponsiveHelper.iconSize(context, 18),
                color: AppColors.warning,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              const Text('수정'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(
                Icons.delete,
                size: ResponsiveHelper.iconSize(context, 18),
                color: AppColors.error,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              const Text('삭제'),
            ],
          ),
        ),
        if (masterTO.isShortTerm)
          PopupMenuItem(
            value: 'link',
            child: Row(
              children: [
                Icon(
                  Icons.link,
                  size: ResponsiveHelper.iconSize(context, 18),
                  color: AppColors.info,  
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                const Text('그룹 연결'),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'confirmedList',
          child: Row(
            children: [
              Icon(
                Icons.check_circle_outline,
                size: ResponsiveHelper.iconSize(context, 18),
                color: AppColors.success,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              const Text('확정명단'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'manageWorkDetails',
          child: Row(
            children: [
              Icon(
                Icons.assignment_turned_in,
                size: ResponsiveHelper.iconSize(context, 18),
                color: AppColors.purple,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              const Text('업무별 마감'),
            ],
          ),
        ),
      ],
    );
  }

  /// 그룹 TO 메뉴
  Widget _buildGroupTOMenu(BuildContext context) {
    final masterTO = widget.groupItem.masterTO;

    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert,
        size: ResponsiveHelper.iconSize(context, 20),
        color: AppColors.grey600,
      ),
      padding: EdgeInsets.zero,
      tooltip: '메뉴',
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      onSelected: (value) => _handleGroupTOMenuAction(context, value),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'editGroupName',
          child: Row(
            children: [
              Icon(
                Icons.edit,
                size: ResponsiveHelper.iconSize(context, 18),
                color: AppColors.info,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              const Text('그룹명 수정'),
            ],
          ),
        ),
        PopupMenuItem(
          value: masterTO.isClosed ? 'reopenGroup' : 'closeGroup',
          child: Row(
            children: [
              Icon(
                masterTO.isClosed ? Icons.lock_open : Icons.lock,
                size: ResponsiveHelper.iconSize(context, 18),
                color: masterTO.isClosed ? AppColors.success : AppColors.warning, 
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Text(masterTO.isClosed ? '그룹 재오픈' : '그룹 마감'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'deleteGroup',
          child: Row(
            children: [
              Icon(
                Icons.delete_forever,
                size: ResponsiveHelper.iconSize(context, 18),
                color: AppColors.error,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              const Text('그룹 전체 삭제'),
            ],
          ),
        ),
      ],
    );
  }

  /// 단일 TO 메뉴 액션
  Future<void> _handleSingleTOMenuAction(
      BuildContext context, String value) async {
    final masterTO = widget.groupItem.masterTO;

    switch (value) {
      case 'preview':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => JobPostingScreen(
              to: widget.groupItem.masterTO,
              workDetails: widget.groupItem.groupTOs.first.workDetails,
              mode: TODetailMode.adminPreview,
            ),
          ),
        );
        break;
      case 'edit':
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
        break;

      case 'delete':
        widget.dialogs.showDeleteTODialog(widget.groupItem.groupTOs.first);
        break;

      case 'link':
        widget.dialogs.showReconnectToGroupDialog(
          widget.groupItem.groupTOs.first,
          widget.allGroupItems,
        );
        break;

      case 'confirmedList':
        ConfirmedListDialog(
          context: context,
          toItem: widget.groupItem.groupTOs.first,
          firestoreService: widget.firestoreService,
        ).show();
        break;

      case 'manageWorkDetails':
        WorkDetailManagementDialog(
          context: context,
          toItem: widget.groupItem.groupTOs.first,
          firestoreService: widget.firestoreService,
          onComplete: widget.onChanged,
        ).show();
        break;
    }
  }

  /// 그룹 TO 메뉴 액션
  Future<void> _handleGroupTOMenuAction(
      BuildContext context, String value) async {
    final masterTO = widget.groupItem.masterTO;

    switch (value) {
      case 'editGroupName':
        widget.dialogs.showEditGroupNameDialog(masterTO);
        break;

      case 'closeGroup':
        widget.dialogs.showCloseGroupDialog(widget.groupItem);
        break;

      case 'reopenGroup':
        widget.dialogs.showReopenGroupDialog(widget.groupItem);
        break;

      case 'deleteGroup':
        widget.dialogs.showDeleteGroupDialog(widget.groupItem);
        break;
    }
  }
  /// 선택된 날짜에 해당하는 TO만 필터링
  List<TOItem> _getFilteredGroupTOs() {
    // selectedDate가 null이면 전체 표시 (리스트 뷰)
    if (widget.selectedDate == null) {
      return widget.groupItem.groupTOs;
    }
    
    // selectedDate가 있으면 해당 날짜 TO만 필터링 (캘린더 뷰)
    return widget.groupItem.groupTOs.where((toItem) {
      return DateUtils.isSameDay(toItem.to.date, widget.selectedDate!);
    }).toList();
  }
}