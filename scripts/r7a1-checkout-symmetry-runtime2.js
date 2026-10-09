/**
 * [R7-ATTENDANCE.1 §22] 2단계 — 성공·비콘·manual·재시도·관리자 복구.
 *
 *   §24 주의: 사업장 좌표를 좌표 입력으로 쓴다. 서버 검증이 동작한다는 증거이고
 *   진짜 기기 위치 증명이 아니다.
 *
 *   비콘·manual 칸은 사업장 `attendanceType` 을 바꿔야 확인할 수 있다.
 *   그건 제품 흐름 위조가 아니라 **테스트 설정**이고, 끝에 원래 값으로 되돌린다.
 *   (Admin SDK 직접 쓰기 — 보고에 그대로 적는다.)
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

async function step(label, fn) {
  try {
    const r = await fn();
    console.log(`  ${label.padEnd(44)} 통과   ${r ?? ''}`);
    return {ok: true, value: r};
  } catch (e) {
    const m = String(e.message).replace(/^callable\w+ 실패 /, '');
    console.log(`  ${label.padEnd(44)} 거절   ${m.slice(0, 86)}`);
    return {ok: false, msg: m};
  }
}

const co = (method, extra = {}) => lib.callAs(S.uid, 'callableCheckOut', {
  attendanceId: S.attendanceId, workDateMs: S.workDateMs,
  scheduledStartTime: S.startTime, scheduledEndTime: S.endTime,
  method, ...extra,
});

async function resetAttendance() {
  await lib.callAs(S.adminUid, 'callableBatchResetAttendance', {
    businessId: S.businessId, attendanceIds: [S.attendanceId],
  });
}

(async () => {
  const biz = (await bizRef.get()).data();
  const originalType = biz.attendanceType;
  const at = {lat: biz.latitude, lng: biz.longitude};
  console.log('원래 attendanceType:', originalType);

  // 근무 종료 + 40초까지 기다린다 — 정시 퇴근 창.
  const [eh, em] = S.endTime.split(':').map(Number);
  const endMs = S.workDateMs + (eh * 60 + em) * 60000 + 40000;
  while (Date.now() < endMs) {
    await new Promise((r) => setTimeout(r, 5000));
  }
  console.log('KST 지금:',
    new Date(Date.now() + KST).toISOString().slice(11, 19),
    '| 근무', S.startTime, '~', S.endTime);

  try {
    console.log('\n═══ §22-1 GPS 반경 안 성공 ═══');
    const ok = await step('반경 안 + gps', () => co('gps',
      {latitude: at.lat, longitude: at.lng}));
    if (!ok.ok) throw new Error('성공 시나리오 실패 — 이후 단계 중단');

    const a = (await attRef.get()).data();
    const t = (v) => v && v.toMillis ?
      new Date(v.toMillis() + KST).toISOString().slice(11, 16) : '(없음)';
    console.log('\n═══ §22-9 / §17 저장된 증거 ═══');
    console.log('  checkOut          :', t(a.checkOut),
      '| originalCheckOut:', t(a.originalCheckOut));
    console.log('  checkOutMethod    :', a.checkOutMethod);
    console.log('  checkOutLat/Lng   :', a.checkOutLat != null && a.checkOutLng != null);
    console.log('  checkOutDistance  :', a.checkOutDistance,
      '(서버 Haversine 값 — 클라이언트는 거리를 보내지 않는다)');
    console.log('  status            :', a.status, '| workHours:', a.workHours);

    console.log('\n═══ §22-12 재시도 ═══');
    await step('같은 퇴근 재호출', () => co('gps',
      {latitude: at.lat, longitude: at.lng}));

    console.log('\n═══ §22-13 / §9 관리자 복구는 영향 없음 ═══');
    await step('관리자 시간 보정 (좌표 없이, 사유 포함)', async () => {
      const r = unwrap(await lib.callAs(S.adminUid,
        'callableBatchAdjustAttendanceTime', {
          businessId: S.businessId,
          entries: [{
            attendanceId: S.attendanceId,
            checkOutMs: S.workDateMs + (eh * 60 + em + 2) * 60000,
            status: 'present', resetWageDetail: false,
            reason: '[R7-A.1] 관리자 경로가 반경과 무관함을 확인',
          }],
        }));
      return `processed=${r.processed}`;
    });
    const a2 = (await attRef.get()).data();
    console.log('    보정 후 checkOut:', t(a2.checkOut),
      '| isModified:', a2.isModified, '| 원본 보존:', t(a2.originalCheckOut));

    // ── 비콘 ────────────────────────────────────────────────
    console.log('\n═══ §22-5 / §22-6 비콘 ═══');
    await resetAttendance();
    await bizRef.update({attendanceType: 'beacon'});
    await step('비콘 사업장 + gps 방식', () => co('gps',
      {latitude: at.lat, longitude: at.lng}));
    await step('비콘 사업장 + beacon, 좌표 없음', () => co('beacon'));
    await step('비콘 사업장 + beacon, 반경 밖', () => co('beacon',
      {latitude: at.lat + 0.05, longitude: at.lng}));
    const bok = await step('비콘 사업장 + beacon, 반경 안', () => co('beacon',
      {latitude: at.lat, longitude: at.lng}));
    if (bok.ok) {
      const a3 = (await attRef.get()).data();
      console.log('    checkOutMethod:', a3.checkOutMethod,
        '| checkOutDistance:', a3.checkOutDistance);
    }

    // ── manual ──────────────────────────────────────────────
    console.log('\n═══ §22-8 manual ═══');
    await resetAttendance();
    await bizRef.update({attendanceType: 'manual'});
    await step('manual 사업장 + 근로자 self 퇴근', () => co('gps',
      {latitude: at.lat, longitude: at.lng}));
    const a4 = (await attRef.get()).data();
    console.log('    checkOut 생성됨:', a4.checkOut != null ? '**예**' : '아니오');
    await step('manual 사업장 + 관리자 보정', async () => {
      const r = unwrap(await lib.callAs(S.adminUid,
        'callableBatchAdjustAttendanceTime', {
          businessId: S.businessId,
          entries: [{
            attendanceId: S.attendanceId,
            checkOutMs: S.workDateMs + (eh * 60 + em) * 60000,
            status: 'present', resetWageDetail: false,
            reason: '[R7-A.1] manual 사업장에서도 관리자 경로는 열려 있다',
          }],
        }));
      return `processed=${r.processed}`;
    });
  } finally {
    await bizRef.update({attendanceType: originalType});
    const back = (await bizRef.get()).data().attendanceType;
    console.log('\nattendanceType 원복:', back,
      back === originalType ? '(확인)' : '(**불일치**)');
  }
  process.exit(0);
})().catch(async (e) => {
  console.error('실패:', e.message);
  process.exit(1);
});
