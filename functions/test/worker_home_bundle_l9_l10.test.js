'use strict';
/**
 * [판정289 L9 · L10] 근로자 홈 묶음 callable(서버만) + srvHomeUnclosed 제한 청크 병렬.
 *
 *   A index.ts 원문 폐포(auth_kakao_index_harness.loadIndexClosure) + 가짜 저장소 — 네트워크·실제 Firestore 0.
 *   L9: 섹션 성공(기존 endpoint 와 응답 동일 · parity) · 부분 실패 · 인가 · 세대 echo · 입력 검증 · fence 1회 ·
 *       users 요청 단위 1회 · 읽기 전용(쓰기 0) · 요청 섹션만 실행.
 *   L10: 같은 입력에서 결과가 기준 계산(직렬 원식)과 같다 · 청크 병렬 상한 · 실패 전파 · 3650일 초과 오류 보존.
 *   RA1_L10_NEGCTL=1 이면 srvHomeUnclosed 결과만 출력한다(이전 원문 사본과 같은 fixture 대사용).
 */
process.env.TZ = 'UTC';
const {test} = require('node:test');
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const {createFakeFirestore} = require('./consent_r4d_fakestore');
const {loadIndexClosure} = require('./auth_kakao_index_harness');

const NEG = process.env.RA1_L10_NEGCTL === '1';
const RealDate = Date;
const H = 3600 * 1000; const DAY = 24 * H; const KST = 9 * H;
const kstMid = (y, m, d) => RealDate.UTC(y, m - 1, d) - KST;
let NOW = kstMid(2026, 11, 26) + 10 * H;
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
const Ts = F.Ts;

// getAll 동시성 계측(L10)
const GA = {inFlight: 0, max: 0, calls: 0, failAt: null};
const origGetAll = F.db.getAll;
F.db.getAll = async (...refs) => {
  GA.calls++; GA.inFlight++; GA.max = Math.max(GA.max, GA.inFlight);
  const n = GA.calls;
  await new Promise((r) => setImmediate(r));
  try {
    if (GA.failAt === n) throw new Error('synthetic getAll failure');
    return await origGetAll(...refs);
  } finally { GA.inFlight--; }
};

const ROOTS = NEG ? ['srvHomeUnclosed'] : [
  'callableGetWorkerHomeBundle', 'callableGetMyApplications', 'getMyMonthlyAttendances', 'callableGetPublishedTOs',
  'callableGetMyIdCardRequests', 'callableGetMyRenewalProposals', 'getMyContracts', 'callableGetLegalReadiness',
  'srvHomeUnclosed',
];
const {exports: X, info} = loadIndexClosure(ROOTS, F, {HttpsError, console: QCON, Date: FakeDate});
console.log('[폐포] ' + info + (NEG ? ' · L10 NEGCTL' : ''));
const call = (fn, data, uid) => fn({data, auth: uid ? {uid, token: {}} : undefined});

