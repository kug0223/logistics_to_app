'use strict';
/**
 * [server_297] 남은 일 닫기 — §12-5 CreateTO 사업장명 서버 소유 · §12-1 A7 동적 재현(단기 지원 workDays) ·
 *   §12-4 H1 건별 거래 급여 권한 · §12-2 정렬 없는 limit 를 전부처럼 쓰던 판정(미지급 급여 · 실근무 근태 ref).
 *   S297_EXPECT_OLD=1 이면 이전 원문(58175022 · A7 은 s296 전)에서 결함을 재현한다.
 */
const {test} = require('node:test');
const assert = require('assert');
const {createFakeFirestore} = require('./consent_r4d_fakestore');
const {loadIndexClosure} = require('./auth_kakao_index_harness');

const OLD = process.env.S297_EXPECT_OLD === '1';
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
const {exports: X} = loadIndexClosure(['callableCreateTO', 'callableApplyToTO', 'srvAttendancePolicyFingerprint',
  'callableRefreshWagePaymentSnapshot', 'srvCountWorkerUnpaidPayableWages', 'srvActualWorkAttendanceRefs'],
F, {HttpsError, console: QCON, Date: FakeDate});
const Ts = F.Ts;
const go = async (fn, data, uid) => {
  try { return {ok: true, r: await fn({data, auth: {uid, token: {}}})}; } catch (e) { return {ok: false, e}; }
};

test('T1 CreateTO — 클라 businessName(다른 회사)은 저장되지 않고 사업장 문서 이름이 저장된다', async () => {
  F.reset();
  F.put('users/sa1', {role: 'SUPER_ADMIN', accountStatus: 'active', name: '운영'});
  F.put('businesses/b1', {name: '평택', ownerId: 'own1', adminIds: ['own1'], isApproved: true});
  const o = await go(X.callableCreateTO, {toData: {businessId: 'b1', creatorUID: 'sa1', publishMode: 'draft', title: '물류',
    businessName: '다른 회사', type: 'flex', status: 'DRAFT', isPublished: false,
    workDetails: [{workType: '포장', startTime: '09:00', endTime: '18:00', wageType: 'hourly', wage: 12000, requiredCount: 3,
      payScheduleType: 'monthly', payScheduleDay: 10}]}}, 'sa1');
  assert.ok(o.ok, o.e && o.e.message);
  const t = F.get(`tos/${o.r.toId}`);
  if (OLD) { assert.strictEqual(t.businessName, '다른 회사', '음성 대조: 이전 원문은 클라 사업장명을 저장'); return; }
  assert.strictEqual(t.businessName, '평택');
});

const WD = {wdId: 'wd1', workType: '포장', startTime: '09:00', endTime: '18:00', wageType: 'hourly', wage: 12000, requiredCount: 3,
  payScheduleType: 'monthly', payScheduleDay: 10};
function applyBase() {
  F.reset();
  F.put('users/w1', {role: 'USER', accountStatus: 'active', name: '근로자', isIdVerified: true, idCardImagePath: 'users/w1/idCard_1.jpg',
    bankName: 'B', accountNumber: 'E', accountHolder: '근로자', bankbookImagePath: 'users/w1/bankbook_1.jpg', nationalityStatus: 'domestic',
    passVerifiedAt: new Ts(NOW - DAY), termsConsentAt: new Ts(NOW - DAY)});
  F.put('businesses/b1', {name: '평택', ownerId: 'own1', adminIds: ['own1'], isApproved: true,
    attendanceRules: {earlyWindow: 30, earlyArrivalUnit: 30, lateGrace: 5, lateUnit: 30, lateWindow: 30, overtimeUnit: 10, earlyLeaveUnit: 30}});
  F.put('users/own1', {role: 'BUSINESS_ADMIN', accountStatus: 'active', name: '사장', sealBase64: 'x'});
  F.put('businesses/b1/contract_templates/ct1', {templateType: 'daily'});
  F.put('tos/t1', {businessId: 'b1', businessName: '평택', title: '물류', status: 'ACTIVE', type: 'flex', isPublished: true,
    totalPending: 0, totalConfirmed: 0, workDetails: [WD]});
  F.put('tos/t1/slots/s1', {status: 'open', date: new Ts(RealDate.UTC(2026, 11, 1) - 9 * 3600000), workDetails: [WD],
    pendingCount: 0, confirmedCount: 0, workDetailCounts: {wd1: {pendingCount: 0, confirmedCount: 0}}});
}

