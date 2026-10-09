/**
 * [R7-GOLDEN-PATH-DEV-E2E] Step B — 지원.
 *   canonical callable 만 사용한다(§27). 검증은 읽기만.
 */
'use strict';
const fs = require('fs');
const lib = require('./r7-fixture-lib');
const {db} = lib;
const unwrap = (r) => (r && (r.result ?? r.data)) ?? r;
const short = (s) => String(s).slice(0, 6) + '…';

// lib/widgets/dialogs/apply/document_access_consent.dart 의 version 과 같아야 한다.
const CONSENT_VERSION = '2026-09-18-v3';

(async () => {
  const L = JSON.parse(fs.readFileSync('.goldenpath.json', 'utf8'));
  const to = (await db.collection('tos').doc(L.toId).get()).data();

  // legal CURRENT 인 지원자를 고른다 — 법적 gate 소음을 섞지 않는다.
  const users = await db.collection('users').where('role', '==', 'USER').get();
  let uid = null;
  for (const u of users.docs) {
    const r = unwrap(await lib.callAs(u.id, 'callableGetLegalReadiness', {}));
    if (r.status === 'CURRENT') { uid = u.id; break; }
  }
  if (!uid) throw new Error('legal CURRENT 지원자 없음');
  console.log('지원자:', short(uid));

  const res = unwrap(await lib.callAs(uid, 'callableApplyToTO', {
    toId: L.toId,
    slotId: L.slotId,
    businessId: L.businessId,
    businessName: to.businessName,
    toTitle: to.title,
    workDateMs: L.workDateMs,
    selectedWorkType: L.workType,
    workDetailId: L.wdId,
    startTime: L.startTime,
    endTime: L.endTime,
    wage: L.wage,
    wageType: 'hourly',
    idCardConsentGiven: true,
    documentAccessConsentGiven: true,
    documentAccessConsentVersion: CONSENT_VERSION,
  }));
  console.log('applicationId:', res.applicationId);

  const app = (await db.collection('applications').doc(res.applicationId).get())
    .data();
  const toAfter = (await db.collection('tos').doc(L.toId).get()).data();
  const slot = (await db.collection('tos').doc(L.toId)
    .collection('slots').doc(L.slotId).get()).data();

  console.log('\n=== Step B 결과 ===');
  console.log('  status        :', app.status);
  console.log('  snapshot wage :', app.wage, '| 시간',
    app.startTime, '~', app.endTime);
  console.log('  workType      :', app.selectedWorkType,
    '| wdId', app.workDetailId);
  console.log('  workDate(KST) :',
    new Date(app.workDate.toMillis() + 9 * 3600 * 1000)
      .toISOString().slice(0, 16));
  console.log('  TO totalPending:', toAfter.totalPending,
    '| totalConfirmed =', toAfter.totalConfirmed);
  console.log('  slot confirmed :', slot.confirmedCount, '| status', slot.status);

  L.applicantUid = uid;
  L.applicationId = res.applicationId;
  fs.writeFileSync('.goldenpath.json', JSON.stringify(L, null, 2));
  process.exit(0);
})().catch((e) => { console.error('실패:', e.message); process.exit(1); });
