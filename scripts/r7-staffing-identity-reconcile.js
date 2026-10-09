/**
 * [R7 Staffing 감사 §7] 원장 → 집계 대조 (READ ONLY, 쓰기 0).
 *
 *   `loadTOWorkDetails` 의 workStats 생성과 `WorkDetailData.lookupByIdentity`
 *   의 조회를 **production 과 같은 순서로** 재현한다.
 *
 *     생성  workStats[w.id] = {0,0}                 ← w.id = composite (항상)
 *           key = app.wdId ?? legacy ?? composite   ← 지원서는 wdId 우선
 *     조회  stats[canonicalId] ?? stats[id]         ← canonicalId = wdId ?? composite
 *
 *   업무 정의(`workDetails`)를 **어디서 가져오는지**에 따라 canonicalId 가
 *   달라진다. slot 문서에는 wdId 가 있고 master TO 에는 없을 수 있다.
 *   그 경우 같은 자리가 slot 기준으로는 1, master 기준으로는 0 이 된다.
 *
 *   PII 출력 없음.
 */
'use strict';

const {db} = require('./r7-fixture-lib');

const BIZ = process.env.AUDIT_BIZ || 'fLmSOHVKUwmBHcbwQE0I';
const KST = 9 * 3600e3;
const day = (ms) => new Date(ms + KST).toISOString().slice(0, 10);
const toMs = (v) => (v && v._seconds != null ? v._seconds * 1000 : null);

const compositeId = (w) => `${w.workType}_${w.startTime}_${w.endTime}`;
const canonicalId = (w) => (w.wdId && w.wdId.length > 0 ? w.wdId : compositeId(w));

/** `loadTOWorkDetails` 의 workStats 생성 재현. */
function buildWorkStats(defs, apps, seatDay) {
  const stats = {};
  for (const w of defs) stats[compositeId(w)] = {confirmed: 0, pending: 0};
  const ACTIVE = ['PENDING', 'CONFIRMED', 'CONTRACT_PENDING'];
  const CONFIRMED = ['CONFIRMED', 'CONTRACT_PENDING'];
  for (const a of apps) {
    if (!ACTIVE.includes(a.status)) continue;
    if (a.staffingReleasedAt) continue;
    // occupiesSeatOn — 장기만 날짜 축이 있다
    if (a.type === 'long_term') {
      const endMs = toMs(a.actualResignDate) || toMs(a.workEndDate);
      if (endMs != null && day(endMs) < day(seatDay)) continue;
    }
    const key = a.wdId && a.wdId.length > 0
      ? a.wdId
      : (a.workDetailId && a.workDetailId.length > 0 &&
         a.workDetailId !== a.selectedWorkType)
          ? a.workDetailId
          : `${a.selectedWorkType}_${a.startTime}_${a.endTime}`;
    stats[key] = stats[key] || {confirmed: 0, pending: 0};
    if (CONFIRMED.includes(a.status)) stats[key].confirmed++;
    else stats[key].pending++;
  }
  return stats;
}

const lookup = (w, stats) => stats[canonicalId(w)] || stats[compositeId(w)] || null;

(async () => {
  const now = Date.now();
  console.log('═══ [R7] Staffing identity 대조 (READ ONLY) ═══');
  console.log('오늘(KST) =', day(now), '| businessId =', BIZ);

  const tos = await db.collection('tos').where('businessId', '==', BIZ).get();
  const mismatches = [];
  let slotsChecked = 0;
  let masterMissingWdId = 0;
  let slotHasWdId = 0;

  for (const d of tos.docs) {
    const to = d.data();
    if (to.isDeleted === true) continue;

    const masterDefs = to.workDetails || [];
    const masterNoWd = masterDefs.length > 0 && masterDefs.every((w) => !w.wdId);
    if (masterNoWd) masterMissingWdId++;

    const apps = (await db.collection('applications')
        .where('toId', '==', d.id).get()).docs.map((s) => s.data());

    const slots = await db.collection('tos').doc(d.id)
        .collection('slots').orderBy('date').get();

    if (slots.size === 0) {
      // contract(장기) — slot 없음. master 정의가 유일한 원천이다.
      const stats = buildWorkStats(masterDefs, apps, now);
      for (const w of masterDefs) {
        const hit = lookup(w, stats);
        const conf = hit ? hit.confirmed : null;
        if (conf === null) {
          mismatches.push({to: to.title, kind: 'CONTRACT_LOOKUP_MISS',
            wd: compositeId(w)});
        }
      }
      continue;
    }

    for (const s of slots.docs) {
      const sd = s.data();
      const slotDefs = sd.workDetails || [];
      const dateStr = day(toMs(sd.date));
      slotsChecked++;
      if (slotDefs.some((w) => w.wdId)) slotHasWdId++;

      const slotApps = apps.filter((a) => a.slotId === s.id);

      // (a) production 이 slotWorkDetails 를 넘긴 경우
      const statsSlot = buildWorkStats(slotDefs.length ? slotDefs : masterDefs,
          slotApps, toMs(sd.date) || now);
      // (b) 같은 stats 를 master 정의로 조회한 경우
      for (let i = 0; i < Math.max(slotDefs.length, masterDefs.length); i++) {
        const sw = slotDefs[i];
        const mw = masterDefs[i];
        if (!sw && !mw) continue;
        const viaSlot = sw ? lookup(sw, statsSlot) : null;
        const viaMaster = mw ? lookup(mw, statsSlot) : null;
        const cSlot = viaSlot ? viaSlot.confirmed : null;
        const cMaster = viaMaster ? viaMaster.confirmed : null;

        // 원장 권위: slot.workDetailCounts
        const wdc = sd.workDetailCounts || {};
        const ledgerKey = sw ? canonicalId(sw) : null;
        const ledger = ledgerKey && wdc[ledgerKey]
          ? wdc[ledgerKey].confirmedCount : null;

        if (cSlot !== cMaster) {
          mismatches.push({
            to: String(to.title).slice(0, 26),
            date: dateStr,
            slot: s.id.slice(0, 8),
            wdSlot: sw ? canonicalId(sw) : null,
            wdMaster: mw ? canonicalId(mw) : null,
            viaSlot: cSlot,
            viaMaster: cMaster,
            slotCounter: sd.confirmedCount ?? null,
            ledgerWdc: ledger,
            kind: 'IDENTITY_SOURCE_DIVERGENCE',
          });
        }
      }
    }
  }

  console.log(`\n표본: TO ${tos.size}건 · slot ${slotsChecked}건`);
  console.log(`master workDetails 에 wdId 가 전부 없는 TO: ${masterMissingWdId}건`);
  console.log(`slot workDetails 에 wdId 가 있는 slot: ${slotHasWdId}건`);

  console.log(`\n── identity 원천에 따라 값이 갈리는 자리: ${mismatches.length}건 ──`);
  for (const m of mismatches.slice(0, 25)) {
    console.log('  ', JSON.stringify(m));
  }
  if (mismatches.length > 25) {
    console.log(`   … 외 ${mismatches.length - 25}건`);
  }

  console.log('\n═══ 쓰기 0건 ═══');
  process.exit(0);
})().catch((e) => { console.error('대조 실패:', e); process.exit(1); });
