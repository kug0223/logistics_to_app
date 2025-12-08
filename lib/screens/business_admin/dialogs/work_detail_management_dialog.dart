import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../models/core/work_detail_model.dart';
import '../../../services/firestore_service.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/dialog_helper.dart';
import '../../../widgets/work_type_icon.dart';
import '../../../widgets/dialogs/styled_dialog.dart';
import '../../../models/ui/admin_to_list_ui_models.dart';
import '../../../theme/app_colors.dart';

class WorkDetailManagementDialog {
  final BuildContext context;
  final TOItem toItem;
  final FirestoreService firestoreService;
  final VoidCallback onComplete;
  final VoidCallback? onLocalStatsChanged;

  WorkDetailManagementDialog({
    required this.context,
    required this.toItem,
    required this.firestoreService,
    required this.onComplete,
    this.onLocalStatsChanged,
  });

  void show() {
    final selectedWorkDetails = <String>{};
    String? selectedStatus;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = Theme.of(context);
          
          // 선택된 상태 확인
          if (selectedWorkDetails.isNotEmpty) {
            final firstSelected = toItem.workDetails.firstWhere(
              (w) => selectedWorkDetails.contains(w.id),
            );
            final stats = toItem.workDetailStats?[firstSelected.id];
            final confirmed = stats?['confirmed'] ?? 0;
            selectedStatus = _getWorkStatus(firstSelected, confirmed);
          } else {
            selectedStatus = null;
          }

          // 선택 가능한 업무들
          final selectableWorks = toItem.workDetails.where((work) {
            if (selectedStatus == null) return true;
            final stats = toItem.workDetailStats?[work.id];
            final confirmed = stats?['confirmed'] ?? 0;
            final workStatus = _getWorkStatus(work, confirmed);
            return workStatus == selectedStatus;
          }).toList();

          final allSelectableSelected = selectableWorks.isNotEmpty &&
              selectableWorks.every((w) => selectedWorkDetails.contains(w.id));

          return StyledDialog(
            title: '업무별 마감 관리',
            subtitle: toItem.to.title,
            icon: Icons.task_alt,
            headerColor: AppColors.purple,
            maxHeightRatio: 0.85,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 전체 선택 체크박스
                _buildSelectAllCard(
                  context,
                  allSelectableSelected,
                  selectedStatus,
                  selectableWorks,
                  selectedWorkDetails,
                  setDialogState,
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),

                // 업무 목록
                ...toItem.workDetails.map((work) {
                  final stats = toItem.workDetailStats?[work.workType];
                  final confirmed = stats?['confirmed'] ?? 0;
                  final pending = stats?['pending'] ?? 0;
                  final workStatus = _getWorkStatus(work, confirmed);
                  final isSelectable = selectedStatus == null || workStatus == selectedStatus;
                  final isSelected = selectedWorkDetails.contains(work.id);

                  return _buildWorkCard(
                    context,
                    work,
                    confirmed,
                    pending,
                    workStatus,
                    isSelectable,
                    isSelected,
                    selectedWorkDetails,
                    setDialogState,
                  );
                }),
              ],
            ),
            actions: [
              StyledDialogButton.cancel(
                onPressed: () => Navigator.pop(context),
              ),
              if (selectedWorkDetails.isNotEmpty && selectedStatus != null)
                _buildActionButton(context, selectedStatus!, selectedWorkDetails),
            ],
          );
        },
      ),
    );
  }

  // ✨ 전체 선택 카드
  Widget _buildSelectAllCard(
    BuildContext context,
    bool allSelected,
    String? selectedStatus,
    List<WorkDetailModel> selectableWorks,
    Set<String> selectedWorkDetails,
    StateSetter setDialogState,
  ) {
    final theme = Theme.of(context);
    
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: theme.primaryColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.primaryColor.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Checkbox(
            value: allSelected,
            onChanged: (value) {
              setDialogState(() {
                if (value == true) {
                  selectedWorkDetails.addAll(selectableWorks.map((w) => w.id));
                } else {
                  selectedWorkDetails.clear();
                }
              });
            },
            activeColor: theme.primaryColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Expanded(
            child: Text(
              '전체 선택',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 12),
              vertical: ResponsiveHelper.spacing(context, 4),
            ),
            decoration: BoxDecoration(
              color: theme.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              '${selectedWorkDetails.length}/${toItem.workDetails.length}개 선택',
              style: ResponsiveHelper.smallStyle(
                context,
                color: theme.primaryColor,
              ).copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // ✨ 업무 카드
  Widget _buildWorkCard(
    BuildContext context,
    WorkDetailModel work,
    int confirmed,
    int pending,
    String workStatus,
    bool isSelectable,
    bool isSelected,
    Set<String> selectedWorkDetails,
    StateSetter setDialogState,
  ) {
    final statusInfo = _getStatusInfo(workStatus);

    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isSelectable
              ? () {
                  setDialogState(() {
                    if (isSelected) {
                      selectedWorkDetails.remove(work.id);
                    } else {
                      selectedWorkDetails.add(work.id);
                    }
                  });
                }
              : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: ResponsiveHelper.cardPadding(context),
            decoration: BoxDecoration(
              color: isSelected
                  ? statusInfo['color'].withOpacity(0.1)
                  : (isSelectable ? Colors.white : AppColors.grey50),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? statusInfo['color']
                    : (isSelectable ? AppColors.border : AppColors.grey200),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                // 체크박스
                Checkbox(
                  value: isSelected,
                  onChanged: isSelectable
                      ? (value) {
                          setDialogState(() {
                            if (value == true) {
                              selectedWorkDetails.add(work.id);
                            } else {
                              selectedWorkDetails.remove(work.id);
                            }
                          });
                        }
                      : null,
                  activeColor: statusInfo['color'],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                
                // 업무 아이콘
                WorkTypeIcon.buildWithBackground(
                  iconString: work.workTypeIcon,
                  backgroundColor: work.workTypeBackgroundColor,
                  size: ResponsiveHelper.iconSize(context, 36),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                
                // 업무 정보
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              work.workType,
                              style: ResponsiveHelper.bodyStyle(context).copyWith(
                                fontWeight: FontWeight.bold,
                                color: isSelectable ? AppColors.textPrimary : AppColors.grey500,
                              ),
                            ),
                          ),
                          // 상태 배지
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: ResponsiveHelper.spacing(context, 8),
                              vertical: ResponsiveHelper.spacing(context, 2),
                            ),
                            decoration: BoxDecoration(
                              color: statusInfo['color'].withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  statusInfo['icon'],
                                  size: ResponsiveHelper.iconSize(context, 12),
                                  color: statusInfo['color'],
                                ),
                                SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                                Text(
                                  statusInfo['label'],
                                  style: ResponsiveHelper.tinyStyle(
                                    context,
                                    color: statusInfo['color'],
                                  ).copyWith(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                      // 시간
                      Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: ResponsiveHelper.iconSize(context, 14),
                            color: AppColors.grey500,
                          ),
                          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                          Text(
                            '${work.startTime} ~ ${work.endTime}',
                            style: ResponsiveHelper.smallStyle(
                              context,
                              color: AppColors.grey600,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                      // 인원
                      Row(
                        children: [
                          Icon(
                            Icons.people,
                            size: ResponsiveHelper.iconSize(context, 14),
                            color: AppColors.grey500,
                          ),
                          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                          Text(
                            '$confirmed/${work.requiredCount}명',
                            style: ResponsiveHelper.smallStyle(
                              context,
                              color: confirmed >= work.requiredCount
                                  ? AppColors.success
                                  : AppColors.grey600,
                            ).copyWith(fontWeight: FontWeight.w600),
                          ),
                          if (pending > 0) ...[
                            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                            Text(
                              '(대기 $pending명)',
                              style: ResponsiveHelper.tinyStyle(
                                context,
                                color: AppColors.warning,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ✨ 액션 버튼
  Widget _buildActionButton(BuildContext context, String status, Set<String> selectedIds) {
    final selectedWorks = toItem.workDetails
        .where((w) => selectedIds.contains(w.id))
        .toList();

    switch (status) {
      case 'ACTIVE':
        return StyledDialogButton.primary(
          text: '${selectedWorks.length}개 마감',
          backgroundColor: AppColors.error,
          onPressed: () => _handleBulkClose(selectedWorks),
        );

      case 'CLOSED':
        return StyledDialogButton.primary(
          text: '${selectedWorks.length}개 재오픈',
          backgroundColor: AppColors.success,
          onPressed: () => _handleBulkReopen(selectedWorks),
        );

      case 'TIME_EXPIRED':
        return StyledDialogButton.primary(
          text: '시간 만료',
          backgroundColor: AppColors.grey400,
          onPressed: () {
            DialogHelper.showInfo(
              context,
              title: '알림',
              message: '시간이 지난 업무는 수정할 수 없습니다.',
            );
          },
        );

      case 'FULL':
        return StyledDialogButton.primary(
          text: '${selectedWorks.length}개 인원충족',
          backgroundColor: AppColors.success,
          onPressed: () {
            DialogHelper.showInfo(
              context,
              title: '알림',
              message: '인원이 충족된 업무입니다.\n추가 인원이 필요하면 모집인원을 늘려주세요.',
            );
          },
        );

      case 'EMERGENCY':
        return StyledDialogButton.primary(
          text: '긴급모집 종료',
          backgroundColor: AppColors.warning,
          onPressed: () => _handleBulkStopEmergency(selectedWorks),
        );

      default:
        return const SizedBox.shrink();
    }
  }

  // 상태 정보
  Map<String, dynamic> _getStatusInfo(String status) {
    switch (status) {
      case 'TIME_EXPIRED':
        return {'label': '시간만료', 'color': AppColors.grey500, 'icon': Icons.schedule};
      case 'CLOSED':
        return {'label': '마감됨', 'color': AppColors.grey600, 'icon': Icons.lock};
      case 'EMERGENCY':
        return {'label': '긴급모집', 'color': AppColors.error, 'icon': Icons.warning};
      case 'FULL':
        return {'label': '인원충족', 'color': AppColors.success, 'icon': Icons.check_circle};
      case 'ACTIVE':
      default:
        return {'label': '진행중', 'color': AppColors.info, 'icon': Icons.play_circle};
    }
  }

  String _getWorkStatus(WorkDetailModel work, int confirmed) {
    if (work.isTimeExpired) return 'TIME_EXPIRED';
    if (work.isClosed) return 'CLOSED';
    if (work.isEmergencyOpen) return 'EMERGENCY';
    if (confirmed >= work.requiredCount) return 'FULL';
    return 'ACTIVE';
  }

  // 일괄 마감
  Future<void> _handleBulkClose(List<WorkDetailModel> works) async {
    final confirm = await DialogHelper.showConfirm(
      context,
      title: '업무 마감',
      message: '${works.length}개 업무를 마감하시겠습니까?',
      confirmText: '마감',
      confirmColor: AppColors.error,
    );

    if (confirm) {
      final adminUID = FirebaseAuth.instance.currentUser!.uid;
      final now = DateTime.now();
      
      for (var work in works) {
        await firestoreService.closeWorkDetail(
          toId: toItem.to.id,
          workDetailId: work.id,
          adminUID: adminUID,
        );
        
        // ⭐ 로컬 데이터 업데이트
        final index = toItem.workDetails.indexWhere((w) => w.id == work.id);
        if (index != -1) {
          toItem.workDetails[index] = work.copyWith(
            closedAt: now,
            closedBy: adminUID,
            isManualClosed: true,
          );
        }
      }

      Navigator.pop(context);
      onLocalStatsChanged?.call();
      ToastHelper.showSuccess('${works.length}개 업무가 마감되었습니다');
    }
  }

  // 일괄 재오픈
  Future<void> _handleBulkReopen(List<WorkDetailModel> works) async {
    final confirm = await DialogHelper.showConfirm(
      context,
      title: '업무 재오픈',
      message: '${works.length}개 업무를 다시 오픈하시겠습니까?',
      confirmText: '재오픈',
      confirmColor: AppColors.success,
    );

    if (confirm) {
      final adminUID = FirebaseAuth.instance.currentUser!.uid;
      
      for (var work in works) {
        await firestoreService.reopenWorkDetail(
          toId: toItem.to.id,
          workDetailId: work.id,
          adminUID: adminUID,
        );
        
        // ⭐ 로컬 데이터 업데이트 (clearClosedAt 사용)
        final index = toItem.workDetails.indexWhere((w) => w.id == work.id);
        if (index != -1) {
          toItem.workDetails[index] = work.copyWith(clearClosedAt: true);
        }
      }

      Navigator.pop(context);
      onLocalStatsChanged?.call();
      ToastHelper.showSuccess('${works.length}개 업무가 재오픈되었습니다');
    }
  }

  // 긴급모집 종료
  Future<void> _handleBulkStopEmergency(List<WorkDetailModel> works) async {
    final confirm = await DialogHelper.showConfirm(
      context,
      title: '긴급모집 종료',
      message: '${works.length}개 업무의 긴급모집을 종료하시겠습니까?',
      confirmText: '종료',
      confirmColor: AppColors.warning,
    );

    if (confirm) {
      final adminUID = FirebaseAuth.instance.currentUser!.uid;
      
      for (var work in works) {
        await firestoreService.stopEmergencyRecruitment(
          toId: toItem.to.id,
          workDetailId: work.id,
          adminUID: adminUID,
        );
        
        // ⭐ 로컬 데이터 업데이트 (clearEmergency 사용)
        final index = toItem.workDetails.indexWhere((w) => w.id == work.id);
        if (index != -1) {
          toItem.workDetails[index] = work.copyWith(clearEmergency: true);
        }
      }

      Navigator.pop(context);
      onLocalStatsChanged?.call();
      ToastHelper.showSuccess('${works.length}개 업무 긴급모집이 종료되었습니다');
    }
  }
}