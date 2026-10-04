// [R7-P4.4E.11C.0C.0b.1] 없는 사람을 계속 "초대 중"으로 기다렸다
//
// `INVITED` 는 이 제품에서 historical row 가 아니다.
//
//   PENDING_STATUSES = [PENDING, INVITED]        ← 대기 집계의 정의
//   관리자 화면       = "초대 중 N명"             ← 응답을 기다리는 상태
//
// 그런데 계정삭제 cleanup 의 대상 집합은 PENDING·CONTRACT_PENDING·CONFIRMED
// 뿐이었고, Final 의 residual 도 INVITED 를 세지 않았다. 그래서 탈퇴가
// 끝난 뒤에도 초대가 **살아 있는 대기 상태로** 남았다.
//
// 종료 상태는 새로 만들지 않았다. 기존 네 개를 보고 골랐다.
//
//   REJECTED      = 초대 거절   ← 근로자가 거절한 사실이 아니다
//   CANCELED      = 초대 철회   ← 관리자가 철회한 사실도 아니다
//   EXPIRED       = 응답 만료   ← 시간이 지난 것도 아니다
//   AUTO_CANCELED = 자동 종료   ← 사유별 분기를 이미 갖고 있다
//
// 그래서 `AUTO_CANCELED` + `cancelReason: "ACCOUNT_DELETED"` 다. 문서는
// 지우지 않는다 — 누가 언제 어떤 조건으로 초대했는지는 남아야 한다.
//
// 그리고 전이에는 counter 계약이 딸려 있다. 대기 counter 세 개가 정확히
// 1 내려가야 하고, 재시도가 두 번 내리면 안 된다. 그 식을 복제하지 않고
// 초대 만료 scheduler 안에 있던 canonical transition 을 **꺼내서** 둘이
// 공유한다.
//
// 고정하는 것
//   IAC-LIFE-*   초대 lifecycle 과 canonical transition
//   IAC-TERM-*   종료 상태 선택
//   IAC-CLEAN-*  cleanup 통합
//   IAC-RES-*    Final residual fail-closed
//   IAC-CNT-*    대기 counter 정합·멱등
//   IAC-HIST-*   기존 종료 기록 불변
//   IAC-SIDE-*   신뢰도·알림 부작용 0
//   IAC-PROJ-*   관리자 projection
//   IAC-SCOPE-*  범위 경계
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
  final transition = _helper(raw, 'srvTerminateWaitingApplicationInTx');
  final cleanup = _fn(raw, 'callableDeleteAccountApplications');
  final residual = _helper(raw, 'srvCountDeletionDomainResidual');
  final expiry = _helper(raw, 'processExpiredTOInvitations');
  final dialog = _src('lib/screens/business_admin/dialogs/day_applicants_dialog.dart');
  final model = _src('lib/models/core/application_model.dart');

  group('IAC-LIFE — 초대 lifecycle 과 canonical transition', () {
    test('IAC-LIFE-01 INVITED 는 대기 집계의 일부다 — 그래서 문제였다', () {
      expect(code, contains('const PENDING_STATUSES = ["PENDING", "INVITED"];'));
      // 서버 대기 집계가 그 정의를 쓴다.
      expect(_count(code, 'PENDING_STATUSES'), greaterThanOrEqualTo(4));
    });

    test('IAC-LIFE-02 기존 종료 상태의 의미가 그대로다', () {
      // 화면이 말하는 네 문장 — 이번 선택의 비교 기준이다.
      expect(_flat(dialog), contains("return ('초대 거절', AppColors.grey600);"));
      expect(_flat(dialog), contains("return ('초대 철회', AppColors.grey600);"));
      expect(_flat(dialog), contains("return ('응답 만료', AppColors.grey600);"));
      expect(_flat(dialog), contains("'자동 종료',"));
    });

    test('IAC-LIFE-03 canonical transition 은 한 벌이고 둘이 공유한다', () {
      expect(_count(code, 'function srvTerminateWaitingApplicationInTx('), 1);
      // [R7-P4.4E.11C.0C.0b.2] 선언 1 + 호출 3(만료 · 삭제 INVITED · 삭제 PENDING).
      expect(_count(code, 'srvTerminateWaitingApplicationInTx'), 4);
      expect(_flat(expiry), contains(
          'srvTerminateWaitingApplicationInTx(tx, doc.ref, { '
          'expectStatus: "INVITED", status: "EXPIRED",'));
      expect(_flat(cleanup), contains(
          'srvTerminateWaitingApplicationInTx(tx, doc.ref, { '
          'expectStatus: "INVITED", status: "AUTO_CANCELED",'));
    });
  });

  group('IAC-TERM — 종료 상태 선택', () {
    test('IAC-TERM-01 AUTO_CANCELED + ACCOUNT_DELETED 로 끝낸다 (I1)', () {
      expect(_flat(cleanup), contains('status: "AUTO_CANCELED", action: "ACCOUNT_DELETED",'));
      expect(_flat(cleanup), contains(
          'fields: {canceledAt: invAt, cancelReason: "ACCOUNT_DELETED"},'));
    });

    test('IAC-TERM-02 문서를 지우지 않는다 — 초대 이력 보존 (§5)', () {
      expect(transition, isNot(contains('.delete()')));
      expect(transition, contains('tx.update(appRef, {'));
      // 이력에 전이를 남긴다.
      expect(_flat(transition), contains(
          'statusHistory: admin.firestore.FieldValue.arrayUnion({'));
      // cleanup 의 초대 구간에도 삭제가 없다.
      final seg = cleanup.substring(
          _at(cleanup, 'let invitedTerminated = 0;'),
          _at(cleanup, 'const [schedSnap, payChgSnap]'));
      expect(seg, isNot(contains('.delete()')));
    });

    test('IAC-TERM-03 거절·철회·만료로 오기록하지 않는다 (§3)', () {
      final seg = cleanup.substring(
          _at(cleanup, 'let invitedTerminated = 0;'),
          _at(cleanup, 'const [schedSnap, payChgSnap]'));
      expect(seg, isNot(contains('"REJECTED"')));
      expect(seg, isNot(contains('"CANCELED"')));
      expect(seg, isNot(contains('"EXPIRED"')));
    });

    test('IAC-TERM-04 새 status enum 을 만들지 않았다 (§4)', () {
      // 클라이언트 상수 집합이 그대로다.
      expect(model, contains("static const String autoCanceled     = 'AUTO_CANCELED';"));
      expect(model, isNot(contains('ACCOUNT_DELETED_STATUS')));
      // 서버도 기존 enum 만 쓴다.
      expect(code, isNot(contains('"ACCOUNT_CLOSED"')));
    });
  });

  group('IAC-CLEAN — cleanup 통합', () {
    test('IAC-CLEAN-01 INVITED 가 대상 집합에 들어왔다', () {
      expect(_flat(cleanup), contains(
          r'db.collection("applications").where("uid", "==", callerUid)'
          r'.where("status", "==", "INVITED").get(),'));
    });

    test('IAC-CLEAN-02 건마다 transaction 으로 전이한다', () {
      expect(_flat(cleanup), contains(
          'srvTerminateWaitingApplicationInTx(tx, doc.ref, { '
          'expectStatus: "INVITED", status: "AUTO_CANCELED",'));
      expect(_flat(cleanup), contains(
          'if (outcome === "skipped") invitedSkipped++; else invitedTerminated++;'));
    });

    test('IAC-CLEAN-03 실패를 숨기지 않는다 (§8·PARTIAL ≠ SUCCESS)', () {
      expect(_flat(cleanup), contains('invitedFailed++;'));
      expect(_flat(cleanup), contains('invitedTerminated, invitedSkipped, invitedFailed,'));
    });

    test('IAC-CLEAN-04 확정 계열 정책은 그대로다 (I13)', () {
      expect(_flat(cleanup), contains(
          'const delReport = await srvLifecycleCancelBulk( '
          '[...contractSnap.docs, ...confirmedSnap.docs], '
          '{status: "CANCELED", canceledAt: now, cancelReason: "USER_DELETED"});'));
      expect(cleanup, contains('delReport.preserved'));
    });

    test('IAC-CLEAN-05 대체업무 초대도 같은 전이를 받는다 (I16)', () {
      // 쿼리는 status 만 본다 — offerKind 로 가르지 않는다.
      final seg = cleanup.substring(
          _at(cleanup, 'let invitedTerminated = 0;'),
          _at(cleanup, 'const [schedSnap, payChgSnap]'));
      expect(seg, isNot(contains('offerKind')));
      expect(seg, isNot(contains('ALTERNATIVE_WORK')));
      // 그리고 그 writer 가 만드는 것도 INVITED 다.
      final offer = _fn(raw, 'callableOfferAlternativeWork');
      expect(_flat(offer), contains('status: "INVITED",'));
    });
  });

  group('IAC-RES — Final residual fail-closed', () {
    test('IAC-RES-01 INVITED 가 남아 있으면 파괴하지 않는다 (I7)', () {
      expect(_flat(residual), contains(
          r'.where("uid", "==", uid).where("status", "==", "INVITED").get(),'));
      expect(_flat(residual), contains(
          'out.applications = pending.size + contractPending.size + '
          'confirmed.size + invited.size;'));
      // residual 0 이 아니면 Final 이 identity 를 파괴하지 않는다.
      final cleared = _helper(raw, 'srvDeletionDomainCleared');
      expect(_flat(cleared), contains('r.applications === 0'));
      final fin = _fn(raw, 'callableDeleteAccountFinal');
      expect(_at(fin, 'srvDeletionDomainCleared(domainResidual)'),
          lessThan(_at(fin, 'userRef.delete()')));
      expect(_flat(fin), contains('reason: "DOMAIN_CLEANUP_INCOMPLETE",'));
    });

    test('IAC-RES-02 종료된 초대는 residual 이 아니다 (I8)', () {
      for (final terminal in [
        '"AUTO_CANCELED"', '"REJECTED"', '"CANCELED"', '"EXPIRED"',
      ]) {
        expect(residual, isNot(contains(terminal)),
            reason: '$terminal 은 끝난 관계다 — 삭제를 막아선 안 된다');
      }
    });
  });

  group('IAC-CNT — 대기 counter 정합·멱등', () {
    test('IAC-CNT-01 세 counter 가 각각 정확히 1 내려간다 (I3·I4·I5)', () {
      expect(_count(transition, 'FieldValue.increment(-1)'), 3);
      expect(_flat(transition), contains(
          'pendingCount: admin.firestore.FieldValue.increment(-1),'));
      expect(_flat(transition), contains(
          r'slotUpdate[`workDetailCounts.${resolvedWdId}.pendingCount`] = '
          'admin.firestore.FieldValue.increment(-1);'));
      expect(_flat(transition), contains(
          'totalPending: admin.firestore.FieldValue.increment(-1),'));
    });

    test('IAC-CNT-02 재시도가 두 번 내리지 않는다 (I6·§11)', () {
      // fresh read 가 INVITED 가 아니면 아무것도 쓰지 않고 skip 한다.
      // [R7-P4.4E.11C.0C.0b.2] 전제 상태는 호출자가 정한다 — PENDING 과
      //   INVITED 가 같은 projection 주인을 공유한다.
      expect(_flat(transition), contains(
          r'if (!fresh.exists || fresh.data()!.status !== terminal.expectStatus) {'));
      final head = transition.substring(0, _at(transition, 'return "skipped";'));
      expect(head, isNot(contains('tx.update')));
      // 상태 전이 자체가 멱등 key 다 — cleanup 재호출 시 쿼리에서 빠진다.
      expect(_flat(cleanup), contains(r'.where("status", "==", "INVITED").get(),'));
    });

    test('IAC-CNT-03 옮기면서 guard 를 잃지 않았다', () {
      expect(transition, contains('DATA INVARIANT'));
      expect(transition, contains('UNDERFLOW GUARD'));
      expect(transition, contains('FAIL-CLOSED'));
      expect(_flat(transition), contains('if (currentPending <= 0) {'));
      expect(_flat(transition), contains('if (isNewSchemaSlot && !resolvedWdId) {'));
      // 읽기가 모두 쓰기보다 앞이다.
      expect(_at(transition, 'slotSnap = await tx.get(slotRef)'),
          lessThan(_at(transition, 'tx.update(appRef, {')));
    });

    test('IAC-CNT-04 counter 산술을 복제하지 않았다 (§11)', () {
      // 만료 scheduler 안에는 더 이상 자체 전이·감소가 없다.
      expect(expiry, isNot(contains('FieldValue.increment(-1)')));
      expect(expiry, isNot(contains('workDetailCounts')));
      expect(expiry, isNot(contains('UNDERFLOW GUARD')));
    });
  });

  group('IAC-HIST — 기존 종료 기록 불변 (I9~I12)', () {
    test('IAC-HIST-01 cleanup 은 살아 있는 초대만 집는다', () {
      // status == INVITED 쿼리 하나. 종료 상태를 긁지 않는다.
      final seg = cleanup.substring(
          _at(cleanup, 'const [pendingSnap'),
          _at(cleanup, 'const now = admin.firestore.FieldValue.serverTimestamp();'));
      expect(_count(seg, '"INVITED"'), 1);
      // `"CANCELED"` 는 앞뒤 따옴표를 함께 고정한다 — `"AUTO_CANCELED"` 의
      //   부분문자열로 잡히지 않는다.
      for (final terminal in [
        '"REJECTED"', '"EXPIRED"', '"AUTO_CANCELED"', '"CANCELED"',
      ]) {
        expect(seg, isNot(contains(terminal)),
            reason: '$terminal 은 이미 끝난 기록이다 — cleanup 이 다시 집지 않는다');
      }
    });

    test('IAC-HIST-02 helper 도 INVITED 가 아니면 손대지 않는다', () {
      expect(_flat(transition), contains(
          r'fresh.data()!.status !== terminal.expectStatus'));
      // 삭제 cleanup 의 초대 경로는 INVITED 를 전제로 호출한다.
      expect(_flat(cleanup), contains('expectStatus: "INVITED",'));
    });
  });

  group('IAC-SIDE — 신뢰도·알림 부작용 0', () {
    test('IAC-SIDE-01 신뢰도 패널티가 붙지 않는다 (I14·§16)', () {
      for (final bad in ['trustScore', 'noShowCount', 'declineCount', 'cancelCount']) {
        expect(transition, isNot(contains(bad)));
      }
      final seg = cleanup.substring(
          _at(cleanup, 'let invitedTerminated = 0;'),
          _at(cleanup, 'const [schedSnap, payChgSnap]'));
      for (final bad in ['trustScore', 'noShowCount', 'declineCount']) {
        expect(seg, isNot(contains(bad)));
      }
      // applications 문서 트리거는 카운터 재계산 하나뿐이다 —
      //   신뢰도는 attendance 쪽 트리거가 담당한다.
      expect(code, contains(
          'export const syncTOStats = onDocumentWritten('));
      expect(_flat(code), contains(
          'document: "applications/{applicationId}", region: "asia-northeast3"'));
    });

    test('IAC-SIDE-02 새 persistent notification 을 만들지 않는다 (I15·§15)', () {
      expect(transition, isNot(contains('srvPersistNotification')));
      final seg = cleanup.substring(
          _at(cleanup, 'let invitedTerminated = 0;'),
          _at(cleanup, 'const [schedSnap, payChgSnap]'));
      expect(seg, isNot(contains('srvPersistNotification')));
      expect(seg, isNot(contains('notifications')));
    });
  });

  group('IAC-PROJ — 관리자 projection', () {
    test('IAC-PROJ-01 "초대 중"에서 빠진다 (I2)', () {
      // 분류는 status 하나로 한다 — INVITED 가 아니면 종료 기록으로 간다.
      expect(_flat(dialog), contains(
          'if (app.status == AppStatus.invited) { g.invitedApps.add(app); } '
          'else { g.closedInvites.add(app); }'));
      // "초대 중"은 invitedApps 에서만 나온다.
      expect(_flat(dialog), contains(
          'List<ApplicationModel> get activeInvites => '
          'capacityState == InviteCapacityState.available ? invitedApps : const [];'));
    });

    test('IAC-PROJ-02 history 문구가 사건을 말한다 (§13)', () {
      expect(_flat(dialog), contains("'ACCOUNT_DELETED' => '탈퇴로 종료',"));
      expect(_flat(dialog), contains("'SCHEDULE_CONFLICT' => '일정 겹침 종료',"));
    });

    test('IAC-PROJ-03 reader 가 깨지지 않는다 (§14)', () {
      // 근로자 측 statusText 도 '알 수 없음'으로 떨어지지 않는다.
      expect(_flat(model), contains(
          r"if (status == 'AUTO_CANCELED' && cancelReason == 'ACCOUNT_DELETED') "
          r"{ return '탈퇴로 종료'; }"));
      expect(model, contains("case 'AUTO_CANCELED':     return '자동 취소됨';"));
    });
  });

  group('IAC-SCOPE — 범위 경계', () {
    test('IAC-SCOPE-01 모집 마감은 INVITED 를 바꾸지 않는다 (§22)', () {
      // 정원 마감·모집 종료는 status 를 그대로 두고 표시만 가른다.
      expect(_flat(dialog), contains(
          'List<ApplicationModel> get staleInvites => '
          'capacityState == InviteCapacityState.full ? invitedApps : const [];'));
      expect(_flat(dialog), contains(
          'List<ApplicationModel> get unitClosedInvites => '
          'capacityState == InviteCapacityState.closed ? invitedApps : const [];'));
    });

    test('IAC-SCOPE-02 .0C.0b fence 를 재설계하지 않았다 (§9)', () {
      final invite = _fn(raw, 'callableInviteWorker');
      expect(invite, contains('srvAssertAccountNotFrozenInTx(invTx, targetUid, "근로자")'));
      final offer = _fn(raw, 'callableOfferAlternativeWork');
      expect(offer, contains('srvAssertAccountNotFrozenInTx(offerTx, offerUid, "근로자")'));
    });
  });
}
