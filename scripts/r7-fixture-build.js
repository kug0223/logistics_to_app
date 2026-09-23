/**
 * [R7-PRE0] 시나리오 실제 구성.
 *
 * 모든 상태 전이는 canonical writer(CF)로만 만든다.
 * 각 빌더는 manifest 에 남길 {entities, expected} 를 돌려준다.
 */
'use strict';

const L = require('./r7-fixture-lib');
const S = require('./r7-fixture-scenarios');

const {admin, callAs, db, kstDateKey, kstMidnightMs, kstWeekday} = L;

// ── 장기 fixture 의 근무일 계약 ──────────────────────────────────────
//
//   [CORRECTION-PRE0-LONGTERM-BACKDATED-ATTENDANCE-SEED]
//
//   fixture 는 "제품이 만들 수 있는 상태"만 만들어야 한다. 그러지 않으면
//   이후 검증이 무엇을 근거로 통과했는지 알 수 없다.
//
//   장기 근무일은 서버 `srvLongTermEligibleOnDay` 가 정한다:
//
//       effectiveStart = desiredStartDate ?? workDate
//         desiredStartDate 가 없고 확정일의 KST 날짜가 더 뒤면 확정일
//       effectiveEnd   = actualResignDate ?? workEndDate   (inclusive)
//       extraWorkDates → 근무 / leaveDates → 근무 아님 / else weekday ∈ workDays
//
//   seed 는 canonical callable 을 지나므로 서버가 결국 거절한다. 그때의
//   실패 메시지는 배치 봉투 안의 reason 코드라 원인을 읽기 어렵다.
//   무엇이 어긋났는지 **여기서** 먼저 말한다.

/** KST 날짜 YYYYMMDD 숫자. */
function kstDayNum(offsetOrMs) {
  const ms = Math.abs(offsetOrMs) > 10000 ?
    offsetOrMs : kstMidnightMs(offsetOrMs);
  return Number(new Date(ms + 9 * 3600e3).toISOString().slice(0, 10)
      .replace(/-/g, ''));
}

/**
 * 이 장기 fixture 가 만들려는 근태 날짜들이 그 지원서의 실제 근무일인가.
 * 어긋나면 던진다 — 반쯤 만들어진 fixture 를 남기지 않는다.
 */
function assertLongTermFixtureAttendanceEligible(label, {
  offsets, confirmedAtMs, workDateOffset, workEndOffset, workDays,
}) {
  const startNum = Math.max(kstDayNum(workDateOffset), kstDayNum(confirmedAtMs));
  const endNum = kstDayNum(workEndOffset);
  for (const o of offsets) {
    const d = kstDayNum(o);
    const day = kstDateKey(o);
    if (d < startNum) {
      throw new Error(
          `${label}: ${day} 는 실효 시작일(${startNum}) 이전이다 — ` +
          '확정 전 근무를 만들지 않는다.');
    }
    if (d > endNum) {
      throw new Error(`${label}: ${day} 는 계약 종료일(${endNum}) 이후다.`);
    }
    if (!workDays.includes(kstWeekday(o))) {
      throw new Error(
          `${label}: ${day}(${kstWeekday(o)}) 는 근무요일이 아니다.`);
    }
  }
}

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
    expected:
      `${dates.length}개 날짜 · 각 정원 3명. 지원·계약 fixture 가 이 공고의 ` +
      '남은 정원을 쓴다(활성 공고 4개 한도). 어느 날짜든 remaining > 0 이어야 하고, ' +
      '한 날짜에 확정이 생겨도 공고가 마감으로 바뀌면 안 된다.',
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

  // ── 확정 시점을 근무 이력 앞으로 되돌린다 ──────────────────────────
  //
  //   [CORRECTION-PRE0-LONGTERM-BACKDATED-ATTENDANCE-SEED]
  //
  //   이 fixture 가 표현하는 것은 **이미 확정되어 일해 온 장기 근로자**다.
  //   그런데 확정은 seed 를 돌리는 지금 일어나므로 confirmedAt 이 오늘이
  //   되고, 근태는 -1·-3·-5·-7 로 과거에 놓인다. 오늘 확정된 사람이
  //   지난주에 일했다는 상태는 제품 경로로 만들어질 수 없다.
  //
  //   (이 모순은 오래 보이지 않았다. 확정일 보정이 서버 근무일 판정에
  //    들어오기 전에는 아무도 confirmedAt 을 보지 않았기 때문이다.)
  //
  //   고칠 자리는 시각 하나다. 근태 날짜를 미래로 옮기면 "과거 근무 이력"
  //   이라는 시나리오 목적 자체가 사라지므로, 확정 시각을 가장 이른
  //   근무일 아침(그날 06:00 근무 시작 전)으로 되돌린다.
  //
  //   약속(workDate·workEndDate·workDays·임금·시간)은 건드리지 않는다 —
  //   어긋난 것은 연대기뿐이다.
  const attendanceOffsets = [-7, -5, -3, -1];
  const seedAppliedAtMs = kstMidnightMs(-8) + 9 * 3600e3;   // -8일 09:00 KST
  const seedConfirmedAtMs = kstMidnightMs(-7) + 5 * 3600e3; // -7일 05:00 KST

  assertLongTermFixtureAttendanceEligible('장기 근무자 fixture', {
    offsets: attendanceOffsets,
    confirmedAtMs: seedConfirmedAtMs,
    workDateOffset: -14,
    workEndOffset: 30,
    workDays,
  });

  await db.collection('applications').doc(appId).update({
    appliedAt: admin.firestore.Timestamp.fromMillis(seedAppliedAtMs),
    confirmedAt: admin.firestore.Timestamp.fromMillis(seedConfirmedAtMs),
  });

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
  // 위 assert 가 검사한 목록과 실제로 만드는 날짜가 같아야 한다 —
  // 한쪽만 고치면 검사하지 않은 날짜가 조용히 생긴다.
  {
    const made = [-1, ...stages.map((s) => s.offset)].sort((a, b) => a - b);
    const checked = [...attendanceOffsets].sort((a, b) => a - b);
    if (made.join() !== checked.join()) {
      throw new Error(
          `장기 fixture: 검사한 날짜(${checked})와 만드는 날짜(${made})가 다르다.`);
    }
  }

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

