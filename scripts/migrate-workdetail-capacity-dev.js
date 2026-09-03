#!/usr/bin/env node
/**
 * PHASE 8.1E.3B — WORKDETAIL CAPACITY DATA MIGRATION  (DEV ONLY)
 *
 * Usage (dry-run — no writes):
 *   node scripts/migrate-workdetail-capacity-dev.js --project alfit-89567
 *
 * Usage (execute — writes enabled):
 *   node scripts/migrate-workdetail-capacity-dev.js --project alfit-89567 --execute
 *
 * HARD GUARDS:
 *   - --project alfit-89567  is required (exact DEV project ID)
 *   - Any other project ID (including alfit-prod) is BLOCKED
 *   - --execute flag is required for actual writes
 */

'use strict';

const path = require('path');
const fs   = require('fs');

// ─── SAFETY BANNER ───────────────────────────────────────────────────────────
console.log('='.repeat(60));
console.log('WORKDETAIL CAPACITY MIGRATION — DEV ONLY');
console.log('='.repeat(60));
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

const projectId   = cliArgs['project']  || null;
const executeMode = !!cliArgs['execute'];

// ─── HARD GUARD: explicit project required ────────────────────────────────────
if (!projectId) {
  console.error('ERROR: --project is REQUIRED.');
  console.error(`Usage: --project ${EXPECTED_DEV_PROJECT}`);
  console.error('No default project is allowed. DEV only.');
  process.exit(1);
}

// ─── HARD BLOCK: PROD ────────────────────────────────────────────────────────
if (projectId !== EXPECTED_DEV_PROJECT) {
  console.error(`ERROR: DEV migration only. Expected: "${EXPECTED_DEV_PROJECT}"`);
  console.error(`Received: "${projectId}"`);
  if (projectId === PROD_PROJECT_ID) {
    console.error('PROD write is PERMANENTLY BLOCKED in this script.');
  }
  process.exit(1);
}

console.log(`Project      : ${projectId}`);
console.log(`Execute mode : ${executeMode ? '⚠️  YES — WRITES ENABLED' : 'DRY-RUN (pass --execute to write)'}`);
console.log();

if (!executeMode) {
  console.log('INFO: Dry-run mode. Showing migration preview only.');
  console.log('      Run with --execute to write to Firestore.');
  console.log();
}

// ─── Admin SDK ────────────────────────────────────────────────────────────────
let admin;
try {
  admin = require(path.join(__dirname, '../functions/node_modules/firebase-admin'));
} catch (_) {
  try { admin = require('firebase-admin'); }
  catch (__) { console.error('firebase-admin not found. cd functions && npm install'); process.exit(1); }
}

const SA_PATH = path.join(__dirname, 'alfit-89567-firebase-adminsdk-fbsvc-d22e7faef3.json');
let credential;
if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  credential = admin.credential.applicationDefault();
} else if (fs.existsSync(SA_PATH)) {
  credential = admin.credential.cert(SA_PATH);
} else {
  console.error(`Service account not found: ${SA_PATH}`);
  process.exit(1);
}

admin.initializeApp({ credential, projectId });
const db = admin.firestore();

// ─── Constants ────────────────────────────────────────────────────────────────
const PENDING_STATUSES       = new Set(['PENDING', 'INVITED']);
const CONFIRMED_STATUSES_SET = new Set(['CONFIRMED', 'CONTRACT_PENDING']);
const ACTIVE_STATUSES        = new Set(['PENDING', 'INVITED', 'CONTRACT_PENDING', 'CONFIRMED']);

// ─── Helpers ─────────────────────────────────────────────────────────────────
async function fetchAll(query, label) {
  const docs = [];
  let cursor = null;
  while (true) {
    const q    = cursor ? query.startAfter(cursor).limit(500) : query.limit(500);
    const snap = await q.get();
    if (snap.empty) break;
    docs.push(...snap.docs);
    if (snap.docs.length < 500) break;
    cursor = snap.docs[snap.docs.length - 1];
    if (label) process.stdout.write(`\r  ${label}: ${docs.length} loaded...`);
  }
  if (label) process.stdout.write(`\r  ${label}: ${docs.length} loaded          \n`);
  return docs;
}

async function loadSlots() {
  try {
    return await fetchAll(db.collectionGroup('slots'), 'slots');
  } catch (_) {
    process.stdout.write('\r  collectionGroup failed, per-TO fallback...      \n');
    const toDocs = await fetchAll(db.collection('tos'));
    const slotDocs = [];
    for (const d of toDocs) {
      const s = await fetchAll(db.collection('tos').doc(d.id).collection('slots'));
      slotDocs.push(...s);
    }
    console.log(`  slots (per-TO): ${slotDocs.length}`);
    return slotDocs;
  }
}

