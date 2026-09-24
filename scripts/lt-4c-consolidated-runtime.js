#!/usr/bin/env node
/**
 * [.4C-RUNTIME] late renewal → proposal → commitment → expiry 통합 DEV runtime.
 *
 * 증명하려는 하나의 문장:
 *
 *   관리자 제안은 약속이 아니고, 근로자가 수락해야 좌석과 근무 의무가
 *   생기며, 그 시작일은 명시적으로 정해지고, 공백에는 아무 의무도 없다.
 *
 *   node scripts/lt-4c-consolidated-runtime.js --project alfit-89567
 *   node scripts/lt-4c-consolidated-runtime.js --project alfit-89567 --execute
 *   node scripts/lt-4c-consolidated-runtime.js --project alfit-89567 --cleanup --execute
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
const {admin, db, callAs, kstMidnightMs, kstDateKey, kstWeekday} =
  require('./r7-fixture-lib');
const S = require('./r7-fixture-scenarios');

const BIZ = 'fLmSOHVKUwmBHcbwQE0I';
const OTHER_BIZ = '0GweEvbpP6KA7v14FMLb';
const ADMIN = 'BErRdiWP1xbgyoTovxwAPNEsuD72';
const SUBADMIN = 'kN2gNpEhLLVjQD7KLGSnNFJHd2v2';
const WORKER = 'tJ8izfP2nNYN79aPTLb6YARiPqC3';
const OTHER_WORKER = 'J6lVRGSFsBewqvWy0gFE46YQI9z1';
const WORK_TYPE = '사무업무';
const CONSENT_VERSION = '2026-09-18-v3';
const NS = 'LT4CRUNTIME';
const STATE = path.join(__dirname, '.lt-4c-runtime-state.json');
const ALL_DAYS = ['월', '화', '수', '목', '금', '토', '일'];

const KST = 9 * 3600e3;
const iso = (ts) => ts ?
  new Date(ts.toMillis() + KST).toISOString().slice(0, 10) : null;
const Ts = (ms) => admin.firestore.Timestamp.fromMillis(ms);

const log = (...a) => console.log(...a);
const head = (s) => log(`\n${'═'.repeat(74)}\n ${s}\n${'═'.repeat(74)}`);
const sub = (s) => log(`\n── ${s} ${'─'.repeat(Math.max(0, 68 - s.length))}`);
const results = [];
const check = (label, ok, detail) => {
  results.push({label, ok});
  log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}${detail ? `\n          ${detail}` : ''}`);
};
const readState = () =>
  fs.existsSync(STATE) ? JSON.parse(fs.readFileSync(STATE, 'utf8')) : {};
let st = readState();
const save = () => fs.writeFileSync(STATE, JSON.stringify(st, null, 2));
const remember = (k, v) => { st[k] = v; save(); return v; };

const loadApp = async (id) =>
  (await db.collection('applications').doc(id).get()).data();
const loadProposal = async (id) =>
  (await db.collection('renewal_proposals').doc(id).get()).data();

/** 서버 srvRenewalProposalEffectiveStatus 의 거울 — 판정을 눈으로 본다. */
function effectiveStatus(p, now) {
  if (p.status !== 'PENDING') return p.status;
  const dn = (t) => {
    const k = new Date(t.toMillis() + KST);
    return k.getUTCFullYear() * 10000 + (k.getUTCMonth() + 1) * 100 + k.getUTCDate();
  };
  const dnNow = (d) => {
    const k = new Date(d.getTime() + KST);
    return k.getUTCFullYear() * 10000 + (k.getUTCMonth() + 1) * 100 + k.getUTCDate();
  };
  const s = dn(p.effectiveStart); const t = dnNow(now);
  if (s < t) return 'STALE';
  if (s > t) return 'PENDING';
  const ko = ['일', '월', '화', '수', '목', '금', '토'];
  const kstNow = new Date(now.getTime() + KST);
  if (Array.isArray(p.workDays) && p.workDays.length &&
      !p.workDays.includes(ko[kstNow.getUTCDay()])) return 'PENDING';
  const m = /^(\d{1,2}):(\d{2})$/.exec(p.startTime || '');
  if (!m) return 'PENDING';
  const nowMin = kstNow.getUTCHours() * 60 + kstNow.getUTCMinutes();
  return nowMin > Number(m[1]) * 60 + Number(m[2]) ? 'STALE' : 'PENDING';
}

