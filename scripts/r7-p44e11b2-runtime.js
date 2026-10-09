/**
 * [R7-P4.4E.11B.2] RT-1 ~ RT-18 — bankbook writer/lifecycle DEV runtime.
 *
 *   핵심 질문은 하나다. 물리 삭제가 실패해도
 *     · canonical 상태는 전진하고
 *     · 그 bytes 에게 **주인**이 남고
 *     · readiness 는 거짓으로 true 가 되지 않는가
 *
 *   실패 주입은 fixture object 하나에 temporaryHold 를 거는 것뿐이다.
 *   버킷 IAM·Storage rules·서비스 계정은 건드리지 않는다(§52).
 */
'use strict';

const {
  admin, db, callAs, PREFIX,
  putObject, objExists, setHold, delObject, makeChecker, mask,
} = require('./r7-p44e11b2-lib');

const RUN = PREFIX + 'rt' + Date.now().toString(36);
const W = RUN + '_w';
const MGR = RUN + '_mgr';
const BIZ = RUN + '_biz';
const SA = RUN + '_super';
const uref = () => db.doc(`users/${W}`);

let seq = 1790000200000;
const nextPath = (uid = W, kind = 'bankbook') => `users/${uid}/${kind}_${seq++}.jpg`;

const snapU = async () => (await uref().get()).data() || {};
const pending = async () => ((await snapU()).bankbookCleanupPendingPaths) || [];
const curPath = async () => (await snapU()).bankbookImagePath;
/** 클라이언트 readiness 와 같은 식 (user_model.dart hasBankbookDocument). */
const ready = async () => {
  const u = await snapU();
  return !!((u.bankbookImagePath && u.bankbookImagePath.length) ||
            (u.bankbookImageUrl && u.bankbookImageUrl.length));
};
const versions = async () => {
  const u = await snapU();
  return {bb: u.bankbookDocumentVersion ?? 0, acc: u.bankAccountVersion ?? 0};
};

async function expectReject(c, label, fn) {
  try { await fn(); c.check(label, 'ALLOWED', 'REJECTED'); return null; } catch (e) {
    c.check(label, 'REJECTED', 'REJECTED', e.wireCode || e.httpStatus); return e;
  }
}

async function resetUser(extra = {}) {
  await uref().set({
    uid: W, name: 'RT11B2 근로자', role: 'USER', accountStatus: 'active',
    createdAt: admin.firestore.Timestamp.now(),
    passVerifiedAt: admin.firestore.Timestamp.now(), isIdVerified: true,
    bankName: '테스트은행', accountNumber: 'enc:rt11b2',
    accountHolder: 'RT11B2 근로자',
    bankbookDocumentVersion: 0, bankAccountVersion: 0,
    ...extra,
  });
}

