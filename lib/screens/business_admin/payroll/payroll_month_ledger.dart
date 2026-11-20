import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../../../models/core/attendance_model.dart';

/// [PAYROLL-ANNUAL-READ.48] 급여 개요의 미확정·미이체를 **달마다 따로** 읽는다.
///
///   예전에는 1~12월 원장을 한 번에 읽었다. 서버(`callableGetAdminAttendances`)는 한 응답을
///   10,000건에서 자르고 `limitReached` 를 붙이는데, 연간 합이 그보다 많으면 달마다는 적어도
///   **12개월 전부**가 '미이체 확인 못함'이 됐다(.33 기기 확인). 같은 API 를 달 하나로 부르면
///   한 달이 10,000건 이하인 사업장은 모든 달을 정확히 센다.
///
///   한 달 자체가 10,000건을 넘으면 그 달만 '확인 못함'이다. 그때 서버 월 집계
///   (`callableGetPayrollMonthLedgerCounts`)가 있으면 그것으로 센다 — 없거나 끝까지 못 세면
///   여전히 '확인 못함'이다. 작은 수를 사실처럼 보이지 않는다(fail-closed).

/// 한 달 원장의 숫자. 서버 `srvPayrollContribution` 과 같은 식이다:
///   미확정 = pending + calculated, 미이체 = confirmed, 이체 완료 = transferred,
///   노쇼·결근 0원(`isNonPayableZeroOf`)은 확정·이체 쪽에서 빠진다. 정상 근무 0원은 남는다.
///   근무자 = 확정·이체 대상 근태의 userId 중복 제거.
@immutable
class MonthLedgerCounts {
  const MonthLedgerCounts({
    required this.pending,
    required this.notTransferred,
    required this.transferred,
    required this.payout,
    required this.workerCount,
  });

  final int pending;
  final int notTransferred;
  final int transferred;
  final int payout;
  final int workerCount;

  /// 원장 문서들에서 [month](1~12) 하나를 센다. 다른 달·형식이 틀린 행은 세지 않는다.
  factory MonthLedgerCounts.fromItems(Iterable<Map<String, dynamic>> items, int month) {
    var pending = 0, notTransferred = 0, transferred = 0, payout = 0;
    final workers = <String>{};
    for (final data in items) {
      final ym = data['yearMonth'] as String?;
      if (ym == null) continue;
      final parts = ym.split('-');
      if (parts.length != 2 || int.tryParse(parts[1]) != month) continue;
      final ws = data['wageStatus'] as String?;
      if (ws == 'pending' || ws == 'calculated') {
        pending++;
      } else if (ws == 'confirmed' || ws == 'transferred') {
        if (AttendanceModel.isNonPayableZeroOf(data['status'] as String?, data['finalWage'] as num?)) {
          continue;
        }
        if (ws == 'confirmed') {
          notTransferred++;
        } else {
          transferred++;
        }
        payout += (data['finalWage'] as num?)?.toInt() ?? 0;
        final uid = data['userId'] as String?;
        if (uid != null) workers.add(uid);
      }
    }
    return MonthLedgerCounts(pending: pending, notTransferred: notTransferred,
        transferred: transferred, payout: payout, workerCount: workers.length);
  }

  /// 서버 월 집계 응답. 끝까지 세지 못했거나(`complete != true`) 형식이 틀리면 null.
  static MonthLedgerCounts? tryFromServer(Object? raw) {
    if (raw is! Map || raw['complete'] != true) return null;
    int? n(String k) => raw[k] is num ? (raw[k] as num).toInt() : null;
    final p = n('pending'), nt = n('notTransferred'), t = n('transferred'), pay = n('payout'), w = n('workerCount');
    if (p == null || nt == null || t == null || pay == null || w == null) return null;
    return MonthLedgerCounts(pending: p, notTransferred: nt, transferred: t, payout: pay, workerCount: w);
  }
}

/// 한 달의 미이체 확인 상태.
enum MonthLedgerStatus {
  /// 읽는 중 — 아직 숫자를 말하지 않는다.
  loading,
  /// 이번 조회로 끝까지 셌다.
  known,
  /// 확인하지 못했다(실패·상한·시간 초과·형식). 숫자 없음.
  unknown,
  /// 이번 새로고침은 실패했고, 같은 사업장·연도의 **이전 조회** 숫자를 보여 준다.
  stale,
}

enum MonthLedgerFailure { failed, limit, timeout }

@immutable
class MonthLedgerState {
  const MonthLedgerState._(this.status, this.counts, this.failure);
  const MonthLedgerState.loading([MonthLedgerCounts? previous])
      : this._(MonthLedgerStatus.loading, previous, null);
  const MonthLedgerState.known(MonthLedgerCounts counts) : this._(MonthLedgerStatus.known, counts, null);
  const MonthLedgerState.unknown(MonthLedgerFailure f) : this._(MonthLedgerStatus.unknown, null, f);
  const MonthLedgerState.stale(MonthLedgerCounts previous, MonthLedgerFailure f)
      : this._(MonthLedgerStatus.stale, previous, f);

  final MonthLedgerStatus status;

  /// known·stale 의 숫자. loading 이면 새로고침 전 숫자(있을 때만 — 화면은 '확인 중'으로 말한다).
  final MonthLedgerCounts? counts;
  final MonthLedgerFailure? failure;

  /// 이 달 숫자를 **이번 조회의 사실**로 말할 수 있는가 — 이체 완료 파생·지급 판단은 이것만 쓴다.
  bool get isComplete => status == MonthLedgerStatus.known;
}

/// 서버 월 집계가 배포돼 있는가 — 한 번 '없음'(not-found·unimplemented)을 확인하면 이번 세션에서는
///   다시 묻지 않는다. null = 아직 모름.
class MonthLedgerCountsCapability {
  bool? available;
}

