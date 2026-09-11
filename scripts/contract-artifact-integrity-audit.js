#!/usr/bin/env node
/**
 * PHASE CONTRACT-CONTENT-3.9 — CONTRACT SIGNATURE/PDF ARTIFACT INTEGRITY AUDIT
 *
 * READ ONLY AUDIT — NO FIRESTORE WRITES / NO STORAGE WRITES / NO STORAGE DELETES
 *
 * 두 가지 별개 문제를 탐지한다 (CONTRACT-CONTENT-3.8 분류):
 *   A. Historical integrity damage
 *      3.4 이전(pre-auth 덮어쓰기+삭제) / 3.5~3.6(동시성 drift) 시기에 발생 가능했던
 *      "Firestore 참조는 있는데 Storage object가 없거나 내용이 다른" 손상.
 *   B. Attempt orphan retention
 *      3.7 이후 contracts/{contractId}/attempts/{attemptId}/ 구조에서
 *      어떤 계약서도 참조하지 않는 민감 artifact 잔존.
 *
 * Usage:
 *   node scripts/contract-artifact-integrity-audit.js --project=dev
 *   node scripts/contract-artifact-integrity-audit.js --project=dev --level=full
 *   node scripts/contract-artifact-integrity-audit.js --project=prod --confirm-prod
 *
 * Options:
 *   --project=dev|prod   필수. 미지정 시 실행 거부.
 *   --level=metadata     (기본) 존재/토큰/generation/size 등 저비용 metadata만 검사
 *   --level=full         metadata + 서명 SHA-256 + PDF SHA-256 (bytes 다운로드 발생)
 *   --confirm-prod       --project=prod 에 필수인 2차 opt-in
 *   --bucket=<name>      Storage 버킷 override (기본: <projectId>.firebasestorage.app)
 *   --limit=<n>          계약서 스캔 상한 (시범 실행용)
 *   --skip-orphans       attempt orphan 열거 생략 (Firestore 측 무결성만)
 *   --concurrency=<n>    Storage 동시 요청 수 (기본 8)
 *   --out=<path>         JSON 리포트 경로 override
 *
 * PROD: --project=prod + --confirm-prod + prod service account at
 *       scripts/alfit-prod-adminsdk.json  또는  GOOGLE_APPLICATION_CREDENTIALS env
 *
 * 이 스크립트에는 --fix / --repair / --delete 옵션이 존재하지 않는다. 순수 audit.
 */

'use strict';

const path   = require('path');
const fs     = require('fs');
const crypto = require('crypto');

// ─── SAFETY BANNER ───────────────────────────────────────────────────────────
const LINE = '='.repeat(68);
console.log(LINE);
console.log('CONTRACT ARTIFACT INTEGRITY AUDIT');
console.log('READ ONLY AUDIT — NO WRITES WILL BE PERFORMED');
console.log('  Firestore : read/query only');
console.log('  Storage   : exists/getMetadata/download/list only');
console.log('  No repair, no cleanup, no delete option exists in this script.');
console.log(LINE);
console.log();

// ─── Args ────────────────────────────────────────────────────────────────────
const cliArgs = {};
for (const a of process.argv.slice(2)) {
  if (a.startsWith('--')) {
    const eq = a.indexOf('=');
    if (eq >= 0) cliArgs[a.slice(2, eq)] = a.slice(eq + 1);
    else          cliArgs[a.slice(2)]     = true;
  }
}

// [GUARD] project 미지정 시 실행 거부 — 잘못된 프로젝트 대상 실행 방지
if (!cliArgs['project']) {
  console.error('--project is required. Use: --project=dev  or  --project=prod');
  console.error('(no default is applied on purpose)');
  process.exit(1);
}
const projectAlias = String(cliArgs['project']).toLowerCase();

const PROJECT_IDS = { dev: 'alfit-89567', prod: 'alfit-prod' };
if (!PROJECT_IDS[projectAlias]) {
  console.error(`Unknown --project="${projectAlias}". Use: dev | prod`);
  process.exit(1);
}
const projectId = PROJECT_IDS[projectAlias];

