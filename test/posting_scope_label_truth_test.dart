// [POSTING-V2-02F.1] 관리자 탭 scope label이 실제 접근 범위를 말한다
//
// 02F READ에서 확인된 문제:
//   query scope / filter scope / CreateTO picker scope는 모두 정확한데
//   상단 chip만 다른 것을 말하고 있었다.
//
//   BUSINESS_ADMIN : 로드된 공고의 사업장 이름 집합 크기로 범위를 판정
//                    → A/B/C 관리 중 공고가 A에만 있으면 'A 사업장'
//                    → B에 공고가 생기면 '전체 사업장'으로 바뀜
//                       (권한이 아니라 데이터 분포가 문구를 흔든다)
//   SUB_ADMIN      : effectiveBusinessId 한 곳만 표시
//                    → A/B 배정인데 'A 사업장', 목록에는 B 공고도 섞여 있다
//                    → Home에서 사업장을 바꾸면 같은 목록의 이름표만 갈린다
//
// 계약: Scope ≠ Filter, Scope ≠ effectiveBusinessId, Scope ≠ 데이터 분포.
//
// 판정은 순수 resolver를 직접 호출해 검증하고(화면은 Firebase 서비스를 필드로
// 즉시 보유해 widget 테스트가 불가능하다), 두 Root의 배선은 소스로 고정한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/utils/admin_business_scope_label.dart';

const _jobsPath = 'lib/screens/business_admin/jobs_root_screen.dart';
const _wfPath =
    'lib/screens/business_admin/workforce_management/workforce_root_screen.dart';
const _ctrlPath = 'lib/controllers/workforce_controller.dart';
const _labelPath = 'lib/utils/admin_business_scope_label.dart';
const _createToPath =
    'lib/screens/business_admin/to_management/create_to_screen.dart';

String _src(String p) {
  final f = File(p);
  expect(f.existsSync(), true, reason: '$p 를 찾지 못함');
  return f.readAsStringSync();
}

/// `//` 주석 줄 제거 — 설명 주석이 코드로 오탐되는 것을 막는다.
String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

/// 공백 1칸 평탄화 — 들여쓰기/줄바꿈에 의존하지 않는 비교용.
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

String _label({
  bool isSuperAdmin = false,
  bool isSubAdmin = false,
  List<String> managed = const [],
  List<String> assigned = const [],
  Map<String, String> subAdminNames = const {},
  List<String> loadedNames = const [],
}) =>
    resolveAdminBusinessScopeLabel(
      isSuperAdmin: isSuperAdmin,
      isSubAdmin: isSubAdmin,
      managedBusinessIds: managed,
      subAdminBusinessIds: assigned,
      subAdminBusinessNames: subAdminNames,
      loadedBusinessNames: loadedNames,
    );

