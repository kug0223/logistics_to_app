/**
 * R10 O01 계약 B — delta + absolute + trigger 의 **최종 수렴**.
 *
 *   9차는 이렇게 적었다: "delta 가 절대 쓰기에 지워져도 원장 변경이 트리거를
 *   깨우고 그 트리거의 읽기가 더 최신이라 결국 이긴다."
 *   그 문장은 **트리거가 깨어나는 경로에만** 참이다. 제품 코드 자신이
 *   반례를 적어 두고 있다 — `callableReleaseNoshowSeat` 안:
 *
 *     "syncTOStats가 발동하지 않으므로 FULL→ACTIVE 전환 명시적 처리"
 *
 *   좌석 반납은 `staffingReleasedAt` 만 쓰고 status 를 바꾸지 않는다.
 *   트리거는 `beforeStatus === afterStatus` 면 즉시 return 한다(index.ts:17380).
 *   즉 **원장은 바뀌었는데 canonical 재계산이 돌지 않는** 경로다.
 *
 *   여기서 두 가지를 실측한다.
 *
 *   D1 (술어 불일치) — 재집계의 TO 합계는 `CONFIRMED_STATUSES` 만 세고
 *       `staffingReleasedAt` 을 보지 않는다(index.ts:24539). 트리거는
 *       `srvOccupiesSeatToday` + 반납 표식을 본다(countCommittedSeats).
 *       같은 원장에서 두 절대 writer 가 **다른 값**을 만든다.
 *       순서와 무관하게 재집계가 쓰면 그 값이 남는다(fence 가 최신 stamp 를 준다).
 *
 *   D2 (복구 이벤트 없음) — 반납 delta 를 낡은 절대 쓰기가 덮으면
 *       후속 트리거가 없어 스스로 낫지 않는다.
 *
 *   대조군으로 **트리거가 깨어나는 실제 경로**(취소 2단계: 원장 update +
 *   `callableIncrementSlotPending`)도 같은 창에서 돌려 수렴을 확인한다.
 *
 *   판정은 원장에서 독립 산출한 기대값과의 일치다. 기대값은 제품과 같은
 *   술어를 쓴다(반납 표식 + 장기 종료일). 판정을 먼저 기록한 뒤에만
 *   다음 사례를 위한 기준선 복구를 한다 — 치유로 PASS 를 만들지 않는다.
 *
 * 격리 에뮬레이터(demo-alfit-r7) 전용.
 * ⚠ ballast 를 쓰므로 같은 세션의 다른 하네스보다 **뒤에** 두거나 에뮬레이터를
 *   다시 띄운다(트리거 큐 적체가 다음 하네스를 늦춘다).
 */
const PROJECT = 'demo-alfit-r7';
process.env.GCLOUD_PROJECT = PROJECT;
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:6070';
process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:6072';

const path = require('path');
const fsp = require('fs');
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
        'X-Firebase-AppCheck': 'r10-audit-emulator-token'},
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

const EMU_LOG = process.env.R10_EMU_LOG || '';
function logCount(re) {
  if (!EMU_LOG) return null;
  try {
    return (fsp.readFileSync(EMU_LOG, 'latin1').match(re) || []).length;
  } catch { return null; }
}
/** fence 가 낡은 쓰기를 건너뛴 횟수 — skip 경로에서만 찍는 태그. */
const skipCount = () => logCount(/\[srvCommitToTotals\]/g);
/**
 * canonical 재계산(트리거)이 **실행된** 횟수.
 *   `statsUpdatedAt` 전진으로 세면 큐에 남은 다른 이벤트에 오염된다
 *   (1차 측정에서 실제로 그랬다). 실행 자체를 센다.
 */
const triggerRuns = () =>
  logCount(/Beginning execution of "asia-northeast3-syncTOStats"/g);
/**
 * 그중 **실제로 집계를 돌린** 횟수.
 *   조기 return 은 수 ms 로 끝난다(문서를 읽지 않는다). 전체 재계산은
 *   원장 스캔이 있어 수십~수백 ms 다. 그래서 소요 시간으로 가른다.
 */
