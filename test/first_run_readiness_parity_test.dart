// [R7-P4.4 CHECKPOINT 7] Home 준비 4칸 == CreateTO 실제 gate 인가.
//
// ── 왜 보는가 ───────────────────────────────────────────────────────
//   Home 이 "공고 등록까지 N단계" 라고 말하는데 CreateTO 가 다른 조건으로
//   막으면, 신규 관리자는 준비를 다 끝냈다고 믿고 막히거나(너무 관대),
//   끝냈는데도 못 낸다고 믿는다(너무 엄격).
//
// ── 이번에 찾은 것 ─────────────────────────────────────────────────
//   네 predicate 는 같았다. 대신 **승인 전 표시**가 문제였다:
//   `workTypesReady` 는 승인된 사업장만 담은 readinessMap 에서 나오므로,
//   미승인 사업장에 업무를 등록해도 '업무 등록' 칸이 완료로 바뀌지 않는다.
//   그런데 그 이유를 아무 데서도 말하지 않았다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/services/business_posting_readiness.dart';

String _src(String p) {
  final f = File(p);
  expect(f.existsSync(), isTrue, reason: '$p 를 찾지 못함');
  return f.readAsStringSync().replaceAll('\r\n', '\n');
}

const _home = 'lib/screens/business_admin/business_admin_home_screen.dart';
const _createTo = 'lib/screens/business_admin/to_management/create_to_screen.dart';
const _server = 'functions/src/index.ts';

String _serverSrc() {
  // 큰 파일이라 필요한 함수 주변만 잘라 쓴다.
  final s = File(_server).readAsStringSync().replaceAll('\r\n', '\n');
  final i = s.indexOf('async function assertBusinessPostingReady(');
  expect(i, greaterThan(-1));
  return s.substring(i, i + 1400);
}

