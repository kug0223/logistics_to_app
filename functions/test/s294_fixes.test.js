'use strict';
/**
 * [판정294 지정 수리 4] F294-DEL-01 · F294-CLOSE-01 · F294-MONEY-01 · F294-NOSHOW-01 — 반례 시험.
 *   S294_EXPECT_OLD=1 이면 이전 원문(e64e1d42 사본)에서 결함을 재현한다(음성 대조). 정상 셀은 두 원문에서 같은 결과(동치).
 */
const {test} = require('node:test');
const assert = require('assert');
const {createFakeFirestore} = require('./consent_r4d_fakestore');
const {loadIndexClosure} = require('./auth_kakao_index_harness');

const OLD = process.env.S294_EXPECT_OLD === '1';
const RealDate = Date;
const NOW = RealDate.UTC(2026, 10, 27, 3, 0);
const DAY = 86400000;
const KST = 9 * 3600000;
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
const {exports: X} = loadIndexClosure(['callableDeleteTO', 'callableDeleteSlots', 'callableCloseSlots',
  'callableGetIdCardSignedUrl', 'callableAdminDirectInterimSettlement', 'callableBatchCancelNoShow', 'callableBatchSetNoShow'],
F, {HttpsError, console: QCON, Date: FakeDate});
const Ts = F.Ts;
const go = async (fn, data, uid = 'own1') => {
  try { return {ok: true, r: await fn({data, auth: {uid, token: {}}})}; } catch (e) { return {ok: false, e}; }
};
const code = (o) => o.e && (o.e.details && o.e.details.code || o.e.code);

function base() {
  F.reset();
  F.hooks.afterGet = null; F.hooks.beforeCommit = null;
  F.put('users/own1', {role: 'BUSINESS_ADMIN', accountStatus: 'active', name: '사장', businessId: 'b1'});
  F.put('businesses/b1', {name: '평택', ownerId: 'own1', adminIds: ['own1'], isApproved: true});
  F.put('tos/t1', {businessId: 'b1', businessName: '평택', title: '물류', status: 'ACTIVE', totalPending: 0, totalConfirmed: 0,
    isPublished: true});
}
const slot = (id, o = {}) => F.put(`tos/t1/slots/${id}`, Object.assign({status: 'open', date: new Ts(NOW + 3 * DAY),
  pendingCount: 0, confirmedCount: 0, workDetails: [{wdId: 'wd1', workType: '포장', startTime: '09:00', endTime: '18:00', requiredCount: 5}],
  workDetailCounts: {wd1: {pendingCount: 0, confirmedCount: 0}}}, o));
const app = (id, status, slotId, o = {}) => F.put(`applications/${id}`, Object.assign({uid: `u_${id}`, businessId: 'b1',
  businessName: '평택', toId: 't1', slotId, wdId: 'wd1', status, selectedWorkType: '포장', workDate: new Ts(NOW + 3 * DAY)}, o));
const grant = (id, appId, uid, o = {}) => F.put(`idCardAccessRequests/${id}`, Object.assign({requesterId: 'own1',
  requesterBusinessId: 'b1', targetUserId: uid, applicationId: appId, status: 'approved', expiresAt: new Ts(NOW + DAY),
  respondedAt: new Ts(NOW - 3600000)}, o));
