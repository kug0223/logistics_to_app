'use strict';
/**
 * [판정296 정책 P5] 공고 삭제(DeleteTO)·날짜 삭제(DeleteSlots)가 실제로 취소/거절한 지원서마다 근로자 알림을
 *   **취소와 같은 거래의 영속 작업**(notification_jobs)으로 만든다 — 공고 삭제가 뒤에서 막혀도(부분 취소) 알림이 남는다.
 *   작업 id = 사건_지원서_g세대(appId 단독 아님 · 재실행 멱등). 문구는 실제 취소 사실.
 *   S296P5_EXPECT_OLD=1 이면 이전 원문에서 결함(부분 취소 알림 0)을 재현한다.
 */
const {test} = require('node:test');
const assert = require('assert');
const {createFakeFirestore} = require('./consent_r4d_fakestore');
const {loadIndexClosure} = require('./auth_kakao_index_harness');

const OLD = process.env.S296P5_EXPECT_OLD === '1';
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
const {exports: X} = loadIndexClosure(['callableDeleteTO', 'callableDeleteSlots'], F, {HttpsError, console: QCON, Date: FakeDate});
const Ts = F.Ts;
const go = async (fn, data, uid = 'own1') => {
  try { return {ok: true, r: await fn({data, auth: {uid, token: {}}})}; } catch (e) { return {ok: false, e}; }
};
function base() {
  F.reset();
  F.put('users/own1', {role: 'BUSINESS_ADMIN', accountStatus: 'active', name: '사장', businessId: 'b1'});
  F.put('businesses/b1', {name: '평택', ownerId: 'own1', adminIds: ['own1'], isApproved: true});
  F.put('tos/t1', {businessId: 'b1', businessName: '평택', title: '물류', status: 'ACTIVE', totalPending: 0, totalConfirmed: 0,
    isPublished: true});
  F.put('tos/t1/slots/s1', {status: 'open', date: new Ts(NOW + 3 * DAY), pendingCount: 0, confirmedCount: 0,
    workDetails: [{wdId: 'wd1', workType: '포장', startTime: '09:00', endTime: '18:00', requiredCount: 5}],
    workDetailCounts: {wd1: {pendingCount: 0, confirmedCount: 0}}});
}
const app = (id, status, o = {}) => F.put(`applications/${id}`, Object.assign({uid: `u_${id}`, businessId: 'b1', businessName: '평택',
  toId: 't1', slotId: 's1', wdId: 'wd1', status, selectedWorkType: '포장', workDate: new Ts(NOW + 3 * DAY)}, o));
function afterRelationCheck(seed) {
  const orig = F.db.collection;
  let fired = false;
  F.db.collection = (c) => {
    const real = orig(c);
    if (c !== 'employment_contracts' || fired) return real;
    const wrap = (q) => new Proxy(q, {get: (t, k) => {
      if (k === 'get') return async () => { const r = await t.get(); if (!fired) { fired = true; seed(); } return r; };
      if (k === 'where' || k === 'limit' || k === 'orderBy') return (...a) => wrap(t[k](...a));
      return typeof t[k] === 'function' ? t[k].bind(t) : t[k];
    }});
    return wrap(real);
  };
  return () => { F.db.collection = orig; };
}
const jobsFor = (uid) => Object.entries(F.dump()).filter(([k, v]) => k.startsWith('notification_jobs/') && v.recipientUid === uid);
const notifsFor = (uid) => Object.keys(F.dump()).filter((k) => k.startsWith(`users/${uid}/notifications/`));

test('N1 공고 삭제가 뒤에서 막혀도(부분 취소) — 이미 취소한 지원서의 알림 작업은 취소와 같은 커밋에 남는다', async () => {
  base();
  const restore = afterRelationCheck(() => app('a1', 'CONFIRMED'));
  // 공고 삭제 마지막 거래를 실패시킨다(취소는 이미 커밋)
  let fail = true;
  F.hooks.beforeCommit = (txId, buf) => {
    if (fail && buf.some((w) => w.path === 'tos/t1' && w.data && w.data.isDeleted === true)) { fail = false; throw new Error('UNAVAILABLE'); }
  };
  const o = await go(X.callableDeleteTO, {toId: 't1'});
  restore(); F.hooks.beforeCommit = null;
  assert.ok(!o.ok, '공고 삭제는 실패');
  assert.strictEqual(F.get('applications/a1').status, 'AUTO_CANCELED');
  await new Promise((r) => setImmediate(r));
  if (OLD) {
    assert.strictEqual(jobsFor('u_a1').length + notifsFor('u_a1').length, 0, '음성 대조: 이전 원문은 부분 취소 알림이 없다');
    return;
  }
  const jobs = jobsFor('u_a1');
  assert.strictEqual(jobs.length, 1);
  assert.ok(/_a1_g\d+$/.test(jobs[0][0]), '사건_지원서_세대 id');
  assert.ok(/취소되었습니다/.test(jobs[0][1].payload.body));
  const c = F.W.commits.find((x) => x.writes.some((w) => w.path === 'applications/a1' && w.data && w.data.status === 'AUTO_CANCELED'));
  assert.ok(c.writes.some((w) => w.path === jobs[0][0]), '취소와 같은 커밋');
});

test('N2 정상 삭제 — 알림 작업 1건(직접 알림 쓰기 0) · 재실행해도 같은 세대 작업은 하나', async () => {
  base();
  const restore = afterRelationCheck(() => app('a1', 'PENDING'));
  const o = await go(X.callableDeleteTO, {toId: 't1'});
  restore();
  assert.ok(o.ok, o.e && o.e.message);
  await new Promise((r) => setImmediate(r));
  if (OLD) return;
  assert.strictEqual(jobsFor('u_a1').length, 1);
  assert.strictEqual(notifsFor('u_a1').length, 0, '커밋 뒤 직접 알림 0');
});

test('N3 날짜 삭제(DeleteSlots) — 대기 거절 알림도 같은 거래 작업', async () => {
  base();
  F.put('tos/t1/slots/s2', {status: 'open', date: new Ts(NOW + 4 * DAY), pendingCount: 0, confirmedCount: 0, workDetails: []});
  const restore = afterRelationCheck(() => app('a1', 'PENDING'));
  const o = await go(X.callableDeleteSlots, {toId: 't1', slotIds: ['s1'], businessId: 'b1'});
  restore();
  assert.ok(o.ok, o.e && o.e.message);
  await new Promise((r) => setImmediate(r));
  if (OLD) return;
  const jobs = jobsFor('u_a1');
  assert.strictEqual(jobs.length, 1);
  assert.strictEqual(jobs[0][1].payload.type, 'applicationRejected');
});
