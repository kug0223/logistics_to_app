// [R5-RESIDUAL.1] 급여 집계 존재 여부 누설 계약.
//
//   지키는 문장은 하나다.
//
//     권한 없는 사람에게 "있음"과 "없음"은 같은 답이어야 한다.
//
//   금액을 못 보더라도 "그 사업장 그 달의 집계가 존재하는가"를 알아낼 수
//   있으면 그것도 정보다. 예전 rule 은 없는 문서의 get 을 로그인한 누구에게나
//   성공시켰고, 있는 문서는 권한 없으면 거절했다. 두 답이 달랐다.
//
//   rule 판정은 Dart 로 재구현해 matrix 를 직접 고정하고(순수 함수),
//   rule·consumer 배선은 소스 문자열로 고정한다.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _codeOf(String src) => src
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

// ─────────────────────────────────────────────────────────────
// rule 판정 — payroll_summaries get 게이트와 같은 식
// ─────────────────────────────────────────────────────────────

const _bizA = 'BIZ_A';

class Actor {
  const Actor(this.uid, {this.role = 'USER', this.subs = const <String>[]});
  final String uid;
  final String role;
  final List<String> subs;
}

const _owner = Actor('u_owner', role: 'BUSINESS_ADMIN');
const _superA = Actor('u_super', role: 'SUPER_ADMIN');
const _wageSub = Actor('u_wage', subs: <String>[_bizA]);
const _noWageSub = Actor('u_nowage', subs: <String>[_bizA]);
const _worker = Actor('u_worker');
// 다른 사업장에서는 급여 권한을 가진 사람.
const _wrongBizWage = Actor('u_other_wage', subs: <String>['BIZ_B']);

const _perms = <String, Map<String, bool>>{
  'u_wage': <String, bool>{'canManageWage': true},
  'u_nowage': <String, bool>{'canManageWorkers': true},
  'u_other_wage': <String, bool>{'canManageWage': true},
};

/// 문서가 있을 때의 판정. 없으면 `resource` 가 없어 이 식을 쓸 수 없다 —
///   그것이 이번 수정의 핵심이다.
bool ruleAllowsExisting(Actor a, String docBusinessId) {
  if (a.role == 'SUPER_ADMIN') return true;
  if (a.role == 'BUSINESS_ADMIN' && docBusinessId == _bizA) return true;
  final isSub = a.subs.contains(docBusinessId);
  if (!isSub) return false;
  return (_perms[a.uid] ?? const <String, bool>{})['canManageWage'] == true;
}

/// 문서가 없을 때의 판정.
///   패치 전: 로그인만 했으면 통과(resource == null 분기).
///   패치 후: 판정할 근거가 없으므로 통과하지 않는다.
bool ruleAllowsMissingBefore(Actor a) => true; // 로그인 전제
bool ruleAllowsMissingAfter(Actor a) => false;

