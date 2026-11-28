'use strict';
/**
 * [판정296 §2-5 K-1c · 정책 P2(b) · P7] 탈퇴/계약/cleanup.
 *   K1–K4 탈퇴 취소 거래가 끊는 미서명 계약 무효 + 사업주 영속 알림(같은 거래) · 살아 있는 연결/실근무/다른 근로자 보존 · 관문 → 경고.
 *   S1–S3 근로자 서명 거래: freeze 뒤 커밋 차단 · 지원서 사업장 · 활성 세대.
 *   C1–C2 정리 callable 같은 거래 상태 fence(재지원으로 되살아남 · 세대).
 *   P1–P3 하루 sweep: 모든 연결 지원서 명확 비활성만 APPLICATION_INACTIVE · 모름 보류 · 완료 보존 · 날짜 만료 0 · 커서 재개.
 *   S296K_EXPECT_OLD=1 이면 이전 원문에서 결함을 재현한다.
 */
const {test} = require('node:test');
const assert = require('assert');
const {createFakeFirestore} = require('./consent_r4d_fakestore');
const {loadIndexClosure} = require('./auth_kakao_index_harness');

const OLD = process.env.S296K_EXPECT_OLD === '1';
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
const ROOTS = ['callableGetWithdrawBlockers', 'callableDeleteAccountApplications', 'callableFinalizeWorkerSignature',
  'callableCleanupApplicationData'];
if (!OLD) ROOTS.push('processPendingContractInactiveSweep');
const {exports: X} = loadIndexClosure(ROOTS, F, {HttpsError, console: QCON, Date: FakeDate});
const Ts = F.Ts;
const go = async (fn, data, uid, token = {}) => {
  try { return {ok: true, r: await fn({data, auth: {uid, token}})}; } catch (e) { return {ok: false, e}; }
};
const code = (o) => o.e && ((o.e.details && o.e.details.code) || o.e.code);
const ownerJobs = () => Object.entries(F.dump()).filter(([k, v]) => k.startsWith('notification_jobs/') &&
  v.recipientUid === 'own1' && v.sourceKind === 'contractVoidedByWorkerExit');

function base() {
  F.reset(); files.clear();
  F.put('users/w1', {role: 'USER', accountStatus: 'active', name: '근로자'});
  F.put('users/own1', {role: 'BUSINESS_ADMIN', accountStatus: 'active', name: '사장', businessId: 'b1'});
  F.put('businesses/b1', {name: '평택', ownerId: 'own1', adminIds: ['own1'], isApproved: true});
  F.put('tos/t1', {businessId: 'b1', title: '물류', status: 'ACTIVE', totalPending: 0, totalConfirmed: 2});
}
const app = (id, o = {}) => F.put(`applications/${id}`, Object.assign({uid: 'w1', businessId: 'b1', toId: 't1',
  status: 'CONTRACT_PENDING', workDate: new Ts(NOW + 3 * DAY)}, o));
const contract = (id, appIds, o = {}) => F.put(`employment_contracts/${id}`, Object.assign({
  applicationId: appIds[0], applicationIds: appIds, businessId: 'b1', workerId: 'w1', toId: 't1',
  status: 'pending_worker', employerSignatureUrl: 'https://fake/e.png', employerSignatureStoragePath: 'contracts/x/e.png',
  employerSignedAt: new Ts(NOW - DAY), createdAt: new Ts(NOW - DAY), snapshot: {workerName: '근로자'}, articles: []}, o));
const delApps = () => go(X.callableDeleteAccountApplications, {}, 'w1', {role: 'USER'});
const cStatus = (id) => F.get(`employment_contracts/${id}`).status;

