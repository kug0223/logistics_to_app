// [R7-APPLICATION-LIFECYCLE.1E.1] 관계 사건 identity — **행동** 테스트.
//
//   실행:  cd functions && npm run build && node test/activation_generation.test.js
//
//   소스 문자열 검색이 아니라 실제 함수를 불러 값을 비교한다. 이 모듈은
//   순수하므로(Firestore·admin SDK 없음) emulator 없이 돌아간다.
//
//   고정하는 것
//     · 같은 사건의 재시도 → 같은 알림 id (무작위 성분 0)
//     · 재활성화 뒤의 자동취소 → 다른 알림 id (새 사건 namespace)
//     · 세대 필드가 없는 legacy 문서 → 0 (crash 없음, backfill 불필요)
//     · 세대는 읽은 snapshot 에서 계산한다 — 같은 snapshot 이면 같은 값
'use strict';
const assert = require('assert');
const M = require('../lib/activation_generation');

let pass = 0;
const fails = [];
function t(id, fn) {
  try {
    fn();
    pass++;
    console.log(`  ok   ${id}`);
  } catch (e) {
    fails.push(`${id}: ${e.message.split('\n')[0]}`);
    console.log(`  FAIL ${id} — ${e.message.split('\n')[0]}`);
  }
}

/** transaction 에서 읽은 관계 문서를 흉내낸다 — exists/data() 만 쓴다. */
const snap = (data) => ({exists: true, data: () => data});
const absent = {exists: false, data: () => undefined};

const APP = 'to1_slot1_wd1_u1';

console.log('\n── EID-1 초기 Application 의 세대는 0 ──');
t('EID-1a 문서가 없으면 0', () => {
  assert.strictEqual(M.nextActivationGeneration(absent), 0);
  assert.strictEqual(M.nextActivationGeneration(null), 0);
  assert.strictEqual(M.nextActivationGeneration(undefined), 0);
});
t('EID-1b 필드가 없으면 0 으로 읽는다', () => {
  assert.strictEqual(M.activationGeneration({}), 0);
  assert.strictEqual(M.activationGeneration(undefined), 0);
  assert.strictEqual(M.activationGeneration(null), 0);
});
t('EID-1c 세대 0 의 사건 id', () => {
  assert.strictEqual(
      M.scheduleConflictNotificationId(APP, 0),
      `schedule_conflict_autocancel_${APP}_g0`);
});

console.log('\n── EID-2·3 같은 사건의 재시도는 같은 id ──');
t('EID-2 첫 자동취소의 id 는 문서+세대로 결정된다', () => {
  const g = M.activationGeneration({activationGeneration: 0, status: 'PENDING'});
  assert.strictEqual(g, 0);
  assert.strictEqual(M.scheduleConflictNotificationId(APP, g),
      `schedule_conflict_autocancel_${APP}_g0`);
});
t('EID-3 같은 snapshot 을 100번 읽어도 같은 id — 무작위 성분 0', () => {
  const d = {activationGeneration: 0};
  const ids = new Set();
  for (let i = 0; i < 100; i++) {
    ids.add(M.scheduleConflictNotificationId(
        APP, M.activationGeneration(d)));
  }
  assert.strictEqual(ids.size, 1, '재시도마다 id 가 달라지면 중복 푸시가 된다');
});
t('EID-3b id 에 시각·무작위 토큰이 섞이지 않는다', () => {
  const a = M.scheduleConflictNotificationId(APP, 2);
  const waitUntil = Date.now() + 5;
  while (Date.now() < waitUntil) { /* 시계를 확실히 넘긴다 */ }
  const b = M.scheduleConflictNotificationId(APP, 2);
  assert.strictEqual(a, b);
  assert.ok(!/\d{10,}/.test(a), `id 에 epoch 같은 긴 숫자가 있다: ${a}`);
});

console.log('\n── EID-4·5·6 재활성화는 새 사건 namespace ──');
t('EID-4 재활성화는 이전 세대 + 1', () => {
  assert.strictEqual(
      M.nextActivationGeneration(snap({activationGeneration: 0})), 1);
  assert.strictEqual(
      M.nextActivationGeneration(snap({activationGeneration: 7})), 8);
});
t('EID-5 두 번째 자동취소의 id 는 첫 번째와 다르다', () => {
  // 1차: 생성 세대 0 → 자동취소 → 알림 A
  const gen1 = M.nextActivationGeneration(absent);
  const A = M.scheduleConflictNotificationId(APP, gen1);
  // 재지원: 같은 문서, 세대 1
  const gen2 = M.nextActivationGeneration(
      snap({activationGeneration: gen1, status: 'AUTO_CANCELED'}));
  const B = M.scheduleConflictNotificationId(APP, gen2);
  assert.strictEqual(gen1, 0);
  assert.strictEqual(gen2, 1);
  assert.notStrictEqual(A, B, '같은 문서라도 두 사건은 다른 알림이어야 한다');
  assert.strictEqual(A, `schedule_conflict_autocancel_${APP}_g0`);
  assert.strictEqual(B, `schedule_conflict_autocancel_${APP}_g1`);
});
t('EID-6 두 번째 사건의 재시도도 같은 B', () => {
  const d = {activationGeneration: 1};
  const b1 = M.scheduleConflictNotificationId(APP, M.activationGeneration(d));
  const b2 = M.scheduleConflictNotificationId(APP, M.activationGeneration(d));
  assert.strictEqual(b1, b2);
});
t('EID-6b 세 번째·네 번째 활성화도 각자 namespace', () => {
  const ids = [0, 1, 2, 3].map(
      (g) => M.scheduleConflictNotificationId(APP, g));
  assert.strictEqual(new Set(ids).size, 4);
});

