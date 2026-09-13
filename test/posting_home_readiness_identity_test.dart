// [POSTING-V2-02C.1] 홈 공고 등록 준비 — business identity 보존
//
// 02C READ에서 확인된 문제:
//   Home이 준비 상태를 두 개의 독립된 any()로 접었다.
//     businessReady  = any(isApproved && hasLicense)
//     workTypesReady = any(hasActiveWorkTypes)
//   같은 map을 훑지만 **같은 원소일 것**을 요구하지 않는다. 그래서
//     A: 승인 O / 등록증 O / 업무 0
//     B: 승인 O / 등록증 X / 업무 1
//   일 때 두 bool이 모두 true가 되고, 어느 사업장으로도 공고를 만들 수 없는데
//   준비 카드가 사라진다. 서버 gate(assertBusinessPostingReady)는 business
//   단위이므로 세 조건은 같은 사업장 안에서 성립해야 한다.
//
// 두 번째 문제: 준비 CTA가 결핍과 무관하게 `_businesses.first`로 이동했다.
// 세 번째 문제: SubAdmin 인감 면제가 CreateTO에만 있고 Home에는 없었다.
//
// 계산은 순수 단위 테스트로, 화면 배선은 소스로 검증한다
// (홈 화면은 Firebase 서비스를 필드로 즉시 보유해 widget 테스트가 불가능하다).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/services/business_posting_readiness.dart';

const _homePath =
    'lib/screens/business_admin/business_admin_home_screen.dart';
const _helperPath = 'lib/services/business_posting_readiness.dart';
const _createToPath =
    'lib/screens/business_admin/to_management/create_to_screen.dart';

String _source(String p) {
  final f = File(p);
  expect(f.existsSync(), true, reason: '$p 를 찾지 못함');
  return f.readAsStringSync();
}

/// 주석을 제외한 실제 코드만 본다 — 설명 주석에도 같은 식별자가 등장한다.
String _codeOf(String p) => _source(p)
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

/// 줄바꿈·들여쓰기를 지워 한 줄로 만든다 (포매팅에 의존하지 않기 위해).
String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

/// [start, end) 구간을 잘라낸다.
String _region(String src, String start, String end) {
  final a = src.indexOf(start);
  if (a < 0) throw StateError('구간 시작을 찾지 못함: $start');
  final b = src.indexOf(end, a);
  if (b < 0) throw StateError('구간 끝을 찾지 못함: $end');
  return src.substring(a, b);
}

BusinessPostingReadiness _br(
  String id, {
  bool approved = true,
  bool license = true,
  bool workTypes = true,
}) =>
    BusinessPostingReadiness(
      bizId: id,
      isApproved: approved,
      hasCanonicalLicense: license,
      hasOwnerLegacyLicense: false,
      hasActiveWorkTypes: workTypes,
    );

Map<String, BusinessPostingReadiness> _map(
  List<BusinessPostingReadiness> rs,
) =>
    {for (final r in rs) r.bizId: r};

// ── CTA 대상 선택 규칙 replica ──────────────────────────────────
// 화면 getter와 같은 우선순위. 소스가 이 순서를 유지하는지는 별도 테스트가 본다.

String? _firstWhere(
  List<String> order,
  Map<String, BusinessPostingReadiness> m,
  bool Function(BusinessPostingReadiness? r) test,
) {
  for (final id in order) {
    if (test(m[id])) return id;
  }
  return null;
}

String? _workTypeCta(
  List<String> order,
  Map<String, BusinessPostingReadiness> m,
) =>
    _firstWhere(
        order,
        m,
        (r) =>
            r != null &&
            r.isApproved &&
            r.hasLicense &&
            !r.hasActiveWorkTypes) ??
    _firstWhere(order, m,
        (r) => r != null && r.isApproved && !r.hasActiveWorkTypes) ??
    _firstWhere(order, m, (r) => r == null);

String? _businessCta(
  List<String> order,
  Map<String, BusinessPostingReadiness> m,
) =>
    _firstWhere(
        order, m, (r) => r == null || !r.isApproved || !r.hasLicense);

