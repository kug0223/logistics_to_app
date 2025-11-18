import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// Models
import '../../models/ui/admin_to_list_ui_models.dart';

// Services
import '../../services/firestore_service.dart';

// Utils
import '../../utils/toast_helper.dart';
import '../../utils/responsive_helper.dart';

// Widgets
import '../common/styled_container.dart';

// Screens
import '../../screens/admin/admin_edit_to_screen.dart';

// Dialogs
import '../../screens/admin/dialogs/confirmed_list_dialog.dart';
import '../../screens/admin/dialogs/work_detail_management_dialog.dart';
import '../../screens/admin/dialogs/to_list_dialogs.dart';

// Local Widgets
import '../../screens/admin/widgets/work_detail_row.dart';

/// TO 아이템 카드 (그룹 내 개별 TO)
class TOItemCard extends StatefulWidget {
  final TOItem toItem;
  final TOGroupItem groupItem;
  final FirestoreService firestoreService;
  final TOListDialogs dialogs;
  final VoidCallback onChanged;
  final bool isExpanded;
  final VoidCallback onToggleExpand;

  const TOItemCard({
    super.key,
    required this.toItem,
    required this.groupItem,
    required this.firestoreService,
    required this.dialogs,
    required this.onChanged,
    required this.isExpanded,
    required this.onToggleExpand,
  });

  @override
  State<TOItemCard> createState() => _TOItemCardState();
}

