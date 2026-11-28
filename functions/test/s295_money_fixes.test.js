'use strict';
/**
 * [판정295 묶음 · AUD-3 H1 · M2 · impl_37] 급여 스냅샷 갱신 경합 · 급여 정정 서버 재검증 · 중간정산 처리 거절 사유 코드.
 *   S295M_EXPECT_OLD=1 이면 이전 원문(dbed3203 사본)에서 결함을 재현한다. 정상 셀(W1·W7·R2)은 두 원문에서 같은 결과(동치).
 */
const {test} = require('node:test');
const assert = require('assert');
const {createFakeFirestore} = require('./consent_r4d_fakestore');
const {loadIndexClosure} = require('./auth_kakao_index_harness');

const OLD = process.env.S295M_EXPECT_OLD === '1';
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
const {exports: X} = loadIndexClosure(['callableRefreshWagePaymentSnapshot', 'callableUpdateWageDetail',
  'callableProcessInterimSettlement'], F, {HttpsError, console: QCON, Date: FakeDate});
const Ts = F.Ts;
const go = async (fn, data, uid = 'own1') => {
  try { return {ok: true, r: await fn({data, auth: {uid, token: {}}})}; } catch (e) { return {ok: false, e}; }
};
const code = (o) => o.e && ((o.e.details && o.e.details.code) || o.e.code);

function base() {
  F.reset(); F.hooks.afterGet = null; F.hooks.beforeCommit = null;
  F.put('users/own1', {role: 'BUSINESS_ADMIN', accountStatus: 'active', name: '사장', businessId: 'b1'});
  F.put('businesses/b1', {name: '평택', ownerId: 'own1', adminIds: ['own1'], isApproved: true});
}

// ═════════════ H1 — 계좌 스냅샷 갱신 경합 ═════════════
function h1Base() {
  base();
  F.put('users/w1', {role: 'USER', name: '근로자', bankName: 'B은행', accountNumber: 'ENC-B', accountHolder: '근로자',
    bankbookImagePath: 'users/w1/bankbook.jpg', bankbookMatchStatus: 'MATCHED',
    bankbookMatchDocumentVersion: 1, bankbookMatchAccountVersion: 2, bankbookDocumentVersion: 1, bankAccountVersion: 2});
  F.put('attendance/att1', {userId: 'w1', businessId: 'b1', applicationId: 'a1', wageStatus: 'confirmed', finalWage: 90000,
    wageAccountSnapshotVersion: 1, wageAccountBankName: 'A은행', wageAccountNumberEncrypted: 'ENC-A', wageAccountHolder: '근로자',
    wageAccountSnapshotAt: new Ts(NOW - DAY), workDate: new Ts(NOW - 3 * DAY)});
}
const refresh = (ids) => go(X.callableRefreshWagePaymentSnapshot, {businessId: 'b1', attendanceIds: ids});
const att1 = () => F.get('attendance/att1');

test('R1 판정 읽기 직후 다른 관리자 이체 커밋 — 이체된 근태의 보낸 계좌 기록은 그대로(skip)', async () => {
  h1Base();
  let fired = false;
  F.hooks.afterGet = (p, txId) => {
    if (fired || p !== 'attendance/att1' || txId) return;
    fired = true;
    F.put('attendance/att1', Object.assign({}, att1(), {wageStatus: 'transferred', transferDate: new Ts(NOW)}));
  };
  const o = await refresh(['att1']);
  F.hooks.afterGet = null;
  assert.ok(o.ok, o.e && o.e.message);
  assert.ok(fired);
  if (OLD) {
    assert.strictEqual(att1().wageAccountBankName, 'B은행', '음성 대조: 이전 원문은 이체된 근태 스냅샷을 새 계좌로 덮는다');
    return;
  }
  assert.strictEqual(att1().wageAccountBankName, 'A은행');
  assert.strictEqual(att1().wageAccountNumberEncrypted, 'ENC-A');
  assert.deepStrictEqual(o.r.refreshed, []);
  assert.strictEqual(o.r.skipped.att1, 'alreadyTransferred');
});

