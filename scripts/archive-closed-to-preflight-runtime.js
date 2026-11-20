/**
 * [ARCHIVE-CLOSED-TO-PREFLIGHT] 마감 공고의 대기·계약 대기 — 사전 조회 ↔ 종료 연쇄 일치,
 *   실근무 계약 대기 사전 해결, 종료 후 단기 출근, 사업장 문서 없는 서명.
 *
 *   같은 seed 를 BEFORE / AFTER 번들에 각각 올린다(번들마다 initializeApp → 자식 프로세스 하나씩).
 *   callable·트리거는 번들의 `.run` 으로 직접 부른다(에뮬레이터 전용, demo-alfit-r7).
 *     BEFORE=<lib/index.js> AFTER=<lib/index.js> node scripts/archive-closed-to-preflight-runtime.js
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
const LABEL = process.env.LABEL;
const fn = LABEL ? require(process.env[LABEL]) : null;
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
const {Timestamp} = admin.firestore;

const RUN = 'cp' + Date.now().toString(36);
const K = 9 * 3600e3; const NOW = Date.now(); const DAY = 86400e3;
const kstMidnight = (ms) => { const d = new Date(ms + K); return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()) - K; };
const TODAY = kstMidnight(NOW);
const ymd = (ms) => { const d = new Date(ms + K); return `${d.getUTCFullYear()}${String(d.getUTCMonth() + 1).padStart(2, '0')}${String(d.getUTCDate()).padStart(2, '0')}`; };
let seq = 0;
const uid = (p) => `${p}-${RUN}-${++seq}`;
const read = async (p) => (await db.doc(p).get()).data();
const B64 = Buffer.from('x').toString('base64');
async function call(name, who, data) {
  try { return {ok: await fn[name].run({auth: {uid: who, token: {}}, rawRequest: {headers: {}}, data})}; } catch (e) {
    return {err: (e.details && (e.details.code || e.details.reason)) || `${e.code || ''}:${String(e.message).slice(0, 40)}`, details: e.details};
  }
}
const RULES = {earlyWindow: 30, earlyArrivalUnit: 10, lateGrace: 5, lateUnit: 10, lateWindow: 600, overtimeUnit: 10, earlyLeaveUnit: 10};

async function world() {
  const b = uid('b'); const o = uid('o');
  await db.doc(`users/${o}`).set({role: 'BUSINESS_ADMIN', name: 'owner', businessId: b});
  await db.doc(`businesses/${b}`).set({isApproved: true, ownerId: o, adminIds: [o], name: 'biz', deactivatedAt: null, attendanceRules: RULES,
    latitude: 37.0, longitude: 127.0, gpsRadius: 100});
  const mkTo = async (status) => {
    const t = uid('t');
    await db.doc(`tos/${t}`).set({businessId: b, status, title: 't', type: 'flex', isPublished: true, closedReason: status === 'CLOSED' ? 'MANUAL' : null});
    await db.doc(`tos/${t}/slots/s1`).set({status: status === 'CLOSED' ? 'closed' : 'open', workDetails: [{id: 'wd1', wdId: 'wd1', workType: 'QA', requiredCount: 5}],
      date: Timestamp.fromMillis(TODAY)}); // 출근 셀(B)은 오늘 근무 — 다른 셀은 슬롯 날짜를 읽지 않는다
    return t;
  };
  return {b, o, open: await mkTo('ACTIVE'), closed: await mkTo('CLOSED')};
}
async function app(x, to, status, dayOffset, o = {}) {
  const id = uid('a'); const w = o.uid || uid('w');
  await db.doc(`users/${w}`).set({role: 'USER', name: 'worker', accountStatus: 'active'}, {merge: true});
  await db.doc(`applications/${id}`).set(Object.assign({uid: w, businessId: x.b, toId: to, slotId: 's1', wdId: 'wd1', selectedWorkType: 'QA',
    status, type: 'short', workDate: Timestamp.fromMillis(TODAY + dayOffset * DAY), startTime: '09:00', endTime: '18:00',
    businessName: 'biz', toTitle: 't', appliedAt: Timestamp.now()}, o));
  return {id, w};
}
async function worked(x, a, dayOffset) {
  await db.doc(`attendance/${a.id}_${ymd(TODAY + dayOffset * DAY)}`).set({applicationId: a.id, userId: a.w, businessId: x.b,
    workDate: Timestamp.fromMillis(TODAY + dayOffset * DAY), checkIn: Timestamp.fromMillis(TODAY + dayOffset * DAY + 9 * 3600e3),
    checkOut: Timestamp.fromMillis(TODAY + dayOffset * DAY + 18 * 3600e3), status: 'present', wageStatus: 'pending'});
}
async function contract(x, a, status = 'pending_worker') {
  const id = uid('c');
  await db.doc(`employment_contracts/${id}`).set({businessId: x.b, workerId: a.w, applicationId: a.id, applicationIds: [a.id], status,
    snapshot: {workerName: 'w'}, employerSignatureUrl: status === 'pending_worker' ? 'https://x/e.png' : null});
  return id;
}
/** 사전 조회 → 실행(expected) → 실제 연쇄(트리거 핸들러). */
async function archive(x) {
  const pv = await call('callableArchiveOwnBusiness', x.o, {businessId: x.b, preview: true});
  const preview = pv.ok && pv.ok.preview;
  const before = await read(`businesses/${x.b}`);
  const r = await call('callableArchiveOwnBusiness', x.o, {businessId: x.b, expected: preview});
  const after = await read(`businesses/${x.b}`);
  if (r.ok && after.deactivatedAt) {
    await fn.onBusinessDeactivated.run({params: {businessId: x.b},
      data: {before: {exists: true, data: () => before}, after: {exists: true, data: () => after}}});
  }
  return {preview, run: r.err || 'OK', closed: after.deactivatedAt != null};
}
const st = async (id) => { const d = await read(`applications/${id}`); return `${d.status}${d.cancelReason ? '/' + d.cancelReason : ''}`; };
const cst = async (id) => (await read(`employment_contracts/${id}`)).status;
const notifs = async (w) => (await db.collection(`users/${w}/notifications`).get()).size;

