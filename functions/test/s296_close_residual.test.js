'use strict';
/**
 * [판정296 §2-1 CLOSE-01 잔여] root_close_review C296-CLOSE-R1/R2/R3.
 *   R1 공고 상태 재계산 — 조회와 쓰기 사이 재오픈이면 옛 스냅샷으로 CLOSED 를 덮지 않는다(같은 거래 · OCC 모형).
 *   R2 legacy(표식 없는) cleanupOnly — 멈춘 옛 요청이 재오픈→새 닫기 뒤 새 사건 대기를 거절하지 않는다 ·
 *      중간 실패면 표식이 남아 매시가 끝낸다 · 표식이 남지 않으면 resumable:false.
 *   R3 매시 순회 — 앞 100 표식이 계속 실패해도 101번째가 다음 매시에 차례를 얻는다.
 *   S296_EXPECT_OLD=1 이면 이전 원문(58175022)에서 결함을 재현한다(음성 대조).
 */
const {test} = require('node:test');
const assert = require('assert');
const {createFakeFirestore} = require('./consent_r4d_fakestore');
const {loadIndexClosure} = require('./auth_kakao_index_harness');

const OLD = process.env.S296_EXPECT_OLD === '1';
const RealDate = Date;
let NOW = RealDate.UTC(2026, 10, 27, 3, 0);
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
const {exports: X} = loadIndexClosure(['callableCloseSlots', 'callableReopenSlots', 'processCloseSlotCleanupMarkers'],
  F, {HttpsError, console: QCON, Date: FakeDate});
const Ts = F.Ts;
const go = async (fn, data, uid = 'own1') => {
  try { return {ok: true, r: await fn({data, auth: {uid, token: {}}})}; } catch (e) { return {ok: false, e}; }
};
const code = (o) => o.e && ((o.e.details && o.e.details.code) || o.e.code);
const cron = () => X.processCloseSlotCleanupMarkers(new Ts(NOW));

function base() {
  F.reset(); NOW = RealDate.UTC(2026, 10, 27, 3, 0);
  F.occ.enabled = true;
  F.put('users/own1', {role: 'BUSINESS_ADMIN', accountStatus: 'active', name: '사장'});
  F.put('businesses/b1', {name: '평택', ownerId: 'own1', adminIds: ['own1'], isApproved: true});
  F.put('tos/t1', {businessId: 'b1', title: '물류', status: 'ACTIVE', type: 'flex', totalPending: 0, totalConfirmed: 0, isPublished: false});
}
const slot = (id, o = {}) => F.put(`tos/t1/slots/${id}`, Object.assign({status: 'open', date: new Ts(NOW + 3 * DAY),
  pendingCount: 0, confirmedCount: 0, workDetails: [{wdId: 'wd1', workType: '포장', startTime: '09:00', endTime: '18:00', requiredCount: 5}],
  workDetailCounts: {wd1: {pendingCount: 0, confirmedCount: 0}}}, o));
const pend = (id, slotId) => F.put(`applications/${id}`, {uid: `u_${id}`, businessId: 'b1', businessName: '평택', toId: 't1', slotId,
  wdId: 'wd1', status: 'PENDING', selectedWorkType: '포장', workDate: new Ts(NOW + 3 * DAY)});
const marker = (slotId) => F.get(`slot_close_cleanup/t1__${slotId}`);
const legacyClosed = (id, n, prefix) => {
  slot(id, {status: 'closed', isManualClosed: true, closedAt: new Ts(NOW - DAY), closedBy: 'own1', pendingCount: n,
    workDetailCounts: {wd1: {pendingCount: n, confirmedCount: 0}}});
  for (let i = 0; i < n; i++) pend(`${prefix}${String(i).padStart(3, '0')}`, id);
  F.put('tos/t1', Object.assign(F.get('tos/t1'), {totalPending: (F.get('tos/t1').totalPending || 0) + n}));
};