test('T2 A7 — 단기(슬롯) 지원에 workDays 7개를 실어도 type short · workDays 저장 0', async () => {
  applyBase();
  const o = await go(X.callableApplyToTO, {toId: 't1', slotId: 's1', businessId: 'b1', workDetailId: 'wd1', selectedWorkType: '포장',
    workDateMs: RealDate.UTC(2026, 11, 1) - 9 * 3600000, wage: 12000, startTime: '09:00', endTime: '18:00',
    idCardConsentGiven: true, documentAccessConsentGiven: true, documentAccessConsentVersion: '2026-11-18-v4',
    expectedAttendancePolicy: X.srvAttendancePolicyFingerprint(F.get('businesses/b1').attendanceRules),
    workDays: ['월', '화', '수', '목', '금', '토', '일']}, 'w1');
  assert.ok(o.ok, o.e && o.e.message);
  const a = F.get(`applications/${o.r.applicationId}`);
  if (OLD) { assert.strictEqual(a.type, 'long_term', '음성 대조: 이전 원문은 단기 지원을 장기로 저장'); return; }
  assert.strictEqual(a.type, 'short');
  assert.strictEqual(a.workDays, undefined);
});

test('T3 H1 — 일괄 갱신 도중 급여 권한이 회수되면 남은 건은 쓰지 않는다(permissionRevoked)', async () => {
  F.reset();
  F.put('users/sub1', {role: 'USER', accountStatus: 'active', name: '부', subAdminBusinessIds: ['b1']});
  F.put('businesses/b1', {name: '평택', ownerId: 'own1', adminIds: ['own1'], isApproved: true});
  F.put('businesses/b1/members/sub1', {uid: 'sub1', permissions: {canManageWage: true}});
  F.put('users/w1', {role: 'USER', name: '근로자', bankName: 'B은행', accountNumber: 'ENC-B', accountHolder: '근로자',
    bankbookImagePath: 'users/w1/bankbook.jpg', bankbookMatchStatus: 'MATCHED',
    bankbookMatchDocumentVersion: 1, bankbookMatchAccountVersion: 2, bankbookDocumentVersion: 1, bankAccountVersion: 2});
  for (const id of ['x1', 'x2']) {
    F.put(`attendance/${id}`, {userId: 'w1', businessId: 'b1', applicationId: 'a1', wageStatus: 'confirmed', finalWage: 90000,
      workDate: new Ts(NOW - 3 * DAY), wageAccountBankName: 'A은행'});
  }
  let armed = true;
  F.hooks.afterGet = (p, txId) => {
    if (armed && txId != null && p === 'attendance/x1') {
      armed = false;
      F.put('businesses/b1/members/sub1', {uid: 'sub1', permissions: {canManageWage: false}});
    }
  };
  const o = await go(X.callableRefreshWagePaymentSnapshot, {businessId: 'b1', attendanceIds: ['x1', 'x2']}, 'sub1');
  F.hooks.afterGet = null;
  if (!o.ok) { assert.ok(OLD || false, o.e && o.e.message); return; }
  if (OLD) { assert.notStrictEqual(o.r.skipped.x2, 'permissionRevoked'); return; }
  assert.strictEqual(o.r.skipped.x2, 'permissionRevoked');
  assert.strictEqual(F.get('attendance/x2').wageAccountBankName, 'A은행', '회수 뒤 건은 쓰기 0');
});

test('T4 H3 같은 꼴 — 미지급 급여: 앞 500건이 0원 노쇼여도 뒤의 미지급 1건을 센다(탈퇴 통과 0)', async () => {
  F.reset();
  for (let i = 0; i < 500; i++) {
    F.put(`attendance/n${String(i).padStart(3, '0')}`, {userId: 'w1', wageStatus: 'confirmed', status: 'NO_SHOW', finalWage: 0});
  }
  F.put('attendance/z999', {userId: 'w1', wageStatus: 'confirmed', status: 'present', finalWage: 90000});
  const n = await X.srvCountWorkerUnpaidPayableWages('w1');
  if (OLD) { assert.strictEqual(n, 0, '음성 대조: 이전 원문은 0(첫 페이지만)'); return; }
  assert.strictEqual(n, 1);
});

test('T5 H3 같은 꼴 — 실근무 근태 ref: 근태 25건 중 25번째에만 출근이 있어도 거래 read-set 에 들어간다', async () => {
  F.reset();
  for (let i = 0; i < 24; i++) F.put(`attendance/a1_old${String(i).padStart(2, '0')}`, {applicationId: 'a1', status: 'absent'});
  F.put('attendance/a1_zz', {applicationId: 'a1', checkIn: new Ts(NOW - 5 * DAY), status: 'present', wageStatus: 'confirmed'});
  const refs = await X.srvActualWorkAttendanceRefs('a1', {type: 'long_term'});
  const ids = refs.map((r) => r.id);
  if (OLD) { assert.ok(!ids.includes('a1_zz'), '음성 대조: 이전 원문은 20건만'); return; }
  assert.ok(ids.includes('a1_zz'));
});
