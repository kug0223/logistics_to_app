// [POSTING-V2-03F.1] 목록 최신화 실패 — STALE != FRESH
//
// 03F READ에서 확인된 것:
//   · load()는 실패해도 _items를 보존한다(01B). 여기까지는 의도된 계약이다.
//   · 소비자 계약도 01B 주석에 이미 적혀 있었다:
//       loadError != null && items.isNotEmpty → 마지막 성공 데이터 + 실패 알림
//     그런데 그 "실패 알림"을 렌더하는 위젯이 없었다.
//   · 실패 안내는 _reload를 거치는 두 trigger(당겨서 새로고침 · mutation 후
//     reload)의 토스트뿐이었고, 앱 복귀 · dataRevision · FCM 세 경로는
//     controller를 직접 불러 아무 신호도 남기지 않았다.
//   · 필터/탭 결과가 0이면 '조건에 맞는 공고가 없습니다'만 보여
//     최신화 실패 사실이 사라졌다(ERROR == ZERO 계열).
//
// 정책: MODEL B — 기존 성공 데이터 유지 + persistent freshness warning.
//   STALE != EMPTY / STALE != FRESH / ERROR != ZERO 를 모두 지킨다.
//
// 위젯 렌더 테스트는 Firebase 초기화를 요구하므로, 렌더 조건과 배선은
// 소스로, 상태 판정은 replica로 검증한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _viewPath =
    'lib/screens/business_admin/workforce_management/workforce_list_view.dart';
const _ctrlPath = 'lib/controllers/workforce_controller.dart';
const _jobsRootPath = 'lib/screens/business_admin/jobs_root_screen.dart';

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

// ── 화면 state replica ──────────────────────────────────────────
enum Surface { loading, fullError, rootEmpty, filteredEmpty, tabEmpty, list }

/// 본문 분기 replica — _buildTOList의 순서를 그대로 따른다.
Surface bodyOf({
  required bool isLoading,
  required bool hasError,
  required int itemCount,
  required int filteredCount,
  required bool hasActiveFilters,
}) {
  if (isLoading) return Surface.loading;
  if (hasError && itemCount == 0) return Surface.fullError;
  if (itemCount == 0) return Surface.rootEmpty;
  if (filteredCount == 0) {
    return hasActiveFilters ? Surface.filteredEmpty : Surface.tabEmpty;
  }
  return Surface.list;
}

/// 배너 조건 replica — 본문과 독립된 freshness 차원.
bool bannerOf({required bool hasError, required int itemCount}) =>
    hasError && itemCount > 0;

