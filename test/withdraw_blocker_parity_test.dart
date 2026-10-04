// [R7-P4.4E.11C.0C.0a.6.1] preview 가 막는 이유와 삭제가 막는 이유가 같은가
//
// `callableGetWithdrawBlockers` 는 **클라이언트 preview 전용**이다. 거기에
// hardBlock 네 개가 있다.
//
//   UNPAID_WAGES · INTERIM_PENDING · CONFIRMED_WORKERS · ACTIVE_CONTRACTS
//
// 이것을 곧바로 "서버 bypass BLOCKER" 로도, "harmless duplicate" 로도 단정
// 하지 않는다. 각 blocker 가 가리키는 **canonical business truth** 를 찾아
// 삭제 경계가 같은 결론을 내리는지 1:1 로 대조한다.
//
// 대조 결과 세 갈래였다.
//
//   ① CONFIRMED_WORKERS / ACTIVE_CONTRACTS — `onBusinessDeactivated` 가
//      활성 TO 를 CLOSED, PENDING 을 REJECTED, 확정 계열을 CANCELED,
//      서명 전 계약을 voided 로 **결정적으로** 끝낸다. 주인 없는 commitment
//      가 남지 않는다. completed 계약은 근로기준법 보존이지 operational
//      commitment 가 아니다.
//
//   ② INTERIM_PENDING — PENDING 은 승인된 지급 의무가 아니다. 그리고
//      `callableRequestInterimSettlement` 가 모든 attendance 에
//      `wageStatus === "confirmed"` 를 요구하므로, PENDING 이 존재한다는
//      것은 그 사업장에 **미이체 확정 급여가 있다**는 뜻이다 — 아래 ③ 의
//      집합에 들어간다.
//
//   ③ UNPAID_WAGES — **실제 server gap 이었다.** `srvActualWorkReasonOf` 가
//      wageStatus ∈ {calculated, confirmed, transferred} 를 실근무로 보고
//      그 지원서를 `preserved` 로 **의도적으로 보존**한다. 즉 자동 teardown
//      이 이 의무를 끝내 주지 않는다. 그런데 `calculated` 를 확정하고
//      `confirmed` 를 이체하는 것은 조회가 아니라 권한 있는 actor 의
//      operation 이고, 그 authority 는 중간정산 processor 와 **완전히 같다**.
//      단독 관리자가 탈퇴하면 끝낼 사람이 사라진다.
//
// 그래서 `.0a.6` 의 successor-aware 술어를 그 집합까지 넓혔다. 사업장 루프와
// successor 판정을 재사용하고, preview 의 쿼리 shape 를 그대로 쓴다.
//
// 고정하는 것
//   WBP-INV-*     preview blocker 의 canonical 술어
//   WBP-GAP-*     UNPAID_WAGES 서버 gate (이번 patch)
//   WBP-COV-*     자동 teardown 이 이미 끝내는 것
//   WBP-SUB-*     INTERIM_PENDING 의 집합 관계
//   WBP-ROLE-*    role 경계
//   WBP-DIRECT-*  preview 를 안 거친 직접 호출
//   WBP-ERR-*     쿼리 실패 ≠ 0건
//   WBP-SET-*     FinalBlocked ⊆ PreviewBlocked
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

