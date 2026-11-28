'use strict';
/**
 * [AUD-7 M-2 · server_298] 비밀번호 재사용 이력 — users 문서(기기로 내려감) sha256 → 서버 전용 password_history/{uid} scrypt.
 *   옛 sha256 항목은 재사용 비교에 쓰고 재설정 성공 때 users 문서에서 지운다 · 탈퇴 개인 정리에 포함.
 *   S298_EXPECT_OLD=1 이면 이전 원문에서 결함(users 문서에 빠른 해시 이력)을 재현한다.
 */
const {test} = require('node:test');
const assert = require('assert');
const crypto = require('crypto');
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
const {exports: X} = loadIndexClosure(['resetPasswordWithCode', 'srvCleanupDeletionOwnedPersonal'], F,
  {HttpsError, console: QCON, Date: FakeDate});
const Ts = F.Ts;
const sha = (pw, uid) => crypto.createHash('sha256').update(pw + uid).digest('hex');
const reset = async (pw) => {
  F.put('passwordResetCodes/qa1', {code: '123456', uid: 'u1', expiresAt: new Ts(NOW + 300000), attempts: 0, used: false});
  try { return {ok: true, r: await X.resetPasswordWithCode({data: {username: 'qa1', code: '123456', newPassword: pw}})}; } catch (e) { return {ok: false, e}; }
};
function base() {
  F.reset();
  F.put('users/u1', {role: 'USER', username: 'qa1', name: 'QA', passwordHistory: [sha('Old1234!a', 'u1')]});
}

test('PH1 옛 sha256 이력과 같은 비밀번호 — 재사용 거절(의미 유지)', async () => {
  base();
  const o = await reset('Old1234!a');
  assert.ok(!o.ok);
  assert.strictEqual(o.e.code, 'already-exists');
});

test('PH2 재설정 성공 — users 문서에 해시 이력 0 · 서버 전용 문서에 scrypt(salt) 1건', async () => {
  base();
  const o = await reset('New1234!b');
  assert.ok(o.ok, o.e && o.e.message);
  const u = F.get('users/u1');
  if (OLD) {
    assert.ok(Array.isArray(u.passwordHistory) && u.passwordHistory.includes(sha('New1234!b', 'u1')),
      '음성 대조: 이전 원문은 본인 users 문서에 sha256 이력을 쌓는다');
    return;
  }
  assert.strictEqual(u.passwordHistory, undefined);
  const h = F.get('password_history/u1');
  assert.strictEqual(h.entries.length, 1);
  assert.ok(/^[0-9a-f]{32}$/.test(h.entries[0].s) && /^[0-9a-f]{64}$/.test(h.entries[0].h));
  assert.notStrictEqual(h.entries[0].h, sha('New1234!b', 'u1'));
});

test('PH3 새 형식 이력으로도 재사용 거절 · 5개까지만 유지', async () => {
  if (OLD) return;
  base();
  assert.ok((await reset('New1234!b')).ok);
  const o = await reset('New1234!b');
  assert.strictEqual(o.e.code, 'already-exists');
  for (const p of ['P2345678!a', 'P3345678!a', 'P4345678!a', 'P5345678!a', 'P6345678!a']) assert.ok((await reset(p)).ok, p);
  assert.strictEqual(F.get('password_history/u1').entries.length, 5);
});

test('PH4 탈퇴 개인 정리 — 서버 전용 이력 문서 삭제', async () => {
  if (OLD) return;
  base();
  assert.ok((await reset('New1234!b')).ok);
  await X.srvCleanupDeletionOwnedPersonal('u1');
  assert.strictEqual(F.get('password_history/u1'), undefined);
});
