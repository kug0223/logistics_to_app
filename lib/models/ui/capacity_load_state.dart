import 'package:flutter/foundation.dart';

import '../core/work_detail_data.dart';

/// [R7-P1-2 DEVICE.1E.1] 정원 조회의 **상태기계**. 화면에서 분리한다.
///
///   DEVICE.1E 에서 인력 현황 다이얼로그가 정원을 직접 읽도록 고쳤지만,
///   그 상태기계는 private State 안에 있어 실패→재시도·순서 역전·dispose
///   같은 **회복 경로를 실행으로 증명할 수 없었다**. 미검증은 closure 면제
///   사유가 아니므로, 가장 작은 단위만 떼어 낸다.
///
///   테스트 전용 분기를 만들지 않는다 — 화면이 쓰는 그 객체를 그대로
///   실행한다. 주입되는 것은 loader 하나뿐이다.
///
///   불변식:
///     · 실패는 0 이 아니라 UNKNOWN 이다.
///     · `statsFailed` 인 응답의 map 은 전부 0 으로 seed 된 값이므로 쓰지 않는다.
///     · 늦게 도착한 응답은 더 새로운 요청을 덮지 않는다.
///     · dispose 이후의 응답은 아무것도 바꾸지 않는다.
class CapacityLoadState {
  /// `loadTOWorkDetails` 와 같은 모양의 결과를 돌려주는 조회.
  /// `{workDetails, workStats, statsFailed}`
  final Future<Map<String, dynamic>> Function() loader;

  /// 상태가 바뀌었을 때 화면에 알린다(setState).
  final VoidCallback? onChanged;

  CapacityLoadState({required this.loader, this.onChanged});

  Map<String, Map<String, int>>? _stats;
  bool _failed = false;
  bool _loading = false;
  int _seq = 0;
  bool _disposed = false;

  Map<String, Map<String, int>>? get stats => _stats;
  bool get failed => _failed;
  bool get loading => _loading;

  /// 부모가 준 snapshot 을 **초기값으로만** 쓴다 — 첫 프레임 깜빡임 방지.
  ///
  ///   실패 flag 가 서 있으면 그 map 은 전부 0 인 seed 다. 숫자로 쓰지 않는다.
  void seed(Map<String, Map<String, int>>? parentStats,
      {required bool parentFailed}) {
    if (parentFailed) {
      _failed = true;
      return;
    }
    _stats = parentStats;
  }

  /// canonical 정원 조회. 실패한 그것을 다시 하는 재시도도 이 함수다.
  Future<void> load() async {
    final seq = ++_seq;
    _loading = true;
    _failed = false;
    _notify();

    Map<String, Map<String, int>>? next;
    var failed = false;
    try {
      final result = await loader();
      failed = result['statsFailed'] == true;
      if (!failed) {
        next = result['workStats'] as Map<String, Map<String, int>>?;
        failed = next == null;
      }
    } catch (e) {
      debugPrint('❌ 인력 현황 정원 조회 실패: $e');
      failed = true;
    }

    if (_disposed) return;
    // 더 새로운 요청이 이미 나갔다 — 이 결과는 과거다.
    if (seq != _seq) return;

    _loading = false;
    _failed = failed;
    if (!failed) _stats = next;
    _notify();
  }

  /// mutation 직후의 로컬 재집계를 반영한다.
  ///
  ///   아는 값을 모르는 값으로 덮지 않는다 — 빈 집계는 정원에 대해 아무
  ///   말도 하지 못한 것이다.
  ///
  ///   그리고 **진행 중인 canonical 조회보다 앞서지 않는다**. 로컬 재집계가
  ///   늦게 온 canonical 응답에 덮이면, 방금 확정한 사람이 사라져 보인다.
  ///   반대로 로컬 값이 canonical 을 영구히 이기면 서버 진실을 잃는다.
  ///   그래서 진행 중인 요청을 무효화하고 로컬 값을 현재로 삼은 뒤,
  ///   호출자가 canonical 재조회를 이어서 하도록 둔다.
  void applyLocal(Map<String, Map<String, int>> local) {
    if (local.isEmpty) return;
    if (_disposed) return;
    _seq++; // 진행 중이던 응답은 이제 과거다.
    _loading = false;
    _failed = false;
    _stats = local;
    _notify();
  }

  /// 이 업무의 canonical 확정 수. 못 읽었으면 null (UNKNOWN != ZERO).
  int? confirmedFor(WorkDetailData? work) {
    if (work == null) return null;
    if (_failed) return null;
    final s = work.lookupByIdentity(_stats);
    if (s == null) return null;
    return s['confirmed'];
  }

  /// 권한이 사라진 것이 확인됐다 — 읽어 둔 정원을 남기지 않는다.
  void clearOnRevocation() {
    if (_disposed) return;
    _seq++; // 진행 중이던 조회 결과로 다시 노출되지 않게 한다.
    _stats = null;
    _failed = false;
    _loading = false;
    _notify();
  }

  void dispose() {
    _disposed = true;
    _seq++;
  }

  void _notify() {
    if (_disposed) return;
    onChanged?.call();
  }
}
