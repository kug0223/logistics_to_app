/**
 * [R7-GOLDEN-PATH-DEV-E2E.1 §B] 근로자 자기 퇴근 fixture.
 *
 *   §7 — 시계를 조작하지 않는다. 지금 실제로 끝날 수 있는 근무를 만든다.
 *   earlyWindow 30분이므로 15:00 시작 근무는 14:30부터 출근할 수 있다.
 *   퇴근은 종료시각(15:10) 이후 lateWindow(30분) 안에 하면
 *   _processCheckout 이 offset 0 으로 처리해 정시 퇴근이 된다.
 *
 *   §8 — canonical posting → application → 서류검토 → confirm → contract
 *   전 흐름을 지킨다.
 *
 *   본 Golden Path 근로자는 오늘 14:00~18:00 이 이미 CONFIRMED 라
 *   겹침 차단에 걸린다. 그래서 **다른 근로자**를 쓴다.
 */
'use strict';
const fs = require('fs');
const lib = require('./r7-fixture-lib');
const {db} = lib;
const unwrap = (r) => (r && (r.result ?? r.data)) ?? r;
const CONSENT_VERSION = '2026-09-18-v3';
const PNG_1PX = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4' +
  '2mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==';
const PDF_MIN = Buffer.from(
  '%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n' +
  '2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n' +
  '3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 595 842]>>endobj\n' +
  'trailer<</Root 1 0 R>>\n%%EOF\n', 'utf8').toString('base64');

const START = '15:00';
const END = '15:10';

