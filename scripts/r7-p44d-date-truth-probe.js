/**
 * [R7-P4.4D §10] TO 날짜 진실 축 — READ ONLY. 쓰기 0.
 *
 * 묻는 것:
 *   1) tos 문서에 `dates` 필드가 실제로 존재하는가 (reader 는 읽는데 writer 가 없다)
 *   2) FLEX 공고의 TO-level 날짜 축이 무엇인가 (rangeStart/rangeEnd/date)
 *   3) slot 문서의 날짜 축과 TO 축이 일치하는가
 *   4) totalSlots 와 실제 slot 수가 일치하는가 (slotDatesLookComplete 전제)
 */
'use strict';

const {db} = require('./r7-fixture-lib');

const KST = 9 * 3600e3;
const toMs = (v) => (v && v._seconds != null ? v._seconds * 1000 : null);
const kstKey = (ms) => (ms == null ? null : new Date(ms + KST).toISOString().slice(0, 10));

(async () => {
  const snap = await db.collection('tos').limit(400).get();
  console.log('tos 표본:', snap.size, '건');

  let hasDates = 0;
  let datesNonEmpty = 0;
  const flex = [];

  for (const d of snap.docs) {
    const x = d.data();
    if (Object.prototype.hasOwnProperty.call(x, 'dates')) {
      hasDates++;
      if (Array.isArray(x.dates) && x.dates.length > 0) datesNonEmpty++;
    }
    const isFlex = x.workType === 'FLEX' || x.toType === 'FLEX' ||
      x.recruitType === 'FLEX' || x.isFlexType === true ||
      (x.totalSlots != null && x.totalSlots > 0);
    if (isFlex) flex.push({id: d.id, x});
  }

  console.log('\n=== §10-A  tos.dates 필드 존재 ===');
  console.log('  dates 키 보유:', hasDates, '/', snap.size);
  console.log('  dates 비어있지 않음:', datesNonEmpty, '/', snap.size);

  console.log('\n=== §10-B  슬롯 공고 TO-level 날짜 축 ===');
  console.log('  슬롯 보유 후보:', flex.length, '건');

  let axis = {rangeStart: 0, rangeEnd: 0, date: 0, none: 0};
  for (const {x} of flex) {
    if (toMs(x.rangeStart) != null) axis.rangeStart++;
    if (toMs(x.rangeEnd) != null) axis.rangeEnd++;
    if (toMs(x.date) != null) axis.date++;
    if (toMs(x.rangeStart) == null && toMs(x.rangeEnd) == null && toMs(x.date) == null) axis.none++;
  }
  console.log('  rangeStart 보유:', axis.rangeStart);
  console.log('  rangeEnd   보유:', axis.rangeEnd);
  console.log('  date       보유:', axis.date);
  console.log('  셋 다 없음  :', axis.none);

  console.log('\n=== §10-C  totalSlots vs 실제 slot 수 / 날짜 일치 ===');
  const probe = flex.slice(0, 12);
  for (const {id, x} of probe) {
    const slots = await db.collection('tos').doc(id).collection('slots').get();
    const slotKeys = new Set();
    for (const s of slots.docs) {
      const sd = s.data();
      const k = kstKey(toMs(sd.workDate)) ?? kstKey(toMs(sd.date)) ?? sd.dateKey ?? null;
      if (k) slotKeys.add(k);
    }
    const declared = Array.isArray(x.dates) ? x.dates.length : 0;
    const lookComplete = declared > 0 && (x.totalSlots ?? 0) <= declared;
    console.log(
      '  ', id.slice(0, 8),
      '| totalSlots=', x.totalSlots ?? '(없음)',
      '| 실제slot=', slots.size,
      '| slot날짜=', slotKeys.size,
      '| dates길이=', declared,
      '| slotDatesLookComplete=', lookComplete,
      '| rangeEnd=', kstKey(toMs(x.rangeEnd)) ?? '-',
    );
  }

  console.log('\n쓰기 0. READ ONLY 종료.');
  process.exit(0);
})().catch((e) => {
  console.error('probe 실패:', e.message);
  process.exit(1);
});
