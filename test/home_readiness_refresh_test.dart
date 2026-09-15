// 홈 첫 공고 준비 상태의 갱신 완결성 (P2-01)
//
// P2-01 READINESS_STALE_AFTER_BUSINESS_REGISTRATION
//   _firstPosting을 갱신하는 경로가 initState / 준비 카드 CTA / 사업장 전환
//   셋뿐이었다. STATE A 배너로 첫 사업장을 등록하고 돌아오면 _businesses는
//   최신인데 _firstPosting은 구 상태라, 방금 사업장을 만들었는데도
//   "0 / 4"와 '사업장 등록 후 가능' 잠금이 그대로 남았다.
//   Shell이 IndexedStack이라 initState가 다시 돌지 않고, 당겨서 새로고침도
//   readiness를 갱신하지 않아 스스로 벗어나기 어려웠다.
//
// 이번 변경은 refresh 완결성만 다룬다 — readiness 계산·카드 UI·CreateTO는
// 손대지 않았다. 계산 로직은 순수 단위 테스트로, 호출 경로는 소스로 검증한다
// (홈 화면은 Firebase 서비스를 필드로 즉시 보유해 widget 테스트가 불가능하다).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/services/business_posting_readiness.dart';

const _homePath =
    'lib/screens/business_admin/business_admin_home_screen.dart';

String _source(String p) {
  final f = File(p);
  expect(f.existsSync(), true, reason: '$p 를 찾지 못함');
  return f.readAsStringSync();
}

/// 주석을 제외한 실제 코드만 본다 —
/// 설명 주석에도 함수명이 등장하므로 호출 지점 계수가 부풀려진다.
List<String> _codeLines(String p) => _source(p)
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .toList();

FirstPostingReadiness _r({
  bool hasAnyBusiness = false,
  bool businessReady = false,
  bool workTypesReady = false,
  bool contractTemplateReady = false,
  bool sealReady = false,
}) =>
    FirstPostingReadiness(
      hasAnyBusiness: hasAnyBusiness,
      businessReady: businessReady,
      workTypesReady: workTypesReady,
      contractTemplateReady: contractTemplateReady,
      sealReady: sealReady,
    );

