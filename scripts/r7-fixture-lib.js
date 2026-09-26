/**
 * [R7-PRE0] fixture seed 전용 호출 계층.
 *
 * canonical writer(CF)만 부른다. Firestore 직접 쓰기는 하지 않는다 —
 * 서버 guard 를 지나야 "존재할 수 있는 상태"만 만들어진다.
 *
 * 읽기(verify)는 Admin SDK 를 쓴다. 검증은 상태를 바꾸지 않는다.
 *
 * 보안: 토큰·키를 출력하지 않는다.
 */
'use strict';

const fs = require('fs');
const path = require('path');
const https = require('https');

const ROOT = path.resolve(__dirname, '..');
const EXPECTED_PROJECT = 'alfit-89567';
const REGION_HOST = 'asia-northeast3-alfit-89567.cloudfunctions.net';

// ── 서비스 계정 ─────────────────────────────────────────────────────
function findServiceAccount() {
  const envPath = process.env.ALFIT_SERVICE_ACCOUNT_PATH;
  const candidates = [];
  if (envPath) candidates.push(envPath);
  for (const dir of [path.join(ROOT, 'functions'), path.join(ROOT, 'scripts')]) {
    if (!fs.existsSync(dir)) continue;
    for (const f of fs.readdirSync(dir)) {
      if (/-adminsdk-.*\.json$/.test(f)) candidates.push(path.join(dir, f));
    }
  }
  for (const p of candidates) {
    if (!fs.existsSync(p)) continue;
    const key = JSON.parse(fs.readFileSync(p, 'utf8'));
    if (key.project_id === EXPECTED_PROJECT) return key;
  }
  throw new Error(
      `DEV(${EXPECTED_PROJECT}) 서비스 계정 키를 찾지 못했습니다. ` +
      'functions/ 또는 scripts/ 아래 *-adminsdk-*.json 이 필요합니다.');
}

// ── Firebase 클라이언트 설정 (google-services.json — 비밀 아님) ─────
function clientConfig() {
  const p = path.join(ROOT, 'android', 'app', 'google-services.json');
  const gs = JSON.parse(fs.readFileSync(p, 'utf8'));
  if (gs.project_info.project_id !== EXPECTED_PROJECT) {
    throw new Error('google-services.json 의 project_id 가 DEV 가 아닙니다.');
  }
  const c = gs.client[0];
  return {appId: c.client_info.mobilesdk_app_id, apiKey: c.api_key[0].current_key};
}

// ── Storage 버킷 ────────────────────────────────────────────────────
//
//   [CORRECTION-DEV-CONTRACT-STORAGE-ORPHAN-CLEANUP]
//
//   initializeApp 에 storageBucket 을 주지 않았다. Cloud Functions 런타임은
//   기본 버킷을 알아서 해상도하지만 스크립트는 그러지 못한다 —
//   `admin.storage().bucket()` 이 매번 throw 했고, fixture cleanup 의
//   `catch (_) {}` 가 그것을 삼켰다. 그래서 계약 서명·PDF artifact 는
//   **한 번도 지워지지 않았다**(실측 orphan 229건).
//
//   이름을 추측하지 않는다. firebase.json 의 storage.bucket 이 이 프로젝트의
//   canonical 값이고, 그것이 DEV 프로젝트의 것인지 확인한 뒤 쓴다.
function canonicalBucket() {
  const cfg = JSON.parse(
      fs.readFileSync(path.join(ROOT, 'firebase.json'), 'utf8')
          .replace(/^﻿/, ''));
  const b = cfg && cfg.storage && cfg.storage.bucket;
  if (typeof b !== 'string' || b.length === 0) {
    throw new Error('firebase.json 에 storage.bucket 이 없습니다.');
  }
  if (!b.startsWith(`${EXPECTED_PROJECT}.`)) {
    throw new Error(
        `firebase.json 의 버킷("${b}")이 DEV 프로젝트의 것이 아닙니다.`);
  }
  return b;
}

const key = findServiceAccount();
const admin = require(path.join(ROOT, 'functions', 'node_modules', 'firebase-admin'));
const STORAGE_BUCKET = canonicalBucket();
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(key),
    projectId: EXPECTED_PROJECT,
    storageBucket: STORAGE_BUCKET,
  });
}
const db = admin.firestore();

/**
 * 삭제 직전 방어선. 버킷을 잘못 잡은 채로 지우는 일이 없게, 쓰기 경로는
 * 반드시 이것을 통해 버킷을 얻는다.
 * @return {import('@google-cloud/storage').Bucket} DEV canonical 버킷
 */