const CELLS = {
  // ── 마감 공고의 시작 전 계약 대기
  A1: async () => {
    const x = await world(); const a = await app(x, x.closed, 'CONTRACT_PENDING', 2); const c = await contract(x, a);
    const r = await archive(x);
    return {pv: r.preview && `시작전취소 ${r.preview.futureConfirmed} · 계약무효 ${r.preview.contractsVoided} · 계약유지 ${r.preview.contractsKept}`,
      out: `실행 ${r.run} · 지원서 ${await st(a.id)} · 계약 ${await cst(c)} · 알림 ${await notifs(a.w)}`};
  },
  // ── 마감 공고의 대기 지원
  A2: async () => {
    const x = await world(); const a = await app(x, x.closed, 'PENDING', 2);
    const r = await archive(x);
    return {pv: r.preview && `대기마감 ${r.preview.pendingApplications}`, out: `실행 ${r.run} · 지원서 ${await st(a.id)} · 알림 ${await notifs(a.w)}`};
  },
  // ── 실근무가 있는 계약 대기(마감 공고) — 사전 해결 필수
  A3: async () => {
    const x = await world(); const a = await app(x, x.closed, 'CONTRACT_PENDING', -1); await worked(x, a, -1);
    const r = await archive(x);
    return {pv: r.preview && `실근무계약대기 ${r.preview.contractPendingWorked} · canArchive ${r.preview.canArchive}`,
      out: `실행 ${r.run} · 사업장 종료 ${r.closed} · 지원서 ${await st(a.id)} · 알림 ${await notifs(a.w)}`};
  },
  // ── 게이트 없는 경로(슈퍼관리자 deactivate 등)로 연쇄만 돌아도 실근무 계약 대기는 건드리지 않는다
  A4: async () => {
    const x = await world(); const a = await app(x, x.closed, 'CONTRACT_PENDING', 2); await worked(x, a, 0); // 시작 전 날짜인데 출근 기록(조기 출근)
    const before = await read(`businesses/${x.b}`);
    await db.doc(`businesses/${x.b}`).update({deactivatedAt: Timestamp.now(), isApproved: false});
    const after = await read(`businesses/${x.b}`);
    await fn.onBusinessDeactivated.run({params: {businessId: x.b}, data: {before: {exists: true, data: () => before}, after: {exists: true, data: () => after}}});
    return {pv: '-', out: `지원서 ${await st(a.id)} · 알림 ${await notifs(a.w)}`};
  },
  // ── 사전 조회 ↔ 실제 처리 건수 일치(혼합 원장)
  A5: async () => {
    const x = await world();
    const P = [await app(x, x.open, 'PENDING', 2), await app(x, x.closed, 'PENDING', 3), await app(x, x.closed, 'PENDING', -2)];
    const F = [await app(x, x.open, 'CONTRACT_PENDING', 2), await app(x, x.open, 'CONFIRMED', 3), await app(x, x.closed, 'CONTRACT_PENDING', 4),
      await app(x, x.closed, 'CONFIRMED', 5)];
    const Kp = [await app(x, x.closed, 'CONFIRMED', -1), await app(x, x.closed, 'CONTRACT_PENDING', -2), await app(x, x.open, 'CONFIRMED', -3)];
    const cF = [await contract(x, F[0]), await contract(x, F[2])]; const cK = [await contract(x, Kp[0]), await contract(x, Kp[1])];
    const r = await archive(x);
    const s = async (arr) => Promise.all(arr.map((a) => st(a.id)));
    const ps = await s(P); const fs2 = await s(F); const ks = await s(Kp);
    const rejected = ps.filter((v) => v === 'REJECTED/BUSINESS_DEACTIVATED').length;
    const canceled = fs2.filter((v) => v === 'CANCELED/BUSINESS_DEACTIVATED').length;
    const kept = ks.filter((v) => v === 'CONFIRMED' || v === 'CONTRACT_PENDING').length;
    const voided = (await Promise.all(cF.map(cst))).filter((v) => v === 'voided').length;
    const ckept = (await Promise.all(cK.map(cst))).filter((v) => v !== 'voided').length;
    const p = r.preview || {};
    const pairs = [['대기마감', p.pendingApplications, rejected], ['시작전취소', p.futureConfirmed, canceled], ['보존', p.keptStarted, kept],
      ['계약무효', p.contractsVoided, voided], ['계약유지', p.contractsKept, ckept]];
    const same = pairs.every(([, e, a]) => e === a);
    return {pv: pairs.map(([k, e]) => `${k} ${e}`).join(' · '), out: `실행 ${r.run} · 실제 ${pairs.map(([k, , a]) => `${k} ${a}`).join(' · ')} · 일치 ${same}`};
  },
  // ── 종료 후 단기 출근 — 관리자 일괄 출근(종료 시각 이후 출근 시각)
  B1: async () => {
    const x = await world(); const a = await app(x, x.closed, 'CONFIRMED', 0, {startTime: '00:00'});
    await db.doc(`businesses/${x.b}`).update({deactivatedAt: Timestamp.fromMillis(NOW - 30 * 60e3), isApproved: false});
    const r = await call('callableBatchCheckIn', x.o, {businessId: x.b, entries: [{applicationId: a.id, workDateMs: TODAY, userId: a.w,
      businessName: 'biz', workType: 'QA', status: 'present', checkInMs: NOW - 60e3}]});
    const att = await read(`attendance/${a.id}_${ymd(TODAY)}`);
    return {pv: '-', out: `${r.err || 'OK'} · 실패 ${JSON.stringify((r.ok && r.ok.failures) || [])} · 출근기록 ${att && att.checkIn ? '생성' : '없음'}`};
  },
  // ── 종료 당일, 종료 전에 시작한 근무의 기록(출근 시각 < 종료 시각) — 둘 다 허용
  B2: async () => {
    // 근무일은 종료 시각이 속한 KST 날짜 — 자정 직후에 돌려도 "종료일 당일, 종료 전 출근" 모양이 유지된다.
    const closedAt = NOW - 30 * 60e3; const day0 = kstMidnight(closedAt);
    const ci = Math.max(day0 + 60e3, closedAt - 10 * 60e3);
    const x = await world(); const a = await app(x, x.closed, 'CONFIRMED', 0, {startTime: '00:00', workDate: Timestamp.fromMillis(day0)});
    await db.doc(`tos/${x.closed}/slots/s1`).update({date: Timestamp.fromMillis(day0)});
    await db.doc(`businesses/${x.b}`).update({deactivatedAt: Timestamp.fromMillis(closedAt), isApproved: false});
    const r = await call('callableBatchCheckIn', x.o, {businessId: x.b, entries: [{applicationId: a.id, workDateMs: day0, userId: a.w,
      businessName: 'biz', workType: 'QA', status: 'present', checkInMs: ci}]});
    const att = await read(`attendance/${a.id}_${ymd(day0)}`);
    return {pv: '-', out: `${r.err || 'OK'} · 출근기록 ${att && att.checkIn ? '생성' : '없음'}`};
  },
  // ── 종료 후 단기 출근 — 근로자 본인
  B3: async () => {
    const x = await world(); const a = await app(x, x.closed, 'CONTRACT_PENDING', 0, {startTime: '00:00', type: 'short'});
    await db.doc(`businesses/${x.b}`).update({deactivatedAt: Timestamp.fromMillis(NOW - 30 * 60e3), isApproved: false});
    const r = await call('callableCheckIn', a.w, {applicationId: a.id, businessId: x.b, businessName: 'biz', workDateMs: TODAY, workType: 'QA', method: 'gps', latitude: 37.0, longitude: 127.0});
    const att = await read(`attendance/${a.id}_${ymd(TODAY)}`);
    return {pv: '-', out: `${r.err || 'OK'} · 출근기록 ${att && att.checkIn ? '생성' : '없음'}`};
  },
  // ── 사업장 문서가 없는 보존 확정의 근로자 서명
  C1: async () => {
    const x = await world(); const a = await app(x, x.closed, 'CONFIRMED', -1); const c = await contract(x, a);
    await db.doc(`businesses/${x.b}`).delete();
    const r = await call('callableFinalizeWorkerSignature', a.w, {contractId: c, signatureBase64: B64, pdfBase64: B64});
    return {pv: '-', out: `${r.err || 'OK'} · 계약 ${await cst(c)} · 지원서 ${await st(a.id)}`};
  },
  // ── 대조: 종료 사업장의 보존 확정 근로자 서명은 그대로 허용
  C2: async () => {
    const x = await world(); const a = await app(x, x.closed, 'CONFIRMED', -1); const c = await contract(x, a);
    await db.doc(`businesses/${x.b}`).update({deactivatedAt: Timestamp.now(), isApproved: false});
    const r = await call('callableFinalizeWorkerSignature', a.w, {contractId: c, signatureBase64: B64, pdfBase64: B64});
    return {pv: '-', out: `${r.err || 'OK'} · 계약 ${await cst(c)} · 지원서 ${await st(a.id)}`};
  },
  // ── 대조: 종료 사업장 계약 대기의 근로자 서명 거절 문구(이유별)
  C3: async () => {
    const x = await world(); const a = await app(x, x.closed, 'CONTRACT_PENDING', 2); const c = await contract(x, a);
    await db.doc(`businesses/${x.b}`).update({deactivatedAt: Timestamp.now(), isApproved: false});
    let msg = '';
    try { await fn.callableFinalizeWorkerSignature.run({auth: {uid: a.w, token: {}}, rawRequest: {headers: {}}, data: {contractId: c, signatureBase64: B64, pdfBase64: B64}}); msg = 'OK'; } catch (e) { msg = e.message; }
    return {pv: '-', out: msg.slice(0, 60)};
  },
};

