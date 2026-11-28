'use strict';
/**
 * [AUD-1 A11 · A8] 알림 본인 수신 fan-out · contractRequested 관계/속도 제한 · 일괄 퇴근 입력 · 누적 근무시간 트리거 입력.
 *   S295A_EXPECT_OLD=1 이면 이전 원문 사본에서 결함을 재현한다. 정상 셀은 같은 결과(동치).
 */
const {test} = require('node:test');
const assert = require('assert');
const {createFakeFirestore} = require('./consent_r4d_fakestore');
const {loadIndexClosure} = require('./auth_kakao_index_harness');

const OLD = process.env.S295A_EXPECT_OLD === '1';
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
const {exports: X} = loadIndexClosure(['createNotification', 'callableBatchCheckOut', 'onAttendanceWageStatusChanged'],
  F, {HttpsError, console: QCON, Date: FakeDate});
const Ts = F.Ts;
const go = async (fn, data, uid) => {
  try { return {ok: true, r: await fn({data, auth: {uid, token: {}}})}; } catch (e) { return {ok: false, e}; }
};
const code = (o) => o.e && ((o.e.details && o.e.details.code) || o.e.code);
const notifsOf = (uid) => Object.keys(F.dump()).filter((k) => k.startsWith(`users/${uid}/notifications/`)).length;

function base() {
  F.reset();
  F.put('users/own1', {role: 'BUSINESS_ADMIN', accountStatus: 'active', name: '사장'});
  F.put('businesses/b1', {name: '평택', ownerId: 'own1', adminIds: ['own1'], isApproved: true});
  F.put('users/atk', {role: 'USER', accountStatus: 'active', name: '공격자'});
  F.put('businesses/b9', {name: '무관 사업장', ownerId: 'own9', adminIds: ['own9'], isApproved: true});
  F.put('users/own9', {role: 'BUSINESS_ADMIN', accountStatus: 'active', name: '사장9'});
  F.put('users/s9', {role: 'USER', accountStatus: 'active', name: '서브', subAdminBusinessIds: ['b9']});
  F.put('businesses/b9/members/s9', {permissions: {canManageContract: true, canManageTo: true}});
}

// ═════════════ A11 ═════════════
test('N1 무관한 근로자 · 본인 수신 · contractRequested · 임의 사업장 — 거절 · 그 사업장 서브관리자 알림 0', async () => {
  base();
  const rs = [];
  for (let i = 0; i < 5; i++) {
    rs.push(await go(X.createNotification, {userId: 'atk', type: 'contractRequested', title: '계약서 확인 요청',
      body: `[공지] 아래 링크에서 계좌를 다시 등록하세요 #${i}`, data: {businessId: 'b9'}}, 'atk'));
  }
  if (OLD) { assert.strictEqual(notifsOf('s9'), 5, '음성 대조: 이전 원문은 무관 사업장 서브관리자에게 5건 복제'); return; }
  assert.ok(rs.every((r) => !r.ok));
  assert.strictEqual(code(rs[0]), 'CONTRACT_REQUEST_APPLICATION_REQUIRED');
  assert.strictEqual(notifsOf('s9'), 0);
});

test('N2 본인 수신 · fan-out 유형(applicationCanceled) · 임의 사업장 — 본인 알림만 · fan-out 0', async () => {
  base();
  const o = await go(X.createNotification, {userId: 'atk', type: 'applicationCanceled', title: '안내', body: '피싱',
    data: {businessId: 'b9'}}, 'atk');
  assert.ok(o.ok, o.e && o.e.message);
  assert.strictEqual(notifsOf('atk'), 1);
  assert.strictEqual(notifsOf('s9'), OLD ? 1 : 0);
});

test('N3 contractRequested — 다른 사업장 지원서로는 거절 · 본인 지원서도 다른 사업장 businessId 면 거절', async () => {
  base();
  F.put('applications/ax', {uid: 'atk', businessId: 'b1', status: 'CONFIRMED'});
  const o = await go(X.createNotification, {userId: 'own9', type: 'contractRequested', title: '요청', body: 'x',
    data: {businessId: 'b9', applicationId: 'ax'}}, 'atk');
  assert.ok(!o.ok);
  if (OLD) return;
  assert.ok(['CONTRACT_REQUEST_APPLICATION_MISMATCH', 'permission-denied', 'not-found'].includes(code(o)), code(o));
  assert.strictEqual(notifsOf('own9'), 0);
  assert.strictEqual(notifsOf('s9'), 0);
});

