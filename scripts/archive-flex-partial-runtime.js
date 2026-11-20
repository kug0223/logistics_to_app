/**
 * [ARCHIVE-FLEX-PARTIAL] callableCreateFlexSlots 의 400건 청크 저장 — 중간 종료·실패·응답 유실·재시도·동시 실행.
 *
 *   같은 seed 를 BEFORE / AFTER 번들에 각각 올린다(번들마다 initializeApp → 자식 프로세스 하나씩).
 *   주입(하네스 전용 — 제품 코드에 장치 없음):
 *     CLOSE_AFTER_FIRST  첫 트랜잭션이 커밋된 직후 사업장을 운영 종료한다
 *     FAIL_SECOND        두 번째 트랜잭션을 한 번 던진다(오류·시간 초과 대용)
 *   공개 스케줄러(masterScheduler)·syncTOStats 는 돌리지 않는다 — 공개 판정은 callablePublishTO 의
 *   완성 판정(srvFlexSlotCompleteness)만, 카운터는 공고 문서의 totalSlots·totalRequired 만 본다.
 *   동시 실행 셀은 에뮬레이터가 트랜잭션 충돌을 검출하지 않으므로 실제 경합은 NOT VERIFIED.
 *     BEFORE=<lib/index.js> AFTER=<lib/index.js> node scripts/archive-flex-partial-runtime.js
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

// ── 주입
let MODE = null; let txSeen = 0; let closeBiz = null;
const origRunTx = FS.Firestore.prototype.runTransaction;
FS.Firestore.prototype.runTransaction = async function (...a) {
  txSeen++;
  if (MODE === 'FAIL_SECOND' && txSeen === 2) { MODE = null; throw new Error('INJECTED chunk failure'); }
  const r = await origRunTx.apply(this, a);
  if (MODE === 'CLOSE_AFTER_FIRST' && txSeen === 1) {
    MODE = null;
    await db.doc(`businesses/${closeBiz}`).update({deactivatedAt: Timestamp.now(), isApproved: false});
  }
  return r;
};
const arm = (m, biz) => { MODE = m; txSeen = 0; closeBiz = biz; };

const RUN = 'fp' + Date.now().toString(36);
const K = 9 * 3600e3; const NOW = Date.now(); const DAY = 86400e3;
const kstMidnight = (ms) => { const d = new Date(ms + K); return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()) - K; };
const TODAY = kstMidnight(NOW);
let seq = 0;
const uid = (p) => `${p}-${RUN}-${++seq}`;
const read = async (p) => (await db.doc(p).get()).data();
async function call(name, who, data) {
  try { return {ok: await fn[name].run({auth: {uid: who, token: {}}, rawRequest: {headers: {}}, data})}; } catch (e) {
    return {err: (e.details && (e.details.code || e.details.reason)) || `${e.code || ''}:${String(e.message).slice(0, 50)}`};
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
/** 새 앱 생성 흐름의 미공개 공고(callableCreateTO 가 남기는 모양) 또는 이미 공개된 완성 공고. */
async function posting(x, published) {
  const t = uid('t');
  await db.doc(`tos/${t}`).set(Object.assign({businessId: x.b, creatorUID: x.owner, type: 'flex', title: 't', totalConfirmed: 0, totalPending: 0,
    createdAt: Timestamp.now()}, published ?
    {status: 'ACTIVE', isPublished: true, publishMode: 'immediate', totalSlots: 1, totalRequired: 2, dates: ['2099-01-01']} :
    {status: 'SCHEDULED', isPublished: false, publishMode: 'deferred', totalSlots: 0, totalRequired: 0}));
  if (published) {
    await db.doc(`tos/${t}/slots/legacy1`).set({toId: t, status: 'open', date: Timestamp.fromMillis(Date.UTC(2099, 0, 1, -9)),
      workDetails: [{wdId: 'w0', workType: 'QA', requiredCount: 2}], confirmedCount: 0, pendingCount: 0});
  }
  return t;
}
const datesOf = (n, offset = 4) => Array.from({length: n}, (_, k) => new Date(TODAY + (offset + k) * DAY + K).toISOString().slice(0, 10));
const flex = (x, t, dates) => call('callableCreateFlexSlots', x.owner, {toId: t, businessId: x.b, dates,
  workDetails: [{workType: 'QA', startTime: '14:00', endTime: '15:00', requiredCount: 2, wage: 12000, wageType: 'hourly', payScheduleType: 'next_day'}],
  deadlineType: 'HOURS_BEFORE', hoursBeforeStart: 1});
