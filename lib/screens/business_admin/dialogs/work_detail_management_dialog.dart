import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../../../providers/user_provider.dart';

import '../../../models/core/work_detail_model.dart';
import '../../../services/firestore_service.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/dialog_helper.dart';
import '../../../widgets/work_type_icon.dart';
import '../../../widgets/dialogs/styled_dialog.dart';
import '../../../models/ui/admin_to_list_ui_models.dart';
import '../../../models/ui/work_capacity_reading.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/common/app_checkbox.dart';

abstract class _WDS {
  static const String active      = 'ACTIVE';
  static const String closed      = 'CLOSED';
  static const String timeExpired = 'TIME_EXPIRED';
  static const String full        = 'FULL';
  static const String emergency   = 'EMERGENCY';

  /// [R7-4 C3] 정원을 **모르는** 상태. 확정 0명과 다르다.
  ///
  ///   예전에는 통계 조회가 빗나가면 `confirmed = 0` 으로 접고 곧바로
  ///   `진행중`이라고 적었다. 정원이 이미 찬 업무가 `0/2 · 진행중`으로
  ///   보였고, 그 상태로 `N개 마감` 버튼까지 열렸다. 모르는 것은
  ///   모른다고 말하고, 그 값에 기대는 판단만 멈춘다.
  static const String unknown     = 'UNKNOWN';
}

class WorkDetailManagementDialog {
  final BuildContext context;
  final TOItem toItem;
  final FirestoreService firestoreService;
  final VoidCallback onComplete;
  final VoidCallback? onLocalStatsChanged;

  bool _isProcessing = false;

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