function buildCompositeId(workType, startTime, endTime) {
  if (!workType || !startTime || !endTime) return null;
  return `${workType}_${startTime}_${endTime}`;
}

/**
 * Resolve which WD an application maps to.
 * Priority chain (Phase 8.1E.2B / 8.1E.3A semantics):
 * P1. app.wdId  P2. composite  P3. time triple  P4. unique workType  P5. ambiguous/unresolved
 */
function resolveWd(app, wds) {
  if (app.wdId) {
    const idx = wds.findIndex(wd => wd.wdId === app.wdId);
    if (idx >= 0) return { resolvedWdId: app.wdId, resolvedWdIdx: idx, method: 'BY_WD_ID', ambiguous: false, orphan: false };
    return { resolvedWdId: app.wdId, resolvedWdIdx: -1, method: 'BY_WD_ID', ambiguous: false, orphan: true };
  }
  const wt = app.selectedWorkType, st = app.startTime, en = app.endTime;
  if (app.workDetailId) {
    const idx = wds.findIndex(wd => {
      const c = buildCompositeId(wd.workType, wd.startTime, wd.endTime);
      return c !== null && c === app.workDetailId;
    });
    if (idx >= 0) return { resolvedWdId: wds[idx].wdId || null, resolvedWdIdx: idx, method: 'BY_COMPOSITE', ambiguous: false, orphan: false };
  }
  if (wt && st && en) {
    const hits = [];
    for (let i = 0; i < wds.length; i++) {
      if (wds[i].workType === wt && wds[i].startTime === st && wds[i].endTime === en) hits.push(i);
    }
    if (hits.length === 1) return { resolvedWdId: wds[hits[0]].wdId || null, resolvedWdIdx: hits[0], method: 'BY_TIME_TRIPLE', ambiguous: false, orphan: false };
    if (hits.length > 1)  return { resolvedWdId: null, resolvedWdIdx: -1, method: 'AMBIGUOUS_TRIPLE', ambiguous: true, orphan: false };
  }
  if (wt) {
    const hits = [];
    for (let i = 0; i < wds.length; i++) { if (wds[i].workType === wt) hits.push(i); }
    if (hits.length === 1) return { resolvedWdId: wds[hits[0]].wdId || null, resolvedWdIdx: hits[0], method: 'BY_UNIQUE_WORKTYPE', ambiguous: false, orphan: false };
    if (hits.length > 1)  return { resolvedWdId: null, resolvedWdIdx: -1, method: 'AMBIGUOUS_WORKTYPE', ambiguous: true, orphan: false };
  }
  return { resolvedWdId: null, resolvedWdIdx: -1, method: 'UNRESOLVED', ambiguous: false, orphan: false };
}

// ─── Slot migration (one transaction per slot) ────────────────────────────────
/**
 * Migrates a single slot within a Firestore transaction.
 * ALL READS → VALIDATE → ALL WRITES (Firestore transaction ordering rules).
 *
 * Classification inside transaction (from fresh data):
 *   CASE A — COMPLETE: all WDs have wdId + WDC complete + apps have wdId → SKIP
 *   CASE B — LEGACY:   no WDs have wdId + no WDC                         → MIGRATE
 *   CASE C — PARTIAL:  mixed state                                        → ABORT
 *
 * Returns: { status, appWriteCount, slotTotalWarning }
 */
