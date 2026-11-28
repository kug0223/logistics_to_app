'use strict';
/**
 * [판정296 §2-4 M2/A1] 급여 정정 — 약속 유형/단가/기본금 누락·null·유형 변경으로 검사 생략·맵 소실 0 · 비유한값 거절 ·
 *   기존 raw 합산 reader(중간정산 처리)가 옛 문자열 금액을 이어 붙이거나 0 으로 삼키지 않고 명시 거절.
 *   S296M_EXPECT_OLD=1 이면 이전 원문에서 결함을 재현한다.
 */
const {test} = require('node:test');
const assert = require('assert');
const {createFakeFirestore} = require('./consent_r4d_fakestore');
const {loadIndexClosure} = require('./auth_kakao_index_harness');

const OLD = process.env.S296M_EXPECT_OLD === '1';
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
const {exports: X} = loadIndexClosure(['callableUpdateWageDetail', 'callableProcessInterimSettlement'],
  F, {HttpsError, console: QCON, Date: FakeDate});
const Ts = F.Ts;
const go = async (fn, data, uid = 'own1') => {
  try { return {ok: true, r: await fn({data, auth: {uid, token: {}}})}; } catch (e) { return {ok: false, e}; }
};
const code = (o) => o.e && ((o.e.details && o.e.details.code) || o.e.code);

function base(storedWd = {}) {
  F.reset();
  F.put('users/own1', {role: 'BUSINESS_ADMIN', accountStatus: 'active', name: '사장', businessId: 'b1'});
  F.put('businesses/b1', {name: '평택', ownerId: 'own1', adminIds: ['own1'], isApproved: true});
  F.put('applications/a1', {uid: 'w1', businessId: 'b1', status: 'CONFIRMED', wageType: 'hourly', wage: 12000});
  F.put('attendance/w1', {userId: 'w1', businessId: 'b1', applicationId: 'a1', wageStatus: 'calculated', workDate: new Ts(NOW - 5 * DAY),
    finalWage: 96000, wageDetail: Object.assign({wageType: 'hourly', baseWage: 12000, baseAmount: 96000, overtimeAmount: 0,
      nightAmount: 0, additionalAmount: 0, deductionAmount: 0, weeklyHolidayAmount: 0, totalAmount: 96000, netWage: 96000,
      taxDeductionType: 'none'}, storedWd)});
}
// 최저임금 미만 단가(5,000) 로 만든 정정 — 항목 합·실수령 식은 맞다
const lowMap = (o = {}) => {
  const m = Object.assign({wageType: 'hourly', baseWage: 5000, baseAmount: 40000, overtimeAmount: 0, nightAmount: 0,
    additionalAmount: 0, deductionAmount: 0, weeklyHolidayAmount: 0, totalAmount: 40000, taxDeductionType: 'none',
    incomeTaxDeduction: 0, employmentInsuranceDeduction: 0, nationalPensionDeduction: 0, healthInsuranceDeduction: 0,
    ltcInsuranceDeduction: 0, retroactiveDeduction: 0, netWage: 40000}, o);
  for (const k of Object.keys(m)) if (m[k] === undefined) delete m[k];
  return m;
};
const upd = (map) => go(X.callableUpdateWageDetail, {attendanceId: 'w1', wageDetailMap: map});

test('W8 wageType 생략 — 최저임금 검사 생략·맵에서 유형 소실 0(WAGE_FIELD_MISSING)', async () => {
  base();
  const o = await upd(lowMap({wageType: undefined}));
  if (OLD) {
    assert.ok(o.ok, '음성 대조: 이전 원문은 유형 없는 정정으로 최저임금 검사를 건너뛴다');
    assert.strictEqual(F.get('attendance/w1').wageDetail.wageType, undefined, '음성 대조: 맵에서 유형이 사라진다');
    return;
  }
  assert.strictEqual(code(o), 'WAGE_FIELD_MISSING');
  assert.strictEqual(F.get('attendance/w1').finalWage, 96000, '저장 0');
});

test('W9 시급 → 일급 유형 변경 — 거절(WAGE_TYPE_CHANGED)', async () => {
  base();
  const o = await upd(lowMap({wageType: 'daily'}));
  if (OLD) { assert.ok(o.ok, '음성 대조: 이전 원문은 유형 변경으로 최저임금 검사를 건너뛴다'); return; }
  assert.strictEqual(code(o), 'WAGE_TYPE_CHANGED');
});

