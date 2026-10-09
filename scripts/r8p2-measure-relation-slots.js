/**
 * [R8-PERFORMANCE.2 §16] 관계 슬롯 읽기 라운드 구조 before/after 실측.
 *
 *   `_loadRelationSlots` 가 읽는 것은 `tos/{toId}/slots` 서브컬렉션 쿼리다.
 *   하네스는 Admin SDK 경로라 클라이언트 지연과 **다르다** — 그래서 절대값이
 *   아니라 **직렬 대 병렬의 비**로만 읽는다. 보고에 그 한계를 적는다.
 *
 *   N 은 후보 공고 수가 아니라 내가 활성 지원을 가진 flex 공고 수다.
 *   DEV 실측 최대 2이므로, N=2 와 함께 N 이 커질 때의 모양도 같이 본다.
 */
'use strict';
const lib = require('./r7-fixture-lib');
const {db} = lib;

const readSlots = (toId) =>
  db.collection('tos').doc(toId).collection('slots').get();

async function serial(ids) {
  const t0 = Date.now();
  for (const id of ids) await readSlots(id);
  return Date.now() - t0;
}

async function parallel(ids) {
  const t0 = Date.now();
  await Promise.all(ids.map(readSlots));
  return Date.now() - t0;
}

const med = (a) => a.slice().sort((x, y) => x - y)[Math.floor(a.length / 2)];

(async () => {
  const ACTIVE = ['PENDING', 'CONTRACT_PENDING', 'CONFIRMED', 'INVITED'];
  // 실제 지원자의 활성 flex 공고 집합 = 진짜 N
  const users = await db.collection('users').where('role', '==', 'USER').get();
  let real = [];
  for (const u of users.docs) {
    const apps = await db.collection('applications')
      .where('uid', '==', u.id).get();
    const ids = new Set();
    for (const a of apps.docs) {
      const d = a.data();
      if (!ACTIVE.includes(d.status) || !d.toId) continue;
      const t = await db.collection('tos').doc(d.toId).get();
      if (t.exists && t.data().type === 'flex') ids.add(d.toId);
    }
    if (ids.size > real.length) real = [...ids];
  }
  console.log(`DEV ${lib.EXPECTED_PROJECT}`);
  console.log(`실제 최대 N = ${real.length} (내 활성 flex 공고 수)`);

  // N 이 커질 때의 모양도 본다 — flex 공고 전체를 빌려 쓴다(읽기 비용만 동일).
  const allFlex = await db.collection('tos').where('type', '==', 'flex').get();
  const synthetic = allFlex.docs.map((d) => d.id);
  console.log(`비교용 N = ${synthetic.length} (DEV flex 공고 전체)\n`);

  for (const [label, ids] of [
    [`실제 N=${real.length}`, real],
    [`가상 N=${synthetic.length}`, synthetic],
  ]) {
    if (ids.length === 0) { console.log(`${label}: 표본 없음`); continue; }
    await parallel(ids);                       // 워밍업
    const s = []; const p = [];
    for (let i = 0; i < 4; i++) {
      s.push(await serial(ids));
      p.push(await parallel(ids));
    }
    console.log(`${label}`);
    console.log(`  직렬 ${s.join(', ')} ms → 중위 ${med(s)}ms`);
    console.log(`  병렬 ${p.join(', ')} ms → 중위 ${med(p)}ms`);
    const d = med(s) - med(p);
    console.log(`  차이 ${d}ms (${Math.round(d / med(s) * 100)}% 감소)\n`);
  }
  console.log('읽기 수는 양쪽 모두 N 회로 동일하다 — 라운드만 줄었다.');
  console.log('주의: Admin SDK 경로 측정이므로 절대값이 아니라 비로만 읽는다.');
  process.exit(0);
})().catch((e) => { console.error('실패:', e.message); process.exit(1); });
