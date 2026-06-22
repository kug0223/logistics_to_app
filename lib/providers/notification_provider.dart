import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/core/notification_model.dart';
import '../services/firestore_service.dart';

/// 알림 상태 관리 Provider
class NotificationProvider with ChangeNotifier {
  final FirestoreService _firestoreService = FirestoreService();

  // 스트림에서 받은 최신 30건 (31번째가 있으면 hasMore=true)
  List<NotificationModel> _streamNotifications = [];
  // loadMore()로 추가 로드된 오래된 알림
  List<NotificationModel> _additionalNotifications = [];

  bool _isLoading = false;
  bool _hasError = false;
  bool _hasMore = false;
  bool _isLoadingMore = false;
  bool _disposed = false;
  String? _userId;

  StreamSubscription? _notificationSubscription;

  // ── Getters ───────────────────────────────────────────────

  /// 스트림 + 추가 로드된 알림 병합 (중복 제거)
  List<NotificationModel> get notifications {
    if (_additionalNotifications.isEmpty) return _streamNotifications;
    final streamIds = _streamNotifications.map((n) => n.id).toSet();
    final extra = _additionalNotifications.where((n) => !streamIds.contains(n.id));
    return [..._streamNotifications, ...extra];
  }

  int get unreadCount => notifications.where((n) => !n.isRead).length;
  bool get isLoading => _isLoading;
  bool get hasError => _hasError;
  bool get hasUnread => notifications.any((n) => !n.isRead);
  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;
  String? get userId => _userId;

  // ── 초기화 / 정리 ─────────────────────────────────────────

  /// 사용자 설정 및 실시간 리스닝 시작
  void setUser(String userId) {
    if (_disposed) return;
    if (_userId == userId && _notificationSubscription != null) return;

    debugPrint('🔔 [NotificationProvider] 사용자 설정: $userId');
    _userId = userId;
    _startListening();
    // 30일 이상 오래된 알림 정리 (로그인 시 1회, 결과 무시)
    deleteOldNotifications();
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
    _streamNotifications = [];
    _additionalNotifications = [];
    _hasMore = false;
    _isLoadingMore = false;
    notifyListeners();
  }

  /// 실시간 리스닝 시작
  void _startListening() {
    if (_userId == null || _disposed) return;

    // 기존 구독 취소 + 페이지네이션 상태 초기화
    _stopListening();
    _additionalNotifications = [];
    _hasMore = false;
    _isLoadingMore = false;

    debugPrint('🔔 [NotificationProvider] 실시간 리스닝 시작');

    _isLoading = true;
    notifyListeners();

    _notificationSubscription = _firestoreService
        .watchUserNotifications(_userId!)
        .listen(
          (received) {
            if (_disposed) return;
            // [특이사항] limit(31) 패턴: 31건 조회해 31건이면 hasMore=true, 30건만 표시 — length>30 보장 후 sublist 안전
            if (received.length > 30) {
              _streamNotifications = received.sublist(0, 30);
              _hasMore = true;
            } else {
              _streamNotifications = received;
              _hasMore = false;
            }
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

  // ── 페이지네이션 ──────────────────────────────────────────

  /// 스트림 이전 알림 추가 로드
  Future<void> loadMore() async {
    final uid = _userId;
    if (uid == null || !_hasMore || _isLoadingMore || _disposed) return;

    // 현재 로드된 알림 중 가장 오래된 것의 createdAt을 기준으로 이전 알림 로드
    final allCurrent = notifications;
    if (allCurrent.isEmpty) return;
    final oldest = allCurrent.last.createdAt;

    _isLoadingMore = true;
    notifyListeners();

    try {
      final page = await _firestoreService.getOlderNotificationsPaged(
        userId: uid,
        before: oldest,
      );
      if (_disposed) return;
      _additionalNotifications = [..._additionalNotifications, ...page.records];
      _hasMore = page.hasMore;
    } catch (e) {
      debugPrint('❌ 알림 더 보기 실패: $e');
    } finally {
      if (!_disposed) {
        _isLoadingMore = false;
        notifyListeners();
      }
    }
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
    // 스트림 이벤트가 오기 전에 _additionalNotifications도 즉시 반영
    // (스트림은 _streamNotifications만 갱신하므로 _additionalNotifications는 별도 처리 필요)
    if (_additionalNotifications.isNotEmpty) {
      _additionalNotifications =
          _additionalNotifications.map((n) => n.copyWith(isRead: true)).toList();
      notifyListeners();
    }
  }

  /// 개별 알림 삭제
  Future<bool> deleteNotification(String notificationId) async {
    final result = await _firestoreService.deleteNotification(notificationId);
    if (result && _additionalNotifications.isNotEmpty) {
      _additionalNotifications.removeWhere((n) => n.id == notificationId);
      notifyListeners();
    }
    return result;
  }

  /// 오래된 알림 삭제 (30일 이상)
  Future<int> deleteOldNotifications() async {
    if (_userId == null) return 0;
    return _firestoreService.deleteOldNotifications(_userId!);
  }

  // ── 리소스 정리 ───────────────────────────────────────────

  @override
  void dispose() {
    _disposed = true;
    _stopListening();
    super.dispose();
  }
}
