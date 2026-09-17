// [CROSS-DOMAIN-R5.1F.1] 탭 화면의 권한 반응성 / zero-scope Hero
//
// 두 가지를 닫는다.
//
//   1. [CORRECTION-TAB-SCREEN-PERMISSION-NOT-REACTIVE]
//      탭 화면들이 권한을 진입 시점에 한 번만 읽고 있었다. Home은 R5.1E에서
//      구독으로 바꿨지만, 나머지 화면은 그대로였다 — 머무는 동안 권한이
//      회수돼도 화면은 옛 권한으로 남았다(서버는 막는다 — CORRECTION).
//      다섯 화면은 패턴이 서로 달라서, 각자의 기존 패턴 안에서 가장 작은
//      방식으로 고쳤다:
//        · 공고 탭        build-time CTA      → context.read → context.select
//        · 급여 개요      provider listener   → 회수 방향만 보던 것을 양방향으로
//        · 계약 관리      entry guard(pop)    → listener + 거부 상태
//        · 미마감 큐      entry guard(pop)    → listener + 거부 상태
//        · 운영 뷰        action-time 무응답  → CTA 구독 + 이유 있는 거절
//
//   2. [CORRECTION-READINESS-ZERO-SCOPE-COPY]
//      publishedPostingCount는 authorized scope의 합이다. 공고를 볼 수 있는
//      사업장이 하나도 없으면 그 값은 언제나 0이고, Home은 그 0을
//      "현재 등록된 공고가 없어요"라고 말했다 — 권한 부재를 사업 상태로
//      번역한 것이다. scope 판정을 emptiness 판정보다 앞에 둔다.
//
// readiness의 서버 의미(available = 조회 성공 여부)는 이번에 건드리지 않았고,
// 그 계약은 admin_home_staffing_rollout_contract_test / admin_home_empty_scope_test
// 가 계속 지킨다. 여기서는 클라이언트가 그 값을 권한 판정으로 재해석하지
// 않는다는 것만 추가로 고정한다.
//
// 테스트 가능 범위:
//   UserProvider는 필드 초기화에서 Firebase를 잡아 테스트에서 생성되지 않는다
//   (permission_provider_seam_probe_test 실측). 따라서 전이 자체가 아니라
//   "무엇을 구독하는가 / 어떤 상태를 구분하는가"를 소스에서 고정한다.
//   실기기 전이 확인은 R7 PRODUCT PENDING이다.

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

const _home = 'lib/screens/business_admin/business_admin_home_screen.dart';
const _jobs = 'lib/screens/business_admin/jobs_root_screen.dart';
const _payroll = 'lib/screens/business_admin/payroll/payroll_overview_screen.dart';
const _contract = 'lib/screens/business_admin/admin_contract_management_screen.dart';
const _queue = 'lib/screens/business_admin/unclosed_action_queue_screen.dart';
const _workforce =
    'lib/screens/business_admin/workforce_management/workforce_operational_view.dart';

