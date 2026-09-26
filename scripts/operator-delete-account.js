'use strict';
// [PRIVACY-REWRITE.1A] 운영자 계정 삭제 도구 — 앱 밖에서 실행한다.
//
//   웹으로 접수된 삭제 요청을 운영자가 처리한다. 앱 내 탈퇴는 본인이
//   재인증해야만 실행되므로, 앱을 지운 사람의 요청은 그 경로로 처리할 수
//   없다.
//
//   **앱에 callable 을 만들지 않는다.** 타인 계정을 지우는 권한이 앱 표면에
//   생기면 그 자체가 새 공격면이다. 이 도구는 배포되지 않고, 서비스 계정을
//   가진 운영자만 로컬에서 실행한다.
//
//   in-app 탈퇴(callableDeleteAccountPreData → Applications → Final)와
//   **같은 순서·같은 의미**로 처리한다. 순서를 바꾸면 중간 실패 시 복구가
//   어려워지고, 재가입 게이트가 열린 채 sentinel 만 풀리는 구간이 생긴다.
//
//   사용법:
//     node scripts/operator-delete-account.js --uid <uid> --request <id> \
//       --actor <운영자> --reason "<요청 근거>" [--apply]
//
//   --apply 가 없으면 아무것도 바꾸지 않고 계획만 출력한다.

process.chdir(require('path').join(__dirname, '..'));
const {db, admin} = require('./r7-fixture-lib.js');

const argv = process.argv.slice(2);
const arg = (k) => {
  const i = argv.indexOf(`--${k}`);
  return i >= 0 ? argv[i + 1] : undefined;
};
const UID = arg('uid');
const REQUEST = arg('request');
const ACTOR = arg('actor');
const REASON = arg('reason');
const APPLY = argv.includes('--apply');
const ANON = 'deleted_user';

if (!UID || !REQUEST || !ACTOR || !REASON) {
  console.error('필수: --uid --request --actor --reason  (실행은 --apply)');
  process.exit(1);
}

const log = [];
const step = (entity, action, before, after) => {
  log.push({entity, action, before, after});
  console.log(`  ${APPLY ? '실행' : '계획'}  ${entity.padEnd(26)} ${action}` +
    `  ${before} → ${after}`);
};

/** 컬렉션에서 한 필드가 uid 인 문서를 모은다. */
const where1 = async (col, field) =>
  (await db.collection(col).where(field, '==', UID).get()).docs;

