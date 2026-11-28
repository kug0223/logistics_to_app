'use strict';
/**
 * [server_299 · AUD-9 T1–T4] trigger 재시도·해제 경합·오류 삼킴 수리 — 가짜 저장소 + 원문 폐포.
 *   AUD9R_EXPECT_OLD=1 이면 이전 원문(31675a4c)의 결함을 재현하는 쪽으로 기대를 뒤집는다(음성 대조).
 *   I1 초대 수락 trigger — 멤버 행 확인 직후 해제가 커밋되면: 수리 = 배정 0 / 예전 = 해제된 사업장 배정이 되살아남.
 *   I2 같은 이벤트 2회 → 배정 1개(멱등) · 해제 뒤 재전달 → 배정 0(양쪽 같음).
 *   I3 retry 설정 — 수리 = retry:true / 예전 = 없음.
 *   I4 일시 오류 → 재전파(재시도) · 영구 오류 → trigger_failures 기록 후 ACK(수리만).
 *   W1 급여 집계 — retry 설정 · 일시 오류 재전파 뒤 재전달 1회 반영 · 영구 오류 기록 후 ACK(집계 0 · 기록 1).
 *   B1 사업장 생성 — 거래 일시 오류: 수리 = 재전파(재시도) 뒤 재전달 승인 / 예전 = 삼킴·미승인.
 *   B2 등록증 확인 실패(Storage 오류 · CHECK_FAILED) → 수리 = 재전파 / 예전 = 삼킴.
 *   B3 재전달 시점에 운영 중지(deactivatedAt) → 승인 0(수리) · 오래된 이벤트(>1h) → 재판정 0 · 기록.
 *   B4 등록증 없음(MISSING) → 재시도 없이 미승인(정책 그대로 · 양쪽 같음).
 *   A1 assertBizAdmin — users 배정만 있고 멤버 행 없음: 수리 = 거절 / 예전 = 통과. 멤버 행 있음·소유자·adminIds·SUPER_ADMIN 통과 · 무배정 거절(양쪽 같음).
 */
const {test} = require('node:test');
const assert = require('assert');
const fs = require('fs');
const path = require('path');
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
const {exports: X} = loadIndexClosure(['onMemberInvitationAccepted', 'onAttendanceWageChanged', 'onBusinessCreated',
  'assertBizAdmin'], F, {HttpsError, console: QCON, Date: FakeDate});
const Ts = F.Ts;
const OLD = process.env.AUD9R_EXPECT_OLD === '1';
const SRC = fs.readFileSync(path.join(__dirname, '..', 'src', 'index.ts'), 'utf8');
const optsOf = (name) => {
  const i = SRC.indexOf(`export const ${name} = `);
  return SRC.slice(i, SRC.indexOf('async (event)', i));
};
const failures = () => [...F.STORE.keys()].filter((k) => k.startsWith('trigger_failures/'));

const invEv = (id = 'e1') => ({id, params: {invitationId: 'i1'}, data: {
  before: {data: () => ({status: 'pending', targetUid: 's1', businessId: 'b1'})},
  after: {data: () => ({status: 'accepted', targetUid: 's1', businessId: 'b1'})}}});
function invBase() {
  F.reset();
  F.occ.enabled = true;
  F.put('users/s1', {role: 'USER', subAdminBusinessIds: []});
  F.put('businesses/b1/members/s1', {uid: 's1', invitationId: 'i1', permissions: {canManageTo: true}});
}

test('I1 초대 수락 — 멤버 확인 직후 해제가 커밋되면 배정이 되살아나지 않는다', async () => {
  invBase();
  let armed = true;
  F.hooks.afterGet = (p) => {
    if (armed && p === 'businesses/b1/members/s1') {
      armed = false;
      F.del('businesses/b1/members/s1');
      F.put('users/s1', {role: 'USER', subAdminBusinessIds: []});
    }
  };
  await X.onMemberInvitationAccepted(invEv());
  F.hooks.afterGet = null;
  const ids = F.get('users/s1').subAdminBusinessIds;
  if (OLD) { assert.deepStrictEqual(ids, ['b1'], '재현: 해제된 사업장 배정이 되살아남'); return; }
  assert.deepStrictEqual(ids, [], '해제가 먼저 커밋됐으면 배정 0');
});

test('I2 같은 이벤트 2회 → 배정 1개 · 해제 뒤 재전달 → 배정 0', async () => {
  invBase();
  await X.onMemberInvitationAccepted(invEv());
  await X.onMemberInvitationAccepted(invEv());
  assert.deepStrictEqual(F.get('users/s1').subAdminBusinessIds, ['b1']);
  F.del('businesses/b1/members/s1');
  F.put('users/s1', {role: 'USER', subAdminBusinessIds: []});
  await X.onMemberInvitationAccepted(invEv());
  assert.deepStrictEqual(F.get('users/s1').subAdminBusinessIds, []);
});

