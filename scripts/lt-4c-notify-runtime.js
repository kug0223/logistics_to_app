#!/usr/bin/env node
/**
 * [.4C-RUNTIME.1] 근로자 계약 만료 알림 — 실제 KST 자정 scheduler runtime.
 *
 *   processContractRenewalChecks 는 masterScheduler 안에서
 *   `hour === 0 && minute < 10` (KST) 에만 돈다. 그래서 이 harness 는
 *   fixture 를 미리 만들어 두고, 자정 창이 지난 뒤 결과를 읽는다.
 *
 *   제품에 test-only 우회로를 넣지 않는다. 실제 배포된 scheduler 가
 *   실제 production predicate 로 무엇을 했는지만 본다.
 *
 *   node scripts/lt-4c-notify-runtime.js --project alfit-89567 --setup --execute
 *   node scripts/lt-4c-notify-runtime.js --project alfit-89567 --collect
 *   node scripts/lt-4c-notify-runtime.js --project alfit-89567 --cleanup --execute
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
const MODE = argv.includes('--cleanup') ? 'cleanup' :
  argv.includes('--collect') ? 'collect' : 'setup';

const fs = require('fs');
const path = require('path');
const {admin, db, callAs, kstMidnightMs, kstDateKey, kstWeekday} =
  require('./r7-fixture-lib');
const S = require('./r7-fixture-scenarios');

const BIZ = 'fLmSOHVKUwmBHcbwQE0I';
const ADMIN = 'BErRdiWP1xbgyoTovxwAPNEsuD72';
const WORKER = 'tJ8izfP2nNYN79aPTLb6YARiPqC3';
const WORK_TYPE = '사무업무';
const CONSENT_VERSION = '2026-09-18-v3';
const NS = 'LT4CNOTIFY';
const STATE = path.join(__dirname, '.lt-4c-notify-state.json');

const KST = 9 * 3600e3;
const iso = (t) => t ?
  new Date(t.toMillis() + KST).toISOString().slice(0, 10) : null;
const stamp = (t) => t ?
  new Date(t.toMillis() + KST).toISOString().slice(0, 19).replace('T', ' ') : null;
const Ts = (ms) => admin.firestore.Timestamp.fromMillis(ms);

const log = (...a) => console.log(...a);
const head = (s) => log(`\n${'═'.repeat(74)}\n ${s}\n${'═'.repeat(74)}`);
const sub = (s) => log(`\n── ${s} ${'─'.repeat(Math.max(0, 66 - s.length))}`);
const results = [];
const check = (label, ok, detail) => {
  results.push({label, ok});
  log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}${detail ? `\n          ${detail}` : ''}`);
};
let st = fs.existsSync(STATE) ? JSON.parse(fs.readFileSync(STATE, 'utf8')) : {};
const save = () => fs.writeFileSync(STATE, JSON.stringify(st, null, 2));
const remember = (k, v) => { st[k] = v; save(); return v; };

const loadApp = async (id) =>
  (await db.collection('applications').doc(id).get()).data();
const loadProposal = async (id) =>
  (await db.collection('renewal_proposals').doc(id).get()).data();

// ── R = scheduler 실행일 (다음 KST 자정) ─────────────────────────
//   setup 을 오늘 돌리면 다음 자정 창은 내일이다. 날짜는 전부 R 기준.
const R_OFFSET = 1;
const R = () => kstDateKey(R_OFFSET);

/** 자동결근이 처리할 "어제" = R-1 의 요일. 이 요일은 근무일로 쓰지 않는다. */
const NO_SHOW_DAY = () => kstWeekday(R_OFFSET - 1);

/**
 * 시나리오 정의.
 *
 *   workDays 에서 R-1 의 요일을 뺀다 — 그러면 자동결근 대상이 아니다.
 *   제품에 예외를 넣지 않고 **정상 상태**로 피한다.
 */
