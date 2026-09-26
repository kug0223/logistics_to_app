// [CROSS-DOMAIN-R5.1F.5] 선택 사업장 권한 신선도의 소비
//
// R5.1F.4에서 선택 사업장 listener도 terminal error를 기록하게 만들었다.
// 그런데 **기록만 했다.** 선택 사업장 UI는 거의 전부 bool `can(...)`을 쓰고
// 있었고, 그 값은 마지막으로 본 값이다. 그래서:
//
//   마지막 검증 = 허용 → listener terminal error → _memberPermissions 유지
//   → can(...) == true → Task와 CTA가 검증된 허용처럼 계속 남는다.
//
// 이번에 한 것:
//   · 선택 사업장용 4상태 판정 하나를 추가했다(checkCurrentBusiness).
//     값의 출처는 can()과 같고, error/unknown만 더 구분한다.
//     대상 사업장의 PermissionWatchState/PermissionCheck를 그대로 재사용한다 —
//     두 번째 권한 프레임워크를 만들지 않았다.
//   · 소비자를 셋으로 나눠, **privileged action과 sensitive read만** 옮겼다.
//     메뉴 노출·권한 요약처럼 행동 경로가 아닌 곳은 bool 그대로 둔다.
//     거기서 목록을 지우면 ERROR를 DENIED로 말하는 셈이기 때문이다.
//   · bool만 구독하던 Selector에 신선도를 더했다. 허용 값이 true→true인 채
//     전송 상태만 나빠지는 전이는 bool로는 rebuild를 만들지 못한다.
//
// 바뀌지 않은 것: can()의 의미. 값을 지우지도, ERROR를 false로 치환하지도
// 않는다 — 쓰지 않을 뿐이다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

String _load(String p) => _flat(_codeOf(_src(p)));

String _bodyOf(String raw, String signature) {
  final i = raw.indexOf(signature);
  if (i < 0) throw StateError('$signature 를 찾지 못함');
  final open = raw.indexOf('{', i);
  var depth = 0;
  for (var j = open; j < raw.length; j++) {
    if (raw[j] == '{') depth++;
    if (raw[j] == '}') {
      depth--;
      if (depth == 0) return raw.substring(i, j + 1);
    }
  }
  throw StateError('$signature 본문이 닫히지 않음');
}

const _provider = 'lib/providers/user_provider.dart';
const _home = 'lib/screens/business_admin/business_admin_home_screen.dart';
const _jobs = 'lib/screens/business_admin/jobs_root_screen.dart';
const _payroll = 'lib/screens/business_admin/payroll/payroll_overview_screen.dart';
const _queue = 'lib/screens/business_admin/unclosed_action_queue_screen.dart';
const _workforce =
    'lib/screens/business_admin/workforce_management/workforce_operational_view.dart';
const _shell = 'lib/screens/business_admin/business_admin_shell.dart';

