/**
 * [BUSINESS-DELETE-CONTAINMENT] 구 앱(1.0.20) 사업장 삭제 — 선행 일괄 삭제 + 사업장 삭제 + 서버 정리, Rules 후보별.
 *
 *   구 앱 순서(HEAD business_list_screen._deleteBusiness) 그대로 REST(서명 없는 에뮬레이터 토큰)로 보낸다:
 *     workTypes 전부 · members 전부 → 499건씩 batch commit → businesses/{id} delete → (성공 시) onBusinessDeleted
 *   중단 위치: AFTER_BATCH(batch 커밋 뒤 앱 종료) · MID_CHUNKS(첫 batch 커밋 뒤 종료 — 600건 픽스처) · FULL(끝까지).
 *   서버 쪽(onBusinessDeleted · callableRemoveMember · callableLeaveAsSubAdmin · callableArchiveOwnBusiness)은
 *   BUNDLE 의 `.run`(Admin SDK, Rules 무관)이다. 에뮬레이터 전용(demo-alfit-r7).
 *     BUNDLE=<lib> RULES_DEV=<원문> RULES_BIZDEL=<…> RULES_CONTAIN=<…> RULES_COMPAT_CONTAIN=<…> node scripts/business-delete-containment-runtime.js
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
const fn = require(process.env.BUNDLE);
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
const {Timestamp} = admin.firestore;
const RUN = 'bc' + Date.now().toString(36);
let seq = 0; const uid = (p) => `${p}-${RUN}-${++seq}`;
const NOW = Date.now(); const DAY = 86400e3;

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
const loadRules = async (c) => { const r = await req('PUT', `/emulator/v1/projects/${PROJECT}:securityRules`, {rules: {files: [{name: 'firestore.rules', content: c}]}}); if (r.status !== 200) throw new Error('rules ' + r.status); };
const DB = `projects/${PROJECT}/databases/(default)`;
const commit = async (writes, who) => (await req('POST', `/v1/${DB}/documents:commit`, {writes}, emuToken(who))).status === 200 ? 'ALLOW' : 'DENY';
const delW = (p) => ({delete: `${DB}/documents/${p}`});
function val(v) {
  if (v === null) return {nullValue: null};
  if (typeof v === 'boolean') return {booleanValue: v};
  if (typeof v === 'number') return Number.isInteger(v) ? {integerValue: String(v)} : {doubleValue: v};
  return {stringValue: String(v)};
}
const updW = (p, fields) => ({update: {name: `${DB}/documents/${p}`, fields: Object.fromEntries(Object.entries(fields).map(([k, x]) => [k, val(x)]))},
  updateMask: {fieldPaths: Object.keys(fields)}, currentDocument: {exists: true}});

/** 사업장 + 업무유형 n개 + SubAdmin 멤버 + 공고·지원서(대기·확정·거절)·근태(급여 확정)·계약(완료·서명 대기). */
async function world(nWorkTypes = 2) {
  const b = uid('b'); const owner = uid('o'); const sub = uid('sub'); const w = uid('w');
  await db.doc(`users/${owner}`).set({role: 'BUSINESS_ADMIN', name: 'owner', businessId: b, accountStatus: 'active'});
  await db.doc(`users/${sub}`).set({role: 'USER', subAdminBusinessIds: [b], name: 'sub'});
  await db.doc(`businesses/${b}`).set({ownerId: owner, adminIds: [owner], name: 'b', isApproved: true, businessNumber: '1234567890', deactivatedAt: null,
    attendanceRules: {earlyWindow: 30}});
  for (let i = 0; i < nWorkTypes; i += 400) {
    const batch = db.batch();
    for (let k = i; k < Math.min(nWorkTypes, i + 400); k++) batch.set(db.doc(`businesses/${b}/workTypes/wt${k}`), {isActive: true, name: `QA${k}`, businessId: b});
    await batch.commit();
  }
  await db.doc(`businesses/${b}/members/${sub}`).set({permissions: {canManageTo: true, canManageWage: true, canManageWorkers: true}});
  const t = uid('t');
  await db.doc(`tos/${t}`).set({businessId: b, status: 'CLOSED', isPublished: true, title: 't', type: 'flex', totalSlots: 1});
  await db.doc(`tos/${t}/slots/s1`).set({toId: t, status: 'closed', date: Timestamp.fromMillis(NOW - 5 * DAY)});
  const apps = {};
  for (const st of ['PENDING', 'CONFIRMED', 'REJECTED']) {
    apps[st] = uid('a');
    await db.doc(`applications/${apps[st]}`).set({uid: w, businessId: b, toId: t, slotId: 's1', status: st, workDate: Timestamp.fromMillis(NOW - 5 * DAY), appliedAt: Timestamp.now()});
  }
  await db.doc(`attendance/${apps.CONFIRMED}_x`).set({applicationId: apps.CONFIRMED, userId: w, businessId: b, checkIn: Timestamp.fromMillis(NOW - 5 * DAY),
    checkOut: Timestamp.fromMillis(NOW - 5 * DAY + 3600e3), wageStatus: 'confirmed', status: 'present'});
  const c1 = uid('c'); const c2 = uid('c');
  await db.doc(`employment_contracts/${c1}`).set({businessId: b, workerId: w, applicationId: apps.CONFIRMED, status: 'completed'});
  await db.doc(`employment_contracts/${c2}`).set({businessId: b, workerId: w, applicationId: apps.PENDING, status: 'pending_worker'});
  return {b, owner, sub, w, t, apps, c1, c2};
}
async function census(x) {
  const e = async (p) => (await db.doc(p).get()).exists;
  const st = async (p) => { const d = (await db.doc(p).get()).data(); return d ? d.status : '없음'; };
  const wt = (await db.collection(`businesses/${x.b}/workTypes`).get()).size;
  const mem = (await db.collection(`businesses/${x.b}/members`).get()).size;
  return `사업장 ${await e(`businesses/${x.b}`) ? 'O' : 'X'} · 업무유형 ${wt} · 멤버 ${mem} · 공고 ${await e(`tos/${x.t}`) ? 'O' : 'X'} · ` +
    `지원서(대기/확정/거절) ${await st(`applications/${x.apps.PENDING}`)}/${await st(`applications/${x.apps.CONFIRMED}`)}/${await st(`applications/${x.apps.REJECTED}`)} · ` +
    `근태 ${await e(`attendance/${x.apps.CONFIRMED}_x`) ? 'O' : 'X'} · 계약(완료/서명대기) ${await st(`employment_contracts/${x.c1}`)}/${await st(`employment_contracts/${x.c2}`)}`;
}
/** 구 앱 _deleteBusiness — stopAt: 'AFTER_BATCH' | 'MID_CHUNKS' | 'FULL' */
async function oldAppDelete(x, stopAt) {
  const wt = (await db.collection(`businesses/${x.b}/workTypes`).get()).docs.map((d) => d.ref.path);
  const mem = (await db.collection(`businesses/${x.b}/members`).get()).docs.map((d) => d.ref.path);
  const refs = [...wt, ...mem]; const steps = [];
  const before = (await db.doc(`businesses/${x.b}`).get()).data();
  for (let i = 0; i < refs.length; i += 499) {
    const r = await commit(refs.slice(i, i + 499).map(delW), x.owner); steps.push(`batch${i / 499 + 1} ${r}`);
    if (r === 'DENY') return {steps, ui: '"사업장 삭제에 실패했습니다"(첫 실패에서 멈춤)'};
    if (stopAt === 'MID_CHUNKS') return {steps, ui: '(앱 종료)'};
  }
  if (stopAt === 'AFTER_BATCH') return {steps, ui: '(앱 종료)'};
  const r = await commit([delW(`businesses/${x.b}`)], x.owner); steps.push(`사업장 ${r}`);
  if (r === 'DENY') return {steps, ui: '"사업장 삭제에 실패했습니다"'};
  try { await fn.onBusinessDeleted.run({params: {businessId: x.b}, data: {exists: true, data: () => before, id: x.b, ref: db.doc(`businesses/${x.b}`)}}); steps.push('onBusinessDeleted'); } catch (e) { steps.push('onBusinessDeleted 오류'); }
  return {steps, ui: '"사업장이 삭제되었습니다"'};
}
const runCall = async (name, who, data) => { try { await fn[name].run({auth: {uid: who, token: {}}, rawRequest: {headers: {}}, data}); return 'OK'; } catch (e) { return (e.details && e.details.code) || e.code || 'ERR'; } };

