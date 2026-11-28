/**
 * [SERVER-MERGE-1 2026-11-25] DEV 후보 패키지 동작 → A(functions/src) 병합 시험.
 *
 *   대상: A index.ts 원문 폐포를 auth_kakao_index_harness.loadIndexClosure 로 실행한다(재구현 0).
 *     · 노쇼 원장·제한 성분 — ResetPenalty(auto 만 해제 · noop · 전환 운영 계정) · 수동 제한 설정/해제 ·
 *       srvLedgerUserUpdates(base 보존) · ReleaseNoshowSeat 이중 반납 · ApplyNoShowPenalty 장기 차단 ·
 *       CancelResignRequest 철회 이력
 *     · 최저임금 — SetMinimumWages(고시값·충돌·감사) · 공고 helper(바뀐 업무만 · 마감 제외 · 묶음 오류)
 *     · 수동 제한 중 새 약속 차단 helper · UpdateWageDetail expectedCurrent → WAGE_CHANGED ·
 *       GetPayrollMonthLedgerCounts · GetReviewsForUser 공개 범위 · ManageBusiness 중지 사업장 승인 차단 ·
 *       createNotification 관계 증명 · terms_consent_payload .54 발행본 경계
 *     · 원문 배선 — 확정/승인/갱신 수락의 제한 차단 · 공개/재오픈/USWD 최저임금 호출 자리 · CheckIn 기간 제재 통과 ·
 *       새 callable 의 공통 onCall(탈퇴 fence) 경유
 *   네트워크·실제 Firestore 0(가짜 저장소). 원문 수정 0.
 */
'use strict';
const NET = [];
for (const [m, ks] of [['http', ['request', 'get']], ['https', ['request', 'get']], ['net', ['connect', 'createConnection']],
  ['tls', ['connect']], ['dns', ['lookup', 'resolve', 'resolve4', 'resolve6']]]) {
  const mod = require(m);
  for (const k of ks) mod[k] = () => { NET.push(`${m}.${k}`); throw new Error(`[차단] ${m}.${k}`); };
}
globalThis.fetch = () => { NET.push('fetch'); throw new Error('[차단] fetch'); };

const test = require('node:test');
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const {createFakeFirestore} = require('./consent_r4d_fakestore');
const {loadIndexClosure} = require('./auth_kakao_index_harness');

process.env.FOREIGN_HMAC_SECRET = 'synthetic-foreign-hmac-secret-000';
process.env.TAX_ID_HMAC_SECRET = 'synthetic-tax-hmac-secret-0000000';
process.env.TAX_ID_ENCRYPT_KEY = Buffer.alloc(32, 7).toString('base64');

const RealDate = Date;
let NOW = RealDate.UTC(2026, 10, 25, 3, 0); // 2026-11-25 12:00 KST
class FakeDate extends RealDate {
  constructor(...a) { if (a.length === 0) super(NOW); else super(...a); }
  static now() { return NOW; }
}
class HttpsError extends Error {
  constructor(code, message, details) { super(message); this.code = code; this.details = details; }
}
const LOGS = [];
const QCON = {};
for (const k of ['log', 'info', 'warn', 'error', 'debug']) QCON[k] = (...a) => LOGS.push(a.map(String).join(' '));
const F = createFakeFirestore({now: () => NOW});

const ROOTS = [
  'callableResetPenalty', 'callableSetManualRestriction', 'callableReleaseManualRestriction',
  'callableSetMinimumWages', 'callableUpdateWageDetail', 'callableGetPayrollMonthLedgerCounts',
  'callableApplyNoShowPenalty', 'callableReleaseNoshowSeat', 'callableCancelResignRequest',
  'callableGetReviewsForUser', 'callableManageBusiness',
  'srvLedgerUserUpdates', 'srvReadRestrictionParts', 'srvAssertNoRestrictionForNewCommitment',
  'srvAssertChangedWDsMinWageInTx52', 'srvSlotEntries52', 'srvThrowMinWage52', 'srvNotifRelationProof',
  'SRV_PERMANENT_RESTRICTION_MS', 'srvTaxIdentityFingerprint',
  'callableApproveResignation', 'callableRejectResignation', 'callableApproveTermination', 'srvHomeResignRequest', 'srvResignDerivedFields',
  'srvNsDeliverPendingAlert',
];
const {exports: X, info} = loadIndexClosure(ROOTS, F, {HttpsError, console: QCON, Date: FakeDate});
console.log('[폐포] ' + info);
const SRC = fs.readFileSync(path.join(__dirname, '..', 'src', 'index.ts'), 'utf8');
const TCP = require(path.join(__dirname, '..', 'lib', 'terms_consent_payload.js'));

const Ts = F.Ts;
const DAY = 24 * 3600 * 1000;
const call = (fn, data, uid) => fn({data, auth: uid ? {uid, token: {}} : undefined});
async function rejects(p, pred, label) {
  try { await p; } catch (e) {
    const code = e.details && (e.details.code || e.details.reason);
    if (typeof pred === 'string') assert.ok(code === pred || e.code === pred, `${label}: 기대 ${pred} · 실제 ${e.code}/${code} ${e.message}`);
    else assert.ok(pred(e), `${label}: 실제 ${e.code} ${e.message}`);
    return e;
  }
  throw new Error(`${label}: 거절 기대 — 성공함`);
}
const bodyOf = (name) => {
  const i = SRC.indexOf(`export const ${name} = `);
  assert.ok(i > 0, name);
  const j = SRC.indexOf('\nexport const ', i + 10);
  return SRC.slice(i, j < 0 ? undefined : j);
};
const docsUnder = (prefix) => Object.keys(F.dump()).filter((k) => k.startsWith(prefix + '/'));
function seedSA(uid = 'sa1') { F.put('users/' + uid, {role: 'SUPER_ADMIN', accountStatus: 'active', name: 'SA'}); }
function seedMigratedUser(uid, o = {}) {
  const ledger = o.ledger || {};
  const dates = Object.values(ledger).map((e) => e.at).sort((a, b) => a.toMillis() - b.toMillis());
  F.put('users/' + uid, Object.assign({
    role: 'USER', accountStatus: 'active', name: '근로자',
    noShowPenaltyLedger: ledger, noShowCount: dates.length, recentNoShowCount: dates.length, noShowDates: dates,
    noShowLedgerSync: {count: dates.length, datesMs: dates.map((t) => t.toMillis())},
    noShowLedgerMigratedAt: new Ts(NOW - 30 * DAY),
  }, o.extra || {}));
}

