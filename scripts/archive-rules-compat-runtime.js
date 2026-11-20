/**
 * [ARCHIVE-RULES-COMPAT] 사업장 종료 표식·연쇄 상태·슬롯 재오픈 직접 쓰기 — **실제 firestore.rules 평가**.
 *
 *   같은 요청을 (1) DEV 활성 ruleset 원문과 (2) 후보에 차례로 올려 allow/deny 를 잰다.
 *   요청 모양은 구·현재 앱 코드 그대로다(to_firestore.dart updateSlotsDeadlines·updateSlotsPublishSettings,
 *   firestore_service.dart _updateWorkDetailInArray·_syncSlotCascadeStatus, application_firestore.dart
 *   _recalculateSlotStatus, business_form_screen.dart 수정 저장).
 *     DEV_RULES=<DEV 활성 원문> CAND_RULES=<후보> node scripts/archive-rules-compat-runtime.js
 *   에뮬레이터 전용(demo-alfit-r7). 끝나면 작업 트리 rules 를 다시 올린다.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const http = require('http');
const PROJECT = 'demo-alfit-r7';
process.env.GCLOUD_PROJECT = PROJECT;
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:6070';
const admin = require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin'));
if (!admin.apps.length) admin.initializeApp({projectId: PROJECT});
const db = admin.firestore();
const T = admin.firestore.Timestamp;
const RUN = 'rc' + Date.now().toString(36);
if (!process.env.DEV_RULES || !process.env.CAND_RULES) throw new Error('DEV_RULES·CAND_RULES 경로가 필요하다');
const DEV = fs.readFileSync(process.env.DEV_RULES, 'utf8');
const CAND = fs.readFileSync(process.env.CAND_RULES, 'utf8');
const WT = fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8');

function emuToken(uid) {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  return `${b64({alg: 'none', typ: 'JWT'})}.${b64({iss: `https://securetoken.google.com/${PROJECT}`, aud: PROJECT,
    auth_time: now, user_id: uid, sub: uid, iat: now, exp: now + 3600, firebase: {identities: {}, sign_in_provider: 'custom'}})}.`;
}
function req(method, p, body, token) {
  return new Promise((res, rej) => {
    const data = body ? JSON.stringify(body) : null;
    const r = http.request({host: '127.0.0.1', port: 6070, method, path: p,
      headers: Object.assign({'Content-Type': 'application/json'}, token ? {Authorization: 'Bearer ' + token} : {},
        data ? {'Content-Length': Buffer.byteLength(data)} : {})}, (x) => {
      const bufs = []; x.on('data', (c) => bufs.push(c)); x.on('end', () => res({status: x.statusCode, body: Buffer.concat(bufs).toString('utf8')}));
    });
    r.on('error', rej); if (data) r.write(data); r.end();
  });
}
const loadRules = async (content) => {
  const r = await req('PUT', `/emulator/v1/projects/${PROJECT}:securityRules`, {rules: {files: [{name: 'firestore.rules', content}]}});
  if (r.status !== 200) throw new Error('rules 적재 실패 ' + r.status + ' ' + r.body.slice(0, 300));
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
const DEL = Symbol('delete'); const TS = Symbol('serverTs');
async function update(docPath, fields, who) {
  const plain = Object.entries(fields).filter(([, x]) => x !== DEL && x !== TS);
  const write = {update: {name: `${DB}/documents/${docPath}`, fields: Object.fromEntries(plain.map(([k, x]) => [k, val(x)]))},
    updateMask: {fieldPaths: Object.keys(fields).filter((k) => fields[k] !== TS)}, currentDocument: {exists: true}};
  const ts = Object.keys(fields).filter((k) => fields[k] === TS);
  if (ts.length) write.updateTransforms = ts.map((f) => ({fieldPath: f, setToServerValue: 'REQUEST_TIME'}));
  const r = await req('POST', `/v1/${DB}/documents:commit`, {writes: [write]}, emuToken(who));
  return r.status === 200 ? 'ALLOW' : 'DENY';
}
async function create(docPath, fields, who) {
  const [coll, id] = [docPath.slice(0, docPath.lastIndexOf('/')), docPath.slice(docPath.lastIndexOf('/') + 1)];
  const r = await req('POST', `/v1/${DB}/documents/${coll}?documentId=${id}`,
    {fields: Object.fromEntries(Object.entries(fields).map(([k, x]) => [k, val(x)]))}, emuToken(who));
  return r.status === 200 ? 'ALLOW' : 'DENY';
}

(async () => {
  const A = {owner: `own-${RUN}`, co: `co-${RUN}`, sup: `sup-${RUN}`, worker: `wk-${RUN}`};
  await db.doc(`users/${A.owner}`).set({role: 'BUSINESS_ADMIN'});
  await db.doc(`users/${A.co}`).set({role: 'BUSINESS_ADMIN'});
  await db.doc(`users/${A.sup}`).set({role: 'SUPER_ADMIN'});
  await db.doc(`users/${A.worker}`).set({role: 'USER'});
  let n = 0;
  const wds = (closed) => [{id: 'wd1', wdId: 'wd1', workType: 'QA', requiredCount: 2, ...(closed ? {isManualClosed: true} : {})}];
  /** 사업장 + 공고 + 슬롯 한 벌. closedBiz 면 운영 종료. */
  async function seed(closedBiz, slot = {}, o = {}) {
    const k = ++n; const b = `b-${RUN}-${k}`; const t = `t-${RUN}-${k}`;
    await db.doc(`businesses/${b}`).set(Object.assign({ownerId: A.owner, adminIds: o.coAdmin ? [A.owner, A.co] : [A.owner], name: 'b',
      isApproved: !closedBiz, businessNumber: '1234567890', deactivatedAt: closedBiz ? T.fromMillis(Date.now() - 3600e3) : null}, o.biz || {}));
    await db.doc(`tos/${t}`).set({businessId: b, status: closedBiz ? 'CLOSED' : 'ACTIVE', title: 't', type: 'flex', isPublished: true,
      workDetails: wds(false), totalRequired: 2, totalSlots: 1});
    await db.doc(`tos/${t}/slots/s1`).set(Object.assign({toId: t, status: 'closed', isManualClosed: false, workDetails: wds(true),
      date: T.fromMillis(Date.now() + 3 * 86400e3), confirmedCount: 0, pendingCount: 0, workDetailCounts: {}}, slot));
    return {b, t, s: `tos/${t}/slots/s1`};
  }
  const deadlineReopen = {workDetails: wds(false), applicationDeadline: new Date(Date.now() + 2 * 86400e3), status: 'open', isManualClosed: false, closedAt: DEL};
  const CASES = [
    // [id, 분류, 설명, seed(closedBiz, slot, o), 행위자, 동작, 기대 DEV, 기대 후보]
    // ── 사업장 종료 표식·연쇄 상태
    ['B1', '표식', '단독 관리자 deactivatedAt 삭제(종료 사업장)', [true], A.owner, (x) => update(`businesses/${x.b}`, {deactivatedAt: DEL}, A.owner), 'ALLOW', 'DENY'],
    ['B2', '표식', '단독 관리자 deactivatedAt → null', [true], A.owner, (x) => update(`businesses/${x.b}`, {deactivatedAt: null}, A.owner), 'ALLOW', 'DENY'],
    ['B3', '표식', '단독 관리자 deactivatedAt 직접 설정(사전 조회 우회 종료)', [false], A.owner, (x) => update(`businesses/${x.b}`, {deactivatedAt: new Date()}, A.owner), 'ALLOW', 'DENY'],
    ['B4', '표식', '관리자 archivedAt·archivedBy·archiveReason 위조', [true], A.owner,
      (x) => update(`businesses/${x.b}`, {archivedAt: new Date(), archivedBy: A.owner, archiveReason: 'X'}, A.owner), 'ALLOW', 'DENY'],
    ['B5', '표식', '관리자 archiveCascade{COMPLETE}·runs 위조', [true], A.owner,
      (x) => update(`businesses/${x.b}`, {archiveCascade: {state: 'COMPLETE', counts: {}}, archiveCascadeRuns: 9}, A.owner), 'ALLOW', 'DENY'],
    ['B6', '표식', '슈퍼관리자 archiveCascade 위조', [true], A.sup, (x) => update(`businesses/${x.b}`, {archiveCascade: {state: 'COMPLETE'}}, A.sup), 'ALLOW', 'DENY'],
    ['B7', '표식', '슈퍼관리자 deactivatedAt 삭제(재활성화는 callableManageBusiness)', [true], A.sup, (x) => update(`businesses/${x.b}`, {deactivatedAt: DEL}, A.sup), 'ALLOW', 'DENY'],
    ['B8', '표식', '공동 관리자 사업장 deactivatedAt 설정(기존부터 금지)', [false, {}, {coAdmin: true}], A.owner,
      (x) => update(`businesses/${x.b}`, {deactivatedAt: new Date()}, A.owner), 'DENY', 'DENY'],
    ['B9', '정상', '사업장 수정 저장(폼 필드) — 운영 중', [false], A.owner, (x) => update(`businesses/${x.b}`, {name: '새이름', phone: '0101', updatedAt: TS}, A.owner), 'ALLOW', 'ALLOW'],
    ['B10', '정상', '사업장 수정 저장(폼 필드) — 종료 사업장', [true], A.owner, (x) => update(`businesses/${x.b}`, {name: '새이름', updatedAt: TS}, A.owner), 'ALLOW', 'ALLOW'],
    // ── 운영 중 사업장: 구·현재 앱 정상 슬롯·업무 쓰기 (둘 다 ALLOW)
    ['S1o', '운영중', '공고 저장: 마감 시각 재계산 + 자동 마감 슬롯 재오픈', [false], A.owner, (x) => update(x.s, deadlineReopen, A.owner), 'ALLOW', 'ALLOW'],
    ['S2o', '운영중', '공개 설정 visibleFrom', [false], A.owner, (x) => update(x.s, {visibleFrom: new Date()}, A.owner), 'ALLOW', 'ALLOW'],
    ['S4o', '운영중', '업무 단위 재오픈(workDetails)', [false], A.owner, (x) => update(x.s, {workDetails: wds(false)}, A.owner), 'ALLOW', 'ALLOW'],
    ['S5o', '운영중', 'cascade 마감', [false, {status: 'open'}], A.owner,
      (x) => update(x.s, {status: 'closed', isManualClosed: false, closedAt: TS, closedBy: DEL}, A.owner), 'ALLOW', 'ALLOW'],
    ['S6o', '운영중', 'cascade 재오픈(closed→open)', [false], A.owner,
      (x) => update(x.s, {status: 'open', isManualClosed: false, reopenedAt: TS, closedAt: DEL}, A.owner), 'ALLOW', 'ALLOW'],
    ['S7o', '운영중', '확정 취소 뒤 full→open 재계산', [false, {status: 'full'}], A.owner, (x) => update(x.s, {status: 'open'}, A.owner), 'ALLOW', 'ALLOW'],
    ['T1o', '운영중', '슬롯 없는 공고 업무 단위 마감·재오픈(tos.workDetails)', [false], A.owner,
      (x) => update(`tos/${x.t}`, {workDetails: wds(true)}, A.owner), 'ALLOW', 'ALLOW'],
    ['SCo', '운영중', '슬롯 직접 생성(open)', [false], A.owner, (x) => create(`tos/${x.t}/slots/new-${RUN}-${++n}`,
      {toId: x.t, status: 'open', confirmedCount: 0, pendingCount: 0, workDetails: wds(false), date: new Date()}, A.owner), 'ALLOW', 'ALLOW'],
    // ── 운영 종료 사업장: 다시 여는 직접 쓰기 (DEV ALLOW → 후보 DENY)
    ['S1c', '종료', '공고 저장: 마감 시각 재계산 + 재오픈', [true], A.owner, (x) => update(x.s, deadlineReopen, A.owner), 'ALLOW', 'DENY'],
    ['S4c', '종료', '업무 단위 재오픈(workDetails)', [true], A.owner, (x) => update(x.s, {workDetails: wds(false)}, A.owner), 'ALLOW', 'DENY'],
    ['S6c', '종료', 'cascade 재오픈(closed→open)', [true], A.owner,
      (x) => update(x.s, {status: 'open', isManualClosed: false, reopenedAt: TS, closedAt: DEL}, A.owner), 'ALLOW', 'DENY'],
    ['T1c', '종료', '슬롯 없는 공고 업무 재오픈(tos.workDetails)', [true], A.owner, async (x) => { await db.doc(`tos/${x.t}`).update({workDetails: wds(true)}); return update(`tos/${x.t}`, {workDetails: wds(false)}, A.owner); }, 'ALLOW', 'DENY'],
    ['SCc', '종료', '슬롯 직접 생성(open)', [true], A.owner, (x) => create(`tos/${x.t}/slots/new-${RUN}-${++n}`,
      {toId: x.t, status: 'open', confirmedCount: 0, pendingCount: 0, workDetails: wds(false), date: new Date()}, A.owner), 'ALLOW', 'DENY'],
    ['SCs', '종료', '슈퍼관리자 슬롯 직접 생성', [true], A.sup, (x) => create(`tos/${x.t}/slots/new-${RUN}-${++n}`,
      {toId: x.t, status: 'open', workDetails: wds(false), date: new Date()}, A.sup), 'ALLOW', 'DENY'],
    ['S6s', '종료', '슈퍼관리자 슬롯 closed→open', [true], A.sup, (x) => update(x.s, {status: 'open'}, A.sup), 'ALLOW', 'DENY'],
    // ── 운영 종료 사업장: 다시 열지 않는 쓰기는 그대로 (둘 다 ALLOW)
    ['S5c', '종료유지', 'cascade 마감', [true, {status: 'open'}], A.owner,
      (x) => update(x.s, {status: 'closed', isManualClosed: false, closedAt: TS, closedBy: DEL}, A.owner), 'ALLOW', 'ALLOW'],
    ['S7c', '종료유지', '확정 취소 뒤 full→open 재계산(공고는 CLOSED)', [true, {status: 'full'}], A.owner, (x) => update(x.s, {status: 'open'}, A.owner), 'ALLOW', 'ALLOW'],
    ['S2c', '종료유지', '공개 설정 visibleFrom', [true], A.owner, (x) => update(x.s, {visibleFrom: new Date()}, A.owner), 'ALLOW', 'ALLOW'],
    ['U1c', '종료유지', '근로자 pendingCount -1(기존 분기)', [true, {pendingCount: 1}], A.worker, (x) => update(x.s, {pendingCount: 0}, A.worker), 'ALLOW', 'ALLOW'],
  ];
  const got = {};
  for (const [label, rules] of [['DEV', DEV], ['후보', CAND]]) {
    await loadRules(rules);
    for (const c of CASES) {
      const x = await seed(...c[3]);
      (got[c[0]] = got[c[0]] || {})[label] = await c[5](x);
    }
  }
  await loadRules(WT);
  let fail = 0;
  for (const [id, cls, desc, , , , eDev, eCand] of CASES) {
    const g = got[id]; const ok = g.DEV === eDev && g['후보'] === eCand; if (!ok) fail++;
    console.log(`${ok ? 'ok  ' : 'FAIL'} ${id.padEnd(4)} ${cls.padEnd(5)} ${desc.padEnd(46)} | DEV ${eDev}/${g.DEV} | 후보 ${eCand}/${g['후보']}`);
  }
  console.log(`\n후보 ${path.basename(process.env.CAND_RULES)} · 셀 ${CASES.length} · 실패 ${fail}`);
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.log('ERR ' + e.stack); process.exit(2); });
