'use strict';
/**
 * [판정296 §2-2] G1 같은 셀 대조 — CheckIdCardAccess 단건/배치 · GetIdCardSignedUrl 공통 판정.
 *   missing/null/빈/타입오류 requesterBusinessId · 다른 사업장 · 취소 · manual/auto · owner/admin/허용 subAdmin ·
 *   실제 소속 수 > 20 완결 · 표시(Check)와 URL 발급의 같은 판정.
 *   S296G_EXPECT_OLD=1 이면 이전 원문에서 결함(limit20 절단 · 첫 후보 고정 · 표시 불일치)을 재현한다.
 *   'not-found'(이미지 없음) = 인가 단계를 지났다는 뜻(실제 이미지 열람 0).
 */
const {test} = require('node:test');
const assert = require('assert');
const {createFakeFirestore} = require('./consent_r4d_fakestore');
const {loadIndexClosure} = require('./auth_kakao_index_harness');

const OLD = process.env.S296G_EXPECT_OLD === '1';
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
const url = (uid) => go(X.callableGetIdCardSignedUrl, {targetUserId: 'w1'}, uid);
const check = (uid) => go(X.callableCheckIdCardAccess, {requesterId: uid, targetUserId: 'w1'}, uid);
const batch = (uid) => go(X.callableCheckIdCardAccessBatch, {requesterId: uid, targetUserIds: ['w1']}, uid);
const passedAuth = (o) => !o.ok && o.e.code === 'not-found';

function base(appStatus = 'CONFIRMED') {
  F.reset();
  F.put('businesses/b1', {name: '평택', ownerId: 'own1', adminIds: ['own1', 'adm2']});
  F.put('businesses/b2', {name: '다른', ownerId: 'own9', adminIds: ['own9']});
  F.put('users/own1', {role: 'BUSINESS_ADMIN', name: '사장', businessId: 'b1'});
  F.put('users/adm2', {role: 'BUSINESS_ADMIN', name: '관리자', businessId: 'b1'});
  F.put('users/ex1', {role: 'BUSINESS_ADMIN', name: '전 관리자', businessId: 'b1'});
  F.put('users/sub1', {role: 'USER', name: '부', subAdminBusinessIds: ['b1']});
  F.put('businesses/b1/members/sub1', {uid: 'sub1', permissions: {canManageWage: true}});
  F.put('users/sub2', {role: 'USER', name: '부2', subAdminBusinessIds: ['b1']});
  F.put('businesses/b1/members/sub2', {uid: 'sub2', permissions: {canManageWage: false}});
  F.put('users/w1', {role: 'USER', name: '근로자'});
  F.put('applications/a1', {uid: 'w1', businessId: 'b1', status: appStatus});
}
const grant = (id, o) => F.put(`idCardAccessRequests/${id}`, Object.assign({targetUserId: 'w1', applicationId: 'a1',
  status: 'approved', expiresAt: new Ts(NOW + DAY), respondedAt: new Ts(NOW - 3600000), requestedAt: new Ts(NOW - 7200000)}, o));

test('M1 requesterBusinessId missing/null/빈/타입오류 — business: 접두로 사업장 확정 · owner/admin/허용 subAdmin 만', async () => {
  for (const rb of [undefined, null, '', 123]) {
    base();
    const o = {requesterId: 'business:b1'};
    if (rb !== undefined) o.requesterBusinessId = rb;
    grant('g1', o);
    for (const u of ['own1', 'adm2', 'sub1']) assert.ok(passedAuth(await url(u)), `${String(rb)} ${u} 통과`);
    for (const u of ['ex1', 'sub2']) assert.strictEqual((await url(u)).e.code, 'permission-denied', `${String(rb)} ${u} 거절`);
  }
});

test('M2 다른 사업장 — requesterBusinessId ≠ 접두 · 지원서 사업장 ≠ 열람권 사업장 → 열지 않는다', async () => {
  base(); grant('g1', {requesterId: 'business:b1', requesterBusinessId: 'b2'});
  assert.strictEqual((await url('own1')).e.code, 'permission-denied');
  base(); F.put('applications/a1', {uid: 'w1', businessId: 'b2', status: 'CONFIRMED'});
  grant('g1', {requesterId: 'business:b1'});
  assert.strictEqual(code(await url('own1')), 'GRANT_APPLICATION_INACTIVE');
});

test('M3 취소 지원 — manual(개인) · auto(business) 모두 GRANT_APPLICATION_INACTIVE · 표시 revoked', async () => {
  base('CANCELED');
  grant('g1', {requesterId: 'own1', requesterBusinessId: 'b1'});
  assert.strictEqual(code(await url('own1')), 'GRANT_APPLICATION_INACTIVE');
  base('CANCELED');
  grant('g1', {requesterId: 'business:b1', grantSource: 'auto_confirm'});
  assert.strictEqual(code(await url('own1')), 'GRANT_APPLICATION_INACTIVE');
  const c = await check('own1');
  assert.strictEqual(c.r.request.status, 'revoked');
});

