/**
 * [R7-P4.4E.11B.2 §8·RT-15] rules 권위 runtime probe.
 *
 *   `bankbookCleanupPendingPaths` 는 server-owned 다. 클라이언트가
 *   직접 만들거나 바꾸거나 비울 수 없어야 한다. Admin SDK 는 canonical
 *   server writer 이므로 rules 우회가 정상이다.
 *
 *   rules 를 **지나는** 경로로만 묻는다 — 실 ID 토큰 + Firestore REST.
 */
'use strict';

const {
  admin, db, PREFIX, clientPatch, clientCreate, str, arr, makeChecker, mask,
} = require('./r7-p44e11b2-lib');

const RUN = PREFIX + 'rul' + Date.now().toString(36);
const U = RUN + '_worker';
const SA = RUN + '_super';

(async () => {
  const c = makeChecker();
  console.log('fixture run =', RUN);

  // ── fixture: disposable USER + SUPER_ADMIN ──────────────────
  for (const uid of [U, SA]) {
    try { await admin.auth().createUser({uid}); } catch (e) {
      if (e.code !== 'auth/uid-already-exists') throw e;
    }
  }
  await db.doc(`users/${U}`).set({
    uid: U, name: 'RT11B2 근로자', role: 'USER', accountStatus: 'active',
    passVerifiedAt: admin.firestore.Timestamp.now(), isIdVerified: true,
  });
  await db.doc(`users/${SA}`).set({
    uid: SA, name: 'RT11B2 슈퍼', role: 'SUPER_ADMIN', accountStatus: 'active',
    passVerifiedAt: admin.firestore.Timestamp.now(),
  });

  const victimPath = `users/${U}/bankbook_1790000000000.jpg`;

  console.log('\n=== §8 owner direct UPDATE 차단 ===');
  let r = await clientPatch(U, `users/${U}`,
      {bankbookCleanupPendingPaths: arr([str(victimPath)])});
  c.check('owner 가 cleanup 필드를 직접 쓴다 → 거부', r.status, 403, 'HTTP');

  console.log('\n=== §8 owner 가 비우기(clear) 시도도 차단 ===');
  // 서버가 심어 둔 상태를 클라이언트가 지울 수 있으면 주인을 잃는다.
  await db.doc(`users/${U}`).update({
    bankbookCleanupPendingPaths: admin.firestore.FieldValue.arrayUnion(victimPath),
  });
  r = await clientPatch(U, `users/${U}`, {bankbookCleanupPendingPaths: arr([])});
  c.check('owner 가 cleanup 필드를 비운다 → 거부', r.status, 403, 'HTTP');
  const after = (await db.doc(`users/${U}`).get()).data();
  c.check('서버가 심은 항목이 그대로 남는다',
      (after.bankbookCleanupPendingPaths || []).length, 1);
  await db.doc(`users/${U}`).update({
    bankbookCleanupPendingPaths: admin.firestore.FieldValue.delete(),
  });

  console.log('\n=== §8 CREATE injection 차단 ===');
  const newUid = RUN + '_fresh';
  try { await admin.auth().createUser({uid: newUid}); } catch (e) {
    if (e.code !== 'auth/uid-already-exists') throw e;
  }
  r = await clientCreate(newUid, 'users', newUid, {
    uid: str(newUid), name: str('RT11B2 신규'), role: str('USER'),
    bankbookCleanupPendingPaths: arr([str(`users/${newUid}/bankbook_1790000000001.jpg`)]),
  });
  c.check('가입 시 cleanup 필드를 끼워 넣는다 → 거부', r.status, 403, 'HTTP');
  const freshDoc = await db.doc(`users/${newUid}`).get();
  c.check('그 문서가 만들어지지 않았다', freshDoc.exists, false);

  console.log('\n=== §8 SUPER_ADMIN client SDK 직접 쓰기도 차단 ===');
  r = await clientPatch(SA, `users/${U}`,
      {bankbookCleanupPendingPaths: arr([str(victimPath)])});
  c.check('SUPER_ADMIN 이 타인 cleanup 필드를 쓴다 → 거부', r.status, 403, 'HTTP');

  console.log('\n=== §8 무관한 정상 user update 는 그대로 허용 ===');
  // [정정] 처음에 `name` 으로 control 을 잡았는데 403 이 나왔다. 그건
  //   rules 가 깨진 것이 아니다 — `name`/`legalName`/`koreanName` 은
  //   883fc6a 시점에도 self-update denylist 에 있었다(신원 필드, PASS
  //   인증에서 서버가 정한다). 내 probe 가 금지 필드를 고른 것이었다.
  //   클라이언트가 실제로 쓰는 필드로 control 을 다시 잡는다.
  r = await clientPatch(U, `users/${U}`, {fcmToken: str('rt11b2-token')});
  c.check('본인 fcmToken 수정 → 허용', r.status, 200, 'HTTP');
  const okDoc = (await db.doc(`users/${U}`).get()).data();
  c.check('실제로 반영됐다', okDoc.fcmToken, 'rt11b2-token');

  // denylist 가 의도대로 계속 막는다는 것도 같이 남긴다 (회귀 방향 확인).
  r = await clientPatch(U, `users/${U}`, {name: str('RT11B2 이름변경')});
  c.check('본인 name 수정 → 거부 (기존 동작 유지)', r.status, 403, 'HTTP');

  console.log('\n=== Admin SDK 는 canonical writer — 우회 정상 ===');
  await db.doc(`users/${U}`).update({
    bankbookCleanupPendingPaths: admin.firestore.FieldValue.arrayUnion(victimPath),
  });
  const adm = (await db.doc(`users/${U}`).get()).data();
  c.check('Admin SDK 쓰기는 성공한다',
      (adm.bankbookCleanupPendingPaths || []).length, 1);

  // ── teardown ────────────────────────────────────────────────
  console.log('\n=== teardown ===');
  for (const uid of [U, SA, newUid]) {
    await db.doc(`users/${uid}`).delete().catch(() => {});
    await admin.auth().deleteUser(uid).catch(() => {});
  }
  const left = await db.collection('users').get();
  const residual = left.docs.filter((d) => d.id.startsWith(RUN)).length;
  c.check('fixture Firestore 잔류 0', residual, 0);
  console.log('  fixture uid =', mask(U), mask(SA), mask(newUid), '→ 삭제');

  const {fail} = c.summary();
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.error('실패:', e.message); process.exit(1); });
