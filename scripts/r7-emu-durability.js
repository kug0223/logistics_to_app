/**
 * R7 6차 — F1(내구성) · F2(주기 간 멱등) · F3(절대 재계산 vs 증감 경합).
 *
 *   판정은 **원장에서 독립적으로 산출한 기대값**과 파생 집계의 일치다.
 *   "0 미만이 아니다" 나 "값이 몇 번 같았다" 는 근거로 쓰지 않는다.
 *   수렴은 bounded timeout 안에서 기대값과 일치해야 하고, 시간 안에 못 맞추면
 *   미수렴으로 남긴다.
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

const kstDayStart = (ms) => {
  const off = 9 * 3600 * 1000;
  const d = new Date(ms + off); d.setUTCHours(0, 0, 0, 0);
  return d.getTime() - off;
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

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

/** 한 시나리오용 fixture 한 벌. */
function makeWorld(tag) {
  const RUN = `r7d${tag}${Date.now().toString(36)}`;
  return {
    RUN,
    BIZ: `${RUN}biz`, TO: `${RUN}to`, SLOT: `${RUN}slot`,
    WD: `${RUN}wd`, WD2: `${RUN}wd2`,
    OWNER: `${RUN}own`, WA: `${RUN}wa`, WB: `${RUN}wb`,
  };
}

async function seed(w, {required = 1, twoWorkDetails = false} = {}) {
  const workDate = kstDayStart(Date.now()) + 3 * 86400000;
  for (const uid of [w.OWNER, w.WA, w.WB]) {
    try { await admin.auth().createUser({uid}); } catch (e) {
      if (e.code !== 'auth/uid-already-exists') throw e;
    }
  }
  await db.doc(`businesses/${w.BIZ}`).set({name: 'D', ownerId: w.OWNER,
    status: 'approved', isActive: true, adminIds: [w.OWNER],
    city: '강남구', address: '서울특별시 강남구 테헤란로 1'});
  await db.doc(`users/${w.OWNER}`).set({uid: w.OWNER, name: 'D 관리자',
    role: 'BUSINESS_ADMIN', businessId: w.BIZ, accountStatus: 'active',
    passVerifiedAt: admin.firestore.Timestamp.now()});
  for (const u of [w.WA, w.WB]) {
    await db.doc(`users/${u}`).set({uid: u, name: `D ${u.slice(-2)}`, role: 'USER',
      accountStatus: 'active', passVerifiedAt: admin.firestore.Timestamp.now(),
      isIdVerified: true, idCardImagePath: `id_cards/${u}/id.jpg`,
      bankName: '국민', accountNumber: 'enc', accountHolder: 'D',
      bankbookImagePath: `bankbooks/${u}/b.jpg`,
      termsConsentAt: admin.firestore.Timestamp.now(),
      isBlacklisted: false, isForeign: false,
      idDocumentVersion: 1, bankbookDocumentVersion: 1, bankAccountVersion: 1});
    await db.doc(`businessApplicantDocumentReviews/${w.BIZ}_${u}`).set({
      businessId: w.BIZ, workerUid: u,
      idDecision: 'REVIEWED_OK', reviewedIdDocumentVersion: 1,
      bankDecision: 'REVIEWED_OK',
      reviewedBankbookDocumentVersion: 1, reviewedBankAccountVersion: 1});
  }
  const wd1 = {wdId: w.WD, workType: '홀서빙', startTime: '09:00', endTime: '12:00',
    wage: 12000, wageType: 'hourly', requiredCount: required};
  const wd2 = {wdId: w.WD2, workType: '주방', startTime: '18:00', endTime: '22:00',
    wage: 13000, wageType: 'hourly', requiredCount: required};
  const wds = twoWorkDetails ? [wd1, wd2] : [wd1];
  const base = kstDayStart(Date.now()) - 86400000;
  await db.doc(`tos/${w.TO}`).set({id: w.TO, businessId: w.BIZ, title: 'D 공고',
    status: 'published', isPublic: true, isPublished: true, isDeleted: false,
    type: 'flex', createdBy: w.OWNER, workDetails: wds,
    totalRequired: required * wds.length, totalConfirmed: 0, totalPending: 0,
    publishedAt: admin.firestore.Timestamp.fromMillis(base),
    createdAt: admin.firestore.Timestamp.fromMillis(base)});
  const counts = {};
  for (const d of wds) counts[d.wdId] = {confirmedCount: 0, pendingCount: 0};
  await db.doc(`tos/${w.TO}/slots/${w.SLOT}`).set({id: w.SLOT, toId: w.TO,
    businessId: w.BIZ, status: 'open', isManualClosed: false,
    date: admin.firestore.Timestamp.fromMillis(workDate),
    workDetails: wds, workDetailCounts: counts,
    requiredCount: required * wds.length, confirmedCount: 0, pendingCount: 0});
  return {workDate};
}

