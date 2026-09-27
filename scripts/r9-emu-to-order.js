/**
 * R9 O01 — 공고 합계(`to.totalPending`/`totalConfirmed`)의 **저장 순서**.
 *
 *   묻는 것은 하나다: 먼저 읽은 스냅샷이 **마지막에 커밋될 수 있는가.**
 *
 *   8차는 이 순서를 시험하지 못했다. 그때 fixture 는 지원서 483건이라
 *   재집계의 원장 스캔이 **1페이지**였고(`limit(499)`), 취소를 호출 +700ms 에
 *   넣었다 — 그 시점엔 TO 쓰기가 이미 끝나 있었다(슬롯 transaction 구간).
 *   그래서 "간격이 짧다"는 관측이 나왔고, 그건 창을 줄이는 설명이었다.
 *
 *   이번에는 그 창 **안쪽**에 B 를 넣는다. 제품에는 아무것도 주입하지 않는다.
 *
 *     ① 대상 지원서의 docId 를 가장 앞에 둔다. 스캔 질의
 *        (`toId==` + `businessId==` + `limit(499)`)에는 orderBy 가 없으므로
 *        Firestore 가 `__name__` 오름차순을 붙인다 → 대상은 **1페이지**에 있다.
 *     ② 같은 공고에 ballast 지원서를 넣어 스캔을 여러 페이지로 만든다.
 *        → A 가 대상을 읽은 시점과 A 가 TO 를 쓰는 시점 사이에 남은
 *          페이지 읽기가 들어간다. 그게 창이다.
 *     ③ 그 창 안에서 원장을 바꾼다(취소). 트리거 B 가 최신값을 커밋한다.
 *     ④ 순서는 추론하지 않는다. TO 문서 listener 로 **커밋 시각**
 *        (`snapshot.updateTime`, 서버 시각)을 전부 기록해 실제 순서를 남긴다.
 *
 *   ballast 는 `status` 필드가 없다. 제품 트리거가 스스로 건너뛰는 모양
 *   (index.ts:17380 `beforeStatus === afterStatus` → return)이라 seeding 이
 *   트리거 폭풍을 만들지 않는다. 카운터에는 0 을 기여한다 —
 *   스캔 루프(index.ts:24427~)의 분기는 `status` 가 없을 때와
 *   `CANCELED` 일 때가 **같다**(`isPending` false, `CONFIRMED_STATUSES.includes`
 *   false). 즉 이 재현은 ballast 의 status 에 의존하지 않는다.
 *   제품 전제조건은 "한 공고의 전체 지원서(상태 무관) > 499" 뿐이다.
 *
 *   판정은 원장에서 독립 산출한 기대값과 저장값의 비교다. 순서를 못 만들면
 *   PASS 가 아니라 **INCONCLUSIVE** 로 남긴다 — 고정 sleep 으로 판정하지 않는다.
 *
 * 격리 에뮬레이터(demo-alfit-r7) 전용.
 *
 * ⚠ 다른 하네스와 같은 세션에서 돌릴 때는 **이것을 마지막에** 두거나 에뮬레이터를
 *   다시 띄운다. seeding·cleanup 이 ballast 만큼 no-op 트리거 이벤트를 만들어
 *   (제품 가드로 각 2ms 지만 invocation 비용이 있다) 다음 하네스의 트리거가
 *   수십 초 늦게 실행된다. 그 지연을 제품 결함으로 읽지 않도록 주의한다.
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
async function call(name, data, token, timeoutMs = 240000) {
  const ac = new AbortController();
  const timer = setTimeout(() => ac.abort(), timeoutMs);
  try {
    const r = await fetch(`${FN}/${name}`, {
      method: 'POST',
      headers: {'Content-Type': 'application/json',
        ...(token ? {Authorization: `Bearer ${token}`} : {}),
        'X-Firebase-AppCheck': 'r9-audit-emulator-token'},
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

/**
 * 에뮬레이터 로그에서 "낡은 스냅샷이라 건너뜀" 횟수를 센다.
 *
 *   수정 후에는 A 의 쓰기가 **사라진다** — 그래서 TO 문서만 보면 A 가 언제
 *   쓰려 했는지 알 수 없다. CF 가 남기는 skip 로그가 그 증거다.
 *   로그 경로를 주지 않으면 이 증거는 수집하지 않는다(없다고 적는다).
 */