// [GUARD] PROD 이중 opt-in
if (projectAlias === 'prod' && cliArgs['confirm-prod'] !== true) {
  console.error('PROD target requires an explicit second opt-in: --confirm-prod');
  console.error('Refusing to run against production without it.');
  process.exit(1);
}

const level = String(cliArgs['level'] || 'metadata').toLowerCase();
if (!['metadata', 'full'].includes(level)) {
  console.error(`Unknown --level="${level}". Use: metadata | full`);
  process.exit(1);
}

const concurrency  = Math.max(1, Math.min(32, parseInt(cliArgs['concurrency'], 10) || 8));
const contractLimit = cliArgs['limit'] ? parseInt(cliArgs['limit'], 10) : null;
const skipOrphans   = cliArgs['skip-orphans'] === true;
const bucketName    = cliArgs['bucket'] || `${projectId}.firebasestorage.app`;

// orphan 판정 하한 — CONTRACT-CONTENT-3.8 권장값.
// 근거: onCall(v2) 기본 타임아웃 60초 + 플랫폼 자동 재시도 없음.
//       업로드 후 TX 진행 중인 정상 in-flight attempt를 orphan으로 오판하지 않도록
//       이론적 안전선(수 분)보다 2~3자릿수 여유를 둔다.
const ORPHAN_AGE_HOURS = 24;

console.log(`Project alias : ${projectAlias}`);
console.log(`Project ID    : ${projectId}`);
console.log(`Storage bucket: ${bucketName}`);
console.log(`Scan level    : ${level}${level === 'metadata' ? '  (no bytes downloaded)' : '  (signature + PDF bytes downloaded for SHA-256)'}`);
console.log(`Concurrency   : ${concurrency}`);
console.log(`Orphan age    : >= ${ORPHAN_AGE_HOURS}h unreferenced`);
if (contractLimit) console.log(`Contract limit: ${contractLimit}`);
if (skipOrphans)   console.log('Orphan scan   : SKIPPED (--skip-orphans)');
console.log();

// ─── Admin SDK ───────────────────────────────────────────────────────────────
let admin;
try {
  admin = require(path.join(__dirname, '../functions/node_modules/firebase-admin'));
} catch (_) {
  try { admin = require('firebase-admin'); }
  catch (__) {
    console.error('firebase-admin not found. cd functions && npm install');
    process.exit(1);
  }
}

const SA_PATHS = {
  dev:  path.join(__dirname, 'alfit-89567-firebase-adminsdk-fbsvc-d22e7faef3.json'),
  prod: path.join(__dirname, 'alfit-prod-adminsdk.json'),
};

// [SECURITY] 자격증명 "출처"만 표시하고 경로 전체·키 내용은 출력하지 않는다.
let credential;
if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  credential = admin.credential.applicationDefault();
  console.log('Credentials   : GOOGLE_APPLICATION_CREDENTIALS env');
} else if (fs.existsSync(SA_PATHS[projectAlias])) {
  credential = admin.credential.cert(SA_PATHS[projectAlias]);
  console.log(`Credentials   : service account file (scripts/${path.basename(SA_PATHS[projectAlias])})`);
} else {
  console.error(`Service account not found for "${projectAlias}".`);
  console.error('Set GOOGLE_APPLICATION_CREDENTIALS or place the key under scripts/.');
  process.exit(1);
}
console.log();

admin.initializeApp({ credential, projectId, storageBucket: bucketName });
const db     = admin.firestore();
const bucket = admin.storage().bucket();

// ─── Domain constants ────────────────────────────────────────────────────────

/**
 * Artifact expectation matrix (CONTRACT-CONTENT-3.8).
 * lifecycle 코드 근거:
 *   employer 서명 TX → status='pending_worker' + employerSignatureUrl 동시 기록
 *   worker  서명 TX → status='completed' + workerSignatureUrl + pdfUrl 동시 기록
 *                     (진입 조건으로 employerSignatureUrl 존재를 명시 검증)
 * voided 는 직전 status를 알 수 없어 단일 기대치를 세울 수 없다 → INDETERMINATE.
 */
