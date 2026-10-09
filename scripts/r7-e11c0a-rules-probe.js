/**
 * [R7-P4.4E.11C.0A] cross-service Storage Rules + pre-barrier session 실측.
 *
 *   Q1 firestore.get()/exists() 가 이 프로젝트의 Storage Rules 에서 작동하나
 *   Q2 barrier 전에 시작한 resumable session 이 barrier 후에 finalize 되나
 *
 *   격리 네임스페이스만 쓴다(`__r7_e11c_*`). 제품 경로는 건드리지 않는다.
 *   실제 Firebase Storage endpoint(v0, Authorization: Firebase <idToken>)를
 *   쓴다 — SDK 가 쓰는 것과 같은 rules-enforced 경로다(generic GCS 아님).
 *
 *   [§76·§77] session URL 은 credential 로 취급한다 — 출력·저장하지 않는다.
 */
'use strict';

const fs = require('fs');
const path = require('path');
const lib = require('./r7-fixture-lib');

const {admin, db} = lib;
const ROOT = path.resolve(__dirname, '..');
const gs = JSON.parse(
    fs.readFileSync(path.join(ROOT, 'android', 'app', 'google-services.json'), 'utf8'));
const API_KEY = gs.client[0].api_key[0].current_key;
const BUCKET = JSON.parse(
    fs.readFileSync(path.join(ROOT, 'firebase.json'), 'utf8').replace(/^﻿/, ''))
    .storage.bucket;

const PROBE_COL = '__r7_e11c_rules_probe';
const UID = '__r7probe' + Date.now().toString(36);
const GET_NS = `__r7_e11c_rules_probe/${UID}`;
const EXISTS_NS = `__r7_e11c_exists_probe/${UID}`;

/** 1x1 PNG — synthetic bytes. */
const BYTES = Buffer.from(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/58BAwAI/AL+' +
    'XJ8BAAAAAElFTkSuQmCC', 'base64');

let idToken = null;
async function token() {
  if (idToken) return idToken;
  const custom = await admin.auth().createCustomToken(UID);
  const r = await fetch(
      `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${API_KEY}`,
      {method: 'POST', headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({token: custom, returnSecureToken: true})});
  const j = await r.json();
  if (!j.idToken) throw new Error('ID 토큰 발급 실패');
  idToken = j.idToken;
  return idToken;
}

const UP = (p) =>
  `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o?uploadType=media&name=${encodeURIComponent(p)}`;
const RS = (p) =>
  `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o?uploadType=resumable&name=${encodeURIComponent(p)}`;

/** 단순(비 resumable) 업로드 — rules 평가 1회. */
async function simpleUpload(objPath) {
  const t = await token();
  const r = await fetch(UP(objPath), {
    method: 'POST',
    headers: {Authorization: `Firebase ${t}`, 'Content-Type': 'image/png'},
    body: BYTES,
  });
  return r.status;
}

/** resumable session 시작 — session URL 은 반환하지만 절대 로깅하지 않는다. */
async function startSession(objPath) {
  const t = await token();
  const r = await fetch(RS(objPath), {
    method: 'POST',
    headers: {
      Authorization: `Firebase ${t}`,
      'X-Goog-Upload-Protocol': 'resumable',
      'X-Goog-Upload-Command': 'start',
      'X-Goog-Upload-Header-Content-Length': String(BYTES.length),
      'X-Goog-Upload-Header-Content-Type': 'image/png',
      'Content-Type': 'application/json',
    },
    body: '',
  });
  const url = r.headers.get('x-goog-upload-url');
  return {status: r.status, url: url || null};
}

