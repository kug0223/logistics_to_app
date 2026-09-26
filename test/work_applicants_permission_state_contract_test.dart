// [R7-P1-2.1] 인력 현황 다이얼로그 — 권한 없음은 고장이 아니다.
//
//   30d82dd 에서 ERROR != ZERO 는 닫혔다. 그런데 한 축이 더 있었다.
//
//     명단을 본 뒤 권한이 회수되면, 새로고침이 거부로 끝나도
//     `최신 정보를 불러오지 못했어요` 배너와 함께 **이름과 연락처가
//     그대로 남아 있었다.** 일반 실패를 위해 만든 stale-data 보존이
//     볼 자격을 잃은 사람에게도 그대로 적용된 것이다.
//
//   그래서 네 상태를 갈라 둔다.
//
//     SUCCESS_ZERO   확인했고 0명이다
//     ERROR          읽지 못했다 — 다시 시도
//     PARTIAL        읽지 못했지만 전에 받은 것은 아직 쓸 만하다
//     NO_PERMISSION  볼 자격이 없다 — 지우고, 다시 시도를 권하지 않는다
//
//   stale-data 보존은 **권한이 아직 유효할 때만** 적용된다.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync();

String _codeOf(String dart) => dart
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _slice(String src, String start, String end) {
  final i = src.indexOf(start);
  expect(i, greaterThan(-1), reason: '구간 시작을 찾지 못했다: $start');
  final j = src.indexOf(end, i + start.length);
  expect(j, greaterThan(i), reason: '구간 끝을 찾지 못했다: $end');
  return src.substring(i, j);
}

// ── canonical 권한 판정 4상태 복제 (UserProvider.PermissionCheck) ────
enum Perm { allowed, denied, unknown, error }

enum Surface { noPermission, loading, error, empty, rows }

/// 로드 결과 상태 — `_loadApplicants()` 의 판단 그대로.
class LoadState {
  const LoadState({
    this.hasLoadedOnce = false,
    this.loadFailed = false,
    this.refreshFailed = false,
    this.loadDenied = false,
    this.rowCount = 0,
  });

  final bool hasLoadedOnce;
  final bool loadFailed;
  final bool refreshFailed;
  final bool loadDenied;
  final int rowCount;

  /// [ok]=성공, [denied]=확인된 권한 거부(그 외는 일반 실패).
  LoadState apply({required bool ok, bool denied = false, int rows = 0}) {
    if (ok) {
      return LoadState(
          hasLoadedOnce: true,
          loadFailed: false,
          refreshFailed: false,
          loadDenied: false,
          rowCount: rows);
    }
    if (denied) {
      // 낡은 명단을 남기지 않는다 — 배너도 붙이지 않는다.
      return const LoadState(
          hasLoadedOnce: false,
          loadFailed: false,
          refreshFailed: false,
          loadDenied: true,
          rowCount: 0);
    }
    if (hasLoadedOnce) {
      return LoadState(
          hasLoadedOnce: true,
          loadFailed: false,
          refreshFailed: true,
          loadDenied: false,
          rowCount: rowCount);
    }
    return LoadState(
        hasLoadedOnce: false,
        loadFailed: true,
        refreshFailed: false,
        loadDenied: false,
        rowCount: rowCount);
  }
}

/// build() 의 분기 그대로 — 권한 없음이 가장 먼저다.
Surface surfaceOf({
  required Perm perm,
  required bool isLoading,
  required LoadState s,
}) {
  if (perm == Perm.denied || s.loadDenied) return Surface.noPermission;
  if (isLoading) return Surface.loading;
  if (s.loadFailed) return Surface.error;
  if (s.rowCount == 0) return Surface.empty;
  return Surface.rows;
}

/// 민감 내용·액션이 그려지는가.
bool rendersApplicants(Surface s) => s == Surface.rows;
bool rendersActions(Surface s) => s != Surface.noPermission;