const EXPECTATION = {
  pending_employer: { employer: 'NOT_EXPECTED', worker: 'NOT_EXPECTED', pdf: 'NOT_EXPECTED' },
  pending_worker:   { employer: 'REQUIRED',     worker: 'NOT_EXPECTED', pdf: 'NOT_EXPECTED' },
  completed:        { employer: 'REQUIRED',     worker: 'REQUIRED',     pdf: 'REQUIRED' },
  voided:           { employer: 'OPTIONAL',     worker: 'OPTIONAL',     pdf: 'OPTIONAL' },
};
const UNKNOWN_EXPECTATION = { employer: 'OPTIONAL', worker: 'OPTIONAL', pdf: 'OPTIONAL' };

const LEGACY_FILENAMES = ['signature_employer.png', 'signature_worker.png', 'contract.pdf'];

/** artifactType → { urlField, hashField } (hash 3종은 server-only forensic field) */
const ARTIFACTS = [
  { type: 'employer', urlField: 'employerSignatureUrl', hashField: 'employerSignatureHash' },
  { type: 'worker',   urlField: 'workerSignatureUrl',   hashField: 'workerSignatureHash' },
  { type: 'pdf',      urlField: 'pdfUrl',               hashField: 'pdfHash' },
];

// ─── Helpers ─────────────────────────────────────────────────────────────────

/** bounded concurrency map — 무제한 Promise.all 금지 (production Storage 보호) */
async function mapWithConcurrency(items, limit, fn) {
  const results = new Array(items.length);
  let next = 0;
  const workers = new Array(Math.min(limit, items.length)).fill(0).map(async () => {
    while (true) {
      const i = next++;
      if (i >= items.length) return;
      results[i] = await fn(items[i], i);
    }
  });
  await Promise.all(workers);
  return results;
}

/**
 * Firebase download URL → { bucket, objectPath, token }
 * 형식: https://firebasestorage.googleapis.com/v0/b/{bucket}/o/{encodedPath}?alt=media&token=...
 * 문자열 split 대신 URL parser 사용. malformed 는 null 반환(예외 전파 금지).
 */
function parseArtifactUrl(rawUrl) {
  if (typeof rawUrl !== 'string' || rawUrl.length === 0) return null;
  let u;
  try { u = new URL(rawUrl); } catch (_) { return null; }
  const m = u.pathname.match(/^\/v0\/b\/([^/]+)\/o\/(.+)$/);
  if (!m) return null;
  let objectPath;
  try { objectPath = decodeURIComponent(m[2]); } catch (_) { return null; }
  if (!objectPath) return null;
  return {
    bucket: m[1],
    objectPath,
    token: u.searchParams.get('token'), // 없을 수 있음 → URL_TOKEN_MISSING
  };
}

/** objectPath → 'LEGACY' | 'ATTEMPT' | 'UNKNOWN' */
function classifyPathFamily(objectPath) {
  const seg = objectPath.split('/');
  if (seg[0] !== 'contracts' || seg.length < 3) return 'UNKNOWN';
  if (seg.length === 3 && LEGACY_FILENAMES.includes(seg[2])) return 'LEGACY';
  if (seg.length === 5 && seg[2] === 'attempts' && LEGACY_FILENAMES.includes(seg[4])) return 'ATTEMPT';
  return 'UNKNOWN';
}

/** objectPath 에서 소유 계약 id 추출 (contracts/{contractId}/...) */
function contractIdFromPath(objectPath) {
  const seg = objectPath.split('/');
  return (seg[0] === 'contracts' && seg.length >= 2) ? seg[1] : null;
}

/**
 * firebaseStorageDownloadTokens 는 단일 문자열이 아니라
 * 쉼표로 구분된 복수 토큰 목록일 수 있다. raw equality 비교 금지.
 */
