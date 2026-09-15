// 첫 공고 준비 정렬 (BUSINESS-ADMIN-FIRST-POSTING-READINESS-ALIGNMENT)
//
// FP-01: 홈은 서버 강제 항목(등록증·업무) 2개만 셌고 CreateTO는 5개를 요구했다.
//        홈에서 준비 카드가 사라진 뒤에도 공고 등록에서 계약서 템플릿·인감으로
//        다시 막혀, 준비의 끝이 두 번 왔다.
// FP-03: 계약서 템플릿·인감은 사업장 승인과 무관한데 UI가 승인에 종속시켰다.
// FP-05/06: 업무 용어 5가지 혼용, 사용자 노출 문자열의 내부 용어 'TO'.
// FP-07: 인감 CTA가 설정 최상단에만 떨어뜨렸다.
//
// readiness는 저장 플래그 없이 canonical fact에서만 derive된다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/services/business_posting_readiness.dart';

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

String _source(String p) {
  final f = File(p);
  expect(f.existsSync(), true, reason: '$p 를 찾지 못함');
  return f.readAsStringSync();
}

/// 사용자에게 보이는 문구만 본다.
///
/// 제외 대상:
///   · 주석 — "이 표현은 쓰지 않는다"고 적은 설명까지 금지어로 걸린다
///   · debugPrint — 로그는 내부 용어를 써도 되는 영역이다(§20)
String _copyOf(String p) {
  final withoutComments = _source(p)
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .where((l) => !l.contains('debugPrint('))
      .join('\n');
  return RegExp(r"'(?:[^'\\\n]|\\.)*'")
      .allMatches(withoutComments)
      .map((m) => m.group(0)!)
      .join('\n');
}

