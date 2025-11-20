import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Models
import '../../../models/core/work_detail_model.dart';
import '../../../models/core/to_model.dart';
import '../../../models/ui/admin_to_list_ui_models.dart';

// Services
import '../../../services/firestore_service.dart';

// Providers
import '../../../providers/user_provider.dart';

// Utils
import '../../../utils/toast_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/responsive_helper.dart';

// Widgets
import '../../work_type_icon.dart';

// Dialogs
import '../../../screens/business_admin/dialogs/work_applicants_dialog.dart';

/// ✨ 업무 상세 행 위젯 (세련된 디자인)
class WorkDetailRow extends StatelessWidget {
  final WorkDetailModel work;
  final int confirmedCount;
  final int pendingCount;
  final TOItem toItem;
  final FirestoreService firestoreService;
  final VoidCallback onChanged;

  const WorkDetailRow({
    super.key,
    required this.work,
    required this.confirmedCount,
    required this.pendingCount,
    required this.toItem,
    required this.firestoreService,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final workStatus = _getWorkStatus(work, confirmedCount);
    final theme = Theme.of(context);
    
    return Container(
      margin: EdgeInsets.only(
        bottom: ResponsiveHelper.spacing(context, 8),
      ),
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✨ 1줄: 업무 타입 + 메뉴
          Row(
            children: [
              // 업무 타입 아이콘
              Container(
                width: ResponsiveHelper.iconSize(context, 36),
                height: ResponsiveHelper.iconSize(context, 36),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      FormatHelper.parseColor(work.workTypeBackgroundColor ?? '#2196F3'),
                      FormatHelper.parseColor(work.workTypeBackgroundColor ?? '#2196F3').withOpacity(0.8),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: FormatHelper.parseColor(work.workTypeBackgroundColor ?? '#2196F3').withOpacity(0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: WorkTypeIcon.buildFromString(
                    work.workTypeIcon,
                    color: FormatHelper.parseColor(work.workTypeColor),
                    size: ResponsiveHelper.iconSize(context, 18),
                  ),
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Expanded(
                child: Text(
                  work.workType,
                  style: ResponsiveHelper.subtitleStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              // 메뉴
              _buildPopupMenu(context),
            ],
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          
          // ✨ 2줄: 시간 정보
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 6)),
                  decoration: BoxDecoration(
                    color: Colors.blue[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.access_time,
                    size: ResponsiveHelper.iconSize(context, 14),
                    color: Colors.blue[700],
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 10)),
                Text(
                  '${work.startTime} ~ ${work.endTime}',
                  style: ResponsiveHelper.bodyStyle(
                    context,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          
          // ✨ 3줄: 금액 정보 (wageType 포함)
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 6)),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.payments,
                    size: ResponsiveHelper.iconSize(context, 14),
                    color: theme.primaryColor,
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 10)),
                Text(
                  work.wageTypeLabel,
                  style: ResponsiveHelper.smallStyle(
                    context,
                    color: Colors.grey[700],
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                Text(
                  '${NumberFormat('#,###').format(work.wage)}원',
                  style: ResponsiveHelper.bodyStyle(
                    context,
                    color: theme.primaryColor,
                  ).copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          
          // ✨ 마감시간 (HOURS_BEFORE인 경우)
          if (toItem.to.deadlineType == 'HOURS_BEFORE') ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 10),
                vertical: ResponsiveHelper.spacing(context, 6),
              ),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.alarm,
                    size: ResponsiveHelper.iconSize(context, 14),
                    color: Colors.orange[700],
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                  Text(
                    '마감: ${_calculateDeadline(toItem.to, work)}까지',
                    style: ResponsiveHelper.smallStyle(
                      context,
                      color: Colors.orange[700],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
          
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          
          // ✨ 마지막 줄: 확정 + 대기 + 상태 배지
          Row(
            children: [
              // 확정 인원
              Container(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: work.isFull
                        ? [Colors.green[50]!, Colors.green[50]!.withOpacity(0.3)]
                        : [
                            theme.primaryColor.withOpacity(0.1),
                            theme.primaryColor.withOpacity(0.05)
                          ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: work.isFull
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
                      color: work.isFull ? Colors.green[700] : theme.primaryColor,
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                    Text(
                      '확정 ',
                      style: ResponsiveHelper.smallStyle(
                        context,
                        color: work.isFull ? Colors.green[700] : theme.primaryColor,
                      ),
                    ),
                    Text(
                      '$confirmedCount/${work.requiredCount}',
                      style: ResponsiveHelper.bodyStyle(
                        context,
                        color: work.isFull ? Colors.green[700] : theme.primaryColor,
                      ).copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              
              if (pendingCount > 0) ...[
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
                        '$pendingCount',
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
              
              // 상태 배지 (오른쪽 끝)
              _buildStatusBadge(context, workStatus),
            ],
          ),
        ],
      ),
    );
  }

  /// ✨ 상태 배지
  Widget _buildStatusBadge(BuildContext context, Map<String, dynamic> workStatus) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 10),
        vertical: ResponsiveHelper.spacing(context, 6),
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            (workStatus['color'] as Color).withOpacity(0.2),
            (workStatus['color'] as Color).withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: (workStatus['color'] as Color).withOpacity(0.5),
          width: 1.5,
        ),
      ),
      child: Text(
        workStatus['label'],
        style: ResponsiveHelper.tinyStyle(
          context,
          color: workStatus['color'],
        ).copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  /// 팝업 메뉴
  Widget _buildPopupMenu(BuildContext context) {
    final isClosed = work.isClosed;
    final isTimeExpired = work.isTimeExpired;
    final isEmergencyOpen = work.isEmergencyOpen;

    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert,
        size: ResponsiveHelper.iconSize(context, 20),
        color: Theme.of(context).primaryColor,
      ),
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      onSelected: (value) => _handleWorkDetailMenu(context, value, work, toItem),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'manage',
          child: Row(
            children: [
              Icon(
                Icons.people,
                size: ResponsiveHelper.iconSize(context, 18),
                color: Colors.blue[600],
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              const Text('지원자 관리'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        if (isTimeExpired)
          PopupMenuItem(
            enabled: false,
            value: 'expired',
            child: Row(
              children: [
                Icon(
                  Icons.schedule,
                  size: ResponsiveHelper.iconSize(context, 18),
                  color: Colors.grey[400],
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Text(
                  '시간 만료됨',
                  style: ResponsiveHelper.bodyStyle(
                    context,
                    color: Colors.grey[400],
                  ),
                ),
              ],
            ),
          )
        else if (isClosed)
          PopupMenuItem(
            value: 'reopen',
            child: Row(
              children: [
                Icon(
                  Icons.lock_open,
                  size: ResponsiveHelper.iconSize(context, 18),
                  color: Colors.green[600],
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                const Text('업무 재오픈'),
              ],
            ),
          )
        else
          PopupMenuItem(
            value: 'close',
            child: Row(
              children: [
                Icon(
                  Icons.block,
                  size: ResponsiveHelper.iconSize(context, 18),
                  color: Colors.red[600],
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                const Text('업무 마감'),
              ],
            ),
          ),
        if (!isClosed && !isTimeExpired) ...[
          const PopupMenuDivider(),
          if (!isEmergencyOpen)
            PopupMenuItem(
              value: 'emergency_start',
              child: Row(
                children: [
                  Icon(
                    Icons.warning,
                    size: ResponsiveHelper.iconSize(context, 18),
                    color: Colors.orange[600],
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                  const Text('긴급 모집 시작'),
                ],
              ),
            )
          else
            PopupMenuItem(
              value: 'emergency_stop',
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    size: ResponsiveHelper.iconSize(context, 18),
                    color: Colors.green[600],
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                  const Text('긴급 모집 종료'),
                ],
              ),
            ),
        ],
      ],
    );
  }

  /// 업무별 메뉴 핸들러
  Future<void> _handleWorkDetailMenu(
    BuildContext context,
    String value,
    WorkDetailModel work,
    TOItem toItem,
  ) async {
    switch (value) {
      case 'manage':
        await _showWorkApplicantsDialog(context, work, toItem);
        break;
      case 'close':
        await _closeWork(context, work, toItem);
        break;
      case 'reopen':
        await _reopenWork(context, work, toItem);
        break;
      case 'expired':
        ToastHelper.showWarning('시간이 지난 업무는 재오픈할 수 없습니다');
        break;
      case 'emergency_start':
        await _startEmergency(context, work, toItem);
        break;
      case 'emergency_stop':
        await _stopEmergency(context, work, toItem);
        break;
    }
  }

  /// 지원자 관리 다이얼로그
  Future<void> _showWorkApplicantsDialog(
    BuildContext context,
    WorkDetailModel work,
    TOItem toItem,
  ) async {
    await showDialog(
      context: context,
      builder: (context) => WorkApplicantsDialog(
        work: work,
        toItem: toItem,
        onChanged: onChanged,
      ),
    );
  }

  /// 업무 마감
  Future<void> _closeWork(
    BuildContext context,
    WorkDetailModel work,
    TOItem toItem,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${work.workType} 마감'),
        content: const Text('이 업무를 마감하시겠습니까?\n마감 후에도 재오픈할 수 있습니다.'),
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

    if (confirmed != true) return;

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final adminUID = userProvider.currentUser?.uid;

      await firestoreService.updateWorkDetail(
        toId: toItem.to.id,
        workDetailId: work.id,
        updates: {
          'closedAt': Timestamp.now(),
          'closedBy': adminUID,
          'isManualClosed': true,
          'isEmergencyOpen': false,
        },
      );

      ToastHelper.showSuccess('${work.workType} 업무가 마감되었습니다');
      onChanged();
    } catch (e) {
      print('❌ 업무 마감 실패: $e');
      ToastHelper.showError('업무 마감에 실패했습니다');
    }
  }

  /// 업무 재오픈
  Future<void> _reopenWork(
    BuildContext context,
    WorkDetailModel work,
    TOItem toItem,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('업무 재오픈'),
        content: Text('${work.workType} 업무를 재오픈하시겠습니까?'),
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

    if (confirm != true) return;

    try {
      await firestoreService.reopenWorkDetail(
        toId: toItem.to.id,
        workDetailId: work.id,
        adminUID: FirebaseAuth.instance.currentUser!.uid,
      );
      
      onChanged();
      ToastHelper.showSuccess('업무가 재오픈되었습니다');
    } catch (e) {
      print('❌ 업무 재오픈 실패: $e');
      ToastHelper.showError('업무 재오픈에 실패했습니다');
    }
  }

  /// 긴급 모집 시작
  Future<void> _startEmergency(
    BuildContext context,
    WorkDetailModel work,
    TOItem toItem,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🚨 긴급 모집'),
        content: Text('${work.workType} 긴급 모집을 시작하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('시작'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final adminUID = userProvider.currentUser?.uid;

      await firestoreService.updateWorkDetail(
        toId: toItem.to.id,
        workDetailId: work.id,
        updates: {
          'isEmergencyOpen': true,
          'emergencyOpenedAt': Timestamp.now(),
          'emergencyOpenedBy': adminUID,
        },
      );

      ToastHelper.showSuccess('🚨 ${work.workType} 긴급 모집이 시작되었습니다');
      onChanged();
    } catch (e) {
      print('❌ 긴급 모집 시작 실패: $e');
      ToastHelper.showError('긴급 모집 시작에 실패했습니다');
    }
  }

  /// 긴급 모집 종료
  Future<void> _stopEmergency(
    BuildContext context,
    WorkDetailModel work,
    TOItem toItem,
  ) async {
    try {
      await firestoreService.updateWorkDetail(
        toId: toItem.to.id,
        workDetailId: work.id,
        updates: {
          'isEmergencyOpen': false,
          'emergencyOpenedAt': null,
          'emergencyOpenedBy': null,
        },
      );

      ToastHelper.showSuccess('${work.workType} 긴급 모집이 종료되었습니다');
      onChanged();
    } catch (e) {
      print('❌ 긴급 모집 종료 실패: $e');
      ToastHelper.showError('긴급 모집 종료에 실패했습니다');
    }
  }

  /// 업무 상태 계산
  Map<String, dynamic> _getWorkStatus(WorkDetailModel work, int confirmedCount) {
    if (work.isTimeExpired) {
      return {
        'label': '마감됨',
        'color': Colors.grey[600],
      };
    }
    
    if (work.isClosed) {
      return {
        'label': '마감됨',
        'color': Colors.grey[600],
      };
    }
    
    if (work.isEmergencyOpen) {
      return {
        'label': '긴급모집',
        'color': Colors.red[600],
      };
    }
    
    if (confirmedCount >= work.requiredCount) {
      return {
        'label': '인원충족',
        'color': Colors.green[600],
      };
    }
    
    return {
      'label': '진행중',
      'color': Colors.blue[600],
    };
  }

  /// 마감시간 계산
  String _calculateDeadline(TOModel to, WorkDetailModel work) {
    final hoursBeforeStart = to.hoursBeforeStart ?? 2;
    
    final timeParts = work.startTime.split(':');
    final hour = int.parse(timeParts[0]);
    final minute = int.parse(timeParts[1]);
    
    final deadlineHour = hour - hoursBeforeStart;
    final deadlineMinute = minute;
    
    return '${deadlineHour.toString().padLeft(2, '0')}:${deadlineMinute.toString().padLeft(2, '0')}';
  }
}