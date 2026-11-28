'use strict';
// [판정295 묶음 · AUD-2 K-1a/b · K-2 · G-2] AUD-2 재현 시험(aud2_tools/aud2_contract_residue.test.js) 재사용 — 수리 뒤 기대값(EXPECT_DEFECT 없음).
/**
 * [AUD-2] 미서명 계약 잔존 — 반례 재현(동결 원문 dbed3203 · D: 사본에서만 실행).
 *   K1a 현행 모양 계약(workerSignedAt 키 없음 · pending_worker)이 탈퇴 차단에 안 잡힘
 *   K1b 옛 모양(workerSignedAt:null · status "voided")은 서명 불가인데 영구 차단
 *   K1c 탈퇴 지원서 정리(callableDeleteAccountApplications) 뒤 pending_worker 계약 잔존
 *   K2  취소된 지원서의 pending_worker 계약을 근로자가 서명 → completed(지원서는 CANCELED 그대로)
 *   기대값은 '정책대로라면'이고, 실패(= 결함 재현)가 이 시험의 목적이다. EXPECT_DEFECT=1 이면 결함 존재를 단언한다.
 */
const {test} = require('node:test');
const assert = require('assert');
const {createFakeFirestore} = require('./consent_r4d_fakestore');
const {loadIndexClosure} = require('./auth_kakao_index_harness');

const DEFECT = process.env.EXPECT_DEFECT === '1';
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
// 서명 업로드용 storage — save/getMetadata/makePublic/getSignedUrl 만 흉내(바이트 저장 0)
const files = new Map();
const storage = {bucket: () => ({name: 'fake-bucket', file: (p) => ({
  name: p, metadata: {generation: '1'},
  save: async (buf) => { files.set(p, buf.length); },
  exists: async () => [files.has(p)],
  delete: async () => { files.delete(p); return []; },
  getMetadata: async () => [{generation: '1', md5Hash: 'x', size: files.get(p) ?? 0}],
  getSignedUrl: async () => ['https://fake/' + p],
  makePublic: async () => [],
  publicUrl: () => 'https://fake/' + p,
})})};
F.admin.storage = () => storage;
const {exports: X} = loadIndexClosure(['callableGetWithdrawBlockers', 'callableDeleteAccountApplications',
  'callableFinalizeWorkerSignature'], F, {HttpsError, console: QCON, Date: FakeDate});
const Ts = F.Ts;
const go = async (fn, data, uid, token = {}) => {
  try { return {ok: true, r: await fn({data, auth: {uid, token}})}; } catch (e) { return {ok: false, e}; }
};

function base() {
  F.reset();
  F.put('users/w1', {role: 'USER', accountStatus: 'active', name: '근로자'});
  F.put('users/own1', {role: 'BUSINESS_ADMIN', accountStatus: 'active', name: '사장', businessId: 'b1'});
  F.put('businesses/b1', {name: '평택', ownerId: 'own1', adminIds: ['own1'], isApproved: true});
  F.put('tos/t1', {businessId: 'b1', title: '물류', status: 'ACTIVE', totalPending: 0, totalConfirmed: 1});
}
// 서버가 만드는 모양(callableFinalizeEmployerSignature 새 계약 data) — workerSignedAt 키 없음
const serverContract = (id, appId, o = {}) => F.put(`employment_contracts/${id}`, Object.assign({
  applicationId: appId, applicationIds: [appId], businessId: 'b1', workerId: 'w1', toId: 't1',
  status: 'pending_worker', employerSignatureUrl: 'https://fake/e.png', employerSignatureStoragePath: 'contracts/x/e.png',
  employerSignedAt: new Ts(NOW - DAY), createdAt: new Ts(NOW - DAY),
  snapshot: {workerName: '근로자'}, articles: [],
}, o));
const unsignedBlock = (r) => ((r.hardBlocks || []).find((b) => b.type === 'UNSIGNED_CONTRACT') || {count: 0}).count;

test('K1a 현행 모양 pending_worker 계약은 탈퇴 차단에 잡혀야 한다', async () => {
  base();
  F.put('applications/a1', {uid: 'w1', businessId: 'b1', toId: 't1', status: 'CONTRACT_PENDING', workDate: new Ts(NOW + 3 * DAY)});
  serverContract('c1', 'a1');
  const o = await go(X.callableGetWithdrawBlockers, {}, 'w1', {role: 'USER'});
  assert.ok(o.ok, o.e && o.e.message);
  const n = unsignedBlock(o.r);
  if (DEFECT) assert.strictEqual(n, 0, '결함 재현: 미서명 계약 차단 0');
  else {
    // [판정296 정책 P2] 서명 강제 관문 제거 — 미서명 계약은 탈퇴를 막지 않고(탈퇴 취소 거래가 무효 + 사업주 알림) 경고로만 센다.
    //   K-1a 의 '현행 모양 계약을 센다' 는 그대로(경고 count ≥ 1).
    assert.strictEqual(n, 0, 'P2: 하드 차단 아님');
    const w = ((o.r.warnings || []).find((b) => b.type === 'UNSIGNED_CONTRACT') || {count: 0}).count;
    assert.ok(w >= 1, `미서명 계약 경고가 0 이다(UNSIGNED_CONTRACT=${w})`);
  }
});

test('K1b 서명 불가 상태(voided)는 탈퇴를 막지 않아야 한다(옛 모양 workerSignedAt:null)', async () => {
  base();
  serverContract('c2', 'a2', {status: 'voided', workerSignedAt: null, voidReason: 'X'});
  const o = await go(X.callableGetWithdrawBlockers, {}, 'w1', {role: 'USER'});
  assert.ok(o.ok, o.e && o.e.message);
  const n = unsignedBlock(o.r);
  if (DEFECT) assert.strictEqual(n, 1, '결함 재현: voided 가 차단으로 셈(제외 목록 "VOID" ≠ "voided")');
  else assert.strictEqual(n, 0, `voided 계약이 탈퇴를 막는다(UNSIGNED_CONTRACT=${n})`);
});

