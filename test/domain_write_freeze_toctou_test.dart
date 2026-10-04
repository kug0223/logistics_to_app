// [R7-P4.4E.11C.0C.0b] freeze 가 먼저 commit 된 뒤에도 약속이 생길 수 있었다
//
// begin-deletion 은 한 transaction 에서 두 값을 세운다.
//
//   account_deletion_tombstones/{uid}        ← canonical deletion truth
//   users/{uid}.accountStatus = "deleting"   ← live-user domain freeze projection
//
// 문제는 writer 쪽이었다. 여러 writer 가 `accountStatus` 를 **transaction
// 밖에서** 읽고 안에서 썼다. 그러면 이 순서가 성립한다.
//
//   T1 writer: active 읽음 (TX 밖)
//   T2 freeze : deleting commit
//   T1 writer: 새 Application / 근무 사실 commit     ← 금지 상태
//
// 그래서 lifecycle read 를 **그 쓰기와 같은 transaction** 으로 옮겼다.
// freeze transaction 이 `users/{uid}` 를 쓰므로, 경합하면 writer
// transaction 이 재시도되고 재시도에서 `deleting` 을 다시 관측해 거부된다.
//
// 반대 순서(writer-first)는 정상이다 — 먼저 commit 한 쪽이 이기고, 삭제
// 파이프라인이 그 새 truth 를 발견한다(`.0a` cleanup·residual·약속 blocker).
//
// 그리고 caller ≠ target 이다. 관리자가 active 라는 사실은 근로자가 탈퇴
// 중이 아니라는 뜻이 아니다. 확정·초대·대체업무 제안·일괄 출근은 모두
// **대상 근로자** 기준으로 본다.
//
// 고정하는 것
//   TOC-INV-*    active writer inventory 와 fence 위치
//   TOC-A-*      지원(Apply)
//   TOC-C-*      확정(Confirm)
//   TOC-ATT-*    근태 생성 writer 분류
//   TOC-CON-*    계약 writer 분류
//   TOC-AUTH-*   tombstone ↔ accountStatus 권위 선택
//   TOC-ERR-*    거부 semantics
//   TOC-NOTIF-*  실패 뒤 성공 알림 0
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('소스를 찾지 못했다: $p');
  return f.readAsStringSync();
}

String _codeOf(String src) => src
    .split(RegExp(r'\r?\n'))
    .where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
    })
    .join('\n');

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

int _at(String s, String needle) {
  final i = s.indexOf(needle);
  if (i < 0) throw StateError('경계를 찾지 못함: $needle');
  return i;
}

int _count(String s, String needle) {
  var n = 0;
  var i = 0;
  while (true) {
    final k = s.indexOf(needle, i);
    if (k < 0) return n;
    n++;
    i = k + needle.length;
  }
}

String _fn(String raw, String name) {
  final a = raw.indexOf('export const $name =');
  if (a < 0) throw StateError('$name 을 찾지 못함');
  var b = raw.indexOf('\nexport const', a + 10);
  if (b < 0) b = raw.length;
  return _codeOf(raw.substring(a, b));
}

String _helper(String raw, String name) {
  final a = raw.indexOf('function $name(');
  if (a < 0) throw StateError('$name 을 찾지 못함');
  final rel = raw.substring(a).indexOf('\n}');
  if (rel < 0) throw StateError('$name 의 끝을 찾지 못함');
  return _codeOf(raw.substring(a, a + rel));
}

/// writer 의 lifecycle fence 가 **transaction 안**이고 **첫 쓰기보다 앞**인가.
void _expectFencedInTx(
  String fn, {
  required String fence,
  required String firstWrite,
  String tx = 'runTransaction',
}) {
  final txAt = _at(fn, tx);
  final fenceAt = _at(fn, fence);
  final writeAt = _at(fn, firstWrite);
  expect(fenceAt, greaterThan(txAt),
      reason: 'fence 가 transaction 밖에 있다 — race window 가 열린다');
  expect(fenceAt, lessThan(writeAt),
      reason: 'fence 가 첫 쓰기보다 뒤에 있다 — 부분 mutation 이 가능해진다');
}

