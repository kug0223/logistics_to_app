/**
 * [ARCHIVE-ACTIVE-PARTIAL] 이미 공개된 flex 공고에 새 날짜 801건을 추가하다 첫 묶음 뒤 중단 — 실제 노출·지원·초대·
 *   스케줄러·통계 트리거·재시도·삭제 경로.
 *
 *   같은 seed 를 BEFORE / AFTER 번들에 각각 올린다(번들마다 initializeApp → 자식 프로세스 하나씩).
 *   중단 방식(MODE): FAIL(두 번째 묶음 throw) · CLOSE(첫 묶음 직후 운영 종료) · LOST(전부 저장, 응답만 유실 = 정상 완료).
 *   실행하는 것(전부 실제 번들 `.run` / 실제 Rules):
 *     · 근로자 공고 목록  callableGetPublishedTOsPaged
 *     · 근로자 날짜 목록  앱 reader 와 같은 질의(tos/{id}/slots orderBy date) — REST + 근로자 토큰(Rules 평가)
 *     · 지원            callableApplyToTO (부분 저장된 새 날짜)
 *     · 초대            callableInviteWorker (부분 저장된 새 날짜)
 *     · masterScheduler.run · syncTOStats.run(지원·초대 쓰기 이벤트를 그대로 넘긴다)
 *     · 같은 요청 재시도 · callableDeleteTO(공식 삭제)
 *     MODE=FAIL BEFORE=<lib> AFTER=<lib> node scripts/archive-active-partial-runtime.js
 */
'use strict';
const fs = require('fs');
const path = require('path');
const http = require('http');
const ROOT = path.join(__dirname, '..');
const PROJECT = 'demo-alfit-r7';
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:6070';
process.env.GCLOUD_PROJECT = PROJECT;
process.env.FIREBASE_CONFIG = JSON.stringify({projectId: PROJECT, storageBucket: 'demo-alfit-r7.appspot.com'});
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
const LABEL = process.env.LABEL;
const fn = LABEL ? require(process.env[LABEL]) : null;
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
const {Timestamp} = admin.firestore;
const MODE = process.env.MODE || 'FAIL';

let ARM = null; let txSeen = 0; let closeBiz = null;
const origRunTx = FS.Firestore.prototype.runTransaction;
FS.Firestore.prototype.runTransaction = async function (...a) {
  if (ARM) txSeen++;
  if (ARM === 'FAIL' && txSeen === 2) { ARM = null; throw new Error('INJECTED chunk failure'); }
  const r = await origRunTx.apply(this, a);
  if (ARM === 'CLOSE' && txSeen === 1) { ARM = null; await db.doc(`businesses/${closeBiz}`).update({deactivatedAt: Timestamp.now(), isApproved: false}); }
  return r;
};

const RUN = 'ap' + Date.now().toString(36);
const K = 9 * 3600e3; const NOW = Date.now(); const DAY = 86400e3;
const kstMidnight = (ms) => { const d = new Date(ms + K); return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()) - K; };
const TODAY = kstMidnight(NOW);
const ymdDash = (ms) => new Date(ms + K).toISOString().slice(0, 10);
let seq = 0; const uid = (p) => `${p}-${RUN}-${++seq}`;
const read = async (p) => (await db.doc(p).get()).data();
async function call(name, who, data) {
  try { return {ok: await fn[name].run({auth: {uid: who, token: {}}, rawRequest: {headers: {}}, data})}; } catch (e) {
    return {err: (e.details && (e.details.code || e.details.reason)) || `${e.code || ''}:${String(e.message).slice(0, 60)}`};
  }
}
const RULES = {earlyWindow: 30, earlyArrivalUnit: 10, lateGrace: 5, lateUnit: 10, lateWindow: 60, overtimeUnit: 10, earlyLeaveUnit: 10};
const F7 = ['earlyWindow', 'earlyArrivalUnit', 'lateGrace', 'lateUnit', 'lateWindow', 'overtimeUnit', 'earlyLeaveUnit'];
const FP = F7.map((k) => `${k}=${RULES[k]}`).join('|');
const WD = {wdId: 'wdA', workType: 'QA', startTime: '14:00', endTime: '15:00', requiredCount: 2, wage: 12000, wageType: 'hourly', payScheduleType: 'next_day'};

