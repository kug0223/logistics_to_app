/**
 * [R8-PERFORMANCE §3 · §16] 읽기 경로 callable 실지연 측정 (DEV).
 *
 *   §3 — DEVICE profiling 이 불가능하므로 측정 등급을 분리한다.
 *   여기서 재는 것은 **callable 왕복 시간**이다(네트워크 + CF 실행 + Firestore).
 *   first meaningful paint 는 재지 못한다 — NOT MEASURED 로 보고한다.
 *
 *   콜드/웜을 나눈다. minInstances 가 제거돼 있어(이전 R8) 첫 호출은
 *   콜드스타트를 포함할 수 있고, 그게 관리자가 실제로 겪는 첫 진입이다.
 */
'use strict';
const lib = require('./r7-fixture-lib');
const {db} = lib;
const G = require('../.goldenpath.json');

const KST = 9 * 3600000;
const nowKst = new Date(Date.now() + KST);
const year = nowKst.getUTCFullYear();
const month = nowKst.getUTCMonth() + 1;
const ym = `${year}-${String(month).padStart(2, '0')}`;
const dayStartMs = Date.UTC(year, month - 1, nowKst.getUTCDate()) - KST;
const monthStartMs = Date.UTC(year, month - 1, 1) - KST;
const monthEndMs = Date.UTC(year, month, 1) - KST;

async function time(uid, fn, data) {
  const t0 = Date.now();
  try {
    const r = await lib.callAs(uid, fn, data);
    return {ms: Date.now() - t0, ok: true, size: JSON.stringify(r ?? {}).length};
  } catch (e) {
    return {ms: Date.now() - t0, ok: false, err: String(e.message).slice(0, 70)};
  }
}

const CASES = [
  // [surface, label, fn, data]
  ['Home', 'AdminHomeSummary', 'callableGetAdminHomeSummary', {}],
  ['Home', 'StaffingReadiness', 'callableGetStaffingReadiness', {}],
  ['Posting', 'AdminTOs(전체)', 'callableGetAdminTOs',
    {activeOnly: false, closedOnly: false, businessIds: [G.businessId]}],
  ['Attendance', 'AdminAttendances(월)', 'callableGetAdminAttendances',
    {businessId: G.businessId, startMs: monthStartMs, endMs: monthEndMs}],
  ['Attendance', 'DayStaffingDetail', 'callableGetDayStaffingDetail',
    {businessId: G.businessId, dateMs: dayStartMs}],
  ['Attendance', 'ApplicationsByBiz', 'callableGetApplicationsByBiz',
    {businessId: G.businessId, statuses: ['CONFIRMED', 'CONTRACT_PENDING']}],
  ['Payroll', 'PayrollSummaries(연)', 'callableGetPayrollSummaries',
    {businessId: G.businessId, year}],
  ['Payroll', 'AdminAttendances(연 12개월)', 'callableGetAdminAttendances',
    {businessId: G.businessId, yearMonthGte: `${year}-01`,
      yearMonthLte: `${year}-12`}],
];

(async () => {
  const admin = G.adminUid;
  // usersBatch 는 대상 uid 가 필요하다 — 확정 근로자에서 뽑는다.
  const apps = await db.collection('applications')
    .where('businessId', '==', G.businessId).limit(10).get();
  const uids = [...new Set(apps.docs.map((d) => d.data().uid))].filter(Boolean);
  if (uids.length > 0) {
    CASES.push(['Attendance', `UsersBatch(${uids.length}명)`,
      'callableGetUsersBatch', {uids, businessId: G.businessId,
        purpose: 'workerDirectory'}]);
  }

  console.log(`DEV ${lib.EXPECTED_PROJECT} | KST ${nowKst.toISOString().slice(0, 16)}`);
  console.log(`사업장 1개 · 지원서 ${apps.size}건 표본 · ym=${ym}\n`);
  console.log('surface      호출                          콜드    웜(3회 중위)  응답크기');
  console.log('─'.repeat(78));

  const out = [];
  for (const [surface, label, fn, data] of CASES) {
    const cold = await time(admin, fn, data);
    const warms = [];
    for (let i = 0; i < 3; i++) warms.push(await time(admin, fn, data));
    const okWarms = warms.filter((w) => w.ok).map((w) => w.ms).sort((a, b) => a - b);
    const med = okWarms.length ? okWarms[Math.floor(okWarms.length / 2)] : null;
    const row = {surface, label, cold: cold.ms, warm: med,
      ok: cold.ok, err: cold.err, size: cold.size ?? 0};
    out.push(row);
    console.log(
      surface.padEnd(12),
      label.padEnd(28),
      String(cold.ms).padStart(5) + 'ms',
      String(med ?? '-').padStart(10) + 'ms',
      String(row.size).padStart(9),
      cold.ok ? '' : '  ← ' + cold.err);
  }

  console.log('\n=== surface 별 임계 경로 합 (웜 중위 기준) ===');
  const bySurface = {};
  for (const r of out) {
    if (r.warm == null) continue;
    (bySurface[r.surface] ??= []).push(r);
  }
  for (const [s, rows] of Object.entries(bySurface)) {
    const parallelMax = Math.max(...rows.map((r) => r.warm));
    const serialSum = rows.reduce((a, r) => a + r.warm, 0);
    console.log(`  ${s.padEnd(12)} 병렬이면 ${String(parallelMax).padStart(5)}ms` +
      ` · 직렬이면 ${String(serialSum).padStart(5)}ms` +
      ` (호출 ${rows.length}개)`);
  }
  process.exit(0);
})().catch((e) => { console.error('실패:', e.message); process.exit(1); });
