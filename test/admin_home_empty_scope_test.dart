// 빈 scope와 조회 실패의 구분 (FP-02)
//
// canonical rule:
//   EMPTY_SCOPE != QUERY_FAILURE
//
// callableGetAdminHomeSummary의 `available`은 "쿼리가 성공했는가"다
// (거짓 0 방지용). 관리 중인 사업장이 0개인 것은 실패가 아니라 정상 상태인데,
// 이전에는 available:false로 반환해 갓 가입한 관리자의 첫 홈에서
// '처리할 일' 다섯 줄이 모두 '조회 실패'로 렌더됐다.
//
// 이 파일은 그 구분이 다시 무너지지 않게 지킨다.
// 서버는 TypeScript라 Dart 테스트에서 실행할 수 없으므로 응답 계약은
// 소스로, 클라이언트 해석은 실제 DTO 단위 테스트로 검증한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/ui/admin_home_summary_model.dart';

String _source(String p) {
  final f = File(p);
  expect(f.existsSync(), true, reason: '$p 를 찾지 못함');
  return f.readAsStringSync();
}

/// 서버의 빈 scope 응답과 동일한 모양.
/// 각 섹션이 available:true / count:0 이어야 한다.
Map<String, dynamic> _emptyScopeActions({required bool available}) {
  final simple = {'available': available, 'count': 0, 'byBusiness': <dynamic>[]};
  return {
    'approval': {...simple, 'overdueCount': 0},
    'unsentContract': simple,
    'unpaidWage': {...simple, 'overdueCount': 0, 'missingDueDateCount': 0},
    'unclosed': {...simple, 'oldestDate': null},
    'wageChangeRequest': simple,
    'settlementRequest': simple,
  };
}

