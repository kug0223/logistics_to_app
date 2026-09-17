// [CROSS-DOMAIN-R5.1F.2] 대상 사업장 권한 / 확정 권한 canonical
//
// 두 가지를 닫는다.
//
//   1. [CORRECTION-MULTI-BIZ-TARGET-PERMISSION-NOT-LIVE]
//      UserProvider의 realtime member listener는 **선택 사업장 하나**뿐이라,
//      selected=A인 채로 target=B 화면을 보고 있으면 B의 권한 회수가 화면에
//      닿지 않았다. 서버는 막지만 클라이언트에는 stale 권한이 남는다.
//      해결은 모든 사업장 상시 구독도, 폴링도 아니다 — **열려 있는 화면의
//      사업장 하나만** 보고, 닫히면 끊는다(refcount). 여러 사업장을 한 화면에
//      모으는 큐는 목록을 다시 읽는 같은 길목에서 권한도 다시 읽는다.
//
//      같은 화면에서 발견한 두 번째 문제: 고정근무 관리 다이얼로그는
//      `_selectedBusinessId`(대상 B)의 일을 하면서 action guard는 `can()`
//      (선택 A) 기준이었다. A의 권한으로 B의 action이 열린다.
//
//   2. [VERIFY-APPLICATION-CONFIRM-PERMISSION-MATRIX]
//      확정/좌석 커밋의 canonical capability는 `canManageTo`다.
//      DEV 실측(P0~P4 + 타사업장 + businessId 누락 + 소유자) PASS 8/FAIL 0.
//      지원 검토 큐만 client gate가 아예 없어 권한 없는 사업장의 CTA가
//      남아 있었다 — 서버 403으로만 끝나는 형태. 행의 사업장 기준으로 막는다.

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

const _provider = 'lib/providers/user_provider.dart';
const _contract = 'lib/screens/business_admin/admin_contract_management_screen.dart';
const _dayDlg = 'lib/screens/business_admin/dialogs/day_applicants_dialog.dart';
const _workDlg = 'lib/screens/business_admin/dialogs/work_applicants_dialog.dart';
const _fixedDlg = 'lib/screens/business_admin/dialogs/fixed_worker_management_dialog.dart';
const _queue = 'lib/screens/business_admin/support_review_queue_screen.dart';
const _cf = 'functions/src/index.ts';

