/**
 * [R7-P1-2 DEVICE.1F §5] test8 공고의 운영 종료 분류 — READ ONLY.
 *
 *   `operationEndDate` resolver 의 **입력**을 raw source 로 제출한다.
 *   '계약 1개월' 은 근로자 계약 기간일 수 있으므로 Posting end 로 가정하지 않는다.
 *   쓰기 0. PII 출력 없음.
 */
'use strict';

const {db} = require('./r7-fixture-lib');

const KST = 9 * 3600e3;
const kstDay = (ms) => {
  const d = new Date(ms + KST);
  return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate());
};
const toMs = (v) => (v && v._seconds != null ? v._seconds * 1000 : null);
const fmt = (v) => {
  const ms = toMs(v);
  return ms == null ? null : new Date(ms + KST).toISOString().slice(0, 16) + ' KST';
};

(async () => {
  const today = kstDay(Date.now());
  console.log('═══ [R7-1F] test8 운영 종료 분류 (READ ONLY) ═══');
  console.log('오늘(KST) =', new Date(today).toISOString().slice(0, 10));

  // 제목으로 후보를 찾는다 — 정확한 TO 를 먼저 식별한다.
  const snap = await db.collection('tos').get();
  const hits = [];
  snap.forEach((s) => {
    const t = s.data().title || '';
    if (/test\s*8/i.test(t) || t.trim() === 'test8') hits.push(s);
  });

  if (hits.length === 0) {
    console.log('\ntest8 제목의 TO 를 찾지 못했다 → 식별 실패로 기록한다.');
    process.exit(0);
  }
  console.log(`\n후보 ${hits.length}건`);

  for (const s of hits) {
    const to = s.data();
    console.log('\n──────────────────────────────────────────');
    console.log('  toId       =', s.id.slice(0, 8) + '…');
    console.log('  title      =', to.title);
    console.log('  type       =', to.type, '| status =', to.status);
    console.log('  isManualClosed =', to.isManualClosed,
        '| closedAt =', fmt(to.closedAt));
    console.log('  rangeStart =', fmt(to.rangeStart));
    console.log('  rangeEnd   =', fmt(to.rangeEnd));
    console.log('  date       =', fmt(to.date));
    console.log('  createdAt  =', fmt(to.createdAt));
    console.log('  totalSlots =', to.totalSlots,
        '| totalRequired =', to.totalRequired,
        '| totalConfirmed =', to.totalConfirmed);
    console.log('  contractMonths/period =',
        JSON.stringify(to.contractMonths ?? to.contractPeriod ?? null));
    (to.workDetails || []).forEach((w, i) => {
      console.log(`  wd[${i}] ${w.workType} ${w.startTime}~${w.endTime} ` +
          `required=${w.requiredCount} wdId=${JSON.stringify(w.wdId)}`);
    });

    // FLEX 면 실제 슬롯이 canonical 운영 truth 다.
    const slots = await db.collection('tos').doc(s.id).collection('slots')
        .orderBy('date').get();
    console.log(`  slots      = ${slots.size}건`);
    if (slots.size > 0) {
      const dates = [];
      slots.forEach((x) => { const m = toMs(x.data().date); if (m) dates.push(m); });
      dates.sort((a, b) => a - b);
      console.log('    first =', fmt({_seconds: dates[0] / 1000}));
      console.log('    last  =', fmt({_seconds: dates[dates.length - 1] / 1000}));
    }

    // ── resolver 입력 재현 (TOGroupItem.operationEndDate) ──
    const isFlex = to.type === 'flex';
    let opEndMs = null;
    let src;
    if (!isFlex) {
      opEndMs = toMs(to.rangeEnd);
      src = 'CONTRACT → rangeEnd';
    } else if (slots.size > 0) {
      const dates = [];
      slots.forEach((x) => { const m = toMs(x.data().date); if (m) dates.push(m); });
      opEndMs = dates.length ? Math.max(...dates) : null;
      src = 'FLEX → 마지막 슬롯 날짜';
    } else {
      src = 'FLEX → 슬롯 없음 (UNKNOWN)';
    }

    console.log('\n  ▶ operationEndDate source =', src);
    console.log('  ▶ operationEnd =', opEndMs == null ? 'null (모름)' : fmt({_seconds: opEndMs / 1000}));

    // recruitmentClosed — TOGroupItem.isClosed 의 입력만 제출(판정은 클라이언트)
    console.log('  ▶ recruitment close 입력: status =', to.status,
        ', isManualClosed =', to.isManualClosed,
        ', closedAt =', fmt(to.closedAt));

    let mode;
    if (opEndMs != null && kstDay(opEndMs) < today) {
      mode = 'PAST_ENDED (운영 종료 증명됨)';
    } else if (opEndMs == null) {
      mode = 'operationEnd UNKNOWN → 끝났다고 단정하지 않는다';
    } else {
      mode = '운영 기간 잔존 → 모집 마감이면 CLOSED_ACTIVE';
    }
    console.log('  ▶ 분류 =', mode);
  }

  console.log('\n═══ 쓰기 0건 ═══');
  process.exit(0);
})().catch((e) => { console.error('추적 실패:', e); process.exit(1); });
