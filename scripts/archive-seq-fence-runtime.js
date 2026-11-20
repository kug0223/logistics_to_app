/**
 * [ARCHIVE-SEQ-FENCE] 운영 종료 사업장 — 남은 대기·계약 대기로 새 확정이 생기는가.
 *
 *   같은 원장(같은 seed)을 BEFORE 번들과 AFTER 번들에 차례로 올려 비교한다.
 *   callable 은 번들의 `.run` 으로 직접 부른다(App Check 우회 — 에뮬레이터 전용).
 *   트리거는 돌지 않는다(Functions 에뮬레이터 없음) → 보이는 쓰기는 callable 자신의 것뿐.
 *
 *   실행: firestore+storage 에뮬레이터 기동 후
 *     BEFORE=<lib/index.js> AFTER=<lib/index.js> node scripts/archive-seq-fence-runtime.js
 *   DEV·PROD 에 연결하지 않는다(demo-alfit-r7).
 */
'use strict';
const fs = require('fs');
const path = require('path');
const ROOT = path.join(__dirname, '..');
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:6070';
process.env.GCLOUD_PROJECT = 'demo-alfit-r7';
process.env.FIREBASE_CONFIG = JSON.stringify({projectId: 'demo-alfit-r7', storageBucket: 'demo-alfit-r7.appspot.com'});
process.env.FIREBASE_STORAGE_EMULATOR_HOST = '127.0.0.1:6071';
delete process.env.GOOGLE_APPLICATION_CREDENTIALS;
for (const line of fs.readFileSync(path.join(ROOT, 'functions', '.env.demo-alfit-r7'), 'utf8').split(/\r?\n/)) {
  const m = /^([A-Z0-9_]+)=(.*)$/.exec(line); if (m) process.env[m[1]] = m[2];
}
const log = console.log; console.error = () => {}; console.warn = () => {}; console.log = () => {}; console.info = () => {};
process.env.NODE_PATH = path.join(ROOT, 'functions', 'node_modules');
require('module').Module._initPaths();
const admin = require(path.join(ROOT, 'functions', 'node_modules', 'firebase-admin'));
if (!process.env.BEFORE || !process.env.AFTER) throw new Error('BEFORE·AFTER 번들 경로가 필요하다');
// 번들마다 initializeApp 을 부르므로 한 프로세스에 하나씩 — 부모가 두 자식을 띄워 결과를 맞댄다.
const LABEL = process.env.LABEL;
const BUNDLE = LABEL ? require(process.env[LABEL]) : null;
if (!admin.apps.length) admin.initializeApp(); // 부모(비교만 함)
const db = admin.firestore();
const {Timestamp} = admin.firestore;
const bucket = admin.storage().bucket();

const RUN = 'sf' + Date.now().toString(36);
const K = 9 * 3600e3;
const NOW = Date.now();
const kstMidnight = (ms) => { const d = new Date(ms + K); return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()) - K; };
const TODAY = kstMidnight(NOW); const DAY = 86400e3;
let seq = 0;
const uid = (p) => `${p}-${RUN}-${++seq}`;
const B64 = Buffer.from('fence-test').toString('base64');