// 관계 확인(계약 질의) 직후 한 번 — 관계 확인 뒤 · 정리 전 경합 경로로 늦은 지원을 넣는다.
function afterRelationCheck(seed) {
  const orig = F.db.collection;
  let fired = false;
  F.db.collection = (c) => {
    const real = orig(c);
    if (c !== 'employment_contracts' || fired) return real;
    const wrap = (q) => new Proxy(q, {get: (t, k) => {
      if (k === 'get') return async () => { const r = await t.get(); if (!fired) { fired = true; seed(); } return r; };
      if (k === 'where' || k === 'limit' || k === 'orderBy') return (...a) => wrap(t[k](...a));
      return typeof t[k] === 'function' ? t[k].bind(t) : t[k];
    }});
    return wrap(real);
  };
  return () => { F.db.collection = orig; };
}
// 그 컬렉션의 n번째 질의 결과 직후 한 번 바꾼다.
function afterNthQuery(col, n, fn) {
  const orig = F.db.collection;
  let seen = 0; let fired = false;
  F.db.collection = (c) => {
    const real = orig(c);
    if (c !== col || fired) return real;
    const wrap = (q) => new Proxy(q, {get: (t, k) => {
      if (k === 'get') return async () => { const r = await t.get(); if (!fired && ++seen === n) { fired = true; fn(); } return r; };
      if (k === 'where' || k === 'limit' || k === 'orderBy' || k === 'startAfter') return (...a) => wrap(t[k](...a));
      return typeof t[k] === 'function' ? t[k].bind(t) : t[k];
    }});
    return wrap(real);
  };
  return () => { F.db.collection = orig; };
}
// Firestore 거래 재시도 흉내 — 첫 거래 본문을 한 번 끝까지 돌리고 버린 뒤(between 으로 상태 변경) 다시 돌린다.
function retryFirstTx(between) {
  const orig = F.db.runTransaction;
  let done = false;
  F.db.runTransaction = async (cb) => {
    if (!done) {
      done = true;
      try { await orig(async (tx) => { await cb(tx); throw new Error('RETRY_SIM'); }); } catch (e) {
        if (e.message !== 'RETRY_SIM') throw e;
      }
      if (between) between();
    }
    return orig(cb);
  };
  return () => { F.db.runTransaction = orig; };
}
const commitOf = (path) => F.W.commits.find((c) => c.writes.some((w) => w.path === path));

// ═════════════════════ F294-DEL-01 ═════════════════════
test('DEL1 공고 삭제 — 늦은 확정 지원 취소와 열람권(auto·개인) 회수가 **같은 커밋**', async () => {
  base();
  const restore = afterRelationCheck(() => {
    app('a1', 'CONFIRMED', 's1');
    grant('auto_a1', 'a1', 'u_a1', {requesterId: 'business:b1'});
    grant('pg1', 'a1', 'u_a1');
  });
  const o = await go(X.callableDeleteTO, {toId: 't1'});
  restore();
  assert.ok(o.ok, o.e && o.e.message);
  assert.strictEqual(F.get('applications/a1').status, 'AUTO_CANCELED');
  assert.strictEqual(F.get('idCardAccessRequests/pg1').status, 'revoked');
  assert.strictEqual(F.get('idCardAccessRequests/auto_a1').status, 'revoked');
  const ca = commitOf('applications/a1'); const cg = commitOf('idCardAccessRequests/pg1');
  if (OLD) { assert.notStrictEqual(ca.tx, cg.tx, '음성 대조: 이전 원문은 취소와 회수가 다른 커밋'); return; }
  assert.strictEqual(ca.tx, cg.tx, '취소와 회수가 같은 거래');
});

test('DEL2 재실행 수렴 — 앞 실행이 취소만 남긴 지원서(AUTO_CANCELED · 열람권 approved)의 열람권을 다시 회수', async () => {
  base();
  const restore = afterRelationCheck(() => {
    app('a1', 'AUTO_CANCELED', 's1', {cancelReason: 'TO_DELETED'});
    grant('pg1', 'a1', 'u_a1');
  });
  const o = await go(X.callableDeleteTO, {toId: 't1'});
  restore();
  assert.ok(o.ok, o.e && o.e.message);
  assert.strictEqual(F.get('tos/t1').isDeleted, true);
  assert.strictEqual(F.get('idCardAccessRequests/pg1').status, OLD ? 'approved' : 'revoked',
    OLD ? '음성 대조: 이전 원문은 비활성 지원서를 건너뛰어 열람권이 남는다' : '');
});

test('DEL3 과대 묶음(확정 + 개인 열람권 451) — 지원서를 바꾸기 **전에** 거절 · 쓰기 0', async () => {
  base();
  const restore = afterRelationCheck(() => {
    app('a1', 'CONFIRMED', 's1');
    for (let i = 0; i < 451; i++) grant(`pg${i}`, 'a1', 'u_a1');
  });
  const o = await go(X.callableDeleteTO, {toId: 't1'});
  restore();
  assert.ok(!o.ok);
  assert.strictEqual(code(o), 'WRITE_GROUP_TOO_LARGE');
  if (OLD) {
    assert.strictEqual(F.get('applications/a1').status, 'AUTO_CANCELED', '음성 대조: 이전 원문은 취소를 먼저 커밋했다');
    return;
  }
  assert.strictEqual(F.get('applications/a1').status, 'CONFIRMED');
  assert.strictEqual(F.get('idCardAccessRequests/pg0').status, 'approved');
  assert.ok(!F.get('tos/t1').isDeleted);
});