test('I3 retry 설정', () => {
  const has = /retry:\s*true/.test(optsOf('onMemberInvitationAccepted'));
  assert.strictEqual(has, !OLD);
});

test('I4 일시 오류 재전파 · 영구 오류 기록 후 ACK', async (t) => {
  if (OLD) { t.skip('예전 원문은 거래 밖 update — 같은 주입점이 없다(I3 로 대조)'); return; }
  invBase();
  let fail = 'UNAVAILABLE';
  F.hooks.beforeCommit = () => { if (fail) { const m = fail; fail = null; throw new Error(m); } };
  await assert.rejects(X.onMemberInvitationAccepted(invEv()), /UNAVAILABLE/);
  assert.strictEqual(failures().length, 0);
  await X.onMemberInvitationAccepted(invEv());
  assert.deepStrictEqual(F.get('users/s1').subAdminBusinessIds, ['b1'], '재전달로 부여');
  F.put('users/s1', {role: 'USER', subAdminBusinessIds: []});
  fail = 'INVALID_ARGUMENT 데이터 모양';
  await X.onMemberInvitationAccepted(invEv('e2'));
  F.hooks.beforeCommit = null;
  assert.deepStrictEqual(failures(), ['trigger_failures/onMemberInvitationAccepted__i1']);
  assert.strictEqual(F.get(failures()[0]).businessId, 'b1');
});

const att = (o) => Object.assign({businessId: 'b1', userId: 'w1', workDate: new Ts(NOW - 2 * 86400000), status: 'present', finalWage: 90000}, o);
const wageEv = (id) => ({id, params: {attendanceId: 'a1'}, data: {
  before: {data: () => att({wageStatus: 'calculated'})}, after: {data: () => att({wageStatus: 'confirmed'})}}});

test('W1 급여 집계 — retry · 일시 오류 재전파 뒤 1회 반영 · 영구 오류 기록 후 ACK', async () => {
  assert.strictEqual(/retry:\s*true/.test(optsOf('onAttendanceWageChanged')), !OLD);
  F.reset();
  F.put('users/w1', {name: '근로자'});
  // [server_300 · F298-01 갱신] 집계가 원장(근태 현재 상태) 재집계로 바뀌어, 트리거 시점의 근태 문서를 둔다(운영과 같은 전제).
  F.put('attendance/a1', att({wageStatus: 'confirmed'}));
  let fail = 'UNAVAILABLE';
  F.hooks.beforeCommit = () => { if (fail) { const m = fail; fail = null; throw new Error(m); } };
  await assert.rejects(X.onAttendanceWageChanged(wageEv('evA')), /UNAVAILABLE/, '일시 오류는 양쪽 다 재전파');
  await X.onAttendanceWageChanged(wageEv('evA'));
  await X.onAttendanceWageChanged(wageEv('evA'));
  assert.strictEqual(F.get('payroll_summaries/b1_2026-11').totalPayout, 90000, '재전달 2회 → 1회 반영');
  F.del('payroll_summaries/b1_2026-11');
  F.del('payroll_summaries/b1_2026-11/workers/w1');
  fail = 'INVALID_ARGUMENT 데이터 모양';
  let threw = false;
  try { await X.onAttendanceWageChanged(wageEv('evB')); } catch (_) { threw = true; }
  F.hooks.beforeCommit = null;
  if (OLD) { assert.strictEqual(threw, true); assert.strictEqual(failures().length, 0); return; }
  assert.strictEqual(threw, false, '영구 오류는 ACK');
  assert.deepStrictEqual(failures(), ['trigger_failures/onAttendanceWageChanged__a1__evB']);
  const rec = F.get(failures()[0]);
  // [server_300] 기록 필드가 summaryId(단수) → summaryIds(영향 받는 달 목록)로 바뀌었다(근무일 정정 시 두 달).
  assert.deepStrictEqual(rec.summaryIds ?? [rec.summaryId], ['b1_2026-11']);
});

const LIC = 'https://firebasestorage.googleapis.com/v0/b/fake/o/businesses%2Fb9%2Flicense%2Fx.jpg?alt=media';
function bizBase(o) {
  F.reset();
  F.put('settings/system', {businessAutoApprove: true});
  F.put('businesses/b9', Object.assign({name: 'x', ownerId: 'o9', businessLicenseImageUrl: LIC}, o));
}
const bizEv = (time) => ({id: 'eb', time, params: {businessId: 'b9'},
  data: {data: () => F.get('businesses/b9'), ref: F.db.doc('businesses/b9')}});

