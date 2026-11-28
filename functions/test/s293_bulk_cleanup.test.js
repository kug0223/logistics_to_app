'use strict';
/**
 * [판정293 §10 (1)] CloseSlots fresh 재확인 · 실제 전환 수 카운터 / DeleteTO·DeleteSlots 쓰기 수 기준 끊기 / DeleteSlots 스냅샷 경합.
 *
 *   CS-*  CloseSlots: 조회 스냅샷의 PENDING 이 커밋 전에 확정·취소되면 덮지 않고, 카운터도 실제 전환 수만큼만 줄인다.
 *   DS-*  DeleteSlots: 관계 확인 뒤 늦게 생긴 활성 지원(경합 경로)의 정리 — 커밋당 쓰기 ≤ 450 · 그 사이 상태가 바뀐 지원은
 *         덮지 않음 · 공고 totalPending 감소 = 실제로 거절된 PENDING 수 · 한 지원서 묶음이 예산을 넘으면 쓰기 전 거절.
 *   DT-*  DeleteTO: 같은 늦은 지원 정리의 grant 회수 batch 가 커밋당 ≤ 450.
 *   S293_EXPECT_OLD=1 이면 이전 원문(be3108c0)에서 결함(덮어쓰기 · 카운터 과다 감소 · 500 초과 커밋)을 재현한다(음성 대조).
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
const {exports: X} = loadIndexClosure(['callableCloseSlots', 'callableDeleteSlots', 'callableDeleteTO'], F,
  {HttpsError, console: QCON, Date: FakeDate});
const call = (fn, data, uid) => fn({data, auth: {uid, token: {}}});
const Ts = F.Ts;
const DAY = 86400000;
const OLD = process.env.S293_EXPECT_OLD === '1';

function base() {
  F.reset();
  F.put('users/own1', {role: 'BUSINESS_ADMIN', accountStatus: 'active', name: '사장'});
  F.put('businesses/b1', {name: '평택', ownerId: 'own1', adminIds: ['own1'], isApproved: true});
  F.put('tos/t1', {businessId: 'b1', title: '물류', status: 'ACTIVE', totalPending: 0, totalConfirmed: 0, isPublished: true});
}
function slot(id, o = {}) {
  F.put(`tos/t1/slots/${id}`, Object.assign({status: 'open', date: new Ts(NOW + 3 * DAY), pendingCount: 0, confirmedCount: 0,
    workDetails: [{wdId: 'wd1', workType: '포장', startTime: '09:00', endTime: '18:00', requiredCount: 5}],
    workDetailCounts: {wd1: {pendingCount: 0, confirmedCount: 0}}}, o));
}
function app(id, status, slotId, o = {}) {
  F.put(`applications/${id}`, Object.assign({uid: `u_${id}`, businessId: 'b1', businessName: '평택', toId: 't1', slotId, wdId: 'wd1',
    status, selectedWorkType: '포장', workDate: new Ts(NOW + 3 * DAY)}, o));
}
const maxCommitWrites = () => Math.max(0, ...F.W.commits.map((c) => c.writes.length));
async function run(p) { try { return {ok: true, r: await p}; } catch (e) { return {ok: false, code: e.code, details: e.details, message: e.message}; } }
// 첫 거래 읽기 직전에 한 번 바꾼다(조회 스냅샷 뒤 · 커밋 전 경합)
function onFirstTxRead(fn) {
  F.hooks.afterGet = (p, txId) => { if (txId != null) { F.hooks.afterGet = null; fn(); } };
}
// 그 컬렉션의 첫 질의 결과가 돌아온 직후 한 번 바꾼다(조회 스냅샷 뒤 · 커밋 전 경합)
function afterFirstQuery(col, fn) {
  const orig = F.db.collection;
  let fired = false;
  F.db.collection = (c) => {
    const real = orig(c);
    if (c !== col || fired) return real;
    const wrap = (q) => new Proxy(q, {get: (t, k) => {
      if (k === 'get') return async () => { const r = await t.get(); if (!fired) { fired = true; fn(); } return r; };
      if (k === 'where' || k === 'limit' || k === 'orderBy') return (...a) => wrap(t[k](...a));
      return typeof t[k] === 'function' ? t[k].bind(t) : t[k];
    }});
    return wrap(real);
  };
  return () => { F.db.collection = orig; };
}
// 관계 확인(계약 질의) 직후 늦은 지원을 넣는다(관계 확인 뒤 · 정리 조회 전 경합 경로)
function lateAppsAfterRelationCheck(seedLate) {
  const orig = F.db.collection;
  let fired = false;
  F.db.collection = (c) => {
    const real = orig(c);
    if (c !== 'employment_contracts' || fired) return real;
    const wrap = (q) => new Proxy(q, {get: (t, k) => {
      if (k === 'get') return async () => { const r = await t.get(); if (!fired) { fired = true; seedLate(); } return r; };
      if (k === 'where' || k === 'limit' || k === 'orderBy') return (...a) => wrap(t[k](...a));
      return typeof t[k] === 'function' ? t[k].bind(t) : t[k];
    }});
    return wrap(real);
  };
  return () => { F.db.collection = orig; };
}

test('CS1 정상 — PENDING 3 거절 · 슬롯/업무/공고 대기 -3', async () => {
  base(); slot('s1', {pendingCount: 3, workDetailCounts: {wd1: {pendingCount: 3, confirmedCount: 0}}});
  F.put('tos/t1', Object.assign(F.get('tos/t1'), {totalPending: 3}));
  for (const i of [1, 2, 3]) app(`a${i}`, 'PENDING', 's1');
  const o = await run(call(X.callableCloseSlots, {toId: 't1', slotIds: ['s1'], businessId: 'b1'}, 'own1'));
  assert.ok(o.ok, o.message);
  assert.strictEqual(o.r.canceledCount, 3);
  assert.deepStrictEqual([1, 2, 3].map((i) => F.get(`applications/a${i}`).status), ['REJECTED', 'REJECTED', 'REJECTED']);
  assert.strictEqual(F.get('tos/t1/slots/s1').pendingCount, 0);
  assert.strictEqual(F.get('tos/t1/slots/s1').workDetailCounts.wd1.pendingCount, 0);
  assert.strictEqual(F.get('tos/t1').totalPending, 0);
});

test('CS2 경합 — 조회 뒤 확정된 지원은 덮지 않고 대기 감소는 실제 거절 수', async () => {
  base(); slot('s1', {pendingCount: 3, workDetailCounts: {wd1: {pendingCount: 3, confirmedCount: 0}}});
  F.put('tos/t1', Object.assign(F.get('tos/t1'), {totalPending: 3}));
  for (const i of [1, 2, 3]) app(`a${i}`, 'PENDING', 's1');
  // PENDING 조회 직후 확정 경로가 a2 를 CONFIRMED 로 바꾸며 대기 1 을 이미 뺐다(그 경로의 카운터)
  const restoreQ = afterFirstQuery('applications', () => {
    F.put('applications/a2', Object.assign(F.get('applications/a2'), {status: 'CONFIRMED'}));
    const s = F.get('tos/t1/slots/s1'); s.pendingCount = 2; s.workDetailCounts.wd1.pendingCount = 2; s.confirmedCount = 1; F.put('tos/t1/slots/s1', s);
    F.put('tos/t1', Object.assign(F.get('tos/t1'), {totalPending: 2, totalConfirmed: 1}));
  });
  const o = await run(call(X.callableCloseSlots, {toId: 't1', slotIds: ['s1'], businessId: 'b1'}, 'own1'));
  restoreQ();
  assert.ok(o.ok, o.message);
  if (OLD) {
    assert.strictEqual(F.get('applications/a2').status, 'REJECTED', '음성 대조: 예전 원문은 확정된 지원을 거절로 덮는다');
    assert.strictEqual(F.get('tos/t1/slots/s1').pendingCount, -1, '음성 대조: 예전 원문은 대기를 3 빼 -1');
    return;
  }
  assert.strictEqual(F.get('applications/a2').status, 'CONFIRMED');
  assert.strictEqual(o.r.canceledCount, 2);
  assert.strictEqual(F.get('tos/t1/slots/s1').pendingCount, 0);
  assert.strictEqual(F.get('tos/t1/slots/s1').workDetailCounts.wd1.pendingCount, 0);
  assert.strictEqual(F.get('tos/t1').totalPending, 0);
});

test('CS3 예산 — 한 슬롯 PENDING 500 → 커밋당 쓰기 ≤ 450 · 전부 거절 · 대기 -500', async () => {
  base(); slot('s1', {pendingCount: 500, workDetailCounts: {wd1: {pendingCount: 500, confirmedCount: 0}}});
  F.put('tos/t1', Object.assign(F.get('tos/t1'), {totalPending: 500}));
  for (let i = 0; i < 500; i++) app(`p${i}`, 'PENDING', 's1');
  const o = await run(call(X.callableCloseSlots, {toId: 't1', slotIds: ['s1'], businessId: 'b1'}, 'own1'));
  assert.ok(o.ok, o.message);
  assert.strictEqual(o.r.canceledCount, 500);
  assert.ok(maxCommitWrites() <= 450, `커밋 쓰기 ${maxCommitWrites()}`);
  assert.strictEqual(F.get('tos/t1/slots/s1').pendingCount, 0);
  assert.strictEqual(F.get('tos/t1').totalPending, 0);
});

function lateConfirmedWithGrants(n, personal, slotId) {
  for (let i = 0; i < n; i++) {
    app(`c${i}`, 'CONFIRMED', slotId);
    F.put(`idCardAccessRequests/auto_c${i}`, {applicationId: `c${i}`, targetUserId: `u_c${i}`, status: 'approved'});
    for (let k = 0; k < personal; k++) {
      F.put(`idCardAccessRequests/p_c${i}_${k}`, {applicationId: `c${i}`, targetUserId: `u_c${i}`, status: 'approved'});
    }
  }
}

test('DS1 예산 — 늦은 확정 160(각 auto + 개인 2) → 커밋당 ≤ 450 · grant 전부 회수', async () => {
  base(); slot('s1');
  const restore = lateAppsAfterRelationCheck(() => lateConfirmedWithGrants(160, 2, 's1'));
  const o = await run(call(X.callableDeleteSlots, {toId: 't1', slotIds: ['s1'], businessId: 'b1'}, 'own1'));
  restore();
  if (OLD) {
    assert.ok(maxCommitWrites() > 500, `음성 대조: 예전 원문은 한 batch 가 500 을 넘는다(${maxCommitWrites()})`);
    return;
  }
  assert.ok(o.ok, o.message);
  assert.ok(maxCommitWrites() <= 450, `커밋 쓰기 ${maxCommitWrites()}`);
  const revoked = [...F.STORE.keys()].filter((k) => k.startsWith('idCardAccessRequests/') && F.get(k).status === 'revoked').length;
  assert.strictEqual(revoked, 160 * 3);
  assert.strictEqual([...F.STORE.keys()].filter((k) => /^applications\/c\d+$/.test(k) && F.get(k).status === 'REJECTED').length, 160);
});

test('DS2 경합 — 늦은 PENDING 중 하나가 커밋 전에 취소되면 덮지 않고 공고 대기 감소는 실제 거절 수', async () => {
  base(); slot('s1');
  F.put('tos/t1', Object.assign(F.get('tos/t1'), {totalPending: 3}));
  const restore = lateAppsAfterRelationCheck(() => { for (const i of [1, 2, 3]) app(`q${i}`, 'PENDING', 's1'); });
  onFirstTxRead(() => {
    F.put('applications/q2', Object.assign(F.get('applications/q2'), {status: 'CANCELED'}));
    F.put('tos/t1', Object.assign(F.get('tos/t1'), {totalPending: 2})); // 취소 경로가 이미 1 뺐다
  });
  const o = await run(call(X.callableDeleteSlots, {toId: 't1', slotIds: ['s1'], businessId: 'b1'}, 'own1'));
  restore(); F.hooks.afterGet = null;
  assert.ok(o.ok, o.message);
  if (OLD) {
    assert.strictEqual(F.get('applications/q2').status, 'REJECTED', '음성 대조: 예전 원문은 취소된 지원을 거절로 덮는다');
    assert.strictEqual(F.get('tos/t1').totalPending, -1, '음성 대조: 예전 원문은 공고 대기를 3 빼 -1');
    return;
  }
  assert.strictEqual(F.get('applications/q2').status, 'CANCELED');
  assert.strictEqual(F.get('applications/q1').status, 'REJECTED');
  assert.strictEqual(F.get('tos/t1').totalPending, 0);
});

test('DS3 한 지원서 묶음이 예산 초과 — 쓰기 전 거절(WRITE_GROUP_TOO_LARGE) · 쪼개지 않음', async () => {
  base(); slot('s1');
  const restore = lateAppsAfterRelationCheck(() => lateConfirmedWithGrants(1, 460, 's1'));
  const o = await run(call(X.callableDeleteSlots, {toId: 't1', slotIds: ['s1'], businessId: 'b1'}, 'own1'));
  restore();
  if (OLD) return; // 예전 원문은 한 batch 로 462 쓰기(가짜 저장소 한도 미검사)
  assert.strictEqual(o.ok, false);
  assert.strictEqual(o.details && o.details.code, 'WRITE_GROUP_TOO_LARGE');
  assert.strictEqual(F.get('applications/c0').status, 'CONFIRMED');
  assert.strictEqual([...F.STORE.keys()].filter((k) => k.startsWith('idCardAccessRequests/') && F.get(k).status === 'revoked').length, 0);
});

test('DT1 예산 — 공고 삭제 중 늦은 확정 160(각 auto + 개인 3) → grant 회수 커밋당 ≤ 450', async () => {
  base(); slot('s1');
  const restore = lateAppsAfterRelationCheck(() => lateConfirmedWithGrants(160, 3, 's1'));
  const o = await run(call(X.callableDeleteTO, {toId: 't1'}, 'own1'));
  restore();
  if (OLD) {
    assert.ok(maxCommitWrites() > 450, `음성 대조: 예전 원문 페이지 batch 쓰기 ${maxCommitWrites()}`);
    return;
  }
  assert.ok(maxCommitWrites() <= 450, `커밋 쓰기 ${maxCommitWrites()}`);
  const revoked = [...F.STORE.keys()].filter((k) => k.startsWith('idCardAccessRequests/') && F.get(k).status === 'revoked').length;
  assert.strictEqual(revoked, 160 * 4);
  void o;
});
