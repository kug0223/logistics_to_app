/**
 * [R7-P1-2 DEVICE.1E §3/§11] WorkApplicants 다이얼로그 정원 조회 READ-ONLY 추적.
 *
 *   쓰기 0. 실제 callable 을 클라이언트와 같은 purpose 로 호출해서
 *   "무엇이 실패했는가"를 화면 문구가 아니라 응답으로 확인한다.
 *
 *   PII 는 출력하지 않는다 — 이름·연락처·uid 는 마스킹한다.
 */
'use strict';

const {admin, db, callAs} = require('./r7-fixture-lib');

const TO_ID = process.env.TRACE_TO_ID || 'zqaJEjUVPA6O1FWajlTX';
const BIZ = 'fLmSOHVKUwmBHcbwQE0I';
const OWNER = 'BErRdiWP1xbgyoTovxwAPNEsuD72';

const mask = (s) => (s ? String(s).slice(0, 6) + '…' : String(s));
const d = (v) => {
  if (!v) return null;
  const ms = v._seconds != null ? v._seconds * 1000
      : (typeof v.toMillis === 'function' ? v.toMillis() : Date.parse(v));
  if (Number.isNaN(ms)) return String(v);
  return new Date(ms + 9 * 3600 * 1000).toISOString().slice(0, 16) + ' KST';
};