function tokenState(urlToken, metaTokensRaw) {
  if (metaTokensRaw === undefined || metaTokensRaw === null || metaTokensRaw === '') {
    return 'TOKEN_METADATA_MISSING';
  }
  if (!urlToken) return 'URL_TOKEN_MISSING';
  const valid = String(metaTokensRaw).split(',').map(s => s.trim()).filter(Boolean);
  return valid.includes(urlToken) ? 'TOKEN_OK' : 'TOKEN_MISMATCH';
}

function sha256Hex(buf) {
  return crypto.createHash('sha256').update(buf).digest('hex');
}

/** hash 전체를 로그/리포트에 남기지 않는다 — 앞 8자 접두만 */
function hashPrefix(h) {
  return (typeof h === 'string' && h.length >= 8) ? h.slice(0, 8) : null;
}

function tsToIso(v) {
  if (!v) return null;
  if (typeof v.toDate === 'function') { try { return v.toDate().toISOString(); } catch (_) { return null; } }
  if (v instanceof Date) return v.toISOString();
  if (typeof v === 'string') return v;
  return null;
}

function hoursSince(iso) {
  if (!iso) return null;
  const t = Date.parse(iso);
  if (Number.isNaN(t)) return null;
  return (Date.now() - t) / 36e5;
}

// ─── Aggregate state ─────────────────────────────────────────────────────────
const agg = {
  contractsScanned: 0,
  byStatus: { pending_employer: 0, pending_worker: 0, completed: 0, voided: 0, unknown: 0 },

  requiredUrlMissing: 0,
  invalidArtifactUrl: 0,
  objectMissing: 0,

  hashOk: 0,
  hashNotRecorded: 0,
  signatureHashMismatch: 0,
  pdfHashMismatch: 0,

  tokenOk: 0,
  tokenMismatch: 0,
  tokenMetadataMissing: 0,
  urlTokenMissing: 0,

  legacyArtifacts: 0,
  attemptArtifacts: 0,
  unknownPathArtifacts: 0,

  crossContractArtifactReference: 0,
  crossBucketArtifactReference: 0,

  attemptObjectsScanned: 0,
  unreferencedRecent: 0,
  agedUnreferencedAttempts: 0,
  parentContractMissing: 0,

  scanErrors: 0,
};

/** 개별 레코드 — PII 없음 (§29 허용 필드만) */
const findings = [];
function record(rec) { findings.push(rec); }

// ─── Stage: contract artifact audit ──────────────────────────────────────────

/** 참조된 모든 Storage path 집합 (orphan 판정 기준) */
const referencedArtifactPaths = new Set();
/** Firestore 에 존재하는 contractId 집합 (parentless 판정 기준) */
const knownContractIds = new Set();

