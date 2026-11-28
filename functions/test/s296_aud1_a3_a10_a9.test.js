'use strict';
/**
 * [AUD-1 A3 · A10 · A9] 재현(aud1_repro2 레시피) → 수리 확인.
 *   A3 UpdateTO 허용 목록 · 점/슬래시 키 · 서버 소유 필드 거절 · CreateTO 서버 소유 필드 제거
 *   A10 BatchSetNoShow 근태 id 경로 — 저장 workDate·지원서로 거래 안 판정 시각 재계산
 *   A9 BatchCheckIn id 없는 경로 — calculated·기존 checkIn 거절 · 같은 근태 중복 항목 충돌 거절
 *   S296A1_EXPECT_OLD=1 이면 이전 원문에서 결함을 재현한다.
 */
const {test} = require('node:test');
const assert = require('assert');
const {createFakeFirestore} = require('./consent_r4d_fakestore');
const {loadIndexClosure} = require('./auth_kakao_index_harness');

const OLD = process.env.S296A1_EXPECT_OLD === '1';
const RealDate = Date;
const NOW = RealDate.UTC(2026, 10, 27, 3, 0); // KST 2026-11-27 12:00
const KST = 9 * 3600000;
const KST_MID = (d) => RealDate.UTC(2026, 10, d) - KST;
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
const {exports: X} = loadIndexClosure(['callableBatchCheckIn', 'callableBatchSetNoShow', 'callableUpdateTO'],
  F, {HttpsError, console: QCON, Date: FakeDate});
const Ts = F.Ts;
const go = async (fn, data, uid = 'own1') => {
  try { return {ok: true, r: await fn({data, auth: {uid, token: {}}})}; } catch (e) { return {ok: false, e}; }
};
const code = (o) => o.e && ((o.e.details && o.e.details.code) || o.e.code);

function base() {
  F.reset();
  F.put('users/own1', {role: 'BUSINESS_ADMIN', accountStatus: 'active', name: '사장', businessId: 'b1'});
  F.put('users/w1', {role: 'USER', accountStatus: 'active', name: '근로자'});
  F.put('businesses/b1', {name: '평택', ownerId: 'own1', adminIds: ['own1'], isApproved: true});
}
const toFixture = () => F.put('tos/t3', {businessId: 'b1', businessName: '평택', creatorUID: 'own1', title: '물류', status: 'ACTIVE',
  isPublished: true, type: 'flex', totalRequired: 5, totalConfirmed: 2, totalPending: 1, editRevision: 3, postingCapacityScopeKey: 'b1:own1',
  workTypeConfirmedCounts: {wd1: 2}, workDetails: [{wdId: 'wd1', workType: '포장', startTime: '09:00', endTime: '18:00', requiredCount: 5}]});
const updTO = (updates) => go(X.callableUpdateTO, {toId: 't3', expectedEditRevision: 3, updates});

test('A3 서버 소유 필드·점 키 주입 — 거절(TO_FIELD_NOT_ALLOWED) · 저장 0', async () => {
  for (const u of [{postingCapacityScopeKey: null}, {'workTypeConfirmedCounts.wd1': -50}, {businessName: '다른 사업장'},
    {type: 'long_term'}, {isDeleted: true}, {totalConfirmed: 0}, {'a/b': 1}]) {
    base(); toFixture();
    const o = await updTO(Object.assign({title: '물류(수정)'}, u));
    const t = F.get('tos/t3');
    if (OLD) continue;
    assert.strictEqual(code(o), 'TO_FIELD_NOT_ALLOWED', JSON.stringify(u));
    assert.strictEqual(t.title, '물류', '저장 0');
    assert.strictEqual(t.postingCapacityScopeKey, 'b1:own1');
    assert.deepStrictEqual(t.workTypeConfirmedCounts, {wd1: 2});
  }
  if (OLD) {
    base(); toFixture();
    const o = await updTO({postingCapacityScopeKey: null, 'workTypeConfirmedCounts.wd1': -50, businessName: '다른', type: 'long_term'});
    assert.ok(o.ok, '음성 대조: 이전 원문은 받는다');
    assert.strictEqual(F.get('tos/t3').workTypeConfirmedCounts.wd1, -50, '음성 대조: 점 키로 서버 카운터 위조');
  }
});

test('A3b 정상 동치 — 제목·설명 수정은 저장된다', async () => {
  base(); toFixture();
  const o = await updTO({title: '물류(수정)', description: '설명', hoursBeforeStart: 2});
  assert.ok(o.ok, o.e && o.e.message);
  assert.strictEqual(F.get('tos/t3').title, '물류(수정)');
});

function noshowFixture() {
  base();
  F.put('applications/a2', {uid: 'w1', businessId: 'b1', status: 'CONFIRMED', type: 'short', startTime: '18:00', endTime: '22:00',
    selectedWorkType: '분류'});
  F.put('attendance/att_today', {applicationId: 'a2', userId: 'w1', businessId: 'b1', workDate: new Ts(KST_MID(27)),
    status: 'scheduled', wageStatus: 'pending', checkIn: null});
}
const noshow = (workDateMs, extra = {}) => go(X.callableBatchSetNoShow, {businessId: 'b1', entries: [Object.assign({
  attendanceId: 'att_today', applicationId: 'a2', workDateMs, userId: 'w1', businessName: '평택', workType: '분류'}, extra)]});

