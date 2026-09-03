#!/usr/bin/env node
/**
 * PHASE 8.1E.3A — WORKDETAIL CAPACITY MIGRATION DRY-RUN AUDIT
 *
 * READ ONLY MIGRATION AUDIT — NO FIRESTORE WRITES
 *
 * Usage:
 *   node scripts/migration-audit.js [--project=dev]
 *
 * Default: dev (alfit-89567)
 * PROD: requires --project=prod + prod service account at
 *       scripts/alfit-prod-adminsdk.json  OR  GOOGLE_APPLICATION_CREDENTIALS env
 */

'use strict';

const path = require('path');
const fs   = require('fs');

// ─── SAFETY BANNER ───────────────────────────────────────────────────────────
console.log('='.repeat(60));
console.log('READ ONLY MIGRATION AUDIT');
console.log('NO FIRESTORE WRITES');
console.log('='.repeat(60));
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
const projectAlias = (cliArgs['project'] || 'dev').toLowerCase();

const PROJECT_IDS = { dev: 'alfit-89567', prod: 'alfit-prod' };
if (!PROJECT_IDS[projectAlias]) {
  console.error(`Unknown --project="${projectAlias}". Use: dev | prod`);
  process.exit(1);
}
const projectId = PROJECT_IDS[projectAlias];
console.log(`Project alias : ${projectAlias}`);
console.log(`Project ID    : ${projectId}`);
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

let credential;
if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  credential = admin.credential.applicationDefault();
  console.log('Credentials   : GOOGLE_APPLICATION_CREDENTIALS env');
} else if (fs.existsSync(SA_PATHS[projectAlias])) {
  credential = admin.credential.cert(SA_PATHS[projectAlias]);
  console.log(`Credentials   : ${SA_PATHS[projectAlias]}`);
} else {
  console.error(`Service account not found: ${SA_PATHS[projectAlias]}`);
  console.error('Set GOOGLE_APPLICATION_CREDENTIALS or place the key at the expected path.');
  process.exit(1);
}

admin.initializeApp({ credential, projectId });
const db = admin.firestore();

// ─── Helpers ─────────────────────────────────────────────────────────────────

/** Paginated Firestore read. Returns all docs matching query. */
async function fetchAll(query, label) {
  const docs = [];
  let cursor = null;
  let page = 0;
  while (true) {
    let q = cursor ? query.startAfter(cursor).limit(500) : query.limit(500);
    const snap = await q.get();
    if (snap.empty) break;
    docs.push(...snap.docs);
    if (snap.docs.length < 500) break;
    cursor = snap.docs[snap.docs.length - 1];
    page++;
    if (label) process.stdout.write(`\r  ${label}: ${docs.length} loaded (page ${page + 1})...`);
  }
  if (label) process.stdout.write(`\r  ${label}: ${docs.length} loaded           \n`);
  return docs;
}

function buildCompositeId(workType, startTime, endTime) {
  if (!workType || !startTime || !endTime) return null;
  return `${workType}_${startTime}_${endTime}`;
}

/**
 * Resolve which WD index an application maps to.
 * Priority chain (Phase 8.1E.2B semantics):
 *  P1. app.wdId direct match
 *  P2. composite workDetailId (workType_start_end)
 *  P3. selectedWorkType + startTime + endTime triple
 *  P4. unique workType (exactly 1 WD of that type)
 *  P5. ambiguous / unresolved
 *
 * Returns { resolvedWdId, resolvedWdIdx, method, ambiguous, orphan }
 *  resolvedWdId  : real wdId if the WD has one, else null
 *  resolvedWdIdx : index in wds array (-1 if not found)
 */
