'use strict';
/**
 * [판정296 정책 P3 · §2-6 C1] 사업장 보관(운영 종료) cascade — 취소한 관계의 열람권을 취소와 같은 거래에서 영속 회수 ·
 *   이전 실행이 남긴(비활성) 관계의 approved 열람권도 재개 회수 · 취소의 실제 좌석 기여 반납.
 *   S296A_EXPECT_OLD=1 이면 이전 원문에서 결함(열람권 approved 잔존 · 좌석 미반납)을 재현한다.
 */
const {test} = require('node:test');
const assert = require('assert');
const {createFakeFirestore} = require('./consent_r4d_fakestore');
const {loadIndexClosure} = require('./auth_kakao_index_harness');

const OLD = process.env.S296A_EXPECT_OLD === '1';
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
const {exports: X} = loadIndexClosure(['srvRunBusinessArchiveCascade'], F, {HttpsError, console: QCON, Date: FakeDate});
const Ts = F.Ts;

function base() {
  F.reset();
  F.put('businesses/b1', {name: '평택', ownerId: 'own1', adminIds: ['own1'], deactivatedAt: new Ts(NOW - 1000), isApproved: true});
  F.put('tos/t1', {businessId: 'b1', status: 'CLOSED', type: 'flex', totalConfirmed: 2, totalPending: 0});
  F.put('tos/t1/slots/s1', {status: 'full', confirmedCount: 2, workDetails: [{wdId: 'wd1', requiredCount: 2}],
    workDetailCounts: {wd1: {confirmedCount: 2, pendingCount: 0}}});
  F.put('applications/a1', {uid: 'w1', businessId: 'b1', toId: 't1', slotId: 's1', wdId: 'wd1', status: 'CONFIRMED',
    type: 'short', workDate: new Ts(NOW + 5 * DAY), startTime: '09:00', endTime: '18:00'});
  F.put('idCardAccessRequests/auto_a1', {applicationId: 'a1', targetUserId: 'w1', requesterBusinessId: 'b1', status: 'approved'});
  F.put('idCardAccessRequests/m1', {applicationId: 'a1', targetUserId: 'w1', requesterId: 'own1', requesterBusinessId: 'b1',
    status: 'approved'});
  // 이전 실행이 취소했지만 열람권이 남은 관계
  F.put('applications/a0', {uid: 'w0', businessId: 'b1', toId: 't1', status: 'CANCELED', cancelReason: 'BUSINESS_DEACTIVATED',
    businessEndNotifiedAt: new Ts(NOW - 500)});
  F.put('idCardAccessRequests/auto_a0', {applicationId: 'a0', targetUserId: 'w0', requesterBusinessId: 'b1', status: 'approved'});
}

test('A1 보관 취소 — 같은 거래에서 열람권(자동·개인) 회수 + 좌석 반납', async () => {
  base();
  await X.srvRunBusinessArchiveCascade('b1');
  assert.strictEqual(F.get('applications/a1').status, 'CANCELED');
  if (OLD) {
    assert.strictEqual(F.get('idCardAccessRequests/m1').status, 'approved', '음성 대조: 이전 원문은 개인 열람권을 남긴다');
    return;
  }
  assert.strictEqual(F.get('idCardAccessRequests/auto_a1').status, 'revoked');
  assert.strictEqual(F.get('idCardAccessRequests/m1').status, 'revoked');
  const c = F.W.commits.find((x) => x.writes.some((w) => w.path === 'applications/a1' && w.data && w.data.status === 'CANCELED'));
  assert.ok(c.writes.some((w) => w.path === 'idCardAccessRequests/m1'), '같은 커밋');
  assert.strictEqual(F.get('tos/t1/slots/s1').confirmedCount, 1);
  assert.strictEqual(F.get('tos/t1').totalConfirmed, 1);
});

test('A2 재개 — 이전 실행이 취소한 비활성 관계의 남은 approved 열람권도 회수 · 되살아난 관계는 건드리지 않는다', async () => {
  base();
  // 옛 표식(cancelReason)이 남았지만 지금은 확정 · 실근무로 보존되는 관계
  F.put('applications/a9', {uid: 'w9', businessId: 'b1', toId: 't1', status: 'CONFIRMED', cancelReason: 'BUSINESS_DEACTIVATED',
    workDate: new Ts(NOW - DAY)});
  F.put('attendance/a9_20261126', {applicationId: 'a9', userId: 'w9', businessId: 'b1', checkIn: new Ts(NOW - DAY), wageStatus: 'confirmed'});
  F.put('idCardAccessRequests/auto_a9', {applicationId: 'a9', targetUserId: 'w9', requesterBusinessId: 'b1', status: 'approved'});
  await X.srvRunBusinessArchiveCascade('b1');
  if (OLD) { assert.strictEqual(F.get('idCardAccessRequests/auto_a0').status, 'approved', '음성 대조'); return; }
  assert.strictEqual(F.get('idCardAccessRequests/auto_a0').status, 'revoked');
  assert.strictEqual(F.get('idCardAccessRequests/auto_a9').status, 'approved', '활성 관계의 열람권은 이 단계가 회수하지 않는다');
});

test('A3 실근무 보존 — 시작한 근무는 취소·회수·반납 0(동치)', async () => {
  base();
  F.put('applications/a1', Object.assign(F.get('applications/a1'), {workDate: new Ts(NOW - DAY)}));
  F.put('attendance/a1_20261126', {applicationId: 'a1', userId: 'w1', businessId: 'b1', checkIn: new Ts(NOW - DAY), wageStatus: 'confirmed'});
  await X.srvRunBusinessArchiveCascade('b1');
  assert.strictEqual(F.get('applications/a1').status, 'CONFIRMED');
  assert.strictEqual(F.get('idCardAccessRequests/m1').status, 'approved');
  assert.strictEqual(F.get('tos/t1/slots/s1').confirmedCount, 2);
});
