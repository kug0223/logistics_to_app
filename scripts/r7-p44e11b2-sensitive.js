/**
 * [R7-P4.4E.11B.2 §11·RT-14] sensitive user reader 가 cleanup 필드를 지운다.
 *
 *   `bankbookCleanupPendingPaths` 는 server-owned internal state 다.
 *   user 문서를 통째로 가져와 denylist 로 걸러 보내는 두 reader 가
 *   그 필드를 응답에서 제거해야 한다.
 *
 *   STEP B 직후(수동 seed)와 RT-14(실 writer 가 만든 state) 두 번 쓴다.
 *   인자로 `--phase=stepB|rt14` 를 받는다.
 */
'use strict';

const {
  admin, db, callAs, PREFIX, makeChecker, mask,
} = require('./r7-p44e11b2-lib');

const PHASE = (process.argv.find((a) => a.startsWith('--phase=')) || '--phase=stepB')
    .split('=')[1];
const RUN = PREFIX + 'sen' + Date.now().toString(36);
const SA = RUN + '_super';
const W = RUN + '_worker';
const SEEDED = `users/${W}/bankbook_1790000009999.jpg`;

(async () => {
  const c = makeChecker();
  console.log('phase =', PHASE, '/ fixture run =', RUN);

  for (const uid of [SA, W]) {
    try { await admin.auth().createUser({uid}); } catch (e) {
      if (e.code !== 'auth/uid-already-exists') throw e;
    }
  }
  await db.doc(`users/${SA}`).set({
    uid: SA, name: 'RT11B2 슈퍼', role: 'SUPER_ADMIN', accountStatus: 'active',
    passVerifiedAt: admin.firestore.Timestamp.now(),
  });
  // 응답에서 사라지면 안 되는 일반 필드도 같이 둔다 — 회귀 확인용.
  await db.doc(`users/${W}`).set({
    uid: W, name: 'RT11B2 근로자', role: 'USER', accountStatus: 'active',
    // [정정] callableGetAllUsers 는 `orderBy("createdAt","desc")` 로 읽는다.
    //   `createdAt` 이 없는 문서는 그 쿼리에서 **빠진다** — 처음엔 그걸
    //   모르고 fixture 에 넣지 않아 "목록에 없음"으로 나왔다. 응답 누락이
    //   아니라 내 fixture 가 쿼리 조건을 못 맞춘 것이었다.
    createdAt: admin.firestore.Timestamp.now(),
    passVerifiedAt: admin.firestore.Timestamp.now(), isIdVerified: true,
    bankName: '테스트은행', accountNumber: 'enc:rt11b2', accountHolder: 'RT11B2 근로자',
    bankbookImagePath: `users/${W}/bankbook_1790000010000.jpg`,
    bankbookDocumentVersion: 3, bankAccountVersion: 2,
    trustScore: 77,
    bankbookCleanupPendingPaths: [SEEDED],
  });

  console.log('\n=== callableGetUsersBatch ===');
  const batch = await callAs(SA, 'callableGetUsersBatch', {
    uids: [W], businessId: RUN + '_biz',
  });
  const u = (batch.users || {})[W] || {};
  const keys = Object.keys(u);
  c.check('cleanup 필드 노출 0', 'bankbookCleanupPendingPaths' in u, false);
  c.check('raw cleanup 경로가 응답 어디에도 없다',
      JSON.stringify(batch).includes(SEEDED), false);
  c.check('일반 필드는 그대로 온다 (name)', u.name, 'RT11B2 근로자');
  c.check('문서 버전도 그대로 온다', u.bankbookDocumentVersion, 3);
  c.check('readiness 포인터는 그대로 온다',
      typeof u.bankbookImagePath === 'string', true);
  c.check('기존 민감 필드 제거도 유지 (bankbookImageUrl)',
      'bankbookImageUrl' in u, false);
  c.note('응답 필드 수', keys.length);

  console.log('\n=== callableGetAllUsers ===');
  const all = await callAs(SA, 'callableGetAllUsers', {});
  const list = all.users || all.result || [];
  const mine = (Array.isArray(list) ? list : []).find((x) => x && x.uid === W);
  c.check('대상 사용자가 목록에 있다', !!mine, true);
  if (mine) {
    c.check('cleanup 필드 노출 0', 'bankbookCleanupPendingPaths' in mine, false);
    c.check('일반 필드는 그대로 온다 (name)', mine.name, 'RT11B2 근로자');
  }
  c.check('raw cleanup 경로가 응답 어디에도 없다',
      JSON.stringify(all).includes(SEEDED), false);

  // ── probe 완료 후 test-only 필드 제거 (§10) ──────────────────
  console.log('\n=== teardown ===');
  await db.doc(`users/${W}`).update({
    bankbookCleanupPendingPaths: admin.firestore.FieldValue.delete(),
  });
  const cleared = (await db.doc(`users/${W}`).get()).data();
  c.check('seed 한 test-only 필드 제거됨',
      'bankbookCleanupPendingPaths' in cleared, false);
  for (const uid of [SA, W]) {
    await db.doc(`users/${uid}`).delete().catch(() => {});
    await admin.auth().deleteUser(uid).catch(() => {});
  }
  const left = await db.collection('users').get();
  c.check('fixture Firestore 잔류 0',
      left.docs.filter((d) => d.id.startsWith(RUN)).length, 0);
  console.log('  fixture uid =', mask(SA), mask(W), '→ 삭제');

  const {fail} = c.summary();
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.error('실패:', e.message); process.exit(1); });
