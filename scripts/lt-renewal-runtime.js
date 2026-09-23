#!/usr/bin/env node
/**
 * [PRELAUNCH-LONGTERM-LIFECYCLE-INTEGRITY.4]
 * 장기 계약 연장 — 기존 기간 보존 · 새 기간 생성 · 경계 parity DEV 실행.
 *
 * 핵심 invariant:
 *
 *   OLD period = 지나간 약속의 역사
 *   NEW period = 새 약속
 *   연장 ≠ 기존 Application/Contract 소급 수정
 *
 * 그리고 경계:
 *
 *   workEndDate 는 inclusive 다. 그러므로 D 는 OLD 의 근무일이고
 *   NEW 는 D+1 부터여야 한다. 같은 날짜가 둘 다에 속하면 그 날
 *   한 사람이 좌석 둘을 차지한다.
 *
 *   node scripts/lt-renewal-runtime.js --project alfit-89567
 *   node scripts/lt-renewal-runtime.js --project alfit-89567 --execute
 *   node scripts/lt-renewal-runtime.js --project alfit-89567 --cleanup --execute
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

const BIZ = 'fLmSOHVKUwmBHcbwQE0I';
const ADMIN = 'BErRdiWP1xbgyoTovxwAPNEsuD72';
const WORKER = 'tJ8izfP2nNYN79aPTLb6YARiPqC3';
const SUBADMIN = 'kN2gNpEhLLVjQD7KLGSnNFJHd2v2';
const WORK_TYPE = '사무업무';
const CONSENT_VERSION = '2026-09-18-v3';
const NS = 'LTRENEW';
const STATE = path.join(__dirname, '.lt-renewal-runtime-state.json');

// 다른 확정 근무와 겹치지 않는 창.
const START_TIME = '04:00';
const END_TIME = '05:00';
const PROMISED_WAGE = 15500;
const POSTING_WAGE_AFTER = 21000; // 연장 직전 공고를 올린 값 (§15)
const WORK_DAYS = ['월', '화', '수', '목', '금'];
const FROM_OFFSET = -2;
const OLD_END_OFFSET = 5;   // D
const NEW_END_OFFSET = 35;

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

/** 서버 srvLongTermEligibleOnDay 의 거울. */
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

const loadApp = async (id) =>
  (await db.collection('applications').doc(id).get()).data();
const loadContract = async (id) =>
  (await db.collection('employment_contracts').doc(id).get()).data();

async function inventory(label) {
  const [ap, ec, at, scr, tos] = await Promise.all([
    db.collection('applications').get(),
    db.collection('employment_contracts').get(),
    db.collection('attendance').get(),
    db.collection('schedule_change_requests').get(),
    db.collection('tos').get(),
  ]);
  const [files] = await devBucket().getFiles({prefix: 'contracts/'});
  const inv = {
    applications: ap.size, contracts: ec.size, attendance: at.size,
    scheduleRequests: scr.size, tos: tos.size, contractArtifacts: files.length,
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
    renewalDecision: app.renewalDecision ?? null, wages,
  };
}

/** 그 날짜에 이 공고에서 좌석을 차지하는 Application 들. */
async function seatsOnDay(toId, dayNum, wkd) {
  const snap = await db.collection('applications')
      .where('toId', '==', toId)
      .where('status', 'in', ['CONFIRMED', 'CONTRACT_PENDING']).get();
  const hits = [];
  for (const d of snap.docs) {
    if (eligibility(d.data(), dayNum, wkd) === 'WORK') hits.push(d.id);
  }
  return hits;
}

