// [R7-P4.4E.11C.0C.0a.6.2] 약속은 약속대로, 일한 임금은 끝까지
//
// 네 BLOCKER 를 닫는다.
//
//   A. CONFIRMED_WORKERS — preview 는 삭제를 거부하는데, 직접 호출하면
//      통과하고 Final 의 비활성화가 확정 약속을 CANCELED 로 바꿨다.
//   B. ACTIVE_CONTRACTS — 같은 구조. 서명 대기 계약이 voided 가 됐다.
//   C. 출근은 했는데 wageStatus 가 아직 pending 인 건 — 어느 gate 에도
//      없었다. 정산 개시 **이전** 단계라 가장 먼저 주인을 잃는다.
//   D. 근로자 탈퇴 + 확정 미이체 급여 — users 문서가 사라지면 이체가
//      영구히 막힌다(stale 판정 + 회복 경로가 함께 닫힌다).
//
// 가장 중요한 구분(§5):
//
//   teardown 이 모순 없이 종결한다는 사실은
//   그 destructive event 를 **허용할지**에 대한 답이 아니다.
//   safety mechanism ≠ authorization.
//
// 범위 술어가 둘인 이유:
//
//   약속 continuity → **비활성화될 사업장**(adminIds.length === 1).
//     canManageWage 서브관리자는 사업장을 살려 두지 못한다.
//   급여 continuity → **successor 존재**(canManageWage 포함).
//     사업장이 비활성화돼도 급여 처리 경로는 남는다.
//
// 고정하는 것
//   WPM-A-*    확정 약속(CONFIRMED_WORKERS)
//   WPM-B-*    계약 상태별 정책(ACTIVE_CONTRACTS)
//   WPM-C-*    실근무 + 미계산 급여
//   WPM-D-*    근로자 탈퇴 + 확정 미이체 급여
//   WPM-PAR-*  preview ↔ server parity
//   WPM-ERR-*  쿼리 실패 ≠ 0건
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
  final assertFn = _helper(raw, 'srvAssertAccountDeletionAllowed');
  final promise = _helper(raw, 'srvCountWithdrawPromiseScope');
  final money = _helper(raw, 'srvCountOrphanMoneyObligations');
  final workerWage = _helper(raw, 'srvCountWorkerUnpaidPayableWages');
  final preview = _fn(raw, 'callableGetWithdrawBlockers');
  final deact = _fn(raw, 'onBusinessDeactivated');
  final finalFn = _fn(raw, 'callableDeleteAccountFinal');

  group('WPM-A — 확정 약속(CONFIRMED_WORKERS)', () {
    test('WPM-A-01 공용 precondition 이 약속을 막는다 (C1·C2)', () {
      expect(assertFn, contains('srvCountWithdrawPromiseScope(uid)'));
      expect(assertFn, contains('[CONFIRMED_WORKERS]'));
      expect(_flat(assertFn), contains(
          'if (promise.liveConfirmed > 0) { throw new HttpsError('));
      // preview 를 안 거친 직접 호출도 같은 답을 받는다.
      expect(_fn(raw, 'callableDeleteAccountPreData'),
          contains('srvAssertAccountDeletionAllowed('));
      expect(finalFn, contains('srvAssertAccountDeletionAllowed('));
      // 무력화 단축이 끼어들지 않는다.
      expect(assertFn, isNot(contains('false &&')));
      expect(assertFn, isNot(contains('&& false')));
      expect(assertFn, isNot(contains('true ||')));
    });

    test('WPM-A-02 범위 술어가 Final 의 business cleanup 과 같다', () {
      // 약속이 취소되는 것은 **사업장이 비활성화될 때**뿐이다.
      expect(_flat(finalFn), contains(
          'const isSoleAdmin = adminIds.length === 1 && adminIds.includes(uid);'));
      expect(_flat(promise), contains(
          'return adminIds.length === 1 && adminIds.includes(uid);'));
      expect(_flat(promise), contains(r'if (d.data()["deactivatedAt"]) return false;'));
      // 비활성화될 사업장이 없으면 더 읽지 않는다.
      expect(_flat(promise), contains('if (sole.length === 0) return out;'));
    });

    test('WPM-A-03 PENDING 은 약속이 아니다 (C3)', () {
      expect(code, contains(
          'const CONFIRMED_STATUSES = ["CONFIRMED", "CONTRACT_PENDING"];'));
      expect(_flat(promise), contains('CONFIRMED_STATUSES.map((st) =>'));
      expect(promise, isNot(contains('"PENDING"')));
      expect(promise, isNot(contains('"INVITED"')));
    });

    test('WPM-A-04 반납·기간종료·지나간 단기는 약속이 아니다 (C4)', () {
      expect(_flat(promise), contains(r'if (d.get("staffingReleasedAt") != null) continue;'));
      // 좌석 판정은 canonical helper 하나다 — 새 규칙을 만들지 않는다.
      expect(_flat(promise), contains('if (!srvOccupiesSeatToday(d)) continue;'));
      expect(code, contains('function srvOccupiesSeatToday('));
      // 단기 과거 근무일 제외 — 기준은 KST 달력 하루다.
      expect(_flat(promise), contains('if (!futureShortTerm(d)) continue;'));
      expect(_flat(promise), contains('return srvKstDateNum(wd.toDate()) >= todayNum;'));
      // 날짜를 모르면 산 것으로 본다(fail closed).
      expect(_flat(promise), contains(
          'if (!wd || typeof wd.toDate !== "function") return true;'));
    });

    test('WPM-A-05 실근무 개시 건은 취소되지 않는다 — 그래서 세지 않는다 (C4)', () {
      // teardown 이 `preserved` 로 보존하는 집합이다.
      expect(_flat(promise), contains(
          'const verdict = await srvHasActualWorkStarted(d.id, d.data());'));
      expect(_flat(promise), contains('if (!verdict.started) out.liveConfirmed++;'));
      // 읽을 양이 많으면 "보존될 것"이라고 추정하지 않는다 — 막는다.
      expect(_flat(promise), contains('const CHECK_CAP = 50;'));
      expect(_flat(promise), contains(
          'if (candidates.length > CHECK_CAP) { out.liveConfirmed += candidates.length;'));
    });

    test('WPM-A-06 공동 관리자가 남으면 약속이 취소되지 않는다 (C5)', () {
      // Final 은 사업장을 살려 두고 adminIds 에서 uid 만 뺀다.
      expect(_flat(finalFn), contains(
          'adminIds: admin.firestore.FieldValue.arrayRemove(uid),'));
      // 그래서 그 경우는 blocker 가 아니다 — 비활성화 분기와 배타적이다.
      expect(_flat(finalFn), contains('if (isSoleAdmin) {'));
    });

    test('WPM-A-07 teardown 이 실제로 취소한다는 증거 (§5)', () {
      expect(_flat(deact), contains('srvLifecycleCancelBulk('));
      expect(_flat(deact), contains('status: "CANCELED"'));
      expect(_flat(deact), contains('cancelReason: "BUSINESS_DEACTIVATED"'));
      // 비활성화는 account withdrawal 이 유발한다.
      expect(_flat(finalFn), contains(
          'deactivatedAt: admin.firestore.FieldValue.serverTimestamp(),'));
    });

    test('WPM-A-08 "관리자 탈퇴 시 약속 자동취소" product decision 은 없다', () {
      // 문서에 적힌 유일한 자동취소 정책은 **확정 시 겹치는 PENDING** 이다.
      final doc = _src('CLAUDE.md');
      final lines = doc
          .split(RegExp(r'\r?\n'))
          .where((l) => l.contains('자동취소') || l.contains('자동 취소'))
          .toList();
      expect(lines, isNotEmpty, reason: '비교 기준이 되는 문장이 있어야 한다');
      for (final l in lines) {
        expect(l, contains('겹치는'),
            reason: '탈퇴 자동취소를 허용하는 명시적 결정이 생기면 이 셀을 고쳐야 한다: $l');
      }
    });
  });

  group('WPM-B — 계약 상태별 정책(ACTIVE_CONTRACTS)', () {
    test('WPM-B-01 서명 대기 계약만 서버 blocker 다', () {
      expect(assertFn, contains('[ACTIVE_CONTRACTS]'));
      expect(_flat(assertFn), contains('if (promise.pendingContracts > 0) {'));
      expect(_flat(promise), contains(
          '.where("status", "in", ["pending_employer", "pending_worker"])'));
    });

    test('WPM-B-02 completed 는 세지 않는다 — 법정 보존이다', () {
      // 체결된 계약 문서는 근로기준법 42조 보존 대상이고, teardown 도
      // 건드리지 않는다. 그 operational 부분은 확정 약속(A)이 막는다.
      expect(promise, isNot(contains('"completed"')));
      expect(deact, isNot(contains('"completed"')));
      expect(raw, contains('근로기준법 제42조: 계약서 문서는 삭제 금지'));
    });

    test('WPM-B-03 teardown 이 서명 대기 계약을 무효화한다 — isLongTerm 무관', () {
      expect(_flat(deact), contains(
          '.where("status", "in", ["pending_employer", "pending_worker"])'));
      expect(_flat(deact), contains('status: "voided"'));
      expect(_flat(deact), contains('voidReason: "BUSINESS_DEACTIVATED"'));
      // preview 는 isLongTerm == true 만 센다 — teardown 은 전부 void 한다.
      // 그래서 서버 gate 도 isLongTerm 으로 좁히지 않는다.
      expect(_flat(preview), contains('.where("isLongTerm", "==", true)'));
      expect(promise, isNot(contains('isLongTerm')));
    });

    test('WPM-B-04 종결 상태를 과차단하지 않는다', () {
      for (final terminal in ['voided', 'expired', 'terminated']) {
        expect(promise, isNot(contains('"$terminal"')));
      }
    });

    test('WPM-B-05 사업장 영구 삭제는 별도 사건이다', () {
      // 탈퇴는 사업장을 삭제하지 않는다 — 비활성화만 한다.
      expect(finalFn, isNot(contains('businesses").doc(')));
      final del = _fn(raw, 'onBusinessDeleted');
      expect(del, contains('employment_contracts'));
      expect(_flat(del), contains('pending_employer'));
    });
  });

  group('WPM-C — 실근무 + 미계산 급여', () {
    test('WPM-C-01 공용 precondition 이 막는다 (W1)', () {
      expect(assertFn, contains('[WORKED_WAGE_UNCALCULATED]'));
      expect(_flat(assertFn), contains(
          'if (money.orphanWorkedUncalculated > 0) {'));
      expect(assertFn, contains('srvCountOrphanMoneyObligations(uid)'));
    });

    test('WPM-C-02 canonical actual-work 술어를 재사용한다 (W2)', () {
      // 새 정의를 만들지 않는다 — 노쇼·결근 제외가 그 안에 있다.
      expect(_flat(money), contains(
          'if (srvActualWorkReasonOf(att.data())) workedUncalculated++;'));
      final reason = _helper(raw, 'srvActualWorkReasonOf');
      expect(_flat(reason), contains(
          'if (ATTENDANCE_NON_WORK_STATUSES.includes(st)) return null;'));
      expect(code, contains(
          'const ATTENDANCE_NON_WORK_STATUSES = ["absent", "NO_SHOW"];'));
      expect(_flat(reason), contains(r'if (attData["checkIn"] != null) return "CHECKED_IN";'));
    });

    test('WPM-C-03 미래 예정 근무를 실근무로 오인하지 않는다 (W3)', () {
      expect(_flat(money), contains('.where("wageStatus", "==", "pending")'));
      expect(_flat(money), contains('.where("workDate", "<=", todayStartTs)'));
      expect(_flat(money), contains(
          'const todayStartTs = admin.firestore.Timestamp.fromMillis( '
          'srvKstDayStartMs(Date.now()));'));
    });

    test('WPM-C-04 successor 가 있으면 통과한다 (W4·W5)', () {
      // 급여 continuity 는 사업장 생존이 아니라 처리 권한의 생존이다.
      final seg = _between(money, 'if (!hasSuccessor)', 'return out');
      expect(_flat(seg), contains(
          'out.orphanWorkedUncalculated += workedUncalculated;'));
      expect(_count(money, 'out.orphanWorkedUncalculated +='), 1);
      expect(_flat(money), contains(
          '.where("permissions.canManageWage", "==", true)'));
      // 셋 다 0 일 때만 successor 판정을 건너뛴다.
      expect(_flat(money), contains(
          'if (pendingTransfer === 0 && unpaidWages === 0 && '
          'workedUncalculated === 0) continue;'));
    });

    test('WPM-C-05 기존 인덱스로 서빙된다 — 신규 index 0', () {
      // equality(businessId) + equality(wageStatus) + range(workDate) 는
      // 이 복합 인덱스의 prefix 다. 없으면 throw 가 fail closed 로 번져
      // 모든 관리자 탈퇴가 막힌다.
      final idx = _src('firestore.indexes.json');
      expect(_flat(idx), contains(_flat('''
        {
          "collectionGroup": "attendance",
          "queryScope": "COLLECTION",
          "fields": [
            { "fieldPath": "businessId", "order": "ASCENDING" },
            { "fieldPath": "wageStatus", "order": "ASCENDING" },
            { "fieldPath": "workDate", "order": "ASCENDING" }''')));
    });
  });

  group('WPM-D — 근로자 탈퇴 + 확정 미이체 급여', () {
    test('WPM-D-01 근로자 분기가 막는다 (P1)', () {
      expect(assertFn, contains('[PENDING_WAGES]'));
      expect(_flat(assertFn), contains(
          'const unpaidPayable = await srvCountWorkerUnpaidPayableWages(uid);'));
      expect(_flat(assertFn), contains('if (unpaidPayable > 0) {'));
      // 근로자 분기 안에 있다 — 관리자 분기와 섞지 않는다.
      expect(_at(assertFn, 'if (role !== "BUSINESS_ADMIN" && role !== "SUPER_ADMIN") {'),
          lessThan(_at(assertFn, '[PENDING_WAGES]')));
      expect(_at(assertFn, '[PENDING_WAGES]'),
          lessThan(_at(assertFn, '[INTERIM_SETTLEMENT_UNPROCESSED]')));
    });

    test('WPM-D-02 왜 영구 lock 인가 — 두 경로가 함께 닫힌다 (P2·P3)', () {
      // (1) 이체: 현재 버전이 0 으로 읽히고 확정 근거 버전과 불일치한다.
      final stale = _helper(raw, 'srvWageSnapshotStaleReason');
      expect(_flat(stale), contains('const cur = srvDocumentVersionsOf(user ?? {});'));
      expect(_flat(stale), contains(
          'if (srcAcc !== cur.account || srcBb !== cur.bankbook) { '
          'return XFER_STALE_PAYMENT_SNAPSHOT;'));
      final versions = _helper(raw, 'srvDocumentVersionsOf');
      expect(_flat(versions), contains(
          'const n = (v: unknown) => (typeof v === "number" && v >= 0 ? v : 0);'));
      // (2) 회복: readiness 가 계좌 없음으로 떨어져 갱신이 skip 된다.
      final readiness = _helper(raw, 'srvResolvePayrollReadiness');
      expect(_flat(readiness), contains(
          r'if (!u["bankName"] || !u["accountNumber"] || !u["accountHolder"]) { '
          'return no(PR_MISSING_BANK_ACCOUNT,'));
      final refresh = _flat(_fn(raw, 'callableRefreshWagePaymentSnapshot'));
      expect(refresh, contains('if (!pr.ready) { skipped[id] = pr.state; continue; }'));
    });

    test('WPM-D-03 기존 stale 안전장치를 약화시키지 않았다 (§13 금지·P5)', () {
      // "탈퇴한 사용자면 freshness 검사를 건너뛴다" 같은 예외가 없다.
      final stale = _helper(raw, 'srvWageSnapshotStaleReason');
      for (final bad in ['deleted', 'tombstone', 'exists', 'skip']) {
        expect(stale, isNot(contains(bad)));
      }
      // `user` 는 파라미터와 `?? {}` 두 곳에만 등장한다 — `if (user && …)`
      //   같은 조건부 우회가 끼어들면 이 수가 바뀐다.
      expect(_count(stale, 'user'), 2);
      expect(_flat(stale), contains(
          'if (srcAcc !== cur.account || srcBb !== cur.bankbook) { '
          'return XFER_STALE_PAYMENT_SNAPSHOT;'));
      // provenance 를 모르면 여전히 막는다.
      expect(_flat(stale), contains('return XFER_SNAPSHOT_PROVENANCE_UNKNOWN;'));
      // 그리고 이체 writer 가 그 판정을 **실제로** 본다.
      final transfer = _flat(_fn(raw, 'callableMarkTransferredBatch'));
      expect(transfer, contains('const staleReason = srvWageSnapshotStaleReason('));
      expect(transfer, contains('if (staleReason) {'));
      expect(transfer, contains('blocked[id] = staleReason;'));
      // 4필드 완전성 판정도 그대로다.
      final blockReason = _helper(raw, 'srvWageAccountBlockReason');
      expect(_flat(blockReason), contains(
          r'if (data["wageAccountSnapshotVersion"] !== 1) return XFER_LEGACY_NO_SNAPSHOT;'));
    });

    test('WPM-D-04 이미 보낸 돈은 blocker 가 아니다 (P4)', () {
      expect(_flat(workerWage), contains(
          '(["calculated", "confirmed"] as const).map((ws) =>'));
      expect(workerWage, isNot(contains('"transferred"')));
      expect(workerWage, isNot(contains('"pending"')));
    });

    test('WPM-D-05 보낼 돈이 0원인 건으로 막지 않는다 (P8)', () {
      // 노쇼·결근은 finalWage 0 으로 confirmed 가 된다. 해소할 방법이
      // 없는 blocker 를 만들지 않는다.
      expect(_flat(workerWage), contains('if (srvIsNonPayableZero('));
      final nonPayable = _helper(raw, 'srvIsNonPayableZero');
      expect(_flat(nonPayable), contains(
          'return (status === "NO_SHOW" || status === "absent") && '
          '((finalWage ?? 0) === 0);'));
    });

    test('WPM-D-06 cross-business 를 섞지 않는다 (P7)', () {
      expect(_count(workerWage, '.where("userId", "==", uid)'), 1);
      expect(workerWage, isNot(contains('businessId')));
      expect(workerWage, isNot(contains('collectionGroup')));
    });

    test('WPM-D-07 회복 경로의 권한·전제와 모순되지 않는다 (P6)', () {
      // 갱신은 canManageWage 관리자만, 그리고 readiness READY 일 때만이다.
      // 근로자 본인은 그것을 할 수 없다 — 그래서 Option A(선지급 후 탈퇴)다.
      final refresh = _flat(_fn(raw, 'callableRefreshWagePaymentSnapshot'));
      expect(refresh, contains('if (!perms.canManageWage) {'));
      expect(refresh, contains(r'if (d.wageStatus !== "confirmed") {'));
    });
  });

  group('WPM-PAR — preview ↔ server parity', () {
    test('WPM-PAR-01 근로자 preview 가 같은 helper 를 쓰고 hardBlock 이다', () {
      expect(preview, contains('srvCountWorkerUnpaidPayableWages(callerUid)'));
      expect(_flat(preview), contains(
          'hardBlocks.push({type: "PENDING_WAGES", count: pendingWageCount});'));
      // warning 으로 남아 있지 않다 — 두 곳에서 다른 결론을 내지 않는다.
      expect(_flat(preview), isNot(contains(
          'warnings.push({type: "PENDING_WAGES"')));
      // 선언 1 + 호출 2(precondition·preview) = 3.
      expect(_count(code, 'srvCountWorkerUnpaidPayableWages'), 3);
    });

    test('WPM-PAR-02 관리자 preview 에 WORKED_WAGE_UNCALCULATED 가 있다', () {
      expect(_flat(preview), contains(
          'if (orphanInterim.orphanWorkedUncalculated > 0) { hardBlocks.push({ '
          'type: "WORKED_WAGE_UNCALCULATED",'));
      // 같은 helper 한 번 호출로 세 blocker 를 모두 만든다.
      expect(_count(preview, 'srvCountOrphanMoneyObligations'), 1);
    });

    test('WPM-PAR-03 클라이언트가 두 신규 code 를 설명한다', () {
      final s = _src('lib/screens/common/settings_screen.dart');
      expect(s, contains("'WORKED_WAGE_UNCALCULATED' =>"));
      expect(s, contains('급여 계산 전 완료 근무 \$n건'));
      expect(s, contains("'PENDING_WAGES' =>"));
      expect(s, contains('받지 못한 급여 \$n건'));
      // 승격됐으므로 warning 라벨에는 더 이상 없다.
      final warnSeg = _between(s, 'String warnLabel(', 'String? blockNavKey(');
      expect(warnSeg, isNot(contains('PENDING_WAGES')));
      // 문구를 섞지 않는다 — 정산 개시 건과 계산 전 건은 할 일이 다르다.
      expect(s, contains("'UNPAID_WAGES' => '미확정/미이체 급여 \$n건'"));
    });

    test('WPM-PAR-04 삭제 writer 는 preview 에 의존하지 않는다', () {
      expect(_fn(raw, 'callableDeleteAccountPreData'),
          isNot(contains('callableGetWithdrawBlockers')));
      expect(finalFn, isNot(contains('callableGetWithdrawBlockers')));
      expect(assertFn, isNot(contains('callableGetWithdrawBlockers')));
    });

    test('WPM-PAR-05 gate 가 파괴보다 앞이다', () {
      expect(_at(finalFn, 'srvAssertAccountDeletionAllowed('),
          lessThan(_at(finalFn, 'userRef.delete()')));
      final pre = _fn(raw, 'callableDeleteAccountPreData');
      expect(_at(pre, 'srvAssertAccountDeletionAllowed('),
          lessThan(_at(pre, 'srvEnsureAccountDeletionTombstone(')));
    });
  });

  group('WPM-ERR — 쿼리 실패 ≠ 0건 (W6)', () {
    test('WPM-ERR-01 세 helper 모두 오류를 삼키지 않는다', () {
      for (final h in [promise, money, workerWage]) {
        expect(h, isNot(contains('catch')));
        expect(h, isNot(contains('?? 0')));
        expect(h, isNot(contains('queryFailed')));
      }
    });

    test('WPM-ERR-02 precondition 이 그 throw 를 가로채지 않는다', () {
      expect(assertFn, isNot(contains('catch')));
      final seg = _between(assertFn,
          'srvCountWithdrawPromiseScope(uid)', '[CONFIRMED_WORKERS]');
      expect(seg, isNot(contains('?? 0')));
    });

    test('WPM-ERR-03 helper 는 읽기 전용이다 — 통과시키려고 상태를 바꾸지 않는다', () {
      for (final h in [promise, money, workerWage]) {
        for (final bad in ['.update(', '.set(', '.delete()',
          'status: "CANCELED"', 'wageStatus:']) {
          expect(h, isNot(contains(bad)));
        }
      }
    });
  });
}