test('K1 탈퇴 취소 — 끊는 미서명 계약을 같은 거래에서 무효 + 사업주 영속 알림', async () => {
  base(); app('a1'); contract('c1', ['a1']);
  const o = await delApps();
  assert.ok(o.ok, o.e && o.e.message);
  assert.strictEqual(F.get('applications/a1').status, 'CANCELED');
  if (OLD) { assert.strictEqual(cStatus('c1'), 'pending_worker', '음성 대조: 이전 원문은 계약이 남는다'); return; }
  assert.strictEqual(cStatus('c1'), 'voided');
  assert.strictEqual(F.get('employment_contracts/c1').voidReason, 'WORKER_ACCOUNT_DELETED');
  assert.strictEqual(ownerJobs().length, 1);
  const c = F.W.commits.find((x) => x.writes.some((w) => w.path === 'applications/a1' && w.data && w.data.status === 'CANCELED'));
  assert.ok(c.writes.some((w) => w.path === 'employment_contracts/c1') && c.writes.some((w) => w.path.startsWith('notification_jobs/')),
    '지원서 취소 · 계약 무효 · 알림 작업 = 같은 커밋');
});

test('K2 묶음 계약(두 지원서) — 마지막 취소에서 한 번 무효 · 한쪽이 실근무로 보존되면 무효 0', async () => {
  base(); app('a1'); app('a2', {status: 'CONFIRMED'}); contract('c1', ['a1', 'a2']);
  F.occ.enabled = true; // 두 취소 거래가 병렬 — 서로의 지원서를 읽으므로 한쪽이 재실행에서 상대 취소를 본다(Firestore 직렬화 모형)
  let o = await delApps();
  assert.ok(o.ok, o.e && o.e.message);
  if (!OLD) {
    assert.strictEqual(cStatus('c1'), 'voided');
    assert.strictEqual(ownerJobs().length, 1);
  }
  base(); app('a1'); app('a2', {status: 'CONFIRMED', workDate: new Ts(NOW)}); contract('c1', ['a1', 'a2']);
  F.put('attendance/a2_20261127', {applicationId: 'a2', userId: 'w1', businessId: 'b1', checkIn: new Ts(NOW - 3600000)});
  o = await delApps();
  assert.ok(o.ok, o.e && o.e.message);
  assert.strictEqual(F.get('applications/a2').status, 'CONFIRMED', '실근무 보존');
  assert.strictEqual(cStatus('c1'), 'pending_worker', '살아 있는 연결(실근무) 계약 무효 0');
});

test('K3 다른 근로자·다른 사업장 계약 · 완료 계약은 건드리지 않는다', async () => {
  base(); app('a1'); contract('cx', ['a1'], {workerId: 'w9'}); contract('cy', ['a1'], {businessId: 'b9'});
  contract('cz', ['a1'], {status: 'completed', workerSignatureUrl: 'https://fake/w.png'});
  const o = await delApps();
  assert.ok(o.ok);
  assert.strictEqual(cStatus('cx'), 'pending_worker');
  assert.strictEqual(cStatus('cy'), 'pending_worker');
  assert.strictEqual(cStatus('cz'), 'completed');
});

test('K4 관문 정렬(P2) — 미서명 계약은 하드 차단이 아니라 경고', async () => {
  base(); app('a1'); contract('c1', ['a1']);
  const o = await go(X.callableGetWithdrawBlockers, {}, 'w1', {role: 'USER'});
  assert.ok(o.ok, o.e && o.e.message);
  const hard = (o.r.hardBlocks || []).some((b) => b.type === 'UNSIGNED_CONTRACT');
  if (OLD) { assert.ok(hard, '음성 대조: 이전 원문은 서명 강제'); return; }
  assert.ok(!hard);
  assert.ok((o.r.warnings || []).some((b) => b.type === 'UNSIGNED_CONTRACT' && b.count === 1));
});

const png = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3]).toString('base64');
const pdf = Buffer.from('%PDF-1.4 fake').toString('base64');
const sign = () => go(X.callableFinalizeWorkerSignature, {contractId: 'c1', signatureBase64: png, pdfBase64: pdf}, 'w1', {role: 'USER'});

