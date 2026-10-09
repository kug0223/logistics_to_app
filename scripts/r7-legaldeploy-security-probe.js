/**
 * [R7-LEGAL.DEPLOY §22·§23] 배포된 Rules 를 **런타임**에서 확인한다.
 *
 *   안전 설계
 *     · 성공을 기대하는 쓰기는 하나도 없다. 전부 403 을 기대한다.
 *     · 혹시 통과하면 그 자리에서 지운다(흔적 0).
 *     · canonical 문서(app_settings/legal_terms)에는 **쓰기를 시도하지
 *       않는다** — 통과했을 때 법적 문서가 더럽혀지기 때문이다.
 *       그 축은 에뮬레이터(AS-WRITE-02)가 이미 지킨다.
 *
 *   PII 를 출력하지 않는다.
 */
'use strict';

const https = require('https');
const path = require('path');
const lib = require('./r7-fixture-lib');
const {db} = lib;

const ROOT = path.resolve(__dirname, '..');
const admin = require(path.join(ROOT, 'functions', 'node_modules',
  'firebase-admin'));

const PROJECT = 'alfit-89567';
const FS_HOST = 'firestore.googleapis.com';
const BASE = `/v1/projects/${PROJECT}/databases/(default)/documents`;

function readClientConfig() {
  const fs = require('fs');
  const j = JSON.parse(fs.readFileSync(
    path.join(ROOT, 'android', 'app', 'google-services.json'), 'utf8'));
  return j.client[0].api_key[0].current_key;
}
const API_KEY = readClientConfig();

function request(method, urlPath, token, body) {
  return new Promise((resolve) => {
    const payload = body ? JSON.stringify(body) : null;
    const headers = {};
    if (payload) {
      headers['Content-Type'] = 'application/json';
      headers['Content-Length'] = Buffer.byteLength(payload);
    }
    if (token) headers['Authorization'] = 'Bearer ' + token;
    const req = https.request({host: FS_HOST, path: urlPath, method, headers},
      (res) => {
        let d = '';
        res.on('data', (c) => (d += c));
        res.on('end', () => resolve({status: res.statusCode, body: d}));
      });
    req.on('error', (e) => resolve({status: -1, body: String(e)}));
    if (payload) req.write(payload);
    req.end();
  });
}

async function idTokenFor(uid) {
  const custom = await admin.auth().createCustomToken(uid);
  const r = await new Promise((resolve) => {
    const payload = JSON.stringify({token: custom, returnSecureToken: true});
    const req = https.request({
      host: 'identitytoolkit.googleapis.com',
      path: `/v1/accounts:signInWithCustomToken?key=${API_KEY}`,
      method: 'POST',
      headers: {'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(payload)},
    }, (res) => {
      let d = '';
      res.on('data', (c) => (d += c));
      res.on('end', () => resolve(JSON.parse(d || '{}')));
    });
    req.on('error', () => resolve({}));
    req.write(payload);
    req.end();
  });
  return r.idToken || null;
}

let pass = 0;
const fails = [];
function check(id, ok, detail) {
  if (ok) {
    pass++;
    console.log(`  ok   ${id}`);
  } else {
    fails.push(`${id} — ${detail}`);
    console.log(`  FAIL ${id} — ${detail}`);
  }
}

(async () => {
  // 대표 사용자 하나(역할만 쓰고 식별값은 출력하지 않는다).
  const users = await db.collection('users').where('role', '==', 'USER')
    .limit(1).get();
  if (users.empty) throw new Error('USER fixture 없음');
  const uid = users.docs[0].id;
  const token = await idTokenFor(uid);
  if (!token) throw new Error('idToken 발급 실패');

  console.log('=== §22 익명 읽기 (공개 법적 문서) ===');
  const anonTerms = await request('GET',
    `${BASE}/app_settings/legal_terms?key=${API_KEY}`, null);
  check('A1 익명이 현재 약관을 읽는다', anonTerms.status === 200,
    `status=${anonTerms.status}`);

  const anonRev = await request('GET',
    `${BASE}/legal_revisions/zzprober7?key=${API_KEY}`, null);
  // 아직 발행본이 없으므로 404 가 정상 — 403(권한 거부)이 아니어야 한다.
  check('A2 익명이 발행본 경로를 읽을 수 있다(없으면 404)',
    anonRev.status === 200 || anonRev.status === 404,
    `status=${anonRev.status}`);

  const anonConfig = await request('GET',
    `${BASE}/app_settings/app_config?key=${API_KEY}`, null);
  check('A3 익명은 legal_terms 외 설정을 읽지 못한다',
    anonConfig.status === 403, `status=${anonConfig.status}`);

  console.log('\n=== §23 쓰기 차단 (전부 거부를 기대한다) ===');
  const probeDoc = {fields: {probe: {booleanValue: true}}};

  const anonRevWrite = await request('PATCH',
    `${BASE}/legal_revisions/zzprober7?key=${API_KEY}`, null, probeDoc);
  check('B1 익명은 발행본을 쓸 수 없다', anonRevWrite.status === 403,
    `status=${anonRevWrite.status}`);

  const userRevWrite = await request('PATCH',
    `${BASE}/legal_revisions/zzprober7?key=${API_KEY}`, token, probeDoc);
  check('B2 로그인 사용자도 발행본을 쓸 수 없다', userRevWrite.status === 403,
    `status=${userRevWrite.status}`);

  const selfEvent = await request('PATCH',
    `${BASE}/users/${uid}/consentEvents/zzprober7?key=${API_KEY}`,
    token, probeDoc);
  check('B3 본인도 동의 증거를 쓸 수 없다', selfEvent.status === 403,
    `status=${selfEvent.status}`);

  console.log('\n=== 본인 증거 읽기 ===');
  const selfRead = await request('GET',
    `${BASE}/users/${uid}/consentEvents/zznoner7?key=${API_KEY}`, token);
  check('C1 본인은 자기 증거 경로를 읽을 수 있다(없으면 404)',
    selfRead.status === 200 || selfRead.status === 404,
    `status=${selfRead.status}`);

  // 혹시라도 통과한 쓰기가 있으면 흔적을 지운다.
  for (const [label, res, p] of [
    ['legal_revisions/zzprober7', anonRevWrite, `${BASE}/legal_revisions/zzprober7`],
    ['legal_revisions/zzprober7(user)', userRevWrite, `${BASE}/legal_revisions/zzprober7`],
    ['consentEvents/zzprober7', selfEvent,
      `${BASE}/users/${uid}/consentEvents/zzprober7`],
  ]) {
    if (res.status >= 200 && res.status < 300) {
      console.log(`  ⚠️ 예상과 달리 통과함 — 정리: ${label}`);
      await request('DELETE', `${p}?key=${API_KEY}`, token);
    }
  }

  console.log(`\n${pass} passed, ${fails.length} failed`);
  for (const f of fails) console.log('  - ' + f);
  process.exit(fails.length ? 1 : 0);
})().catch((e) => {
  console.error('실패:', e.message);
  process.exit(1);
});