(async () => {
  console.log('═══ [R7-1E] 다이얼로그 정원 조회 추적 (READ ONLY) ═══');
  console.log('오늘(KST) =', new Date(Date.now() + 9 * 3600e3).toISOString().slice(0, 10));
  console.log('TO =', TO_ID);

  // ── 1. TO 문서: workDetail identity ──────────────────────────────
  const toSnap = await db.collection('tos').doc(TO_ID).get();
  if (!toSnap.exists) { console.log('TO 없음'); process.exit(1); }
  const to = toSnap.data();
  console.log('\n── TO ──');
  console.log('  title      =', to.title);
  console.log('  status     =', to.status, '| type =', to.type);
  console.log('  rangeStart =', d(to.rangeStart), '| rangeEnd =', d(to.rangeEnd));
  console.log('  isLongTerm =', to.isLongTerm, '| wageType =', to.wageType);

  const wds = to.workDetails || [];
  console.log('\n── workDetails (identity) ──');
  wds.forEach((w, i) => {
    const compositeId = `${w.workType}_${w.startTime}_${w.endTime}`;
    console.log(`  [${i}] workType=${w.workType} ${w.startTime}~${w.endTime}`);
    console.log(`       wdId          = ${w.wdId === undefined ? '(필드없음)' : JSON.stringify(w.wdId)}`);
    console.log(`       canonicalId   = ${w.wdId || compositeId}`);
    console.log(`       composite id  = ${compositeId}`);
    console.log(`       requiredCount = ${w.requiredCount} | wage = ${w.wage}`);
  });

  // ── 2. Admin SDK 로 본 Application 진실 ──────────────────────────
  const appsSnap = await db.collection('applications').where('toId', '==', TO_ID).get();
  console.log(`\n── applications (admin 직접 읽기, ${appsSnap.size}건) ──`);
  const today = new Date(Date.now() + 9 * 3600e3);
  const todayKst = Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate());
  appsSnap.forEach((s) => {
    const a = s.data();
    const endRaw = a.actualResignDate || a.workEndDate;
    // Application 문서의 장기/단기 판별 필드는 `type` 이다.
    const isLong = a.type === 'long_term' || a.isLongTerm === true;
    let occupies = `(단기→true, type=${JSON.stringify(a.type)})`;
    if (isLong) {
      if (!endRaw) occupies = 'true (종료일 없음)';
      else {
        const ms = endRaw._seconds * 1000;
        const e = new Date(ms + 9 * 3600e3);
        const eKst = Date.UTC(e.getUTCFullYear(), e.getUTCMonth(), e.getUTCDate());
        occupies = String(eKst >= todayKst);
      }
    }
    console.log(`  app ${mask(s.id)} uid=${mask(a.uid)}`);
    console.log(`     status=${a.status} type=${a.applicationType}`);
    console.log(`     wdId=${JSON.stringify(a.wdId)} workDetailId=${JSON.stringify(a.workDetailId)}`);
    console.log(`     selectedWorkType=${a.selectedWorkType} ${a.startTime}~${a.endTime}`);
    console.log(`     workDate=${d(a.workDate)} desiredStartDate=${d(a.desiredStartDate)}`);
    console.log(`     confirmedAt=${d(a.confirmedAt)} appliedAt=${d(a.appliedAt)}`);
    console.log(`     workEndDate=${d(a.workEndDate)} actualResignDate=${d(a.actualResignDate)}`);
    console.log(`     renewalDecision=${JSON.stringify(a.renewalDecision)} staffingReleasedAt=${d(a.staffingReleasedAt)}`);
    console.log(`     contractId=${a.contractId ? mask(a.contractId) : null}`);
    console.log(`     ▶ occupiesSeatOn(오늘) = ${occupies}`);
  });

  // ── 3. 클라이언트와 같은 호출: purpose=capacity ──────────────────
  for (const purpose of ['capacity', 'applicantReview']) {
    console.log(`\n── callableGetApplicationsByBiz  purpose=${purpose} (as OWNER) ──`);
    try {
      const r = await callAs(OWNER, 'callableGetApplicationsByBiz',
          {businessId: BIZ, toId: TO_ID, purpose});
      const items = r.applications || r.items || [];
      console.log(`  ✅ 성공 — ${items.length}건`);
      items.forEach((a) => {
        console.log(`     ${mask(a.id)} status=${a.status} wdId=${JSON.stringify(a.wdId)} ` +
            `workDetailId=${JSON.stringify(a.workDetailId)} type=${a.selectedWorkType} ` +
            `${a.startTime}~${a.endTime} workEndDate=${d(a.workEndDate)} ` +
            `actualResignDate=${d(a.actualResignDate)}`);
        console.log(`       필드수=${Object.keys(a).length} 키=${Object.keys(a).sort().join(',')}`);
      });

      if (purpose === 'capacity') {
        // 클라이언트 loadTOWorkDetails 가 만들 workStats 를 그대로 재현한다.
        const workStats = {};
        for (const w of wds) workStats[`${w.workType}_${w.startTime}_${w.endTime}`] = {confirmed: 0, pending: 0};
        const ACTIVE = ['PENDING', 'CONFIRMED', 'CONTRACT_PENDING'];
        for (const a of items) {
          if (!ACTIVE.includes(a.status)) continue;
          if (a.staffingReleasedAt) continue;
          const endRaw = a.actualResignDate || a.workEndDate;
          const isLong = a.type === 'long_term';
          if (isLong && endRaw) {
            const e = new Date(endRaw._seconds * 1000 + 9 * 3600e3);
            const eKst = Date.UTC(e.getUTCFullYear(), e.getUTCMonth(), e.getUTCDate());
            if (eKst < todayKst) continue; // occupiesSeatOn=false
          }
          const canonical = a.wdId;
          const legacy = a.workDetailId;
          const key = (canonical) ? canonical
              : (legacy && legacy !== a.selectedWorkType) ? legacy
                  : `${a.selectedWorkType}_${a.startTime}_${a.endTime}`;
          workStats[key] = workStats[key] || {confirmed: 0, pending: 0};
          if (['CONFIRMED', 'CONTRACT_PENDING'].includes(a.status)) workStats[key].confirmed++;
          else workStats[key].pending++;
        }
        console.log('\n  ▶ 클라이언트가 만들 workStats =', JSON.stringify(workStats));
        for (const w of wds) {
          const composite = `${w.workType}_${w.startTime}_${w.endTime}`;
          const canonicalId = w.wdId || composite;
          const hit = workStats[canonicalId] || workStats[composite];
          console.log(`  ▶ lookupByIdentity(${w.workType}) = ${JSON.stringify(hit) || 'null'}` +
              `  → _canonicalConfirmed = ${hit ? hit.confirmed : 'null → UNKNOWN(정원 확인 불가)'}`);
        }
      }
    } catch (e) {
      console.log(`  ❌ 실패 wireCode=${e.wireCode} http=${e.httpStatus}`);
      console.log(`     ${e.message}`);
    }
  }

  console.log('\n═══ 쓰기 0건 — READ ONLY 종료 ═══');
  process.exit(0);
})().catch((e) => { console.error('추적 실패:', e); process.exit(1); });