test('B1 사업장 생성 — 거래 일시 오류는 재전파 · 재전달로 승인', async () => {
  assert.strictEqual(/retry:\s*true/.test(optsOf('onBusinessCreated')), !OLD);
  bizBase();
  let fail = true;
  F.hooks.beforeCommit = () => { if (fail) { fail = false; throw new Error('UNAVAILABLE'); } };
  let threw = false;
  try { await X.onBusinessCreated(bizEv()); } catch (_) { threw = true; }
  F.hooks.beforeCommit = null;
  assert.strictEqual(fail, false, '주입 발생');
  if (OLD) { assert.strictEqual(threw, false, '재현: 삼킴'); assert.notStrictEqual(F.get('businesses/b9').isApproved, true); return; }
  assert.strictEqual(threw, true, '재전파 → retry');
  await X.onBusinessCreated(bizEv());
  assert.strictEqual(F.get('businesses/b9').isApproved, true);
  assert.strictEqual(failures().length, 0);
});

test('B2 등록증 확인 실패(Storage 오류) → 재전파', async () => {
  bizBase();
  const st = F.admin.storage();
  const orig = st.bucket;
  st.bucket = () => ({name: 'fake', file: () => ({exists: async () => { throw new Error('storage down'); }})});
  let threw = false;
  try { await X.onBusinessCreated(bizEv()); } catch (_) { threw = true; } finally { st.bucket = orig; }
  assert.strictEqual(threw, !OLD, OLD ? '재현: 삼킴' : 'CHECK_FAILED 는 재시도');
  assert.notStrictEqual(F.get('businesses/b9').isApproved, true);
  if (!OLD) { await X.onBusinessCreated(bizEv()); assert.strictEqual(F.get('businesses/b9').isApproved, true, '재전달로 승인'); }
});

test('B3 재전달 시점 운영 중지 → 승인 0 · 1시간 넘은 이벤트 → 재판정 0 · 기록', async (t) => {
  if (OLD) { t.skip('예전 원문은 재시도가 없다(B1 로 대조)'); return; }
  bizBase({deactivatedAt: new Ts(NOW - 1000)});
  await X.onBusinessCreated(bizEv());
  assert.notStrictEqual(F.get('businesses/b9').isApproved, true, '운영 중지 사업장 승인 0');
  bizBase();
  await X.onBusinessCreated(bizEv(new RealDate(NOW - 2 * 3600000).toISOString()));
  assert.notStrictEqual(F.get('businesses/b9').isApproved, true, '오래된 이벤트는 재판정하지 않는다');
  assert.deepStrictEqual(failures(), ['trigger_failures/onBusinessCreated__b9']);
  bizBase();
  await X.onBusinessCreated(bizEv(new RealDate(NOW - 60000).toISOString()));
  assert.strictEqual(F.get('businesses/b9').isApproved, true, '1분 전 이벤트는 정상 처리');
});

test('B4 등록증 없음(MISSING) → 재시도 없이 미승인(정책 그대로)', async () => {
  bizBase({businessLicenseImageUrl: null});
  await X.onBusinessCreated(bizEv());
  assert.notStrictEqual(F.get('businesses/b9').isApproved, true);
  assert.strictEqual(failures().length, 0);
});

test('A1 assertBizAdmin — 하위 관리자는 현재 멤버 행이 있어야 통과', async () => {
  F.reset();
  F.put('businesses/b1', {name: 'b', ownerId: 'own', adminIds: ['adm']});
  F.put('users/own', {role: 'BUSINESS_ADMIN', accountStatus: 'active'});
  F.put('users/adm', {role: 'BUSINESS_ADMIN', accountStatus: 'active'});
  F.put('users/sa', {role: 'SUPER_ADMIN'});
  F.put('users/stale', {role: 'USER', accountStatus: 'active', subAdminBusinessIds: ['b1']});
  F.put('users/legacy', {role: 'USER', accountStatus: 'active', subAdminOf: 'b1'});
  F.put('users/live', {role: 'USER', accountStatus: 'active', subAdminBusinessIds: ['b1']});
  F.put('users/none', {role: 'USER', accountStatus: 'active'});
  F.put('businesses/b1/members/live', {uid: 'live', permissions: {}});
  const ok = async (u) => { await X.assertBizAdmin(u, 'b1'); return true; };
  const denied = async (u) => { try { await X.assertBizAdmin(u, 'b1'); return false; } catch (e) { return e.code === 'permission-denied'; } };
  for (const u of ['own', 'adm', 'sa', 'live']) assert.ok(await ok(u), u);
  assert.ok(await denied('none'));
  if (OLD) {
    assert.ok(await ok('stale'), '재현: 멤버 행 없는 배정만으로 통과');
    assert.ok(await ok('legacy'));
    return;
  }
  assert.ok(await denied('stale'), '멤버 행 없는 배정은 거절');
  assert.ok(await denied('legacy'), '옛 subAdminOf 도 멤버 행이 있어야');
});
