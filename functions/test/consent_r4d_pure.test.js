/**
 * [CONSENT-R4d] 순수 판정 모듈(src/consent_r4.ts · r4d 후보) — 실제 소스를 TypeScript 로 변환해 실행한다.
 *   r4d: P-W9(F-R4C-1 — 지난 종료일 계약의 시작 오류/역전/혼합/양성). 그 밖 r4c 와 같다.
 *   r5(판정 consent1121 §4 F-R4D-1): P-W5 기간 지남 · P-W6 종료 형식오류 · P-W6 혼합의 snapshot 에 유효 시작일(2026-11-02) 명시 —
 *     얕은 Object.assign 이 snapshot 을 통째로 바꿔 시작일이 사라지던 것. 기대(ENDED/END_MALFORMED/UNKNOWN) 약화 0 · P-W9 그대로.
 *   r4c(r4b 판 191c3041 대체 · 바뀐 기대 = r4c 폴더 manifests/r4c_expectation_map.tsv):
 *     · A1 계약 시작·종료 양 경계 필수 · 역전/결손/null/빈값 반례(F-R4B-1 · PP-R4B-A1)
 *     · 보완은 현재 계좌·통장 판본 결속으로만 A4(F-R4B-2 · PP-R4B-A4) · 판본/연결 불명 = A3
 *     · 관계 무결성이 S1·A1 보다 먼저(F-R4B-3)
 *
 *   작성만 했다 — 이번 배정 실행 0(제품 CLI · Node 시험 0). 통과 결과가 아니다.
 *   실행(제안 · LOCAL 계약 F2 · 실행권 0):
 *     cwd = A_copy/functions
 *     <R 안 node> test/consent_r4b_pure.test.js
 *   의존: node_modules/typescript(변환만) · 이 폴더의 consent_r4_clock.js(r4 와 같은 바이트 8739ba12).
 *   성공 = 마지막 줄 '통과 N / 실패 0' · rc 0. 실패 하나라도 있으면 rc 1.
 *
 *   r4 판의 consent_r4_pure.test.js(454dfa1f)를 대체한다 — 옛 기대(S4/S5 DRAFT 닫힘 · 연결 보완 = S2 ·
 *   noPayment/unknownEvidence/mixed 스위치 · NO_END 닫힘)는 r4 폴더에 바이트 그대로 남고, 이 판에서는
 *   질문1 대표 답('응' · Codex 정본 기록 전)과 후속 six_answers §2 기대로 **교체**한다(삭제가 아니다 —
 *   교체 대응표 = r4b_test_change_map.tsv).
 *
 *   고정하는 것
 *     P-A  Timestamp 모양·유한값                       (r4 와 같음)
 *     P-B  L · 시작일 · 계약 날짜 문자열
 *     P-C  근태 배타 5분류                              (r4 와 같음)
 *     P-W  A1 현재 근무 근거 — 현재/미시작/종료/불명 · 합성 0 · 전이
 *     P-D  열람 기간 — S1 · A1 · S2(T 규칙) · S3 T30 · A2/A3/A4 L30 · L 불명 · 무결성 ·
 *          경계 −1ms/정각/+1ms · 대안 경계식 · T<L/T>L · 늦게 열린 보완 · 잘림 · 반환 계약
 *     P-E  새 URL 만료 = min(now+1h, 닫힘, 재판정) · 서명 직전 재판정(경계 넘김)
 *     P-F  재배치 원동의 승계(양방향 계보 · A→B→C 원 At)
 *     P-G  재배치 제안 ↔ A 계보 정합                     (r4 와 같음)
 *   (r4 P-H 초대 수락 보존은 index.ts 로 옮겨졌으므로 consent_r4b_index.test.js I-H 가 본다.)
 */
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const ts = require('typescript');
const C = require('./consent_r4_clock');

const SRC_PATH = path.join(__dirname, '..', 'src', 'consent_r4.ts');
const SRC = fs.readFileSync(SRC_PATH, 'utf8');
console.log('consent_r4.ts sha256=' +
  crypto.createHash('sha256').update(fs.readFileSync(SRC_PATH)).digest('hex'));
const js = ts.transpileModule(SRC, {compilerOptions: {
  target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS}}).outputText;
const mod = {exports: {}};
// eslint-disable-next-line no-new-func
new Function('module', 'exports', 'require', js)(mod, mod.exports, () => {
  throw new Error('consent_r4.ts 는 import 가 없어야 한다');
});
const M = mod.exports;

const {Ts, kst, DAY, HOUR, MIN, V4, INV2, V1, V2, V3, INV1, CR_KIND,
  WORK_DAY, T0, T1, PAY1, PAY2, app, att, cell, summary} = C;
// [r4c] 지급 보완 기본 = 현재 판본(계좌 1 · 통장 1)에 결속된 공통 PAYROLL 요청. 판본 반례는 P-D11 에서 따로.
const corr = (o = {}) => C.corr(Object.assign({bankAccountVersionAtRequest: 1, documentVersionAtRequest: 1}, o));
const CUR = {account: 1, bankbook: 1};
const GEN = [V4, INV2];
const P = M.CR4_BANK_WINDOW_POLICY_DRAFT;
const pol = (o) => Object.assign({}, P, o);
const NOW = kst(2026, 12, 1, 12, 0);
const L30 = WORK_DAY + 30 * DAY;            // 2026-12-20 00:00 KST(배타)
const T30 = PAY2 + 30 * DAY;                // 2026-12-27 18:30 KST(배타)
const win = (a, atts, o = {}) => M.cr4BankWindow(Object.assign({
  app: a, applicationId: 'a1', attendances: atts, attendanceSetComplete: true,
  corrections: [], correctionSetComplete: true, docVersions: CUR,
  contracts: null, contractSetComplete: true, business: {},
  nowMs: NOW, policy: P,
}, o));

// ── NO_END 장기 · 계약 fixture ────────────────────────────────────────────
const START_DAY = kst(2026, 11, 2);
const noEnd = (o = {}) => app(Object.assign({type: 'long_term', workDate: new Ts(START_DAY),
  desiredStartDate: new Ts(START_DAY), workDays: ['월', '화', '수', '목', '금']}, o));
const con = (id, o = {}) => Object.assign({
  id, applicationId: 'a1', applicationIds: [], workerId: 'w1', businessId: 'b1',
  status: 'completed', employerSignedAt: new Ts(kst(2026, 11, 1, 10)),
  workerSignedAt: new Ts(kst(2026, 11, 1, 12)),
  // 결손 예외의 전형: 지원서에는 종료일이 없고 서명 계약 스냅샷에는 기간이 있다.
  snapshot: {contractStart: '2026-11-02', contractEnd: '2027-03-31'},
}, o);
const CON_END = kst(2027, 3, 31);
const cw = (a, contracts, o = {}) => M.cr4CurrentWork(Object.assign({
  app: a, applicationId: 'a1', contracts, contractSetComplete: true, business: {}, nowMs: NOW,
}, o));

