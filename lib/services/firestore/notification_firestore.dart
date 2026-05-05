part of '../firestore_service.dart';

// ═══════════════════════════════════════════════════════════
// 알림/리뷰/신분증 관리 (Notification & Review Management)
// ═══════════════════════════════════════════════════════════

extension NotificationFirestore on FirestoreService {
  // ═══════════════════════════════════════════════════════════
  // 알림 관리 (Notification Management)
  // ═══════════════════════════════════════════════════════════

  /// 알림 생성
  Future<String?> createNotification(NotificationModel notification) async {
    try {
      final docRef = await _firestore.collection('notifications').add(
        notification.toMap(),
      );
      debugPrint('✅ 알림 생성: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      debugPrint('❌ 알림 생성 실패: $e');
      return null;
    }
  }

  /// 사용자 알림 목록 조회
  Future<List<NotificationModel>> getUserNotifications(
    String userId, {
    int limit = 50,
    bool unreadOnly = false,
  }) async {
    try {
      Query query = _firestore
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .limit(limit);
      
      if (unreadOnly) {
        query = query.where('isRead', isEqualTo: false);
      }
      
      final snapshot = await query.get();
      
      return snapshot.docs
          .map((doc) => NotificationModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('❌ 알림 조회 실패: $e');
      return [];
    }
  }

  /// 읽지 않은 알림 개수
  Future<int> getUnreadNotificationCount(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .where('isRead', isEqualTo: false)
          .count()
          .get();
      
      return snapshot.count ?? 0;
    } catch (e) {
      debugPrint('❌ 읽지 않은 알림 개수 조회 실패: $e');
      return 0;
    }
  }

  /// 알림 읽음 처리
  Future<bool> markNotificationAsRead(String notificationId) async {
    try {
      await _firestore.collection('notifications').doc(notificationId).update({
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('❌ 알림 읽음 처리 실패: $e');
      return false;
    }
  }

  /// 개별 알림 삭제
  Future<bool> deleteNotification(String notificationId) async {
    try {
      await _firestore.collection('notifications').doc(notificationId).delete();
      debugPrint('✅ 알림 삭제: $notificationId');
      return true;
    } catch (e) {
      debugPrint('❌ 알림 삭제 실패: $e');
      return false;
    }
  }

  /// 모든 알림 읽음 처리

  /// 모든 알림 읽음 처리
  Future<bool> markAllNotificationsAsRead(String userId) async {
    try {
      final batch = _firestore.batch();
      
      final snapshot = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .where('isRead', isEqualTo: false)
          .get();
      
      for (var doc in snapshot.docs) {
        batch.update(doc.reference, {
          'isRead': true,
          'readAt': FieldValue.serverTimestamp(),
        });
      }
      
      await batch.commit();
      debugPrint('✅ ${snapshot.docs.length}개 알림 읽음 처리');
      return true;
    } catch (e) {
      debugPrint('❌ 전체 읽음 처리 실패: $e');
      return false;
    }
  }

  /// 오래된 알림 삭제 (30일 이상)
  Future<int> deleteOldNotifications(String userId) async {
    try {
      final cutoffDate = DateTime.now().subtract(const Duration(days: 30));
      
      final snapshot = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .where('createdAt', isLessThan: Timestamp.fromDate(cutoffDate))
          .get();
      
      final batch = _firestore.batch();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      
      await batch.commit();
      debugPrint('✅ ${snapshot.docs.length}개 오래된 알림 삭제');
      return snapshot.docs.length;
    } catch (e) {
      debugPrint('❌ 오래된 알림 삭제 실패: $e');
      return 0;
    }
  }

  /// 알림 스트림 (실시간)
  Stream<List<NotificationModel>> watchUserNotifications(String userId) {
    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => NotificationModel.fromFirestore(doc))
            .toList());
  }

  /// 읽지 않은 알림 개수 스트림 (실시간)
  Stream<int> watchUnreadNotificationCount(String userId) {
    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

}