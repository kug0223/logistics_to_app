/**
 * [R7-P4.4E.11C.0A] 교란 제거 대조 실험.
 *
 *   앞선 probe 에서 `firestore.*` 가 들어간 모든 조건이 403 이었다.
 *   그것만으로는 "게이트가 올바르게 거부했다"와 "cross-service 호출 자체가
 *   실패해서 무조건 거부됐다"를 구별할 수 없다.
 *
 *   세 경로를 같은 actor·같은 모양으로 비교한다.
 *     control  : firestore 호출 없음
 *     get      : firestore.get().data.allowWrite == true   (문서 allowWrite=true)
 *     exists   : firestore.exists()                        (문서 존재)
 *
 *   control 만 허용되면 원인은 cross-service 호출이다.
 *
 *   추가로 rules 평가 시점(session start vs finalize)을 대조군에서 측정한다.
 */
'use strict';

const fs = require('fs');
const path = require('path');
const lib = require('./r7-fixture-lib');
const {admin, db} = lib;

const ROOT = path.resolve(__dirname, '..');
const API_KEY = JSON.parse(fs.readFileSync(
    path.join(ROOT, 'android', 'app', 'google-services.json'), 'utf8'))
    .client[0].api_key[0].current_key;
const BUCKET = JSON.parse(fs.readFileSync(path.join(ROOT, 'firebase.json'), 'utf8')
    .replace(/^﻿/, '')).storage.bucket;

const UID = '__r7ctl' + Date.now().toString(36);
const BYTES = Buffer.from(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/58BAwAI/AL+' +
    'XJ8BAAAAAElFTkSuQmCC', 'base64');

let tok = null;
async function token() {
  if (tok) return tok;
  const custom = await admin.auth().createCustomToken(UID);
  const r = await fetch(
      `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${API_KEY}`,
      {method: 'POST', headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({token: custom, returnSecureToken: true})});
  tok = (await r.json()).idToken;
  if (!tok) throw new Error('ID 토큰 발급 실패');
  return tok;
}

async function upload(p) {
  const t = await token();
  const r = await fetch(
      `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o?uploadType=media&name=${encodeURIComponent(p)}`,
      {method: 'POST', headers: {Authorization: `Firebase ${t}`, 'Content-Type': 'image/png'},
        body: BYTES});
  return r.status;
}

async function startSession(p) {
  const t = await token();
  const r = await fetch(
      `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o?uploadType=resumable&name=${encodeURIComponent(p)}`,
      {method: 'POST', headers: {
        Authorization: `Firebase ${t}`,
        'X-Goog-Upload-Protocol': 'resumable',
        'X-Goog-Upload-Command': 'start',
        'X-Goog-Upload-Header-Content-Length': String(BYTES.length),
        'X-Goog-Upload-Header-Content-Type': 'image/png',
      }, body: ''});
  return {status: r.status, url: r.headers.get('x-goog-upload-url')};
}

async function finalize(url) {
  const t = await token();
  const r = await fetch(url, {method: 'POST', headers: {
    Authorization: `Firebase ${t}`,
    'X-Goog-Upload-Command': 'upload, finalize',
    'X-Goog-Upload-Offset': '0',
    'Content-Type': 'image/png',
  }, body: BYTES});
  return r.status;
}

(async () => {
  console.log('버킷:', BUCKET, '/ probe uid 접두:', UID.slice(0, 12) + '…');
  try { await admin.auth().createUser({uid: UID}); } catch (e) {
    if (e.code !== 'auth/uid-already-exists') throw e;
  }
  // 두 firestore 조건이 모두 "허용"이어야 하는 상태로 둔다.
  await db.doc(`__r7_e11c_rules_probe/${UID}`).set({allowWrite: true, probe: true});

  console.log('\n=== 같은 actor · 같은 모양 · firestore 호출만 차이 ===');
  const c = await upload(`__r7_e11c_control_probe/${UID}/x.png`);
  const g = await upload(`__r7_e11c_rules_probe/${UID}/x.png`);
  const e = await upload(`__r7_e11c_exists_probe/${UID}/x.png`);
  console.log(`  control (firestore 호출 없음)        → HTTP ${c}`);
  console.log(`  get     (allowWrite=true 문서 존재)  → HTTP ${g}`);
  console.log(`  exists  (문서 존재)                  → HTTP ${e}`);
  const verdict = (c === 200 && g !== 200 && e !== 200)
    ? 'CROSS-SERVICE 호출이 원인 (control 만 통과)'
    : (c === 200 && g === 200 && e === 200)
      ? 'cross-service 정상 작동'
      : '해석 보류 — control 도 실패했다(별도 원인)';
  console.log(`  → 판정: ${verdict}`);

  console.log('\n=== rules 평가 시점 (대조군에서 측정) ===');
  const s = await startSession(`__r7_e11c_control_probe/${UID}/sess.png`);
  console.log(`  session start → HTTP ${s.status}, URL 수신=${!!s.url}`);
  if (s.url) {
    const f = await finalize(s.url);
    console.log(`  finalize      → HTTP ${f}`);
  }
  // 거부되는 경로에서 start 가 어떻게 나오는지
  const s2 = await startSession(`__r7_e11c_rules_probe/${UID}/sess.png`);
  console.log(`  거부 경로 session start → HTTP ${s2.status}, URL 수신=${!!s2.url}`);
  if (s2.url) {
    const f2 = await finalize(s2.url);
    console.log(`  거부 경로 finalize      → HTTP ${f2}`);
    console.log('  → rules 는 finalize 에서 평가된다 (start 는 통과)');
  }

  console.log('\n=== teardown ===');
  const bucket = admin.storage().bucket(BUCKET);
  for (const pre of ['__r7_e11c']) {
    const [fs2] = await bucket.getFiles({prefix: pre});
    for (const f of fs2) await f.delete({ignoreNotFound: true});
  }
  await db.doc(`__r7_e11c_rules_probe/${UID}`).delete().catch(() => {});
  await admin.auth().deleteUser(UID).catch(() => {});
  const [left] = await bucket.getFiles({prefix: '__r7_e11c'});
  console.log('  probe Storage 잔류:', left.length);
  console.log('  probe Firestore 잔류:',
      (await db.collection('__r7_e11c_rules_probe').get()).size);
  process.exit(0);
})().catch((err) => { console.error('실패:', err.message); process.exit(1); });
