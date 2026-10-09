/**
 * [R7-P4.4E.8 §4 후속] 같은 공고를 **KST 기준**으로 다시 읽는다. READ ONLY.
 *   1차 프로브가 UTC 날짜를 찍어 하루 밀려 보였다 — 날짜 주장을 틀리지 않기 위해
 *   두 표현을 나란히 둔다.
 *   그리고 각 날짜에 이 사용자가 **아직 지원 가능한 wdId** 가 남아 있는지 센다.
 */
'use strict';

const {db} = require('./r7-fixture-lib');

const TO_ID = 'Zi9UDkhZdTua5AgkG5HQ';
const UID = 'psKpbHANvkdPU9PgJoBiPNoeIT93';
const ACTIVE = ['PENDING', 'CONTRACT_PENDING', 'CONFIRMED', 'INVITED'];

const kstKey = (dt) => {
  const k = new Date(dt.getTime() + 9 * 3600 * 1000);
  return k.toISOString().slice(0, 10);
};

(async () => {
  const toSnap = await db.collection('tos').doc(TO_ID).get();
  const to = toSnap.data();
  console.log('=== 공고 ===');
  console.log('  toId:', TO_ID, '| type:', to.type, '| status:', to.status);
  console.log('  to.dates:', (to.dates || []).join(','));
  console.log('  rangeStart(KST):', to.rangeStart ? kstKey(to.rangeStart.toDate()) : '-',
    '| rangeEnd(KST):', to.rangeEnd ? kstKey(to.rangeEnd.toDate()) : '-');

  const apps = await db.collection('applications')
    .where('toId', '==', TO_ID).where('uid', '==', UID).limit(50).get();
  const byKey = new Map();
  console.log('');
  console.log('=== 이 사용자의 지원서 ===');
  for (const a of apps.docs) {
    const d = a.data();
    const wd = d.workDate ? d.workDate.toDate() : null;
    console.log('  status:', d.status, '| slotId:', d.slotId,
      '| wdId:', d.wdId,
      '| workType:', d.selectedWorkType,
      '| workDate UTC:', wd ? wd.toISOString().slice(0, 10) : '?',
      '→ KST:', wd ? kstKey(wd) : '?');
    if (ACTIVE.includes(d.status)) byKey.set(`${d.slotId}|${d.wdId}`, d.status);
  }

  const slots = await db.collection('tos').doc(TO_ID)
    .collection('slots').limit(40).get();
  const rows = [];
  for (const s of slots.docs) {
    const sd = s.data();
    const dt = sd.date ? sd.date.toDate() : null;
    rows.push({
      slotId: s.id,
      utc: dt ? dt.toISOString().slice(0, 10) : '?',
      kst: dt ? kstKey(dt) : '?',
      status: sd.status,
      wds: (sd.workDetails || []).filter(Boolean),
    });
  }
  rows.sort((a, b) => a.kst.localeCompare(b.kst));

  console.log('');
  console.log('=== 날짜별: 이 사용자가 아직 지원 가능한 wdId 가 남아 있는가 ===');
  console.log('  KST날짜      UTC날짜     slot상태  총wd  관계있음  남은신규');
  for (const r of rows) {
    let active = 0;
    for (const w of r.wds) {
      if (byKey.has(`${r.slotId}|${w.wdId}`)) active++;
    }
    const remain = r.wds.length - active;
    console.log('  ', r.kst, ' ', r.utc, '  ', (r.status || '?').padEnd(8),
      String(r.wds.length).padEnd(5), String(active).padEnd(9), remain,
      remain > 0 ? '' : '  ← 이 날짜는 0 이 정상');
  }
  console.log('');
  console.log('  to.dates 와 slot KST 날짜 일치:',
    JSON.stringify((to.dates || []).slice().sort()) ===
    JSON.stringify(rows.map((r) => r.kst).sort()) ? 'YES' : 'NO');
})().then(() => process.exit(0)).catch((e) => {
  console.error('PROBE 실패:', e && e.message);
  process.exit(1);
});
