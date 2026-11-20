// [NOSHOW-CONTRACT-GUARD] 노쇼·결근 단기 근무일에는 계약서를 발행하지 않는다 —
//   발행(callableFinalizeEmployerSignature)·미발송 목록(callableGetUnsentApplicationsByBiz)·
//   관리자 홈 숫자(callableGetAdminHomeSummary)가 같은 판정을 쓴다.
//
//   실행:  cd functions && npm run build && node test/noshow_contract_guard.test.js
//          다른 빌드: CIG_FUNCTIONS_DIR=<dir with lib/index.js> node test/noshow_contract_guard.test.js
//
//   DEV 실측(10-20): 관리자 미발송 7건 중 6건이 지난 NO_SHOW 근무였다(실근무 JYAe 1건).
//   빌드된 lib/index.js 의 **실제 핸들러 전체**를 가짜 firebase-functions/admin
//   (require 가로채기)·메모리 Firestore·가짜 Storage 로 실행한다.
//   거절 사례는 Firestore 쓰기(계약·지원서·공고·슬롯·사용자·알림 전부)를 직접 센다.
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const Module = require('module');

// ── 가짜 Firestore ────────────────────────────────────────────────────────
class FakeTimestamp {
  constructor(ms) { this._ms = ms; }
  static fromMillis(ms) { return new FakeTimestamp(ms); }
  static fromDate(d) { return new FakeTimestamp(d.getTime()); }
  static now() { return new FakeTimestamp(Date.now()); }
  toMillis() { return this._ms; }
  toDate() { return new global.Date(this._ms); }
  get seconds() { return Math.floor(this._ms / 1000); }
  get nanoseconds() { return (this._ms % 1000) * 1e6; }
}
const SERVER_TS = {__serverTimestamp: true};
const FieldValue = {
  serverTimestamp: () => SERVER_TS,
  increment: (n) => ({__inc: n}),
  arrayUnion: (...a) => ({__union: a}),
  arrayRemove: (...a) => ({__remove: a}),
  delete: () => ({__delete: true}),
};
const FieldPath = {documentId: () => '__name__'};

let STORE = new Map();
let WRITES = [];
let STORAGE = [];            // {op, path}
let ON_UPLOAD = null;        // 업로드 직후 훅 — "목록 조회와 서명 사이" 근태 변경 재현