function scenarios() {
  const skip = NO_SHOW_DAY();
  const safe = ['월', '화', '수', '목', '금'].filter((d) => d !== skip);
  return [
    {key: 'n1', label: 'D-15 종료 예정', from: -2, to: R_OFFSET + 15,
      time: ['01:00', '02:00'], workDays: safe},
    {key: 'n2', label: 'D+1 미결정 종료', from: -2, to: R_OFFSET - 1,
      time: ['02:10', '03:10'], workDays: safe},
    {key: 'n3', label: 'D+1 연속 연장(E=D+1)', from: -2, to: R_OFFSET - 1,
      time: ['03:20', '04:20'], workDays: safe,
      accept: R_OFFSET, acceptEnd: R_OFFSET + 30},
    {key: 'n4', label: 'D+1 나중 시작 연장(E>D+1)', from: -2, to: R_OFFSET - 1,
      time: ['04:30', '05:30'], workDays: safe,
      accept: R_OFFSET + 3, acceptEnd: R_OFFSET + 33},
    {key: 'n5', label: 'D+1 응답 대기 제안', from: -2, to: R_OFFSET - 1,
      time: ['08:10', '09:10'], workDays: safe,
      proposeOnly: R_OFFSET + 2, proposeEnd: R_OFFSET + 32},
    {key: 'n6', label: 'D+1 만료된 제안(derived STALE)',
      from: -6, to: R_OFFSET - 1, time: ['00:00', '01:00'],
      workDays: [kstWeekday(R_OFFSET)], // R 요일만 — R 에 STALE 이 되게
      proposeOnly: R_OFFSET, proposeEnd: R_OFFSET + 30},
    {key: 'n7', label: 'D+1 관리자 종료 결정', from: -2, to: R_OFFSET - 1,
      time: ['09:20', '10:20'], workDays: safe, terminate: true},
  ];
}