void main() {
  late String src;
  late String buildBody;

  setUpAll(() {
    src = _codeOf(
        _read('lib/screens/business_admin/dialogs/work_applicants_dialog.dart'));
    buildBody = _slice(src, 'Widget build(BuildContext context) {',
        'Widget _buildHeader(');
  });

  // ══════════════════════════════════════════════════════════════
  // A. 최초 권한 거부
  // ══════════════════════════════════════════════════════════════

  group('WAP-A 최초 권한 거부', () {
    test('WAP-A1 NO_PERMISSION 이고 행·액션이 0이다', () {
      final s = const LoadState().apply(ok: false, denied: true);
      final surface = surfaceOf(perm: Perm.denied, isLoading: false, s: s);
      expect(surface, Surface.noPermission);
      expect(rendersApplicants(surface), isFalse);
      expect(rendersActions(surface), isFalse);
      expect(s.rowCount, 0);
    });

    test('WAP-A2 로딩보다 먼저 판정된다', () {
      final s = const LoadState().apply(ok: false, denied: true);
      expect(surfaceOf(perm: Perm.allowed, isLoading: true, s: s),
          Surface.noPermission,
          reason: '로딩 스피너 뒤에 민감 화면이 준비되는 것처럼 보이면 안 된다');
    });

    test('WAP-A3 build 가 권한을 가장 먼저 분기한다', () {
      final np = buildBody.indexOf('noPermission');
      final loading = buildBody.indexOf('isLoading\n');
      expect(np, greaterThan(-1), reason: '권한 분기가 없다');
      expect(buildBody, contains('? _buildNoPermissionState()'));
      expect(np, lessThan(loading == -1 ? buildBody.length : loading));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // B·C. 일반 실패는 그대로 (30d82dd semantics 유지)
  // ══════════════════════════════════════════════════════════════

  test('WAP-B 최초 일반 실패는 ERROR 이고 재시도 가능하다', () {
    final s = const LoadState().apply(ok: false);
    expect(surfaceOf(perm: Perm.allowed, isLoading: false, s: s), Surface.error);
    expect(s.loadDenied, isFalse);

    final err = _slice(src, 'Widget _buildLoadErrorState() {',
        'Widget _buildNoPermissionState() {');
    expect(err, contains('다시 시도'));
  });

  test('WAP-C 권한 유효 + 일반 새로고침 실패 → 기존 행 유지 + 경고', () {
    var s = const LoadState().apply(ok: true, rows: 4);
    s = s.apply(ok: false);
    expect(s.rowCount, 4, reason: '쓸 만한 데이터를 지우는 것도 거짓말이다');
    expect(s.refreshFailed, isTrue);
    expect(surfaceOf(perm: Perm.allowed, isLoading: false, s: s), Surface.rows);
  });

  // ══════════════════════════════════════════════════════════════
  // D. BLOCKER — 행을 본 뒤 권한 회수
  // ══════════════════════════════════════════════════════════════

  group('WAP-D 권한 회수', () {
    test('WAP-D1 거부 새로고침은 기존 행을 지운다', () {
      var s = const LoadState().apply(ok: true, rows: 5);
      expect(s.rowCount, 5);
      s = s.apply(ok: false, denied: true);
      expect(s.rowCount, 0, reason: '볼 자격을 잃은 뒤에도 이름·연락처가 남았다');
      expect(s.loadDenied, isTrue);
      expect(surfaceOf(perm: Perm.allowed, isLoading: false, s: s),
          Surface.noPermission);
    });

    test('WAP-D2 stale 배너를 붙이지 않는다', () {
      var s = const LoadState().apply(ok: true, rows: 5);
      s = s.apply(ok: false, denied: true);
      expect(s.refreshFailed, isFalse,
          reason: '권한 상실을 `새로고침 실패`로 말하면 다시 시도하게 만든다');
      expect(s.loadFailed, isFalse);
    });

    test('WAP-D3 구독이 회수를 밀어준 경우도 같은 결론이다', () {
      // 재조회 없이 permission watch 만으로 denied 가 된 경우.
      final s = const LoadState().apply(ok: true, rows: 3);
      expect(surfaceOf(perm: Perm.denied, isLoading: false, s: s),
          Surface.noPermission);
      expect(rendersApplicants(Surface.noPermission), isFalse);
    });

    test('WAP-D4 실제 clear 가 코드에 있다', () {
      final handler = _slice(src, 'Future<void> _loadApplicants() async {',
          'Future<void> _runLoadApplicants()');
      expect(handler, contains('_applicants = [];'));
      expect(handler, contains('_allApplications = [];'));
      expect(handler, contains('_idCardStatusMap = {};'));
      expect(handler, contains('_contractStatusMap = {};'));
      expect(handler, contains('_selectedIds.clear();'));
      expect(handler, contains('_isBatchMode = false;'));
      expect(handler, contains('_isIdCardSelectMode = false;'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // E·F. 다른 상태의 문구를 빌려 쓰지 않는다
  // ══════════════════════════════════════════════════════════════

  group('WAP-EF 문구 분리', () {
    late String noPerm;
    setUpAll(() {
      noPerm = _slice(src, 'Widget _buildNoPermissionState() {',
          'Widget _buildCloseOnlyBar(');
    });

    test('WAP-E "지원자가 없습니다"를 쓰지 않는다', () {
      expect(noPerm, isNot(contains('지원자가 없습니다')));
      expect(noPerm, isNot(contains('지원자 없음')));
    });

    test('WAP-F 일반 로드 실패 문구가 아니다', () {
      expect(noPerm, isNot(contains('불러오지 못했')));
      expect(noPerm, isNot(contains('error_outline')));
      expect(noPerm, contains('권한이 없습니다'));
    });

    test('WAP-F2 retry loop 대신 닫기를 준다', () {
      expect(noPerm, isNot(contains('다시 시도')),
          reason: '다시 눌러서 열릴 문이 아니다');
      final bar =
          _slice(src, 'Widget _buildCloseOnlyBar(', 'Widget _buildRefreshFailedBanner(');
      expect(bar, contains('닫기'));
      expect(bar, isNot(contains('_batchApprove')));
      expect(bar, isNot(contains('_batchReject')));
    });

    test('WAP-F3 고장처럼 보이지 않는다', () {
      expect(noPerm, contains('Icons.lock_outline'));
      expect(noPerm, contains('문의'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // G. 권한 복구
  // ══════════════════════════════════════════════════════════════

  test('WAP-G 권한 복구 + 재조회 → 현재 명단이 다시 보인다', () {
    var s = const LoadState().apply(ok: true, rows: 5);
    s = s.apply(ok: false, denied: true);
    expect(surfaceOf(perm: Perm.denied, isLoading: false, s: s),
        Surface.noPermission);

    // 권한이 돌아오고 재조회에 성공하면 **그때 읽은** 행을 보여준다.
    s = s.apply(ok: true, rows: 2);
    expect(s.loadDenied, isFalse);
    expect(s.rowCount, 2, reason: '지워진 옛 5건이 아니라 지금 읽은 2건이다');
    expect(surfaceOf(perm: Perm.allowed, isLoading: false, s: s), Surface.rows);
  });

  test('WAP-G2 재조회 시작 시 거부 표식이 초기화된다', () {
    final loader = _slice(src, 'Future<void> _loadApplicants() async {',
        'await _runLoadApplicants();');
    expect(loader, contains('_loadDenied = false;'));
    expect(loader, contains('_loadOk = false;'));
  });

  // ══════════════════════════════════════════════════════════════
  // H. 판정 근거 — code 만 쓴다
  // ══════════════════════════════════════════════════════════════

  group('WAP-H 판정 근거', () {
    test('WAP-H1 error code 로만 판정한다', () {
      final fn = _slice(src, 'static bool isPermissionDenial(Object error) {',
          '@override');
      expect(fn, contains('FirebaseFunctionsException'));
      expect(fn, contains('FirebaseException'));
      expect(fn, contains("'permission-denied'"));
      expect(fn, contains("'unauthenticated'"));
      expect(fn, contains('.code'));
    });

    test('WAP-H2 메시지·UI 문구로 판정하지 않는다', () {
      for (final banned in [
        "message.contains('permission",
        "toString().contains('permission",
        "e.message ==",
      ]) {
        expect(src, isNot(contains(banned)), reason: '문자열 파싱: $banned');
      }
      // 문구를 바꿨다고 보안 판정이 흔들리면 안 된다.
      expect(src, isNot(contains("contains('권한')")));
    });

    test('WAP-H3 canonical permission helper 를 재사용한다', () {
      expect(src, contains('checkForBusiness'));
      expect(src, contains('PermissionCheck.denied'));
      // 새 권한 capability 를 만들지 않았다.
      expect(src, contains('p.canManageTo'));
      final up = _codeOf(_read('lib/providers/user_provider.dart'));
      expect(up, contains('PermissionCheck checkForBusiness'));
      for (final invented in ['canViewApplicants', 'canReadStaffing']) {
        expect(up, isNot(contains(invented)), reason: '새 capability: $invented');
      }
    });

    test('WAP-H4 unknown/error 를 denied 로 추정하지 않는다', () {
      for (final p in [Perm.unknown, Perm.error]) {
        final s = const LoadState().apply(ok: true, rows: 3);
        expect(surfaceOf(perm: p, isLoading: false, s: s), Surface.rows,
            reason: '$p 를 권한 없음으로 바꿨다');
      }
      final helper = _slice(src, 'PermissionCheck _staffingPermission() {',
          'static bool isPermissionDenial(');
      expect(helper, contains('PermissionCheck.unknown'));
      expect(helper, contains('widget.targetPermissions'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §10. 권한 상실 후 실행 가능한 것이 없다
  // ══════════════════════════════════════════════════════════════

  group('WAP-S 보안 회귀', () {
    test('WAP-S1 민감 표면이 전부 권한 게이트 안에 있다', () {
      final gated = _slice(buildBody, 'if (!noPermission) ...[', '],');
      for (final w in [
        '_buildStatsBar',
        '_buildStaffingActionRow',
        '_buildSelectAllRow',
        '_buildRefreshFailedBanner',
      ]) {
        expect(gated, contains(w), reason: '$w 가 권한 게이트 밖에 있다');
      }
    });

    test('WAP-S2 목록 빌더가 권한 분기 뒤에 온다', () {
      final np = buildBody.indexOf('_buildNoPermissionState()');
      for (final w in [
        '_buildGroupedApplicantList',
        '_buildApplicantList',
      ]) {
        final i = buildBody.indexOf(w);
        expect(i, greaterThan(-1));
        expect(np, lessThan(i), reason: '$w 가 권한 판정보다 먼저 온다');
      }
    });

    test('WAP-S4 일괄 액션 하단 바가 서지 않는다', () {
      expect(buildBody,
          contains('if (noPermission) _buildCloseOnlyBar(context) else _buildBottomBar(context)'));
      // 일괄 확정·거절은 _buildBottomBar 안에만 있다.
      final bottom = _slice(src, 'Widget _buildBottomBar(BuildContext context) {',
          'Widget _buildBottomBarButton(');
      expect(bottom, contains('_batchReject'));
      expect(bottom, contains('_batchApprove'));
    });

    test('WAP-S5 서버 가드를 건드리지 않았다', () {
      final cf = _read('functions/src/index.ts');
      expect(cf, contains('callableGetApplicationsByBiz'));
      expect(cf, contains('assertBizAdmin'));
      expect(cf, contains('"TO 관리 권한이 없습니다."'));
    });

    test('WAP-S6 액션 게이트는 그대로다', () {
      expect(src, contains('bool _canManageTo() => _permissionFor'));
      expect(src, contains('bool _canManageContract() => _permissionFor'));
      expect(src, contains('return false; // fail-closed'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // I. 기존 계약 회귀
  // ══════════════════════════════════════════════════════════════

  group('WAP-I 기존 계약', () {
    test('WAP-I1 SUCCESS_ZERO / ERROR / PARTIAL 의미가 그대로다', () {
      final zero = const LoadState().apply(ok: true, rows: 0);
      expect(surfaceOf(perm: Perm.allowed, isLoading: false, s: zero),
          Surface.empty);

      final err = const LoadState().apply(ok: false);
      expect(surfaceOf(perm: Perm.allowed, isLoading: false, s: err),
          Surface.error);

      final partial =
          const LoadState().apply(ok: true, rows: 3).apply(ok: false);
      expect(surfaceOf(perm: Perm.allowed, isLoading: false, s: partial),
          Surface.rows);
      expect(partial.refreshFailed, isTrue);
    });

    test('WAP-I2 네 상태가 서로 다른 표면을 갖는다', () {
      final seen = <Surface>{
        surfaceOf(
            perm: Perm.allowed,
            isLoading: false,
            s: const LoadState().apply(ok: true, rows: 0)),
        surfaceOf(
            perm: Perm.allowed,
            isLoading: false,
            s: const LoadState().apply(ok: false)),
        surfaceOf(
            perm: Perm.allowed,
            isLoading: false,
            s: const LoadState().apply(ok: true, rows: 2).apply(ok: false)),
        surfaceOf(
            perm: Perm.denied,
            isLoading: false,
            s: const LoadState().apply(ok: false, denied: true)),
      };
      expect(seen.length, 4, reason: '네 상태가 같은 화면으로 뭉개졌다');
    });

    test('WAP-I3 부족·정원 UNKNOWN 표면 유지', () {
      expect(src, contains('_buildCapacityUnknownNotice'));
      expect(src, contains('InviteCapacityState.unknown'));
      expect(src, contains('staffingShortageOf'));
    });

    test('WAP-I4 recruiting 색·Day 동작을 건드리지 않았다', () {
      final badge = _codeOf(_read('lib/widgets/common/slot_status_badge.dart'));
      expect(badge, contains('AppColors.infoDeep'));
      final day = _codeOf(_read(
          'lib/screens/business_admin/dialogs/day_applicants_dialog.dart'));
      expect(day, contains('인력 현황을 불러오지 못했어요'));
    });
  });
}
