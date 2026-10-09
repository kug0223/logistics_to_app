/**
 * [R7-GOLDEN-PATH-DEV-E2E] Step C — 확정 + FULL 확인.
 *   §7 검증도 함께: 확정 **전**에 계약·근태가 만들어지지 않았는가.
 */
'use strict';
const fs = require('fs');
const lib = require('./r7-fixture-lib');
const {db} = lib;
const unwrap = (r) => (r && (r.result ?? r.data)) ?? r;

(async () => {
  const L = JSON.parse(fs.readFileSync('.goldenpath.json', 'utf8'));

  // ── §7: 확정 전에는 약속 truth 가 없어야 한다 ─────────────────
  const cBefore = await db.collection('employment_contracts')
    .where('applicationId', '==', L.applicationId).get();
  const aBefore = await db.collection('attendance')
    .where('applicationId', '==', L.applicationId).get();
  console.log('=== 확정 전 (지원 = 관심) ===');
  console.log('  계약:', cBefore.size, '| 근태:', aBefore.size,
    (cBefore.size === 0 && aBefore.size === 0) ? '(OK)' : '(**약속이 미리 생겼다**)');

  console.log('\n— callableConfirmApplication');
  const res = unwrap(await lib.callAs(L.adminUid, 'callableConfirmApplication', {
    applicationId: L.applicationId,
    businessId: L.businessId,
  }));
  console.log('  응답 키:', Object.keys(res).join(', '));

  const app = (await db.collection('applications').doc(L.applicationId).get())
    .data();
  const to = (await db.collection('tos').doc(L.toId).get()).data();
  const slot = (await db.collection('tos').doc(L.toId)
    .collection('slots').doc(L.slotId).get()).data();
  const wd = (slot.workDetails || []).find((w) => w.wdId === L.wdId) || {};

  console.log('\n=== Step C 결과 ===');
  console.log('  application status :', app.status);
  console.log('  snapshot 보존      : wage', app.wage,
    '| 시간', app.startTime, '~', app.endTime,
    '| wdId', app.workDetailId);
  console.log('  TO  totalConfirmed :', to.totalConfirmed,
    '| totalPending =', to.totalPending, '| status =', to.status);
  console.log('  slot confirmedCount:', slot.confirmedCount,
    '| status =', slot.status);
  console.log('  wd  requiredCount  :', wd.requiredCount,
    '| confirmed =', wd.confirmedCount ?? '(필드 없음)');

  // ── §10: FULL 이후에도 lifecycle 이 살아 있는가 ───────────────
  const cAfter = await db.collection('employment_contracts')
    .where('applicationId', '==', L.applicationId).get();
  console.log('\n=== FULL 이후 lifecycle ===');
  console.log('  계약 문서:', cAfter.size);
  cAfter.forEach((c) => {
    const d = c.data();
    console.log('   contractId:', c.id.slice(0, 10) + '…',
      '| status =', d.status,
      '| 기간 =', d.contractStart, '~', d.contractEnd);
    L.contractId = c.id;
  });

  L.appStatusAfterConfirm = app.status;
  fs.writeFileSync('.goldenpath.json', JSON.stringify(L, null, 2));
  process.exit(0);
})().catch((e) => { console.error('실패:', e.message); process.exit(1); });
