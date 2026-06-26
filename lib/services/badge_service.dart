// lib/services/badge_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/settings/trust_settings_model.dart';
import '../models/core/user_model.dart';
import '../models/core/attendance_model.dart';

/// 배지 자동 획득·재계산 서비스
///
/// 배지는 상향 누적 원칙 — 한번 획득한 배지는 조건이 낮아져도 박탈하지 않는다.
/// 신규 획득 배지만 arrayUnion으로 추가하고, 기존 badges 배열은 건드리지 않는다.
/// 슈퍼관리자가 직접 badges 배열을 편집하는 케이스는 UI 단에서 별도 처리.
///
/// 호출 시점:
/// - 슈퍼관리자 신뢰도 수동 조정 후 (all_users_screen._adjustTrustScore)
/// - 월간 리뷰/출근 완료 후 (trust_score_service 이벤트 핸들러에서 fire-and-forget)
class BadgeService {
  static const _userCol = 'users';
  static const _attendanceCol = 'attendance';

  final FirebaseFirestore _firestore;

  BadgeService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// uid 사용자의 배지 조건을 평가해 신규 획득 배지를 Firestore에 추가한다.
  /// 반환값: 이번 호출로 새로 획득된 배지 ID 목록 (기존 보유 배지 제외)
  Future<List<String>> evaluateAndUpdateBadgesForUser(String uid) async {
    try {
      final userDoc = await _firestore.collection(_userCol).doc(uid).get();
      if (!userDoc.exists) return [];
      final user = UserModel.fromMap(userDoc.data()!, uid);
      return _evaluateAndSave(uid, user);
    } catch (e) {
      debugPrint('⚠️ [BadgeService] 배지 평가 실패 ($uid): $e');
      return [];
    }
  }

  Future<List<String>> _evaluateAndSave(String uid, UserModel user) async {
    final allBadges = BadgeModel.defaultBadges().where((b) => b.isActive).toList();
    final currentIds = Set<String>.from(user.badges);
    final newlyEarned = <String>[];

    for (final badge in allBadges) {
      if (currentIds.contains(badge.id)) continue;
      final earned = await _check(uid, user, badge);
      if (earned) newlyEarned.add(badge.id);
    }

    if (newlyEarned.isNotEmpty) {
      await _firestore.collection(_userCol).doc(uid).update({
        'badges': FieldValue.arrayUnion(newlyEarned),
      });
      debugPrint('✅ [BadgeService] 신규 배지 획득 ($uid): $newlyEarned');
    }

    return newlyEarned;
  }

  Future<bool> _check(String uid, UserModel user, BadgeModel badge) async {
    return switch (badge.conditionType) {
      BadgeConditionType.minScore => _checkMinScore(user, badge),
      BadgeConditionType.workDays => await _checkWorkDays(uid, user, badge),
      BadgeConditionType.consecutive => await _checkConsecutive(uid, badge),
      BadgeConditionType.monthlyPerfect => await _checkMonthlyPerfect(uid),
    };
  }

  // ── 조건 평가 ──────────────────────────────────────────────────

  bool _checkMinScore(UserModel user, BadgeModel badge) {
    if (user.trustScore < badge.conditionValue) { return false; }
    if (badge.minWorkDaysRequired != null &&
        user.totalWorkDays < badge.minWorkDaysRequired!) { return false; }
    if (badge.maxNoShowAllowed != null &&
        user.noShowCount > badge.maxNoShowAllowed!) { return false; }
    if (badge.minRatingRequired != null &&
        user.averageRating < badge.minRatingRequired!) { return false; }
    return true;
  }

  Future<bool> _checkWorkDays(String uid, UserModel user, BadgeModel badge) async {
    if (badge.workType != null) {
      // specialty 배지: 특정 업무유형 완료 근무일수를 attendance 컬렉션에서 집계
      // (userId, workType, status) 복합 인덱스 필요 — firestore.indexes.json에 추가 완료.
      final countSnap = await _firestore
          .collection(_attendanceCol)
          .where('userId', isEqualTo: uid)
          .where('workType', isEqualTo: badge.workType)
          .where('status', whereIn: [
            AttendanceModel.statusPresent,
            AttendanceModel.statusLate,
            AttendanceModel.statusEarlyLeave,
          ])
          .count()
          .get();
      return (countSnap.count ?? 0) >= badge.conditionValue;
    }
    // experience 배지: user.totalWorkDays로 직접 평가
    return user.totalWorkDays >= badge.conditionValue;
  }

  Future<bool> _checkConsecutive(String uid, BadgeModel badge) async {
    // 최근 출근 기록을 역순으로 조회해 연속 무지각 횟수 계산
    // attendance 컬렉션에 (userId, workDate) 복합 인덱스 필요.
    final snap = await _firestore
        .collection(_attendanceCol)
        .where('userId', isEqualTo: uid)
        .orderBy('workDate', descending: true)
        .limit(badge.conditionValue + 5)
        .get();

    int streak = 0;
    for (final doc in snap.docs) {
      final status = doc.data()['status'] as String?;
      if (status == AttendanceModel.statusPresent ||
          status == AttendanceModel.statusEarlyLeave) {
        // statusEarlyLeave는 출근 사실로 인정해 streak 포함.
        //           statusLate는 성실 연속으로 불인정 → else에서 break.
        //           (정책: 조기퇴근 = 출근 인정, 지각 = 연속 출근 배지 불인정)
        streak++;
        if (streak >= badge.conditionValue) return true;
      } else {
        // late / absent / NO_SHOW → 연속 중단
        break;
      }
    }
    return false;
  }

  Future<bool> _checkMonthlyPerfect(String uid) async {
    // 전월 1일 ~ 전월 말일 기간의 출근 기록 전부 present/early_leave이어야 달성
    final now = DateTime.now();
    final firstOfLastMonth = DateTime(now.year, now.month - 1, 1);
    final firstOfThisMonth = DateTime(now.year, now.month, 1);

    final snap = await _firestore
        .collection(_attendanceCol)
        .where('userId', isEqualTo: uid)
        .where('workDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(firstOfLastMonth))
        .where('workDate', isLessThan: Timestamp.fromDate(firstOfThisMonth))
        .get();

    if (snap.docs.isEmpty) return false;

    return snap.docs.every((doc) {
      final status = doc.data()['status'] as String?;
      return status != AttendanceModel.statusAbsent &&
          status != AttendanceModel.statusNoShow;
    });
  }
}
