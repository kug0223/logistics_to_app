'use strict';
/**
 * [판정296 §2-6 C1 · P4] 계약 무효화(두 callable 공용 helper)의 실제 좌석 기여 원자 반납 · syncTOStats retry/영구 오류 기록.
 * [판정297 §2 기존 오염 retry] callableRetryVoidFailedApplications — contractId 만 받아 서버가 대상 파생·검증(F296-56 CH3).
 *   S296V_EXPECT_OLD=1 이면 이전 원문에서 결함(좌석 미반납)을 재현한다(retry callable 은 이전 원문에 없다).
 */
const {test} = require('node:test');
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const {createFakeFirestore} = require('./consent_r4d_fakestore');
const {loadIndexClosure} = require('./auth_kakao_index_harness');

const OLD = process.env.S296V_EXPECT_OLD === '1';
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
const ROOTS = OLD ? ['callableVoidContractWithApplications', 'callableVoidContract'] :
  ['callableVoidContractWithApplications', 'callableVoidContract', 'callableRetryVoidFailedApplications', 'syncTOStats'];
const {exports: X} = loadIndexClosure(ROOTS, F, {HttpsError, console: QCON, Date: FakeDate});
const Ts = F.Ts;
const go = async (fn, data, uid = 'own1') => {
  try { return {ok: true, r: await fn({data, auth: {uid, token: {}}})}; } catch (e) { return {ok: false, e}; }
};
const code = (o) => o.e && ((o.e.details && o.e.details.code) || o.e.code);

function base() {
  F.reset();
  F.put('users/own1', {role: 'BUSINESS_ADMIN', accountStatus: 'active', name: '사장', businessId: 'b1'});
  F.put('users/sub0', {role: 'USER', name: '부', subAdminBusinessIds: ['b1']});
  F.put('businesses/b1/members/sub0', {uid: 'sub0', permissions: {canManageContract: false}});
  F.put('businesses/b1', {name: '평택', ownerId: 'own1', adminIds: ['own1'], isApproved: true});
  F.put('tos/t1', {businessId: 'b1', status: 'FULL', type: 'flex', totalConfirmed: 3, totalPending: 0});
  F.put('tos/t1/slots/s1', {status: 'full', confirmedCount: 3, workDetails: [{wdId: 'wd1', requiredCount: 3}],
    workDetailCounts: {wd1: {confirmedCount: 3, pendingCount: 0}}});
  const app = (id, uid, o = {}) => F.put(`applications/${id}`, Object.assign({uid, businessId: 'b1', toId: 't1', slotId: 's1',
    wdId: 'wd1', status: 'CONFIRMED', workDate: new Ts(NOW + 3 * DAY)}, o));
  app('a1', 'w1'); app('a2', 'w1'); app('x9', 'w9');
}
const contract = (o = {}) => F.put('employment_contracts/c1', Object.assign({businessId: 'b1', workerId: 'w1', status: 'pending_worker',
  applicationIds: ['a1', 'a2'], applicationId: 'a1'}, o));

test('V1 무효화 — 취소한 확정 지원서 2건의 좌석을 같은 거래에서 반납(공고·슬롯·업무)', async () => {
  base(); contract();
  const o = await go(X.callableVoidContractWithApplications, {contractId: 'c1'});
  assert.ok(o.ok, o.e && o.e.message);
  assert.strictEqual(F.get('applications/a1').status, 'CANCELED');
  if (OLD) {
    assert.strictEqual(F.get('tos/t1/slots/s1').confirmedCount, 3, '음성 대조: 이전 원문은 좌석을 반납하지 않는다(재집계 트리거에만 맡김)');
    return;
  }
  const c = F.W.commits.find((x) => x.writes.some((w) => w.path === 'employment_contracts/c1' && w.data && w.data.status === 'voided'));
  assert.ok(c.writes.some((w) => w.path === 'tos/t1/slots/s1'), '같은 커밋');
  assert.strictEqual(F.get('tos/t1/slots/s1').confirmedCount, 1);
  assert.strictEqual(F.get('tos/t1/slots/s1').workDetailCounts.wd1.confirmedCount, 1);
  assert.strictEqual(F.get('tos/t1').totalConfirmed, 1);
  assert.ok(F.get('applications/a1').confirmedDecrementedAt);
});

test('V2 이미 반납한 좌석(staffingReleasedAt)은 다시 줄이지 않는다 · 카운터는 0 아래로 안 간다 · callableVoidContract 도 같은 helper', async () => {
  base(); contract();
  F.put('applications/a2', Object.assign(F.get('applications/a2'), {staffingReleasedAt: new Ts(NOW - 1000)}));
  F.put('tos/t1', Object.assign(F.get('tos/t1'), {totalConfirmed: 0}));
  const o = await go(X.callableVoidContract, {contractId: 'c1'});
  assert.ok(o.ok, o.e && o.e.message);
  if (OLD) return;
  assert.strictEqual(F.get('tos/t1/slots/s1').confirmedCount, 2, 'a1 한 자리만');
  assert.strictEqual(F.get('tos/t1').totalConfirmed, 0, '0 아래로 안 간다');
  assert.strictEqual(F.get('applications/a2').confirmedDecrementedAt, undefined);
});

