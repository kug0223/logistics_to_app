/**
 * R7 Staffing 감사 — 격리 에뮬레이터 전이 매트릭스 하네스
 *
 * 실행 전제: firebase.r7audit.json 으로 demo-alfit-r7 에뮬레이터가 떠 있어야 한다.
 *   functions 5011 / firestore 6070 / storage 6071 / auth 6072
 *
 * 이 스크립트는 커밋하지 않는다. shared DEV 를 건드리지 않는다.
 * 실제 production 함수(callable)를 호출해 원장·카운터·projection 을 대조한다.
 */
const PROJECT = 'demo-alfit-r7';
process.env.GCLOUD_PROJECT = PROJECT;
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:6070';
process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:6072';
process.env.FIREBASE_STORAGE_EMULATOR_HOST = '127.0.0.1:6071';

const path = require('path');
const FN = path.join(__dirname, '..', 'functions', 'node_modules');
const admin = require(path.join(FN, 'firebase-admin'));

admin.initializeApp({projectId: PROJECT});
const db = admin.firestore();
const FN_BASE = `http://127.0.0.1:5011/${PROJECT}/asia-northeast3`;

const BIZ = 'r7biz';
const TO = 'r7to';
const SLOT = 'r7slot';
const WD_ID = 'wd-canonical-001';
const WORKER = 'r7worker001';
const OWNER = 'r7owner001';

function kstDayStart(ms) {
  const off = 9 * 3600 * 1000;
  const d = new Date(ms + off);
  d.setUTCHours(0, 0, 0, 0);
  return d.getTime() - off;
}

