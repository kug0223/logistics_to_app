// [ARCHIVE-SEQ-FENCE 2026-10-16] 운영 종료 후 순차 호출로 새 확정이 생기던 경로
//
// 무엇이 잘못됐었나 (에뮬레이터 반례 — scripts/archive-seq-fence-runtime.js BEFORE=/AFTER=)
//
//   종료 연쇄는 ACTIVE/FULL/SCHEDULED 공고만 접는다. 이미 마감된 공고의 PENDING·
//   CONTRACT_PENDING 은 남았고, 지원 검토 승인 → 사업주 새 계약 → 근로자 서명을
//   순서대로 부르면 닫힌 사업장에 CONFIRMED 가 생겼다. 세 writer 가 사업장을 읽지 않았다.
//
// 이 파일은 그 경계가 코드에 남아 있는지 고정한다(실행 검증은 위 스크립트).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final cf = _read('functions/src/index.ts');
  String body(String head, [String end = '\n}\n']) {
    final i = cf.indexOf(head);
    expect(i, greaterThanOrEqualTo(0), reason: head);
    return cf.substring(i, cf.indexOf(end, i));
  }

  String callable(String name) => body('export const $name = onCall(', '\n);\n');

  group('SF-1 판정은 상태를 바꾸는 트랜잭션 안에서', () {
    test('SF-11 근로자 서명: 지원서 읽기 뒤·쓰기 앞에서 사업장 판정', () {
      final b = callable('callableFinalizeWorkerSignature');
      final reads = b.indexOf('const appSnaps = await Promise.all(appRefs.map((ref) => tx.get(ref)));');
      final fence = b.indexOf('await srvAssertArchiveContractFenceInTx(tx, fenceBizId,');
      final write = b.indexOf('tx.update(contractRef, {');
      expect(reads, greaterThan(0));
      expect(fence, greaterThan(reads));
      expect(write, greaterThan(fence));
    });
    test('SF-12 사업주 서명: 새 계약·기존 계약 두 트랜잭션 모두 쓰기 앞에서 판정', () {
      final b = callable('callableFinalizeEmployerSignature');
      final newTx = b.indexOf('await srvAssertArchiveContractFenceInTx(tx, dupBizId, fenceApps, archiveFenceRefs);');
      expect(newTx, greaterThan(0));
      expect(b.indexOf('tx.set(contractRef, data);'), greaterThan(newTx));
      final oldTx = b.indexOf('await srvAssertArchiveContractFenceInTx(tx, fenceBizId,');
      expect(oldTx, greaterThan(newTx));
      expect(b.indexOf('tx.update(contractRef, {', oldTx), greaterThan(oldTx));
    });
    test('SF-13 지원 검토 승인: 멱등 분기보다 앞에서 사업장을 읽는다(재호출 알림 금지)', () {
      final b = callable('callableApproveApplicationForReview');
      final fence = b.indexOf('if (srvBizClosedForNewCommitment(approveBizFresh)) {');
      expect(fence, greaterThan(b.indexOf('const approveBizFresh = await tx.get(db.collection("businesses").doc(targetBusinessId));')));
      expect(b.indexOf('if (freshStatus === "CONTRACT_PENDING") {'), greaterThan(fence));
    });
    test('SF-14 사업장 판정은 tx.get — 트랜잭션 밖 사업장 읽기로 정하지 않는다', () {
      final b = body('async function srvAssertArchiveContractFenceInTx(');
      expect(b, contains('const biz = await tx.get(db.collection("businesses").doc(bizId));'));
      // [ARCHIVE-CLOSED-TO-PREFLIGHT] 이유별 문구(앱이 그대로 띄운다), 없는 이유는 공통 문구.
      expect(b, contains('ARCHIVE_FENCE_MESSAGES[reason] ?? ARCHIVE_FENCE_MESSAGE, {reason});'));
    });
  });

  group('SF-2 보존 경계', () {
    test('SF-21 닫힌 사업장: CONTRACT_PENDING 은 막고, CONFIRMED 는 보존된 것만 문서화', () {
      final b = body('function srvArchiveContractFenceReason(');
      expect(b, contains('if (st === "CONTRACT_PENDING") return "CONTRACT_PENDING_AFTER_CLOSURE";'));
      expect(b, contains('if (!(a.actualWork || srvScheduleKnownStarted(a.data, nowMs))) return "CONFIRMED_NOT_STARTED_AFTER_CLOSURE";'));
      expect(b, contains('return preserved > 0 ? null : "NO_PRESERVED_COMMITMENT";'));
    });
    test('SF-22 시작을 모르면 "이미 일함"으로 보지 않는다(그날 안이면 false, 하루가 다 지나면 true)', () {
      final b = body('function srvScheduleKnownStarted(');
      expect(b, contains('return startNum > 0 && startNum <= kstDateNum(new Date(nowMs));'));
      expect(b, contains('?? (dayStart + 86400000);'));
      expect(b, contains('if (!wd || typeof wd.toMillis !== "function") return false;'));
    });
    test('SF-23 사업장 문서가 없으면 닫힌 것으로 보고, 계약 문서화도 거절한다', () {
      expect(body('function srvBizClosedForNewCommitment('),
          contains('return !biz.exists || biz.get("deactivatedAt") != null;'));
      // [ARCHIVE-CLOSED-TO-PREFLIGHT] 보존 근무라도 사업주 주체를 확인할 수 없으면 서명하지 않는다.
      final b = body('async function srvAssertArchiveContractFenceInTx(');
      final missing = b.indexOf('if (!biz.exists) {');
      expect(missing, greaterThan(0));
      expect(b.indexOf('if (!srvBizClosedForNewCommitment(biz)) return;'), greaterThan(missing));
      expect(b, contains('{reason: "BUSINESS_MISSING"}'));
    });
    test('SF-24 공용 lifecycle helper 는 그대로, 종료 연쇄는 서명 펜스를 쓰지 않는다', () {
      // 바꾸면 onBusinessDeleted·callableDeleteTO·탈퇴가 배포 대상에 끌려온다.
      expect(body('function srvScheduleNotStarted('), contains('if (startNum <= 0) return false; // 모름 → 보존'));
      expect(cf.contains('srvAssertArchiveContractFenceInTx(tx') &&
          !body('export const onBusinessDeactivated = onDocumentUpdated(', '\n);\n').contains('srvArchiveContractFence'), isTrue);
    });
  });

  group('SF-3 마감 공고 잔여 · 사전 조회 = 연쇄 (ARCHIVE-CLOSED-TO-PREFLIGHT)', () {
    test('SF-31 연쇄: 사업장 전체 대기·계약 대기를 id 페이지로 끝까지 처리한다', () {
      // [ARCHIVE-CASCADE-PAGINATION] 상한 한 번 읽기(ARCHIVE_CASCADE_LIMIT)를 페이지 루프로 바꿨다.
      final run = body('async function srvRunBusinessArchiveCascade(');
      expect(run, contains('await srvForEachIdPage(apps.where("status", "==", "PENDING"), async (docs) => {'));
      expect(run, contains('const r = await srvRejectPendingByBusinessEnd(docs);'));
      expect(run, contains('srvLifecycleCancelBulk(srvNotStartedOnly(docs), {'));
      expect(cf.contains('const ARCHIVE_CASCADE_LIMIT'), isFalse);
      expect(cf.contains('.limit(ARCHIVE_CASCADE_LIMIT)'), isFalse);
    });
    test('SF-32 사전 조회: 같은 질의를 같은 페이지로, 끝까지 못 읽으면 truncated', () {
      final pv = body('async function srvArchivePreview(');
      expect(pv, contains('scan(apps.where("status", "==", "PENDING")),'));
      expect(pv, contains('scan(apps.where("status", "==", "CONTRACT_PENDING")),'));
      expect(pv, contains('}, {deadlineMs, maxDocs: ARCHIVE_PREVIEW_MAX});'));
      expect(pv, contains('if (!r.complete) truncated = true;'));
      expect(pv, contains('const cls = srvArchiveCommitClass(d, worked, now);'));
      expect(pv, contains('out.canArchive = !srvArchiveBlocked(out);'));
      // 예전의 "열린 공고 기준" 대기·계약 대기 질의는 남아 있지 않다.
      expect(pv.contains('.where("toId", "in", ids)'), isFalse);
    });
    test('SF-33 실근무 계약 대기는 자동 취소·확정하지 않고 종료를 막는다', () {
      final c = body('function srvArchiveCommitClass(');
      expect(c, contains('if (app["status"] === "CONTRACT_PENDING" && actualWork) return "WORKED_CONTRACT_PENDING";'));
      expect(c, contains('if (!actualWork && srvScheduleNotStarted(app, nowMs)) return "FUTURE_CANCEL";'));
      expect(body('function srvArchiveBlocked('), contains('(p.contractPendingWorked as number) > 0 ||'));
    });
    test('SF-34 대기 마감은 건마다 트랜잭션으로 PENDING 을 다시 본다', () {
      final b = body('async function srvRejectPendingByBusinessEnd(');
      expect(b, contains('if (!fresh.exists || fresh.get("status") !== "PENDING") return false;'));
    });
  });

  group('SF-5 연쇄 페이지·재시도·종료 뒤 writer (ARCHIVE-CASCADE-PAGINATION)', () {
    test('SF-51 페이지 커서는 문서 id 뒤에서 잇는다(처리로 빠진 문서 때문에 건너뛰지 않는다)', () {
      final p = body('async function srvForEachIdPage(');
      expect(p, contains('let q = base.orderBy(admin.firestore.FieldPath.documentId()).limit(ARCHIVE_PAGE);'));
      expect(p, contains('if (last) q = q.startAfter(last);'));
      expect(p, contains('last = snap.docs[snap.docs.length - 1].id;'));
    });
    test('SF-52 미완료면 결과를 남기고 던진다 — 정상 종료로 숨기지 않는다', () {
      final trig = body('export const onBusinessDeactivated = onDocumentUpdated(', '\n);\n');
      expect(trig, contains('await srvRecordArchiveCascade(businessId, cascade);'));
      expect(trig, contains('if (cascade.state === "INCOMPLETE") {'));
      expect(trig, contains('throw new Error('));
      final run = body('async function srvRunBusinessArchiveCascade(');
      expect(run, contains('const state: SrvArchiveCascadeReport["state"] = c.failures > 0 || residual > 0 ? "INCOMPLETE" :'));
    });
    test('SF-53 알림은 표식으로 한 번 — 저장 실패는 실패로 센다', () {
      final run = body('async function srvRunBusinessArchiveCascade(');
      expect(run, contains('await d.ref.update({businessEndNotifiedAt: ts()});'));
      expect(run, contains('if (!ok.has(d.id)) {'));
      expect(body('function srvNeedsBusinessEndNotice('), contains('d["businessEndNotifiedAt"] == null &&'));
    });
    test('SF-54 재실행 callable: 종료된 사업장에만, 소유자·슈퍼관리자', () {
      final cb = body('export const callableRetryBusinessArchiveCascade = onCall(', '\n);\n');
      expect(cb, contains('if (!isSuper && bizSnap.get("ownerId") !== callerUid) {'));
      expect(cb, contains('if (bizSnap.get("deactivatedAt") == null) {'));
      expect(cb, contains('const r = await srvRunBusinessArchiveCascade(businessId);'));
    });
    test('SF-55 종료 뒤 재개·초대·지원은 트랜잭션 안에서 사업장을 본다', () {
      final upd = body('export const callableUpdateTO = onCall(', '\n);\n');
      expect('await srvAssertBizOpenInTx('.allMatches(upd).length, 2, reason: '재개 경로 + 일반 편집 경로');
      expect(body('export const callableReopenSlots = onCall(', '\n);\n'),
          contains('await srvAssertBizOpenInTx(tx, businessId, ARCHIVE_REOPEN_MESSAGE);'));
      expect(body('export const callableInviteWorker = onCall(', '\n);\n'),
          contains('await srvAssertBizOpenInTx(invTx, businessId,'));
      expect(body('export const callableApplyToTO = onCall(', '\n);\n'),
          contains('if (srvBizClosedForNewCommitment(applyTxBizSnap)) {'));
      expect(cf, contains('if (!bizSnapForMatch.exists || bizSnapForMatch.get("deactivatedAt") != null) {'));
    });
  });

  group('SF-4 종료 후 단기 출근', () {
    test('SF-41 근로자 본인 출근: 단기도 종료일부터 BUSINESS_CLOSED', () {
      final ci = body('export const callableCheckIn = onCall(', '\n);\n');
      expect(ci, contains('const ciShortClosedAt = bizSnap.get("deactivatedAt") as admin.firestore.Timestamp | undefined;'));
      expect(ci, contains('ciDayNum >= srvKstDateNum(ciShortClosedAt.toDate())) {'));
    });
    test('SF-42 관리자 일괄 출근: 근무 종류와 무관하게 같은 경계', () {
      final b = body('function srvArchivedNewWorkBlocked(');
      expect(b.contains('if (app["type"] !== "long_term") return false;'), isFalse);
      expect(b, contains('return !(typeof checkInMs === "number" && checkInMs < closedAt.toMillis());'));
    });
  });
}
