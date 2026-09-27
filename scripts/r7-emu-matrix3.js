/**
 * R7 §6 — 수리 후 전이 매트릭스. **기대값으로 판정한다.**
 *
 *   "값이 4회 같았다"는 관측 기간의 안정성일 뿐 정확성이 아니다.
 *   그래서 매 단계마다 원장에서 기대값을 계산하고, 파생 집계 셋이 그것과
 *   같은지 본다. 수렴을 기다리되, 수렴한 값이 **틀리면 FAIL** 이다.
 *
 * 격리 에뮬레이터(demo-alfit-r7) 전용.
 */
const PROJECT = 'demo-alfit-r7';
process.env.GCLOUD_PROJECT = PROJECT;
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:6070';
process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:6072';
process.env.FIREBASE_STORAGE_EMULATOR_HOST = '127.0.0.1:6071';

const path = require('path');
const admin = require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin'));
admin.initializeApp({projectId: PROJECT});
const db = admin.firestore();
const FN = `http://127.0.0.1:5011/${PROJECT}/asia-northeast3`;

// [R7-5] id 를 실행마다 유일하게 만든다.
//
//   같은 id 를 재사용했더니, 직전 실행의 cleanup 이 일으킨
//   `onTODeleted`/`onBusinessDeleted` cascade(각 ~900ms)가 **새 실행이
//   막 seed 한 문서**를 지웠다. 제품 결함이 아니라 하네스 간섭이다.
const RUN = `r7m3${Date.now().toString(36)}`;
const BIZ = `${RUN}biz`;
const TO = `${RUN}to`;
const SLOT = `${RUN}slot`;
const WD = `${RUN}wd`;
const OWNER = `${RUN}owner`;
const WORKERS = [`${RUN}wa`, `${RUN}wb`];
const REQUIRED = 1; // 마지막 한 자리 경합을 보기 위해 정원 1

const results = [];
let failures = 0;
function check(label, actual, expected, note) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) failures++;
  results.push({label, ok, actual, expected, ...(note ? {note} : {})});
}

const kstDayStart = (ms) => {
  const off = 9 * 3600 * 1000;
  const d = new Date(ms + off);
  d.setUTCHours(0, 0, 0, 0);
  return d.getTime() - off;
};

async function idToken(uid) {
  const custom = await admin.auth().createCustomToken(uid);
  const r = await fetch(
    'http://127.0.0.1:6072/identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=fake',
    {method: 'POST', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({token: custom, returnSecureToken: true})});
  const j = await r.json();
  if (!j.idToken) throw new Error('idToken: ' + JSON.stringify(j).slice(0, 200));
  return j.idToken;
}

