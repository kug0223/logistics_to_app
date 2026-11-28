'use strict';
/**
 * [판정295 F295-CLOSE-01] 날짜 닫기(CloseSlots) 대기 정리 — 영속 진행 표식 · 같은 fresh helper 재개(callable · 매시) · cleanupOnly.
 *   S295_EXPECT_OLD=1 이면 이전 원문(dbed3203 사본)에서 결함(조회 실패 일반 오류 · 표식 0 · 재진입 시 closedAt 덮어쓰기)을 재현한다.
 */
const {test} = require('node:test');
const assert = require('assert');
const {createFakeFirestore} = require('./consent_r4d_fakestore');
const {loadIndexClosure} = require('./auth_kakao_index_harness');

const OLD = process.env.S295_EXPECT_OLD === '1';
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
const ROOTS = OLD ? ['callableCloseSlots', 'callableReopenSlots'] :
  ['callableCloseSlots', 'callableReopenSlots', 'processCloseSlotCleanupMarkers'];
const {exports: X} = loadIndexClosure(ROOTS, F, {HttpsError, console: QCON, Date: FakeDate});
const Ts = F.Ts;
const go = async (fn, data, uid = 'own1') => {
  try { return {ok: true, r: await fn({data, auth: {uid, token: {}}})}; } catch (e) { return {ok: false, e}; }
};
const code = (o) => o.e && ((o.e.details && o.e.details.code) || o.e.code);
const cron = () => X.processCloseSlotCleanupMarkers(new Ts(NOW));

function base() {
  F.reset(); F.hooks.afterGet = null; F.hooks.beforeCommit = null; NOW = RealDate.UTC(2026, 10, 27, 3, 0);
  F.put('users/own1', {role: 'BUSINESS_ADMIN', accountStatus: 'active', name: '사장'});
  F.put('users/sub1', {role: 'USER', accountStatus: 'active', name: '부', subAdminBusinessIds: ['b1']});
  F.put('businesses/b1/members/sub1', {uid: 'sub1', permissions: {canManageTo: true}});
  F.put('businesses/b1', {name: '평택', ownerId: 'own1', adminIds: ['own1'], isApproved: true});
  F.put('tos/t1', {businessId: 'b1', title: '물류', status: 'ACTIVE', type: 'flex', totalPending: 0, totalConfirmed: 0, isPublished: false});
}
const slot = (id, o = {}) => F.put(`tos/t1/slots/${id}`, Object.assign({status: 'open', date: new Ts(NOW + 3 * DAY),
  pendingCount: 0, confirmedCount: 0, workDetails: [{wdId: 'wd1', workType: '포장', startTime: '09:00', endTime: '18:00', requiredCount: 5}],
  workDetailCounts: {wd1: {pendingCount: 0, confirmedCount: 0}}}, o));
const pend = (id, slotId) => F.put(`applications/${id}`, {uid: `u_${id}`, businessId: 'b1', businessName: '평택', toId: 't1', slotId,
  wdId: 'wd1', status: 'PENDING', selectedWorkType: '포장', workDate: new Ts(NOW + 3 * DAY)});