test('DEL4 실근무 보존 — 출근 기록이 있는 확정은 취소·회수하지 않고 공고만 삭제(기존 의미)', async () => {
  base();
  const wd = new Ts(NOW - DAY);
  const restore = afterRelationCheck(() => {
    app('a1', 'CONFIRMED', 's1', {workDate: wd});
    grant('pg1', 'a1', 'u_a1');
    const kd = new RealDate(wd.toMillis() + KST);
    const ds = `${kd.getUTCFullYear()}${String(kd.getUTCMonth() + 1).padStart(2, '0')}${String(kd.getUTCDate()).padStart(2, '0')}`;
    F.put(`attendance/a1_${ds}`, {applicationId: 'a1', businessId: 'b1', userId: 'u_a1', checkIn: new Ts(NOW - DAY + 3600000)});
  });
  const o = await go(X.callableDeleteTO, {toId: 't1'});
  restore();
  assert.ok(o.ok, o.e && o.e.message);
  assert.strictEqual(F.get('applications/a1').status, 'CONFIRMED');
  assert.strictEqual(F.get('idCardAccessRequests/pg1').status, 'approved');
  assert.strictEqual(F.get('tos/t1').isDeleted, true);
});

test('DEL5 슬롯 삭제 경합 — 조회 뒤 PENDING→확정+열람권+계약 → 거절과 함께 열람권 회수·계약 무효(같은 커밋)', async () => {
  base(); slot('s1'); slot('s2');
  const restoreA = afterRelationCheck(() => app('a1', 'PENDING', 's1'));
  // 정리 조회(지원서 질의) 직후: 다른 경로가 확정 + 열람권 + 계약 생성
  const restoreB = afterNthQuery('applications', 2, () => {
    app('a1', 'CONFIRMED', 's1');
    grant('pg1', 'a1', 'u_a1');
    F.put('employment_contracts/c1', {applicationId: 'a1', businessId: 'b1', status: 'pending_worker'});
  });
  const o = await go(X.callableDeleteSlots, {toId: 't1', slotIds: ['s1'], businessId: 'b1'});
  restoreB(); restoreA();
  assert.ok(o.ok, o.e && o.e.message);
  assert.strictEqual(F.get('applications/a1').status, 'REJECTED');
  if (OLD) {
    assert.strictEqual(F.get('idCardAccessRequests/pg1').status, 'approved', '음성 대조: 조회 당시 PENDING 이라 열람권을 놓친다');
    assert.strictEqual(F.get('employment_contracts/c1').status, 'pending_worker', '음성 대조: 계약도 놓친다');
    return;
  }
  assert.strictEqual(F.get('idCardAccessRequests/pg1').status, 'revoked');
  assert.strictEqual(F.get('employment_contracts/c1').status, 'voided');
  assert.strictEqual(commitOf('applications/a1').tx, commitOf('idCardAccessRequests/pg1').tx);
  assert.strictEqual(commitOf('applications/a1').tx, commitOf('employment_contracts/c1').tx);
  assert.strictEqual(F.get('tos/t1').totalPending, 0, '확정을 대기로 잘못 빼지 않는다');
});

test('DEL5b 계획(열람권 조회) 뒤 · 커밋 전 PENDING→확정+열람권 — 거래가 바뀐 상태를 보고 다시 계획해 열람권까지 회수', async () => {
  base(); slot('s1'); slot('s2');
  const restoreA = afterRelationCheck(() => app('a1', 'PENDING', 's1'));
  const restoreB = afterNthQuery('idCardAccessRequests', 1, () => {
    app('a1', 'CONFIRMED', 's1');
    grant('pg1', 'a1', 'u_a1');
  });
  const o = await go(X.callableDeleteSlots, {toId: 't1', slotIds: ['s1'], businessId: 'b1'});
  restoreB(); restoreA();
  if (OLD) return; // 이전 원문은 이 계획 단계가 없다(DEL5 가 이전 원문 반례)
  assert.ok(o.ok, o.e && o.e.message);
  assert.strictEqual(F.get('applications/a1').status, 'REJECTED');
  assert.strictEqual(F.get('idCardAccessRequests/pg1').status, 'revoked', '낡은 계획(대기 · 열람권 0)으로 커밋하지 않는다');
  assert.strictEqual(F.get('tos/t1').totalPending, 0);
});