void main() {
  // ── §1 새 state 없음 ───────────────────────────────────────────
  group('STALE-01 기존 두 값만으로 판정한다', () {
    test('01-a controller에 새 필드를 넣지 않았다 (§1)', () {
      final code = _codeOf(_src(_ctrlPath));
      expect(code.contains('_lastSuccessfulLoadAt'), false);
      expect(code.contains('hasStaleLoadError'), false);
      expect(code.contains('bool _isRefreshing'), false,
          reason: 'refreshing state 신규 도입 금지 (§11)');
      // 판정 재료는 기존 두 getter뿐이다
      expect(code.contains('Object? get loadError => _loadError;'), true);
      expect(code.contains('List<TOGroupItem> get items => _items;'), true);
    });

    test('01-b 배너가 그 두 값만 읽는다', () {
      final body = _flat(_codeOf(_bodyOf(_src(_viewPath), 'Widget _buildStaleBanner(')));
      expect(
          body.contains('final isStale = controller.loadError != null '
              '&& controller.items.isNotEmpty;'),
          true);
      expect(body.contains('if (!isStale) return const SizedBox.shrink();'), true);
    });

    test('01-c 01B의 소비자 계약이 그대로 살아 있다', () {
      final code = _src(_ctrlPath);
      expect(
          code.contains('loadError != null && items.isNotEmpty→ 마지막 성공 데이터 + 실패 알림'),
          true,
          reason: '이번 수정이 이행하는 계약이다');
    });
  });

  // ── §2, §15, §16 배너 자체 ─────────────────────────────────────
  group('STALE-02 persistent warning', () {
    test('02-a 문구가 운영 상태를 말한다 (§2)', () {
      final body = _flat(_codeOf(_bodyOf(_src(_viewPath), 'Widget _buildStaleBanner(')));
      expect(body.contains("'최신 정보를 불러오지 못했습니다. 다시 시도해 주세요.'"), true);
    });

    test('02-b 내부 예외를 노출하지 않는다 (§2)', () {
      final body = _codeOf(_bodyOf(_src(_viewPath), 'Widget _buildStaleBanner('));
      expect(body.contains('loadError.toString()'), false);
      expect(body.contains('\$e'), false);
      expect(body.contains('controller.loadError}'), false);
    });

    test('02-c 대형 error card가 아니다 (§15)', () {
      final body = _flat(_codeOf(_bodyOf(_src(_viewPath), 'Widget _buildStaleBanner(')));
      expect(body.contains('AppEmptyState('), false,
          reason: '오류 화면이 아니라 운영 상태 표시다');
      expect(body.contains('Row('), true, reason: '낮은 높이의 inline 배너');
      expect(body.contains('color: AppColors.warningBg,'), true,
          reason: '기존 토큰 재사용');
      // CTA는 하나뿐
      expect('TextButton('.allMatches(body).length, 1);
      expect(body.contains("child: Text('다시 시도',"), true);
    });

    test('02-d 목록보다 위에 있다 (§4, §16)', () {
      final body = _codeOf(_bodyOf(_src(_viewPath), 'Widget build(BuildContext context)'));
      final tabIdx = body.indexOf('_buildTabBar(controller),');
      final bannerIdx = body.indexOf('_buildStaleBanner(controller),');
      final listIdx = body.indexOf('Expanded(child: _buildTOList(controller)),');
      expect(bannerIdx, greaterThan(tabIdx));
      expect(listIdx, greaterThan(bannerIdx),
          reason: 'stale 카드의 CTA를 누르기 전에 freshness를 먼저 봐야 한다');
    });

    test('02-e 본문 renderer 안이 아니다 — 별도 freshness layer (§4)', () {
      final list = _codeOf(_bodyOf(_src(_viewPath), 'Widget _buildTOList('));
      expect(list.contains('_buildStaleBanner'), false,
          reason: '본문 분기 안에 있으면 empty/list 중 하나에서만 보인다');
    });
  });

  // ── §5, §6, §7, §19 empty 통합 ─────────────────────────────────
  group('STALE-03 empty taxonomy와 공존한다', () {
    test('03-a 목록 + 실패 → 목록 유지 + 배너', () {
      expect(
          bodyOf(
              isLoading: false,
              hasError: true,
              itemCount: 5,
              filteredCount: 5,
              hasActiveFilters: false),
          Surface.list);
      expect(bannerOf(hasError: true, itemCount: 5), true);
    });

    test('03-b 필터 0건 + 실패 → FILTERED_EMPTY + 배너 (§5)', () {
      expect(
          bodyOf(
              isLoading: false,
              hasError: true,
              itemCount: 5,
              filteredCount: 0,
              hasActiveFilters: true),
          Surface.filteredEmpty,
          reason: 'cached 기준 필터 결과 0은 그 자체로 참이다');
      expect(bannerOf(hasError: true, itemCount: 5), true,
          reason: '실패가 필터 문구 뒤로 숨으면 ERROR == ZERO다');
    });

    test('03-c 탭 0건 + 실패 → TAB_EMPTY + 배너 (§6)', () {
      expect(
          bodyOf(
              isLoading: false,
              hasError: true,
              itemCount: 5,
              filteredCount: 0,
              hasActiveFilters: false),
          Surface.tabEmpty);
      expect(bannerOf(hasError: true, itemCount: 5), true);
    });

    test('03-d items 0건 + 실패 → full error, 배너 없음 (§7)', () {
      expect(
          bodyOf(
              isLoading: false,
              hasError: true,
              itemCount: 0,
              filteredCount: 0,
              hasActiveFilters: false),
          Surface.fullError,
          reason: 'ROOT_EMPTY가 아니다');
      expect(bannerOf(hasError: true, itemCount: 0), false,
          reason: '본문이 이미 실패를 말하고 있다 — 두 번 말하지 않는다');
    });

    test('03-e 성공 + 0건은 여전히 ROOT_EMPTY다 (§19)', () {
      expect(
          bodyOf(
              isLoading: false,
              hasError: false,
              itemCount: 0,
              filteredCount: 0,
              hasActiveFilters: false),
          Surface.rootEmpty);
      expect(bannerOf(hasError: false, itemCount: 0), false);
    });

    test('03-f 정상 성공에는 배너가 없다', () {
      expect(bannerOf(hasError: false, itemCount: 5), false);
    });

    test('03-g empty 문구를 바꾸지 않았다 (§5, §19)', () {
      final body = _codeOf(_bodyOf(_src(_viewPath), 'Widget _buildEmptyState('));
      for (final copy in [
        "'등록된 공고가 없습니다'",
        "'조건에 맞는 공고가 없습니다'",
        "'진행중인 공고가 없습니다'",
        "'마감된 공고가 없습니다'",
      ]) {
        expect(body.contains(copy), true, reason: '$copy 가 바뀌었다');
      }
      expect(body.contains('loadError'), false,
          reason: 'empty renderer가 freshness를 알 필요가 없다 — 차원이 다르다');
    });

    test('03-h 본문 분기 순서가 그대로다 (§7, §19)', () {
      final body = _codeOf(_bodyOf(_src(_viewPath), 'Widget _buildTOList('));
      final loadingIdx = body.indexOf('if (controller.isLoading)');
      final errorIdx =
          body.indexOf('if (controller.loadError != null && controller.items.isEmpty)');
      final rootIdx = body.indexOf('if (controller.items.isEmpty)');
      final filterIdx = body.indexOf('if (allFilteredItems.isEmpty)');
      expect(errorIdx, greaterThan(loadingIdx));
      expect(rootIdx, greaterThan(errorIdx),
          reason: 'ROOT_EMPTY가 error보다 앞서면 장애가 빈 상태로 보인다');
      expect(filterIdx, greaterThan(rootIdx));
    });
  });

  // ── §3, §18 retry ──────────────────────────────────────────────
  group('STALE-04 retry가 canonical 경로를 쓴다', () {
    test('04-a 배너 retry = _reload (§3)', () {
      final body = _flat(_codeOf(_bodyOf(_src(_viewPath), 'Widget _buildStaleBanner(')));
      expect(body.contains('onPressed: _reload,'), true);
      expect(body.contains('controller.reload('), false,
          reason: 'controller 직접 호출은 SubAdmin access → data 순서를 우회한다');
      expect(body.contains('controller.load('), false);
    });

    test('04-b _reload가 03B 순서를 유지한다 (§3)', () {
      final body = _codeOf(_bodyOf(_src(_viewPath), 'Future<void> _reload('));
      final accessIdx = body.indexOf('await up.refreshSubAdminAccessState();');
      final dataIdx = body.indexOf('await controller.reload(context);');
      expect(accessIdx, greaterThan(-1), reason: 'access refresh가 사라졌다');
      expect(dataIdx, greaterThan(accessIdx),
          reason: 'stale scope로 서버를 부르면 멀쩡한 사업장 공고까지 못 본다');
      expect(body.contains('if (up.isSubAdmin) {'), true);
    });

    test('04-c full error state도 같은 _reload를 쓴다', () {
      final body = _flat(_codeOf(_bodyOf(_src(_viewPath), 'Widget _buildErrorState(')));
      expect(body.contains('onPressed: _reload,'), true,
          reason: '두 실패 표면의 재시도 의미가 달라지면 안 된다');
    });

    test('04-d 새 reload path를 만들지 않았다 (§3)', () {
      final code = _codeOf(_src(_viewPath));
      expect('Future<void> _reload('.allMatches(code).length, 1);
      expect(code.contains('_retryStale'), false);
      expect(code.contains('_refreshFromBanner'), false);
    });
  });

  // ── §8, §18 trigger 수렴 ───────────────────────────────────────
  group('STALE-05 모든 trigger가 같은 표면으로 수렴한다', () {
    test('05-a 토스트 없는 세 경로도 배너에 도달한다 (§8)', () {
      // resume · dataRevision · FCM은 controller를 직접 부른다 —
      // 배너는 controller state만 보므로 이 경로들도 자동 포함된다.
      final jobs = _codeOf(_src(_jobsRootPath));
      expect(jobs.contains('_controller.load(context);'), true,
          reason: 'dataRevision 경로');
      expect(jobs.contains('_controller.reload(context);'), true,
          reason: 'resume / FCM 경로');
      // 그 경로들에 개별 안내를 붙이지 않았다
      expect(jobs.contains('ToastHelper.showError'), false,
          reason: 'trigger마다 snackbar를 추가하지 않는다 (§8)');
    });

    test('05-b 실패는 모두 같은 _loadError 하나에 모인다', () {
      final body = _codeOf(_bodyOf(_src(_ctrlPath), 'Future<void> load('));
      expect(body.contains('_loadError = e;'), true);
      expect(body.contains('_items = [];\n      return;'), false,
          reason: '실패가 목록을 지우면 배너 조건(items.isNotEmpty)이 깨진다');
      // reload()는 load()로 위임 — 두 경로가 갈라지지 않는다
      final reload = _flat(_codeOf(_bodyOf(_src(_ctrlPath), 'Future<void> reload(')));
      expect(reload.contains('return load(context);'), true);
    });

    test('05-c 기존 토스트는 유지된다 — 역할이 다르다 (§9)', () {
      final body = _flat(_codeOf(_bodyOf(_src(_viewPath), 'Future<void> _reload(')));
      expect(
          body.contains("if (controller.loadError != null && "
              "controller.items.isNotEmpty) { "
              "ToastHelper.showError('공고 목록을 새로고침하지 못했습니다'); }"),
          true,
          reason: '토스트 = 즉시 feedback, 배너 = 지속되는 truth');
    });

    test('05-d 같은 실패에 토스트가 두 번 뜨지 않는다 (§9)', () {
      final body = _codeOf(_bodyOf(_src(_viewPath), 'Future<void> _reload('));
      expect("ToastHelper.showError('공고 목록을 새로고침하지 못했습니다')".allMatches(body).length,
          1);
    });
  });

  // ── §10 lifetime ───────────────────────────────────────────────
  group('STALE-06 실패 truth의 수명', () {
    test('06-a 다음 성공 load에서 사라진다', () {
      final body = _codeOf(_bodyOf(_src(_ctrlPath), 'Future<void> load('));
      expect(body.contains('_loadError = null;'), true,
          reason: '재시도 시작 시 초기화 → 성공하면 그대로 null');
      // 성공 경로에서 다시 채우지 않는다
      expect('_loadError = e;'.allMatches(body).length, 1);
    });

    test('06-b filter 변경은 reload를 일으키지 않는다 → 배너 유지 (§10)', () {
      for (final sig in [
        'void setTOTypeFilter(',
        'void setPublishStatusFilter(',
      ]) {
        final body = _flat(_codeOf(_bodyOf(_src(_ctrlPath), sig)));
        expect(body.contains('notifyListeners();'), true, reason: sig);
        expect(body.contains('load('), false,
            reason: '$sig — 필터가 loadError를 지우면 실패가 은폐된다');
      }
      final clear = _flat(_codeOf(_bodyOf(_src(_ctrlPath), 'void clearFilters(')));
      expect(clear.contains('load('), false);
    });

    test('06-c 필터 초기화도 재조회가 아니다', () {
      final body = _flat(_codeOf(_bodyOf(_src(_viewPath), 'void _clearFilters(')));
      expect(body.contains('clearFilters();'), true);
      expect(body.contains('_reload'), false,
          reason: '기존 목록을 다시 거를 뿐이다 (02E.1)');
    });

    test('06-d 탭 변경은 setState뿐이다 → 배너 유지 (§10)', () {
      final body = _flat(_codeOf(_bodyOf(_src(_viewPath), 'Widget _buildTab(')));
      expect(body.contains('if (_selectedTab != tab) { setState(() {'), true);
      expect(body.contains('_reload'), false);
      expect(body.contains('controller.load('), false,
          reason: 'loadError 참조와 구분해 재조회 호출만 본다');
      // 탭은 loadError를 읽기만 한다 — count 신뢰도 판정(01B)
      expect(body.contains('controller.loadError == null'), true);
    });
  });

  // ── §12 mutation success + refresh failure ─────────────────────
  group('STALE-07 mutation 성공과 최신화 실패를 구분한다', () {
    test('07-a 성공 toast는 그대로 유지된다 (§12)', () {
      final dialogs = _codeOf(
          _src('lib/screens/business_admin/dialogs/to_list_dialogs.dart'));
      expect(dialogs.contains("ToastHelper.showSuccess('공고가 종료되었습니다.');"), true);
      expect(dialogs.contains("ToastHelper.showSuccess('공고가 재오픈되었습니다.');"), true);
    });

    test('07-b 성공 후 reload 실패를 작업 실패로 말하지 않는다 (§12)', () {
      final body = _flat(_codeOf(_bodyOf(_src(_viewPath), 'Future<void> _reload(')));
      // reload 실패 문구는 '목록 새로고침' 실패지 action 실패가 아니다
      expect(body.contains("'공고 목록을 새로고침하지 못했습니다'"), true);
      expect(body.contains("'작업에 실패했습니다'"), false);
      expect(body.contains("'처리에 실패했습니다'"), false);
    });

    test('07-c local optimistic 패치를 넣지 않았다 (§22)', () {
      final body = _codeOf(_bodyOf(_src(_viewPath), 'Future<void> _reload('));
      expect(body.contains('_items'), false);
      expect(body.contains('.remove('), false);
    });
  });

  // ── §13 stale 상태의 action ────────────────────────────────────
  group('STALE-08 stale이어도 action을 막지 않는다', () {
    test('08-a 카드 렌더에 stale 조건이 끼어들지 않는다 (§13)', () {
      final body = _codeOf(_bodyOf(_src(_viewPath), 'Widget _buildTOList('));
      final cardIdx = body.indexOf('child: TOGroupCard(');
      expect(cardIdx, greaterThan(-1));
      final cardBlock = body.substring(cardIdx);
      expect(cardBlock.contains('loadError'), false,
          reason: 'stale → 전체 disable은 과잉 방어다. 서버 guard가 canonical이다');
      expect(cardBlock.contains('readOnly'), false);
      expect(cardBlock.contains('IgnorePointer'), false);
    });

    test('08-b 배너가 목록을 덮지 않는다', () {
      final body = _codeOf(_bodyOf(_src(_viewPath), 'Widget build(BuildContext context)'));
      expect(body.contains('Expanded(child: _buildTOList(controller)),'), true,
          reason: '배너는 Column의 한 줄일 뿐 본문을 대체하지 않는다');
      expect(body.contains('Stack('), false);
    });
  });

  // ── §14 group detail error와 독립 ──────────────────────────────
  group('STALE-09 카드별 상세 실패와 별개다', () {
    test('09-a 두 실패 표시가 서로를 가리지 않는다 (§14)', () {
      final body = _codeOf(_bodyOf(_src(_viewPath), 'Widget _buildTOList('));
      expect(body.contains('controller.hasGroupDetailError(groupItem.id)'), true,
          reason: '카드별 슬롯 실패 표시가 그대로 살아 있다');
      expect(body.contains('onRetryGroupDetail:'), true);
      // 배너 조건에 groupDetailError가 섞여 있지 않다
      final banner =
          _codeOf(_bodyOf(_src(_viewPath), 'Widget _buildStaleBanner('));
      expect(banner.contains('hasGroupDetailError'), false,
          reason: '목록 freshness와 개별 공고 상세는 다른 실패다');
    });
  });

  // ── §20, §21 계약 무회귀 ───────────────────────────────────────
  group('STALE-10 02B / 성능 계약 무회귀', () {
    test('10-a 배너와 retry가 dataRevision을 올리지 않는다 (§20)', () {
      final banner =
          _codeOf(_bodyOf(_src(_viewPath), 'Widget _buildStaleBanner('));
      expect(banner.contains('notifyDataChanged'), false);
      final reload = _codeOf(_bodyOf(_src(_viewPath), 'Future<void> _reload('));
      expect(reload.contains('notifyDataChanged'), false,
          reason: 'dataRevision = mutation-only');
    });

    test('10-b 새 Firestore read가 없다 (§21)', () {
      final banner =
          _codeOf(_bodyOf(_src(_viewPath), 'Widget _buildStaleBanner('));
      for (final forbidden in [
        '_firestoreService',
        'FirebaseFirestore',
        'await ',
        '.get(',
      ]) {
        expect(banner.contains(forbidden), false, reason: forbidden);
      }
    });

    test('10-c 자동 polling / retry가 없다 (§14, §21)', () {
      final code = _codeOf(_src(_viewPath));
      expect(code.contains('Timer.periodic'), false);
      expect(code.contains('Future.delayed'), false);
      final banner =
          _codeOf(_bodyOf(_src(_viewPath), 'Widget _buildStaleBanner('));
      expect(banner.contains('addPostFrameCallback'), false,
          reason: '배너가 스스로 재시도하지 않는다 — 사용자가 누를 때만');
    });

    test('10-d refreshing state를 새로 만들지 않았다 (§11, §22)', () {
      final code = _codeOf(_src(_viewPath));
      expect(code.contains('_isRefreshing'), false);
      // isLoading 중에는 본문이 LoadingWidget이라 old data를 fresh라고
      // 주장하는 순간이 없다 — §11의 material gap 없음
      final list = _codeOf(_bodyOf(_src(_viewPath), 'Widget _buildTOList('));
      expect(list.contains("if (controller.isLoading) {"), true);
      expect(list.contains("return const LoadingWidget(message: '공고 목록을 불러오는 중...');"),
          true);
    });
  });
}
