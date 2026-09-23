import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/core/notification_model.dart';
import '../services/firestore_service.dart';
import '../utils/notification_retention.dart';

/// 알림 상태 관리 Provider
class NotificationProvider with ChangeNotifier {
  final FirestoreService _firestoreService = FirestoreService();

  // 스트림에서 받은 최신 30건 (31번째가 있으면 hasMore=true)
  List<NotificationModel> _streamNotifications = [];
  // loadMore()로 추가 로드된 오래된 알림
  List<NotificationModel> _additionalNotifications = [];
  // notifications 병합 결과 캐시 — 두 소스 중 하나가 바뀔 때만 재계산
  List<NotificationModel>? _mergedCache;

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

  /// 스트림 + 추가 로드된 알림 병합 (중복 제거) — 소스 변경 시에만 재계산
  ///
  /// [R7-P1-9 §21] visible window와 [R7-P1-8 §18] 삭제 대기 숨김을 **여기
  /// 한 곳에서** 적용한다. 목록·안읽음 수·배지가 모두 이 getter를 지나므로,
  /// 화면마다 따로 거르면 "목록에는 없는데 배지 숫자에는 남아 있는" 상태가
  /// 생긴다.
  List<NotificationModel> get notifications => _mergedCache ??= _buildMerged();
  List<NotificationModel> _buildMerged() {
    final now = DateTime.now();
    final streamIds = _streamNotifications.map((n) => n.id).toSet();
    final all = _additionalNotifications.isEmpty
        ? _streamNotifications
        : [
            ..._streamNotifications,
            ..._additionalNotifications.where((n) => !streamIds.contains(n.id)),
          ];
    if (_pendingDeleteIds.isEmpty) {
      // 창만 적용하면 되는 흔한 경우 — 전부 창 안이면 원본을 그대로 돌려준다.
      if (all.every((n) =>
          NotificationRetention.isVisible(
              n.createdAtKnown ? n.createdAt : null, now))) {
        return all;
      }
    }
    return all
        .where((n) => !_pendingDeleteIds.contains(n.id))
        .where((n) => NotificationRetention.isVisible(
            n.createdAtKnown ? n.createdAt : null, now))
        .toList();
  }
  void _invalidateCache() => _mergedCache = null;

  List<NotificationModel> get unreadNotifications => notifications.where((n) => !n.isRead).toList();
  List<NotificationModel> get adminNotifications  => notifications.where((n) => kAdminNotifTypes.contains(n.type)).toList();
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
    // 오래된 알림 정리 (로그인 시 1회, 결과 무시).
    // [R7-P1-9] 기준은 NotificationRetention.visibleDays — 화면이 보여 주는
    //   기간과 같다. 이 job이 화면보다 짧게 지우면 창은 말뿐이 된다.
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
    // [R7-P1-8 §18] 사용자는 이미 지운 것으로 알고 있다 — 예약을 버리면
    //   다음 로그인에 그 알림이 되돌아온다.
    flushPendingDeletes();
    _stopListening();
    _userId = null;
    _streamNotifications = [];
    _additionalNotifications = [];
    _invalidateCache();
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
    _invalidateCache();
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
            _invalidateCache();
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

    // [R7-P1-9 §21] pagination은 visible window 안에서만 돈다.
    //   창 경계에 닿았는데도 `더 보기`가 남아 있으면, 눌러도 아무것도
    //   나타나지 않는 버튼이 된다(불러오긴 했는데 전부 걸러지므로).
    final cutoff = NotificationRetention.cutoffFrom(DateTime.now());
    if (!oldest.isAfter(cutoff)) {
      _hasMore = false;
      notifyListeners();
      return;
    }

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
      _invalidateCache();
      // [R7-P1-9 §21] 받아 온 페이지가 전부 창 밖이면 더 눌러도 소용없다.
      //   서버가 `hasMore: true`라고 해도 그것은 문서가 더 있다는 뜻이지
      //   **보여 줄 것이 더 있다**는 뜻이 아니다.
      final anyVisible = page.records.any((n) => NotificationRetention.isVisible(
          n.createdAtKnown ? n.createdAt : null, DateTime.now()));
      _hasMore = page.hasMore && (page.records.isEmpty || anyVisible);
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
    if (changed) { _invalidateCache(); notifyListeners(); }
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
      _invalidateCache();
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

  /// 개별 알림 삭제 — **즉시 커밋**. 되돌릴 수 없다.
  ///
  /// Undo가 필요한 사용자 경로는 [deleteNotificationDeferred]를 쓴다.
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