test('DEL6 슬롯 삭제 — 실근무 확정은 거절하지 않는다(삭제는 관계로 막힘)', async () => {
  base(); slot('s1', {date: new Ts(NOW - DAY)}); slot('s2');
  const wd = new Ts(NOW - DAY);
  const restore = afterRelationCheck(() => {
    app('a1', 'CONFIRMED', 's1', {workDate: wd});
    const kd = new RealDate(wd.toMillis() + KST);
    const ds = `${kd.getUTCFullYear()}${String(kd.getUTCMonth() + 1).padStart(2, '0')}${String(kd.getUTCDate()).padStart(2, '0')}`;
    F.put(`attendance/a1_${ds}`, {applicationId: 'a1', businessId: 'b1', userId: 'u_a1', checkIn: new Ts(NOW - DAY + 3600000)});
  });
  const o = await go(X.callableDeleteSlots, {toId: 't1', slotIds: ['s1'], businessId: 'b1'});
  restore();
  if (OLD) { assert.strictEqual(F.get('applications/a1').status, 'REJECTED', '음성 대조: 이전 원문은 실근무 확정도 거절'); return; }
  assert.ok(!o.ok);
  assert.strictEqual(code(o), 'RELATION_AFTER_CHECK');
  assert.strictEqual(F.get('applications/a1').status, 'CONFIRMED');
  assert.ok(F.get('tos/t1/slots/s1'), '슬롯 삭제 0');
});

test('DEL7 정상 동치 — 늦은 대기 1 · 확정 1(열람권 없음) 슬롯 삭제 결과·대기 감소', async () => {
  base(); slot('s1'); slot('s2');
  F.put('tos/t1', Object.assign(F.get('tos/t1'), {totalPending: 1}));
  const restore = afterRelationCheck(() => { app('a1', 'PENDING', 's1'); app('a2', 'CONFIRMED', 's1'); });
  const o = await go(X.callableDeleteSlots, {toId: 't1', slotIds: ['s1'], businessId: 'b1'});
  restore();
  assert.ok(o.ok, o.e && o.e.message);
  assert.deepStrictEqual([F.get('applications/a1').status, F.get('applications/a2').status], ['REJECTED', 'REJECTED']);
  assert.strictEqual(F.get('tos/t1').totalPending, 0);
  assert.strictEqual(o.r.deletedSlotCount, 1);
});

// ── 신분증 열람 읽기 fence ──
function urlBase(appStatus) {
  base();
  F.put('users/w1', {role: 'USER', name: '근로자'}); // 이미지 없음 — fence 를 지나면 not-found
  app('a1', appStatus, 's1', {uid: 'w1'});
  grant('pg1', 'a1', 'w1');
}
test('URL1 취소된 지원서의 수동 열람권(approved · 유효) → 새 URL 발급 거절', async () => {
  urlBase('AUTO_CANCELED');
  const o = await go(X.callableGetIdCardSignedUrl, {targetUserId: 'w1'});
  assert.ok(!o.ok);
  if (OLD) { assert.strictEqual(o.e.code, 'not-found', '음성 대조: 이전 원문은 지원서 상태를 보지 않고 다음 단계로 간다'); return; }
  assert.strictEqual(o.e.code, 'permission-denied');
  assert.strictEqual(code(o), 'GRANT_APPLICATION_INACTIVE');
});
test('URL2 확정 지원서의 열람권은 fence 를 지난다(동치 · 이미지 없음 not-found)', async () => {
  urlBase('CONFIRMED');
  const o = await go(X.callableGetIdCardSignedUrl, {targetUserId: 'w1'});
  assert.ok(!o.ok);
  assert.strictEqual(o.e.code, 'not-found');
});
test('URL3 지원서 id 없는 열람권 — 그 사업장에 확정 지원이 없으면 거절 · 있으면 통과', async () => {
  urlBase('REJECTED');
  F.put('idCardAccessRequests/pg1', Object.assign(F.get('idCardAccessRequests/pg1'), {applicationId: null}));
  let o = await go(X.callableGetIdCardSignedUrl, {targetUserId: 'w1'});
  if (!OLD) assert.strictEqual(code(o), 'GRANT_APPLICATION_INACTIVE');
  app('a2', 'CONFIRMED', 's1', {uid: 'w1'});
  o = await go(X.callableGetIdCardSignedUrl, {targetUserId: 'w1'});
  assert.strictEqual(o.e.code, 'not-found');
});

