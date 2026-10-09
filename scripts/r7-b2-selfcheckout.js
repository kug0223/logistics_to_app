/**
 * [R7-GOLDEN-PATH-DEV-E2E.1 §B] 근로자 자기 퇴근.
 *
 *   §11 — 이 fixture 에는 관리자 보정이 **한 번도 없다**. 그래서 여기서 나오는
 *   증거는 전부 self checkout 증거다.
 *   §7 — 시계를 조작하지 않는다. 실패하면 실패로 기록한다.
 */
'use strict';
const fs = require('fs');
const lib = require('./r7-fixture-lib');
const {db} = lib;
const unwrap = (r) => (r && (r.result ?? r.data)) ?? r;

(async () => {
  const B = JSON.parse(fs.readFileSync('.b1fixture.json', 'utf8'));
  const biz = (await db.collection('businesses').doc(B.businessId).get()).data();
  const nowKst = new Date(Date.now() + 9 * 3600000).toISOString().slice(11, 16);
  console.log('KST 지금:', nowKst, '| 근무', B.startTime, '~', B.endTime);

  const before = (await db.collection('attendance').doc(B.attendanceId).get())
    .data();
  const t = (v) => v && v.toMillis ?
    new Date(v.toMillis() + 9 * 3600000).toISOString().slice(11, 16) : '(없음)';
  console.log('퇴근 전: checkIn', t(before.checkIn),
    '| checkOut', t(before.checkOut), '| status', before.status,
    '| isModified', before.isModified);

  console.log('\n— callableCheckOut (근로자 본인)');
  let ok = false;
  try {
    const res = unwrap(await lib.callAs(B.uid, 'callableCheckOut', {
      attendanceId: B.attendanceId,
      workDateMs: B.workDateMs,
      latitude: biz.latitude, longitude: biz.longitude,
      method: 'gps',
      scheduledStartTime: B.startTime,
      scheduledEndTime: B.endTime,
    }));
    ok = true;
    console.log('  성공:', JSON.stringify(res).slice(0, 300));
  } catch (e) {
    console.log('  거절:', String(e.message).slice(0, 200));
  }

  const a = (await db.collection('attendance').doc(B.attendanceId).get()).data();
  console.log('\n=== 근태 상태 ===');
  console.log('  attendanceId 동일 :',
    B.attendanceId === B.attendanceId ? '예' : '아니오');
  console.log('  checkIn 보존      :', t(a.checkIn),
    a.checkIn?.toMillis() === before.checkIn?.toMillis() ? '(변화 없음)' :
      '(**변했다**)');
  console.log('  checkOut          :', t(a.checkOut),
    '| 원본', t(a.originalCheckOut));
  console.log('  workDate 보존     :',
    a.workDate?.toMillis() === before.workDate?.toMillis() ?
      '예' : '**아니오**');
  console.log('  status            :', a.status);
  console.log('  workHours         :', a.workHours ?? '(없음)');
  console.log('  isModified        :', a.isModified,
    '| modifyReason', a.modifyReason ?? '(없음)',
    '| modifiedBy', a.modifiedBy ? '있음' : '(없음)');

  // 중복 근태 행이 생기지 않았는가
  const dup = await db.collection('attendance')
    .where('applicationId', '==', B.applicationId).get();
  console.log('  이 지원서의 근태 행 수:', dup.size,
    dup.size === 1 ? '(중복 없음)' : '(**중복**)');

  if (ok) {
    B.selfCheckoutAt = Date.now();
    fs.writeFileSync('.b1fixture.json', JSON.stringify(B, null, 2));
  }
  process.exit(0);
})().catch((e) => { console.error('실패:', e.message); process.exit(1); });
