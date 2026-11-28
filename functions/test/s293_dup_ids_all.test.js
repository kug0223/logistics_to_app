'use strict';
/**
 * [판정293 · impl_32 §5 같은 꼴 · 대표 규칙 '근본까지'] 배열 id 중복 입력 — 중간정산 2종 · 저장 요청 방어 · 노쇼 취소 좌석 · LOW 응답 수치.
 *   DUP_EXPECT_OLD=1 이면 이전 원문(e90ab88e 사본)에서 결함을 재현하고, 정상 데이터 셀은 같은 기대값으로 동치를 고정한다.
 */
const {test} = require('node:test');
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const {createFakeFirestore} = require('./consent_r4d_fakestore');
const {loadIndexClosure} = require('./auth_kakao_index_harness');

const OLD = process.env.DUP_EXPECT_OLD === '1';
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
const {exports: X} = loadIndexClosure(['callableRequestInterimSettlement', 'callableAdminDirectInterimSettlement',
  'callableApproveInterimSettlement', 'callableProcessInterimSettlement', 'callableCancelApprovedInterimSettlement',
  'callableBatchCancelNoShow', 'callableBatchResetAttendance', 'callableBatchAdminConfirm', 'callableBatchAdjustAttendanceTime'],
F, {HttpsError, console: QCON, Date: FakeDate});
const Ts = F.Ts;
const SRC = fs.readFileSync(path.join(__dirname, '..', 'src', 'index.ts'), 'utf8');
const go = async (fn, data, uid = 'own1') => {
  try { return {ok: true, r: await fn({data, auth: {uid, token: {}}})}; } catch (e) { return {ok: false, e}; }
};
const ACCT = {wageAccountSnapshotVersion: 1, wageAccountBankName: '국민', wageAccountNumberEncrypted: 'enc', wageAccountHolder: '근로자',
  wageAccountSnapshotAt: new Ts(NOW - 5 * DAY), wageAccountSourceBankAccountVersion: 1, wageAccountSourceBankbookDocumentVersion: 1};
function base() {
  F.reset();
  F.put('users/own1', {role: 'BUSINESS_ADMIN', accountStatus: 'active', name: '사장'});
  F.put('businesses/b1', {name: '평택', ownerId: 'own1', adminIds: ['own1']});
  F.put('users/w1', {role: 'USER', accountStatus: 'active', name: '근로자', bankAccountVersion: 1, bankbookDocumentVersion: 1});
  F.put('applications/a1', {uid: 'w1', businessId: 'b1', toId: 't1', slotId: 's1', wdId: 'wd1', status: 'CONFIRMED'});
}
const att = (id, o = {}) => F.put(`attendance/${id}`, Object.assign({userId: 'w1', businessId: 'b1', applicationId: 'a1',
  wageStatus: 'confirmed', finalWage: 100000, wageDetail: {netWage: 90000}, workDate: new Ts(NOW - 7 * DAY), status: 'completed'}, ACCT, o));
const isrDocs = () => Object.entries(F.dump()).filter(([k]) => /^interim_settlement_requests\/[^/]+$/.test(k)).map(([, v]) => v);
const reqData = (o = {}) => Object.assign({businessId: 'b1', applicationId: 'a1', businessName: '평택', workerName: '근로자',
  periodStart: '2026-11-01', periodEnd: '2026-11-20', attendanceIds: ['x1'], requestedAmount: 1, netAmount: 1}, o);
const isr = (id, o) => F.put(`interim_settlement_requests/${id}`, Object.assign({businessId: 'b1', workerId: 'w1', applicationId: 'a1',
  workerName: '근로자', businessName: '평택', periodStart: new Ts(NOW - 20 * DAY), periodEnd: new Ts(NOW - 7 * DAY),
  attendanceIds: ['x1', 'x2'], requestedAmount: 200000, netAmount: 180000, status: 'PENDING', createdAt: new Ts(NOW - DAY)}, o));
