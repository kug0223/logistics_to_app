// [R7-P4.4E.11C.0C.0b.2] TO 는 0명이라 하고 slot 은 1명이라 말할 수 있었다
//
// 지원(PENDING)이 생길 때 올라가는 대기 counter 는 셋이다.
//
//   TO.totalPending                                 항상
//   slot.pendingCount                               slot 있을 때(단기)
//   slot.workDetailCounts[wdId].pendingCount        wdId 해석됐을 때
//
// 그런데 계정삭제 cleanup 은 상태만 batch 로 바꾸고 **TO 하나만** 내렸다.
// 그래서 삭제 뒤 이런 상태가 성립했다.
//
//   Application active waiting = 0
//   TO.totalPending            = N-1
//   slot.pendingCount          = N      ← 아직 기다린다고 말한다
//   workDetail.pendingCount    = N      ← 여기도
//
// `PENDING_STATUSES = [PENDING, INVITED]` 라는 대기 정의를 직접 위반한다.
//
// 고친 방식: 상태 semantics 는 그대로 두고(CANCELED + USER_DELETED),
// **대기 projection 감소의 주인을 하나로** 만들었다.
// `.0b.1` 에서 INVITED 전이로 추출한 owner 에 `expectStatus` 를 주어
// PENDING 도 같은 주인을 쓴다 — 상태는 호출자가, counter 는 owner 가.
//
// 그리고 TO 만 내리던 옛 블록을 **지웠다.** 남겨 두면 이중 감소가 된다.
//
// 고정하는 것
//   PCC-SYM-*    create +1 ↔ cleanup -1 대칭
//   PCC-OWN-*    대기 counter 주인은 하나
//   PCC-SEM-*    상태 semantics 무변경
//   PCC-ATOM-*   상태 전이와 counter 가 같은 transaction
//   PCC-ID-*     workDetail identity fail-closed
//   PCC-RETRY-*  재시도 멱등
//   PCC-UF-*     underflow fail-closed
//   PCC-RES-*    Final residual
//   PCC-SCOPE-*  범위 경계
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
  final a = raw.indexOf('export const $name =');
  if (a < 0) throw StateError('$name 을 찾지 못함');
  var b = raw.indexOf('\nexport const', a + 10);
  if (b < 0) b = raw.length;
  return _codeOf(raw.substring(a, b));
}

String _helper(String raw, String name) {
  final a = raw.indexOf('function $name(');
  if (a < 0) throw StateError('$name 을 찾지 못함');
  final rel = raw.substring(a).indexOf('\n}');
  if (rel < 0) throw StateError('$name 의 끝을 찾지 못함');
  return _codeOf(raw.substring(a, a + rel));
}

