import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════
// POSTING-V2-01C.1 DELETE RELATION GUARD
//
// 정책 MODEL B:
//   공고/날짜에 외부 관계가 한 번도 생기지 않았을 때만 삭제할 수 있다.
//   관계가 생긴 뒤에는 삭제가 아니라 모집 마감으로 운영하고 기록을 남긴다.
//
// 이전 계약의 구멍:
//   callableDeleteTO   status ∈ {ACTIVE, FULL} + confirmed-like 일 때만 차단
//                      → CLOSED/EXPIRED는 확정자 있어도 통과
//                      → PENDING / INVITED / 과거 REJECTED 무방비
//   callableDeleteSlots guard 없음
//                      → 확정자 REJECTED + 슬롯 문서 물리 삭제
//                      → 전 슬롯 삭제로 TO guard 우회 가능
// ═══════════════════════════════════════════════════════════════

const _fnPath = 'functions/src/index.ts';
const _cardPath = 'lib/widgets/admin/cards/admin_to_group_card.dart';
const _dialogPath =
    'lib/screens/business_admin/dialogs/invite_worker_dialog.dart';
const _ctrlPath = 'lib/controllers/workforce_controller.dart';

String _src(String p) => File(p).readAsStringSync();

/// `//` 주석 줄 제거 — 주석 안의 문자열이 코드로 오탐되는 것을 막는다.
String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

/// 공백 1칸 평탄화.
String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

