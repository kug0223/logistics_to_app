// [POSTING-V2-03T.1] 운영 population completeness 분리
//
// 03T READ에서 확인된 것:
//   · callableGetAdminTOs가 사업장당 `orderBy(createdAt desc).limit(500)`
//     하나로 모든 status를 가져왔다. 정렬 키가 생성 시각이라 운영상 유효성과
//     무관했고, ACTIVE·FULL·SCHEDULED·DRAFT·CLOSED·EXPIRED와 소프트삭제
//     문서가 같은 window를 경쟁했다.
//   · 그래서 "오래전에 만들었지만 지금도 근무가 진행 중인 CONTRACT"가
//     최근 공고 500건에 밀려 목록에서 통째로 사라질 수 있었다.
//   · 카드가 사라지면 수정·마감·지원자 관리·초대 경로가 전부 끊긴다.
//   · lifecycle cascade(마감 처리)는 window를 전혀 비워 주지 않아서
//     시간이 갈수록 누락 확률이 단조 증가했다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _fnPath = 'functions/src/index.ts';
const _svcPath = 'lib/services/firestore_service.dart';
const _ctrlPath = 'lib/controllers/workforce_controller.dart';
const _indexesPath = 'firestore.indexes.json';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

/// `export const <name> = ...` 부터 다음 top-level export 직전까지.
String _callableOf(String source, String name) {
  final start = source.indexOf('export const $name');
  if (start == -1) throw StateError('$name 를 찾지 못함');
  final next = source.indexOf('\nexport const ', start + 1);
  return next == -1 ? source.substring(start) : source.substring(start, next);
}

// ═══════════════════════════════════════════════════════════════
// 서버 query 모델 replica
// ═══════════════════════════════════════════════════════════════

const openStates = {'ACTIVE', 'FULL', 'SCHEDULED', 'DRAFT'};
const closedStates = {'CLOSED', 'EXPIRED'};

class ToDoc {
  final String id;
  final String businessId;
  final String status;

  /// 클수록 최근
  final int createdAt;
  final bool isDeleted;

  const ToDoc({
    required this.id,
    required this.businessId,
    required this.status,
    required this.createdAt,
    this.isDeleted = false,
  });
}

/// 이전 구현 — 사업장당 단일 window.
List<String> legacyFetch(
  List<ToDoc> all,
  List<String> bizIds, {
  bool activeOnly = false,
  bool closedOnly = false,
  int perBizLimit = 500,
}) {
  final out = <String>[];
  for (final biz in bizIds) {
    var q = all.where((d) => d.businessId == biz);
    if (activeOnly) {
      q = q.where((d) => openStates.contains(d.status));
    } else if (closedOnly) {
      q = q.where((d) => closedStates.contains(d.status));
    }
    final sorted = q.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    // limit은 isDeleted 필터보다 **먼저** 적용된다
    out.addAll(sorted
        .take(perBizLimit)
        .where((d) => !d.isDeleted)
        .map((d) => d.id));
  }
  return out;
}

/// 현재 구현 — OPEN 무제한 + CLOSED 최신 500.
List<String> splitFetch(
  List<ToDoc> all,
  List<String> bizIds, {
  bool activeOnly = false,
  bool closedOnly = false,
  int closedHistoryLimit = 500,
}) {
  final out = <String>[];
  for (final biz in bizIds) {
    final base = all.where((d) => d.businessId == biz);
    if (!closedOnly) {
      // 상한 없음
      out.addAll(base
          .where((d) => openStates.contains(d.status))
          .where((d) => !d.isDeleted)
          .map((d) => d.id));
    }
    if (!activeOnly) {
      final closed = base.where((d) => closedStates.contains(d.status)).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      out.addAll(closed
          .take(closedHistoryLimit)
          .where((d) => !d.isDeleted)
          .map((d) => d.id));
    }
  }
  return out;
}

// ═══════════════════════════════════════════════════════════════
// fixture
// ═══════════════════════════════════════════════════════════════

/// 최근 [count]건의 마감 공고. createdAt은 1000부터 증가.
List<ToDoc> recentClosed(String biz, int count, {String status = 'CLOSED'}) => [
      for (var i = 0; i < count; i++)
        ToDoc(
            id: '${biz}_closed_$i',
            businessId: biz,
            status: status,
            createdAt: 1000 + i),
    ];

