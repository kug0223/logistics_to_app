/**
 * R7 6차 §6 — 배포 호환 조합을 **실제로** 돌린다. 배포는 하지 않는다.
 *
 *   new CF 는 지금 트리에 있다. 클라이언트 세대는 **write set 으로** 재현한다:
 *
 *     old client : 취소 시 원장 + `to.totalPending` + `slot.pendingCount` 를
 *                  자기가 내리고, 카운터 command 는 부르지 않는다.
 *                  (`workDetailCounts` 는 rules 가 막아 손대지 못한다)
 *     new client : 원장만 바꾸고 `callableIncrementSlotPending(-1)` 을 부른다.
 *
 *   `new client × old CF` 는 `functions/src` 를 stash 한 뒤 durability 하네스를
 *   돌려 이미 확인했다(실패 8건 — drift 는 남지만 이중 차감·음수는 없었다).
 *   여기서는 `old client × new CF` 와 `new client × new CF` 를 본다.
 *
 * 격리 에뮬레이터(demo-alfit-r7) 전용.
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

async function idToken(uid) {
  const custom = await admin.auth().createCustomToken(uid);
  const r = await fetch(
    'http://127.0.0.1:6072/identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=fake',
    {method: 'POST', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({token: custom, returnSecureToken: true})});
  return (await r.json()).idToken;
}
async function call(name, data, token, timeoutMs = 60000) {
  const ac = new AbortController();
  const timer = setTimeout(() => ac.abort(), timeoutMs);
  try {
    const r = await fetch(`${FN}/${name}`, {
      method: 'POST',
      headers: {'Content-Type': 'application/json',
        ...(token ? {Authorization: `Bearer ${token}`} : {}),
        'X-Firebase-AppCheck': 'r7-audit-emulator-token'},
      body: JSON.stringify({data}), signal: ac.signal,
    });
    const t = await r.text();
    let body; try { body = JSON.parse(t); } catch { body = t; }
    return {status: r.status, body};
  } catch (e) {
    return {status: -1, body: {error: String(e && e.name === 'AbortError'
      ? `TIMEOUT ${timeoutMs}ms` : e)}};
  } finally { clearTimeout(timer); }
}

const PENDING = ['PENDING', 'INVITED'];
const SEATED = ['CONFIRMED', 'CONTRACT_PENDING'];

function makeWorld(tag) {
  const RUN = `r7k${tag}${Date.now().toString(36)}`;
  return {RUN, BIZ: `${RUN}biz`, TO: `${RUN}to`, SLOT: `${RUN}slot`,
    WD: `${RUN}wd`, OWNER: `${RUN}own`, WA: `${RUN}wa`};
}

async function seed(w) {
  const workDate = kstDayStart(Date.now()) + 3 * 86400000;
  for (const uid of [w.OWNER, w.WA]) {
    try { await admin.auth().createUser({uid}); } catch (e) {
      if (e.code !== 'auth/uid-already-exists') throw e;
    }
  }
  await db.doc(`businesses/${w.BIZ}`).set({name: 'K', ownerId: w.OWNER,
    status: 'approved', isActive: true, adminIds: [w.OWNER],
    city: '강남구', address: '서울특별시 강남구 테헤란로 1'});
  await db.doc(`users/${w.OWNER}`).set({uid: w.OWNER, name: 'K 관리자',
    role: 'BUSINESS_ADMIN', businessId: w.BIZ, accountStatus: 'active',
    passVerifiedAt: admin.firestore.Timestamp.now()});
  await db.doc(`users/${w.WA}`).set({uid: w.WA, name: 'K 근로자', role: 'USER',
    accountStatus: 'active', passVerifiedAt: admin.firestore.Timestamp.now(),
    isIdVerified: true, idCardImagePath: `id_cards/${w.WA}/id.jpg`,
    bankName: '국민', accountNumber: 'enc', accountHolder: 'K',
    bankbookImagePath: `bankbooks/${w.WA}/b.jpg`,
    termsConsentAt: admin.firestore.Timestamp.now(),
    isBlacklisted: false, isForeign: false,
    idDocumentVersion: 1, bankbookDocumentVersion: 1, bankAccountVersion: 1});
  await db.doc(`businessApplicantDocumentReviews/${w.BIZ}_${w.WA}`).set({
    businessId: w.BIZ, workerUid: w.WA,
    idDecision: 'REVIEWED_OK', reviewedIdDocumentVersion: 1,
    bankDecision: 'REVIEWED_OK',
    reviewedBankbookDocumentVersion: 1, reviewedBankAccountVersion: 1});

  const wd = {wdId: w.WD, workType: '홀서빙', startTime: '09:00', endTime: '18:00',
    wage: 12000, wageType: 'hourly', requiredCount: 2};
  const base = kstDayStart(Date.now()) - 86400000;
  await db.doc(`tos/${w.TO}`).set({id: w.TO, businessId: w.BIZ, title: 'K 공고',
    status: 'published', isPublic: true, isPublished: true, isDeleted: false,
    type: 'flex', createdBy: w.OWNER, workDetails: [wd],
    totalRequired: 2, totalConfirmed: 0, totalPending: 0,
    publishedAt: admin.firestore.Timestamp.fromMillis(base),
    createdAt: admin.firestore.Timestamp.fromMillis(base)});
  await db.doc(`tos/${w.TO}/slots/${w.SLOT}`).set({id: w.SLOT, toId: w.TO,
    businessId: w.BIZ, status: 'open', isManualClosed: false,
    date: admin.firestore.Timestamp.fromMillis(workDate),
    workDetails: [wd],
    workDetailCounts: {[w.WD]: {confirmedCount: 0, pendingCount: 0}},
    requiredCount: 2, confirmedCount: 0, pendingCount: 0});
  return {workDate};
}

async function cleanup(w) {
  const apps = await db.collection('applications').where('toId', '==', w.TO).get();
  for (const d of apps.docs) await d.ref.delete();
  await db.doc(`tos/${w.TO}/slots/${w.SLOT}`).delete().catch(() => {});
  await db.doc(`tos/${w.TO}`).delete().catch(() => {});
  await db.doc(`businesses/${w.BIZ}`).delete().catch(() => {});
  await sleep(1800);
  for (const p of [`users/${w.OWNER}`, `users/${w.WA}`,
    `businessApplicantDocumentReviews/${w.BIZ}_${w.WA}`]) {
    await db.doc(p).delete().catch(() => {});
  }
}

const payload = (w, workDate) => ({
  toId: w.TO, slotId: w.SLOT, businessId: w.BIZ, businessName: 'K', toTitle: 'K',
  workDateMs: workDate, selectedWorkType: '홀서빙', workDetailId: w.WD,
  startTime: '09:00', endTime: '18:00', wage: 12000, wageType: 'hourly',
  idCardConsentGiven: true, documentAccessConsentGiven: true,
  documentAccessConsentVersion: '2026-09-18-v3',
});

async function expectedOf(w) {
  const apps = await db.collection('applications').where('toId', '==', w.TO).get();
  let pending = 0, seated = 0, wdP = 0, wdC = 0;
  apps.forEach((d) => {
    const a = d.data();
    const isP = PENDING.includes(a.status);
    const isS = SEATED.includes(a.status) && a.staffingReleasedAt == null;
    if (isP) pending++;
    if (isS) seated++;
    if (a.wdId === w.WD) { if (isP) wdP++; if (isS) wdC++; }
  });
  return {pending, seated, wdP, wdC};
}
async function derivedOf(w) {
  const [s, t] = await Promise.all([
    db.doc(`tos/${w.TO}/slots/${w.SLOT}`).get(), db.doc(`tos/${w.TO}`).get()]);
  const sd = s.data() || {}; const td = t.data() || {};
  const e = sd.workDetailCounts?.[w.WD] || {};
  return {slotPending: sd.pendingCount ?? null, toPending: td.totalPending ?? null,
    wdP: e.pendingCount ?? null, wdC: e.confirmedCount ?? null};
}
async function awaitMatch(w, {maxMs = 25000} = {}) {
  const t0 = Date.now(); let last = null;
  for (;;) {
    const exp = await expectedOf(w); const der = await derivedOf(w);
    last = {exp, der};
    if (der.slotPending === exp.pending && der.toPending === exp.pending &&
        der.wdP === exp.wdP && der.wdC === exp.wdC) {
      return {matched: true, elapsedMs: Date.now() - t0, ...last};
    }
    if (Date.now() - t0 > maxMs) return {matched: false, elapsedMs: Date.now() - t0, ...last};
    await sleep(250);
  }
}

/** 구버전 클라이언트의 취소 write set — 원장 + 상위 두 카운터, command 없음. */
async function oldClientCancel(w, appId) {
  await db.runTransaction(async (tx) => {
    const ref = db.collection('applications').doc(appId);
    const fresh = await tx.get(ref);
    if (!fresh.exists || fresh.data()?.status === 'CANCELED') return;
    tx.update(ref, {status: 'CANCELED', cancelReason: 'USER_CANCELED',
      canceledAt: admin.firestore.FieldValue.serverTimestamp()});
    tx.update(db.doc(`tos/${w.TO}`),
      {totalPending: admin.firestore.FieldValue.increment(-1)});
    tx.update(db.doc(`tos/${w.TO}/slots/${w.SLOT}`),
      {pendingCount: admin.firestore.FieldValue.increment(-1)});
  });
}
/** 신버전 클라이언트의 취소 write set — 원장만, 그리고 권위 command. */
async function newClientCancel(w, appId, tok) {
  let did = false;
  await db.runTransaction(async (tx) => {
    const ref = db.collection('applications').doc(appId);
    const fresh = await tx.get(ref);
    if (!fresh.exists || fresh.data()?.status === 'CANCELED') return;
    tx.update(ref, {status: 'CANCELED', cancelReason: 'USER_CANCELED',
      canceledAt: admin.firestore.FieldValue.serverTimestamp()});
    did = true;
  });
  if (!did) return {skipped: true};
  return call('callableIncrementSlotPending',
    {applicationId: appId, toId: w.TO, slotId: w.SLOT, delta: -1}, tok);
}

