/**
 * [ARCHIVE-WRITER-FENCE] 운영 종료와 남은 writer — 종료 직후 순차 호출 · 종료와 겹치는 쓰기(구조) · 재실행 권한.
 *
 *   같은 seed 를 BEFORE / AFTER 번들에 각각 올린다(번들마다 initializeApp → 자식 프로세스 하나씩).
 *   경합 셀(RACE)은 하네스가 writer 의 **첫 트랜잭션/배치 커밋 직전**에 사업장 종료를 끼워 넣는다 —
 *   사전 확인은 열린 사업장을 보고, 쓰기 직전에 종료가 커밋된 순서를 만든다. 진짜 동시 커밋 충돌은
 *   에뮬레이터가 검출하지 않으므로 NOT VERIFIED(구조 검증만)다.
 *     BEFORE=<lib/index.js> AFTER=<lib/index.js> node scripts/archive-writer-fence-runtime.js
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

// ── 경합 주입: 무장하면 다음 runTransaction / WriteBatch.commit 직전에 사업장을 한 번 종료한다
let RACE = null; // {biz, closedAtMs}
async function fireRace() {
  if (!RACE) return; const r = RACE; RACE = null;
  await origCommit.call(db.batch().update(db.doc(`businesses/${r.biz}`), {deactivatedAt: Timestamp.fromMillis(r.closedAtMs), isApproved: false}));
}
const origRunTx = FS.Firestore.prototype.runTransaction;
FS.Firestore.prototype.runTransaction = async function (...a) { await fireRace(); return origRunTx.apply(this, a); };
const origCommit = FS.WriteBatch.prototype.commit;
FS.WriteBatch.prototype.commit = async function (...a) { await fireRace(); return origCommit.apply(this, a); };

const RUN = 'wf' + Date.now().toString(36);
const K = 9 * 3600e3; const NOW = Date.now(); const DAY = 86400e3;
const kstMidnight = (ms) => { const d = new Date(ms + K); return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()) - K; };
const TODAY = kstMidnight(NOW);
const ymd = (ms) => { const d = new Date(ms + K); return `${d.getUTCFullYear()}${String(d.getUTCMonth() + 1).padStart(2, '0')}${String(d.getUTCDate()).padStart(2, '0')}`; };
let seq = 0;
const uid = (p) => `${p}-${RUN}-${++seq}`;
const read = async (p) => (await db.doc(p).get()).data();
async function call(name, who, data) {
  if (!fn[name]) return {err: 'NO_FUNCTION'};
  try { return {ok: await fn[name].run({auth: {uid: who, token: {}}, rawRequest: {headers: {}}, data})}; } catch (e) {
    return {err: (e.details && (e.details.code || e.details.reason)) || `${e.code || ''}:${String(e.message).slice(0, 60)}`};
  }
}
const RULES = {earlyWindow: 30, earlyArrivalUnit: 10, lateGrace: 5, lateUnit: 10, lateWindow: 600, overtimeUnit: 10, earlyLeaveUnit: 10};
/** 공개 준비가 끝난 사업장(등록증 파일·업무·계약 템플릿·근태 기준 확인·좌표). */
async function biz(o = {}) {
  const b = uid('b'); const owner = uid('o'); const sa = uid('sa');
  await db.doc(`users/${owner}`).set({role: 'BUSINESS_ADMIN', sealBase64: 'x', businessId: b, name: 'owner'});
  await db.doc(`users/${sa}`).set({role: 'SUPER_ADMIN', name: 'sa'});
  const lic = `businesses/${b}/license/license.jpg`;
  await admin.storage().bucket().file(lic).save(Buffer.from('x'));
  await db.doc(`businesses/${b}`).set(Object.assign({isApproved: true, ownerId: owner, adminIds: [owner], name: 'biz', city: '평택시',
    address: '경기도 평택시 1', attendanceRules: RULES, latitude: 37, longitude: 127, gpsRadius: 100, deactivatedAt: null,
    attendancePolicyConfirmation: Object.assign({confirmedAt: Timestamp.now(), confirmedBy: owner, actorRole: 'business_admin'}, RULES),
    businessLicenseImageUrl: `https://firebasestorage.googleapis.com/v0/b/demo-alfit-r7.appspot.com/o/${encodeURIComponent(lic)}?alt=media`}, o));
  await db.doc(`businesses/${b}/workTypes/wt1`).set({isActive: true, name: 'QA'});
  await db.doc(`businesses/${b}/contract_templates/tpl`).set({templateType: 'daily'});
  return {b, owner, sa};
}
const close = (x, atMs = NOW - 60e3) => db.doc(`businesses/${x.b}`).update({deactivatedAt: Timestamp.fromMillis(atMs), isApproved: false});
const wd = {workType: 'QA', startTime: '09:00', endTime: '18:00', requiredCount: 1, wage: 12000, wageType: 'hourly', payScheduleType: 'next_day'};
const toData = (x) => ({businessId: x.b, businessName: 'biz', type: 'contract', title: `[${RUN}]`, description: 'wf',
  workDetails: [wd], totalSlots: 0, totalRequired: 1, totalConfirmed: 0, totalPending: 0,
  rangeStart: TODAY + 3 * DAY, rangeEnd: TODAY + 30 * DAY, workDays: ['월', '화', '수', '목', '금', '토', '일'],
  deadlineType: 'HOURS_BEFORE', hoursBeforeStart: 2, contractPeriodType: 'custom', postingDurationDays: 30,
  creatorUID: x.sa, isPublished: true, status: 'ACTIVE', isManualClosed: false});
