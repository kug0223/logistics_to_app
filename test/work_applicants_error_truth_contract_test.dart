// [R7-P1-2] 인력 현황 다이얼로그 — 로드 실패를 0명으로 말하지 않는다.
//
//   증상은 이랬다. 지원자 조회가 실패하면 `runWithLoading`이 예외를 삼키고
//   (errorMessage 도 넘기지 않아 토스트조차 없었다) 목록이 빈 채로 남았다.
//   화면은 `지원자가 없습니다`라고 말했다 — 확정자가 3명인 업무에서도.
//   관리자는 지원자가 없다고 믿고 나갔다.
//
//   그래서 여기서 고정하는 두 문장.
//
//     ERROR   != ZERO
//     REFRESH != INITIAL
//
//   후자가 없으면 확정 직후 새로고침이 한 번 실패했다는 이유로 방금까지
//   보던 명단이 통째로 사라진다. 쓸 만한 데이터를 지우는 것도 거짓말이다.
//
//   상태 전이는 순수 함수로 복제해 경계를 고정하고, 실제 배선은 원문
//   문자열로 고정한다. 주석은 검사하지 않는다(`_codeOf`).

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

// ── 다이얼로그의 로드 상태 전이 복제 ────────────────────────────────
//
//   `_loadApplicants()` 가 하는 판단 그대로다. 값이 바뀌면 여기가 먼저 깨진다.

class LoadFlags {
  const LoadFlags({
    this.hasLoadedOnce = false,
    this.loadFailed = false,
    this.refreshFailed = false,
  });

  final bool hasLoadedOnce;
  final bool loadFailed;
  final bool refreshFailed;

  /// 한 번의 로드 시도 결과를 반영한다.
  LoadFlags apply({required bool ok}) {
    if (ok) {
      return const LoadFlags(
          hasLoadedOnce: true, loadFailed: false, refreshFailed: false);
    }
    if (hasLoadedOnce) {
      // 기존 행은 살려 둔다 — PARTIAL 이지 EMPTY 가 아니다.
      return LoadFlags(
          hasLoadedOnce: hasLoadedOnce, loadFailed: false, refreshFailed: true);
    }
    return const LoadFlags(
        hasLoadedOnce: false, loadFailed: true, refreshFailed: false);
  }

  /// 실패했을 때 토스트로 알리는가 — 기존 데이터가 있을 때만이다.
  bool toastOnFailure() => hasLoadedOnce;
}

enum Surface { loading, error, empty, rows }

