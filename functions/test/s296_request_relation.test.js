'use strict';
/**
 * [판정297 승인 callable · F296-56 CH1 · F296-56b CH5] 요청형 문서 처리의 대상 소속 대조.
 *   SCR(일정 변경) 승인·거절 모두 지원서 uid/biz 대조 + 생성 주체별 유형 검증 · 어긋나면 보류(코드) · 알림 0.
 *   PCR(지급방식 변경) 승인·거절·효력 해석 모두 지원서 사업장 == 요청 businessId · 지원서 uid == 요청 workerId.
 *   S296R_EXPECT_OLD=1 이면 이전 원문에서 결함을 재현한다.
 */
const {test} = require('node:test');
const assert = require('assert');
const {createFakeFirestore} = require('./consent_r4d_fakestore');
const {loadIndexClosure} = require('./auth_kakao_index_harness');

const OLD = process.env.S296R_EXPECT_OLD === '1';
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
const {exports: X} = loadIndexClosure(['callableApproveScheduleChangeRequest', 'callableApprovePaymentChangeRequest',
  'callableRejectPaymentChangeRequest', 'srvResolveEffectivePaySchedule'], F, {HttpsError, console: QCON, Date: FakeDate});
const Ts = F.Ts;
const go = async (fn, data, uid) => {
  try { return {ok: true, r: await fn({data, auth: {uid, token: {}}})}; } catch (e) { return {ok: false, e}; }
};
const code = (o) => o.e && ((o.e.details && o.e.details.code) || o.e.code);
const jobs = () => Object.entries(F.dump()).filter(([k]) => /^notification_jobs\//.test(k) || /notifications\//.test(k));
const jobFor = (uid) => jobs().filter(([, v]) => JSON.stringify(v).includes(`"${uid}"`)).length;

function base() {
  F.reset();
  F.put('users/own1', {role: 'BUSINESS_ADMIN', accountStatus: 'active', name: '사장', businessId: 'b1'});
  F.put('users/own2', {role: 'BUSINESS_ADMIN', accountStatus: 'active', name: '다른', businessId: 'b2'});
  F.put('businesses/b1', {name: 'b1', ownerId: 'own1', adminIds: ['own1'], isApproved: true});
  F.put('businesses/b2', {name: 'b2', ownerId: 'own2', adminIds: ['own2'], isApproved: true});
  F.put('users/w1', {role: 'USER', name: '근로자'});
  F.put('users/victim', {role: 'USER', name: '무관'});
  F.put('applications/a1', {uid: 'w1', businessId: 'b1', toId: 't1', status: 'CONFIRMED', workDate: new Ts(NOW - 10 * DAY),
    desiredStartDate: new Ts(NOW - 10 * DAY), payScheduleType: 'monthly', payScheduleDay: 10, leaveDates: [], extraWorkDates: []});
}
const scr = (id, o) => F.put(`schedule_change_requests/${id}`, Object.assign({applicationId: 'a1', businessId: 'b1',
  applicantUid: 'w1', targetDate: new Ts(NOW + 2 * DAY), requestType: 'LEAVE', requestedBy: 'APPLICANT', requestedByUid: 'w1',
  status: 'PENDING', requestedAt: new Ts(NOW - 60000)}, o));
const approveScr = (action, uid = 'own1') => go(X.callableApproveScheduleChangeRequest, {requestId: 's1', action, rejectReason: 'x'}, uid);

test('SC1 거절 — 관계없는 사용자(applicantUid=victim)를 넣은 요청은 처리·알림 0(보류)', async () => {
  base(); scr('s1', {applicantUid: 'victim', requestedByUid: 'victim'});
  const o = await approveScr('REJECTED');
  if (OLD) {
    assert.ok(o.ok, '음성 대조: 이전 원문은 거절을 처리한다');
    assert.ok(jobFor('victim') > 0, '음성 대조: 무관 사용자에게 알림');
    return;
  }
  assert.ok(!o.ok);
  assert.strictEqual(code(o), 'SCR_RELATION_MISMATCH');
  assert.strictEqual(F.get('schedule_change_requests/s1').status, 'PENDING');
  assert.strictEqual(jobFor('victim'), 0);
});

test('SC2 거절 — 다른 사업장 지원서를 가리키는 요청(요청 biz=b1 · 지원서 biz=b2) 보류', async () => {
  base(); F.put('applications/a2', {uid: 'w1', businessId: 'b2', status: 'CONFIRMED'});
  scr('s1', {applicationId: 'a2'});
  const o = await approveScr('REJECTED');
  if (OLD) { assert.ok(o.ok); return; }
  assert.strictEqual(code(o), 'SCR_RELATION_MISMATCH');
});

test('SC3 생성 주체별 유형 — APPLICANT 인데 EXTRA_WORK · ADMIN 인데 LEAVE · 모르는 requestedBy → 보류(승인·거절 모두)', async () => {
  for (const [o, action] of [[{requestType: 'EXTRA_WORK'}, 'APPROVED'], [{requestedBy: 'ADMIN', requestedByUid: 'own1'}, 'REJECTED'],
    [{requestedBy: 'WORKER'}, 'REJECTED'], [{requestedByUid: 'own1'}, 'REJECTED']]) {
    base(); scr('s1', o);
    const r = await approveScr(action);
    if (OLD) continue;
    assert.strictEqual(code(r), 'SCR_TYPE_INVALID', JSON.stringify(o));
    assert.strictEqual(F.get('schedule_change_requests/s1').status, 'PENDING');
  }
});

test('SC4 정상 동치 — 근로자 휴무 요청 승인(leaveDates 추가 · 알림) · 거절(상태 · 알림) · 관리자 추가근무 요청 승인', async () => {
  base(); scr('s1', {});
  let o = await approveScr('APPROVED');
  assert.ok(o.ok, o.e && o.e.message);
  assert.strictEqual(F.get('schedule_change_requests/s1').status, 'APPROVED');
  assert.strictEqual(F.get('applications/a1').leaveDates.length, 1);
  assert.ok(jobFor('w1') > 0);
  base(); scr('s1', {});
  o = await approveScr('REJECTED');
  assert.ok(o.ok, o.e && o.e.message);
  assert.strictEqual(F.get('schedule_change_requests/s1').status, 'REJECTED');
  base(); scr('s1', {requestType: 'EXTRA_WORK', requestedBy: 'ADMIN', requestedByUid: 'own1'});
  o = await approveScr('APPROVED');
  assert.ok(o.ok, o.e && o.e.message);
  assert.strictEqual(F.get('applications/a1').extraWorkDates.length, 1);
});

const pcr = (id, o) => F.put(`payment_change_requests/${id}`, Object.assign({applicationId: 'a1', businessId: 'b1', workerId: 'w1',
  currentPayScheduleType: 'monthly', currentPayScheduleDay: 10, requestedPayScheduleType: 'weekly', requestedPayScheduleDay: 5,
  effectiveFrom: '2026-11-01', status: 'PENDING', createdAt: new Ts(NOW - 60000)}, o));
const promise = {payScheduleType: 'monthly', payScheduleDay: 10, payScheduleTime: undefined, source: 'APPLICATION'};

test('PC1 CH5 — 다른 사업장(b2) 소유자가 남의 지원서(a1) 요청을 자기 사업장으로 승인 → 거절 · 지급일정 불변', async () => {
  base(); pcr('p1', {businessId: 'b2'});
  const o = await go(X.callableApprovePaymentChangeRequest, {businessId: 'b2', requestId: 'p1'}, 'own2');
  const after = await X.srvResolveEffectivePaySchedule(promise, 'a1', '2026-11-27');
  if (OLD) {
    assert.ok(o.ok, '음성 대조: 이전 원문은 승인한다');
    assert.strictEqual(after.payScheduleType, 'weekly', '음성 대조: 남의 지급일정이 바뀐다');
    return;
  }
  assert.strictEqual(code(o), 'PCR_RELATION_MISMATCH');
  assert.strictEqual(F.get('payment_change_requests/p1').status, 'PENDING');
  assert.strictEqual(after.amended, false);
  assert.strictEqual(after.payScheduleType, 'monthly');
});

test('PC2 효력 해석 — 이미 APPROVED 로 만들어진 어긋난 문서(biz 다름 · worker 다름)는 무시 · 맞는 문서는 적용', async () => {
  base();
  pcr('pbad1', {businessId: 'b2', status: 'APPROVED', processedAt: new Ts(NOW - 1000), effectiveFrom: '2026-11-20'});
  pcr('pbad2', {workerId: 'victim', status: 'APPROVED', processedAt: new Ts(NOW - 1000), effectiveFrom: '2026-11-21'});
  let r = await X.srvResolveEffectivePaySchedule(promise, 'a1', '2026-11-27');
  if (OLD) { assert.strictEqual(r.amended, true, '음성 대조: 어긋난 APPROVED 가 효력을 가진다'); return; }
  assert.strictEqual(r.amended, false);
  pcr('pok', {status: 'APPROVED', processedAt: new Ts(NOW - 500), effectiveFrom: '2026-11-01', requestedPayScheduleDay: 3});
  r = await X.srvResolveEffectivePaySchedule(promise, 'a1', '2026-11-27');
  assert.strictEqual(r.amended, true);
  assert.strictEqual(r.amendmentId, 'pok');
  assert.strictEqual(r.payScheduleType, 'weekly');
});

test('PC3 거절도 대조 — 어긋난 요청 거절은 보류 · 정상 요청 승인/거절 동치', async () => {
  base(); pcr('p1', {workerId: 'victim'});
  let o = await go(X.callableRejectPaymentChangeRequest, {businessId: 'b1', requestId: 'p1'}, 'own1');
  if (!OLD) {
    assert.strictEqual(code(o), 'PCR_RELATION_MISMATCH');
    assert.strictEqual(F.get('payment_change_requests/p1').status, 'PENDING');
  }
  base(); pcr('p1', {});
  o = await go(X.callableApprovePaymentChangeRequest, {businessId: 'b1', requestId: 'p1'}, 'own1');
  assert.ok(o.ok, o.e && o.e.message);
  assert.strictEqual(F.get('payment_change_requests/p1').status, 'APPROVED');
  base(); pcr('p1', {});
  o = await go(X.callableRejectPaymentChangeRequest, {businessId: 'b1', requestId: 'p1'}, 'own1');
  assert.ok(o.ok, o.e && o.e.message);
  assert.strictEqual(F.get('payment_change_requests/p1').status, 'REJECTED');
});