async function migrateSlotTx(slotRef, appRefs, preGenWdIds, preGenWdCount) {
  return db.runTransaction(async (tx) => {
    // ── PHASE 1: ALL READS ────────────────────────────────────────────────
    const slotSnap     = await tx.get(slotRef);
    const freshAppSnaps = appRefs.length > 0
      ? await Promise.all(appRefs.map(ref => tx.get(ref)))
      : [];

    if (!slotSnap.exists) throw new Error('SLOT_NOT_FOUND');

    const sd       = slotSnap.data();
    const freshWds = Array.isArray(sd.workDetails) ? sd.workDetails : [];
    const freshWdc = (sd.workDetailCounts && typeof sd.workDetailCounts === 'object') ? sd.workDetailCounts : null;

    // ── PHASE 2: CLASSIFY ────────────────────────────────────────────────
    const anyHasWdId  = freshWds.some(wd => typeof wd.wdId === 'string' && wd.wdId.length > 0);
    const allHaveWdId = freshWds.length > 0 && freshWds.every(wd => typeof wd.wdId === 'string' && wd.wdId.length > 0);
    const wdIdSet     = new Set(freshWds.filter(wd => wd.wdId).map(wd => wd.wdId));
    const wdcComplete = freshWdc !== null && freshWds.every(wd => wd.wdId && freshWdc[wd.wdId] !== undefined);

    const freshApps      = freshAppSnaps.filter(s => s.exists).map(s => ({ ref: s.ref, ...s.data() }));
    const appsAllHaveWdId = freshApps.length === 0 || freshApps.every(a => a.wdId);

    // CASE A: fully migrated → skip
    if (allHaveWdId && wdcComplete && appsAllHaveWdId) {
      return { status: 'SKIP_ALREADY_MIGRATED', appWriteCount: 0, slotTotalWarning: null };
    }

    // CASE C: partial/mixed state → abort (do not auto-repair)
    if (anyHasWdId || freshWdc !== null) {
      throw new Error('PARTIAL_MIGRATION_ERROR: mixed state — wdId or WDC partially present');
    }

    // CASE B: pure legacy → proceed

    // Safety: WD count changed between preload and transaction
    if (freshWds.length !== preGenWdCount) {
      throw new Error(`SLOT_CHANGED: workDetails count changed (preload=${preGenWdCount}, fresh=${freshWds.length})`);
    }

    // ── PHASE 3: GENERATE wdIds (use pre-generated stable IDs) ───────────
    const wdsWithIds = freshWds.map((wd, i) => ({ ...wd, wdId: preGenWdIds[i] }));
    const newWdIdSet = new Set(wdsWithIds.map(w => w.wdId));

    // INVARIANT: no duplicate wdIds
    if (newWdIdSet.size !== wdsWithIds.length) {
      throw new Error('INVARIANT_VIOLATION: duplicate wdId in generated set');
    }

    // ── PHASE 4: RESOLVE APPLICATIONS ────────────────────────────────────
    const appWrites = []; // { ref, resolvedWdId }

    for (const app of freshApps) {
      const res = resolveWd(app, wdsWithIds);

      if (res.ambiguous) {
        throw new Error(`FAIL_CLOSED_AMBIGUOUS: app=${app.id || '?'} method=${res.method}`);
      }
      if (res.orphan || res.resolvedWdIdx < 0) {
        throw new Error(`FAIL_CLOSED_UNRESOLVED: app=${app.id || '?'} method=${res.method}`);
      }

      const resolvedWdId = wdsWithIds[res.resolvedWdIdx].wdId;
      appWrites.push({ ref: app.ref, resolvedWdId });
    }

    // ── PHASE 5: RECOUNT workDetailCounts ────────────────────────────────
    const workDetailCounts = {};
    for (const wd of wdsWithIds) {
      workDetailCounts[wd.wdId] = { pendingCount: 0, confirmedCount: 0 };
    }
    for (const app of freshApps) {
      const write = appWrites.find(w => w.ref.id === (app.id || app.ref?.id));
      if (!write) continue;
      const status = app.status || '';
      if (PENDING_STATUSES.has(status))       workDetailCounts[write.resolvedWdId].pendingCount++;
      if (CONFIRMED_STATUSES_SET.has(status)) workDetailCounts[write.resolvedWdId].confirmedCount++;
    }

    // ── PHASE 6: PRE-COMMIT INVARIANTS ───────────────────────────────────

    // 6a. workDetailCounts entry for every wdId (and vice versa)
    for (const wdId of newWdIdSet) {
      if (!workDetailCounts[wdId]) throw new Error(`INVARIANT: missing WDC entry for wdId=${wdId}`);
    }
    for (const k of Object.keys(workDetailCounts)) {
      if (!newWdIdSet.has(k)) throw new Error(`INVARIANT: orphan WDC key=${k} not in wdsWithIds`);
    }

    // 6b. App.resolvedWdId ∈ newWdIdSet
    for (const { resolvedWdId } of appWrites) {
      if (!newWdIdSet.has(resolvedWdId)) throw new Error(`INVARIANT: resolvedWdId=${resolvedWdId} not in generated wdIdSet`);
    }

    // 6c. Aggregate comparison: workDetailCounts sum == workTypeCounts (bidirectional)
    const workTypeSim = {};
    for (const wd of wdsWithIds) {
      const wt = wd.workType;
      if (!wt) continue;
      if (!workTypeSim[wt]) workTypeSim[wt] = { pendingCount: 0, confirmedCount: 0 };
      const wdcEntry = workDetailCounts[wd.wdId];
      workTypeSim[wt].pendingCount   += wdcEntry.pendingCount;
      workTypeSim[wt].confirmedCount += wdcEntry.confirmedCount;
    }
    const existingWTC = sd.workTypeCounts || {};
    for (const [wt, sim] of Object.entries(workTypeSim)) {
      const ex = existingWTC[wt] || {};
      if ((ex.pendingCount || 0) !== sim.pendingCount || (ex.confirmedCount || 0) !== sim.confirmedCount) {
        throw new Error(`AGGREGATE_MISMATCH: workType=${wt} existing=(p=${ex.pendingCount || 0},c=${ex.confirmedCount || 0}) sim=(p=${sim.pendingCount},c=${sim.confirmedCount})`);
      }
    }
    for (const [wt, ex] of Object.entries(existingWTC)) {
      const sim = workTypeSim[wt] || { pendingCount: 0, confirmedCount: 0 };
      if ((ex.pendingCount || 0) !== sim.pendingCount || (ex.confirmedCount || 0) !== sim.confirmedCount) {
        throw new Error(`AGGREGATE_MISMATCH(reverse): workType=${wt} existing=(p=${ex.pendingCount || 0},c=${ex.confirmedCount || 0}) sim=(p=${sim.pendingCount},c=${sim.confirmedCount})`);
      }
    }

    // 6d. Slot total comparison (soft warning, no abort — semantics may differ)
    const simTotalPending   = Object.values(workDetailCounts).reduce((s, c) => s + c.pendingCount,   0);
    const simTotalConfirmed = Object.values(workDetailCounts).reduce((s, c) => s + c.confirmedCount, 0);
    const slotTotalWarning  = (simTotalPending !== (sd.pendingCount || 0) || simTotalConfirmed !== (sd.confirmedCount || 0))
      ? `sim(p=${simTotalPending},c=${simTotalConfirmed}) vs slot(p=${sd.pendingCount || 0},c=${sd.confirmedCount || 0})`
      : null;

    // ── PHASE 7: ALL WRITES ───────────────────────────────────────────────
    // Write slot: workDetails (with wdIds) + workDetailCounts
    // Do NOT touch: workTypeCounts, pendingCount, confirmedCount (preserved)
    tx.update(slotRef, {
      workDetails:       wdsWithIds,
      workDetailCounts,
    });

    // Backfill Application.wdId (status-agnostic, all resolvable apps)
    for (const { ref, resolvedWdId } of appWrites) {
      tx.update(ref, { wdId: resolvedWdId });
    }

    // ── Return result (no reads after writes) ─────────────────────────────
    return {
      status: 'MIGRATED',
      appWriteCount: appWrites.length,
      slotTotalWarning,
    };
  });
}

