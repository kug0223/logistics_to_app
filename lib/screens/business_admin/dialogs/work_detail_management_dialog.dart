import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../../../models/core/work_detail_model.dart';
import '../../../services/firestore_service.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/responsive_helper.dart';  // ⭐ 추가
import '../../../widgets/work_type_icon.dart';
import '../../../models/ui/admin_to_list_ui_models.dart';
import '../../../utils/dialog_helper.dart';

class WorkDetailManagementDialog {
  final BuildContext context;
  final TOItem toItem;
  final FirestoreService firestoreService;
  final VoidCallback onComplete;

  WorkDetailManagementDialog({
    required this.context,
    required this.toItem,
    required this.firestoreService,
    required this.onComplete,
  });

  void show() {
    final selectedWorkDetails = <String>{};
    String? selectedStatus;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // 선택된 상태 확인
          if (selectedWorkDetails.isNotEmpty) {
            final firstSelected = toItem.workDetails.firstWhere(
              (w) => selectedWorkDetails.contains(w.id)
            );
            final stats = toItem.workDetailStats?[firstSelected.workType];
            final confirmed = stats?['confirmed'] ?? 0;
            
            selectedStatus = _getWorkStatus(firstSelected, confirmed);
          } else {
            selectedStatus = null;
          }
          
          // 선택 가능한 업무들
          final selectableWorks = toItem.workDetails.where((work) {
            if (selectedStatus == null) return true;
            
            final stats = toItem.workDetailStats?[work.workType];
            final confirmed = stats?['confirmed'] ?? 0;
            final workStatus = _getWorkStatus(work, confirmed);
            
            return workStatus == selectedStatus;
          }).toList();
          
          final allSelectableSelected = selectableWorks.isNotEmpty &&
            selectableWorks.every((w) => selectedWorkDetails.contains(w.id));
          
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.task_alt, color: Colors.purple),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
                const Text('업무별 마감 관리'),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildSelectAllCheckbox(
                    allSelectableSelected,
                    selectedStatus,
                    selectableWorks,
                    selectedWorkDetails,
                    setDialogState,
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),  // ⭐ 변경
                  
                  ..._buildWorkDetailCards(
                    selectedWorkDetails,
                    selectedStatus,
                    setDialogState,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('닫기'),
              ),
              