function emuToken(u) {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url'); const now = Math.floor(Date.now() / 1000);
  return `${b64({alg: 'none', typ: 'JWT'})}.${b64({iss: `https://securetoken.google.com/${PROJECT}`, aud: PROJECT, auth_time: now, user_id: u, sub: u,
    iat: now, exp: now + 3600, firebase: {identities: {}, sign_in_provider: 'custom'}})}.`;
}
function req(method, p, body, token) {
  return new Promise((res, rej) => {
    const data = body ? JSON.stringify(body) : null;
    const r = http.request({host: '127.0.0.1', port: 6070, method, path: p, headers: Object.assign({'Content-Type': 'application/json'},
      token ? {Authorization: 'Bearer ' + token} : {}, data ? {'Content-Length': Buffer.byteLength(data)} : {})}, (x) => {
      const bufs = []; x.on('data', (c) => bufs.push(c)); x.on('end', () => res({status: x.statusCode, body: Buffer.concat(bufs).toString('utf8')}));
    });
    r.on('error', rej); if (data) r.write(data); r.end();
  });
}
/** 앱 reader(_flexSlotSnapshot)와 같은 질의를 근로자 토큰으로 — Rules 가 평가한다. */
async function workerSlotQuery(toId, who) {
  const r = await req('POST', `/v1/projects/${PROJECT}/databases/(default)/documents/tos/${toId}:runQuery`,
    {structuredQuery: {from: [{collectionId: 'slots'}], orderBy: [{field: {fieldPath: 'date'}}], limit: 1001}}, emuToken(who));
  if (r.status !== 200) return {err: r.status};
  const rows = JSON.parse(r.body).filter((x) => x.document);
  return {count: rows.length, open: rows.filter((x) => (x.document.fields.status || {}).stringValue === 'open').length};
}

async function world() {
  const b = uid('b'); const owner = uid('o');
  await db.doc(`users/${owner}`).set({role: 'BUSINESS_ADMIN', sealBase64: 'x', businessId: b, name: 'owner', accountStatus: 'active'});
  const lic = `businesses/${b}/license/license.jpg`;
  await admin.storage().bucket().file(lic).save(Buffer.from('x'));
  await db.doc(`businesses/${b}`).set({isApproved: true, ownerId: owner, adminIds: [owner], name: 'biz', city: '평택시', district: '평택시',
    address: '경기도 평택시 1', attendanceRules: RULES, latitude: 37, longitude: 127, deactivatedAt: null,
    attendancePolicyConfirmation: Object.assign({confirmedAt: Timestamp.now(), confirmedBy: owner, actorRole: 'business_admin'}, RULES),
    businessLicenseImageUrl: `https://firebasestorage.googleapis.com/v0/b/demo-alfit-r7.appspot.com/o/${encodeURIComponent(lic)}?alt=media`});
  await db.doc(`businesses/${b}/workTypes/wt1`).set({isActive: true, name: 'QA'});
  await db.doc(`businesses/${b}/contract_templates/tpl`).set({templateType: 'daily'});
  // 공개 중인 flex 공고 + 정상 날짜 2개 + 기존 대기 지원 1건(관계 이력)
  const t = uid('t'); const d1 = TODAY + 2 * DAY; const d2 = TODAY + 3 * DAY;
  await db.doc(`tos/${t}`).set({businessId: b, businessName: 'biz', creatorUID: owner, type: 'flex', title: 't', status: 'ACTIVE', isPublished: true,
    publishMode: 'immediate', totalSlots: 2, totalRequired: 4, totalConfirmed: 0, totalPending: 1, dates: [ymdDash(d1), ymdDash(d2)],
    workDetails: [WD], businessCity: '평택시', createdAt: Timestamp.now(), editRevision: 0});
  for (const [id, d, p] of [['old1', d1, 1], ['old2', d2, 0]]) {
    await db.doc(`tos/${t}/slots/${id}`).set({toId: t, status: 'open', isManualClosed: false, date: Timestamp.fromMillis(d), workDetails: [WD],
      workDetailCounts: {wdA: {pendingCount: p, confirmedCount: 0}}, pendingCount: p, confirmedCount: 0, editRevision: 0});
  }
  const w0 = await worker(b, null);
  const oldApp = uid('a');
  await db.doc(`applications/${oldApp}`).set({uid: w0, businessId: b, toId: t, slotId: 'old1', wdId: 'wdA', selectedWorkType: 'QA', status: 'PENDING',
    type: 'short', workDate: Timestamp.fromMillis(d1), startTime: '14:00', endTime: '15:00', appliedAt: Timestamp.now(), statusHistory: []});
  return {b, owner, t, oldApp};
}
async function worker(b, availDate) {
  const w = uid('w');
  await db.doc(`users/${w}`).set({uid: w, name: 'w', role: 'USER', accountStatus: 'active', passVerifiedAt: Timestamp.now(),
    isIdVerified: true, idCardImagePath: `id_cards/${w}/id.jpg`, bankName: '국민', accountNumber: 'enc', accountHolder: 'w',
    bankbookImagePath: `bankbooks/${w}/b.jpg`, termsConsentAt: Timestamp.now(), isBlacklisted: false, isForeign: false,
    idDocumentVersion: 1, bankbookDocumentVersion: 1, bankAccountVersion: 1, homeRegion: '경기도|평택시'});
  await db.doc(`businessApplicantDocumentReviews/${b}_${w}`).set({businessId: b, workerUid: w, idDecision: 'REVIEWED_OK', reviewedIdDocumentVersion: 1,
    bankDecision: 'REVIEWED_OK', reviewedBankbookDocumentVersion: 1, reviewedBankAccountVersion: 1});
  if (availDate) await db.doc(`worker_availability/${w}`).set({uid: w, inviteEnabled: true, inviteRegionKeys: ['경기도|평택시'], dates: [availDate]});
  return w;
}
const newDates = Array.from({length: 801}, (_, k) => ymdDash(TODAY + (5 + k) * DAY));
const flex = (x) => call('callableCreateFlexSlots', x.owner, {toId: x.t, businessId: x.b, dates: newDates,
  workDetails: [{workType: 'QA', startTime: '14:00', endTime: '15:00', requiredCount: 2, wage: 12000, wageType: 'hourly', payScheduleType: 'next_day'}],
  deadlineType: 'HOURS_BEFORE', hoursBeforeStart: 1});
