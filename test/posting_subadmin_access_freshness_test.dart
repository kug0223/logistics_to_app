// [POSTING-V2-03B.1] SubAdmin 접근 상태 freshness
//
// 03B READ에서 확인된 것:
//   · 02G.1이 권한 판정 근거를 _memberPermissions(listener 있음)에서
//     사업장별 map(listener 없음)으로 옮기면서, 실시간 권한 회수가
//     Posting UI에 반영되지 않게 됐다 — 이번 시리즈가 만든 회귀다.
//   · users/{uid}에는 realtime listener가 없고 비선택 사업장 member 문서에도 없다.
//   · 배정 해제된 사업장 id를 그대로 보내면 callableGetAdminTOs의
//     Promise.all(ids.map(assertBizAdmin))가 통째로 reject돼
//     정상 사업장 공고까지 목록 전체가 error가 된다.
//   · WorkApplicantsDialog는 생성자 snapshot을 계속 canonical로 썼다.
//
// UserProvider는 생성자에서 Firebase auth 스트림을 구독해 단위 테스트로
// 인스턴스화할 수 없다. 판정 로직은 순수 replica로, 배선은 소스로 고정한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/business_member_model.dart';

const _providerPath = 'lib/providers/user_provider.dart';
const _listPath =
    'lib/screens/business_admin/workforce_management/workforce_list_view.dart';
const _jobsPath = 'lib/screens/business_admin/jobs_root_screen.dart';
const _createToPath =
    'lib/screens/business_admin/to_management/create_to_screen.dart';
const _workPath =
    'lib/screens/business_admin/dialogs/work_applicants_dialog.dart';
const _dayPath =
    'lib/screens/business_admin/dialogs/day_applicants_dialog.dart';
const _ctrlPath = 'lib/controllers/workforce_controller.dart';

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

// ── access state replica ─────────────────────────────────────────
// map 갱신 / prune / 판정 계약을 그대로 옮긴다.

class _Access {
  List<String> assigned;
  Map<String, MemberPermissions> map;
  bool loaded;

  _Access({
    required this.assigned,
    Map<String, MemberPermissions>? map,
    this.loaded = true,
  }) : map = {...?map};

  /// _setBusinessPermission — listener snapshot 1건 반영
  void setBusinessPermission(String bizId, MemberPermissions? perms) {
    if (perms == null) {
      map.remove(bizId);
    } else {
      map[bizId] = perms;
    }
  }

  /// refreshSubAdminAccessState — 최신 배정 + 전체 권한 강제 재조회
  void refresh(
    List<String> serverAssigned,
    Map<String, MemberPermissions> serverPerms,
  ) {
    assigned = List.of(serverAssigned);
    map = {
      for (final id in serverAssigned)
        if (serverPerms[id] != null) id: serverPerms[id]!,
    };
    loaded = true;
  }

  bool canForBusiness(String bizId, bool Function(MemberPermissions p) check) {
    final p = map[bizId];
    if (p == null) return false;
    return check(p);
  }

  bool get canManagePostingAnywhere =>
      assigned.any((id) => canForBusiness(id, (p) => p.canManageTo));

  /// 서버에 보낼 scope — stale revoked id가 섞이면 전체 request가 거부된다.
  List<String> get postingScope => List.of(assigned);

  /// CreateTO picker — membership ∩ canManageTo
  List<String> get createToPicker =>
      assigned.where((id) => canForBusiness(id, (p) => p.canManageTo)).toList();
}

const _manage = MemberPermissions(canManageTo: true);
const _noManage = MemberPermissions();
const _contractOnly = MemberPermissions(canManageContract: true);

