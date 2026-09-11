// 사업장 승인 자가 복구 (BUSINESS-ADMIN-FIRST-POSTING-APPROVAL-RECOVERY)
//
// FP-04: 자동 승인은 onBusinessCreated 1회만 실행되고 재평가 트리거가 없다.
// 그 순간 Storage API가 일시 실패하면 hasValidBusinessLicense가 fail-closed로
// false를 반환하고, 사업자등록증이 정상인데도 isApproved=false가 영구 고착된다.
// UI는 이를 정상 수동 승인 대기처럼 표현해 사용자가 스스로 벗어날 수 없다.
//
// 복구는 **새 승인 권한이 아니라 자동 승인 정책의 재평가 경로**다.
// 승인 판정은 전적으로 서버가 한다 — 이 파일은 그 계약이 유지되는지 지킨다.
//
// Functions(TypeScript)는 Dart 테스트에서 실행할 수 없고, 클라이언트 서비스는
// FirebaseFunctions 인스턴스를 요구한다. 따라서 순수 로직(enum 계약)은 단위
// 테스트로, 서버/화면 계약은 소스 검증으로 확인한다 — test 전용 public API를
// 새로 열지 않는다(5.8·5.11에서 쓴 방식과 동일).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/services/business_posting_readiness.dart';

String _source(String relativePath) {
  final f = File(relativePath);
  expect(f.existsSync(), true, reason: '$relativePath 를 찾지 못함');
  return f.readAsStringSync();
}

/// TypeScript 소스에서 지정한 함수/콜러블 본문만 잘라낸다.
/// 파일 전역 검색은 다른 콜러블의 코드를 오인하기 쉽다.
String _tsBlock(String src, String anchor, {int span = 5000}) {
  final i = src.indexOf(anchor);
  expect(i, greaterThan(-1), reason: 'TS 앵커를 찾지 못함: $anchor');
  final end = (i + span) > src.length ? src.length : i + span;
  return src.substring(i, end);
}

