import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../models/core/work_detail_model.dart';
import '../../../services/firestore_service.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/dialog_helper.dart';
import '../../../widgets/work_type_icon.dart';
import '../../../widgets/dialogs/styled_dialog.dart';
import '../../../models/ui/admin_to_list_ui_models.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/common/app_checkbox.dart';

abstract class _WDS {
  static const String active      = 'ACTIVE';
  static const String closed      = 'CLOSED';
  static const String timeExpired = 'TIME_EXPIRED';
  static const String full        = 'FULL';
  static const String emergency   = 'EMERGENCY';
}

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
          // 선택된 상태 확인
          final firstSelected = selectedWorkDetails.isNotEmpty
              ? toItem.workDetails
                  .where((w) => selectedWorkDetails.contains(w.id))
                  .firstOrNull
              : null;
          if (firstSelected != null) {
            final stats = toItem.workDetailStats?[firstSelected.id];
            final confirmed = stats?['confirmed'] ?? 0;
            selectedStatus = _getWorkStatus(firstSelected, confirmed);
          } else {
            selectedWorkDetails.clear();
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
            fillHeight: true,
            content: SingleChildScrollView(
              padding: ResponsiveHelper.cardPadding(context),
              child: Column(
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
                  final stats = toItem.workDetailStats?[work.id];
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
        color: theme.primaryColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.primaryColor.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          AppCheckbox(
            value: allSelected,
            onTap: () => setDialogState(() {
              if (!allSelected) {
                selectedWorkDetails.addAll(selectableWorks.map((w) => w.id));
              } else {
                selectedWorkDetails.clear();
              }
            }),
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
              color: theme.primaryColor.withValues(alpha: 0.1),
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
                  ? statusInfo['color'].withValues(alpha: 0.1)
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
                // 체크박스 (행 InkWell이 탭 처리)
                AppCheckbox(
                  value: isSelected,
                  enabled: isSelectable,
                  activeColor: statusInfo['color'],
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
                              color: statusInfo['color'].withValues(alpha: 0.15),
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
      case _WDS.active:
        return StyledDialogButton.primary(
          text: '${selectedWorks.length}개 마감',
          backgroundColor: AppColors.warning,
          onPressed: () => _handleBulkClose(selectedWorks),
        );

      case _WDS.closed:
        return StyledDialogButton.primary(
          text: '${selectedWorks.length}개 재오픈',
          backgroundColor: AppColors.success,
          onPressed: () => _handleBulkReopen(selectedWorks),
        );

      case _WDS.timeExpired:
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

      case _WDS.full:
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

      case _WDS.emergency:
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
      case _WDS.timeExpired:
        return {'label': '시간만료', 'color': AppColors.grey500, 'icon': Icons.schedule};
      case _WDS.closed:
        return {'label': '마감', 'color': AppColors.grey600, 'icon': Icons.lock};
      case _WDS.emergency:
        return {'label': '긴급모집', 'color': AppColors.error, 'icon': Icons.warning};
      case _WDS.full:
        return {'label': '인원충족', 'color': AppColors.success, 'icon': Icons.check_circle};
      case _WDS.active:
      default:
        return {'label': '진행중', 'color': AppColors.info, 'icon': Icons.play_circle};
    }
  }

  String _getWorkStatus(WorkDetailModel work, int confirmed) {
    if (work.isTimeExpired) return _WDS.timeExpired;
    if (work.isClosed) return _WDS.closed;

    // CF가 슬롯 status='closed'를 기록했어도 in-memory workDetail.closedAt은
    // 아직 반영 안 된 경우(stale 캐시) → 슬롯 상태로 보정
    // isEffectivelyClosed = isManualClosed || status=='closed' || isDatePast
    final slot = toItem.slot;
    if (slot != null && slot.isEffectivelyClosed && !work.isEmergencyOpen) {
      if (slot.isManualClosed) return _WDS.closed;
      if (slot.isFull) return _WDS.full;   // 인원충족 마감 — timeExpired와 구분
      return _WDS.timeExpired;
    }

    if (work.isEmergencyOpen) return _WDS.emergency;
    if (confirmed >= work.requiredCount) return _WDS.full;
    return _WDS.active;
  }

  // 일괄 마감
  Future<void> _handleBulkClose(List<WorkDetailModel> works) async {
    final confirm = await DialogHelper.showConfirm(
      context,
      title: '업무 마감',
      message: '${works.length}개 업무를 마감하시겠습니까?',
      confirmText: '마감',
      confirmColor: AppColors.warning,
    );

    if (!context.mounted || !confirm) return;
    {
      final adminUID = FirebaseAuth.instance.currentUser?.uid;
      if (adminUID == null) {
        ToastHelper.showError('로그인 정보를 찾을 수 없습니다');
        return;
      }
      final now = DateTime.now();
      try {
        for (var work in works) {
          await firestoreService.closeWorkDetail(
            toId: toItem.to.id,
            workDetailId: work.id,
            adminUID: adminUID,
            slotId: toItem.slot?.id,
          );
          if (!context.mounted) return;

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

        if (!context.mounted) return;
        Navigator.pop(context);
        onLocalStatsChanged?.call();
        onComplete();
        ToastHelper.showSuccess('${works.length}개 업무가 마감되었습니다');
      } catch (e) {
        if (context.mounted) ToastHelper.showError('일부 업무 마감에 실패했습니다');
      }
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

    if (!context.mounted || !confirm) return;
    {
      final adminUID = FirebaseAuth.instance.currentUser?.uid;
      if (adminUID == null) {
        ToastHelper.showError('로그인 정보를 찾을 수 없습니다');
        return;
      }
      try {
        for (var work in works) {
          await firestoreService.reopenWorkDetail(
            toId: toItem.to.id,
            workDetailId: work.id,
            adminUID: adminUID,
            slotId: toItem.slot?.id,
          );
          if (!context.mounted) return;

          // ⭐ 로컬 데이터 업데이트 (clearClosedAt 사용)
          final index = toItem.workDetails.indexWhere((w) => w.id == work.id);
          if (index != -1) {
            toItem.workDetails[index] = work.copyWith(clearClosedAt: true);
          }
        }

        if (!context.mounted) return;
        Navigator.pop(context);
        onLocalStatsChanged?.call();
        onComplete();
        ToastHelper.showSuccess('${works.length}개 업무가 재오픈되었습니다');
      } catch (e) {
        if (context.mounted) ToastHelper.showError('일부 업무 재오픈에 실패했습니다');
      }
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

    if (!context.mounted || !confirm) return;
    {
      final adminUID = FirebaseAuth.instance.currentUser?.uid;
      if (adminUID == null) {
        ToastHelper.showError('로그인 정보를 찾을 수 없습니다');
        return;
      }
      try {
        for (var work in works) {
          await firestoreService.stopEmergencyRecruitment(
            toId: toItem.to.id,
            workDetailId: work.id,
            adminUID: adminUID,
            slotId: toItem.slot?.id,
          );
          if (!context.mounted) return;

          // ⭐ 로컬 데이터 업데이트 (clearEmergency 사용)
          final index = toItem.workDetails.indexWhere((w) => w.id == work.id);
          if (index != -1) {
            toItem.workDetails[index] = work.copyWith(clearEmergency: true);
          }
        }

        if (!context.mounted) return;
        Navigator.pop(context);
        onLocalStatsChanged?.call();
        ToastHelper.showSuccess('${works.length}개 업무 긴급모집이 종료되었습니다');
      } catch (e) {
        if (context.mounted) ToastHelper.showError('일부 긴급모집 종료에 실패했습니다');
      }
    }
  }
}