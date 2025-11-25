import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// Models
import '../../../models/ui/admin_to_list_ui_models.dart';

// Services
import '../../../services/firestore_service.dart';

// Utils
import '../../../utils/responsive_helper.dart';

// Widgets

// Screens
import '../../../screens/business_admin/to_management/edit_to_screen.dart';

// Dialogs
import '../../../screens/business_admin/dialogs/confirmed_list_dialog.dart';
import '../../../screens/business_admin/dialogs/work_detail_management_dialog.dart';
import '../../../screens/business_admin/dialogs/to_list_dialogs.dart';

// Local Widgets
import 'admin_work_detail.dart';

/// ✨ TO 아이템 카드 (그룹 내 개별 TO - 세련된 디자인)
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
    final theme = Theme.of(context);
    
    final isFull = widget.toItem.workDetails.every((work) {
      final stats = widget.toItem.workDetailStats?[work.workType];
      final confirmed = stats?['confirmed'] ?? 0;
      return confirmed >= work.requiredCount;
    });

    return Container(
      margin: EdgeInsets.only(
        bottom: ResponsiveHelper.spacing(context, 12),
        left: ResponsiveHelper.spacing(context, 12),
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        // ✨ 펼쳐진 경우 테두리 강조
        border: widget.isExpanded
            ? Border.all(color: theme.primaryColor, width: 2)
            : Border.all(color: Colors.grey[200]!, width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          children: [
            InkWell(
              onTap: widget.onToggleExpand,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              child: Container(
                // ✨ 펼쳐진 경우 그라데이션
                decoration: widget.isExpanded
                    ? BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            theme.primaryColor.withOpacity(0.05),
                            Colors.white,
                          ],
                        ),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                      )
                    : null,
                child: Padding(
                  padding: ResponsiveHelper.cardPadding(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ✅ 1줄: 날짜 배지 + 진행중 배지 + 메뉴
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // 날짜 배지
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: ResponsiveHelper.spacing(context, 10),
                              vertical: ResponsiveHelper.spacing(context, 6),
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  theme.primaryColor.withOpacity(0.15),
                                  theme.primaryColor.withOpacity(0.05),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: theme.primaryColor.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.calendar_today,
                                  size: ResponsiveHelper.iconSize(context, 14),
                                  color: theme.primaryColor,
                                ),
                                SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                                Text(
                                  dateFormat.format(to.date),
                                  style: ResponsiveHelper.smallStyle(
                                    context,
                                    color: theme.primaryColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          
                          // 오른쪽: 진행중 배지 + 메뉴
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildStatusBadge(context, isFull),
                              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                              _buildPopupMenu(context),
                            ],
                          ),
                        ],
                      ),
                      
                      SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                      
                      // ✅ 2줄: 제목
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 제목
                          Expanded(
                            child: Text(
                              to.title,
                              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[900],
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          
                          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                          
                          
                        ],
                      ),
                      
                      // ✨ 장기 TO인 경우 기간 정보
                      if (to.isLongTerm) ...[
                        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                        Container(
                          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 6)),
                                decoration: BoxDecoration(
                                  color: Colors.purple[100],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.calendar_month,
                                  size: ResponsiveHelper.iconSize(context, 14),
                                  color: Colors.purple[700],
                                ),
                              ),
                              SizedBox(width: ResponsiveHelper.spacing(context, 10)),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      to.longTermPeriodWithDays,
                                      style: ResponsiveHelper.smallStyle(
                                        context,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (to.workDays != null && to.workDays!.isNotEmpty) ...[
                                      SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                                      Text(
                                        to.workDaysLabel,
                                        style: ResponsiveHelper.tinyStyle(
                                          context,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      
                      SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                                                // 마감시간 배지
                     _buildDeadlineBadge(context, to),
                      SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                      
                      // ✅ 3줄: 확정 + 대기 + 화살표
                      Row(
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
                                  '${widget.toItem.confirmedCount}/${widget.toItem.totalRequired}',
                                  style: ResponsiveHelper.bodyStyle(
                                    context,
                                    color: isFull ? Colors.green[700] : theme.primaryColor,
                                  ).copyWith(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                          
                          if (widget.toItem.pendingCount > 0) ...[
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
                                    '${widget.toItem.pendingCount}',
                                    style: ResponsiveHelper.bodyStyle(
                                      context,
                                      color: Colors.orange[700],
                                    ).copyWith(fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          
                          const Spacer(),

                          // 화살표
                          Icon(
                            widget.isExpanded ? Icons.expand_less : Icons.expand_more,
                            size: ResponsiveHelper.iconSize(context, 24),
                            color: theme.primaryColor,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            // 펼쳐진 경우: 업무 상세
            if (widget.isExpanded) ...[
              Divider(height: 1, color: Colors.grey[200]),
              Container(
                padding: ResponsiveHelper.cardPadding(context),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
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
                            size: ResponsiveHelper.iconSize(context, 14),
                            color: theme.primaryColor,
                          ),
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                        Text(
                          '업무 상세',
                          style: ResponsiveHelper.bodyStyle(context).copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 12)),
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
      ),
    );
  }

  /// ✨ 상태 배지
  Widget _buildStatusBadge(BuildContext context, bool isFull) {
    final allWorksClosed = widget.toItem.workDetails.every((work) => 
      work.isClosed || work.isTimeExpired || work.isFull
    );
    
    IconData icon;
    String label;
    Color color;

    if (allWorksClosed) {
      icon = Icons.lock;
      label = '마감';
      color = Colors.grey[600]!;
    } else if (isFull) {
      icon = Icons.check_circle;
      label = '충족';
      color = Colors.green[600]!;
    } else {
      icon = Icons.circle;
      label = '진행';
      color = Theme.of(context).primaryColor;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 5),
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.2),
            color.withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.5), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: ResponsiveHelper.iconSize(context, 12),
            color: color,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Text(
            label,
            style: ResponsiveHelper.tinyStyle(
              context,
              color: color,
            ).copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  /// 마감시간 배지
  Widget _buildDeadlineBadge(BuildContext context, to) {
    String label;
    if (to.deadlineType == 'FIXED_TIME') {
      label = '마감 ${DateFormat('MM/dd HH:mm').format(to.applicationDeadline)}';
    } else if (to.deadlineType == 'HOURS_BEFORE' && to.hoursBeforeStart != null) {
      label = '마감 업무${to.hoursBeforeStart}시간 전';
    } else {
      return const SizedBox.shrink();
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 10),
        vertical: ResponsiveHelper.spacing(context, 6),
      ),
      decoration: BoxDecoration(
        color: Colors.orange[100],
        borderRadius: BorderRadius.circular(10),
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

  /// 팝업 메뉴
  Widget _buildPopupMenu(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert,
        size: ResponsiveHelper.iconSize(context, 18),
        color: Theme.of(context).primaryColor,
      ),
      padding: EdgeInsets.zero,
      tooltip: '메뉴',
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      onSelected: (value) => _handleMenuAction(context, value),
      itemBuilder: (context) => [
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
        PopupMenuItem(
          value: 'unlink',
          child: Row(
            children: [
              Icon(
                Icons.link_off,
                size: ResponsiveHelper.iconSize(context, 18),
                color: Colors.blue[600],
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
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