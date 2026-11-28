'use strict';
/**
 * [AUD-9 S1 · rules_303 §3 발견] 슬롯 업무 마감 스케줄러(processSlotWorkDetailExpiry)의 공고 id 는 **경로로만**.
 *   예전 원문은 슬롯 **데이터** toId 를 경로보다 먼저 썼다. rules 는 공고 관리자의 슬롯 create/update 에서 toId 를 묶지 않는다 →
 *   사업장 A 관리자가 자기 공고 아래 슬롯(같은 slotId · 만료된 업무)에 toId = B 공고를 적으면, 스케줄러 1회로
 *   B 공고의 같은 slotId·같은 업무 PENDING 지원서가 AUTO_CANCELED 되고 B 공고 totalRequired 가 줄고 B 공고 상태 동기화가 돈다.
 *   P1 교차 사업장 변조 → B 지원서·B 정원 무변경(수리) / 예전 원문은 B 취소·감소(AUD9S1_EXPECT_OLD=1 · 재현).
 *   P2 대조 — 데이터 toId 가 경로와 같은 정상 슬롯은 예전과 같이 자기 공고 대기 지원을 취소·정원 감소.
 *   P3 대조 — 데이터 toId 없는 슬롯(현재 앱 꼴)은 경로 공고로 처리(예전과 같음).
 *   P4 변조 슬롯 자체는 자기 경로 공고(A) 기준으로 닫히고 A 정원만 준다(수리 뒤).
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
const {exports: X} = loadIndexClosure(['processSlotWorkDetailExpiry'], F, {HttpsError, console: QCON, Date: FakeDate});
const Ts = F.Ts;
const H = 3600000;
const OLD = process.env.AUD9S1_EXPECT_OLD === '1';
const SID = 'd20261128';
const WD = (o) => Object.assign({wdId: 'wd1', workType: '포장', startTime: '09:00', endTime: '18:00', requiredCount: 2,
  wage: 12000, wageType: 'hourly'}, o);
const app = (toId, bid, uid) => ({toId, slotId: SID, businessId: bid, businessName: bid, uid, userId: uid,
  selectedWorkType: '포장', wdId: 'wd1', status: 'PENDING'});

function base() {
  F.reset();
  F.put('businesses/bA', {name: 'A', ownerId: 'oA', adminIds: ['oA'], isApproved: true});
  F.put('businesses/bB', {name: 'B', ownerId: 'oB', adminIds: ['oB'], isApproved: true});
  F.put('users/wB', {role: 'USER', accountStatus: 'active'});
  F.put('users/wA', {role: 'USER', accountStatus: 'active'});
  // B 공고: 같은 날짜 슬롯 · 업무 마감 전(아직 모집 중)
  F.put('tos/tB', {businessId: 'bB', status: 'ACTIVE', type: 'short', totalRequired: 2});
  F.put(`tos/tB/slots/${SID}`, {status: 'open', date: new Ts(NOW + 24 * H), workDetails: [WD({applicationDeadline: new Ts(NOW + 5 * H)})]});
  F.put('applications/aB1', app('tB', 'bB', 'wB'));
}

test('P1 교차 사업장 — A 슬롯 데이터 toId=B 공고 → B 대기 지원·B 정원은 그대로', async () => {
  base();
  F.put('tos/tA', {businessId: 'bA', status: 'ACTIVE', type: 'short', totalRequired: 2});
  F.put(`tos/tA/slots/${SID}`, {toId: 'tB', status: 'open', date: new Ts(NOW + 24 * H),
    workDetails: [WD({applicationDeadline: new Ts(NOW - H)})]});
  await X.processSlotWorkDetailExpiry(new Ts(NOW));
  const aB = F.get('applications/aB1');
  const tB = F.get('tos/tB');
  const tA = F.get('tos/tA');
  if (OLD) {
    assert.strictEqual(aB.status, 'AUTO_CANCELED', '재현: 다른 사업장의 대기 지원이 자동 취소된다');
    assert.strictEqual(tB.totalRequired, 0, '재현: 다른 사업장 공고 정원이 준다');
    assert.strictEqual(tA.totalRequired, 2, '재현: 정작 자기 공고 정원은 그대로');
    return;
  }
  assert.strictEqual(aB.status, 'PENDING', 'B 지원서 무변경');
  assert.strictEqual(tB.totalRequired, 2, 'B 정원 무변경');
  assert.strictEqual(F.get(`tos/tB/slots/${SID}`).workDetails[0].closedAt, undefined, 'B 슬롯 무변경');
  // P4 — 변조 슬롯은 자기 경로 공고 기준으로 닫힌다
  assert.ok(F.get(`tos/tA/slots/${SID}`).workDetails[0].closedAt, 'A 슬롯 업무는 닫힌다');
  assert.strictEqual(tA.totalRequired, 0, 'A 정원만 준다');
});

test('P2 대조 — 데이터 toId 가 경로와 같으면 자기 공고 대기 지원 취소 · 정원 감소(예전과 같음)', async () => {
  base();
  F.put('tos/tA', {businessId: 'bA', status: 'ACTIVE', type: 'short', totalRequired: 2});
  F.put(`tos/tA/slots/${SID}`, {toId: 'tA', status: 'open', date: new Ts(NOW + 24 * H),
    workDetails: [WD({applicationDeadline: new Ts(NOW - H)})]});
  F.put('applications/aA1', app('tA', 'bA', 'wA'));
  await X.processSlotWorkDetailExpiry(new Ts(NOW));
  assert.strictEqual(F.get('applications/aA1').status, 'AUTO_CANCELED');
  assert.strictEqual(F.get('tos/tA').totalRequired, 0);
  assert.strictEqual(F.get('applications/aB1').status, 'PENDING');
  assert.strictEqual(F.get('tos/tB').totalRequired, 2);
});

test('P3 대조 — 데이터 toId 없는 슬롯은 경로 공고로 처리(예전과 같음)', async () => {
  base();
  F.put('tos/tA', {businessId: 'bA', status: 'ACTIVE', type: 'short', totalRequired: 2});
  F.put(`tos/tA/slots/${SID}`, {status: 'open', date: new Ts(NOW + 24 * H),
    workDetails: [WD({applicationDeadline: new Ts(NOW - H)})]});
  F.put('applications/aA1', app('tA', 'bA', 'wA'));
  await X.processSlotWorkDetailExpiry(new Ts(NOW));
  assert.strictEqual(F.get('applications/aA1').status, 'AUTO_CANCELED');
  assert.strictEqual(F.get('tos/tA').totalRequired, 0);
  assert.strictEqual(F.get('applications/aB1').status, 'PENDING');
});

test('P5 tos 아래가 아닌 slots 문서는 대상 아님(데이터 toId 가 B 라도 B 무변경)', async () => {
  base();
  F.put(`misc/m1/slots/${SID}`, {toId: 'tB', status: 'open', date: new Ts(NOW + 24 * H),
    workDetails: [WD({applicationDeadline: new Ts(NOW - H)})]});
  await X.processSlotWorkDetailExpiry(new Ts(NOW));
  if (OLD) {
    assert.strictEqual(F.get('applications/aB1').status, 'AUTO_CANCELED', '재현: 공고 밖 slots 문서도 데이터 toId 로 B 를 취소');
    return;
  }
  assert.strictEqual(F.get('applications/aB1').status, 'PENDING');
  assert.strictEqual(F.get('tos/tB').totalRequired, 2);
  assert.strictEqual(F.get(`misc/m1/slots/${SID}`).workDetails[0].closedAt, undefined, '공고 밖 문서는 건드리지 않는다');
});