void main() {
  final rawUp = _src(_provider);
  final up = _load(_provider);

  // ── PART B/C. 선택 사업장 4상태 ────────────────────────────────────

  group('선택 사업장도 네 상태로 판정한다', () {
    final body = _flat(_codeOf(_bodyOf(rawUp, 'PermissionCheck checkCurrentBusiness(')));

    test('기존 enum을 재사용한다 — 두 번째 framework가 없다', () {
      expect('enum PermissionCheck'.allMatches(up).length, 1);
      expect('enum PermissionWatchState'.allMatches(up).length, 1);
    });

    test('BUSINESS_ADMIN은 언제나 allowed다', () {
      expect(body.contains('if (user.isBusinessAdmin || user.isSuperAdmin) '
          'return PermissionCheck.allowed;'), true,
          reason: '소유자는 member 문서로 판정하지 않는다 — 신선도 gate의 영향을 받지 않는다');
      expect(body.indexOf('isBusinessAdmin') < body.indexOf('permissionWatchStateFor'),
          true, reason: '소유자 판정이 신선도 판정보다 먼저여야 한다');
    });

    test('구독이 error면 캐시된 허용보다 error가 먼저다', () {
      expect(
          body.contains('if (bizId != null && permissionWatchStateFor(bizId) == '
              'PermissionWatchState.error) { return PermissionCheck.error; }'),
          true);
      expect(body.indexOf('PermissionWatchState.error') <
              body.indexOf('final perms = _memberPermissions;'),
          true,
          reason: '캐시 값을 먼저 보면 stale allow가 통과한다');
    });

    test('하이드레이션 전은 unknown이다', () {
      expect(body.contains('if (!_permissionsLoaded) return PermissionCheck.unknown;'),
          true);
    });

    test('읽었는데 없으면 denied다 — membership 상실', () {
      expect(body.contains('if (perms == null) return PermissionCheck.denied;'), true);
    });

    test('verified true/false는 allowed/denied다', () {
      expect(
          body.contains('return check(perms) ? PermissionCheck.allowed '
              ': PermissionCheck.denied;'),
          true);
    });

    test('값의 출처가 can()과 같다 — allowed/denied가 갈라지지 않는다', () {
      final canBody = _flat(_codeOf(
          _bodyOf(rawUp, 'bool can(bool Function(MemberPermissions p) check) {')));
      expect(canBody.contains('_memberPermissions'), true);
      expect(body.contains('_memberPermissions'), true);
    });

    test('can()의 의미는 그대로다', () {
      final canBody = _flat(_codeOf(
          _bodyOf(rawUp, 'bool can(bool Function(MemberPermissions p) check) {')));
      expect(canBody.contains('PermissionCheck'), false,
          reason: '전역 semantics를 한 번에 바꾸지 않는다');
      expect(canBody.contains('PermissionWatchState'), false);
    });
  });

  group('신선도는 구독 가능한 값으로 노출된다', () {
    test('health getter가 있다', () {
      expect(up.contains('PermissionWatchState get currentBusinessPermissionHealth {'),
          true);
    });

    test('SUB_ADMIN이 아니면 신선도가 판정에 끼어들지 않는다', () {
      final body = _flat(_codeOf(
          _bodyOf(rawUp, 'PermissionWatchState get currentBusinessPermissionHealth {')));
      expect(body.contains('if (user == null || !user.isSubAdmin) '
          'return PermissionWatchState.verified;'), true);
    });
  });

  // ── PART F. Home ───────────────────────────────────────────────────

  group('Home은 신선도까지 구독하고, 확인된 허용만 쓴다', () {
    final home = _load(_home);

    test('Selector가 신선도를 구독한다', () {
      expect(home.contains('permissionHealth: p.currentBusinessPermissionHealth,'), true,
          reason: 'bool만 보면 true→true 전이가 rebuild를 만들지 못한다');
      expect(home.contains('PermissionWatchState permissionHealth,'), true);
    });

    test('판정은 한 자리에서 한다', () {
      expect(
          home.contains('bool _verified(UserProvider up, '
              'bool Function(MemberPermissions p) check) => '
              'up.checkCurrentBusiness(check) == PermissionCheck.allowed;'),
          true);
    });

    test('네 Task가 모두 확인된 허용을 요구한다', () {
      expect(home.contains('final canWorkers = _verified(up, (p) => p.canManageWorkers);'),
          true);
      expect(home.contains('final canTo = _verified(up, (p) => p.canManageTo);'), true);
      expect(home.contains('final canContract = _verified(up, (p) => p.canManageContract);'),
          true);
      expect(home.contains('final canWage = _verified(up, (p) => p.canManageWage);'), true);
    });

    test('`!isSub || can()` 형태가 남아 있지 않다', () {
      expect(home.contains('!isSub || up.can('), false,
          reason: 'bool 하나로는 error와 allow가 구분되지 않는다');
    });

    test('action-time 재확인도 같은 판정이다', () {
      expect(home.contains('if (!_verified(up, (p) => p.canManageWorkers)) {'), true);
      expect(home.contains('if (!_verified(up, (p) => p.canManageContract)) {'), true);
      expect(home.contains('if (!_verified(up, (p) => p.canManageWage)) {'), true);
    });

    test('권한 오류를 Task로 만들지 않는다', () {
      // 신선도 때문에 새 Task 행이 생기지 않는다 — 기존 체계만 쓴다.
      expect(home.contains("label: '권한 오류'"), false);
      expect(home.contains('PermissionWatchState.error'), false,
          reason: 'Home은 error를 직접 렌더하지 않고 _verified로 걸러낼 뿐이다');
    });

    test('정보성 한 줄은 bool 그대로다 — ERROR를 DENIED로 말하지 않는다', () {
      expect(home.contains("if (up.can((p) => p.canManageTo)) perms.add('공고');"), true,
          reason: '받은 권한 목록이지 행동 경로가 아니다');
    });
  });

  // ── PART G. 탭 루트 ────────────────────────────────────────────────

  group('탭 루트는 신선도 전이에도 재평가된다', () {
    test('공고 탭 — 4상태를 구독한다', () {
      final s = _load(_jobs);
      expect(
          s.contains('if (context.select<UserProvider, PermissionCheck>( '
              '(p) => p.checkCurrentBusiness((x) => x.canManageTo)) == '
              'PermissionCheck.allowed)'),
          true,
          reason: 'bool을 구독하면 값이 true→true라 다시 그리지 않는다');
      expect(s.contains('p.can((x) => x.canManageTo)'), false);
    });

    test('운영 뷰 — 4상태를 구독한다', () {
      final s = _load(_workforce);
      expect(
          s.contains('if (context.select<UserProvider, PermissionCheck>( '
              '(p) => p.checkCurrentBusiness((x) => x.canManageWorkers)) == '
              'PermissionCheck.allowed)'),
          true);
      expect(s.contains('if (check != PermissionCheck.allowed) {'), true,
          reason: 'action-time도 같은 판정');
      expect(s.contains("? '근로자 관리 권한이 없습니다' : '권한 정보를 확인하지 못했습니다. "
          "잠시 후 다시 시도해주세요.'"), true,
          reason: '거부와 확인 실패가 다른 말을 한다');
    });

    test('급여 개요 — 확인 실패를 권한 없음과 구분한다', () {
      final s = _load(_payroll);
      expect(s.contains('final check = _userProvider.checkCurrentBusiness('
          '(p) => p.canManageWage);'), true);
      expect(s.contains('final unverified = check == PermissionCheck.error || '
          'check == PermissionCheck.unknown;'), true);
      expect(s.contains("title: '권한 정보를 확인하지 못했습니다',"), true);
      expect(s.contains("title: '접근 권한이 없습니다',"), true,
          reason: '확인된 거부는 그대로 권한 없음이다');
    });

    test('급여 개요 — 진입 gate도 4상태다', () {
      final s = _load(_payroll);
      expect(
          s.contains('final entryCheck = userProvider.checkCurrentBusiness('
              '(p) => p.canManageWage); if (entryCheck != PermissionCheck.allowed) {'),
          true);
    });

    test('미마감 큐 — 확인 실패에서 되돌리지 않는다', () {
      final s = _load(_queue);
      expect(s.contains('if (entry == PermissionCheck.denied) { '
          'Navigator.of(context).pop(); return; }'), true,
          reason: '확인하지 못한 상태에서 pop하면 ERROR를 DENIED로 말하는 것이다');
      expect(s.contains("title: '권한 정보를 확인하지 못했습니다',"), true);
      expect(s.contains('if (!_accessUnverified) _load();'), true,
          reason: '확인되지 않은 상태에서 조회하지 않는다');
    });

    test('미마감 큐 — 확인되면 미뤘던 조회를 한다', () {
      final s = _load(_queue);
      expect(s.contains('if (wasUnverified && allowed) _load();'), true);
    });
  });

  // ── PART D. 소비자 분류 ────────────────────────────────────────────

  group('소비자 분류가 지켜진다', () {
    test('privileged action에 선택-사업장 bool can()이 남아 있지 않다', () {
      const privileged = [
        'lib/screens/business_admin/dialogs/attendance_status_dialog.dart',
        'lib/screens/business_admin/dialogs/work_detail_management_dialog.dart',
        'lib/widgets/dialogs/worker_detail_dialog.dart',
        'lib/screens/business_admin/dialogs/fixed_worker_management_dialog.dart',
        'lib/screens/business_admin/to_management/create_to_screen.dart',
        'lib/screens/business_admin/contract_template_list_screen.dart',
        'lib/screens/business_admin/admin_stats_screen.dart',
        'lib/screens/business_admin/business_list_screen.dart',
      ];
      for (final p in privileged) {
        final code = _codeOf(_src(p));
        expect(RegExp(r'\.can\(\((p|x)\)').hasMatch(code), false, reason: p);
      }
    });

    test('탭을 없애는 것은 확인된 거부의 표현이다', () {
      // [R5-G] 이 테스트의 이유문이 원래부터 말하고 있던 것을 코드가 이제
      //   지킨다. bool can() 은 확인 실패도 false 로 돌려주므로, 그것으로
      //   탭을 지우면 ERROR 를 DENIED 로 말하는 것이었다. 각 탭 루트가
      //   안에서 fail-closed 이므로 모르는 동안 자리를 지켜도 안전하다.
      final s = _load(_shell);
      expect(
        s.contains('if (!up.checkCurrentBusiness((p) => p.canManageWorkers)'),
        true,
        reason: '확인 실패로 탭이 사라지면 ERROR를 DENIED로 말하는 것이고, '
            '각 탭 루트가 이미 안에서 fail-closed다',
      );
      expect(s.contains('if (up.can((p) => p.canManageWorkers)) 2,'), false);
    });

    test('sensitive read도 확인된 허용을 요구한다', () {
      final s = _load('lib/screens/business_admin/admin_stats_screen.dart');
      expect(
          s.contains('if (userProvider.checkCurrentBusiness((p) => p.canManageWage) '
              '!= PermissionCheck.allowed) {'),
          true);
    });
  });

  // ── PART H/I. 회복과 소유자 ────────────────────────────────────────

  group('회복은 기존 경로를 쓴다', () {
    test('재로그인을 요구하지 않는다', () {
      for (final p in [_payroll, _queue]) {
        final s = _load(p);
        expect(s.contains('signOut'), false, reason: p);
      }
    });

    test('기존 access refresh를 재사용한다 — 새 trigger가 없다', () {
      final s = _load(_payroll);
      expect(s.contains('_userProvider.refreshSubAdminAccessState()'), true);
      final q = _load(_queue);
      expect(q.contains('_userProvider?.refreshSubAdminAccessState()'), true);
    });

    test('폴링이나 전체 reload가 없다', () {
      for (final p in [_payroll, _queue, _jobs, _workforce, _home]) {
        final code = _codeOf(_src(p));
        expect(code.contains('Timer.periodic'), false, reason: p);
      }
    });
  });

  group('BUSINESS_ADMIN은 영향받지 않는다', () {
    test('소유자 판정이 신선도보다 먼저다', () {
      final body = _flat(_codeOf(_bodyOf(rawUp, 'PermissionCheck checkCurrentBusiness(')));
      final ownerAt = body.indexOf('user.isBusinessAdmin');
      final healthAt = body.indexOf('permissionWatchStateFor');
      final loadedAt = body.indexOf('_permissionsLoaded');
      expect(ownerAt >= 0 && ownerAt < healthAt && ownerAt < loadedAt, true);
    });

    test('소유자는 member 구독 대상이 아니다', () {
      expect(up.contains('if (businessId.isEmpty || user == null || !user.isSubAdmin) '
          '{ return () {}; }'), true);
    });
  });
}
