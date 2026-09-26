// [POSTING-V2-03N.1] 권한이 회수된 사업장에서 빠져나온다
//
// 03N READ에서 확인된 것:
//   · 서버는 요청한 businessId를 **전부** 검증하고 하나라도 어긋나면 요청
//     전체를 거부한다(MODEL A). 이 정책은 올바르고 바꾸지 않는다.
//   · 선택하지 않은 사업장에는 realtime listener가 없다. 배정이 회수돼도
//     클라이언트는 모르고, stale scope [A,B]로 계속 요청해 목록 전체가
//     permission-denied로 막혔다.
//   · 그 사이 회수된 B의 공고가 화면에 계속 남았다 — 일반 network stale과
//     같은 정책으로 처리됐기 때문이다.
//
// 새 계약: permission-denied일 때만 canonical scope를 다시 읽고, 회수가
// 확인되면 그 사업장 캐시를 즉시 지운 뒤 새 scope로 **정확히 한 번** 재시도한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _ctrlPath = 'lib/controllers/workforce_controller.dart';
const _providerPath = 'lib/providers/user_provider.dart';
const _fnsPath = 'functions/src/index.ts';

String _src(String p) {
  final f = File(p);
  expect(f.existsSync(), true, reason: '$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

String _bodyOf(String source, String signature) {
  final start = source.indexOf(signature);
  if (start == -1) throw StateError('$signature 를 찾지 못함');
  var paren = 0;
  var afterParams = start;
  for (var i = source.indexOf('(', start); i < source.length; i++) {
    if (source[i] == '(') paren++;
    if (source[i] == ')') {
      paren--;
      if (paren == 0) {
        afterParams = i;
        break;
      }
    }
  }
  final open = source.indexOf('{', afterParams);
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  throw StateError('$signature 본문의 끝을 찾지 못함');
}

// ═══════════════════════════════════════════════════════════════
// _loadWithScopeRecovery replica
// ═══════════════════════════════════════════════════════════════

/// 목록 호출 실패 종류.
///
/// [POSTING-V2-03N.1] `not-found`도 후보다 — 사업장 문서가 삭제되면
/// `assertBizAdmin`이 `permission-denied`가 아니라 이것을 던진다.
enum Fail { none, permissionDenied, notFound, network }

/// scope 축소로 이어질 수 있는 코드. 코드만으로 회수를 단정하지는 않는다.
const _candidates = {Fail.permissionDenied, Fail.notFound};

class Item {
  final String businessId;
  const Item(this.businessId);
}

class LoadOutcome {
  /// 최종 items. null이면 예외로 끝났다(caller가 loadError로 받는다).
  final List<Item>? items;

  /// 예외로 끝났을 때 화면에 남는 캐시.
  final List<Item> cached;
  final int listCalls;
  final int accessRefreshes;
  final String? selectedBusinessFilter;

  const LoadOutcome({
    this.items,
    required this.cached,
    required this.listCalls,
    required this.accessRefreshes,
    this.selectedBusinessFilter,
  });

  bool get threw => items == null;
}

/// [serverAuthorized]는 서버가 실제로 허용하는 사업장 — MODEL A이므로
/// 요청 중 하나라도 여기 없으면 호출 전체가 거부된다.
/// [deletedBusinesses]에 있으면 `permission-denied`가 아니라 `not-found`다.
LoadOutcome loadWithRecovery({
  required List<String> requestedScope,
  required List<String> serverAuthorized,
  required List<String> canonicalScopeAfterRefresh,
  required List<Item> cachedItems,
  List<String> deletedBusinesses = const [],
  bool accessRefreshFails = false,
  Fail retryFailure = Fail.none,
  Fail firstFailure = Fail.none,
  String? selectedBusinessFilter,
}) {
  var cached = [...cachedItems];
  var filter = selectedBusinessFilter;
  var listCalls = 0;
  var refreshes = 0;

  List<Item> serve(List<String> scope) =>
      [for (final b in scope) ...cached.where((i) => i.businessId == b)];

  // ── 1차 호출 ──
  listCalls++;
  final unauthorized =
      requestedScope.where((b) => !serverAuthorized.contains(b)).toList();
  // 서버는 businessId마다 assertBizAdmin을 부른다 — 문서가 없으면 not-found,
  //   있는데 내 것이 아니면 permission-denied.
  final Fail serverResult;
  if (unauthorized.isEmpty) {
    serverResult = Fail.none;
  } else if (unauthorized.any(deletedBusinesses.contains)) {
    serverResult = Fail.notFound;
  } else {
    serverResult = Fail.permissionDenied;
  }
  final firstResult = firstFailure != Fail.none ? firstFailure : serverResult;

  if (firstResult == Fail.none) {
    return LoadOutcome(
      items: serve(requestedScope),
      cached: cached,
      listCalls: listCalls,
      accessRefreshes: refreshes,
      selectedBusinessFilter: filter,
    );
  }
  // network 등 일시적 실패 — 기존 stale 계약 그대로, 캐시를 건드리지 않는다.
  if (!_candidates.contains(firstResult)) {
    return LoadOutcome(
      cached: cached,
      listCalls: listCalls,
      accessRefreshes: refreshes,
      selectedBusinessFilter: filter,
    );
  }

  // ── candidate error → canonical scope 재확인 ──
  refreshes++;
  if (accessRefreshFails) {
    // 회수를 **확인하지 못했다** — 임의로 지우지 않는다.
    return LoadOutcome(
      cached: cached,
      listCalls: listCalls,
      accessRefreshes: refreshes,
      selectedBusinessFilter: filter,
    );
  }
  final newScope = canonicalScopeAfterRefresh;
  final revoked =
      requestedScope.where((b) => !newScope.contains(b)).toSet();
  if (revoked.isEmpty) {
    // scope 그대로 — membership 회수라고 단정하지 않는다.
    return LoadOutcome(
      cached: cached,
      listCalls: listCalls,
      accessRefreshes: refreshes,
      selectedBusinessFilter: filter,
    );
  }

  // 회수 확인 — 재시도 성공 여부와 무관하게 캐시에서 제거한다.
  cached = cached.where((i) => !revoked.contains(i.businessId)).toList();
  if (filter != null && revoked.contains(filter)) filter = null;

  if (newScope.isEmpty) {
    return LoadOutcome(
      items: const [],
      cached: const [],
      listCalls: listCalls,
      accessRefreshes: refreshes,
      selectedBusinessFilter: filter,
    );
  }

  // ── 재시도 정확히 1회 ──
  listCalls++;
  if (retryFailure != Fail.none) {
    return LoadOutcome(
      cached: cached,
      listCalls: listCalls,
      accessRefreshes: refreshes,
      selectedBusinessFilter: filter,
    );
  }
  return LoadOutcome(
    items: serve(newScope),
    cached: cached,
    listCalls: listCalls,
    accessRefreshes: refreshes,
    selectedBusinessFilter: filter,
  );
}

void main() {
  const cachedAB = [Item('A'), Item('A'), Item('B'), Item('B')];

  // ── §22 정상 경로 ─────────────────────────────────────────────
  group('SCOPE-01 정상 경로에 비용이 없다', () {
    test('01-a 성공하면 access refresh 0 (§13, §21)', () {
      final r = loadWithRecovery(
        requestedScope: ['A', 'B'],
        serverAuthorized: ['A', 'B'],
        canonicalScopeAfterRefresh: ['A', 'B'],
        cachedItems: cachedAB,
      );
      expect(r.threw, false);
      expect(r.accessRefreshes, 0);
      expect(r.listCalls, 1);
      expect(r.items!.length, 4);
    });

    test('01-b 네트워크 실패는 기존 stale 계약 그대로다 (§2, §7)', () {
      final r = loadWithRecovery(
        requestedScope: ['A', 'B'],
        serverAuthorized: ['A', 'B'],
        canonicalScopeAfterRefresh: ['A'],
        cachedItems: cachedAB,
        firstFailure: Fail.network,
      );
      expect(r.threw, true);
      expect(r.accessRefreshes, 0, reason: '일시적 실패로 scope를 다시 읽지 않는다');
      expect(r.listCalls, 1);
      expect(r.cached.length, 4, reason: 'cached items를 지우지 않는다');
    });
  });

  // ── §5, §6, §11 회수 복구 ─────────────────────────────────────
  group('SCOPE-02 회수된 사업장에서 빠져나온다', () {
    test('02-a B 회수 → prune + 재시도 성공 (§11)', () {
      final r = loadWithRecovery(
        requestedScope: ['A', 'B'],
        serverAuthorized: ['A'], // B membership 회수됨
        canonicalScopeAfterRefresh: ['A'],
        cachedItems: cachedAB,
      );
      expect(r.threw, false);
      expect(r.accessRefreshes, 1);
      expect(r.listCalls, 2, reason: '재시도는 정확히 1회');
      expect(r.items!.every((i) => i.businessId == 'A'), true);
      expect(r.cached.any((i) => i.businessId == 'B'), false);
    });

    test('02-b 재시도가 네트워크로 실패해도 B는 돌아오지 않는다 (§6, §7)', () {
      final r = loadWithRecovery(
        requestedScope: ['A', 'B'],
        serverAuthorized: ['A'],
        canonicalScopeAfterRefresh: ['A'],
        cachedItems: cachedAB,
        retryFailure: Fail.network,
      );
      expect(r.threw, true);
      expect(r.cached.map((i) => i.businessId).toSet(), {'A'},
          reason: '권한이 사라진 데이터는 stale 허용 대상이 아니다');
      expect(r.cached.length, 2, reason: '여전히 authorized인 A는 유지된다');
      expect(r.listCalls, 2);
    });

    test('02-c 사용자가 당겨서 새로고침하지 않아도 복구된다 (§11)', () {
      // 이 replica의 입력에는 pull-to-refresh가 없다 — load 한 번으로 끝난다.
      final r = loadWithRecovery(
        requestedScope: ['A', 'B'],
        serverAuthorized: ['A'],
        canonicalScopeAfterRefresh: ['A'],
        cachedItems: cachedAB,
      );
      expect(r.items, isNotNull);
    });
  });

  // ── §3, §8, §9 사업장 삭제(not-found) ─────────────────────────
  group('SCOPE-10 삭제된 사업장도 같은 경로로 회복한다', () {
    test('10-a BUSINESS_ADMIN [A,B] → B 삭제 → not-found → [A] (§3)', () {
      final r = loadWithRecovery(
        requestedScope: ['A', 'B'],
        serverAuthorized: ['A'],
        deletedBusinesses: ['B'], // 문서 자체가 없다 → not-found
        canonicalScopeAfterRefresh: ['A'], // 트리거가 arrayRemove를 끝냈다
        cachedItems: cachedAB,
      );
      expect(r.threw, false);
      expect(r.accessRefreshes, 1);
      expect(r.listCalls, 2);
      expect(r.items!.every((i) => i.businessId == 'A'), true);
      expect(r.cached.any((i) => i.businessId == 'B'), false);
    });

    test('10-b 삭제 + scope가 유일했으면 빈 목록 (§8)', () {
      final r = loadWithRecovery(
        requestedScope: ['B'],
        serverAuthorized: const [],
        deletedBusinesses: ['B'],
        canonicalScopeAfterRefresh: const [],
        cachedItems: const [Item('B'), Item('B')],
      );
      expect(r.threw, false);
      expect(r.items, isEmpty);
      expect(r.cached, isEmpty);
      expect(r.listCalls, 1, reason: '빈 scope로 재요청하지 않는다');
    });

    // [POSTING-V2-03N.1] onBusinessDeleted는 문서 삭제 **뒤에** 실행되고,
    //   managedBusinessIds/subAdminBusinessIds 정리는 cascade 뒷부분이다.
    //   그 사이에는 "문서 없음 + scope에는 남음"이 실제로 가능하다.
    test('10-c 삭제 직후 scope가 아직 안 줄었으면 지우지 않는다 (§4, §9)', () {
      final r = loadWithRecovery(
        requestedScope: ['A', 'B'],
        serverAuthorized: ['A'],
        deletedBusinesses: ['B'],
        canonicalScopeAfterRefresh: ['A', 'B'], // 트리거가 아직 안 끝났다
        cachedItems: cachedAB,
      );
      expect(r.threw, true);
      expect(r.cached.length, 4, reason: '확인되지 않은 축소로 캐시를 건드리지 않는다');
      expect(r.listCalls, 1, reason: '같은 scope로 재시도하지 않는다');
    });

    test('10-d 다음 load에서 정리가 끝나면 회복한다 (§4)', () {
      // 10-c 직후 — 트리거가 완료된 뒤의 같은 load
      final r = loadWithRecovery(
        requestedScope: ['A', 'B'],
        serverAuthorized: ['A'],
        deletedBusinesses: ['B'],
        canonicalScopeAfterRefresh: ['A'],
        cachedItems: cachedAB,
      );
      expect(r.threw, false);
      expect(r.cached.map((i) => i.businessId).toSet(), {'A'});
    });

    test('10-e not-found + refresh 실패 → 임의 삭제 없음 (§2)', () {
      final r = loadWithRecovery(
        requestedScope: ['A', 'B'],
        serverAuthorized: ['A'],
        deletedBusinesses: ['B'],
        canonicalScopeAfterRefresh: ['A'],
        cachedItems: cachedAB,
        accessRefreshFails: true,
      );
      expect(r.threw, true);
      expect(r.cached.length, 4);
    });

    test('10-f 재시도도 not-found면 종료한다 (§7)', () {
      final r = loadWithRecovery(
        requestedScope: ['A', 'B'],
        serverAuthorized: const [],
        deletedBusinesses: ['B'],
        canonicalScopeAfterRefresh: ['A'],
        cachedItems: cachedAB,
        retryFailure: Fail.notFound,
      );
      expect(r.threw, true);
      expect(r.listCalls, 2, reason: '무한 복구 금지');
      expect(r.accessRefreshes, 1);
    });

    test('10-g 관계 없는 not-found는 캐시를 건드리지 않는다 (§2)', () {
      // scope는 그대로인데 다른 이유로 not-found가 온 경우
      final r = loadWithRecovery(
        requestedScope: ['A'],
        serverAuthorized: ['A'],
        canonicalScopeAfterRefresh: ['A'],
        cachedItems: const [Item('A'), Item('A')],
        firstFailure: Fail.notFound,
      );
      expect(r.threw, true);
      expect(r.cached.length, 2, reason: 'error code만으로 revoke를 추정하지 않는다');
      expect(r.listCalls, 1);
    });
  });

  // ── §9 scope unchanged ────────────────────────────────────────
  group('SCOPE-03 회수를 확인하지 못하면 지우지 않는다', () {
    test('03-a scope가 그대로면 캐시를 건드리지 않는다 (§9)', () {
      final r = loadWithRecovery(
        requestedScope: ['A', 'B'],
        serverAuthorized: ['A'],
        canonicalScopeAfterRefresh: ['A', 'B'], // 서버 전파 지연 등
        cachedItems: cachedAB,
      );
      expect(r.threw, true);
      expect(r.cached.length, 4);
      expect(r.listCalls, 1, reason: '같은 scope로 재시도하지 않는다');
      expect(r.accessRefreshes, 1);
    });

    test('03-b access refresh 자체가 실패하면 그대로 끝난다 (§19)', () {
      final r = loadWithRecovery(
        requestedScope: ['A', 'B'],
        serverAuthorized: ['A'],
        canonicalScopeAfterRefresh: ['A'],
        cachedItems: cachedAB,
        accessRefreshFails: true,
      );
      expect(r.threw, true);
      expect(r.cached.length, 4, reason: '확인하지 못한 회수로 데이터를 지우지 않는다');
      expect(r.listCalls, 1);
    });
  });

  // ── §8 scope 0 ────────────────────────────────────────────────
  group('SCOPE-04 남은 scope가 없을 때', () {
    test('04-a 전부 회수 → 캐시 비움 + 재요청 없음 (§8)', () {
      final r = loadWithRecovery(
        requestedScope: ['B'],
        serverAuthorized: const [],
        canonicalScopeAfterRefresh: const [],
        cachedItems: const [Item('B'), Item('B')],
      );
      expect(r.threw, false);
      expect(r.items, isEmpty);
      expect(r.cached, isEmpty, reason: 'unauthorized 데이터가 0이어야 한다');
      expect(r.listCalls, 1, reason: '빈 scope로 목록을 다시 부르지 않는다');
    });
  });

  // ── §4 retry 상한 ─────────────────────────────────────────────
  group('SCOPE-05 재시도는 최대 1회', () {
    test('05-a 재시도도 permission-denied면 종료한다 (§4)', () {
      final r = loadWithRecovery(
        requestedScope: ['A', 'B'],
        serverAuthorized: const [], // 재시도도 거부
        canonicalScopeAfterRefresh: ['A'],
        cachedItems: cachedAB,
        retryFailure: Fail.permissionDenied,
      );
      expect(r.threw, true);
      expect(r.listCalls, 2, reason: '무한 retry 금지');
      expect(r.accessRefreshes, 1);
    });
  });

  // ── §16, §17 filter / count ───────────────────────────────────
  group('SCOPE-06 필터와 개수가 새 scope로 정렬된다', () {
    test('06-a 회수된 사업장을 가리키던 필터가 해제된다 (§16)', () {
      final r = loadWithRecovery(
        requestedScope: ['A', 'B'],
        serverAuthorized: ['A'],
        canonicalScopeAfterRefresh: ['A'],
        cachedItems: cachedAB,
        selectedBusinessFilter: 'B',
      );
      expect(r.selectedBusinessFilter, isNull,
          reason: '없어진 선택지로 목록이 영원히 비어 있으면 안 된다');
    });

    test('06-b 살아 있는 사업장 필터는 유지된다 (§16)', () {
      final r = loadWithRecovery(
        requestedScope: ['A', 'B'],
        serverAuthorized: ['A'],
        canonicalScopeAfterRefresh: ['A'],
        cachedItems: cachedAB,
        selectedBusinessFilter: 'A',
      );
      expect(r.selectedBusinessFilter, 'A');
    });

    test('06-c items가 곧 count·filter 모집단이다 (§17)', () {
      final r = loadWithRecovery(
        requestedScope: ['A', 'B'],
        serverAuthorized: ['A'],
        canonicalScopeAfterRefresh: ['A'],
        cachedItems: cachedAB,
      );
      // 별도 count query 없이 같은 집합에서 파생된다
      expect(r.items!.map((i) => i.businessId).toSet(), {'A'});
      expect(r.cached.map((i) => i.businessId).toSet(), {'A'});
    });
  });

  // ── 클라이언트 배선 ───────────────────────────────────────────
  group('SCOPE-07 배선', () {
    late final String ctrl = _src(_ctrlPath);

    test('07-a recovery가 공통 load path에 있다 (§12)', () {
      final load = _flat(_codeOf(_bodyOf(ctrl, 'Future<void> _runOneLoad(')));
      expect(load.contains('_loadWithScopeRecovery('), true);
      expect(load.contains('getTOGroupItemsLight('), false,
          reason: '진입점마다 다른 경로가 생기면 계약이 갈라진다');
    });

    test('07-b 후보 코드 둘만 잡는다 (§1, §6)', () {
      final body = _flat(_codeOf(
          _bodyOf(ctrl, 'Future<List<TOGroupItem>> _loadWithScopeRecovery(')));
      expect(body.contains('} on FirebaseFunctionsException catch (e) {'), true);
      expect(
          body.contains('if (!_scopeShrinkCandidates.contains(e.code) '
              '|| requestedScope == null) { rethrow; }'),
          true);
      final set = _flat(_codeOf(ctrl));
      expect(
          set.contains("static const _scopeShrinkCandidates = "
              "{'permission-denied', 'not-found'};"),
          true,
          reason: 'network/unavailable/internal은 후보가 아니다');
    });

    test('07-c 선제 refresh를 넣지 않았다 (§13)', () {
      final load = _flat(_codeOf(_bodyOf(ctrl, 'Future<void> _runOneLoad(')));
      expect(load.contains('refreshAdminScopeState()'), false,
          reason: '정상 load 비용은 access read 0이어야 한다');
      final body = _flat(_codeOf(
          _bodyOf(ctrl, 'Future<List<TOGroupItem>> _loadWithScopeRecovery(')));
      // refresh는 catch 안에서만 일어난다
      final catchIdx = body.indexOf('} on FirebaseFunctionsException catch (e) {');
      expect(body.indexOf('refreshAdminScopeState()'), greaterThan(catchIdx));
    });

    test('07-d 회수 확인 → prune → 재시도 순서다 (§5, §6)', () {
      final body = _codeOf(
          _bodyOf(ctrl, 'Future<List<TOGroupItem>> _loadWithScopeRecovery('));
      final revokedIdx = body.indexOf('final revoked =');
      final pruneIdx = body.indexOf('_pruneRevokedItems(revoked);');
      final retryIdx = body.lastIndexOf('_service.getTOGroupItemsLight(');
      expect(revokedIdx, greaterThan(-1));
      expect(pruneIdx, greaterThan(revokedIdx));
      expect(retryIdx, greaterThan(pruneIdx),
          reason: '재시도 전에 unauthorized 캐시를 비운다');
    });

    test('07-e scope 미변경/빈 scope 분기가 있다 (§8, §9)', () {
      final body = _flat(_codeOf(
          _bodyOf(ctrl, 'Future<List<TOGroupItem>> _loadWithScopeRecovery(')));
      expect(body.contains('if (revoked.isEmpty) {'), true);
      expect(body.contains('if (newScope.isEmpty) { return []; }'), true);
    });

    test('07-f prune이 캐시·이름·필터를 함께 정리한다 (§15, §16, §17)', () {
      final body = _flat(_codeOf(
          _bodyOf(ctrl, 'void _pruneRevokedItems(Set<String> revokedBusinessIds)')));
      expect(body.contains('!revokedBusinessIds.contains(g.businessId)'), true);
      expect(body.contains('_knownBusinessNames = _items'), true);
      expect(body.contains('_selectedBusinessId = null;'), true);
    });

    test('07-g scope 계산이 한 곳이다 (§15)', () {
      final body = _flat(_codeOf(_bodyOf(ctrl, 'List<String>? _scopeOf(UserModel user)')));
      expect(body.contains('if (user.isSuperAdmin) return null;'), true);
      expect(body.contains('if (user.isSubAdmin) return user.subAdminBusinessIds;'),
          true);
      expect(body.contains('return user.managedBusinessIds;'), true);
    });
  });

  // ── §3 role coverage ──────────────────────────────────────────
  group('SCOPE-08 role별 canonical refresh', () {
    late final String provider = _src(_providerPath);

    test('08-a SUB_ADMIN은 기존 함수를 그대로 쓴다 (§3)', () {
      final body = _flat(_codeOf(
          _bodyOf(provider, 'Future<void> refreshAdminScopeState()')));
      expect(body.contains('if (user.isSubAdmin) return refreshSubAdminAccessState();'),
          true,
          reason: '새 membership 아키텍처를 만들지 않는다');
    });

    test('08-b BUSINESS_ADMIN은 users 문서 1건만 다시 읽는다 (§3, §21)', () {
      final body = _flat(_codeOf(
          _bodyOf(provider, 'Future<void> _reloadCurrentUserDoc()')));
      expect(
          body.contains(
              "FirebaseFirestore.instance.collection('users').doc(uid).get()"),
          true);
      expect(body.contains('_hydrateSubAdminPermissions'), false,
          reason: 'BUSINESS_ADMIN에는 권한 맵 개념이 없다');
    });

    test('08-c 그 밖의 role은 no-op이다 (§3)', () {
      final body = _flat(_codeOf(
          _bodyOf(provider, 'Future<void> refreshAdminScopeState()')));
      expect(body.contains('if (!user.isBusinessAdmin) return Future.value();'),
          true);
    });

    test('08-d 동시 호출을 하나로 합친다 (§21)', () {
      final body = _flat(_codeOf(
          _bodyOf(provider, 'Future<void> refreshAdminScopeState()')));
      expect(body.contains('final inFlight = _accessRefreshInFlight;'), true);
      expect(body.contains('if (inFlight != null) return inFlight;'), true);
    });

    test('08-e 읽기 실패로 범위를 추측해 줄이지 않는다 (§19)', () {
      final body = _flat(_codeOf(
          _bodyOf(provider, 'Future<void> _reloadCurrentUserDoc()')));
      expect(body.contains('} catch (e) {'), true);
      expect(body.contains('_currentUser = null'), false);
      expect(body.contains('managedBusinessIds ='), false);
    });
  });

  // ── §1, §18, §23 무회귀 ───────────────────────────────────────
  group('SCOPE-09 서버·write 무회귀', () {
    test('09-a strict all-or-nothing 유지 (§1, §23)', () {
      final fns = _flat(_src(_fnsPath));
      // [R5-D2] 자격이 canManageTo 로 올라갔다. all-or-nothing(MODEL A)은 그대로.
      expect(
          fns.contains(
              'await Promise.all(ids.map(id => srvAssertToAuthority(callerUid, id)));'),
          true,
          reason: 'MODEL A는 canonical policy다');
    });

    test('09-b write는 대상 TO의 businessId로 재검증한다 (§18)', () {
      final fns = _src(_fnsPath);
      expect(
          fns.contains('const businessId = toData.businessId as string | undefined;'),
          true,
          reason: '목록에 보였다는 사실을 write 권한으로 쓰지 않는다');
    });

    // [POSTING-V2-03N.1 §4] 삭제 트리거의 실제 순서를 사실대로 고정한다.
    //   onDocumentDeleted이므로 문서는 이미 없고, scope 정리는 cascade 뒤쪽이다.
    //   그래서 "문서 없음 + scope에 남음" 창이 실재하고, 그때는 10-c대로
    //   임의 prune하지 않는다.
    test('09-d 사업장 삭제는 문서 삭제 뒤에 scope를 정리한다 (§4)', () {
      final fns = _src(_fnsPath);
      final start =
          fns.indexOf('export const onBusinessDeleted = onDocumentDeleted(');
      expect(start, greaterThan(-1));
      final managed = fns.indexOf(
          'managedBusinessIds: admin.firestore.FieldValue.arrayRemove(businessId)',
          start);
      expect(managed, greaterThan(-1), reason: 'BUSINESS_ADMIN scope 정리가 있다');
      // cascade 정리(Promise.all)보다 뒤다 — 비원자 창이 존재한다
      final cascade = fns.indexOf('deleteByBusinessId("review_requests")', start);
      expect(cascade, greaterThan(-1));
      expect(cascade, lessThan(managed));
    });

    test('09-e SUB_ADMIN scope도 같은 트리거가 정리한다 (§5)', () {
      final fns = _src(_fnsPath);
      final start =
          fns.indexOf('export const onBusinessDeleted = onDocumentDeleted(');
      final sub = fns.indexOf(
          'subAdminBusinessIds: admin.firestore.FieldValue.arrayRemove(businessId)',
          start);
      expect(sub, greaterThan(-1),
          reason: 'SUB_ADMIN에도 삭제된 사업장이 남을 수 있다');
      // 같은 refreshAdminScopeState가 그 축소를 읽는다
      final provider = _flat(_codeOf(
          _bodyOf(_src(_providerPath), 'Future<void> refreshAdminScopeState()')));
      expect(provider.contains('return refreshSubAdminAccessState();'), true);
    });

    test('09-c 기존 access → data 경로를 망가뜨리지 않았다 (§14)', () {
      final list = _codeOf(_src(
          'lib/screens/business_admin/workforce_management/workforce_list_view.dart'));
      expect(list.contains('await up.refreshSubAdminAccessState();'), true);
      final jobs =
          _codeOf(_src('lib/screens/business_admin/jobs_root_screen.dart'));
      expect(jobs.contains('up.refreshSubAdminAccessState().whenComplete('), true);
    });
  });
}
