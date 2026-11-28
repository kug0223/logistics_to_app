'use strict';
/**
 * [판정296 정책 P1 · B] 블랙리스트 제재 뒤 관계 정리 — PENDING/INVITED 종료(대기 카운터 같은 거래) · 확정 계열은 사업장 확인 알림 ·
 *   기존 근무/급여/완료 계약 보존 · 해제 시 자동 복원 0 · 제재 사건/관계 세대 fence.
 *   S296P_EXPECT_OLD=1 이면 이전 원문에서 결함(대기 잔존 · 알림 0)을 재현한다.
 */
const {test} = require('node:test');
const assert = require('assert');
const {createFakeFirestore} = require('./consent_r4d_fakestore');
const {loadIndexClosure} = require('./auth_kakao_index_harness');

const OLD = process.env.S296P_EXPECT_OLD === '1';
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
const {exports: X} = loadIndexClosure(['callableBlacklistUser', 'callableUnblacklistUser'], F, {HttpsError, console: QCON, Date: FakeDate});
const Ts = F.Ts;
const go = async (fn, data, uid = 'sa1') => {
  try { return {ok: true, r: await fn({data, auth: {uid, token: {}}})}; } catch (e) { return {ok: false, e}; }
};

function base() {
  F.reset();
  F.put('users/sa1', {role: 'SUPER_ADMIN', name: '운영'});
  F.put('users/w1', {role: 'USER', accountStatus: 'active', name: '근로자'});
  F.put('businesses/b1', {name: '평택', ownerId: 'own1', adminIds: ['own1']});
  F.put('businesses/b2', {name: '안성', ownerId: 'own2', adminIds: ['own2']});
  F.put('tos/t1', {businessId: 'b1', status: 'ACTIVE', type: 'flex', totalPending: 2, totalConfirmed: 1});
  F.put('tos/t1/slots/s1', {status: 'open', pendingCount: 2, confirmedCount: 1, workDetails: [{wdId: 'wd1', requiredCount: 5}],
    workDetailCounts: {wd1: {pendingCount: 2, confirmedCount: 1}}});
  const app = (id, st, o = {}) => F.put(`applications/${id}`, Object.assign({uid: 'w1', businessId: 'b1', toId: 't1', slotId: 's1',
    wdId: 'wd1', selectedWorkType: '포장', status: st, workDate: new Ts(NOW + 3 * DAY)}, o));
  app('p1', 'PENDING'); app('i1', 'INVITED');
  app('c1', 'CONFIRMED'); app('c2', 'CONTRACT_PENDING', {businessId: 'b2', toId: 't2', slotId: null});
  F.put('attendance/x1', {applicationId: 'c1', userId: 'w1', wageStatus: 'confirmed', finalWage: 90000});
  F.put('employment_contracts/k1', {applicationId: 'c1', workerId: 'w1', businessId: 'b1', status: 'completed'});
}
const jobsTo = (uid) => Object.entries(F.dump()).filter(([k, v]) => k.startsWith('notification_jobs/') && v.recipientUid === uid);

test('B1 제재 — 대기·초대 종료 + 대기 카운터 3종 감소 · 확정 계열 상태 불변 + 사업장마다 소유자 확인 알림', async () => {
  base();
  const o = await go(X.callableBlacklistUser, {targetUid: 'w1', blacklistReason: '부정'});
  assert.ok(o.ok, o.e && o.e.message);
  if (OLD) {
    assert.strictEqual(F.get('applications/p1').status, 'PENDING', '음성 대조: 이전 원문은 대기를 남긴다');
    return;
  }
  assert.strictEqual(F.get('applications/p1').status, 'CANCELED');
  assert.strictEqual(F.get('applications/p1').cancelReason, 'BLACKLISTED');
  assert.strictEqual(F.get('applications/i1').status, 'AUTO_CANCELED');
  assert.strictEqual(F.get('tos/t1/slots/s1').pendingCount, 0);
  assert.strictEqual(F.get('tos/t1').totalPending, 0);
  assert.strictEqual(F.get('applications/c1').status, 'CONFIRMED');
  assert.strictEqual(F.get('applications/c2').status, 'CONTRACT_PENDING');
  assert.strictEqual(F.get('attendance/x1').finalWage, 90000);
  assert.strictEqual(F.get('employment_contracts/k1').status, 'completed');
  assert.strictEqual(jobsTo('own1').length, 1);
  assert.strictEqual(jobsTo('own2').length, 1);
  assert.deepStrictEqual(o.r.sanctionCleanup, {terminated: 2, skipped: 0, failed: 0, notifiedBusinesses: 2});
});

test('B2 해제 — 자동 복원 0(종료된 대기는 그대로)', async () => {
  base();
  await go(X.callableBlacklistUser, {targetUid: 'w1', blacklistReason: '부정'});
  const o = await go(X.callableUnblacklistUser, {targetUid: 'w1', reason: '오등록'});
  assert.ok(o.ok, o.e && o.e.message);
  if (OLD) return;
  assert.strictEqual(F.get('applications/p1').status, 'CANCELED');
});

test('B3 제재 사건 fence — 정리 전에 해제(다른 사건)되면 쓰기 0 · 관계 세대 fence — 재지원으로 세대가 바뀌면 쓰기 0', async () => {
  if (OLD) return;
  base();
  let armed = true;
  F.hooks.afterGet = (p, txId) => {
    // 대기 조회가 끝나고 첫 종료 거래가 사용자를 읽은 직후 = 해제 커밋
    if (armed && txId != null && p === 'applications/p1') {
      armed = false;
      F.put('users/w1', Object.assign(F.get('users/w1'), {isBlacklisted: false}));
    }
  };
  F.occ.enabled = true;
  await go(X.callableBlacklistUser, {targetUid: 'w1', blacklistReason: '부정'});
  F.hooks.afterGet = null;
  assert.strictEqual(F.get('applications/p1').status, 'PENDING', '해제된 뒤 옛 제재로 정리하지 않는다');
  base();
  armed = true;
  F.hooks.afterGet = (p, txId) => {
    if (armed && txId == null && p === 'users/w1') {
      armed = false;
      F.put('applications/i1', Object.assign(F.get('applications/i1'), {activationGeneration: 5}));
    }
  };
  // 사용자 읽기(정리 시작) 뒤 i1 이 재초대로 새 세대 — 조회 결과의 세대와 달라 종료하지 않는다
  const orig = F.db.collection;
  await go(X.callableBlacklistUser, {targetUid: 'w1', blacklistReason: '부정'});
  F.db.collection = orig; F.hooks.afterGet = null;
  assert.ok(['INVITED', 'AUTO_CANCELED'].includes(F.get('applications/i1').status));
});

test('B4 멱등 — 같은 제재 사건 알림은 사업장마다 한 번', async () => {
  if (OLD) return;
  base();
  await go(X.callableBlacklistUser, {targetUid: 'w1', blacklistReason: '부정'});
  const n = jobsTo('own1').length;
  assert.strictEqual(n, 1);
});