/** 사업장 + 마감 공고 + 슬롯. closed 면 운영 종료 상태(연쇄가 이미 지나간 뒤 모양). */
async function world(closed) {
  const biz = uid('b'); const owner = uid('o'); const worker = uid('w'); const to = uid('t'); const slot = 's1';
  await db.doc(`users/${owner}`).set({role: 'BUSINESS_ADMIN', sealBase64: 'x', businessId: biz, name: 'owner'});
  await db.doc(`users/${worker}`).set({role: 'USER', name: 'worker'});
  await db.doc(`businesses/${biz}`).set(Object.assign({isApproved: true, ownerId: owner, adminIds: [owner], name: 'biz'},
    closed ? {deactivatedAt: Timestamp.fromMillis(NOW - 3600e3)} : {deactivatedAt: null}));
  // 종료 연쇄는 ACTIVE/FULL/SCHEDULED 만 접는다 — 이 공고는 그 전에 이미 마감돼 있었다.
  await db.doc(`tos/${to}`).set({businessId: biz, status: closed ? 'CLOSED' : 'ACTIVE', closedReason: closed ? 'MANUAL' : null,
    title: 't', type: 'flex', totalPending: 1, totalConfirmed: 0, totalRequired: 3});
  await db.doc(`tos/${to}/slots/${slot}`).set({date: Timestamp.fromMillis(TODAY + DAY), status: closed ? 'closed' : 'open',
    workDetails: [{id: 'wd1', wdId: 'wd1', workType: 'QA', requiredCount: 3}], pendingCount: 1, confirmedCount: 0,
    workDetailCounts: {wd1: {pendingCount: 1, confirmedCount: 0}}});
  return {biz, owner, worker, to, slot};
}
async function app(w, status, o = {}) {
  const id = uid('a');
  await db.doc(`applications/${id}`).set(Object.assign({uid: w.worker, businessId: w.biz, toId: w.to, slotId: w.slot,
    wdId: 'wd1', selectedWorkType: 'QA', status, workDate: Timestamp.fromMillis(TODAY + DAY), startTime: '09:00', endTime: '18:00',
    businessName: 'biz', appliedAt: Timestamp.now(), statusHistory: []}, o));
  return id;
}
async function contract(w, appId, status) {
  const id = uid('c');
  await db.doc(`employment_contracts/${id}`).set({businessId: w.biz, workerId: w.worker, applicationId: appId, applicationIds: [appId],
    status, snapshot: {workerName: 'worker'}, employerSignatureUrl: status === 'pending_worker' ? 'https://x/e.png' : null});
  return id;
}

/** 이 세계에서 callable 이 건드릴 수 있는 모든 것의 지문. */
async function ledger(w, ids) {
  const docs = {};
  for (const p of [`tos/${w.to}`, `tos/${w.to}/slots/${w.slot}`, ...ids.apps.map((a) => `applications/${a}`),
    ...ids.contracts.map((c) => `employment_contracts/${c}`)]) {
    const d = (await db.doc(p).get()).data();
    docs[p] = d ? JSON.stringify(Object.keys(d).sort().map((k) => [k, d[k] && d[k].toMillis ? 'ts' : d[k]])) : null;
  }
  const contracts = (await db.collection('employment_contracts').where('businessId', '==', w.biz).get()).size;
  const notifs = (await db.collection(`users/${w.worker}/notifications`).get()).size;
  const files = (await bucket.getFiles({prefix: 'contracts/'}))[0]
    .filter((f) => ids.contracts.some((c) => f.name.startsWith(`contracts/${c}/`)) || f.name.includes(RUN)).length;
  return {docs, contracts, notifs, files};
}
const diff = (a, b) => {
  const out = [];
  for (const k of Object.keys(a.docs)) if (a.docs[k] !== b.docs[k]) out.push(k.split('/').slice(0, 1).join('') + '변경');
  if (a.contracts !== b.contracts) out.push(`계약 ${a.contracts}→${b.contracts}`);
  if (a.notifs !== b.notifs) out.push(`알림 ${a.notifs}→${b.notifs}`);
  if (a.files !== b.files) out.push(`파일 ${a.files}→${b.files}`);
  return out;
};
const st = async (p) => ((await db.doc(p).get()).data() || {}).status;

async function call(fn, name, who, data) {
  try { await fn[name].run({auth: {uid: who, token: {}}, rawRequest: {headers: {}}, data}); return 'ALLOW'; } catch (e) {
    return 'DENY:' + (e.details && e.details.reason ? e.details.reason : (e.code || '') + ' ' + String(e.message).slice(0, 40));
  }
}
const workerSign = (fn, w, c) => call(fn, 'callableFinalizeWorkerSignature', w.worker, {contractId: c, signatureBase64: B64, pdfBase64: B64});
const employerNew = (fn, w, a, cid) => call(fn, 'callableFinalizeEmployerSignature', w.owner, {contractId: cid || uid('nc'),
  signatureBase64: B64, isNewUnsaved: true, contractData: Object.assign({businessId: w.biz, workerId: w.worker, isLongTerm: false,
    toId: w.to, snapshot: {workerName: 'worker'}, articles: [], templateId: 'tpl'}, a ? {applicationId: a, applicationIds: [a]} : {})});
