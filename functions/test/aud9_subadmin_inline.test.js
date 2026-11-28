'use strict';
/**
 * [server_299 §8 · AUD-9 T1 같은 꼴] 인라인 하위 관리자 판정 — users 배정 필드만이 아니라 **현재 멤버 행**이 있어야 한다(공용 srvIsCurrentSubAdminOf).
 *   AUD9S_EXPECT_OLD=1 이면 이전 원문(58f581b8)의 결함(배정 필드 단독 신뢰)을 재현하는 쪽으로 기대를 뒤집는다.
 *   S1 GetUserByPhone · S2 LogResidentNumberCopy · S3 CleanupApplicationData · S4 ReportLate —
 *      배정만 있고 멤버 행 없음(stale): 수리 = 권한 거절 / 예전 = 통과. 멤버 행 있음(live)·소유자: 통과(양쪽 같음).
 *   S5 옛 subAdminOf 단수 필드 — 멤버 행 있으면 통과, 없으면 거절(수리).
 *   S6 DecrementSlotConfirmed — 이미 본문 진입 전 차단(DECREMENT-DEAD-BLOCK) · stale 도 failed-precondition(양쪽 같음 · 수정 0).
 *   S7 이상 입력 — 배정 배열에 문자열 아닌 값·'/' 포함 값이 섞여도 판정이 깨지지 않는다.
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
const {exports: X} = loadIndexClosure(['callableGetUserByPhone', 'callableLogResidentNumberCopy', 'callableCleanupApplicationData',
  'callableReportLate', 'callableDecrementSlotConfirmed'], F, {HttpsError, console: QCON, Date: FakeDate});
const OLD = process.env.AUD9S_EXPECT_OLD === '1';

function base() {
  F.reset();
  F.put('businesses/b1', {name: 'b', ownerId: 'own', adminIds: ['own']});
  F.put('users/own', {role: 'BUSINESS_ADMIN', accountStatus: 'active'});
  F.put('users/stale', {role: 'USER', accountStatus: 'active', subAdminBusinessIds: ['b1']});
  F.put('users/live', {role: 'USER', accountStatus: 'active', subAdminBusinessIds: ['b1']});
  F.put('businesses/b1/members/live', {uid: 'live', permissions: {}});
  F.put('users/w1', {role: 'USER', accountStatus: 'active', name: '근로자', phone: '01012345678'});
}
// 권한 단계에서 그 메시지로 거절됐는가(그 뒤 단계의 다른 오류·성공은 '권한 통과')
async function deniedWith(fn, data, uid, msg) {
  try { await fn({data, auth: {uid, token: {}}}); return false; } catch (e) {
    return e.code === 'permission-denied' && String(e.message).includes(msg);
  }
}
const expectStale = (denied, label) => assert.strictEqual(denied, !OLD, OLD ? `재현: ${label} 배정만으로 통과` : `${label} 멤버 행 없으면 거절`);

test('S1 GetUserByPhone', async () => {
  base();
  const M = '멤버 검색 권한이 없습니다';
  expectStale(await deniedWith(X.callableGetUserByPhone, {phone: '010-1234-5678'}, 'stale', M), 'GetUserByPhone');
  assert.strictEqual(await deniedWith(X.callableGetUserByPhone, {phone: '010-1234-5678'}, 'live', M), false);
  assert.strictEqual(await deniedWith(X.callableGetUserByPhone, {phone: '010-1234-5678'}, 'own', M), false);
  F.put('users/plain', {role: 'USER', accountStatus: 'active'});
  assert.strictEqual(await deniedWith(X.callableGetUserByPhone, {phone: '010-1234-5678'}, 'plain', M), true);
});

test('S2 LogResidentNumberCopy', async () => {
  base();
  const M = '해당 사업장 관리자만 열람 기록을 남길 수 있습니다';
  const logs = () => [...F.STORE.keys()].filter((k) => k.startsWith('id_card_copy_logs/')).length;
  expectStale(await deniedWith(X.callableLogResidentNumberCopy, {targetUserId: 'w1', businessId: 'b1'}, 'stale', M), 'LogResidentNumberCopy');
  assert.strictEqual(logs(), OLD ? 1 : 0, '거절이면 기록 0');
  assert.strictEqual(await deniedWith(X.callableLogResidentNumberCopy, {targetUserId: 'w1', businessId: 'b1'}, 'live', M), false);
  assert.strictEqual(await deniedWith(X.callableLogResidentNumberCopy, {targetUserId: 'w1', businessId: 'b1'}, 'own', M), false);
});

test('S3 CleanupApplicationData', async () => {
  base();
  F.put('applications/aC', {uid: 'w1', businessId: 'b1', toId: 't1', slotId: 's1', status: 'CANCELED'});
  const M = '권한이 없습니다';
  expectStale(await deniedWith(X.callableCleanupApplicationData, {applicationId: 'aC'}, 'stale', M), 'CleanupApplicationData');
  assert.strictEqual(await deniedWith(X.callableCleanupApplicationData, {applicationId: 'aC'}, 'live', M), false);
  assert.strictEqual(await deniedWith(X.callableCleanupApplicationData, {applicationId: 'aC'}, 'own', M), false);
});

test('S4 ReportLate', async () => {
  base();
  const M = '해당 사업장 관리 권한이 필요합니다';
  const d = {userId: 'w1', businessId: 'b1', mode: 'late', attendanceId: 'att1'};
  expectStale(await deniedWith(X.callableReportLate, d, 'stale', M), 'ReportLate');
  assert.strictEqual(await deniedWith(X.callableReportLate, d, 'live', M), false);
  assert.strictEqual(await deniedWith(X.callableReportLate, d, 'own', M), false);
});

test('S5 옛 subAdminOf 단수 필드 — 멤버 행이 기준', async () => {
  base();
  F.put('users/legacyLive', {role: 'USER', accountStatus: 'active', subAdminOf: 'b1'});
  F.put('businesses/b1/members/legacyLive', {uid: 'legacyLive', permissions: {}});
  F.put('users/legacyStale', {role: 'USER', accountStatus: 'active', subAdminOf: 'b1'});
  const M = '해당 사업장 관리자만 열람 기록을 남길 수 있습니다';
  assert.strictEqual(await deniedWith(X.callableLogResidentNumberCopy, {targetUserId: 'w1', businessId: 'b1'}, 'legacyLive', M), false);
  expectStale(await deniedWith(X.callableLogResidentNumberCopy, {targetUserId: 'w1', businessId: 'b1'}, 'legacyStale', M), 'subAdminOf');
});

test('S6 DecrementSlotConfirmed — 본문 진입 전 차단(양쪽 같음)', async () => {
  base();
  F.put('applications/aC', {uid: 'w1', businessId: 'b1', toId: 't1', slotId: 's1', status: 'CANCELED'});
  for (const u of ['stale', 'live', 'own']) {
    await assert.rejects(X.callableDecrementSlotConfirmed({data: {applicationId: 'aC', toId: 't1', slotId: 's1', workType: null},
      auth: {uid: u, token: {}}}), (e) => e.code === 'failed-precondition');
  }
});

test('S7 이상 입력 — 배정 배열에 숫자·null·경로 문자 섞임', async () => {
  base();
  F.put('users/odd', {role: 'USER', accountStatus: 'active', subAdminBusinessIds: [7, null, 'x/y', 'b1']});
  F.put('businesses/b1/members/odd', {uid: 'odd', permissions: {}});
  F.put('users/oddStale', {role: 'USER', accountStatus: 'active', subAdminBusinessIds: [7, null, 'x/y']});
  const M = '멤버 검색 권한이 없습니다';
  assert.strictEqual(await deniedWith(X.callableGetUserByPhone, {phone: '01012345678'}, 'odd', M), false);
  const r = await deniedWith(X.callableGetUserByPhone, {phone: '01012345678'}, 'oddStale', M);
  if (!OLD) assert.strictEqual(r, true, '유효 배정 0 → 거절');
});
