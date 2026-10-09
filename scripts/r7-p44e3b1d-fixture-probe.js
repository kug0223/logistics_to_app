/**
 * [R7-P4.4E.3B.1-D §7] runtime permission matrix 를 돌릴 fixture 가 있는가.
 *   READ ONLY. 쓰기 0. 실사용 계정의 권한·날인을 바꾸지 않는다.
 */
'use strict';

const {db} = require('./r7-fixture-lib');

const mask = (s) => (!s ? '(없음)' : s.length <= 2 ? '*'.repeat(s.length)
  : s[0] + '*'.repeat(Math.max(s.length - 2, 1)) + s[s.length - 1]);

(async () => {
  const biz = await db.collection('businesses').get();
  console.log('=== 사업장', biz.size, '건 ===');
  for (const b of biz.docs) {
    const d = b.data();
    console.log('  ', b.id.slice(0, 8) + '…', '| 이름 =', mask(d.name),
      '| owner =', String(d.ownerId ?? '').slice(0, 8) + '…',
      '| 승인 =', d.isApproved === true,
      '| adminIds =', Array.isArray(d.adminIds) ? d.adminIds.length : 0);

    const members = await db.collection('businesses').doc(b.id)
      .collection('members').get();
    console.log('     members:', members.size, '건');
    for (const m of members.docs) {
      const p = (m.data() || {}).permissions || {};
      console.log('       ', m.id.slice(0, 8) + '…',
        'canManageTo=', p.canManageTo === true,
        'canManageContract=', p.canManageContract === true,
        'canManageWorkers=', p.canManageWorkers === true,
        'canManageWage=', p.canManageWage === true);
    }
  }

  console.log('\n=== SubAdmin 후보 (users) ===');
  const users = await db.collection('users').get();
  let subAdmins = 0;
  for (const u of users.docs) {
    const d = u.data();
    const ids = d.subAdminBusinessIds;
    const legacy = d.subAdminOf;
    if ((Array.isArray(ids) && ids.length > 0) || (legacy && legacy.length > 0)) {
      subAdmins++;
      console.log('  ', u.id.slice(0, 8) + '…', '| role =', d.role,
        '| subAdminBusinessIds =', Array.isArray(ids) ? ids.length : 0,
        '| subAdminOf =', legacy ? 'Y' : 'N',
        '| 개인 날인 =', (d.sealBase64 || '').length > 0);
    }
  }
  console.log('  SubAdmin 보유 계정:', subAdmins, '건');

  console.log('\n=== owner 날인 상태 (true/false fixture 가용성) ===');
  for (const b of biz.docs) {
    const ownerId = b.data().ownerId;
    if (!ownerId) continue;
    const o = await db.collection('users').doc(ownerId).get();
    const has = ((o.data() || {}).sealBase64 || '').length > 0;
    console.log('  ', b.id.slice(0, 8) + '…', '→ owner 날인:', has);
  }

  console.log('\n쓰기 0. READ ONLY 종료.');
  process.exit(0);
})().catch((e) => { console.error('probe 실패:', e.message); process.exit(1); });
