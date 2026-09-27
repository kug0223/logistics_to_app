/**
 * R8 O01 — 공고 합계(`to.totalPending` / `to.totalConfirmed`) stale 창.
 *
 *   7차에 슬롯·업무 축은 transaction 안으로 옮겨 닫았다. TO 축은 남겼다.
 *   그 축의 owner 는 이렇다:
 *
 *     절대 쓰기(transaction **밖** 읽기 + 무조건 update):
 *       · `_syncTOCounters` 비슬롯 분기            (index.ts:17747)
 *       · `_syncTOCounters` flex 분기              (index.ts:17787)
 *       · `callableRecalculateTOStats`             (index.ts:24501)
 *     delta 쓰기(transaction 안, FieldValue.increment): apply/confirm/cancel 등 다수
 *
 *   7차 수정으로 재집계는 **슬롯마다 transaction** 을 돌기 때문에 트리거보다
 *   훨씬 느려졌다. 그래서 "먼저 읽고 나중에 쓰는" 쪽이 마지막이 되기 쉽다.
 *   그 순서를 만들어 TO 합계가 낡은 값으로 남는지 본다.
 *
 *   판정은 원장에서 독립 산출한 기대값과의 일치다. 연속 같은 값으로 정착했다는
 *   것만으로 PASS 하지 않는다.
 *
 * 격리 에뮬레이터(demo-alfit-r7) 전용. 읽기·쓰기 모두 그 안에서만.
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
async function call(name, data, token, timeoutMs = 180000) {
  const ac = new AbortController();
  const timer = setTimeout(() => ac.abort(), timeoutMs);
  try {
    const r = await fetch(`${FN}/${name}`, {
      method: 'POST',
      headers: {'Content-Type': 'application/json',
        ...(token ? {Authorization: `Bearer ${token}`} : {}),
        'X-Firebase-AppCheck': 'r8-audit-emulator-token'},
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

const RUN = `r8t${Date.now().toString(36)}`;
const BIZ = `${RUN}biz`, TO = `${RUN}to`, WD = `${RUN}wd`, OWNER = `${RUN}own`;
const TARGET_SLOT = `${RUN}slot`;
const BULK_SLOTS = 60;
const BULK_PER_SLOT = 8;

const wd = () => ({wdId: WD, workType: '홀서빙', startTime: '09:00', endTime: '18:00',
  wage: 12000, wageType: 'hourly', requiredCount: 60});

async function seed() {
  const workDate = kstDayStart(Date.now()) + 3 * 86400000;
  try { await admin.auth().createUser({uid: OWNER}); } catch (e) {
    if (e.code !== 'auth/uid-already-exists') throw e;
  }
  await db.doc(`businesses/${BIZ}`).set({name: 'T', ownerId: OWNER,
    status: 'approved', isActive: true, adminIds: [OWNER],
    city: '강남구', address: '서울특별시 강남구 테헤란로 1'});
  await db.doc(`users/${OWNER}`).set({uid: OWNER, name: 'T 관리자',
    role: 'BUSINESS_ADMIN', businessId: BIZ, accountStatus: 'active'});

  const base = kstDayStart(Date.now()) - 86400000;
  await db.doc(`tos/${TO}`).set({id: TO, businessId: BIZ, title: 'T 공고',
    status: 'published', isPublic: true, isPublished: true, isDeleted: false,
    type: 'flex', createdBy: OWNER, workDetails: [wd()],
    totalRequired: 60, totalConfirmed: 0, totalPending: 0,
    publishedAt: admin.firestore.Timestamp.fromMillis(base),
    createdAt: admin.firestore.Timestamp.fromMillis(base)});

  const mkSlot = (sid) => ({id: sid, toId: TO, businessId: BIZ, status: 'open',
    isManualClosed: false,
    date: admin.firestore.Timestamp.fromMillis(workDate),
    workDetails: [wd()],
    workDetailCounts: {[WD]: {confirmedCount: 0, pendingCount: 0}},
    requiredCount: 60, confirmedCount: 0, pendingCount: 0});

  let batch = db.batch(); let n = 0;
  await db.doc(`tos/${TO}/slots/${TARGET_SLOT}`).set(mkSlot(TARGET_SLOT));
  for (let s = 0; s < BULK_SLOTS; s++) {
    const sid = `${RUN}bs${s}`;
    batch.set(db.doc(`tos/${TO}/slots/${sid}`), mkSlot(sid));
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
  // 대상 슬롯에 3명
  for (const tag of ['x', 'y', 'z']) {
    batch.set(db.doc(`applications/${RUN}t${tag}`), {
      uid: `${RUN}tu${tag}`, toId: TO, slotId: TARGET_SLOT, businessId: BIZ, wdId: WD,
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

/** 원장에서 독립 산출 — 파생값을 근거로 쓰지 않는다. */
async function expectedTotals() {
  let pending = 0, seated = 0;
  let cursor;
  for (;;) {
    let q = db.collection('applications').where('toId', '==', TO)
      .select('status', 'staffingReleasedAt', 'type', 'workEndDate', 'actualResignDate')
      .limit(500);
    if (cursor) q = q.startAfter(cursor);
    const page = await q.get();
    if (page.empty) break;
    for (const d of page.docs) {
      const st = d.get('status');
      if (PENDING.includes(st)) pending++;
      if (SEATED.includes(st) && d.get('staffingReleasedAt') == null) seated++;
    }
    if (page.size < 500) break;
    cursor = page.docs[page.size - 1];
  }
  return {pending, seated};
}
async function storedTotals() {
  const t = (await db.doc(`tos/${TO}`).get()).data() || {};
  return {pending: t.totalPending ?? null, seated: t.totalConfirmed ?? null,
    statsUpdatedAt: t.statsUpdatedAt?.toMillis?.() ?? null};
}
async function storedTargetSlot() {
  const s = (await db.doc(`tos/${TO}/slots/${TARGET_SLOT}`).get()).data() || {};
  const e = s.workDetailCounts?.[WD] || {};
  return {slotPending: s.pendingCount ?? null, slotConfirmed: s.confirmedCount ?? null,
    wdP: e.pendingCount ?? null, wdC: e.confirmedCount ?? null};
}
async function expectedTargetSlot() {
  const apps = await db.collection('applications')
    .where('toId', '==', TO).where('slotId', '==', TARGET_SLOT).get();
  let p = 0, c = 0;
  apps.forEach((d) => {
    const a = d.data();
    if (PENDING.includes(a.status)) p++;
    if (SEATED.includes(a.status) && a.staffingReleasedAt == null) c++;
  });
  return {pending: p, confirmed: c};
}

