import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════
// POSTING-V2-01B ERROR != ZERO
//
// 공고 탭의 조회 실패가 정상 EMPTY/ZERO로 둔갑하면 안 된다.
//
//   root list 실패   → '조건에 맞는 공고가 없습니다 / 새 공고를 등록하세요'
//   tab count 실패   → '진행중 (0/4)'
//   detail 실패      → '확정 0 · 대기 0 · 미충원 N'
//   slot 실패        → '슬롯 없음'
//
// 네 경로 모두 장애를 정상 수치로 확정해 보여주고 있었고,
// root 실패는 장애 중에 '새 공고를 만들라'는 잘못된 행동까지 유도했다.
// ═══════════════════════════════════════════════════════════════

const _svcPath = 'lib/services/firestore_service.dart';
const _ctrlPath = 'lib/controllers/workforce_controller.dart';
const _listPath =
    'lib/screens/business_admin/workforce_management/workforce_list_view.dart';
const _cardPath = 'lib/widgets/admin/cards/admin_to_group_card.dart';
const _rowPath = 'lib/widgets/admin/cards/admin_work_detail.dart';
const _modelPath = 'lib/models/ui/admin_to_list_ui_models.dart';
const _dialogPath =
    'lib/screens/business_admin/dialogs/invite_worker_dialog.dart';

String _src(String p) => File(p).readAsStringSync();

/// `//` 주석 줄 제거 — 주석 문자열이 코드로 오탐되는 것을 막는다.
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

// ── 상태 계약 재현 ────────────────────────────────────────────
//
// WorkforceController / WorkforceListView 의 판정 순서를 그대로 옮긴다.

enum _RootState { loading, error, empty, data }

/// workforce_list_view._buildTOList 의 분기 순서 재현.
_RootState _rootState({
  required bool isLoading,
  required Object? loadError,
  required int itemCount,
  required int filteredCount,
}) {
  if (isLoading) return _RootState.loading;
  if (loadError != null && itemCount == 0) return _RootState.error;
  if (filteredCount == 0) return _RootState.empty;
  return _RootState.data;
}

/// workforce_list_view._buildTab 의 count 판정 재현.
int? _tabCount({
  required Object? loadError,
  required int itemCount,
  required int activeToCount,
}) {
  final trustworthy = loadError == null || itemCount > 0;
  return trustworthy ? activeToCount : null;
}

/// WorkforceController.load 의 상태 전이 재현.
class _Ctrl {
  bool isLoading = false;
  Object? loadError;
  List<String> items = [];

  /// [throws] 가 null이 아니면 실패로 끝난다.
  void load({Object? throws, List<String>? result}) {
    isLoading = true;
    loadError = null; // 새 시도 시작 시 이전 실패 제거
    try {
      if (throws != null) throw throws;
      items = result ?? [];
    } catch (e) {
      // items는 건드리지 않는다
      loadError = e;
    } finally {
      isLoading = false;
    }
  }
}

/// TOItem.resolveStats 의 statsFailed 폴백 재현.
({int confirmed, int pending, int required}) _resolveStats({
  required bool statsFailed,
  required bool isWorkDetailLoaded,
  required Map<String, Map<String, int>> workStats,
  required List<String> workDetailIds,
  required List<int> requiredCounts,
  required int slotConfirmed,
  required int slotPending,
  required int slotRequired,
}) {
  if (statsFailed) {
    return (
      confirmed: slotConfirmed,
      pending: slotPending,
      required: slotRequired
    );
  }
  if (isWorkDetailLoaded && workDetailIds.isNotEmpty) {
    var c = 0, p = 0, r = 0;
    for (var i = 0; i < workDetailIds.length; i++) {
      final s = workStats[workDetailIds[i]];
      c += s?['confirmed'] ?? 0;
      p += s?['pending'] ?? 0;
      r += requiredCounts[i];
    }
    return (confirmed: c, pending: p, required: r);
  }
  return (
    confirmed: slotConfirmed,
    pending: slotPending,
    required: slotRequired
  );
}