test('N4 contractRequested 도 속도 제한 기록', async () => {
  base();
  F.put('applications/ax', {uid: 'atk', businessId: 'b9', status: 'CONTRACT_PENDING'});
  await go(X.createNotification, {userId: 'own9', type: 'contractRequested', title: '계약서 작성 요청', body: 'x',
    data: {businessId: 'b9', applicationId: 'ax'}}, 'atk');
  const rl = F.get('rate_limits/notifications_atk');
  if (OLD) { assert.strictEqual(rl, undefined, '음성 대조: 이전 원문은 contractRequested 에 속도 제한 0'); return; }
  assert.ok(rl, '속도 제한 문서');
});

// ═════════════ A8 ═════════════
function coBase() {
  base();
  F.put('attendance/att9', {userId: 'w1', businessId: 'b1', applicationId: 'a1', wageStatus: 'pending', status: 'present',
    workDate: new Ts(NOW - 2 * DAY - KST), checkIn: new Ts(NOW - 2 * DAY)});
}
const ci = NOW - 2 * DAY;
const co = (entries) => go(X.callableBatchCheckOut, {businessId: 'b1', entries}, 'own1');
const e9 = (o) => Object.assign({attendanceId: 'att9', checkOutMs: ci + 9 * 3600000, workHours: 8, status: 'present', resetWageDetail: false}, o);
const att9 = () => F.get('attendance/att9');

test('C1 문자열 workHours — 그 항목 실패 · 저장 0', async () => {
  coBase();
  const o = await co([e9({workHours: '100000'})]);
  assert.ok(o.ok);
  if (OLD) { assert.strictEqual(att9().workHours, '100000', '음성 대조: 문자열 그대로 저장'); return; }
  assert.strictEqual(o.r.processed, 0);
  assert.strictEqual(o.r.failures[0].reason, 'invalidWorkHours');
  assert.strictEqual(att9().checkOut, undefined);
});

test('C2 출근보다 이른 퇴근 — 실패(checkOutBeforeCheckIn)', async () => {
  coBase();
  const o = await co([e9({checkOutMs: ci - 5 * 3600000, workHours: 1})]);
  if (OLD) { assert.strictEqual(att9().checkOut.toMillis(), ci - 5 * 3600000); return; }
  assert.strictEqual(o.r.failures[0].reason, 'checkOutBeforeCheckIn');
  assert.strictEqual(att9().checkOut, undefined);
});

test('C3 같은 근태 두 번 — 쓰기 전 전체 거절(DUPLICATE_ATTENDANCE_ID)', async () => {
  coBase();
  const o = await co([e9({}), e9({checkOutMs: ci + 3600000, workHours: 1})]);
  if (OLD) { assert.ok(o.ok, '음성 대조: 이전 원문은 둘 다 처리(마지막 값이 이김)'); return; }
  assert.ok(!o.ok);
  assert.strictEqual(code(o), 'DUPLICATE_ATTENDANCE_ID');
  assert.strictEqual(att9().checkOut, undefined);
});

test('C4 workHours 가 출근~퇴근 경과보다 김 — 실패(workHoursExceedsElapsed)', async () => {
  coBase();
  const o = await co([e9({checkOutMs: ci + 2 * 3600000, workHours: 8})]);
  if (OLD) { assert.strictEqual(att9().workHours, 8); return; }
  assert.strictEqual(o.r.failures[0].reason, 'workHoursExceedsElapsed');
});

test('C5 정상 퇴근 — 처리(동치)', async () => {
  coBase();
  const o = await co([e9({})]);
  assert.ok(o.ok, o.e && o.e.message);
  assert.strictEqual(o.r.processed, 1);
  assert.strictEqual(att9().workHours, 8);
  assert.strictEqual(att9().checkOut.toMillis(), ci + 9 * 3600000);
});

test('T1 누적 근무시간 트리거 — 저장된 workHours 가 문자열이면 누적 0(폴백: workMinutes 숫자)', async () => {
  base();
  F.put('users/w1', {role: 'USER', totalWorkHours: 10, totalWorkDays: 1});
  const before = {userId: 'w1', businessId: 'b1', wageStatus: 'calculated', workHours: '100000'};
  const after = Object.assign({}, before, {wageStatus: 'confirmed', wageDetail: {workMinutes: 480}});
  await X.onAttendanceWageStatusChanged({id: 'ev1', params: {attendanceId: 'at1'},
    data: {before: {data: () => before}, after: {data: () => after}}});
  const u = F.get('users/w1');
  if (OLD) { assert.strictEqual(u.totalWorkHours, 100010, '음성 대조: 문자열 100000 이 누적'); return; }
  assert.strictEqual(u.totalWorkHours, 18, '문자열은 버리고 workMinutes 480 → 8시간');
});
