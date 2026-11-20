/**
 * [PREDEVICE-CONTRACT-PDF-REMEDIATION §9] 계약서 PDF Signed URL 발급을
 * **production 함수 그대로** 에뮬레이터에서 돌려 권한별 결과를 본다.
 *
 *   무엇을 보는가
 *     · 계약 당사자 근로자 → 허용
 *     · 사업장 owner / adminIds 관리자 → 허용
 *     · canManageContract SubAdmin → 허용
 *     · canManageContract 없는 SubAdmin → 거부
 *     · 무관한 사업장 관리자 → 거부
 *     · 다른 근로자 → 거부
 *     · 비로그인 → 거부
 *     · 권한 상실 후 **재발급** → 거부 (과거 링크가 근거가 되지 않는다)
 *     · 다른 계약 경로 주입 → 거부
 *     · 레거시 pdfUrl 만 있는 계약 → 경로 역산으로 허용
 *     · PDF 없는 계약 / 파일 없는 계약 → 서로 다른 오류
 *     · 응답·로그에 토큰이 없다
 *
 *   격리: demo 프로젝트. 공유 DEV/PROD 쓰기 0. 합성 PDF만 사용한다.
 *   production 로직은 손대지 않는다 — 슬라이스해서 그대로 실행한다.
 */
'use strict';

const PROJECT = 'demo-r8pdfurl';
process.env.GCLOUD_PROJECT = PROJECT;
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:6060';
process.env.FIREBASE_STORAGE_EMULATOR_HOST = '127.0.0.1:6061';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const admin = require('../functions/node_modules/firebase-admin');

const BUCKET = `${PROJECT}.appspot.com`;

// [함정] Storage 에뮬레이터는 `getSignedUrl` 을 서명해 주지 못한다 —
//   "Could not load the default credentials" 로 실패한다. Signed URL 은
//   Service Account 개인키로 **로컬에서** 서명되는 값이므로, 이 자리에서
//   합성 RSA 키를 만들어 주면 실제 서명 경로를 그대로 지날 수 있다.
//   실제 자격증명이 아니다 — 매 실행마다 새로 만들고 버린다.
const {privateKey: SYNTH_KEY} = crypto.generateKeyPairSync('rsa', {
  modulusLength: 2048,
  privateKeyEncoding: {type: 'pkcs8', format: 'pem'},
  publicKeyEncoding: {type: 'spki', format: 'pem'},
});

if (!admin.apps.length) {
  admin.initializeApp({
    projectId: PROJECT,
    storageBucket: BUCKET,
    credential: admin.credential.cert({
      projectId: PROJECT,
      clientEmail: `synthetic@${PROJECT}.iam.gserviceaccount.com`,
      privateKey: SYNTH_KEY,
    }),
  });
}
const db = admin.firestore();

// ── production 슬라이스 ────────────────────────────────────────────────
const LIB = fs.readFileSync(
    path.join(__dirname, '..', 'functions', 'lib', 'index.js'), 'utf8');

/** `exports.NAME = ...` 한 덩어리를 떼어 온다. */
function sliceExport(name) {
  const re = new RegExp(`^exports\\.${name} = `, 'm');
  const m = re.exec(LIB);
  if (!m) throw new Error(`export ${name} 없음`);
  const from = m.index;
  const next = /^exports\.[A-Za-z0-9_]+ = /m.exec(LIB.slice(from + m[0].length));
  return LIB.slice(from, next ? from + m[0].length + next.index : LIB.length);
}
/** 최상위 `function NAME(` 한 덩어리. */
function sliceFn(name) {
  const re = new RegExp(`^(?:async )?function ${name}\\(`, 'm');
  const m = re.exec(LIB);
  if (!m) throw new Error(`function ${name} 없음`);
  const from = m.index;
  const rest = LIB.slice(from);
  const end = /^\}/m.exec(rest.slice(1));
  return rest.slice(0, end ? end.index + 2 : rest.length);
}
function sliceConst(name) {
  const re = new RegExp(`^const ${name} = [^\\n]*\\n`, 'm');
  const m = re.exec(LIB);
  if (!m) throw new Error(`const ${name} 없음`);
  return m[0];
}

