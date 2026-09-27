/**
 * R7 §6 — 전이 매트릭스 2단계.
 *
 * 1차(r7-emu-transition-matrix.js)가 확인한 T1~T4(지원·중복·확정·확정취소)를
 * 기준점으로 두고, 여기서는 **비동기 수렴**과 **보정자 없는 카운터**를 본다.
 *
 * 묻는 것:
 *   - 근로자 지원취소(클라이언트 직접 write 경로)가 남기는 상태.
 *   - `syncTOStats` 트리거가 무엇을 되돌리고 무엇을 되돌리지 않는가.
 *   - 고정 sleep 이 아니라 **수렴 관측**으로 판정한다.
 *
 * 격리 에뮬레이터(demo-alfit-r7) 전용. 커밋되는 감사 산출물이다.
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
const FN_BASE = `http://127.0.0.1:5011/${PROJECT}/asia-northeast3`;

const BIZ = 'r7biz2';
const TO = 'r7to2';
const SLOT = 'r7slot2';
const WD = 'wd-canonical-002';
const WORKER = 'r7worker002';
const OWNER = 'r7owner002';

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
  if (!j.idToken) throw new Error('idToken 실패: ' + JSON.stringify(j).slice(0, 200));
  return j.idToken;
}

async function call(name, data, token) {
  const r = await fetch(`${FN_BASE}/${name}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(token ? {Authorization: `Bearer ${token}`} : {}),
      'X-Firebase-AppCheck': 'r7-audit-emulator-token',
    },
    body: JSON.stringify({data}),
  });
  const text = await r.text();
  let body; try { body = JSON.parse(text); } catch { body = text; }
  return {status: r.status, body};
}

async function snap() {
  const [slotD, toD, apps] = await Promise.all([
    db.doc(`tos/${TO}/slots/${SLOT}`).get(),
    db.doc(`tos/${TO}`).get(),
    db.collection('applications').where('toId', '==', TO).get(),
  ]);
  const s = slotD.data() || {};
  const t = toD.data() || {};
  const ledger = {};
  apps.forEach((d) => {
    const a = d.data();
    ledger[a.status] = (ledger[a.status] || 0) + 1;
  });
  return {
    ledgerPending: ledger.PENDING || 0,
    ledgerSeated: (ledger.CONFIRMED || 0) + (ledger.CONTRACT_PENDING || 0),
    ledger,
    slotPendingCount: s.pendingCount ?? null,
    slotConfirmedCount: s.confirmedCount ?? null,
    wdcPending: s.workDetailCounts?.[WD]?.pendingCount ?? null,
    wdcConfirmed: s.workDetailCounts?.[WD]?.confirmedCount ?? null,
    toPending: t.totalPending ?? null,
    toConfirmed: t.totalConfirmed ?? null,
  };
}

/**
 * 수렴 관측 — 고정 sleep 로 "우연히 맞는" 것을 PASS 로 삼지 않는다.
 * 값이 연속 [stableFor]회 동일하면 정착으로 본다. 끝까지 흔들리면 그 사실을 남긴다.
 */
async function settle({maxMs = 20000, stepMs = 400, stableFor = 4} = {}) {
  const t0 = Date.now();
  let last = null, same = 0, samples = 0;
  while (Date.now() - t0 < maxMs) {
    const cur = JSON.stringify(await snap());
    samples++;
    if (cur === last) { same++; if (same >= stableFor) break; } else { same = 0; last = cur; }
    await new Promise((r) => setTimeout(r, stepMs));
  }
  return {settled: same >= stableFor, elapsedMs: Date.now() - t0, samples};
}

async function cleanup() {
  const apps = await db.collection('applications').where('toId', '==', TO).get();
  for (const d of apps.docs) await d.ref.delete();
  for (const p of [`tos/${TO}/slots/${SLOT}`, `tos/${TO}`, `businesses/${BIZ}`,
    `users/${WORKER}`, `users/${OWNER}`, `businessApplicantDocumentReviews/${BIZ}_${WORKER}`]) {
    await db.doc(p).delete().catch(() => {});
  }
}