void main() {
  late String rules;
  late String screen;

  setUpAll(() {
    rules = _codeOf(File('firestore.rules').readAsStringSync());
    screen = _codeOf(File(
      'lib/screens/business_admin/payroll/payroll_overview_screen.dart',
    ).readAsStringSync());
  });

  // ───────────────────────────────────────────────────────────
  group('O-1x direct get matrix (§10)', () {
    test('A 급여 권한자 + 존재 → ALLOW', () {
      expect(ruleAllowsExisting(_owner, _bizA), isTrue);
      expect(ruleAllowsExisting(_wageSub, _bizA), isTrue);
    });

    test('H SUPER_ADMIN 은 그대로다', () {
      expect(ruleAllowsExisting(_superA, _bizA), isTrue);
      expect(ruleAllowsExisting(_superA, 'BIZ_B'), isTrue);
    });

    test('B·C wage 없는 SubAdmin — 존재/부재가 같은 답이다', () {
      expect(ruleAllowsExisting(_noWageSub, _bizA), isFalse);
      expect(ruleAllowsMissingAfter(_noWageSub), isFalse);
      expect(ruleAllowsExisting(_noWageSub, _bizA),
          ruleAllowsMissingAfter(_noWageSub),
          reason: '두 답이 다르면 존재 여부가 새어 나간다');
    });

    test('D·E 근로자 — 존재/부재가 같은 답이다', () {
      expect(ruleAllowsExisting(_worker, _bizA), isFalse);
      expect(ruleAllowsMissingAfter(_worker), isFalse);
      expect(ruleAllowsExisting(_worker, _bizA),
          ruleAllowsMissingAfter(_worker));
    });

    test('F·G 다른 사업장 급여 권한자 — 존재/부재가 같은 답이다', () {
      expect(ruleAllowsExisting(_wrongBizWage, _bizA), isFalse);
      expect(ruleAllowsMissingAfter(_wrongBizWage), isFalse);
      expect(ruleAllowsExisting(_wrongBizWage, _bizA),
          ruleAllowsMissingAfter(_wrongBizWage));
    });

    test('패치 전에는 세 쌍 모두 답이 달랐다 — 그것이 oracle 이었다', () {
      for (final a in <Actor>[_noWageSub, _worker, _wrongBizWage]) {
        expect(ruleAllowsExisting(a, _bizA), isFalse, reason: a.uid);
        expect(ruleAllowsMissingBefore(a), isTrue, reason: a.uid);
      }
    });
  });

  // ───────────────────────────────────────────────────────────
  group('O-2x rule 배선 (§7·§3)', () {
    test('resource == null 허용이 사라졌다', () {
      final i = rules.indexOf('match /payroll_summaries/{summaryId}');
      expect(i, greaterThan(-1));
      final block = rules.substring(i, rules.indexOf('allow list', i));
      expect(block.contains('resource == null'), isFalse,
          reason: '없는 문서를 누구에게나 열어 주면 존재 여부가 새어 나간다');
      expect(block.contains('subAdminCanManageWage'), isTrue,
          reason: '급여 권한을 약화하지 않았다');
      expect(block.contains('isSuperAdmin()'), isTrue);
    });

    test('§3-A 문서 id 를 쪼개지 않았다', () {
      final i = rules.indexOf('match /payroll_summaries/{summaryId}');
      final block = rules.substring(i, i + 3000);
      expect(block.contains('summaryId.split('), isFalse,
          reason: 'businessId 에 _ 가 들어갈 수 있어 권위가 없다');
      expect(block.contains("summaryId.matches("), isFalse);
    });

    test('§14 list 권한을 넓히지 않았다', () {
      final i = rules.indexOf('match /payroll_summaries/{summaryId}');
      final block = rules.substring(i, i + 3000);
      expect(block.contains('allow list: if isSuperAdmin();'), isTrue);
      expect(block.contains('allow write: if false;'), isTrue);
    });

    test('workers 서브컬렉션·money_audit 계약이 그대로다', () {
      expect(rules.contains('isPayrollSummaryAdmin(summaryId)'), isTrue);
      final h = rules.indexOf('function isPayrollSummaryAdmin(summaryId)');
      expect(rules.substring(h, h + 400).contains('subAdminCanManageWage'),
          isTrue);
      expect(rules.contains('match /money_audit/{eventId}'), isTrue,
          reason: 'H 의 감사 규칙을 건드리지 않았다');
    });
  });

  // ───────────────────────────────────────────────────────────
  group('O-3x optional read 를 서버로 옮겼다 (§6·§8·§9)', () {
    test('새로고침이 직접 문서 get 을 쓰지 않는다', () {
      // 새로고침은 canonical 급여 reader 를 재사용한다 — 새 API 를 만들지 않았다.
      final i = screen.indexOf('Future<void> _refreshSummary()');
      expect(i, greaterThan(-1));
      // 창이 다음 메서드로 넘치면 그쪽 직접 접근을 잡아 오진한다.
      final end = screen.indexOf('Future<void> _loadWorkers()', i);
      expect(end, greaterThan(i));
      final body = screen.substring(i, end);
      expect(body.contains("httpsCallable('callableGetPayrollSummaries'"), isTrue);
      expect(body.contains("collection('payroll_summaries')"), isFalse,
          reason: '있을 수도 없을 수도 있는 조회는 서버가 판정해야 한다');
      // 화면 전체에서 이 컬렉션 직접 접근은 workers 로더 하나만 남는다.
      expect("collection('payroll_summaries')".allMatches(screen).length, 1);
    });

    test('§8 없음은 정상이다 — 들고 있던 값을 빈 값으로 덮지 않는다', () {
      final i = screen.indexOf('Future<void> _refreshSummary()');
      final body = screen.substring(i, i + 2200);
      expect(body.contains('if (hit.isEmpty) return;'), isTrue);
    });

    test('§9 없음·권한 없음·실패를 각각 다르게 다룬다', () {
      final i = screen.indexOf('Future<void> _refreshSummary()');
      final body = screen.substring(i, i + 2200);
      expect(body.contains('on FirebaseFunctionsException catch (e)'), isTrue);
      expect(body.contains("e.code == 'permission-denied'"), isTrue);
      expect(body.contains('급여 정보를 볼 권한이 없습니다'), isTrue);
      expect(body.contains('새로고침에 실패했습니다'), isTrue);
    });

    test('§9 PERMISSION_DENIED 를 "집계 없음"으로 바꾸지 않았다', () {
      final i = screen.indexOf('Future<void> _refreshSummary()');
      final body = screen.substring(i, i + 2200);
      // 권한 오류 분기가 조용한 return 으로 끝나지 않는다.
      final permIdx = body.indexOf("e.code == 'permission-denied'");
      final absentIdx = body.indexOf('if (hit.isEmpty) return;');
      expect(absentIdx, lessThan(permIdx),
          reason: '없음 처리와 권한 처리가 별개 경로여야 한다');
      expect(body.contains('ToastHelper.showError'), isTrue);
    });

    test('workers 로더는 그대로다 — 이미 부재를 권한 거부로 받는다', () {
      // 이 경로는 부모 문서가 없으면 isPayrollSummaryAdmin 이 false 가 되어
      //   권한 거부를 받는다. 즉 존재/부재가 원래부터 같은 답이었다.
      //   조용히 실패하고 복원 버튼으로 넘기는 기존 처리를 유지한다.
      final i = screen.indexOf('Future<void> _loadWorkers()');
      expect(i, greaterThan(-1));
      final body = screen.substring(i, i + 1400);
      expect(body.contains("collection('payroll_summaries')"), isTrue);
      expect(body.contains("collection('workers')"), isTrue);
      expect(body.contains('_workersLoading = false'), isTrue);
      expect(body.contains('ToastHelper.showError'), isFalse,
          reason: '부재를 오류로 말하지 않는 기존 동작 유지');
    });
  });

  // ───────────────────────────────────────────────────────────
  group('O-4x 앞선 closure 보존 (§15)', () {
    test('D-1 급여 자격이 그대로다', () {
      final cf = _codeOf(File('functions/src/index.ts').readAsStringSync());
      for (final f in <String>[
        'export const callableGetPayrollSummaries',
        'export const callableRepairPayrollSummaries',
        'export const callableGetNotTransferredCount',
      ]) {
        final i = cf.indexOf(f);
        expect(i, greaterThan(-1), reason: f);
        final n = cf.indexOf('\nexport const ', i + 10);
        expect(cf.substring(i, n > 0 ? n : cf.length)
            .contains('srvAssertWageAuthority('), isTrue, reason: f);
      }
    });

    test('.6-P1 payable population·H 감사가 그대로다', () {
      final cf = _codeOf(File('functions/src/index.ts').readAsStringSync());
      expect(cf.contains('function srvPayableForTransfer('), isTrue);
      expect(cf.contains('function srvWriteMoneyAudit('), isTrue);
    });
  });
}
