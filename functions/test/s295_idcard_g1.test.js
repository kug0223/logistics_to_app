'use strict';
/**
 * [AUD-2 G-1a/b/c] 신분증 열람권 — legacy users.businessId 로 인가하지 않고, 열람권 사업장 확정 + 호출자 현재 소속 + 지원서 확정 계열.
 *   S295G_EXPECT_OLD=1 이면 이전 원문 사본에서 결함을 재현한다. 'not-found'(이미지 없음) = 인가 단계를 지났다는 뜻(실제 이미지 열람 0).
 */
const {test} = require('node:test');
const assert = require('assert');
const {createFakeFirestore} = require('./consent_r4d_fakestore');
const {loadIndexClosure} = require('./auth_kakao_index_harness');

const OLD = process.env.S295G_EXPECT_OLD === '1';
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
const {exports: X} = loadIndexClosure(['callableGetIdCardSignedUrl', 'callableCheckIdCardAccess', 'callableCheckIdCardAccessBatch'],
  F, {HttpsError, console: QCON, Date: FakeDate});
const Ts = F.Ts;
const go = async (fn, data, uid) => {
  try { return {ok: true, r: await fn({data, auth: {uid, token: {}}})}; } catch (e) { return {ok: false, e}; }
};
const code = (o) => o.e && ((o.e.details && o.e.details.code) || o.e.code);

function base(appStatus = 'CONFIRMED') {
  F.reset();
  F.put('businesses/b1', {name: '평택', ownerId: 'own1', adminIds: ['own1', 'adm2']});
  F.put('users/own1', {role: 'BUSINESS_ADMIN', name: '사장', businessId: 'b1'});
  F.put('users/adm2', {role: 'BUSINESS_ADMIN', name: '관리자', businessId: 'b1'});
  F.put('users/ex1', {role: 'BUSINESS_ADMIN', name: '전 관리자', businessId: 'b1'}); // adminIds 에 없다(legacy hint 만)
  F.put('users/sub1', {role: 'USER', name: '부', subAdminBusinessIds: ['b1']});
  F.put('businesses/b1/members/sub1', {uid: 'sub1', permissions: {canManageWage: true}});
  F.put('users/sub2', {role: 'USER', name: '부2', subAdminBusinessIds: ['b1']});
  F.put('businesses/b1/members/sub2', {uid: 'sub2', permissions: {canManageWage: false}});
  F.put('users/w1', {role: 'USER', name: '근로자'}); // 이미지 없음 → 인가를 지나면 not-found
  F.put('applications/a1', {uid: 'w1', businessId: 'b1', status: appStatus});
}
// requesterBusinessId 없는 옛 business 열람권
const legacyBizGrant = (o = {}) => F.put('idCardAccessRequests/g1', Object.assign({requesterId: 'business:b1', targetUserId: 'w1',
  applicationId: 'a1', status: 'approved', expiresAt: new Ts(NOW + DAY), respondedAt: new Ts(NOW - 3600000),
  requestedAt: new Ts(NOW - 7200000)}, o));
const url = (uid) => go(X.callableGetIdCardSignedUrl, {targetUserId: 'w1'}, uid);

test('GC1 전 관리자(legacy hint 만) + requesterBusinessId 없는 옛 business 열람권 — URL 단계로 가지 않는다', async () => {
  base(); legacyBizGrant();
  const o = await url('ex1');
  assert.ok(!o.ok);
  if (OLD) { assert.strictEqual(o.e.code, 'not-found', '음성 대조: 이전 원문은 인가를 지나 이미지 단계까지 간다'); return; }
  assert.strictEqual(o.e.code, 'permission-denied'); // 소속 사업장이 없으니 business 후보 자체를 찾지 않는다
});

test('GC2 현재 관리자 · 소유자 — 같은 열람권으로 인가 통과(동치)', async () => {
  base(); legacyBizGrant();
  for (const u of ['own1', 'adm2']) {
    const o = await url(u);
    assert.strictEqual(o.e.code, 'not-found', u);
  }
});

test('GC3 SubAdmin — 배정 + canManageWage 만 통과 · 권한 없으면 거절', async () => {
  base(); legacyBizGrant();
  assert.strictEqual((await url('sub1')).e.code, 'not-found');
  const o = await url('sub2');
  assert.strictEqual(o.e.code, 'permission-denied');
});

test('GC4 사업장을 확정할 수 없는 옛 개인 열람권(requesterBusinessId · applicationId 없음) — 열지 않는다', async () => {
  base();
  F.put('idCardAccessRequests/g2', {requesterId: 'own1', targetUserId: 'w1', status: 'approved', expiresAt: new Ts(NOW + DAY),
    respondedAt: new Ts(NOW - 3600000), requestedAt: new Ts(NOW - 7200000)});
  const o = await url('own1');
  assert.ok(!o.ok);
  if (OLD) return; // 이전 원문(판정294 fence)은 사업장도 지원서도 모르면 이미 거절 — 같은 결과
  assert.strictEqual(o.e.code, 'permission-denied');
});

