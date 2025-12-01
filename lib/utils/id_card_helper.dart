// lib/utils/id_card_helper.dart
// 신분증 관련 공통 헬퍼

import 'package:flutter/material.dart';
import '../models/core/id_card_access_request_model.dart';
import '../services/firestore_service.dart';
import '../theme/app_colors.dart';
import 'responsive_helper.dart';

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
    final Map<String, String> statusMap = {};
    
    try {
      for (final userId in targetUserIds) {
        final access = await firestoreService.checkIdCardAccess(
          requesterId: requesterId,
          targetUserId: userId,
        );
        
        if (access == null) {
          statusMap[userId] = 'none';
        } else if (access.status == IdCardAccessStatus.pending) {
          statusMap[userId] = 'pending';
        } else if (access.isValidAccess) {
          statusMap[userId] = 'approved';
        } else {
          statusMap[userId] = 'none';
        }
      }
    } catch (e) {
      print('⚠️ 신분증 상태 조회 실패: $e');
    }
    
    return statusMap;
  }

  /// 신분증 상태 정보 가져오기
  static IdCardStatusInfo getStatusInfo(String status) {
    switch (status) {
      case 'approved':
        return IdCardStatusInfo(
          icon: Icons.verified,
          label: '신분증',
          color: AppColors.success,
        );
      case 'pending':
        return IdCardStatusInfo(
          icon: Icons.hourglass_top,
          label: '요청중',
          color: AppColors.warning,
        );
      case 'none':
      default:
        return IdCardStatusInfo(
          icon: Icons.lock_outline,
          label: '미요청',
          color: AppColors.grey400,
        );
    }
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
        color: info.color.withOpacity(0.15),
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
        color: info.color.withOpacity(0.15),
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