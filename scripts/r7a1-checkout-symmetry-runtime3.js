/**
 * [R7-ATTENDANCE.1 §22-5] 비콘 성공 칸만 닫는다.
 *
 *   2단계에서 비콘 + 좌표 + 반경 안은 **게이트를 통과**했지만, 그 앞에서 돌린
 *   reset 이 `checkIn` 까지 지워서 반올림 단계에서 멈췄다. 관리자 경로로
 *   출근 시각을 되돌린 뒤 비콘 퇴근을 끝까지 본다.
 */
'use strict';
const fs = require('fs');
const lib = require('./r7-fixture-lib');
const {db} = lib;
const unwrap = (r) => (r && (r.result ?? r.data)) ?? r;
const KST = 9 * 3600000;

const S = JSON.parse(fs.readFileSync('.symfixture.json', 'utf8'));
const bizRef = db.collection('businesses').doc(S.businessId);
const attRef = db.collection('attendance').doc(S.attendanceId);

(async () => {
  const biz = (await bizRef.get()).data();
  const originalType = biz.attendanceType;
  const [sh, sm] = S.startTime.split(':').map(Number);
  const [eh, em] = S.endTime.split(':').map(Number);

  try {
    // 퇴근 기록을 비운 뒤(reset) 출근 시각만 복원한다.
    await lib.callAs(S.adminUid, 'callableBatchResetAttendance', {
      businessId: S.businessId, attendanceIds: [S.attendanceId],
    });
    // 출근 시각 복원 (관리자 경로 — 좌표 없이, 사유 포함)
    await lib.callAs(S.adminUid, 'callableBatchAdjustAttendanceTime', {
      businessId: S.businessId,
      entries: [{
        attendanceId: S.attendanceId,
        checkInMs: S.workDateMs + (sh * 60 + sm) * 60000,
        status: 'present', resetWageDetail: false,
        reason: '[R7-A.1] 비콘 퇴근 확인을 위한 출근 시각 복원',
      }],
    });
    const pre = (await attRef.get()).data();
    const t = (v) => v && v.toMillis ?
      new Date(v.toMillis() + KST).toISOString().slice(11, 16) : '(없음)';
    console.log('복원된 checkIn:', t(pre.checkIn),
      '| checkOut:', t(pre.checkOut));
    if (pre.checkOut != null) throw new Error('checkOut 이 남아 있다');

    await bizRef.update({attendanceType: 'beacon'});
    console.log('\n═══ §22-5 비콘 + 좌표 + 반경 안 ═══');
    const r = unwrap(await lib.callAs(S.uid, 'callableCheckOut', {
      attendanceId: S.attendanceId, workDateMs: S.workDateMs,
      scheduledStartTime: S.startTime, scheduledEndTime: S.endTime,
      method: 'beacon', latitude: biz.latitude, longitude: biz.longitude,
    }));
    console.log('  응답:', JSON.stringify(r));
    const a = (await attRef.get()).data();
    console.log('  checkOut         :', t(a.checkOut),
      '| originalCheckOut:', t(a.originalCheckOut));
    console.log('  checkOutMethod   :', a.checkOutMethod,
      '(비콘으로 기록 — gps 로 추정하지 않는다)');
    console.log('  checkOutDistance :', a.checkOutDistance,
      '(비콘이어도 서버가 거리를 남긴다)');
    console.log('  status           :', a.status,
      '| workHours:', a.workHours);
  } finally {
    await bizRef.update({attendanceType: originalType});
    console.log('\nattendanceType 원복:',
      (await bizRef.get()).data().attendanceType);
  }
  process.exit(0);
})().catch((e) => { console.error('실패:', e.message); process.exit(1); });