test('S1 서명 거래 — 이미 들어온 서명 요청도 freeze(탈퇴 tombstone) 뒤에는 커밋하지 않는다', async () => {
  base(); app('a1'); contract('c1', ['a1']);
  let armed = true;
  // 사전 인가·업로드를 지나 거래가 계약을 읽는 순간 freeze 가 커밋된다(진입은 freeze 전)
  F.hooks.afterGet = (p, txId) => {
    if (armed && txId != null && p === 'employment_contracts/c1') {
      armed = false;
      F.put('account_deletion_tombstones/w1', {barrierAt: new Ts(NOW)});
    }
  };
  F.occ.enabled = true;
  const o = await sign();
  F.hooks.afterGet = null;
  assert.ok(!armed);
  if (OLD) { assert.strictEqual(cStatus('c1'), 'completed', '음성 대조: 이전 원문은 freeze 뒤에도 서명 완료'); return; }
  assert.strictEqual(code(o), 'ACCOUNT_DELETING');
  assert.strictEqual(cStatus('c1'), 'pending_worker');
  assert.strictEqual(F.get('applications/a1').status, 'CONTRACT_PENDING');
});

test('S2 연결 지원서 사업장이 계약 사업장과 다르면 서명 거절', async () => {
  base(); app('a1', {businessId: 'b9'}); contract('c1', ['a1']);
  const o = await sign();
  if (OLD) { assert.strictEqual(cStatus('c1'), 'completed', '음성 대조'); return; }
  assert.strictEqual(code(o), 'APPLICATION_NOT_ACTIVE');
  assert.strictEqual(o.e.details.reason, 'BUSINESS');
});

test('S3 활성 세대 — 계약이 기록한 세대와 다르면(취소 뒤 재지원) 거절 · 같으면/기록 없으면 정상 완료', async () => {
  base(); app('a1', {activationGeneration: 2}); contract('c1', ['a1'], {applicationActivationGenerations: {a1: 1}});
  let o = await sign();
  if (!OLD) {
    assert.strictEqual(code(o), 'APPLICATION_NOT_ACTIVE');
    assert.strictEqual(o.e.details.reason, 'GENERATION');
  }
  base(); app('a1', {activationGeneration: 1}); contract('c1', ['a1'], {applicationActivationGenerations: {a1: 1}});
  o = await sign();
  assert.ok(o.ok, o.e && o.e.message);
  assert.strictEqual(cStatus('c1'), 'completed');
  base(); app('a1'); contract('c1', ['a1']);
  o = await sign();
  assert.ok(o.ok, o.e && o.e.message);
});

const cleanup = () => go(X.callableCleanupApplicationData, {applicationId: 'a1'}, 'w1', {role: 'USER'});
test('C1 정리 callable — 초기 조회 뒤 재지원으로 되살아나면(같은 거래 fence) 쓰기 0', async () => {
  base(); app('a1', {status: 'CANCELED'});
  F.put('attendance/at1', {applicationId: 'a1', userId: 'w1', businessId: 'b1', wageStatus: 'pending'});
  F.put('idCardAccessRequests/auto_a1', {applicationId: 'a1', targetUserId: 'w1', requesterBusinessId: 'b1', status: 'approved'});
  let armed = true;
  F.hooks.afterGet = (p, txId) => {
    if (armed && txId == null && p === 'idCardAccessRequests/auto_a1') {
      armed = false;
      app('a1', {status: 'PENDING', activationGeneration: 1});
    }
  };
  const o = await cleanup();
  F.hooks.afterGet = null;
  assert.ok(o.ok);
  if (OLD) { assert.strictEqual(F.get('attendance/at1').canceledWithApplication, true, '음성 대조: 이전 원문은 되살아난 지원에도 표식'); return; }
  assert.strictEqual(o.r.skipped, 'APPLICATION_ACTIVE');
  assert.strictEqual(F.get('attendance/at1').canceledWithApplication, undefined);
  assert.strictEqual(F.get('idCardAccessRequests/auto_a1').status, 'approved');
});