test('W10 baseWage null · baseAmount 생략 — 거절(WAGE_FIELD_MISSING · 필드명)', async () => {
  base();
  let o = await upd(lowMap({baseWage: null}));
  if (!OLD) { assert.strictEqual(code(o), 'WAGE_FIELD_MISSING'); assert.strictEqual(o.e.details.field, 'baseWage'); }
  base();
  o = await upd(lowMap({baseWage: 12000, baseAmount: undefined, totalAmount: 96000, netWage: 96000}));
  if (OLD) return;
  assert.strictEqual(code(o), 'WAGE_FIELD_MISSING');
  assert.strictEqual(o.e.details.field, 'baseAmount');
});

test('W11 NaN · Infinity · 소수 — 거절(WAGE_FIELD_INVALID · 동치)', async () => {
  for (const bad of [{netWage: NaN}, {totalAmount: Infinity}, {baseWage: Infinity}, {baseAmount: 40000.5}]) {
    base();
    const o = await upd(lowMap(Object.assign({baseWage: 12000}, bad)));
    assert.ok(!o.ok, JSON.stringify(bad));
    assert.strictEqual(o.e.code, 'invalid-argument', JSON.stringify(bad)); // 앞단 총액 검사 또는 WAGE_FIELD_INVALID
    assert.strictEqual(F.get('attendance/w1').finalWage, 96000, '저장 0');
  }
});

test('W12 저장 맵에 유형이 없던 옛 근태 — 지원서 약속 유형(hourly)으로 채워 최저임금 검사를 한다', async () => {
  base({wageType: undefined, baseWage: undefined});
  const w = F.get('attendance/w1'); delete w.wageDetail.wageType; delete w.wageDetail.baseWage; F.put('attendance/w1', w);
  const o = await upd(lowMap({wageType: undefined}));
  if (OLD) { assert.ok(o.ok, '음성 대조: 검사 생략'); return; }
  assert.strictEqual(code(o), 'WAGE_BELOW_MINIMUM');
});

test('W13 정상 동치 — 같은 유형·단가로 추가수당 정정은 저장된다', async () => {
  base();
  const o = await upd(lowMap({baseWage: 12000, baseAmount: 96000, additionalAmount: 10000, totalAmount: 106000, netWage: 106000}));
  assert.ok(o.ok, o.e && o.e.message);
  assert.strictEqual(F.get('attendance/w1').finalWage, 106000);
  assert.strictEqual(F.get('attendance/w1').wageDetail.wageType, 'hourly');
});

test('I1 중간정산 처리 — 옛 문자열 실수령("100000") 저장분은 이어 붙이지 않고 WAGE_VALUE_INVALID', async () => {
  F.reset();
  F.put('users/own1', {role: 'BUSINESS_ADMIN', accountStatus: 'active', name: '사장', businessId: 'b1'});
  F.put('businesses/b1', {name: '평택', ownerId: 'own1', adminIds: ['own1'], isApproved: true});
  F.put('users/w2', {role: 'USER', bankAccountVersion: 1, bankbookDocumentVersion: 1});
  const att = (id, net) => F.put(`attendance/${id}`, {userId: 'w2', businessId: 'b1', applicationId: 'a2', wageStatus: 'confirmed',
    finalWage: 100000, wageDetail: {netWage: net}, activeInterimSettlementId: 'r1', workDate: new Ts(NOW - 5 * DAY),
    wageAccountSnapshotVersion: 1, wageAccountBankName: 'A', wageAccountNumberEncrypted: 'E', wageAccountHolder: 'h',
    wageAccountSnapshotAt: new Ts(NOW - DAY), wageAccountSourceBankAccountVersion: 1, wageAccountSourceBankbookDocumentVersion: 1});
  att('x1', '100000'); att('x2', 30000);
  F.put('interim_settlement_requests/r1', {businessId: 'b1', workerId: 'w2', status: 'APPROVED', attendanceIds: ['x1', 'x2'],
    requestedAmount: 200000, netAmount: 130000, periodStart: new Ts(NOW - 6 * DAY), periodEnd: new Ts(NOW - 5 * DAY)});
  const o = await go(X.callableProcessInterimSettlement, {settlementRequestId: 'r1', businessId: 'b1'});
  assert.ok(!o.ok, '처리되면 안 된다');
  if (OLD) { assert.notStrictEqual(code(o), 'WAGE_VALUE_INVALID'); return; }
  assert.strictEqual(code(o), 'WAGE_VALUE_INVALID');
  assert.strictEqual(o.e.details.attendanceId, 'x1');
  assert.strictEqual(F.get('interim_settlement_requests/r1').status, 'APPROVED', '쓰기 0');
});
