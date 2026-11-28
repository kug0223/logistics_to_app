import 'package:flutter/widgets.dart';

/// [L48 · impl_28] 처리 뒤 다시 읽기 — **보여 주던 목록을 그대로 두고** 새 결과로 바꾼다.
///
///   예전에는 저장·삭제·상태 변경 뒤 `_load()` 가 전체 로딩 화면을 켜서 목록이 통째로 사라졌다가 다시 그려졌다
///   (스크롤 위치·보던 행을 잃는다). 이제는:
///   · 이미 정상 목록을 한 번 보여 준 화면이면(= [beginContentLoad] 의 keep) 목록을 유지하고, 그 위를 잠그고
///     얇은 진행 표시만 둔다(`KeepContentBody`). 첫 읽기 · 실패 화면에서의 다시 시도는 예전처럼 로딩 화면이다.
///   · 읽기마다 차례 번호를 매긴다 — 늦게 도착한 옛 응답은 [isCurrentContentLoad] 가 false 라 착지하지 않는다.
///   · 실패는 예전 화면의 실패 처리를 그대로 따른다(목록을 낡은 채 "최신처럼" 두지 않는다 — 화면별 기존 의미).
///   · 값·금액을 서버 확인 전에 미리 그리지 않는다 — 유지되는 것은 **마지막으로 서버에서 읽은** 화면이다.
///     편집 중이던(서버가 아직 받지 않은) 값은 화면이 [beginContentLoad] 직후 스스로 되돌린다(최저시급·보험료율).
mixin KeepContentRefreshMixin<T extends StatefulWidget> on State<T> {
  int _contentLoadGen = 0;
  bool _contentShownOnce = false;

  /// 목록을 유지한 채 다시 읽는 중 — 본문 잠금 · 진행 표시에 쓴다.
  bool refreshingKeep = false;

  /// 읽기 하나를 시작한다. [canKeep] = 지금 화면이 정상 목록을 보이고 있는가(실패 화면이면 false).
  ///   돌려준 `keep` 이 true 면 호출자는 전체 로딩을 켜지 않는다.
  ({int gen, bool keep}) beginContentLoad({required bool canKeep}) {
    final gen = ++_contentLoadGen;
    final keep = canKeep && _contentShownOnce;
    if (mounted && keep != refreshingKeep) setState(() => refreshingKeep = keep);
    return (gen: gen, keep: keep);
  }

  /// 이 읽기가 아직 최신인가(늦게 온 옛 응답이면 false — 착지 0).
  bool isCurrentContentLoad(int gen) => mounted && gen == _contentLoadGen;

  /// 최신 읽기가 끝났다. [shown] = 정상 목록이 앉았는가(다음 읽기부터 유지 대상).
  void finishContentLoad(int gen, {required bool shown}) {
    if (gen != _contentLoadGen) return;
    if (shown) _contentShownOnce = true;
    if (!shown) _contentShownOnce = false;
    if (mounted && refreshingKeep) setState(() => refreshingKeep = false);
  }
}
