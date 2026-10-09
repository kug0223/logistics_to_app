/**
 * [R7-P4.4E.11C.0B §24·§27·§83] tombstone Firestore 권위 — **실제 rule 평가**.
 *
 *   source 문자열만 보고 PASS 하지 않는다. 격리 에뮬레이터에서 실제
 *   `firestore.rules` 를 지나가는 요청을 보내 allow/deny 를 측정한다.
 *
 *   격리: demo 프로젝트. 공유 DEV 를 건드리지 않는다.
 */
'use strict';

const PROJECT = 'demo-r7e11c0b';
process.env.GCLOUD_PROJECT = PROJECT;
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:6060';

const path = require('path');
const admin = require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin'));
if (!admin.apps.length) admin.initializeApp({projectId: PROJECT});
const db = admin.firestore();

const REST = `http://127.0.0.1:6060/v1/projects/${PROJECT}/databases/(default)/documents`;
const RUN = 'tomb' + Date.now().toString(36);
const OWNER = `${RUN}owner`;
const SUPER = `${RUN}super`;
const OTHER = `${RUN}other`;

const rows = [];
let fail = 0;
function check(label, actual, expected, note) {
  const ok = actual === expected;
  if (!ok) fail++;
  rows.push({label, ok});
  console.log(`  [${ok ? 'PASS' : 'FAIL'}] ${label}` +
      (ok ? `  (HTTP ${actual})` : `  기대=${expected} 실제=${actual}`) +
      (note ? `  ${note}` : ''));
}

/**
 * Firestore 에뮬레이터용 **서명 없는** ID 토큰.
 *
 *   이 repo 의 `firebase.json` 에는 auth 에뮬레이터 설정이 없고,
 *   그 파일은 tracked production 파일이라 이번 Phase 에서 건드리지 않는다.
 *   Firestore 에뮬레이터는 토큰 서명을 검증하지 않고 claim 만 읽으므로
 *   (공식 rules-unit-testing 이 쓰는 방식) 여기서 직접 만든다.
 *   실제 서비스에서는 통하지 않는다 — 에뮬레이터 전용이다.
 */
function emuToken(uid) {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  const header = {alg: 'none', typ: 'JWT'};
  const payload = {
    iss: `https://securetoken.google.com/${PROJECT}`,
    aud: PROJECT,
    auth_time: now,
    user_id: uid,
    sub: uid,
    iat: now,
    exp: now + 3600,
    firebase: {identities: {}, sign_in_provider: 'custom'},
  };
  return `${b64(header)}.${b64(payload)}.`;
}
async function idToken(uid) {
  return emuToken(uid);
}

const str = (v) => ({stringValue: v});

/** rules 를 지나는 단건 조회. */
async function get(tok, p) {
  const r = await fetch(`${REST}/${p}`, {headers: {Authorization: `Bearer ${tok}`}});
  return r.status;
}
/** rules 를 지나는 list(query). */
async function list(tok, col) {
  const r = await fetch(`${REST}/${col}?pageSize=1`,
      {headers: {Authorization: `Bearer ${tok}`}});
  return r.status;
}
async function create(tok, col, id, fields) {
  const r = await fetch(`${REST}/${col}?documentId=${encodeURIComponent(id)}`,
      {method: 'POST', headers: {Authorization: `Bearer ${tok}`, 'Content-Type': 'application/json'},
        body: JSON.stringify({fields})});
  return r.status;
}
async function patch(tok, p, fields) {
  const mask = Object.keys(fields)
      .map((k) => `updateMask.fieldPaths=${encodeURIComponent(k)}`).join('&');
  const r = await fetch(`${REST}/${p}?${mask}`,
      {method: 'PATCH', headers: {Authorization: `Bearer ${tok}`, 'Content-Type': 'application/json'},
        body: JSON.stringify({fields})});
  return r.status;
}
async function del(tok, p) {
  const r = await fetch(`${REST}/${p}`,
      {method: 'DELETE', headers: {Authorization: `Bearer ${tok}`}});
  return r.status;
}