// ── 1. 노쇼 원장·제한 성분 ─────────────────────────────────────────────────
test('NS-01 ResetPenalty — 자동 제한만 지우고 수동(base) 제한은 남긴다 · 감사에 보존 base 기록', async () => {
  seedSA();
  const base = new Ts(NOW + 30 * DAY);
  const auto = new Ts(NOW + DAY);
  const ledger = {};
  for (let i = 0; i < 3; i++) ledger[`app${i}__2026112${i}`] = {at: new Ts(NOW - (i + 1) * DAY), source: 'trigger', day: `2026112${i}`, applicationId: `app${i}`};
  seedMigratedUser('w1', {ledger, extra: {restrictionParts: {base, baseSource: 'manual', auto},
    restrictedUntil: base, restrictionSource: 'manual'}});
  const out = await call(X.callableResetPenalty, {targetUid: 'w1'}, 'sa1');
  assert.deepStrictEqual(out, {success: true});
  const u = F.get('users/w1');
  assert.strictEqual(u.restrictedUntil.toMillis(), base.toMillis(), '수동 제한 만료 시각 유지');
  assert.strictEqual(u.restrictionSource, 'manual');
  assert.ok(u.restrictionParts.base && !u.restrictionParts.auto, 'auto 성분만 제거');
  assert.strictEqual(u.noShowCount, 0);
  assert.deepStrictEqual(Object.keys(u.noShowPenaltyLedger || {}), []);
  const audits = docsUnder('penalty_reset_audit_log');
  assert.strictEqual(audits.length, 1);
  const a = F.get(audits[0]);
  assert.strictEqual(a.baseRestrictionKept.toMillis(), base.toMillis());
  assert.strictEqual(a.resetLedgerKeys.length, 3);
});

test('NS-02 ResetPenalty — 리셋할 것이 없으면 noop(감사·해제 시각 덮어쓰기 0)', async () => {
  const before = docsUnder('penalty_reset_audit_log').length;
  const relAt = F.get('users/w1').restrictionReleasedAt;
  const out = await call(X.callableResetPenalty, {targetUid: 'w1'}, 'sa1');
  assert.deepStrictEqual(out, {success: true, noop: true});
  assert.strictEqual(docsUnder('penalty_reset_audit_log').length, before);
  assert.deepStrictEqual(F.get('users/w1').restrictionReleasedAt, relAt);
});

test('NS-03 ResetPenalty — 전환 운영 시험 SA 는 리셋 거절(CUTOVER_OPERATOR_NO_RESET)', async () => {
  seedSA('qa-cutover-sa-20261023');
  await rejects(call(X.callableResetPenalty, {targetUid: 'w1'}, 'qa-cutover-sa-20261023'), 'CUTOVER_OPERATOR_NO_RESET', 'NS-03');
});

test('NS-04 SetManualRestriction — 전환 완료 전 거절 · 완료 뒤 base 설정 + 감사 · 같은 requestId 재생', async () => {
  seedSA();
  seedMigratedUser('w2');
  const req = {targetUid: 'w2', untilMs: NOW + 10 * DAY, reason: '운영 조치', requestId: 'req-set-0001', expectedBaseUntilMs: null};
  await rejects(call(X.callableSetManualRestriction, req, 'sa1'), 'TRANSITION_IN_PROGRESS', 'NS-04a');
  F.put('ops_state/noShowTransition', {phase: 'COMPLETE'});
  const out = await call(X.callableSetManualRestriction, req, 'sa1');
  assert.strictEqual(out.success, true);
  const u = F.get('users/w2');
  assert.strictEqual(u.restrictionParts.baseSource, 'manual');
  assert.strictEqual(u.restrictedUntil.toMillis(), NOW + 10 * DAY);
  assert.ok(F.get('restriction_audit_log/req-set-0001'));
  const again = await call(X.callableSetManualRestriction, req, 'sa1');
  assert.strictEqual(again.replayed, true);
});

test('NS-05 ReleaseManualRestriction — 화면 값 불일치 BASE_RESTRICTION_CHANGED · 일치하면 base 만 해제(auto 유지)', async () => {
  const u0 = F.get('users/w2');
  F.put('users/w2', Object.assign(u0, {restrictionParts: Object.assign(u0.restrictionParts, {auto: new Ts(NOW + DAY)})}));
  await rejects(call(X.callableReleaseManualRestriction,
    {targetUid: 'w2', expectedBaseUntilMs: NOW + 9 * DAY, reason: '해제', requestId: 'req-rel-0001'}, 'sa1'),
  'BASE_RESTRICTION_CHANGED', 'NS-05a');
  const out = await call(X.callableReleaseManualRestriction,
    {targetUid: 'w2', expectedBaseUntilMs: NOW + 10 * DAY, reason: '해제', requestId: 'req-rel-0002'}, 'sa1');
  assert.strictEqual(out.success, true);
  const u = F.get('users/w2');
  assert.ok(!u.restrictionParts.base, 'base 해제');
  assert.ok(u.restrictionParts.auto, 'auto 유지');
  assert.strictEqual(u.restrictionSource, 'auto');
});

test('NS-06 srvLedgerUserUpdates — add 는 최근 3건이면 auto 만 갱신, remove 는 auto 만 해제(영구 base 보존)', () => {
  const perm = new Ts(X.SRV_PERMANENT_RESTRICTION_MS);
  const user = {restrictedUntil: perm, restrictionSource: 'permanent'};
  const l3 = {};
  for (let i = 0; i < 3; i++) l3['a' + i] = {at: new Ts(NOW - i * DAY), source: 'trigger'};
  const add = X.srvLedgerUserUpdates(user, l3, 'add');
  assert.strictEqual(add.restrictionParts.baseSource, 'permanent');
  assert.ok(add.restrictionParts.auto, 'auto 성분 생김');
  assert.strictEqual(add.restrictedUntil.toMillis(), perm.toMillis(), '유효 제한 = 늦은 쪽(영구)');
  const rm = X.srvLedgerUserUpdates(Object.assign({}, user, {restrictionParts: add.restrictionParts}), {a0: l3.a0}, 'remove');
  assert.ok(!rm.restrictionParts.auto, 'auto 해제');
  assert.strictEqual(rm.restrictionParts.baseSource, 'permanent', '영구 base 보존');
  assert.strictEqual(rm.noShowCount, 1);
  assert.deepStrictEqual(rm.noShowLedgerSync.count, 1);
});

