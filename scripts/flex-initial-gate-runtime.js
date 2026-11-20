/**
 * [FLEX-INITIAL-ONLY] callableCreateFlexSlots 최초 생성 전용 관문 — 수정 전·후 원장 비교.
 *
 *   같은 seed 를 BEFORE / AFTER 번들에 각각 올린다(번들마다 initializeApp → 자식 프로세스 하나씩).
 *   주입: FAIL_SECOND(두 번째 묶음 한 번 throw). 서버 롤백이 일어나지 않게(시간 초과로 래퍼가 못 도는 경우와
 *   같은 원장) 이어 쓰기 셀의 공고는 생성 20분 전으로 둔다(롤백은 생성 15분 안만 한다).
 *   예약 공개 스케줄러(masterScheduler.run)는 S1 셀에서만 실행한다. syncTOStats 는 실행하지 않는다
 *   (카운터 전체 검증 아님 — 공고 문서의 totalSlots·totalRequired 와 슬롯 원장만 대조).
 *     BEFORE=<lib> AFTER=<lib> node scripts/flex-initial-gate-runtime.js
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

let ARM = false; let txSeen = 0;
const orig = FS.Firestore.prototype.runTransaction;
FS.Firestore.prototype.runTransaction = async function (...a) {
  if (ARM) { txSeen++; if (txSeen === 2) { ARM = false; throw new Error('INJECTED chunk failure'); } }
  return orig.apply(this, a);
};
const arm = () => { ARM = true; txSeen = 0; };

const RUN = 'ig' + Date.now().toString(36);
const K = 9 * 3600e3; const NOW = Date.now(); const DAY = 86400e3;
const TODAY = (() => { const d = new Date(NOW + K); return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()) - K; })();
let seq = 0; const uid = (p) => `${p}-${RUN}-${++seq}`;
const read = async (p) => (await db.doc(p).get()).data();
async function call(name, who, data) {
  try { return {ok: await fn[name].run({auth: {uid: who, token: {}}, rawRequest: {headers: {}}, data})}; } catch (e) {
    return {err: (e.details && (e.details.why || e.details.code)) || `${e.code || ''}:${String(e.message).slice(0, 40)}`};
  }
}
const RULES = {earlyWindow: 30, earlyArrivalUnit: 10, lateGrace: 5, lateUnit: 10, lateWindow: 600, overtimeUnit: 10, earlyLeaveUnit: 10};
async function biz() {
  const b = uid('b'); const owner = uid('o');
  await db.doc(`users/${owner}`).set({role: 'BUSINESS_ADMIN', sealBase64: 'x', businessId: b, name: 'owner'});
  const lic = `businesses/${b}/license/license.jpg`;
  await admin.storage().bucket().file(lic).save(Buffer.from('x'));
  await db.doc(`businesses/${b}`).set({isApproved: true, ownerId: owner, adminIds: [owner], name: 'biz', city: '평택시', address: '경기도 평택시 1',
    attendanceRules: RULES, latitude: 37, longitude: 127, deactivatedAt: null,
    attendancePolicyConfirmation: Object.assign({confirmedAt: Timestamp.now(), confirmedBy: owner, actorRole: 'business_admin'}, RULES),
    businessLicenseImageUrl: `https://firebasestorage.googleapis.com/v0/b/demo-alfit-r7.appspot.com/o/${encodeURIComponent(lic)}?alt=media`});
  await db.doc(`businesses/${b}/workTypes/wt1`).set({isActive: true, name: 'QA'});
  await db.doc(`businesses/${b}/contract_templates/tpl`).set({templateType: 'daily'});
  return {b, owner};
}
/** callableCreateTO 가 남기는 flex 공고 모양 — o 로 상태를 바꾼다. */
async function to(x, o = {}) {
  const t = uid('t');
  await db.doc(`tos/${t}`).set(Object.assign({businessId: x.b, businessName: 'biz', creatorUID: x.owner, type: 'flex', title: 't', status: 'SCHEDULED',
    isPublished: false, publishMode: 'deferred', totalSlots: 0, totalRequired: 0, totalConfirmed: 0, totalPending: 0, editRevision: 0,
    createdAt: Timestamp.fromMillis(NOW - 20 * 60e3)}, o));
  return t;
}
const days = (n, off = 4) => Array.from({length: n}, (_, k) => new Date(TODAY + (off + k) * DAY + K).toISOString().slice(0, 10));
const wds = (req = 2) => [{workType: 'QA', startTime: '14:00', endTime: '15:00', requiredCount: req, wage: 12000, wageType: 'hourly', payScheduleType: 'next_day'}];
const flex = (x, t, dates, o = {}) => call('callableCreateFlexSlots', x.owner, Object.assign({toId: t, businessId: x.b, dates, workDetails: wds(),
  deadlineType: 'HOURS_BEFORE', hoursBeforeStart: 1}, o));