function resolveWd(app, wds) {
  // P1: direct wdId
  if (app.wdId) {
    const idx = wds.findIndex(wd => wd.wdId === app.wdId);
    if (idx >= 0)
      return { resolvedWdId: app.wdId, resolvedWdIdx: idx, method: 'BY_WD_ID', ambiguous: false, orphan: false };
    return { resolvedWdId: app.wdId, resolvedWdIdx: -1, method: 'BY_WD_ID', ambiguous: false, orphan: true };
  }

  const wt    = app.selectedWorkType;
  const start = app.startTime;
  const end   = app.endTime;

  // P2: composite workDetailId
  if (app.workDetailId) {
    const idx = wds.findIndex(wd => {
      const c = buildCompositeId(wd.workType, wd.startTime, wd.endTime);
      return c !== null && c === app.workDetailId;
    });
    if (idx >= 0)
      return { resolvedWdId: wds[idx].wdId || null, resolvedWdIdx: idx, method: 'BY_COMPOSITE', ambiguous: false, orphan: false };
    // composite present but no match → fall through (not ambiguous; may resolve via P3/P4)
  }

  // P3: triple exact match
  if (wt && start && end) {
    const hits = [];
    for (let i = 0; i < wds.length; i++) {
      if (wds[i].workType === wt && wds[i].startTime === start && wds[i].endTime === end) hits.push(i);
    }
    if (hits.length === 1)
      return { resolvedWdId: wds[hits[0]].wdId || null, resolvedWdIdx: hits[0], method: 'BY_TIME_TRIPLE', ambiguous: false, orphan: false };
    if (hits.length > 1)
      return { resolvedWdId: null, resolvedWdIdx: -1, method: 'AMBIGUOUS_TRIPLE', ambiguous: true, orphan: false };
  }

  // P4: unique workType
  if (wt) {
    const hits = [];
    for (let i = 0; i < wds.length; i++) {
      if (wds[i].workType === wt) hits.push(i);
    }
    if (hits.length === 1)
      return { resolvedWdId: wds[hits[0]].wdId || null, resolvedWdIdx: hits[0], method: 'BY_UNIQUE_WORKTYPE', ambiguous: false, orphan: false };
    if (hits.length > 1)
      return { resolvedWdId: null, resolvedWdIdx: -1, method: 'AMBIGUOUS_WORKTYPE', ambiguous: true, orphan: false };
  }

  return { resolvedWdId: null, resolvedWdIdx: -1, method: 'UNRESOLVED', ambiguous: false, orphan: false };
}

const ACTIVE_STATUSES   = new Set(['PENDING', 'INVITED', 'CONTRACT_PENDING', 'CONFIRMED']);
const PENDING_STATUSES  = new Set(['PENDING', 'INVITED']);
const CONFIRMED_STATUSES_SET = new Set(['CONFIRMED', 'CONTRACT_PENDING']);