test('R1b 판정 뒤 중간정산 승인 잠금이 끼면 — skip(SETTLEMENT_LOCKED)', async () => {
  h1Base();
  let fired = false;
  F.hooks.afterGet = (p, txId) => {
    if (fired || p !== 'attendance/att1' || txId) return;
    fired = true;
    F.put('attendance/att1', Object.assign({}, att1(), {activeInterimSettlementId: 'isr1'}));
  };
  const o = await refresh(['att1']);
  F.hooks.afterGet = null;
  if (OLD) { assert.strictEqual(att1().wageAccountBankName, 'B은행'); return; }
  assert.strictEqual(att1().wageAccountBankName, 'A은행');
  assert.ok(o.r.skipped.att1);
});

test('R2 정상 갱신 동치 — 확정·미잠금이면 새 계좌로 갱신', async () => {
  h1Base();
  const o = await refresh(['att1']);
  assert.ok(o.ok, o.e && o.e.message);
  assert.deepStrictEqual(o.r.refreshed, ['att1']);
  assert.strictEqual(att1().wageAccountBankName, 'B은행');
  assert.strictEqual(att1().wageAccountSourceBankAccountVersion, 2);
});

// ═════════════ M2 — 급여 정정 서버 재검증 ═════════════
function m2Base() {
  base();
  F.put('attendance/w1', {userId: 'w1', businessId: 'b1', wageStatus: 'calculated', workDate: new Ts(NOW - 5 * DAY),
    finalWage: 96000, wageDetail: {wageType: 'hourly', baseWage: 12000, baseAmount: 96000, overtimeAmount: 0, nightAmount: 0,
      additionalAmount: 0, deductionAmount: 0, weeklyHolidayAmount: 0, totalAmount: 96000, netWage: 96000, taxDeductionType: 'none'}});
}
// 앱 WageDetailDialog 와 같은 식으로 만든 정상 정정(추가수당 10,000 · 3.3% 공제)
const okMap = (o = {}) => Object.assign({wageType: 'hourly', baseWage: 12000, baseAmount: 96000, overtimeAmount: 0, nightAmount: 0,
  additionalAmount: 10000, deductionAmount: 0, weeklyHolidayAmount: 0, totalAmount: 106000, taxDeductionType: 'freelancer_3_3',
  incomeTaxDeduction: 3490, employmentInsuranceDeduction: 0, nationalPensionDeduction: 0, healthInsuranceDeduction: 0,
  ltcInsuranceDeduction: 0, retroactiveDeduction: 0, netWage: 102510, workMinutes: 480, breakMinutes: 60, memo: '추가 작업'}, o);
const upd = (map) => go(X.callableUpdateWageDetail, {attendanceId: 'w1', wageDetailMap: map});
const w1 = () => F.get('attendance/w1');

test('W1 정상 정정 동치 — 저장 결과(finalWage·wageDetail 숫자) 같음', async () => {
  m2Base();
  const o = await upd(okMap());
  assert.ok(o.ok, o.e && o.e.message);
  assert.strictEqual(w1().finalWage, 102510);
  assert.strictEqual(w1().wageDetail.netWage, 102510);
  assert.strictEqual(w1().wageDetail.totalAmount, 106000);
  assert.strictEqual(w1().wageDetail.memo, '추가 작업');
});

test('W2 문자열 금액("102510") — 거절(WAGE_FIELD_INVALID) · 저장 0', async () => {
  m2Base();
  const o = await upd(okMap({netWage: '102510', totalAmount: '106000'}));
  if (OLD) {
    assert.ok(o.ok);
    assert.strictEqual(typeof w1().wageDetail.netWage, 'string', '음성 대조: 이전 원문은 문자열을 그대로 저장');
    return;
  }
  assert.ok(!o.ok);
  assert.strictEqual(code(o), 'WAGE_FIELD_INVALID');
  assert.strictEqual(w1().finalWage, 96000);
});

test('W3 세전 ≠ 항목 합 — 거절(WAGE_TOTAL_MISMATCH)', async () => {
  m2Base();
  const o = await upd(okMap({totalAmount: 200000, netWage: 196510}));
  if (OLD) { assert.ok(o.ok, '음성 대조: 이전 원문은 항목 합과 다른 총액을 저장'); return; }
  assert.strictEqual(code(o), 'WAGE_TOTAL_MISMATCH');
  assert.strictEqual(o.e.details.expected, 106000);
});

