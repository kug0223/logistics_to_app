'use strict';
/**
 * [AUD-1 A2 · A12 · AUD-4 H3] 비유한 금액 거절 · 신분증 열람 요청 서버 파생 값 · 내 지원 목록 상한에서 진행 중 관계 누락 0.
 *   S296B_EXPECT_OLD=1 이면 이전 원문에서 결함을 재현한다.
 */
const {test} = require('node:test');
const assert = require('assert');
const {createFakeFirestore} = require('./consent_r4d_fakestore');
const {loadIndexClosure} = require('./auth_kakao_index_harness');

const OLD = process.env.S296B_EXPECT_OLD === '1';
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
const {exports: X} = loadIndexClosure(['callableCalculateAndConfirmWage', 'callableCreateIdCardAccessRequest', 'callableGetMyApplications'],
  F, {HttpsError, console: QCON, Date: FakeDate});
const Ts = F.Ts;
const go = async (fn, data, uid = 'own1') => {
  try { return {ok: true, r: await fn({data, auth: {uid, token: {}}})}; } catch (e) { return {ok: false, e}; }
};
const code = (o) => o.e && ((o.e.details && o.e.details.code) || o.e.code);

function base() {
  F.reset();
  F.put('users/own1', {role: 'BUSINESS_ADMIN', accountStatus: 'active', name: '사장', businessId: 'b1'});
  F.put('users/w1', {role: 'USER', accountStatus: 'active', name: '근로자'});
  F.put('businesses/b1', {name: '평택', ownerId: 'own1', adminIds: ['own1'], isApproved: true});
  F.put('applications/a1', {uid: 'w1', businessId: 'b1', toId: 't1', status: 'CONFIRMED'});
}

const calc = (o) => go(X.callableCalculateAndConfirmWage, Object.assign({attendanceId: 'att1', wageType: 'hourly', baseWage: 12000,
  workDate: '2026-11-25', scheduledStart: '09:00', scheduledEnd: '18:00', actualStart: '09:00', actualEnd: '18:00',
  breakMinutes: 60, nightAllowanceApplied: false, nightIncluded: false, taxDeductionType: 'none', yearMonth: '2026-11'}, o));

test('A2 additionalAmount Infinity(1e400)·소수·문자열 · breakMinutes NaN — 입력 단계 거절(WAGE_FIELD_INVALID)', async () => {
  for (const bad of [{additionalAmount: Infinity}, {additionalAmount: 1000.5}, {additionalAmount: '5000'},
    {breakMinutes: NaN}, {scheduledBreakMinutes: 30.5}]) {
    base();
    const o = await calc(bad);
    if (OLD) { assert.notStrictEqual(code(o), 'WAGE_FIELD_INVALID'); continue; }
    assert.strictEqual(code(o), 'WAGE_FIELD_INVALID', JSON.stringify(bad));
  }
  base();
  const ok = await calc({additionalAmount: 5000});
  assert.notStrictEqual(code(ok), 'WAGE_FIELD_INVALID', '정상 값은 입력 단계 통과');
});

const req = (o = {}) => go(X.callableCreateIdCardAccessRequest, Object.assign({requesterId: 'own1', requesterName: '사칭이름',
  requesterBusinessId: 'b1', requesterBusinessName: '다른 회사', targetUserId: 'w1', targetUserName: '근로자', reason: 'TAX'}, o));

test('A12 신분증 열람 요청 — 가짜 applicationId 거절 · 사업장명/요청자명은 서버 값 · applicationId 없으면 서버가 확정 지원서로', async () => {
  base();
  let o = await req({applicationId: 'fake'});
  if (OLD) {
    assert.ok(o.ok, '음성 대조: 이전 원문은 가짜 지원서 id 로 요청을 만든다');
    const doc = Object.entries(F.dump()).find(([k]) => k.startsWith('idCardAccessRequests/'))[1];
    assert.strictEqual(doc.requesterBusinessName, '다른 회사', '음성 대조: 위조 사업장명 저장');
    return;
  }
  assert.strictEqual(code(o), 'APPLICATION_MISMATCH');
  base();
  o = await req();
  assert.ok(o.ok, o.e && o.e.message);
  const doc = F.get(`idCardAccessRequests/${o.r.requestId}`);
  assert.strictEqual(doc.requesterBusinessName, '평택');
  assert.strictEqual(doc.requesterName, '사장');
  assert.strictEqual(doc.applicationId, 'a1');
  base();
  o = await req({reason: {x: 1}});
  assert.strictEqual(o.e.code, 'invalid-argument');
});

test('H3 내 지원 목록 — 상한을 넘으면(문서 id 순) 빠질 수 있던 확정 근무를 덧붙인다 · 커서는 원래 페이지 기준', async () => {
  base();
  F.del('applications/a1');
  for (let i = 0; i < 5; i++) F.put(`applications/a${i}`, {uid: 'w1', businessId: 'b1', toId: 't1', status: 'CANCELED'});
  F.put('applications/z9', {uid: 'w1', businessId: 'b1', toId: 't1', status: 'CONFIRMED', workDate: new Ts(NOW)});
  const o = await go(X.callableGetMyApplications, {limit: 2}, 'w1');
  assert.ok(o.ok, o.e && o.e.message);
  const ids = o.r.applications.map((a) => a.id);
  assert.strictEqual(o.r.hasMore, true);
  if (OLD) { assert.ok(!ids.includes('z9'), '음성 대조: 이전 원문은 오늘 확정 근무가 빠진다'); return; }
  assert.ok(ids.includes('z9'));
  assert.strictEqual(o.r.activeIncluded, 1);
  assert.strictEqual(o.r.lastDocId, 'a1', '커서는 원래 페이지 마지막');
  const o2 = await go(X.callableGetMyApplications, {limit: 10}, 'w1');
  assert.strictEqual(o2.r.hasMore, false);
  assert.strictEqual(o2.r.activeIncluded, 0, '안 잘리면 덧붙임 0(동치)');
});
