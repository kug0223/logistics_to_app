// [R7-P4.4E.11C.0C.0a.6] 승인된 돈인데 끝낼 사람이 사라졌다
//
// `APPROVED` 중간정산은 이미 승인된 지급 의무다. 그런데 그것을 `PROCESSED`
// 로 끝내는 것은 조회가 아니라 권한 있는 actor 의 operation 이다.
//
//   단독 관리자 탈퇴
//   → 사업장 비활성화(`deactivatedAt`)
//   → 그 사업장 정산을 처리할 일반 제품 actor 0
//   → 승인된 돈이 영구히 미지급
//
// 그리고 금전 blocker 는 **서버 삭제 경계에 하나도 없었다.**
// `callableGetWithdrawBlockers` 는 클라이언트 preview 전용이라, 직접 호출이든
// 구버전 client 든 그대로 통과했다.
//
// 이번 Phase 의 invariant:
//
//   APPROVED 미이체가 있으면
//   → 그것을 끝낼 **운영 가능한** 주인이 반드시 남아야 한다
//   → 남지 않으면 계정 삭제는 FAIL CLOSED
//
// 역할 이름으로 판단하지 않는다. SUPER_ADMIN 은 서버 guard 는 통과하지만
// 제품 UI 에 남의 사업장 정산으로 들어가는 경로가 없다 — emergency
// authority 이지 normal continuity 가 아니다.
//
// 고정하는 것
//   ISC-LIFE-*   lifecycle / 전이 / 권한 술어
//   ISC-GATE-*   서버 삭제 경계의 blocker
//   ISC-SUCC-*   successor 판정이 capability 기준
//   ISC-RACE-*   approve/freeze/process 경쟁
//   ISC-ERR-*    쿼리 실패 ≠ 0건
//   ISC-SCOPE-*  multi-business
//   ISC-TRUTH-*  money truth 자동변조 0
//   ISC-UI-*     preview ↔ Final parity + 실제 처리 가능한 화면
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
  final helper = _helper(raw, 'srvCountOrphanApprovedSettlements');
  final assertFn = _helper(raw, 'srvAssertAccountDeletionAllowed');

  group('ISC-LIFE — lifecycle / 전이 / 권한 술어', () {
    test('ISC-LIFE-01 상태 전이 writer 가 그대로다', () {
      // PENDING → APPROVED / REJECTED, APPROVED → PROCESSED / CANCELED.
      final approve = _fn(raw, 'callableApproveInterimSettlement');
      expect(_flat(approve), contains(r'if (rd.status !== "PENDING")'));
      expect(_flat(approve), contains('status: "APPROVED"'));
      final reject = _fn(raw, 'callableRejectInterimSettlement');
      expect(_flat(reject), contains(r'if (reqData.status !== "PENDING")'));
      expect(_flat(reject), contains('status: "REJECTED"'));
      final process = _fn(raw, 'callableProcessInterimSettlement');
      expect(_flat(process), contains(r'if (rd.status !== "APPROVED")'));
      expect(_flat(process), contains('status: "PROCESSED"'));
      final cancel = _fn(raw, 'callableCancelApprovedInterimSettlement');
      expect(_flat(cancel), contains(r'if (rd.status !== "APPROVED")'));
      expect(_flat(cancel), contains('status: "CANCELED"'));
    });

    test('ISC-LIFE-02 APPROVED → PROCESSED 권한 술어', () {
      // SUPER_ADMIN · adminIds/ownerId 구성원 · canManageWage 서브관리자.
      final process = _flat(_fn(raw, 'callableProcessInterimSettlement'));
      expect(process, contains('assertBizAdmin(callerUid, d.businessId)'));
      expect(process, contains('!== "SUPER_ADMIN"'));
      expect(process, contains('processAdminIds.includes(callerUid)'));
      expect(process, contains('processPerms.canManageWage !== true'));
    });

    test('ISC-LIFE-03 blocker helper 가 **같은** capability 술어를 쓴다', () {
      // 판정이 갈라지면 "서버는 처리 가능한데 삭제가 막히는" 상태가 된다.
      expect(helper, contains('adminIds'));
      expect(helper, contains('ownerId'));
      expect(_flat(helper),
          contains('.where("permissions.canManageWage", "==", true)'));
    });
  });

  group('ISC-GATE — 서버 삭제 경계의 blocker', () {
    test('ISC-GATE-01 공용 precondition 에 금전 blocker 가 있다', () {
      // PreData(BEGIN)와 Final 이 같은 helper 를 쓴다 — 파괴 전에 막힌다.
      expect(assertFn, contains('srvCountOrphanApprovedSettlements(uid)'));
      expect(assertFn, contains('INTERIM_SETTLEMENT_UNPROCESSED'));
      // 두 호출부가 모두 이 precondition 을 거친다.
      expect(_fn(raw, 'callableDeleteAccountPreData'),
          contains('srvAssertAccountDeletionAllowed('));
      expect(_fn(raw, 'callableDeleteAccountFinal'),
          contains('srvAssertAccountDeletionAllowed('));
    });

    test('ISC-GATE-02 관리자 역할에만 적용되고, 조건이 무력화되지 않았다', () {
      // 근로자 탈퇴를 불필요하게 다시 막지 않는다 — 근로자는 processing
      // authority 가 아니고, 정산 금액·근태 truth 는 보존된다.
      //
      // 그런데 "guard 가 존재한다" 만 보면 `if (false && …)` 같은 단축
      // 무력화를 놓친다. 그래서 조건식 **모양**을 그대로 고정한다.
      expect(_flat(assertFn), contains(
          'if (role === "BUSINESS_ADMIN" || role === "SUPER_ADMIN") { '
          'const interim = await srvCountOrphanApprovedSettlements(uid);'));
      // 상수 단축이 끼어들지 않는다.
      expect(assertFn, isNot(contains('false &&')));
      expect(assertFn, isNot(contains('&& false')));
      expect(assertFn, isNot(contains('true ||')));
    });

    test('ISC-GATE-03 blocker 는 던진다 — 조용히 통과하지 않는다', () {
      final seg = _between(assertFn, 'INTERIM_SETTLEMENT_UNPROCESSED', '}');
      expect(_flat(assertFn), contains('throw new HttpsError( "failed-precondition", '
          '"[INTERIM_SETTLEMENT_UNPROCESSED] 승인된 중간정산 "'));
      expect(seg, isNot(contains('return')));
    });

    test('ISC-GATE-04 APPROVED 만 센다 — terminal 상태는 막지 않는다', () {
      expect(_flat(helper), contains('.where("status", "==", "APPROVED")'));
      for (final terminal in ['"PROCESSED"', '"REJECTED"', '"CANCELED"']) {
        expect(helper, isNot(contains(terminal)),
            reason: '$terminal 은 정상 종결 상태다 — 삭제를 막아선 안 된다');
      }
    });

    test('ISC-GATE-05 비활성화된 사업장은 세지 않는다', () {
      // 이 탈퇴가 만드는 상태가 아니다 — 기존 blocker 관례와 같은 필터.
      expect(_flat(helper), contains(r'!d.data()["deactivatedAt"]'));
    });
  });

  group('ISC-SUCC — successor 판정이 capability 기준이다', () {
    test('ISC-SUCC-01 역할 이름이 아니라 capability 로 후보를 모은다', () {
      final seg = _between(helper, 'const candidates', 'let hasSuccessor');
      expect(seg, contains('adminIds'));
      expect(seg, contains('ownerId'));
      expect(seg, contains('permissions.canManageWage'));
      // 자기 자신은 후보가 아니다.
      expect(_count(seg, '!== uid'), greaterThanOrEqualTo(3));
    });

    test('ISC-SUCC-02 쓸 수 없는 계정은 successor 가 아니다', () {
      final seg = _between(helper, 'let hasSuccessor', 'if (!hasSuccessor)');
      expect(seg, contains('s.exists'));
      expect(seg, contains('accountStatus'));
      expect(seg, contains('isBlacklisted'));
      expect(_flat(seg), contains('status === "active"'));
    });

    test('ISC-SUCC-03 SUPER_ADMIN 존재만으로 통과시키지 않는다', () {
      // helper 는 SUPER_ADMIN 을 후보로 수집하지 않는다. 제품 UI 에 남의
      // 사업장 정산으로 들어가는 경로가 없기 때문이다(backend-only).
      expect(helper, isNot(contains('SUPER_ADMIN')));
      expect(helper, isNot(contains("role")));
    });

    test('ISC-SUCC-04 SUPER_ADMIN 에게 제품 route 가 없다는 근거', () {
      // 모든 급여 대시보드 진입이 **호출자 자신의** 사업장 id 를 넘긴다.
      final picker = _src('lib/utils/business_picker_helper.dart');
      expect(picker, contains('subAdminBusinessIds'));
      expect(picker, contains('managedBusinessIds'));
      // 비활성 사업장을 보여주는 유일한 SUPER_ADMIN 화면에 push 가 없다.
      final allBiz = _src('lib/screens/super_admin/all_businesses_screen.dart');
      expect(allBiz, contains('deactivatedAt'));
      expect(allBiz, isNot(contains('PayrollPaymentDashboardScreen')));
    });

    test('ISC-SUCC-05 서브관리자 본인은 애초에 탈퇴할 수 없다', () {
      // 유일한 canManageWage 주체가 서브관리자인 경우는 이미 닫혀 있다.
      expect(assertFn, contains('subAdminBusinessIds'));
      expect(_flat(assertFn), contains('서브관리자로 등록된 사업장'));
    });
  });

  group('ISC-RACE — approve / freeze / process 경쟁', () {
    test('ISC-RACE-01 freeze 이후 본인은 승인할 수 없다', () {
      // `assertBizAdmin` 이 accountStatus active 가 아닌 호출자를 거부한다.
      final ab = _helper(raw, 'assertBizAdmin');
      expect(_flat(ab), contains(r'if (accountStatus !== undefined && accountStatus !== "active")'));
      // 그래서 freeze(=deleting) 이후 본인 승인으로 새 APPROVED 가 생기지 않는다.
      expect(code, contains('ACCOUNT_STATUS_DELETING'));
    });

    test('ISC-RACE-02 다른 사람이 승인할 수 있다면 그 사람이 successor 다', () {
      // 승인은 같은 capability 를 요구하므로, 승인 가능한 actor 가 있다는
      // 것은 처리 가능한 actor 가 있다는 것과 같다 — orphan 이 생기지 않는다.
      final approve = _flat(_fn(raw, 'callableApproveInterimSettlement'));
      expect(approve, contains('approvePerms.canManageWage !== true'));
      final process = _flat(_fn(raw, 'callableProcessInterimSettlement'));
      expect(process, contains('processPerms.canManageWage !== true'));
    });

    test('ISC-RACE-03 process 가 먼저 commit 되면 삭제가 통과한다', () {
      // helper 는 **현재** APPROVED 만 센다 — 캐시나 미리 읽은 값이 아니다.
      expect(_flat(helper), contains('.count() .get()'));
      expect(helper, isNot(contains('cached')));
    });

    test('ISC-RACE-04 blocker 가 파괴보다 앞이다', () {
      final fin = _fn(raw, 'callableDeleteAccountFinal');
      expect(_at(fin, 'srvAssertAccountDeletionAllowed('),
          lessThan(_at(fin, 'userRef.delete()')));
      expect(_at(fin, 'srvAssertAccountDeletionAllowed('),
          lessThan(_at(fin, 'admin.auth().deleteUser(uid)')));
      // PreData 도 freeze 보다 앞에서 막는다 — 아무것도 파괴되지 않는다.
      final pre = _fn(raw, 'callableDeleteAccountPreData');
      expect(_at(pre, 'srvAssertAccountDeletionAllowed('),
          lessThan(_at(pre, 'srvEnsureAccountDeletionTombstone(')));
    });
  });

  group('ISC-ERR — 쿼리 실패 ≠ 0건', () {
    test('ISC-ERR-01 helper 가 오류를 삼키지 않는다', () {
      expect(helper, isNot(contains('catch')));
      expect(helper, isNot(contains('queryFailed')));
    });

    test('ISC-ERR-02 precondition 이 그 throw 를 가로채지 않는다', () {
      final seg = _between(
          assertFn, 'srvCountOrphanApprovedSettlements', 'INTERIM_SETTLEMENT_UNPROCESSED');
      expect(seg, isNot(contains('catch')));
      expect(seg, isNot(contains('?? 0')));
    });

    test('ISC-ERR-03 preview 도 오류를 0건으로 바꾸지 않는다', () {
      final blockers = _fn(raw, 'callableGetWithdrawBlockers');
      final seg = _between(blockers,
          'const orphanInterim = await srvCountOrphanApprovedSettlements',
          'hardBlocks.push');
      expect(seg, isNot(contains('catch')));
      // 클라이언트는 preview 실패 시 삭제 버튼을 비활성화한다.
      final settings = _src('lib/screens/common/settings_screen.dart');
      expect(_flat(settings), contains(
          'onPressed: (hardBlocks.isEmpty && !isLoading && cfError == null)'));
    });
  });

  group('ISC-SCOPE — multi-business', () {
    test('ISC-SCOPE-01 사업장별로 독립 판정하고 하나라도 orphan 이면 막는다', () {
      // Business A 가 orphan 이면 B 가 정상이어도 계정 삭제는 막힌다.
      expect(_flat(helper), contains('for (const biz of live)'));
      expect(_flat(helper), contains('out.orphanBusinesses++'));
      expect(_flat(assertFn), contains('if (interim.orphanApproved > 0)'));
    });

    test('ISC-SCOPE-02 다른 사업장의 정산과 섞지 않는다', () {
      expect(_flat(helper), contains(r'.where("businessId", "==", biz.id)'));
      // 전체 컬렉션 스캔이나 whereIn 혼합이 없다.
      expect(helper, isNot(contains('array-contains-any')));
      expect(_count(helper, '.where("businessId"'), 1);
    });
  });

  group('ISC-TRUTH — money truth 자동변조 0', () {
    test('ISC-TRUTH-01 blocker 경로가 정산 문서를 쓰지 않는다', () {
      // 삭제를 통과시키려고 상태를 바꾸거나 금액을 0 으로 만들지 않는다.
      for (final bad in [
        'status: "PROCESSED"',
        'status: "CANCELED"',
        'netAmount: 0',
        '.delete()',
        '.update(',
        '.set(',
      ]) {
        expect(helper, isNot(contains(bad)), reason: 'helper 는 읽기 전용이어야 한다');
      }
      final seg = _between(
          assertFn, 'srvCountOrphanApprovedSettlements', 'INTERIM_SETTLEMENT_UNPROCESSED');
      expect(seg, isNot(contains('interim_settlement_requests')));
    });

    test('ISC-TRUTH-02 승인 취소는 기존 canonical writer 뿐이다', () {
      // APPROVED → CANCELED 는 제품 경로가 이미 있다(관리자가 명시적으로).
      // 삭제 gate 가 그것을 자동 수행하지 않는다.
      expect(code, contains('export const callableCancelApprovedInterimSettlement'));
      expect(assertFn, isNot(contains('CancelApprovedInterimSettlement')));
    });
  });

  group('ISC-UI — preview ↔ Final parity + 처리 가능한 화면', () {
    test('ISC-UI-01 preview 와 Final 이 같은 술어를 쓴다', () {
      // 호출부 2곳 + 선언 1 = 3.
      expect(_count(code, 'srvCountOrphanApprovedSettlements'), 3);
      expect(_fn(raw, 'callableGetWithdrawBlockers'),
          contains('srvCountOrphanApprovedSettlements(callerUid)'));
      expect(assertFn, contains('srvCountOrphanApprovedSettlements(uid)'));
    });

    test('ISC-UI-02 blocker 가 사용자에게 설명된다', () {
      final s = _src('lib/screens/common/settings_screen.dart');
      expect(s, contains("'INTERIM_SETTLEMENT_UNPROCESSED' =>"));
      expect(s, contains('승인된 중간정산 \$n건 미이체'));
      // "승인 대기"(INTERIM_PENDING)와 문구를 섞지 않는다.
      expect(s, contains("'INTERIM_PENDING' => '중간정산 승인 대기 \$n건'"));
    });

    test('ISC-UI-03 그 화면에서 APPROVED 행이 실제로 보인다', () {
      // PENDING 필터를 끈 경로로 보낸다 — 그러지 않으면 막힌 이유를
      // 말해 놓고 그 일을 할 화면이 비어 있다.
      final s = _src('lib/screens/common/settings_screen.dart');
      expect(s, contains("'INTERIM_SETTLEMENT_UNPROCESSED' => 'payroll_interim_approved'"));
      expect(s, contains("case 'payroll_interim_approved':"));
      expect(_flat(s), contains(
          "showPendingSettlementOnly: navTarget != 'payroll_interim_approved'"));
    });

    test('ISC-UI-04 APPROVED 행에 이체 처리 CTA 가 있다', () {
      final dash = _src(
          'lib/screens/business_admin/payroll/payroll_payment_dashboard_screen.dart');
      expect(_flat(dash),
          contains('onProcess: req.isApproved ? () => _processSettlement(req) : null'));
      // 그리고 그 화면 진입은 canManageWage 로 fail-closed 다.
      expect(_flat(dash), contains('if (perms == null || !perms.canManageWage)'));
    });
  });
}
