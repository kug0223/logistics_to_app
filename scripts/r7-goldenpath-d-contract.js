/**
 * [R7-GOLDEN-PATH-DEV-E2E] Step D — 계약서 발송(사업주 서명) → 근로자 서명.
 *
 *   canonical writer:
 *     callableFinalizeEmployerSignature (isNewUnsaved=true, contractData 포함)
 *     callableFinalizeWorkerSignature
 *
 *   §27 주의 — contractData 는 원래 Dart `ContractService` 가 만든다.
 *   이 스크립트는 그 **직렬화 형태만** 재현하고, 쓰기는 전부 canonical
 *   callable 이 한다. 따라서 CF 경로는 DEV RUNTIME 증거지만
 *   **Dart contract builder 자체는 이 단계에서 실행되지 않는다**(정직하게 기록).
 */
'use strict';
const fs = require('fs');
const lib = require('./r7-fixture-lib');
const {db} = lib;
const unwrap = (r) => (r && (r.result ?? r.data)) ?? r;

// 1x1 투명 PNG — 서명 이미지 자리. 실제 인감/서명 이미지를 쓰지 않는다.
const PNG_1PX = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4' +
  '2mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==';

// 최소 유효 PDF — 실제 계약서 PDF 는 Dart 가 만든다(이 단계 미실행).
const PDF_MIN = Buffer.from(
  '%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n' +
  '2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n' +
  '3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 595 842]>>endobj\n' +
  'trailer<</Root 1 0 R>>\n%%EOF\n', 'utf8').toString('base64');

(async () => {
  const L = JSON.parse(fs.readFileSync('.goldenpath.json', 'utf8'));
  const app = (await db.collection('applications').doc(L.applicationId).get())
    .data();
  const biz = (await db.collection('businesses').doc(L.businessId).get()).data();
  const owner = (await db.collection('users').doc(biz.ownerId).get()).data();
  const worker = (await db.collection('users').doc(L.applicantUid).get()).data();
  const tplSnap = await db.collection('businesses').doc(L.businessId)
    .collection('contract_templates').limit(1).get();
  const tpl = tplSnap.docs[0];
  const articles = (tpl.data().articles || [])
    .map((a) => ({title: a.title ?? '', content: a.content ?? ''}));
  console.log('템플릿:', tpl.id.slice(0, 8) + '…', '| 조항', articles.length);

  const slot = {
    applicationId: L.applicationId,
    workDate: L.dateStr,
    startTime: L.startTime,
    endTime: L.endTime,
    wage: L.wage,
    wageType: 'hourly',
  };

  const contractData = {
    applicationId: L.applicationId,
    businessId: L.businessId,
    workerId: L.applicantUid,
    isLongTerm: false,
    toId: L.toId,
    workDetailId: L.wdId,
    slots: [slot],
    applicationIds: [L.applicationId],
    pdfUrl: null,
    templateId: tpl.id,
    snapshot: {
      businessName: biz.name ?? '',
      businessNumber: biz.businessNumber ?? '',
      businessAddress: [biz.address, biz.detailAddress].filter(Boolean).join(' '),
      businessPhone: biz.phone ?? null,
      ownerName: biz.ownerName ?? owner?.name ?? '',
      workerName: worker.name ?? '',
      workerBirthDate: null,
      workerPhone: worker.phone ?? null,
      workerAddress: null,
      workType: L.workType,
      workPlace: biz.address ?? '',
      isLongTerm: false,
      contractStart: null, contractEnd: null, workDays: null,
      startTime: L.startTime, endTime: L.endTime,
      breakMinutes: 0,
      wage: L.wage, wageType: 'hourly',
      wagePaymentDay: null,
      paymentMethod: '계좌이체',
      baseHourlyWage: null,
    },
    articles,
  };

  // 이미 발송된 계약서가 있으면 그것을 이어서 쓴다 — 두 장 보내지 않는다.
  const existing = await db.collection('employment_contracts')
    .where('applicationId', '==', L.applicationId).get();
  let contractId;
  if (!existing.empty) {
    contractId = existing.docs[0].id;
    console.log('기존 계약서 이어서 진행:', contractId.slice(0, 10) + '…',
      '| status =', existing.docs[0].data().status);
  } else {
    contractId = db.collection('employment_contracts').doc().id;
    console.log('contractId:', contractId.slice(0, 10) + '…');
    console.log('\n— callableFinalizeEmployerSignature (isNewUnsaved)');
    await lib.callAs(L.adminUid, 'callableFinalizeEmployerSignature', {
      contractId, signatureBase64: PNG_1PX,
      isNewUnsaved: true, contractData,
    });
  }

  let c = (await db.collection('employment_contracts').doc(contractId).get())
    .data();
  let a = (await db.collection('applications').doc(L.applicationId).get())
    .data();
  console.log('  계약 status :', c.status, '| 지원서 status:', a.status);
  console.log('  지급일정(서버 주입):', c.snapshot.payScheduleType ?? '(없음)');

  // 근로자에게 간 알림 — 어느 사업장 계약인지 말하는가
  const nSnap = await db.collection('users').doc(L.applicantUid)
    .collection('notifications')
    .where('type', '==', 'contractSignRequested').get();
  console.log('\n=== 서명 요청 알림 ===');
  console.log('  건수:', nSnap.size);
  nSnap.forEach((n) => console.log('  본문:', JSON.stringify(n.data().body)));
  console.log('  계약 문서 top-level businessName:',
    c.businessName === undefined ? '(없음 — 필드 자체가 없다)' : c.businessName);

  console.log('\n— callableFinalizeWorkerSignature');
  const wres = unwrap(await lib.callAs(L.applicantUid,
    'callableFinalizeWorkerSignature', {
      contractId, signatureBase64: PNG_1PX, pdfBase64: PDF_MIN,
    }));
  console.log('  응답 키:', Object.keys(wres).join(', '));

  c = (await db.collection('employment_contracts').doc(contractId).get()).data();
  a = (await db.collection('applications').doc(L.applicationId).get()).data();
  console.log('\n=== Step D 결과 ===');
  console.log('  계약 status  :', c.status);
  console.log('  사업주 서명  :', !!c.employerSignatureUrl,
    '| 근로자 서명:', !!c.workerSignatureUrl);
  console.log('  지원서 status:', a.status);

  L.contractId = contractId;
  fs.writeFileSync('.goldenpath.json', JSON.stringify(L, null, 2));
  process.exit(0);
})().catch((e) => { console.error('실패:', e.message); process.exit(1); });