// ── 기존 공고 재사용 ────────────────────────────────────────────────
//
//   [MAX_ACTIVE_TO_LIMIT] 활성 공고 수는 제품이 오너 단위로 4개까지만
//   허용한다(users/{owner}.maxActiveTOs 로 오너별 상향 가능, 기본 4).
//   DEV 는 이미 R7FIX 3개 + 기존 테스트 공고 1개로 4를 채우고 있다.
//
//   한도를 올리는 것은 제품 설정 변경이고, 우회는 더 나쁘다. 그래서
//   지원·계약 fixture 는 새 공고를 만들지 않고 SHORTAGE 공고의 남은
//   정원을 쓴다. 정원이 날짜마다 3명이라 한 명씩 확정해도 여전히 부족이
//   남는다 — SHORTAGE 의 계약(remaining > 0)이 깨지지 않는다.
//   한도가 4인 사업장이 실제로 하는 일이기도 하다.

/** SHORTAGE 공고의 n번째 날짜 슬롯. */
async function shortageSlot(ctx, index) {
  const rec = (ctx.manifest.scenarios || {}).R7_FIX_POST_SHORTAGE;
  const toId = rec && rec.entities && rec.entities.toId;
  if (!toId) throw new Error('R7_FIX_POST_SHORTAGE 가 먼저 있어야 합니다.');
  const slots = await slotsOf(toId);
  if (slots.length <= index) {
    throw new Error(`SHORTAGE 공고에 ${index + 1}번째 슬롯이 없습니다.`);
  }
  const s = slots[index];
  const to = (await db.collection('tos').doc(toId).get()).data();
  ctx.titleOf[toId] = to.title || '[R7FIX] 부족 남은 공고';
  return {
    toId, slotId: s.id, wd: (s.workDetails || [])[0],
    workDateMs: s.date.toMillis(),
    dateKey: kstDateKey(0) && new Date(s.date.toMillis() + 9 * 3600e3)
        .toISOString().slice(0, 10),
  };
}

/**
 * 지원만 하고 확정하지 않는다 — 지원 = 관심.
 *
 * 확정 인원과 지원 인원을 한 숫자로 합치는 표면이 있는지 보려면
 * "확정 0 · 지원 1" 인 날짜가 하나 필요하다.
 */
