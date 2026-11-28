'use strict';
/**
 * [판정293 · impl_32 §5] callableMarkTransferredBatch 입력 id 정규화 · 중복 제거.
 *   같은 attendanceId 를 한 호출에 두 번 보내면 이전 원문(72bd9f71)은 같은 스냅샷을 두 번 보고
 *   tx.update 2 · 금액 감사 2 · processed 2 · 알림 2 로 처리했다.
 *   새 원문: 입력 순서 유지(첫 위치) · 고유 id 기준 응답·카운트·감사 · 알림도 근태당 1.
 *   XFER_DUP_EXPECT_OLD=1 이면 이전 원문 사본에서 이중 처리를 재현한다(음성 대조).
 */
const {test} = require('node:test');
const assert = require('assert');
const {createFakeFirestore} = require('./consent_r4d_fakestore');
const {loadIndexClosure} = require('./auth_kakao_index_harness');

const OLD = process.env.XFER_DUP_EXPECT_OLD === '1';
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
const {exports: X} = loadIndexClosure(['callableMarkTransferredBatch'], F, {HttpsError, console: QCON, Date: FakeDate});
const Ts = F.Ts;
const DAY = 86400000;
const call = (data) => X.callableMarkTransferredBatch({data, auth: {uid: 'own1', token: {}}});
const run = async (data) => { try { return {ok: true, r: await call(data)}; } catch (e) { return {ok: false, e}; } };

const ACCT = {wageAccountSnapshotVersion: 1, wageAccountBankName: '국민', wageAccountNumberEncrypted: 'enc',
  wageAccountHolder: '근로자', wageAccountSnapshotAt: new Ts(NOW - 5 * DAY),
  wageAccountSourceBankAccountVersion: 1, wageAccountSourceBankbookDocumentVersion: 1};
function base() {
  F.reset();
  F.put('users/own1', {role: 'BUSINESS_ADMIN', accountStatus: 'active', name: '사장'});
  F.put('businesses/b1', {name: '평택', ownerId: 'own1', adminIds: ['own1']});
  for (const w of ['w1', 'w2']) {
    F.put(`users/${w}`, {role: 'USER', accountStatus: 'active', name: '근로자', bankAccountVersion: 1, bankbookDocumentVersion: 1});
  }
}
function att(id, o = {}) {
  F.put(`attendance/${id}`, Object.assign({userId: 'w1', businessId: 'b1', applicationId: 'a1', wageStatus: 'confirmed',
    finalWage: 96000, workDate: new Ts(NOW - 7 * DAY), status: 'completed'}, ACCT, o));
}
const audits = (id) => Object.keys(F.dump()).filter((k) => k.startsWith(`attendance/${id}/`)).length;
const notifs = (uid) => Object.keys(F.dump()).filter((k) => k.startsWith(`users/${uid}/notifications/`)).length;
const attWrites = (id) => F.W.commits.flatMap((c) => c.writes).filter((w) => w.path === `attendance/${id}`).length;
const nf = (attendanceId, userId = 'w1') => ({userId, workerName: '근로자', businessName: '평택', businessId: 'b1',
  finalWage: 96000, attendanceId});

test('X1 같은 id 두 번 — 한 번만 이체 · 감사 1 · processed 1 · 알림 1', async () => {
  base(); att('t1');
  const o = await run({businessId: 'b1', attendanceIds: ['t1', 't1'], notifications: [nf('t1'), nf('t1')]});
  assert.ok(o.ok, o.e && o.e.message);
  assert.strictEqual(F.get('attendance/t1').wageStatus, 'transferred');
  if (OLD) {
    assert.strictEqual(o.r.processed, 2, '음성 대조: 이전 원문은 processed 2');
    assert.strictEqual(audits('t1'), 2, '음성 대조: 이전 원문은 금액 감사 2건');
    assert.strictEqual(attWrites('t1'), 2, '음성 대조: 이전 원문은 같은 근태 update 2회');
    assert.strictEqual(notifs('w1'), 2, '음성 대조: 이전 원문은 알림 2건');
    return;
  }
  assert.strictEqual(o.r.processed, 1);
  assert.strictEqual(audits('t1'), 1);
  assert.strictEqual(attWrites('t1'), 1);
  assert.strictEqual(notifs('w1'), 1);
  assert.deepStrictEqual(o.r.alreadyTransferred, []);
  assert.deepStrictEqual(o.r.skipped, []);
});

