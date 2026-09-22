#!/usr/bin/env node
/**
 * [R7-PRE1A.1] personNo 백필 — 사업장별로 기존 관계에 번호를 붙인다.
 *
 * 번호는 앞으로 지원·초대 시점에 CF 가 준다. 이 스크립트는 그 기능 이전에
 * 생긴 관계에만 쓴다.
 *
 * 순서가 중요하다. 조회 순서대로 주면 실행할 때마다 다른 번호가 나가고,
 * 그러면 어제 내보낸 Excel 과 오늘 내보낸 Excel 의 같은 사람이 다른 번호가
 * 된다. **그 사업장과 관계가 생긴 순서**(가장 이른 지원서 생성 시각)로 준다 —
 * 언제 돌려도 같은 결과가 나오고, 사람이 보기에도 자연스럽다.
 *
 * 이미 번호가 있는 사람은 건드리지 않는다. 번호는 재사용하지 않는다.
 *
 *   node scripts/backfill-person-no-dev.js --project alfit-89567
 *   node scripts/backfill-person-no-dev.js --project alfit-89567 --execute
 */
'use strict';

const EXPECTED_DEV_PROJECT = 'alfit-89567';
const argv = process.argv.slice(2);
const projectId = (() => {
  const i = argv.indexOf('--project');
  return i >= 0 ? argv[i + 1] : null;
})();
const EXECUTE = argv.includes('--execute');

if (projectId !== EXPECTED_DEV_PROJECT) {
  console.error(`이 스크립트는 DEV 전용입니다. --project ${EXPECTED_DEV_PROJECT}`);
  process.exit(2);
}

const {db, admin} = require('./r7-fixture-lib');

const log = (...a) => console.log(...a);

const msOf = (v) => {
  if (v == null) return null;
  if (typeof v === 'number') return v;
  if (typeof v.toMillis === 'function') return v.toMillis();
  return null;
};

async function main() {
  log('R7-PRE1A.1 personNo 백필');
  log(`  project : ${projectId}`);
  log(`  mode    : ${EXECUTE ? 'execute' : 'dry-run (--execute 로 실제 반영)'}`);

  const bizSnap = await db.collection('businesses').get();
  log(`  사업장  : ${bizSnap.size}개\n`);

  let assignedTotal = 0;
  let skippedTotal = 0;

  for (const bizDoc of bizSnap.docs) {
    const bizId = bizDoc.id;
    const bizName = bizDoc.data().name || '(이름 없음)';

    // 이 사업장의 모든 관계 — status 를 가리지 않는다.
    //   지나간 지원서도 관계였다. 그 사람이 다시 지원하면 같은 번호여야 한다.
    const apps = await db.collection('applications')
        .where('businessId', '==', bizId).get();
    if (apps.empty) continue;

    // uid → 가장 이른 관계 시각
    const firstSeen = new Map();
    for (const d of apps.docs) {
      const a = d.data();
      const uid = a.uid;
      if (!uid) continue;
      const t = msOf(a.createdAt) ?? msOf(a.appliedAt) ??
          msOf(a.invitedAt) ?? msOf(a.workDate) ?? Number.MAX_SAFE_INTEGER;
      const prev = firstSeen.get(uid);
      if (prev == null || t < prev) firstSeen.set(uid, t);
    }

    // 같은 시각이면 uid 로 갈라 결정적으로 만든다.
    const ordered = [...firstSeen.entries()]
        .sort((a, b) => (a[1] - b[1]) || a[0].localeCompare(b[0]))
        .map(([uid]) => uid);

    const personsRef = db.collection('businesses').doc(bizId).collection('persons');
    const existing = await personsRef.get();
    const have = new Map();
    existing.docs.forEach((d) => {
      const n = d.data().personNo;
      if (typeof n === 'number') have.set(d.id, n);
    });

    const missing = ordered.filter((uid) => !have.has(uid));
    let next = have.size > 0 ? Math.max(...have.values()) : 0;
    const counterRef = db.collection('businesses').doc(bizId)
        .collection('counters').doc('personNo');
    const counterSnap = await counterRef.get();
    const counterNext = counterSnap.data()?.next;
    if (typeof counterNext === 'number' && counterNext > next) next = counterNext;

    log(`── ${bizName} (${bizId.slice(0, 10)})`);
    log(`   관계 ${ordered.length}명 · 이미 번호 있음 ${have.size}명 · 부여 대상 ${missing.length}명`);

    if (missing.length === 0) { skippedTotal += have.size; continue; }

    const batch = EXECUTE ? db.batch() : null;
    for (const uid of missing) {
      next += 1;
      log(`     W-${String(next).padStart(3, '0')}  ${uid.slice(0, 12)}…`);
      if (batch) {
        batch.set(personsRef.doc(uid), {
          uid,
          businessId: bizId,
          personNo: next,
          assignedAt: admin.firestore.FieldValue.serverTimestamp(),
          backfilled: true,
        });
      }
      assignedTotal++;
    }
    if (batch) {
      batch.set(counterRef, {next}, {merge: true});
      await batch.commit();
    }
    skippedTotal += have.size;
  }

  log(`\n부여 ${assignedTotal}명 · 유지 ${skippedTotal}명`);
  if (!EXECUTE) log('dry-run 이었다 — 아무것도 쓰지 않았다.');
  process.exit(0);
}

main().catch((e) => {
  console.error('\n실패:', e && e.message ? e.message : e);
  process.exit(1);
});