async function cleanup(w) {
  const apps = await db.collection('applications').where('toId', '==', w.TO).get();
  for (const d of apps.docs) await d.ref.delete();
  const paths = [`tos/${w.TO}/slots/${w.SLOT}`, `tos/${w.TO}`, `businesses/${w.BIZ}`,
    `users/${w.OWNER}`, `users/${w.WA}`, `users/${w.WB}`,
    `businessApplicantDocumentReviews/${w.BIZ}_${w.WA}`,
    `businessApplicantDocumentReviews/${w.BIZ}_${w.WB}`];
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

const payload = (w, workDate, wdId, workType, st, et) => ({
  toId: w.TO, slotId: w.SLOT, businessId: w.BIZ, businessName: 'D',
  toTitle: 'D 공고', workDateMs: workDate,
  selectedWorkType: workType, workDetailId: wdId,
  startTime: st, endTime: et, wage: 12000, wageType: 'hourly',
  idCardConsentGiven: true, documentAccessConsentGiven: true,
  documentAccessConsentVersion: '2026-09-18-v3',
});
const applyWd1 = (w, d) => payload(w, d, w.WD, '홀서빙', '09:00', '12:00');
const applyWd2 = (w, d) => payload(w, d, w.WD2, '주방', '18:00', '22:00');

/** 원장을 직접 세어 기대값을 만든다 — 파생 집계를 근거로 쓰지 않는다. */
async function expectedOf(w) {
  const apps = await db.collection('applications').where('toId', '==', w.TO).get();
  const perWd = {};
  let pending = 0, seated = 0;
  apps.forEach((d) => {
    const a = d.data();
    const isP = PENDING.includes(a.status);
    const isS = SEATED.includes(a.status) && a.staffingReleasedAt == null;
    if (isP) pending++;
    if (isS) seated++;
    const k = a.wdId;
    if (!k) return;
    perWd[k] ??= {pending: 0, confirmed: 0};
    if (isP) perWd[k].pending++;
    if (isS) perWd[k].confirmed++;
  });
  return {pending, seated, perWd};
}

async function derivedOf(w) {
  const [slotD, toD] = await Promise.all([
    db.doc(`tos/${w.TO}/slots/${w.SLOT}`).get(),
    db.doc(`tos/${w.TO}`).get(),
  ]);
  const s = slotD.data() || {}; const t = toD.data() || {};
  const wdc = {};
  for (const [k, v] of Object.entries(s.workDetailCounts || {})) {
    wdc[k] = {pending: v.pendingCount ?? 0, confirmed: v.confirmedCount ?? 0};
  }
  return {
    slotPending: s.pendingCount ?? null, slotConfirmed: s.confirmedCount ?? null,
    toPending: t.totalPending ?? null, toConfirmed: t.totalConfirmed ?? null,
    wdc,
  };
}

/** 기대값과 파생 집계가 **일치**할 때까지. 못 맞추면 미수렴으로 남긴다. */
async function awaitMatch(w, {maxMs = 25000, stepMs = 250} = {}) {
  const t0 = Date.now();
  let last = null;
  for (;;) {
    const exp = await expectedOf(w);
    const der = await derivedOf(w);
    const wdOk = Object.keys({...exp.perWd, ...der.wdc}).every((k) => {
      const e = exp.perWd[k] ?? {pending: 0, confirmed: 0};
      const d = der.wdc[k] ?? {pending: 0, confirmed: 0};
      return e.pending === d.pending && e.confirmed === d.confirmed;
    });
    const ok = wdOk &&
      der.slotPending === exp.pending && der.slotConfirmed === exp.seated &&
      der.toPending === exp.pending && der.toConfirmed === exp.seated;
    last = {exp, der};
    if (ok) return {matched: true, elapsedMs: Date.now() - t0, ...last};
    if (Date.now() - t0 > maxMs) return {matched: false, elapsedMs: Date.now() - t0, ...last};
    await sleep(stepMs);
  }
}

/** 클라이언트 취소의 **원장 부분만**. command 는 부르지 않는다(프로세스 종료 재현). */
async function ledgerCancelOnly(appId) {
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
  return did;
}
const decrement = (w, appId, tok) => call('callableIncrementSlotPending',
  {applicationId: appId, toId: w.TO, slotId: w.SLOT, delta: -1}, tok);

// ══════════════════════════════════════════════════════════════════════════
// F1 — 원장은 성공했고 command 는 오지 않았다
// ══════════════════════════════════════════════════════════════════════════
async function f1() {
  const w = makeWorld('f1');
  const {workDate} = await seed(w);
  const ta = await idToken(w.WA);
  const appId = `${w.TO}_${w.SLOT}_${w.WD}_${w.WA}`;

  check('F1-0 지원 200', (await call('callableApplyToTO', applyWd1(w, workDate), ta)).status, 200);
  let m = await awaitMatch(w);
  check('F1-0 초기 일치', m.matched, true, JSON.stringify(m.der));

  // (a) 원장만 커밋하고 command 를 **아예 부르지 않는다** = 호출자 사망
  await ledgerCancelOnly(appId);
  m = await awaitMatch(w);
  check('F1-a command 없이도 업무 카운터가 복구된다', m.matched, true,
    `expected=${JSON.stringify(m.exp)} derived=${JSON.stringify(m.der)}`);
  observe('F1-a 복구까지', `${m.elapsedMs}ms`);

  // (b) 늦게 도착한 command — 이미 복구된 상태에서 이중 차감하지 않는다
  const late = await decrement(w, appId, ta);
  check('F1-b 늦은 command 200', late.status, 200);
  m = await awaitMatch(w);
  check('F1-b 이중 차감 없음', m.matched, true, JSON.stringify(m.der));

  // (c) 같은 요청 재시도(응답 유실 재현) — 여러 번 불러도 같다
  for (let i = 0; i < 3; i++) await decrement(w, appId, ta);
  m = await awaitMatch(w);
  check('F1-c 반복 재시도 후에도 일치', m.matched, true, JSON.stringify(m.der));

  // (d) 확정 → 롤백 원장만 (recalculate 미실행) → 트리거가 복구
  await call('callableApplyToTO', applyWd1(w, workDate), ta);
  await awaitMatch(w);
  const otok = await idToken(w.OWNER);
  const conf = await call('callableConfirmApplication',
    {applicationId: appId, businessId: w.BIZ}, otok);
  check('F1-d 확정 200', conf.status, 200, JSON.stringify(conf.body).slice(0, 140));
  m = await awaitMatch(w);
  check('F1-d 확정 후 일치', m.matched, true, JSON.stringify(m.der));

  await db.collection('applications').doc(appId).update({status: 'PENDING'});
  m = await awaitMatch(w);
  check('F1-e 롤백 원장만 — 재집계 없이도 복구된다', m.matched, true,
    `expected=${JSON.stringify(m.exp)} derived=${JSON.stringify(m.der)}`);

  await cleanup(w);
}

// ══════════════════════════════════════════════════════════════════════════
// F2 — 같은 문서의 다음 주기와 지난 주기의 요청
// ══════════════════════════════════════════════════════════════════════════
async function f2() {
  const w = makeWorld('f2');
  const {workDate} = await seed(w, {required: 2});
  const ta = await idToken(w.WA);
  const appId = `${w.TO}_${w.SLOT}_${w.WD}_${w.WA}`;

  // 1. 주기 A
  await call('callableApplyToTO', applyWd1(w, workDate), ta);
  let m = await awaitMatch(w);
  check('F2-1 주기A 일치', m.matched, true, JSON.stringify(m.der));

  // 2. A 취소 — 원장만. A 의 감소 명령은 **지연**시킨다.
  await ledgerCancelOnly(appId);
  m = await awaitMatch(w);
  check('F2-2 A 취소 후 일치(트리거 복구)', m.matched, true, JSON.stringify(m.der));

  // 3. 같은 문서로 주기 B 활성화
  const reB = await call('callableApplyToTO', applyWd1(w, workDate), ta);
  check('F2-3 주기B 재지원 200', reB.status, 200);
  check('F2-3 같은 문서 재활성화', reB.body?.result?.isReactivation, true);
  m = await awaitMatch(w);
  check('F2-3 주기B 일치', m.matched, true, JSON.stringify(m.der));
  const bPending = (await derivedOf(w)).wdc[w.WD]?.pending;
  check('F2-3 주기B 대기 1', bPending, 1);

  // 4. 지난 주기(A)의 감소가 늦게 도착 — B 의 좌석을 건드리면 안 된다
  const staleA = await decrement(w, appId, ta);
  observe('F2-4 지난 주기 감소 응답', `${staleA.status}`);
  await sleep(1500);
  const afterStale = await derivedOf(w);
  const expAfter = await expectedOf(w);
  check('F2-4 지난 주기 감소가 새 주기를 바꾸지 않았다',
    {wd: afterStale.wdc[w.WD]?.pending, slot: afterStale.slotPending,
      to: afterStale.toPending, ledger: expAfter.pending},
    {wd: 1, slot: 1, to: 1, ledger: 1});

  // 5. B 정상 취소 후 A/B 추가 replay
  await ledgerCancelOnly(appId);
  await decrement(w, appId, ta);
  m = await awaitMatch(w);
  check('F2-5 B 취소 후 일치', m.matched, true, JSON.stringify(m.der));
  for (let i = 0; i < 3; i++) await decrement(w, appId, ta);
  m = await awaitMatch(w);
  check('F2-5 A/B replay 후에도 일치(음수 없음)', m.matched, true,
    JSON.stringify(m.der));
  const neg = Object.values((await derivedOf(w)).wdc)
    .some((v) => v.pending < 0 || v.confirmed < 0);
  check('F2-5 음수 카운터 없음', neg, false);

  await cleanup(w);
}

// ══════════════════════════════════════════════════════════════════════════
// F3 — 절대 재계산과 증감의 경합
// ══════════════════════════════════════════════════════════════════════════
async function f3() {
  const w = makeWorld('f3');
  const {workDate} = await seed(w, {required: 1, twoWorkDetails: true});
  const ta = await idToken(w.WA);
  const tb = await idToken(w.WB);
  const otok = await idToken(w.OWNER);
  const appA = `${w.TO}_${w.SLOT}_${w.WD}_${w.WA}`;
  const appB = `${w.TO}_${w.SLOT}_${w.WD}_${w.WB}`;
  const appA2 = `${w.TO}_${w.SLOT}_${w.WD2}_${w.WA}`;

  // 두 업무에 각각 지원 — 업무별 후보가 다른 데이터가 되게 한다
  await call('callableApplyToTO', applyWd1(w, workDate), ta);
  await call('callableApplyToTO', applyWd2(w, workDate), ta);
  await call('callableApplyToTO', applyWd1(w, workDate), tb);
  let m = await awaitMatch(w);
  check('F3-0 초기 일치(업무 2개)', m.matched, true, JSON.stringify(m.der));

  // (a) 재집계와 원장 변경을 겹친다 — 재집계가 읽은 뒤 커밋이 들어간다
  const recalcP = call('callableRecalculateTOStats', {toId: w.TO}, otok);
  await sleep(60);
  await ledgerCancelOnly(appB);
  const recalc = await recalcP;
  observe('F3-a 겹친 재집계 응답', `${recalc.status}`);
  m = await awaitMatch(w);
  check('F3-a 오래된 재집계가 최종값을 덮지 않는다', m.matched, true,
    `expected=${JSON.stringify(m.exp)} derived=${JSON.stringify(m.der)}`);

  // (b) delta command 와 트리거를 겹친다
  await call('callableApplyToTO', applyWd1(w, workDate), tb);
  await awaitMatch(w);
  const cancelP = ledgerCancelOnly(appB);
  const decP = decrement(w, appB, tb);
  await Promise.all([cancelP, decP]);
  m = await awaitMatch(w);
  check('F3-b 증감과 절대 재계산이 겹쳐도 일치', m.matched, true,
    `expected=${JSON.stringify(m.exp)} derived=${JSON.stringify(m.der)}`);

  // (c) 마지막 한 자리 확정과 취소가 겹친다
  await call('callableApplyToTO', applyWd1(w, workDate), tb);
  await awaitMatch(w);
  const [c1, c2] = await Promise.all([
    call('callableConfirmApplication', {applicationId: appA, businessId: w.BIZ}, otok),
    call('callableConfirmApplication', {applicationId: appB, businessId: w.BIZ}, otok),
  ]);
  const okCount = [c1, c2].filter((r) => r.status === 200).length;
  check('F3-c 정원 1 — 확정 성공 1건', okCount, 1, `${c1.status}/${c2.status}`);
  m = await awaitMatch(w);
  check('F3-c 경합 후 일치', m.matched, true,
    `expected=${JSON.stringify(m.exp)} derived=${JSON.stringify(m.der)}`);

  // (d) 다른 업무(wd2)가 영향을 받지 않았다 — business/업무 격리
  const der = await derivedOf(w);
  const exp = await expectedOf(w);
  check('F3-d 다른 업무 카운터가 독립적이다',
    der.wdc[w.WD2] ?? {pending: 0, confirmed: 0},
    exp.perWd[w.WD2] ?? {pending: 0, confirmed: 0},
    `appA2=${appA2}`);

  // (e) 트리거 중복 실행 — 같은 상태에서 여러 번 재집계해도 같은 값
  for (let i = 0; i < 3; i++) await call('callableRecalculateTOStats', {toId: w.TO}, otok);
  m = await awaitMatch(w);
  check('F3-e 재집계 반복이 값을 바꾸지 않는다', m.matched, true, JSON.stringify(m.der));

  await cleanup(w);
}

(async () => {
  await f1();
  await f2();
  await f3();
  console.log(JSON.stringify({failures, results}, null, 2));
  process.exit(failures > 0 ? 1 : 0);
})().catch((e) => { console.error('HARNESS ERROR:', e); process.exit(2); });
