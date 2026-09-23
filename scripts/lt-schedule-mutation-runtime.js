#!/usr/bin/env node
/**
 * [PRELAUNCH-LONGTERM-LIFECYCLE-INTEGRITY.3]
 * 장기 근로자의 일정 예외 — 휴무 · 추가근무 · 상호전환 · 취소 DEV 실행.
 *
 * 묻는 것은 하나다:
 *
 *   schedule_change_request 승인
 *   → Application.leaveDates / extraWorkDates
 *   → canonical worker-day eligibility
 *   → Staffing(Home · 하루 상세)
 *   → Attendance / NO_SHOW eligibility
 *
 *   이 전부가 같은 날짜에 대해 **같은 사실**을 말하는가?
 *
 * 전용 fixture 를 쓴다. R7_FIX_LT_WORKER 는 건드리지 않는다.
 *
 *   node scripts/lt-schedule-mutation-runtime.js --project alfit-89567
 *   node scripts/lt-schedule-mutation-runtime.js --project alfit-89567 --execute
 *   node scripts/lt-schedule-mutation-runtime.js --project alfit-89567 --cleanup --execute
 */
'use strict';

const EXPECTED_DEV_PROJECT = 'alfit-89567';
const PROD_PROJECT_ID = 'alfit-prod';
const argv = process.argv.slice(2);
const projectId = (() => {
  const i = argv.indexOf('--project');
  return i >= 0 ? argv[i + 1] : null;
})();
if (projectId === PROD_PROJECT_ID) {
  console.error('PROD 프로젝트입니다. 실행하지 않습니다.');
  process.exit(2);
}
if (projectId !== EXPECTED_DEV_PROJECT) {
  console.error(`DEV 전용입니다. --project ${EXPECTED_DEV_PROJECT}`);
  process.exit(2);
}
const EXECUTE = argv.includes('--execute');
const CLEANUP = argv.includes('--cleanup');

const fs = require('fs');
const path = require('path');
const {db, callAs, devBucket, kstMidnightMs, kstDateKey} =
  require('./r7-fixture-lib');
const S = require('./r7-fixture-scenarios');

// ── DEV 고정 ────────────────────────────────────────────────────────
const BIZ = 'fLmSOHVKUwmBHcbwQE0I';
const ADMIN = 'BErRdiWP1xbgyoTovxwAPNEsuD72';
const WORKER = 'tJ8izfP2nNYN79aPTLb6YARiPqC3';
// 이 사업장의 SubAdmin — canManageWorkers 를 갖고 있으므로 §40 의
// "권한 있는 관리자" 쪽 증거가 된다. 권한 없는 actor 는 근로자 본인.
const SUBADMIN = 'kN2gNpEhLLVjQD7KLGSnNFJHd2v2';
const WORK_TYPE = '사무업무';
const CONSENT_VERSION = '2026-09-18-v3';
const NS = 'LTSCHED';
const STATE = path.join(__dirname, '.lt-schedule-runtime-state.json');

// 근로자의 기존 확정 근무(06:00~08:00 장기 · 09:00~19:00 대 · 23:00 대)와
// 겹치지 않는 창. 서버는 시간이 겹치는 확정 근무가 있으면 지원을 거절한다.
const START_TIME = '01:00';
const END_TIME = '02:30';
const WAGE = 14000;
// §8 — E(비근무일)가 존재하려면 workDays 가 전 요일이면 안 된다.
const WORK_DAYS = ['월', '화', '수', '목', '금'];
const FROM_OFFSET = -2;
const TO_OFFSET = 27;

const KST = 9 * 3600e3;
const WK = ['일', '월', '화', '수', '목', '금', '토'];
const iso = (ts) => ts ?
  new Date(ts.toMillis() + KST).toISOString().slice(0, 10) : null;
const dnumOfMs = (ms) =>
  Number(new Date(ms + KST).toISOString().slice(0, 10).replace(/-/g, ''));
const wkdOfOffset = (o) => WK[new Date(kstMidnightMs(o) + KST).getUTCDay()];

const log = (...a) => console.log(...a);
const head = (s) => log(`\n${'─'.repeat(74)}\n${s}\n${'─'.repeat(74)}`);
const results = [];
const check = (label, ok, detail) => {
  results.push({label, ok});
  log(`${ok ? 'PASS' : 'FAIL'}  ${label}${detail ? `\n        ${detail}` : ''}`);
};
const readState = () =>
  fs.existsSync(STATE) ? JSON.parse(fs.readFileSync(STATE, 'utf8')) : {};
const writeState = (s) => fs.writeFileSync(STATE, JSON.stringify(s, null, 2));

// ══════════════════════════════════════════════════════════════════
// canonical worker-day resolver 의 거울 — 서버 srvLongTermEligibleOnDay.
// ══════════════════════════════════════════════════════════════════
function eligibility(app, dayNum, wkd) {
  let start = app.desiredStartDate ?
    dnumOfMs(app.desiredStartDate.toMillis()) :
    (app.workDate ? dnumOfMs(app.workDate.toMillis()) : 0);
  if (!app.desiredStartDate && app.confirmedAt) {
    const c = dnumOfMs(app.confirmedAt.toMillis());
    if (c > start) start = c;
  }
  if (dayNum < start) return 'BEFORE_START';
  const resign = app.actualResignDate;
  const end = resign || app.workEndDate;
  if (!end) return 'NO_END';
  if (dayNum > dnumOfMs(end.toMillis())) return resign ? 'AFTER_RESIGN' : 'AFTER_END';
  const has = (k) => Array.isArray(app[k]) &&
    app[k].some((t) => t && t.toMillis && dnumOfMs(t.toMillis()) === dayNum);
  if (has('extraWorkDates')) return 'WORK';
  if (has('leaveDates')) return 'NO_WORK';
  return (app.workDays || []).includes(wkd) ? 'WORK' : 'NO_WORK';
}

