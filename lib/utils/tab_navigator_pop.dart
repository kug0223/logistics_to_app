import 'package:flutter/widgets.dart';

/// [DU1 R8-TAB-RESELECT] 탭 Navigator 를 첫 화면까지 비우되 **각 화면의 PopScope 를 따른다.**
///
/// 예전에는 같은 탭 재탭·딥링크 정규화가 `popUntil((r) => r.isFirst)` 였다. popUntil 은
/// route 를 직접 pop 해서 저장 안 한 변경 확인·저장 중 보호를 건너뛰고, 결과도 null 로
/// 돌려줘(`Navigator.pop(context, _hasChanges)` 를 쓰는 큐 화면) 부모 갱신을 놓쳤다.
///
/// 여기서는 한 번에 하나씩 `maybePop()` 한다. 맨 위 화면이 닫히기를 거절하면(확인 창을 띄우거나
/// 진행 중 차단) **그 자리에서 멈춘다** — 비동기 확인이 끝나기 전에 그 아래 route 를 강제로 걷어내지 않는다.
/// 사용자가 '나가기'를 고르면 그 화면만 닫히고, 남은 스택은 다음 재탭에서 같은 규칙으로 비운다.
///
/// 반환: 첫 화면에 도달했으면 true, 어떤 화면이 거절했거나 Navigator 가 사라졌으면 false.
Future<bool> popTabToRoot(NavigatorState nav) async {
  if (_inFlight.contains(nav)) return false; // 빠른 연속 재탭 — 이미 비우는 중
  _inFlight.add(nav);
  try {
    while (nav.mounted && nav.canPop()) {
      final before = _topRoute(nav);
      await nav.maybePop();
      if (!nav.mounted) return false;
      if (identical(_topRoute(nav), before)) return false; // 화면이 거절 — 확인/진행 보호에 맡긴다
    }
    return nav.mounted;
  } finally {
    _inFlight.remove(nav);
  }
}

final Set<NavigatorState> _inFlight = <NavigatorState>{};

/// 현재 맨 위 route — popUntil 에 첫 항목에서 true 를 돌려주면 아무것도 pop 하지 않고 읽기만 한다.
Route<dynamic>? _topRoute(NavigatorState nav) {
  Route<dynamic>? top;
  nav.popUntil((r) {
    top = r;
    return true;
  });
  return top;
}