/// `export const <name> = onCall(` 부터 대응 닫는 괄호까지.
String _callableBody(String source, String name) {
  final start = source.indexOf('export const $name = onCall(');
  if (start == -1) throw StateError('$name 을 찾지 못함');
  var depth = 0;
  final open = source.indexOf('(', start);
  for (var i = open; i < source.length; i++) {
    if (source[i] == '(') depth++;
    if (source[i] == ')') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  throw StateError('$name 본문의 끝을 찾지 못함');
}

/// `function <name>(` 또는 `async function <name>(` 본문.
String _fnBody(String source, String name) {
  final start = source.indexOf('function $name(');
  if (start == -1) throw StateError('$name 을 찾지 못함');
  final open = source.indexOf('{', source.indexOf(')', start));
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  throw StateError('$name 본문의 끝을 찾지 못함');
}

// ── 서버 guard 재현 ───────────────────────────────────────────
//
// assertNoPostingRelations / assertNoSlotRelations 의 판정을 옮겨
// fixture별 결과를 직접 확인한다.

class _App {
  final String status;
  final String? slotId;
  const _App(this.status, {this.slotId});
}

class _Contract {
  /// 'yyyy-MM-dd'
  final String workDate;
  const _Contract(this.workDate);
}

class _Slot {
  final String id;

  /// 'yyyy-MM-dd' (KST)
  final String date;
  const _Slot(this.id, this.date);
}

class _Result {
  final bool blocked;
  final String reason;
  const _Result(this.blocked, this.reason);
}

/// index.ts assertNoPostingRelations 재현.
/// [queryFails]면 fail-closed.
_Result postingGuard({
  required List<_App> applications,
  required List<_Contract> contracts,
  bool queryFails = false,
}) {
  if (queryFails) return const _Result(true, 'RELATION_CHECK_FAILED');
  // status 필터 없음 — 문서 존재 자체가 관계
  if (applications.isNotEmpty) return const _Result(true, 'APPLICATION_EXISTS');
  if (contracts.isNotEmpty) return const _Result(true, 'CONTRACT_EXISTS');
  return const _Result(false, '');
}

const _contractScanLimit = 300;

/// index.ts assertNoSlotRelations 재현.
_Result slotGuard({
  required List<String> selectedSlotIds,
  required List<_Slot> slots,
  required List<_App> applications,
  required List<_Contract> contracts,
  bool queryFails = false,
  int contractTotal = -1,
}) {
  if (queryFails) return const _Result(true, 'RELATION_CHECK_FAILED');

  // 1. 선택 슬롯의 지원서 — status 무관
  final selected = selectedSlotIds.toSet();
  if (applications.any((a) => a.slotId != null && selected.contains(a.slotId))) {
    return const _Result(true, 'APPLICATION_EXISTS');
  }

  // 2. 계약 — toId로 모아 슬롯 날짜와 대조, 스캔 한도 초과 시 fail-closed
  final total = contractTotal >= 0 ? contractTotal : contracts.length;
  if (total >= _contractScanLimit) {
    return const _Result(true, 'CONTRACT_SCAN_TRUNCATED');
  }
  final targetDates = slots
      .where((s) => selected.contains(s.id))
      .map((s) => s.date)
      .toSet();
  if (contracts.any((c) => targetDates.contains(c.workDate))) {
    return const _Result(true, 'CONTRACT_EXISTS');
  }
  return const _Result(false, '');
}

/// 전 슬롯 삭제 → TO 삭제 client chain 재현.
/// 슬롯 단계에서 막히면 TO 단계에 도달하지 못한다.
({bool slotBlocked, bool toReached, bool toBlocked}) deleteAllChain({
  required List<String> selectedSlotIds,
  required List<_Slot> slots,
  required List<_App> applications,
  required List<_Contract> contracts,
}) {
  final s = slotGuard(
    selectedSlotIds: selectedSlotIds,
    slots: slots,
    applications: applications,
    contracts: contracts,
  );
  if (s.blocked) {
    return (slotBlocked: true, toReached: false, toBlocked: false);
  }
  // 슬롯 삭제가 통과했다면 client가 이어서 deleteTO를 호출한다
  final t = postingGuard(applications: applications, contracts: contracts);
  return (slotBlocked: false, toReached: true, toBlocked: t.blocked);
}

/// 실제 코드에 존재하는 application status 전수.
const _allStatuses = [
  'PENDING',
  'INVITED',
  'CONTRACT_PENDING',
  'CONFIRMED',
  'REJECTED',
  'CANCELED',
  'AUTO_CANCELED',
  'EXPIRED',
];

void main() {
  final fn = _src(_fnPath);
  final code = _codeOf(fn);

  // ═════════════════════════════════════════════════════════════
  // guard 구현 검증
  // ═════════════════════════════════════════════════════════════
  group('guard 구현', () {
    test('공통 helper 두 개가 존재한다', () {
      expect(code.contains('async function assertNoPostingRelations('), isTrue);
      expect(code.contains('async function assertNoSlotRelations('), isTrue);
      expect(code.contains('type RelationCheck = '), isTrue);
    });

    test('application 질의에 status 필터가 없다 (allowlist 금지)', () {
      for (final name in ['assertNoPostingRelations', 'assertNoSlotRelations']) {
        final body = _codeOf(_fnBody(fn, name));
        expect(body.contains('"status"'), isFalse,
            reason: '$name 이 status 기반 allowlist를 쓴다');
        expect(body.contains('"CONFIRMED"'), isFalse);
        expect(body.contains('"PENDING"'), isFalse);
        expect(body.contains('"in",'), isFalse);
      }
    });

    test('TO guard는 applications + employment_contracts를 본다', () {
      final body = _flat(_codeOf(_fnBody(fn, 'assertNoPostingRelations')));
      expect(
        body.contains('db.collection("applications") '
            '.where("toId", "==", toId) '
            '.where("businessId", "==", businessId) .limit(1) .get(),'),
        isTrue,
      );
      expect(
        body.contains('db.collection("employment_contracts") '
            '.where("toId", "==", toId) .limit(1) .get(),'),
        isTrue,
      );
    });

    test('slot guard는 slotId로 정확히 연결한다 (workDate 단독 사용 금지)', () {
      final body = _flat(_codeOf(_fnBody(fn, 'assertNoSlotRelations')));
      expect(
        body.contains('.where("toId", "==", toId) '
            '.where("businessId", "==", businessId) '
            '.where("slotId", "==", slotId) .limit(1) .get()'),
        isTrue,
        reason: 'slotId 기반 정확 매칭이 아니다',
      );
      // application 질의에 workDate를 섞지 않는다
      final appPart = body.substring(0, body.indexOf('employment_contracts'));
      expect(appPart.contains('workDate'), isFalse,
          reason: 'workDate로 질의하면 다른 슬롯 지원서까지 걸린다');
    });

    test('두 guard 모두 fail-closed다', () {
      for (final name in ['assertNoPostingRelations', 'assertNoSlotRelations']) {
        final body = _flat(_codeOf(_fnBody(fn, name)));
        expect(
          body.contains("return {blocked: true, reason: "
              "\"RELATION_CHECK_FAILED\"};"),
          isTrue,
          reason: '$name 의 catch가 관계 0으로 통과시킨다',
        );
        expect(body.contains('return {blocked: false'), isTrue);
        // catch에서 false를 반환하지 않는다
        final catchIdx = body.indexOf('} catch (e) {');
        expect(catchIdx, isNot(-1));
        expect(body.substring(catchIdx).contains('blocked: false'), isFalse);
      }
    });

    test('계약 스캔 한도 초과도 fail-closed', () {
      final body = _flat(_codeOf(_fnBody(fn, 'assertNoSlotRelations')));
      expect(body.contains('const CONTRACT_SCAN_LIMIT = 300;'), isTrue);
      expect(
        body.contains('if (contractSnap.size >= CONTRACT_SCAN_LIMIT) { '
            'return {blocked: true, reason: "CONTRACT_SCAN_TRUNCATED"}; }'),
        isTrue,
      );
    });

    test('슬롯 문서를 재조회하지 않고 호출자 것을 재사용한다', () {
      final body = _codeOf(_fnBody(fn, 'assertNoSlotRelations'));
      expect(body.contains('slotSnaps'), isTrue);
      expect(body.contains('collection("slots")'), isFalse,
          reason: 'guard가 슬롯을 다시 읽는다 (N+1)');
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 기존 status 기반 guard 제거
  // ═════════════════════════════════════════════════════════════
  group('이전 status 기반 guard 제거', () {
    test('ACTIVE/FULL 조건부 confirmed guard가 사라졌다', () {
      final body = _codeOf(_callableBody(fn, 'callableDeleteTO'));
      expect(
        body.contains('if (toStatus === "ACTIVE" || toStatus === "FULL") {'),
        isFalse,
        reason: 'lifecycle status 기반 예외가 남아 있다',
      );
      expect(
        body.contains('"확정된 근로자가 있는 공고는 삭제할 수 없습니다. '
            '먼저 계약 해지 처리 후 삭제하세요."'),
        isFalse,
        reason: '옛 메시지가 남아 있다',
      );
    });

    test('deleteTO가 새 relation guard를 쓴다', () {
      final body = _flat(_codeOf(_callableBody(fn, 'callableDeleteTO')));
      expect(
        body.contains('const toRelation = await assertNoPostingRelations('
            'toId, businessId); if (toRelation.blocked) { '
            'throw new HttpsError( "failed-precondition", '
            'postingRelationBlockMessage(toRelation.reason) ); }'),
        isTrue,
      );
    });

    test('deleteSlots가 새 relation guard를 쓴다 (이전엔 guard 자체가 없었다)', () {
      final body = _flat(_codeOf(_callableBody(fn, 'callableDeleteSlots')));
      expect(
        body.contains('const slotRelation = await assertNoSlotRelations( '
            'toId, toBusinessId, slotIds, slotSnaps ); '
            'if (slotRelation.blocked) { throw new HttpsError( '
            '"failed-precondition", '
            'slotRelationBlockMessage(slotRelation.reason) ); }'),
        isTrue,
      );
    });
  });

  // ═════════════════════════════════════════════════════════════
  // DELETE-RELATION-01 / 02 — 모든 status가 삭제를 막는다
  // ═════════════════════════════════════════════════════════════
  group('DELETE-RELATION-01 application 1건이 TO 삭제를 막는다', () {
    for (final s in _allStatuses) {
      test('$s 1건 → BLOCK', () {
        final r = postingGuard(applications: [_App(s)], contracts: []);
        expect(r.blocked, isTrue, reason: '$s 가 삭제를 통과시킨다');
        expect(r.reason, 'APPLICATION_EXISTS');
      });
    }

    test('코드에 존재하는 status가 모두 커버된다', () {
      // 새 status가 생겨도 guard는 문서 존재만 보므로 자동으로 안전하다
      final r = postingGuard(
        applications: [const _App('SOME_FUTURE_STATUS')],
        contracts: [],
      );
      expect(r.blocked, isTrue,
          reason: '알 수 없는 새 status가 guard를 통과한다');
    });
  });

  group('DELETE-RELATION-02 application 1건이 슬롯 삭제를 막는다', () {
    const slots = [_Slot('s1', '2026-09-20'), _Slot('s2', '2026-09-21')];
    for (final s in _allStatuses) {
      test('$s 1건 → BLOCK', () {
        final r = slotGuard(
          selectedSlotIds: ['s1'],
          slots: slots,
          applications: [_App(s, slotId: 's1')],
          contracts: [],
        );
        expect(r.blocked, isTrue);
        expect(r.reason, 'APPLICATION_EXISTS');
      });
    }

    test('다른 슬롯의 지원서는 선택 슬롯 삭제를 막지 않는다', () {
      final r = slotGuard(
        selectedSlotIds: ['s1'],
        slots: slots,
        applications: [const _App('CONFIRMED', slotId: 's2')],
        contracts: [],
      );
      expect(r.blocked, isFalse,
          reason: 'slotId 정확 매칭이 아니라 과잉 차단된다');
    });

    test('slotId 없는 legacy 지원서는 슬롯 매칭에서 제외된다', () {
      final r = slotGuard(
        selectedSlotIds: ['s1'],
        slots: slots,
        applications: [const _App('CONFIRMED')],
        contracts: [],
      );
      // 슬롯 단위로는 연결을 확정할 수 없다.
      // 단 TO 단위 guard가 이 지원서를 잡으므로 최종 안전성은 유지된다.
      expect(r.blocked, isFalse);
      expect(
        postingGuard(
          applications: [const _App('CONFIRMED')],
          contracts: [],
        ).blocked,
        isTrue,
        reason: 'TO guard도 못 잡으면 legacy 지원서가 완전히 무방비가 된다',
      );
    });
  });

  // ═════════════════════════════════════════════════════════════
  // DELETE-RELATION-03 / 04 — contract / attendance
  // ═════════════════════════════════════════════════════════════
  group('DELETE-RELATION-03 contract-only legacy', () {
    test('application 없이 계약만 있어도 TO 삭제 BLOCK', () {
      final r = postingGuard(
        applications: [],
        contracts: [const _Contract('2026-09-20')],
      );
      expect(r.blocked, isTrue);
      expect(r.reason, 'CONTRACT_EXISTS');
    });

    test('선택 날짜와 같은 날 계약이 있으면 슬롯 삭제 BLOCK', () {
      final r = slotGuard(
        selectedSlotIds: ['s1'],
        slots: const [_Slot('s1', '2026-09-20')],
        applications: [],
        contracts: [const _Contract('2026-09-20')],
      );
      expect(r.blocked, isTrue);
      expect(r.reason, 'CONTRACT_EXISTS');
    });

    test('다른 날짜 계약은 선택 날짜 삭제를 막지 않는다', () {
      final r = slotGuard(
        selectedSlotIds: ['s1'],
        slots: const [_Slot('s1', '2026-09-20'), _Slot('s2', '2026-09-21')],
        applications: [],
        contracts: [const _Contract('2026-09-21')],
      );
      expect(r.blocked, isFalse);
    });

    test('계약이 스캔 한도만큼 있으면 날짜 대조 없이 BLOCK', () {
      final r = slotGuard(
        selectedSlotIds: ['s1'],
        slots: const [_Slot('s1', '2026-09-20')],
        applications: [],
        contracts: [const _Contract('2099-01-01')],
        contractTotal: _contractScanLimit,
      );
      expect(r.blocked, isTrue);
      expect(r.reason, 'CONTRACT_SCAN_TRUNCATED');
    });
  });

  group('DELETE-RELATION-04 attendance 관계', () {
    test('attendance는 toId/slotId가 없어 직접 질의 대상이 아니다', () {
      // 서버 attendance 문서에는 applicationId/userId/businessId/workDate/workType만 있다.
      // 이 사실이 바뀌면 guard 설계도 다시 봐야 하므로 여기서 고정한다.
      final att = _src('lib/models/core/attendance_model.dart');
      expect(att.contains('final String toId'), isFalse,
          reason: 'attendance에 toId가 생겼다 — guard에 직접 질의를 추가해야 한다');
      expect(att.contains('final String slotId'), isFalse,
          reason: 'attendance에 slotId가 생겼다 — guard 재설계 필요');
      expect(att.contains('final String applicationId;'), isTrue);
    });

    test('attendance 문서 id가 applicationId에서 파생된다', () {
      // `${applicationId}_${yyyyMMdd}` — application 없이는 생성될 수 없다
      expect(
        code.contains(r'const docId = `${applicationId}_${dateStr}`;'),
        isTrue,
        reason: 'attendance id 파생 규칙이 바뀌면 전이적 보호가 깨진다',
      );
    });

    test('삭제 경로가 application을 물리 삭제하지 않는다 (전이 보호의 전제)', () {
      for (final name in ['callableDeleteTO', 'callableDeleteSlots']) {
        final body = _codeOf(_callableBody(fn, name));
        expect(body.contains('.delete(doc.ref)'), isFalse,
            reason: '$name 이 application 문서를 물리 삭제한다');
      }
      // 탈퇴 경로도 status 업데이트만 한다
      final acct = _codeOf(_callableBody(fn, 'callableDeleteAccountApplications'));
      expect(acct.contains('status: "CANCELED"'), isTrue);
    });

    test('attendance가 있으면 그 application도 반드시 있으므로 TO 삭제가 막힌다', () {
      // attendance 존재 ⇒ application 존재 (id 파생 + 물리삭제 없음)
      final r = postingGuard(
        applications: [const _App('CONFIRMED')],
        contracts: [],
      );
      expect(r.blocked, isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // DELETE-RELATION-05 — 부분 삭제 없음
  // ═════════════════════════════════════════════════════════════
  group('DELETE-RELATION-05 mixed selected slots', () {
    const slots = [
      _Slot('A', '2026-09-20'),
      _Slot('B', '2026-09-21'),
      _Slot('C', '2026-09-22'),
    ];

    test('B에만 REJECTED 1건이 있어도 A/B/C 요청 전체가 차단된다', () {
      final r = slotGuard(
        selectedSlotIds: ['A', 'B', 'C'],
        slots: slots,
        applications: [const _App('REJECTED', slotId: 'B')],
        contracts: [],
      );
      expect(r.blocked, isTrue, reason: '부분 삭제가 일어난다');
      expect(r.reason, 'APPLICATION_EXISTS');
    });

    test('차단은 slotIds 순서와 무관하다', () {
      for (final order in [
        ['A', 'B', 'C'],
        ['C', 'B', 'A'],
        ['B', 'A', 'C'],
      ]) {
        final r = slotGuard(
          selectedSlotIds: order,
          slots: slots,
          applications: [const _App('CANCELED', slotId: 'B')],
          contracts: [],
        );
        expect(r.blocked, isTrue, reason: '순서 $order 에서 통과됨');
      }
    });

    test('B를 빼면 A/C는 삭제 가능하다', () {
      final r = slotGuard(
        selectedSlotIds: ['A', 'C'],
        slots: slots,
        applications: [const _App('REJECTED', slotId: 'B')],
        contracts: [],
      );
      expect(r.blocked, isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // DELETE-RELATION-06 / 07 — 관계 0이면 기존 삭제 유지
  // ═════════════════════════════════════════════════════════════
  group('DELETE-RELATION-06·07 zero relation 삭제 보존', () {
    test('관계 0이면 TO 삭제가 통과한다', () {
      final r = postingGuard(applications: [], contracts: []);
      expect(r.blocked, isFalse);
    });

    test('관계 0이면 슬롯 삭제가 통과한다', () {
      final r = slotGuard(
        selectedSlotIds: ['s1'],
        slots: const [_Slot('s1', '2026-09-20')],
        applications: [],
        contracts: [],
      );
      expect(r.blocked, isFalse);
    });

    test('TO soft delete 계약이 그대로다', () {
      final body = _flat(_codeOf(_callableBody(fn, 'callableDeleteTO')));
      expect(
        body.contains('await db.collection("tos").doc(toId).update({ '
            'isDeleted: true, deletedAt: '
            'admin.firestore.FieldValue.serverTimestamp(), '
            'isPublished: false,'),
        isTrue,
        reason: 'soft delete 구현이 바뀌었다',
      );
      expect(
        body.contains('postingCapacityScopeKey: '
            'admin.firestore.FieldValue.delete(),'),
        isTrue,
      );
    });

    test('슬롯 물리 삭제 구현이 그대로다', () {
      final body = _flat(_codeOf(_callableBody(fn, 'callableDeleteSlots')));
      expect(
        body.contains('deleteBatch.delete(db.collection("tos").doc(toId)'
            '.collection("slots").doc(slotId));'),
        isTrue,
      );
    });
  });

  // ═════════════════════════════════════════════════════════════
  // DELETE-RELATION-08 / 09 — lifecycle status 무관
  // ═════════════════════════════════════════════════════════════
  group('DELETE-RELATION-08·09 status 예외 없음', () {
    test('DRAFT + INVITED → BLOCK', () {
      // DRAFT는 callableInviteWorker가 막지 않아 INVITED가 붙을 수 있다.
      // relation guard가 status와 무관하므로 자동으로 보호된다.
      final r = postingGuard(
        applications: [const _App('INVITED')],
        contracts: [],
      );
      expect(r.blocked, isTrue);
    });

    test('SCHEDULED + CONFIRMED → BLOCK', () {
      final r = postingGuard(
        applications: [const _App('CONFIRMED')],
        contracts: [],
      );
      expect(r.blocked, isTrue);
    });

    test('CLOSED + 과거 REJECTED → BLOCK', () {
      final r =
          postingGuard(applications: [const _App('REJECTED')], contracts: []);
      expect(r.blocked, isTrue);
    });

    test('EXPIRED + 과거 CONFIRMED → BLOCK', () {
      final r =
          postingGuard(applications: [const _App('CONFIRMED')], contracts: []);
      expect(r.blocked, isTrue);
    });

    test('guard 코드에 lifecycle status 분기가 없다', () {
      final body = _codeOf(_fnBody(fn, 'assertNoPostingRelations'));
      for (final s in ['DRAFT', 'SCHEDULED', 'ACTIVE', 'FULL', 'CLOSED',
        'EXPIRED']) {
        expect(body.contains('"$s"'), isFalse,
            reason: 'guard가 $s 를 특별 취급한다');
      }
    });
  });

  // ═════════════════════════════════════════════════════════════
  // DELETE-RELATION-10 — 차단 시 side effect 0
  // ═════════════════════════════════════════════════════════════
  group('DELETE-RELATION-10 차단 시 side effect 없음', () {
    test('deleteTO: guard가 모든 write 이전에 있다', () {
      final body = _codeOf(_callableBody(fn, 'callableDeleteTO'));
      final guardIdx = body.indexOf('assertNoPostingRelations(');
      expect(guardIdx, isNot(-1));
      for (final write in [
        'batch.update(',
        'db.collection("tos").doc(toId).update(',
        '.collection("notifications")',
        'AUTO_CANCELED',
        'revokeReason',
      ]) {
        final wIdx = body.indexOf(write);
        if (wIdx == -1) continue;
        expect(guardIdx < wIdx, isTrue,
            reason: 'guard보다 먼저 "$write" 가 실행된다');
      }
    });

    test('deleteSlots: guard가 모든 write 이전에 있다', () {
      final body = _codeOf(_callableBody(fn, 'callableDeleteSlots'));
      final guardIdx = body.indexOf('assertNoSlotRelations(');
      expect(guardIdx, isNot(-1));
      for (final write in [
        'cancelBatch.update(',
        'deleteBatch.delete(',
        'deleteBatch.update(',
        '.collection("notifications")',
        'status: "REJECTED"',
        'revokeReason',
      ]) {
        final wIdx = body.indexOf(write);
        if (wIdx == -1) continue;
        expect(guardIdx < wIdx, isTrue,
            reason: 'guard보다 먼저 "$write" 가 실행된다');
      }
    });

    test('guard 이전 구간에 commit이 없다', () {
      for (final name in ['callableDeleteTO', 'callableDeleteSlots']) {
        final body = _codeOf(_callableBody(fn, name));
        final guardIdx = body.indexOf(
            name == 'callableDeleteTO'
                ? 'assertNoPostingRelations('
                : 'assertNoSlotRelations(');
        final before = body.substring(0, guardIdx);
        expect(before.contains('.commit()'), isFalse,
            reason: '$name 이 guard 이전에 batch를 commit한다');
      }
    });
  });

  // ═════════════════════════════════════════════════════════════
  // DELETE-RELATION-11 — TO guard 우회 불가
  // ═════════════════════════════════════════════════════════════
  group('DELETE-RELATION-11 guard 우회', () {
    const slots = [_Slot('s1', '2026-09-20'), _Slot('s2', '2026-09-21')];

    test('확정자 있는 공고: 전 슬롯 삭제 chain이 첫 단계에서 막힌다', () {
      final r = deleteAllChain(
        selectedSlotIds: ['s1', 's2'],
        slots: slots,
        applications: [const _App('CONFIRMED', slotId: 's1')],
        contracts: [],
      );
      expect(r.slotBlocked, isTrue);
      expect(r.toReached, isFalse, reason: 'deleteTO에 도달해 우회가 성립한다');
    });

    test('슬롯을 통과해도 TO guard가 동일 관계로 막는다', () {
      // slotId 없는 legacy 지원서 — 슬롯 매칭은 실패하지만 TO 매칭은 성공
      final r = deleteAllChain(
        selectedSlotIds: ['s1', 's2'],
        slots: slots,
        applications: [const _App('CONFIRMED')],
        contracts: [],
      );
      expect(r.slotBlocked, isFalse);
      expect(r.toReached, isTrue);
      expect(r.toBlocked, isTrue, reason: '2단계 방어가 뚫린다');
    });

    test('관계 0이면 chain 전체가 통과한다', () {
      final r = deleteAllChain(
        selectedSlotIds: ['s1', 's2'],
        slots: slots,
        applications: [],
        contracts: [],
      );
      expect(r.slotBlocked, isFalse);
      expect(r.toBlocked, isFalse);
    });

    test('어느 status로든 chain 우회가 불가능하다', () {
      for (final s in _allStatuses) {
        final r = deleteAllChain(
          selectedSlotIds: ['s1', 's2'],
          slots: slots,
          applications: [_App(s, slotId: 's1')],
          contracts: [],
        );
        expect(r.slotBlocked || r.toBlocked, isTrue,
            reason: '$s 로 삭제가 완주된다');
      }
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 메시지
  // ═════════════════════════════════════════════════════════════
  group('차단 메시지', () {
    test('TO는 공고 종료를 안내한다', () {
      final body = _codeOf(_fnBody(fn, 'postingRelationBlockMessage'));
      expect(body.contains('"이 공고에는 지원·초대·근무 기록이 있어 삭제할 수 없습니다. " +'),
          isTrue);
      expect(body.contains('"모집을 중단하려면 공고 종료를 이용해주세요."'), isTrue);
    });

    test('슬롯은 날짜 종료를 안내한다', () {
      final body = _codeOf(_fnBody(fn, 'slotRelationBlockMessage'));
      expect(
          body.contains('"선택한 날짜에 지원 또는 근무 기록이 있어 삭제할 수 없습니다. " +'),
          isTrue);
      expect(body.contains('"해당 날짜의 모집을 중단하려면 날짜 종료를 이용해주세요."'), isTrue);
    });

    test('확인 실패는 재시도를 안내한다 (관계 있음과 구분)', () {
      for (final name in [
        'postingRelationBlockMessage',
        'slotRelationBlockMessage'
      ]) {
        final body = _flat(_codeOf(_fnBody(fn, name)));
        expect(
          body.contains('if (reason === "RELATION_CHECK_FAILED") { return '
              '"지원·근무 기록을 확인하지 못해 삭제할 수 없습니다. 잠시 후 다시 시도해주세요."; }'),
          isTrue,
        );
      }
    });
  });

  // ═════════════════════════════════════════════════════════════
  // scope guard
  // ═════════════════════════════════════════════════════════════
  group('scope guard', () {
    test('permission 검증 무변경', () {
      expect(
        code.contains('if (!memberPerms.canManageTo) throw new HttpsError('
            '"permission-denied", "TO 관리 권한이 없습니다.");'),
        isTrue,
      );
      expect(
        code.contains('if (!memberPermsForDeleteSlots.canManageTo) '
            'throw new HttpsError("permission-denied", "TO 관리 권한이 없습니다.");'),
        isTrue,
      );
    });

    test('close semantics 무변경', () {
      final close = _codeOf(_callableBody(fn, 'callableCloseSlots'));
      expect(
        close.contains('{isManualClosed: true, status: "closed", '
            'closedAt: now, closedBy: callerUid}'),
        isTrue,
      );
      // 마감은 여전히 PENDING만 거절한다
      expect(close.contains('.where("status", "==", "PENDING")'), isTrue);
      expect(close.contains('assertNoSlotRelations'), isFalse,
          reason: '마감에까지 relation guard가 붙었다');
    });

    test('invite 정책 무변경 (DRAFT/SCHEDULED gap은 별도 backlog)', () {
      final inv = _codeOf(_callableBody(fn, 'callableInviteWorker'));
      expect(
        inv.contains('const closedStatuses = ["CLOSED", "POSTING_EXPIRED", '
            '"DELETED"];'),
        isTrue,
        reason: 'invite guard를 이번 Phase에서 건드렸다',
      );
      expect(inv.contains('isPublished'), isFalse,
          reason: 'DRAFT/SCHEDULED invite 정책을 수정했다',
      );
    });

    // [POSTING-V2-01C.2] 이 테스트는 원래 '클라이언트 삭제 UI 무변경'을 고정했다.
    // 01C.2에서 클라이언트를 DRAFT-only로 좁혔으므로, 이제 고정해야 할 것은
    // "클라이언트가 좁아져도 서버 guard는 여전히 독립적인 최종 권위"라는 관계다.
    // 구버전 클라이언트와 직접 callable 호출이 서버만으로 보호되어야 한다.
    test('서버 guard가 클라이언트 UI 정책에 의존하지 않는다', () {
      for (final name in ['assertNoPostingRelations', 'assertNoSlotRelations']) {
        final body = _codeOf(_fnBody(fn, name));
        // 서버는 DRAFT 여부를 보지 않는다 — 관계만 본다
        expect(body.contains('"DRAFT"'), isFalse,
            reason: '$name 이 클라이언트의 DRAFT-only 정책을 서버에 복제한다');
        expect(body.contains('status'), isFalse,
            reason: '$name 이 lifecycle status에 결합됐다');
      }
      // deleteTO/deleteSlots도 status 기반 예외를 두지 않는다
      final toBody = _codeOf(_callableBody(fn, 'callableDeleteTO'));
      expect(toBody.contains('toStatus === "ACTIVE"'), isFalse);
    });

    test('클라이언트는 서버보다 좁게 노출한다 (의도된 비대칭)', () {
      final card = _codeOf(_src(_cardPath));
      // 01C.2: DRAFT에서만 삭제 메뉴 노출
      expect(card.contains('if (canDelete && isDraft)'), isTrue,
          reason: '클라이언트 DRAFT-only gate가 사라졌다');
      // 서버는 relation-zero면 어떤 status든 허용하므로,
      // 이 비대칭은 UI 정책이지 서버 안전성의 전제가 아니다.
      expect(
        _codeOf(_fnBody(fn, 'assertNoPostingRelations')).contains('isDraft'),
        isFalse,
      );
    });

    test('새 근무 취소 기능을 만들지 않았다', () {
      expect(code.contains('callableCancelConfirmedApplication'), isTrue,
          reason: '기존 개별 취소 경로가 사라졌다');
      expect(code.contains('callableBatchCancelConfirmed'), isFalse);
      expect(code.contains('callableCancelWork'), isFalse);
    });

    test('guard는 읽기 전용이다 — legacy 데이터를 고치지 않는다', () {
      for (final name in ['assertNoPostingRelations', 'assertNoSlotRelations']) {
        final body = _codeOf(_fnBody(fn, name));
        // 로컬 Set.add 등은 제외하고 Firestore write API만 본다
        for (final write in [
          '.set(',
          '.update(',
          '.delete(',
          '.commit(',
          'db.batch(',
          'runTransaction',
          'FieldValue',
        ]) {
          expect(body.contains(write), isFalse,
              reason: '$name 이 "$write" 로 데이터를 건드린다');
        }
      }
    });

    test('POSTING-V2-01A 초대 정합성 회귀 없음', () {
      final dialog = _flat(_codeOf(_src(_dialogPath)));
      expect(
        dialog.contains("'selectedWorkType': generalWd!.workType, "
            "'workDetailStartTime': generalWd.startTime, "
            "'workDetailEndTime': generalWd.endTime,"),
        isTrue,
      );
    });

    test('POSTING-V2-01B ERROR != ZERO 회귀 없음', () {
      final ctrl = _codeOf(_src(_ctrlPath));
      expect(ctrl.contains('_loadError = e;'), isTrue);
      expect(ctrl.contains('Object? get loadError => _loadError;'), isTrue);
      expect(ctrl.contains('_groupDetailErrorIds.add(group.id);'), isTrue);
    });
  });
}