void main() {
  // ── PART A. 대상 사업장 live permission ────────────────────────────

  group('대상 사업장 구독은 화면이 열려 있는 동안만이다', () {
    final up = _load(_provider);

    test('열린 화면 단위 구독 API가 있다', () {
      expect(up.contains('VoidCallback watchBusinessPermissions(String businessId) {'),
          true);
    });

    test('같은 사업장을 여러 surface가 봐도 구독은 하나다', () {
      // [CROSS-DOMAIN-R5.1F.4] 살아 있으면 그대로 쓰고, 에러로 죽은 자리면
      //   다시 붙인다. 어느 쪽이든 사업장당 구독은 하나다.
      expect(
          up.contains('sub: existing.sub ?? '
              '_attachTargetPermsListener(businessId, user.uid), '
              'count: existing.count + 1,'),
          true,
          reason: 'refcount가 없으면 다이얼로그를 겹쳐 열 때마다 listener가 늘어난다');
      expect(up.contains('if (cur.count <= 1) { cur.sub?.cancel(); '
          '_targetPermsSubs.remove(businessId);'), true,
          reason: '마지막 surface가 닫히면 끊어야 상시 구독이 아니다');
      expect(up.contains('_targetPermsSubs[businessId] = '
          '(sub: cur.sub, count: cur.count - 1);'), true,
          reason: '남아 있는 surface가 있으면 유지한다');
    });

    test('SUB_ADMIN이 아니면 구독하지 않는다', () {
      expect(
          up.contains('if (businessId.isEmpty || user == null || !user.isSubAdmin) '
              '{ return () {}; }'),
          true,
          reason: '소유자·SUPER_ADMIN은 권한 map으로 판정하지 않는다 — read를 만들 이유가 없다');
    });

    test('폴링이 아니라 snapshot이다', () {
      // [CROSS-DOMAIN-R5.1F.4] 구독 생성이 _attachTargetPermsListener로 빠졌다
      //   (재부착이 같은 자리를 쓰기 위해서다). 보는 성질은 그대로다.
      final i = up.indexOf('_attachTargetPermsListener(String businessId, String uid) {');
      expect(i, greaterThan(-1));
      final body = up.substring(i, i + 2400);
      expect(body.contains(".collection('members') .doc(uid) .snapshots() .listen"), true);
      expect(body.contains('Timer'), false, reason: '주기적 재조회를 넣지 않는다');
    });

    test('membership이 사라지면 fail-closed다', () {
      final i = up.indexOf('_attachTargetPermsListener(String businessId, String uid) {');
      final body = up.substring(i, i + 2400);
      expect(body.contains('data == null ? null : MemberPermissions.fromMap('), true,
          reason: '문서가 없으면 map에서 지운다 — canForBusiness가 false를 돌려준다');
    });

    test('대상 사업장 구독이 선택 사업장 복구 로직을 타지 않는다', () {
      final i = up.indexOf('_attachTargetPermsListener(String businessId, String uid) {');
      final body = up.substring(i, i + 2400);
      expect(body.contains('_recoverFromSelectedMembershipLoss'), false,
          reason: 'B의 membership 상실이 A의 선택 context를 흔들면 안 된다');
      expect(body.contains('_switchGeneration++'), false);
    });

    test('provider dispose에서 전부 끊는다', () {
      expect(up.contains('for (final e in _targetPermsSubs.values) { e.sub?.cancel(); } '
          '_targetPermsSubs.clear();'), true);
    });
  });

  group('대상 사업장 화면들이 그 사업장을 구독한다', () {
    test('계약 관리 — widget.businessId', () {
      final s = _load(_contract);
      expect(
          s.contains('_releasePermsWatch = up.watchBusinessPermissions(widget.businessId);'),
          true);
      expect(s.contains('_releasePermsWatch?.call();'), true, reason: 'dispose 해제');
    });

    test('업무별 지원자 — toItem.to.businessId', () {
      final s = _load(_workDlg);
      expect(
          s.contains('_releasePermsWatch = context .read<UserProvider>() '
              '.watchBusinessPermissions(widget.toItem.to.businessId);'),
          true);
      expect(s.contains('void dispose() { _releasePermsWatch?.call(); super.dispose(); }'),
          true);
    });

    test('날짜별 지원자 — 선택기로 바뀌면 구독도 옮긴다', () {
      final s = _load(_dayDlg);
      expect(s.contains('void _watchPermsFor(String? bizId) { '
          'if (_watchedBizId == bizId) return; _releasePermsWatch?.call();'), true);
      expect(s.contains('_watchPermsFor(bizId);'), true,
          reason: '사업장이 정해지는 길목(_load)에서 맞춘다');
    });

    test('고정근무 관리 — 선택기로 바뀌면 구독도 옮긴다', () {
      final s = _load(_fixedDlg);
      expect(s.contains('_watchPermsFor(businessId);'), true);
      expect(s.contains('void dispose() { _releasePermsWatch?.call();'), true);
    });
  });

  group('selected 권한을 target 화면에 재사용하지 않는다', () {
    final s = _load(_fixedDlg);

    test('이 다이얼로그는 보고 있는 사업장 기준으로 판정한다', () {
      expect(
          s.contains('bool _canForThisBiz(bool Function(MemberPermissions p) check) { '
              'final bizId = _selectedBusinessId; if (bizId == null) return false; '
              'return context.read<UserProvider>().canForBusiness(bizId, check); }'),
          true);
    });

    test('action guard에 선택-사업장 can()이 남아 있지 않다', () {
      expect(s.contains('context.read<UserProvider>().can((p) => p.canManageWorkers)'),
          false, reason: 'A의 권한으로 B의 action이 열린다');
      expect(s.contains('context.read<UserProvider>().can((p) => p.canManageContract)'),
          false);
    });

    test('모든 action guard가 같은 helper를 쓴다', () {
      expect('_canForThisBiz('.allMatches(s).length, greaterThanOrEqualTo(8),
          reason: '한 자리만 고치면 다시 갈라진다');
    });
  });

  // ── PART B. 확정 권한 canonical ────────────────────────────────────

  group('확정은 어디서 눌러도 canManageTo다', () {
    test('업무별 지원자 — 단건·일괄 모두 canManageTo', () {
      final s = _load(_workDlg);
      expect(s.contains('bool _canManageTo() => _permissionFor((p) => p.canManageTo);'),
          true);
      expect(s.contains('if (!_canManageTo()) {'), true);
      expect(
          s.contains('return up.canForBusiness(widget.toItem.to.businessId, check);'),
          true,
          reason: '알림·deep-link 진입은 selected와 다른 사업장이다');
    });

    test('날짜별 지원자 — 대상 사업장 기준 canManageTo', () {
      final s = _load(_dayDlg);
      expect(s.contains('final canManageTo = _canForSelectedBiz((p) => p.canManageTo);'),
          true);
      expect(s.contains('return up.canForBusiness(bizId, check);'), true);
    });

    test('Home 지원 검토 Task — canManageTo', () {
      final s = _load('lib/screens/business_admin/business_admin_home_screen.dart');
      // [CROSS-DOMAIN-R5.1F.5] 같은 capability를 더 좁게 본다 —
      //   확인된 허용에서만 Task가 열린다.
      expect(s.contains('if (_verified(up, (p) => p.canManageTo)) { '
          'final approval = cs?.actions.approval;'), true);
      expect(s.contains('chk(permitted: canTo, available: a.approval.available);'), true);
    });

    test('지원 검토 큐 — 행의 사업장 기준 canManageTo', () {
      final s = _load(_queue);
      // [CROSS-DOMAIN-R5.1F.3] bool → 4상태로 올라갔다. 판정 대상(행의 사업장,
      //   canManageTo)은 그대로이고, 거부와 확인불가를 더 구분한다.
      expect(
          s.contains('PermissionCheck _actCheck(ApplicationModel app) => '
              'context.read<UserProvider>().checkForBusiness( app.businessId, '
              '(p) => p.canManageTo, );'),
          true);
      expect(
          s.contains('bool _canActOn(ApplicationModel app) => '
              '_actCheck(app) == PermissionCheck.allowed;'),
          true,
          reason: '검증된 허용에서만 action이 열린다');
      expect(s.contains("? '이 사업장의 공고 관리 권한이 없습니다.'"), true,
          reason: '승인·거절 양쪽 모두');
      expect("if (!_canActOn(app)) {".allMatches(s).length, greaterThanOrEqualTo(2));
    });

    test('지원 검토 큐 — 누를 수 없는 CTA를 남기지 않는다', () {
      final s = _load(_queue);
      expect(s.contains('if (!_canActOn(app)) Text( '
          "_actCheck(app) == PermissionCheck.denied ? '권한 없음' : '권한 확인 불가',"), true);
      expect(s.contains('context.watch<UserProvider>();'), true,
          reason: '권한이 바뀌면 다시 그려야 한다');
    });

    test('지원 검토 큐 — 목록과 권한을 같은 주기로 다시 읽는다', () {
      final s = _load(_queue);
      expect(
          s.contains('final up = context.read<UserProvider>();') &&
              s.contains('unawaited(up.refreshSubAdminAccessState());'),
          true,
          reason: '사업장마다 listener를 달지 않는 대신 결정적 refresh를 쓴다');
    });

    test('client gate 제거를 서버 403으로 대신하던 자리가 사라졌다', () {
      final raw = _src(_queue);
      expect(raw.contains('[APPROVE-AUTH-01 C2] 클라이언트 selected-A canManageTo 게이트 제거.'),
          false,
          reason: '답은 게이트 없음이 아니라 target-business 게이트다');
    });
  });

  group('서버도 같은 capability를 요구한다', () {
    final cf = _codeOf(_src(_cf));

    test('callableConfirmApplication — canManageTo', () {
      expect(
          _flat(cf).contains("if (prePerms?.canManageTo !== true) { "
              'throw new HttpsError( "permission-denied", "TO 관리 권한이 없습니다."); }'),
          true);
    });

    test('businessId는 여전히 필수다 (R5.1D)', () {
      expect(
          _flat(cf).contains('if (typeof claimedBusinessId !== "string" || '
              'claimedBusinessId.length === 0) { throw new HttpsError('
              '"invalid-argument", "businessId가 필요합니다."); }'),
          true);
    });

    test('승인·거절도 canManageTo다', () {
      expect(cf.contains('if (!rejectPerms.canManageTo) throw new HttpsError('
          '"permission-denied", "TO 관리 권한이 없습니다.");'), true);
    });

    test('근태 일괄 확정은 확정이 아니라 근로자 도메인이다', () {
      // 이름이 비슷해 matrix에서 섞였던 자리 — 서로 다른 capability임을 못박는다.
      final i = cf.indexOf('export const callableBatchAdminConfirm = onCall(');
      expect(i, greaterThan(-1));
      final body = cf.substring(i, i + 2000);
      expect(body.contains('canManageWorkers'), true);
      expect(body.contains('canManageTo'), false,
          reason: 'adminConfirmed 플래그는 근태(canManageWorkers)다');
    });
  });
}