const countTos = async (x) => (await db.collection('tos').where('businessId', '==', x.b).get()).size;
async function shortApp(x, o = {}) {
  const t = uid('t'); const a = uid('a'); const w = uid('w');
  await db.doc(`users/${w}`).set({role: 'USER', name: 'w', accountStatus: 'active'});
  await db.doc(`tos/${t}`).set({businessId: x.b, status: 'ACTIVE', title: 't', type: 'flex', isPublished: true});
  await db.doc(`tos/${t}/slots/s1`).set({status: 'open', date: Timestamp.fromMillis(TODAY), workDetails: [{id: 'wd1', wdId: 'wd1', workType: 'QA', requiredCount: 5}]});
  await db.doc(`applications/${a}`).set(Object.assign({uid: w, businessId: x.b, toId: t, slotId: 's1', wdId: 'wd1', selectedWorkType: 'QA',
    status: 'CONFIRMED', type: 'short', workDate: Timestamp.fromMillis(TODAY), startTime: '00:00', endTime: '23:00', businessName: 'biz', appliedAt: Timestamp.now()}, o));
  return {a, w, t};
}
async function longApp(x) {
  const a = uid('a'); const w = uid('w');
  await db.doc(`users/${w}`).set({role: 'USER', name: 'w', accountStatus: 'active'});
  await db.doc(`applications/${a}`).set({uid: w, businessId: x.b, toId: uid('t'), status: 'CONFIRMED', type: 'long_term', isLongTerm: true,
    desiredStartDate: Timestamp.fromMillis(TODAY - 10 * DAY), workDate: Timestamp.fromMillis(TODAY - 10 * DAY),
    workEndDate: Timestamp.fromMillis(TODAY + 60 * DAY), workDays: ['월', '화', '수', '목', '금'], startTime: '09:00', endTime: '18:00',
    selectedWorkType: 'QA', businessName: 'biz', appliedAt: Timestamp.now()});
  return {a, w};
}
const hasAtt = async (a) => !(await db.collection('attendance').where('applicationId', '==', a).get()).empty;

