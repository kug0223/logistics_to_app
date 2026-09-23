#!/usr/bin/env node
/**
 * [PRELAUNCH-LONGTERM-LIFECYCLE-INTEGRITY.4A §34 · §16]
 * 자동 연장을 걷어낸 뒤의 "미결정 만료" 상태를 DEV 에서 확인한다.
 *
 *   계약 종료일 D = 오늘, renewalDecision = null
 *
 *   D    → 마지막 근무 가능일 (근무일 · 좌석 1)
 *   D+1  → 근무 대상 아님 · 좌석 0 · 출근 불가
 *
 * 이것은 "근로자를 취소했다"가 아니라 "계약기간이 끝났고 새 약속이 아직
 * 없다"는 뜻이다. 그리고 그 상태에서도 관리자는 여전히 연장할 수 있어야
 * 한다 — 그 경로가 막히면 자동 연장을 없앤 대가로 근로자가 갇힌다.
 *
 *   node scripts/lt-noauto-expiry-runtime.js --project alfit-89567
 *   node scripts/lt-noauto-expiry-runtime.js --project alfit-89567 --execute
 *   node scripts/lt-noauto-expiry-runtime.js --project alfit-89567 --cleanup --execute
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
const WORK_TYPE = '사무업무';
const CONSENT_VERSION = '2026-09-18-v3';
const NS = 'LTNOAUTO';
const STATE = path.join(__dirname, '.lt-noauto-runtime-state.json');

const START_TIME = '02:00';
const END_TIME = '03:00';
const WAGE = 16500;
// 전 요일 근무 — D+1 이 대상이 아닌 이유가 **요일이 아니라 기간**이어야 한다.
const WORK_DAYS = ['월', '화', '수', '목', '금', '토', '일'];
const FROM_OFFSET = -2;
const END_OFFSET = 0; // D = 오늘

const KST = 9 * 3600e3;
const WK = ['일', '월', '화', '수', '목', '금', '토'];
const LAT = 37.1432540168018;
const LNG = 127.060063542351;
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

async function seatsOnDay(toId, dayNum, wkd) {
  const snap = await db.collection('applications')
      .where('toId', '==', toId)
      .where('status', 'in', ['CONFIRMED', 'CONTRACT_PENDING']).get();
  return snap.docs.filter((d) => eligibility(d.data(), dayNum, wkd) === 'WORK')
      .map((d) => d.id);
}

async function inventory(label) {
  const [ap, ec, at, tos] = await Promise.all([
    db.collection('applications').get(),
    db.collection('employment_contracts').get(),
    db.collection('attendance').get(),
    db.collection('tos').get(),
  ]);
  const [files] = await devBucket().getFiles({prefix: 'contracts/'});
  const inv = {applications: ap.size, contracts: ec.size, attendance: at.size,
    tos: tos.size, contractArtifacts: files.length};
  log(`${label}  ${JSON.stringify(inv)}`);
  return inv;
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
      workerName: worker.name || '', workerBirthDate: worker.birthDate ?
        new Date(worker.birthDate.toMillis() + KST).toISOString().slice(0, 10) : null,
      workerPhone: worker.authPhone || worker.phone || null,
      workerAddress: [worker.address, worker.detailAddress]
          .filter(Boolean).join(' ').trim() || null,
      workType: app.selectedWorkType, workPlace: biz.address || '',
      isLongTerm: true,
      contractStart: iso(app.desiredStartDate || app.workDate),
      contractEnd: iso(app.workEndDate), workDays: app.workDays || [],
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

async function cleanup() {
  const st = readState();
  head('cleanup — state 에 적힌 id 만');
  const before = await inventory('BEFORE');
  for (const cid of [st.contractId, st.renewContractId].filter(Boolean)) {
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
  for (const aid of [st.renewApplicationId, st.applicationId].filter(Boolean)) {
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
        (d) => ![st.applicationId, st.renewApplicationId].includes(d.id));
    if (foreign.length > 0) log(`   공고 ${st.toId} — 남의 지원서 ${foreign.length}건, 남긴다`);
    else { log(`   공고 ${st.toId}`); if (EXECUTE) await db.collection('tos').doc(st.toId).delete(); }
  }
  for (const who of [WORKER, ADMIN]) {
    const col = db.collection('users').doc(who).collection('notifications');
    const seen = new Map();
    for (const [f, v] of [
      ['data.applicationId', st.applicationId],
      ['data.applicationId', st.renewApplicationId],
      ['data.contractId', st.contractId],
      ['data.contractId', st.renewContractId],
    ].filter(([, v]) => !!v)) {
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

async function main() {
  if (CLEANUP) return cleanup();
  log(`\nDEV=${projectId}  ${EXECUTE ? '' : '(dry-run)'}`);
  head('pre-runtime inventory');
  const invBefore = await inventory('BEFORE');
  if (!EXECUTE) { log('\ndry-run 종료.'); return; }

  const st = readState();
  if (st.renewApplicationId) {
    head('이미 실행된 fixture 가 있다 — --cleanup --execute 후 재실행');
    process.exitCode = 2; return;
  }

  // ── fixture: 오늘 끝나는 장기 계약, 미결정 ──────────────────────
  head('fixture — 오늘 종료 · renewalDecision 없음');
  if (!st.toId) {
    const wd = S.workDetail({workType: WORK_TYPE, start: START_TIME,
      end: END_TIME, required: 1, wage: WAGE});
    const created = await callAs(ADMIN, 'callableCreateTO', {
      toData: {
        businessId: BIZ, businessName: '위워커', type: 'contract',
        title: `[${NS}] 미결정 만료 런타임`,
        description: 'LONGTERM-LIFECYCLE-INTEGRITY.4A — 자동연장 제거 후 만료 semantics',
        workDetails: [wd], totalSlots: 0, totalRequired: 1,
        totalConfirmed: 0, totalPending: 0,
        rangeStart: kstMidnightMs(FROM_OFFSET), rangeEnd: kstMidnightMs(END_OFFSET),
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
      toTitle: `[${NS}] 미결정 만료 런타임`, selectedWorkType: WORK_TYPE,
      startTime: START_TIME, endTime: END_TIME,
      workDateMs: kstMidnightMs(FROM_OFFSET),
      workEndDateMs: kstMidnightMs(END_OFFSET),
      workDays: WORK_DAYS, wage: WAGE, wageType: 'hourly',
    });
    st.applicationId = r.applicationId || r.id; writeState(st);
  }
  let app = await loadApp(st.applicationId);
  if (app.status === 'PENDING') {
    await callAs(ADMIN, 'callableConfirmApplication',
        {applicationId: st.applicationId, businessId: BIZ});
  }
  if (!st.contractId) {
    st.contractId = db.collection('employment_contracts').doc().id; writeState(st);
  }
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
      pdfBase64: S.onePagePdf([`[${NS}] DEV test data.`]).toString('base64'),
    });
  }
  app = await loadApp(st.applicationId);
  log(`   toId=${st.toId}`);
  log(`   application=${st.applicationId}`);
  check('fixture — CONFIRMED', app.status === 'CONFIRMED', app.status);
  check('fixture — 종료일이 오늘이다', iso(app.workEndDate) === kstDateKey(0),
      iso(app.workEndDate));
  check('§6 renewalDecision 없음', !app.renewalDecision, String(app.renewalDecision));

  const D = {num: dnumOfMs(kstMidnightMs(0)), wkd: wkdOfOffset(0)};
  const N = {num: dnumOfMs(kstMidnightMs(1)), wkd: wkdOfOffset(1)};
  log(`   D   ${kstDateKey(0)} (${D.wkd})`);
  log(`   D+1 ${kstDateKey(1)} (${N.wkd})`);

  // ── §7 · §34  D / D+1 ──────────────────────────────────────────
  head('§7·§34  D 와 D+1');
  check('§7 D 는 마지막 근무 가능일이다',
      eligibility(app, D.num, D.wkd) === 'WORK', eligibility(app, D.num, D.wkd));
  check('§7 D+1 은 근무 대상이 아니다',
      eligibility(app, N.num, N.wkd) === 'AFTER_END', eligibility(app, N.num, N.wkd));
  const seatD = await seatsOnDay(st.toId, D.num, D.wkd);
  const seatN = await seatsOnDay(st.toId, N.num, N.wkd);
  check('§14 D 좌석 1', seatD.length === 1, `${seatD.length}건`);
  check('§14 D+1 좌석 0 — 새 약속이 없으므로', seatN.length === 0, `${seatN.length}건`);
  const detail = await callAs(ADMIN, 'callableGetDayStaffingDetail',
      {businessId: BIZ, dateMs: kstMidnightMs(0)});
  const mine = ((detail && detail.rows) || []).filter((x) => x.toId === st.toId);
  check('§34 하루 상세도 D 에 확정 1을 말한다',
      mine.reduce((s, x) => s + (x.confirmedCount || 0), 0) === 1,
      JSON.stringify(mine.map((x) => x.confirmedCount)));

  // ── §13  출근 대상 아님 — 실제 서버 게이트 ──────────────────────
  head('§13  D+1 출근 시도');
  let outcome = 'ALLOWED(!)';
  try {
    await callAs(WORKER, 'callableCheckIn', {
      applicationId: st.applicationId, businessId: BIZ, businessName: '위워커',
      workDateMs: kstMidnightMs(1), workType: WORK_TYPE,
      latitude: LAT, longitude: LNG, method: 'gps',
    });
  } catch (e) { outcome = String(e.message).slice(0, 120); }
  check('§13 D+1 출근 → 거절', outcome !== 'ALLOWED(!)', outcome);
  const attAfter = (await db.collection('attendance')
      .where('applicationId', '==', st.applicationId).get()).size;
  check('§13 거절이 근태를 만들지 않았다', attAfter === 0, `${attAfter}건`);

  // ── §8  status 를 억지로 바꾸지 않는다 ──────────────────────────
  head('§8  만료가 status 를 바꾸지 않는다');
  check('§8 status 는 CONFIRMED 그대로', app.status === 'CONFIRMED', app.status);
  check('§8 renewalDecision 을 TERMINATE 로 추측하지 않는다',
      !app.renewalDecision, String(app.renewalDecision));
  check('§8 renewedToApplicationId 없음', !app.renewedToApplicationId);

  // ── §16 · §17  만료 이후에도 연장 가능 ──────────────────────────
  head('§16·§17  미결정 만료 뒤 수동 연장');
  const rr = await callAs(ADMIN, 'callableCreateContractRenewal', {
    originalApplicationId: st.applicationId,
    newStartDateMs: kstMidnightMs(1),
    newEndDateMs: kstMidnightMs(30),
  });
  st.renewApplicationId = rr.newApplicationId; writeState(st);
  const renewed = await loadApp(st.renewApplicationId);
  const oldAfter = await loadApp(st.applicationId);
  check('§16 연장이 여전히 가능하다', !!st.renewApplicationId, st.renewApplicationId);
  check('§16 NEW 는 CONTRACT_PENDING — 수동 경로 그대로',
      renewed.status === 'CONTRACT_PENDING', renewed.status);
  check('§16 NEW 시작일 = D+1', iso(renewed.workDate) === kstDateKey(1),
      iso(renewed.workDate));
  check('§16 OLD renewalDecision = EXTEND', oldAfter.renewalDecision === 'EXTEND');
  check('§29 양방향 링크', oldAfter.renewedToApplicationId === st.renewApplicationId &&
      renewed.renewedFromApplicationId === st.applicationId);
  const seatN2 = await seatsOnDay(st.toId, N.num, N.wkd);
  check('§16 연장 후 D+1 좌석이 1로 돌아온다', seatN2.length === 1 &&
      seatN2[0] === st.renewApplicationId, `${seatN2.length}건`);

  // ── §29  수동 연장 회귀 — 서명까지 ──────────────────────────────
  head('§29  수동 연장 회귀 (서명 → CONFIRMED)');
  st.renewContractId = db.collection('employment_contracts').doc().id; writeState(st);
  await callAs(ADMIN, 'callableFinalizeEmployerSignature', {
    contractId: st.renewContractId,
    signatureBase64: S.signaturePng().toString('base64'),
    isNewUnsaved: true, contractData: await contractDataFor(st.renewApplicationId),
  });
  const c1 = (await db.collection('employment_contracts')
      .doc(st.renewContractId).get()).data();
  check('§29 사업주 서명 → pending_worker', c1.status === 'pending_worker', c1.status);
  check('§29 그 시점 NEW 는 아직 CONTRACT_PENDING',
      (await loadApp(st.renewApplicationId)).status === 'CONTRACT_PENDING');
  await callAs(WORKER, 'callableFinalizeWorkerSignature', {
    contractId: st.renewContractId,
    signatureBase64: S.signaturePng(200, 80).toString('base64'),
    pdfBase64: S.onePagePdf([`[${NS}] renewed`]).toString('base64'),
  });
  const c2 = (await db.collection('employment_contracts')
      .doc(st.renewContractId).get()).data();
  check('§29 근로자 서명 → completed', c2.status === 'completed', c2.status);
  check('§29 NEW CONFIRMED',
      (await loadApp(st.renewApplicationId)).status === 'CONFIRMED');

  // ── §29  경계 회귀 ─────────────────────────────────────────────
  head('§29  경계 회귀 (newStart == oldEnd)');
  let eq = 'ALLOWED(!)';
  try {
    await callAs(ADMIN, 'callableCreateContractRenewal', {
      originalApplicationId: st.renewApplicationId,
      newStartDateMs: kstMidnightMs(30),
      newEndDateMs: kstMidnightMs(60),
    });
  } catch (e) { eq = String(e.message).slice(0, 110); }
  check('§29 시작일 == 종료일 연장 거절 유지', eq !== 'ALLOWED(!)', eq);

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
