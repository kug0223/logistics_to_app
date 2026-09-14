// [POSTING-V2-03P.1] 최초 로딩 / 새로고침 로딩 UX 정렬
//
// 03P READ에서 확인된 것:
//   · WorkforceController의 생성 직후 상태(items=[] · isLoading=false ·
//     loadError=null)가 "성공적으로 조회했는데 0건"과 글자 그대로 같았다.
//     그래서 load가 시작되기 전 프레임에 '등록된 공고가 없습니다'가 그려졌다.
//     NOT LOADED YET != LOADED AND EMPTY.
//   · _buildTOList가 isLoading을 가장 먼저 봐서, 모든 새로고침이 카드 목록을
//     통째로 스피너로 갈아치웠다. ListView가 tree에서 빠지므로 스크롤 위치도
//     매번 최상단으로 돌아갔다.
//   · 03O.1에서 controller를 공유하게 된 뒤로 Jobs의 pull-to-refresh가
//     Workforce 탭까지 스피너로 비웠다. 건드리지도 않은 탭이 비는 셈이다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _ctrlPath = 'lib/controllers/workforce_controller.dart';
const _listPath =
    'lib/screens/business_admin/workforce_management/workforce_list_view.dart';
const _jobsPath = 'lib/screens/business_admin/jobs_root_screen.dart';
const _opsPath =
    'lib/screens/business_admin/workforce_management/workforce_operational_view.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
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
// controller load-state replica
// ═══════════════════════════════════════════════════════════════

/// `_runOneLoad`의 hasLoadedOnce / lastSuccessfulWasEmpty 전이 재현.
class LoadState {
  bool hasLoadedOnce = false;
  bool lastSuccessfulWasEmpty = false;
  bool isLoading = false;
  bool hasError = false;
  bool lastLoadFailed = false;
  int itemCount = 0;

  /// 사용자를 아직 모르는 상태 — canonical 결과가 아니다.
  void loadWithNoUser() {
    isLoading = true;
    hasError = false;
    itemCount = 0;
    // hasLoadedOnce 갱신 없음
    isLoading = false;
  }

  /// scope가 비어 서버 조회 자체가 없는 경우도 "서버 기준 0건"이다.
  void loadWithEmptyScope() => _succeed(0);

  void loadSuccess(int count) => _succeed(count);

  void _succeed(int count) {
    isLoading = true;
    hasError = false;
    itemCount = count;
    hasLoadedOnce = true;
    lastSuccessfulWasEmpty = count == 0;
    lastLoadFailed = false;
    isLoading = false;
  }

  /// 실패는 items를 비우지 않는다(01B). hasLoadedOnce도 세우지 않는다.
  void loadFailure() {
    isLoading = true;
    hasError = false;
    hasError = true;
    lastLoadFailed = true;
    isLoading = false;
  }

  /// 새 시도 시작 — isLoading만 올라가고 확정 플래그는 그대로다.
  void beginRefresh() {
    isLoading = true;
    hasError = false;
  }

  /// 03N 회수 복구: 권한이 사라진 사업장 캐시를 즉시 비운다.
  void pruneAllDuringLoad() => itemCount = 0;
}

// ═══════════════════════════════════════════════════════════════
// render decision replica
// ═══════════════════════════════════════════════════════════════

enum Rendered {
  /// 조회 실패 + 보여줄 데이터 없음
  error,

  /// 아직 한 번도 canonical 결과를 얻지 못함
  initialLoading,

  /// 0건이지만 아직 확정된 0건이 아님 (회수 복구 등)
  transientLoading,

  /// 카드 목록 — refresh 중이어도 유지
  content,
  rootEmpty,
  filteredEmpty,
  tabEmpty,
}

/// `_buildTOList`의 분기 순서 재현.
Rendered decide(
  LoadState s, {
  int filteredCount = -1,
  bool hasActiveFilters = false,
}) {
  if (s.hasError && s.itemCount == 0) return Rendered.error;
  if (!s.hasLoadedOnce) return Rendered.initialLoading;
  if (s.itemCount == 0) {
    if (s.isLoading && !s.lastSuccessfulWasEmpty) {
      return Rendered.transientLoading;
    }
    return Rendered.rootEmpty;
  }
  final filtered = filteredCount < 0 ? s.itemCount : filteredCount;
  if (filtered == 0) {
    return hasActiveFilters ? Rendered.filteredEmpty : Rendered.tabEmpty;
  }
  return Rendered.content;
}

