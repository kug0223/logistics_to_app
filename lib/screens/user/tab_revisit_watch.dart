import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// [PERF-P9 · 판정291 §8 · 2026-11-26] 근로자 탭의 **실제 가시 재방문**과 앱 복귀를 알려 준다.
///
///   셸(UserRootScreen)은 방문한 탭을 IndexedStack 에 남겨 두고, 보이지 않는 탭은 `TickerMode(false)` 로 감싼다.
///   탭 안에서 상세 화면을 열었다 닫을 때도 Navigator 가 가려진 화면을 `TickerMode(false)` 로 둔다.
///   그래서 "TickerMode 가 꺼졌다가 다시 켜졌다" = 그 화면이 **다시 보이게 됐다**는 뜻이다.
///
///   이 감시자는 판단하지 않는다 — 신호만 준다. 무엇이 낡았는지(데이터별 신선도·무효화·계정)는 각 탭이 정한다.
///   숨어 있는 동안 앱이 복귀하면 아무것도 하지 않는다(숨은 탭 network 0) — 다음에 보일 때 각 탭이 시간으로 판단한다.
///   주기 polling·매 build 조회는 하지 않는다.
class TabRevisitWatch with WidgetsBindingObserver {
  TabRevisitWatch({required this.onRevisit});

  /// 다시 보이게 됐거나, 보이는 채로 앱이 복귀했다.
  final VoidCallback onRevisit;

  ValueListenable<bool>? _ticker;
  bool _visible = true;
  bool _attached = false;

  /// 지금 이 화면이 보이는가(TickerMode 기준).
  bool get visible => _visible;

  /// State.initState 에서 한 번.
  void attach() {
    if (_attached) return;
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
  }

  /// State.didChangeDependencies 에서 매번 — TickerMode 알림원이 바뀌면 갈아 끼운다.
  void updateFrom(BuildContext context) {
    final n = TickerMode.getNotifier(context);
    if (identical(n, _ticker)) return;
    _ticker?.removeListener(_onTicker);
    _ticker = n;
    _visible = n.value;
    n.addListener(_onTicker);
  }

  void _onTicker() {
    final v = _ticker?.value ?? true;
    final was = _visible;
    _visible = v;
    if (v && !was) onRevisit();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _visible) onRevisit();
  }

  /// State.dispose 에서.
  void dispose() {
    _ticker?.removeListener(_onTicker);
    _ticker = null;
    if (_attached) WidgetsBinding.instance.removeObserver(this);
    _attached = false;
  }
}
