#!/usr/bin/env node
/**
 * [PRELAUNCH-LONGTERM-LIFECYCLE-INTEGRITY.2]
 * 장기 계약 생성 → 사업주 서명 → 근로자 서명 → completed — DEV 실제 실행.
 *
 * DEV employment_contracts 17건은 **전부 단기**였다(isLongTerm=false, 기간은
 * slots[].workDate 한 줄). 그래서 장기 계약의 snapshot·서명 lifecycle 은
 * 지금까지 코드로만 확인됐다. 이 스크립트가 그 공백 하나를 닫는다.
 *
 * 쓰는 것: LTCR 네임스페이스의 TO 1건 · Application 1건 · Contract 1건
 * 안 건드리는 것: R7_FIX_* fixture 전부, 기존 지원서·근태·급여
 *
 *   node scripts/lt-contract-dual-signature-runtime.js --project alfit-89567
 *   node scripts/lt-contract-dual-signature-runtime.js --project alfit-89567 --execute
 *   node scripts/lt-contract-dual-signature-runtime.js --project alfit-89567 --cleanup
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
const {admin, db, callAs, kstMidnightMs, kstDateKey} = require('./r7-fixture-lib');
const S = require('./r7-fixture-scenarios');

// ── DEV 고정 ────────────────────────────────────────────────────────
const BIZ = 'fLmSOHVKUwmBHcbwQE0I';
const ADMIN = 'BErRdiWP1xbgyoTovxwAPNEsuD72';
// DEV 에서 이 사업장 공고에 지원할 수 있는 계정은 하나뿐이다.
//   kN2g… 는 이 사업장의 SubAdmin 이라 서버가 지원을 막는다
//   ("관리자로 등록된 사업장의 공고에는 지원할 수 없습니다" — 실측).
// 그래서 근로자는 tJ8iz… 를 쓰되, **새 지원서**를 따로 만든다.
// R7_FIX_LT_WORKER 의 지원서·근태·급여는 건드리지 않는다(§37 로 검증).
const WORKER = 'tJ8izfP2nNYN79aPTLb6YARiPqC3';
// 계약 당사자가 아닌 제3자. 이 사업장의 SubAdmin 이므로
//   · 근로자 서명 negative(§23): 계약의 workerId 가 아니다
//   · 사업주 서명 negative(§24): canManageContract 보유 여부로 판정이 갈린다
const OTHER_PERSON = 'kN2gNpEhLLVjQD7KLGSnNFJHd2v2';
const WORK_TYPE = '사무업무';
const CONSENT_VERSION = '2026-09-18-v3';
const NS = 'LTCR'; // long-term contract runtime
// r7-fixture-lib 의 initializeApp 은 storageBucket 을 주지 않는다. CF 런타임과
// 달리 스크립트에서는 기본 버킷이 해상도되지 않으므로 이름을 직접 준다.
// (PRE0 cleanup 도 같은 이유로 계약 Storage 를 한 번도 지우지 못하고 있었다.)
const BUCKET = 'alfit-89567.firebasestorage.app';
const STATE = path.join(__dirname, `.lt-contract-runtime-state.json`);

// 이 근로자에게 이미 있는 확정 근무와 겹치지 않는 창.
//   06:00~08:00 장기(R7FIX) · 09:00~19:00 대 단기 다수 · 23:00 대 둘.
//   서버는 시간이 겹치는 확정 근무가 있으면 지원을 거절한다.
const START_TIME = '03:00';
const END_TIME = '05:00';
const PROMISED_WAGE = 13500;   // 지원 시점의 약속
const POSTING_WAGE_AFTER = 19000; // 확정 뒤 공고를 올린 값 — 계약은 이걸 쓰면 안 된다
const WORK_DAYS = ['월', '화', '수', '목', '금', '토', '일'];
const FROM_OFFSET = -3;
const TO_OFFSET = 27;

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

const KST = 9 * 3600e3;
const iso = (ts) => ts ?
  new Date(ts.toMillis() + KST).toISOString().slice(0, 10) : null;
const stamp = (ts) => ts ?
  new Date(ts.toMillis() + KST).toISOString().replace('T', ' ').slice(0, 19) : '-';

async function inventory(label) {
  const [ap, at, ec, tos, nt] = await Promise.all([
    db.collection('applications').get(),
    db.collection('attendance').get(),
    db.collection('employment_contracts').get(),
    db.collection('tos').get(),
    db.collection('users').doc(WORKER).collection('notifications').get(),
  ]);
  const inv = {
    applications: ap.size, attendance: at.size, contracts: ec.size,
    tos: tos.size, workerNotifications: nt.size,
  };
  log(`${label}  ${JSON.stringify(inv)}`);
  return inv;
}

/** R7_FIX_LT_WORKER 가 이 runtime 때문에 변하지 않았는지. */
async function pre0Snapshot() {
  const m = require('./r7-fixture-manifest-dev.json');
  const e = m.scenarios.R7_FIX_LT_WORKER.entities;
  const app = (await db.collection('applications').doc(e.applicationId).get()).data();
  const wages = {};
  for (const [k, id] of Object.entries(e.payroll)) {
    const s = await db.collection('attendance').doc(id).get();
    wages[k] = s.exists ? s.data().wageStatus : 'MISSING';
  }
  const todayAtt = await db.collection('attendance')
      .doc(`${e.applicationId}_${kstDateKey(0).replace(/-/g, '')}`).get();
  return {
    status: app.status,
    confirmedAt: app.confirmedAt.toMillis(),
    workEndDate: app.workEndDate.toMillis(),
    workDays: (app.workDays || []).join(','),
    todayAttendanceExists: todayAtt.exists,
    wages,
  };
}

