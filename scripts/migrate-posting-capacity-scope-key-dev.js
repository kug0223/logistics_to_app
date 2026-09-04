#!/usr/bin/env node
/**
 * PHASE ADMIN.POSTING.CAPACITY-SCOPE-STAGE2 — postingCapacityScopeKey BACKFILL (DEV ONLY)
 *
 * 목적:
 *   Stage 1 dual-write 배포 이전에 이미 ACTIVE/FULL 상태인 TO 문서에
 *   postingCapacityScopeKey 파생 인덱스 키를 소급 기록한다.
 *
 * Usage (dry-run — 쓰기 없음, 기본값):
 *   node scripts/migrate-posting-capacity-scope-key-dev.js --project alfit-89567
 *
 * Usage (execute — 쓰기 활성화):
 *   node scripts/migrate-posting-capacity-scope-key-dev.js --project alfit-89567 --execute
 *
 * HARD GUARDS:
 *   - --project alfit-89567  필수 (정확한 DEV project ID)
 *   - alfit-prod 포함 모든 비-DEV project ID 는 PERMANENT BLOCK
 *   - --execute 없으면 dry-run (Firestore 쓰기 없음)
 *
 * DEPLOYMENT GATE:
 *   POSTING-CAPACITY-STAGE2-MIGRATION-EXECUTION-GATE-01
 *   Stage 1 Functions dual-write 가 DEV 에 실제 배포된 것이 확인된 후에만 --execute 를 실행한다.
 *   코드 존재 / typecheck 통과 / Stage 1 CODE CLOSED 만으로는 gate 를 통과한 것이 아니다.
 *
 * 쓰기 필드:
 *   tos/{toId}.postingCapacityScopeKey  only
 *
 * 절대 변경하지 않는 필드:
 *   status, isPublished, isDeleted, businessId, ownerId, creatorUID,
 *   업무 관련 타임스탬프, 쿼터 카운트, maxActiveTOs
 */

'use strict';

const path = require('path');
const fs   = require('fs');

// ─── SAFETY BANNER ───────────────────────────────────────────────────────────
console.log('='.repeat(70));
console.log('postingCapacityScopeKey BACKFILL — DEV ONLY');
console.log('DEPLOYMENT GATE: Stage 1 Functions DEV deploy must be confirmed');
console.log('='.repeat(70));
console.log();

// ─── Arg parsing ─────────────────────────────────────────────────────────────
// Supports: --key value,  --key=value,  --flag (boolean)
const cliArgs = {};
const argList = process.argv.slice(2);
for (let i = 0; i < argList.length; i++) {
  const a = argList[i];
  if (!a.startsWith('--')) continue;
  const eq = a.indexOf('=');
  if (eq >= 0) {
    cliArgs[a.slice(2, eq)] = a.slice(eq + 1);
  } else if (i + 1 < argList.length && !argList[i + 1].startsWith('--')) {
    cliArgs[a.slice(2)] = argList[i + 1];
    i++;
  } else {
    cliArgs[a.slice(2)] = true;
  }
}

const EXPECTED_DEV_PROJECT = 'alfit-89567';
const PROD_PROJECT_ID      = 'alfit-prod';

const projectId   = cliArgs['project'] || null;
const executeMode = !!cliArgs['execute'];

// ─── HARD GUARD: explicit project required ────────────────────────────────────
if (!projectId) {
  console.error('ERROR: --project is REQUIRED.');
  console.error(`Usage: --project ${EXPECTED_DEV_PROJECT}`);
  console.error('No default project. DEV only.');
  process.exit(1);
}

// ─── HARD BLOCK: PROD and any non-DEV project ────────────────────────────────
if (projectId !== EXPECTED_DEV_PROJECT) {
  console.error(`ERROR: DEV migration only. Expected: "${EXPECTED_DEV_PROJECT}"`);
  console.error(`Received: "${projectId}"`);
  if (projectId === PROD_PROJECT_ID) {
    console.error('PROD write is PERMANENTLY BLOCKED in this script.');
  } else {
    console.error('Only the canonical DEV project ID is accepted.');
  }
  process.exit(1);
}

console.log(`Project      : ${projectId}`);
console.log(`Execute mode : ${executeMode ? '⚠️  YES — WRITES ENABLED' : 'DRY-RUN (pass --execute to write)'}`);
console.log();

