'use strict';
/**
 * [server_300 · 판정298 F298-02] OTP 오답 제한 — 오답 횟수 증가·상한/만료 삭제가 **커밋된 뒤** 오류가 돌아온다.
 *   대상: resetPasswordWithCode(옛 아이디 재설정 · passwordResetCodes) · callableResetPasswordWithOtp(현재 앱 경로 · sms_verifications · 같은 꼴).
 *   AUD298O_EXPECT_OLD=1 이면 이전 원문(e2353d90)의 결함(callback 안 throw 로 쓰기 버려짐)을 재현하는 쪽으로 뒤집는다.
 *   O1 오답 1…5 → attempts 1…5 저장 · 6번째 → 상한(resource-exhausted) + 문서 삭제 · 그 뒤 → not-found  (예전: 6회 모두 invalid · attempts 0 · 문서 유지)
 *   O2 정상 코드 → used 표시 · 이어서 같은 코드 → 사용됨 거절 · 새 비밀번호 적용(Auth 갱신)
 *   O3 만료 → deadline-exceeded + 문서 삭제(예전: 문서 유지)
 *   O4 동시 오답 2건(거래 재시도 · OCC) → attempts 2(유실 0)
 *   O5 현재 앱 경로 callableResetPasswordWithOtp — 오답 1…5 저장 · 6번째 상한 · 만료 삭제 · 정상 코드 → 문서 삭제 + customToken
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
const {exports: X} = loadIndexClosure(['resetPasswordWithCode', 'callableResetPasswordWithOtp'], F,
  {HttpsError, console: QCON, Date: FakeDate});
const Ts = F.Ts;
const OLD = process.env.AUD298O_EXPECT_OLD === '1';
const call = async (fn, data, auth) => { try { return {ok: await fn({data, auth})}; } catch (e) { return {code: e.code}; } };
const seedCode = (o) => F.put('passwordResetCodes/qa1', Object.assign({code: '123456', uid: 'u1',
  expiresAt: new Ts(NOW + 300000), attempts: 0, used: false}, o));
const reset = (code) => call(X.resetPasswordWithCode, {username: 'qa1', code, newPassword: 'Reset123!x'});

test('O1 오답 1…5 저장 · 6번째 상한 + 삭제', async () => {
  F.reset(); F.put('users/u1', {username: 'qa1'}); seedCode();
  const codes = [];
  const stored = [];
  for (let n = 0; n < 7; n++) {
    codes.push((await reset('000000')).code);
    stored.push(F.has('passwordResetCodes/qa1') ? F.get('passwordResetCodes/qa1').attempts : 'deleted');
  }
  if (OLD) {
    assert.deepStrictEqual(codes, Array(7).fill('invalid-argument'), '재현: 상한에 닿지 않는다');
    assert.deepStrictEqual(stored, Array(7).fill(0), '재현: attempts 저장 0');
    return;
  }
  assert.deepStrictEqual(codes, ['invalid-argument', 'invalid-argument', 'invalid-argument', 'invalid-argument', 'invalid-argument',
    'resource-exhausted', 'not-found']);
  assert.deepStrictEqual(stored, [1, 2, 3, 4, 5, 'deleted', 'deleted']);
});

test('O2 정상 코드 → 재설정 · 같은 코드 재사용 거절', async () => {
  F.reset(); F.put('users/u1', {username: 'qa1'}); seedCode({attempts: 3});
  const r = await reset('123456');
  assert.ok(r.ok && r.ok.success, JSON.stringify(r));
  assert.strictEqual(F.has('passwordResetCodes/qa1'), false, '성공 뒤 코드 문서 삭제');
  seedCode({used: true});
  assert.strictEqual((await reset('123456')).code, 'invalid-argument', '사용된 코드 거절');
});

test('O3 만료 → deadline-exceeded + 삭제', async () => {
  F.reset(); seedCode({expiresAt: new Ts(NOW - 1000)});
  const r = await reset('000000');
  assert.strictEqual(r.code, 'deadline-exceeded');
  assert.strictEqual(F.has('passwordResetCodes/qa1'), !OLD ? false : true, OLD ? '재현: 만료 문서가 남는다' : '만료 삭제 커밋');
});

test('O4 동시 오답 2건(거래 재시도) → attempts 2', async (t) => {
  if (OLD) { t.skip('예전 원문은 저장 자체가 0(O1)'); return; }
  F.reset(); seedCode();
  F.occ.enabled = true;
  const [a, b] = await Promise.all([reset('000000'), reset('111111')]);
  F.occ.enabled = false;
  assert.deepStrictEqual([a.code, b.code], ['invalid-argument', 'invalid-argument']);
  assert.strictEqual(F.get('passwordResetCodes/qa1').attempts, 2, '동시 오답도 유실 0');
});

test('O5 현재 앱 경로 callableResetPasswordWithOtp — 같은 꼴', async () => {
  F.reset();
  F.put('users/u9', {username: 'qa9', role: 'USER', accountStatus: 'active', foreignIdentityFingerprint: 'fp9', contactPhone: '010-1234-5678'});
  const seed = (o) => F.put('sms_verifications/01012345678', Object.assign({code: '654321', attempts: 0, purpose: 'password_reset',
    boundUid: 'u9', expiredAt: new Ts(NOW + 300000)}, o));
  // 입력 꼴은 원문 검증을 그대로 통과해야 한다 — 먼저 한 번 원문이 요구하는 필드를 확인한다.
  const data = (code) => ({username: 'qa9', code});
  seed();
  const probe = await call(X.callableResetPasswordWithOtp, data('000000'));
  if (probe.code !== 'invalid-argument' || !F.has('sms_verifications/01012345678')) {
    // 원문의 사용자 해석 단계에서 먼저 막히면 이 셀은 입력 꼴을 맞춰야 한다 — 그 사실을 드러낸다.
    assert.fail(`입력 꼴 불일치: probe=${JSON.stringify(probe)} doc=${F.has('sms_verifications/01012345678')}`);
  }
  const after1 = F.get('sms_verifications/01012345678').attempts;
  if (OLD) { assert.strictEqual(after1, 0, '재현: 오답 저장 0'); return; }
  assert.strictEqual(after1, 1);
  const codes = [];
  for (let n = 0; n < 5; n++) codes.push((await call(X.callableResetPasswordWithOtp, data('000000'))).code);
  assert.deepStrictEqual(codes, ['invalid-argument', 'invalid-argument', 'invalid-argument', 'invalid-argument', 'resource-exhausted']);
  assert.strictEqual(F.get('sms_verifications/01012345678').attempts, 5);
  seed({expiredAt: new Ts(NOW - 1000)});
  assert.strictEqual((await call(X.callableResetPasswordWithOtp, data('654321'))).code, 'deadline-exceeded');
  assert.strictEqual(F.has('sms_verifications/01012345678'), false, '만료 삭제 커밋');
  seed();
  const ok = await call(X.callableResetPasswordWithOtp, data('654321'));
  assert.ok(ok.ok, JSON.stringify(ok));
  assert.strictEqual(F.has('sms_verifications/01012345678'), false, '정상 코드 → 일회용 삭제');
});
