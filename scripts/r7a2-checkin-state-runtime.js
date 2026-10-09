/**
 * [R7-ATTENDANCE.2 §17] 근태 문서 상태별 self 출근 거절 — DEV 런타임.
 *
 *   상태는 **canonical callable 로만** 만든다. 억지 재현을 위한 직접 쓰기 없음.
 *   `missed_checkout` 은 자정 스케줄러만 만들 수 있어 여기서 재현하지 않는다
 *   (보고에 NOT TESTED 로 적는다).
 */
'use strict';
const fs = require('fs');
const lib = require('./r7-fixture-lib');
const {db} = lib;
const unwrap = (r) => (r && (r.result ?? r.data)) ?? r;

const S = JSON.parse(fs.readFileSync('.symfixture.json', 'utf8'));
const attRef = db.collection('attendance').doc(S.attendanceId);

async function tryCheckIn() {
  const biz = (await db.collection('businesses').doc(S.businessId).get()).data();
  try {
    await lib.callAs(S.uid, 'callableCheckIn', {
      applicationId: S.applicationId, businessId: S.businessId,
      businessName: biz.name, workDateMs: S.workDateMs,
      workType: (await attRef.get()).data().workType,
      method: 'gps', latitude: biz.latitude, longitude: biz.longitude,
      scheduledStartTime: S.startTime,
    });
    return {ok: true};
  } catch (e) {
    return {ok: false, wire: e.wireCode, msg: String(e.message)
      .replace(/^callableCheckIn 실패 \[[A-Z_]+\] /, '')};
  }
}

async function show(label) {
  const a = (await attRef.get()).data() ?? {};
  const u = (await db.collection('users').doc(S.uid).get()).data();
  const t = (v) => v && v.toMillis ?
    new Date(v.toMillis() + 9 * 3600000).toISOString().slice(11, 16) : '없음';
  const r = await tryCheckIn();
  console.log(`\n── ${label}`);
  console.log(`   문서: checkIn=${t(a.checkIn)} status=${a.status ?? '없음'}` +
    ` wageStatus=${a.wageStatus ?? '없음'} finalWage=${a.finalWage ?? '없음'}`);
  console.log(`   self 출근: ${r.ok ? '**통과**' : '차단'}` +
    (r.ok ? '' : ` [${r.wire}] ${r.msg}`));
  console.log(`   noShowCount: ${u.noShowCount ?? 0}`);
  return r;
}

(async () => {
  const att0 = (await attRef.get()).data();
  console.log('fixture:', S.attendanceId.slice(0, 28) + '…');

  // ── 1. 정상 출근 기록이 있는 상태 ────────────────────────────
  await show('1) checkIn 있음 (정상 출근)');

  // ── 2. NO_SHOW ──────────────────────────────────────────────
  await lib.callAs(S.adminUid, 'callableBatchSetNoShow', {
    businessId: S.businessId,
    entries: [{
      applicationId: S.applicationId, workDateMs: S.workDateMs,
      userId: S.uid, businessName: att0.businessName,
      workType: att0.workType, attendanceId: S.attendanceId,
    }],
  });
  await show('2) NO_SHOW');
  const slotAfterNoShow = (await db.collection('tos').doc(S.toId)
    .collection('slots').doc(S.slotId).get()).data();
  const appAfterNoShow = (await db.collection('applications')
    .doc(S.applicationId).get()).data();
  console.log(`   좌석: slot.confirmedCount=${slotAfterNoShow.confirmedCount}` +
    ` | 지원서 status=${appAfterNoShow.status}` +
    ` | staffingReleasedAt=${appAfterNoShow.staffingReleasedAt ? '있음' : '없음'}`);

  // ── 3. 노쇼 취소 ────────────────────────────────────────────
  await lib.callAs(S.adminUid, 'callableBatchCancelNoShow', {
    businessId: S.businessId, attendanceIds: [S.attendanceId],
  });
  await show('3) 노쇼 취소 뒤 (비어 있는 문서)');

  // ── 4. 결근 ─────────────────────────────────────────────────
  await lib.callAs(S.adminUid, 'callableBatchAdjustAttendanceTime', {
    businessId: S.businessId,
    entries: [{
      attendanceId: S.attendanceId, status: 'absent', resetWageDetail: false,
    }],
  });
  await show('4) 결근(absent)');

  // ── 5. 초기화 ───────────────────────────────────────────────
  await lib.callAs(S.adminUid, 'callableBatchResetAttendance', {
    businessId: S.businessId, attendanceIds: [S.attendanceId],
  });
  await show('5) 초기화(reset) 뒤');

  // ── 6. 관리자 복구는 여전히 가능한가 ────────────────────────
  const [sh, sm] = S.startTime.split(':').map(Number);
  const res = unwrap(await lib.callAs(S.adminUid, 'callableBatchCheckIn', {
    businessId: S.businessId,
    entries: [{
      applicationId: S.applicationId, workDateMs: S.workDateMs,
      userId: S.uid, businessId: S.businessId,
      businessName: att0.businessName, workType: att0.workType,
      status: 'present',
      checkInMs: S.workDateMs + (sh * 60 + sm) * 60000,
      attendanceId: S.attendanceId,
    }],
  }));
  const a6 = (await attRef.get()).data();
  const t = (v) => v && v.toMillis ?
    new Date(v.toMillis() + 9 * 3600000).toISOString().slice(11, 16) : '없음';
  console.log('\n── 6) 관리자 복구 (callableBatchCheckIn)');
  console.log('   응답:', JSON.stringify(res));
  console.log('   문서: checkIn=' + t(a6.checkIn), 'status=' + a6.status,
    '| 근태 행 수 =',
    (await db.collection('attendance')
      .where('applicationId', '==', S.applicationId).get()).size);
  process.exit(0);
})().catch((e) => { console.error('실패:', e.message); process.exit(1); });