    // [SYSTEM-INTEGRATION-R2.4.1 §4] 인원 현황을 못 읽었으면 마감 결정을 시키지 않는다.
    //
    //   이 화면은 `$confirmed/${work.requiredCount}명`을 보여 주면서 같은 자리에서
    //   일괄 마감·재개·긴급모집을 실행한다. 통계 조회가 실패하면 confirmed가
    //   0으로 떨어져 `0/3`이 되고, 실제로는 3명이 확정된 업무를 관리자가
    //   `아무도 안 왔다`고 보고 마감할 수 있었다.
    //
    //   ERROR != ZERO. 읽지 못한 것은 0이 아니다.
    if (toItem.workDetailStatsFailed) {
      DialogHelper.showAlert(
        context,
        title: '인원 현황을 불러오지 못했어요',
        message: '지금 인원 수를 확인할 수 없어 업무를 마감하거나 재개할 수 없어요.\n'
            '새로고침 후 다시 시도해 주세요.',
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // 선택된 상태 확인
          final firstSelected = selectedWorkDetails.isNotEmpty
              ? toItem.workDetails
                  .where((w) => selectedWorkDetails.contains(w.id))
                  .firstOrNull
              : null;
          if (firstSelected != null) {
            selectedStatus = _getWorkStatus(firstSelected, _readingOf(firstSelected));
          } else {
            selectedWorkDetails.clear();
            selectedStatus = null;
          }

          // 선택 가능한 업무들
          final selectableWorks = toItem.workDetails.where((work) {
            if (selectedStatus == null) return true;
            final workStatus = _getWorkStatus(work, _readingOf(work));
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
                  final reading = _readingOf(work);
                  final workStatus = _getWorkStatus(work, reading);
                  final isSelectable = selectedStatus == null || workStatus == selectedStatus;
                  final isSelected = selectedWorkDetails.contains(work.id);

                  return _buildWorkCard(
                    context,
                    work,
                    reading,
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
    WorkCapacityReading reading,
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
                            // [R7-4 C3] 모르는 확정 수를 0 으로 적지 않는다.
                            //   필요 인원은 업무 정의라 언제나 말할 수 있다.
                            reading.isKnown
                                ? '${reading.confirmed}/${work.requiredCount}명'
                                : '확정 ?/${work.requiredCount}명',
                            style: ResponsiveHelper.smallStyle(
                              context,
                              color: !reading.isKnown
                                  ? AppColors.grey500
                                  : reading.isFull
                                      ? AppColors.success
                                      : AppColors.grey600,
                            ).copyWith(fontWeight: FontWeight.w600),
                          ),
                          if ((reading.pending ?? 0) > 0) ...[
                            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                            Text(
                              '(대기 ${reading.pending}명)',
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

      // [R7-4 C3] 정원을 모르는 업무에는 정원에 기대는 action 을 열지 않는다.
      //
      //   마감·재오픈은 "지금 몇 명 찼는가"를 보고 하는 판단이다. 그 값을
      //   모르는 채로 버튼을 열면, 모른다는 사실이 아니라 0 이라는 오답을
      //   근거로 누르게 된다. 대신 왜 막혔고 어떻게 푸는지 말한다.
      case _WDS.unknown:
        return StyledDialogButton.primary(
          text: '정원 확인 필요',
          backgroundColor: AppColors.grey500,
          onPressed: () {
            DialogHelper.showInfo(
              context,
              title: '정원 정보를 불러오지 못했습니다',
              message: '이 업무의 확정 인원을 확인할 수 없어 마감·재오픈을 '
                  '진행하지 않습니다.\n\n'
                  '목록을 새로고침한 뒤 다시 시도해주세요. '
                  '정원을 확인할 수 있는 다른 업무는 그대로 관리할 수 있습니다.',
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
      // [R7-4 C3] 확정 0 과 구분되는 라벨. `진행중`으로 내려앉지 않는다.
      case _WDS.unknown:
        return {'label': '확인 필요', 'color': AppColors.grey500, 'icon': Icons.sync_problem};
      case _WDS.active:
      default:
        return {'label': '진행중', 'color': AppColors.info, 'icon': Icons.play_circle};
    }
  }

  /// [R7-4 C3] 이 다이얼로그가 정원을 읽는 **단 하나의 창구**.
  ///
  ///   `toItem.workDetailStatsFailed` 는 조회 실패라는 사실이고,
  ///   identity miss 는 `WorkCapacityReading` 안에서 걸러진다.
  WorkCapacityReading _readingOf(WorkDetailModel work) =>
      WorkCapacityReading.read(
        work,
        toItem.workDetailStats,
        statsFailed: toItem.workDetailStatsFailed,
      );

  /// [R7-4 C3] 정원 판독([reading])을 받는다.
  ///
  ///   시간만료·마감·긴급모집은 업무 정의만으로 정해지므로 통계와 무관하게
  ///   그대로 답한다. 통계가 필요한 것은 **인원충족인지 진행중인지** 하나뿐이고,
  ///   그것을 모를 때 진행중으로 내려앉지 않는 것이 이 수정의 전부다.
  String _getWorkStatus(WorkDetailModel work, WorkCapacityReading reading) {
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
    // 여기서부터는 정원 수치가 있어야 답할 수 있다.
    if (!reading.isKnown) return _WDS.unknown;
    if (reading.isFull) return _WDS.full;
    return _WDS.active;
  }

  // 일괄 마감
  Future<void> _handleBulkClose(List<WorkDetailModel> works) async {
    // TO-05: 업무별 마감 권한 확인
    if (context.read<UserProvider>().checkCurrentBusiness((p) => p.canManageTo) != PermissionCheck.allowed) {
      ToastHelper.showWarning('공고 관리 권한이 없습니다.');
      return;
    }
    if (_isProcessing) return;
    _isProcessing = true;
    try {
      final confirm = await DialogHelper.showConfirm(
        context,
        title: '업무 마감',
        message: '${works.length}개 업무를 마감하시겠습니까?',
        confirmText: '마감',
        confirmColor: AppColors.warning,
      );

      if (!context.mounted || !confirm) return;

      final adminUID = FirebaseAuth.instance.currentUser?.uid;
      if (adminUID == null) {
        ToastHelper.showError('로그인 정보를 찾을 수 없습니다');
        return;
      }
      final now = DateTime.now();
      try {
        await Future.wait(works.map((work) => firestoreService.closeWorkDetail(
          toId: toItem.to.id,
          workDetailId: work.id,
          adminUID: adminUID,
          slotId: toItem.slot?.id,
        )));
        if (!context.mounted) return;

        // ⭐ 로컬 데이터 일괄 업데이트
        for (final work in works) {
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
        debugPrint('❌ 업무 일괄 마감 실패: $e');
        if (context.mounted) {
          ToastHelper.showError('일부 업무 마감에 실패했습니다');
          // 성공한 항목이 있을 수 있으므로 부모 화면 갱신 후 닫기
          Navigator.pop(context);
          onLocalStatsChanged?.call();
          onComplete();
        }
      }
    } finally {
      _isProcessing = false;
    }
  }

  // 일괄 재오픈
  Future<void> _handleBulkReopen(List<WorkDetailModel> works) async {
    if (context.read<UserProvider>().checkCurrentBusiness((p) => p.canManageTo) != PermissionCheck.allowed) {
      ToastHelper.showWarning('공고 관리 권한이 없습니다.');
      return;
    }
    if (_isProcessing) return;
    _isProcessing = true;
    try {
      final confirm = await DialogHelper.showConfirm(
        context,
        title: '업무 재오픈',
        message: '${works.length}개 업무를 다시 오픈하시겠습니까?',
        confirmText: '재오픈',
        confirmColor: AppColors.success,
      );

      if (!context.mounted || !confirm) return;

      final adminUID = FirebaseAuth.instance.currentUser?.uid;
      if (adminUID == null) {
        ToastHelper.showError('로그인 정보를 찾을 수 없습니다');
        return;
      }
      try {
        await Future.wait(works.map((work) => firestoreService.reopenWorkDetail(
          toId: toItem.to.id,
          workDetailId: work.id,
          adminUID: adminUID,
          slotId: toItem.slot?.id,
        )));
        if (!context.mounted) return;

        // ⭐ 로컬 데이터 일괄 업데이트 (clearClosedAt 사용)
        for (final work in works) {
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
        debugPrint('❌ 업무 일괄 재오픈 실패: $e');
        if (context.mounted) ToastHelper.showError('일부 업무 재오픈에 실패했습니다');
        // 부분 성공된 변경사항을 부모 화면에 반영 (_handleBulkClose와 동일한 패턴)
        if (context.mounted) {
          Navigator.pop(context);
          onLocalStatsChanged?.call();
          onComplete();
        }
      }
    } finally {
      _isProcessing = false;
    }
  }

  // 긴급모집 종료
  Future<void> _handleBulkStopEmergency(List<WorkDetailModel> works) async {
    if (context.read<UserProvider>().checkCurrentBusiness((p) => p.canManageTo) != PermissionCheck.allowed) {
      ToastHelper.showWarning('공고 관리 권한이 없습니다.');
      return;
    }
    if (_isProcessing) return;
    _isProcessing = true;
    try {
      final confirm = await DialogHelper.showConfirm(
        context,
        title: '긴급모집 종료',
        message: '${works.length}개 업무의 긴급모집을 종료하시겠습니까?',
        confirmText: '종료',
        confirmColor: AppColors.warning,
      );

      if (!context.mounted || !confirm) return;

      final adminUID = FirebaseAuth.instance.currentUser?.uid;
      if (adminUID == null) {
        ToastHelper.showError('로그인 정보를 찾을 수 없습니다');
        return;
      }
      await Future.wait(works.map((work) => firestoreService.stopEmergencyRecruitment(
        toId: toItem.to.id,
        workDetailId: work.id,
        adminUID: adminUID,
        slotId: toItem.slot?.id,
      )));
      if (!context.mounted) return;

      // ⭐ 로컬 데이터 일괄 업데이트 (clearEmergency 사용)
      for (final work in works) {
        final index = toItem.workDetails.indexWhere((w) => w.id == work.id);
        if (index != -1) {
          toItem.workDetails[index] = work.copyWith(clearEmergency: true);
        }
      }

      if (!context.mounted) return;
      Navigator.pop(context);
      onLocalStatsChanged?.call();
      onComplete();
      ToastHelper.showSuccess('${works.length}개 업무 긴급모집이 종료되었습니다');
    } catch (e) {
      debugPrint('❌ 업무 일괄 긴급모집 종료 실패: $e');
      if (context.mounted) ToastHelper.showError('일부 긴급모집 종료에 실패했습니다');
      // 부분 성공된 변경사항을 부모 화면에 반영
      if (context.mounted) {
        Navigator.pop(context);
        onLocalStatsChanged?.call();
        onComplete();
      }
    } finally {
      _isProcessing = false;
    }
  }
}