async function auditContractArtifact(ctx, artifact) {
  const { contractId, businessId, status, data, createdAtIso, updatedAtIso } = ctx;
  const expectation = (EXPECTATION[status] || UNKNOWN_EXPECTATION)[artifact.type];

  const rawUrl  = data[artifact.urlField];
  const rawHash = data[artifact.hashField];

  const base = {
    contractId, businessId, status,
    artifactType: artifact.type,
    expectation,
    contractCreatedAt: createdAtIso,
    contractUpdatedAt: updatedAtIso,
  };

  // ── URL 부재
  if (!rawUrl) {
    if (expectation === 'REQUIRED') {
      agg.requiredUrlMissing++;
      record({ ...base, pathFamily: null, storagePath: null, signal: 'REQUIRED_URL_MISSING',
               severity: status === 'completed' ? 'CRITICAL' : 'HIGH' });
    }
    return; // NOT_EXPECTED / OPTIONAL 은 정상
  }

  // ── URL 파싱
  const parsed = parseArtifactUrl(rawUrl);
  if (!parsed) {
    agg.invalidArtifactUrl++;
    record({ ...base, pathFamily: null, storagePath: null, signal: 'INVALID_ARTIFACT_URL', severity: 'REVIEW' });
    return;
  }

  const { objectPath, token: urlToken } = parsed;
  const pathFamily = classifyPathFamily(objectPath);
  if (pathFamily === 'LEGACY')       agg.legacyArtifacts++;
  else if (pathFamily === 'ATTEMPT') agg.attemptArtifacts++;
  else                               agg.unknownPathArtifacts++;

  referencedArtifactPaths.add(objectPath);

  const rec = { ...base, pathFamily, storagePath: objectPath };

  // ── 타 버킷 참조
  if (parsed.bucket !== bucketName) {
    agg.crossBucketArtifactReference++;
    record({ ...rec, signal: 'CROSS_BUCKET_ARTIFACT_REFERENCE', severity: 'CRITICAL',
             referencedBucket: parsed.bucket });
    return; // 이 버킷에서 검증 불가
  }

  // ── 타 계약 namespace 참조 (자동 수정 금지 — 집계만)
  const ownerId = contractIdFromPath(objectPath);
  if (ownerId && ownerId !== contractId) {
    agg.crossContractArtifactReference++;
    record({ ...rec, signal: 'CROSS_CONTRACT_ARTIFACT_REFERENCE', severity: 'CRITICAL',
             referencedContractId: ownerId });
    // 계속 진행 — 존재/해시도 함께 본다
  }

  // ── Stage 1: metadata
  const file = bucket.file(objectPath);
  let meta;
  try {
    const [exists] = await file.exists();
    if (!exists) {
      agg.objectMissing++;
      record({ ...rec, signal: 'OBJECT_MISSING',
               severity: expectation === 'REQUIRED'
                 ? (status === 'completed' ? 'CRITICAL' : 'HIGH')
                 : 'REVIEW' });
      return;
    }
    [meta] = await file.getMetadata();
  } catch (e) {
    agg.scanErrors++;
    record({ ...rec, signal: 'SCAN_ERROR', severity: 'REVIEW', errorMessage: e.message });
    return;
  }

  const objectTimeCreated = meta.timeCreated || null;
  const generation        = meta.generation != null ? String(meta.generation) : null;
  const size              = meta.size != null ? Number(meta.size) : null;

  Object.assign(rec, { generation, objectTimeCreated, size });

  // ── token 상태 (hash 와 독립 signal)
  const tState = tokenState(urlToken, meta.metadata && meta.metadata.firebaseStorageDownloadTokens);
  if      (tState === 'TOKEN_OK')               agg.tokenOk++;
  else if (tState === 'TOKEN_MISMATCH')         agg.tokenMismatch++;
  else if (tState === 'TOKEN_METADATA_MISSING') agg.tokenMetadataMissing++;
  else if (tState === 'URL_TOKEN_MISSING')      agg.urlTokenMissing++;

  if (tState !== 'TOKEN_OK') {
    // TOKEN_MISMATCH != OBJECT_CORRUPTED. stale/invalid download reference 후보.
    record({ ...rec, signal: tState, severity: 'REVIEW',
             note: 'STALE_OR_INVALID_DOWNLOAD_REFERENCE_CANDIDATE' });
  }

  // ── hash 3상태 (없음을 mismatch 로 취급 금지)
  if (typeof rawHash !== 'string' || rawHash.length === 0) {
    agg.hashNotRecorded++;
    // UNKNOWN 이지 PASS 가 아니다.
    record({ ...rec, signal: 'HASH_NOT_RECORDED', severity: 'REVIEW' });
    return;
  }

  if (level !== 'full') return; // metadata 단계에서는 bytes 를 읽지 않는다

  // ── Stage 2/3: bytes SHA-256 (hash 가 기록된 경우에만 — 새 baseline 생성 금지)
  let actual;
  try {
    const [buf] = await file.download();
    actual = sha256Hex(buf);
  } catch (e) {
    agg.scanErrors++;
    record({ ...rec, signal: 'SCAN_ERROR', severity: 'REVIEW', errorMessage: e.message });
    return;
  }

  if (actual === rawHash) {
    agg.hashOk++;
    return;
  }
  if (artifact.type === 'pdf') agg.pdfHashMismatch++;
  else                         agg.signatureHashMismatch++;
  record({ ...rec,
           signal: artifact.type === 'pdf' ? 'PDF_HASH_MISMATCH' : 'SIGNATURE_HASH_MISMATCH',
           severity: status === 'completed' ? 'CRITICAL' : 'HIGH',
           expectedHashPrefix: hashPrefix(rawHash),
           actualHashPrefix:   hashPrefix(actual) });
}

