import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════
// POSTING-V2-02A.1 TAB COUNT / QUOTA SEPARATION
//
// '진행중 (N / max)' 는 서로 다른 두 모집단을 한 숫자로 묶고 있었다.
//
//   client N   : _items.where(!isClosed)
//                FULL 제외 · DRAFT/SCHEDULED 포함 · 사업장 필터 미반영
//   server quota: owner-global scope · ACTIVE+FULL · DRAFT/SCHEDULED 제외
//                 한도는 owner 문서, 클라이언트는 호출자 문서를 읽었다
//
// MODEL C: 탭은 렌더 카드 수만 말하고, 한도는 생성·공개 시점에 서버가 말한다.
// ═══════════════════════════════════════════════════════════════

const _listPath =
    'lib/screens/business_admin/workforce_management/workforce_list_view.dart';
const _ctrlPath = 'lib/controllers/workforce_controller.dart';
const _toFsPath = 'lib/services/firestore/to_firestore.dart';
const _createPath =
    'lib/screens/business_admin/to_management/create_to_screen.dart';
const _fnPath = 'functions/src/index.ts';
const _cardPath = 'lib/widgets/admin/cards/admin_to_group_card.dart';
const _inviteDialogPath =
    'lib/screens/business_admin/dialogs/invite_worker_dialog.dart';

String _src(String p) => File(p).readAsStringSync();

/// `//` 주석 줄 제거 — 주석 안의 문자열이 코드로 오탐되는 것을 막는다.
String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

/// 공백 1칸 평탄화.
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

// ── 탭 계약 재현 ──────────────────────────────────────────────

/// 목록의 한 공고. [isClosed]는 TOGroupItem.isClosed 결과.
class _Item {
  final String businessId;
  final String type;
  final bool isClosed;
  const _Item(this.businessId, {this.type = 'flex', this.isClosed = false});
}

/// workforce_list_view._matchesFilters 의 사업장/유형 부분 재현.
bool matchesFilters(_Item i, {String? businessId, String? toType}) {
  if (businessId != null && i.businessId != businessId) return false;
  if (toType != null && i.type != toType) return false;
  return true;
}

/// workforce_list_view._visibleActiveCount 재현.
int visibleActiveCount(
  List<_Item> items, {
  String? businessId,
  String? toType,
}) =>
    items
        .where((i) =>
            !i.isClosed && matchesFilters(i, businessId: businessId, toType: toType))
        .length;

/// 진행중 탭이 렌더하는 목록 재현 (_computeFilteredItems active 분기).
List<_Item> renderedActiveList(
  List<_Item> items, {
  String? businessId,
  String? toType,
}) =>
    items
        .where((i) =>
            !i.isClosed && matchesFilters(i, businessId: businessId, toType: toType))
        .toList();

/// 탭 라벨 재현 — _buildTab.
String tabLabel({
  required String label,
  required bool isActiveTab,
  required Object? loadError,
  required int itemCount,
  required int visibleCount,
}) {
  final trustworthy = loadError == null || itemCount > 0;
  final count = (isActiveTab && trustworthy) ? visibleCount : null;
  return count != null ? '$label ($count)' : label;
}

// 옛 계약 재현 — 회귀 기준용
String legacyTabLabel({
  required int activeToCount,
  required int maxActiveTOs,
  required bool showDenominator,
}) =>
    showDenominator
        ? '진행중 ($activeToCount/$maxActiveTOs)'
        : '진행중 ($activeToCount)';