void main() {
  // ══════════════════════════════════════════════════════════════
  // CP7-01. 네 항목이 같은 사실을 쓰는가
  // ══════════════════════════════════════════════════════════════
  group('CP7-01 Home ↔ CreateTO parity', () {
    late final String home;
    late final String create;
    setUpAll(() {
      home = _src(_home);
      create = _src(_createTo);
    });

    test('CP7-01a 사업장 — 양쪽 다 승인 + 등록증을 요구한다', () {
      expect(
          home.contains(
              'readinessMap.values.any((r) => r.isApproved && r.hasLicense)'),
          isTrue);
      expect(create.contains('_businessApproved && _workTypesReady'), isTrue);
      expect(create.contains('_hasLicense && _hasSeal'), isTrue);
    });

    test('CP7-01b 계약서 템플릿 — 같은 함수를 쓴다', () {
      // "템플릿이 있다" 가 아니라 "신규 계약에 **고를 수 있는** 템플릿이
      // 있다" 여야 한다. 두 화면이 다른 술어를 쓰면 CreateTO 에서 고를
      // 것이 0개인 dead-end 가 생긴다.
      // [R7-P4.4B] 줄바꿈에 걸리지 않게 두 토큰으로 본다 — 어느 쪽이 줄을
      //   어떻게 접든 **같은 함수를 쓴다**는 사실만 고정한다.
      for (final s in [home, create]) {
        expect(s.contains('ContractTemplateModel'), isTrue);
        expect(s.contains('selectableForNewContract('), isTrue);
      }
      // [R7-P4.4B TPL-01] 그리고 양쪽 다 **사업장별**로 넘긴다.
      expect(create.contains('selectableForNewContract(sel.templates)'), isTrue);
      expect(home.contains('selectableForNewContract(lists[i])'), isTrue);
    });

    test('CP7-01c 인감 — 양쪽 다 그 사업장 owner 날인을 본다', () {
      // [R7-P4.4C SEAL-02] 갱신. 이 셀은 "양쪽 다 SubAdmin 을 면제한다" 를
      //   고정했다 — P4.4 시점에는 두 화면이 **같은 규칙**을 쓰는지가 관심
      //   이었고 그 답은 맞았다. P4.4C 에서 그 규칙 자체가 틀렸다는 반례를
      //   찾았다: SubAdmin 면제는 개인 날인을 요구하지 않는다는 뜻이어야
      //   하는데, 구현은 **고용주 날인 존재 여부 자체를 무시**했다.
      //   그 상태로 공고가 열리면 확정 뒤 계약을 만들 수 없다.
      //   parity 요구는 그대로다 — 양쪽이 이제 같은 canonical(owner 날인)을 쓴다.
      expect(home.contains("up.currentUser?.isSubAdmin == true ||"), isFalse);
      expect(home.contains('readinessMap.values.any((r) => r.hasEmployerSeal)'),
          isTrue);
      expect(create.contains('_hasSeal = sel.employerSeal;'), isTrue);
      expect(create.contains('_hasSeal = up.isSubAdmin'), isFalse);
    });

    test('CP7-01d 업무 — 사업장 identity 를 유지한다', () {
      // A(등록증만) + B(업무만) 를 합쳐 준비 완료로 보면, 어느 사업장으로도
      // 공고를 낼 수 없는데 READY 가 된다.
      expect(
          home.contains(
              'BusinessPostingReadiness.hasReadyBusiness(readinessMap)'),
          isTrue);
    });

    test('CP7-01e 네 칸이 곧 CreateTO 의 다섯 조건이다', () {
      // Home 의 '사업장' 한 칸이 CreateTO 의 승인 + 등록증 두 조건을 덮는다.
      expect(BusinessPostingReadiness(
        bizId: 'b',
        isApproved: true,
        hasCanonicalLicense: true,
        hasOwnerLegacyLicense: false,
        hasActiveWorkTypes: true,
      ).isReady, isTrue);
      // 하나라도 빠지면 아니다.
      for (final r in [
        const BusinessPostingReadiness(
            bizId: 'b',
            isApproved: false,
            hasCanonicalLicense: true,
            hasOwnerLegacyLicense: false,
            hasActiveWorkTypes: true),
        const BusinessPostingReadiness(
            bizId: 'b',
            isApproved: true,
            hasCanonicalLicense: false,
            hasOwnerLegacyLicense: false,
            hasActiveWorkTypes: true),
        const BusinessPostingReadiness(
            bizId: 'b',
            isApproved: true,
            hasCanonicalLicense: true,
            hasOwnerLegacyLicense: false,
            hasActiveWorkTypes: false),
      ]) {
        expect(r.isReady, isFalse);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // CP7-02. 서버가 최종 gate — 클라이언트가 더 관대하지 않다
  // ══════════════════════════════════════════════════════════════
  group('CP7-02 서버 gate', () {
    test('CP7-02a 서버가 다섯 축을 본다', () {
      // [R7-P4.4C/C.1] 갱신. P4.4 시점에는 셋이었고 그것이 사실이었다.
      //   P4.4C 가 템플릿·고용주 날인을 더했고, P4.4C.1 이 네 축을
      //   transaction 안에서도 쓸 수 있는 evaluator 로 옮겼다.
      final s = File(_server).readAsStringSync();
      final gi = s.indexOf('async function assertBusinessPostingReady(');
      final gate =
          s.substring(gi, s.indexOf('function postingNotReadyMessage(', gi));
      expect(gate.contains('hasValidBusinessLicense(bizId, bizData)'), isTrue);
      // [R7-P4.4C.2A] 축이 두 함수로 갈렸다 — 두 본문을 합쳐 본다.
      final ei = s.indexOf('async function evaluateContractCapability(');
      final ev =
          s.substring(ei, s.indexOf('interface PostingReadinessReader', ei));
      expect(ev.contains('if (!bizData?.isApproved)'), isTrue);
      expect(ev.contains('.where("isActive", "==", true)'), isTrue);
      expect(ev.contains('contract_templates'), isTrue);
      expect(ev.contains('sealBase64'), isTrue);
    });

    test('CP7-02b 클라이언트가 서버보다 관대하지 않다', () {
      // 서버 3조건 ⊂ 클라이언트 5조건. 클라이언트는 여기에 템플릿·인감을
      // 더 요구한다 — 그것이 없으면 계약 단계에서 막히기 때문이다.
      // 반대 방향(클라이언트가 더 느슨)이면 "등록 가능" 이라 해 놓고 서버가
      // 거절하게 된다.
      final create = _src(_createTo);
      for (final cond in const [
        '_businessApproved',
        '_hasLicense',
        '_workTypesReady',
        '_contractTemplatesReady',
        '_hasSeal',
      ]) {
        expect(create.contains(cond), isTrue, reason: cond);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // CP7-03. 승인 전 표시 — 이번에 고친 것
  // ══════════════════════════════════════════════════════════════
  group('CP7-03 승인 대기 중 체크리스트', () {
    late final String home;
    setUpAll(() => home = _src(_home));

    test('CP7-03a readiness 는 승인된 사업장만 조회한다 (전제)', () {
      expect(
          home.contains(
              'final approvedBizs = _businesses.where((b) => b.isApproved)'),
          isTrue,
          reason: '이 사실 때문에 승인 전에는 업무 칸이 완료로 바뀌지 않는다');
    });

    test('CP7-03b 사업장 칸은 승인 진행 중이라고 말한다', () {
      expect(
          home.contains(
              "pendingHint: r.hasAnyBusiness && !r.businessReady ? '승인 진행 중' : null"),
          isTrue);
    });

    test('CP7-03c 업무 칸도 막힌 이유를 말한다', () {
      // 예전에는 pendingHint 가 null 이라, 업무를 등록하고 돌아와도 같은
      // 줄이 이유 없이 미완료로 남아 있었다.
      final i = home.indexOf("label: '업무 등록',");
      expect(i, greaterThan(-1));
      final next = home.indexOf("label: '계약서 템플릿',", i);
      expect(next, greaterThan(i));
      final block = home.substring(i, next);
      expect(block.contains("'사업장 승인 후 반영돼요'"), isTrue);
      expect(block.contains('r.hasAnyBusiness && !r.businessReady'), isTrue);
      // 못 읽었을 때의 문장은 그대로 우선한다.
      expect(block.contains("'상태를 확인하지 못했어요'"), isTrue);
    });

    test('CP7-03d 승인과 무관한 두 칸은 건드리지 않았다', () {
      // 계약서 템플릿은 `_businesses` 전체에서 계산하고, 인감은 users 값이라
      // 둘 다 승인 전에도 완료될 수 있다. 여기에 승인 문구를 붙이면 거짓이다.
      final t = home.indexOf("label: '계약서 템플릿',");
      final s = home.indexOf("label: '인감/서명',");
      expect(t, greaterThan(-1));
      if (s > t) {
        final block = home.substring(t, s);
        expect(block.contains("'사업장 승인 후 반영돼요'"), isFalse);
      }
      // 템플릿은 승인 사업장이 아니라 전체 사업장에서 계산한다.
      expect(
          home.contains('_businesses.map((b) => _reads.contractTemplates(b.id))'),
          isTrue);
    });

    test('CP7-03e 완료로 올려서 해결하지 않았다', () {
      // 표시가 불편하다고 workTypesReady 를 미승인 사업장까지 넓히면,
      // 공고를 낼 수 없는 상태가 "준비 완료" 가 된다.
      expect(
          home.contains(
              'workTypesReady: BusinessPostingReadiness.hasReadyBusiness(readinessMap)'),
          isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // CP0-01. 회원가입이 남기는 것 (DEV 실측과 대조)
  // ══════════════════════════════════════════════════════════════
  group('CP0-01 BUSINESS_ADMIN 가입', () {
    test('CP0-01a 가입은 사업자등록번호를 받지 않는다', () {
      // DEV 실측: BUSINESS_ADMIN 1건, businessNumber=null.
      // 가입 화면이 signUp 에 businessNumber 를 넘기지 않는다는 사실을
      // 고정한다 — 아래 CP0-01b 의 전제다.
      final reg = _src('lib/screens/auth/register_screen.dart');
      final i = reg.indexOf('await userProvider.signUp(');
      expect(i, greaterThan(-1));
      final block = reg.substring(i, reg.indexOf(');', i));
      expect(block.contains('businessNumber:'), isFalse);
    });

    test('CP0-01b 그래서 users 기준 중복 체크는 지금 대상이 없다', () {
      // CF 는 users.businessNumber 로 조회한다. 가입이 그 필드를 쓰지 않으므로
      // 신규 계정에서는 항상 빈 결과다 — 이 사실을 residual 로 들고 간다.
      // (이번 Phase 에서 고치지 않는다. 사업자번호 authority 는 사업장
      //  생성 writer 쪽 결정이 먼저다.)
      final fns = File('functions/src/index.ts').readAsStringSync();
      final i = fns.indexOf('export const callableCheckBusinessNumberDuplicate');
      expect(i, greaterThan(-1));
      final block = fns.substring(i, i + 900);
      expect(block.contains('.collection("users")'), isTrue);
      expect(block.contains('.where("businessNumber", "==", clean)'), isTrue);
      expect(block.contains('.where("role", "==", "BUSINESS_ADMIN")'), isTrue);
    });
  });
}