test('NS-07 srvReadRestrictionParts — 성분 없는 옛 문서: 출처 manual→base · KST 9999→permanent · auto→auto', () => {
  const t = new Ts(NOW + 5 * DAY);
  assert.strictEqual(X.srvReadRestrictionParts({restrictedUntil: t, restrictionSource: 'manual'}).baseSource, 'manual');
  assert.strictEqual(X.srvReadRestrictionParts({restrictedUntil: new Ts(X.SRV_PERMANENT_RESTRICTION_MS)}).baseSource, 'permanent');
  const p = X.srvReadRestrictionParts({restrictedUntil: t, restrictionSource: 'auto'});
  assert.ok(p.auto && !p.base);
});

function seedRelease() {
  const kstMidnight = RealDate.UTC(2026, 10, 24, 15, 0); // 11-25 00:00 KST
  F.put('users/owner1', {role: 'BUSINESS_ADMIN', accountStatus: 'active', name: '사장'});
  F.put('businesses/b1', {ownerId: 'owner1', adminIds: [], name: '가게', isApproved: true});
  F.put('tos/t1', {businessId: 'b1', totalConfirmed: 1, totalRequired: 1, status: 'FULL', type: 'short'});
  F.put('tos/t1/slots/s1', {date: new Ts(kstMidnight), status: 'full', confirmedCount: 1,
    workDetails: [{wdId: 'wd1', workType: '홀', startTime: '09:00', endTime: '18:00', requiredCount: 1, wage: 11000, wageType: 'hourly'}],
    workDetailCounts: {wd1: {confirmedCount: 1}}});
  F.put('applications/ap1', {uid: 'w3', businessId: 'b1', toId: 't1', slotId: 's1', wdId: 'wd1', status: 'CONFIRMED',
    type: 'short', workDate: new Ts(kstMidnight), startTime: '09:00', endTime: '18:00', selectedWorkType: '홀'});
  F.put('attendance/ap1_20261125', {applicationId: 'ap1', userId: 'w3', businessId: 'b1', status: 'NO_SHOW', workDate: new Ts(kstMidnight)});
  F.put('users/w3', {role: 'USER', accountStatus: 'active', name: '근로자3'});
}

test('NS-08 ReleaseNoshowSeat — 사전 확인 뒤 취소가 먼저 좌석을 돌려주면 SEAT_ALREADY_RELEASED(이중 감소 0)', async () => {
  seedRelease();
  let injected = false;
  F.hooks.afterGet = (p, txId) => {
    if (!injected && txId != null && p === 'tos/t1') {
      injected = true;
      const a = F.get('applications/ap1');
      F.put('applications/ap1', Object.assign(a, {status: 'CANCELED', confirmedDecrementedAt: new Ts(NOW)}));
    }
  };
  try {
    await rejects(call(X.callableReleaseNoshowSeat, {applicationId: 'ap1'}, 'owner1'), 'SEAT_ALREADY_RELEASED', 'NS-08');
  } finally { F.hooks.afterGet = null; }
  assert.ok(injected, '경합 주입이 실제로 일어났다');
  assert.strictEqual(F.get('tos/t1').totalConfirmed, 1, 'TO 확정 수 그대로');
  assert.strictEqual(F.get('tos/t1/slots/s1').confirmedCount, 1, '슬롯 확정 수 그대로');
});

test('NS-09 ApplyNoShowPenalty — 장기 지원서(취소 포함)는 지원서 단위 벌점 거절(LONG_TERM_APPLY_PENALTY_BLOCKED)', async () => {
  F.put('applications/lt1', {uid: 'w4', status: 'CANCELED', type: 'long_term', workDays: ['월'], businessId: 'b1',
    workDate: new Ts(NOW - DAY), workEndDate: new Ts(NOW + 60 * DAY)});
  F.put('users/w4', {role: 'USER', accountStatus: 'active'});
  await rejects(call(X.callableApplyNoShowPenalty, {applicationId: 'lt1'}, 'w4'), 'LONG_TERM_APPLY_PENALTY_BLOCKED', 'NS-09');
  assert.strictEqual(F.get('users/w4').noShowCount, undefined, '벌점 쓰기 0');
});

test('NS-10 CancelResignRequest — 철회가 exit_decision_log 에 RESIGN·CANCEL 로 남는다', async () => {
  F.put('applications/rs1', {uid: 'w5', businessId: 'b1', status: 'CONFIRMED', resignStatus: 'PENDING',
    resignRequestedAt: new Ts(NOW - DAY), resignRequestDate: new Ts(NOW + 7 * DAY), resignDecisionCycle: 1});
  F.put('users/w5', {role: 'USER', accountStatus: 'active'});
  await call(X.callableCancelResignRequest, {applicationId: 'rs1'}, 'w5');
  const logs = docsUnder('exit_decision_log');
  assert.deepStrictEqual(logs, ['exit_decision_log/rs1__RESIGN__1__CANCEL']);
  assert.strictEqual(F.get(logs[0]).actor.type, 'WORKER');
  assert.strictEqual(F.get('applications/rs1').resignStatus, null);
});