async function dayDetail(toId, offset) {
  const r = await callAs(ADMIN, 'callableGetDayStaffingDetail',
      {businessId: BIZ, dateMs: kstMidnightMs(offset)});
  const mine = ((r && r.rows) || []).filter((x) => x.toId === toId);
  return {
    rows: mine.length,
    confirmed: mine.reduce((s, x) => s + (x.confirmedCount || 0), 0),
  };
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

async function issueAndSign(applicationId, contractId) {
  const ref = db.collection('employment_contracts').doc(contractId);
  if (!(await ref.get()).exists) {
    await callAs(ADMIN, 'callableFinalizeEmployerSignature', {
      contractId, signatureBase64: S.signaturePng().toString('base64'),
      isNewUnsaved: true, contractData: await contractDataFor(applicationId),
    });
  }
  if (!(await ref.get()).data().workerSignatureUrl) {
    await callAs(WORKER, 'callableFinalizeWorkerSignature', {
      contractId, signatureBase64: S.signaturePng(200, 80).toString('base64'),
      pdfBase64: S.onePagePdf([`[${NS}] DEV test data. Not a real contract.`])
          .toString('base64'),
    });
  }
}

// ══════════════════════════════════════════════════════════════════
async function cleanup() {
  const st = readState();
  head('cleanup — state 에 적힌 id 만');
  const before = await inventory('BEFORE');
  for (const cid of [st.newContractId, st.oldContractId].filter(Boolean)) {
    const ref = db.collection('employment_contracts').doc(cid);
    if ((await ref.get()).exists) {
      log(`   계약서 ${cid}`);
      if (EXECUTE) {
        await ref.delete();
        const [files] = await devBucket().getFiles({prefix: `contracts/${cid}/`});
        for (const f of files) await f.delete();
        log(`     Storage artifact ${files.length}건 삭제`);
      }
    }
  }
  for (const aid of [st.newApplicationId, st.oldApplicationId].filter(Boolean)) {
    const ref = db.collection('applications').doc(aid);
    if ((await ref.get()).exists) {
      log(`   지원서 ${aid}`);
      if (EXECUTE) await ref.delete();
    }
  }
  if (st.toId) {
    const others = await db.collection('applications')
        .where('toId', '==', st.toId).get();
    const foreign = others.docs.filter(
        (d) => ![st.newApplicationId, st.oldApplicationId].includes(d.id));
    if (foreign.length > 0) {
      log(`   공고 ${st.toId} — 남의 지원서 ${foreign.length}건, 남긴다`);
    } else {
      log(`   공고 ${st.toId}`);
      if (EXECUTE) await db.collection('tos').doc(st.toId).delete();
    }
  }
  for (const who of [WORKER, ADMIN, SUBADMIN]) {
    const col = db.collection('users').doc(who).collection('notifications');
    const seen = new Map();
    const keys = [
      ['data.applicationId', st.oldApplicationId],
      ['data.applicationId', st.newApplicationId],
      ['data.contractId', st.oldContractId],
      ['data.contractId', st.newContractId],
    ].filter(([, v]) => !!v);
    for (const [f, v] of keys) {
      (await col.where(f, '==', v).get()).docs.forEach((d) => seen.set(d.id, d.ref));
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
    tos: after.tos - before.tos,
    contractArtifacts: after.contractArtifacts - before.contractArtifacts,
  }));
  if (fs.existsSync(STATE)) fs.unlinkSync(STATE);
}