function snapOf(p, fields) {
  const raw = STORE.get(p);
  const data = raw === undefined ? undefined :
    fields ? Object.fromEntries(fields.filter((f) => f in raw).map((f) => [f, raw[f]])) : raw;
  return {
    id: p.split('/').pop(), exists: raw !== undefined, ref: refOf(p),
    data: () => (data === undefined ? undefined : {...data}),
    get: (f) => (data === undefined ? undefined : data[f]),
    updateTime: FakeTimestamp.fromMillis(0),
  };
}
function refOf(p) {
  return {
    path: p, id: p.split('/').pop(),
    get: async () => snapOf(p),
    set: async (d) => { WRITES.push({op: 'set', path: p}); STORE.set(p, d); },
    update: async (d) => { WRITES.push({op: 'update', path: p}); STORE.set(p, {...STORE.get(p), ...d}); },
    delete: async () => { WRITES.push({op: 'delete', path: p}); STORE.delete(p); },
    collection: (c) => colOf(`${p}/${c}`),
  };
}
function colOf(c, st = {filters: [], fields: null, lim: Infinity, after: null}) {
  const next = (patch) => colOf(c, {...st, ...patch});
  const q = {
    doc: (id) => refOf(`${c}/${id}`),
    where: (f, op, v) => next({filters: [...st.filters, [f, op, v]]}),
    select: (...f) => next({fields: f}),
    limit: (n) => next({lim: n}),
    orderBy: () => q,
    startAfter: (snap) => next({after: snap.ref.path}),
    get: async () => {
      const paths = [...STORE.keys()].filter((p) =>
        p.startsWith(c + '/') && !p.slice(c.length + 1).includes('/')).sort();
      const docs = [];
      for (const p of paths) {
        if (st.after && p <= st.after) continue;
        const d = STORE.get(p);
        const ok = st.filters.every(([f, op, v]) =>
          op === '==' ? d[f] === v :
          op === 'in' ? v.includes(d[f]) :
          op === 'array-contains' ? Array.isArray(d[f]) && d[f].includes(v) :
          (() => { throw new Error('unsupported op ' + op); })());
        if (ok) docs.push(snapOf(p, st.fields));
        if (docs.length >= st.lim) break;
      }
      return {empty: docs.length === 0, size: docs.length, docs};
    },
  };
  return q;
}
const fakeDb = {
  collection: (c) => colOf(c),
  doc: (p) => refOf(p),
  getAll: async (...refs) => Promise.all(refs.map((r) => r.get())),
  runTransaction: async (fn) => {
    const pend = [];
    const tx = {
      get: async (r) => (r.get ? r.get() : r),
      set: (r, d) => pend.push(() => { WRITES.push({op: 'tx.set', path: r.path}); STORE.set(r.path, d); }),
      update: (r, d) => pend.push(() => { WRITES.push({op: 'tx.update', path: r.path}); }),
      delete: (r) => pend.push(() => { WRITES.push({op: 'tx.delete', path: r.path}); }),
    };
    const out = await fn(tx);
    pend.forEach((w) => w());    // 커밋은 콜백이 성공했을 때만
    return out;
  },
  batch: () => { const pend = []; return {
    set: (r) => pend.push(r.path), update: (r) => pend.push(r.path), delete: (r) => pend.push(r.path),
    commit: async () => pend.forEach((p) => WRITES.push({op: 'batch', path: p})),
  }; },
};
const fakeStorage = () => ({bucket: () => ({
  name: 'test-bucket',
  file: (p) => ({
    metadata: {generation: '1'},
    save: async () => { STORAGE.push({op: 'save', path: p}); if (ON_UPLOAD) await ON_UPLOAD(); },
    delete: async () => { STORAGE.push({op: 'delete', path: p}); },
  }),
})});

// ── 가짜 firebase-functions / firebase-admin ────────────────────────────
class HttpsError extends Error {
  constructor(code, message, details) { super(message); this.code = code; this.details = details; }
}
const anyFn = new Proxy(function() {}, {get: () => anyFn, apply: () => ({})});
function functionsModule() {
  return new Proxy({}, {
    get: (_, k) => {
      if (k === 'HttpsError') return HttpsError;
      if (k === 'onCall') return (opts, h) => ({__handler: typeof opts === 'function' ? opts : h});
      if (k === '__esModule') return true;
      if (k === 'defineSecret' || k === 'defineString' || k === 'defineInt' ||
          k === 'defineBoolean') return () => ({value: () => '', name: 'x'});
      return anyFn;
    },
  });
}
const adminModule = {
  initializeApp: () => ({}), apps: [], app: () => ({}),
  firestore: Object.assign(() => fakeDb, {Timestamp: FakeTimestamp, FieldValue, FieldPath}),
  auth: () => anyFn, storage: fakeStorage, messaging: () => anyFn, credential: anyFn,
};
Module._load = (function(orig) {
  return function(request) {
    if (request.startsWith('firebase-functions')) return functionsModule();
    if (request === 'firebase-admin/app') return {initializeApp: () => ({}), getApps: () => []};
    if (request === 'firebase-admin/firestore') {
      return {getFirestore: () => fakeDb, Timestamp: FakeTimestamp, FieldValue, FieldPath,
        Firestore: function() {}};
    }
    if (request === 'firebase-admin' || request.startsWith('firebase-admin/')) return adminModule;
    return orig.apply(this, arguments);
  };
})(Module._load);

const FN_DIR = process.env.CIG_FUNCTIONS_DIR || path.join(__dirname, '..');
const LIB = path.join(FN_DIR, 'lib', 'index.js');
const SRC = path.join(FN_DIR, 'src', 'index.ts');
console.log(`[target] ${FN_DIR}`);
const quiet = {error: console.error, warn: console.warn};
console.error = () => {}; console.warn = () => {};
const lib = require(LIB);
const finalize = lib.callableFinalizeEmployerSignature.__handler;
const unsentList = lib.callableGetUnsentApplicationsByBiz.__handler;
const home = lib.callableGetAdminHomeSummary.__handler;
const _log = console.log;