function devBucket() {
  const b = admin.storage().bucket();
  if (b.name !== STORAGE_BUCKET) {
    throw new Error(`버킷이 예상과 다릅니다: ${b.name}`);
  }
  if (!b.name.startsWith(`${EXPECTED_PROJECT}.`)) {
    throw new Error(`DEV 프로젝트의 버킷이 아닙니다: ${b.name}`);
  }
  return b;
}
const {appId: APP_ID, apiKey: API_KEY} = clientConfig();

function post(host, urlPath, body, headers = {}) {
  return new Promise((resolve, reject) => {
    const payload = JSON.stringify(body);
    const req = https.request({
      host, path: urlPath, method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(payload),
        ...headers,
      },
    }, (res) => {
      res.setEncoding('utf8');
      let buf = '';
      res.on('data', (c) => { buf += c; });
      res.on('end', () => resolve({status: res.statusCode, body: buf}));
    });
    req.on('error', reject);
    req.write(payload);
    req.end();
  });
}

const idTokenCache = new Map();

async function idTokenFor(uid) {
  if (idTokenCache.has(uid)) return idTokenCache.get(uid);
  const custom = await admin.auth().createCustomToken(uid);
  const r = await post('identitytoolkit.googleapis.com',
      `/v1/accounts:signInWithCustomToken?key=${API_KEY}`,
      {token: custom, returnSecureToken: true});
  const parsed = JSON.parse(r.body);
  if (!parsed.idToken) {
    throw new Error(`ID 토큰 발급 실패 (uid=${uid.slice(0, 8)}…)`);
  }
  idTokenCache.set(uid, parsed.idToken);
  return parsed.idToken;
}

/**
 * canonical writer 호출. 실패는 그대로 던진다 —
 * seed 가 반쯤 만들어진 상태로 넘어가지 않게 한다.
 */
async function callAs(uid, fn, data) {
  const idToken = await idTokenFor(uid);
  const ac = await admin.appCheck().createToken(APP_ID);
  const r = await post(REGION_HOST, '/' + fn, {data}, {
    Authorization: 'Bearer ' + idToken,
    'X-Firebase-AppCheck': ac.token,
  });
  let parsed;
  try { parsed = JSON.parse(r.body); } catch (_) { parsed = {}; }
  if (r.status !== 200) {
    const err = parsed.error || {};
    const e = new Error(
        `${fn} 실패 [${err.status || r.status}] ${err.message || r.body.slice(0, 160)}`);
    // [R7-P1-2.1] 구조화된 오류를 메시지 안에만 묻어 두면, 호출부는 코드를
    //   확인하려고 문자열을 파싱하게 된다. 그건 문구 한 번 바뀌면 조용히
    //   틀어지는 판정이다. wire 의 canonical status 를 그대로 얹어 둔다.
    //   (Firebase SDK 의 `permission-denied` 와 같은 값의 다른 표기다:
    //    wire=PERMISSION_DENIED ↔ SDK=permission-denied)
    e.wireCode = err.status || null;
    e.httpStatus = r.status;
    throw e;
  }
  return parsed.result;
}

// ── KST 날짜 도우미 ─────────────────────────────────────────────────
const KST_MS = 9 * 60 * 60 * 1000;

/** KST 달력 기준 offsetDays 만큼 떨어진 날의 KST 자정 epoch ms. */
function kstMidnightMs(offsetDays = 0) {
  const nowKst = new Date(Date.now() + KST_MS);
  const y = nowKst.getUTCFullYear();
  const m = nowKst.getUTCMonth();
  const d = nowKst.getUTCDate() + offsetDays;
  return Date.UTC(y, m, d) - KST_MS;
}

/** KST 'YYYY-MM-DD'. */
function kstDateKey(offsetDays = 0) {
  return new Date(kstMidnightMs(offsetDays) + KST_MS).toISOString().slice(0, 10);
}

/** KST 기준 요일 라벨. */
function kstWeekday(offsetDays = 0) {
  const names = ['월', '화', '수', '목', '금', '토', '일'];
  const d = new Date(kstMidnightMs(offsetDays) + KST_MS).getUTCDay();
  return names[d === 0 ? 6 : d - 1];
}

module.exports = {
  admin, db, callAs,
  kstMidnightMs, kstDateKey, kstWeekday,
  EXPECTED_PROJECT,
  STORAGE_BUCKET, devBucket,
};