test('X2 혼합 중복(이체·이미·제외) — 응답 배열은 고유 id · 첫 위치 순서', async () => {
  base(); att('a'); att('b', {wageStatus: 'transferred'}); att('c', {wageStatus: 'pending'}); att('d', {userId: 'w2'});
  const o = await run({businessId: 'b1', attendanceIds: ['c', 'a', 'b', 'a', 'c', 'd', 'b', 'd']});
  assert.ok(o.ok, o.e && o.e.message);
  if (OLD) {
    assert.strictEqual(o.r.processed, 4, '음성 대조: a·d 두 번씩');
    assert.deepStrictEqual(o.r.skipped, ['c', 'c']);
    assert.deepStrictEqual(o.r.alreadyTransferred, ['b', 'b']);
    return;
  }
  assert.strictEqual(o.r.processed, 2);
  assert.deepStrictEqual(o.r.skipped, ['c']);
  assert.deepStrictEqual(o.r.alreadyTransferred, ['b']);
  assert.deepStrictEqual(Object.keys(o.r.blocked), ['c']);
  assert.strictEqual(audits('a'), 1);
  assert.strictEqual(audits('d'), 1);
});

test('X3 중복 없는 입력 — 이전과 같은 결과(동치)', async () => {
  base(); att('a'); att('b', {wageStatus: 'transferred'}); att('c', {wageStatus: 'pending'});
  const o = await run({businessId: 'b1', attendanceIds: ['c', 'a', 'b'], notifications: [nf('a')]});
  assert.ok(o.ok, o.e && o.e.message);
  assert.strictEqual(o.r.processed, 1);
  assert.deepStrictEqual(o.r.skipped, ['c']);
  assert.deepStrictEqual(o.r.alreadyTransferred, ['b']);
  assert.strictEqual(audits('a'), 1);
  assert.strictEqual(notifs('w1'), 1);
});

test('X4 형식이 틀린 id(빈 값 · 문자열 아님 · 경로 문자) — 쓰기 전 invalid-argument', async () => {
  for (const bad of [[''], [7], ['a/b/c'], ['..'], [null]]) {
    base(); att('a');
    const o = await run({businessId: 'b1', attendanceIds: ['a'].concat(bad)});
    if (OLD) continue; // 이전 원문은 경로에 따라 내부 오류 또는 다른 문서 경로 — 여기서 고정하지 않는다
    assert.ok(!o.ok, `거절되어야 한다: ${JSON.stringify(bad)}`);
    assert.strictEqual(o.e.code, 'invalid-argument');
    assert.strictEqual(F.get('attendance/a').wageStatus, 'confirmed', '쓰기 0');
  }
});

test('X5 상한은 받은 그대로 센다 — 201개(중복 포함)면 지금처럼 거절', async () => {
  base(); att('a');
  const ids = Array.from({length: 201}, () => 'a');
  const o = await run({businessId: 'b1', attendanceIds: ids});
  assert.ok(!o.ok);
  assert.strictEqual(o.e.code, 'invalid-argument');
});

test('X6 알림 — 같은 근태 알림 중복은 1건 · attendanceId 없는 구 앱 항목은 지금처럼 그대로', async () => {
  base(); att('a'); att('d', {userId: 'w2'});
  const legacy = {userId: 'w2', workerName: '근로자', businessName: '평택', businessId: 'b1', finalWage: 1};
  const o = await run({businessId: 'b1', attendanceIds: ['a', 'd'], notifications: [nf('a'), nf('a'), legacy, legacy]});
  assert.ok(o.ok, o.e && o.e.message);
  if (OLD) { assert.strictEqual(notifs('w1'), 2); return; }
  assert.strictEqual(notifs('w1'), 1);
  assert.strictEqual(notifs('w2'), 2, '구 앱 항목(근태 id 없음)은 중복 판정 근거가 없어 지금처럼 보낸다');
});

test('X7 입력 순서 유지 — 중복은 첫 위치 기준', async () => {
  base(); att('p1', {wageStatus: 'pending'}); att('p2', {wageStatus: 'pending'});
  const o = await run({businessId: 'b1', attendanceIds: ['p2', 'p1', 'p2']});
  assert.ok(o.ok, o.e && o.e.message);
  if (OLD) { assert.deepStrictEqual(o.r.skipped, ['p2', 'p1', 'p2']); return; }
  assert.deepStrictEqual(o.r.skipped, ['p2', 'p1']);
});