async function snap(t) {
  const d = await read(`tos/${t}`); const s = await db.collection(`tos/${t}/slots`).get();
  const ser = JSON.stringify(Object.keys(d).sort().map((k) => [k, d[k] && d[k].toMillis ? d[k].toMillis() : d[k]]));
  return {slots: s.size, total: d.totalSlots, req: d.totalRequired, write: d.slotWrite ? d.slotWrite.state : '-', del: d.isDeleted === true, ser,
    sig: s.docs.map((x) => x.updateTime.toMillis()).sort().join()};
}
const S = (o) => `슬롯 ${o.slots} · totalSlots ${o.total} · 필요 ${o.req} · 표식 ${o.write}${o.del ? ' · 삭제됨' : ''}`;
const res = (r) => r.err || (r.ok && r.ok.alreadyComplete ? 'OK(이미 완료)' : `OK(+${r.ok ? r.ok.slotCount : '?'})`);
/** 한 번 호출하고 원장 변화(공고 문서·슬롯 문서)가 있었는지. */
async function measure(t, f) {
  const a = await snap(t); const r = await f(); const b = await snap(t);
  return {r: res(r), before: a, after: b, wrote: a.ser !== b.ser || a.sig !== b.sig};
}
const W = (m) => `${m.r} · ${S(m.after)} · 쓰기 ${m.wrote ? '있음' : '0'}`;

