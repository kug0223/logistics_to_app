// [R7-P4.4C] 공고 server authority + canonical signer binding.
//
// ── 확정된 제품 정책 (재논의 대상 아님) ─────────────────────────────
//   지원 = 관심 / 확정 = 약속.
//   그래서 확정 **이후에** 관리자에게 계약 준비를 다시 요구하고 근로자를
//   계약 대기로 세워 두지 않는다. 계약서 템플릿과 사업주 날인은 공고가
//   근로자에게 **보이기 전에** 갖춰져 있어야 한다.
//
// ── 이번에 찾은 것 ─────────────────────────────────────────────────
//   ① 서버 gate 가 승인·등록증·업무 셋만 봤다 — 템플릿·날인 없이도 공고가
//      만들어질 수 있었다(stale/변조 클라이언트가 그 경로를 쓴다).
//   ② **예약 공개 scheduler 가 gate 를 부르지 않았다.** 만들 때는 준비돼
//      있었어도 그 사이 템플릿·날인이 지워지면, scheduler 가 그대로 공개해
//      "확정해도 계약을 만들 수 없는 공고" 가 근로자에게 열린다.
//   ③ 계약 날인이 `isSubAdmin ? owner : caller` 였다 — owner 가 아닌
//      co-admin 이 발송하면 그 사람 **개인 날인**이 고용주 자리에 찍힌다.
//   ④ 클라이언트 readiness 가 **호출자 자신의** 날인을 봤고 SubAdmin 은
//      무조건 면제였다 — 고용주 날인이 없는 사업장도 준비 완료가 됐다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/services/business_posting_readiness.dart';
import 'package:ALfit/utils/posting_readiness_reason.dart';

String _src(String p) {
  final f = File(p);
  expect(f.existsSync(), isTrue, reason: '$p 를 찾지 못함');
  return f.readAsStringSync().replaceAll('\r\n', '\n');
}

String _fns() => File('functions/src/index.ts').readAsStringSync();

/// [R7-P4.4C.1] gate 판정은 **두 조각**으로 나뉘었다 — 등록증(Storage 호출)은
/// `assertBusinessPostingReady` 에, 나머지 네 축은 transaction 안에서도 쓸 수
/// 있는 `evaluatePostingReadinessFirestore` 에. 그래서 검사 창도 둘이다.
String _gateBody() {
  final s = _fns();
  final i = s.indexOf('async function assertBusinessPostingReady(');
  expect(i, greaterThan(-1));
  final end = s.indexOf('function postingNotReadyMessage(', i);
  expect(end, greaterThan(i));
  return s.substring(i, end);
}

/// [R7-P4.4C.2A] Firestore 축 evaluator 본문.
///
///   P4.4C.2A 에서 축이 두 함수로 갈렸다 — 승인·템플릿·날인은
///   `evaluateContractCapability`(계약을 만들 수 있는가), 활성 업무는
///   `evaluatePostingReadinessFirestore`(공고를 새로 낼 수 있는가).
///   둘 다 합쳐 본다 — 이 파일이 검증하는 것은 "gate 가 다섯 축을 본다" 다.
String _evalBody() {
  final s = _fns();
  final ci = s.indexOf('async function evaluateContractCapability(');
  expect(ci, greaterThan(-1));
  final pi = s.indexOf('async function evaluatePostingReadinessFirestore(');
  expect(pi, greaterThan(ci));
  final end = s.indexOf('interface PostingReadinessReader', pi);
  expect(end, greaterThan(pi));
  return s.substring(ci, end);
}

/// 이유 코드 → 문장 map 본문.
String _msgBody() {
  final s = _fns();
  final i = s.indexOf('function postingNotReadyMessage(');
  expect(i, greaterThan(-1));
  return s.substring(i, i + 900);
}

const _createTo =
    'lib/screens/business_admin/to_management/create_to_screen.dart';
