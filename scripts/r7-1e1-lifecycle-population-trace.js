/**
 * [R7-P1-2 DEVICE.1E.1 §10] lifecycle 4분류의 자연 표본 — READ ONLY.
 *
 *   `staffingRelationOf` 의 판정을 DEV 실제 데이터에 그대로 적용해서
 *   각 분류가 자연히 존재하는지 센다. 쓰기 0. PII 출력 없음(집계만).
 *
 *   분류(제품 코드와 같은 순서):
 *     1) 좌석 아님 + 결정 남음  → 계약 확인 필요
 *     2) 좌석 아님 + 결정 끝남  → 계약 종료
 *     3) 좌석 있음 + 반납       → 좌석 반납
 *     4) 좌석 있음              → 확정(현재 인력)
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

(async () => {
  const today = kstDay(Date.now());
  console.log('═══ [R7-1E.1] lifecycle 모집단 (READ ONLY) ═══');
  console.log('오늘(KST) =', new Date(today).toISOString().slice(0, 10));

  const snap = await db.collection('applications')
      .where('businessId', '==', BIZ).get();

  const CONFIRMED_LIKE = ['CONFIRMED', 'CONTRACT_PENDING'];
  const buckets = {
    current: 0, released: 0, decisionPending: 0, resolvedEnded: 0,
    shortTerm: 0, noEndDate: 0,
  };
  const samples = {};

  snap.forEach((s) => {
    const a = s.data();
    if (!CONFIRMED_LIKE.includes(a.status)) return;

    const isLong = a.type === 'long_term';
    const releasedAt = toMs(a.staffingReleasedAt);
    const endMs = toMs(a.actualResignDate) || toMs(a.workEndDate);

    // occupiesSeatOn — 제품과 같은 식
    let occupies;
    if (!isLong) { occupies = true; buckets.shortTerm++; }
    else if (endMs == null) { occupies = true; buckets.noEndDate++; }
    else occupies = kstDay(endMs) >= today;

    let key;
    if (!occupies) {
      // renewalDecisionStateOf — 결정이 끝났는가
      const resolved = a.renewalDecision != null ||
          ['APPROVED', 'AUTO_APPROVED'].includes(a.resignStatus) ||
          ['APPROVED', 'AUTO_APPROVED'].includes(a.terminationStatus);
      key = resolved ? 'resolvedEnded' : 'decisionPending';
    } else if (releasedAt != null) {
      key = 'released';
    } else {
      key = 'current';
    }
    buckets[key]++;
    if (!samples[key]) {
      samples[key] = {
        app: s.id.slice(0, 6) + '…',
        toId: (a.toId || '').slice(0, 6) + '…',
        status: a.status,
        type: a.type,
        end: endMs ? new Date(endMs + KST).toISOString().slice(0, 10) : null,
        renewalDecision: a.renewalDecision ?? null,
        released: releasedAt != null,
      };
    }
  });

  console.log(`\n확정 계열 총 ${Object.values(buckets).reduce((x, y) => x + y, 0) -
      buckets.shortTerm - buckets.noEndDate}건 (단기 ${buckets.shortTerm} · 종료일없음 ${buckets.noEndDate} 포함 집계 별도)`);
  console.log('\n── 분류별 자연 표본 수 ──');
  for (const k of ['current', 'released', 'decisionPending', 'resolvedEnded']) {
    const label = {
      current: '확정(현재 인력)', released: '좌석 반납',
      decisionPending: '계약 확인 필요', resolvedEnded: '계약 종료',
    }[k];
    console.log(`  ${label.padEnd(16)} = ${buckets[k]}` +
        (buckets[k] === 0 ? '   → NOT SEEN (자연 표본 없음)' : ''));
    if (samples[k]) console.log(`     예: ${JSON.stringify(samples[k])}`);
  }

  console.log('\n═══ 쓰기 0건 ═══');
  process.exit(0);
})().catch((e) => { console.error('추적 실패:', e); process.exit(1); });
