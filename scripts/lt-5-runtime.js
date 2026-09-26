#!/usr/bin/env node
/**
 * [.5-RUNTIME] termination / resignation effective-date · permission ownership
 *
 *   승인은 결정이고 효력은 D+1 에 온다 — 이걸 실제 배포본으로 확인한다.
 *   auto approval 과 effective transition 은 masterScheduler 의 자정 창
 *   (`hour === 0 && minute < 10`) 에서만 돈다. 그래서 callable 시나리오는
 *   오늘 돌리고, scheduler 시나리오는 자정을 넘긴 뒤 collect 한다.
 *
 *   제품에 test 우회로를 넣지 않는다. fixture 의 사전 상태만 구성한다.
 *
 *   node scripts/lt-5-runtime.js --project alfit-89567 --setup --execute
 *   node scripts/lt-5-runtime.js --project alfit-89567 --collect
 *   node scripts/lt-5-runtime.js --project alfit-89567 --cleanup --execute
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
const BIZ_NAME = '위워커';
const ADMIN = 'BErRdiWP1xbgyoTovxwAPNEsuD72';
const WORKER = 'tJ8izfP2nNYN79aPTLb6YARiPqC3';
const OTHER = 'J6lVRGSFsBewqvWy0gFE46YQI9z1';
// [DUAL-ROLE 순서] callableApplyToTO 는 "관리자로 등록된 사업장의 공고에는
//   지원할 수 없습니다"로 막는다(이해충돌 가드). 그래서 같은 사업장에서
//   worker + SubAdmin 이 되는 경로는 **근로자 먼저 → 이후 관리자 초대**뿐이다.
//   fixture 도 그 순서를 따른다: 지원·확정을 끝낸 뒤 멤버십을 부여한다.
//   이 멤버십은 우리가 만든 것이므로 cleanup 에서 제거한다.
//   OTHER(J6lVRGSF…) 는 이 사업장의 신분증 확인이 없어 확정 자체가 막힌다
//   (`callableConfirmApplication` → "신분증 확인이 필요합니다"). 그래서
//   dual-role 대상은 확정 가능한 WORKER 로 둔다.
const DUAL = 'tJ8izfP2nNYN79aPTLb6YARiPqC3'; // = WORKER
const DUAL_PERMS = {
  canManageTo: true, canManageWorkers: true, canManageContract: true,
  canManageWage: true, canCancelTransfer: true,
};
const WORK_TYPE = '사무업무';
const CONSENT_VERSION = '2026-09-18-v3';
const NS = 'LT5RT';
const STATE = path.join(__dirname, '.lt-5-runtime-state.json');

const KST = 9 * 3600e3;
const Ts = (ms) => admin.firestore.Timestamp.fromMillis(ms);
const iso = (t) => t ?
  new Date(t.toMillis() + KST).toISOString().slice(0, 10) : null;

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
const loadTo = async (id) => (await db.collection('tos').doc(id).get()).data();
const loadContract = async (id) =>
  (await db.collection('employment_contracts').doc(id).get()).data();

// [.5-PATCH.1 §22] 계정 전역 세션 무효화의 관측 가능한 신호.
const tokensValidAfter = async (uid) =>
  (await admin.auth().getUser(uid)).tokensValidAfterTime || null;

const membershipOf = async (uid) => {
  const u = (await db.collection('users').doc(uid).get()).data() || {};
  const m = await db.collection('businesses').doc(BIZ)
      .collection('members').doc(uid).get();
  return {
    subAdminBusinessIds: (u.subAdminBusinessIds || []).slice().sort(),
    subAdminOf: u.subAdminOf ?? null,
    memberExists: m.exists,
    permissions: m.exists ? ((m.data() || {}).permissions || {}) : null,
    role: u.role ?? null,
  };
};
const sameMembership = (a, b) => JSON.stringify(a) === JSON.stringify(b);

const inventory = async (label) => {
  const out = {};
  for (const c of ['applications', 'employment_contracts', 'attendance']) {
    out[c] = (await db.collection(c).count().get()).data().count;
  }
  log(`  ${label} ${JSON.stringify(out)}`);
  return out;
};
const reliability = async (label) => {
  const out = {};
  for (const [k, uid] of [['WORKER', WORKER], ['OTHER', OTHER]]) {
    const u = (await db.collection('users').doc(uid).get()).data() || {};
    out[k] = {n: u.noShowCount ?? null, r: u.recentNoShowCount ?? null,
      restricted: u.restricted === true};
  }
  log(`  ${label} ${JSON.stringify(out)}`);
  return out;
};

// ════════════════════════════════════════════════════════════════
// 시나리오 정의
//
//   [§54] 오늘(=자정 scheduler 가 처리할 "어제")의 요일을 근무일에서 뺀다.
//   그래야 fixture 때문에 자동 NO_SHOW·신뢰도 사건이 생기지 않는다.
// ════════════════════════════════════════════════════════════════
const TODAY_WD = () => kstWeekday(0);
const SAFE_DAYS = () =>
  ['월', '화', '수', '목', '금'].filter((d) => d !== TODAY_WD());

// [시간대 선택] 이 DEV 근로자는 09:00~19:00 과 23:05~23:57 에 이미 확정된
//   단기 근무가 있다. 장기 fixture 가 그 시간대를 쓰면 서버가
//   "확정된 근무가 있어 지원할 수 없습니다"로 막는다 — 실제 약속 충돌
//   가드이므로 우회하지 않고 빈 시간대에 배치한다.
function scenarios() {
  const wd = SAFE_DAYS();
  return [
    {key: 'A', who: WORKER, label: '수동 해지 + 미래 D', time: ['00:00', '00:50'],
      endOffset: 20, contract: 'pending', workDays: wd},
    {key: 'B', who: WORKER, label: '자동 해지 + 미래 D', time: ['02:00', '02:50'],
      endOffset: 20, contract: 'none', workDays: wd},
    {key: 'C', who: WORKER, label: 'D 없음 fail-closed', time: ['03:00', '03:50'],
      endOffset: 20, contract: 'none', workDays: wd},
    {key: 'D', who: WORKER, label: 'D 당일 — 조기 종료 금지', time: ['08:00', '08:50'],
      endOffset: 40, contract: 'none', workDays: wd},
    {key: 'E', who: WORKER, label: 'D+1 해지 효력', time: ['19:10', '20:00'],
      endOffset: 40, contract: 'pending', workDays: wd},
    {key: 'F', who: WORKER, label: 'D+1 이력 보존', time: ['04:00', '04:50'],
      endOffset: 40, contract: 'completed', workDays: wd, wage: true},
    {key: 'G', who: WORKER, label: '수동 퇴사 + 미래 D', time: ['01:00', '01:50'],
      endOffset: 25, contract: 'none', workDays: wd},
    {key: 'H', who: WORKER, label: 'D+1 퇴사 효력', time: ['20:10', '21:00'],
      endOffset: 40, contract: 'none', workDays: wd},
    {key: 'I1', who: WORKER, label: 'mutex 퇴사→해지', time: ['05:00', '05:50'],
      endOffset: 20, contract: 'none', workDays: wd},
    {key: 'I2', who: WORKER, label: 'mutex 해지→퇴사', time: ['06:00', '06:50'],
      endOffset: 20, contract: 'none', workDays: wd},
    {key: 'J', who: WORKER, label: '동시 race', time: ['07:00', '07:50'],
      endOffset: 20, contract: 'none', workDays: wd},
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

// ════════════════════════════════════════════════════════════════
// SETUP
// ════════════════════════════════════════════════════════════════
async function setup() {
  head(`SETUP  오늘=${kstDateKey(0)}(${TODAY_WD()})  근무일=${SAFE_DAYS().join('')}`);
  log(`  자정 scheduler 가 처리할 "어제" = ${kstDateKey(0)}(${TODAY_WD()})`);
  log('  → 이 요일을 근무일에서 빼 자동 NO_SHOW 를 원천 차단한다');

  const before = await inventory('BEFORE');
  const relBefore = await reliability('BEFORE');
  if (!EXECUTE) { log('\ndry-run 종료. --execute 로 생성.'); return; }
  if (st.AApp) throw new Error('이미 setup 됨 — --cleanup --execute 후 재실행');

  remember('R', kstDateKey(0));
  remember('setupAt', new Date().toISOString());
  remember('beforeInventory', before);
  remember('beforeReliability', relBefore);

  sub('§17 membership 사전 상태 (멤버십 부여 전)');
  for (const [k, uid] of [['WORKER', WORKER], ['OTHER', OTHER]]) {
    const m = await membershipOf(uid);
    remember(`memPre_${k}`, m);
    log(`  ${k} member=${m.memberExists} subAdminBiz=${JSON.stringify(m.subAdminBusinessIds)}`);
  }

  // ── fixture 생성 ──────────────────────────────────────────────
  for (const s of scenarios()) {
    sub(`${s.key}  ${s.label}  (${s.who.slice(0, 8)}… ${s.time[0]}-${s.time[1]})`);
    const wd = S.workDetail({workType: WORK_TYPE, start: s.time[0],
      end: s.time[1], required: 1, wage: 15000});
    const to = await callAs(ADMIN, 'callableCreateTO', {
      toData: {
        businessId: BIZ, businessName: BIZ_NAME, type: 'contract',
        title: `[${NS}] ${s.key}`, description: '.5-RUNTIME',
        workDetails: [wd], totalSlots: 0, totalRequired: 1,
        totalConfirmed: 0, totalPending: 0,
        rangeStart: kstMidnightMs(-2), rangeEnd: kstMidnightMs(s.endOffset),
        workDays: s.workDays, deadlineType: 'HOURS_BEFORE', hoursBeforeStart: 2,
        contractPeriodType: 'custom', postingDurationDays: 60,
        creatorUID: ADMIN, publishMode: 'immediate',
        isPublished: true, status: 'ACTIVE', isManualClosed: false,
      },
    });
    remember(`${s.key}To`, to.toId);
    const ap = await callAs(s.who, 'callableApplyToTO', {
      idCardConsentGiven: true, documentAccessConsentGiven: true,
      documentAccessConsentVersion: CONSENT_VERSION,
      toId: to.toId, slotId: null, businessId: BIZ, businessName: BIZ_NAME,
      toTitle: `[${NS}] ${s.key}`, selectedWorkType: WORK_TYPE,
      startTime: s.time[0], endTime: s.time[1],
      workDateMs: kstMidnightMs(-2),
      workEndDateMs: kstMidnightMs(s.endOffset),
      workDays: s.workDays, wage: 15000, wageType: 'hourly',
    });
    const appId = remember(`${s.key}App`, ap.applicationId || ap.id);
    await callAs(ADMIN, 'callableConfirmApplication',
        {applicationId: appId, businessId: BIZ});
    // [MAX_ACTIVE_TO_LIMIT] 공고는 지원 직후 닫는다.
    await callAs(ADMIN, 'callableCloseTOManually', {toId: to.toId}).catch(() => {});

    if (s.contract !== 'none') {
      const cid = remember(`${s.key}Contract`,
          db.collection('employment_contracts').doc().id);
      await callAs(ADMIN, 'callableFinalizeEmployerSignature', {
        contractId: cid, signatureBase64: S.signaturePng().toString('base64'),
        isNewUnsaved: true, contractData: await contractDataFor(appId),
      });
      if (s.contract === 'completed') {
        await callAs(s.who, 'callableFinalizeWorkerSignature', {
          contractId: cid,
          signatureBase64: S.signaturePng(200, 80).toString('base64'),
          pdfBase64: S.onePagePdf([`[${NS}] ${s.key}`]).toString('base64'),
        });
      }
      log(`  계약서 ${cid} (${s.contract})`);
    }

    // [TEMPORAL FIXTURE SETUP] 확정 시각을 기간 앞으로 — canonical writer 로는
    //   만들 수 없는 사전 상태다. 확정이 오늘이면 근무일 판정의 confirmedAt
    //   보정이 시작일을 오늘로 당겨 기간이 뒤틀린다.
    await db.collection('applications').doc(appId).update({
      confirmedAt: Ts(kstMidnightMs(-2) + 5 * 3600e3),
    });
    remember(`${s.key}SeatBefore`,
        ((await loadTo(to.toId)) || {}).totalConfirmed ?? null);
    log(`  app ${appId.slice(0, 44)}  seat=${st[`${s.key}SeatBefore`]}`);
  }

  // ── F: 과거 실근무 + 확정 급여 (이력 보존 대상) ────────────────
  sub('F  과거 근태 + 확정 급여 준비');
  {
    const appId = st.FApp;
    const app = await loadApp(appId);
    const dayMs = kstMidnightMs(-2);
    const attId = `${appId}_${kstDateKey(-2).replace(/-/g, '')}`;
    await db.collection('attendance').doc(attId).set({
      applicationId: appId, userId: app.uid, businessId: BIZ,
      businessName: BIZ_NAME, workDate: Ts(dayMs),
      yearMonth: kstDateKey(-2).slice(0, 7), workType: WORK_TYPE,
      status: 'present',
      checkIn: Ts(dayMs + 5 * 3600e3 + 40 * 60e3),
      checkOut: Ts(dayMs + 6 * 3600e3 + 40 * 60e3),
      wageStatus: 'confirmed', finalWage: 15000,
      paymentDueDate: Ts(kstMidnightMs(10)),
      isModified: false, modifyRequested: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    remember('FAttendance', attId);
    log(`  근태 ${attId.slice(-34)} present/confirmed 15000원`);
  }

  // ── §16 dual-role fixture: 확정 뒤에 관리자 멤버십 부여 ────────
  sub('§16 dual-role — 같은 사업장 worker + SubAdmin');
  {
    if (st.memPre_WORKER.memberExists) {
      throw new Error('dual-role 대상이 이미 멤버다 — fixture 소유를 판별할 수 없다');
    }
    await db.collection('businesses').doc(BIZ).collection('members')
        .doc(DUAL).set({
          uid: DUAL, businessId: BIZ, name: `[${NS}] dual-role`,
          phone: null, role: 'WORKER', permissions: DUAL_PERMS,
          invitationId: `${NS}_fixture`, invitedBy: ADMIN,
          addedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    await db.collection('users').doc(DUAL).update({
      subAdminBusinessIds: admin.firestore.FieldValue.arrayUnion(BIZ),
    });
    remember('dualMembershipCreated', true);
    log(`  ${DUAL.slice(0, 10)}… 에게 member doc + subAdminBusinessIds 부여`);
  }

  sub('§17 membership baseline (부여 후 — 이후 비교 기준)');
  for (const [k, uid] of [['WORKER', WORKER], ['OTHER', OTHER]]) {
    const m = await membershipOf(uid);
    remember(`mem_${k}`, m);
    log(`  ${k} member=${m.memberExists} perms=${JSON.stringify(m.permissions)}`);
    remember(`tok_${k}`, await tokensValidAfter(uid));
  }

  // ════════════════════════════════════════════════════════════
  // 즉시 실행 시나리오 (deployed callable)
  // ════════════════════════════════════════════════════════════
  sub('A  수동 해지 승인 — 미래 D');
  {
    const appId = st.AApp;
    const memBefore = await membershipOf(DUAL);
    const tokBefore = await tokensValidAfter(DUAL);
    await callAs(ADMIN, 'callableRequestTermination', {
      applicationId: appId, businessId: BIZ, reason: `[${NS}] A`,
    });
    const reqd = await loadApp(appId);
    remember('AD', iso(reqd.terminationEffectiveDate));
    log(`  요청됨 — D=${st.AD}`);
    // 근로자 본인이 동의한다 (canonical responder)
    await callAs(DUAL, 'callableApproveTermination', {applicationId: appId});

    const a = await loadApp(appId);
    const to = await loadTo(st.ATo);
    const c = st.AContract ? await loadContract(st.AContract) : null;
    const memAfter = await membershipOf(DUAL);
    const tokAfter = await tokensValidAfter(DUAL);
    remember('Aresult', {
      terminationStatus: a.terminationStatus,
      terminationEffectiveDate: iso(a.terminationEffectiveDate),
      actualResignDate: iso(a.actualResignDate),
      status: a.status,
      confirmedDecrementedAt: a.confirmedDecrementedAt ?? null,
      seat: to.totalConfirmed, contract: c ? c.status : null,
      memberExists: memAfter.memberExists,
      subAdminBusinessIds: memAfter.subAdminBusinessIds,
      tokensValidAfterChanged: tokBefore !== tokAfter,
    });
    check('A-01 terminationStatus=APPROVED', a.terminationStatus === 'APPROVED',
        String(a.terminationStatus));
    check('A-02 actualResignDate = D',
        iso(a.actualResignDate) === st.AD,
        `${iso(a.actualResignDate)} vs D=${st.AD}`);
    check('A-03 D 는 미래다', st.AD > kstDateKey(0), st.AD);
    check('A-04 status 가 아직 살아 있다',
        ['CONFIRMED', 'CONTRACT_PENDING'].includes(a.status), a.status);
    check('A-05 confirmedDecrementedAt = null', !a.confirmedDecrementedAt);
    check('A-06 seat 불변',
        to.totalConfirmed === st.ASeatBefore,
        `${st.ASeatBefore} → ${to.totalConfirmed}`);
    check('A-07 pending 계약서 불변', c && c.status === 'pending_worker',
        c ? c.status : '없음');
    check('A-08 멤버십 불변', sameMembership(memBefore, memAfter),
        JSON.stringify(memAfter));
    check('A-09 계정 세션 무효화 관측되지 않음', tokBefore === tokAfter,
        `${tokBefore} → ${tokAfter}`);
  }

  sub('C  D 없는 malformed — 승인 거부');
  {
    const appId = st.CApp;
    await db.collection('applications').doc(appId).update({
      terminationStatus: 'PENDING',
      terminationRequestedAt: admin.firestore.FieldValue.serverTimestamp(),
      terminationRequestedByUid: ADMIN,
      terminationReason: `[${NS}] C malformed`,
      terminationEffectiveDate: admin.firestore.FieldValue.delete(),
    });
    const bef = await loadApp(appId);
    const toBefore = await loadTo(st.CTo);
    let err = null;
    try {
      await callAs(WORKER, 'callableApproveTermination', {applicationId: appId});
    } catch (e) { err = e; }
    const aft = await loadApp(appId);
    const toAfter = await loadTo(st.CTo);
    const msg = err ? String(err.message || err) : '';
    remember('Cresult', {rejected: !!err, message: msg.slice(0, 160),
      terminationStatus: aft.terminationStatus,
      actualResignDate: iso(aft.actualResignDate), status: aft.status});
    check('C-01 서버가 거부했다', !!err, msg.slice(0, 120));
    check('C-02 failed-precondition 계열',
        /failed-precondition|계약해지 예정일/.test(msg), msg.slice(0, 120));
    check('C-03 terminationStatus 불변',
        aft.terminationStatus === bef.terminationStatus, String(aft.terminationStatus));
    check('C-04 actualResignDate 없음', !aft.actualResignDate);
    check('C-05 status 불변', aft.status === bef.status, aft.status);
    check('C-06 seat 불변', toAfter.totalConfirmed === toBefore.totalConfirmed);
  }

  sub('G  수동 퇴사 승인 — 미래 D');
  {
    const appId = st.GApp;
    const memBefore = await membershipOf(DUAL);
    const tokBefore = await tokensValidAfter(DUAL);
    const dIso = kstDateKey(15);
    await callAs(DUAL, 'callableRequestResignation', {
      applicationId: appId, businessId: BIZ,
      resignDateIso: new Date(kstMidnightMs(15)).toISOString(),
      reason: `[${NS}] G`,
    });
    await callAs(ADMIN, 'callableApproveResignation', {applicationId: appId});
    const a = await loadApp(appId);
    const to = await loadTo(st.GTo);
    const memAfter = await membershipOf(DUAL);
    const tokAfter = await tokensValidAfter(DUAL);
    remember('GD', dIso);
    remember('Gresult', {
      resignStatus: a.resignStatus, actualResignDate: iso(a.actualResignDate),
      status: a.status, seat: to.totalConfirmed,
      confirmedDecrementedAt: a.confirmedDecrementedAt ?? null,
      memberExists: memAfter.memberExists,
      subAdminBusinessIds: memAfter.subAdminBusinessIds,
      tokensValidAfterChanged: tokBefore !== tokAfter,
    });
    check('G-01 resignStatus=APPROVED', a.resignStatus === 'APPROVED',
        String(a.resignStatus));
    check('G-02 actualResignDate = D', iso(a.actualResignDate) === dIso,
        `${iso(a.actualResignDate)} vs ${dIso}`);
    check('G-03 status 가 아직 살아 있다',
        ['CONFIRMED', 'CONTRACT_PENDING'].includes(a.status), a.status);
    check('G-04 confirmedDecrementedAt = null', !a.confirmedDecrementedAt);
    check('G-05 seat 불변', to.totalConfirmed === st.GSeatBefore,
        `${st.GSeatBefore} → ${to.totalConfirmed}`);
    check('G-06 멤버십 불변', sameMembership(memBefore, memAfter),
        JSON.stringify(memAfter));
    check('G-07 계정 세션 무효화 관측되지 않음', tokBefore === tokAfter);
  }

  sub('I  순차 mutex');
  {
    // I1: 퇴사 먼저 → 해지 거부
    await callAs(WORKER, 'callableRequestResignation', {
      applicationId: st.I1App, businessId: BIZ,
      resignDateIso: new Date(kstMidnightMs(15)).toISOString(),
      reason: `[${NS}] I1`,
    });
    let e1 = null;
    try {
      await callAs(ADMIN, 'callableRequestTermination', {
        applicationId: st.I1App, businessId: BIZ, reason: `[${NS}] I1x`,
      });
    } catch (e) { e1 = e; }
    const a1 = await loadApp(st.I1App);
    check('I1-01 퇴사 요청 성공', a1.resignStatus === 'PENDING', String(a1.resignStatus));
    check('I1-02 해지 요청 거부', !!e1, e1 ? String(e1.message).slice(0, 110) : '거부 안 됨');
    check('I1-03 해지가 활성화되지 않았다', !a1.terminationStatus,
        String(a1.terminationStatus));

    // I2: 해지 먼저 → 퇴사 거부
    await callAs(ADMIN, 'callableRequestTermination', {
      applicationId: st.I2App, businessId: BIZ, reason: `[${NS}] I2`,
    });
    let e2 = null;
    try {
      await callAs(WORKER, 'callableRequestResignation', {
        applicationId: st.I2App, businessId: BIZ,
        resignDateIso: new Date(kstMidnightMs(15)).toISOString(),
        reason: `[${NS}] I2x`,
      });
    } catch (e) { e2 = e; }
    const a2 = await loadApp(st.I2App);
    check('I2-01 해지 요청 성공', a2.terminationStatus === 'PENDING',
        String(a2.terminationStatus));
    check('I2-02 퇴사 요청 거부', !!e2, e2 ? String(e2.message).slice(0, 110) : '거부 안 됨');
    check('I2-03 퇴사가 활성화되지 않았다', !a2.resignStatus, String(a2.resignStatus));
    remember('Iresult', {
      i1: {resign: a1.resignStatus, term: a1.terminationStatus ?? null,
        err: e1 ? String(e1.message).slice(0, 140) : null},
      i2: {term: a2.terminationStatus, resign: a2.resignStatus ?? null,
        err: e2 ? String(e2.message).slice(0, 140) : null},
    });
  }

  sub('J  동시 race');
  {
    const r = await Promise.allSettled([
      callAs(WORKER, 'callableRequestResignation', {
        applicationId: st.JApp, businessId: BIZ,
        resignDateIso: new Date(kstMidnightMs(15)).toISOString(),
        reason: `[${NS}] J-resign`,
      }),
      callAs(ADMIN, 'callableRequestTermination', {
        applicationId: st.JApp, businessId: BIZ, reason: `[${NS}] J-term`,
      }),
    ]);
    const okCount = r.filter((x) => x.status === 'fulfilled').length;
    const a = await loadApp(st.JApp);
    const ACTIVE = ['PENDING', 'APPROVED', 'AUTO_APPROVED'];
    const bothActive = ACTIVE.includes(a.resignStatus) &&
      ACTIVE.includes(a.terminationStatus);
    remember('Jresult', {
      settled: r.map((x) => x.status === 'fulfilled' ? 'OK' :
        String(x.reason && x.reason.message).slice(0, 120)),
      resignStatus: a.resignStatus ?? null,
      terminationStatus: a.terminationStatus ?? null,
      okCount,
    });
    log(`  결과 ${JSON.stringify(st.Jresult.settled)}`);
    check('J-01 두 종료 절차가 동시에 활성화되지 않았다', !bothActive,
        `resign=${a.resignStatus} termination=${a.terminationStatus}`);
    check('J-02 최대 1건만 성공', okCount <= 1, `${okCount}건 성공`);
  }

  // ── 자정 대상 fixture 사전 상태 ────────────────────────────────
  sub('자정 scheduler 대상 사전 상태 구성');
  {
    // B: D+3 자동승인 대상 — 요청 시각을 임계 너머로
    await callAs(ADMIN, 'callableRequestTermination', {
      applicationId: st.BApp, businessId: BIZ, reason: `[${NS}] B`,
    });
    const b = await loadApp(st.BApp);
    remember('BD', iso(b.terminationEffectiveDate));
    await db.collection('applications').doc(st.BApp).update({
      terminationRequestedAt: Ts(Date.now() - 4 * 864e5),
    });
    log(`  B 요청시각을 4일 전으로 — D=${st.BD} (응답 시한 경과 상태)`);

    // D: 오늘이 D — 전환되면 안 된다
    await db.collection('applications').doc(st.DApp).update({
      terminationStatus: 'APPROVED',
      terminationRequestedAt: Ts(Date.now() - 2 * 864e5),
      terminationRequestedByUid: ADMIN,
      terminationEffectiveDate: Ts(kstMidnightMs(0)),
      terminationRespondedAt: admin.firestore.FieldValue.serverTimestamp(),
      actualResignDate: Ts(kstMidnightMs(0)),
    });
    remember('DD', kstDateKey(0));
    log(`  D actualResignDate=${kstDateKey(0)} (오늘)`);

    // E: 어제가 D — 전환돼야 한다
    await db.collection('applications').doc(st.EApp).update({
      terminationStatus: 'APPROVED',
      terminationRequestedAt: Ts(Date.now() - 3 * 864e5),
      terminationRequestedByUid: ADMIN,
      terminationEffectiveDate: Ts(kstMidnightMs(-1)),
      terminationRespondedAt: admin.firestore.FieldValue.serverTimestamp(),
      actualResignDate: Ts(kstMidnightMs(-1)),
    });
    remember('ED', kstDateKey(-1));

    // F: 어제가 D (퇴사) + completed 계약 + 과거 근태/급여
    await db.collection('applications').doc(st.FApp).update({
      resignStatus: 'APPROVED',
      resignRequestedAt: Ts(Date.now() - 3 * 864e5),
      resignRequestDate: Ts(kstMidnightMs(-1)),
      resignApprovedAt: admin.firestore.FieldValue.serverTimestamp(),
      resignApprovedBy: ADMIN,
      actualResignDate: Ts(kstMidnightMs(-1)),
    });
    remember('FD', kstDateKey(-1));

    // H: 어제가 D (퇴사)
    await db.collection('applications').doc(st.HApp).update({
      resignStatus: 'APPROVED',
      resignRequestedAt: Ts(Date.now() - 3 * 864e5),
      resignRequestDate: Ts(kstMidnightMs(-1)),
      resignApprovedAt: admin.firestore.FieldValue.serverTimestamp(),
      resignApprovedBy: ADMIN,
      actualResignDate: Ts(kstMidnightMs(-1)),
    });
    remember('HD', kstDateKey(-1));
    log(`  E/F/H actualResignDate=${kstDateKey(-1)} (어제)`);

    for (const k of ['B', 'D', 'E', 'F', 'H']) {
      const to = await loadTo(st[`${k}To`]);
      remember(`${k}SeatPre`, to.totalConfirmed);
    }
    const fc = await loadContract(st.FContract);
    remember('FContractPre', {status: fc.status,
      hasPdf: !!fc.pdfUrl, hasWorkerSig: !!fc.workerSignatureUrl});
    const fa = (await db.collection('attendance').doc(st.FAttendance).get()).data();
    remember('FAttPre', {status: fa.status, wageStatus: fa.wageStatus,
      finalWage: fa.finalWage});
    const ec = await loadContract(st.EContract);
    remember('EContractPre', {status: ec.status});
  }

  sub('§51 apply-side 관측 — 미래 D 승인자의 지원 가능성');
  {
    const apps = await callAs(DUAL, 'callableGetMyApplications', {limit: 200});
    const list = (apps.applications || []);
    const a = list.find((x) => x.id === st.AApp);
    remember('applySide', {
      myApplicationsVisible: !!a,
      statusInList: a ? a.status : null,
      total: list.length,
    });
    check('S-01 승인된 미래 D 근무가 내 지원 목록에 그대로 있다', !!a,
        a ? `status=${a.status}` : '목록에 없음');
  }

  sub('알림 inventory (§53 — 고치지 않고 기록만)');
  {
    const types = {};
    for (const uid of [DUAL, WORKER, OTHER, ADMIN]) {
      const ns = await db.collection('users').doc(uid)
          .collection('notifications')
          .orderBy('createdAt', 'desc').limit(40).get();
      for (const d of ns.docs) {
        const dt = d.data();
        const aid = (dt.data || {}).applicationId;
        if (!aid) continue;
        const mine = Object.keys(st).filter((k) => k.endsWith('App'))
            .some((k) => st[k] === aid);
        if (!mine) continue;
        types[dt.type] = (types[dt.type] || 0) + 1;
      }
    }
    remember('notifTypes', types);
    log(`  ${JSON.stringify(types)}`);
  }

  await inventory('AFTER-SETUP');
  await reliability('AFTER-SETUP');
  log('\n자정 창(다음날 00:00~00:10 KST) 이후 --collect 로 나머지를 확인한다.');
}

// ════════════════════════════════════════════════════════════════
// COLLECT — 자정 scheduler 이후
// ════════════════════════════════════════════════════════════════
async function collect() {
  head(`COLLECT  setup R=${st.R}  지금=${kstDateKey(0)} ` +
    `${new Date(Date.now() + KST).toISOString().slice(11, 19)} KST`);
  if (!st.AApp) throw new Error('setup 기록이 없다.');
  if (kstDateKey(0) === st.R) {
    log('\n⚠ 아직 setup 과 같은 KST 날짜다 — 자정 창이 지나지 않았다.');
  }

  // [§26] 기대값은 manifest 의 D 로만 판정한다. 실행 시점의 오늘로
  //   D/D+1 을 다시 계산하지 않는다 — 그러면 수집이 하루 밀릴 때마다
  //   기대가 함께 밀려 아무것도 증명하지 못한다.
  sub(`§26 date anchor — scheduler business date = ${st.schedulerBusinessDate}`);
  {
    const sched = st.schedulerBusinessDate;
    const prev = (d) => {
      const t = Date.parse(`${d}T00:00:00Z`) - 864e5;
      return new Date(t).toISOString().slice(0, 10);
    };
    check('X-01 실제 수집일이 scheduler 창 이후다',
        kstDateKey(0) >= sched, `오늘=${kstDateKey(0)} sched=${sched}`);
    check('X-02 D 시나리오는 today == D 로 앵커됐다',
        st.DD === sched, `D=${st.DD} sched=${sched}`);
    for (const k of ['E', 'F', 'H']) {
      check(`X-03${k} ${k} 시나리오는 today == D+1 로 앵커됐다`,
          st[`${k}D`] === prev(sched), `D=${st[`${k}D`]} sched-1=${prev(sched)}`);
    }
    check('X-04 B 는 미래 D 그대로다', st.BD > sched, `D=${st.BD}`);
  }

  sub('B  자동 해지 승인 (masterScheduler)');
  {
    const a = await loadApp(st.BApp);
    const to = await loadTo(st.BTo);
    const mem = await membershipOf(WORKER);
    check('B-01 terminationStatus=AUTO_APPROVED',
        a.terminationStatus === 'AUTO_APPROVED', String(a.terminationStatus));
    check('B-02 terminationEffectiveDate 불변 — 날짜를 발명하지 않았다',
        iso(a.terminationEffectiveDate) === st.BD,
        `${iso(a.terminationEffectiveDate)} vs ${st.BD}`);
    check('B-03 actualResignDate = D', iso(a.actualResignDate) === st.BD,
        `${iso(a.actualResignDate)} vs ${st.BD}`);
    check('B-04 status 가 아직 살아 있다',
        ['CONFIRMED', 'CONTRACT_PENDING'].includes(a.status), a.status);
    check('B-05 confirmedDecrementedAt = null', !a.confirmedDecrementedAt);
    check('B-06 seat 불변', to.totalConfirmed === st.BSeatPre,
        `${st.BSeatPre} → ${to.totalConfirmed}`);
    check('B-07 멤버십 불변 (manual A 와 동일 결과)',
        sameMembership(mem, st.mem_WORKER), JSON.stringify(mem));
    check('B-08 manual/auto actualResignDate parity — 둘 다 요청의 D',
        !!st.Aresult && st.Aresult.actualResignDate === st.AD &&
        iso(a.actualResignDate) === st.BD);
  }

  sub('D  오늘이 D — 조기 종료 금지');
  {
    const a = await loadApp(st.DApp);
    const to = await loadTo(st.DTo);
    check('D-01 status 가 그대로 살아 있다',
        ['CONFIRMED', 'CONTRACT_PENDING'].includes(a.status), a.status);
    check('D-02 confirmedDecrementedAt = null', !a.confirmedDecrementedAt,
        String(a.confirmedDecrementedAt));
    check('D-03 seat 불변', to.totalConfirmed === st.DSeatPre,
        `${st.DSeatPre} → ${to.totalConfirmed}`);
    check('D-04 actualResignDate 불변', iso(a.actualResignDate) === st.DD);
  }

  sub('E  D+1 해지 효력 전환');
  {
    const a = await loadApp(st.EApp);
    const to = await loadTo(st.ETo);
    const c = await loadContract(st.EContract);
    const mem = await membershipOf(OTHER);
    check('E-01 status = CANCELED', a.status === 'CANCELED', a.status);
    check('E-02 cancelReason 가 해지를 가리킨다',
        a.cancelReason === 'TERMINATION_EFFECTIVE', String(a.cancelReason));
    check('E-03 confirmedDecrementedAt 기록됨', !!a.confirmedDecrementedAt);
    check('E-04 seat 정확히 1회 반납',
        to.totalConfirmed === st.ESeatPre - 1,
        `${st.ESeatPre} → ${to.totalConfirmed}`);
    check('E-05 pending 계약서 void',
        c.status === 'voided', `${st.EContractPre.status} → ${c.status}`);
    check('E-06 멤버십 불변 — 고용 종료는 멤버십 사건이 아니다',
        sameMembership(mem, st.mem_OTHER), JSON.stringify(mem));
    remember('EseatAfter', to.totalConfirmed);
    remember('EdecAt', a.confirmedDecrementedAt ?
      a.confirmedDecrementedAt.toMillis() : null);
  }

  sub('F  D+1 이후 이력 보존');
  {
    const a = await loadApp(st.FApp);
    const c = await loadContract(st.FContract);
    const att = (await db.collection('attendance').doc(st.FAttendance).get()).data();
    check('F-01 퇴사도 전환된다', a.status === 'CANCELED', a.status);
    check('F-02 cancelReason 가 퇴사를 가리킨다',
        a.cancelReason === 'RESIGNATION_EFFECTIVE', String(a.cancelReason));
    check('F-03 completed 계약서는 그대로다',
        c.status === 'completed', `${st.FContractPre.status} → ${c.status}`);
    check('F-04 서명·PDF 보존',
        !!c.workerSignatureUrl === st.FContractPre.hasWorkerSig &&
        !!c.pdfUrl === st.FContractPre.hasPdf);
    check('F-05 과거 근태 보존', !!att && att.status === st.FAttPre.status,
        att ? att.status : '없음');
    check('F-06 확정 급여 보존',
        att && att.wageStatus === 'confirmed' &&
        att.finalWage === st.FAttPre.finalWage,
        att ? `${att.wageStatus}/${att.finalWage}` : '없음');
  }

  sub('H  D+1 퇴사 효력 전환');
  {
    const a = await loadApp(st.HApp);
    const to = await loadTo(st.HTo);
    const mem = await membershipOf(OTHER);
    check('H-01 status = CANCELED', a.status === 'CANCELED', a.status);
    check('H-02 seat 정확히 1회 반납',
        to.totalConfirmed === st.HSeatPre - 1,
        `${st.HSeatPre} → ${to.totalConfirmed}`);
    check('H-03 confirmedDecrementedAt 기록됨', !!a.confirmedDecrementedAt);
    check('H-04 멤버십 불변', sameMembership(mem, st.mem_OTHER));
  }

  sub('A / G  승인 상태가 자정을 넘겨도 유지되는가');
  {
    const a = await loadApp(st.AApp);
    const g = await loadApp(st.GApp);
    check('AG-01 A 미래 D — 여전히 active',
        ['CONFIRMED', 'CONTRACT_PENDING'].includes(a.status), a.status);
    check('AG-02 A seat 불변',
        (await loadTo(st.ATo)).totalConfirmed === st.ASeatBefore);
    check('AG-03 G 미래 D — 여전히 active',
        ['CONFIRMED', 'CONTRACT_PENDING'].includes(g.status), g.status);
    check('AG-04 A/G 모두 confirmedDecrementedAt = null',
        !a.confirmedDecrementedAt && !g.confirmedDecrementedAt);
  }

  sub('§58 permission parity — 전 경로 실측');
  {
    const rows = {};
    for (const [k, uid] of [['WORKER', WORKER], ['OTHER', OTHER]]) {
      const m = await membershipOf(uid);
      rows[k] = m;
      check(`P-${k} 멤버십이 setup 시점과 동일`,
          sameMembership(m, st[`mem_${k}`]), JSON.stringify(m));
      const tok = await tokensValidAfter(uid);
      check(`P-${k} 계정 세션 무효화 관측되지 않음`, tok === st[`tok_${k}`],
          `${st[`tok_${k}`]} → ${tok}`);
    }
    remember('permAfter', rows);
  }

  sub('§54 회귀 — 예상 밖 NO_SHOW / 신뢰도');
  {
    const appIds = Object.keys(st).filter((k) => k.endsWith('App')).map((k) => st[k]);
    let ns = 0; let extra = 0;
    for (const id of appIds) {
      const s = await db.collection('attendance')
          .where('applicationId', '==', id).get();
      for (const d of s.docs) {
        if (d.id === st.FAttendance) continue;
        extra++;
        if (d.data().status === 'NO_SHOW') ns++;
        log(`    예상 밖 근태 ${d.id.slice(-30)} status=${d.data().status}`);
      }
    }
    check('R-01 fixture 발 예상 밖 근태 0건', extra === 0, `${extra}건`);
    check('R-02 fixture 발 NO_SHOW 0건', ns === 0, `${ns}건`);
    const rel = await reliability('AFTER ');
    check('R-03 신뢰도 baseline 동일',
        JSON.stringify(rel) === JSON.stringify(st.beforeReliability),
        JSON.stringify(rel));
  }

  const failed = results.filter((r) => !r.ok);
  log(`\n  ${results.length - failed.length}/${results.length} PASS`);
  failed.forEach((r) => log(`    · ${r.label}`));
  remember('collectAt', new Date().toISOString());
}

// ════════════════════════════════════════════════════════════════
// CLEANUP — manifest exact id 만
// ════════════════════════════════════════════════════════════════
async function cleanup() {
  head('CLEANUP — manifest exact id 만');
  const before = await inventory('BEFORE');
  const relBefore = await reliability('BEFORE');

  const appIds = Object.keys(st).filter((k) => k.endsWith('App'))
      .map((k) => st[k]).filter(Boolean);
  const toIds = Object.keys(st).filter((k) => k.endsWith('To'))
      .map((k) => st[k]).filter(Boolean);
  const contractIds = Object.keys(st).filter((k) => k.endsWith('Contract'))
      .map((k) => st[k]).filter(Boolean);
  const attIds = [st.FAttendance].filter(Boolean);

  for (const uid of [DUAL, WORKER, OTHER, ADMIN]) {
    const col = db.collection('users').doc(uid).collection('notifications');
    const seen = new Map();
    for (const aid of appIds) {
      (await col.where('data.applicationId', '==', aid).get())
          .docs.forEach((d) => seen.set(d.id, d.ref));
    }
    if (seen.size) log(`  알림 ${seen.size}건 (${uid.slice(0, 10)}…)`);
    if (EXECUTE) for (const r of seen.values()) await r.delete();
  }
  for (const id of attIds) {
    const ref = db.collection('attendance').doc(id);
    if (!(await ref.get()).exists) continue;
    log(`  근태 ${id.slice(-34)}`);
    if (EXECUTE) await ref.delete();
  }
  for (const aid of appIds) {
    const s = await db.collection('attendance')
        .where('applicationId', '==', aid).get();
    for (const d of s.docs) {
      log(`  근태(추가) ${d.id.slice(-34)}`);
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
  for (const aid of appIds) {
    const ref = db.collection('applications').doc(aid);
    if (!(await ref.get()).exists) continue;
    log(`  지원서 ${aid.slice(0, 44)}`);
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

  // [§62] dual-role 멤버십은 이번 runtime 이 만든 것이다 — 여기서 제거한다.
  //   단, 제품의 exit writer 가 지우는지 보려고 남겨 두지 않는다:
  //   runtime assertion 이 끝난 뒤 fixture cleanup 으로만 제거한다.
  sub('§62 fixture 멤버십 제거');
  {
    const m = await membershipOf(DUAL);
    check('M-01 종료 전 과정을 거치고도 멤버십이 살아 있었다',
        m.memberExists && m.subAdminBusinessIds.includes(BIZ),
        JSON.stringify(m));
    log(`  member doc + subAdminBusinessIds 제거 (${DUAL.slice(0, 10)}…)`);
    if (EXECUTE && st.dualMembershipCreated) {
      await db.collection('businesses').doc(BIZ).collection('members')
          .doc(DUAL).delete();
      await db.collection('users').doc(DUAL).update({
        subAdminBusinessIds: admin.firestore.FieldValue.arrayRemove(BIZ),
      });
    }
  }
  if (EXECUTE) {
    for (const [k, uid] of [['WORKER', WORKER], ['OTHER', OTHER]]) {
      const m = await membershipOf(uid);
      check(`M-${k} 멤버십이 fixture 이전 상태로 복귀`,
          sameMembership(m, st[`memPre_${k}`]), JSON.stringify(m));
    }
  }

  if (!EXECUTE) { log('\ndry-run — 아무것도 지우지 않았습니다.'); return; }
  const after = await inventory('AFTER ');
  const relAfter = await reliability('AFTER ');
  log(`  delta ${JSON.stringify({
    applications: after.applications - before.applications,
    employment_contracts:
      after.employment_contracts - before.employment_contracts,
    attendance: after.attendance - before.attendance,
  })}`);
  check('신뢰도 변화 없음',
      JSON.stringify(relAfter) === JSON.stringify(relBefore),
      JSON.stringify(relAfter));
  check('baseline inventory 복귀',
      JSON.stringify(after) === JSON.stringify(st.beforeInventory),
      `${JSON.stringify(after)} vs ${JSON.stringify(st.beforeInventory)}`);
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
  console.error('\n실패:', e && e.message ? e.message : e);
  process.exit(1);
});
