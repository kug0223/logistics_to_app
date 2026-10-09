/**
 * [R7-PAYROLL-POLICY.4A §37·§38·§39] DEV 런타임.
 *
 *   §37 mismatch:
 *     A. 기준 A · 미확인 상태로 공고를 열어 둔다(기존 열린 공고 재현)
 *     B. 근로자 지원 → snapshot A
 *     C. 기준 B 로 변경 + B 확인
 *     D. 확정 시도 → APPLICATION_POLICY_NOT_ACKNOWLEDGED
 *     E. 지원서 기준 확인(callableAcknowledgeApplicationPolicy) → 확정 성공
 *        · snapshot 은 A 그대로 (덮이지 않는다)
 *        · 확인 기록은 A 의 7개 숫자 + 실제 actor + 서버 시각
 *     F. 같은 공고에 **새로** 지원하면 snapshot B (현재 기준)
 *     G. snapshot == 현재 확인 기준이면 추가 확인 없이 확정된다
 *
 *   §38 offer:
 *     H. 기준 B 확인 상태에서 대체근무 제안 → target snapshot B + 확인 기록
 *     I. 기준 C 로 변경 + C 확인 → 근로자 수락 → target 은 **B 그대로**
 *
 *   §39 기존 확정 근무는 막히지 않는다 (출근 성공 확인)
 *
 *   사업장 기준 값 변경만 Admin SDK 직접 쓰기다(테스트 설정). 확인·지원·
 *   확정·제안·수락·출근은 모두 canonical callable 이고, 확인 기록
 *   (`attendancePolicyConfirmation` / `attendancePolicyAcknowledgement`)은
 *   이 스크립트가 쓰지 않는다.
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

const F = ['earlyWindow', 'earlyArrivalUnit', 'lateGrace', 'lateUnit',
  'lateWindow', 'overtimeUnit', 'earlyLeaveUnit'];
const brief = (o) => o == null ? '(없음)' :
  `grace ${o.lateGrace}/unit ${o.lateUnit}/early ${o.earlyLeaveUnit}/ot ${o.overtimeUnit}`;
const sameNums = (a, b) => a != null && b != null && F.every((k) => a[k] === b[k]);
const reasonOf = (e) => {
  const d = e && e.details;
  if (d && d.reason) return d.reason;
  const m = String((e && e.message) || e);
  const mm = m.match(/POSTING_NOT_READY:([A-Z_]+)/);
  return mm ? mm[1] : m.slice(0, 90);
};

const POLICY_A = {lateGrace: 5, lateUnit: 30, earlyLeaveUnit: 30, overtimeUnit: 30};
const POLICY_B = {lateGrace: 10, lateUnit: 10, earlyLeaveUnit: 10, overtimeUnit: 10};
const POLICY_C = {lateGrace: 3, lateUnit: 20, earlyLeaveUnit: 20, overtimeUnit: 20};

async function setRules(p) {
  const upd = {};
  for (const k of Object.keys(p)) upd[`attendanceRules.${k}`] = p[k];
  await bizRef.update(upd);
}
async function clearConfirmation() {
  await bizRef.update({
    attendancePolicyConfirmation: lib.admin.firestore.FieldValue.delete(),
  });
}
async function confirmPolicy() {
  await lib.callAs(adminUid, 'callableConfirmAttendancePolicy', {businessId});
}

/** 지정 offset 분 뒤 시작하는 2업무 1분 근무 TO + 슬롯을 만든다. */
async function makeTO(label, startOffsetMin, {twoWorkDetails = false} = {}) {
  const nowKst = new Date(Date.now() + KST);
  const dateStr = lib.kstDateKey(0);
  const workDateMs = lib.kstMidnightMs(0);
  const sM = nowKst.getUTCHours() * 60 + nowKst.getUTCMinutes() + startOffsetMin;
  const START = `${pad(Math.floor(sM / 60))}:${pad(sM % 60)}`;
  const END = `${pad(Math.floor((sM + 1) / 60))}:${pad((sM + 1) % 60)}`;
  const biz = (await bizRef.get()).data();
  const wts = (await bizRef.collection('workTypes').limit(2).get()).docs;
  const mk = (i) => ({
    wdId: `p4a-${label}-${i}`,
    workType: (wts[Math.min(i, wts.length - 1)].data()).name,
    workTypeIcon: 'box', workTypeColor: '#1565C0',
    workTypeBackgroundColor: '#E3F2FD',
    wage: 12000 + i * 1000, wageType: 'hourly', requiredCount: 1,
    startTime: START, endTime: END, order: i, payScheduleType: 'next_day',
  });
  const wds = twoWorkDetails ? [mk(0), mk(1)] : [mk(0)];
  const created = unwrap(await lib.callAs(adminUid, 'callableCreateTO', {
    toData: {
      businessId, businessName: biz.name, title: `[P4A-${label}] 확인 증거`,
      description: 'R7-PAYROLL-POLICY.4A 전용. 실제 모집 아님.',
      type: 'flex', workDetails: wds, creatorUID: adminUid,
      totalRequired: wds.length, totalConfirmed: 0, totalPending: 0,
      status: 'active', deadlineType: 'FIXED_TIME', hoursBeforeStart: 1,
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
  const slotId = slots.docs[0].id;
  const slotWds = (slots.docs[0].data().workDetails || []);
  const to = (await db.collection('tos').doc(toId).get()).data();
  return {toId, slotId, slotWds, to, workDateMs, START, END};
}

async function apply(uid, T, wdIndex) {
  const wd = T.slotWds[wdIndex];
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
    // 오늘 비어 있는 근로자 2명
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

    // ── §37 A. 기준 A 확인 상태에서 공고를 열어 둔다 ────────────
    //    (공고 생성 자체는 확인된 기준에서만 된다 — `.4` gate)
    await setRules(POLICY_A);
    await confirmPolicy();
    console.log('═══ §37 A. 기준 A 확인 · 공고 개설 ═══');
    console.log('  기준 A:', brief((await bizRef.get()).data().attendanceRules));
    const T1 = await makeTO('mismatch', 4, {twoWorkDetails: true});
    createdTOIds.push(T1.toId);

    // 그 뒤 확인만 지운다 — "기존 열린 공고 + 미확인 기준" 상태 재현
    await clearConfirmation();
    console.log('  확인 기록 제거 → 기존 열린 공고 + 미확인 기준 상태');

    // ── B. 근로자 지원 (§6 도달성) ─────────────────────────────
    const appA = await apply(uidA, T1, 0);
    const a0 = await appDoc(appA);
    console.log('\n═══ §6·B. 미확인 기준에서 지원 ═══');
    console.log('  지원 성공 · snapshot:', brief(a0.attendancePolicySnapshot));
    console.log('  확인 기록:', a0.attendancePolicyAcknowledgement == null ?
      '(없음 — 직접 지원이므로 정상)' : '**있다**');

    // ── C. 기준 B 로 변경 + B 확인 ─────────────────────────────
    await setRules(POLICY_B);
    await confirmPolicy();
    const bizB = (await bizRef.get()).data();
    console.log('\n═══ §37 C. 기준 B 로 변경 + B 확인 ═══');
    console.log('  사업장 기준 B:', brief(bizB.attendanceRules));
    console.log('  사업장 확인  :', brief(bizB.attendancePolicyConfirmation));

    // ── D. 확정 시도 → mismatch 감지 ───────────────────────────
    await reviewDocs(appA);
    console.log('\n═══ §37 D. 확정 시도 ═══');
    try {
      await lib.callAs(adminUid, 'callableConfirmApplication',
        {applicationId: appA, businessId});
      console.log('  **통과했다 — B 의 확인이 A 의 확인으로 쓰였다**');
    } catch (e) {
      console.log('  차단 reason =', reasonOf(e));
    }
    const a1 = await appDoc(appA);
    console.log('  차단 후 snapshot:', brief(a1.attendancePolicySnapshot),
      sameNums(a1.attendancePolicySnapshot, a0.attendancePolicySnapshot) ?
        '(A 그대로 — 덮이지 않았다)' : '(**바뀌었다**)');

    // ── E. 지원서 기준 확인 → 확정 성공 ────────────────────────
    console.log('\n═══ §37 E. 지원 당시 기준 확인 후 확정 ═══');
    const ackRes = unwrap(await lib.callAs(adminUid,
      'callableAcknowledgeApplicationPolicy',
      {applicationId: appA, businessId}));
    console.log('  확인 응답:', JSON.stringify(ackRes));
    const a2 = await appDoc(appA);
    const ack = a2.attendancePolicyAcknowledgement;
    console.log('  확인 기록:', brief(ack),
      '· by =', ack.acknowledgedBy === adminUid ? '실제 호출자 일치' : '**불일치**',
      '· at =', ack.acknowledgedAt ? '있음' : '**없음**');
    console.log('  A 의 숫자를 확인했는가:',
      sameNums(ack, a0.attendancePolicySnapshot) ? '예' : '**아니오**');
    await lib.callAs(adminUid, 'callableConfirmApplication',
      {applicationId: appA, businessId});
    const a3 = await appDoc(appA);
    console.log('  확정 성공 · status =', a3.status);
    console.log('  확정 후 snapshot:', brief(a3.attendancePolicySnapshot),
      sameNums(a3.attendancePolicySnapshot, a0.attendancePolicySnapshot) ?
        '(A 그대로 — 소급변경 없음)' : '(**바뀌었다**)');

    // ── F. 새 지원은 현재 기준 B ───────────────────────────────
    console.log('\n═══ §33-9·F. 변경 후 신규 지원 ═══');
    const appB = await apply(uidB, T1, 1);
    const b0 = await appDoc(appB);
    console.log('  신규 snapshot:', brief(b0.attendancePolicySnapshot),
      sameNums(b0.attendancePolicySnapshot, bizB.attendanceRules) ?
        '(현재 기준 B)' : '(**현재 기준이 아니다**)');

    // ── G. snapshot == 현재 확인 기준 → 추가 확인 없이 확정 ────
    console.log('\n═══ §33-10·G. 일치하면 추가 확인 없이 확정 ═══');
    await reviewDocs(appB);
    await lib.callAs(adminUid, 'callableConfirmApplication',
      {applicationId: appB, businessId});
    const b1 = await appDoc(appB);
    console.log('  확정 성공 · status =', b1.status,
      '· 지원서 확인 기록 =',
      b1.attendancePolicyAcknowledgement == null ?
        '(없음 — 사업장 확인으로 증명됨)' : '있음');

    // ── §38 H. 대체근무 제안 — 제안 시점 기준 고정 ─────────────
    console.log('\n═══ §38 H. 대체근무 제안 (기준 B) ═══');
    const T2 = await makeTO('offer', 7, {twoWorkDetails: true});
    createdTOIds.push(T2.toId);
    const srcApp = await apply(uidA, T2, 0);
    const offerTargetWdId = T2.slotWds[1].wdId;
    await lib.callAs(adminUid, 'callableOfferAlternativeWork', {
      sourceApplicationId: srcApp, targetWdId: offerTargetWdId,
      compensationOption: 'TARGET_BASE',
    });
    // 제안으로 생긴 INVITED target 을 찾는다.
    const invSnap = await db.collection('applications')
      .where('uid', '==', uidA).where('toId', '==', T2.toId)
      .where('status', '==', 'INVITED').get();
    const targetId = invSnap.docs[0].id;
    const t0 = await appDoc(targetId);
    console.log('  target snapshot:', brief(t0.attendancePolicySnapshot));
    console.log('  target 확인 기록:', brief(t0.attendancePolicyAcknowledgement),
      '· by =', t0.attendancePolicyAcknowledgement?.acknowledgedBy === adminUid ?
        '제안한 관리자' : '**불일치**');

    // ── I. 기준 C 로 변경 + C 확인 → 수락 → target 은 B 그대로 ─
    await setRules(POLICY_C);
    await confirmPolicy();
    console.log('\n═══ §38 I. 기준 C 로 변경 후 근로자 수락 ═══');
    console.log('  사업장 기준 C:', brief((await bizRef.get()).data().attendanceRules));
    await reviewDocs(targetId);
    await lib.callAs(uidA, 'callableAcceptTOInvitation', {
      applicationId: targetId,
      documentAccessConsentGiven: true,
      documentAccessConsentVersion: CONSENT,
    });
    const t1 = await appDoc(targetId);
    console.log('  수락 후 status =', t1.status);
    console.log('  수락 후 snapshot:', brief(t1.attendancePolicySnapshot),
      sameNums(t1.attendancePolicySnapshot, t0.attendancePolicySnapshot) ?
        '(제안 시점 B 그대로 — drift 없음)' : '(**live C 로 덮였다**)');

    // ── §39 기존 확정 근무는 막히지 않는다 ─────────────────────
    console.log('\n═══ §39. 미확인 상태에서도 기존 약속의 출근은 된다 ═══');
    await clearConfirmation();
    const bizF = (await bizRef.get()).data();
    try {
      const ci = unwrap(await lib.callAs(uidB, 'callableCheckIn', {
        applicationId: appB, businessId, businessName: bizF.name,
        workDateMs: T1.workDateMs, workType: T1.slotWds[1].workType,
        method: 'gps', latitude: bizF.latitude, longitude: bizF.longitude,
        scheduledStartTime: T1.START,
      }));
      const att = (await db.collection('attendance').doc(ci.attendanceId).get())
        .data();
      const t = (v) => v && v.toMillis ?
        new Date(v.toMillis() + KST).toISOString().slice(11, 16) : '(없음)';
      console.log('  출근 성공: 원본', t(att.originalCheckIn),
        '→ 적용', t(att.checkIn), '| status', att.status);
      console.log('  적용 기준: snapshot grace',
        b1.attendancePolicySnapshot.lateGrace,
        '/ 사업장 현재 grace', bizF.attendanceRules.lateGrace);
    } catch (e) {
      console.log('  출근 **차단됐다 — 기존 약속 이행이 막혔다**:', reasonOf(e));
    }
    // 반대로 새 제안은 막혀야 한다 (§21)
    try {
      await lib.callAs(adminUid, 'callableOfferAlternativeWork', {
        sourceApplicationId: srcApp, targetWdId: offerTargetWdId,
        compensationOption: 'TARGET_BASE',
      });
      console.log('  새 제안: **통과했다 — gate 미작동**');
    } catch (e) {
      console.log('  새 제안 차단 reason =', reasonOf(e));
    }

    fs.writeFileSync('.p4afixture.json', JSON.stringify({
      businessId, adminUid, uidA, uidB, appA, appB, targetId, srcApp,
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
    // 테스트 공고 정리 — 오너 활성 공고 한도를 비워 둔다.
    for (const toId of createdTOIds) {
      try {
        await lib.callAs(adminUid, 'callableCloseTOManually', {toId, businessId});
      } catch (e) { console.log('  공고 정리 실패', toId, e.message); }
    }
    const back = (await bizRef.get()).data();
    console.log('\n기준 원복:', brief(back.attendanceRules),
      sameNums(back.attendanceRules, originalRules) ? '(확인)' : '(**불일치**)');
    console.log('확인 원복:',
      back.attendancePolicyConfirmation == null ? '(없음 — 원래 상태)' : '있음');
  }
  process.exit(0);
})().catch((e) => { console.error('실패:', e.message); process.exit(1); });
