// [R5-PATCH-05 / D-2+E] 남은 capability 정합성 계약.
//
//   지키는 문장은 셋이다.
//
//     멤버 관리는 capability 로 얻을 수 없다 — 관리자 자리여야 한다.
//     재집계는 TO 를 만들 때와 같은 자격을 요구한다.
//     목록을 읽는 자격은 그 목록으로 하는 행동의 자격보다 낮지 않다.
//
//   판정은 Dart 로 재구현해 matrix 를 직접 고정하고(순수 함수), 어느 문이
//   어느 판정을 쓰는지는 소스 문자열로 고정한다.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _codeOf(String src) => src
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _fn(String src, String name) {
  final i = src.indexOf(name);
  expect(i, greaterThan(-1), reason: '$name 을 찾지 못했다');
  final n = src.indexOf('\nexport const ', i + 10);
  return src.substring(i, n > 0 ? n : src.length);
}

String _after(String src, String name, int chars) {
  final i = src.indexOf(name);
  expect(i, greaterThan(-1), reason: '$name 을 찾지 못했다');
  final e = (i + chars) > src.length ? src.length : i + chars;
  return src.substring(i, e);
}

// ─────────────────────────────────────────────────────────────
// 권한 판정 — 서버 helper 들과 같은 식
// ─────────────────────────────────────────────────────────────

const _biz = 'BIZ_A';

class Actor {
  const Actor(this.uid, {this.role = 'USER', this.subs = const <String>[]});
  final String uid;
  final String role;
  final List<String> subs;
}

const _owner = Actor('u_owner', role: 'BUSINESS_ADMIN');
const _superA = Actor('u_super', role: 'SUPER_ADMIN');
const _allCaps = Actor('u_all', subs: <String>[_biz]);
const _toOnly = Actor('u_to', subs: <String>[_biz]);
const _wageOnly = Actor('u_wage', subs: <String>[_biz]);
const _zeroCaps = Actor('u_zero', subs: <String>[_biz]);
const _worker = Actor('u_worker');
const _wrongBiz = Actor('u_wrong', subs: <String>['BIZ_B']);

const _perms = <String, Map<String, bool>>{
  'u_all': <String, bool>{
    'canManageTo': true, 'canManageWage': true,
    'canManageWorkers': true, 'canManageContract': true,
    'canCancelTransfer': true,
  },
  'u_to': <String, bool>{'canManageTo': true},
  'u_wage': <String, bool>{'canManageWage': true},
  'u_zero': <String, bool>{},
};

const _ownerId = 'u_owner';
const _adminIds = <String>['u_owner'];

/// capability 한 개를 요구하는 판정 (wage / to / contract 공통 모양).
String? capability(Actor a, String cap) {
  if (a.role == 'SUPER_ADMIN') return null;
  final isMember = _adminIds.contains(a.uid) ||
      _ownerId == a.uid || a.subs.contains(_biz);
  if (!isMember) return 'not-member';
  if (_ownerId == a.uid || _adminIds.contains(a.uid)) return null;
  final p = _perms[a.uid] ?? const <String, bool>{};
  return p[cap] == true ? null : 'no-$cap';
}

/// 멤버 관리 판정 — capability 를 보지 않는다.
String? memberManagement(Actor a) {
  if (a.role == 'SUPER_ADMIN') return null;
  if (_adminIds.contains(a.uid) || _ownerId == a.uid) return null;
  return 'not-admin';
}

