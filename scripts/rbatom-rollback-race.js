/**
 * [ROLLBACK-ATOMICITY §7] 롤백과 계약 발행의 **경쟁** — 에뮬레이터 실측.
 *
 *   묻는 것은 하나다.
 *
 *     "이 지원서에 계약이 없다"를 **원자적으로** 고정할 수 있는가?
 *
 *   세 모델을 같은 경쟁 순서에 넣고 결과를 비교한다.
 *
 *     M1 현재 클라이언트  — 원장 조회 → (B 커밋) → precondition 없는 쓰기
 *                           + 확정 계열이면 계약 void
 *     M2 지원서만 트랜잭션 — tx.get(appRef) → (B 커밋) → tx.update(appRef)
 *                           (클라이언트 SDK 가 할 수 있는 최대치. 쿼리 불가)
 *     M3 서버 조건부       — tx.get(appRef) + **srvIssuedContractExists(tx)**
 *                           → (B 커밋) → tx.update(appRef)
 *
 *   판정식은 복제하지 않는다. `functions/lib/index.js` 에서
 *   `srvIssuedContractExists` · `srvContractNotIssuedYet` 를 **그대로 떼어** 쓴다.
 *   계약 발행 쪽도 제품 트랜잭션과 같은 모양(계약 doc get → 중복 질의 → set)이다.
 *
 *   경쟁 A: 롤백 읽기 → 발행 커밋 → 롤백 쓰기
 *   경쟁 B: 롤백 커밋 → 발행 시도
 *
 *   격리: demo 프로젝트 Firestore 에뮬레이터(127.0.0.1:6060). 공유 DEV 쓰기 0.
 */
'use strict';

const PROJECT = 'demo-rbatom';
process.env.GCLOUD_PROJECT = PROJECT;
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:6060';

const fs = require('fs');
const path = require('path');
const admin = require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin'));

admin.initializeApp({projectId: PROJECT});
const db = admin.firestore();

// ── production 슬라이스 ────────────────────────────────────────────────
const LIB = fs.readFileSync(
    path.join(__dirname, '..', 'functions', 'lib', 'index.js'), 'utf8');

/** 최상위 `function NAME(` 한 덩어리. */
function sliceFn(name) {
  const re = new RegExp(`^(?:async )?function ${name}\\(`, 'm');
  const m = re.exec(LIB);
  if (!m) throw new Error(`function ${name} 없음`);
  const from = m.index;
  const rest = LIB.slice(from);
  const end = /^\}/m.exec(rest.slice(1));
  return rest.slice(0, end ? end.index + 2 : rest.length);
}

const build = new Function('db', 'admin',
    sliceFn('srvContractNotIssuedYet') +
    sliceFn('srvIssuedContractExists') +
    'return {srvContractNotIssuedYet, srvIssuedContractExists};');
const {srvContractNotIssuedYet, srvIssuedContractExists} = build(db, admin);

// 슬라이스가 실제로 제품 판정식인지 먼저 확인한다.
const PRED = [
  [undefined, true], ['voided', true], ['pending_employer', true],
  ['draft', true], ['pending_worker', false], ['completed', false],
  ['active', false],
];

// ── 판정 수집 ──────────────────────────────────────────────────────────
const results = [];
let failures = 0;
function check(label, actual, expected, note) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) failures++;
  results.push({label, ok, actual, expected, ...(note ? {note} : {})});
}
/**
 * 사실만 기록한다 — PASS/FAIL 로 말할 **자격이 없는** 관측.
 *
 *   이 에뮬레이터가 트랜잭션 충돌을 감지하지 않는다는 것이 RA-X0 에서
 *   드러났다(아래). 그러면 "트랜잭션이 보호해 주는가"를 묻는 셀의 결과는
 *   설계의 성질이 아니라 **환경의 성질**이다. 그걸 FAIL 로 적으면 설계가
 *   틀렸다고 말하는 것이 되고, PASS 로 적으면 안전하다고 말하는 것이 된다.
 *   둘 다 거짓이다.
 */