// ── 2. 최저임금 ────────────────────────────────────────────────────────────
test('MW-01 SetMinimumWages — 비SA 거절 · 고시값 아님(BELOW/NOT_OFFICIAL/UNKNOWN_YEAR) · 충돌 · 성공 + 감사', async () => {
  F.put('users/u9', {role: 'USER', accountStatus: 'active'});
  await rejects(call(X.callableSetMinimumWages, {changes: [{year: 2027, op: 'set', wage: 10700, expected: null}]}, 'u9'), 'permission-denied', 'MW-01a');
  await rejects(call(X.callableSetMinimumWages, {changes: [{year: 2027, op: 'set', wage: 10000, expected: null}]}, 'sa1'), 'BELOW_OFFICIAL', 'MW-01b');
  await rejects(call(X.callableSetMinimumWages, {changes: [{year: 2027, op: 'set', wage: 11000, expected: null}]}, 'sa1'), 'NOT_OFFICIAL', 'MW-01c');
  await rejects(call(X.callableSetMinimumWages, {changes: [{year: 2028, op: 'set', wage: 11000, expected: null}]}, 'sa1'), 'OFFICIAL_UNKNOWN_YEAR', 'MW-01d');
  F.put('settings/wage_config', {minimumWages: {2026: 10320}, insuranceRates: {keep: 1}});
  await rejects(call(X.callableSetMinimumWages, {changes: [{year: 2026, op: 'set', wage: 10320, expected: null}]}, 'sa1'), 'MIN_WAGE_CONFLICT', 'MW-01e');
  const out = await call(X.callableSetMinimumWages, {changes: [{year: 2027, op: 'set', wage: 10700, expected: null}]}, 'sa1');
  assert.strictEqual(out.success, true);
  assert.strictEqual(out.minimumWages['2027'], 10700);
  const cfg = F.get('settings/wage_config');
  assert.strictEqual(cfg.minimumWages['2027'], 10700);
  assert.strictEqual(cfg.minimumWages['2026'], 10320, '다른 연도 유지');
  assert.deepStrictEqual(cfg.insuranceRates, {keep: 1}, '다른 필드 유지');
  const audits = docsUnder('minimum_wage_audit_log');
  assert.strictEqual(audits.length, 1);
  assert.strictEqual(F.get(audits[0]).officialCheck, 'OFFICIAL_MATCH');
});

test('MW-02 공고 helper — 공개 공고의 바뀐 업무만 최저임금 판정 · 미공개는 판정 0 · 묶음 오류 문구/코드', async () => {
  F.put('settings/wage_config', {minimumWages: {2027: 10700}});
  const slot = {date: new Ts(RealDate.UTC(2027, 0, 4, 15))}; // 2027-01-05 KST
  const oldW = [{wdId: 'w1', wageType: 'hourly', wage: 10800, startTime: '09:00', endTime: '18:00', breakMinutes: 60}];
  const lowW = [{wdId: 'w1', wageType: 'hourly', wage: 10500, startTime: '09:00', endTime: '18:00', breakMinutes: 60}];
  const runTx = (fn) => F.db.runTransaction((tx) => fn(tx));
  await runTx((tx) => X.srvAssertChangedWDsMinWageInTx52(tx, {isPublished: false}, slot, oldW, lowW)); // 미공개 → 통과
  await runTx((tx) => X.srvAssertChangedWDsMinWageInTx52(tx, {isPublished: true}, slot, oldW, oldW.map((w) => Object.assign({}, w, {requiredCount: 9})))); // 금액 그대로
  await rejects(runTx((tx) => X.srvAssertChangedWDsMinWageInTx52(tx, {isPublished: true}, slot, oldW, lowW)), 'MIN_WAGE_BELOW', 'MW-02a');
  const docs = [
    {exists: true, get: (k) => ({status: 'open', date: slot.date, workDetails: lowW})[k]},
    {exists: true, get: (k) => ({status: 'closed', date: slot.date, workDetails: lowW})[k]},
  ];
  assert.strictEqual(X.srvSlotEntries52(docs, false).length, 1, '마감 슬롯 제외');
  assert.strictEqual(X.srvSlotEntries52(docs, true).length, 2, '재오픈은 마감 포함');
  const e = await rejects(Promise.resolve().then(() => X.srvThrowMinWage52(
    [{date: '2027-01-05', workType: '홀', reason: 'r1'}, {date: '2027-01-06', workType: null, reason: 'r2'}], ' 업무 임금을 고친 뒤 다시 공개해 주세요.')),
  'MIN_WAGE_BELOW', 'MW-02b');
  assert.ok(e.message.startsWith('2027-01-05 홀: r1 외 1건 업무 임금을'), e.message);
});

test('MW-03 원문 배선 — 공개·재오픈·USWD(단건·일괄)·승인·확정 호출 자리', () => {
  assert.ok(bodyOf('callablePublishTO').includes('" 업무 임금을 고친 뒤 다시 공개해 주세요."'));
  assert.ok(bodyOf('callableReopenSlots').includes('" 업무 임금을 고친 뒤 다시 열어 주세요."'));
  const uswd = bodyOf('callableUpdateSlotWorkDetails');
  assert.strictEqual(uswd.split('await srvAssertChangedWDsMinWageInTx52(tx, toData, slotData, oldWDs, ').length - 1, 2);
  assert.ok(bodyOf('callableApproveApplicationForReview').includes('await srvAssertAppPromiseMinWageInTx52(tx, freshData, "APPROVE");'));
  assert.ok(bodyOf('callableConfirmApplication').includes('await srvAssertAppPromiseMinWageInTx52(tx, fd, "CONFIRM");'));
});

// ── 3. 수동 제한 중 새 약속 차단 · CheckIn ─────────────────────────────────
test('RC-01 srvAssertNoRestrictionForNewCommitment — 제한 중 WORKER_RESTRICTED · 만료 정각 통과', async () => {
  await rejects(Promise.resolve().then(() => X.srvAssertNoRestrictionForNewCommitment({restrictedUntil: new Ts(NOW + 1)}, 'admin')), 'WORKER_RESTRICTED', 'RC-01');
  X.srvAssertNoRestrictionForNewCommitment({restrictedUntil: new Ts(NOW)}, 'admin');
  X.srvAssertNoRestrictionForNewCommitment({}, 'worker');
});