test('GC5 개인 열람권 — requesterBusinessId 있고 지원서 확정이면 통과(동치)', async () => {
  base();
  F.put('idCardAccessRequests/g3', {requesterId: 'own1', requesterBusinessId: 'b1', targetUserId: 'w1', applicationId: 'a1',
    status: 'approved', expiresAt: new Ts(NOW + DAY), respondedAt: new Ts(NOW - 3600000), requestedAt: new Ts(NOW - 7200000)});
  assert.strictEqual((await url('own1')).e.code, 'not-found');
});

test('GB1 CheckIdCardAccess — 전 관리자는 business 열람권 메타데이터를 받지 않는다', async () => {
  base(); legacyBizGrant();
  const o = await go(X.callableCheckIdCardAccess, {requesterId: 'ex1', targetUserId: 'w1'}, 'ex1');
  assert.ok(o.ok, o.e && o.e.message);
  if (OLD) { assert.ok(o.r.request && o.r.request.status === 'approved', '음성 대조: legacy hint 로 열람권이 노출된다'); return; }
  assert.strictEqual(o.r.request, null);
});

test('GA1 CheckIdCardAccess — 지원서 취소된 개인 열람권은 approved 로 보이지 않는다(revoked 표시 · 저장 0)', async () => {
  base('CANCELED');
  F.put('idCardAccessRequests/g4', {requesterId: 'own1', requesterBusinessId: 'b1', targetUserId: 'w1', applicationId: 'a1',
    status: 'approved', expiresAt: new Ts(NOW + DAY), respondedAt: new Ts(NOW - 3600000), requestedAt: new Ts(NOW - 7200000)});
  const o = await go(X.callableCheckIdCardAccess, {requesterId: 'own1', targetUserId: 'w1'}, 'own1');
  assert.ok(o.ok, o.e && o.e.message);
  if (OLD) { assert.strictEqual(o.r.request.status, 'approved', '음성 대조: 표시와 URL 판정이 갈린다'); return; }
  assert.strictEqual(o.r.request.status, 'revoked');
  assert.strictEqual(o.r.request.unusableReason, 'GRANT_APPLICATION_INACTIVE');
  assert.strictEqual(F.get('idCardAccessRequests/g4').status, 'approved', '저장값은 바꾸지 않는다');
});

test('GA2 CheckIdCardAccess — 확정 지원의 열람권은 approved 그대로(동치)', async () => {
  base();
  F.put('idCardAccessRequests/g4', {requesterId: 'own1', requesterBusinessId: 'b1', targetUserId: 'w1', applicationId: 'a1',
    status: 'approved', expiresAt: new Ts(NOW + DAY), respondedAt: new Ts(NOW - 3600000), requestedAt: new Ts(NOW - 7200000)});
  const o = await go(X.callableCheckIdCardAccess, {requesterId: 'own1', targetUserId: 'w1'}, 'own1');
  assert.strictEqual(o.r.request.status, 'approved');
});

test('GBATCH CheckIdCardAccessBatch — 같은 판정(전 관리자 null · 취소 지원 revoked · 확정 approved)', async () => {
  base(); legacyBizGrant();
  let o = await go(X.callableCheckIdCardAccessBatch, {requesterId: 'ex1', targetUserIds: ['w1']}, 'ex1');
  assert.ok(o.ok, o.e && o.e.message);
  if (OLD) { assert.ok(o.r.requests.w1 && o.r.requests.w1.status === 'approved'); return; }
  assert.strictEqual(o.r.requests.w1, null);
  o = await go(X.callableCheckIdCardAccessBatch, {requesterId: 'own1', targetUserIds: ['w1']}, 'own1');
  assert.strictEqual(o.r.requests.w1.status, 'approved');
  F.put('applications/a1', Object.assign(F.get('applications/a1'), {status: 'CANCELED'}));
  o = await go(X.callableCheckIdCardAccessBatch, {requesterId: 'own1', targetUserIds: ['w1']}, 'own1');
  assert.strictEqual(o.r.requests.w1.status, 'revoked');
});

test('GC6 지원서에 사업장이 없는 열람권(사업장 확정 불가 · 지원서는 확정) — 열지 않는다', async () => {
  base();
  F.put('applications/a9', {uid: 'w1', status: 'CONFIRMED'});
  F.put('idCardAccessRequests/g6', {requesterId: 'own1', targetUserId: 'w1', applicationId: 'a9', status: 'approved',
    expiresAt: new Ts(NOW + DAY), respondedAt: new Ts(NOW - 3600000), requestedAt: new Ts(NOW - 7200000)});
  const o = await url('own1');
  assert.ok(!o.ok);
  if (OLD) { assert.strictEqual(o.e.code, 'not-found', '음성 대조: 이전 원문은 사업장 모르는 열람권으로 인가를 지난다'); return; }
  assert.strictEqual(code(o), 'NOT_CURRENT_MEMBER');
});