async function buildAppPending(ctx) {
  const s = await shortageSlot(ctx, 1);
  const appId = await apply(ctx, {
    toId: s.toId, slotId: s.slotId, wd: s.wd, workDateMs: s.workDateMs,
  });
  return {
    entities: {
      sharedToId: s.toId, slotId: s.slotId, dateKey: s.dateKey,
      applicationId: appId,
    },
    expected:
      `${s.dateKey} (SHORTAGE 공고) 정원 3명 · 확정 0 · 지원 1(PENDING). ` +
      '지원자 명단에는 1명이 보이고 확정 인원은 0이어야 한다. ' +
      '지원 1건을 확정 1건으로 세는 표면이 있으면 그것이 결함이다.',
  };
}

// ── 계약 ────────────────────────────────────────────────────────────

/**
 * 계약서 한 벌.
 *
 * 클라이언트 ContractService._createNew 가 만드는 모양을 그대로 따른다.
 * snapshot 은 사업장·근로자·근무조건의 서명 시점 사본이다 — 서버가
 * 내용을 검증하지 않으므로 여기가 정확해야 계약서 화면이 정상으로 보인다.
 */
async function contractData(ctx, {applicationId, app, dateKey, wd, isLong}) {
  const biz = ctx.biz;
  const worker = ctx.worker;
  const addr = [biz.address, biz.detailAddress].filter(Boolean).join(' ');
  const workerAddr = [worker.address, worker.detailAddress].filter(Boolean).join(' ').trim();
  const bn = String(biz.businessNumber || '').replace(/\D/g, '');
  return {
    applicationId,
    businessId: ctx.businessId,
    businessName: ctx.businessName,
    workerId: ctx.workerUid,
    isLongTerm: isLong,
    toId: app.toId || '',
    workDetailId: app.wdId || app.workDetailId || '',
    slots: isLong ? [] : [{
      applicationId,
      workDate: dateKey,
      startTime: wd.startTime,
      endTime: wd.endTime,
      wage: wd.wage,
      wageType: wd.wageType,
    }],
    applicationIds: [applicationId],
    snapshot: {
      businessName: biz.name || '',
      businessNumber: bn.length === 10
        ? `${bn.slice(0, 3)}-${bn.slice(3, 5)}-${bn.slice(5)}` : bn,
      businessAddress: addr,
      businessPhone: biz.phone || null,
      ownerName: biz.ownerName || '',
      workerName: worker.name || '',
      workerBirthDate: worker.birthDate
        ? new Date(worker.birthDate.toMillis() + 9 * 3600e3)
            .toISOString().slice(0, 10)
        : null,
      workerPhone: worker.authPhone || worker.phone || null,
      workerAddress: workerAddr || null,
      workType: wd.workType,
      workPlace: biz.address || '',
      isLongTerm: isLong,
      contractStart: isLong ? dateKey : null,
      contractEnd: null,
      workDays: isLong ? (app.workDays || []) : null,
      startTime: wd.startTime,
      endTime: wd.endTime,
      breakMinutes: wd.breakMinutes || 0,
      wage: wd.wage,
      wageType: wd.wageType,
      wagePaymentDay: biz.wagePaymentDay ?? null,
      paymentMethod: '계좌이체',
      baseHourlyWage: null,
      payScheduleType: wd.payScheduleType || 'same_day',
    },
    articles: [],
    templateId: null,
  };
}

/** 확정된 지원서 하나에 계약서를 만들고 사업주 서명까지 — pending_worker. */
async function issueContract(ctx, {applicationId, dateKey, wd, isLong}) {
  const app = (await db.collection('applications').doc(applicationId).get()).data();
  // contractId 는 클라이언트가 정한다(Firestore auto-id). 같은 규칙을 쓴다.
  const contractId = db.collection('employment_contracts').doc().id;
  await callAs(ctx.adminUid, 'callableFinalizeEmployerSignature', {
    contractId,
    signatureBase64: S.signaturePng().toString('base64'),
    isNewUnsaved: true,
    contractData: await contractData(ctx, {applicationId, app, dateKey, wd, isLong}),
  });
  return contractId;
}

/** 근로자 서명 → 계약 completed + 지원서 CONFIRMED. */
async function signAsWorker(ctx, contractId, pdfLines) {
  await callAs(ctx.workerUid, 'callableFinalizeWorkerSignature', {
    contractId,
    signatureBase64: S.signaturePng(200, 80).toString('base64'),
    pdfBase64: S.onePagePdf(pdfLines).toString('base64'),
  });
}