test('A10 근태 id 경로 — 오늘(18:00 시작 전) 근태에 workDateMs=어제 → 노쇼 0원 확정하지 않는다', async () => {
  noshowFixture();
  const o = await noshow(KST_MID(26));
  const a = F.get('attendance/att_today');
  if (OLD) { assert.strictEqual(a.status, 'NO_SHOW', '음성 대조: 이전 원문은 시작 전 노쇼 0원'); return; }
  assert.ok(o.ok, o.e && o.e.message);
  assert.strictEqual(a.status, 'scheduled');
  assert.strictEqual(a.finalWage, undefined);
});

test('A10b 클라 applicationId 가 저장 근태와 다르면 건너뜀 · 정상(어제 시작 지난 근태)은 처리', async () => {
  if (OLD) return;
  noshowFixture();
  await noshow(KST_MID(26), {applicationId: 'zz'});
  assert.strictEqual(F.get('attendance/att_today').status, 'scheduled');
  base();
  F.put('applications/a2', {uid: 'w1', businessId: 'b1', status: 'CONFIRMED', type: 'short', startTime: '09:00', endTime: '12:00',
    selectedWorkType: '분류'});
  F.put('attendance/att_y', {applicationId: 'a2', userId: 'w1', businessId: 'b1', workDate: new Ts(KST_MID(26)),
    status: 'scheduled', wageStatus: 'pending', checkIn: null});
  const o = await go(X.callableBatchSetNoShow, {businessId: 'b1', entries: [{attendanceId: 'att_y', applicationId: 'a2',
    workDateMs: KST_MID(26), userId: 'w1', businessName: '평택', workType: '분류'}]});
  assert.ok(o.ok, o.e && o.e.message);
  assert.strictEqual(F.get('attendance/att_y').status, 'NO_SHOW');
});

function checkinFixture(att) {
  base();
  F.put('tos/t1', {businessId: 'b1', status: 'ACTIVE'});
  F.put('tos/t1/slots/s1', {date: new Ts(KST_MID(25)), status: 'open'});
  F.put('applications/a1', {uid: 'w1', businessId: 'b1', status: 'CONFIRMED', type: 'short', toId: 't1', slotId: 's1',
    startTime: '09:00', endTime: '18:00', selectedWorkType: '분류', wage: 10000, wageType: 'hourly'});
  if (att) F.put('attendance/a1_20261125', Object.assign({applicationId: 'a1', userId: 'w1', businessId: 'b1',
    workDate: new Ts(KST_MID(25))}, att));
}
const ci = (entries) => go(X.callableBatchCheckIn, {businessId: 'b1', entries});
const ent = (o = {}) => Object.assign({applicationId: 'a1', workDateMs: KST_MID(25), userId: 'w1', businessName: '평택',
  workType: '분류', status: 'late', checkInMs: KST_MID(25) + 11 * 3600000}, o);

test('A9 id 없는 재전송 — calculated 근태를 pending 으로 되돌리지 않는다 · 기존 checkIn 덮기 0', async () => {
  checkinFixture({checkIn: new Ts(KST_MID(25) + 9 * 3600000), checkOut: new Ts(KST_MID(25) + 18 * 3600000), status: 'present',
    wageStatus: 'calculated', finalWage: 80000, wageDetail: {netWage: 80000, totalAmount: 80000}});
  await ci([ent()]);
  const a = F.get('attendance/a1_20261125');
  if (OLD) { assert.strictEqual(a.wageStatus, 'pending', '음성 대조: 이전 원문은 calculated → pending'); return; }
  assert.strictEqual(a.wageStatus, 'calculated');
  assert.strictEqual(a.checkIn.toMillis(), KST_MID(25) + 9 * 3600000);
  checkinFixture({checkIn: new Ts(KST_MID(25) + 9 * 3600000), status: 'present', wageStatus: 'pending'});
  const o = await ci([ent()]);
  assert.strictEqual(F.get('attendance/a1_20261125').checkIn.toMillis(), KST_MID(25) + 9 * 3600000, 'pending 이어도 기존 출근 덮기 0');
  assert.ok((o.r.failures || []).some((f) => f.reason === 'alreadyCheckedIn'), JSON.stringify(o.r));
});

test('A9b 같은 근태 두 항목 — 내용이 다르면 쓰기 전 거절 · 같으면 하나로 · 정상 신규 출근 동치', async () => {
  checkinFixture(null);
  let o = await ci([ent(), ent({checkInMs: KST_MID(25) + 10 * 3600000})]);
  if (!OLD) {
    assert.strictEqual(code(o), 'CHECKIN_ENTRY_CONFLICT');
    assert.strictEqual(F.get('attendance/a1_20261125'), undefined);
  }
  checkinFixture(null);
  o = await ci([ent(), ent()]);
  assert.ok(o.ok, o.e && o.e.message);
  assert.strictEqual(F.get('attendance/a1_20261125').checkIn.toMillis(), KST_MID(25) + 11 * 3600000);
});
