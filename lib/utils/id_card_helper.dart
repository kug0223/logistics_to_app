// lib/utils/id_card_helper.dart
// 신분증 관련 공통 헬퍼

import 'package:flutter/material.dart';
import '../models/core/id_card_access_request_model.dart';
import '../services/firestore_service.dart';
import '../theme/app_colors.dart';
import 'responsive_helper.dart';
import '../utils/toast_helper.dart';
import '../widgets/dialogs/styled_dialog.dart';

/// 신분증 관련 공통 헬퍼
class IdCardHelper {
  
  /// 신분증 상태 일괄 조회
  /// 
  /// [firestoreService] - Firestore 서비스
  /// [requesterId] - 요청자 UID (관리자)
  /// [targetUserIds] - 대상 사용자 UID 목록
  /// 
  /// 반환: {userId: 'approved' | 'pending' | 'none'}
  static Future<Map<String, String>> loadStatusBatch({
    required FirestoreService firestoreService,
    required String requesterId,
    required List<String> targetUserIds,
  }) async {
    if (targetUserIds.isEmpty) return {};

    try {
      final entries = await Future.wait(
        targetUserIds.map((userId) async {
          final access = await firestoreService.checkIdCardAccess(
            requesterId: requesterId,
            targetUserId: userId,
          );
          final String status;
          if (access == null) {
            status = 'none';
          } else if (access.status == IdCardAccessStatus.pending) {
            status = 'pending';
          } else if (access.isValidAccess) {
            status = 'approved';
          } else if (access.status == IdCardAccessStatus.expired) {
            status = 'expired';
          } else if (access.status == IdCardAccessStatus.rejected) {
            status = 'rejected';
          } else {
            status = 'none';
          }
          return MapEntry(userId, status);
        }),
      );
      return Map.fromEntries(entries);
    } catch (e) {
      debugPrint('⚠️ 신분증 상태 조회 실패: $e');
      return {};
    }
  }

  /// 신분증 상태 정보 가져오기
  static IdCardStatusInfo getStatusInfo(String status) {
    switch (status) {
      case 'approved':
        return IdCardStatusInfo(
          icon: Icons.verified,
          label: '신분증완료',
          color: AppColors.success,
        );
      case 'pending':
        return IdCardStatusInfo(
          icon: Icons.hourglass_top,
          label: '신분증요청중',
          color: AppColors.warning,
        );
      case 'expired':
        return IdCardStatusInfo(
          icon: Icons.timer_off_outlined,
          label: '신분증만료',
          color: AppColors.grey500,
        );
      case 'rejected':
        return IdCardStatusInfo(
          icon: Icons.cancel_outlined,
          label: '신분증거절',
          color: AppColors.error,
        );
      case 'none':
      default:
        return IdCardStatusInfo(
          icon: Icons.lock_outline,
          label: '신분증미요청',
          color: AppColors.grey400,
        );
    }
  }
  // ═══════════════════════════════════════════════════════════
  // 일괄 신분증 요청 기능
  // ═══════════════════════════════════════════════════════════

  /// 신분증 요청 가능한 사용자 필터링
  /// 
  /// [statusMap] - {userId: 'approved' | 'pending' | 'none'}
  /// [userIds] - 필터링할 사용자 ID 목록
  /// 
  /// 반환: 'none' 상태인 사용자 ID 목록 (요청 가능)
  static List<String> filterRequestableUsers({
    required Map<String, String> statusMap,
    required List<String> userIds,
  }) {
    return userIds.where((uid) {
      final status = statusMap[uid] ?? 'none';
      // 미요청·만료·거절 → 재요청 가능
      return status == 'none' || status == 'expired' || status == 'rejected';
    }).toList();
  }

  /// 일괄 신분증 요청
  /// 
  /// [context] - BuildContext (다이얼로그용)
  /// [firestoreService] - Firestore 서비스
  /// [requester] - 요청자 정보 (현재 로그인한 관리자)
  /// [business] - 사업장 정보
  /// [targets] - 요청 대상 목록 [{uid, name, applicationId?}]
  /// [reason] - 요청 사유
  /// [customReason] - 기타 사유 (reason이 other인 경우)
  /// 
  /// 반환: 성공한 요청 수
  static Future<int> batchRequestIdCard({
    required BuildContext context,
    required FirestoreService firestoreService,
    required Map<String, String> requester,  // {uid, name}
    required Map<String, String> business,   // {id, name}
    required List<Map<String, String>> targets,  // [{uid, name, applicationId?}]
    required IdCardAccessReason reason,
    String? customReason,
  }) async {
    if (targets.isEmpty) return 0;

    int successCount = 0;

    for (final target in targets) {
      try {
        final result = await firestoreService.createIdCardAccessRequest(
          requesterId: requester['uid']!,
          requesterName: requester['name']!,
          requesterBusinessId: business['id']!,
          requesterBusinessName: business['name']!,
          targetUserId: target['uid']!,
          targetUserName: target['name']!,
          reason: reason,
          customReason: customReason,
          applicationId: target['applicationId'],
        );

        if (result != null) {
          successCount++;
        }
      } catch (e) {
        debugPrint('⚠️ 신분증 요청 실패 (${target['name']}): $e');
      }
    }

    return successCount;
  }