// 핸들러만 꺼내 직접 호출한다 — onCall 래퍼는 쓰지 않는다.
/**
 * `exports.NAME = onCall(opts, async (request) => {…})` 에서 **핸들러만** 떼어 온다.
 *
 *   [함정] 예전에는 `lastIndexOf(');')` 로 끝을 찾았다. 그런데 export 사이에
 *   최상위 helper 가 끼면 슬라이스가 그 helper 까지 삼키고, 한국어 문자열의
 *   `");` 안에 있는 `);` 가 마지막으로 잡혀 **문법이 깨진 코드**가 나온다(실측).
 *   그래서 본문 `{` 에서 짝 맞는 `}` 까지 **중괄호로** 센다. 문자열·템플릿
 *   리터럴 안의 중괄호는 건너뛴다.
 */
function handlerOf(name) {
  const src = sliceExport(name);
  const i = src.indexOf('async (request)');
  if (i < 0) throw new Error(name + ' 핸들러 시작을 찾지 못함');
  const open = src.indexOf('{', i);
  if (open < 0) throw new Error(name + ' 본문 시작을 찾지 못함');
  let depth = 0;
  let quote = null;
  for (let k = open; k < src.length; k++) {
    const c = src[k];
    if (quote) {
      if (c === '\\') { k++; continue; }
      if (c === quote) quote = null;
      continue;
    }
    if (c === '"' || c === '\'' || c === '`') { quote = c; continue; }
    if (c === '{') depth++;
    else if (c === '}') {
      depth--;
      if (depth === 0) return src.slice(i, k + 1);
    }
  }
  throw new Error(name + ' 본문 끝을 찾지 못함');
}

const HANDLER_SRC = handlerOf('callableGetContractPdfSignedUrl');

class HttpsError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

// [함정] 컴파일된 코드는 `new https_1.HttpsError(...)` 를 쓴다 — bare `HttpsError`
//   를 주면 `https_1` 이 정의되지 않아 ReferenceError 가 나고, 그것이 모든 셀을
//   `code: unknown` 으로 만든다(실측). 네임스페이스 모양 그대로 주입한다.
const deps = {
  db,
  admin,
  https_1: {HttpsError},
  HttpsError,
  Timestamp: admin.firestore.Timestamp,
  console,
};

const build = new Function(
    ...Object.keys(deps),
    sliceConst('SRV_CONTRACT_PDF_PATH_RE') +
    sliceConst('SRV_CONTRACT_PDF_LEGACY_RE') +
    sliceFn('srvIsOwnedContractPdfPath') +
    sliceFn('srvContractPdfPathFromLegacyUrl') +
    sliceConst('SRV_SIG_PATH_RE') +
    sliceConst('SRV_SIG_LEGACY_RE') +
    sliceFn('srvIsOwnedContractSigPath') +
    // [SIG-CUTOVER] 캐시 판 — 주입하지 않으면 서명 핸들러가 ReferenceError 를
    //   내고, 그것이 모든 서명 셀을 `code: unknown` 으로 만든다.
    sliceConst('SRV_SIG_ATTEMPT_RE') +
    sliceFn('srvContractSigVersion') +
    sliceFn('assertBizAdmin') +
    sliceFn('srvAssertContractViewAccess') +
    `return {pdf: (${HANDLER_SRC}), sig: (${handlerOf('callableGetContractSignatureUrl')})};`);
const {pdf: handler, sig: sigHandler} = build(...Object.values(deps));

// ── 합성 원장 ─────────────────────────────────────────────────────────
const SYNTH_PDF = Buffer.from(
    '%PDF-1.4\n1 0 obj<</Type/Catalog>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n',
    'latin1');

let pass = 0;
const fails = [];
function check(name, actual, expected) {
  if (JSON.stringify(actual) === JSON.stringify(expected)) {
    pass++;
    console.log(`  PASS  ${name}`);
  } else {
    fails.push(name);
    console.log(`  FAIL  ${name}`);
    console.log(`        기대 ${JSON.stringify(expected)}`);
    console.log(`        실제 ${JSON.stringify(actual)}`);
  }
}

