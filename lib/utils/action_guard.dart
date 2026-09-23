import 'package:flutter/foundation.dart';

/// [R7-P1-CORR] 같은 행동 · 같은 대상에 대한 single-flight 게이트.
///
/// ── 무엇을 고치는가 ──────────────────────────────────────────────────────
///
/// 버튼을 빠르게 두 번 누르면 같은 다이얼로그가 두 개 쌓였다. `showDialog`는
/// `Navigator.push`를 **동기로** 부르지만, 그 route의 `ModalBarrier`가 화면을
/// 덮는 것은 다음 프레임이다. 그 한 프레임 동안 두 번째 탭은 여전히 아래의
/// CTA에 닿는다.
///
/// 그것만이라면 보기 싫은 정도다. 진짜 문제는 그 다음이다. 호출부의 방어는
/// 대부분 이런 모양이었다:
///
/// ```dart
/// if (_isProcessing) return;              // 체크
/// final ok = await DialogHelper.showConfirm(...);   // 갭 — 아직 false다
/// if (!ok) return;
/// setState(() => _isProcessing = true);   // 설정 — await 뒤 재확인이 없다
/// await mutate();                          // 두 번 실행될 수 있다
/// ```
///
/// 모달 두 개가 쌓이면 사용자는 확인을 두 번 누를 수 있고, 두 번째 확인도
/// 같은 경로로 mutation에 도달한다. 중복 제안·중복 알림·정원 카운터 이중 변경이
/// 나오는 길이다. 체크와 설정 사이에 await가 있는 가드는 가드가 아니다.
///
/// ── 어떻게 고치는가 ──────────────────────────────────────────────────────
///
/// [run]은 busy 표시를 **첫 await 이전에 동기로** 세운다. 같은 프레임에 들어온
/// 두 번째 탭은 그 표시를 보고 돌아간다. 시간(debounce)이 아니라 상태로 막기
/// 때문에, 모달이 3초를 떠 있든 30초를 떠 있든 그동안 내내 닫혀 있다.
///
/// 잠그는 단위는 **행동 + 대상**이다. 전역 잠금이 아니다:
///
///   · `invite:to1:slot9`  와  `invite:to1:slot10`  → 서로 막지 않는다
///   · `offer:app7`        와  `offer-confirm:app7` → 중첩 확인 흐름이 산다
///
/// 서버 쪽은 이 가드와 **별개**다. UI 가드는 사용자의 손가락만 막을 수 있고,
/// 재시도·네트워크 재전송·다른 기기는 막지 못한다. mutation의 최종 방어선은
/// 서버 idempotency이며, 이 클래스는 그것을 대신하지 않는다.
class ActionGuard {
  ActionGuard._();

  /// 진행 중인 key. 값은 진입 시각 — 디버깅용이다.
  static final Map<String, DateTime> _inFlight = <String, DateTime>{};

  /// 이 행동+대상이 지금 진행 중인가.
  static bool isBusy(String key) => _inFlight.containsKey(key);

  /// 진행 중인 key 수 — 테스트에서 누수를 잡는 용도.
  @visibleForTesting
  static int get inFlightCount => _inFlight.length;

  @visibleForTesting
  static void resetForTest() => _inFlight.clear();

  /// [key]가 놀고 있을 때만 [body]를 실행한다. 진행 중이면 `null`을 돌려준다.
  ///
  /// 돌려주는 `null`은 "사용자가 취소했다"와 구분되지 않는다. 그래도 되는
  /// 이유는, 중복 탭에서 해야 할 일이 정확히 **아무것도 하지 않기**이기
  /// 때문이다. 토스트로 "이미 처리 중입니다"라고 말하지 않는다 — 사용자는
  /// 두 번 눌렀다고 생각하지 않고, 첫 번째 탭의 결과(열린 모달)를 이미
  /// 보고 있다.
  ///
  /// [body]가 던지든 정상 종료하든 key는 반드시 풀린다.
  static Future<T?> run<T>(String key, Future<T?> Function() body) async {
    if (_inFlight.containsKey(key)) return null;
    _inFlight[key] = DateTime.now();
    try {
      return await body();
    } finally {
      _inFlight.remove(key);
    }
  }

  /// 반환값이 없는 행동용.
  static Future<void> runVoid(String key, Future<void> Function() body) async {
    if (_inFlight.containsKey(key)) return;
    _inFlight[key] = DateTime.now();
    try {
      await body();
    } finally {
      _inFlight.remove(key);
    }
  }

  // ── key 생성 ─────────────────────────────────────────────────────────
  //
  // key를 호출부에서 문자열로 조립하면 오타 하나가 조용히 가드를 없앤다
  // (`'invite:$toId'` vs `'invite :$toId'`). 같은 행동은 같은 함수로 만든다.

  /// 행동 이름 + 대상 식별자들. 빈 조각은 `_`로 남겨 서로 다른 대상이
  /// 우연히 같은 key가 되지 않게 한다.
  static String keyOf(String action, List<String?> entityIds) {
    final parts = entityIds.map((e) => (e == null || e.isEmpty) ? '_' : e);
    return '$action:${parts.join(':')}';
  }
}
