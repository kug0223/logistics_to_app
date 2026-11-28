// [CHECKIN-END-GUARD] callableCheckIn — 근무가 끝났으면 서버가 출근을 만들지 않는다.
//
//   실행:  cd functions && npm run build && node test/checkin_end_guard.test.js
//
//   DEV 실측(10-20): 10:00~11:00 근무(Zdn7, 근태 없음)에 14:58 에도 근로자 출근이
//   열려 있었다(배포 rev 00073 — 시작 하한 earlyWindow 만 있고 종료 상한 없음).
//   화면 버튼을 숨긴 것(앱 패치)은 서버 결함을 고친 것이 아니다.
//
//   이 테스트는 **빌드된 lib/index.js 의 실제 핸들러 전체**를 실행한다.
//   firebase-functions / firebase-admin 을 require 단계에서 가짜로 바꾸고,
//   메모리 Firestore 로 모든 읽기·쓰기를 기록한다. 시계는 고정한다.
//   거절 사례는 "근태 문서 0건 + 어떤 쓰기도 0건" 을 직접 센다
//   (출근 카운터는 근태 생성 트리거가 움직이므로, 문서가 없으면 트리거도 없다).
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

let STORE = new Map(); // "col/id" → data
let WRITES = [];      // {op, path, data}

function snapOf(p) {
  const data = STORE.get(p);
  const id = p.split('/').pop();
  return {
    id, exists: data !== undefined, ref: refOf(p),
    data: () => (data === undefined ? undefined : {...data}),
    get: (f) => (data === undefined ? undefined : data[f]),
  };
}
function refOf(p) {
  return {
    path: p, id: p.split('/').pop(),
    get: async () => snapOf(p),
    set: async (d) => { WRITES.push({op: 'set', path: p, data: d}); STORE.set(p, d); },
    update: async (d) => { WRITES.push({op: 'update', path: p, data: d}); },
    delete: async () => { WRITES.push({op: 'delete', path: p}); STORE.delete(p); },
    collection: (c) => colOf(`${p}/${c}`),
  };
}
function colOf(c) {
  const filters = [];
  const q = {
    doc: (id) => refOf(`${c}/${id}`),
    where: (f, op, v) => { filters.push([f, op, v]); return q; },
    limit: () => q,
    orderBy: () => q,
    get: async () => {
      const docs = [];
      for (const [p, d] of STORE) {
        if (!p.startsWith(c + '/') || p.slice(c.length + 1).includes('/')) continue;
        const ok = filters.every(([f, op, v]) =>
          op === '==' ? d[f] === v :
          op === 'array-contains' ? Array.isArray(d[f]) && d[f].includes(v) :
          (() => { throw new Error('unsupported op ' + op); })());
        if (ok) docs.push(snapOf(p));
      }
      return {empty: docs.length === 0, size: docs.length, docs};
    },
  };
  return q;
}
const fakeDb = {
  collection: (c) => colOf(c),
  runTransaction: async (fn) => {
    const tx = {
      get: async (r) => (r.get ? r.get() : r),
      set: (r, d) => { WRITES.push({op: 'tx.set', path: r.path, data: d}); STORE.set(r.path, d); },
      update: (r, d) => { WRITES.push({op: 'tx.update', path: r.path, data: d}); },
      delete: (r) => { WRITES.push({op: 'tx.delete', path: r.path}); },
    };
    return fn(tx);
  },
  batch: () => ({set() {}, update() {}, delete() {}, commit: async () => {}}),
};