if (!executeMode) {
  console.log('INFO: Dry-run mode. Candidate preview only. No Firestore writes.');
  console.log('      Run with --execute to write.');
  console.log();
}

// ─── Admin SDK ────────────────────────────────────────────────────────────────
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

const SA_PATH = path.join(__dirname, 'alfit-89567-firebase-adminsdk-fbsvc-d22e7faef3.json');
let credential;
if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  credential = admin.credential.applicationDefault();
  console.log('Credentials  : GOOGLE_APPLICATION_CREDENTIALS env');
} else if (fs.existsSync(SA_PATH)) {
  credential = admin.credential.cert(SA_PATH);
  console.log(`Credentials  : ${SA_PATH}`);
} else {
  console.error(`Service account not found: ${SA_PATH}`);
  console.error('Set GOOGLE_APPLICATION_CREDENTIALS or place the key at the expected path.');
  process.exit(1);
}

admin.initializeApp({ credential, projectId });
const db = admin.firestore();

// ─── Constants ────────────────────────────────────────────────────────────────
const SCOPE_PREFIX = 'ADMIN:';

// ─── Pure helpers ─────────────────────────────────────────────────────────────

/** Firestore Timestamp → milliseconds. null if absent/invalid. */
function tsToMs(v) {
  if (!v) return null;
  if (typeof v.toMillis === 'function') return v.toMillis();
  if (typeof v.toDate  === 'function') return v.toDate().getTime();
  if (v instanceof Date) return v.getTime();
  if (typeof v === 'number') return v;
  return null;
}

/**
 * isEffectiveActiveTOForQuota — mirrors CF helper exactly.
 * Returns true if document should count toward the active posting quota.
 *
 * MUST NOT use `where isDeleted == false` in Firestore query.
 * Call this in memory after querying status IN [ACTIVE, FULL].
 */
function isEffectiveActiveTOForQuota(data, nowMs) {
  // isDeleted !== true  (field may be absent on legacy docs — absent is NOT deleted)
  if (data.isDeleted === true) return false;

  const toType = data.type;
  const dl = tsToMs(data.applicationDeadline);
  const pe = tsToMs(data.postingExpiryDate);

  if (toType === 'contract') {
    if (pe != null && pe < nowMs) return false;
  } else {
    if (dl != null && dl < nowMs) return false;
    if (pe != null && pe < nowMs) return false;
  }
  return true;
}

/**
 * buildPostingCapacityScopeKey — mirrors CF helper exactly.
 * Returns "ADMIN:<ownerUid>". Throws if ownerUid is blank (fail-closed).
 */
function buildPostingCapacityScopeKey(ownerUid) {
  if (!ownerUid || typeof ownerUid !== 'string' || ownerUid.trim() === '') {
    throw new Error(`[CAPACITY-STAGE1] ownerUid가 비어 있습니다. postingCapacityScopeKey를 생성할 수 없습니다.`);
  }
  return `${SCOPE_PREFIX}${ownerUid}`;
}

/** Paginated Firestore read. Returns all docs matching query. */
async function fetchAll(query, label) {
  const docs   = [];
  let   cursor = null;
  while (true) {
    const q    = cursor ? query.startAfter(cursor).limit(500) : query.limit(500);
    const snap = await q.get();
    if (snap.empty) break;
    docs.push(...snap.docs);
    if (snap.docs.length < 500) break;
    cursor = snap.docs[snap.docs.length - 1];
    if (label) process.stdout.write(`\r  ${label}: ${docs.length} loaded...`);
  }
  if (label) process.stdout.write(`\r  ${label}: ${docs.length} loaded           \n`);
  return docs;
}

// ─── Key classification ───────────────────────────────────────────────────────
// K1: MISSING   — field absent or null
// K2: MATCH     — correct ADMIN:<ownerUid>
// K3: MISMATCH  — present but wrong owner
// K4: MALFORMED — present but not a valid "ADMIN:..." string

function classifyKey(existingKey, expectedKey) {
  if (existingKey === undefined || existingKey === null) return 'MISSING';
  if (typeof existingKey !== 'string') return 'MALFORMED';
  if (!existingKey.startsWith(SCOPE_PREFIX) || existingKey === SCOPE_PREFIX) return 'MALFORMED';
  if (existingKey === expectedKey) return 'MATCH';
  return 'MISMATCH';
}