const CELLS = {
  // ── 순차: 종료 뒤 슈퍼관리자 공고 생성(사전 확인 면제 분기)
  W1: async () => {
    const x = await biz(); await close(x);
    const r = await call('callableCreateTO', x.sa, {toData: Object.assign(toData(x), {publishMode: 'immediate'})});
    const d = await call('callableCreateTO', x.sa, {toData: Object.assign(toData(x), {publishMode: 'draft', isPublished: false, status: 'DRAFT'})});
    return {out: `즉시 ${r.err || 'OK'} · 초안 ${d.err || 'OK'} · 공고 ${await countTos(x)}건`, ok: {blocked: !!r.err && !!d.err && (await countTos(x)) === 0}};
  },
  // ── 경합(구조): 공고 공개 — 사전 확인 뒤 종료 커밋
  W2: async () => {
    const x = await biz();
    const t = uid('t');
    await db.doc(`tos/${t}`).set(Object.assign(toData(x), {status: 'DRAFT', isPublished: false, publishMode: 'draft', creatorUID: x.owner, editRevision: 0}));
    RACE = {biz: x.b, closedAtMs: NOW - 60e3};
    const r = await call('callablePublishTO', x.owner, {toId: t}); RACE = null;
    const d = await read(`tos/${t}`);
    return {out: `공개 ${r.err || 'OK'} · 공고 ${d.status}/게시 ${d.isPublished} · 사업장 종료 ${(await read(`businesses/${x.b}`)).deactivatedAt != null}`,
      ok: {blocked: d.isPublished !== true}};
  },
  // ── 경합(구조): 슬롯 생성 — 확인과 쓰기 사이 종료
  W3: async () => {
    const x = await biz();
    const t = uid('t');
    await db.doc(`tos/${t}`).set({businessId: x.b, creatorUID: x.owner, status: 'SCHEDULED', type: 'flex', isPublished: false, publishMode: 'scheduled',
      publishAt: Timestamp.fromMillis(NOW + DAY), title: 't', totalRequired: 0, totalSlots: 0, totalConfirmed: 0, totalPending: 0, createdAt: Timestamp.now()});
    const dateStr = new Date(TODAY + 4 * DAY + K).toISOString().slice(0, 10);
    RACE = {biz: x.b, closedAtMs: NOW - 60e3};
    const r = await call('callableCreateFlexSlots', x.owner, {toId: t, businessId: x.b, dates: [dateStr],
      workDetails: [Object.assign({}, wd, {startTime: '14:00', endTime: '15:00'})], deadlineType: 'HOURS_BEFORE', hoursBeforeStart: 1});
    RACE = null;
    const n = (await db.collection(`tos/${t}/slots`).get()).size;
    return {out: `슬롯 생성 ${r.err || 'OK'} · 슬롯 ${n}개`, ok: {blocked: n === 0}};
  },
  // ── 순차: 종료 사업장 공고 편집(UpdateTO 일반 경로)
  W4: async () => {
    const x = await biz(); const t = uid('t');
    await db.doc(`tos/${t}`).set(Object.assign(toData(x), {status: 'CLOSED', closedReason: 'BUSINESS_DEACTIVATED', creatorUID: x.owner, editRevision: 0}));
    await close(x);
    const r = await call('callableUpdateTO', x.owner, {toId: t, updates: {description: '수정'}, expectedEditRevision: 0});
    return {out: `편집 ${r.err || 'OK'} · 설명 ${(await read(`tos/${t}`)).description}`, ok: {blocked: (await read(`tos/${t}`)).description !== '수정'}};
  },
  // ── 경합(구조): 관리자 일괄 출근 — 사전 판정은 열림, 쓰기 직전 종료(종료 시각 < 출근 시각)
  W5: async () => {
    const x = await biz(); const s = await shortApp(x);
    RACE = {biz: x.b, closedAtMs: NOW - 30 * 60e3};
    const r = await call('callableBatchCheckIn', x.owner, {businessId: x.b, entries: [{applicationId: s.a, workDateMs: TODAY, userId: s.w,
      businessName: 'biz', workType: 'QA', status: 'present', checkInMs: NOW - 60e3}]});
    RACE = null;
    return {out: `${r.err || 'OK'} · 실패 ${JSON.stringify((r.ok && r.ok.failures || []).map((f) => f.reason))} · 출근기록 ${await hasAtt(s.a) ? '생성' : '없음'}`,
      ok: {blocked: !(await hasAtt(s.a))}};
  },
  // ── 경합(구조): 근로자 본인 출근
  W6: async () => {
    const x = await biz(); const s = await shortApp(x);
    RACE = {biz: x.b, closedAtMs: NOW - 30 * 60e3};
    const r = await call('callableCheckIn', s.w, {applicationId: s.a, businessId: x.b, businessName: 'biz', workDateMs: TODAY, workType: 'QA',
      method: 'gps', latitude: 37, longitude: 127});
    RACE = null;
    return {out: `${r.err || 'OK'} · 출근기록 ${await hasAtt(s.a) ? '생성' : '없음'}`, ok: {blocked: !(await hasAtt(s.a))}};
  },
  // ── 순차: 종료 뒤 추가 근무(EXTRA_WORK) 승인 / 대조: 휴무(LEAVE) 승인은 허용
  W7: async () => {
    const x = await biz(); const l = await longApp(x);
    const mk = async (type, dayOffset) => {
      const id = uid('scr');
      await db.doc(`schedule_change_requests/${id}`).set({businessId: x.b, applicationId: l.a, applicantUid: l.w, requestType: type,
        targetDate: Timestamp.fromMillis(TODAY + dayOffset * DAY), status: 'PENDING', createdAt: Timestamp.now()});
      return id;
    };
    const ex = await mk('EXTRA_WORK', 5); const lv = await mk('LEAVE', 6);
    await close(x);
    const r1 = await call('callableApproveScheduleChangeRequest', x.owner, {requestId: ex, action: 'APPROVED'});
    const r2 = await call('callableApproveScheduleChangeRequest', x.owner, {requestId: lv, action: 'APPROVED'});
    const app = await read(`applications/${l.a}`);
    return {out: `추가근무 ${r1.err || 'OK'} · 휴무 ${r2.err || 'OK'} · extraWorkDates ${(app.extraWorkDates || []).length} · leaveDates ${(app.leaveDates || []).length}`,
      ok: {blocked: (app.extraWorkDates || []).length === 0, leaveOk: !r2.err}};
  },
  // ── 재실행 callable 권한
  W8: async () => {
    const x = await biz(); const co = uid('co'); const sub = uid('sub'); const st = uid('st');
    await db.doc(`businesses/${x.b}`).update({adminIds: [x.owner, co]});
    await db.doc(`users/${co}`).set({role: 'BUSINESS_ADMIN'});
    await db.doc(`users/${sub}`).set({role: 'USER', subAdminBusinessIds: [x.b]});
    await db.doc(`users/${st}`).set({role: 'USER'});
    const activeR = await call('callableRetryBusinessArchiveCascade', x.owner, {businessId: x.b});
    const missingR = await call('callableRetryBusinessArchiveCascade', x.sa, {businessId: uid('nob')});
    await close(x);
    const res = {};
    for (const [k, who] of [['owner', x.owner], ['super', x.sa], ['coAdmin', co], ['subAdmin', sub], ['stranger', st]]) {
      const r = await call('callableRetryBusinessArchiveCascade', who, {businessId: x.b});
      res[k] = r.err || (r.ok && r.ok.state);
    }
    let noAuth = 'OK';
    try { await fn.callableRetryBusinessArchiveCascade.run({auth: undefined, rawRequest: {headers: {}}, data: {businessId: x.b}}); } catch (e) { noAuth = e.code; }
    return {out: `활성 ${activeR.err} · 없는 사업장 ${missingR.err} · ${JSON.stringify(res)} · 미인증 ${noAuth}`,
      ok: {authz: /^COMPLETE|NEEDS/.test(res.owner) && /^COMPLETE|NEEDS/.test(res.super) && /permission/.test(res.coAdmin) && /permission/.test(res.subAdmin) &&
        /permission/.test(res.stranger) && /failed-precondition/.test(activeR.err) && /not-found/.test(missingR.err) && noAuth === 'unauthenticated'}};
  },
  // ── 대조: 운영 중 사업장의 정상 흐름(공고 생성·공개·일괄 출근·추가 근무 승인)
  W9: async () => {
    const x = await biz(); const out = [];
    const r1 = await call('callableCreateTO', x.sa, {toData: Object.assign(toData(x), {publishMode: 'immediate'})}); out.push(`생성 ${r1.err || 'OK'}`);
    const t = uid('t');
    await db.doc(`tos/${t}`).set(Object.assign(toData(x), {status: 'DRAFT', isPublished: false, publishMode: 'draft', creatorUID: x.owner, editRevision: 0}));
    const r2 = await call('callablePublishTO', x.owner, {toId: t}); out.push(`공개 ${r2.err || 'OK'}`);
    const s = await shortApp(x);
    const r3 = await call('callableBatchCheckIn', x.owner, {businessId: x.b, entries: [{applicationId: s.a, workDateMs: TODAY, userId: s.w,
      businessName: 'biz', workType: 'QA', status: 'present', checkInMs: NOW - 60e3}]}); out.push(`일괄출근 ${await hasAtt(s.a) ? '생성' : '없음'}`);
    const l = await longApp(x); const id = uid('scr');
    await db.doc(`schedule_change_requests/${id}`).set({businessId: x.b, applicationId: l.a, applicantUid: l.w, requestType: 'EXTRA_WORK',
      targetDate: Timestamp.fromMillis(TODAY + 5 * DAY), status: 'PENDING', createdAt: Timestamp.now()});
    const r4 = await call('callableApproveScheduleChangeRequest', x.owner, {requestId: id, action: 'APPROVED'}); out.push(`추가근무 ${r4.err || 'OK'}`);
    void r3;
    return {out: out.join(' · '), ok: {normal: !r1.err && !r2.err && (await hasAtt(s.a)) && !r4.err}};
  },
};
const EXPECT = [
  ['W1', '순차: 종료 뒤 슈퍼관리자 공고 생성(즉시·초안)', (b) => !b.ok.blocked, (a) => a.ok.blocked],
  ['W2', '경합(구조): 공고 공개 — 사전 확인 뒤 종료', (b) => !b.ok.blocked, (a) => a.ok.blocked],
  ['W3', '경합(구조): 슬롯 생성 — 확인과 쓰기 사이 종료', (b) => !b.ok.blocked, (a) => a.ok.blocked],
  ['W4', '순차: 종료 사업장 공고 편집', (b) => !b.ok.blocked, (a) => a.ok.blocked],
  ['W5', '경합(구조): 관리자 일괄 출근', (b) => !b.ok.blocked, (a) => a.ok.blocked],
  ['W6', '경합(구조): 근로자 본인 출근', (b) => !b.ok.blocked, (a) => a.ok.blocked],
  ['W7', '순차: 추가 근무 승인 거절 · 휴무 승인 허용', (b) => !b.ok.blocked && b.ok.leaveOk, (a) => a.ok.blocked && a.ok.leaveOk],
  ['W8', '재실행 callable 권한·상태', (b) => true, (a) => a.ok.authz],
  ['W9', '대조: 운영 중 정상 흐름', (b) => b.ok.normal, (a) => a.ok.normal],
];

(async () => {
  if (LABEL) {
    const out = {};
    for (const [id] of EXPECT) { try { out[id] = await CELLS[id](); } catch (e) { RACE = null; out[id] = {out: 'THROW ' + e.message, ok: {}}; } }
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
    log(`${ok ? 'ok  ' : 'FAIL'} ${id} ${desc}\n       BEFORE → ${b.out}\n       AFTER  → ${a.out}`);
  }
  log(`\n셀 ${EXPECT.length} · 실패 ${fail}`);
  process.exit(fail ? 1 : 0);
})().catch((e) => { log('ERR ' + e.stack); process.exit(2); });
