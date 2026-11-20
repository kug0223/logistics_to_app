/**
 * [ARCHIVE-RULES-COMPAT] 혼합 버전 배포 순서 — (서버 번들) × (Rules) 조합을 실제 요청 모양으로 잰다.
 *
 *   서버 쪽 동작은 Admin SDK 라 Rules 와 무관하다 → 번들별로 한 번(자식 프로세스, 번들마다 initializeApp).
 *     "현재 DEV 서버" 는 **함수마다 DEV 에서 받은 배포본**(scratchpad wf-dep-<함수>/lib)이다.
 *   클라이언트 직접 쓰기는 Rules 와만 관계있다 → Rules 마다 한 번(REST + 서명 없는 에뮬레이터 토큰).
 *   구 앱의 "종료 사업장 공고 편집" 은 서버(UpdateTO)와 직접 쓰기(슬롯 마감 시각 재계산)가 이어진
 *   흐름이라 네 조합 모두 따로 잰다.
 *     SERVER_OLD_DIR=<wf-dep- 접두 폴더들이 있는 곳> SERVER_NEW=<lib/index.js> DEV_RULES=<원문> CAND_RULES=<후보>
 *       node scripts/archive-mixed-version-runtime.js
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
const CHILD = process.env.CHILD_OP; // 자식: 이 서버 동작 하나를 BUNDLE 로 실행
const fn = CHILD ? require(process.env.BUNDLE) : null;
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
const {Timestamp} = admin.firestore;
const RUN = 'mx' + Date.now().toString(36) + (process.env.SALT || '');
const K = 9 * 3600e3; const NOW = Date.now(); const DAY = 86400e3;
const TODAY = (() => { const d = new Date(NOW + K); return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()) - K; })();
let seq = 0; const uid = (p) => `${p}-${RUN}-${++seq}`;
const read = async (p) => (await db.doc(p).get()).data();
const RULES = {earlyWindow: 30, earlyArrivalUnit: 10, lateGrace: 5, lateUnit: 10, lateWindow: 600, overtimeUnit: 10, earlyLeaveUnit: 10};
async function biz(closed) {
  const b = uid('b'); const owner = uid('o');
  await db.doc(`users/${owner}`).set({role: 'BUSINESS_ADMIN', sealBase64: 'x', businessId: b, name: 'owner'});
  const lic = `businesses/${b}/license/license.jpg`;
  await admin.storage().bucket().file(lic).save(Buffer.from('x'));
  await db.doc(`businesses/${b}`).set({isApproved: !closed, ownerId: owner, adminIds: [owner], name: 'biz', city: '평택시', address: '경기도 평택시 1',
    attendanceRules: RULES, latitude: 37, longitude: 127, businessNumber: '1234567890',
    deactivatedAt: closed ? Timestamp.fromMillis(NOW - 3600e3) : null,
    attendancePolicyConfirmation: Object.assign({confirmedAt: Timestamp.now(), confirmedBy: owner, actorRole: 'business_admin'}, RULES),
    businessLicenseImageUrl: `https://firebasestorage.googleapis.com/v0/b/demo-alfit-r7.appspot.com/o/${encodeURIComponent(lic)}?alt=media`});
  await db.doc(`businesses/${b}/workTypes/wt1`).set({isActive: true, name: 'QA'});
  await db.doc(`businesses/${b}/contract_templates/tpl`).set({templateType: 'daily'});
  return {b, owner};
}
const wds = (closed) => [{id: 'wd1', wdId: 'wd1', workType: 'QA', requiredCount: 2, ...(closed ? {isManualClosed: true} : {})}];
async function closedPosting(x, o = {}) {
  const t = uid('t');
  await db.doc(`tos/${t}`).set(Object.assign({businessId: x.b, creatorUID: x.owner, status: 'CLOSED', closedReason: 'BUSINESS_DEACTIVATED', type: 'flex',
    isPublished: true, title: 't', editRevision: 0, totalConfirmed: 0, totalPending: 0, totalSlots: 1, totalRequired: 2, workDetails: wds(false)}, o));
  await db.doc(`tos/${t}/slots/s1`).set({toId: t, status: 'closed', isManualClosed: true, workDetails: wds(true),
    date: Timestamp.fromMillis(TODAY + 5 * DAY), confirmedCount: 0, pendingCount: 0, workDetailCounts: {}});
  return t;
}
async function call(name, who, data) {
  try { await fn[name].run({auth: {uid: who, token: {}}, rawRequest: {headers: {}}, data}); return 'OK'; } catch (e) {
    return (e.details && (e.details.code || e.details.reason)) || `${e.code || 'ERR'}`;
  }
}

// ── 서버 동작(자식에서 실행)
const SERVER_OPS = {
  reopenSlots: async () => {
    const x = await biz(true); const t = await closedPosting(x);
    const r = await call('callableReopenSlots', x.owner, {toId: t, slotIds: ['s1'], businessId: x.b});
    return `${r} → 공고 ${(await read(`tos/${t}`)).status} · 슬롯 ${(await read(`tos/${t}/slots/s1`)).status}`;
  },
  updateToActive: async () => {
    const x = await biz(true); const t = await closedPosting(x);
    const r = await call('callableUpdateTO', x.owner, {toId: t, updates: {status: 'ACTIVE'}, expectedEditRevision: 0});
    return `${r} → 공고 ${(await read(`tos/${t}`)).status}`;
  },
  createFlexSlots: async () => {
    const x = await biz(true); const t = await closedPosting(x, {status: 'SCHEDULED', isPublished: false, totalSlots: 0});
    const r = await call('callableCreateFlexSlots', x.owner, {toId: t, businessId: x.b, dates: [new Date(TODAY + 9 * DAY + K).toISOString().slice(0, 10)],
      workDetails: [{workType: 'QA', startTime: '14:00', endTime: '15:00', requiredCount: 1, wage: 12000, wageType: 'hourly', payScheduleType: 'next_day'}],
      deadlineType: 'HOURS_BEFORE', hoursBeforeStart: 1});
    return `${r} → 새 슬롯 ${(await db.collection(`tos/${t}/slots`).get()).size - 1}개`;
  },
  publishTo: async () => {
    const x = await biz(true); const t = uid('t');
    await db.doc(`tos/${t}`).set({businessId: x.b, creatorUID: x.owner, status: 'DRAFT', isPublished: false, type: 'contract', title: 't',
      workDetails: [{workType: 'QA', startTime: '09:00', endTime: '18:00', requiredCount: 1, wage: 12000, wageType: 'hourly'}],
      rangeStart: TODAY + 3 * DAY, rangeEnd: TODAY + 30 * DAY, totalSlots: 0, totalRequired: 1, totalConfirmed: 0, totalPending: 0, editRevision: 0});
    const r = await call('callablePublishTO', x.owner, {toId: t});
    return `${r} → 게시 ${(await read(`tos/${t}`)).isPublished === true}`;
  },
  // 구 앱의 종료 사업장 공고 편집 1단계(서버) — 결과 공고 id 를 넘겨 2단계(직접 쓰기)는 부모가 한다
  editClosedStep1: async () => {
    const x = await biz(true); const t = await closedPosting(x);
    const r = await call('callableUpdateTO', x.owner, {toId: t, updates: {description: '편집'}, expectedEditRevision: 0});
    return JSON.stringify({r, t, owner: x.owner});
  },
};

// ── 클라이언트 직접 쓰기(부모에서, Rules 평가)
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
const loadRules = async (content) => {
  const r = await req('PUT', `/emulator/v1/projects/${PROJECT}:securityRules`, {rules: {files: [{name: 'firestore.rules', content}]}});
  if (r.status !== 200) throw new Error('rules 적재 실패 ' + r.status);
};
const DB = `projects/${PROJECT}/databases/(default)`;
function val(v) {
  if (v === null) return {nullValue: null};
  if (v instanceof Date) return {timestampValue: v.toISOString()};
  if (Array.isArray(v)) return {arrayValue: {values: v.map(val)}};
  if (typeof v === 'boolean') return {booleanValue: v};
  if (typeof v === 'number') return Number.isInteger(v) ? {integerValue: String(v)} : {doubleValue: v};
  if (typeof v === 'string') return {stringValue: v};
  return {mapValue: {fields: Object.fromEntries(Object.entries(v).map(([k, x]) => [k, val(x)]))}};
}
const DEL = Symbol('del');
async function update(docPath, fields, who) {
  const plain = Object.entries(fields).filter(([, x]) => x !== DEL);
  const w = {update: {name: `${DB}/documents/${docPath}`, fields: Object.fromEntries(plain.map(([k, x]) => [k, val(x)]))},
    updateMask: {fieldPaths: Object.keys(fields)}, currentDocument: {exists: true}};
  return (await req('POST', `/v1/${DB}/documents:commit`, {writes: [w]}, emuToken(who))).status === 200 ? 'ALLOW' : 'DENY';
}
async function del(docPath, who) {
  return (await req('DELETE', `/v1/${DB}/documents/${docPath}`, null, emuToken(who))).status === 200 ? 'ALLOW' : 'DENY';
}
const deadlineReopen = {workDetails: wds(false), applicationDeadline: new Date(NOW + 2 * DAY), status: 'open', isManualClosed: false, closedAt: DEL};
const CLIENT_OPS = {
  clearDeactivatedAt: async () => { const x = await biz(true); return update(`businesses/${x.b}`, {deactivatedAt: DEL}, x.owner); },
  forgeCascade: async () => { const x = await biz(true); return update(`businesses/${x.b}`, {archiveCascade: {state: 'COMPLETE'}}, x.owner); },
  slotReopenClosedBiz: async () => { const x = await biz(true); const t = await closedPosting(x); return update(`tos/${t}/slots/s1`, deadlineReopen, x.owner); },
  slotReopenOpenBiz: async () => { const x = await biz(false); const t = await closedPosting(x, {status: 'ACTIVE', closedReason: null});
    return update(`tos/${t}/slots/s1`, deadlineReopen, x.owner); },
  oldAppCreateRollback: async () => { // 구 앱: 생성 실패 → 부분 슬롯·공고 직접 삭제(운영 중 사업장)
    const x = await biz(false); const t = await closedPosting(x, {status: 'SCHEDULED', isPublished: false, closedReason: null});
    const a = await del(`tos/${t}/slots/s1`, x.owner); const b = await del(`tos/${t}`, x.owner); return `${a}/${b}`;
  },
  oldAppBusinessHardDelete: async () => { const x = await biz(false); return del(`businesses/${x.b}`, x.owner); },
};

(async () => {
  if (CHILD) { const out = await SERVER_OPS[CHILD](); log('@@' + JSON.stringify(out)); process.exit(0); }
  const {execFileSync} = require('child_process');
  const oldDir = process.env.SERVER_OLD_DIR; const NEW = process.env.SERVER_NEW;
  const OLD_OF = {reopenSlots: 'callableReopenSlots', updateToActive: 'callableUpdateTO', createFlexSlots: 'callableCreateFlexSlots',
    publishTo: 'callablePublishTO', editClosedStep1: 'callableUpdateTO'};
  const runChild = (op, bundle) => JSON.parse(execFileSync(process.execPath, [__filename], {env: Object.assign({}, process.env,
    {CHILD_OP: op, BUNDLE: bundle, SALT: String(Math.random()).slice(2, 6)}), maxBuffer: 1 << 24}).toString().split('@@').pop());
  const oldB = (op) => path.join(oldDir, `wf-dep-${OLD_OF[op]}`, 'lib', 'index.js');
  // 서버 동작: 번들별
  const server = {};
  for (const op of ['reopenSlots', 'updateToActive', 'createFlexSlots', 'publishTo']) {
    server[op] = {old: runChild(op, oldB(op)), neu: runChild(op, NEW)};
  }
  // 클라이언트 직접 쓰기: Rules 별
  const DEV = fs.readFileSync(process.env.DEV_RULES, 'utf8'); const CAND = fs.readFileSync(process.env.CAND_RULES, 'utf8');
  const client = {};
  for (const [label, rules] of [['dev', DEV], ['cand', CAND]]) {
    await loadRules(rules);
    for (const [op, f] of Object.entries(CLIENT_OPS)) (client[op] = client[op] || {})[label] = await f();
  }
  // 구 앱 종료 사업장 공고 편집(서버 → 직접 쓰기) — 네 조합
  const edit = {};
  for (const [srv, bundle] of [['old', oldB('editClosedStep1')], ['neu', NEW]]) {
    for (const [rl, rules] of [['dev', DEV], ['cand', CAND]]) {
      const s1 = JSON.parse(runChild('editClosedStep1', bundle));
      let s2 = '(1단계 거절 → 앱이 멈춤)';
      if (s1.r === 'OK') { await loadRules(rules); s2 = await update(`tos/${s1.t}/slots/s1`, deadlineReopen, s1.owner); }
      const slot = await read(`tos/${s1.t}/slots/s1`); const to = await read(`tos/${s1.t}`);
      edit[`${srv}+${rl}`] = `서버 ${s1.r} · 슬롯 쓰기 ${s2} → 설명 ${to.description === '편집' ? '바뀜' : '그대로'} · 슬롯 ${slot.status}`;
    }
  }
  await loadRules(fs.readFileSync(path.join(ROOT, 'firestore.rules'), 'utf8'));
  log('── 서버 동작 (운영 종료 사업장, Admin SDK — Rules 무관)');
  for (const [op, v] of Object.entries(server)) log(`  ${op.padEnd(16)} 현재 DEV 서버: ${v.old}\n  ${''.padEnd(16)} 새 서버:       ${v.neu}`);
  log('── 클라이언트 직접 쓰기 (Rules 평가)');
  for (const [op, v] of Object.entries(client)) log(`  ${op.padEnd(24)} DEV Rules ${v.dev} · 호환 후보 ${v.cand}`);
  log('── 구 앱: 종료 사업장 공고 편집(서버 UpdateTO → 슬롯 마감 시각 직접 쓰기)');
  for (const [k, v] of Object.entries(edit)) log(`  ${k.padEnd(10)} ${v}`);
  process.exit(0);
})().catch((e) => { log('ERR ' + e.stack); process.exit(2); });