void main() {
  // ═════════════════════════════════════════════════════════════
  // 1. 실패 전파 — 삼키지 않는다
  // ═════════════════════════════════════════════════════════════
  group('실패 전파', () {
    final svc = _src(_svcPath);

    test('getTOGroupItemsLight가 빈 배열 대신 예외를 올린다', () {
      final body = _codeOf(
          _bodyOf(svc, 'Future<List<TOGroupItem>> getTOGroupItemsLight('));
      expect(body.contains('rethrow;'), isTrue,
          reason: '실패를 rethrow하지 않는다');
      // catch 블록에 return [] 이 남아 있으면 안 된다
      final catchIdx = body.indexOf('} catch (e) {');
      expect(catchIdx, isNot(-1));
      expect(body.substring(catchIdx).contains('return [];'), isFalse,
          reason: 'catch가 여전히 빈 배열을 반환한다');
      // 정상 early-return(빈 사업장)은 보존
      expect(
        body.contains('if (businessIds != null && businessIds.isEmpty) return [];'),
        isTrue,
        reason: '사업장 0개라는 진짜 empty까지 없애면 안 된다',
      );
    });

    // [POSTING-V2-02D.1] 슬롯 로더가 loadGroupTOsLight → loadFlexSlots로 통합됐다.
    //   ERROR != EMPTY 계약은 그대로 canonical loader 하나에 걸린다.
    test('loadFlexSlots가 빈 결과 대신 예외를 올린다', () {
      final body =
          _codeOf(_bodyOf(svc, 'Future<FlexSlotLoad> loadFlexSlots('));
      final catchIdx = body.indexOf('} catch (e) {');
      expect(catchIdx, isNot(-1));
      expect(body.substring(catchIdx).contains('rethrow;'), isTrue);
      expect(body.substring(catchIdx).contains('return empty;'), isFalse);
      expect(body.substring(catchIdx).contains('return {};'), isFalse,
          reason: '옛 getFlexTOSlotDates의 ERROR==EMPTY 의미가 되살아났다');
      // 슬롯이 실제로 0건인 경우는 여전히 빈 결과
      expect(body.contains('if (snap.docs.isEmpty) return empty;'), isTrue,
          reason: '슬롯 0건이라는 진짜 empty는 보존돼야 한다');
    });

    test('loadTOWorkDetails가 statsFailed를 함께 반환한다', () {
      final body = _codeOf(
          _bodyOf(svc, 'Future<Map<String, dynamic>> loadTOWorkDetails('));
      final flat = _flat(body);
      expect(flat.contains('var statsFailed = false;'), isTrue);
      expect(flat.contains('statsFailed = true;'), isTrue,
          reason: 'catch에서 실패 사실을 기록하지 않는다');
      expect(
        flat.contains("return { 'workDetails': workDetails, "
            "'workStats': workStats, 'statsFailed': statsFailed, };"),
        isTrue,
        reason: '반환 계약에 statsFailed가 없다',
      );
    });

    test('workStats 초기화는 그대로 — 0은 여전히 정상 0의 표현이다', () {
      final body = _codeOf(
          _bodyOf(svc, 'Future<Map<String, dynamic>> loadTOWorkDetails('));
      expect(
        _flat(body).contains(
            "for (final w in workDetails) w.id: {'confirmed': 0, 'pending': 0},"),
        isTrue,
      );
    });
  });

  // ═════════════════════════════════════════════════════════════
  // ERROR-ZERO-01 — root 실패
  // ═════════════════════════════════════════════════════════════
  group('ERROR-ZERO-01 root list 실패', () {
    test('controller가 실패를 loadError로 남기고 items를 지우지 않는다', () {
      final body = _codeOf(_bodyOf(_src(_ctrlPath), 'Future<void> load('));
      final catchIdx = body.indexOf('} catch (e) {');
      expect(catchIdx, isNot(-1));
      final catchBlock = body.substring(catchIdx);
      expect(catchBlock.contains('_loadError = e;'), isTrue);
      expect(catchBlock.contains('_items = [];'), isFalse,
          reason: '실패를 빈 목록으로 커밋하고 있다');
    });

    test('실패 상태에서 empty state가 아니라 error state가 나온다', () {
      expect(
        _rootState(
            isLoading: false, loadError: 'boom', itemCount: 0, filteredCount: 0),
        _RootState.error,
      );
    });

    test('error 분기가 empty 분기보다 먼저 평가된다', () {
      final body = _codeOf(_bodyOf(_src(_listPath), 'Widget _buildTOList('));
      final errIdx = body.indexOf('return _buildErrorState();');
      // [POSTING-V2-02E.1] 성공 empty가 셋으로 갈렸다 — error는 그 **전부**보다 앞선다.
      final emptyIdx = body.indexOf('_buildEmptyState(');
      expect(errIdx, isNot(-1), reason: 'error state 분기가 없다');
      expect(emptyIdx, isNot(-1));
      expect(errIdx < emptyIdx, isTrue,
          reason: 'empty가 먼저 평가되면 실패가 empty로 새어나간다');
      for (final kind in ['root', 'filtered', 'tab']) {
        expect(body.contains('_PostingEmptyKind.$kind'), isTrue,
            reason: '성공 empty가 ROOT / FILTERED / TAB로 갈리지 않는다');
      }
      expect(
        _flat(body).contains(
            'if (controller.loadError != null && controller.items.isEmpty) {'),
        isTrue,
      );
    });

    test('error state의 primary action이 공고 등록이 아니라 다시 시도다', () {
      final err = _codeOf(_bodyOf(_src(_listPath), 'Widget _buildErrorState('));
      expect(err.contains("title: '공고 목록을 불러오지 못했습니다',"), isTrue);
      expect(err.contains("const Text('다시 시도')"), isTrue);
      expect(err.contains('onPressed: _reload,'), isTrue,
          reason: 'retry가 canonical reload를 쓰지 않는다');
      // 장애 상황에서 '새 공고를 등록하세요' 유도 금지
      expect(err.contains('공고를 등록'), isFalse);
      expect(err.contains('등록하세요'), isFalse);
    });

    test('empty state 문구는 error state로 재사용되지 않는다', () {
      final empty = _codeOf(_bodyOf(_src(_listPath), 'Widget _buildEmptyState('));
      final err = _codeOf(_bodyOf(_src(_listPath), 'Widget _buildErrorState('));
      expect(empty.contains('조건에 맞는 공고가 없습니다'), isTrue);
      expect(err.contains('조건에 맞는 공고가 없습니다'), isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // ERROR-ZERO-02 / 03 — 진짜 empty / filter empty 보존
  // ═════════════════════════════════════════════════════════════
  group('ERROR-ZERO-02·03 정상 empty 보존', () {
    test('조회 성공 + 0건은 여전히 empty state', () {
      expect(
        _rootState(
            isLoading: false, loadError: null, itemCount: 0, filteredCount: 0),
        _RootState.empty,
      );
    });

    test('조회 성공 + 필터 결과 0건은 empty state (ERROR 아님)', () {
      expect(
        _rootState(
            isLoading: false, loadError: null, itemCount: 12, filteredCount: 0),
        _RootState.empty,
      );
    });

    test('조회 성공 + 결과 있음은 data', () {
      expect(
        _rootState(
            isLoading: false, loadError: null, itemCount: 12, filteredCount: 3),
        _RootState.data,
      );
    });

    test('로딩이 항상 최우선', () {
      expect(
        _rootState(
            isLoading: true, loadError: 'boom', itemCount: 0, filteredCount: 0),
        _RootState.loading,
      );
    });

    test('LOADING → ERROR 가 LOADING → EMPTY 로 끝나지 않는다', () {
      final c = _Ctrl();
      c.load(throws: 'network');
      expect(c.isLoading, isFalse);
      expect(
        _rootState(
            isLoading: c.isLoading,
            loadError: c.loadError,
            itemCount: c.items.length,
            filteredCount: 0),
        _RootState.error,
      );
    });
  });

  // ═════════════════════════════════════════════════════════════
  // ERROR-ZERO-01b — tab count / filter options / scope
  // ═════════════════════════════════════════════════════════════
  group('tab count · filter options', () {
    test('실패 + 데이터 없음이면 count를 숨긴다 (0으로 확정하지 않음)', () {
      expect(_tabCount(loadError: 'boom', itemCount: 0, activeToCount: 0),
          isNull);
    });

    test('실패 + stale 데이터면 마지막 known count를 유지한다', () {
      expect(_tabCount(loadError: 'boom', itemCount: 7, activeToCount: 5), 5);
    });

    test('성공하면 실제 count를 그대로 쓴다 (0건 포함)', () {
      expect(_tabCount(loadError: null, itemCount: 0, activeToCount: 0), 0);
      expect(_tabCount(loadError: null, itemCount: 9, activeToCount: 4), 4);
    });

    test('_buildTab이 loadError를 count 신뢰도로 쓴다', () {
      final body = _codeOf(_bodyOf(_src(_listPath), 'Widget _buildTab('));
      final flat = _flat(body);
      expect(
        flat.contains('final countIsTrustworthy = controller.loadError == null '
            '|| controller.items.isNotEmpty;'),
        isTrue,
      );
      // [POSTING-V2-02A.1] count source가 controller.activeToCount에서
      // 렌더 목록 기반 _visibleActiveCount로 바뀌었다. ERROR != ZERO 계약
      // (실패 + 데이터 없음 → count 숨김)은 그대로다.
      expect(
        flat.contains('final activeCount = (isActiveTab && countIsTrustworthy) '
            '? _visibleActiveCount(controller) : null;'),
        isTrue,
      );
    });

    test('실패 상태에서 사업장 필터를 열지 않는다 (사업장 0개 오인 방지)', () {
      final body = _codeOf(_bodyOf(_src(_listPath), 'void _showFilterDialog('));
      final flat = _flat(body);
      expect(
        flat.contains(
            'if (controller.loadError != null && controller.items.isEmpty) {'),
        isTrue,
        reason: '실패 상태에서 빈 사업장 목록이 노출된다',
      );
      // 새 사업장 query를 만들지 않았다
      expect(body.contains('getBusinesses'), isFalse);
      expect(body.contains('httpsCallable'), isFalse);
      // 옵션 파생 방식은 그대로
      expect(flat.contains('for (final g in controller.items) '
          'if (g.businessId.isNotEmpty) g.businessId: g.businessName,'), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // ERROR-ZERO-04 / 05 — workDetail 통계 실패와 재시도
  // ═════════════════════════════════════════════════════════════
  group('ERROR-ZERO-04·05 workDetail 통계', () {
    test('controller가 statsFailed를 모델로 전달한다', () {
      final body =
          _codeOf(_bodyOf(_src(_ctrlPath), 'Future<void> loadWorkDetails('));
      final flat = _flat(body);
      expect(flat.contains("statsFailed: result['statsFailed'] == true,"),
          isTrue);
      final catchIdx = flat.indexOf('} catch (e) {');
      expect(catchIdx, isNot(-1));
      expect(flat.substring(catchIdx).contains('slot.markWorkDetailStatsFailed();'),
          isTrue, reason: '예외를 조용히 삼켜 0으로 남긴다');
    });

    test('WorkDetailRow가 실패 시 수치 대신 실패 행을 그린다', () {
      final row = _codeOf(_src(_rowPath));
      final flat = _flat(row);
      expect(
        flat.contains('if (widget.statsFailed) _buildStatsErrorRow(context) '
            'else _buildPersonnelStatus(context, isFull, isClosed, missing),'),
        isTrue,
        reason: '실패 상태에서도 확정/대기/미충원 수치를 그린다',
      );
      expect(row.contains("'지원 현황을 불러오지 못했습니다',"), isTrue);
      expect(row.contains("Text('재시도',"), isTrue);
    });

    test('실패 시 진행률 바와 지원자 칩을 숨긴다', () {
      final flat = _flat(_codeOf(_src(_rowPath)));
      expect(
        flat.contains('if (!widget.statsFailed) ...[ '
            'SizedBox(height: ResponsiveHelper.spacing(context, 6)), '
            '_buildProgressBar(isClosed), ],'),
        isTrue,
        reason: '0% 진행률 바가 그대로 그려진다',
      );
      expect(
        flat.contains('if (!widget.statsFailed && totalApplicants > 0) ...['),
        isTrue,
        reason: '지원자 칩이 통계 실패와 무관하게 표시된다',
      );
    });

    test('실패 시 isFull을 판정하지 않는다', () {
      final flat = _flat(_codeOf(_src(_rowPath)));
      expect(
        flat.contains('final isFull = !widget.statsFailed && '
            '_confirmedCount >= widget.work.requiredCount;'),
        isTrue,
        reason: '0/N으로 모집 상태를 주장한다',
      );
    });

    test('재시도가 기존 loadTOWorkDetails를 재사용한다 (신규 API 없음)', () {
      final retry = _codeOf(
          _bodyOf(_src(_cardPath), 'Future<void> _retryWorkDetailStats('));
      expect(retry.contains('widget.firestoreService.loadTOWorkDetails('), isTrue);
      expect(retry.contains('item.resetWorkDetailLoad()'), isTrue,
          reason: '재시도 전에 실패 상태를 되돌리지 않는다');
      expect(retry.contains("statsFailed: result['statsFailed'] == true,"), isTrue);
      expect(retry.contains('httpsCallable'), isFalse);
      expect(retry.contains('FirebaseFirestore'), isFalse);
    });

    test('재시도 성공 시 error flag가 남지 않는다', () {
      final model = _src(_modelPath);
      final reset = _codeOf(_bodyOf(model, 'void resetWorkDetailLoad('));
      expect(_flat(reset).contains('isWorkDetailLoaded = false; '
          'workDetailStatsFailed = false;'), isTrue);
      // setWorkDetails는 항상 statsFailed를 새 값으로 덮어쓴다
      final setter = _codeOf(_bodyOf(model, 'void setWorkDetails('));
      expect(setter.contains('workDetailStatsFailed = statsFailed;'), isTrue,
          reason: '성공해도 이전 실패 flag가 남는다');
    });
  });

  // ═════════════════════════════════════════════════════════════
  // §12 — header counter와 detail stats 분리
  // ═════════════════════════════════════════════════════════════
  group('header capacity vs detail stats', () {
    test('detail 실패 시 header는 슬롯 counter로 폴백한다 (0이 되지 않음)', () {
      final s = _resolveStats(
        statsFailed: true,
        isWorkDetailLoaded: true,
        workStats: {'a': {'confirmed': 0, 'pending': 0}},
        workDetailIds: ['a'],
        requiredCounts: [5],
        slotConfirmed: 3,
        slotPending: 2,
        slotRequired: 5,
      );
      expect(s.confirmed, 3, reason: 'detail 실패가 header를 0으로 만든다');
      expect(s.pending, 2);
      expect(s.required, 5);
    });

    test('detail 성공 시에는 workDetailStats 집계를 그대로 쓴다', () {
      final s = _resolveStats(
        statsFailed: false,
        isWorkDetailLoaded: true,
        workStats: {'a': {'confirmed': 4, 'pending': 1}},
        workDetailIds: ['a'],
        requiredCounts: [6],
        slotConfirmed: 3,
        slotPending: 2,
        slotRequired: 5,
      );
      expect(s.confirmed, 4);
      expect(s.required, 6);
    });

    test('resolveStats에 statsFailed 폴백이 실제로 들어 있다', () {
      final body = _codeOf(_bodyOf(_src(_modelPath),
          '({int confirmed, int pending, int required}) resolveStats('));
      final flat = _flat(body);
      expect(flat.contains('if (workDetailStatsFailed) { return ( '
          'confirmed: confirmedCount, pending: pendingCount, '
          'required: totalRequired ); }'), isTrue);
      // 폴백이 workDetailStats 분기보다 앞에 있어야 한다
      final failIdx = body.indexOf('if (workDetailStatsFailed)');
      final loadedIdx = body.indexOf('if (isWorkDetailLoaded');
      expect(failIdx < loadedIdx, isTrue);
    });

    test('capacity source 통합을 하지 않았다 (범위 밖)', () {
      final model = _codeOf(_src(_modelPath));
      // 슬롯 counter 기반 폴백 경로가 그대로 살아 있다
      expect(
        _flat(model).contains('return ( confirmed: confirmedCount, '
            'pending: pendingCount, required: totalRequired ); }'),
        isTrue,
      );
    });
  });

  // ═════════════════════════════════════════════════════════════
  // ERROR-ZERO-06 — group/slot detail 실패
  // ═════════════════════════════════════════════════════════════
  group('ERROR-ZERO-06 slot/group detail 실패', () {
    test('controller가 group detail 실패를 id로 기록한다', () {
      final body =
          _codeOf(_bodyOf(_src(_ctrlPath), 'Future<void> loadGroupDetails('));
      final flat = _flat(body);
      expect(flat.contains('_groupDetailErrorIds.remove(group.id);'), isTrue,
          reason: '재시도 시작 시 이전 실패를 지우지 않는다');
      final catchIdx = flat.indexOf('} catch (e) {');
      expect(catchIdx, isNot(-1));
      expect(flat.substring(catchIdx).contains('_groupDetailErrorIds.add(group.id);'),
          isTrue);
      // 실패 시 setGroupTOs([])로 '슬롯 없음'을 커밋하지 않는다
      expect(flat.substring(catchIdx).contains('setGroupTOs'), isFalse);
    });

    test('카드가 슬롯 실패를 슬롯 없음이 아니라 error로 그린다', () {
      final body =
          _codeOf(_bodyOf(_src(_cardPath), 'Widget _buildExpandedBodyContent('));
      final flat = _flat(body);
      expect(flat.contains('if (widget.hasGroupDetailError) {'), isTrue);
      expect(flat.contains("message: '근무 일정을 불러오지 못했습니다',"), isTrue);
      expect(flat.contains('onRetry: widget.onRetryGroupDetail,'), isTrue);
      // 로딩 다음, 정상 렌더 이전에 평가돼야 한다
      final loadIdx = body.indexOf('widget.isGroupLoading');
      final errIdx = body.indexOf('widget.hasGroupDetailError');
      final rowIdx = body.indexOf('_getSingleTOWorkDetails()');
      expect(loadIdx < errIdx && errIdx < rowIdx, isTrue,
          reason: 'error 분기 순서가 잘못됐다');
    });

    test('group detail 실패 범위가 카드에 한정된다 (root ERROR 아님)', () {
      final list = _codeOf(_src(_listPath));
      final flat = _flat(list);
      // 카드에만 전달
      expect(
        flat.contains(
            'hasGroupDetailError: controller.hasGroupDetailError(groupItem.id),'),
        isTrue,
      );
      // root ERROR 판정 조건 자체는 loadError/items만 본다.
      // (카드에 prop을 넘기는 코드는 같은 함수 안에 있으므로 조건절만 검사한다)
      final rootBody = _flat(_codeOf(_bodyOf(list, 'Widget _buildTOList(')));
      final condIdx = rootBody.indexOf('return _buildErrorState();');
      expect(condIdx, isNot(-1));
      final cond = rootBody.substring(0, condIdx);
      expect(cond.contains('hasGroupDetailError'), isFalse,
          reason: '카드 하나의 실패가 탭 전체를 ERROR로 만든다');
      expect(
        cond.contains(
            'if (controller.loadError != null && controller.items.isEmpty) {'),
        isTrue,
      );
    });

    test('group 재시도가 canonical load 경로를 재사용한다', () {
      final retry = _codeOf(
          _bodyOf(_src(_listPath), 'Future<void> _handleGroupDetailRetry('));
      expect(retry.contains('controller.loadGroupDetails(context, groupItem)'),
          isTrue);
      expect(retry.contains('httpsCallable'), isFalse);
      expect(retry.contains('FirebaseFirestore'), isFalse);
    });

    test('목록 재로드 시 stale group error가 정리된다', () {
      final body = _codeOf(_bodyOf(_src(_ctrlPath), 'Future<void> load('));
      expect(body.contains('_groupDetailErrorIds.clear();'), isTrue,
          reason: '복구된 공고가 계속 error로 보인다');
    });
  });

  // ═════════════════════════════════════════════════════════════
  // ERROR-ZERO-07 + §29 — 에러 종류 무관 / 상태 지속성
  // ═════════════════════════════════════════════════════════════
  group('ERROR-ZERO-07 에러 종류 · 상태 전이', () {
    for (final err in [
      'permission-denied',
      'unauthenticated',
      'unavailable (network)',
      'deadline-exceeded',
    ]) {
      test('$err 도 empty가 아니라 ERROR', () {
        final c = _Ctrl();
        c.load(throws: err);
        expect(c.loadError, err);
        expect(
          _rootState(
              isLoading: false,
              loadError: c.loadError,
              itemCount: c.items.length,
              filteredCount: 0),
          _RootState.error,
        );
      });
    }

    test('첫 로드 실패 → 재시도 성공 → error가 사라진다', () {
      final c = _Ctrl();
      c.load(throws: 'boom');
      expect(c.loadError, isNotNull);
      c.load(result: ['to_1', 'to_2']);
      expect(c.loadError, isNull, reason: '성공 후에도 error flag가 남는다');
      expect(
        _rootState(
            isLoading: false,
            loadError: c.loadError,
            itemCount: c.items.length,
            filteredCount: 2),
        _RootState.data,
      );
    });

    test('첫 로드 실패 → 재시도 성공 → 0건이면 정상 EMPTY', () {
      final c = _Ctrl();
      c.load(throws: 'boom');
      c.load(result: []);
      expect(c.loadError, isNull);
      expect(
        _rootState(
            isLoading: false,
            loadError: null,
            itemCount: 0,
            filteredCount: 0),
        _RootState.empty,
      );
    });

    test('실패 → 재시도 재실패 → 여전히 ERROR (empty로 안 떨어짐)', () {
      final c = _Ctrl();
      c.load(throws: 'boom');
      c.load(throws: 'boom again');
      expect(c.loadError, 'boom again');
      expect(
        _rootState(
            isLoading: false,
            loadError: c.loadError,
            itemCount: 0,
            filteredCount: 0),
        _RootState.error,
      );
    });

    test('성공 후 refresh 실패가 기존 데이터를 지우지 않는다', () {
      final c = _Ctrl();
      c.load(result: ['to_1', 'to_2', 'to_3']);
      expect(c.items.length, 3);
      c.load(throws: 'refresh failed');
      expect(c.items.length, 3, reason: 'refresh 실패가 목록을 비웠다');
      expect(c.loadError, isNotNull, reason: '실패가 인지 불가능하다');
      // 데이터가 남아 있으므로 본문은 data, 실패는 토스트로 알린다
      expect(
        _rootState(
            isLoading: false,
            loadError: c.loadError,
            itemCount: 3,
            filteredCount: 3),
        _RootState.data,
      );
    });

    test('refresh 실패를 토스트로 알린다', () {
      final body = _codeOf(_bodyOf(_src(_listPath), 'Future<void> _reload('));
      final flat = _flat(body);
      expect(
        flat.contains('if (controller.loadError != null && '
            'controller.items.isNotEmpty) { '
            "ToastHelper.showError('공고 목록을 새로고침하지 못했습니다'); }"),
        isTrue,
        reason: 'refresh 실패가 아무 신호 없이 지나간다',
      );
      expect(flat.contains('if (!mounted) return;'), isTrue,
          reason: 'async gap 이후 mounted 체크가 없다');
    });

    test('실패한 로드의 stale items로 후처리를 돌리지 않는다', () {
      final body = _codeOf(_bodyOf(_src(_ctrlPath), 'Future<void> load('));
      final flat = _flat(body);
      expect(flat.contains('if (_loadError != null) return;'), isTrue);
      final guardIdx = body.indexOf('if (_loadError != null) return;');
      // [POSTING-V2-02D.1] _preloadFlexTOSlots가 사라지고 flex cascade close가
      //   guard 뒤로 직접 옮겨졌다. 지켜야 할 것은 "write는 guard 뒤"다.
      final flexCascadeIdx =
          body.indexOf('_maybeCascadeCloseExpiredTO(group, group.groupTOs);');
      final cascadeIdx = body.indexOf('_maybeCascadeCloseExpiredContractTOs();');
      expect(flexCascadeIdx, isNot(-1), reason: 'flex cascade close 지점을 찾지 못함');
      expect(guardIdx < flexCascadeIdx && guardIdx < cascadeIdx, isTrue,
          reason: '신뢰할 수 없는 상태에서 cascade close write가 실행된다');
    });
  });

  // ═════════════════════════════════════════════════════════════
  // §18 — 개별 문서 파싱 실패는 정책 변경 없음
  // ═════════════════════════════════════════════════════════════
  group('malformed document 정책 무변경', () {
    test('슬롯 파싱 실패는 여전히 해당 문서만 skip한다', () {
      // [POSTING-V2-02D.1] 파서가 _slotItemsFromSnapshot으로 분리됐다 — 정책은 동일.
      final body = _codeOf(
          _bodyOf(_src(_svcPath), 'List<TOItem> _slotItemsFromSnapshot('));
      expect(body.contains("debugPrint('⚠️ 슬롯 파싱 실패 (id=\${d.id}): \$e');"),
          isTrue);
      expect(body.contains('.whereType<TOItem>().toList();'), isTrue,
          reason: 'tryFromMap + whereType skip 패턴이 바뀌었다');
    });
  });

  // ═════════════════════════════════════════════════════════════
  // scope guard
  // ═════════════════════════════════════════════════════════════
  group('scope guard', () {
    test('POSTING-V2-01A 초대 정합성 회귀 없음', () {
      final sendBody =
          _flat(_codeOf(_bodyOf(_src(_dialogPath), 'Future<void> _send()')));
      expect(sendBody.contains("'selectedWorkType': generalWd!.workType, "
          "'workDetailStartTime': generalWd.startTime, "
          "'workDetailEndTime': generalWd.endTime,"), isTrue);
      expect(
        sendBody.contains('if (!widget.isContextualMode && generalWd == null) {'),
        isTrue,
      );
    });

    test('write semantics 무변경 — 확정/거절 경로 그대로', () {
      final card = _codeOf(_src(_cardPath));
      expect(card.contains('batchCloseSlots('), isTrue);
      expect(card.contains('batchReopenSlots('), isTrue);
      expect(card.contains('batchDeleteSlots('), isTrue);
    });

    test('P1-3 슬롯 삭제 문구 무변경', () {
      final flat = _flat(_codeOf(_src(_cardPath)));
      expect(
        flat.contains("'선택한 \${deleteSlots.length}개 날짜를 삭제하시겠습니까?"),
        isTrue,
      );
    });

    // [POSTING-V2-02A.1] 이 테스트는 원래 'quota 계산 무변경'을 고정했다
    // (01B 당시 P2-1은 범위 밖이었다). 02A.1에서 탭의 quota 표현을 제거했으므로,
    // 이제 고정해야 할 것은 "탭 count가 ERROR != ZERO 계약을 유지한다"이다.
    test('탭 count가 quota가 아닌 렌더 수를 쓰되 ERROR != ZERO는 유지한다', () {
      final ctrl = _codeOf(_src(_ctrlPath));
      expect(ctrl.contains('activeToCount'), isFalse,
          reason: '거부된 quota 분자 계약이 controller에 남아 있다');
      expect(ctrl.contains('maxActiveTOs'), isFalse);

      final tab = _codeOf(_bodyOf(_src(_listPath), 'Widget _buildTab('));
      expect(_flat(tab).contains('showDenominator'), isFalse,
          reason: 'quota 분모 노출 로직이 남아 있다');
      // 실패 + 데이터 없음 → count 숨김 계약은 그대로
      expect(
        _flat(tab).contains('final countIsTrustworthy = controller.loadError == null '
            '|| controller.items.isNotEmpty;'),
        isTrue,
      );
    });

    test('empty 문구 세분화(P2-5) 하지 않았다 — empty state는 1종 그대로', () {
      final list = _codeOf(_src(_listPath));
      expect('AppEmptyState('.allMatches(list).length, 2,
          reason: 'empty(1) + error(1) 외에 새 상태 surface가 늘었다');
    });

    test('freshness(P2-2) 무변경 — notifyDataChanged 배선 없음', () {
      expect(_codeOf(_src(_listPath)).contains('notifyDataChanged'), isFalse);
    });

    test('신규 query / callable 없음', () {
      for (final p in [_ctrlPath, _listPath]) {
        final s = _codeOf(_src(p));
        expect(s.contains('httpsCallable'), isFalse, reason: '$p 에 새 callable');
        expect(s.contains('FirebaseFirestore'), isFalse,
            reason: '$p 에 새 Firestore 직접 접근');
      }
    });

    // [POSTING-V2-02D.1] duplicate flex read(P2-4)가 해소됐다.
    //   01B가 지켜야 하는 것은 "flex slot 조회 실패가 root error나 empty로
    //   둔갑하지 않는다"이지, 특정 helper의 존재가 아니다. 새 계약으로 옮긴다.
    test('flex slot 조회 실패는 group-detail error로만 남는다', () {
      final body = _codeOf(_bodyOf(_src(_ctrlPath), 'Future<void> load('));
      final start = body.indexOf('flexGroups.map((group) async {');
      final end = body.indexOf('} // else 블록 닫힘');
      expect(start, isNot(-1), reason: 'flex slot 로드 지점을 찾지 못함');
      expect(end, greaterThan(start));
      final flexBlock = body.substring(start, end);

      expect(flexBlock.contains('_groupDetailErrorIds.add(group.id);'), isTrue,
          reason: 'flex slot 실패가 어떤 error truth에도 기록되지 않는다');
      expect(flexBlock.contains('_loadError'), isFalse,
          reason: 'TO 하나의 슬롯 실패가 목록 전체를 ERROR로 만든다');
      expect(flexBlock.contains('rethrow'), isFalse);
      // 실패한 그룹은 setGroupTOs를 거치지 않으므로 '슬롯 없음'으로 굳지 않는다
      expect(flexBlock.contains('setGroupTOs(const [])'), isFalse);
      expect(flexBlock.contains('setSlotDates(const [])'), isFalse);
    });
  });
}
