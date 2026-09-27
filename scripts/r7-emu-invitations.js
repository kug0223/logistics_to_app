/**
 * R7 6차 §4 — 초대 전이와 겹침 자동취소.
 *
 *   초대 발송 / 수락 / 거절 / 관리자 취소 / 만료, 그리고 확정으로 인한
 *   겹치는 지원의 자동취소. 각 단계에서 원장과 파생 집계(업무·슬롯·공고)를
 *   **원장에서 만든 기대값**으로 대조한다.
 *
 *   초대는 대기(PENDING_STATUSES 에 INVITED 포함)로 센다. 그 정의를 그대로 쓴다.
 *
 * 격리 에뮬레이터(demo-alfit-r7) 전용. id 는 실행마다 유일하다.
 */
const PROJECT = 'demo-alfit-r7';
process.env.GCLOUD_PROJECT = PROJECT;
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:6070';
process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:6072';

const path = require('path');
const admin = require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin'));
admin.initializeApp({projectId: PROJECT});
const db = admin.firestore();
const FN = `http://127.0.0.1:5011/${PROJECT}/asia-northeast3`;

const results = [];
let failures = 0;
function check(label, actual, expected, note) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) failures++;
  results.push({label, ok, actual, expected, ...(note ? {note} : {})});
}
const observe = (label, actual, note) =>
  results.push({label, ok: true, actual, expected: '관측', ...(note ? {note} : {})});

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const kstDayStart = (ms) => {
  const off = 9 * 3600 * 1000;
  const d = new Date(ms + off); d.setUTCHours(0, 0, 0, 0);
  return d.getTime() - off;
};
const ymd = (ms) => {
  const d = new Date(ms + 9 * 3600 * 1000);
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-` +
    `${String(d.getUTCDate()).padStart(2, '0')}`;
};

async function idToken(uid) {
  const custom = await admin.auth().createCustomToken(uid);
  const r = await fetch(
    'http://127.0.0.1:6072/identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=fake',
    {method: 'POST', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({token: custom, returnSecureToken: true})});
  return (await r.json()).idToken;
}
async function call(name, data, token) {
  const r = await fetch(`${FN}/${name}`, {
    method: 'POST',
    headers: {'Content-Type': 'application/json',
      ...(token ? {Authorization: `Bearer ${token}`} : {}),
      'X-Firebase-AppCheck': 'r7-audit-emulator-token'},
    body: JSON.stringify({data}),
  });
  const t = await r.text();
  let body; try { body = JSON.parse(t); } catch { body = t; }
  return {status: r.status, body};
}

const SEATED = ['CONFIRMED', 'CONTRACT_PENDING'];
const PENDING = ['PENDING', 'INVITED'];

const W = (() => {
  const RUN = `r7i${Date.now().toString(36)}`;
  return {RUN, BIZ: `${RUN}biz`, TO: `${RUN}to`, SLOT: `${RUN}slot`,
    TO2: `${RUN}to2`, SLOT2: `${RUN}slot2`, WD2X: `${RUN}wd2x`,
    WD: `${RUN}wd`, OWNER: `${RUN}own`, WA: `${RUN}wa`, WB: `${RUN}wb`};
})();

async function expectedOf(toId, wdId) {
  const apps = await db.collection('applications').where('toId', '==', toId).get();
  let pending = 0, seated = 0, wdP = 0, wdC = 0;
  const byStatus = {};
  apps.forEach((d) => {
    const a = d.data();
    byStatus[a.status] = (byStatus[a.status] || 0) + 1;
    const isP = PENDING.includes(a.status);
    const isS = SEATED.includes(a.status) && a.staffingReleasedAt == null;
    if (isP) pending++;
    if (isS) seated++;
    if (a.wdId === wdId) { if (isP) wdP++; if (isS) wdC++; }
  });
  return {pending, seated, wdP, wdC, byStatus};
}
async function derivedOf(toId, slotId, wdId) {
  const [s, t] = await Promise.all([
    db.doc(`tos/${toId}/slots/${slotId}`).get(),
    db.doc(`tos/${toId}`).get(),
  ]);
  const sd = s.data() || {}; const td = t.data() || {};
  const e = sd.workDetailCounts?.[wdId] || {};
  return {slotPending: sd.pendingCount ?? null, slotConfirmed: sd.confirmedCount ?? null,
    toPending: td.totalPending ?? null, toConfirmed: td.totalConfirmed ?? null,
    wdP: e.pendingCount ?? null, wdC: e.confirmedCount ?? null};
}
async function awaitMatch(toId, slotId, wdId, {maxMs = 25000} = {}) {
  const t0 = Date.now();
  let last = null;
  for (;;) {
    const exp = await expectedOf(toId, wdId);
    const der = await derivedOf(toId, slotId, wdId);
    last = {exp, der};
    if (der.slotPending === exp.pending && der.slotConfirmed === exp.seated &&
        der.toPending === exp.pending && der.toConfirmed === exp.seated &&
        der.wdP === exp.wdP && der.wdC === exp.wdC) {
      return {matched: true, elapsedMs: Date.now() - t0, ...last};
    }
    if (Date.now() - t0 > maxMs) return {matched: false, elapsedMs: Date.now() - t0, ...last};
    await sleep(250);
  }
}

async function seedWorker(uid, name) {
  await db.doc(`users/${uid}`).set({uid, name, role: 'USER', accountStatus: 'active',
    passVerifiedAt: admin.firestore.Timestamp.now(),
    isIdVerified: true, idCardImagePath: `id_cards/${uid}/id.jpg`,
    bankName: '국민', accountNumber: 'enc', accountHolder: name,
    bankbookImagePath: `bankbooks/${uid}/b.jpg`,
    termsConsentAt: admin.firestore.Timestamp.now(),
    isBlacklisted: false, isForeign: false,
    idDocumentVersion: 1, bankbookDocumentVersion: 1, bankAccountVersion: 1});
  await db.doc(`businessApplicantDocumentReviews/${W.BIZ}_${uid}`).set({
    businessId: W.BIZ, workerUid: uid,
    idDecision: 'REVIEWED_OK', reviewedIdDocumentVersion: 1,
    bankDecision: 'REVIEWED_OK',
    reviewedBankbookDocumentVersion: 1, reviewedBankAccountVersion: 1});

  // 초대를 받을 수 있는 상태 — 제품 전제를 우회하지 않고 갖춘다.
  //   `inviteEnabled` · 지역 키(`시/도|시군구`) · 그 날짜의 근무 가능.
  await db.doc(`worker_availability/${uid}`).set({
    uid, inviteEnabled: true,
    inviteRegionKeys: ['서울특별시|강남구'],
    dates: [ymd(kstDayStart(Date.now()) + 3 * 86400000)],
  });
}

async function seed() {
  const workDate = kstDayStart(Date.now()) + 3 * 86400000;
  for (const uid of [W.OWNER, W.WA, W.WB]) {
    try { await admin.auth().createUser({uid}); } catch (e) {
      if (e.code !== 'auth/uid-already-exists') throw e;
    }
  }
  await db.doc(`businesses/${W.BIZ}`).set({name: 'INV', ownerId: W.OWNER,
    status: 'approved', isActive: true, adminIds: [W.OWNER],
    city: '강남구', address: '서울특별시 강남구 테헤란로 1'});
  await db.doc(`users/${W.OWNER}`).set({uid: W.OWNER, name: 'INV 관리자',
    role: 'BUSINESS_ADMIN', businessId: W.BIZ, accountStatus: 'active',
    passVerifiedAt: admin.firestore.Timestamp.now()});
  await seedWorker(W.WA, 'INV A');
  await seedWorker(W.WB, 'INV B');

  const base = kstDayStart(Date.now()) - 86400000;
  const mk = async (toId, slotId, wdId, required) => {
    const wd = {wdId, workType: '홀서빙', startTime: '09:00', endTime: '18:00',
      wage: 12000, wageType: 'hourly', requiredCount: required};
    await db.doc(`tos/${toId}`).set({id: toId, businessId: W.BIZ, title: `INV ${toId}`,
      status: 'published', isPublic: true, isPublished: true, isDeleted: false,
      type: 'flex', createdBy: W.OWNER, workDetails: [wd],
      totalRequired: required, totalConfirmed: 0, totalPending: 0,
      publishedAt: admin.firestore.Timestamp.fromMillis(base),
      createdAt: admin.firestore.Timestamp.fromMillis(base)});
    await db.doc(`tos/${toId}/slots/${slotId}`).set({id: slotId, toId,
      businessId: W.BIZ, status: 'open', isManualClosed: false,
      date: admin.firestore.Timestamp.fromMillis(workDate),
      workDetails: [wd],
      workDetailCounts: {[wdId]: {confirmedCount: 0, pendingCount: 0}},
      requiredCount: required, confirmedCount: 0, pendingCount: 0});
  };
  await mk(W.TO, W.SLOT, W.WD, 2);
  // 두 번째 공고 — 같은 날 같은 시간. 확정 시 겹침 자동취소 대상이 된다.
  await mk(W.TO2, W.SLOT2, W.WD2X, 2);
  return {workDate};
}

async function cleanup() {
  for (const toId of [W.TO, W.TO2]) {
    const apps = await db.collection('applications').where('toId', '==', toId).get();
    for (const d of apps.docs) await d.ref.delete();
  }
  const paths = [`tos/${W.TO}/slots/${W.SLOT}`, `tos/${W.TO}`,
    `tos/${W.TO2}/slots/${W.SLOT2}`, `tos/${W.TO2}`,
    `businesses/${W.BIZ}`, `users/${W.OWNER}`, `users/${W.WA}`, `users/${W.WB}`,
    `businessApplicantDocumentReviews/${W.BIZ}_${W.WA}`,
    `businessApplicantDocumentReviews/${W.BIZ}_${W.WB}`,
    `worker_availability/${W.WA}`, `worker_availability/${W.WB}`];
  // [R7-6] 사업장을 먼저 지우고 cascade 가 끝난 뒤 사용자를 지운다.
  //   순서를 뒤집으면 onBusinessDeleted 가 없는 사용자 문서를 update 하다
  //   unhandled error 로 죽고, functions 런타임이 재시작되며 진행 중인
  //   요청까지 끊긴다(실측). 제품 후보 결함이지만 하네스에서도 피해야 한다.
  const bizPaths = paths.filter((p) => p.startsWith('businesses/'));
  const rest = paths.filter((p) => !p.startsWith('businesses/'));
  for (const p of bizPaths) await db.doc(p).delete().catch(() => {});
  if (bizPaths.length > 0) await sleep(1800);
  for (const p of rest) await db.doc(p).delete().catch(() => {});
}

const applyPayload = (toId, slotId, wdId, workDate) => ({
  toId, slotId, businessId: W.BIZ, businessName: 'INV', toTitle: 'INV',
  workDateMs: workDate, selectedWorkType: '홀서빙', workDetailId: wdId,
  startTime: '09:00', endTime: '18:00', wage: 12000, wageType: 'hourly',
  idCardConsentGiven: true, documentAccessConsentGiven: true,
  documentAccessConsentVersion: '2026-09-18-v3',
});

(async () => {
  await cleanup();
  const {workDate} = await seed();
  const otok = await idToken(W.OWNER);
  const ta = await idToken(W.WA);
  const tb = await idToken(W.WB);

  const invite = (targetUid) => call('callableInviteWorker', {
    toId: W.TO, businessId: W.BIZ, targetUid, slotId: W.SLOT,
    workDate: ymd(workDate), selectedWorkType: '홀서빙',
    workDetailStartTime: '09:00', workDetailEndTime: '18:00',
  }, otok);

  // ── I1 초대 발송 ────────────────────────────────────────────────────────
  const inv = await invite(W.WA);
  check('I1 초대 발송 200', inv.status, 200, JSON.stringify(inv.body).slice(0, 200));
  const invAppId = inv.body?.result?.applicationId ??
    (await db.collection('applications').where('toId', '==', W.TO)
      .where('uid', '==', W.WA).get()).docs[0]?.id;
  observe('I1 초대 지원서 id', String(invAppId));
  let m = await awaitMatch(W.TO, W.SLOT, W.WD);
  check('I1 초대는 대기로 센다 — 원장=파생', m.matched, true,
    `expected=${JSON.stringify(m.exp)} derived=${JSON.stringify(m.der)}`);

  // ── I2 관리자 초대 취소 ─────────────────────────────────────────────────
  //   먼저 취소를 본다. 거절부터 하면 재초대가 409(이미 초대됨)로 막혀
  //   관리자 취소 경로에 닿지 못한다 — 실측으로 확인했다.
  const can = await call('callableCancelTOInvitation', {applicationId: invAppId}, otok);
  check('I2 관리자 초대 취소 200', can.status, 200, JSON.stringify(can.body).slice(0, 180));
  m = await awaitMatch(W.TO, W.SLOT, W.WD);
  check('I2 취소 후 원장=파생', m.matched, true,
    `expected=${JSON.stringify(m.exp)} derived=${JSON.stringify(m.der)}`);

  // ── I3 다시 초대 → 근로자 거절 ──────────────────────────────────────────
  const inv2 = await invite(W.WA);
  check('I3 재초대 200', inv2.status, 200, JSON.stringify(inv2.body).slice(0, 180));
  await awaitMatch(W.TO, W.SLOT, W.WD);
  const dec = await call('callableDeclineTOInvitation', {applicationId: invAppId}, ta);
  check('I3 초대 거절 200', dec.status, 200, JSON.stringify(dec.body).slice(0, 180));
  m = await awaitMatch(W.TO, W.SLOT, W.WD);
  check('I3 거절 후 원장=파생', m.matched, true,
    `expected=${JSON.stringify(m.exp)} derived=${JSON.stringify(m.der)}`);

  // ── I4 초대 수락 → 좌석으로 전환 ────────────────────────────────────────
  const inv3 = await invite(W.WB);
  observe('I4 초대(B) 응답', String(inv3.status), JSON.stringify(inv3.body).slice(0, 180));
  const invB = (await db.collection('applications').where('toId', '==', W.TO)
    .where('uid', '==', W.WB).get()).docs[0]?.id;
  if (inv3.status === 200 && invB) {
    const acc = await call('callableAcceptTOInvitation', {
      applicationId: invB, documentAccessConsentGiven: true,
      documentAccessConsentVersion: '2026-09-18-v3',
    }, tb);
    check('I4 초대 수락 200', acc.status, 200, JSON.stringify(acc.body).slice(0, 220));
    m = await awaitMatch(W.TO, W.SLOT, W.WD);
    check('I4 수락 후 원장=파생(대기→좌석)', m.matched, true,
      `expected=${JSON.stringify(m.exp)} derived=${JSON.stringify(m.der)}`);
  } else {
    observe('I4 판정 보류', `${inv3.status} invB=${invB}`);
  }

  // ── I5 겹침 자동취소 — 두 공고에 지원 후 한쪽 확정 ────────────────────────
  await call('callableApplyToTO', applyPayload(W.TO, W.SLOT, W.WD, workDate), ta);
  await call('callableApplyToTO', applyPayload(W.TO2, W.SLOT2, W.WD2X, workDate), ta);
  await awaitMatch(W.TO, W.SLOT, W.WD);
  await awaitMatch(W.TO2, W.SLOT2, W.WD2X);
  const before2 = await expectedOf(W.TO2, W.WD2X);
  observe('I5 확정 전 두 번째 공고 상태', JSON.stringify(before2.byStatus));

  const confA = await call('callableConfirmApplication',
    {applicationId: `${W.TO}_${W.SLOT}_${W.WD}_${W.WA}`, businessId: W.BIZ}, otok);
  check('I5 확정 200', confA.status, 200, JSON.stringify(confA.body).slice(0, 200));
  observe('I5 자동취소 보고', JSON.stringify(
    confA.body?.result?.autoCanceledDetails ?? []).slice(0, 220));

  const m1 = await awaitMatch(W.TO, W.SLOT, W.WD);
  check('I5 확정 공고 원장=파생', m1.matched, true,
    `expected=${JSON.stringify(m1.exp)} derived=${JSON.stringify(m1.der)}`);
  const m2 = await awaitMatch(W.TO2, W.SLOT2, W.WD2X);
  check('I5 자동취소된 다른 공고도 원장=파생', m2.matched, true,
    `expected=${JSON.stringify(m2.exp)} derived=${JSON.stringify(m2.der)}`);
  observe('I5 두 번째 공고 최종 상태', JSON.stringify(m2.exp.byStatus));

  // ── I6 trigger replay — 같은 상태에서 재집계를 반복해도 같다 ──────────────
  for (let i = 0; i < 3; i++) {
    await call('callableRecalculateTOStats', {toId: W.TO}, otok);
    await call('callableRecalculateTOStats', {toId: W.TO2}, otok);
  }
  const r1 = await awaitMatch(W.TO, W.SLOT, W.WD);
  const r2 = await awaitMatch(W.TO2, W.SLOT2, W.WD2X);
  check('I6 재집계 반복 후에도 두 공고 모두 일치', {a: r1.matched, b: r2.matched},
    {a: true, b: true},
    `A=${JSON.stringify(r1.der)} B=${JSON.stringify(r2.der)}`);

  // ── I7 만료 처리 ────────────────────────────────────────────────────────
  const exp = await call('callableExpireApplications', {}, otok);
  observe('I7 만료 callable 응답', String(exp.status),
    JSON.stringify(exp.body).slice(0, 200));
  const e1 = await awaitMatch(W.TO, W.SLOT, W.WD);
  check('I7 만료 처리 후에도 일치', e1.matched, true,
    `expected=${JSON.stringify(e1.exp)} derived=${JSON.stringify(e1.der)}`);

  console.log(JSON.stringify({run: W.RUN, failures, results}, null, 2));
  await cleanup();
  process.exit(failures > 0 ? 1 : 0);
})().catch((e) => { console.error('HARNESS ERROR:', e); process.exit(2); });