void main() {
  late String code;

  setUpAll(() {
    code = _codeOf(File('functions/src/index.ts').readAsStringSync());
  });

  // ───────────────────────────────────────────────────────────
  group('D2-1x 멤버 관리 읽기 (§11)', () {
    test('A owner → ALLOW', () => expect(memberManagement(_owner), isNull));
    test('B SUPER_ADMIN → ALLOW', () {
      expect(memberManagement(_superA), isNull);
    });
    test('C 모든 capability 를 가진 SUB_ADMIN → DENY', () {
      expect(memberManagement(_allCaps), 'not-admin',
          reason: '권한을 받은 사람이 권한을 또 나눠 줄 수는 없다');
    });
    test('D capability 없는 SUB_ADMIN → DENY', () {
      expect(memberManagement(_zeroCaps), 'not-admin');
    });
    test('E 근로자 → DENY', () => expect(memberManagement(_worker), 'not-admin'));
    test('F 다른 사업장 → DENY', () {
      expect(memberManagement(_wrongBiz), 'not-admin');
    });

    test('D2-10 판정이 capability 를 보지 않는다', () {
      final h =
          _after(code, 'async function srvAssertMemberManagementAuthority(', 900);
      expect(h.contains('canManage'), isFalse,
          reason: 'capability 를 보면 SubAdmin 에게 길이 열린다');
      expect(h.contains('adminIds'), isTrue);
      expect(h.contains('ownerId'), isTrue);
      expect(h.contains('SUPER_ADMIN'), isTrue);
    });

    test('D2-11 두 초대 reader 가 그 판정을 쓴다', () {
      for (final f in <String>[
        'export const callableCheckPendingInvitation',
        'export const callableGetSentPendingInvitations',
      ]) {
        final body = _fn(code, f);
        expect(body.contains('srvAssertMemberManagementAuthority('), isTrue,
            reason: f);
        expect(RegExp(r'\bawait assertBizAdmin\(').hasMatch(body), isFalse,
            reason: '$f 에 membership-only 판정이 남았다');
      }
    });

    test('D2-12 멤버 제거도 같은 판정에 얹혀 있다', () {
      final f = _fn(code, 'export const callableRemoveMember');
      expect(f.contains('srvAssertMemberManagementAuthority('), isTrue);
      // 판정이 두 벌이 되면 한쪽만 고쳐지는 날이 온다.
      expect(f.contains('해당 사업장 관리자만 멤버를 제거할 수 있습니다'), isFalse);
    });

    test('D2-13 새 member capability 를 만들지 않았다', () {
      for (final bad in <String>[
        'canManageMember', 'canManageMembers', 'canInviteMember',
      ]) {
        expect(code.contains(bad), isFalse, reason: bad);
      }
    });
  });

  // ───────────────────────────────────────────────────────────
  group('D2-2x TO 재집계 (§12)', () {
    String? t(Actor a) => capability(a, 'canManageTo');

    test('A owner → ALLOW', () => expect(t(_owner), isNull));
    test('B canManageTo SUB_ADMIN → ALLOW', () => expect(t(_toOnly), isNull));
    test('C canManageTo 없는 SUB_ADMIN → DENY', () {
      expect(t(_wageOnly), 'no-canManageTo');
      expect(t(_zeroCaps), 'no-canManageTo');
    });
    test('D 근로자 → DENY', () => expect(t(_worker), 'not-member'));
    test('E 다른 사업장 → DENY', () => expect(t(_wrongBiz), 'not-member'));
    test('F SUPER_ADMIN → ALLOW', () => expect(t(_superA), isNull));

    test('D2-20 두 recompute writer 가 TO 자격을 쓴다', () {
      for (final f in <String>[
        'export const callableRecalculateTOStats',
        'export const callableRecalcToTotalRequired',
      ]) {
        final body = _fn(code, f);
        expect(body.contains('srvAssertToAuthority('), isTrue, reason: f);
        expect(RegExp(r'\bawait assertBizAdmin\(').hasMatch(body), isFalse,
            reason: f);
      }
    });

    test('D2-21 §6 권한 기준 사업장이 공고에서 나온다', () {
      final a = _fn(code, 'export const callableRecalculateTOStats');
      expect(a.contains('const businessId = toData.businessId'), isTrue);
      final b = _fn(code, 'export const callableRecalcToTotalRequired');
      expect(b.contains('srvAssertToAuthority(callerUid, recalcBizId)'), isTrue,
          reason: 'payload 가 아니라 공고의 사업장으로 판정해야 한다');
    });

    test('D2-22 §15 권한 판정이 쓰기보다 앞이다', () {
      for (final f in <String>[
        'export const callableRecalculateTOStats',
        'export const callableRecalcToTotalRequired',
      ]) {
        final body = _fn(code, f);
        final gate = body.indexOf('srvAssertToAuthority(');
        final write = body.indexOf('.update(');
        expect(gate, greaterThan(-1), reason: f);
        if (write > -1) {
          expect(write, greaterThan(gate),
              reason: '$f — 거절된 호출자가 카운터를 건드리면 안 된다');
        }
      }
    });

    test('D2-23 소속 교차검증이 권한 판정 앞에 남아 있다', () {
      final b = _fn(code, 'export const callableRecalcToTotalRequired');
      final cross = b.indexOf('recalcBizId !== businessId');
      final gate = b.indexOf('srvAssertToAuthority(');
      expect(cross, greaterThan(-1));
      expect(gate, greaterThan(cross),
          reason: '남의 공고 id 와 자기 사업장 id 를 섞어 보내는 경로를 먼저 막는다');
    });
  });

  // ───────────────────────────────────────────────────────────
  group('D2-3x 사업장 범위 read — least privilege (§13)', () {
    test('D2-30 지급방식 변경 목록 = 승인 행동과 같은 자격', () {
      final read = _fn(code, 'export const callableGetPaymentChangeRequests');
      expect(read.contains('srvAssertWageAuthority('), isTrue);
      expect(RegExp(r'\bawait assertBizAdmin\(').hasMatch(read), isFalse);
      // 행동 주인이 canManageWage 임을 같은 소스에서 확인한다.
      final act = _fn(code, 'export const callableApprovePaymentChangeRequest');
      expect(act.contains('canManageWage'), isTrue);
    });

    test('D2-31 갱신 제안 목록 = 제안 생성과 같은 자격', () {
      final read = _fn(code, 'export const callableGetRenewalProposalsByBiz');
      expect(read.contains('srvAssertContractAuthority('), isTrue);
      expect(RegExp(r'\bawait assertBizAdmin\(').hasMatch(read), isFalse);
      final act = _fn(code, 'export const callableCreateRenewalProposal');
      expect(act.contains('canManageContract'), isTrue);
    });

    test('D2-32 관리자 공고 목록 = canManageTo', () {
      final f = _fn(code, 'export const callableGetAdminTOs');
      expect(f.contains('srvAssertToAuthority(callerUid, id)'), isTrue);
      expect(RegExp(r'\bawait assertBizAdmin\(').hasMatch(f), isFalse);
    });

    test('D2-33 기존 canManageTo 계약이 유지된다', () {
      // callableGetTOsByBiz 는 이미 canManageTo 였다 — 되돌리지 않았다.
      final f = _fn(code, 'export const callableGetTOsByBiz');
      expect(f.contains('canManageTo'), isTrue);
    });

    test('D2-34 4-capability OR gate 로 묶지 않았다', () {
      for (final f in <String>[
        'export const callableGetPaymentChangeRequests',
        'export const callableGetRenewalProposalsByBiz',
        'export const callableGetAdminTOs',
      ]) {
        final body = _fn(code, f);
        final caps = <String>[
          'canManageTo', 'canManageWage', 'canManageWorkers',
          'canManageContract',
        ].where(body.contains).length;
        expect(caps, 0,
            reason: '$f 은 helper 한 개에 위임한다 — 인라인 OR 로 묶지 않는다');
      }
    });

    test('D2-35 세 도메인 판정이 같은 모양이다', () {
      for (final h in <List<String>>[
        ['async function srvAssertWageAuthority(', 'canManageWage'],
        ['async function srvAssertToAuthority(', 'canManageTo'],
        ['async function srvAssertContractAuthority(', 'canManageContract'],
      ]) {
        final body = _after(code, h[0], 900);
        expect(body.contains('assertBizAdmin('), isTrue, reason: h[0]);
        expect(body.contains('SUPER_ADMIN'), isTrue, reason: h[0]);
        expect(body.contains(h[1]), isTrue, reason: h[0]);
      }
    });

    test('D2-36 전역 permission framework 를 만들지 않았다', () {
      for (final bad in <String>[
        'requireCanManage', 'function assertCapability(',
        'PERMISSION_MATRIX', 'capabilityGuard',
      ]) {
        expect(code.contains(bad), isFalse, reason: bad);
      }
    });
  });

  // ───────────────────────────────────────────────────────────
  group('D2-4x 앞선 Phase 계약 보존 (§17)', () {
    test('D2-40 D-1 급여 자격이 그대로다', () {
      for (final f in <String>[
        'export const callableGetPayrollSummaries',
        'export const callableRepairPayrollSummaries',
        'export const callableGetNotTransferredCount',
      ]) {
        expect(_fn(code, f).contains('srvAssertWageAuthority('), isTrue,
            reason: f);
      }
    });

    test('D2-41 D-1 초대 취소 자격이 그대로다', () {
      expect(
        _fn(code, 'export const callableCancelTOInvitation')
            .contains('srvAssertToAuthority('),
        isTrue,
      );
    });

    test('D2-42 .6-P3 날짜 권위가 그대로다', () {
      final f = _fn(code, 'export const callableCalculateAndConfirmWage');
      expect(f.contains('yearMonth: canon.yearMonth'), isTrue);
    });
  });
}