void main() {
  // ── §34 readiness ───────────────────────────────────────────────
  group('FPR-0x 준비 상태 판정', () {
    test('FPR-01 사업장 없음 → 0/4', () {
      final r = _r();
      expect(r.completedCount, 0);
      expect(r.allReady, false);
      expect(FirstPostingReadiness.totalTasks, 4);
    });

    test('FPR-02 사업장 승인+등록증 → 사업장 task 완료', () {
      final r = _r(hasAnyBusiness: true, businessReady: true);
      expect(r.isDone(FirstPostingTask.business), true);
      expect(r.completedCount, 1);
    });

    test('FPR-03 등록됐지만 미승인 → 사업장 task 미완료', () {
      // 수동 승인 대기를 "완료"로 세면 준비가 끝난 것처럼 보인다.
      final r = _r(hasAnyBusiness: true, businessReady: false);
      expect(r.isDone(FirstPostingTask.business), false);
      expect(r.completedCount, 0);
    });

    test('FPR-04 업무 없음 → 업무 task 미완료', () {
      final r = _r(hasAnyBusiness: true, businessReady: true);
      expect(r.isDone(FirstPostingTask.workType), false);
    });

    test('FPR-05 인감 없음 → 인감 task 미완료', () {
      final r = _r(hasAnyBusiness: true, businessReady: true, sealReady: false);
      expect(r.isDone(FirstPostingTask.seal), false);
    });

    test('FPR-06 4개 모두 → 4/4 + allReady', () {
      final r = _r(
        hasAnyBusiness: true,
        businessReady: true,
        workTypesReady: true,
        contractTemplateReady: true,
        sealReady: true,
      );
      expect(r.completedCount, 4);
      expect(r.allReady, true);
      expect(r.remaining, isEmpty);
    });

    test('FPR-07 남은 항목이 표시 순서를 유지한다', () {
      final r = _r(hasAnyBusiness: true, businessReady: true, sealReady: true);
      expect(r.remaining, [
        FirstPostingTask.workType,
        FirstPostingTask.contractTemplate,
      ]);
    });
  });

  // ── 계약서 템플릿 판정은 5.11 semantics를 그대로 쓴다 ───────────
  group('FPR-1x 계약서 템플릿 판정', () {
    test('FPR-10 홈이 CreateTO와 같은 selectableForNewContract를 쓴다', () {
      final home = _source(
          'lib/screens/business_admin/business_admin_home_screen.dart');
      expect(home.contains('selectableForNewContract'), true);
      // outsource-only는 미완료여야 한다 — 판정 함수가 이를 보장한다(5.11 테스트).
    });

    test('FPR-11 템플릿 소유 모델을 바꾸지 않았다 (전 사업장 합산)', () {
      final createTo = _source(
          'lib/screens/business_admin/to_management/create_to_screen.dart');
      expect(createTo.contains('selectableForNewContract(allTemplates)'), true);
    });
  });

  // ── §35 병렬 수행 ───────────────────────────────────────────────
  group('FPR-2x 병렬 준비', () {
    test('FPR-20 사업장·인감은 언제나 지금 가능', () {
      final r = _r(); // 사업장 0개
      expect(r.isActionable(FirstPostingTask.business), true);
      expect(r.isActionable(FirstPostingTask.seal), true);
    });

    test('FPR-21 미승인 사업장에서도 계약서 템플릿 가능', () {
      // Rules: contract_templates write는 isAdminOf만 요구 — 승인 무관.
      final r = _r(hasAnyBusiness: true, businessReady: false);
      expect(r.isActionable(FirstPostingTask.contractTemplate), true);
    });

    test('FPR-22 미승인 사업장에서도 인감 가능', () {
      final r = _r(hasAnyBusiness: true, businessReady: false);
      expect(r.isActionable(FirstPostingTask.seal), true);
    });

    test('FPR-23 사업장 0개면 업무·템플릿은 선행 필요', () {
      final r = _r();
      expect(r.isActionable(FirstPostingTask.workType), false);
      expect(r.isActionable(FirstPostingTask.contractTemplate), false);
    });

    test('FPR-24 CreateTO 템플릿 CTA가 승인에 종속되지 않는다', () {
      final createTo = _copyOf(
          'lib/screens/business_admin/to_management/create_to_screen.dart');
      final src = _source(
          'lib/screens/business_admin/to_management/create_to_screen.dart');
      expect(src.contains('canManageContract && _businessApproved'), false,
          reason: '계약서 템플릿 CTA가 여전히 사업장 승인을 요구함');
      expect(src.contains('_templateTargetBusinessId'), true);
      expect(createTo.length, greaterThan(0));
    });

    test('FPR-25 강제 순서(STEP) UI를 만들지 않았다', () {
      final home = _copyOf(
          'lib/screens/business_admin/business_admin_home_screen.dart');
      for (final banned in const ['STEP 1', 'STEP 2', '1단계', '2단계']) {
        expect(home.contains(banned), false, reason: '"$banned" wizard 표현이 추가됨');
      }
    });
  });

  // ── §36 용어 ────────────────────────────────────────────────────
  group('FPR-3x 용어 정렬', () {
    const workScreens = [
      'lib/screens/business_admin/to_management/create_to_screen.dart',
      'lib/screens/business_admin/work_type_management_screen.dart',
      'lib/screens/business_admin/work_type_detail_screen.dart',
      'lib/screens/common/settings_screen.dart',
      'lib/screens/business_admin/business_admin_home_screen.dart',
    ];

    test('FPR-30 사용자 문구에 업무목록/업무유형 혼용이 없다', () {
      for (final p in workScreens) {
        final copy = _copyOf(p);
        expect(copy.contains('업무목록'), false, reason: '$p 에 "업무목록" 잔존');
        expect(copy.contains('업무유형'), false, reason: '$p 에 "업무유형"(붙여쓰기) 잔존');
      }
    });

    test('FPR-31 설정 진입 명칭이 업무 관리로 통일됐다', () {
      final s = _copyOf('lib/screens/common/settings_screen.dart');
      expect(s.contains("'업무 관리'"), true);
      expect(s.contains("'업무 유형 관리'"), false);
    });

    const toScreens = [
      'lib/screens/business_admin/business_list_screen.dart',
      'lib/screens/business_admin/dialogs/day_applicants_dialog.dart',
      'lib/screens/business_admin/dialogs/to_list_dialogs.dart',
      'lib/screens/business_admin/dialogs/work_detail_management_dialog.dart',
      'lib/screens/business_admin/workforce_management/workforce_list_view.dart',
      'lib/screens/common/help_screen.dart',
    ];

    test('FPR-32 알려진 사용자 노출 TO 문구가 제거됐다', () {
      const stale = [
        '모든 TO와 데이터가',
        'TO를 확인해 주세요',
        'TO 정보가 없는 지원서',
        '지난 TO는',
        '새로운 날짜로 TO를',
        'TO 관리 권한이 없습니다',
        '조건에 맞는 TO가 없습니다',
        '새로운 TO를 생성하세요',
        '공고(TO)',
      ];
      for (final p in toScreens) {
        final copy = _copyOf(p);
        for (final t in stale) {
          expect(copy.contains(t), false, reason: '$p 에 "$t" 잔존');
        }
      }
    });

    test('FPR-33 코드 식별자의 TO는 그대로 유지된다', () {
      // 내부 모델명까지 바꾸지 않는다 — UI 문구만 정렬했다.
      final src = _source(
          'lib/screens/business_admin/to_management/create_to_screen.dart');
      expect(src.contains('AdminCreateTOScreen') || src.contains('CreateTO'),
          true);
      expect(_source('lib/models/core/to_model.dart').contains('class TOModel'),
          true);
    });
  });

  // ── §37 복귀 재조회 / §22 ───────────────────────────────────────
  group('FPR-4x 복귀·진입', () {
    late final String home =
        _source('lib/screens/business_admin/business_admin_home_screen.dart');

    test('FPR-40 홈 준비 CTA 복귀 시 자동 재조회', () {
      expect(home.contains('_reloadReadiness'), true);
      final i = home.indexOf('Future<void> _reloadReadiness() async {');
      expect(i, greaterThan(-1));
      final body = home.substring(i, i + 320);
      expect(body.contains('_loadApprovedBusinessStatus()'), true);
      expect(body.contains('_loadPostingReadiness()'), true);
    });

    test('FPR-41 사업장 0개에서도 readiness를 계산한다', () {
      // 이전에는 승인 사업장이 없으면 early return 해 카드가 아예 안 나왔다.
      final i = home.indexOf('Future<void> _loadPostingReadiness() async {');
      final body = home.substring(i, i + 600);
      expect(body.contains('if (approvedBizs.isEmpty) return;'), false,
          reason: '신규 관리자에게 준비 카드가 렌더되지 않는다');
    });

    test('FPR-42 인감 CTA가 설정의 해당 섹션으로 이동한다', () {
      expect(home.contains('SettingsTarget.seal'), true);
      final settings = _source('lib/screens/common/settings_screen.dart');
      expect(settings.contains('enum SettingsTarget'), true);
      expect(settings.contains('Scrollable.ensureVisible'), true);
      expect(settings.contains('KeyedSubtree(key: _sealKey'), true);
    });

    test('FPR-43 기존 SettingsScreen() 호출부가 깨지지 않는다', () {
      // initialTarget은 선택 인자여야 한다.
      final settings = _source('lib/screens/common/settings_screen.dart');
      expect(settings.contains('const SettingsScreen({super.key, this.initialTarget});'),
          true);
    });
  });

  // ── 범위 불변식 ─────────────────────────────────────────────────
  group('FPR-5x 범위 밖 불변식', () {
    late final String createTo = _source(
        'lib/screens/business_admin/to_management/create_to_screen.dart');

    test('FPR-50 CreateTO gate 구조·조건 무변경', () {
      expect(
          createTo.contains(
              '_businessApproved && _workTypesReady && _contractTemplatesReady &&'),
          true);
      expect(createTo.contains('_hasLicense && _hasSeal'), true);
      expect(createTo.contains('cardCount = isSubAdmin ? 4 : 5'), true);
      expect(createTo.contains('if (!_formUnlocked)'), true);
    });

    test('FPR-51 승인 복구 경로 무변경', () {
      expect(createTo.contains('BusinessPostingReadiness.recheckApproval'), true);
      // 홈에서 자동 호출을 추가하지 않았다
      final home = _source(
          'lib/screens/business_admin/business_admin_home_screen.dart');
      expect(home.contains('recheckApproval'), false,
          reason: '홈이 승인 복구를 자동 호출하면 무제한 재시도가 된다');
    });

    test('FPR-52 새 persisted onboarding 상태가 없다', () {
      for (final p in const [
        'lib/services/business_posting_readiness.dart',
        'lib/screens/business_admin/business_admin_home_screen.dart',
      ]) {
        final s = _source(p);
        for (final banned in const [
          'onboardingCompleted',
          'firstPostingReady',
          'setupStep',
        ]) {
          expect(s.contains(banned), false, reason: '$p 에 $banned 추가됨');
        }
      }
    });

    test('FPR-53 FP-02(조회 실패)를 UI로 덮지 않았다', () {
      // backend state semantics 문제는 별도 Phase — 여기서 숨기면 원인이 가려진다.
      final home = _source(
          'lib/screens/business_admin/business_admin_home_screen.dart');
      // [HOME-V2-08D.5] 표현이 행 → section notice로 옮겨졌다. 숨긴 것이 아니다.
      expect(home.contains("'일부 업무 상태를 확인하지 못했어요'"), true,
          reason: 'FP-02를 UI에서 지워버렸다');
    });

    test('FPR-54 SUB_ADMIN 준비 카드 비노출 유지', () {
      final home = _source(
          'lib/screens/business_admin/business_admin_home_screen.dart');
      expect(home.contains('currentUser?.isSubAdmin == true'), true);
    });
  });
}