test('R1 공고 상태 재계산 — 슬롯 조회 직후 재오픈이 커밋되면 옛 스냅샷으로 공고를 CLOSED 로 덮지 않는다', async () => {
  base(); slot('s1', {pendingCount: 1, workDetailCounts: {wd1: {pendingCount: 1, confirmedCount: 0}}}); pend('a000', 's1');
  let armed = true;
  F.hooks.afterQuery = (cp) => {
    // 공고 상태 재계산이 슬롯 목록을 읽은 직후 = 재오픈(ReopenSlots 결과와 같은 상태)이 커밋된다
    if (!armed || cp !== 'tos/t1/slots') return;
    armed = false;
    const sl = F.get('tos/t1/slots/s1');
    delete sl.closeCleanupToken; delete sl.closedAt; delete sl.closedBy;
    F.put('tos/t1/slots/s1', Object.assign(sl, {status: 'open', isManualClosed: false, reopenedBy: 'own1'}));
    F.del('slot_close_cleanup/t1__s1');
  };
  const o = await go(X.callableCloseSlots, {toId: 't1', slotIds: ['s1'], businessId: 'b1'});
  F.hooks.afterQuery = null;
  assert.ok(!armed, '재오픈 주입이 일어났다');
  assert.ok(o.ok, o.e && o.e.message);
  assert.strictEqual(F.get('tos/t1/slots/s1').status, 'open');
  if (OLD) {
    assert.strictEqual(F.get('tos/t1').status, 'CLOSED', '음성 대조: 이전 원문은 재오픈된 공고를 옛 스냅샷으로 CLOSED 로 덮는다');
    return;
  }
  assert.strictEqual(F.get('tos/t1').status, 'ACTIVE', '재오픈된 공고는 모집 상태 유지');
});

test('R1b 정상 동치 — 열린 슬롯이 없으면 공고 CLOSED(같은 거래) · 열린 다른 날짜가 있으면 ACTIVE', async () => {
  base(); slot('s1'); slot('s2');
  let o = await go(X.callableCloseSlots, {toId: 't1', slotIds: ['s1'], businessId: 'b1'});
  assert.ok(o.ok, o.e && o.e.message);
  assert.strictEqual(F.get('tos/t1').status, 'ACTIVE');
  o = await go(X.callableCloseSlots, {toId: 't1', slotIds: ['s2'], businessId: 'b1'});
  assert.ok(o.ok, o.e && o.e.message);
  assert.strictEqual(F.get('tos/t1').status, 'CLOSED');
  if (OLD) return;
  const c = F.W.commits.find((x) => x.writes.some((w) => w.path === 'tos/t1' && w.data && w.data.status === 'CLOSED'));
  const reads = F.W.reads.filter((r) => r.tx === c.tx).map((r) => r.path);
  assert.ok(reads.includes('tos/t1') && reads.includes('tos/t1/slots'), 'CLOSED 쓰기 거래가 공고·슬롯 목록을 같은 거래에서 읽는다');
});

test('R2a legacy cleanupOnly — 멈춘 옛 요청이 재오픈→새 지원→새 닫기 뒤 새 사건의 대기를 거절하지 않는다', async () => {
  base(); legacyClosed('s1', 1, 'r');
  let armed = true;
  F.hooks.afterGet = (p, txId) => {
    if (!armed || txId != null || p !== 'slot_close_cleanup/t1__s1') return;
    armed = false;
    // 옛 요청이 멈춘 사이: 재오픈 → 새 지원 n1 → 새 닫기(새 closedAt · 새 사건 token T2 · 표식 T2 · 그 정리는 아직)
    const sl = F.get('tos/t1/slots/s1');
    F.put('tos/t1/slots/s1', Object.assign(sl, {status: 'closed', isManualClosed: true, closedAt: new Ts(NOW + 1000),
      closedBy: 'own1', closeCleanupToken: 'T2', pendingCount: 2, workDetailCounts: {wd1: {pendingCount: 2, confirmedCount: 0}}}));
    pend('n1', 's1');
    F.put('slot_close_cleanup/t1__s1', {toId: 't1', slotId: 's1', businessId: 'b1', token: 'T2', closedAt: new Ts(NOW + 1000),
      closedBy: 'own1', attempts: 0, lastError: null, nextAttemptAt: new Ts(NOW + 1000)});
  };
  const o = await go(X.callableCloseSlots, {toId: 't1', slotIds: ['s1'], businessId: 'b1', cleanupOnly: true});
  F.hooks.afterGet = null;
  assert.ok(!armed, '주입이 일어났다');
  assert.ok(o.ok, o.e && o.e.message);
  if (OLD) {
    assert.strictEqual(F.get('applications/n1').status, 'REJECTED', '음성 대조: 이전 원문은 옛 legacy 요청이 새 사건의 대기를 거절한다');
    return;
  }
  assert.strictEqual(F.get('applications/n1').status, 'PENDING', '옛 요청은 새 사건(T2)의 대기를 건드리지 않는다');
  assert.strictEqual(marker('s1').token, 'T2', '새 사건 표식 보존');
  // 새 사건 정리는 그 표식(매시)이 한다
  await cron();
  assert.strictEqual(F.get('applications/n1').status, 'REJECTED');
  assert.strictEqual(F.get('applications/r000').status, 'REJECTED');
  assert.strictEqual(F.get('tos/t1/slots/s1').pendingCount, 0);
  assert.strictEqual(marker('s1'), undefined);
});