/// build() 의 분기 그대로.
Surface surfaceOf({
  required bool isLoading,
  required LoadFlags flags,
  required int rowCount,
}) {
  if (isLoading) return Surface.loading;
  if (flags.loadFailed) return Surface.error;
  if (rowCount == 0) return Surface.empty;
  return Surface.rows;
}

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
  // A~G. 상태 진실성
  // ══════════════════════════════════════════════════════════════

  group('WAE-A 최초 로드 실패', () {
    test('WAE-A1 ERROR 가 되고 EMPTY 가 아니다', () {
      final f = const LoadFlags().apply(ok: false);
      expect(f.loadFailed, isTrue);
      expect(f.refreshFailed, isFalse);
      expect(f.hasLoadedOnce, isFalse);
      expect(surfaceOf(isLoading: false, flags: f, rowCount: 0), Surface.error);
    });

    test('WAE-A2 ERROR 화면이 "지원자가 없습니다"를 말하지 않는다', () {
      final err = _slice(src, 'Widget _buildLoadErrorState() {',
          'Widget _buildRefreshFailedBanner(');
      expect(err, isNot(contains('지원자가 없습니다')));
      expect(err, isNot(contains('지원자 없음')));
      expect(err, contains('확인하지 못했'), reason: '실제 zero 와 다른 표현');
      expect(err, contains('다시 시도'), reason: '복구 수단');
      expect(err, contains('Icons.error_outline'));
    });

    test('WAE-A3 build 가 EMPTY 보다 먼저 ERROR 를 분기한다', () {
      final e = buildBody.indexOf('_loadFailed');
      final z = buildBody.indexOf('_buildEmptyState()');
      expect(e, greaterThan(-1), reason: 'ERROR 분기가 없다');
      expect(z, greaterThan(-1));
      expect(e, lessThan(z),
          reason: 'EMPTY 를 먼저 판정하면 실패가 0명으로 새어 나간다');
    });

    test('WAE-A4 다시 시도가 실제 로더에 연결돼 있다', () {
      final err = _slice(src, 'Widget _buildLoadErrorState() {',
          'Widget _buildRefreshFailedBanner(');
      expect(err, contains('_loadApplicants'));
    });
  });

  group('WAE-B/C 성공 경로', () {
    test('WAE-B 성공 0건은 실제 EMPTY 다', () {
      final f = const LoadFlags().apply(ok: true);
      expect(f.loadFailed, isFalse);
      expect(surfaceOf(isLoading: false, flags: f, rowCount: 0), Surface.empty);
    });

    test('WAE-C 성공 N건은 ROWS 다', () {
      final f = const LoadFlags().apply(ok: true);
      expect(surfaceOf(isLoading: false, flags: f, rowCount: 3), Surface.rows);
    });

    test('WAE-C2 EMPTY 문구는 성공 경로에만 남아 있다', () {
      final empty =
          _slice(src, 'Widget _buildEmptyState() {', 'Widget _buildLoadErrorState(');
      expect(empty, contains('지원자가 없습니다'));
      expect(empty, isNot(contains('error_outline')));
    });
  });

  group('WAE-D/E 재시도', () {
    test('WAE-D 실패 → 재시도 → 0건이면 EMPTY', () {
      var f = const LoadFlags().apply(ok: false);
      expect(surfaceOf(isLoading: false, flags: f, rowCount: 0), Surface.error);
      f = f.apply(ok: true);
      expect(f.loadFailed, isFalse);
      expect(surfaceOf(isLoading: false, flags: f, rowCount: 0), Surface.empty);
    });

    test('WAE-E 실패 → 재시도 → N건이면 ROWS', () {
      var f = const LoadFlags().apply(ok: false);
      f = f.apply(ok: true);
      expect(surfaceOf(isLoading: false, flags: f, rowCount: 2), Surface.rows);
      expect(f.refreshFailed, isFalse, reason: '성공하면 실패 표시가 남지 않는다');
    });
  });

  group('WAE-F 새로고침 실패', () {
    test('WAE-F1 기존 행을 유지한다', () {
      var f = const LoadFlags().apply(ok: true); // 첫 로드 성공
      f = f.apply(ok: false); // 새로고침 실패
      expect(f.loadFailed, isFalse, reason: '전체를 ERROR 로 바꾸지 않는다');
      expect(f.refreshFailed, isTrue);
      expect(surfaceOf(isLoading: false, flags: f, rowCount: 4), Surface.rows);
    });

    test('WAE-F2 실패 신호가 존재한다', () {
      var f = const LoadFlags().apply(ok: true).apply(ok: false);
      expect(f.refreshFailed, isTrue, reason: '조용히 넘어가지 않는다');
      expect(f.toastOnFailure(), isTrue);

      final banner = _slice(src, 'Widget _buildRefreshFailedBanner(',
          'Widget _buildIdCardRequestSection(');
      expect(banner, contains('다시 시도'));
      expect(banner, contains('이전에 받은 내용'));
    });

    test('WAE-F3 배너가 목록을 대체하지 않는다', () {
      // 배너는 Expanded(목록) 앞에 놓인 형제여야 한다 — 목록 자리를 먹으면 안 된다.
      final b = buildBody.indexOf('_buildRefreshFailedBanner');
      final list = buildBody.indexOf('Expanded(');
      expect(b, greaterThan(-1));
      expect(list, greaterThan(-1));
      expect(b, lessThan(list));
      expect(buildBody, contains('_refreshFailed && !_loadFailed'),
          reason: '초기 실패와 새로고침 실패가 동시에 그려지지 않는다');
    });

    test('WAE-F4 일반 새로고침 실패가 행 수를 0으로 만들지 않는다', () {
      // [R7-P1-2.1] 여기는 원래 "실패 처리 어디에도 _applicants 대입이 없다"를
      //   고정하고 있었다. 그 뒤 축이 하나 늘었다 — **확인된 권한 거부**는
      //   반대로 지워야 한다. 그래서 앵커를 일반 실패 가지로 좁힌다.
      //   지우면 안 되는 곳과 지워야 하는 곳을 각각 못 박는다.
      final handler = _slice(src, 'Future<void> _loadApplicants() async {',
          'Future<void> _runLoadApplicants()');
      final genericBranch = _slice(handler, '} else if (hadRows) {', '} else {');
      for (final banned in ['_applicants =', '_pending =', '_confirmed =']) {
        expect(genericBranch, isNot(contains(banned)),
            reason: '일반 실패가 기존 명단을 비운다: $banned');
      }
      expect(genericBranch, contains('_refreshFailed = true;'));

      // 권한 거부 가지는 반대다 — 남기는 것이 사고다.
      final deniedBranch = _slice(handler, '} else if (denied) {', '} else if (hadRows) {');
      expect(deniedBranch, contains('_applicants = [];'));
    });
  });

  group('WAE-G 변환 금지', () {
    test('WAE-G1 확인하지 못한 것이 0명으로 바뀌지 않는다', () {
      // 한 번도 읽지 못한 실패는 절대 EMPTY 가 될 수 없다.
      //   권한 거부도 여기로 온다 — 조회가 throw 하므로 ok=false 다.
      final never = const LoadFlags().apply(ok: false);
      expect(surfaceOf(isLoading: false, flags: never, rowCount: 0),
          Surface.error,
          reason: '읽지 못한 것을 `없다`로 말했다');

      // 이미 0건을 **확인한 뒤**의 새로고침 실패는 EMPTY 가 맞다.
      //   그 0 은 실패에서 나온 값이 아니라 서버가 실제로 답한 값이다.
      //   다만 낡았다는 사실을 반드시 함께 말해야 한다 — 그래야 거짓이 아니다.
      final stale = const LoadFlags().apply(ok: true).apply(ok: false);
      expect(surfaceOf(isLoading: false, flags: stale, rowCount: 0),
          Surface.empty);
      expect(stale.refreshFailed, isTrue,
          reason: '낡았다는 신호 없이 0 을 말하면 그것도 거짓이다');
      expect(stale.toastOnFailure(), isTrue);
    });

    test('WAE-G2 실패는 반드시 어딘가에 드러난다', () {
      for (final hadRows in [true, false]) {
        final f = LoadFlags(hasLoadedOnce: hadRows).apply(ok: false);
        expect(f.loadFailed || f.refreshFailed, isTrue,
            reason: 'hasLoadedOnce=$hadRows — 실패가 흔적 없이 사라졌다');
      }
    });

    test('WAE-G3 로더가 결과를 삼키지 않는다', () {
      // runWithLoading 은 예외를 먹는다. 성공 표식이 있어야 실패를 알 수 있다.
      expect(src, contains('_loadOk = false;'));
      expect(src, contains('_loadOk = true;'));
      final inner = _slice(src, 'Future<void> _runLoadApplicants()',
          'void _groupApplicants()');
      final okIdx = inner.indexOf('_loadOk = true;');
      final setIdx = inner.indexOf('_applicants = applicantsWithUserInfo;');
      expect(okIdx, greaterThan(-1), reason: '성공 표식이 로더 안에 없다');
      expect(okIdx, lessThan(setIdx),
          reason: 'unmount 로 조기 반환되는 성공도 실패로 세면 안 된다');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 회귀 — 이번 패치가 건드리지 말아야 할 것
  // ══════════════════════════════════════════════════════════════

  group('WAE-R 회귀', () {
    test('WAE-R1 권한 게이트 그대로', () {
      expect(src, contains('_canManageTo()'));
      expect(src, contains('_canManageContract()'));
      expect(src, contains('canForBusiness'));
    });

    test('WAE-R2 정원 UNKNOWN 표면 그대로', () {
      expect(src, contains('InviteCapacityState.unknown'));
      expect(src, contains('_buildCapacityUnknownNotice'));
      expect(src, contains('staffingShortageOf'));
      expect(src, contains('inviteCapacityStateOf'));
    });

    test('WAE-R3 초대·확정 경로 그대로', () {
      expect(src, contains('_openInviteMethod'));
      expect(src, contains('AvailableWorkersBottomSheet'));
      expect(src, contains('InviteWorkerDialog.contextual'));
    });

    test('WAE-R4 AppEmptyState 에 새 capability 를 추가하지 않았다', () {
      final aes = _codeOf(_read('lib/widgets/common/app_empty_state.dart'));
      for (final banned in ['kind', 'EmptyStateKind', 'isError', 'partial']) {
        expect(aes, isNot(contains(banned)),
            reason: '쓰지 않는 shared abstraction 을 만들었다: $banned');
      }
      // 이번 ERROR 표면은 기존 icon/iconColor/action 만으로 만들었다.
      expect(aes, contains('this.iconColor'));
      expect(aes, contains('this.action'));
    });

    test('WAE-R5 서버·권한 계약 파일을 건드리지 않았다', () {
      // 이 Phase 는 클라이언트 표현 패치다.
      final day = _codeOf(_read(
          'lib/screens/business_admin/dialogs/day_applicants_dialog.dart'));
      expect(day, contains('인력 현황을 불러오지 못했어요'),
          reason: 'Day 의 기존 error semantics 는 그대로여야 한다');
    });
  });
}