/// 핸들러를 부르고 결과를 {ok, code} 로 정규화한다. URL 은 **보관하지 않는다**.
async function call(uid, data) {
  try {
    const r = await handler({auth: uid ? {uid} : null, data});
    return {
      ok: true,
      hasUrl: typeof r.signedUrl === 'string' && r.signedUrl.length > 0,
      ttl: r.expiresInSeconds,
      // 토큰 파라미터가 섞여 있지 않은지만 본다 — 값은 버린다.
      hasToken: /[?&]token=/.test(r.signedUrl || ''),
      // 서명 URL 의 만료 **시각**이 지금부터 몇 초 뒤인지.
      //   서명 방식에 따라 파라미터 이름이 다르다:
      //   V2 = `Expires`(절대 epoch 초), V4 = `X-Goog-Expires`(상대 초).
      //   에뮬레이터는 V2 를 낸다 — 둘 다 받아 "남은 수명"으로 환산한다.
      ttlFromUrl: (() => {
        const u = r.signedUrl || '';
        const v4 = /[?&]X-Goog-Expires=(\d+)/.exec(u);
        if (v4) return Number(v4[1]);
        const v2 = /[?&]Expires=(\d+)/.exec(u);
        if (!v2) return null;
        return Number(v2[1]) - Math.floor(Date.now() / 1000);
      })(),
    };
  } catch (e) {
    return {ok: false, code: e.code ?? 'unknown'};
  }
}

