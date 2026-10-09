/**
 * [R7-ATTENDANCE.1 §22 §24] 퇴근 서버 대칭 — DEV 런타임 검증.
 *
 *   §24 — 실기기 GPS 가 없으므로 사업장 좌표를 좌표 입력으로 쓴다.
 *   이것은 **서버 검증이 동작한다**는 증거이고, **진짜 기기 위치 증명이
 *   아니다**(TARGETED_GPS_SPOOF_REMAINS 는 그대로 열려 있다). 과장하지 않는다.
 *
 *   거절 시나리오는 위치·방식 게이트가 **반올림 이전**에 돌기 때문에
 *   시간 창과 무관하게 바로 확인할 수 있다. 성공 시나리오만 시간이 필요하다.
 *
 *   fixture: 지금 시작해 1분 뒤 끝나는 근무를 canonical 흐름으로 만든다.
 */
'use strict';
const fs = require('fs');
const lib = require('./r7-fixture-lib');
const {db} = lib;
const unwrap = (r) => (r && (r.result ?? r.data)) ?? r;
const CONSENT = '2026-09-18-v3';
const PNG = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4' +
  '2mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==';

const KST = 9 * 3600000;
const pad = (n) => String(n).padStart(2, '0');

async function step(label, fn) {
  try {
    const r = await fn();
    console.log(`  ${label.padEnd(42)} 통과   ${r ?? ''}`);
    return {ok: true};
  } catch (e) {
    const m = String(e.message).replace(/^callable\w+ 실패 /, '');
    console.log(`  ${label.padEnd(42)} 거절   ${m.slice(0, 92)}`);
    return {ok: false, msg: m};
  }
}

