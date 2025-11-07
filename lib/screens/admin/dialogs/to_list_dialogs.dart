import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../models/core/to_model.dart';
import '../../../services/firestore_service.dart';
import '../../../providers/user_provider.dart';
import '../../../utils/toast_helper.dart';
import '../../../models/ui/admin_to_list_ui_models.dart';
import '../../../utils/dialog_helper.dart';

/// TO 관련 다이얼로그 모음
class TOListDialogs {
  final BuildContext context;
  final FirestoreService firestoreService;
  final VoidCallback onChanged;

  TOListDialogs({
    required this.context,
    required this.firestoreService,
    required this.onChanged,
  });

  /// 그룹명 수정 다이얼로그
  Future<void> showEditGroupNameDialog(TOModel to) async {
    if (to.groupId == null || to.groupName == null) return;

    final controller = TextEditingController(text: to.groupName);

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.edit, color: Colors.blue),
            SizedBox(width: 12),
            Text('그룹명 수정'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '그룹에 속한 모든 TO의 이름이 변경됩니다',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: '새 그룹명',
                hintText: '예: 4주차 파트타임 모음',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isEmpty) {
                ToastHelper.showError('그룹명을 입력하세요');
                return;
              }
              Navigator.pop(context, newName);
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final success = await firestoreService.updateGroupName(to.groupId!, result);
      if (success) {
        onChanged();
      }
    }

    controller.dispose();
  }

  /// TO 삭제 다이얼로그
  Future<void> showDeleteTODialog(TOItem toItem) async {
    final to = toItem.to;
    
    final checkResult = await firestoreService.checkTOBeforeDelete(to.id);
    final hasApplicants = checkResult['hasApplicants'] as bool;
    final confirmedCount = checkResult['confirmedCount'] as int;
    final totalCount = checkResult['totalCount'] as int;
    
    final isGroupTO = to.groupId != null;
    final isMasterTO = to.isGroupMaster;
    
    String title = 'TO 삭제 확인';
    String content = '';
    
    if (isGroupTO) {
      if (isMasterTO) {
        title = '⚠️ 대표 TO 삭제';
        content = '그룹: "${to.groupName}"의\n대표 TO를 삭제하시겠습니까?\n\n📋 ${DateFormat('MM/dd (E)', 'ko_KR').format(to.date)} ${to.title}\n\n⚠️ 다음 TO가 새로운 대표가 됩니다.\n✅ 그룹은 유지됩니다';
      } else {
        title = '⚠️ TO 삭제 확인';
        content = '그룹: "${to.groupName}"에서\n다음 TO를 삭제하시겠습니까?\n\n📋 ${DateFormat('MM/dd (E)', 'ko_KR').format(to.date)} ${to.title}\n\n✅ 그룹은 유지됩니다\n✅ 다른 TO는 영향 없음';
      }
    } else {
      content = '다음 TO를 삭제하시겠습니까?\n\n📋 ${DateFormat('MM/dd (E)', 'ko_KR').format(to.date)} ${to.title}';
    }
    
    if (hasApplicants) {
      content += '\n\n👤 지원자: $totalCount명 (확정 $confirmedCount명)';
      if (confirmedCount > 0) {
        content += '\n⚠️ 확정된 지원자가 있습니다!';
      }
    }
    
    final confirmed = await DialogHelper.showDeleteConfirm(
      context,
      itemName: 'TO',
      additionalMessage: content,
    );
    
    if (confirmed == true) {
      final success = await firestoreService.deleteTO(to.id);
      if (success) {
        onChanged();
      }
    }
  }

  /// 그룹 전체 삭제 다이얼로그
  Future<void> showDeleteGroupDialog(TOGroupItem groupItem) async {
    final masterTO = groupItem.masterTO;
    
    int totalApplicants = 0;
    for (var toItem in groupItem.groupTOs) {
      totalApplicants += toItem.confirmedCount + toItem.pendingCount;
    }
    
    // ⭐ 변경: DialogHelper 사용
    final confirmed = await DialogHelper.showDangerConfirm(
      context,
      title: '⚠️ 그룹 전체 삭제',
      message: '다음 그룹을 전체 삭제하시겠습니까?\n\n'
          '🔗 ${masterTO.groupName}\n\n'
          '포함된 TO: ${groupItem.groupTOs.length}개\n'
          '⚠️ 총 $totalApplicants명의 지원자가 영향받습니다\n'
          '⚠️ 이 작업은 되돌릴 수 없습니다',
      confirmText: '전체 삭제',
    );

    if (confirmed) {
      final success = await firestoreService.deleteGroupTOs(masterTO.groupId!);
      if (success) {
        onChanged();
      }
    }
    
    if (confirmed == true) {
      final success = await firestoreService.deleteGroupTOs(masterTO.groupId!);
      if (success) {
        onChanged();
      }
    }
  }

  /// 그룹 해제 다이얼로그
  Future<void> showRemoveFromGroupDialog(TOItem toItem) async {
    final to = toItem.to;
    
    if (to.groupId == null) {
      ToastHelper.showError('그룹 TO가 아닙니다.');
      return;
    }
    
    // ⭐ 변경: DialogHelper 사용
    final confirmed = await DialogHelper.showConfirm(
      context,
      title: '그룹 해제',
      message: '그룹: "${to.groupName}"에서\n다음 TO를 해제하시겠습니까?\n\n'
          '📋 ${DateFormat('MM/dd (E)', 'ko_KR').format(to.date)} ${to.title}\n\n'
          '✅ 독립 TO로 전환됩니다\n'
          '✅ 다른 그룹으로 재연결 가능\n'
          '✅ 지원자 정보는 유지됩니다',
      confirmText: '해제',
      confirmColor: Colors.orange,
      icon: Icons.link_off,
      iconColor: Colors.orange,
    );

    if (confirmed) {
      final success = await firestoreService.removeFromGroup(to.id);
      if (success) {
        onChanged();
      }
    }
  }

  /// TO 마감 다이얼로그
  Future<void> showCloseTODialog(TOModel to) async {
    // ⭐ 변경: DialogHelper 사용 (커스텀 콘텐츠)
    final confirmed = await DialogHelper.showCustom<bool>(
      context,
      title: 'TO 마감',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('이 TO를 마감 처리하시겠습니까?'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• 더 이상 지원을 받을 수 없습니다', style: TextStyle(fontSize: 13)),
                Text('• 재오픈으로 다시 활성화 가능합니다', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('취소'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
          ),
          child: const Text('마감'),
        ),
      ],
    );

    if (confirmed != true) return;

    DialogHelper.showLoading(context, message: '처리 중...');

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final adminUID = userProvider.currentUser?.uid ?? '';

      final success = await firestoreService.closeTOManually(to.id, adminUID);

      Navigator.pop(context); // 로딩 닫기

      if (success) {
        ToastHelper.showSuccess('TO가 마감되었습니다.');
        onChanged();
      } else {
        ToastHelper.showError('TO 마감에 실패했습니다.');
      }
    } catch (e) {
      Navigator.pop(context);
      print('❌ TO 마감 실패: $e');
      ToastHelper.showError('TO 마감 중 오류가 발생했습니다.');
    }
  }

  /// TO 재오픈 다이얼로그
  Future<void> showReopenTODialog(TOModel to) async {
    if (to.isTimeExpired) {
      _showTimeExpiredDialog(to);
      return;
    }

    final isFull = to.isFull;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('TO 재오픈'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('이 TO를 다시 오픈하시겠습니까?'),
            const SizedBox(height: 16),
            
            if (isFull) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[300]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.orange[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '⚠️ 이미 인원이 충족된 TO입니다.\n추가 지원자를 받으시겠습니까?',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange[800],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.green[700]),
                      const SizedBox(width: 8),
                      const Text(
                        '재오픈 후 변경사항',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('• 지원자가 다시 지원할 수 있습니다', style: TextStyle(fontSize: 13)),
                  const Text('• 기존 확정 지원자는 유지됩니다', style: TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('재오픈'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    DialogHelper.showLoading(context, message: '재오픈 중...');

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final adminUID = userProvider.currentUser?.uid ?? '';

      final success = await firestoreService.reopenTO(to.id, adminUID);

      Navigator.pop(context);

      if (success) {
        ToastHelper.showSuccess('TO가 재오픈되었습니다.');
        onChanged();
      } else {
        ToastHelper.showError('TO 재오픈에 실패했습니다.');
      }
    } catch (e) {
      Navigator.pop(context);
      print('❌ TO 재오픈 실패: $e');
      ToastHelper.showError('TO 재오픈 중 오류가 발생했습니다.');
    }
  }

  /// 그룹 전체 마감 다이얼로그
  Future<void> showCloseGroupDialog(TOGroupItem groupItem) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('그룹 전체 마감'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('그룹 "${groupItem.masterTO.groupName}"의 모든 TO를 마감하시겠습니까?'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '포함된 TO: ${groupItem.groupTOs.length}개',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text('• 모든 TO가 마감됩니다', style: TextStyle(fontSize: 13)),
                  const Text('• 더 이상 지원을 받을 수 없습니다', style: TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('전체 마감'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    DialogHelper.showLoading(context, message: '그룹 마감 중...');

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final adminUID = userProvider.currentUser?.uid ?? '';

      final success = await firestoreService.closeGroupTOs(
        groupItem.masterTO.groupId!,
        adminUID,
      );

      Navigator.pop(context);

      if (success) {
        ToastHelper.showSuccess('그룹 전체가 마감되었습니다.');
        onChanged();
      } else {
        ToastHelper.showError('그룹 마감에 실패했습니다.');
      }
    } catch (e) {
      Navigator.pop(context);
      print('❌ 그룹 마감 실패: $e');
      ToastHelper.showError('그룹 마감 중 오류가 발생했습니다.');
    }
  }

  /// 그룹 전체 재오픈 다이얼로그
  Future<void> showReopenGroupDialog(TOGroupItem groupItem) async {
    final hasExpiredTO = groupItem.groupTOs.any((toItem) => toItem.to.isTimeExpired);
    
    if (hasExpiredTO) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red[700]),
              const SizedBox(width: 8),
              const Text('재오픈 불가'),
            ],
          ),
          content: const Text(
            '그룹 내에 근무 시작 시간이 지난 TO가 있어\n그룹 전체를 재오픈할 수 없습니다.\n\n각 TO를 개별적으로 확인해주세요.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('그룹 전체 재오픈'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('그룹 "${groupItem.masterTO.groupName}"의 모든 TO를 재오픈하시겠습니까?'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '포함된 TO: ${groupItem.groupTOs.length}개',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text('• 모든 TO가 재오픈됩니다', style: TextStyle(fontSize: 13)),
                  const Text('• 지원자가 다시 지원할 수 있습니다', style: TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('전체 재오픈'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    DialogHelper.showLoading(context, message: '그룹 재오픈 중...');

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final adminUID = userProvider.currentUser?.uid ?? '';

      final success = await firestoreService.reopenGroupTOs(
        groupItem.masterTO.groupId!,
        adminUID,
      );

      Navigator.pop(context);

      if (success) {
        ToastHelper.showSuccess('그룹 전체가 재오픈되었습니다.');
        onChanged();
      } else {
        ToastHelper.showError('그룹 재오픈에 실패했습니다.');
      }
    } catch (e) {
      Navigator.pop(context);
      print('❌ 그룹 재오픈 실패: $e');
      ToastHelper.showError('그룹 재오픈 중 오류가 발생했습니다.');
    }
  }

  // ========================================
  // Helper 메서드들
  // ========================================

  void _showTimeExpiredDialog(TOModel to) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red[700]),
            const SizedBox(width: 8),
            const Text('재오픈 불가'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '근무 시작 시간이 지난 TO는 재오픈할 수 없습니다.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 16, color: Colors.red[700]),
                      const SizedBox(width: 8),
                      Text(
                        '근무일: ${DateFormat('yyyy-MM-dd (E)', 'ko_KR').format(to.date)}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.red[900],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 16, color: Colors.red[700]),
                      const SizedBox(width: 8),
                      Text(
                        '근무 시간: ${to.startTime} ~ ${to.endTime}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.red[900],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '💡 새로운 날짜로 TO를 생성하세요.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }
  /// 그룹 연결 다이얼로그 (기존 그룹 또는 새 그룹 생성)
  Future<void> showReconnectToGroupDialog(TOItem toItem, List<TOGroupItem> allGroups) async {
    final to = toItem.to;
    
    // 동일 사업장의 그룹만 필터링
    final availableGroups = allGroups
        .where((item) => 
            item.isGrouped && 
            item.masterTO.groupId != to.groupId &&
            item.masterTO.businessId == to.businessId
        )
        .toList();
    
    String? selectedOption = 'existing';
    String? selectedGroupId;
    final newGroupNameController = TextEditingController();
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.link, color: Colors.blue),
              SizedBox(width: 12),
              Text('그룹 연결'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '다음 TO를 그룹에 연결합니다:\n\n'
                  '📋 ${DateFormat('MM/dd (E)', 'ko_KR').format(to.date)} ${to.title}',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 20),
                
                // 옵션 1: 기존 그룹에 연결
                RadioListTile<String>(
                  title: const Text('기존 그룹에 연결'),
                  value: 'existing',
                  groupValue: selectedOption,
                  onChanged: availableGroups.isEmpty ? null : (value) {
                    setState(() => selectedOption = value);
                  },
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                
                if (selectedOption == 'existing') ...[
                  const SizedBox(height: 8),
                  if (availableGroups.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Text(
                        '연결 가능한 그룹이 없습니다',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: DropdownButtonFormField<String>(
                        initialValue: selectedGroupId,
                        decoration: const InputDecoration(
                          labelText: '그룹 선택',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: availableGroups.map((item) {
                          final master = item.masterTO;
                          return DropdownMenuItem(
                            value: master.groupId,
                            child: Text(
                              '${master.groupName} (${master.businessName})',
                              style: const TextStyle(fontSize: 13),
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() => selectedGroupId = value);
                        },
                      ),
                    ),
                ],
                
                const SizedBox(height: 16),
                
                // 옵션 2: 새 그룹 생성
                RadioListTile<String>(
                  title: const Text('새 그룹 생성'),
                  value: 'new',
                  groupValue: selectedOption,
                  onChanged: (value) {
                    setState(() => selectedOption = value);
                  },
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                
                if (selectedOption == 'new') ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: newGroupNameController,
                          decoration: const InputDecoration(
                            labelText: '새 그룹명',
                            hintText: '예: 11월 1주차 모음',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue[200]!),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline, size: 16, color: Colors.blue[700]),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '이 TO가 새 그룹의 대표가 됩니다.\n나중에 다른 TO를 이 그룹에 추가할 수 있습니다.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[700],
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () {
                if (selectedOption == 'existing' && selectedGroupId == null) {
                  ToastHelper.showError('그룹을 선택하세요');
                  return;
                }
                if (selectedOption == 'new' && newGroupNameController.text.trim().isEmpty) {
                  ToastHelper.showError('그룹명을 입력하세요');
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('연결'),
            ),
          ],
        ),
      ),
    );
    
    if (confirmed == true) {
      bool success = false;
      
      if (selectedOption == 'existing' && selectedGroupId != null) {
        success = await firestoreService.reconnectToGroup(
          toId: to.id,
          targetGroupId: selectedGroupId!,
        );
      } else if (selectedOption == 'new') {
        final groupName = newGroupNameController.text.trim();
        success = await firestoreService.createNewGroupFromTO(
          toId: to.id,
          groupName: groupName,
        );
      }
      
      if (success) {
        onChanged();
      }
    }
    
    newGroupNameController.dispose();
  }
}