// ══════════════════════════════════════════════════════════════════
async function main() {
  if (CLEANUP) return cleanup();
  log(`\nDEV=${projectId}  ${EXECUTE ? '' : '(dry-run)'}`);

  head('§54 pre-runtime inventory · PRE0 기준선');
  const invBefore = await inventory('BEFORE');
  const pre0Before = await pre0Snapshot();
  log(`R7_FIX_LT_WORKER  ${JSON.stringify(pre0Before)}`);
  if (!EXECUTE) { log('\ndry-run 종료.'); return; }

  const st = readState();
  if (st.newApplicationId) {
    head('이미 실행된 fixture 가 있다');
    log('   --cleanup --execute 후 다시 실행하세요.');
    process.exitCode = 2;
    return;
  }

  // ── §3 fixture ─────────────────────────────────────────────────
  head('§3  fixture — 계약 완료 장기 근로자');
  if (!st.toId) {
    const wd = S.workDetail({
      workType: WORK_TYPE, start: START_TIME, end: END_TIME,
      required: 1, wage: PROMISED_WAGE,
    });
    const created = await callAs(ADMIN, 'callableCreateTO', {
      toData: {
        businessId: BIZ, businessName: '위워커', type: 'contract',
        title: `[${NS}] 계약 연장 런타임`,
        description: 'LONGTERM-LIFECYCLE-INTEGRITY.4 — 연장/기간 parity',
        workDetails: [wd], totalSlots: 0, totalRequired: 1,
        totalConfirmed: 0, totalPending: 0,
        rangeStart: kstMidnightMs(FROM_OFFSET),
        rangeEnd: kstMidnightMs(OLD_END_OFFSET),
        workDays: WORK_DAYS, deadlineType: 'HOURS_BEFORE', hoursBeforeStart: 2,
        contractPeriodType: 'custom', postingDurationDays: 30,
        creatorUID: ADMIN, publishMode: 'immediate',
        isPublished: true, status: 'ACTIVE', isManualClosed: false,
      },
    });
    st.toId = created.toId; writeState(st);
  }
  if (!st.oldApplicationId) {
    const r = await callAs(WORKER, 'callableApplyToTO', {
      idCardConsentGiven: true, documentAccessConsentGiven: true,
      documentAccessConsentVersion: CONSENT_VERSION,
      toId: st.toId, slotId: null, businessId: BIZ, businessName: '위워커',
      toTitle: `[${NS}] 계약 연장 런타임`, selectedWorkType: WORK_TYPE,
      startTime: START_TIME, endTime: END_TIME,
      workDateMs: kstMidnightMs(FROM_OFFSET),
      workEndDateMs: kstMidnightMs(OLD_END_OFFSET),
      workDays: WORK_DAYS, wage: PROMISED_WAGE, wageType: 'hourly',
    });
    st.oldApplicationId = r.applicationId || r.id; writeState(st);
  }
  let oldApp = await loadApp(st.oldApplicationId);
  if (oldApp.status === 'PENDING') {
    await callAs(ADMIN, 'callableConfirmApplication',
        {applicationId: st.oldApplicationId, businessId: BIZ});
  }
  if (!st.oldContractId) {
    st.oldContractId = db.collection('employment_contracts').doc().id; writeState(st);
  }
  await issueAndSign(st.oldApplicationId, st.oldContractId);
  oldApp = await loadApp(st.oldApplicationId);
  const oldContract0 = await loadContract(st.oldContractId);
  log(`   toId=${st.toId}`);
  log(`   OLD application=${st.oldApplicationId}`);
  log(`   OLD contract=${st.oldContractId}`);
  check('§3 OLD Application CONFIRMED', oldApp.status === 'CONFIRMED', oldApp.status);
  check('§3 OLD Contract completed', oldContract0.status === 'completed',
      oldContract0.status);

  // ── §4·§5 baseline ─────────────────────────────────────────────
  head('§4  OLD baseline');
  const oldPromise0 = {
    workDate: iso(oldApp.workDate), workEndDate: iso(oldApp.workEndDate),
    desiredStartDate: oldApp.desiredStartDate ? iso(oldApp.desiredStartDate) : null,
    workDays: (oldApp.workDays || []).join(','),
    selectedWorkType: oldApp.selectedWorkType,
    startTime: oldApp.startTime, endTime: oldApp.endTime,
    breakMinutes: oldApp.breakMinutes ?? 0,
    wage: oldApp.wage, wageType: oldApp.wageType,
    taxDeductionType: oldApp.taxDeductionType ?? null,
    payScheduleType: oldApp.payScheduleType ?? null,
  };
  const oc = oldContract0.snapshot;
  const oldContractFrozen = {
    contractStart: oc.contractStart, contractEnd: oc.contractEnd,
    workDays: (oc.workDays || []).join(','), workType: oc.workType,
    startTime: oc.startTime, endTime: oc.endTime,
    wage: oc.wage, wageType: oc.wageType,
    pdfHash: oldContract0.pdfHash, pdfUrl: oldContract0.pdfUrl,
    employerSignedAt: oldContract0.employerSignedAt.toMillis(),
    workerSignedAt: oldContract0.workerSignedAt.toMillis(),
    status: oldContract0.status,
  };
  log(`   promise  ${JSON.stringify(oldPromise0)}`);
  log(`   contract ${JSON.stringify({...oldContractFrozen, pdfHash: oldContractFrozen.pdfHash.slice(0, 12) + '…', pdfUrl: '…'})}`);
  check('§4 연장 전 renewalDecision 없음', !oldApp.renewalDecision,
      String(oldApp.renewalDecision));

  // ── §5 경계 날짜 ────────────────────────────────────────────────
  head('§5  경계 정책');
  const D = {offset: OLD_END_OFFSET, num: dnumOfMs(kstMidnightMs(OLD_END_OFFSET)),
    wkd: wkdOfOffset(OLD_END_OFFSET)};
  const N = {offset: OLD_END_OFFSET + 1, num: dnumOfMs(kstMidnightMs(OLD_END_OFFSET + 1)),
    wkd: wkdOfOffset(OLD_END_OFFSET + 1)};
  log(`   D  (OLD 종료일)  ${kstDateKey(D.offset)} (${D.wkd})`);
  log(`   N  (NEW 시작일)  ${kstDateKey(N.offset)} (${N.wkd})`);
  log(`   workEndDate 는 inclusive — D 는 OLD 의 근무일이다.`);
  check('§5 D 는 OLD 기간의 마지막 날이다',
      eligibility(oldApp, D.num, D.wkd) !== 'AFTER_END',
      eligibility(oldApp, D.num, D.wkd));
  check('§5 D+1 은 OLD 기간 밖이다',
      eligibility(oldApp, N.num, N.wkd) === 'AFTER_END',
      eligibility(oldApp, N.num, N.wkd));

  // ── §6·§7  equality overlap negative ───────────────────────────
  head('§6·§7  newStart == oldEnd — 거절되어야 한다');
  let eqOutcome = 'ALLOWED(!)';
  let eqNewAppId = null;
  try {
    const r = await callAs(ADMIN, 'callableCreateContractRenewal', {
      originalApplicationId: st.oldApplicationId,
      newStartDateMs: oldApp.workEndDate.toMillis(),           // == D
      newEndDateMs: kstMidnightMs(NEW_END_OFFSET),
    });
    eqNewAppId = r.newApplicationId || null;
    if (eqNewAppId) { st.equalityNewAppId = eqNewAppId; writeState(st); }
  } catch (e) { eqOutcome = String(e.message).slice(0, 120); }
  check('§7 시작일 == 종료일 연장 → 거절', eqOutcome !== 'ALLOWED(!)', eqOutcome);
  if (eqOutcome === 'ALLOWED(!)') {
    log(`        ⚠️ 통과했다 — newApplicationId=${eqNewAppId}`);
    const bad = await loadApp(eqNewAppId);
    const overlapSeats = await seatsOnDay(st.toId, D.num, D.wkd);
    log(`        NEW workDate=${iso(bad.workDate)} · D(${D.num}) 좌석 ${overlapSeats.length}건`);
    check('§7 그 결과로 D 에 좌석이 둘이 되지 않는다', overlapSeats.length <= 1,
        `좌석 ${overlapSeats.length}건: ${overlapSeats.map((x) => x.slice(-12)).join(' ')}`);
    // 이 상태로는 이후 검증이 오염된다 — 되돌린다.
    await db.collection('applications').doc(eqNewAppId).delete();
    await db.collection('applications').doc(st.oldApplicationId).update({
      renewalDecision: null, renewedToApplicationId: null,
    });
    delete st.equalityNewAppId; writeState(st);
    log('        (검증 계속을 위해 그 결과를 되돌렸다)');
    oldApp = await loadApp(st.oldApplicationId);
  }

  // ── §15  연장 직전 공고 임금 인상 ───────────────────────────────
  head('§15  연장 직전 공고 임금 인상');
  const toNow = (await db.collection('tos').doc(st.toId).get()).data();
  if (toNow.workDetails[0].wage !== POSTING_WAGE_AFTER) {
    await callAs(ADMIN, 'callableUpdateTO', {
      toId: st.toId,
      updates: {workDetails: [{...toNow.workDetails[0], wage: POSTING_WAGE_AFTER}]},
      expectedEditRevision: toNow.editRevision ?? 0,
    });
  }
  log(`   공고 모집 임금 ${PROMISED_WAGE} → ${POSTING_WAGE_AFTER}`);
  log(`   OLD 약속 임금 ${oldApp.wage}`);

  // ── §9  정상 연장 ──────────────────────────────────────────────
  head('§9  정상 연장 (newStart = D+1)');
  const attBefore = (await db.collection('attendance').get()).size;
  const rr = await callAs(ADMIN, 'callableCreateContractRenewal', {
    originalApplicationId: st.oldApplicationId,
    newStartDateMs: kstMidnightMs(OLD_END_OFFSET + 1),
    newEndDateMs: kstMidnightMs(NEW_END_OFFSET),
  });
  st.newApplicationId = rr.newApplicationId; writeState(st);
  log(`   NEW application=${st.newApplicationId}`);

  const oldAfter = await loadApp(st.oldApplicationId);
  const newApp = await loadApp(st.newApplicationId);

  // ── §10  연장 링크 ─────────────────────────────────────────────
  head('§10  연장 링크');
  check('§10 OLD renewalDecision = EXTEND',
      oldAfter.renewalDecision === 'EXTEND', String(oldAfter.renewalDecision));
  check('§10 OLD → NEW 역참조',
      oldAfter.renewedToApplicationId === st.newApplicationId);
  check('§10 NEW → OLD 역참조',
      newApp.renewedFromApplicationId === st.oldApplicationId);
  check('§10 NEW status = CONTRACT_PENDING',
      newApp.status === 'CONTRACT_PENDING', newApp.status);

  // ── §11  OLD Application immutable ─────────────────────────────
  head('§11  OLD Application 불변');
  const oldPromise1 = {
    workDate: iso(oldAfter.workDate), workEndDate: iso(oldAfter.workEndDate),
    desiredStartDate: oldAfter.desiredStartDate ? iso(oldAfter.desiredStartDate) : null,
    workDays: (oldAfter.workDays || []).join(','),
    selectedWorkType: oldAfter.selectedWorkType,
    startTime: oldAfter.startTime, endTime: oldAfter.endTime,
    breakMinutes: oldAfter.breakMinutes ?? 0,
    wage: oldAfter.wage, wageType: oldAfter.wageType,
    taxDeductionType: oldAfter.taxDeductionType ?? null,
    payScheduleType: oldAfter.payScheduleType ?? null,
  };
  check('§11 OLD 약속 필드 불변',
      JSON.stringify(oldPromise0) === JSON.stringify(oldPromise1),
      JSON.stringify(oldPromise1) !== JSON.stringify(oldPromise0) ?
        JSON.stringify(oldPromise1) : '');
  check('§11 OLD workEndDate 가 새 종료일로 늘어나지 않았다',
      iso(oldAfter.workEndDate) === kstDateKey(OLD_END_OFFSET),
      iso(oldAfter.workEndDate));

  // ── §12  OLD Contract immutable ────────────────────────────────
  head('§12  OLD Contract 불변');
  const oldContract1 = await loadContract(st.oldContractId);
  const oc1 = oldContract1.snapshot;
  const oldContractNow = {
    contractStart: oc1.contractStart, contractEnd: oc1.contractEnd,
    workDays: (oc1.workDays || []).join(','), workType: oc1.workType,
    startTime: oc1.startTime, endTime: oc1.endTime,
    wage: oc1.wage, wageType: oc1.wageType,
    pdfHash: oldContract1.pdfHash, pdfUrl: oldContract1.pdfUrl,
    employerSignedAt: oldContract1.employerSignedAt.toMillis(),
    workerSignedAt: oldContract1.workerSignedAt.toMillis(),
    status: oldContract1.status,
  };
  check('§12 OLD completed 계약 전체 불변',
      JSON.stringify(oldContractFrozen) === JSON.stringify(oldContractNow),
      JSON.stringify(oldContractNow) !== JSON.stringify(oldContractFrozen) ?
        'MISMATCH' : '');

  // ── §13  NEW reset ─────────────────────────────────────────────
  head('§13  NEW 운영 state 초기화');
  const resets = {
    leaveDates: (newApp.leaveDates || []).length,
    extraWorkDates: (newApp.extraWorkDates || []).length,
    wageStatus: newApp.wageStatus, finalWage: newApp.finalWage,
    wageDetail: newApp.wageDetail,
    actualResignDate: newApp.actualResignDate ?? null,
    resignStatus: newApp.resignStatus ?? null,
    terminationStatus: newApp.terminationStatus ?? null,
    renewalDecision: newApp.renewalDecision ?? null,
    renewedToApplicationId: newApp.renewedToApplicationId ?? null,
    desiredStartDate: newApp.desiredStartDate ?? null,
  };
  log(`   ${JSON.stringify(resets)}`);
  check('§13 leave/extra 비어 있다',
      resets.leaveDates === 0 && resets.extraWorkDates === 0);
  check('§13 급여 state 초기화',
      resets.wageStatus === 'pending' && !resets.finalWage && !resets.wageDetail);
  check('§13 퇴사·해지·연장 state 초기화',
      !resets.actualResignDate && !resets.resignStatus &&
      !resets.terminationStatus && !resets.renewalDecision &&
      !resets.renewedToApplicationId);

  // ── §14·§15  promise 승계 ──────────────────────────────────────
  head('§14·§15  약속 승계 — 공고 현재값이 아니다');
  const inherited = ['workDays', 'selectedWorkType', 'startTime', 'endTime',
    'wage', 'wageType', 'taxDeductionType', 'payScheduleType', 'breakMinutes'];
  let inheritFail = 0;
  for (const f of inherited) {
    const a = Array.isArray(oldAfter[f]) ? oldAfter[f].join(',') : (oldAfter[f] ?? null);
    const b = Array.isArray(newApp[f]) ? newApp[f].join(',') : (newApp[f] ?? null);
    const ok = String(a) === String(b);
    if (!ok) inheritFail++;
    log(`   ${f.padEnd(18)} OLD ${String(a).padEnd(14)} NEW ${String(b).padEnd(14)} ${ok ? 'MATCH' : 'MISMATCH'}`);
  }
  check('§14 약속 필드가 OLD 를 그대로 잇는다', inheritFail === 0,
      `불일치 ${inheritFail}건`);
  check('§15 공고의 현재 모집 임금을 따르지 않았다',
      newApp.wage === PROMISED_WAGE && newApp.wage !== POSTING_WAGE_AFTER,
      `NEW.wage=${newApp.wage} · 공고=${POSTING_WAGE_AFTER}`);
  check('§9 NEW 기간이 요청대로다',
      iso(newApp.workDate) === kstDateKey(OLD_END_OFFSET + 1) &&
      iso(newApp.workEndDate) === kstDateKey(NEW_END_OFFSET),
      `${iso(newApp.workDate)} ~ ${iso(newApp.workEndDate)}`);

  // ── §26  NEW 는 근태·급여 없이 시작한다 ─────────────────────────
  head('§26  OLD 이력이 NEW 로 넘어오지 않는다');
  const newAtt = (await db.collection('attendance')
      .where('applicationId', '==', st.newApplicationId).get()).size;
  check('§26 NEW attendance 0건', newAtt === 0, `${newAtt}건`);
  check('§26 전체 attendance 개수 변화 0',
      (await db.collection('attendance').get()).size === attBefore);

  // ── §33  Step 1 만 된 상태의 좌석 ──────────────────────────────
  head('§33  계약 전(CONTRACT_PENDING) 좌석 정책');
  const seatsN_partial = await seatsOnDay(st.toId, N.num, N.wkd);
  check('§33 CONTRACT_PENDING 도 좌석을 차지한다 — 신규 확정 flow 와 같다',
      seatsN_partial.includes(st.newApplicationId),
      `${seatsN_partial.length}건`);

  // ── §28  중복 연장 ─────────────────────────────────────────────
  head('§28  중복 연장');
  let dupOutcome = 'ALLOWED(!)';
  try {
    await callAs(ADMIN, 'callableCreateContractRenewal', {
      originalApplicationId: st.oldApplicationId,
      newStartDateMs: kstMidnightMs(OLD_END_OFFSET + 1),
      newEndDateMs: kstMidnightMs(NEW_END_OFFSET),
    });
  } catch (e) { dupOutcome = String(e.message).slice(0, 120); }
  check('§28 같은 원본 재연장 → 거절', dupOutcome !== 'ALLOWED(!)', dupOutcome);
  const oldDup = await loadApp(st.oldApplicationId);
  check('§28 renewedToApplicationId 가 바뀌지 않았다',
      oldDup.renewedToApplicationId === st.newApplicationId);
  const renewedCount = (await db.collection('applications')
      .where('renewedFromApplicationId', '==', st.oldApplicationId).get()).size;
  check('§28 이 원본에서 파생된 Application 은 1건', renewedCount === 1,
      `${renewedCount}건`);

  // ── §43  권한 ──────────────────────────────────────────────────
  head('§43  권한');
  {
    let outcome = 'ALLOWED(!)';
    try {
      await callAs(WORKER, 'callableCreateContractRenewal', {
        originalApplicationId: st.oldApplicationId,
        newStartDateMs: kstMidnightMs(OLD_END_OFFSET + 1),
        newEndDateMs: kstMidnightMs(NEW_END_OFFSET),
      });
    } catch (e) { outcome = String(e.message).slice(0, 110); }
    check('§43 사업장 구성원이 아닌 계정 → 거절', outcome !== 'ALLOWED(!)', outcome);
    const p = (await db.collection('businesses').doc(BIZ)
        .collection('members').doc(SUBADMIN).get()).data();
    log(`   SubAdmin canManageContract=${(p?.permissions || {}).canManageContract}`);
    check('§42 연장 capability = canManageContract',
        (p?.permissions || {}).canManageContract === true);
  }

  // ── §16·§34  NEW 계약 생성 + 양측 서명 ──────────────────────────
  head('§16·§34  NEW 계약');
  if (!st.newContractId) {
    st.newContractId = db.collection('employment_contracts').doc().id; writeState(st);
  }
  await issueAndSign(st.newApplicationId, st.newContractId);
  const newContract = await loadContract(st.newContractId);
  check('§16 NEW 계약 completed', newContract.status === 'completed',
      newContract.status);
  const activeForNew = (await db.collection('employment_contracts')
      .where('applicationId', '==', st.newApplicationId).get())
      .docs.filter((d) => d.data().status !== 'voided');
  check('§34 NEW Application 의 active 계약은 1건', activeForNew.length === 1,
      `${activeForNew.length}건`);

  // ── §13  NEW CONFIRMED ─────────────────────────────────────────
  const newAfterSign = await loadApp(st.newApplicationId);
  check('§13 NEW Application CONFIRMED', newAfterSign.status === 'CONFIRMED',
      newAfterSign.status);
  check('§18 OLD renewalDecision 은 EXTEND 로 유지',
      (await loadApp(st.oldApplicationId)).renewalDecision === 'EXTEND');

  // ── §17  NEW contract parity ───────────────────────────────────
  head('§17  NEW Application ↔ NEW Contract parity');
  const ns = newContract.snapshot;
  const rows = [
    ['period start', iso(newAfterSign.workDate), ns.contractStart],
    ['period end', iso(newAfterSign.workEndDate), ns.contractEnd],
    ['workDays', (newAfterSign.workDays || []).join(','), (ns.workDays || []).join(',')],
    ['workType', newAfterSign.selectedWorkType, ns.workType],
    ['startTime', newAfterSign.startTime, ns.startTime],
    ['endTime', newAfterSign.endTime, ns.endTime],
    ['breakMinutes', newAfterSign.breakMinutes ?? 0, ns.breakMinutes ?? 0],
    ['wage', newAfterSign.wage, ns.wage],
    ['wageType', newAfterSign.wageType, ns.wageType],
    ['tax', newAfterSign.taxDeductionType ?? 'none', ns.taxDeductionType ?? 'none'],
    ['paySchedule', newAfterSign.payScheduleType ?? null, ns.payScheduleType ?? null],
    ['businessId', newAfterSign.businessId, newContract.businessId],
    ['workerUid', newAfterSign.uid, newContract.workerId],
    ['applicationId', st.newApplicationId, newContract.applicationId],
  ];
  log('   FIELD           NEW APPLICATION        NEW CONTRACT           RESULT');
  let parityFail = 0;
  for (const [f, a, b] of rows) {
    const ok = String(a) === String(b);
    if (!ok) parityFail++;
    log(`   ${String(f).padEnd(15)} ${String(a).padEnd(22)} ${String(b).padEnd(22)} ${ok ? 'MATCH' : 'MISMATCH'}`);
  }
  check('§17 NEW parity 전부 일치', parityFail === 0, `불일치 ${parityFail}건`);

  // ── §19·§20·§21  경계 matrix ───────────────────────────────────
  head('§21  날짜 경계 matrix');
  const oldFinal = await loadApp(st.oldApplicationId);
  const newFinal = await loadApp(st.newApplicationId);
  const boundary = [];
  for (const off of [D.offset - 1, D.offset, D.offset + 1, D.offset + 2]) {
    const num = dnumOfMs(kstMidnightMs(off));
    const wkd = wkdOfOffset(off);
    const seats = await seatsOnDay(st.toId, num, wkd);
    boundary.push({
      date: kstDateKey(off), wkd,
      old: eligibility(oldFinal, num, wkd),
      neu: eligibility(newFinal, num, wkd),
      seats: seats.length,
      detail: await dayDetail(st.toId, off),
    });
  }
  log('   DATE         요일  OLD APP      NEW APP      좌석  dayDetail.confirmed');
  for (const b of boundary) {
    log(`   ${b.date}   ${b.wkd}    ${b.old.padEnd(12)} ${b.neu.padEnd(12)} ` +
      `${String(b.seats).padEnd(5)} ${b.detail.confirmed}`);
  }
  const dRow = boundary.find((b) => b.date === kstDateKey(D.offset));
  const nRow = boundary.find((b) => b.date === kstDateKey(D.offset + 1));
  check('§19 D 는 OLD 만 유효하다',
      dRow.old !== 'AFTER_END' && dRow.neu === 'BEFORE_START',
      `OLD=${dRow.old} NEW=${dRow.neu}`);
  check('§20 D+1 은 NEW 만 유효하다',
      nRow.old === 'AFTER_END' && nRow.neu !== 'BEFORE_START',
      `OLD=${nRow.old} NEW=${nRow.neu}`);
  const doubleSeat = boundary.filter((b) => b.seats > 1);
  check('§22 어느 날짜에도 좌석이 둘이 되지 않는다', doubleSeat.length === 0,
      doubleSeat.map((b) => `${b.date}:${b.seats}`).join(' '));
  const workDayRows = boundary.filter((b) => b.old === 'WORK' || b.neu === 'WORK');
  const missing = workDayRows.filter((b) => b.seats === 0);
  check('§22 근무일인데 좌석이 비지 않는다', missing.length === 0,
      missing.map((b) => b.date).join(' '));
  // 하루 상세는 **모집** 화면이다 — 공고의 모집 기간으로 범위가 잡힌다.
  //   그래서 공고 기간이 끝난 날짜에는 행 자체가 없다. 그 날 일하는
  //   갱신 근로자가 "사라진" 것이 아니라, 그 화면이 답하는 질문
  //   (누구를 더 뽑아야 하는가)에 해당하지 않는 것이다.
  //   두 질문을 한 자리에서 비교하면 안 되므로 나눠서 본다.
  const toEndNum = dnumOfMs(kstMidnightMs(OLD_END_OFFSET));
  const inPosting = boundary.filter((b) => Number(b.date.replace(/-/g, '')) <= toEndNum);
  const outPosting = boundary.filter((b) => Number(b.date.replace(/-/g, '')) > toEndNum);
  const detailMismatch = inPosting.filter((b) => b.detail.confirmed !== b.seats);
  check('§22 모집 기간 안에서는 하루 상세가 resolver 와 같은 수를 말한다',
      detailMismatch.length === 0,
      detailMismatch.map((b) => `${b.date} ${b.seats}≠${b.detail.confirmed}`).join(' '));
  log('\n   모집 기간 밖(공고 rangeEnd 이후) 날짜 — 하루 상세 범위 밖:');
  outPosting.forEach((b) => log(
      `     ${b.date}  resolver 좌석 ${b.seats} · 하루 상세 rows ${b.detail.rows}`));
  check('§24 공고 기간 밖에는 모집 행이 없다 — 모집과 운영은 다른 질문이다',
      outPosting.every((b) => b.detail.rows === 0),
      outPosting.map((b) => `${b.date}:${b.detail.rows}`).join(' '));

  // ── §46  운영 reader — Application 기준이라 공고 범위에 묶이지 않는다 ──
  head('§46  운영 reader (FixedWorker 규칙)');
  //   FixedWorkerManagement 는 공고가 아니라 지원서를 읽는다.
  //     status ∈ {CONFIRMED, CONTRACT_PENDING} · 장기 · 퇴사/해지 완료 제외
  //     일반 목록: renewalDecision=EXTEND 인 구 계약 제외
  //     날짜 모드: 그 날짜를 덮는 지원서
  const fixedWorkerRows = async (dayNum, wkd, dateMode) => {
    const snap = await db.collection('applications')
        .where('businessId', '==', BIZ)
        .where('status', 'in', ['CONFIRMED', 'CONTRACT_PENDING']).get();
    return snap.docs.filter((d) => {
      const a = d.data();
      if (![st.oldApplicationId, st.newApplicationId].includes(d.id)) return false;
      if (!(a.workDays || []).length) return false;
      if (!dateMode) return a.renewalDecision !== 'EXTEND';
      return eligibility(a, dayNum, wkd) !== 'BEFORE_START' &&
        eligibility(a, dayNum, wkd) !== 'AFTER_END';
    }).map((d) => d.id);
  };
  const fwD = await fixedWorkerRows(D.num, D.wkd, true);
  const fwN = await fixedWorkerRows(N.num, N.wkd, true);
  const fwList = await fixedWorkerRows(0, '', false);
  log(`   날짜 모드 D   (${kstDateKey(D.offset)}) → ${fwD.map((x) => x.slice(-10)).join(' ') || '없음'}`);
  log(`   날짜 모드 D+1 (${kstDateKey(N.offset)}) → ${fwN.map((x) => x.slice(-10)).join(' ') || '없음'}`);
  log(`   일반 목록                     → ${fwList.map((x) => x.slice(-10)).join(' ') || '없음'}`);
  check('§46 D 에는 OLD 만 나온다',
      fwD.length === 1 && fwD[0] === st.oldApplicationId, fwD.join(' '));
  check('§46 D+1 에는 NEW 만 나온다',
      fwN.length === 1 && fwN[0] === st.newApplicationId, fwN.join(' '));
  check('§46 일반 목록에는 구 계약이 아니라 새 계약이 나온다',
      fwList.length === 1 && fwList[0] === st.newApplicationId, fwList.join(' '));

  // ── §24·§25  Posting lifecycle 독립성 ──────────────────────────
  head('§24·§25  모집 종료와 운영 관계의 분리');
  await callAs(ADMIN, 'callableCloseTOManually', {toId: st.toId});
  const toClosed = (await db.collection('tos').doc(st.toId).get()).data();
  log(`   공고 status=${toClosed.status} isManualClosed=${toClosed.isManualClosed}`);
  const afterClose = await loadApp(st.newApplicationId);
  check('§25 공고 마감이 NEW 확정 상태를 바꾸지 않는다',
      afterClose.status === 'CONFIRMED', afterClose.status);
  check('§25 공고 마감 후에도 NEW 기간 근무일이 유효하다',
      eligibility(afterClose, N.num, N.wkd) !== 'BEFORE_START' &&
      eligibility(afterClose, N.num, N.wkd) !== 'AFTER_END',
      eligibility(afterClose, N.num, N.wkd));
  const seatsAfterClose = await seatsOnDay(st.toId, N.num, N.wkd);
  check('§25 공고 마감 후에도 좌석 계산에서 사라지지 않는다',
      seatsAfterClose.includes(st.newApplicationId));

  // ── §21·§45  이력 보존 ─────────────────────────────────────────
  head('§45  OLD 이력 보존');
  const oldStill = await loadApp(st.oldApplicationId);
  const oldContractStill = await loadContract(st.oldContractId);
  check('§45 OLD Application 조회 가능', !!oldStill);
  check('§45 OLD completed 계약 조회 가능',
      oldContractStill && oldContractStill.status === 'completed');
  const byWorker = await db.collection('employment_contracts')
      .where('workerId', '==', WORKER).where('status', '==', 'completed').get();
  const ids = byWorker.docs.map((d) => d.id);
  check('§22 근로자 계약 이력에 OLD·NEW 둘 다 보인다',
      ids.includes(st.oldContractId) && ids.includes(st.newContractId));

  // ── §49  KST ───────────────────────────────────────────────────
  head('§49  KST 날짜 parity');
  log(`   요청 NEW start  ${dnumOfMs(kstMidnightMs(OLD_END_OFFSET + 1))}`);
  log(`   Application     ${dnumOfMs(newFinal.workDate.toMillis())}`);
  log(`   Contract        ${ns.contractStart.replace(/-/g, '')}`);
  check('§49 요청·Application·Contract 의 KST 시작일이 같다',
      dnumOfMs(newFinal.workDate.toMillis()) === dnumOfMs(kstMidnightMs(OLD_END_OFFSET + 1)) &&
      Number(ns.contractStart.replace(/-/g, '')) === dnumOfMs(kstMidnightMs(OLD_END_OFFSET + 1)));

  // ── §44  consent 관찰 (READ ONLY) ──────────────────────────────
  head('§44  동의 필드 승계 관찰');
  log(`   OLD documentAccessConsentGiven=${oldStill.documentAccessConsentGiven} ` +
    `version=${oldStill.documentAccessConsentVersion}`);
  log(`   NEW documentAccessConsentGiven=${newFinal.documentAccessConsentGiven} ` +
    `version=${newFinal.documentAccessConsentVersion}`);
  log(`   NEW idCardConsentGiven=${newFinal.idCardConsentGiven}`);
  log('   (관찰만 한다 — 이번 Phase 에서 privacy 정책을 설계하지 않는다)');

  // ── §55  PRE0 보존 ─────────────────────────────────────────────
  head('§55  PRE0 fixture 보존');
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
  log('\n   정리: --cleanup --execute');
}

main().then(() => process.exit(process.exitCode || 0)).catch((e) => {
  console.error('\n실패:', e && e.message ? e.message : e);
  process.exit(1);
});
