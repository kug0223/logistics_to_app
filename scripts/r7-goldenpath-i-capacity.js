/**
 * [R7-GOLDEN-PATH-DEV-E2E] Step I — §8 정원 차단 격리 관측.
 *
 *   본 Golden Path 의 공고는 마감이 이미 지나서, 두 번째 지원자가
 *   "마감 시간이 지났습니다" 로 거절됐다. 그건 정원 차단이 아니다.
 *   마감을 넉넉히 열어 둔 공고 하나로 **정원만** 격리해서 본다.
 */
'use strict';
const lib = require('./r7-fixture-lib');
const {db} = lib;
const unwrap = (r) => (r && (r.result ?? r.data)) ?? r;
const CONSENT_VERSION = '2026-09-18-v3';

(async () => {
  const L = require('../.goldenpath.json');
  const dateStr = lib.kstDateKey(1);           // 내일
  const workDateMs = lib.kstMidnightMs(1);
  const biz = (await db.collection('businesses').doc(L.businessId).get()).data();
  const wtSnap = await db.collection('businesses').doc(L.businessId)
    .collection('workTypes').limit(1).get();
  const wt = wtSnap.docs[0].data();

  const wd = {
    wdId: 'cap-wd-1', workType: wt.name,
    workTypeIcon: wt.icon ?? 'box',
    workTypeColor: wt.color ?? '#1565C0',
    workTypeBackgroundColor: wt.backgroundColor ?? '#E3F2FD',
    wage: 12000, wageType: 'hourly', requiredCount: 1,
    startTime: '10:00', endTime: '14:00', order: 0,
    payScheduleType: 'next_day',
  };

  const created = unwrap(await lib.callAs(L.adminUid, 'callableCreateTO', {
    toData: {
      businessId: L.businessId,
      businessName: biz.name ?? '테스트사업장',
      title: '[GOLDEN PATH §8] 정원 격리 공고',
      description: 'R7-GOLDEN-PATH-DEV-E2E §8 전용. 실제 모집 아님.',
      type: 'flex', workDetails: [wd],
      creatorUID: L.adminUid,
      totalRequired: 1, totalConfirmed: 0, totalPending: 0,
      status: 'active',
      deadlineType: 'HOURS_BEFORE', hoursBeforeStart: 1,
      isPublished: false, publishMode: 'deferred',
    },
  }));
  const toId = created.toId;
  await lib.callAs(L.adminUid, 'callableCreateFlexSlots', {
    toId, businessId: L.businessId, dates: [dateStr], workDetails: [wd],
    deadlineType: 'HOURS_BEFORE', hoursBeforeStart: 1,
    publishMode: 'immediate',
  });
  try { await lib.callAs(L.adminUid, 'callablePublishTO', {toId}); } catch (_) {}

  const slots = await db.collection('tos').doc(toId).collection('slots').get();
  const slotId = slots.docs[0].id;
  const srvWd = (slots.docs[0].data().workDetails || [])[0] || {};
  const wdId = srvWd.wdId;
  const to = (await db.collection('tos').doc(toId).get()).data();
  console.log('공고:', toId.slice(0, 10) + '…', '| 근무일', dateStr,
    '| 마감 =', to.deadlineType, to.hoursBeforeStart + 'h 전');

  const base = {
    toId, slotId, businessId: L.businessId,
    businessName: to.businessName, toTitle: to.title,
    workDateMs, selectedWorkType: wd.workType, workDetailId: wdId,
    startTime: wd.startTime, endTime: wd.endTime,
    wage: wd.wage, wageType: 'hourly',
    idCardConsentGiven: true, documentAccessConsentGiven: true,
    documentAccessConsentVersion: CONSENT_VERSION,
  };

  // 지원자 둘 — 첫 번째는 확정, 두 번째는 정원이 찬 뒤 지원.
  const users = await db.collection('users').where('role', '==', 'USER').get();
  const u1 = L.applicantUid;
  const u2 = users.docs.find((d) => d.id !== u1).id;

  const a1 = unwrap(await lib.callAs(u1, 'callableApplyToTO', base));
  console.log('\n지원자1 지원:', a1.applicationId.slice(0, 20) + '…');

  await lib.callAs(L.adminUid, 'callableConfirmApplication', {
    applicationId: a1.applicationId, businessId: L.businessId,
  });
  const s1 = (await db.collection('tos').doc(toId)
    .collection('slots').doc(slotId).get()).data();
  console.log('확정 후 slot: status =', s1.status,
    '| confirmedCount =', s1.confirmedCount,
    '| wdCounts =', JSON.stringify(s1.workDetailCounts));

  console.log('\n지원자2 지원 (정원 1/1, 마감은 아직 열려 있다):');
  try {
    const a2 = unwrap(await lib.callAs(u2, 'callableApplyToTO', base));
    console.log('  통과 — applicationId', a2.applicationId.slice(0, 20) + '…');
    const app2 = (await db.collection('applications').doc(a2.applicationId)
      .get()).data();
    console.log('  status =', app2.status,
      '→ 대기(PENDING)는 정원과 무관하다는 설계와 일치하는가:',
      app2.status === 'PENDING');
  } catch (e) {
    console.log('  거절:', String(e.message).slice(0, 180));
  }

  const to2 = (await db.collection('tos').doc(toId).get()).data();
  console.log('\nTO: status =', to2.status,
    '| totalConfirmed =', to2.totalConfirmed,
    '| totalPending =', to2.totalPending);

  // 두 번째 지원자를 확정하려 하면 — 자리가 없다.
  const pend = await db.collection('applications')
    .where('toId', '==', toId).where('status', '==', 'PENDING').get();
  if (!pend.empty) {
    console.log('\n대기자 확정 시도 (좌석 없음):');
    try {
      await lib.callAs(L.adminUid, 'callableConfirmApplication', {
        applicationId: pend.docs[0].id, businessId: L.businessId,
      });
      console.log('  **통과했다 — 정원을 넘겼다**');
    } catch (e) {
      console.log('  거절:', String(e.message).slice(0, 180));
    }
  }
  console.log('\n(정리는 하지 않는다 — §30)');
  process.exit(0);
})().catch((e) => { console.error('실패:', e.message); process.exit(1); });