// ── 픽스처(DEV 10-20 qa 사업장 축소판) ───────────────────────────────────
const KST = 9 * 3600e3;
const kstMid = (y, m, d) => Date.UTC(y, m - 1, d) - KST;
const dkey = (ms) => new Date(ms + KST).toISOString().slice(0, 10).replace(/-/g, '');
const BIZ = 'qa_biz';
const ADMIN = 'ADMINuid';
const XZAH = 'xZahWORKER';
const OZZ = '7oZZWORKER';

function app(id, uid, day, extra = {}) {
  return {id, data: {uid, businessId: BIZ, status: 'CONFIRMED', type: 'short',
    toId: 'TO1', slotId: 'S_' + id, workDate: FakeTimestamp.fromMillis(day),
    startTime: '10:00', endTime: '11:00', selectedWorkType: 'QA', ...extra}};
}
function att(appId, day, status, extra = {}) {
  return [`attendance/${appId}_${dkey(day)}`, {applicationId: appId, userId: 'x', businessId: BIZ,
    workDate: FakeTimestamp.fromMillis(day), status, ...extra}];
}
const D = (d) => kstMid(2026, 10, d);
const NOSHOW6 = [
  app('DLNt', OZZ, D(11)), app('QAvG', OZZ, D(10)), app('Toli', OZZ, D(15)),
  app('XNjJ', XZAH, D(13), {status: 'CONTRACT_PENDING'}), app('Zujr', XZAH, D(12), {status: 'CONTRACT_PENDING'}),
  app('n16p', OZZ, D(11)),
];
function seed({apps = [], atts = [], contracts = []} = {}) {
  STORE = new Map(); WRITES = []; STORAGE = []; ON_UPLOAD = null;
  STORE.set(`users/${ADMIN}`, {role: 'BUSINESS_ADMIN', accountStatus: 'active', managedBusinessIds: [BIZ]});
  STORE.set(`businesses/${BIZ}`, {name: 'QA 사업장', ownerId: ADMIN, adminIds: [ADMIN]});
  STORE.set('tos/TO1', {businessId: BIZ, totalConfirmed: 9, totalPending: 0});
  for (const a of apps) {
    STORE.set(`applications/${a.id}`, a.data);
    STORE.set(`tos/TO1/slots/S_${a.id}`, {confirmedCount: 1, pendingCount: 0});
  }
  for (const [p, d] of atts) STORE.set(p, d);
  contracts.forEach((c, i) => STORE.set(`employment_contracts/k${i}`, {businessId: BIZ, ...c}));
}
/** 전체 DEV 축소판: 노쇼 6 + 실근무 JYAe + 좌석반납 QAvG(xZah) + 같은 근로자 RUBE·Zdn7(완료 계약). */
function seedFull(more = {}) {
  seed({
    apps: [...NOSHOW6,
      app('JYAe', OZZ, D(10), {status: 'CONTRACT_PENDING'}),
      app('QAvGx', XZAH, D(10), {status: 'CONTRACT_PENDING', staffingReleasedAt: FakeTimestamp.fromMillis(D(11))}),
      app('RUBE', XZAH, D(20), {startTime: '13:00', endTime: '14:00'}),
      app('Zdn7', XZAH, D(20)),
      ...(more.apps ?? [])],
    atts: [...NOSHOW6.map((a) => att(a.id, a.data.workDate.toMillis(), 'NO_SHOW')),
      att('JYAe', D(10), 'present'), att('QAvGx', D(10), 'NO_SHOW'), att('RUBE', D(20), 'present'),
      ...(more.atts ?? [])],
    contracts: [{applicationId: 'RUBE', applicationIds: ['RUBE'], status: 'completed'},
      {applicationId: 'Zdn7', applicationIds: ['Zdn7'], status: 'completed'},
      ...(more.contracts ?? [])],
  });
}