(async () => {
  console.log('프로젝트:', PROJECT, '(격리 에뮬레이터)');

  // Auth 계정은 만들지 않는다 — rules 평가는 토큰 claim 과 Firestore 문서만
  //   본다. auth 에뮬레이터를 띄우려면 tracked firebase.json 을 고쳐야 한다.
  // Admin SDK 는 rules 를 우회한다 — canonical writer 역할.
  await db.doc(`users/${OWNER}`).set({uid: OWNER, name: 'owner', role: 'USER',
    accountStatus: 'active', createdAt: admin.firestore.Timestamp.now()});
  await db.doc(`users/${SUPER}`).set({uid: SUPER, name: 'super', role: 'SUPER_ADMIN',
    accountStatus: 'active', createdAt: admin.firestore.Timestamp.now()});
  await db.doc(`users/${OTHER}`).set({uid: OTHER, name: 'other', role: 'USER',
    accountStatus: 'active', createdAt: admin.firestore.Timestamp.now()});
  // 서버가 세운 tombstone — 이것을 클라이언트가 읽거나 지울 수 있는지 본다.
  await db.doc(`account_deletion_tombstones/${OWNER}`).set(
      {barrierAt: admin.firestore.Timestamp.now(), schemaVersion: 1});

  const tOwner = await idToken(OWNER);
  const tSuper = await idToken(SUPER);
  const COL = 'account_deletion_tombstones';
  const OWN = `${COL}/${OWNER}`;

  console.log('\n=== §27 owner (본인 uid tombstone) ===');
  check('ACC-TOMB-RULE-01 owner get DENY', await get(tOwner, OWN), 403);
  check('ACC-TOMB-RULE-02 owner list DENY', await list(tOwner, COL), 403);
  check('ACC-TOMB-RULE-03 owner create DENY',
      await create(tOwner, COL, `${OWNER}x`, {schemaVersion: str('1')}), 403);
  check('ACC-TOMB-RULE-04 owner update DENY',
      await patch(tOwner, OWN, {schemaVersion: str('9')}), 403);
  check('ACC-TOMB-RULE-05 owner delete DENY', await del(tOwner, OWN), 403);

  console.log('\n=== §24 SUPER_ADMIN client SDK ===');
  check('ACC-TOMB-RULE-10 SUPER_ADMIN get DENY', await get(tSuper, OWN), 403);
  check('ACC-TOMB-RULE-11 SUPER_ADMIN list DENY', await list(tSuper, COL), 403);
  check('ACC-TOMB-RULE-12 SUPER_ADMIN create DENY',
      await create(tSuper, COL, `${SUPER}y`, {schemaVersion: str('1')}), 403);
  check('ACC-TOMB-RULE-13 SUPER_ADMIN update DENY',
      await patch(tSuper, OWN, {schemaVersion: str('9')}), 403);
  check('ACC-TOMB-RULE-14 SUPER_ADMIN delete DENY', await del(tSuper, OWN), 403);

  console.log('\n=== §27 비인증 ===');
  const r20 = await fetch(`${REST}/${OWN}`);
  check('ACC-TOMB-RULE-20 unauth get DENY', r20.status, 403);

  console.log('\n=== tombstone 이 실제로 보존됐는지 (Admin SDK 확인) ===');
  const still = await db.doc(OWN).get();
  check('모든 거부 시도 뒤에도 tombstone 존재', still.exists, true, '');

  console.log('\n=== §21·§59 기존 권한 회귀 ===');
  check('ACC-TOMB-RULE-21a owner 본인 users 문서 get 허용',
      await get(tOwner, `users/${OWNER}`), 200);
  check('ACC-TOMB-RULE-21b owner 가 타인 users 문서 get 거부',
      await get(tOwner, `users/${OTHER}`), 403);
  check('ACC-TOMB-RULE-21c SUPER_ADMIN 이 타인 users 문서 get 허용',
      await get(tSuper, `users/${OTHER}`), 200);
  check('ACC-TOMB-RULE-21d owner 가 deleted_accounts get 거부',
      await get(tOwner, 'deleted_accounts/whatever'), 403);

  console.log(`\n판정 ${rows.filter((r) => r.ok).length}/${rows.length} PASS` +
      (fail ? `  실패 ${fail}건` : ''));

  console.log('\n=== teardown (격리 에뮬레이터 — 공유 DEV 무관) ===');
  for (const p of [OWN, `users/${OWNER}`, `users/${SUPER}`, `users/${OTHER}`]) {
    await db.doc(p).delete().catch(() => {});
  }
  console.log('  완료');
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.error('실패:', e.message); process.exit(1); });