/** 이미 시작된 session 을 finalize. */
async function finalizeSession(url) {
  const t = await token();
  const r = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Firebase ${t}`,
      'X-Goog-Upload-Command': 'upload, finalize',
      'X-Goog-Upload-Offset': '0',
      'Content-Type': 'image/png',
    },
    body: BYTES,
  });
  return r.status;
}

const rows = [];
let fail = 0;
function check(label, actual, expected, note) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) fail++;
  rows.push({label, ok});
  console.log(`  [${ok ? 'PASS' : 'FAIL'}] ${label}` +
      (ok ? `  (${JSON.stringify(actual)})` : `  기대=${JSON.stringify(expected)} 실제=${JSON.stringify(actual)}`) +
      (note ? `  ${note}` : ''));
}
function note(label, v) {
  console.log(`  [NOTE] ${label} = ${JSON.stringify(v)}`);
  rows.push({label, ok: null, v});
}

const setBarrier = (allowWrite) =>
  db.doc(`${PROBE_COL}/${UID}`).set({allowWrite, probe: true});

(async () => {
  console.log('버킷:', BUCKET);
  console.log('probe uid 접두:', UID.slice(0, 14) + '…');

  try { await admin.auth().createUser({uid: UID}); } catch (e) {
    if (e.code !== 'auth/uid-already-exists') throw e;
  }

  // ── Q1-a firestore.get() + 필드 읽기 ─────────────────────────
  console.log('\n=== Q1-a firestore.get() 필드 읽기 ===');
  await setBarrier(true);
  const s1 = await simpleUpload(`${GET_NS}/allow.png`);
  check('allowWrite=true → 업로드 허용', s1 === 200, true, `HTTP ${s1}`);

  await setBarrier(false);
  const s2 = await simpleUpload(`${GET_NS}/deny.png`);
  check('allowWrite=false → 업로드 거부', s2 === 403, true, `HTTP ${s2}`);

  await db.doc(`${PROBE_COL}/${UID}`).delete();
  const s3 = await simpleUpload(`${GET_NS}/absent.png`);
  check('문서 없음 → fail closed(거부)', s3 === 403, true, `HTTP ${s3}`);

  // ── Q1-b firestore.exists() ─────────────────────────────────
  console.log('\n=== Q1-b firestore.exists() ===');
  const e1 = await simpleUpload(`${EXISTS_NS}/absent.png`);
  check('문서 없음 → 거부', e1 === 403, true, `HTTP ${e1}`);
  await setBarrier(false); // 값은 무관 — 존재만 본다
  const e2 = await simpleUpload(`${EXISTS_NS}/present.png`);
  check('문서 존재 → 허용(값 무관)', e2 === 200, true, `HTTP ${e2}`);

  // ── Q2 pre-barrier resumable session ────────────────────────
  console.log('\n=== Q2 barrier 전 시작한 resumable session ===');
  await setBarrier(true);
  const sess = await startSession(`${GET_NS}/prebarrier.png`);
  check('barrier 전 session 시작 성공', sess.status === 200 && !!sess.url, true,
      `HTTP ${sess.status}`);
  if (!sess.url) {
    note('session URL 미수신 — Q2 측정 불가', false);
  } else {
    // barrier 를 닫는다 (= Final 이 destructive phase 에 진입한 순간)
    await setBarrier(false);
    const after = await finalizeSession(sess.url);
    note('barrier 후 기존 session finalize HTTP', after);
    const finalized = after >= 200 && after < 300;
    note('기존 session 이 object 를 만들었나', finalized);
    // 실제로 object 가 생겼는지 bucket 에서 확인한다 — HTTP 만 믿지 않는다.
    const [exists] = await admin.storage().bucket(BUCKET)
        .file(`${GET_NS}/prebarrier.png`).exists();
    note('bucket 에 object 실재', exists);
    check('[Q2 판정] barrier 후 기존 session 이 거부된다', finalized === false && exists === false,
        true, finalized ? '→ CASE B (late arrival 가능)' : '→ CASE A');
  }

  // ── §34 barrier 후 신규 write 전수 ───────────────────────────
  console.log('\n=== §34 barrier 후 신규 write ===');
  const n1 = await simpleUpload(`${GET_NS}/newafter.png`);
  check('신규 단순 업로드 → 거부', n1 === 403, true, `HTTP ${n1}`);
  const n2 = await startSession(`${GET_NS}/newsession.png`);
  check('신규 session 시작 → 거부', n2.status === 403, true, `HTTP ${n2.status}`);
  // 덮어쓰기(고정 경로 — 프로필과 같은 모양)
  await setBarrier(true);
  const ov0 = await simpleUpload(`${GET_NS}/fixed/photo.png`);
  check('사전 조건: 고정 경로 업로드 성공', ov0 === 200, true, `HTTP ${ov0}`);
  await setBarrier(false);
  const ov1 = await simpleUpload(`${GET_NS}/fixed/photo.png`);
  check('barrier 후 덮어쓰기 → 거부', ov1 === 403, true, `HTTP ${ov1}`);

  // ── 제품 경로가 영향받지 않았는지 ────────────────────────────
  console.log('\n=== 제품 경로 무영향 확인 ===');
  const prod = await simpleUpload(`users/${UID}/bankbook_1790000000000.jpg`);
  note('probe uid 로 users/{uid}/ 업로드 HTTP', prod);
  check('제품 경로는 기존 규칙대로 동작(본인 경로 허용)', prod === 200, true,
      '기존 /users/{uid}/** 규칙 변경 0');

  console.log(`\n판정 ${rows.filter((r) => r.ok === true).length}/` +
      `${rows.filter((r) => r.ok !== null).length} PASS` + (fail ? `  실패 ${fail}건` : ''));

  // ── teardown (§66) ──────────────────────────────────────────
  console.log('\n=== teardown ===');
  const bucket = admin.storage().bucket(BUCKET);
  const [objs] = await bucket.getFiles({prefix: '__r7_e11c'});
  for (const f of objs) await f.delete({ignoreNotFound: true});
  const [own] = await bucket.getFiles({prefix: `users/${UID}/`});
  for (const f of own) await f.delete({ignoreNotFound: true});
  await db.doc(`${PROBE_COL}/${UID}`).delete().catch(() => {});
  await admin.auth().deleteUser(UID).catch(() => {});
  const [left1] = await bucket.getFiles({prefix: '__r7_e11c'});
  const [left2] = await bucket.getFiles({prefix: `users/${UID}/`});
  console.log('  probe Storage 잔류:', left1.length + left2.length);
  console.log('  probe Firestore 잔류:',
      (await db.collection(PROBE_COL).get()).size);
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.error('실패:', e.message); process.exit(1); });
