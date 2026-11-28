'use strict';
/**
 * [L57 r6] 해지 요청·취소·거절 — 계약 terminationStatus 동기화가 지원서 전이와 같은 거래인가.
 *
 *   T1–T3 각 writer 의 정상 경로: 지원서·계약 쓰기가 **한 커밋**에 있다(커밋 뒤 별도 쓰기 0).
 *   T4 경합: 요청 거래 커밋 직후(예전 코드의 '커밋 뒤 계약 batch' 직전)에 거절이 끝까지 실행된다.
 *       예전: 거절의 복원 쿼리는 아직 PENDING 이 아닌 계약을 못 찾고, 뒤늦은 요청 batch 가 계약을 PENDING 으로 만든다
 *             → 지원서 REJECTED · 계약 PENDING (영구 불일치).
 *       지금: 그 틈이 없다 → 지원서 REJECTED · 계약 null.
 *   T5 계약 쓰기 실패: 거절 거래가 통째로 실패한다(지원서 PENDING 그대로 · 부분 커밋 0).
 *   T6 계약이 applicationIds 로만 연결된 경우(두 번째 쿼리)도 같은 거래에서 고친다.
 *   L57_EXPECT_OLD=1 이면 예전 원문 사본에서 T4 불일치가 재현되는지(음성 대조) 본다.
 */
const {test} = require('node:test');
const assert = require('assert');
const {createFakeFirestore} = require('./consent_r4d_fakestore');
const {loadIndexClosure} = require('./auth_kakao_index_harness');

const RealDate = Date;
const NOW = RealDate.UTC(2026, 10, 26, 3, 0);
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
const {exports: X} = loadIndexClosure(
  ['callableRequestTermination', 'callableCancelTermination', 'callableRejectTermination'], F,
  {HttpsError, console: QCON, Date: FakeDate});
const call = (fn, data, uid) => fn({data, auth: {uid, token: {}}});
const OLD = process.env.L57_EXPECT_OLD === '1';

function seed({byIds = false, appTerm = null} = {}) {
  F.reset();
  F.put('users/own1', {role: 'BUSINESS_ADMIN', accountStatus: 'active', name: '사장'});
  F.put('users/w1', {role: 'USER', accountStatus: 'active', name: '근로자'});
  F.put('businesses/b1', {name: '평택', ownerId: 'own1', adminIds: ['own1']});
  F.put('applications/a1', Object.assign({uid: 'w1', businessId: 'b1', businessName: '평택', status: 'CONFIRMED',
    type: 'long_term', workEndDate: new F.Ts(NOW + 20 * 86400000)}, appTerm ? {
    terminationStatus: appTerm, terminationRequestedByUid: 'own1', terminationRequestedAt: new F.Ts(NOW - 3600000)} : {}));
  F.put('employment_contracts/c1', Object.assign({businessId: 'b1', status: 'active'},
    byIds ? {applicationIds: ['a1', 'a9']} : {applicationId: 'a1'},
    appTerm === 'PENDING' ? {terminationStatus: 'PENDING'} : {}));
}
const appTerm = () => F.get('applications/a1').terminationStatus ?? null;
const conTerm = () => F.get('employment_contracts/c1').terminationStatus ?? null;
/** 지원서 쓰기가 들어간 커밋에 계약 쓰기도 있는가 · 그 밖의 계약 쓰기(직접·batch)는 없는가 */
function sameCommit() {
  const c = F.W.commits.find((x) => x.writes.some((w) => w.path === 'applications/a1'));
  return !!c && c.writes.some((w) => w.path === 'employment_contracts/c1');
}

test('T1 해지 요청 — 지원서 PENDING 과 계약 PENDING 이 한 커밋', async () => {
  seed();
  await call(X.callableRequestTermination, {applicationId: 'a1', reason: '사유'}, 'own1');
  assert.strictEqual(appTerm(), 'PENDING');
  assert.strictEqual(conTerm(), 'PENDING');
  if (!OLD) assert.ok(sameCommit(), '계약 쓰기가 요청 거래 밖에 있다');
});

test('T2 해지 거절 — 지원서 REJECTED 와 계약 복원(null)이 한 커밋', async () => {
  seed({appTerm: 'PENDING'});
  await call(X.callableRejectTermination, {applicationId: 'a1', rejectReason: '안 됨'}, 'own1');
  assert.strictEqual(appTerm(), 'REJECTED');
  assert.strictEqual(conTerm(), null);
  if (!OLD) assert.ok(sameCommit(), '계약 복원이 거절 거래 밖에 있다');
});

