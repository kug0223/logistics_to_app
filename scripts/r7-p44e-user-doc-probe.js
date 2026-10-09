/**
 * [E2 §38] 저장 실패 진단 — READ ONLY. 쓰기 0.
 *   오류가 가리키는 uid 의 users 문서가 실제로 있는지, 그리고 DEV 의
 *   users 8건이 각각 어떤 역할·상태인지 본다. PII 는 가린다.
 */
'use strict';

const {db} = require('./r7-fixture-lib');

const TARGET = 'BErRdiWP1xbgyoTovxwAPNEsuD72';
const mask = (s) => (!s ? '(없음)' : s.length <= 2 ? '*'.repeat(s.length)
  : s[0] + '*'.repeat(Math.max(s.length - 2, 1)) + s[s.length - 1]);

(async () => {
  const t = await db.collection('users').doc(TARGET).get();
  console.log('=== 오류가 가리킨 uid ===');
  console.log('  ', TARGET.slice(0, 8) + '…');
  console.log('   users 문서 존재:', t.exists ? 'YES' : '**NO**');
  if (t.exists) {
    const d = t.data();
    console.log('   role =', d.role, '| accountStatus =', d.accountStatus,
      '| 이름 =', mask(d.name), '| managedBusinessIds =',
      Array.isArray(d.managedBusinessIds) ? d.managedBusinessIds.length : '(없음)');
  }

  console.log('\n=== DEV users 전수 ===');
  const all = await db.collection('users').get();
  for (const doc of all.docs) {
    const d = doc.data();
    console.log('  ', doc.id.slice(0, 8) + '…',
      '| role =', String(d.role ?? '(없음)').padEnd(15),
      '| status =', String(d.accountStatus ?? '(없음)').padEnd(22),
      '| managed =', Array.isArray(d.managedBusinessIds) ? d.managedBusinessIds.length : 0,
      '| 이름 =', mask(d.name));
  }

  console.log('\n=== deleted_accounts 에 그 uid 가 있는가 ===');
  const del = await db.collection('deleted_accounts').limit(50).get();
  console.log('   deleted_accounts 건수(표본):', del.size);
  for (const doc of del.docs) {
    const d = doc.data();
    if (doc.id === TARGET || d.uid === TARGET) {
      console.log('   ** 일치:', doc.id.slice(0, 8) + '…', '| canReregisterAt =',
        d.canReregisterAt && d.canReregisterAt._seconds
          ? new Date(d.canReregisterAt._seconds * 1000).toISOString().slice(0, 10) : '(없음)');
    }
  }

  console.log('\n쓰기 0. READ ONLY 종료.');
  process.exit(0);
})().catch((e) => { console.error('probe 실패:', e.message); process.exit(1); });