(async () => {
  const bucket = admin.storage().bucket();

  // 사업장 A: owner=ownerA, adminIds=[adminA], subAdmins: subOk(계약권한), subNo(없음)
  await db.collection('businesses').doc('bizA').set({
    ownerId: 'ownerA', adminIds: ['adminA'],
  });
  await db.collection('businesses').doc('bizA').collection('members')
      .doc('subOk').set({permissions: {canManageContract: true}});
  await db.collection('businesses').doc('bizA').collection('members')
      .doc('subNo').set({permissions: {canManageContract: false}});
  // 사업장 B — 무관한 관리자
  await db.collection('businesses').doc('bizB').set({
    ownerId: 'ownerB', adminIds: [],
  });

  await db.collection('users').doc('worker1').set({role: 'USER'});
  await db.collection('users').doc('worker2').set({role: 'USER'});
  await db.collection('users').doc('ownerA').set({role: 'BUSINESS_ADMIN'});
  await db.collection('users').doc('adminA').set({role: 'BUSINESS_ADMIN'});
  await db.collection('users').doc('ownerB').set({role: 'BUSINESS_ADMIN'});
  await db.collection('users').doc('subOk')
      .set({role: 'USER', subAdminBusinessIds: ['bizA']});
  await db.collection('users').doc('subNo')
      .set({role: 'USER', subAdminBusinessIds: ['bizA']});
  await db.collection('users').doc('superA').set({role: 'SUPER_ADMIN'});

  // 신규 계약 — pdfStoragePath 방식
  const c1 = 'contractNew1';
  const p1 = `contracts/${c1}/attempts/${crypto.randomBytes(16).toString('hex')}/contract.pdf`;
  await bucket.file(p1).save(SYNTH_PDF,
      {contentType: 'application/pdf', resumable: false});
  await db.collection('employment_contracts').doc(c1).set({
    workerId: 'worker1', businessId: 'bizA', status: 'completed',
    pdfStoragePath: p1, pdfHash: 'synthetic-hash',
  });

  console.log('\n[1] 권한별 발급 결과');
  check('1-a 계약 당사자 근로자 → 허용',
      (await call('worker1', {contractId: c1})).ok, true);
  check('1-b 사업장 owner → 허용',
      (await call('ownerA', {contractId: c1})).ok, true);
  check('1-c adminIds 관리자 → 허용',
      (await call('adminA', {contractId: c1})).ok, true);
  check('1-d canManageContract SubAdmin → 허용',
      (await call('subOk', {contractId: c1})).ok, true);
  check('1-e 계약권한 없는 SubAdmin → 거부',
      await call('subNo', {contractId: c1}),
      {ok: false, code: 'permission-denied'});
  check('1-f 무관한 사업장 관리자 → 거부',
      await call('ownerB', {contractId: c1}),
      {ok: false, code: 'permission-denied'});
  check('1-g 다른 근로자 → 거부',
      await call('worker2', {contractId: c1}),
      {ok: false, code: 'permission-denied'});
  check('1-h 비로그인 → 거부',
      await call(null, {contractId: c1}),
      {ok: false, code: 'unauthenticated'});
  check('1-i SUPER_ADMIN → 허용',
      (await call('superA', {contractId: c1})).ok, true);

  console.log('\n[2] 발급된 링크의 성질');
  const issued = await call('worker1', {contractId: c1});
  check('2-a URL 이 나온다', issued.hasUrl, true);
  check('2-b 수명이 15분으로 응답에 실린다', issued.ttl, 900);
  check('2-c 영구 다운로드 토큰이 섞이지 않는다', issued.hasToken, false);
  // URL 자체에 박힌 만료가 15분쯤이어야 한다 — 응답의 숫자만 믿지 않는다.
  check('2-d URL 에 박힌 만료가 15분 이내다',
      issued.ttlFromUrl !== null && issued.ttlFromUrl > 840 &&
        issued.ttlFromUrl <= 900, true);

  console.log('\n[3] 권한을 잃은 뒤 재발급');
  // SubAdmin 의 계약 권한을 회수한다 — 과거에 링크를 받았든 말든 새 발급은 막혀야 한다.
  await db.collection('businesses').doc('bizA').collection('members')
      .doc('subOk').set({permissions: {canManageContract: false}});
  check('3-a 권한 회수 후 재발급 → 거부',
      await call('subOk', {contractId: c1}),
      {ok: false, code: 'permission-denied'});
  // 사업장 소속 자체가 끊긴 경우
  await db.collection('users').doc('subOk')
      .set({role: 'USER', subAdminBusinessIds: []});
  check('3-b 소속 해제 후 재발급 → 거부',
      await call('subOk', {contractId: c1}),
      {ok: false, code: 'permission-denied'});

  console.log('\n[4] 경로 주입·소유 불일치');
  // 다른 계약의 경로를 Firestore 에 심어 둔 계약 — 서명 직전 검사가 막아야 한다.
  const c2 = 'contractNew2';
  await db.collection('employment_contracts').doc(c2).set({
    workerId: 'worker1', businessId: 'bizA', status: 'completed',
    pdfStoragePath: p1, // ← c1 의 경로
  });
  check('4-a 다른 계약 경로가 심겨 있으면 거부',
      await call('worker1', {contractId: c2}),
      {ok: false, code: 'failed-precondition'});

  const c3 = 'contractNew3';
  await db.collection('employment_contracts').doc(c3).set({
    workerId: 'worker1', businessId: 'bizA', status: 'completed',
    pdfStoragePath: `contracts/${c3}/../../etc/passwd`,
  });
  check('4-b 상위 경로 탈출 시도 거부',
      await call('worker1', {contractId: c3}),
      {ok: false, code: 'failed-precondition'});

  console.log('\n[5] 레거시 계약 호환');
  const c4 = 'contractLegacy1';
  const p4 = `contracts/${c4}/contract.pdf`;   // attempt 도입 전 평면 경로
  await bucket.file(p4).save(SYNTH_PDF, {
    contentType: 'application/pdf',
    metadata: {metadata: {firebaseStorageDownloadTokens:
      crypto.randomBytes(16).toString('hex')}},
    resumable: false,
  });
  const [md] = await bucket.file(p4).getMetadata();
  const legacyToken = (md.metadata || {}).firebaseStorageDownloadTokens;
  await db.collection('employment_contracts').doc(c4).set({
    workerId: 'worker1', businessId: 'bizA', status: 'completed',
    pdfUrl: `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/` +
      `${encodeURIComponent(p4)}?alt=media&token=${legacyToken}`,
  });
  const legacy = await call('worker1', {contractId: c4});
  check('5-a 레거시 URL 에서 경로를 역산해 발급한다', legacy.ok, true);
  check('5-b 발급된 링크는 Signed URL 이다 (토큰 URL 아님)', legacy.hasToken, false);
  check('5-c 레거시도 당사자 아닌 사람은 거부',
      await call('worker2', {contractId: c4}),
      {ok: false, code: 'permission-denied'});

  console.log('\n[6] 없음·오류 구별');
  const c5 = 'contractNoPdf';
  await db.collection('employment_contracts').doc(c5).set({
    workerId: 'worker1', businessId: 'bizA', status: 'pending_worker',
  });
  check('6-a PDF 미생성 → failed-precondition',
      await call('worker1', {contractId: c5}),
      {ok: false, code: 'failed-precondition'});

  const c6 = 'contractMissingFile';
  await db.collection('employment_contracts').doc(c6).set({
    workerId: 'worker1', businessId: 'bizA', status: 'completed',
    pdfStoragePath: `contracts/${c6}/attempts/${'a'.repeat(32)}/contract.pdf`,
  });
  check('6-b 파일 없음 → not-found (권한 없음과 구별)',
      await call('worker1', {contractId: c6}),
      {ok: false, code: 'not-found'});

  check('6-c 없는 계약 → not-found',
      await call('worker1', {contractId: 'nope'}),
      {ok: false, code: 'not-found'});
  check('6-d contractId 누락 → invalid-argument',
      await call('worker1', {}),
      {ok: false, code: 'invalid-argument'});

  console.log('\n[7] 사업장 없는 계약 — 당사자만');
  const c7 = 'contractNoBiz';
  const p7 = `contracts/${c7}/attempts/${crypto.randomBytes(16).toString('hex')}/contract.pdf`;
  await bucket.file(p7).save(SYNTH_PDF,
      {contentType: 'application/pdf', resumable: false});
  await db.collection('employment_contracts').doc(c7).set({
    workerId: 'worker1', status: 'completed', pdfStoragePath: p7,
  });
  check('7-a 당사자는 사업장 없이도 허용',
      (await call('worker1', {contractId: c7})).ok, true);
  check('7-b 사업장을 모르면 당사자 외 전원 거부',
      await call('ownerA', {contractId: c7}),
      {ok: false, code: 'not-found'});

  // ══════════════════════════════════════════════════════════════════
  // [8] 서명 PNG Signed URL — PDF 와 같은 인가여야 한다 (REMEDIATION.3 §3)
  // ══════════════════════════════════════════════════════════════════
  console.log('\n[8] 서명 PNG Signed URL');

  /** 서명 핸들러 호출 — URL 은 보관하지 않는다. */
  async function callSig(uid, data) {
    try {
      const r = await sigHandler({auth: uid ? {uid} : null, data});
      return {
        ok: true,
        hasUrl: typeof r.signedUrl === 'string' && r.signedUrl.length > 0,
        ttl: r.expiresInSeconds,
        hasToken: /[?&]token=/.test(r.signedUrl || ''),
        // [SIG-CUTOVER] 클라이언트 캐시 키의 근거 — 값 자체를 본다(URL 은 버린다).
        version: r.signatureVersion,
      };
    } catch (e) {
      return {ok: false, code: e.code ?? 'unknown'};
    }
  }

  const cs = 'contractWithSigs';
  const sigPrefix = `contracts/${cs}/attempts/${crypto.randomBytes(16).toString('hex')}`;
  const empPath = `${sigPrefix}/signature_employer.png`;
  const wrkPath = `${sigPrefix}/signature_worker.png`;
  const SYNTH_PNG = Buffer.from('\x89PNG\r\n\x1a\n', 'latin1');
  await bucket.file(empPath).save(SYNTH_PNG,
      {contentType: 'image/png', resumable: false});
  await bucket.file(wrkPath).save(SYNTH_PNG,
      {contentType: 'image/png', resumable: false});
  await db.collection('employment_contracts').doc(cs).set({
    workerId: 'worker1', businessId: 'bizA', status: 'completed',
    employerSignatureStoragePath: empPath,
    workerSignatureStoragePath: wrkPath,
  });

  check('8-a 당사자 근로자 — 사업주 서명 허용',
      (await callSig('worker1', {contractId: cs, role: 'employer'})).ok, true);
  check('8-b 당사자 근로자 — 자기 서명 허용',
      (await callSig('worker1', {contractId: cs, role: 'worker'})).ok, true);
  check('8-c 사업장 owner 허용',
      (await callSig('ownerA', {contractId: cs, role: 'worker'})).ok, true);
  // subOk 는 [3] 에서 권한이 회수됐다 — 지금은 거부돼야 한다.
  check('8-d 권한 회수된 SubAdmin 거부',
      await callSig('subOk', {contractId: cs, role: 'worker'}),
      {ok: false, code: 'permission-denied'});
  check('8-e 무관한 사업장 관리자 거부',
      await callSig('ownerB', {contractId: cs, role: 'employer'}),
      {ok: false, code: 'permission-denied'});
  check('8-f 다른 근로자 거부',
      await callSig('worker2', {contractId: cs, role: 'worker'}),
      {ok: false, code: 'permission-denied'});
  check('8-g 비로그인 거부',
      await callSig(null, {contractId: cs, role: 'worker'}),
      {ok: false, code: 'unauthenticated'});
  check('8-h role 이 틀리면 거부',
      await callSig('worker1', {contractId: cs, role: 'boss'}),
      {ok: false, code: 'invalid-argument'});

  const sigIssued = await callSig('worker1', {contractId: cs, role: 'worker'});
  check('8-i 수명이 15분이다', sigIssued.ttl, 900);
  check('8-j 영구 토큰이 섞이지 않는다', sigIssued.hasToken, false);

  // 역할 경로가 섞이면 거부 — worker 요청에 employer 경로가 심긴 계약.
  const csBad = 'contractSigRoleMix';
  await db.collection('employment_contracts').doc(csBad).set({
    workerId: 'worker1', businessId: 'bizA', status: 'completed',
    workerSignatureStoragePath: empPath, // ← employer 경로
  });
  check('8-k 역할이 다른 경로는 거부',
      await callSig('worker1', {contractId: csBad, role: 'worker'}),
      {ok: false, code: 'failed-precondition'});

  // 레거시 토큰 URL 만 있는 계약도 경로 역산으로 열린다.
  const csLegacy = 'contractSigLegacy';
  const legacyEmp = `contracts/${csLegacy}/signature_employer.png`;
  await bucket.file(legacyEmp).save(SYNTH_PNG, {
    contentType: 'image/png',
    metadata: {metadata: {firebaseStorageDownloadTokens:
      crypto.randomBytes(16).toString('hex')}},
    resumable: false,
  });
  const [lmd] = await bucket.file(legacyEmp).getMetadata();
  await db.collection('employment_contracts').doc(csLegacy).set({
    workerId: 'worker1', businessId: 'bizA', status: 'completed',
    employerSignatureUrl: `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/` +
      `${encodeURIComponent(legacyEmp)}?alt=media&token=` +
      `${(lmd.metadata || {}).firebaseStorageDownloadTokens}`,
  });
  check('8-l 레거시 서명 URL 에서 경로를 역산해 발급',
      (await callSig('worker1', {contractId: csLegacy, role: 'employer'})).ok,
      true);
  check('8-m 서명이 없으면 failed-precondition',
      await callSig('worker1', {contractId: csLegacy, role: 'worker'}),
      {ok: false, code: 'failed-precondition'});

  // ══════════════════════════════════════════════════════════════════
  // [9] PDF 와 서명이 **같은 인가**를 쓴다 — 한쪽만 열리지 않는다
  // ══════════════════════════════════════════════════════════════════
  console.log('\n[9] PDF ↔ 서명 인가 일치');
  const pdfPathForCs = `${sigPrefix}/contract.pdf`;
  await bucket.file(pdfPathForCs).save(SYNTH_PDF,
      {contentType: 'application/pdf', resumable: false});
  await db.collection('employment_contracts').doc(cs).update(
      {pdfStoragePath: pdfPathForCs});
  for (const uid of ['worker1', 'ownerA', 'subNo', 'ownerB', 'worker2']) {
    const p = await call(uid, {contractId: cs});
    const s = await callSig(uid, {contractId: cs, role: 'worker'});
    check(`9-${uid} PDF 와 서명의 허용 여부가 같다`,
        {pdf: p.ok, sig: s.ok}, {pdf: p.ok, sig: p.ok});
  }

  // ══════════════════════════════════════════════════════════════════
  // [10] 계약 **진행 상태**가 서명 열람을 막지 않는다 (SIG-CUTOVER §3)
  // ══════════════════════════════════════════════════════════════════
  //
  //   가장 중요한 상태는 `pending_worker` 다: 사업주가 서명했고 근로자는 아직
  //   안 한 때다. 이때 근로자는 **사업주 서명을 봐야** 서명할지 결정할 수 있다.
  //   그래서 인가는 계약 상태를 보지 않고 **당사자·사업장 관계**만 본다.
  //
  //   반대 방향도 센다: 상태가 무엇이든 무관한 사용자는 열 수 없다.
  console.log('\n[10] 계약 상태별 서명 접근');

  const STATES = [
    'pending_employer', 'pending_worker', 'active',
    'completed', 'voided', 'expired',
  ];
  for (const st of STATES) {
    const id = `cs_${st}`;
    const pfx = `contracts/${id}/attempts/${crypto.randomBytes(16).toString('hex')}`;
    const ep = `${pfx}/signature_employer.png`;
    await bucket.file(ep).save(SYNTH_PNG,
        {contentType: 'image/png', resumable: false});
    await db.collection('employment_contracts').doc(id).set({
      workerId: 'worker1', businessId: 'bizA', status: st,
      employerSignatureStoragePath: ep,
    });
    // 당사자 근로자는 **모든 상태에서** 사업주 서명을 볼 수 있다.
    check(`10-${st} 당사자 근로자 — 허용`,
        (await callSig('worker1', {contractId: id, role: 'employer'})).ok, true);
    // 무관한 근로자는 **어느 상태에서도** 못 본다.
    //   당사자가 아니면 사업장 관계를 묻고, 거기서 막힌다 —
    //   `not-found` 는 계약이 사업장을 모를 때(7절)의 코드다.
    check(`10-${st} 무관 근로자 — 거부`,
        await callSig('worker2', {contractId: id, role: 'employer'}),
        {ok: false, code: 'permission-denied'});
  }

  // ══════════════════════════════════════════════════════════════════
  // [11] 관계가 끊기면 **그 다음 발급이** 막힌다
  // ══════════════════════════════════════════════════════════════════
  //
  //   영구 토큰 URL 의 핵심 결함이 이것이었다 — 한 번 받은 링크는 권한을 잃은
  //   뒤에도 계속 열렸다. 이제는 열 때마다 묻기 때문에 관계가 끊기면 끊긴다.
  console.log('\n[11] 관계 상실 후 재발급');

  // ① 사업장 관리자였다가 adminIds 에서 빠진 사람
  check('11-a 관리자였을 때는 허용',
      (await callSig('adminA', {contractId: cs, role: 'worker'})).ok, true);
  await db.collection('businesses').doc('bizA').update({adminIds: []});
  check('11-b adminIds 에서 빠진 뒤 거부',
      await callSig('adminA', {contractId: cs, role: 'worker'}),
      {ok: false, code: 'permission-denied'});
  await db.collection('businesses').doc('bizA').update({adminIds: ['adminA']});

  // ② 계약 관리 권한을 잃은 SubAdmin
  //   [3] 절이 subOk 의 **권한(3-a)과 소속(3-b)을 둘 다** 거뒀고 복구하지
  //   않았다. 이 절은 "있다 → 없다" 전이를 보는 곳이므로 전제를 다시 세운다.
  await db.collection('users').doc('subOk')
      .set({role: 'USER', subAdminBusinessIds: ['bizA']});
  await db.collection('businesses').doc('bizA').collection('members')
      .doc('subOk').set({permissions: {canManageContract: true}});
  check('11-c canManageContract 있을 때는 허용',
      (await callSig('subOk', {contractId: cs, role: 'worker'})).ok, true);
  await db.collection('businesses').doc('bizA').collection('members')
      .doc('subOk').set({permissions: {canManageContract: false}});
  check('11-d 권한을 잃은 뒤 거부',
      await callSig('subOk', {contractId: cs, role: 'worker'}),
      {ok: false, code: 'permission-denied'});
  await db.collection('businesses').doc('bizA').collection('members')
      .doc('subOk').set({permissions: {canManageContract: true}});

  // ③ 계약의 당사자가 교체된 경우 — 옛 근로자는 못 본다
  await db.collection('employment_contracts').doc(cs)
      .update({workerId: 'worker2'});
  check('11-e 당사자에서 빠진 근로자 거부',
      await callSig('worker1', {contractId: cs, role: 'worker'}),
      {ok: false, code: 'permission-denied'});
  await db.collection('employment_contracts').doc(cs)
      .update({workerId: 'worker1'});

  // ══════════════════════════════════════════════════════════════════
  // [12] 캐시 판 — 재서명을 구별한다 (SIG-CUTOVER §5)
  // ══════════════════════════════════════════════════════════════════
  //
  //   `_newContractAttemptPrefix` 가 요청마다 무작위 경로를 쓰므로, 재서명하면
  //   파일이 새 경로에 저장된다. 클라이언트가 `계약 + 역할`만으로 캐시 키를
  //   만들면 옛 이미지가 계속 보인다. 그래서 서버가 판을 함께 돌려준다.
  console.log('\n[12] 서명 캐시 판');

  const v1 = await callSig('worker1', {contractId: cs, role: 'employer'});
  check('12-a 판은 경로의 attempt 와 같다',
      v1.version, sigPrefix.split('/').pop());
  check('12-b 같은 파일을 다시 받아도 판은 그대로다',
      (await callSig('worker1', {contractId: cs, role: 'employer'})).version,
      v1.version);

  // 재서명 — 새 attempt 경로에 저장하고 필드를 갱신한다(원본은 그대로 둔다).
  const pfx2 = `contracts/${cs}/attempts/${crypto.randomBytes(16).toString('hex')}`;
  const ep2 = `${pfx2}/signature_employer.png`;
  await bucket.file(ep2).save(SYNTH_PNG,
      {contentType: 'image/png', resumable: false});
  await db.collection('employment_contracts').doc(cs)
      .update({employerSignatureStoragePath: ep2});
  const v2 = await callSig('worker1', {contractId: cs, role: 'employer'});
  check('12-c 재서명하면 판이 달라진다', v2.version !== v1.version, true);
  check('12-d 새 판은 새 경로의 attempt 다',
      v2.version, pfx2.split('/').pop());
  // 되돌린다 — 뒤 셀이 원래 경로를 본다.
  await db.collection('employment_contracts').doc(cs)
      .update({employerSignatureStoragePath: empPath});

  check('12-e 레거시 경로의 판은 legacy 다',
      (await callSig('worker1', {contractId: csLegacy, role: 'employer'}))
          .version,
      'legacy');

  // ══════════════════════════════════════════════════════════════════
  // [13] 단계 C 시뮬레이션 — 영구 URL 이 **아예 없는** 계약
  // ══════════════════════════════════════════════════════════════════
  //
  //   단계 C 의 신규 계약은 Firestore 에 서명 URL 도 PDF URL 도 없다. 경로만
  //   있다. 그 상태에서 사업주 서명 확인 → 근로자 서명 → PDF 열람이 이어지는지
  //   본다. 이것이 이 Phase 의 종료 기준이다.
  console.log('\n[13] 단계 C — 토큰 없는 신규 계약');

  const cFree = 'contract_token_free';
  const fPfx = `contracts/${cFree}/attempts/${crypto.randomBytes(16).toString('hex')}`;
  const fEmp = `${fPfx}/signature_employer.png`;
  const fWrk = `${fPfx}/signature_worker.png`;
  const fPdf = `${fPfx}/contract.pdf`;
  // 토큰 메타데이터를 **심지 않는다** — 단계 C writer 의 결과물이다.
  for (const [p, b, ct] of [
    [fEmp, SYNTH_PNG, 'image/png'],
    [fWrk, SYNTH_PNG, 'image/png'],
    [fPdf, SYNTH_PDF, 'application/pdf'],
  ]) {
    await bucket.file(p).save(b, {contentType: ct, resumable: false});
  }
  await db.collection('employment_contracts').doc(cFree).set({
    workerId: 'worker1', businessId: 'bizA', status: 'pending_worker',
    employerSignatureStoragePath: fEmp,
    workerSignatureStoragePath: fWrk,
    pdfStoragePath: fPdf,
    // pdfUrl·employerSignatureUrl·workerSignatureUrl 없음
  });

  // ① 근로자가 서명하기 전에 사업주 서명을 확인한다 (pending_worker)
  const fe = await callSig('worker1', {contractId: cFree, role: 'employer'});
  check('13-a 사업주 서명 확인 — 발급됨', {ok: fe.ok, hasUrl: fe.hasUrl},
      {ok: true, hasUrl: true});
  check('13-b 그 링크에 영구 토큰 파라미터가 없다', fe.hasToken, false);
  check('13-c 수명은 15분이다', fe.ttl, 900);
  check('13-d 판이 있다 — 캐시 키를 만들 수 있다',
      typeof fe.version === 'string' && fe.version.length > 0, true);

  // ② 근로자 서명도 같은 경로로 열린다
  check('13-e 근로자 서명 — 발급됨',
      (await callSig('worker1', {contractId: cFree, role: 'worker'})).ok, true);

  // ③ 완료 후 PDF 열람 — 관리자와 당사자 모두
  await db.collection('employment_contracts').doc(cFree)
      .update({status: 'completed'});
  const fp = await call('worker1', {contractId: cFree});
  check('13-f 근로자 PDF 열람 — 발급됨', {ok: fp.ok, hasToken: fp.hasToken},
      {ok: true, hasToken: false});
  check('13-g 관리자 PDF 열람 — 발급됨',
      (await call('ownerA', {contractId: cFree})).ok, true);
  check('13-h 무관한 사용자는 PDF 도 서명도 못 본다',
      {
        pdf: (await call('worker2', {contractId: cFree})).ok,
        sig: (await callSig('worker2', {contractId: cFree, role: 'employer'})).ok,
      },
      {pdf: false, sig: false});

  console.log('\n' + '─'.repeat(44));
  console.log(`총 ${pass + fails.length}건 · 실패 ${fails.length}건`);
  if (fails.length) process.exit(1);
})().catch((e) => {
  console.log('오류: ' + (e && e.stack ? e.stack : e));
  process.exit(1);
});