(async () => {
  // RULES_SETS='[["라벨","경로"],...]' 가 있으면 그것을, 없으면 기본 네 세트를 쓴다.
  const sets = (process.env.RULES_SETS ? JSON.parse(process.env.RULES_SETS) : [['DEV 현재', process.env.RULES_DEV], ['사업장 delete만', process.env.RULES_BIZDEL],
    ['삭제 3종 봉쇄', process.env.RULES_CONTAIN], ['호환+삭제 3종', process.env.RULES_COMPAT_CONTAIN]]).map(([l, p]) => [l, fs.readFileSync(p, 'utf8')]);
  for (const [label, rules] of sets) {
    await loadRules(rules);
    log(`\n━━ ${label}`);
    for (const [stopAt, n] of [['FULL', 0], ['FULL', 2], ['AFTER_BATCH', 2], ['MID_CHUNKS', 600]]) {
      const x = await world(n); const r = await oldAppDelete(x, stopAt);
      // 부분 상태에서 새 앱 운영 종료·SubAdmin 권한
      const arch = (await db.doc(`businesses/${x.b}`).get()).exists ?
        await (async () => { try { const pv = await fn.callableArchiveOwnBusiness.run({auth: {uid: x.owner, token: {}}, rawRequest: {headers: {}}, data: {businessId: x.b, preview: true}});
          return pv.preview && pv.preview.canArchive ? '종료 가능' : '종료 사전조회 막힘'; } catch (e) { return 'ERR ' + (e.code || ''); } })() : '사업장 없음';
      const subPerm = (await db.doc(`businesses/${x.b}/members/${x.sub}`).get()).exists ? 'SubAdmin 권한 문서 있음' : 'SubAdmin 권한 문서 없음';
      log(`  구 앱 삭제[${stopAt}${n !== 2 ? ` 업무유형 ${n}` : ''}] ${r.steps.join(' → ')} · 앱 ${r.ui}\n     원장: ${await census(x)}\n     이후: 새 앱 운영 종료 ${arch} · ${subPerm}`);
    }
    // 정상 운영 회귀
    {
      const x = await world(3);
      const soft = await commit([updW(`businesses/${x.b}/workTypes/wt0`, {isActive: false})], x.owner);
      const add = await commit([{update: {name: `${DB}/documents/businesses/${x.b}/workTypes/new${RUN}`, fields: {isActive: val(true), name: val('NEW'), businessId: val(x.b)}}}], x.owner);
      const edit = await commit([updW(`businesses/${x.b}`, {name: '새이름'})], x.owner);
      const oneDel = await commit([delW(`businesses/${x.b}/workTypes/wt1`)], x.owner);
      const memDel = await commit([delW(`businesses/${x.b}/members/${x.sub}`)], x.owner);
      const cfRemove = await runCall('callableRemoveMember', x.owner, {businessId: x.b, uid: x.sub});
      const x2 = await world(1); const cfLeave = await runCall('callableLeaveAsSubAdmin', x2.sub, {businessId: x2.b});
      log(`  정상: 업무유형 소프트 삭제 ${soft} · 업무유형 추가 ${add} · 사업장 수정 ${edit} | 직접 단건: 업무유형 delete ${oneDel} · 멤버 delete ${memDel} | CF 멤버 제외 ${cfRemove} · CF 자진 해제 ${cfLeave}`);
    }
    // 새 앱 운영 종료(선삭제 없음)
    {
      const x = await world(2); const before = (await db.doc(`businesses/${x.b}`).get()).data(); let r = 'OK';
      try {
        const pv = await fn.callableArchiveOwnBusiness.run({auth: {uid: x.owner, token: {}}, rawRequest: {headers: {}}, data: {businessId: x.b, preview: true}});
        await fn.callableArchiveOwnBusiness.run({auth: {uid: x.owner, token: {}}, rawRequest: {headers: {}}, data: {businessId: x.b, expected: pv.preview}});
        const after = (await db.doc(`businesses/${x.b}`).get()).data();
        await fn.onBusinessDeactivated.run({params: {businessId: x.b}, data: {before: {exists: true, data: () => before}, after: {exists: true, data: () => after}}});
      } catch (e) { r = (e.details && e.details.code) || e.message; }
      log(`  새 앱 운영 종료 ${r} → ${await census(x)}`);
    }
  }
  await loadRules(fs.readFileSync(path.join(ROOT, 'firestore.rules'), 'utf8'));
  process.exit(0);
})().catch((e) => { log('ERR ' + e.stack); process.exit(2); });