const auth = {auth: {uid: ADMIN}};
async function listIds() {
  const r = await unsentList({...auth, data: {businessId: BIZ}});
  return r.applications.map((a) => a.id).sort();
}
async function homeCount() {
  const r = await home({...auth, data: {}});
  const u = r.actions.unsentContract;
  assert.strictEqual(u.available, true, '홈 미발송 집계가 실패했다');
  return u.count;
}
let seq = 0;
async function sign(appId, {applicationIds = [appId], workerId} = {}) {
  const a = STORE.get(`applications/${appId}`);
  try {
    const out = await finalize({...auth, data: {
      contractId: `NEW_${++seq}`, signatureBase64: Buffer.from('sig').toString('base64'),
      isNewUnsaved: true,
      contractData: {applicationId: appId, businessId: BIZ, workerId: workerId ?? (a && a.uid),
        applicationIds, toId: 'TO1', snapshot: {startTime: '10:00', endTime: '11:00'}},
    }});
    return {ok: true, out};
  } catch (e) {
    return {ok: false, code: e.code, reason: e.details && (e.details.code || e.details.reason), message: e.message};
  }
}
function snapshotLedger() {
  const pick = (pre) => JSON.stringify([...STORE].filter(([k]) => k.startsWith(pre)).sort());
  return {contracts: pick('employment_contracts/'), applications: pick('applications/'),
    tos: pick('tos/'), users: pick('users/'), attendance: pick('attendance/')};
}
function expectRejectedNoWrites(r, before, reason) {
  assert.strictEqual(r.ok, false, '거절돼야 한다');
  assert.strictEqual(r.code, 'failed-precondition', r.message);
  if (reason) assert.strictEqual(r.reason, reason, r.message);
  assert.strictEqual(WRITES.length, 0, '쓰기: ' + JSON.stringify(WRITES));
  const after = snapshotLedger();
  for (const k of Object.keys(before)) assert.strictEqual(after[k], before[k], `${k} 가 바뀌었다`);
}

let pass = 0;
const fails = [];
async function t(id, name, fn) {
  try { await fn(); pass++; _log(`  ok   ${id} ${name}`); } catch (e) {
    fails.push(`${id}: ${e.message.split('\n')[0]}`);
    _log(`  FAIL ${id} ${name} — ${e.message.split('\n')[0]}`);
  }
}

