import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/core/notification_model.dart';
import '../services/firestore_service.dart';

/// 알림 상태 관리 Provider
class NotificationProvider with ChangeNotifier {
  final FirestoreService _firestoreService = FirestoreService();
  
  List<NotificationModel> _notifications = [];
  int _unreadCount = 0;
  bool _isLoading = false;
  String? _userId;
  
  StreamSubscription? _notificationSubscription;
  StreamSubscription? _unreadCountSubscription;
  
  // ═══════════════════════════════════════════════════════════
  // Getters
  // ═══════════════════════════════════════════════════════════
  
  List<NotificationModel> get notifications => _notifications;
  int get unreadCount => _unreadCount;
  bool get isLoading => _isLoading;
  bool get hasUnread => _unreadCount > 0;
  String? get userId => _userId;
  
  // ═══════════════════════════════════════════════════════════
  // 초기화 / 정리
  // ═══════════════════════════════════════════════════════════
  
  /// 사용자 설정 및 실시간 리스닝 시작
  void setUser(String userId) {
    if (_userId == userId) return;
    
    print('🔔 [NotificationProvider] 사용자 설정: $userId');
    _userId = userId;
    _startListening();
  }
  
  /// 로그아웃 시 정리
  void clearUser() {
    print('🔔 [NotificationProvider] 사용자 정리');
    _stopListening();
    _userId = null;
    _notifications = [];
    _unreadCount = 0;
    notifyListeners();
  }
  
  /// 실시간 리스닝 시작
  void _startListening() {
    if (_userId == null) return;
    
    // 기존 구독 취소
    _stopListening();
    
    print('🔔 [NotificationProvider] 실시간 리스닝 시작');
    
    // 알림 목록 리스닝
    _notificationSubscription = _firestoreService
        .watchUserNotifications(_userId!)
        .listen(
          (notifications) {
            _notifications = notifications;
            notifyListeners();
          },
          onError: (e) {
            print('❌ 알림 스트림 에러: $e');
          },
        );
    
    // 읽지 않은 개수 리스닝
    _unreadCountSubscription = _firestoreService
        .watchUnreadNotificationCount(_userId!)
        .listen(
          (count) {
            _unreadCount = count;
            notifyListeners();
          },
          onError: (e) {
            print('❌ 읽지않은 알림 개수 스트림 에러: $e');
          },
        );
  }
  
  /// 리스닝 중지
  void _stopListening() {
    _notificationSubscription?.cancel();
    _unreadCountSubscription?.cancel();
    _notificationSubscription = null;
    _unreadCountSubscription = null;
  }
  
  // ═══════════════════════════════════════════════════════════
  // 알림 액션
  // ═══════════════════════════════════════════════════════════
  
  /// 알림 읽음 처리
  Future<void> markAsRead(String notificationId) async {
    await _firestoreService.markNotificationAsRead(notificationId);
  }
  
  /// 모든 알림 읽음 처리
  Future<void> markAllAsRead() async {
    if (_userId == null) return;
    await _firestoreService.markAllNotificationsAsRead(_userId!);
  }
  
  /// 오래된 알림 삭제 (30일 이상)
  Future<int> deleteOldNotifications() async {
    if (_userId == null) return 0;
    return await _firestoreService.deleteOldNotifications(_userId!);
  }
  
  // ═══════════════════════════════════════════════════════════
  // 리소스 정리
  // ═══════════════════════════════════════════════════════════
  
  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }
}