test('W4 실수령 ≠ 세전 − 공제 — 거절(WAGE_NET_MISMATCH)', async () => {
  m2Base();
  const o = await upd(okMap({netWage: 105000}));
  if (OLD) { assert.ok(o.ok); assert.strictEqual(w1().finalWage, 105000, '음성 대조: 공제와 맞지 않는 실수령 저장'); return; }
  assert.strictEqual(code(o), 'WAGE_NET_MISMATCH');
  assert.strictEqual(o.e.details.expected, 102510);
});

test('W5 시급 최저임금 미만(2026 · 5,000원) — 거절(WAGE_BELOW_MINIMUM)', async () => {
  m2Base();
  const o = await upd(okMap({baseWage: 5000}));
  if (OLD) { assert.ok(o.ok, '음성 대조: 정정 경로는 최저임금을 보지 않았다'); return; }
  assert.strictEqual(code(o), 'WAGE_BELOW_MINIMUM');
});

test('W6 소수 원 공제 · 음수 항목 — 거절', async () => {
  m2Base();
  let o = await upd(okMap({incomeTaxDeduction: 3489.5, netWage: 102510.5}));
  if (OLD) return;
  assert.strictEqual(o.e.code, 'invalid-argument'); // 기존 실수령 정수 검사 또는 새 필드 검사가 먼저 막는다
  o = await upd(okMap({incomeTaxDeduction: 3489.5}));
  assert.strictEqual(code(o), 'WAGE_FIELD_INVALID');
  o = await upd(okMap({overtimeAmount: -1, totalAmount: 105999, netWage: 102509}));
  assert.strictEqual(code(o), 'WAGE_FIELD_INVALID');
  assert.strictEqual(w1().finalWage, 96000, '쓰기 0');
});

test('W7 T-01 레거시(실수령 0 · 세전 > 0) — 지금처럼 서버가 세전 − 공제로 finalWage(동치)', async () => {
  m2Base();
  const o = await upd(okMap({netWage: 0}));
  assert.ok(o.ok, o.e && o.e.message);
  assert.strictEqual(w1().finalWage, 102510);
});

// ═════════════ impl_37 — 중간정산 처리 거절 사유 코드 ═════════════
test('P1 처리 거절(계좌 스냅샷) — 문구·괄호 사유 그대로 + details.code = 그 사유', async () => {
  base();
  F.put('users/w2', {role: 'USER', bankAccountVersion: 2, bankbookDocumentVersion: 1});
  F.put('attendance/x1', {userId: 'w2', businessId: 'b1', applicationId: 'a2', wageStatus: 'confirmed', finalWage: 100000,
    wageDetail: {netWage: 100000}, activeInterimSettlementId: 'r1', workDate: new Ts(NOW - 5 * DAY),
    wageAccountSnapshotVersion: 1, wageAccountBankName: 'A', wageAccountNumberEncrypted: 'E', wageAccountHolder: 'h',
    wageAccountSnapshotAt: new Ts(NOW - DAY), wageAccountSourceBankAccountVersion: 1, wageAccountSourceBankbookDocumentVersion: 1});
  F.put('interim_settlement_requests/r1', {businessId: 'b1', workerId: 'w2', status: 'APPROVED', attendanceIds: ['x1'],
    requestedAmount: 100000, netAmount: 100000, periodStart: new Ts(NOW - 6 * DAY), periodEnd: new Ts(NOW - 5 * DAY)});
  const o = await go(X.callableProcessInterimSettlement, {settlementRequestId: 'r1', businessId: 'b1'});
  assert.ok(!o.ok);
  assert.strictEqual(o.e.code, 'failed-precondition');
  const m = /\(([A-Za-z_]+)\)$/.exec(o.e.message);
  assert.ok(m, o.e.message);
  if (OLD) { assert.ok(!o.e.details, '음성 대조: 이전 원문은 details 없음'); return; }
  assert.strictEqual(o.e.details.code, m[1]);
  assert.strictEqual(o.e.details.attendanceId, 'x1');
});