  // ── [R7-P1-8 §18] 삭제 + 실행 취소 ──────────────────────────────────────
  //
  // ── 왜 "복원"이 아니라 "지연 커밋"인가 ─────────────────────────────────
  //
  // 되돌리는 방법은 둘이었다.
  //
  //   (A) 지금 지우고, Undo를 누르면 같은 문서를 다시 쓴다
  //   (B) 화면에서만 치우고, 유예 시간이 지나면 그때 지운다
  //
  // (A)는 **클라이언트가 알림 문서를 만드는** 일이다. 알림은 CF가 쓰는
  // 문서이고 클라이언트는 읽기·읽음표시·삭제만 한다. 복원을 위해 create
  // 권한을 열면, 그 권한은 복원에만 쓰이지 않는다 — 사용자가 자기 자신에게
  // 임의의 알림을 만들어 넣을 수 있게 된다. 그리고 복원된 문서는 CF가 쓴
  // 원본과 같다는 보장이 없다(서버 타임스탬프·CF가 나중에 추가한 필드).
  //
  // 그래서 (B)다. 유예 창 안에서는 아무것도 지워지지 않았으므로, Undo는
  // 타이머를 끄는 것으로 끝난다. 복원할 것이 없다 — 애초에 잃지 않았다.
  //
  // 알려진 한계: 유예 창 안에 앱이 죽으면 커밋이 일어나지 않아 알림이
  // 다시 보인다. 실패 방향이 **지우지 않는 쪽**이라 그대로 둔다.
  // 잘못 지워 잃는 것보다 안 지워져 다시 보이는 편이 낫다.

  /// 커밋 대기 중인 삭제. 화면에서는 이미 사라져 있다.
  final Map<String, Timer> _pendingDeletes = {};
  Set<String> get _pendingDeleteIds => _pendingDeletes.keys.toSet();

  /// Undo를 누를 수 있는 시간.
  static const Duration undoWindow = Duration(seconds: 5);

  /// 삭제를 예약한다. 화면에서는 즉시 사라지고, [undoWindow] 뒤에 커밋된다.
  ///
  /// 같은 알림을 다시 삭제하면 기존 예약을 유지한다 — 타이머를 갱신해
  /// 커밋을 무한히 미루지 않는다.
  void deleteNotificationDeferred(String notificationId) {
    if (_disposed || _userId == null) return;
    if (_pendingDeletes.containsKey(notificationId)) return;
    _pendingDeletes[notificationId] = Timer(undoWindow, () {
      _pendingDeletes.remove(notificationId);
      // 커밋 시점에는 이미 목록에서 빠져 있으므로 notifyListeners가 필요 없다.
      // 실패해도 스트림이 그 알림을 다시 실어 오고, 그때 다시 보인다
      // (조용히 사라진 척하지 않는다).
      deleteNotification(notificationId);
    });
    _invalidateCache();
    notifyListeners();
  }

  /// 예약된 삭제를 취소한다. 커밋 전이면 true.
  ///
  /// 유예 창이 이미 지났으면 false — 그때는 정말 지워졌고, 되돌릴 수 없다.
  /// 호출부는 이 값을 보고 "실행 취소했습니다"와 "이미 삭제되었습니다"를
  /// 구분해 말해야 한다. 취소하지 못했는데 취소했다고 말하지 않는다.
  bool undoDeleteNotification(String notificationId) {
    final timer = _pendingDeletes.remove(notificationId);
    if (timer == null) return false;
    timer.cancel();
    if (_disposed) return true;
    _invalidateCache();
    notifyListeners();
    return true;
  }

  /// 대기 중인 삭제를 **지금** 모두 커밋한다.
  ///
  /// 화면을 떠나거나 로그아웃할 때 부른다. 사용자는 이미 지운 것으로 알고
  /// 있으므로, 예약을 조용히 버리면 지웠다고 생각한 알림이 되돌아온다.
  void flushPendingDeletes() {
    if (_pendingDeletes.isEmpty) return;
    final ids = _pendingDeletes.keys.toList();
    for (final t in _pendingDeletes.values) {
      t.cancel();
    }
    _pendingDeletes.clear();
    for (final id in ids) {
      deleteNotification(id);
    }
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
    flushPendingDeletes(); // _disposed 이전에 — 그 뒤엔 커밋이 막힌다
    _disposed = true;
    _stopListening();
    super.dispose();
  }
}
