/**
 * [R7-PAYROLL-POLICY.4B §41·§42·§44] DEV 런타임.
 *
 *   §41 actor
 *     A1. BUSINESS_ADMIN(owner) → 사업장 기준 확인 성공 · actorRole·actor uid 확인
 *     A2. 권한 없는 호출자(근로자) → 실패 + side effect 0
 *     A3. 다른 사업장 관리자 → 실패
 *     A4. SUPER_ADMIN → 결정된 semantics 검증
 *         (DEV 에 SUPER_ADMIN 계정이 없으면 ABSENT 로 기록 — 위조하지 않는다)
 *     A5. 지원서 기준 확인도 같은 actor 계약
 *
 *   §42 disclosure data
 *     B1. snapshot A 생성 → 사업장 기준 B 로 변경 → 지원서 payload 에 A 7개 그대로
 *     B2. callableGetMyApplications 응답(근로자가 실제로 받는 것)에 7개 전부 존재
 *
 *   §44 confirmed reassignment
 *     C1. 확정 A → 재배치 B 제안/수락 → B snapshot == A, 현재 기준 C 와 무관
 *
 *   사업장 기준 값 변경만 Admin SDK 직접 쓰기다(테스트 설정).
 *   확인 기록은 이 스크립트가 쓰지 않는다.
 */
'use strict';
const fs = require('fs');
const lib = require('./r7-fixture-lib');
const {db} = lib;
const unwrap = (r) => (r && (r.result ?? r.data)) ?? r;
const CONSENT = '2026-09-18-v3';
const KST = 9 * 3600000;
const pad = (n) => String(n).padStart(2, '0');
// [4B] 내일로 잡는다 — 오늘은 .4A 런타임에서 이미 확정된 근로자가 많다.
//   이 Phase 는 출퇴근을 보지 않으니 미래 날짜로 충분하다.
const DAY = 1;

const G = JSON.parse(fs.readFileSync('.goldenpath.json', 'utf8'));
const businessId = G.businessId;
const adminUid = G.adminUid;
const bizRef = db.collection('businesses').doc(businessId);

const F = ['earlyWindow', 'earlyArrivalUnit', 'lateGrace', 'lateUnit',
  'lateWindow', 'overtimeUnit', 'earlyLeaveUnit'];
const all7 = (o) => o != null && F.every((k) => typeof o[k] === 'number');
const brief = (o) => o == null ? '(없음)' :
  F.map((k) => `${k.slice(0, 9)}=${o[k]}`).join(' ');
const same7 = (a, b) => a != null && b != null && F.every((k) => a[k] === b[k]);
const reasonOf = (e) => {
  const d = e && e.details;
  if (d && d.reason) return d.reason;
  return String((e && e.code) || '') + ' ' +
    String((e && e.message) || e).slice(0, 80);
};

const A = {lateGrace: 5, lateUnit: 30, earlyLeaveUnit: 30, overtimeUnit: 30};
const B = {lateGrace: 10, lateUnit: 10, earlyLeaveUnit: 10, overtimeUnit: 10};
const C = {lateGrace: 3, lateUnit: 20, earlyLeaveUnit: 20, overtimeUnit: 20};

async function setRules(p) {
  const upd = {};
  for (const k of Object.keys(p)) upd[`attendanceRules.${k}`] = p[k];
  await bizRef.update(upd);
}
const confirmPolicy = (uid = adminUid) =>
  lib.callAs(uid, 'callableConfirmAttendancePolicy', {businessId});