async function loadApp(id) {
  return (await db.collection('applications').doc(id).get()).data();
}
const dateArr = (app, k) =>
  ((app[k] || []).map((t) => dnumOfMs(t.toMillis()))).sort();

async function inventory(label) {
  const [ap, ec, scr, at, tos] = await Promise.all([
    db.collection('applications').get(),
    db.collection('employment_contracts').get(),
    db.collection('schedule_change_requests').get(),
    db.collection('attendance').get(),
    db.collection('tos').get(),
  ]);
  const [files] = await devBucket().getFiles({prefix: 'contracts/'});
  const inv = {
    applications: ap.size, contracts: ec.size, scheduleRequests: scr.size,
    attendance: at.size, tos: tos.size, contractArtifacts: files.length,
  };
  log(`${label}  ${JSON.stringify(inv)}`);
  return inv;
}

async function pre0Snapshot() {
  const m = require('./r7-fixture-manifest-dev.json');
  const e = m.scenarios.R7_FIX_LT_WORKER.entities;
  const app = await loadApp(e.applicationId);
  const wages = {};
  for (const [k, id] of Object.entries(e.payroll)) {
    const s = await db.collection('attendance').doc(id).get();
    wages[k] = s.exists ? s.data().wageStatus : 'MISSING';
  }
  return {
    status: app.status, confirmedAt: app.confirmedAt.toMillis(),
    workEndDate: app.workEndDate.toMillis(),
    leaveDates: dateArr(app, 'leaveDates').join(','),
    extraWorkDates: dateArr(app, 'extraWorkDates').join(','),
    wages,
  };
}

/** 그 날짜의 이 공고 좌석 — 서버 srvContractConfirmedOnDay 와 같은 규칙. */
async function seatOnDay(toId, dayNum, wkd) {
  const snap = await db.collection('applications')
      .where('toId', '==', toId)
      .where('status', 'in', ['CONFIRMED', 'CONTRACT_PENDING']).get();
  let n = 0;
  for (const d of snap.docs) {
    if (eligibility(d.data(), dayNum, wkd) === 'WORK') n++;
  }
  return n;
}

/** callableGetDayStaffingDetail 에서 이 공고의 부족을 뽑는다. */
async function dayDetailShortage(toId, offset) {
  const r = await callAs(ADMIN, 'callableGetDayStaffingDetail',
      {businessId: BIZ, dateMs: kstMidnightMs(offset)});
  const rows = (r && r.rows) || [];
  const mine = rows.filter((x) => x.toId === toId);
  return {
    rows: mine.length,
    required: mine.reduce((s, x) => s + (x.requiredCount || 0), 0),
    confirmed: mine.reduce((s, x) => s + (x.confirmedCount || 0), 0),
  };
}

/** callableGetStaffingReadiness 에서 그 날짜의 사업장 전체 부족. */
async function readinessOnDay(offset) {
  const r = await callAs(ADMIN, 'callableGetStaffingReadiness', {});
  const key = kstDateKey(offset);
  const days = (r && (r.days || r.staffing || [])) || [];
  const hit = days.find((d) => (d.date || d.dateKey || '').startsWith(key));
  return hit ? {
    required: hit.required, confirmed: hit.confirmed, shortage: hit.shortage,
  } : null;
}

const contractDataFor = async (applicationId) => {
  const app = await loadApp(applicationId);
  const biz = (await db.collection('businesses').doc(BIZ).get()).data();
  const worker = (await db.collection('users').doc(WORKER).get()).data();
  const bn = String(biz.businessNumber || '').replace(/\D/g, '');
  return {
    applicationId, businessId: BIZ, businessName: biz.name || '',
    workerId: WORKER, isLongTerm: true, toId: app.toId || '',
    workDetailId: `${app.selectedWorkType}_${app.startTime}_${app.endTime}`,
    slots: [], applicationIds: [applicationId],
    snapshot: {
      businessName: biz.name || '',
      businessNumber: bn.length === 10 ?
        `${bn.slice(0, 3)}-${bn.slice(3, 5)}-${bn.slice(5)}` : bn,
      businessAddress: [biz.address, biz.detailAddress].filter(Boolean).join(' '),
      businessPhone: biz.phone || null, ownerName: biz.ownerName || '',
      workerName: worker.name || '',
      workerBirthDate: worker.birthDate ?
        new Date(worker.birthDate.toMillis() + KST).toISOString().slice(0, 10) : null,
      workerPhone: worker.authPhone || worker.phone || null,
      workerAddress: [worker.address, worker.detailAddress]
          .filter(Boolean).join(' ').trim() || null,
      workType: app.selectedWorkType, workPlace: biz.address || '',
      isLongTerm: true,
      contractStart: iso(app.desiredStartDate || app.workDate),
      contractEnd: iso(app.workEndDate),
      workDays: app.workDays || [],
      startTime: app.startTime, endTime: app.endTime,
      breakMinutes: app.breakMinutes || 0,
      wage: app.wage, wageType: app.wageType,
      wagePaymentDay: biz.wagePaymentDay ?? null, paymentMethod: '계좌이체',
      baseHourlyWage: app.baseHourlyWage ?? null,
      payScheduleType: app.payScheduleType || 'same_day',
      payScheduleDay: app.payScheduleDay ?? null,
      payScheduleTime: app.payScheduleTime ?? null,
      taxDeductionType: app.taxDeductionType || 'none',
    },
    articles: [], templateId: null,
  };
};