void main() {
  final list = _src(_listPath);
  final listCode = _codeOf(list);
  final ctrl = _src(_ctrlPath);
  final ctrlCode = _codeOf(ctrl);

  // ═════════════════════════════════════════════════════════════
  // QUOTA-UI-01 — 기본 count
  // ═════════════════════════════════════════════════════════════
  group('QUOTA-UI-01 탭 count 기본', () {
    test('진행중 5건 → 진행중 (5)', () {
      final items = List.generate(5, (i) => const _Item('A'));
      expect(
        tabLabel(
          label: '진행중',
          isActiveTab: true,
          loadError: null,
          itemCount: items.length,
          visibleCount: visibleActiveCount(items),
        ),
        '진행중 (5)',
      );
    });

    test('분모가 어떤 형태로도 붙지 않는다', () {
      final l = tabLabel(
        label: '진행중',
        isActiveTab: true,
        loadError: null,
        itemCount: 3,
        visibleCount: 3,
      );
      expect(l.contains('/'), isFalse);
      expect(l, isNot(contains('4')));
    });

    test('마감됨 탭은 count 없음 (현행 유지)', () {
      expect(
        tabLabel(
          label: '마감됨',
          isActiveTab: false,
          loadError: null,
          itemCount: 9,
          visibleCount: 4,
        ),
        '마감됨',
      );
    });

    test('라벨 조립이 단순 (N) 형태다', () {
      final body = _codeOf(_bodyOf(list, 'Widget _buildTab('));
      expect(
        _flat(body).contains(
            "final displayLabel = activeCount != null ? '\$label (\$activeCount)' : label;"),
        isTrue,
      );
    });
  });

  // ═════════════════════════════════════════════════════════════
  // QUOTA-UI-02 — 탭 배치 기준, 서버 quota와 독립
  // ═════════════════════════════════════════════════════════════
  group('QUOTA-UI-02 DRAFT / SCHEDULED / FULL', () {
    // 탭 배치는 TOGroupItem.isClosed가 결정한다.
    //   DRAFT / SCHEDULED / ACTIVE → isClosed false → 진행중
    //   FULL                       → isClosed true  → 마감됨
    const draft = _Item('A');
    const scheduled = _Item('A');
    const active = _Item('A');
    const full = _Item('A', isClosed: true);

    test('진행중에 렌더되는 것은 모두 N에 포함된다', () {
      expect(visibleActiveCount([draft, scheduled, active]), 3);
    });

    test('FULL은 마감됨 탭이므로 N에서 빠진다', () {
      expect(visibleActiveCount([active, full]), 1);
    });

    test('서버 quota membership과 독립이다', () {
      // 서버: ACTIVE+FULL을 세고 DRAFT/SCHEDULED를 뺀다 → 이 fixture에서 2
      // 탭  : 진행중 렌더 3
      // 두 숫자가 다른 것이 정상이다 — 같은 것을 세지 않는다.
      final tab = visibleActiveCount([draft, scheduled, active, full]);
      const serverQuotaUsed = 2; // active + full
      expect(tab, 3);
      expect(tab == serverQuotaUsed, isFalse);
    });

    test('FULL을 quota에 맞추려고 진행중에 끌어오지 않았다', () {
      // isClosed 기반 탭 분기는 그대로다
      final body = _codeOf(_bodyOf(list, 'List<TOGroupItem> _computeFilteredItems('));
      expect(
        _flat(body).contains('if (_selectedTab == TOStatus.active) { '
            'source = allItems.where((g) => !g.isClosed); } '
            'else { source = allItems.where((g) => g.isClosed); }'),
        isTrue,
      );
    });
  });

  // ═════════════════════════════════════════════════════════════
  // QUOTA-UI-03 — 필터 반영
  // ═════════════════════════════════════════════════════════════
  group('QUOTA-UI-03 필터', () {
    final items = [
      const _Item('A'),
      const _Item('A'),
      const _Item('A'),
      const _Item('B'),
      const _Item('B'),
      const _Item('C', isClosed: true),
    ];

    test('무필터 5 → 사업장 A 3 → 사업장 B 2', () {
      expect(visibleActiveCount(items), 5);
      expect(visibleActiveCount(items, businessId: 'A'), 3);
      expect(visibleActiveCount(items, businessId: 'B'), 2);
    });

    test('유형 필터도 반영된다', () {
      final mixed = [
        const _Item('A', type: 'flex'),
        const _Item('A', type: 'contract'),
        const _Item('A', type: 'flex'),
      ];
      expect(visibleActiveCount(mixed, toType: 'flex'), 2);
      expect(visibleActiveCount(mixed, toType: 'contract'), 1);
    });

    test('N이 렌더 목록 길이와 항상 같다', () {
      for (final biz in [null, 'A', 'B', 'C']) {
        expect(
          visibleActiveCount(items, businessId: biz),
          renderedActiveList(items, businessId: biz).length,
          reason: '필터 $biz 에서 탭 숫자와 카드 수가 다르다',
        );
      }
    });

    test('필터 결과 0도 렌더 0과 일치한다', () {
      expect(visibleActiveCount(items, businessId: 'Z'), 0);
      expect(renderedActiveList(items, businessId: 'Z'), isEmpty);
    });

    test('옛 계약은 필터를 반영하지 않았다 (회귀 기준)', () {
      // activeToCount = _items.where(!isClosed) — 필터 무관
      const legacyNumerator = 5; // A3 + B2, 필터와 무관하게 고정
      expect(visibleActiveCount(items, businessId: 'A'), 3);
      expect(legacyNumerator == 3, isFalse,
          reason: '옛 분자가 필터를 따랐다면 이 Phase의 전제가 틀린 것');
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 단일 source
  // ═════════════════════════════════════════════════════════════
  group('필터 술어 단일 source', () {
    test('_matchesFilters 하나를 목록과 count가 공유한다', () {
      expect(listCode.contains('bool _matchesFilters('), isTrue);
      final visible = _codeOf(_bodyOf(list, 'int _visibleActiveCount('));
      final computed =
          _codeOf(_bodyOf(list, 'List<TOGroupItem> _computeFilteredItems('));
      expect(visible.contains('_matchesFilters(g, controller)'), isTrue);
      expect(computed.contains('_matchesFilters(g, controller)'), isTrue);
    });

    test('필터 술어가 복제되지 않았다', () {
      // selectedBusinessId 비교는 _matchesFilters 안에서만 일어난다
      expect(
        'groupItem.businessId != selectedBusinessId'.allMatches(listCode).length,
        1,
        reason: '사업장 필터 비교가 두 곳에 존재한다',
      );
      expect(
        'selectedPublishStatus != null'.allMatches(listCode).length,
        1,
        reason: '공개상태 필터가 복제됐다',
      );
    });

    test('count가 렌더와 같은 isClosed 기준을 쓴다', () {
      final visible = _flat(_codeOf(_bodyOf(list, 'int _visibleActiveCount(')));
      expect(visible.contains('!g.isClosed && _matchesFilters(g, controller)'),
          isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // quota UI 제거
  // ═════════════════════════════════════════════════════════════
  group('quota UI 제거', () {
    test('공고 탭에 showDenominator / isMaxed 가 없다', () {
      expect(listCode.contains('showDenominator'), isFalse);
      expect(listCode.contains('isMaxed'), isFalse);
      expect(listCode.contains('managedBusinessIds'), isFalse,
          reason: 'quota scope 추정 로직이 남아 있다');
    });

    test('분모 문자열 조립이 없다', () {
      expect(listCode.contains(r'/${controller.maxActiveTOs}'), isFalse);
      expect(listCode.contains('maxActiveTOs'), isFalse);
    });

    test('탭 count에 경고 색상이 없다', () {
      final body = _codeOf(_bodyOf(list, 'Widget _buildTab('));
      expect(body.contains('AppColors.error'), isFalse,
          reason: '한도 초과 추정 색상이 남아 있다');
      expect(
        _flat(body)
            .contains('color: isSelected ? theme.primaryColor : AppColors.grey500,'),
        isTrue,
      );
    });

    test('controller가 한도를 들고 있지 않다', () {
      expect(ctrlCode.contains('maxActiveTOs'), isFalse);
      expect(ctrlCode.contains('getMaxActiveTOLimit'), isFalse);
      expect(ctrlCode.contains('activeToCount'), isFalse,
          reason: '거부된 분자 계약이 재사용 가능한 상태로 남아 있다');
    });

    test('옛 라벨은 이제 만들 수 없다 (회귀 기준)', () {
      expect(
        legacyTabLabel(
            activeToCount: 6, maxActiveTOs: 4, showDenominator: true),
        '진행중 (6/4)',
      );
      // 새 계약에서는 이런 라벨이 나올 수 없다
      final l = tabLabel(
        label: '진행중',
        isActiveTab: true,
        loadError: null,
        itemCount: 6,
        visibleCount: 6,
      );
      expect(l, '진행중 (6)');
    });
  });

  // ═════════════════════════════════════════════════════════════
  // QUOTA-UI-04 — SubAdmin drift 비노출
  // ═════════════════════════════════════════════════════════════
  group('QUOTA-UI-04 SubAdmin', () {
    test('owner override와 무관하게 visible count만 표시', () {
      // owner max 10 / global 4 / SubAdmin visible 6
      final items = List.generate(6, (i) => const _Item('A'));
      final l = tabLabel(
        label: '진행중',
        isActiveTab: true,
        loadError: null,
        itemCount: 6,
        visibleCount: visibleActiveCount(items),
      );
      expect(l, '진행중 (6)');
      expect(l.contains('/4'), isFalse);
      expect(l.contains('/10'), isFalse);
    });

    test('탭이 isSubAdmin을 보지 않는다', () {
      final body = _codeOf(_bodyOf(list, 'Widget _buildTab('));
      expect(body.contains('isSubAdmin'), isFalse);
      expect(body.contains('UserProvider'), isFalse);
    });

    test('UserProvider import가 목록 뷰에서 사라졌다', () {
      expect(list.contains("import '../../../providers/user_provider.dart';"),
          isFalse,
          reason: 'quota scope 추정을 위한 의존이 남아 있다');
    });
  });

  // ═════════════════════════════════════════════════════════════
  // QUOTA-UI-05 — error / genuine zero (01B 계약 유지)
  // ═════════════════════════════════════════════════════════════
  group('QUOTA-UI-05 error vs zero', () {
    test('초기 로드 실패 → count 숨김', () {
      expect(
        tabLabel(
          label: '진행중',
          isActiveTab: true,
          loadError: 'boom',
          itemCount: 0,
          visibleCount: 0,
        ),
        '진행중',
      );
    });

    test('성공 + 0건 → 진행중 (0)', () {
      expect(
        tabLabel(
          label: '진행중',
          isActiveTab: true,
          loadError: null,
          itemCount: 0,
          visibleCount: 0,
        ),
        '진행중 (0)',
      );
    });

    test('refresh 실패 + stale 데이터 → 마지막 visible count 유지', () {
      expect(
        tabLabel(
          label: '진행중',
          isActiveTab: true,
          loadError: 'refresh failed',
          itemCount: 7,
          visibleCount: 5,
        ),
        '진행중 (5)',
      );
    });

    test('countIsTrustworthy 계약이 그대로다', () {
      final body = _flat(_codeOf(_bodyOf(list, 'Widget _buildTab(')));
      expect(
        body.contains('final countIsTrustworthy = controller.loadError == null '
            '|| controller.items.isNotEmpty;'),
        isTrue,
      );
      expect(
        body.contains('final activeCount = (isActiveTab && countIsTrustworthy) '
            '? _visibleActiveCount(controller) : null;'),
        isTrue,
      );
    });
  });

  // ═════════════════════════════════════════════════════════════
  // QUOTA-UI-06 — CreateTO / 서버 gate 무변경
  // ═════════════════════════════════════════════════════════════
  group('QUOTA-UI-06 서버 quota gate 무변경', () {
    final fn = _codeOf(_src(_fnPath));

    test('서버 quota 계약 그대로', () {
      expect(fn.contains('.where("status", "in", ["ACTIVE", "FULL"]),'), isTrue);
      expect(fn.contains(r'return `ADMIN:${ownerUid}`;'), isTrue);
      expect(
        fn.contains('const globalRaw = configSnap.data()?.maxActiveTOPerBusiness as unknown;'),
        isTrue,
      );
      expect(
        fn.contains('throw new HttpsError("resource-exhausted", '
            '`MAX_ACTIVE_TO_LIMIT:\${activePostingCapacity}`);'),
        isTrue,
      );
    });

    test('FULL quota 정책을 결정하지 않았다', () {
      // [BACKLOG-QUOTA-FULL-RELEASE-POLICY] 유지
      expect(fn.contains('"FULL"'), isTrue);
      expect(fn.contains('function isEffectiveActiveTOForQuota('), isTrue);
    });

    test('CreateTO 한도 안내 카피 무변경', () {
      final create = _codeOf(_src(_createPath));
      expect(create.contains("if (msg.contains('MAX_ACTIVE_TO_LIMIT')) {"), isTrue);
      expect(
        create.contains(
            "ToastHelper.showError('진행중인 공고가 최대 \$limitStr개입니다.\\n기존 공고를 마감 후 새 공고를 등록해주세요.');"),
        isTrue,
      );
    });

    test('publish / reopen gate 무변경', () {
      expect(fn.contains('const effectivePubCount = await getEffectiveActivePostingCountTx('),
          isTrue);
      expect(fn.contains('const rtCount = await getEffectiveActivePostingCountTx('),
          isTrue);
      expect(fn.contains('const effectiveCountRS = await getEffectiveActivePostingCountTx('),
          isTrue);
    });

    test('공고 등록 CTA를 한도로 비활성화하지 않았다', () {
      final root =
          _codeOf(_src('lib/screens/business_admin/jobs_root_screen.dart'));
      expect(root.contains('maxActiveTOs'), isFalse);
      expect(root.contains('isMaxed'), isFalse);
      expect(root.contains('_JobsCreateButton('), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 읽기 비용
  // ═════════════════════════════════════════════════════════════
  group('읽기 비용', () {
    test('load()에서 한도 조회가 제거됐다', () {
      final body = _codeOf(_bodyOf(ctrl, 'Future<void> load('));
      expect(body.contains('getMaxActiveTOLimit'), isFalse);
      expect(body.contains('limitFuture'), isFalse);
      // 목록 조회는 그대로
      expect(body.contains('_service.getTOGroupItemsLight('), isTrue);
    });

    test('탭 count 계산이 새 조회를 하지 않는다', () {
      final visible = _codeOf(_bodyOf(list, 'int _visibleActiveCount('));
      for (final forbidden in [
        'await',
        'httpsCallable',
        'FirebaseFirestore',
        'getMaxActiveTOLimit',
      ]) {
        expect(visible.contains(forbidden), isFalse,
            reason: 'count 계산이 "$forbidden" 로 조회한다');
      }
    });

    test('service 메서드 자체는 남겨 뒀다 (다른 caller 존재)', () {
      final svc = _src(_toFsPath);
      expect(svc.contains('Future<int> getMaxActiveTOLimit('), isTrue,
          reason: 'SUPER_ADMIN 캐시 무효화 API와 dead preflight가 참조한다');
      expect(svc.contains('void invalidateGlobalTOLimitCache()') ||
          svc.contains('invalidateGlobalTOLimitCache'), isTrue);
    });

    test('dead quota preflight는 이번에 건드리지 않았다', () {
      // [BACKLOG-POSTING-DEAD-QUOTA-PREFLIGHT]
      final svc = _codeOf(_src(_toFsPath));
      expect(svc.contains('Future<void> assertActiveTOLimit('), isTrue);
      expect(svc.contains('Future<int> countAllActiveTO('), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // scope guard
  // ═════════════════════════════════════════════════════════════
  group('scope guard', () {
    test('quota persistent UI를 추가하지 않았다', () {
      for (final forbidden in ['공고 한도', '남은 공고', '한도 초과']) {
        expect(listCode.contains(forbidden), isFalse,
            reason: '"$forbidden" 표면을 새로 만들었다 (MODEL B 금지)');
      }
    });

    test('마감됨 탭에 count를 추가하지 않았다', () {
      final body = _flat(_codeOf(_bodyOf(list, 'Widget _buildTabBar(')));
      expect(body.contains("TOStatus.closed, '마감됨', Icons.check_circle_outline"),
          isTrue);
      // count는 isActiveTab에서만 계산된다
      final tabBody = _codeOf(_bodyOf(list, 'Widget _buildTab('));
      expect(tabBody.contains('isActiveTab && countIsTrustworthy'), isTrue);
    });

    test('POSTING-V2-01A 회귀 없음', () {
      final d = _flat(_codeOf(_src(_inviteDialogPath)));
      expect(
        d.contains("'selectedWorkType': generalWd!.workType, "
            "'workDetailStartTime': generalWd.startTime, "
            "'workDetailEndTime': generalWd.endTime,"),
        isTrue,
      );
    });

    test('POSTING-V2-01B 회귀 없음', () {
      expect(ctrlCode.contains('_loadError = e;'), isTrue);
      expect(ctrlCode.contains('Object? get loadError => _loadError;'), isTrue);
      expect(listCode.contains('return _buildErrorState();'), isTrue);
    });

    test('POSTING-V2-01C 회귀 없음', () {
      final cardCode = _codeOf(_src(_cardPath));
      expect(cardCode.contains('if (canDelete && isDraft)'), isTrue);
      expect(_codeOf(_src(_fnPath)).contains('assertNoPostingRelations('), isTrue);
    });

    test('business result 변경 없음', () {
      final cardCode = _codeOf(_src(_cardPath));
      for (final action in [
        'batchCloseSlots(',
        'batchReopenSlots(',
        'batchDeleteSlots(',
        'showCloseTODialog(',
        'showReopenTODialog(',
      ]) {
        expect(cardCode.contains(action), isTrue, reason: '$action 경로가 사라졌다');
      }
    });
  });
}