void main() {
  // ══════════════════════════════════════════════════════════════
  // §16 — 핵심 누락 재현
  // ══════════════════════════════════════════════════════════════
  group('01. 오래된 운영 공고가 최근 마감 이력에 밀리지 않는다', () {
    // 1년 전에 만들었고 지금도 근무가 진행 중인 CONTRACT
    const oldActive = ToDoc(
        id: 'contract_running',
        businessId: 'A',
        status: 'ACTIVE',
        createdAt: 1);
    final all = [oldActive, ...recentClosed('A', 500)];

    test('01-a 이전 구현에서는 누락됐다', () {
      final got = legacyFetch(all, ['A']);
      expect(got.length, 500);
      expect(got.contains('contract_running'), false,
          reason: '생성 시각만으로 잘려 나갔다');
    });

    test('01-b 현재 구현은 반환한다', () {
      final got = splitFetch(all, ['A']);
      expect(got.contains('contract_running'), true);
    });

    test('01-c 마감 이력도 함께 유지된다 — 범위 축소 없음', () {
      final got = splitFetch(all, ['A']);
      expect(got.length, 501, reason: 'OPEN 1건 + CLOSED 500건');
    });

    test('01-d 마감이 500을 넘어도 운영 공고는 살아남는다', () {
      final many = [oldActive, ...recentClosed('A', 1200)];
      final got = splitFetch(many, ['A']);
      expect(got.contains('contract_running'), true);
      expect(got.length, 501, reason: 'CLOSED는 여전히 최신 500');
    });

    test('01-e 운영 공고가 여러 개여도 전부 나온다 (§1 상한 없음)', () {
      final all = [
        for (var i = 0; i < 900; i++)
          ToDoc(
              id: 'open_$i',
              businessId: 'A',
              status: 'ACTIVE',
              createdAt: i),
        ...recentClosed('A', 500),
      ];
      final got = splitFetch(all, ['A']);
      expect(got.where((id) => id.startsWith('open_')).length, 900);
      expect(legacyFetch(all, ['A']).where((id) => id.startsWith('open_')).length,
          lessThan(900));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §17 — FLEX
  // ══════════════════════════════════════════════════════════════
  group('02. 미래 슬롯이 남은 FLEX', () {
    test('02-a 오래된 FLEX가 최근 마감 500에 밀리지 않는다', () {
      // 슬롯 추가는 totalSlots만 increment하고 createdAt을 갱신하지 않는다.
      //   그래서 미래 슬롯이 아무리 많아도 createdAt은 최초 생성 시각 그대로다.
      const oldFlex = ToDoc(
          id: 'flex_future_slots',
          businessId: 'A',
          status: 'ACTIVE',
          createdAt: 2);
      final all = [oldFlex, ...recentClosed('A', 700)];
      expect(legacyFetch(all, ['A']).contains('flex_future_slots'), false);
      expect(splitFetch(all, ['A']).contains('flex_future_slots'), true);
    });

    test('02-b cascade가 아직 안 돈 FLEX도 OPEN으로 넘어온다 (§8)', () {
      // master ACTIVE + 전 슬롯 종료 → 서버는 OPEN으로 보고, 클라이언트가
      //   TOGroupItem.isClosed로 마감 분류한다. over-fetch 방향이라 안전하다.
      const stale = ToDoc(
          id: 'cascade_pending',
          businessId: 'A',
          status: 'ACTIVE',
          createdAt: 3);
      expect(splitFetch([stale], ['A']).contains('cascade_pending'), true);
    });

    test('02-c FULL도 운영 population이다', () {
      const full =
          ToDoc(id: 'full_to', businessId: 'A', status: 'FULL', createdAt: 4);
      final all = [full, ...recentClosed('A', 600)];
      expect(splitFetch(all, ['A']).contains('full_to'), true);
    });

    test('02-d SCHEDULED도 운영 population이다', () {
      const sched = ToDoc(
          id: 'sched_to', businessId: 'A', status: 'SCHEDULED', createdAt: 5);
      final all = [sched, ...recentClosed('A', 600)];
      expect(splitFetch(all, ['A']).contains('sched_to'), true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §6 §18 — DRAFT
  // ══════════════════════════════════════════════════════════════
  group('03. DRAFT 보존', () {
    test('03-a openStates에 DRAFT가 있다', () {
      expect(openStates.contains('DRAFT'), true);
    });

    test('03-b 오래된 DRAFT도 OPEN population에 포함된다', () {
      const oldDraft = ToDoc(
          id: 'old_draft', businessId: 'A', status: 'DRAFT', createdAt: 6);
      final all = [oldDraft, ...recentClosed('A', 800)];
      expect(legacyFetch(all, ['A']).contains('old_draft'), false);
      expect(splitFetch(all, ['A']).contains('old_draft'), true);
    });

    test('03-c DRAFT를 빼면 회귀다 — 진행중 탭에서 사라진다', () {
      const drafts = {'ACTIVE', 'FULL', 'SCHEDULED'}; // DRAFT 누락 가정
      const d = ToDoc(id: 'x', businessId: 'A', status: 'DRAFT', createdAt: 1);
      expect(drafts.contains(d.status), false,
          reason: '이 집합을 쓰면 미공개 공고가 통째로 누락된다');
      expect(openStates.contains(d.status), true);
    });

    test('03-d DRAFT가 마감 window를 소비하지 않는다', () {
      final all = [
        for (var i = 0; i < 400; i++)
          ToDoc(
              id: 'draft_$i',
              businessId: 'A',
              status: 'DRAFT',
              createdAt: 2000 + i),
        ...recentClosed('A', 500),
      ];
      final got = splitFetch(all, ['A']);
      expect(got.where((id) => id.startsWith('draft_')).length, 400);
      expect(got.where((id) => id.contains('closed')).length, 500,
          reason: 'DRAFT가 늘어도 마감 500이 줄지 않는다');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §19 — 마감 이력
  // ══════════════════════════════════════════════════════════════
  group('04. 마감 이력 window', () {
    test('04-a createdAt DESC 최신 500', () {
      final all = recentClosed('A', 700);
      final got = splitFetch(all, ['A']);
      expect(got.length, 500);
      expect(got.contains('A_closed_699'), true, reason: '가장 최근');
      expect(got.contains('A_closed_0'), false, reason: '가장 오래된');
    });

    test('04-b EXPIRED도 마감 population이다', () {
      final all = [
        ...recentClosed('A', 250),
        ...recentClosed('A', 250, status: 'EXPIRED')
            .map((d) => ToDoc(
                id: '${d.id}_exp',
                businessId: d.businessId,
                status: 'EXPIRED',
                createdAt: d.createdAt + 5000)),
      ];
      final got = splitFetch(all, ['A']);
      expect(got.where((id) => id.endsWith('_exp')).length, 250);
    });

    test('04-c OPEN 수가 많아도 마감 500이 줄지 않는다', () {
      final all = [
        for (var i = 0; i < 2000; i++)
          ToDoc(
              id: 'open_$i',
              businessId: 'A',
              status: 'ACTIVE',
              createdAt: 5000 + i),
        ...recentClosed('A', 700),
      ];
      final got = splitFetch(all, ['A']);
      expect(got.where((id) => id.contains('closed')).length, 500);
      expect(got.where((id) => id.startsWith('open_')).length, 2000);
    });

    test('04-d 이전보다 마감 범위가 줄지 않았다 (§2)', () {
      final all = recentClosed('A', 700);
      expect(splitFetch(all, ['A']).length,
          greaterThanOrEqualTo(legacyFetch(all, ['A']).length));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §4 — API contract
  // ══════════════════════════════════════════════════════════════
  group('05. activeOnly / closedOnly 계약', () {
    final all = [
      const ToDoc(id: 'a', businessId: 'A', status: 'ACTIVE', createdAt: 1),
      const ToDoc(id: 'd', businessId: 'A', status: 'DRAFT', createdAt: 2),
      const ToDoc(id: 'c', businessId: 'A', status: 'CLOSED', createdAt: 3),
    ];

    test('05-a activeOnly=true → OPEN만', () {
      final got = splitFetch(all, ['A'], activeOnly: true);
      expect(got.toSet(), {'a', 'd'});
    });

    test('05-b closedOnly=true → CLOSED만', () {
      final got = splitFetch(all, ['A'], closedOnly: true);
      expect(got.toSet(), {'c'});
    });

    test('05-c 둘 다 false → merge', () {
      final got = splitFetch(all, ['A']);
      expect(got.toSet(), {'a', 'd', 'c'});
    });

    test('05-d 두 모집단은 배타적이라 중복이 없다', () {
      final got = splitFetch(all, ['A']);
      expect(got.length, got.toSet().length);
      expect(openStates.intersection(closedStates), isEmpty);
    });

    test('05-e Posting은 둘 다 false로 호출한다', () {
      final code = _codeOf(_src(_ctrlPath));
      expect(_flat(code).contains('activeOnly: false, closedOnly: false'), true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §20 — 다사업장 / scope
  // ══════════════════════════════════════════════════════════════
  group('06. 다사업장 독립성', () {
    test('06-a A의 문서 수가 B 결과에 영향을 주지 않는다', () {
      final all = [
        ...recentClosed('A', 2000),
        const ToDoc(id: 'b_open', businessId: 'B', status: 'ACTIVE', createdAt: 1),
        ...recentClosed('B', 10),
      ];
      final got = splitFetch(all, ['A', 'B']);
      expect(got.contains('b_open'), true);
      expect(got.where((id) => id.startsWith('B_closed')).length, 10);
      expect(got.where((id) => id.startsWith('A_closed')).length, 500);
    });

    test('06-b 사업장마다 독립적인 마감 window를 갖는다', () {
      final all = [...recentClosed('A', 700), ...recentClosed('B', 700)];
      final got = splitFetch(all, ['A', 'B']);
      expect(got.where((id) => id.startsWith('A_closed')).length, 500);
      expect(got.where((id) => id.startsWith('B_closed')).length, 500);
    });

    test('06-c scope 밖 사업장은 조회되지 않는다', () {
      final all = [
        const ToDoc(id: 'c_open', businessId: 'C', status: 'ACTIVE', createdAt: 1),
        const ToDoc(id: 'a_open', businessId: 'A', status: 'ACTIVE', createdAt: 1),
      ];
      expect(splitFetch(all, ['A']).toSet(), {'a_open'});
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §10 §21 — soft delete
  // ══════════════════════════════════════════════════════════════
  group('07. soft delete', () {
    test('07-a 삭제된 문서는 결과에서 빠진다', () {
      final all = [
        const ToDoc(id: 'live', businessId: 'A', status: 'ACTIVE', createdAt: 2),
        const ToDoc(
            id: 'gone',
            businessId: 'A',
            status: 'ACTIVE',
            createdAt: 1,
            isDeleted: true),
      ];
      expect(splitFetch(all, ['A']).toSet(), {'live'});
    });

    test('07-b OPEN이 무제한이라 삭제 문서가 completeness를 자르지 않는다', () {
      final all = [
        for (var i = 0; i < 800; i++)
          ToDoc(
              id: 'del_$i',
              businessId: 'A',
              status: 'DRAFT',
              createdAt: 3000 + i,
              isDeleted: true),
        const ToDoc(id: 'live', businessId: 'A', status: 'ACTIVE', createdAt: 1),
      ];
      expect(legacyFetch(all, ['A']).contains('live'), false,
          reason: '삭제 문서가 window를 소진했다');
      expect(splitFetch(all, ['A']).contains('live'), true);
    });

    test('07-c CLOSED에서는 삭제 문서가 여전히 cap을 소비한다 — backlog', () {
      final all = [
        for (var i = 0; i < 500; i++)
          ToDoc(
              id: 'del_$i',
              businessId: 'A',
              status: 'CLOSED',
              createdAt: 4000 + i,
              isDeleted: true),
        ...recentClosed('A', 10),
      ];
      final got = splitFetch(all, ['A']);
      expect(got.where((id) => id.startsWith('A_closed')).length, 0,
          reason: '[BACKLOG-POSTING-SOFT-DELETED-CAP-CONSUMPTION] 알려진 한계');
    });

    test('07-d where(isDeleted) 쿼리를 새로 만들지 않았다 (§21)', () {
      final fn = _codeOf(_callableOf(_src(_fnPath), 'callableGetAdminTOs'));
      expect(fn.contains('where("isDeleted"'), false,
          reason: '필드 부재는 쿼리로 표현할 수 없다 — 레거시 문서가 빠진다');
      expect(fn.contains('d.data().isDeleted !== true'), true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 서버 소스 고정
  // ══════════════════════════════════════════════════════════════
  group('08. callableGetAdminTOs 소스', () {
    final fn = _callableOf(_src(_fnPath), 'callableGetAdminTOs');
    final code = _codeOf(fn);
    final flat = _flat(code);

    test('08-a openStates에 DRAFT가 포함됐다', () {
      expect(
        flat.contains(
            'const openStates = ["ACTIVE", "FULL", "SCHEDULED", "DRAFT"];'),
        true,
      );
      expect(flat.contains('const closedStates = ["CLOSED", "EXPIRED"];'), true);
    });

    test('08-b 사업장별 단일 window가 사라졌다', () {
      expect(code.contains('PER_BIZ_LIMIT'), false);
      expect(
        flat.contains(
            '.where("businessId", "==", bizId) .orderBy("createdAt", "desc") .limit('),
        false,
        reason: 'status 무관 단일 window는 제거됐다',
      );
    });

    test('08-c OPEN 쿼리에 limit이 없다 (§1)', () {
      final open = flat.substring(
          flat.indexOf('if (!closedOnly)'), flat.indexOf('if (!activeOnly)'));
      expect(open.contains('base.where("status", "in", openStates)'), true);
      expect(open.contains('.limit('), false);
    });

    test('08-d CLOSED 쿼리는 createdAt DESC 500이다 (§1)', () {
      final closed = flat.substring(flat.indexOf('if (!activeOnly)'));
      expect(
        closed.contains(
            '.where("status", "in", closedStates) .orderBy("createdAt", "desc") .limit(CLOSED_HISTORY_LIMIT)'),
        true,
      );
      expect(code.contains('const CLOSED_HISTORY_LIMIT = 500;'), true);
    });

    test('08-e activeOnly / closedOnly 분기가 계약대로다 (§4)', () {
      expect(code.contains('if (!closedOnly) {'), true);
      expect(code.contains('if (!activeOnly) {'), true);
    });

    test('08-f authorization이 쿼리보다 앞이다 (§5)', () {
      final auth = code.indexOf('assertBizAdmin(callerUid, id)');
      final query = code.indexOf('ids.flatMap(bizId');
      expect(auth, greaterThan(-1));
      expect(auth, lessThan(query));
      expect(
        _flat(code).contains(
            'await Promise.all(ids.map(id => assertBizAdmin(callerUid, id)))'),
        true,
        reason: '03N all-or-nothing scope 무회귀',
      );
    });

    test('08-g 응답 DTO shape이 그대로다 (§12)', () {
      expect(flat.contains('return {items};'), true);
      expect(
        flat.contains(
            'map(d => ({id: d.id, ...serializeFirestoreData(d.data())}))'),
        true,
      );
    });

    test('08-h 사업장별 병렬 구조가 유지된다', () {
      expect(code.contains('await Promise.all('), true);
      expect(code.contains('ids.flatMap(bizId'), true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §15 — index
  // ══════════════════════════════════════════════════════════════
  group('09. Firestore index', () {
    final indexes = _flat(_src(_indexesPath));

    test('09-a businessId + status + createdAt 인덱스가 이미 있다', () {
      expect(
        indexes.contains(
            '"collectionGroup": "tos", "queryScope": "COLLECTION", "fields": [ { "fieldPath": "businessId", "order": "ASCENDING" }, { "fieldPath": "status", "order": "ASCENDING" }, { "fieldPath": "createdAt", "order": "DESCENDING" } ]'),
        true,
      );
    });

    test('09-b 신규 인덱스를 추가하지 않았다', () {
      // 두 쿼리 모두 위 인덱스(또는 그 prefix)로 커버된다
      final tosIndexes =
          RegExp(r'"collectionGroup": "tos"').allMatches(indexes).length;
      expect(tosIndexes, 11, reason: '03T READ 시점과 동일');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §13 §25 — 클라이언트 무회귀
  // ══════════════════════════════════════════════════════════════
  group('10. 클라이언트 무변경', () {
    test('10-a getTOGroupItemsLight는 계속 단일 리스트를 받는다', () {
      final body = _codeOf(_src(_svcPath));
      expect(body.contains("result.data['items'] as List<dynamic>?"), true);
      expect(_flat(body).contains('..sort((a, b) => b.singleTO.createdAt.compareTo(a.singleTO.createdAt));'),
          true,
          reason: 'service 예비 정렬 유지');
    });

    test('10-b controller의 정렬·loading·coalescing 계약 무변경', () {
      final ctrl = _codeOf(_src(_ctrlPath));
      for (final marker in [
        'static List<TOGroupItem> sortForOperations(',
        'static DateTime? priorityDateOf(',
        'bool get hasLoadedOnce => _hasLoadedOnce;',
        'Future<void>? _loadCycle;',
        'static const _scopeShrinkCandidates',
      ]) {
        expect(ctrl.contains(marker), true, reason: marker);
      }
    });

    test('10-c 추가 client read가 없다', () {
      final ctrl = _codeOf(_src(_ctrlPath));
      expect(
        RegExp(r'getTOGroupItemsLight\(').allMatches(ctrl).length,
        2,
        reason: 'root 조회 + scope 복구 재시도 — 03N 그대로',
      );
    });
  });
}
