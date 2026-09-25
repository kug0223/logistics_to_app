// [R5-PATCH-01 / D-1] 급여 권한 · TO 초대 취소 권한 계약.
//
//   지키는 문장은 하나다.
//
//     같은 사업장 · 같은 행위는 callable 로 하든 직접 읽든 같은 답을 낸다.
//
//   권한 판정은 Dart 로 재구현해 matrix 를 직접 고정하고(순수 함수),
//   어느 문이 어느 판정을 쓰는지는 소스 문자열로 고정한다.
//   둘 다 없으면 한쪽만 고쳐도 통과한다.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// 주석을 걷어낸 코드만 본다. 마커가 주석에만 있으면 계약이 아니다.
String _codeOf(String src) => src
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

/// [name] 선언부터 다음 export 직전까지. 함수가 길어 고정 길이로는 모자란다.
String _fn(String src, String name) {
  final i = src.indexOf(name);
  expect(i, greaterThan(-1), reason: '$name 을 찾지 못했다');
  final n = src.indexOf('\nexport const ', i + 10);
  return src.substring(i, n > 0 ? n : src.length);
}

// ─────────────────────────────────────────────────────────────
// 권한 판정 — 서버 srvAssertWageAuthority / srvAssertToAuthority 와 같은 식
// ─────────────────────────────────────────────────────────────

/// 한 호출자가 한 사업장에 대해 갖는 사실들.
class Actor {
  const Actor({
    required this.uid,
    this.role = 'USER',
    this.accountStatus,
    this.subAdminBusinessIds = const <String>[],
    this.subAdminOf = '',
  });

  final String uid;
  final String role;
  final String? accountStatus;
  final List<String> subAdminBusinessIds;
  final String subAdminOf;
}

/// 사업장 한 곳의 사실들.
class Biz {
  const Biz({
    required this.id,
    this.ownerId,
    this.adminIds = const <String>[],
    this.memberPerms = const <String, Map<String, bool>>{},
    this.exists = true,
  });

  final String id;
  final String? ownerId;
  final List<String> adminIds;
  final Map<String, Map<String, bool>> memberPerms;
  final bool exists;
}

/// 거절 사유. null 이면 통과.
String? assertBizAdmin(Actor a, Biz b, String targetBusinessId) {
  if (a.role == 'SUPER_ADMIN') return null;
  if (a.accountStatus != null && a.accountStatus != 'active') {
    return 'pending-account';
  }
  if (!b.exists) return 'not-found';
  final isMember = b.adminIds.contains(a.uid) ||
      b.ownerId == a.uid ||
      a.subAdminBusinessIds.contains(targetBusinessId) ||
      (a.subAdminOf.isNotEmpty && a.subAdminOf == targetBusinessId);
  return isMember ? null : 'not-member';
}

/// capability 한 개를 요구하는 권한 판정. 서버 두 helper 가 이 모양이다.
String? assertCapability(
  Actor a,
  Biz b,
  String targetBusinessId,
  String capability,
) {
  final base = assertBizAdmin(a, b, targetBusinessId);
  if (base != null) return base;
  if (a.role == 'SUPER_ADMIN') return null;
  if (b.ownerId == a.uid || b.adminIds.contains(a.uid)) return null;
  final perms = b.memberPerms[a.uid] ?? const <String, bool>{};
  return perms[capability] == true ? null : 'no-$capability';
}

/// firestore.rules 의 payroll_summaries get 게이트를 같은 자리에서 재현한다.
///   isAdminOf(owner/adminIds) || (isSubAdminOf && subAdminCanManageWage)
///   || isSuperAdmin
bool ruleAllowsPayrollGet(Actor a, Biz b, String targetBusinessId) {
  if (a.role == 'SUPER_ADMIN') return true;
  if (!b.exists) return false;
  if (b.ownerId == a.uid || b.adminIds.contains(a.uid)) return true;
  final isSub = a.subAdminBusinessIds.contains(targetBusinessId) ||
      (a.subAdminOf.isNotEmpty && a.subAdminOf == targetBusinessId);
  if (!isSub) return false;
  return (b.memberPerms[a.uid] ?? const <String, bool>{})['canManageWage'] ==
      true;
}