const _home = 'lib/screens/business_admin/business_admin_home_screen.dart';
// [R7-P4.4E.2A] Home 의 준비 판정은 **화면 밖**으로 옮겨졌다.
//   Home 을 한 번도 그리지 않고 공고 탭으로 바로 들어가면 아무도 답을
//   갖고 있지 않았기 때문이다. Home 은 여전히 setup UX 의 owner 이고,
//   판정은 그 resolver 에 **위임**한다. 그래서 '홈의 판정' 을 볼 때는
//   두 파일을 같이 본다 — 규칙이 어느 파일에 있느냐가 아니라 **무엇을
//   보느냐**가 계약이다.
const _readinessResolver = 'lib/services/business_posting_readiness.dart';
const _readiness = 'lib/services/business_posting_readiness.dart';

void main() {
  // ══════════════════════════════════════════════════════════════
  // AUTH-01. 서버 gate 가 다섯 축을 본다
  // ══════════════════════════════════════════════════════════════
  group('AUTH-01 server gate 5축', () {
    late final String body;
    late final String ev;
    setUpAll(() { body = _gateBody(); ev = _evalBody(); });

    test('AUTH-01a 다섯 축이 두 조각으로 나뉘어 있다', () {
      // [R7-P4.4C.1] 갱신. 등록증만 `assertBusinessPostingReady` 에 남고
      //   나머지 네 축은 `evaluatePostingReadinessFirestore` 로 옮겼다 —
      //   그래야 scheduler transaction 의 read-set 에 넣을 수 있다.
      //   규칙(다섯 축 전부 강제)은 그대로다.
      expect(body.contains('hasValidBusinessLicense(bizId, bizData)'), isTrue,
          reason: '등록증은 Storage 호출이라 transaction 밖');
      expect(body.contains('evaluatePostingReadinessFirestore('), isTrue);
      expect(body.contains('dbReadinessReader'), isTrue);
      // 네 축은 evaluator 쪽에 있다.
      expect(ev.contains("if (!bizData?.isApproved)"), isTrue);
      expect(ev.contains('.collection("workTypes")'), isTrue);
      expect(ev.contains('.where("isActive", "==", true)'), isTrue);
    });

    test('AUTH-01b 계약서 템플릿 — 이 사업장의 서브컬렉션을 본다', () {
      expect(ev.contains('.collection("contract_templates")'), isTrue);
      // 사업장 단위여야 한다 — 전역 조회면 A 의 템플릿으로 B 가 통과한다.
      expect(ev.contains('.collection("businesses").doc(bizId)'), isTrue);
    });

    test('AUTH-01c 템플릿 후보는 Flutter 와 같은 화이트리스트다', () {
      // `isSupportedForNewUse` = daily | period. legacy outsource 만 가진
      // 사업장을 통과시키면 계약 단계에서 고를 것이 0개다.
      expect(
          ev.contains('.where("templateType", "in", ["daily", "period"])'),
          isTrue);
    });

    test('AUTH-01d 고용주 날인 — caller 가 아니라 owner 것을 본다', () {
      expect(ev.contains('bizData?.ownerId'), isTrue);
      expect(ev.contains('.collection("users").doc(ownerId)'), isTrue);
      expect(ev.contains('sealBase64'), isTrue);
      // caller 의 날인을 보지 않는다.
      expect(ev.contains('request.auth'), isFalse);
      expect(ev.contains('callerUid'), isFalse);
    });

    test('AUTH-01e ownerId 를 모르면 통과시키지 않는다', () {
      expect(ev.contains('if (!ownerId) return "NO_EMPLOYER_SEAL";'), isTrue);
      // 승인 축도 계약 능력 쪽으로 옮겨졌다.
      expect(ev.contains('BUSINESS_NOT_APPROVED'), isTrue);
    });

    test('AUTH-01f 다섯 축 모두 domain reason 을 실어 보낸다', () {
      // 코드는 evaluator 가 돌려주고, 문장은 map 이 붙인다.
      final msg = _msgBody();
      for (final code in const [
        'BUSINESS_NOT_APPROVED',
        'NO_ACTIVE_WORK_TYPE',
        'NO_CONTRACT_TEMPLATE',
        'NO_EMPLOYER_SEAL',
      ]) {
        expect(ev.contains(code), isTrue, reason: code);
        expect(msg.contains(code), isTrue, reason: '$code 문장');
      }
      // 등록증은 gate 쪽에서 직접 던진다.
      expect(body.contains('POSTING_NOT_READY:BUSINESS_LICENSE_NOT_READY'),
          isTrue);
      expect(msg.contains('BUSINESS_LICENSE_NOT_READY'), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // AUTH-02. worker-visible 로 만드는 모든 writer 가 gate 를 지난다
  // ══════════════════════════════════════════════════════════════
  group('AUTH-02 transition 별 gate', () {
    late final String s;
    setUpAll(() => s = _fns());

    test('AUTH-02a CreateTO', () {
      final i = s.indexOf('export const callableCreateTO');
      final end = s.indexOf('export const', i + 10);
      final body = s.substring(i, end);
      expect(body.contains('await assertBusinessPostingReady('), isTrue);
      // immediate 만 바로 공개다 — 나머지는 비공개로 만들어진다.
      expect(body.contains('finalData.isPublished = true;'), isTrue);
      expect(body.contains('finalData.status = "DRAFT";'), isTrue);
    });

    test('AUTH-02b PublishTO — 공개 시점에 다시 본다', () {
      final i = s.indexOf('export const callablePublishTO');
      final end = s.indexOf('export const', i + 10);
      final body = s.substring(i, end);
      expect(body.contains('await assertBusinessPostingReady('), isTrue);
    });

    test('AUTH-02c UpdateTO — 재공개 transition 에서만 본다', () {
      // 제목·설명 수정까지 막지 않는다.
      final i = s.indexOf('export const callableUpdateTO');
      final end = s.indexOf('export const', i + 10);
      final body = s.substring(i, end);
      final reopen = body.indexOf('if (wantsReopen) {');
      expect(reopen, greaterThan(-1));
      final gate = body.indexOf('await assertBusinessPostingReady(', reopen);
      expect(gate, greaterThan(reopen),
          reason: 'gate 가 reopen 분기 안에 있어야 한다');
    });

    test('AUTH-02d 예약 공개 scheduler 도 readiness 를 지난다', () {
      // [R7-P4.4C.1] 갱신. P4.4C 는 transaction **밖에서** 확인했고 이 셀이
      //   그 모양을 고정했다. 그러면 확인과 commit 사이에 창이 남아
      //   TOCTOU 가 된다 — P4.4C.1 이 판정을 transaction **안으로** 옮겼다.
      //   read-set·per-business fail closed·blocked 기록의 세부는
      //   `scheduled_publish_atomicity_test` 가 본다. 여기서는 "예약 경로도
      //   gate 를 지난다" 는 사실만 고정한다.
      final i = s.indexOf('async function processScheduledPublish(');
      expect(i, greaterThan(-1));
      final end = s.indexOf('\nasync function ', i + 10);
      final body = s.substring(i, end);
      expect(body.contains('evaluatePostingReadinessFirestore('), isTrue);
      expect(body.contains('txReadinessReader(tx)'), isTrue);
      expect(body.contains('hasValidBusinessLicense('), isTrue,
          reason: 'Storage 축은 transaction 밖에서라도 반드시 본다');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // SIGNER-01. 계약 날인 = 그 사업장 owner
  // ══════════════════════════════════════════════════════════════
  group('SIGNER-01 canonical signer', () {
    test('SIGNER-01a 세 발송 경로 모두 owner 날인을 쓴다', () {
      for (final p in const [
        'lib/screens/business_admin/dialogs/day_applicants_dialog.dart',
        'lib/screens/business_admin/dialogs/work_applicants_dialog.dart',
      ]) {
        final s = _src(p);
        expect(s.contains('final sealUid = business.ownerId;'), isTrue,
            reason: p);
        // 예전 규칙이 남아 있으면 co-admin 개인 날인이 다시 샌다.
        expect(s.contains("up.isSubAdmin ? business.ownerId"), isFalse,
            reason: p);
      }
      final day = _src(
          'lib/screens/business_admin/dialogs/day_applicants_dialog.dart');
      expect('final sealUid = business.ownerId;'.allMatches(day).length, 2);
    });

    test('SIGNER-01b 날인이 없으면 발송하지 않고 복구 경로를 준다', () {
      final s = _src(
          'lib/screens/business_admin/dialogs/day_applicants_dialog.dart');
      expect(s.contains("title: '사업주 날인 미등록'"), isTrue);
      expect(s.contains('사업주에게 날인 등록을 요청해주세요'), isTrue,
          reason: 'SubAdmin 은 자기가 등록할 수 없다');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // SEAL-01. actor seal != employer seal readiness
  // ══════════════════════════════════════════════════════════════
  group('SEAL-01 readiness 는 고용주 날인을 본다', () {
    test('SEAL-01a canonical helper 가 사업장별로 들고 있다', () {
      final s = _src(_readiness);
      expect(s.contains('final bool hasEmployerSeal;'), isTrue);
      expect(s.contains('final bool employerSealUnknown;'), isTrue);
      expect(s.contains(".collection('users')\n            .doc(ownerId)"),
          isTrue, reason: 'caller uid 가 아니라 ownerId 로 읽는다');
    });

    test('SEAL-01b 못 읽은 것을 "날인 없음" 으로 단정하지 않는다', () {
      const r = BusinessPostingReadiness(
        bizId: 'b',
        isApproved: true,
        hasCanonicalLicense: true,
        hasOwnerLegacyLicense: false,
        hasActiveWorkTypes: true,
        employerSealUnknown: true,
      );
      expect(r.hasEmployerSeal, isFalse);
      expect(r.isMissingEmployerSeal, isFalse,
          reason: '모르는 동안 "등록하세요" 라고 단정하지 않는다');
    });

    test('SEAL-01c isReady 는 사업장 축만 — 잘못된 귀인을 만들지 않는다', () {
      // 날인이 없다고 '업무 등록' 칸이 미완료로 보이면 안 된다.
      const r = BusinessPostingReadiness(
        bizId: 'b',
        isApproved: true,
        hasCanonicalLicense: true,
        hasOwnerLegacyLicense: false,
        hasActiveWorkTypes: true,
        hasEmployerSeal: false,
      );
      expect(r.isReady, isTrue, reason: '사업장 축은 갖춰졌다');
      expect(r.hasEmployerSeal, isFalse, reason: '날인 축은 별도로 말한다');
    });

    test('SEAL-01d Home 은 SubAdmin 을 무조건 면제하지 않는다', () {
      final s = _src(_home) + _src(_readinessResolver);
      expect(s.contains("up.currentUser?.isSubAdmin == true ||"), isFalse,
          reason: '면제하면 고용주 날인 없는 사업장이 준비 완료가 된다');
      expect(
          s.contains('readinessMap.values.any((r) => r.hasEmployerSeal)'),
          isTrue);
      // 사업장이 아직 없으면 호출자를 예비 owner 로 본다.
      expect(s.contains('readinessMap.isEmpty'), isTrue);
    });

    test('SEAL-01e CreateTO 도 선택 사업장 owner 날인을 본다', () {
      final s = _src(_createTo);
      expect(s.contains('_hasSeal = sel.employerSeal;'), isTrue);
      expect(s.contains('_hasSeal = employerSeal;'), isTrue,
          reason: '사업장 전환 경로도 같은 기준');
      expect(s.contains('_hasSeal = up.isSubAdmin'), isFalse);
      expect(s.contains('employerSeal: employerSeal,'), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // ERR-01. 거부 이유 → 준비 단계
  // ══════════════════════════════════════════════════════════════
  group('ERR-01 domain reason 매핑', () {
    test('ERR-01a 다섯 코드가 각각 다른 준비 단계로 간다', () {
      final map = {
        'BUSINESS_NOT_APPROVED': FirstPostingTask.business,
        'BUSINESS_LICENSE_NOT_READY': FirstPostingTask.business,
        'NO_ACTIVE_WORK_TYPE': FirstPostingTask.workType,
        'NO_CONTRACT_TEMPLATE': FirstPostingTask.contractTemplate,
        'NO_EMPLOYER_SEAL': FirstPostingTask.seal,
      };
      map.forEach((code, task) {
        final r = PostingNotReady.parse(
            Exception('[firebase_functions/failed-precondition] '
                'POSTING_NOT_READY:$code 어쩌구 저쩌구'));
        expect(r, isNotNull, reason: code);
        expect(r!.task, task, reason: code);
        expect(r.message.isNotEmpty, isTrue);
      });
    });

    test('ERR-01b 모르는 코드는 null — 단계를 단정하지 않는다', () {
      expect(PostingNotReady.parse(Exception('POSTING_NOT_READY:WHAT_IS_THIS x')),
          isNull);
      expect(PostingNotReady.parse(Exception('MAX_ACTIVE_TO_LIMIT:4')), isNull);
      expect(PostingNotReady.parse(Exception('그냥 실패')), isNull);
    });

    test('ERR-01c 사용자 문구에 서버 접두어가 새지 않는다', () {
      for (final reason in PostingNotReadyReason.values) {
        final m = PostingNotReady(reason).message;
        expect(m.contains('POSTING_NOT_READY'), isFalse, reason: '$reason');
        expect(m.contains('failed-precondition'), isFalse, reason: '$reason');
      }
    });

    test('ERR-01d 화면이 서버 메시지를 그대로 띄우지 않는다', () {
      for (final p in const [
        _createTo,
        'lib/screens/business_admin/to_management/edit_to_screen.dart',
      ]) {
        final s = _src(p);
        expect(s.contains('PostingNotReady.parse(e) case final notReady?'),
            isTrue, reason: p);
        expect(s.contains('ToastHelper.showError(notReady.message)'), isTrue,
            reason: p);
      }
      // 예전 경로(서버 문장 직접 노출)가 남아 있지 않다.
      expect(_src(_createTo).contains("e.message ?? '공고 등록 조건을 확인해 주세요.'"),
          isFalse);
      expect(
          _src('lib/screens/business_admin/to_management/edit_to_screen.dart')
              .contains('ToastHelper.showError(e.message!)'),
          isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // SNAPSHOT-01. 날인 교체가 과거 계약을 바꾸지 않는다
  // ══════════════════════════════════════════════════════════════
  test('SNAPSHOT-01 서명된 계약은 서명 시점 이미지를 렌더한다', () {
    // 과거 완료 계약이 현재 `users.sealBase64` 를 runtime 으로 렌더하면
    // 날인을 바꾼 순간 과거 계약의 도장이 바뀐다 — BLOCKER 가 된다.
    //
    // 실제 구조(확인): 계약 문서는 base64 가 아니라 **서명 시점 Storage
    // URL**(`employerSignatureUrl`)을 들고 있고, 렌더는 그 URL 을 **우선**
    // 한다. base64 는 아직 서명 전 미리보기용 폴백이다.
    final model = _src('lib/models/core/employment_contract_model.dart');
    expect(model.contains('final String? employerSignatureUrl;'), isTrue);
    expect(model.contains("'employerSignatureUrl': employerSignatureUrl"),
        isTrue);

    final sign = _src('lib/screens/contract/contract_sign_screen.dart');
    expect(
        sign.contains('employerSignatureUrl: widget.contract.employerSignatureUrl'),
        isTrue, reason: '계약 문서의 고정 URL 을 넘긴다');
    expect(sign.contains('/// 미서명 상태의 미리보기용 base64 — imageUrl이 없을 때만 사용'),
        isTrue, reason: 'base64 가 URL 을 덮으면 과거 계약이 바뀐다');
  });

  test('SNAPSHOT-02 서명 화면도 owner 날인을 읽는다', () {
    // 이 화면은 원래부터 `businesses.ownerId → users/{ownerId}` 였다.
    // 내 발송 경로 수정이 이 canonical 과 같은 방향인지 확인한다.
    final sign = _src('lib/screens/contract/contract_sign_screen.dart');
    expect(sign.contains("final ownerId = data['ownerId'] as String?;"), isTrue);
    expect(sign.contains("sealBase64 = ud?['sealBase64'] as String?;"), isTrue);
  });
}