// ══════════════════════════════════════════════════════════════════
// 계약 payload — 클라이언트 contract_service._buildSnapshot 과 같은 식.
//
//   PRE0 의 contractData 헬퍼는 단기 전용이다(contractEnd 가 null 고정).
//   장기를 그것으로 만들면 기간이 사라지는데, 그건 스크립트 잘못이지
//   제품 동작이 아니다. 그래서 여기서 클라이언트 규칙을 그대로 옮긴다.
//
//     contractStart = desiredStartDate ?? workDate
//     contractEnd   = workEndDate                  (장기이고 있을 때만)
//     workDays      = application.workDays
//     wage/wageType = **지원서의 약속** (_withPromisedWage)
// ══════════════════════════════════════════════════════════════════
async function buildLongTermContractData(applicationId) {
  const app = (await db.collection('applications').doc(applicationId).get()).data();
  const biz = (await db.collection('businesses').doc(BIZ).get()).data();
  const worker = (await db.collection('users').doc(WORKER).get()).data();
  const bn = String(biz.businessNumber || '').replace(/\D/g, '');
  const fmt = (ts) => ts ? iso(ts) : null;

  if (!app.wage || app.wage <= 0) {
    throw new Error('지원 시점 임금이 없어 계약서를 만들 수 없습니다.');
  }
  return {
    applicationId,
    businessId: BIZ,
    businessName: biz.name || '',
    workerId: WORKER,
    isLongTerm: true,
    toId: app.toId || '',
    // 장기에는 wdId 가 없다 — composite identity 가 canonical 이다.
    workDetailId: app.wdId || app.workDetailId ||
      `${app.selectedWorkType}_${app.startTime}_${app.endTime}`,
    slots: [], // 장기에는 날짜별 슬롯이 없다
    applicationIds: [applicationId],
    snapshot: {
      businessName: biz.name || '',
      businessNumber: bn.length === 10 ?
        `${bn.slice(0, 3)}-${bn.slice(3, 5)}-${bn.slice(5)}` : bn,
      businessAddress: [biz.address, biz.detailAddress].filter(Boolean).join(' '),
      businessPhone: biz.phone || null,
      ownerName: biz.ownerName || '',
      workerName: worker.name || '',
      workerBirthDate: worker.birthDate ?
        new Date(worker.birthDate.toMillis() + KST).toISOString().slice(0, 10) : null,
      workerPhone: worker.authPhone || worker.phone || null,
      workerAddress: [worker.address, worker.detailAddress]
          .filter(Boolean).join(' ').trim() || null,
      workType: app.selectedWorkType,
      workPlace: biz.address || '',
      isLongTerm: true,
      contractStart: fmt(app.desiredStartDate || app.workDate),
      contractEnd: fmt(app.workEndDate),
      workDays: app.workDays || [],
      startTime: app.startTime,
      endTime: app.endTime,
      breakMinutes: app.breakMinutes || 0,
      wage: app.wage,              // ← 약속. 공고의 현재 모집 임금이 아니다.
      wageType: app.wageType,
      wagePaymentDay: biz.wagePaymentDay ?? null,
      paymentMethod: '계좌이체',
      baseHourlyWage: app.baseHourlyWage ?? null,
      payScheduleType: app.payScheduleType || 'same_day',
      payScheduleDay: app.payScheduleDay ?? null,
      payScheduleTime: app.payScheduleTime ?? null,
      taxDeductionType: app.taxDeductionType || 'none',
    },
    articles: [],
    templateId: null,
  };
}