// ═════════════════════ F294-CLOSE-01 ═════════════════════
test('CL1 슬롯 대기 501 — 500 다음 페이지까지 모두 거절 · 대기 −501', async () => {
  base(); slot('s1', {pendingCount: 501, workDetailCounts: {wd1: {pendingCount: 501, confirmedCount: 0}}});
  F.put('tos/t1', Object.assign(F.get('tos/t1'), {totalPending: 501}));
  for (let i = 0; i < 501; i++) app(`p${String(i).padStart(3, '0')}`, 'PENDING', 's1');
  const o = await go(X.callableCloseSlots, {toId: 't1', slotIds: ['s1'], businessId: 'b1'});
  assert.ok(o.ok, o.e && o.e.message);
  if (OLD) { assert.strictEqual(o.r.canceledCount, 500, '음성 대조: 이전 원문은 500 에서 멈춘다'); return; }
  assert.strictEqual(o.r.canceledCount, 501);
  assert.strictEqual(F.get('applications/p500').status, 'REJECTED');
  assert.strictEqual(F.get('tos/t1/slots/s1').pendingCount, 0);
  assert.strictEqual(F.get('tos/t1').totalPending, 0);
});

test('CL2 한 슬롯 정리 커밋 실패(권한 외) — 성공으로 끝내지 않고 실패 슬롯을 알린다 · 재실행이 남은 것만 처리', async () => {
  base(); slot('s1', {pendingCount: 1}); slot('s2', {pendingCount: 1}); slot('s3');
  F.put('tos/t1', Object.assign(F.get('tos/t1'), {totalPending: 2}));
  app('a1', 'PENDING', 's1'); app('a2', 'PENDING', 's2');
  let failOnce = true;
  F.hooks.beforeCommit = (txId, buf) => {
    if (failOnce && buf.some((w) => w.path === 'applications/a2')) { failOnce = false; throw new Error('UNAVAILABLE'); }
  };
  const o = await go(X.callableCloseSlots, {toId: 't1', slotIds: ['s1', 's2'], businessId: 'b1'});
  F.hooks.beforeCommit = null;
  if (OLD) { assert.ok(o.ok, '음성 대조: 이전 원문은 성공으로 끝낸다'); return; }
  assert.ok(!o.ok);
  assert.strictEqual(o.e.code, 'aborted');
  assert.strictEqual(code(o), 'CLOSE_SLOTS_INCOMPLETE');
  assert.deepStrictEqual(o.e.details.failedSlotIds, ['s2']);
  assert.strictEqual(o.e.details.applicationsRejected, 1);
  assert.strictEqual(F.get('applications/a2').status, 'PENDING');
  const o2 = await go(X.callableCloseSlots, {toId: 't1', slotIds: ['s1', 's2'], businessId: 'b1'});
  assert.ok(o2.ok, o2.e && o2.e.message);
  assert.strictEqual(o2.r.canceledCount, 1);
  assert.strictEqual(F.get('applications/a2').status, 'REJECTED');
  assert.strictEqual(F.get('tos/t1').totalPending, 0);
});

// ═════════════════════ F294-MONEY-01 ═════════════════════
const ACCT = {wageAccountSnapshotVersion: 1, wageAccountBankName: '국민', wageAccountNumberEncrypted: 'enc', wageAccountHolder: '근로자',
  wageAccountSnapshotAt: new Ts(NOW - 5 * DAY), wageAccountSourceBankAccountVersion: 1, wageAccountSourceBankbookDocumentVersion: 1};
function moneyBase() {
  base();
  F.put('users/w1', {role: 'USER', accountStatus: 'active', name: '근로자', bankAccountVersion: 1, bankbookDocumentVersion: 1});
  F.put('applications/a1', {uid: 'w1', businessId: 'b1', toId: 't1', status: 'CONFIRMED'});
}
const att = (id, o = {}) => F.put(`attendance/${id}`, Object.assign({userId: 'w1', businessId: 'b1', applicationId: 'a1',
  wageStatus: 'confirmed', finalWage: 100000, wageDetail: {netWage: 90000}, workDate: new Ts(NOW - 7 * DAY), status: 'completed'}, ACCT, o));