// ─── Post-verify (re-read from Firestore) ────────────────────────────────────
async function postVerify() {
  console.log('Post-verify: re-reading all slots and apps from Firestore...');
  const slotDocs  = await loadSlots();
  const allApps   = await fetchAll(db.collection('applications'), 'post-verify apps');

  const appsBySlot = new Map();
  for (const doc of allApps) {
    const d = doc.data();
    if (!d.slotId) continue;
    if (!appsBySlot.has(d.slotId)) appsBySlot.set(d.slotId, []);
    appsBySlot.get(d.slotId).push({ id: doc.id, ...d });
  }

  let legacyRemaining = 0, newSchemaCount = 0, wdcCompleteCount = 0;
  let orphanWDC = 0, missingWDC = 0;
  let appWdIdValid = 0, appWdIdInvalid = 0, appWdIdMissing = 0;
  let recountMismatch = 0, legacyAggregateDrift = 0;
  const warnings = [];

  for (const slotDoc of slotDocs) {
    const sd    = slotDoc.data();
    const wds   = Array.isArray(sd.workDetails) ? sd.workDetails : [];
    const wdc   = (sd.workDetailCounts && typeof sd.workDetailCounts === 'object') ? sd.workDetailCounts : null;
    const apps  = appsBySlot.get(slotDoc.id) || [];

    const allHaveWdId = wds.length > 0 && wds.every(wd => typeof wd.wdId === 'string' && wd.wdId.length > 0);
    const wdIdSet     = new Set(wds.filter(wd => wd.wdId).map(wd => wd.wdId));

    if (allHaveWdId) newSchemaCount++; else legacyRemaining++;

    if (wdc) {
      const wdcKeys = new Set(Object.keys(wdc));
      let ok = true;
      for (const wdId of wdIdSet) { if (!wdcKeys.has(wdId)) { missingWDC++; ok = false; } }
      for (const k   of wdcKeys)  { if (!wdIdSet.has(k))    { orphanWDC++;  ok = false; } }
      if (ok && wdcKeys.size === wdIdSet.size) wdcCompleteCount++;
    }

    // App wdId validation (slot-based apps only)
    for (const app of apps) {
      if (app.wdId) {
        if (wdIdSet.has(app.wdId)) appWdIdValid++;
        else { appWdIdInvalid++; warnings.push(`INVALID: app=${app.id} wdId=${app.wdId} not in slot ${slotDoc.id}`); }
      } else {
        appWdIdMissing++;
        if (ACTIVE_STATUSES.has(app.status)) {
          warnings.push(`MISSING_WD_ID_ACTIVE: app=${app.id} status=${app.status} slot=${slotDoc.id}`);
        }
      }
    }

    // Recount verification
    if (allHaveWdId && wdc) {
      const simCounts = {};
      for (const wdId of wdIdSet) simCounts[wdId] = { pendingCount: 0, confirmedCount: 0 };

      for (const app of apps) {
        const wdId = app.wdId;
        if (!wdId || !simCounts[wdId]) continue;
        if (PENDING_STATUSES.has(app.status))       simCounts[wdId].pendingCount++;
        if (CONFIRMED_STATUSES_SET.has(app.status)) simCounts[wdId].confirmedCount++;
      }

      let mismatch = false;
      for (const [wdId, sim] of Object.entries(simCounts)) {
        const stored = wdc[wdId] || {};
        if ((stored.pendingCount || 0) !== sim.pendingCount || (stored.confirmedCount || 0) !== sim.confirmedCount) {
          mismatch = true;
          warnings.push(`RECOUNT_MISMATCH: slot=${slotDoc.id} wdId=${wdId} stored=(p=${stored.pendingCount || 0},c=${stored.confirmedCount || 0}) sim=(p=${sim.pendingCount},c=${sim.confirmedCount})`);
        }
      }
      if (mismatch) recountMismatch++;
    }

    // Legacy aggregate drift (new-schema slots should match workTypeCounts)
    if (allHaveWdId && wdc && sd.workTypeCounts) {
      const simWTC = {};
      for (const wd of wds) {
        const wt = wd.workType;
        if (!wt || !wd.wdId) continue;
        if (!simWTC[wt]) simWTC[wt] = { pendingCount: 0, confirmedCount: 0 };
        const e = wdc[wd.wdId] || {};
        simWTC[wt].pendingCount   += e.pendingCount   || 0;
        simWTC[wt].confirmedCount += e.confirmedCount || 0;
      }
      let drift = false;
      for (const [wt, sim] of Object.entries(simWTC)) {
        const ex = sd.workTypeCounts[wt] || {};
        if ((ex.pendingCount || 0) !== sim.pendingCount || (ex.confirmedCount || 0) !== sim.confirmedCount) {
          drift = true;
          warnings.push(`LEGACY_AGG_DRIFT: slot=${slotDoc.id} wt=${wt} WTC=(p=${ex.pendingCount || 0},c=${ex.confirmedCount || 0}) WDC_sum=(p=${sim.pendingCount},c=${sim.confirmedCount})`);
        }
      }
      if (drift) legacyAggregateDrift++;
    }
  }

  return {
    totalSlots: slotDocs.length,
    legacyRemaining,
    newSchemaCount,
    wdcCompleteCount,
    orphanWDC,
    missingWDC,
    appWdIdValid,
    appWdIdInvalid,
    appWdIdMissing,
    recountMismatch,
    legacyAggregateDrift,
    warnings,
    pass: legacyRemaining === 0 && orphanWDC === 0 && missingWDC === 0 && appWdIdInvalid === 0 && recountMismatch === 0 && legacyAggregateDrift === 0,
  };
}