// ─── Main ────────────────────────────────────────────────────────────────────
async function main() {

  // 1. Load slots
  console.log('Step 1/4 — Loading all slots (collection group)...');
  let slotDocs;
  try {
    slotDocs = await fetchAll(db.collectionGroup('slots'), 'slots');
  } catch (cgErr) {
    console.warn(`  collectionGroup failed (${cgErr.message}), falling back to per-TO query...`);
    const toDocs = await fetchAll(db.collection('tos'), 'tos');
    slotDocs = [];
    for (const toDoc of toDocs) {
      const s = await fetchAll(db.collection('tos').doc(toDoc.id).collection('slots'));
      slotDocs.push(...s);
    }
    console.log(`  slots (via per-TO): ${slotDocs.length} loaded`);
  }

  // 2. Load all applications (fetch all, filter slot-based in code)
  console.log('Step 2/4 — Loading all applications...');
  const allAppDocs = await fetchAll(db.collection('applications'), 'applications');

  // Build slotId → apps map
  const appsBySlot  = new Map();
  const statusCounts = {};
  let totalApps = 0, withWdId = 0, withoutWdId = 0;
  let withCompositeId = 0, withStartEnd = 0, withoutStartEnd = 0;

  for (const doc of allAppDocs) {
    const d = doc.data();
    if (!d.slotId) continue; // skip non-slot applications
    totalApps++;
    const s = d.status || 'UNKNOWN';
    statusCounts[s] = (statusCounts[s] || 0) + 1;
    if (d.wdId)               withWdId++;    else withoutWdId++;
    if (d.workDetailId)       withCompositeId++;
    if (d.startTime && d.endTime) withStartEnd++; else withoutStartEnd++;
    if (!appsBySlot.has(d.slotId)) appsBySlot.set(d.slotId, []);
    appsBySlot.get(d.slotId).push({ id: doc.id, ...d });
  }

  // 3. Load contracts
  console.log('Step 3/4 — Loading employment contracts...');
  let contractDocs = [];
  try {
    contractDocs = await fetchAll(db.collection('employment_contracts'), 'contracts');
  } catch (e) {
    console.warn(`  employment_contracts fetch failed: ${e.message}`);
  }

  // 4. Analysis
  console.log('Step 4/4 — Running analysis...');
  console.log();

  // ── Slot/resolution counters ─────────────────────────────────────────────
  let totalSlots = 0, legacySlots = 0, newSchemaSlots = 0;
  let slotsWithWDC = 0, slotsWithoutWDC = 0;
  let slotsMultipleWDs = 0, slotsSameWorkTypeMulti = 0;

  let resolvedByWdId = 0, resolvedByComposite = 0;
  let resolvedByTimeTriple = 0, resolvedByUniqueWorkType = 0;
  let ambiguousApps = 0, unresolvedApps = 0;
  let orphanAppWdIds = 0;

  let activeTotal = 0, activeResolved = 0, activeAmbiguous = 0, activeUnresolved = 0;

  let typeA = 0, typeB = 0, typeC = 0, typeD = 0;
  let legacyMatchSlots = 0, legacyDriftSlots = 0;
  let missingLegacyCounterEntries = 0, invalidCounterEntries = 0;
  let newSchemaMatch = 0, newSchemaDrift = 0;
  let missingWDCEntries = 0, orphanWDCEntries = 0;

  let backfillableCount = 0;

  const multiTimeSlotList = [];
  const driftDetails      = [];   // capped at 50
  const blockers          = [];

  // ── Per-slot loop ─────────────────────────────────────────────────────────
  for (const slotDoc of slotDocs) {
    totalSlots++;
    const sd     = slotDoc.data();
    const slotId = slotDoc.id;
    const toId   = (slotDoc.ref.parent && slotDoc.ref.parent.parent)
                     ? slotDoc.ref.parent.parent.id
                     : 'UNKNOWN';

    const wds         = Array.isArray(sd.workDetails) ? sd.workDetails : [];
    const isNewSchema = wds.some(wd => typeof wd.wdId === 'string' && wd.wdId.length > 0);
    const wdc         = (sd.workDetailCounts && typeof sd.workDetailCounts === 'object')
                          ? sd.workDetailCounts : null;
    const wdIdSet     = new Set(wds.filter(wd => wd.wdId).map(wd => wd.wdId));

    if (isNewSchema) newSchemaSlots++; else legacySlots++;
    if (wdc) slotsWithWDC++; else slotsWithoutWDC++;
    if (wds.length > 1) slotsMultipleWDs++;

    // same workType / multi-time check
    const wtList        = wds.map(wd => wd.workType).filter(Boolean);
    const uniqueWTSet   = new Set(wtList);
    if (wtList.length > uniqueWTSet.size) {
      slotsSameWorkTypeMulti++;
      multiTimeSlotList.push({ slotId, toId, workTypes: wtList });
    }

    // Orphan / missing WDC for new-schema
    if (isNewSchema) {
      for (const wdId of wdIdSet) {
        if (!wdc || !wdc[wdId]) missingWDCEntries++;
      }
      if (wdc) {
        for (const key of Object.keys(wdc)) {
          if (!wdIdSet.has(key)) orphanWDCEntries++;
        }
      }
    }

    // Per-slot simulation
    // simCounts key: real wdId if available, else "DRY_wd_N" (dry-run temp ID)
    const simCounts  = {};  // key → { pending, confirmed }
    const workTypeSim = {}; // workType → { pending, confirmed }

    let slotActiveAmbiguous = 0, slotActiveUnresolved = 0;
    let slotAllResolved = true;

    const apps = appsBySlot.get(slotId) || [];

    for (const app of apps) {
      const status      = app.status || 'UNKNOWN';
      const isActive    = ACTIVE_STATUSES.has(status);
      const isPending   = PENDING_STATUSES.has(status);
      const isConfirmed = CONFIRMED_STATUSES_SET.has(status);

      if (isActive) activeTotal++;

      // Check orphan app.wdId (new-schema only)
      if (app.wdId && isNewSchema && !wdIdSet.has(app.wdId)) orphanAppWdIds++;

      const res       = resolveWd(app, wds);
      const isAmbig   = res.ambiguous;
      const isOrphan  = res.orphan;
      const isResolved = !isAmbig && !isOrphan && res.resolvedWdIdx >= 0;

      // Count resolution
      if (isResolved) {
        switch (res.method) {
          case 'BY_WD_ID':           resolvedByWdId++;           break;
          case 'BY_COMPOSITE':        resolvedByComposite++;      backfillableCount++; break;
          case 'BY_TIME_TRIPLE':      resolvedByTimeTriple++;     backfillableCount++; break;
          case 'BY_UNIQUE_WORKTYPE':  resolvedByUniqueWorkType++; backfillableCount++; break;
        }
        if (isActive) activeResolved++;
      } else if (isAmbig) {
        ambiguousApps++;
        slotAllResolved = false;
        if (isActive) { activeAmbiguous++; slotActiveAmbiguous++; }
      } else {
        // unresolved or orphan
        unresolvedApps++;
        slotAllResolved = false;
        if (isActive) { activeUnresolved++; slotActiveUnresolved++; }
      }

      // Build sim key (real wdId or dry-run temp)
      const simKey = res.resolvedWdId != null
        ? res.resolvedWdId
        : (res.resolvedWdIdx >= 0 ? `DRY_wd_${res.resolvedWdIdx}` : null);

      if (simKey) {
        if (!simCounts[simKey]) simCounts[simKey] = { pending: 0, confirmed: 0 };
        if (isPending)   simCounts[simKey].pending++;
        if (isConfirmed) simCounts[simKey].confirmed++;
      }

      const wt = app.selectedWorkType;
      if (wt) {
        if (!workTypeSim[wt]) workTypeSim[wt] = { pending: 0, confirmed: 0 };
        if (isPending)   workTypeSim[wt].pending++;
        if (isConfirmed) workTypeSim[wt].confirmed++;
      }
    }

    // ── Migration classification ──────────────────────────────────────────
    if (apps.length === 0) {
      typeD++;
    } else if (slotActiveAmbiguous > 0 || slotActiveUnresolved > 0) {
      typeC++;
      blockers.push({ slotId, toId, activeAmbiguous: slotActiveAmbiguous, activeUnresolved: slotActiveUnresolved });
    } else {
      // Check legacy drift
      const existingWTC = sd.workTypeCounts || {};
      let hasDrift = false;
      for (const [wt, sim] of Object.entries(workTypeSim)) {
        const ex = existingWTC[wt] || {};
        if ((ex.pendingCount || 0) !== sim.pending || (ex.confirmedCount || 0) !== sim.confirmed) {
          hasDrift = true; break;
        }
      }
      if (slotAllResolved && !hasDrift) typeA++;
      else typeB++;
    }

    // ── Legacy drift comparison ───────────────────────────────────────────
    if (!isNewSchema) {
      const existingWTC = sd.workTypeCounts || {};
      let slotDrifted = false;

      for (const wt of uniqueWTSet) {
        if (!existingWTC[wt]) missingLegacyCounterEntries++;
      }
      for (const [wt, ex] of Object.entries(existingWTC)) {
        if ((ex.pendingCount || 0) < 0 || (ex.confirmedCount || 0) < 0) invalidCounterEntries++;
      }
      for (const [wt, sim] of Object.entries(workTypeSim)) {
        const ex = existingWTC[wt] || {};
        const ep = ex.pendingCount   || 0;
        const ec = ex.confirmedCount || 0;
        if (ep !== sim.pending || ec !== sim.confirmed) {
          slotDrifted = true;
          if (driftDetails.length < 50) {
            driftDetails.push({
              slotId, toId, workType: wt, schema: 'LEGACY',
              existingPending: ep,    simulatedPending: sim.pending,    pendingDelta:   sim.pending   - ep,
              existingConfirmed: ec,  simulatedConfirmed: sim.confirmed, confirmedDelta: sim.confirmed - ec,
            });
          }
        }
      }
      if (slotDrifted) legacyDriftSlots++; else legacyMatchSlots++;
    }

    // ── New-schema WDC validation ─────────────────────────────────────────
    if (isNewSchema && wdc) {
      for (const [wdId, count] of Object.entries(wdc)) {
        if (!wdIdSet.has(wdId)) continue; // already counted in orphanWDCEntries
        const sim = simCounts[wdId] || { pending: 0, confirmed: 0 };
        const ep  = count.pendingCount   || 0;
        const ec  = count.confirmedCount || 0;
        if (ep !== sim.pending || ec !== sim.confirmed) {
          newSchemaDrift++;
          if (driftDetails.length < 50) {
            driftDetails.push({
              slotId, toId, wdId, schema: 'NEW',
              existingPending: ep,    simulatedPending: sim.pending,    pendingDelta:   sim.pending   - ep,
              existingConfirmed: ec,  simulatedConfirmed: sim.confirmed, confirmedDelta: sim.confirmed - ec,
            });
          }
        } else {
          newSchemaMatch++;
        }
      }
    }
  } // end slot loop

  // ── Contract check ────────────────────────────────────────────────────────
  let contractsUsingCompositeId = 0, contractsUsingUnknownIdentity = 0;
  for (const doc of contractDocs) {
    const d   = doc.data();
    const cid = d.workDetailId;
    if (typeof cid === 'string' && cid.length > 0) {
      contractsUsingCompositeId++;
      if (!cid.includes('_')) contractsUsingUnknownIdentity++;
    }
  }

  // ── Summary calc ─────────────────────────────────────────────────────────
  const resolvedTotal  = resolvedByWdId + resolvedByComposite + resolvedByTimeTriple + resolvedByUniqueWorkType;
  const resolutionRate = totalApps > 0 ? (resolvedTotal / totalApps * 100).toFixed(1) : 'N/A';
  const ambiguityRate  = totalApps > 0 ? (ambiguousApps   / totalApps * 100).toFixed(1) : 'N/A';
  const unresolvedRate = totalApps > 0 ? (unresolvedApps  / totalApps * 100).toFixed(1) : 'N/A';
  const ready          = activeAmbiguous === 0 && activeUnresolved === 0;

  // ── JSON report ───────────────────────────────────────────────────────────
  const report = {
    generatedAt: new Date().toISOString(),
    project: projectAlias, projectId,
    readOnly: true, noFirestoreWrites: true,

    slots: {
      total: totalSlots, legacy: legacySlots, newSchema: newSchemaSlots,
      withWorkDetailCounts: slotsWithWDC, withoutWorkDetailCounts: slotsWithoutWDC,
      withMultipleWorkDetails: slotsMultipleWDs, withSameWorkTypeMultipleTimes: slotsSameWorkTypeMulti,
      multiTimeSlotDetails: multiTimeSlotList,
    },
    applications: {
      total: totalApps, withWdId, withoutWdId,
      withCompositeWorkDetailId: withCompositeId, withStartEnd, withoutStartEnd,
      byStatus: statusCounts,
    },
    resolution: {
      byWdId: resolvedByWdId, byComposite: resolvedByComposite,
      byTimeTriple: resolvedByTimeTriple, byUniqueWorkType: resolvedByUniqueWorkType,
      ambiguous: ambiguousApps, unresolved: unresolvedApps,
      resolutionRate: `${resolutionRate}%`,
      ambiguityRate:  `${ambiguityRate}%`,
      unresolvedRate: `${unresolvedRate}%`,
    },
    active: { total: activeTotal, resolved: activeResolved, ambiguous: activeAmbiguous, unresolved: activeUnresolved },
    counterComparison: {
      legacy:    { matchSlots: legacyMatchSlots, driftSlots: legacyDriftSlots, missingLegacyCounterEntries, invalidCounterEntries },
      newSchema: { match: newSchemaMatch, drift: newSchemaDrift, missingWDCEntries, orphanWDCEntries },
      driftDetails,
    },
    orphans: { orphanWDCEntries, missingWDCEntries, orphanAppWdIds },
    migrationClassification: { typeA_safeDirect: typeA, typeB_safeWithRecount: typeB, typeC_manualReview: typeC, typeD_noApplications: typeD },
    contracts: { total: contractDocs.length, usingCompositeWorkDetailId: contractsUsingCompositeId, usingUnknownIdentity: contractsUsingUnknownIdentity },
    decisionGate: { activeAmbiguous, activeUnresolved, readyForWriteMigration: ready },
    blockers,
    recommendation: {
      applicationWdIdBackfill: 'RECOMMENDED',
      backfillableCount,
      rationale: 'exact resolve 가능 앱에 wdId backfill → resolver P1 직접 사용, identity guard 강화, legacy composite 의존 제거',
      proposedMigrationOrder: [
        '1. slot.workDetails 각 항목에 wdId 생성 (db.collection("_").doc().id — auto-ID)',
        '2. legacy composite → new wdId in-memory mapping (workType_start_end → wdId)',
        '3. Application.wdId backfill (resolve 가능 항목, 상태 무관) — slot wave 와 동시 처리 권장',
        '4. workDetailCounts 초기화 (recount 기반: pending/confirmed per wdId)',
        '5. invariant verify (sim recount == written workDetailCounts)',
        '6. atomic commit (slot + workDetailCounts + app wdId)',
      ],
    },
  };

  const ts      = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const outPath = path.join(__dirname, `migration-audit-${projectAlias}-${ts}.json`);
  fs.writeFileSync(outPath, JSON.stringify(report, null, 2), 'utf8');

  // ── Human-readable output ─────────────────────────────────────────────────
  const line = '═'.repeat(60);
  console.log(line);
  console.log('PHASE 8.1E.3A — MIGRATION DRY-RUN REPORT');
  console.log(line);

  console.log('\n1. Environment');
  console.log(`   DEV inspected : ${projectAlias === 'dev' ? 'YES (alfit-89567)' : 'NO'}`);
  console.log(`   PROD inspected: ${projectAlias === 'prod' ? 'YES (READ ONLY)' : 'NO — LIVE DATA NOT INSPECTED'}`);
  console.log('   READ ONLY verified: YES (see §14)');

  console.log('\n2. Slot inventory');
  console.log(`   total                       : ${totalSlots}`);
  console.log(`   legacy (no wdId)            : ${legacySlots}`);
  console.log(`   new-schema (wdId exists)    : ${newSchemaSlots}`);
  console.log(`   same workType / multi-time  : ${slotsSameWorkTypeMulti}`);
  console.log(`   with workDetailCounts       : ${slotsWithWDC}`);
  console.log(`   without workDetailCounts    : ${slotsWithoutWDC}`);
  if (multiTimeSlotList.length > 0) {
    console.log('   multi-time slot examples (up to 5):');
    for (const s of multiTimeSlotList.slice(0, 5)) {
      console.log(`     slotId=${s.slotId}  workTypes=[${s.workTypes.join(', ')}]`);
    }
    if (multiTimeSlotList.length > 5) console.log(`     … (${multiTimeSlotList.length - 5} more — see JSON report)`);
  }

  console.log('\n3. Application inventory');
  console.log(`   total (slot-based)                          : ${totalApps}`);
  console.log(`   with wdId                                   : ${withWdId}`);
  console.log(`   without wdId                                : ${withoutWdId}`);
  console.log(`   with composite workDetailId                 : ${withCompositeId}`);
  console.log(`   with startTime + endTime                    : ${withStartEnd}`);
  console.log(`   without startTime / endTime                 : ${withoutStartEnd}`);
  console.log(`   active (PENDING/INVITED/CP/CONFIRMED)       : ${activeTotal}`);
  console.log('   Status breakdown:');
  const sortedStatuses = Object.entries(statusCounts).sort(([,a],[,b]) => b - a);
  for (const [s, c] of sortedStatuses) {
    console.log(`     ${s.padEnd(22)}: ${c}`);
  }

  console.log('\n4. Resolution');
  console.log(`   P1 by wdId               : ${resolvedByWdId}`);
  console.log(`   P2 by composite          : ${resolvedByComposite}`);
  console.log(`   P3 by time triple        : ${resolvedByTimeTriple}`);
  console.log(`   P4 by unique workType    : ${resolvedByUniqueWorkType}`);
  console.log(`   ambiguous                : ${ambiguousApps}`);
  console.log(`   unresolved               : ${unresolvedApps}`);
  console.log(`   resolution rate          : ${resolutionRate}%`);
  console.log(`   ambiguity rate           : ${ambiguityRate}%`);
  console.log(`   unresolved rate          : ${unresolvedRate}%`);
  console.log(`   active ambiguous         : ${activeAmbiguous}`);
  console.log(`   active unresolved        : ${activeUnresolved}`);

  console.log('\n5. Counter comparison');
  console.log('   Legacy slots:');
  console.log(`     exact match            : ${legacyMatchSlots}`);
  console.log(`     drift                  : ${legacyDriftSlots}`);
  console.log(`     missing counter entry  : ${missingLegacyCounterEntries}`);
  console.log(`     invalid (negative)     : ${invalidCounterEntries}`);
  console.log('   New-schema slots:');
  console.log(`     WDC match              : ${newSchemaMatch}`);
  console.log(`     WDC drift              : ${newSchemaDrift}`);
  console.log(`     missing WDC entry      : ${missingWDCEntries}`);
  console.log(`     orphan WDC entry       : ${orphanWDCEntries}`);
  if (driftDetails.length > 0) {
    console.log(`   Drift samples (up to 5 of ${driftDetails.length}):`);
    for (const d of driftDetails.slice(0, 5)) {
      const key = d.wdId ? `wdId=${d.wdId}` : `workType=${d.workType}`;
      console.log(`     [${d.schema}] slotId=${d.slotId}  ${key}`);
      console.log(`       pending  : existing=${d.existingPending}  sim=${d.simulatedPending}  Δ=${d.pendingDelta}`);
      console.log(`       confirmed: existing=${d.existingConfirmed}  sim=${d.simulatedConfirmed}  Δ=${d.confirmedDelta}`);
    }
  }

  console.log('\n6. New-schema invariant');
  console.log(`   missing WDC entries  : ${missingWDCEntries}`);
  console.log(`   orphan WDC entries   : ${orphanWDCEntries}`);
  console.log(`   orphan app.wdId      : ${orphanAppWdIds}`);

  console.log('\n7. Migration classification');
  console.log(`   TYPE A — safe direct       : ${typeA}`);
  console.log(`   TYPE B — safe w/ recount   : ${typeB}`);
  console.log(`   TYPE C — manual review     : ${typeC}`);
  console.log(`   TYPE D — no applications   : ${typeD}`);

  console.log('\n8. Application wdId backfill');
  console.log('   recommended         : YES');
  console.log(`   backfillable count  : ${backfillableCount}  (via P2/P3/P4 — already-set P1 excluded)`);

  console.log('\n9. Contract impact');
  console.log(`   total contracts              : ${contractDocs.length}`);
  console.log(`   using composite workDetailId : ${contractsUsingCompositeId}`);
  console.log(`   using unknown identity       : ${contractsUsingUnknownIdentity}`);

  console.log('\n10. Write migration recommendation');
  console.log(`    ${ready ? '✅ READY' : '❌ BLOCKED'}`);
  if (!ready) {
    if (activeAmbiguous  > 0) console.log(`    ❌ activeAmbiguous=${activeAmbiguous}  — manual data review required before write migration`);
    if (activeUnresolved > 0) console.log(`    ❌ activeUnresolved=${activeUnresolved} — manual data review required before write migration`);
  }

  if (blockers.length > 0) {
    console.log(`\n11. Blockers (${blockers.length} slot(s))`);
    for (const b of blockers.slice(0, 20)) {
      console.log(`    slotId=${b.slotId}  toId=${b.toId}  activeAmbiguous=${b.activeAmbiguous}  activeUnresolved=${b.activeUnresolved}`);
    }
    if (blockers.length > 20) console.log(`    … (${blockers.length - 20} more — see JSON report)`);
  } else {
    console.log('\n11. Blockers: none');
  }

  console.log('\n12. Proposed 8.1E.3B migration order');
  for (const step of report.recommendation.proposedMigrationOrder) {
    console.log(`    ${step}`);
  }

  console.log('\n13. Files created/changed');
  console.log('    scripts/migration-audit.js  (NEW — this read-only audit script)');
  console.log(`    ${outPath}  (NEW — JSON report)`);

  console.log('\n14. NO WRITE CONFIRMATION');
  console.log('    ✅ No .set()          calls');
  console.log('    ✅ No .update()       calls');
  console.log('    ✅ No .create()       calls');
  console.log('    ✅ No .delete()       calls');
  console.log('    ✅ No .commit()       calls');
  console.log('    ✅ No runTransaction() write paths');
  console.log('    ✅ Admin SDK read-only usage only');

  console.log('\n' + line);
  console.log('AUDIT COMPLETE');
  console.log(`JSON report: ${outPath}`);
  console.log(line);
}

main().catch(err => {
  console.error('\n❌ AUDIT FAILED:', err.message);
  console.error(err.stack);
  process.exit(1);
});