// ══════════════════════════════════════════════════════════════════
// cleanup — 정확히 LTCR 엔티티만
// ══════════════════════════════════════════════════════════════════
async function cleanup() {
  const st = readState();
  if (!st.toId && !st.contractId) { log('정리할 것이 없습니다.'); return; }
  head('cleanup — state 에 적힌 id 만');
  const before = await inventory('BEFORE');

  if (st.contractId) {
    const ref = db.collection('employment_contracts').doc(st.contractId);
    if ((await ref.get()).exists) {
      log(`   계약서 ${st.contractId}`);
      if (EXECUTE) {
        await ref.delete();
        try {
          await admin.storage().bucket(BUCKET)
              .deleteFiles({prefix: `contracts/${st.contractId}/`});
        } catch (_) { /* 없으면 그만 */ }
      }
    }
  }
  if (st.applicationId) {
    const ref = db.collection('applications').doc(st.applicationId);
    if ((await ref.get()).exists) {
      log(`   지원서 ${st.applicationId}`);
      if (EXECUTE) await ref.delete();
    }
  }
  if (st.toId) {
    // 남의 지원서가 붙었으면 공고를 남긴다 — 고아를 만들지 않는다.
    const others = await db.collection('applications')
        .where('toId', '==', st.toId).get();
    const foreign = others.docs.filter((d) => d.id !== st.applicationId);
    if (foreign.length > 0) {
      log(`   공고 ${st.toId} — 남의 지원서 ${foreign.length}건이 붙어 있어 남긴다`);
    } else {
      log(`   공고 ${st.toId}`);
      if (EXECUTE) await db.collection('tos').doc(st.toId).delete();
    }
  }
  // 이 runtime 이 만든 알림만.
  //   contractId 로 식별되는 것(서명 요청)과 applicationId 로 식별되는 것
  //   (지원 확정·서명 완료)이 따로 있다. 한쪽만 지우면 남는다 — 실제로
  //   applicationConfirmed 한 건이 남았다.
  for (const who of [WORKER, ADMIN, OTHER_PERSON]) {
    const col = db.collection('users').doc(who).collection('notifications');
    const seen = new Map();
    for (const q of [
      col.where('data.contractId', '==', st.contractId || '_'),
      col.where('data.applicationId', '==', st.applicationId || '_'),
    ]) {
      const s = await q.get();
      s.docs.forEach((d) => seen.set(d.id, d.ref));
    }
    if (seen.size === 0) continue;
    log(`   알림 ${seen.size}건 (${who.slice(0, 10)}…)`);
    if (EXECUTE) for (const ref of seen.values()) await ref.delete();
  }

  if (!EXECUTE) { log('\ndry-run — 아무것도 지우지 않았습니다.'); return; }
  const after = await inventory('AFTER ');
  log(JSON.stringify({
    applications: after.applications - before.applications,
    contracts: after.contracts - before.contracts,
    tos: after.tos - before.tos,
    attendance: after.attendance - before.attendance,
  }));
  fs.unlinkSync(STATE);
}

