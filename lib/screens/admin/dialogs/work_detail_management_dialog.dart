import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../../../models/to_model.dart';
import '../../../models/work_detail_model.dart';
import '../../../services/firestore_service.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../widgets/work_type_icon.dart';
import '../models/to_list_models.dart';

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
                Icon(Icons.task_alt, color: Colors.purple[600]),
                const SizedBox(width: 8),
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
                  const SizedBox(height: 12),
                  
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
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
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                if (selectedStatus != null)
                  Text(
                    _getStatusLabel(selectedStatus),
                    style: TextStyle(
                      fontSize: 11,
                      color: _getStatusColor(selectedStatus),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            '${selectedWorkDetails.length}/${selectedStatus == null ? toItem.workDetails.length : selectableWorks.length}개 선택',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
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
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue[50] : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected 
                ? Colors.blue[300]! 
                : isEnabled 
                  ? Colors.grey[300]! 
                  : Colors.grey[200]!,
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
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: FormatHelper.parseColor(work.workTypeColor),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: WorkTypeIcon.buildFromString(
                    work.workTypeIcon,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      work.workType,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${work.startTime}~${work.endTime} | ${NumberFormat('#,###').format(work.wage)}원',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: _getStatusColor(workStatus).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _getStatusColor(workStatus),
                      ),
                    ),
                    child: Text(
                      _getStatusLabel(workStatus),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: _getStatusColor(workStatus),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '확정 $confirmed/${work.requiredCount}명',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                    ),
                  ),
                  if (pending > 0)
                    Text(
                      '대기 $pending명',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange[700],
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
          icon: const Icon(Icons.lock, size: 16),
          label: Text('${selectedWorks.length}개 마감'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
        );
        
      case 'CLOSED':
        return ElevatedButton.icon(
          onPressed: () => _handleBulkReopen(selectedWorks),
          icon: const Icon(Icons.lock_open, size: 16),
          label: Text('${selectedWorks.length}개 재오픈'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
        );
      
      case 'TIME_EXPIRED':  // 🔥 추가!
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
          icon: const Icon(Icons.schedule, size: 16),
          label: Text('시간 만료 (${selectedWorks.length})'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.grey[400],
            foregroundColor: Colors.white,
          ),
        );
      
      case 'FULL':  // 🔥 추가!
        return ElevatedButton.icon(
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('알림'),
                content: const Text('인원이 충족된 업무입니다.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('확인'),
                  ),
                ],
              ),
            );
          },
          icon: const Icon(Icons.check_circle, size: 16),
          label: Text('인원충족 (${selectedWorks.length})'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green[400],
            foregroundColor: Colors.white,
          ),
        );
      
      case 'EMERGENCY':  // 🔥 추가!
        return ElevatedButton.icon(
          onPressed: () => _handleBulkStopEmergency(selectedWorks),
          icon: const Icon(Icons.warning_amber, size: 16),
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('긴급모집 종료'),
        content: Text('${works.length}개 업무의 긴급모집을 종료하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('종료'),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
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
      case 'TIME_EXPIRED': return Colors.grey[600]!;
      case 'CLOSED': return Colors.grey[600]!;
      case 'EMERGENCY': return Colors.red[600]!;
      case 'FULL': return Colors.green[600]!;
      case 'ACTIVE': return Colors.blue[600]!;
      default: return Colors.grey[600]!;
    }
  }

  // 일괄 처리
  Future<void> _handleBulkClose(List<WorkDetailModel> works) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('업무 마감'),
        content: Text('${works.length}개 업무를 마감하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('마감'),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('업무 재오픈'),
        content: Text('${works.length}개 업무를 재오픈하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('재오픈'),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
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