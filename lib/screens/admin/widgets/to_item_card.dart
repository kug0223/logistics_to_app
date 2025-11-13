import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// Models
import '../../../models/ui/admin_to_list_ui_models.dart';

// Services
import '../../../services/firestore_service.dart';

// Utils
import '../../../utils/toast_helper.dart';

// Widgets
import '../../../widgets/common/styled_container.dart';

// Screens
import '../admin_edit_to_screen.dart';

// Dialogs
import '../dialogs/confirmed_list_dialog.dart';
import '../dialogs/work_detail_management_dialog.dart';
import '../dialogs/to_list_dialogs.dart';

// Local Widgets
import 'work_detail_row.dart';

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
      margin: const EdgeInsets.only(bottom: 8, left: 12),
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
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        dateFormat.format(to.date),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          to.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800],
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildStatusBadge(context, isFull),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 6),
                      Expanded(
                        child: to.isLongTerm 
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  to.longTermPeriodWithDays,
                                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                                ),
                                if (to.workDays != null && to.workDays!.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    to.workDaysLabel,
                                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                  ),
                                ],
                              ],
                            )
                          : Text(
                              dateFormat.format(to.date),
                              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                            ),
                      ),
                      const Spacer(),
                      _buildDeadlineBadge(context, to),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildStatsBadge(context, isFull),
                      const SizedBox(width: 8),
                      if (widget.toItem.pendingCount > 0)
                        _buildPendingBadge(context),
                      const Spacer(),
                      _buildPopupMenu(context),
                      const SizedBox(width: 4),
                      Icon(
                        widget.isExpanded ? Icons.expand_less : Icons.expand_more,
                        size: 20,
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
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '업무 상세',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 8),
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
        fontSize: 10,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        borderRadius: 10,
      );
    } else if (isFull) {
      return StyledOutlineBadge(
        label: '인원충족',
        color: Colors.green[600]!,
        icon: Icons.check_circle,
        fontSize: 10,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        borderRadius: 10,
      );
    } else {
      return StyledOutlineBadge(
        label: '진행중',
        color: Theme.of(context).primaryColor,
        icon: Icons.circle,
        fontSize: 10,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
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
        fontSize: 12,
        borderRadius: 4,
      );
    }
    
    if (to.deadlineType == 'HOURS_BEFORE' && to.hoursBeforeStart != null) {
      return StyledBadge(
        label: '🕐 각 업무 ${to.hoursBeforeStart}시간 전',
        backgroundColor: Colors.orange[50]!,
        textColor: Colors.orange[700]!,
        fontSize: 12,
        borderRadius: 4,
      );
    }
    
    return const SizedBox.shrink();
  }

  /// 통계 배지
  Widget _buildStatsBadge(BuildContext context, bool isFull) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
          const Text('👥', style: TextStyle(fontSize: 11)),
          const SizedBox(width: 4),
          Text(
            '확정 ${widget.toItem.confirmedCount}/${widget.toItem.totalRequired}명',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isFull 
                ? Colors.green[700] 
                : Theme.of(context).primaryColor,
            ),
          ),
        ],
      ),
    );
  }

  /// 대기 인원 배지
  Widget _buildPendingBadge(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange[200]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('⏳', style: TextStyle(fontSize: 11)),
          const SizedBox(width: 4),
          Text(
            '대기 ${widget.toItem.pendingCount}명',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.orange[700],
            ),
          ),
        ],
      ),
    );
  }

  /// 팝업 메뉴
  Widget _buildPopupMenu(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, size: 20, color: Colors.grey[700]),
      padding: EdgeInsets.zero,
      tooltip: '메뉴',
      onSelected: (value) => _handleMenuAction(context, value),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit, size: 18, color: Colors.orange[700]),
              const SizedBox(width: 12),
              const Text('수정'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, size: 18, color: Colors.red[700]),
              const SizedBox(width: 12),
              const Text('삭제'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'unlink',
          child: Row(
            children: [
              Icon(Icons.link_off, size: 18, color: Colors.orange[700]),
              const SizedBox(width: 12),
              const Text('그룹 해제'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'confirmedList',
          child: Row(
            children: [
              Icon(Icons.check_circle_outline, size: 18, color: Colors.green[600]),
              const SizedBox(width: 12),
              const Text('확정명단'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'manageWorkDetails',
          child: Row(
            children: [
              Icon(Icons.task_alt, size: 18, color: Colors.purple[600]),
              const SizedBox(width: 12),
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