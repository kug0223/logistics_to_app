/**
 * [BUSINESS-DELETE-ISOLATION] 사업장 문서 직접 삭제만 막은 Rules 후보 — 구 앱 요청 순서 그대로 + 후속 연쇄.
 *
 *   구 앱(HEAD business_list_screen._deleteBusiness)의 실제 순서:
 *     ① workTypes 전부 batch.delete → ② members 전부 batch.delete → ③ businesses/{id}.delete()
 *     → (성공 시) Storage 정리 · 서버 onBusinessDeleted 가 공고·지원서를 정리
 *   이 순서를 DEV 활성 Rules 와 후보에 각각 REST(서명 없는 에뮬레이터 토큰)로 보내고, ③이 허용된 경우에만
 *   후보 번들의 onBusinessDeleted 를 같은 이벤트 모양으로 돌려 남는 것을 센다.
 *   함께: 슈퍼관리자 직접 삭제 · 구 앱 생성 실패 직접 롤백 · 정상 사업장 수정·슬롯 쓰기 · 서버 정식 운영 종료.
 *     BUNDLE=<lib/index.js> DEV_RULES=<원문> CAND_RULES=<후보> node scripts/business-delete-isolation-runtime.js
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
const RUN = 'bd' + Date.now().toString(36);
let seq = 0; const uid = (p) => `${p}-${RUN}-${++seq}`;
const read = async (p) => (await db.doc(p).get()).data();

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
/** 여러 쓰기를 한 commit(batch)으로 — 하나라도 거절되면 전부 거절. */
async function commit(writes, who) {
  return (await req('POST', `/v1/${DB}/documents:commit`, {writes}, emuToken(who))).status === 200 ? 'ALLOW' : 'DENY';
}
const delW = (p) => ({delete: `${DB}/documents/${p}`});
const updW = (p, fields) => {
  const plain = Object.entries(fields).filter(([, x]) => x !== DEL);
  return {update: {name: `${DB}/documents/${p}`, fields: Object.fromEntries(plain.map(([k, x]) => [k, val(x)]))},
    updateMask: {fieldPaths: Object.keys(fields)}, currentDocument: {exists: true}};
};

async function world() {
  const b = uid('b'); const owner = uid('o'); const sa = uid('sa'); const sub = uid('sub');
  await db.doc(`users/${owner}`).set({role: 'BUSINESS_ADMIN', name: 'owner', businessId: b});
  await db.doc(`users/${sa}`).set({role: 'SUPER_ADMIN'});
  await db.doc(`users/${sub}`).set({role: 'USER', subAdminBusinessIds: [b]});
  await db.doc(`businesses/${b}`).set({ownerId: owner, adminIds: [owner], name: 'b', isApproved: true, businessNumber: '1234567890', deactivatedAt: null});
  await db.doc(`businesses/${b}/workTypes/wt1`).set({isActive: true, name: 'QA', businessId: b});
  await db.doc(`businesses/${b}/workTypes/wt2`).set({isActive: true, name: 'QB', businessId: b});
  await db.doc(`businesses/${b}/members/${sub}`).set({permissions: {canManageTo: true}});
  const t = uid('t');
  await db.doc(`tos/${t}`).set({businessId: b, status: 'ACTIVE', isPublished: true, title: 't', type: 'flex', totalSlots: 1, totalRequired: 1, workDetails: []});
  await db.doc(`tos/${t}/slots/s1`).set({toId: t, status: 'open', date: Timestamp.now(), workDetails: [], confirmedCount: 0, pendingCount: 0});
  const a = uid('a');
  await db.doc(`applications/${a}`).set({uid: uid('w'), businessId: b, toId: t, slotId: 's1', status: 'REJECTED', workDate: Timestamp.now(), appliedAt: Timestamp.now()});
  return {b, owner, sa, sub, t, a};
}
async function census(x) {
  const wt = (await db.collection(`businesses/${x.b}/workTypes`).get()).size;
  const mem = (await db.collection(`businesses/${x.b}/members`).get()).size;
  const biz = (await db.doc(`businesses/${x.b}`).get()).exists;
  const to = (await db.doc(`tos/${x.t}`).get()).exists; const app = (await db.doc(`applications/${x.a}`).get()).exists;
  return `사업장 ${biz ? '있음' : '없음'} · 업무유형 ${wt} · 멤버 ${mem} · 공고 ${to ? '있음' : '없음'} · 지원서 ${app ? '있음' : '없음'}`;
}

