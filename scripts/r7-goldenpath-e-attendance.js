/**
 * [R7-GOLDEN-PATH-DEV-E2E] Step E — 출근 / 퇴근.
 *
 *   §13 — GPS 검증을 우회하는 patch 를 만들지 않는다. 실제 기기가 하는 것과
 *   같이 **좌표를 보낸다**. 사업장 좌표를 보내는 것은 "근무지에 있다"는
 *   정상 입력이며, 검증 로직은 그대로 돌아간다.
 */
'use strict';
const fs = require('fs');
const lib = require('./r7-fixture-lib');
const {db} = lib;
const unwrap = (r) => (r && (r.result ?? r.data)) ?? r;

const mode = process.argv[2] || 'in';

(async () => {
  const L = JSON.parse(fs.readFileSync('.goldenpath.json', 'utf8'));
  const biz = (await db.collection('businesses').doc(L.businessId).get()).data();
  const to = (await db.collection('tos').doc(L.toId).get()).data();

  const nowKst = new Date(Date.now() + 9 * 3600 * 1000)
    .toISOString().slice(11, 16);
  console.log('KST 지금:', nowKst, '| 근무', L.startTime, '~', L.endTime);

  if (mode === 'in') {
    console.log('\n— callableCheckIn');
    const res = unwrap(await lib.callAs(L.applicantUid, 'callableCheckIn', {
      applicationId: L.applicationId,
      businessId: L.businessId,
      businessName: to.businessName,
      workDateMs: L.workDateMs,
      workType: L.workType,
      latitude: biz.latitude,
      longitude: biz.longitude,
      method: 'gps',
      scheduledStartTime: L.startTime,
    }));
    console.log('  응답:', JSON.stringify(res).slice(0, 300));
    if (res.attendanceId) L.attendanceId = res.attendanceId;
  } else {
    console.log('\n— callableCheckOut');
    const res = unwrap(await lib.callAs(L.applicantUid, 'callableCheckOut', {
      attendanceId: L.attendanceId,
      workDateMs: L.workDateMs,
      latitude: biz.latitude,
      longitude: biz.longitude,
      method: 'gps',
      scheduledStartTime: L.startTime,
      scheduledEndTime: L.endTime,
    }));
    console.log('  응답:', JSON.stringify(res).slice(0, 300));
  }

  const aSnap = await db.collection('attendance')
    .where('applicationId', '==', L.applicationId).get();
  console.log('\n=== 근태 ===');
  console.log('  건수:', aSnap.size);
  aSnap.forEach((d) => {
    const a = d.data();
    const t = (v) => v?.toDate ?
      new Date(v.toMillis() + 9 * 3600 * 1000).toISOString().slice(11, 16) :
      '(없음)';
    console.log('  id:', d.id.slice(0, 10) + '…', '| status =', a.status);
    console.log('   날짜키 :', a.workDateKey ?? a.dateKey ?? '(필드 확인)',
      '| workDate =',
      a.workDate ? new Date(a.workDate.toMillis() + 9 * 3600 * 1000)
        .toISOString().slice(0, 10) : '(없음)');
    console.log('   출근   :', t(a.checkIn), '| 원본', t(a.originalCheckIn),
      '| autoRounded =', a.autoRounded ?? '(없음)');
    console.log('   퇴근   :', t(a.checkOut), '| 원본', t(a.originalCheckOut));
    console.log('   wageStatus:', a.wageStatus ?? '(없음)',
      '| finalWage =', a.finalWage ?? '(없음)');
    L.attendanceId = d.id;
  });

  fs.writeFileSync('.goldenpath.json', JSON.stringify(L, null, 2));
  process.exit(0);
})().catch((e) => { console.error('실패:', e.message); process.exit(1); });