(async () => {
  _log('[NC-A] 미발송 목록·홈 숫자');
  await t('NC-1', 'DEV 축소판: 목록 = 실근무 JYAe 하나, 노쇼 6·좌석반납·완료 계약 제외', async () => {
    seedFull();
    assert.deepStrictEqual(await listIds(), ['JYAe']);
    assert.strictEqual(WRITES.length, 0);
  });
  await t('NC-2', '홈 숫자 = 목록 수(1)', async () => {
    seedFull();
    assert.strictEqual(await homeCount(), 1);
    assert.strictEqual(WRITES.length, 0);
  });
  await t('NC-3', '결근(absent)도 제외', async () => {
    seed({apps: [app('ABSN', OZZ, D(9))], atts: [att('ABSN', D(9), 'absent')]});
    assert.deepStrictEqual(await listIds(), []);
    assert.strictEqual(await homeCount(), 0);
  });
  await t('NC-4', '근태가 없는 지난 근무는 남는다(사후 계약 가능)', async () => {
    seed({apps: [app('NOAT', XZAH, D(9))]});
    assert.deepStrictEqual(await listIds(), ['NOAT']);
    assert.strictEqual(await homeCount(), 1);
  });
  await t('NC-5', '장기 근무는 근무일 노쇼가 있어도 남는다', async () => {
    seed({apps: [app('LONG', OZZ, D(1), {type: 'long_term', workDays: ['월'], workEndDate: FakeTimestamp.fromMillis(D(31))})],
      atts: [att('LONG', D(1), 'NO_SHOW')]});
    assert.deepStrictEqual(await listIds(), ['LONG']);
    assert.strictEqual(await homeCount(), 1);
  });
  await t('NC-6', '정확히 대응하지 않는 근태는 보지 않는다(다른 지원서 id·다른 날짜)', async () => {
    seed({apps: [app('MISM', OZZ, D(9)), app('OTHD', OZZ, D(9))],
      atts: [att('MISM', D(9), 'NO_SHOW', {applicationId: 'SOMEONE'}), att('OTHD', D(8), 'NO_SHOW')]});
    assert.deepStrictEqual(await listIds(), ['MISM', 'OTHD']);
    assert.strictEqual(await homeCount(), 2);
  });
  await t('NC-7', '노쇼를 present 로 정정하면 다시 목록에 오른다', async () => {
    seed({apps: [app('FIXD', OZZ, D(9))], atts: [att('FIXD', D(9), 'present')]});
    assert.deepStrictEqual(await listIds(), ['FIXD']);
  });

  _log('\n[NC-B] 발행 거절 — 쓰기 0');
  for (const a of NOSHOW6) {
    await t(`NC-8.${a.id}`, `노쇼 ${a.id} 발행 — CONTRACT_ATTENDANCE_NON_WORK, 업로드 0`, async () => {
      seedFull();
      const before = snapshotLedger();
      const r = await sign(a.id);
      expectRejectedNoWrites(r, before, 'CONTRACT_ATTENDANCE_NON_WORK');
      assert.ok(r.message.includes('노쇼·결근'), r.message);
      assert.strictEqual(STORAGE.length, 0, '업로드 전 거절이어야 한다');
    });
  }
  await t('NC-9', '결근(absent) 발행 거절', async () => {
    seed({apps: [app('ABSN', OZZ, D(9))], atts: [att('ABSN', D(9), 'absent')]});
    const before = snapshotLedger();
    expectRejectedNoWrites(await sign('ABSN'), before, 'CONTRACT_ATTENDANCE_NON_WORK');
  });
  await t('NC-10', '좌석 반납 QAvG(xZah) — 기존 반납 거절이 먼저(메시지 불변), 쓰기 0', async () => {
    seedFull();
    const before = snapshotLedger();
    const r = await sign('QAvGx');
    expectRejectedNoWrites(r, before);
    assert.ok(r.message.includes('좌석이 반납되었거나'), r.message);
  });
  await t('NC-11', '묶음 계약: 실근무 JYAe + 노쇼 DLNt 를 함께 담으면 거절', async () => {
    seedFull();
    const before = snapshotLedger();
    expectRejectedNoWrites(await sign('JYAe', {applicationIds: ['JYAe', 'DLNt']}), before,
      'CONTRACT_ATTENDANCE_NON_WORK');
  });

  _log('\n[NC-C] 발행 허용');
  await t('NC-12', '실근무 JYAe — 계약 1건(pending_worker), 이후 목록·홈에서 빠진다', async () => {
    seedFull();
    const r = await sign('JYAe');
    assert.ok(r.ok, r.message);
    const made = [...STORE].filter(([k, v]) => k.startsWith('employment_contracts/NEW_'));
    assert.strictEqual(made.length, 1);
    assert.strictEqual(made[0][1].status, 'pending_worker');
    assert.strictEqual(WRITES.filter((w) => w.path.startsWith('employment_contracts/')).length, 1);
    assert.ok(!WRITES.some((w) => /^(applications|tos)\//.test(w.path)), '지원서·공고·슬롯 쓰기 없음');
    assert.deepStrictEqual(await listIds(), []);
    assert.strictEqual(await homeCount(), 0);
  });
  await t('NC-13', '근태 없는 지난 근무 발행 허용', async () => {
    seed({apps: [app('NOAT', XZAH, D(9))]});
    assert.ok((await sign('NOAT')).ok);
  });
  await t('NC-14', '장기 근무(근무일 노쇼 있음) 발행 허용', async () => {
    seed({apps: [app('LONG', OZZ, D(1), {type: 'long_term', workDays: ['월'], workEndDate: FakeTimestamp.fromMillis(D(31))})],
      atts: [att('LONG', D(1), 'NO_SHOW')]});
    const r = await sign('LONG');
    assert.ok(r.ok, r.message);
  });
  await t('NC-15', '묶음 계약: 노쇼 없는 묶음(JYAe + 근태 없는 NOAT) 허용', async () => {
    seedFull({apps: [app('NOAT', OZZ, D(9))]});
    assert.ok((await sign('JYAe', {applicationIds: ['JYAe', 'NOAT']})).ok);
  });

  _log('\n[NC-D] 목록 조회와 서명 사이 근태 변경');
  await t('NC-16', '목록에 있던 근무에 업로드 중 노쇼가 기록되면 트랜잭션이 거절 — Firestore 쓰기 0, 업로드는 정리', async () => {
    seed({apps: [app('RACE', OZZ, D(9))]});
    assert.deepStrictEqual(await listIds(), ['RACE']);
    const before = snapshotLedger();
    ON_UPLOAD = async () => { const [p, d] = att('RACE', D(9), 'NO_SHOW'); STORE.set(p, d); };
    const r = await sign('RACE');
    const beforeWithAtt = {...before, attendance: snapshotLedger().attendance};
    expectRejectedNoWrites(r, beforeWithAtt, 'CONTRACT_ATTENDANCE_NON_WORK');
    assert.deepStrictEqual(STORAGE.map((x) => x.op), ['save', 'delete']);
    assert.strictEqual(STORAGE[0].path, STORAGE[1].path);
  });
  await t('NC-17', '목록 뒤 노쇼가 present 로 정정되면 발행 허용', async () => {
    seed({apps: [app('FIXD', OZZ, D(9))], atts: [att('FIXD', D(9), 'NO_SHOW')]});
    assert.deepStrictEqual(await listIds(), []);
    const [p, d] = att('FIXD', D(9), 'present'); STORE.set(p, d);
    assert.ok((await sign('FIXD')).ok);
  });

  _log('\n[NC-E] 이미 보낸 계약·과거 원장 불변');
  await t('NC-18', '완료 계약이 있는 노쇼 근무(XNjJ-7oZZ 형) — 목록 제외, 발행은 기존 중복 거절, 쓰기 0', async () => {
    seed({apps: [app('XNjZ', OZZ, D(13))], atts: [att('XNjZ', D(13), 'NO_SHOW')],
      contracts: [{applicationId: 'XNjZ', applicationIds: ['XNjZ'], status: 'completed'}]});
    assert.deepStrictEqual(await listIds(), []);
    const before = snapshotLedger();
    const r = await sign('XNjZ');
    assert.strictEqual(r.ok, false);
    assert.strictEqual(WRITES.length, 0);
    assert.deepStrictEqual(snapshotLedger(), before);
  });
  await t('NC-19', '목록·홈 조회는 어떤 쓰기도 하지 않는다', async () => {
    seedFull();
    const before = snapshotLedger();
    await listIds(); await homeCount();
    assert.strictEqual(WRITES.length, 0);
    assert.deepStrictEqual(snapshotLedger(), before);
  });

  _log('\n[NC-F] 소스');
  await t('NC-20', '판정 한 벌: 목록·홈은 srvNeedsContractIssue, 발행은 PREAUTH + 트랜잭션', async () => {
    if (!fs.existsSync(SRC)) { _log('       (src 없음 — 건너뜀)'); return; }
    const src = fs.readFileSync(SRC, 'utf8');
    const n = (re) => (src.match(re) || []).length;
    assert.strictEqual(n(/srvContractBlockedByAttendance\(/g), 1 + 3, '정의 1 + 사용 3');
    const a = src.indexOf('export const callableFinalizeEmployerSignature = onCall(');
    const b = src.indexOf('\nexport const ', a + 10);
    const body = src.slice(a, b);
    const tx = body.indexOf('await db.runTransaction');
    const g2 = body.indexOf('srvContractBlockedByAttendance(gid, gdata, tx)');
    const set = body.indexOf('tx.set(contractRef, data)');
    assert.ok(body.indexOf('srvContractBlockedByAttendance(gid, gdata))') < tx && tx < g2 && g2 < set);
  });

  _log(`\n${pass} passed, ${fails.length} failed`);
  if (fails.length) { _log(fails.join('\n')); process.exit(1); }
  process.exit(0);
})();
