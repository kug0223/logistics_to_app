/**
 * [R7-PAYROLL-POLICY.4B §44] 확정 재배치 DEV 런타임.
 *
 *   `.4A` 에서 미제출이었다. 확정(CONFIRMED)을 만들려면 계약 서명까지 필요해
 *   보였지만, **초대 수락은 CONFIRMED 를 직접 만든다** — 계약 fixture 없이
 *   재배치 전제조건을 만들 수 있다.
 *
 *   절차:
 *     1. 사업장 기준 A 확인 → 업무 2개인 공고/슬롯 생성
 *     2. 근로자를 wd0 에 **초대** → 수락 → CONFIRMED (snapshot A + 확인 기록)
 *     3. 사업장 기준을 C 로 변경하고 확인
 *     4. wd1 로 재배치 제안 → 근로자 수락
 *     5. 결과 지원서 B 의 기준이 **A 그대로**인지(현재 C 가 아닌지) 확인
 */
'use strict';
const fs = require('fs');
const lib = require('./r7-fixture-lib');
const {db} = lib;
const unwrap = (r) => (r && (r.result ?? r.data)) ?? r;
const CONSENT = '2026-09-18-v3';
const KST = 9 * 3600000;
const pad = (n) => String(n).padStart(2, '0');
const DAY = 1; // 내일 — 오늘은 이미 확정된 근로자가 많다

const G = JSON.parse(fs.readFileSync('.goldenpath.json', 'utf8'));
const businessId = G.businessId;
const adminUid = G.adminUid;
const bizRef = db.collection('businesses').doc(businessId);

const F = ['earlyWindow', 'earlyArrivalUnit', 'lateGrace', 'lateUnit',
  'lateWindow', 'overtimeUnit', 'earlyLeaveUnit'];
const brief = (o) => o == null ? '(없음)' :
  `grace ${o.lateGrace}/unit ${o.lateUnit}/early ${o.earlyLeaveUnit}/ot ${o.overtimeUnit}`;
const same7 = (a, b) => a != null && b != null && F.every((k) => a[k] === b[k]);
const reasonOf = (e) => {
  const d = e && e.details;
  if (d && d.reason) return d.reason;
  return String((e && e.code) || '') + ' ' +
    String((e && e.message) || e).slice(0, 110);
};

const A = {lateGrace: 5, lateUnit: 30, earlyLeaveUnit: 30, overtimeUnit: 30};
const C = {lateGrace: 3, lateUnit: 20, earlyLeaveUnit: 20, overtimeUnit: 20};

async function setRules(p) {
  const upd = {};
  for (const k of Object.keys(p)) upd[`attendanceRules.${k}`] = p[k];
  await bizRef.update(upd);
}
const confirmPolicy = () =>
  lib.callAs(adminUid, 'callableConfirmAttendancePolicy', {businessId});
const appDoc = (id) =>
  db.collection('applications').doc(id).get().then((d) => d.data());

// 1x1 투명 PNG / 최소 유효 PDF — 실제 인감·계약서 이미지를 쓰지 않는다.
const PNG_1PX = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4' +
  '2mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==';
const PDF_MIN = Buffer.from(
  '%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n' +
  '2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n' +
  '3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 595 842]>>endobj\n' +
  'trailer<</Root 1 0 R>>\n%%EOF\n', 'utf8').toString('base64');

/**
 * 계약 쌍방 서명으로 CONTRACT_PENDING → CONFIRMED.
 *
 *   `contractData` 는 제품에서 Dart `ContractService` 가 만든다. 이 스크립트는
 *   **직렬화 형태만** 재현하고 쓰기는 canonical callable 이 한다 — 따라서
 *   Dart contract builder 자체는 이 단계에서 실행되지 않는다(정직하게 기록).
 *   근태 기준 표시는 Dart 쪽 계약이므로 CODE 로만 고정된다(DISC-12).
 */