async function ledger(x) {
  const slots = await db.collection(`tos/${x.t}/slots`).get(); const to = await read(`tos/${x.t}`);
  const apps = await db.collection('applications').where('toId', '==', x.t).get();
  const pend = apps.docs.filter((a) => a.get('status') === 'PENDING').length; const inv = apps.docs.filter((a) => a.get('status') === 'INVITED').length;
  const slotPendSum = slots.docs.reduce((s, d) => s + (d.get('pendingCount') || 0), 0);
  return {slots: slots.size, totalSlots: to.totalSlots, dates: (to.dates || []).length, write: to.slotWrite ? to.slotWrite.state : '-', status: to.status,
    published: to.isPublished === true, deleted: to.isDeleted === true, appPending: pend, appInvited: inv, totalPending: to.totalPending,
    slotPendingSum: slotPendSum, oldApp: (await read(`applications/${x.oldApp}`)).status};
}
const L = (o) => `슬롯 ${o.slots} · totalSlots ${o.totalSlots} · dates ${o.dates} · 표식 ${o.write} · ${o.status}${o.published ? '/공개' : ''}${o.deleted ? '/삭제' : ''}` +
  ` · 대기 지원 ${o.appPending}·초대 ${o.appInvited} | 공고 totalPending ${o.totalPending} · 슬롯 pending 합 ${o.slotPendingSum} · 기존 지원 ${o.oldApp}`;