// ══════════════════════════════════════════════════════════════════
async function main() {
  if (CLEANUP) return cleanup();

  log(`\nDEV=${projectId}  ${EXECUTE ? '' : '(dry-run — --execute 로 실제 실행)'}`);
  log(`근로자=${WORKER.slice(0, 10)}…  창=${START_TIME}~${END_TIME}  약속임금=${PROMISED_WAGE}`);

  head('§2 pre-runtime inventory · PRE0 보존 기준선');
  const invBefore = await inventory('BEFORE');
  const pre0Before = await pre0Snapshot();
  log(`R7_FIX_LT_WORKER  ${JSON.stringify(pre0Before)}`);
  if (!EXECUTE) { log('\ndry-run 종료.'); return; }

  const st = readState();

  // ── 재실행 보호 ─────────────────────────────────────────────────
  //   체인이 이미 끝까지 간 상태에서 다시 돌리면 "사업주 서명만으로
  //   CONFIRMED 가 되지 않는다" 같은 **중간 단계** 단언이 전부 실패한다.
  //   그건 제품이 틀린 것이 아니라 시점이 지난 것이다. 지나간 단계를
  //   실패로 적으면 보고서가 거짓말을 한다.
  if (st.contractId) {
    const done = await db.collection('employment_contracts').doc(st.contractId).get();
    if (done.exists && done.data().status === 'completed') {
      head('이미 완료된 체인 — 사후 상태만 다시 본다');
      log('   lifecycle 전이(T2·T3·§14·§23)는 그때 한 번만 관측할 수 있다.');
      log('   처음부터 다시 보려면 --cleanup --execute 후 재실행.');
      await postStateChecks(st);
      await summarize(invBefore, pre0Before);
      return;
    }
  }

  // ── T0 장기 공고 ────────────────────────────────────────────────
  head('T0  장기 공고 생성 (callableCreateTO)');
  if (!st.toId) {
    const wd = S.workDetail({
      workType: WORK_TYPE, start: START_TIME, end: END_TIME,
      required: 1, wage: PROMISED_WAGE,
    });
    const created = await callAs(ADMIN, 'callableCreateTO', {
      toData: {
        businessId: BIZ, businessName: '위워커', type: 'contract',
        title: `[${NS}] 장기 계약 런타임`,
        description: 'LONGTERM-LIFECYCLE-INTEGRITY.2 — 계약 생성/양측 서명 검증',
        workDetails: [wd],
        totalSlots: 0, totalRequired: 1, totalConfirmed: 0, totalPending: 0,
        rangeStart: kstMidnightMs(FROM_OFFSET),
        rangeEnd: kstMidnightMs(TO_OFFSET),
        workDays: WORK_DAYS,
        deadlineType: 'HOURS_BEFORE', hoursBeforeStart: 2,
        contractPeriodType: 'custom', postingDurationDays: 30,
        creatorUID: ADMIN, publishMode: 'immediate',
        isPublished: true, status: 'ACTIVE', isManualClosed: false,
      },
    });
    st.toId = created.toId;
    writeState(st);
  }
  log(`   toId=${st.toId}  range ${kstDateKey(FROM_OFFSET)} ~ ${kstDateKey(TO_OFFSET)}`);

  // ── T1 지원 ─────────────────────────────────────────────────────
  head('T1  근로자 지원 (callableApplyToTO)');
  if (!st.applicationId) {
    const r = await callAs(WORKER, 'callableApplyToTO', {
      idCardConsentGiven: true,
      documentAccessConsentGiven: true,
      documentAccessConsentVersion: CONSENT_VERSION,
      toId: st.toId, slotId: null,
      businessId: BIZ, businessName: '위워커',
      toTitle: `[${NS}] 장기 계약 런타임`,
      selectedWorkType: WORK_TYPE,
      startTime: START_TIME, endTime: END_TIME,
      workDateMs: kstMidnightMs(FROM_OFFSET),
      workEndDateMs: kstMidnightMs(TO_OFFSET),
      workDays: WORK_DAYS,
      wage: PROMISED_WAGE, wageType: 'hourly',
    });
    st.applicationId = r.applicationId || r.id;
    writeState(st);
  }
  log(`   applicationId=${st.applicationId}`);

  // ── T2 확정 → CONTRACT_PENDING ─────────────────────────────────
  head('T2  관리자 확정 (callableConfirmApplication)');
  let app = (await db.collection('applications').doc(st.applicationId).get()).data();
  if (app.status === 'PENDING') {
    await callAs(ADMIN, 'callableConfirmApplication',
        {applicationId: st.applicationId, businessId: BIZ});
    app = (await db.collection('applications').doc(st.applicationId).get()).data();
  }
  check('T2 확정 후 status = CONTRACT_PENDING', app.status === 'CONTRACT_PENDING',
      `status=${app.status}`);

  head('§3 canonical Application');
  const canonical = {
    applicationId: st.applicationId, toId: app.toId, businessId: app.businessId,
    uid: app.uid, type: app.type, status: app.status,
    workDate: iso(app.workDate), workEndDate: iso(app.workEndDate),
    desiredStartDate: app.desiredStartDate ? iso(app.desiredStartDate) : null,
    workDays: (app.workDays || []).join(','),
    selectedWorkType: app.selectedWorkType,
    startTime: app.startTime, endTime: app.endTime,
    breakMinutes: app.breakMinutes ?? null,
    wage: app.wage, wageType: app.wageType,
    taxDeductionType: app.taxDeductionType ?? null,
    payScheduleType: app.payScheduleType ?? null,
    workDetailId: app.workDetailId ?? null, wdId: app.wdId ?? null,
    compositeIdentity: `${app.toId} × (${app.selectedWorkType}_${app.startTime}_${app.endTime})`,
  };
  Object.entries(canonical).forEach(([k, v]) => log(`   ${k.padEnd(18)} ${v}`));
  check('§6 장기에는 wdId 가 없다 — composite identity 가 canonical',
      !app.wdId, `wdId=${app.wdId ?? 'null'}`);

  // ── T2.5 공고 임금 인상 — 약속을 덮어쓰면 안 된다 ────────────────
  head('§11  확정 뒤 공고 임금 인상 (callableUpdateTO)');
  const toNow = (await db.collection('tos').doc(st.toId).get()).data();
  if ((toNow.workDetails[0].wage) !== POSTING_WAGE_AFTER) {
    await callAs(ADMIN, 'callableUpdateTO', {
      toId: st.toId,
      updates: {
        workDetails: [{...toNow.workDetails[0], wage: POSTING_WAGE_AFTER}],
      },
      expectedEditRevision: toNow.editRevision ?? 0,
    });
  }
  const toAfter = (await db.collection('tos').doc(st.toId).get()).data();
  log(`   공고 모집 임금 ${PROMISED_WAGE} → ${toAfter.workDetails[0].wage}`);
  log(`   지원서 약속 임금 ${app.wage} (변하지 않아야 한다)`);
  check('§11 공고 수정이 지원서 약속을 덮지 않았다', app.wage === PROMISED_WAGE,
      `application.wage=${app.wage}`);

  // ── §22/§24 employer permission ─────────────────────────────────
  //
  //   처음에는 이 사업장의 SubAdmin(kN2g…)을 "권한 없는 사용자"로 놓고
  //   거절을 기대했는데 **통과했다.** 서버가 틀린 것이 아니라 시험이
  //   틀렸다 — 그 계정은 members 문서에 canManageContract=true 를
  //   갖고 있다. 즉 통과가 정답이다(§22 ALIGNED).
  //
  //   진짜 negative 는 그 사업장의 구성원이 **아닌** 계정이다.
  head('§22/§24  사업주 서명 권한');
  {
    const memberSnap = await db.collection('businesses').doc(BIZ)
        .collection('members').doc(OTHER_PERSON).get();
    const perms = memberSnap.exists ? (memberSnap.data().permissions || {}) : {};
    log(`   SubAdmin ${OTHER_PERSON.slice(0, 10)}… canManageContract=${perms.canManageContract}`);
    check('§22 canManageContract 보유 SubAdmin 은 서명할 수 있어야 한다 (ALIGNED)',
        perms.canManageContract === true,
        '실측: 이 계정의 서명 요청이 실제로 통과했다');

    // 구성원이 아닌 계정 — assertBizAdmin 에서 막혀야 한다.
    const probeId = db.collection('employment_contracts').doc().id;
    let outcome = 'ALLOWED(!)';
    try {
      await callAs(WORKER, 'callableFinalizeEmployerSignature', {
        contractId: probeId,
        signatureBase64: S.signaturePng().toString('base64'),
        isNewUnsaved: true,
        contractData: await buildLongTermContractData(st.applicationId),
      });
    } catch (e) { outcome = String(e.message).slice(0, 110); }
    check('§24 사업장 구성원이 아닌 계정 → 거절', outcome !== 'ALLOWED(!)', outcome);
    const leaked = await db.collection('employment_contracts').doc(probeId).get();
    check('§24 거절된 시도가 계약 문서를 남기지 않았다', !leaked.exists);
    const [orphan] = await admin.storage().bucket(BUCKET)
        .getFiles({prefix: `contracts/${probeId}/`});
    check('§24 거절된 시도가 Storage artifact 를 남기지 않았다',
        orphan.length === 0, `${orphan.length}건`);
  }

  // ── T3 사업주 서명 ──────────────────────────────────────────────
  head('T3  사업주 서명 (callableFinalizeEmployerSignature)');
  if (!st.contractId) st.contractId = db.collection('employment_contracts').doc().id;
  writeState(st);
  const cRef = db.collection('employment_contracts').doc(st.contractId);
  log(`   실행 전: contract 문서 존재? ${(await cRef.get()).exists}`);
  const notifBefore = (await db.collection('users').doc(WORKER)
      .collection('notifications').get()).size;

  if (!(await cRef.get()).exists) {
    await callAs(ADMIN, 'callableFinalizeEmployerSignature', {
      contractId: st.contractId,
      signatureBase64: S.signaturePng().toString('base64'),
      isNewUnsaved: true,
      contractData: await buildLongTermContractData(st.applicationId),
    });
  }
  const c1 = (await cRef.get()).data();
  check('T3 계약서가 생성됐다', !!c1);
  check('T3 status = pending_worker', c1.status === 'pending_worker', `status=${c1.status}`);
  check('T3 employerSignedAt 기록', !!c1.employerSignedAt, stamp(c1.employerSignedAt));
  check('T3 employerSignatureUrl/Hash 기록',
      !!c1.employerSignatureUrl && !!c1.employerSignatureHash);
  check('T3 isLongTerm = true', c1.isLongTerm === true);
  check('T3 장기에는 slots 가 비어 있다', Array.isArray(c1.slots) && c1.slots.length === 0,
      `slots=${JSON.stringify(c1.slots)}`);

  // ── §14 사업주 서명 후 Application 은 아직 CONTRACT_PENDING ─────
  const appAfterEmployer =
    (await db.collection('applications').doc(st.applicationId).get()).data();
  check('§14 사업주 서명만으로 CONFIRMED 가 되지 않는다',
      appAfterEmployer.status === 'CONTRACT_PENDING',
      `status=${appAfterEmployer.status}`);

  // ── §9 contractSignRequested ────────────────────────────────────
  head('§9  contractSignRequested 알림');
  const nts = await db.collection('users').doc(WORKER).collection('notifications')
      .where('data.contractId', '==', st.contractId).get();
  const n0 = nts.docs[0]?.data();
  check('§9 근로자 알림 1건 생성', nts.size === 1, `count=${nts.size} (이전 총 ${notifBefore}건)`);
  if (n0) {
    log(`   type=${n0.type} screen=${n0.data.screen} ` +
      `businessId=${n0.data.businessId} applicationId=${n0.data.applicationId}`);
    check('§9 type = contractSignRequested', n0.type === 'contractSignRequested');
    check('§9 payload 에 contractId·businessId·applicationId·screen',
        !!n0.data.contractId && !!n0.data.businessId &&
        !!n0.data.applicationId && n0.data.screen === 'contractSign');
  }

  // ── §25 employer idempotency ────────────────────────────────────
  head('§25  사업주 서명 재요청');
  {
    let outcome = 'ALLOWED(!)';
    try {
      await callAs(ADMIN, 'callableFinalizeEmployerSignature', {
        contractId: db.collection('employment_contracts').doc().id,
        signatureBase64: S.signaturePng().toString('base64'),
        isNewUnsaved: true,
        contractData: await buildLongTermContractData(st.applicationId),
      });
    } catch (e) { outcome = String(e.message).slice(0, 110); }
    check('§25 같은 지원서에 두 번째 계약서 발송 → 거절', outcome !== 'ALLOWED(!)', outcome);
    const all = await db.collection('employment_contracts')
        .where('applicationId', '==', st.applicationId).get();
    check('§16/§31 같은 지원서의 active 계약서는 하나뿐',
        all.docs.filter((d) => d.data().status !== 'voided').length === 1,
        `총 ${all.size}건`);
  }

  // ── §10/§23 worker identity gate ────────────────────────────────
  head('§23  다른 근로자의 서명 — 거절되어야 한다');
  {
    let outcome = 'ALLOWED(!)';
    try {
      await callAs(OTHER_PERSON, 'callableFinalizeWorkerSignature', {
        contractId: st.contractId,
        signatureBase64: S.signaturePng(200, 80).toString('base64'),
        pdfBase64: S.onePagePdf(['wrong signer']).toString('base64'),
      });
    } catch (e) { outcome = String(e.message).slice(0, 110); }
    check('§23 계약 당사자가 아닌 근로자 → 거절', outcome !== 'ALLOWED(!)', outcome);
    const still = (await cRef.get()).data();
    check('§23 거절이 계약 상태를 바꾸지 않았다', still.status === 'pending_worker' &&
      !still.workerSignatureUrl);
  }

  // ── §17 staffing seat — 서명 전 ─────────────────────────────────
  const seatBefore = await seatOnDay(st.toId, 0);

  // ── T4 근로자 서명 ──────────────────────────────────────────────
  head('T4  근로자 서명 (callableFinalizeWorkerSignature)');
  if (!c1.workerSignatureUrl) {
    await callAs(WORKER, 'callableFinalizeWorkerSignature', {
      contractId: st.contractId,
      signatureBase64: S.signaturePng(200, 80).toString('base64'),
      pdfBase64: S.onePagePdf([
        'ALfit DEV runtime - long-term employment contract',
        `contract: ${st.contractId}`,
        `period: ${kstDateKey(FROM_OFFSET)} ~ ${kstDateKey(TO_OFFSET)}`,
        `days: ${WORK_DAYS.join(' ')}  time: ${START_TIME}-${END_TIME}`,
        'This document is DEV test data. Not a real contract.',
      ]).toString('base64'),
    });
  }
  const c2 = (await cRef.get()).data();
  check('T4 status = completed', c2.status === 'completed', `status=${c2.status}`);
  check('T4 workerSignedAt 기록', !!c2.workerSignedAt, stamp(c2.workerSignedAt));
  check('T4 employerSignedAt 보존', !!c2.employerSignedAt);
  check('§15 pdfUrl 존재', !!c2.pdfUrl);
  check('§15 pdfHash 존재하고 비어 있지 않다',
      typeof c2.pdfHash === 'string' && c2.pdfHash.length === 64, `len=${(c2.pdfHash||'').length}`);
  check('§15 서명 이미지 두 장 모두 참조 가능',
      !!c2.employerSignatureUrl && !!c2.workerSignatureUrl);

  const appFinal =
    (await db.collection('applications').doc(st.applicationId).get()).data();
  check('§13 Application status = CONFIRMED', appFinal.status === 'CONFIRMED',
      `status=${appFinal.status}`);
  const hist = (appFinal.statusHistory || []).slice(-1)[0];
  check('§13 statusHistory 에 CONTRACT_SIGNED 기록',
      hist && hist.action === 'CONTRACT_SIGNED', JSON.stringify(hist || {}));

  // ── §26 worker idempotency ──────────────────────────────────────
  head('§26  완료 계약에 재서명');
  {
    const pdfBefore = c2.pdfUrl; const hashBefore = c2.pdfHash;
    let outcome = 'ALLOWED(!)';
    try {
      await callAs(WORKER, 'callableFinalizeWorkerSignature', {
        contractId: st.contractId,
        signatureBase64: S.signaturePng(200, 80).toString('base64'),
        pdfBase64: S.onePagePdf(['second attempt']).toString('base64'),
      });
    } catch (e) { outcome = String(e.message).slice(0, 110); }
    check('§26 완료 계약 재서명 → 거절', outcome !== 'ALLOWED(!)', outcome);
    const c3 = (await cRef.get()).data();
    check('§26 PDF 가 덮어쓰이지 않았다',
        c3.pdfUrl === pdfBefore && c3.pdfHash === hashBefore);
    check('§26 Application 상태가 더 변하지 않았다', c3.status === 'completed');
  }

  // ── §17 staffing seat — 서명 후 ─────────────────────────────────
  head('§17  좌석 parity');
  const seatAfter = await seatOnDay(st.toId, 0);
  log(`   오늘(${kstDateKey(0)}) 좌석  before=${seatBefore}  after=${seatAfter}`);
  check('§17 계약 완료가 좌석을 늘리지 않았다', seatBefore === seatAfter,
      `${seatBefore} → ${seatAfter}`);

  await postStateChecks(st);
  await summarize(invBefore, pre0Before);
}