// ══════════════════════════════════════════════════════════════════
async function cleanup() {
  const st = readState();
  head('cleanup — state 에 적힌 id 만');
  const before = await inventory('BEFORE');

  // 1. 일정 예외를 canonical cancel 로 먼저 되돌린다 (§50)
  if (st.applicationId) {
    const scrs = await db.collection('schedule_change_requests')
        .where('applicationId', '==', st.applicationId).get();
    log(`   schedule_change_requests ${scrs.size}건`);
    for (const d of scrs.docs) {
      const s = d.data().status;
      if (EXECUTE && (s === 'PENDING' || s === 'APPROVED')) {
        try {
          await callAs(ADMIN, 'callableCancelScheduleChangeRequest', {requestId: d.id});
        } catch (e) { log(`     취소 실패 ${d.id}: ${e.message}`); }
      }
      if (EXECUTE) await d.ref.delete();
    }
  }
  // 1-b. §31 probe 가 만든 근태 — 정확히 그 id 만
  if (st.probeAttendanceId) {
    const ref = db.collection('attendance').doc(st.probeAttendanceId);
    if ((await ref.get()).exists) {
      log(`   probe 근태 ${st.probeAttendanceId}`);
      if (EXECUTE) await ref.delete();
    }
  }
  // 2. 계약 + Storage
  if (st.contractId) {
    const ref = db.collection('employment_contracts').doc(st.contractId);
    if ((await ref.get()).exists) {
      log(`   계약서 ${st.contractId}`);
      if (EXECUTE) {
        await ref.delete();
        const [files] = await devBucket()
            .getFiles({prefix: `contracts/${st.contractId}/`});
        for (const f of files) await f.delete();
        log(`     Storage artifact ${files.length}건 삭제`);
      }
    }
  }
  // 3. 지원서 · 공고
  if (st.applicationId) {
    const ref = db.collection('applications').doc(st.applicationId);
    if ((await ref.get()).exists) {
      log(`   지원서 ${st.applicationId}`);
      if (EXECUTE) await ref.delete();
    }
  }
  if (st.toId) {
    const others = await db.collection('applications')
        .where('toId', '==', st.toId).get();
    const foreign = others.docs.filter((d) => d.id !== st.applicationId);
    if (foreign.length > 0) {
      log(`   공고 ${st.toId} — 남의 지원서 ${foreign.length}건, 남긴다`);
    } else {
      log(`   공고 ${st.toId}`);
      if (EXECUTE) await db.collection('tos').doc(st.toId).delete();
    }
  }
  // 4. 알림
  for (const who of [WORKER, ADMIN, SUBADMIN]) {
    const col = db.collection('users').doc(who).collection('notifications');
    const seen = new Map();
    for (const q of [
      col.where('data.applicationId', '==', st.applicationId || '_'),
      col.where('data.contractId', '==', st.contractId || '_'),
    ]) {
      (await q.get()).docs.forEach((d) => seen.set(d.id, d.ref));
    }
    // scheduleChange 알림은 requestId 로 달린다.
    for (const rid of st.requestIds || []) {
      (await col.where('data.requestId', '==', rid).get()).docs
          .forEach((d) => seen.set(d.id, d.ref));
    }
    if (seen.size === 0) continue;
    log(`   알림 ${seen.size}건 (${who.slice(0, 10)}…)`);
    if (EXECUTE) for (const r of seen.values()) await r.delete();
  }

  if (!EXECUTE) { log('\ndry-run — 아무것도 지우지 않았습니다.'); return; }
  const after = await inventory('AFTER ');
  log(JSON.stringify({
    applications: after.applications - before.applications,
    contracts: after.contracts - before.contracts,
    scheduleRequests: after.scheduleRequests - before.scheduleRequests,
    tos: after.tos - before.tos,
    contractArtifacts: after.contractArtifacts - before.contractArtifacts,
  }));
  if (fs.existsSync(STATE)) fs.unlinkSync(STATE);
}