async function makeTO(label, startOffsetMin) {
  const nowKst = new Date(Date.now() + KST);
  const dateStr = lib.kstDateKey(DAY);
  const workDateMs = lib.kstMidnightMs(DAY);
  const sM = nowKst.getUTCHours() * 60 + nowKst.getUTCMinutes() + startOffsetMin;
  const START = `${pad(Math.floor(sM / 60))}:${pad(sM % 60)}`;
  const END = `${pad(Math.floor((sM + 1) / 60))}:${pad((sM + 1) % 60)}`;
  const biz = (await bizRef.get()).data();
  const wts = (await bizRef.collection('workTypes').limit(2).get()).docs;
  const mk = (i) => ({
    wdId: `p4b-${label}-${i}`,
    workType: (wts[Math.min(i, wts.length - 1)].data()).name,
    workTypeIcon: 'box', workTypeColor: '#1565C0',
    workTypeBackgroundColor: '#E3F2FD',
    wage: 12000 + i * 1000, wageType: 'hourly', requiredCount: 1,
    startTime: START, endTime: END, order: i, payScheduleType: 'next_day',
  });
  const wds = [mk(0), mk(1)];
  const created = unwrap(await lib.callAs(adminUid, 'callableCreateTO', {
    toData: {
      businessId, businessName: biz.name, title: `[P4B-${label}] actor/고지`,
      description: 'R7-PAYROLL-POLICY.4B 전용. 실제 모집 아님.',
      type: 'flex', workDetails: wds, creatorUID: adminUid,
      totalRequired: 2, totalConfirmed: 0, totalPending: 0, status: 'active',
      deadlineType: 'FIXED_TIME', hoursBeforeStart: 1,
      isPublished: false, publishMode: 'deferred',
    },
  }));
  const toId = created.toId;
  await lib.callAs(adminUid, 'callableCreateFlexSlots', {
    toId, businessId, dates: [dateStr], workDetails: wds,
    deadlineType: 'FIXED_TIME', hoursBeforeStart: 1,
    fixedDeadlineMs: Date.now() + 180000, publishMode: 'immediate',
  });
  await lib.callAs(adminUid, 'callablePublishTO', {toId});
  const slots = await db.collection('tos').doc(toId).collection('slots').get();
  const to = (await db.collection('tos').doc(toId).get()).data();
  return {
    toId, slotId: slots.docs[0].id,
    slotWds: slots.docs[0].data().workDetails || [],
    to, workDateMs, START, END,
  };
}

async function apply(uid, T, i) {
  const wd = T.slotWds[i];
  const ap = unwrap(await lib.callAs(uid, 'callableApplyToTO', {
    toId: T.toId, slotId: T.slotId, businessId,
    businessName: T.to.businessName, toTitle: T.to.title,
    workDateMs: T.workDateMs, selectedWorkType: wd.workType,
    workDetailId: wd.wdId, startTime: T.START, endTime: T.END,
    wage: wd.wage, wageType: 'hourly',
    idCardConsentGiven: true, documentAccessConsentGiven: true,
    documentAccessConsentVersion: CONSENT,
  }));
  return ap.applicationId;
}

async function reviewDocs(applicationId) {
  const rev = unwrap(await lib.callAs(adminUid,
    'callableGetApplicantDocumentReview', {applicationId, businessId}));
  if (rev.readiness.ready) return;
  for (const t of ['ID', 'BANKBOOK']) {
    await lib.callAs(adminUid, 'callableReviewApplicantDocument', {
      applicationId, businessId, targetUid: rev.workerUid, documentType: t,
      decision: 'REVIEWED_OK',
      expectedVersion: t === 'ID' ? rev.versions.id : rev.versions.bankbook,
      expectedAccountVersion: rev.versions.account,
    });
  }
}

const appDoc = (id) =>
  db.collection('applications').doc(id).get().then((d) => d.data());