const employerExisting = (fn, w, c) => call(fn, 'callableFinalizeEmployerSignature', w.owner, {contractId: c, signatureBase64: B64});
const approve = (fn, w, a) => call(fn, 'callableApproveApplicationForReview', w.owner, {applicationId: a});

const PAST = Timestamp.fromMillis(TODAY - DAY); // 어제(KST)
const CASES = [
  // [id, 설명, 기대 BEFORE, 기대 AFTER, 실행]
  ['K1', '종료·마감공고 CONTRACT_PENDING 의 근로자 서명', 'ALLOW', 'DENY', async (fn) => {
    const w = await world(true); const a = await app(w, 'CONTRACT_PENDING'); const c = await contract(w, a, 'pending_worker');
    return {w, ids: {apps: [a], contracts: [c]}, act: () => workerSign(fn, w, c), after: async () => `app ${await st(`applications/${a}`)} · 계약 ${await st(`employment_contracts/${c}`)}`};
  }],
  ['K2', '종료·마감공고 PENDING 의 지원 검토 승인', 'ALLOW', 'DENY', async (fn) => {
    const w = await world(true); const a = await app(w, 'PENDING');
    return {w, ids: {apps: [a], contracts: []}, act: () => approve(fn, w, a), after: async () => `app ${await st(`applications/${a}`)}`};
  }],
  ['K3', '종료: 승인 → 새 계약(사업주) → 근로자 서명 연쇄', 'ALLOW', 'DENY', async (fn) => {
    const w = await world(true); const a = await app(w, 'PENDING'); const cid = uid('nc');
    return {w, ids: {apps: [a], contracts: [cid]}, act: async () => {
      const r1 = await approve(fn, w, a); const r2 = await employerNew(fn, w, a, cid);
      const r3 = (await st(`employment_contracts/${cid}`)) === 'pending_worker' ? await workerSign(fn, w, cid) : 'SKIP';
      return [r1, r2, r3].every((x) => x === 'ALLOW') ? 'ALLOW' : `DENY(${[r1, r2, r3].map((x) => x.split(':')[0]).join('/')})`;
    }, after: async () => `app ${await st(`applications/${a}`)} · 계약 ${await st(`employment_contracts/${cid}`) || '없음'}`};
  }],
  ['K4', '종료: 승인 이미 된 CONTRACT_PENDING 재승인(멱등 분기·알림)', 'ALLOW', 'DENY', async (fn) => {
    const w = await world(true); const a = await app(w, 'CONTRACT_PENDING');
    return {w, ids: {apps: [a], contracts: []}, act: () => approve(fn, w, a), after: async () => `app ${await st(`applications/${a}`)}`};
  }],
  ['K5', '종료: CONTRACT_PENDING 에 새 미서명 계약(사업주)', 'ALLOW', 'DENY', async (fn) => {
    const w = await world(true); const a = await app(w, 'CONTRACT_PENDING'); const cid = uid('nc');
    return {w, ids: {apps: [a], contracts: [cid]}, act: () => employerNew(fn, w, a, cid), after: async () => `계약 ${await st(`employment_contracts/${cid}`) || '없음'}`};
  }],
  ['K6', '종료: CONTRACT_PENDING 의 기존 pending_employer 계약 사업주 서명', 'ALLOW', 'DENY', async (fn) => {
    const w = await world(true); const a = await app(w, 'CONTRACT_PENDING'); const c = await contract(w, a, 'pending_employer');
    return {w, ids: {apps: [a], contracts: [c]}, act: () => employerExisting(fn, w, c), after: async () => `계약 ${await st(`employment_contracts/${c}`)}`};
  }],
  ['K7', '종료: 레거시 새 계약(applicationId 없음)', 'ALLOW', 'DENY', async (fn) => {
    const w = await world(true); const a = await app(w, 'CONTRACT_PENDING'); const cid = uid('nc');
    return {w, ids: {apps: [a], contracts: [cid]}, act: () => employerNew(fn, w, null, cid), after: async () => `계약 ${await st(`employment_contracts/${cid}`) || '없음'}`};
  }],
  ['K8', '종료: 시작 전 CONFIRMED(연쇄 누락 가정)의 근로자 서명', 'ALLOW', 'DENY', async (fn) => {
    const w = await world(true); const a = await app(w, 'CONFIRMED'); const c = await contract(w, a, 'pending_worker');
    return {w, ids: {apps: [a], contracts: [c]}, act: () => workerSign(fn, w, c), after: async () => `app ${await st(`applications/${a}`)} · 계약 ${await st(`employment_contracts/${c}`)}`};
  }],
  ['K9', '종료: 오늘 근무·시작 시각 모름 CONFIRMED 서명(모름≠일함)', 'ALLOW', 'DENY', async (fn) => {
    const w = await world(true); const a = await app(w, 'CONFIRMED', {workDate: Timestamp.fromMillis(TODAY), startTime: null});
    const c = await contract(w, a, 'pending_worker');
    return {w, ids: {apps: [a], contracts: [c]}, act: () => workerSign(fn, w, c), after: async () => `계약 ${await st(`employment_contracts/${c}`)}`};
  }],
  // ── 보존 경계: 둘 다 허용, 지원서 상태 불변
  ['P1', '종료: 어제 시작한 보존 CONFIRMED 의 근로자 서명', 'ALLOW', 'ALLOW', async (fn) => {
    const w = await world(true); const a = await app(w, 'CONFIRMED', {workDate: PAST}); const c = await contract(w, a, 'pending_worker');
    return {w, ids: {apps: [a], contracts: [c]}, act: () => workerSign(fn, w, c), after: async () => `app ${await st(`applications/${a}`)} · 계약 ${await st(`employment_contracts/${c}`)}`};
  }],
  ['P2', '종료: 어제·시작 시각 모름 보존 CONFIRMED 서명(하루가 다 지남)', 'ALLOW', 'ALLOW', async (fn) => {
    const w = await world(true); const a = await app(w, 'CONFIRMED', {workDate: PAST, startTime: null}); const c = await contract(w, a, 'pending_worker');
    return {w, ids: {apps: [a], contracts: [c]}, act: () => workerSign(fn, w, c), after: async () => `app ${await st(`applications/${a}`)} · 계약 ${await st(`employment_contracts/${c}`)}`};
  }],
  ['P3', '종료: 보존 CONFIRMED 의 새 계약(사업주, 문서화)', 'ALLOW', 'ALLOW', async (fn) => {
    const w = await world(true); const a = await app(w, 'CONFIRMED', {workDate: PAST}); const cid = uid('nc');
    return {w, ids: {apps: [a], contracts: [cid]}, act: () => employerNew(fn, w, a, cid), after: async () => `app ${await st(`applications/${a}`)} · 계약 ${await st(`employment_contracts/${cid}`) || '없음'}`};
  }],
  ['P4', '종료: 시작 전이지만 출근 기록 있는 CONFIRMED 서명(실근무)', 'ALLOW', 'ALLOW', async (fn) => {
    const w = await world(true); const a = await app(w, 'CONFIRMED'); const c = await contract(w, a, 'pending_worker');
    const d = new Date(TODAY + DAY + K); const key = `${d.getUTCFullYear()}${String(d.getUTCMonth() + 1).padStart(2, '0')}${String(d.getUTCDate()).padStart(2, '0')}`;
    await db.doc(`attendance/${a}_${key}`).set({applicationId: a, userId: w.worker, checkIn: Timestamp.now(), status: 'working'});
    return {w, ids: {apps: [a], contracts: [c]}, act: () => workerSign(fn, w, c), after: async () => `app ${await st(`applications/${a}`)} · 계약 ${await st(`employment_contracts/${c}`)}`};
  }],
  // ── 운영 중 사업장: 둘 다 허용
  ['O1', '운영 중: CONTRACT_PENDING 근로자 서명 → CONFIRMED', 'ALLOW', 'ALLOW', async (fn) => {
    const w = await world(false); const a = await app(w, 'CONTRACT_PENDING'); const c = await contract(w, a, 'pending_worker');
    return {w, ids: {apps: [a], contracts: [c]}, act: () => workerSign(fn, w, c), after: async () => `app ${await st(`applications/${a}`)} · 계약 ${await st(`employment_contracts/${c}`)}`};
  }],
  ['O2', '운영 중: PENDING 승인 → CONTRACT_PENDING', 'ALLOW', 'ALLOW', async (fn) => {
    const w = await world(false); const a = await app(w, 'PENDING');
    return {w, ids: {apps: [a], contracts: []}, act: () => approve(fn, w, a), after: async () => `app ${await st(`applications/${a}`)}`};
  }],
  ['O3', '운영 중: 승인 → 새 계약 → 근로자 서명 연쇄', 'ALLOW', 'ALLOW', async (fn) => {
    const w = await world(false); const a = await app(w, 'PENDING'); const cid = uid('nc');
    return {w, ids: {apps: [a], contracts: [cid]}, act: async () => {
      const r1 = await approve(fn, w, a); const r2 = await employerNew(fn, w, a, cid);
      const r3 = (await st(`employment_contracts/${cid}`)) === 'pending_worker' ? await workerSign(fn, w, cid) : 'SKIP';
      return [r1, r2, r3].every((x) => x === 'ALLOW') ? 'ALLOW' : `DENY(${[r1, r2, r3].join('/')})`;
    }, after: async () => `app ${await st(`applications/${a}`)} · 계약 ${await st(`employment_contracts/${cid}`) || '없음'}`};
  }],
  ['O4', '운영 중: pending_employer 사업주 서명', 'ALLOW', 'ALLOW', async (fn) => {
    const w = await world(false); const a = await app(w, 'CONTRACT_PENDING'); const c = await contract(w, a, 'pending_employer');
    return {w, ids: {apps: [a], contracts: [c]}, act: () => employerExisting(fn, w, c), after: async () => `계약 ${await st(`employment_contracts/${c}`)}`};
  }],
];

