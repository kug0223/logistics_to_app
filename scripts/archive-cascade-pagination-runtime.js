/**
 * [ARCHIVE-CASCADE-PAGINATION] 운영 종료 연쇄 — 500건 초과·중간 실패·재실행·중복 실행·종료 뒤 writer.
 *
 *   같은 seed 를 BEFORE / AFTER 번들에 각각 올린다(번들마다 initializeApp → 자식 프로세스 하나씩).
 *   callable·트리거는 번들의 `.run` 으로 직접 부른다(에뮬레이터 전용, demo-alfit-r7).
 *   장애는 하네스가 Firestore SDK 의 Transaction.update / Transaction.create 를 감싸 **한 번씩** 던진다
 *   (제품 코드에는 주입 장치가 없다). 에뮬레이터는 트랜잭션 충돌을 재현하지 않으므로 경합 셀은
 *   "구조 검증"으로만 적는다.
 *     BEFORE=<lib/index.js> AFTER=<lib/index.js> node scripts/archive-cascade-pagination-runtime.js
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
const FS = require(path.join(ROOT, 'functions', 'node_modules', '@google-cloud', 'firestore'));
if (!process.env.BEFORE || !process.env.AFTER) throw new Error('BEFORE·AFTER 번들 경로가 필요하다');
const LABEL = process.env.LABEL;
const fn = LABEL ? require(process.env[LABEL]) : null;
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
const {Timestamp} = admin.firestore;

// ── 장애 주입(하네스 전용): 경로 집합에 든 문서의 트랜잭션 update/create 를 한 번 던진다
const FAULT = new Set();
const faultHit = (ref) => { const p = ref && ref.path; for (const k of FAULT) if (p && p.startsWith(k)) { FAULT.delete(k); return true; } return false; };
const origUpdate = FS.Transaction.prototype.update;
FS.Transaction.prototype.update = function (ref, ...rest) { if (faultHit(ref)) throw new Error('FAULT update ' + ref.path); return origUpdate.call(this, ref, ...rest); };
const origCreate = FS.Transaction.prototype.create;
FS.Transaction.prototype.create = function (ref, ...rest) { if (faultHit(ref)) throw new Error('FAULT create ' + ref.path); return origCreate.call(this, ref, ...rest); };

const RUN = 'pg' + Date.now().toString(36);
const K = 9 * 3600e3; const NOW = Date.now(); const DAY = 86400e3;
const kstMidnight = (ms) => { const d = new Date(ms + K); return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()) - K; };
const TODAY = kstMidnight(NOW);
const ymd = (ms) => { const d = new Date(ms + K); return `${d.getUTCFullYear()}${String(d.getUTCMonth() + 1).padStart(2, '0')}${String(d.getUTCDate()).padStart(2, '0')}`; };
let seq = 0;
const uid = (p) => `${p}-${RUN}-${String(++seq).padStart(5, '0')}`;
const read = async (p) => (await db.doc(p).get()).data();
async function call(name, who, data) {
  if (!fn[name]) return {err: 'NO_FUNCTION'};
  try { return {ok: await fn[name].run({auth: {uid: who, token: {}}, rawRequest: {headers: {}}, data})}; } catch (e) {
    return {err: (e.details && (e.details.code || e.details.reason)) || `${e.code || ''}:${String(e.message).slice(0, 50)}`};
  }
}
async function writeMany(items) { // [path, data]
  for (let i = 0; i < items.length; i += 400) {
    const b = db.batch(); items.slice(i, i + 400).forEach(([p, d]) => b.set(db.doc(p), d)); await b.commit();
  }
}
const RULES = {earlyWindow: 30, earlyArrivalUnit: 10, lateGrace: 5, lateUnit: 10, lateWindow: 600, overtimeUnit: 10, earlyLeaveUnit: 10};
async function world() {
  const b = uid('b'); const o = uid('o'); const sa = uid('sa');
  await writeMany([[`users/${o}`, {role: 'BUSINESS_ADMIN', name: 'owner', businessId: b}], [`users/${sa}`, {role: 'SUPER_ADMIN', name: 'sa'}],
    [`businesses/${b}`, {isApproved: true, ownerId: o, adminIds: [o], name: 'biz', deactivatedAt: null, attendanceRules: RULES, latitude: 37, longitude: 127}]]);
  const closed = uid('t');
  await writeMany([[`tos/${closed}`, {businessId: b, status: 'CLOSED', closedReason: 'MANUAL', title: 't', type: 'flex', isPublished: true}],
    [`tos/${closed}/slots/s1`, {status: 'closed', date: Timestamp.fromMillis(TODAY + 2 * DAY), workDetails: [{id: 'wd1', wdId: 'wd1', workType: 'QA', requiredCount: 9999}],
      workDetailCounts: {wd1: {pendingCount: 0, confirmedCount: 0}}, pendingCount: 0, confirmedCount: 0}]]);
  return {b, o, sa, closed};
}
const appDoc = (x, status, dayOffset, o = {}) => Object.assign({uid: o.uid || uid('w'), businessId: x.b, toId: x.closed, slotId: 's1', wdId: 'wd1',
  selectedWorkType: 'QA', status, type: 'short', workDate: Timestamp.fromMillis(TODAY + dayOffset * DAY), startTime: '09:00', endTime: '18:00',
  businessName: 'biz', toTitle: 't', appliedAt: Timestamp.now(), statusHistory: []}, o);
async function seedApps(x, status, n, dayOffset, extra = {}) {
  const ids = []; const items = [];
  for (let i = 0; i < n; i++) { const id = uid('a'); ids.push(id); items.push([`applications/${id}`, appDoc(x, status, dayOffset, extra)]); }
  await writeMany(items); return ids;
}
async function deactivateAndRun(x, viaOwner) {
  if (viaOwner) {
    const pv = await call('callableArchiveOwnBusiness', x.o, {businessId: x.b, preview: true});
    const before = await read(`businesses/${x.b}`);
    const r = await call('callableArchiveOwnBusiness', x.o, {businessId: x.b, expected: pv.ok && pv.ok.preview});
    const after = await read(`businesses/${x.b}`);
    let trig = 'NOT_RUN';
    if (after.deactivatedAt) trig = await runTrigger(x, before, after);
    return {preview: pv.ok && pv.ok.preview, run: r.err || 'OK', trig, before, after};
  }
  const before = await read(`businesses/${x.b}`);
  const r = await call('callableManageBusiness', x.sa, {businessId: x.b, action: 'deactivate'});
  const after = await read(`businesses/${x.b}`);
  return {run: r.err || 'OK', trig: after.deactivatedAt ? await runTrigger(x, before, after) : 'NOT_RUN', before, after};
}
async function runTrigger(x, before, after) {
  try {
    await fn.onBusinessDeactivated.run({params: {businessId: x.b}, data: {before: {exists: true, data: () => before}, after: {exists: true, data: () => after}}});
    return 'RESOLVED';
  } catch (e) { return 'THREW'; }
}
async function countWhere(coll, f) {
  let q = db.collection(coll); for (const [k, op, v] of f) q = q.where(k, op, v); return (await q.count().get()).data().count;
}
async function ledger(x) {
  const apps = await db.collection('applications').where('businessId', '==', x.b).get();
  const st = {}; let hist = 0; const users = new Set();
  for (const d of apps.docs) { const k = `${d.get('status')}${d.get('cancelReason') ? '/' + d.get('cancelReason') : ''}`; st[k] = (st[k] || 0) + 1; hist += (d.get('statusHistory') || []).length; users.add(d.get('uid')); }
  let notifs = 0; for (const u of users) notifs += (await db.collection(`users/${u}/notifications`).get()).size;
  const tos = await db.collection('tos').where('businessId', '==', x.b).get();
  const tst = {}; for (const t of tos.docs) tst[t.get('status')] = (tst[t.get('status')] || 0) + 1;
  const slot = await read(`tos/${x.closed}/slots/s1`);
  const ct = await db.collection('employment_contracts').where('businessId', '==', x.b).get();
  const cst = {}; for (const c of ct.docs) cst[c.get('status')] = (cst[c.get('status')] || 0) + 1;
  const biz = await read(`businesses/${x.b}`);
  return {st, hist, notifs, tst, slotPending: slot && slot.workDetailCounts && slot.workDetailCounts.wd1 && slot.workDetailCounts.wd1.pendingCount, cst,
    cascade: biz && biz.archiveCascade ? biz.archiveCascade.state : 'none'};
}
const J = (o) => JSON.stringify(o);

const CELLS = {
  // ── G1 501건 이상·여러 페이지: 사전 조회 분류 = 최종 처리
  G1: async () => {
    const x = await world();
    const P = 520, F = 510, T = 505, I = 505;
    await seedApps(x, 'PENDING', P, 2);
    await seedApps(x, 'CONTRACT_PENDING', F, 3);
    await seedApps(x, 'INVITED', I, 2, {invitedAt: Timestamp.now()});
    const tos = []; for (let i = 0; i < T; i++) tos.push([`tos/${uid('t')}`, {businessId: x.b, status: 'ACTIVE', title: 't', type: 'flex', isPublished: true}]);
    await writeMany(tos);
    // BEFORE 는 사전 조회가 상한에 막혀 소유자 경로로 종료할 수 없다 → 같은 원장을 슈퍼관리자 경로로도 돌린다
    const pv = await call('callableArchiveOwnBusiness', x.o, {businessId: x.b, preview: true});
    const p = pv.ok && pv.ok.preview;
    const owner = await deactivateAndRun(x, true);
    let path2 = 'owner';
    if (!owner.after.deactivatedAt) { path2 = 'superAdmin'; await deactivateAndRun(x, false); }
    const l = await ledger(x);
    const pending = l.st.PENDING || 0; const cp = l.st.CONTRACT_PENDING || 0; const inv = l.st.INVITED || 0; const open = l.tst.ACTIVE || 0;
    return {pv: p ? `대기 ${p.pendingApplications} · 시작전취소 ${p.futureConfirmed} · 초대 ${p.invites} · 공고 ${p.openPostings} · truncated ${p.truncated} · canArchive ${p.canArchive}` : 'ERR',
      out: `종료 경로 ${path2} · 트리거 ${owner.trig} · 남은 대기 ${pending} · 남은 계약대기 ${cp} · 남은 초대 ${inv} · 남은 열린 공고 ${open} · 상태 ${l.cascade}`,
      ok: {prevExact: !!p && p.pendingApplications === P && p.futureConfirmed === F && p.invites === I && p.openPostings === T + 0 && p.canArchive === true,
        allDone: pending === 0 && cp === 0 && inv === 0 && open === 0}};
  },
  // ── G2 중간 실패 → 트리거 결과 → 재실행 → 미처리 완료, 중복 0
  G2: async () => {
    const x = await world();
    const cps = await seedApps(x, 'CONTRACT_PENDING', 40, 3);
    const pend = await seedApps(x, 'PENDING', 20, 3);
    const badState = cps.slice(0, 3);
    const badNotif = [pend[0], pend[1]];
    const users = await Promise.all(badNotif.map(async (id) => (await read(`applications/${id}`)).uid));
    badState.forEach((id) => FAULT.add(`applications/${id}`));
    users.forEach((u, k) => FAULT.add(`users/${u}/notifications/biz_end_${badNotif[k]}`));
    const r1 = await deactivateAndRun(x, true);
    const l1 = await ledger(x);
    const r2 = await runTrigger(x, r1.before, r1.after); // 플랫폼 재시도와 같은 이벤트
    const l2 = await ledger(x);
    const r3 = await runTrigger(x, r1.before, r1.after); // 한 번 더 — 결과 불변
    const l3 = await ledger(x);
    FAULT.clear();
    return {pv: '-',
      out: `1차 ${r1.trig} [${J(l1.st)} 알림 ${l1.notifs} 상태 ${l1.cascade}] → 2차 ${r2} [${J(l2.st)} 알림 ${l2.notifs} 상태 ${l2.cascade}] → 3차 ${r3} [알림 ${l3.notifs} 이력 ${l3.hist}]`,
      ok: {firstSignalsRetry: r1.trig === 'THREW', secondDone: (l2.st.CONTRACT_PENDING || 0) === 0 && (l2.st.PENDING || 0) === 0 && l2.notifs === 60,
        thirdSame: J(l3.st) === J(l2.st) && l3.notifs === l2.notifs && l3.hist === l2.hist}};
  },
  // ── G3 동일 이벤트 중복 실행 — 초대 철회 카운터·알림·이력 불변
  G3: async () => {
    const x = await world();
    await seedApps(x, 'INVITED', 5, 2, {invitedAt: Timestamp.now()});
    await db.doc(`tos/${x.closed}/slots/s1`).update({'workDetailCounts.wd1.pendingCount': 5});
    await seedApps(x, 'PENDING', 4, 2);
    await seedApps(x, 'CONFIRMED', 3, 4);
    const r1 = await deactivateAndRun(x, true);
    const l1 = await ledger(x);
    await runTrigger(x, r1.before, r1.after);
    const l2 = await ledger(x);
    return {pv: '-', out: `1회 ${J(l1)} | 2회 ${J(l2)}`, ok: {same: J(Object.assign({}, l1, {cascade: 0})) === J(Object.assign({}, l2, {cascade: 0})), slotOnce: l1.slotPending === 0}};
  },
  // ── G4 사전 조회 뒤 원장 변화 / 연쇄 뒤 늦은 쓰기 (구조 검증 — 실제 경합 아님)
  G4: async () => {
    const x = await world();
    await seedApps(x, 'PENDING', 2, 2);
    const pv = await call('callableArchiveOwnBusiness', x.o, {businessId: x.b, preview: true});
    await seedApps(x, 'PENDING', 1, 2); // 사전 조회 뒤 새 대기 지원
    const stale = await call('callableArchiveOwnBusiness', x.o, {businessId: x.b, expected: pv.ok && pv.ok.preview});
    const r = await deactivateAndRun(x, true);
    await seedApps(x, 'PENDING', 1, 2); // 연쇄가 끝난 뒤 늦게 커밋된 쓰기(다른 writer 가 남긴 것)
    const late = (await ledger(x)).st.PENDING || 0;
    const retry = await call('callableRetryBusinessArchiveCascade', x.o, {businessId: x.b});
    const after = (await ledger(x)).st.PENDING || 0;
    return {pv: '-', out: `낡은 사전 조회 ${stale.err || 'OK'} · 종료 ${r.run}/${r.trig} · 늦은 대기 ${late} → 재실행 ${retry.err || (retry.ok && retry.ok.state)} → 남은 대기 ${after}`,
      ok: {stale: stale.err === 'ARCHIVE_PREVIEW_CHANGED', retryCleans: late === 1 && after === 0}};
  },
  // ── G5 종료 뒤 공고 재개(편집 경로 status ACTIVE)·슬롯 재오픈
  G5: async () => {
    const x = await world();
    const t = uid('t');
    await writeMany([[`tos/${t}`, {businessId: x.b, status: 'ACTIVE', title: 't', type: 'flex', isPublished: true, creatorUID: x.o, editRevision: 0, totalConfirmed: 0, totalPending: 0}],
      [`tos/${t}/slots/s1`, {status: 'closed', isManualClosed: true, date: Timestamp.fromMillis(TODAY + 3 * DAY), workDetails: [{id: 'wd1', wdId: 'wd1', workType: 'QA', requiredCount: 2}]}]]);
    await deactivateAndRun(x, true);
    const tAfter = (await read(`tos/${t}`)).status;
    const u = await call('callableUpdateTO', x.o, {toId: t, updates: {status: 'ACTIVE'}, expectedEditRevision: (await read(`tos/${t}`)).editRevision || 0});
    const s1 = (await read(`tos/${t}`)).status;
    const rs = await call('callableReopenSlots', x.o, {toId: t, slotIds: ['s1'], businessId: x.b});
    const slot = (await read(`tos/${t}/slots/s1`)).status; const s2 = (await read(`tos/${t}`)).status;
    return {pv: '-', out: `종료 직후 공고 ${tAfter} · UpdateTO ${u.err || 'OK'} → 공고 ${s1} · ReopenSlots ${rs.err || 'OK'} → 슬롯 ${slot} · 공고 ${s2}`,
      ok: {reopenBlocked: s1 === 'CLOSED' && s2 === 'CLOSED' && slot === 'closed'}};
  },
  // ── G6 슈퍼관리자 경로(게이트 없음) vs 소유자 경로 — 실근무 계약 대기
  G6: async () => {
    const x = await world(); const y = await world();
    const mk = async (w) => {
      const [a] = await seedApps(w, 'CONTRACT_PENDING', 1, -1);
      const d = await read(`applications/${a}`);
      await db.doc(`attendance/${a}_${ymd(TODAY - DAY)}`).set({applicationId: a, userId: d.uid, businessId: w.b, workDate: Timestamp.fromMillis(TODAY - DAY),
        checkIn: Timestamp.fromMillis(TODAY - DAY + 9 * 3600e3), checkOut: Timestamp.fromMillis(TODAY - DAY + 18 * 3600e3), status: 'present', wageStatus: 'pending'});
      return a;
    };
    const ax = await mk(x); const ay = await mk(y);
    const sa = await deactivateAndRun(x, false);
    const ow = await deactivateAndRun(y, true);
    const bx = await read(`businesses/${x.b}`); const by = await read(`businesses/${y.b}`);
    return {pv: '-', out: `슈퍼관리자: 종료 ${sa.run} · 지원서 ${(await read(`applications/${ax}`)).status} · 상태 ${bx.archiveCascade ? bx.archiveCascade.state + ' 보존 ' + bx.archiveCascade.counts.preservedWorkedContractPending : 'none'}` +
      ` | 소유자: 종료 ${ow.run} · 지원서 ${(await read(`applications/${ay}`)).status} · 종료됨 ${by.deactivatedAt != null}`,
      ok: {saFlagged: !!bx.archiveCascade && bx.archiveCascade.state === 'NEEDS_ATTENTION', preserved: (await read(`applications/${ax}`)).status === 'CONTRACT_PENDING', ownerBlocked: by.deactivatedAt == null}};
  },
};
const EXPECT = [
  ['G1', '501건 이상·여러 페이지 — 사전 조회 = 최종 처리', (b) => !b.ok.prevExact && !b.ok.allDone, (a) => a.ok.prevExact && a.ok.allDone],
  ['G2', '중간 실패 → 재실행 → 미처리 완료, 중복 0', (b) => !b.ok.firstSignalsRetry, (a) => a.ok.firstSignalsRetry && a.ok.secondDone && a.ok.thirdSame],
  ['G3', '동일 이벤트 중복 실행 결과 불변', (b) => true, (a) => a.ok.same && a.ok.slotOnce],
  ['G4', '사전 조회 뒤 변화(구조) · 연쇄 뒤 늦은 쓰기 재실행', (b) => b.ok.stale && !b.ok.retryCleans, (a) => a.ok.stale && a.ok.retryCleans],
  ['G5', '종료 뒤 공고 재개·슬롯 재오픈', (b) => !b.ok.reopenBlocked, (a) => a.ok.reopenBlocked],
  ['G6', '슈퍼관리자 경로 vs 소유자 경로 — 실근무 계약 대기', (b) => b.ok.preserved && !b.ok.saFlagged, (a) => a.ok.preserved && a.ok.saFlagged && a.ok.ownerBlocked],
];

(async () => {
  if (LABEL) {
    const out = {};
    const only = process.env.ONLY ? process.env.ONLY.split(',') : null;
    for (const [id] of EXPECT) {
      if (only && !only.includes(id)) continue;
      try { out[id] = await CELLS[id](); } catch (e) { out[id] = {pv: '-', out: 'THROW ' + e.message, ok: {}}; }
    }
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
    if (!b || !a) continue;
    const ok = fb(b) && fa(a); if (!ok) fail++;
    log(`${ok ? 'ok  ' : 'FAIL'} ${id} ${desc}\n       BEFORE 사전[${b.pv}] → ${b.out}\n       AFTER  사전[${a.pv}] → ${a.out}`);
  }
  log(`\n셀 ${Object.keys(got.AFTER).length} · 실패 ${fail}`);
  process.exit(fail ? 1 : 0);
})().catch((e) => { log('ERR ' + e.stack); process.exit(2); });