function triggerFullRuns() {
  if (!EMU_LOG) return null;
  try {
    const s = fsp.readFileSync(EMU_LOG, 'latin1');
    const re = /Finished "asia-northeast3-syncTOStats" in ([0-9.]+)ms/g;
    let m; let n = 0;
    while ((m = re.exec(s)) !== null) { if (Number(m[1]) >= 50) n++; }
    return n;
  } catch { return null; }
}

const RUN = `r10${Date.now().toString(36)}`;
const BIZ = `${RUN}biz`, TO = `${RUN}to`, WD = `${RUN}wd`, OWNER = `${RUN}own`;
const SLOT = `${RUN}slot`;
const BALLAST = Number(process.env.R10_BALLAST || 4000);
const CANARY = `${RUN}_a_canary`;
const APP = (n) => `${RUN}_a_${n}`;

const wd = () => ({wdId: WD, workType: '홀서빙', startTime: '09:00', endTime: '18:00',
  wage: 12000, wageType: 'hourly', requiredCount: 40});

/** 제품 술어와 같은 식 — 반납 표식 + 장기 종료일(여기 fixture 는 전부 단기). */
function seatsOf(d) {
  if (!SEATED.includes(d.status)) return false;
  if (d.staffingReleasedAt != null) return false;
  return d.type !== 'long_term';
}

async function seed() {
  // 반납 CF 는 **당일 근무**만 허용한다 — workDate 를 오늘로 둔다.
  const workDate = kstDayStart(Date.now());
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
  await db.doc(`tos/${TO}/slots/${SLOT}`).set({id: SLOT, toId: TO, businessId: BIZ,
    status: 'open', isManualClosed: false,
    date: admin.firestore.Timestamp.fromMillis(workDate),
    workDetails: [wd()],
    workDetailCounts: {[WD]: {confirmedCount: 0, pendingCount: 0}},
    requiredCount: 40, confirmedCount: 0, pendingCount: 0});

  const mkApp = (uid, status) => {
    const d = {uid, toId: TO, slotId: SLOT, businessId: BIZ, wdId: WD,
      type: 'short_term', selectedWorkType: '홀서빙',
      startTime: '09:00', endTime: '18:00',
      workDate: admin.firestore.Timestamp.fromMillis(workDate),
      createdAt: admin.firestore.Timestamp.now()};
    if (status) d.status = status;
    return d;
  };

  // ballast — status 필드 없음(제품 트리거가 스스로 건너뛴다).
  let batch = db.batch(); let n = 0;
  for (let i = 0; i < BALLAST; i++) {
    batch.set(db.doc(`applications/${RUN}_z_${String(i).padStart(6, '0')}`),
      mkApp(`${RUN}zu${i}`, null));
    if (++n >= 450) { await batch.commit(); batch = db.batch(); n = 0; }
  }
  if (n > 0) await batch.commit();

  await db.doc(`applications/${CANARY}`).set(mkApp(`${RUN}cu`, 'CANCELED'));
  for (const t of ['c1', 'c2']) {
    await db.doc(`applications/${APP(t)}`).set(mkApp(`${RUN}u${t}`, 'CONFIRMED'));
    // 반납 CF 는 NO_SHOW 근태 기록을 요구한다.
    await db.doc(`attendance/${RUN}att${t}`).set({
      applicationId: APP(t), uid: `${RUN}u${t}`, businessId: BIZ, toId: TO,
      status: 'NO_SHOW',
      workDate: admin.firestore.Timestamp.fromMillis(workDate)});
  }
  for (const t of ['p1', 'p2', 'p3']) {
    await db.doc(`applications/${APP(t)}`).set(mkApp(`${RUN}u${t}`, 'PENDING'));
  }
  // delta command(`callableIncrementSlotPending`)는 **본인만** 부를 수 있다
  //   (`appData.uid !== callerUid` → permission-denied). 그 경로를 실제로
  //   돌리려면 지원자 계정이 필요하다.
  try { await admin.auth().createUser({uid: `${RUN}up1`}); } catch (e) {
    if (e.code !== 'auth/uid-already-exists') throw e;
  }
  await db.doc(`users/${RUN}up1`).set({uid: `${RUN}up1`, name: 'T 근로자',
    role: 'USER', accountStatus: 'active'});
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
  const att = await db.collection('attendance').where('toId', '==', TO).get();
  for (const d of att.docs) await d.ref.delete().catch(() => {});
  const slots = await db.collection(`tos/${TO}/slots`).get();
  for (const d of slots.docs) await d.ref.delete().catch(() => {});
  await db.doc(`tos/${TO}`).delete().catch(() => {});
  await db.doc(`businesses/${BIZ}`).delete().catch(() => {});
  await sleep(1800);
  await db.doc(`users/${OWNER}`).delete().catch(() => {});
}