async function child() {
  const x = await world(); const out = [];
  ARM = MODE === 'LOST' ? null : MODE; txSeen = 0; closeBiz = x.b;
  const r = await flex(x); ARM = null;
  out.push(`추가 ${r.err || 'OK'} → ${L(await ledger(x))}`);
  // 근로자 목록·날짜
  const wList = await worker(x.b, null);
  const list = await call('callableGetPublishedTOsPaged', wList, {pageSize: 50});
  const items = list.ok && (list.ok.items || list.ok.tos || list.ok.data || []);
  const mine = Array.isArray(items) ? items.find((i) => (i.id || i.toId) === x.t) : null;
  out.push(`근로자 목록 ${list.err || (mine ? `노출(totalSlots ${mine.totalSlots}, dates ${(mine.dates || []).length})` : '미노출')}`);
  const q = await workerSlotQuery(x.t, wList);
  out.push(`근로자 날짜 질의 ${q.err ? 'ERR ' + q.err : `${q.count}개(open ${q.open})`}`);
  // 부분 저장된 새 날짜(첫 번째 새 날짜)에 지원·초대
  const newSlot = (await db.collection(`tos/${x.t}/slots`).where('date', '==', Timestamp.fromMillis(TODAY + 5 * DAY)).get()).docs[0];
  if (newSlot) {
    const wdId = (newSlot.get('workDetails') || [])[0].wdId;
    const wa = await worker(x.b, null);
    const ap = await call('callableApplyToTO', wa, {toId: x.t, slotId: newSlot.id, businessId: x.b, businessName: 'biz', toTitle: 't',
      workDateMs: TODAY + 5 * DAY, selectedWorkType: 'QA', workDetailId: wdId, startTime: '14:00', endTime: '15:00', wage: 12000, wageType: 'hourly',
      idCardConsentGiven: true, documentAccessConsentGiven: true, documentAccessConsentVersion: '2026-09-18-v3', expectedAttendancePolicy: FP});
    const wi = await worker(x.b, ymdDash(TODAY + 5 * DAY).replace(/-/g, '-'));
    const iv = await call('callableInviteWorker', x.owner, {toId: x.t, businessId: x.b, targetUid: wi, slotId: newSlot.id,
      workDate: ymdDash(TODAY + 5 * DAY), selectedWorkType: 'QA', workDetailStartTime: '14:00', workDetailEndTime: '15:00'});
    out.push(`새 날짜 지원 ${ap.err || 'OK'} · 초대 ${iv.err || 'OK'}`);
  } else out.push('새 날짜 슬롯 없음(지원·초대 해당 없음)');
  // syncTOStats — 이 공고 지원서 쓰기 이벤트를 그대로 넘긴다(생성 이벤트)
  const before = await ledger(x);
  const apps = await db.collection('applications').where('toId', '==', x.t).get();
  for (const a of apps.docs) {
    try { await fn.syncTOStats.run({params: {applicationId: a.id}, data: {before: {exists: false, data: () => undefined}, after: {exists: true, data: () => a.data()}}}); } catch (_) { /* 기록 */ }
  }
  out.push(`syncTOStats 전 [totalPending ${before.totalPending} · 슬롯합 ${before.slotPendingSum}] 후 → ${L(await ledger(x))}`);
  // masterScheduler
  try { await fn.masterScheduler.run({}); } catch (_) { /* allSettled */ }
  out.push(`masterScheduler 후 → ${L(await ledger(x))} · 근로자 날짜 ${(await workerSlotQuery(x.t, wList)).count}개`);
  // 같은 요청 재시도
  const r2 = await flex(x);
  out.push(`재시도 ${r2.err || 'OK'} → ${L(await ledger(x))}`);
  // 공식 삭제
  const del = await call('callableDeleteTO', x.owner, {toId: x.t});
  out.push(`공식 삭제 ${del.err || 'OK'} → ${L(await ledger(x))}`);
  log('@@' + JSON.stringify(out)); process.exit(0);
}

(async () => {
  if (LABEL) return child();
  const {execFileSync} = require('child_process');
  for (const lb of ['BEFORE', 'AFTER']) {
    const o = execFileSync(process.execPath, [__filename], {env: Object.assign({}, process.env, {LABEL: lb}), maxBuffer: 1 << 26}).toString();
    const lines = JSON.parse(o.split('@@').pop());
    log(`── ${lb} (MODE=${MODE})`); for (const l of lines) log('  ' + l);
  }
  process.exit(0);
})().catch((e) => { log('ERR ' + e.stack); process.exit(2); });
