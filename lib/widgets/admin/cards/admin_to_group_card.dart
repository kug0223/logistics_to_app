import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// Models
import '../../../models/ui/admin_to_list_ui_models.dart';

// Services
import '../../../services/firestore_service.dart';

// Utils
import '../../../utils/responsive_helper.dart';
import '../../../utils/navigation_helper.dart';

// Widgets

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

/// ✨ TO 그룹 카드 (세련된 디자인 - 최종)
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
  });

  @override
  State<TOGroupCard> createState() => _TOGroupCardState();
}

class _TOGroupCardState extends State<TOGroupCard> {
  @override
  Widget build(BuildContext context) {
    final masterTO = widget.groupItem.masterTO;
    final dateFormat = DateFormat('MM/dd (E)', 'ko_KR');
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
    
    // 인원 충족 여부
    final isFull = widget.groupItem.groupTOs.every((toItem) {
      return toItem.workDetails.every((work) {
        final stats = toItem.workDetailStats?[work.workType];
        final confirmed = stats?['confirmed'] ?? 0;
        return confirmed >= work.requiredCount;
      });
    });

    return Container(
      margin: EdgeInsets.only(
        bottom: ResponsiveHelper.spacing(context, 12),
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),  // ✅ 0.05 → 0.08
            blurRadius: 12,  // ✅ 10 → 12
            offset: const Offset(0, 2),
            spreadRadius: 1,  // ✅ 추가!
          ),
        ],
        // ✨ 펼쳐진 경우 또는 인원 충족 시 테두리 강조
        border: widget.isExpanded
            ? Border.all(color: theme.primaryColor, width: 2)
            : isFull
                ? Border.all(color: Colors.green[300]!, width: 2)
                : Border.all(
                  color: Colors.grey[200]!,  // ⭐ 추가
                  width: 1,
                ),
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          children: [
            // ✨ 헤더 (클릭 가능)
            InkWell(
              onTap: widget.onToggleExpand,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
              child: Container(
                // ✨ 펼쳐진 경우 은은한 그라데이션
                decoration: widget.isExpanded
                    ? BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            theme.primaryColor.withOpacity(0.05),
                            Colors.white,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(20),
                          topRight: Radius.circular(20),
                        ),
                      )
                    : null,
                child: Padding(
                  padding: ResponsiveHelper.cardPadding(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ✨ 첫 줄: 사업장 + 장기/단기 배지
                      Row(
                        children: [
                          // 사업장명 (아이콘 + 배경)
                          Expanded(
                            child: Row(
                              children: [
                                Container(
                                  padding: EdgeInsets.all(
                                    ResponsiveHelper.spacing(context, 8),
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        theme.primaryColor,
                                        theme.primaryColor.withOpacity(0.85),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.business,
                                    size: ResponsiveHelper.iconSize(context, 18),
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(width: ResponsiveHelper.spacing(context, 10)),
                                Expanded(
                                  child: Text(
                                    masterTO.businessName,
                                    style: ResponsiveHelper.subtitleStyle(context).copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          
                          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                          
                          // ✅ 장기/단기 배지
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: ResponsiveHelper.spacing(context, 10),
                              vertical: ResponsiveHelper.spacing(context, 6),
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: masterTO.isLongTerm
                                    ? [Colors.purple[100]!, Colors.purple[50]!]
                                    : [Colors.blue[100]!, Colors.blue[50]!],
                              ),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: masterTO.isLongTerm
                                    ? Colors.purple[300]!
                                    : Colors.blue[300]!,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  masterTO.isLongTerm ? Icons.calendar_month : Icons.today,
                                  size: ResponsiveHelper.iconSize(context, 14),
                                  color: masterTO.isLongTerm
                                      ? Colors.purple[700]
                                      : Colors.blue[700],
                                ),
                                SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                                Text(
                                  masterTO.jobTypeLabel,
                                  style: ResponsiveHelper.smallStyle(
                                    context,
                                    fontWeight: FontWeight.bold,
                                    color: masterTO.isLongTerm
                                        ? Colors.purple[700]
                                        : Colors.blue[700],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      
                      SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                      
                      // ✨ 둘째 줄: 그룹명/단일공고 + 메뉴만!
                      Row(
                        children: [
                          // 그룹명 또는 단일공고
                          Expanded(
                            child: masterTO.groupName != null
                                ? _buildGroupNameBadge(context, masterTO.groupName!)
                                : _buildSingleTOBadge(context),
                          ),
                          
                          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                          
                          // 메뉴 버튼
                          Container(
                            decoration: BoxDecoration(
                              color: theme.primaryColor.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: widget.groupItem.isGrouped
                                ? _buildGroupTOMenu(context)
                                : _buildSingleTOMenu(context),
                          ),
                        ],
                      ),
                      
                      // 단일 TO 제목
                      if (masterTO.groupName == null) ...[
                        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                        Text(
                          masterTO.title,
                          style: ResponsiveHelper.subtitleStyle(context).copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[900],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],

                      SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                      
                      // ✨ 날짜 및 시간 정보 섹션
                      Container(
                        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 6)),
                              decoration: BoxDecoration(
                                color: Colors.blue[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.calendar_today,
                                size: ResponsiveHelper.iconSize(context, 16),
                                color: Colors.blue[700],
                              ),
                            ),
                            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                            Expanded(
                              child: masterTO.isLongTerm
                                  ? Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          masterTO.longTermPeriodWithDays,
                                          style: ResponsiveHelper.bodyStyle(context).copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        if (masterTO.workDays != null &&
                                            masterTO.workDays!.isNotEmpty) ...[
                                          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                                          Text(
                                            masterTO.workDaysLabel,
                                            style: ResponsiveHelper.smallStyle(
                                              context,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        ],
                                      ],
                                    )
                                  : Text(
                                      widget.groupItem.isGrouped
                                          ? '${dateFormat.format(masterTO.date)} 외 ${widget.groupItem.groupTOs.length - 1}일'
                                          : dateFormat.format(masterTO.date),
                                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                            // 단일 TO인 경우 마감시간
                            if (!widget.groupItem.isGrouped)
                              _buildDeadlineBadge(context, masterTO),
                          ],
                        ),
                      ),

                      SizedBox(height: ResponsiveHelper.spacing(context, 16)),

                      // ✅ 통계 섹션 + 상태 배지
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,  // ✅ 추가!
                        children: [
                          // 왼쪽 그룹: 확정 + 대기
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 확정 인원
                              Container(
                                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: isFull
                                        ? [Colors.green[50]!, Colors.green[50]!.withOpacity(0.3)]
                                        : [
                                            theme.primaryColor.withOpacity(0.1),
                                            theme.primaryColor.withOpacity(0.05)
                                          ],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isFull
                                        ? Colors.green[300]!
                                        : theme.primaryColor.withOpacity(0.3),
                                    width: 1.5,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.people,
                                      size: ResponsiveHelper.iconSize(context, 16),
                                      color: isFull ? Colors.green[700] : theme.primaryColor,
                                    ),
                                    SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                                    Text(
                                      '확정 ',
                                      style: ResponsiveHelper.smallStyle(
                                        context,
                                        color: isFull ? Colors.green[700] : theme.primaryColor,
                                      ),
                                    ),
                                    Text(
                                      '$totalConfirmed/$totalRequired',
                                      style: ResponsiveHelper.bodyStyle(
                                        context,
                                        color: isFull ? Colors.green[700] : theme.primaryColor,
                                      ).copyWith(fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                              
                              if (totalPending > 0) ...[
                                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                                // 대기 인원
                                Container(
                                  padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.orange[50]!,
                                        Colors.orange[50]!.withOpacity(0.3)
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.orange[300]!,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.schedule,
                                        size: ResponsiveHelper.iconSize(context, 16),
                                        color: Colors.orange[700],
                                      ),
                                      SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                                      Text(
                                        '대기 ',
                                        style: ResponsiveHelper.smallStyle(
                                          context,
                                          color: Colors.orange[700],
                                        ),
                                      ),
                                      Text(
                                        '$totalPending',
                                        style: ResponsiveHelper.bodyStyle(
                                          context,
                                          color: Colors.orange[700],
                                        ).copyWith(fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          
                          // 오른쪽: 상태 배지
                          _buildStatusBadge(context, isFull),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            // 펼쳐진 경우: 그룹 TO 목록
            if (widget.isExpanded && widget.groupItem.isGrouped) ...[
              Divider(height: 1, color: Colors.grey[200]),
              Padding(
                padding: ResponsiveHelper.cardPadding(context),
                child: Column(
                  children: widget.groupItem.groupTOs.map((toItem) {
                    return TOItemCard(
                      toItem: toItem,
                      groupItem: widget.groupItem,
                      firestoreService: widget.firestoreService,
                      dialogs: widget.dialogs,
                      onChanged: widget.onChanged,
                      isExpanded: widget.expandedTOs.contains(toItem.to.id),
                      onToggleExpand: () => widget.onToggleTOExpand(toItem.to.id),
                    );
                  }).toList(),
                ),
              ),
            ],
            
            // 펼쳐진 경우: 단일 TO 업무 상세
            if (widget.isExpanded && !widget.groupItem.isGrouped) ...[
              Divider(height: 1, color: Colors.grey[200]),
              Container(
                padding: ResponsiveHelper.cardPadding(context),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 6)),
                          decoration: BoxDecoration(
                            color: theme.primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.assignment,
                            size: ResponsiveHelper.iconSize(context, 16),
                            color: theme.primaryColor,
                          ),
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                        Text(
                          '업무 상세',
                          style: ResponsiveHelper.subtitleStyle(context).copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                    ...widget.groupItem.groupTOs.first.workDetails.map((work) {
                      final stats =
                          widget.groupItem.groupTOs.first.workDetailStats?[work.workType];
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
    );
  }

  /// ✨ 그룹명 배지
  Widget _buildGroupNameBadge(BuildContext context, String groupName) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green[100]!, Colors.green[50]!],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green[300]!, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.folder_open,
            size: ResponsiveHelper.iconSize(context, 18),
            color: Colors.green[700],
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Flexible(
            child: Text(
              groupName,
              style: ResponsiveHelper.bodyStyle(
                context,
                color: Colors.green[800],
              ).copyWith(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// ✨ 단일 공고 배지
  Widget _buildSingleTOBadge(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue[100]!, Colors.blue[50]!],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[300]!, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.work_outline,
            size: ResponsiveHelper.iconSize(context, 18),
            color: Colors.blue[700],
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Text(
            '단일 공고',
            style: ResponsiveHelper.bodyStyle(
              context,
              color: Colors.blue[800],
            ).copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  /// ✨ 상태 배지 (더 세련되게)
  Widget _buildStatusBadge(BuildContext context, bool isFull) {
    bool allClosed = widget.groupItem.groupTOs.every((toItem) {
      return toItem.workDetails.every((work) =>
          work.isClosed || work.isTimeExpired || work.isFull);
    });

    IconData icon;
    String label;
    Color color;

    if (allClosed) {
      icon = Icons.lock;
      label = '마감됨';
      color = Colors.grey[600]!;
    } else if (isFull) {
      icon = Icons.check_circle;
      label = '인원충족';
      color = Colors.green[600]!;
    } else {
      icon = Icons.circle;
      label = '진행중';
      color = Theme.of(context).primaryColor;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 10),
        vertical: ResponsiveHelper.spacing(context, 6),
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.2),
            color.withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.5), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: ResponsiveHelper.iconSize(context, 14),
            color: color,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Text(
            label,
            style: ResponsiveHelper.smallStyle(
              context,
              color: color,
            ).copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  /// 마감시간 배지
  Widget _buildDeadlineBadge(BuildContext context, masterTO) {
    String label;
    if (masterTO.deadlineType == 'FIXED_TIME') {
      label = '마감 ${DateFormat('MM/dd HH:mm').format(masterTO.applicationDeadline)}';
    } else if (masterTO.deadlineType == 'HOURS_BEFORE' &&
        masterTO.hoursBeforeStart != null) {
      label = '${masterTO.hoursBeforeStart}시간 전';
    } else {
      return const SizedBox.shrink();
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      decoration: BoxDecoration(
        color: Colors.orange[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange[300]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.access_time,
            size: ResponsiveHelper.iconSize(context, 12),
            color: Colors.orange[700],
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Text(
            label,
            style: ResponsiveHelper.tinyStyle(
              context,
              color: Colors.orange[700],
            ).copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  /// 단일 TO 메뉴
  Widget _buildSingleTOMenu(BuildContext context) {
    final masterTO = widget.groupItem.masterTO;

    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert,
        size: ResponsiveHelper.iconSize(context, 20),
        color: Theme.of(context).primaryColor,
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
                color: Colors.teal[600],
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
                color: Colors.orange[600],
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
                color: Colors.red[600],
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
                  color: Colors.blue[600],
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
                color: Colors.green[600],
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
                color: Colors.purple[600],
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
        color: Theme.of(context).primaryColor,
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
                color: Colors.blue[600],
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
                color: masterTO.isClosed ? Colors.green[600] : Colors.orange[600],
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
                color: Colors.red[600],
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
}