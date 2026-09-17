// [POSTING-V2-02G.1] 공고 권한을 대상 사업장 기준으로 판정한다
//
// 02G READ에서 확정된 서버 계약:
//   READ  = membership (assertBizAdmin) — canManageTo를 보지 않는다
//   WRITE = 대상 사업장의 MemberPermissions.canManageTo (mutation 15종 전부)
//
// 반면 클라이언트는 up.can()으로 **선택된 한 사업장**의 권한만 썼다.
//   A(canManageTo=true) / B(false), selected=A
//     → 목록에는 A+B가 나오고 B 카드의 쓰기 액션까지 켜진 채 서버가 거부
//   selected=B
//     → 공고 탭 자체가 사라지고 Shell이 현재 탭을 홈으로 되돌림
//       (A에는 관리 권한이 있는데도 도달 불가)
//
// UserProvider는 Firebase auth 스트림을 생성자에서 구독해 단위 테스트로
// 인스턴스화할 수 없다. 판정 로직은 순수 replica로, 배선은 소스로 검증한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/business_member_model.dart';

const _providerPath = 'lib/providers/user_provider.dart';
const _shellPath = 'lib/screens/business_admin/business_admin_shell.dart';
const _cardPath = 'lib/widgets/admin/cards/admin_to_group_card.dart';
const _dayPath =
    'lib/screens/business_admin/dialogs/day_applicants_dialog.dart';
const _workPath =
    'lib/screens/business_admin/dialogs/work_applicants_dialog.dart';
const _workDetailPath = 'lib/widgets/admin/cards/admin_work_detail.dart';
const _createToPath =
    'lib/screens/business_admin/to_management/create_to_screen.dart';
const _ctrlPath = 'lib/controllers/workforce_controller.dart';
const _listPath =
    'lib/screens/business_admin/workforce_management/workforce_list_view.dart';

