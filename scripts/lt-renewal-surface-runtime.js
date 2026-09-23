#!/usr/bin/env node
/**
 * [CORRECTION-EXPIRED-UNDECIDED-RENEWAL-ACTION-SURFACE §38~§42]
 *
 * 만료·미결정 계약이 세 곳에서 같은 말을 하는지 DEV 에서 확인한다.
 *
 *   Home 처리할 일 · 계약 확인 필요 화면 · 고정근무자 목록
 *
 * 그리고 결정(EXTEND / TERMINATE)이 내려지면 세 곳에서 함께 빠지는지.
 *
 *   node scripts/lt-renewal-surface-runtime.js --project alfit-89567
 *   node scripts/lt-renewal-surface-runtime.js --project alfit-89567 --execute
 *   node scripts/lt-renewal-surface-runtime.js --project alfit-89567 --cleanup --execute
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
const NS = 'LTSURF';
const STATE = path.join(__dirname, '.lt-surface-runtime-state.json');

const START_TIME = '02:10';
const END_TIME = '03:10';
const WAGE = 17000;
const WORK_DAYS = ['월', '화', '수', '목', '금', '토', '일'];
const FROM_OFFSET = -3;
const END_OFFSET = -1; // 어제 종료 → 오늘 기준 만료·미결정

const KST = 9 * 3600e3;
const iso = (ts) => ts ?
  new Date(ts.toMillis() + KST).toISOString().slice(0, 10) : null;

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
const loadApp = async (id) =>
  (await db.collection('applications').doc(id).get()).data();

/** 클라이언트 renewalDecisionStateOf 의 거울. */
function decisionState(app, todayNum) {
  const dn = (ts) =>
    Number(new Date(ts.toMillis() + KST).toISOString().slice(0, 10).replace(/-/g, ''));
  const isLong = app.type === 'long_term' ||
    (Array.isArray(app.workDays) && app.workDays.length > 0);
  if (!isLong) return 'NOT_APPLICABLE';
  if (app.renewalDecision) return 'RESOLVED';
  const done = ['APPROVED', 'AUTO_APPROVED'];
  if (done.includes(app.resignStatus) || done.includes(app.terminationStatus)) {
    return 'RESOLVED';
  }
  if (!['CONFIRMED', 'CONTRACT_PENDING'].includes(app.status)) return 'NOT_APPLICABLE';
  const end = app.actualResignDate || app.workEndDate;
  if (!end) return 'NOT_APPLICABLE';
  const endNum = dn(end);
  if (endNum < todayNum) return 'EXPIRED';
  const days = Math.round(
      (Date.UTC(Math.floor(endNum / 10000), Math.floor((endNum % 10000) / 100) - 1, endNum % 100) -
       Date.UTC(Math.floor(todayNum / 10000), Math.floor((todayNum % 10000) / 100) - 1, todayNum % 100)) / 86400000);
  return days <= 15 ? 'UPCOMING' : 'NOT_APPLICABLE';
}

/** Home 의 계약 결정 섹션. */
async function homeContractSection() {
  const r = await callAs(ADMIN, 'callableGetAdminHomeSummary', {});
  return (r && r.upcoming && r.upcoming.expiringContract) || null;
}

/**
 * 계약 확인 필요 화면이 읽는 후보 — getExpiringLongTermApplications 와 같은
 * 서버 경로(callableGetApplicationsByBiz)에 같은 파라미터를 준다.
 */
async function expiringCandidates(lookBackDays = 180) {
  const from = kstMidnightMs(0) - lookBackDays * 86400e3;
  const out = [];
  let cursor = null;
  for (let page = 0; page < 50; page++) {
    const r = await callAs(ADMIN, 'callableGetApplicationsByBiz', {
      businessId: BIZ, workEndDateGteMs: from, limit: 200,
      ...(cursor ? {startAfterDocId: cursor} : {}),
    });
    out.push(...((r && r.applications) || []));
    if (r.hasMore !== true || !r.lastDocId) return out;
    cursor = r.lastDocId;
  }
  throw new Error('페이지를 다 쓰고도 남았다 — 범위를 좁혀야 한다.');
}