(async () => {
  const DEV = fs.readFileSync(process.env.DEV_RULES, 'utf8'); const CAND = fs.readFileSync(process.env.CAND_RULES, 'utf8');
  const rows = [];
  for (const [label, rules] of [['DEV 현재', DEV], ['사업장 삭제만 차단', CAND]]) {
    await loadRules(rules);
    // ① 구 앱 소유자 '삭제' 클릭 — 실제 요청 순서
    {
      const x = await world(); const before = await read(`businesses/${x.b}`);
      const s1 = await commit([delW(`businesses/${x.b}/workTypes/wt1`), delW(`businesses/${x.b}/workTypes/wt2`)], x.owner);
      const s2 = await commit([delW(`businesses/${x.b}/members/${x.sub}`)], x.owner);
      const s3 = await commit([delW(`businesses/${x.b}`)], x.owner);
      let chain = '연쇄 없음(삭제 거절)';
      if (s3 === 'ALLOW') {
        try { await fn.onBusinessDeleted.run({params: {businessId: x.b}, data: {exists: true, data: () => before, id: x.b, ref: db.doc(`businesses/${x.b}`)}}); chain = 'onBusinessDeleted 실행'; } catch (e) { chain = 'onBusinessDeleted 오류 ' + String(e.message).slice(0, 40); }
      }
      rows.push([label, '구 앱 소유자 삭제(업무유형 → 멤버 → 사업장)', `${s1} → ${s2} → ${s3} · ${chain} → ${await census(x)} · 앱 표시 ${s3 === 'ALLOW' ? '"삭제되었습니다"' : '"사업장 삭제에 실패했습니다"'}`]);
    }
    // ② 슈퍼관리자 직접 삭제
    { const x = await world(); rows.push([label, '슈퍼관리자 사업장 직접 삭제', await commit([delW(`businesses/${x.b}`)], x.sa)]); }
    // ③ 구 앱 생성 실패 롤백(부분 슬롯 + 공고 직접 삭제)
    { const x = await world(); rows.push([label, '구 앱 생성 실패 롤백(슬롯·공고 직접 삭제)', `${await commit([delW(`tos/${x.t}/slots/s1`)], x.owner)}/${await commit([delW(`tos/${x.t}`)], x.owner)}`]); }
    // ④ 정상 사업장 수정·슬롯 쓰기
    {
      const x = await world();
      const e1 = await commit([updW(`businesses/${x.b}`, {name: '새이름', phone: '0101'})], x.owner);
      const e2 = await commit([updW(`tos/${x.t}/slots/s1`, {visibleFrom: new Date(), status: 'closed', isManualClosed: false})], x.owner);
      const e3 = await commit([updW(`businesses/${x.b}/workTypes/wt1`, {name: 'QA2'})], x.owner);
      rows.push([label, '정상 사업장 수정 · 슬롯 마감 · 업무유형 수정', `${e1} · ${e2} · ${e3}`]);
    }
    // ⑤ 서버 정식 운영 종료(Admin SDK) — callableArchiveOwnBusiness + onBusinessDeactivated
    {
      const x = await world(); const before = await read(`businesses/${x.b}`);
      let r = 'OK';
      try {
        const pv = await fn.callableArchiveOwnBusiness.run({auth: {uid: x.owner, token: {}}, rawRequest: {headers: {}}, data: {businessId: x.b, preview: true}});
        await fn.callableArchiveOwnBusiness.run({auth: {uid: x.owner, token: {}}, rawRequest: {headers: {}}, data: {businessId: x.b, expected: pv.preview}});
        const after = await read(`businesses/${x.b}`);
        await fn.onBusinessDeactivated.run({params: {businessId: x.b}, data: {before: {exists: true, data: () => before}, after: {exists: true, data: () => after}}});
      } catch (e) { r = (e.details && e.details.code) || e.message; }
      const b2 = await read(`businesses/${x.b}`);
      rows.push([label, '서버 정식 운영 종료(Admin SDK)', `${r} · 종료 ${b2.deactivatedAt != null} · 연쇄 ${b2.archiveCascade ? b2.archiveCascade.state : '-'} · 공고 ${(await read(`tos/${x.t}`)).status} · ${await census(x)}`]);
    }
  }
  await loadRules(fs.readFileSync(path.join(ROOT, 'firestore.rules'), 'utf8'));
  for (const [l, k, v] of rows) log(`${l.padEnd(10)} | ${k.padEnd(34)} | ${v}`);
  process.exit(0);
})().catch((e) => { log('ERR ' + e.stack); process.exit(2); });
