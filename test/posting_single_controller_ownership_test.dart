// [POSTING-V2-03O.1] 공고 controller 하나 + 요청을 버리지 않는 load
//
// 03O READ에서 확인된 것:
//   · JobsRootScreen과 WorkforceRootScreen이 각각 WorkforceController를
//     만들었고, Shell의 IndexedStack이 둘을 동시에 mount했다. 그래서 최초
//     진입·FCM·resume·Home mutation마다 callableGetAdminTOs와 전 FLEX 슬롯
//     preload가 두 벌씩 돌았다.
//   · load()의 `if (_isLoading) return;`이 진행 중 들어온 요청을 **버렸다**.
//     진행 중인 load가 mutation보다 앞선 데이터를 들고 있어도 그 mutation이
//     유발한 reload가 사라져 화면이 낡은 채로 고착될 수 있었다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _ctrlPath = 'lib/controllers/workforce_controller.dart';
const _shellPath = 'lib/screens/business_admin/business_admin_shell.dart';
const _jobsPath = 'lib/screens/business_admin/jobs_root_screen.dart';
const _wfPath =
    'lib/screens/business_admin/workforce_management/workforce_root_screen.dart';

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
// load coalescing replica
// ═══════════════════════════════════════════════════════════════

/// `_runLoadCycle` / `_requestLoad`의 순차 coalescing 재현.
class LoadCoalescer {
  /// 각 회차가 사용한 scope — 매 회차 다시 계산한다.
  final List<List<String>> fetchedScopes = [];

  /// 회차마다 실패시킬지. 큐가 비면 성공.
  final List<bool> failurePlan;

  /// 현재 canonical scope. 테스트가 도중에 바꿀 수 있다.
  List<String> scope;

  /// 이 회차(1-based) **도중에** 새 요청이 도착한다 — mutation·FCM·revision.
  /// `_pending = false` 이후에 들어오는 실제 타이밍을 재현한다.
  final Set<int> requestDuringFetchAt;

  /// 이 회차 도중 canonical scope가 이 값으로 바뀐다.
  final Map<int, List<String>> scopeChangeDuringFetch;

  bool _running = false;
  bool _pending = false;
  Object? loadError;

  /// 가장 최근에 commit된 결과(마지막 fetch가 이긴다).
  String? committed;

  LoadCoalescer({
    required this.scope,
    List<bool>? failurePlan,
    Set<int>? requestDuringFetchAt,
    Map<int, List<String>>? scopeChangeDuringFetch,
  })  : failurePlan = failurePlan ?? [],
        requestDuringFetchAt = requestDuringFetchAt ?? const {},
        scopeChangeDuringFetch = scopeChangeDuringFetch ?? const {};

  int fetchCount = 0;

  /// 진행 중이면 pending으로 접고, 아니면 사이클을 시작한다.
  void request() {
    if (_running) {
      _pending = true;
      return;
    }
    _runCycle();
  }

  void _runCycle() {
    _running = true;
    try {
      do {
        _pending = false;
        _runOne();
      } while (_pending);
    } finally {
      _running = false;
    }
  }

  void _runOne() {
    fetchCount++;
    final n = fetchCount;
    // scope는 회차마다 다시 읽는다 — 첫 요청의 낡은 scope를 재사용하지 않는다.
    fetchedScopes.add([...scope]);
    loadError = null;
    final fails = failurePlan.isNotEmpty ? failurePlan.removeAt(0) : false;

    // ── 이 회차가 진행되는 동안 일어나는 일들 ──
    final changed = scopeChangeDuringFetch[n];
    if (changed != null) scope = [...changed];
    if (requestDuringFetchAt.contains(n)) _pending = true;

    if (fails) {
      loadError = 'network';
      return;
    }
    committed = 'result@$n:${fetchedScopes[n - 1].join(",")}';
  }

  bool get idle => !_running && !_pending;
}