// ── L10 fixture(이전 원문 사본과 같은 입력으로 대사) ──────────────────────────────
const L10_TODAY = kstMid(2026, 11, 26);
function seedUnclosed() {
  F.reset(); GA.max = 0; GA.calls = 0; GA.failAt = null;
  const ts = (ms) => new Ts(ms);
  // 장기 3명 — 400일 가까이(청크 여러 개) · 휴무·추가근무 · 퇴사일
  F.put('applications/L1', {businessId: 'bU', status: 'CONFIRMED', type: 'long_term', workDate: ts(kstMid(2025, 10, 1)),
    confirmedAt: ts(kstMid(2025, 9, 20)), workDays: ['월', '수', '금'],
    leaveDates: [ts(kstMid(2025, 10, 3)), ts(kstMid(2026, 11, 2) + 5 * H)], extraWorkDates: [ts(kstMid(2025, 10, 4) + H)]});
  F.put('applications/L2', {businessId: 'bU', status: 'CONTRACT_PENDING', type: 'long_term', workDate: ts(kstMid(2025, 12, 1)),
    confirmedAt: ts(kstMid(2025, 11, 25)), workEndDate: ts(kstMid(2026, 12, 31)), workDays: ['월', '화', '수', '목', '금', '토', '일']});
  F.put('applications/L3', {businessId: 'bU', status: 'CONFIRMED', type: 'long_term', workDate: ts(kstMid(2026, 1, 5)),
    confirmedAt: ts(kstMid(2026, 1, 1)), actualResignDate: ts(kstMid(2026, 6, 30)), workDays: ['화', '목']});
  for (const id of ['L4', 'L5', 'L6']) F.put('applications/' + id, Object.assign({}, F.get('applications/L2'))); // 미존재 = 미마감 · 청크 5개
  F.put('applications/S1', {businessId: 'bU', status: 'CONFIRMED', type: 'short', workDate: ts(kstMid(2026, 11, 20) + 15 * H)});
  F.put('applications/S2', {businessId: 'bU', status: 'CONFIRMED', type: 'short', workDate: ts(kstMid(2026, 11, 27))}); // 미래
  F.put('applications/X1', {businessId: 'bU', status: 'CANCELED', type: 'short', workDate: ts(kstMid(2026, 11, 1))});
  F.put('applications/O1', {businessId: 'bOther', status: 'CONFIRMED', type: 'short', workDate: ts(kstMid(2026, 11, 1))});
  // 마감(confirmed/transferred/NO_SHOW) · 미마감(pending) · 미존재(=미마감)
  let k = 0;
  for (let d = kstMid(2025, 12, 1); d < L10_TODAY; d += DAY) {
    const id = `L2_${new RealDate(d + KST).toISOString().slice(0, 10).replace(/-/g, '')}`;
    k++;
    if (k % 7 === 0) continue; // 미존재
    const st = k % 5 === 0 ? {wageStatus: 'pending', status: 'CHECKED_OUT'} :
      k % 11 === 0 ? {status: 'NO_SHOW'} : k % 2 ? {wageStatus: 'confirmed'} : {wageStatus: 'transferred'};
    F.put('attendance/' + id, st);
  }
  F.put('attendance/S1_20261120', {wageStatus: 'pending'});
}