/** 원장에서 독립 산출 — 제품과 같은 술어. */
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
      const v = d.data();
      if (PENDING.includes(v.status)) pending++;
      if (seatsOf(v)) seated++;
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
    statsAt: t.statsUpdatedAt?.toMillis?.() ?? null,
    fenceAt: t.statsSourceReadAt?.toMillis?.() ?? null};
}
function watchTO() {
  const revs = [];
  const push = (src, snap) => {
    if (!snap.exists) return;
    const d = snap.data();
    const commitMs = snap.updateTime.toMillis();
    if (revs.some((r) => r.commitMs === commitMs)) return;
    revs.push({src, commitMs, p: d.totalPending ?? null, c: d.totalConfirmed ?? null,
      statsAt: d.statsUpdatedAt?.toMillis?.() ?? null, atMs: Date.now()});
  };
  const unsubL = db.doc(`tos/${TO}`).onSnapshot((s) => push('listen', s), () => {});
  let stop = false;
  (async () => {
    while (!stop) {
      try { push('poll', await db.doc(`tos/${TO}`).get()); } catch {}
      await sleep(100);
    }
  })();
  return {revs, unsub: () => { stop = true; unsubL(); }};
}
async function quiesce(revs, {quietMs = 5000, minMs = 9000, maxMs = 120000} = {}) {
  const t0 = Date.now();
  for (;;) {
    const last = revs.length ? revs[revs.length - 1].atMs : t0;
    if (Date.now() - last > quietMs && Date.now() - t0 > minMs) return Date.now() - t0;
    if (Date.now() - t0 > maxMs) return -1;
    await sleep(250);
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
/** 트리거 큐가 비었는지 제품 트리거로 잰다(환경 오염 방지 전용). */
async function drainTriggers({targetMs = 1500, maxMs = 600000} = {}) {
  const t0 = Date.now(); const samples = [];
  for (;;) {
    const before = (await storedTotals()).statsAt ?? 0;
    // **현재 값과 다른 값**을 써야 한다. 같은 값으로 update 하면 새 revision 이
    //   생기지 않아 트리거 이벤트가 나지 않고, 기다리다 timeout 을 태운다
    //   (처음엔 고정 순서로 번갈아 써서 첫 시도가 자주 no-op 이 됐다).
    const cur = (await db.doc(`applications/${CANARY}`).get()).get('status');
    const st = (cur === 'CANCELED') ? 'AUTO_CANCELED' : 'CANCELED';
    const sentAt = Date.now();
    await db.doc(`applications/${CANARY}`).update({status: st});
    let latency = -1;
    while (Date.now() - sentAt < 120000) {
      if (((await storedTotals()).statsAt ?? 0) > before) { latency = Date.now() - sentAt; break; }
      await sleep(150);
    }
    samples.push(latency);
    if (latency >= 0 && latency <= targetMs) return {drainedMs: Date.now() - t0, latency, samples};
    if (Date.now() - t0 > maxMs) return {drainedMs: -1, latency, samples};
  }
}

(async () => {
  await seed();
  const otok = await idToken(OWNER);
  const wtok = await idToken(`${RUN}up1`);
  observe('R10-0 규모', `ballast ${BALLAST} · 확정 2 · 대기 3 · 스캔 페이지 ≈ ${Math.ceil((BALLAST + 6) / 499)}`);

  const warm = await call('callableRecalculateTOStats', {toId: TO}, otok);
  observe('R10-0 기준 재집계', `${warm.status}`);
  let m = await awaitTotals();
  check('R10-0 기준선 일치', m.matched, true,
    `기대=${JSON.stringify(m.e)} 저장=${JSON.stringify(m.s)}`);
  const drain = await drainTriggers();
  observe('R10-0 트리거 큐 배수', `${drain.drainedMs}ms → 지연 ${drain.latency}ms`);

  // ── D2 전제: 좌석 반납이 canonical 재계산을 깨우는가 ──────────────────
  {
    // 큐 잔여 이벤트가 섞이지 않도록 먼저 완전히 멎게 둔다.
    { const w0 = watchTO(); await quiesce(w0.revs, {quietMs: 5000, minMs: 6000}); w0.unsub(); }
    const before = await storedTotals();
    const runsBefore = triggerRuns();
    const fullBefore = triggerFullRuns();
    const w = watchTO();
    const rel = await call('callableReleaseNoshowSeat', {applicationId: APP('c1')}, otok);
    await quiesce(w.revs, {minMs: 9000});
    w.unsub();
    const after = await storedTotals();
    const led = await expectedTotals();
    const runsDelta = (runsBefore == null) ? null : triggerRuns() - runsBefore;
    const fullDelta = (fullBefore == null) ? null : triggerFullRuns() - fullBefore;
    observe('R10-1 좌석 반납 응답', `${rel.status} ${JSON.stringify(rel.body?.result ?? rel.body)}`.slice(0, 120));
    check('R10-1 반납 delta 자체는 원장과 맞는다',
      {pending: after.pending, seated: after.seated},
      {pending: led.pending, seated: led.seated},
      `기대=${JSON.stringify(led)} 저장=${JSON.stringify(after)}`);
    check('R10-1 반납이 canonical 재계산을 깨운다', (fullDelta ?? 0) >= 1, true,
      `전체 재계산(≥50ms) ${fullDelta}회 · 조기 return 포함 실행 ${runsDelta}회. ` +
      '0이면 status 만 보는 가드에 걸려 재계산이 돌지 않은 것이다');
    observe('R10-1 반납 관측값',
      `syncTOStats 실행 ${runsDelta}회 · 전체 재계산 ${fullDelta}회 · statsUpdatedAt 전진=` +
      `${(after.statsAt ?? 0) > (before.statsAt ?? 0)} · fence 전진=` +
      `${(after.fenceAt ?? 0) > (before.fenceAt ?? 0)}`,
      '0회면 status 만 보는 가드에 걸려 재계산이 돌지 않은 것이다. ' +
      'statsUpdatedAt 전진만으로 판정하지 않는다 — 큐에 남은 다른 이벤트에 오염된다');
  }

  // ── D1: 경합 없이 재집계만 돌려도 같은 값이 나오는가 ──────────────────
  {
    const led = await expectedTotals();
    const r = await call('callableRecalculateTOStats', {toId: TO}, otok);
    await sleep(2500);
    const s = await storedTotals();
    check('R10-2 재집계가 트리거와 같은 좌석 술어를 쓴다',
      {pending: s.pending, seated: s.seated},
      {pending: led.pending, seated: led.seated},
      `경합 없음. 응답=${JSON.stringify(r.body?.result ?? r.body).slice(0, 90)} ` +
      `기대=${JSON.stringify(led)} 저장=${JSON.stringify(s)} ` +
      '(불일치면 절대 writer 두 개가 같은 원장에서 다른 값을 만든다)');
  }

  // 판정을 기록한 뒤에만 기준선을 되돌린다 — 치유로 PASS 를 만들지 않는다.
  await drainTriggers({targetMs: 1500, maxMs: 120000});
  const rebase = await awaitTotals({maxMs: 60000});
  observe('R10-2 이후 기준선 복구', `${rebase.matched} 저장=${JSON.stringify(rebase.s)}`);

  // ── B 대조군: 트리거가 깨어나는 실제 경로(취소 2단계) ─────────────────
  {
    const w = watchTO();
    const before = await expectedTotals();
    const skipsBefore = skipCount();
    const t0 = Date.now();
    const aP = call('callableRecalculateTOStats', {toId: TO}, otok);
    await sleep(200);
    // 실제 클라이언트 취소 경로: 원장 update → 권위 command(delta -1).
    //   delta command 는 **본인 토큰**으로만 통한다.
    await db.doc(`applications/${APP('p1')}`).update({
      status: 'CANCELED', canceledAt: admin.firestore.FieldValue.serverTimestamp()});
    const inc = await call('callableIncrementSlotPending',
      {applicationId: APP('p1'), toId: TO, slotId: SLOT, delta: -1}, wtok);
    const a = await aP;
    const q = await quiesce(w.revs);
    w.unsub();
    const led = await expectedTotals(); const s = await storedTotals();
    const skipDelta = (skipsBefore == null) ? null : skipCount() - skipsBefore;
    check('R10-3 트리거가 깨는 경로 — delta+absolute 겹쳐도 최종 수렴',
      {pending: s.pending, seated: s.seated},
      {pending: led.pending, seated: led.seated},
      `A=${a.status} A계산=${JSON.stringify(a.body?.result ?? {}).slice(0, 60)} ` +
      `delta=${inc.status} skip=${skipDelta} 정지=${q}ms ` +
      `이전원장=${JSON.stringify(before)} 기대=${JSON.stringify(led)} 저장=${JSON.stringify(s)} ` +
      `커밋열=${JSON.stringify(w.revs.map((r) => ({t: r.atMs - t0, p: r.p, c: r.c})))}`);
  }

  await drainTriggers({targetMs: 1500, maxMs: 120000});
  await awaitTotals({maxMs: 60000});

  // ── B 본체: 트리거가 깨지 않는 경로(좌석 반납) + 낡은 절대 쓰기 ────────
  {
    const w = watchTO();
    const before = await expectedTotals();
    const skipsBefore = skipCount();
    const t0 = Date.now();
    const aP = call('callableRecalculateTOStats', {toId: TO}, otok);
    await sleep(200);
    const rel = await call('callableReleaseNoshowSeat', {applicationId: APP('c2')}, otok);
    const a = await aP;
    const q = await quiesce(w.revs);
    w.unsub();
    const led = await expectedTotals(); const s = await storedTotals();
    const skipDelta = (skipsBefore == null) ? null : skipCount() - skipsBefore;
    check('R10-4 트리거가 깨지 않는 경로 — 추가 행동 없이 최종 수렴',
      {pending: s.pending, seated: s.seated},
      {pending: led.pending, seated: led.seated},
      `A=${a.status} A계산=${JSON.stringify(a.body?.result ?? {}).slice(0, 60)} ` +
      `반납=${rel.status} skip=${skipDelta} 정지=${q}ms ` +
      `이전원장=${JSON.stringify(before)} 기대=${JSON.stringify(led)} 저장=${JSON.stringify(s)} ` +
      `커밋열=${JSON.stringify(w.revs.map((r) => ({t: r.atMs - t0, p: r.p, c: r.c})))}`);
  }

  console.log(JSON.stringify({run: RUN, ballast: BALLAST, failures, results}, null, 2));
  await cleanup();
  process.exit(failures > 0 ? 1 : 0);
})().catch(async (e) => {
  console.error('FATAL', e);
  try { await cleanup(); } catch {}
  process.exit(2);
});