async function child() {
  const out = {};
  for (const [id, , , , mk] of CASES) {
    const s = await mk(BUNDLE);
    const l0 = await ledger(s.w, s.ids);
    const r = await s.act();
    const l1 = await ledger(s.w, s.ids);
    out[id] = {r, changes: diff(l0, l1), state: await s.after()};
  }
  log('@@' + JSON.stringify(out));
  process.exit(0);
}

(async () => {
  if (LABEL) return child();
  const {execFileSync} = require('child_process');
  const got = {};
  for (const label of ['BEFORE', 'AFTER']) {
    const o = execFileSync(process.execPath, [__filename], {env: Object.assign({}, process.env, {LABEL: label}), maxBuffer: 1 << 26}).toString();
    got[label] = JSON.parse(o.split('@@').pop());
  }
  let fail = 0; const rows = [];
  for (const [id, desc, eB, eA] of CASES) {
    const res = {BEFORE: got.BEFORE[id], AFTER: got.AFTER[id]};
    const okB = res.BEFORE.r.startsWith(eB); const okA = res.AFTER.r.startsWith(eA);
    // 거절이면 쓰기 0 이어야 한다(지원서·계약·공고·슬롯·알림·파일)
    const zeroOk = !res.AFTER.r.startsWith('DENY') || res.AFTER.changes.length === 0;
    const ok = okB && okA && zeroOk; if (!ok) fail++;
    rows.push(`${ok ? 'ok  ' : 'FAIL'} ${id.padEnd(3)} ${desc}\n       BEFORE ${res.BEFORE.r} | ${res.BEFORE.state} | 변화 [${res.BEFORE.changes.join(', ')}]` +
      `\n       AFTER  ${res.AFTER.r} | ${res.AFTER.state} | 변화 [${res.AFTER.changes.join(', ')}]`);
  }
  log(rows.join('\n'));
  log(`\n셀 ${CASES.length} · 실패 ${fail}`);
  process.exit(fail ? 1 : 0);
})().catch((e) => { log('ERR ' + e.stack); process.exit(2); });
