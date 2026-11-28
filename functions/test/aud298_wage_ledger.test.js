'use strict';
/**
 * [server_300 · 판정298 F298-01] 급여 집계 trigger(onAttendanceWageChanged)는 근태 원장의 현재 상태로 수렴한다.
 *   실제 운영처럼 트리거가 돌 때 attendance 문서는 **그 시점 최신 상태**다(이벤트 before/after 는 과거 스냅샷).
 *   AUD298W_EXPECT_OLD=1 이면 이전 원문(e2353d90 · delta 모델)의 중복가산을 재현하는 쪽으로 기대를 뒤집는다(W2·W3).
 *   W1 시간순(E1 calculated→confirmed 때 원장 confirmed · E2 confirmed→transferred 때 원장 transferred) → 90,000 / 1 / 미이체 0
 *   W2 역순(E2 먼저 · E1 나중 · 원장 transferred) → 90,000 / 1 / 0  (예전 180,000 / 2 / 1)
 *   W3 E1 일시 실패 → E2 → E1 retry → 90,000 / 1 / 0  (예전 180,000 / 2 / 1)
 *   W4 같은 이벤트 2회 → 그대로(표식)
 *   W5 이미 틀어진 summary(옛 delta 의 180,000 · 근무자 2일)가 있으면 그 달 다음 사건에서 원장 값으로 바로잡힌다
 *   W6 취소(confirmed→calculated) → 0 · summary 는 남고 근무자 행 삭제 · 재확정 → 다시 90,000
 *   W7 금액 정정(confirmed→confirmed 90,000→100,000) · 다른 근무자 포함 합계 · workerCount
 *   W8 노쇼 0원 제외 · summary 가 없고 지급 대상 0 이면 만들지 않는다
 *   W9 근무일이 다음 달로 정정 → 두 달 모두 다시 센다(이전 달에서 빠지고 새 달에 들어감)
 *   W10 영구 오류 → trigger_failures 기록 후 ACK · 일시 오류 → 재전파
 */
const {test} = require('node:test');
const assert = require('assert');
const {createFakeFirestore} = require('./consent_r4d_fakestore');
const {loadIndexClosure} = require('./auth_kakao_index_harness');

const RealDate = Date;
const NOW = RealDate.UTC(2026, 10, 27, 3, 0);
class FakeDate extends RealDate {
  constructor(...a) { if (a.length === 0) super(NOW); else super(...a); }
  static now() { return NOW; }
}
class HttpsError extends Error {
  constructor(code, message, details) { super(message); this.code = code; this.details = details; }
}
const QCON = {};
for (const k of ['log', 'info', 'warn', 'error', 'debug']) QCON[k] = () => {};
const F = createFakeFirestore({now: () => NOW});
const {exports: X} = loadIndexClosure(['onAttendanceWageChanged'], F, {HttpsError, console: QCON, Date: FakeDate});
const Ts = F.Ts;
const OLD = process.env.AUD298W_EXPECT_OLD === '1';
const DAY = 86400000;
const NOV = new Ts(NOW - 2 * DAY); // 2026-11-25
const DEC = new Ts(RealDate.UTC(2026, 11, 3, 3, 0));
const att = (o) => Object.assign({businessId: 'b1', userId: 'w1', workDate: NOV, status: 'present', finalWage: 90000}, o);
const ev = (id, b, a, aid = 'a1') => ({id, params: {attendanceId: aid}, data: {before: {data: () => b}, after: {data: () => a}}});
const root = (m = '2026-11') => F.get(`payroll_summaries/b1_${m}`);
const worker = (u = 'w1', m = '2026-11') => F.get(`payroll_summaries/b1_${m}/workers/${u}`);
const sum = (r) => r && {totalPayout: r.totalPayout, confirmedCount: r.confirmedCount, notTransferredCount: r.notTransferredCount, workerCount: r.workerCount};
const failures = () => [...F.STORE.keys()].filter((k) => k.startsWith('trigger_failures/'));
function base() { F.reset(); F.put('users/w1', {name: '근로자'}); F.put('users/w2', {name: '근로자2'}); }
const E1 = (id = 'e1') => ev(id, att({wageStatus: 'calculated'}), att({wageStatus: 'confirmed'}));
const E2 = (id = 'e2') => ev(id, att({wageStatus: 'confirmed'}), att({wageStatus: 'transferred'}));
const RIGHT = {totalPayout: 90000, confirmedCount: 1, notTransferredCount: 0, workerCount: 1};