typedef MonthLedgerRead = Future<({List<Map<String, dynamic>> items, bool limitReached})> Function(
    String yearMonth);
typedef MonthLedgerCountsRead = Future<Object?> Function(String yearMonth);

/// 달 목록을 동시 [concurrency] 개씩 읽고, 끝나는 대로 [onMonth] 로 알린다.
///
///   - 전체 대기는 [budget] 하나다(.39-A1 읽기 대기 30초) — 달마다 새로 주지 않는다. 넘으면 남은 달은
///     timeout 으로 '확인 못함'이다. 서버 요청을 취소하거나 서버 실패를 증명하는 것이 아니다.
///   - 한 달 실패는 그 달만이다. 다른 달은 그대로 끝까지 읽는다.
///   - [countsRead](서버 월 집계)를 **먼저** 쓴다 — 화면은 숫자만 필요하고 이 응답은 수백 바이트다.
///     없다고 확인되면([capability]) 기존 월 원장(문서 목록)으로 센다. 서버가 끝까지 세지 못했으면
///     (complete=false) 그 달은 limit 으로 '확인 못함' — 원장도 같은 상한에 걸린다.
///   - 집계가 있는지 모르면 첫 달만 먼저 묻는다(없을 때 실패 호출이 동시에 쌓이지 않게).
///   - 원장이 상한에 걸린 달은 집계를 다시 묻고(있을 때), 아니면 limit 으로 '확인 못함'.
///   - [isCurrent] 가 false 가 되면(사업장·연도 전환, 더 새 조회) 결과를 알리지 않는다.
///   - 쓰기를 하지 않는다. 재시도는 호출자가 실패한 달만 다시 넘긴다.
Future<void> loadMonthLedgers({
  required List<int> months,
  required String Function(int month) yearMonthOf,
  required MonthLedgerRead read,
  MonthLedgerCountsRead? countsRead,
  required void Function(int month, MonthLedgerState state) onMonth,
  required bool Function() isCurrent,
  MonthLedgerCounts? Function(int month)? previousOf,
  MonthLedgerCountsCapability? capability,
  int concurrency = 3,
  Duration budget = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(budget);
  final queue = List<int>.of(months);

  MonthLedgerState fail(int month, MonthLedgerFailure f) {
    final prev = previousOf?.call(month);
    return prev != null ? MonthLedgerState.stale(prev, f) : MonthLedgerState.unknown(f);
  }

  Future<T> bounded<T>(Future<T> f) {
    final left = deadline.difference(DateTime.now());
    if (left <= Duration.zero) return Future<T>.error(TimeoutException('budget'));
    return f.timeout(left);
  }

  final cap = capability ?? MonthLedgerCountsCapability();

  bool isMissing(Object e) =>
      e is FirebaseFunctionsException && (e.code == 'not-found' || e.code == 'unimplemented');

  Future<MonthLedgerState> one(int month) async {
    final ym = yearMonthOf(month);
    if (countsRead != null && cap.available != false) {
      try {
        final raw = await bounded(countsRead(ym));
        cap.available = true;
        final c = MonthLedgerCounts.tryFromServer(raw);
        if (c != null) return MonthLedgerState.known(c);
        if (raw is Map && raw['complete'] == false) return fail(month, MonthLedgerFailure.limit);
        // 형식이 틀린 응답 — 원장으로 센다.
      } on TimeoutException {
        return fail(month, MonthLedgerFailure.timeout);
      } catch (e) {
        if (isMissing(e)) {
          cap.available = false; // 아직 배포되지 않았다 — 이번 세션은 원장으로 센다.
        } else {
          debugPrint('⚠️ 월 집계 조회 실패($ym): $e');
        }
      }
    }
    try {
      final r = await bounded(read(ym));
      if (!r.limitReached) return MonthLedgerState.known(MonthLedgerCounts.fromItems(r.items, month));
      if (countsRead == null || cap.available != null) return fail(month, MonthLedgerFailure.limit);
      try {
        final c = MonthLedgerCounts.tryFromServer(await bounded(countsRead(ym)));
        return c != null ? MonthLedgerState.known(c) : fail(month, MonthLedgerFailure.limit);
      } on TimeoutException {
        return fail(month, MonthLedgerFailure.timeout);
      } on FirebaseFunctionsException catch (e) {
        // 서버 월 집계가 아직 없다(not-found·unimplemented) — 그 달은 상한으로 남는다.
        debugPrint('⚠️ 월 집계 조회 실패($ym): ${e.code}');
        return fail(month, MonthLedgerFailure.limit);
      } catch (e) {
        debugPrint('⚠️ 월 집계 조회 실패($ym): $e');
        return fail(month, MonthLedgerFailure.limit);
      }
    } on TimeoutException {
      return fail(month, MonthLedgerFailure.timeout);
    } catch (e) {
      debugPrint('⚠️ 월 원장 조회 실패($ym): $e');
      return fail(month, MonthLedgerFailure.failed);
    }
  }

  Future<void> worker() async {
    while (queue.isNotEmpty) {
      final m = queue.removeAt(0);
      final s = await one(m);
      if (!isCurrent()) return;
      onMonth(m, s);
    }
  }

  // 집계가 있는지 모르면 첫 달 하나로 먼저 확인한다.
  if (countsRead != null && cap.available == null && queue.isNotEmpty) {
    final m = queue.removeAt(0);
    final st = await one(m);
    if (!isCurrent()) return;
    onMonth(m, st);
  }
  final workers = concurrency < queue.length ? concurrency : queue.length;
  await Future.wait([for (var i = 0; i < workers; i++) worker()]);
}
