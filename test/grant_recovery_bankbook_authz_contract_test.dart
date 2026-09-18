// [CROSS-DOMAIN-R5.2A] grant 복구 / 통장사본 인가 / FULL·CLOSED 수락
//
// 세 가지를 닫는다.
//
//   1. [BLOCKER-ID-GRANT-POSTCOMMIT-RECOVERY]
//      grant 쓰기는 좌석 트랜잭션 밖이라(POST_COMMIT), 좌석은 커밋됐는데
//      grant만 실패한 상태가 남을 수 있다. 그런데 두 경로의 멱등 early return이
//      **헬퍼보다 앞에** 있어서, 다시 눌러도 만들 기회가 없었다 — 근로자가
//      신분증을 다시 올리기 전까지 영영 비어 있었다.
//      이제 멱등 재호출이 복구 경로다. 이미 있으면 skip이고, 좌석·카운터·
//      상태는 건드리지 않는다.
//      DEV 실측: grant 삭제 → 재호출 → 0→1 복구(approved/pre_consent,
//      올바른 사업장·지원서·근로자·만료), 좌석 diff 0, 2차 재시도 중복 0.
//
//   2. [BLOCKER-BANKBOOK-URL-OWNER-BIZ-RESOLUTION]
//      통장사본 Signed URL이 호출자 사업장을 `users/{uid}.businessId` 하나로
//      해석했다. 소유자는 그 필드가 비어 있고 managedBusinessIds/ownerId로
//      관리하는 경우가 있어, 자기 사업장 지원서인데도 403이 났다(실측).
//      대상 사업장을 payload로 명시받고, canonical source(businesses 문서 +
//      users의 배정 필드)로 인가한 **뒤에** 지원서를 읽는다.
//      DEV 실측 A~H 전원 PASS.
//
//   3. FULL / manually CLOSED 수락 — 같은 근로자 중복이 아니라 **다른 근로자**로.
//      DEV 실측: 정원 1/1에서 B 수락 400, INVITED 유지, 확정 1 유지,
//      대기 변화 0, 계약·grant 0, 수락 알림 0. 수동 마감도 동일.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

String _load(String p) => _flat(_codeOf(_src(p)));

String _callableBody(String raw, String name) {
  final start = raw.indexOf('export const $name = onCall(');
  if (start < 0) throw StateError('$name 을 찾지 못함');
  final end = raw.indexOf('\n);', start);
  if (end < 0) throw StateError('$name 본문 끝을 찾지 못함');
  return raw.substring(start, end);
}

const _cf = 'functions/src/index.ts';
const _workerDlg = 'lib/widgets/dialogs/worker_detail_dialog.dart';