console.log('\n── EID-7·8·9 legacy 문서 ──');
t('EID-7 세대 필드가 없는 legacy 문서에서 crash 없음', () => {
  const g = M.activationGeneration({status: 'PENDING', uid: 'u1'});
  assert.strictEqual(g, 0);
  assert.strictEqual(typeof M.scheduleConflictNotificationId(APP, g), 'string');
});
t('EID-8 legacy 의 첫 겹침 알림도 결정적이다', () => {
  const legacy = {status: 'PENDING'};
  const a = M.scheduleConflictNotificationId(APP, M.activationGeneration(legacy));
  const b = M.scheduleConflictNotificationId(APP, M.activationGeneration(legacy));
  assert.strictEqual(a, b);
  assert.strictEqual(a, `schedule_conflict_autocancel_${APP}_g0`);
});
t('EID-9 legacy 재활성화 뒤의 두 번째 사건은 구별된다', () => {
  const legacy = snap({status: 'AUTO_CANCELED'}); // 세대 필드 없음
  const g = M.nextActivationGeneration(legacy);
  assert.strictEqual(g, 1);
  assert.notStrictEqual(
      M.scheduleConflictNotificationId(APP, g),
      M.scheduleConflictNotificationId(APP, 0));
});
t('EID-9b 1E 이전 형식의 알림 id 와 겹치지 않는다', () => {
  // 1E 는 `schedule_conflict_autocancel_{appId}` 를 썼다(접미사 없음).
  const old = `schedule_conflict_autocancel_${APP}`;
  for (const g of [0, 1, 2, 99]) {
    assert.notStrictEqual(M.scheduleConflictNotificationId(APP, g), old);
  }
});

console.log('\n── EID-10·11 세대 증가 조건 ──');
t('EID-10 같은 snapshot 으로 두 번 계산해도 값은 하나다', () => {
  // transaction 재실행은 같은 문서를 다시 읽는다 — 그 값에서 계산하므로
  //   두 번 올라가지 않는다. `increment(1)` 이면 이 보장이 없다.
  const s = snap({activationGeneration: 3});
  assert.strictEqual(M.nextActivationGeneration(s), 4);
  assert.strictEqual(M.nextActivationGeneration(s), 4);
});
t('EID-11 한 번의 재활성화는 정확히 1 올린다', () => {
  let cur = 0;
  for (let i = 1; i <= 5; i++) {
    cur = M.nextActivationGeneration(snap({activationGeneration: cur}));
    assert.strictEqual(cur, i);
  }
});

console.log('\n── EID-12·13 비정상 값 ──');
t('EID-12 숫자가 아닌 값은 0 으로 떨어진다', () => {
  for (const bad of ['3', null, undefined, {}, [], true, NaN, Infinity, -1]) {
    assert.strictEqual(M.activationGeneration({activationGeneration: bad}), 0,
        `bad=${String(bad)}`);
  }
});
t('EID-13 id 에 NaN·undefined 문자열이 들어가지 않는다', () => {
  for (const g of [NaN, Infinity, -5, undefined]) {
    const id = M.scheduleConflictNotificationId(APP, g);
    assert.ok(!/NaN|undefined|Infinity/.test(id), id);
    assert.strictEqual(id, `schedule_conflict_autocancel_${APP}_g0`);
  }
});
t('EID-13b 소수 세대는 내림한다 — id 에 점이 없다', () => {
  assert.strictEqual(M.activationGeneration({activationGeneration: 2.9}), 2);
  assert.strictEqual(M.scheduleConflictNotificationId(APP, 2.9),
      `schedule_conflict_autocancel_${APP}_g2`);
});

console.log('\n── EID-14 multi-loser ──');
t('EID-14 loser 가 둘이면 문서별로 구별된다', () => {
  const a = M.scheduleConflictNotificationId('appA', 1);
  const b = M.scheduleConflictNotificationId('appB', 1);
  assert.notStrictEqual(a, b);
  // 같은 문서의 다른 세대도 구별된다.
  assert.notStrictEqual(
      M.scheduleConflictNotificationId('appA', 1),
      M.scheduleConflictNotificationId('appA', 2));
});
t('EID-14b 접두어는 사건 종류를 말한다', () => {
  assert.strictEqual(M.SCHEDULE_CONFLICT_NOTIF_PREFIX,
      'schedule_conflict_autocancel');
  assert.ok(M.scheduleConflictNotificationId(APP, 0)
      .startsWith(`${M.SCHEDULE_CONFLICT_NOTIF_PREFIX}_`));
});

console.log(`\n${pass} pass, ${fails.length} fail`);
if (fails.length > 0) {
  for (const f of fails) console.log(`  - ${f}`);
  process.exit(1);
}
