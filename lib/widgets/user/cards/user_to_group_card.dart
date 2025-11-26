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
import '../../common/styled_container.dart';

// Screens
import '../../../screens/business_admin/to_management/edit_to_screen.dart';

// Dialogs
import '../../../screens/business_admin/dialogs/confirmed_list_dialog.dart';
import '../../../screens/business_admin/dialogs/work_detail_management_dialog.dart';
import '../../../screens/business_admin/dialogs/to_list_dialogs.dart';

// Local Widgets
import '../../admin/cards/admin_to_item_card.dart';
import '../../admin/cards/admin_work_detail.dart';

/// TO 그룹 카드 (그룹 TO 또는 단일 TO)
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

    return Card(
      elevation: widget.isExpanded ? 4 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: widget.isExpanded 
              ? Theme.of(context).primaryColor
              : (isFull ? Colors.green[200]! : Colors.grey[200]!),
          width: widget.isExpanded ? 2 : (isFull ? 2 : 1),
        ),
      ),
      child: Column(
        children: [
          // 헤더 (클릭 가능)
          InkWell(
            onTap: widget.onToggleExpand,
            child: Padding(
              padding: ResponsiveHelper.cardPadding(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 첫 줄: 사업장 + 근무유형 + 상태
                  Row(
                    children: [
                      // 사업장명
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: ResponsiveHelper.spacing(context, 10),
                          vertical: ResponsiveHelper.spacing(context, 5),
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.business, 
                              size: ResponsiveHelper.iconSize(context, 14), 
                              color: Colors.white
                            ),
                            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                            Text(
                              masterTO.businessName,
                              style: ResponsiveHelper.smallStyle(
                                context,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                      // 장기/단기 배지
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: ResponsiveHelper.spacing(context, 8),
                          vertical: ResponsiveHelper.spacing(context, 4),
                        ),
                        decoration: BoxDecoration(
                          color: masterTO.isLongTerm ? Colors.purple[50] : Colors.blue[50],
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: masterTO.isLongTerm ? Colors.purple[300]! : Colors.blue[300]!,
                          ),
                        ),
                        child: Text(
                          masterTO.jobTypeLabel,
                          style: ResponsiveHelper.tinyStyle(
                            context,
                            color: masterTO.isLongTerm ? Colors.purple[700] : Colors.blue[700],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Spacer(),
                      // 상태 배지
                      _buildStatusBadge(context, isFull),
                    ],
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 10)),
                  
                  // 둘째 줄: 그룹명/단일공고 + 메뉴
                  Row(
                    children: [
                      // 그룹명 또는 단일공고 배지
                      if (masterTO.groupName != null) ...[
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: ResponsiveHelper.spacing(context, 10),
                            vertical: ResponsiveHelper.spacing(context, 6),
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green[300]!, width: 1.5),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.folder_open, 
                                size: ResponsiveHelper.iconSize(context, 16), 
                                color: Colors.green[700]
                              ),
                              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                              Text(
                                masterTO.groupName!,
                                style: ResponsiveHelper.bodyStyle(
                                  context,
                                  color: Colors.green[800],
                                ).copyWith(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: ResponsiveHelper.spacing(context, 10)),
                      ],
                      if (masterTO.groupName == null) ...[
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: ResponsiveHelper.spacing(context, 10),
                            vertical: ResponsiveHelper.spacing(context, 6),
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue[300]!, width: 1.5),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.work_outline, 
                                size: ResponsiveHelper.iconSize(context, 16), 
                                color: Colors.blue[700]
                              ),
                              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                              Text(
                                '단일 공고',
                                style: ResponsiveHelper.smallStyle(
                                  context,
                                  color: Colors.blue[800],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const Spacer(),
                      // 메뉴 버튼
                      if (!widget.groupItem.isGrouped)
                        _buildSingleTOMenu(context)
                      else if (masterTO.groupId != null)
                        _buildGroupTOMenu(context),
                      SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                      // 펼침/접힘 아이콘
                      Icon(
                        widget.isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        color: Colors.grey[600],
                      ),
                    ],
                  ),
                  
                  // 단일 TO 제목
                  if (masterTO.groupName == null) ...[
                    SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                    Text(
                      masterTO.title,
                      style: ResponsiveHelper.subtitleStyle(
                        context,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                  
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                  
                  // 날짜 및 시간 정보
                  Row(
                    children: [
                      // ✅ 변경
                      Icon(
                        Icons.calendar_today, 
                        size: ResponsiveHelper.iconSize(context, 16), 
                        color: Colors.grey[600]
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                      Expanded(
                        child: masterTO.isLongTerm
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  masterTO.longTermPeriodWithDays,
                                  style: ResponsiveHelper.bodyStyle(context, color: Colors.grey[700]),
                                ),
                                if (masterTO.workDays != null && masterTO.workDays!.isNotEmpty) ...[
                                  SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                                  Text(
                                    masterTO.workDaysLabel,
                                    style: ResponsiveHelper.smallStyle(context, color: Colors.grey[600]),
                                  ),
                                ],
                              ],
                            )
                          : Text(
                            widget.groupItem.isGrouped
                                ? '${dateFormat.format(masterTO.date)} 외 ${widget.groupItem.groupTOs.length - 1}일'
                                : dateFormat.format(masterTO.date),
                            style: ResponsiveHelper.bodyStyle(context, color: Colors.grey[700]),
                          ),
                      ),
                      // 단일 TO인 경우 마감시간
                      if (!widget.groupItem.isGrouped) ...[
                        const Spacer(),
                        _buildDeadlineBadge(context, masterTO),
                      ],
                    ],
                  ),
                  
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                  
                  // 통계
                  Row(
                    children: [  
                     Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: ResponsiveHelper.spacing(context, 8),
                          vertical: ResponsiveHelper.spacing(context, 4),
                        ),
                        decoration: BoxDecoration(
                          color: isFull 
                            ? Colors.green[50] 
                            : Theme.of(context).primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isFull 
                              ? Colors.green[200]! 
                              : Theme.of(context).primaryColor.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('👥', style: ResponsiveHelper.tinyStyle(context)),
                            SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                            Text(
                              '확정 $totalConfirmed/$totalRequired명',
                              style: ResponsiveHelper.tinyStyle(
                                context,
                                color: isFull ? Colors.green[700] : Theme.of(context).primaryColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                      if (totalPending > 0)
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: ResponsiveHelper.spacing(context, 8),
                            vertical: ResponsiveHelper.spacing(context, 4),
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange[200]!),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('⏳', style: ResponsiveHelper.tinyStyle(context)),
                              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                              Text(
                                '대기 $totalPending명',
                                style: ResponsiveHelper.tinyStyle(
                                  context,
                                  color: Colors.orange[700],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const Spacer()
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          // 펼쳐진 경우: 그룹 TO 목록
          if (widget.isExpanded && widget.groupItem.isGrouped) ...[
            const Divider(height: 1),
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
            const Divider(height: 1),
            Padding(
              padding: ResponsiveHelper.cardPadding(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '업무 상세',
                    style: ResponsiveHelper.smallStyle(
                      context,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  ...widget.groupItem.groupTOs.first.workDetails.map((work) {
                    final stats = widget.groupItem.groupTOs.first.workDetailStats?[work.workType];
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
    );
  }

  /// 상태 배지
  Widget _buildStatusBadge(BuildContext context, bool isFull) {
    bool allClosed = widget.groupItem.groupTOs.every((toItem) {
      return toItem.workDetails.every((work) => 
        work.isClosed || work.isTimeExpired || work.isFull
      );
    });
    
    if (allClosed) {
      return StyledOutlineBadge(
        label: '마감됨',
        color: Colors.grey[600]!,
        backgroundColor: Colors.grey[50],
        icon: Icons.lock,
        fontSize: ResponsiveHelper.getFontSize(context, 11),
      );
    } else if (isFull) {
      return StyledOutlineBadge(
        label: '인원충족',
        color: Colors.green[600]!,
        icon: Icons.check_circle,
        fontSize: ResponsiveHelper.getFontSize(context, 11),
      );
    } else {
      return StyledOutlineBadge(
        label: '진행중',
        color: Theme.of(context).primaryColor,
        icon: Icons.circle,
        fontSize: ResponsiveHelper.getFontSize(context, 11),
      );
    }
  }

  /// 마감시간 배지
  Widget _buildDeadlineBadge(BuildContext context, masterTO) {
    if (masterTO.deadlineType == 'FIXED_TIME') {
      return StyledBadge(
        label: '🕐 ${DateFormat('MM/dd HH:mm').format(masterTO.applicationDeadline)}',
        backgroundColor: Colors.orange[50]!,
        textColor: Colors.orange[700]!,
        fontSize: ResponsiveHelper.getFontSize(context, 12),
        borderRadius: 4,
      );
    }
    
    if (masterTO.deadlineType == 'HOURS_BEFORE' && masterTO.hoursBeforeStart != null) {
      return StyledBadge(
        label: '🕐 각 업무 ${masterTO.hoursBeforeStart}시간 전',
        backgroundColor: Colors.orange[50]!,
        textColor: Colors.orange[700]!,
        fontSize: ResponsiveHelper.getFontSize(context, 12),
        borderRadius: 4,
      );
    }
    
    return const SizedBox.shrink();
  }

  /// 단일 TO 메뉴
  Widget _buildSingleTOMenu(BuildContext context) {
    final masterTO = widget.groupItem.masterTO;
    
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert, 
        size: ResponsiveHelper.iconSize(context, 20), 
        color: Colors.grey[700]
      ),
      padding: EdgeInsets.zero,
      tooltip: '메뉴',
      onSelected: (value) => _handleSingleTOMenuAction(context, value),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(
                Icons.edit, 
                size: ResponsiveHelper.iconSize(context, 18), 
                color: Colors.orange[600]
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
              Icon(Icons.delete, size: 18, color: Colors.red[600]),
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
                Icon(Icons.link, size: 18, color: Colors.blue[600]),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                const Text('그룹 연결'),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'confirmedList',
          child: Row(
            children: [
              Icon(Icons.check_circle_outline, size: 18, color: Colors.green[600]),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              const Text('확정명단'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'manageWorkDetails',
          child: Row(
            children: [
              Icon(Icons.assignment_turned_in, size: 18, color: Colors.purple[600]),
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
        color: Colors.grey[700]
      ),
      padding: EdgeInsets.zero,
      tooltip: '메뉴',
      onSelected: (value) => _handleGroupTOMenuAction(context, value),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'editGroupName',
          child: Row(
            children: [
              Icon(Icons.edit, size: 18, color: Colors.blue[600]),
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
                size: 18,
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
              Icon(Icons.delete_forever, size: 18, color: Colors.red[600]),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              const Text('그룹 전체 삭제'),
            ],
          ),
        ),
      ],
    );
  }

  /// 단일 TO 메뉴 액션
  Future<void> _handleSingleTOMenuAction(BuildContext context, String value) async {
    final masterTO = widget.groupItem.masterTO;
    
    switch (value) {
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
  Future<void> _handleGroupTOMenuAction(BuildContext context, String value) async {
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