const direct = (ids) => go(X.callableAdminDirectInterimSettlement, {businessId: 'b1', workerId: 'w1', workerName: '근로자',
  businessName: '평택', applicationId: 'a1', attendanceIds: ids, netAmount: 999999});
const isrs = () => Object.entries(F.dump()).filter(([k]) => /^interim_settlement_requests\/[^/]+$/.test(k)).map(([k, v]) => [k, v]);
const jobBody = () => Object.values(F.dump()).filter((v) => v && v.sourceKind === 'interimSettlementCompleted').map((v) => v.payload.body);

test('MO1 과거 이체 A + 새 확정 B — 새 정산은 B 만(목록·기간·세전·실수령·알림)', async () => {
  moneyBase();
  att('A', {wageStatus: 'transferred', workDate: new Ts(NOW - 20 * DAY)});
  att('B', {workDate: new Ts(NOW - 7 * DAY)});
  const o = await direct(['A', 'B']);
  assert.ok(o.ok, o.e && o.e.message);
  const d = isrs()[0][1];
  if (OLD) { assert.strictEqual(d.netAmount, 200000, '음성 대조: 이전 원문은 과거 이체 금액까지 더한다'); return; }
  assert.deepStrictEqual(d.attendanceIds, ['B']);
  assert.strictEqual(d.requestedAmount, 100000);
  assert.strictEqual(d.netAmount, 90000);
  const ps = typeof d.periodStart.toMillis === 'function' ? d.periodStart.toMillis() : d.periodStart.__ts; // F.dump 직렬화 꼴
  assert.strictEqual(ps, NOW - 7 * DAY, '기간은 이번 이체 근태만');
  assert.ok(jobBody()[0].includes('90,000원'), jobBody()[0]);
  assert.deepStrictEqual(o.r.transferredAttendanceIds, ['B']);
  assert.strictEqual(o.r.excluded.A, 'ALREADY_TRANSFERRED');
});

test('MO2 세전≠실수령 1건 · 클라 금액(999,999) 무시', async () => {
  moneyBase(); att('B');
  const o = await direct(['B']);
  assert.ok(o.ok, o.e && o.e.message);
  const d = isrs()[0][1];
  if (OLD) { assert.strictEqual(d.requestedAmount, 999999, '음성 대조: 이전 원문은 클라 금액을 requestedAmount 로'); return; }
  assert.strictEqual(d.requestedAmount, 100000);
  assert.strictEqual(d.netAmount, 90000);
  assert.strictEqual(o.r.netAmount, 90000);
});

test('MO3 제외 혼합(다른 근로자 · lock · 미확정 · 없음) + 정상 1 — 정상 1 만', async () => {
  moneyBase();
  att('ok'); att('ow', {userId: 'w2'}); att('lk', {activeInterimSettlementId: 'isrX'}); att('pd', {wageStatus: 'pending'});
  const o = await direct(['ow', 'lk', 'pd', 'ok', 'none']);
  assert.ok(o.ok, o.e && o.e.message);
  const d = isrs()[0][1];
  if (OLD) { assert.deepStrictEqual(d.attendanceIds, ['ow', 'lk', 'pd', 'ok', 'none'], '음성 대조: 이전 원문은 입력 전체를 저장'); return; }
  assert.deepStrictEqual(d.attendanceIds, ['ok']);
  assert.deepStrictEqual(o.r.excluded, {ow: 'OTHER_WORKER', lk: 'SETTLEMENT_LOCKED', pd: 'NOT_CONFIRMED', none: 'NOT_FOUND'});
});

test('MO4 거래 재시도 — 금액·목록을 시도마다 새로(누적 0)', async () => {
  moneyBase(); att('B');
  const restore = retryFirstTx();
  const o = await direct(['B']);
  restore();
  assert.ok(o.ok, o.e && o.e.message);
  const d = isrs()[0][1];
  assert.strictEqual(d.netAmount, OLD ? 100000 : 90000);
  if (!OLD) { assert.deepStrictEqual(d.attendanceIds, ['B']); assert.deepStrictEqual(o.r.transferredAttendanceIds, ['B']); }
});