async function call(name, data, token) {
  const r = await fetch(`${FN}/${name}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(token ? {Authorization: `Bearer ${token}`} : {}),
      'X-Firebase-AppCheck': 'r7-audit-emulator-token',
    },
    body: JSON.stringify({data}),
  });
  const t = await r.text();
  let body; try { body = JSON.parse(t); } catch { body = t; }
  return {status: r.status, body};
}

/** 원장에서 기대값을 만든다 — 파생 집계를 기대값의 근거로 쓰지 않는다. */
const SEATED = new Set(['CONFIRMED', 'CONTRACT_PENDING']);
const PENDING = new Set(['PENDING']);

async function observe() {
  const [slotD, toD, apps] = await Promise.all([
    db.doc(`tos/${TO}/slots/${SLOT}`).get(),
    db.doc(`tos/${TO}`).get(),
    db.collection('applications').where('toId', '==', TO).get(),
  ]);
  const s = slotD.data() || {};
  const t = toD.data() || {};
  let lp = 0, ls = 0;
  const statuses = {};
  apps.forEach((d) => {
    const a = d.data();
    statuses[a.status] = (statuses[a.status] || 0) + 1;
    if (PENDING.has(a.status)) lp++;
    if (SEATED.has(a.status)) ls++;
  });
  return {
    expected: {pending: lp, seated: ls},
    derived: {
      wdcPending: s.workDetailCounts?.[WD]?.pendingCount ?? null,
      wdcConfirmed: s.workDetailCounts?.[WD]?.confirmedCount ?? null,
      slotPending: s.pendingCount ?? null,
      slotConfirmed: s.confirmedCount ?? null,
      toPending: t.totalPending ?? null,
      toConfirmed: t.totalConfirmed ?? null,
    },
    statuses,
  };
}

/**
 * 원장 기대값과 파생 집계 셋이 **같아질 때까지** 기다린다.
 * 시간 안에 같아지지 않으면 미수렴으로 남긴다 — 마지막 값을 PASS 로 삼지 않는다.
 */
async function awaitConsistent({maxMs = 25000, stepMs = 300} = {}) {
  const t0 = Date.now();
  let last = null;
  while (Date.now() - t0 < maxMs) {
    const o = await observe();
    last = o;
    const d = o.derived;
    if (d.wdcPending === o.expected.pending &&
        d.slotPending === o.expected.pending &&
        d.toPending === o.expected.pending &&
        d.wdcConfirmed === o.expected.seated &&
        d.slotConfirmed === o.expected.seated &&
        d.toConfirmed === o.expected.seated) {
      return {converged: true, elapsedMs: Date.now() - t0, ...o};
    }
    await new Promise((r) => setTimeout(r, stepMs));
  }
  return {converged: false, elapsedMs: Date.now() - t0, ...last};
}

async function cleanup() {
  const apps = await db.collection('applications').where('toId', '==', TO).get();
  for (const d of apps.docs) await d.ref.delete();
  const paths = [`tos/${TO}/slots/${SLOT}`, `tos/${TO}`, `businesses/${BIZ}`, `users/${OWNER}`];
  for (const w of WORKERS) {
    paths.push(`users/${w}`, `businessApplicantDocumentReviews/${BIZ}_${w}`);
  }
  for (const p of paths) await db.doc(p).delete().catch(() => {});
}

async function seed() {
  const workDate = kstDayStart(Date.now()) + 3 * 86400000;
  for (const uid of [...WORKERS, OWNER]) {
    try { await admin.auth().createUser({uid}); } catch (e) {
      if (e.code !== 'auth/uid-already-exists') throw e;
    }
  }
  await db.doc(`businesses/${BIZ}`).set(
    {name: 'R7 감사 사업장3', ownerId: OWNER, status: 'approved', isActive: true});
  await db.doc(`users/${OWNER}`).set({
    uid: OWNER, name: 'R7 관리자3', role: 'BUSINESS_ADMIN', businessId: BIZ,
    accountStatus: 'active', passVerifiedAt: admin.firestore.Timestamp.now()});
  for (const w of WORKERS) {
    await db.doc(`users/${w}`).set({
      uid: w, name: `R7 근로자 ${w.slice(-1)}`, role: 'USER', accountStatus: 'active',
      passVerifiedAt: admin.firestore.Timestamp.now(),
      isIdVerified: true, idCardImagePath: `id_cards/${w}/id.jpg`,
      bankName: '국민', accountNumber: 'enc-r7', accountHolder: 'R7',
      bankbookImagePath: `bankbooks/${w}/b.jpg`,
      termsConsentAt: admin.firestore.Timestamp.now(),
      isBlacklisted: false, isForeign: false,
      idDocumentVersion: 1, bankbookDocumentVersion: 1, bankAccountVersion: 1});
    await db.doc(`businessApplicantDocumentReviews/${BIZ}_${w}`).set({
      businessId: BIZ, workerUid: w,
      idDecision: 'REVIEWED_OK', reviewedIdDocumentVersion: 1,
      bankDecision: 'REVIEWED_OK',
      reviewedBankbookDocumentVersion: 1, reviewedBankAccountVersion: 1});
  }
  const wd = {wdId: WD, workType: '홀서빙', startTime: '09:00', endTime: '18:00',
    wage: 12000, wageType: 'hourly', requiredCount: REQUIRED};
  const base = kstDayStart(Date.now()) - 86400000;
  await db.doc(`tos/${TO}`).set({
    id: TO, businessId: BIZ, title: 'R7 감사 공고3', status: 'published',
    isPublic: true, isPublished: true, isDeleted: false, type: 'flex', createdBy: OWNER,
    workDetails: [wd], totalRequired: REQUIRED, totalConfirmed: 0, totalPending: 0,
    publishedAt: admin.firestore.Timestamp.fromMillis(base),
    createdAt: admin.firestore.Timestamp.fromMillis(base)});
  await db.doc(`tos/${TO}/slots/${SLOT}`).set({
    id: SLOT, toId: TO, businessId: BIZ, status: 'open', isManualClosed: false,
    date: admin.firestore.Timestamp.fromMillis(workDate),
    workDetails: [wd],
    workDetailCounts: {[WD]: {confirmedCount: 0, pendingCount: 0}},
    requiredCount: REQUIRED, confirmedCount: 0, pendingCount: 0});
  return {workDate};
}

const payload = (workDate) => ({
  toId: TO, slotId: SLOT, businessId: BIZ, businessName: 'R7 감사 사업장3',
  toTitle: 'R7 감사 공고3', workDateMs: workDate,
  selectedWorkType: '홀서빙', workDetailId: WD,
  startTime: '09:00', endTime: '18:00', wage: 12000, wageType: 'hourly',
  idCardConsentGiven: true, documentAccessConsentGiven: true,
  documentAccessConsentVersion: '2026-09-18-v3',
});

/**
 * 수리된 클라이언트 취소 경로를 그대로 재현한다.
 *   1) 원장만 바꾸는 transaction (카운터 미터치)
 *   2) 권위 command `callableIncrementSlotPending(delta:-1)` 호출
 * Admin SDK 라 rules 는 지나지 않는다 — write set 만 같다.
 */
async function clientCancel(appId, token) {
  let did = false;
  await db.runTransaction(async (tx) => {
    const ref = db.collection('applications').doc(appId);
    const fresh = await tx.get(ref);
    const st = fresh.data()?.status;
    if (!st || st === 'CANCELED') return;
    tx.update(ref, {status: 'CANCELED', cancelReason: 'USER_CANCELED',
      canceledAt: admin.firestore.FieldValue.serverTimestamp()});
    did = true;
  });
  if (!did) return {skipped: true};
  return call('callableIncrementSlotPending',
    {applicationId: appId, toId: TO, slotId: SLOT, delta: -1}, token);
}

(async () => {
  await cleanup();
  const {workDate} = await seed();
  const tok = {};
  for (const w of WORKERS) tok[w] = await idToken(w);
  const otok = await idToken(OWNER);
  const appIdOf = (w) => `${TO}_${SLOT}_${WD}_${w}`;

  // ── S1 지원 ────────────────────────────────────────────────────────────
  const a1 = await call('callableApplyToTO', payload(workDate), tok[WORKERS[0]]);
  check('S1 지원 응답 200', a1.status, 200);
  let o = await awaitConsistent();
  check('S1 원장=파생 일치', {c: o.converged, d: o.derived}, {c: true, d: o.expected && {
    wdcPending: 1, wdcConfirmed: 0, slotPending: 1, slotConfirmed: 0,
    toPending: 1, toConfirmed: 0}});

  // ── S2 취소 → 재지원 2회 반복 ───────────────────────────────────────────
  for (let cycle = 1; cycle <= 2; cycle++) {
    const c = await clientCancel(appIdOf(WORKERS[0]), tok[WORKERS[0]]);
    check(`S2.${cycle} 취소 후 카운터 command 200`, c.status ?? 'skipped', 200);
    o = await awaitConsistent();
    check(`S2.${cycle} 취소 후 원장=파생`, {c: o.converged, d: o.derived}, {c: true, d: {
      wdcPending: 0, wdcConfirmed: 0, slotPending: 0, slotConfirmed: 0,
      toPending: 0, toConfirmed: 0}});

    const re = await call('callableApplyToTO', payload(workDate), tok[WORKERS[0]]);
    check(`S2.${cycle} 재지원 200`, re.status, 200);
    o = await awaitConsistent();
    check(`S2.${cycle} 재지원 후 원장=파생`, {c: o.converged, d: o.derived}, {c: true, d: {
      wdcPending: 1, wdcConfirmed: 0, slotPending: 1, slotConfirmed: 0,
      toPending: 1, toConfirmed: 0}});
  }

  // ── S3 replay — 같은 감소 command 를 한 번 더 ────────────────────────────
  const c3 = await clientCancel(appIdOf(WORKERS[0]), tok[WORKERS[0]]);
  check('S3 취소 200', c3.status ?? 'skipped', 200);
  await awaitConsistent();
  const replay = await call('callableIncrementSlotPending',
    {applicationId: appIdOf(WORKERS[0]), toId: TO, slotId: SLOT, delta: -1},
    tok[WORKERS[0]]);
  check('S3 replay 응답 200', replay.status, 200);
  o = await awaitConsistent();
  check('S3 replay 후에도 음수·이중감소 없음', {c: o.converged, d: o.derived}, {c: true, d: {
    wdcPending: 0, wdcConfirmed: 0, slotPending: 0, slotConfirmed: 0,
    toPending: 0, toConfirmed: 0}});

  // ── S4 마지막 한 자리 동시 확정 ─────────────────────────────────────────
  await call('callableApplyToTO', payload(workDate), tok[WORKERS[0]]);
  await call('callableApplyToTO', payload(workDate), tok[WORKERS[1]]);
  o = await awaitConsistent();
  check('S4 두 명 대기', {c: o.converged, p: o.derived.wdcPending}, {c: true, p: 2});

  const [r1, r2] = await Promise.all([
    call('callableConfirmApplication',
      {applicationId: appIdOf(WORKERS[0]), businessId: BIZ}, otok),
    call('callableConfirmApplication',
      {applicationId: appIdOf(WORKERS[1]), businessId: BIZ}, otok),
  ]);
  const okCount = [r1, r2].filter((r) => r.status === 200).length;
  check('S4 정원 1에서 확정 성공은 1건', okCount, 1,
    `r1=${r1.status} r2=${r2.status}`);
  o = await awaitConsistent();
  check('S4 동시 확정 후 원장=파생', {c: o.converged, seated: o.expected.seated,
    wdcC: o.derived.wdcConfirmed, slotC: o.derived.slotConfirmed,
    toC: o.derived.toConfirmed},
  {c: true, seated: 1, wdcC: 1, slotC: 1, toC: 1});

  // ── S5 확정취소 → 재확정 ────────────────────────────────────────────────
  const winner = r1.status === 200 ? WORKERS[0] : WORKERS[1];
  const cc = await call('callableCancelConfirmedApplication',
    {applicationId: appIdOf(winner), cancelReason: 'R7 감사'}, otok);
  check('S5 확정취소 200', cc.status, 200);
  o = await awaitConsistent();
  check('S5 확정취소 후 원장=파생', {c: o.converged, d: {
    wdcC: o.derived.wdcConfirmed, slotC: o.derived.slotConfirmed,
    toC: o.derived.toConfirmed}}, {c: true, d: {wdcC: 0, slotC: 0, toC: 0}});

  const loser = winner === WORKERS[0] ? WORKERS[1] : WORKERS[0];
  const rc = await call('callableConfirmApplication',
    {applicationId: appIdOf(loser), businessId: BIZ}, otok);
  check('S5 자리가 비었으니 재확정 200', rc.status, 200, JSON.stringify(rc.body).slice(0, 160));
  o = await awaitConsistent();
  check('S5 재확정 후 원장=파생', {c: o.converged, seated: o.expected.seated,
    wdcC: o.derived.wdcConfirmed}, {c: true, seated: 1, wdcC: 1});

  // ── S6 권한 — 401 과 사업장 권한 거부를 나눈다 ───────────────────────────
  const noAuth = await call('callableConfirmApplication',
    {applicationId: appIdOf(loser), businessId: BIZ}, null);
  check('S6 무인증 = 401', noAuth.status, 401);
  const wrongActor = await call('callableConfirmApplication',
    {applicationId: appIdOf(loser), businessId: BIZ}, tok[WORKERS[0]]);
  check('S6 근로자 토큰으로 확정 시도 = 거부(401 아님)',
    wrongActor.status !== 401 && wrongActor.status >= 400, true,
    `status=${wrongActor.status} ${JSON.stringify(wrongActor.body).slice(0, 140)}`);
  const otherWorkerCounter = await call('callableIncrementSlotPending',
    {applicationId: appIdOf(loser), toId: TO, slotId: SLOT, delta: -1},
    tok[winner === WORKERS[0] ? WORKERS[0] : WORKERS[1]]);
  check('S6 타인 지원서 카운터 조작 거부',
    otherWorkerCounter.status >= 400, true,
    `status=${otherWorkerCounter.status} ${JSON.stringify(otherWorkerCounter.body).slice(0, 140)}`);

  // ── S7 확정 → 대기 롤백 (계약서 생성 실패 복구 경로) ─────────────────────
  //
  //   `updateApplicationStatus(status: pending)` 이 CONTRACT_PENDING 에서
  //   돌 때의 write set 을 재현한다. 수리 전에는 원장만 바뀌고 업무 단위
  //   확정 수가 1 로 남았다. 이제 서버 재집계 command 가 그것까지 맞춘다.
  const rolledBack = appIdOf(loser);
  await db.collection('applications').doc(rolledBack).update({
    status: 'PENDING',
    statusHistory: admin.firestore.FieldValue.arrayUnion(
      {status: 'PENDING', at: admin.firestore.Timestamp.now(),
        by: OWNER, action: 'CONFIRM_ROLLBACK'}),
  });
  const recalc = await call('callableRecalculateTOStats', {toId: TO}, otok);
  check('S7 재집계 응답 200', recalc.status, 200,
    JSON.stringify(recalc.body).slice(0, 160));
  o = await awaitConsistent();
  check('S7 롤백 후 원장=파생', {c: o.converged, pending: o.expected.pending,
    seated: o.expected.seated, wdcP: o.derived.wdcPending,
    wdcC: o.derived.wdcConfirmed},
  {c: true, pending: 1, seated: 0, wdcP: 1, wdcC: 0});

  console.log(JSON.stringify({run: RUN, failures, results}, null, 2));
  // 자기 fixture 만 지운다. id 가 유일하므로 cascade 가 다른 실행을 건드리지 않는다.
  await cleanup();
  process.exit(failures > 0 ? 1 : 0);
})().catch((e) => { console.error('HARNESS ERROR:', e); process.exit(2); });