void main() {
  final rawCf = _codeOf(_src(_cf));
  final cf = _flat(rawCf);
  final accept = _flat(_callableBody(rawCf, 'callableAcceptTOInvitation'));
  final confirm = _flat(_callableBody(rawCf, 'callableConfirmApplication'));
  final bankbook = _flat(_callableBody(rawCf, 'callableGetBankbookSignedUrl'));

  // ── PART A. grant 복구 ─────────────────────────────────────────────

  group('멱등 재호출이 grant 복구 경로다', () {
    test('수락 경로 — 멱등 반환 전에 헬퍼를 부른다', () {
      final at = accept.indexOf('if (currentStatus === "CONFIRMED") {');
      final helper = accept.indexOf(
          'await ensureIdCardGrantForConfirmedApplication(', at);
      final ret = accept.indexOf('return {success: true, alreadyConfirmed: true};', at);
      expect(at, greaterThan(-1));
      expect(helper, greaterThan(at));
      expect(helper < ret, true,
          reason: '반환이 헬퍼보다 앞서면 복구할 기회가 없다');
    });

    test('확정 경로 — 멱등 반환 전에 헬퍼를 부른다', () {
      final at = confirm.indexOf('if (alreadyConfirmed) {');
      final helper = confirm.indexOf(
          'await ensureIdCardGrantForConfirmedApplication(', at);
      final ret = confirm.indexOf('return {success: true, alreadyConfirmed: true};', at);
      expect(at, greaterThan(-1));
      expect(helper, greaterThan(at));
      expect(helper < ret, true);
    });

    test('복구 호출이 좌석·상태를 건드리지 않는다', () {
      final at = accept.indexOf('if (currentStatus === "CONFIRMED") {');
      final ret = accept.indexOf('return {success: true, alreadyConfirmed: true};', at);
      final seg = accept.substring(at, ret);
      for (final forbidden in [
        'tx.update(', 'runTransaction', 'totalConfirmed', 'pendingCount',
        'status: "CONFIRMED"',
      ]) {
        expect(seg.contains(forbidden), false, reason: forbidden);
      }
    });

    test('복구 실패가 멱등 응답을 막지 않는다', () {
      expect(accept.contains('console.warn("[acceptTOInvitation] '
          '멱등 재호출 grant 복구 실패:", e);'), true);
      expect(confirm.contains('console.warn("[confirmApplication] '
          '멱등 재호출 grant 복구 실패:", e);'), true);
    });

    test('헬퍼가 이미 있는 grant를 덮어쓰지 않는다', () {
      final i = cf.indexOf('async function ensureIdCardGrantForConfirmedApplication(');
      final body = cf.substring(i, i + 3200);
      expect(
          body.contains('if (existingGrant.exists && '
              'existingGrant.data()?.status === "approved") { return "skipped"; }'),
          true);
    });

    test('polling·scheduler를 새로 만들지 않았다', () {
      // 복구는 사용자가 만든 재호출 경로뿐이다.
      final at = accept.indexOf('if (currentStatus === "CONFIRMED") {');
      final ret = accept.indexOf('return {success: true, alreadyConfirmed: true};', at);
      final seg = accept.substring(at, ret);
      expect(seg.contains('onSchedule'), false);
      expect(seg.contains('setInterval'), false);
    });
  });

  // ── PART B. 통장사본 인가 ──────────────────────────────────────────

  group('통장사본은 대상 사업장 기준으로 인가한다', () {
    test('businessId를 명시적으로 받는다', () {
      expect(
          bankbook.contains('const {applicationId, businessId: claimedBizId} = '
              'request.data as {applicationId?: string; businessId?: string};'),
          true);
      expect(
          bankbook.contains('if (!claimedBizId || typeof claimedBizId !== "string") { '
              'throw new HttpsError("invalid-argument", "businessId가 필요합니다."); }'),
          true);
    });

    test('users.businessId 단독 판정을 쓰지 않는다', () {
      expect(
          bankbook.contains('if (isBusinessAdmin && callerBusinessId) { '
              'if (callerBusinessId === appBusinessId) {'),
          false,
          reason: '소유자는 businessId가 비어 있을 수 있다');
      expect(
          bankbook.contains('const callerManagedBizIds = '
              '(callerData.managedBusinessIds as string[] | undefined) ?? [];'),
          true,
          reason: 'canonical 배정 source를 함께 본다');
    });

    test('businesses 문서의 owner/adminIds가 판정에 들어간다', () {
      expect(
          bankbook.contains('const stillMember = bizOwnerId === callerUid || '
              'bizAdminIds.includes(callerUid) ||'),
          true);
      expect(bankbook.contains('claimedByCallerFields;'), true);
    });

    test('canManageWage를 여전히 요구한다', () {
      expect(
          bankbook.contains('if (!canManageWage) { throw new HttpsError('
              '"permission-denied", "급여 관리 권한이 없습니다."); }'),
          true);
    });

    test('인가가 지원서 읽기보다 먼저다 (existence oracle 차단)', () {
      final wage = bankbook.indexOf('"급여 관리 권한이 없습니다."');
      final fetch = bankbook.indexOf(
          'const appDoc = await db.collection("applications").doc(applicationId).get();');
      expect(wage, greaterThan(-1));
      expect(fetch, greaterThan(-1));
      expect(wage < fetch, true,
          reason: '문서를 먼저 읽으면 없는 id와 있는 id의 응답이 갈린다');
    });

    test('주장한 사업장과 다르면 없는 것과 같이 답한다', () {
      expect(
          bankbook.contains('if (appBusinessId !== callerBizId) { '
              'throw new HttpsError("not-found", "지원서를 찾을 수 없습니다."); }'),
          true);
    });

    test('상태·동의 게이트는 그대로다', () {
      expect(
          bankbook.contains('if (appStatus !== "CONFIRMED") { throw new HttpsError('
              '"permission-denied", "확정된 지원서의 통장사본만 열람 가능합니다."); }'),
          true);
      expect(
          bankbook.contains('if (!docConsentGiven) { throw new HttpsError('
              '"permission-denied", "근로자가 서류 접근에 동의하지 않았습니다."); }'),
          true);
    });

    test('클라이언트가 대상 사업장을 보낸다', () {
      final w = _load(_workerDlg);
      expect(
          w.contains(".call({'applicationId': appId, 'businessId': bizId});"), true);
      expect(w.contains("final bizId = widget.application?.businessId;"), true);
    });
  });

  group('신분증 Signed URL은 같은 결함이 없다', () {
    test('caller 사업장을 users.businessId로 해석하지 않는다', () {
      final idurl = _flat(_callableBody(rawCf, 'callableGetIdCardSignedUrl'));
      // 이 엔드포인트는 targetUserId + grant 문서로 판정한다 —
      // caller business 해석 자체가 없으므로 건드리지 않는다.
      expect(idurl.contains('const {targetUserId} = request.data'), true);
      expect(idurl.contains('callerData.businessId as string | undefined'), false);
    });
  });

  // ── PART C/D. FULL · CLOSED 수락 ───────────────────────────────────

  group('정원이 찼거나 마감된 근무는 수락되지 않는다', () {
    test('정원 재검증이 트랜잭션 안에 있다', () {
      final txAt = accept.indexOf('await db.runTransaction(async (tx)');
      final cap = accept.indexOf('슬롯 정원이 초과되어 초대를 수락할 수 없습니다', txAt);
      expect(txAt, greaterThan(-1));
      expect(cap, greaterThan(txAt), reason: '실측 문구와 같은 자리');
    });

    test('마감 상태를 현재 값으로 다시 읽는다', () {
      expect(accept.contains('모집이 종료된 근무는 수락할 수 없습니다'), true);
    });

    test('거부는 좌석을 잡기 전에 일어난다', () {
      final cap = accept.indexOf('슬롯 정원이 초과되어 초대를 수락할 수 없습니다');
      final seat = accept.indexOf('totalConfirmed: admin.firestore.FieldValue.increment(1)');
      expect(cap < seat, true);
    });

    test('서류 readiness 게이트가 정원·마감 판정보다 먼저다', () {
      // 서류가 없으면 정원 계산까지 가지도 않는다 — 실측 순서와 같다.
      final doc = accept.indexOf('"통장사본 등록이 필요합니다."');
      final cap = accept.indexOf('슬롯 정원이 초과되어 초대를 수락할 수 없습니다');
      expect(doc, greaterThan(-1));
      expect(cap, greaterThan(-1));
      expect(doc < cap, true);
    });
  });

  // ── PART E. overlap guard 무변경 ───────────────────────────────────

  group('겹침 guard는 그대로다', () {
    test('수락 트랜잭션의 KST 달력일 비교가 유지된다', () {
      expect(
          accept.contains('if (txKst.getUTCFullYear() !== cKst.getUTCFullYear() || '
              'txKst.getUTCMonth() !== cKst.getUTCMonth() || '
              'txKst.getUTCDate() !== cKst.getUTCDate()) continue;'),
          true);
      expect(accept.contains('이미 확정된 근무가 있어 수락할 수 없습니다'), true);
    });

    test('초대 사전검사의 KST 창도 유지된다', () {
      expect(cf.contains('if (cKey !== invDateKey) continue;'), true);
    });
  });

  // ── 회귀. R5.2 본체는 그대로 ───────────────────────────────────────

  group('R5.2 parity 패치는 유지된다', () {
    test('수락 시 서류·동의 게이트가 그대로다', () {
      for (final m in [
        '"통장사본 등록이 필요합니다."',
        '"신분증 등록이 필요합니다."',
        '"통장 정보 등록이 필요합니다."',
        '소득신고·급여처리 목적 서류 접근에 동의해야',
      ]) {
        expect(accept.contains(m), true, reason: m);
      }
    });

    test('동의는 여전히 CONFIRMED와 같은 트랜잭션에 쓴다', () {
      expect(accept.contains('tx.update(appRef, acceptUpdate);'), true);
      expect(accept.contains('documentAccessConsentGiven: true, '
          'documentAccessConsentAt: confirmedAt,'), true);
    });

    // [CROSS-DOMAIN-R5.3E.2] 호출 수 대신 경로 이름으로 확인한다.
    //   확정을 만드는 경로가 늘어도(확정 재배치 수락) 계약은 같다.
    test('확정을 만드는 모든 경로가 같은 grant 헬퍼를 쓴다', () {
      for (final w in const [
        'callableConfirmApplication',
        'callableAcceptTOInvitation',
        'callableAcceptConfirmedReassignment',
      ]) {
        final a = cf.indexOf('export const $w = onCall(');
        expect(a >= 0, true, reason: '$w 를 찾지 못함');
        final b = cf.indexOf('export const ', a + 20);
        final body = cf.substring(a, b < 0 ? cf.length : b);
        expect(body.contains('ensureIdCardGrantForConfirmedApplication('), true,
            reason: '$w 에서 grant가 빠지면 그 경로만 신분증 접근이 끊긴다');
      }
    });
  });
}