async function idToken(uid) {
  const custom = await admin.auth().createCustomToken(uid);
  const r = await fetch(
    `http://127.0.0.1:6072/identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=fake`,
    {method: 'POST', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({token: custom, returnSecureToken: true})});
  const j = await r.json();
  if (!j.idToken) throw new Error('idToken 실패: ' + JSON.stringify(j).slice(0, 300));
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

/** 화면이 읽는 자리 그대로: 원장(applications) / 카운터(slot.workDetailCounts) / TO 집계 */
async function snapshot(label) {
  const slot = (await db.doc(`tos/${TO}/slots/${SLOT}`).get()).data() || {};
  const to = (await db.doc(`tos/${TO}`).get()).data() || {};
  const apps = await db.collection('applications')
    .where('toId', '==', TO).get();

  const ledger = {};
  apps.forEach((d) => {
    const a = d.data();
    const key = a.wdId || '(wdId 없음)';
    ledger[key] = ledger[key] || {};
    ledger[key][a.status] = (ledger[key][a.status] || 0) + 1;
  });

  return {
    label,
    counter: slot.workDetailCounts || null,
    toTotals: {
      totalConfirmed: to.totalConfirmed ?? null,
      totalPending: to.totalPending ?? null,
      totalRequired: to.totalRequired ?? null,
    },
    ledger,
    appCount: apps.size,
  };
}

async function seed() {
  const today = kstDayStart(Date.now());
  const workDate = today + 3 * 86400000; // 3일 뒤

  for (const uid of [WORKER, OWNER]) {
    try { await admin.auth().createUser({uid}); } catch (e) { if (e.code !== 'auth/uid-already-exists') throw e; }
  }

  await db.doc(`businesses/${BIZ}`).set({
    name: 'R7 감사 사업장', ownerId: OWNER, status: 'approved', isActive: true,
  });

  await db.doc(`users/${OWNER}`).set({
    uid: OWNER, name: 'R7 관리자', role: 'BUSINESS_ADMIN',
    businessId: BIZ, accountStatus: 'active', passVerifiedAt: admin.firestore.Timestamp.now(),
  });

  await db.doc(`users/${WORKER}`).set({
    uid: WORKER, name: 'R7 근로자', role: 'USER', accountStatus: 'active',
    passVerifiedAt: admin.firestore.Timestamp.now(),
    isIdVerified: true, idCardImagePath: `id_cards/${WORKER}/id.jpg`,
    bankName: '국민', accountNumber: 'enc-r7', accountHolder: 'R7 근로자',
    bankbookImagePath: `bankbooks/${WORKER}/b.jpg`,
    termsConsentAt: admin.firestore.Timestamp.now(),
    isBlacklisted: false, isForeign: false,
    idDocumentVersion: 1, bankbookDocumentVersion: 1, bankAccountVersion: 1,
  });

  // 확정 게이트(문서 검토)를 통과시키기 위한 실제 검토 상태 — 게이트를 우회하지 않는다.
  await db.doc(`businessApplicantDocumentReviews/${BIZ}_${WORKER}`).set({
    businessId: BIZ, workerUid: WORKER,
    idDecision: 'REVIEWED_OK', reviewedIdDocumentVersion: 1,
    bankDecision: 'REVIEWED_OK',
    reviewedBankbookDocumentVersion: 1, reviewedBankAccountVersion: 1,
  });

  // 업무 정의 — wdId 가 identity 원천이다.
  const wd = {
    wdId: WD_ID, workType: '홀서빙', startTime: '09:00', endTime: '18:00',
    wage: 12000, wageType: 'hourly', requiredCount: 2,
  };

  await db.doc(`tos/${TO}`).set({
    id: TO, businessId: BIZ, title: 'R7 감사 공고', status: 'published',
    isPublic: true, isPublished: true, isDeleted: false,
    type: 'flex', createdBy: OWNER,
    workDetails: [wd],
    totalRequired: 2, totalConfirmed: 0, totalPending: 0,
    publishedAt: admin.firestore.Timestamp.fromMillis(today - 86400000),
    createdAt: admin.firestore.Timestamp.fromMillis(today - 86400000),
  });

  await db.doc(`tos/${TO}/slots/${SLOT}`).set({
    id: SLOT, toId: TO, businessId: BIZ, status: 'open', isManualClosed: false,
    date: admin.firestore.Timestamp.fromMillis(workDate),
    workDetails: [wd],
    workDetailCounts: {[WD_ID]: {confirmedCount: 0, pendingCount: 0}},
    requiredCount: 2,
  });

  return {workDate};
}

async function cleanup() {
  const apps = await db.collection('applications').where('toId', '==', TO).get();
  for (const d of apps.docs) await d.ref.delete();
  await db.doc(`tos/${TO}/slots/${SLOT}`).delete().catch(() => {});
  await db.doc(`tos/${TO}`).delete().catch(() => {});
  await db.doc(`businesses/${BIZ}`).delete().catch(() => {});
  await db.doc(`users/${WORKER}`).delete().catch(() => {});
  await db.doc(`businessApplicantDocumentReviews/${BIZ}_${WORKER}`).delete().catch(() => {});
  await db.doc(`users/${OWNER}`).delete().catch(() => {});
}

(async () => {
  await cleanup();
  const {workDate} = await seed();
  const wtok = await idToken(WORKER);

  const out = [];
  out.push(await snapshot('T0 seed 직후'));

  const applyRes = await call('callableApplyToTO', {
    toId: TO, slotId: SLOT, businessId: BIZ, businessName: 'R7 감사 사업장',
    toTitle: 'R7 감사 공고', workDateMs: workDate,
    selectedWorkType: '홀서빙', workDetailId: WD_ID,
    startTime: '09:00', endTime: '18:00', wage: 12000, wageType: 'hourly',
    idCardConsentGiven: true, documentAccessConsentGiven: true,
    documentAccessConsentVersion: '2026-09-18-v3',
  }, wtok);
  out.push({label: 'APPLY 응답', status: applyRes.status, body: applyRes.body});
  out.push(await snapshot('T1 지원 직후'));

  const appId = applyRes.body?.result?.applicationId;
  const otok = await idToken(OWNER);

  // T2 — 같은 조건 재지원(중복)
  const dup = await call('callableApplyToTO', {
    toId: TO, slotId: SLOT, businessId: BIZ, businessName: 'R7 감사 사업장',
    toTitle: 'R7 감사 공고', workDateMs: workDate,
    selectedWorkType: '홀서빙', workDetailId: WD_ID,
    startTime: '09:00', endTime: '18:00', wage: 12000, wageType: 'hourly',
    idCardConsentGiven: true, documentAccessConsentGiven: true,
    documentAccessConsentVersion: '2026-09-18-v3',
  }, wtok);
  out.push({label: 'T2 중복지원 응답', status: dup.status, body: dup.body});
  out.push(await snapshot('T2 중복지원 직후'));

  // T3 — 관리자 확정
  const conf = await call('callableConfirmApplication',
    {applicationId: appId, businessId: BIZ}, otok);
  out.push({label: 'T3 확정 응답', status: conf.status, body: conf.body});
  out.push(await snapshot('T3 확정 직후'));

  // T4 — 확정 취소
  const cancel = await call('callableCancelConfirmedApplication',
    {applicationId: appId, cancelReason: 'R7 감사 전이 검증'}, otok);
  out.push({label: 'T4 확정취소 응답', status: cancel.status, body: cancel.body});
  out.push(await snapshot('T4 확정취소 직후'));

  console.log(JSON.stringify(out, null, 2));
  process.exit(0);
})().catch((e) => { console.error('HARNESS ERROR:', e); process.exit(1); });