/** 근무일 판정 — 서버 srvLongTermEligibleOnDay 의 거울. */
function eligibleOn(app, offset) {
  const dn = (t) => {
    const k = new Date(t.toMillis() + KST);
    return k.getUTCFullYear() * 10000 + (k.getUTCMonth() + 1) * 100 + k.getUTCDate();
  };
  const ms = kstMidnightMs(offset);
  const k = new Date(ms + KST);
  const dayNum = k.getUTCFullYear() * 10000 + (k.getUTCMonth() + 1) * 100 + k.getUTCDate();
  const wkd = kstWeekday(offset);
  const desired = app.desiredStartDate;
  let start = desired ? dn(desired) : (app.workDate ? dn(app.workDate) : 0);
  if (!desired && app.confirmedAt) {
    const c = dn(app.confirmedAt); if (c > start) start = c;
  }
  if (dayNum < start) return 'BEFORE_START';
  const end = app.actualResignDate || app.workEndDate;
  if (!end) return 'NO_END';
  if (dayNum > dn(end)) return app.actualResignDate ? 'AFTER_RESIGN' : 'AFTER_END';
  const wd = app.workDays;
  if (!Array.isArray(wd) || !wd.length || !wd.includes(wkd)) return 'NON_WORKDAY';
  return 'ELIGIBLE';
}

const homeContract = async () => {
  const r = await callAs(ADMIN, 'callableGetAdminHomeSummary', {});
  return (r && r.upcoming && r.upcoming.expiringContract) || null;
};
const bizProposals = async () =>
  ((await callAs(ADMIN, 'callableGetRenewalProposalsByBiz', {businessId: BIZ}))
      .proposals) || [];
const myProposals = async (uid) =>
  ((await callAs(uid, 'callableGetMyRenewalProposals', {})).proposals) || [];

async function notificationsFor(uid, appId) {
  const s = await db.collection('users').doc(uid).collection('notifications')
      .where('data.applicationId', '==', appId).get();
  return s.docs.map((d) => ({id: d.id, type: d.data().type, body: d.data().body}));
}