void main() {
  const bizId = 'BIZ_A';
  const otherId = 'BIZ_B';

  const owner = Actor(uid: 'u_owner', role: 'BUSINESS_ADMIN');
  const superA = Actor(uid: 'u_super', role: 'SUPER_ADMIN');
  const wageSub = Actor(
      uid: 'u_wage', subAdminBusinessIds: <String>[bizId],
      accountStatus: 'active');
  const noWageSub = Actor(
      uid: 'u_nowage', subAdminBusinessIds: <String>[bizId],
      accountStatus: 'active');
  const toSub = Actor(
      uid: 'u_to', subAdminBusinessIds: <String>[bizId],
      accountStatus: 'active');
  const worker = Actor(uid: 'u_worker', accountStatus: 'active');
  const wrongBizSub = Actor(
      uid: 'u_wrong', subAdminBusinessIds: <String>[otherId],
      accountStatus: 'active');
  // 권한은 members 문서에 남아 있지만 membership 이 회수된 사람.
  const removed = Actor(uid: 'u_removed', accountStatus: 'active');

  const biz = Biz(
    id: bizId,
    ownerId: 'u_owner',
    adminIds: <String>['u_owner'],
    memberPerms: <String, Map<String, bool>>{
      'u_wage': <String, bool>{'canManageWage': true},
      'u_nowage': <String, bool>{'canManageWorkers': true},
      'u_to': <String, bool>{'canManageTo': true},
      'u_removed': <String, bool>{'canManageWage': true, 'canManageTo': true},
    },
  );

  late String source;
  late String code;

  setUpAll(() {
    source = File('functions/src/index.ts').readAsStringSync();
    code = _codeOf(source);
  });

  // ───────────────────────────────────────────────────────────
  group('D1-1x payroll read — 권한 matrix', () {
    String? w(Actor a) => assertCapability(a, biz, bizId, 'canManageWage');

    test('D1-10 A. BUSINESS_ADMIN own business → ALLOW', () {
      expect(w(owner), isNull);
    });
    test('D1-11 B. SUB_ADMIN + canManageWage → ALLOW', () {
      expect(w(wageSub), isNull);
    });
    test('D1-12 C. SUB_ADMIN without canManageWage → DENY', () {
      expect(w(noWageSub), 'no-canManageWage');
    });
    test('D1-13 D. wrong business → DENY', () {
      expect(w(wrongBizSub), 'not-member',
          reason: '다른 사업장 권한은 이 사업장 자격이 아니다');
    });
    test('D1-14 E. membership removed → DENY', () {
      // members 문서에 canManageWage 가 남아 있어도 소속이 없으면 막힌다.
      expect(w(removed), 'not-member');
    });
    test('D1-15 F. SUPER_ADMIN → ALLOW', () {
      expect(w(superA), isNull);
    });
    test('D1-16 canManageTo 만 가진 SubAdmin 은 급여를 못 본다', () {
      expect(w(toSub), 'no-canManageWage',
          reason: 'capability 는 도메인별로 따로다');
    });
  });

  // ───────────────────────────────────────────────────────────
  group('D1-2x payroll — rule / callable parity', () {
    test('D1-20 여섯 authority class 에서 두 경로가 같은 답을 낸다', () {
      for (final a in <Actor>[
        owner, superA, wageSub, noWageSub, wrongBizSub, removed, toSub, worker,
      ]) {
        final callable =
            assertCapability(a, biz, bizId, 'canManageWage') == null;
        final rule = ruleAllowsPayrollGet(a, biz, bizId);
        expect(callable, rule,
            reason: '${a.uid}: callable=$callable rule=$rule — '
                '한쪽만 막히면 CF 가 우회로가 된다');
      }
    });

    test('D1-21 rules 가 payroll direct read 를 wage 로 잠근다', () {
      final rules = _codeOf(File('firestore.rules').readAsStringSync());
      expect(rules.contains('function subAdminCanManageWage(businessId)'),
          isTrue);
      final block = rules.substring(
          rules.indexOf('match /payroll_summaries/{summaryId}'));
      final getGate = block.substring(0, block.indexOf('allow list'));
      expect(getGate.contains('subAdminCanManageWage'), isTrue,
          reason: 'direct get 이 membership 만 보면 CF 를 조인 의미가 없다');
      expect(block.contains('allow list: if isSuperAdmin();'), isTrue);
      expect(block.contains('allow write: if false;'), isTrue);
    });

    test('D1-22 workers 서브컬렉션도 같은 자격이다', () {
      final rules = _codeOf(File('firestore.rules').readAsStringSync());
      final helper = rules.substring(
          rules.indexOf('function isPayrollSummaryAdmin(summaryId)'));
      expect(helper.substring(0, 400).contains('subAdminCanManageWage'),
          isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────
  group('D1-3x 서버 배선 — 어느 문이 어느 판정을 쓰는가', () {
    test('D1-30 wage 판정이 한 곳에만 있다', () {
      expect(code.contains('async function srvAssertWageAuthority('), isTrue);
      final body = code.substring(
          code.indexOf('async function srvAssertWageAuthority('));
      expect(body.substring(0, 900).contains('canManageWage'), isTrue);
      expect(body.substring(0, 900).contains('assertBizAdmin('), isTrue,
          reason: '소속 확인을 건너뛰면 타 사업장 owner 가 들어온다');
    });

    test('D1-31 payroll read 문이 wage 판정을 쓴다', () {
      final f = _fn(code, 'export const callableGetPayrollSummaries');
      expect(f.contains('srvAssertWageAuthority('), isTrue);
      expect(RegExp(r'\bawait assertBizAdmin\(').hasMatch(f), isFalse,
          reason: 'membership-only 판정이 남아 있으면 안 된다');
    });

    test('D1-32 payroll repair 문이 wage 판정을 쓴다', () {
      final f = _fn(code, 'export const callableRepairPayrollSummaries');
      expect(f.contains('srvAssertWageAuthority('), isTrue);
      expect(RegExp(r'\bawait assertBizAdmin\(').hasMatch(f), isFalse);
    });

    test('D1-33 권한 판정이 projection 쓰기보다 앞에 있다', () {
      final f = _fn(code, 'export const callableRepairPayrollSummaries');
      final gate = f.indexOf('srvAssertWageAuthority(');
      final write = f.indexOf('runTransaction');
      expect(gate, greaterThan(-1));
      expect(write, greaterThan(-1));
      expect(write, greaterThan(gate),
          reason: '거절된 호출자가 payroll_summaries 를 건드리면 안 된다');
    });

    test('D1-34 세무 문도 같은 판정에 얹혀 있다', () {
      // 급여 권한이 두 벌이 되면 한쪽만 고쳐지는 날이 온다.
      final t = code.substring(
          code.indexOf('async function srvAssertTaxIdentityAuthority('));
      expect(t.substring(0, 300).contains('srvAssertWageAuthority('), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────
  group('D1-4x TO 초대 취소 — 권한 matrix', () {
    String? t(Actor a) => assertCapability(a, biz, bizId, 'canManageTo');

    test('D1-40 A. owner → ALLOW', () => expect(t(owner), isNull));
    test('D1-41 B. canManageTo SUB_ADMIN → ALLOW', () {
      expect(t(toSub), isNull);
    });
    test('D1-42 C. no-canManageTo SUB_ADMIN → DENY', () {
      expect(t(noWageSub), 'no-canManageTo');
    });
    test('D1-43 D. wrong business → DENY', () {
      expect(t(wrongBizSub), 'not-member');
    });
    test('D1-44 E. worker → DENY', () {
      expect(t(worker), 'not-member');
    });
    test('D1-45 F. SUPER_ADMIN → ALLOW', () => expect(t(superA), isNull));
    test('D1-46 canManageWage 만으로는 초대를 취소할 수 없다', () {
      expect(t(wageSub), 'no-canManageTo');
    });
  });

  // ───────────────────────────────────────────────────────────
  group('D1-5x TO 초대 취소 — 서버 배선', () {
    test('D1-50 TO 판정이 한 곳에만 있다', () {
      expect(code.contains('async function srvAssertToAuthority('), isTrue);
      final body = code.substring(
          code.indexOf('async function srvAssertToAuthority('));
      expect(body.substring(0, 900).contains('canManageTo'), isTrue);
      expect(body.substring(0, 900).contains('assertBizAdmin('), isTrue);
    });

    test('D1-51 취소 문이 TO 판정을 쓴다', () {
      final f = _fn(code, 'export const callableCancelTOInvitation');
      expect(f.contains('srvAssertToAuthority('), isTrue);
      expect(RegExp(r'\bawait assertBizAdmin\(').hasMatch(f), isFalse);
    });

    test('D1-52 businessId 는 초대 문서에서 온다 — 호출자 선택이 아니다', () {
      final f = _fn(code, 'export const callableCancelTOInvitation');
      expect(f.contains('const businessId = appData.businessId'), isTrue);
      expect(f.contains('request.data as {applicationId: string}'), isTrue,
          reason: 'businessId 를 payload 로 받으면 target 을 바꿔치기할 수 있다');
    });

    test('D1-53 권한 판정이 상태 전이·카운터보다 앞에 있다', () {
      final f = _fn(code, 'export const callableCancelTOInvitation');
      final gate = f.indexOf('srvAssertToAuthority(');
      final tx = f.indexOf('runTransaction');
      expect(gate, greaterThan(-1));
      expect(tx, greaterThan(gate),
          reason: '거절된 호출자가 초대 상태나 카운터를 건드리면 안 된다');
    });

    test('D1-54 취소 semantics 는 그대로다', () {
      // 이 Phase 는 문만 고친다 — 상태 전이·카운터 규칙은 손대지 않는다.
      final f = _fn(code, 'export const callableCancelTOInvitation');
      expect(f.contains('status: "CANCELED"'), isTrue);
      expect(f.contains('"INVITE_CANCELED"'), isTrue);
      expect(f.contains('workDetailCounts'), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────
  group('D1-6x 범위', () {
    test('D1-60 새 capability 를 만들지 않았다', () {
      for (final bad in <String>[
        'canManageIdentity', 'canReadPayroll', 'canViewWage', 'canCancelTo',
      ]) {
        expect(code.contains(bad), isFalse, reason: '$bad 가 생겼다');
      }
    });

    test('D1-61 반환 projection 을 새로 줄이지 않았다', () {
      final f = _fn(code, 'export const callableGetPayrollSummaries');
      expect(f.contains('serializeFirestoreData'), isTrue,
          reason: 'Core V1 에서 payroll summary 는 통째로 wage 데이터다');
    });
  });
}