void main() {
  // ── [02F.1-SUPERADMIN] §12, §13 SUPER_ADMIN ─────────────────────
  //
  // reachability: SUPER_ADMIN은 BusinessAdminShell에 진입할 수 없지만
  // (main.dart의 role switch가 AdminHomeScreen으로 보낸다),
  // NotificationScreen에서 JobsRootScreen을 **직접 push**하는 경로가 있다.
  // 그 화면의 load()는 isSuperAdmin → businessIds = null로 전체를 조회한다.
  group('SCOPE-00 SUPER_ADMIN', () {
    test('00-a businessIds가 비어도 전체 사업장', () {
      expect(_label(isSuperAdmin: true), '전체 사업장');
    });

    test('00-b ids 길이에 의존하지 않는다 (§13)', () {
      for (final managed in [<String>[], ['A'], ['A', 'B']]) {
        expect(_label(isSuperAdmin: true, managed: managed), '전체 사업장',
            reason: 'SUPER_ADMIN 범위가 businessIds 길이에 좌우된다');
      }
    });

    test('00-c 일반 관리자의 빈 범위와 구분된다 (§11)', () {
      expect(_label(isSuperAdmin: true), '전체 사업장');
      expect(_label(), '', reason: '진짜 빈 범위는 chip을 숨긴다');
      expect(_label(isSubAdmin: true), '');
    });

    test('00-d 역할 판정이 SUPER_ADMIN → SUB_ADMIN → BUSINESS_ADMIN 순이다 (§8)', () {
      final body = _codeOf(_bodyOf(
          _src(_labelPath), 'String resolveAdminBusinessScopeLabel('));
      final superIdx = body.indexOf("if (isSuperAdmin) return '전체 사업장';");
      final idsIdx = body.indexOf('final ids = isSubAdmin ?');
      expect(superIdx, greaterThan(-1), reason: 'SUPER_ADMIN 분기가 없다');
      expect(idsIdx, greaterThan(superIdx),
          reason: 'SUPER_ADMIN 판정이 ids 분기보다 앞서야 한다');
    });

    test('00-e 별도 카피 체계를 만들지 않았다 (§5)', () {
      final code = _codeOf(_src(_labelPath));
      for (final forbidden in ['플랫폼', '모든 사업장', '슈퍼관리자']) {
        expect(code.contains(forbidden), false);
      }
    });

    test('00-f 두 caller 모두 isSuperAdmin을 전달한다 (§9)', () {
      for (final p in [_jobsPath, _wfPath]) {
        final body =
            _flat(_codeOf(_bodyOf(_src(p), 'String _computeScopeLabel(')));
        expect(body.contains('isSuperAdmin: user?.isSuperAdmin ?? false,'), true,
            reason: '$p 가 SUPER_ADMIN을 전달하지 않는다');
      }
    });

    test('00-g reachability 근거 — Shell 진입은 막혀 있다', () {
      final main = _codeOf(_src('lib/main.dart'));
      // role switch: SUPER_ADMIN → AdminHomeScreen, Shell 아님
      expect(
          _flat(main).contains(
              'case UserRole.SUPER_ADMIN: debugPrint(\'🎯 SUPER_ADMIN → AdminHomeScreen으로 이동\'); '
              'return const AdminHomeScreen();'),
          true);
      // SubAdmin 경로도 role == USER 안에서만 성립한다
      final model = _codeOf(_src('lib/models/core/user_model.dart'));
      expect(
          model.contains(
              'bool get isSubAdmin => role == UserRole.USER && subAdminBusinessIds.isNotEmpty;'),
          true);
    });

    test('00-h reachability 근거 — 알림에서 JobsRootScreen을 직접 push한다', () {
      final notif = _codeOf(_src('lib/screens/common/notification_screen.dart'));
      expect(
          _flat(notif).contains(
              'MaterialPageRoute(builder: (_) => const JobsRootScreen()),'),
          true,
          reason: 'SUPER_ADMIN이 도달하는 경로가 사라졌다면 이 테스트를 재작성해야 한다');
      // 그 경로의 guard는 SUPER_ADMIN을 막지 않는다
      expect(
          notif.contains(
              'final isUser = userProvider.isUser && !userProvider.isSubAdmin;'),
          true);
      expect(
          notif.contains('if (!up.isSubAdmin) return _AdminAccessResult.allowed;'),
          true);
      // SUPER_ADMIN은 알림 화면 자체에 접근한다
      final superHome =
          _codeOf(_src('lib/screens/super_admin/super_admin_home_screen.dart'));
      expect(superHome.contains('const NotificationScreen()'), true);
    });

    test('00-i SUPER_ADMIN query scope는 그대로 전체다 (§10)', () {
      final body = _flat(_codeOf(_bodyOf(_src(_ctrlPath), 'Future<void> load(')));
      expect(body.contains('if (user.isSuperAdmin) { businessIds = null;'), true,
          reason: 'display 수정이 query scope를 건드렸다');
    });
  });

  // ── §20, §2 BUSINESS_ADMIN 단일 ─────────────────────────────────
  group('SCOPE-01 BUSINESS_ADMIN 단일 사업장', () {
    test('01-a 사업장 이름을 그대로 쓴다', () {
      expect(
          _label(managed: ['A'], loadedNames: ['평택센터']),
          '평택센터');
    });

    test('01-b 공고 0건이면 이름 대신 안전 fallback (§14)', () {
      expect(_label(managed: ['A']), '내 사업장');
    });

    test('01-c businessId 원문을 노출하지 않는다', () {
      expect(_label(managed: ['biz_abc123']).contains('biz_abc123'), false);
    });
  });

  // ── §21, §22, §3 BUSINESS_ADMIN 다사업장 ────────────────────────
  group('SCOPE-02 BUSINESS_ADMIN 다사업장 — 데이터 분포와 무관', () {
    test('02-a 공고가 A에만 있어도 전체 사업장', () {
      expect(
          _label(managed: ['A', 'B', 'C'], loadedNames: ['평택센터']),
          '전체 사업장',
          reason: '로드된 공고 분포로 범위를 축소하면 안 된다');
    });

    test('02-b 공고 0건이어도 전체 사업장', () {
      expect(_label(managed: ['A', 'B']), '전체 사업장');
    });

    test('02-c 여러 사업장에 공고가 있어도 같은 문구', () {
      expect(
          _label(managed: ['A', 'B'], loadedNames: ['평택센터', '안성센터']),
          '전체 사업장');
    });

    test('02-d 데이터가 늘어도 문구가 흔들리지 않는다', () {
      const managed = ['A', 'B', 'C'];
      final before = _label(managed: managed, loadedNames: ['평택센터']);
      final after =
          _label(managed: managed, loadedNames: ['평택센터', '안성센터', '천안센터']);
      expect(before, after,
          reason: '권한이 아니라 데이터 분포가 문구를 바꾸던 것이 02F의 결함이다');
    });
  });

  // ── §23, §4 SUB_ADMIN 단일 ──────────────────────────────────────
  group('SCOPE-03 SUB_ADMIN 단일 배정', () {
    test('03-a 배정 사업장 이름을 쓴다', () {
      expect(
          _label(
            isSubAdmin: true,
            assigned: ['A'],
            subAdminNames: {'A': '평택센터'},
          ),
          '평택센터');
    });

    test('03-b 이름 미확보 시 안전 fallback', () {
      expect(_label(isSubAdmin: true, assigned: ['A']), '내 사업장');
    });

    test('03-c 빈 문자열 이름도 fallback으로 떨어진다', () {
      expect(
          _label(
            isSubAdmin: true,
            assigned: ['A'],
            subAdminNames: {'A': ''},
          ),
          '내 사업장');
    });
  });

  // ── §24, §5 SUB_ADMIN 다중 ──────────────────────────────────────
  group('SCOPE-04 SUB_ADMIN 다중 배정', () {
    test('04-a 배정 개수를 말한다', () {
      expect(
          _label(
            isSubAdmin: true,
            assigned: ['A', 'B'],
            subAdminNames: {'A': '평택센터', 'B': '안성센터'},
          ),
          '담당 사업장 2곳');
    });

    test('04-b 3곳이면 3곳', () {
      expect(
          _label(isSubAdmin: true, assigned: ['A', 'B', 'C']),
          '담당 사업장 3곳');
    });

    test('04-c 한 사업장 이름으로 축소하지 않는다', () {
      final label = _label(
        isSubAdmin: true,
        assigned: ['A', 'B'],
        subAdminNames: {'A': '평택센터', 'B': '안성센터'},
      );
      expect(label.contains('평택센터'), false);
      expect(label.contains('안성센터'), false);
    });

    test('04-d SubAdmin에게 전체 사업장은 쓰지 않는다 (§5, §31)', () {
      // 배정 범위는 owner 사업장의 부분집합이라 '전체'로 읽히면 안 된다.
      for (final n in [2, 3, 5]) {
        final label = _label(
          isSubAdmin: true,
          assigned: List.generate(n, (i) => 'biz$i'),
        );
        expect(label, isNot('전체 사업장'));
      }
      final code = _codeOf(_src(_labelPath));
      expect(
          code.contains("isSubAdmin ? '담당 사업장 \${ids.length}곳' : '전체 사업장'"),
          true);
    });
  });

  // ── §25, §9 Home 사업장 전환 독립 ───────────────────────────────
  group('SCOPE-05 Home 사업장 전환이 chip을 바꾸지 않는다', () {
    test('05-a A 선택이든 B 선택이든 같은 문구', () {
      // effectiveBusinessId는 resolver의 입력이 아니다 — 넣을 자리가 없다.
      const assigned = ['A', 'B'];
      final withA = _label(
          isSubAdmin: true,
          assigned: assigned,
          subAdminNames: {'A': '평택센터', 'B': '안성센터'});
      final withB = _label(
          isSubAdmin: true,
          assigned: assigned,
          subAdminNames: {'B': '안성센터', 'A': '평택센터'});
      expect(withA, withB);
      expect(withA, '담당 사업장 2곳');
    });

    test('05-b §29 resolver·caller 어디에도 effectiveBusinessId가 없다', () {
      expect(_codeOf(_src(_labelPath)).contains('effectiveBusinessId'), false);
      for (final p in [_jobsPath, _wfPath]) {
        final body =
            _codeOf(_bodyOf(_src(p), 'String _computeScopeLabel('));
        expect(body.contains('effectiveBusinessId'), false,
            reason: '$p 의 scope label이 Home context를 말한다');
      }
    });

    test('05-c CreateTO·Home의 effectiveBusinessId 사용처는 그대로다', () {
      // unrelated 사용처를 건드리지 않았다.
      final jobs = _codeOf(_src(_jobsPath));
      expect(jobs.contains('up.isSubAdmin ? up.effectiveBusinessId : null'), true,
          reason: 'CreateTO 진입 계약이 사라졌다');
    });
  });

  // ── §30, §7 데이터 분포 비사용 ──────────────────────────────────
  group('SCOPE-06 공고 분포로 범위를 판정하지 않는다', () {
    test('06-a resolver가 범위를 ids로만 판정한다', () {
      final body = _codeOf(_bodyOf(_src(_labelPath),
          'String resolveAdminBusinessScopeLabel('));
      expect(
          body.contains(
              'final ids = isSubAdmin ? subAdminBusinessIds : managedBusinessIds;'),
          true);
      // 분기 판정(ids 결정 → 다중 분기)에 loadedBusinessNames가 쓰이지 않는다.
      // 파라미터 목록은 제외하고 본문의 판정 구간만 본다 —
      // loadedBusinessNames는 단일 사업장의 이름 source일 뿐이다.
      final branchRegion = body.substring(
          body.indexOf('final ids ='), body.indexOf('if (isSubAdmin) {'));
      expect(branchRegion.contains('loadedBusinessNames'), false,
          reason: '데이터 분포가 범위 판정에 개입한다');
    });

    test('06-b caller가 items/businessName으로 범위를 세지 않는다', () {
      for (final p in [_jobsPath, _wfPath]) {
        final body =
            _flat(_codeOf(_bodyOf(_src(p), 'String _computeScopeLabel(')));
        expect(body.contains('names.length == 1'), false, reason: p);
        expect(body.contains('.toSet()'), false, reason: p);
        expect(body.contains("return '전체 사업장';"), false,
            reason: '$p 가 범위 판정을 다시 복제했다');
      }
    });

    test('06-c 옛 분포 기반 판정이 코드베이스에 남아 있지 않다', () {
      for (final p in [_jobsPath, _wfPath]) {
        final code = _codeOf(_src(p));
        expect(code.contains('managedBusinessIds.length ?? 0'), false,
            reason: p);
      }
    });
  });

  // ── §28, §10, §12 shared resolver ───────────────────────────────
  group('SCOPE-07 공고 탭과 근무 탭이 같은 resolver를 쓴다', () {
    test('07-a 두 화면이 동일 함수를 호출한다', () {
      for (final p in [_jobsPath, _wfPath]) {
        final body =
            _codeOf(_bodyOf(_src(p), 'String _computeScopeLabel('));
        expect(body.contains('resolveAdminBusinessScopeLabel('), true,
            reason: '$p 가 공용 resolver를 쓰지 않는다');
      }
    });

    test('07-b 두 caller가 같은 인자를 넘긴다', () {
      final jobs =
          _flat(_codeOf(_bodyOf(_src(_jobsPath), 'String _computeScopeLabel(')));
      final wf =
          _flat(_codeOf(_bodyOf(_src(_wfPath), 'String _computeScopeLabel(')));
      for (final arg in [
        'isSubAdmin: up.isSubAdmin,',
        'managedBusinessIds: user?.managedBusinessIds ?? const [],',
        'subAdminBusinessIds: user?.subAdminBusinessIds ?? const [],',
        'subAdminBusinessNames: up.subAdminBusinessNames,',
      ]) {
        expect(jobs.contains(arg), true, reason: 'jobs: $arg');
        expect(wf.contains(arg), true, reason: 'workforce: $arg');
      }
    });

    test('07-c 같은 fixture면 두 화면이 같은 label을 낸다', () {
      // 두 caller가 동일 인자 집합을 넘기므로 resolver 출력이 곧 두 화면의 출력이다.
      const fixture = ['A', 'B'];
      expect(_label(isSubAdmin: true, assigned: fixture), '담당 사업장 2곳');
      expect(_label(managed: fixture), '전체 사업장');
    });

    test('07-d resolver 정의는 한 곳뿐이다 (§12)', () {
      var hits = 0;
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        if (_codeOf(f.readAsStringSync())
            .contains('String resolveAdminBusinessScopeLabel(')) {
          hits++;
        }
      }
      expect(hits, 1, reason: 'resolver가 복제돼 새 drift point가 생겼다');
    });
  });

  // ── §15 fail-safe ───────────────────────────────────────────────
  group('SCOPE-08 범위가 비면 chip을 숨긴다', () {
    test('08-a ids 0개 → 빈 문자열', () {
      expect(_label(), '');
      expect(_label(isSubAdmin: true), '');
    });

    test('08-b 새 error surface를 만들지 않았다', () {
      final code = _codeOf(_src(_labelPath));
      expect(code.contains('throw'), false);
      expect(code.contains('Exception'), false);
    });

    test('08-c 빈 label이면 화면이 chip을 그리지 않는다', () {
      // 두 화면의 guard 형태는 다르지만(기존 구조 유지) 효과는 같다.
      expect(
          _flat(_codeOf(_src(_jobsPath)))
              .contains('if (label.isEmpty) return const SizedBox.shrink();'),
          true);
      expect(
          _flat(_codeOf(_src(_wfPath)))
              .contains('if (scopeLabel.isNotEmpty) ...['),
          true);
    });
  });

  // ── §8, §26 filter 독립 ─────────────────────────────────────────
  group('SCOPE-09 filter가 scope label을 바꾸지 않는다', () {
    test('09-a resolver가 필터 상태를 입력으로 받지 않는다', () {
      final code = _codeOf(_src(_labelPath));
      for (final f in [
        'selectedBusinessId',
        'selectedDateRange',
        'selectedTOType',
        'selectedPublishStatus',
        'hasActiveFilters',
      ]) {
        expect(code.contains(f), false, reason: 'scope가 filter를 말하게 됐다');
      }
    });

    test('09-b caller도 필터를 넘기지 않는다', () {
      for (final p in [_jobsPath, _wfPath]) {
        final body =
            _codeOf(_bodyOf(_src(p), 'String _computeScopeLabel('));
        expect(body.contains('selected'), false, reason: p);
      }
    });

    test('09-c 필터 뱃지 계약은 그대로다', () {
      final jobs = _codeOf(_src(_jobsPath));
      expect(jobs.contains('hasFilters: controller.hasActiveFilters,'), true);
      expect(jobs.contains('filterCount: controller.activeFilterCount,'), true);
    });
  });

  // ── §17, §27 query scope 무변경 ─────────────────────────────────
  group('SCOPE-10 범위 밖 무변경', () {
    test('10-a load()의 query scope가 그대로다', () {
      final body = _flat(_codeOf(_bodyOf(_src(_ctrlPath), 'Future<void> load(')));
      expect(body.contains('businessIds = user.subAdminBusinessIds;'), true);
      expect(body.contains('businessIds = user.managedBusinessIds;'), true);
      expect(body.contains('if (user.isSuperAdmin) { businessIds = null;'), true);
    });

    test('10-b CreateTO picker scope 무변경 (§16)', () {
      final code = _flat(_codeOf(_src(_createToPath)));
      expect(
          code.contains(
              'final bizIds = userProvider.currentUser?.subAdminBusinessIds ?? [];'),
          true);
      expect(
          code.contains(
              'final managedIds = userProvider.currentUser?.managedBusinessIds ?? [];'),
          true);
    });

    test('10-c permission gating 무변경 (§18)', () {
      final shell =
          _codeOf(_src('lib/screens/business_admin/business_admin_shell.dart'));
      expect(shell.contains('if (up.can((p) => p.canManageTo)) 1,'), true);
      final card =
          _codeOf(_src('lib/widgets/admin/cards/admin_to_group_card.dart'));
      expect(card.contains('final canManageTo = up.can((p) => p.canManageTo);'),
          true);
    });

    test('10-d 근무 탭의 다른 동작을 건드리지 않았다 (§11)', () {
      final wf = _codeOf(_src(_wfPath));
      // query·permission·lifecycle 배선 그대로
      expect(wf.contains('_controller.load(context);'), true);
      expect(wf.contains('WorkforceController.dataRevision.addListener'), true);
      expect(wf.contains('child: WorkforceOperationalView(),'), true);
      expect(wf.contains('FCMService().addAdminRefreshListener'), true);
    });

    test('10-e resolver가 순수 계산이다 (§31)', () {
      final code = _codeOf(_src(_labelPath));
      for (final forbidden in [
        'await',
        'Firestore',
        'httpsCallable',
        'FirestoreService',
        'import',
      ]) {
        expect(code.contains(forbidden), false,
            reason: 'scope label에 $forbidden 이 들어감');
      }
    });

    test('10-f 서버 무변경 (§32)', () {
      final fns = _src('functions/src/index.ts');
      expect(fns.contains('export const callableGetAdminTOs'), true);
      expect(fns.contains('async function assertBizAdmin('), true);
    });
  });
}