function seedPending(slotId, n, prefix) {
  slot(slotId, {pendingCount: n, workDetailCounts: {wd1: {pendingCount: n, confirmedCount: 0}}});
  for (let i = 0; i < n; i++) pend(`${prefix}${String(i).padStart(3, '0')}`, slotId);
  F.put('tos/t1', Object.assign(F.get('tos/t1'), {totalPending: (F.get('tos/t1').totalPending || 0) + n}));
}
const marker = (slotId) => F.get(`slot_close_cleanup/t1__${slotId}`);
const notifCount = () => Object.keys(F.dump()).filter((k) => /^users\/[^/]+\/notifications\//.test(k)).length;
// 지원서 PENDING 질의(slotId 지정)를 n번째 호출에서 한 번 실패시킨다.
function failNthPendingQuery(slotId, n) {
  const orig = F.db.collection;
  let seen = 0; let fired = false;
  F.db.collection = (c) => {
    const real = orig(c);
    if (c !== 'applications' || fired) return real;
    const filters = [];
    const wrap = (q) => new Proxy(q, {get: (t, k) => {
      if (k === 'get') return async () => {
        if (!fired && filters.includes(`slotId=${slotId}`) && filters.includes('status=PENDING') && ++seen === n) {
          fired = true; throw new Error('UNAVAILABLE');
        }
        return t.get();
      };
      if (k === 'where') return (f, op, v) => { filters.push(`${f}=${v}`); return wrap(t.where(f, op, v)); };
      if (k === 'limit' || k === 'orderBy' || k === 'startAfter') return (...a) => wrap(t[k](...a));
      return typeof t[k] === 'function' ? t[k].bind(t) : t[k];
    }});
    return wrap(real);
  };
  return () => { F.db.collection = orig; };
}

test('K1 정상 닫기 — 슬롯 닫기와 진행 표식이 **같은 커밋** · 정리 끝나면 표식·token 삭제', async () => {
  base(); seedPending('s1', 2, 'a'); slot('s9');
  const o = await go(X.callableCloseSlots, {toId: 't1', slotIds: ['s1'], businessId: 'b1'});
  assert.ok(o.ok, o.e && o.e.message);
  assert.strictEqual(o.r.canceledCount, 2);
  if (OLD) return;
  const c = F.W.commits.find((x) => x.writes.some((w) => w.path === 'tos/t1/slots/s1' && w.data && w.data.status === 'closed'));
  assert.ok(c.writes.some((w) => w.path === 'slot_close_cleanup/t1__s1'), '표식이 닫기와 같은 커밋');
  assert.strictEqual(marker('s1'), undefined, '완료 뒤 표식 삭제');
  assert.strictEqual(F.get('tos/t1/slots/s1').closeCleanupToken, undefined);
});

test('K2 닫기 뒤 첫 페이지 조회 실패 — 일반 오류가 아니라 미완료(범위) · 표식 남음 → 매시 재개가 끝낸다', async () => {
  base(); seedPending('s1', 1, 'a'); seedPending('s2', 2, 'b'); slot('s9');
  const restore = failNthPendingQuery('s2', 1);
  const o = await go(X.callableCloseSlots, {toId: 't1', slotIds: ['s1', 's2'], businessId: 'b1'});
  restore();
  assert.ok(!o.ok);
  if (OLD) { assert.notStrictEqual(code(o), 'CLOSE_SLOTS_INCOMPLETE', '음성 대조: 이전 원문은 조회 실패를 일반 오류로'); return; }
  assert.strictEqual(code(o), 'CLOSE_SLOTS_INCOMPLETE');
  assert.deepStrictEqual(o.e.details.failedSlotIds, ['s2']);
  assert.strictEqual(o.e.details.slotsClosed, 2);
  assert.strictEqual(o.e.details.applicationsRejected, 1);
  assert.strictEqual(o.e.details.resumable, true);
  assert.ok(marker('s2'), 's2 표식 남음');
  assert.strictEqual(marker('s2').lastError.includes('UNAVAILABLE'), true);
  // 앱이 '나중에' 를 골라도 — 매시 재개
  await cron();
  assert.deepStrictEqual(['b000', 'b001'].map((id) => F.get(`applications/${id}`).status), ['REJECTED', 'REJECTED']);
  assert.strictEqual(F.get('tos/t1/slots/s2').pendingCount, 0);
  assert.strictEqual(F.get('tos/t1').totalPending, 0);
  assert.strictEqual(marker('s2'), undefined);
});

test('K3 501 · 두 번째 페이지 조회 실패 → 매시 재개가 남은 1건만 · 대기 −501 정확', async () => {
  base(); seedPending('s1', 501, 'p'); slot('s9');
  const restore = failNthPendingQuery('s1', 2);
  const o = await go(X.callableCloseSlots, {toId: 't1', slotIds: ['s1'], businessId: 'b1'});
  restore();
  if (OLD) { assert.ok(!o.ok); assert.notStrictEqual(code(o), 'CLOSE_SLOTS_INCOMPLETE'); return; }
  assert.strictEqual(code(o), 'CLOSE_SLOTS_INCOMPLETE');
  assert.strictEqual(o.e.details.applicationsRejected, 500);
  assert.strictEqual(F.get('applications/p500').status, 'PENDING');
  const before = notifCount();
  await cron();
  assert.strictEqual(F.get('applications/p500').status, 'REJECTED');
  assert.strictEqual(notifCount() - before, 1, '알림은 실제 거절한 1건만');
  assert.strictEqual(F.get('tos/t1/slots/s1').pendingCount, 0);
  assert.strictEqual(F.get('tos/t1').totalPending, 0);
  assert.strictEqual(marker('s1'), undefined);
});

test('K4 중간 커밋 실패 → 앱 종료(재호출 0) → 매시 재개 · 실제 적용분만 delta/알림', async () => {
  base(); seedPending('s1', 2, 'a'); slot('s9');
  let fail = true;
  F.hooks.beforeCommit = (txId, buf) => {
    if (fail && buf.some((w) => w.path === 'applications/a000')) { fail = false; throw new Error('UNAVAILABLE'); }
  };
  const o = await go(X.callableCloseSlots, {toId: 't1', slotIds: ['s1'], businessId: 'b1'});
  F.hooks.beforeCommit = null;
  assert.ok(!o.ok);
  if (OLD) { assert.strictEqual(F.get('slot_close_cleanup/t1__s1'), undefined, '음성 대조: 이전 원문은 재개할 표식이 없다'); return; }
  assert.ok(marker('s1'));
  // 그 사이 a001 은 확정(다른 경로) — 거절·감소 대상 아님
  F.put('applications/a001', Object.assign(F.get('applications/a001'), {status: 'CONFIRMED'}));
  const before = notifCount();
  await cron();
  assert.strictEqual(F.get('applications/a000').status, 'REJECTED');
  assert.strictEqual(F.get('applications/a001').status, 'CONFIRMED');
  assert.strictEqual(F.get('tos/t1/slots/s1').pendingCount, 1, '실제 거절 1 만 감소');
  assert.strictEqual(notifCount() - before, 1);
  assert.strictEqual(marker('s1'), undefined);
});

test('K5 공고 상태 갱신 실패 → 표식 유지(TO_STATUS_FAILED) → 매시 재개가 공고 CLOSED 뒤 표식 삭제', async () => {
  base(); seedPending('s1', 1, 'a');
  let fail = true;
  F.hooks.beforeCommit = (txId, buf) => {
    if (fail && buf.some((w) => w.path === 'tos/t1' && w.data && w.data.status === 'CLOSED')) { fail = false; throw new Error('UNAVAILABLE'); }
  };
  const o = await go(X.callableCloseSlots, {toId: 't1', slotIds: ['s1'], businessId: 'b1'});
  F.hooks.beforeCommit = null;
  assert.ok(!o.ok);
  assert.strictEqual(o.e.details.toStatusFailed, true);
  if (OLD) return;
  assert.strictEqual(marker('s1').lastError, 'TO_STATUS_FAILED');
  await cron();
  assert.strictEqual(F.get('tos/t1').status, 'CLOSED');
  assert.strictEqual(marker('s1'), undefined);
});

test('K6 cleanupOnly — 최초 closedAt/closedBy 보존 · 남은 대기만 · fresh 권한(다른 관리자)', async () => {
  base(); seedPending('s1', 2, 'a'); slot('s9');
  let fail = true;
  F.hooks.beforeCommit = (txId, buf) => {
    if (fail && buf.some((w) => w.path === 'applications/a000')) { fail = false; throw new Error('UNAVAILABLE'); }
  };
  await go(X.callableCloseSlots, {toId: 't1', slotIds: ['s1'], businessId: 'b1'});
  F.hooks.beforeCommit = null;
  const closedAt0 = F.get('tos/t1/slots/s1').closedAt;
  NOW += 3600000;
  const o = await go(X.callableCloseSlots, {toId: 't1', slotIds: ['s1'], businessId: 'b1', cleanupOnly: true}, 'sub1');
  assert.ok(o.ok, o.e && o.e.message);
  const sl = F.get('tos/t1/slots/s1');
  if (OLD) {
    assert.strictEqual(sl.closedBy, 'sub1', '음성 대조: 이전 원문은 재호출이 closedBy/closedAt 을 덮는다');
    return;
  }
  assert.strictEqual(o.r.mode, 'cleanupOnly');
  assert.strictEqual(sl.closedBy, 'own1');
  assert.strictEqual(sl.closedAt.toMillis(), closedAt0.toMillis());
  assert.strictEqual(F.get('applications/a000').status, 'REJECTED');
  assert.strictEqual(marker('s1'), undefined);
});

test('K7 권한 회수 — cleanupOnly 는 permission-denied(쓰기 0) · 기록된 닫기 사건은 매시 재개가 끝낸다', async () => {
  base(); seedPending('s1', 1, 'a'); slot('s9');
  let fail = true;
  F.hooks.beforeCommit = (txId, buf) => {
    if (fail && buf.some((w) => w.path === 'applications/a000')) { fail = false; throw new Error('UNAVAILABLE'); }
  };
  await go(X.callableCloseSlots, {toId: 't1', slotIds: ['s1'], businessId: 'b1'}, 'sub1');
  F.hooks.beforeCommit = null;
  F.put('businesses/b1/members/sub1', {uid: 'sub1', permissions: {canManageTo: false}});
  const o = await go(X.callableCloseSlots, {toId: 't1', slotIds: ['s1'], businessId: 'b1', cleanupOnly: true}, 'sub1');
  assert.ok(!o.ok);
  assert.strictEqual(o.e.code, 'permission-denied');
  assert.strictEqual(F.get('applications/a000').status, 'PENDING');
  if (OLD) return;
  await cron();
  assert.strictEqual(F.get('applications/a000').status, 'REJECTED', '권한이 있던 때 커밋된 닫기 사건의 정리를 완결');
});

test('K8 재오픈 경합 — 재오픈(callable) 뒤 새 대기는 옛 표식으로 거절되지 않는다', async () => {
  base(); seedPending('s1', 1, 'a'); slot('s9');
  let fail = true;
  F.hooks.beforeCommit = (txId, buf) => {
    if (fail && buf.some((w) => w.path === 'applications/a000')) { fail = false; throw new Error('UNAVAILABLE'); }
  };
  await go(X.callableCloseSlots, {toId: 't1', slotIds: ['s1'], businessId: 'b1'});
  F.hooks.beforeCommit = null;
  const ro = await go(X.callableReopenSlots, {toId: 't1', slotIds: ['s1'], businessId: 'b1'});
  assert.ok(ro.ok, ro.e && ro.e.message);
  pend('n1', 's1');
  if (OLD) return;
  assert.strictEqual(marker('s1'), undefined, '재오픈이 표식을 지운다');
  await cron();
  assert.strictEqual(F.get('applications/n1').status, 'PENDING');
  assert.strictEqual(F.get('applications/a000').status, 'PENDING', '재오픈으로 끝난 사건의 대기는 더 거절하지 않는다');
});

test('K9 재오픈·다시 닫기를 직접 쓰기로 한 경합 — closedAt 이 다르면 옛 표식은 끝난 사건(삭제) · 새 대기 보존', async () => {
  base(); seedPending('s1', 1, 'a'); slot('s9');
  let fail = true;
  F.hooks.beforeCommit = (txId, buf) => {
    if (fail && buf.some((w) => w.path === 'applications/a000')) { fail = false; throw new Error('UNAVAILABLE'); }
  };
  await go(X.callableCloseSlots, {toId: 't1', slotIds: ['s1'], businessId: 'b1'});
  F.hooks.beforeCommit = null;
  if (OLD) return;
  const sl = F.get('tos/t1/slots/s1');
  F.put('tos/t1/slots/s1', Object.assign({}, sl, {status: 'open', isManualClosed: false, closedAt: null}));
  pend('n1', 's1');
  F.put('tos/t1/slots/s1', Object.assign(F.get('tos/t1/slots/s1'), {status: 'closed', isManualClosed: true, closedAt: new Ts(NOW + 5000)}));
  await cron();
  assert.strictEqual(F.get('applications/n1').status, 'PENDING');
  assert.strictEqual(marker('s1'), undefined);
});

test('K10 완료 no-op · 표식 없는 기존 잔여 — 매시는 손대지 않고 관리자 cleanupOnly 명시 때만 · 닫히지 않은 날짜는 notClosed', async () => {
  base();
  slot('s1', {status: 'closed', isManualClosed: true, closedAt: new Ts(NOW - DAY), closedBy: 'own1', pendingCount: 1,
    workDetailCounts: {wd1: {pendingCount: 1, confirmedCount: 0}}});
  pend('r1', 's1');
  slot('s2');
  slot('s3', {status: 'closed', isManualClosed: true, closedAt: new Ts(NOW - DAY), closedBy: 'own1'});
  F.put('tos/t1', Object.assign(F.get('tos/t1'), {totalPending: 1}));
  if (!OLD) {
    await cron();
    assert.strictEqual(F.get('applications/r1').status, 'PENDING', '표식 없는 잔여를 매시가 일괄 거절하지 않는다');
  }
  const o = await go(X.callableCloseSlots, {toId: 't1', slotIds: ['s1', 's2', 's3'], businessId: 'b1', cleanupOnly: true});
  assert.ok(o.ok, o.e && o.e.message);
  if (OLD) { assert.strictEqual(F.get('tos/t1/slots/s2').status, 'closed', '음성 대조: 이전 원문은 cleanupOnly 를 모르고 열린 날짜를 닫는다'); return; }
  assert.strictEqual(F.get('applications/r1').status, 'REJECTED');
  assert.deepStrictEqual(o.r.notClosedSlotIds, ['s2']);
  assert.strictEqual(F.get('tos/t1/slots/s2').status, 'open', 'cleanupOnly 는 닫지 않는다');
  assert.strictEqual(o.r.canceledCount, 1);
  const o2 = await go(X.callableCloseSlots, {toId: 't1', slotIds: ['s1', 's3'], businessId: 'b1', cleanupOnly: true});
  assert.ok(o2.ok);
  assert.strictEqual(o2.r.canceledCount, 0, '완료 no-op');
  assert.strictEqual(F.get('tos/t1').totalPending, 0);
});

test('K11 cleanupOnly 형식 — boolean 아님 거절', async () => {
  base(); slot('s1');
  const o = await go(X.callableCloseSlots, {toId: 't1', slotIds: ['s1'], businessId: 'b1', cleanupOnly: 'yes'});
  if (OLD) return;
  assert.strictEqual(o.e.code, 'invalid-argument');
});