class _TOItemCardState extends State<TOItemCard> {
  @override
  Widget build(BuildContext context) {
    final to = widget.toItem.to;
    final dateFormat = DateFormat('MM/dd (E)', 'ko_KR');
    
    final isFull = widget.toItem.workDetails.every((work) {
      final stats = widget.toItem.workDetailStats?[work.workType];
      final confirmed = stats?['confirmed'] ?? 0;
      return confirmed >= work.requiredCount;
    });

    return Container(
      margin: EdgeInsets.only(  // ⭐ const 제거
        bottom: ResponsiveHelper.spacing(context, 8),  // ⭐ 변경
        left: ResponsiveHelper.spacing(context, 12),  // ⭐ 변경
      ),
      decoration: BoxDecoration(
        color: widget.isExpanded ? Theme.of(context).primaryColor.withOpacity(0.1) : Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: widget.isExpanded ? Theme.of(context).primaryColor : Colors.grey[300]!,
          width: widget.isExpanded ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: widget.onToggleExpand,
            child: Padding(
              padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        dateFormat.format(to.date),
                        style: ResponsiveHelper.smallStyle(  // ⭐ 변경
                          context,
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 12)),  // ⭐ 변경
                      Expanded(
                        child: Text(
                          to.title,
                          style: ResponsiveHelper.bodyStyle(  // ⭐ 변경
                            context,
                            color: Colors.grey[800],
                          ).copyWith(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
                      _buildStatusBadge(context, isFull),
                    ],
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,  // ⭐ 추가
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: ResponsiveHelper.iconSize(context, 14),  // ⭐ 변경
                        color: Colors.grey[600],
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 6)),  // ⭐ 변경
                      Expanded(
                        child: to.isLongTerm 
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  to.longTermPeriodWithDays,
                                  style: ResponsiveHelper.smallStyle(  // ⭐ 변경
                                    context,
                                    color: Colors.grey[700],
                                  ),
                                ),
                                if (to.workDays != null && to.workDays!.isNotEmpty) ...[
                                  SizedBox(height: ResponsiveHelper.spacing(context, 2)),  // ⭐ 변경
                                  Text(
                                    to.workDaysLabel,
                                    style: ResponsiveHelper.tinyStyle(  // ⭐ 변경
                                      context,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ],
                            )
                          : Text(
                              dateFormat.format(to.date),
                              style: ResponsiveHelper.smallStyle(  // ⭐ 변경
                                context,
                                color: Colors.grey[700],
                              ),
                            ),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),  // ⭐ Spacer 대신
                      _buildDeadlineBadge(context, to),
                    ],
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
                  Row(
                    children: [
                      _buildStatsBadge(context, isFull),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
                      if (widget.toItem.pendingCount > 0)
                        _buildPendingBadge(context),
                      const Spacer(),
                      _buildPopupMenu(context),
                      SizedBox(width: ResponsiveHelper.spacing(context, 4)),  // ⭐ 변경
                      Icon(
                        widget.isExpanded ? Icons.expand_less : Icons.expand_more,
                        size: ResponsiveHelper.iconSize(context, 20),  // ⭐ 변경
                        color: Colors.grey[600],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (widget.isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '업무 상세',
                    style: ResponsiveHelper.smallStyle(  // ⭐ 변경
                      context,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
                  ...widget.toItem.workDetails.map((work) {
                    final stats = widget.toItem.workDetailStats?[work.workType];
                    final confirmed = stats?['confirmed'] ?? 0;
                    final pending = stats?['pending'] ?? 0;
                    
                    return WorkDetailRow(
                      work: work,
                      confirmedCount: confirmed,
                      pendingCount: pending,
                      toItem: widget.toItem,
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
    final allWorksClosed = widget.toItem.workDetails.every((work) => 
      work.isClosed || work.isTimeExpired || work.isFull
    );
    
    if (allWorksClosed) {
      return StyledOutlineBadge(
        label: '마감됨',
        color: Colors.grey[600]!,
        backgroundColor: Colors.grey[300],
        icon: Icons.lock,
        fontSize: ResponsiveHelper.getFontSize(context, 10),  // ⭐ 변경
        padding: EdgeInsets.symmetric(  // ⭐ const 제거
          horizontal: ResponsiveHelper.spacing(context, 6),  // ⭐ 변경
          vertical: ResponsiveHelper.spacing(context, 3),  // ⭐ 변경
        ),
        borderRadius: 10,
      );
    } else if (isFull) {
      return StyledOutlineBadge(
        label: '인원충족',
        color: Colors.green[600]!,
        icon: Icons.check_circle,
        fontSize: ResponsiveHelper.getFontSize(context, 10),  // ⭐ 변경
        padding: EdgeInsets.symmetric(  // ⭐ const 제거
          horizontal: ResponsiveHelper.spacing(context, 6),  // ⭐ 변경
          vertical: ResponsiveHelper.spacing(context, 3),  // ⭐ 변경
        ),
        borderRadius: 10,
      );
    } else {
      return StyledOutlineBadge(
        label: '진행중',
        color: Theme.of(context).primaryColor,
        icon: Icons.circle,
        fontSize: ResponsiveHelper.getFontSize(context, 10),  // ⭐ 변경
        padding: EdgeInsets.symmetric(  // ⭐ const 제거
          horizontal: ResponsiveHelper.spacing(context, 6),  // ⭐ 변경
          vertical: ResponsiveHelper.spacing(context, 3),  // ⭐ 변경
        ),
        borderRadius: 10,
      );
    }
  }

  /// 마감시간 배지
  Widget _buildDeadlineBadge(BuildContext context, to) {
    if (to.deadlineType == 'FIXED_TIME') {
      return StyledBadge(
        label: '🕐 ${DateFormat('MM/dd HH:mm').format(to.applicationDeadline)}',
        backgroundColor: Colors.orange[50]!,
        textColor: Colors.orange[700]!,
        fontSize: ResponsiveHelper.getFontSize(context, 12),  // ⭐ 변경
        borderRadius: 4,
      );
    }
    
    if (to.deadlineType == 'HOURS_BEFORE' && to.hoursBeforeStart != null) {
      return StyledBadge(
        label: '🕐 각 업무 ${to.hoursBeforeStart}시간 전',
        backgroundColor: Colors.orange[50]!,
        textColor: Colors.orange[700]!,
        fontSize: ResponsiveHelper.getFontSize(context, 12),  // ⭐ 변경
        borderRadius: 4,
      );
    }
    
    return const SizedBox.shrink();
  }

  /// 통계 배지
  Widget _buildStatsBadge(BuildContext context, bool isFull) {
    return Container(
      padding: EdgeInsets.symmetric(  // ⭐ const 제거
        horizontal: ResponsiveHelper.spacing(context, 8),  // ⭐ 변경
        vertical: ResponsiveHelper.spacing(context, 4),  // ⭐ 변경
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
          Text(
            '👥',
            style: ResponsiveHelper.tinyStyle(context),  // ⭐ 변경
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),  // ⭐ 변경
          Text(
            '확정 ${widget.toItem.confirmedCount}/${widget.toItem.totalRequired}명',
            style: ResponsiveHelper.tinyStyle(  // ⭐ 변경
              context,
              color: isFull 
                ? Colors.green[700] 
                : Theme.of(context).primaryColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// 대기 인원 배지
  Widget _buildPendingBadge(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(  // ⭐ const 제거
        horizontal: ResponsiveHelper.spacing(context, 8),  // ⭐ 변경
        vertical: ResponsiveHelper.spacing(context, 4),  // ⭐ 변경
      ),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange[200]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '⏳',
            style: ResponsiveHelper.tinyStyle(context),  // ⭐ 변경
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),  // ⭐ 변경
          Text(
            '대기 ${widget.toItem.pendingCount}명',
            style: ResponsiveHelper.tinyStyle(  // ⭐ 변경
              context,
              color: Colors.orange[700],
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// 팝업 메뉴
  Widget _buildPopupMenu(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert,
        size: ResponsiveHelper.iconSize(context, 20),  // ⭐ 변경
        color: Colors.grey[700],
      ),
      padding: EdgeInsets.zero,
      tooltip: '메뉴',
      onSelected: (value) => _handleMenuAction(context, value),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(
                Icons.edit,
                size: ResponsiveHelper.iconSize(context, 18),  // ⭐ 변경
                color: Colors.orange[700],
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),  // ⭐ 변경
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
                size: ResponsiveHelper.iconSize(context, 18),  // ⭐ 변경
                color: Colors.red[700],
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),  // ⭐ 변경
              const Text('삭제'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'unlink',
          child: Row(
            children: [
              Icon(
                Icons.link_off,
                size: ResponsiveHelper.iconSize(context, 18),  // ⭐ 변경
                color: Colors.orange[700],
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),  // ⭐ 변경
              const Text('그룹 해제'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'confirmedList',
          child: Row(
            children: [
              Icon(
                Icons.check_circle_outline,
                size: ResponsiveHelper.iconSize(context, 18),  // ⭐ 변경
                color: Colors.green[600],
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),  // ⭐ 변경
              const Text('확정명단'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'manageWorkDetails',
          child: Row(
            children: [
              Icon(
                Icons.task_alt,
                size: ResponsiveHelper.iconSize(context, 18),  // ⭐ 변경
                color: Colors.purple[600],
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),  // ⭐ 변경
              const Text('업무별 마감'),
            ],
          ),
        ),
      ],
    );
  }

  /// 메뉴 액션 처리
  Future<void> _handleMenuAction(BuildContext context, String value) async {
    switch (value) {
      case 'edit':
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AdminEditTOScreen(to: widget.toItem.to),
          ),
        );
        if (result == true) {
          widget.firestoreService.clearCache();
          widget.onChanged();
        }
        break;
        
      case 'delete':
        widget.dialogs.showDeleteTODialog(widget.toItem);
        break;
        
      case 'unlink':
        widget.dialogs.showRemoveFromGroupDialog(widget.toItem);
        break;
        
      case 'confirmedList':
        _showConfirmedListDialog(context);
        break;
        
      case 'manageWorkDetails':
        WorkDetailManagementDialog(
          context: context,
          toItem: widget.toItem,
          firestoreService: widget.firestoreService,
          onComplete: widget.onChanged,
        ).show();
        break;
    }
  }

  /// 확정명단 다이얼로그
  void _showConfirmedListDialog(BuildContext context) {
    ConfirmedListDialog(
      context: context,
      toItem: widget.toItem,
      firestoreService: widget.firestoreService,
    ).show();
  }
}