async function signContract(applicationId, uid, wd, START, END, dateStr) {
  const biz = (await bizRef.get()).data();
  const owner = (await db.collection('users').doc(biz.ownerId).get()).data();
  const worker = (await db.collection('users').doc(uid).get()).data();
  const tplSnap = await bizRef.collection('contract_templates').limit(1).get();
  const tpl = tplSnap.docs[0];
  const articles = (tpl.data().articles || [])
    .map((a) => ({title: a.title ?? '', content: a.content ?? ''}));
  const contractId = db.collection('employment_contracts').doc().id;
  await lib.callAs(adminUid, 'callableFinalizeEmployerSignature', {
    contractId, signatureBase64: PNG_1PX, isNewUnsaved: true,
    contractData: {
      applicationId, businessId, workerId: uid, isLongTerm: false,
      toId: null, workDetailId: wd.wdId,
      slots: [{applicationId, workDate: dateStr, startTime: START,
        endTime: END, wage: wd.wage, wageType: 'hourly'}],
      applicationIds: [applicationId], pdfUrl: null, templateId: tpl.id,
      snapshot: {
        businessName: biz.name ?? '',
        businessNumber: biz.businessNumber ?? '',
        businessAddress: [biz.address, biz.detailAddress]
          .filter(Boolean).join(' '),
        businessPhone: biz.phone ?? null,
        ownerName: biz.ownerName ?? owner?.name ?? '',
        workerName: worker.name ?? '',
        workerBirthDate: null, workerPhone: worker.phone ?? null,
        workerAddress: null,
        workType: wd.workType, workPlace: biz.address ?? '',
        isLongTerm: false,
        contractStart: null, contractEnd: null, workDays: null,
        startTime: START, endTime: END, breakMinutes: 0,
        wage: wd.wage, wageType: 'hourly', wagePaymentDay: null,
        paymentMethod: '계좌이체', baseHourlyWage: null,
      },
      articles,
    },
  });
  await lib.callAs(uid, 'callableFinalizeWorkerSignature', {
    contractId, signatureBase64: PNG_1PX, pdfBase64: PDF_MIN,
  });
  return contractId;
}

