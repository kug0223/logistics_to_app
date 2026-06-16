part of '../firestore_service.dart';

// ═══════════════════════════════════════════════════════════
// 알림/리뷰/신분증 관리 (Notification & Review Management)
// ═══════════════════════════════════════════════════════════

/// 알림 커서 기반 페이지네이션 결과
class NotificationPage {
  final List<NotificationModel> records;
  final bool hasMore;
  const NotificationPage({required this.records, required this.hasMore});
}

extension NotificationFirestore on FirestoreService {
  // ═══════════════════════════════════════════════════════════
  // 알림 관리 (Notification Management)
  // ═══════════════════════════════════════════════════════════

  /// 알림 생성
  ///
  /// [D01 동시성 설계] 알림 중복 발송 가능성:
  /// `add()`는 매번 새 document를 생성하므로, 호출 측이 실수로 두 번 호출하면
  /// 동일 내용의 알림 2개가 저장된다. 현재 각 이벤트 핸들러(확정, 취소 등)에서
  /// 단 1회만 호출하도록 설계되어 있으므로 실질적 중복 위험은 없다.
  /// 완전한 방어가 필요하다면 (userId + type + referenceId) 복합 키로 upsert 전환 필요.
  ///
  /// [D02 읽음 처리 동시성] markNotificationAsRead는 트랜잭션 없이 update.
  /// isRead: true 덮어쓰기는 멱등(idempotent)이므로 동시 요청도 안전하다 — 의도된 설계.
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
          .where('userId', isEqualTo: userId);

      // isRead 필터는 orderBy 전에 적용 (복합 인덱스: userId + isRead + createdAt)
      if (unreadOnly) {
        query = query.where('isRead', isEqualTo: false);
      }

      query = query.orderBy('createdAt', descending: true).limit(limit);
      
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

  /// 모든 알림 읽음 처리 (Firestore batch 500개 제한 대응: 청크 분할)
  Future<bool> markAllNotificationsAsRead(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .where('isRead', isEqualTo: false)
          .get();

      const chunkSize = 500;
      for (int i = 0; i < snapshot.docs.length; i += chunkSize) {
        final batch = _firestore.batch();
        final end = (i + chunkSize).clamp(0, snapshot.docs.length);
        for (int j = i; j < end; j++) {
          batch.update(snapshot.docs[j].reference, {
            'isRead': true,
            'readAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }

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
          .limit(500) // 1회 호출당 최대 500건 처리 — 메모리 보호
          .get();
      
      const chunkSize = 500;
      for (int i = 0; i < snapshot.docs.length; i += chunkSize) {
        final batch = _firestore.batch();
        final end = (i + chunkSize).clamp(0, snapshot.docs.length);
        for (int j = i; j < end; j++) {
          batch.delete(snapshot.docs[j].reference);
        }
        await batch.commit();
      }
      debugPrint('✅ ${snapshot.docs.length}개 오래된 알림 삭제');
      return snapshot.docs.length;
    } catch (e) {
      debugPrint('❌ 오래된 알림 삭제 실패: $e');
      return 0;
    }
  }

  /// 알림 스트림 (실시간) — limit(31)로 hasMore 감지
  ///
  /// 31건 수신 시 NotificationProvider가 30건만 표시하고 _hasMore=true 설정.
  /// 31건 미만이면 _hasMore=false — 더 이상 오래된 알림 없음.
  Stream<List<NotificationModel>> watchUserNotifications(String userId) {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff))
        .orderBy('createdAt', descending: true)
        .limit(31)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => NotificationModel.fromFirestore(doc))
            .toList());
  }

  /// 스트림 범위 이전 알림 페이지 조회 — NotificationProvider.loadMore() 전용
  Future<NotificationPage> getOlderNotificationsPaged({
    required String userId,
    required DateTime before,
    int pageSize = 30,
  }) async {
    try {
      final snap = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .where('createdAt', isLessThan: Timestamp.fromDate(before))
          .orderBy('createdAt', descending: true)
          .limit(pageSize + 1)
          .get();
      final hasMore = snap.docs.length > pageSize;
      final docs = hasMore ? snap.docs.sublist(0, pageSize) : snap.docs;
      return NotificationPage(
        records: docs.map(NotificationModel.fromFirestore).toList(),
        hasMore: hasMore,
      );
    } catch (e) {
      debugPrint('❌ 이전 알림 조회 실패: $e');
      return const NotificationPage(records: [], hasMore: false);
    }
  }

  /// 읽지 않은 알림 개수 — NotificationProvider.unreadCount에서 파생 (별도 쿼리 불필요)
  /// Deprecated: NotificationProvider.unreadCount getter를 사용하세요.

}