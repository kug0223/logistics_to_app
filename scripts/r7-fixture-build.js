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
  // 오늘과 어제가 모두 근무일이 되도록 두 요일을 넣는다.
  const workDays = [...new Set([kstWeekday(0), kstWeekday(-1)])];
  const wds = [S.workDetail(
      {workType: WORK_TYPE, start: '09:00', end: '18:00', required: 2})];

  const {toId} = await S.createContractPosting(ctx, {
    scenarioId: 'R7_FIX_LT_WORKER',
    title: '장기 근무 공고',
    fromOffset: -7, toOffset: 30, workDays, wds,
  });
  ctx.titleOf[toId] = '[R7FIX] 장기 근무 공고';

  const appId = await apply(ctx, {
    toId, slotId: null, wd: wds[0], workDateMs: kstMidnightMs(-7),
  });
  await confirm(ctx, appId);

  // 어제 근무 — canonical writer 로 만든다. workDateMs 가 문서 id 의 날짜다.
  const yesterdayMs = kstMidnightMs(-1);
  await callAs(ctx.workerUid, 'callableCheckIn', {
    applicationId: appId,
    businessId: ctx.businessId,
    businessName: ctx.businessName,
    workDateMs: yesterdayMs,
    workType: WORK_TYPE,
    method: 'gps',
    latitude: ctx.lat,
    longitude: ctx.lng,
    scheduledStartTime: '09:00',
  });
  await callAs(ctx.workerUid, 'callableCheckOut', {
    applicationId: appId,
    businessId: ctx.businessId,
    workDateMs: yesterdayMs,
    method: 'gps',
    latitude: ctx.lat,
    longitude: ctx.lng,
    scheduledStartTime: '09:00',
  });

  return {
    entities: {
      toId, applicationId: appId,
      yesterdayAttendanceId: `${appId}_${kstDateKey(-1).replace(/-/g, '')}`,
      workDays,
    },
    expected:
      `어제(${kstDateKey(-1)}) 근무 완료 · 오늘(${kstDateKey(0)}) 근무일이고 ` +
      'attendance 문서 없음 → 오늘 카드와 체크인 CTA 가 보여야 한다. ' +
      '어제 기록을 오늘 기록으로 쓰지 않는다.',
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
