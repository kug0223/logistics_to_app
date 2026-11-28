import 'package:flutter/foundation.dart';

import '../models/core/user_model.dart';

/// [PERF-L1 안전판 · 판정289 §3 C289-02] 버전 판정 **전에** 사용자 문서 읽기만 미리 출발시킨다.
///
///   허용 범위는 **부수효과 없는 users/{uid} 읽기 한 번**뿐이다. 구독·FCM 권한/등록·지역 쓰기·업무 callable·
///   홈/딥링크 진입은 여기서 하지 않는다 — 그것들은 여전히 버전 판정(supported) 뒤 AuthWrapper 가
///   UserProvider 를 만들 때 시작한다(Provider lazy 생성 그대로 · lazy:false 미채택).
///
///   소비는 `UserProvider._loadUserData` 한 곳이다. 같은 uid · 출발 후 [maxAge] 안일 때만 그 결과를 쓰고,
///   쓴 뒤에는 기존과 같은 세대 검사 → 고아/삭제/pending/LoginGate/역할 판정을 그대로 지난다.
///   UNKNOWN/차단이면 AuthWrapper 가 그려지지 않으므로 이 결과는 쓰이지 않는다(우회 0).
///   미리 읽기가 실패하면 소비자가 평소처럼 다시 읽는다.
class UserSnapshotPrefetch {
  UserSnapshotPrefetch._();

  /// 미리 읽은 값을 믿는 최대 시간 — 넘으면 버리고 새로 읽는다(업데이트 권고 창에 오래 머문 경우 등).
  static const Duration maxAge = Duration(seconds: 20);

  static ({String uid, DateTime at, Future<UserModel?> future})? _pending;

  /// 앱 시작(main) — Firebase · App Check 준비 뒤, 복원된 세션의 uid 로 한 번 부른다.
  static void start(String uid, Future<UserModel?> Function(String uid) read,
      {DateTime Function()? clock}) {
    if (_pending != null) return;
    Future<UserModel?> f;
    try {
      f = read(uid);
    } catch (e) {
      f = Future<UserModel?>.error(e);
    }
    // 아무도 소비하지 않아도 처리되지 않은 오류로 남지 않게 한다(원 future 는 그대로 넘긴다).
    f.then<void>((_) {}, onError: (Object _) {});
    _pending = (uid: uid, at: (clock ?? DateTime.now)(), future: f);
  }

  /// 같은 uid 의 미리 읽기를 **한 번** 넘겨준다. 없거나 다른 uid 거나 오래됐으면 null.
  static Future<UserModel?>? take(String uid, {DateTime Function()? clock}) {
    final p = _pending;
    _pending = null;
    if (p == null || p.uid != uid) return null;
    final age = (clock ?? DateTime.now)().difference(p.at);
    if (age > maxAge || age.isNegative) return null;
    return p.future;
  }

  @visibleForTesting
  static void debugReset() => _pending = null;

  @visibleForTesting
  static bool get debugHasPending => _pending != null;
}
