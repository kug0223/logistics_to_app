/**
 * [R7-PAYROLL-POLICY.4] **지원 시점에 찍힌** snapshot 이 실제 계산을 지배하는가.
 *
 *   `.3` 은 "확정 시 snapshot" 이 계산을 지배함을 산술로 증명했다.
 *   `.4` 는 snapshot 을 **지원 시점**에 찍는다. 그 값이 계산에 쓰이는지를
 *   구분되는 케이스로 다시 본다.
 *
 *   절차:
 *     1. 사업장 기준을 B(grace 10 / lateUnit 10)로 두고 확인
 *     2. 지원 → snapshot B 가 찍힌다 → 확정
 *     3. 사업장 기준을 A(grace 5 / lateUnit 30)로 바꾸고 확인
 *     4. START + 6분에 출근
 *
 *   snapshot B(grace 10) → 6 ≤ 10 → **정시(START)**
 *   live     A(grace 5)  → 지각 ceil(6/30)*30 → **START + 30분**
 *
 *   적용된 checkIn 이 START 면 지원 시점 snapshot 이 계산에 쓰인 것이다.
 */
'use strict';
const fs = require('fs');
const lib = require('./r7-fixture-lib');
const {db} = lib;
const unwrap = (r) => (r && (r.result ?? r.data)) ?? r;
const CONSENT = '2026-09-18-v3';
const KST = 9 * 3600000;
const pad = (n) => String(n).padStart(2, '0');

const G = JSON.parse(fs.readFileSync('.goldenpath.json', 'utf8'));
const businessId = G.businessId;
const adminUid = G.adminUid;
const bizRef = db.collection('businesses').doc(businessId);

const POLICY_B = {lateGrace: 10, lateUnit: 10, earlyLeaveUnit: 10, overtimeUnit: 10};
const POLICY_A = {lateGrace: 5, lateUnit: 30, earlyLeaveUnit: 30, overtimeUnit: 30};

async function setPolicy(p) {
  const upd = {};
  for (const k of Object.keys(p)) upd[`attendanceRules.${k}`] = p[k];
  await bizRef.update(upd);
  await lib.callAs(adminUid, 'callableConfirmAttendancePolicy', {businessId});
}

