'use strict';
/**
 * [판정292 J2 · 판정293 §10 (2)] 서버 자동 마감 3거래 — 실제 변경이 있을 때만 editRevision +1, no-op 이면 쓰기 0.
 *   R1 계약 공고 업무 마감(processWorkDetailExpiry) · R2 슬롯 업무 마감(processSlotWorkDetailExpiry) · R3 공고 접수 마감(srvTOApplicationDeadlineExpiry)
 *   R4 부분 업무 마감 뒤 옛 폼(마감 전 editRevision)으로 슬롯 업무 저장 → STALE-EDIT 거절.
 *   S293J2_EXPECT_OLD=1 이면 이전 원문에서 revision 이 그대로(0)인 것을 확인한다(음성 대조).
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
const {exports: X} = loadIndexClosure(['processWorkDetailExpiry', 'processSlotWorkDetailExpiry', 'srvTOApplicationDeadlineExpiry',
  'callableUpdateSlotWorkDetails'], F, {HttpsError, console: QCON, Date: FakeDate});
const Ts = F.Ts;
const H = 3600000;
const OLD = process.env.S293J2_EXPECT_OLD === '1';
const nowTs = () => new Ts(NOW);
const writesTo = (p) => F.W.commits.flatMap((c) => c.writes).filter((w) => w.path === p).length;

function base() {
  F.reset();
  F.put('users/own1', {role: 'BUSINESS_ADMIN', accountStatus: 'active', name: '사장'});
  F.put('businesses/b1', {name: '평택', ownerId: 'own1', adminIds: ['own1'], isApproved: true});
}
const WD = (o) => Object.assign({wdId: 'wd1', workType: '포장', startTime: '09:00', endTime: '18:00', requiredCount: 2,
  wage: 12000, wageType: 'hourly'}, o);

test('R1 계약 공고 업무 마감 — 닫으면 editRevision +1 · 다시 돌리면 쓰기 0', async () => {
  base();
  F.put('tos/t1', {businessId: 'b1', status: 'ACTIVE', type: 'contract', editRevision: 4,
    workDetails: [WD({applicationDeadline: new Ts(NOW - H)}), WD({wdId: 'wd2', workType: '분류'})]});
  await X.processWorkDetailExpiry(nowTs());
  const t = F.get('tos/t1');
  assert.ok(t.workDetails[0].closedAt, '업무가 닫혀야 한다');
  assert.strictEqual(t.editRevision, OLD ? 4 : 5);
  const n = writesTo('tos/t1');
  await X.processWorkDetailExpiry(nowTs());
  assert.strictEqual(F.get('tos/t1').editRevision, OLD ? 4 : 5, 'no-op 에서 올리면 안 된다');
  assert.strictEqual(writesTo('tos/t1'), n, 'no-op 쓰기 0');
});

test('R2 슬롯 업무 마감 — 닫으면 슬롯 editRevision +1 · 다시 돌리면 쓰기 0', async () => {
  base();
  F.put('tos/t1', {businessId: 'b1', status: 'ACTIVE', type: 'short', totalRequired: 4});
  F.put('tos/t1/slots/s1', {status: 'open', editRevision: 2, date: new Ts(NOW + 24 * H),
    workDetails: [WD({applicationDeadline: new Ts(NOW - H)}), WD({wdId: 'wd2', workType: '분류'})]});
  await X.processSlotWorkDetailExpiry(nowTs());
  const s = F.get('tos/t1/slots/s1');
  assert.ok(s.workDetails[0].closedAt);
  assert.strictEqual(s.editRevision, OLD ? 2 : 3);
  const n = writesTo('tos/t1/slots/s1');
  await X.processSlotWorkDetailExpiry(nowTs());
  assert.strictEqual(F.get('tos/t1/slots/s1').editRevision, OLD ? 2 : 3);
  assert.strictEqual(writesTo('tos/t1/slots/s1'), n);
});

test('R3 공고 접수 마감 — 닫으면 공고 editRevision +1 · 다시 돌리면 쓰기 0', async () => {
  base();
  F.put('tos/t1', {businessId: 'b1', status: 'ACTIVE', type: 'short', editRevision: 7, applicationDeadline: new Ts(NOW - H),
    workDetails: [WD()]});
  await X.srvTOApplicationDeadlineExpiry(nowTs());
  const t = F.get('tos/t1');
  assert.strictEqual(t.status, 'CLOSED');
  assert.strictEqual(t.editRevision, OLD ? 7 : 8);
  const n = writesTo('tos/t1');
  await X.srvTOApplicationDeadlineExpiry(nowTs());
  assert.strictEqual(F.get('tos/t1').editRevision, OLD ? 7 : 8);
  assert.strictEqual(writesTo('tos/t1'), n);
});

test('R4 부분 업무 마감 뒤 옛 폼(마감 전 버전)으로 슬롯 업무 저장 → STALE-EDIT', async () => {
  base();
  F.put('tos/t1', {businessId: 'b1', status: 'ACTIVE', type: 'short', totalRequired: 4, title: '물류'});
  F.put('tos/t1/slots/s1', {status: 'open', editRevision: 2, date: new Ts(NOW + 24 * H), confirmedCount: 0, pendingCount: 0,
    workDetails: [WD({applicationDeadline: new Ts(NOW - H)}), WD({wdId: 'wd2', workType: '분류'})],
    workDetailCounts: {wd1: {confirmedCount: 0, pendingCount: 0}, wd2: {confirmedCount: 0, pendingCount: 0}}});
  await X.processSlotWorkDetailExpiry(nowTs());
  let err = null;
  try {
    await X.callableUpdateSlotWorkDetails({auth: {uid: 'own1', token: {}}, data: {toId: 't1', businessId: 'b1', slotId: 's1',
      expectedEditRevision: 2,
      workDetails: [WD({applicationDeadline: new Ts(NOW + 5 * H)}), WD({wdId: 'wd2', workType: '분류'})]}});
  } catch (e) { err = e; }
  if (OLD) {
    assert.ok(!err || !/다른 관리자가 슬롯을 수정했습니다/.test(String(err.message)), '음성 대조: 예전 원문은 옛 폼을 막지 못한다');
    return;
  }
  assert.ok(err, '옛 폼 저장이 거절되어야 한다');
  assert.match(String(err.message), /다른 관리자가 슬롯을 수정했습니다/);
});

// 슬롯 조회 스냅샷 뒤 · 거래 전에 다른 관리자가 슬롯을 저장(편집 버전 +1)한 경합 — 자동 마감은 거래 안 fresh 값 + 1 이어야 한다.
function afterFirstGroupQuery(col, fn) {
  const orig = F.db.collectionGroup;
  let fired = false;
  F.db.collectionGroup = (c) => {
    const real = orig(c);
    if (c !== col || fired) return real;
    const wrap = (q) => new Proxy(q, {get: (t, k) => {
      if (k === 'get') return async () => { const r = await t.get(); if (!fired) { fired = true; fn(); } return r; };
      if (k === 'where' || k === 'limit' || k === 'orderBy') return (...a) => wrap(t[k](...a));
      return typeof t[k] === 'function' ? t[k].bind(t) : t[k];
    }});
    return wrap(real);
  };
  return () => { F.db.collectionGroup = orig; };
}

test('R5 조회 뒤 다른 관리자 저장(rev 2→3) 경합 — 자동 마감은 fresh 3 + 1 = 4', async () => {
  base();
  F.put('tos/t1', {businessId: 'b1', status: 'ACTIVE', type: 'short', totalRequired: 4});
  F.put('tos/t1/slots/s1', {status: 'open', editRevision: 2, date: new Ts(NOW + 24 * H),
    workDetails: [WD({applicationDeadline: new Ts(NOW - H)}), WD({wdId: 'wd2', workType: '분류'})]});
  const restore = afterFirstGroupQuery('slots', () => {
    F.put('tos/t1/slots/s1', Object.assign(F.get('tos/t1/slots/s1'), {editRevision: 3}));
  });
  try { await X.processSlotWorkDetailExpiry(nowTs()); } finally { restore(); }
  const s = F.get('tos/t1/slots/s1');
  assert.ok(s.workDetails[0].closedAt);
  assert.strictEqual(s.editRevision, OLD ? 3 : 4, '조회 스냅샷 값으로 올리면 3 — 관리자 버전 폼이 마감을 덮는다');
});

// 거래 안 no-op — 바깥 조회는 마감 대상으로 봤지만 거래 전에 다른 실행이 이미 닫았다 → 쓰기 0 · 버전 그대로.
function afterFirstCollectionQuery(col, fn) {
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

test('R6 거래 안 no-op(다른 실행이 먼저 닫음) — 계약 공고 쓰기 0 · 버전 그대로', async () => {
  base();
  F.put('tos/t1', {businessId: 'b1', status: 'ACTIVE', type: 'contract', editRevision: 5,
    workDetails: [WD({applicationDeadline: new Ts(NOW - H)}), WD({wdId: 'wd2', workType: '분류'})]});
  const restore = afterFirstCollectionQuery('tos', () => {
    const t = F.get('tos/t1');
    t.workDetails[0] = Object.assign({}, t.workDetails[0], {closedAt: new Ts(NOW - 1000), closedReason: 'TIME_EXPIRED'});
    F.put('tos/t1', t);
  });
  const n = writesTo('tos/t1');
  try { await X.processWorkDetailExpiry(nowTs()); } finally { restore(); }
  assert.strictEqual(F.get('tos/t1').editRevision, 5);
  assert.strictEqual(writesTo('tos/t1'), n, '거래 안 no-op 은 쓰기 0');
});

test('R7 거래 안 no-op(다른 실행이 먼저 닫음) — 슬롯 쓰기 0 · 버전 그대로', async () => {
  base();
  F.put('tos/t1', {businessId: 'b1', status: 'ACTIVE', type: 'short', totalRequired: 4});
  F.put('tos/t1/slots/s1', {status: 'open', editRevision: 2, date: new Ts(NOW + 24 * H),
    workDetails: [WD({applicationDeadline: new Ts(NOW - H)}), WD({wdId: 'wd2', workType: '분류'})]});
  const restore = afterFirstGroupQuery('slots', () => {
    const s = F.get('tos/t1/slots/s1');
    s.workDetails[0] = Object.assign({}, s.workDetails[0], {closedAt: new Ts(NOW - 1000), closedReason: 'TIME_EXPIRED'});
    F.put('tos/t1/slots/s1', s);
  });
  const n = writesTo('tos/t1/slots/s1');
  try { await X.processSlotWorkDetailExpiry(nowTs()); } finally { restore(); }
  assert.strictEqual(F.get('tos/t1/slots/s1').editRevision, 2);
  assert.strictEqual(writesTo('tos/t1/slots/s1'), n);
});
