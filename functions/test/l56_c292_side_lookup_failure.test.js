'use strict';
/**
 * [C292-01 · 판정292] 알림 수신자·이름을 거래 직전에 정하는 부수 조회가 실패해도 본 행동은 성공하고 알림만 빠진다.
 *
 *   RequestResignation · RequestInterimSettlement 각각에 세 가지 실패를 LOCAL 로 넣는다:
 *     ① 사업장 문서 읽기 실패 ② 근로자 이름(users) 읽기 실패(퇴사만) ③ 부관리자 조회(users 질의) 실패
 *   대사: 응답(성공/오류) · 도메인 상태(지원서 resignStatus · 정산 요청 문서) · 알림 작업 수신자 집합.
 *   L56C292_EXPECT_OLD=1 이면 이전 원문(7063aca1)에서 ① 이 **요청 전체 실패**였던 것을 확인한다(음성 대조).
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
const {exports: X} = loadIndexClosure(['callableRequestResignation', 'callableRequestInterimSettlement'], F,
  {HttpsError, console: QCON, Date: FakeDate});
const call = (fn, data, uid) => fn({data, auth: {uid, token: {}}});
const Ts = F.Ts;
const DAY = 86400000;
const OLD = process.env.L56C292_EXPECT_OLD === '1';

function seed() {
  F.reset();
  F.put('users/own1', {role: 'BUSINESS_ADMIN', accountStatus: 'active', name: '사장'});
  F.put('users/sub1', {role: 'USER', accountStatus: 'active', name: '부', subAdminBusinessIds: ['b1']});
  F.put('businesses/b1/members/sub1', {uid: 'sub1', permissions: {canManageWorkers: true, canManageWage: true}});
  F.put('users/w1', {role: 'USER', accountStatus: 'active', name: '근로자'});
  F.put('businesses/b1', {name: '평택', ownerId: 'own1', adminIds: ['own1']});
  F.put('applications/a1', {uid: 'w1', businessId: 'b1', businessName: '평택', status: 'CONFIRMED', type: 'long_term',
    workEndDate: new Ts(NOW + 40 * DAY)});
  F.put('attendance/at1', {userId: 'w1', businessId: 'b1', applicationId: 'a1', wageStatus: 'confirmed', finalWage: 96000,
    wageDetail: {netWage: 93000}, workDate: new Ts(NOW - 7 * DAY)});
}
const jobs = () => [...F.STORE.keys()].filter((k) => k.startsWith('notification_jobs/')).map((k) => F.get(k));
const recipients = () => jobs().map((j) => j.recipientUid).sort();

// 실패 주입
function failDocOnce(path) {
  let n = 1;
  F.hooks.afterGet = (p, txId) => { if (txId == null && p === path && n-- > 0) throw new Error('UNAVAILABLE ' + path); };
}
function failUsersQuery() {
  const orig = F.db.collection;
  F.db.collection = (c) => {
    const real = orig(c);
    if (c !== 'users') return real;
    return new Proxy(real, {get: (t, k) => (k === 'where' ?
      () => ({get: async () => { throw new Error('UNAVAILABLE users query'); }}) : (typeof t[k] === 'function' ? t[k].bind(t) : t[k]))});
  };
  return () => { F.db.collection = orig; };
}
async function run(fnCall) {
  try { return {ok: true, r: await fnCall()}; } catch (e) { return {ok: false, code: e.code ?? null, message: String(e.message)}; }
}
const RESIGN = () => call(X.callableRequestResignation, {applicationId: 'a1', resignDateIso: new RealDate(NOW + 14 * DAY).toISOString()}, 'w1');
const INTERIM = () => call(X.callableRequestInterimSettlement, {businessId: 'b1', applicationId: 'a1', businessName: '평택',
  workerName: '근로자', periodStart: '2026-11-17', periodEnd: '2026-11-24', attendanceIds: ['at1'], requestedAmount: 96000, netAmount: 93000}, 'w1');
const interimDocs = () => [...F.STORE.keys()].filter((k) => k.startsWith('interim_settlement_requests/'));

test('R0 퇴사 요청 정상 — 성공 · PENDING · 관리자+부관리자 작업', async () => {
  seed();
  const o = await run(RESIGN);
  assert.ok(o.ok, o.message);
  assert.strictEqual(F.get('applications/a1').resignStatus, 'PENDING');
  assert.deepStrictEqual(recipients(), ['own1', 'sub1']);
});

test('R1 사업장 읽기 실패 — 성공 · PENDING · 관리자 알림만 빠짐(부관리자는 감)', async () => {
  seed();
  failDocOnce('businesses/b1');
  const o = await run(RESIGN);
  F.hooks.afterGet = null;
  if (OLD) {
    assert.strictEqual(o.ok, false, '음성 대조: 예전 원문은 요청 전체가 실패해야 한다');
    assert.strictEqual(F.get('applications/a1').resignStatus, undefined, '예전: 도메인 변경 0');
    return;
  }
  assert.ok(o.ok, o.message);
  assert.strictEqual(F.get('applications/a1').resignStatus, 'PENDING');
  assert.deepStrictEqual(recipients(), ['sub1']);
});

test('R2 근로자 이름 읽기 실패 — 성공 · 알림 본문은 기본 호칭', async () => {
  seed();
  failDocOnce('users/w1');
  const o = await run(RESIGN);
  F.hooks.afterGet = null;
  assert.ok(o.ok, o.message);
  assert.strictEqual(F.get('applications/a1').resignStatus, 'PENDING');
  if (OLD) return;
  assert.deepStrictEqual(recipients(), ['own1', 'sub1']);
  assert.ok(jobs().every((j) => j.payload.body.startsWith('근무자님이 퇴사를 요청했습니다.')));
});

test('R3 부관리자 조회 실패 — 성공 · 관리자에게만', async () => {
  seed();
  const restore = failUsersQuery();
  const o = await run(RESIGN);
  restore();
  assert.ok(o.ok, o.message);
  assert.strictEqual(F.get('applications/a1').resignStatus, 'PENDING');
  if (OLD) return;
  assert.deepStrictEqual(recipients(), ['own1']);
});

test('I0 중간정산 요청 정상 — 성공 · 요청 문서 1 · 관리자+부관리자 작업', async () => {
  seed();
  const o = await run(INTERIM);
  assert.ok(o.ok, o.message);
  assert.strictEqual(interimDocs().length, 1);
  assert.deepStrictEqual(recipients(), ['own1', 'sub1']);
});

test('I1 사업장 읽기 실패 — 성공 · 요청 문서 1 · 부관리자에게만', async () => {
  seed();
  failDocOnce('businesses/b1');
  const o = await run(INTERIM);
  F.hooks.afterGet = null;
  if (OLD) {
    assert.strictEqual(o.ok, false, '음성 대조: 예전 원문은 요청 전체가 실패해야 한다');
    assert.strictEqual(interimDocs().length, 0);
    return;
  }
  assert.ok(o.ok, o.message);
  assert.strictEqual(interimDocs().length, 1);
  assert.deepStrictEqual(recipients(), ['sub1']);
});

test('I3 부관리자 조회 실패 — 성공 · 관리자에게만', async () => {
  seed();
  const restore = failUsersQuery();
  const o = await run(INTERIM);
  restore();
  assert.ok(o.ok, o.message);
  assert.strictEqual(interimDocs().length, 1);
  if (OLD) return;
  assert.deepStrictEqual(recipients(), ['own1']);
});