test('W1 시간순 — 원장 상태를 따라 90,000 / 1 / 미이체 1 → 0', async (t) => {
  if (OLD) { t.skip('예전 원문도 시간순은 맞다(Codex 통제와 같음)'); return; }
  base();
  F.put('attendance/a1', att({wageStatus: 'confirmed'}));
  await X.onAttendanceWageChanged(E1());
  assert.deepStrictEqual(sum(root()), {totalPayout: 90000, confirmedCount: 1, notTransferredCount: 1, workerCount: 1});
  F.put('attendance/a1', att({wageStatus: 'transferred'}));
  await X.onAttendanceWageChanged(E2());
  assert.deepStrictEqual(sum(root()), RIGHT);
  assert.deepStrictEqual([worker().totalPayout, worker().workDays, worker().name], [90000, 1, '근로자']);
});

test('W2 역순(E2 먼저 · E1 나중) — 중복가산 없음', async () => {
  base();
  F.put('attendance/a1', att({wageStatus: 'transferred'}));
  await X.onAttendanceWageChanged(E2());
  await X.onAttendanceWageChanged(E1());
  if (OLD) {
    assert.deepStrictEqual(sum(root()), {totalPayout: 180000, confirmedCount: 2, notTransferredCount: 1, workerCount: 1}, '재현: 중복가산');
    assert.strictEqual(worker().workDays, 2);
    return;
  }
  assert.deepStrictEqual(sum(root()), RIGHT);
  assert.deepStrictEqual([worker().totalPayout, worker().workDays], [90000, 1]);
});

test('W3 E1 일시 실패 → E2 → E1 retry — 중복가산 없음', async () => {
  base();
  F.put('attendance/a1', att({wageStatus: 'transferred'}));
  let fail = true;
  F.hooks.beforeCommit = () => { if (fail) { fail = false; throw new Error('UNAVAILABLE'); } };
  await assert.rejects(X.onAttendanceWageChanged(E1()), /UNAVAILABLE/, '일시 오류는 재전파(retry:true)');
  F.hooks.beforeCommit = null;
  await X.onAttendanceWageChanged(E2());
  await X.onAttendanceWageChanged(E1());
  if (OLD) {
    assert.deepStrictEqual(sum(root()), {totalPayout: 180000, confirmedCount: 2, notTransferredCount: 1, workerCount: 1}, '재현');
    return;
  }
  assert.deepStrictEqual(sum(root()), RIGHT);
  assert.strictEqual(worker().workDays, 1);
});

test('W4 같은 이벤트 2회 — 그대로', async (t) => {
  if (OLD) { t.skip('예전 원문도 같은 id 는 표식으로 막는다'); return; }
  base();
  F.put('attendance/a1', att({wageStatus: 'transferred'}));
  await X.onAttendanceWageChanged(E2());
  await X.onAttendanceWageChanged(E2());
  assert.deepStrictEqual(sum(root()), RIGHT);
});

test('W5 이미 틀어진 summary — 그 달 다음 사건에서 원장 값으로 바로잡힌다', async (t) => {
  if (OLD) { t.skip('예전 원문은 delta 라 기존 오염을 고치지 않는다'); return; }
  base();
  F.put('payroll_summaries/b1_2026-11', {businessId: 'b1', yearMonth: '2026-11', year: 2026, month: 11, totalPayout: 180000,
    confirmedCount: 2, workerCount: 1, notTransferredCount: 1, createdAt: new Ts(NOW - DAY)});
  F.put('payroll_summaries/b1_2026-11/workers/w1', {name: '근로자', totalPayout: 180000, workDays: 2});
  F.put('attendance/a1', att({wageStatus: 'transferred'}));
  F.put('attendance/a2', att({wageStatus: 'confirmed', userId: 'w1', finalWage: 50000}));
  await X.onAttendanceWageChanged(ev('e5', att({wageStatus: 'calculated', finalWage: 50000}), att({wageStatus: 'confirmed', finalWage: 50000}), 'a2'));
  assert.deepStrictEqual(sum(root()), {totalPayout: 140000, confirmedCount: 2, notTransferredCount: 1, workerCount: 1});
  assert.deepStrictEqual([worker().totalPayout, worker().workDays], [140000, 2]);
  assert.strictEqual(root().createdAt.toMillis(), NOW - DAY, '생성 시각 보존');
});