// ══════════════════════════════════════════════════════════════════
async function main() {
  if (CLEANUP) return cleanup();
  log(`\nDEV=${projectId}  ${EXECUTE ? '' : '(dry-run)'}`);

  head('§2 pre-runtime inventory · PRE0 기준선');
  const invBefore = await inventory('BEFORE');
  const pre0Before = await pre0Snapshot();
  log(`R7_FIX_LT_WORKER  ${JSON.stringify(pre0Before)}`);
  if (!EXECUTE) { log('\ndry-run 종료.'); return; }

  const st = readState();
  st.requestIds = st.requestIds || [];

  // ── 재실행 보호 ─────────────────────────────────────────────────
  //   이 검증은 **누적 상태가 없다는 전제**로 센다. 지난 회차가 남긴
  //   PENDING 요청이나 probe 근태가 있으면 "중복 PENDING 없음" 같은
  //   단언이 실패하는데, 그건 제품이 틀린 것이 아니라 시작점이 다른 것이다.
  //   지나간 회차를 실패로 적으면 보고서가 거짓말을 한다.
  if (st.applicationId) {
    const prior = await db.collection('schedule_change_requests')
        .where('applicationId', '==', st.applicationId).get();
    if (prior.size > 0) {
      head('이미 실행된 fixture 가 있다');
      log(`   schedule_change_requests ${prior.size}건이 남아 있다.`);
      log('   이 검증은 깨끗한 시작점을 전제로 한다 —');
      log('   --cleanup --execute 후 다시 실행하세요.');
      process.exitCode = 2;
      return;
    }
  }

  // ── fixture: 장기 TO → 지원 → 확정 → 양측 서명 → CONFIRMED ──────
  head('fixture — 계약 완료 장기 근로자');
  if (!st.toId) {
    const wd = S.workDetail({
      workType: WORK_TYPE, start: START_TIME, end: END_TIME,
      required: 1, wage: WAGE,
    });
    const created = await callAs(ADMIN, 'callableCreateTO', {
      toData: {
        businessId: BIZ, businessName: '위워커', type: 'contract',
        title: `[${NS}] 일정 예외 런타임`,
        description: 'LONGTERM-LIFECYCLE-INTEGRITY.3 — 휴무/추가근무 검증',
        workDetails: [wd], totalSlots: 0, totalRequired: 1,
        totalConfirmed: 0, totalPending: 0,
        rangeStart: kstMidnightMs(FROM_OFFSET), rangeEnd: kstMidnightMs(TO_OFFSET),
        workDays: WORK_DAYS, deadlineType: 'HOURS_BEFORE', hoursBeforeStart: 2,
        contractPeriodType: 'custom', postingDurationDays: 30,
        creatorUID: ADMIN, publishMode: 'immediate',
        isPublished: true, status: 'ACTIVE', isManualClosed: false,
      },
    });
    st.toId = created.toId; writeState(st);
  }
  if (!st.applicationId) {
    const r = await callAs(WORKER, 'callableApplyToTO', {
      idCardConsentGiven: true, documentAccessConsentGiven: true,
      documentAccessConsentVersion: CONSENT_VERSION,
      toId: st.toId, slotId: null, businessId: BIZ, businessName: '위워커',
      toTitle: `[${NS}] 일정 예외 런타임`, selectedWorkType: WORK_TYPE,
      startTime: START_TIME, endTime: END_TIME,
      workDateMs: kstMidnightMs(FROM_OFFSET),
      workEndDateMs: kstMidnightMs(TO_OFFSET),
      workDays: WORK_DAYS, wage: WAGE, wageType: 'hourly',
    });
    st.applicationId = r.applicationId || r.id; writeState(st);
  }
  let app = await loadApp(st.applicationId);
  if (app.status === 'PENDING') {
    await callAs(ADMIN, 'callableConfirmApplication',
        {applicationId: st.applicationId, businessId: BIZ});
  }
  if (!st.contractId) { st.contractId = db.collection('employment_contracts').doc().id; writeState(st); }
  const cRef = db.collection('employment_contracts').doc(st.contractId);
  if (!(await cRef.get()).exists) {
    await callAs(ADMIN, 'callableFinalizeEmployerSignature', {
      contractId: st.contractId,
      signatureBase64: S.signaturePng().toString('base64'),
      isNewUnsaved: true, contractData: await contractDataFor(st.applicationId),
    });
  }
  if (!(await cRef.get()).data().workerSignatureUrl) {
    await callAs(WORKER, 'callableFinalizeWorkerSignature', {
      contractId: st.contractId,
      signatureBase64: S.signaturePng(200, 80).toString('base64'),
      pdfBase64: S.onePagePdf([`[${NS}] DEV test data. Not a real contract.`])
          .toString('base64'),
    });
  }
  app = await loadApp(st.applicationId);
  const contract0 = (await cRef.get()).data();
  log(`   toId=${st.toId}`);
  log(`   applicationId=${st.applicationId}`);
  log(`   contractId=${st.contractId}`);
  check('fixture — Application CONFIRMED', app.status === 'CONFIRMED', app.status);
  check('fixture — Contract completed', contract0.status === 'completed',
      contract0.status);

  // ── §3 baseline snapshot ────────────────────────────────────────
  head('§3  baseline');
  const promise0 = {
    workDate: iso(app.workDate), workEndDate: iso(app.workEndDate),
    desiredStartDate: app.desiredStartDate ? iso(app.desiredStartDate) : null,
    workDays: (app.workDays || []).join(','),
    selectedWorkType: app.selectedWorkType,
    startTime: app.startTime, endTime: app.endTime,
    wage: app.wage, wageType: app.wageType, breakMinutes: app.breakMinutes ?? 0,
  };
  const snap0 = contract0.snapshot;
  const contractFrozen = {
    contractStart: snap0.contractStart, contractEnd: snap0.contractEnd,
    workDays: (snap0.workDays || []).join(','), workType: snap0.workType,
    startTime: snap0.startTime, endTime: snap0.endTime,
    wage: snap0.wage, wageType: snap0.wageType, pdfHash: contract0.pdfHash,
  };
  log(`   promise  ${JSON.stringify(promise0)}`);
  log(`   contract ${JSON.stringify({...contractFrozen, pdfHash: contractFrozen.pdfHash.slice(0, 12) + '…'})}`);
  log(`   leaveDates ${dateArr(app, 'leaveDates').join(',') || '없음'} · ` +
    `extraWorkDates ${dateArr(app, 'extraWorkDates').join(',') || '없음'}`);

  // ── §4 · §8  R / E 결정 ─────────────────────────────────────────
  head('§4  테스트 날짜');
  let rOffset = null; let eOffset = null;
  for (let o = 1; o <= TO_OFFSET; o++) {
    const w = wkdOfOffset(o);
    if (rOffset === null && WORK_DAYS.includes(w)) rOffset = o;
    if (eOffset === null && !WORK_DAYS.includes(w)) eOffset = o;
  }
  const R = {offset: rOffset, num: dnumOfMs(kstMidnightMs(rOffset)), wkd: wkdOfOffset(rOffset)};
  const E = {offset: eOffset, num: dnumOfMs(kstMidnightMs(eOffset)), wkd: wkdOfOffset(eOffset)};
  log(`   R 정규 근무일  ${kstDateKey(R.offset)} (${R.wkd})`);
  log(`   E 비근무일     ${kstDateKey(E.offset)} (${E.wkd})`);
  check('§8 R 은 계약 범위 안이고 근무요일이다',
      WORK_DAYS.includes(R.wkd) && R.num <= dnumOfMs(kstMidnightMs(TO_OFFSET)));
  check('§8 E 는 계약 범위 안이고 비근무요일이다',
      !WORK_DAYS.includes(E.wkd) && E.num <= dnumOfMs(kstMidnightMs(TO_OFFSET)));

  // ── §9  baseline eligibility ────────────────────────────────────
  head('§9  baseline eligibility');
  check('§9 R = WORK', eligibility(app, R.num, R.wkd) === 'WORK',
      eligibility(app, R.num, R.wkd));
  check('§9 E = NO_WORK', eligibility(app, E.num, E.wkd) === 'NO_WORK',
      eligibility(app, E.num, E.wkd));
  const seatR0 = await seatOnDay(st.toId, R.num, R.wkd);
  const detailR0 = await dayDetailShortage(st.toId, R.offset);
  log(`   R 좌석 ${seatR0} · dayDetail ${JSON.stringify(detailR0)}`);

  // ── 공통 헬퍼 ───────────────────────────────────────────────────
  const createReq = async (targetOffset, type) => {
    const r = await callAs(ADMIN, 'callableCreateScheduleChangeRequest', {
      applicationId: st.applicationId, businessId: BIZ,
      // 클라이언트와 같은 형식: 그 KST 달력 날짜의 UTC 자정
      targetDateMs: Date.UTC(
          ...kstDateKey(targetOffset).split('-').map((x, i) => i === 1 ? +x - 1 : +x)),
      requestType: type, reason: `${NS} runtime`,
    });
    if (r.requestId && !st.requestIds.includes(r.requestId)) {
      st.requestIds.push(r.requestId); writeState(st);
    }
    return r;
  };
  const approve = (requestId) => callAs(ADMIN, 'callableApproveScheduleChangeRequest',
      {requestId, action: 'APPROVED'});
  const reject = (requestId) => callAs(ADMIN, 'callableApproveScheduleChangeRequest',
      {requestId, action: 'REJECTED', rejectReason: `${NS} runtime`});
  const cancel = (requestId) => callAs(ADMIN, 'callableCancelScheduleChangeRequest',
      {requestId});
  const scrStatus = async (id) =>
    (await db.collection('schedule_change_requests').doc(id).get()).data().status;

  const matrix = [];
  const snapRow = async (label, requestStatus) => {
    const a = await loadApp(st.applicationId);
    const leave = dateArr(a, 'leaveDates');
    const extra = dateArr(a, 'extraWorkDates');
    matrix.push({
      label, requestStatus,
      leaveR: leave.includes(R.num) ? 'present' : 'absent',
      extraR: extra.includes(R.num) ? 'present' : 'absent',
      leaveE: leave.includes(E.num) ? 'present' : 'absent',
      extraE: extra.includes(E.num) ? 'present' : 'absent',
      eligR: eligibility(a, R.num, R.wkd),
      eligE: eligibility(a, E.num, E.wkd),
    });
    return a;
  };
  await snapRow('baseline', '—');

  // ══════════════════════════════════════════════════════════════
  // Scenario A — 정규 근무일 R → NO_WORK
  // ══════════════════════════════════════════════════════════════
  head('§5·§10  NO_WORK(R) 생성');
  const attBefore = (await db.collection('attendance').get()).size;
  const a1 = await createReq(R.offset, 'NO_WORK');
  log(`   requestId=${a1.requestId} created=${a1.created}`);
  check('§10 생성 직후 status = PENDING',
      (await scrStatus(a1.requestId)) === 'PENDING');
  const appPending = await snapRow('NO_WORK pending', 'PENDING');
  check('§27 PENDING 만으로 leaveDates 가 변하지 않는다',
      !dateArr(appPending, 'leaveDates').includes(R.num));
  check('§27 PENDING 만으로 eligibility 가 변하지 않는다',
      eligibility(appPending, R.num, R.wkd) === 'WORK');

  // §29 duplicate pending
  const a1dup = await createReq(R.offset, 'NO_WORK');
  const pendingSame = await db.collection('schedule_change_requests')
      .where('applicationId', '==', st.applicationId)
      .where('requestType', '==', 'NO_WORK')
      .where('status', '==', 'PENDING').get();
  check('§29 같은 날짜 PENDING 중복이 생기지 않는다',
      a1dup.created === false && a1dup.requestId === a1.requestId &&
      pendingSame.size === 1, `created=${a1dup.created} pending=${pendingSame.size}`);

  head('§6·§11  NO_WORK(R) 승인');
  await approve(a1.requestId);
  check('§11 request status = APPROVED',
      (await scrStatus(a1.requestId)) === 'APPROVED');
  const appA = await snapRow('NO_WORK approved', 'APPROVED');
  check('§11 R ∈ leaveDates', dateArr(appA, 'leaveDates').includes(R.num));
  check('§11 R ∉ extraWorkDates', !dateArr(appA, 'extraWorkDates').includes(R.num));
  check('§12 R = NO_WORK', eligibility(appA, R.num, R.wkd) === 'NO_WORK',
      eligibility(appA, R.num, R.wkd));

  head('§8·§13  좌석 delta');
  const seatR1 = await seatOnDay(st.toId, R.num, R.wkd);
  const detailR1 = await dayDetailShortage(st.toId, R.offset);
  log(`   좌석 ${seatR0} → ${seatR1}`);
  log(`   dayDetail ${JSON.stringify(detailR0)} → ${JSON.stringify(detailR1)}`);
  check('§13 휴무가 되면 그날 좌석을 놓는다', seatR1 === seatR0 - 1,
      `${seatR0} → ${seatR1}`);
  check('§13 하루 상세도 같은 확정 수를 말한다',
      detailR1.confirmed === detailR0.confirmed - 1,
      `${detailR0.confirmed} → ${detailR1.confirmed}`);

  head('§15  승인이 근태·급여를 만들지 않는다');
  const attAfterA = (await db.collection('attendance').get()).size;
  check('§15 attendance 개수 변화 0', attAfterA === attBefore,
      `${attBefore} → ${attAfterA}`);

  // ══════════════════════════════════════════════════════════════
  // Scenario C — 휴무 R → EXTRA_WORK 전환 (핵심 regression)
  // ══════════════════════════════════════════════════════════════
  head('§21  휴무 → 추가근무 전환 (같은 날짜 R)');
  const c1 = await createReq(R.offset, 'EXTRA_WORK');
  const appCp = await snapRow('EXTRA pending on R', 'PENDING');
  check('§27 PENDING 이 휴무 사실을 바꾸지 않는다',
      dateArr(appCp, 'leaveDates').includes(R.num) &&
      eligibility(appCp, R.num, R.wkd) === 'NO_WORK');
  await approve(c1.requestId);
  const appC = await snapRow('EXTRA approved on R', 'APPROVED');
  check('§21 R ∉ leaveDates', !dateArr(appC, 'leaveDates').includes(R.num));
  check('§21 R ∈ extraWorkDates', dateArr(appC, 'extraWorkDates').includes(R.num));
  check('§21 R = WORK 로 복귀', eligibility(appC, R.num, R.wkd) === 'WORK');

  head('§22  dual-state 검사');
  const leaveSet = new Set(dateArr(appC, 'leaveDates'));
  const extraSet = new Set(dateArr(appC, 'extraWorkDates'));
  const inter = [...leaveSet].filter((d) => extraSet.has(d));
  check('§22 leaveDates ∩ extraWorkDates = 0', inter.length === 0,
      `교집합 ${JSON.stringify(inter)}`);

  head('§23  좌석 복귀');
  const seatR2 = await seatOnDay(st.toId, R.num, R.wkd);
  const detailR2 = await dayDetailShortage(st.toId, R.offset);
  check('§23 좌석이 원래대로 돌아온다', seatR2 === seatR0, `${seatR1} → ${seatR2}`);
  check('§23 하루 상세도 복귀', detailR2.confirmed === detailR0.confirmed,
      `${detailR1.confirmed} → ${detailR2.confirmed}`);

  // ══════════════════════════════════════════════════════════════
  // Scenario D — 추가근무 R → NO_WORK 역방향
  // ══════════════════════════════════════════════════════════════
  head('§24  추가근무 → 휴무 역전환 (같은 날짜 R)');
  const d1 = await createReq(R.offset, 'NO_WORK');
  await approve(d1.requestId);
  const appD = await snapRow('NO_WORK approved again on R', 'APPROVED');
  check('§24 R ∈ leaveDates', dateArr(appD, 'leaveDates').includes(R.num));
  check('§24 R ∉ extraWorkDates', !dateArr(appD, 'extraWorkDates').includes(R.num));
  check('§24 R = NO_WORK', eligibility(appD, R.num, R.wkd) === 'NO_WORK');
  const inter2 = dateArr(appD, 'leaveDates')
      .filter((d) => dateArr(appD, 'extraWorkDates').includes(d));
  check('§22 역방향에서도 dual-state 0', inter2.length === 0);

  // ── §25·§26  approved NO_WORK 취소 → 원래 정규일 복귀 ───────────
  head('§25·§26  승인된 NO_WORK 취소');
  await cancel(d1.requestId);
  check('§25 request status = CANCELED',
      (await scrStatus(d1.requestId)) === 'CANCELED');
  const appD2 = await snapRow('NO_WORK canceled on R', 'CANCELED');
  check('§25 R ∉ leaveDates', !dateArr(appD2, 'leaveDates').includes(R.num));
  check('§26 R = WORK 로 복귀', eligibility(appD2, R.num, R.wkd) === 'WORK');
  const seatR3 = await seatOnDay(st.toId, R.num, R.wkd);
  check('§26 좌석도 복귀', seatR3 === seatR0, `${seatR3}`);

  // ══════════════════════════════════════════════════════════════
  // Scenario B — 비근무일 E → EXTRA_WORK
  // ══════════════════════════════════════════════════════════════
  head('§9·§16  EXTRA_WORK(E) 생성');
  const toBefore = (await db.collection('tos').doc(st.toId).get()).data();
  const b1 = await createReq(E.offset, 'EXTRA_WORK');
  const appBp = await snapRow('EXTRA pending on E', 'PENDING');
  check('§16 PENDING 시점에 E ∉ extraWorkDates',
      !dateArr(appBp, 'extraWorkDates').includes(E.num));
  check('§27 E 는 아직 NO_WORK', eligibility(appBp, E.num, E.wkd) === 'NO_WORK');

  head('§10·§17  EXTRA_WORK(E) 승인');
  await approve(b1.requestId);
  const appB = await snapRow('EXTRA approved on E', 'APPROVED');
  check('§16 E ∈ extraWorkDates', dateArr(appB, 'extraWorkDates').includes(E.num));
  check('§16 E ∉ leaveDates', !dateArr(appB, 'leaveDates').includes(E.num));
  check('§17 E = WORK 로 전환', eligibility(appB, E.num, E.wkd) === 'WORK');

  head('§18  추가근무는 모집 정원이 아니다');
  const toAfter = (await db.collection('tos').doc(st.toId).get()).data();
  check('§18 TO totalConfirmed 불변',
      toAfter.totalConfirmed === toBefore.totalConfirmed,
      `${toBefore.totalConfirmed} → ${toAfter.totalConfirmed}`);
  check('§18 TO totalRequired 불변',
      toAfter.totalRequired === toBefore.totalRequired);
  check('§18 workDetails requiredCount 불변',
      JSON.stringify(toAfter.workDetails.map((w) => w.requiredCount)) ===
      JSON.stringify(toBefore.workDetails.map((w) => w.requiredCount)));

  head('§19·§20  추가근무 승인이 근태·급여를 만들지 않는다');
  const attAfterB = (await db.collection('attendance').get()).size;
  check('§19 attendance 개수 변화 0', attAfterB === attBefore,
      `${attBefore} → ${attAfterB}`);
  const wageRows = (await db.collection('attendance')
      .where('applicationId', '==', st.applicationId).get()).size;
  check('§20 이 지원서의 wage row 0', wageRows === 0, `${wageRows}건`);

  // ── §25·§26  approved EXTRA 취소 → 원래 비근무일 복귀 ────────────
  head('§25·§26  승인된 EXTRA_WORK 취소');
  await cancel(b1.requestId);
  check('§25 request status = CANCELED',
      (await scrStatus(b1.requestId)) === 'CANCELED');
  const appB2 = await snapRow('EXTRA canceled on E', 'CANCELED');
  check('§25 E ∉ extraWorkDates', !dateArr(appB2, 'extraWorkDates').includes(E.num));
  check('§26 E = NO_WORK 로 복귀', eligibility(appB2, E.num, E.wkd) === 'NO_WORK');

  // ── §28  REJECTED 는 일정을 바꾸지 않는다 ───────────────────────
  head('§28  거절');
  const before28 = await loadApp(st.applicationId);
  const r1 = await createReq(E.offset, 'EXTRA_WORK');
  await reject(r1.requestId);
  check('§28 request status = REJECTED',
      (await scrStatus(r1.requestId)) === 'REJECTED');
  const after28 = await loadApp(st.applicationId);
  check('§28 거절은 leaveDates/extraWorkDates 를 건드리지 않는다',
      dateArr(before28, 'leaveDates').join() === dateArr(after28, 'leaveDates').join() &&
      dateArr(before28, 'extraWorkDates').join() === dateArr(after28, 'extraWorkDates').join());
  check('§28 거절 후 E 는 여전히 NO_WORK',
      eligibility(after28, E.num, E.wkd) === 'NO_WORK');

  // ── §30  범위 밖 날짜 ───────────────────────────────────────────
  head('§30  계약 범위 밖 날짜');
  for (const [label, off] of [['시작 이전', FROM_OFFSET - 5], ['종료 이후', TO_OFFSET + 5]]) {
    let outcome = 'APPROVED(!)';
    try {
      const x = await createReq(off, 'EXTRA_WORK');
      await approve(x.requestId);
    } catch (e) { outcome = String(e.message).slice(0, 100); }
    check(`§30 ${label} 날짜 승인 거절`, outcome !== 'APPROVED(!)', outcome);
  }

  // ── §43  KST 날짜 parity ────────────────────────────────────────
  head('§43  KST 날짜 parity');
  const k1 = await createReq(R.offset, 'NO_WORK');
  await approve(k1.requestId);
  const scrDoc = (await db.collection('schedule_change_requests').doc(k1.requestId).get()).data();
  const appK = await loadApp(st.applicationId);
  const storedNum = dnumOfMs(scrDoc.targetDate.toMillis());
  const arrNum = dateArr(appK, 'leaveDates').find((d) => d === R.num);
  log(`   요청한 KST 날짜   ${R.num}`);
  log(`   저장된 targetDate ${storedNum}`);
  log(`   Application 배열  ${arrNum}`);
  check('§43 요청·저장·배열의 KST 날짜가 같다',
      storedNum === R.num && arrNum === R.num);
  await cancel(k1.requestId);

  // ── §31  이미 출근한 날은 휴무로 바꿀 수 없다 ───────────────────
  //
  //   money/attendance integrity 축이다. 출근 기록이 있는 날을 휴무로
  //   만들면 실제 근로가 화면에서 사라진다.
  //
  //   오늘(T)은 이 fixture 의 근무요일이고 01:00~02:30 창이 이미 지났다.
  //   관리자 배치 경로로 실제 출근을 만든 뒤 그 날짜에 NO_WORK 승인을
  //   시도한다. 시계나 날짜를 조작하지 않는다.
  head('§31  출근한 날 휴무 차단');
  const T = {offset: 0, num: dnumOfMs(kstMidnightMs(0)), wkd: wkdOfOffset(0)};
  const appT = await loadApp(st.applicationId);
  if (WORK_DAYS.includes(T.wkd) && eligibility(appT, T.num, T.wkd) === 'WORK') {
    const attId = `${st.applicationId}_${kstDateKey(0).replace(/-/g, '')}`;
    st.probeAttendanceId = attId; writeState(st);
    const already = (await db.collection('attendance').doc(attId).get()).exists;
    if (!already) {
      await callAs(ADMIN, 'callableBatchCheckIn', {
        businessId: BIZ,
        entries: [{
          applicationId: st.applicationId, workDateMs: kstMidnightMs(0),
          userId: WORKER, businessId: BIZ, businessName: '위워커',
          workType: WORK_TYPE, status: 'present',
          checkInMs: kstMidnightMs(0) + 1 * 3600e3,
        }],
      });
    }
    const attSnap = await db.collection('attendance').doc(attId).get();
    check('§31 probe — 오늘 출근 기록이 만들어졌다',
        attSnap.exists && attSnap.data().checkIn != null,
        attSnap.exists ? `status=${attSnap.data().status}` : '없음');

    if (attSnap.exists && attSnap.data().checkIn != null) {
      const g1 = await createReq(0, 'NO_WORK');
      let outcome = 'APPROVED(!)';
      try { await approve(g1.requestId); } catch (e) {
        outcome = String(e.message).slice(0, 110);
      }
      check('§31 출근한 날의 NO_WORK 승인 → 거절',
          outcome !== 'APPROVED(!)', outcome);
      const appG = await loadApp(st.applicationId);
      check('§31 거절이 leaveDates 를 건드리지 않았다',
          !dateArr(appG, 'leaveDates').includes(T.num));
      check('§31 그날은 여전히 근무일이다',
          eligibility(appG, T.num, T.wkd) === 'WORK');
    }
  } else {
    log(`   오늘(${kstDateKey(0)} ${T.wkd})은 이 fixture 의 근무일이 아니다 — DEV NOT SEEN`);
  }

  // ── §32·§33  불변성 ─────────────────────────────────────────────
  head('§32·§33  signed Contract / Application promise 불변');
  const contract1 = (await cRef.get()).data();
  const snap1 = contract1.snapshot;
  const contractNow = {
    contractStart: snap1.contractStart, contractEnd: snap1.contractEnd,
    workDays: (snap1.workDays || []).join(','), workType: snap1.workType,
    startTime: snap1.startTime, endTime: snap1.endTime,
    wage: snap1.wage, wageType: snap1.wageType, pdfHash: contract1.pdfHash,
  };
  check('§32 signed Contract snapshot 불변',
      JSON.stringify(contractFrozen) === JSON.stringify(contractNow),
      JSON.stringify(contractNow) !== JSON.stringify(contractFrozen) ?
        JSON.stringify(contractNow) : '');
  const appF = await loadApp(st.applicationId);
  const promise1 = {
    workDate: iso(appF.workDate), workEndDate: iso(appF.workEndDate),
    desiredStartDate: appF.desiredStartDate ? iso(appF.desiredStartDate) : null,
    workDays: (appF.workDays || []).join(','),
    selectedWorkType: appF.selectedWorkType,
    startTime: appF.startTime, endTime: appF.endTime,
    wage: appF.wage, wageType: appF.wageType, breakMinutes: appF.breakMinutes ?? 0,
  };
  check('§33 Application 약속 필드 불변',
      JSON.stringify(promise0) === JSON.stringify(promise1),
      JSON.stringify(promise1) !== JSON.stringify(promise0) ?
        JSON.stringify(promise1) : '');
  check('§33 Application status 는 CONFIRMED 그대로',
      appF.status === 'CONFIRMED', appF.status);

  // ── §40  권한 ───────────────────────────────────────────────────
  head('§40  권한');
  {
    let outcome = 'ALLOWED(!)';
    try {
      await callAs(WORKER, 'callableCreateScheduleChangeRequest', {
        applicationId: st.applicationId, businessId: BIZ,
        targetDateMs: Date.UTC(...kstDateKey(R.offset).split('-')
            .map((x, i) => i === 1 ? +x - 1 : +x)),
        requestType: 'NO_WORK',
      });
    } catch (e) { outcome = String(e.message).slice(0, 100); }
    check('§40 관리자가 아닌 계정의 생성 → 거절', outcome !== 'ALLOWED(!)', outcome);
  }
  {
    const p = (await db.collection('businesses').doc(BIZ)
        .collection('members').doc(SUBADMIN).get()).data();
    log(`   SubAdmin canManageWorkers=${(p?.permissions || {}).canManageWorkers}`);
    check('§40 schedule mutation capability = canManageWorkers',
        (p?.permissions || {}).canManageWorkers === true);
  }

  // ── §42  알림 ───────────────────────────────────────────────────
  head('§42  승인 알림');
  const nts = await db.collection('users').doc(WORKER).collection('notifications')
      .where('data.requestId', '==', a1.requestId).get();
  const approved = nts.docs.filter((d) => d.data().type === 'scheduleChangeApproved');
  check('§42 승인 결과 알림 1건', approved.length === 1, `${approved.length}건`);
  if (approved[0]) {
    const n = approved[0].data();
    log(`   type=${n.type} action=${n.data.action} businessId=${n.data.businessId}`);
  }

  // ── §46  mutation matrix ────────────────────────────────────────
  head('§46  mutation matrix');
  log('   EVENT                        request    leaveR   extraR   R          leaveE   extraE   E');
  for (const m of matrix) {
    log(`   ${m.label.padEnd(28)} ${String(m.requestStatus).padEnd(10)} ` +
      `${m.leaveR.padEnd(8)} ${m.extraR.padEnd(8)} ${m.eligR.padEnd(10)} ` +
      `${m.leaveE.padEnd(8)} ${m.extraE.padEnd(8)} ${m.eligE}`);
  }

  // ── §52  PRE0 보존 ──────────────────────────────────────────────
  head('§52  PRE0 fixture 보존');
  const pre0After = await pre0Snapshot();
  check('R7_FIX_LT_WORKER 불변',
      JSON.stringify(pre0Before) === JSON.stringify(pre0After),
      JSON.stringify(pre0After));

  head('요약');
  await inventory('AFTER ');
  log(`   기준선 ${JSON.stringify(invBefore)}`);
  const failed = results.filter((r) => !r.ok);
  log(`\n   ${results.length - failed.length}/${results.length} PASS`);
  failed.forEach((r) => log(`     · ${r.label}`));
  if (failed.length > 0) process.exitCode = 1;
  log(`\n   정리: --cleanup --execute`);
}

main().then(() => process.exit(process.exitCode || 0)).catch((e) => {
  console.error('\n실패:', e && e.message ? e.message : e);
  process.exit(1);
});