// ─── Main ─────────────────────────────────────────────────────────────────────
async function main() {
  const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const nowMs = Date.now();

  // ── Step 1: Query ACTIVE/FULL TOs ─────────────────────────────────────────
  console.log('Step 1/4 — Querying status IN [ACTIVE, FULL]...');
  // NOTE: Do NOT add where("isDeleted", "==", false) — absent field ≠ false
  const toDocs = await fetchAll(
    db.collection('tos').where('status', 'in', ['ACTIVE', 'FULL']),
    'tos',
  );
  console.log(`  status IN [ACTIVE, FULL]: ${toDocs.length} docs`);
  console.log();

  // ── Step 2: In-memory classify ────────────────────────────────────────────
  console.log('Step 2/4 — In-memory classification...');

  // Collect unique businessIds
  const bizIdSet = new Set();
  for (const doc of toDocs) {
    const d = doc.data();
    if (d.businessId) bizIdSet.add(d.businessId);
  }

  // Resolve businesses: businessId → ownerId
  const bizOwnerMap = new Map(); // bizId → { ownerId, exists }
  if (bizIdSet.size > 0) {
    process.stdout.write(`  Loading ${bizIdSet.size} business doc(s)...\n`);
    for (const bizId of bizIdSet) {
      const snap = await db.collection('businesses').doc(bizId).get();
      if (snap.exists) {
        const ownerId = snap.data().ownerId || null;
        bizOwnerMap.set(bizId, { ownerId: typeof ownerId === 'string' && ownerId.trim() ? ownerId : null, exists: true });
      } else {
        bizOwnerMap.set(bizId, { ownerId: null, exists: false });
      }
    }
  }

  // Classify all docs
  let countEffective = 0;
  let countSoftDeleted = 0, countLogicallyExpired = 0;

  // Among effective:
  const keyMatch     = [];
  const keyMissing   = [];
  const keyMismatch  = [];
  const keyMalformed = [];
  const blockers     = []; // { toId, reason }

  for (const doc of toDocs) {
    const d    = doc.data();
    const toId = doc.id;

    // Soft-deleted but still ACTIVE/FULL status (data anomaly — do not write)
    if (d.isDeleted === true) {
      countSoftDeleted++;
      continue;
    }

    // Logically expired — skip (Stage 1 runtime does not write on already-expired)
    if (!isEffectiveActiveTOForQuota(d, nowMs)) {
      countLogicallyExpired++;
      continue;
    }

    countEffective++;

    // Resolve businessId
    const bizId = d.businessId;
    if (!bizId || typeof bizId !== 'string' || bizId.trim() === '') {
      blockers.push({ toId, reason: 'missing_businessId', bizId: null, ownerId: null });
      continue;
    }

    const biz = bizOwnerMap.get(bizId);
    if (!biz || !biz.exists) {
      blockers.push({ toId, reason: 'business_doc_missing', bizId, ownerId: null });
      continue;
    }

    if (!biz.ownerId) {
      blockers.push({ toId, reason: 'ownerId_absent_or_blank', bizId, ownerId: null });
      continue;
    }

    const expectedKey  = buildPostingCapacityScopeKey(biz.ownerId);
    const existingKey  = d.postingCapacityScopeKey;
    const classification = classifyKey(existingKey, expectedKey);

    const entry = { toId, bizId, ownerId: biz.ownerId, expectedKey, existingKey };

    switch (classification) {
      case 'MATCH':     keyMatch.push(entry);     break;
      case 'MISSING':   keyMissing.push(entry);   break;
      case 'MISMATCH':  keyMismatch.push(entry);  break;
      case 'MALFORMED': keyMalformed.push(entry); break;
    }
  }

  // ── Step 3: Report pre-migration state ───────────────────────────────────
  console.log();
  console.log('Pre-migration classification:');
  console.log(`  Total ACTIVE/FULL            : ${toDocs.length}`);
  console.log(`  Soft-deleted (skip)          : ${countSoftDeleted}`);
  console.log(`  Logically-expired (skip)     : ${countLogicallyExpired}`);
  console.log(`  EFFECTIVE_ACTIVE             : ${countEffective}`);
  console.log();
  console.log(`  Key MATCH (no write needed)  : ${keyMatch.length}`);
  console.log(`  Key MISSING  ← backfill      : ${keyMissing.length}`);
  console.log(`  Key MISMATCH ← NOT migrated  : ${keyMismatch.length}`);
  console.log(`  Key MALFORMED← NOT migrated  : ${keyMalformed.length}`);
  console.log(`  BLOCKERS                     : ${blockers.length}`);
  console.log();

  // ── FAIL-CLOSED: abort if ANY effective target has non-MISSING anomalies ──
  //
  // Rule (spec §7): if any effective target has mismatch / malformed / blocker,
  // abort BEFORE any write — do not partially migrate the clean MISSING subset.
  // Rationale: this migration establishes a quota enforcement invariant.
  const hasAnomalies = blockers.length > 0 || keyMismatch.length > 0 || keyMalformed.length > 0;

  if (hasAnomalies) {
    console.error('═'.repeat(70));
    console.error('ABORT — FAIL-CLOSED: data anomalies detected in effective ACTIVE/FULL TOs.');
    console.error('Migration BLOCKED. No writes will be performed.');
    console.error('Resolve all anomalies and re-run dry-run before executing.');
    console.error('');
    if (blockers.length > 0) {
      console.error(`Blockers (${blockers.length}):`);
      for (const b of blockers) {
        console.error(`  toId=${b.toId}  reason=${b.reason}  bizId=${b.bizId ?? 'n/a'}`);
      }
    }
    if (keyMismatch.length > 0) {
      console.error(`\nMISMATCH (${keyMismatch.length}) — requires manual investigation:`);
      for (const m of keyMismatch) {
        console.error(`  toId=${m.toId}  existing=${m.existingKey}  expected=${m.expectedKey}`);
      }
    }
    if (keyMalformed.length > 0) {
      console.error(`\nMALFORMED (${keyMalformed.length}) — requires manual investigation:`);
      for (const m of keyMalformed) {
        console.error(`  toId=${m.toId}  existing=${JSON.stringify(m.existingKey)}`);
      }
    }
    console.error('═'.repeat(70));
    process.exit(2);
  }

  // ── Proposed writes ───────────────────────────────────────────────────────
  console.log('Proposed writes (MISSING → ADMIN:<ownerId>):');
  if (keyMissing.length === 0) {
    console.log('  (none — all effective TOs already have correct key)');
  } else {
    for (const t of keyMissing) {
      console.log(`  TO: ${t.toId} | biz: ${t.bizId} | key: ${t.expectedKey}`);
    }
  }
  console.log();

  // ── DRY-RUN EXIT ─────────────────────────────────────────────────────────
  if (!executeMode) {
    console.log('='.repeat(70));
    console.log('DRY-RUN COMPLETE — No writes performed.');
    console.log(`Effective ACTIVE/FULL: ${countEffective}`);
    console.log(`Proposed writes      : ${keyMissing.length}`);
    if (keyMissing.length === 0) {
      console.log('All effective TOs already have correct key. No backfill needed.');
    }
    console.log('Run with --execute to write.');
    console.log('='.repeat(70));
    return;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // EXECUTE MODE below
  // ─────────────────────────────────────────────────────────────────────────

  if (keyMissing.length === 0) {
    console.log('='.repeat(70));
    console.log('EXECUTE: Nothing to write. All effective TOs already have correct key.');
    console.log('Migration COMPLETE (zero writes).');
    console.log('='.repeat(70));
    return;
  }

  // ── Backup ────────────────────────────────────────────────────────────────
  console.log('Step 3/4 — Creating backup...');
  const backupPath = path.join(__dirname, `migration-backup-capacity-scope-key-dev-${ts}.json`);

  // Backup records the original key state for each target.
  // Rollback: if originalKeyState === 'ABSENT', rollback = FieldValue.delete().
  const backupTargets = keyMissing.map(t => ({
    toId:             t.toId,
    bizId:            t.bizId,
    resolvedOwnerId:  t.ownerId,
    originalKeyState: t.existingKey === undefined ? 'ABSENT' : (t.existingKey === null ? 'NULL' : t.existingKey),
    expectedKey:      t.expectedKey,
    migratedAt:       null, // filled after write
  }));

  const backup = {
    generatedAt:       new Date().toISOString(),
    project:           projectId,
    phase:             'CAPACITY-SCOPE-STAGE2',
    description:       'Pre-migration snapshot for postingCapacityScopeKey backfill. Rollback: set field to originalKeyState (ABSENT → FieldValue.delete(), NULL → null, string → that string).',
    targets:           backupTargets,
    rollbackInstructions: [
      'If originalKeyState === "ABSENT": run db.collection("tos").doc(toId).update({ postingCapacityScopeKey: admin.firestore.FieldValue.delete() })',
      'If originalKeyState === "NULL":   run db.collection("tos").doc(toId).update({ postingCapacityScopeKey: null })',
      'If originalKeyState is a string:  run db.collection("tos").doc(toId).update({ postingCapacityScopeKey: "<that string>" })',
    ],
  };

  fs.writeFileSync(backupPath, JSON.stringify(backup, null, 2), 'utf8');
  console.log(`  Backup saved: ${backupPath}`);
  console.log();

  // ── Execute: per-target write with pre-write revalidation ─────────────────
  console.log('Step 4/4 — Executing backfill...');
  console.log('  (Re-reads each target immediately before write.)');
  console.log();

  const writeResults = {
    written:     0,
    skipped:     0,
    abortedAt:   null, // toId where abort happened
    errors:      [],
  };

  for (const target of keyMissing) {
    const { toId, bizId, ownerId, expectedKey } = target;

    // ── Pre-write revalidation ────────────────────────────────────────────
    // 1. Re-read TO
    const freshToSnap = await db.collection('tos').doc(toId).get();
    if (!freshToSnap.exists) {
      writeResults.errors.push({ toId, reason: 'TO_NOT_FOUND_AT_EXECUTE' });
      writeResults.abortedAt = toId;
      break; // fail-closed: abort entire run
    }
    const freshTo = freshToSnap.data();

    // 1a. Still ACTIVE/FULL?
    if (freshTo.status !== 'ACTIVE' && freshTo.status !== 'FULL') {
      writeResults.errors.push({ toId, reason: `STATUS_CHANGED: ${freshTo.status}` });
      writeResults.abortedAt = toId;
      break;
    }

    // 1b. Still not deleted?
    if (freshTo.isDeleted === true) {
      writeResults.errors.push({ toId, reason: 'BECAME_SOFT_DELETED' });
      writeResults.abortedAt = toId;
      break;
    }

    // 1c. Still effective?
    if (!isEffectiveActiveTOForQuota(freshTo, Date.now())) {
      writeResults.errors.push({ toId, reason: 'BECAME_LOGICALLY_EXPIRED' });
      writeResults.abortedAt = toId;
      break;
    }

    // 1d. Key still MISSING? (not set by Stage 1 deploy between dry-run and execute)
    const currentKey = freshTo.postingCapacityScopeKey;
    if (currentKey !== undefined && currentKey !== null) {
      // Already written by Stage 1 runtime — skip gracefully
      console.log(`  SKIP ${toId}: key now present (${currentKey}) — Stage 1 already wrote it`);
      writeResults.skipped++;
      continue;
    }

    // 2. Re-read business
    const freshBizSnap = await db.collection('businesses').doc(bizId).get();
    if (!freshBizSnap.exists) {
      writeResults.errors.push({ toId, reason: 'BIZ_DOC_MISSING_AT_EXECUTE', bizId });
      writeResults.abortedAt = toId;
      break;
    }
    const freshOwnerId = freshBizSnap.data().ownerId;
    if (!freshOwnerId || typeof freshOwnerId !== 'string' || freshOwnerId.trim() === '') {
      writeResults.errors.push({ toId, reason: 'OWNER_MISSING_AT_EXECUTE', bizId });
      writeResults.abortedAt = toId;
      break;
    }

    // 3. Re-compute expected key from fresh data
    const freshExpectedKey = buildPostingCapacityScopeKey(freshOwnerId);
    if (freshExpectedKey !== expectedKey) {
      // Owner changed between dry-run and execute
      writeResults.errors.push({
        toId,
        reason: 'OWNER_CHANGED',
        dryRunKey: expectedKey,
        freshKey: freshExpectedKey,
      });
      writeResults.abortedAt = toId;
      break;
    }

    // ── Write ─────────────────────────────────────────────────────────────
    // Single-field update only. No other fields touched.
    await db.collection('tos').doc(toId).update({
      postingCapacityScopeKey: freshExpectedKey,
    });

    console.log(`  ✅ WRITTEN ${toId} → ${freshExpectedKey}`);
    writeResults.written++;

    // Update backup with actual migration timestamp
    const bt = backupTargets.find(b => b.toId === toId);
    if (bt) bt.migratedAt = new Date().toISOString();
  }

  // Persist backup update (with migratedAt filled in)
  fs.writeFileSync(backupPath, JSON.stringify(backup, null, 2), 'utf8');

  console.log();

  // ── Post-write verification ────────────────────────────────────────────────
  console.log('Post-write verification...');
  const postNowMs    = Date.now();
  const postToDocs   = await fetchAll(
    db.collection('tos').where('status', 'in', ['ACTIVE', 'FULL']),
    'post-verify tos',
  );

  // Re-resolve bizOwnerMap for post-verify (re-read from Firestore)
  const postBizIdSet = new Set();
  for (const doc of postToDocs) {
    const d = doc.data();
    if (d.businessId) postBizIdSet.add(d.businessId);
  }
  const postBizOwnerMap = new Map();
  for (const bid of postBizIdSet) {
    const snap = await db.collection('businesses').doc(bid).get();
    if (snap.exists) {
      const oid = snap.data().ownerId || null;
      postBizOwnerMap.set(bid, { ownerId: typeof oid === 'string' && oid.trim() ? oid : null, exists: true });
    } else {
      postBizOwnerMap.set(bid, { ownerId: null, exists: false });
    }
  }

  let verifyEffective = 0, verifyMissing = 0, verifyMatch = 0;
  let verifyMismatch  = 0, verifyMalformed = 0, verifyBlockers = 0;
  const verifyWarnings = [];

  for (const doc of postToDocs) {
    const d = doc.data();
    if (d.isDeleted === true) continue;
    if (!isEffectiveActiveTOForQuota(d, postNowMs)) continue;
    verifyEffective++;

    const bizId = d.businessId;
    if (!bizId) { verifyBlockers++; continue; }
    const biz = postBizOwnerMap.get(bizId);
    if (!biz || !biz.exists || !biz.ownerId) { verifyBlockers++; continue; }

    const exp = buildPostingCapacityScopeKey(biz.ownerId);
    const cls = classifyKey(d.postingCapacityScopeKey, exp);

    if (cls === 'MATCH')     verifyMatch++;
    else if (cls === 'MISSING')   { verifyMissing++;   verifyWarnings.push(`MISSING: ${doc.id}`); }
    else if (cls === 'MISMATCH')  { verifyMismatch++;  verifyWarnings.push(`MISMATCH: ${doc.id} existing=${d.postingCapacityScopeKey} expected=${exp}`); }
    else if (cls === 'MALFORMED') { verifyMalformed++; verifyWarnings.push(`MALFORMED: ${doc.id} value=${JSON.stringify(d.postingCapacityScopeKey)}`); }
  }

  const verifyPass =
    verifyMissing === 0 &&
    verifyMismatch === 0 &&
    verifyMalformed === 0 &&
    verifyBlockers === 0;

  // ── Save report ────────────────────────────────────────────────────────────
  const reportPath = path.join(__dirname, `migration-report-capacity-scope-key-dev-${ts}.json`);
  const report = {
    generatedAt:   new Date().toISOString(),
    project:       projectId,
    phase:         'CAPACITY-SCOPE-STAGE2',
    writeResults,
    postVerify: {
      effectiveActive:  verifyEffective,
      keyMatch:         verifyMatch,
      keyMissing:       verifyMissing,
      keyMismatch:      verifyMismatch,
      keyMalformed:     verifyMalformed,
      blockers:         verifyBlockers,
      pass:             verifyPass,
      warnings:         verifyWarnings,
    },
    backupFile: backupPath,
  };
  fs.writeFileSync(reportPath, JSON.stringify(report, null, 2), 'utf8');

  // ── Final report ───────────────────────────────────────────────────────────
  const line = '═'.repeat(70);
  console.log();
  console.log(line);
  console.log('PHASE ADMIN.POSTING.CAPACITY-SCOPE-STAGE2 — EXECUTION REPORT');
  console.log(line);

  console.log('\n1. Safety');
  console.log(`   DEV project hard guard  : YES (alfit-89567 only)`);
  console.log(`   PROD blocked            : YES (permanent, any non-alfit-89567 project)`);
  console.log(`   --execute required      : YES`);
  console.log(`   Backup created          : ${backupPath}`);

  console.log('\n2. Pre-migration (dry-run state)');
  console.log(`   Effective ACTIVE/FULL   : ${countEffective}`);
  console.log(`   MATCH (no write needed) : ${keyMatch.length}`);
  console.log(`   MISSING (proposed write): ${keyMissing.length}`);
  console.log(`   MISMATCH / MALFORMED    : ${keyMismatch.length} / ${keyMalformed.length}`);
  console.log(`   Blockers                : ${blockers.length}`);

  console.log('\n3. Migration writes');
  console.log(`   Written                 : ${writeResults.written}`);
  console.log(`   Skipped (already set)   : ${writeResults.skipped}`);
  if (writeResults.abortedAt) {
    console.log(`   ❌ ABORTED at TO        : ${writeResults.abortedAt}`);
    for (const e of writeResults.errors) {
      console.log(`      reason: ${e.reason}`);
    }
  } else {
    console.log(`   Abort                   : none`);
  }

  console.log('\n4. Post-write verification');
  console.log(`   Effective ACTIVE/FULL   : ${verifyEffective}`);
  console.log(`   Key MATCH               : ${verifyMatch}`);
  console.log(`   Key MISSING             : ${verifyMissing}  (expected: 0)`);
  console.log(`   Key MISMATCH            : ${verifyMismatch}  (expected: 0)`);
  console.log(`   Key MALFORMED           : ${verifyMalformed}  (expected: 0)`);
  console.log(`   Blockers                : ${verifyBlockers}  (expected: 0)`);
  console.log(`   PASS                    : ${verifyPass ? '✅ YES' : '❌ NO'}`);

  if (verifyWarnings.length > 0) {
    console.log('   Warnings:');
    for (const w of verifyWarnings.slice(0, 10)) console.log(`     ⚠️  ${w}`);
    if (verifyWarnings.length > 10) console.log(`     … (${verifyWarnings.length - 10} more — see JSON report)`);
  }

  console.log('\n5. Write scope (ONLY postingCapacityScopeKey modified)');
  console.log('   status / isPublished / isDeleted    : NOT CHANGED ✅');
  console.log('   businessId / ownerId / creatorUID   : NOT CHANGED ✅');
  console.log('   timestamps / quota counts           : NOT CHANGED ✅');
  console.log('   maxActiveTOs                        : NOT CHANGED ✅');

  console.log('\n6. Files created');
  console.log(`   migration script   : scripts/migrate-posting-capacity-scope-key-dev.js`);
  console.log(`   backup             : ${backupPath}`);
  console.log(`   verification report: ${reportPath}`);

  console.log('\n7. MIGRATION RESULT');
  if (!writeResults.abortedAt && verifyPass) {
    console.log('   ✅ PASS — postingCapacityScopeKey backfill COMPLETE');
    console.log('   Stage 2 CLOSED.');
  } else if (writeResults.abortedAt) {
    console.log(`   ❌ FAIL — Aborted at ${writeResults.abortedAt}. See backup for rollback.`);
  } else {
    console.log('   ❌ FAIL — Post-verify failed. Review warnings and re-run.');
  }

  console.log('\n8. NEXT');
  if (!writeResults.abortedAt && verifyPass) {
    console.log('   Stage 2 CLOSED → Stage 3 planning.');
    console.log('   Stage 3: admin-total quota enforcement (maxActiveTOs cross-business).');
    console.log('   Note: multi-business owner DEV test setup needed for Stage 3 validation.');
  } else {
    console.log('   Resolve errors → re-run dry-run → confirm → re-execute.');
  }

  console.log('\n' + line);
  console.log(`JSON report: ${reportPath}`);
  console.log(line);

  if (!verifyPass || writeResults.abortedAt) {
    process.exit(3);
  }
}

main().catch(err => {
  console.error('\n❌ MIGRATION FAILED:', err.message);
  console.error(err.stack);
  process.exit(1);
});