test('MO5 과거 PROCESSED 정산 문서는 다시 쓰지 않는다', async () => {
  moneyBase(); att('B');
  F.put('interim_settlement_requests/old1', {businessId: 'b1', workerId: 'w1', status: 'PROCESSED', netAmount: 200000,
    requestedAmount: 200000, attendanceIds: ['A', 'B0']});
  const before = JSON.stringify(F.get('interim_settlement_requests/old1'));
  const o = await direct(['B']);
  assert.ok(o.ok, o.e && o.e.message);
  assert.strictEqual(JSON.stringify(F.get('interim_settlement_requests/old1')), before);
});

// ═════════════════════ F294-NOSHOW-01 ═════════════════════
function nsBase() {
  base();
  F.put('tos/t1/slots/s1', {status: 'open', confirmedCount: 0, workDetails: [{wdId: 'wd1', requiredCount: 3}],
    workDetailCounts: {wd1: {confirmedCount: 0}}});
  F.put('applications/a1', {uid: 'w1', businessId: 'b1', toId: 't1', slotId: 's1', wdId: 'wd1', status: 'CONFIRMED',
    staffingReleasedAt: new Ts(NOW - DAY), staffingReleased: true});
}
const nsAtt = (id, o = {}) => F.put(`attendance/${id}`, Object.assign({userId: 'w1', businessId: 'b1', applicationId: 'a1',
  status: 'NO_SHOW', wageStatus: 'confirmed', finalWage: 0, workDate: new Ts(NOW - 7 * DAY)}, o));
const seat = () => F.get('tos/t1/slots/s1').confirmedCount;

test('NS1 없는 근태 + 정상 1 — processed 1 · skipped [없는 id] · 서로 겹치지 않음', async () => {
  nsBase(); nsAtt('n1');
  const o = await go(X.callableBatchCancelNoShow, {businessId: 'b1', attendanceIds: ['n1', 'ghost']});
  assert.ok(o.ok, o.e && o.e.message);
  if (OLD) { assert.strictEqual(o.r.processed, 2, '음성 대조: 이전 원문은 없는 근태를 처리 수로 센다'); return; }
  assert.strictEqual(o.r.processed, 1);
  assert.deepStrictEqual(o.r.skipped, ['ghost']);
  assert.strictEqual(seat(), 1);
});

test('NS2 사전 조회 뒤 근태가 이체됨(거래에서 취소 건너뜀) — 좌석 복원 0', async () => {
  nsBase(); nsAtt('n1');
  // 이전 원문: 거래 밖 사전 조회(지원서 읽기) 직후 근태가 이체 상태로 바뀐다
  F.hooks.afterGet = (p, txId) => {
    if (txId == null && p === 'applications/a1') {
      F.hooks.afterGet = null;
      F.put('attendance/n1', Object.assign(F.get('attendance/n1'), {wageStatus: 'transferred'}));
    }
  };
  const o = await go(X.callableBatchCancelNoShow, {businessId: 'b1', attendanceIds: ['n1']});
  F.hooks.afterGet = null;
  assert.ok(o.ok, o.e && o.e.message);
  if (OLD) {
    assert.strictEqual(F.get('attendance/n1').wageStatus, 'transferred');
    assert.strictEqual(seat(), 1, '음성 대조: 이전 원문은 취소 0 인데 좌석 +1');
    return;
  }
  // 새 원문은 거래 밖 사전 조회가 없다 — 같은 상황을 거래 전 상태로 직접 둔다
  nsBase(); nsAtt('n1', {wageStatus: 'transferred'});
  const o2 = await go(X.callableBatchCancelNoShow, {businessId: 'b1', attendanceIds: ['n1']});
  assert.ok(o2.ok);
  assert.deepStrictEqual([o2.r.processed, o2.r.skipped, seat()], [0, ['n1'], 0]);
});

test('NS3 거래 재시도 — 첫 시도 뒤 근태가 사라져도 결과는 마지막 시도 기준(누적 0)', async () => {
  nsBase(); nsAtt('n1'); nsAtt('n2', {applicationId: 'a9'});
  const restore = retryFirstTx(() => F.put('attendance/n2', Object.assign(F.get('attendance/n2'), {status: 'present'})));
  const o = await go(X.callableBatchCancelNoShow, {businessId: 'b1', attendanceIds: ['n1', 'n2']});
  restore();
  assert.ok(o.ok, o.e && o.e.message);
  if (OLD) return; // 이전 원문은 첫 시도 skipped 가 거래 밖 배열에 남지 않는 경로(skip 0)라 이 셀의 반례가 아니다
  assert.strictEqual(o.r.processed, 1);
  assert.deepStrictEqual(o.r.skipped, ['n2']);
});

