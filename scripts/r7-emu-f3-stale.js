/**
 * R7 7차 §3 — 마지막 stale 절대 재계산이 최신 값을 덮는가.
 *
 *   경계(코드 확인): `_syncTOCounters` 와 `callableRecalculateTOStats` 는
 *   원장을 **transaction 밖** 쿼리로 읽고 `db.batch()` 로 **무조건** 쓴다.
 *   conflict detection 도 precondition 도 없다. 그래서 다음이 구조상 가능하다:
 *
 *     r1: A 가 원장을 읽는다
 *     t2: 새 이벤트가 커밋된다
 *     r2: B 가 원장을 읽는다(새 상태 포함)
 *     w2: B 가 쓴다 (정확)
 *     w1: A 가 쓴다 (낡음) ← 최신을 덮는다
 *     그 뒤 이벤트가 없으면 낡은 값이 남는다.
 *
 *   product 코드에 barrier 를 넣지 않고 **부하로** 창을 만든다:
 *   지원서를 많이 깔면 재집계의 읽기+계산이 길어지고, 그 사이에 원장을 바꿔
 *   트리거를 먼저 끝내 버릴 수 있다.
 *
 *   판정은 원장 기대값과의 일치다. 마지막 값이 틀리고 후속 이벤트가 없으면
 *   재현 성공(= 결함 확인)이다.
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
async function call(name, data, token, timeoutMs = 120000) {
  const ac = new AbortController();
  const timer = setTimeout(() => ac.abort(), timeoutMs);
  try {
    const r = await fetch(`${FN}/${name}`, {
      method: 'POST',
      headers: {'Content-Type': 'application/json',
        ...(token ? {Authorization: `Bearer ${token}`} : {}),
        'X-Firebase-AppCheck': 'r7-audit-emulator-token'},
      body: JSON.stringify({data}), signal: ac.signal});
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

const RUN = `r7s${Date.now().toString(36)}`;
const BIZ = `${RUN}biz`, TO = `${RUN}to`, SLOT = `${RUN}slot`, WD = `${RUN}wd`;
const OWNER = `${RUN}own`;
/** 재집계를 느리게 만들기 위한 부하 — 같은 TO 의 다른 슬롯들에 지원서를 깐다. */
const BULK_SLOTS = 12;
const BULK_PER_SLOT = 40;