// [id, 무엇을 보는가, BEFORE 판정, AFTER 판정]
const EXPECT = [
  ['A1', '마감 공고 · 시작 전 계약 대기 + 미서명 계약', (b) => /지원서 CONTRACT_PENDING/.test(b.out) && /계약 pending_worker/.test(b.out),
    (a) => /시작전취소 1/.test(a.pv) && /지원서 CANCELED\/BUSINESS_DEACTIVATED · 계약 voided · 알림 1/.test(a.out)],
  ['A2', '마감 공고 · 대기 지원', (b) => /대기마감 0/.test(b.pv) && /지원서 PENDING/.test(b.out),
    (a) => /대기마감 1/.test(a.pv) && /지원서 REJECTED\/BUSINESS_DEACTIVATED · 알림 1/.test(a.out)],
  ['A3', '실근무 있는 계약 대기 — 사전 해결 필수', (b) => /사업장 종료 true/.test(b.out),
    (a) => /실근무계약대기 1 · canArchive false/.test(a.pv) && /실행 ARCHIVE_BLOCKED · 사업장 종료 false · 지원서 CONTRACT_PENDING · 알림 0/.test(a.out)],
  ['A4', '게이트 없는 연쇄 — 실근무 계약 대기 보존(자동 취소 없음)', (b) => /지원서 CONTRACT_PENDING · 알림 0/.test(b.out),
    (a) => /지원서 CONTRACT_PENDING · 알림 0/.test(a.out)],
  ['A5', '사전 조회 건수 = 실제 처리 건수', (b) => /일치 false/.test(b.out), (a) => /실행 OK/.test(a.out) && /일치 true/.test(a.out)],
  ['B1', '종료 후 단기 출근(관리자 일괄, 종료 시각 이후)', (b) => /출근기록 생성/.test(b.out), (a) => /businessClosed/.test(a.out) && /출근기록 없음/.test(a.out)],
  ['B2', '종료 당일 종료 전 출근 기록(대조)', (b) => /출근기록 생성/.test(b.out), (a) => /출근기록 생성/.test(a.out)],
  ['B3', '종료 후 단기 출근(근로자 본인)', (b) => !/BUSINESS_CLOSED/.test(b.out), (a) => /BUSINESS_CLOSED/.test(a.out) && /출근기록 없음/.test(a.out)],
  ['C1', '사업장 문서 없는 보존 확정 서명', (b) => /^OK · 계약 completed/.test(b.out), (a) => /BUSINESS_MISSING · 계약 pending_worker · 지원서 CONFIRMED/.test(a.out)],
  ['C2', '종료 사업장 보존 확정 서명(대조)', (b) => /^OK · 계약 completed · 지원서 CONFIRMED/.test(b.out), (a) => /^OK · 계약 completed · 지원서 CONFIRMED/.test(a.out)],
  ['C3', '계약 대기 서명 거절 문구', (b) => /운영이 종료된 사업장/.test(b.out), (a) => /계약 대기/.test(a.out)],
];

