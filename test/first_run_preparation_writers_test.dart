// [R7-P4.4B] 준비 chain writer 감사 — CP7 / CP4 업무 / CP5 템플릿 / CP6 인감.
//
// ── 이번에 찾은 것 ─────────────────────────────────────────────────
//   템플릿은 `businesses/{id}/contract_templates` **서브컬렉션**이고 계약
//   발송도 그 사업장 것만 고르는데, readiness 판정만 **전 사업장 합산**이었다.
//   그래서 A 에만 템플릿이 있는데 B 로 공고를 낼 수 있었고, 지원자가
//   **확정된 뒤에** 고를 템플릿이 0개인 dead-end 를 만난다.
//
//   같은 파일의 기존 주석이 바로 그 상황을 경고하고 있었다 — legacy 분류
//   축(outsource)은 막았는데 사업장 축은 열려 있었다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/contract_template_model.dart';

String _src(String p) {
  final f = File(p);
  expect(f.existsSync(), isTrue, reason: '$p 를 찾지 못함');
  return f.readAsStringSync().replaceAll('\r\n', '\n');
}

const _home = 'lib/screens/business_admin/business_admin_home_screen.dart';
const _createTo =
    'lib/screens/business_admin/to_management/create_to_screen.dart';
const _tplService = 'lib/services/contract_template_service.dart';
const _bizFs = 'lib/services/firestore/business_firestore.dart';
const _settings = 'lib/screens/common/settings_screen.dart';
const _contractDialog =
    'lib/screens/business_admin/dialogs/day_applicants_dialog.dart';