const contractDataFor = async (applicationId) => {
  const app = await loadApp(applicationId);
  const biz = (await db.collection('businesses').doc(BIZ).get()).data();
  const worker = (await db.collection('users').doc(app.uid).get()).data();
  const bn = String(biz.businessNumber || '').replace(/\D/g, '');
  return {
    applicationId, businessId: BIZ, businessName: biz.name || '',
    workerId: app.uid, isLongTerm: true, toId: app.toId || '',
    workDetailId: `${app.selectedWorkType}_${app.startTime}_${app.endTime}`,
    slots: [], applicationIds: [applicationId],
    snapshot: {
      businessName: biz.name || '',
      businessNumber: bn.length === 10 ?
        `${bn.slice(0, 3)}-${bn.slice(3, 5)}-${bn.slice(5)}` : bn,
      businessAddress: [biz.address, biz.detailAddress].filter(Boolean).join(' '),
      businessPhone: biz.phone || null, ownerName: biz.ownerName || '',
      workerName: worker.name || '', workerBirthDate: null,
      workerPhone: worker.authPhone || worker.phone || null, workerAddress: null,
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

async function inventory(label) {
  const [ap, ec, at, rp] = await Promise.all([
    db.collection('applications').get(),
    db.collection('employment_contracts').get(),
    db.collection('attendance').get(),
    db.collection('renewal_proposals').get(),
  ]);
  const inv = {applications: ap.size, contracts: ec.size,
    attendance: at.size, renewal_proposals: rp.size};
  log(`  ${label}  ${JSON.stringify(inv)}`);
  return inv;
}

async function reliability(label) {
  const u = (await db.collection('users').doc(WORKER).get()).data();
  const r = {noShowCount: u.noShowCount ?? 0,
    recentNoShowCount: u.recentNoShowCount ?? 0,
    restricted: !!u.restrictedUntil};
  log(`  ${label}  ${JSON.stringify(r)}`);
  return r;
}

/** 이 지원서에 대해 그 사람이 받은 알림. */
async function notifs(uid, appId) {
  const s = await db.collection('users').doc(uid).collection('notifications')
      .where('data.applicationId', '==', appId).get();
  return s.docs.map((d) => ({
    id: d.id, type: d.data().type, title: d.data().title,
    body: d.data().body, data: d.data().data,
    createdAt: stamp(d.data().createdAt),
  }));
}

// ════════════════════════════════════════════════════════════════
// SETUP
// ════════════════════════════════════════════════════════════════
async function setup() {
  head(`SETUP   오늘=${kstDateKey(0)}(${kstWeekday(0)})  ` +
    `R=${R()}(${kstWeekday(R_OFFSET)})`);
  log(`  자동결근이 R 에 처리할 "어제" = ${kstDateKey(R_OFFSET - 1)}` +
      `(${NO_SHOW_DAY()}) → 이 요일을 근무일에서 뺀다`);
  log(`  D-15 대상일 = ${kstDateKey(R_OFFSET + 15)}`);
  log(`  D+1 대상일  = ${kstDateKey(R_OFFSET - 1)}`);

  await inventory('BEFORE');
  await reliability('BEFORE');
  if (!EXECUTE) { log('\ndry-run 종료. --execute 로 생성.'); return; }
  if (st.n1App) throw new Error('이미 setup 됨 — --cleanup --execute 후 재실행');

  remember('R', R());
  remember('setupAt', new Date().toISOString());

  for (const s of scenarios()) {
    sub(`${s.key}  ${s.label}`);
    const wd = S.workDetail({workType: WORK_TYPE, start: s.time[0],
      end: s.time[1], required: 1, wage: 15000});
    const to = await callAs(ADMIN, 'callableCreateTO', {
      toData: {
        businessId: BIZ, businessName: '위워커', type: 'contract',
        title: `[${NS}] ${s.key}`, description: '.4C-RUNTIME.1 notification',
        workDetails: [wd], totalSlots: 0, totalRequired: 1,
        totalConfirmed: 0, totalPending: 0,
        rangeStart: kstMidnightMs(s.from), rangeEnd: kstMidnightMs(s.to),
        workDays: s.workDays, deadlineType: 'HOURS_BEFORE', hoursBeforeStart: 2,
        contractPeriodType: 'custom', postingDurationDays: 30,
        creatorUID: ADMIN, publishMode: 'immediate',
        isPublished: true, status: 'ACTIVE', isManualClosed: false,
      },
    });
    remember(`${s.key}To`, to.toId);
    const ap = await callAs(WORKER, 'callableApplyToTO', {
      idCardConsentGiven: true, documentAccessConsentGiven: true,
      documentAccessConsentVersion: CONSENT_VERSION,
      toId: to.toId, slotId: null, businessId: BIZ, businessName: '위워커',
      toTitle: `[${NS}] ${s.key}`, selectedWorkType: WORK_TYPE,
      startTime: s.time[0], endTime: s.time[1],
      workDateMs: kstMidnightMs(s.from),
      workEndDateMs: kstMidnightMs(s.to),
      workDays: s.workDays, wage: 15000, wageType: 'hourly',
    });
    const appId = remember(`${s.key}App`, ap.applicationId || ap.id);
    await callAs(ADMIN, 'callableConfirmApplication',
        {applicationId: appId, businessId: BIZ});
    await callAs(ADMIN, 'callableCloseTOManually', {toId: to.toId})
        .catch(() => {});

    // 계약서 양측 서명 → CONFIRMED
    const cid = remember(`${s.key}Contract`,
        db.collection('employment_contracts').doc().id);
    await callAs(ADMIN, 'callableFinalizeEmployerSignature', {
      contractId: cid, signatureBase64: S.signaturePng().toString('base64'),
      isNewUnsaved: true, contractData: await contractDataFor(appId),
    });
    await callAs(WORKER, 'callableFinalizeWorkerSignature', {
      contractId: cid,
      signatureBase64: S.signaturePng(200, 80).toString('base64'),
      pdfBase64: S.onePagePdf([`[${NS}] ${s.key}`]).toString('base64'),
    });

    // [TEMPORAL FIXTURE SETUP] 확정 시각을 기간 앞으로 — canonical writer 로는
    //   만들 수 없는 시간 사전 상태다. 확정이 오늘이면 근무일 판정의
    //   confirmedAt 보정이 시작일을 오늘로 당겨 기간이 뒤틀린다.
    await db.collection('applications').doc(appId).update({
      confirmedAt: Ts(kstMidnightMs(s.from) + 5 * 3600e3),
    });

    if (s.accept !== undefined) {
      const p = await callAs(ADMIN, 'callableCreateRenewalProposal', {
        oldApplicationId: appId,
        effectiveStartMs: kstMidnightMs(s.accept),
        effectiveEndMs: kstMidnightMs(s.acceptEnd),
      });
      remember(`${s.key}Proposal`, p.proposalId);
      const acc = await callAs(WORKER, 'callableAcceptRenewalProposal',
          {proposalId: p.proposalId});
      remember(`${s.key}NewApp`, acc.newApplicationId);
      log(`  수락됨 → NEW ${acc.newApplicationId} E=${kstDateKey(s.accept)}`);
    }
    if (s.proposeOnly !== undefined) {
      const p = await callAs(ADMIN, 'callableCreateRenewalProposal', {
        oldApplicationId: appId,
        effectiveStartMs: kstMidnightMs(s.proposeOnly),
        effectiveEndMs: kstMidnightMs(s.proposeEnd),
      });
      remember(`${s.key}Proposal`, p.proposalId);
      log(`  제안만 → ${p.proposalId} E=${kstDateKey(s.proposeOnly)}`);
    }
    if (s.terminate) {
      // [TEMPORAL FIXTURE SETUP] 관리자 종료 결정의 canonical writer 는
      //   클라이언트의 whitelist 직접 쓰기다. 같은 필드·같은 값만 쓴다.
      await db.collection('applications').doc(appId)
          .update({renewalDecision: 'TERMINATE'});
      log('  renewalDecision = TERMINATE');
    }
    const a = await loadApp(appId);
    log(`  ${appId.slice(0, 26)}… ${a.status} ${iso(a.workDate)}~${iso(a.workEndDate)}` +
        ` workDays=${(a.workDays || []).join('')}`);
  }

  sub('setup 후 상태 확인');
  const relAfter = await reliability('AFTER ');
  await inventory('AFTER ');
  // 자동결근 후보가 되지 않는지 — scheduler 의 질의를 그대로 흉내낸다.
  const pop = await db.collection('applications')
      .where('status', 'in', ['CONFIRMED', 'CONTRACT_PENDING'])
      .where('workEndDate', '>=', Ts(kstMidnightMs(R_OFFSET - 1)))
      .limit(499).get();
  const mine = pop.docs.filter((d) =>
    Object.values(st).includes(d.id));
  const nsDay = kstDateKey(R_OFFSET - 1);
  const risky = mine.filter((d) => {
    const a = d.data();
    return Array.isArray(a.workDays) && a.workDays.includes(NO_SHOW_DAY()) &&
      iso(a.workDate) <= nsDay && nsDay <= iso(a.workEndDate);
  });
  log(`  자동결근 질의에 걸린 runtime 지원서 ${mine.length}건 · ` +
      `그중 ${nsDay}(${NO_SHOW_DAY()}) 근무일 ${risky.length}건`);
  check('setup — 자동결근 위험 0', risky.length === 0,
      risky.map((d) => d.id.slice(0, 20)).join(','));
  check('setup — 신뢰도 무변화', !relAfter.restricted);
  log(`\n  R=${R()} 자정 창(00:00~00:09 KST) 이후 --collect 로 결과를 읽는다.`);
}

// ════════════════════════════════════════════════════════════════
// COLLECT
// ════════════════════════════════════════════════════════════════
async function collect() {
  head(`COLLECT   R=${st.R}  지금=${new Date(Date.now() + KST)
      .toISOString().slice(0, 19).replace('T', ' ')} KST`);
  if (!st.n1App) throw new Error('setup 기록이 없다.');

  // 기대값은 **저장된 기준일 R** 에 고정한다.
  //
  //   kstDateKey/kstMidnightMs 는 Date.now() 기준이다. 그런데 collect 는
  //   정의상 자정을 넘겨 실행되므로, 실행일이 바뀌는 순간 기대 날짜가
  //   통째로 하루 밀린다. setup(9/24)의 kstDateKey(R_OFFSET+15) 와
  //   collect(9/25)의 같은 식은 서로 다른 날을 가리킨다 — 그러면 제품이
  //   맞게 동작해도 FAIL 이 난다. fixture 가 실제로 무슨 날짜로 만들어졌는지는
  //   st.R 만이 알고 있다.
  const rMid = (k = 0) => {
    const [y, m, d] = st.R.split('-').map(Number);
    return Date.UTC(y, m - 1, d + k) - KST;
  };
  const rKey = (k = 0) =>
    new Date(rMid(k) + KST).toISOString().slice(0, 10);

  const rows = [];
  for (const s of scenarios()) {
    const appId = st[`${s.key}App`];
    sub(`${s.key}  ${s.label}`);
    const app = await loadApp(appId);
    const wn = await notifs(WORKER, appId);
    const an = await notifs(ADMIN, appId);
    const expiring = wn.filter((n) => n.type === 'workerContractExpiring');
    const ended = wn.filter((n) => n.type === 'workerContractEnded');
    const adminRem = an.filter((n) => n.type === 'contractExpiringReminder');
    const terminating = wn.filter((n) => n.type === 'contractTerminating');
    log(`  기간 ${iso(app.workDate)}~${iso(app.workEndDate)} · ` +
        `renewalDecision=${app.renewalDecision ?? 'null'}`);
    log(`  근로자 알림 ${JSON.stringify(wn.map((n) => n.type))}`);
    log(`  관리자 알림 ${JSON.stringify(an.map((n) => n.type))}`);
    for (const n of [...expiring, ...ended, ...terminating]) {
      log(`    · ${n.type}  id=${n.id}`);
      log(`      "${n.title}" / "${n.body}"`);
      log(`      data=${JSON.stringify(n.data)} createdAt=${n.createdAt}`);
    }
    rows.push({key: s.key, expiring: expiring.length, ended: ended.length,
      terminating: terminating.length, adminRem: adminRem.length,
      renewalDecision: app.renewalDecision ?? null});

    // 공통 — 도메인 불변
    const newApps = await db.collection('applications')
        .where('renewedFromApplicationId', '==', appId).get();
    const expectNew = s.accept !== undefined ? 1 : 0;
    check(`${s.key} 새 계약 ${expectNew}건 — scheduler 가 만들지 않았다`,
        newApps.size === expectNew, `${newApps.size}건`);
    const expectDecision = s.terminate ? 'TERMINATE' :
      (s.accept !== undefined ? 'EXTEND' : null);
    check(`${s.key} renewalDecision 불변`,
        (app.renewalDecision ?? null) === expectDecision,
        `${app.renewalDecision ?? 'null'} (기대 ${expectDecision})`);

    if (s.key === 'n1') {
      check('N1 근로자 종료 예정 알림 1건', expiring.length === 1,
          `${expiring.length}건`);
      check('N1 종료 알림은 없다', ended.length === 0);
      check('N1 관리자 D-15 리마인더도 살아 있다', adminRem.length === 1,
          `${adminRem.length}건`);
      if (expiring[0]) {
        const d = expiring[0].data || {};
        check('N1 payload 가 이 관계를 가리킨다',
            d.applicationId === appId && d.businessId === BIZ &&
            !!d.expiryDate && d.screen === 'mySchedule',
            JSON.stringify(d));
        check('N1 dedupe id 가 applicationId + 날짜다',
            expiring[0].id ===
              `worker_contract_expiring_${appId}_${rKey(15).replace(/-/g, '')}`,
            expiring[0].id);
      }
    }
    if (s.key === 'n2') {
      check('N2 종료 알림 1건', ended.length === 1, `${ended.length}건`);
      check('N2 종료 예정 알림은 없다', expiring.length === 0);
      if (ended[0]) {
        check('N2 문구가 사실만 말한다',
            ended[0].body.includes('기존 계약기간이') &&
            ended[0].body.includes('새로운 근무 일정이 확정되면'),
            ended[0].body);
        for (const banned of ['퇴사', '해고', '재입사', '근로관계 종료']) {
          check(`N2 "${banned}" 문구 없음`, !ended[0].body.includes(banned));
        }
      }
    }
    if (s.key === 'n3') {
      check('N3 연속 연장 — 종료 알림 억제', ended.length === 0,
          `${ended.length}건`);
      const nw = newApps.docs[0] && newApps.docs[0].data();
      check('N3 새 계약이 D+1 에 이어진다',
          nw && iso(nw.workDate) === rKey(0),
          nw ? iso(nw.workDate) : '없음');
    }
    if (s.key === 'n4') {
      check('N4 종료 알림 1건', ended.length === 1, `${ended.length}건`);
      if (ended[0]) {
        check('N4 문구가 새 시작일을 말한다',
            ended[0].body.includes('새 계약은') &&
            ended[0].body.includes(`${new Date(rMid(3) + KST).getUTCMonth() + 1}/`),
            ended[0].body);
      }
      const nw = newApps.docs[0] && newApps.docs[0].data();
      if (nw) {
        const gapDays = [];
        for (let o = 0; o < 3; o++) {
          gapDays.push(`${rKey(o)}`);
        }
        log(`  공백 ${gapDays.join(', ')} — NEW 시작 ${iso(nw.workDate)}`);
        check('N4 공백은 새 계약 시작 전이다',
            iso(nw.workDate) === rKey(3));
        const att = await db.collection('attendance')
            .where('applicationId', '==', newApps.docs[0].id).get();
        check('N4 공백에 근태 0건', att.size === 0, `${att.size}건`);
      }
    }
    if (s.key === 'n5') {
      const p = await loadProposal(st.n5Proposal);
      check('N5 제안이 여전히 PENDING', p.status === 'PENDING', p.status);
      check('N5 종료 알림 1건', ended.length === 1, `${ended.length}건`);
      if (ended[0]) {
        check('N5 문구가 확인 중인 제안을 말한다',
            ended[0].body.includes('확인 중인 연장 제안'), ended[0].body);
      }
      const mine = (await callAs(WORKER, 'callableGetMyRenewalProposals', {}))
          .proposals || [];
      check('N5 근로자 할 일이 그대로 남아 있다',
          mine.some((x) => x.id === st.n5Proposal), `${mine.length}건`);
    }
    if (s.key === 'n6') {
      const p = await loadProposal(st.n6Proposal);
      check('N6 제안은 저장상 PENDING', p.status === 'PENDING', p.status);
      check('N6 종료 알림 1건', ended.length === 1, `${ended.length}건`);
      if (ended[0]) {
        check('N6 만료된 제안을 "확인 중"이라 하지 않는다',
            !ended[0].body.includes('확인 중인 연장 제안'), ended[0].body);
      }
      const mine = (await callAs(WORKER, 'callableGetMyRenewalProposals', {}))
          .proposals || [];
      check('N6 근로자 할 일에도 없다',
          !mine.some((x) => x.id === st.n6Proposal));
    }
    if (s.key === 'n7') {
      check('N7 generic 종료 알림 없음 — contractTerminating 이 주인',
          ended.length === 0, `${ended.length}건`);
      check('N7 contractTerminating 1건', terminating.length === 1,
          `${terminating.length}건`);
    }
  }

  sub('같은 근로자 · 같은 날 · 여러 계약');
  const sameDay = rows.filter((r) => ['n2', 'n4', 'n5', 'n6'].includes(r.key));
  log(`  ${rKey(-1)} 종료 계약 ${sameDay.length}건 · ` +
      `각 종료 알림 ${sameDay.map((r) => r.ended).join('/')}`);
  check('계약마다 따로 알림이 간다 — worker+date 로 뭉치지 않는다',
      sameDay.every((r) => r.ended === 1));

  sub('회귀');
  await reliability('AFTER ');
  const ok7 = true;
  void ok7;
  log('\n  결과 표');
  log('  key  expiring ended terminating adminReminder renewalDecision');
  rows.forEach((r) => log(`  ${r.key}   ${r.expiring}        ${r.ended}` +
    `     ${r.terminating}           ${r.adminRem}         ${r.renewalDecision}`));
}

// ════════════════════════════════════════════════════════════════
// CLEANUP
// ════════════════════════════════════════════════════════════════
async function cleanup() {
  head('CLEANUP — manifest exact id 만');
  const before = await inventory('BEFORE');
  const relBefore = await reliability('BEFORE');
  const appIds = Object.entries(st)
      .filter(([k]) => k.endsWith('App') || k.endsWith('NewApp'))
      .map(([, v]) => v).filter(Boolean);
  const proposalIds = Object.entries(st)
      .filter(([k]) => k.endsWith('Proposal')).map(([, v]) => v).filter(Boolean);
  const contractIds = Object.entries(st)
      .filter(([k]) => k.endsWith('Contract')).map(([, v]) => v).filter(Boolean);
  const toIds = Object.entries(st)
      .filter(([k]) => k.endsWith('To')).map(([, v]) => v).filter(Boolean);

  for (const uid of [WORKER, ADMIN]) {
    const col = db.collection('users').doc(uid).collection('notifications');
    const seen = new Map();
    for (const aid of appIds) {
      (await col.where('data.applicationId', '==', aid).get())
          .docs.forEach((d) => seen.set(d.id, d.ref));
    }
    for (const pid of proposalIds) {
      (await col.where('data.proposalId', '==', pid).get())
          .docs.forEach((d) => seen.set(d.id, d.ref));
    }
    if (seen.size) log(`  알림 ${seen.size}건 (${uid.slice(0, 10)}…)`);
    if (EXECUTE) for (const r of seen.values()) await r.delete();
  }
  for (const aid of appIds) {
    const s = await db.collection('attendance')
        .where('applicationId', '==', aid).get();
    for (const d of s.docs) {
      log(`  근태 ${d.id.slice(-30)}`);
      if (EXECUTE) await d.ref.delete();
    }
  }
  for (const cid of contractIds) {
    const ref = db.collection('employment_contracts').doc(cid);
    if (!(await ref.get()).exists) continue;
    log(`  계약서 ${cid}`);
    if (EXECUTE) {
      await ref.delete();
      const {devBucket} = require('./r7-fixture-lib');
      const [files] = await devBucket().getFiles({prefix: `contracts/${cid}/`});
      for (const f of files) await f.delete();
    }
  }
  for (const pid of proposalIds) {
    const ref = db.collection('renewal_proposals').doc(pid);
    if (!(await ref.get()).exists) continue;
    log(`  제안 ${pid}`);
    if (EXECUTE) await ref.delete();
  }
  for (const aid of appIds) {
    const ref = db.collection('applications').doc(aid);
    if (!(await ref.get()).exists) continue;
    log(`  지원서 ${aid.slice(0, 40)}`);
    if (EXECUTE) await ref.delete();
  }
  for (const tid of toIds) {
    const others = await db.collection('applications')
        .where('toId', '==', tid).get();
    if (others.docs.some((d) => !appIds.includes(d.id))) {
      log(`  공고 ${tid} — 남의 지원서, 남긴다`); continue;
    }
    log(`  공고 ${tid}`);
    if (EXECUTE) await db.collection('tos').doc(tid).delete();
  }
  if (!EXECUTE) { log('\ndry-run — 아무것도 지우지 않았습니다.'); return; }
  const after = await inventory('AFTER ');
  const relAfter = await reliability('AFTER ');
  log(`  delta ${JSON.stringify({
    applications: after.applications - before.applications,
    contracts: after.contracts - before.contracts,
    attendance: after.attendance - before.attendance,
    renewal_proposals: after.renewal_proposals - before.renewal_proposals,
  })}`);
  check('신뢰도 변화 없음',
      relAfter.noShowCount === relBefore.noShowCount &&
      relAfter.restricted === relBefore.restricted);
  if (fs.existsSync(STATE)) fs.unlinkSync(STATE);
}

const main = MODE === 'cleanup' ? cleanup : MODE === 'collect' ? collect : setup;
main().then(() => {
  const failed = results.filter((r) => !r.ok);
  if (results.length) {
    log(`\n  ${results.length - failed.length}/${results.length} PASS`);
    failed.forEach((r) => log(`    · ${r.label}`));
  }
  process.exit(failed.length ? 1 : 0);
}).catch((e) => {
  console.error('\n실패:', e && e.stack ? e.stack : e);
  process.exit(1);
});
