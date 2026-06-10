import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/core/notification_model.dart';
import '../services/firestore_service.dart';

/// 알림 상태 관리 Provider
class NotificationProvider with ChangeNotifier {
  final FirestoreService _firestoreService = FirestoreService();
  
  List<NotificationModel> _notifications = [];
  bool _isLoading = false;
  bool _hasError = false;
  bool _disposed = false;
  String? _userId;

  StreamSubscription? _notificationSubscription;

  // ── Getters ───────────────────────────────────────────────

  List<NotificationModel> get notifications => _notifications;
  int get unreadCount => _notifications.where((n) => !n.isRead).length;
  bool get isLoading => _isLoading;
  bool get hasError => _hasError;
  bool get hasUnread => _notifications.any((n) => !n.isRead);
  String? get userId => _userId;
  
  // ── 초기화 / 정리 ─────────────────────────────────────────
  
  /// 사용자 설정 및 실시간 리스닝 시작
  void setUser(String userId) {
    if (_disposed) return;
    if (_userId == userId && _notificationSubscription != null) return;

    debugPrint('🔔 [NotificationProvider] 사용자 설정: $userId');
    _userId = userId;
    _startListening();
  }
  
  /// 스트림 에러 후 재시도
  void retry() {
    if (_userId == null || _disposed) return;
    _hasError = false;
    _startListening();
  }

  /// 로그아웃 시 정리
  void clearUser() {
    if (_disposed) return;
    debugPrint('🔔 [NotificationProvider] 사용자 정리');
    _stopListening();
    _userId = null;
    _notifications = [];
    notifyListeners();
  }
  
  /// 실시간 리스닝 시작
  void _startListening() {
    if (_userId == null || _disposed) return;
    
    // 기존 구독 취소
    _stopListening();
    
    debugPrint('🔔 [NotificationProvider] 실시간 리스닝 시작');
    
    // 알림 목록 리스닝
    _isLoading = true;
    notifyListeners();

    _notificationSubscription = _firestoreService
        .watchUserNotifications(_userId!)
        .listen(
          (notifications) {
            if (_disposed) return;
            _notifications = notifications;
            _isLoading = false;
            _hasError = false;
            notifyListeners();
          },
          onError: (e) {
            if (_disposed) return;
            debugPrint('❌ 알림 스트림 에러: $e');
            _isLoading = false;
            _hasError = true;
            notifyListeners();
          },
        );
    
  }

  /// 리스닝 중지
  void _stopListening() {
    _notificationSubscription?.cancel();
    _notificationSubscription = null;
  }
  
  // ── 알림 액션 ─────────────────────────────────────────────
  
  /// 알림 읽음 처리
  Future<void> markAsRead(String notificationId) async {
    await _firestoreService.markNotificationAsRead(notificationId);
  }
  
  /// 모든 알림 읽음 처리
  Future<void> markAllAsRead() async {
    if (_userId == null) return;
    await _firestoreService.markAllNotificationsAsRead(_userId!);
  }
  
  /// 개별 알림 삭제
  Future<bool> deleteNotification(String notificationId) async {
    return await _firestoreService.deleteNotification(notificationId);
  }
  
  /// 오래된 알림 삭제 (30일 이상)
  Future<int> deleteOldNotifications() async {
    if (_userId == null) return 0;
    return await _firestoreService.deleteOldNotifications(_userId!);
  }
  
  // ── 리소스 정리 ───────────────────────────────────────────
  
  @override
  void dispose() {
    _disposed = true;
    _stopListening();
    super.dispose();
  }
}