/**
 * [APP-TRANSITION-ISOLATED] applications 직접 쓰기 — **실제 firestore.rules 평가**.
 *
 *   같은 요청을 (1) DEV 에 적용 중인 ruleset 원문(읽기로 받은 사본, ruleset c13d9e91…)과
 *   (2) 후보(작업 트리 firestore.rules)에 차례로 올려 allow/deny 를 잰다.
 *   우회는 DEV 에서 ALLOW → 후보에서 DENY, 정상 구·새 앱 쓰기는 둘 다 ALLOW,
 *   권한 없는 사용자·create 는 둘 다 DENY 여야 한다.
 *
 *   요청 모양은 앱 코드 그대로다.
 *     근로자 취소  application_firestore.dart cancelApplication(tx): status · canceledAt(서버시각) ·
 *                  cancelReason=USER_CANCELED · statusHistory
 *     구 앱 복구   HEAD updateApplicationStatus(PENDING): status · statusHistory
 *     필드 수정    updateApplicationFields: isStarred · renewalDecision · terminationCompletionNotifiedAt
 *
 *   실행: firebase emulators:start --only firestore --project demo-alfit-r7 --config firebase.r7audit.json
 *         DEV_RULES=<DEV ruleset 사본 경로> node scripts/app-transition-rules-runtime.js
 *   끝나면 후보 rules 를 다시 올려 둔다. 에뮬레이터 전용(DEV·PROD 에 연결하지 않는다).
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
const RUN = 'at' + Date.now().toString(36);
// 후보: 기본은 작업 트리, CAND_RULES 로 별도 배포 후보 파일을 지정한다.
const CAND_PATH = process.env.CAND_RULES || path.join(__dirname, '..', 'firestore.rules');
const CANDIDATE = fs.readFileSync(CAND_PATH, 'utf8');
if (!process.env.DEV_RULES) throw new Error('DEV_RULES 경로가 필요하다');
const DEV = fs.readFileSync(process.env.DEV_RULES, 'utf8');

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
// JS 값 → Firestore REST Value
function val(v) {
  if (v === null) return {nullValue: null};
  if (v instanceof Date) return {timestampValue: v.toISOString()};
  if (Array.isArray(v)) return {arrayValue: {values: v.map(val)}};
  if (typeof v === 'boolean') return {booleanValue: v};
  if (typeof v === 'number') return Number.isInteger(v) ? {integerValue: String(v)} : {doubleValue: v};
  if (typeof v === 'string') return {stringValue: v};
  return {mapValue: {fields: Object.fromEntries(Object.entries(v).map(([k, x]) => [k, val(x)]))}};
}
/** 필드 마스크에만 넣고 값은 보내지 않는다 = 필드 삭제. */
const REMOVE = Symbol('remove');
/** update(필드 마스크) — serverTs 에 적힌 필드는 REQUEST_TIME 변환, union 은 arrayUnion 변환. */
async function update(docId, fields, who, serverTs = [], union = {}) {
  const write = {update: {name: `${DB}/documents/applications/${docId}`,
    fields: Object.fromEntries(Object.entries(fields).filter(([, x]) => x !== REMOVE).map(([k, x]) => [k, val(x)]))},
  updateMask: {fieldPaths: Object.keys(fields)}, currentDocument: {exists: true}};
  const tf = [...serverTs.map((f) => ({fieldPath: f, setToServerValue: 'REQUEST_TIME'})),
    ...Object.entries(union).map(([f, arr]) => ({fieldPath: f, appendMissingElements: {values: arr.map(val)}}))];
  if (tf.length) write.updateTransforms = tf;
  const r = await req('POST', `/v1/${DB}/documents:commit`, {writes: [write]}, emuToken(who));
  return r.status === 200 ? 'ALLOW' : 'DENY';
}
async function create(docId, fields, who) {
  const r = await req('POST', `/v1/${DB}/documents/applications?documentId=${docId}`,
    {fields: Object.fromEntries(Object.entries(fields).map(([k, x]) => [k, val(x)]))}, emuToken(who));
  return r.status === 200 ? 'ALLOW' : 'DENY';
}
async function del(docId, who) {
  const r = await req('DELETE', `/v1/${DB}/documents/applications/${docId}`, null, emuToken(who));
  return r.status === 200 ? 'ALLOW' : 'DENY';
}