void main() {
  // ── §25 ownership ─────────────────────────────────────────────
  group('OWNER-01 controller는 Shell이 하나만 만든다', () {
    test('01-a production 생성 지점이 Shell 하나다', () {
      final shell = _codeOf(_src(_shellPath));
      expect(
          shell.contains(
              'final WorkforceController _postingController = WorkforceController();'),
          true);
    });

    test('01-b 두 Root가 같은 instance를 주입받는다', () {
      final shell = _flat(_codeOf(_src(_shellPath)));
      expect(
          shell.contains('JobsRootScreen(postingController: _postingController)'),
          true);
      expect(
          shell.contains(
              'WorkforceRootScreen(postingController: _postingController)'),
          true);
    });

    test('01-c Root는 주입이 없을 때만 자체 인스턴스를 만든다', () {
      for (final p in [_jobsPath, _wfPath]) {
        final code = _flat(_codeOf(_src(p)));
        expect(
            code.contains('late final WorkforceController _controller = '
                'widget.postingController ?? WorkforceController();'),
            true,
            reason: p);
      }
    });

    test('01-d dispose는 소유자만 한다 (§4)', () {
      final shell = _codeOf(_src(_shellPath));
      expect(shell.contains('_postingController.dispose();'), true);
      for (final p in [_jobsPath, _wfPath]) {
        final code = _flat(_codeOf(_src(p)));
        expect(code.contains('if (_ownsController) _controller.dispose();'), true,
            reason: p);
        expect(
            code.contains('bool get _ownsController => '
                'widget.postingController == null;'),
            true,
            reason: p);
      }
    });
  });

  // ── §2, §3, §6, §7, §8 lifecycle owner ────────────────────────
  group('OWNER-02 공고 lifecycle owner는 JobsRoot 하나다', () {
    late final String jobs = _codeOf(_src(_jobsPath));
    late final String wf = _codeOf(_src(_wfPath));

    test('02-a JobsRoot가 초기 load·FCM·resume·revision을 모두 갖는다 (§2)', () {
      expect(jobs.contains('_controller.load(context);'), true);
      expect(jobs.contains('FCMService().addAdminRefreshListener('), true);
      expect(jobs.contains('void didChangeAppLifecycleState('), true);
      expect(jobs.contains('WorkforceController.dataRevision.addListener('), true);
    });

    test('02-b WorkforceRoot에 공고 FCM listener가 없다 (§6)', () {
      expect(wf.contains('addAdminRefreshListener'), false);
      expect(wf.contains('FCMService'), false);
    });

    test('02-c WorkforceRoot에 공고 resume reload가 없다 (§7)', () {
      expect(wf.contains('didChangeAppLifecycleState'), false);
      expect(wf.contains('WidgetsBindingObserver'), false);
    });

    test('02-d WorkforceRoot에 공고 revision listener가 없다 (§8)', () {
      expect(wf.contains('dataRevision.addListener'), false);
      expect(wf.contains('_onDataRevisionChanged'), false);
    });

    // [R8-P1A 갱신] 원래 계약의 전제는 "Shell의 IndexedStack이 두 Root를 동시에
    //   mount한다"였다. 그래서 Jobs가 반드시 먼저 로드했고, Workforce는 조용히
    //   소비만 하면 됐다.
    //
    //   탭이 lazy first-open이 되면서 그 전제가 사라졌다. 관리자가 공고 탭을
    //   거치지 않고 근무 탭을 먼저 열면 공유 controller는 비어 있고, 이 화면은
    //   hasLoadedOnce를 기다리므로 영구 스피너가 된다.
    //
    //   변하지 않은 계약: **무조건 로드하지 않는다.** 비어 있을 때만 낸다.
    test('02-e WorkforceRoot의 초기 load는 조건부다 — standalone 또는 빈 controller (§3, §5)', () {
      final body = _flat(_codeOf(_bodyOf(_src(_wfPath), 'void initState()')));
      expect(body.contains('if (_ownsController || !_controller.hasLoadedOnce)'), true,
          reason: 'Shell 경로에서는 controller가 비어 있을 때만 로드한다');
      final condAt = body.indexOf('if (_ownsController || !_controller.hasLoadedOnce)');
      final loadAt = body.indexOf('_controller.load(context);');
      expect(loadAt, greaterThan(condAt),
          reason: '조건 없는 load가 아니다 — 가드 뒤에서만 호출된다');
    });

    test('02-f WorkforceRoot는 controller를 소비만 한다 (§3)', () {
      final code = _flat(wf);
      // 값 읽기는 유지
      expect(code.contains('controller.items.isNotEmpty'), true);
      expect(code.contains('controller.knownBusinessNames'), true);
      // 그러나 자체 reload 경로는 없다
      expect(code.contains('_controller.reload('), false);
    });
  });

  // ── §10, §13, §14 non-dropping ────────────────────────────────
  group('OWNER-03 진행 중 요청을 버리지 않는다', () {
    test('03-a silent drop guard가 사라졌다 (§10)', () {
      final code = _flat(_codeOf(_src(_ctrlPath)));
      expect(code.contains('if (_isLoading) return;'), false,
          reason: '두 번째 요청을 버리던 guard');
    });

    test('03-b 진행 중이면 pending으로 접고 같은 사이클을 돌려준다 (§11, §12)', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_ctrlPath), 'Future<void> _requestLoad(UserProvider userProvider)')));
      expect(
          body.contains('if (cycle != null) { _pendingLoad = true; return cycle; }'),
          true,
          reason: 'caller가 await하면 follow-up까지 기다린다');
    });

    test('03-c pending이 남아 있으면 사이클이 한 번 더 돈다 (§13)', () {
      final body = _flat(_codeOf(_bodyOf(
          _src(_ctrlPath), 'Future<void> _runLoadCycle(UserProvider userProvider)')));
      expect(
          body.contains('do { _pendingLoad = false; '
              'await _runOneLoad(userProvider); } while (_pendingLoad);'),
          true);
    });

    test('03-d revision listener가 loading 중 요청을 버리지 않는다 (§14)', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_jobsPath), 'void _onDataRevisionChanged()')));
      expect(body.contains('_controller.isLoading'), false,
          reason: 'caller가 먼저 버리면 controller가 coalesce할 기회가 없다');
      expect(body.contains('if (!mounted) return;'), true);
    });

    test('03-e 회차 실패가 예외로 새지 않는다 (§18)', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_ctrlPath), 'Future<void> _runOneLoad(UserProvider userProvider)')));
      expect(body.contains('} catch (e) {'), true);
      expect(body.contains('_loadError = e;'), true);
      expect(body.contains('rethrow'), false,
          reason: '던지면 pending follow-up이 사라진다');
    });
  });

  // ── §11, §19, §27 coalescing 동작 ─────────────────────────────
  group('OWNER-04 coalescing', () {
    test('04-a idle에서 요청 1건 → fetch 1회', () {
      final c = LoadCoalescer(scope: ['A']);
      c.request();
      expect(c.fetchCount, 1);
      expect(c.idle, true);
    });

    test('04-b 진행 중 요청 여러 건 → follow-up 1회로 합쳐진다 (§11)', () {
      // 1회차 도중 mutation·FCM·revision이 겹쳐 들어온다
      final c = LoadCoalescer(scope: ['A'], requestDuringFetchAt: {1});
      c.request();
      expect(c.fetchCount, 2, reason: '병렬 3회가 아니라 follow-up 1회');
      expect(c.idle, true);
    });

    test('04-c mutation이 진행 중이던 load 뒤에 반드시 반영된다 (§27)', () {
      final c = LoadCoalescer(scope: ['A'], requestDuringFetchAt: {1});
      c.request();
      expect(c.fetchCount, 2);
      expect(c.committed, 'result@2:A',
          reason: 'mutation 이후 fetch 결과가 최종이어야 한다');
    });

    test('04-d 요청이 남아 있는데 idle로 끝나지 않는다 (§13 불변식)', () {
      final c = LoadCoalescer(scope: ['A'], requestDuringFetchAt: {1, 2});
      c.request();
      expect(c.idle, true);
      expect(c.fetchCount, 3, reason: '남은 요청마다 사이클이 이어진다');
    });

    test('04-e 순차 실행이라 오래된 결과가 최신을 덮지 않는다 (§19)', () {
      final c = LoadCoalescer(scope: ['A'], requestDuringFetchAt: {1});
      c.request();
      expect(c.committed, 'result@2:A');
      expect(c.fetchedScopes.length, 2);
    });
  });

  // ── §16, §28 scope 재계산 ─────────────────────────────────────
  group('OWNER-05 follow-up은 최신 scope를 쓴다', () {
    test('05-a pending 사이 scope가 줄면 follow-up이 새 scope로 돈다 (§16)', () {
      // 1회차 도중 B 배정이 회수되고, 같은 시점에 재요청이 들어온다
      final c = LoadCoalescer(
        scope: ['A', 'B'],
        requestDuringFetchAt: {1},
        scopeChangeDuringFetch: {
          1: ['A']
        },
      );
      c.request();
      expect(c.fetchedScopes.first, ['A', 'B']);
      expect(c.fetchedScopes.last, ['A'],
          reason: '첫 요청의 낡은 [A,B]를 재사용하면 03N recovery가 무의미해진다');
    });

    test('05-b 서버 배선: scope는 회차마다 다시 계산된다 (§16)', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_ctrlPath), 'Future<void> _runOneLoad(UserProvider userProvider)')));
      expect(body.contains('final List<String>? businessIds = _scopeOf(user);'),
          true);
      expect(body.contains('final user = userProvider.currentUser;'), true,
          reason: 'context가 아니라 provider에서 매번 읽는다');
    });
  });

  // ── §18 failure + pending ─────────────────────────────────────
  group('OWNER-06 실패해도 pending을 잃지 않는다', () {
    test('06-a 첫 회차 실패 + pending → 두 번째 회차가 돈다 (§18)', () {
      final c = LoadCoalescer(
        scope: ['A'],
        failurePlan: [true],
        requestDuringFetchAt: {1},
      );
      c.request();
      expect(c.fetchCount, 2, reason: '실패했다고 pending을 잃지 않는다');
      expect(c.loadError, isNull, reason: '두 번째 회차가 성공해 상태가 회복된다');
      expect(c.committed, 'result@2:A');
    });

    test('06-b 실패만으로 무한 반복하지 않는다 (§18)', () {
      final c = LoadCoalescer(scope: ['A'], failurePlan: [true]);
      c.request();
      expect(c.fetchCount, 1, reason: '실패는 pending을 만들지 않는다');
      expect(c.loadError, 'network');
      expect(c.idle, true);
    });
  });

  // ── §17, §29 무회귀 ───────────────────────────────────────────
  group('OWNER-07 기존 계약 무회귀', () {
    test('07-a 03N scope recovery가 그대로다 (§17)', () {
      final code = _flat(_codeOf(_src(_ctrlPath)));
      expect(
          code.contains("static const _scopeShrinkCandidates = "
              "{'permission-denied', 'not-found'};"),
          true);
      expect(code.contains('_pruneRevokedItems(revoked);'), true);
      expect(code.contains('await userProvider.refreshAdminScopeState();'), true);
    });

    test('07-b 02B origin self-skip이 그대로다 (§8)', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_jobsPath), 'void _onDataRevisionChanged()')));
      expect(
          body.contains('if (WorkforceController.lastMutationOrigin == '
              'AdminMutationOrigin.jobs) { return; }'),
          true);
    });

    test('07-c pull-to-refresh access → data 순서 유지 (§29)', () {
      final list = _codeOf(_src(
          'lib/screens/business_admin/workforce_management/workforce_list_view.dart'));
      expect(list.contains('await up.refreshSubAdminAccessState();'), true);
      final idx = list.indexOf('await up.refreshSubAdminAccessState();');
      expect(list.indexOf('controller.reload(context)'), greaterThan(idx));
    });

    test('07-d reload는 여전히 load로 위임한다 (§20)', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_ctrlPath), 'Future<void> reload(BuildContext context)')));
      expect(body.contains('_onExternalReloadCallback?.call();'), true);
      expect(body.contains('return load(context);'), true);
    });

    test('07-e FLEX preload 계약은 건드리지 않았다 (§23)', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_ctrlPath), 'Future<void> _runOneLoad(UserProvider userProvider)')));
      expect(body.contains('_service.loadFlexSlots('), true);
      expect(body.contains('_items.where((g) => g.masterTO.isFlexType)'), true);
    });

    test('07-f cascade close 후처리가 사이클 끝에 남아 있다 (§20)', () {
      final body = _flat(_codeOf(_bodyOf(
          _src(_ctrlPath), 'Future<void> _runLoadCycle(UserProvider userProvider)')));
      expect(body.contains('if (_loadError != null) return;'), true);
      expect(body.contains('_maybeCascadeCloseExpiredTO(group, group.groupTOs);'),
          true);
      expect(body.contains('_maybeCascadeCloseExpiredContractTOs();'), true);
    });

    test('07-g polling·강제 전체 reload를 추가하지 않았다 (§29)', () {
      for (final p in [_ctrlPath, _shellPath, _jobsPath, _wfPath]) {
        final code = _codeOf(_src(p));
        expect(code.contains('Timer.periodic'), false, reason: p);
      }
    });
  });
}