void main() {
  // ── §35 같은 사업장 불변식 ──────────────────────────────────────
  group('READINESS-01 같은 business가 모든 조건을 만족해야 한다', () {
    test('01-a hasReadyBusiness는 isReady 하나로 판정한다', () {
      final ready = _map([_br('A')]);
      expect(BusinessPostingReadiness.hasReadyBusiness(ready), true);
      expect(ready['A']!.isReady, true);
    });

    test('01-b HOME_READY → readinessMap에 실제 ready business가 있다', () {
      // 계약: workTypes task가 완료라면 반드시 isReady business가 존재한다.
      final splits = <Map<String, BusinessPostingReadiness>>[
        _map([_br('A', workTypes: false), _br('B', license: false)]),
        _map([_br('A', license: false), _br('B', approved: false)]),
        _map([_br('A', workTypes: false)]),
        _map([_br('A', license: false)]),
        <String, BusinessPostingReadiness>{},
      ];
      for (final m in splits) {
        expect(BusinessPostingReadiness.hasReadyBusiness(m),
            m.values.any((r) => r.isReady),
            reason: 'aggregate가 isReady와 어긋남');
      }
    });

    test('01-c 빈 map은 준비 완료가 아니다', () {
      expect(BusinessPostingReadiness.hasReadyBusiness({}), false);
    });

    test('01-d 조각 합성이 불가능하다 — 세 조건 중 하나라도 빠지면 false', () {
      expect(
          BusinessPostingReadiness.hasReadyBusiness(
              _map([_br('A', approved: false)])),
          false);
      expect(
          BusinessPostingReadiness.hasReadyBusiness(
              _map([_br('A', license: false)])),
          false);
      expect(
          BusinessPostingReadiness.hasReadyBusiness(
              _map([_br('A', workTypes: false)])),
          false);
    });
  });

  // ── §36 CASE A′ ────────────────────────────────────────────────
  group('READINESS-02 조각이 나뉜 사업장은 준비 완료가 아니다 (CASE A′)', () {
    // A: 등록증만 / B: 업무만
    final caseAPrime = _map([
      _br('A', workTypes: false),
      _br('B', license: false),
    ]);

    test('02-a 옛 계약(독립 any 2개)이면 준비 완료로 오판된다', () {
      // 이 줄이 바로 02C가 찾아낸 오판이다 — 회귀 방지용 기록.
      final oldBusinessReady =
          caseAPrime.values.any((r) => r.isApproved && r.hasLicense);
      final oldWorkTypesReady =
          caseAPrime.values.any((r) => r.hasActiveWorkTypes);
      expect(oldBusinessReady && oldWorkTypesReady, true);
    });

    test('02-b 새 계약에서는 NOT_READY', () {
      expect(BusinessPostingReadiness.hasReadyBusiness(caseAPrime), false);
    });

    test('02-c 사업장 task는 여전히 완료 — 업무 task만 미완료다', () {
      // §6: 사업장 task는 승인+등록증까지만 본다(A가 충족).
      expect(caseAPrime.values.any((r) => r.isApproved && r.hasLicense), true);
      // §7: 업무 task는 business identity를 요구한다.
      expect(BusinessPostingReadiness.hasReadyBusiness(caseAPrime), false);
    });

    test('02-d §22 업무가 있다는 이유로 전체가 가까워지지 않는다', () {
      // A: 승인 O / 등록증 X / 업무 1  — 등록증이 먼저다.
      final m = _map([_br('A', license: false)]);
      expect(m.values.any((r) => r.isApproved && r.hasLicense), false);
      expect(BusinessPostingReadiness.hasReadyBusiness(m), false);
    });
  });

  // ── §37 하나면 충분 ─────────────────────────────────────────────
  group('READINESS-03 준비된 사업장이 하나면 충분하다', () {
    test('03-a CASE B — A 완비 / B 미완비 → READY', () {
      final m = _map([
        _br('A'),
        _br('B', approved: false, license: false, workTypes: false),
      ]);
      expect(BusinessPostingReadiness.hasReadyBusiness(m), true);
    });

    test('03-b CASE C — inactive workType만 있는 A + 완비된 B → READY', () {
      // hasActiveWorkTypes는 isActive==true 기준이므로 A는 false.
      final m = _map([_br('A', workTypes: false), _br('B')]);
      expect(BusinessPostingReadiness.hasReadyBusiness(m), true);
    });

    test('03-c §15 다른 사업장이 미완비여도 카드를 유지하지 않는다', () {
      final m = _map([
        _br('A'),
        _br('B', license: false),
        _br('C', workTypes: false),
      ]);
      expect(BusinessPostingReadiness.hasReadyBusiness(m), true);
      final r = FirstPostingReadiness(
        hasAnyBusiness: true,
        businessReady: m.values.any((x) => x.isApproved && x.hasLicense),
        workTypesReady: BusinessPostingReadiness.hasReadyBusiness(m),
        contractTemplateReady: true,
        sealReady: true,
      );
      expect(r.allReady, true);
    });
  });

  // ── §41 inactive workType ──────────────────────────────────────
  test('READINESS-06 inactive workType만 있으면 hasActiveWorkTypes=false 유지', () {
    final code = _codeOf('lib/services/firestore_service.dart') +
        _codeOf('lib/services/business_posting_readiness.dart');
    expect(code.contains('hasActiveWorkTypes'), true);
    // helper는 getBusinessWorkTypes(isActive==true)만 신뢰한다 — 자체 필터 없음.
    final body = _region(_codeOf(_helperPath), 'bool hasActiveWorkTypes = false;',
        'return BusinessPostingReadiness(');
    expect(_flat(body).contains('getBusinessWorkTypes(biz.id)'), true);
    expect(body.contains('isActive'), false,
        reason: 'client가 isActive 판정을 따로 복제하면 서버와 갈라진다');
  });

  // ── §38 업무 CTA 대상 ───────────────────────────────────────────
  group('READINESS-04 업무 등록 CTA가 결핍 사업장을 가리킨다', () {
    test('04-a CASE A′ — 업무가 없는 A로 간다 (B 금지)', () {
      final order = ['A', 'B'];
      final m = _map([
        _br('A', workTypes: false), // 업무만 추가하면 공고 가능
        _br('B', license: false), // 업무는 있지만 등록증이 없다
      ]);
      expect(_workTypeCta(order, m), 'A');
    });

    test('04-b 목록 순서가 B, A여도 결핍 사업장 A를 고른다', () {
      final order = ['B', 'A'];
      final m = _map([
        _br('A', workTypes: false),
        _br('B', license: false),
      ]);
      expect(_workTypeCta(order, m), 'A',
          reason: '_businesses.first로 회귀함');
    });

    test('04-c 1순위가 여럿이면 기존 목록 순서의 첫 번째', () {
      final order = ['A', 'B'];
      final m = _map([
        _br('A', workTypes: false),
        _br('B', workTypes: false),
      ]);
      expect(_workTypeCta(order, m), 'A');
    });

    test('04-d 1순위가 없으면 승인+업무없음(2순위)', () {
      final order = ['A', 'B'];
      final m = _map([
        _br('A', license: false, workTypes: false),
        _br('B', license: false),
      ]);
      expect(_workTypeCta(order, m), 'A');
    });

    test('04-e 승인 전 사업장뿐이면 그 사업장으로 — 기존 병행 준비 계약 유지', () {
      // 미승인 사업장은 readinessMap에 없다(=null).
      final order = ['A'];
      expect(_workTypeCta(order, const {}), 'A');
    });

    test('04-f 이동할 대상이 없으면 null — 이동시키지 않는다', () {
      // 승인된 사업장 전부가 업무는 있고 등록증만 없는 경우.
      // 올바른 다음 행동은 업무가 아니라 사업자등록증이다(§22).
      final order = ['A', 'B'];
      final m = _map([
        _br('A', license: false),
        _br('B', license: false),
      ]);
      expect(_workTypeCta(order, m), isNull);
    });
  });

  // ── §14 사업장 CTA 대상 ─────────────────────────────────────────
  group('READINESS-07 사업장 CTA가 미완비 사업장을 가리킨다', () {
    test('07-a 승인됐지만 등록증이 없는 사업장을 고른다', () {
      final order = ['A', 'B'];
      final m = _map([_br('A'), _br('B', license: false)]);
      expect(_businessCta(order, m), 'B');
    });

    test('07-b 미승인 사업장을 고른다', () {
      final order = ['A', 'B'];
      final m = _map([_br('A')]); // B는 미승인이라 map에 없다
      expect(_businessCta(order, m), 'B');
    });

    test('07-c 전부 완비면 null — 완료 상태라 탭할 수 없다', () {
      final order = ['A', 'B'];
      final m = _map([_br('A'), _br('B')]);
      expect(_businessCta(order, m), isNull);
    });
  });

  // ── §39 _businesses.first 금지 ──────────────────────────────────
  group('READINESS-08 준비 CTA가 목록 첫 번째로 회귀하지 않는다', () {
    test('08-a navBizId/navBiz 단일 바인딩이 사라졌다', () {
      final code = _codeOf(_homePath);
      expect(code.contains('navBizId'), false);
      expect(
          code.contains(
              'final navBiz = _businesses.isNotEmpty ? _businesses.first : null;'),
          false);
    });

    test('08-b 준비 카드가 결핍 기반 target 3개를 쓴다', () {
      final card = _flat(_region(_codeOf(_homePath),
          'Widget _buildPostingSetupCard(', 'Future<void> _reloadReadiness()'));
      expect(card.contains('final bizTarget = _businessCtaBusiness;'), true);
      expect(card.contains('final wtTarget = _workTypeCtaBusiness;'), true);
      expect(card.contains('final tplTarget = _templateCtaBusiness;'), true);
      expect(card.contains('_businesses.first'), false,
          reason: '준비 카드가 여전히 목록 첫 번째로 이동함');
    });

    test('08-c 업무 CTA 우선순위가 소스에 그대로 있다', () {
      final code = _flat(_codeOf(_homePath));
      expect(
          code.contains(
              'BusinessModel? get _workTypeCtaBusiness => _firstBusinessWhere((r) => '
              'r != null && r.isApproved && r.hasLicense && !r.hasActiveWorkTypes) ?? '
              '_firstBusinessWhere( (r) => r != null && r.isApproved && !r.hasActiveWorkTypes) ?? '
              '_firstBusinessWhere((r) => r == null);'),
          true,
          reason: 'CTA 우선순위가 replica와 어긋남');
    });

    test('08-d 사업장 CTA 규칙이 소스에 그대로 있다', () {
      final code = _flat(_codeOf(_homePath));
      expect(
          code.contains('BusinessModel? get _businessCtaBusiness => '
              '_firstBusinessWhere((r) => r == null || !r.isApproved || !r.hasLicense);'),
          true);
    });

    test('08-e 대상이 없으면 화살표 대신 선행 필요로 남는다', () {
      final code = _flat(_codeOf(_homePath));
      expect(
          code.contains(
              'final actionable = r.isActionable(task) && (done || onTap != null);'),
          true);
    });
  });

  // ── §40 SubAdmin 인감 ───────────────────────────────────────────
  group('READINESS-05 SubAdmin 인감 면제가 CreateTO와 정렬됐다', () {
    test('05-a Home이 SubAdmin을 면제한다', () {
      final body = _flat(_region(_codeOf(_homePath),
          'Future<void> _loadPostingReadiness() async {', 'BusinessModel? _firstBusinessWhere('));
      expect(
          body.contains("final sealReady = up.currentUser?.isSubAdmin == true || "
              "(up.currentUser?.sealBase64?.isNotEmpty ?? false);"),
          true);
    });

    test('05-b CreateTO의 면제 계약은 그대로다', () {
      final c = _codeOf(_createToPath);
      expect(c.contains('isSubAdmin'), true);
      expect(c.contains('_hasSeal'), true);
    });

    test('05-c 인감 없는 SubAdmin + ready business → 전체 READY', () {
      final m = _map([_br('A')]);
      final r = FirstPostingReadiness(
        hasAnyBusiness: true,
        businessReady: true,
        workTypesReady: BusinessPostingReadiness.hasReadyBusiness(m),
        contractTemplateReady: true,
        sealReady: true, // SubAdmin 면제 결과
      );
      expect(r.allReady, true);
    });

    test('05-d 같은 조건의 BUSINESS_ADMIN은 인감 미완료', () {
      final m = _map([_br('A')]);
      final r = FirstPostingReadiness(
        hasAnyBusiness: true,
        businessReady: true,
        workTypesReady: BusinessPostingReadiness.hasReadyBusiness(m),
        contractTemplateReady: true,
        sealReady: false,
      );
      expect(r.isDone(FirstPostingTask.seal), false);
      expect(r.allReady, false);
      expect(r.completedCount, 3);
    });
  });

  // ── §42 새 read 없음 ────────────────────────────────────────────
  group('READINESS-09 추가 조회가 없다', () {
    test('09-a CTA 대상 선택은 순수 계산이다', () {
      final block = _codeOf(_homePath);
      final ctas = _region(block, 'BusinessModel? _firstBusinessWhere(',
          'Future<void> _safeNavigate(');
      for (final forbidden in [
        'await',
        'FirebaseFirestore',
        '_firestoreService',
        'httpsCallable',
        'FirebaseFunctions',
        '.get(',
      ]) {
        expect(ctas.contains(forbidden), false,
            reason: 'CTA 대상 선택에 $forbidden 이 들어감 — 추가 read');
      }
    });

    test('09-b readiness 로드의 조회 지점이 늘지 않았다', () {
      final body = _region(_codeOf(_homePath),
          'Future<void> _loadPostingReadiness() async {',
          'BusinessModel? _firstBusinessWhere(');
      expect('BusinessPostingReadiness.forBusinesses('.allMatches(body).length,
          1);
      expect('getTemplates('.allMatches(body).length, 1);
      expect(body.contains('httpsCallable'), false);
    });

    test('09-c hasReadyBusiness는 map 위의 동기 계산이다', () {
      final h = _flat(_codeOf(_helperPath));
      expect(
          h.contains('static bool hasReadyBusiness( '
              'Map<String, BusinessPostingReadiness> readinessMap, ) => '
              'readinessMap.values.any((r) => r.isReady);'),
          true);
    });
  });

  // ── 범위 밖 불변식 ──────────────────────────────────────────────
  group('READINESS-10 범위 밖 무변경', () {
    test('10-a canonical business rule 무변경', () {
      final h = _flat(_codeOf(_helperPath));
      expect(
          h.contains(
              'bool get isReady => isApproved && hasLicense && hasActiveWorkTypes;'),
          true);
      expect(
          h.contains(
              'bool get hasLicense => hasCanonicalLicense || hasOwnerLegacyLicense;'),
          true);
    });

    test('10-b 계약서 템플릿 aggregate semantics 무변경 (§23)', () {
      final code = _codeOf(_homePath);
      expect(code.contains('selectableForNewContract('), true);
      expect(_codeOf(_createToPath).contains('selectableForNewContract(allTemplates)'),
          true);
    });

    test('10-c CreateTO 무변경 (§27)', () {
      final c = _codeOf(_createToPath);
      expect(
          c.contains(
              '_businessApproved && _workTypesReady && _contractTemplatesReady &&'),
          true);
      expect(c.contains('BusinessPostingReadiness.hasReadyBusiness'), false,
          reason: 'shared helper refactor는 이번 Phase 금지');
    });

    test('10-d 서버 readiness guard 무변경 (§25)', () {
      final fns = _source('functions/src/index.ts');
      expect(fns.contains('async function assertBusinessPostingReady('), true);
      expect(fns.contains('assertWorkTypesInBusiness'), true);
    });

    test('10-e 카드 UI 계약 무변경 (§33)', () {
      final code = _codeOf(_homePath);
      expect(code.contains("'공고 등록 준비'"), true);
      expect(code.contains('/ \${FirstPostingReadiness.totalTasks} 완료'), true);
      expect(code.contains("'사업장 등록'"), true);
      expect(code.contains("'업무 등록'"), true);
      expect(code.contains("'계약서 템플릿'"), true);
      expect(code.contains("'인감/서명'"), true);
      expect(FirstPostingReadiness.totalTasks, 4);
      expect(FirstPostingTask.values.length, 4);
    });

    test('10-f readiness 실패 표면 무변경 (§29)', () {
      final code = _codeOf(_homePath);
      expect(code.contains('if (!_readinessLoaded) return const SizedBox.shrink();'),
          true);
      expect(code.contains('UNKNOWN'), false,
          reason: 'failure surface 추가는 이번 Phase 금지');
    });

    test('10-g settings-tab freshness 무변경 (§31)', () {
      final code = _codeOf(_homePath);
      // 준비 CTA 복귀 경로의 _reloadReadiness 계약만 유지, 새 invalidation 없음.
      expect(code.contains('_reloadReadiness()'), true);
      expect(code.contains('WorkforceController.dataRevision'), true);
    });
  });
}
