/**
 * [R7-GOLDEN-PATH-DEV-E2E] Step G — 급여 확정 → 이체 표시.
 *
 *   §7(정책) 확인 — 주휴수당 자동계산 없음, effectiveNetWage 기준.
 *   §7(계좌) 확인 — V3 이체 invariant 4필드 snapshot.
 */
'use strict';
const fs = require('fs');
const lib = require('./r7-fixture-lib');
const {db} = lib;
const unwrap = (r) => (r && (r.result ?? r.data)) ?? r;

(async () => {
  const L = JSON.parse(fs.readFileSync('.goldenpath.json', 'utf8'));
  const a = (await db.collection('attendance').doc(L.attendanceId).get()).data();

  console.log('— callableCalculateAndConfirmWage (현재 wageStatus:',
    a.wageStatus, ')');
  const res = a.wageStatus !== 'pending' ? {생략: '이미 계산됨'} :
    unwrap(await lib.callAs(L.adminUid,
      'callableCalculateAndConfirmWage', {
      attendanceId: L.attendanceId,
      wageType: 'hourly',
      baseWage: L.wage,
      workDate: L.dateStr,
      scheduledStart: L.startTime, scheduledEnd: L.endTime,
      actualStart: L.startTime, actualEnd: L.endTime,
      breakMinutes: 0,
      nightAllowanceApplied: false, nightIncluded: false,
      taxDeductionType: 'none',
      yearMonth: L.dateStr.slice(0, 7),
        payScheduleType: 'next_day',
      }));
  console.log('  응답:', JSON.stringify(res).slice(0, 400));

  const a2 = (await db.collection('attendance').doc(L.attendanceId).get())
    .data();
  const wd = a2.wageDetail ?? {};
  console.log('\n=== 급여 확정 후 ===');
  console.log('  wageStatus :', a2.wageStatus);
  console.log('  finalWage  :', a2.finalWage ?? '(없음)');
  console.log('  wageDetail : netWage =', wd.netWage ?? '(없음)',
    '| totalAmount =', wd.totalAmount ?? '(없음)',
    '| isConfirmed =', wd.isConfirmed ?? '(없음)');
  console.log('  주휴수당 필드:',
    Object.keys(wd).filter((k) => /holiday|weekly/i.test(k)).join(',') ||
    '(없음 — 자동계산 없음)');
  console.log('  계좌 snapshot 4필드:');
  for (const f of ['wageAccountBankName', 'wageAccountNumberEncrypted',
    'wageAccountHolder', 'wageAccountSnapshotAt']) {
    const v = a2[f];
    console.log('   ', f.padEnd(30),
      v === undefined ? '(없음)' : (f.includes('Number') ? '(존재·마스킹)' :
        (v.toMillis ? '존재' : '존재')));
  }
  console.log('  snapshotVersion:', a2.wageAccountSnapshotVersion ?? '(없음)');

  // calculated → confirmed. 계좌 4필드 snapshot 은 이 단계가 쓴다.
  console.log('\n— callableConfirmFinalWage');
  const cres = unwrap(await lib.callAs(L.adminUid, 'callableConfirmFinalWage', {
    businessId: L.businessId,
    attendanceIds: [L.attendanceId],
  }));
  console.log('  응답:', JSON.stringify(cres).slice(0, 400));

  const aC = (await db.collection('attendance').doc(L.attendanceId).get())
    .data();
  console.log('  wageStatus:', aC.wageStatus,
    '| snapshotVersion =', aC.wageAccountSnapshotVersion ?? '(없음)');
  for (const f of ['wageAccountBankName', 'wageAccountNumberEncrypted',
    'wageAccountHolder', 'wageAccountSnapshotAt']) {
    console.log('   ', f.padEnd(30),
      aC[f] === undefined ? '(없음)' : '존재');
  }

  console.log('\n— callableMarkTransferredBatch');
  const tres = unwrap(await lib.callAs(L.adminUid, 'callableMarkTransferredBatch', {
    businessId: L.businessId,
    attendanceIds: [L.attendanceId],
  }));
  console.log('  응답:', JSON.stringify(tres).slice(0, 400));

  const a3 = (await db.collection('attendance').doc(L.attendanceId).get())
    .data();
  console.log('\n=== Step G 결과 ===');
  console.log('  wageStatus   :', a3.wageStatus);
  console.log('  transferredAt:', a3.transferredAt ? '존재' : '(없음)');

  L.wageStatus = a3.wageStatus;
  fs.writeFileSync('.goldenpath.json', JSON.stringify(L, null, 2));
  process.exit(0);
})().catch((e) => { console.error('실패:', e.message); process.exit(1); });
