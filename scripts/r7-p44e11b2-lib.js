/**
 * [R7-P4.4E.11B.2] 이 Phase 전용 도우미.
 *
 *   r7-fixture-lib 는 Admin SDK 와 `callAs`(실 callable 호출)를 준다.
 *   여기에 두 가지를 더한다.
 *
 *     ① rules 를 **지나는** 클라이언트 쓰기 (Admin SDK 는 rules 우회)
 *     ② synthetic 이미지 업로드 / object-local 삭제 실패 주입
 *
 *   모든 fixture 는 `rt11b2_` 접두를 쓴다. 공유 DEV 데이터는 건드리지 않는다.
 */
'use strict';

const fs = require('fs');
const path = require('path');
const lib = require('./r7-fixture-lib');

const {admin, db, devBucket} = lib;
const ROOT = path.resolve(__dirname, '..');
const PREFIX = 'rt11b2_';

// ── 클라이언트 설정 (google-services.json — 비밀 아님, 읽기만) ──────
const gs = JSON.parse(
    fs.readFileSync(path.join(ROOT, 'android', 'app', 'google-services.json'), 'utf8'));
if (gs.project_info.project_id !== 'alfit-89567') {
  throw new Error('google-services.json 의 project_id 가 DEV 가 아닙니다.');
}
const API_KEY = gs.client[0].api_key[0].current_key;
const PROJECT = 'alfit-89567';
const REST = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

const tokenCache = new Map();

/** 실 DEV ID 토큰. rules 를 지나는 요청에 쓴다. */
async function idTokenFor(uid) {
  if (tokenCache.has(uid)) return tokenCache.get(uid);
  const custom = await admin.auth().createCustomToken(uid);
  const r = await fetch(
      `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${API_KEY}`,
      {method: 'POST', headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({token: custom, returnSecureToken: true})});
  const j = await r.json();
  if (!j.idToken) throw new Error('ID 토큰 발급 실패: ' + JSON.stringify(j).slice(0, 160));
  tokenCache.set(uid, j.idToken);
  return j.idToken;
}

const str = (v) => ({stringValue: v});
const arr = (vs) => ({arrayValue: {values: vs}});

/**
 * rules 를 지나는 부분 업데이트. 허용 200 / 차단 403.
 * @param {string} uid 호출자
 * @param {string} docPath 예: `users/xxx`
 * @param {object} fields Firestore REST value 맵
 * @return {Promise<{status:number, body:string}>} 결과
 */
async function clientPatch(uid, docPath, fields) {
  const token = await idTokenFor(uid);
  const mask = Object.keys(fields)
      .map((k) => `updateMask.fieldPaths=${encodeURIComponent(k)}`).join('&');
  const r = await fetch(`${REST}/${docPath}?${mask}`, {
    method: 'PATCH',
    headers: {'Content-Type': 'application/json', Authorization: `Bearer ${token}`},
    body: JSON.stringify({fields}),
  });
  return {status: r.status, body: (await r.text()).slice(0, 200)};
}

/** rules 를 지나는 문서 생성. */
async function clientCreate(uid, collection, docId, fields) {
  const token = await idTokenFor(uid);
  const r = await fetch(`${REST}/${collection}?documentId=${encodeURIComponent(docId)}`, {
    method: 'POST',
    headers: {'Content-Type': 'application/json', Authorization: `Bearer ${token}`},
    body: JSON.stringify({fields}),
  });
  return {status: r.status, body: (await r.text()).slice(0, 200)};
}

/** 1×1 투명 PNG — synthetic bytes. 실제 서류 이미지가 아니다. */
const PNG_1PX = Buffer.from(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/58BAwAI/AL+' +
    'XJ8BAAAAAElFTkSuQmCC', 'base64');

/** synthetic object 업로드. jpg 확장자여도 내용은 1px PNG 다. */
async function putObject(objPath, contentType = 'image/jpeg') {
  if (!objPath.includes(PREFIX)) {
    throw new Error(`fixture 접두(${PREFIX})가 없는 경로에 쓰려 했습니다: ${objPath}`);
  }
  await devBucket().file(objPath).save(PNG_1PX, {contentType, resumable: false});
  return objPath;
}

/** object 존재 여부. */
async function objExists(objPath) {
  const [e] = await devBucket().file(objPath).exists();
  return e;
}

/**
 * object-local 삭제 실패 주입 — temporary hold.
 *   버킷 IAM·Storage rules·서비스 계정은 건드리지 않는다(§52).
 *   되돌릴 수 있다.
 */
async function setHold(objPath, on) {
  if (!objPath.includes(PREFIX)) {
    throw new Error(`fixture 접두 없는 object 에 hold 를 걸려 했습니다: ${objPath}`);
  }
  await devBucket().file(objPath).setMetadata({temporaryHold: on});
}

/** fixture object 삭제 (hold 해제 후). */
async function delObject(objPath) {
  if (!objPath.includes(PREFIX)) {
    throw new Error(`fixture 접두 없는 object 삭제 시도: ${objPath}`);
  }
  const f = devBucket().file(objPath);
  try { await f.setMetadata({temporaryHold: false}); } catch (_) { /* 없으면 통과 */ }
  await f.delete({ignoreNotFound: true});
}

/** 판정 수집기. */
function makeChecker() {
  const rows = [];
  let fail = 0;
  return {
    check(label, actual, expected, note) {
      const ok = JSON.stringify(actual) === JSON.stringify(expected);
      if (!ok) fail++;
      rows.push({label, ok, actual, expected, note});
      const mark = ok ? 'PASS' : 'FAIL';
      console.log(`  [${mark}] ${label}` +
          (ok ? '' : `  기대=${JSON.stringify(expected)} 실제=${JSON.stringify(actual)}`) +
          (note ? `  (${note})` : ''));
    },
    note(label, value) {
      rows.push({label, ok: null, actual: value});
      console.log(`  [NOTE] ${label} = ${JSON.stringify(value)}`);
    },
    summary() {
      const total = rows.filter((r) => r.ok !== null).length;
      console.log(`\n판정 ${total - fail}/${total} PASS` + (fail ? `  실패 ${fail}건` : ''));
      return {rows, fail};
    },
  };
}

const mask = (s) => (typeof s === 'string' && s.length > 10
  ? s.slice(0, 6) + '…' + s.slice(-4) : s);

module.exports = {
  admin, db, devBucket, callAs: lib.callAs,
  PREFIX, idTokenFor, clientPatch, clientCreate,
  str, arr, putObject, objExists, setHold, delObject,
  makeChecker, mask,
};
