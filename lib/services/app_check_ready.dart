import 'dart:async';

import 'package:flutter/foundation.dart';

/// [PERF-L12 · analysis_1 §6 #14 · 판정289 §1] App Check 첫 토큰을 **공유 future** 로 둔다.
///
///   예전에는 `main()` 이 `await FirebaseAppCheck.instance.getToken()` 으로 runApp 을 막았다.
///   목적은 "앱 시작 때 여러 요청이 동시에 토큰을 달라고 해 SDK 가 `Too many attempts` 를 내고
///   깨진 토큰이 서버로 가는 것"을 막는 것이다(main.dart 주석). 그 방어는 유지한다 — 단,
///   막는 대상을 **앱 전체 시작**에서 **첫 Firebase 요청들**로 옮긴다.
///
///   · `main()` 은 [start] 로 토큰 받기를 한 번만 출발시키고 runApp 을 바로 부른다.
///   · 앱 시작 직후의 첫 요청(사용자 문서 읽기 · 미리 읽기 · 최저시급/보험료율 읽기 · 로그인)은
///     [wait] 로 그 **같은** future 에 합류한 뒤 나간다 → 토큰 요청은 한 번, 나머지는 캐시를 쓴다.
///   · 토큰 받기 실패는 삼킨다(예전 `catchError((_) => null)` 과 같다 — 앱 시작을 막지 않음).
///   · [wait] 는 상한이 있다. 상한이 지나도 원 요청은 취소되지 않는다(SDK 가 계속 받는다) —
///     기다리던 쪽만 진행한다. 예전에는 상한 없이 runApp 자체가 기다렸다.
///   · [start] 를 부르지 않은 환경(시험)에서는 [wait] 가 바로 끝난다.
class AppCheckReady {
  AppCheckReady._();

  /// 진행 중인 첫 토큰 받기(끝나면 비운다). 완료 결과는 [_done] **값**으로만 남긴다.
  ///   [L30 PZ-2 같은 뿌리] 완료된 static Future 를 영구 보관해 돌려주면, 그 Future 가 만들어진 zone 과
  ///   다른 zone(FakeAsync 시험 · 핫 리스타트 뒤 등)에서 await 할 때 리스너가 원래 zone 의 microtask 로
  ///   예약돼 멈출 수 있다 → 완료 뒤에는 호출자 zone 에서 새 Future 를 만든다.
  static Future<void>? _inFlight;
  static bool _done = false;

  /// 첫 토큰 받기를 한 번만 출발시킨다(진행 중이면 같은 future · 끝났으면 다시 요청하지 않는다).
  static Future<void> start(Future<Object?> Function() getToken) {
    if (_done) return Future<void>.value();
    final cur = _inFlight;
    if (cur != null) return cur;
    Future<Object?> f;
    try {
      f = getToken();
    } catch (e) {
      f = Future<Object?>.error(e);
    }
    return _inFlight = f.then<void>((_) {}, onError: (Object e) {
      debugPrint('⚠️ [AppCheck] 첫 토큰 받기 실패(앱 시작은 계속): $e');
    }).whenComplete(() {
      _done = true;
      _inFlight = null;
    });
  }

  /// 첫 토큰 받기가 끝났는가(성공·실패 무관). 시작하지 않았으면 false.
  static bool get settled => _done;

  /// 첫 토큰 받기에 합류한다. 시작하지 않았거나 이미 끝났으면 즉시 끝난다.
  static Future<void> wait({Duration timeout = const Duration(seconds: 8)}) {
    final f = _inFlight;
    if (f == null || _done) return Future<void>.value();
    return f.timeout(timeout, onTimeout: () {
      debugPrint('⚠️ [AppCheck] 첫 토큰 대기 상한 — 요청을 계속 보낸다');
    });
  }

  @visibleForTesting
  static void debugReset() {
    _inFlight = null;
    _done = false;
  }
}
