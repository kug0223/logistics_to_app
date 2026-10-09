/**
 * [R7-P4.4E §11/§12] 배포 전 DEV 데이터 preflight — READ ONLY. 쓰기 0.
 *   backfill·repair·cleanup 하지 않는다. 세기만 한다.
 */
'use strict';

const {db} = require('./r7-fixture-lib');

(async () => {
  const counts = {};
  for (const c of ['tos', 'businesses', 'applications', 'users']) {
    // count() aggregate — 문서를 읽지 않는다.
    const agg = await db.collection(c).count().get();
    counts[c] = agg.data().count;
  }
  console.log('=== §11 컬렉션 건수 ===');
  for (const [k, v] of Object.entries(counts)) console.log(' ', k, '=', v, '건');

  if (counts.tos === 0) {
    console.log('\n=== §12 legacy dates ===');
    console.log('  tos 0건 → [R7-P4.4D-LEGACY-DATES-BACKFILL] = N/A 유지');
    console.log('  migration 만들지 않았다.');
    process.exit(0);
  }

  const snap = await db.collection('tos').get();
  let flex = 0;
  let flexMissingDates = 0;
  const rows = [];
  for (const d of snap.docs) {
    const x = d.data();
    const isFlex = x.type === 'flex' || x.totalSlots > 0;
    if (!isFlex) continue;
    flex++;
    const hasDates = Array.isArray(x.dates) && x.dates.length > 0;
    if (!hasDates) flexMissingDates++;
    rows.push({
      id: d.id.slice(0, 8),
      totalSlots: x.totalSlots ?? null,
      datesLen: Array.isArray(x.dates) ? x.dates.length : null,
      status: x.status ?? null,
      isPublished: x.isPublished === true,
      createdAt: x.createdAt && x.createdAt._seconds
        ? new Date(x.createdAt._seconds * 1000).toISOString().slice(0, 10) : null,
    });
  }
  console.log('\n=== §11 FLEX ===');
  console.log('  FLEX TO =', flex, '건');
  console.log('  dates 없는 FLEX =', flexMissingDates, '건');
  console.log('\n=== §12 현황 (삭제·수정·backfill 하지 않는다) ===');
  for (const r of rows.slice(0, 30)) {
    console.log('  ', r.id, '| totalSlots=', r.totalSlots,
      '| dates=', r.datesLen ?? '(없음)',
      '| status=', r.status, '| 공개=', r.isPublished, '| 생성=', r.createdAt);
  }
  console.log('\n쓰기 0. READ ONLY 종료.');
  process.exit(0);
})().catch((e) => { console.error('preflight 실패:', e.message); process.exit(1); });
