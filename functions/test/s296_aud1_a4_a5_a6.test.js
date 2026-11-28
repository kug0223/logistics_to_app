'use strict';
/**
 * [AUD-1 A4 · A5 · A6] 정원 정수 1–999(생성·수정 SINGLE·BATCH·공고 생성/수정 공용 helper) · BATCH 슬롯별 보호 집합 ·
 *   달력 왕복 날짜 검증 + 날짜 개수 상한.
 *   S296A4_EXPECT_OLD=1 이면 이전 원문에서 결함을 재현한다.
 */
const {test} = require('node:test');
const assert = require('assert');
const {createFakeFirestore} = require('./consent_r4d_fakestore');
const {loadIndexClosure} = require('./auth_kakao_index_harness');

const OLD = process.env.S296A4_EXPECT_OLD === '1';
const RealDate = Date;
const NOW = RealDate.UTC(2026, 10, 27, 3, 0);
const DAY = 86400000;
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
const {exports: X} = loadIndexClosure(['callableCreateFlexSlots', 'callableUpdateSlotWorkDetails'],
  F, {HttpsError, console: QCON, Date: FakeDate});
const Ts = F.Ts;
const go = async (fn, data, uid = 'own1') => {
  try { return {ok: true, r: await fn({data, auth: {uid, token: {}}})}; } catch (e) { return {ok: false, e}; }
};
const code = (o) => o.e && ((o.e.details && o.e.details.code) || o.e.code);

function base() {
  F.reset();
  F.put('users/own1', {role: 'BUSINESS_ADMIN', accountStatus: 'active', name: '사장', businessId: 'b1'});
  F.put('businesses/b1', {name: '평택', ownerId: 'own1', adminIds: ['own1'], isApproved: true, city: '평택'});
  F.put('tos/t1', {businessId: 'b1', title: '물류', status: 'ACTIVE', type: 'flex', isPublished: false, totalRequired: 0,
    totalPending: 0, totalConfirmed: 0, editRevision: 1});
}
const wd = (o = {}) => Object.assign({workType: '포장', startTime: '09:00', endTime: '18:00', wageType: 'hourly', wage: 12000,
  payScheduleType: 'monthly', payScheduleDay: 10, requiredCount: 3}, o);
const flex = (dates, wds) => go(X.callableCreateFlexSlots, {toId: 't1', businessId: 'b1', dates, workDetails: wds,
  deadlineType: 'HOURS_BEFORE', hoursBeforeStart: 2});

test('A4 생성 — 정원 "3"·1.5·0·-1·Infinity·1000 거절(REQUIRED_COUNT_INVALID) · 정상 3 은 정원 검사 통과', async () => {
  for (const bad of ['3', 1.5, 0, -1, Infinity, 1000]) {
    base();
    const o = await flex(['2026-12-01'], [wd({requiredCount: bad})]);
    if (OLD) { assert.notStrictEqual(code(o), 'REQUIRED_COUNT_INVALID', `음성 대조: 이전 원문은 ${bad} 를 정원 검사 없이 통과`); continue; }
    assert.strictEqual(code(o), 'REQUIRED_COUNT_INVALID', String(bad));
  }
  base();
  const ok = await flex(['2026-12-01'], [wd()]);
  assert.notStrictEqual(code(ok), 'REQUIRED_COUNT_INVALID');
});

test('A6 생성 — 없는 날짜(2026-11-31 · 2026-02-29 · 2026-13-01) 거절 · 날짜 367개 거절 · 윤년 아닌 해 2-28 은 통과', async () => {
  for (const bad of ['2026-11-31', '2027-02-29', '2026-13-01', '2026-12-32']) {
    base();
    const o = await flex([bad, '2026-12-01'], [wd()]);
    if (OLD) { assert.notStrictEqual(code(o), 'INVALID_CALENDAR_DATE'); continue; }
    assert.strictEqual(code(o), 'INVALID_CALENDAR_DATE', bad);
  }
  if (OLD) return;
  base();
  const many = [];
  for (let i = 0; i < 367; i++) many.push(new RealDate(RealDate.UTC(2026, 11, 1) + i * DAY).toISOString().slice(0, 10));
  assert.strictEqual(code(await flex(many, [wd()])), 'TOO_MANY_DATES');
  base();
  const o = await flex(['2027-02-28'], [wd()]);
  assert.ok(!['INVALID_CALENDAR_DATE', 'TOO_MANY_DATES', 'REQUIRED_COUNT_INVALID'].includes(code(o)));
});

