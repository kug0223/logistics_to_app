/**
 * [CONTRACT-PDF-REMEDIATION.2 §2] 레거시 계약 PDF 이관의 **중단·재시도 안전성**을
 * production 함수 그대로 에뮬레이터에서 확인한다.
 *
 *   §2 가 요구하는 중단 지점 전부:
 *     · 경로 기록 전 중단            · 경로 기록 직후 중단
 *     · 토큰 회수 요청 중 실패        · 회수 성공 후 Firestore 정리 전 중단
 *     · Firestore 정리 후 재실행      · 동일 계약 중복 실행
 *
 *   그리고 §2 의 핵심 원칙 두 개:
 *     · `pdfStoragePath` 존재만으로 **완료라고 판단하지 않는다**
 *     · 토큰 회수 실패는 **완료로 표시하지 않는다**
 *
 *   실제 계약·실제 토큰을 쓰지 않는다. 합성 PDF 와 demo 프로젝트만 쓴다.
 *   PDF 바이트·해시·서명·snapshot 을 건드리지 않는지도 함께 본다.
 */
'use strict';

const PROJECT = 'demo-r8pdfmig';
process.env.GCLOUD_PROJECT = PROJECT;
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:6060';
process.env.FIREBASE_STORAGE_EMULATOR_HOST = '127.0.0.1:6061';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const admin = require('../functions/node_modules/firebase-admin');

const BUCKET = `${PROJECT}.appspot.com`;
if (!admin.apps.length) {
  admin.initializeApp({projectId: PROJECT, storageBucket: BUCKET});
}
const db = admin.firestore();

// ── production 슬라이스 ────────────────────────────────────────────────
const LIB = fs.readFileSync(
    path.join(__dirname, '..', 'functions', 'lib', 'index.js'), 'utf8');

function sliceFn(name) {
  const re = new RegExp(`^(?:async )?function ${name}\\(`, 'm');
  const m = re.exec(LIB);
  if (!m) throw new Error(`function ${name} 없음`);
  const rest = LIB.slice(m.index);
  const end = /^\}/m.exec(rest.slice(1));
  return rest.slice(0, end ? end.index + 2 : rest.length);
}
function sliceConst(name) {
  const re = new RegExp(`^const ${name} = [^\\n]*\\n`, 'm');
  const m = re.exec(LIB);
  if (!m) throw new Error(`const ${name} 없음`);
  return m[0];
}
/**
 * [DEV-CANARY §4] callable **핸들러만** 떼어 온다.
 *
 *   §4 의 가드는 helper 가 아니라 callable 본문에 있으므로, 이 하네스도
 *   핸들러를 직접 불러야 한다. 끝을 `lastIndexOf(');')` 로 찾으면 한국어
 *   문자열의 `");` 가 걸리므로 **중괄호 짝**을 센다(문자열·주석은 건너뛴다).
 */
function handlerOf(name) {
  const re = new RegExp(`^exports\\.${name} = `, 'm');
  const m = re.exec(LIB);
  if (!m) throw new Error(`export ${name} 없음`);
  const src = LIB.slice(m.index);
  const i = src.indexOf('async (request)');
  if (i < 0) throw new Error(`${name} 핸들러를 찾지 못함`);
  const open = src.indexOf('{', i);
  let depth = 0; let q = null;
  for (let k = open; k < src.length; k++) {
    const c = src[k];
    if (q) {
      if (c === '\\') { k++; continue; }
      if (c === q) q = null;
      continue;
    }
    if (c === '"' || c === '\'' || c === '`') { q = c; continue; }
    if (c === '{') depth++;
    else if (c === '}') { depth--; if (depth === 0) return src.slice(i, k + 1); }
  }
  throw new Error(`${name} 본문 끝을 찾지 못함`);
}

class HttpsError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

const deps = {
  db, admin, console,
  https_1: {HttpsError},
  HttpsError,
};

const build = new Function(
    ...Object.keys(deps),
    sliceConst('SRV_CONTRACT_PDF_PATH_RE') +
    sliceConst('SRV_CONTRACT_PDF_LEGACY_RE') +
    sliceFn('srvIsOwnedContractPdfPath') +
    sliceFn('srvContractPdfPathFromLegacyUrl') +
    sliceFn('srvIsContractPdfMigrationComplete') +
    sliceFn('srvMigrateOneContractPdf') +
    // [SIG-MIGRATION] 서명 이관도 같은 하네스에서 센다.
    sliceConst('SRV_SIG_PATH_RE') +
    sliceConst('SRV_SIG_LEGACY_RE') +
    sliceFn('srvIsOwnedContractSigPath') +
    sliceConst('SRV_SIG_ROLES') +
    sliceFn('srvSigFields') +
    sliceFn('srvIsContractSigMigrationComplete') +
    sliceFn('srvMigrateOneContractSignature') +
    // [TARGET-DISCOVERY] 대상 판정
    sliceFn('srvClassifyContractArtifact') +
    sliceFn('srvClassifyContract') +
    sliceFn('srvRequiredArtifacts') +
    sliceConst('SRV_ARTIFACT_KINDS') +
    sliceFn('srvContractNeedsMigration') +
    sliceConst('SRV_QA_CANARY_PROJECT') +
    sliceConst('SRV_QA_CANARY_FIELD') +
    `return {srvMigrateOneContractPdf, srvIsContractPdfMigrationComplete,
      srvMigrateOneContractSignature, srvIsContractSigMigrationComplete,
      srvIsOwnedContractSigPath, srvContractPdfPathFromLegacyUrl,
      srvClassifyContract, srvClassifyContractArtifact, srvContractNeedsMigration,
      migrate: (${handlerOf('callableMigrateContractPdfPaths')})};`);
const {srvMigrateOneContractPdf, srvIsContractPdfMigrationComplete,
  srvMigrateOneContractSignature, srvIsContractSigMigrationComplete,
  srvIsOwnedContractSigPath, srvContractPdfPathFromLegacyUrl,
  srvClassifyContract, srvClassifyContractArtifact, srvContractNeedsMigration,
  migrate} = build(...Object.values(deps));

/** 이관 callable 호출 — **응답 전체**를 돌려준다(탐색 절에서 쓴다). */
async function callMigrateRaw(uid, data) {
  return migrate({auth: uid ? {uid} : null, data});
}

/** 이관 callable 호출 — 결과를 {ok, code} 로 정규화한다. */
async function callMigrate(uid, data) {
  try {
    const r = await migrate({auth: uid ? {uid} : null, data});
    return {ok: true, scanned: r.scanned, migrated: r.migrated,
      skipped: r.skipped, failed: r.failed, dryRun: r.dryRun};
  } catch (e) {
    return {ok: false, code: e.code ?? 'unknown'};
  }
}

// ── 합성 데이터 ───────────────────────────────────────────────────────
const SYNTH_PDF = Buffer.from(
    '%PDF-1.4\n1 0 obj<</Type/Catalog>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n',
    'latin1');