void main() {
  final raw = _src('functions/src/index.ts');
  final code = _codeOf(raw);
  final preview = _fn(raw, 'callableGetWithdrawBlockers');
  final helper = _helper(raw, 'srvCountOrphanMoneyObligations');
  final assertFn = _helper(raw, 'srvAssertAccountDeletionAllowed');
  final deact = _fn(raw, 'onBusinessDeactivated');

  group('WBP-INV — preview blocker 의 canonical 술어', () {
    test('WBP-INV-01 UNPAID_WAGES = wageStatus calculated|confirmed', () {
      // 이 두 상태만이다. transferred 는 끝난 돈이고 pending 은 아직
      // 정산이 개시되지 않은 상태다 — 둘 다 세지 않는다.
      expect(_flat(preview), contains(
          '(["calculated", "confirmed"] as const).flatMap((ws) =>'));
      expect(_flat(preview), contains('.where("wageStatus", "==", ws)'));
      expect(preview, contains('hardBlocks.push({type: "UNPAID_WAGES"'));
      final seg = _between(preview,
          '(["calculated", "confirmed"] as const)', 'allCounts.reduce');
      expect(seg, isNot(contains('transferred')));
      expect(seg, isNot(contains('"pending"')));
    });

    test('WBP-INV-02 INTERIM_PENDING = PENDING 만', () {
      final seg = _between(preview,
          'interim_settlement_requests', 'allSnaps.reduce');
      expect(_flat(seg), contains('.where("status", "==", "PENDING")'));
      for (final other in ['APPROVED', 'PROCESSED', 'REJECTED', 'CANCELED']) {
        expect(seg, isNot(contains(other)));
      }
      expect(preview, contains('hardBlocks.push({type: "INTERIM_PENDING"'));
    });

    test('WBP-INV-03 CONFIRMED_WORKERS = 활성 TO 의 totalConfirmed 합', () {
      // 지원서 집계가 아니라 TO 카운터다 — 이 사실이 ①/③ 분류를 가른다.
      expect(code, contains(
          'const ACTIVE_TO_STATUSES = ["ACTIVE", "FULL", "SCHEDULED"];'));
      final seg = _between(preview, 'let confirmedWorkers = 0', 'return {confirmedWorkers');
      expect(_flat(seg), contains(r'if (d["isDeleted"] === true) continue;'));
      expect(_flat(seg), contains(
          r'if (!ACTIVE_TO_STATUSES.includes(d["status"] as string)) continue;'));
      expect(_flat(seg), contains(r'(d["totalConfirmed"] as number) || 0'));
      expect(preview, contains('hardBlocks.push({type: "CONFIRMED_WORKERS"'));
    });

    test('WBP-INV-04 ACTIVE_CONTRACTS = isLongTerm + 3개 status', () {
      expect(code, contains(
          'const activeStatuses = ["pending_employer", "pending_worker", "completed"];'));
      final seg = _between(preview, 'const activeStatuses', 'hardBlocks.push');
      expect(_flat(seg), contains('.where("isLongTerm", "==", true)'));
      // 종결 상태는 세지 않는다.
      for (final terminal in ['voided', 'expired', 'terminated']) {
        expect(seg, isNot(contains(terminal)));
      }
      expect(preview, contains('hardBlocks.push({type: "ACTIVE_CONTRACTS"'));
    });

    test('WBP-INV-05 네 blocker 는 모두 **사업장 측**이다', () {
      // 근로자 branch 에는 이 네 code 가 없다. 하나의 global blocker 로
      // 뭉개지 않는다(§8).
      // 주석은 `_codeOf` 가 지운다 — 코드 경계로 자른다.
      final userBranch =
          _between(preview, '} else {', 'return {hardBlocks, warnings}');
      for (final biz in [
        'UNPAID_WAGES',
        'INTERIM_PENDING',
        'CONFIRMED_WORKERS',
        'ACTIVE_CONTRACTS',
      ]) {
        expect(userBranch, isNot(contains(biz)));
      }
      // 근로자 측 blocker 는 별도 code 를 쓴다.
      expect(userBranch, contains('hardBlocks.push({type: "UNSIGNED_CONTRACT"'));
      expect(userBranch, contains('hardBlocks.push({type: "SUBADMIN_MEMBERSHIP"'));
      // [R7-P4.4E.11C.0C.0a.6.2 §15] PENDING_WAGES 는 warning 에서
      //   hardBlock 으로 승격됐다 — 계정이 사라지면 그 돈은 되살릴 수 없다.
      //   code 는 그대로이므로 여기서는 소속만 갱신한다.
      expect(userBranch, contains('hardBlocks.push({type: "PENDING_WAGES"'));
      expect(userBranch, contains('warnings.push({type: "CONFIRMED_WORK"'));
    });
  });

  group('WBP-GAP — UNPAID_WAGES 서버 gate', () {
    test('WBP-GAP-01 공용 precondition 에 UNPAID_WAGES blocker 가 있다', () {
      expect(assertFn, contains('[UNPAID_WAGES]'));
      expect(_flat(assertFn), contains(
          'if (money.orphanUnpaidWages > 0) { throw new HttpsError( '
          '"failed-precondition", "[UNPAID_WAGES] 미확정·미이체 급여 "'));
      // PreData 와 Final 이 **같은** precondition 을 쓴다.
      expect(_fn(raw, 'callableDeleteAccountPreData'),
          contains('srvAssertAccountDeletionAllowed('));
      expect(_fn(raw, 'callableDeleteAccountFinal'),
          contains('srvAssertAccountDeletionAllowed('));
    });

    test('WBP-GAP-02 guard 가 무력화되지 않았다', () {
      // "guard 가 존재한다"만 보면 `if (false && …)` 를 놓친다.
      expect(_flat(assertFn), contains(
          'if (role === "BUSINESS_ADMIN" || role === "SUPER_ADMIN") { '
          'const money = await srvCountOrphanMoneyObligations(uid);'));
      expect(assertFn, isNot(contains('false &&')));
      expect(assertFn, isNot(contains('&& false')));
      expect(assertFn, isNot(contains('true ||')));
    });

    test('WBP-GAP-03 preview 와 **같은 술어**를 센다', () {
      expect(_flat(helper), contains('.where("wageStatus", "==", "calculated")'));
      expect(_flat(helper), contains('.where("wageStatus", "==", "confirmed")'));
      expect(_flat(helper), contains(
          'const unpaidWages = calculated.data().count + confirmed.data().count;'));
      // 끝난 돈은 세지 않는다 — 영구 해소 불가 blocker 방지.
      expect(helper, isNot(contains('"transferred"')));
      // [R7-P4.4E.11C.0C.0a.6.2] `pending` 은 **별도 counter** 로 들어왔다.
      //   UNPAID_WAGES 집계에는 섞이지 않는다 — 할 일이 다르다.
      expect(_flat(helper), isNot(contains(
          'const unpaidWages = calculated.data().count + '
          'confirmed.data().count + ')));
    });

    test('WBP-GAP-04 사업장 scope 를 섞지 않는다', () {
      // 정산 1 + 급여 2 + 미계산 1 = 4 개 쿼리 모두 biz.id equality 다.
      expect(_count(helper, '.where("businessId", "==", biz.id)'), 4);
      expect(helper, isNot(contains('array-contains-any')));
      expect(helper, isNot(contains('collectionGroup')));
    });

    test('WBP-GAP-05 successor 가 있으면 통과한다 — 돈이라서 막는 게 아니다', () {
      // orphan 집계는 `!hasSuccessor` 안에서만 증가한다.
      final seg = _between(helper, 'if (!hasSuccessor)', 'return out');
      expect(_flat(seg), contains('out.orphanUnpaidWages += unpaidWages;'));
      expect(_flat(seg), contains('out.orphanApproved += pendingTransfer;'));
      // 루프 바깥에서 몰래 더하지 않는다.
      expect(_count(helper, 'out.orphanUnpaidWages +='), 1);
    });

    test('WBP-GAP-06 모두 0 일 때만 successor 판정을 건너뛴다', () {
      // [R7-P4.4E.11C.0C.0a.6.2] 세 번째 counter 가 들어왔다 — 조건도 셋이다.
      expect(_flat(helper), contains(
          'if (pendingTransfer === 0 && unpaidWages === 0 && '
          'workedUncalculated === 0) continue;'));
      // `||` 로 바뀌면 한 종류만 남은 사업장이 그대로 통과한다.
      expect(_flat(helper), isNot(contains(
          'if (pendingTransfer === 0 || unpaidWages === 0')));
    });

    test('WBP-GAP-07 successor 술어가 급여 writer 의 authority 와 같다', () {
      // 확정·이체 writer 가 요구하는 것 = assertBizAdmin + canManageWage.
      final confirm = _flat(_fn(raw, 'callableConfirmFinalWage'));
      expect(confirm, contains('assertBizAdmin(callerUid, businessId)'));
      expect(confirm, contains('memberPerms.canManageWage'));
      final transfer = _flat(_fn(raw, 'callableMarkTransferredBatch'));
      expect(transfer, contains('assertBizAdmin(callerUid, businessId)'));
      expect(transfer, contains('perms.canManageWage !== true'));
      // helper 가 모으는 후보도 같은 술어다.
      expect(_flat(helper), contains(
          '.where("permissions.canManageWage", "==", true)'));
      expect(helper, contains('adminIds'));
      expect(helper, contains('ownerId'));
    });

    test('WBP-GAP-08 신규 인덱스 없이 서빙된다', () {
      // 쿼리가 인덱스를 못 찾으면 throw → fail closed → **모든** 관리자
      // 탈퇴가 막힌다. 그래서 prefix 존재를 코드로 고정한다.
      final idx = _src('firestore.indexes.json');
      expect(_flat(idx), contains(_flat('''
        {
          "collectionGroup": "attendance",
          "queryScope": "COLLECTION",
          "fields": [
            { "fieldPath": "businessId", "order": "ASCENDING" },
            { "fieldPath": "wageStatus", "order": "ASCENDING" },''')));
    });

    test('WBP-GAP-09 gate 가 파괴보다 앞이다', () {
      final fin = _fn(raw, 'callableDeleteAccountFinal');
      expect(_at(fin, 'srvAssertAccountDeletionAllowed('),
          lessThan(_at(fin, 'userRef.delete()')));
      final pre = _fn(raw, 'callableDeleteAccountPreData');
      expect(_at(pre, 'srvAssertAccountDeletionAllowed('),
          lessThan(_at(pre, 'srvEnsureAccountDeletionTombstone(')));
    });
  });

  group('WBP-COV — 자동 teardown 이 이미 끝내는 것', () {
    test('WBP-COV-01 활성 TO 세 상태를 CLOSED 로 끝낸다', () {
      // preview 의 CONFIRMED_WORKERS 가 세는 바로 그 세 상태다.
      for (final st in ['"ACTIVE"', '"FULL"', '"SCHEDULED"']) {
        expect(_flat(deact), contains('.where("status", "==", $st)'));
      }
      expect(_flat(deact), contains('status: "CLOSED"'));
      expect(_flat(deact), contains('closedReason: "BUSINESS_DEACTIVATED"'));
    });

    test('WBP-COV-02 PENDING → REJECTED, 확정 계열 → CANCELED', () {
      expect(_flat(deact), contains('status: "REJECTED"'));
      expect(_flat(deact), contains('srvLifecycleCancelBulk('));
      expect(_flat(deact), contains('cancelReason: "BUSINESS_DEACTIVATED"'));
      // CLOSED TO 에 남은 잔여 CONFIRMED 도 businessId 전수로 처리한다.
      expect(_flat(deact), contains(r'.where("businessId", "==", businessId) '
          r'.where("status", "==", "CONFIRMED")'));
    });

    test('WBP-COV-03 서명 전 계약은 voided 로 끝난다', () {
      expect(_flat(deact), contains(
          '.where("status", "in", ["pending_employer", "pending_worker"])'));
      expect(_flat(deact), contains('status: "voided"'));
      expect(_flat(deact), contains('voidReason: "BUSINESS_DEACTIVATED"'));
    });

    test('WBP-COV-04 completed 계약은 보존된다 — 삭제를 막을 이유가 아니다', () {
      // 근로기준법 제42조 보존 대상이다. 그래서 teardown 이 건드리지 않고,
      // 그 사실이 곧 "operational commitment 가 아니다"라는 뜻이다.
      expect(deact, isNot(contains('"completed"')));
      // preview 는 completed 를 세고 teardown 은 건드리지 않는다 — 이
      // 비대칭이 의도적이라는 근거가 소스에 적혀 있다.
      expect(raw, contains('근로기준법 제42조: 계약서 문서는 삭제 금지'));
      // voided 전환은 batch 와 개별 fallback 두 경로뿐이다.
      expect(_count(deact, 'status: "voided"'), 2);
    });

    test('WBP-COV-05 **돈이 걸린 건은 보존된다** — 그래서 gate 가 필요하다', () {
      // 자동 teardown 이 모든 것을 끝내 주지 않는다. wageStatus 가 붙은
      // 지원서는 `preserved` 로 남는다 — 주인 없는 돈이 되는 경로다.
      expect(code, contains(
          'const WAGE_SETTLEMENT_STARTED_STATUSES = '
          '["calculated", "confirmed", "transferred"];'));
      final reason = _helper(raw, 'srvActualWorkReasonOf');
      expect(_flat(reason), contains(
          'if (WAGE_SETTLEMENT_STARTED_STATUSES.includes(ws)) return "WAGE_SETTLED";'));
      final one = _helper(raw, 'srvLifecycleCancelOne');
      expect(_flat(one), contains(
          'if (srvActualWorkReasonOf(s.data())) return "preserved";'));
    });
  });

  group('WBP-SUB — INTERIM_PENDING 의 집합 관계', () {
    test('WBP-SUB-01 PENDING 요청은 확정 급여를 전제한다', () {
      // 모든 attendance 가 wageStatus === "confirmed" 여야 요청이 생성된다.
      // 즉 PENDING 이 있으면 그 사업장에 미이체 확정 급여가 있었다.
      final req = _flat(_fn(raw, 'callableRequestInterimSettlement'));
      expect(req, contains(r'ad.wageStatus !== "confirmed"'));
      expect(req, contains('status: "PENDING"'));
    });

    test('WBP-SUB-02 서버 gate 는 PENDING 을 막지 않는다 — 의도적이다', () {
      // PENDING 은 승인된 지급 의무가 아니다. 그리고 이미 이체된 뒤 남은
      // stale PENDING 까지 막으면 영구 해소 불가 blocker 가 된다.
      expect(_flat(helper), contains('.where("status", "==", "APPROVED")'));
      expect(helper, isNot(contains('"PENDING"')));
      expect(assertFn, isNot(contains('INTERIM_PENDING')));
    });
  });

  group('WBP-ROLE — role 경계', () {
    test('WBP-ROLE-01 근로자 탈퇴를 사업장 측 금전 gate 로 막지 않는다', () {
      final seg = _between(assertFn,
          'if (role === "BUSINESS_ADMIN" || role === "SUPER_ADMIN") {',
          'srvCountOrphanMoneyObligations');
      expect(_flat(seg), isNot(contains('role !==')));
      // 근로자 측 hard gate 는 미서명 계약뿐이다.
      expect(_flat(assertFn), contains(
          'if (role !== "BUSINESS_ADMIN" && role !== "SUPER_ADMIN") {'));
      expect(_flat(assertFn), contains('미서명 계약서'));
    });

    test('WBP-ROLE-02 서브관리자는 애초에 탈퇴 경로가 막혀 있다', () {
      expect(assertFn, contains('subAdminBusinessIds'));
      expect(_flat(assertFn), contains('서브관리자로 등록된 사업장'));
    });
  });

  group('WBP-DIRECT — preview 를 안 거친 직접 호출', () {
    test('WBP-DIRECT-01 삭제 writer 는 preview 를 호출하지 않는다', () {
      // preview 는 authority 가 아니다. 구버전 client 가 그것을 건너뛰어도
      // 같은 답을 받아야 한다.
      final pre = _fn(raw, 'callableDeleteAccountPreData');
      final fin = _fn(raw, 'callableDeleteAccountFinal');
      expect(pre, isNot(contains('callableGetWithdrawBlockers')));
      expect(fin, isNot(contains('callableGetWithdrawBlockers')));
      expect(assertFn, isNot(contains('callableGetWithdrawBlockers')));
      // 그리고 preview 는 어떤 삭제 writer 도 부르지 않는다.
      expect(preview, isNot(contains('srvEnsureAccountDeletionTombstone')));
      expect(preview, isNot(contains('deleteUser')));
    });

    test('WBP-DIRECT-02 preview 와 Final 이 같은 helper 를 공유한다', () {
      // 선언 1 + 호출 2 = 3.
      expect(_count(code, 'srvCountOrphanMoneyObligations'), 3);
      expect(preview, contains('srvCountOrphanMoneyObligations(callerUid)'));
      expect(assertFn, contains('srvCountOrphanMoneyObligations(uid)'));
    });
  });

  group('WBP-ERR — 쿼리 실패 ≠ 0건', () {
    test('WBP-ERR-01 helper 가 급여 쿼리 오류를 삼키지 않는다', () {
      expect(helper, isNot(contains('catch')));
      expect(helper, isNot(contains('?? 0')));
      expect(helper, isNot(contains('queryFailed')));
    });

    test('WBP-ERR-02 precondition 이 그 throw 를 가로채지 않는다', () {
      final seg = _between(
          assertFn, 'srvCountOrphanMoneyObligations', '[UNPAID_WAGES]');
      expect(seg, isNot(contains('catch')));
      expect(seg, isNot(contains('?? 0')));
    });

    test('WBP-ERR-03 preview 도 오류를 0건으로 바꾸지 않는다', () {
      // 급여 집계 블록에 catch 가 없다.
      final seg = _between(preview,
          '(["calculated", "confirmed"] as const)', 'allCounts.reduce');
      expect(seg, isNot(contains('catch')));
      // 그리고 클라이언트는 preview 실패 시 삭제 버튼을 비활성화한다.
      final settings = _src('lib/screens/common/settings_screen.dart');
      expect(_flat(settings), contains(
          'onPressed: (hardBlocks.isEmpty && !isLoading && cfError == null)'));
    });
  });

  group('WBP-SET — FinalBlocked ⊆ PreviewBlocked', () {
    test('WBP-SET-01 같은 사업장 기준 집합에서 출발한다', () {
      expect(_flat(preview), contains(
          '.where("adminIds", "array-contains", callerUid)'));
      expect(_flat(preview), contains(r'.filter((d) => !d.data()["deactivatedAt"])'));
      expect(_flat(helper), contains(
          '.where("adminIds", "array-contains", uid)'));
      expect(_flat(helper), contains(r'.filter((d) => !d.data()["deactivatedAt"])'));
    });

    test('WBP-SET-02 preview 가 더 넓다 — 같은 code 를 두 번 올리지 않는다', () {
      // preview 의 UNPAID_WAGES 는 successor 유무와 무관하게 사업장 전체를
      // 센다. 서버는 그 중 주인이 사라지는 사업장만 막는다. 방향이
      // 이쪽이므로 "preview 는 통과인데 삭제가 거부되는" 상태는 없다.
      expect(_count(preview, '"UNPAID_WAGES"'), 1);
      expect(preview, isNot(contains('hasSuccessor')));
      expect(preview, contains('orphanInterim.orphanApproved'));
      expect(preview, isNot(contains('orphanInterim.orphanUnpaidWages')));
    });

    test('WBP-SET-03 서버가 막는 code 는 클라이언트가 설명할 수 있다', () {
      final s = _src('lib/screens/common/settings_screen.dart');
      expect(s, contains("'UNPAID_WAGES' => '미확정/미이체 급여 \$n건'"));
      expect(s, contains("'UNPAID_WAGES' => 'payroll_unpaid'"));
    });
  });
}
