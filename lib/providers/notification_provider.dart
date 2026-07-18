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
  bool _loadMoreFailed = false;
  bool _disposed = false;
  String? _userId;
  // 구독 세대 카운터: reload() 시 증가 → 구독 콜백·loadMore가 stale 여부 판단에 사용
  int _generation = 0;

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
  bool get loadMoreFailed => _loadMoreFailed;
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

  /// 스트림 에러 후 재시도 (에러 상태에서만 재연결)
  void retry() {
    if (_userId == null || _disposed) return;
    if (!_hasError && _notificationSubscription != null) return;
    _hasError = false;
    _startListening();
  }

  /// pull-to-refresh: 항상 스트림 재연결
  void reload() {
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
    _isLoading = false;
    _hasError = false;
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

    // 세대 증가: 이 구독 이전에 발생한 콜백·loadMore 결과를 무효화
    final int myGeneration = ++_generation;

    debugPrint('🔔 [NotificationProvider] 실시간 리스닝 시작 (gen=$myGeneration)');

    _isLoading = true;
    notifyListeners();

    _notificationSubscription = _firestoreService
        .watchUserNotifications(_userId!)
        .listen(
          (received) {
            // stale 콜백 차단: reload() 이후 구 구독이 마지막 버퍼 이벤트를 전달할 수 있음
            if (_disposed || myGeneration != _generation) return;
            // limit(31) 패턴: 31건 조회해 31건이면 hasMore=true, 30건만 표시 — length>30 보장 후 sublist 안전
            if (received.length > 30) {
              _streamNotifications = received.sublist(0, 30);
              _hasMore = true;
            } else {
              _streamNotifications = received;
              // additionalNotifications가 이미 로드된 경우 loadMore 결과를 유지
              if (_additionalNotifications.isEmpty) _hasMore = false;
            }
            _isLoading = false;
            _hasError = false;
            notifyListeners();
          },
          onError: (e) {
            if (_disposed || myGeneration != _generation) return;
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
    _loadMoreFailed = false;
    notifyListeners();

    // 세대 스냅샷: await 완료 후 reload()가 발생했으면 결과 버림
    final int genSnapshot = _generation;
    try {
      final page = await _firestoreService.getOlderNotificationsPaged(
        userId: uid,
        before: oldest,
      );
      // reload()가 _additionalNotifications를 이미 초기화한 경우 덮어쓰지 않음
      if (_disposed || genSnapshot != _generation) return;
      _additionalNotifications = [..._additionalNotifications, ...page.records];
      _hasMore = page.hasMore;
    } catch (e) {
      debugPrint('❌ 알림 더 보기 실패: $e');
      // [GEN-FIX] reload()로 세대가 바뀐 경우 stale 에러 배너 표시 차단
      if (!_disposed && genSnapshot == _generation) {
        _loadMoreFailed = true;
      }
    } finally {
      if (!_disposed) {
        _isLoadingMore = false;
        notifyListeners();
      }
    }
  }

  // ── 알림 액션 ─────────────────────────────────────────────

  /// 알림 읽음 처리 (로컬 상태 즉시 반영 — 스트림 이벤트 지연 보완)
  Future<void> markAsRead(String notificationId) async {
    if (_userId == null) return;
    try {
      await _firestoreService.markNotificationAsRead(_userId!, notificationId);
    } catch (e) {
      // Firestore 쓰기 실패 시 로컬 상태를 변경하지 않고 조용히 종료
      // (서버·로컬 불일치 방지)
      debugPrint('markAsRead Firestore 실패 [$notificationId]: $e');
      return;
    }
    if (_disposed) return;
    bool changed = false;
    _streamNotifications = _streamNotifications.map((n) {
      if (n.id == notificationId && !n.isRead) {
        changed = true;
        return n.copyWith(isRead: true);
      }
      return n;
    }).toList();
    if (_additionalNotifications.isNotEmpty) {
      _additionalNotifications = _additionalNotifications.map((n) {
        if (n.id == notificationId && !n.isRead) {
          changed = true;
          return n.copyWith(isRead: true);
        }
        return n;
      }).toList();
    }
    if (changed) notifyListeners();
  }

  /// 모든 알림 읽음 처리 — true: 성공, false: 실패
  Future<bool> markAllAsRead() async {
    // [ASYNC-GAP] clearUser()와 경쟁 조건 방지 — await 이전에 uid 캡처
    final uid = _userId;
    if (uid == null) return false;
    final success = await _firestoreService.markAllNotificationsAsRead(uid);
    if (_disposed) return false;
    // 스트림 이벤트가 오기 전에 _additionalNotifications도 즉시 반영
    if (_additionalNotifications.isNotEmpty) {
      _additionalNotifications =
          _additionalNotifications.map((n) => n.copyWith(isRead: true)).toList();
      notifyListeners();
    }
    return success;
  }

  void clearLoadMoreError() {
    if (_loadMoreFailed && !_disposed) {
      _loadMoreFailed = false;
      notifyListeners();
    }
  }

  /// 개별 알림 삭제
  Future<bool> deleteNotification(String notificationId) async {
    // [ASYNC-GAP] clearUser()와 경쟁 조건 방지 — await 이전에 uid 캡처
    final uid = _userId;
    if (uid == null) return false;
    final result = await _firestoreService.deleteNotification(uid, notificationId);
    if (_disposed) return result;
    if (result && _additionalNotifications.isNotEmpty) {
      _additionalNotifications.removeWhere((n) => n.id == notificationId);
      notifyListeners();
    }
    return result;
  }

  /// 오래된 알림 삭제 (30일 이상)
  Future<int> deleteOldNotifications() async {
    // [ASYNC-GAP] clearUser()와 경쟁 조건 방지 — await 이전에 uid 캡처
    final uid = _userId;
    if (uid == null) return 0;
    return _firestoreService.deleteOldNotifications(uid);
  }

  // ── 리소스 정리 ───────────────────────────────────────────

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopListening();
    super.dispose();
  }
}