const observe = (label, actual, note) =>
  results.push({label, ok: null, actual, expected: '관측(판정 보류)',
    ...(note ? {note} : {})});

const BIZ = 'biz_rbatom';
const WORKER = 'worker_rbatom';
let caseNo = 0;

/** 사례마다 새 지원서 — 상태가 섞이지 않게 한다. */
async function freshApp(status) {
  caseNo++;
  const appId = `app_${String(caseNo).padStart(2, '0')}`;
  await db.collection('applications').doc(appId).set({
    uid: WORKER, businessId: BIZ, toId: 'to_rbatom', slotId: 'slot_1',
    workDetailId: 'wd_1', status,
    startTime: '10:00', endTime: '11:00', wage: 53000, wageType: 'daily',
  });
  return appId;
}

/** 계약 발행 — 제품 트랜잭션과 같은 모양. */
async function issueContract(appId, contractId) {
  await db.runTransaction(async (tx) => {
    const ref = db.collection('employment_contracts').doc(contractId);
    const snap = await tx.get(ref);
    if (snap.exists) throw new Error('already-exists');
    if (await srvIssuedContractExists(appId, BIZ, tx)) {
      throw new Error('already-exists');
    }
    tx.set(ref, {
      businessId: BIZ, workerId: WORKER, applicationId: appId,
      status: 'pending_worker', isLongTerm: false,
      slots: [{applicationId: appId, workDate: '2026-10-20',
        startTime: '10:00', endTime: '11:00', wage: 53000, wageType: 'daily'}],
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
}

/** 계약 void — `callableVoidApplicationContracts` 의 대상 집합 그대로. */
const VOID_TARGET = new Set(['pending_employer', 'pending_worker', 'draft']);
async function voidContractsFor(appId) {
  const q1 = await db.collection('employment_contracts')
      .where('businessId', '==', BIZ).where('applicationId', '==', appId).get();
  const voided = [];
  for (const d of q1.docs) {
    if (VOID_TARGET.has(d.data().status)) {
      await d.ref.update({status: 'voided'});
      voided.push(d.id);
    }
  }
  return voided;
}

// ── M1: 현재 클라이언트 경로 ───────────────────────────────────────────
//   원장 조회(쿼리) → [배리어] → precondition 없는 쓰기 → 확정 계열이면 void
async function m1Rollback(appId, barrier) {
  const q = await db.collection('employment_contracts')
      .where('businessId', '==', BIZ).where('applicationId', '==', appId).get();
  const issued = q.docs.some((d) => !srvContractNotIssuedYet(d.data().status));
  if (issued) return {result: 'already', wrote: false, voided: []};

  const snap = await db.collection('applications').doc(appId).get();
  const prev = snap.data().status;
  if (barrier) await barrier();

  await db.collection('applications').doc(appId).update({status: 'PENDING'});
  const voided = ['CONFIRMED', 'CONTRACT_PENDING'].includes(prev)
      ? await voidContractsFor(appId) : [];
  return {result: 'failed', wrote: true, voided};
}

// ── M2: 지원서 문서만 트랜잭션 ─────────────────────────────────────────
//   클라이언트 SDK 가 할 수 있는 최대치다. **쿼리를 트랜잭션에 넣을 수 없다.**
async function m2Rollback(appId, barrier) {
  const q = await db.collection('employment_contracts')
      .where('businessId', '==', BIZ).where('applicationId', '==', appId).get();
  const issued = q.docs.some((d) => !srvContractNotIssuedYet(d.data().status));
  if (issued) return {result: 'already', wrote: false, voided: []};

  let wrote = false;
  let fired = false;
  await db.runTransaction(async (tx) => {
    const ref = db.collection('applications').doc(appId);
    const snap = await tx.get(ref);
    if (!fired && barrier) { fired = true; await barrier(); }
    if (!['CONFIRMED', 'CONTRACT_PENDING'].includes(snap.data().status)) {
      return;
    }
    tx.update(ref, {status: 'PENDING'});
    wrote = true;
  });
  const voided = wrote ? await voidContractsFor(appId) : [];
  return {result: wrote ? 'failed' : 'rejected', wrote, voided};
}

// ── M3: 서버 조건부 롤백 (제안) ────────────────────────────────────────
//   **같은 트랜잭션 안에서** 제품 술어로 원장을 질의한다.
//   Admin SDK 트랜잭션은 쿼리를 읽을 수 있고, 그 범위에 잠금이 걸린다.
async function m3Rollback(appId, barrier) {
  let fired = false;
  let outcome = null;
  let attempts = 0;
  try {
    await db.runTransaction(async (tx) => {
      attempts++;
      const ref = db.collection('applications').doc(appId);
      const snap = await tx.get(ref);
      if (!snap.exists) { outcome = 'unknown'; return; }
      const st = snap.data().status;
      // 첫 시도에서만 B 를 끼워 넣는다 — 재시도는 최신 상태를 봐야 한다.
      if (!fired && barrier) { fired = true; await barrier(); }
      if (await srvIssuedContractExists(appId, BIZ, tx)) {
        outcome = 'already';
        return;
      }
      if (st === 'PENDING') { outcome = 'failed'; return; }
      if (!['CONFIRMED', 'CONTRACT_PENDING'].includes(st)) {
        outcome = 'rejected';
        return;
      }
      tx.update(ref, {status: 'PENDING'});
      outcome = 'rolledBack';
    });
  } catch (e) {
    outcome = `tx-error:${e.code ?? e.message}`;
  }
  const voided = outcome === 'rolledBack' ? await voidContractsFor(appId) : [];
  return {result: outcome, wrote: outcome === 'rolledBack', voided, attempts};
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ── M3-strict: 배리어를 **모든 읽기 뒤**로 옮긴다 ──────────────────────
//   M3 가 쉽게 통과한 이유는 배리어가 질의 **앞**이어서 질의가 B 의 커밋을
//   봤기 때문이다. 그것만으로 "안전하다"고 쓰면 과신이다.
//   여기서는 A 가 원장 질의까지 끝낸 **뒤**에 B 를 발사한다. 이제 질의는
//   B 를 볼 수 없다 — 안전성의 근거는 전적으로 **트랜잭션 잠금**이다.
//
//   [함정] B 를 await 하면 교착이다. A 는 잠금을 쥔 채 B 를 기다리고,
//   B 는 그 잠금을 기다린다. 그래서 발사만 하고 짧게 쉰 뒤 커밋으로 간다.
async function m3StrictRollback(appId, issueFn) {
  let fired = false;
  let bPromise = null;
  let outcome = null;
  let attempts = 0;
  try {
    await db.runTransaction(async (tx) => {
      attempts++;
      const ref = db.collection('applications').doc(appId);
      const snap = await tx.get(ref);
      const st = snap.exists ? snap.data().status : null;
      const issued = await srvIssuedContractExists(appId, BIZ, tx);
      if (!fired) {
        fired = true;
        bPromise = issueFn().then(() => 'ok').catch((e) => `err:${e.message}`);
        await sleep(400);
      }
      if (issued) { outcome = 'already'; return; }
      if (st === 'PENDING') { outcome = 'failed'; return; }
      if (!['CONFIRMED', 'CONTRACT_PENDING'].includes(st)) {
        outcome = 'rejected';
        return;
      }
      tx.update(ref, {status: 'PENDING'});
      outcome = 'rolledBack';
    });
  } catch (e) {
    outcome = `tx-error:${e.code ?? e.message}`;
  }
  const bResult = bPromise ? await bPromise : null;
  const voided = outcome === 'rolledBack' ? await voidContractsFor(appId) : [];
  return {result: outcome, wrote: outcome === 'rolledBack', voided, attempts,
    bResult};
}

// ── M4: 지원서에 **표식**을 남기는 발행 + 표식을 읽는 롤백 ─────────────
//   M3-strict 가 깨진 이유는 Firestore 가 **읽을 때 없던 문서**(phantom)를
//   충돌로 보지 않기 때문이다. 쿼리를 트랜잭션에 넣어도 삽입은 막지 못한다.
//   그래서 두 writer 가 **처음부터 존재하는 같은 문서**에서 경쟁하게 만든다.
//   그 문서는 지원서 하나뿐이다.
async function issueContractWithMark(appId, contractId) {
  await db.runTransaction(async (tx) => {
    const ref = db.collection('employment_contracts').doc(contractId);
    const appRef = db.collection('applications').doc(appId);
    // [핵심] 발행 쪽도 지원서를 **읽어야** 한다. blind write 는 충돌 감지에
    //   참여하지 않는다 — 제품 CF 는 지금 이 읽기를 트랜잭션 **밖**(PREAUTH)에서
    //   한다. 그것을 안으로 옮기는 것이 이 모델의 전부다.
    const appSnap = await tx.get(appRef);
    if (!appSnap.exists) throw new Error('not-found');
    if (!['CONFIRMED', 'CONTRACT_PENDING'].includes(appSnap.data().status)) {
      throw new Error('failed-precondition');
    }
    const snap = await tx.get(ref);
    if (snap.exists) throw new Error('already-exists');
    if (await srvIssuedContractExists(appId, BIZ, tx)) {
      throw new Error('already-exists');
    }
    tx.set(ref, {
      businessId: BIZ, workerId: WORKER, applicationId: appId,
      status: 'pending_worker', isLongTerm: false,
    });
    // 같은 트랜잭션에서 지원서에 표식 — 이것이 경쟁의 접점이다.
    tx.update(appRef, {
      contractIssuedAt: admin.firestore.FieldValue.serverTimestamp(),
      contractId,
    });
  });
}

/** 표식을 읽는 롤백. 쿼리 없음 — 문서 하나만 본다. */
async function m4Rollback(appId, issueFn) {
  let fired = false;
  let bPromise = null;
  let outcome = null;
  let attempts = 0;
  try {
    await db.runTransaction(async (tx) => {
      attempts++;
      const ref = db.collection('applications').doc(appId);
      const snap = await tx.get(ref);
      if (!snap.exists) { outcome = 'unknown'; return; }
      const d = snap.data();
      if (!fired && issueFn) {
        fired = true;
        bPromise = issueFn().then(() => 'ok').catch((e) => `err:${e.message}`);
        await sleep(400);
      }
      if (d.contractIssuedAt != null) { outcome = 'already'; return; }
      if (d.status === 'PENDING') { outcome = 'failed'; return; }
      if (!['CONFIRMED', 'CONTRACT_PENDING'].includes(d.status)) {
        outcome = 'rejected';
        return;
      }
      tx.update(ref, {status: 'PENDING'});
      outcome = 'rolledBack';
    });
  } catch (e) {
    outcome = `tx-error:${e.code ?? e.message}`;
  }
  const bResult = bPromise ? await bPromise : null;
  const voided = outcome === 'rolledBack' ? await voidContractsFor(appId) : [];
  return {result: outcome, wrote: outcome === 'rolledBack', voided, attempts,
    bResult};
}

const stateOf = async (appId, contractId) => ({
  app: (await db.collection('applications').doc(appId).get()).data().status,
  contract: contractId
    ? ((await db.collection('employment_contracts').doc(contractId).get())
        .data() ?? {}).status ?? '없음'
    : '없음',
});

/** 에뮬레이터 전용 초기화 — 같은 하네스를 다시 돌릴 수 있게 한다. */
async function reset() {
  for (const col of ['applications', 'employment_contracts']) {
    const snap = await db.collection(col).get();
    for (const d of snap.docs) await d.ref.delete();
  }
}

(async () => {
  await reset();

  // ══ 0a. 대조군 — 이 에뮬레이터가 **충돌 감지를 하는가** ══
  //
  //   이걸 먼저 재지 않으면, 아래 모델의 실패가 설계 문제인지 에뮬레이터
  //   한계인지 구별할 수 없다. 교과서적 경쟁 하나를 둔다:
  //   A 가 문서를 읽고, 그 사이 외부가 같은 문서를 바꾸고, A 가 쓴다.
  {
    const ref = db.collection('probe').doc('conflict');
    await ref.set({n: 1});
    let fired = false;
    let attempts = 0;
    await db.runTransaction(async (tx) => {
      attempts++;
      const s = await tx.get(ref);
      if (!fired) {
        fired = true;
        ref.update({n: 99}).catch(() => {});   // await 하지 않는다 (교착 방지)
        await sleep(400);
      }
      tx.update(ref, {n: s.data().n + 1});
    });
    const fin = (await ref.get()).data().n;
    observe('RA-X0 대조군: 이 에뮬레이터의 트랜잭션 충돌 감지',
        {retried: attempts >= 2, attempts, finalN: fin},
        '재시도가 없으면(attempts=1) 이 환경은 충돌을 감지하지 않는다 ' +
        '→ 아래 M3·M4 는 **판정 보류**다. 프로덕션 Firestore 의 ' +
        '서버 SDK 트랜잭션 의미론은 여기서 확인할 수 없다');
  }

  // ══ 0. 슬라이스 건전성 ══
  let predOk = true;
  for (const [st, want] of PRED) {
    if (srvContractNotIssuedYet(st) !== want) predOk = false;
  }
  check('RA-00 제품 술어를 그대로 떼어 왔다', predOk, true,
      'voided·pending_employer·draft·없음 = 미발송');

  // ══ 1. 경쟁 A — 롤백 읽기 → 발행 커밋 → 롤백 쓰기 ══
  //
  //   M1·M2 는 **결함 재현** 셀이다. 기대값이 `voided`·`PENDING` 인 것은
  //   그게 옳다는 뜻이 아니라, 지금 코드가 그렇게 한다는 사실을 고정한다는
  //   뜻이다. 보호를 기대하는 것은 M3 뿐이다.
  const RACE_A = {
    M1: {fn: m1Rollback, contract: 'voided', app: 'PENDING',
      note: '현재 클라이언트 경로 — B 의 정상 계약을 void 한다 (I-1 위반 재현)'},
    M2: {fn: m2Rollback, contract: 'voided', app: 'PENDING',
      note: '지원서 문서만 트랜잭션 — 계약은 **다른 컬렉션의 새 문서**라 ' +
        '충돌이 감지되지 않는다. 트랜잭션을 썼다는 사실만으로는 해결되지 않는다'},
    M3: {fn: m3Rollback, contract: 'pending_worker', app: 'CONTRACT_PENDING',
      note: '같은 트랜잭션 안에서 제품 술어로 원장을 질의 → 쓰기 0, void 0'},
  };
  for (const [name, spec] of Object.entries(RACE_A)) {
    const appId = await freshApp('CONTRACT_PENDING');
    const cid = `ct_A_${name}`;
    const r = await spec.fn(appId, async () => { await issueContract(appId, cid); });
    const s = await stateOf(appId, cid);
    check(`RA-A/${name} 계약·지원서 최종 상태`,
        {contract: s.contract, app: s.app},
        {contract: spec.contract, app: spec.app},
        `${spec.note} | 결과=${r.result} 쓰기=${r.wrote} ` +
        `void=${JSON.stringify(r.voided)}${r.attempts ? ` 시도=${r.attempts}` : ''}`);
  }

  // ══ 1b. 경쟁 A-strict — 배리어를 **모든 읽기 뒤**로 ══
  //   M3 의 안전성이 "질의 순서 운"이 아니라 **잠금**에서 오는지 가른다.
  {
    const appId = await freshApp('CONTRACT_PENDING');
    const cid = 'ct_Astrict_M3';
    const r = await m3StrictRollback(appId,
        () => issueContract(appId, cid));
    const s = await stateOf(appId, cid);
    observe('RA-A2/M3-strict 모든 읽기 뒤에 B 가 커밋',
        {contract: s.contract, app: s.app, result: r.result,
          attempts: r.attempts, b: r.bResult},
        '쿼리를 트랜잭션에 넣어도 **읽을 때 없던 문서**(phantom)는 ' +
        '잡히지 않는다. 이 환경은 충돌 감지 자체가 없어 분리 입증 불가 → 보류');
  }

  // ══ 1c. 경쟁 A-strict / M4 — 지원서 표식으로 경쟁 ══
  {
    const appId = await freshApp('CONTRACT_PENDING');
    const cid = 'ct_Astrict_M4';
    const r = await m4Rollback(appId, () => issueContractWithMark(appId, cid));
    const s = await stateOf(appId, cid);
    observe('RA-A3/M4 지원서 표식을 공유하는 설계',
        {contract: s.contract, app: s.app, result: r.result,
          attempts: r.attempts, b: r.bResult},
        '두 writer 가 **처음부터 있는 같은 문서**를 읽고 쓴다 — 프로덕션 ' +
        '서버 SDK 라면 충돌이 잡혀야 한다. 이 환경은 감지가 없어 보류. ' +
        'B 가 failed-precondition 으로 끝난 것은 A 가 먼저 PENDING 을 ' +
        '써서 발행 선행조건이 깨졌다는 뜻이다(순서 역전)');
  }

  // ══ 1d. M4 — 경쟁이 없을 때는 정상 복구된다 ══
  {
    const appId = await freshApp('CONTRACT_PENDING');
    const r = await m4Rollback(appId, null);
    const s = await stateOf(appId, null);
    check('RA-A4/M4 경쟁이 없으면 복구가 된다',
        {result: r.result, app: s.app}, {result: 'rolledBack', app: 'PENDING'});
  }

  // ══ 2. 경쟁 B — 롤백 커밋 → 발행 시도 ══
  for (const [name, fn] of [['M1', m1Rollback], ['M2', m2Rollback], ['M3', m3Rollback]]) {
    const appId = await freshApp('CONTRACT_PENDING');
    const r = await fn(appId, null);
    let issueErr = null;
    try {
      await issueContract(appId, `ct_B_${name}`);
    } catch (e) { issueErr = e.message; }
    const s = await stateOf(appId, `ct_B_${name}`);
    check(`RA-B/${name} 롤백이 먼저면 지원서는 PENDING`, s.app, 'PENDING',
        `결과=${r.result}`);
    check(`RA-B/${name} 그 뒤 발행은 원장 기준으로 판단된다`,
        {contract: s.contract, issueErr}, {contract: 'pending_worker', issueErr: null},
        '계약 원장에는 아직 아무것도 없으므로 발행 자체는 막히지 않는다 ' +
        '— 지원서 상태 검증은 CF PREAUTH 가 한다(이 하네스 범위 밖)');
  }

  // ══ 3. 이미 계약이 있으면 어느 모델도 손대지 않는다 ══
  for (const st of ['pending_worker', 'completed']) {
    const appId = await freshApp('CONTRACT_PENDING');
    const cid = `ct_pre_${st}_${caseNo}`;
    await db.collection('employment_contracts').doc(cid).set({
      businessId: BIZ, workerId: WORKER, applicationId: appId, status: st,
    });
    const r = await m3Rollback(appId, null);
    const s = await stateOf(appId, cid);
    check(`RA-C/${st} 롤백·void 금지`,
        {result: r.result, app: s.app, contract: s.contract},
        {result: 'already', app: 'CONTRACT_PENDING', contract: st});
  }

  // ══ 4. 다른 날짜(다른 지원서)의 계약은 영향이 없다 ══
  {
    const appA = await freshApp('CONTRACT_PENDING');
    const appB = await freshApp('CONTRACT_PENDING');
    await issueContract(appB, 'ct_other_date');
    const r = await m3Rollback(appA, null);
    const s = await stateOf(appB, 'ct_other_date');
    check('RA-D 다른 근무일 계약의 독립성',
        {result: r.result, otherApp: s.app, otherContract: s.contract},
        {result: 'rolledBack', otherApp: 'CONTRACT_PENDING',
          otherContract: 'pending_worker'});
  }

  // ══ 5. 계약 없는 확정 실패 — 안전한 복구가 된다 ══
  {
    const appId = await freshApp('CONTRACT_PENDING');
    const r = await m3Rollback(appId, null);
    const s = await stateOf(appId, null);
    check('RA-E 계약 없는 확정 실패는 복구된다',
        {result: r.result, app: s.app}, {result: 'rolledBack', app: 'PENDING'});
  }

  // ══ 6. 롤백 재시도 멱등성 ══
  {
    const appId = await freshApp('CONTRACT_PENDING');
    await m3Rollback(appId, null);
    const r2 = await m3Rollback(appId, null);
    const s = await stateOf(appId, null);
    check('RA-F 재시도는 멱등 (두 번째는 쓰지 않는다)',
        {result: r2.result, wrote: r2.wrote, app: s.app},
        {result: 'failed', wrote: false, app: 'PENDING'},
        'PENDING 이면 되돌릴 것이 없다 → 쓰기 0');
  }

  // ══ 7. 두 발행이 동시에 — 중복 계약 0건 ══
  {
    const appId = await freshApp('CONTRACT_PENDING');
    const r = await Promise.allSettled([
      issueContract(appId, 'ct_dup_1'),
      issueContract(appId, 'ct_dup_2'),
    ]);
    const q = await db.collection('employment_contracts')
        .where('businessId', '==', BIZ).where('applicationId', '==', appId).get();
    const live = q.docs.filter((d) => !srvContractNotIssuedYet(d.data().status));
    check('RA-G 동시 발행에서도 계약은 1건', live.length, 1,
        '결과=' + JSON.stringify(r.map((x) => x.status)));
  }

  // ══ 8. 근로자 서명(completed)은 어떤 경로로도 void 되지 않는다 ══
  {
    const appId = await freshApp('CONTRACT_PENDING');
    await db.collection('employment_contracts').doc('ct_done').set({
      businessId: BIZ, workerId: WORKER, applicationId: appId,
      status: 'completed',
    });
    const voided = await voidContractsFor(appId);
    const s = await stateOf(appId, 'ct_done');
    check('RA-H completed 는 void 대상이 아니다',
        {voided, contract: s.contract}, {voided: [], contract: 'completed'},
        'VOID_TARGET = pending_employer·pending_worker·draft');
  }

  // ── 출력 ──
  console.log('\n' + '═'.repeat(74));
  for (const r of results) {
    console.log(`${r.ok === null ? '관측' : (r.ok ? 'PASS' : 'FAIL')}  ${r.label}`);
    if (r.ok === null) console.log(`        ${JSON.stringify(r.actual)}`);
    if (r.ok === false) {
      console.log(`        기대: ${JSON.stringify(r.expected)}`);
      console.log(`        실제: ${JSON.stringify(r.actual)}`);
    }
    if (r.note) console.log(`        · ${r.note}`);
  }
  console.log('═'.repeat(74));
  console.log(`총 ${results.length}판정 / 실패 ${failures}`);
  process.exit(failures ? 1 : 0);
})().catch((e) => {
  console.log('오류:', e && e.stack ? e.stack.split('\n').slice(0, 8).join('\n') : e);
  process.exit(1);
});