  /// 일괄 요청 다이얼로그 표시 (사유 선택 포함)
  /// 
  /// 사용 예:
  /// ```dart
  /// final result = await IdCardHelper.showBatchRequestDialog(
  ///   context: context,
  ///   firestoreService: firestoreService,
  ///   requester: {'uid': user.uid, 'name': user.name},
  ///   business: {'id': businessId, 'name': businessName},
  ///   targets: selectedUsers,
  /// );
  /// if (result > 0) { /* 성공 처리 */ }
  /// ```
  static Future<int> showBatchRequestDialog({
    required BuildContext context,
    required FirestoreService firestoreService,
    required Map<String, String> requester,
    required Map<String, String> business,
    required List<Map<String, String>> targets,
  }) async {
    if (targets.isEmpty) {
      ToastHelper.showWarning('선택된 대상이 없습니다');
      return 0;
    }

    // 1명 vs 여러명 subtitle 분기
    final subtitle = targets.length == 1
        ? '${targets.first['name']}님에게 요청'
        : '${targets.length}명에게 일괄 요청';

    IdCardAccessReason? selectedReason;
    final customReasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return StyledDialog(
            title: '신분증 열람 요청',
            subtitle: subtitle,
            icon: Icons.badge,
            headerColor: AppColors.info,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '신분증 열람 사유를 선택해주세요.',
                  style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                
                // 사유 선택 목록
                ...IdCardAccessRequestModel.reasonOptions.map((option) {
                  final reason = option['value'] as IdCardAccessReason;
                  final label = option['label'] as String;
                  final isSelected = selectedReason == reason;

                  return Container(
                    margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => setDialogState(() => selectedReason = reason),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: ResponsiveHelper.spacing(context, 16),
                            vertical: ResponsiveHelper.spacing(context, 12),
                          ),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.infoBg : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? AppColors.info : AppColors.grey300,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                                color: isSelected ? AppColors.info : AppColors.grey400,
                                size: ResponsiveHelper.iconSize(context, 20),
                              ),
                              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                              Text(
                                label,
                                style: ResponsiveHelper.bodyStyle(context).copyWith(
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                  color: isSelected ? AppColors.info : AppColors.grey700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                
                // 기타 사유 입력
                if (selectedReason == IdCardAccessReason.other) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  TextField(
                    controller: customReasonController,
                    decoration: InputDecoration(
                      hintText: '사유를 입력해주세요',
                      hintStyle: ResponsiveHelper.bodyStyle(context, color: AppColors.grey400),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.info, width: 2),
                      ),
                      contentPadding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
                    ),
                    maxLines: 2,
                  ),
                ],
                
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                
                // 안내 카드
                Container(
                  padding: ResponsiveHelper.cardPadding(context),
                  decoration: BoxDecoration(
                    color: AppColors.infoBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: ResponsiveHelper.iconSize(context, 20), color: AppColors.info),
                      SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                      Expanded(
                        child: Text(
                          '승인 시 7일간 신분증을 열람할 수 있습니다.',
                          style: ResponsiveHelper.smallStyle(context, color: AppColors.infoDark),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              StyledDialogButton.cancel(onPressed: () => Navigator.pop(dialogContext, false)),
              StyledDialogButton.primary(
                text: '요청 보내기',
                backgroundColor: AppColors.info,
                onPressed: selectedReason != null
                    ? () => Navigator.pop(dialogContext, true)
                    : () {},
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true || selectedReason == null) {
      customReasonController.dispose();
      return 0;
    }

    if (!context.mounted) {
      customReasonController.dispose();
      return 0;
    }

    // 일괄 요청 실행
    final successCount = await batchRequestIdCard(
      context: context,
      firestoreService: firestoreService,
      requester: requester,
      business: business,
      targets: targets,
      reason: selectedReason!,
      customReason: selectedReason == IdCardAccessReason.other 
          ? customReasonController.text 
          : null,
    );

    customReasonController.dispose();

    if (successCount > 0) {
      ToastHelper.showSuccess('$successCount명에게 신분증 요청을 보냈습니다');
    }

    return successCount;
  }

  /// 신분증 상태 배지 위젯
  /// 
  /// 사용 예:
  /// ```dart
  /// IdCardHelper.buildStatusBadge(context, 'approved')
  /// IdCardHelper.buildStatusBadge(context, idCardStatusMap[user.uid] ?? 'none')
  /// ```
  static Widget buildStatusBadge(BuildContext context, String status) {
    final info = getStatusInfo(status);
    
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 6),
        vertical: ResponsiveHelper.spacing(context, 2),
      ),
      decoration: BoxDecoration(
        color: info.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            info.icon, 
            size: ResponsiveHelper.iconSize(context, 10), 
            color: info.color,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 3)),
          Text(
            info.label,
            style: ResponsiveHelper.tinyStyle(context, color: info.color).copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// 신분증 상태 배지 (컴팩트 버전 - 아이콘만)
  static Widget buildStatusIcon(BuildContext context, String status, {double size = 16}) {
    final info = getStatusInfo(status);
    
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 4)),
      decoration: BoxDecoration(
        color: info.color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Icon(
        info.icon,
        size: ResponsiveHelper.iconSize(context, size),
        color: info.color,
      ),
    );
  }
}

/// 신분증 상태 정보 클래스
class IdCardStatusInfo {
  final IconData icon;
  final String label;
  final Color color;

  const IdCardStatusInfo({
    required this.icon,
    required this.label,
    required this.color,
  });
}