/**
 * 서명이 끝난 뒤에도 언제든 다시 볼 수 있는 것들 — 약속 parity, 기간 보존,
 * reader 도달성. lifecycle 전이 단언은 여기 넣지 않는다. 그건 그 순간에만
 * 관측된다.
 */
async function postStateChecks(st) {
  const appFinal =
    (await db.collection('applications').doc(st.applicationId).get()).data();
  const c2 = (await db.collection('employment_contracts').doc(st.contractId).get()).data();
  const toAfter = (await db.collection('tos').doc(st.toId).get()).data();

  head('§14  Application ↔ Contract promise parity');
  const sn = c2.snapshot || {};
  const rows = [
    ['period start', iso(appFinal.desiredStartDate || appFinal.workDate), sn.contractStart],
    ['period end', iso(appFinal.workEndDate), sn.contractEnd],
    ['workDays', (appFinal.workDays || []).join(','), (sn.workDays || []).join(',')],
    ['workType', appFinal.selectedWorkType, sn.workType],
    ['startTime', appFinal.startTime, sn.startTime],
    ['endTime', appFinal.endTime, sn.endTime],
    ['breakMinutes', appFinal.breakMinutes ?? 0, sn.breakMinutes ?? 0],
    ['wage', appFinal.wage, sn.wage],
    ['wageType', appFinal.wageType, sn.wageType],
    ['tax', appFinal.taxDeductionType ?? 'none', sn.taxDeductionType ?? 'none'],
    ['paySchedule', appFinal.payScheduleType ?? null, sn.payScheduleType ?? null],
    ['businessId', appFinal.businessId, c2.businessId],
    ['workerUid', appFinal.uid, c2.workerId],
    ['applicationId', st.applicationId, c2.applicationId],
  ];
  log('   FIELD           APPLICATION            CONTRACT               RESULT');
  let parityFail = 0;
  for (const [f, a, b] of rows) {
    const ok = String(a) === String(b);
    if (!ok) parityFail++;
    log(`   ${String(f).padEnd(15)} ${String(a).padEnd(22)} ${String(b).padEnd(22)} ` +
      `${ok ? 'MATCH' : 'MISMATCH'}`);
  }
  check('§14 promise parity 전부 일치', parityFail === 0, `불일치 ${parityFail}건`);
  log(`   (참고) 현재 공고 모집 임금 = ${toAfter.workDetails[0].wage} — ` +
    '계약과 달라도 정상이다. 공고는 앞으로 모집할 사람의 조건이다.');
  check('§11 계약이 공고의 현재 임금을 쓰지 않았다',
      sn.wage !== POSTING_WAGE_AFTER && sn.wage === PROMISED_WAGE,
      `contract.wage=${sn.wage}`);

  // ── §12 장기 기간이 slots 로 축약되지 않았다 ────────────────────
  check('§12 장기 기간이 slots[].workDate 로 축약되지 않았다',
      Array.isArray(c2.slots) && c2.slots.length === 0 &&
      !!sn.contractStart && !!sn.contractEnd);

  // ── §18 reader parity ───────────────────────────────────────────
  head('§18  reader parity — 같은 contractId 를 찾는가');
  const byApp = await db.collection('employment_contracts')
      .where('applicationId', '==', st.applicationId)
      .where('businessId', '==', BIZ).limit(5).get();
  const byAppIds = await db.collection('employment_contracts')
      .where('applicationIds', 'array-contains', st.applicationId)
      .where('businessId', '==', BIZ).limit(5).get();
  const byWorker = await db.collection('employment_contracts')
      .where('workerId', '==', WORKER).where('status', '==', 'completed').get();
  const byBiz = await db.collection('employment_contracts')
      .where('businessId', '==', BIZ).where('status', '==', 'completed').get();
  const byLong = await db.collection('employment_contracts')
      .where('isLongTerm', '==', true).get();
  const has = (s) => s.docs.some((d) => d.id === st.contractId);
  check('§18 applicationId 조회', has(byApp));
  check('§18 applicationIds array-contains 조회', has(byAppIds));
  check('§18 근로자 계약 이력 조회', has(byWorker));
  check('§18 사업장 계약 관리 조회', has(byBiz));
  check('§20 isLongTerm=true 로 장기 판별 가능', has(byLong),
      `isLongTerm=true 계약 ${byLong.size}건`);
}

