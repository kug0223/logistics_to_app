// [POSTING-V2-02E.1] 공고 탭 성공 empty의 의미 분리
//
// 02E READ에서 확인된 문제:
//   성공 조회 후의 0건 네 가지가 전부 한 문구로 수렴했다.
//     '조건에 맞는 공고가 없습니다 / 필터를 변경하거나 새로운 공고를 등록하세요'
//   · 필터가 없는데도 필터를 의심하게 만든다
//   · 마감됨 탭에서 '새 공고를 등록하라'는 실행해도 그 탭이 채워지지 않는 안내다
//   · 필터가 걸려 0건일 때 등록을 권하면 필터만 풀면 보이는 공고를 놓친다
//
// 분리 후 성공 empty는 셋이다 — ROOT / FILTERED / TAB.
// ERROR(01B)는 이 집합 밖이며 계약이 그대로다.
//
// 분기 판정은 순수 함수로 재현해 검증하고(화면이 Firebase 서비스를 필드로
// 즉시 보유해 widget 테스트가 불가능하다), 문구·action 배선은 소스로 고정한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _listPath =
    'lib/screens/business_admin/workforce_management/workforce_list_view.dart';
const _ctrlPath = 'lib/controllers/workforce_controller.dart';
const _svcPath = 'lib/services/firestore_service.dart';

String _src(String p) {
  final f = File(p);
  expect(f.existsSync(), true, reason: '$p 를 찾지 못함');
  return f.readAsStringSync();
}

/// `//` 주석 줄 제거 — 설명 주석이 코드로 오탐되는 것을 막는다.
String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

/// 공백 1칸 평탄화 — 들여쓰기/줄바꿈에 의존하지 않는 비교용.
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

// ── body 분기 계약 재현 ───────────────────────────────────────────
//
// _buildTOList의 판정 순서를 그대로 옮긴다. 순서가 계약의 핵심이다 —
// items.isEmpty가 필터보다 먼저다.

enum _Body { loading, error, rootEmpty, filteredEmpty, tabEmpty, list }

_Body _resolveBody({
  required bool isLoading,
  required bool hasLoadError,
  required int itemCount,
  required int filteredCount,
  required bool hasActiveFilters,
}) {
  if (isLoading) return _Body.loading;
  if (hasLoadError && itemCount == 0) return _Body.error;
  if (itemCount == 0) return _Body.rootEmpty;
  if (filteredCount == 0) {
    return hasActiveFilters ? _Body.filteredEmpty : _Body.tabEmpty;
  }
  return _Body.list;
}

// ── 탭 분류 계약 재현 ─────────────────────────────────────────────
//
// TOGroupItem.isClosed 기준. FULL은 마감됨, DRAFT/SCHEDULED는 진행중.

const _active = 'ACTIVE';
const _closed = 'CLOSED';

typedef _Posting = ({String status, bool isFull});

_Posting _to(String status, {bool isFull = false}) =>
    (status: status, isFull: isFull);

bool _isClosed(_Posting p) =>
    p.isFull || p.status == 'CLOSED' || p.status == 'EXPIRED';

int _tabCount(List<_Posting> items, String tab) => items
    .where((p) => tab == _active ? !_isClosed(p) : _isClosed(p))
    .length;

