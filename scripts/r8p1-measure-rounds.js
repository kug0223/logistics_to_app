/**
 * [R8-PERFORMANCE.1 §14] 라운드 구조 before/after 실측.
 *
 *   개별 callable latency 가 아니라 **임계 네트워크 라운드 수**가 핵심이다.
 *   그래서 같은 DEV 백엔드에 대해 두 모양을 그대로 돌려 비교한다.
 *
 *     BEFORE : [지원서 조회] 끝난 뒤에야 [충원 조회] 시작   (2 라운드)
 *     AFTER  : 둘을 같은 라운드에서 시작                      (1 라운드)
 *
 *   클라이언트의 Firestore 직접 읽기(workTypeDocs·businessById)는 하네스가
 *   Admin SDK 경로라 지연이 다르므로 **측정에서 제외**한다. 지배 항인
 *   callable 왕복만 재고, 보고에 그 한계를 적는다.
 */
'use strict';
const lib = require('./r7-fixture-lib');
const G = require('../.goldenpath.json');

const KST = 9 * 3600000;
const n = new Date(Date.now() + KST);
const dayStart = Date.UTC(n.getUTCFullYear(), n.getUTCMonth(), n.getUTCDate()) - KST;
const dayEnd = dayStart + 86400000;

const APPS = {
  businessId: G.businessId,
  workDateGteMs: dayStart,
  workDateLtMs: dayEnd,
  purpose: 'workerOperation',
  limit: 2000,
};
const LONG = {
  businessId: G.businessId, type: 'long_term',
  purpose: 'workerOperation', limit: 2000,
};
const STAFF = {businessId: G.businessId, dateMs: dayStart};

const call = (fn, d) => lib.callAs(G.adminUid, fn, d);

async function before() {
  const t0 = Date.now();
  // 라운드 1 — 지원서(단기·장기) 병렬
  await Promise.all([
    call('callableGetApplicationsByBiz', APPS),
    call('callableGetApplicationsByBiz', LONG),
  ]);
  // 라운드 2 — 충원. 앞 결과를 쓰지 않는데도 기다렸다.
  await call('callableGetDayStaffingDetail', STAFF);
  return Date.now() - t0;
}

async function after() {
  const t0 = Date.now();
  // 라운드 1 — 셋을 같은 라운드에서
  await Promise.all([
    call('callableGetApplicationsByBiz', APPS),
    call('callableGetApplicationsByBiz', LONG),
    call('callableGetDayStaffingDetail', STAFF),
  ]);
  return Date.now() - t0;
}

const med = (a) => a.slice().sort((x, y) => x - y)[Math.floor(a.length / 2)];

(async () => {
  console.log(`DEV ${lib.EXPECTED_PROJECT} | KST ${n.toISOString().slice(0, 16)}`);
  // 워밍업 — 콜드스타트를 측정에서 분리한다(콜드는 §B 표에 따로 있다).
  console.log('워밍업…');
  await before();

  const b = [];
  const a = [];
  for (let i = 0; i < 4; i++) {
    b.push(await before());
    a.push(await after());
  }
  console.log('\nBEFORE (2 라운드):', b.join(', '), 'ms  → 중위', med(b) + 'ms');
  console.log('AFTER  (1 라운드):', a.join(', '), 'ms  → 중위', med(a) + 'ms');
  const d = med(b) - med(a);
  console.log(`\n차이: ${d}ms (${Math.round(d / med(b) * 100)}% 감소)`);
  console.log('\n주의 — 이것은 callable 왕복만이다. 콜드일 때는 라운드마다');
  console.log('함수별 콜드스타트가 더해지므로 절감폭이 훨씬 커진다(§B 표 참고).');
  process.exit(0);
})().catch((e) => { console.error('실패:', e.message); process.exit(1); });
