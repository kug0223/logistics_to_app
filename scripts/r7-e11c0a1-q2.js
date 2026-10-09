/**
 * [R7-P4.4E.11C.0A.1] Q1 negative + Q2 resumable cross-barrier 실측.
 *
 *   Q1 positive 는 이미 200 으로 닫혔다(control/get/exists). 여기서는
 *   negative 를 확인하고 — 이제 positive 가 존재하므로 403 이 의미를 갖는다 —
 *   barrier 를 실제로 넘겨 본다.
 *
 *   측정 대상
 *     Q2-CTL   barrier 를 안 닫으면 session 이 정상 finalize 되는가 (대조군)
 *     Q2-NEW   barrier 닫은 뒤 **새** session 은 어떻게 되는가
 *     Q2-CRE   barrier 닫기 **전에 시작한** create session 이 finalize 되는가
 *     Q2-OVW   barrier 닫기 전에 시작한 **덮어쓰기** session 이 finalize 되는가
 *
 *   [§18] resumable session URI 는 credential 이다 — 출력·저장하지 않는다.
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

const UID = '__r7q2' + Date.now().toString(36);
const NS = `__r7_e11c_rules_probe/${UID}`;
const ENS = `__r7_e11c_exists_probe/${UID}`;
const DOC = `__r7_e11c_rules_probe/${UID}`;

const V1 = Buffer.from(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/58BAwAI/AL+' +
    'XJ8BAAAAAElFTkSuQmCC', 'base64');
// 덮어쓰기 구분용 — 길이가 다르다.
const V2 = Buffer.concat([V1, Buffer.alloc(32, 0)]);

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

async function simpleUpload(p, body = V1) {
  const t = await token();
  const r = await fetch(
      `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o?uploadType=media&name=${encodeURIComponent(p)}`,
      {method: 'POST', headers: {Authorization: `Firebase ${t}`, 'Content-Type': 'image/png'},
        body});
  return r.status;
}

/** session 시작. 반환된 url 은 호출부에서도 로깅하지 않는다. */
async function startSession(p, body = V1) {
  const t = await token();
  const r = await fetch(
      `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o?uploadType=resumable&name=${encodeURIComponent(p)}`,
      {method: 'POST', headers: {
        Authorization: `Firebase ${t}`,
        'X-Goog-Upload-Protocol': 'resumable',
        'X-Goog-Upload-Command': 'start',
        'X-Goog-Upload-Header-Content-Length': String(body.length),
        'X-Goog-Upload-Header-Content-Type': 'image/png',
      }, body: ''});
  return {status: r.status, url: r.headers.get('x-goog-upload-url')};
}

async function finalizeSession(url, body = V1) {
  const t = await token();
  const r = await fetch(url, {method: 'POST', headers: {
    Authorization: `Firebase ${t}`,
    'X-Goog-Upload-Command': 'upload, finalize',
    'X-Goog-Upload-Offset': '0',
    'Content-Type': 'image/png',
  }, body});
  return r.status;
}

const bucket = () => admin.storage().bucket(BUCKET);
async function meta(p) {
  try {
    const [md] = await bucket().file(p).getMetadata();
    return {exists: true, generation: String(md.generation), size: Number(md.size)};
  } catch (e) {
    return {exists: false, generation: null, size: null};
  }
}

const rows = [];
let fail = 0;
function check(label, actual, expected, note) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) fail++;
  rows.push({label, ok});
  console.log(`  [${ok ? 'PASS' : 'FAIL'}] ${label}` +
      (ok ? '' : `  기대=${JSON.stringify(expected)} 실제=${JSON.stringify(actual)}`) +
      (note ? `  ${note}` : ''));
}
function note(label, v) {
  console.log(`  [NOTE] ${label} = ${JSON.stringify(v)}`);
}

const barrier = async (allowWrite) => {
  await db.doc(DOC).set({allowWrite, probe: true});
  const back = (await db.doc(DOC).get()).data();
  return back && back.allowWrite;
};