async function auditContracts() {
  console.log('1. Scanning employment_contracts …');
  let cursor = null;
  let scanned = 0;

  while (true) {
    let q = db.collection('employment_contracts').orderBy('__name__').limit(300);
    if (cursor) q = q.startAfter(cursor);
    const snap = await q.get();
    if (snap.empty) break;

    const ctxs = [];
    for (const doc of snap.docs) {
      if (contractLimit && scanned >= contractLimit) break;
      scanned++;
      knownContractIds.add(doc.id);

      // [RAW] Flutter 모델을 쓰지 않는다 — hash 3필드는 모델에 없는 server-only field.
      const data = doc.data() || {};
      const rawStatus = typeof data.status === 'string' ? data.status : null;
      const status = rawStatus && EXPECTATION[rawStatus] ? rawStatus : (rawStatus || 'unknown');

      if (agg.byStatus[status] !== undefined) agg.byStatus[status]++;
      else agg.byStatus.unknown++;

      ctxs.push({
        contractId: doc.id,
        businessId: typeof data.businessId === 'string' ? data.businessId : null,
        status,
        data,
        createdAtIso: tsToIso(data.createdAt),
        updatedAtIso: tsToIso(data.updatedAt),
      });
    }
    agg.contractsScanned += ctxs.length;

    // artifact 단위로 펼쳐서 bounded concurrency 적용
    const jobs = [];
    for (const ctx of ctxs) for (const a of ARTIFACTS) jobs.push({ ctx, a });
    await mapWithConcurrency(jobs, concurrency, async ({ ctx, a }) => {
      try { await auditContractArtifact(ctx, a); }
      catch (e) {
        // record-level 격리 — 전체 audit 중단 금지
        agg.scanErrors++;
        record({ contractId: ctx.contractId, businessId: ctx.businessId, status: ctx.status,
                 artifactType: a.type, pathFamily: null, storagePath: null,
                 signal: 'SCAN_ERROR', severity: 'REVIEW', errorMessage: e.message });
      }
    });

    process.stdout.write(`\r   contracts scanned: ${agg.contractsScanned}   `);
    if (contractLimit && scanned >= contractLimit) break;
    if (snap.docs.length < 300) break;
    cursor = snap.docs[snap.docs.length - 1];
  }
  process.stdout.write(`\r   contracts scanned: ${agg.contractsScanned}          \n`);
}

// ─── Stage: attempt orphan enumeration ───────────────────────────────────────

async function auditAttemptOrphans() {
  console.log('2. Enumerating attempt artifacts under contracts/ …');
  let pageToken;
  let page = 0;

  // getFiles(autoPaginate:false) — 버킷 전체를 메모리에 적재하지 않고 페이지 단위 처리
  while (true) {
    const [files, nextQuery] = await bucket.getFiles({
      prefix: 'contracts/',
      autoPaginate: false,
      maxResults: 500,
      pageToken,
    });
    if (!files || files.length === 0) break;

    for (const f of files) {
      const objectPath = f.name;
      if (!objectPath.includes('/attempts/')) continue;
      agg.attemptObjectsScanned++;

      if (referencedArtifactPaths.has(objectPath)) continue; // 정상 참조됨

      const ownerId    = contractIdFromPath(objectPath);
      const created    = (f.metadata && f.metadata.timeCreated) || null;
      const ageHours   = hoursSince(created);
      const pathFamily = classifyPathFamily(objectPath);

      const rec = {
        contractId: ownerId,
        businessId: null, // 미참조 artifact 는 소유 계약 문서가 없을 수 있음
        status: null,
        artifactType: objectPath.split('/').pop(),
        pathFamily,
        storagePath: objectPath,
        generation: f.metadata && f.metadata.generation != null ? String(f.metadata.generation) : null,
        objectTimeCreated: created,
        contractCreatedAt: null,
        contractUpdatedAt: null,
      };

      // 부모 계약 문서 자체가 없는 경우 — 일반 orphan 과 구분
      if (ownerId && !knownContractIds.has(ownerId)) {
        agg.parentContractMissing++;
        record({ ...rec, signal: 'PARENT_CONTRACT_MISSING', severity: 'RETENTION', ageHours });
        continue;
      }

      // [§17] in-flight 정상 attempt 오판 방지 — threshold 이전은 orphan 아님
      if (ageHours === null || ageHours < ORPHAN_AGE_HOURS) {
        agg.unreferencedRecent++;
        record({ ...rec, signal: 'UNREFERENCED_BUT_RECENT', severity: 'INFO', ageHours });
        continue;
      }

      agg.agedUnreferencedAttempts++;
      // 원인(정상 경합 패자 / 크래시 등)은 단정하지 않는다 — 분류만.
      record({ ...rec, signal: 'AGED_UNREFERENCED_ATTEMPT', severity: 'RETENTION', ageHours });
    }

    page++;
    process.stdout.write(`\r   attempt objects scanned: ${agg.attemptObjectsScanned} (page ${page})   `);
    if (!nextQuery || !nextQuery.pageToken) break;
    pageToken = nextQuery.pageToken;
  }
  process.stdout.write(`\r   attempt objects scanned: ${agg.attemptObjectsScanned}          \n`);
}