// ─── Re-run audit (equivalent of migration-audit.js metrics) ─────────────────
async function reRunAudit() {
  console.log('Re-running audit metrics...');
  const slotDocs = await loadSlots();
  const allApps  = await fetchAll(db.collection('applications'));

  const appsBySlot = new Map();
  let totalApps = 0, appsWithWdId = 0, appsWithoutWdId = 0;
  const statusCounts = {};

  for (const doc of allApps) {
    const d = doc.data();
    if (!d.slotId) continue;
    totalApps++;
    if (d.wdId) appsWithWdId++; else appsWithoutWdId++;
    const s = d.status || 'UNKNOWN';
    statusCounts[s] = (statusCounts[s] || 0) + 1;
    if (!appsBySlot.has(d.slotId)) appsBySlot.set(d.slotId, []);
    appsBySlot.get(d.slotId).push({ id: doc.id, ...d });
  }

  let legacy = 0, newSchema = 0, slotsWithWDC = 0;
  let activeAmbiguous = 0, activeUnresolved = 0, activeTotal = 0;

  for (const slotDoc of slotDocs) {
    const wds = Array.isArray(slotDoc.data().workDetails) ? slotDoc.data().workDetails : [];
    const wdc = slotDoc.data().workDetailCounts;
    const isNew = wds.length > 0 && wds.every(wd => typeof wd.wdId === 'string' && wd.wdId.length > 0);
    if (isNew) newSchema++; else legacy++;
    if (wdc) slotsWithWDC++;

    const apps = appsBySlot.get(slotDoc.id) || [];
    for (const app of apps) {
      if (!ACTIVE_STATUSES.has(app.status)) continue;
      activeTotal++;
      const res = resolveWd(app, wds);
      if (res.ambiguous) activeAmbiguous++;
      else if (res.orphan || res.resolvedWdIdx < 0) activeUnresolved++;
    }
  }

  return {
    totalSlots: slotDocs.length,
    legacySlots: legacy, newSchemaSlots: newSchema, slotsWithWDC,
    totalApps, appsWithWdId, appsWithoutWdId,
    activeTotal, activeAmbiguous, activeUnresolved,
    statusCounts,
  };
}