              () {
                print('🔍 selectedWorkDetails: ${selectedWorkDetails.length}');
                print('🔍 selectedStatus: $selectedStatus');
                
                if (selectedWorkDetails.isNotEmpty && selectedStatus != null) {
                  print('✅ 버튼 표시해야 함!');
                  return _buildActionButton(selectedStatus!, selectedWorkDetails);
                } else {
                  print('❌ 버튼 표시 안 함');
                  return const SizedBox.shrink();
                }
              }(),
            ],
          );
        },
      ),
    );
  }

  // 전체 선택 체크박스
  Widget _buildSelectAllCheckbox(
    bool allSelected,
    String? selectedStatus,
    List<WorkDetailModel> selectableWorks,
    Set<String> selectedWorkDetails,
    StateSetter setState,
  ) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Checkbox(
            value: allSelected,
            onChanged: selectedStatus == null || selectableWorks.isNotEmpty
              ? (value) {
                  setState(() {
                    if (value == true) {
                      selectedWorkDetails.addAll(
                        selectableWorks.map((w) => w.id)
                      );
                    } else {
                      selectedWorkDetails.clear();
                    }
                  });
                }
              : null,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selectedStatus == null ? '전체 선택' : '같은 상태만 선택',
                  style: ResponsiveHelper.bodyStyle(context).copyWith(  // ⭐ 변경
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (selectedStatus != null)
                  Text(
                    _getStatusLabel(selectedStatus),
                    style: ResponsiveHelper.tinyStyle(  // ⭐ 변경
                      context,
                      color: _getStatusColor(selectedStatus),
                    ).copyWith(fontWeight: FontWeight.bold),
                  ),
              ],
            ),
          ),
          Text(
            '${selectedWorkDetails.length}/${selectedStatus == null ? toItem.workDetails.length : selectableWorks.length}개 선택',
            style: ResponsiveHelper.tinyStyle(  // ⭐ 변경
              context,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
        ],
      ),
    );
  }

  // 업무 카드들
  List<Widget> _buildWorkDetailCards(
    Set<String> selectedWorkDetails,
    String? selectedStatus,
    StateSetter setState,
  ) {
    return toItem.workDetails.map((work) {
      final stats = toItem.workDetailStats?[work.workType];
      final confirmed = stats?['confirmed'] ?? 0;
      final pending = stats?['pending'] ?? 0;
      final isSelected = selectedWorkDetails.contains(work.id);
      
      final workStatus = _getWorkStatus(work, confirmed);
      final isEnabled = selectedStatus == null || workStatus == selectedStatus;
      
      return Opacity(
        opacity: isEnabled ? 1.0 : 0.4,
        child: Container(
          margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
          padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
          decoration: BoxDecoration(
            color: isSelected 
                ? Theme.of(context).primaryColor.withOpacity(0.1)
                : Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected 
                ? Theme.of(context).primaryColor
                : isEnabled 
                  ? Theme.of(context).dividerColor
                  : Theme.of(context).disabledColor,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Checkbox(
                value: isSelected,
                onChanged: isEnabled 
                  ? (value) {
                      setState(() {
                        if (value == true) {
                          selectedWorkDetails.add(work.id);
                        } else {
                          selectedWorkDetails.remove(work.id);
                        }
                      });
                    }
                  : null,
              ),
              
              Container(
                width: ResponsiveHelper.iconSize(context, 32),  // ⭐ 변경
                height: ResponsiveHelper.iconSize(context, 32),  // ⭐ 변경
                decoration: BoxDecoration(
                  color: FormatHelper.parseColor(work.workTypeColor),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: WorkTypeIcon.buildFromString(
                    work.workTypeIcon,
                    color: Colors.white,
                    size: ResponsiveHelper.iconSize(context, 16),  // ⭐ 변경
                  ),
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),  // ⭐ 변경
              
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      work.workType,
                      style: ResponsiveHelper.bodyStyle(context).copyWith(  // ⭐ 변경
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 4)),  // ⭐ 변경
                    Text(
                      '${work.startTime}~${work.endTime} | ${NumberFormat('#,###').format(work.wage)}원',
                      style: ResponsiveHelper.tinyStyle(  // ⭐ 변경
                        context,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),
                  ],
                ),
              ),
              
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveHelper.spacing(context, 6),  // ⭐ 변경
                      vertical: ResponsiveHelper.spacing(context, 3),  // ⭐ 변경
                    ),
                    decoration: BoxDecoration(
                      color: _getStatusColor(workStatus).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _getStatusColor(workStatus),
                      ),
                    ),
                    child: Text(
                      _getStatusLabel(workStatus),
                      style: ResponsiveHelper.tinyStyle(  // ⭐ 변경
                        context,
                        color: _getStatusColor(workStatus),
                      ).copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 4)),  // ⭐ 변경
                  Text(
                    '확정 $confirmed/${work.requiredCount}명',
                    style: ResponsiveHelper.tinyStyle(  // ⭐ 변경
                      context,
                    ).copyWith(fontWeight: FontWeight.bold),
                  ),
                  if (pending > 0)
                    Text(
                      '대기 $pending명',
                      style: ResponsiveHelper.tinyStyle(  // ⭐ 변경
                        context,
                        color: Colors.orange,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  // 액션 버튼
  Widget _buildActionButton(String status, Set<String> selectedIds) {
    final selectedWorks = toItem.workDetails
        .where((w) => selectedIds.contains(w.id))
        .toList();
    
    print('🔍 _buildActionButton 호출: status=$status, count=${selectedWorks.length}');
    
    switch (status) {
      case 'ACTIVE':
        return ElevatedButton.icon(
          onPressed: () => _handleBulkClose(selectedWorks),
          icon: Icon(Icons.lock, size: ResponsiveHelper.iconSize(context, 16)),  // ⭐ 변경
          label: Text('${selectedWorks.length}개 마감'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
        );
        
      case 'CLOSED':
        return ElevatedButton.icon(
          onPressed: () => _handleBulkReopen(selectedWorks),
          icon: Icon(Icons.lock_open, size: ResponsiveHelper.iconSize(context, 16)),  // ⭐ 변경
          label: Text('${selectedWorks.length}개 재오픈'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
        );
      
      case 'TIME_EXPIRED':
        return ElevatedButton.icon(
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('알림'),
                content: const Text('시간이 지난 업무는 수정할 수 없습니다.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('확인'),
                  ),
                ],
              ),
            );
          },
          icon: Icon(Icons.schedule, size: ResponsiveHelper.iconSize(context, 16)),  // ⭐ 변경
          label: Text('시간 만료 (${selectedWorks.length})'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).disabledColor,
            foregroundColor: Colors.white,
          ),
        );
      
      case 'FULL':
        return ElevatedButton.icon(
          onPressed: () {
            DialogHelper.showInfo(
              context,
              title: '알림',
              message: '인원이 충족된 업무입니다.',
            );
          },
          icon: Icon(Icons.check_circle, size: ResponsiveHelper.iconSize(context, 16)),  // ⭐ 변경
          label: Text('인원충족 (${selectedWorks.length})'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
        );
      
      case 'EMERGENCY':
        return ElevatedButton.icon(
          onPressed: () => _handleBulkStopEmergency(selectedWorks),
          icon: Icon(Icons.warning_amber, size: ResponsiveHelper.iconSize(context, 16)),  // ⭐ 변경
          label: Text('긴급모집 종료 (${selectedWorks.length})'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
          ),
        );
        
      default:
        print('⚠️ 알 수 없는 상태: $status');
        return const SizedBox.shrink();
    }
  }

  // 🔥 긴급모집 종료 메서드 추가
  Future<void> _handleBulkStopEmergency(List<WorkDetailModel> works) async {
    final confirm = await DialogHelper.showConfirm(
      context,
      title: '긴급모집 종료',
      message: '${works.length}개 업무의 긴급모집을 종료하시겠습니까?',
      confirmText: '종료',
      confirmColor: Colors.orange,
    );

    if (confirm) {
      for (var work in works) {
        await firestoreService.stopEmergencyRecruitment(
          toId: toItem.to.id,
          workDetailId: work.id,
          adminUID: FirebaseAuth.instance.currentUser!.uid,
        );
      }
      
      Navigator.pop(context);
      onComplete();
      ToastHelper.showSuccess('${works.length}개 업무 긴급모집이 종료되었습니다');
    }
  }

  // 헬퍼 메서드들
  String _getWorkStatus(WorkDetailModel work, int confirmed) {
    if (work.isTimeExpired) return 'TIME_EXPIRED';
    if (work.isClosed) return 'CLOSED';
    if (work.isEmergencyOpen) return 'EMERGENCY';
    if (confirmed >= work.requiredCount) return 'FULL';
    return 'ACTIVE';
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'TIME_EXPIRED': return '마감됨';
      case 'CLOSED': return '마감됨';
      case 'EMERGENCY': return '긴급모집';
      case 'FULL': return '인원충족';
      case 'ACTIVE': return '진행중';
      default: return '알 수 없음';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'TIME_EXPIRED': return Colors.grey;
      case 'CLOSED': return Colors.grey;
      case 'EMERGENCY': return Colors.red;
      case 'FULL': return Colors.green;
      case 'ACTIVE': return Colors.blue;
      default: return Colors.grey;
    }
  }

  // 일괄 처리
  Future<void> _handleBulkClose(List<WorkDetailModel> works) async {
    final confirm = await DialogHelper.showConfirm(
      context,
      title: '업무 마감',
      message: '${works.length}개 업무를 마감하시겠습니까?',
      confirmText: '마감',
      confirmColor: Colors.red,
    );

    if (confirm) {
      for (var work in works) {
        await firestoreService.closeWorkDetail(
          toId: toItem.to.id,
          workDetailId: work.id,
          adminUID: FirebaseAuth.instance.currentUser!.uid,
        );
      }
      
      Navigator.pop(context);
      onComplete();
      ToastHelper.showSuccess('${works.length}개 업무가 마감되었습니다');
    }
  }

  Future<void> _handleBulkReopen(List<WorkDetailModel> works) async {
    final confirm = await DialogHelper.showConfirm(
      context,
      title: '업무 재오픈',
      message: '${works.length}개 업무를 재오픈하시겠습니까?',
      confirmText: '재오픈',
      confirmColor: Colors.green,
    );

    if (confirm) {
      for (var work in works) {
        await firestoreService.reopenWorkDetail(
          toId: toItem.to.id,
          workDetailId: work.id,
          adminUID: FirebaseAuth.instance.currentUser!.uid,
        );
      }
      
      Navigator.pop(context);
      onComplete();
      ToastHelper.showSuccess('${works.length}개 업무가 재오픈되었습니다');
    }
  }
}