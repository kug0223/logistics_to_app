/**
 * [R7-P1-2 DEVICE.1F §5] PRODUCT 캡처 후보 — READ ONLY.
 *
 *   `TOGroupItem.operationEndDate` 의 **수정된** source 선택을 그대로 적용한다.
 *     CONTRACT → rangeEnd
 *     FLEX     → 실제 마지막 슬롯 날짜 (master rangeEnd 아님)
 *     둘 다 없으면 UNKNOWN — 끝났다고 단정하지 않는다.
 *
 *   쓰기 0. 제목/식별자 일부만 출력.
 */
'use strict';

const {db} = require('./r7-fixture-lib');

const BIZ = 'fLmSOHVKUwmBHcbwQE0I';
const KST = 9 * 3600e3;
const kstDay = (ms) => {
  const d = new Date(ms + KST);
  return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate());
};
const toMs = (v) => (v && v._seconds != null ? v._seconds * 1000 : null);
const day = (ms) => new Date(ms + KST).toISOString().slice(0, 10);

(async () => {
  const today = kstDay(Date.now());
  console.log('═══ [R7-1F] 캡처 후보 (READ ONLY) ═══');
  console.log('오늘(KST) =', new Date(today).toISOString().slice(0, 10));

  const snap = await db.collection('tos').where('businessId', '==', BIZ).get();
  const buckets = {ACTIVE: [], CLOSED_ACTIVE: [], PAST_ENDED: [], UNKNOWN_END: []};

  for (const s of snap.docs) {
    const to = s.data();
    if (to.isDeleted === true) continue;

    let endMs = null;
    if (to.type === 'flex') {
      const slots = await db.collection('tos').doc(s.id).collection('slots').get();
      const ds = [];
      slots.forEach((x) => { const m = toMs(x.data().date); if (m) ds.push(m); });
      endMs = ds.length ? Math.max(...ds) : null;
    } else {
      endMs = toMs(to.rangeEnd);
    }

    // recruitmentClosed — status/manual close 만으로 본다(날짜 폴백은 클라이언트).
    const closed = to.status === 'CLOSED' || to.isManualClosed === true;

    let key;
    if (endMs == null) key = 'UNKNOWN_END';
    else if (kstDay(endMs) < today) key = 'PAST_ENDED';
    else key = closed ? 'CLOSED_ACTIVE' : 'ACTIVE';

    buckets[key].push({
      id: s.id.slice(0, 8) + '…',
      title: String(to.title || '').slice(0, 24),
      type: to.type,
      status: to.status,
      end: endMs == null ? null : day(endMs),
    });
  }

  for (const k of ['PAST_ENDED', 'CLOSED_ACTIVE', 'ACTIVE', 'UNKNOWN_END']) {
    console.log(`\n── ${k} : ${buckets[k].length}건 ──`);
    buckets[k].slice(0, 4).forEach((r) => console.log('  ', JSON.stringify(r)));
    if (buckets[k].length === 0) console.log('   → NOT SEEN');
  }

  console.log('\n═══ 쓰기 0건 ═══');
  process.exit(0);
})().catch((e) => { console.error('실패:', e); process.exit(1); });