const EMU_LOG = process.env.R9_EMU_LOG || '';
const fsp = require('fs');
function skipCount() {
  if (!EMU_LOG) return null;
  try {
    // `[srvCommitToTotals]` 태그는 skip 경로에서만 찍는다. ASCII 라 인코딩과 무관하다.
    const s = fsp.readFileSync(EMU_LOG, 'latin1');
    return (s.match(/\[srvCommitToTotals\]/g) || []).length;
  } catch { return null; }
}

const RUN = `r9o${Date.now().toString(36)}`;
const BIZ = `${RUN}biz`, TO = `${RUN}to`, WD = `${RUN}wd`, OWNER = `${RUN}own`;
const SLOTS = ['s0', 's1', 's2'].map((s) => `${RUN}${s}`);
// ballast: 스캔을 여러 페이지로 만든다. 499/page.
const BALLAST = Number(process.env.R9_BALLAST || 4000);
// canary: 트리거 큐가 비었는지 제품 트리거로 재는 용도.
//   status 를 CANCELED ↔ AUTO_CANCELED 로 번갈아 쓴다 — 둘 다 대기도 좌석도
//   아니므로 기대값이 변하지 않고, 트리거는 매번 전체 재계산을 돌린다.
const CANARY = `${RUN}_a_canary`;
// 대상 지원서 — docId 가 ballast 보다 앞이어야 1페이지에 들어간다.
const TGT = (n) => `${RUN}_a_t${n}`;
const TARGETS_PENDING = [1, 2, 3, 4, 5, 6];
const TARGETS_SEATED = [7, 8];

const wd = () => ({wdId: WD, workType: '홀서빙', startTime: '09:00', endTime: '18:00',
  wage: 12000, wageType: 'hourly', requiredCount: 40});

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
    totalRequired: 40, totalConfirmed: 0, totalPending: 0,
    publishedAt: admin.firestore.Timestamp.fromMillis(base),
    createdAt: admin.firestore.Timestamp.fromMillis(base)});

  for (const sid of SLOTS) {
    await db.doc(`tos/${TO}/slots/${sid}`).set({id: sid, toId: TO, businessId: BIZ,
      status: 'open', isManualClosed: false,
      date: admin.firestore.Timestamp.fromMillis(workDate),
      workDetails: [wd()],
      workDetailCounts: {[WD]: {confirmedCount: 0, pendingCount: 0}},
      requiredCount: 40, confirmedCount: 0, pendingCount: 0});
  }

  const mkApp = (uid, status) => {
    const d = {uid, toId: TO, slotId: SLOTS[0], businessId: BIZ, wdId: WD,
      selectedWorkType: '홀서빙', startTime: '09:00', endTime: '18:00',
      workDate: admin.firestore.Timestamp.fromMillis(workDate),
      createdAt: admin.firestore.Timestamp.now()};
    if (status) d.status = status;
    return d;
  };

  // ballast — status 필드 없음(트리거가 제품 가드로 스스로 건너뛴다).
  let batch = db.batch(); let n = 0;
  for (let i = 0; i < BALLAST; i++) {
    const id = `${RUN}_z_${String(i).padStart(6, '0')}`;
    batch.set(db.doc(`applications/${id}`),
      {...mkApp(`${RUN}zu${i}`, null), slotId: SLOTS[i % SLOTS.length]});
    if (++n >= 450) { await batch.commit(); batch = db.batch(); n = 0; }
  }
  if (n > 0) await batch.commit();

  await db.doc(`applications/${CANARY}`).set(mkApp(`${RUN}cu`, 'CANCELED'));

  // 대상 — docId 가 가장 앞이다.
  for (const t of TARGETS_PENDING) {
    await db.doc(`applications/${TGT(t)}`).set(mkApp(`${RUN}tu${t}`, 'PENDING'));
  }
  for (const t of TARGETS_SEATED) {
    await db.doc(`applications/${TGT(t)}`).set(mkApp(`${RUN}tu${t}`, 'CONFIRMED'));
  }
  return {workDate};
}

