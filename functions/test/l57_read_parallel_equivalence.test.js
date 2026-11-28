'use strict';
/**
 * [L57 · 판정291 B7] 순수 읽기 병렬화·중복 제거 동등성 — 같은 입력 → 같은 결과/오류 코드/문구/인가 판정.
 *
 *   이 파일은 시나리오마다 결과 지문(code·message·성공 여부·주요 쓰기)을 L57_OUT 에 JSON 으로 남긴다.
 *   같은 파일을 이전 원문 사본(L57 전 index.ts)에서도 돌려 두 지문을 비교한다(음성/동등 대조 · compare 시험은 env 로).
 *   읽기 수(사업장·멤버·users)는 새 원문에서 줄었는지만 따로 본다.
 */
const {test} = require('node:test');
const assert = require('assert');
const fs = require('fs');
const {createFakeFirestore} = require('./consent_r4d_fakestore');
const {loadIndexClosure} = require('./auth_kakao_index_harness');

const RealDate = Date;
const H = 3600 * 1000; const KST = 9 * H;
const kstMid = (y, m, d) => RealDate.UTC(y, m - 1, d) - KST;
let NOW = kstMid(2026, 11, 26) + 10 * H;
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
const Ts = F.Ts;
const {exports: X} = loadIndexClosure(['callableConfirmApplication', 'callableCalculateAndConfirmWage', 'callableApplyToTO',
  'callableInviteWorker', 'srvWorkRegionKeyOfBusiness', 'callableCheckIn'], F,
  {HttpsError, console: QCON, Date: FakeDate});
const call = (fn, data, uid) => fn({data, auth: uid ? {uid, token: {}} : undefined});
const OUT = {};