void main() {
  // ══════════════════════════════════════════════════════════════
  // CP5-01. 템플릿은 사업장별이다
  // ══════════════════════════════════════════════════════════════
  group('CP5-01 템플릿 business scope', () {
    test('CP5-01a 저장 위치가 사업장 서브컬렉션이다 (전제)', () {
      final s = _src(_tplService);
      expect(s.contains(".collection('businesses')"), isTrue);
      expect(s.contains(".collection('contract_templates')"), isTrue);
      expect(s.contains('.doc(businessId)'), isTrue);
    });

    test('CP5-01b 계약 발송도 그 사업장 것만 고른다 (전제)', () {
      final s = _src(_contractDialog);
      expect(
          s.contains('ContractTemplateSelectorDialog.show(context, '
              'businessId: bizId)'),
          isTrue);
    });

    test('CP5-01c CreateTO 는 선택 사업장의 템플릿만 본다', () {
      final s = _src(_createTo);
      // 전 사업장 합산 변수가 사라졌다.
      expect(s.contains('final allTemplates ='), isFalse,
          reason: 'A 의 템플릿으로 B 공고를 열면 확정 뒤 dead-end 가 된다');
      expect(
          s.contains('selectableForNewContract(sel.templates)'), isTrue);
      expect(
          s.contains('selectableForNewContract(selectedTemplates)'), isTrue,
          reason: '사업장 드롭다운 전환 경로도 같은 기준이어야 한다');
    });

    test('CP5-01d 사업장 전환 시 템플릿을 다시 읽는다', () {
      final s = _src(_createTo);
      final i = s.indexOf('final results = await Future.wait([');
      expect(i, greaterThan(-1));
      final block = s.substring(i, i + 400);
      expect(block.contains('_contractTemplateService.getTemplates('
          '_selectedBusiness!.id)'), isTrue);
    });

    test('CP5-01e Home 도 사업장 단위로 본다', () {
      final s = _src(_home);
      // 무조건 합산(expand)으로 돌아가지 않는다.
      expect(s.contains('lists.expand((l) => l),'), isFalse);
      expect(s.contains('readinessMap[_businesses[i].id]?.isReady == true'),
          isTrue, reason: '공고 낼 수 있는 사업장이 있으면 그 사업장 기준');
    });

    test('CP5-01f 조회 실패를 "준비됨" 으로 올리지 않는다', () {
      final s = _src(_home);
      expect(s.contains('var hasTemplate = false;'), isTrue);
      final i = s.indexOf('var hasTemplate = false;');
      final block = s.substring(i, i + 1400);
      final ci = block.indexOf('} catch (e) {');
      expect(ci, greaterThan(-1));
      expect(block.substring(ci).contains('hasTemplate = true'), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // CP5-02. selectableForNewContract 의 실제 의미
  // ══════════════════════════════════════════════════════════════
  group('CP5-02 선택 가능 판정', () {
    test('CP5-02a 문서 하나 존재 != 신규 계약에 사용 가능', () {
      // legacy 분류(outsource)는 조회·편집만 되고 신규 선택은 안 된다.
      expect(ContractTemplateType.isSupportedForNewUse(
          ContractTemplateType.daily), isTrue);
      expect(ContractTemplateType.isSupportedForNewUse(
          ContractTemplateType.period), isTrue);
      expect(ContractTemplateType.isSupportedForNewUse(
          ContractTemplateType.outsource), isFalse);
      expect(ContractTemplateType.isSupportedForNewUse('무엇이든'), isFalse);
    });

    test('CP5-02b active·deleted·version 축은 이 모델에 없다', () {
      // 없는 개념을 있다고 보고하지 않기 위해 고정한다. 템플릿은 분류만으로
      // 신규 사용 가능 여부가 정해진다.
      final s = _src('lib/models/core/contract_template_model.dart');
      expect(s.contains('isSupportedForNewUse(String type)'), isTrue);
      for (final absent in const ['isDeleted', 'isArchived', 'version']) {
        expect(s.contains('final bool $absent'), isFalse, reason: absent);
        expect(s.contains('final int $absent'), isFalse, reason: absent);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // CP5-03. 템플릿 수정이 기존 계약을 소급 변경하지 않는다
  // ══════════════════════════════════════════════════════════════
  test('CP5-03 계약은 조항을 복사해 동결한다', () {
    // templateId 참조가 아니라 articles 사본이다. 템플릿을 고쳐도 이미
    // 발송·서명된 계약의 내용은 바뀌지 않는다.
    final s = _src('lib/models/core/employment_contract_model.dart');
    expect(s.contains('final List<ContractArticle> articles;'), isTrue);
    expect(s.contains("'articles': articles.map((a) => a.toMap()).toList()"),
        isTrue);
    expect(s.contains('final String templateId'), isFalse,
        reason: '참조로 들고 있으면 템플릿 수정이 과거 계약을 바꾼다');
  });

  // ══════════════════════════════════════════════════════════════
  // CP4-01. 업무 등록 writer
  // ══════════════════════════════════════════════════════════════
  group('CP4-01 업무 writer', () {
    late final String s;
    setUpAll(() => s = _src(_bizFs));

    test('CP4-01a 사업장 서브컬렉션에 쓴다', () {
      final i = s.indexOf('Future<String?> addBusinessWorkType(');
      final body = s.substring(i, i + 2600);
      expect(body.contains(".collection('businesses')"), isTrue);
      expect(body.contains(".collection('workTypes')"), isTrue);
      expect(body.contains('isActive: true'), isTrue);
      expect(body.contains("'createdAt': FieldValue.serverTimestamp()"), isTrue);
    });

    test('CP4-01b 같은 이름의 활성 업무를 두 개 만들지 않는다', () {
      // 서버가 업무를 **이름으로** 대조하고 공고·지원 snapshot 도 이름을
      // 저장하므로, 같은 이름 문서 둘은 downstream 에서 구별할 수 없다.
      final i = s.indexOf('Future<String?> addBusinessWorkType(');
      final body = s.substring(i, i + 2600);
      expect(body.contains("existingTypes\n          .any((w) => "
          "w.name.trim() == normalized)"), isTrue);
      expect(body.contains('throw StateError('), isTrue);
    });

    test('CP4-01c 중복은 "실패" 가 아니라 고칠 수 있는 입력 문제로 말한다', () {
      final i = s.indexOf('Future<String?> addBusinessWorkType(');
      final body = s.substring(i, i + 2800);
      expect(body.contains('같은 이름의 업무가 이미 있습니다'), isTrue);
      expect(body.contains('e is StateError'), isTrue);
    });

    test('CP4-01d 비활성 업무는 중복 대상이 아니다', () {
      // 서버 대조(`assertWorkTypesInBusiness`)도 active 만 본다.
      expect(
          s.contains("      .where('isActive', isEqualTo: true)"), isTrue);
    });

    test('CP4-01e 읽기 실패를 "업무 0개" 로 접지 않는다', () {
      final i = s.indexOf('Future<List<BusinessWorkTypeModel>> '
          'getBusinessWorkTypes(');
      final body = s.substring(i, i + 1400);
      expect(body.contains('rethrow;'), isTrue);
      expect(body.contains('return [];'), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // CP6-01. 인감/서명 artifact
  // ══════════════════════════════════════════════════════════════
  group('CP6-01 인감 artifact', () {
    late final String s;
    setUpAll(() => s = _src(_settings));

    test('CP6-01a authority 는 users/{uid}.sealBase64 하나다', () {
      // Home readiness 와 계약 생성이 **같은 필드**를 읽는지 본다.
      // 서로 다른 authority 면(예: users vs businesses.sealUrl) BLOCKER 다.
      expect(_src(_home).contains('up.currentUser?.sealBase64'), isTrue);
      final c = _src(_contractDialog);
      expect(c.contains(".collection('users').doc(sealUid).get()"), isTrue);
      expect(c.contains("sealDoc.data()?['sealBase64']"), isTrue);
      // businesses 문서에는 저장하지 않는다는 결정이 남아 있다.
      final b = _src('lib/models/core/business_model.dart');
      expect(b.contains('sealBase64는 users/{uid} 문서에만 저장한다'), isTrue);
    });

    test('CP6-01b P4.3B 의 cache-path 구조가 아니다', () {
      // 도장은 picker 를 쓰지만 **즉시 bytes 로 읽는다** — 파일 경로를
      // 화면 사이로 들고 다니지 않으므로 staging 이 필요 없다.
      final i = s.indexOf('Future<void> _registerSeal(');
      expect(i, greaterThan(-1));
      final body = s.substring(i, i + 1200);
      expect(body.contains('await picked.readAsBytes()'), isTrue);
      expect(body.contains('base64Encode(bytes)'), isTrue);
      expect(body.contains('File('), isFalse,
          reason: '파일 경로를 상태로 들고 있으면 저장 시점에 사라질 수 있다');
      // 서명은 캔버스 → bytes. 파일이 아예 없다.
      expect(s.contains("showSignaturePad(context, title: '사업주 서명')"), isTrue);
    });

    test('CP6-01c 저장 실패를 원인별로 말한다', () {
      expect(s.contains('String _sealErrorMessage(Object e) {'), isTrue);
      final i = s.indexOf('String _sealErrorMessage(Object e) {');
      final body = s.substring(i, i + 900);
      for (final code in const [
        'unauthenticated',
        'permission-denied',
        'invalid-argument',
        'unavailable',
      ]) {
        expect(body.contains("'$code'"), isTrue, reason: code);
      }
    });

    test('CP6-01d 세 경로 모두 로그를 남기고 같은 문구 규칙을 쓴다', () {
      for (final marker in const [
        "debugPrint('❌ 도장 등록 실패: \$e')",
        "debugPrint('❌ 사업주 서명 등록 실패: \$e')",
        "debugPrint('❌ 날인 삭제 실패: \$e')",
      ]) {
        expect(s.contains(marker), isTrue, reason: marker);
      }
      expect('_sealErrorMessage(e)'.allMatches(s).length,
          greaterThanOrEqualTo(3));
    });

    test('CP6-01e 계약 경로가 날인 없음을 복구 가능하게 말한다', () {
      final c = _src(_contractDialog);
      expect(c.contains("title: '사업주 날인 미등록'"), isTrue);
      expect(c.contains('사업주에게 날인 등록을 요청해주세요'), isTrue,
          reason: 'SubAdmin 은 자기가 등록할 수 없다');
      expect(c.contains("confirmText: up.isSubAdmin ? '확인' : '설정으로 이동'"),
          isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // CP7-01. 서버 authority — 아직 세 조건뿐이라는 사실을 고정
  // ══════════════════════════════════════════════════════════════
  test('CP7-01 서버 gate 가 다섯 축을 본다 — 잔여가 닫혔다', () {
    // [R7-P4.4C/C.1] 갱신. 이 셀은 P4.4B 시점의 사실("서버는 아직 셋만
    //   본다")을 기록했고, 마지막 두 줄에 "있으면 잔여가 닫힌 것이다" 라고
    //   적어 뒀다. P4.4C 가 템플릿·고용주 날인을 더했고 P4.4C.1 이 그 판정을
    //   transaction 안에서도 쓸 수 있는 evaluator 로 옮겼다.
    //   기대값을 새 사실로 옮긴다 — 셀을 지우지 않는다.
    final s = File('functions/src/index.ts').readAsStringSync();
    // 등록증(Storage 호출)만 gate 본문에 남았다.
    final gi = s.indexOf('async function assertBusinessPostingReady(');
    expect(gi, greaterThan(-1));
    final gate = s.substring(gi, s.indexOf('function postingNotReadyMessage(', gi));
    expect(gate.contains('hasValidBusinessLicense'), isTrue);
    expect(gate.contains('evaluatePostingReadinessFirestore('), isTrue);
    // 나머지 네 축은 evaluator 쪽.
    // [R7-P4.4C.2A] 축이 두 함수로 갈렸다 — 승인·템플릿·날인은
    //   evaluateContractCapability, 활성 업무는 evaluatePostingReadinessFirestore.
    //   후자가 전자를 호출하므로 두 본문을 합쳐 본다.
    final ei = s.indexOf('async function evaluateContractCapability(');
    expect(ei, greaterThan(-1));
    final ev = s.substring(ei, s.indexOf('interface PostingReadinessReader', ei));
    expect(ev.contains('isApproved'), isTrue);
    expect(ev.contains('collection("workTypes")'), isTrue);
    expect(ev.contains('contract_templates'), isTrue);
    expect(ev.contains('sealBase64'), isTrue);
  });
}