test('W6 취소 → 0(summary 남음 · 근무자 행 삭제) · 재확정 → 다시 90,000', async (t) => {
  if (OLD) { t.skip(); return; }
  base();
  F.put('attendance/a1', att({wageStatus: 'confirmed'}));
  await X.onAttendanceWageChanged(E1());
  F.put('attendance/a1', att({wageStatus: 'calculated'}));
  await X.onAttendanceWageChanged(ev('c1', att({wageStatus: 'confirmed'}), att({wageStatus: 'calculated'})));
  assert.deepStrictEqual(sum(root()), {totalPayout: 0, confirmedCount: 0, notTransferredCount: 0, workerCount: 0});
  assert.strictEqual(worker(), undefined);
  F.put('attendance/a1', att({wageStatus: 'confirmed'}));
  await X.onAttendanceWageChanged(E1('e1b'));
  assert.deepStrictEqual(sum(root()), {totalPayout: 90000, confirmedCount: 1, notTransferredCount: 1, workerCount: 1});
});

test('W7 금액 정정 · 다른 근무자 포함 합계 · workerCount', async (t) => {
  if (OLD) { t.skip(); return; }
  base();
  F.put('attendance/b9', att({wageStatus: 'transferred', userId: 'w2', finalWage: 70000}));
  F.put('attendance/a1', att({wageStatus: 'confirmed', finalWage: 100000}));
  await X.onAttendanceWageChanged(ev('m1', att({wageStatus: 'confirmed', finalWage: 90000}), att({wageStatus: 'confirmed', finalWage: 100000})));
  assert.deepStrictEqual(sum(root()), {totalPayout: 170000, confirmedCount: 2, notTransferredCount: 1, workerCount: 2});
  assert.deepStrictEqual([worker().totalPayout, worker().workDays], [100000, 1]);
});

test('W8 노쇼 0원 제외 · 지급 대상 0 이고 summary 없으면 만들지 않는다', async (t) => {
  if (OLD) { t.skip(); return; }
  base();
  F.put('attendance/a1', att({wageStatus: 'confirmed', status: 'NO_SHOW', finalWage: 0}));
  F.put('attendance/a2', att({wageStatus: 'calculated'}));
  // 정정 전 기여가 있었다고 가정한 이벤트(지급 대상 → 노쇼 0원) — summary 가 없으니 만들지 않는다
  await X.onAttendanceWageChanged(ev('n1', att({wageStatus: 'confirmed'}), att({wageStatus: 'confirmed', status: 'NO_SHOW', finalWage: 0})));
  assert.strictEqual(root(), undefined);
});

test('W9 근무일이 다음 달로 정정 → 두 달 모두 다시 센다', async (t) => {
  if (OLD) { t.skip(); return; }
  base();
  F.put('attendance/a1', att({wageStatus: 'confirmed'}));
  await X.onAttendanceWageChanged(E1());
  F.put('attendance/a1', att({wageStatus: 'confirmed', workDate: DEC}));
  await X.onAttendanceWageChanged(ev('mv', att({wageStatus: 'confirmed'}), att({wageStatus: 'confirmed', workDate: DEC})));
  assert.deepStrictEqual(sum(root('2026-11')), {totalPayout: 0, confirmedCount: 0, notTransferredCount: 0, workerCount: 0});
  assert.strictEqual(worker('w1', '2026-11'), undefined);
  assert.deepStrictEqual(sum(root('2026-12')), {totalPayout: 90000, confirmedCount: 1, notTransferredCount: 1, workerCount: 1});
});

test('W10 영구 오류 → 기록 후 ACK', async (t) => {
  if (OLD) { t.skip(); return; }
  base();
  F.put('attendance/a1', att({wageStatus: 'confirmed'}));
  let fail = true;
  F.hooks.beforeCommit = () => { if (fail) { fail = false; throw new Error('INVALID_ARGUMENT 데이터 모양'); } };
  await X.onAttendanceWageChanged(E1('p1'));
  F.hooks.beforeCommit = null;
  assert.deepStrictEqual(failures(), ['trigger_failures/onAttendanceWageChanged__a1__p1']);
  assert.deepStrictEqual(F.get(failures()[0]).summaryIds, ['b1_2026-11']);
});
