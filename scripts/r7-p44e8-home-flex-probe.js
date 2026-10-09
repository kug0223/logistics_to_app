/**
 * [R7-P4.4E.8 §4] Home flex silent exclusion — DEVICE fixture identity 매핑.
 *   READ ONLY. 쓰기 0. PII 는 가린다.
 *
 * 찾는 것: 같은 slot(날짜)에 '냉장분류' 와 '냉동분류' 가 함께 있는 flex 공고와
 *   그 날짜에 대한 이 사용자의 지원서. 추측하지 않고 실제 id 를 찍는다.
 */
'use strict';

const {db} = require('./r7-fixture-lib');

const mask = (s) => (!s ? '(없음)' : s.length <= 8 ? s : s.slice(0, 8) + '…');

(async () => {
  console.log('=== 1. 냉장/냉동 분류를 가진 공고 탐색 ===');
  const tos = await db.collection('tos').limit(200).get();
  console.log('   tos 표본:', tos.size, '건');

  const hits = [];
  for (const doc of tos.docs) {
    const d = doc.data();
    const wds = Array.isArray(d.workDetails) ? d.workDetails : [];
    const names = wds.map((w) => (w && w.workType) || '').filter(Boolean);
    if (names.some((n) => n.includes('냉장') || n.includes('냉동'))) {
      hits.push({id: doc.id, d, names});
    }
  }
  console.log('   냉장/냉동 포함 공고:', hits.length, '건');

  for (const h of hits) {
    const d = h.d;
    console.log('');
    console.log('── toId:', h.id);
    console.log('   type:', d.type, '| status:', d.status,
      '| isDeleted:', d.isDeleted === true, '| isManualClosed:', d.isManualClosed === true);
    console.log('   totalRequired/Confirmed/Pending:',
      d.totalRequired, '/', d.totalConfirmed, '/', d.totalPending);
    console.log('   dates:', Array.isArray(d.dates) ? d.dates.join(',') : '(없음)');
    console.log('   rangeStart:', d.rangeStart ? 'O' : '없음',
      '| rangeEnd:', d.rangeEnd ? 'O' : '없음');
    console.log('   workDetails:');
    for (const w of (d.workDetails || [])) {
      if (!w) continue;
      console.log('     · workType:', w.workType,
        '| wdId:', w.wdId || '(없음)',
        '|', w.startTime, '~', w.endTime,
        '| required:', w.requiredCount,
        '| isManualClosed:', w.isManualClosed === true,
        '| deadline:', w.applicationDeadline ? 'O' : '없음');
    }

    // 슬롯
    const slots = await db.collection('tos').doc(h.id)
      .collection('slots').limit(40).get();
    console.log('   slots:', slots.size, '건');
    for (const s of slots.docs) {
      const sd = s.data();
      const wds = Array.isArray(sd.workDetails) ? sd.workDetails : [];
      const dt = sd.date && sd.date.toDate ? sd.date.toDate().toISOString().slice(0, 10) : '(?)';
      console.log('     slotId:', s.id, '| date:', dt,
        '| status:', sd.status, '| confirmedCount:', sd.confirmedCount);
      for (const w of wds) {
        if (!w) continue;
        console.log('        · ', w.workType, '| wdId:', w.wdId || '(없음)',
          '|', w.startTime, '~', w.endTime, '| required:', w.requiredCount);
      }
    }

    // 이 공고에 대한 지원서 전수
    const apps = await db.collection('applications')
      .where('toId', '==', h.id).limit(50).get();
    console.log('   applications:', apps.size, '건');
    for (const a of apps.docs) {
      const ad = a.data();
      const wd = ad.workDate && ad.workDate.toDate
        ? ad.workDate.toDate().toISOString().slice(0, 10) : '(?)';
      console.log('     appId:', a.id);
      console.log('        uid:', mask(ad.uid), '| status:', ad.status,
        '| slotId:', ad.slotId || '(없음)',
        '| wdId:', ad.wdId || '(없음)');
      console.log('        selectedWorkType:', ad.selectedWorkType,
        '|', ad.startTime, '~', ad.endTime, '| workDate:', wd);
      console.log('        resignStatus:', ad.resignStatus || '-',
        '| terminationStatus:', ad.terminationStatus || '-');
    }
  }

  if (hits.length === 0) {
    console.log('');
    console.log('   → 표본에서 찾지 못했다. 전체 공고 요약으로 대체한다.');
    for (const doc of tos.docs.slice(0, 20)) {
      const d = doc.data();
      const names = (d.workDetails || []).map((w) => w && w.workType).filter(Boolean);
      console.log('   ', doc.id, '|', d.type, '|', d.status,
        '| wd:', names.join('/') || '(없음)');
    }
  }
})().then(() => process.exit(0)).catch((e) => {
  console.error('PROBE 실패:', e && e.message);
  process.exit(1);
});