(async () => {
  const biz0 = (await bizRef.get()).data();
  const original = biz0.attendanceRules;
  const originalCfm = biz0.attendancePolicyConfirmation ?? null;

  try {
    // ── 1. 기준 B 로 두고 확인 ────────────────────────────────
    await setPolicy(POLICY_B);
    console.log('사업장 기준 B 확인 완료 : grace 10 / lateUnit 10');

    // 오늘 비어 있는 근로자 하나
    const users = await db.collection('users').where('role', '==', 'USER').get();
    const workDateMs = lib.kstMidnightMs(0);
    let uid = null;
    for (const u of users.docs) {
      const busy = await db.collection('applications')
        .where('uid', '==', u.id)
        .where('status', 'in', ['CONFIRMED', 'CONTRACT_PENDING']).get();
      if (!busy.docs.some((d) => d.data().workDate?.toMillis() === workDateMs)) {
        uid = u.id; break;
      }
    }
    if (!uid) throw new Error('오늘 비어 있는 근로자가 없다');

    // ── 2. START = now + 9분 인 근무를 만들고 지원·확정 ───────
    const nowKst = new Date(Date.now() + KST);
    const dateStr = lib.kstDateKey(0);
    const sM = nowKst.getUTCHours() * 60 + nowKst.getUTCMinutes() + 9;
    const START = `${pad(Math.floor(sM / 60))}:${pad(sM % 60)}`;
    const END = `${pad(Math.floor((sM + 1) / 60))}:${pad((sM + 1) % 60)}`;
    const biz = (await bizRef.get()).data();
    const wt = (await bizRef.collection('workTypes').limit(1).get())
      .docs[0].data();
    const wd = {
      wdId: 'p4-arith', workType: wt.name,
      workTypeIcon: wt.icon ?? 'box', workTypeColor: wt.color ?? '#1565C0',
      workTypeBackgroundColor: wt.backgroundColor ?? '#E3F2FD',
      wage: 12000, wageType: 'hourly', requiredCount: 1,
      startTime: START, endTime: END, order: 0, payScheduleType: 'next_day',
    };
    const created = unwrap(await lib.callAs(adminUid, 'callableCreateTO', {
      toData: {
        businessId, businessName: biz.name, title: '[P4-ARITH] 지원 snapshot 산술',
        description: 'R7-PAYROLL-POLICY.4 전용. 실제 모집 아님.',
        type: 'flex', workDetails: [wd], creatorUID: adminUid,
        totalRequired: 1, totalConfirmed: 0, totalPending: 0, status: 'active',
        deadlineType: 'FIXED_TIME', hoursBeforeStart: 1,
        isPublished: false, publishMode: 'deferred',
      },
    }));
    const toId = created.toId;
    await lib.callAs(adminUid, 'callableCreateFlexSlots', {
      toId, businessId, dates: [dateStr], workDetails: [wd],
      deadlineType: 'FIXED_TIME', hoursBeforeStart: 1,
      fixedDeadlineMs: Date.now() + 120000, publishMode: 'immediate',
    });
    try { await lib.callAs(adminUid, 'callablePublishTO', {toId}); } catch (e) { console.log('  publishTO 실패:', e.message); }
    const slots = await db.collection('tos').doc(toId).collection('slots').get();
    const slotId = slots.docs[0].id;
    const wdId = ((slots.docs[0].data().workDetails || [])[0] || {}).wdId;
    const to = (await db.collection('tos').doc(toId).get()).data();

    const ap = unwrap(await lib.callAs(uid, 'callableApplyToTO', {
      toId, slotId, businessId, businessName: to.businessName,
      toTitle: to.title, workDateMs,
      selectedWorkType: wd.workType, workDetailId: wdId,
      startTime: START, endTime: END, wage: wd.wage, wageType: 'hourly',
      idCardConsentGiven: true, documentAccessConsentGiven: true,
      documentAccessConsentVersion: CONSENT,
    }));
    const applicationId = ap.applicationId;
    const appAfterApply = (await db.collection('applications')
      .doc(applicationId).get()).data();
    const snap = appAfterApply.attendancePolicySnapshot;
    console.log('지원 시점 snapshot : grace', snap.lateGrace,
      '/ lateUnit', snap.lateUnit);

    const rev = unwrap(await lib.callAs(adminUid,
      'callableGetApplicantDocumentReview', {applicationId, businessId}));
    if (!rev.readiness.ready) {
      for (const t of ['ID', 'BANKBOOK']) {
        await lib.callAs(adminUid, 'callableReviewApplicantDocument', {
          applicationId, businessId, targetUid: rev.workerUid, documentType: t,
          decision: 'REVIEWED_OK',
          expectedVersion: t === 'ID' ? rev.versions.id : rev.versions.bankbook,
          expectedAccountVersion: rev.versions.account,
        });
      }
    }
    await lib.callAs(adminUid, 'callableConfirmApplication',
      {applicationId, businessId});
    const appAfterConfirm = (await db.collection('applications')
      .doc(applicationId).get()).data();
    console.log('확정 후 snapshot   : grace',
      appAfterConfirm.attendancePolicySnapshot.lateGrace,
      '/ lateUnit', appAfterConfirm.attendancePolicySnapshot.lateUnit,
      appAfterConfirm.attendancePolicySnapshot.lateGrace === snap.lateGrace ?
        '(지원 시점 유지)' : '(**덮였다**)');

    // ── 3. 사업장 기준을 A 로 바꾸고 확인 ─────────────────────
    await setPolicy(POLICY_A);
    const live = (await bizRef.get()).data().attendanceRules;
    console.log('사업장 live 기준   : grace', live.lateGrace,
      '/ lateUnit', live.lateUnit);
    if (live.lateGrace === snap.lateGrace) {
      throw new Error('두 기준이 같아 구분할 수 없다');
    }

    // ── 4. START + 6분에 출근 ────────────────────────────────
    const [sh, sm] = START.split(':').map(Number);
    const startMs = workDateMs + (sh * 60 + sm) * 60000;
    const targetMs = startMs + 6 * 60000 + 15000;
    const hhmm = (ms) => new Date(ms + KST).toISOString().slice(11, 16);
    console.log('근무 시작:', START, '| 목표 출근:', hhmm(targetMs),
      '(START + 6분)');
    while (Date.now() < targetMs) {
      await new Promise((r) => setTimeout(r, 5000));
    }
    const ci = unwrap(await lib.callAs(uid, 'callableCheckIn', {
      applicationId, businessId, businessName: biz.name, workDateMs,
      workType: wd.workType, method: 'gps',
      latitude: biz.latitude, longitude: biz.longitude,
      scheduledStartTime: START,
    }));
    const att = (await db.collection('attendance').doc(ci.attendanceId).get())
      .data();
    const t = (v) => v && v.toMillis ?
      new Date(v.toMillis() + KST).toISOString().slice(11, 16) : '(없음)';
    const appliedMs = att.checkIn.toMillis();
    console.log('\n원본 출근:', t(att.originalCheckIn),
      '→ 적용:', t(att.checkIn), '| status:', att.status);
    console.log('  지원 snapshot(10/10) 기대 :', hhmm(startMs), '(정시)');
    console.log('  live(5/30) 기대           :',
      hhmm(startMs + 30 * 60000), '(지각)');
    console.log('\n판정:', appliedMs === startMs ?
      '**지원 시점 snapshot 이 계산에 쓰였다**' :
      (appliedMs === startMs + 30 * 60000 ?
        '**live 기준이 쓰였다 — 회귀**' : '예상 밖 값'));
  } finally {
    await bizRef.update({attendanceRules: original});
    if (originalCfm != null) {
      await bizRef.update({attendancePolicyConfirmation: originalCfm});
    } else {
      await bizRef.update({
        attendancePolicyConfirmation:
          lib.admin.firestore.FieldValue.delete(),
      });
    }
    const back = (await bizRef.get()).data();
    console.log('\n기준 원복: grace', back.attendanceRules.lateGrace,
      '/ lateUnit', back.attendanceRules.lateUnit,
      back.attendanceRules.lateUnit === original.lateUnit ?
        '(확인)' : '(**불일치**)');
    console.log('확인 원복:',
      back.attendancePolicyConfirmation == null ? '(없음 — 원래 상태)' : '있음');
  }
  process.exit(0);
})().catch((e) => { console.error('실패:', e.message); process.exit(1); });