void main() {
  // ── §26, §13 ROOT_EMPTY ─────────────────────────────────────────
  group('EMPTY-01 공고 자체가 0개', () {
    test('01-a items 0 · 필터 없음 → ROOT_EMPTY', () {
      expect(
          _resolveBody(
            isLoading: false,
            hasLoadError: false,
            itemCount: 0,
            filteredCount: 0,
            hasActiveFilters: false,
          ),
          _Body.rootEmpty);
    });

    test('01-b 문구가 전체 0을 말한다', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_listPath), 'Widget _buildEmptyState(')));
      expect(
          body.contains("_PostingEmptyKind.root => ( '등록된 공고가 없습니다', "
              "'상단 + 버튼에서 새 공고를 등록할 수 있습니다', ),"),
          true);
    });
  });

  group('EMPTY-02 공고 0 + 필터 active여도 ROOT_EMPTY', () {
    test('02-a 필터가 원인이라고 말하지 않는다', () {
      expect(
          _resolveBody(
            isLoading: false,
            hasLoadError: false,
            itemCount: 0,
            filteredCount: 0,
            hasActiveFilters: true, // 필터가 켜져 있어도
          ),
          _Body.rootEmpty,
          reason: '공고가 0개면 필터는 empty의 원인이 아니다');
    });

    test('02-b 소스에서 items.isEmpty 검사가 필터 분기보다 앞선다', () {
      final body = _codeOf(_bodyOf(_src(_listPath), 'Widget _buildTOList('));
      final rootIdx = body.indexOf('if (controller.items.isEmpty) {');
      final filterIdx = body.indexOf('controller.hasActiveFilters');
      expect(rootIdx, greaterThan(-1));
      expect(filterIdx, greaterThan(rootIdx),
          reason: '필터 분기가 먼저면 공고 0개를 필터 탓으로 말하게 된다');
    });

    test('02-c ROOT_EMPTY에는 필터 초기화 action이 없다', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_listPath), 'Widget _buildEmptyState(')));
      expect(
          body.contains('action: kind == _PostingEmptyKind.filtered ? '
              'TextButton.icon('),
          true,
          reason: 'action이 filtered 상태에만 붙어 있어야 한다');
      expect(body.contains(': null, );'), true);
    });
  });

  // ── §28 FILTERED_EMPTY ──────────────────────────────────────────
  group('EMPTY-03 필터 때문에 0건', () {
    test('03-a items 5 · filtered 0 · 필터 active → FILTERED_EMPTY', () {
      expect(
          _resolveBody(
            isLoading: false,
            hasLoadError: false,
            itemCount: 5,
            filteredCount: 0,
            hasActiveFilters: true,
          ),
          _Body.filteredEmpty);
    });

    test('03-b 문구와 primary action', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_listPath), 'Widget _buildEmptyState(')));
      expect(
          body.contains("_PostingEmptyKind.filtered => ( '조건에 맞는 공고가 없습니다', "
              "'필터를 초기화하거나 조건을 변경해 보세요', ),"),
          true);
      expect(body.contains("label: const Text('필터 초기화'),"), true);
      expect(body.contains('onPressed: _clearFilters,'), true);
    });

    test('03-c §12 필터 결과 0에 공고 등록을 권하지 않는다', () {
      final body = _codeOf(_bodyOf(_src(_listPath), 'Widget _buildEmptyState('));
      expect(body.contains('새로운 공고를 등록하세요'), false);
      expect(body.contains('AdminCreateTOScreen'), false);
      expect(body.contains('CreateTOScreen'), false);
    });

    test('03-d §33 body action은 최대 1개다', () {
      final body = _codeOf(_bodyOf(_src(_listPath), 'Widget _buildEmptyState('));
      expect('TextButton'.allMatches(body).length, 1);
      expect(body.contains('ElevatedButton'), false);
    });
  });

  // ── §29, §6, §8 필터 초기화 ─────────────────────────────────────
  group('EMPTY-04 필터 초기화', () {
    test('04-a 네 필터를 모두 null로 되돌린다', () {
      final body = _flat(_codeOf(_bodyOf(_src(_ctrlPath), 'void clearFilters(')));
      for (final f in [
        '_selectedBusinessId = null;',
        '_selectedDateRange = null;',
        '_selectedTOType = null;',
        '_selectedPublishStatus = null;',
      ]) {
        expect(body.contains(f), true, reason: '$f 가 해제되지 않는다');
      }
    });

    test('04-b notifyListeners는 1회다', () {
      final body = _codeOf(_bodyOf(_src(_ctrlPath), 'void clearFilters('));
      expect('notifyListeners()'.allMatches(body).length, 1);
      // 필터가 없으면 아무 일도 하지 않는다
      expect(body.contains('if (!hasActiveFilters) return;'), true);
    });

    test('04-c Firestore / callable 접근이 없다', () {
      final body = _codeOf(_bodyOf(_src(_ctrlPath), 'void clearFilters('));
      for (final forbidden in [
        'await',
        '_service',
        'load(',
        'reload(',
        'httpsCallable',
        'FirebaseFirestore',
      ]) {
        expect(body.contains(forbidden), false,
            reason: '필터 초기화에 $forbidden 이 들어감 — 추가 read');
      }
    });

    test('04-d 화면 쪽 초기화도 재조회를 하지 않는다', () {
      final body = _codeOf(_bodyOf(_src(_listPath), 'void _clearFilters('));
      expect(body.contains('clearFilters();'), true);
      expect(body.contains('reload'), false);
      expect(body.contains('_reload'), false);
      // 필터 변경 콜백과 같은 확장 상태 초기화
      expect(body.contains('_expandedGroups.clear();'), true);
      expect(body.contains('_activeGroupKey = null;'), true);
    });

    test('04-e 새 filter architecture를 만들지 않았다 (§7)', () {
      final code = _codeOf(_src(_ctrlPath));
      // 기존 setter 4개가 그대로 남아 있다
      for (final s in [
        'void setBusinessIdFilter(String? businessId)',
        'void setDateRangeFilter(DateTimeRange? value)',
        'void setTOTypeFilter(String? value)',
        'void setPublishStatusFilter(String? value)',
      ]) {
        expect(code.contains(s), true);
      }
      // 새 model/persisted state 없음
      expect(code.contains('class FilterState'), false);
      expect(code.contains('SharedPreferences'), false);
    });
  });

  // ── §30, §14 진행중 TAB_EMPTY ───────────────────────────────────
  group('EMPTY-05 진행중만 0건', () {
    test('05-a FULL 1건만 있으면 진행중 탭은 TAB_EMPTY', () {
      final items = [_to(_active, isFull: true)];
      expect(_tabCount(items, _active), 0);
      expect(_tabCount(items, _closed), 1);
      expect(
          _resolveBody(
            isLoading: false,
            hasLoadError: false,
            itemCount: items.length,
            filteredCount: _tabCount(items, _active),
            hasActiveFilters: false,
          ),
          _Body.tabEmpty,
          reason: 'ROOT_EMPTY로 떨어지면 공고가 없다고 거짓말하게 된다');
    });

    test('05-b 진행중 문구가 전체 0을 주장하지 않는다', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_listPath), 'Widget _buildEmptyState(')));
      expect(
          body.contains("? ( '진행중인 공고가 없습니다', "
              "'마감된 공고는 마감됨 탭에서 확인할 수 있습니다', )"),
          true);
    });
  });

  // ── §31, §15 마감됨 TAB_EMPTY ───────────────────────────────────
  group('EMPTY-06 마감됨만 0건', () {
    test('06-a ACTIVE 1건만 있으면 마감됨 탭은 TAB_EMPTY', () {
      final items = [_to(_active)];
      expect(_tabCount(items, _closed), 0);
      expect(
          _resolveBody(
            isLoading: false,
            hasLoadError: false,
            itemCount: items.length,
            filteredCount: _tabCount(items, _closed),
            hasActiveFilters: false,
          ),
          _Body.tabEmpty);
    });

    test('06-b 마감됨 문구가 반대 탭을 가리킨다', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_listPath), 'Widget _buildEmptyState(')));
      expect(
          body.contains(": ( '마감된 공고가 없습니다', "
              "'진행 중인 공고는 진행중 탭에서 확인할 수 있습니다', ),"),
          true);
    });

    test('06-c 실행 불가능한 안내가 사라졌다', () {
      // 새 공고를 등록해도 마감됨 탭은 채워지지 않는다.
      final code = _codeOf(_src(_listPath));
      expect(code.contains('새로운 공고를 등록하세요'), false);
      expect(code.contains('필터를 변경하거나 새로운 공고를 등록하세요'), false);
    });

    test('06-d §11 탭 전환 버튼을 만들지 않았다', () {
      final body = _codeOf(_bodyOf(_src(_listPath), 'Widget _buildEmptyState('));
      expect(body.contains('_selectedTab = '), false,
          reason: 'empty 본문에서 탭을 바꾸는 버튼이 생겼다');
      expect(body.contains("'진행중 보기'"), false);
      expect(body.contains("'마감됨 보기'"), false);
    });
  });

  // ── §32 DRAFT / SCHEDULED ───────────────────────────────────────
  group('EMPTY-07 DRAFT·SCHEDULED도 존재하는 공고다', () {
    test('07-a DRAFT만 있어도 ROOT_EMPTY가 아니다', () {
      final items = [_to('DRAFT')];
      expect(
          _resolveBody(
            isLoading: false,
            hasLoadError: false,
            itemCount: items.length,
            filteredCount: _tabCount(items, _active),
            hasActiveFilters: false,
          ),
          _Body.list,
          reason: 'DRAFT는 진행중 탭에 보이는 공고다');
    });

    test('07-b SCHEDULED도 마찬가지', () {
      final items = [_to('SCHEDULED')];
      expect(_isClosed(items.first), false);
      expect(_tabCount(items, _active), 1);
    });

    test('07-c ROOT_EMPTY 판정이 status를 따로 거르지 않는다', () {
      // controller.items는 이미 DRAFT/SCHEDULED를 포함한다.
      // 여기서 status 필터를 다시 걸면 "작성 중인 공고가 있는데 없다"가 된다.
      final body = _codeOf(_bodyOf(_src(_listPath), 'Widget _buildTOList('));
      expect(body.contains('if (controller.items.isEmpty) {'), true);
      expect(body.contains('TOStatus.draft'), false);
      expect(body.contains('TOStatus.scheduled'), false);
    });

    test('07-d 소프트삭제 TO는 애초에 items에 없다 (§18)', () {
      final svc = _codeOf(_src(_svcPath));
      expect(svc.contains('!to.isSoftDeleted'), true,
          reason: '삭제된 공고가 items에 들어오면 ROOT_EMPTY 판정이 오염된다');
    });
  });

  // ── §33, §17 FULL 분류 ──────────────────────────────────────────
  group('EMPTY-08 FULL 배치 정책 무변경', () {
    test('08-a FULL만 있으면 진행중 empty · 마감됨 목록', () {
      final items = [_to(_active, isFull: true)];
      expect(_tabCount(items, _active), 0);
      expect(_tabCount(items, _closed), 1);
    });

    test('08-b isClosed가 isFull을 포함하는 계약 그대로', () {
      final m = _flat(_codeOf(_src('lib/models/core/to_model.dart')));
      expect(
          m.contains('bool get isClosed => isManualClosed || isFull || '
              'status == TOStatus.closed || status == TOStatus.expired ||'),
          true);
    });

    test('08-c 탭 분류 로직을 건드리지 않았다', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_listPath), 'List<TOGroupItem> _computeFilteredItems(')));
      expect(
          body.contains('source = allItems.where((g) => !g.isClosed);'), true);
      expect(body.contains('source = allItems.where((g) => g.isClosed);'), true);
    });
  });

  // ── §34 ERROR 무변경 ────────────────────────────────────────────
  group('EMPTY-09 ERROR 계약 무변경 (01B)', () {
    test('09-a loadError + items 0 → ERROR (empty 아님)', () {
      expect(
          _resolveBody(
            isLoading: false,
            hasLoadError: true,
            itemCount: 0,
            filteredCount: 0,
            hasActiveFilters: false,
          ),
          _Body.error);
    });

    test('09-b ERROR가 ROOT_EMPTY보다 먼저 판정된다', () {
      final body = _codeOf(_bodyOf(_src(_listPath), 'Widget _buildTOList('));
      final errIdx =
          body.indexOf('if (controller.loadError != null && controller.items.isEmpty) {');
      final rootIdx = body.indexOf('if (controller.items.isEmpty) {');
      expect(errIdx, greaterThan(-1));
      expect(rootIdx, greaterThan(errIdx),
          reason: '조회 실패가 "등록된 공고가 없습니다"로 둔갑한다');
    });

    test('09-c ERROR renderer 문구·action 무변경', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_listPath), 'Widget _buildErrorState(')));
      expect(body.contains("title: '공고 목록을 불러오지 못했습니다',"), true);
      expect(body.contains("subtitle: '네트워크 상태를 확인한 뒤 다시 시도해주세요',"), true);
      expect(body.contains("label: const Text('다시 시도'),"), true);
      expect(body.contains('icon: Icons.cloud_off_rounded,'), true);
      expect(body.contains('onPressed: _reload,'), true);
    });

    test('09-d §21 stale + refresh 실패 계약 무변경', () {
      // items가 남아 있으면 error state로 덮지 않는다 — 토스트로만 알린다.
      final body = _flat(_codeOf(_bodyOf(_src(_listPath), 'Future<void> _reload(')));
      expect(
          body.contains('if (controller.loadError != null && '
              "controller.items.isNotEmpty) { ToastHelper.showError('공고 목록을 새로고침하지 못했습니다'); }"),
          true);
    });
  });

  // ── §35 loading ─────────────────────────────────────────────────
  group('EMPTY-10 로딩 중에는 empty가 보이지 않는다', () {
    test('10-a isLoading이면 어떤 empty도 아니다', () {
      for (final items in [0, 5]) {
        for (final filters in [true, false]) {
          expect(
              _resolveBody(
                isLoading: true,
                hasLoadError: false,
                itemCount: items,
                filteredCount: 0,
                hasActiveFilters: filters,
              ),
              _Body.loading);
        }
      }
    });

    test('10-b §22 _isLoading 초기값을 바꾸지 않았다', () {
      final code = _codeOf(_src(_ctrlPath));
      expect(code.contains('bool _isLoading = false;'), true,
          reason: '최초 프레임 flash는 이번 범위 밖 backlog다');
    });
  });

  // ── §36 group error ─────────────────────────────────────────────
  group('EMPTY-11 flex group error가 empty로 둔갑하지 않는다', () {
    test('11-a 슬롯 로드가 실패해도 items는 남는다 → list', () {
      // 02D.1: 실패한 TO도 TOGroupItem 자체는 items에 존재한다.
      expect(
          _resolveBody(
            isLoading: false,
            hasLoadError: false,
            itemCount: 3,
            filteredCount: 3,
            hasActiveFilters: false,
          ),
          _Body.list);
    });

    test('11-b group error는 root _loadError와 분리돼 있다', () {
      final body = _codeOf(_bodyOf(_src(_ctrlPath), 'Future<void> _runOneLoad('));
      final start = body.indexOf('flexGroups.map((group) async {');
      final end = body.indexOf('} // else 블록 닫힘');
      expect(start, greaterThan(-1));
      final flexBlock = body.substring(start, end);
      expect(flexBlock.contains('_groupDetailErrorIds.add(group.id);'), true);
      expect(flexBlock.contains('_loadError'), false);
    });

    test('11-c 카드 error 계약 무변경', () {
      final card = _codeOf(_src('lib/widgets/admin/cards/admin_to_group_card.dart'));
      expect(card.contains('if (widget.hasGroupDetailError) {'), true);
      expect(card.contains("message: '근무 일정을 불러오지 못했습니다',"), true);
    });
  });

  // ── §37, §38 새 read / readiness 없음 ───────────────────────────
  group('EMPTY-12 추가 조회와 readiness 참조가 없다', () {
    test('12-a empty 경로가 readiness를 참조하지 않는다', () {
      final code = _codeOf(_src(_listPath));
      for (final forbidden in [
        'BusinessPostingReadiness',
        'FirstPostingReadiness',
        'getBusinessWorkTypes',
        'getTemplates',
        'sealBase64',
      ]) {
        expect(code.contains(forbidden), false,
            reason: '공고 탭이 세 번째 readiness 표면이 됐다 — CreateTO가 그 책임을 갖는다');
      }
    });

    test('12-b empty renderer가 순수 계산이다', () {
      final body = _codeOf(_bodyOf(_src(_listPath), 'Widget _buildEmptyState('));
      for (final forbidden in [
        'await',
        '_firestoreService',
        'httpsCallable',
        'FirebaseFirestore',
      ]) {
        expect(body.contains(forbidden), false);
      }
    });

    test('12-c 분기 판정도 순수 계산이다', () {
      final body = _codeOf(_bodyOf(_src(_listPath), 'Widget _buildTOList('));
      expect(body.contains('controller.items.isEmpty'), true);
      expect(body.contains('controller.hasActiveFilters'), true);
      // 분기 구간(= 목록 렌더 시작 전)만 본다 — ListView의 expand 콜백은 별개다
      final branchRegion = body.substring(0, body.indexOf('return RefreshIndicator('));
      for (final forbidden in [
        'await',
        '_firestoreService',
        'httpsCallable',
        'FirebaseFirestore',
      ]) {
        expect(branchRegion.contains(forbidden), false,
            reason: 'empty 분기에 $forbidden 이 들어감 — 추가 read');
      }
    });

    test('12-d 서버 무변경', () {
      final fns = _src('functions/src/index.ts');
      expect(fns.contains('export const callableGetAdminTOs'), true);
    });
  });

  // ── §19, §23, §24, §25 범위 밖 무변경 ───────────────────────────
  group('EMPTY-13 범위 밖 무변경', () {
    test('13-a renderer를 상태마다 복제하지 않았다 (§23)', () {
      final code = _codeOf(_src(_listPath));
      expect('Widget _buildEmptyState('.allMatches(code).length, 1);
      expect('AppEmptyState('.allMatches(code).length, 2,
          reason: 'empty 1개 + error 1개여야 한다');
    });

    test('13-b AppEmptyState 디자인 시스템 유지 (§24)', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_listPath), 'Widget _buildEmptyState(')));
      expect(body.contains('icon: Icons.inbox_outlined,'), true);
      // 자체 Column/Padding으로 새 레이아웃을 짜지 않았다
      expect(body.contains('Column('), false);
      expect(body.contains('Padding('), false);
    });

    test('13-c SubAdmin scope 배선 무변경 (§19)', () {
      final root = _codeOf(_src('lib/screens/business_admin/jobs_root_screen.dart'));
      expect(root.contains('up.isSubAdmin ? up.effectiveBusinessId : null'), true);
      expect(root.contains('hasFilters: controller.hasActiveFilters,'), true);
    });

    test('13-d 브랜드 감성 문구가 없다 (§25)', () {
      final body = _bodyOf(_src(_listPath), 'Widget _buildEmptyState(');
      for (final forbidden in ['인재', '시작', 'ALfit', '만나']) {
        expect(body.contains(forbidden), false, reason: '$forbidden — 운영 화면 문구가 아니다');
      }
    });

    test('13-e 필터 다이얼로그 계약 무변경', () {
      final dlg = _codeOf(_src('lib/widgets/inputs/filter_dialog.dart'));
      expect(dlg.contains('void _resetFilters()'), true);
      expect(dlg.contains('void _applyFilters()'), true);
    });
  });
}
