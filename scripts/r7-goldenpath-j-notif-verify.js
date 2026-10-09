/**
 * [R7-GOLDEN-PATH-DEV-E2E] Step J — 서명 요청 알림 본문 수정 검증.
 *
 *   §8 격리 공고(Step I)에서 확정된 지원서로 계약서를 한 장 발송해
 *   알림 본문에 사업장 이름이 들어가는지 **실측**한다.
 */
'use strict';
const lib = require('./r7-fixture-lib');
const {db} = lib;

const PNG_1PX = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4' +
  '2mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==';

(async () => {
  const L = require('../.goldenpath.json');
  // Step I 가 만든 공고의 확정 지원서를 찾는다.
  const apps = await db.collection('applications')
    .where('businessId', '==', L.businessId)
    .where('status', '==', 'CONTRACT_PENDING').get();
  if (apps.empty) throw new Error('CONTRACT_PENDING 지원서 없음');
  const appDoc = apps.docs[0];
  const app = appDoc.data();
  console.log('대상 지원서:', appDoc.id.slice(0, 20) + '…',
    '| toId', String(app.toId).slice(0, 10) + '…');

  const existing = await db.collection('employment_contracts')
    .where('applicationId', '==', appDoc.id).get();
  if (!existing.empty) throw new Error('이미 계약서가 있다 — 알림 비교 불가');

  const biz = (await db.collection('businesses').doc(L.businessId).get()).data();
  const owner = (await db.collection('users').doc(biz.ownerId).get()).data();
  const worker = (await db.collection('users').doc(app.uid).get()).data();
  const tplSnap = await db.collection('businesses').doc(L.businessId)
    .collection('contract_templates').limit(1).get();
  const tpl = tplSnap.docs[0];

  const before = (await db.collection('users').doc(app.uid)
    .collection('notifications')
    .where('type', '==', 'contractSignRequested').get()).size;
  console.log('기존 서명요청 알림:', before, '건');

  const contractId = db.collection('employment_contracts').doc().id;
  const workDate = new Date(app.workDate.toMillis() + 9 * 3600000)
    .toISOString().slice(0, 10);
  await lib.callAs(L.adminUid, 'callableFinalizeEmployerSignature', {
    contractId, signatureBase64: PNG_1PX, isNewUnsaved: true,
    contractData: {
      applicationId: appDoc.id,
      businessId: L.businessId,
      workerId: app.uid,
      isLongTerm: false,
      toId: app.toId,
      workDetailId: app.workDetailId,
      slots: [{
        applicationId: appDoc.id, workDate,
        startTime: app.startTime, endTime: app.endTime,
        wage: app.wage, wageType: 'hourly',
      }],
      applicationIds: [appDoc.id],
      pdfUrl: null, templateId: tpl.id,
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
        workType: app.selectedWorkType, workPlace: biz.address ?? '',
        isLongTerm: false,
        contractStart: null, contractEnd: null, workDays: null,
        startTime: app.startTime, endTime: app.endTime, breakMinutes: 0,
        wage: app.wage, wageType: 'hourly',
        wagePaymentDay: null, paymentMethod: '계좌이체', baseHourlyWage: null,
      },
      articles: (tpl.data().articles || [])
        .map((a) => ({title: a.title ?? '', content: a.content ?? ''})),
    },
  });

  const after = await db.collection('users').doc(app.uid)
    .collection('notifications')
    .where('type', '==', 'contractSignRequested').get();
  console.log('\n=== Step J 결과 ===');
  console.log('  알림:', after.size, '건 (이전', before, ')');
  console.log('  사업장 이름:', JSON.stringify(biz.name));
  after.docs
    .sort((a, b) => (b.data().createdAt?.toMillis() ?? 0) -
      (a.data().createdAt?.toMillis() ?? 0))
    .forEach((n, i) => {
      const b = n.data().body;
      console.log(`  ${i === 0 ? '최신' : '이전'}:`, JSON.stringify(b),
        i === 0 ? (String(b).includes(biz.name) ?
          '← 사업장 이름 포함' : '← **여전히 없다**') : '');
    });
  process.exit(0);
})().catch((e) => { console.error('실패:', e.message); process.exit(1); });
