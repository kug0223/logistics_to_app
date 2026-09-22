/**
 * [R7-PRE0] 시나리오 실제 구성.
 *
 * 모든 상태 전이는 canonical writer(CF)로만 만든다.
 * 각 빌더는 manifest 에 남길 {entities, expected} 를 돌려준다.
 */
'use strict';

const L = require('./r7-fixture-lib');
const S = require('./r7-fixture-scenarios');

const {callAs, db, kstDateKey, kstMidnightMs, kstWeekday} = L;

// ── 공통 ────────────────────────────────────────────────────────────
const WORK_TYPE = '사무업무'; // 사업장에 등록된 업무만 허용된다(서버 검증).

async function slotsOf(toId) {
  const snap = await db.collection('tos').doc(toId)
      .collection('slots').orderBy('date').get();
  return snap.docs.map((d) => ({id: d.id, ...d.data()}));
}

// 서버 allowlist 와 일치해야 한다 (functions DOCUMENT_ACCESS_CONSENT_V3).
// 지원은 소득신고 목적 신분증 열람 동의 없이는 서버가 거절한다.
const CONSENT_VERSION = '2026-09-18-v3';

/** 근로자 지원 → PENDING application. */
async function apply(ctx, {toId, slotId, wd, workDateMs, extra}) {
  const r = await callAs(ctx.workerUid, 'callableApplyToTO', {
    // 서버가 요구하는 두 동의. 앱의 지원 시트가 보내는 것과 같다.
    idCardConsentGiven: true,
    documentAccessConsentGiven: true,
    documentAccessConsentVersion: CONSENT_VERSION,
    toId,
    slotId,
    businessId: ctx.businessId,
    businessName: ctx.businessName,
    toTitle: ctx.titleOf[toId] || 'R7 fixture',
    selectedWorkType: wd.workType,
    // wdId 는 서버가 슬롯 workDetail 에서 직접 정한다 — 클라이언트가 보내지 않는다.
    workDetailId: wd.wdId,
    startTime: wd.startTime,
    endTime: wd.endTime,
    workDateMs,
    wage: wd.wage,
    wageType: wd.wageType,
    ...(extra || {}),
  });
  return r.applicationId || r.id;
}

/**
 * 배치 CF 는 항목 단위 실패를 200 안에 담아 돌려준다.
 *
 *   {success:true, processed:0, failed:1, failures:[{reason:'unknownError'}]}
 *
 * HTTP 상태만 보면 "성공"이라 seed 가 아무것도 만들지 않고 넘어간다.
 * 실제로 그렇게 한 번 속았다 — 봉투를 열어 본다.
 */
function assertBatchOk(result, label) {
  const failed = (result && result.failed) || 0;
  if (failed > 0) {
    const first = (result.failures || [])[0] || {};
    throw new Error(
        `${label}: ${failed}/${result.total}건 실패 (reason=${first.reason || '?'})`);
  }
  if (result && result.processed === 0) {
    throw new Error(`${label}: 처리된 항목이 없습니다.`);
  }
  return result;
}

/** 관리자 확정 → CONFIRMED / CONTRACT_PENDING. */
async function confirm(ctx, applicationId) {
  return callAs(ctx.adminUid, 'callableConfirmApplication', {
    applicationId,
    businessId: ctx.businessId,
  });
}

// ── 빌더 ────────────────────────────────────────────────────────────

/** 부족이 남아 있는 flex 공고. */
async function buildPostShortage(ctx) {
  const wds = [S.workDetail(
      {workType: WORK_TYPE, start: '09:00', end: '18:00', required: 3})];
  const {toId, dates} = await S.createFlexPosting(ctx, {
    scenarioId: 'R7_FIX_POST_SHORTAGE',
    title: '부족 남은 공고', dayOffsets: [3, 4, 5], wds,
  });
  ctx.titleOf[toId] = '[R7FIX] 부족 남은 공고';
  return {
    entities: {toId, dates},
    expected: `${dates.length}개 날짜 · 각 정원 3명 · 확정 0 → 모든 날짜 remaining 3`,
  };
}

/** 한 날짜는 FULL, 다른 날짜는 부족. 공고 전체가 닫히면 안 된다. */
async function buildPostMixed(ctx) {
  const wds = [S.workDetail(
      {workType: WORK_TYPE, start: '10:00', end: '16:00', required: 1})];
  const {toId, dates} = await S.createFlexPosting(ctx, {
    scenarioId: 'R7_FIX_POST_MIXED',
    title: '한 날짜만 마감', dayOffsets: [6, 7], wds,
  });
  ctx.titleOf[toId] = '[R7FIX] 한 날짜만 마감';

  // 첫 날짜만 정원을 채운다 → 그 날짜 FULL, 다음 날짜는 부족.
  const slots = await slotsOf(toId);
  const first = slots[0];
  const wd = (first.workDetails || [])[0];
  const appId = await apply(ctx, {
    toId, slotId: first.id, wd, workDateMs: first.date.toMillis(),
  });
  await confirm(ctx, appId);

  return {
    entities: {toId, dates, fullSlotId: first.id, confirmedApplicationId: appId},
    expected:
      `${dates[0]} 정원 1/1 → FULL, ${dates[1]} 정원 0/1 → 부족. ` +
      '공고 전체를 FULL/종료로 닫으면 안 된다.',
  };
}