(async () => {
  const biz = `b-${RUN}`; const otherBiz = `ob-${RUN}`;
  const A = {owner: `own-${RUN}`, subMW: `submw-${RUN}`, subNo: `subno-${RUN}`, sup: `sup-${RUN}`,
    worker: `wk-${RUN}`, stranger: `st-${RUN}`, otherOwner: `oo-${RUN}`};
  await db.doc(`businesses/${biz}`).set({ownerId: A.owner, adminIds: [A.owner], name: 'b'});
  await db.doc(`businesses/${otherBiz}`).set({ownerId: A.otherOwner, adminIds: [A.otherOwner], name: 'o'});
  await db.doc(`users/${A.owner}`).set({role: 'BUSINESS_ADMIN'});
  await db.doc(`users/${A.otherOwner}`).set({role: 'BUSINESS_ADMIN'});
  await db.doc(`users/${A.subMW}`).set({role: 'USER', subAdminBusinessIds: [biz]});
  await db.doc(`users/${A.subNo}`).set({role: 'USER', subAdminBusinessIds: [biz]});
  await db.doc(`users/${A.sup}`).set({role: 'SUPER_ADMIN'});
  await db.doc(`users/${A.worker}`).set({role: 'USER'});
  await db.doc(`users/${A.stranger}`).set({role: 'USER'});
  await db.doc(`businesses/${biz}/members/${A.subMW}`).set({permissions: {canManageWorkers: true, canManageTo: true}});
  await db.doc(`businesses/${biz}/members/${A.subNo}`).set({permissions: {canManageWorkers: false, canManageTo: true}});

  // 기존 이력 — 밀리초 정밀도로 고정(REST 로 되돌려 보낼 때 같은 값이어야 한다).
  const T0 = Math.floor(Date.now() / 1000) * 1000 - 3600e3;
  const prevEntry = (k) => ({status: 'PENDING', at: new Date(T0 + k * 1000), by: A.worker});
  const prevHist = (len = 1) => Array.from({length: len}, (_, k) => prevEntry(k));
  // 구 앱 _appendHistory 모양: 기존 이력 + 새 항목 1개, 20개를 넘으면 앞에서 잘라 낸다.
  const rollbackEntry = (o = {}) => Object.assign({status: 'PENDING', at: new Date(), by: null, action: 'CONFIRM_ROLLBACK'}, o);
  const appended = (len, o) => { const h = [...prevHist(len), rollbackEntry(o)]; return h.length > 20 ? h.slice(h.length - 20) : h; };
  // 근로자 취소(HEAD cancelApplication) 모양: 기존 이력 + CANCEL 항목, 20개를 넘으면 앞에서 잘라 낸다.
  //   o 의 값이 undefined 인 키는 항목에서 뺀다(예전 빌드 모양).
  const cancelEntry = (o = {}) => {
    const e = Object.assign({status: 'CANCELED', at: new Date(), by: A.worker, action: 'CANCEL', reason: 'USER_CANCELED'}, o);
    for (const k of Object.keys(e)) if (e[k] === undefined) delete e[k];
    return e;
  };
  const cancelHist = (len = 1, o) => { const h = [...prevHist(len), cancelEntry(o)]; return h.length > 20 ? h.slice(h.length - 20) : h; };
  const W = (fields, extra = {}) => Object.assign({fields: Object.assign({status: 'CANCELED', cancelReason: 'USER_CANCELED'}, fields), ts: ['canceledAt']}, extra);
  const hist = () => appended(1); // 되돌리기 정상 모양
  const toAdminHist = (arr) => arr.map((e) => Object.assign({}, e, {at: T.fromDate(e.at)}));
  const base = (status, extra = {}) => Object.assign({uid: A.worker, businessId: biz, toId: 't1', slotId: 's1', status,
    wage: 12000, statusHistory: toAdminHist(prevHist(extra.__histLen === undefined ? 1 : extra.__histLen))}, extra);
  let n = 0;
  async function seed(status, extra = {}) {
    const id = `a-${RUN}-${++n}`;
    const d = base(status, extra);
    if (extra.__histLen === 0) delete d.statusHistory;
    delete d.__histLen;
    await db.doc(`applications/${id}`).set(d);
    return id;
  }

  // [id, 분류, 설명, 출발 상태, 초기 덧붙임, 행위자, 동작, 기대(DEV), 기대(후보)]
  //   동작: {fields, ts} = update · {create} · {del}
  const CASES = [
    // ── 정상 구·새 앱 쓰기 (둘 다 ALLOW)
    ['N1', '정상', '근로자 본인 PENDING→CANCELED (cancelApplication 모양)', 'PENDING', {}, A.worker,
      {fields: {status: 'CANCELED', cancelReason: 'USER_CANCELED', statusHistory: cancelHist()}, ts: ['canceledAt']}, 'ALLOW', 'ALLOW'],
    ['N2', '정상', '구 앱 관리자 복구 CONFIRMED→PENDING {status,statusHistory}', 'CONFIRMED', {}, A.owner,
      {fields: {status: 'PENDING', statusHistory: hist('PENDING')}}, 'ALLOW', 'ALLOW'],
    ['N3', '정상', '구 앱 관리자 복구 CONTRACT_PENDING→PENDING', 'CONTRACT_PENDING', {}, A.owner,
      {fields: {status: 'PENDING', statusHistory: hist('PENDING')}}, 'ALLOW', 'ALLOW'],
    ['N4', '정상', 'SubAdmin(canManageWorkers) 복구 CONFIRMED→PENDING', 'CONFIRMED', {}, A.subMW,
      {fields: {status: 'PENDING', statusHistory: hist('PENDING')}}, 'ALLOW', 'ALLOW'],
    ['N5', '정상', '관리자 isStarred (상태 유지)', 'PENDING', {}, A.owner, {fields: {isStarred: true}}, 'ALLOW', 'ALLOW'],
    ['N6', '정상', 'SubAdmin(소속만) isStarred', 'PENDING', {}, A.subNo, {fields: {isStarred: true}}, 'ALLOW', 'ALLOW'],
    ['N7', '정상', '관리자 renewalDecision=TERMINATE', 'CONFIRMED', {}, A.owner, {fields: {renewalDecision: 'TERMINATE'}}, 'ALLOW', 'ALLOW'],
    ['N8', '정상', '관리자 terminationCompletionNotifiedAt', 'CONFIRMED', {}, A.owner,
      {fields: {terminationCompletionNotifiedAt: new Date()}}, 'ALLOW', 'ALLOW'],
    ['N9', '정상', '관리자 isStarred + renewalDecision 함께(둘 다 허용 필드)', 'CONFIRMED', {}, A.owner,
      {fields: {isStarred: true, renewalDecision: 'TERMINATE'}}, 'ALLOW', 'ALLOW'],
    // ── 우회 (DEV ALLOW → 후보 DENY)
    ['B1', '우회', '관리자 PENDING→CONTRACT_PENDING (확정 관문 우회)', 'PENDING', {}, A.owner, {fields: {status: 'CONTRACT_PENDING'}}, 'ALLOW', 'DENY'],
    ['B2', '우회', '관리자 INVITED→CONFIRMED', 'INVITED', {}, A.owner, {fields: {status: 'CONFIRMED'}}, 'ALLOW', 'DENY'],
    ['B3', '우회', '관리자 INVITED→CONTRACT_PENDING', 'INVITED', {}, A.owner, {fields: {status: 'CONTRACT_PENDING'}}, 'ALLOW', 'DENY'],
    ['B4', '우회', '관리자 EXPIRED→CONFIRMED', 'EXPIRED', {}, A.owner, {fields: {status: 'CONFIRMED'}}, 'ALLOW', 'DENY'],
    ['B5', '우회', '관리자 REJECTED→CONTRACT_PENDING', 'REJECTED', {}, A.owner, {fields: {status: 'CONTRACT_PENDING'}}, 'ALLOW', 'DENY'],
    ['B6', '우회', '관리자 CANCELED→CONTRACT_PENDING (+cancelReason 삭제)', 'CANCELED', {cancelReason: 'BUSINESS_DEACTIVATED'}, A.owner,
      {fields: {status: 'CONTRACT_PENDING', cancelReason: null}}, 'ALLOW', 'DENY'],
    ['B7', '우회', '관리자 CONFIRMED→AUTO_CANCELED', 'CONFIRMED', {}, A.owner, {fields: {status: 'AUTO_CANCELED'}}, 'ALLOW', 'DENY'],
    ['B8', '우회', '관리자 CONFIRMED→EXPIRED', 'CONFIRMED', {}, A.owner, {fields: {status: 'EXPIRED'}}, 'ALLOW', 'DENY'],
    ['B9', '우회', '관리자 PENDING→INVITED', 'PENDING', {}, A.owner, {fields: {status: 'INVITED'}}, 'ALLOW', 'DENY'],
    ['B10', '우회', '관리자 임의 상태 문자열 "HACKED"', 'PENDING', {}, A.owner, {fields: {status: 'HACKED'}}, 'ALLOW', 'DENY'],
    ['B11', '우회', '관리자 CONFIRMED→CONTRACT_PENDING', 'CONFIRMED', {}, A.owner, {fields: {status: 'CONTRACT_PENDING'}}, 'ALLOW', 'DENY'],
    ['B12', '우회', 'SUPER_ADMIN INVITED→CONFIRMED', 'INVITED', {}, A.sup, {fields: {status: 'CONFIRMED'}}, 'ALLOW', 'DENY'],
    ['B13', '우회', '복구 모양 + 임금 변경 섞기', 'CONFIRMED', {}, A.owner,
      {fields: {status: 'PENDING', statusHistory: hist('PENDING'), wage: 99999}}, 'ALLOW', 'DENY'],
    ['B14', '우회', 'isStarred + PENDING→CONTRACT_PENDING 섞기', 'PENDING', {}, A.owner,
      {fields: {isStarred: true, status: 'CONTRACT_PENDING'}}, 'ALLOW', 'DENY'],
    ['B15', '우회', '상태 유지 + 허용 밖 필드(wage·slotId) 변경', 'CONFIRMED', {}, A.owner,
      {fields: {wage: 99999, slotId: 's2'}}, 'ALLOW', 'DENY'],
    ['B16', '우회', '관리자 직접 PENDING→CANCELED (앱 사용처 0)', 'PENDING', {}, A.owner, {fields: {status: 'CANCELED'}}, 'ALLOW', 'DENY'],
    ['B17', '우회', 'SUPER_ADMIN 상태 유지 + wage 변경', 'CONFIRMED', {}, A.sup, {fields: {wage: 1}}, 'ALLOW', 'DENY'],
    // ── 권한 없음·기존 금지 (둘 다 DENY)
    ['U1', '권한', '무관 USER 가 남의 PENDING→CANCELED', 'PENDING', {}, A.stranger,
      {fields: {status: 'CANCELED', cancelReason: 'USER_CANCELED', statusHistory: cancelHist()}, ts: ['canceledAt']}, 'DENY', 'DENY'],
    ['U2', '권한', '다른 사업장 관리자 복구 CONFIRMED→PENDING', 'CONFIRMED', {}, A.otherOwner,
      {fields: {status: 'PENDING', statusHistory: hist('PENDING')}}, 'DENY', 'DENY'],
    ['U3', '권한', 'SubAdmin(인력 관리 권한 없음) 복구 CONFIRMED→PENDING', 'CONFIRMED', {}, A.subNo,
      {fields: {status: 'PENDING', statusHistory: hist('PENDING')}}, 'DENY', 'DENY'],
    ['U4', '권한', 'SubAdmin PENDING→CONTRACT_PENDING', 'PENDING', {}, A.subMW, {fields: {status: 'CONTRACT_PENDING'}}, 'DENY', 'DENY'],
    ['U5', '권한', '근로자 본인 isStarred', 'PENDING', {}, A.worker, {fields: {isStarred: true}}, 'DENY', 'DENY'],
    ['U6', '권한', '근로자 본인 PENDING→CONFIRMED', 'PENDING', {}, A.worker, {fields: {status: 'CONFIRMED'}}, 'DENY', 'DENY'],
    ['U7', '권한', '관리자 renewalDecision=EXTEND', 'CONFIRMED', {}, A.owner, {fields: {renewalDecision: 'EXTEND'}}, 'DENY', 'DENY'],
    ['U8', '권한', '계약해지 대기 중 renewalDecision', 'CONFIRMED', {terminationStatus: 'PENDING'}, A.owner,
      {fields: {renewalDecision: 'TERMINATE'}}, 'DENY', 'DENY'],
    ['U9', '권한', '관리자 PENDING→CONFIRMED (기존 금지)', 'PENDING', {}, A.owner, {fields: {status: 'CONFIRMED'}}, 'DENY', 'DENY'],
    ['U10', '권한', '근로자 취소 + 서버시각 아닌 canceledAt(과거 위조)', 'PENDING', {}, A.worker,
      {fields: {status: 'CANCELED', canceledAt: new Date(Date.now() - 86400e3), statusHistory: cancelHist()}}, 'DENY', 'DENY'],
    // ── 되돌리기 이력 (구 앱 _appendHistory 모양 기준)
    ['H1', '이력', '되돌리기 · 이력 없음(레거시) → [새 항목]', 'CONFIRMED', {__histLen: 0}, A.owner,
      {fields: {status: 'PENDING', statusHistory: [rollbackEntry()]}}, 'ALLOW', 'ALLOW'],
    ['H2', '이력', '되돌리기 · 이력 20개 → 앞 1개 잘리고 새 항목(길이 20)', 'CONFIRMED', {__histLen: 20}, A.owner,
      {fields: {status: 'PENDING', statusHistory: appended(20)}}, 'ALLOW', 'ALLOW'],
    ['H3', '이력', '되돌리기 · by=본인 uid(앞으로의 호출 대비)', 'CONFIRMED', {}, A.owner,
      {fields: {status: 'PENDING', statusHistory: appended(1, {by: A.owner})}}, 'ALLOW', 'ALLOW'],
    ['H4', '이력위조', '되돌리기 + 이력 전체 삭제([새 항목]만)', 'CONFIRMED', {__histLen: 3}, A.owner,
      {fields: {status: 'PENDING', statusHistory: [rollbackEntry()]}}, 'ALLOW', 'DENY'],
    ['H5', '이력위조', '되돌리기 + 기존 항목 내용 바꿔 쓰기', 'CONFIRMED', {__histLen: 2}, A.owner,
      {fields: {status: 'PENDING', statusHistory: [prevEntry(0), {status: 'CONFIRMED', at: new Date(T0), by: A.owner}, rollbackEntry()]}}, 'ALLOW', 'DENY'],
    ['H6', '이력위조', '되돌리기 + 항목 2개 덧붙이기', 'CONFIRMED', {}, A.owner,
      {fields: {status: 'PENDING', statusHistory: [...appended(1), rollbackEntry()]}}, 'ALLOW', 'DENY'],
    ['H7', '이력위조', '되돌리기 · 새 항목 by=다른 관리자 uid', 'CONFIRMED', {}, A.owner,
      {fields: {status: 'PENDING', statusHistory: appended(1, {by: A.otherOwner})}}, 'ALLOW', 'DENY'],
    ['H8', '이력위조', '되돌리기 · 새 항목 action 위조', 'CONFIRMED', {}, A.owner,
      {fields: {status: 'PENDING', statusHistory: appended(1, {action: 'CONTRACT_SIGNED'})}}, 'ALLOW', 'DENY'],
    ['H9', '이력위조', '되돌리기 · 20개 중 가운데 항목 빼기(길이 20)', 'CONFIRMED', {__histLen: 20}, A.owner,
      {fields: {status: 'PENDING', statusHistory: [...prevHist(20).filter((_, k) => k !== 10), rollbackEntry()]}}, 'ALLOW', 'DENY'],
    ['H10', '이력위조', '근로자 취소 + 이력 전체 교체([한 항목]만)', 'PENDING', {__histLen: 3}, A.worker,
      W({statusHistory: [cancelEntry()]}), 'ALLOW', 'DENY'],
    // ── 근로자 취소 — 역대 빌드 모양 (둘 다 ALLOW)
    ['W1', '취소', '이력 필드 없음(레거시) → [새 항목]', 'PENDING', {__histLen: 0}, A.worker,
      W({statusHistory: [cancelEntry()]}), 'ALLOW', 'ALLOW'],
    ['W2', '취소', '이력 19개 → 20개', 'PENDING', {__histLen: 19}, A.worker, W({statusHistory: cancelHist(19)}), 'ALLOW', 'ALLOW'],
    ['W3', '취소', '이력 20개 → 앞 1개 잘리고 새 항목(길이 20)', 'PENDING', {__histLen: 20}, A.worker,
      W({statusHistory: cancelHist(20)}), 'ALLOW', 'ALLOW'],
    ['W4', '취소', '~2025-12-16 빌드: status·canceledAt 만(이력·사유 없음)', 'PENDING', {}, A.worker,
      {fields: {status: 'CANCELED'}, ts: ['canceledAt']}, 'ALLOW', 'ALLOW'],
    ['W5', '취소', '2026-06-09~15 빌드: 항목 reason 없음 · cancelReason 없음', 'PENDING', {}, A.worker,
      {fields: {status: 'CANCELED', statusHistory: cancelHist(1, {reason: undefined})}, ts: ['canceledAt']}, 'ALLOW', 'ALLOW'],
    ['W6', '취소', '2025-12~2026-06 빌드: arrayUnion 변환(reason 없음)', 'PENDING', {}, A.worker,
      {fields: {status: 'CANCELED'}, ts: ['canceledAt'], union: {statusHistory: [cancelEntry({reason: undefined})]}}, 'ALLOW', 'ALLOW'],
    ['W7', '취소', 'arrayUnion · 이력 20개 → 21개(상한 없던 빌드)', 'PENDING', {__histLen: 20}, A.worker,
      {fields: {status: 'CANCELED'}, ts: ['canceledAt'], union: {statusHistory: [cancelEntry({reason: undefined})]}}, 'ALLOW', 'ALLOW'],
    // ── 근로자 취소 — 이력·필드 위조 (DEV ALLOW → 후보 DENY)
    ['W8', '취소위조', 'statusHistory 필드 삭제', 'PENDING', {__histLen: 3}, A.worker, W({statusHistory: REMOVE}), 'ALLOW', 'DENY'],
    ['W9', '취소위조', 'statusHistory = []', 'PENDING', {__histLen: 3}, A.worker, W({statusHistory: []}), 'ALLOW', 'DENY'],
    ['W10', '취소위조', '기존 항목 내용 바꿔 쓰기 + 새 항목', 'PENDING', {__histLen: 2}, A.worker,
      W({statusHistory: [prevEntry(0), {status: 'CONFIRMED', at: new Date(T0), by: A.owner}, cancelEntry()]}), 'ALLOW', 'DENY'],
    ['W11', '취소위조', '20개 중 가운데 항목 빼고 새 항목(길이 20)', 'PENDING', {__histLen: 20}, A.worker,
      W({statusHistory: [...prevHist(20).filter((_, k) => k !== 10), cancelEntry()]}), 'ALLOW', 'DENY'],
    ['W12', '취소위조', '항목 2개 덧붙이기', 'PENDING', {}, A.worker, W({statusHistory: [...cancelHist(1), cancelEntry()]}), 'ALLOW', 'DENY'],
    ['W13', '취소위조', '새 항목 action=ADMIN_CANCEL', 'PENDING', {}, A.worker,
      W({statusHistory: cancelHist(1, {action: 'ADMIN_CANCEL'})}), 'ALLOW', 'DENY'],
    ['W14', '취소위조', '새 항목 action 없음', 'PENDING', {}, A.worker,
      W({statusHistory: cancelHist(1, {action: undefined})}), 'ALLOW', 'DENY'],
    ['W15', '취소위조', '새 항목 status=CONFIRMED', 'PENDING', {}, A.worker,
      W({statusHistory: cancelHist(1, {status: 'CONFIRMED'})}), 'ALLOW', 'DENY'],
    ['W16', '취소위조', '새 항목 by=관리자 uid', 'PENDING', {}, A.worker,
      W({statusHistory: cancelHist(1, {by: A.owner})}), 'ALLOW', 'DENY'],
    ['W17', '취소위조', '새 항목에 다른 키(canceledBy)', 'PENDING', {}, A.worker,
      W({statusHistory: cancelHist(1, {canceledBy: A.owner})}), 'ALLOW', 'DENY'],
    ['W18', '취소위조', '새 항목 reason=SAME_DAY_CANCEL', 'PENDING', {}, A.worker,
      W({statusHistory: cancelHist(1, {reason: 'SAME_DAY_CANCEL'})}), 'ALLOW', 'DENY'],
    ['W19', '취소위조', '새 항목 at 문자열', 'PENDING', {}, A.worker,
      W({statusHistory: cancelHist(1, {at: '2026-01-01T00:00:00Z'})}), 'ALLOW', 'DENY'],
    ['W20', '취소위조', 'cancelReason=ADMIN_CANCELED', 'PENDING', {}, A.worker,
      W({cancelReason: 'ADMIN_CANCELED', statusHistory: cancelHist(1)}), 'ALLOW', 'DENY'],
    ['W21', '취소위조', 'arrayUnion 으로 관리자 action 항목 붙이기', 'PENDING', {}, A.worker,
      {fields: {status: 'CANCELED'}, ts: ['canceledAt'], union: {statusHistory: [cancelEntry({action: 'CONTRACT_SIGNED'})]}}, 'ALLOW', 'DENY'],
    ['W22', '취소', '다른 필드 혼합(wage) — 기존부터 금지', 'PENDING', {}, A.worker,
      W({statusHistory: cancelHist(1), wage: 99999}), 'DENY', 'DENY'],
    // ── create (둘 다 DENY)
    ['C1', 'create', '관리자 CONFIRMED 지원서 생성', null, null, A.owner, {create: true}, 'DENY', 'DENY'],
    ['C2', 'create', '근로자 PENDING 지원서 생성', null, null, A.worker, {create: true, status: 'PENDING'}, 'DENY', 'DENY'],
    ['C3', 'create', 'SUPER_ADMIN CONFIRMED 생성', null, null, A.sup, {create: true}, 'DENY', 'DENY'],
    // ── delete (이번에 바꾸지 않음 — 둘이 같아야 한다)
    // ── delete — 클라이언트 직접 삭제 전면 차단
    ['D1', 'delete', '관리자 REJECTED 삭제', 'REJECTED', {}, A.owner, {del: true}, 'ALLOW', 'DENY'],
    ['D2', 'delete', '관리자 CONFIRMED 삭제', 'CONFIRMED', {}, A.owner, {del: true}, 'DENY', 'DENY'],
    ['D3', 'delete', '근로자 본인 PENDING 삭제', 'PENDING', {}, A.worker, {del: true}, 'DENY', 'DENY'],
    ['D4', 'delete', '관리자 PENDING 삭제', 'PENDING', {}, A.owner, {del: true}, 'ALLOW', 'DENY'],
    ['D5', 'delete', '관리자 INVITED 삭제', 'INVITED', {}, A.owner, {del: true}, 'ALLOW', 'DENY'],
    ['D6', 'delete', '관리자 CANCELED 삭제', 'CANCELED', {}, A.owner, {del: true}, 'ALLOW', 'DENY'],
    ['D7', 'delete', '관리자 EXPIRED 삭제', 'EXPIRED', {}, A.owner, {del: true}, 'ALLOW', 'DENY'],
    ['D8', 'delete', 'SUPER_ADMIN REJECTED 삭제', 'REJECTED', {}, A.sup, {del: true}, 'ALLOW', 'DENY'],
    ['D9', 'delete', 'SubAdmin INVITED 삭제', 'INVITED', {}, A.subMW, {del: true}, 'DENY', 'DENY'],
    ['D10', 'delete', '관리자 CONTRACT_PENDING 삭제', 'CONTRACT_PENDING', {}, A.owner, {del: true}, 'DENY', 'DENY'],
  ];

  const got = {};
  for (const [label, content] of [['DEV', DEV], ['후보', CANDIDATE]]) {
    await loadRules(content);
    for (const c of CASES) {
      const [id, , , status, extra, who, act] = c;
      let r;
      if (act.create) {
        r = await create(`c-${RUN}-${label === 'DEV' ? 'd' : 'c'}-${id}`, base(act.status || 'CONFIRMED'), who);
      } else {
        const doc = await seed(status, extra);
        r = act.del ? await del(doc, who) : await update(doc, act.fields, who, act.ts || [], act.union || {});
      }
      (got[id] = got[id] || {})[label] = r;
    }
  }
  await loadRules(CANDIDATE);
  let fail = 0;
  console.log('id   분류    설명                                                   | DEV(기대/실제)   | 후보(기대/실제)');
  for (const c of CASES) {
    const [id, cls, desc, , , , , eDev, eCand] = c;
    const g = got[id];
    const ok = g.DEV === eDev && g['후보'] === eCand;
    if (!ok) fail++;
    console.log(`${ok ? 'ok  ' : 'FAIL'} ${id.padEnd(4)} ${cls.padEnd(6)} ${desc.padEnd(52)} | ${eDev}/${g.DEV}`.padEnd(100) + ` | ${eCand}/${g['후보']}`);
  }
  const bypass = CASES.filter((c) => c[7] === 'ALLOW' && c[8] === 'DENY').length;
  console.log(`\n후보 ${path.basename(CAND_PATH)} · 셀 ${CASES.length} · 실패 ${fail} · DEV 허용→후보 거절 ${bypass}건`);
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.log('ERR ' + e.stack); process.exit(2); });