(async () => {
  const G = JSON.parse(fs.readFileSync('.goldenpath.json', 'utf8'));
  const businessId = G.businessId;
  const adminUid = G.adminUid;
  const dateStr = lib.kstDateKey(0);
  const workDateMs = lib.kstMidnightMs(0);
  const nowKst = new Date(Date.now() + 9 * 3600000).toISOString().slice(11, 16);
  console.log('KST 지금:', nowKst, '| 근무', START, '~', END, '|', dateStr);

  const biz = (await db.collection('businesses').doc(businessId).get()).data();
  const wtSnap = await db.collection('businesses').doc(businessId)
    .collection('workTypes').limit(1).get();
  const wt = wtSnap.docs[0].data();

  // 겹침이 없는 근로자 — 오늘 확정 근무가 없는 사람.
  const users = await db.collection('users').where('role', '==', 'USER').get();
  let uid = null;
  for (const u of users.docs) {
    const busy = await db.collection('applications')
      .where('uid', '==', u.id)
      .where('status', 'in', ['CONFIRMED', 'CONTRACT_PENDING']).get();
    const todayBusy = busy.docs.some((d) =>
      d.data().workDate?.toMillis() === workDateMs);
    if (!todayBusy) { uid = u.id; break; }
  }
  if (!uid) throw new Error('오늘 비어 있는 근로자가 없다');
  console.log('근로자:', uid.slice(0, 6) + '…');

  const wd = {
    wdId: 'b1-wd-1', workType: wt.name,
    workTypeIcon: wt.icon ?? 'box',
    workTypeColor: wt.color ?? '#1565C0',
    workTypeBackgroundColor: wt.backgroundColor ?? '#E3F2FD',
    wage: 12000, wageType: 'hourly', requiredCount: 1,
    startTime: START, endTime: END, order: 0,
    payScheduleType: 'next_day',
  };

  const created = unwrap(await lib.callAs(adminUid, 'callableCreateTO', {
    toData: {
      businessId, businessName: biz.name ?? '테스트사업장',
      title: '[B1] 자기 퇴근 검증 근무',
      description: 'R7-GOLDEN-PATH-DEV-E2E.1 §B 전용. 실제 모집 아님.',
      type: 'flex', workDetails: [wd], creatorUID: adminUid,
      totalRequired: 1, totalConfirmed: 0, totalPending: 0,
      status: 'active',
      deadlineType: 'FIXED_TIME', hoursBeforeStart: 1,
      isPublished: false, publishMode: 'deferred',
    },
  }));
  const toId = created.toId;
  await lib.callAs(adminUid, 'callableCreateFlexSlots', {
    toId, businessId, dates: [dateStr], workDetails: [wd],
    deadlineType: 'FIXED_TIME', hoursBeforeStart: 1,
    fixedDeadlineMs: Date.now() + 3 * 60000,
    publishMode: 'immediate',
  });
  try { await lib.callAs(adminUid, 'callablePublishTO', {toId}); } catch (_) {}

  const slots = await db.collection('tos').doc(toId).collection('slots').get();
  const slotId = slots.docs[0].id;
  const wdId = ((slots.docs[0].data().workDetails || [])[0] || {}).wdId;
  const to = (await db.collection('tos').doc(toId).get()).data();
  console.log('공고:', toId.slice(0, 10) + '…', '| slot', slotId.slice(0, 8) + '…',
    '| wdId', String(wdId).slice(0, 8) + '…');

  const ap = unwrap(await lib.callAs(uid, 'callableApplyToTO', {
    toId, slotId, businessId,
    businessName: to.businessName, toTitle: to.title,
    workDateMs, selectedWorkType: wd.workType, workDetailId: wdId,
    startTime: START, endTime: END, wage: wd.wage, wageType: 'hourly',
    idCardConsentGiven: true, documentAccessConsentGiven: true,
    documentAccessConsentVersion: CONSENT_VERSION,
  }));
  const applicationId = ap.applicationId;
  console.log('지원:', applicationId.slice(0, 24) + '…');

  // 서류 검토 — 확정 전 필수 단계(직전 Phase 확정 사실).
  const rev = unwrap(await lib.callAs(adminUid,
    'callableGetApplicantDocumentReview', {applicationId, businessId}));
  if (!rev.readiness.ready) {
    for (const t of ['ID', 'BANKBOOK']) {
      await lib.callAs(adminUid, 'callableReviewApplicantDocument', {
        applicationId, businessId, targetUid: rev.workerUid,
        documentType: t, decision: 'REVIEWED_OK',
        expectedVersion: t === 'ID' ?
          rev.versions.id : rev.versions.bankbook,
        expectedAccountVersion: rev.versions.account,
      });
    }
    console.log('서류 검토: 완료');
  } else {
    console.log('서류 검토: 이미 유효');
  }

  await lib.callAs(adminUid, 'callableConfirmApplication',
    {applicationId, businessId});
  let app = (await db.collection('applications').doc(applicationId).get())
    .data();
  console.log('확정:', app.status);

  // 계약 — canonical callable (경계 A 와는 별개로 둔다).
  const owner = (await db.collection('users').doc(biz.ownerId).get()).data();
  const worker = (await db.collection('users').doc(uid).get()).data();
  const tplSnap = await db.collection('businesses').doc(businessId)
    .collection('contract_templates').limit(1).get();
  const tpl = tplSnap.docs[0];
  const contractId = db.collection('employment_contracts').doc().id;
  await lib.callAs(adminUid, 'callableFinalizeEmployerSignature', {
    contractId, signatureBase64: PNG_1PX, isNewUnsaved: true,
    contractData: {
      applicationId, businessId, workerId: uid, isLongTerm: false,
      toId, workDetailId: wdId,
      slots: [{
        applicationId, workDate: dateStr,
        startTime: START, endTime: END, wage: wd.wage, wageType: 'hourly',
      }],
      applicationIds: [applicationId], pdfUrl: null, templateId: tpl.id,
      snapshot: {
        businessName: biz.name ?? '', businessNumber: biz.businessNumber ?? '',
        businessAddress: [biz.address, biz.detailAddress]
          .filter(Boolean).join(' '),
        businessPhone: biz.phone ?? null,
        ownerName: biz.ownerName ?? owner?.name ?? '',
        workerName: worker.name ?? '', workerBirthDate: null,
        workerPhone: worker.phone ?? null, workerAddress: null,
        workType: wd.workType, workPlace: biz.address ?? '',
        isLongTerm: false,
        contractStart: null, contractEnd: null, workDays: null,
        startTime: START, endTime: END, breakMinutes: 0,
        wage: wd.wage, wageType: 'hourly',
        wagePaymentDay: null, paymentMethod: '계좌이체', baseHourlyWage: null,
      },
      articles: (tpl.data().articles || [])
        .map((a) => ({title: a.title ?? '', content: a.content ?? ''})),
    },
  });
  await lib.callAs(uid, 'callableFinalizeWorkerSignature', {
    contractId, signatureBase64: PNG_1PX, pdfBase64: PDF_MIN,
  });
  const c = (await db.collection('employment_contracts').doc(contractId).get())
    .data();
  app = (await db.collection('applications').doc(applicationId).get()).data();
  console.log('계약:', c.status, '| 지원서:', app.status);

  // 출근 — 지금(earlyWindow 안).
  const ci = unwrap(await lib.callAs(uid, 'callableCheckIn', {
    applicationId, businessId, businessName: to.businessName,
    workDateMs, workType: wd.workType,
    latitude: biz.latitude, longitude: biz.longitude,
    method: 'gps', scheduledStartTime: START,
  }));
  const attendanceId = ci.attendanceId;
  const a = (await db.collection('attendance').doc(attendanceId).get()).data();
  const t = (v) => v && v.toMillis ?
    new Date(v.toMillis() + 9 * 3600000).toISOString().slice(11, 16) : '(없음)';
  console.log('\n=== 출근 완료 ===');
  console.log('  attendanceId:', attendanceId.slice(0, 30) + '…');
  console.log('  checkIn:', t(a.checkIn), '| originalCheckIn:',
    t(a.originalCheckIn), '| status:', a.status);
  console.log('  퇴근 가능 시각:', END, '이후 (lateWindow 30분 안)');

  fs.writeFileSync('.b1fixture.json', JSON.stringify({
    businessId, adminUid, uid, toId, slotId, wdId, applicationId,
    contractId, attendanceId, workDateMs, dateStr,
    startTime: START, endTime: END, wage: wd.wage,
  }, null, 2));
  console.log('\nledger: .b1fixture.json');
  process.exit(0);
})().catch((e) => { console.error('실패:', e.message); process.exit(1); });