test('R2b legacy cleanupOnly 중간 실패 — 표식이 남아 resumable:true 가 참이 된다 · 매시가 끝낸다 · closedAt/By 보존', async () => {
  base(); legacyClosed('s1', 2, 'r'); slot('s9');
  const closedAt0 = F.get('tos/t1/slots/s1').closedAt;
  let fail = true;
  F.hooks.beforeCommit = (txId, buf) => {
    if (fail && buf.some((w) => w.path === 'applications/r000')) { fail = false; throw new Error('UNAVAILABLE'); }
  };
  const o = await go(X.callableCloseSlots, {toId: 't1', slotIds: ['s1'], businessId: 'b1', cleanupOnly: true});
  F.hooks.beforeCommit = null;
  assert.ok(!o.ok);
  assert.strictEqual(code(o), 'CLOSE_SLOTS_INCOMPLETE');
  if (OLD) {
    assert.strictEqual(o.e.details.resumable, true);
    assert.strictEqual(marker('s1'), undefined, '음성 대조: 이전 원문은 표식 없이 resumable:true 라고 답한다');
    return;
  }
  assert.strictEqual(o.e.details.resumable, true);
  assert.ok(marker('s1'), '재개할 사건 표식');
  assert.strictEqual(marker('s1').origin, 'cleanupOnly');
  assert.strictEqual(marker('s1').attempts, 1);
  await cron();
  assert.deepStrictEqual(['r000', 'r001'].map((id) => F.get(`applications/${id}`).status), ['REJECTED', 'REJECTED']);
  const sl = F.get('tos/t1/slots/s1');
  assert.strictEqual(sl.closedBy, 'own1');
  assert.strictEqual(sl.closedAt.toMillis(), closedAt0.toMillis());
  assert.strictEqual(sl.closeCleanupToken, undefined);
  assert.strictEqual(sl.pendingCount, 0);
  assert.strictEqual(marker('s1'), undefined);
});

test('R2c 실패했는데 그 사이 표식이 사라졌다(재오픈) — resumable:false(재개 약속 0)', async () => {
  base(); slot('s1', {pendingCount: 1, workDetailCounts: {wd1: {pendingCount: 1, confirmedCount: 0}}}); pend('a000', 's1'); slot('s9');
  let fail = true;
  F.hooks.beforeCommit = (txId, buf) => {
    if (fail && buf.some((w) => w.path === 'applications/a000')) {
      fail = false;
      // 실패한 그 순간 재오픈(표식·token 제거)
      const sl = F.get('tos/t1/slots/s1'); delete sl.closeCleanupToken;
      F.put('tos/t1/slots/s1', Object.assign(sl, {status: 'open', isManualClosed: false}));
      F.del('slot_close_cleanup/t1__s1');
      throw new Error('UNAVAILABLE');
    }
  };
  const o = await go(X.callableCloseSlots, {toId: 't1', slotIds: ['s1'], businessId: 'b1'});
  F.hooks.beforeCommit = null;
  assert.ok(!o.ok);
  assert.strictEqual(code(o), 'CLOSE_SLOTS_INCOMPLETE');
  if (OLD) { assert.strictEqual(o.e.details.resumable, true, '음성 대조: 이전 원문은 표식이 없어도 resumable:true'); return; }
  assert.strictEqual(o.e.details.resumable, false);
  assert.strictEqual(marker('s1'), undefined, '실패 기록이 끝난 사건 표식을 되살리지 않는다');
});