// K1c(탈퇴 정리의 계약 무효)는 정책 판정 대상이라 이 셀에서 수리하지 않는다 — server_295_impl.md 표(AUD-2 원본 시험에 남아 있다).

test('K2 취소된 지원서의 계약은 근로자 서명으로 completed 가 되면 안 된다', async () => {
  base();
  F.put('applications/a1', {uid: 'w1', businessId: 'b1', toId: 't1', status: 'CANCELED', cancelReason: 'ADMIN_CANCELED',
    workDate: new Ts(NOW + 3 * DAY)});
  serverContract('c1', 'a1');
  const png = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3]).toString('base64');
  const pdf = Buffer.from('%PDF-1.4 fake').toString('base64');
  const o = await go(X.callableFinalizeWorkerSignature, {contractId: 'c1', signatureBase64: png, pdfBase64: pdf}, 'w1', {role: 'USER'});
  const c = F.get('employment_contracts/c1'); const app = F.get('applications/a1');
  const note = `contract=${c.status} app=${app.status} call=${o.ok ? 'ok' : (o.e.code + ':' + o.e.message)}`;
  if (DEFECT) {
    assert.ok(o.ok, note);
    assert.strictEqual(c.status, 'completed', '결함 재현: ' + note);
    assert.strictEqual(app.status, 'CANCELED', note);
  } else {
    assert.notStrictEqual(c.status, 'completed', '취소된 근무의 계약이 서명 완료됨: ' + note);
  }
});

// G-2 — 정리 callable 이 지원서 상태를 보지 않는다(확정 중인 지원서에도 근태 표식·열람권 회수)
const {exports: Y} = loadIndexClosure(['callableCleanupApplicationData'], F, {HttpsError, console: QCON, Date: FakeDate});
test('G2 확정 중인 지원서에는 정리 callable 이 쓰지 않아야 한다', async () => {
  base();
  F.put('applications/a1', {uid: 'w1', businessId: 'b1', toId: 't1', status: 'CONFIRMED', workDate: new Ts(NOW)});
  F.put('attendance/at1', {applicationId: 'a1', userId: 'w1', businessId: 'b1', wageStatus: 'pending',
    checkIn: new Ts(NOW - 3600000), checkOut: null, status: 'checked_in'});
  F.put('idCardAccessRequests/auto_a1', {applicationId: 'a1', targetUserId: 'w1', requesterBusinessId: 'b1', status: 'approved'});
  const o = await go(Y.callableCleanupApplicationData, {applicationId: 'a1'}, 'w1', {role: 'USER'});
  const at = F.get('attendance/at1'); const g = F.get('idCardAccessRequests/auto_a1');
  const note = `call=${o.ok ? JSON.stringify(o.r) : o.e.code} att.canceledWithApplication=${at.canceledWithApplication} grant=${g.status}`;
  if (DEFECT) {
    assert.strictEqual(at.canceledWithApplication, true, '결함 재현: ' + note);
    assert.strictEqual(g.status, 'revoked', note);
  } else {
    assert.notStrictEqual(at.canceledWithApplication, true, '확정 지원서 근태에 취소 표식: ' + note);
  }
});

// ── 정상 동치(두 원문 같은 결과) ──
test('KN1 계약 대기 지원의 근로자 서명 — 완료 · 지원서 CONFIRMED', async () => {
  base();
  F.put('applications/a1', {uid: 'w1', businessId: 'b1', toId: 't1', status: 'CONTRACT_PENDING', workDate: new Ts(NOW + 3 * DAY)});
  serverContract('c1', 'a1');
  const png = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3]).toString('base64');
  const pdf = Buffer.from('%PDF-1.4 fake').toString('base64');
  const o = await go(X.callableFinalizeWorkerSignature, {contractId: 'c1', signatureBase64: png, pdfBase64: pdf}, 'w1', {role: 'USER'});
  assert.ok(o.ok, o.e && o.e.message);
  assert.strictEqual(F.get('employment_contracts/c1').status, 'completed');
  assert.strictEqual(F.get('applications/a1').status, 'CONFIRMED');
});
test('KN2 완료 계약은 탈퇴를 막지 않는다', async () => {
  base();
  serverContract('c3', 'a3', {status: 'completed', workerSignatureUrl: 'https://fake/w.png'});
  const o = await go(X.callableGetWithdrawBlockers, {}, 'w1', {role: 'USER'});
  assert.strictEqual(unsignedBlock(o.r), 0);
});
test('KN3 취소된 지원의 정리 — 지금처럼 근태 표식 · 열람권 회수', async () => {
  base();
  F.put('applications/a1', {uid: 'w1', businessId: 'b1', toId: 't1', status: 'CANCELED', workDate: new Ts(NOW)});
  F.put('attendance/at1', {applicationId: 'a1', userId: 'w1', businessId: 'b1', wageStatus: 'pending'});
  F.put('idCardAccessRequests/auto_a1', {applicationId: 'a1', targetUserId: 'w1', requesterBusinessId: 'b1', status: 'approved'});
  const o = await go(Y.callableCleanupApplicationData, {applicationId: 'a1'}, 'w1', {role: 'USER'});
  assert.ok(o.ok);
  assert.strictEqual(F.get('attendance/at1').canceledWithApplication, true);
  assert.strictEqual(F.get('idCardAccessRequests/auto_a1').status, 'revoked');
});