async function seed() {
  const workDate = kstDayStart(Date.now()) + 3 * 86400000;
  for (const uid of [WORKER, OWNER]) {
    try { await admin.auth().createUser({uid}); } catch (e) {
      if (e.code !== 'auth/uid-already-exists') throw e;
    }
  }
  await db.doc(`businesses/${BIZ}`).set(
    {name: 'R7 감사 사업장2', ownerId: OWNER, status: 'approved', isActive: true});
  await db.doc(`users/${OWNER}`).set({
    uid: OWNER, name: 'R7 관리자2', role: 'BUSINESS_ADMIN', businessId: BIZ,
    accountStatus: 'active', passVerifiedAt: admin.firestore.Timestamp.now()});
  await db.doc(`users/${WORKER}`).set({
    uid: WORKER, name: 'R7 근로자2', role: 'USER', accountStatus: 'active',
    passVerifiedAt: admin.firestore.Timestamp.now(),
    isIdVerified: true, idCardImagePath: `id_cards/${WORKER}/id.jpg`,
    bankName: '국민', accountNumber: 'enc-r7', accountHolder: 'R7 근로자2',
    bankbookImagePath: `bankbooks/${WORKER}/b.jpg`,
    termsConsentAt: admin.firestore.Timestamp.now(),
    isBlacklisted: false, isForeign: false,
    idDocumentVersion: 1, bankbookDocumentVersion: 1, bankAccountVersion: 1});
  await db.doc(`businessApplicantDocumentReviews/${BIZ}_${WORKER}`).set({
    businessId: BIZ, workerUid: WORKER,
    idDecision: 'REVIEWED_OK', reviewedIdDocumentVersion: 1,
    bankDecision: 'REVIEWED_OK',
    reviewedBankbookDocumentVersion: 1, reviewedBankAccountVersion: 1});

  const wd = {wdId: WD, workType: '홀서빙', startTime: '09:00', endTime: '18:00',
    wage: 12000, wageType: 'hourly', requiredCount: 2};
  await db.doc(`tos/${TO}`).set({
    id: TO, businessId: BIZ, title: 'R7 감사 공고2', status: 'published',
    isPublic: true, isPublished: true, isDeleted: false, type: 'flex', createdBy: OWNER,
    workDetails: [wd], totalRequired: 2, totalConfirmed: 0, totalPending: 0,
    publishedAt: admin.firestore.Timestamp.fromMillis(kstDayStart(Date.now()) - 86400000),
    createdAt: admin.firestore.Timestamp.fromMillis(kstDayStart(Date.now()) - 86400000)});
  await db.doc(`tos/${TO}/slots/${SLOT}`).set({
    id: SLOT, toId: TO, businessId: BIZ, status: 'open', isManualClosed: false,
    date: admin.firestore.Timestamp.fromMillis(workDate),
    workDetails: [wd],
    workDetailCounts: {[WD]: {confirmedCount: 0, pendingCount: 0}},
    requiredCount: 2, confirmedCount: 0, pendingCount: 0});
  return {workDate};
}

function applyPayload(workDate) {
  return {
    toId: TO, slotId: SLOT, businessId: BIZ, businessName: 'R7 감사 사업장2',
    toTitle: 'R7 감사 공고2', workDateMs: workDate,
    selectedWorkType: '홀서빙', workDetailId: WD,
    startTime: '09:00', endTime: '18:00', wage: 12000, wageType: 'hourly',
    idCardConsentGiven: true, documentAccessConsentGiven: true,
    documentAccessConsentVersion: '2026-09-18-v3',
  };
}