test('RC-02 원문 배선 — 확정·승인·갱신 수락이 같은 거래 users 문서로 제한 판정 · CheckIn 은 기간형 통과/영구만 거절', () => {
  assert.ok(bodyOf('callableConfirmApplication').includes('srvAssertNoRestrictionForNewCommitment(await srvAssertAccountNotFrozenInTx(tx, applicantUid, "근로자"), "admin");'));
  assert.ok(bodyOf('callableApproveApplicationForReview').includes('srvAssertNoRestrictionForNewCommitment(await srvAssertAccountNotFrozenInTx(tx, approveApplicantUid, "근로자"), "admin");'));
  assert.ok(bodyOf('callableAcceptRenewalProposal').includes('srvAssertNoRestrictionForNewCommitment(await srvAssertAccountNotFrozenInTx(tx, callerUid, "사용자"), "worker");'));
  const ci = bodyOf('callableCheckIn');
  assert.ok(!ci.includes('제재 중인 계정입니다. 제재 해제 후 이용 가능합니다.'), '기간형 제재 출근 차단 제거');
  assert.ok(ci.includes('{code: "ACCOUNT_PERMANENTLY_RESTRICTED"}'));
});

// ── 4. 급여 ────────────────────────────────────────────────────────────────
function seedWage() {
  F.put('users/owner2', {role: 'BUSINESS_ADMIN', accountStatus: 'active'});
  F.put('businesses/b2', {ownerId: 'owner2', adminIds: [], name: '가게2'});
  F.put('attendance/att9', {businessId: 'b2', userId: 'w9', wageStatus: 'calculated',
    workDate: new Ts(RealDate.UTC(2026, 10, 19, 15)),
    wageDetail: {netWage: 9000, totalAmount: 10000, additionalAmount: 0, deductionAmount: 0, incomeTaxDeduction: 330}});
}
test('PAY-01 UpdateWageDetail — expectedCurrent 가 저장값과 다르면 WAGE_CHANGED(쓰기 0)', async () => {
  seedWage();
  const before = JSON.stringify(F.get('attendance/att9'));
  const e = await rejects(call(X.callableUpdateWageDetail, {attendanceId: 'att9',
    // [판정295 M2] 정정 맵은 서버 불변식(실수령 = 세전 − 공제)을 만족해야 한다 — 공제 1,000 을 실어 일관된 값으로(의도: 버전 불일치만 본다).
    wageDetailMap: {netWage: 9500, totalAmount: 10500, additionalAmount: 500, incomeTaxDeduction: 1000},
    expectedCurrent: {netWage: 8000, totalAmount: 10000}}, 'owner2'), 'WAGE_CHANGED', 'PAY-01');
  assert.strictEqual(e.details.current.netWage, 9000);
  assert.strictEqual(JSON.stringify(F.get('attendance/att9')), before);
  await rejects(call(X.callableUpdateWageDetail, {attendanceId: 'att9', wageDetailMap: {netWage: 1, totalAmount: 2},
    expectedCurrent: {netWage: 'x'}}, 'owner2'), 'invalid-argument', 'PAY-01b');
});

test('PAY-02 UpdateWageDetail — 같은 기준 값(또는 구 앱: 비교값 없음)은 WAGE_CHANGED 로 막지 않는다', async () => {
  for (const ec of [{netWage: 9000, totalAmount: 10000, incomeTaxDeduction: 330}, undefined]) {
    seedWage();
    try {
      await call(X.callableUpdateWageDetail, Object.assign({attendanceId: 'att9',
        wageDetailMap: {netWage: 9500, totalAmount: 10500, additionalAmount: 500, incomeTaxDeduction: 330}},
      ec ? {expectedCurrent: ec} : {}), 'owner2');
    } catch (e) {
      assert.notStrictEqual(e.details && e.details.code, 'WAGE_CHANGED', '같은 기준인데 WAGE_CHANGED');
    }
  }
});

test('PAY-03 GetPayrollMonthLedgerCounts — 달 전체 숫자(노쇼 0원 제외) · 권한 없는 호출 거절', async () => {
  F.put('users/owner3', {role: 'BUSINESS_ADMIN', accountStatus: 'active'});
  F.put('users/stranger', {role: 'BUSINESS_ADMIN', accountStatus: 'active'});
  F.put('businesses/b3', {ownerId: 'owner3', adminIds: []});
  const rows = [['pending', 'present', 0, 'u1'], ['calculated', 'present', 0, 'u1'], ['confirmed', 'present', 12000, 'u2'],
    ['transferred', 'present', 8000, 'u3'], ['confirmed', 'NO_SHOW', 0, 'u4'], ['confirmed', 'present', 0, 'u5']];
  rows.forEach(([ws, st, fw, u], i) => F.put(`attendance/m${i}`, {businessId: 'b3', yearMonth: '2026-11', wageStatus: ws, status: st, finalWage: fw, userId: u}));
  F.put('attendance/other', {businessId: 'b3', yearMonth: '2026-10', wageStatus: 'confirmed', status: 'present', finalWage: 1, userId: 'u9'});
  const r = await call(X.callableGetPayrollMonthLedgerCounts, {businessId: 'b3', yearMonth: '2026-11'}, 'owner3');
  assert.deepStrictEqual({p: r.pending, n: r.notTransferred, t: r.transferred, pay: r.payout, w: r.workerCount, c: r.complete},
    {p: 2, n: 2, t: 1, pay: 20000, w: 3, c: true});
  await rejects(call(X.callableGetPayrollMonthLedgerCounts, {businessId: 'b3', yearMonth: '2026-11'}, 'stranger'), 'permission-denied', 'PAY-03b');
  await rejects(call(X.callableGetPayrollMonthLedgerCounts, {businessId: 'b3', yearMonth: '2026-13'}, 'owner3'), 'invalid-argument', 'PAY-03c');
});

// ── 5. 범위 밖 의심(병합분) ────────────────────────────────────────────────
test('EXT-01 GetReviewsForUser — 권한 없는 일반 사용자의 타인 리뷰 조회 거절', async () => {
  F.put('users/plain', {role: 'USER', accountStatus: 'active'});
  await rejects(call(X.callableGetReviewsForUser, {targetUserId: 'someone'}, 'plain'), 'permission-denied', 'EXT-01');
});