async function cleanup() {
  for (;;) {
    const snap = await db.collection('applications').where('toId', '==', TO).limit(450).get();
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

/** 원장에서 독립 산출 — 파생값을 근거로 쓰지 않는다. 제품과 같은 술어다. */
async function expectedTotals() {
  let pending = 0, seated = 0, cursor;
  for (;;) {
    let q = db.collection('applications').where('toId', '==', TO)
      .select('status', 'staffingReleasedAt', 'type', 'workEndDate', 'actualResignDate')
      .limit(450);
    if (cursor) q = q.startAfter(cursor);
    const page = await q.get();
    if (page.empty) break;
    for (const d of page.docs) {
      const st = d.get('status');
      if (PENDING.includes(st)) pending++;
      if (SEATED.includes(st) && d.get('staffingReleasedAt') == null) seated++;
    }
    if (page.size < 450) break;
    cursor = page.docs[page.size - 1];
  }
  return {pending, seated};
}
async function storedTotals() {
  const snap = await db.doc(`tos/${TO}`).get();
  const t = snap.data() || {};
  return {pending: t.totalPending ?? null, seated: t.totalConfirmed ?? null,
    // statsUpdatedAt 은 **트리거만** 쓴다(index.ts:17750·17790).
    //   재집계(index.ts:24501)는 쓰지 않는다 → 마지막 writer 의 지문이다.
    statsAt: t.statsUpdatedAt?.toMillis?.() ?? null,
    docCommitMs: snap.updateTime?.toMillis?.() ?? null};
}

/**
 * TO 문서의 커밋을 **서버 시각**으로 기록한다 — 순서의 근거.
 *   listener 는 연속 커밋을 합칠 수 있으므로(중간 revision 누락 가능)
 *   짧은 주기 polling 으로도 같이 기록한다. 둘은 독립 기록이다.
 */
function watchTO() {
  const revs = [];
  const errs = [];
  const push = (src, snap) => {
    if (!snap.exists) return;
    const d = snap.data();
    const commitMs = snap.updateTime.toMillis();
    if (revs.some((r) => r.commitMs === commitMs)) return;
    revs.push({src, commitMs, commitIso: snap.updateTime.toDate().toISOString(),
      p: d.totalPending ?? null, c: d.totalConfirmed ?? null,
      statsAt: d.statsUpdatedAt?.toMillis?.() ?? null, atMs: Date.now()});
  };
  const unsubL = db.doc(`tos/${TO}`).onSnapshot(
    (s) => push('listen', s), (e) => errs.push(String(e)));
  let stop = false;
  (async () => {
    while (!stop) {
      try { push('poll', await db.doc(`tos/${TO}`).get()); } catch (e) { errs.push(String(e)); }
      await sleep(100);
    }
  })();
  return {revs, errs, unsub: () => { stop = true; unsubL(); }};
}
/** 커밋이 멎을 때까지 — bounded. 최소 대기 시간을 보장한다. */
async function quiesce(revs, {quietMs = 5000, minMs = 10000, maxMs = 120000} = {}) {
  const t0 = Date.now();
  for (;;) {
    const last = revs.length ? revs[revs.length - 1].atMs : t0;
    const quiet = Date.now() - last > quietMs;
    if (quiet && Date.now() - t0 > minMs) return Date.now() - t0;
    if (Date.now() - t0 > maxMs) return -1;
    await sleep(250);
  }
}
/**
 * 트리거 큐가 비었는지 **제품 트리거로** 잰다.
 *
 *   ballast 를 넣으면 그만큼 트리거 이벤트가 생긴다. 제품 가드
 *   (index.ts:17380)로 각 2ms 에 끝나지만 invocation 자체의 비용이 있어
 *   수천 건이면 큐가 밀린다. 그 상태에서 B 를 넣으면 **B 가 창 안에서
 *   실행되지 않는다** — 그건 요청된 순서가 아니다.
 *
 *   canary 의 status 를 바꾸면 트리거가 전체 재계산을 하고
 *   `statsUpdatedAt`(트리거 전용 필드)을 쓴다. 그 왕복 시간이 곧 큐 지연이다.
 *   목표 지연 아래로 내려갈 때까지 기다린 뒤 본 시험을 시작한다.
 */
async function drainTriggers({targetMs = 1500, maxMs = 900000} = {}) {
  const t0 = Date.now();
  const samples = [];
  let flip = 0;
  for (;;) {
    const before = (await storedTotals()).statsAt ?? 0;
    const st = (flip++ % 2 === 0) ? 'AUTO_CANCELED' : 'CANCELED';
    const sentAt = Date.now();
    await db.doc(`applications/${CANARY}`).update({status: st});
    let latency = -1;
    while (Date.now() - sentAt < 120000) {
      const s = await storedTotals();
      if ((s.statsAt ?? 0) > before) { latency = Date.now() - sentAt; break; }
      await sleep(150);
    }
    samples.push(latency);
    if (latency >= 0 && latency <= targetMs) {
      return {drainedMs: Date.now() - t0, latency, samples};
    }
    if (Date.now() - t0 > maxMs) {
      return {drainedMs: -1, latency, samples};
    }
  }
}

async function awaitTotals({maxMs = 120000} = {}) {
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
  observe('R9-0 규모',
    `슬롯 ${SLOTS.length} · 대상 ${TARGETS_PENDING.length + TARGETS_SEATED.length} · ` +
    `ballast ${BALLAST} · 스캔 페이지 ≈ ${Math.ceil((BALLAST + 8) / 499)}`);

  // 기준선
  const warm0 = Date.now();
  const warm = await call('callableRecalculateTOStats', {toId: TO}, otok);
  observe('R9-0 기준 재집계', `${warm.status} ${Date.now() - warm0}ms`);
  let m = await awaitTotals();
  check('R9-0 기준선 일치', m.matched, true,
    `기대=${JSON.stringify(m.e)} 저장=${JSON.stringify(m.s)}`);

  // ── 트리거 큐를 비운다 — B 가 창 안에서 실행될 수 있는 상태를 만든다 ────
  const drain = await drainTriggers();
  observe('R9-0 트리거 큐 배수',
    `${drain.drainedMs}ms 걸려 지연 ${drain.latency}ms 까지 내려왔다`,
    `표본=${JSON.stringify(drain.samples)}`);
  check('R9-0 트리거 왕복이 창보다 짧다', drain.latency >= 0 && drain.latency <= 1500,
    true, `지연 ${drain.latency}ms — 이보다 느리면 B 가 창 안에서 못 쓴다`);

  // ── 보정: A 의 "호출 → TO 커밋" 까지 걸리는 시간을 실측한다 ──────────────
  //   내용이 같은 update 는 새 revision 을 남기지 않을 수 있으므로,
  //   A 가 반드시 **다른 값**을 쓰도록 저장된 파생값을 일부러 틀리게 둔다.
  //   (원장은 건드리지 않는다. A 가 바로 되돌린다.)
  await db.doc(`tos/${TO}`).update({totalPending: 999});
  const calBefore = (await storedTotals()).docCommitMs ?? 0;
  const cal = watchTO();
  const calT0 = Date.now();
  const calRes = await call('callableRecalculateTOStats', {toId: TO}, otok);
  const calTotal = Date.now() - calT0;
  await sleep(1500);
  cal.unsub();
  const firstNew = cal.revs.find((r) => r.commitMs > calBefore && r.p !== 999);
  const calWrite = firstNew ? firstNew.atMs - calT0 : -1;
  observe('R9-1 A 의 읽기→쓰기 구간 실측',
    `호출→TO커밋 ${calWrite}ms · 응답 ${calTotal}ms · ${calRes.status}`,
    'TO 커밋 이후가 슬롯 transaction 구간이다. ' +
    `커밋열=${JSON.stringify(cal.revs.map((r) => ({t: r.atMs - calT0, p: r.p})))}`);
  // 이 보정값은 **시도 지점을 고르는 참고**일 뿐이다. 판정 근거가 아니다.
  //   큐에 남은 트리거가 같은 순간 TO 를 쓰면 여기 잡힌 커밋이 A 의 것이
  //   아닐 수 있다(1차 측정에서 실제로 그랬다). 순서 성립 여부는 시도마다
  //   **사후에** 기록으로 검증한다(aUsedStaleSnapshot · triggerWrote · sawFresh).
  observe('R9-1 보정값의 한계',
    `창 추정 ${calWrite}ms · 트리거 지연 ${drain.latency}ms · A 응답 ${calTotal}ms`,
    '시도 지점 선택에만 쓴다');
  await awaitTotals();

  // ── R9-2 요청된 순서: A 가 먼저 읽고, B 가 최신값을 쓰고, A 가 마지막에 쓴다 ──
  const attempts = [];
  let reproduced = null;
  let orderingMadeCount = 0;
  for (let k = 0; k < TARGETS_PENDING.length && !reproduced; k++) {
    // A 는 첫 페이지를 수십 ms 안에 읽는다(공고 1건 + 슬롯 1질의 뒤).
    //   그 뒤~쓰기 전 사이에 B 를 넣는다. 지점은 사다리로 바꿔 시도하고,
    //   성립 여부는 사후 기록으로 판정한다.
    const at = [140, 240, 360, 520, 700, 900][k];
    const w = watchTO();
    const beforeLedger = await expectedTotals();
    const statsAtBefore = (await storedTotals()).statsAt;
    const skipsBefore = skipCount();

    const t0 = Date.now();
    const aP = call('callableRecalculateTOStats', {toId: TO}, otok);
    await sleep(at);
    // 원장만 바꾼다 — 트리거가 깨어난다. 파생값은 건드리지 않는다.
    await db.doc(`applications/${TGT(TARGETS_PENDING[k])}`).update({
      status: 'CANCELED', canceledAt: admin.firestore.FieldValue.serverTimestamp()});
    const cancelAt = Date.now() - t0;
    const afterLedger = await expectedTotals();

    const a = await aP;
    const quietMs = await quiesce(w.revs);
    w.unsub();

    const stored = await storedTotals();
    const ledger = await expectedTotals();
    const revs = w.revs.map((r) => ({
      t: r.atMs - t0, src: r.src, commit: r.commitIso, p: r.p, c: r.c,
      statsAt: r.statsAt}));
    // A 가 **자기 스냅샷으로 계산한 값** — 응답에 그대로 들어 있다.
    const aResult = a.body?.result
      ? {p: a.body.result.totalPending, c: a.body.result.totalConfirmed}
      : null;

    // 순서 판정 — 추론이 아니라 기록이다.
    //   · A 가 취소 **전** 원장으로 계산했는가 (응답값 == 취소 전 원장)
    //   · B(트리거)가 최신값을 커밋했는가 (statsUpdatedAt 전진 — 트리거 전용 필드)
    //   · A 의 쓰기가 B **뒤에** 왔는가
    //       수정 전: A 의 낡은 커밋이 B 의 커밋보다 나중에 보인다
    //       수정 후: A 의 쓰기가 사라진다 → CF skip 로그로 확인한다
    const ledgerChanged = beforeLedger.pending !== afterLedger.pending ||
      beforeLedger.seated !== afterLedger.seated;
    const freshRev = w.revs.find((r) =>
      r.p === afterLedger.pending && r.c === afterLedger.seated &&
      r.statsAt && r.statsAt > (statsAtBefore ?? 0));
    const sawFresh = !!freshRev;
    const triggerWrote = w.revs.some((r) => r.statsAt && r.statsAt > (statsAtBefore ?? 0));
    const aUsedStaleSnapshot = !!aResult && ledgerChanged &&
      aResult.p === beforeLedger.pending && aResult.c === beforeLedger.seated;
    // B 뒤에 온, 취소 전 값의 커밋 = A 의 낡은 쓰기.
    const staleAfterFresh = !!freshRev && w.revs.some((r) =>
      r.atMs > freshRev.atMs &&
      r.p === beforeLedger.pending && r.c === beforeLedger.seated);
    const skipsAfter = skipCount();
    const skipDelta = (skipsBefore == null || skipsAfter == null)
      ? null : skipsAfter - skipsBefore;
    const lastIsStale = ledgerChanged &&
      stored.pending === beforeLedger.pending && stored.seated === beforeLedger.seated;

    // 이 시도가 **요청된 순서를 실제로 만들었는가.**
    //   A 가 취소 전 스냅샷으로 계산했고, B 가 최신값을 먼저 커밋했고,
    //   그 뒤에 A 가 쓰려 했어야 한다. 하나라도 아니면 순서를 만들지 못한
    //   것이고, 그건 PASS 도 FAIL 도 아니다(INCONCLUSIVE).
    const aWroteAfterFresh = staleAfterFresh || (skipDelta != null && skipDelta > 0);
    const orderingMade = aUsedStaleSnapshot && sawFresh && aWroteAfterFresh;
    if (orderingMade) orderingMadeCount++;

    const rec = {
      k, cancelAtMs: cancelAt, aStatus: a.status, aResult,
      before: beforeLedger, after: afterLedger,
      stored, ledger, orderingMade, sawFresh, triggerWrote,
      aUsedStaleSnapshot, staleAfterFresh, skipDelta, lastIsStale, quietMs, revs,
      listenerErrors: w.errs.slice(0, 3),
    };
    attempts.push(rec);
    observe(`R9-2.${k} 시도`,
      `취소 +${cancelAt}ms · A계산=${JSON.stringify(aResult)}(낡음=${aUsedStaleSnapshot}) · ` +
      `B먼저최신커밋=${sawFresh} · A가그뒤에씀=${staleAfterFresh}/skip=${skipDelta} · ` +
      `순서성립=${orderingMade} · 마지막이낡음=${lastIsStale} · ` +
      `원장=${JSON.stringify(ledger)} 저장=${JSON.stringify(stored)}`,
      `커밋열=${JSON.stringify(revs)}`);

    if (orderingMade &&
        (stored.pending !== ledger.pending || stored.seated !== ledger.seated)) {
      reproduced = rec;
      break;
    }
    // 다음 시도 전 정합 회복 + 큐 재배수(취소 이벤트가 큐에 남을 수 있다).
    const back = await awaitTotals({maxMs: 90000});
    if (!back.matched) {
      observe(`R9-2.${k} 다음 시도 전 정합 회복 실패`,
        `기대=${JSON.stringify(back.e)} 저장=${JSON.stringify(back.s)}`,
        '순서 성립 여부와 무관하게 낡은 값이 남아 있다 = 결함 후보');
      reproduced = rec;
      break;
    }
    // 순서를 세 번 만들고도 낡은 값이 남지 않으면 그것으로 충분하다.
    if (orderingMadeCount >= 3) break;
    await drainTriggers({targetMs: 1500, maxMs: 120000});
  }

  if (reproduced) {
    // 후속 도메인 이벤트 없이 낡은 값이 남는가 — 자가 복구 여부.
    await sleep(8000);
    const e = await expectedTotals(); const s = await storedTotals();
    check('R9-2 낡은 스냅샷이 마지막에 커밋되지 않는다',
      {pending: s.pending, seated: s.seated},
      {pending: e.pending, seated: e.seated},
      `재현됨 — 원장=${JSON.stringify(e)} 저장=${JSON.stringify(s)} ` +
      `(취소 +${reproduced.cancelAtMs}ms, A계산=${JSON.stringify(reproduced.aResult)}, ` +
      `커밋열=${JSON.stringify(reproduced.revs)})`);

    // ── 대조: 트리거 자체는 정상인가 ──────────────────────────────────────
    //   새 원장 이벤트가 오면 낫는다면, 이것은 "트리거 고장"이 아니라
    //   **저장 순서** 문제다. 대기 인원이 변하지 않는 전이를 쓴다.
    //   CONFIRMED → CONTRACT_PENDING 은 좌석 수가 그대로다(둘 다 SEATED).
    await db.doc(`applications/${TGT(TARGETS_SEATED[0])}`).update({
      status: 'CONTRACT_PENDING'});
    const healed = await awaitTotals({maxMs: 60000});
    check('R9-3 새 원장 이벤트가 오면 트리거가 정정한다', healed.matched, true,
      `기대=${JSON.stringify(healed.e)} 저장=${JSON.stringify(healed.s)} ` +
      `${healed.elapsedMs}ms — 트리거 고장이 아니라 저장 순서 문제라는 대조`);
  } else if (orderingMadeCount > 0) {
    // 순서는 만들었는데 낡은 값이 남지 않았다 → 그 순서에서는 보호가 작동했다.
    check('R9-2 요청된 순서에서 낡은 값이 남지 않았다', true, true,
      `순서 성립 ${orderingMadeCount}/${attempts.length}회. ` +
      '보호 장치를 코드로 지목해야 종료 근거가 된다.');
  } else {
    observe('R9-2 결과', 'INCONCLUSIVE — 요청된 순서를 만들지 못했다',
      `시도 ${attempts.length}회, 순서 성립 0회. PASS 로 세지 않는다.`);
  }

  console.log(JSON.stringify({
    run: RUN, ballast: BALLAST, failures,
    results, attempts,
  }, null, 2));

  await cleanup();
  process.exit(failures > 0 ? 1 : 0);
})().catch(async (e) => {
  console.error('FATAL', e);
  try { await cleanup(); } catch {}
  process.exit(2);
});