async function inventory(label) {
  const [ap, ec, tos] = await Promise.all([
    db.collection('applications').get(),
    db.collection('employment_contracts').get(),
    db.collection('tos').get(),
  ]);
  const [files] = await devBucket().getFiles({prefix: 'contracts/'});
  const inv = {applications: ap.size, contracts: ec.size, tos: tos.size,
    contractArtifacts: files.length};
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
      workerName: worker.name || '', workerBirthDate: null,
      workerPhone: worker.authPhone || worker.phone || null,
      workerAddress: null,
      workType: app.selectedWorkType, workPlace: biz.address || '',
      isLongTerm: true,
      contractStart: iso(app.desiredStartDate || app.workDate),
      contractEnd: iso(app.workEndDate), workDays: app.workDays || [],
      startTime: app.startTime, endTime: app.endTime, breakMinutes: 0,
      wage: app.wage, wageType: app.wageType,
      wagePaymentDay: biz.wagePaymentDay ?? null, paymentMethod: '계좌이체',
      baseHourlyWage: null, payScheduleType: app.payScheduleType || 'same_day',
      payScheduleDay: null, payScheduleTime: null,
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
      }
    }
  }
  for (const aid of [st.renewApplicationId, st.applicationId, st.terminateApplicationId]
      .filter(Boolean)) {
    const ref = db.collection('applications').doc(aid);
    if ((await ref.get()).exists) {
      log(`   지원서 ${aid}`);
      if (EXECUTE) await ref.delete();
    }
  }
  for (const toId of [st.toId, st.terminateToId].filter(Boolean)) {
    const others = await db.collection('applications').where('toId', '==', toId).get();
    const mine = [st.applicationId, st.renewApplicationId, st.terminateApplicationId];
    if (others.docs.some((d) => !mine.includes(d.id))) {
      log(`   공고 ${toId} — 남의 지원서, 남긴다`);
    } else {
      log(`   공고 ${toId}`);
      if (EXECUTE) await db.collection('tos').doc(toId).delete();
    }
  }
  for (const who of [WORKER, ADMIN]) {
    const col = db.collection('users').doc(who).collection('notifications');
    const seen = new Map();
    for (const [f, v] of [
      ['data.applicationId', st.applicationId],
      ['data.applicationId', st.renewApplicationId],
      ['data.applicationId', st.terminateApplicationId],
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

/** 만료·미결정 fixture 하나를 canonical writer 로 만든다. */
async function buildExpiredFixture(st, keyTo, keyApp, keyContract, title, time) {
  if (!st[keyTo]) {
    const wd = S.workDetail({workType: WORK_TYPE, start: time[0], end: time[1],
      required: 1, wage: WAGE});
    const created = await callAs(ADMIN, 'callableCreateTO', {
      toData: {
        businessId: BIZ, businessName: '위워커', type: 'contract',
        title: `[${NS}] ${title}`,
        description: 'CORRECTION-EXPIRED-UNDECIDED-RENEWAL-ACTION-SURFACE',
        workDetails: [wd], totalSlots: 0, totalRequired: 1,
        totalConfirmed: 0, totalPending: 0,
        rangeStart: kstMidnightMs(FROM_OFFSET), rangeEnd: kstMidnightMs(END_OFFSET),
        workDays: WORK_DAYS, deadlineType: 'HOURS_BEFORE', hoursBeforeStart: 2,
        contractPeriodType: 'custom', postingDurationDays: 30,
        creatorUID: ADMIN, publishMode: 'immediate',
        isPublished: true, status: 'ACTIVE', isManualClosed: false,
      },
    });
    st[keyTo] = created.toId; writeState(st);
  }
  if (!st[keyApp]) {
    const r = await callAs(WORKER, 'callableApplyToTO', {
      idCardConsentGiven: true, documentAccessConsentGiven: true,
      documentAccessConsentVersion: CONSENT_VERSION,
      toId: st[keyTo], slotId: null, businessId: BIZ, businessName: '위워커',
      toTitle: `[${NS}] ${title}`, selectedWorkType: WORK_TYPE,
      startTime: time[0], endTime: time[1],
      workDateMs: kstMidnightMs(FROM_OFFSET),
      workEndDateMs: kstMidnightMs(END_OFFSET),
      workDays: WORK_DAYS, wage: WAGE, wageType: 'hourly',
    });
    st[keyApp] = r.applicationId || r.id; writeState(st);
  }
  const app = await loadApp(st[keyApp]);
  if (app.status === 'PENDING') {
    await callAs(ADMIN, 'callableConfirmApplication',
        {applicationId: st[keyApp], businessId: BIZ});
  }
  if (keyContract) {
    if (!st[keyContract]) {
      st[keyContract] = db.collection('employment_contracts').doc().id; writeState(st);
    }
    const cRef = db.collection('employment_contracts').doc(st[keyContract]);
    if (!(await cRef.get()).exists) {
      await callAs(ADMIN, 'callableFinalizeEmployerSignature', {
        contractId: st[keyContract],
        signatureBase64: S.signaturePng().toString('base64'),
        isNewUnsaved: true, contractData: await contractDataFor(st[keyApp]),
      });
    }
    if (!(await cRef.get()).data().workerSignatureUrl) {
      await callAs(WORKER, 'callableFinalizeWorkerSignature', {
        contractId: st[keyContract],
        signatureBase64: S.signaturePng(200, 80).toString('base64'),
        pdfBase64: S.onePagePdf([`[${NS}] DEV test data.`]).toString('base64'),
      });
    }
  }
  return loadApp(st[keyApp]);
}

async function main() {
  if (CLEANUP) return cleanup();
  log(`\nDEV=${projectId}  ${EXECUTE ? '' : '(dry-run)'}`);

  const todayNum = Number(kstDateKey(0).replace(/-/g, ''));
  head('§38 기준선');
  const invBefore = await inventory('BEFORE');
  const homeBefore = await homeContractSection();
  log(`Home 계약 섹션  ${JSON.stringify(homeBefore)}`);
  if (!EXECUTE) { log('\ndry-run 종료.'); return; }

  const st = readState();
  if (st.applicationId) {
    head('이미 실행된 fixture — --cleanup --execute 후 재실행');
    process.exitCode = 2; return;
  }

  // ── fixture: 어제 종료 · 미결정 ─────────────────────────────────
  head('§38 fixture — 어제 종료 · renewalDecision 없음');
  const app = await buildExpiredFixture(
      st, 'toId', 'applicationId', 'contractId', '만료 미결정', [START_TIME, END_TIME]);
  log(`   application=${st.applicationId}  종료일=${iso(app.workEndDate)}`);
  check('fixture — CONFIRMED', app.status === 'CONFIRMED', app.status);
  check('fixture — 어제 종료', iso(app.workEndDate) === kstDateKey(-1),
      iso(app.workEndDate));
  check('§2 판정 = EXPIRED', decisionState(app, todayNum) === 'EXPIRED',
      decisionState(app, todayNum));

  // ── §38 Home ───────────────────────────────────────────────────
  head('§38 Home 처리할 일');
  const homeAfter = await homeContractSection();
  log(`   BEFORE ${JSON.stringify(homeBefore)}`);
  log(`   AFTER  ${JSON.stringify(homeAfter)}`);
  check('§38 Home 계약 결정 건수 +1',
      homeAfter.count === (homeBefore.count || 0) + 1,
      `${homeBefore.count} → ${homeAfter.count}`);
  check('§23 만료 건수를 따로 보낸다',
      homeAfter.expiredCount === (homeBefore.expiredCount || 0) + 1,
      `${homeBefore.expiredCount} → ${homeAfter.expiredCount}`);
  check('§28 available = true (ERROR 아님)', homeAfter.available === true);
  check('§33 사업장별로 분리된다',
      (homeAfter.byBusiness || []).some((b) => b.businessId === BIZ));

  // ── §39 계약 확인 필요 화면 ────────────────────────────────────
  head('§39 계약 확인 필요 화면 reader');
  const cands = await expiringCandidates();
  const rows = cands.filter((a) => a.id === st.applicationId);
  check('§39 조회에 만료 건이 들어온다 — 예전 창에서는 아예 없었다',
      rows.length === 1, `${rows.length}건`);

  // ── §40 고정근무자 ─────────────────────────────────────────────
  head('§40 고정근무자');
  const fw = await db.collection('applications')
      .where('businessId', '==', BIZ)
      .where('status', 'in', ['CONFIRMED', 'CONTRACT_PENDING']).get();
  const mineRow = fw.docs.find((d) => d.id === st.applicationId);
  check('§20 목록에는 남아 있다 — 연장 진입점이 사라지지 않는다', !!mineRow);
  const expiredInList = fw.docs.filter(
      (d) => decisionState(d.data(), todayNum) === 'EXPIRED');
  const normalInList = fw.docs.filter((d) => {
    const a = d.data();
    const isLong = a.type === 'long_term' ||
      (Array.isArray(a.workDays) && a.workDays.length > 0);
    return isLong && !a.resignStatus &&
      decisionState(a, todayNum) !== 'EXPIRED';
  });
  log(`   만료·미결정 ${expiredInList.length}건 · 정상 ${normalInList.length}건`);
  check('§18 정상 집계에서 만료 건이 빠진다',
      !normalInList.some((d) => d.id === st.applicationId));
  check('§17 만료 건은 따로 세어진다',
      expiredInList.some((d) => d.id === st.applicationId));

  // ── §41 late EXTEND ────────────────────────────────────────────
  head('§41 만료 뒤 수동 연장 → 세 면에서 함께 빠진다');
  const rr = await callAs(ADMIN, 'callableCreateContractRenewal', {
    originalApplicationId: st.applicationId,
    newStartDateMs: kstMidnightMs(0),
    newEndDateMs: kstMidnightMs(30),
  });
  st.renewApplicationId = rr.newApplicationId; writeState(st);
  const oldAfter = await loadApp(st.applicationId);
  const newApp = await loadApp(st.renewApplicationId);
  check('§41 OLD renewalDecision = EXTEND', oldAfter.renewalDecision === 'EXTEND');
  check('§41 OLD 판정 = RESOLVED',
      decisionState(oldAfter, todayNum) === 'RESOLVED',
      decisionState(oldAfter, todayNum));
  check('§21 NEW 는 CONTRACT_PENDING', newApp.status === 'CONTRACT_PENDING',
      newApp.status);
  const homeResolved = await homeContractSection();
  log(`   Home ${JSON.stringify(homeResolved)}`);
  check('§41 Home 만료 건수 -1',
      homeResolved.expiredCount === (homeBefore.expiredCount || 0),
      `${homeAfter.expiredCount} → ${homeResolved.expiredCount}`);

  // ── §42 TERMINATE ──────────────────────────────────────────────
  head('§42 종료 결정 → 세 면에서 함께 빠진다');
  // DEV 사업장의 활성 공고 쿼터(MAX_ACTIVE_TO_LIMIT) 안에서 두 번째 fixture 를
  // 만들려면 첫 fixture 공고를 먼저 마감해야 한다. canonical 관리자 동작이고,
  // 이미 만료된 공고라 마감이 상태를 왜곡하지 않는다.
  await callAs(ADMIN, 'callableCloseTOManually', {toId: st.toId})
      .then(() => log(`   첫 fixture 공고 마감 ${st.toId}`))
      .catch((e) => log(`   첫 fixture 공고 마감 생략 — ${e.message}`));
  const tApp = await buildExpiredFixture(
      st, 'terminateToId', 'terminateApplicationId', null, '만료 종료결정',
      ['03:20', '04:20']);
  check('§42 fixture 판정 = EXPIRED',
      decisionState(tApp, todayNum) === 'EXPIRED', decisionState(tApp, todayNum));
  // 이 fixture 는 계약서 서명 전이라 CONTRACT_PENDING 이다. 고정근무자 화면은
  // 이 상태에도 연장·종료 action 을 열어 준다 — 그래서 홈도 세야 한다.
  check('§42 fixture 는 CONTRACT_PENDING', tApp.status === 'CONTRACT_PENDING',
      tApp.status);
  const homeWithT = await homeContractSection();
  check('§26 CONTRACT_PENDING 만료 건도 Home 이 센다 — action 이 열려 있으므로',
      homeWithT.count === homeResolved.count + 1,
      `${homeResolved.count} → ${homeWithT.count}`);
  // canonical 종료 결정 writer 는 CF 가 아니라 관리자 클라이언트의
  // updateApplicationFields(화이트리스트 필드 renewalDecision) 직접 쓰기다.
  // 여기서는 같은 필드·같은 값만 쓴다. 뒤따르는 CANCELED 전환(effective
  // transition)은 이번 Phase 범위 밖이라 일부러 하지 않는다.
  await db.collection('applications').doc(st.terminateApplicationId)
      .update({renewalDecision: 'TERMINATE'});
  const tAfter = await loadApp(st.terminateApplicationId);
  check('§42 renewalDecision = TERMINATE', tAfter.renewalDecision === 'TERMINATE');
  check('§42 판정 = RESOLVED', decisionState(tAfter, todayNum) === 'RESOLVED');
  const homeAfterT = await homeContractSection();
  log(`   Home ${JSON.stringify(homeWithT)} → ${JSON.stringify(homeAfterT)}`);
  check('§42 종료 결정으로 Home task 가 빠진다',
      homeAfterT.count === homeWithT.count - 1,
      `${homeWithT.count} → ${homeAfterT.count}`);

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