async function inventory(label) {
  const [ap, ec, at, tos, rp] = await Promise.all([
    db.collection('applications').get(),
    db.collection('employment_contracts').get(),
    db.collection('attendance').get(),
    db.collection('tos').get(),
    db.collection('renewal_proposals').get(),
  ]);
  const inv = {applications: ap.size, contracts: ec.size, attendance: at.size,
    tos: tos.size, renewal_proposals: rp.size};
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

// ════════════════════════════════════════════════════════════════
// fixture 생성 — canonical writer 로
// ════════════════════════════════════════════════════════════════

/**
 * 장기 근무관계 하나. 공고는 만들자마자 마감한다(활성 공고 쿼터).
 * @param {string} key 시나리오 키
 * @param {object} o 기간·시간·근로자
 * @return {Promise<string>} applicationId
 */
async function makeRelation(key, o) {
  const kTo = `${key}To`; const kApp = `${key}App`;
  if (!st[kTo]) {
    const wd = S.workDetail({workType: WORK_TYPE, start: o.startTime,
      end: o.endTime, required: 1, wage: 15000});
    const r = await callAs(ADMIN, 'callableCreateTO', {
      toData: {
        businessId: BIZ, businessName: '위워커', type: 'contract',
        title: `[${NS}] ${key}`,
        description: '.4C consolidated runtime',
        workDetails: [wd], totalSlots: 0, totalRequired: 1,
        totalConfirmed: 0, totalPending: 0,
        rangeStart: kstMidnightMs(o.from), rangeEnd: kstMidnightMs(o.to),
        workDays: o.workDays || ALL_DAYS,
        deadlineType: 'HOURS_BEFORE', hoursBeforeStart: 2,
        contractPeriodType: 'custom', postingDurationDays: 30,
        creatorUID: ADMIN, publishMode: 'immediate',
        isPublished: true, status: 'ACTIVE', isManualClosed: false,
      },
    });
    remember(kTo, r.toId);
  }
  if (!st[kApp]) {
    const r = await callAs(o.worker || WORKER, 'callableApplyToTO', {
      idCardConsentGiven: true, documentAccessConsentGiven: true,
      documentAccessConsentVersion: CONSENT_VERSION,
      toId: st[kTo], slotId: null, businessId: BIZ, businessName: '위워커',
      toTitle: `[${NS}] ${key}`, selectedWorkType: WORK_TYPE,
      startTime: o.startTime, endTime: o.endTime,
      workDateMs: kstMidnightMs(o.from),
      workEndDateMs: kstMidnightMs(o.to),
      workDays: o.workDays || ALL_DAYS, wage: 15000, wageType: 'hourly',
    });
    remember(kApp, r.applicationId || r.id);
  }
  if ((await loadApp(st[kApp])).status === 'PENDING') {
    await callAs(ADMIN, 'callableConfirmApplication',
        {applicationId: st[kApp], businessId: BIZ});
  }
  await callAs(ADMIN, 'callableCloseTOManually', {toId: st[kTo]}).catch(() => {});

  // [DEV FIXTURE SETUP] 확정 시각을 근무 이력 앞으로 되돌린다.
  //
  //   canonical writer 로는 만들 수 없는 **시간적 사전 상태**다. 확정은
  //   지금 일어나므로 confirmedAt 이 오늘이 되고, 근무일 판정의
  //   confirmedAt 보정이 시작일을 오늘로 당긴다. 그러면 '이미 끝난
  //   계약'이 '아직 시작도 안 한 계약'으로 읽혀 공백 증거가 엉뚱한
  //   이유로 통과한다.
  //
  //   실제 운영에서 과거 계약은 과거에 확정됐다. 그 사실만 복원한다.
  if (o.confirmedAtOffset !== undefined) {
    await db.collection('applications').doc(st[kApp]).update({
      confirmedAt: Ts(kstMidnightMs(o.confirmedAtOffset) + 5 * 3600e3),
    });
  }
  return st[kApp];
}

/** 계약서 양측 서명까지 — CONFIRMED 로 만든다. */
async function signContract(key, appId) {
  const kC = `${key}Contract`;
  if (!st[kC]) remember(kC, db.collection('employment_contracts').doc().id);
  const ref = db.collection('employment_contracts').doc(st[kC]);
  if (!(await ref.get()).exists) {
    await callAs(ADMIN, 'callableFinalizeEmployerSignature', {
      contractId: st[kC],
      signatureBase64: S.signaturePng().toString('base64'),
      isNewUnsaved: true, contractData: await contractDataFor(appId),
    });
  }
  const c = (await ref.get()).data();
  if (!c.workerSignatureUrl) {
    await callAs(WORKER, 'callableFinalizeWorkerSignature', {
      contractId: st[kC],
      signatureBase64: S.signaturePng(200, 80).toString('base64'),
      pdfBase64: S.onePagePdf([`[${NS}] DEV runtime.`]).toString('base64'),
    });
  }
  return st[kC];
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

/** 마지막 근무일을 완결시킨다 — scheduler 가 없는 결근을 만들지 않게. */
async function completeDay(appId, offset) {
  const ms = kstMidnightMs(offset);
  const attId = `${appId}_${kstDateKey(offset).replace(/-/g, '')}`;
  if ((await db.collection('attendance').doc(attId).get()).exists) return attId;
  const app = await loadApp(appId);
  await callAs(ADMIN, 'callableBatchCheckIn', {
    businessId: BIZ,
    entries: [{applicationId: appId, workDateMs: ms, userId: app.uid,
      businessId: BIZ, businessName: '위워커', workType: WORK_TYPE,
      status: 'present', checkInMs: ms + 1 * 3600e3}],
  });
  await callAs(ADMIN, 'callableBatchCheckOut', {
    businessId: BIZ,
    entries: [{attendanceId: attId, checkOutMs: ms + 2 * 3600e3,
      workHours: 1, status: 'present', resetWageDetail: false}],
  });
  return attId;
}

// ════════════════════════════════════════════════════════════════
// cleanup
// ════════════════════════════════════════════════════════════════
async function cleanup() {
  head('CLEANUP — manifest exact id 만');
  const before = await inventory('BEFORE');
  const relBefore = await reliability('BEFORE');

  const appIds = Object.entries(st)
      .filter(([k]) => k.endsWith('App') || k.endsWith('NewApp'))
      .map(([, v]) => v).filter(Boolean);
  const contractIds = Object.entries(st)
      .filter(([k]) => k.endsWith('Contract')).map(([, v]) => v).filter(Boolean);
  const toIds = Object.entries(st)
      .filter(([k]) => k.endsWith('To')).map(([, v]) => v).filter(Boolean);
  const proposalIds = Object.entries(st)
      .filter(([k]) => k.toLowerCase().includes('proposal'))
      .map(([, v]) => v).filter((v) => typeof v === 'string');

  sub('근태');
  for (const aid of appIds) {
    const s = await db.collection('attendance')
        .where('applicationId', '==', aid).get();
    for (const d of s.docs) {
      log(`  삭제 attendance ${d.id.slice(-30)}`);
      if (EXECUTE) await d.ref.delete();
    }
  }
  sub('알림');
  for (const uid of [WORKER, OTHER_WORKER, ADMIN]) {
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
    if (seen.size) log(`  삭제 알림 ${seen.size}건 (${uid.slice(0, 10)}…)`);
    if (EXECUTE) for (const r of seen.values()) await r.delete();
  }
  sub('계약서');
  for (const cid of contractIds) {
    const ref = db.collection('employment_contracts').doc(cid);
    if (!(await ref.get()).exists) continue;
    log(`  삭제 contract ${cid}`);
    if (EXECUTE) {
      await ref.delete();
      const {devBucket} = require('./r7-fixture-lib');
      const [files] = await devBucket().getFiles({prefix: `contracts/${cid}/`});
      for (const f of files) await f.delete();
    }
  }
  sub('제안');
  for (const pid of proposalIds) {
    const ref = db.collection('renewal_proposals').doc(pid);
    if (!(await ref.get()).exists) continue;
    log(`  삭제 proposal ${pid}`);
    if (EXECUTE) await ref.delete();
  }
  sub('지원서');
  for (const aid of appIds) {
    const ref = db.collection('applications').doc(aid);
    if (!(await ref.get()).exists) continue;
    log(`  삭제 application ${aid.slice(0, 40)}`);
    if (EXECUTE) await ref.delete();
  }
  sub('공고');
  for (const tid of toIds) {
    const others = await db.collection('applications')
        .where('toId', '==', tid).get();
    if (others.docs.some((d) => !appIds.includes(d.id))) {
      log(`  공고 ${tid} — 남의 지원서, 남긴다`); continue;
    }
    log(`  삭제 TO ${tid}`);
    if (EXECUTE) await db.collection('tos').doc(tid).delete();
  }

  if (!EXECUTE) { log('\ndry-run — 아무것도 지우지 않았습니다.'); return; }

  head('CLEANUP 결과');
  const after = await inventory('AFTER ');
  const relAfter = await reliability('AFTER ');
  log(`  delta ${JSON.stringify({
    applications: after.applications - before.applications,
    contracts: after.contracts - before.contracts,
    attendance: after.attendance - before.attendance,
    tos: after.tos - before.tos,
    renewal_proposals: after.renewal_proposals - before.renewal_proposals,
  })}`);
  check('신뢰도 변화 없음',
      relAfter.noShowCount === relBefore.noShowCount &&
      relAfter.recentNoShowCount === relBefore.recentNoShowCount &&
      relAfter.restricted === relBefore.restricted);
  if (fs.existsSync(STATE)) fs.unlinkSync(STATE);
}

module.exports = {
  // 시나리오 본문은 part2 에서 이어진다.
  db, callAs, check, log, head, sub, results, st, remember, save,
  makeRelation, signContract, completeDay, loadApp, loadProposal,
  homeContract, bizProposals, myProposals, notificationsFor,
  inventory, reliability, effectiveStatus, eligibleOn, iso, Ts,
  BIZ, OTHER_BIZ, ADMIN, SUBADMIN, WORKER, OTHER_WORKER, NS, ALL_DAYS,
  EXECUTE, CLEANUP, cleanup, contractDataFor,
};

if (require.main === module) {
  const run = require('./lt-4c-runtime-scenarios');
  (CLEANUP ? cleanup() : run())
      .then(() => {
        const failed = results.filter((r) => !r.ok);
        if (results.length) {
          log(`\n  ${results.length - failed.length}/${results.length} PASS`);
          failed.forEach((r) => log(`    · ${r.label}`));
        }
        process.exit(failed.length ? 1 : 0);
      })
      .catch((e) => {
        console.error('\n실패:', e && e.stack ? e.stack : e);
        process.exit(1);
      });
}