test('EXT-02 ManageBusiness — 운영 중지 사업장 승인 BUSINESS_DEACTIVATED · 이미 승인은 덮어쓰지 않음 · 검토 뒤 변경 REVIEW_STALE', async () => {
  F.put('businesses/bz1', {name: 'A', isApproved: false, deactivatedAt: new Ts(NOW - DAY)});
  await rejects(call(X.callableManageBusiness, {action: 'approve', businessId: 'bz1'}, 'sa1'), 'BUSINESS_DEACTIVATED', 'EXT-02a');
  const at = new Ts(NOW - 5 * DAY);
  F.put('businesses/bz2', {name: 'B', isApproved: true, approvedAt: at, approvedBy: 'old'});
  const out = await call(X.callableManageBusiness, {action: 'approve', businessId: 'bz2'}, 'sa1');
  assert.deepStrictEqual(out, {success: true, alreadyApproved: true});
  assert.strictEqual(F.get('businesses/bz2').approvedBy, 'old');
  F.put('businesses/bz3', {name: 'C', isApproved: false, businessNumber: '123'});
  await rejects(call(X.callableManageBusiness, {action: 'approve', businessId: 'bz3',
    expected: {licenseUrl: null, businessNumber: '999', name: 'C'}}, 'sa1'), 'REVIEW_STALE', 'EXT-02c');
});

test('EXT-03 createNotification 관계 증명 — 다른 사람 지원서를 가리키면 APPLICATION_MISMATCH · 맞으면 서버가 본문 구성', async () => {
  F.put('applications/n1', {uid: 'wr', businessId: 'bn', status: 'CONFIRMED', selectedWorkType: '홀', workDate: new Ts(RealDate.UTC(2026, 10, 26, 15))});
  const base = {type: 'applicationConfirmed', callerUid: 'adm', businessId: 'bn', rawBody: 'x', callerIsAdmin: true,
    callerIsSubAdminOnly: false, recipientIsAdmin: false, recipientRole: 'USER', callerName: '사장', businessName: '가게N'};
  const bad = await X.srvNotifRelationProof(Object.assign({}, base, {recipientUid: 'other', data: {applicationId: 'n1'}}));
  assert.strictEqual(bad.reason, 'APPLICATION_MISMATCH');
  const ok = await X.srvNotifRelationProof(Object.assign({}, base, {recipientUid: 'wr', data: {applicationId: 'n1'}}));
  assert.strictEqual(ok.reason, 'OK');
  assert.ok(ok.composed.body.includes('가게N의 홀 지원이 승인되었습니다') && ok.composed.body.includes('근무일: 11/27'), ok.composed.body);
  const sys = await X.srvNotifRelationProof(Object.assign({}, base, {type: 'systemNotice', recipientUid: 'wr', data: {}}));
  assert.strictEqual(sys.reason, 'RESERVED_TYPE');
});

test('EXT-04 terms_consent_payload .54 — 같은 발행본 같은 값 재전송은 쓰지 않고, 거부 차단은 같은 발행본 안에서만', () => {
  const item = {id: 'privacy', version: 'v2', revisionId: 'privacy__v2', isRequired: false};
  const same = TCP.sanitizeConsentEntries({entries: [['privacy', {agreed: true, version: 'v2'}]], activeItems: [item],
    existing: {privacy: {agreed: true, version: 'v2', revisionId: 'privacy__v2'}}});
  assert.deepStrictEqual(Object.keys(same.updates), []);
  assert.deepStrictEqual(same.dropped, ['privacy']);
  const newRev = TCP.sanitizeConsentEntries({entries: [['privacy', {agreed: false, version: 'v2'}]], activeItems: [item],
    existing: {privacy: {agreed: true, version: 'v1', revisionId: 'privacy__v1'}}});
  assert.strictEqual(newRev.updates.privacy.agreed, false, '새 판의 거부는 저장');
  const sameRevRevoke = TCP.sanitizeConsentEntries({entries: [['privacy', {agreed: false, version: 'v2'}]], activeItems: [item],
    existing: {privacy: {agreed: true, version: 'v2', revisionId: 'privacy__v2'}}});
  assert.deepStrictEqual(sameRevRevoke.dropped, ['privacy'], '같은 판 동의 → 거부 뒤집기 차단');
  const kakaoSession = TCP.sanitizeConsentEntries({entries: [['privacy', {agreed: true, version: 'v2'}]], activeItems: [item], existing: {}});
  assert.strictEqual(kakaoSession.updates.privacy.revisionId, 'privacy__v2', '카카오 세션(existing {}) 경로 그대로');
});

// ── 6. 공통 래퍼(탈퇴 fence) ───────────────────────────────────────────────
test('FENCE-01 새 callable(수동 제한·이관·최저시급·원장 숫자)도 공통 onCall 을 지난다 — 탈퇴 중 SA 거절', async () => {
  for (const n of ['callableSetManualRestriction', 'callableReleaseManualRestriction', 'callableMigrateNoShowLedger',
    'callableSetMinimumWages', 'callableGetPayrollMonthLedgerCounts']) {
    const b = bodyOf(n);
    assert.ok(b.startsWith(`export const ${n} = onCall(`), n);
    assert.ok(!b.includes('allowDuringAccountDeletion('), n + ' 허용 목록 아님');
  }
  F.put('users/saDel', {role: 'SUPER_ADMIN', accountStatus: 'deleting'});
  F.put('account_deletion_tombstones/saDel', {uid: 'saDel'});
  await rejects(call(X.callableSetMinimumWages, {changes: [{year: 2027, op: 'set', wage: 10700, expected: 10700}]}, 'saDel'),
    (e) => e.details && e.details.reason === 'ACCOUNT_DELETION_IN_PROGRESS', 'FENCE-01');
});

