// lib/services/badge_service.dart

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// 배지 자동 획득·재계산 서비스
///
/// [CF-MIGRATED 2026-07-17] callableEvaluateAndUpdateBadges CF 이전
/// - 이전: attendance 직접 list 쿼리 (allow list: if false → PERMISSION_DENIED)
///         users/{uid}.badges 직접 write (슈퍼어드민 blocked 필드 → PERMISSION_DENIED)
/// - 현재: Admin SDK 경유 CF에서 모든 평가·write 처리
///
/// 배지는 상향 누적 원칙 — 한번 획득한 배지는 조건이 낮아져도 박탈하지 않는다.
///
/// 호출 시점:
/// - 슈퍼관리자 신뢰도 수동 조정 후 (all_users_screen._adjustTrustScore)
class BadgeService {
  /// uid 사용자의 배지 조건을 평가해 신규 획득 배지를 Firestore에 추가한다.
  /// 반환값: 이번 호출로 새로 획득된 배지 ID 목록 (기존 보유 배지 제외)
  /// 실패 시 예외를 rethrow — 호출자가 처리 방식(무시/Toast/로그)을 결정한다.
  Future<List<String>> evaluateAndUpdateBadgesForUser(String uid) async {
    final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
        .httpsCallable('callableEvaluateAndUpdateBadges',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
    final result = await callable.call<Map<String, dynamic>>({'uid': uid});
    final newBadges =
        (result.data['newBadges'] as List?)?.cast<String>() ?? [];
    if (newBadges.isNotEmpty) {
      debugPrint('✅ [BadgeService] 신규 배지 획득 ($uid): $newBadges');
    }
    return newBadges;
  }
}