async function fingerprint(p) {
  const before = F.W.reads.length;
  try {
    const r = await p;
    return {ok: true, result: JSON.parse(JSON.stringify(r ?? null)), reads: F.W.reads.slice(before)};
  } catch (e) {
    return {ok: false, code: e.code ?? null, message: String(e.message ?? e), reads: F.W.reads.slice(before)};
  }
}
const authReads = (reads) => reads.filter((r) => r.kind === 'doc' &&
  (/^businesses\/[^/]+$/.test(r.path) || /\/members\//.test(r.path) || /^users\/[^/]+$/.test(r.path))).length;

function seedBiz() {
  F.reset();
  F.put('users/own1', {role: 'BUSINESS_ADMIN', accountStatus: 'active', name: '사장', businessId: 'b1'});
  F.put('users/out1', {role: 'BUSINESS_ADMIN', accountStatus: 'active', name: '남'});
  F.put('users/sub1', {role: 'USER', accountStatus: 'active', name: '부', subAdminBusinessIds: ['b1'], subAdminOf: ['b1']});
  F.put('users/sub2', {role: 'USER', accountStatus: 'active', name: '부2', subAdminBusinessIds: ['b1'], subAdminOf: ['b1']});
  F.put('users/w1', {role: 'USER', accountStatus: 'active', name: '근로자'});
  F.put('businesses/b1', {name: '평택 물류', ownerId: 'own1', adminIds: ['own1']});
  F.put('businesses/b2', {name: '다른', ownerId: 'out1', adminIds: ['out1']});
  F.put('businesses/b1/members/sub1', {uid: 'sub1', permissions: {canManageTo: true, canManageWage: true}});
  F.put('businesses/b1/members/sub2', {uid: 'sub2', permissions: {canManageTo: false, canManageWage: false}});
  F.put('applications/a1', {uid: 'w1', businessId: 'b1', toId: 't1', slotId: 's1', status: 'PENDING', type: 'short'});
  F.put('applications/a2', {uid: 'w1', businessId: 'b2', toId: 't2', status: 'PENDING'});
  F.put('applications/aSelf', {uid: 'own1', businessId: 'b1', toId: 't1', status: 'PENDING'});
}

const CONFIRM = [
  ['c1-unauth', {applicationId: 'a1', businessId: 'b1'}, null],
  ['c2-no-biz', {applicationId: 'a1'}, 'own1'],
  ['c3-outsider', {applicationId: 'a1', businessId: 'b1'}, 'out1'],
  ['c3b-outsider-missing-id', {applicationId: 'zzz', businessId: 'b1'}, 'out1'],
  ['c4-sub-no-perm', {applicationId: 'a1', businessId: 'b1'}, 'sub2'],
  ['c5-missing', {applicationId: 'zzz', businessId: 'b1'}, 'own1'],
  ['c6-other-biz', {applicationId: 'a2', businessId: 'b1'}, 'own1'],
  ['c7-self', {applicationId: 'aSelf', businessId: 'b1'}, 'own1'],
  ['c8-owner-proceeds', {applicationId: 'a1', businessId: 'b1'}, 'own1'],
  ['c9-sub-proceeds', {applicationId: 'a1', businessId: 'b1'}, 'sub1'],
];
for (const [id, data, uid] of CONFIRM) {
  test(`CONFIRM ${id}`, async () => {
    seedBiz();
    const fp = await fingerprint(call(X.callableConfirmApplication, data, uid));
    OUT[id] = {ok: fp.ok, code: fp.code ?? null, message: fp.message ?? null, authReads: authReads(fp.reads)};
  });
}

function seedWage() {
  seedBiz();
  F.put('settings/wage_config', {minimumWages: {2026: 10030}});
  F.put('attendance/att1', {applicationId: 'a1', userId: 'w1', businessId: 'b1', workDate: new Ts(kstMid(2026, 11, 20)),
    status: 'CHECKED_OUT', wageStatus: 'pending'});
  F.put('attendance/attNoApp', {applicationId: 'gone', userId: 'w1', businessId: 'b1', workDate: new Ts(kstMid(2026, 11, 20)),
    status: 'CHECKED_OUT', wageStatus: 'pending'});
}
const WBASE = {wageType: 'hourly', baseWage: 12000, workDate: '2026-11-20', scheduledStart: '09:00', scheduledEnd: '18:00',
  actualStart: '09:00', actualEnd: '18:00', breakMinutes: 60, nightAllowanceApplied: true, nightIncluded: false,
  taxDeductionType: 'none', yearMonth: '2026-11'};
const WAGE = [
  ['w1-outsider', 'att1', 'out1'],
  ['w2-sub-no-wage', 'att1', 'sub2'],
  ['w3-app-missing-outsider', 'attNoApp', 'out1'],
  ['w3b-app-missing-owner', 'attNoApp', 'own1'],
  ['w4-owner', 'att1', 'own1'],
  ['w5-sub-ok', 'att1', 'sub1'],
  ['w6-att-missing', 'nope', 'own1'],
];
for (const [id, att, uid] of WAGE) {
  test(`WAGE ${id}`, async () => {
    seedWage();
    const fp = await fingerprint(call(X.callableCalculateAndConfirmWage, Object.assign({attendanceId: att}, WBASE), uid));
    const a = F.get('attendance/att1');
    OUT[id] = {ok: fp.ok, code: fp.code ?? null, message: fp.message ?? null, authReads: authReads(fp.reads),
      wageStatus: a?.wageStatus ?? null, finalWage: a?.finalWage ?? null};
  });
}

// ── [L57 r2] callableApplyToTO 사전 읽기 묶음 ─────────────────────────────────────
function seedApply() {
  seedBiz();
  F.put('app_settings/legal_terms', {items: []});
  const docs = {isIdVerified: true, idCardImagePath: 'users/x/id.png', bankName: '국민', accountNumber: '1', accountHolder: '근로자',
    bankbookImagePath: 'users/x/bb.png', termsConsent: {}, passVerifiedAt: new Ts(kstMid(2026, 1, 1)), ciHash: 'ci'};
  F.put('users/w1', Object.assign({role: 'USER', accountStatus: 'active', name: '근로자'}, docs));
  F.put('users/own1', Object.assign(F.get('users/own1'), docs));
  F.put('tos/t1', {businessId: 'b1', isPublished: true, status: 'ACTIVE', type: 'short', title: '단기'});
  F.put('tos/t1/slots/s1', {status: 'open', date: new Ts(kstMid(2026, 12, 1)), workDetails: [{wdId: 'wd1', workType: '포장',
    startTime: '09:00', endTime: '18:00', requiredCount: 2, wage: 12000, wageType: 'hourly'}]});
  F.put('tos/tDel', {businessId: 'b1', isPublished: true, status: 'ACTIVE', isDeleted: true});
  F.put('tos/tDraft', {businessId: 'b1', isPublished: false, status: 'DRAFT'});
  F.put('tos/tOther', {businessId: 'b2', isPublished: true, status: 'ACTIVE'});
  F.put('tos/tNoBiz', {businessId: 'bGone', isPublished: true, status: 'ACTIVE'});
}
const AB = {slotId: 's1', selectedWorkType: '포장', workDetailId: 'wd1', workDateMs: kstMid(2026, 12, 1),
  startTime: '09:00', endTime: '18:00', wage: 12000, wageType: 'hourly',
  idCardConsentGiven: true, documentAccessConsentGiven: true, documentAccessConsentVersion: '2026-11-18-v4'};
const APPLY = [
  ['a1-unauth', Object.assign({toId: 't1', businessId: 'b1'}, AB), null],
  ['a2-no-user', Object.assign({toId: 't1', businessId: 'b1'}, AB), 'ghost'],
  ['a3-to-missing', Object.assign({toId: 'tNone', businessId: 'b1'}, AB), 'w1'],
  ['a4-to-deleted', Object.assign({toId: 'tDel', businessId: 'b1'}, AB), 'w1'],
  ['a5-to-draft', Object.assign({toId: 'tDraft', businessId: 'b1'}, AB), 'w1'],
  ['a6-biz-mismatch', Object.assign({toId: 'tOther', businessId: 'b1'}, AB), 'w1'],
  ['a7-biz-missing', Object.assign({toId: 'tNoBiz', businessId: 'bGone'}, AB), 'w1'],
  ['a8-admin-conflict', Object.assign({toId: 't1', businessId: 'b1'}, AB), 'own1'],
  ['a9-proceeds', Object.assign({toId: 't1', businessId: 'b1'}, AB), 'w1'],
  ['a10-bad-toid', Object.assign({toId: 'x/y', businessId: 'b1'}, AB), 'w1'],
];
for (const [id, data, uid] of APPLY) {
  test(`APPLY ${id}`, async () => {
    seedApply();
    const fp = await fingerprint(call(X.callableApplyToTO, data, uid));
    const usersReads = fp.reads.filter((r) => r.kind === 'doc' && r.path === `users/${uid}`).length;
    const bizReads = fp.reads.filter((r) => r.kind === 'doc' && /^businesses\/[^/]+$/.test(r.path)).length;
    OUT[id] = {ok: fp.ok, code: fp.code ?? null, message: fp.message ?? null, authReads: usersReads + bizReads,
      wageStatus: null, finalWage: null};
  });
}

// ── [L57 r3] callableInviteWorker 사전 읽기 묶음 + 사업장 문서 재사용 ───────────────
const POLICY7 = {earlyWindow: 30, earlyArrivalUnit: 30, lateGrace: 5, lateUnit: 30, lateWindow: 30, overtimeUnit: 10, earlyLeaveUnit: 30};
const BIZ_POLICY = {attendanceRules: Object.assign({policySource: 'ALFIT_DEFAULT'}, POLICY7),
  attendancePolicyConfirmation: Object.assign({confirmedAt: new Ts(kstMid(2026, 11, 1)), confirmedBy: 'own1', actorRole: 'business_admin'}, POLICY7)};
const IWD = kstMid(2026, 12, 1);
const IDATE = '2026-12-01';
function seedInvite() {
  seedBiz();
  F.put('app_settings/legal_terms', {items: []});
  F.put('businesses/b1', Object.assign(F.get('businesses/b1'), {address: '경기도 평택시 포승읍 1', city: '평택시', isApproved: true}, BIZ_POLICY));
  F.put('businesses/b3', Object.assign({name: '지역없음', ownerId: 'own3', adminIds: ['own3']}, BIZ_POLICY));
  F.put('users/own3', {role: 'BUSINESS_ADMIN', accountStatus: 'active', name: '사장3'});
  F.put('users/su1', {role: 'SUPER_ADMIN', accountStatus: 'active', name: '운영'});
  const rk = X.srvWorkRegionKeyOfBusiness(F.get('businesses/b1'));
  const worker = {role: 'USER', accountStatus: 'active', name: '근로자', isIdVerified: true, idCardImagePath: 'users/x/id.png',
    passVerifiedAt: new Ts(kstMid(2026, 1, 1))};
  for (const u of ['w1', 'w2', 'w3', 'w4', 'w5']) F.put(`users/${u}`, Object.assign({}, worker));
  F.put('worker_availability/w1', {inviteEnabled: true, inviteRegionKeys: [rk], dates: [IDATE]});
  F.put('worker_availability/w3', {inviteEnabled: true, inviteRegionKeys: ['다른#지역'], dates: [IDATE]});
  F.put('worker_availability/w4', {inviteEnabled: true, inviteRegionKeys: [rk], dates: [IDATE]});
  F.put('worker_availability/w5', {inviteEnabled: true, inviteRegionKeys: [rk], dates: ['2026-12-02']});
  F.put('applications/dup4', {uid: 'w4', toId: 't1', businessId: 'b1', status: 'INVITED', workDetailId: 'wd1'});
  F.put('tos/t1', {businessId: 'b1', isPublished: true, status: 'ACTIVE', type: 'short', title: '단기', totalRequired: 2, totalConfirmed: 0, totalPending: 0});
  F.put('tos/t1/slots/s1', {status: 'open', date: new Ts(IWD), confirmedCount: 0, pendingCount: 0,
    workDetailCounts: {wd1: {confirmedCount: 0, pendingCount: 0}},
    workDetails: [{wdId: 'wd1', workType: '포장', startTime: '09:00', endTime: '18:00', requiredCount: 2, wage: 12000, wageType: 'hourly', breakMinutes: 60}]});
  F.put('tos/tOther', {businessId: 'b2', isPublished: true, status: 'ACTIVE'});
  F.put('tos/t3', {businessId: 'b3', isPublished: true, status: 'ACTIVE', type: 'short'});
  F.put('tos/t3/slots/s1', F.get('tos/t1/slots/s1'));
}
const IB = {slotId: 's1', workDate: new RealDate(IWD).toISOString(), selectedWorkType: '포장'};
const INVITE = [
  ['i1-unauth', {toId: 't1', businessId: 'b1', targetUid: 'w1'}, null],
  ['i2-outsider', {toId: 't1', businessId: 'b1', targetUid: 'w1'}, 'out1'],
  ['i3-sub-no-perm', {toId: 't1', businessId: 'b1', targetUid: 'w1'}, 'sub2'],
  ['i4-self', {toId: 't1', businessId: 'b1', targetUid: 'own1'}, 'own1'],
  ['i5-target-missing', {toId: 't1', businessId: 'b1', targetUid: 'ghost'}, 'own1'],
  ['i6-target-admin', {toId: 't1', businessId: 'b1', targetUid: 'out1'}, 'own1'],
  ['i7-to-missing', {toId: 'tNone', businessId: 'b1', targetUid: 'w1'}, 'own1'],
  ['i8-to-other-biz', {toId: 'tOther', businessId: 'b1', targetUid: 'w1'}, 'own1'],
  ['i9-slot-missing', {toId: 't1', businessId: 'b1', targetUid: 'w1', slotId: 'sNone'}, 'own1'],
  ['i10-no-availability', {toId: 't1', businessId: 'b1', targetUid: 'w2'}, 'own1'],
  ['i11-region-not-allowed', {toId: 't1', businessId: 'b1', targetUid: 'w3'}, 'own1'],
  ['i12-date-not-registered', {toId: 't1', businessId: 'b1', targetUid: 'w5'}, 'own1'],
  ['i13-dup-invited', {toId: 't1', businessId: 'b1', targetUid: 'w4'}, 'own1'],
  ['i14-owner-proceeds', {toId: 't1', businessId: 'b1', targetUid: 'w1'}, 'own1'],
  ['i15-sub-proceeds', {toId: 't1', businessId: 'b1', targetUid: 'w1'}, 'sub1'],
  ['i16-bad-target', {toId: 't1', businessId: 'b1', targetUid: 'x/y'}, 'own1'],
  ['i17-bad-slot', {toId: 't1', businessId: 'b1', targetUid: 'w1', slotId: 'x/y'}, 'own1'],
  ['i18-super-biz-missing', {toId: 't1', businessId: 'bGone', targetUid: 'w1'}, 'su1'],
  ['i19-region-unresolved', {toId: 't3', businessId: 'b3', targetUid: 'w1'}, 'own3'],
  ['i20-bad-toid', {toId: 'x/y', businessId: 'b1', targetUid: 'w1'}, 'own1'],
  // 여러 판정이 동시에 실패하면 예전 순서(대상 → 공고 → 슬롯 → 초대 설정 → 중복)의 첫 오류가 나와야 한다.
  ['i21-target-and-to-missing', {toId: 'tNone', businessId: 'b1', targetUid: 'ghost', slotId: 'sNone'}, 'own1'],
  ['i22-to-and-slot-missing', {toId: 'tNone', businessId: 'b1', targetUid: 'w2', slotId: 'sNone'}, 'own1'],
  ['i23-no-av-and-dup', {toId: 't1', businessId: 'b1', targetUid: 'w2'}, 'own1', () => F.put('applications/dup2', {uid: 'w2', toId: 't1', businessId: 'b1', status: 'INVITED'})],
];
const invitedApps = () => [...F.STORE.keys()].filter((k) => /^applications\/[^/]+$/.test(k) && k !== 'applications/dup4' && k !== 'applications/dup2' &&
  F.get(k).status === 'INVITED').map((k) => {
  const d = F.get(k); return {id: k, uid: d.uid, toId: d.toId, slotId: d.slotId ?? null, wage: d.wage ?? null, wageType: d.wageType ?? null,
    workDetailId: d.workDetailId ?? null, startTime: d.startTime ?? null, endTime: d.endTime ?? null};
});
for (const [id, data, uid, extra] of INVITE) {
  test(`INVITE ${id}`, async () => {
    seedInvite();
    if (extra) extra();
    const fp = await fingerprint(call(X.callableInviteWorker, Object.assign({}, IB, data), uid));
    OUT[id] = {ok: fp.ok, code: fp.code ?? null, message: fp.message ?? null, authReads: authReads(fp.reads),
      wageStatus: null, finalWage: null, invited: invitedApps(), totalReads: fp.reads.length};
  });
}

// ── [L57 r4] callableCheckIn 트랜잭션 안 읽기 — 사전 읽기 뒤 경쟁 상태를 넣어 판정 순서를 본다 ─────────
const CWD = kstMid(2026, 11, 26);
function seedCheckIn() {
  F.reset();
  F.put('users/cw1', {role: 'USER', accountStatus: 'active', name: '출근자'});
  F.put('businesses/cb1', {name: '출근 사업장', attendanceType: 'gps', latitude: 37.0, longitude: 127.0, gpsRadius: 100,
    ownerId: 'co1', adminIds: ['co1']});
  F.put('applications/ca1', {uid: 'cw1', businessId: 'cb1', toId: 'ct1', status: 'CONFIRMED', type: 'short', selectedWorkType: '분류',
    wage: 12000, wageType: 'hourly', workDate: new Ts(CWD), startTime: '09:30', endTime: '18:00'});
  F.put('employment_contracts/cc1', {status: 'completed', workerId: 'cw1', businessId: 'cb1', applicationId: 'ca1', applicationIds: ['ca1'],
    slots: [], employerSignedAt: new Ts(CWD - 86400000), workerSignedAt: new Ts(CWD - 86400000)});
}
const RACE = {
  frozen: () => F.put('users/cw1', Object.assign(F.get('users/cw1'), {accountStatus: 'deleting'})),
  bizClosed: () => F.put('businesses/cb1', Object.assign(F.get('businesses/cb1'), {deactivatedAt: new Ts(CWD - 86400000)})),
  attendance: () => F.put('attendance/ca1_20261126', {userId: 'cw1', applicationId: 'ca1', status: 'checked_in', checkIn: new Ts(NOW - 60000)}),
  appCanceled: () => F.put('applications/ca1', Object.assign(F.get('applications/ca1'), {status: 'CANCELED'})),
  contractVoid: () => F.put('employment_contracts/cc1', Object.assign(F.get('employment_contracts/cc1'), {status: 'voided'})),
};
const CI = {applicationId: 'ca1', businessId: 'cb1', businessName: '출근 사업장', workType: '분류', workDateMs: CWD,
  latitude: 37.0, longitude: 127.0, method: 'gps'};
const CHECKIN = [
  ['k1-unauth', {}, null, []],
  ['k2-user-missing', {}, 'ghost', []],
  ['k3-app-missing', {applicationId: 'nope'}, 'cw1', []],
  ['k4-race-frozen', {}, 'cw1', ['frozen']],
  ['k5-race-biz-closed', {}, 'cw1', ['bizClosed']],
  ['k6-race-attendance', {}, 'cw1', ['attendance']],
  ['k7-race-app-canceled', {}, 'cw1', ['appCanceled']],
  ['k8-race-contract-void', {}, 'cw1', ['contractVoid']],
  ['k9-race-frozen-biz-att', {}, 'cw1', ['frozen', 'bizClosed', 'attendance']],
  ['k10-race-biz-att', {}, 'cw1', ['bizClosed', 'attendance']],
  ['k11-race-att-app', {}, 'cw1', ['attendance', 'appCanceled']],
  ['k12-race-app-contract', {}, 'cw1', ['appCanceled', 'contractVoid']],
  ['k13-race-frozen-contract', {}, 'cw1', ['frozen', 'contractVoid']],
  ['k14-proceeds', {}, 'cw1', []],
  ['k15-already-checked-in', {}, 'cw1', [], () => RACE.attendance()],
];
for (const [id, data, uid, races, pre] of CHECKIN) {
  test(`CHECKIN ${id}`, async () => {
    seedCheckIn();
    if (pre) pre();
    if (races.length) {
      // 트랜잭션 밖 사전 읽기 3건(사용자·지원서·사업장)이 끝난 직후 경쟁 상태를 넣는다.
      F.hooks.afterGet = (p, txId) => {
        if (txId == null && p === 'businesses/cb1') { F.hooks.afterGet = null; for (const r of races) RACE[r](); }
      };
    }
    const fp = await fingerprint(call(X.callableCheckIn, Object.assign({}, CI, data), uid));
    F.hooks.afterGet = null;
    const att = [...F.STORE.keys()].filter((k) => k.startsWith('attendance/')).sort();
    OUT[id] = {ok: fp.ok, code: fp.code ?? null, message: fp.message ?? null, authReads: authReads(fp.reads),
      wageStatus: null, finalWage: null, invited: att.map((k) => ({id: k, status: F.get(k).status ?? null}))};
  });
}

test('OUT 기록', () => {
  if (process.env.L57_OUT) fs.writeFileSync(process.env.L57_OUT, JSON.stringify(OUT, null, 2));
  assert.ok(Object.keys(OUT).length === CONFIRM.length + WAGE.length + APPLY.length + INVITE.length + CHECKIN.length);
});

if (process.env.L57_COMPARE) {
  test('EQ 이전 원문과 결과·오류 코드·문구·저장이 같고 인가 읽기는 같거나 적다', () => {
    const old = JSON.parse(fs.readFileSync(process.env.L57_COMPARE, 'utf8'));
    for (const k of Object.keys(OUT)) {
      const a = old[k]; const b = OUT[k];
      assert.ok(a, `${k} 이전 결과 없음`);
      assert.deepStrictEqual({ok: b.ok, code: b.code, message: b.message, wageStatus: b.wageStatus, finalWage: b.finalWage},
        {ok: a.ok, code: a.code, message: a.message, wageStatus: a.wageStatus, finalWage: a.finalWage}, k);
      // [L57 r3] 초대는 만들어진 INVITED 지원서(대상·공고·슬롯·임금·업무·시각)까지 같아야 한다.
      if ('invited' in a || 'invited' in b) assert.deepStrictEqual(b.invited, a.invited, `${k} 초대 결과`);
      // 공고 판정에서 끝나는 지원 경로는 공고·사업장 병렬 출발로 사업장 읽기 1건이 늘 수 있다(지원자 판정 통과 뒤 · 응답 동일).
      const slack = /^a(3|4|5|6|10)-/.test(k) ? 1 : 0;
      assert.ok(b.authReads <= a.authReads + slack, `${k} 인가 읽기 ${a.authReads}→${b.authReads}`);
    }
  });
}