/** 수동 전체 종료. */
async function buildPostClosed(ctx) {
  const wds = [S.workDetail(
      {workType: WORK_TYPE, start: '13:00', end: '17:00', required: 2})];
  const {toId, dates} = await S.createFlexPosting(ctx, {
    scenarioId: 'R7_FIX_POST_CLOSED',
    title: '수동 종료 공고', dayOffsets: [8, 9], wds,
  });
  ctx.titleOf[toId] = '[R7FIX] 수동 종료 공고';
  await callAs(ctx.adminUid, 'callableCloseTOManually', {toId});
  return {
    entities: {toId, dates},
    expected: '종료 탭에만 보인다. 슬롯 preload 대상에서 빠진다(R8-P9F).',
  };
}

/**
 * 장기 근무자 + 어제 완료 근태.
 *
 * R8-P9E 에서 DEV 데이터가 없어 재현하지 못한 바로 그 상태다.
 *   어제 근무 완료(checkOut 있음) + 오늘도 근무일 + 오늘 문서 없음
 *   → 오늘 카드와 체크인 CTA 가 살아 있어야 한다.
 */
async function buildLongTermWorker(ctx) {
  // 전 요일을 근무일로 둔다.
  //   오늘·어제가 모두 근무일이어야 하고(LT-ATT-01), 급여 4상태를 만들려면
  //   과거 근무일이 여러 날 필요하다. 한 근무자의 이력으로 묶는 편이
  //   fixture 수를 늘리지 않으면서 실제 운영에 더 가깝다.
  const workDays = ['월', '화', '수', '목', '금', '토', '일'];

  // [중복 근무 가드] 서버는 같은 날 시간이 겹치는 확정 근무를 거절한다.
  //   DEV 근로자에게는 09:00~18:00 · 13:00~19:00 대의 확정 근무가 이미 있다.
  //   fixture 는 아무 데도 겹치지 않는 이른 시간대를 쓰고, 계약 기간도
  //   어제부터로 좁혀 과거 확정 건과 부딪히지 않게 한다.
  const wds = [S.workDetail(
      {workType: WORK_TYPE, start: '06:00', end: '08:00', required: 2})];

  const {toId} = await S.createContractPosting(ctx, {
    scenarioId: 'R7_FIX_LT_WORKER',
    title: '장기 근무 공고',
    fromOffset: -14, toOffset: 30, workDays, wds,
  });
  ctx.titleOf[toId] = '[R7FIX] 장기 근무 공고';

  const appId = await apply(ctx, {
    toId, slotId: null, wd: wds[0], workDateMs: kstMidnightMs(-14),
  });
  await confirm(ctx, appId);

  // ── 어제 근무를 완료 상태로 기록한다 ─────────────────────────────
  //
  //   근로자용 callableCheckIn/CheckOut 은 **서버 현재 시각**을 실제
  //   출퇴근 시각으로 쓴다. 그래서 어제 근무를 그 경로로 완결할 수 없다 —
  //   퇴근 시각(어제 08:00)이 출근 시각(오늘 지금)보다 앞서서 서버가 거절한다.
  //
  //   관리자 배치 경로는 시각을 명시로 받는다. 지난 근무를 관리자가
  //   기록하는 것이 실제 운영이기도 하다. canonical writer 를 유지하면서
  //   과거 시각을 쓸 수 있는 유일한 길이다.
  const yesterdayMs = kstMidnightMs(-1);
  const at = (hh, mm) => yesterdayMs + (hh * 60 + mm) * 60 * 1000;
  const yesterdayAttendanceId =
      `${appId}_${kstDateKey(-1).replace(/-/g, '')}`;

  // attendanceId 는 **기존 레코드를 고칠 때만** 넘긴다(CF 주석). 새로 만들
  //   때 넘기면 없는 문서를 고치려다 unknownError 로 조용히 실패한다.
  //   문서 id 는 서버가 applicationId + workDateMs 로 만든다.
  assertBatchOk(await callAs(ctx.adminUid, 'callableBatchCheckIn', {
    businessId: ctx.businessId,
    entries: [{
      applicationId: appId,
      workDateMs: yesterdayMs,
      userId: ctx.workerUid,
      businessId: ctx.businessId,
      businessName: ctx.businessName,
      workType: WORK_TYPE,
      status: 'present',
      checkInMs: at(6, 0),
    }],
  }), 'batchCheckIn');

  assertBatchOk(await callAs(ctx.adminUid, 'callableBatchCheckOut', {
    businessId: ctx.businessId,
    entries: [{
      attendanceId: yesterdayAttendanceId,
      checkOutMs: at(8, 0),
      workHours: 2,
      status: 'present',
      resetWageDetail: false,
    }],
  }), 'batchCheckOut');

  // ── 급여 4상태 ────────────────────────────────────────────────
  //
  //   한 근무자의 이력으로 묶는다. 지난 근무일 셋을 더 만들고 각각
  //   다른 단계까지만 전이시킨다.
  //     -1 pending      근태만 있고 정산 전 (wageDetail 자체가 없다)
  //     -3 calculated   계산까지
  //     -5 confirmed    확정까지
  //     -7 transferred  이체까지
  //
  //   callableCalculateAndConfirmWage 는 이름과 달리 `calculated` 까지만
  //   쓴다. `confirmed` 는 callableConfirmFinalWage 가 따로 한다.
  //   그래서 calculated 가 독립 상태로 성립한다 — 직접 write 가 필요 없다.
  const payroll = {pendingAttendanceId: yesterdayAttendanceId};
  const stages = [
    {offset: -3, upto: 'calculated', key: 'calculatedAttendanceId'},
    {offset: -5, upto: 'confirmed', key: 'confirmedAttendanceId'},
    {offset: -7, upto: 'transferred', key: 'transferredAttendanceId'},
  ];

  for (const s of stages) {
    const ms = kstMidnightMs(s.offset);
    const dayKey = kstDateKey(s.offset);
    const attId = `${appId}_${dayKey.replace(/-/g, '')}`;
    const atDay = (hh) => ms + hh * 3600 * 1000;

    assertBatchOk(await callAs(ctx.adminUid, 'callableBatchCheckIn', {
      businessId: ctx.businessId,
      entries: [{
        applicationId: appId, workDateMs: ms, userId: ctx.workerUid,
        businessId: ctx.businessId, businessName: ctx.businessName,
        workType: WORK_TYPE, status: 'present', checkInMs: atDay(6),
      }],
    }), `batchCheckIn(${dayKey})`);

    assertBatchOk(await callAs(ctx.adminUid, 'callableBatchCheckOut', {
      businessId: ctx.businessId,
      entries: [{
        attendanceId: attId, checkOutMs: atDay(8), workHours: 2,
        status: 'present', resetWageDetail: false,
      }],
    }), `batchCheckOut(${dayKey})`);

    await callAs(ctx.adminUid, 'callableCalculateAndConfirmWage', {
      attendanceId: attId,
      wageType: 'hourly', baseWage: wds[0].wage, workDate: dayKey,
      scheduledStart: '06:00', scheduledEnd: '08:00',
      actualStart: '06:00', actualEnd: '08:00',
      breakMinutes: 0,
      nightAllowanceApplied: true, nightIncluded: false,
      taxDeductionType: 'none',
      yearMonth: dayKey.slice(0, 7),
      payScheduleType: 'same_day',
    });

    if (s.upto === 'confirmed' || s.upto === 'transferred') {
      await callAs(ctx.adminUid, 'callableConfirmFinalWage',
          {businessId: ctx.businessId, attendanceIds: [attId]});
    }
    if (s.upto === 'transferred') {
      await callAs(ctx.adminUid, 'callableMarkTransferredBatch', {
        businessId: ctx.businessId, attendanceIds: [attId],
        transferNote: 'R7 fixture',
      });
    }
    payroll[s.key] = attId;
  }

  return {
    entities: {
      toId, applicationId: appId,
      yesterdayAttendanceId,
      workDays,
      payroll,
    },
    expected:
      `어제(${kstDateKey(-1)}) 근무 완료 · 오늘(${kstDateKey(0)}) 근무일이고 ` +
      'attendance 문서 없음 → 오늘 카드와 체크인 CTA 가 보여야 한다. ' +
      '어제 기록을 오늘 기록으로 쓰지 않는다. ' +
      '급여는 pending/calculated/confirmed/transferred 네 상태가 각각 하루씩. ' +
      '근무일·근무시간은 4일·8h 인데 확정분만 세는 화면은 2일·4h 로 보인다 ' +
      '(금액은 맞다 — metric 정의 문제, R7 확인 항목).',
  };
}

module.exports = {
  WORK_TYPE,
  slotsOf,
  apply,
  confirm,
  builders: {
    R7_FIX_POST_SHORTAGE: buildPostShortage,
    R7_FIX_POST_MIXED: buildPostMixed,
    R7_FIX_POST_CLOSED: buildPostClosed,
    R7_FIX_LT_WORKER: buildLongTermWorker,
  },
};
