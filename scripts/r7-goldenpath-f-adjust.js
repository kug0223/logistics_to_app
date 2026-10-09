/**
 * [R7-GOLDEN-PATH-DEV-E2E] Step F — 관리자 근태 보정으로 퇴근 기록.
 *
 *   §28 — 시스템 clock 을 조작하지 않는다. 지금은 KST 14시대이고 근무는
 *   18:00 에 끝난다. 근로자 self 퇴근은 서버가 정상적으로 거절했다
 *   ("계산된 퇴근 시각이 출근 시각보다 이릅니다 — 관리자에게 수동 수정을
 *   요청하세요"). 그 안내가 가리키는 **제품의 정상 경로**를 그대로 탄다.
 *
 *   따라서 이 단계의 퇴근 시각은 '근로자가 기기로 찍은 시각'이 아니라
 *   '관리자가 보정한 시각'이다 — 보고에 그대로 기록한다.
 */
'use strict';
const fs = require('fs');
const lib = require('./r7-fixture-lib');
const {db} = lib;
const unwrap = (r) => (r && (r.result ?? r.data)) ?? r;

(async () => {
  const L = JSON.parse(fs.readFileSync('.goldenpath.json', 'utf8'));
  const [eh, em] = L.endTime.split(':').map(Number);
  const checkOutMs = L.workDateMs + (eh * 60 + em) * 60000;
  const [sh, sm] = L.startTime.split(':').map(Number);
  const checkInMs = L.workDateMs + (sh * 60 + sm) * 60000;

  console.log('— 사유 없이 호출 (거절돼야 한다)');
  try {
    await lib.callAs(L.adminUid, 'callableBatchAdjustAttendanceTime', {
      businessId: L.businessId,
      entries: [{
        attendanceId: L.attendanceId, checkOutMs,
        status: 'present', resetWageDetail: false,
      }],
    });
    console.log('  **거절되지 않았다**');
  } catch (e) {
    console.log('  거절:', String(e.message).slice(0, 120));
  }

  console.log('\n— callableBatchAdjustAttendanceTime (사유 포함)');
  const res = unwrap(await lib.callAs(L.adminUid,
    'callableBatchAdjustAttendanceTime', {
      businessId: L.businessId,
      entries: [{
        attendanceId: L.attendanceId,
        checkInMs, checkOutMs,
        workHours: (checkOutMs - checkInMs) / 3600000,
        status: 'present',
        resetWageDetail: false,
        reason: '[GOLDEN PATH] 근로자 퇴근 기록 누락 — 약속 시각으로 보정',
      }],
    }));
  console.log('  응답:', JSON.stringify(res));

  const a = (await db.collection('attendance').doc(L.attendanceId).get()).data();
  const t = (v) => v && v.toMillis ?
    new Date(v.toMillis() + 9 * 3600000).toISOString().slice(11, 16) : '(없음)';
  console.log('\n=== Step F 결과 ===');
  console.log('  status     :', a.status, '| wageStatus =', a.wageStatus);
  console.log('  출근       :', t(a.checkIn), '| 원본', t(a.originalCheckIn));
  console.log('  퇴근       :', t(a.checkOut), '| 원본', t(a.originalCheckOut));
  console.log('  workHours  :', a.workHours ?? '(없음)');
  console.log('  isModified :', a.isModified, '| 사유 =',
    a.modifyReason ?? '(없음)');
  console.log('  수정자     :', a.modifiedBy ?
    String(a.modifiedBy).slice(0, 6) + '…' : '(없음)');

  fs.writeFileSync('.goldenpath.json', JSON.stringify(L, null, 2));
  process.exit(0);
})().catch((e) => { console.error('실패:', e.message); process.exit(1); });