if (NEG) {
  test('L10-NEG 이전 원문 결과 출력', async () => {
    seedUnclosed();
    const r = await X.srvHomeUnclosed('bU', new RealDate(L10_TODAY));
    console.log('L10RESULT ' + JSON.stringify(r) + ' getAllCalls=' + GA.calls + ' maxInFlight=' + GA.max);
    assert.ok(r.count > 0);
  });
} else {
  // ── L9 fixture ────────────────────────────────────────────────────────
  function seedHome() {
    F.reset();
    F.put('users/w1', {role: 'USER', accountStatus: 'active', name: '근로자', termsConsent: {}});
    F.put('users/w2', {role: 'USER', accountStatus: 'active', name: '다른'});
    F.put('app_settings/legal_terms', {items: []});
    F.put('applications/a1', {uid: 'w1', businessId: 'b1', toId: 't1', status: 'PENDING', appliedAt: new Ts(NOW - DAY)});
    F.put('applications/a2', {uid: 'w1', businessId: 'b1', toId: 't1', slotId: 's1', wdId: 'wd1', status: 'INVITED',
      inviteExpiresAt: new Ts(NOW + 2 * DAY)});
    F.put('applications/a3', {uid: 'w2', businessId: 'b1', toId: 't1', status: 'PENDING'});
    F.put('tos/t1', {businessId: 'b1', isPublished: true, status: 'ACTIVE', createdAt: new Ts(NOW - 2 * DAY), type: 'short'});
    F.put('tos/t1/slots/s1', {workDetailCounts: {wd1: {requiredCount: 3, confirmedCount: 1}}});
    F.put('tos/t2', {businessId: 'b2', isPublished: false, status: 'ACTIVE', createdAt: new Ts(NOW)});
    F.put('attendance/x1', {userId: 'w1', workDate: new Ts(kstMid(2026, 11, 3) + 15 * H)});
    F.put('attendance/x2', {userId: 'w1', workDate: new Ts(kstMid(2026, 10, 20))});
    F.put('attendance/x3', {userId: 'w2', workDate: new Ts(kstMid(2026, 11, 3))});
    F.put('idCardAccessRequests/r1', {targetUserId: 'w1', status: 'pending'});
    F.put('idCardAccessRequests/r2', {targetUserId: 'w1', status: 'approved'});
    F.put('idCardAccessRequests/r3', {targetUserId: 'w2', status: 'pending'});
    for (let i = 0; i < 105; i++) {
      F.put(`employment_contracts/c${String(i).padStart(3, '0')}`, {workerId: 'w1', status: i % 3 ? 'active' : 'pending_worker',
        createdAt: new Ts(NOW - i * H), pdfStoragePath: `contracts/c${i}.pdf`});
    }
    F.put('employment_contracts/cOther', {workerId: 'w2', status: 'active', createdAt: new Ts(NOW)});
    F.put('renewal_proposals/p1', {workerUid: 'w1', status: 'PENDING', effectiveDate: new Ts(NOW + 5 * DAY)});
  }
  const readsOf = (pred) => F.W.reads.filter(pred);

  test('WHB-01 기본 6섹션 성공 — 각 data 가 기존 endpoint 응답과 같다(parity) · partial=false · 갱신 제안은 기본 제외', async () => {
    seedHome();
    const b = await call(X.callableGetWorkerHomeBundle, {generation: 7,
      monthlyAttendances: {months: [{year: 2026, month: 11}, {year: 2026, month: 10}]}}, 'w1');
    assert.strictEqual(b.version, 1);
    assert.strictEqual(b.uid, 'w1');
    assert.strictEqual(b.generation, 7);
    assert.strictEqual(b.serverTimeMs, NOW);
    assert.strictEqual(b.partial, false);
    assert.deepStrictEqual(Object.keys(b.sections).sort(),
      ['applications', 'contracts', 'idCardRequests', 'legalReadiness', 'monthlyAttendances', 'publishedTOs']);
    for (const s of Object.values(b.sections)) assert.strictEqual(s.ok, true);
    const S = b.sections;
    assert.deepStrictEqual(S.applications.data, await call(X.callableGetMyApplications, {limit: 200}, 'w1'));
    assert.deepStrictEqual(S.publishedTOs.data, await call(X.callableGetPublishedTOs, {}, 'w1'));
    assert.deepStrictEqual(S.idCardRequests.data, await call(X.callableGetMyIdCardRequests, {status: 'pending'}, 'w1'));
    assert.deepStrictEqual(S.contracts.data, await call(X.getMyContracts, {pageSize: 200}, 'w1'));
    assert.deepStrictEqual(S.legalReadiness.data, await call(X.callableGetLegalReadiness, {}, 'w1'));
    const m11 = await call(X.getMyMonthlyAttendances, {year: 2026, month: 11}, 'w1');
    const m10 = await call(X.getMyMonthlyAttendances, {year: 2026, month: 10}, 'w1');
    assert.deepStrictEqual(S.monthlyAttendances.data, {months: [{year: 2026, month: 11, items: m11.items}, {year: 2026, month: 10, items: m10.items}]});
    // 내용 확인(빈 parity 방지)
    assert.strictEqual(S.applications.data.applications.length, 2);
    const inv = S.applications.data.applications.find((a) => a.id === 'a2');
    assert.ok(inv.inviteAcceptReadiness && inv.workInstanceCapacityState, '초대 투영(UNKNOWN/UNAVAILABLE 등 3-state)이 그대로');
    assert.strictEqual(S.contracts.data.items.length, 100, 'pageSize 200 → 서버 상한 100');
    assert.strictEqual(S.contracts.data.hasMore, true, '완전성 표지(hasMore) 그대로');
    assert.ok(S.contracts.data.items.every((c) => c.pdfAvailable === true && !('pdfStoragePath' in c)), '목록 PDF 투영 규칙(경로 제거 · 있음 표지) 그대로');
    assert.deepStrictEqual(S.idCardRequests.data.requests.map((r) => r.id), ['r1']);
    assert.strictEqual(S.publishedTOs.data.tos.length, 1);
    assert.strictEqual(m11.items.length, 1);
  });

  test('WHB-02 fence 1회 · users 요청 단위 1회 · 쓰기 0 · application 문서 외 타인 데이터 0', async () => {
    seedHome();
    F.clearLog();
    await call(X.callableGetWorkerHomeBundle, {}, 'w1');
    const tomb = readsOf((r) => r.kind === 'doc' && r.path.startsWith('account_deletion_tombstones/'));
    assert.strictEqual(tomb.length, 1, 'fence 는 handler 앞 1회');
    const users = readsOf((r) => r.kind === 'doc' && r.path === 'users/w1');
    assert.strictEqual(users.length, 1, '약관 준비 + 초대 수락 준비가 users 하나를 공유');
    assert.ok(!readsOf((r) => r.kind === 'doc' && r.path === 'users/w2').length);
    assert.strictEqual(F.W.commits.length + F.W.direct.length, 0, '읽기 전용');
    // 대조: 개별 endpoint 둘이면 users 2회
    F.clearLog();
    await call(X.callableGetMyApplications, {limit: 200}, 'w1');
    await call(X.callableGetLegalReadiness, {}, 'w1');
    assert.strictEqual(readsOf((r) => r.kind === 'doc' && r.path === 'users/w1').length, 2);
  });

  test('WHB-03 부분 실패 — 실패 섹션은 ok:false/code 만(data 없음 · 0/빈 목록 합성 0) · 나머지는 성공', async () => {
    seedHome();
    // 계약 cursor 가 타인 문서 → permission-denied(기존 인가) · 약관 문서 읽기 예외 → internal
    F.hooks.afterGet = (p) => { if (p === 'app_settings/legal_terms') throw new Error('synthetic read failure'); };
    const b = await call(X.callableGetWorkerHomeBundle, {contracts: {pageSize: 20, lastDocId: 'cOther'},
      sections: ['applications', 'contracts', 'legalReadiness', 'idCardRequests']}, 'w1');
    F.hooks.afterGet = null;
    assert.strictEqual(b.partial, true);
    assert.deepStrictEqual(b.sections.contracts, {ok: false, code: 'permission-denied', message: '접근 권한이 없는 커서입니다.'});
    assert.deepStrictEqual(b.sections.legalReadiness, {ok: false, code: 'internal'});
    assert.ok(!('data' in b.sections.contracts) && !('data' in b.sections.legalReadiness));
    assert.strictEqual(b.sections.applications.ok, true);
    assert.strictEqual(b.sections.idCardRequests.ok, true);
    assert.deepStrictEqual(Object.keys(b.sections).sort(), ['applications', 'contracts', 'idCardRequests', 'legalReadiness']);
    assert.ok(LOGS.some((l) => l.includes('[workerHomeBundle] legalReadiness 실패')));
    // 섹션 검증 오류도 섹션 실패(기존 endpoint 의 invalid-argument 그대로)
    const b2 = await call(X.callableGetWorkerHomeBundle, {sections: ['monthlyAttendances', 'contracts'],
      monthlyAttendances: {months: [{year: 2019, month: 1}]}, contracts: {statusFilter: 'bogus'}}, 'w1');
    assert.strictEqual(b2.sections.monthlyAttendances.code, 'invalid-argument');
    assert.strictEqual(b2.sections.contracts.code, 'invalid-argument');
  });

  test('WHB-04 인가 — 미인증은 요청 전체 오류 · uid 는 auth 만(요청의 uid 무시) · 탈퇴 중이면 섹션 읽기 0', async () => {
    seedHome();
    await assert.rejects(call(X.callableGetWorkerHomeBundle, {}, null), (e) => e.code === 'unauthenticated');
    const b = await call(X.callableGetWorkerHomeBundle, {uid: 'w2', sections: ['applications', 'idCardRequests']}, 'w1');
    assert.strictEqual(b.uid, 'w1');
    assert.ok(b.sections.applications.data.applications.every((a) => a.uid === 'w1'));
    assert.deepStrictEqual(b.sections.idCardRequests.data.requests.map((r) => r.id), ['r1']);
    F.put('account_deletion_tombstones/w1', {uid: 'w1'});
    F.clearLog();
    await assert.rejects(call(X.callableGetWorkerHomeBundle, {}, 'w1'),
      (e) => e.details && e.details.reason === 'ACCOUNT_DELETION_IN_PROGRESS');
    assert.deepStrictEqual(F.W.reads.map((r) => r.path), ['account_deletion_tombstones/w1'], 'fence 실패면 업무 읽기 0');
  });

  test('WHB-05 입력 검증(요청 전체 invalid-argument) — 섹션 허용 목록 · 중복 · 보완 요청(쓰기 포함) 제외 · 월 1–2 · 세대 형식', async () => {
    seedHome();
    const bad = [
      {sections: ['documentCorrections']}, {sections: ['applications', 'applications']}, {sections: []}, {sections: 'applications'},
      {monthlyAttendances: {months: []}}, {monthlyAttendances: {months: [{year: 2026, month: 1}, {year: 2026, month: 2}, {year: 2026, month: 3}]}},
      {monthlyAttendances: {months: [{year: 2026, month: 1}, {year: 2026, month: 1}]}},
      {generation: {x: 1}}, {generation: 'x'.repeat(65)}, {generation: 1.5}, {contracts: [1]}, [1],
    ];
    for (const d of bad) {
      await assert.rejects(call(X.callableGetWorkerHomeBundle, d, 'w1'), (e) => e.code === 'invalid-argument', JSON.stringify(d));
    }
    const ok = await call(X.callableGetWorkerHomeBundle, {generation: 'gen-abc', sections: ['renewalProposals']}, 'w1');
    assert.strictEqual(ok.generation, 'gen-abc');
    assert.deepStrictEqual(ok.sections.renewalProposals.data, await call(X.callableGetMyRenewalProposals, {}, 'w1'));
    assert.strictEqual((await call(X.callableGetWorkerHomeBundle, {sections: ['publishedTOs']}, 'w1')).generation, null);
  });

  test('WHB-06 요청한 섹션만 실행 · 기본 근무 월 = 서버 기준 이번 KST 월', async () => {
    seedHome();
    F.clearLog();
    const b = await call(X.callableGetWorkerHomeBundle, {sections: ['monthlyAttendances']}, 'w1');
    assert.deepStrictEqual(Object.keys(b.sections), ['monthlyAttendances']);
    assert.deepStrictEqual(b.sections.monthlyAttendances.data.months.map((m) => [m.year, m.month]), [[2026, 11]]);
    const cols = new Set(F.W.reads.map((r) => r.path.split('/')[0]));
    assert.deepStrictEqual([...cols].sort(), ['account_deletion_tombstones', 'attendance']);
    // 월 경계: KST 12-01 00:30 이면 12월
    NOW = kstMid(2026, 12, 1) + 30 * 60 * 1000;
    const b2 = await call(X.callableGetWorkerHomeBundle, {sections: ['monthlyAttendances']}, 'w1');
    assert.deepStrictEqual(b2.sections.monthlyAttendances.data.months.map((m) => [m.year, m.month]), [[2026, 12]]);
    NOW = kstMid(2026, 11, 26) + 10 * H;
  });

  test('WHB-07 원문 배선 — 기존 endpoint 7개는 helper 위임만 · 묶음은 공통 onCall · 허용 목록에 보완 요청 없음', () => {
    const SRC = fs.readFileSync(path.join(__dirname, '..', 'src', 'index.ts'), 'utf8');
    const thin = {
      callableGetMyApplications: 'return srvReadMyApplications(request.auth.uid, request.data);',
      getMyMonthlyAttendances: 'return srvReadMyMonthlyAttendances(request.auth.uid, request.data);',
      callableGetPublishedTOs: 'return srvReadPublishedTOs(request.data);',
      callableGetMyIdCardRequests: 'return srvReadMyIdCardRequests(request.auth.uid, request.data);',
      callableGetMyRenewalProposals: 'return srvReadMyRenewalProposals(request.auth.uid);',
      getMyContracts: 'return srvReadMyContracts(request.auth.uid, request.data);',
      callableGetLegalReadiness: 'return srvReadLegalReadiness(request.auth.uid);',
    };
    for (const [n, line] of Object.entries(thin)) {
      const i = SRC.indexOf(`export const ${n} = onCall(`);
      const body = SRC.slice(i, SRC.indexOf('\n);\n', i));
      assert.ok(body.includes(line), n);
    }
    const i = SRC.indexOf('export const callableGetWorkerHomeBundle = onCall(');
    assert.ok(i > 0);
    const w = SRC.slice(SRC.indexOf('const WHB_SECTIONS = ['), SRC.indexOf('] as const;', SRC.indexOf('const WHB_SECTIONS = [')));
    assert.ok(!/Correction/i.test(w), '보완 요청 섹션 없음');
    assert.ok(!SRC.slice(SRC.indexOf('async function srvWorkerHomeBundle('), i).includes('srvGetMyDocumentCorrections'));
  });

  // ── L10 ─────────────────────────────────────────────────────────────────
  /** 기준 계산 — 직렬 원식(예상 근무일 펼치기 → 마감 판정 → unique 근무일 · oldest)을 시험 안에서 따로 적는다. */
  function referenceUnclosed(biz, todayMs) {
    const all = F.dump();
    const dayKey = (ms) => new RealDate(ms + KST).toISOString().slice(0, 10);
    const KRD = ['일', '월', '화', '수', '목', '금', '토'];
    const want = new Map();
    for (const [p, d0] of Object.entries(all)) {
      if (!p.startsWith('applications/') || p.split('/').length !== 2) continue;
      const d = d0; const id = p.split('/')[1];
      if (d.businessId !== biz || !['CONFIRMED', 'CONTRACT_PENDING'].includes(d.status)) continue;
      const ms = (v) => (v && typeof v === 'object' && '__ts' in v ? v.__ts : null);
      if (d.type !== 'long_term') {
        const w = ms(d.workDate); if (w == null || w >= todayMs) continue;
        const k = dayKey(w); want.set(`${id}_${k.replace(/-/g, '')}`, k);
      } else {
        assert.ok(ms(d.confirmedAt) < ms(d.workDate), 'fixture: 확정이 시작 전 → 실효 시작 = workDate');
        const start = ms(d.workDate);
        const endRaw = ms(d.actualResignDate) ?? ms(d.workEndDate);
        const end = endRaw == null ? todayMs - DAY : Math.min(endRaw, todayMs - DAY);
        let cur = RealDate.UTC(...dayKey(start).split('-').map((x, i) => (i === 1 ? Number(x) - 1 : Number(x)))) - KST;
        for (; cur <= end; cur += DAY) {
          const wd = KRD[new RealDate(cur + KST).getUTCDay()];
          const inDay = (arr) => (arr || []).some((t) => ms(t) >= cur && ms(t) < cur + DAY);
          if (!inDay(d.leaveDates) && ((d.workDays || []).includes(wd) || inDay(d.extraWorkDates))) {
            const k = dayKey(cur); want.set(`${id}_${k.replace(/-/g, '')}`, k);
          }
        }
      }
    }
    const open = new Set(); let oldest = null;
    for (const [docId, k] of want) {
      const a = all['attendance/' + docId];
      const closed = a && (a.wageStatus === 'confirmed' || a.wageStatus === 'transferred' || a.status === 'NO_SHOW');
      if (!closed) { open.add(k); if (!oldest || k < oldest) oldest = k; }
    }
    return {count: open.size, oldestKey: oldest, refs: want.size};
  }

  test('L10-01 제한 청크 병렬 — 결과 = 기준 직렬 계산(unique 근무일·미존재=미마감·휴무/추가근무·퇴사일) · 동시 getAll ≤4 · >1', async () => {
    seedUnclosed();
    const ref = referenceUnclosed('bU', L10_TODAY);
    const r = await X.srvHomeUnclosed('bU', new RealDate(L10_TODAY));
    assert.ok(ref.refs > 1200, '청크 4개 이상: ' + ref.refs);
    assert.strictEqual(r.count, ref.count);
    assert.strictEqual(r.oldestDate, ref.oldestKey);
    assert.strictEqual(GA.calls, Math.ceil(ref.refs / 400));
    assert.ok(GA.max > 1 && GA.max <= 4, 'maxInFlight=' + GA.max);
    console.log('L10RESULT ' + JSON.stringify(r) + ' getAllCalls=' + GA.calls + ' maxInFlight=' + GA.max);
  });

  test('L10-02 청크 하나 실패 → 전체 실패(부분 결과 0) · 그 물결의 다른 읽기가 끝난 뒤 던진다', async () => {
    seedUnclosed();
    GA.failAt = 2;
    await assert.rejects(X.srvHomeUnclosed('bU', new RealDate(L10_TODAY)), /synthetic getAll failure/);
    assert.strictEqual(GA.inFlight, 0, '실패 뒤 남은 getAll 0');
  });

  test('L10-03 3650일 초과는 잘라 성공하지 않고 오류 · 0건/빈 결과는 그대로', async () => {
    F.reset(); GA.calls = 0; GA.max = 0; GA.failAt = null;
    F.put('applications/Z', {businessId: 'bZ', status: 'CONFIRMED', type: 'long_term', workDate: new Ts(kstMid(2010, 1, 1)),
      confirmedAt: new Ts(kstMid(2009, 12, 1)), workDays: ['월']});
    await assert.rejects(X.srvHomeUnclosed('bZ', new RealDate(L10_TODAY)), /3650일을 초과/);
    assert.strictEqual(GA.calls, 0);
    assert.deepStrictEqual(await X.srvHomeUnclosed('bNone', new RealDate(L10_TODAY)), {count: 0, oldestDate: null});
  });
}
