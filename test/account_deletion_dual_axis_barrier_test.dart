// [R7-P4.4E.11C.0C.0a.4.2] tombstone 을 확인했다 ≠ 그 뒤 create 가 막힌다
//
// .0a.4.1 은 기존 행의 cleanup key 를 불변으로 만들었다. 그러나 **새 행**은
// 여전히 만들어질 수 있었다. 그리고 두 가지가 빠져 있었다.
//
//   1) 축이 둘이다. 한 문서가 두 사람을 가리킨다 —
//      member_invitations 의 `invitedBy`, idCardAccessRequests 의
//      `requesterId`, monthly_reviews 의 `reviewerId` 는 모두 탈퇴 cleanup
//      대상인데 .0a.4 는 받는 쪽만 막았다.
//
//   2) 서버는 Rules 를 우회한다. 그리고
//        await tombstone.get()   →   await ref.create()
//      는 race closure 가 아니다. 그 사이에 freeze 가 commit 되면
//      "barrier 가 먼저 섰는데 그 뒤의 create 가 성공"하는 창이 열린다.
//
// 그래서 서버 writer 는 barrier read 와 create 를 **같은 transaction** 에
// 넣는다. transaction 은 읽은 문서를 read set 에 넣으므로, freeze 가 그
// 문서를 쓰면 ABORTED 로 재시도되고 재시도에서는 barrier 를 본다.
//
// 동작 검증은 rules 에뮬레이터가 한다
// (rules-test/src/rules/deletion_dual_axis_barrier.test.ts).
// 이 파일은 축 목록과 **서버 원자성**을 고정한다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('소스를 찾지 못했다: $p');
  return f.readAsStringSync();
}

String _codeOf(String src) => src
    .split(RegExp(r'\r?\n'))
    .where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
    })
    .join('\n');

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

int _at(String s, String needle) {
  final i = s.indexOf(needle);
  if (i < 0) throw StateError('경계를 찾지 못함: $needle');
  return i;
}

String _between(String s, String from, String to) {
  final a = _at(s, from);
  final b = s.indexOf(to, a);
  if (b < 0) throw StateError('끝 경계를 찾지 못함: $to');
  return s.substring(a, b);
}

int _count(String s, String needle) {
  var n = 0;
  var i = 0;
  while (true) {
    final k = s.indexOf(needle, i);
    if (k < 0) return n;
    n++;
    i = k + needle.length;
  }
}

String _fn(String raw, String name) {
  final a = raw.indexOf('export const $name');
  if (a < 0) throw StateError('$name 을 찾지 못함');
  final rel = raw.substring(a).indexOf('\n);');
  if (rel < 0) throw StateError('$name 의 끝을 찾지 못함');
  return _codeOf(raw.substring(a, a + rel));
}

String _helper(String raw, String name) {
  final a = raw.indexOf('function $name(');
  if (a < 0) throw StateError('$name 을 찾지 못함');
  final rel = raw.substring(a).indexOf('\n}');
  if (rel < 0) throw StateError('$name 의 끝을 찾지 못함');
  return _codeOf(raw.substring(a, a + rel));
}

/// 앵커를 **포함하는** `runTransaction` 블록을 떼어낸다.
///
///   앵커 뒤에서 transaction 을 찾으면 안 된다 — 앵커가 이미 transaction
///   안에 있으므로 그 뒤의 `runTransaction` 은 **다른** transaction 이거나
///   없다. 그래서 앵커 앞에서 가장 가까운 transaction 시작을 찾는다.
String _txBlock(String src, String anchor) {
  final a = _at(src, anchor);
  final t = src.lastIndexOf('runTransaction(async (tx) => {', a);
  if (t < 0) throw StateError('앵커를 감싸는 transaction 이 없다: $anchor');
  final end = src.indexOf('});', a);
  if (end < 0) throw StateError('transaction 끝을 찾지 못함: $anchor');
  return src.substring(t, end);
}