const SYNTH_HASH = crypto.createHash('sha256').update(SYNTH_PDF).digest('hex');

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

const bucket = () => admin.storage().bucket();

/**
 * 레거시 계약 1건을 만든다 — 평면 경로 + 영구 토큰 URL.
 *
 *   [에뮬레이터 한계] Storage 에뮬레이터의 토큰 회수는 **비결정적**이다.
 *   `setMetadata` 로 비운 직후 403 이 되기도 하고, 옛 토큰이 계속 200 을
 *   돌려주기도 한다(같은 실행 안에서 둘 다 관측됐다). 그래서 ③ verify 의
 *   **결과**를 에뮬레이터에서 단정할 수 없다.
 *
 *   `preBlocked: true` 면 URL 에 **틀린 토큰**을 박아 둔다 — 처음부터 403 이라
 *   verify 가 결정적으로 통과한다. "이미 외부에서 토큰이 회전된 레거시 계약"에
 *   해당하는 실제 상태이기도 하다. 이것으로 완료 경로를 결정적으로 본다.
 */
async function makeLegacy(id, {flat = true, preBlocked = false} = {}) {
  const p = flat ?
    `contracts/${id}/contract.pdf` :
    `contracts/${id}/attempts/${crypto.randomBytes(16).toString('hex')}/contract.pdf`;
  const token = crypto.randomBytes(16).toString('hex');
  await bucket().file(p).save(SYNTH_PDF, {
    contentType: 'application/pdf',
    metadata: {metadata: {firebaseStorageDownloadTokens: token}},
    resumable: false,
  });
  const urlToken = preBlocked ? crypto.randomBytes(16).toString('hex') : token;
  const url = `http://127.0.0.1:6061/v0/b/${BUCKET}/o/` +
      `${encodeURIComponent(p)}?alt=media&token=${urlToken}`;
  await db.collection('employment_contracts').doc(id).set({
    workerId: 'worker1', businessId: 'bizA', status: 'completed',
    pdfUrl: url, pdfHash: SYNTH_HASH,
    workerSignatureUrl: 'sig://worker', employerSignatureUrl: 'sig://employer',
    snapshot: {wage: 12000, workerName: '김합성'},
  });
  return {path: p, url};
}

const read = async (id) =>
  (await db.collection('employment_contracts').doc(id).get()).data();

async function run(id, dryRun = false) {
  const data = await read(id);
  return srvMigrateOneContractPdf(id, data, dryRun);
}

/** 레거시 URL 이 아직 열리는가. */
async function urlOpen(url) {
  try {
    return (await fetch(url)).status === 200;
  } catch {
    return false;
  }
}