test('T3 해지 취소 — 지원서 null 과 계약 복원(null)이 한 커밋', async () => {
  seed({appTerm: 'PENDING'});
  await call(X.callableCancelTermination, {applicationId: 'a1'}, 'own1');
  assert.strictEqual(appTerm(), null);
  assert.strictEqual(conTerm(), null);
  if (!OLD) assert.ok(sameCommit(), '계약 복원이 취소 거래 밖에 있다');
});

test('T4 경합 — 요청 커밋 직후 거절이 끝나도 지원서·계약이 어긋나지 않는다', async () => {
  seed();
  const orig = F.db.collection;
  let fired = false;
  const requestCommitted = () => F.W.commits.some((c) => c.writes.some((w) =>
    w.path === 'applications/a1' && w.data && w.data.terminationStatus === 'PENDING'));
  const rejectNow = async () => {
    F.db.collection = orig;
    await call(X.callableRejectTermination, {applicationId: 'a1', rejectReason: '경합'}, 'own1');
  };
  // 요청 거래가 커밋된 **뒤** 처음 만들어지는 계약 쿼리(= 예전 코드의 커밋 뒤 batch 조회) 직전에 거절을 끝까지 돌린다.
  F.db.collection = (c) => {
    const real = orig(c);
    if (c !== 'employment_contracts' || fired || !requestCommitted()) return real;
    fired = true;
    const wrap = (q) => ({where: (...a) => wrap(q.where(...a)), limit: (n) => wrap(q.limit(n)),
      get: async () => { await rejectNow(); return q.get(); }});
    return wrap(real);
  };
  try {
    await call(X.callableRequestTermination, {applicationId: 'a1', reason: '사유'}, 'own1');
    if (!fired) await rejectNow(); // 지금 코드: 커밋 뒤 틈이 없으므로 요청이 끝난 뒤 거절한다
  } finally {
    F.db.collection = orig;
  }
  assert.strictEqual(appTerm(), 'REJECTED');
  if (OLD) {
    assert.ok(fired, '예전 코드의 커밋 뒤 계약 조회 틈을 재현하지 못했다');
    assert.strictEqual(conTerm(), 'PENDING', '음성 대조: 예전 코드는 계약 PENDING 이 남아야 한다');
  } else {
    assert.strictEqual(fired, false, '요청 커밋 뒤 계약 조회가 아직 있다');
    assert.strictEqual(conTerm(), null, '지원서 REJECTED 인데 계약이 PENDING 으로 남았다');
  }
});

test('T5 계약 쓰기 실패 — 거절이 통째로 실패하고 지원서는 PENDING 그대로', async () => {
  seed({appTerm: 'PENDING'});
  F.hooks.beforeCommit = (txId, buf) => {
    if (buf.some((w) => w.path === 'employment_contracts/c1')) throw new Error('ABORTED: contract write failed');
  };
  // 예전 코드: 계약은 커밋 뒤 batch — 거래 훅으로는 계약 실패를 만들 수 없다(지원서만 REJECTED).
  let err = null;
  try { await call(X.callableRejectTermination, {applicationId: 'a1'}, 'own1'); } catch (e) { err = e; }
  F.hooks.beforeCommit = null;
  if (OLD) {
    assert.strictEqual(err, null);
    assert.strictEqual(appTerm(), 'REJECTED');
    return;
  }
  assert.ok(err && /contract write failed/.test(String(err.message)));
  assert.strictEqual(appTerm(), 'PENDING');
  assert.strictEqual(conTerm(), 'PENDING');
});

test('T6 applicationIds 로만 연결된 계약도 같은 거래에서 고친다(두 번째 쿼리)', async () => {
  seed({byIds: true});
  await call(X.callableRequestTermination, {applicationId: 'a1', reason: '사유'}, 'own1');
  assert.strictEqual(conTerm(), 'PENDING');
  if (!OLD) assert.ok(sameCommit());
  await call(X.callableRejectTermination, {applicationId: 'a1'}, 'own1');
  assert.strictEqual(appTerm(), 'REJECTED');
  assert.strictEqual(conTerm(), null);
  if (!OLD) assert.ok(sameCommit());
});

test('T7 끝난 계약(completed)은 요청이 건드리지 않는다(예전 필터 그대로)', async () => {
  seed();
  F.put('employment_contracts/c1', Object.assign(F.get('employment_contracts/c1'), {status: 'completed'}));
  await call(X.callableRequestTermination, {applicationId: 'a1', reason: '사유'}, 'own1');
  assert.strictEqual(appTerm(), 'PENDING');
  assert.strictEqual(conTerm(), null);
});
