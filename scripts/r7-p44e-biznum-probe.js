/**
 * [E2 §38] 사업장 생성 규칙 조건을 실제 계정 값과 대조 — READ ONLY. 쓰기 0.
 *
 *   firestore.rules 의 businesses create 는 다음을 요구한다:
 *     isBusinessAdmin() / ownerId==uid / uid in adminIds / adminIds.hasOnly([uid])
 *     isApproved==false / rating==0 / reviewCount==0
 *     businessNumber.matches('[0-9]{10}')
 *     users/{uid}.managedBusinessIds.size() < 5
 *   클라이언트는 businessNumber 를 users/{uid}.businessNumber 에서 미리 채운다.
 */
'use strict';

const {db} = require('./r7-fixture-lib');

(async () => {
  const snap = await db.collection('users')
    .where('role', '==', 'BUSINESS_ADMIN').get();
  console.log('BUSINESS_ADMIN 계정:', snap.size, '건\n');

  for (const doc of snap.docs) {
    const d = doc.data();
    const raw = d.businessNumber;
    const digits = typeof raw === 'string' ? raw.replace(/-/g, '') : '';
    const ok = /^[0-9]{10}$/.test(digits);
    console.log('  uid       ', doc.id.slice(0, 8) + '…');
    console.log('   role     ', d.role, '| accountStatus =', d.accountStatus);
    console.log('   businessNumber 필드 존재:',
      Object.prototype.hasOwnProperty.call(d, 'businessNumber') ? 'YES' : '**NO**');
    console.log('   타입      ', raw === undefined ? '(undefined)' : typeof raw);
    console.log('   숫자만 길이', digits.length, '자리');
    console.log('   규칙 [0-9]{10} 통과:', ok ? 'YES' : '**NO — create 거부**');
    console.log('   managedBusinessIds',
      Array.isArray(d.managedBusinessIds) ? d.managedBusinessIds.length : '(없음)');
    console.log('');
  }

  console.log('쓰기 0. READ ONLY 종료.');
  process.exit(0);
})().catch((e) => { console.error('probe 실패:', e.message); process.exit(1); });