void main() {
  late final String fns = _source('functions/src/index.ts');
  late final String recheck =
      _tsBlock(fns, 'export const callableRecheckBusinessApproval');

  // ── result contract ─────────────────────────────────────────────
  group('BAR-0x result contract', () {
    test('BAR-01 서버 상태값이 클라이언트 enum과 1:1 대응한다', () {
      for (final wire in const [
        'ALREADY_APPROVED',
        'APPROVED',
        'AWAITING_MANUAL_REVIEW',
        'LICENSE_NOT_READY',
        'TEMPORARY_CHECK_FAILED',
      ]) {
        expect(recheck.contains('"$wire"'), true,
            reason: '서버가 $wire 를 반환하지 않음');
        expect(
            BusinessApprovalRecheck.values.any((e) => e.wireName == wire), true,
            reason: '클라이언트에 $wire 매핑이 없음');
      }
    });

    test('BAR-02 승인으로 해석되는 상태는 두 가지뿐', () {
      final approved = BusinessApprovalRecheck.values
          .where((e) => e.isApproved)
          .toSet();
      expect(approved, {
        BusinessApprovalRecheck.approved,
        BusinessApprovalRecheck.alreadyApproved,
      });
    });

    test('BAR-03 수동 검토·등록증 미비는 승인이 아니다', () {
      expect(BusinessApprovalRecheck.awaitingManualReview.isApproved, false);
      expect(BusinessApprovalRecheck.licenseNotReady.isApproved, false);
      expect(BusinessApprovalRecheck.temporaryCheckFailed.isApproved, false);
      expect(BusinessApprovalRecheck.notPermitted.isApproved, false);
      expect(BusinessApprovalRecheck.notFound.isApproved, false);
    });

    test('BAR-04 재시도 가능한 상태는 일시 실패뿐', () {
      final retryable =
          BusinessApprovalRecheck.values.where((e) => e.isRetryable).toSet();
      expect(retryable, {BusinessApprovalRecheck.temporaryCheckFailed});
      // 등록증 미비는 재시도가 아니라 등록으로 풀린다.
      expect(BusinessApprovalRecheck.licenseNotReady.isRetryable, false);
      // 수동 검토를 재시도 유도하면 "다시 누르면 승인된다"는 오해가 생긴다.
      expect(BusinessApprovalRecheck.awaitingManualReview.isRetryable, false);
    });

    test('BAR-05 알 수 없는 상태는 승인으로 해석되지 않는다', () {
      // 서버가 새 상태를 추가해도 클라이언트가 임의로 통과시키면 안 된다.
      expect(
          BusinessApprovalRecheck.values
              .any((e) => e.wireName == 'SOMETHING_NEW'),
          false);
      expect(recheck.contains('orElse'), false,
          reason: 'orElse는 서비스 쪽에 있어야 한다');
      final svc = _source('lib/services/business_posting_readiness.dart');
      expect(svc.contains('orElse: () => BusinessApprovalRecheck.temporaryCheckFailed'),
          true, reason: '미지의 상태를 승인으로 해석하지 않는 fallback이 없음');
    });
  });

  // ── §24 authorization ───────────────────────────────────────────
  group('BAR-1x 권한', () {
    test('BAR-10 인증 필수 + App Check', () {
      expect(recheck.contains('enforceAppCheck: true'), true);
      expect(
          recheck.contains('if (!request.auth) throw new HttpsError("unauthenticated"'),
          true);
    });

    test('BAR-11 businessId 입력 검증', () {
      expect(recheck.contains('invalid-argument'), true);
      expect(recheck.contains('typeof businessId !== "string"'), true);
    });

    test('BAR-12 존재하지 않는 사업장 거부', () {
      expect(recheck.contains('if (!bizSnap.exists) throw new HttpsError("not-found"'),
          true);
    });

    test('BAR-13 소유자만 허용 — SUB_ADMIN 승인권 확대 없음', () {
      // assertBizAdmin은 adminIds·subAdminBusinessIds까지 인정하므로 호출하면 안 된다.
      // (설명 주석에는 이름이 등장하므로 호출 형태로 검사한다)
      expect(recheck.contains('assertBizAdmin('), false,
          reason: 'assertBizAdmin을 호출하면 SUB_ADMIN에게 승인 경로가 열린다');
      expect(recheck.contains('bizData?.ownerId as string | undefined) !== callerUid'),
          true);
      expect(recheck.contains('permission-denied'), true);
    });

    test('BAR-14 pending 계정 차단', () {
      expect(recheck.contains('accountStatus !== "active"'), true);
    });
  });

  // ── §9 정책 canonical ───────────────────────────────────────────
  group('BAR-2x 승인 정책', () {
    test('BAR-20 businessAutoApprove를 서버가 다시 읽는다', () {
      expect(recheck.contains('settings").doc("system")'), true);
      expect(recheck.contains('businessAutoApprove'), true);
    });

    test('BAR-21 autoApprove=false면 self-approve 불가', () {
      final i = recheck.indexOf('if (!autoApprove)');
      expect(i, greaterThan(-1));
      final branch = recheck.substring(i, i + 200);
      expect(branch.contains('AWAITING_MANUAL_REVIEW'), true);
      expect(branch.contains('isApproved: true'), false,
          reason: '수동 승인 정책을 우회해 승인하고 있음');
    });

    test('BAR-22 클라이언트 전달값을 승인 근거로 쓰지 않는다', () {
      // request.data에서 읽는 것은 businessId 하나뿐이어야 한다.
      final dataReads = RegExp(r'request\.data as \{([^}]*)\}')
          .firstMatch(recheck)
          ?.group(1);
      expect(dataReads, isNotNull);
      expect(dataReads!.contains('isApproved'), false);
      expect(dataReads.contains('license'), false);
      expect(dataReads.contains('autoApprove'), false);
    });

    test('BAR-23 승인 판정에 canonical license 검증을 쓴다', () {
      expect(recheck.contains('checkBusinessLicense(businessId, bizData)'), true);
      // truthy check로 약화되지 않았는지
      expect(recheck.contains('businessLicenseImageUrl'), false,
          reason: 'URL truthy 검사로 승인하면 LICENSE-GATE가 무력화된다');
    });

    test('BAR-24 비활성화된 사업장은 자가 복구 대상이 아니다', () {
      expect(recheck.contains('bizData?.deactivatedAt'), true);
    });
  });

  // ── §11 idempotency / §19 atomicity ─────────────────────────────
  group('BAR-3x 멱등성·원자성', () {
    test('BAR-30 이미 승인된 경우 즉시 반환', () {
      expect(recheck.contains('if (bizData?.isApproved === true)'), true);
      expect(recheck.contains('"ALREADY_APPROVED"'), true);
    });

    test('BAR-31 승인 write는 트랜잭션으로 중복 기록을 막는다', () {
      expect(recheck.contains('runTransaction'), true);
      expect(recheck.contains('if (fresh.data()?.isApproved === true) return;'),
          true, reason: '경합 시 approvedAt이 덮어써진다');
    });

    test('BAR-32 트랜잭션 안에서 Storage를 호출하지 않는다', () {
      final i = recheck.indexOf('runTransaction');
      final tx = recheck.substring(i, i + 400);
      expect(tx.contains('checkBusinessLicense'), false);
      expect(tx.contains('bucket'), false);
      expect(tx.contains('storage'), false);
      // license 검증이 트랜잭션보다 먼저 끝나야 한다
      expect(recheck.indexOf('checkBusinessLicense') < i, true);
    });

    test('BAR-33 승인 출처가 감사 가능하다', () {
      expect(recheck.contains('approvedBy: "system_auto_recheck"'), true,
          reason: '자동 생성 승인(system_auto)과 구분되어야 한다');
    });
  });

  // ── §12 transient vs missing ────────────────────────────────────
  group('BAR-4x 일시 실패와 미등록을 구분한다', () {
    late final String checkFn = _tsBlock(fns, 'async function checkBusinessLicense');

    test('BAR-40 3-state 판정이 존재한다', () {
      expect(fns.contains('type BusinessLicenseCheck = "VALID" | "MISSING" | "CHECK_FAILED"'),
          true);
    });

    test('BAR-41 API 오류를 미등록으로 단정하지 않는다', () {
      expect(checkFn.contains('apiFailed = true'), true);
      expect(checkFn.contains('return apiFailed ? "CHECK_FAILED" : "MISSING";'),
          true);
    });

    test('BAR-42 후보 경로가 아예 없으면 MISSING', () {
      // URL이 없거나 prefix가 틀리면 apiFailed가 서지 않아 MISSING이 된다.
      expect(checkFn.contains('let apiFailed = false;'), true);
    });

    test('BAR-43 기존 boolean gate의 fail-closed가 유지된다', () {
      final boolFn = _tsBlock(fns, 'async function hasValidBusinessLicense', span: 600);
      expect(
          boolFn.contains('(await checkBusinessLicense(businessId, bizData)) === "VALID"'),
          true,
          reason: 'CHECK_FAILED가 승인 gate를 통과하면 LICENSE-GATE가 약화된다');
    });

    test('BAR-44 CHECK_FAILED는 승인하지 않고 별도 상태로 알린다', () {
      final i = recheck.indexOf('if (licenseCheck === "CHECK_FAILED")');
      expect(i, greaterThan(-1));
      final branch = recheck.substring(i, i + 300);
      expect(branch.contains('TEMPORARY_CHECK_FAILED'), true);
      expect(branch.contains('isApproved: true'), false);
    });
  });

  // ── §13 no automatic retry / §21 creation path ──────────────────
  group('BAR-5x 범위 불변식', () {
    test('BAR-50 자동 승인 트리거가 그대로 남아 있다', () {
      expect(fns.contains('export const onBusinessCreated'), true);
      expect(fns.contains('approvedBy: "system_auto"'), true);
    });

    test('BAR-51 업데이트 기반 자동 재평가를 추가하지 않았다', () {
      // businesses/{businessId} onDocumentUpdated는 deactivate 전용 하나뿐이어야 한다.
      final updateTriggers =
          RegExp(r'onDocumentUpdated\(\s*\{?\s*\n?\s*document: "businesses/\{businessId\}"')
              .allMatches(fns)
              .length;
      expect(updateTriggers <= 1, true,
          reason: '승인 재평가용 update 트리거가 추가됨 (무제한 자동 재시도 금지)');
      // 복구는 호출자 개시로만 실행된다 — 스케줄러·다른 함수가 부르지 않는다.
      // 주석 줄을 제외한 실제 코드에서 이름이 나오는 곳은 export 선언 하나뿐이어야 한다.
      final codeRefs = fns
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .where((l) => l.contains('callableRecheckBusinessApproval'))
          .toList();
      expect(codeRefs.length, 1,
          reason: '복구 콜러블을 export 외의 경로가 참조함: $codeRefs');
      expect(codeRefs.single.contains('export const'), true);
    });

    test('BAR-52 SUPER_ADMIN 수동 승인 경로 무변경', () {
      final manage = _tsBlock(fns, 'export const callableManageBusiness');
      expect(manage.contains('callerRole !== "SUPER_ADMIN"'), true);
      expect(manage.contains('hasValidBusinessLicense(businessId, bizSnap.data())'),
          true);
      expect(manage.contains('approvedBy: callerUid'), true);
    });

    test('BAR-53 새 persisted 상태 필드를 만들지 않았다', () {
      for (final banned in const [
        'approvalRetryNeeded',
        'approvalCheckFailed',
        'onboardingApprovalState',
        'approvalRecheckedAt',
      ]) {
        expect(fns.contains(banned), false, reason: '$banned 필드가 추가됨');
      }
    });
  });

  // ── §14~18 클라이언트 계약 ──────────────────────────────────────
  group('BAR-6x 클라이언트 복구 진입점', () {
    late final String createTo = _source(
        'lib/screens/business_admin/to_management/create_to_screen.dart');

    test('BAR-60 기존 "다시 확인" 하나에만 연결됐다', () {
      expect(createTo.contains('_onRecheckPressed'), true);
      // 복구 호출부가 여러 곳으로 번지지 않았는지
      final calls = 'recheckApproval'.allMatches(createTo).length;
      expect(calls, 1, reason: '복구 호출이 여러 곳에 중복 구현됨');
    });

    test('BAR-61 미승인일 때만 서버 재판정을 요청한다', () {
      expect(
          createTo.contains('if (!_businessApproved && _unapprovedBusinesses.isNotEmpty)'),
          true);
    });

    test('BAR-62 CTA 복귀 경로는 기존 동작 그대로다', () {
      // _reCheckPrerequisites 자체는 승인 재판정을 하지 않는다 —
      // 5개 카드 복귀마다 콜러블을 호출하면 불필요한 반복 호출이 된다.
      final i = createTo.indexOf('Future<void> _reCheckPrerequisites() async {');
      expect(i, greaterThan(-1));
      final body = createTo.substring(i, i + 1500);
      expect(body.contains('recheckApproval'), false);
    });

    test('BAR-63 일시 실패를 승인 대기로 삼키지 않는다', () {
      expect(createTo.contains('현재 상태를 확인하지 못했어요'), true);
    });

    test('BAR-64 "다시 확인하면 승인된다"는 문구가 없다', () {
      for (final banned in const [
        '다시 확인하면 승인',
        '자동으로 승인됩니다',
        '승인 요청',
      ]) {
        expect(createTo.contains(banned), false, reason: '"$banned" 문구가 사용됨');
      }
    });

    test('BAR-65 중복 호출 가드가 있다', () {
      expect(createTo.contains('_isRecheckingApproval'), true);
      expect(createTo.contains('if (_isLoading || _isRecheckingApproval) return;'),
          true);
    });

    test('BAR-66 성공 시 사전조건 전체를 다시 읽는다', () {
      final i = createTo.indexOf('Future<void> _onRecheckPressed() async {');
      final body = createTo.substring(i, createTo.indexOf('/// 사전조건 화면에서', i));
      expect(body.contains('await _reCheckPrerequisites();'), true);
    });
  });

  // ── §28 readiness IA 미변경 ─────────────────────────────────────
  group('BAR-7x 이번 Phase 범위 밖 불변식', () {
    test('BAR-70 CreateTO 5개 gate 구조 유지', () {
      final createTo = _source(
          'lib/screens/business_admin/to_management/create_to_screen.dart');
      expect(
          createTo.contains(
              '_businessApproved && _workTypesReady && _contractTemplatesReady &&'),
          true);
      expect(createTo.contains('cardCount = isSubAdmin ? 4 : 5'), true);
    });

    test('BAR-71 홈이 승인 복구를 자동 호출하지 않는다', () {
      // 원래 이 테스트는 "FP-01 미변경"을 지켰으나, FP-01은 후속
      // READINESS-ALIGNMENT Phase에서 의도적으로 닫혔다(홈 준비 카드가
      // CreateTO와 같은 4개 task를 셈). 여기서 지켜야 할 불변식은
      // 승인 복구 쪽 — 홈 readiness가 recheck callable을 자동으로 부르면
      // 화면 진입마다 무제한 재시도가 된다(§13 금지).
      final home = _source(
          'lib/screens/business_admin/business_admin_home_screen.dart');
      expect(home.contains('recheckApproval'), false,
          reason: '홈 readiness가 승인 복구를 자동 호출함');
    });
  });
}
