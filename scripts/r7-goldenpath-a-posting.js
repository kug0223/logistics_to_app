/**
 * [R7-GOLDEN-PATH-DEV-E2E] Step A — 공고 등록.
 *
 *   §27: canonical callable 만 쓴다. Firestore 직접 write 로 정상 흐름을
 *   흉내 내지 않는다. 읽기(검증)만 Admin SDK.
 *
 *   ledger 는 `scratchpad/goldenpath.json` 에 누적한다.
 */
'use strict';

const fs = require('fs');
const path = require('path');
const lib = require('./r7-fixture-lib');
const {db} = lib;

const LEDGER = path.join(__dirname, '..', '.goldenpath.json');
const unwrap = (r) => (r && (r.result ?? r.data)) ?? r;
const KST = 9 * 3600 * 1000;

function kstTodayParts() {
  const d = new Date(Date.now() + KST);
  return {
    y: d.getUTCFullYear(), m: d.getUTCMonth() + 1, d: d.getUTCDate(),
  };
}
const pad = (n) => String(n).padStart(2, '0');

function saveLedger(patch) {
  const cur = fs.existsSync(LEDGER) ?
    JSON.parse(fs.readFileSync(LEDGER, 'utf8')) : {};
  fs.writeFileSync(LEDGER, JSON.stringify({...cur, ...patch}, null, 2));
}

(async () => {
  const t = kstTodayParts();
  const dateStr = `${t.y}-${pad(t.m)}-${pad(t.d)}`;
  console.log('KST 오늘:', dateStr);

  const bizSnap = await db.collection('businesses').limit(1).get();
  const biz = bizSnap.docs[0];
  const bizData = biz.data();
  const admins = await db.collection('users')
    .where('role', '==', 'BUSINESS_ADMIN').limit(1).get();
  const adminUid = admins.docs[0].id;

  // 업무 하나를 그대로 쓴다 — 새 identity 를 만들지 않는다.
  const wtSnap = await db.collection('businesses').doc(biz.id)
    .collection('workTypes').limit(1).get();
  const wt = wtSnap.docs[0].data();
  console.log('사용할 업무:', wt.name);

  // WorkDetailData 모양 (lib/models/core/work_detail_data.dart 와 같은 키)
  const wd = {
    wdId: 'gp-wd-1',
    workType: wt.name,
    workTypeIcon: wt.icon ?? 'box',
    workTypeColor: wt.color ?? '#1565C0',
    workTypeBackgroundColor: wt.backgroundColor ?? '#E3F2FD',
    wage: 12000,
    wageType: 'hourly',
    requiredCount: 1,          // §8: 1명이면 확정 후 FULL 전환까지 본다
    // KST 지금이 13시대라 09시 시작은 이미 지났다. 지각으로 오염되지
    // 않도록 아직 시작 전인 시간대를 쓴다.
    startTime: '14:00',
    endTime: '18:00',
    order: 0,
    // 서버가 요구하는 지급 일정 (same_day | next_day | weekly | monthly)
    payScheduleType: 'next_day',
  };

  const toData = {
    businessId: biz.id,
    businessName: bizData.name ?? '테스트사업장',
    title: '[GOLDEN PATH] 테스트 공고',
    description: 'R7-GOLDEN-PATH-DEV-E2E 전용. 실제 모집이 아닙니다.',
    type: 'flex',
    workDetails: [wd],
    creatorUID: adminUid,
    totalRequired: 1,
    totalConfirmed: 0,
    totalPending: 0,
    status: 'active',
    // 오늘 근무라 '시작 N시간 전' 마감은 이미 지났다 — 고정 시각을 쓴다.
    deadlineType: 'FIXED_TIME',
    hoursBeforeStart: 1,
    isPublished: false,        // 슬롯 생성 뒤 공개(클라이언트와 같은 순서)
    publishMode: 'deferred',
  };

  console.log('\n— callableCreateTO');
  const created = unwrap(await lib.callAs(adminUid, 'callableCreateTO',
    {toData}));
  const toId = created.toId;
  console.log('  toId:', toId);

  console.log('— callableCreateFlexSlots');
  await lib.callAs(adminUid, 'callableCreateFlexSlots', {
    toId,
    businessId: biz.id,
    dates: [dateStr],
    workDetails: [wd],
    deadlineType: 'FIXED_TIME',
    hoursBeforeStart: 1,
    // 마감은 슬롯 시작(14:00 KST) 이전이어야 한다 — 서버가 검증한다.
    fixedDeadlineMs: Date.now() + 8 * 60 * 1000,
    publishMode: 'immediate',
  });

  console.log('— callablePublishTO');
  try {
    await lib.callAs(adminUid, 'callablePublishTO', {toId});
  } catch (e) {
    console.log('  공개 호출 결과:', String(e.message).slice(0, 120));
  }

  // ── 검증 (읽기만) ───────────────────────────────────────────
  const toSnap = await db.collection('tos').doc(toId).get();
  const to = toSnap.data() ?? {};
  const slots = await db.collection('tos').doc(toId).collection('slots').get();
  console.log('\n=== Step A 결과 ===');
  console.log('  status      :', to.status, '| isPublished =', to.isPublished);
  console.log('  totalRequired:', to.totalRequired,
    '| totalConfirmed =', to.totalConfirmed);
  console.log('  슬롯        :', slots.size);
  slots.forEach((s) => {
    const d = s.data();
    const wds = Array.isArray(d.workDetails) ? d.workDetails : [];
    console.log('   slotId:', s.id.slice(0, 10) + '…',
      '| date =', d.date?.toDate?.().toISOString().slice(0, 10),
      '| status =', d.status, '| confirmed =', d.confirmedCount,
      '| wd =', wds.map((w) => `${w.wdId}:${w.workType}:${w.requiredCount}`)
        .join(','));
  });

  saveLedger({
    toId, businessId: biz.id, adminUid,
    slotId: slots.docs[0]?.id ?? null,
    wdId: wd.wdId, workType: wd.workType,
    dateStr, wage: wd.wage,
    startTime: wd.startTime, endTime: wd.endTime,
  });
  console.log('\nledger 저장:', LEDGER);
  process.exit(0);
})().catch((e) => {
  console.error('실패:', e.message);
  process.exit(1);
});