// ── 7. §2차 — 세무 지문 · 새 코호트 등록증 지문 ─────────────────────────────
test('TAX-01 srvTaxIdentityFingerprint — 새 코호트 등록증 지문이 바뀌면 지문이 바뀐다 · 옛 계정(필드 없음) 지문은 그대로', () => {
  const crypto = require('crypto');
  const birth = new Ts(RealDate.UTC(1990, 0, 1));
  const old = {name: '홍길동', birthDate: birth, gender: '남성', foreignIdentityFingerprint: 'oldfp'};
  const expectOld = crypto.createHash('sha256')
    .update(['홍길동', '', String(birth.toMillis()), '남성', 'oldfp', 'R:ABSENT'].join('\0')).digest('hex');
  assert.strictEqual(X.srvTaxIdentityFingerprint(old, undefined), expectOld, '옛 계정 지문 식 불변(검토 일괄 STALE 0)');
  const nu = {name: 'KIM', legalName: 'KIM MINSU', birthDate: birth, gender: '남성', signupSource: 'kakao_v1',
    nationalityStatus: 'foreign', foreignIdDocumentFingerprint: 'docA'};
  const a = X.srvTaxIdentityFingerprint(nu, {identifierFingerprint: 'T1'});
  const b = X.srvTaxIdentityFingerprint(Object.assign({}, nu, {foreignIdDocumentFingerprint: 'docB'}), {identifierFingerprint: 'T1'});
  const none = X.srvTaxIdentityFingerprint(Object.assign({}, nu, {foreignIdDocumentFingerprint: undefined}), {identifierFingerprint: 'T1'});
  assert.notStrictEqual(a, b, '등록증 재등록 → 지문 변화(STALE 근거)');
  assert.notStrictEqual(a, none);
});

// ── 8. §3차 — DEV zip 대조 뒤 병합(10-23 3eaa · 4cbe · 1846 · 9868 · 10-25 · 11-05) ─────────────
function seedExit(id, o) {
  F.put('users/ownerX', {role: 'BUSINESS_ADMIN', accountStatus: 'active'});
  F.put('businesses/bX', {ownerId: 'ownerX', adminIds: [], name: '가게X'});
  F.put('applications/' + id, Object.assign({uid: 'wX', businessId: 'bX', businessName: '가게X', status: 'CONFIRMED'}, o));
}
test('EXIT-01 ApproveResignation — 이미 승인은 쓰기 없이 alreadyApproved · 취소된 지원서 APPLICATION_NOT_ACTIVE · 승인은 APPROVE 이력', async () => {
  seedExit('ex1', {resignStatus: 'APPROVED'});
  const before = JSON.stringify(F.get('applications/ex1'));
  assert.deepStrictEqual(await call(X.callableApproveResignation, {applicationId: 'ex1'}, 'ownerX'), {success: true, alreadyApproved: true});
  assert.strictEqual(JSON.stringify(F.get('applications/ex1')), before);
  seedExit('ex2', {status: 'CANCELED', resignStatus: 'PENDING', resignRequestDate: new Ts(NOW + 3 * DAY), resignDecisionCycle: 2});
  await rejects(call(X.callableApproveResignation, {applicationId: 'ex2'}, 'ownerX'), 'APPLICATION_NOT_ACTIVE', 'EXIT-01b');
  seedExit('ex3', {resignStatus: 'PENDING', resignRequestDate: new Ts(NOW + 3 * DAY), resignDecisionCycle: 2});
  await call(X.callableApproveResignation, {applicationId: 'ex3'}, 'ownerX');
  assert.strictEqual(F.get('applications/ex3').resignStatus, 'APPROVED');
  const log = F.get('exit_decision_log/ex3__RESIGN__2__APPROVE');
  assert.ok(log && log.actor.type === 'ADMIN' && log.actor.uid === 'ownerX', JSON.stringify(log));
});

test('EXIT-02 RejectResignation · ApproveTermination — REJECT/APPROVE 이력 · 해지 재호출 alreadyApproved', async () => {
  seedExit('ex4', {resignStatus: 'PENDING', resignRequestDate: new Ts(NOW + 3 * DAY), resignDecisionCycle: 1});
  await call(X.callableRejectResignation, {applicationId: 'ex4', rejectReason: '인원 부족'}, 'ownerX');
  const rj = F.get('exit_decision_log/ex4__RESIGN__1__REJECT');
  assert.ok(rj && rj.reason === '인원 부족', JSON.stringify(rj));
  seedExit('ex5', {terminationStatus: 'APPROVED'});
  assert.deepStrictEqual(await call(X.callableApproveTermination, {applicationId: 'ex5'}, 'ownerX'), {success: true, alreadyApproved: true});
});

test('EXIT-03 원문 배선 — 요청(퇴사·해지)은 주기 +1 필드와 REQUEST 이력을 같은 거래에 쓴다 · 해지 승인/거절도 이력', () => {
  const rq = bodyOf('callableRequestResignation');
  assert.ok(rq.includes('resignDecisionCycle: srvExitDecisionCycle(data, "RESIGN", "REQUEST"),'));
  assert.ok(rq.includes('srvExitDecisionLogInTx(tx, applicationId, data, "RESIGN", "REQUEST", {type: "WORKER", uid: callerUid}, rqUpd);'));
  const rt = bodyOf('callableRequestTermination');
  assert.ok(rt.includes('terminationDecisionCycle: srvExitDecisionCycle(snap.data(), "TERMINATION", "REQUEST"),'));
  assert.ok(rt.includes('"TERMINATION", "REQUEST"'));
  assert.ok(bodyOf('callableApproveTermination').includes('"TERMINATION", "APPROVE"'));
  assert.ok(bodyOf('callableRejectTermination').includes('"TERMINATION", "REJECT"'));
});

test('HOME-01 srvHomeResignRequest — 소급 요청은 곧 자동 승인이 아니라 직접 확인(manualReviewCount)으로 센다', async () => {
  // [BL284-01 · 판정288 A안 추종] 소급/임박 판정은 요청 거래가 저장한 서버 전용 파생 필드(resignRetroRequest·
  //   resignAutoApproveAt)로 센다 → 시드에도 같은 writer 식(srvResignDerivedFields)으로 넣는다. 세 집계는 read-only 거래의
  //   tx.get(count()) — 이 가짜 저장소는 집계 읽기를 몰라 이 시험 안에서만 얇게 이어 준다. 상세 경계·실패 전파는 resign_agg_1.test.js.
  const midnight = new RealDate(RealDate.UTC(2026, 10, 24, 15)); // 11-25 00:00 KST
  const old = new Ts(midnight.getTime() - 5 * DAY);
  const put = (id, req, eff) => F.put('applications/' + id, Object.assign({businessId: 'bH', resignStatus: 'PENDING',
    resignRequestedAt: req, resignRequestDate: eff}, X.srvResignDerivedFields(eff, req)));
  put('h1', old, new Ts(midnight.getTime() + DAY));
  put('h2', old, new Ts(old.toMillis() - 3 * DAY)); // 소급
  put('h3', new Ts(midnight.getTime()), new Ts(midnight.getTime() + 9 * DAY));
  const orig = F.db.runTransaction;
  F.db.runTransaction = (cb, o) => orig((tx) => cb(Object.assign({}, tx, {
    get: (x) => (x && !x.__kind && typeof x.get === 'function' ? x.get() : tx.get(x))})), o);
  try {
    const r = await X.srvHomeResignRequest('bH', midnight);
    assert.deepStrictEqual(r, {count: 3, soonCount: 1, manualReviewCount: 1});
  } finally { F.db.runTransaction = orig; }
});

