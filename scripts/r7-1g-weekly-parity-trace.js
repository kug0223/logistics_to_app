/**
 * [R7-P1-2 DEVICE.1G §3] 주N회 배지 parity — READ ONLY.
 *
 *   두 화면이 같은 사람·같은 날짜에 대해 만드는 **주간 창**을 각각 재현하고,
 *   그 창으로 센 출근 일수를 비교한다. 쓰기 0. PII 는 가린다.
 */
'use strict';

const {db} = require('./r7-fixture-lib');

const BIZ = 'fLmSOHVKUwmBHcbwQE0I';
const KST = 9 * 3600e3;
const TARGET = '2026-09-28'; // 두 캡처의 대상 날짜

const toMs = (v) => (v && v._seconds != null ? v._seconds * 1000 : null);
const kstStr = (ms) => new Date(ms + KST).toISOString().slice(0, 10);
const kstDayMs = (ms) => {
  const d = new Date(ms + KST);
  return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()) - KST;
};
const WD = ['일', '월', '화', '수', '목', '금', '토'];
const kstWeekdayName = (ms) => WD[new Date(ms + KST).getUTCDay()];
/** ISO weekday 1(월)~7(일), KST 기준 */
const kstIsoWeekday = (ms) => {
  const g = new Date(ms + KST).getUTCDay(); // 0=일
  return g === 0 ? 7 : g;
};

(async () => {
  const targetMs = Date.parse(TARGET + 'T00:00:00+09:00');
  const nowMs = Date.now();
  console.log('═══ [R7-1G] 주간 배지 parity (READ ONLY) ═══');
  console.log(`대상 날짜 = ${TARGET} (${kstWeekdayName(targetMs)}, ISO ${kstIsoWeekday(targetMs)})`);
  console.log(`오늘(KST) = ${kstStr(nowMs)} (${kstWeekdayName(nowMs)}, ISO ${kstIsoWeekday(nowMs)})`);

  // ── 공고 식별 ──────────────────────────────────────────────
  const tos = await db.collection('tos').where('businessId', '==', BIZ).get();
  const target = tos.docs.find((d) =>
    String(d.data().title || '').includes('부족 남은 공고'));
  if (!target) { console.log('공고를 찾지 못했다'); process.exit(0); }
  const to = target.data();
  console.log(`\n── TO ${target.id.slice(0, 8)}… "${to.title}" type=${to.type} status=${to.status}`);
  console.log(`   rangeEnd = ${toMs(to.rangeEnd) ? kstStr(toMs(to.rangeEnd)) : null}`);

  const slots = await db.collection('tos').doc(target.id).collection('slots').get();
  console.log(`   slots = ${slots.size}건`);
  let targetSlotId = null;
  slots.forEach((s) => {
    const m = toMs(s.data().date);
    if (m == null) return;
    const mark = kstStr(m) === TARGET ? '  ← 대상' : '';
    console.log(`     ${s.id.slice(0, 8)}… ${kstStr(m)}${mark}`);
    if (kstStr(m) === TARGET) targetSlotId = s.id;
  });

  // ── 해당 공고의 확정자 ──────────────────────────────────────
  const apps = await db.collection('applications')
      .where('toId', '==', target.id).get();
  console.log(`\n── applications ${apps.size}건 ──`);
  const confirmed = [];
  apps.forEach((s) => {
    const a = s.data();
    if (!['CONFIRMED', 'CONTRACT_PENDING'].includes(a.status)) return;
    confirmed.push({id: s.id, uid: a.uid, slotId: a.slotId, status: a.status,
      workDate: toMs(a.workDate)});
    console.log(`   app ${s.id.slice(0, 6)}… uid=${a.uid.slice(0, 6)}… ` +
        `status=${a.status} slotId=${String(a.slotId || '').slice(0, 8)}… ` +
        `workDate=${toMs(a.workDate) ? kstStr(toMs(a.workDate)) : null}`);
  });
  if (confirmed.length === 0) { console.log('확정자 없음'); process.exit(0); }

  // ── 두 화면의 주간 창 재현 ─────────────────────────────────
  //
  //   DayApplicants  : weekStart = date - (date.weekday - 1)   ← WeekHelper 미사용
  //                    `date.weekday` 는 **기기 달력** 성분이다.
  //   WorkApplicants : WeekHelper.weekStart(slotDate ?? now)   ← KST 정규화
  //
  const windows = [];

  // (1) DayApplicants — 기기가 KST 인 경우
  {
    const iso = kstIsoWeekday(targetMs);
    const ws = targetMs - (iso - 1) * 86400e3;
    windows.push({name: 'DayApplicants (기기=KST)', ws, we: ws + 6 * 86400e3});
  }
  // (2) DayApplicants — 기기가 UTC 인 경우: date.weekday 가 UTC 성분이다
  {
    const g = new Date(targetMs).getUTCDay(); // KST 자정 instant 의 UTC 요일
    const iso = g === 0 ? 7 : g;
    const ws = targetMs - (iso - 1) * 86400e3;
    windows.push({name: 'DayApplicants (기기=UTC)', ws, we: ws + 6 * 86400e3,
      note: `UTC 요일 = ${WD[g]} (KST 요일과 다름)`});
  }
  // (3) WorkApplicants — 기준일이 대상 슬롯 날짜
  {
    const base = kstDayMs(targetMs);
    const ws = base - (kstIsoWeekday(base) - 1) * 86400e3;
    windows.push({name: 'WorkApplicants (기준=슬롯 날짜)', ws, we: ws + 6 * 86400e3});
  }
  // (4) WorkApplicants — 기준일이 오늘(슬롯 없음 폴백)
  {
    const base = kstDayMs(nowMs);
    const ws = base - (kstIsoWeekday(base) - 1) * 86400e3;
    windows.push({name: 'WorkApplicants (기준=오늘 폴백)', ws, we: ws + 6 * 86400e3});
  }

  // ── 출근 기록 ──────────────────────────────────────────────
  const atts = await db.collection('attendance')
      .where('businessId', '==', BIZ).get();
  const byUid = {};
  atts.forEach((s) => {
    const a = s.data();
    const wd = toMs(a.workDate);
    if (wd == null) return;
    (byUid[a.userId] ||= []).push({
      wd, status: a.status, checkIn: a.checkIn ?? null,
    });
  });

  for (const c of confirmed) {
    console.log(`\n══ uid ${c.uid.slice(0, 6)}… 의 주간 카운트 ══`);
    const recs = byUid[c.uid] || [];
    console.log(`   전체 출근문서 ${recs.length}건`);
    recs.sort((x, y) => x.wd - y.wd).slice(-8).forEach((r) => {
      console.log(`     ${kstStr(r.wd)} status=${r.status} checkIn=${r.checkIn}`);
    });
    for (const w of windows) {
      const n = recs.filter((r) =>
        r.checkIn != null && r.status !== 'absent' && r.status !== 'no_show' &&
        kstDayMs(r.wd) >= kstDayMs(w.ws) && kstDayMs(r.wd) <= kstDayMs(w.we)).length;
      console.log(`   ▶ ${w.name.padEnd(30)} ${kstStr(w.ws)}~${kstStr(w.we)}  → 주${n}회` +
          (w.note ? `   [${w.note}]` : ''));
    }
  }

  console.log('\n═══ 쓰기 0건 ═══');
  process.exit(0);
})().catch((e) => { console.error('실패:', e); process.exit(1); });
