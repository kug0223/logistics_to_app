/**
 * [R7-GOLDEN-PATH-DEV-E2E §2] Preflight — **READ ONLY. 쓰기 0.**
 *
 *   mutation 을 시작하기 전에 전제가 맞는지 본다. 안 맞으면 STOP 한다.
 *   PII 를 출력하지 않는다(uid 앞 6자만).
 */
'use strict';

const lib = require('./r7-fixture-lib');
const {db} = lib;
const unwrap = (r) => (r && (r.result ?? r.data)) ?? r;
const short = (s) => String(s).slice(0, 6) + '…';

(async () => {
  console.log('=== 사업장 ===');
  const bizSnap = await db.collection('businesses').get();
  for (const b of bizSnap.docs) {
    const d = b.data();
    const ownerSnap = await db.collection('users').doc(d.ownerId ?? '_').get();
    const owner = ownerSnap.data() ?? {};
    const wt = await db.collection('businesses').doc(b.id)
      .collection('workTypes').where('isActive', '==', true).get();
    const tpl = await db.collection('contract_templates')
      .where('businessId', '==', b.id).get();
    console.log('  bizId     :', short(b.id));
    console.log('   승인      :', d.isApproved === true);
    console.log('   등록증(biz):', !!(d.businessLicenseImageUrl ||
      d.businessLicenseImagePath));
    console.log('   등록증(owner):', !!(owner.businessLicenseImageUrl ||
      owner.businessLicenseImagePath));
    console.log('   활성 업무 :', wt.size);
    console.log('   계약 템플릿:', tpl.size);
    console.log('   사업주 날인:', !!(owner.sealBase64 || owner.signatureBase64));
    console.log('   좌표      :', d.latitude != null && d.longitude != null,
      '| gpsRadius =', d.gpsRadius ?? '(없음)');
  }

  console.log('\n=== 관리자 ===');
  const admins = await db.collection('users')
    .where('role', '==', 'BUSINESS_ADMIN').get();
  for (const a of admins.docs) {
    const d = a.data();
    console.log('  uid:', short(a.id), '| status =', d.accountStatus,
      '| managedBusinessIds =',
      Array.isArray(d.managedBusinessIds) ? d.managedBusinessIds.length : 0);
    try {
      const lr = unwrap(await lib.callAs(a.id, 'callableGetLegalReadiness', {}));
      console.log('   legal:', lr.status);
    } catch (e) {
      console.log('   legal: 조회 실패', String(e.message).slice(0, 60));
    }
  }

  console.log('\n=== 지원자 후보 ===');
  const users = await db.collection('users').where('role', '==', 'USER').get();
  for (const u of users.docs) {
    const d = u.data();
    const hasId = !!(d.idCardImagePath || d.idCardImageUrl);
    const hasBank = !!(d.bankName && d.accountNumber && d.accountHolder);
    const hasBook = !!(d.bankbookImagePath || d.bankbookImageUrl);
    const ready = hasId && hasBank && hasBook;
    let legal = '?';
    try {
      legal = unwrap(await lib.callAs(u.id, 'callableGetLegalReadiness', {}))
        .status;
    } catch (_) { legal = '조회실패'; }
    console.log(' ', short(u.id),
      '| 신분증', hasId, '| 계좌', hasBank, '| 통장', hasBook,
      '| isIdVerified', d.isIdVerified === true,
      '| PASS', !!d.passVerifiedAt,
      '| 외국인', d.isForeign === true,
      '| status', d.accountStatus,
      '| legal', legal,
      ready ? '  ← 서류 OK' : '');
  }

  console.log('\n=== 기존 데이터 규모 ===');
  for (const c of ['tos', 'applications', 'employment_contracts',
    'attendances', 'contract_templates']) {
    try {
      const s = await db.collection(c).get();
      console.log(' ', c.padEnd(22), s.size);
    } catch (e) {
      console.log(' ', c.padEnd(22), '조회 실패');
    }
  }

  console.log('\n(쓰기 0)');
  process.exit(0);
})().catch((e) => {
  console.error('실패:', e.message);
  process.exit(1);
});
