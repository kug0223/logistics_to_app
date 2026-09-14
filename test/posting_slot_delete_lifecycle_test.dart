// [POSTING-V2-03L.1] 날짜 삭제 → 공고 lifecycle 판정은 서버가 한다
//
// 03L READ에서 확인된 것:
//   · 클라이언트가 `deleteSlots.length >= totalSlotCount`로 "전부 삭제"를
//     추론한 뒤 callableDeleteTO를 따로 불렀다.
//   · 그 boolean은 확인 다이얼로그를 사이에 두고 낡을 수 있었고,
//     callableDeleteTO는 남은 날짜를 확인하지 않았다.
//   · 서버의 `toData.totalSlots - slotIds.length`도 denormalized 카운터라
//     동시 삭제 두 건이 같은 값을 읽으면 슬롯 0개 공고가 남았다.
//
// 새 계약:
//   client intent = "이 slotIds를 지워라" 뿐.
//   server가 삭제 시점의 canonical slot 문서로 남은 날짜를 세고,
//   DRAFT에서 0이면 같은 mutation 안에서 공고를 soft-delete한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _fnsPath = 'functions/src/index.ts';
const _cardPath = 'lib/widgets/admin/cards/admin_to_group_card.dart';
const _toFsPath = 'lib/services/firestore/to_firestore.dart';