/// `match /x/{y} {` 블록 전체 — 다음 `match /` 직전까지.
///
///   고정폭 창(`substring(i, i + 900)`)을 쓰지 않는다. 주석이 길어지면
///   찾으려는 `allow` 선언이 창 밖으로 밀린다.
String _matchBlock(String rules, String matchLine) {
  final a = _at(rules, matchLine);
  final nxt = rules.indexOf('\n    match /', a + matchLine.length);
  return rules.substring(a, nxt < 0 ? rules.length : nxt);
}

void main() {
  final raw = _src('functions/src/index.ts');
  final rules = _src('firestore.rules');
  final code = _codeOf(raw);

  // ── §84 축 목록 ──────────────────────────────────────────────────────
  group('DA-AXIS — deletion-owned identity 축 목록 (§84)', () {
    test('DA-AXIS-01 삭제 helper 가 보는 축이 그대로다', () {
      // 누락 방지가 목적이다. 축이 추가·삭제되면 이 셀이 먼저 깨지고,
      // 그때 barrier 도 같이 봐야 한다.
      final targets = _helper(raw, 'srvDeletionOwnedQueryTargets');
      final t = _flat(targets);
      for (final pair in [
        'col: "member_invitations", field: "targetUid"',
        'col: "member_invitations", field: "invitedBy"',
        'col: "idCardAccessRequests", field: "targetUserId"',
        'col: "idCardAccessRequests", field: "requesterId"',
        'col: "monthly_reviews", field: "targetUserId"',
        'col: "monthly_reviews", field: "reviewerId"',
        'col: "review_requests", field: "workerId"',
        'col: "trust_score_history", field: "userId"',
      ]) {
        expect(t, contains('{$pair'), reason: '축이 사라졌다: $pair');
      }
    });
  });

  // ── Rules: 양축 barrier ──────────────────────────────────────────────
  group('DA-RULES — client create 가 두 축을 모두 본다', () {
    /// `match` 블록의 create 절만.
    String createClause(String matchLine) {
      final a = _at(rules, matchLine);
      final c = rules.indexOf('allow create:', a);
      if (c < 0) throw StateError('allow create 없음: $matchLine');
      final nxt = rules.indexOf('      allow ', c + 10);
      return _flat(rules.substring(c, nxt < 0 ? rules.length : nxt));
    }

    test('DA-RULES-01 초대 — target + caller 양축', () {
      final c = createClause('match /member_invitations/{invitationId}');
      expect(c,
          contains('!accountDeletionBarrierExists(request.resource.data.targetUid)'));
      expect(c, contains('!accountDeletionBarrierExists(request.auth.uid)'));
      // SUPER_ADMIN 분기보다 앞이어야 우회가 불가능하다.
      expect(c.indexOf('!accountDeletionBarrierExists(request.auth.uid)'),
          lessThan(c.indexOf('isSuperAdmin()')));
    });

    test('DA-RULES-02 열람요청 — target + requester 양축', () {
      final c = createClause('match /idCardAccessRequests/{requestId}');
      expect(
          c,
          contains(
              '!accountDeletionBarrierExists(request.resource.data.targetUserId)'));
      expect(c, contains('!accountDeletionBarrierExists(request.auth.uid)'));
      expect(c.indexOf('!accountDeletionBarrierExists(request.auth.uid)'),
          lessThan(c.indexOf('isSuperAdmin()')));
    });

    test('DA-RULES-03 월간리뷰 — targetUserId + reviewerId 양축', () {
      final c = createClause('match /monthly_reviews/{reviewId}');
      expect(
          c,
          contains("!accountDeletionBarrierExists( request.resource.data.get('targetUserId', ''))"));
      expect(
          c,
          contains("!accountDeletionBarrierExists( request.resource.data.get('reviewerId', ''))"));
      expect(c.indexOf('accountDeletionBarrierExists'),
          lessThan(c.indexOf('isSuperAdmin()')));
    });

    test('DA-RULES-04 월간리뷰 — 값이 없으면 barrier 가 평가되지 않는다 (§34)', () {
      // USER_TO_BUSINESS 는 reviewerId 가 없다. helper 가 `uid.size() > 0`
      // 에서 멈춰 exists() 를 평가하지 않으므로 동작도 비용도 그대로다.
      final h = _between(
          rules, 'function accountDeletionBarrierExists', '\n    }');
      expect(_flat(h), contains('uid is string && uid.size() > 0 && exists('));
      // 그래서 `in` 체크를 따로 두지 않았다 — `.get(field, '')` 하나로 끝난다.
      final c = createClause('match /monthly_reviews/{reviewId}');
      expect(c, isNot(contains("'reviewerId' in request.resource.data &&")));
    });

    test('DA-RULES-05 리뷰요청 — workerId 축 (SUPER_ADMIN 예외 없음)', () {
      final c = createClause('match /review_requests/{requestId}');
      expect(
          c,
          contains("!accountDeletionBarrierExists( request.resource.data.get('workerId', ''))"));
      expect(c, contains('isSuperAdmin()'));
    });

    test('DA-RULES-06 .0a.4 의 members create barrier 가 그대로다', () {
      final c = createClause('match /businesses/{businessId}/members/{uid}');
      expect(c, contains('!accountDeletionBarrierExists(uid)'));
    });
  });

  // ── 서버 원자성 (§5·§6·§44·§69·§87) ──────────────────────────────────
  group('DA-TX — 서버는 barrier read 와 create 를 같은 transaction 에 둔다', () {
    test('DA-TX-01 in-transaction helper 가 존재하고 tx.get 을 쓴다', () {
      final h = _helper(raw, 'srvDeletionBarrierExistsInTx');
      expect(_flat(h), contains('tx: FirebaseFirestore.Transaction'));
      expect(_flat(h), contains('await tx.get('));
      expect(h, contains('ACCOUNT_DELETION_TOMBSTONE_COL'));
      // 읽기 실패를 "barrier 없음"으로 바꾸지 않는다 — 삼키는 catch 가 없다.
      expect(h, isNot(contains('catch')));
      expect(h, isNot(contains('return false;\n}')));
    });

    test('DA-TX-02 uid 형식이 이상하면 "없음"이 아니라 "있음"으로 본다 (§8)', () {
      final h = _flat(_helper(raw, 'srvDeletionBarrierExistsInTx'));
      // fail-closed: 판정 불가 → true.
      expect(h, contains('uid.includes("/") || uid.includes("..")'));
      expect(h, contains('return true;'));
      expect(h.indexOf('return true;'), lessThan(h.indexOf('await tx.get(')));
    });

    test('DA-TX-03 리뷰요청 scheduler 두 경로 모두 transaction 안이다', () {
      final sched = _between(
          code, 'async function createPendingReviewRequests', 'export const');
      // 두 경로(단기·장기) 모두 transaction 안에서 barrier 를 읽고 create 한다.
      expect(_count(sched, 'srvDeletionBarrierExistsInTx(tx, workerId)'), 2);
      expect(_count(sched, 'tx.create(requestRef,'), 2);
      // transaction 밖 create 가 남아 있지 않다.
      expect(sched, isNot(contains('await requestRef.create(')));
    });

    test('DA-TX-04 scheduler transaction 안에서 barrier 가 create 보다 앞이다', () {
      final sched = _between(
          code, 'async function createPendingReviewRequests', 'export const');
      final tx = _txBlock(sched, 'srvDeletionBarrierExistsInTx');
      expect(tx, contains('srvDeletionBarrierExistsInTx(tx, workerId)'));
      expect(tx, contains('tx.create(requestRef,'));
      expect(_at(tx, 'srvDeletionBarrierExistsInTx'),
          lessThan(_at(tx, 'tx.create(requestRef,')));
    });

    test('DA-TX-05 늦은 급여 사건(onWageConfirmed)도 transaction 안이다', () {
      final f = _fn(raw, 'onWageConfirmed');
      expect(f, contains('srvDeletionBarrierExistsInTx(tx, workerId)'));
      expect(f, contains('tx.create(requestRef,'));
      expect(f, isNot(contains('await requestRef.create(')));
      final tx = _txBlock(f, 'srvDeletionBarrierExistsInTx');
      expect(_at(tx, 'srvDeletionBarrierExistsInTx'),
          lessThan(_at(tx, 'tx.create(requestRef,')));
    });

    test('DA-TX-06 barrier 에 걸리면 재시도하지 않고 no-op 으로 끝낸다 (§7)', () {
      final f = _fn(raw, 'onWageConfirmed');
      expect(_flat(f), contains('if (skippedByBarrier) {'));
      // throw 로 trigger 재시도를 유발하지 않는다.
      final tail = _between(f, 'if (skippedByBarrier) {', 'await Promise.all([');
      expect(tail, isNot(contains('throw')));
      expect(tail, contains('return;'));
    });

    test('DA-TX-07 열람요청 callable 이 양축을 transaction 안에서 읽는다', () {
      final f = _fn(raw, 'callableCreateIdCardAccessRequest');
      expect(f, contains('srvDeletionBarrierExistsInTx(tx, requesterId)'));
      expect(f, contains('srvDeletionBarrierExistsInTx(tx, targetUserId)'));
      expect(f, contains('tx.create(docRef,'));
      // transaction 밖 add() 가 남아 있지 않다.
      expect(f, isNot(contains('collection("idCardAccessRequests").add(')));
      final tx = _txBlock(f, 'srvDeletionBarrierExistsInTx');
      expect(_at(tx, 'srvDeletionBarrierExistsInTx(tx, requesterId)'),
          lessThan(_at(tx, 'tx.create(docRef,')));
      expect(_at(tx, 'srvDeletionBarrierExistsInTx(tx, targetUserId)'),
          lessThan(_at(tx, 'tx.create(docRef,')));
    });

    test('DA-TX-08 callable 은 계정 상태를 구체적으로 노출하지 않는다 (§27)', () {
      final f = _fn(raw, 'callableCreateIdCardAccessRequest');
      expect(_flat(f),
          contains('throw new HttpsError( "failed-precondition", "지금은 신분증 열람을 요청할 수 없습니다.");'));
      expect(f, isNot(contains('탈퇴 중인 요청자')));
      expect(f, isNot(contains('탈퇴 중인 대상')));
    });

    test('DA-TX-09 transaction 밖 precheck 패턴이 없다 (§6·§69)', () {
      // `await ...tombstones...get()` 뒤에 create 하는 모양을 금지한다.
      // barrier 를 읽는 유일한 서버 경로가 in-tx helper 여야 한다.
      final barrierReads = _count(code, 'ACCOUNT_DELETION_TOMBSTONE_COL');
      expect(barrierReads, greaterThan(0));
      // [R7-P4.4E.11C.0C 갱신] 3 → 4.
      //   선언 1 + ensure helper(tx 안) 1 + in-tx helper 1 + **삭제 재개
      //   상태 질의** 1. 늘어난 자리는 write authority 가 아니라 self-only
      //   읽기다 — 그 사실을 함께 고정한다. 숫자만 올리면 다음에 transaction
      //   밖 precheck 가 생겨도 통과한다.
      // [R7-P4.4E.11C.0C.1.1 갱신] 5 → 6. 가입중단 transaction 도 tombstone
      //   을 read-set 에 넣는다(race guard) — 역시 읽기다.
      // [R7-P4.4E.11C.0C.1 갱신] 4 → 5. Final 이 Auth-tail 증거로 tombstone
      //   존재를 **읽는다**. 여전히 읽기이고 write authority 가 아니다.
      expect(barrierReads, 6,
          reason: 'barrier 문서를 읽는 자리가 늘어났다 — transaction 밖인지 확인해야 한다');
      final recovery = _fn(raw, 'callableGetAccountDeletionRecoveryState');
      expect(recovery, contains('ACCOUNT_DELETION_TOMBSTONE_COL).doc(uid).get()'));
      expect(recovery, isNot(contains('.set(')));
      expect(recovery, isNot(contains('.update(')));
      expect(recovery, isNot(contains('.delete()')));
    });
  });

  // ── 구조적으로 불가능한 축 (§46~§49) ─────────────────────────────────
  group('DA-NONE — create writer 가 없는 축', () {
    test('DA-NONE-01 trust_score_history 는 create writer 가 0 이다', () {
      // rules 는 create: if false, CF 는 [5A.2B] 에서 write 를 제거했다.
      final seg = _flat(
          _matchBlock(rules, 'match /trust_score_history/{historyId}'));
      expect(seg, contains('allow create: if false;'));
      // CF 에 쓰기 호출이 없다 — 참조는 삭제 목록과 주석뿐.
      expect(code, isNot(contains('collection("trust_score_history").add(')));
      expect(code, isNot(contains('collection("trust_score_history").doc(')));
      expect(raw, contains('[5A.2B] trust_score_history write 제거'));
    });

    test('DA-NONE-02 monthly_reviews 는 CF create writer 가 없다', () {
      // 서버가 만들지 않으므로 Rules 가 유일한 gate 다.
      expect(code, isNot(contains('collection("monthly_reviews").add(')));
      expect(code, isNot(contains('tx.create(db.collection("monthly_reviews")')));
    });
  });

  // ── 회귀 (§52~§58·§71) ───────────────────────────────────────────────
  group('DA-REG — 기존 closure 회귀', () {
    test('DA-REG-01 cleanup key 불변성(.0a.4.1)이 그대로다', () {
      for (final keys in [
        "['uid', 'businessId']",
        "['targetUid', 'invitedBy']",
        "['targetUserId', 'requesterId']",
        "['workerId']",
        "['userId']",
      ]) {
        expect(_flat(rules),
            contains('!request.resource.data.diff(resource.data).affectedKeys() .hasAny($keys)'),
            reason: '$keys 불변성이 사라졌다');
      }
    });

    test('DA-REG-02 Final 의 personal·identity cleanup gate 가 그대로다', () {
      final fn = _fn(raw, 'callableDeleteAccountFinal');
      expect(fn, contains('if (personalCleanup.failed > 0)'));
      expect(fn, contains('if (identityCleanup.failed > 0)'));
      expect(fn, contains('srvDeletionPersonalCleared('));
      expect(fn, contains('srvDeletionIdentityCleared('));
      // [R7-P4.4E.11C.1.2 갱신] 9 → 10. 사업장 소유 잔존 gate 의 쿼리 실패
      //   분기가 하나 늘었다(정책 위반은 throw 라 partial 이 아니다).
      //   이 셀이 고정하는 personal·identity gate 자체는 그대로다.
      expect(_count(fn, 'partial: true'), 10);
    });

    test('DA-REG-03 worker_availability·세무 writer gate 가 그대로다', () {
      for (final n in [
        'callableSetAvailability',
        'callableSetInviteRegions',
        'callableAcceptInvitation',
        'callableRegisterTaxIdentity',
        'callableUpdateTaxIdentity',
        'callableRecoverForeignTaxIdentity',
        'callableFinalizeForeignIdentity',
      ]) {
        expect(_fn(raw, n), contains('srvAssertNotDeletingAccount('),
            reason: '$n 의 freeze gate 가 사라졌다');
      }
    });

    test('DA-REG-04 일정·지급 요청 생성 gate 가 그대로다', () {
      // .0a.1 에서 닫은 post-freeze create 차단.
      expect(_flat(rules),
          contains("get(/databases/\$(database)/documents/users/\$(request.auth.uid)).data.get('accountStatus', 'active') != 'deleting'"));
    });

    test('DA-REG-05 notification emitter 는 건드리지 않았다 (§90)', () {
      // .0a.5 소관이다. 이 Phase 에서 수신자 lifecycle 을 심지 않았다.
      final wage = _helper(raw, 'srvNotifyWageEvent');
      expect(wage, isNot(contains('srvDeletionBarrierExistsInTx')));
      expect(wage, isNot(contains('account_deletion_tombstones')));
    });
  });
}
