import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../models/core/to_model.dart';
import '../../../services/firestore_service.dart';
import '../../../providers/user_provider.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/responsive_helper.dart';  // ⭐ 추가
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
        title: Row(
          children: [
            Icon(Icons.edit, color: Theme.of(context).primaryColor),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),  // ⭐ 변경
            const Text('그룹명 수정'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '그룹에 속한 모든 TO의 이름이 변경됩니다',
              style: ResponsiveHelper.bodyStyle(  // ⭐ 변경
                context,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),  // ⭐ 변경
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
    // groupTOs가 로드되지 않았으면 group 통계 사용
    int totalApplicants = 0;
    if (groupItem.groupTOs.isNotEmpty) {
      for (var toItem in groupItem.groupTOs) {
        totalApplicants += toItem.confirmedCount + toItem.pendingCount;
      }
    } else {
      // 그룹 통계에서 가져옴
      totalApplicants = groupItem.totalConfirmed + groupItem.totalPending;
    }
    
    final toCount = groupItem.actualDaysCount;
    
    final confirmed = await DialogHelper.showDangerConfirm(
      context,
      title: '⚠️ 그룹 전체 삭제',
      message: '다음 그룹을 전체 삭제하시겠습니까?\n\n'
          '🔗 ${groupItem.groupName}\n\n'
          '포함된 TO: ${toCount}개\n'
          '⚠️ 총 $totalApplicants명의 지원자가 영향받습니다\n'
          '⚠️ 이 작업은 되돌릴 수 없습니다',
      confirmText: '전체 삭제',
    );

    if (confirmed) {
      final success = await firestoreService.deleteGroupTOs(groupItem.id);
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
    final confirmed = await DialogHelper.showCustom<bool>(
      context,
      title: 'TO 마감',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('이 TO를 마감 처리하시겠습니까?'),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),  // ⭐ 변경
          Container(
            padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '• 더 이상 지원을 받을 수 없습니다', 
                  style: ResponsiveHelper.smallStyle(context),  // ⭐ 변경
                ),
                Text(
                  '• 재오픈으로 다시 활성화 가능합니다', 
                  style: ResponsiveHelper.smallStyle(context),  // ⭐ 변경
                ),
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
      debugPrint('❌ TO 마감 실패: $e');
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
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),  // ⭐ 변경
            
            if (isFull) ...[
              Container(
                padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber, 
                      color: Colors.orange,
                      size: ResponsiveHelper.iconSize(context, 20),  // ⭐ 변경
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
                    Expanded(
                      child: Text(
                        '⚠️ 이미 인원이 충족된 TO입니다.\n추가 지원자를 받으시겠습니까?',
                        style: ResponsiveHelper.tinyStyle(  // ⭐ 변경
                          context,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),  // ⭐ 변경
            ],
            
            Container(
              padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline, 
                        size: ResponsiveHelper.iconSize(context, 16),  // ⭐ 변경
                        color: Colors.green,
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
                      Text(
                        '재오픈 후 변경사항',
                        style: ResponsiveHelper.bodyStyle(context).copyWith(  // ⭐ 변경
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
                  Text(
                    '• 지원자가 다시 지원할 수 있습니다', 
                    style: ResponsiveHelper.smallStyle(context),  // ⭐ 변경
                  ),
                  Text(
                    '• 기존 확정 지원자는 유지됩니다', 
                    style: ResponsiveHelper.smallStyle(context),  // ⭐ 변경
                  ),
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
      debugPrint('❌ TO 재오픈 실패: $e');
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
            Text('그룹 "${groupItem.groupName}"의 모든 TO를 마감하시겠습니까?'),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),  // ⭐ 변경
            Container(
              padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '포함된 TO: ${groupItem.actualDaysCount}개',
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
                  Text(
                    '• 모든 TO가 마감됩니다', 
                    style: ResponsiveHelper.smallStyle(context),  // ⭐ 변경
                  ),
                  Text(
                    '• 더 이상 지원을 받을 수 없습니다', 
                    style: ResponsiveHelper.smallStyle(context),  // ⭐ 변경
                  ),
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
        groupItem.id,
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
      debugPrint('❌ 그룹 마감 실패: $e');
      ToastHelper.showError('그룹 마감 중 오류가 발생했습니다.');
    }
  }

  /// 그룹 전체 재오픈 다이얼로그
  Future<void> showReopenGroupDialog(TOGroupItem groupItem) async {
    // groupTOs가 비어있으면 체크 불가 - 일단 통과시키고 서버에서 처리
    final hasExpiredTO = groupItem.groupTOs.isNotEmpty 
        ? groupItem.groupTOs.any((toItem) => toItem.to.isTimeExpired)
        : false;
    
    if (hasExpiredTO) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
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
            Text('그룹 "${groupItem.groupName}"의 모든 TO를 재오픈하시겠습니까?'),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),  // ⭐ 변경
            Container(
              padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '포함된 TO: ${groupItem.actualDaysCount}개',
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
                  Text(
                    '• 모든 TO가 재오픈됩니다',
                    style: ResponsiveHelper.smallStyle(context),  // ⭐ 변경
                  ),
                  Text(
                    '• 지원자가 다시 지원할 수 있습니다', 
                    style: ResponsiveHelper.smallStyle(context),  // ⭐ 변경
                  ),
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
        groupItem.id,
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
      debugPrint('❌ 그룹 재오픈 실패: $e');
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
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
            const Text('재오픈 불가'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '근무 시작 시간이 지난 TO는 재오픈할 수 없습니다.',
              style: ResponsiveHelper.bodyStyle(context).copyWith(  // ⭐ 변경
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),  // ⭐ 변경
            Container(
              padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today, 
                        size: ResponsiveHelper.iconSize(context, 16),  // ⭐ 변경
                        color: Colors.red,
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
                      Text(
                        '근무일: ${DateFormat('yyyy-MM-dd (E)', 'ko_KR').format(to.date)}',
                        style: ResponsiveHelper.smallStyle(  // ⭐ 변경
                          context,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 4)),  // ⭐ 변경
                  Row(
                    children: [
                      Icon(
                        Icons.access_time, 
                        size: ResponsiveHelper.iconSize(context, 16),  // ⭐ 변경
                        color: Colors.red,
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
                      Text(
                        '근무 시간: ${to.startTime} ~ ${to.endTime}',
                        style: ResponsiveHelper.smallStyle(  // ⭐ 변경
                          context,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),  // ⭐ 변경
            Text(
              '💡 새로운 날짜로 TO를 생성하세요.',
              style: ResponsiveHelper.bodyStyle(  // ⭐ 변경
                context,
                color: Theme.of(context).textTheme.bodySmall?.color,
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
    final theme = Theme.of(context);
    
    // 동일 사업장의 그룹만 필터링
    final availableGroups = allGroups
        .where((item) => 
            item.isGrouped && 
            item.id != to.groupId &&
            item.businessId == to.businessId
        )
        .toList();
    
    String selectedOption = 'existing';
    String? selectedGroupId;
    final newGroupNameController = TextEditingController();
    
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          titlePadding: EdgeInsets.zero,
          contentPadding: EdgeInsets.zero,
          actionsPadding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
          
          // ✅ 헤더
          title: Container(
            padding: ResponsiveHelper.cardPadding(context),
            decoration: BoxDecoration(
              color: theme.primaryColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.link,
                  color: Colors.white,
                  size: ResponsiveHelper.iconSize(context, 24),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Text(
                  '그룹 연결',
                  style: ResponsiveHelper.subtitleStyle(context).copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          
          // ✅ 콘텐츠
          content: SingleChildScrollView(
            padding: ResponsiveHelper.cardPadding(context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 연결할 TO 정보
                Container(
                  padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
                  decoration: BoxDecoration(
                    color: AppColors.grey100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.description_outlined,
                        size: ResponsiveHelper.iconSize(context, 20),
                        color: theme.primaryColor,
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                      Expanded(
                        child: Text(
                          '${DateFormat('MM/dd (E)', 'ko_KR').format(to.date)} ${to.title}',
                          style: ResponsiveHelper.bodyStyle(context).copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                
                SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                
                // ✅ 옵션 1: 기존 그룹에 연결
                _buildOptionTile(
                  context: context,
                  title: '기존 그룹에 연결',
                  icon: Icons.folder_open,
                  isSelected: selectedOption == 'existing',
                  isEnabled: availableGroups.isNotEmpty,
                  onTap: availableGroups.isEmpty ? null : () {
                    setState(() => selectedOption = 'existing');
                  },
                ),
                
                // 기존 그룹 선택 드롭다운 (항상 표시, 비선택 시 비활성화)
                AnimatedOpacity(
                  opacity: selectedOption == 'existing' ? 1.0 : 0.4,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: selectedOption != 'existing',
                    child: Column(
                      children: [
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                  if (availableGroups.isEmpty)
                    Container(
                      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
                      decoration: BoxDecoration(
                        color: AppColors.warningBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: ResponsiveHelper.iconSize(context, 16),
                            color: AppColors.warningDark,
                          ),
                          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                          Expanded(
                            child: Text(
                              '연결 가능한 그룹이 없습니다',
                              style: ResponsiveHelper.smallStyle(context, color: AppColors.warningDark),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    DropdownButtonFormField<String>(
                      value: selectedGroupId,
                      isExpanded: true,  // ✅ 전체 너비 사용
                      decoration: InputDecoration(
                        labelText: '그룹 선택',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: ResponsiveHelper.spacing(context, 12),
                          vertical: ResponsiveHelper.spacing(context, 12),
                        ),
                      ),
                      items: availableGroups.map((item) {
                        return DropdownMenuItem(
                          value: item.id,
                          child: Text(
                            item.groupName,
                            style: ResponsiveHelper.bodyStyle(context),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() => selectedGroupId = value);
                      },
                    ),
                ],
                    ),
                  ),
                ),
                
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                
                // ✅ 옵션 2: 새 그룹 생성
                _buildOptionTile(
                  context: context,
                  title: '새 그룹 생성',
                  icon: Icons.create_new_folder,
                  isSelected: selectedOption == 'new',
                  isEnabled: true,
                  onTap: () {
                    setState(() => selectedOption = 'new');
                  },
                ),
                
                // 새 그룹명 입력 (항상 표시, 비선택 시 비활성화)
                AnimatedOpacity(
                  opacity: selectedOption == 'new' ? 1.0 : 0.4,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: selectedOption != 'new',
                    child: Column(
                      children: [
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                  TextField(
                    controller: newGroupNameController,
                    decoration: InputDecoration(
                      labelText: '새 그룹명',
                      hintText: '예: 11월 1주차 모음',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.edit),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 12),
                        vertical: ResponsiveHelper.spacing(context, 12),
                      ),
                    ),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                  Container(
                    padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
                    decoration: BoxDecoration(
                      color: theme.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: theme.primaryColor.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: ResponsiveHelper.iconSize(context, 16),
                          color: theme.primaryColor,
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                        Expanded(
                          child: Text(
                            '이 TO가 새 그룹의 대표가 됩니다.\n나중에 다른 TO를 이 그룹에 추가할 수 있습니다.',
                            style: ResponsiveHelper.smallStyle(
                              context,
                              color: theme.primaryColor,
                            ).copyWith(height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // ✅ 액션 버튼
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(
                '취소',
                style: ResponsiveHelper.bodyStyle(context),
              ),
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
                Navigator.pop(dialogContext, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 24),
                  vertical: ResponsiveHelper.spacing(context, 12),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
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
    // ✅ dispose를 다음 프레임으로 지연 (다이얼로그 완전히 닫힌 후)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      newGroupNameController.dispose();
    });
  }

  /// 옵션 타일 빌더 (그룹 연결 다이얼로그용)
  Widget _buildOptionTile({
    required BuildContext context,
    required String title,
    required IconData icon,
    required bool isSelected,
    required bool isEnabled,
    required VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    
    return InkWell(
      onTap: isEnabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
        decoration: BoxDecoration(
          color: isSelected 
              ? theme.primaryColor.withOpacity(0.1) 
              : (isEnabled ? Colors.transparent : AppColors.grey100),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected 
                ? theme.primaryColor 
                : (isEnabled ? AppColors.grey300 : AppColors.grey200),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: isSelected 
                  ? theme.primaryColor 
                  : (isEnabled ? AppColors.grey500 : AppColors.grey400),
              size: ResponsiveHelper.iconSize(context, 20),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            Icon(
              icon,
              color: isSelected 
                  ? theme.primaryColor 
                  : (isEnabled ? AppColors.grey600 : AppColors.grey400),
              size: ResponsiveHelper.iconSize(context, 20),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Text(
              title,
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isEnabled ? null : AppColors.grey400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}