test('R3 앞 100 표식이 계속 실패 — 다음 매시에 101번째 표식이 차례를 얻는다', async () => {
  base();
  const failing = new Set();
  for (let i = 0; i < 100; i++) {
    const id = `f${String(i).padStart(3, '0')}`; failing.add(id);
    slot(id, {status: 'closed', isManualClosed: true, closedAt: new Ts(NOW - DAY), closeCleanupToken: `T${id}`, pendingCount: 1,
      workDetailCounts: {wd1: {pendingCount: 1, confirmedCount: 0}}});
    pend(`p${id}`, id);
    F.put(`slot_close_cleanup/t1__${id}`, {toId: 't1', slotId: id, businessId: 'b1', token: `T${id}`, closedAt: new Ts(NOW - DAY),
      closedBy: 'own1', attempts: 0, lastError: null, nextAttemptAt: new Ts(NOW - DAY + i)});
  }
  slot('z', {status: 'closed', isManualClosed: true, closedAt: new Ts(NOW - DAY), closeCleanupToken: 'Tz', pendingCount: 1,
    workDetailCounts: {wd1: {pendingCount: 1, confirmedCount: 0}}});
  pend('pz', 'z');
  F.put('slot_close_cleanup/t1__z', {toId: 't1', slotId: 'z', businessId: 'b1', token: 'Tz', closedAt: new Ts(NOW - DAY),
    closedBy: 'own1', attempts: 0, lastError: null, nextAttemptAt: new Ts(NOW - 1000)});
  F.put('tos/t1', Object.assign(F.get('tos/t1'), {totalPending: 101}));
  // f* 슬롯의 대기 조회는 언제나 실패(지속 장애)
  const orig = F.db.collection;
  F.db.collection = (c) => {
    const real = orig(c);
    if (c !== 'applications') return real;
    const filters = [];
    const wrap = (q) => new Proxy(q, {get: (t, k) => {
      if (k === 'get') return async () => { if (filters.some((f) => failing.has(f))) throw new Error('UNAVAILABLE'); return t.get(); };
      if (k === 'where') return (f, op, v) => { if (f === 'slotId') filters.push(v); return wrap(t.where(f, op, v)); };
      if (k === 'limit' || k === 'orderBy' || k === 'startAfter') return (...a) => wrap(t[k](...a));
      return typeof t[k] === 'function' ? t[k].bind(t) : t[k];
    }});
    return wrap(real);
  };
  try {
    await cron();
    NOW += 3600000;
    await cron();
  } finally { F.db.collection = orig; }
  if (OLD) {
    assert.strictEqual(F.get('applications/pz').status, 'PENDING', '음성 대조: 이전 원문은 앞 100개만 계속 보고 101번째를 굶긴다');
    return;
  }
  assert.strictEqual(F.get('applications/pz').status, 'REJECTED', '두 번째 매시에 101번째가 처리됐다');
  assert.strictEqual(marker('z'), undefined);
  assert.ok(marker('f000').attempts >= 1, '실패 표식은 남고 시도 수가 오른다');
  assert.ok(marker('f000').nextAttemptAt.toMillis() > NOW - 3600000 - 1, '실패 표식은 순회 맨 뒤로');
});

test('R3b CloseSlots 닫기 커밋의 표식에 nextAttemptAt(매시 순회 대상)', async () => {
  base(); slot('s1', {pendingCount: 1, workDetailCounts: {wd1: {pendingCount: 1, confirmedCount: 0}}}); pend('a000', 's1');
  let fail = true;
  F.hooks.beforeCommit = (txId, buf) => {
    if (fail && buf.some((w) => w.path === 'applications/a000')) { fail = false; throw new Error('UNAVAILABLE'); }
  };
  const o = await go(X.callableCloseSlots, {toId: 't1', slotIds: ['s1'], businessId: 'b1'});
  F.hooks.beforeCommit = null;
  assert.ok(!o.ok);
  if (OLD) return;
  assert.strictEqual(o.e.details.resumable, true);
  assert.ok(marker('s1').nextAttemptAt && typeof marker('s1').nextAttemptAt.toMillis === 'function');
  await cron();
  assert.strictEqual(F.get('applications/a000').status, 'REJECTED');
});