(async () => {
  const out = [];
  const push = (label, extra) => out.push({label, ...extra});

  await cleanup();
  const {workDate} = await seed();
  const wtok = await idToken(WORKER);

  // ── T5 지원 → 근로자 지원취소(클라이언트 write 경로 재현) ──────────────
  const apply = await call('callableApplyToTO', applyPayload(workDate), wtok);
  push('T5-a 지원', {status: apply.status});
  await settle();
  push('T5-b 지원 정착', {state: await snap()});

  const appId = apply.body?.result?.applicationId;

  // 클라이언트 `cancelApplication` 과 **같은 write set** 을 재현한다.
  //   주의: Admin SDK 는 rules 를 통과하지 않는다 — 여기서 검증하는 것은
  //   권한이 아니라 **카운터 수렴**이다. rules 는 별도 경로로 확인해야 한다.
  await db.runTransaction(async (tx) => {
    const ref = db.collection('applications').doc(appId);
    tx.update(ref, {status: 'CANCELED', cancelReason: 'USER_CANCELED'});
    tx.update(db.doc(`tos/${TO}`), {totalPending: admin.firestore.FieldValue.increment(-1)});
    tx.update(db.doc(`tos/${TO}/slots/${SLOT}`),
      {pendingCount: admin.firestore.FieldValue.increment(-1)});
  });
  push('T5-c 근로자 지원취소 직후(트리거 전)', {state: await snap()});
  const s1 = await settle();
  push('T5-d 지원취소 정착', {settle: s1, state: await snap()});

  // ── T6 재지원 (취소 후 같은 업무로 다시) ────────────────────────────────
  const re = await call('callableApplyToTO', applyPayload(workDate), wtok);
  push('T6-a 재지원', {status: re.status, body: re.body});
  const s2 = await settle();
  push('T6-b 재지원 정착', {settle: s2, state: await snap()});

  // ── T7 외부 부작용 실패 주입 ────────────────────────────────────────────
  //
  //   지금까지는 fixture 사용자에게 FCM 토큰이 없어 알림 트리거가
  //   `토큰 없음` 에서 멈췄다 — 전송 경로에 닿지도 않았다.
  //   여기서는 **일부러 토큰을 넣어** 전송까지 가게 한다. demo 프로젝트에는
  //   자격증명이 없으므로 그 호출은 실패한다. 그때 원장 commit 과 응답이
  //   어떻게 되는지를 본다. 실패를 성공이라 말하지도, 성공을 실패라 말하지도
  //   않아야 한다. (mock 이 아니라 진짜 실패다.)
  //   확정 알림은 **근로자**에게 간다 — 대상에 토큰을 넣어야 전송 경로에 닿는다.
  await db.doc(`users/${WORKER}`).update(
    {fcmToken: 'r7-audit-invalid-token-not-a-real-device'});
  await db.doc(`users/${OWNER}`).update(
    {fcmToken: 'r7-audit-invalid-token-not-a-real-device'});

  const beforeT7 = await snap();
  const t7 = await call('callableApplyToTO', {
    ...applyPayload(workDate),
    // 같은 업무에 다시 지원할 수 없으므로, 두 번째 근무 정의를 쓰지 않고
    // 이미 PENDING 인 건을 관리자 확정으로 보낸다 — 확정 알림이 나간다.
  }, wtok);
  const otok = await idToken(OWNER);
  const confirmT7 = await call('callableConfirmApplication',
    {applicationId: `${TO}_${SLOT}_${WD}_${WORKER}`, businessId: BIZ}, otok);
  push('T7-a 알림 대상이 있는 상태의 확정', {
    duplicateApply: t7.status,
    confirmStatus: confirmT7.status,
    confirmOk: confirmT7.body?.result?.success ?? null,
  });
  const s3 = await settle();
  push('T7-b 확정 정착', {settle: s3, before: beforeT7, state: await snap()});

  console.log(JSON.stringify(out, null, 2));
  process.exit(0);
})().catch((e) => { console.error('HARNESS ERROR:', e); process.exit(1); });