/** PRE0 보존 확인 + 집계. */
async function summarize(invBefore, pre0Before) {
  head('§37  PRE0 fixture 보존');
  const pre0After = await pre0Snapshot();
  const same = JSON.stringify(pre0Before) === JSON.stringify(pre0After);
  check('R7_FIX_LT_WORKER 가 변하지 않았다', same,
      same ? JSON.stringify(pre0After) :
        `BEFORE ${JSON.stringify(pre0Before)}\n        AFTER  ${JSON.stringify(pre0After)}`);

  // ── 요약 ────────────────────────────────────────────────────────
  head('요약');
  await inventory('AFTER ');
  log(`   기준선 ${JSON.stringify(invBefore)}`);
  const failed = results.filter((r) => !r.ok);
  log(`\n   ${results.length - failed.length}/${results.length} PASS`);
  if (failed.length) {
    log('   실패:');
    failed.forEach((r) => log(`     · ${r.label}`));
  }
  log(`\n   state: ${path.basename(STATE)} — 정리는 --cleanup --execute`);
}

/** 그 날짜의 이 공고 좌석 수 — 서버 staffing 과 같은 규칙. */
async function seatOnDay(toId, offset) {
  const dayMs = kstMidnightMs(offset);
  const dnum = Number(kstDateKey(offset).replace(/-/g, ''));
  const WK = ['일', '월', '화', '수', '목', '금', '토'];
  const wkd = WK[new Date(dayMs + KST).getUTCDay()];
  const snap = await db.collection('applications')
      .where('toId', '==', toId)
      .where('status', 'in', ['CONFIRMED', 'CONTRACT_PENDING']).get();
  let n = 0;
  for (const d of snap.docs) {
    const a = d.data();
    let s = a.desiredStartDate ? Number(iso(a.desiredStartDate).replace(/-/g, '')) :
      (a.workDate ? Number(iso(a.workDate).replace(/-/g, '')) : 0);
    if (!a.desiredStartDate && a.confirmedAt) {
      const c = Number(iso(a.confirmedAt).replace(/-/g, ''));
      if (c > s) s = c;
    }
    if (dnum < s) continue;
    const end = a.actualResignDate || a.workEndDate;
    if (!end) continue;
    if (dnum > Number(iso(end).replace(/-/g, ''))) continue;
    const hasDay = (k) => Array.isArray(a[k]) &&
      a[k].some((t) => Number(iso(t).replace(/-/g, '')) === dnum);
    if (hasDay('extraWorkDates')) { n++; continue; }
    if (hasDay('leaveDates')) continue;
    if (!(a.workDays || []).includes(wkd)) continue;
    n++;
  }
  return n;
}

main().then(() => process.exit(0)).catch((e) => {
  console.error('\n실패:', e && e.message ? e.message : e);
  process.exit(1);
});
