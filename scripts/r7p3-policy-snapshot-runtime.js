/**
 * [R7-PAYROLL-POLICY.3 §38] 정책 snapshot — DEV 런타임 시나리오 A/B/C.
 *
 *   A. 사업장 정책 5/30 → worker A 확정 → snapshot 5/30
 *   B. 사업장 정책을 10/10 으로 변경 → worker A 출근 → **5/30 적용**
 *   C. worker B 신규 확정 → snapshot 10/10
 *
 *   사업장 정책 변경은 테스트 설정이므로 Admin SDK 로 직접 쓰고 끝에 원복한다
 *   (보고에 그대로 적는다). 확정·출근은 모두 canonical callable 이다.
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

/** 지정 시각에 시작하는 1분 근무를 canonical 흐름으로 만들고 확정까지. */
async function makeConfirmed(uid, startOffsetMin, label) {
  const nowKst = new Date(Date.now() + KST);
  const dateStr = lib.kstDateKey(0);
  const workDateMs = lib.kstMidnightMs(0);
  const sM = nowKst.getUTCHours() * 60 + nowKst.getUTCMinutes() + startOffsetMin;
  const START = `${pad(Math.floor(sM / 60))}:${pad(sM % 60)}`;
  const END = `${pad(Math.floor((sM + 1) / 60))}:${pad((sM + 1) % 60)}`;
  const biz = (await bizRef.get()).data();
  const wt = (await bizRef.collection('workTypes').limit(1).get())
    .docs[0].data();
  const wd = {
    wdId: `p3-${label}`, workType: wt.name,
    workTypeIcon: wt.icon ?? 'box', workTypeColor: wt.color ?? '#1565C0',
    workTypeBackgroundColor: wt.backgroundColor ?? '#E3F2FD',
    wage: 12000, wageType: 'hourly', requiredCount: 1,
    startTime: START, endTime: END, order: 0, payScheduleType: 'next_day',
  };
  const created = unwrap(await lib.callAs(adminUid, 'callableCreateTO', {
    toData: {
      businessId, businessName: biz.name, title: `[P3-${label}] 정책 snapshot`,
      description: 'R7-PAYROLL-POLICY.3 전용. 실제 모집 아님.',
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
    fixedDeadlineMs: Date.now() + 60000, publishMode: 'immediate',
  });
  try { await lib.callAs(adminUid, 'callablePublishTO', {toId}); } catch (_) {}
  const slots = await db.collection('tos').doc(toId).collection('slots').get();
  const slotId = slots.docs[0].id;
  const wdId = ((slots.docs[0].data().workDetails || [])[0] || {}).wdId;
  const to = (await db.collection('tos').doc(toId).get()).data();

  const ap = unwrap(await lib.callAs(uid, 'callableApplyToTO', {
    toId, slotId, businessId, businessName: to.businessName, toTitle: to.title,
    workDateMs, selectedWorkType: wd.workType, workDetailId: wdId,
    startTime: START, endTime: END, wage: wd.wage, wageType: 'hourly',
    idCardConsentGiven: true, documentAccessConsentGiven: true,
    documentAccessConsentVersion: CONSENT,
  }));
  const applicationId = ap.applicationId;
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
  return {applicationId, toId, slotId, wdId, workDateMs, START, END,
    workType: wd.workType, dateStr};
}

const show = (s) => s == null ? '(없음)' :
  `grace ${s.lateGrace} / lateUnit ${s.lateUnit} / earlyLeave ${s.earlyLeaveUnit}` +
  ` / overtime ${s.overtimeUnit} · source=${s.policySource}` +
  ` · capturedAt=${s.capturedAt ? '있음' : '없음'}`;

(async () => {
  const biz0 = (await bizRef.get()).data();
  const original = biz0.attendanceRules;
  console.log('원래 정책:', JSON.stringify({
    lateGrace: original.lateGrace, lateUnit: original.lateUnit,
    earlyLeaveUnit: original.earlyLeaveUnit, overtimeUnit: original.overtimeUnit,
    policySource: original.policySource ?? '(없음 → legacy)',
  }));

  try {
    // ── A. 5/30 으로 두고 worker A 확정 ───────────────────────
    await bizRef.update({
      'attendanceRules.lateGrace': 5,
      'attendanceRules.lateUnit': 30,
      'attendanceRules.earlyLeaveUnit': 30,
      'attendanceRules.overtimeUnit': 30,
      'attendanceRules.policySource': 'admin_selected',
    });
    const users = await db.collection('users').where('role', '==', 'USER').get();
    const workDateMs = lib.kstMidnightMs(0);
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

    console.log('\n═══ A. 정책 5/30 · worker A 확정 ═══');
    const A = await makeConfirmed(uidA, 3, 'A');
    const appA1 = (await db.collection('applications').doc(A.applicationId)
      .get()).data();
    console.log('  A snapshot:', show(appA1.attendancePolicySnapshot));

    // 재확정(멱등) — snapshot 이 바뀌면 안 된다 (§29)
    await lib.callAs(adminUid, 'callableConfirmApplication',
      {applicationId: A.applicationId, businessId});
    const appA2 = (await db.collection('applications').doc(A.applicationId)
      .get()).data();
    console.log('  재확정 후 동일:',
      JSON.stringify(appA1.attendancePolicySnapshot) ===
      JSON.stringify(appA2.attendancePolicySnapshot) ? '예' : '**아니오**');

    // ── B. 정책을 10/10 으로 바꾼 뒤 worker A 출근 ────────────
    await bizRef.update({
      'attendanceRules.lateGrace': 10,
      'attendanceRules.lateUnit': 10,
      'attendanceRules.earlyLeaveUnit': 10,
      'attendanceRules.overtimeUnit': 10,
    });
    console.log('\n═══ B. 정책을 10/10 으로 변경 · worker A 출근 ═══');
    const ci = unwrap(await lib.callAs(uidA, 'callableCheckIn', {
      applicationId: A.applicationId, businessId,
      businessName: biz0.name, workDateMs: A.workDateMs,
      workType: A.workType, method: 'gps',
      latitude: biz0.latitude, longitude: biz0.longitude,
      scheduledStartTime: A.START,
    }));
    const att = (await db.collection('attendance').doc(ci.attendanceId).get())
      .data();
    const t = (v) => v && v.toMillis ?
      new Date(v.toMillis() + KST).toISOString().slice(11, 16) : '(없음)';
    // 출근은 START 3분 전이다. grace 5 면 정시(START), grace 10 이어도 정시다.
    //   구분되는 지점은 **지각 반올림 단위**이므로 그 값을 직접 확인한다.
    console.log('  출근 원본:', t(att.originalCheckIn),
      '→ 적용:', t(att.checkIn), '| status:', att.status);
    console.log('  이 근무가 쓴 snapshot:',
      show(appA2.attendancePolicySnapshot));
    const live = (await bizRef.get()).data().attendanceRules;
    console.log('  현재 live 정책     : lateUnit', live.lateUnit,
      '/ grace', live.lateGrace,
      live.lateUnit !== appA2.attendancePolicySnapshot.lateUnit ?
        '← snapshot 과 다르다 (소급되지 않았다)' : '');

    // ── C. worker B 신규 확정 → 새 정책 ──────────────────────
    console.log('\n═══ C. worker B 신규 확정 ═══');
    const C = await makeConfirmed(uidB, 4, 'C');
    const appC = (await db.collection('applications').doc(C.applicationId)
      .get()).data();
    console.log('  B snapshot:', show(appC.attendancePolicySnapshot));
    console.log('  A 와 다른가:',
      appC.attendancePolicySnapshot.lateUnit !==
      appA2.attendancePolicySnapshot.lateUnit ? '예' : '**아니오**');

    fs.writeFileSync('.p3fixture.json', JSON.stringify({
      businessId, adminUid, uidA, uidB,
      appA: A.applicationId, appC: C.applicationId,
      attendanceA: ci.attendanceId,
      startA: A.START, endA: A.END, workDateMs: A.workDateMs,
    }, null, 2));
  } finally {
    await bizRef.update({attendanceRules: original});
    const back = (await bizRef.get()).data().attendanceRules;
    console.log('\n정책 원복: lateUnit', back.lateUnit,
      '/ grace', back.lateGrace,
      back.lateUnit === original.lateUnit ? '(확인)' : '(**불일치**)');
  }
  process.exit(0);
})().catch((e) => { console.error('실패:', e.message); process.exit(1); });
