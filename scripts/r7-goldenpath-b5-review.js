/**
 * [R7-GOLDEN-PATH-DEV-E2E] Step B5 — 관리자 서류 검토.
 *
 *   Step C(확정)가 FAILED_PRECONDITION "신분증 확인이 필요합니다" 로 막혔다.
 *   이것은 결함이 아니라 **제품이 요구하는 실제 단계**다(확정 전 gate).
 *   §27 에 따라 Firestore 직접 write 가 아니라 canonical callable 로 통과한다.
 */
'use strict';
const fs = require('fs');
const lib = require('./r7-fixture-lib');
const unwrap = (r) => (r && (r.result ?? r.data)) ?? r;

(async () => {
  const L = JSON.parse(fs.readFileSync('.goldenpath.json', 'utf8'));
  const base = {applicationId: L.applicationId, businessId: L.businessId};

  const before = unwrap(await lib.callAs(L.adminUid,
    'callableGetApplicantDocumentReview', base));
  console.log('=== 검토 전 ===');
  console.log('  canReviewDocuments:', before.canReviewDocuments);
  console.log('  consentBlock      :', before.consentBlock ?? '(없음)');
  console.log('  versions          :', JSON.stringify(before.versions));
  console.log('  readiness         : ready =', before.readiness.ready,
    '| id =', before.readiness.idDecision,
    '| bank =', before.readiness.bankDecision);
  console.log('  이유              :', before.readiness.reason ?? '(없음)');

  if (before.consentBlock) {
    throw new Error('동의 block 상태 — 검토 진행 불가: ' + before.consentBlock);
  }

  for (const t of ['ID', 'BANKBOOK']) {
    console.log(`\n— callableReviewApplicantDocument (${t})`);
    await lib.callAs(L.adminUid, 'callableReviewApplicantDocument', {
      ...base,
      targetUid: before.workerUid,
      documentType: t,
      decision: 'REVIEWED_OK',
      expectedVersion: t === 'ID' ?
        before.versions.id : before.versions.bankbook,
      expectedAccountVersion: before.versions.account,
    });
    console.log('  OK');
  }

  const after = unwrap(await lib.callAs(L.adminUid,
    'callableGetApplicantDocumentReview', base));
  console.log('\n=== 검토 후 ===');
  console.log('  readiness: ready =', after.readiness.ready,
    '| id =', after.readiness.idDecision,
    '| bank =', after.readiness.bankDecision);
  console.log('  이유     :', after.readiness.reason ?? '(없음)');

  L.docReviewReady = after.readiness.ready;
  fs.writeFileSync('.goldenpath.json', JSON.stringify(L, null, 2));
  process.exit(after.readiness.ready ? 0 : 1);
})().catch((e) => { console.error('실패:', e.message); process.exit(1); });
