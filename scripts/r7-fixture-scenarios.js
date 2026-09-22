/**
 * [R7-PRE0] 시나리오 빌더.
 *
 * 각 빌더는 canonical writer 만 불러 상태를 만들고, manifest 에 남길
 * entity id 와 "기대 사실"을 돌려준다. R7 에서 스크린샷·버그 보고가
 * 이 id 를 그대로 참조한다.
 *
 * 규칙
 *   · 불가능한 조합을 만들지 않는다 — CF 를 지나면 애초에 만들어지지 않는다.
 *   · 랜덤 대량 생성하지 않는다. 각 fixture 는 확인 목적이 하나씩 있다.
 *   · 실패하면 던진다. 반쯤 만들어진 상태로 넘어가지 않는다.
 */
'use strict';

const {callAs, kstMidnightMs, kstDateKey, kstWeekday} = require('./r7-fixture-lib');

const TITLE_PREFIX = '[R7FIX]';

/**
 * 업무 상세 한 벌. wdId 는 CF(createFlexSlots)가 부여한다.
 *
 * payScheduleType 은 서버 필수값이다 — 없으면 공고 생성이 거절된다.
 * (근태 레코드의 payScheduleType 이 null 인 상태는 이것과 다른 축이다.
 *  그건 정산 전이라 wageDetail 자체가 없는 경우다 — PAY-01 참조.)
 */
function workDetail({
  workType, start, end, required, wage = 12000,
  payScheduleType = 'same_day', payScheduleDay,
}) {
  return {
    workType,
    workTypeIcon: '📋',
    startTime: start,
    endTime: end,
    requiredCount: required,
    wage,
    wageType: 'hourly',
    breakMinutes: 0,
    nightAllowanceApplied: true,
    nightIncluded: false,
    weeklyHolidayIncluded: false,
    payScheduleType,
    ...(payScheduleDay != null ? {payScheduleDay} : {}),
  };
}

/** flex 공고 생성 + 슬롯 + 공개. createTO 의 클라이언트 오케스트레이션과 같은 순서. */
async function createFlexPosting(ctx, {scenarioId, title, dayOffsets, wds}) {
  const dates = dayOffsets.map((o) => kstDateKey(o));
  const toData = {
    businessId: ctx.businessId,
    businessName: ctx.businessName,
    type: 'flex',
    title: `${TITLE_PREFIX} ${title}`,
    description: `R7 fixture — ${scenarioId}`,
    workDetails: wds,
    totalSlots: dates.length,
    totalRequired: wds.reduce((s, w) => s + w.requiredCount, 0) * dates.length,
    totalConfirmed: 0,
    totalPending: 0,
    rangeStart: kstMidnightMs(Math.min(...dayOffsets)),
    rangeEnd: kstMidnightMs(Math.max(...dayOffsets)),
    workDays: [],
    deadlineType: 'HOURS_BEFORE',
    hoursBeforeStart: 2,
    postingDurationDays: 30,
    creatorUID: ctx.adminUid,
    // 슬롯이 생기기 전에 공개되지 않게 — 클라이언트와 같은 deferred 경로.
    publishMode: 'deferred',
    isPublished: false,
    status: 'SCHEDULED',
    isManualClosed: false,
  };

  const created = await callAs(ctx.adminUid, 'callableCreateTO', {toData});
  const toId = created.toId;

  await callAs(ctx.adminUid, 'callableCreateFlexSlots', {
    toId,
    businessId: ctx.businessId,
    dates,
    workDetails: wds,
    deadlineType: 'HOURS_BEFORE',
    hoursBeforeStart: 2,
    publishMode: 'immediate',
  });

  await callAs(ctx.adminUid, 'callablePublishTO', {toId});
  return {toId, dates};
}

/** contract(장기) 공고 생성 + 공개. 슬롯이 없다. */
async function createContractPosting(ctx, {scenarioId, title, fromOffset, toOffset, workDays, wds}) {
  const toData = {
    businessId: ctx.businessId,
    businessName: ctx.businessName,
    type: 'contract',
    title: `${TITLE_PREFIX} ${title}`,
    description: `R7 fixture — ${scenarioId}`,
    workDetails: wds,
    totalSlots: 0,
    totalRequired: wds.reduce((s, w) => s + w.requiredCount, 0),
    totalConfirmed: 0,
    totalPending: 0,
    rangeStart: kstMidnightMs(fromOffset),
    rangeEnd: kstMidnightMs(toOffset),
    workDays,
    deadlineType: 'HOURS_BEFORE',
    hoursBeforeStart: 2,
    contractPeriodType: 'custom',
    postingDurationDays: 30,
    creatorUID: ctx.adminUid,
    publishMode: 'immediate',
    isPublished: true,
    status: 'ACTIVE',
    isManualClosed: false,
  };
  const created = await callAs(ctx.adminUid, 'callableCreateTO', {toData});
  return {toId: created.toId};
}

/** 슬롯 목록 조회 — 지원에 필요한 slotId/wdId 를 얻는다. */
async function readSlots(ctx, toId) {
  const snap = await ctx.db.collection('tos').doc(toId)
      .collection('slots').orderBy('date').get();
  return snap.docs.map((d) => ({
    slotId: d.id,
    date: d.data().date,
    workDetails: d.data().workDetails || [],
  }));
}

module.exports = {
  TITLE_PREFIX,
  workDetail,
  createFlexPosting,
  createContractPosting,
  readSlots,
  kstDateKey,
  kstWeekday,
  kstMidnightMs,
};