test('C2 정리 callable 정상 동치 — 비활성 그대로면 표식·회수 · 반복 호출 멱등', async () => {
  base(); app('a1', {status: 'CANCELED'});
  F.put('attendance/at1', {applicationId: 'a1', userId: 'w1', businessId: 'b1', wageStatus: 'pending'});
  F.put('idCardAccessRequests/auto_a1', {applicationId: 'a1', targetUserId: 'w1', requesterBusinessId: 'b1', status: 'approved'});
  let o = await cleanup();
  assert.ok(o.ok);
  assert.strictEqual(o.r.cleaned, 2);
  assert.strictEqual(F.get('attendance/at1').canceledWithApplication, true);
  assert.strictEqual(F.get('idCardAccessRequests/auto_a1').status, 'revoked');
  o = await cleanup();
  assert.ok(o.ok);
});

test('P1 하루 sweep — 모든 연결 지원서가 명확히 비활성인 미서명 계약만 APPLICATION_INACTIVE', async () => {
  if (OLD) return;
  base();
  app('a1', {status: 'CANCELED'}); app('a2', {status: 'REJECTED'}); app('a3', {status: 'CONFIRMED'}); app('a4', {status: 'NO_SHOW'});
  contract('c1', ['a1', 'a2']); // 전부 비활성 → 무효
  contract('c2', ['a1', 'a3']); // 살아 있는 연결 → 보존
  contract('c3', ['a4']); // 모르는 상태(NO_SHOW) → 보존
  contract('c4', ['zz']); // 지원서 없음 → 보류
  contract('c5', ['a1'], {status: 'completed'}); // 완료 보존
  contract('c6', ['a3'], {createdAt: new Ts(NOW - 400 * DAY)}); // 오래돼도 날짜 만료 0
  const r = await X.processPendingContractInactiveSweep(new Ts(NOW));
  assert.strictEqual(cStatus('c1'), 'voided');
  assert.strictEqual(F.get('employment_contracts/c1').voidReason, 'APPLICATION_INACTIVE');
  for (const id of ['c2', 'c3', 'c4', 'c6']) assert.strictEqual(cStatus(id), 'pending_worker', id);
  assert.strictEqual(cStatus('c5'), 'completed');
  assert.strictEqual(r.voided, 1);
  assert.ok(r.held >= 1);
});

test('P2 sweep 거래 fresh — 판정 직전 서명·재활성화되면 쓰기 0', async () => {
  if (OLD) return;
  base(); app('a1', {status: 'CANCELED'}); contract('c1', ['a1']);
  F.occ.enabled = true;
  let armed = true;
  F.hooks.afterGet = (p, txId) => {
    if (armed && txId != null && p === 'applications/a1') { armed = false; app('a1', {status: 'PENDING'}); }
  };
  await X.processPendingContractInactiveSweep(new Ts(NOW));
  F.hooks.afterGet = null;
  assert.strictEqual(cStatus('c1'), 'pending_worker');
});

test('P3 sweep 커서 재개 — 300 넘으면 다음 날 이어서(끝에 닿으면 처음부터)', async () => {
  if (OLD) return;
  base(); app('a1', {status: 'CANCELED'});
  for (let i = 0; i < 305; i++) contract(`k${String(i).padStart(3, '0')}`, ['a1']);
  let r = await X.processPendingContractInactiveSweep(new Ts(NOW));
  assert.strictEqual(r.scanned, 300);
  assert.strictEqual(cStatus('k304'), 'pending_worker');
  r = await X.processPendingContractInactiveSweep(new Ts(NOW + DAY));
  assert.strictEqual(r.scanned, 5);
  assert.strictEqual(cStatus('k304'), 'voided');
  assert.strictEqual(F.get('sweep_cursors/pendingContractInactive').lastId, '');
});