void main() {
  // ── §17 CASE A — 빈 scope ───────────────────────────────────────
  group('FP02-0x 빈 scope는 정상 0건이다', () {
    test('FP02-01 서버가 빈 scope를 available:true로 반환한다', () {
      final fns = _source('functions/src/index.ts');
      final i = fns.indexOf('if (businessIds.length === 0) {');
      expect(i, greaterThan(-1), reason: '빈 scope 분기를 찾지 못함');
      final branch = fns.substring(i, i + 900);
      expect(
          branch.contains(
              'const emptySimple = {available: true, count: 0, byBusiness: [] as unknown[]};'),
          true,
          reason: '빈 scope가 여전히 조회 실패로 표현됨');
    });

    test('FP02-02 빈 scope 응답에서 처리할 액션이 0건으로 해석된다', () {
      final a = AdminHomeActionsData.fromMap(
          _emptyScopeActions(available: true));
      expect(a.hasAnyAction, false);
      expect(a.totalActionCount, 0);
      // 각 섹션은 "사용 가능하지만 0건"이다 — 실패가 아니다.
      expect(a.approval.available, true);
      expect(a.unsentContract.available, true);
      expect(a.unpaidWage.available, true);
      expect(a.unclosed.available, true);
      expect(a.wageChangeRequest.available, true);
      expect(a.settlementRequest.available, true);
    });

    test('FP02-03 available:true + count:0 은 hasData=false', () {
      // 클라이언트의 행 숨김 규칙(available && count == 0 → hide)이
      // 그대로 동작하는 근거.
      final s = AdminHomeSimpleSection.fromMap(
          {'available': true, 'count': 0, 'byBusiness': <dynamic>[]});
      expect(s.available, true);
      expect(s.count, 0);
      expect(s.hasData, false);
    });

    test('FP02-04 빈 scope에서 scope.businessCount가 0으로 온다', () {
      final fns = _source('functions/src/index.ts');
      final i = fns.indexOf('if (businessIds.length === 0) {');
      final branch = fns.substring(i, i + 900);
      expect(branch.contains('scope: {businessCount: 0}'), true);
    });
  });

  // ── §17 CASE B/C — 사업장 있음 ──────────────────────────────────
  group('FP02-1x 사업장이 있는 경우', () {
    test('FP02-10 처리할 건이 없으면 0건 (실패 아님)', () {
      final a = AdminHomeActionsData.fromMap(
          _emptyScopeActions(available: true));
      expect(a.hasAnyAction, false);
    });

    test('FP02-11 실제 건수가 있으면 그대로 해석된다', () {
      final a = AdminHomeActionsData.fromMap({
        'approval': {
          'available': true,
          'count': 3,
          'overdueCount': 1,
          'byBusiness': <dynamic>[],
        },
        'unsentContract': {
          'available': true,
          'count': 2,
          'byBusiness': <dynamic>[],
        },
        'unpaidWage': {
          'available': true,
          'count': 0,
          'overdueCount': 0,
          'missingDueDateCount': 0,
          'byBusiness': <dynamic>[],
        },
        'unclosed': {
          'available': true,
          'count': 0,
          'oldestDate': null,
          'byBusiness': <dynamic>[],
        },
        'wageChangeRequest': {
          'available': true,
          'count': 0,
          'byBusiness': <dynamic>[],
        },
        'settlementRequest': {
          'available': true,
          'count': 0,
          'byBusiness': <dynamic>[],
        },
      });
      expect(a.hasAnyAction, true);
      expect(a.totalActionCount, 5);
      expect(a.approval.hasData, true);
      expect(a.unpaidWage.hasData, false);
    });
  });

  // ── §9 / §17 CASE D — 실제 실패는 실패로 남는다 ─────────────────
  group('FP02-2x 실제 조회 실패 semantics 보존', () {
    test('FP02-20 available:false 는 여전히 데이터 없음과 구분된다', () {
      final failed = AdminHomeActionsData.fromMap(
          _emptyScopeActions(available: false));
      expect(failed.hasAnyAction, false);
      // 0건이 아니라 "확인하지 못함" — 클라이언트가 이 차이로 '조회 실패'를 띄운다.
      expect(failed.approval.available, false);
      expect(failed.unsentContract.available, false);
    });

    test('FP02-21 집계 경로의 실패 판정이 그대로다', () {
      final fns = _source('functions/src/index.ts');
      // 권한 있는 사업장 중 하나라도 쿼리 실패하면 available:false
      expect(
          fns.contains('available: permCount > 0 && successCount === permCount'),
          true,
          reason: '실제 쿼리 실패가 더 이상 available:false로 표현되지 않음');
    });

    test('FP02-22 부분 실패를 0으로 삼키지 않는다', () {
      // 빈 scope 분기만 바꿨고 집계 경로는 손대지 않았다.
      final fns = _source('functions/src/index.ts');
      for (final marker in const [
        'appPermCount > 0 && appSuccessCount === appPermCount',
        'unpaidPermCount > 0 && unpaidSuccessCount === unpaidPermCount',
        'unclosedPermCount > 0 && unclosedSuccessCount === unclosedPermCount',
      ]) {
        expect(fns.contains(marker), true, reason: '"$marker" 판정이 사라짐');
      }
    });

    test('FP02-23 noAccess 상수의 권한 없음 표현은 그대로다', () {
      // 권한 없음은 이번 범위가 아니다 — 클라이언트가 해당 행 자체를
      // 렌더하지 않으므로 '조회 실패'로 새지 않는다.
      const denied = AdminHomeSimpleSection.noAccess;
      expect(denied.available, false);
      expect(denied.count, 0);
      expect(denied.hasData, false);
    });
  });

  // ── §8 / §13 UI를 덮지 않았다 ───────────────────────────────────
  group('FP02-3x 클라이언트 계약 무변경', () {
    late final String home =
        _source('lib/screens/business_admin/business_admin_home_screen.dart');

    test('FP02-30 행 숨김 규칙이 그대로다', () {
      expect(home.contains('if (!available || count == 0) return;'), true);
    });

    test('FP02-31 조회 실패 사실이 사라지지 않았다', () {
      // backend 의미 오류를 UI에서 숨기는 방식으로 고치지 않았다.
      // [HOME-V2-08D.5] 다만 표현 위치가 바뀌었다 — 행이 아니라 section notice다.
      //   `퇴사 요청 조회 실패`라는 행은 "처리할 퇴사 요청이 있다"는 뜻이라
      //   실패를 없는 업무로 둔갑시켰다. 실패는 데이터 상태로만 말한다.
      expect(home.contains("'일부 업무 상태를 확인하지 못했어요'"), true);
      expect(home.contains("'처리할 업무 상태를 확인하지 못했어요'"), true);
    });

    test('FP02-32 빈 scope 전용 client special-case를 넣지 않았다', () {
      for (final banned in const [
        'businessIds.isEmpty',
        '_businesses.isEmpty && _canonicalSummary',
        'hideActionsWhenNoBusiness',
      ]) {
        expect(home.contains(banned), false, reason: '"$banned" 우회 분기가 추가됨');
      }
    });

    test('FP02-33 새 빈 상태 카드를 추가하지 않았다', () {
      // 기존 '처리할 업무가 없어요'가 그대로 처리한다.
      expect(home.contains("'처리할 업무가 없어요'"), true);
    });
  });

  // ── 범위 불변식 ─────────────────────────────────────────────────
  group('FP02-4x 범위 밖 불변식', () {
    test('FP02-40 응답 필드가 그대로다 (rename/removal 없음)', () {
      final fns = _source('functions/src/index.ts');
      final i = fns.indexOf('if (businessIds.length === 0) {');
      final branch = fns.substring(i, i + 900);
      for (final key in const [
        'approval:',
        'unsentContract:',
        'unpaidWage:',
        'unclosed:',
        'wageChangeRequest:',
        'settlementRequest:',
        'expiringContract:',
        'generatedAt:',
      ]) {
        expect(branch.contains(key), true, reason: '$key 필드가 사라짐');
      }
    });

    test('FP02-41 first-posting readiness 무변경', () {
      final home = _source(
          'lib/screens/business_admin/business_admin_home_screen.dart');
      expect(home.contains('FirstPostingReadiness'), true);
      expect(home.contains('_reloadReadiness'), true);
    });

    test('FP02-42 승인 복구 무변경', () {
      final fns = _source('functions/src/index.ts');
      expect(fns.contains('export const callableRecheckBusinessApproval'), true);
      expect(fns.contains('approvedBy: "system_auto_recheck"'), true);
    });

    test('FP02-43 새 persisted 상태가 없다', () {
      final fns = _source('functions/src/index.ts');
      for (final banned in const [
        'hasBusiness:',
        'emptyScope:',
        'summaryInitialized',
      ]) {
        expect(fns.contains(banned), false, reason: '$banned 필드가 추가됨');
      }
    });
  });
}