// ── 가짜 firebase-functions / firebase-admin ────────────────────────────
class HttpsError extends Error {
  constructor(code, message, details) { super(message); this.code = code; this.details = details; }
}
const HANDLERS = {};
const anyFn = new Proxy(function() {}, {
  get: () => anyFn, apply: () => ({}),
});
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
  initializeApp: () => ({}),
  apps: [],
  app: () => ({}),
  firestore: Object.assign(() => fakeDb, {Timestamp: FakeTimestamp, FieldValue}),
  auth: () => anyFn,
  storage: () => anyFn,
  messaging: () => anyFn,
  credential: anyFn,
};
const origLoad = Module._load;
Module._load = function(request, parent, isMain) {
  if (request.startsWith('firebase-functions')) return functionsModule();
  if (request === 'firebase-admin/app') return {initializeApp: () => ({}), getApps: () => []};
  if (request === 'firebase-admin/firestore') {
    return {getFirestore: () => fakeDb, Timestamp: FakeTimestamp, FieldValue,
      Firestore: function() {}};
  }
  if (request === 'firebase-admin' || request.startsWith('firebase-admin/')) return adminModule;
  return origLoad.apply(this, arguments);
};

// ── 시계 고정 ────────────────────────────────────────────────────────────
const RealDate = Date;
let NOW = 0;
class FakeDate extends RealDate {
  constructor(...a) { if (a.length === 0) super(NOW); else super(...a); }
  static now() { return NOW; }
}

// 빌드 위치를 바꿔 같은 사례를 다른 배포물(예: 격리된 00073 기준 빌드)에 돌린다.
const FN_DIR = process.env.CIG_FUNCTIONS_DIR || path.join(__dirname, '..');
const LIB = path.join(FN_DIR, 'lib', 'index.js');
const SRC = path.join(FN_DIR, 'src', 'index.ts');
console.log(`[target] ${FN_DIR}`);
const lib = require(LIB);
const handler = lib.callableCheckIn && lib.callableCheckIn.__handler;
assert.ok(handler, 'callableCheckIn 핸들러를 찾지 못했다');

// ── 픽스처 ───────────────────────────────────────────────────────────────
const KST = 9 * 3600e3;
const kstMid = (y, m, d) => RealDate.UTC(y, m - 1, d) - KST;
const at = (y, m, d, hh, mm, ss = 0, ms = 0) =>
  kstMid(y, m, d) + ((hh * 60 + mm) * 60 + ss) * 1000 + ms;
const D20 = kstMid(2026, 10, 20);
const UID = 'xZahWORKER';
const BIZ = 'qa_biz';
const LAT = 37.0;
const LNG = 127.0;

// [SERVER-MERGE-1 §2차 2026-11-26] 이 시험(10-20)은 출근 계약 관문(CONTRACT-BEFORE-CHECKIN, 10-25 · 대표 11-26 확정 정책)보다 먼저
//   쓰였다. 관문은 '그 지원서·그 근로자·그 사업장의 양측 서명 완료 계약'을 요구하므로, 종료 상한을 보려는 셀은 기본으로
//   **시각 정보 없는 동의 계약 1건**(slots·snapshot 없음 → 종료 시각 판정에 기여 0)을 함께 심는다. 관문 자체는 CE-27 이 본다.
function seed({app, contracts = [], attendance = null, consent = true}) {
  STORE = new Map();
  WRITES = [];
  STORE.set(`users/${UID}`, {accountStatus: 'active', role: 'USER'});
  STORE.set(`businesses/${BIZ}`, {
    name: 'QA 사업장', attendanceType: 'gps', latitude: LAT, longitude: LNG, gpsRadius: 100,
  });
  STORE.set(`applications/${app.id}`, {
    uid: UID, businessId: BIZ, status: 'CONFIRMED', type: 'short',
    selectedWorkType: 'QA 분류', wage: 12000, wageType: 'hourly',
    workDate: FakeTimestamp.fromMillis(app.workDateMs ?? D20),
    ...app.fields,
  });
  contracts.forEach((c, i) => STORE.set(`employment_contracts/c${i}`, c));
  if (consent) {
    STORE.set('employment_contracts/consent', {status: 'completed', workerId: UID, businessId: BIZ,
      applicationId: app.id, applicationIds: [app.id], slots: [],
      employerSignedAt: FakeTimestamp.fromMillis(D20 - 86400000), workerSignedAt: FakeTimestamp.fromMillis(D20 - 86400000)});
  }
  if (attendance) STORE.set(`attendance/${app.id}_${attendance.day}`, attendance.data);
}