void main() {
  // ── §1 선택 사업장 listener → canonical map ─────────────────────
  group('FRESH-01 선택 사업장 권한 회수/부여가 즉시 map에 반영된다', () {
    test('01-a revoke: canManageTo true → false', () {
      final a = _Access(assigned: ['A', 'B'], map: {'A': _manage, 'B': _manage});
      expect(a.canForBusiness('A', (p) => p.canManageTo), true);
      a.setBusinessPermission('A', _noManage); // listener snapshot
      expect(a.canForBusiness('A', (p) => p.canManageTo), false);
      expect(a.canForBusiness('B', (p) => p.canManageTo), true,
          reason: '다른 사업장까지 건드리면 안 된다');
    });

    test('01-b grant: false → true', () {
      final a = _Access(assigned: ['A'], map: {'A': _noManage});
      a.setBusinessPermission('A', _manage);
      expect(a.canForBusiness('A', (p) => p.canManageTo), true);
      expect(a.canManagePostingAnywhere, true);
    });

    test('01-c member 문서 삭제 → entry 제거 (fail-closed)', () {
      final a = _Access(assigned: ['A', 'B'], map: {'A': _manage, 'B': _manage});
      a.setBusinessPermission('A', null);
      expect(a.canForBusiness('A', (p) => p.canManageTo), false);
      expect(a.map.containsKey('A'), false);
    });

    test('01-d listener가 같은 snapshot으로 map을 정렬한다', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_providerPath), 'void _startMemberPermsListener(')));
      expect(body.contains('_setBusinessPermission(businessId, _memberPermissions);'),
          true, reason: 'listener가 map을 갱신하지 않으면 02G.1 회귀가 남는다');
      expect(body.contains('_setBusinessPermission(businessId, null);'), true,
          reason: '문서 삭제 시 map에서도 빠져야 한다');
      // in-flight switch 무효화는 그대로
      expect(body.contains('_switchGeneration++;'), true);
      // [C2] 관리자 모드 종료는 listener가 단독으로 결정하지 않는다
      expect(body.contains('_recoverFromSelectedMembershipLoss(businessId)'), true);
    });

    test('01-e 새 listener도 새 read도 없다 (§1 조건)', () {
      final code = _codeOf(_src(_providerPath));
      expect('snapshots()'.allMatches(code).length, 1,
          reason: 'realtime listener는 선택 사업장 하나뿐이어야 한다');
      final setter = _codeOf(
          _bodyOf(_src(_providerPath), 'void _setBusinessPermission('));
      for (final forbidden in ['await', 'getMemberPermissions', 'FirebaseFirestore']) {
        expect(setter.contains(forbidden), false,
            reason: 'map 반영에 $forbidden 이 들어감 — 추가 read');
      }
    });
  });

  // ── §2 explicit access refresh ──────────────────────────────────
  group('FRESH-02 명시적 access refresh가 강제 재검증한다', () {
    test('02-a 배정 동일 + 권한만 변경 → 반영된다', () {
      final a = _Access(assigned: ['A', 'B'], map: {'A': _manage, 'B': _manage});
      // 서버에서 B의 canManageTo만 회수됨 (배정 집합은 그대로)
      a.refresh(['A', 'B'], {'A': _manage, 'B': _noManage});
      expect(a.canForBusiness('B', (p) => p.canManageTo), false,
          reason: '캐시 비교로는 권한 변경을 알 수 없다 — force가 필요하다');
      expect(a.canForBusiness('A', (p) => p.canManageTo), true);
    });

    test('02-b force 파라미터가 캐시 최적화를 건너뛴다', () {
      final body = _flat(_codeOf(_bodyOf(
          _src(_providerPath), 'Future<void> _hydrateSubAdminPermissions(')));
      expect(body.contains('bool force = false,'), true);
      expect(body.contains('if (!force && _subAdminPermissionsLoaded &&'), true);
    });

    test('02-c 일반 하이드레이션의 최적화는 유지된다', () {
      final code = _codeOf(_src(_providerPath));
      // 명시 refresh만 force: true
      expect('force: true'.allMatches(code).length, 1);
      final body = _flat(_codeOf(_bodyOf(
          _src(_providerPath), 'Future<void> _hydrateSubAdminPermissions(')));
      expect(
          body.contains('_hydratedPermissionBusinessIds.containsAll(idSet)) { return;'),
          true,
          reason: '탭 전환마다 N reads를 하지 않는 기존 최적화가 사라졌다');
    });

    test('02-d refresh가 users 문서를 다시 읽는다', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_providerPath), 'Future<void> _runSubAdminAccessRefresh(')));
      expect(body.contains("collection('users').doc(uid).get()"), true);
      expect(body.contains('_currentUser = UserModel.fromMap(data, doc.id);'), true);
      expect(body.contains('_hydrateSubAdminPermissions(refreshed, uid, force: true)'),
          true);
      expect(body.contains('notifyListeners();'), true);
    });

    test('02-e 배정 조회 실패 시 기존 상태를 유지한다', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_providerPath), 'Future<void> _runSubAdminAccessRefresh(')));
      expect(body.contains('} catch (e) {'), true);
      expect(body.contains("debugPrint('⚠️ [03B.1] 배정 갱신 실패: \$e');"), true,
          reason: '읽지 못한 배정을 추측해서 줄이면 안 된다');
    });

    test('02-f 동시 호출이 하나로 합쳐진다', () {
      final body = _flat(_codeOf(_bodyOf(
          _src(_providerPath), 'Future<void> refreshSubAdminAccessState(')));
      expect(body.contains('final inFlight = _accessRefreshInFlight;'), true);
      expect(body.contains('if (inFlight != null) return inFlight;'), true,
          reason: 'resume과 당겨서 새로고침이 겹치면 read가 두 배가 된다');
    });
  });

  // ── §11 membership revoke ───────────────────────────────────────
  group('FRESH-03 배정 해제가 재시작 없이 회복된다', () {
    test('03-a B 해제 → map prune + scope에서 제외', () {
      final a = _Access(assigned: ['A', 'B'], map: {'A': _manage, 'B': _manage});
      expect(a.postingScope, ['A', 'B']);
      a.refresh(['A'], {'A': _manage});
      expect(a.assigned, ['A']);
      expect(a.map.containsKey('B'), false);
      expect(a.postingScope, ['A'],
          reason: 'stale revoked id를 보내면 서버가 전체 request를 거부한다');
      expect(a.createToPicker, ['A']);
      expect(a.canForBusiness('B', (p) => p.canManageTo), false);
    });

    test('03-b 선택 사업장이 배정에서 빠지면 정리한다', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_providerPath), 'Future<void> _runSubAdminAccessRefresh(')));
      expect(
          body.contains(
              'if (selected != null && !refreshed.subAdminBusinessIds.contains(selected)) '
              '{ _selectedSubAdminBusinessId = null; _memberPermsSub?.cancel();'),
          true);
      // 새 선택 사업장으로 listener를 옮긴다
      expect(
          body.contains('if (active != null && _memberPermsSub == null) { '
              '_startMemberPermsListener(active, uid);'),
          true);
    });

    test('03-c access → data 순서로 전체 error를 예방한다 (§4)', () {
      final body = _codeOf(_bodyOf(_src(_listPath), 'Future<void> _reload('));
      final accessIdx = body.indexOf('refreshSubAdminAccessState()');
      final reloadIdx = body.indexOf('controller.reload(context)');
      expect(accessIdx, greaterThan(-1), reason: 'access refresh가 없다');
      expect(reloadIdx, greaterThan(accessIdx),
          reason: 'stale scope로 서버를 먼저 부르면 all-or-nothing으로 거부된다');
    });

    test('03-d 서버 all-or-nothing 정책은 건드리지 않았다 (§13)', () {
      final fns = _src('functions/src/index.ts');
      expect(
          _flat(fns).contains(
              'await Promise.all(ids.map(id => assertBizAdmin(callerUid, id)));'),
          true,
          reason: '[BACKLOG-ADMIN-TOS-ALL-OR-NOTHING-SCOPE-ASSERT] 유지');
    });
  });

  // ── §12 membership grant ────────────────────────────────────────
  group('FRESH-04 배정 추가가 재시작 없이 반영된다', () {
    test('04-a 다른 session에서 추가된 B가 refresh로 들어온다', () {
      final a = _Access(assigned: ['A'], map: {'A': _manage});
      a.refresh(['A', 'B'], {'A': _manage, 'B': _manage});
      expect(a.assigned, ['A', 'B']);
      expect(a.canForBusiness('B', (p) => p.canManageTo), true);
      expect(a.postingScope, ['A', 'B']);
      expect(a.createToPicker, ['A', 'B']);
    });

    test('04-b 현재 기기 초대 수락 경로가 회귀하지 않았다', () {
      final notif =
          _codeOf(_src('lib/screens/common/notification_screen.dart'));
      expect(notif.contains('await MemberService().acceptInvitation(invitation);'),
          true);
      expect(notif.contains('await userProvider.refreshUserData();'), true,
          reason: '기존 LIVE_OK 경로를 깨면 안 된다');
    });
  });

  // ── §5 trigger matrix ───────────────────────────────────────────
  group('FRESH-05 refresh trigger', () {
    test('05-a 당겨서 새로고침 / 에러 재시도 (SUB_ADMIN 한정)', () {
      final body = _flat(_codeOf(_bodyOf(_src(_listPath), 'Future<void> _reload(')));
      expect(body.contains('if (up.isSubAdmin) { await up.refreshSubAdminAccessState();'),
          true, reason: 'BUSINESS_ADMIN/SUPER_ADMIN 동작을 바꾸지 않는다');
      // 에러 재시도도 같은 _reload를 쓴다
      final err = _codeOf(_bodyOf(_src(_listPath), 'Widget _buildErrorState('));
      expect(err.contains('onPressed: _reload,'), true);
    });

    test('05-b 앱 복귀 — access → data 순서', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_jobsPath), 'void didChangeAppLifecycleState(')));
      expect(
          body.contains('up.refreshSubAdminAccessState().whenComplete(() { '
              'if (mounted) _controller.reload(context); });'),
          true);
      expect(body.contains('} else { _controller.reload(context); }'), true,
          reason: '비SubAdmin은 기존 동작 유지');
      // 기존 쿨다운 보존
      expect(body.contains('const Duration(minutes: 2)'), true);
    });

    test('05-c 탭 전환마다 N reads를 하지 않는다 (§6)', () {
      // Shell 탭 전환 경로에 access refresh를 심지 않았다
      final shell =
          _codeOf(_src('lib/screens/business_admin/business_admin_shell.dart'));
      expect(shell.contains('refreshSubAdminAccessState'), false);
      // JobsRootScreen initState에도 없다 — resume/pull/retry/CreateTO만
      final init = _codeOf(_bodyOf(_src(_jobsPath), 'void initState('));
      expect(init.contains('refreshSubAdminAccessState'), false);
    });

    test('05-d CreateTO 진입 시 1회 (§7)', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_createToPath), 'Future<void> _loadMyBusinesses(')));
      expect(
          body.contains(
              'if (refreshAccess && userProvider.isSubAdmin) { await userProvider.refreshSubAdminAccessState();'),
          true);
      expect('refreshSubAdminAccessState'.allMatches(body).length, 1,
          reason: '중복 refresh');
      // provider가 이미 아는 변화로 재로드할 때는 refresh를 건너뛴다
      expect(
          _flat(_codeOf(_src(_createToPath)))
              .contains('_loadMyBusinesses(refreshAccess: false)'),
          true);
    });

    test('05-e refresh 호출 지점이 정해진 넷뿐이다', () {
      var hits = 0;
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final code = _codeOf(f.readAsStringSync());
        if (f.path.endsWith('user_provider.dart')) continue; // 정의 측 제외
        hits += 'refreshSubAdminAccessState()'.allMatches(code).length;
      }
      // pull/retry(공유) 1 + resume 1 + CreateTO 진입 1 + CreateTO submit preflight 1
      expect(hits, 4, reason: '무분별한 refresh 추가 금지');
    });
  });

  // ── §8, §9 open surface ─────────────────────────────────────────
  group('FRESH-06 열린 dialog가 stale snapshot을 쓰지 않는다', () {
    test('06-a WorkApplicants: LOADED면 provider가 canonical', () {
      final body = _flat(
          _codeOf(_bodyOf(_src(_workPath), 'bool _permissionFor(')));
      expect(body.contains('if (up.subAdminPermissionsLoaded) { '
          'return up.canForBusiness(widget.toItem.to.businessId, check); }'), true,
          reason: '생성자 snapshot이 최신 값을 덮으면 안 된다');
    });

    test('06-b UNKNOWN일 때만 알림 snapshot으로 폴백 (tri-state 유지)', () {
      final body = _flat(
          _codeOf(_bodyOf(_src(_workPath), 'bool _permissionFor(')));
      final loadedIdx = body.indexOf('if (up.subAdminPermissionsLoaded)');
      final targetIdx = body.indexOf('final target = widget.targetPermissions;');
      expect(loadedIdx, greaterThan(-1));
      expect(targetIdx, greaterThan(loadedIdx),
          reason: 'UNKNOWN ≠ DENIED — 폴백이 LOADED 판정보다 앞서면 안 된다');
      expect(body.contains('return false; '), true, reason: 'fail-closed 기본값');
    });

    test('06-c owner/super는 그대로 통과', () {
      final body = _flat(
          _codeOf(_bodyOf(_src(_workPath), 'bool _permissionFor(')));
      expect(body.contains('if (user.isBusinessAdmin || user.isSuperAdmin) return true;'),
          true);
    });

    test('06-d 두 dialog가 권한 변경에 rebuild한다', () {
      for (final p in [_workPath, _dayPath]) {
        final build = _codeOf(_bodyOf(_src(p), 'Widget build(BuildContext context)'));
        expect(build.contains('context.watch<UserProvider>();'), true, reason: p);
      }
      // 평가 자체는 read — 이벤트 핸들러에서도 호출되기 때문
      final work = _codeOf(_bodyOf(_src(_workPath), 'bool _permissionFor('));
      expect(work.contains('context.read<UserProvider>()'), true);
      final day = _codeOf(_bodyOf(_src(_dayPath), 'bool _canForSelectedBiz('));
      expect(day.contains('listen: false'), true);
    });

    test('06-e canManageContract도 같은 경로를 쓴다 (§9)', () {
      final code = _flat(_codeOf(_src(_workPath)));
      expect(code.contains('bool _canManageTo() => _permissionFor((p) => p.canManageTo);'),
          true);
      expect(
          code.contains(
              'bool _canManageContract() => _permissionFor((p) => p.canManageContract);'),
          true);
    });

    test('06-f contract-only 사업장이 정확히 갈린다', () {
      final a = _Access(assigned: ['B'], map: {'B': _contractOnly});
      expect(a.canForBusiness('B', (p) => p.canManageTo), false);
      expect(a.canForBusiness('B', (p) => p.canManageContract), true);
    });
  });

  // ── §14 시나리오 matrix (selected / non-selected) ───────────────
  group('FRESH-07 시나리오', () {
    test('07-a selected revoke → 탭·CreateTO 즉시 반영', () {
      final a = _Access(assigned: ['A', 'B'], map: {'A': _manage, 'B': _noManage});
      expect(a.canManagePostingAnywhere, true);
      expect(a.createToPicker, ['A']);
      a.setBusinessPermission('A', _noManage); // listener
      expect(a.canManagePostingAnywhere, false, reason: '공고 탭이 숨겨져야 한다');
      expect(a.createToPicker, isEmpty);
    });

    test('07-b non-selected revoke → refresh 후 반영', () {
      final a = _Access(assigned: ['A', 'B'], map: {'A': _manage, 'B': _manage});
      expect(a.createToPicker, ['A', 'B']);
      // listener 없음 — refresh 전에는 stale
      a.refresh(['A', 'B'], {'A': _manage, 'B': _noManage});
      expect(a.createToPicker, ['A']);
      expect(a.canForBusiness('B', (p) => p.canManageTo), false);
    });

    test('07-c non-selected grant → refresh 후 capability 노출', () {
      final a = _Access(assigned: ['A', 'B'], map: {'A': _manage, 'B': _noManage});
      a.refresh(['A', 'B'], {'A': _manage, 'B': _manage});
      expect(a.createToPicker, ['A', 'B']);
    });

    test('07-d 전부 회수되면 공고 탭이 사라진다', () {
      final a = _Access(assigned: ['A', 'B'], map: {'A': _manage, 'B': _manage});
      a.refresh(['A', 'B'], {'A': _noManage, 'B': _noManage});
      expect(a.canManagePostingAnywhere, false);
    });
  });

  // ── BLOCKER 1: selected membership ≠ 관리자 자격 ───────────────
  group('FRESH-09 선택 사업장 하나를 잃어도 다른 배정이 남으면 유지한다', () {
    /// 복구 판정 replica — refresh 실패까지 고려해 잃은 사업장만 제외한다.
    bool endsAdminMode(List<String> assignedAfter, String lost) =>
        assignedAfter.where((id) => id != lost).isEmpty;

    test('09-a assigned [A,B] · selected B 회수 → 관리자 모드 유지', () {
      expect(endsAdminMode(['A'], 'B'), false);
      final a = _Access(assigned: ['A', 'B'], map: {'A': _manage, 'B': _manage});
      a.setBusinessPermission('B', null); // listener delete
      a.refresh(['A'], {'A': _manage}); // 복구
      expect(a.assigned, ['A']);
      expect(a.canManagePostingAnywhere, true, reason: 'A 관리 권한은 그대로다');
      expect(a.postingScope, ['A']);
      expect(a.createToPicker, ['A']);
      expect(a.canForBusiness('B', (p) => p.canManageTo), false);
    });

    test('09-b assigned [B] 하나뿐 · B 회수 → 관리자 모드 종료', () {
      expect(endsAdminMode(const [], 'B'), true);
    });

    test('09-c 배정 조회 실패해도 잃은 사업장은 제외하고 판단한다', () {
      // refresh가 실패해 stale 목록 [A,B]가 남아도 B는 확실히 잃었다.
      expect(endsAdminMode(['A', 'B'], 'B'), false, reason: 'A가 남아 유지');
      expect(endsAdminMode(['B'], 'B'), true, reason: '잃은 것뿐이면 종료');
    });

    test('09-d listener가 즉시 종료하지 않고 최신 배정을 확인한다', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_providerPath), 'void _startMemberPermsListener(')));
      expect(body.contains('_recoverFromSelectedMembershipLoss(businessId)'), true);
      // 무조건 종료하던 코드가 남아 있으면 안 된다
      expect(
          body.contains('if (_isAdminMode) { _isAdminMode = false; '
              '_permissionsLoaded = false;'),
          false,
          reason: '다중 배정 SubAdmin이 남은 사업장까지 잃는다');
    });

    test('09-e 복구 판정이 잃은 사업장만 제외한다', () {
      final body = _flat(_codeOf(_bodyOf(
          _src(_providerPath), 'Future<void> _recoverFromSelectedMembershipLoss(')));
      expect(body.contains('await refreshSubAdminAccessState();'), true);
      expect(
          body.contains(
              'user.subAdminBusinessIds.where((id) => id != lostBusinessId).toList();'),
          true);
      expect(body.contains('if (remaining.isEmpty) { _endAdminMode(); return; }'),
          true);
    });

    test('09-f 종료 경로는 기존 SM-05 정리 패턴 그대로다', () {
      final body =
          _flat(_codeOf(_bodyOf(_src(_providerPath), 'void _endAdminMode(')));
      expect(body.contains('_isAdminMode = false;'), true);
      expect(body.contains('_permissionsLoaded = false;'), true);
      expect(body.contains('FCMService().updateAdminStatus(false);'), true);
      expect(body.contains('prefs.setBool(_kSubAdminIsAdminModeKey, false);'), true);
    });

    test('09-g 새 selected는 기존 canonical resolver가 정한다 (§4)', () {
      // effectiveBusinessId: 유효하면 유지, 아니면 첫 배정. 새 정책을 만들지 않았다.
      final getter =
          _flat(_codeOf(_bodyOf(_src(_providerPath), 'String? get effectiveBusinessId')));
      expect(getter.contains('if (selected != null && user.subAdminBusinessIds.contains(selected))'),
          true);
      expect(getter.contains('return user.subAdminBusinessIds.firstOrNull;'), true);
      final refresh = _flat(_codeOf(_bodyOf(
          _src(_providerPath), 'Future<void> _runSubAdminAccessRefresh(')));
      expect(refresh.contains('final active = effectiveBusinessId;'), true,
          reason: '별도 ordering 정책을 만들면 안 된다');
      expect(refresh.contains('ids.first'), false);
    });

    test('09-h listener를 새 selected로 옮기고 저장값도 정렬한다 (§5)', () {
      final body = _flat(_codeOf(_bodyOf(
          _src(_providerPath), 'Future<void> _runSubAdminAccessRefresh(')));
      expect(
          body.contains('if (active != null && _memberPermsSub == null) { '
              '_startMemberPermsListener(active, uid);'),
          true);
      expect(body.contains('prefs.setString(_kSubAdminLastBizKey, active);'), true);
      // 중복 구독 방지: 연결 전 cancel은 listener 정의에 그대로 있다
      final listener = _flat(_codeOf(
          _bodyOf(_src(_providerPath), 'void _startMemberPermsListener(')));
      expect(listener.contains('_memberPermsSub?.cancel();'), true);
    });
  });

  // ── BLOCKER 2: 이미 열린 CreateTO ───────────────────────────────
  group('FRESH-10 열린 CreateTO가 접근 변화를 반영한다', () {
    test('10-a provider 변경을 구독한다', () {
      final code = _flat(_codeOf(_src(_createToPath)));
      expect(
          code.contains('_accessProvider = Provider.of<UserProvider>(context, listen: false) '
              '..addListener(_onAccessStateChanged);'),
          true);
      expect(code.contains('_accessProvider?.removeListener(_onAccessStateChanged);'),
          true, reason: 'listener 누수');
    });

    test('10-b 실제 eligibility 변화에만 반응한다', () {
      final body = _flat(
          _codeOf(_bodyOf(_src(_createToPath), 'void _onAccessStateChanged(')));
      expect(body.contains('if (setEquals(eligible, _eligibleBusinessIds)) return;'),
          true, reason: '매 notify마다 재로드하면 안 된다');
      expect(body.contains('_loadMyBusinesses(refreshAccess: false);'), true,
          reason: 'provider가 이미 아는 변화에 access refresh를 또 돌리면 안 된다');
    });

    test('10-c 선택한 사업장이 자격을 잃으면 폼을 잠근다', () {
      final body = _flat(
          _codeOf(_bodyOf(_src(_createToPath), 'void _onAccessStateChanged(')));
      expect(body.contains('_formUnlocked = false; _selectedBusiness = null;'), true,
          reason: '일방향 래치 때문에 무효한 선택으로 입력을 계속하게 된다');
      expect(body.contains("ToastHelper.showError('선택한 사업장의 공고 관리 권한이 변경되었습니다')"),
          true);
    });

    test('10-d eligibility는 membership ∩ canManageTo로 계산한다', () {
      final body = _flat(
          _codeOf(_bodyOf(_src(_createToPath), 'Set<String> _computeEligible(')));
      expect(body.contains('up.currentUser?.subAdminBusinessIds'), true);
      expect(body.contains('up.canForBusiness(id, (p) => p.canManageTo)'), true);
    });

    test('10-e picker 필터가 같은 규칙을 쓴다 (02G.1 무회귀)', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_createToPath), 'Future<void> _loadMyBusinesses(')));
      expect(
          body.contains('membershipBusinesses .where((b) => '
              'userProvider.canForBusiness(b.id, (p) => p.canManageTo)) .toList();'),
          true);
    });
  });

  group('FRESH-11 submit preflight', () {
    test('11-a 제출 전에 접근 상태를 재검증한다', () {
      final body = _flat(_codeOf(_bodyOf(_src(_createToPath), 'Future<void> _createTO(')));
      expect(body.contains('if (submitUp.isSubAdmin) { await submitUp.refreshSubAdminAccessState();'),
          true);
      expect(
          body.contains(
              'submitUp.canForBusiness(targetBizId, (p) => p.canManageTo);'),
          true);
      expect(body.contains('subAdminBusinessIds.contains(targetBizId)'), true,
          reason: 'membership도 함께 확인해야 한다');
    });

    test('11-b 무효면 callable을 보내지 않는다', () {
      final body = _codeOf(_bodyOf(_src(_createToPath), 'Future<void> _createTO('));
      final guardIdx = body.indexOf('if (!stillAllowed) {');
      final callIdx = body.indexOf('callableCreateTO');
      expect(guardIdx, greaterThan(-1));
      if (callIdx > -1) {
        expect(callIdx, greaterThan(guardIdx),
            reason: 'stale 권한으로 서버 제출을 시도하면 안 된다');
      }
      expect(_flat(body).contains('if (!stillAllowed) { _scrollToSection(_businessSectionKey);'),
          true);
      expect(_flat(body).contains("ToastHelper.showError('선택한 사업장의 공고 관리 권한이 변경되었습니다'); "
          'await _loadMyBusinesses(refreshAccess: false); return; }'), true);
    });

    test('11-c 새 permission query를 복제하지 않았다', () {
      final code = _codeOf(_src(_createToPath));
      expect(code.contains('getMemberPermissions('), false,
          reason: '기존 access refresh를 재사용해야 한다');
      expect(code.contains("collection('members')"), false);
    });

    test('11-d BUSINESS_ADMIN / SUPER_ADMIN 추가 read 0', () {
      final body = _flat(_codeOf(_bodyOf(_src(_createToPath), 'Future<void> _createTO(')));
      expect(body.contains('if (submitUp.isSubAdmin) {'), true,
          reason: 'SubAdmin이 아닐 때 preflight가 돌면 read가 늘어난다');
      final load = _flat(_codeOf(
          _bodyOf(_src(_createToPath), 'Future<void> _loadMyBusinesses(')));
      expect(load.contains('if (refreshAccess && userProvider.isSubAdmin) {'), true);
    });

    test('11-e 동시 호출은 provider가 합친다', () {
      final body = _flat(_codeOf(_bodyOf(
          _src(_providerPath), 'Future<void> refreshSubAdminAccessState(')));
      expect(body.contains('if (inFlight != null) return inFlight;'), true);
    });
  });

  // ── §16, §18 범위 밖 무변경 ─────────────────────────────────────
  group('FRESH-08 범위 밖 무변경', () {
    test('08-a dataRevision을 permission bus로 쓰지 않았다 (§16)', () {
      final provider = _codeOf(_src(_providerPath));
      expect(provider.contains('notifyDataChanged'), false);
      expect(provider.contains('dataRevision'), false);
      final ctrl = _codeOf(_src(_ctrlPath));
      expect(
          ctrl.contains(
              'static void notifyDataChanged({required AdminMutationOrigin origin})'),
          true,
          reason: '02B 계약 유지');
    });

    test('08-b 서버 permission 정책·callableGetAdminTOs 무변경', () {
      final fns = _src('functions/src/index.ts');
      for (final marker in [
        '[PERM-TO-02]',
        '[SUBADMIN-PERM-01]',
        'export const callableGetAdminTOs',
        'async function assertBizAdmin(',
      ]) {
        expect(fns.contains(marker), true, reason: '$marker 가 사라졌다');
      }
    });

    test('08-c 02G canonical 무변경', () {
      final code = _codeOf(_src(_providerPath));
      expect(code.contains('bool canForBusiness('), true);
      expect(code.contains('bool canForAnyBusiness('), true);
      expect(code.contains('bool get canManagePostingAnywhere =>'), true);
      // 기존 can()도 그대로
      final can = _flat(_codeOf(_bodyOf(_src(_providerPath), 'bool can(')));
      expect(can.contains('if (_currentUser?.isBusinessAdmin == true) return true;'),
          true);
    });

    test('08-d 03A notification route 무변경', () {
      final notif = _flat(
          _codeOf(_src('lib/screens/common/notification_screen.dart')));
      expect(notif.contains('switchToJobsWithTarget(expiredToId)'), true);
      expect(notif.contains("payload['notificationId']?.toString() ?? ''"), true);
    });

    test('08-e read scope 계약 무변경', () {
      final body = _flat(_codeOf(_bodyOf(_src(_ctrlPath), 'Future<void> load(')));
      expect(body.contains('businessIds = user.subAdminBusinessIds;'), true);
      expect(body.contains('canManageTo'), false,
          reason: 'READ scope를 manageable로 좁히면 안 된다');
    });

    test('08-f 권한 상태가 비워지는 지점이 모두 남아 있다', () {
      final code = _codeOf(_src(_providerPath));
      // signOut 성공/실패 2 + refresh 결과 SubAdmin 자격 상실 1
      expect('_clearSubAdminPermissionMap();'.allMatches(code).length, 3);
      final refresh = _flat(_codeOf(_bodyOf(
          _src(_providerPath), 'Future<void> _runSubAdminAccessRefresh(')));
      expect(
          refresh.contains('if (!refreshed.isSubAdmin) { _memberPermsSub?.cancel();'),
          true,
          reason: '관리자 자격을 잃으면 남은 권한 상태를 비워야 한다');
    });
  });
}