async function state(t) {
  const d = await read(`tos/${t}`);
  const slots = await db.collection(`tos/${t}/slots`).get();
  const dates = new Set(slots.docs.map((s) => s.get('date').toMillis()));
  const req = slots.docs.reduce((a, s) => a + (s.get('workDetails') || []).reduce((b, w) => b + (w.requiredCount || 0), 0), 0);
  return {slots: slots.size, uniqDates: dates.size, totalSlots: d.totalSlots, totalRequired: d.totalRequired, actualRequired: req,
    write: d.slotWrite ? d.slotWrite.state : '-', deleted: d.isDeleted === true, status: d.status, published: d.isPublished === true};
}
const S = (o) => `슬롯 ${o.slots}(날짜 ${o.uniqDates}) · totalSlots ${o.totalSlots} · 필요 ${o.totalRequired}/실제 ${o.actualRequired} · 표식 ${o.write} · ${o.status}${o.published ? '/공개' : ''}${o.deleted ? '/삭제' : ''}`;
const publishVerdict = async (x, t) => { const r = await call('callablePublishTO', x.owner, {toId: t}); return r.err || 'PUBLISHED'; };

const CELLS = {
  F1: async () => { // 401건 — 첫 400건 커밋 직후 운영 종료(새 앱 흐름: 미공개 공고)
    const x = await biz(); const t = await posting(x, false);
    arm('CLOSE_AFTER_FIRST', x.b); const r = await flex(x, t, datesOf(401)); arm(null);
    const s = await state(t);
    return {out: `${r.err || 'OK'} · ${S(s)}`, s};
  },
  F2: async () => { // 801건 — 이미 공개된 공고에 날짜 추가 중 운영 종료(롤백 대상 아님)
    const x = await biz(); const t = await posting(x, true);
    arm('CLOSE_AFTER_FIRST', x.b); const r = await flex(x, t, datesOf(801)); arm(null);
    const s = await state(t);
    return {out: `${r.err || 'OK'} · ${S(s)}`, s};
  },
  F3: async () => { // 801건 — 공개 공고, 두 번째 묶음 실패 → 같은 요청 재시도(새 앱은 재시도하지 않는다 — 사용자가 다시 저장)
    const x = await biz(); const t = await posting(x, true); const ds = datesOf(801);
    arm('FAIL_SECOND', x.b); const r1 = await flex(x, t, ds); arm(null);
    const s1 = await state(t);
    const v1 = await (async () => { const d = await read(`tos/${t}`); return d.slotWrite && d.slotWrite.state === 'IN_PROGRESS' ? 'INCOMPLETE(표식)' : (d.totalSlots > 0 ? 'COMPLETE(totalSlots>0)' : 'INCOMPLETE'); })();
    const r2 = await flex(x, t, ds);
    const s2 = await state(t);
    return {out: `1차 ${r1.err || 'OK'} · ${S(s1)} · 완성판정 ${v1} → 재시도 ${r2.err || 'OK'} · ${S(s2)}`, s1, s2};
  },
  F4: async () => { // 801건 — 미공개 공고, 두 번째 묶음 실패(서버 롤백 대상)
    const x = await biz(); const t = await posting(x, false);
    arm('FAIL_SECOND', x.b); const r = await flex(x, t, datesOf(801)); arm(null);
    const s = await state(t);
    return {out: `${r.err || 'OK'} · ${S(s)} · 새 앱 '서버 완료' 판정 ${(s.totalSlots > 0) && !s.deleted ? '완료' : '미완료→callableDeleteTO'}`, s};
  },
  F5: async () => { // 저장 성공·응답 유실 → 같은 요청 재시도
    const x = await biz(); const t = await posting(x, false); const ds = datesOf(401);
    const r1 = await flex(x, t, ds); const s1 = await state(t);
    const ids1 = (await db.collection(`tos/${t}/slots`).get()).docs.map((d) => d.id).sort().join();
    const r2 = await flex(x, t, ds); const s2 = await state(t);
    const ids2 = (await db.collection(`tos/${t}/slots`).get()).docs.map((d) => d.id).sort().join();
    const pub = await publishVerdict(x, t);
    return {out: `1차 ${r1.err || 'OK'} ${S(s1)} → 재시도 ${r2.err || 'OK'} ${S(s2)} · id 불변 ${ids1 === ids2} · 공개 ${pub}`, s1, s2, same: ids1 === ids2, pub};
  },
  F6: async () => { // 같은 요청 두 개 동시(에뮬레이터는 충돌을 검출하지 않는다 → 구조만)
    const x = await biz(); const t = await posting(x, false); const ds = datesOf(300);
    const [a, b] = await Promise.all([flex(x, t, ds), flex(x, t, ds)]);
    const s = await state(t);
    return {out: `${a.err || 'OK'}/${b.err || 'OK'} · ${S(s)}`, s};
  },
};
const EXPECT = [
  ['F1', '401건 · 첫 400건 뒤 운영 종료(미공개)', (b) => b.s.slots === 400 && b.s.deleted, (a) => a.s.slots === 400 && a.s.deleted && a.s.write === 'IN_PROGRESS'],
  // [FLEX-INITIAL-ONLY] 공개 중 공고의 날짜 추가는 이제 서버가 받지 않는다(제품 결정 8/30) — 기대: 거절·원장 불변(슬롯 1).
  ['F2', '801건 · 공개 공고에 추가 중 운영 종료', (b) => b.s.slots >= 401, (a) => /FLEX_NOT_INITIAL/.test(a.out) && a.s.slots === 1 && a.s.totalSlots === 1],
  ['F3', '801건 · 두 번째 묶음 실패 → 재시도', (b) => b.s2.slots >= 802, (a) => /FLEX_NOT_INITIAL/.test(a.out) && a.s2.slots === 1 && a.s2.totalSlots === 1],
  ['F4', '801건 · 미공개 공고 두 번째 묶음 실패(서버 롤백)', (b) => b.s.deleted, (a) => a.s.deleted && a.s.write === 'IN_PROGRESS' && a.s.totalSlots === 0],
  ['F5', '저장 성공·응답 유실 → 재시도(중복·카운트)', (b) => b.s2.slots === 401 && b.s2.totalSlots === 401 && b.same, (a) => a.s2.slots === 401 && a.s2.totalSlots === 401 && a.same && a.pub === 'PUBLISHED'],
  ['F6', '같은 요청 동시 두 번(구조)', (b) => b.s.slots > b.s.uniqDates, (a) => a.s.slots === a.s.uniqDates && a.s.totalSlots === a.s.slots],
];

(async () => {
  if (LABEL) {
    const out = {};
    for (const [id] of EXPECT) { try { out[id] = await CELLS[id](); } catch (e) { arm(null); out[id] = {out: 'THROW ' + e.message, s: {}, s1: {}, s2: {}}; } }
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
    let ok = false; try { ok = fb(b) && fa(a); } catch (_) { ok = false; }
    if (!ok) fail++;
    log(`${ok ? 'ok  ' : 'FAIL'} ${id} ${desc}\n       BEFORE → ${b.out}\n       AFTER  → ${a.out}`);
  }
  log(`\n셀 ${EXPECT.length} · 실패 ${fail}`);
  process.exit(fail ? 1 : 0);
})().catch((e) => { log('ERR ' + e.stack); process.exit(2); });