test('V3 정상 동치 — 이미 voided 면 멱등(카운터 변화 0) · 완료 계약은 거절', async () => {
  base(); contract({status: 'voided'});
  let o = await go(X.callableVoidContractWithApplications, {contractId: 'c1'});
  assert.ok(o.ok);
  assert.strictEqual(F.get('tos/t1/slots/s1').confirmedCount, 3);
  base(); contract({status: 'completed'});
  o = await go(X.callableVoidContractWithApplications, {contractId: 'c1'});
  assert.ok(!o.ok);
  assert.strictEqual(F.get('tos/t1/slots/s1').confirmedCount, 3);
});

test('S1 syncTOStats — retry:true 선언 · 일시 오류는 다시 던짐 · 영구 오류는 기록 뒤 ACK', async () => {
  if (OLD) return;
  const src = fs.readFileSync(path.join(__dirname, '..', 'src', 'index.ts'), 'utf8');
  assert.ok(/export const syncTOStats = onDocumentWritten\(\s*\{document: "applications\/\{applicationId\}", region: "asia-northeast3", retry: true\}/.test(src));
  base();
  const ev = {params: {applicationId: 'a1'}, data: {before: {data: () => ({status: 'CONFIRMED', toId: 't1', slotId: 's1'})},
    after: {data: () => ({status: 'CANCELED', toId: 't1', slotId: 's1'})}}};
  const orig = F.db.collection;
  F.db.collection = (c) => { if (c === 'tos') { const e = new Error('14 UNAVAILABLE'); e.code = 14; throw e; } return orig(c); };
  await assert.rejects(() => X.syncTOStats(ev), /UNAVAILABLE/);
  F.db.collection = (c) => { if (c === 'tos') throw new TypeError('bad data'); return orig(c); };
  await X.syncTOStats(ev);
  F.db.collection = orig;
  const rec = F.get('stats_sync_failures/t1__s1');
  assert.ok(rec && /bad data/.test(rec.error));
  assert.strictEqual(rec.applicationId, 'a1');
});

// ── retry callable ──
const retry = (uid = 'own1') => go(X.callableRetryVoidFailedApplications, {contractId: 'c1'}, uid);

test('RT1 CH3 — 실패 목록에 주입된 다른 근로자 지원서(x9 · 계약 연결 0)는 취소하지 않는다 · 연결된 a2 만 취소', async () => {
  if (OLD) return;
  base(); contract({status: 'voided', voidFailedAppIds: ['x9', 'a2']});
  F.put('applications/a1', Object.assign(F.get('applications/a1'), {status: 'CANCELED'}));
  const o = await retry();
  assert.ok(o.ok, o.e && o.e.message);
  assert.deepStrictEqual(o.r.canceled, ['a2']);
  assert.deepStrictEqual(o.r.kept, [{applicationId: 'x9', reason: 'NOT_LINKED'}]);
  assert.strictEqual(F.get('applications/x9').status, 'CONFIRMED', '다른 근로자의 확정 근무 보존');
  assert.strictEqual(F.get('applications/a2').status, 'CANCELED');
  assert.deepStrictEqual(F.get('employment_contracts/c1').voidFailedAppIds, ['x9'], '성공 항목만 제거');
  assert.strictEqual(F.get('tos/t1/slots/s1').confirmedCount, 2, '좌석 반납(C1 helper)');
});

test('RT2 연결돼 있어도 근로자·사업장이 다르면 보류 · 이미 비활성은 목록에서만 뺀다 · 실근무는 보존', async () => {
  if (OLD) return;
  base();
  F.put('applications/a3', {uid: 'w9', businessId: 'b1', toId: 't1', slotId: 's1', wdId: 'wd1', status: 'CONFIRMED'});
  F.put('applications/a4', {uid: 'w1', businessId: 'b2', toId: 't1', slotId: 's1', wdId: 'wd1', status: 'CONFIRMED'});
  F.put('applications/a5', {uid: 'w1', businessId: 'b1', toId: 't1', status: 'CANCELED'});
  contract({status: 'voided', applicationIds: ['a1', 'a3', 'a4', 'a5'], voidFailedAppIds: ['a3', 'a4', 'a5', 'a1']});
  F.put('attendance/a1_20261130', {applicationId: 'a1', userId: 'w1', businessId: 'b1', checkIn: new Ts(NOW - 3600000)});
  const o = await retry();
  assert.ok(o.ok, o.e && o.e.message);
  const kept = Object.fromEntries(o.r.kept.map((k) => [k.applicationId, k.reason]));
  assert.strictEqual(kept.a3, 'WORKER_MISMATCH');
  assert.strictEqual(kept.a4, 'BUSINESS_MISMATCH');
  assert.deepStrictEqual(o.r.cleared, ['a5']);
  assert.ok(kept.a1 === 'ACTUAL_WORK', JSON.stringify(o.r));
  assert.strictEqual(F.get('applications/a1').status, 'CONFIRMED');
  assert.strictEqual(F.get('applications/a3').status, 'CONFIRMED');
  assert.deepStrictEqual(F.get('employment_contracts/c1').voidFailedAppIds.sort(), ['a1', 'a3', 'a4']);
});

test('RT3 권한 — canManageContract 없는 서브관리자 거절 · 무효 아닌 계약 거절 · 재실행 멱등', async () => {
  if (OLD) return;
  base(); contract({status: 'voided', voidFailedAppIds: ['a2']});
  let o = await retry('sub0');
  assert.strictEqual(o.e.code, 'permission-denied');
  assert.strictEqual(F.get('applications/a2').status, 'CONFIRMED');
  base(); contract({voidFailedAppIds: ['a2']});
  o = await retry();
  assert.strictEqual(code(o), 'CONTRACT_NOT_VOIDED');
  base(); contract({status: 'voided', voidFailedAppIds: ['a2']});
  o = await retry();
  assert.deepStrictEqual(o.r.canceled, ['a2']);
  const before = F.get('tos/t1/slots/s1').confirmedCount;
  o = await retry();
  assert.ok(o.ok);
  assert.deepStrictEqual(o.r.canceled, []);
  assert.strictEqual(F.get('tos/t1/slots/s1').confirmedCount, before, '두 번째 실행은 변화 0');
});

test('RT4 거래 사이 경합 — 실패 목록에서 이미 빠졌거나(다른 재처리) 계약 연결이 바뀌면 CHANGED/NOT_LINKED 로 쓰기 0', async () => {
  if (OLD) return;
  base(); contract({status: 'voided', voidFailedAppIds: ['a2']});
  let armed = true;
  F.hooks.afterGet = (p, txId) => {
    if (armed && txId == null && p === 'applications/a2') {
      armed = false;
      F.put('employment_contracts/c1', Object.assign(F.get('employment_contracts/c1'), {voidFailedAppIds: []}));
    }
  };
  const o = await retry();
  F.hooks.afterGet = null;
  assert.ok(o.ok);
  assert.deepStrictEqual(o.r.kept, [{applicationId: 'a2', reason: 'CHANGED'}]);
  assert.strictEqual(F.get('applications/a2').status, 'CONFIRMED');
});

test('RT5 CH3/CH3b 반례(rules_297 chain 꼴) — 주입된 무관 지원서(같은 사업장 a2 · 소유자의 다른 사업장 b9 지원서) 모두 보존', async () => {
  if (OLD) return;
  base();
  F.put('businesses/b9', {name: '안성', ownerId: 'own1', adminIds: ['own1'], isApproved: true}); // 소유자의 다른 사업장
  F.put('applications/v2', {uid: 'victim', businessId: 'b1', toId: 't1', status: 'CONFIRMED', workDate: new Ts(NOW + 5 * DAY)});
  F.put('applications/v9', {uid: 'victim', businessId: 'b9', toId: 't9', status: 'CONFIRMED', workDate: new Ts(NOW + 5 * DAY)});
  contract({status: 'voided', applicationIds: ['a1'], voidFailedAppIds: ['v2', 'v9']});
  let o = await retry();
  assert.ok(o.ok, o.e && o.e.message);
  assert.deepStrictEqual(o.r.kept.map((k) => k.reason), ['NOT_LINKED', 'NOT_LINKED']);
  assert.strictEqual(F.get('applications/v2').status, 'CONFIRMED');
  assert.strictEqual(F.get('applications/v9').status, 'CONFIRMED');
  // 연결 목록에까지 들어간(직접 쓰기 오염) 다른 사업장 지원서도 사업장 대조로 보존
  base();
  F.put('applications/v9', {uid: 'w1', businessId: 'b9', toId: 't9', status: 'CONFIRMED', workDate: new Ts(NOW + 5 * DAY)});
  contract({status: 'voided', applicationIds: ['a1', 'v9'], voidFailedAppIds: ['v9']});
  o = await retry();
  assert.deepStrictEqual(o.r.kept, [{applicationId: 'v9', reason: 'BUSINESS_MISMATCH'}]);
  assert.strictEqual(F.get('applications/v9').status, 'CONFIRMED');
});