async function call(appId, nowMs, {workDateMs = D20, extra = {}} = {}) {
  NOW = nowMs;
  global.Date = FakeDate;
  try {
    const out = await handler({
      auth: {uid: UID},
      data: {
        applicationId: appId, businessId: BIZ, businessName: 'QA 사업장',
        workDateMs, workType: 'QA 분류', latitude: LAT, longitude: LNG, method: 'gps',
        ...extra,
      },
    });
    return {ok: true, out};
  } catch (e) {
    return {ok: false, code: e.code, reason: e.details && (e.details.code || e.details.reason),
      message: e.message};
  } finally {
    global.Date = RealDate;
  }
}

const attDocs = () => [...STORE.keys()].filter((k) => k.startsWith('attendance/'));
const writesTo = (prefix) => WRITES.filter((w) => w.path.startsWith(prefix));

// ── 실행 ─────────────────────────────────────────────────────────────────
let pass = 0;
const fails = [];
async function t(id, name, fn) {
  try { await fn(); pass++; console.log(`  ok   ${id} ${name}`); } catch (e) {
    fails.push(`${id}: ${e.message.split('\n')[0]}`);
    console.log(`  FAIL ${id} ${name} — ${e.message.split('\n')[0]}`);
  }
}
function expectRejected(r, reason) {
  assert.strictEqual(r.ok, false, '거절돼야 한다');
  assert.strictEqual(r.code, 'failed-precondition', r.message);
  if (reason) assert.strictEqual(r.reason, reason, r.message);
  assert.strictEqual(WRITES.length, 0, `쓰기가 있었다: ${JSON.stringify(WRITES.map((w) => w.op + ' ' + w.path))}`);
}

const RUBE = {id: 'RUBE', fields: {startTime: '13:00', endTime: '14:00'}};
const ZDN7 = {id: 'Zdn7', fields: {startTime: '10:00', endTime: '11:00'}};