async function runCell(tag, cancelFn) {
  const w = makeWorld(tag);
  const {workDate} = await seed(w);
  const tok = await idToken(w.WA);
  const appId = `${w.TO}_${w.SLOT}_${w.WD}_${w.WA}`;

  await call('callableApplyToTO', payload(w, workDate), tok);
  let m = await awaitMatch(w);
  check(`${tag} 지원 후 일치`, m.matched, true, JSON.stringify(m.der));

  // 취소 → 재지원 2주기
  for (let i = 1; i <= 2; i++) {
    await cancelFn(w, appId, tok);
    m = await awaitMatch(w);
    check(`${tag} ${i}주기 취소 후 일치`, m.matched, true,
      `expected=${JSON.stringify(m.exp)} derived=${JSON.stringify(m.der)}`);
    await call('callableApplyToTO', payload(w, workDate), tok);
    m = await awaitMatch(w);
    check(`${tag} ${i}주기 재지원 후 일치`, m.matched, true,
      `expected=${JSON.stringify(m.exp)} derived=${JSON.stringify(m.der)}`);
  }
  // 음수/이중차감 확인
  const der = await derivedOf(w);
  check(`${tag} 음수 카운터 없음`,
    (der.wdP ?? 0) >= 0 && (der.wdC ?? 0) >= 0 &&
    (der.slotPending ?? 0) >= 0 && (der.toPending ?? 0) >= 0, true,
    JSON.stringify(der));
  await cleanup(w);
}

(async () => {
  await runCell('old-client×new-CF', oldClientCancel);
  await runCell('new-client×new-CF', newClientCancel);
  observe('new-client×old-CF',
    'functions/src stash 후 durability 하네스 — 실패 8건',
    'drift 는 남지만 이중 차감·음수 없음. 같은 세션에서 실행해 기록했다.');
  console.log(JSON.stringify({failures, results}, null, 2));
  process.exit(failures > 0 ? 1 : 0);
})().catch((e) => { console.error('HARNESS ERROR:', e); process.exit(2); });