(async () => {
  const biz0 = (await bizRef.get()).data();
  const originalRules = biz0.attendanceRules;
  const originalCfm = biz0.attendancePolicyConfirmation ?? null;
  const createdTOIds = [];

  try {
    const users = await db.collection('users').where('role', '==', 'USER').get();
    const workDateMs = lib.kstMidnightMs(DAY);
    const free = [];
    for (const u of users.docs) {
      const busy = await db.collection('applications')
        .where('uid', '==', u.id)
        .where('status', 'in', ['CONFIRMED', 'CONTRACT_PENDING']).get();
      if (!busy.docs.some((d) => d.data().workDate?.toMillis() === workDateMs)) {
        free.push(u.id);
      }
    }
    if (free.length < 2) throw new Error('오늘 비어 있는 근로자가 2명 필요하다');
    const [uidA, uidB] = free;

    // ── §41 A1. 사업장 관리자 확인 ──────────────────────────────
    console.log('═══ §41 A1. 사업장 관리자(owner/adminIds) 확인 ═══');
    await setRules(A);
    await confirmPolicy();
    let bizNow = (await bizRef.get()).data();
    const cfm = bizNow.attendancePolicyConfirmation;
    console.log('  기록:', brief(cfm));
    console.log('  actorRole =', cfm.actorRole,
      cfm.actorRole === 'business_admin' ? '(사업장 측)' : '(**예상 밖**)');
    console.log('  confirmedBy 일치 =', cfm.confirmedBy === adminUid ? '예' : '**아니오**');
    console.log('  confirmedAt 있음 =', cfm.confirmedAt ? '예' : '**아니오**');
    console.log('  7개 전부 기록 =', all7(cfm) ? '예' : '**아니오**');
    const cfmAtFirst = cfm.confirmedAt.toMillis();

    // ── A2. 권한 없는 호출자 ───────────────────────────────────
    console.log('\n═══ §41 A2. 권한 없는 호출자(근로자) ═══');
    try {
      await confirmPolicy(uidA);
      console.log('  **통과했다 — 경계 미작동**');
    } catch (e) {
      console.log('  차단:', reasonOf(e));
    }
    bizNow = (await bizRef.get()).data();
    console.log('  side effect 0 =',
      bizNow.attendancePolicyConfirmation.confirmedAt.toMillis() === cfmAtFirst &&
      bizNow.attendancePolicyConfirmation.confirmedBy === adminUid ?
        '예 (기록 불변)' : '**기록이 바뀌었다**');

    // ── A3. 다른 사업장 관리자 ─────────────────────────────────
    console.log('\n═══ §41 A3. 다른 사업장 관리자 ═══');
    const otherBiz = (await db.collection('businesses').get()).docs
      .filter((d) => d.id !== businessId);
    let otherAdmin = null;
    for (const d of otherBiz) {
      const ids = (d.data().adminIds || []).concat([d.data().ownerId]);
      const cand = ids.find((u) => u && u !== adminUid);
      if (cand) { otherAdmin = cand; break; }
    }
    if (!otherAdmin) {
      console.log('  다른 사업장 관리자 ABSENT — 이 축은 DEV 표본 없음');
    } else {
      try {
        await confirmPolicy(otherAdmin);
        console.log('  **통과했다 — 소속 검사 미작동**');
      } catch (e) {
        console.log('  차단:', reasonOf(e));
      }
    }

    // ── A4. SUPER_ADMIN ───────────────────────────────────────
    console.log('\n═══ §41 A4. SUPER_ADMIN ═══');
    const supers = await db.collection('users')
      .where('role', '==', 'SUPER_ADMIN').limit(1).get();
    if (supers.empty) {
      console.log('  SUPER_ADMIN 계정 ABSENT — DEV 표본 0.');
      console.log('  → 런타임 증명 불가. CODE/TEST 로만 고정(ACT-3).');
    } else {
      const su = supers.docs[0].id;
      try {
        await confirmPolicy(su);
        console.log('  **통과했다 — 운영자 행위가 사업장 확인으로 기록된다**');
      } catch (e) {
        console.log('  차단:', reasonOf(e));
      }
    }

    // ── §42 B1. 지원 snapshot 이 기준 변경에도 불변 ────────────
    console.log('\n═══ §42 B1. 지원 snapshot 불변 ═══');
    const T = await makeTO('disc', 5);
    createdTOIds.push(T.toId);
    const appA = await apply(uidA, T, 0);
    const a0 = await appDoc(appA);
    console.log('  지원 시점 snapshot(A):', brief(a0.attendancePolicySnapshot));
    console.log('  7개 전부 =', all7(a0.attendancePolicySnapshot) ? '예' : '**아니오**');
    await setRules(B);
    await confirmPolicy();
    const a1 = await appDoc(appA);
    console.log('  사업장 기준 B 로 변경 후 snapshot:',
      same7(a1.attendancePolicySnapshot, a0.attendancePolicySnapshot) ?
        'A 그대로' : '**바뀌었다**');
    console.log('  사업장 현재:', brief((await bizRef.get()).data().attendanceRules));

    // ── §41 A5. 지원서 기준 확인 (mismatch 경로) ───────────────
    console.log('\n═══ §41 A5. 지원서 기준 확인 — 같은 actor 계약 ═══');
    try {
      await lib.callAs(uidA, 'callableAcknowledgeApplicationPolicy',
        {applicationId: appA, businessId});
      console.log('  근로자 호출 **통과 — 경계 미작동**');
    } catch (e) {
      console.log('  근로자 호출 차단:', reasonOf(e));
    }
    if (!supers.empty) {
      try {
        await lib.callAs(supers.docs[0].id,
          'callableAcknowledgeApplicationPolicy', {applicationId: appA, businessId});
        console.log('  SUPER_ADMIN **통과 — 운영자가 사업장 확인을 만들었다**');
      } catch (e) {
        console.log('  SUPER_ADMIN 차단:', reasonOf(e));
      }
    }
    await lib.callAs(adminUid, 'callableAcknowledgeApplicationPolicy',
      {applicationId: appA, businessId});
    const a2 = await appDoc(appA);
    const ack = a2.attendancePolicyAcknowledgement;
    console.log('  관리자 확인 기록:', brief(ack));
    console.log('  actorRole =', ack.actorRole,
      '· by 일치 =', ack.acknowledgedBy === adminUid ? '예' : '**아니오**',
      '· 7개 전부 =', all7(ack) ? '예' : '**아니오**');

    // ── §42 B2. 근로자가 받는 payload 에 7개 전부 ──────────────
    console.log('\n═══ §42 B2. 근로자 payload(7개 전부) ═══');
    const mine = unwrap(await lib.callAs(uidA, 'callableGetMyApplications', {}));
    const row = (mine.applications || []).find((x) => x.id === appA);
    if (!row) {
      console.log('  **응답에 이 지원서가 없다**');
    } else {
      const s = row.attendancePolicySnapshot;
      console.log('  payload snapshot:', brief(s));
      console.log('  7개 전부 =', all7(s) ? '예' : '**아니오**');
      console.log('  A 와 동일 =',
        same7(s, a0.attendancePolicySnapshot) ? '예' : '**아니오**');
    }

    // ── §44 C1. 확정 재배치 ───────────────────────────────────
    console.log('\n═══ §44 C1. 확정 재배치 — 원 약속 상속 ═══');
    await reviewDocs(appA);
    await lib.callAs(adminUid, 'callableConfirmApplication',
      {applicationId: appA, businessId});
    const conf = await appDoc(appA);
    console.log('  A 확정 status =', conf.status,
      '· snapshot =', same7(conf.attendancePolicySnapshot,
        a0.attendancePolicySnapshot) ? 'A 그대로' : '**바뀌었다**');
    let proposalId = null;
    try {
      const pr = unwrap(await lib.callAs(adminUid,
        'callableProposeConfirmedReassignment', {
          sourceApplicationId: appA,
          targetWdId: T.slotWds[1].wdId,
          compensationOption: 'TARGET_BASE',
        }));
      proposalId = pr.proposalId;
      console.log('  제안 생성:', proposalId);
    } catch (e) {
      console.log('  제안 PENDING — 실행 불가:', reasonOf(e));
    }
    if (proposalId) {
      // 사업장 기준을 C 로 바꾸고 확인 — 수락이 C 를 끌어오면 안 된다.
      await setRules(C);
      await confirmPolicy();
      console.log('  사업장 기준 C:',
        brief((await bizRef.get()).data().attendanceRules));
      try {
        await lib.callAs(uidA, 'callableAcceptConfirmedReassignment', {
          proposalId,
          documentAccessConsentGiven: true,
          documentAccessConsentVersion: CONSENT,
        });
        const pdoc = (await db.collection('applications').doc(proposalId).get())
          .data();
        const newId = pdoc && pdoc.resultApplicationId;
        const target = newId ? await appDoc(newId) : null;
        if (target == null) {
          console.log('  수락 후 결과 지원서를 찾지 못함 — PENDING');
        } else {
          console.log('  B status =', target.status);
          console.log('  B snapshot:', brief(target.attendancePolicySnapshot));
          console.log('  A 와 동일 =',
            same7(target.attendancePolicySnapshot,
              a0.attendancePolicySnapshot) ? '예 (상속)' : '**아니오**');
          console.log('  현재 기준 C 와 무관 =',
            same7(target.attendancePolicySnapshot,
              (await bizRef.get()).data().attendanceRules) ?
              '**아니오 — C 를 끌어왔다**' : '예');
          console.log('  확인 기록 상속 =',
            same7(target.attendancePolicyAcknowledgement, ack) &&
            target.attendancePolicyAcknowledgement.acknowledgedBy ===
              ack.acknowledgedBy ? '예' : '**아니오**');
        }
      } catch (e) {
        console.log('  수락 PENDING — 실행 불가:', reasonOf(e));
      }
    }
    void uidB;

    fs.writeFileSync('.p4bfixture.json', JSON.stringify({
      businessId, adminUid, uidA, uidB, appA, proposalId,
      toIds: createdTOIds,
    }, null, 2));
  } finally {
    await bizRef.update({attendanceRules: originalRules});
    if (originalCfm != null) {
      await bizRef.update({attendancePolicyConfirmation: originalCfm});
    } else {
      await bizRef.update({
        attendancePolicyConfirmation:
          lib.admin.firestore.FieldValue.delete(),
      });
    }
    for (const toId of createdTOIds) {
      try {
        await lib.callAs(adminUid, 'callableCloseTOManually', {toId, businessId});
      } catch (e) { console.log('  공고 정리 실패', toId, e.message); }
    }
    const back = (await bizRef.get()).data();
    console.log('\n기준 원복:', brief(back.attendanceRules),
      same7(back.attendanceRules, originalRules) ? '(확인)' : '(**불일치**)');
    console.log('확인 원복:',
      back.attendancePolicyConfirmation == null ? '(없음 — 원래 상태)' : '있음');
  }
  process.exit(0);
})().catch((e) => { console.error('실패:', e.message); process.exit(1); });