(async () => {
  console.log('[CE-A] 정상 출근은 그대로');
  await t('CE-1', '[DEV 재현 RUBE] 시작 24분 전(12:36) — 출근, 근태 1건, 보정 출근 13:00', async () => {
    seed({app: RUBE});
    const r = await call('RUBE', at(2026, 10, 20, 12, 36, 12));
    assert.ok(r.ok, r.message);
    assert.deepStrictEqual(attDocs(), ['attendance/RUBE_20261020']);
    const d = STORE.get('attendance/RUBE_20261020');
    assert.strictEqual(d.checkIn.toMillis(), at(2026, 10, 20, 13, 0));
    assert.strictEqual(d.originalCheckIn.toMillis(), at(2026, 10, 20, 12, 36, 12));
    assert.strictEqual(writesTo('attendance/').length, 1);
  });
  await t('CE-2', '종료 직전(13:59:59.999) — 출근', async () => {
    seed({app: RUBE});
    const r = await call('RUBE', at(2026, 10, 20, 13, 59, 59, 999));
    assert.ok(r.ok, r.message);
    assert.strictEqual(attDocs().length, 1);
  });

  console.log('\n[CE-B] 종료 정각·직후는 거절, 쓰기 0');
  await t('CE-3', '종료 정각(14:00:00.000) — SHIFT_ENDED', async () => {
    seed({app: RUBE});
    expectRejected(await call('RUBE', at(2026, 10, 20, 14, 0)), 'SHIFT_ENDED');
    assert.strictEqual(attDocs().length, 0);
  });
  await t('CE-4', '종료 1ms 뒤 — SHIFT_ENDED', async () => {
    seed({app: RUBE});
    expectRejected(await call('RUBE', at(2026, 10, 20, 14, 0, 0, 1)), 'SHIFT_ENDED');
  });
  await t('CE-5', '[DEV 재현 Zdn7] 10:00~11:00 근무에 14:58 — SHIFT_ENDED, 메시지에 종료 시각', async () => {
    seed({app: ZDN7});
    const r = await call('Zdn7', at(2026, 10, 20, 14, 58));
    expectRejected(r, 'SHIFT_ENDED');
    assert.ok(r.message.includes('11:00'), r.message);
  });
  await t('CE-6', '앱이 보낸 종료·시작 시간은 판정에 쓰지 않는다', async () => {
    seed({app: ZDN7});
    const r = await call('Zdn7', at(2026, 10, 20, 14, 58),
        {extra: {scheduledStartTime: '14:00', scheduledEndTime: '23:59', endTime: '23:59'}});
    expectRejected(r, 'SHIFT_ENDED');
  });

  console.log('\n[CE-C] 자정 넘김(23:00~06:00, 근무일 10-20)');
  const NIGHT = {id: 'NITE', fields: {startTime: '23:00', endTime: '06:00'}};
  await t('CE-7', '다음 날 05:59 — 출근(종료 전)', async () => {
    seed({app: NIGHT});
    const r = await call('NITE', at(2026, 10, 21, 5, 59));
    assert.ok(r.ok, r.message);
    assert.deepStrictEqual(attDocs(), ['attendance/NITE_20261020']);
  });
  await t('CE-8', '다음 날 06:00 — SHIFT_ENDED', async () => {
    seed({app: NIGHT});
    expectRejected(await call('NITE', at(2026, 10, 21, 6, 0)), 'SHIFT_ENDED');
  });
  await t('CE-9', '당일 22:40 — 시작 20분 전 정상 출근(종료를 같은 날 06:00 으로 오판하지 않는다)', async () => {
    seed({app: NIGHT});
    const r = await call('NITE', at(2026, 10, 20, 22, 40));
    assert.ok(r.ok, r.message);
  });

  console.log('\n[CE-C2] 시작 = 종료 — 유효하지 않은 시간(퇴근 계산과 해석을 맞춘다)');
  const SAME = {id: 'SAME', fields: {startTime: '13:00', endTime: '13:00'}};
  await t('CE-23', '13:00~13:00, 시작 15분 전 — SHIFT_TIME_INVALID, 쓰기 0', async () => {
    seed({app: SAME});
    const r = await call('SAME', at(2026, 10, 20, 12, 45));
    expectRejected(r, 'SHIFT_TIME_INVALID');
    assert.ok(r.message.includes('시작·종료 시간이 같아'), r.message);
    assert.strictEqual(attDocs().length, 0);
  });
  await t('CE-24', '13:00~13:00, 시작 10분 뒤(24시간 근무로 보지 않는다) — SHIFT_TIME_INVALID', async () => {
    seed({app: SAME});
    expectRejected(await call('SAME', at(2026, 10, 20, 13, 10)), 'SHIFT_TIME_INVALID');
  });
  await t('CE-25', '완료 계약 slot 의 종료가 시작과 같음 — SHIFT_TIME_INVALID', async () => {
    seed({app: {id: 'NOEN', fields: {startTime: '13:00'}}, contracts: [{status: 'completed',
      applicationId: 'NOEN', applicationIds: ['NOEN'],
      slots: [{applicationId: 'NOEN', startTime: '13:00', endTime: '13:00'}]}]});
    expectRejected(await call('NOEN', at(2026, 10, 20, 12, 50)), 'SHIFT_TIME_INVALID');
  });
  await t('CE-26', '소스: 퇴근은 종료 < 시작일 때만 +1일, 가드는 같음을 거절하고 < 일 때만 +1일', async () => {
    const src = fs.readFileSync(SRC, 'utf8');
    const a = src.indexOf('export const callableCheckOut = onCall(');
    const co = src.slice(a, src.indexOf('\nexport const ', a + 10));
    assert.ok(/cEndMs < cStartMs/.test(co) && !/cEndMs <= cStartMs/.test(co), '퇴근 자정 규칙');
    const h = src.indexOf('async function srvCommittedShiftEndMs(');
    const hb = src.slice(h, src.indexOf('\n}\n', h));
    assert.ok(hb.includes('if (endMin === startMin) return {ok: false, reason: "SHIFT_TIME_INVALID"};'));
    assert.ok(hb.includes('if (endMin < startMin) endMin += 1440;'));
    assert.ok(!hb.includes('endMin <= startMin'));
  });

  await t('CE-27', '[계약 관문] 동의 계약이 없으면 종료 판정 전에 CONTRACT_MISSING 거절 · 쓰기 0', async () => {
    seed({app: RUBE, consent: false});
    expectRejected(await call('RUBE', at(2026, 10, 20, 12, 36, 12)), 'CONTRACT_MISSING');
  });

  console.log('\n[CE-D] 종료 시각 출처');

  const NOEND = {id: 'NOEN', fields: {startTime: '13:00'}};
  const doneContract = (extra) => ({status: 'completed', applicationId: 'NOEN',
    applicationIds: ['NOEN'], snapshot: {startTime: '13:00', endTime: '14:00'},
    slots: [{applicationId: 'NOEN', startTime: '13:00', endTime: '14:00'}], ...extra});
  await t('CE-10', '지원서 endTime 없음 + 완료 계약 slot 14:00 — 13:30 출근', async () => {
    seed({app: NOEND, contracts: [doneContract()]});
    const r = await call('NOEN', at(2026, 10, 20, 13, 30));
    assert.ok(r.ok, r.message);
  });
  await t('CE-11', '지원서 endTime 없음 + 완료 계약 — 14:00 정각 거절', async () => {
    seed({app: NOEND, contracts: [doneContract()]});
    expectRejected(await call('NOEN', at(2026, 10, 20, 14, 0)), 'SHIFT_ENDED');
  });
  await t('CE-12', '계약 slot 없음 + 이 지원서 하나만 담은 완료 계약의 snapshot.endTime', async () => {
    seed({app: NOEND, contracts: [doneContract({slots: []})]});
    assert.ok((await call('NOEN', at(2026, 10, 20, 13, 30))).ok);
    seed({app: NOEND, contracts: [doneContract({slots: []})]});
    expectRejected(await call('NOEN', at(2026, 10, 20, 14, 0)), 'SHIFT_ENDED');
  });
  await t('CE-13', '완료가 아닌 계약(pending_worker)의 시각은 쓰지 않는다 — SHIFT_END_UNKNOWN', async () => {
    seed({app: NOEND, contracts: [doneContract({status: 'pending_worker'})]});
    expectRejected(await call('NOEN', at(2026, 10, 20, 13, 30)), 'SHIFT_END_UNKNOWN');
  });
  await t('CE-14', '묶음 계약에 이 지원서 slot 이 없으면 snapshot 을 쓰지 않는다 — UNKNOWN', async () => {
    seed({app: NOEND, contracts: [doneContract({applicationIds: ['NOEN', 'OTHR'],
      slots: [{applicationId: 'OTHR', endTime: '18:00'}]})]});
    expectRejected(await call('NOEN', at(2026, 10, 20, 13, 30)), 'SHIFT_END_UNKNOWN');
  });
  await t('CE-15', '완료 계약 두 개의 종료가 서로 다르면 모른다 — UNKNOWN', async () => {
    seed({app: NOEND, contracts: [doneContract(),
      doneContract({slots: [{applicationId: 'NOEN', endTime: '16:00'}]})]});
    expectRejected(await call('NOEN', at(2026, 10, 20, 13, 30)), 'SHIFT_END_UNKNOWN');
  });
  await t('CE-16', '지원서·계약 모두 종료 없음 — 앱 값으로 대체하지 않고 거절', async () => {
    seed({app: NOEND});
    const r = await call('NOEN', at(2026, 10, 20, 13, 30), {extra: {scheduledEndTime: '23:00'}});
    expectRejected(r, 'SHIFT_END_UNKNOWN');
    assert.strictEqual(attDocs().length, 0);
  });

  console.log('\n[CE-E] 기존 근태가 있으면 기존 판정이 먼저(메시지 불변)');
  await t('CE-17', '이미 출근한 근무를 종료 뒤 다시 출근 — already-exists(ALREADY_CHECKED_IN), 쓰기 0', async () => {
    seed({app: RUBE, attendance: {day: '20261020', data: {
      applicationId: 'RUBE', userId: UID, status: 'present',
      checkIn: FakeTimestamp.fromMillis(at(2026, 10, 20, 13, 0)),
      checkOut: FakeTimestamp.fromMillis(at(2026, 10, 20, 14, 0))}}});
    const r = await call('RUBE', at(2026, 10, 20, 14, 30));
    assert.strictEqual(r.ok, false);
    assert.strictEqual(r.code, 'already-exists', r.message);
    assert.strictEqual(r.reason, 'ALREADY_CHECKED_IN');
    assert.strictEqual(WRITES.length, 0);
  });
  await t('CE-18', '노쇼 근태가 있는 근무 — 기존 노쇼 차단 그대로, 쓰기 0', async () => {
    seed({app: ZDN7, attendance: {day: '20261020', data: {
      applicationId: 'Zdn7', userId: UID, status: 'NO_SHOW'}}});
    const r = await call('Zdn7', at(2026, 10, 20, 10, 30));
    assert.strictEqual(r.ok, false);
    assert.notStrictEqual(r.reason, 'SHIFT_ENDED');
    assert.strictEqual(WRITES.length, 0);
  });

  console.log('\n[CE-F] 기존 하한·장기 근무');
  await t('CE-19', '시작 31분 전(12:29) — 기존 하한 거절 그대로(종료 판정이 끼어들지 않음)', async () => {
    seed({app: RUBE});
    const r = await call('RUBE', at(2026, 10, 20, 12, 29));
    assert.strictEqual(r.ok, false);
    assert.ok(r.message.includes('아직 출근할 수 있는 시간이 아닙니다'), r.message);
    assert.strictEqual(WRITES.length, 0);
  });
  const LONG = {id: 'LONG', fields: {type: 'long_term', startTime: '09:00', endTime: '18:00',
    workDays: ['월', '화', '수', '목', '금', '토', '일'],
    desiredStartDate: FakeTimestamp.fromMillis(kstMid(2026, 10, 1)),
    workEndDate: FakeTimestamp.fromMillis(kstMid(2026, 12, 31))}};
  await t('CE-20', '장기 근무 — 근무 중 출근, 종료 뒤 거절', async () => {
    seed({app: LONG});
    { const r0 = await call("LONG", at(2026, 10, 20, 9, 10)); assert.ok(r0.ok, r0.message + " " + r0.reason); }
    seed({app: LONG});
    expectRejected(await call('LONG', at(2026, 10, 20, 18, 0)), 'SHIFT_ENDED');
  });

  console.log('\n[CE-G] 퇴근 경로는 건드리지 않았다(소스)');
  await t('CE-21', 'callableCheckOut 본문에 종료 상한 판정이 없다', async () => {
    const src = fs.readFileSync(SRC, 'utf8');
    const a = src.indexOf('export const callableCheckOut = onCall(');
    const b = src.indexOf('\nexport const ', a + 10);
    const body = src.slice(a, b);
    assert.ok(a > 0);
    assert.ok(!body.includes('srvCommittedShiftEndMs'));
    assert.ok(!body.includes('SHIFT_ENDED'));
  });
  await t('CE-22', '판정은 tx.set 보다 앞, 기존 근태 판정보다 뒤', async () => {
    const src = fs.readFileSync(SRC, 'utf8');
    const a = src.indexOf('export const callableCheckIn = onCall(');
    const b = src.indexOf('export const callableCheckOut = onCall(');
    const body = src.slice(a, b);
    const block = body.indexOf('srvResolveCheckInBlock(snap.data()!)');
    const guard = body.indexOf('code: "SHIFT_ENDED"');
    const write = body.indexOf('tx.set(ref,');
    assert.ok(block > 0 && guard > block && write > guard, `${block} ${guard} ${write}`);
  });

  console.log(`\n${pass} passed, ${fails.length} failed`);
  if (fails.length) { console.log(fails.join('\n')); process.exit(1); }
})().catch((e) => { console.error(e); process.exit(2); });