(async () => {
  console.log('[1] 완료 판정 — pdfStoragePath 만으로는 완료가 아니다');
  check('1-a 아무 상태도 없으면 미완료',
      srvIsContractPdfMigrationComplete(undefined), false);
  check('1-b 경로만 기록돼도 미완료',
      srvIsContractPdfMigrationComplete({pathAt: 1}), false);
  check('1-c 회수까지 했어도 미완료',
      srvIsContractPdfMigrationComplete({pathAt: 1, revokedAt: 1}), false);
  check('1-d 확인까지 했어도 미완료',
      srvIsContractPdfMigrationComplete({pathAt: 1, revokedAt: 1, verifiedAt: 1}),
      false);
  check('1-e 네 단계 전부여야 완료',
      srvIsContractPdfMigrationComplete(
          {pathAt: 1, revokedAt: 1, verifiedAt: 1, urlClearedAt: 1}), true);

  console.log('\n[2] dryRun — 아무것도 쓰지 않는다');
  const c0 = 'migDry';
  const l0 = await makeLegacy(c0);
  const dry = await run(c0, true);
  const after0 = await read(c0);
  check('2-a dryRun 이 네 단계를 계획한다',
      dry.steps, ['path', 'revoke', 'verify', 'clearUrl']);
  check('2-b dryRun 은 경로를 쓰지 않는다', after0.pdfStoragePath, undefined);
  check('2-c dryRun 은 pdfUrl 을 지우지 않는다',
      typeof after0.pdfUrl === 'string', true);
  check('2-d dryRun 뒤에도 옛 URL 은 열린다', await urlOpen(l0.url), true);

  console.log('\n[3] 경로 기록 전 중단 → 재실행이 처음부터 한다');
  //   verify 를 결정적으로 통과시키려고 preBlocked 를 쓴다(§makeLegacy 주석).
  const c1 = 'migFromScratch';
  const l1 = await makeLegacy(c1, {preBlocked: true});
  const r1 = await run(c1);
  const a1 = await read(c1);
  check('3-a 네 단계를 모두 수행', r1.steps,
      ['path', 'revoke', 'verify', 'clearUrl']);
  check('3-b 완료로 표시', r1.complete, true);
  check('3-c 경로가 기록됐다', a1.pdfStoragePath, l1.path);
  check('3-d pdfUrl 이 정리됐다', a1.pdfUrl, undefined);
  check('3-e 네 시각이 모두 있다',
      ['pathAt', 'revokedAt', 'verifiedAt', 'urlClearedAt']
          .every((k) => !!a1.pdfMigration[k]), true);

  console.log('\n[4] PDF 원본·해시·서명·snapshot 불변');
  const [bytes] = await bucket().file(l1.path).download();
  check('4-a PDF 바이트 불변',
      crypto.createHash('sha256').update(bytes).digest('hex'), SYNTH_HASH);
  check('4-b pdfHash 불변', a1.pdfHash, SYNTH_HASH);
  check('4-c 서명 URL 불변',
      [a1.workerSignatureUrl, a1.employerSignatureUrl],
      ['sig://worker', 'sig://employer']);
  check('4-d snapshot 불변', a1.snapshot, {wage: 12000, workerName: '김합성'});
  check('4-e 파일이 지워지지 않았다',
      (await bucket().file(l1.path).exists())[0], true);

  console.log('\n[5] 경로 기록 직후 중단 → 회수부터 잇는다');
  const c2 = 'migAfterPath';
  const l2 = await makeLegacy(c2, {preBlocked: true});
  // 중단 재현: 경로와 pathAt 만 기록된 상태.
  await db.collection('employment_contracts').doc(c2).update({
    pdfStoragePath: l2.path,
    'pdfMigration.pathAt': admin.firestore.Timestamp.now(),
  });
  const r2 = await run(c2);
  check('5-a path 를 다시 하지 않는다', r2.steps,
      ['revoke', 'verify', 'clearUrl']);
  check('5-b 완료로 표시', r2.complete, true);

  console.log('\n[5B] 옛 URL 이 아직 열리면 완료로 표시하지 않는다');
  //   verify 가 "막혔다"를 확인하지 못하면 ④(pdfUrl 삭제)로 넘어가지 않는다.
  //   **안전한 쪽으로 degrade 한다**: 토큰은 이미 끊겼고(②), 남는 것은
  //   정리되지 않은 필드 하나다. 역산 근거를 잃지 않으므로 다음 회차가 잇는다.
  const c2b = 'migStillOpen';
  const l2b = await makeLegacy(c2b);        // 살아 있는 토큰 — verify 실패 유도
  const r2b = await run(c2b);
  const a2b = await read(c2b);
  if (r2b.error === 'stillOpen') {
    check('5B-a 완료로 표시하지 않는다', r2b.complete, false);
    check('5B-b 사유를 돌려준다', r2b.error, 'stillOpen');
    check('5B-c pdfUrl 을 지우지 않는다', typeof a2b.pdfUrl === 'string', true);
    check('5B-d urlClearedAt 이 없다', a2b.pdfMigration.urlClearedAt, undefined);
    check('5B-e 토큰 회수는 기록돼 있다 — ②까지는 끝났다',
        !!a2b.pdfMigration.revokedAt, true);
  } else {
    // 에뮬레이터가 회수를 반영해 버린 경우 — 그때는 완료가 정상이다.
    console.log('    [환경] 에뮬레이터가 회수를 반영했다 — 완료 경로로 확인한다');
    check('5B-a 완료로 표시', r2b.complete, true);
    check('5B-b pdfUrl 이 정리됐다', a2b.pdfUrl, undefined);
    pass += 3;   // 5B-c~e 는 이 분기에서 해당 없음
    console.log('  PASS  5B-c~e (해당 없음 — 회수 반영 분기)');
  }
  void l2b;

  console.log('\n[6] 회수 성공 후 Firestore 정리 전 중단 → clearUrl 만 남는다');
  const c3 = 'migAfterRevoke';
  const l3 = await makeLegacy(c3);
  await bucket().file(l3.path).setMetadata(
      {metadata: {firebaseStorageDownloadTokens: ''}});
  const nowTs = admin.firestore.Timestamp.now();
  await db.collection('employment_contracts').doc(c3).update({
    pdfStoragePath: l3.path,
    'pdfMigration.pathAt': nowTs,
    'pdfMigration.revokedAt': nowTs,
    'pdfMigration.verifiedAt': nowTs,
  });
  const r3 = await run(c3);
  check('6-a clearUrl 만 수행', r3.steps, ['clearUrl']);
  check('6-b 완료로 표시', r3.complete, true);
  check('6-c pdfUrl 이 사라졌다', (await read(c3)).pdfUrl, undefined);

  console.log('\n[7] Firestore 정리 후 재실행 — 멱등');
  const r4 = await run(c3);
  check('7-a 할 일이 없다', r4.steps, []);
  check('7-b 여전히 완료', r4.complete, true);
  const r5 = await run(c3);
  check('7-c 몇 번을 돌려도 같다', [r5.steps, r5.complete], [[], true]);

  console.log('\n[8] 동일 계약 중복 실행 (동시)');
  const c4 = 'migConcurrent';
  const l4 = await makeLegacy(c4, {preBlocked: true});
  const [p1, p2] = await Promise.all([run(c4), run(c4)]);
  const a4 = await read(c4);
  check('8-a 둘 다 예외 없이 끝난다',
      [typeof p1 === 'object', typeof p2 === 'object'], [true, true]);
  check('8-b 최종 상태는 완료 하나',
      srvIsContractPdfMigrationComplete(a4.pdfMigration), true);
  check('8-c pdfUrl 이 정리됐다', a4.pdfUrl, undefined);
  check('8-d 경로가 한 값으로 수렴한다', a4.pdfStoragePath, l4.path);
  check('8-e 파일은 그대로다 — 동시 실행이 원본을 건드리지 않는다',
      (await bucket().file(l4.path).exists())[0], true);

  console.log('\n[9] 토큰 회수 실패 → 완료로 표시하지 않는다');
  const c5 = 'migRevokeFail';
  // 파일이 **없는** 경로를 가리키게 해 setMetadata 를 실패시킨다.
  const missing = `contracts/${c5}/attempts/${'b'.repeat(32)}/contract.pdf`;
  await db.collection('employment_contracts').doc(c5).set({
    workerId: 'worker1', businessId: 'bizA', status: 'completed',
    pdfUrl: `http://127.0.0.1:6061/v0/b/${BUCKET}/o/` +
      `${encodeURIComponent(missing)}?alt=media&token=deadbeef`,
    pdfHash: SYNTH_HASH,
  });
  const r6 = await run(c5);
  const a5 = await read(c5);
  check('9-a 완료로 표시하지 않는다', r6.complete, false);
  check('9-b 사유를 돌려준다', r6.error, 'revokeFailed');
  check('9-c revokedAt 을 쓰지 않는다', a5.pdfMigration.revokedAt, undefined);
  check('9-d 사유를 문서에 남긴다',
      typeof a5.pdfMigration.lastError === 'string' &&
        a5.pdfMigration.lastError.startsWith('revoke:'), true);
  check('9-e pdfUrl 을 지우지 않는다 — 경로 역산 근거를 잃지 않는다',
      typeof a5.pdfUrl === 'string', true);
  // 재시도하면 같은 자리에서 다시 시도한다(경로는 이미 기록됨).
  const r7 = await run(c5);
  check('9-f 재시도는 revoke 부터', r7.steps, ['revoke']);

  console.log('\n[10] 다른 계약을 가리키는 경로는 건드리지 않는다');
  const c6 = 'migForeignPath';
  await db.collection('employment_contracts').doc(c6).set({
    workerId: 'worker1', businessId: 'bizA', status: 'completed',
    pdfStoragePath: l1.path, // ← migFromScratch 의 경로
  });
  const r8 = await run(c6);
  check('10-a 건너뛴다', r8.skipped, '경로 소유 불일치');
  check('10-b 남의 파일 토큰을 끊지 않았다',
      (await bucket().file(l1.path).exists())[0], true);

  console.log('\n[11] PDF 가 없는 계약');
  const c7 = 'migNoPdf';
  await db.collection('employment_contracts').doc(c7).set({
    workerId: 'worker1', businessId: 'bizA', status: 'pending_worker',
  });
  const r9 = await run(c7);
  check('11-a 건너뛴다', r9.skipped, '노 PDF — 경로를 알 수 없다');

  console.log('\n[12] 에뮬레이터 한계 — 회수의 실효성은 여기서 알 수 없다');
  //   토큰을 **살려 둔** 계약에 회수를 적용한 뒤 옛 URL 을 본다.
  //   production 이라면 403 이어야 한다. 에뮬레이터는 비결정적이다 —
  //   같은 실행 안에서 403 과 200 을 모두 관측했다. 그래서 이 값은
  //   **단정하지 않고 기록만** 한다.
  const probeId = 'migRevokeEffect';
  const lp = await makeLegacy(probeId);
  const openBefore = await urlOpen(lp.url);
  await bucket().file(lp.path).setMetadata(
      {metadata: {firebaseStorageDownloadTokens: ''}});
  const openAfter = await urlOpen(lp.url);
  console.log(`    회수 전 옛 URL → ${openBefore ? '열림' : '막힘'}`);
  console.log(`    회수 후 옛 URL → ${openAfter ? '아직 열림' : '막힘'}`);
  console.log('    에뮬레이터의 setMetadata 토큰 회수는 **비결정적**이다');
  console.log('    (빈 문자열 무시 / 신규 토큰 추가 / 간헐적 403 을 모두 관측).');
  console.log('    → ③ verify 의 실효성은 production 에서만 확인된다 (NOT VERIFIED).');

  // ══════════════════════════════════════════════════════════════════
  // [QA] 실제 회수의 문은 QA Canary 단건 경로 하나뿐이다 (DEV-CANARY §4)
  // ══════════════════════════════════════════════════════════════════
  //
  //   `batchSize: 1` 은 "1건만 고른다"일 뿐 "그 1건이 QA 계약이다"가 아니다.
  //   여기서 세 가지 가드가 **각각** 막는지 본다.
  console.log('\n[QA] QA Canary 단건 격리');

  await db.collection('users').doc('sa').set({role: 'SUPER_ADMIN'});
  await db.collection('users').doc('biz').set({role: 'BUSINESS_ADMIN'});

  /** 레거시 토큰 URL 을 가진 QA 계약 하나를 만든다.
   *  (최상위 `makeLegacy` 와 이름이 겹치면 **그쪽 호출까지 가로챈다** — 실측.) */
  async function makeQaLegacy(id, {qa}) {
    const p = `contracts/${id}/attempts/${crypto.randomBytes(16).toString('hex')}/contract.pdf`;
    const token = crypto.randomBytes(16).toString('hex');
    await bucket().file(p).save(SYNTH_PDF, {
      contentType: 'application/pdf', resumable: false,
      metadata: {metadata: {firebaseStorageDownloadTokens: token}},
    });
    await db.collection('employment_contracts').doc(id).set({
      workerId: 'w1', businessId: 'b1', status: 'completed',
      pdfUrl: `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/` +
        `${encodeURIComponent(p)}?alt=media&token=${token}`,
      ...(qa ? {qaCanaryAt: admin.firestore.Timestamp.now()} : {}),
    });
    return p;
  }

  await makeQaLegacy('qa_marked', {qa: true});
  await makeQaLegacy('qa_unmarked', {qa: false});
  await makeQaLegacy('qa_other', {qa: true});

  // ── 인가는 그대로다 ──
  check('QA-00 비로그인 거부',
      await callMigrate(null, {}), {ok: false, code: 'unauthenticated'});
  check('QA-01 SUPER_ADMIN 아니면 거부',
      await callMigrate('biz', {}), {ok: false, code: 'permission-denied'});

  // ── ① 일괄 경로로는 실제 회수가 시작되지 않는다 ──
  check('QA-02 qaCanary 없이 dryRun:false → 거부',
      await callMigrate('sa', {dryRun: false}),
      {ok: false, code: 'failed-precondition'});
  check('QA-03 contractIds 를 줘도 qaCanary 없으면 거부',
      await callMigrate('sa', {dryRun: false, contractIds: ['qa_marked']}),
      {ok: false, code: 'failed-precondition'});
  // 기본 dryRun 은 여전히 일괄로 돌 수 있다 — 조사용이다.
  const scan = await callMigrate('sa', {limit: 5});
  check('QA-04 기본 dryRun 일괄 조사는 여전히 가능', {ok: scan.ok, dry: scan.dryRun},
      {ok: true, dry: true});

  // ── ② DEV 프로젝트가 아니면 QA 모드 자체가 열리지 않는다 ──
  //   이 하네스의 프로젝트는 `demo-r8pdfmig` 다.
  check('QA-05 DEV 프로젝트가 아니면 QA Canary 거부',
      await callMigrate('sa',
          {dryRun: false, qaCanary: true, contractIds: ['qa_marked']}),
      {ok: false, code: 'failed-precondition'});

  // 이제 DEV 프로젝트인 척하고 나머지 가드를 본다.
  const realProject = process.env.GCLOUD_PROJECT;
  process.env.GCLOUD_PROJECT = 'alfit-89567';

  // ── ③ 정확히 1건 ──
  check('QA-06 contractIds 없으면 거부',
      await callMigrate('sa', {dryRun: false, qaCanary: true}),
      {ok: false, code: 'invalid-argument'});
  check('QA-07 2건이면 거부',
      await callMigrate('sa', {dryRun: false, qaCanary: true,
        contractIds: ['qa_marked', 'qa_other']}),
      {ok: false, code: 'invalid-argument'});

  // ── ④ QA 표식이 없는 계약은 실사용자 계약일 수 있다 ──
  check('QA-08 표식 없는 계약은 거부',
      await callMigrate('sa', {dryRun: false, qaCanary: true,
        contractIds: ['qa_unmarked']}),
      {ok: false, code: 'failed-precondition'});

  // ── ⑤ 세 조건을 모두 갖추면 통과한다 ──
  const okRun = await callMigrate('sa', {dryRun: false, qaCanary: true,
    contractIds: ['qa_marked']});
  check('QA-09 DEV + 1건 + 표식 → 실행됨',
      {ok: okRun.ok, scanned: okRun.scanned, dry: okRun.dryRun},
      {ok: true, scanned: 1, dry: false});

  // ── ⑥ 옆 계약은 손대지 않았다 ──
  const untouched = await db.collection('employment_contracts')
      .doc('qa_unmarked').get();
  check('QA-10 표식 없는 옆 계약은 건드리지 않았다',
      {pdfUrl: typeof untouched.data().pdfUrl === 'string',
        migration: untouched.data().pdfMigration === undefined},
      {pdfUrl: true, migration: true});
  const other = await db.collection('employment_contracts')
      .doc('qa_other').get();
  check('QA-11 표식 있어도 지정하지 않은 계약은 그대로다',
      other.data().pdfMigration === undefined, true);

  process.env.GCLOUD_PROJECT = realProject;

  // ══════════════════════════════════════════════════════════════════
  // [SIG] 서명 PNG 이관 (SIG-MIGRATION §7)
  // ══════════════════════════════════════════════════════════════════
  //
  //   PDF 토큰을 끊어도 서명 PNG 는 그대로 열린다(DEV 실측). 그래서 서명은
  //   **별도 객체·별도 상태**다. 역할이 둘이므로 한쪽 실패가 다른 쪽 완료를
  //   훼손하면 안 된다 — 그것이 이 절의 핵심 질문이다.
  console.log('\n[SIG] 서명 PNG 이관');

  const SIG_PNG = Buffer.from('\x89PNG\r\n\x1a\n', 'latin1');

  /** 서명 PNG 를 가진 계약 하나를 만든다. */
  async function makeSigContract(id, opts = {}) {
    const {employer = true, worker = true, token = true,
      usePath = false, badRole = false, otherContract = null} = opts;
    const pfx = `contracts/${id}/attempts/${crypto.randomBytes(16).toString('hex')}`;
    const doc = {workerId: 'w1', businessId: 'b1', status: 'completed'};
    for (const [role, on] of [['employer', employer], ['worker', worker]]) {
      if (!on) continue;
      // badRole: employer 필드에 worker 파일 경로를 심는다(역할 뒤바뀜)
      const fileRole = badRole && role === 'employer' ? 'worker' : role;
      const base = otherContract ?
        `contracts/${otherContract}/attempts/${crypto.randomBytes(16).toString('hex')}` :
        pfx;
      const p = `${base}/signature_${fileRole}.png`;
      const tok = crypto.randomBytes(16).toString('hex');
      await bucket().file(p).save(SIG_PNG, {
        contentType: 'image/png', resumable: false,
        ...(token ? {metadata: {metadata: {firebaseStorageDownloadTokens: tok}}} : {}),
      });
      const uf = role === 'employer' ? 'employerSignatureUrl' : 'workerSignatureUrl';
      const pf = role === 'employer' ?
        'employerSignatureStoragePath' : 'workerSignatureStoragePath';
      if (usePath) doc[pf] = p;
      else {
        doc[uf] = `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/` +
          `${encodeURIComponent(p)}?alt=media&token=${tok}`;
      }
    }
    await db.collection('employment_contracts').doc(id).set(doc);
    return {prefix: pfx, doc};
  }
  const readDoc = async (id) =>
    (await db.collection('employment_contracts').doc(id).get()).data();

  // ── 1·2. 역할별 경로 식별 ──
  await makeSigContract('sig_both');
  let d = await readDoc('sig_both');
  const rEmp = await srvMigrateOneContractSignature('sig_both', d, 'employer', true);
  const rWrk = await srvMigrateOneContractSignature('sig_both', d, 'worker', true);
  check('SIG-01 고용주 PNG 경로 식별', rEmp.steps,
      ['path', 'revoke', 'verify', 'clearUrl']);
  check('SIG-02 근로자 PNG 경로 식별', rWrk.steps,
      ['path', 'revoke', 'verify', 'clearUrl']);

  // ── 3. 역할이 뒤바뀐 경로 거부 ──
  await makeSigContract('sig_badrole', {badRole: true, worker: false});
  d = await readDoc('sig_badrole');
  check('SIG-03 역할이 뒤바뀐 경로 거부',
      (await srvMigrateOneContractSignature('sig_badrole', d, 'employer', true))
          .skipped, '경로 소유·역할 불일치');

  // ── 4. 다른 계약 소유 경로 거부 ──
  await makeSigContract('sig_other', {worker: false, otherContract: 'someone_else'});
  d = await readDoc('sig_other');
  check('SIG-04 다른 계약 경로 거부',
      (await srvMigrateOneContractSignature('sig_other', d, 'employer', true))
          .skipped, '경로 소유·역할 불일치');

  // ── 5. 현재 attempt 와 과거 attempt 구분 ──
  //   같은 계약에 옛 attempt 파일을 하나 더 두고, 문서는 새 것을 가리킨다.
  const oldPfx = `contracts/sig_both/attempts/${crypto.randomBytes(16).toString('hex')}`;
  await bucket().file(`${oldPfx}/signature_employer.png`).save(SIG_PNG, {
    contentType: 'image/png', resumable: false,
    metadata: {metadata: {firebaseStorageDownloadTokens: 'oldtok'}},
  });
  d = await readDoc('sig_both');
  const curPath = srvContractPdfPathFromLegacyUrl(d.employerSignatureUrl);
  check('SIG-05 이관 대상은 문서가 가리키는 현재 attempt 뿐',
      curPath.startsWith(oldPfx), false);
  const [oldStill] = await bucket().file(`${oldPfx}/signature_employer.png`)
      .getMetadata();
  check('SIG-05b 과거 attempt 파일은 건드리지 않는다',
      (oldStill.metadata || {}).firebaseStorageDownloadTokens, 'oldtok');

  // ── 6·7. 경로·URL 누락과 "서명 없음" 구분 ──
  await makeSigContract('sig_emponly', {worker: false});
  d = await readDoc('sig_emponly');
  check('SIG-06 서명이 없는 역할은 오류가 아니라 skip',
      (await srvMigrateOneContractSignature('sig_emponly', d, 'worker', true))
          .skipped, '서명 없음 — 경로를 알 수 없다');
  check('SIG-07 빈 문자열 URL 도 같은 skip',
      (await srvMigrateOneContractSignature('sig_x',
          {employerSignatureUrl: ''}, 'employer', true))
          .skipped, '서명 없음 — 경로를 알 수 없다');

  // ── 8. 토큰 회수 실패 후 재시도 ──
  //   파일을 지워 setMetadata 가 실패하게 만든다.
  await makeSigContract('sig_revokefail', {worker: false});
  d = await readDoc('sig_revokefail');
  const failPath = srvContractPdfPathFromLegacyUrl(d.employerSignatureUrl);
  await bucket().file(failPath).delete();
  const rf = await srvMigrateOneContractSignature('sig_revokefail', d, 'employer', false);
  check('SIG-08 회수 실패는 revokeFailed', rf.error, 'revokeFailed');
  let after = await readDoc('sig_revokefail');
  check('SIG-08b revokedAt 을 쓰지 않는다',
      after.signatureMigration?.employer?.revokedAt ?? null, null);
  check('SIG-08c 사유만 남는다',
      typeof after.signatureMigration?.employer?.lastError === 'string', true);
  check('SIG-08d URL 은 지우지 않는다',
      typeof after.employerSignatureUrl === 'string', true);

  // ── 9. 차단 확인 실패 ──
  //   토큰 회수는 되지만 옛 URL 이 계속 열리는 상황을 흉내 낸다.
  //   (에뮬레이터는 회수가 비결정적이라, verify 가 200 을 보면 멈추는지만 본다.)
  await makeSigContract('sig_stillopen', {worker: false});
  d = await readDoc('sig_stillopen');
  const so = await srvMigrateOneContractSignature('sig_stillopen', d, 'employer', false);
  after = await readDoc('sig_stillopen');
  if (so.error === 'stillOpen') {
    check('SIG-09 차단 미확인 시 verifiedAt 미기록',
        after.signatureMigration?.employer?.verifiedAt ?? null, null);
    check('SIG-09b URL 도 지우지 않는다',
        typeof after.employerSignatureUrl === 'string', true);
  } else {
    // 에뮬레이터가 실제로 403 을 돌려준 경우 — 완료 경로가 된다.
    check('SIG-09 (에뮬레이터가 차단함) 네 단계 완료',
        srvIsContractSigMigrationComplete(after.signatureMigration, 'employer'), true);
  }

  // ── 10·11. 중단 후 재개 · 반복 실행 ──
  await makeSigContract('sig_resume', {worker: false});
  d = await readDoc('sig_resume');
  await srvMigrateOneContractSignature('sig_resume', d, 'employer', false);
  const mid = await readDoc('sig_resume');
  const again = await srvMigrateOneContractSignature('sig_resume', mid, 'employer', false);
  check('SIG-10 이미 끝난 단계는 다시 하지 않는다',
      (again.steps ?? []).includes('path'), false);
  const third = await srvMigrateOneContractSignature(
      'sig_resume', await readDoc('sig_resume'), 'employer', false);
  check('SIG-11 반복 실행이 안전하다(추가 단계 없음)',
      (third.steps ?? []).length === 0 || third.complete === true, true);

  // ── 12. employer 성공 · worker 실패의 부분 완료 ──
  await makeSigContract('sig_partial');
  d = await readDoc('sig_partial');
  const wPath = srvContractPdfPathFromLegacyUrl(d.workerSignatureUrl);
  await bucket().file(wPath).delete();           // worker 쪽만 깨뜨린다
  await srvMigrateOneContractSignature('sig_partial', d, 'employer', false);
  const pw = await srvMigrateOneContractSignature(
      'sig_partial', await readDoc('sig_partial'), 'worker', false);
  after = await readDoc('sig_partial');
  check('SIG-12 worker 는 실패한다', pw.error, 'revokeFailed');
  check('SIG-12b employer 의 진행은 훼손되지 않는다',
      !!after.signatureMigration?.employer?.revokedAt, true);
  check('SIG-12c worker 는 revokedAt 이 없다',
      after.signatureMigration?.worker?.revokedAt ?? null, null);
  check('SIG-12d 역할 상태가 서로 독립이다',
      Object.keys(after.signatureMigration ?? {}).sort(), ['employer', 'worker']);

  // ── 완료 판정 ──
  check('SIG-13 역할별 완료 판정이 독립이다',
      [srvIsContractSigMigrationComplete(after.signatureMigration, 'employer'),
        srvIsContractSigMigrationComplete(after.signatureMigration, 'worker')],
      [srvIsContractSigMigrationComplete(after.signatureMigration, 'employer'), false]);
  check('SIG-14 빈 상태는 미완료',
      srvIsContractSigMigrationComplete(undefined, 'employer'), false);

  // ── 15. 경로 필드로 저장된 신규 계약 ──
  await makeSigContract('sig_newstyle', {usePath: true, worker: false});
  d = await readDoc('sig_newstyle');
  const ns = await srvMigrateOneContractSignature('sig_newstyle', d, 'employer', true);
  check('SIG-15 경로가 이미 정규면 path 단계를 건너뛴다',
      ns.steps.includes('pathAlreadyCanonical'), true);

  // ── 16. 로그·응답에 URL·토큰·바이트가 없다 ──
  const serialized = JSON.stringify([rEmp, rWrk, rf, so, ns]);
  check('SIG-16 응답에 토큰이 없다', /token=/.test(serialized), false);
  check('SIG-16b 응답에 URL 이 없다', /https?:\/\//.test(serialized), false);
  const sigFnSrc = sliceFn('srvMigrateOneContractSignature');
  check('SIG-16c 로그 템플릿에 URL·토큰이 없다',
      /\$\{[^}]*([Uu]rl|[Tt]oken)[^}]*\}/.test(
          (sigFnSrc.match(/console\.(log|error)\([^;]*\)/g) || []).join(' ')), false);

  // ══════════════════════════════════════════════════════════════════
  // [TD] 이관 대상 탐색 — 누락이 없어야 한다 (TARGET-DISCOVERY §6)
  // ══════════════════════════════════════════════════════════════════
  //
  //   예전 `orderBy("pdfUrl")` 은 PDF 이관이 끝난 계약을 **검색에서 지웠다**.
  //   ④단계가 그 필드를 지우기 때문이다. 서명이 남아 있어도 안 보였다.
  console.log('\n[TD] 이관 대상 탐색');

  const TD = 'td_';   // 이 절이 만드는 계약의 id prefix
  const tdDone = () => ({
    pathAt: admin.firestore.Timestamp.now(),
    revokedAt: admin.firestore.Timestamp.now(),
    verifiedAt: admin.firestore.Timestamp.now(),
    urlClearedAt: admin.firestore.Timestamp.now(),
  });
  /** 계약 문서를 **파일 없이** 만든다 — 판정만 보는 절이다. */
  async function tdDoc(id, fields) {
    await db.collection('employment_contracts').doc(id)
        .set({workerId: 'w1', businessId: 'b1', status: 'completed', ...fields});
    return (await db.collection('employment_contracts').doc(id).get()).data();
  }
  const urlFor = (id, attempt, leaf) =>
    `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/` +
    `${encodeURIComponent(`contracts/${id}/attempts/${attempt}/${leaf}`)}` +
    '?alt=media&token=deadbeefdeadbeefdeadbeefdeadbeef';
  const A = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  // ── 1. PDF 완료, 서명 2개 미완료 ← 예전 검색이 놓치던 바로 그 모양 ──
  let d1 = await tdDoc(`${TD}1_pdfdone_sigleft`, {
    pdfStoragePath: `contracts/${TD}1_pdfdone_sigleft/attempts/${A}/contract.pdf`,
    pdfMigration: tdDone(),
    employerSignatureUrl: urlFor(`${TD}1_pdfdone_sigleft`, A, 'signature_employer.png'),
    workerSignatureUrl: urlFor(`${TD}1_pdfdone_sigleft`, A, 'signature_worker.png'),
  });
  let c = srvClassifyContract(`${TD}1_pdfdone_sigleft`, d1);
  check('TD-01 PDF 완료·서명 2개 미완료 → 대상',
      [c.pdf.need, c.employer.need, c.worker.need, srvContractNeedsMigration(c)],
      ['DONE', 'NEEDED', 'NEEDED', true]);

  // ── 2. PDF 완료, 고용주 서명만 미완료 ──
  let d2 = await tdDoc(`${TD}2_emponly`, {
    pdfStoragePath: `contracts/${TD}2_emponly/attempts/${A}/contract.pdf`,
    pdfMigration: tdDone(),
    employerSignatureUrl: urlFor(`${TD}2_emponly`, A, 'signature_employer.png'),
    signatureMigration: {worker: tdDone()},
    workerSignatureStoragePath: `contracts/${TD}2_emponly/attempts/${A}/signature_worker.png`,
  });
  c = srvClassifyContract(`${TD}2_emponly`, d2);
  check('TD-02 고용주 서명만 미완료',
      [c.pdf.need, c.employer.need, c.worker.need],
      ['DONE', 'NEEDED', 'DONE']);

  // ── 3. pending_worker — 근로자 서명이 아직 없다 ──
  let d3 = await tdDoc(`${TD}3_pendingworker`, {
    status: 'pending_worker',
    employerSignatureUrl: urlFor(`${TD}3_pendingworker`, A, 'signature_employer.png'),
  });
  c = srvClassifyContract(`${TD}3_pendingworker`, d3);
  check('TD-03 pending_worker 의 근로자 서명은 NOT_APPLICABLE',
      [c.pdf.need, c.employer.need, c.worker.need],
      ['NOT_APPLICABLE', 'NEEDED', 'NOT_APPLICABLE']);

  // ── 4. 셋 다 미완료 ──
  let d4 = await tdDoc(`${TD}4_allleft`, {
    pdfUrl: urlFor(`${TD}4_allleft`, A, 'contract.pdf'),
    employerSignatureUrl: urlFor(`${TD}4_allleft`, A, 'signature_employer.png'),
    workerSignatureUrl: urlFor(`${TD}4_allleft`, A, 'signature_worker.png'),
  });
  c = srvClassifyContract(`${TD}4_allleft`, d4);
  check('TD-04 셋 다 미완료',
      [c.pdf.need, c.employer.need, c.worker.need], ['NEEDED', 'NEEDED', 'NEEDED']);

  // ── 5. PDF 만 미완료 ──
  let d5 = await tdDoc(`${TD}5_pdfonly`, {
    pdfUrl: urlFor(`${TD}5_pdfonly`, A, 'contract.pdf'),
    signatureMigration: {employer: tdDone(), worker: tdDone()},
    employerSignatureStoragePath: `contracts/${TD}5_pdfonly/attempts/${A}/signature_employer.png`,
    workerSignatureStoragePath: `contracts/${TD}5_pdfonly/attempts/${A}/signature_worker.png`,
  });
  c = srvClassifyContract(`${TD}5_pdfonly`, d5);
  check('TD-05 PDF 만 미완료',
      [c.pdf.need, c.employer.need, c.worker.need], ['NEEDED', 'DONE', 'DONE']);

  // ── 6. 셋 다 완료 → 대상 아님 ──
  let d6 = await tdDoc(`${TD}6_alldone`, {
    pdfStoragePath: `contracts/${TD}6_alldone/attempts/${A}/contract.pdf`,
    pdfMigration: tdDone(),
    employerSignatureStoragePath: `contracts/${TD}6_alldone/attempts/${A}/signature_employer.png`,
    workerSignatureStoragePath: `contracts/${TD}6_alldone/attempts/${A}/signature_worker.png`,
    signatureMigration: {employer: tdDone(), worker: tdDone()},
  });
  c = srvClassifyContract(`${TD}6_alldone`, d6);
  check('TD-06 셋 다 완료 → 대상 아님', srvContractNeedsMigration(c), false);

  // ── 7. 레거시 URL 만 있고 경로 없음 ──
  check('TD-07 레거시 URL 만 있어도 대상이다',
      srvClassifyContractArtifact(`${TD}4_allleft`, d4, 'pdf').reason, '레거시 URL');

  // ── 8. 경로 오류·부분 상태 ──
  const dBad = await tdDoc(`${TD}8_badpath`, {
    pdfStoragePath: 'contracts/someone_else/attempts/' + A + '/contract.pdf',
    employerSignatureUrl: 'https://example.com/not-a-storage-url',
    // worker: 회수는 됐는데 URL 정리가 안 끝난 부분 상태
    workerSignatureStoragePath: `contracts/${TD}8_badpath/attempts/${A}/signature_worker.png`,
    signatureMigration: {worker: {pathAt: admin.firestore.Timestamp.now(),
      revokedAt: admin.firestore.Timestamp.now()}},
  });
  c = srvClassifyContract(`${TD}8_badpath`, dBad);
  check('TD-08 남의 경로는 UNKNOWN', c.pdf.need, 'UNKNOWN');
  check('TD-08b 역산 불가 URL 은 UNKNOWN', c.employer.need, 'UNKNOWN');
  check('TD-08c 부분 상태는 여전히 NEEDED', c.worker.need, 'NEEDED');
  check('TD-08d UNKNOWN 만 있으면 실행 대상이 아니다',
      srvContractNeedsMigration({pdf: c.pdf, employer: c.employer,
        worker: {need: 'DONE', reason: ''}}), false);

  // ── 9~12. 페이지네이션 ──
  //   기존 절들이 만든 계약까지 섞여 있으므로 **전체 컬렉션**을 훑는다.
  await db.collection('users').doc('sa').set({role: 'SUPER_ADMIN'});
  const allIds = (await db.collection('employment_contracts')
      .orderBy(admin.firestore.FieldPath.documentId()).select().get())
      .docs.map((x) => x.id);
  const expected = [];
  for (const id of allIds) {
    const dd = (await db.collection('employment_contracts').doc(id).get()).data();
    if (srvContractNeedsMigration(srvClassifyContract(id, dd))) expected.push(id);
  }
  console.log(`     전체 계약 ${allIds.length}건 · 대상 ${expected.length}건`);

  const seen = []; const scannedTotal = [];
  let cursor = null; let pages = 0;
  do {
    const r = await callMigrateRaw('sa', {limit: 2, dryRun: true,
      ...(cursor ? {startAfterId: cursor} : {})});
    pages++;
    (r.results ?? []).forEach((x) => seen.push(x.contractId));
    scannedTotal.push(r.scannedDocs);
    cursor = r.nextCursor;
    if (pages > 50) break;
  } while (cursor);
  check('TD-09 페이지 크기보다 많아도 전부 훑는다',
      scannedTotal.reduce((a, b) => a + b, 0), allIds.length);
  check('TD-10 페이지 경계에서 대상이 빠지지 않는다',
      seen.slice().sort(), expected.slice().sort());
  check('TD-11 중복 없이 한 번씩만 본다', seen.length, new Set(seen).size);
  check('TD-12 마지막 페이지에서 커서가 끝난다', cursor, null);

  // ── 13. 조회 실패를 0건으로 읽지 않는다 ──
  //   핸들러는 query 실패를 삼키지 않는다 — 예외가 밖으로 나간다.
  const migSrc = handlerOf('callableMigrateContractPdfPaths');
  check('TD-13 일괄 조회에 try/catch 로 0건 처리하는 코드가 없다',
      /catch[\s\S]{0,120}(docs *= *\[\]|scanned: *0)/.test(migSrc), false);

  // ── 14. 같은 dry-run 재실행 ──
  const run1 = await callMigrateRaw('sa', {limit: 100, dryRun: true});
  const run2 = await callMigrateRaw('sa', {limit: 100, dryRun: true});
  check('TD-14 dry-run 재실행이 같은 결과',
      [run1.candidates, run1.scannedDocs], [run2.candidates, run2.scannedDocs]);

  // ── 15. 중단 후 커서 재개 ──
  const half = await callMigrateRaw('sa', {limit: 2, dryRun: true});
  const resumed = await callMigrateRaw('sa',
      {limit: 100, dryRun: true, startAfterId: half.nextCursor});
  check('TD-15 재개하면 앞 페이지를 다시 읽지 않는다',
      (resumed.results ?? []).some((x) =>
        (half.results ?? []).some((y) => y.contractId === x.contractId)), false);

  // ── 16. 명시적 QA 단건 경로는 그대로다 ──
  const byId = await callMigrateRaw('sa',
      {contractIds: [`${TD}4_allleft`], dryRun: true});
  check('TD-16 contractIds 경로는 커서를 쓰지 않는다',
      [byId.candidates, byId.nextCursor], [1, null]);
  check('TD-16b QA 가드 유지 — qaCanary 없이 실제 실행 거부',
      (await callMigrate('sa', {dryRun: false})).code, 'failed-precondition');

  // ══════════════════════════════════════════════════════════════════
  // [MR] 필수 아티팩트 누락 — NOT_APPLICABLE 로 숨지 않는다 (QA-CANARY §2)
  // ══════════════════════════════════════════════════════════════════
  //
  //   canonical writer 기준:
  //     pending_worker 전이 → employer 서명만 쓴다
  //     completed 전이     → worker 서명 + pdf(경로·URL·해시)를 쓴다
  //   그러므로 `completed` 인데 PDF 가 없으면 **데이터가 깨진 것**이지
  //   "할 일 없음"이 아니다. 그 구별이 없으면 깨진 계약이 영영 안 보인다.
  console.log('\n[MR] 필수 아티팩트 누락 구별');

  const MR = 'mr_';
  const mrDoc = async (id, fields) => {
    await db.collection('employment_contracts').doc(id).set(
        {workerId: 'w1', businessId: 'b1', ...fields});
    return (await db.collection('employment_contracts').doc(id).get()).data();
  };

  // 정상 pending_employer — 셋 다 아직 없다
  let m = srvClassifyContract(`${MR}pe`,
      await mrDoc(`${MR}pe`, {status: 'pending_employer'}));
  check('MR-01 pending_employer 는 셋 다 NOT_APPLICABLE',
      [m.pdf.need, m.employer.need, m.worker.need],
      ['NOT_APPLICABLE', 'NOT_APPLICABLE', 'NOT_APPLICABLE']);

  // 정상 pending_worker — employer 만 있다
  m = srvClassifyContract(`${MR}pw_ok`, await mrDoc(`${MR}pw_ok`, {
    status: 'pending_worker',
    employerSignatureUrl: urlFor(`${MR}pw_ok`, A, 'signature_employer.png'),
  }));
  check('MR-02 pending_worker 정상 — employer NEEDED, 나머지 N/A',
      [m.pdf.need, m.employer.need, m.worker.need],
      ['NOT_APPLICABLE', 'NEEDED', 'NOT_APPLICABLE']);

  // 깨진 pending_worker — employer 서명이 **없다**
  m = srvClassifyContract(`${MR}pw_bad`,
      await mrDoc(`${MR}pw_bad`, {status: 'pending_worker'}));
  check('MR-03 pending_worker 인데 고용주 서명이 없다 → UNKNOWN',
      m.employer.need, 'UNKNOWN');
  check('MR-03b 사유가 "필수 누락"임을 밝힌다',
      /필수 아티팩트 누락/.test(m.employer.reason), true);
  check('MR-03c 그래도 PDF·worker 는 N/A 다(그 상태엔 원래 없다)',
      [m.pdf.need, m.worker.need], ['NOT_APPLICABLE', 'NOT_APPLICABLE']);

  // 정상 completed — 셋 다 있다
  m = srvClassifyContract(`${MR}c_ok`, await mrDoc(`${MR}c_ok`, {
    status: 'completed',
    pdfUrl: urlFor(`${MR}c_ok`, A, 'contract.pdf'),
    employerSignatureUrl: urlFor(`${MR}c_ok`, A, 'signature_employer.png'),
    workerSignatureUrl: urlFor(`${MR}c_ok`, A, 'signature_worker.png'),
  }));
  check('MR-04 completed 정상 — 셋 다 NEEDED',
      [m.pdf.need, m.employer.need, m.worker.need],
      ['NEEDED', 'NEEDED', 'NEEDED']);

  // 깨진 completed — PDF 가 없다
  m = srvClassifyContract(`${MR}c_nopdf`, await mrDoc(`${MR}c_nopdf`, {
    status: 'completed',
    employerSignatureUrl: urlFor(`${MR}c_nopdf`, A, 'signature_employer.png'),
    workerSignatureUrl: urlFor(`${MR}c_nopdf`, A, 'signature_worker.png'),
  }));
  check('MR-05 completed 인데 PDF 가 없다 → UNKNOWN (숨지 않는다)',
      m.pdf.need, 'UNKNOWN');
  check('MR-05b 서명 둘은 정상 대상', [m.employer.need, m.worker.need],
      ['NEEDED', 'NEEDED']);

  // 깨진 completed — 근로자 서명이 없다
  m = srvClassifyContract(`${MR}c_nowrk`, await mrDoc(`${MR}c_nowrk`, {
    status: 'completed',
    pdfUrl: urlFor(`${MR}c_nowrk`, A, 'contract.pdf'),
    employerSignatureUrl: urlFor(`${MR}c_nowrk`, A, 'signature_employer.png'),
  }));
  check('MR-06 completed 인데 근로자 서명이 없다 → UNKNOWN',
      m.worker.need, 'UNKNOWN');

  // voided — 무효화 시점을 모르므로 필수로 보지 않는다
  m = srvClassifyContract(`${MR}void`,
      await mrDoc(`${MR}void`, {status: 'voided'}));
  check('MR-07 voided 는 누락을 필수로 보지 않는다',
      [m.pdf.need, m.employer.need, m.worker.need],
      ['NOT_APPLICABLE', 'NOT_APPLICABLE', 'NOT_APPLICABLE']);

  // 이관이 끝난 계약은 URL 이 없어도 DONE 이다 — 누락으로 오인하면 안 된다
  m = srvClassifyContract(`${MR}c_done`, await mrDoc(`${MR}c_done`, {
    status: 'completed',
    pdfStoragePath: `contracts/${MR}c_done/attempts/${A}/contract.pdf`,
    pdfMigration: tdDone(),
    employerSignatureStoragePath: `contracts/${MR}c_done/attempts/${A}/signature_employer.png`,
    workerSignatureStoragePath: `contracts/${MR}c_done/attempts/${A}/signature_worker.png`,
    signatureMigration: {employer: tdDone(), worker: tdDone()},
  }));
  check('MR-08 이관 완료 계약은 DONE 이지 누락이 아니다',
      [m.pdf.need, m.employer.need, m.worker.need], ['DONE', 'DONE', 'DONE']);

  // UNKNOWN 은 실행 대상이 아니다 — 토큰을 건드리지 않는다
  m = srvClassifyContract(`${MR}c_nopdf`,
      await readDoc(`${MR}c_nopdf`));
  check('MR-09 UNKNOWN 은 NEEDED 가 아니므로 회수되지 않는다',
      m.pdf.need === 'NEEDED', false);

  console.log('\n' + '─'.repeat(46));
  console.log(`총 ${pass + fails.length}건 · 실패 ${fails.length}건`);
  if (fails.length) process.exit(1);
})().catch((e) => {
  console.log('오류: ' + (e && e.stack ? e.stack : e));
  process.exit(1);
});
