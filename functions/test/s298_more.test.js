'use strict';
/**
 * [server_298] limit 전수 2차(권한/상태 판정 보조) · AUD-5 ①-1 FCM recipientUid.
 *   S298_EXPECT_OLD=1 이면 이전 원문에서 결함을 재현한다.
 */
const {test} = require('node:test');
const assert = require('assert');
const {createFakeFirestore} = require('./consent_r4d_fakestore');
const {loadIndexClosure} = require('./auth_kakao_index_harness');

const OLD = process.env.S298_EXPECT_OLD === '1';
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
let sent = [];
F.admin.messaging = () => ({sendEachForMulticast: async (m) => { sent.push(m); return {responses: m.tokens.map(() => ({success: true})), successCount: m.tokens.length, failureCount: 0}; }});
const {exports: X} = loadIndexClosure(['srvIssuedContractExists', 'srvLiveContractRefsFor', 'onNotificationCreated'], F,
  {HttpsError, console: QCON, Date: FakeDate});
const Ts = F.Ts;

test('L1 발급 계약 존재 — 무효 계약 6건이 앞서도 뒤의 살아 있는 계약을 본다(중복 발급 0)', async () => {
  F.reset();
  for (let i = 0; i < 6; i++) F.put(`employment_contracts/a${i}`, {businessId: 'b1', applicationId: 'ap1', status: 'voided'});
  F.put('employment_contracts/z9', {businessId: 'b1', applicationId: 'ap1', status: 'pending_worker'});
  const r = await X.srvIssuedContractExists('ap1', 'b1');
  if (OLD) { assert.strictEqual(r, false, '음성 대조: 이전 원문은 첫 5건만 보고 없다고 한다'); return; }
  assert.strictEqual(r, true);
});

test('L2 살아 있는 계약 ref — 지난 계약 21건 뒤의 살아 있는 계약도 포함', async () => {
  F.reset();
  for (let i = 0; i < 21; i++) F.put(`employment_contracts/a${String(i).padStart(2, '0')}`, {businessId: 'b1', applicationId: 'ap1', status: 'voided'});
  F.put('employment_contracts/z9', {businessId: 'b1', applicationId: 'ap1', status: 'pending_worker'});
  const refs = await X.srvLiveContractRefsFor('ap1', 'b1');
  const ids = refs.map((r) => r.id);
  if (OLD) { assert.ok(!ids.includes('z9'), '음성 대조'); return; }
  assert.ok(ids.includes('z9'));
});

test('N1 FCM data 에 recipientUid(알림 문서 경로 uid · data 의 같은 키보다 서버 값이 이긴다)', async () => {
  F.reset(); sent = [];
  F.put('users/u1', {fcmTokens: ['tok1']});
  F.put('users/u1/notifications/n1', {title: 't', body: 'b', type: 'workCanceled', data: {businessId: 'b1', recipientUid: 'spoof'}});
  const snap = {data: () => F.get('users/u1/notifications/n1')};
  await X.onNotificationCreated({time: new RealDate(NOW).toISOString(), params: {userId: 'u1', notificationId: 'n1'}, data: snap});
  assert.strictEqual(sent.length, 1);
  if (OLD) { assert.strictEqual(sent[0].data.recipientUid, 'spoof', '음성 대조: 이전 원문은 서버 수신자 키가 없다'); return; }
  assert.strictEqual(sent[0].data.recipientUid, 'u1');
  assert.strictEqual(sent[0].data.businessId, 'b1', '기존 키 그대로');
});