(async () => {
  const c = makeChecker();
  console.log('fixture run =', RUN);
  const madeObjects = new Set();
  const put = async (p) => { await putObject(p); madeObjects.add(p); return p; };

  for (const uid of [W, MGR, SA]) {
    try { await admin.auth().createUser({uid}); } catch (e) {
      if (e.code !== 'auth/uid-already-exists') throw e;
    }
  }
  await db.doc(`businesses/${BIZ}`).set({
    name: 'RT11B2 사업장', ownerId: MGR, adminIds: [MGR],
    status: 'approved', isActive: true, createdAt: admin.firestore.Timestamp.now(),
  });
  await db.doc(`users/${MGR}`).set({
    uid: MGR, name: 'RT11B2 관리자', role: 'BUSINESS_ADMIN', businessId: BIZ,
    accountStatus: 'active', createdAt: admin.firestore.Timestamp.now(),
  });
  await db.doc(`users/${SA}`).set({
    uid: SA, name: 'RT11B2 슈퍼', role: 'SUPER_ADMIN', accountStatus: 'active',
    createdAt: admin.firestore.Timestamp.now(),
  });
  await resetUser();

  const mark = (p) => callAs(W, 'callableMarkBankbookVerified', {storagePath: p});

  // ══ RT-1 최초 등록 ═════════════════════════════════════════
  console.log('\n=== RT-1 최초 통장사본 등록 ===');
  const A = await put(nextPath());
  const r1 = await mark(A);
  c.check('callable 성공', r1.success, true);
  c.check('bankbookImagePath = A', await curPath(), A);
  c.check('A object 존재', await objExists(A), true);
  c.check('cleanup 대기 없음', (await pending()).length, 0);
  c.check('previousBankbookPath = null', r1.previousBankbookPath, null);
  c.check('cleanupPending = false', r1.cleanupPending, false);
  c.check('readiness true', await ready(), true);
  c.check('bankbookDocumentVersion = 1', (await versions()).bb, 1);

  // ══ RT-9 writer 네임스페이스 거부 ══════════════════════════
  console.log('\n=== RT-9 writer 가 통장사본 아닌 경로를 거부한다 ===');
  const idc = await put(nextPath(W, 'idCard'));
  const otherBb = await put(nextPath(RUN + '_w2'));
  const nested = await put(`users/${W}/sub/bankbook_${seq++}.jpg`);
  for (const [label, p] of [['같은 사용자 신분증', idc],
    ['타인 통장사본', otherBb], ['중첩 경로', nested],
    ['malformed', `users/${W}/bankbook_abc.jpg`]]) {
    await expectReject(c, `등록 거부 ← ${label}`, () => mark(p));
  }
  c.check('current 는 그대로 A', await curPath(), A);
  c.check('신분증 object 보존', await objExists(idc), true);
  c.check('타인 통장사본 보존', await objExists(otherBb), true);
  c.check('버전 증가 없음', (await versions()).bb, 1);

  // ══ RT-2 정상 교체 ════════════════════════════════════════
  console.log('\n=== RT-2 정상 교체 A → B ===');
  const B = await put(nextPath());
  const r2 = await mark(B);
  c.check('B 가 current', await curPath(), B);
  c.check('B object 존재', await objExists(B), true);
  c.check('A object 삭제됨', await objExists(A), false);
  c.check('cleanup 대기 0', (await pending()).length, 0);
  c.check('cleanupPending = false', r2.cleanupPending, false);
  c.check('previousBankbookPath = A (힌트)', r2.previousBankbookPath, A);
  c.check('bankbookDocumentVersion = 2', (await versions()).bb, 2);
  c.check('readiness true (B 기준)', await ready(), true);

  // ══ RT-3 교체 중 물리 삭제 실패 ═══════════════════════════
  console.log('\n=== RT-3 교체 — B 삭제 실패 주입 (temporaryHold) ===');
  await setHold(B, true);
  const C = await put(nextPath());
  const vBefore = (await versions()).bb;
  const r3 = await mark(C);
  c.check('callable 성공 — 등록이 실패로 바뀌지 않는다', r3.success, true);
  c.check('C 가 current', await curPath(), C);
  c.check('C object 존재', await objExists(C), true);
  c.check('B bytes 남아 있다', await objExists(B), true);
  c.check('B 가 cleanup 대기에 등록됐다', (await pending()).includes(B), true);
  c.check('cleanupPending = true', r3.cleanupPending, true);
  c.check('readiness true (C 기준)', await ready(), true);
  c.check('버전은 정확히 한 번만 증가', (await versions()).bb, vBefore + 1);

  // ══ RT-4 current-path 보호 ════════════════════════════════
  console.log('\n=== RT-4 current 는 대기 목록에 있어도 지워지지 않는다 ===');
  await uref().update({
    bankbookCleanupPendingPaths: admin.firestore.FieldValue.arrayUnion(C),
  });
  c.check('C 가 current 이면서 대기 목록에도 있다',
      (await pending()).includes(C) && (await curPath()) === C, true);
  // drain 을 일으키는 mutation: 같은 경로 재등록(= current 유지)
  const r4 = await callAs(W, 'callableMarkBankbookVerified', {storagePath: C});
  c.check('재등록 성공', r4.success, true);
  c.check('C object 가 살아 있다', await objExists(C), true);
  c.check('C 가 여전히 current', await curPath(), C);
  c.check('C 가 대기 목록에 남아 있다 (삭제 안 함)',
      (await pending()).includes(C), true);
  c.check('같은 경로 재등록은 previous 를 만들지 않는다',
      r4.previousBankbookPath, null);
  // 정리: C 를 대기에서 빼고 B hold 해제
  await uref().update({
    bankbookCleanupPendingPaths: admin.firestore.FieldValue.arrayRemove(C),
  });

  // ══ RT-3 recovery ═════════════════════════════════════════
  console.log('\n=== RT-3 recovery — hold 해제 후 다음 mutation 이 비운다 ===');
  await setHold(B, false);
  const D = await put(nextPath());
  const r5 = await mark(D);
  c.check('D 가 current', await curPath(), D);
  c.check('B 가 삭제됐다 (지연 cleanup 수렴)', await objExists(B), false);
  c.check('C 가 삭제됐다 (직전 current)', await objExists(C), false);
  c.check('대기 목록 최종 0', (await pending()).length, 0);
  c.check('cleanupPending = false', r5.cleanupPending, false);
  c.check('D object 는 살아 있다', await objExists(D), true);

  // ══ RT-7 not-found 멱등 ═══════════════════════════════════
  console.log('\n=== RT-7 object 없는 대기 항목은 성공 동치로 수렴한다 ===');
  const ghost = `users/${W}/bankbook_${seq++}.jpg`; // 업로드하지 않는다
  await uref().update({
    bankbookCleanupPendingPaths: admin.firestore.FieldValue.arrayUnion(ghost),
  });
  const E = await put(nextPath());
  const r6 = await mark(E);
  c.check('대기 목록에서 제거됐다', (await pending()).includes(ghost), false);
  c.check('오류 없이 성공', r6.success, true);
  c.check('cleanupPending = false', r6.cleanupPending, false);
  c.check('E 가 current', await curPath(), E);

  // ══ RT-8 오염된 대기 목록 ═════════════════════════════════
  console.log('\n=== RT-8 오염된 대기 목록 — cross-artifact 삭제 0 ===');
  const lic = await put(nextPath(W, 'businessLicense'));
  const prof = await put(nextPath(W, 'profile'));
  const bizNs = `businesses/${BIZ}/license/x_${seq++}.jpg`;
  await putObject(bizNs); madeObjects.add(bizNs);
  const contractNs = `contracts/${RUN}_k/signature_${seq++}.jpg`;
  await putObject(contractNs); madeObjects.add(contractNs);
  const poison = [idc, lic, prof, otherBb, bizNs, contractNs, nested];
  await uref().update({
    bankbookCleanupPendingPaths: admin.firestore.FieldValue.arrayUnion(...poison),
  });
  const F = await put(nextPath());
  const r7 = await mark(F);
  c.check('callable 성공', r7.success, true);
  for (const [label, p] of [['신분증', idc], ['사업자등록증 유사', lic],
    ['프로필 유사', prof], ['타인 통장사본', otherBb],
    ['business 네임스페이스', bizNs], ['contracts 네임스페이스', contractNs],
    ['중첩 경로', nested]]) {
    c.check(`${label} object 보존 (물리 삭제 0)`, await objExists(p), true);
  }
  const leftQ = await pending();
  c.check('invalid 항목은 목록에 남는다 (조용히 처리하지 않는다)',
      poison.every((p) => leftQ.includes(p)), true);
  c.check('직전 current(E) 는 정상 삭제됐다', await objExists(E), false);
  c.note('오염 후 대기 항목 수', leftQ.length);
  // 정리
  await uref().update({
    bankbookCleanupPendingPaths: admin.firestore.FieldValue.delete(),
  });

  // ══ RT-5 UpdateBankAccount cleanup 실패 ═══════════════════
  console.log('\n=== RT-5 계좌 변경 — 옛 통장사본 삭제 실패 주입 ===');
  c.check('사전 조건: F 가 current', await curPath(), F);
  await setHold(F, true);
  const v5 = await versions();
  const r8 = await callAs(W, 'callableUpdateBankAccount', {
    bankName: '변경은행', accountNumber: 'enc:rt11b2-new',
  });
  c.check('callable 성공 (던지지 않는다)', r8.success, true);
  c.check('cleanupPending = true', r8.cleanupPending, true);
  const u5 = await snapU();
  c.check('새 계좌 저장됨', u5.bankName, '변경은행');
  c.check('bankAccountVersion 정확히 +1', u5.bankAccountVersion, v5.acc + 1);
  c.check('bankbookDocumentVersion 정확히 +1', u5.bankbookDocumentVersion, v5.bb + 1);
  c.check('bankbookImagePath 제거됨', u5.bankbookImagePath, undefined);
  c.check('readiness false', await ready(), false);
  c.check('F bytes 남아 있다', await objExists(F), true);
  c.check('F 가 cleanup 대기에 있다', (await pending()).includes(F), true);
  c.check('[§32 금지상태] 삭제실패 + 옛 포인터 current + readiness true',
      ((await curPath()) === F) && (await ready()), false);

  // ══ RT-5 recovery ═════════════════════════════════════════
  console.log('\n=== RT-5 recovery ===');
  await setHold(F, false);
  const G = await put(nextPath());
  const r9 = await mark(G);
  c.check('G 가 current', await curPath(), G);
  c.check('F 가 삭제됐다', await objExists(F), false);
  c.check('대기 0', (await pending()).length, 0);
  c.check('cleanupPending = false', r9.cleanupPending, false);
  c.check('readiness true', await ready(), true);

  // ══ RT-6 DeleteBankInfo 물리 실패 + 재호출 멱등 ════════════
  console.log('\n=== RT-6 계좌 삭제 — 물리 삭제 실패 주입 ===');
  await setHold(G, true);
  const v6 = await versions();
  const e6 = await expectReject(c, 'callable 은 미완료를 말한다',
      () => callAs(W, 'callableDeleteBankInfo', {}));
  c.note('거부 코드', e6 && (e6.wireCode || e6.httpStatus));
  const u6 = await snapU();
  c.check('bankName 제거됨', u6.bankName, undefined);
  c.check('accountNumber 제거됨', u6.accountNumber, undefined);
  c.check('accountHolder 제거됨', u6.accountHolder, undefined);
  c.check('bankbookImagePath 제거됨', u6.bankbookImagePath, undefined);
  c.check('readiness false', await ready(), false);
  c.check('bankAccountVersion 정확히 +1', u6.bankAccountVersion, v6.acc + 1);
  c.check('bankbookDocumentVersion 정확히 +1', u6.bankbookDocumentVersion, v6.bb + 1);
  c.check('G bytes 남아 있다', await objExists(G), true);
  c.check('G 가 cleanup 대기에 있다', (await pending()).includes(G), true);

  console.log('\n=== RT-6 재호출 멱등성 ===');
  await setHold(G, false);
  const r10 = await callAs(W, 'callableDeleteBankInfo', {});
  c.check('재호출 성공', r10.success, true);
  const u6b = await snapU();
  c.check('bankAccountVersion 두 번째 증가 없음',
      u6b.bankAccountVersion, v6.acc + 1);
  c.check('bankbookDocumentVersion 두 번째 증가 없음',
      u6b.bankbookDocumentVersion, v6.bb + 1);
  c.check('G 가 삭제됐다', await objExists(G), false);
  c.check('대기 0', (await pending()).length, 0);
  c.check('readiness false 유지', await ready(), false);

  // ══ RT-13 backfill ════════════════════════════════════════
  console.log('\n=== RT-13 backfill positive / negative ===');
  const H = await put(nextPath());
  const bucket = admin.storage().bucket().name;
  const urlOf = (p) =>
    `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/${encodeURIComponent(p)}?alt=media`;
  await resetUser({bankbookImageUrl: urlOf(H), createdAt: admin.firestore.Timestamp.now()});
  const bf = await callAs(SA, 'callableBackfillBankbookImagePath',
      {dryRun: false, pageSize: 50});
  c.note('backfill 결과', {succeeded: bf.succeeded, failed: bf.failed,
    processed: bf.processed});
  c.check('legacy URL → exact 경로로 승격', await curPath(), H);

  console.log('  — negative: legacy URL 이 신분증이면 승격 금지');
  await resetUser({bankbookImageUrl: urlOf(idc), createdAt: admin.firestore.Timestamp.now()});
  await callAs(SA, 'callableBackfillBankbookImagePath', {dryRun: false, pageSize: 50});
  c.check('신분증 URL 은 승격되지 않는다', await curPath(), undefined);
  console.log('  — negative: legacy URL 이 타인 통장사본이면 승격 금지');
  await resetUser({bankbookImageUrl: urlOf(otherBb), createdAt: admin.firestore.Timestamp.now()});
  await callAs(SA, 'callableBackfillBankbookImagePath', {dryRun: false, pageSize: 50});
  c.check('타인 통장사본 URL 은 승격되지 않는다', await curPath(), undefined);

  // ══ RT-16 readiness 일관성 ════════════════════════════════
  console.log('\n=== RT-16 cleanup ownership ≠ readiness ===');
  await resetUser();
  const I = await put(nextPath());
  await mark(I);
  c.check('valid current → readiness true', await ready(), true);
  await uref().update({
    bankbookImagePath: admin.firestore.FieldValue.delete(),
    bankbookCleanupPendingPaths: admin.firestore.FieldValue.arrayUnion(I),
  });
  c.check('대기만 있고 current 없음 → readiness false', await ready(), false);
  const J = await put(nextPath());
  const r11 = await mark(J);
  c.check('교체 후 readiness 는 J 기준 true', await ready(), true);
  c.check('I 는 정리됐다', await objExists(I), false);
  c.check('대기 0', (await pending()).length, 0);
  c.note('마지막 cleanupPending', r11.cleanupPending);

  // ══ RT-18 queue cap 21건 ══════════════════════════════════
  console.log('\n=== RT-18 대기 21건 — cap 20, drop 0 ===');
  const many = [];
  for (let i = 0; i < 21; i++) many.push(await put(nextPath()));
  await uref().update({
    bankbookCleanupPendingPaths: admin.firestore.FieldValue.arrayUnion(...many),
  });
  c.check('대기 21건 등록', (await pending()).length, 21);
  const prevCur = await curPath();
  const K = await put(nextPath());
  await mark(K);
  const after1 = await pending();
  // [정정] 처음에 1 을 기대했는데 2 였다. 교체 자체가 **직전 current 를
  //   대기에 추가**하므로 drain 시작 시점의 목록은 21 이 아니라 22 다.
  //   cap 20 → 남는 것은 2. 설계대로이고, 내 산수가 교체분을 빼먹었다.
  c.check('drain 시작 시점 목록 = 21 + 직전 current 1 = 22 → cap 20 → 남은 2',
      after1.length, 2);
  c.check('처리되지 않은 항목이 버려지지 않았다 (seed 21건 중 1건 잔존)',
      many.filter((p) => after1.includes(p)).length, 1);
  c.check('직전 current 도 주인을 잃지 않았다',
      after1.includes(prevCur) || !(await objExists(prevCur)), true);
  const L = await put(nextPath());
  await mark(L);
  const after2 = await pending();
  c.check('두 번째 drain 후 대기 0', after2.length, 0);
  const survivors = [];
  for (const p of many) if (await objExists(p)) survivors.push(p);
  c.check('21건 전부 물리 삭제됨', survivors.length, 0);
  c.check('L 이 current 이고 살아 있다',
      (await curPath()) === L && (await objExists(L)), true);

  // ══ RT-14 실 writer state 로 SENSITIVE_FIELDS 재확인 ═══════
  console.log('\n=== RT-14 실 writer 가 만든 대기 state 에서 reader 재확인 ===');
  await setHold(L, true);
  const M = await put(nextPath());
  const r12 = await mark(M);
  c.check('실 writer 가 대기 항목을 만들었다', (await pending()).includes(L), true);
  c.check('cleanupPending = true', r12.cleanupPending, true);
  const batch = await callAs(SA, 'callableGetUsersBatch',
      {uids: [W], businessId: BIZ});
  const bu = (batch.users || {})[W] || {};
  c.check('GetUsersBatch 에 cleanup 필드 없음',
      'bankbookCleanupPendingPaths' in bu, false);
  c.check('응답 어디에도 대기 경로 문자열 없음',
      JSON.stringify(batch).includes(L), false);
  const all = await callAs(SA, 'callableGetAllUsers', {});
  const am = (all.users || []).find((x) => x && x.uid === W);
  c.check('GetAllUsers 에 cleanup 필드 없음',
      !!am && !('bankbookCleanupPendingPaths' in am), true);
  c.check('응답 어디에도 대기 경로 문자열 없음',
      JSON.stringify(all).includes(L), false);
  await setHold(L, false);

  // ══ RT-17 Task/Notification 0 ═════════════════════════════
  console.log('\n=== RT-17 cleanup 대기가 Task/알림을 만들지 않는다 ===');
  for (const col of ['notifications', 'document_corrections']) {
    try {
      const s = await db.collection(col).where('userId', '==', W).get();
      c.check(`${col} 에 fixture 관련 문서 0`, s.size, 0);
    } catch (e) {
      c.note(`${col} 조회 불가`, e.message.slice(0, 60));
    }
  }

  // ══ teardown (§55 순서: 대기 0 → Storage → Firestore → Auth) ══
  console.log('\n=== teardown ===');
  // [정정] 처음 실행에서 RT-14 가 남긴 대기 1건을 비우지 않고 fixture
  //   사용자 문서를 지웠다. §55 가 금지한 순서다 — cleanup owner 를 먼저
  //   없애면 그 bytes 가 untracked 가 된다. (그 회차에는 Storage fixture 를
  //   전부 명시 삭제했으므로 실제 고아는 생기지 않았지만, 순서 자체가
  //   틀렸다.) 지금은 정상 mutation 으로 먼저 비운다.
  if ((await pending()).length > 0) {
    const Z = await put(nextPath());
    await mark(Z);
    console.log('  대기 비우기용 정상 등록 1회 수행');
  }
  const finalPending = await pending();
  c.check('[§55] fixture 삭제 전 대기 0', finalPending.length, 0);
  let residual = 0;
  for (const p of madeObjects) { await delObject(p); if (await objExists(p)) residual++; }
  c.check('fixture Storage 잔류 0', residual, 0);
  for (const d of [`businesses/${BIZ}`, `users/${W}`, `users/${MGR}`, `users/${SA}`]) {
    await db.doc(d).delete().catch(() => {});
  }
  for (const uid of [W, MGR, SA]) await admin.auth().deleteUser(uid).catch(() => {});
  const left = await db.collection('users').get();
  c.check('fixture Firestore users 잔류 0',
      left.docs.filter((d) => d.id.startsWith(RUN)).length, 0);
  console.log('  fixture uid =', mask(W), mask(MGR), mask(SA), '→ 삭제');

  const {fail} = c.summary();
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.error('실패:', e.message, '\n', e.stack); process.exit(1); });