/** TO 합계가 기대와 같아질 때까지 — bounded. 못 맞추면 미수렴으로 남긴다. */
async function awaitTotals({maxMs = 90000} = {}) {
  const t0 = Date.now(); let last = null;
  for (;;) {
    const e = await expectedTotals(); const s = await storedTotals();
    last = {e, s};
    if (s.pending === e.pending && s.seated === e.seated) {
      return {matched: true, elapsedMs: Date.now() - t0, ...last};
    }
    if (Date.now() - t0 > maxMs) return {matched: false, elapsedMs: Date.now() - t0, ...last};
    await sleep(300);
  }
}

(async () => {
  await seed();
  const otok = await idToken(OWNER);
  const totalApps = BULK_SLOTS * BULK_PER_SLOT + 3;
  observe('T0 규모', `슬롯 ${BULK_SLOTS + 1} · 지원서 ${totalApps}`);

  // 기준선 — 재집계로 맞춘다. 동시에 소요 시간을 잰다.
  const t0 = Date.now();
  const warm = await call('callableRecalculateTOStats', {toId: TO}, otok);
  const recalcMs = Date.now() - t0;
  observe('T1 재집계 소요', `${warm.status} ${recalcMs}ms`);
  let m = await awaitTotals();
  check('T1 기준선 TO 합계 일치', m.matched, true,
    `기대=${JSON.stringify(m.e)} 저장=${JSON.stringify(m.s)}`);

  if (recalcMs < 1500) {
    observe('T2 판정 보류 — 재집계가 빨라 창을 만들 수 없다', `${recalcMs}ms`);
  } else {
    // ── 창: 느린 재집계가 읽은 뒤 원장이 바뀌고, 재집계가 마지막에 쓴다 ──
    const startedAt = Date.now();
    const slowP = call('callableRecalculateTOStats', {toId: TO}, otok);
    await sleep(700); // 재집계가 원장 스캔을 끝내고 슬롯 transaction 구간에 들어간 뒤

    // 대상 슬롯의 한 명을 취소 — 원장만 바꾼다(트리거가 깨어난다).
    await db.doc(`applications/${RUN}tx`).update({
      status: 'CANCELED', canceledAt: admin.firestore.FieldValue.serverTimestamp()});
    const cancelAt = Date.now() - startedAt;

    // 트리거가 먼저 정답을 쓰는지 본다.
    const afterTrigger = await awaitTotals({maxMs: 30000});
    observe('T2 트리거 수렴',
      `${afterTrigger.matched} ${afterTrigger.elapsedMs}ms ` +
      `저장=${JSON.stringify(afterTrigger.s)}`, `취소 시점 +${cancelAt}ms`);

    const slow = await slowP;
    observe('T2 느린 재집계 응답',
      `${slow.status} 총 ${Date.now() - startedAt}ms`);

    // 후속 이벤트 없이 둔다 — 낡은 값이 남는지 본다.
    await sleep(4000);
    const e = await expectedTotals(); const s = await storedTotals();
    check('T2 낡은 재집계가 TO 합계를 덮지 않는다',
      {pending: s.pending, seated: s.seated}, {pending: e.pending, seated: e.seated},
      `기대=${JSON.stringify(e)} 저장=${JSON.stringify(s)} ` +
      '(불일치면 TO 축 stale overwrite 재현 = 결함)');

    // 슬롯·업무 축은 7차에 닫았다 — 같은 순서에서 여전히 맞는지 확인한다.
    const se = await expectedTargetSlot(); const ss = await storedTargetSlot();
    check('T2 슬롯·업무 축은 영향 없다',
      {sp: ss.slotPending, sc: ss.slotConfirmed, wp: ss.wdP, wc: ss.wdC},
      {sp: se.pending, sc: se.confirmed, wp: se.pending, wc: se.confirmed},
      `기대=${JSON.stringify(se)} 저장=${JSON.stringify(ss)}`);
  }

  // ── T3 delta 와 절대 쓰기의 경합 — 확정 delta 가 사라지는지 ────────────
  const startedAt2 = Date.now();
  const slow2 = call('callableRecalculateTOStats', {toId: TO}, otok);
  await sleep(400);
  // 좌석 delta 를 직접 만든다(원장 + TO 합계 증가) — confirm CF 와 같은 write set.
  await db.runTransaction(async (tx) => {
    tx.update(db.collection('applications').doc(`${RUN}ty`),
      {status: 'CONTRACT_PENDING'});
    tx.update(db.doc(`tos/${TO}`), {
      totalPending: admin.firestore.FieldValue.increment(-1),
      totalConfirmed: admin.firestore.FieldValue.increment(1),
    });
  });
  const afterDelta = await awaitTotals({maxMs: 30000});
  observe('T3 delta 후 수렴', `${afterDelta.matched} ${afterDelta.elapsedMs}ms`);
  await slow2;
  observe('T3 느린 재집계 응답', `총 ${Date.now() - startedAt2}ms`);
  await sleep(4000);
  const e3 = await expectedTotals(); const s3 = await storedTotals();
  check('T3 낡은 절대 쓰기가 delta 를 지우지 않는다',
    {pending: s3.pending, seated: s3.seated},
    {pending: e3.pending, seated: e3.seated},
    `기대=${JSON.stringify(e3)} 저장=${JSON.stringify(s3)}`);

  // ── T4 torn read — 스캔 중 연속 변경 후 정적 상태에서 대조 ───────────────
  //
  //   절대 writer 는 원장을 `while` 페이지네이션(`countCommittedSeats`)과
  //   별도 `.count()` 로 **두 번** 읽는다. 두 읽기는 서로 다른 순간이고
  //   페이지 사이에도 틈이 있다. 그 틈에 상태가 바뀌면 한 스냅샷 안에서
  //   앞뒤가 어긋난 값이 계산될 수 있다.
  //
  //   burst 로 변경을 몰아넣고, 그 뒤 **정적 상태**에서 원장과 대조한다.
  //   정적 상태에서 틀리면 낡은/찢어진 쓰기가 마지막으로 남았다는 뜻이다.
  {
    const ids = [];
    for (let s = 0; s < 6; s++) {
      for (let i = 0; i < 6; i++) ids.push(`${RUN}b${s}_${i}`);
    }
    const before = await expectedTotals();
    observe('T4 burst 전 원장', JSON.stringify(before));

    // 재집계 두 개를 겹쳐 띄우고 그 위에 변경을 몰아넣는다.
    const r1 = call('callableRecalculateTOStats', {toId: TO}, otok);
    const r2 = call('callableRecalculateTOStats', {toId: TO}, otok);
    const muts = [];
    for (const id of ids) {
      muts.push(db.doc(`applications/${id}`).update({
        status: 'CANCELED',
        canceledAt: admin.firestore.FieldValue.serverTimestamp()}));
      await sleep(60);
    }
    await Promise.all(muts);
    await Promise.all([r1, r2]);

    // 정적 상태를 기다린 뒤 대조한다.
    const settled = await awaitTotals({maxMs: 120000});
    observe('T4 수렴', `${settled.matched} ${settled.elapsedMs}ms`);
    await sleep(6000);
    const e4 = await expectedTotals(); const s4 = await storedTotals();
    check('T4 burst 후 정적 상태에서 TO 합계가 원장과 같다',
      {pending: s4.pending, seated: s4.seated},
      {pending: e4.pending, seated: e4.seated},
      `변경 ${ids.length}건 · 기대=${JSON.stringify(e4)} 저장=${JSON.stringify(s4)}`);
  }

  // ── T5 재집계 경합 중 정상 요청이 부당하게 거절되는가 ────────────────────
  //
  //   7차에 "대규모 재집계와 동시에 돌면 수렴이 71.8초" 라고 적었다.
  //   그 시간 자체보다 중요한 것은 **그 사이 사용자 요청이 어떻게 되는가** 다.
  //   슬롯 카운터는 이제 transaction 안에서 갱신되므로 apply 와 슬롯 문서를
  //   두고 경합한다. 정원 guard 는 그 파생값을 읽는다.
  //
  //   그래서 재집계가 도는 동안 **정상 지원**을 여러 번 보내고,
  //   성공/실패와 실패 사유·소요를 기록한다. 임의 SLA 를 만들지 않는다.
  {
    const W = `${RUN}w1`;
    try { await admin.auth().createUser({uid: W}); } catch (e) {
      if (e.code !== 'auth/uid-already-exists') throw e;
    }
    await db.doc(`users/${W}`).set({uid: W, name: 'T 근로자', role: 'USER',
      accountStatus: 'active', passVerifiedAt: admin.firestore.Timestamp.now(),
      isIdVerified: true, idCardImagePath: `id_cards/${W}/id.jpg`,
      bankName: '국민', accountNumber: 'enc', accountHolder: 'T',
      bankbookImagePath: `bankbooks/${W}/b.jpg`,
      termsConsentAt: admin.firestore.Timestamp.now(),
      isBlacklisted: false, isForeign: false,
      idDocumentVersion: 1, bankbookDocumentVersion: 1, bankAccountVersion: 1});
    await db.doc(`businessApplicantDocumentReviews/${BIZ}_${W}`).set({
      businessId: BIZ, workerUid: W,
      idDecision: 'REVIEWED_OK', reviewedIdDocumentVersion: 1,
      bankDecision: 'REVIEWED_OK',
      reviewedBankbookDocumentVersion: 1, reviewedBankAccountVersion: 1});
    const wtok = await idToken(W);
    const workDate = kstDayStart(Date.now()) + 3 * 86400000;
    const payload = {
      toId: TO, slotId: TARGET_SLOT, businessId: BIZ, businessName: 'T',
      toTitle: 'T', workDateMs: workDate, selectedWorkType: '홀서빙',
      workDetailId: WD, startTime: '09:00', endTime: '18:00',
      wage: 12000, wageType: 'hourly',
      idCardConsentGiven: true, documentAccessConsentGiven: true,
      documentAccessConsentVersion: '2026-09-18-v3',
    };

    const recalcStart = Date.now();
    const rP = call('callableRecalculateTOStats', {toId: TO}, otok);
    const attempts = [];
    for (let i = 0; i < 5; i++) {
      const t = Date.now();
      const r = await call('callableApplyToTO', payload, wtok);
      attempts.push({i, status: r.status, ms: Date.now() - t,
        msg: r.status === 200 ? 'ok'
          : String(r.body?.error?.message ?? r.body?.error ?? '').slice(0, 60)});
      await sleep(150);
    }
    const rr = await rP;
    observe('T5 재집계 소요·응답',
      `${rr.status} ${Date.now() - recalcStart}ms`);
    observe('T5 경합 중 지원 시도', JSON.stringify(attempts));

    // 첫 지원은 성공해야 하고, 그 뒤는 중복(409)이어야 한다.
    const first = attempts[0];
    check('T5 경합 중에도 첫 지원이 성공한다', first.status, 200, first.msg);
    const rest = attempts.slice(1);
    check('T5 이후 시도는 중복으로만 막힌다',
      rest.every((a) => a.status === 409), true, JSON.stringify(rest));
    // 정원 초과 오판이 없어야 한다.
    check('T5 정원 미달인데 마감으로 거절하지 않는다',
      attempts.some((a) => /모집 인원이 마감/.test(a.msg)), false,
      JSON.stringify(attempts));

    const settled2 = await awaitTotals({maxMs: 120000});
    observe('T5 수렴', `${settled2.matched} ${settled2.elapsedMs}ms`);
    const e5 = await expectedTotals(); const s5 = await storedTotals();
    check('T5 경합 후 TO 합계가 원장과 같다',
      {pending: s5.pending, seated: s5.seated},
      {pending: e5.pending, seated: e5.seated},
      `기대=${JSON.stringify(e5)} 저장=${JSON.stringify(s5)}`);
    const se5 = await expectedTargetSlot(); const ss5 = await storedTargetSlot();
    check('T5 경합 후 슬롯·업무 축도 원장과 같다',
      {sp: ss5.slotPending, wp: ss5.wdP},
      {sp: se5.pending, wp: se5.pending},
      `기대=${JSON.stringify(se5)} 저장=${JSON.stringify(ss5)}`);

    await db.doc(`users/${W}`).delete().catch(() => {});
    await db.doc(`businessApplicantDocumentReviews/${BIZ}_${W}`).delete().catch(() => {});
  }

  console.log(JSON.stringify({run: RUN, failures, results}, null, 2));
  await cleanup();
  process.exit(failures > 0 ? 1 : 0);
})().catch((e) => { console.error('HARNESS ERROR:', e); process.exit(2); });
