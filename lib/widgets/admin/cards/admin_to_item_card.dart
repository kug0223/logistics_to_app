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

// Theme
import '../../../theme/app_colors.dart';

// Screens
import '../../../screens/business_admin/to_management/edit_to_screen.dart';
import '../../../screens/common/job_posting_screen.dart';

// Dialogs
import '../../../screens/business_admin/dialogs/confirmed_list_dialog.dart';
import '../../../screens/business_admin/dialogs/work_detail_management_dialog.dart';
import '../../../screens/business_admin/dialogs/to_list_dialogs.dart';

// Local Widgets
import 'admin_work_detail.dart';

/// ✨ TO 아이템 카드 (그룹 내 개별 TO - 간소화된 디자인)
/// 
/// 개선 사항:
/// - 좌측 연결선으로 그룹 소속 표시
/// - 정보 간소화 (날짜 + 인원만)
/// - 배지 최소화
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
    final theme = Theme.of(context);
    
    // 인원 계산
    int confirmed = 0;
    int pending = 0;
    int required = 0;
    
    for (var work in widget.toItem.workDetails) {
      final stats = widget.toItem.workDetailStats?[work.workType];
      confirmed += (stats?['confirmed'] ?? 0) as int;
      pending += (stats?['pending'] ?? 0) as int;
      required += work.requiredCount;
    }
    
    final isFull = confirmed >= required && required > 0;
    
    // 전체 마감 여부
    final allClosed = widget.toItem.workDetails.every((work) =>
        work.isClosed || work.isTimeExpired || work.isFull);

    // 상태별 컬러
    Color statusColor;
    if (allClosed) {
      statusColor = AppColors.grey400;
    } else if (isFull) {
      statusColor = AppColors.success;
    } else {
      statusColor = theme.primaryColor;
    }

    return Container(
      margin: EdgeInsets.only(
        bottom: ResponsiveHelper.spacing(context, 8),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ✨ 좌측 연결선 (그룹 소속 표시)
            Column(
              children: [
                // 상단 연결선
                Container(
                  width: 2,
                  height: ResponsiveHelper.spacing(context, 8),
                  color: AppColors.grey300,
                ),
                // 연결 점
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                // 하단 연결선
                Expanded(
                  child: Container(
                    width: 2,
                    color: AppColors.grey300,
                  ),
                ),
              ],
            ),
            
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            
            // ✨ 메인 카드
            Expanded(
              child: Container(
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
                              // ✨ 1줄: 날짜 + 제목 (전체 표시)
                              Row(
                                children: [
                                  // 날짜 배지
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: ResponsiveHelper.spacing(context, 8),
                                      vertical: ResponsiveHelper.spacing(context, 4),
                                    ),
                                    decoration: BoxDecoration(
                                      color: theme.primaryColor.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      FormatHelper.formatDate(to.date),
                                      style: ResponsiveHelper.smallStyle(
                                        context,
                                        color: theme.primaryColor,
                                      ).copyWith(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  SizedBox(width: ResponsiveHelper.spacing(context, 10)),
                                  // 제목 (전체 표시)
                                  Expanded(
                                    child: Text(
                                      to.title,
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
                                  
                                  // 마감 표시
                                  if (allClosed) ...[
                                    _buildClosedBadge(context),
                                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                                  ],
                                  
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
                      
                      // ✨ 펼쳐진 경우: 업무 상세
                      if (widget.isExpanded) ...[
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
                          child: Column(
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
                                final stats = widget.toItem.workDetailStats?[work.workType];
                                final workConfirmed = stats?['confirmed'] ?? 0;
                                final workPending = stats?['pending'] ?? 0;

                                return WorkDetailRow(
                                  work: work,
                                  confirmedCount: workConfirmed,
                                  pendingCount: workPending,
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
              ),
            ),
          ],
        ),
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

  /// ✨ 마감 배지 (간소화)
  Widget _buildClosedBadge(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 6),
        vertical: ResponsiveHelper.spacing(context, 3),
      ),
      decoration: BoxDecoration(
        color: AppColors.grey100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock,
            size: ResponsiveHelper.iconSize(context, 10),
            color: AppColors.grey600,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 2)),
          Text(
            '마감',
            style: ResponsiveHelper.tinyStyle(
              context,
              color: AppColors.grey600,
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
        size: ResponsiveHelper.iconSize(context, 18),
        color: AppColors.grey600,
      ),
      padding: EdgeInsets.zero,
      tooltip: '메뉴',
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      onSelected: (value) => _handleMenuAction(context, value),
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
              const Text('공고 상세보기'),
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
        PopupMenuItem(
          value: 'unlink',
          child: Row(
            children: [
              Icon(
                Icons.link_off,
                size: ResponsiveHelper.iconSize(context, 18),
                color: AppColors.info,
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

  /// 메뉴 액션 처리
  Future<void> _handleMenuAction(BuildContext context, String value) async {
    switch (value) {
      case 'preview':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => JobPostingScreen(
              to: widget.toItem.to,
              workDetails: widget.toItem.workDetails,
              mode: TODetailMode.adminPreview,
            ),
          ),
        );
        break;
        
      case 'edit':
        await NavigationHelper.push<bool>(
          context,
          destination: AdminEditTOScreen(to: widget.toItem.to),
          onReturn: (result) {
            if (result == true) {
              widget.firestoreService.clearCache();
              widget.onChanged();
            }
          },
        );
        break;
        
      case 'delete':
        widget.dialogs.showDeleteTODialog(widget.toItem);
        break;
        
      case 'unlink':
        widget.dialogs.showRemoveFromGroupDialog(widget.toItem);
        break;
        
      case 'confirmedList':
        ConfirmedListDialog(
          context: context,
          toItem: widget.toItem,
          firestoreService: widget.firestoreService,
        ).show();
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
}