const CELLS = {
  I1: async () => { const x = await biz(); const t = await to(x); const m = await measure(t, () => flex(x, t, days(3))); return {m, out: W(m)}; },
  I2: async () => { const x = await biz(); const t = await to(x, {status: 'DRAFT', publishMode: 'draft'}); const m = await measure(t, () => flex(x, t, days(3))); return {m, out: W(m)}; },
  R1: async () => { // 401건 — 두 번째 묶음 실패 → 같은 요청 이어 쓰기
    const x = await biz(); const t = await to(x); const ds = days(401);
    arm(); const r1 = await flex(x, t, ds); ARM = false; const s1 = await snap(t);
    const m = await measure(t, () => flex(x, t, ds));
    return {m, s1, out: `1차 ${res(r1)} · ${S(s1)} → 재시도 ${W(m)}`};
  },
  R2: async () => { // 801건
    const x = await biz(); const t = await to(x); const ds = days(801);
    arm(); const r1 = await flex(x, t, ds); ARM = false; const s1 = await snap(t);
    const m = await measure(t, () => flex(x, t, ds));
    return {m, s1, out: `1차 ${res(r1)} · ${S(s1)} → 재시도 ${W(m)}`};
  },
  R3: async () => { // 이어 쓰기 중 다른 요청(날짜 다름)
    const x = await biz(); const t = await to(x);
    arm(); await flex(x, t, days(401)); ARM = false;
    const m = await measure(t, () => flex(x, t, days(401, 900)));
    return {m, out: W(m)};
  },
  L1: async () => { // 완료 + 응답 유실 → 정확히 같은 요청
    const x = await biz(); const t = await to(x); const ds = days(5); await flex(x, t, ds);
    const m = await measure(t, () => flex(x, t, ds));
    return {m, out: W(m)};
  },
  L2: async () => { // 완료 뒤 같은 날짜 · 업무 인원만 다름
    const x = await biz(); const t = await to(x); const ds = days(5); await flex(x, t, ds);
    const m = await measure(t, () => flex(x, t, ds, {workDetails: wds(3)}));
    return {m, out: W(m)};
  },
  A1: async () => { // 완료된 미공개 예약 공고에 다른 날짜 추가
    const x = await biz(); const t = await to(x, {publishMode: 'scheduled', publishAt: Timestamp.fromMillis(NOW + DAY)});
    await flex(x, t, days(5));
    const m = await measure(t, () => flex(x, t, days(2, 40)));
    return {m, out: W(m)};
  },
  A2: async () => { // 공개 중(ACTIVE) 완성 공고
    const x = await biz(); const t = await to(x); await flex(x, t, days(5)); await db.doc(`tos/${t}`).update({status: 'ACTIVE', isPublished: true});
    const m = await measure(t, () => flex(x, t, days(2, 40)));
    return {m, out: W(m)};
  },
  A3: async () => { // FULL
    const x = await biz(); const t = await to(x); await flex(x, t, days(5)); await db.doc(`tos/${t}`).update({status: 'FULL', isPublished: true});
    const m = await measure(t, () => flex(x, t, days(2, 40))); return {m, out: W(m)};
  },
  A4: async () => { // CLOSED
    const x = await biz(); const t = await to(x); await flex(x, t, days(5)); await db.doc(`tos/${t}`).update({status: 'CLOSED', isPublished: true});
    const m = await measure(t, () => flex(x, t, days(2, 40))); return {m, out: W(m)};
  },
  A5: async () => { // 소프트 삭제된 미공개 공고(롤백 뒤)
    const x = await biz(); const t = await to(x, {isDeleted: true, deleteReason: 'CREATE_ROLLBACK'});
    const m = await measure(t, () => flex(x, t, days(2, 40))); return {m, out: W(m)};
  },
  A6: async () => { // 레거시: totalSlots·표식 없음 + 기존 슬롯
    const x = await biz(); const t = await to(x); await db.doc(`tos/${t}`).update({totalSlots: admin.firestore.FieldValue.delete()});
    await db.doc(`tos/${t}/slots/legacy`).set({toId: t, status: 'open', date: Timestamp.fromMillis(TODAY + 2 * DAY), workDetails: [{wdId: 'w0', workType: 'QA', requiredCount: 1}]});
    const m = await measure(t, () => flex(x, t, days(2, 40))); return {m, out: W(m)};
  },
  A7: async () => { // 관문 이전 데이터: 표식 없이 공개 중(ACTIVE)인 완성 공고 + 날짜
    const x = await biz(); const t = await to(x, {status: 'ACTIVE', isPublished: true, totalSlots: 1, totalRequired: 2});
    await db.doc(`tos/${t}/slots/old`).set({toId: t, status: 'open', date: Timestamp.fromMillis(TODAY + 2 * DAY), workDetails: [{wdId: 'w0', workType: 'QA', requiredCount: 2}]});
    const m = await measure(t, () => flex(x, t, days(2, 40))); return {m, out: W(m)};
  },
  C1: async () => { // 1.0.1+5 이후 배포 앱의 최초 생성 요청 그대로: CreateTO(deferred) → CreateFlexSlots → PublishTO
    const x = await biz();
    const c = await call('callableCreateTO', x.owner, {toData: {businessId: x.b, businessName: 'biz', type: 'flex', title: `[${RUN}] c1`, description: 'c1',
      workDetails: wds(), totalSlots: 3, totalRequired: 6, totalConfirmed: 0, totalPending: 0, deadlineType: 'HOURS_BEFORE', hoursBeforeStart: 1,
      creatorUID: x.owner, isPublished: false, status: 'SCHEDULED', publishMode: 'deferred', isManualClosed: false}});
    const t = c.ok && c.ok.toId;
    if (!t) return {out: `생성 ${c.err}`, m: {r: c.err}};
    const f = await flex(x, t, days(3));
    const p = await call('callablePublishTO', x.owner, {toId: t});
    const d = await read(`tos/${t}`);
    return {out: `생성 OK · 슬롯 ${res(f)} · 공개 ${p.err || 'OK'} → ${d.status}/게시 ${d.isPublished} · totalSlots ${d.totalSlots}`, m: {r: res(f), pub: p.err || 'OK'}};
  },
  S1: async () => { // 예약 공개 — 실제 masterScheduler 실행
    const x = await biz(); const t = await to(x, {publishMode: 'scheduled', publishAt: Timestamp.fromMillis(NOW - 60e3)});
    const f = await flex(x, t, days(3));
    try { await fn.masterScheduler.run({}); } catch (_) { /* allSettled */ }
    const d = await read(`tos/${t}`);
    return {out: `슬롯 ${res(f)} · 스케줄러 후 ${d.status}/게시 ${d.isPublished}${d.publishBlockedReason ? ' 막힘 ' + d.publishBlockedReason : ''}`, m: {r: res(f), published: d.isPublished === true}};
  },
};
const ok = (m) => m.r.startsWith('OK');
const rej = (m) => !m.r.startsWith('OK') && !m.wrote && !m.after.del;
const EXPECT = [
  ['I1', '최초 등록 — 미공개 SCHEDULED(deferred)', (b) => ok(b.m), (a) => ok(a.m) && a.m.after.write === 'COMPLETE'],
  ['I2', '최초 등록 — DRAFT', (b) => ok(b.m), (a) => ok(a.m)],
  ['R1', '401건 실패 → 같은 요청 이어 쓰기', (b) => ok(b.m), (a) => a.s1.write === 'IN_PROGRESS' && ok(a.m) && a.m.after.slots === 401 && a.m.after.total === 401],
  ['R2', '801건 실패 → 같은 요청 이어 쓰기', (b) => ok(b.m), (a) => ok(a.m) && a.m.after.slots === 801 && a.m.after.total === 801 && a.m.after.write === 'COMPLETE'],
  ['R3', '이어 쓰기 중 다른 요청', (b) => ok(b.m) && b.m.wrote, (a) => rej(a.m)],
  ['L1', '완료 + 응답 유실 → 같은 요청', (b) => ok(b.m) && b.m.wrote, (a) => a.m.r === 'OK(이미 완료)' && !a.m.wrote],
  ['L2', '완료 뒤 같은 날짜·인원만 다름', (b) => ok(b.m), (a) => rej(a.m)],
  ['A1', '완료된 미공개 예약 공고 + 다른 날짜', (b) => ok(b.m) && b.m.wrote, (a) => rej(a.m)],
  ['A2', '공개 중(ACTIVE) 공고 + 날짜', (b) => ok(b.m) && b.m.wrote, (a) => rej(a.m)],
  ['A3', 'FULL 공고 + 날짜', (b) => ok(b.m) && b.m.wrote, (a) => rej(a.m)],
  ['A4', 'CLOSED 공고 + 날짜', (b) => ok(b.m) && b.m.wrote, (a) => rej(a.m)],
  ['A5', '소프트 삭제 공고 + 날짜', (b) => ok(b.m) && b.m.wrote, (a) => !a.m.r.startsWith('OK') && !a.m.wrote],
  ['A6', '레거시(totalSlots·표식 없음, 기존 슬롯) + 날짜', (b) => ok(b.m) && b.m.wrote, (a) => rej(a.m)],
  ['A7', '표식 없는 공개 중 공고(관문 이전 데이터) + 날짜', (b) => ok(b.m) && b.m.wrote, (a) => rej(a.m)],
  ['C1', '배포 앱 최초 생성 요청(CreateTO→Slots→Publish)', (b) => ok(b.m) && b.m.pub === 'OK', (a) => ok(a.m) && a.m.pub === 'OK'],
  ['S1', '예약 공개 — masterScheduler 실행', (b) => ok(b.m) && b.m.published, (a) => ok(a.m) && a.m.published],
];

(async () => {
  if (LABEL) {
    const out = {};
    for (const [id] of EXPECT) { try { out[id] = await CELLS[id](); } catch (e) { ARM = false; out[id] = {out: 'THROW ' + e.message, m: {r: 'THROW', after: {}}, s1: {}}; } }
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
    let pass = false; try { pass = fb(b) && fa(a); } catch (_) { pass = false; }
    if (!pass) fail++;
    log(`${pass ? 'ok  ' : 'FAIL'} ${id} ${desc}\n       BEFORE → ${b.out}\n       AFTER  → ${a.out}`);
  }
  log(`\n셀 ${EXPECT.length} · 실패 ${fail}`);
  process.exit(fail ? 1 : 0);
})().catch((e) => { log('ERR ' + e.stack); process.exit(2); });