test('M4 소속 사업장 25개 — 25번째 사업장 열람권도 소속으로 판정(limit 20 절단 없음)', async () => {
  base();
  for (let i = 1; i <= 25; i++) F.put(`businesses/x${String(i).padStart(2, '0')}`, {name: `사업장${i}`, ownerId: 'big', adminIds: []});
  F.put('users/big', {role: 'BUSINESS_ADMIN', name: '대표'});
  F.put('applications/a25', {uid: 'w1', businessId: 'x25', status: 'CONFIRMED'});
  grant('g1', {requesterId: 'business:x25', applicationId: 'a25'});
  const o = await url('big');
  if (OLD) { assert.strictEqual(o.e.code, 'permission-denied', '음성 대조: 이전 원문은 21번째 이후 사업장을 소속에서 뺀다'); return; }
  assert.ok(passedAuth(o), o.e && o.e.message);
  assert.strictEqual((await check('big')).r.request.status, 'approved');
});

test('M5 URL — 앞 후보가 자동 열람권(pre_consent)이어도 뒤 유효 수동 열람권으로 발급(첫 후보 고정 없음)', async () => {
  base();
  grant('g1', {requesterId: 'business:b1', grantSource: 'pre_consent_v2'});
  grant('g2', {requesterId: 'business:b1'});
  const o = await url('own1');
  if (OLD) { assert.strictEqual(o.e.code, 'permission-denied', '음성 대조: 이전 원문은 첫 후보가 자동이면 거절'); return; }
  assert.ok(passedAuth(o), o.e && o.e.message);
});

test('M6 표시 = URL — 자동 열람권만 · 수동 7일 상한 초과는 revoked(사유) · URL 도 거절', async () => {
  base();
  grant('g1', {requesterId: 'own1', requesterBusinessId: 'b1', grantSource: 'pre_consent_v2'});
  assert.strictEqual((await url('own1')).e.code, 'permission-denied');
  let c = await check('own1');
  if (OLD) { assert.strictEqual(c.r.request.status, 'approved', '음성 대조: 이전 원문은 URL 이 거절하는 자동 열람권을 approved 로 보인다'); return; }
  assert.strictEqual(c.r.request.status, 'revoked');
  assert.strictEqual(c.r.request.unusableReason, 'LEGACY_AUTO_GRANT');
  base();
  grant('g1', {requesterId: 'own1', requesterBusinessId: 'b1', respondedAt: new Ts(NOW - 8 * DAY)});
  const u = await url('own1');
  assert.strictEqual(u.e.code, 'permission-denied');
  assert.ok(/만료/.test(u.e.message));
  c = await check('own1');
  assert.strictEqual(c.r.request.unusableReason, 'MANUAL_GRANT_EXPIRED');
  const b = await batch('own1');
  assert.strictEqual(b.r.requests.w1.unusableReason, 'MANUAL_GRANT_EXPIRED');
});

test('M7 전 관리자 시절 개인 approved 가 남아도 지금 소속 사업장의 유효 business 열람권을 가리지 않는다(단건·배치)', async () => {
  base();
  // own1 은 예전에 b2 관리자였다 — 개인 열람권(b2)은 승인·미만료지만 지금은 소속 아님
  F.put('applications/a2', {uid: 'w1', businessId: 'b2', status: 'CONFIRMED'});
  grant('gp', {requesterId: 'own1', requesterBusinessId: 'b2', applicationId: 'a2', requestedAt: new Ts(NOW - 60000)});
  grant('gb', {requesterId: 'business:b1'});
  assert.ok(passedAuth(await url('own1')), 'URL 은 b1 열람권으로 발급');
  const c = await check('own1');
  const b = await batch('own1');
  if (OLD) { assert.strictEqual(c.r.request.status, 'revoked', '음성 대조: 이전 원문 표시는 회수로 보인다(URL 은 성공)'); return; }
  assert.strictEqual(c.r.request.status, 'approved');
  assert.strictEqual(c.r.request.id, 'gb');
  assert.strictEqual(b.r.requests.w1.status, 'approved');
  assert.strictEqual(b.r.requests.w1.id, 'gb');
});

test('M8 정상 동치 — 개인 수동 열람권 approved(단건·배치·URL)', async () => {
  base();
  grant('g1', {requesterId: 'own1', requesterBusinessId: 'b1'});
  assert.ok(passedAuth(await url('own1')));
  assert.strictEqual((await check('own1')).r.request.status, 'approved');
  assert.strictEqual((await batch('own1')).r.requests.w1.status, 'approved');
});