(async () => {
  console.log(`\n═══ 운영자 계정 삭제 ${APPLY ? '(실행)' : '(계획)'} ═══`);
  console.log(`  uid=${UID}\n  요청=${REQUEST}  운영자=${ACTOR}\n  근거=${REASON}\n`);

  const userSnap = await db.collection('users').doc(UID).get();
  if (!userSnap.exists) {
    console.error('users 문서가 없습니다 — 이미 처리됐거나 잘못된 uid 입니다.');
    process.exit(1);
  }
  const u = userSnap.data();

  // ── 0. 차단 사유 — 앱 탈퇴가 막는 것과 같은 조건 ─────────
  const subAdminBizIds = (u.subAdminBusinessIds ?? []);
  if (subAdminBizIds.length > 0) {
    console.error(`중단: 서브관리자 직책이 ${subAdminBizIds.length}곳 남아 있습니다.`);
    process.exit(2);
  }
  const unsigned = (await db.collection('employment_contracts')
    .where('workerId', '==', UID).where('workerSignedAt', '==', null).get())
    .docs.filter((d) => !['VOID', 'EXPIRED'].includes(d.get('status')));
  if (unsigned.length > 0) {
    console.error(`중단: 미서명 근로계약 ${unsigned.length}건이 남아 있습니다.`);
    process.exit(2);
  }

  console.log('── 1. 사전 정리 (callableDeleteAccountPreData 와 동일) ──');

  // 1-a. deleted_accounts 기록 — sentinel 삭제보다 **먼저**.
  const role = (u.role ?? 'USER');
  const ciHash = u.ciHash;
  const phoneHash = u.phoneHash;
  const foreignFp = u.foreignIdentityFingerprint;
  const already = ciHash || foreignFp ?
    (await db.collection('deleted_accounts')
      .where('originalUid', '==', UID).limit(1).get()).docs.length > 0 : false;
  if ((ciHash || phoneHash || foreignFp) && !already) {
    step('deleted_accounts', 'ADD(+30일 재가입 제한)', '없음', '기록');
    if (APPLY) {
      const rec = {
        originalUid: UID, role,
        deletedAt: admin.firestore.Timestamp.now(),
        canReregisterAt: admin.firestore.Timestamp.fromMillis(
          Date.now() + 30 * 24 * 3600 * 1000),
        isBlacklisted: u.isBlacklisted === true,
        // 누가 왜 지웠는지 — 운영자 실행은 반드시 근거가 남는다.
        deletedBy: 'OPERATOR', operatorActor: ACTOR,
        operatorRequestId: REQUEST, operatorReason: REASON,
      };
      if (ciHash) rec.ciHash = ciHash;
      if (phoneHash) rec.phoneHash = phoneHash;
      if (foreignFp) rec.foreignIdentityFingerprint = foreignFp;
      await db.collection('deleted_accounts').add(rec);
    }
  } else {
    step('deleted_accounts', already ? 'SKIP(이미 기록)' : 'SKIP(식별값 없음)',
      '-', '-');
  }

  // 1-b. sentinel 삭제 — 기록 이후에만.
  for (const [col, val] of [
    ['nativeIdentityFingerprints', ciHash],
    ['foreignIdFingerprints', foreignFp],
  ]) {
    if (!val) { step(col, 'SKIP(값 없음)', '-', '-'); continue; }
    const id = `${val}_${role}`;
    const ex = (await db.collection(col).doc(id).get()).exists;
    step(col, 'DELETE', ex ? '있음' : '없음', '없음');
    if (APPLY && ex) await db.collection(col).doc(id).delete();
  }

  // 1-c. 즉시 삭제 대상.
  const taxEx = (await db.collection('taxIdentities').doc(UID).get()).exists;
  step('taxIdentities', 'DELETE', taxEx ? '있음' : '없음', '없음');
  if (APPLY && taxEx) await db.collection('taxIdentities').doc(UID).delete();

  for (const [col, field] of [
    ['idCardAccessRequests', 'targetUserId'],
    ['member_invitations', 'targetUid'],
  ]) {
    const docs = await where1(col, field);
    step(col, 'DELETE', `${docs.length}건`, '0건');
    if (APPLY) for (const d of docs) await d.ref.delete();
  }

  // 1-d. 식별자만 지우고 기록은 남기는 대상.
  for (const [col, field] of [
    ['review_requests', 'workerId'],
    ['monthly_reviews', 'targetUserId'],
    ['monthly_reviews', 'reviewerId'],
    ['trust_score_history', 'userId'],
    ['member_invitations', 'invitedBy'],
  ]) {
    const docs = await where1(col, field);
    step(`${col}.${field}`, 'ANONYMIZE', `${docs.length}건`, ANON);
    if (APPLY) for (const d of docs) await d.ref.update({[field]: ANON});
  }

  console.log('\n── 2. 관계 정리 (callableDeleteAccountApplications 와 동일) ──');
  const apps = await where1('applications', 'uid');
  const live = apps.filter((d) =>
    ['CONFIRMED', 'CONTRACT_PENDING', 'PENDING', 'INVITED'].includes(d.get('status')));
  step('applications', 'CANCELED', `활성 ${live.length}건`, 'CANCELED');
  if (APPLY) {
    for (const d of live) {
      await d.ref.update({
        status: 'CANCELED',
        canceledAt: admin.firestore.Timestamp.now(),
        canceledBy: 'OPERATOR',
      });
    }
  }
  const atts = await where1('attendance', 'userId');
  const sched = atts.filter((d) => d.get('status') === 'scheduled');
  step('attendance', 'absent(USER_DELETED)', `예정 ${sched.length}건`, 'absent');
  if (APPLY) {
    for (const d of sched) {
      await d.ref.update({status: 'absent', absentReason: 'USER_DELETED'});
    }
  }
  step('attendance(기록)', 'RETAIN(법정 보존)',
    `${atts.length - sched.length}건`, '유지');

  console.log('\n── 3. 문서·계정 (callableDeleteAccountFinal 과 동일) ──');
  // 3-a. Storage — 사용자 소유 경로.
  const bucket = admin.storage().bucket();
  let files = [];
  for (const prefix of [`users/${UID}/`, `id_cards/${UID}/`,
    `bankbooks/${UID}/`, `signatures/${UID}/`]) {
    const [fs] = await bucket.getFiles({prefix});
    files = files.concat(fs);
  }
  step('Storage(소유 문서)', 'DELETE', `${files.length}개`, '0개');
  if (APPLY) for (const f of files) await f.delete().catch(() => {});

  // 3-b. users 문서 → 3-c. Auth. 이 순서가 마지막이어야 재시도가 가능하다.
  step('users/{uid}', 'DELETE', '있음', '없음');
  if (APPLY) await db.collection('users').doc(UID).delete();

  let authEx = true;
  try { await admin.auth().getUser(UID); } catch (_) { authEx = false; }
  step('Auth 계정', 'DELETE', authEx ? '있음' : '없음', '없음');
  if (APPLY && authEx) {
    await admin.auth().deleteUser(UID).catch((e) => {
      if (e.code !== 'auth/user-not-found') throw e;
    });
  }

  // ── 4. 실행 기록 — 이메일 기억에 의존하지 않는다 ─────────
  if (APPLY) {
    await db.collection('account_deletion_records').add({
      requestId: REQUEST, actor: ACTOR, reason: REASON,
      targetUid: UID, targetRole: role,
      executedAt: admin.firestore.FieldValue.serverTimestamp(),
      steps: log.map((l) => `${l.entity}:${l.action}`),
      source: 'OPERATOR_OFF_APP',
    });
    console.log('\n  실행 기록을 account_deletion_records 에 남겼습니다.');
  }

  console.log(`\n═══ ${APPLY ? '완료' : '계획 출력 완료 — --apply 로 실행'} ═══\n`);
  process.exit(0);
})().catch((e) => { console.error('실패:', e.message); process.exit(1); });