const jobBodies = () => Object.entries(F.dump()).filter(([k]) => /^notification_jobs\//.test(k)).map(([, v]) => v.payload && v.payload.body);

// ── 중간정산 요청(근로자) ──
test('I1 요청 — 같은 근태 3번이어도 금액·저장 목록·알림 건수는 고유 1건 기준', async () => {
  base(); att('x1');
  const o = await go(X.callableRequestInterimSettlement, reqData({attendanceIds: ['x1', 'x1', 'x1']}), 'w1');
  assert.ok(o.ok, o.e && o.e.message);
  const d = isrDocs()[0];
  if (OLD) {
    assert.strictEqual(d.requestedAmount, 300000, '음성 대조: 이전 원문은 3배');
    return;
  }
  assert.strictEqual(d.requestedAmount, 100000);
  assert.strictEqual(d.netAmount, 90000);
  assert.deepStrictEqual(d.attendanceIds, ['x1']);
  assert.ok(jobBodies().every((b) => !b || b.includes(' 1건 중간정산')), '관리자 알림 건수 = 고유 1');
});

test('I2 요청 — 고유 입력은 이전과 같은 결과(동치)', async () => {
  base(); att('x1'); att('x2', {finalWage: 50000, wageDetail: {netWage: 45000}});
  const o = await go(X.callableRequestInterimSettlement, reqData({attendanceIds: ['x2', 'x1']}), 'w1');
  assert.ok(o.ok, o.e && o.e.message);
  const d = isrDocs()[0];
  assert.strictEqual(d.requestedAmount, 150000);
  assert.strictEqual(d.netAmount, 135000);
  assert.deepStrictEqual(d.attendanceIds, ['x2', 'x1']);
});

test('I3 요청 — 형식이 틀린 id 는 쓰기 전 invalid-argument', async () => {
  base(); att('x1');
  const o = await go(X.callableRequestInterimSettlement, reqData({attendanceIds: ['x1', '']}), 'w1');
  if (OLD) return;
  assert.ok(!o.ok);
  assert.strictEqual(o.e.code, 'invalid-argument');
  assert.strictEqual(isrDocs().length, 0);
});

// ── 관리자 직접 정산 ──
test('D1 직접 정산 — 같은 근태 2번이어도 정산 금액·목록은 고유 기준', async () => {
  base(); att('x1');
  const o = await go(X.callableAdminDirectInterimSettlement, {businessId: 'b1', workerId: 'w1', workerName: '근로자',
    businessName: '평택', applicationId: 'a1', attendanceIds: ['x1', 'x1']});
  assert.ok(o.ok, o.e && o.e.message);
  const d = isrDocs()[0];
  if (OLD) { assert.strictEqual(d.netAmount, 200000, '음성 대조: 이전 원문은 2배'); return; }
  // [판정294 F294-MONEY-01] 세전 = finalWage 100,000 · 실수령 = wageDetail.netWage 90,000(요청→승인→처리와 같은 식)
  assert.strictEqual(d.requestedAmount, 100000);
  assert.strictEqual(d.netAmount, 90000);
  assert.deepStrictEqual(d.attendanceIds, ['x1']);
  assert.strictEqual(F.get('attendance/x1').wageStatus, 'transferred');
});

test('D2 직접 정산 — 고유 입력 동치', async () => {
  base(); att('x1'); att('x2', {finalWage: 50000, wageDetail: {netWage: 45000}});
  const o = await go(X.callableAdminDirectInterimSettlement, {businessId: 'b1', workerId: 'w1', workerName: '근로자',
    businessName: '평택', applicationId: 'a1', attendanceIds: ['x1', 'x2']});
  assert.ok(o.ok, o.e && o.e.message);
  // [판정294 F294-MONEY-01] 이전 원문(e90ab88e·e64e1d42)은 세전 합을 실수령 칸에 썼다(음성 대조)
  if (OLD) { assert.strictEqual(isrDocs()[0].netAmount, 150000); return; }
  assert.strictEqual(isrDocs()[0].requestedAmount, 150000);
  assert.strictEqual(isrDocs()[0].netAmount, 135000);
  assert.deepStrictEqual(isrDocs()[0].attendanceIds, ['x1', 'x2']);
});

// ── 이미 저장된 요청 방어 ──
test('S1 승인 — 저장 목록에 같은 근태 2번(예전 writer) → 거절(INTERIM_DUPLICATE_ATTENDANCE) · 쓰기 0', async () => {
  base(); att('x1');
  isr('r1', {attendanceIds: ['x1', 'x1'], requestedAmount: 200000, netAmount: 180000});
  const before = F.W.commits.length;
  const o = await go(X.callableApproveInterimSettlement, {settlementRequestId: 'r1', businessId: 'b1', scheduledTransferDate: '2026-11-30'});
  if (OLD) {
    assert.ok(o.ok, '음성 대조: 이전 원문은 승인한다');
    assert.strictEqual(F.get('interim_settlement_requests/r1').requestedAmount, 200000, '음성 대조: 2배 금액으로 재고정');
    return;
  }
  assert.ok(!o.ok);
  assert.strictEqual(o.e.code, 'failed-precondition');
  assert.strictEqual(o.e.details.code, 'INTERIM_DUPLICATE_ATTENDANCE');
  assert.strictEqual(F.get('interim_settlement_requests/r1').status, 'PENDING');
  assert.strictEqual(F.get('attendance/x1').activeInterimSettlementId, undefined);
  assert.strictEqual(F.W.commits.length, before, '쓰기 0');
});

test('S2 승인 — 정상 요청은 이전과 같은 결과(재고정 · lock)', async () => {
  base(); att('x1'); att('x2', {finalWage: 50000, wageDetail: {netWage: 45000}});
  isr('r1', {attendanceIds: ['x1', 'x2'], requestedAmount: 150000, netAmount: 135000});
  const o = await go(X.callableApproveInterimSettlement, {settlementRequestId: 'r1', businessId: 'b1', scheduledTransferDate: '2026-11-30'});
  assert.ok(o.ok, o.e && o.e.message);
  const r = F.get('interim_settlement_requests/r1');
  assert.strictEqual(r.status, 'APPROVED');
  assert.strictEqual(r.requestedAmount, 150000);
  assert.strictEqual(r.netAmount, 135000);
  assert.strictEqual(F.get('attendance/x1').activeInterimSettlementId, 'r1');
  assert.strictEqual(F.get('attendance/x2').activeInterimSettlementId, 'r1');
});

test('S3 이체 처리 — 승인된 중복 요청 → 거절 · 이체 0', async () => {
  base(); att('x1', {activeInterimSettlementId: 'r1'});
  isr('r1', {attendanceIds: ['x1', 'x1'], requestedAmount: 200000, netAmount: 180000, status: 'APPROVED'});
  const o = await go(X.callableProcessInterimSettlement, {settlementRequestId: 'r1', businessId: 'b1'});
  if (OLD) {
    assert.ok(o.ok, '음성 대조: 이전 원문은 2배 금액 요청을 이체 처리한다(금액 검사도 2배끼리 비교)');
    return;
  }
  assert.ok(!o.ok);
  assert.strictEqual(o.e.details.code, 'INTERIM_DUPLICATE_ATTENDANCE');
  assert.strictEqual(F.get('attendance/x1').wageStatus, 'confirmed');
  assert.strictEqual(F.get('interim_settlement_requests/r1').status, 'APPROVED');
});

test('S4 이체 처리 — 정상 요청 동치', async () => {
  base(); att('x1', {activeInterimSettlementId: 'r1'});
  isr('r1', {attendanceIds: ['x1'], requestedAmount: 100000, netAmount: 90000, status: 'APPROVED'});
  const o = await go(X.callableProcessInterimSettlement, {settlementRequestId: 'r1', businessId: 'b1'});
  assert.ok(o.ok, o.e && o.e.message);
  assert.strictEqual(F.get('attendance/x1').wageStatus, 'transferred');
  assert.strictEqual(F.get('interim_settlement_requests/r1').status, 'PROCESSED');
});

test('S5 승인 취소 — 중복 요청도 빠져나갈 수 있다(거절 0 · lock 해제)', async () => {
  base(); att('x1', {activeInterimSettlementId: 'r1'});
  isr('r1', {attendanceIds: ['x1', 'x1'], requestedAmount: 200000, netAmount: 180000, status: 'APPROVED'});
  const o = await go(X.callableCancelApprovedInterimSettlement, {settlementRequestId: 'r1', businessId: 'b1', cancelReason: '중복'});
  assert.ok(o.ok, o.e && o.e.message);
  assert.strictEqual(F.get('interim_settlement_requests/r1').status, 'CANCELED');
  assert.strictEqual(F.get('attendance/x1').activeInterimSettlementId, undefined);
  const lockWrites = F.W.commits.flatMap((c) => c.writes).filter((w) => w.path === 'attendance/x1').length;
  assert.strictEqual(lockWrites, OLD ? 2 : 1, '새 원문은 고유 근태마다 1회');
});

// ── 노쇼 취소 좌석 복원 ──
function seatBase() {
  base();
  F.put('tos/t1', {businessId: 'b1', status: 'ACTIVE', totalConfirmed: 0, totalRequired: 3});
  F.put('tos/t1/slots/s1', {status: 'open', confirmedCount: 0, workDetails: [{wdId: 'wd1', requiredCount: 3}],
    workDetailCounts: {wd1: {confirmedCount: 0}}});
  F.put('applications/a1', {uid: 'w1', businessId: 'b1', toId: 't1', slotId: 's1', wdId: 'wd1', status: 'CONFIRMED',
    staffingReleasedAt: new Ts(NOW - DAY), staffingReleased: true});
}
const seats = () => [F.get('tos/t1').totalConfirmed, F.get('tos/t1/slots/s1').confirmedCount,
  F.get('tos/t1/slots/s1').workDetailCounts.wd1.confirmedCount];

test('N1 같은 근태 2번 — 좌석 +1', async () => {
  seatBase(); att('n1', {status: 'NO_SHOW', finalWage: 0});
  const o = await go(X.callableBatchCancelNoShow, {businessId: 'b1', attendanceIds: ['n1', 'n1']});
  assert.ok(o.ok, o.e && o.e.message);
  assert.deepStrictEqual(seats(), OLD ? [2, 2, 2] : [1, 1, 1]);
  if (!OLD) assert.strictEqual(o.r.processed, 1);
});

test('N2 같은 지원서의 다른 근태 2건 — 좌석은 지원서 기준 +1', async () => {
  seatBase(); att('n1', {status: 'NO_SHOW', finalWage: 0}); att('n2', {status: 'NO_SHOW', finalWage: 0});
  const o = await go(X.callableBatchCancelNoShow, {businessId: 'b1', attendanceIds: ['n1', 'n2']});
  assert.ok(o.ok, o.e && o.e.message);
  assert.deepStrictEqual(seats(), OLD ? [2, 2, 2] : [1, 1, 1]);
  assert.strictEqual(F.get('attendance/n1').status, undefined, '두 근태 모두 노쇼 해제');
  assert.strictEqual(F.get('attendance/n2').status, undefined);
});

test('N3 경합 — 사전 조회 뒤 · 거래 전에 다른 호출이 이미 복원(staffingReleasedAt 해제) → 추가 복원 0', async () => {
  seatBase(); att('n1', {status: 'NO_SHOW', finalWage: 0});
  let fired = false;
  F.hooks.afterGet = (p, txId) => {
    if (!fired && txId != null) {
      fired = true;
      const a = F.get('applications/a1'); delete a.staffingReleasedAt; delete a.staffingReleased; F.put('applications/a1', a);
      F.put('tos/t1', Object.assign(F.get('tos/t1'), {totalConfirmed: 1}));
    }
  };
  const o = await go(X.callableBatchCancelNoShow, {businessId: 'b1', attendanceIds: ['n1']});
  F.hooks.afterGet = null;
  assert.ok(o.ok, o.e && o.e.message);
  assert.strictEqual(F.get('tos/t1').totalConfirmed, 1, '다른 호출이 한 복원 1 위에 더하지 않는다');
});

test('N4 순차 두 호출(n1 → n2 같은 지원서) — 합계 +1', async () => {
  seatBase(); att('n1', {status: 'NO_SHOW', finalWage: 0}); att('n2', {status: 'NO_SHOW', finalWage: 0});
  assert.ok((await go(X.callableBatchCancelNoShow, {businessId: 'b1', attendanceIds: ['n1']})).ok);
  assert.ok((await go(X.callableBatchCancelNoShow, {businessId: 'b1', attendanceIds: ['n2']})).ok);
  assert.deepStrictEqual(seats(), [1, 1, 1]);
});

// ── LOW: 응답 수치 ──
test('L1 근태 초기화 — 같은 id 2번이어도 processed 1', async () => {
  base(); att('r1', {wageStatus: 'pending', status: 'completed'});
  const o = await go(X.callableBatchResetAttendance, {businessId: 'b1', attendanceIds: ['r1', 'r1']});
  assert.ok(o.ok, o.e && o.e.message);
  assert.strictEqual(o.r.processed, OLD ? 2 : 1);
});

test('L2 관리자 확인 — 같은 id 2번이어도 processed 1', async () => {
  base(); att('c1');
  const o = await go(X.callableBatchAdminConfirm, {businessId: 'b1', attendanceIds: ['c1', 'c1'], confirmed: true});
  assert.ok(o.ok, o.e && o.e.message);
  assert.strictEqual(o.r.processed, OLD ? 2 : 1);
  assert.strictEqual(F.get('attendance/c1').adminConfirmed, true);
});

test('L3 시간 일괄 조정 — 같은 출근기록 두 번(다른 시각) → 거절(조용히 마지막 값 적용 0)', async () => {
  base(); att('j1', {wageStatus: 'pending', checkIn: new Ts(NOW - 7 * DAY), checkOut: new Ts(NOW - 7 * DAY + 8 * 3600000)});
  const e1 = {attendanceId: 'j1', checkInMs: NOW - 7 * DAY + 3600000, status: 'completed', resetWageDetail: true, reason: '정정'};
  const e2 = Object.assign({}, e1, {checkInMs: NOW - 7 * DAY + 2 * 3600000});
  const o = await go(X.callableBatchAdjustAttendanceTime, {businessId: 'b1', entries: [e1, e2]});
  if (OLD) {
    assert.ok(!(o.e && o.e.details && o.e.details.code === 'DUPLICATE_ATTENDANCE_ID'), '음성 대조: 이전 원문은 중복을 따로 거절하지 않는다');
    return;
  }
  assert.ok(!o.ok);
  assert.strictEqual(o.e.code, 'invalid-argument');
  assert.strictEqual(o.e.details.code, 'DUPLICATE_ATTENDANCE_ID');
  assert.strictEqual(F.get('attendance/j1').checkIn.toMillis(), NOW - 7 * DAY, '쓰기 0');
});

test('L4 원문 — 입력 고유화 helper 를 쓰는 callable(동적 시험 밖 LOW 포함)', () => {
  if (OLD) return;
  for (const [fn, field] of [['callableMarkTransferredBatch', 'attendanceIds'], ['callableRequestInterimSettlement', 'attendanceIds'],
    ['callableAdminDirectInterimSettlement', 'attendanceIds'], ['callableBatchCancelNoShow', 'attendanceIds'],
    ['callableBatchResetAttendance', 'attendanceIds'], ['callableBatchAdminConfirm', 'attendanceIds'],
    ['callableRefreshWagePaymentSnapshot', 'attendanceIds'], ['callableConfirmFinalWage', 'attendanceIds'],
    ['callableCancelFinalConfirmation', 'attendanceIds'], ['callableReopenSlots', 'slotIds'], ['callableCloseSlots', 'slotIds']]) {
    const a = SRC.indexOf(`export const ${fn} = onCall(`);
    const body = SRC.slice(a, SRC.indexOf('\n);\n', a));
    assert.ok(body.includes(`srvNormalizeIdList(`) && body.includes(`"${field}")`), fn);
  }
  for (const fn of ['callableApproveInterimSettlement', 'callableProcessInterimSettlement']) {
    const a = SRC.indexOf(`export const ${fn} = onCall(`);
    assert.ok(SRC.slice(a, SRC.indexOf('\n);\n', a)).includes('srvInterimStoredIdsOrThrow(rd.attendanceIds)'), fn);
  }
});