(async () => {
  if (LABEL) {
    const out = {};
    for (const [id] of EXPECT) { try { out[id] = await CELLS[id](); } catch (e) { out[id] = {pv: '-', out: 'THROW ' + e.message}; } }
    log('@@' + JSON.stringify(out)); process.exit(0);
  }
  const {execFileSync} = require('child_process');
  const got = {};
  for (const L of ['BEFORE', 'AFTER']) {
    const o = execFileSync(process.execPath, [__filename], {env: Object.assign({}, process.env, {LABEL: L}), maxBuffer: 1 << 26}).toString();
    got[L] = JSON.parse(o.split('@@').pop());
  }
  let fail = 0;
  for (const [id, desc, fb, fa] of EXPECT) {
    const b = got.BEFORE[id]; const a = got.AFTER[id];
    const ok = fb(b) && fa(a); if (!ok) fail++;
    log(`${ok ? 'ok  ' : 'FAIL'} ${id} ${desc}\n       BEFORE 사전[${b.pv}] → ${b.out}\n       AFTER  사전[${a.pv}] → ${a.out}`);
  }
  log(`\n셀 ${EXPECT.length} · 실패 ${fail}`);
  process.exit(fail ? 1 : 0);
})().catch((e) => { log('ERR ' + e.stack); process.exit(2); });