String _src(String p) {
  final f = File(p);
  expect(f.existsSync(), true, reason: '$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

String _bodyOf(String source, String signature) {
  final start = source.indexOf(signature);
  if (start == -1) throw StateError('$signature 를 찾지 못함');
  var paren = 0;
  var afterParams = start;
  for (var i = source.indexOf('(', start); i < source.length; i++) {
    if (source[i] == '(') paren++;
    if (source[i] == ')') {
      paren--;
      if (paren == 0) {
        afterParams = i;
        break;
      }
    }
  }
  final open = source.indexOf('{', afterParams);
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  throw StateError('$signature 본문의 끝을 찾지 못함');
}

// ── UserProvider 판정 replica ────────────────────────────────────
// canForBusiness / canForAnyBusiness의 계약을 그대로 옮긴다.
// 소스가 이 형태를 유지하는지는 별도 테스트가 본다.

enum _Role { businessAdmin, superAdmin, subAdmin, plainUser }

class _Fixture {
  final _Role role;
  final List<String> assigned;
  final Map<String, MemberPermissions> permsByBiz;
  final bool permsLoaded;

  /// 선택 사업장 권한 — 기존 can()이 보던 값
  final MemberPermissions? selectedPerms;

  const _Fixture({
    required this.role,
    this.assigned = const [],
    this.permsByBiz = const {},
    this.permsLoaded = true,
    this.selectedPerms,
  });

  bool can(bool Function(MemberPermissions p) check) {
    if (role == _Role.businessAdmin) return true;
    if (selectedPerms != null) return check(selectedPerms!);
    return false;
  }

  bool canForBusiness(String bizId, bool Function(MemberPermissions p) check) {
    if (role == _Role.businessAdmin || role == _Role.superAdmin) return true;
    if (role != _Role.subAdmin) return false;
    final p = permsByBiz[bizId];
    if (p == null) return false;
    return check(p);
  }

  bool canForAnyBusiness(
    bool Function(MemberPermissions p) check, {
    required bool whenUnknown,
  }) {
    if (role == _Role.businessAdmin || role == _Role.superAdmin) return true;
    if (role != _Role.subAdmin) return false;
    if (!permsLoaded) return whenUnknown;
    return assigned.any((id) {
      final p = permsByBiz[id];
      return p != null && check(p);
    });
  }

  bool get canManagePostingAnywhere => canForAnyBusiness(
        (p) => p.canManageTo,
        whenUnknown: can((p) => p.canManageTo),
      );
}

const _manage = MemberPermissions(canManageTo: true);
const _noManage = MemberPermissions();
const _contractOnly = MemberPermissions(canManageContract: true);

void main() {
  // ── §45 사업장별 권한 map ───────────────────────────────────────
  group('CAP-01 권한이 사업장별로 구분된다', () {
    final f = _Fixture(
      role: _Role.subAdmin,
      assigned: const ['A', 'B'],
      permsByBiz: const {'A': _manage, 'B': _noManage},
      selectedPerms: _manage, // 선택은 A
    );

    test('01-a A는 true, B는 false', () {
      expect(f.canForBusiness('A', (p) => p.canManageTo), true);
      expect(f.canForBusiness('B', (p) => p.canManageTo), false);
    });

    test('01-b 선택 사업장을 B로 바꿔도 값이 뒤집히지 않는다', () {
      final selectedB = _Fixture(
        role: _Role.subAdmin,
        assigned: const ['A', 'B'],
        permsByBiz: const {'A': _manage, 'B': _noManage},
        selectedPerms: _noManage, // 선택은 B
      );
      expect(selectedB.canForBusiness('A', (p) => p.canManageTo), true);
      expect(selectedB.canForBusiness('B', (p) => p.canManageTo), false);
    });

    test('01-c map에 없는 사업장은 fail-closed (§36)', () {
      expect(f.canForBusiness('C', (p) => p.canManageTo), false);
    });

    test('01-d 소스가 businessId로 조회한다', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_providerPath), 'bool canForBusiness(')));
      expect(
          body.contains(
              'final perms = _subAdminPermissionsByBusinessView[businessId];'),
          true);
      expect(body.contains('if (perms == null) return false;'), true);
    });
  });

  // ── §46 사업장별 실패 격리 ──────────────────────────────────────
  group('CAP-02 한 사업장 조회 실패가 나머지를 무효로 만들지 않는다', () {
    test('02-a A 성공 / B 실패 / C 성공', () {
      // B는 조회 실패 → map에 없음 → fail-closed
      final f = _Fixture(
        role: _Role.subAdmin,
        assigned: const ['A', 'B', 'C'],
        permsByBiz: const {'A': _manage, 'C': _manage},
      );
      expect(f.canForBusiness('A', (p) => p.canManageTo), true);
      expect(f.canForBusiness('B', (p) => p.canManageTo), false);
      expect(f.canForBusiness('C', (p) => p.canManageTo), true);
      expect(f.permsLoaded, true, reason: '전체 load 실패로 만들면 안 된다');
    });

    test('02-b 하이드레이션이 사업장별 try/catch를 쓴다', () {
      final body = _flat(_codeOf(_bodyOf(
          _src(_providerPath), 'Future<void> _hydrateSubAdminPermissions(')));
      expect(body.contains('} catch (e) {'), true);
      expect(body.contains('return MapEntry(bizId, null);'), true,
          reason: '실패한 사업장만 제외되어야 한다');
      expect(body.contains('_subAdminPermissionsLoaded = true;'), true);
    });

    test('02-c 실패한 사업장은 다음 하이드레이션에서 재시도된다', () {
      final body = _flat(_codeOf(_bodyOf(
          _src(_providerPath), 'Future<void> _hydrateSubAdminPermissions(')));
      expect(body.contains('_hydratedPermissionBusinessIds = map.keys.toSet();'),
          true,
          reason: '성공분만 기록해야 실패분이 재시도된다');
    });
  });

  // ── §47 UNKNOWN vs DENIED ───────────────────────────────────────
  group('CAP-03 미하이드레이션과 거부를 구분한다', () {
    test('03-a UNKNOWN이면 whenUnknown을 따른다', () {
      final unknown = _Fixture(
        role: _Role.subAdmin,
        assigned: const ['A', 'B'],
        permsByBiz: const {},
        permsLoaded: false,
        selectedPerms: _manage,
      );
      expect(unknown.canManagePostingAnywhere, true,
          reason: '빈 map을 거부로 읽으면 탭이 사라졌다 돌아온다');
    });

    test('03-b LOADED + 전부 false면 거부', () {
      final denied = _Fixture(
        role: _Role.subAdmin,
        assigned: const ['A', 'B'],
        permsByBiz: const {'A': _noManage, 'B': _noManage},
        selectedPerms: _noManage,
      );
      expect(denied.permsLoaded, true);
      expect(denied.canManagePostingAnywhere, false);
    });

    test('03-c 두 상태가 같은 값으로 수렴하지 않는다', () {
      final unknown = _Fixture(
        role: _Role.subAdmin,
        assigned: const ['A'],
        permsLoaded: false,
        selectedPerms: _manage,
      );
      final denied = _Fixture(
        role: _Role.subAdmin,
        assigned: const ['A'],
        permsByBiz: const {'A': _noManage},
        selectedPerms: _manage,
      );
      expect(unknown.canManagePostingAnywhere, isNot(denied.canManagePostingAnywhere));
    });

    test('03-d tri-state가 소스에 존재한다', () {
      final code = _codeOf(_src(_providerPath));
      expect(code.contains('bool _subAdminPermissionsLoaded = false;'), true);
      expect(code.contains('bool get subAdminPermissionsLoaded =>'), true);
      final body = _flat(_codeOf(
          _bodyOf(_src(_providerPath), 'bool canForAnyBusiness(')));
      expect(
          body.contains('if (!_subAdminPermissionsLoaded) return whenUnknown;'),
          true);
    });
  });

  // ── §48 flicker 방지 전략 ───────────────────────────────────────
  group('CAP-04 하이드레이션 중 탭이 사라지지 않는다', () {
    test('04-a whenUnknown이 기존 선택-사업장 판정이다', () {
      final body = _flat(_codeOf(_bodyOf(
          _src(_providerPath), 'bool get canManagePostingAnywhere =>')));
      expect(body.contains('whenUnknown: can((p) => p.canManageTo),'), true,
          reason: '하이드레이션 전 동작이 기존과 달라지면 새 flicker가 생긴다');
    });

    test('04-b 하이드레이션 전 동작이 기존 계약과 같다', () {
      // 기존: selected 권한으로 판정. UNKNOWN 동안 그대로여야 한다.
      for (final selected in [_manage, _noManage]) {
        final f = _Fixture(
          role: _Role.subAdmin,
          assigned: const ['A', 'B'],
          permsLoaded: false,
          selectedPerms: selected,
        );
        expect(f.canManagePostingAnywhere, f.can((p) => p.canManageTo));
      }
    });
  });

  // ── §49 탭 가시성 ───────────────────────────────────────────────
  group('CAP-05 공고 탭은 배정 범위 전체를 본다', () {
    test('05-a A=true / B=false / selected=B → 탭 유지 (§16)', () {
      final f = _Fixture(
        role: _Role.subAdmin,
        assigned: const ['A', 'B'],
        permsByBiz: const {'A': _manage, 'B': _noManage},
        selectedPerms: _noManage, // B 선택 중
      );
      expect(f.can((p) => p.canManageTo), false, reason: '옛 판정은 false였다');
      expect(f.canManagePostingAnywhere, true,
          reason: 'A에 권한이 있는데 탭이 사라지면 안 된다');
    });

    test('05-b 전부 false면 숨김 — MODEL C로 확장하지 않는다 (§17)', () {
      final f = _Fixture(
        role: _Role.subAdmin,
        assigned: const ['A', 'B'],
        permsByBiz: const {'A': _noManage, 'B': _noManage},
      );
      expect(f.canManagePostingAnywhere, false);
    });

    test('05-c BUSINESS_ADMIN은 map 없이 true (§18)', () {
      const f = _Fixture(role: _Role.businessAdmin);
      expect(f.canManagePostingAnywhere, true);
      expect(f.canForBusiness('anything', (p) => p.canManageTo), true);
    });

    test('05-d SUPER_ADMIN도 true (§19)', () {
      const f = _Fixture(role: _Role.superAdmin);
      expect(f.canManagePostingAnywhere, true);
      expect(f.canForBusiness('anything', (p) => p.canManageTo), true);
      final body = _flat(
          _codeOf(_bodyOf(_src(_providerPath), 'bool canForBusiness(')));
      expect(body.contains('if (user.isBusinessAdmin || user.isSuperAdmin) return true;'),
          true);
    });

    test('05-e Shell이 새 계약을 쓴다', () {
      final code = _codeOf(_src(_shellPath));
      expect(code.contains('if (up.canManagePostingAnywhere) 1,'), true);
      expect(code.contains('if (up.can((p) => p.canManageTo)) 1,'), false,
          reason: '탭이 선택 사업장 권한으로 회귀했다');
      // 다른 탭의 기존 계약은 그대로
      expect(code.contains('if (up.can((p) => p.canManageWorkers)) 2,'), true);
      expect(code.contains('if (up.can((p) => p.canManageWage)) 3,'), true);
    });
  });

  // ── §50, §51 카드 ───────────────────────────────────────────────
  group('CAP-06 카드 액션이 대상 사업장 기준이다', () {
    test('06-a 카드 게이트가 groupItem.businessId를 쓴다', () {
      final code = _flat(_codeOf(_src(_cardPath)));
      expect(
          'up.canForBusiness(widget.groupItem.businessId, (p) => p.canManageTo)'
              .allMatches(code)
              .length,
          4,
          reason: 'canManageTo 2곳 + canDelete 2곳');
      expect(code.contains('up.can((p) => p.canManageTo)'), false,
          reason: '선택 사업장 판정이 남아 있다');
    });

    test('06-b B 카드는 쓰기 액션이 닫히고 읽기는 남는다 (§22)', () {
      final f = _Fixture(
        role: _Role.subAdmin,
        assigned: const ['A', 'B'],
        permsByBiz: const {'A': _manage, 'B': _noManage},
        selectedPerms: _manage,
      );
      expect(f.canForBusiness('B', (p) => p.canManageTo), false);
      // 카드 자체를 숨기지 않는다 — 목록 필터는 권한을 보지 않는다
      final list = _codeOf(_src(_listPath));
      expect(list.contains('canManageTo'), false,
          reason: '목록/필터가 권한으로 걸러지면 read scope가 좁아진다');
    });

    test('06-c selected=B여도 A 카드 액션은 살아 있다 (§51)', () {
      final f = _Fixture(
        role: _Role.subAdmin,
        assigned: const ['A', 'B'],
        permsByBiz: const {'A': _manage, 'B': _noManage},
        selectedPerms: _noManage,
      );
      expect(f.canForBusiness('A', (p) => p.canManageTo), true);
    });

    test('06-d 삭제의 owner/super 예외가 보존됐다', () {
      final code = _flat(_codeOf(_src(_cardPath)));
      expect(
          code.contains('final canDelete = user?.isBusinessAdmin == true || '
              'user?.isSuperAdmin == true || up.canForBusiness('),
          true);
    });
  });

  // ── §52 지원자 다이얼로그 ───────────────────────────────────────
  group('CAP-07 지원자 액션이 대상 사업장 기준이다', () {
    test('07-a DayApplicantsDialog가 보고 있는 사업장으로 판정한다', () {
      final body = _flat(
          _codeOf(_bodyOf(_src(_dayPath), 'bool _canForSelectedBiz(')));
      expect(body.contains('final bizId = _selectedBusinessId;'), true);
      expect(body.contains('return up.canForBusiness(bizId, check);'), true);
      expect(body.contains('if (bizId == null || bizId.isEmpty) return up.can(check);'),
          true, reason: '사업장을 특정할 수 없을 때만 폴백');
    });

    test('07-b 확정·거절·일괄확정·계약이 모두 그 helper를 쓴다', () {
      final code = _codeOf(_src(_dayPath));
      expect('_canForSelectedBiz((p) => p.canManageTo)'.allMatches(code).length,
          greaterThanOrEqualTo(3));
      expect(
          '_canForSelectedBiz((p) => p.canManageContract)'
              .allMatches(code)
              .length,
          greaterThanOrEqualTo(2));
      expect(code.contains('up.can((p) => p.canManageTo)'), false);
      expect(code.contains('up.can((p) => p.canManageContract)'), false);
    });

    test('07-c §25 bool이 아니라 MemberPermissions 단위로 판정한다', () {
      // canManageTo가 없어도 canManageContract는 살아 있을 수 있다.
      final f = _Fixture(
        role: _Role.subAdmin,
        assigned: const ['B'],
        permsByBiz: const {'B': _contractOnly},
      );
      expect(f.canForBusiness('B', (p) => p.canManageTo), false);
      expect(f.canForBusiness('B', (p) => p.canManageContract), true);
    });

    test('07-d §40 canManageWorkers로 대체되지 않았다', () {
      final code = _codeOf(_src(_dayPath)) + _codeOf(_src(_cardPath));
      expect(code.contains('canManageWorkers'), false,
          reason: '공고 계보의 canonical은 canManageTo다');
    });
  });

  // ── §26, §53 WorkApplicantsDialog ───────────────────────────────
  group('CAP-08 WorkApplicantsDialog 계약', () {
    // [POSTING-V2-03B.1] targetPermissions는 canonical에서 UNKNOWN 폴백으로 내려갔다.
    //   provider가 그 사업장 권한을 LOADED로 갖고 있으면 그쪽이 이긴다.
    //   지켜야 할 것은 "알림 경로가 넘긴 정확한 권한이 버려지지 않는다"이다.
    test('08-a targetPermissions가 UNKNOWN 폴백으로 살아 있다', () {
      final code = _flat(_codeOf(_src(_workPath)));
      expect(code.contains('final MemberPermissions? targetPermissions;'), true);
      final body = _flat(_codeOf(_bodyOf(_src(_workPath), 'bool _permissionFor(')));
      expect(body.contains('if (up.subAdminPermissionsLoaded) {'), true);
      expect(body.contains('final target = widget.targetPermissions; '
          'if (target != null) return check(target);'), true);
      // canManageTo / canManageContract 둘 다 같은 경로를 쓴다
      expect(code.contains('bool _canManageTo() => _permissionFor((p) => p.canManageTo);'),
          true);
      expect(
          code.contains(
              'bool _canManageContract() => _permissionFor((p) => p.canManageContract);'),
          true);
    });

    test('08-b 공고 카드 진입도 target permissions를 주입한다', () {
      final code = _flat(_codeOf(_src(_workDetailPath)));
      expect(
          code.contains('targetPermissions: context .read<UserProvider>() '
              '.permissionsForBusiness(widget.toItem.to.businessId),'),
          true);
    });

    test('08-c 알림 경로 계약 무변경 (§53)', () {
      final notif =
          _codeOf(_src('lib/screens/common/notification_screen.dart'));
      expect(notif.contains('targetPermissions'), true);
      expect(
          notif.contains('if (!up.isSubAdmin) return _AdminAccessResult.allowed;'),
          true);
    });
  });

  // ── §54, §55 CreateTO ───────────────────────────────────────────
  group('CAP-09 CreateTO picker가 권한을 반영한다', () {
    test('09-a membership을 canManageTo로 한 번 더 거른다', () {
      final body = _flat(
          _codeOf(_bodyOf(_src(_createToPath), 'Future<void> _loadMyBusinesses(')));
      expect(
          body.contains('final allBusinesses = membershipBusinesses '
              '.where((b) => userProvider.canForBusiness(b.id, (p) => p.canManageTo)) '
              '.toList();'),
          true);
    });

    test('09-b membership 조회 자체는 그대로다 (read scope 무변경)', () {
      final body = _flat(
          _codeOf(_bodyOf(_src(_createToPath), 'Future<void> _loadMyBusinesses(')));
      expect(
          body.contains(
              'final bizIds = userProvider.currentUser?.subAdminBusinessIds ?? [];'),
          true);
      expect(
          body.contains(
              'final managedIds = userProvider.currentUser?.managedBusinessIds ?? [];'),
          true);
    });

    test('09-c B는 selectable이 아니다 (§30)', () {
      final f = _Fixture(
        role: _Role.subAdmin,
        assigned: const ['A', 'B'],
        permsByBiz: const {'A': _manage, 'B': _noManage},
      );
      final selectable = ['A', 'B']
          .where((id) => f.canForBusiness(id, (p) => p.canManageTo))
          .toList();
      expect(selectable, ['A']);
    });

    test('09-d effectiveBusinessId=B여도 dead-end가 되지 않는다 (§31, §55)', () {
      // B가 목록에서 빠지므로 initCheck가 null이 되고
      // 기존 ready-first fallback이 A를 고른다.
      final f = _Fixture(
        role: _Role.subAdmin,
        assigned: const ['A', 'B'],
        permsByBiz: const {'A': _manage, 'B': _noManage},
      );
      const initialBusinessId = 'B';
      final selectable = ['A', 'B']
          .where((id) => f.canForBusiness(id, (p) => p.canManageTo))
          .toList();
      expect(selectable.contains(initialBusinessId), false);
      expect(selectable.isNotEmpty, true);
      // 새 선택 정책을 만들지 않았다
      final code = _codeOf(_src(_createToPath));
      expect(code.contains('initialBusinessId'), true);
    });

    test('09-e BUSINESS_ADMIN은 필터에 걸리지 않는다 (§33, §56)', () {
      const f = _Fixture(role: _Role.businessAdmin);
      expect(f.canForBusiness('A', (p) => p.canManageTo), true);
      expect(f.canForBusiness('B', (p) => p.canManageTo), true);
    });

    test('09-f SUPER_ADMIN도 0개가 되지 않는다 (§34, §57)', () {
      const f = _Fixture(role: _Role.superAdmin);
      expect(f.canForBusiness('A', (p) => p.canManageTo), true);
    });
  });

  // ── §37, §38 cross-entry invariant ──────────────────────────────
  group('CAP-10 진입 경로가 달라도 결과가 같다', () {
    final f = _Fixture(
      role: _Role.subAdmin,
      assigned: const ['A', 'B'],
      permsByBiz: const {'A': _manage, 'B': _noManage},
      selectedPerms: _noManage, // B 선택 중 — 옛 판정이라면 A까지 막혔을 상태
    );

    test('10-a B는 모든 진입에서 mutation 불가', () {
      expect(f.canForBusiness('B', (p) => p.canManageTo), false);
    });

    test('10-b A는 모든 진입에서 mutation 가능 (§38)', () {
      expect(f.canForBusiness('A', (p) => p.canManageTo), true);
      expect(f.canManagePostingAnywhere, true);
    });

    test('10-c 판정이 선택 사업장에 의존하지 않는다', () {
      final other = _Fixture(
        role: _Role.subAdmin,
        assigned: const ['A', 'B'],
        permsByBiz: const {'A': _manage, 'B': _noManage},
        selectedPerms: _manage,
      );
      for (final biz in ['A', 'B']) {
        expect(f.canForBusiness(biz, (p) => p.canManageTo),
            other.canForBusiness(biz, (p) => p.canManageTo),
            reason: '$biz 판정이 선택 사업장에 따라 달라진다');
      }
    });
  });

  // ── §41, §14, §12 비용 / listener ───────────────────────────────
  group('CAP-11 조회 비용과 listener', () {
    test('11-a 배정 집합이 같으면 재조회하지 않는다 (§12)', () {
      final body = _flat(_codeOf(_bodyOf(
          _src(_providerPath), 'Future<void> _hydrateSubAdminPermissions(')));
      // [POSTING-V2-03B.1] 명시적 access refresh만 force로 이 최적화를 건너뛴다.
      expect(
          body.contains('if (!force && _subAdminPermissionsLoaded && '
              '_hydratedPermissionBusinessIds.length == idSet.length && '
              '_hydratedPermissionBusinessIds.containsAll(idSet)) { return;'),
          true,
          reason: '사업장 전환마다 N개를 다시 읽으면 안 된다');
    });

    test('11-b 새 realtime listener가 없다 (§14)', () {
      final body = _codeOf(_bodyOf(
          _src(_providerPath), 'Future<void> _hydrateSubAdminPermissions('));
      expect(body.contains('snapshots()'), false);
      expect(body.contains('listen('), false);
      // 기존 선택-사업장 listener는 그대로 (§13)
      final code = _codeOf(_src(_providerPath));
      expect(code.contains('void _startMemberPermsListener(String businessId, String uid)'),
          true);
      // [POSTING-V2-03B.1] +1 — access refresh가 선택 사업장 변경 시 listener를 옮긴다.
      //   여전히 **동시에 살아 있는 구독은 하나**다(연결 전 cancel).
      expect('_startMemberPermsListener('.allMatches(code).length, 4,
          reason: '정의 1 + 호출 3 (switchToAdminMode, _loadUserData, access refresh)');
      // [CROSS-DOMAIN-R5.1F.2] +1 — 대상 사업장 화면이 열려 있는 동안만 사는
      //   구독이 생겼다(selected≠target일 때 권한 회수가 화면에 닿지 않던 문제).
      //   **상시** 구독은 여전히 선택 사업장 하나뿐이고, 새 구독은 refcount로
      //   합쳐지고 마지막 화면이 닫히면 끊긴다 — 그 성질을 여기서 못박는다.
      expect('snapshots()'.allMatches(code).length, 2,
          reason: '상시 구독 1(선택 사업장) + 화면 수명 구독 1(대상 사업장)');
      expect(code.contains('if (cur.count <= 1) {'), true,
          reason: '화면 수명 구독이 해제 경로를 잃으면 상시 구독이 된다');
      expect(code.contains('for (final e in _targetPermsSubs.values) {'), true,
          reason: 'provider dispose에서도 전부 끊어야 한다');
    });

    test('11-c 액션마다 조회하지 않는다 (§5)', () {
      for (final p in [_cardPath, _dayPath, _workDetailPath]) {
        final code = _codeOf(_src(p));
        expect(code.contains('getMemberPermissions('), false, reason: p);
      }
    });

    test('11-d 새 callable이 없다 (§6)', () {
      final code = _codeOf(_src(_providerPath));
      expect(code.contains('httpsCallable'), false);
      expect(code.contains('collectionGroup'), false);
      final body = _flat(_codeOf(_bodyOf(
          _src(_providerPath), 'Future<void> _hydrateSubAdminPermissions(')));
      expect(body.contains('MemberService().getMemberPermissions(bizId, uid)'),
          true, reason: '기존 canonical member read를 재사용해야 한다');
    });

    test('11-e 하이드레이션 지점이 배선돼 있다 (§12, §42)', () {
      final code = _codeOf(_src(_providerPath));
      // [POSTING-V2-03B.1] +1 — 명시적 access refresh(force)
      expect('_hydrateSubAdminPermissions('.allMatches(code).length, 5,
          reason: '정의 1 + 초기 로드 / 관리자 모드 전환 / 사용자 갱신 / access refresh');
    });
  });

  // ── §4, §35, §58 범위 밖 무변경 ─────────────────────────────────
  group('CAP-12 범위 밖 무변경', () {
    test('12-a 기존 can() semantics 무변경 (§4)', () {
      final body = _flat(_codeOf(_bodyOf(_src(_providerPath), 'bool can(')));
      expect(
          body.contains('if (_currentUser?.isBusinessAdmin == true) return true; '
              'if (_memberPermissions != null) return check(_memberPermissions!); '
              'return false;'),
          true);
    });

    test('12-b 선택-사업장 권한과 listener가 남아 있다 (§13)', () {
      final code = _codeOf(_src(_providerPath));
      expect(code.contains('MemberPermissions? _memberPermissions;'), true);
      expect(code.contains('MemberPermissions? get memberPermissions =>'), true);
      expect(code.contains('bool get permissionsLoaded => _permissionsLoaded;'), true);
    });

    test('12-c read scope 무변경 (§35)', () {
      // [POSTING-V2-03N.1] scope 결정은 _scopeOf로 옮겨졌다 — 내용은 그대로.
      final body = _flat(_codeOf(
          _bodyOf(_src(_ctrlPath), 'List<String>? _scopeOf(UserModel user)')));
      expect(body.contains('if (user.isSubAdmin) return user.subAdminBusinessIds;'),
          true);
      expect(body.contains('return user.managedBusinessIds;'), true);
      expect(body.contains('canManageTo'), false,
          reason: '조회 범위를 manageable로 좁히면 안 된다');
    });

    test('12-d business filter 선택지가 권한으로 좁혀지지 않았다 (§35)', () {
      final body = _flat(
          _codeOf(_bodyOf(_src(_listPath), 'void _showFilterDialog(')));
      expect(body.contains('for (final g in controller.items)'), true);
      expect(body.contains('canManageTo'), false);
    });

    test('12-e 서버 permission 정책 무변경 (§58)', () {
      final fns = _src('functions/src/index.ts');
      for (final marker in [
        '[PERM-TO-02]',
        '[PERM-TO-03]',
        '[PERM-TO-04]',
        '[PERM-TO-05]',
        '[SUBADMIN-PERM-01]',
        '[SUBADMIN-PERM-REJECT]',
      ]) {
        expect(fns.contains(marker), true, reason: '$marker 가 사라졌다');
      }
      expect(fns.contains('async function assertBizAdmin('), true);
    });

    test('12-f close/reopen 문구 무변경 (§43)', () {
      final dialogs = _codeOf(
          _src('lib/screens/business_admin/dialogs/to_list_dialogs.dart'));
      expect(dialogs.contains("'공고 종료에 실패했습니다.'"), true);
      expect(dialogs.contains("'공고 재오픈에 실패했습니다.'"), true);
    });

    test('12-g 권한 map이 정리되는 지점', () {
      final code = _codeOf(_src(_providerPath));
      // [POSTING-V2-03B.1] +1 — access refresh에서 SubAdmin 자격 상실 감지
      expect('_clearSubAdminPermissionMap();'.allMatches(code).length, 3,
          reason: 'signOut 성공/실패 2 + 자격 상실 1');
      expect(code.contains('void _clearSubAdminPermissionMap() {'), true);
    });
  });
}