void main() {
  // ── §18 STATE A 복귀 ────────────────────────────────────────────
  group('HRR-0x 사업장 등록 복귀', () {
    test('HRR-01 등록 전/후 readiness가 실제로 달라진다', () {
      // 이 차이가 화면에 반영되지 않던 것이 P2-01이었다.
      final before = _r();
      expect(before.completedCount, 0);
      expect(before.hasAnyBusiness, false);

      final after = _r(hasAnyBusiness: true, businessReady: true);
      expect(after.hasAnyBusiness, true);
      expect(after.isDone(FirstPostingTask.business), true);
      expect(after.completedCount, 1);
    });

    test('HRR-02 STATE A 복귀가 readiness까지 다시 계산한다', () {
      final code = _codeLines(_homePath);
      // 사업장 상태만 다시 읽고 끝나는 복귀 경로가 남아 있으면 안 된다.
      final bare = code
          .where((l) => l.contains('_loadApprovedBusinessStatus()'))
          .where((l) => l.contains('if (mounted)'))
          .toList();
      expect(bare, isEmpty,
          reason: 'readiness 갱신 없이 사업장 상태만 다시 읽는 복귀 경로: $bare');
    });

    test('HRR-03 BusinessFormScreen 복귀 지점이 _reloadReadiness를 쓴다', () {
      final src = _source(_homePath);
      final i = src.indexOf('builder: (_) => const BusinessFormScreen()));');
      expect(i, greaterThan(-1), reason: 'STATE A 배너의 이동 지점을 찾지 못함');
      final after = src.substring(i, i + 400);
      expect(after.contains('_reloadReadiness()'), true);
    });
  });

  // ── §19 등록 직후 actionability ─────────────────────────────────
  group('HRR-1x 등록 직후 잠금이 풀린다', () {
    test('HRR-10 사업장이 생기면 업무 등록이 즉시 가능해진다', () {
      expect(_r().isActionable(FirstPostingTask.workType), false);
      expect(
          _r(hasAnyBusiness: true).isActionable(FirstPostingTask.workType),
          true);
    });

    test('HRR-11 사업장이 생기면 계약서 템플릿이 즉시 가능해진다', () {
      expect(_r().isActionable(FirstPostingTask.contractTemplate), false);
      expect(
          _r(hasAnyBusiness: true)
              .isActionable(FirstPostingTask.contractTemplate),
          true);
    });

    test('HRR-12 승인 전이어도 잠기지 않는다', () {
      // 승인 대기 중에도 두 항목은 준비할 수 있다(Rules도 승인을 요구하지 않음).
      final pending = _r(hasAnyBusiness: true, businessReady: false);
      expect(pending.isActionable(FirstPostingTask.workType), true);
      expect(pending.isActionable(FirstPostingTask.contractTemplate), true);
      expect(pending.isDone(FirstPostingTask.business), false);
    });

    test('HRR-13 잠금 판정이 hasAnyBusiness에서 나온다', () {
      // 화면이 stale 값을 쓰면 이 판정이 맞아도 잠금이 남는다 — HRR-02가 그것을 막는다.
      final src = _source('lib/services/business_posting_readiness.dart');
      final i = src.indexOf('bool isActionable(FirstPostingTask task)');
      expect(i, greaterThan(-1));
      final body = src.substring(i, i + 420);
      expect(body.contains('return hasAnyBusiness;'), true);
    });
  });

  // ── §20 pull-to-refresh ─────────────────────────────────────────
  group('HRR-2x 당겨서 새로고침', () {
    test('HRR-20 _refresh가 readiness를 포함한다', () {
      final src = _source(_homePath);
      final i = src.indexOf('Future<void> _refresh() async {');
      expect(i, greaterThan(-1));
      final body = src.substring(i, i + 700);
      expect(body.contains('_reloadReadiness()'), true,
          reason: '당겨서 새로고침 후에도 준비 상태가 stale하게 남는다');
    });

    test('HRR-21 RefreshIndicator가 _refresh에 연결돼 있다', () {
      final src = _source(_homePath);
      expect(src.contains('onRefresh: _refresh'), true);
    });
  });

  // ── §21 Settings 복귀 ───────────────────────────────────────────
  group('HRR-3x 설정 복귀', () {
    test('HRR-30 인감 등록 전후 readiness가 달라진다', () {
      final before = _r(hasAnyBusiness: true, businessReady: true);
      expect(before.isDone(FirstPostingTask.seal), false);
      final after = _r(
          hasAnyBusiness: true, businessReady: true, sealReady: true);
      expect(after.isDone(FirstPostingTask.seal), true);
      expect(after.completedCount, before.completedCount + 1);
    });

    test('HRR-31 헤더 설정 복귀가 readiness를 갱신한다', () {
      final src = _source(_homePath);
      final i = src.indexOf('builder: (_) => const SettingsScreen()));');
      expect(i, greaterThan(-1), reason: '헤더 설정 이동 지점을 찾지 못함');
      final after = src.substring(i, i + 400);
      expect(after.contains('_reloadReadiness()'), true);
    });

    test('HRR-32 인감 저장이 UserProvider를 갱신한다', () {
      // readiness가 UserProvider의 sealBase64를 읽으므로,
      // 저장 후 provider가 갱신되지 않으면 복귀해도 stale이다.
      final s = _source('lib/screens/common/settings_screen.dart');
      final i = s.indexOf("_callSaveSeal(b64, 'stamp')");
      expect(i, greaterThan(-1));
      expect(s.substring(i, i + 200).contains('refreshUserData()'), true);
    });
  });

  // ── §4 / §10 순서·중복 ──────────────────────────────────────────
  group('HRR-4x 순서와 중복', () {
    test('HRR-40 readiness 계산 전에 사업장 상태를 먼저 읽는다', () {
      final src = _source(_homePath);
      final i = src.indexOf('Future<void> _reloadReadiness() async {');
      expect(i, greaterThan(-1));
      final body = src.substring(i, src.indexOf('\n  }', i));
      final a = body.indexOf('_loadApprovedBusinessStatus()');
      final b = body.indexOf('_loadPostingReadiness()');
      expect(a, greaterThan(-1));
      expect(b, greaterThan(a),
          reason: 'stale _businesses로 readiness를 계산하게 된다');
      // 중간에 mounted 가드가 있어야 setState-after-dispose가 안 난다
      expect(body.contains('if (!mounted) return;'), true);
    });

    test('HRR-41 한 경로에서 사업장 조회를 두 번 하지 않는다', () {
      // _reloadReadiness()가 이미 _loadApprovedBusinessStatus()를 품고 있으므로
      // 같은 지점에서 둘 다 부르면 중복 쿼리가 된다.
      final code = _codeLines(_homePath);
      for (var i = 0; i < code.length; i++) {
        if (!code[i].contains('_reloadReadiness()')) continue;
        // 정의부는 제외 — 내부에서 사업장 조회를 부르는 것이 정상이다.
        if (code[i].contains('Future<void> _reloadReadiness()')) continue;
        final window = code
            .sublist((i - 3).clamp(0, code.length), (i + 4).clamp(0, code.length))
            .join('\n');
        expect(window.contains('_loadApprovedBusinessStatus()'), false,
            reason: '${i + 1}행 부근에서 사업장 조회가 중복된다');
      }
    });

    test('HRR-42 initState는 사업장 확정 후 readiness를 계산한다', () {
      // 기존 순서를 깨지 않았는지 — Future.wait로 사업장 조회가 끝난 뒤 호출된다.
      final src = _source(_homePath);
      final a = src.indexOf('_loadApprovedBusinessStatus(),');
      final b = src.indexOf('unawaited(_loadPostingReadiness());');
      expect(a, greaterThan(-1));
      expect(b, greaterThan(a));
    });
  });

  // ── §13~17, §22 범위 불변식 ─────────────────────────────────────
  group('HRR-5x 범위 밖 불변식', () {
    test('HRR-50 readiness 계산 로직 무변경', () {
      final s = _source('lib/services/business_posting_readiness.dart');
      expect(s.contains('static const int totalTasks = 4;'), true);
      expect(FirstPostingReadiness.totalTasks, 4);
      expect(FirstPostingTask.values.length, 4);
      // 완료 시 자동 소멸 계약
      expect(
          _r(
            hasAnyBusiness: true,
            businessReady: true,
            workTypesReady: true,
            contractTemplateReady: true,
            sealReady: true,
          ).allReady,
          true);
    });

    test('HRR-51 카드 UI 계약 무변경', () {
      final src = _source(_homePath);
      // [HOME-V2-08D.2] 제목이 Hero 문장으로 바뀌었다 — 카드 구성은 그대로다.
      expect(src.contains(r'공고 등록까지 ${FirstPostingReadiness.totalTasks - done}단계 남았어요'), true);
      expect(src.contains('/ \${FirstPostingReadiness.totalTasks} 완료'), true);
      expect(src.contains('SettingsTarget.seal'), true);
      expect(src.contains('if (r == null || r.allReady) return const SizedBox.shrink();'),
          true);
    });

    test('HRR-52 CreateTO 무변경', () {
      final c = _source(
          'lib/screens/business_admin/to_management/create_to_screen.dart');
      expect(
          c.contains(
              '_businessApproved && _workTypesReady && _contractTemplatesReady &&'),
          true);
      expect(c.contains('cardCount = isSubAdmin ? 4 : 5'), true);
      expect(c.contains('if (!_formUnlocked)'), true);
      // R-ADMIN-01은 backlog 유지 — workType CTA는 여전히 승인 의존
      expect(c.contains('onAction: _businessApproved'), true);
    });

    test('HRR-53 승인 복구·FP-02 무변경', () {
      final src = _source(_homePath);
      expect(src.contains('recheckApproval'), false);
      // [HOME-V2-08D.5] FP-02 표면이 행 → section notice로 옮겨졌다
      expect(src.contains("'일부 업무 상태를 확인하지 못했어요'"), true);
      final fns = _source('functions/src/index.ts');
      expect(
          fns.contains(
              'const emptySimple = {available: true, count: 0, byBusiness: [] as unknown[]};'),
          true);
    });

    test('HRR-54 새 조정 상태를 추가하지 않았다', () {
      final src = _source(_homePath);
      for (final banned in const [
        'needsReadinessRefresh',
        'readinessDirty',
        'forceReload',
      ]) {
        expect(src.contains(banned), false, reason: '$banned 추가됨');
      }
    });

    test('HRR-55 SUB_ADMIN 비노출 정책 무변경', () {
      final src = _source(_homePath);
      expect(src.contains('currentUser?.isSubAdmin == true'), true);
    });
  });
}