(async () => {
  console.log('\n[P-A] Timestamp 모양·유한값');
  await cell('P-A1', 'toMillis 가 유한 숫자면 그 값', () => {
    assert.strictEqual(M.cr4ValidTsMs(new Ts(5)), 5);
  });
  await cell('P-A2', '숫자·문자열·Date·null·undefined 는 null', () => {
    for (const v of [5, '2026-11-20', new Date(5), null, undefined, true, []]) {
      assert.strictEqual(M.cr4ValidTsMs(v), null, String(v));
    }
  });
  await cell('P-A3', 'NaN·Infinity·문자열 반환·throw 는 null', () => {
    for (const f of [() => NaN, () => Infinity, () => '5', () => { throw new Error('x'); }]) {
      assert.strictEqual(M.cr4ValidTsMs({toMillis: f}), null);
    }
    assert.strictEqual(M.cr4ValidTsMs({toMillis: 5}), null);
  });

  console.log('\n[P-B] L · 시작일 · 계약 날짜');
  const L = M.cr4LastWorkDay;
  await cell('P-B1', '단기 = workDate', () => {
    assert.deepStrictEqual(L(app()), {kind: 'KNOWN', ms: WORK_DAY, field: 'workDate'});
  });
  await cell('P-B2', '조기 종료가 먼저, 형식오류면 MALFORMED(다른 날짜로 대체 0)', () => {
    const r = kst(2026, 11, 15);
    assert.strictEqual(L(app({actualResignDate: new Ts(r)})).ms, r);
    assert.deepStrictEqual(L(app({actualResignDate: '2026-11-15'})),
        {kind: 'MALFORMED', field: 'actualResignDate'});
  });
  await cell('P-B3', '장기 = workEndDate, 없으면 NO_END', () => {
    const e = kst(2027, 1, 31);
    assert.strictEqual(L(app({type: 'long_term', workEndDate: new Ts(e)})).ms, e);
    assert.deepStrictEqual(L(app({type: 'contract'})), {kind: 'NO_END'});
    assert.deepStrictEqual(L(app({type: 'long_term', workEndDate: 12345})),
        {kind: 'MALFORMED', field: 'workEndDate'});
  });
  await cell('P-B4', '단기 workDate 없음 = MISSING', () => {
    assert.deepStrictEqual(L(app({workDate: undefined})), {kind: 'MISSING', field: 'workDate'});
  });
  await cell('P-B5', 'type 없음(legacy) — workDays + 다른 날짜면 workEndDate, 아니면 workDate', () => {
    const e = kst(2026, 12, 31);
    assert.strictEqual(L(app({type: undefined, workDays: ['월'], workEndDate: new Ts(e)})).ms, e);
    assert.strictEqual(L(app({type: undefined})).ms, WORK_DAY);
    assert.deepStrictEqual(L(app({type: undefined, workDate: 'x'})),
        {kind: 'MALFORMED', field: 'workDate'});
  });
  await cell('P-B6', '시작일 = desiredStartDate ?? workDate, 희망일 없을 때만 confirmedAt 으로 민다(commitment_dates 와 같은 식)', () => {
    const S = M.cr4StartDay;
    assert.deepStrictEqual(S(noEnd()), {kind: 'KNOWN', ms: START_DAY, field: 'desiredStartDate'});
    const late = kst(2026, 11, 5, 15);
    assert.strictEqual(S(noEnd({desiredStartDate: undefined, confirmedAt: new Ts(late)})).ms,
        kst(2026, 11, 5), '희망일 없으면 확정일(KST 일)로 민다');
    assert.strictEqual(S(noEnd({confirmedAt: new Ts(late)})).ms, START_DAY, '희망일이 있으면 밀지 않는다');
    assert.deepStrictEqual(S(noEnd({desiredStartDate: 'x'})), {kind: 'MALFORMED', field: 'desiredStartDate'});
    assert.deepStrictEqual(S(noEnd({desiredStartDate: undefined, workDate: undefined})), {kind: 'MISSING'});
  });
  await cell('P-B7', "계약 날짜 'yyyy-MM-dd' → KST 0시, 실재하지 않는 날짜·다른 모양은 null", () => {
    assert.strictEqual(M.cr4KstYmdMs('2026-11-20'), WORK_DAY);
    for (const s of ['2026-02-30', '2026-13-01', '2026/11/20', '20261120', '', null, 5]) {
      assert.strictEqual(M.cr4KstYmdMs(s), null, String(s));
    }
  });

  console.log('\n[P-C] 근태 배타 5분류');
  const cls = (a, o = {}) => M.cr4ClassifyAttendance(att('x', o), a || app(), NOW).cls;
  await cell('P-C1', '① 양수 이체 = PAID', () => assert.strictEqual(cls(null), 'PAID'));
  await cell('P-C2', '③ 정상근무 0원 유효 이체 = ZERO_PAID', () => {
    assert.strictEqual(cls(null, {finalWage: 0}), 'ZERO_PAID');
  });
  await cell('P-C3', '② 노쇼·결근 0원 확정 = NONPAYABLE_ZERO', () => {
    assert.strictEqual(cls(null, {wageStatus: 'confirmed', status: 'NO_SHOW', finalWage: 0}), 'NONPAYABLE_ZERO');
    assert.strictEqual(cls(null, {wageStatus: 'confirmed', status: 'absent', finalWage: undefined}), 'NONPAYABLE_ZERO');
  });
  await cell('P-C4', '④ 정상근무 0원 confirmed 는 미결(OPEN)', () => {
    assert.strictEqual(cls(null, {wageStatus: 'confirmed', status: 'present', finalWage: 0}), 'OPEN');
  });
  await cell('P-C5', '④ pending·calculated·양수 confirmed·정산잠금', () => {
    for (const ws of ['pending', 'calculated', 'confirmed']) {
      assert.strictEqual(cls(null, {wageStatus: ws, transferDate: undefined}), 'OPEN', ws);
    }
    assert.strictEqual(cls(null, {wageStatus: 'confirmed', status: 'NO_SHOW', finalWage: 0,
      activeInterimSettlementId: 'isr1'}), 'OPEN');
  });
  await cell('P-C6', '⑤ 이체인데 transferDate 없음·형식오류·미래 / 잠금 / 비지급 / 금액불명 / 상태불명 / 다른 관계', () => {
    const u = [
      {transferDate: undefined}, {transferDate: '2026-11-25'}, {transferDate: new Ts(NOW + 1)},
      {activeInterimSettlementId: 'isr1'}, {status: 'NO_SHOW', finalWage: 0},
      {finalWage: undefined}, {finalWage: -1}, {wageStatus: undefined}, {wageStatus: 'weird'},
      {businessId: 'b2'}, {userId: 'w2'},
    ];
    for (const o of u) assert.strictEqual(cls(null, o), 'UNKNOWN', JSON.stringify(o));
  });

  console.log('\n[P-W] A1 결손 예외 — 현재 근무 별도 확인(N-EP2 #4 · 확인 방법 = Claude 기술 후보 · Codex 판정 요청)');
  await cell('P-W1', '서명 완료 계약 기간이 오늘을 포함 · 시작 지남 · 종료 전이 없음 → CURRENT(출처·계약 id·시작·서명·계약 끝)', () => {
    const r = cw(noEnd(), [con('c1')]);
    assert.strictEqual(r.state, 'CURRENT');
    assert.strictEqual(r.source, 'SIGNED_CONTRACT_IN_FORCE');
    assert.strictEqual(r.contractId, 'c1');
    assert.strictEqual(r.effectiveStartMs, START_DAY);
    assert.strictEqual(r.workerSignedAtMs, kst(2026, 11, 1, 12));
    assert.strictEqual(r.contractPeriodEndMs, CON_END);
    assert.strictEqual(cw(noEnd(), [con('c1')], {nowMs: CON_END + 10 * HOUR}).state, 'CURRENT', '계약 마지막 날 포함');
    const after = cw(noEnd(), [con('c1')], {nowMs: CON_END + DAY});
    assert.strictEqual(after.state, 'ENDED', '다음 날 0시부터 종료');
    assert.ok(after.reasons.includes('CONTRACT_c1_PERIOD_ENDED'));
  });
  await cell('P-W2', 'applicationIds 로 묶인 번들 계약도 같은 근거 · 여럿이면 가장 늦게 서명한 것', () => {
    const r = cw(noEnd(), [con('c1', {applicationId: 'other', applicationIds: ['a1']}),
      con('c2', {workerSignedAt: new Ts(kst(2026, 11, 3))})]);
    assert.strictEqual(r.state, 'CURRENT'); assert.strictEqual(r.contractId, 'c2');
  });
  await cell('P-W3', '합성 0 — 계약 없음 · 서명 대기 · 무효 · 서명시각 결손 · 계약에도 종료일 없음(정상 NO_END 없음) · 동의 true 만으로는 CURRENT 아님', () => {
    const r0 = cw(noEnd(), [con('c1', {snapshot: {contractStart: '2026-11-02', contractEnd: null}})]);
    assert.ok(r0.reasons.includes('CONTRACT_c1_END_MISSING_NOT_EVIDENCE'));
    for (const cs of [[], [con('c1', {status: 'pending_worker'})], [con('c1', {status: 'pending_employer'})],
      [con('c1', {status: 'voided'})], [con('c1', {status: 'active'})],
      [con('c1', {employerSignedAt: undefined})], [con('c1', {workerSignedAt: '2026-11-01'})],
      [con('c1', {snapshot: {contractStart: '2026-11-02', contractEnd: ''}})], [con('c1', {snapshot: undefined})]]) {
      const r = cw(noEnd({documentAccessConsentGiven: true}), cs);
      assert.strictEqual(r.state, 'UNKNOWN', JSON.stringify(cs.map((c) => c.status)));
      assert.strictEqual(r.source, null);
    }
  });
  await cell('P-W4', '시작 전 → NOT_STARTED(지원서 시작일 또는 계약 시작일 · 새 열람 근거 아님)', () => {
    const fut = kst(2026, 12, 15);
    const r = cw(noEnd({desiredStartDate: new Ts(fut)}), [con('c1')]);
    assert.strictEqual(r.state, 'NOT_STARTED'); assert.strictEqual(r.effectiveStartMs, fut);
    assert.ok(r.reasons.includes('BEFORE_EFFECTIVE_START'));
    assert.strictEqual(cw(noEnd({desiredStartDate: new Ts(fut)}), [con('c1')],
      {nowMs: fut}).state, 'CURRENT', '시작일 0시부터 CURRENT');
    const cs = cw(noEnd(), [con('c1', {snapshot: {contractStart: '2026-12-10', contractEnd: '2027-03-31'}})]);
    // [r4c] 계약 시작이 미래면 NOT_STARTED(지원서 시작이 지났어도).
    assert.strictEqual(cs.state, 'NOT_STARTED'); assert.strictEqual(cs.effectiveStartMs, kst(2026, 12, 10));
    assert.ok(cs.reasons.includes('CONTRACT_c1_NOT_STARTED'));
  });
  await cell('P-W5', '종료 전이 → ENDED: 퇴사·해지 승인(날짜 없음) · 좌석 반납 · 사업장 운영 종료 · 계약 만료 · 계약 기간 지남', () => {
    const cases = [
      [cw(noEnd({resignStatus: 'APPROVED'}), [con('c1')]), 'RESIGN_APPROVED_WITHOUT_DATE'],
      [cw(noEnd({terminationStatus: 'AUTO_APPROVED'}), [con('c1')]), 'TERMINATION_APPROVED_WITHOUT_DATE'],
      [cw(noEnd({staffingReleasedAt: new Ts(kst(2026, 11, 20))}), [con('c1')]), 'SEAT_RELEASED'],
      [cw(noEnd(), [con('c1')], {business: {deactivatedAt: new Ts(kst(2026, 12, 1, 9))}}), 'BUSINESS_CLOSED'],
      [cw(noEnd(), [con('c1', {status: 'expired'})]), 'CONTRACT_c1_EXPIRED'],
      [cw(noEnd(), [con('c1', {snapshot: {contractStart: '2026-11-02', contractEnd: '2026-11-30'}})]), 'CONTRACT_c1_PERIOD_ENDED'],
    ];
    for (const [r, why] of cases) {
      assert.strictEqual(r.state, 'ENDED', why); assert.ok(r.reasons.includes(why), why);
    }
    assert.strictEqual(cw(noEnd(), [con('c1')], {business: {deactivatedAt: new Ts(kst(2026, 12, 2))}}).state,
        'CURRENT', '내일 종료 예정이면 오늘은 아직 운영 중');
    assert.strictEqual(cw(noEnd({resignStatus: 'PENDING'}), [con('c1')]).state, 'CURRENT', '요청 대기는 종료가 아니다');
  });
  await cell('P-W6', '근거 불명 → UNKNOWN: 계약 미조회 · 잘림 · 다른 사람/사업장 계약 · 계약 날짜 형식오류 · 서명 시각 미래 · 사업장 문서 없음/형식오류 · 시작일 없음/오류', () => {
    const cases = [
      [cw(noEnd(), null), 'CONTRACTS_NOT_READ'],
      [cw(noEnd(), [con('c1')], {contractSetComplete: false}), 'CONTRACT_SET_TRUNCATED'],
      [cw(noEnd(), [con('c1'), con('c2', {workerId: 'w9'})]), 'CONTRACT_c2_FOREIGN_ROW'],
      [cw(noEnd(), [con('c1', {businessId: 'b9'})]), 'CONTRACT_c1_FOREIGN_ROW'],
      [cw(noEnd(), [con('c1', {snapshot: {contractStart: '2026-11-02', contractEnd: '2026/12/31'}})]), 'CONTRACT_c1_END_MALFORMED'],
      [cw(noEnd(), [con('c1', {snapshot: {contractStart: '11/02', contractEnd: '2027-03-31'}})]), 'CONTRACT_c1_START_MALFORMED'],
      [cw(noEnd(), [con('c1', {workerSignedAt: new Ts(NOW + 1)})]), 'CONTRACT_c1_SIGNATURE_TIME_FUTURE'],
      [cw(noEnd(), [con('c1')], {business: null}), 'BUSINESS_MISSING'],
      [cw(noEnd(), [con('c1')], {business: {deactivatedAt: '2026-12-01'}}), 'BUSINESS_DEACTIVATED_AT_MALFORMED'],
      [cw(noEnd({desiredStartDate: undefined, workDate: undefined}), [con('c1')]), 'START_MISSING'],
      [cw(noEnd({desiredStartDate: 7}), [con('c1')]), 'START_MALFORMED_desiredStartDate'],
    ];
    for (const [r, why] of cases) {
      assert.strictEqual(r.state, 'UNKNOWN', why); assert.ok(r.reasons.includes(why), why + ' ' + r.reasons);
    }
    // 형식이 깨진 계약이 하나라도 있으면 다른 정상 계약이 있어도 열지 않는다(어긋난 자료로 열지 않음).
    assert.strictEqual(cw(noEnd(), [con('c1'), con('c2', {snapshot: {contractStart: '2026-11-02', contractEnd: 'x'}})]).state, 'UNKNOWN');
    // 종료일 없는 계약은 근거가 아닐 뿐 막지는 않는다 — 기간 있는 정상 계약이 있으면 CURRENT.
    assert.strictEqual(cw(noEnd(), [con('c1'), con('c2', {snapshot: {contractEnd: null}})]).state, 'CURRENT');
  });
  await cell('P-W8', '[r4c · F-R4B-1] 계약 양 경계 필수 — 시작 결손/null/빈값은 근거 아님 · 시작 형식오류·역전은 불명', () => {
    for (const snap of [{contractEnd: '2027-03-31'}, {contractStart: null, contractEnd: '2027-03-31'},
      {contractStart: '', contractEnd: '2027-03-31'}]) {
      const r = cw(noEnd(), [con('c1', {snapshot: snap})]);
      assert.strictEqual(r.state, 'UNKNOWN', JSON.stringify(snap));
      assert.ok(r.reasons.includes('CONTRACT_c1_START_MISSING_NOT_EVIDENCE'), JSON.stringify(snap));
    }
    for (const [snap, why] of [[{contractStart: '2026/11/02', contractEnd: '2027-03-31'}, 'CONTRACT_c1_START_MALFORMED'],
      [{contractStart: '2027-04-01', contractEnd: '2027-03-31'}, 'CONTRACT_c1_RANGE_REVERSED']]) {
      const r = cw(noEnd(), [con('c1', {snapshot: snap})]);
      assert.strictEqual(r.state, 'UNKNOWN', why); assert.ok(r.reasons.includes(why), why);
    }
    // 양 경계가 있는 다른 계약이 있으면 시작 결손 계약은 근거가 아닐 뿐 막지 않는다.
    assert.strictEqual(cw(noEnd(), [con('c1'), con('c2', {snapshot: {contractEnd: '2027-03-31'}})]).state, 'CURRENT');
    // 오늘 = 계약 시작일 0시 → CURRENT · 그 전날 → NOT_STARTED
    const s0 = kst(2026, 12, 1);
    const c0 = [con('c1', {snapshot: {contractStart: '2026-12-01', contractEnd: '2027-03-31'}})];
    assert.strictEqual(cw(noEnd(), c0, {nowMs: s0}).state, 'CURRENT');
    assert.strictEqual(cw(noEnd(), c0, {nowMs: s0 - 1}).state, 'NOT_STARTED');
  });
  await cell('P-W9', '[r4d · F-R4C-1] 종료일이 지난 계약도 양 날짜 형식·순서를 먼저 — 시작 오류/역전은 ENDED 아닌 불명', () => {
    const past = (o) => con('c9', {snapshot: Object.assign({contractStart: '2026-10-01', contractEnd: '2026-11-30'}, o)});
    // 단독
    let r = cw(noEnd(), [past({contractStart: '10/01'})]);
    assert.strictEqual(r.state, 'UNKNOWN'); assert.ok(r.reasons.includes('CONTRACT_c9_START_MALFORMED'));
    assert.ok(!r.reasons.includes('CONTRACT_c9_PERIOD_ENDED'), '형식오류를 종료로 숨겼다');
    r = cw(noEnd(), [past({contractStart: '2026-12-05'})]);
    assert.strictEqual(r.state, 'UNKNOWN'); assert.ok(r.reasons.includes('CONTRACT_c9_RANGE_REVERSED'));
    r = cw(noEnd(), [past({contractEnd: '2026/11/30'})]);
    assert.strictEqual(r.state, 'UNKNOWN'); assert.ok(r.reasons.includes('CONTRACT_c9_END_MALFORMED'));
    // 정상 현재 계약과 섞임 → 어긋난 자료가 있으면 열지 않는다
    assert.strictEqual(cw(noEnd(), [con('c1'), past({contractStart: '2026-12-05'})]).state, 'UNKNOWN');
    assert.strictEqual(cw(noEnd(), [con('c1'), past({contractStart: 'x'})]).state, 'UNKNOWN');
    // 정상 과거 단독 = ENDED · 정상 과거 + 정상 현재 = CURRENT
    r = cw(noEnd(), [past({})]);
    assert.strictEqual(r.state, 'ENDED'); assert.ok(r.reasons.includes('CONTRACT_c9_PERIOD_ENDED'));
    assert.strictEqual(cw(noEnd(), [con('c1'), past({})]).state, 'CURRENT');
    // 과거 종료 + 시작 결손 = 근거 아님(ENDED 로도 쓰지 않음)
    r = cw(noEnd(), [past({contractStart: null})]);
    assert.strictEqual(r.state, 'UNKNOWN'); assert.ok(r.reasons.includes('CONTRACT_c9_START_MISSING_NOT_EVIDENCE'));
  });
  await cell('P-W7', '호출 전제 방어 — CONFIRMED 아님 · 종료일 있음 · 장기 아님 → UNKNOWN', () => {
    assert.strictEqual(cw(noEnd({status: 'CONTRACT_PENDING'}), [con('c1')]).state, 'UNKNOWN');
    assert.strictEqual(cw(noEnd({workEndDate: new Ts(kst(2027, 1, 1))}), [con('c1')]).state, 'UNKNOWN');
    assert.strictEqual(cw(app(), [con('c1')]).state, 'UNKNOWN');
  });

  console.log('\n[P-D] 열람 기간(질문1 답 · Codex 정본 기록 전 · 경계 수식 = 기술 DRAFT)');
  await cell('P-D1', 'S1 근무일 당일·이전 — 열림 · 닫힘 없음 · 재판정 = L 다음 날 0시', () => {
    for (const now of [WORK_DAY + 10 * HOUR, WORK_DAY - DAY, WORK_DAY + DAY - 1]) {
      const w = win(app(), [], {nowMs: now});
      assert.strictEqual(w.state, 'S1_WORKING'); assert.strictEqual(w.open, true);
      assert.strictEqual(w.basis, 'LAST_WORK_DAY');
      assert.strictEqual(w.closesAtMs, null); assert.strictEqual(w.reevaluateAtMs, WORK_DAY + DAY);
    }
    assert.notStrictEqual(win(app(), [], {nowMs: WORK_DAY + DAY}).state, 'S1_WORKING');
  });
  await cell('P-D2', "S3 T30('나머지') — T = ①∪③ 최댓값 · 닫힘 = T + 30×24h · 기산 = LAST_PAYMENT", () => {
    const w = win(app(), [att('a', {transferDate: new Ts(PAY1)}),
      att('b', {finalWage: 0, transferDate: new Ts(PAY2)})]);
    assert.strictEqual(w.state, 'S3_SETTLED_T30'); assert.strictEqual(w.basis, 'LAST_PAYMENT');
    assert.strictEqual(w.tMs, PAY2); assert.strictEqual(w.closesAtMs, T30);
    assert.strictEqual(w.lMs, WORK_DAY, 'L 도 함께 돌려준다');
  });
  await cell('P-D3', 'T30 경계 −1ms 열림 · 정각 닫힘 · +1ms 닫힘', () => {
    const atts = [att('a', {transferDate: new Ts(PAY2)})];
    assert.strictEqual(win(app(), atts, {nowMs: T30 - 1}).open, true);
    assert.strictEqual(win(app(), atts, {nowMs: T30}).open, false);
    assert.strictEqual(win(app(), atts, {nowMs: T30 + 1}).open, false);
  });
  await cell('P-D4', '③ 단독도 S3 T30', () => {
    const w = win(app(), [att('a', {finalWage: 0, transferDate: new Ts(PAY1)})]);
    assert.strictEqual(w.state, 'S3_SETTLED_T30'); assert.strictEqual(w.tMs, PAY1);
  });
  await cell("P-D5", "S2 순수 미결(지급 기록 모두 확인) — 기존 T 규칙: 열림 · 30일 아직 안 셈('나머지' · Claude 해석)", () => {
    for (const o of [{wageStatus: 'pending', transferDate: undefined},
      {wageStatus: 'confirmed', finalWage: 0, transferDate: undefined},
      {wageStatus: 'calculated', transferDate: undefined}]) {
      const w = win(app(), [att('a'), att('b', o)], {nowMs: kst(2027, 3, 1)});
      assert.strictEqual(w.state, 'S2_PENDING', JSON.stringify(o));
      assert.strictEqual(w.open, true); assert.strictEqual(w.closesAtMs, null);
      assert.strictEqual(w.rule, 'T_RULE_PENDING'); assert.strictEqual(w.basis, 'LAST_PAYMENT');
    }
  });
  await cell('P-D6', 'A2 종료·지급 이력 없음(근태 0건 / ②만) → L30 · −1ms/정각/+1ms', () => {
    const only2 = [att('a', {wageStatus: 'confirmed', status: 'NO_SHOW', finalWage: 0, transferDate: undefined})];
    for (const [atts, rule] of [[[], 'A2_NO_ATTENDANCE'], [only2, 'A2_NONPAYABLE_ONLY']]) {
      const w = win(app(), atts);
      assert.strictEqual(w.state, 'A2_NO_PAYMENT_L30'); assert.strictEqual(w.rule, rule);
      assert.strictEqual(w.basis, 'LAST_WORK_DAY'); assert.strictEqual(w.closesAtMs, L30);
      assert.strictEqual(w.open, true); assert.strictEqual(w.tMs, null);
      assert.strictEqual(win(app(), atts, {nowMs: L30 - 1}).open, true);
      assert.strictEqual(win(app(), atts, {nowMs: L30}).open, false);
      assert.strictEqual(win(app(), atts, {nowMs: L30 + 1}).open, false);
    }
  });
  await cell('P-D7', '[PP-DELEGATION-20261118] L30 = KST(L) 0시 + 30×24h 배타 — 독립 oracle: L=11-18 → 12-18 00:00 KST 닫힘', () => {
    // 독립 기대: 모듈 함수가 아니라 KST 벽시계로 직접 만든 instant 와 비교한다.
    const L1118 = app({workDate: new Ts(kst(2026, 11, 18))});
    const close = kst(2026, 12, 18, 0, 0);
    const w = win(L1118, [], {nowMs: kst(2026, 12, 1)});
    assert.strictEqual(w.state, 'A2_NO_PAYMENT_L30'); assert.strictEqual(w.closesAtMs, close);
    assert.strictEqual(win(L1118, [], {nowMs: close - 1}).open, true, '12-17 23:59:59.999 열림');
    assert.strictEqual(win(L1118, [], {nowMs: close}).open, false, '12-18 00:00 정각 닫힘');
    assert.strictEqual(win(L1118, [], {nowMs: close + 1}).open, false);
    // 월 경계·연 경계도 같은 식(KST 는 일광절약 없음 — 30×24h 가 달력 30일).
    const Ldec = app({workDate: new Ts(kst(2026, 12, 20))});
    assert.strictEqual(win(Ldec, [], {nowMs: kst(2027, 1, 2)}).closesAtMs, kst(2027, 1, 19, 0, 0));
    // 채택하지 않은 식은 정책 값이 아니다.
    assert.throws(() => M.cr4LastWorkCloseMs(WORK_DAY, 'KST_L_PLUS_30D_END_OF_DAY'));
  });
  await cell('P-D8', 'A3 지급 기록만 불명 → L30 · 알려진 지급만으로 T 를 만들지 않는다(tMs null)', () => {
    const atts = [att('a', {transferDate: new Ts(PAY2)}), att('b', {transferDate: undefined})];
    const w = win(app(), atts);
    assert.strictEqual(w.state, 'A3_UNKNOWN_L30'); assert.strictEqual(w.rule, 'A3_UNKNOWN_ONLY');
    assert.strictEqual(w.tMs, null); assert.strictEqual(w.closesAtMs, L30);
    assert.ok(w.unknownReasons.includes('ATT_b_TRANSFER_DATE_INVALID'));
  });
  await cell("P-D9", "A3 미결 확인 + 불명 → 아직 줄 급여가 있어도 L30(S2 무상한 0)", () => {
    const atts = [att('a', {wageStatus: 'pending', transferDate: undefined}), att('b', {transferDate: undefined})];
    const w = win(app(), atts);
    assert.strictEqual(w.state, 'A3_UNKNOWN_L30'); assert.strictEqual(w.rule, 'A3_PENDING_AND_UNKNOWN');
    assert.strictEqual(w.counts.OPEN, 1); assert.strictEqual(w.closesAtMs, L30);
    assert.strictEqual(win(app(), atts, {nowMs: L30}).open, false, '미결이 남아도 L30 정각에 닫힌다(지급 전용 reader 는 별개)');
  });
  await cell('P-D10', 'A3 근태 잘림 → T·정산 종결을 만들지 않되 독립 L 의 L30 은 계산', () => {
    const w = win(app(), [att('a', {transferDate: new Ts(PAY2)})], {attendanceSetComplete: false});
    assert.strictEqual(w.state, 'A3_UNKNOWN_L30'); assert.strictEqual(w.tMs, null);
    assert.strictEqual(w.closesAtMs, L30); assert.strictEqual(w.evidence.attendanceComplete, false);
    assert.ok(w.unknownReasons.includes('ATTENDANCE_SET_TRUNCATED'));
  });
  await cell('P-D11', '[r4c · PP-R4B-A4] 현재 두 판본에 결속된 공통 지급 보완 → A4 L30(다른 근태 출처·수동 포함) · T 그대로 · 미결 아님', () => {
    const atts = [att('a', {transferDate: new Ts(PAY2)})];
    for (const c of [corr({sourceAttendanceId: 'a'}), corr({}), corr({sourceAttendanceId: 'zz'}),
      corr({status: 'RESUBMITTED'}), corr({sourceDomain: undefined, sourceApplicationId: 'a1',
        bankAccountVersionAtRequest: undefined})]) {
      const w = win(app(), atts, {corrections: [c]});
      assert.strictEqual(w.state, 'A4_CORRECTION_L30', JSON.stringify(c));
      assert.strictEqual(w.tMs, PAY2, 'T 그대로'); assert.strictEqual(w.closesAtMs, L30, 'L30 — T30 아님');
      assert.strictEqual(w.counts.accountCorrections, 1);
      assert.strictEqual(w.counts.OPEN, 0, '보완을 미결로 넣지 않는다');
    }
    assert.strictEqual(win(app(), atts, {corrections: [corr({})]}).counts.binding.PAYROLL_BOTH_VERSIONS, 1);
    assert.strictEqual(win(app(), atts, {corrections: [corr({sourceDomain: undefined, sourceApplicationId: 'a1'})]})
      .counts.binding.REVIEW_BANKBOOK_VERSION, 1);
  });
  await cell('P-D11b', '[r4c · PP-R4B-A4] 구판본·다른 관계 전용 보완은 제외 → S3 T30 · 판본/연결 불명은 A3 L30(결손을 0 으로 합성 0)', () => {
    const atts = [att('a', {transferDate: new Ts(PAY2)})];
    for (const [c, key] of [
      [corr({bankAccountVersionAtRequest: 0}), 'staleCorrections'],
      [corr({documentVersionAtRequest: 2}), 'staleCorrections'],
      [corr({sourceDomain: undefined, sourceApplicationId: 'a1', documentVersionAtRequest: 0}), 'staleCorrections'],
      [corr({sourceDomain: undefined, sourceApplicationId: 'a9'}), 'otherRelationCorrections'],
    ]) {
      const w = win(app(), atts, {corrections: [c]});
      assert.strictEqual(w.state, 'S3_SETTLED_T30', JSON.stringify(c));
      assert.strictEqual(w.counts[key], 1, key);
    }
    for (const [c, o, why] of [
      [corr({bankAccountVersionAtRequest: undefined}), {}, 'CORRECTION_PAYROLL_REQUEST_VERSION_INVALID'],
      [corr({documentVersionAtRequest: '1'}), {}, 'CORRECTION_PAYROLL_REQUEST_VERSION_INVALID'],
      [corr({bankAccountVersionAtRequest: 1.5}), {}, 'CORRECTION_PAYROLL_REQUEST_VERSION_INVALID'],
      [corr({}), {docVersions: {account: null, bankbook: 1}}, 'CORRECTION_CURRENT_VERSION_UNKNOWN'],
      [corr({sourceDomain: undefined, sourceApplicationId: undefined}), {}, 'CORRECTION_REVIEW_SOURCE_UNKNOWN'],
      [corr({sourceDomain: undefined, sourceApplicationId: 'a1', documentVersionAtRequest: undefined}), {},
        'CORRECTION_REVIEW_REQUEST_VERSION_INVALID'],
      [corr({sourceDomain: 'TAX_IDENTITY'}), {}, 'CORRECTION_SOURCE_DOMAIN_UNKNOWN'],
    ]) {
      const w = win(app(), atts, Object.assign({corrections: [c]}, o));
      assert.strictEqual(w.state, 'A3_UNKNOWN_L30', why);
      assert.strictEqual(w.rule, 'A3_SETTLED_CORRECTION_RECORD_UNKNOWN', why);
      assert.ok(w.unknownReasons.includes(why), why + ' ' + w.unknownReasons);
    }
    // 판본 결손 사용자 문서를 0 과 같다고 보지 않는다.
    assert.deepStrictEqual(M.cr4DocVersionsOf({}), {account: null, bankbook: null});
    assert.deepStrictEqual(M.cr4DocVersionsOf({bankAccountVersion: 0, bankbookDocumentVersion: 3}), {account: 0, bankbook: 3});
    assert.deepStrictEqual(M.cr4DocVersionsOf({bankAccountVersion: -1, bankbookDocumentVersion: '3'}), {account: null, bankbook: null});
  });
  await cell('P-D11c', '[r4c] 보완 발생/해소 · 계좌 변경 뒤 옛 요청 — 같은 근무관계에서 A4 ↔ S3 · 시계 재시작 0', () => {
    const atts = [att('a', {transferDate: new Ts(PAY2)})];
    assert.strictEqual(win(app(), atts).state, 'S3_SETTLED_T30');
    assert.strictEqual(win(app(), atts, {corrections: [corr({})]}).state, 'A4_CORRECTION_L30', '현재 판본 보완 발생');
    assert.strictEqual(win(app(), atts, {corrections: [corr({status: 'RESOLVED'})]}).state, 'S3_SETTLED_T30', '해소');
    // 근로자가 계좌를 바꿔 현재 판본이 2 가 되면 판본 1 의 옛 요청은 현재 문제가 아니다.
    const w = win(app(), atts, {corrections: [corr({})], docVersions: {account: 2, bankbook: 1}});
    assert.strictEqual(w.state, 'S3_SETTLED_T30'); assert.strictEqual(w.closesAtMs, T30);
  });
  await cell('P-D12', 'A4 결과 대조 — T > L(근무 뒤 지급)이면 보완이 열려 T30 보다 일찍 닫힌다 · T < L(선지급)이면 늦게', () => {
    const atts = [att('a', {transferDate: new Ts(PAY2)})];
    const at = kst(2026, 12, 22);
    assert.strictEqual(win(app(), atts, {nowMs: at}).open, true, '보완 없으면 T30 안');
    assert.strictEqual(win(app(), atts, {nowMs: at, corrections: [corr({})]}).open, false, '보완이 남으면 L30 지남');
    const lt = app({type: 'long_term', workEndDate: new Ts(kst(2027, 1, 31)), workDays: ['월']});
    const pre = [att('a', {transferDate: new Ts(kst(2026, 12, 20))})];
    const after = kst(2027, 2, 2);
    assert.strictEqual(win(lt, pre, {nowMs: after}).open, false, '선지급 T_ONLY — 종료 뒤 잔여 0일');
    const w = win(lt, pre, {nowMs: after, corrections: [corr({})]});
    assert.strictEqual(w.state, 'A4_CORRECTION_L30'); assert.strictEqual(w.closesAtMs, kst(2027, 1, 31) + 30 * DAY);
    assert.strictEqual(w.open, true);
  });
  await cell('P-D13', 'A4 전이 — 보완 해결 → T30 · 뒤에 유효 이체가 더해짐 → 여전히 A4(T 만 갱신, 닫힘 L30) · 늦게 열린 보완은 즉시 닫힘', () => {
    const atts = [att('a', {transferDate: new Ts(PAY1)})];
    assert.strictEqual(win(app(), atts, {corrections: [corr({status: 'RESOLVED'})]}).state, 'S3_SETTLED_T30');
    const more = [att('a', {transferDate: new Ts(PAY1)}), att('b', {transferDate: new Ts(PAY2)})];
    const w = win(app(), more, {corrections: [corr({})]});
    assert.strictEqual(w.state, 'A4_CORRECTION_L30'); assert.strictEqual(w.tMs, PAY2);
    assert.strictEqual(w.closesAtMs, L30);
    const late = kst(2026, 12, 21);
    assert.strictEqual(win(app(), more, {nowMs: late}).open, true);
    assert.strictEqual(win(app(), more, {nowMs: late, corrections: [corr({})]}).open, false);
  });
  await cell('P-D14', '보완은 미결이 아니다 — 미결 + 보완 → S2(T 규칙), 지급 없음 + 보완 → A2(같은 L30)', () => {
    const pend = [att('a', {wageStatus: 'pending', transferDate: undefined})];
    assert.strictEqual(win(app(), pend, {corrections: [corr({})]}).state, 'S2_PENDING');
    assert.strictEqual(win(app(), [], {corrections: [corr({})]}).state, 'A2_NO_PAYMENT_L30');
  });
  await cell('P-D15', '신분증·세무 보완은 계좌서류가 아니다 → S3 T30 · 모르는 문서종류/보완 잘림(종결 뒤) → A3 L30', () => {
    const atts = [att('a', {transferDate: new Ts(PAY2)})];
    const ids = [corr({documentType: 'ID'}), corr({documentType: 'ID', sourceDomain: 'TAX_IDENTITY'})];
    const w = win(app(), atts, {corrections: ids});
    assert.strictEqual(w.state, 'S3_SETTLED_T30'); assert.strictEqual(w.counts.nonAccountCorrections, 2);
    const u = win(app(), atts, {corrections: [corr({documentType: 'PASSPORT'})]});
    assert.strictEqual(u.state, 'A3_UNKNOWN_L30'); assert.strictEqual(u.rule, 'A3_SETTLED_CORRECTION_RECORD_UNKNOWN');
    assert.strictEqual(u.tMs, PAY2, '지급 기록은 확인됐다 — T 는 남긴다');
    const tr = win(app(), atts, {correctionSetComplete: false});
    assert.strictEqual(tr.state, 'A3_UNKNOWN_L30'); assert.ok(tr.unknownReasons.includes('CORRECTION_SET_TRUNCATED'));
    assert.strictEqual(tr.evidence.correctionComplete, false);
  });
  await cell('P-D16', '무결성 — 다른 사람·사업장 근태/보완 행이 섞이면 INTEGRITY 닫힘(기록 불명 L30 으로 완화 0)', () => {
    const w = win(app(), [att('a', {transferDate: new Ts(PAY2)}), att('b', {businessId: 'b2'})]);
    assert.strictEqual(w.state, 'INTEGRITY'); assert.strictEqual(w.open, false);
    assert.strictEqual(w.evidence.foreignAttendanceRows, 1);
    const c = win(app(), [att('a', {transferDate: new Ts(PAY2)})], {corrections: [corr({workerUid: 'w2'})]});
    assert.strictEqual(c.state, 'INTEGRITY'); assert.strictEqual(c.evidence.foreignCorrections, 1);
    assert.strictEqual(M.cr4ClosedKind(w), 'NEEDS_CONFIRMATION');
  });
  await cell('P-D16b', '[r4c · F-R4B-3] 무결성이 S1·A1 보다 먼저 — 다른 사람·사업장 근태/보완이 섞이면 S1·A1 도 닫힘', () => {
    const fa = att('x', {businessId: 'b2'});
    const fc = corr({workerUid: 'w2'});
    for (const extra of [{atts: [fa], cs: []}, {atts: [], cs: [fc]}]) {
      const s1 = win(app(), extra.atts, {nowMs: WORK_DAY + 10 * HOUR, corrections: extra.cs});
      assert.strictEqual(s1.state, 'INTEGRITY', 'S1 경로'); assert.strictEqual(s1.open, false);
      const a1 = win(noEnd(), extra.atts, {contracts: [con('c1')], corrections: extra.cs});
      assert.strictEqual(a1.state, 'INTEGRITY', 'A1 경로'); assert.strictEqual(a1.open, false);
    }
    // 무계좌·무서명 경로 음성: 서명 없는 계약이면 A1 아님 · 정상이면 S1/A1 그대로.
    assert.strictEqual(win(noEnd(), [], {contracts: [con('c1', {workerSignedAt: undefined})]}).state, 'L_UNKNOWN');
    assert.strictEqual(win(app(), [], {nowMs: WORK_DAY - DAY}).state, 'S1_WORKING', '유효 L 시작 전 열림 유지(PP-R4B-PRESTART)');
    assert.strictEqual(win(noEnd(), [], {contracts: [con('c1')]}).state, 'A1_CURRENT');
  });
  await cell('P-D17', 'L 자체 불명 — A2/A3/A4 는 계산 불가(L_UNKNOWN 닫힘) · T30·S2 는 L 없이 계산', () => {
    const bad = app({workDate: 'x'});
    assert.strictEqual(win(bad, []).state, 'L_UNKNOWN');
    assert.strictEqual(win(bad, [att('a', {transferDate: undefined})]).state, 'L_UNKNOWN');
    assert.strictEqual(win(bad, [att('a', {transferDate: new Ts(PAY2)})], {corrections: [corr({})]}).state, 'L_UNKNOWN');
    const s3 = win(bad, [att('a', {transferDate: new Ts(PAY2)})]);
    assert.strictEqual(s3.state, 'S3_SETTLED_T30'); assert.strictEqual(s3.lMs, null);
    assert.ok(s3.unknownReasons.includes('L_MALFORMED_workDate'));
    assert.strictEqual(win(bad, [att('a', {wageStatus: 'pending', transferDate: undefined})]).state, 'S2_PENDING');
    const lu = win(bad, []);
    assert.strictEqual(lu.open, false); assert.strictEqual(lu.basis, 'NONE');
    assert.ok(lu.reasons.includes('A2_NO_ATTENDANCE_NEEDS_LAST_WORK_DAY'));
  });
  await cell('P-D18', '장기 · 퇴사/해지 승인인데 실제 종료일 없음 → 남은 workEndDate 를 L 로 쓰지 않는다(S1 으로 열지 않음)', () => {
    const lt = app({type: 'long_term', workEndDate: new Ts(kst(2027, 6, 30)), workDays: ['월'],
      terminationStatus: 'APPROVED'});
    const w = win(lt, []);
    assert.notStrictEqual(w.state, 'S1_WORKING'); assert.strictEqual(w.state, 'L_UNKNOWN');
    assert.ok(w.unknownReasons.includes('L_ENDED_DECISION_WITHOUT_RESIGN_DATE'));
    const ok = win(app({type: 'long_term', workEndDate: new Ts(kst(2027, 6, 30)), workDays: ['월'],
      terminationStatus: 'APPROVED', actualResignDate: new Ts(kst(2026, 11, 25))}), []);
    assert.strictEqual(ok.state, 'A2_NO_PAYMENT_L30'); assert.strictEqual(ok.lMs, kst(2026, 11, 25));
  });
  await cell('P-D19', 'A1 결손 예외 — 현재 근무 별도 확인 → 열림(기산 CURRENT_WORK · 닫힘 없음 · 재판정 = 계약 끝 다음 날) · 과거 출근 1건만으로는 A1 아님', () => {
    const w = win(noEnd(), [], {contracts: [con('c1')]});
    assert.strictEqual(w.state, 'A1_CURRENT'); assert.strictEqual(w.open, true);
    assert.strictEqual(w.basis, 'CURRENT_WORK'); assert.strictEqual(w.closesAtMs, null);
    assert.strictEqual(w.reevaluateAtMs, CON_END + DAY); assert.strictEqual(w.lMs, null, '계약 끝을 L 로 쓰지 않는다');
    const ended = win(noEnd(), [], {contracts: [con('c1')], nowMs: CON_END + DAY});
    assert.strictEqual(ended.state, 'L_UNKNOWN', '계약 기간이 끝나면 L 이 없어 계산 불가(근거 보완 필요)');
    assert.strictEqual(w.currentWork.contractId, 'c1'); assert.strictEqual(w.evidence.contractComplete, true);
    const past = win(noEnd(), [att('a', {transferDate: new Ts(PAY1)})], {contracts: []});
    assert.notStrictEqual(past.state, 'A1_CURRENT');
    assert.strictEqual(past.state, 'S3_SETTLED_T30', '근거 없음 → L 불명 · 지급 종결은 T30');
    assert.ok(past.unknownReasons.includes('L_NO_END_CURRENT_WORK_UNKNOWN'));
  });
  await cell('P-D20', 'A1 시작 전 — 닫힘(미시작 근무에 새 열람 0 · 정책 스위치 없음)', () => {
    const fut = kst(2026, 12, 15);
    const a = noEnd({desiredStartDate: new Ts(fut)});
    const w = win(a, [], {contracts: [con('c1')]});
    assert.strictEqual(w.state, 'A1_NOT_STARTED'); assert.strictEqual(w.open, false);
    assert.strictEqual(M.cr4ClosedKind(w), 'NOT_STARTED');
    assert.strictEqual(win(a, [], {contracts: [con('c1')], nowMs: fut}).state, 'A1_CURRENT', '시작일 0시부터');
  });
  await cell('P-D21', 'A1 전이 — 근거 소실(계약 무효)·종료 승인(날짜 없음) → L 불명 → 지급 없음이면 계산 불가 닫힘 · 퇴사일이 생기면 L 기준으로', () => {
    for (const [a, cs] of [[noEnd(), [con('c1', {status: 'voided'})]], [noEnd({resignStatus: 'APPROVED'}), [con('c1')]]]) {
      const w = win(a, [], {contracts: cs});
      assert.strictEqual(w.state, 'L_UNKNOWN'); assert.strictEqual(w.open, false);
    }
    const r = noEnd({resignStatus: 'APPROVED', actualResignDate: new Ts(kst(2026, 11, 28))});
    const w = win(r, [], {contracts: [con('c1')]});
    assert.strictEqual(w.state, 'A2_NO_PAYMENT_L30'); assert.strictEqual(w.closesAtMs, kst(2026, 11, 28) + 30 * DAY);
    assert.strictEqual(w.currentWork, null, 'NO_END 가 아니면 계약을 보지 않는다');
  });
  await cell('P-D22', '선지급 T_ONLY 유지 — 근무 중 S1, 종료 뒤 T30 이 이미 지났으면 닫힘', () => {
    const lt = app({type: 'long_term', workEndDate: new Ts(kst(2027, 1, 31)), workDays: ['월']});
    const pre = kst(2026, 12, 20);
    const atts = [att('a', {transferDate: new Ts(pre)})];
    assert.strictEqual(win(lt, atts, {nowMs: kst(2027, 1, 31, 23, 59)}).state, 'S1_WORKING');
    const a = win(lt, atts, {nowMs: kst(2027, 2, 2)});
    assert.strictEqual(a.state, 'S3_SETTLED_T30'); assert.strictEqual(a.closesAtMs, pre + 30 * DAY);
    assert.strictEqual(a.open, false);
  });
  await cell('P-D23', '이체취소 → confirmed 미결 → S2 · 재이체 뒤 새 T', () => {
    const cancelled = att('b', {wageStatus: 'confirmed', transferDate: undefined});
    assert.strictEqual(win(app(), [att('a'), cancelled], {nowMs: PAY1 + 30 * DAY + 1}).state, 'S2_PENDING');
    const re = kst(2027, 1, 5);
    assert.strictEqual(win(app(), [att('a'), att('b', {transferDate: new Ts(re)})], {nowMs: re + 1}).tMs, re);
  });
  await cell('P-D24', 'DRAFT 정책 값 — 옛 스위치 없음(질문1 확정으로 대체) · 경계 수식·선지급만', () => {
    assert.deepStrictEqual(P, {lastWorkBoundary: 'KST_L_PLUS_30D', prepaid: 'T_ONLY'});
    for (const k of ['noPayment', 'unknownEvidence', 'mixedPendingUnknown', 'settledWithOpenCorrection',
      'linkedOpenCorrection', 'noEndWorking', 'noEndNotStarted']) {
      assert.ok(!(k in P), k);
      assert.ok(!SRC.includes(`${k}:`), k + ' 가 소스에 남아 있다');
    }
  });
  await cell('P-D25', '반환 계약 — 상태·허용·기산·L·T·현재근무·닫힘·재판정·불명 사유·완전성·집계', () => {
    const w = win(app(), [att('a', {transferDate: new Ts(PAY2)})]);
    assert.deepStrictEqual(Object.keys(w).sort(), ['basis', 'closesAtMs', 'counts', 'currentWork',
      'evidence', 'lField', 'lMs', 'open', 'reasons', 'reevaluateAtMs', 'rule', 'state', 'tMs',
      'unknownReasons'].sort());
    assert.deepStrictEqual(Object.keys(w.evidence).sort(), ['attendanceComplete', 'contractComplete',
      'correctionComplete', 'docVersions', 'foreignAttendanceRows', 'foreignCorrections']);
    assert.deepStrictEqual(w.evidence.docVersions, CUR);
    assert.strictEqual(w.evidence.contractComplete, null, 'NO_END 아니면 계약 미조회 = null');
    assert.strictEqual(w.lField, 'workDate');
  });
  await cell('P-D26', '닫힘 구분 — 기간 종료 / 확인 필요 / 시작 전 · 열려 있으면 null', () => {
    assert.strictEqual(M.cr4ClosedKind(win(app(), [], {nowMs: L30})), 'PERIOD_ENDED');
    assert.strictEqual(M.cr4ClosedKind(win(app({workDate: 'x'}), [])), 'NEEDS_CONFIRMATION');
    assert.strictEqual(M.cr4ClosedKind(win(app(), [])), null);
  });

  console.log('\n[P-E] 새 서명 URL 만료 · 서명 직전 재판정');
  const exp = M.cr4BankbookUrlExpiryMs;
  await cell('P-E1', 'S2 · A1 → now+1h', () => {
    assert.strictEqual(exp(win(app(), [att('a', {wageStatus: 'pending', transferDate: undefined})]), NOW), NOW + HOUR);
    assert.strictEqual(exp(win(noEnd(), [], {contracts: [con('c1')]}), NOW), NOW + HOUR);
  });
  await cell('P-E2', 'T30·L30 남은 기간 > 1h → now+1h, < 1h → 닫히는 시각', () => {
    const atts = [att('a', {transferDate: new Ts(PAY2)})];
    assert.strictEqual(exp(win(app(), atts), NOW), NOW + HOUR);
    const near = T30 - 10 * MIN;
    assert.strictEqual(exp(win(app(), atts, {nowMs: near}), near), T30);
    const nl = L30 - 10 * MIN;
    assert.strictEqual(exp(win(app(), [], {nowMs: nl}), nl), L30);
  });
  await cell('P-E3', '정각·이후·L_UNKNOWN·INTEGRITY·A1 시작 전(DRAFT) 은 발급 0', () => {
    const atts = [att('a', {transferDate: new Ts(PAY2)})];
    assert.strictEqual(exp(win(app(), atts, {nowMs: T30}), T30), null);
    assert.strictEqual(exp(win(app(), [], {nowMs: L30}), L30), null);
    assert.strictEqual(exp(win(app({workDate: 'x'}), []), NOW), null);
    assert.strictEqual(exp(win(app(), [att('a', {businessId: 'b2'})]), NOW), null);
    assert.strictEqual(exp(win(noEnd({desiredStartDate: new Ts(kst(2026, 12, 15))}), [], {contracts: [con('c1')]}), NOW), null);
  });
  await cell('P-E4', 'S1 마지막 한 시간 — URL 이 L 다음 날 0시를 넘지 않는다(재판정 시각 상한)', () => {
    const t = WORK_DAY + DAY - 20 * MIN;
    assert.strictEqual(exp(win(app(), [], {nowMs: t}), t), WORK_DAY + DAY);
  });
  await cell('P-E5', '서명 직전 재판정 — 판정 S1(열림) 뒤 날짜가 넘어가 선지급 T30 이 지난 상태면 발급 0', () => {
    const lt = app({type: 'long_term', workEndDate: new Ts(kst(2027, 1, 31)), workDays: ['월']});
    const input = {app: lt, applicationId: 'a1', attendances: [att('a', {transferDate: new Ts(kst(2026, 12, 20))})],
      attendanceSetComplete: true, corrections: [], correctionSetComplete: true, contracts: null,
      contractSetComplete: true, business: {}, nowMs: kst(2027, 2, 1) - 1, policy: P, docVersions: CUR};
    assert.strictEqual(M.cr4BankWindow(input).state, 'S1_WORKING');
    const s = M.cr4SignableExpiryMs(input, kst(2027, 2, 1));
    assert.strictEqual(s.window.state, 'S3_SETTLED_T30'); assert.strictEqual(s.expiresMs, null);
  });
  await cell('P-E6', '서명 직전 재판정 — L30·T30 정각을 넘으면 발급 0, 1ms 전이면 그 정각까지', () => {
    const base = {app: app(), applicationId: 'a1', attendances: [], attendanceSetComplete: true,
      corrections: [], correctionSetComplete: true, contracts: null, contractSetComplete: true,
      business: {}, nowMs: L30 - 5 * MIN, policy: P, docVersions: CUR};
    assert.strictEqual(M.cr4SignableExpiryMs(base, L30 - 1).expiresMs, L30);
    assert.strictEqual(M.cr4SignableExpiryMs(base, L30).expiresMs, null);
  });
  await cell('P-E7', '열린 창이라도 now ≥ closesAt 이면 null(방어)', () => {
    assert.strictEqual(exp({open: true, closesAtMs: NOW, reevaluateAtMs: null}, NOW), null);
  });

  console.log('\n[P-F] 재배치 원동의 승계(양방향 계보)');
  const inh = (src, now = T1 + HOUR) => M.cr4ConsentInheritance(src, now, GEN, CR_KIND);
  const inherited = (o = {}) => app(Object.assign({documentAccessConsentSource: 'REASSIGN_INHERITED',
    documentAccessConsentInheritedFrom: 'a0', sourceApplicationId: 'a0', offerKind: CR_KIND,
    reassignmentProposalId: 'p1', appliedAt: new Ts(T1), confirmedAt: new Ts(T1)}, o));
  await cell('P-F1', 'v4 유효 → 승계, At 은 원 객체 그대로(새 시각 0)', () => {
    const a = app();
    const r = inh(a);
    assert.strictEqual(r.ok, true);
    assert.strictEqual(r.fields.documentAccessConsentAt, a.documentAccessConsentAt);
    assert.strictEqual(r.fields.documentAccessConsentVersion, V4);
  });
  await cell('P-F2', 'invite-v2 (초대 사전 동의 원시각 t0 < 수락 t1) → 승계, At=t0', () => {
    const r = inh(app({documentAccessConsentVersion: INV2, confirmedAt: new Ts(T1)}));
    assert.strictEqual(r.ok, true); assert.strictEqual(r.fields.documentAccessConsentAt.toMillis(), T0);
  });
  await cell('P-F3', 'A→B→C — B(Source=REASSIGN_INHERITED · parent=A · 계보 정합)에서 C 로 다시 승계, At 원시각', () => {
    const r = inh(inherited(), T1 + DAY);
    assert.strictEqual(r.ok, true); assert.strictEqual(r.fields.documentAccessConsentAt.toMillis(), T0);
  });
  await cell('P-F4', 'EXPLICIT 로 생긴 재배치 관계(parent 없음 · REASSIGN_EXPLICIT) 는 정상 직접 동의 — 승계 가능', () => {
    const b = app({documentAccessConsentSource: 'REASSIGN_EXPLICIT', offerKind: CR_KIND,
      reassignmentProposalId: 'p1', sourceApplicationId: 'a0'});
    assert.strictEqual(inh(b).ok, true);
  });
  await cell('P-F5', '양방향 계보 결손 → LINEAGE_INCONSISTENT(세부)', () => {
    const cases = [
      [inherited({documentAccessConsentInheritedFrom: undefined}), 'INHERITED_WITHOUT_PARENT'],
      [app({documentAccessConsentInheritedFrom: 'a0', sourceApplicationId: 'a0', offerKind: CR_KIND,
        reassignmentProposalId: 'p1', documentAccessConsentSource: 'APPLY'}), 'PARENT_WITHOUT_INHERITED_SOURCE'],
      [app({documentAccessConsentInheritedFrom: 'a0', sourceApplicationId: 'a0', offerKind: CR_KIND,
        reassignmentProposalId: 'p1'}), 'PARENT_WITHOUT_INHERITED_SOURCE'],
      [inherited({documentAccessConsentSource: 7}), 'SOURCE_MALFORMED'],
      [inherited({documentAccessConsentInheritedFrom: ''}), 'PARENT_MALFORMED'],
      [inherited({documentAccessConsentInheritedFrom: 9}), 'PARENT_MALFORMED'],
      [inherited({sourceApplicationId: 'zz'}), 'PARENT_NOT_SOURCE'],
      [inherited({offerKind: 'ALTERNATIVE_WORK'}), 'OFFER_KIND'],
      [inherited({reassignmentProposalId: ''}), 'PROPOSAL_ID'],
      [inherited({reassignmentProposalId: undefined}), 'PROPOSAL_ID'],
    ];
    for (const [src, detail] of cases) {
      const r = inh(src);
      assert.strictEqual(r.ok, false, detail);
      assert.strictEqual(r.reason, 'LINEAGE_INCONSISTENT', detail);
      assert.strictEqual(r.detail, detail);
    }
  });
  await cell('P-F6', 'given/판본/At 결손·형식·미래 — r4 와 같은 이유', () => {
    for (const g of [undefined, false, 'true', 1]) {
      assert.strictEqual(inh(app({documentAccessConsentGiven: g})).reason, 'GIVEN_NOT_TRUE', String(g));
    }
    assert.strictEqual(inh(app({documentAccessConsentVersion: undefined})).reason, 'VERSION_MISSING');
    for (const v of [V1, V2, V3, INV1, 'v9', 4]) {
      assert.strictEqual(inh(app({documentAccessConsentVersion: v})).reason, 'VERSION_NOT_INHERITABLE', String(v));
    }
    assert.strictEqual(inh(app({documentAccessConsentVersion: null})).reason, 'VERSION_MISSING');
    assert.strictEqual(inh(app({documentAccessConsentAt: undefined})).reason, 'AT_MISSING');
    for (const v of [T0, '2026-11-10', new Date(T0), {toMillis: () => NaN}]) {
      assert.strictEqual(inh(app({documentAccessConsentAt: v})).reason, 'AT_MALFORMED', String(v));
    }
    assert.strictEqual(inh(app({documentAccessConsentAt: new Ts(T1 + 2 * HOUR)})).reason, 'AT_FUTURE');
    assert.strictEqual(inh(app({documentAccessConsentAt: new Ts(T1 + HOUR)})).ok, true, '같은 ms 는 통과');
  });
  await cell('P-F7', '신분증 legacy 축은 유효할 때만 옮긴다(값을 만들지 않음)', () => {
    const r = inh(app({idCardConsentGiven: undefined, idCardConsentAt: undefined}));
    assert.strictEqual(r.ok, true);
    assert.ok(!('idCardConsentGiven' in r.fields) && !('idCardConsentAt' in r.fields));
    const r2 = inh(app({idCardConsentAt: 'bad'}));
    assert.ok(!('idCardConsentAt' in r2.fields));
    const a = app();
    assert.strictEqual(inh(a).fields.idCardConsentAt, a.idCardConsentAt, '유효하면 원 객체 그대로(새 시각 0)');
  });

  console.log('\n[P-G] 재배치 제안 ↔ A 계보');
  const prop = (o = {}) => Object.assign({sourceApplicationId: 'a1', uid: 'w1', businessId: 'b1',
    targetToId: 't1', targetSlotId: 's1', sourceWdId: 'wd-1', workDate: new Ts(WORK_DAY)}, o);
  const lb = (p, s, caller = 'w1', id = 'a1') => M.cr4LineageBlock(p, s, caller, id);
  await cell('P-G1', '모두 같으면 null', () => assert.strictEqual(lb(prop(), app()), null));
  await cell('P-G2', '각 항목 불일치 코드', () => {
    assert.strictEqual(lb(prop({sourceApplicationId: 'zz'}), app()), 'SOURCE_ID');
    assert.strictEqual(lb(prop({uid: 'w9'}), app()), 'UID');
    assert.strictEqual(lb(prop(), app({uid: 'w9'})), 'UID');
    assert.strictEqual(lb(prop(), app(), 'w9'), 'UID');
    assert.strictEqual(lb(prop(), app({businessId: 'b2'})), 'BUSINESS');
    assert.strictEqual(lb(prop(), app({toId: 't2'})), 'TO');
    assert.strictEqual(lb(prop(), app({slotId: 's2'})), 'SLOT');
    assert.strictEqual(lb(prop(), app({wdId: 'wd-9'})), 'SOURCE_WD');
    assert.strictEqual(lb(prop(), app({workDate: new Ts(WORK_DAY + DAY)})), 'WORK_DATE');
    assert.strictEqual(lb(prop({workDate: 'x'}), app()), 'WORK_DATE');
    assert.strictEqual(lb(prop(), app({workDate: undefined})), 'WORK_DATE');
  });
  await cell('P-G3', '제안 sourceWdId 가 없으면 wdId 는 비교하지 않는다', () => {
    assert.strictEqual(lb(prop({sourceWdId: null}), app({wdId: 'other'})), null);
  });

  console.log('\n[P-Z] 모듈 경계');
  await cell('P-Z1', 'consent_r4.ts 에 import·판본 문자열이 없다(판본 단일 소유자 = index.ts)', () => {
    assert.ok(!/^\s*import\s/m.test(SRC));
    for (const v of [V1, V2, V3, INV1, V4, INV2]) assert.ok(!SRC.includes(v), v);
  });

  summary();
})();
