#!/usr/bin/env node
/**
 * [CORRECTION-DEV-CONTRACT-STORAGE-ORPHAN-CLEANUP §25 · §26]
 *
 * fixture cleanup 이 이제 **끝까지** 작동하는지 실제로 태워 본다.
 *
 *   계약 artifact 생성  (lt-contract-dual-signature-runtime 이 만든 진짜 계약)
 *   → removeScenario    (patch 한 그 코드)
 *   → Firestore 제거
 *   → Storage artifact 제거      ← 예전에는 여기가 조용히 실패했다
 *   → 한 번 더 실행해도 오류 없음 (멱등)
 *
 * 선행:
 *   node scripts/lt-contract-dual-signature-runtime.js --project alfit-89567 --execute
 *
 * 실행:
 *   node scripts/pre0-fixture-cleanup-probe.js --project alfit-89567
 *   node scripts/pre0-fixture-cleanup-probe.js --project alfit-89567 --execute
 */
'use strict';

const EXPECTED_DEV_PROJECT = 'alfit-89567';
const argv = process.argv.slice(2);
const projectId = (() => {
  const i = argv.indexOf('--project');
  return i >= 0 ? argv[i + 1] : null;
})();
if (projectId !== EXPECTED_DEV_PROJECT) {
  console.error(`DEV 전용입니다. --project ${EXPECTED_DEV_PROJECT}`);
  process.exit(2);
}
const EXECUTE = argv.includes('--execute');

const fs = require('fs');
const path = require('path');
const {db, devBucket} = require('./r7-fixture-lib');
const {removeScenario} = require('./r7-fixture-cleanup');

const BIZ = 'fLmSOHVKUwmBHcbwQE0I';
const ADMIN = 'BErRdiWP1xbgyoTovxwAPNEsuD72';
const STATE = path.join(__dirname, '.lt-contract-runtime-state.json');

const log = (...a) => console.log(...a);
const head = (s) => log(`\n${'─'.repeat(74)}\n${s}\n${'─'.repeat(74)}`);
const results = [];
const check = (label, ok, detail) => {
  results.push({label, ok});
  log(`${ok ? 'PASS' : 'FAIL'}  ${label}${detail ? `\n        ${detail}` : ''}`);
};

async function storageCount(contractId) {
  const [files] = await devBucket().getFiles({prefix: `contracts/${contractId}/`});
  return files.length;
}

async function main() {
  if (!fs.existsSync(STATE)) {
    console.error('선행 필요: lt-contract-dual-signature-runtime --execute');
    process.exit(2);
  }
  const st = JSON.parse(fs.readFileSync(STATE, 'utf8'));
  if (!st.contractId) { console.error('state 에 contractId 가 없습니다.'); process.exit(2); }

  const bucket = devBucket();
  log(`\nproject ${projectId}   bucket ${bucket.name}`);
  log(`probe 대상 계약 ${st.contractId}`);

  head('BEFORE');
  const docBefore = await db.collection('employment_contracts').doc(st.contractId).get();
  const fileBefore = await storageCount(st.contractId);
  log(`   Firestore 계약 문서 ${docBefore.exists ? '있음' : '없음'} (status=${docBefore.data()?.status})`);
  log(`   Storage artifact ${fileBefore}건`);
  check('probe 전제 — 계약과 artifact 가 실재한다',
      docBefore.exists && fileBefore > 0, `${fileBefore}건`);

  if (!EXECUTE) {
    head('DRY RUN');
    const n = await removeScenario(
        {contractId: st.contractId, applicationId: st.applicationId, toId: st.toId},
        {execute: false, adminUid: ADMIN, businessId: BIZ});
    log(`   ${JSON.stringify({...n, storageErrors: n.storageErrors.length})}`);
    log('   아무것도 지우지 않았습니다. 실제 실행은 --execute');
    return;
  }

  // ── §25  1회차 ──────────────────────────────────────────────────
  head('§25  fixture cleanup 1회차');
  const first = await removeScenario(
      {contractId: st.contractId, applicationId: st.applicationId, toId: st.toId},
      {execute: true, adminUid: ADMIN, businessId: BIZ});
  log(`   계약 ${first.contracts} · 지원서 ${first.applications} · 공고 ${first.tos}`);
  log(`   Storage  삭제 ${first.storageDeleted} · 이미 없음 ${first.storageMissing} · ` +
    `실패 ${first.storageFailed}`);
  first.storageErrors.slice(0, 3).forEach((e) => log(`     · ${e}`));

  check('§25 Storage artifact 가 실제로 삭제됐다', first.storageDeleted > 0,
      `${first.storageDeleted}건`);
  check('§10 Storage 삭제 실패 0', first.storageFailed === 0);

  const docAfter = await db.collection('employment_contracts').doc(st.contractId).get();
  const fileAfter = await storageCount(st.contractId);
  check('§25 Firestore 계약 문서가 사라졌다', !docAfter.exists);
  check('§25 Storage artifact 가 0건이다', fileAfter === 0, `${fileAfter}건`);

  // ── §26  2회차 — 멱등 ───────────────────────────────────────────
  head('§26  같은 cleanup 2회차 (멱등)');
  let threw = null;
  let second;
  try {
    second = await removeScenario(
        {contractId: st.contractId, applicationId: st.applicationId, toId: st.toId},
        {execute: true, adminUid: ADMIN, businessId: BIZ});
  } catch (e) { threw = e && e.message ? e.message : String(e); }
  check('§26 두 번째 실행이 예외로 죽지 않는다', threw === null, threw || '');
  if (second) {
    log(`   ${JSON.stringify({
      contracts: second.contracts, applications: second.applications,
      tos: second.tos, storageDeleted: second.storageDeleted,
      storageMissing: second.storageMissing, storageFailed: second.storageFailed,
    })}`);
    check('§26 두 번째는 지울 것이 없다',
        second.contracts === 0 && second.storageDeleted === 0 &&
        second.storageFailed === 0);
  }

  // ── 정리 흔적 — 다른 계약은 건드리지 않았는가 ───────────────────
  head('§12  범위');
  const all = await db.collection('employment_contracts').get();
  const [files] = await bucket.getFiles({prefix: 'contracts/'});
  log(`   employment_contracts ${all.size}건 · contracts/ object ${files.length}건`);

  head('요약');
  const failed = results.filter((r) => !r.ok);
  log(`   ${results.length - failed.length}/${results.length} PASS`);
  failed.forEach((r) => log(`     · ${r.label}`));
  if (failed.length > 0) process.exitCode = 1;
  if (fs.existsSync(STATE)) fs.unlinkSync(STATE);
}

main().then(() => process.exit(process.exitCode || 0)).catch((e) => {
  console.error('\n실패:', e && e.message ? e.message : e);
  process.exit(1);
});