async function seed() {
  const workDate = kstDayStart(Date.now()) + 3 * 86400000;
  try { await admin.auth().createUser({uid: OWNER}); } catch (e) {
    if (e.code !== 'auth/uid-already-exists') throw e;
  }
  await db.doc(`businesses/${BIZ}`).set({name: 'S', ownerId: OWNER,
    status: 'approved', isActive: true, adminIds: [OWNER],
    city: '강남구', address: '서울특별시 강남구 테헤란로 1'});
  await db.doc(`users/${OWNER}`).set({uid: OWNER, name: 'S 관리자',
    role: 'BUSINESS_ADMIN', businessId: BIZ, accountStatus: 'active'});

  const wd = {wdId: WD, workType: '홀서빙', startTime: '09:00', endTime: '18:00',
    wage: 12000, wageType: 'hourly', requiredCount: 50};
  const base = kstDayStart(Date.now()) - 86400000;
  await db.doc(`tos/${TO}`).set({id: TO, businessId: BIZ, title: 'S 공고',
    status: 'published', isPublic: true, isPublished: true, isDeleted: false,
    type: 'flex', createdBy: OWNER, workDetails: [wd],
    totalRequired: 50, totalConfirmed: 0, totalPending: 0,
    publishedAt: admin.firestore.Timestamp.fromMillis(base),
    createdAt: admin.firestore.Timestamp.fromMillis(base)});

  // 대상 슬롯
  await db.doc(`tos/${TO}/slots/${SLOT}`).set({id: SLOT, toId: TO, businessId: BIZ,
    status: 'open', isManualClosed: false,
    date: admin.firestore.Timestamp.fromMillis(workDate),
    workDetails: [wd], workDetailCounts: {[WD]: {confirmedCount: 0, pendingCount: 0}},
    requiredCount: 50, confirmedCount: 0, pendingCount: 0});

  // 부하 슬롯 + 지원서 — 원장을 크게 만들어 재집계 시간을 늘린다.
  let batch = db.batch(); let n = 0;
  for (let s = 0; s < BULK_SLOTS; s++) {
    const sid = `${RUN}bs${s}`;
    batch.set(db.doc(`tos/${TO}/slots/${sid}`), {id: sid, toId: TO, businessId: BIZ,
      status: 'open', isManualClosed: false,
      date: admin.firestore.Timestamp.fromMillis(workDate),
      workDetails: [wd], workDetailCounts: {[WD]: {confirmedCount: 0, pendingCount: 0}},
      requiredCount: 50, confirmedCount: 0, pendingCount: 0});
    n++;
    for (let i = 0; i < BULK_PER_SLOT; i++) {
      batch.set(db.doc(`applications/${RUN}b${s}_${i}`), {
        uid: `${RUN}u${s}_${i}`, toId: TO, slotId: sid, businessId: BIZ, wdId: WD,
        status: 'PENDING', selectedWorkType: '홀서빙',
        startTime: '09:00', endTime: '18:00',
        workDate: admin.firestore.Timestamp.fromMillis(workDate),
        createdAt: admin.firestore.Timestamp.now()});
      n++;
      if (n >= 450) { await batch.commit(); batch = db.batch(); n = 0; }
    }
  }
  // 대상 슬롯에 2명
  for (const tag of ['x', 'y']) {
    batch.set(db.doc(`applications/${RUN}t${tag}`), {
      uid: `${RUN}tu${tag}`, toId: TO, slotId: SLOT, businessId: BIZ, wdId: WD,
      status: 'PENDING', selectedWorkType: '홀서빙',
      startTime: '09:00', endTime: '18:00',
      workDate: admin.firestore.Timestamp.fromMillis(workDate),
      createdAt: admin.firestore.Timestamp.now()});
    n++;
  }
  if (n > 0) await batch.commit();
  return {workDate};
}

async function cleanup() {
  for (;;) {
    const snap = await db.collection('applications').where('toId', '==', TO).limit(400).get();
    if (snap.empty) break;
    const b = db.batch();
    snap.docs.forEach((d) => b.delete(d.ref));
    await b.commit();
  }
  const slots = await db.collection(`tos/${TO}/slots`).get();
  for (const d of slots.docs) await d.ref.delete().catch(() => {});
  await db.doc(`tos/${TO}`).delete().catch(() => {});
  await db.doc(`businesses/${BIZ}`).delete().catch(() => {});
  await sleep(1800);
  await db.doc(`users/${OWNER}`).delete().catch(() => {});
}

async function expectedTarget() {
  const apps = await db.collection('applications')
    .where('toId', '==', TO).where('slotId', '==', SLOT).get();
  let p = 0, c = 0;
  apps.forEach((d) => {
    const a = d.data();
    if (PENDING.includes(a.status)) p++;
    if (SEATED.includes(a.status) && a.staffingReleasedAt == null) c++;
  });
  return {pending: p, confirmed: c};
}
async function derivedTarget() {
  const s = (await db.doc(`tos/${TO}/slots/${SLOT}`).get()).data() || {};
  const e = s.workDetailCounts?.[WD] || {};
  return {slotPending: s.pendingCount ?? null, slotConfirmed: s.confirmedCount ?? null,
    wdP: e.pendingCount ?? null, wdC: e.confirmedCount ?? null};
}
async function matches() {
  const e = await expectedTarget(); const d = await derivedTarget();
  return {ok: d.slotPending === e.pending && d.wdP === e.pending &&
    d.slotConfirmed === e.confirmed && d.wdC === e.confirmed, e, d};
}
async function awaitMatch({maxMs = 30000} = {}) {
  const t0 = Date.now(); let last = null;
  for (;;) {
    last = await matches();
    if (last.ok) return {matched: true, elapsedMs: Date.now() - t0, ...last};
    if (Date.now() - t0 > maxMs) return {matched: false, elapsedMs: Date.now() - t0, ...last};
    await sleep(250);
  }
}