function slotsFixture() {
  base();
  const wdsA = [{wdId: 'wA', workType: '포장', startTime: '09:00', endTime: '18:00', wageType: 'hourly', wage: 12000,
    payScheduleType: 'monthly', payScheduleDay: 10, requiredCount: 3}];
  const wdsB = [...wdsA, {wdId: 'wB', workType: '분류', startTime: '09:00', endTime: '18:00', wageType: 'hourly', wage: 12000,
    payScheduleType: 'monthly', payScheduleDay: 10, requiredCount: 2}];
  F.put('tos/t1/slots/s1', {status: 'open', date: new Ts(NOW + 5 * DAY), workDetails: wdsA, confirmedCount: 0, pendingCount: 0,
    workDetailCounts: {wA: {confirmedCount: 0, pendingCount: 0}}, editRevision: 1});
  F.put('tos/t1/slots/s2', {status: 'open', date: new Ts(NOW + 6 * DAY), workDetails: wdsB, confirmedCount: 1, pendingCount: 0,
    workDetailCounts: {wA: {confirmedCount: 0, pendingCount: 0}, wB: {confirmedCount: 1, pendingCount: 0}}, editRevision: 1});
  F.put('applications/c1', {uid: 'w1', businessId: 'b1', toId: 't1', slotId: 's2', wdId: 'wB', status: 'CONFIRMED',
    selectedWorkType: '분류', startTime: '09:00', endTime: '18:00', workDate: new Ts(NOW + 6 * DAY)});
  return {wdsA, wdsB};
}

test('A4 수정 SINGLE — 정원 "3"·1.5·Infinity 거절(예전 \'1 미만\'만 거절)', async () => {
  for (const bad of ['3', 1.5, Infinity]) {
    const {wdsA} = slotsFixture();
    const o = await go(X.callableUpdateSlotWorkDetails, {toId: 't1', slotId: 's1', expectedEditRevision: 1,
      workDetails: [Object.assign({}, wdsA[0], {requiredCount: bad})]});
    if (OLD) { assert.notStrictEqual(code(o), 'REQUIRED_COUNT_INVALID'); continue; }
    assert.strictEqual(code(o), 'REQUIRED_COUNT_INVALID', String(bad));
    assert.strictEqual(F.get('tos/t1/slots/s1').workDetails[0].requiredCount, 3, '저장 0');
  }
});

test('A5 수정 BATCH — 다른 슬롯(s2)의 확정 업무(wB)를 지우는 항목은 첫 슬롯 기준이 아니라 그 슬롯 기준으로 막는다', async () => {
  const {wdsA, wdsB} = slotsFixture();
  F.put('tos/t1/slots/s1', Object.assign(F.get('tos/t1/slots/s1'), {workDetails: wdsB,
    workDetailCounts: {wA: {confirmedCount: 0, pendingCount: 0}, wB: {confirmedCount: 0, pendingCount: 0}}}));
  // 첫 항목(s1)은 wB 를 유지 → 예전 보호 집합(첫 슬롯 기준)에 wB 가 들어 있어 s2 의 wB 제거가 통과했다
  const o = await go(X.callableUpdateSlotWorkDetails, {toId: 't1', batchUpdates: [
    {slotId: 's1', workDetails: wdsB, expectedEditRevision: 1},
    {slotId: 's2', workDetails: wdsA, expectedEditRevision: 1}, // wB(확정 1명) 제거
  ]});
  const s2 = F.get('tos/t1/slots/s2');
  if (OLD) {
    assert.ok(!s2.workDetails.some((w) => w.wdId === 'wB'), '음성 대조: 이전 원문은 첫 슬롯 기준이라 확정 업무 제거가 통과');
    return;
  }
  assert.ok(!o.ok, 'wB 제거가 통과하면 안 된다');
  assert.ok(s2.workDetails.some((w) => w.wdId === 'wB'), '확정 업무 보존');
});