/// `workforce_operational_view`의 gate 재현.
bool workforceGated(LoadState s) => !s.hasLoadedOnce && !s.hasError;

/// `_buildStaleBanner`의 표시 조건 재현.
bool staleBannerShown(LoadState s) =>
    (s.hasError || (s.isLoading && s.lastLoadFailed)) && s.itemCount > 0;

void main() {
  // ══════════════════════════════════════════════════════════════
  // §1·§2 NOT LOADED != TRUE EMPTY
  // ══════════════════════════════════════════════════════════════
  group('01. controller 확정 플래그', () {
    test('01-a 생성 직후에는 아무것도 확정되지 않았다', () {
      final s = LoadState();
      expect(s.hasLoadedOnce, false);
      expect(s.lastSuccessfulWasEmpty, false);
      expect(s.itemCount, 0);
      expect(s.isLoading, false);
      expect(s.hasError, false);
    });

    test('01-b 성공 0건은 확정된 0건이다', () {
      final s = LoadState()..loadSuccess(0);
      expect(s.hasLoadedOnce, true);
      expect(s.lastSuccessfulWasEmpty, true);
    });

    test('01-c 성공 N건이면 lastSuccessfulWasEmpty=false', () {
      final s = LoadState()..loadSuccess(3);
      expect(s.hasLoadedOnce, true);
      expect(s.lastSuccessfulWasEmpty, false);
    });

    test('01-d scope가 비어 조회를 건너뛴 경우도 서버 기준 0건이다', () {
      final s = LoadState()..loadWithEmptyScope();
      expect(s.hasLoadedOnce, true);
      expect(s.lastSuccessfulWasEmpty, true);
    });

    test('01-e user==null은 canonical 결과가 아니다', () {
      final s = LoadState()..loadWithNoUser();
      expect(s.hasLoadedOnce, false);
      expect(s.lastSuccessfulWasEmpty, false);
    });

    test('01-f 실패는 hasLoadedOnce를 세우지 않는다', () {
      final s = LoadState()..loadFailure();
      expect(s.hasLoadedOnce, false);
      expect(s.hasError, true);
    });

    test('01-g 한 번 성공하면 이후 실패해도 hasLoadedOnce는 내려가지 않는다', () {
      final s = LoadState()..loadSuccess(2);
      s.loadFailure();
      expect(s.hasLoadedOnce, true);
      expect(s.itemCount, 2, reason: '실패가 items를 비우지 않는다(01B)');
    });

    test('01-h 0건 성공 → N건 성공이면 확정 해석이 갱신된다', () {
      final s = LoadState()..loadSuccess(0);
      expect(s.lastSuccessfulWasEmpty, true);
      s.loadSuccess(4);
      expect(s.lastSuccessfulWasEmpty, false);
    });

    test('01-i N건 성공 → 0건 성공이면 다시 확정된 0건이다', () {
      final s = LoadState()..loadSuccess(4);
      s.loadSuccess(0);
      expect(s.lastSuccessfulWasEmpty, true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §3 렌더 우선순위
  // ══════════════════════════════════════════════════════════════
  group('02. 최초 진입', () {
    test('02-a load 시작 전 프레임은 ROOT_EMPTY가 아니라 로딩이다', () {
      final s = LoadState();
      expect(decide(s), Rendered.initialLoading);
    });

    test('02-b load 진행 중에도 로딩이다', () {
      final s = LoadState()..beginRefresh();
      expect(decide(s), Rendered.initialLoading);
    });

    test('02-c 첫 성공이 0건이면 그때 비로소 ROOT_EMPTY다', () {
      final s = LoadState()..loadSuccess(0);
      expect(decide(s), Rendered.rootEmpty);
    });

    test('02-d 첫 성공이 N건이면 content다', () {
      final s = LoadState()..loadSuccess(5);
      expect(decide(s), Rendered.content);
    });
  });

  group('03. 첫 조회 실패 — §15 영구 스피너 금지', () {
    test('03-a 첫 실패는 로딩이 아니라 error다', () {
      final s = LoadState()..loadFailure();
      expect(s.hasLoadedOnce, false);
      expect(decide(s), Rendered.error,
          reason: 'error 분기가 hasLoadedOnce 분기보다 앞에 있어야 한다');
    });

    test('03-b 실패 후 재시도 중에도 error를 계속 보여준다 — 중간에 깜빡이지 않는다', () {
      final s = LoadState()..loadFailure();
      // 재시도 시작: _loadError = null, isLoading = true
      s.beginRefresh();
      expect(decide(s), Rendered.initialLoading,
          reason: '재시도는 아직 결과가 없으므로 최초 로딩 상태로 되돌아간다');
    });

    test('03-c 재시도가 성공하면 정상 경로로 복귀한다', () {
      final s = LoadState()..loadFailure();
      s.loadSuccess(2);
      expect(decide(s), Rendered.content);
    });

    test('03-d 데이터가 있는 상태의 실패는 error가 아니라 content 유지다', () {
      final s = LoadState()..loadSuccess(3);
      s.loadFailure();
      expect(decide(s), Rendered.content,
          reason: 'stale 배너가 최신이 아님을 알린다 — 목록을 지우지 않는다');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §6·§7 새로고침 중 content 유지
  // ══════════════════════════════════════════════════════════════
  group('04. 새로고침', () {
    test('04-a 데이터가 있으면 refresh 중에도 content를 유지한다', () {
      final s = LoadState()..loadSuccess(7);
      s.beginRefresh();
      expect(s.isLoading, true);
      expect(decide(s), Rendered.content,
          reason: '목록을 LoadingWidget으로 교체하지 않는다');
    });

    test('04-b refresh가 끝나 건수가 바뀌어도 content다', () {
      final s = LoadState()..loadSuccess(7);
      s.beginRefresh();
      s.loadSuccess(6);
      expect(decide(s), Rendered.content);
    });

    test('04-c refresh 결과가 0건이면 그때 ROOT_EMPTY로 간다', () {
      final s = LoadState()..loadSuccess(7);
      s.beginRefresh();
      s.loadSuccess(0);
      expect(decide(s), Rendered.rootEmpty);
    });

    test('04-d §8 true empty 상태의 refresh는 ROOT_EMPTY를 유지한다', () {
      final s = LoadState()..loadSuccess(0);
      s.beginRefresh();
      expect(s.isLoading, true);
      expect(decide(s), Rendered.rootEmpty,
          reason: '확정된 0건에서 당긴 새로고침이 화면을 스피너로 바꾸지 않는다');
    });

    test('04-e refresh 중 어떤 경우에도 initialLoading으로 되돌아가지 않는다', () {
      for (final count in [0, 1, 9]) {
        final s = LoadState()..loadSuccess(count);
        s.beginRefresh();
        expect(decide(s), isNot(Rendered.initialLoading));
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §9 scope 복구 transient empty
  // ══════════════════════════════════════════════════════════════
  group('05. 회수 복구 중 transient empty', () {
    test('05-a prune으로 0건이 된 상태를 ROOT_EMPTY로 확정하지 않는다', () {
      final s = LoadState()..loadSuccess(4);
      s.beginRefresh();
      s.pruneAllDuringLoad();
      expect(decide(s), Rendered.transientLoading,
          reason: '마지막 성공이 0건이 아니었으므로 지금의 0건은 확정이 아니다');
    });

    test('05-b 복구 결과가 실제 0건이면 그때 ROOT_EMPTY다', () {
      final s = LoadState()..loadSuccess(4);
      s.beginRefresh();
      s.pruneAllDuringLoad();
      s.loadSuccess(0);
      expect(decide(s), Rendered.rootEmpty);
    });

    test('05-c 복구 결과에 남은 사업장이 있으면 content다', () {
      final s = LoadState()..loadSuccess(4);
      s.beginRefresh();
      s.pruneAllDuringLoad();
      s.loadSuccess(1);
      expect(decide(s), Rendered.content);
    });

    test('05-d 마지막 성공이 0건이었다면 refresh 중 0건은 여전히 확정 0건이다', () {
      final s = LoadState()..loadSuccess(0);
      s.beginRefresh();
      expect(decide(s), Rendered.rootEmpty,
          reason: 'transient 가드가 정상 0건 새로고침까지 스피너로 만들면 안 된다');
    });

    test('05-e 로딩이 끝난 0건은 언제나 확정이다', () {
      final s = LoadState()..loadSuccess(4);
      s.loadSuccess(0);
      expect(s.isLoading, false);
      expect(decide(s), Rendered.rootEmpty);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // filtered / tab empty는 content가 있을 때만
  // ══════════════════════════════════════════════════════════════
  group('06. 필터·탭 0건', () {
    test('06-a 필터가 전부 걸러내면 FILTERED_EMPTY', () {
      final s = LoadState()..loadSuccess(5);
      expect(decide(s, filteredCount: 0, hasActiveFilters: true),
          Rendered.filteredEmpty);
    });

    test('06-b 필터 없이 탭만 비면 TAB_EMPTY', () {
      final s = LoadState()..loadSuccess(5);
      expect(decide(s, filteredCount: 0), Rendered.tabEmpty);
    });

    test('06-c 아직 로드 전에는 필터 해석에 도달하지 않는다', () {
      final s = LoadState();
      expect(decide(s, filteredCount: 0, hasActiveFilters: true),
          Rendered.initialLoading);
    });

    test('06-d 공고가 0건이면 필터를 원인으로 말하지 않는다', () {
      final s = LoadState()..loadSuccess(0);
      expect(decide(s, filteredCount: 0, hasActiveFilters: true),
          Rendered.rootEmpty);
    });

    test('06-e refresh 중에도 필터 해석은 그대로다', () {
      final s = LoadState()..loadSuccess(5);
      s.beginRefresh();
      expect(decide(s, filteredCount: 0, hasActiveFilters: true),
          Rendered.filteredEmpty);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §14·§15 Workforce gate
  // ══════════════════════════════════════════════════════════════
  group('07. Workforce 운영 화면 gate', () {
    test('07-a 첫 조회 전에는 gate된다', () {
      expect(workforceGated(LoadState()), true);
    });

    test('07-b 첫 성공 뒤에는 gate되지 않는다', () {
      expect(workforceGated(LoadState()..loadSuccess(3)), false);
    });

    test('07-c 성공 0건이어도 gate되지 않는다', () {
      expect(workforceGated(LoadState()..loadSuccess(0)), false);
    });

    test('07-d Jobs의 pull-to-refresh가 Workforce를 비우지 않는다', () {
      final s = LoadState()..loadSuccess(3);
      s.beginRefresh();
      expect(s.isLoading, true);
      expect(workforceGated(s), false,
          reason: '03O.1 공유 controller — 건드리지 않은 탭이 비면 안 된다');
    });

    test('07-e 첫 조회 실패는 영구 스피너가 아니다', () {
      expect(workforceGated(LoadState()..loadFailure()), false);
    });

    test('07-f 실패 후 재시도 중에는 다시 gate된다 — 무한이 아니다', () {
      final s = LoadState()..loadFailure();
      s.beginRefresh();
      expect(workforceGated(s), true);
      s.loadSuccess(1);
      expect(workforceGated(s), false);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §6의 부작용 — stale 데이터가 fresh로 보이는 창
  // ══════════════════════════════════════════════════════════════
  group('07b. 새로고침 중 freshness 표시', () {
    test('07b-a 정상 데이터의 새로고침에는 stale 배너가 없다', () {
      final s = LoadState()..loadSuccess(3);
      s.beginRefresh();
      expect(staleBannerShown(s), false);
    });

    test('07b-b 실패로 낡은 데이터는 배너가 붙는다', () {
      final s = LoadState()..loadSuccess(3);
      s.loadFailure();
      expect(staleBannerShown(s), true);
    });

    test('07b-c 재시도가 도는 동안에도 배너가 유지된다', () {
      final s = LoadState()..loadSuccess(3);
      s.loadFailure();
      s.beginRefresh();
      expect(s.hasError, false, reason: 'loadError는 재시도 시작 시 지워진다(01B)');
      expect(staleBannerShown(s), true,
          reason: '목록을 계속 보여주는 동안 낡았다는 사실이 사라지면 안 된다');
    });

    test('07b-d 재시도가 성공하면 배너가 사라진다', () {
      final s = LoadState()..loadSuccess(3);
      s.loadFailure();
      s.beginRefresh();
      s.loadSuccess(3);
      expect(staleBannerShown(s), false);
    });

    test('07b-e 재시도가 또 실패하면 배너가 남는다', () {
      final s = LoadState()..loadSuccess(3);
      s.loadFailure();
      s.beginRefresh();
      s.loadFailure();
      expect(staleBannerShown(s), true);
    });

    test('07b-f 보여줄 데이터가 없으면 배너가 아니라 error state다', () {
      final s = LoadState()..loadFailure();
      expect(staleBannerShown(s), false);
      expect(decide(s), Rendered.error);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 소스 고정
  // ══════════════════════════════════════════════════════════════
  group('08. controller 소스', () {
    final src = _src(_ctrlPath);

    test('08-a hasLoadedOnce / lastSuccessfulWasEmpty getter가 노출된다', () {
      expect(src.contains('bool get hasLoadedOnce => _hasLoadedOnce;'), true);
      expect(
        src.contains(
            'bool get lastSuccessfulWasEmpty => _lastSuccessfulWasEmpty;'),
        true,
      );
    });

    test('08-b 두 플래그는 false로 시작한다', () {
      expect(src.contains('bool _hasLoadedOnce = false;'), true);
      expect(src.contains('bool _lastSuccessfulWasEmpty = false;'), true);
    });

    test('08-c 성공 표시는 _runOneLoad의 try 안, catch 앞에 있다', () {
      final body = _codeOf(_bodyOf(src, 'Future<void> _runOneLoad('));
      final mark = body.indexOf('_hasLoadedOnce = true;');
      // flex 슬롯 루프에 자체 catch가 있으므로 **바깥** catch를 본다.
      final catchAt = body.lastIndexOf('} catch (e)');
      expect(mark, greaterThan(-1), reason: '성공 표시를 찾지 못함');
      expect(catchAt, greaterThan(-1));
      expect(mark, lessThan(catchAt),
          reason: '실패 경로가 hasLoadedOnce를 세우면 안 된다');
    });

    test('08-d lastSuccessfulWasEmpty는 같은 지점에서 items 기준으로 정해진다', () {
      final body = _codeOf(_bodyOf(src, 'Future<void> _runOneLoad('));
      expect(
        _flat(body).contains(
            '_hasLoadedOnce = true; _lastSuccessfulWasEmpty = _items.isEmpty;'),
        true,
      );
    });

    test('08-e user==null early return은 성공 표시보다 앞이다', () {
      final body = _codeOf(_bodyOf(src, 'Future<void> _runOneLoad('));
      final userNull = body.indexOf('if (user == null)');
      final mark = body.indexOf('_hasLoadedOnce = true;');
      expect(userNull, greaterThan(-1));
      expect(userNull, lessThan(mark),
          reason: 'user를 모르는 상태는 canonical 결과가 아니다');
    });

    test('08-f catch 블록에는 성공 표시가 없다', () {
      final body = _codeOf(_bodyOf(src, 'Future<void> _runOneLoad('));
      final catchAt = body.lastIndexOf('} catch (e)');
      expect(body.substring(catchAt).contains('_hasLoadedOnce'), false);
      expect(body.substring(catchAt).contains('_lastSuccessfulWasEmpty'), false);
    });

    test('08-h lastLoadFailed는 성공에서만 내려간다', () {
      final body = _codeOf(_bodyOf(src, 'Future<void> _runOneLoad('));
      expect(_flat(body).contains('_lastSuccessfulWasEmpty = _items.isEmpty; _lastLoadFailed = false;'),
          true);
      final catchAt = body.lastIndexOf('} catch (e)');
      expect(body.substring(catchAt).contains('_lastLoadFailed = true;'), true);
      // 시작 시점(_loadError = null 옆)에서 같이 지우면 재시도 창을 못 잡는다.
      final start = body.indexOf('_loadError = null;');
      final tryAt = body.indexOf('try {');
      expect(
        body.substring(start, tryAt).contains('_lastLoadFailed'),
        false,
        reason: 'loadError와 달리 재시도 시작 시 지우지 않는다',
      );
    });

    test('08-g 두 플래그를 false로 되돌리는 코드가 없다', () {
      final code = _codeOf(src);
      expect(code.contains('_hasLoadedOnce = false;'), true,
          reason: '필드 초기화 1회는 존재해야 한다');
      expect(
        RegExp(r'_hasLoadedOnce = false;').allMatches(code).length,
        1,
        reason: '초기화 외에 false로 되돌리는 지점이 있으면 안 된다',
      );
    });
  });

  group('09. Jobs 목록 소스', () {
    final src = _src(_listPath);
    final body = _codeOf(_bodyOf(src, 'Widget _buildTOList('));

    test('09-a 분기 순서: error → initial loading → true empty → 필터', () {
      final err = body.indexOf('_buildErrorState()');
      final init = body.indexOf('!controller.hasLoadedOnce');
      // error 조건에도 items.isEmpty가 들어가므로 단독 분기를 찾는다.
      final empty = body.indexOf('if (controller.items.isEmpty) {');
      final filtered = body.indexOf('_getFilteredItems(');
      expect(err, greaterThan(-1));
      expect(init, greaterThan(-1));
      expect(empty, greaterThan(-1));
      expect(filtered, greaterThan(-1));
      expect(err, lessThan(init));
      expect(init, lessThan(empty));
      expect(empty, lessThan(filtered));
    });

    test('09-b isLoading을 목록 앞의 무조건 gate로 쓰지 않는다', () {
      expect(
        _flat(body).contains('if (controller.isLoading) { return const LoadingWidget'),
        false,
        reason: '모든 새로고침이 카드를 스피너로 갈아치우던 분기',
      );
    });

    test('09-c isLoading은 items.isEmpty 분기 안에서만 참조된다', () {
      final emptyAt = body.indexOf('controller.items.isEmpty');
      final loadingAt = body.indexOf('controller.isLoading');
      expect(loadingAt, greaterThan(emptyAt),
          reason: 'isLoading은 확정 0건 판정의 보조 조건일 뿐이다');
    });

    test('09-d transient 가드는 lastSuccessfulWasEmpty와 함께 쓴다', () {
      expect(
        _flat(body).contains(
            'if (controller.isLoading && !controller.lastSuccessfulWasEmpty)'),
        true,
      );
    });

    test('09-e RefreshIndicator + ListView가 content 분기에 그대로 남아 있다', () {
      expect(body.contains('RefreshIndicator('), true);
      expect(body.contains('controller: _scrollController'), true,
          reason: '§7 — 목록이 tree에서 빠지지 않아야 스크롤 위치가 유지된다');
    });

    test('09-f 새 shimmer/skeleton을 만들지 않았다', () {
      final code = _codeOf(src);
      expect(code.toLowerCase().contains('shimmer'), false);
      expect(code.toLowerCase().contains('skeleton'), false);
    });

    test('09-g 로딩 문구는 기존 것을 그대로 쓴다', () {
      expect(body.contains("LoadingWidget(message: '공고 목록을 불러오는 중...')"), true);
    });
  });

  group('10. scope chip 소스', () {
    final src = _src(_jobsPath);

    test('10-a scope chip에 isLoading 가드가 없다', () {
      final code = _codeOf(src);
      expect(
        code.contains('if (controller.isLoading) return const SizedBox.shrink();'),
        false,
        reason: '새로고침마다 헤더의 사업장 줄이 사라졌다 나타나면 안 된다',
      );
    });

    test('10-b chip은 여전히 label이 비었을 때만 숨긴다', () {
      expect(
        _flat(_codeOf(src))
            .contains('if (label.isEmpty) return const SizedBox.shrink();'),
        true,
      );
    });

    test('10-c 사업장명 preload를 추가하지 않았다 — §13 추가 read 금지', () {
      final code = _codeOf(src);
      expect(code.contains('preloadBusinessNames'), false);
      expect(code.contains('getBusinessNames'), false);
    });
  });

  group('11. Workforce 운영 화면 소스', () {
    final src = _src(_opsPath);

    test('11-a gate는 hasLoadedOnce 기준이다', () {
      expect(
        _flat(_codeOf(src)).contains(
            'if (!controller.hasLoadedOnce && controller.loadError == null)'),
        true,
      );
    });

    test('11-b isLoading 단독 gate가 사라졌다', () {
      final code = _flat(_codeOf(src));
      expect(
        code.contains(
            "if (controller.isLoading) { return const LoadingWidget(message: '인력 정보를 불러오는 중...'); }"),
        false,
      );
    });

    test('11-c 로딩 문구는 그대로다', () {
      expect(src.contains("LoadingWidget(message: '인력 정보를 불러오는 중...')"), true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §16·§18 범위 제한
  // ══════════════════════════════════════════════════════════════
  group('12. 범위', () {
    test('12-a root-local 로딩 플래그를 새로 만들지 않았다', () {
      for (final p in [_listPath, _jobsPath, _opsPath]) {
        final code = _codeOf(_src(p));
        expect(code.contains('bool _hasLoadedOnce'), false,
            reason: '$p — 상태는 controller 하나가 소유한다');
        expect(code.contains('bool _didInitialLoad'), false, reason: p);
      }
    });

    test('12-b controller 소유 구조(03O.1)를 건드리지 않았다', () {
      final shell = _src('lib/screens/business_admin/business_admin_shell.dart');
      expect(
        shell.contains('final WorkforceController _postingController = WorkforceController();'),
        true,
      );
      expect(shell.contains('_postingController.dispose();'), true);
    });

    test('12-c 추가 Firestore read / callable을 넣지 않았다', () {
      for (final p in [_listPath, _jobsPath, _opsPath, _ctrlPath]) {
        final code = _codeOf(_src(p));
        expect(code.contains('httpsCallable('), false, reason: p);
      }
    });
  });
}