String _src(String p) {
  final f = File(p);
  expect(f.existsSync(), true, reason: '$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

String _callableOf(String source, String name) {
  final start = source.indexOf('export const $name = onCall(');
  if (start == -1) throw StateError('$name 을 찾지 못함');
  var depth = 0;
  for (var i = source.indexOf('(', start); i < source.length; i++) {
    if (source[i] == '(') depth++;
    if (source[i] == ')') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  throw StateError('$name 본문의 끝을 찾지 못함');
}

String _caseBlock(String source, String head) {
  final start = source.indexOf(head);
  if (start == -1) throw StateError('$head 를 찾지 못함');
  final end = source.indexOf('\n        break;', start);
  return source.substring(start, end == -1 ? source.length : end);
}

// ═══════════════════════════════════════════════════════════════
// callableDeleteSlots lifecycle 판정 replica
// ═══════════════════════════════════════════════════════════════

const _closableStatuses = ['ACTIVE', 'FULL', 'EXPIRED', 'SCHEDULED'];
const _relationMessage =
    '이 공고에는 지원·초대·근무 기록이 있어 삭제할 수 없습니다. 모집을 중단하려면 공고 종료를 이용해주세요.';

/// mutation 전체가 거부됐다 — 트랜잭션이 롤백되어 아무것도 바뀌지 않는다.
class DeleteRejected implements Exception {
  final String message;
  const DeleteRejected(this.message);
}

class DeleteOutcome {
  final int deletedSlotCount;
  final int remainingSlotCount;
  final bool postingDeleted;
  final bool postingClosed;

  const DeleteOutcome({
    this.deletedSlotCount = 0,
    this.remainingSlotCount = 0,
    this.postingDeleted = false,
    this.postingClosed = false,
  });
}

/// [canonicalSlotIds]는 **트랜잭션이 읽은 시점**의 실제 slot 문서다.
/// 클라이언트가 무엇을 전부라고 믿었는지는 판정에 들어오지 않는다.
///
/// [POSTING-V2-03L.1] 마지막 날짜 삭제는 공고 삭제와 한 덩어리다.
/// 공고 관계가 막으면 [DeleteRejected] — 날짜 삭제도 되돌아간다.
DeleteOutcome deleteSlots({
  required List<String> requestedSlotIds,
  required List<String> canonicalSlotIds,
  String status = 'DRAFT',
  bool alreadyDeleted = false,
  bool slotRelationBlocked = false,
  bool postingRelationBlocked = false,
}) {
  final unique = {...requestedSlotIds};
  if (slotRelationBlocked) {
    throw const DeleteRejected('이 공고에는 지원·초대·근무 기록이 있어 삭제할 수 없습니다.');
  }

  final remaining =
      canonicalSlotIds.where((id) => !unique.contains(id)).length;
  final deleted = canonicalSlotIds.where(unique.contains).length;

  var postingDeleted = false;
  var postingClosed = false;
  if (remaining == 0 && !alreadyDeleted) {
    if (status == 'DRAFT') {
      // predicate가 write보다 앞이다 — 여기서 던지면 삭제가 커밋되지 않는다.
      if (postingRelationBlocked) throw const DeleteRejected(_relationMessage);
      postingDeleted = true;
    } else if (_closableStatuses.contains(status)) {
      postingClosed = true;
    }
  }
  return DeleteOutcome(
    deletedSlotCount: deleted,
    remainingSlotCount: remaining,
    postingDeleted: postingDeleted,
    postingClosed: postingClosed,
  );
}

/// 카드가 서버 결과로 고르는 토스트. 예외는 기존 에러 경로가 처리한다.
String toastFor(DeleteOutcome o) {
  if (o.postingDeleted) return 'SUCCESS:공고가 삭제되었습니다';
  return 'SUCCESS:${o.deletedSlotCount}개 날짜가 삭제되었습니다';
}

void main() {
  late final String deleteSlotsFn = _callableOf(_src(_fnsPath), 'callableDeleteSlots');
  late final String cardBlock =
      _flat(_codeOf(_caseBlock(_src(_cardPath), "case 'batchDelete':")));

  // ── §22 정상 ──────────────────────────────────────────────────
  group('SLOTDEL-01 부분 삭제와 마지막 삭제', () {
    test('01-a A,B,C 중 A만 삭제 → 공고 유지', () {
      final r = deleteSlots(
        requestedSlotIds: ['A'],
        canonicalSlotIds: ['A', 'B', 'C'],
      );
      expect(r.deletedSlotCount, 1);
      expect(r.remainingSlotCount, 2);
      expect(r.postingDeleted, false);
      expect(r.postingClosed, false);
    });

    test('01-b 마지막 날짜 삭제 → DRAFT 공고 soft-delete', () {
      final r = deleteSlots(
        requestedSlotIds: ['A'],
        canonicalSlotIds: ['A'],
      );
      expect(r.remainingSlotCount, 0);
      expect(r.postingDeleted, true);
    });

    test('01-c 공개 공고는 삭제가 아니라 마감으로 전이된다 (§8)', () {
      for (final st in _closableStatuses) {
        final r = deleteSlots(
          requestedSlotIds: ['A'],
          canonicalSlotIds: ['A'],
          status: st,
        );
        expect(r.postingDeleted, false, reason: st);
        expect(r.postingClosed, true, reason: st);
      }
    });

    test('01-d 이미 삭제된 공고는 다시 건드리지 않는다', () {
      final r = deleteSlots(
        requestedSlotIds: ['A'],
        canonicalSlotIds: ['A'],
        alreadyDeleted: true,
      );
      expect(r.postingDeleted, false);
      expect(r.postingClosed, false);
    });
  });

  // ── §23 race ──────────────────────────────────────────────────
  group('SLOTDEL-02 동시 변경', () {
    test('02-a 삭제 도중 날짜가 추가되면 공고를 지우지 않는다 (§6)', () {
      // 클라이언트는 A,B가 전부라고 믿고 둘 다 선택했지만
      // 트랜잭션이 읽은 시점에는 C가 생겨 있다.
      final r = deleteSlots(
        requestedSlotIds: ['A', 'B'],
        canonicalSlotIds: ['A', 'B', 'C'],
      );
      expect(r.remainingSlotCount, 1);
      expect(r.postingDeleted, false,
          reason: '남은 날짜가 있는데 공고가 사라지면 그 날짜는 고아가 된다');
    });

    test('02-b 서로 다른 mutation이 나눠 지워도 orphan이 남지 않는다 (§7)', () {
      // T1: A 삭제 — 이 시점 canonical = [A, B]
      final t1 = deleteSlots(
        requestedSlotIds: ['A'],
        canonicalSlotIds: ['A', 'B'],
      );
      expect(t1.postingDeleted, false);
      expect(t1.remainingSlotCount, 1);
      // T2: B 삭제 — 이 시점 canonical = [B]
      final t2 = deleteSlots(
        requestedSlotIds: ['B'],
        canonicalSlotIds: ['B'],
      );
      expect(t2.remainingSlotCount, 0);
      expect(t2.postingDeleted, true,
          reason: '둘 다 stale totalSlots를 보면 빈 공고가 남는다');
    });

    test('02-c stale client — 전부라고 믿어도 canonical이 이긴다 (§23)', () {
      final r = deleteSlots(
        requestedSlotIds: ['A', 'B', 'C'], // 클라이언트가 본 전부
        canonicalSlotIds: ['A', 'B', 'C', 'D'],
      );
      expect(r.postingDeleted, false);
      expect(r.remainingSlotCount, 1);
    });
  });

  // ── §20 identity ─────────────────────────────────────────────
  group('SLOTDEL-03 중복·유령 slotId', () {
    test('03-a 중복 slotId가 개수를 부풀리지 않는다', () {
      final r = deleteSlots(
        requestedSlotIds: ['A', 'A', 'B'],
        canonicalSlotIds: ['A', 'B'],
      );
      expect(r.deletedSlotCount, 2);
      expect(r.remainingSlotCount, 0);
      expect(r.postingDeleted, true);
    });

    test('03-b 이미 없는 slotId는 삭제 개수에 들어가지 않는다', () {
      final r = deleteSlots(
        requestedSlotIds: ['A', 'GHOST'],
        canonicalSlotIds: ['A'],
      );
      expect(r.deletedSlotCount, 1, reason: '없는 날짜를 지웠다고 말하면 안 된다');
      expect(r.remainingSlotCount, 0);
      expect(r.postingDeleted, true);
    });
  });

  // ── §12 relation — 마지막 날짜는 공고 삭제와 한 덩어리다 ─────────
  group('SLOTDEL-04 관계 guard 우회 없음', () {
    test('04-a 선택 슬롯에 관계가 있으면 요청 전체가 막힌다 (§7)', () {
      expect(
          () => deleteSlots(
                requestedSlotIds: ['A'],
                canonicalSlotIds: ['A', 'B'],
                slotRelationBlocked: true,
              ),
          throwsA(isA<DeleteRejected>()),
          reason: '부분 삭제 없음');
    });

    test('04-b 마지막 날짜 + 공고 관계 → 전체 rollback (§1 CASE B)', () {
      // 현재 슬롯은 B 하나. 과거 지운 A의 지원 이력이 남아 있어
      // 공고 관계 guard가 막는다. B도 지워지면 안 된다.
      expect(
          () => deleteSlots(
                requestedSlotIds: ['B'],
                canonicalSlotIds: ['B'],
                postingRelationBlocked: true,
              ),
          throwsA(isA<DeleteRejected>()));
    });

    test('04-c 거부 사유는 기존 canonical 문구다 (§2)', () {
      try {
        deleteSlots(
          requestedSlotIds: ['B'],
          canonicalSlotIds: ['B'],
          postingRelationBlocked: true,
        );
        fail('rollback되지 않았다');
      } on DeleteRejected catch (e) {
        expect(e.message, _relationMessage,
            reason: '새 error taxonomy를 만들지 않는다');
      }
    });

    test('04-d 부분 삭제는 공고 관계에 영향받지 않는다 (§5)', () {
      // A,B,C 중 A만 삭제 — 과거 슬롯에 historical relation이 있어도
      // 공고 삭제 guard를 부분 수정에 확대 적용하지 않는다.
      final r = deleteSlots(
        requestedSlotIds: ['A'],
        canonicalSlotIds: ['A', 'B', 'C'],
        postingRelationBlocked: true,
      );
      expect(r.deletedSlotCount, 1);
      expect(r.remainingSlotCount, 2);
      expect(r.postingDeleted, false);
    });

    test('04-e 관계가 없으면 마지막 날짜와 공고가 함께 사라진다 (§8)', () {
      final r = deleteSlots(
        requestedSlotIds: ['A'],
        canonicalSlotIds: ['A'],
      );
      expect(r.remainingSlotCount, 0);
      expect(r.postingDeleted, true);
    });
  });

  // ── §11 success invariant ────────────────────────────────────
  group('SLOTDEL-05 결과 표시와 불변식', () {
    test('05-a 부분 삭제 → 날짜 삭제 성공만', () {
      final t = toastFor(deleteSlots(
        requestedSlotIds: ['A'],
        canonicalSlotIds: ['A', 'B', 'C'],
      ));
      expect(t, 'SUCCESS:1개 날짜가 삭제되었습니다');
    });

    test('05-b 공고 삭제 → 공고 삭제 성공', () {
      final t = toastFor(deleteSlots(
        requestedSlotIds: ['A'],
        canonicalSlotIds: ['A'],
      ));
      expect(t, 'SUCCESS:공고가 삭제되었습니다');
    });

    test('05-c DRAFT 성공 결과에 slot 0 + 미삭제 공고가 없다 (§11)', () {
      // 가능한 모든 조합을 돌려 불변식을 확인한다.
      const universe = ['A', 'B', 'C'];
      for (var mask = 1; mask < 8; mask++) {
        for (var canonMask = 1; canonMask < 8; canonMask++) {
          final requested = [
            for (var i = 0; i < 3; i++)
              if (mask & (1 << i) != 0) universe[i],
          ];
          final canonical = [
            for (var i = 0; i < 3; i++)
              if (canonMask & (1 << i) != 0) universe[i],
          ];
          for (final blocked in [false, true]) {
            DeleteOutcome? r;
            try {
              r = deleteSlots(
                requestedSlotIds: requested,
                canonicalSlotIds: canonical,
                postingRelationBlocked: blocked,
              );
            } on DeleteRejected {
              continue; // rollback — 성공 결과가 아니다
            }
            expect(r.remainingSlotCount == 0 && !r.postingDeleted, false,
                reason: 'requested=$requested canonical=$canonical '
                    'blocked=$blocked → 빈 공고가 남는다');
          }
        }
      }
    });

    test('05-d 이미 삭제된 공고는 예외 없이 넘어간다', () {
      final r = deleteSlots(
        requestedSlotIds: ['A'],
        canonicalSlotIds: ['A'],
        alreadyDeleted: true,
      );
      expect(r.postingDeleted, false);
      expect(r.remainingSlotCount, 0,
          reason: '이미 삭제된 공고는 05-c 불변식의 대상이 아니다');
    });
  });

  // ── 서버 배선 ─────────────────────────────────────────────────
  group('SLOTDEL-06 서버가 authority다', () {
    test('06-a 삭제·카운터·lifecycle이 한 트랜잭션 안이다 (§5, §11)', () {
      final body = _flat(_codeOf(deleteSlotsFn));
      expect(body.contains('await db.runTransaction(async (txDel) => {'), true);
      for (final marker in [
        'const freshToSnap = await txDel.get(toRefForDelete);',
        'const allSlotSnap = await txDel.get(slotsRefForDelete);',
        'txDel.delete(slotsRefForDelete.doc(slotId));',
        'txDel.update(toRefForDelete, toUpdate);',
      ]) {
        expect(body.contains(marker), true, reason: '$marker 가 없다');
      }
    });

    test('06-b toRef를 읽어 날짜 추가와 충돌시킨다 (§5, §6)', () {
      final body = _flat(_codeOf(deleteSlotsFn));
      final readIdx = body.indexOf('await txDel.get(toRefForDelete)');
      final writeIdx = body.indexOf('txDel.update(toRefForDelete');
      expect(readIdx, greaterThan(-1));
      expect(writeIdx, greaterThan(readIdx), reason: 'read-before-write');
      // 날짜 생성이 같은 문서를 쓴다 — 그래서 충돌·재시도가 성립한다
      final fns = _src(_fnsPath);
      expect(
          fns.contains('totalSlots: admin.firestore.FieldValue.increment(totalNewSlots),'),
          true);
    });

    test('06-c 재시도마다 판정을 처음부터 다시 한다 (§5)', () {
      final body = _flat(_codeOf(deleteSlotsFn));
      expect(
          body.contains('remainingSlotCount = 0; deletedSlotCount = 0; '
              'postingDeleted = false; postingClosed = false;'),
          true,
          reason: '이전 시도의 판정이 남으면 stale 결과로 커밋된다');
    });

    test('06-d totalSlots를 canonical 결과로 맞춘다 (§12)', () {
      final body = _flat(_codeOf(deleteSlotsFn));
      expect(body.contains('totalSlots: remainingSlotCount,'), true);
      expect(
          body.contains('totalSlots: admin.firestore.FieldValue.increment(-slotIds.length)'),
          false,
          reason: '동시 삭제에서 어긋나는 increment로 되돌아가면 안 된다');
    });

    test('06-e 공고 관계 guard를 재사용하고, 막히면 throw한다 (§2, §3)', () {
      final body = _flat(_codeOf(deleteSlotsFn));
      expect(
          body.contains('const postingRelation = '
              'await assertNoPostingRelations(toId, toBusinessId);'),
          true);
      expect(
          body.contains('if (postingRelation.blocked) { '
              'throw new HttpsError( "failed-precondition", '
              'postingRelationBlockMessage(postingRelation.reason) ); }'),
          true,
          reason: '기존 canonical error contract를 그대로 surface한다');
    });

    test('06-f throw가 모든 write보다 앞이다 — rollback 보장 (§3, §4)', () {
      final body = _flat(_codeOf(deleteSlotsFn));
      final guardIdx = body.indexOf('await assertNoPostingRelations(toId, toBusinessId)');
      final deleteIdx = body.indexOf('txDel.delete(slotsRefForDelete.doc(slotId))');
      final updateIdx = body.indexOf('txDel.update(toRefForDelete, toUpdate)');
      expect(guardIdx, greaterThan(-1));
      expect(deleteIdx, greaterThan(guardIdx),
          reason: '관계 실패 뒤에 slot delete가 커밋되는 경로가 있으면 안 된다');
      expect(updateIdx, greaterThan(guardIdx));
    });

    test('06-g 성공 결과에 blocked 상태가 없다 (§2, §11)', () {
      final body = _flat(_codeOf(deleteSlotsFn));
      expect(body.contains('postingDeleteBlockedReason'), false,
          reason: '완료되지 않은 action을 success로 반환하지 않는다');
    });

    test('06-h DRAFT만 삭제하고 나머지는 마감이다 (§8)', () {
      final body = _flat(_codeOf(deleteSlotsFn));
      expect(body.contains('if (freshStatus === "DRAFT") {'), true);
      expect(body.contains('toUpdate.isDeleted = true;'), true);
      expect(body.contains('closableStatuses.includes(freshStatus ?? "")'), true);
      expect(body.contains('toUpdate.closedReason = "ALL_SLOTS_DELETED";'), true);
    });

    test('06-i 결과 계약을 반환한다 (§11)', () {
      final body = _flat(_codeOf(deleteSlotsFn));
      for (final k in [
        'deletedSlotCount,',
        'remainingSlotCount,',
        'postingDeleted,',
        'postingClosed,',
      ]) {
        expect(body.contains(k), true, reason: '$k 가 결과에 없다');
      }
    });

    test('06-j 중복 slotId를 입구에서 제거한다', () {
      final body = _flat(_codeOf(deleteSlotsFn));
      expect(body.contains('const uniqueSlotIds = [...new Set(slotIds)];'), true);
      expect(body.contains('const uniqueSlotIdSet = new Set(uniqueSlotIds);'), true);
      // 이후 로직은 raw slotIds를 쓰지 않는다
      expect(body.contains('slotIds.map((id) =>'), false);
      expect(body.contains('for (const slotId of slotIds)'), false);
    });
  });

  // ── 클라이언트 ────────────────────────────────────────────────
  group('SLOTDEL-07 클라이언트는 추론하지 않는다', () {
    test('07-a deletesAll 판정과 두 번째 mutation이 없다 (§1, §11)', () {
      expect(cardBlock.contains('deletesAll'), false);
      expect(cardBlock.contains('totalSlotCount'), false);
      expect(cardBlock.contains('deleteTO('), false);
    });

    test('07-b 서버 결과를 그대로 소비한다 (§11)', () {
      expect(cardBlock.contains("result['postingDeleted'] == true"), true);
      expect(cardBlock.contains("result['deletedSlotCount'] as num?"), true);
    });

    // [POSTING-V2-03L.1] 관계 거부는 예외로 온다 — 기존 catch가 서버 문구를
    //   그대로 띄우고 onChanged를 부르지 않는다. 성공 토스트는 없다.
    test('07-f 관계 거부를 성공 분기에서 다루지 않는다 (§10)', () {
      expect(cardBlock.contains('postingDeleteBlockedReason'), false);
      expect(cardBlock.contains('showWarning'), false);
      final catchIdx = cardBlock.indexOf('} catch (e) {');
      expect(catchIdx, greaterThan(-1));
      expect(cardBlock.substring(catchIdx).contains('_cfErrorMessage(e'), true,
          reason: '서버 canonical 문구를 그대로 표면화한다');
      expect(cardBlock.substring(catchIdx).contains('showSuccess'), false);
    });

    test('07-c 서비스가 결과를 돌려준다 (§3)', () {
      final code = _codeOf(_src(_toFsPath));
      expect(
          code.contains('Future<Map<String, dynamic>> batchDeleteSlots('), true);
      expect(code.contains('return Map<String, dynamic>.from(result.data);'), true);
    });

    test('07-d 확인 문구가 결과를 단정하지 않는다 (§15)', () {
      expect(cardBlock.contains('삭제 후 남은 날짜가 없으면 미공개 공고도 함께 삭제됩니다.'), true);
      expect(cardBlock.contains('모든 날짜를 삭제하면'), false,
          reason: '동시에 날짜가 추가되면 거짓말이 된다');
    });

    // [POSTING-V2-02B.2] DRAFT 삭제는 Home truth를 바꾸지 않는다 —
    //   미공개 공고에는 확정 근무자가 없다. 종료·재오픈이 신호를 보내는 것은
    //   그쪽이 공개 공고를 다루기 때문이다.
    test('07-e Workforce 신호를 보내지 않는다 (02B.2 경계 유지)', () {
      expect(cardBlock.contains('notifyDataChanged'), false);
    });
  });
}