/** 근로자 서명 대기 계약. */
async function buildContractPendingWorker(ctx) {
  const s = await shortageSlot(ctx, 0);
  const appId = await apply(ctx, {
    toId: s.toId, slotId: s.slotId, wd: s.wd, workDateMs: s.workDateMs,
  });
  await confirm(ctx, appId);
  const contractId = await issueContract(ctx, {
    applicationId: appId, dateKey: s.dateKey, wd: s.wd, isLong: false,
  });

  return {
    entities: {
      sharedToId: s.toId, slotId: s.slotId, dateKey: s.dateKey,
      applicationId: appId, contractId,
    },
    expected:
      'employment_contracts.status = pending_worker · 지원서 CONTRACT_PENDING. ' +
      '근로자에게 서명 CTA 가 보이고, 관리자 계약 목록에는 "서명 대기"로 보인다. ' +
      '계약 미완료를 확정 취소로 표시하면 안 된다.',
  };
}

/**
 * 계약 완료 — 지원서가 CONFIRMED 가 되는 유일한 정상 경로.
 *
 * 독립 CONFIRMED fixture 를 따로 만들지 않는다. callableConfirmApplication 은
 * CONTRACT_PENDING 까지만 보내고, CONFIRMED 는 근로자 서명(또는 초대 수락)이
 * 만든다. 그 전이를 실제로 태워서 확인하는 것이 confirmed-family 커버리지다.
 */
async function buildContractCompleted(ctx) {
  const s = await shortageSlot(ctx, 2);
  const appId = await apply(ctx, {
    toId: s.toId, slotId: s.slotId, wd: s.wd, workDateMs: s.workDateMs,
  });
  await confirm(ctx, appId);
  const contractId = await issueContract(ctx, {
    applicationId: appId, dateKey: s.dateKey, wd: s.wd, isLong: false,
  });
  await signAsWorker(ctx, contractId, [
    'ALfit R7 fixture - employment contract',
    `contract: ${contractId}`,
    `work date: ${s.dateKey}  ${s.wd.startTime}-${s.wd.endTime}`,
    'This document is DEV test data. Not a real contract.',
  ]);

  const after = (await db.collection('applications').doc(appId).get()).data();
  if (after.status !== 'CONFIRMED') {
    throw new Error(
        `계약 완료 후에도 지원서가 CONFIRMED 가 아닙니다: ${after.status}`);
  }

  return {
    entities: {
      sharedToId: s.toId, slotId: s.slotId, dateKey: s.dateKey,
      applicationId: appId, contractId,
    },
    expected:
      'employment_contracts.status = completed · 지원서 CONFIRMED. ' +
      'CONFIRMED 는 이 경로(또는 초대 수락)로만 도달한다 — 독립 생성 경로가 없다. ' +
      '확정 1명이 공고·지원명단·업무상세·Home 에서 모두 같은 1명이어야 한다.',
  };
}

// ── 신뢰도 ──────────────────────────────────────────────────────────
//
//   노쇼 fixture 는 만들지 않는다. canonical writer(callableBatchSetNoShow)는
//   있고 동작하지만, 그 부수 효과가 DEV 를 못 쓰게 만든다 —
//   90일 내 3회가 되면 users.restrictedUntil 이 서고 그 계정은 지원이 막힌다.
//   DEV 근로자 계정은 하나뿐이고 이미 노쇼 2건이 있어서, 한 건만 더 만들면
//   나머지 fixture 를 seed 할 수 없다(실제로 한 번 그렇게 막혔다).
//   기존 노쇼 2건을 reliability 참조로 쓴다. 자세한 이유는
//   seed-r7-fixtures-dev.js 의 NOT_SEEDED 에 적어 뒀다.

module.exports = {
  WORK_TYPE,
  slotsOf,
  apply,
  confirm,
  // 근무일 계약은 Firestore 없이도 확인할 수 있어야 한다 — 그래야
  // seed 를 돌리지 않고도 이 규칙이 살아 있는지 볼 수 있다.
  assertLongTermFixtureAttendanceEligible,
  builders: {
    R7_FIX_POST_SHORTAGE: buildPostShortage,
    R7_FIX_POST_MIXED: buildPostMixed,
    R7_FIX_POST_CLOSED: buildPostClosed,
    R7_FIX_LT_WORKER: buildLongTermWorker,
    R7_FIX_APP_PENDING: buildAppPending,
    R7_FIX_CONTRACT_PW: buildContractPendingWorker,
    R7_FIX_CONTRACT_DONE: buildContractCompleted,
  },
};