test('NS4 같은 지원서 다른 근태 2건 — 좌석 +1 (정상 동치 · 293 수리 유지)', async () => {
  nsBase(); nsAtt('n1'); nsAtt('n2', {workDate: new Ts(NOW - 6 * DAY)});
  const o = await go(X.callableBatchCancelNoShow, {businessId: 'b1', attendanceIds: ['n1', 'n2']});
  assert.ok(o.ok, o.e && o.e.message);
  assert.strictEqual(o.r.processed, 2);
  assert.strictEqual(seat(), 1);
  assert.strictEqual(F.get('tos/t1').totalConfirmed, 1);
  assert.strictEqual(F.get('tos/t1/slots/s1').workDetailCounts.wd1.confirmedCount, 1);
});

// ── BatchSetNoShow ──
const kstMid = (ms) => { const d = new RealDate(ms + KST); d.setUTCHours(0, 0, 0, 0); return d.getTime() - KST; };
function setBase() {
  base();
  const wdMs = kstMid(NOW - 7 * DAY);
  F.put('applications/a1', {uid: 'w1', businessId: 'b1', status: 'CONFIRMED', type: 'short', startTime: '09:00', endTime: '18:00'});
  F.put('attendance/na1', {userId: 'w1', businessId: 'b1', applicationId: 'a1', workDate: new Ts(wdMs), wageStatus: 'pending'});
  return {applicationId: 'a1', workDateMs: wdMs, userId: 'w1', businessName: '평택', workType: '포장', attendanceId: 'na1'};
}
test('SN1 같은 항목 2번 — processed 1 · skipped 에 처리된 id 없음', async () => {
  const e = setBase();
  const o = await go(X.callableBatchSetNoShow, {businessId: 'b1', entries: [e, Object.assign({}, e)]});
  assert.ok(o.ok, o.e && o.e.message);
  assert.strictEqual(F.get('attendance/na1').status, 'NO_SHOW');
  // 음성 대조: 이전 원문은 같은 항목 2개를 두 번 처리로 세거나(processed 2) 처리된 id 를 skipped 에도 넣는다(실 Firestore 직렬화 시)
  if (OLD) { assert.ok(o.r.processed === 2 || o.r.skipped.includes('na1'), JSON.stringify(o.r)); return; }
  assert.strictEqual(o.r.processed, 1);
  assert.deepStrictEqual(o.r.skipped, []);
  assert.strictEqual(F.W.commits.filter((c) => c.writes.some((w) => w.path === 'attendance/na1')).length, 1, '근태 쓰기 1회');
});
test('SN2 같은 근태 · 내용이 다른 항목 — 쓰기 전 거절(NOSHOW_ENTRY_CONFLICT)', async () => {
  const e = setBase();
  const o = await go(X.callableBatchSetNoShow, {businessId: 'b1', entries: [e, Object.assign({}, e, {workType: '분류'})]});
  if (OLD) return;
  assert.ok(!o.ok);
  assert.strictEqual(code(o), 'NOSHOW_ENTRY_CONFLICT');
  assert.strictEqual(F.get('attendance/na1').status, undefined);
});
test('SN3 거래 재시도 — 첫 시도 건너뜀(이미 계산됨) 뒤 성공 시도면 processed 로만 보고', async () => {
  const e = setBase();
  F.put('attendance/na1', Object.assign(F.get('attendance/na1'), {wageStatus: 'calculated'}));
  const restore = retryFirstTx(() => F.put('attendance/na1', Object.assign(F.get('attendance/na1'), {wageStatus: 'pending'})));
  const o = await go(X.callableBatchSetNoShow, {businessId: 'b1', entries: [e]});
  restore();
  assert.ok(o.ok, o.e && o.e.message);
  if (OLD) { assert.deepStrictEqual([o.r.processed, o.r.skipped], [0, ['na1']], '음성 대조: 첫 시도의 건너뜀이 남는다'); return; }
  assert.strictEqual(F.get('attendance/na1').status, 'NO_SHOW');
  assert.deepStrictEqual([o.r.processed, o.r.skipped], [1, []]);
});