// ─── Report ──────────────────────────────────────────────────────────────────

function severityCounts() {
  const c = { CRITICAL: 0, HIGH: 0, REVIEW: 0, RETENTION: 0, INFO: 0 };
  for (const f of findings) if (c[f.severity] !== undefined) c[f.severity]++;
  return c;
}

function printSummary(outPath) {
  const sev = severityCounts();

  console.log('\n' + LINE);
  console.log('SUMMARY');
  console.log(LINE);

  console.log('\n1. Contracts');
  console.log(`   scanned           : ${agg.contractsScanned}`);
  console.log(`   pending_employer  : ${agg.byStatus.pending_employer}`);
  console.log(`   pending_worker    : ${agg.byStatus.pending_worker}`);
  console.log(`   completed         : ${agg.byStatus.completed}`);
  console.log(`   voided            : ${agg.byStatus.voided}   (INDETERMINATE expectation)`);
  console.log(`   unknown status    : ${agg.byStatus.unknown}`);

  console.log('\n2. Reference integrity');
  console.log(`   REQUIRED_URL_MISSING            : ${agg.requiredUrlMissing}`);
  console.log(`   INVALID_ARTIFACT_URL            : ${agg.invalidArtifactUrl}`);
  console.log(`   OBJECT_MISSING                  : ${agg.objectMissing}`);
  console.log(`   CROSS_CONTRACT_ARTIFACT_REF     : ${agg.crossContractArtifactReference}`);
  console.log(`   CROSS_BUCKET_ARTIFACT_REF       : ${agg.crossBucketArtifactReference}`);

  console.log('\n3. Hash integrity');
  if (level !== 'full') {
    console.log('   (level=metadata — SHA-256 not evaluated; re-run with --level=full)');
  }
  console.log(`   HASH_OK                         : ${agg.hashOk}`);
  console.log(`   SIGNATURE_HASH_MISMATCH         : ${agg.signatureHashMismatch}`);
  console.log(`   PDF_HASH_MISMATCH               : ${agg.pdfHashMismatch}`);
  console.log(`   HASH_NOT_RECORDED               : ${agg.hashNotRecorded}   ← UNKNOWN, not PASS`);

  console.log('\n4. Download reference (independent of hash)');
  console.log(`   TOKEN_OK                        : ${agg.tokenOk}`);
  console.log(`   TOKEN_MISMATCH                  : ${agg.tokenMismatch}   ← stale/invalid ref candidate`);
  console.log(`   TOKEN_METADATA_MISSING          : ${agg.tokenMetadataMissing}`);
  console.log(`   URL_TOKEN_MISSING               : ${agg.urlTokenMissing}`);

  console.log('\n5. Path family (code generation tracing)');
  console.log(`   LEGACY deterministic            : ${agg.legacyArtifacts}`);
  console.log(`   ATTEMPT (post-3.7)              : ${agg.attemptArtifacts}`);
  console.log(`   UNKNOWN shape                   : ${agg.unknownPathArtifacts}`);

  console.log('\n6. Attempt retention');
  if (skipOrphans) {
    console.log('   (skipped — --skip-orphans)');
  } else {
    console.log(`   attempt objects scanned         : ${agg.attemptObjectsScanned}`);
    console.log(`   UNREFERENCED_BUT_RECENT (<${ORPHAN_AGE_HOURS}h) : ${agg.unreferencedRecent}   ← not orphan candidates`);
    console.log(`   AGED_UNREFERENCED_ATTEMPT       : ${agg.agedUnreferencedAttempts}`);
    console.log(`   PARENT_CONTRACT_MISSING         : ${agg.parentContractMissing}`);
  }

  console.log('\n7. Severity buckets');
  console.log(`   CRITICAL  : ${sev.CRITICAL}   (completed artifact missing / hash mismatch / cross-reference)`);
  console.log(`   HIGH      : ${sev.HIGH}       (pending_worker employer signature problems)`);
  console.log(`   REVIEW    : ${sev.REVIEW}     (token mismatch / hash not recorded / anomalies)`);
  console.log(`   RETENTION : ${sev.RETENTION}  (aged unreferenced attempts / parentless)`);
  console.log(`   INFO      : ${sev.INFO}`);

  console.log('\n8. Scan errors');
  console.log(`   SCAN_ERROR (isolated, scan continued) : ${agg.scanErrors}`);

  console.log('\n9. NO WRITE CONFIRMATION');
  console.log('   ✅ Firestore : no .set() / .update() / .create() / .delete() / .commit()');
  console.log('   ✅ Firestore : no runTransaction()');
  console.log('   ✅ Storage   : no .save() / .delete() / .setMetadata() / .copy() / .move()');
  console.log('   ✅ Storage   : exists() / getMetadata() / download() / getFiles() only');
  console.log('   ✅ No --fix / --repair / --delete option exists');

  console.log('\n10. Next step');
  console.log('    Repair and orphan cleanup are deliberately NOT implemented here.');
  console.log('    Review the JSON report, then design a separate remediation phase.');
  if (sev.CRITICAL > 0) {
    console.log('    ⚠️  CRITICAL findings present — signature artifacts of completed contracts');
    console.log('        are generally NOT recoverable (source bytes exist only in Storage).');
  }

  console.log('\n' + LINE);
  console.log('AUDIT COMPLETE — NO DATA WAS MODIFIED');
  console.log(`JSON report: ${outPath}`);
  console.log(LINE);
}

