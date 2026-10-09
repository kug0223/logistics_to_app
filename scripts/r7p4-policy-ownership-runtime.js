/**
 * [R7-PAYROLL-POLICY.4 §55·§56] DEV 런타임 — 확인 증거 + 지원 시점 snapshot.
 *
 *   A. 사업장 미확인 상태 → **새 약속 차단** 확인
 *   B. 관리자 확인(기본값 그대로) → policySource 유지 + actor/time 기록
 *   C. Worker 1 지원(정책 A) → snapshot A
 *   D. 정책 B 로 변경 → **미확인으로 떨어짐** → 확인 → Worker 1 확정
 *        → snapshot 은 **A 그대로** (지원 당시 조건 유지)
 *   E. Worker 2 신규 지원/확정 → snapshot B (A 와 다름)
 *   F. 기존 확정 근무의 출근은 그대로 된다(§56)
 *
 *   사업장 정책 값 변경은 테스트 설정이므로 Admin SDK 로 직접 쓰고 끝에
 *   원복한다(보고에 그대로 적는다). 확인·지원·확정·출근은 모두 canonical
 *   callable 이다. 확인 기록(`attendancePolicyConfirmation`)은 CF 만 쓴다 —
 *   이 스크립트도 직접 쓰지 않는다.
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

const FIELDS = ['earlyWindow', 'earlyArrivalUnit', 'lateGrace', 'lateUnit',
  'lateWindow', 'overtimeUnit', 'earlyLeaveUnit'];

const showRules = (r) => r == null ? '(없음)' :
  FIELDS.map((k) => `${k}=${r[k]}`).join(' ') +
  ` · source=${r.policySource ?? '(없음→legacy)'}`;

const showCfm = (c) => c == null ? '(없음)' :
  FIELDS.map((k) => `${k}=${c[k]}`).join(' ') +
  ` · by=${c.confirmedBy ? c.confirmedBy.slice(0, 6) + '…' : '(없음)'}` +
  ` · at=${c.confirmedAt ? '있음' : '(없음)'}`;

/** 지정 offset 분 뒤 시작하는 1분 근무를 만들고 지원까지. 확정은 호출자가. */
async function makeApplication(uid, startOffsetMin, label) {
  const nowKst = new Date(Date.now() + KST);
  const dateStr = lib.kstDateKey(0);
  const workDateMs = lib.kstMidnightMs(0);
  const sM = nowKst.getUTCHours() * 60 + nowKst.getUTCMinutes() + startOffsetMin;
  const START = `${pad(Math.floor(sM / 60))}:${pad(sM % 60)}`;
  const END = `${pad(Math.floor((sM + 1) / 60))}:${pad((sM + 1) % 60)}`;
  const biz = (await bizRef.get()).data();
  const wt = (await bizRef.collection('workTypes').limit(1).get()).docs[0].data();
  const wd = {
    wdId: `p4-${label}`, workType: wt.name,
    workTypeIcon: wt.icon ?? 'box', workTypeColor: wt.color ?? '#1565C0',
    workTypeBackgroundColor: wt.backgroundColor ?? '#E3F2FD',
    wage: 12000, wageType: 'hourly', requiredCount: 1,
    startTime: START, endTime: END, order: 0, payScheduleType: 'next_day',
  };
  const created = unwrap(await lib.callAs(adminUid, 'callableCreateTO', {
    toData: {
      businessId, businessName: biz.name, title: `[P4-${label}] 기준 확인`,
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
  return {applicationId, toId, slotId, wdId, workDateMs, START, END,
    workType: wd.workType, dateStr};
}

const reason = (e) => {
  const d = e && e.details;
  if (d && d.reason) return d.reason;
  const m = String((e && e.message) || e);
  const mm = m.match(/POSTING_NOT_READY:([A-Z_]+)/);
  return mm ? mm[1] : m.slice(0, 90);
};

(async () => {
  const biz0 = (await bizRef.get()).data();
  const original = biz0.attendanceRules;
  const originalCfm = biz0.attendancePolicyConfirmation ?? null;
  console.log('원래 기준 :', showRules(original));
  console.log('원래 확인 :', showCfm(originalCfm));

  try {
    // ── A. 미확인 상태를 만든다(확인 기록 제거 + 기준 A) ──────────
    await bizRef.update({
      'attendanceRules.lateGrace': 5,
      'attendanceRules.lateUnit': 30,
      'attendanceRules.earlyLeaveUnit': 30,
      'attendanceRules.overtimeUnit': 30,
      attendancePolicyConfirmation:
        lib.admin.firestore.FieldValue.delete(),
    });
    console.log('\n═══ A. 미확인 상태 — 새 약속 차단 ═══');

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

    // 공고 생성 자체가 막히는지 — readiness gate
    try {
      await makeApplication(uidA, 3, 'blocked');
      console.log('  공고 생성 : **통과했다 — gate 미작동**');
    } catch (e) {
      console.log('  공고 생성 차단 reason =', reason(e));
    }

    // ── B. 관리자 확인 — 기본값/현재값 그대로 ───────────────────
    console.log('\n═══ B. 관리자 확인(값 변경 없음) ═══');
    const cfmRes = unwrap(await lib.callAs(adminUid,
      'callableConfirmAttendancePolicy', {businessId}));
    console.log('  응답 :', JSON.stringify(cfmRes));
    let bizNow = (await bizRef.get()).data();
    console.log('  기준 :', showRules(bizNow.attendanceRules));
    console.log('  확인 :', showCfm(bizNow.attendancePolicyConfirmation));
    console.log('  출처 유지 :',
      (bizNow.attendanceRules.policySource ?? '(없음)') ===
      (original.policySource ?? '(없음)') ? '예' : '**아니오**');
    console.log('  actor 일치 :',
      bizNow.attendancePolicyConfirmation.confirmedBy === adminUid ?
        '예' : '**아니오**');

    // ── C. Worker 1 지원 — 정책 A ───────────────────────────────
    console.log('\n═══ C. Worker 1 지원 (정책 A) ═══');
    const A = await makeApplication(uidA, 3, 'A');
    const appA0 = (await db.collection('applications').doc(A.applicationId)
      .get()).data();
    console.log('  지원 시점 snapshot :',
      showRules(appA0.attendancePolicySnapshot));

    // ── D. 정책 B 로 변경 → 미확인 → 확인 → Worker 1 확정 ───────
    console.log('\n═══ D. 정책 B(10/10) 변경 ═══');
    await bizRef.update({
      'attendanceRules.lateGrace': 10,
      'attendanceRules.lateUnit': 10,
      'attendanceRules.earlyLeaveUnit': 10,
      'attendanceRules.overtimeUnit': 10,
    });
    try {
      await lib.callAs(adminUid, 'callableConfirmApplication',
        {applicationId: A.applicationId, businessId});
      console.log('  변경 직후 확정 : **통과했다 — 낡은 확인이 재사용됐다**');
    } catch (e) {
      console.log('  변경 직후 확정 차단 reason =', reason(e));
    }
    await lib.callAs(adminUid, 'callableConfirmAttendancePolicy', {businessId});
    await lib.callAs(adminUid, 'callableConfirmApplication',
      {applicationId: A.applicationId, businessId});
    const appA1 = (await db.collection('applications').doc(A.applicationId)
      .get()).data();
    console.log('  확정 후 snapshot   :',
      showRules(appA1.attendancePolicySnapshot));
    console.log('  지원 당시와 동일   :',
      FIELDS.every((k) => appA1.attendancePolicySnapshot[k] ===
        appA0.attendancePolicySnapshot[k]) ? '예 (소급 없음)' : '**아니오**');
    bizNow = (await bizRef.get()).data();
    console.log('  사업장 현재 기준   :', showRules(bizNow.attendanceRules));

    // ── E. Worker 2 신규 지원/확정 → 새 기준 ────────────────────
    console.log('\n═══ E. Worker 2 신규 지원/확정 (정책 B) ═══');
    const B = await makeApplication(uidB, 4, 'B');
    const appB0 = (await db.collection('applications').doc(B.applicationId)
      .get()).data();
    await lib.callAs(adminUid, 'callableConfirmApplication',
      {applicationId: B.applicationId, businessId});
    const appB1 = (await db.collection('applications').doc(B.applicationId)
      .get()).data();
    console.log('  B snapshot :', showRules(appB1.attendancePolicySnapshot));
    console.log('  지원 시점과 동일 :',
      FIELDS.every((k) => appB1.attendancePolicySnapshot[k] ===
        appB0.attendancePolicySnapshot[k]) ? '예' : '**아니오**');
    console.log('  A 와 다른가 :',
      appB1.attendancePolicySnapshot.lateUnit !==
      appA1.attendancePolicySnapshot.lateUnit ? '예' : '**아니오**');

    // ── F. §56 기존 확정 근무 운영 무중단 ───────────────────────
    console.log('\n═══ F. 미확인 상태에서도 기존 약속의 출근은 된다 ═══');
    await bizRef.update({
      attendancePolicyConfirmation:
        lib.admin.firestore.FieldValue.delete(),
    });
    const bizF = (await bizRef.get()).data();
    try {
      const ci = unwrap(await lib.callAs(uidA, 'callableCheckIn', {
        applicationId: A.applicationId, businessId,
        businessName: bizF.name, workDateMs: A.workDateMs,
        workType: A.workType, method: 'gps',
        latitude: bizF.latitude, longitude: bizF.longitude,
        scheduledStartTime: A.START,
      }));
      const att = (await db.collection('attendance').doc(ci.attendanceId).get())
        .data();
      const t = (v) => v && v.toMillis ?
        new Date(v.toMillis() + KST).toISOString().slice(11, 16) : '(없음)';
      console.log('  출근 성공 : 원본', t(att.originalCheckIn),
        '→ 적용', t(att.checkIn), '| status', att.status);
      console.log('  적용 기준 : snapshot lateGrace =',
        appA1.attendancePolicySnapshot.lateGrace,
        '/ 사업장 현재 =', bizF.attendanceRules.lateGrace);
    } catch (e) {
      console.log('  출근 **차단됐다 — 기존 약속 이행이 막혔다**:', reason(e));
    }
    // 반대로 새 확정은 막혀야 한다
    try {
      const C = await makeApplication(uidB, 6, 'C');
      await lib.callAs(adminUid, 'callableConfirmApplication',
        {applicationId: C.applicationId, businessId});
      console.log('  새 확정 : **통과했다 — gate 미작동**');
    } catch (e) {
      console.log('  새 확정 차단 reason =', reason(e));
    }

    fs.writeFileSync('.p4fixture.json', JSON.stringify({
      businessId, adminUid, uidA, uidB,
      appA: A.applicationId, appB: B.applicationId,
      workDateMs, startA: A.START,
    }, null, 2));
  } finally {
    await bizRef.update({attendanceRules: original});
    if (originalCfm != null) {
      // 원래 확인 기록이 있었으면 그대로 되돌린다(CF 가 쓴 값이다).
      await bizRef.update({attendancePolicyConfirmation: originalCfm});
    } else {
      await bizRef.update({
        attendancePolicyConfirmation: lib.admin.firestore.FieldValue.delete(),
      });
    }
    const back = (await bizRef.get()).data();
    console.log('\n기준 원복 :', showRules(back.attendanceRules));
    console.log('확인 원복 :', showCfm(back.attendancePolicyConfirmation));
  }
  process.exit(0);
})().catch((e) => { console.error('실패:', e.message); process.exit(1); });