(async () => {
  const biz0 = (await bizRef.get()).data();
  const originalRules = biz0.attendanceRules;
  const originalCfm = biz0.attendancePolicyConfirmation ?? null;
  let toId = null;
  let avBackup = null;

  try {
    // ── 1. 기준 A 확인 + 업무 2개 공고 ─────────────────────────
    await setRules(A);
    await confirmPolicy();
    console.log('기준 A 확인:', brief((await bizRef.get()).data().attendanceRules));

    const nowKst = new Date(Date.now() + KST);
    const dateStr = lib.kstDateKey(DAY);
    const workDateMs = lib.kstMidnightMs(DAY);
    const sM = nowKst.getUTCHours() * 60 + nowKst.getUTCMinutes() + 30;
    const START = `${pad(Math.floor(sM / 60))}:${pad(sM % 60)}`;
    const END = `${pad(Math.floor((sM + 1) / 60))}:${pad((sM + 1) % 60)}`;
    const biz = (await bizRef.get()).data();
    const wts = (await bizRef.collection('workTypes').limit(2).get()).docs;
    const mk = (i) => ({
      wdId: `p4b-ras-${i}`,
      workType: (wts[Math.min(i, wts.length - 1)].data()).name,
      workTypeIcon: 'box', workTypeColor: '#1565C0',
      workTypeBackgroundColor: '#E3F2FD',
      wage: 12000 + i * 1000, wageType: 'hourly', requiredCount: 1,
      startTime: START, endTime: END, order: i, payScheduleType: 'next_day',
    });
    const wds = [mk(0), mk(1)];
    const created = unwrap(await lib.callAs(adminUid, 'callableCreateTO', {
      toData: {
        businessId, businessName: biz.name, title: '[P4B-RAS] 재배치 상속',
        description: 'R7-PAYROLL-POLICY.4B 전용. 실제 모집 아님.',
        type: 'flex', workDetails: wds, creatorUID: adminUid,
        totalRequired: 2, totalConfirmed: 0, totalPending: 0, status: 'active',
        deadlineType: 'FIXED_TIME', hoursBeforeStart: 1,
        isPublished: false, publishMode: 'deferred',
      },
    }));
    toId = created.toId;
    await lib.callAs(adminUid, 'callableCreateFlexSlots', {
      toId, businessId, dates: [dateStr], workDetails: wds,
      deadlineType: 'FIXED_TIME', hoursBeforeStart: 1,
      fixedDeadlineMs: Date.now() + 300000, publishMode: 'immediate',
    });
    await lib.callAs(adminUid, 'callablePublishTO', {toId});
    const slots = await db.collection('tos').doc(toId).collection('slots').get();
    const slotId = slots.docs[0].id;
    const slotWds = slots.docs[0].data().workDetails || [];

    // 내일 비어 있는 근로자
    const users = await db.collection('users').where('role', '==', 'USER').get();
    let uid = null;
    for (const u of users.docs) {
      const busy = await db.collection('applications')
        .where('uid', '==', u.id)
        .where('status', 'in', ['CONFIRMED', 'CONTRACT_PENDING']).get();
      if (!busy.docs.some((d) => d.data().workDate?.toMillis() === workDateMs)) {
        uid = u.id; break;
      }
    }
    if (!uid) throw new Error('내일 비어 있는 근로자가 없다');

    // ── 2. 초대 → 수락 = CONFIRMED (계약 없음) ──────────────
    //   재배치 제안은 계약서가 발행된 근무를 거부한다(실측: "이미 근로계약서가
    //   발행된 근무입니다"). 그래서 계약 없이 CONFIRMED 가 되는 유일한 제품
    //   경로인 **초대 수락**을 쓴다.
    //
    //   초대는 근로자가 초대를 켜고 그 날짜를 가능일로 등록해야 성립한다.
    //   DEV 전원이 OFF 이므로 **canonical callable 로** 켜고, 끝에 원래 값으로
    //   되돌린다(보고에 그대로 적는다). 근로자 설정 문서를 Admin SDK 로
    //   직접 쓰지 않는다.
    const avRef = db.collection('worker_availability').doc(uid);
    avBackup = {uid, data: (await avRef.get()).data() ?? null};
    await lib.callAs(uid, 'callableSetAvailability', {dates: [dateStr]});
    await lib.callAs(uid, 'callableSetInviteRegions', {
      enabled: true,
      regions: [{province: '경기도', city: biz.city}],
    });
    console.log('\n근로자 초대 설정 ON (canonical callable) · 가능일', dateStr);

    const userDoc = (await db.collection('users').doc(uid).get()).data();
    await lib.callAs(adminUid, 'callableInviteWorker', {
      toId, slotId, businessId, targetUid: uid,
      targetName: userDoc.name ?? '근로자',
      workDate: new Date(workDateMs).toISOString(),
      startTime: START, endTime: END,
      selectedWorkType: slotWds[0].workType, workDetailId: slotWds[0].wdId,
    });
    const invSnap = await db.collection('applications')
      .where('uid', '==', uid).where('toId', '==', toId)
      .where('status', '==', 'INVITED').get();
    const srcId = invSnap.docs[0].id;
    const inv0 = await appDoc(srcId);
    console.log('초대 snapshot(A):', brief(inv0.attendancePolicySnapshot));
    console.log('초대 확인 기록 actorRole =',
      inv0.attendancePolicyAcknowledgement?.actorRole ?? '(없음)');

    const rev = unwrap(await lib.callAs(adminUid,
      'callableGetApplicantDocumentReview',
      {applicationId: srcId, businessId}));
    if (!rev.readiness.ready) {
      for (const t of ['ID', 'BANKBOOK']) {
        await lib.callAs(adminUid, 'callableReviewApplicantDocument', {
          applicationId: srcId, businessId, targetUid: rev.workerUid,
          documentType: t, decision: 'REVIEWED_OK',
          expectedVersion: t === 'ID' ? rev.versions.id : rev.versions.bankbook,
          expectedAccountVersion: rev.versions.account,
        });
      }
    }
    await lib.callAs(uid, 'callableAcceptTOInvitation', {
      applicationId: srcId,
      documentAccessConsentGiven: true,
      documentAccessConsentVersion: CONSENT,
    });
    const src = await appDoc(srcId);
    console.log('수락 후 status =', src.status,
      '· snapshot =', same7(src.attendancePolicySnapshot,
        inv0.attendancePolicySnapshot) ? 'A 그대로' : '**바뀌었다**');
    // ── 3. 사업장 기준을 C 로 ──────────────────────────────────
    await setRules(C);
    await confirmPolicy();
    console.log('\n사업장 기준 C:',
      brief((await bizRef.get()).data().attendanceRules));

    // ── 4. 재배치 제안 → 수락 ─────────────────────────────────
    const pr = unwrap(await lib.callAs(adminUid,
      'callableProposeConfirmedReassignment', {
        sourceApplicationId: srcId,
        targetWdId: slotWds[1].wdId,
        compensationOption: 'TARGET_BASE',
      }));
    console.log('제안:', pr.proposalId);
    await lib.callAs(uid, 'callableAcceptConfirmedReassignment', {
      proposalId: pr.proposalId,
      documentAccessConsentGiven: true,
      documentAccessConsentVersion: CONSENT,
    });

    // ── 5. 결과 B 의 기준 ─────────────────────────────────────
    const after = await db.collection('applications')
      .where('uid', '==', uid).where('toId', '==', toId)
      .where('status', '==', 'CONFIRMED').get();
    const target = after.docs
      .map((d) => ({id: d.id, ...d.data()}))
      .find((x) => x.id !== srcId);
    if (!target) {
      console.log('\n**결과 지원서를 찾지 못했다**');
    } else {
      console.log('\n재배치 결과 B:');
      console.log('  업무:', target.selectedWorkType, '| status:', target.status);
      console.log('  B snapshot:', brief(target.attendancePolicySnapshot));
      console.log('  A 와 동일 =',
        same7(target.attendancePolicySnapshot, inv0.attendancePolicySnapshot) ?
          '예 (원 약속 상속)' : '**아니오**');
      const live = (await bizRef.get()).data().attendanceRules;
      console.log('  현재 기준 C 와 무관 =',
        same7(target.attendancePolicySnapshot, live) ?
          '**아니오 — C 를 끌어왔다**' : '예');
      const ackA = inv0.attendancePolicyAcknowledgement;
      const ackB = target.attendancePolicyAcknowledgement;
      console.log('  확인 기록 상속 =',
        ackB != null && same7(ackB, ackA) &&
        ackB.acknowledgedBy === ackA.acknowledgedBy &&
        ackB.actorRole === ackA.actorRole ? '예' : '**아니오**');
      console.log('  B 확인 기록 actorRole =', ackB?.actorRole ?? '(없음)');
    }
  } finally {
    await bizRef.update({attendanceRules: originalRules});
    if (originalCfm != null) {
      await bizRef.update({attendancePolicyConfirmation: originalCfm});
    } else {
      await bizRef.update({
        attendancePolicyConfirmation: lib.admin.firestore.FieldValue.delete(),
      });
    }
    if (avBackup != null) {
      try {
        await lib.callAs(avBackup.uid, 'callableSetInviteRegions',
          {enabled: false, regions: []});
        await lib.callAs(avBackup.uid, 'callableSetAvailability',
          {dates: (avBackup.data && avBackup.data.dates) || []});
        const back = (await db.collection('worker_availability')
          .doc(avBackup.uid).get()).data() ?? {};
        console.log('근로자 초대 설정 원복: inviteEnabled =',
          back.inviteEnabled === true ? '**true (원복 실패)**' : 'false',
          '| dates', JSON.stringify(back.dates || []));
      } catch (e) { console.log('근로자 설정 원복 실패:', reasonOf(e)); }
    }
    if (toId) {
      try {
        await lib.callAs(adminUid, 'callableCloseTOManually', {toId, businessId});
      } catch (e) { console.log('공고 정리 실패:', reasonOf(e)); }
    }
    const back = (await bizRef.get()).data();
    console.log('\n기준 원복:', brief(back.attendanceRules),
      same7(back.attendanceRules, originalRules) ? '(확인)' : '(**불일치**)');
    console.log('확인 원복:',
      back.attendancePolicyConfirmation == null ? '(없음 — 원래 상태)' : '있음');
  }
  process.exit(0);
})().catch((e) => { console.error('실패:', reasonOf(e)); process.exit(1); });
