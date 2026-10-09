/**
 * [R7-ATTENDANCE.2 §17] NO_SHOW 상태와 그 취소 뒤 상태 — DEV 런타임.
 *
 *   `callableBatchSetNoShow` 는 checkIn 이 있는 문서를 NO_SHOW 로 만들지 않는다
 *   (CF-MED-3-FIX — 모순 문서 방지). 그래서 canonical 순서는
 *   reset → setNoShow 다. 억지 재현이 아니라 그 가드를 지키는 순서다.
 */
'use strict';
const fs = require('fs');
const lib = require('./r7-fixture-lib');
const {db} = lib;
const unwrap = (r) => (r && (r.result ?? r.data)) ?? r;

const S = JSON.parse(fs.readFileSync('.symfixture.json', 'utf8'));
const attRef = db.collection('attendance').doc(S.attendanceId);
const appRef = db.collection('applications').doc(S.applicationId);
const slotRef = db.collection('tos').doc(S.toId)
  .collection('slots').doc(S.slotId);

async function tryCheckIn() {
  const biz = (await db.collection('businesses').doc(S.businessId).get()).data();
  const att = (await attRef.get()).data() ?? {};
  try {
    await lib.callAs(S.uid, 'callableCheckIn', {
      applicationId: S.applicationId, businessId: S.businessId,
      businessName: biz.name, workDateMs: S.workDateMs,
      workType: att.workType ?? '상하차',
      method: 'gps', latitude: biz.latitude, longitude: biz.longitude,
      scheduledStartTime: S.startTime,
    });
    return {ok: true};
  } catch (e) {
    return {ok: false, wire: e.wireCode, msg: String(e.message)
      .replace(/^callableCheckIn 실패 \[[A-Z_]+\] /, '')};
  }
}

async function snapshot(label) {
  const a = (await attRef.get()).data() ?? {};
  const app = (await appRef.get()).data();
  const slot = (await slotRef.get()).data();
  const u = (await db.collection('users').doc(S.uid).get()).data();
  const t = (v) => v && v.toMillis ?
    new Date(v.toMillis() + 9 * 3600000).toISOString().slice(11, 16) : '없음';
  const r = await tryCheckIn();
  console.log(`\n── ${label}`);
  console.log(`   문서: checkIn=${t(a.checkIn)} status=${a.status ?? '없음'}` +
    ` wageStatus=${a.wageStatus ?? '없음'} finalWage=${a.finalWage ?? '없음'}`);
  console.log(`   self 출근: ${r.ok ? '**통과**' : '차단'}` +
    (r.ok ? '' : ` [${r.wire}] ${r.msg}`));
  console.log(`   좌석: slot.confirmedCount=${slot.confirmedCount}` +
    ` | 지원서=${app.status}` +
    ` | staffingReleasedAt=${app.staffingReleasedAt ? '있음' : '없음'}` +
    ` | noShowCount=${u.noShowCount ?? 0}`);
  return r;
}

(async () => {
  const att0 = (await attRef.get()).data();

  // 0. reset — NO_SHOW 가드를 지키기 위해 checkIn 을 비운다(관리자 경로).
  await lib.callAs(S.adminUid, 'callableBatchResetAttendance', {
    businessId: S.businessId, attendanceIds: [S.attendanceId],
  });

  // 1. NO_SHOW
  const ns = unwrap(await lib.callAs(S.adminUid, 'callableBatchSetNoShow', {
    businessId: S.businessId,
    entries: [{
      applicationId: S.applicationId, workDateMs: S.workDateMs,
      userId: S.uid, businessName: att0.businessName,
      workType: att0.workType, attendanceId: S.attendanceId,
    }],
  }));
  console.log('setNoShow 응답:', JSON.stringify(ns));
  await snapshot('1) NO_SHOW');

  // 2. 좌석 반납 (노쇼 전용 경로)
  try {
    const rel = unwrap(await lib.callAs(S.adminUid, 'callableReleaseNoshowSeat', {
      businessId: S.businessId, applicationId: S.applicationId,
    }));
    console.log('\n좌석 반납 응답:', JSON.stringify(rel).slice(0, 160));
  } catch (e) {
    console.log('\n좌석 반납 실패:', String(e.message).slice(0, 120));
  }
  await snapshot('2) NO_SHOW + 좌석 반납');

  // 3. 노쇼 취소
  const cn = unwrap(await lib.callAs(S.adminUid, 'callableBatchCancelNoShow', {
    businessId: S.businessId, attendanceIds: [S.attendanceId],
  }));
  console.log('\ncancelNoShow 응답:', JSON.stringify(cn));
  await snapshot('3) 노쇼 취소 뒤 (비어 있는 문서)');

  console.log('\n근태 행 수:',
    (await db.collection('attendance')
      .where('applicationId', '==', S.applicationId).get()).size);
  process.exit(0);
})().catch((e) => { console.error('실패:', e.message); process.exit(1); });