void main() {
  // ── PART A. 탭 화면이 권한을 구독한다 ──────────────────────────────

  group('공고 탭 — CTA가 현재 권한을 본다', () {
    final s = _load(_jobs);

    test('read가 아니라 select다', () {
      expect(
          s.contains('if (context.select<UserProvider, bool>( '
              '(p) => !p.isSubAdmin || p.can((x) => x.canManageTo)))'),
          true);
    });

    test('진입 시점 스냅샷으로 CTA를 그리지 않는다', () {
      expect(
          s.contains('final canCreate = context.read<UserProvider>()'), false,
          reason: '한 번 읽고 끝내면 회수가 화면에 닿지 않는다');
    });
  });

  group('급여 개요 — 회수와 부여를 같은 판정으로 본다', () {
    final s = _load(_payroll);

    test('listener가 양방향이다', () {
      expect(s.contains('final allowed = _userProvider.can((p) => p.canManageWage);'),
          true);
      expect(s.contains('if (!allowed) { if (_accessDenied) return;'), true,
          reason: '회수 방향');
      expect(s.contains('if (!_accessDenied) return; setState(() { '
          '_accessDenied = false;'), true, reason: '부여 방향');
    });

    test('거부는 빈 목록이 아니라 거부 상태다', () {
      expect(s.contains("title: '접근 권한이 없습니다',"), true);
      expect(s.contains("subtitle: '급여 관리 권한이 있는 관리자에게 문의하세요.',"), true);
    });
  });

  group('계약 관리 — 대상 사업장 기준으로 머무는 동안에도 본다', () {
    final s = _load(_contract);

    test('진입 guard는 그대로 대상 사업장 기준이다', () {
      expect(s.contains('final allowed = await _canAccessTargetBusiness();'), true);
      expect(s.contains('return perms?.canManageContract == true;'), true);
    });

    test('진입 후 변화를 listener로 받는다', () {
      expect(s.contains('up.addListener(_onPermissionChanged);'), true);
      expect(s.contains('_userProvider?.removeListener(_onPermissionChanged);'),
          true, reason: 'dispose에서 해제하지 않으면 죽은 화면이 setState를 부른다');
    });

    test('선택 사업장이 아니라 이 화면의 사업장을 본다', () {
      expect(
          s.contains(
              'final perms = up.permissionsForBusiness(widget.businessId);'),
          true);
    });

    test('UNKNOWN을 거부로 바꾸지 않는다', () {
      expect(s.contains('if (perms == null) return;'), true,
          reason: '권한을 모르는 상태는 거부가 아니다');
    });

    test('회수·부여 양방향이다', () {
      expect(s.contains('if (allowed != _accessRevoked) return;'), true);
      expect(s.contains('if (allowed) unawaited(_refresh());'), true);
    });

    test('거부를 "계약 없음"으로 말하지 않는다', () {
      expect(s.contains('body: _accessRevoked ? const AppEmptyState( '
          'icon: Icons.lock_outline, '
          "title: '접근 권한이 없습니다', "
          "subtitle: '계약 관리 권한이 있는 관리자에게 문의하세요.', )"), true);
    });

    test('거부 상태에서 재조회 버튼이 살아 있지 않다', () {
      expect(s.contains('onPressed: _accessRevoked ? null : _refresh,'), true);
    });
  });

  group('미마감 큐 — entry guard와 같은 predicate로 계속 본다', () {
    final s = _load(_queue);

    test('entry guard와 listener가 같은 권한을 쓴다', () {
      expect(s.contains('if (!up.can((p) => p.canManageWage)) { '
          'Navigator.of(context).pop();'), true);
      expect(s.contains('final allowed = up.can((p) => p.canManageWage);'), true,
          reason: '두 자리가 다른 규칙을 쓰면 다시 어긋난다');
    });

    test('하이드레이션 전(UNKNOWN)을 거부로 읽지 않는다', () {
      expect(
          s.contains('if (up.currentUser?.isSubAdmin == true && '
              '!up.permissionsLoaded) return;'),
          true);
    });

    test('회수·부여 양방향이다', () {
      expect(s.contains('if (allowed != _accessRevoked) return;'), true);
      expect(s.contains('if (allowed) _load();'), true);
    });

    test('거부를 "마감 필요 0건"으로 말하지 않는다', () {
      expect(s.contains('body: _accessRevoked ? const AppEmptyState( '
          'icon: Icons.lock_outline, '
          "title: '접근 권한이 없습니다',"), true);
      expect(s.contains('onPressed: (isLoading || _accessRevoked) ? null : _load,'),
          true);
    });

    test('listener를 dispose에서 해제한다', () {
      expect(s.contains('_userProvider?.removeListener(_onPermissionChanged);'),
          true);
    });
  });

  group('운영 뷰 — 누를 수 없는 버튼을 남기지 않는다', () {
    final s = _load(_workforce);

    test('고정 근로자 CTA가 권한을 구독한다', () {
      expect(
          s.contains('if (context.select<UserProvider, bool>( '
              '(p) => p.can((x) => x.canManageWorkers))) _buildIconButton( '
              'icon: Icons.settings_outlined,'),
          true);
    });

    test('action-time guard는 이유를 말한다', () {
      expect(s.contains("ToastHelper.showWarning('근로자 관리 권한이 없습니다');"), true,
          reason: '아무 일도 일어나지 않는 탭은 고장과 구분되지 않는다');
      expect(s.contains('if (!up.can((p) => p.canManageWorkers)) return;'), false,
          reason: '조용한 return은 남겨두지 않는다');
    });

    test('server guard를 UI 숨김으로 대신하지 않는다', () {
      final cf = _src('functions/src/index.ts');
      expect(cf.contains('scrDPerms?.canManageWorkers !== true'), true,
          reason: '같은 권한을 서버도 요구해야 한다');
    });
  });

  // ── PART C. zero-scope Hero ────────────────────────────────────────

  group('Home Hero — scope 판정이 emptiness보다 먼저다', () {
    final s = _load(_home);

    test('scope 상태가 별도 상태로 존재한다', () {
      expect(s.contains('noPostingScope,'), true);
    });

    test('publishedPostingCount == 0 보다 앞에서 판정한다', () {
      final scopeAt = s.indexOf('return _HeroState.noPostingScope;');
      final emptyAt = s.indexOf('sr.publishedPostingCount == 0');
      expect(scopeAt, greaterThan(-1));
      expect(emptyAt, greaterThan(-1));
      expect(scopeAt < emptyAt, true,
          reason: '뒤에 오면 이미 "공고 없음"이라고 말한 뒤다');
    });

    test('기존 permission architecture를 그대로 쓴다', () {
      expect(
          s.contains(
              "if (!up.canForAnyBusiness((p) => p.canManageTo, whenUnknown: true)) "
              "{ return _HeroState.noPostingScope; }"),
          true,
          reason: '새 데이터 source를 만들지 않는다');
    });

    test('하이드레이션 전에는 아무 주장도 하지 않는다', () {
      expect(
          s.contains('if (!up.subAdminPermissionsLoaded) return _HeroState.loading;'),
          true,
          reason: 'UNKNOWN ≠ EMPTY, UNKNOWN ≠ NO_PERMISSION');
    });

    test('BUSINESS_ADMIN은 이 분기를 타지 않는다', () {
      final i = s.indexOf('if (!up.subAdminPermissionsLoaded)');
      expect(s.substring(0, i).endsWith('if (isSub) { '), true,
          reason: '소유자는 noPosting 그대로여야 한다');
    });

    test('copy가 공고 없음을 단정하지 않는다', () {
      expect(s.contains("message: '공고 정보를 볼 수 있는 권한이 없어요',"), true);
      expect(
          s.contains("supporting: '공고를 관리할 수 있는 사업장이 배정되어 있지 않습니다.\\n' "
              "'필요하면 사업장 관리자에게 권한을 요청하세요.');"),
          true);
    });

    test('CTA를 주지 않는다', () {
      final i = s.indexOf('case _HeroState.noPostingScope:');
      final body = s.substring(i, s.indexOf('case _HeroState.draftOnly:', i));
      expect(body.contains('ctaLabel'), false);
      expect(body.contains('onCta'), false);
    });

    test('Selector가 scope 판정 값도 구독한다', () {
      expect(s.contains('subAdminPermissionsLoaded: p.subAdminPermissionsLoaded,'),
          true);
      expect(
          s.contains('canManageToAnywhere: '
              'p.canForAnyBusiness((x) => x.canManageTo, whenUnknown: true),'),
          true,
          reason: '판정에 쓰는 값이 구독 밖이면 변화가 화면에 닿지 않는다');
    });
  });

  // ── PART D. readiness 의미는 그대로다 ──────────────────────────────

  group('readiness available 의미를 다시 바꾸지 않았다', () {
    test('서버의 두 early return은 여전히 available: true다', () {
      final cf = _codeOf(_src('functions/src/index.ts'));
      expect(
        'return {available: true, partial: false, failedBusinessCount: 0, days: []};'
            .allMatches(cf)
            .length,
        2,
        reason: '사업장 0개 / 권한 사업장 0개 — 둘 다 조회 실패가 아니다',
      );
    });

    test('클라이언트는 available을 권한 판정으로 쓰지 않는다', () {
      final s = _load(_home);
      final i = s.indexOf('return _HeroState.noPostingScope;');
      final head = s.lastIndexOf('if (isSub) {', i);
      final branch = s.substring(head, i);
      expect(branch.contains('available'), false,
          reason: 'zero-scope는 permission으로 판정한다 — fetch 성공 여부가 아니다');
    });

    test('ERROR 판정은 여전히 available/partial이 한다', () {
      final s = _load(_home);
      expect(s.contains('if (sr == null || !sr.hasUsableData) return _HeroState.error;'),
          true);
      expect(s.contains('if (sr.partial) return _HeroState.partialInfo;'), true);
    });
  });

  // ── PART E. canForBusiness 사용처 ──────────────────────────────────

  group('canForBusiness는 여전히 admin surface 전용이다', () {
    test('applicant(mode) 화면에서 쓰이지 않는다', () {
      final dir = Directory('lib');
      final users = <String>[];
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        if (f.path.replaceAll('\\', '/').endsWith('providers/user_provider.dart')) {
          continue;
        }
        final code = _codeOf(f.readAsStringSync());
        if (code.contains('canForBusiness(')) {
          users.add(f.path.replaceAll('\\', '/'));
        }
      }
      expect(users, isNotEmpty);
      for (final p in users) {
        expect(
            p.contains('/business_admin/') || p.contains('/widgets/admin/'),
            true,
            reason: '$p — applicant 경로에서 쓰이면 mode asymmetry가 실제 bypass가 된다');
      }
    });

    test('BUSINESS_ADMIN early-return이 유지된다', () {
      final up = _load('lib/providers/user_provider.dart');
      expect(up.contains('if (user.isBusinessAdmin || user.isSuperAdmin) return true;'),
          true);
    });
  });
}
