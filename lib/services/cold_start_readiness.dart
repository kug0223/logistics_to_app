import 'dart:async';

/// [PERF-L2 · 판정289 §2] 알림 탭 cold-start payload 의 **준비 완료** 신호(세션 결속).
///
///   FCMService.initialize 가 세션마다 [begin] 하고, 성공·실패·세션 취소 모두에서 [settle] 한다.
///   로그아웃은 [cancel] 로 대기자를 끝낸다. 대기자([waitFor])는 준비가 끝난 뒤 세션이 그대로일 때만
///   [stillValid] 판정을 받아 소비 여부를 정한다. 준비 중 새 세션이 시작되면(계정 전환 재초기화) 그 준비를
///   최대 [maxHops] 번 다시 기다린다. timeout 은 두지 않는다 — 준비는 반드시 끝난다.
class ColdStartReadiness {
  Completer<void>? _ready;
  int _session = -1;

  /// 마지막으로 [begin] 한 세션 번호(-1 = 없음).
  int get session => _session;

  /// 현재 준비가 아직 끝나지 않았는가.
  bool get pending => _ready != null && !_ready!.isCompleted;

  /// 새 세션의 준비를 연다. 이전 세션 준비는 끝낸다(대기자는 세션 변경을 보고 다시 기다린다).
  void begin(int session) {
    final prev = _ready;
    if (prev != null && !prev.isCompleted) prev.complete();
    _ready = Completer<void>();
    _session = session;
  }

  /// [session] 의 준비를 끝낸다. 다른 세션이면 아무것도 하지 않는다. 끝냈으면 true.
  bool settle(int session) {
    final c = _ready;
    if (c == null || _session != session || c.isCompleted) return false;
    c.complete();
    return true;
  }

  /// 로그아웃 — 지금 준비를 끝낸다(대기자는 [stillValid] 에서 거절된다).
  void cancel() {
    final c = _ready;
    if (c != null && !c.isCompleted) c.complete();
  }

  /// 준비가 끝나기를 기다린 뒤, 세션이 그대로면 [stillValid] 의 답을 돌려준다.
  ///   준비가 연 적 없으면 false(받을 payload 없음).
  Future<bool> waitFor({
    required bool Function(int session) stillValid,
    int maxHops = 3,
  }) async {
    for (var i = 0; i < maxHops; i++) {
      final ready = _ready;
      if (ready == null) return false;
      final s = _session;
      await ready.future;
      if (_session != s) continue;
      return stillValid(s);
    }
    return false;
  }
}
