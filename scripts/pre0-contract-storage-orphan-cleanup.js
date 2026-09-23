#!/usr/bin/env node
/**
 * [CORRECTION-DEV-CONTRACT-STORAGE-ORPHAN-CLEANUP]
 *
 * DEV Storage 의 **부모 없는** 계약 artifact 만 정리한다.
 *
 * 원인은 fixture 쪽이었다 — initializeApp 에 storageBucket 이 없어
 * `admin.storage().bucket()` 이 매번 throw 했고, cleanup 의 `catch (_) {}` 가
 * 그것을 삼켰다. Firestore 계약서는 사라지고 서명 PNG 와 계약 PDF 는 남았다.
 * 그 파일들에는 임금과 개인정보가 들어 있다.
 *
 * 이 스크립트는 그 누적분을 한 번 걷어내기 위한 것이다. 정기 retention 도,
 * "오래된 계약 파일 정리" 도 아니다 — 지우는 것은 **가리키는 계약 문서가
 * 존재하지 않는 object** 뿐이다.
 *
 *   node scripts/pre0-contract-storage-orphan-cleanup.js --project alfit-89567
 *   node scripts/pre0-contract-storage-orphan-cleanup.js --project alfit-89567 --execute
 *
 * 기본은 READ ONLY. --execute 가 있을 때만 삭제한다.
 * 로그에는 contractId · path · artifactType 만 남긴다 — 문서 내용은 읽지 않는다.
 */
'use strict';

// ══════════════════════════════════════════════════════════════════
// §1 · §14  안전 경계 — 셋 다 만족해야 지운다
// ══════════════════════════════════════════════════════════════════
const EXPECTED_DEV_PROJECT = 'alfit-89567';
const PROD_PROJECT_ID = 'alfit-prod';

const argv = process.argv.slice(2);
const projectId = (() => {
  const i = argv.indexOf('--project');
  return i >= 0 ? argv[i + 1] : null;
})();
if (projectId === PROD_PROJECT_ID) {
  console.error('PROD 프로젝트입니다. 실행하지 않습니다.');
  process.exit(2);
}
if (projectId !== EXPECTED_DEV_PROJECT) {
  console.error(`DEV 전용입니다. --project ${EXPECTED_DEV_PROJECT}`);
  process.exit(2);
}
const EXECUTE = argv.includes('--execute');

const {db, devBucket, STORAGE_BUCKET, EXPECTED_PROJECT} =
  require('./r7-fixture-lib');

// ══════════════════════════════════════════════════════════════════
// §4  판정 기준 — 감사 스크립트와 같은 규칙을 쓴다.
//     (scripts/contract-artifact-integrity-audit.js 의 분류를 옮긴 것이다.
//      두 곳이 다르게 판정하면 지우면 안 되는 것을 지운다.)
// ══════════════════════════════════════════════════════════════════
const LEGACY_FILENAMES =
  ['signature_employer.png', 'signature_worker.png', 'contract.pdf'];
const ARTIFACT_URL_FIELDS =
  ['employerSignatureUrl', 'workerSignatureUrl', 'pdfUrl'];

/** Firebase download URL → object path. malformed 는 null. */
function objectPathOfUrl(rawUrl) {
  if (typeof rawUrl !== 'string' || rawUrl.length === 0) return null;
  let u;
  try { u = new URL(rawUrl); } catch (_) { return null; }
  const m = u.pathname.match(/^\/v0\/b\/([^/]+)\/o\/(.+)$/);
  if (!m) return null;
  try { return decodeURIComponent(m[2]) || null; } catch (_) { return null; }
}

/** objectPath → 'LEGACY_DETERMINISTIC_PATH' | 'NEW_ATTEMPT_PATH' | 'UNKNOWN' */
function pathFamily(objectPath) {
  const seg = objectPath.split('/');
  if (seg[0] !== 'contracts' || seg.length < 3) return 'UNKNOWN';
  if (seg.length === 3 && LEGACY_FILENAMES.includes(seg[2])) {
    return 'LEGACY_DETERMINISTIC_PATH';
  }
  if (seg.length === 5 && seg[2] === 'attempts' &&
      LEGACY_FILENAMES.includes(seg[4])) {
    return 'NEW_ATTEMPT_PATH';
  }
  return 'UNKNOWN';
}