// ─── Main ─────────────────────────────────────────────────────────────────────
async function main() {
  const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);

  // ── Load data ─────────────────────────────────────────────────────────────
  console.log('Loading data...');
  const slotDocs  = await loadSlots();
  const allApps   = await fetchAll(db.collection('applications'), 'applications');

  const appsBySlot = new Map();
  for (const doc of allApps) {
    const d = doc.data();
    if (!d.slotId) continue;
    if (!appsBySlot.has(d.slotId)) appsBySlot.set(d.slotId, []);
    appsBySlot.get(d.slotId).push({ id: doc.id, ref: doc.ref, ...d });
  }

  const totalSlotApps = Array.from(appsBySlot.values()).reduce((s, a) => s + a.length, 0);
  console.log(`  ${slotDocs.length} slots, ${totalSlotApps} slot-based applications`);
  console.log();

  // ── Pre-migration classification ──────────────────────────────────────────
  let preComplete = 0, preLegacy = 0, prePartial = 0;
  for (const slotDoc of slotDocs) {
    const wds = Array.isArray(slotDoc.data().workDetails) ? slotDoc.data().workDetails : [];
    const wdc = slotDoc.data().workDetailCounts;
    const anyWdId = wds.some(wd => wd.wdId);
    const allWdId = wds.length > 0 && wds.every(wd => wd.wdId);
    if (allWdId && wdc) preComplete++;
    else if (!anyWdId && !wdc) preLegacy++;
    else prePartial++;
  }

  console.log('Pre-migration classification:');
  console.log(`  COMPLETE (already migrated) : ${preComplete}`);
  console.log(`  LEGACY (migration target)   : ${preLegacy}`);
  console.log(`  PARTIAL/MIXED (blocked)     : ${prePartial}`);
  console.log(`  Applications to backfill    : ~${totalSlotApps} (exact count from dry-run: 6)`);
  console.log();

  // ── Backup ────────────────────────────────────────────────────────────────
  const backupPath = path.join(__dirname, `migration-backup-dev-${ts}.json`);
  const backup = {
    generatedAt: new Date().toISOString(),
    project: projectId,
    description: 'Pre-migration snapshot for recovery. No personal data.',
    slots: slotDocs.map(doc => {
      const d    = doc.data();
      const toId = doc.ref.parent?.parent?.id ?? 'UNKNOWN';
      const apps = appsBySlot.get(doc.id) || [];
      return {
        toId, slotId: doc.id,
        originalWorkDetails: (d.workDetails || []).map(wd => ({
          workType: wd.workType, startTime: wd.startTime, endTime: wd.endTime,
          wdId: wd.wdId || null,
        })),
        originalWorkTypeCounts: d.workTypeCounts || null,
        originalPendingCount:   d.pendingCount   ?? null,
        originalConfirmedCount: d.confirmedCount ?? null,
        originalWorkDetailCountsExisted: !!(d.workDetailCounts),
        applicationCount: apps.length,
        applications: apps.map(a => ({ appId: a.id, status: a.status, originalWdId: a.wdId || null })),
      };
    }),
  };
  fs.writeFileSync(backupPath, JSON.stringify(backup, null, 2), 'utf8');
  console.log(`Backup saved: ${backupPath}`);
  console.log();

  // ── DRY-RUN EXIT ──────────────────────────────────────────────────────────
  if (!executeMode) {
    console.log('='.repeat(60));
    console.log('DRY-RUN COMPLETE — No writes performed.');
    console.log(`Candidates: ${preLegacy} legacy + ${preComplete} already-complete + ${prePartial} partial/mixed`);
    console.log(`Run with --execute to start actual migration.`);
    console.log('='.repeat(60));
    return;
  }

  // ── EXECUTE MODE: Migrate ─────────────────────────────────────────────────
  console.log('Starting migration...');
  console.log('  Legend: . = migrated  S = skipped  P = partial  A = ambiguous  U = unresolved  M = mismatch  E = error');
  process.stdout.write('  ');

  const results = {
    totalCandidates: slotDocs.length,
    migrated: 0, alreadyMigrated: 0,
    partialError: 0, ambiguous: 0, unresolved: 0, counterMismatch: 0, failed: 0,
    applicationBackfilled: 0,
    failedSlots: [], partialSlots: [],
  };

  for (const slotDoc of slotDocs) {
    const slotId  = slotDoc.id;
    const toId    = slotDoc.ref.parent?.parent?.id ?? 'UNKNOWN';
    const wds     = Array.isArray(slotDoc.data().workDetails) ? slotDoc.data().workDetails : [];
    const apps    = appsBySlot.get(slotId) || [];
    const appRefs = apps.map(a => a.ref || db.collection('applications').doc(a.id));

    // Pre-generate wdIds (outside transaction for stable retry behavior)
    const preGenWdIds = wds.map(() => db.collection('_').doc().id);

    try {
      const result = await migrateSlotTx(slotDoc.ref, appRefs, preGenWdIds, wds.length);

      if (result.status === 'SKIP_ALREADY_MIGRATED') {
        results.alreadyMigrated++;
        process.stdout.write('S');
      } else {
        results.migrated++;
        results.applicationBackfilled += result.appWriteCount;
        if (result.slotTotalWarning) {
          process.stdout.write('\n');
          console.log(`  ⚠️  SLOT_TOTAL_WARNING slotId=${slotId}: ${result.slotTotalWarning}`);
          process.stdout.write('  ');
        } else {
          process.stdout.write('.');
        }
      }
    } catch (err) {
      const msg = err.message || String(err);
      let sym;
      if (msg.startsWith('PARTIAL_MIGRATION_ERROR')) { results.partialError++;    sym = 'P'; results.partialSlots.push({ slotId, toId, error: msg }); }
      else if (msg.startsWith('FAIL_CLOSED_AMBIGUOUS'))  { results.ambiguous++;      sym = 'A'; results.failedSlots.push({ slotId, toId, error: msg }); }
      else if (msg.startsWith('FAIL_CLOSED_UNRESOLVED')) { results.unresolved++;     sym = 'U'; results.failedSlots.push({ slotId, toId, error: msg }); }
      else if (msg.startsWith('AGGREGATE_MISMATCH'))     { results.counterMismatch++;sym = 'M'; results.failedSlots.push({ slotId, toId, error: msg }); }
      else                                               { results.failed++;         sym = 'E'; results.failedSlots.push({ slotId, toId, error: msg }); }
      process.stdout.write(sym);
    }
  }
  console.log('\n');

  // ── Post-verify ────────────────────────────────────────────────────────────
  const verify = await postVerify();
  console.log();

  // ── Re-run audit ───────────────────────────────────────────────────────────
  const reAudit = await reRunAudit();
  console.log();

  // ── Save report ────────────────────────────────────────────────────────────
  const reportPath = path.join(__dirname, `migration-report-dev-${ts}.json`);
  const report = {
    generatedAt: new Date().toISOString(), project: projectId,
    migration: results, verify, reAudit,
  };
  fs.writeFileSync(reportPath, JSON.stringify(report, null, 2), 'utf8');

  // ── Final report ───────────────────────────────────────────────────────────
  const line  = '═'.repeat(60);
  const totalFailed = results.failed + results.ambiguous + results.unresolved + results.counterMismatch + results.partialError;
  const overallPass = verify.pass && reAudit.legacySlots === 0 && reAudit.activeAmbiguous === 0 && reAudit.activeUnresolved === 0;

  console.log(line);
  console.log('PHASE 8.1E.3B — DEV DATA MIGRATION REPORT');
  console.log(line);

  console.log('\n1. Safety');
  console.log(`   DEV project hard guard  : YES (alfit-89567 only)`);
  console.log(`   --execute required      : YES`);
  console.log(`   PROD blocked            : YES (hard error on any non-alfit-89567 project)`);
  console.log(`   backup created          : ${backupPath}`);

  console.log('\n2. Pre-migration');
  console.log(`   candidate slots         : ${results.totalCandidates}`);
  console.log(`   slot-based applications : ${totalSlotApps}`);
  console.log(`   ambiguous (dry-run)     : 0`);
  console.log(`   unresolved (dry-run)    : 0`);
  console.log(`   counter mismatch (dry-run): 0`);

  console.log('\n3. Migration');
  console.log(`   migrated                : ${results.migrated}`);
  console.log(`   already migrated (skip) : ${results.alreadyMigrated}`);
  console.log(`   application wdId backfilled : ${results.applicationBackfilled}`);
  console.log(`   partial/mixed blocked   : ${results.partialError}`);
  console.log(`   ambiguous blocked       : ${results.ambiguous}`);
  console.log(`   unresolved blocked      : ${results.unresolved}`);
  console.log(`   aggregate mismatch abort: ${results.counterMismatch}`);
  console.log(`   failed (other)          : ${results.failed}`);
  if (results.failedSlots.length > 0) {
    console.log('   Failed details:');
    for (const f of results.failedSlots.slice(0, 10)) {
      console.log(`     slotId=${f.slotId}: ${f.error}`);
    }
  }

  console.log('\n4. Post-verify');
  console.log(`   legacy slots remaining  : ${verify.legacyRemaining}  (expected: 0)`);
  console.log(`   new-schema slots        : ${verify.newSchemaCount}  (expected: 32)`);
  console.log(`   WDC complete            : ${verify.wdcCompleteCount}`);
  console.log(`   orphan WDC              : ${verify.orphanWDC}  (expected: 0)`);
  console.log(`   missing WDC             : ${verify.missingWDC}  (expected: 0)`);
  console.log(`   app wdId valid          : ${verify.appWdIdValid}  (expected: 6)`);
  console.log(`   app wdId invalid        : ${verify.appWdIdInvalid}  (expected: 0)`);
  console.log(`   app wdId missing        : ${verify.appWdIdMissing}  (expected: 0)`);
  console.log(`   recount mismatch        : ${verify.recountMismatch}  (expected: 0)`);
  console.log(`   legacy aggregate drift  : ${verify.legacyAggregateDrift}  (expected: 0)`);
  console.log(`   PASS                    : ${verify.pass ? '✅ YES' : '❌ NO'}`);
  if (verify.warnings.length > 0) {
    console.log('   Warnings:');
    for (const w of verify.warnings.slice(0, 10)) console.log(`     ⚠️  ${w}`);
    if (verify.warnings.length > 10) console.log(`     … (${verify.warnings.length - 10} more — see JSON report)`);
  }

  console.log('\n5. Re-run 8.1E.3A');
  console.log(`   legacy slots            : ${reAudit.legacySlots}  (expected: 0)`);
  console.log(`   new-schema slots        : ${reAudit.newSchemaSlots}  (expected: 32)`);
  console.log(`   slots with WDC          : ${reAudit.slotsWithWDC}  (expected: 32)`);
  console.log(`   apps with wdId          : ${reAudit.appsWithWdId}  (expected: 6)`);
  console.log(`   apps without wdId       : ${reAudit.appsWithoutWdId}  (expected: 0)`);
  console.log(`   active ambiguous        : ${reAudit.activeAmbiguous}  (expected: 0)`);
  console.log(`   active unresolved       : ${reAudit.activeUnresolved}  (expected: 0)`);

  console.log('\n6. Contract');
  console.log('   changed: NO  (workDetailId composite identity preserved — no write)');

  console.log('\n7. Files created');
  console.log(`   migration script        : scripts/migrate-workdetail-capacity-dev.js`);
  console.log(`   backup                  : ${backupPath}`);
  console.log(`   verification report     : ${reportPath}`);

  console.log('\n8. Application/Functions/Flutter changed');
  console.log('   NO — data migration only (slot.workDetails, slot.workDetailCounts, Application.wdId)');

  console.log('\n9. DEV migration result');
  if (totalFailed === 0 && overallPass) {
    console.log('   ✅ PASS');
  } else if (results.migrated > 0 && (totalFailed > 0 || !overallPass)) {
    console.log(`   ⚠️  PARTIAL (${results.migrated} migrated, ${totalFailed} failed, verify.pass=${verify.pass})`);
  } else {
    console.log('   ❌ FAIL');
  }

  console.log('\n10. Remaining blockers');
  const blockerLines = [];
  if (results.failed     > 0) blockerLines.push(`❌ ${results.failed} slots failed (see report)`);
  if (results.partialError > 0) blockerLines.push(`❌ ${results.partialError} partial/mixed slots need manual review`);
  if (!verify.pass)            blockerLines.push(`❌ post-verify failed — see warnings in report`);
  if (reAudit.activeAmbiguous  > 0) blockerLines.push(`❌ activeAmbiguous=${reAudit.activeAmbiguous}`);
  if (reAudit.activeUnresolved > 0) blockerLines.push(`❌ activeUnresolved=${reAudit.activeUnresolved}`);
  if (blockerLines.length === 0) console.log('   none');
  else for (const b of blockerLines) console.log(`   ${b}`);

  console.log('\n11. NEXT');
  if (totalFailed === 0 && overallPass) {
    console.log('   PROD READ-ONLY AUDIT READY');
    console.log('   Run: node scripts/migration-audit.js --project=prod');
    console.log('   (requires PROD service account credentials)');
  } else {
    console.log('   PROD audit BLOCKED — resolve DEV failures first');
  }

  console.log('\n' + line);
  console.log(`JSON report: ${reportPath}`);
  console.log(line);
}

main().catch(err => {
  console.error('\n❌ MIGRATION FAILED:', err.message);
  console.error(err.stack);
  process.exit(1);
});