void main() {
  final raw = _src('functions/src/index.ts');
  final code = _codeOf(raw);
  final fenceThrow = _helper(raw, 'srvAssertAccountNotFrozenInTx');
  final fenceReason = _helper(raw, 'srvAccountFreezeReasonInTx');
  final notDeleting = _helper(raw, 'srvAssertNotDeletingAccount');
  final freeze = _helper(raw, 'srvEnsureAccountDeletionTombstone');
  final apply = _fn(raw, 'callableApplyToTO');
  final confirm = _fn(raw, 'callableConfirmApplication');
  final checkIn = _fn(raw, 'callableCheckIn');
  final batchCheckIn = _fn(raw, 'callableBatchCheckIn');
  final invite = _fn(raw, 'callableInviteWorker');
  final offer = _fn(raw, 'callableOfferAlternativeWork');
  final renewAccept = _fn(raw, 'callableAcceptRenewalProposal');
  final noShow = _fn(raw, 'callableBatchSetNoShow');

  group('TOC-INV — active writer inventory 와 fence', () {
    test('TOC-INV-01 fence 는 두 벌뿐이고 둘 다 TX read 다', () {
      // throw 버전과 분류 버전. 판정 규칙은 하나를 공유한다.
      expect(_flat(fenceThrow), contains(
          'const snap = await tx.get(db.collection("users").doc(uid));'));
      expect(_flat(fenceThrow), contains('srvAssertNotDeletingAccount(data);'));
      expect(_flat(fenceReason), contains(
          'const snap = await tx.get(db.collection("users").doc(uid));'));
      expect(_flat(fenceReason), contains(
          'if ((snap.data()?.["accountStatus"] as string | undefined) === '
          'ACCOUNT_STATUS_DELETING) { return "accountDeleting";'));
      // 새 lifecycle source 를 만들지 않았다.
      expect(code, contains('const ACCOUNT_STATUS_DELETING = "deleting";'));
      expect(_flat(notDeleting), contains(
          r'if ((data?.["accountStatus"] as string | undefined) === '
          'ACCOUNT_STATUS_DELETING) {'));
    });

    test('TOC-INV-02 patch 한 writer 7곳이 모두 TX 안에서 fence 한다', () {
      // Application 생성/전이 4 + 근태 생성 2 + 확정 1.
      _expectFencedInTx(apply,
          fence: 'srvAssertAccountNotFrozenInTx(tx, uid, "사용자")',
          firstWrite: 'tx.set(appRef, setData)');
      _expectFencedInTx(confirm,
          fence: 'srvAssertAccountNotFrozenInTx(tx, applicantUid, "근로자")',
          firstWrite: 'tx.set(lockRef');
      _expectFencedInTx(checkIn,
          fence: 'srvAssertAccountNotFrozenInTx(tx, callerUid, "사용자")',
          firstWrite: 'tx.set(ref, srvOmitUndefined(docData))');
      _expectFencedInTx(invite,
          fence: 'srvAssertAccountNotFrozenInTx(invTx, targetUid, "근로자")',
          firstWrite: 'invTx.set(newAppRef, appData)');
      _expectFencedInTx(offer,
          fence: 'srvAssertAccountNotFrozenInTx(offerTx, offerUid, "근로자")',
          firstWrite: 'offerTx.set(targetRef, offerAppData)');
      _expectFencedInTx(renewAccept,
          fence: 'srvAssertAccountNotFrozenInTx(tx, callerUid, "사용자")',
          firstWrite: 'tx.set(newRef, newData)');
      // 일괄 출근은 두 경로 각각.
      expect(_count(batchCheckIn, 'srvAccountFreezeReasonInTx(tx, userId)'), 2);
    });

    test('TOC-INV-03 이미 TX 안에서 보던 writer 는 그대로다', () {
      // 초대 수락(member) · 확정 재배치 수락 — 재패치하지 않는다.
      final acceptInv = _fn(raw, 'callableAcceptInvitation');
      _expectFencedInTx(acceptInv,
          fence: 'srvAssertNotDeletingAccount(userSnap.data())',
          firstWrite: 'tx.update(invRef');
      final reassign = _fn(raw, 'callableAcceptConfirmedReassignment');
      _expectFencedInTx(reassign,
          fence: r'if ((u.accountStatus as string | undefined) !== "active")',
          firstWrite: 'tx.set(acTargetRef, bDoc)');
    });

    test('TOC-INV-04 fence 는 users/{uid} 하나만 읽는다 (§16 최소)', () {
      // tombstone read 를 모든 writer 에 심지 않았다.
      for (final fn in [apply, confirm, checkIn, batchCheckIn, invite, offer,
        renewAccept]) {
        expect(fn, isNot(contains('srvDeletionBarrierExistsInTx')));
        expect(fn, isNot(contains('account_deletion_tombstones')));
      }
      expect(fenceThrow, isNot(contains('ACCOUNT_DELETION_TOMBSTONE_COL')));
      expect(fenceReason, isNot(contains('ACCOUNT_DELETION_TOMBSTONE_COL')));
    });
  });

  group('TOC-A — 지원(Apply)', () {
    test('TOC-A-01 정상 지원 경로의 전제는 그대로다 (A1)', () {
      // TX 밖의 가입 완료·제재·서류 gate 를 제거하지 않았다.
      expect(_flat(apply), contains(r'if (userData["accountStatus"] !== "active") {'));
      expect(apply, contains('srvMissingApplicantPayoutRegistration(userData)'));
      expect(apply, contains('isBlacklisted'));
      expect(apply, contains('restrictedUntil'));
    });

    test('TOC-A-02 fence 가 TX 의 첫 read 다 (A2·A3)', () {
      final txAt = _at(apply, 'runTransaction');
      final fenceAt = _at(apply, 'srvAssertAccountNotFrozenInTx(tx, uid, "사용자")');
      final firstAppRead = _at(apply, 'const existingInTx = await tx.get(appRef)');
      expect(fenceAt, greaterThan(txAt));
      expect(fenceAt, lessThan(firstAppRead));
    });

    test('TOC-A-03 지원 business semantics 를 바꾸지 않았다 (§6)', () {
      // TO/슬롯 fresh 재검증 · 정원 · 중복 guard · docId · 임금 출처.
      expect(apply, contains('const latestSlot = await tx.get(slotRef)'));
      expect(_flat(apply), contains('이미 지원한 업무입니다.'));
      expect(apply, contains('resolvedWdId'));
      expect(_flat(apply), contains('const appRef = db.collection("applications").doc(applyDocId);'));
    });

    test('TOC-A-04 writer-first 는 기존 cleanup 이 처리한다 (A4)', () {
      // 먼저 commit 된 PENDING 은 삭제 cleanup·residual 의 대상 집합에 있다.
      final residual = _helper(raw, 'srvCountDeletionDomainResidual');
      expect(_flat(residual), contains(
          r'.where("uid", "==", uid).where("status", "==", "PENDING").get()'));
      final cleanup = _fn(raw, 'callableDeleteAccountApplications');
      expect(_flat(cleanup), contains(r'.where("status", "==", "PENDING")'));
    });

    test('TOC-A-05 거부 시 카운터·알림이 0 이다 (§19)', () {
      // 카운터 증감은 모두 같은 TX 안이고 fence 보다 뒤다.
      final fenceAt = _at(apply, 'srvAssertAccountNotFrozenInTx(tx, uid, "사용자")');
      expect(_at(apply, 'tx.update('), greaterThan(fenceAt));
      // 알림은 TX 가 성공한 뒤에만 쓴다.
      expect(_at(apply, 'srvPersistNotification'),
          greaterThan(_at(apply, 'tx.set(appRef, setData)')));
    });
  });

  group('TOC-C — 확정(Confirm)', () {
    test('TOC-C-01 확정의 기존 invariant 순서를 깨지 않았다 (C1)', () {
      // 서류 검토 → 계약 준비 → lock → 겹침 → 정원 순서가 그대로다.
      expect(_at(confirm, 'confirmReviewGate'),
          lessThan(_at(confirm, 'runTransaction')));
      final fenceAt = _at(confirm, 'srvAssertAccountNotFrozenInTx(tx, applicantUid');
      expect(fenceAt, lessThan(_at(confirm, 'evaluateContractCapability')));
      expect(_at(confirm, 'evaluateContractCapability'),
          lessThan(_at(confirm, 'confirmation_locks')));
      expect(_at(confirm, 'confirmation_locks'),
          lessThan(_at(confirm, 'srvCollectSeatCommitOverlap')));
    });

    test('TOC-C-02 대상 근로자 fence 가 확정 TX 안이다 (C2·C5)', () {
      _expectFencedInTx(confirm,
          fence: 'srvAssertAccountNotFrozenInTx(tx, applicantUid, "근로자")',
          firstWrite: 'tx.set(lockRef');
      // 좌석·상태 쓰기도 모두 fence 뒤다.
      final fenceAt = _at(confirm, 'srvAssertAccountNotFrozenInTx(tx, applicantUid');
      expect(_at(confirm, 'tx.update('), greaterThan(fenceAt));
    });

    test('TOC-C-03 caller 가 아니라 target 을 본다 (C5·§10)', () {
      expect(confirm, contains('srvAssertAccountNotFrozenInTx(tx, applicantUid'));
      expect(confirm, isNot(contains('srvAssertAccountNotFrozenInTx(tx, callerUid')));
      // applicantUid 는 지원서에서 서버가 읽은 값이다 — 클라이언트 입력이 아니다.
      expect(_flat(confirm), contains('const applicantUid = appDataPre.uid as string | undefined;'));
    });

    test('TOC-C-04 writer-first 는 약속 blocker 가 발견한다 (C4)', () {
      // 먼저 확정됐으면 `.0a.6.2` 의 약속 gate 가 삭제를 멈춘다.
      final promise = _helper(raw, 'srvCountWithdrawPromiseScope');
      expect(_flat(promise), contains('CONFIRMED_STATUSES.map((st) =>'));
      final assertFn = _helper(raw, 'srvAssertAccountDeletionAllowed');
      expect(assertFn, contains('[CONFIRMED_WORKERS]'));
      // 그리고 residual 도 CONFIRMED 를 센다.
      final residual = _helper(raw, 'srvCountDeletionDomainResidual');
      expect(_flat(residual), contains(r'.where("status", "==", "CONFIRMED").get()'));
    });

    test('TOC-C-05 idempotent 재시도 경로는 막지 않는다 (§14)', () {
      // 이미 CONFIRMED / CONTRACT_PENDING 재시도는 쓰기가 없는 early-return
      // 이고, fence 는 그 **뒤**에 있다 — 성립한 약속의 후속 처리를
      // freeze 로 끊지 않는다.
      final fenceAt = _at(confirm, 'srvAssertAccountNotFrozenInTx(tx, applicantUid');
      expect(_at(confirm, 'alreadyConfirmed = true'), lessThan(fenceAt));
      expect(_at(confirm, 'isContractPendingRetry = true'), lessThan(fenceAt));
    });

    test('TOC-C-06 거부 시 알림 0 (§19·§20)', () {
      expect(_at(confirm, 'srvPersistNotification'),
          greaterThan(_at(confirm, 'runTransaction')));
      // 자동취소 알림도 TX 뒤다.
      expect(_at(confirm, 'txAutoCanceledDetails'),
          lessThan(_at(confirm, 'srvPersistNotification')));
    });
  });

  group('TOC-ATT — 근태 생성 writer 분류', () {
    test('TOC-ATT-01 callableCheckIn = MUST BLOCK, fence 는 TX 안 (§11)', () {
      _expectFencedInTx(checkIn,
          fence: 'srvAssertAccountNotFrozenInTx(tx, callerUid, "사용자")',
          firstWrite: 'tx.set(ref, srvOmitUndefined(docData))');
      // TX 밖 precheck 도 남겨 둔다 — UX 용 빠른 거부.
      expect(_flat(checkIn), contains(r'if (userData.accountStatus !== "active") {'));
    });

    test('TOC-ATT-02 일괄 출근 = MUST BLOCK, 사유를 분류로 돌려준다 (§12·§19)', () {
      // throw 하면 바깥 catch 가 unknownError 로 뭉갠다.
      expect(_count(batchCheckIn, 'srvAccountFreezeReasonInTx(tx, userId)'), 2);
      expect(_flat(batchCheckIn), contains('if (ciFrozen) return ciFrozen;'));
      expect(_flat(batchCheckIn), contains('if (ciNewFrozen) return ciNewFrozen;'));
      expect(_flat(fenceReason), contains('return "workerMissing";'));
      expect(_flat(fenceReason), contains('return "accountDeleting";'));
    });

    test('TOC-ATT-03 신규 생성 경로가 TX 안으로 들어왔다 (§17)', () {
      // 예전에는 기존 문서 조회가 TX 밖이고 생성이 `.set()` 단독이었다.
      expect(_flat(batchCheckIn), contains(
          'const newCiRef = db.collection("attendance").doc(docId);'));
      expect(_flat(batchCheckIn), contains('tx.set(newCiRef, srvOmitUndefined({'));
      expect(batchCheckIn, isNot(contains('db.collection("attendance").doc(docId).set(')));
      expect(batchCheckIn, isNot(contains('db.collection("attendance").doc(docId).get()')));
    });

    test('TOC-ATT-04 NO_SHOW = MAY CONTINUE — fence 를 넣지 않았다 (§13)', () {
      // 비근무 terminal 기록이고 금액 0 이다. 약속 불이행의 종결이므로
      // freeze 뒤에도 사업장이 끝낼 수 있어야 한다.
      expect(noShow, isNot(contains('srvAssertAccountNotFrozenInTx')));
      expect(noShow, isNot(contains('srvAccountFreezeReasonInTx')));
      expect(_flat(noShow), contains('status: "NO_SHOW"'));
      expect(_flat(noShow), contains('finalWage: 0'));
      // 그리고 그 기록은 돈 obligation 으로 세지 않는다.
      final nonPayable = _helper(raw, 'srvIsNonPayableZero');
      expect(_flat(nonPayable), contains(
          'return (status === "NO_SHOW" || status === "absent") && '
          '((finalWage ?? 0) === 0);'));
      // 새 근무 사실도 만들지 않는다 — checkIn 이 있으면 건너뛴다.
      expect(_flat(noShow), contains(r'if (snap.exists && snap.data()!.checkIn != null) {'));
    });

    test('TOC-ATT-05 자동 NO_SHOW·결근 = MAY CONTINUE (§13)', () {
      // 과거 약속의 lifecycle 종결이다. 그리고 삭제 residual 은
      // scheduled 만 세므로 모순이 생기지 않는다.
      final residual = _helper(raw, 'srvCountDeletionDomainResidual');
      expect(_flat(residual), contains(
          r'.where("userId", "==", uid).where("status", "==", "scheduled").get()'));
      expect(residual, isNot(contains('"NO_SHOW"')));
      expect(residual, isNot(contains('"absent"')));
      // 자동 결근은 기존 scheduled row 를 종결할 뿐 새로 만들지 않는다.
      final autoAbsent = _helper(raw, 'processAutoAbsent');
      expect(_flat(autoAbsent), contains(r'.where("status", "==", "scheduled")'));
      expect(_flat(autoAbsent), contains('batch.update(doc.ref, { status: "absent",'));
    });
  });

  group('TOC-CON — 계약 writer 분류', () {
    test('TOC-CON-01 서명 완료 = MAY CONTINUE, 상류에서 이미 닫혀 있다 (§14)', () {
      // 서명은 이미 성립한 약속의 **문서화**다. 그리고 미서명 계약이 있는
      // 근로자는 애초에 탈퇴를 시작할 수 없다.
      final worker = _fn(raw, 'callableFinalizeWorkerSignature');
      expect(worker, isNot(contains('srvAssertAccountNotFrozenInTx')));
      final assertFn = _helper(raw, 'srvAssertAccountDeletionAllowed');
      expect(_flat(assertFn), contains(r'.where("workerSignedAt", "==", null)'));
      expect(_flat(assertFn), contains('미서명 계약서'));
    });

    test('TOC-CON-02 연장 수락 = MUST BLOCK, 제안 생성은 제안일 뿐이다', () {
      expect(renewAccept, contains('srvAssertAccountNotFrozenInTx(tx, callerUid'));
      // 관리자 단독 연장 생성 경로는 비활성화되어 있다.
      final createRenewal = _fn(raw, 'callableCreateContractRenewal');
      expect(_flat(createRenewal), contains('계약 연장은 근무자의 수락이 필요합니다.'));
      // 재배치 제안도 수락 시점에 fence 된다.
      final reassign = _fn(raw, 'callableAcceptConfirmedReassignment');
      expect(_flat(reassign), contains(r'if ((u.accountStatus as string | undefined) !== "active")'));
    });
  });

  group('TOC-AUTH — tombstone ↔ accountStatus 권위', () {
    test('TOC-AUTH-01 user 문서가 없으면 거부한다 — Auth-tail 구간도 닫힌다', () {
      expect(_flat(fenceThrow), contains(
          'if (!snap.exists) { throw new HttpsError("not-found",'));
      expect(_flat(fenceReason), contains(
          'if (!snap.exists) return "workerMissing";'));
    });

    test('TOC-AUTH-02 두 값이 같은 transaction 에서 세워진다 (근거)', () {
      expect(_flat(freeze), contains('await db.runTransaction(async (tx) => {'));
      expect(_flat(freeze), contains('tx.set(tombRef, {'));
      expect(_flat(freeze), contains(
          'tx.update(userRef, {accountStatus: ACCOUNT_STATUS_DELETING});'));
      // freeze 가 users/{uid} 를 **쓴다** — 그래서 writer TX 의 read-set 에
      //   그 문서가 들어가면 경합 시 재시도된다.
      expect(_flat(freeze), contains('tx.get(userRef)'));
    });

    test('TOC-AUTH-03 새 lifecycle source 를 만들지 않았다 (§16)', () {
      // 판정 값은 기존 두 개뿐이다.
      expect(code, contains(
          'const ACCOUNT_DELETION_TOMBSTONE_COL = "account_deletion_tombstones";'));
      expect(_count(code, 'const ACCOUNT_STATUS_DELETING ='), 1);
      expect(_count(code, 'function srvAssertAccountNotFrozenInTx('), 1);
      expect(_count(code, 'function srvAccountFreezeReasonInTx('), 1);
    });
  });

  group('TOC-ERR — 거부 semantics (§18)', () {
    test('TOC-ERR-01 freeze 거부는 business rejection 이다', () {
      // 메시지는 기존 helper 하나가 소유한다 — 새 문구를 만들지 않았다.
      expect(_flat(notDeleting), contains(
          'throw new HttpsError( "failed-precondition", "탈퇴 처리 중인 계정입니다.");'));
      expect(fenceThrow, isNot(contains('"internal"')));
      expect(fenceReason, isNot(contains('"internal"')));
    });

    test('TOC-ERR-02 fence 가 오류를 삼키지 않는다', () {
      expect(fenceThrow, isNot(contains('catch')));
      expect(fenceReason, isNot(contains('catch')));
      // 식별자 위생 — 경로 주입을 통과시키지 않는다.
      expect(_flat(fenceThrow), contains(r'uid.includes("/") || uid.includes("..")'));
      expect(_flat(fenceReason), contains(r'uid.includes("/") || uid.includes("..")'));
    });
  });

  group('TOC-NOTIF — 실패 뒤 성공 알림 0 (§20)', () {
    test('TOC-NOTIF-01 알림은 domain commit 뒤에만 쓴다', () {
      // 초대·대체제안·지원·확정 모두 TX 성공 뒤에 알림을 만든다.
      expect(_at(invite, 'srvPersistNotification'),
          greaterThan(_at(invite, 'invTx.set(newAppRef, appData)')));
      // 대체업무 제안은 알림 쓰기를 함수로 정의해 두고 **커밋된 뒤** 부른다.
      //   정의 위치가 아니라 호출 위치가 계약이다.
      expect(_at(offer, 'const notifResult = await writeOfferedNotification(offerId)'),
          greaterThan(_at(offer, 'offerTx.set(targetRef, offerAppData)')));
      // notification architecture 는 이번 Phase 에서 바꾸지 않았다.
      expect(code, contains('async function srvPersistNotificationWithId('));
    });
  });
}
