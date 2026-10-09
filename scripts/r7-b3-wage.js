/**
 * [R7-GOLDEN-PATH-DEV-E2E.1 §B 후속] B1 fixture 급여 확정.
 *
 *   리뷰(§C)는 wageStatus=confirmed 트리거가 review_request 를 만든 뒤에만
 *   가능하다. 이 단계는 §B 의 증거가 아니라 §C 의 전제다.
 */
'use strict';
const fs = require('fs');
const lib = require('./r7-fixture-lib');
const {db} = lib;
const unwrap = (r) => (r && (r.result ?? r.data)) ?? r;

(async () => {
  const B = JSON.parse(fs.readFileSync('.b1fixture.json', 'utf8'));
  const a = (await db.collection('attendance').doc(B.attendanceId).get()).data();
  console.log('근태: status', a.status, '| wageStatus', a.wageStatus,
    '| workHours', a.workHours ?? '(없음)');
  if (a.checkOut == null) throw new Error('퇴근 전이다 — §B 가 선행돼야 한다');

  if (a.wageStatus === 'pending') {
    const res = unwrap(await lib.callAs(B.adminUid,
      'callableCalculateAndConfirmWage', {
        attendanceId: B.attendanceId,
        wageType: 'hourly', baseWage: B.wage,
        workDate: B.dateStr,
        scheduledStart: B.startTime, scheduledEnd: B.endTime,
        actualStart: B.startTime, actualEnd: B.endTime,
        breakMinutes: 0,
        nightAllowanceApplied: false, nightIncluded: false,
        taxDeductionType: 'none',
        yearMonth: B.dateStr.slice(0, 7),
        payScheduleType: 'next_day',
      }));
    console.log('계산:', JSON.stringify(res));
  } else {
    console.log('계산: 이미 완료 (', a.wageStatus, ')');
  }

  const a2 = (await db.collection('attendance').doc(B.attendanceId).get())
    .data();
  if (a2.wageStatus === 'calculated') {
    const c = unwrap(await lib.callAs(B.adminUid, 'callableConfirmFinalWage', {
      businessId: B.businessId, attendanceIds: [B.attendanceId],
    }));
    console.log('확정:', JSON.stringify(c));
  }

  const a3 = (await db.collection('attendance').doc(B.attendanceId).get())
    .data();
  console.log('\nwageStatus:', a3.wageStatus, '| finalWage:', a3.finalWage);

  const requestId = `${B.businessId}_${B.uid}_2026_10`;
  const rr = await db.collection('review_requests').doc(requestId).get();
  console.log('review_request 생성:', rr.exists,
    rr.exists ? `| adminStatus=${rr.data().adminStatus} workerStatus=${rr.data().workerStatus}` : '');
  process.exit(0);
})().catch((e) => { console.error('실패:', e.message); process.exit(1); });