void main() {
  final raw = _src('functions/src/index.ts');
  final code = _codeOf(raw);
  final owner = _helper(raw, 'srvTerminateWaitingApplicationInTx');
  final cleanup = _fn(raw, 'callableDeleteAccountApplications');
  final apply = _fn(raw, 'callableApplyToTO');
  final residual = _helper(raw, 'srvCountDeletionDomainResidual');

  group('PCC-SYM — create +1 ↔ cleanup -1 대칭 (§11)', () {
    test('PCC-SYM-01 지원 생성이 올리는 projection 이 셋이다', () {
      expect(_flat(apply), contains(
          'tx.update(toRef, {totalPending: admin.firestore.FieldValue.increment(1)});'));
      expect(_flat(apply), contains(
          'if (slotRef) { const slotPendingUpdate: Record<string, unknown> = { '
          'pendingCount: admin.firestore.FieldValue.increment(1), };'));
      expect(_flat(apply), contains(
          r'slotPendingUpdate[`workDetailCounts.${resolvedWdId}.pendingCount`] = '
          'admin.firestore.FieldValue.increment(1);'));
    });

    test('PCC-SYM-02 종료 owner 가 같은 셋을 같은 조건으로 내린다', () {
      expect(_count(owner, 'FieldValue.increment(-1)'), 3);
      expect(_flat(owner), contains(
          'pendingCount: admin.firestore.FieldValue.increment(-1),'));
      expect(_flat(owner), contains(
          r'slotUpdate[`workDetailCounts.${resolvedWdId}.pendingCount`] = '
          'admin.firestore.FieldValue.increment(-1);'));
      expect(_flat(owner), contains(
          'totalPending: admin.firestore.FieldValue.increment(-1),'));
      // 조건도 대칭이다 — slot 이 있을 때만 slot/TO 를 건드린다.
      expect(_flat(owner), contains('if (slotRef && toId) {'));
      expect(_flat(owner), contains('if (resolvedWdId) {'));
    });

    test('PCC-SYM-03 장기(slot 없음)는 양쪽 모두 slot 을 만들지 않는다 (§10)', () {
      // 생성: slotId 가 없으면 slotRef 가 null 이라 slot 증가가 없다.
      expect(_flat(apply), contains(
          'const slotRef = slotId ? db.collection("tos").doc(toId)'
          '.collection("slots").doc(slotId) : null;'));
      // 종료: slotRef 가 없으면 slot/TO 블록 자체를 건너뛴다.
      final seg = owner.substring(_at(owner, 'if (slotRef && toId) {'));
      expect(_flat(seg), contains('totalPending'));
      // slot 읽기도 조건부다 — 없는 문서를 읽지 않는다.
      expect(_flat(owner), contains('if (slotId && toId) {'));
    });
  });

  group('PCC-OWN — 대기 counter 주인은 하나 (§21·§24)', () {
    test('PCC-OWN-01 cleanup 에 자체 대기 counter 산술이 없다', () {
      // 옛 블록(TO 만 내리던 것)이 사라졌다. 이중 감소 경로 0.
      expect(cleanup, isNot(contains('totalPending: admin.firestore.FieldValue.increment')));
      expect(cleanup, isNot(contains('pendingCount: admin.firestore.FieldValue.increment')));
      expect(cleanup, isNot(contains('workDetailCounts')));
    });

    test('PCC-OWN-02 PENDING 이 공용 owner 를 지난다', () {
      expect(_flat(cleanup), contains(
          'srvTerminateWaitingApplicationInTx(tx, doc.ref, { '
          'expectStatus: "PENDING", status: "CANCELED",'));
      expect(_flat(cleanup), contains('action: "USER_DELETED",'));
      expect(_flat(cleanup), contains(
          'fields: {canceledAt: pendAt, cancelReason: "USER_DELETED"},'));
    });

    test('PCC-OWN-03 TO 단독 감소 구조로 되돌아갈 수 없다 (§24)', () {
      // cleanup 안에서 `tos` 문서를 직접 update 하는 대기 경로가 없다.
      final seg = cleanup.substring(
          _at(cleanup, 'let pendingTerminated = 0;'),
          _at(cleanup, 'const [schedSnap, payChgSnap]'));
      expect(seg, isNot(contains('totalPending')));
      expect(seg, isNot(contains('Math.min')));
      // 그리고 PENDING 상태를 batch 로 직접 쓰지 않는다.
      expect(cleanup, isNot(contains(
          'data: {status: "CANCELED", canceledAt: now, cancelReason: "USER_DELETED"}')));
    });

    test('PCC-OWN-04 선언 1 + 호출 3', () {
      expect(_count(code, 'function srvTerminateWaitingApplicationInTx('), 1);
      expect(_count(code, 'srvTerminateWaitingApplicationInTx'), 4);
      expect(_count(cleanup, 'srvTerminateWaitingApplicationInTx'), 2);
      final expiry = _helper(raw, 'processExpiredTOInvitations');
      expect(_count(expiry, 'srvTerminateWaitingApplicationInTx'), 1);
    });
  });

  group('PCC-SEM — 상태 semantics 무변경 (§3)', () {
    test('PCC-SEM-01 PENDING 종료 상태·사유가 그대로다', () {
      expect(_flat(cleanup), contains('status: "CANCELED",'));
      expect(_flat(cleanup), contains('cancelReason: "USER_DELETED"'));
    });

    test('PCC-SEM-02 새 status·reason 을 만들지 않았다', () {
      final seg = cleanup.substring(
          _at(cleanup, 'let pendingTerminated = 0;'),
          _at(cleanup, 'let invitedTerminated = 0;'));
      expect(seg, isNot(contains('AUTO_CANCELED')));
      expect(seg, isNot(contains('REJECTED')));
      expect(seg, isNot(contains('ACCOUNT_DELETED')));
    });

    test('PCC-SEM-03 확정·근태 경로는 ±0 (§19)', () {
      expect(_flat(cleanup), contains(
          'const delReport = await srvLifecycleCancelBulk( '
          '[...contractSnap.docs, ...confirmedSnap.docs], '
          '{status: "CANCELED", canceledAt: now, cancelReason: "USER_DELETED"});'));
      expect(_flat(cleanup), contains(
          'data: {status: "absent", absentReason: "USER_DELETED", updatedAt: now}'));
      // 확정 좌석/정원 로직(B 구간)은 그대로 있다.
      expect(cleanup, contains('totalConfirmed: admin.firestore.FieldValue.increment'));
      expect(cleanup, contains('confirmedDecrementedAt'));
    });
  });

  group('PCC-ATOM — 같은 transaction (§12)', () {
    test('PCC-ATOM-01 상태 전이와 counter 가 한 경계 안이다', () {
      final statusAt = _at(owner, 'tx.update(appRef, {');
      final slotAt = _at(owner, 'tx.update(slotRef, slotUpdate);');
      final toAt = _at(owner, 'totalPending: admin.firestore.FieldValue.increment(-1)');
      expect(slotAt, greaterThan(statusAt));
      expect(toAt, greaterThan(statusAt));
      // 모든 read 가 모든 write 앞이다.
      expect(_at(owner, 'slotSnap = await tx.get(slotRef)'), lessThan(statusAt));
    });

    test('PCC-ATOM-02 cleanup 에 commit 이후 counter 단계가 없다', () {
      expect(_flat(cleanup), contains(
          'const outcome = await db.runTransaction((tx) => '
          'srvTerminateWaitingApplicationInTx(tx, doc.ref, { expectStatus: "PENDING",'));
      // 그 뒤에 대기 counter 를 만지는 블록이 없다(PCC-OWN-01 과 함께).
      final after = cleanup.substring(_at(cleanup, 'pendingFailed++;'));
      expect(after, isNot(contains('totalPending')));
    });
  });

  group('PCC-ID — workDetail identity fail-closed (§8·§9)', () {
    test('PCC-ID-01 canonical 해석 체인을 재사용한다 — 새 fallback 0', () {
      // Priority 1~4: app.wdId → workDetailId → triple match → unique workType
      expect(owner, contains('let resolvedWdId: string | undefined = appWdId;'));
      expect(owner, contains('const workDetailId = appData.workDetailId as string | undefined;'));
      expect(_flat(owner), contains(
          r'`${wd["workType"]}_${wd["startTime"]}_${wd["endTime"]}` === workDetailId'));
      expect(_flat(owner), contains(
          r'wds.filter((wd) => wd["workType"] === selectedWorkType)'));
    });

    test('PCC-ID-02 해석 실패는 전체 mutation 을 막는다', () {
      expect(_flat(owner), contains('if (isNewSchemaSlot && !resolvedWdId) {'));
      final seg = owner.substring(
          _at(owner, 'if (isNewSchemaSlot && !resolvedWdId) {'));
      expect(seg, contains('FAIL-CLOSED'));
      expect(seg, contains('throw new Error('));
      // throw 지점이 모든 write 보다 앞이다 — 부분 mutation 0.
      expect(_at(owner, 'FAIL-CLOSED'), lessThan(_at(owner, 'tx.update(appRef, {')));
    });

    test('PCC-ID-03 workDetailCounts 엔트리 부재도 fail-closed', () {
      expect(owner, contains('DATA INVARIANT'));
      expect(_flat(owner), contains('if (!wdc || wdc[resolvedWdId] === undefined) {'));
      expect(_at(owner, 'DATA INVARIANT'), lessThan(_at(owner, 'tx.update(appRef, {')));
    });
  });

  group('PCC-RETRY — 재시도 멱등 (§13)', () {
    test('PCC-RETRY-01 전제 상태가 아니면 쓰기 0', () {
      expect(_flat(owner), contains(
          r'if (!fresh.exists || fresh.data()!.status !== terminal.expectStatus) {'));
      final head = owner.substring(0, _at(owner, 'return "skipped";'));
      expect(head, isNot(contains('tx.update')));
    });

    test('PCC-RETRY-02 재실행은 쿼리에서 빠지고 skip 으로 센다', () {
      expect(_flat(cleanup), contains(
          r'.where("uid", "==", callerUid).where("status", "==", "PENDING").get(),'));
      expect(_flat(cleanup), contains(
          'if (outcome === "skipped") pendingSkipped++; else pendingTerminated++;'));
      expect(_flat(cleanup), contains(
          'pendingTerminated, pendingSkipped, pendingFailed,'));
    });
  });

  group('PCC-UF — underflow fail-closed (§14·§15)', () {
    test('PCC-UF-01 workDetail 집계 underflow guard', () {
      expect(_flat(owner), contains('if (currentPending <= 0) {'));
      expect(owner, contains('UNDERFLOW GUARD: workDetailCounts'));
    });

    test('PCC-UF-02 slot 집계도 같은 기준이다 — 추가 read 없음', () {
      expect(_flat(owner), contains(
          r'const slotPending = (slotSnap.data()!.pendingCount as number | undefined) ?? 0;'));
      expect(_flat(owner), contains('if (slotPending <= 0) {'));
      expect(owner, contains('UNDERFLOW GUARD: slot.pendingCount'));
      // 이미 읽은 문서를 쓴다 — tx.get 횟수는 그대로 2(앱·슬롯)다.
      expect(_count(owner, 'await tx.get('), 2);
      // guard 가 write 보다 앞이다.
      expect(_at(owner, 'UNDERFLOW GUARD: slot.pendingCount'),
          lessThan(_at(owner, 'tx.update(appRef, {')));
    });

    test('PCC-UF-03 조용한 clamp 가 사라졌다', () {
      // 예전 PENDING 경로는 Math.min 으로 0 까지만 깎고 넘어갔다 —
      //   모순을 소리 없이 남기는 방식이다(§15).
      final seg = cleanup.substring(
          _at(cleanup, 'let pendingTerminated = 0;'),
          _at(cleanup, 'const [schedSnap, payChgSnap]'));
      expect(seg, isNot(contains('Math.min')));
      expect(seg, isNot(contains('Math.max')));
    });
  });

  group('PCC-RES — Final residual (§16)', () {
    test('PCC-RES-01 PENDING 이 남으면 파괴하지 않는다', () {
      expect(_flat(residual), contains(
          r'.where("uid", "==", uid).where("status", "==", "PENDING").get(),'));
      final cleared = _helper(raw, 'srvDeletionDomainCleared');
      expect(_flat(cleared), contains('r.applications === 0'));
      final fin = _fn(raw, 'callableDeleteAccountFinal');
      expect(_at(fin, 'srvDeletionDomainCleared(domainResidual)'),
          lessThan(_at(fin, 'userRef.delete()')));
    });
  });

  group('PCC-SCOPE — 범위 경계 (§19·§20·§26)', () {
    test('PCC-SCOPE-01 종결된 상태를 cleanup 이 집지 않는다', () {
      final seg = cleanup.substring(
          _at(cleanup, 'const [pendingSnap'),
          _at(cleanup, 'const now = admin.firestore.FieldValue.serverTimestamp();'));
      for (final terminal in [
        '"REJECTED"', '"EXPIRED"', '"AUTO_CANCELED"', '"CANCELED"',
      ]) {
        expect(seg, isNot(contains(terminal)));
      }
    });

    test('PCC-SCOPE-02 앱 전체 PENDING writer 를 리팩터링하지 않았다', () {
      // owner 를 쓰는 곳은 셋뿐이다 — 공고 마감·사업장 비활성화·근로자
      // 취소 경로는 그대로 둔다(§20 범위 확장 금지).
      final toExpiry = _helper(raw, 'processTOExpiry');
      expect(toExpiry, isNot(contains('srvTerminateWaitingApplicationInTx')));
      final deact = _fn(raw, 'onBusinessDeactivated');
      expect(deact, isNot(contains('srvTerminateWaitingApplicationInTx')));
    });

    test('PCC-SCOPE-03 INVITED 정책은 .0b.1 그대로다 (§22-P8·P12)', () {
      expect(_flat(cleanup), contains(
          'srvTerminateWaitingApplicationInTx(tx, doc.ref, { '
          'expectStatus: "INVITED", status: "AUTO_CANCELED",'));
      expect(_flat(cleanup), contains(
          'fields: {canceledAt: invAt, cancelReason: "ACCOUNT_DELETED"},'));
      final offer = _fn(raw, 'callableOfferAlternativeWork');
      expect(_flat(offer), contains('status: "INVITED",'));
    });
  });
}
