/**
 * [WORKTYPE-LOCAL-CLOSURE] D7 최종 저장 경로 · D4 수동 재개 · 업무유형 목록 페이지 질의 Rules.
 *
 *   D7: 실제 수정창 위젯이 만든 결과를 공고 수정 화면과 같은 copyWith·직렬화로 바꾼 payload(D7_PAYLOAD,
 *       flutter 에서 내보낸 JSON)를 그대로 callableUpdateTO / callableUpdateSlotWorkDetails 에 보내고 원장을 다시 읽는다.
 *   서버 셀은 BEFORE / AFTER 번들 각각 자식 프로세스. Rules 셀은 REST.
 *     BEFORE=<lib> AFTER=<lib> D7_PAYLOAD=<json> RULES_DEV=<원문> node scripts/worktype-closure-runtime.js
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
const LABEL = process.env.LABEL;
const fn = LABEL ? require(process.env[LABEL]) : null;
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
const {Timestamp} = admin.firestore;
const P = JSON.parse(fs.readFileSync(process.env.D7_PAYLOAD, 'utf8'));

const RUN = 'wc' + Date.now().toString(36);
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
  await db.doc(`businesses/${b}`).set({isApproved: true, ownerId: owner, adminIds: [owner], name: 'biz', city: '평택시', district: '평택시',
    address: '경기도 평택시 1', attendanceRules: RULES, latitude: 37, longitude: 127, gpsRadius: 100, deactivatedAt: null,
    attendancePolicyConfirmation: Object.assign({confirmedAt: Timestamp.now(), confirmedBy: owner, actorRole: 'business_admin'}, RULES),
    businessLicenseImageUrl: `https://firebasestorage.googleapis.com/v0/b/demo-alfit-r7.appspot.com/o/${encodeURIComponent(lic)}?alt=media`});
  // A(QA) 는 목록에서 사라졌다(비활성) · B 는 활성
  await db.doc(`businesses/${b}/workTypes/wt1`).set({isActive: false, name: 'QA', businessId: b, icon: '📦', createdAt: Timestamp.now()});
  await db.doc(`businesses/${b}/workTypes/wt2`).set({isActive: true, name: 'B', businessId: b, icon: '🚚', createdAt: Timestamp.now()});
  await db.doc(`businesses/${b}/contract_templates/tpl`).set({templateType: 'daily'});
  return {b, owner};
}
const A = () => JSON.parse(JSON.stringify(Object.assign({}, P.masterWageOnly[0], {wage: 12000})));
const baseTo = (x, o = {}) => Object.assign({businessId: x.b, businessName: 'biz', type: 'contract', title: `[${RUN}]`, description: 'wc',
  workDetails: [A()], totalSlots: 0, totalRequired: 1, totalConfirmed: 0, totalPending: 0,
  rangeStart: Timestamp.fromMillis(TODAY + 3 * DAY), rangeEnd: Timestamp.fromMillis(TODAY + 30 * DAY), workDays: ['월', '화', '수', '목', '금', '토', '일'],
  deadlineType: 'HOURS_BEFORE', hoursBeforeStart: 2, contractPeriodType: 'custom', postingDurationDays: 30,
  creatorUID: x.owner, isPublished: true, status: 'ACTIVE', isManualClosed: false, editRevision: 0, createdAt: Timestamp.now()}, o);
async function seedApp(x, t, status) {
  const a = uid('a');
  await db.doc(`applications/${a}`).set({uid: uid('w'), businessId: x.b, toId: t, status, type: 'long_term', isLongTerm: true, selectedWorkType: 'QA',
    workDetailId: 'QA_09:00_18:00', wage: 12000, wageType: 'hourly', startTime: '09:00', endTime: '18:00',
    workDate: Timestamp.fromMillis(TODAY + 3 * DAY), appliedAt: Timestamp.now(), businessName: 'biz'});
  if (status === 'CONFIRMED') await db.doc(`tos/${t}`).update({totalConfirmed: 1});
}
const show = (w) => w ? `${w.workType}/${w.workTypeIcon}/${w.workTypeColor}/${w.workTypeBackgroundColor}/${w.workTypeId || '∅'}·${w.wage}` : '-';

const CELLS = {
  D7M: async () => {
    const out = [];
    for (const [label, st, payload] of [['지원 없음', null, P.masterWageOnly], ['PENDING', 'PENDING', P.masterWageOnly], ['CONFIRMED', 'CONFIRMED', P.masterWageOnly],
      ['명시적 새 업무 B(지원 없음)', null, P.masterExplicitB], ['명시적 새 업무 B(PENDING)', 'PENDING', P.masterExplicitB]]) {
      const x = await biz(); const t = uid('t');
      await db.doc(`tos/${t}`).set(baseTo(x));
      if (st) await seedApp(x, t, st);
      const r = await call('callableUpdateTO', x.owner, {toId: t, expectedEditRevision: 0, updates: {title: 't2', workDetails: payload, totalRequired: 1}});
      const apps = (await db.collection('applications').where('toId', '==', t).get()).docs.map((d) => d.get('wage'));
      out.push(`${label}: ${r.err ? '거절(' + String(r.err).slice(0, 30) + ')' : 'OK'} → ${show((await read(`tos/${t}`)).workDetails[0])}${apps.length ? ' · 지원서 임금 ' + apps.join(',') : ''}`);
    }
    return out.join('\n           ');
  },
  D7S: async () => {
    const out = [];
    for (const [label, st] of [['지원 없음', null], ['PENDING', 'PENDING']]) {
      const x = await biz(); const t = uid('t');
      await db.doc(`tos/${t}`).set(baseTo(x, {type: 'flex', workDetails: [A()], totalSlots: 1}));
      await db.doc(`tos/${t}/slots/s1`).set({toId: t, status: 'open', isManualClosed: false, date: Timestamp.fromMillis(TODAY + 3 * DAY), workDetails: [A()],
        workDetailCounts: {wdA: {pendingCount: st ? 1 : 0, confirmedCount: 0}}, pendingCount: st ? 1 : 0, confirmedCount: 0, editRevision: 0});
      if (st) {
        await db.doc(`applications/${uid('a')}`).set({uid: uid('w'), businessId: x.b, toId: t, slotId: 's1', wdId: 'wdA', workDetailId: 'wdA', selectedWorkType: 'QA',
          status: st, type: 'short', workDate: Timestamp.fromMillis(TODAY + 3 * DAY), startTime: '09:00', endTime: '18:00', appliedAt: Timestamp.now()});
      }
      const r = await call('callableUpdateSlotWorkDetails', x.owner, {toId: t, slotId: 's1', workDetails: P.slotWageOnly, title: 't', expectedEditRevision: 0});
      out.push(`${label}: ${r.err ? '거절(' + String(r.err).slice(0, 30) + ')' : 'OK'} → 슬롯 ${show((await read(`tos/${t}/slots/s1`)).workDetails[0])}`);
    }
    return out.join('\n           ');
  },
  D4R: async () => {
    const out = [];
    for (const [label, mutate] of [['업무유형 0개 활성', async () => {}],
      ['+ 근태 기준 확인 없음', async (x) => db.doc(`businesses/${x.b}`).update({attendancePolicyConfirmation: admin.firestore.FieldValue.delete()})],
      ['+ 사업장 미승인', async (x) => db.doc(`businesses/${x.b}`).update({isApproved: false})]]) {
      const x = await biz(); const t = uid('t');
      await db.doc(`businesses/${x.b}/workTypes/wt2`).update({isActive: false}); // 마지막 활성 업무유형도 비활성
      await db.doc(`tos/${t}`).set(baseTo(x, {status: 'CLOSED', isManualClosed: true, closedBy: x.owner, closedAt: Timestamp.now()}));
      await mutate(x);
      // 앱 재개 요청 모양: isManualClosed:false + status ACTIVE (edit_to_screen wasClosed 분기)
      const r = await call('callableUpdateTO', x.owner, {toId: t, expectedEditRevision: 0, updates: {title: 'reopen', isManualClosed: false, status: 'ACTIVE'}});
      const d = await read(`tos/${t}`);
      out.push(`${label}: ${r.err ? '막힘(' + String(r.err).slice(0, 44) + ')' : 'OK'} → ${d.status}/수동마감 ${d.isManualClosed}`);
    }
    return out.join('\n           ');
  },
};

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
const DBP = `projects/${PROJECT}/databases/(default)`;

(async () => {
  if (LABEL) {
    const out = {};
    for (const id of Object.keys(CELLS)) { try { out[id] = await CELLS[id](); } catch (e) { out[id] = 'THROW ' + e.message; } }
    log('@@' + JSON.stringify(out)); process.exit(0);
  }
  const {execFileSync} = require('child_process');
  const got = {};
  for (const L of ['BEFORE', 'AFTER']) {
    const o = execFileSync(process.execPath, [__filename], {env: Object.assign({}, process.env, {LABEL: L}), maxBuffer: 1 << 26}).toString();
    got[L] = JSON.parse(o.split('@@').pop());
  }
  for (const id of Object.keys(CELLS)) log(`${id}\n   BEFORE → ${got.BEFORE[id]}\n   AFTER  → ${got.AFTER[id]}`);
  // 업무유형 목록 페이지 질의(앱 getBusinessWorkTypeCatalog 와 같은 모양) — 근로자 토큰
  for (const [label, file] of [['DEV 원문', process.env.RULES_DEV], ['후보 worktype-identity', path.join(ROOT, 'rules_candidates', 'firestore.worktype-identity.rules')]]) {
    await req('PUT', `/emulator/v1/projects/${PROJECT}:securityRules`, {rules: {files: [{name: 'firestore.rules', content: fs.readFileSync(file, 'utf8')}]}});
    const b = uid('b'); const w = uid('w');
    await db.doc(`users/${w}`).set({role: 'USER'});
    for (let i = 0; i < 5; i++) await db.doc(`businesses/${b}/workTypes/w${i}`).set({name: `N${i}`, isActive: i % 2 === 0, businessId: b});
    const q = (startAfter) => req('POST', `/v1/${DBP}/documents/businesses/${b}:runQuery`, {structuredQuery: {from: [{collectionId: 'workTypes'}],
      orderBy: [{field: {fieldPath: '__name__'}, direction: 'ASCENDING'}], limit: 2,
      ...(startAfter ? {startAt: {values: [{referenceValue: `${DBP}/documents/businesses/${b}/workTypes/${startAfter}`}], before: false}} : {})}}, emuToken(w));
    const p1 = await q(null); const p2 = await q('w1');
    const n = (r) => r.status === 200 ? JSON.parse(r.body).filter((x) => x.document).length : 'DENY';
    log(`\n━━ Rules(${label}) 근로자 목록 페이지 질의: 1쪽 ${n(p1)}건 · 다음 쪽(w1 다음) ${n(p2)}건`);
  }
  await req('PUT', `/emulator/v1/projects/${PROJECT}:securityRules`, {rules: {files: [{name: 'firestore.rules', content: fs.readFileSync(path.join(ROOT, 'firestore.rules'), 'utf8')}]}});
  process.exit(0);
})().catch((e) => { log('ERR ' + e.stack); process.exit(2); });