/** contracts/{contractId}/… → contractId */
function contractIdOf(objectPath) {
  const seg = objectPath.split('/');
  return (seg[0] === 'contracts' && seg.length >= 2 && seg[1]) ? seg[1] : null;
}

const log = (...a) => console.log(...a);
const head = (s) => log(`\n${'─'.repeat(74)}\n${s}\n${'─'.repeat(74)}`);

async function main() {
  const bucket = devBucket(); // §9 — 버킷/프로젝트 guard. 다르면 여기서 throw.
  log(`\nproject ${EXPECTED_PROJECT}   bucket ${bucket.name}`);
  log(EXECUTE ? '모드    EXECUTE — 증명된 parentless 만 삭제' :
    '모드    DRY RUN — 아무것도 쓰지 않는다 (--execute 로 삭제)');
  if (bucket.name !== STORAGE_BUCKET) {
    throw new Error('버킷 불일치 — 중단합니다.');
  }

  // ── §22  Firestore 기준선 ────────────────────────────────────────
  const contractsSnap = await db.collection('employment_contracts').get();
  const byStatus = {};
  const knownIds = new Set();
  const referenced = new Set();       // 보호 대상 object path
  const refOwner = new Map();         // path → {contractId, status, field}
  for (const d of contractsSnap.docs) {
    knownIds.add(d.id);
    const c = d.data();
    const st = (c.status || 'unknown');
    byStatus[st] = (byStatus[st] || 0) + 1;
    for (const f of ARTIFACT_URL_FIELDS) {
      const p = objectPathOfUrl(c[f]);
      if (!p) continue;
      referenced.add(p);
      refOwner.set(p, {contractId: d.id, status: st, field: f});
    }
  }
  const firestoreBefore = {total: contractsSnap.size, ...byStatus};
  head('§3  Firestore 기준선');
  log(`   employment_contracts ${JSON.stringify(firestoreBefore)}`);
  log(`   참조 중인 Storage object ${referenced.size}건 — 전부 보호 대상`);

  // ── §2 · §3 · §5  READ ONLY INVENTORY ───────────────────────────
  head('§3~§5  Storage inventory (read only)');
  const tally = {
    total: 0,
    family: {
      LEGACY_DETERMINISTIC_PATH: 0, NEW_ATTEMPT_PATH: 0, UNKNOWN: 0,
    },
    A_PARENTLESS: 0,
    B_UNREFERENCED_ATTEMPT: 0,
    C_REFERENCED_ACTIVE: 0,
    D_REFERENCED_HISTORICAL: 0,
    E_UNKNOWN: 0,
  };
  const candidates = [];   // A. PARENTLESS 만
  const bFamily = [];      // B. 보고만 한다
  const eFamily = [];
  const HISTORICAL = new Set(['completed', 'voided']);

  let pageToken;
  while (true) {
    const [files, nextQuery] = await bucket.getFiles({
      prefix: 'contracts/', autoPaginate: false, maxResults: 500, pageToken,
    });
    if (!files || files.length === 0) break;
    for (const f of files) {
      const p = f.name;
      tally.total++;
      const fam = pathFamily(p);
      tally.family[fam]++;
      const cid = contractIdOf(p);

      if (referenced.has(p)) {
        const owner = refOwner.get(p);
        if (HISTORICAL.has(owner.status)) tally.D_REFERENCED_HISTORICAL++;
        else tally.C_REFERENCED_ACTIVE++;
        continue;
      }
      if (!cid || fam === 'UNKNOWN') {
        tally.E_UNKNOWN++;
        eFamily.push({path: p, family: fam});
        continue;
      }
      if (!knownIds.has(cid)) {
        tally.A_PARENTLESS++;
        candidates.push({
          path: p, contractId: cid, family: fam,
          artifactType: p.split('/').pop(),
          created: (f.metadata && f.metadata.timeCreated) || null,
          size: (f.metadata && f.metadata.size) || null,
          file: f,
        });
        continue;
      }
      // 부모 계약은 있는데 지금 참조하지 않는 attempt.
      tally.B_UNREFERENCED_ATTEMPT++;
      bFamily.push({path: p, contractId: cid, family: fam});
    }
    if (!nextQuery || !nextQuery.pageToken) break;
    pageToken = nextQuery.pageToken;
  }

  log(`   contracts/ object 총 ${tally.total}건`);
  log(`   path family  LEGACY ${tally.family.LEGACY_DETERMINISTIC_PATH} · ` +
    `ATTEMPT ${tally.family.NEW_ATTEMPT_PATH} · UNKNOWN ${tally.family.UNKNOWN}`);
  log('');
  log(`   A PARENTLESS             ${tally.A_PARENTLESS}   ← 삭제 후보`);
  log(`   B UNREFERENCED_ATTEMPT   ${tally.B_UNREFERENCED_ATTEMPT}   ← 이번엔 남긴다`);
  log(`   C REFERENCED_ACTIVE      ${tally.C_REFERENCED_ACTIVE}   ← 보호`);
  log(`   D REFERENCED_HISTORICAL  ${tally.D_REFERENCED_HISTORICAL}   ← 보호`);
  log(`   E UNKNOWN                ${tally.E_UNKNOWN}   ← 보호`);

  // family 별 orphan 분포
  const famOfA = {};
  candidates.forEach((c) => { famOfA[c.family] = (famOfA[c.family] || 0) + 1; });
  log(`\n   A 의 path family 분포  ${JSON.stringify(famOfA)}`);
  const typeOfA = {};
  candidates.forEach((c) => { typeOfA[c.artifactType] = (typeOfA[c.artifactType] || 0) + 1; });
  log(`   A 의 artifact 종류      ${JSON.stringify(typeOfA)}`);
  const ownersOfA = new Set(candidates.map((c) => c.contractId));
  log(`   A 가 속한 사라진 계약   ${ownersOfA.size}건`);

  log('\n   sample (최대 5건 — 경로와 종류만):');
  candidates.slice(0, 5).forEach((c) =>
    log(`     ${c.contractId}/${c.artifactType}  ${c.created || '-'}`));
  if (bFamily.length > 0) {
    log('\n   B sample (삭제하지 않는다):');
    bFamily.slice(0, 5).forEach((c) => log(`     ${c.contractId}/${c.path.split('/').pop()}`));
  }
  if (eFamily.length > 0) {
    log('\n   E sample (판정 불가 — 삭제하지 않는다):');
    eFamily.slice(0, 5).forEach((c) => log(`     ${c.path}  family=${c.family}`));
  }

  if (!EXECUTE) {
    head('DRY RUN 종료');
    log(`   삭제 후보 ${candidates.length}건 · 보호 ` +
      `${tally.C_REFERENCED_ACTIVE + tally.D_REFERENCED_HISTORICAL +
         tally.B_UNREFERENCED_ATTEMPT + tally.E_UNKNOWN}건`);
    log('   아무것도 쓰지 않았습니다. 삭제하려면 --execute');
    return;
  }

  // ── §16 · §20  삭제 — 직전에 부모를 다시 확인한다 ────────────────
  head('§20  삭제');
  const result = {
    requested: candidates.length, deleted: 0, alreadyMissing: 0,
    skippedBecauseParentAppeared: 0, failed: 0, errors: [],
  };
  // 같은 계약의 파일이 여러 개다 — 계약당 한 번만 재확인한다.
  const recheck = new Map();
  for (const c of candidates) {
    if (!recheck.has(c.contractId)) {
      const s = await db.collection('employment_contracts').doc(c.contractId).get();
      recheck.set(c.contractId, s.exists);
    }
    if (recheck.get(c.contractId)) {
      // scan 과 delete 사이에 부모가 생겼다 — 지우지 않는다.
      result.skippedBecauseParentAppeared++;
      continue;
    }
    try {
      await c.file.delete();
      result.deleted++;
    } catch (e) {
      if (e && e.code === 404) result.alreadyMissing++;
      else {
        result.failed++;
        result.errors.push(`${c.contractId}/${c.artifactType}: ${e && e.message ? e.message : e}`);
      }
    }
    if ((result.deleted + result.alreadyMissing) % 50 === 0) {
      process.stdout.write(`\r   진행 ${result.deleted + result.alreadyMissing}/${result.requested}   `);
    }
  }
  process.stdout.write('\r');
  log(`   requested                    ${result.requested}`);
  log(`   deleted                      ${result.deleted}`);
  log(`   alreadyMissing               ${result.alreadyMissing}`);
  log(`   skippedBecauseParentAppeared ${result.skippedBecauseParentAppeared}`);
  log(`   failed                       ${result.failed}`);
  result.errors.slice(0, 5).forEach((e) => log(`     · ${e}`));

  // ── §21  post-delete rescan ─────────────────────────────────────
  head('§21  재스캔');
  const after = {total: 0, parentless: 0, referenced: 0, b: 0, unknown: 0};
  pageToken = undefined;
  while (true) {
    const [files, nextQuery] = await bucket.getFiles({
      prefix: 'contracts/', autoPaginate: false, maxResults: 500, pageToken,
    });
    if (!files || files.length === 0) break;
    for (const f of files) {
      const p = f.name;
      after.total++;
      if (referenced.has(p)) { after.referenced++; continue; }
      const cid = contractIdOf(p);
      if (!cid || pathFamily(p) === 'UNKNOWN') { after.unknown++; continue; }
      if (!knownIds.has(cid)) { after.parentless++; continue; }
      after.b++;
    }
    if (!nextQuery || !nextQuery.pageToken) break;
    pageToken = nextQuery.pageToken;
  }
  log(`   총 ${after.total}건 — parentless ${after.parentless} · ` +
    `referenced ${after.referenced} · unreferenced-attempt ${after.b} · unknown ${after.unknown}`);

  // ── §22  Firestore 불변 ─────────────────────────────────────────
  const after2 = await db.collection('employment_contracts').get();
  const byStatus2 = {};
  after2.docs.forEach((d) => {
    const st = d.data().status || 'unknown';
    byStatus2[st] = (byStatus2[st] || 0) + 1;
  });
  const firestoreAfter = {total: after2.size, ...byStatus2};
  head('§22  Firestore 계약 문서');
  log(`   BEFORE ${JSON.stringify(firestoreBefore)}`);
  log(`   AFTER  ${JSON.stringify(firestoreAfter)}`);
  log(JSON.stringify(firestoreBefore) === JSON.stringify(firestoreAfter) ?
    '   UNCHANGED — 이 스크립트는 Firestore 를 쓰지 않는다.' :
    '   ⚠️ 변했다 — 이 스크립트가 아니라면 다른 무언가가 썼다.');

  // ── §24  참조 artifact 가 살아 있는가 ───────────────────────────
  head('§24  참조 artifact 존재 확인');
  let missing = 0;
  for (const [p, owner] of refOwner) {
    const [exists] = await bucket.file(p).exists();
    if (!exists) {
      missing++;
      log(`   ⚠️ 없음  ${owner.contractId} ${owner.field} (${owner.status})`);
    }
  }
  log(missing === 0 ?
    `   참조 ${refOwner.size}건 전부 존재한다.` :
    `   ⚠️ ${missing}건이 사라졌다 — NEW FINDING, 자동 복구하지 않는다.`);

  if (result.failed > 0 || missing > 0) {
    log('\n실패가 있습니다 — closure 하지 않습니다.');
    process.exitCode = 1;
  }
}

main().then(() => process.exit(process.exitCode || 0)).catch((e) => {
  console.error('\n실패:', e && e.message ? e.message : e);
  process.exit(1);
});