test('M3-01 원문 배선 — BatchSetNoShow id 경로 근무일 판정 · 일별 인원 장기 비대상 제외 · 급여 일자 후보 접합 · 송금 알림 호칭', () => {
  assert.ok(bodyOf('callableBatchSetNoShow').includes('노쇼 처리 건너뜀 — 근무일 아님(근태 id 경로'));
  const ds = bodyOf('callableGetDayStaffingDetail');
  assert.ok(ds.includes('if (!srvLongTermEligibleOnDay(ad, dsDayNum, dsDayWkd).eligible) continue;') && ds.includes('rawWDs.length > 1 && dsAnyWdId'));
  assert.ok(bodyOf('callableGetAdminAttendances').includes('return await srvAttachWageDayCandidate(callerUid, request.data, docs, baseResponse);'));
  assert.ok(bodyOf('callableMarkTransferredBatch').includes('급여 이체 처리가 등록됐어요. 내역을 확인해 주세요.'));
});

test('WD-01 wage_day_projection — opt-in 조건 · 관계 검증 · projection 필드(DEV 모듈과 같은 판정)', () => {
  const W = require(path.join(__dirname, '..', 'lib', 'wage_day_projection.js'));
  const day = RealDate.UTC(2026, 10, 24, 15);
  assert.deepStrictEqual(W.wageDayOptIn({purpose: 'wageDay', startMs: day, endMs: day + DAY}, {canManageWage: true}), {ok: true});
  assert.strictEqual(W.wageDayOptIn({purpose: 'wageDay', startMs: day + 1, endMs: day + DAY + 1}, {canManageWage: true}).reason, 'notKstDay');
  assert.strictEqual(W.wageDayOptIn({purpose: 'wageDay', startMs: day, endMs: day + DAY}, {canManageWage: false}).reason, 'notWageAuthority');
  const FTs = require('firebase-admin/firestore').Timestamp;
  const app = {businessId: 'b', uid: 'u', type: 'short', workDate: FTs.fromMillis(day), appliedAt: FTs.fromMillis(day - DAY), wage: 11000, secret: 'x'};
  const att = {id: 'a1', applicationId: 'ap', businessId: 'b', userId: 'u', workDate: FTs.fromMillis(day)};
  const r = W.attachWageDayProjection({req: {purpose: 'wageDay', businessId: 'b', startMs: day, endMs: day + DAY}, caller: {canManageWage: true},
    items: [att, Object.assign({}, att, {id: 'a2', userId: 'v'})], limitReached: false, appsById: new Map([['ap', app]]),
    liveWorkDetailOf: () => ({wd: {startTime: '09:00', endTime: '18:00', wageType: 'hourly', wage: 11000, junk: 1}})});
  assert.ok(r.items[0].wageApplication && !('secret' in r.items[0].wageApplication) && !('junk' in r.items[0].wageWorkDetail));
  assert.strictEqual(r.wageDay.applicationMismatch, 1);
  assert.strictEqual(r.wageDay.mismatchReasons.attendanceBusiness ?? r.wageDay.mismatchReasons.uid, 1);
  assert.strictEqual(r.wageDay.complete, false);
});

// ── 9. §6차 — 원장 보류 경보 알림도 정본 탈퇴 barrier ──────────────────────────
test('NSA-01 srvNsDeliverPendingAlert — 탈퇴 중(tombstone) SA 는 억제 · 아니면 결정적 id 1건 · 재전달은 ALREADY', async () => {
  F.put('noshow_ledger_pending/pA', {uid: 'wP', status: 'OPEN', reason: 'LEGACY_COUNT_DATES_MISMATCH', occurrence: 1});
  F.put('account_deletion_tombstones/saGone', {barrierAt: new Ts(NOW - DAY), schemaVersion: 1});
  const pref = F.db.collection('noshow_ledger_pending').doc('pA');
  assert.strictEqual(await X.srvNsDeliverPendingAlert(pref, 'saGone', 1), 'SUPPRESSED');
  assert.strictEqual(F.get('users/saGone/notifications/ledger_pending_pA__o1'), undefined, '탈퇴 중 수신자에게 쓰기 0');
  assert.deepStrictEqual(F.get('noshow_ledger_pending/pA').alert.suppressed, ['saGone']);
  assert.strictEqual(await X.srvNsDeliverPendingAlert(pref, 'saLive', 1), 'CREATED');
  const n = F.get('users/saLive/notifications/ledger_pending_pA__o1');
  assert.ok(n && n.type === 'noShowLedgerPending', JSON.stringify(n));
  assert.strictEqual(await X.srvNsDeliverPendingAlert(pref, 'saLive', 1), 'ALREADY');
  const body = bodyOf('scheduledNoShowReconcileScan'); void body;
  const fn = SRC.slice(SRC.indexOf('async function srvNsDeliverPendingAlert('), SRC.indexOf('async function srvNsMarkNoRecipient('));
  assert.ok(fn.includes('srvDeletionBarrierExistsInTx(tx, sa)') && fn.includes('srvPersistNotificationInTx(tx, sa, notificationId, payload)'));
  assert.ok(!fn.includes('collection("notifications")'), '알림 컬렉션 직접 쓰기 0');
});

test('ZZ 외부 접근 0', () => { assert.deepStrictEqual(NET, []); });