// ─── Main ────────────────────────────────────────────────────────────────────

async function main() {
  const startedAt = new Date();

  await auditContracts();
  if (!skipOrphans) await auditAttemptOrphans();

  const stamp = startedAt.toISOString().replace(/[:.]/g, '-');
  const outPath = cliArgs['out']
    ? path.resolve(String(cliArgs['out']))
    : path.join(__dirname, `contract-artifact-audit-${projectAlias}-${stamp}.json`);

  const report = {
    phase: 'CONTRACT-CONTENT-3.9',
    mode: 'READ_ONLY_AUDIT',
    projectAlias,
    projectId,
    bucket: bucketName,
    level,
    orphanAgeThresholdHours: ORPHAN_AGE_HOURS,
    startedAt: startedAt.toISOString(),
    finishedAt: new Date().toISOString(),
    summary: agg,
    severity: severityCounts(),
    // PII 없음: 서명/PDF bytes, 조항, 성명, 생년월일, 주소, 전화, 임금 일절 미포함.
    // hash 는 전체 값이 아닌 8자 접두만 기록.
    findings,
  };
  fs.writeFileSync(outPath, JSON.stringify(report, null, 2), 'utf8');

  printSummary(outPath);
}

main().catch(err => {
  console.error('\n❌ AUDIT FAILED:', err.message);
  console.error(err.stack);
  process.exit(1);
});