(async () => {
  console.log('버킷:', BUCKET, '/ probe uid 접두:', UID.slice(0, 11) + '…');
  try { await admin.auth().createUser({uid: UID}); } catch (e) {
    if (e.code !== 'auth/uid-already-exists') throw e;
  }

  // ══ §11 Q1 negative (positive 200 이 확인된 뒤라 의미 있다) ══
  console.log('\n=== §11 Q1 negative ===');
  await barrier(false);
  check('get: allowWrite=false → 403', await simpleUpload(`${NS}/neg1.png`), 403);
  check('exists: 문서 존재 → 200 (값 무관)', await simpleUpload(`${ENS}/pos.png`), 200);
  await db.doc(DOC).delete();
  check('get: 문서 없음 → 403', await simpleUpload(`${NS}/neg2.png`), 403);
  check('exists: 문서 없음 → 403', await simpleUpload(`${ENS}/neg.png`), 403);

  // ══ §16 Q2 CONTROL — barrier 를 닫지 않으면 정상 finalize ══
  console.log('\n=== §16 Q2-CTL 대조군 (barrier 계속 열림) ===');
  note('barrier read-back', await barrier(true));
  const ctl = await startSession(`${NS}/q2ctl.png`);
  check('session start 200', ctl.status, 200);
  check('session URL 수신', !!ctl.url, true);
  const ctlFin = await finalizeSession(ctl.url);
  check('finalize 성공(2xx)', ctlFin >= 200 && ctlFin < 300, true, `HTTP ${ctlFin}`);
  const ctlMeta = await meta(`${NS}/q2ctl.png`);
  check('object 실재', ctlMeta.exists, true);
  note('generation', ctlMeta.generation ? '…' + ctlMeta.generation.slice(-6) : null);

  // ══ §19 Q2-NEW — barrier 닫은 뒤 새 session ══
  console.log('\n=== §19 Q2-NEW barrier 닫은 뒤 신규 session ===');
  note('barrier read-back', await barrier(false));
  const nw = await startSession(`${NS}/q2new.png`);
  note('session start HTTP (200 이어도 실패 아님)', nw.status);
  if (nw.url) {
    const f = await finalizeSession(nw.url);
    check('finalize 거부', f === 403, true, `HTTP ${f}`);
  }
  const nwMeta = await meta(`${NS}/q2new.png`);
  check('object 없음', nwMeta.exists, false);

  // ══ §17 Q2-CRE — barrier 전에 시작한 create session ══
  console.log('\n=== §17 Q2-CRE barrier 전 시작 → barrier 닫음 → finalize ===');
  note('T0 barrier read-back', await barrier(true));
  const cre = await startSession(`${NS}/q2create.png`);           // T1
  check('T1 session start 200', cre.status, 200);
  check('T1 session URL 수신', !!cre.url, true);
  note('T2 barrier flip → read-back', await barrier(false));      // T2·T3
  // T4 — 같은 상태에서 신규 write 가 실제로 막히는지 교차 확인
  check('T4 신규 단순 write 거부 (barrier 작동 확인)',
      await simpleUpload(`${NS}/t4probe.png`), 403);
  const creFin = await finalizeSession(cre.url);                   // T5
  note('T5 pre-barrier create session finalize HTTP', creFin);
  const creMeta = await meta(`${NS}/q2create.png`);                // T6
  note('T6 object 실재', creMeta.exists);
  check('[Q2-CRE 판정] barrier 후 finalize 거부 + object 없음',
      {denied: creFin === 403, absent: creMeta.exists === false},
      {denied: true, absent: true},
      creMeta.exists ? '→ CASE B 신호' : '→ CASE A 신호');

  // ══ §21 Q2-OVW — barrier 전에 시작한 덮어쓰기 session ══
  console.log('\n=== §21 Q2-OVW 덮어쓰기 race ===');
  note('barrier read-back', await barrier(true));
  const ovwPath = `${NS}/q2overwrite.png`;
  check('V1 선행 생성', await simpleUpload(ovwPath, V1), 200);
  const v1 = await meta(ovwPath);
  note('V1 generation/size', {g: v1.generation ? '…' + v1.generation.slice(-6) : null, s: v1.size});
  const ovw = await startSession(ovwPath, V2);
  check('덮어쓰기 session start 200', ovw.status, 200);
  note('barrier flip → read-back', await barrier(false));
  const ovwFin = await finalizeSession(ovw.url, V2);
  note('덮어쓰기 finalize HTTP', ovwFin);
  const v2 = await meta(ovwPath);
  note('finalize 후 generation/size',
      {g: v2.generation ? '…' + v2.generation.slice(-6) : null, s: v2.size});
  check('[Q2-OVW 판정] 거부 + generation·size 불변',
      {denied: ovwFin === 403, sameGen: v2.generation === v1.generation, sameSize: v2.size === v1.size},
      {denied: true, sameGen: true, sameSize: true},
      v2.size !== v1.size ? '→ 덮어쓰기가 성립했다' : '');

  // ══ 최종 CASE 판정 ══
  console.log('\n=== §22·§23 CASE 판정 ===');
  const caseA = (creFin === 403 && !creMeta.exists) &&
                (ovwFin === 403 && v2.generation === v1.generation) &&
                !nwMeta.exists;
  console.log('  new session after barrier → object 0 :', !nwMeta.exists);
  console.log('  pre-barrier CREATE finalize denied   :', creFin === 403 && !creMeta.exists);
  console.log('  pre-barrier OVERWRITE finalize denied:', ovwFin === 403 && v2.generation === v1.generation);
  console.log('  → CASE ' + (caseA ? 'A CONFIRMED (rule barrier 단독으로 충분)'
    : 'B (late-arrival cleanup 필요)'));

  console.log(`\n판정 ${rows.filter((r) => r.ok).length}/${rows.length} PASS` +
      (fail ? `  실패 ${fail}건` : ''));

  // ══ §31 teardown ══
  console.log('\n=== teardown ===');
  await barrier(true); // 정리를 위해 잠시 허용 — 어차피 Admin SDK 로 지운다
  const [objs] = await bucket().getFiles({prefix: '__r7_e11c'});
  for (const f of objs) await f.delete({ignoreNotFound: true});
  await db.doc(DOC).delete().catch(() => {});
  await admin.auth().deleteUser(UID).catch(() => {});
  const [left] = await bucket().getFiles({prefix: '__r7_e11c'});
  console.log('  probe Storage 잔류:', left.length);
  console.log('  probe Firestore 잔류:',
      (await db.collection('__r7_e11c_rules_probe').get()).size);
  process.exit(0);
})().catch((e) => { console.error('실패:', e.message); process.exit(1); });