(async () => {
  await seed();
  const otok = await idToken(OWNER);

  let m = await awaitMatch();
  observe('S0 seed 후 정합(카운터는 seed 값 0 이라 불일치가 정상)',
    `${m.matched} expected=${JSON.stringify(m.e)} derived=${JSON.stringify(m.d)}`);

  // 기준선 — 재집계로 맞춰 둔다.
  const t0 = Date.now();
  const warm = await call('callableRecalculateTOStats', {toId: TO}, otok);
  const recalcMs = Date.now() - t0;
  observe('S1 재집계 1회 소요', `${warm.status} ${recalcMs}ms`,
    `부하: 슬롯 ${BULK_SLOTS + 1}개 · 지원서 ${BULK_SLOTS * BULK_PER_SLOT + 2}건`);
  m = await awaitMatch();
  check('S1 기준선 일치', m.matched, true,
    `expected=${JSON.stringify(m.e)} derived=${JSON.stringify(m.d)}`);

  if (recalcMs < 400) {
    observe('S2 판정 보류 — 재집계가 너무 빨라 창을 만들 수 없다',
      `${recalcMs}ms`, '부하를 더 키워야 재현 가능');
  } else {
    // ── 창 만들기 ──────────────────────────────────────────────────────
    //   느린 재집계를 띄우고, 그 사이에 원장을 바꿔 트리거를 먼저 끝낸다.
    const slowP = call('callableRecalculateTOStats', {toId: TO}, otok);
    await sleep(Math.min(200, Math.floor(recalcMs / 4)));

    // 대상 슬롯의 한 명을 취소 — 원장만 바꾼다(트리거가 깨어난다).
    await db.doc(`applications/${RUN}tx`).update({
      status: 'CANCELED', canceledAt: admin.firestore.FieldValue.serverTimestamp()});

    // 트리거가 정답을 쓰는 것을 먼저 확인한다.
    const afterTrigger = await awaitMatch({maxMs: 20000});
    observe('S2 트리거 먼저 수렴',
      `${afterTrigger.matched} derived=${JSON.stringify(afterTrigger.d)}`);

    // 이제 낡은 재집계가 끝난다.
    const slow = await slowP;
    observe('S2 느린 재집계 응답', String(slow.status));

    // 후속 이벤트 없이 잠시 둔다 — 낡은 값이 남는지 본다.
    await sleep(3000);
    const after = await matches();
    check('S2 낡은 재집계가 최신 카운터를 덮지 않는다', after.ok, true,
      `expected=${JSON.stringify(after.e)} derived=${JSON.stringify(after.d)} ` +
      '(불일치면 stale overwrite 재현 성공 = 결함)');

    // 한 번 더, 순서를 반대로 — 재집계가 먼저 끝나고 트리거가 나중
    await db.doc(`applications/${RUN}ty`).update({
      status: 'CANCELED', canceledAt: admin.firestore.FieldValue.serverTimestamp()});
    const m2 = await awaitMatch({maxMs: 90000});
    observe('S3 반대 순서 수렴 시간', m2.elapsedMs + 'ms matched=' + m2.matched);
    check('S3 반대 순서에서도 최종 일치', m2.matched, true,
      `expected=${JSON.stringify(m2.e)} derived=${JSON.stringify(m2.d)}`);
  }

  // ── S4 같은 owner 의 replay — 0-reset 과 최신 값 보존 ──────────────────
  for (let i = 0; i < 3; i++) await call('callableRecalculateTOStats', {toId: TO}, otok);
  const m4 = await awaitMatch();
  check('S4 재집계 replay 후에도 일치(0-reset 이 최신을 지우지 않는다)', m4.matched, true,
    `expected=${JSON.stringify(m4.e)} derived=${JSON.stringify(m4.d)}`);

  console.log(JSON.stringify({run: RUN, failures, results}, null, 2));
  await cleanup();
  process.exit(failures > 0 ? 1 : 0);
})().catch((e) => { console.error('HARNESS ERROR:', e); process.exit(2); });