(async () => {
  const G = JSON.parse(fs.readFileSync('.goldenpath.json', 'utf8'));
  const businessId = G.businessId;
  const adminUid = G.adminUid;
  const biz = (await db.collection('businesses').doc(businessId).get()).data();
  console.log('사업장 attendanceType:', biz.attendanceType,
    '| gpsRadius:', biz.gpsRadius, '| 좌표:', biz.latitude != null);

  // ── fixture: 지금~+1분 근무 ──────────────────────────────────
  const nowKst = new Date(Date.now() + KST);
  const dateStr = lib.kstDateKey(0);
  const workDateMs = lib.kstMidnightMs(0);
  // 마감은 슬롯 시작 이전이어야 한다 — 시작을 3분 뒤로 둔다.
  //   출근은 earlyWindow(30분) 안이라 지금 바로 가능하다.
  const startM = nowKst.getUTCHours() * 60 + nowKst.getUTCMinutes() + 3;
  const START = `${pad(Math.floor(startM / 60))}:${pad(startM % 60)}`;
  const endM = startM + 1;
  const END = `${pad(Math.floor(endM / 60))}:${pad(endM % 60)}`;
  console.log('근무:', dateStr, START, '~', END, '(KST) — 지금', 
    nowKst.toISOString().slice(11,16));

  const wtSnap = await db.collection('businesses').doc(businessId)
    .collection('workTypes').limit(1).get();
  const wt = wtSnap.docs[0].data();
  const wd = {
    wdId: 'sym-wd-1', workType: wt.name,
    workTypeIcon: wt.icon ?? 'box', workTypeColor: wt.color ?? '#1565C0',
    workTypeBackgroundColor: wt.backgroundColor ?? '#E3F2FD',
    wage: 12000, wageType: 'hourly', requiredCount: 1,
    startTime: START, endTime: END, order: 0, payScheduleType: 'next_day',
  };

  // 오늘 비어 있는 근로자
  const users = await db.collection('users').where('role', '==', 'USER').get();
  let uid = null;
  for (const u of users.docs) {
    const busy = await db.collection('applications')
      .where('uid', '==', u.id)
      .where('status', 'in', ['CONFIRMED', 'CONTRACT_PENDING']).get();
    if (!busy.docs.some((d) => d.data().workDate?.toMillis() === workDateMs)) {
      uid = u.id; break;
    }
  }
  if (!uid) throw new Error('오늘 비어 있는 근로자가 없다');

  const created = unwrap(await lib.callAs(adminUid, 'callableCreateTO', {
    toData: {
      businessId, businessName: biz.name, title: '[R7-A.1] 퇴근 대칭 검증',
      description: 'R7-ATTENDANCE.1 전용. 실제 모집 아님.',
      type: 'flex', workDetails: [wd], creatorUID: adminUid,
      totalRequired: 1, totalConfirmed: 0, totalPending: 0, status: 'active',
      deadlineType: 'FIXED_TIME', hoursBeforeStart: 1,
      isPublished: false, publishMode: 'deferred',
    },
  }));
  const toId = created.toId;
  await lib.callAs(adminUid, 'callableCreateFlexSlots', {
    toId, businessId, dates: [dateStr], workDetails: [wd],
    deadlineType: 'FIXED_TIME', hoursBeforeStart: 1,
    fixedDeadlineMs: Date.now() + 60000, publishMode: 'immediate',
  });
  try { await lib.callAs(adminUid, 'callablePublishTO', {toId}); } catch (_) {}
  const slots = await db.collection('tos').doc(toId).collection('slots').get();
  const slotId = slots.docs[0].id;
  const wdId = ((slots.docs[0].data().workDetails || [])[0] || {}).wdId;
  const to = (await db.collection('tos').doc(toId).get()).data();

  const ap = unwrap(await lib.callAs(uid, 'callableApplyToTO', {
    toId, slotId, businessId, businessName: to.businessName, toTitle: to.title,
    workDateMs, selectedWorkType: wd.workType, workDetailId: wdId,
    startTime: START, endTime: END, wage: wd.wage, wageType: 'hourly',
    idCardConsentGiven: true, documentAccessConsentGiven: true,
    documentAccessConsentVersion: CONSENT,
  }));
  const applicationId = ap.applicationId;
  const rev = unwrap(await lib.callAs(adminUid,
    'callableGetApplicantDocumentReview', {applicationId, businessId}));
  if (!rev.readiness.ready) {
    for (const t of ['ID', 'BANKBOOK']) {
      await lib.callAs(adminUid, 'callableReviewApplicantDocument', {
        applicationId, businessId, targetUid: rev.workerUid, documentType: t,
        decision: 'REVIEWED_OK',
        expectedVersion: t === 'ID' ? rev.versions.id : rev.versions.bankbook,
        expectedAccountVersion: rev.versions.account,
      });
    }
  }
  await lib.callAs(adminUid, 'callableConfirmApplication',
    {applicationId, businessId});

  // ── 출근 (대칭 helper 가 양쪽에 걸렸는지도 같이 본다) ─────────
  console.log('\n═══ 출근 (공용 게이트) ═══');
  await step('좌표 없이 출근', () => lib.callAs(uid, 'callableCheckIn', {
    applicationId, businessId, businessName: to.businessName,
    workDateMs, workType: wd.workType, method: 'gps',
  }));
  await step('반경 밖에서 출근', () => lib.callAs(uid, 'callableCheckIn', {
    applicationId, businessId, businessName: to.businessName,
    workDateMs, workType: wd.workType, method: 'gps',
    latitude: biz.latitude + 0.05, longitude: biz.longitude,
  }));
  const ci = await step('반경 안에서 출근', async () => {
    const r = unwrap(await lib.callAs(uid, 'callableCheckIn', {
      applicationId, businessId, businessName: to.businessName,
      workDateMs, workType: wd.workType, method: 'gps',
      latitude: biz.latitude, longitude: biz.longitude,
      scheduledStartTime: START,
    }));
    return r.attendanceId.slice(0, 26) + '…';
  });
  if (!ci.ok) throw new Error('출근 실패 — 이후 검증 불가');
  const attendanceId = `${applicationId}_${dateStr.replace(/-/g, '')}`;

  // ── 퇴근 거절 시나리오 (게이트는 반올림 이전) ────────────────
  console.log('\n═══ 퇴근 거절 (§22 2·3·4·7) ═══');
  const base = {
    attendanceId, workDateMs,
    scheduledStartTime: START, scheduledEndTime: END,
  };
  const before = (await db.collection('attendance').doc(attendanceId).get())
    .data();

  await step('좌표 없음', () =>
    lib.callAs(uid, 'callableCheckOut', {...base, method: 'gps'}));
  await step('반경 밖 (+0.05°)', () => lib.callAs(uid, 'callableCheckOut',
    {...base, method: 'gps',
      latitude: biz.latitude + 0.05, longitude: biz.longitude}));
  await step('잘못된 방식 (beacon on gps 사업장)', () =>
    lib.callAs(uid, 'callableCheckOut', {...base, method: 'beacon',
      latitude: biz.latitude, longitude: biz.longitude}));
  await step('알 수 없는 방식 (qr)', () =>
    lib.callAs(uid, 'callableCheckOut', {...base, method: 'qr',
      latitude: biz.latitude, longitude: biz.longitude}));
  await step('방식 누락', () => lib.callAs(uid, 'callableCheckOut',
    {...base, latitude: biz.latitude, longitude: biz.longitude}));
  await step('위도 범위 밖 (999)', () => lib.callAs(uid, 'callableCheckOut',
    {...base, method: 'gps', latitude: 999, longitude: biz.longitude}));

  // ── §22-10 실패한 시도의 부작용 0 ───────────────────────────
  const after = (await db.collection('attendance').doc(attendanceId).get())
    .data();
  const same = (k) => JSON.stringify(before[k] ?? null) ===
    JSON.stringify(after[k] ?? null);
  console.log('\n═══ 실패 시도의 부작용 (§22-10) ═══');
  for (const k of ['checkOut', 'originalCheckOut', 'checkOutLat',
    'checkOutLng', 'checkOutDistance', 'status', 'workHours', 'wageStatus']) {
    console.log(`  ${k.padEnd(20)} ${same(k) ? '변화 없음' : '**변했다**'}` +
      `  (${after[k] === undefined ? '없음' : '있음'})`);
  }

  fs.writeFileSync('.symfixture.json', JSON.stringify({
    businessId, adminUid, uid, toId, slotId, wdId, applicationId,
    attendanceId, workDateMs, dateStr, startTime: START, endTime: END,
    wage: wd.wage,
  }, null, 2));
  console.log('\nledger: .symfixture.json  (성공 퇴근은 END 이후 2단계에서)');
  process.exit(0);
})().catch((e) => { console.error('실패:', e.message); process.exit(1); });
