/**
 * [CONSENT-R4c] 후보 index.ts 의 판본·writer·reader 계약 — 원문을 잘라 실행 + 순서 고정.
 *   r4c(r4b 판 3e8c76df 대체): I-S7 통장 reader 의 단일 사용자 snapshot · I-S11 계좌 reader 의
 *   '로그 뒤 최종 재판정'과 최종 window · I-S3b INHERIT 명시 동의 키 존재 거절.
 *   계좌 reader 의 로그 대기 중 경계 넘김·무계좌 실행 반례는 consent_r4d_callables.test.js AR-* 가 본다.
 *
 *   작성만 했다 — 이번 배정 실행 0. 통과 결과가 아니다.
 *   r4 판 consent_r4_index.test.js(dca69262)를 대체한다. 바뀐 기대(교체 대응 = r4b_test_change_map.tsv):
 *     · 동의 전용 writer 는 payload 의 documentAccessConsentGiven === true 를 읽는다(C-R4-1) — 없거나
 *       false·문자열이면 읽기 전에 CONSENT_NOT_GIVEN(쓰기 0 · 읽기 0). 아래 req() 가 기본으로 given:true 를
 *       싣는 것은 후보 클라이언트(my_applications_screen 후보)가 '동의하기' 뒤 보내는 모양과 같게 하려는
 *       하네스 모양이다 — given 결손 기대는 I-D0 이 따로 고정한다.
 *     · '이미 동의' = 같은 세대 + Given true + At 유효·비미래(C-R4-2 · srvConsentValidSameGeneration).
 *     · 덮어쓸 때 prev* 에 출처·parent 도 남기고, 낡은 inheritedFrom 은 지운다(FieldValue.delete).
 *     · 초대 수락 보존 판정은 index.ts srvInviteAcceptConsentPlan(r4 cr4InviteAcceptConsentPlan 대체).
 *     · 확정자 통장사본 = 판본 → 기간 판정(계약은 NO_END 일 때만) → 서명 직전 재판정 → 서명.
 *     · 새 목적별 계좌 reader callableGetWorkerPayrollAccount 의 순서·상태 코드.
 *
 *   방식은 기존 `test/invite_preaccept_consent.test.js` 와 같다(원문 추출 → TypeScript 변환 →
 *   가짜 Firestore/admin/Date 주입). 추출 도우미는 그 파일의 19–82줄을 그대로 옮겼다(A sha256 df6c6842…).
 *
 *   실행(제안 · LOCAL 계약 F3 · 실행권 0):
 *     cwd = A_copy/functions
 *     <R 안 node> test/consent_r4b_index.test.js
 *   입력: ../src/index.ts(후보 적용본) · ../../lib/widgets/dialogs/apply/document_access_consent.dart(후보)
 *         · node_modules/typescript. 네트워크·Firestore 0. 성공 = '통과 N / 실패 0' · rc 0.
 */
'use strict';
// [r5 · 판정 consent1121 §3] 외부 HTTP · 소켓 · DNS · fetch 진입점 차단 — 닿으면 그 자리에서 throw 하고 기록한다.
//   에뮬레이터 · DEV · 네트워크 0. 기록이 하나라도 있으면 끝에서 그 사실을 마지막 줄로 남기고 rc 1(성공 줄 '통과 N / 실패 0' 이 마지막 줄이 아니게 된다).
const R5_NET = [];
for (const [m, ks] of [['http', ['request', 'get']], ['https', ['request', 'get']], ['net', ['connect', 'createConnection']],
  ['tls', ['connect']], ['dns', ['lookup', 'resolve', 'resolve4', 'resolve6']]]) {
  const mod = require(m);
  for (const k of ks) {
    mod[k] = () => { R5_NET.push(`${m}.${k}`); throw new Error(`[r5 차단] ${m}.${k}`); };
  }
}
globalThis.fetch = () => { R5_NET.push('fetch'); throw new Error('[r5 차단] fetch'); };
process.on('exit', () => {
  if (R5_NET.length) {
    console.log('[r5 차단] 외부 진입 시도: ' + R5_NET.join(', '));
    process.exitCode = 1;
  }
});
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const ts = require('typescript');
const C = require('./consent_r4_clock');

const IDX = path.join(__dirname, '..', 'src', 'index.ts');
const DART = path.join(__dirname, '..', '..', 'lib', 'widgets', 'dialogs', 'apply',
  'document_access_consent.dart');
const SRC = fs.readFileSync(IDX, 'utf8');
const DSRC = fs.readFileSync(DART, 'utf8');
const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
console.log('index.ts sha256=' + sha(IDX));
console.log('document_access_consent.dart sha256=' + sha(DART));

// ── 원문 추출(기존 시험과 같은 코드) ──────────────────────────────────────
function balancedFrom(src, start, open, close) {
  const i = src.indexOf(open, start);
  let d = 0;
  for (let k = i; k < src.length; k++) {
    const c = src[k];
    if (c === '"' || c === '\'' || c === '`') {
      const q = c; k++;
      while (k < src.length && src[k] !== q) { if (src[k] === '\\') k++; k++; }
      continue;
    }
    if (c === '/' && src[k + 1] === '/') { while (k < src.length && src[k] !== '\n') k++; continue; }
    if (c === '/' && src[k + 1] === '*') { k += 2; while (!(src[k] === '*' && src[k + 1] === '/')) k++; k++; continue; }
    if (c === open) d++;
    else if (c === close) { d--; if (d === 0) return k; }
  }
  throw new Error('균형이 맞지 않는다: ' + src.slice(start, start + 60));
}
const AST = ts.createSourceFile('index.ts', SRC, ts.ScriptTarget.ES2020, true);
const FN_DECLS = new Map();
for (const st of AST.statements) {
  if (ts.isFunctionDeclaration(st) && st.name) FN_DECLS.set(st.name.text, st.getText(AST));
}
function cutFn(name) {
  const t = FN_DECLS.get(name);
  assert.ok(t, `함수 원문 없음: ${name}`);
  return t;
}
function cutConst(name) {
  const re = new RegExp(`^const\\s+${name}\\b[^=]*=`, 'm');
  const m = re.exec(SRC);
  assert.ok(m, `상수 원문 없음: ${name}`);
  let k = m.index + m[0].length;
  let d = 0;
  for (; k < SRC.length; k++) {
    const c = SRC[k];
    if (c === '"' || c === '\'' || c === '`') {
      const q = c; k++;
      while (SRC[k] !== q) { if (SRC[k] === '\\') k++; k++; }
      continue;
    }
    if ('([{'.includes(c)) d++;
    else if (')]}'.includes(c)) d--;
    else if (c === ';' && d === 0) return SRC.slice(m.index, k + 1);
  }
  throw new Error('상수 끝 없음: ' + name);
}
function cutCallable(name) {
  const head = `export const ${name} = onCall(`;
  const i = SRC.indexOf(head);
  assert.ok(i >= 0, `callable 원문 없음: ${name}`);
  const end = balancedFrom(SRC, i + head.length - 1, '(', ')');
  return 'const ' + SRC.slice(i + 'export const '.length, end + 1) + ';';
}
function callableSrc(name) {
  const i = SRC.indexOf(`export const ${name} = onCall(`);
  assert.ok(i >= 0, name);
  return SRC.slice(i, SRC.indexOf('\nexport const ', i + 10));
}

const CONSTS = ['SRV_KST_MS', 'CONFIRMED_STATUSES', 'DOC_MATCH_MISSING',
  'DOC_MATCH_UNASSESSED', 'DOC_MATCH_MATCHED', 'DOC_MATCH_MISMATCH',
  'DOC_MATCH_OCR_UNCERTAIN', 'SRV_DOC_MATCH_MISSING', 'REVIEW_NOT_REVIEWED',
  'REVIEW_OK', 'MR_READY_AUTO', 'MR_READY_MANUAL', 'MR_ID_MISSING',
  'MR_ID_MISMATCH', 'MR_ID_OCR_UNCERTAIN', 'MR_ID_UNASSESSED',
  'DOCUMENT_ACCESS_CONSENT_V3', 'DOCUMENT_ACCESS_CONSENT_INVITE_V1',
  'DOCUMENT_ACCESS_CONSENT_V4', 'DOCUMENT_ACCESS_CONSENT_INVITE_V2',
  'REVIEW_PURPOSE_CONSENT_VERSIONS', 'ID_CARD_ACCESS_WINDOW_MS',
  'DOCUMENT_ACCESS_CONSENT_V1', 'DOCUMENT_ACCESS_CONSENT_V2',
  'RETIRED_DOCUMENT_ACCESS_CONSENT_VERSIONS', 'NEW_REQUEST_CONSENT_VERSION_GENERAL',
  'NEW_REQUEST_CONSENT_VERSION_INVITE', 'SUPPORTED_DOCUMENT_ACCESS_CONSENT_VERSIONS',
  'APPLICANT_REVIEW_STATUSES', 'ACCOUNT_STATUS_DELETING',
  'SRV_INVITE_READINESS_WORKER_MESSAGE', 'ID_LONG_TERM_TYPES', 'ID_SHORT_TERM_TYPES',
  'SRV_INTAKE_AUTO_UNIT_REASON', 'SRV_INTAKE_AUTO_TO_REASONS',
  'SRV_INVITE_RECRUIT_ENDED_MESSAGE'];
const FNS = ['srvKstDateNum', 'srvDocumentVersionsOf', 'srvBuildMatchingProvenance',
  'srvAssertNotDeletingAccount', 'srvConsentVersionReject', 'srvPrevConsentEvidence',
  // [CONSENT-R4b] 동의 전용 writer·초대 수락이 함께 쓰는 같은 세대 판정
  'srvConsentAtValidMs', 'srvConsentValidSameGeneration', 'srvInviteAcceptConsentPlan',
  'resolveDocumentAccessConsentVersion', 'srvResolveCommitmentConsentVersion',
  'srvConsentCoversApplicantReview', 'srvInviteReviewWindowOpen',
  'srvApplicantReviewAccessBlockAsync', 'srvIdWindowLastWorkDay', 'srvKstMidnightMsOf',
  'srvIdWindowOpen', 'srvKstDayStartMs', 'srvShiftStartMsFrom', 'srvIsLongTermInvite',
  'srvResolveGuardShiftStart', 'srvResolveIdCardMatch',
  'srvResolveMatchingReadiness', 'srvInviteAcceptReadiness',
  'srvInviteWindowClosed', 'srvApplicantReviewAccessBlock',
  'srvInviteConsentWindowBlock', 'srvInviteConsentWindowBlockTx',
  'srvInviteRecruitClosureBlock', 'srvToClosedByApplicationDeadline'];

// ── 스텁 ────────────────────────────────────────────────────────────────
class HttpsError extends Error {
  constructor(code, message, details) { super(message); this.code = code; this.details = details; }
}
const {Ts, kst, DAY, HOUR, V4, INV2, V1, V2, V3, INV1, RETIRED, T0, cell, summary} = C;
let NOW = 0;
class FakeDate extends Date {
  constructor(...a) { if (a.length === 0) super(NOW); else super(...a); }
  static now() { return NOW; }
}
const DELETE = Object.freeze({__delete: true});
const admin = {firestore: {
  Timestamp: {now: () => new Ts(NOW), fromMillis: (ms) => new Ts(ms)},
  // [CONSENT-R4b] 낡은 승계 parent 삭제 표식(하네스 모양) — 저장 시 그 키를 지운다.
  FieldValue: {arrayUnion: (...x) => ({__arrayUnion: x}), delete: () => DELETE},
}};
let STORE = new Map();
let WRITES = [];
let READS = 0;
function ref(p) {
  return {
    path: p,
    collection: (c) => ({doc: (d) => ref(`${p}/${c}/${d}`)}),
    get: async () => {
      READS++;
      const v = STORE.get(p);
      return {exists: v !== undefined, data: () => v, get: (k) => (v || {})[k]};
    },
  };
}
function query(col, filters = [], lim = 1e9) {
  const q = {
    where: (f, op, v) => query(col, [...filters, [f, op, v]], lim),
    orderBy: () => q,
    limit: (n) => query(col, filters, n),
    get: async () => {
      READS++;
      const docs = [...STORE.entries()]
        .filter(([k]) => k.startsWith(col + '/') && k.split('/').length === 2)
        .filter(([, v]) => filters.every(([f, op, x]) =>
          op === 'in' ? x.includes(v[f]) : v[f] === x))
        .slice(0, lim)
        .map(([k, v]) => ({id: k.split('/')[1], data: () => v}));
      return {docs, empty: docs.length === 0};
    },
  };
  return q;
}
const db = {
  collection: (c) => Object.assign(query(c), {doc: (d) => ref(`${c}/${d}`)}),
  runTransaction: async (cb) => {
    const pending = [];
    const tx = {
      get: async (r) => {
        READS++;
        const v = STORE.get(r.path);
        return {exists: v !== undefined, data: () => v, get: (k) => (v || {})[k]};
      },
      update: (r, patch) => pending.push({path: r.path, patch}),
    };
    const out = await cb(tx);
    for (const w of pending) {
      WRITES.push(w);
      const next = Object.assign({}, STORE.get(w.path), w.patch);
      for (const [k, v] of Object.entries(w.patch)) if (v === DELETE) delete next[k];
      STORE.set(w.path, next);
    }
    return out;
  },
};
const onCall = (_opts, fn) => fn;
const harness = [
  ...CONSTS.map(cutConst),
  ...FNS.map(cutFn),
  cutCallable('callableGiveApplicationDocumentConsent'),
  'module.exports = {' + FNS.join(',') +
    ', callableGiveApplicationDocumentConsent, REVIEW_PURPOSE_CONSENT_VERSIONS,' +
    ' SUPPORTED_DOCUMENT_ACCESS_CONSENT_VERSIONS, RETIRED_DOCUMENT_ACCESS_CONSENT_VERSIONS,' +
    ' NEW_REQUEST_CONSENT_VERSION_GENERAL, NEW_REQUEST_CONSENT_VERSION_INVITE,' +
    ' DOCUMENT_ACCESS_CONSENT_V4, DOCUMENT_ACCESS_CONSENT_INVITE_V2};',
].join('\n\n');
const js = ts.transpileModule(harness, {compilerOptions: {
  target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS}}).outputText;
const mod = {exports: {}};
// eslint-disable-next-line no-new-func
new Function('module', 'exports', 'admin', 'db', 'HttpsError', 'onCall', 'Date',
    'console', js)(mod, mod.exports, admin, db, HttpsError, onCall, FakeDate,
    {error: () => {}, log: () => {}, warn: () => {}});
const R = mod.exports;

// ── fixture ─────────────────────────────────────────────────────────────
const DAYK = kst(2026, 11, 20);
const START = kst(2026, 11, 20, 20);
const SLOT = {date: new Ts(DAYK), workDetails: [
  {wdId: 'wd-1', workType: 'QA', startTime: '20:00', endTime: '22:00'}]};
const invite = (o = {}) => Object.assign({
  uid: 'w1', businessId: 'b1', toId: 't1', slotId: 's1', wdId: 'wd-1',
  status: 'INVITED', type: 'short', startTime: '20:00', endTime: '22:00',
  workDate: new Ts(DAYK), inviteExpiresAt: new Ts(START),
}, o);
const seed = (a) => {
  STORE = new Map(); WRITES = []; READS = 0;
  STORE.set('applications/a1', a);
  STORE.set('tos/t1', {status: 'ACTIVE', totalPending: 1, totalConfirmed: 0});
  STORE.set('tos/t1/slots/s1', Object.assign({pendingCount: 1, confirmedCount: 0}, SLOT));
};
const call = R.callableGiveApplicationDocumentConsent;
// 하네스 모양: 후보 클라이언트처럼 given:true 를 싣는다(given 결손 기대는 I-D0).
const req = (uid, data) => ({auth: {uid}, data: Object.assign({documentAccessConsentGiven: true}, data)});
const rawReq = (uid, data) => ({auth: {uid}, data});
const rejects = async (p, code, dcode) => {
  await assert.rejects(p, (e) => {
    assert.strictEqual(e.code, code, e.message);
    if (dcode) assert.strictEqual(e.details && e.details.code, dcode);
    return true;
  });
};
const histOf = (w) => w.patch.statusHistory.__arrayUnion[0];

(async () => {
  console.log('\n[I-A] 판본 단일 소유자 — 서버 상수 ↔ 클라이언트 상수');
  await cell('I-A1', '새 세대 두 토큰이 서버·클라이언트에서 같은 문자열', () => {
    assert.strictEqual(R.DOCUMENT_ACCESS_CONSENT_V4, V4);
    assert.strictEqual(R.DOCUMENT_ACCESS_CONSENT_INVITE_V2, INV2);
    assert.ok(DSRC.includes(`static const String version = '${V4}';`));
    assert.ok(DSRC.includes(`static const String inviteVersion = '${INV2}';`));
  });
  await cell('I-A2', '집합 분리 — 새 요청(화면별 하나) · 저장 이력 읽기 · 검토 목적 · 은퇴', () => {
    assert.strictEqual(R.NEW_REQUEST_CONSENT_VERSION_GENERAL, V4);
    assert.strictEqual(R.NEW_REQUEST_CONSENT_VERSION_INVITE, INV2);
    assert.deepStrictEqual([...R.SUPPORTED_DOCUMENT_ACCESS_CONSENT_VERSIONS].sort(), [V4, INV2].sort());
    assert.deepStrictEqual([...R.REVIEW_PURPOSE_CONSENT_VERSIONS].sort(), [V4, INV2].sort());
    assert.deepStrictEqual([...R.RETIRED_DOCUMENT_ACCESS_CONSENT_VERSIONS].sort(), [...RETIRED].sort());
  });

  console.log('\n[I-B] 새 요청 판본 판정 — 정확한 code');
  const rej = R.srvConsentVersionReject;
  await cell('I-B1', '없음 → CONSENT_VERSION_MISSING(failed-precondition) · 추론 0', () => {
    for (const v of [undefined, null]) {
      const r = rej(v, null);
      assert.strictEqual(r.code, 'CONSENT_VERSION_MISSING'); assert.strictEqual(r.httpCode, 'failed-precondition');
    }
  });
  await cell('I-B2', '은퇴 4종 → CONSENT_VERSION_RETIRED', () => {
    for (const v of RETIRED) assert.strictEqual(rej(v, null).code, 'CONSENT_VERSION_RETIRED', v);
  });
  await cell('I-B3', '모름·빈 문자열·숫자·객체 → CONSENT_VERSION_UNSUPPORTED', () => {
    for (const v of ['v9', '', 'latest', 5, {}, '2026-11-18-v5']) {
      assert.strictEqual(rej(v, null).code, 'CONSENT_VERSION_UNSUPPORTED', String(v));
    }
  });
  await cell('I-B4', '새 세대지만 다른 화면 → CONSENT_VERSION_SCREEN_MISMATCH', () => {
    assert.strictEqual(rej(V4, INV2).code, 'CONSENT_VERSION_SCREEN_MISMATCH');
    assert.strictEqual(rej(INV2, V4).code, 'CONSENT_VERSION_SCREEN_MISMATCH');
  });
  await cell('I-B5', '맞으면 null', () => {
    assert.strictEqual(rej(V4, V4), null); assert.strictEqual(rej(INV2, INV2), null);
  });

  console.log('\n[I-C] 약속 writer resolver — given 필수 · 화면별 판본');
  const f = R.srvResolveCommitmentConsentVersion;
  await cell('I-C1', 'given false·결손 → CONSENT_NOT_GIVEN (판본이 맞아도)', () => {
    for (const g of [false, undefined, 'true']) {
      assert.throws(() => f(V4, g), (e) => e.code === 'invalid-argument' && e.details.code === 'CONSENT_NOT_GIVEN');
    }
  });
  await cell('I-C2', '일반 화면 = v4 만, 초대 화면 = invite-v2 만', () => {
    assert.strictEqual(f(V4, true), V4);
    assert.strictEqual(f(INV2, true, true), INV2);
    assert.throws(() => f(INV2, true), (e) => e.details.code === 'CONSENT_VERSION_SCREEN_MISMATCH');
    assert.throws(() => f(V4, true, true), (e) => e.details.code === 'CONSENT_VERSION_SCREEN_MISMATCH');
  });
  await cell('I-C3', '은퇴 판본 → RETIRED, 없음 → MISSING', () => {
    assert.throws(() => f(V3, true), (e) => e.details.code === 'CONSENT_VERSION_RETIRED');
    assert.throws(() => f(INV1, true, true), (e) => e.details.code === 'CONSENT_VERSION_RETIRED');
    assert.throws(() => f(undefined, true), (e) => e.code === 'failed-precondition' &&
      e.details.code === 'CONSENT_VERSION_MISSING');
  });

  console.log('\n[I-V] 같은 세대 유효 판정(srvConsentValidSameGeneration) — 두 writer 공용');
  const sg = R.srvConsentValidSameGeneration;
  await cell('I-V1', '이유 코드 — NONE · GIVEN_NOT_TRUE · VERSION_MISSING · VERSION_OTHER_GENERATION · AT_MISSING · AT_MALFORMED · AT_FUTURE · 유효', () => {
    const base = {documentAccessConsentGiven: true, documentAccessConsentVersion: INV2,
      documentAccessConsentAt: new Ts(T0)};
    const cases = [
      [{}, 'NONE'], [{documentAccessConsentGiven: false}, 'GIVEN_NOT_TRUE'],
      [Object.assign({}, base, {documentAccessConsentGiven: 'true'}), 'GIVEN_NOT_TRUE'],
      [Object.assign({}, base, {documentAccessConsentVersion: undefined}), 'VERSION_MISSING'],
      [Object.assign({}, base, {documentAccessConsentVersion: V3}), 'VERSION_OTHER_GENERATION'],
      [Object.assign({}, base, {documentAccessConsentAt: undefined}), 'AT_MISSING'],
      [Object.assign({}, base, {documentAccessConsentAt: '2026-11-10'}), 'AT_MALFORMED'],
      [Object.assign({}, base, {documentAccessConsentAt: {toMillis: () => NaN}}), 'AT_MALFORMED'],
      [Object.assign({}, base, {documentAccessConsentAt: new Ts(T0 + 1)}), 'AT_FUTURE'],
      [base, 'SAME_GENERATION_VALID'],
    ];
    for (const [a, why] of cases) {
      const r = sg(a, T0);
      assert.strictEqual(r.reason, why, why); assert.strictEqual(r.valid, why === 'SAME_GENERATION_VALID', why);
    }
  });

  console.log('\n[I-D] 동의 전용 writer 실행 — 실제 given · 새 세대 · 무쓰기 거절 · 원시각 보존');
  await cell('I-D0', '[C-R4-1] given 결손·false·문자열·숫자 → CONSENT_NOT_GIVEN · 읽기 0 · 쓰기 0', async () => {
    for (const g of [undefined, false, 'true', 1, null]) {
      NOW = START - 3600e3; seed(invite());
      const data = {applicationId: 'a1', documentAccessConsentVersion: INV2};
      if (g !== undefined) data.documentAccessConsentGiven = g;
      await rejects(call(rawReq('w1', data)), 'invalid-argument', 'CONSENT_NOT_GIVEN');
      assert.strictEqual(WRITES.length, 0, String(g)); assert.strictEqual(READS, 0, String(g));
    }
  });
  await cell('I-D1', 'INVITED + invite-v2 → 동의 필드만, 출처 CONSENT_ONLY, status·집계 불변', async () => {
    NOW = START - 3600e3; seed(invite());
    const out = await call(req('w1', {applicationId: 'a1', documentAccessConsentVersion: INV2}));
    assert.strictEqual(out.alreadyConsented, false);
    assert.strictEqual(WRITES.length, 1);
    assert.deepStrictEqual(Object.keys(WRITES[0].patch).sort(), ['documentAccessConsentAt',
      'documentAccessConsentGiven', 'documentAccessConsentSource', 'documentAccessConsentVersion',
      'idCardConsentAt', 'idCardConsentGiven', 'statusHistory']);
    const a = STORE.get('applications/a1');
    assert.strictEqual(a.documentAccessConsentVersion, INV2);
    assert.strictEqual(a.documentAccessConsentSource, 'CONSENT_ONLY');
    assert.strictEqual(a.status, 'INVITED');
    assert.strictEqual(STORE.get('tos/t1/slots/s1').pendingCount, 1);
    assert.deepStrictEqual(Object.keys(histOf(WRITES[0])).filter((k) => k.startsWith('prev')), [],
      '덮을 기존 값이 없으면 prev* 0');
  });
  await cell('I-D2', '같은 요청 반복 → 쓰기 0 · 처음 시각 보존', async () => {
    const before = STORE.get('applications/a1').documentAccessConsentAt;
    NOW = START - 3000e3;
    const out = await call(req('w1', {applicationId: 'a1', documentAccessConsentVersion: INV2}));
    assert.strictEqual(out.alreadyConsented, true);
    assert.strictEqual(WRITES.length, 1);
    assert.strictEqual(STORE.get('applications/a1').documentAccessConsentAt, before);
  });
  await cell('I-D3', '은퇴·모름·없음 판본 → 정확한 code, 읽기 전 거절(쓰기 0 · 읽기 0)', async () => {
    for (const [v, code, dcode] of [[V3, 'invalid-argument', 'CONSENT_VERSION_RETIRED'],
      [INV1, 'invalid-argument', 'CONSENT_VERSION_RETIRED'],
      ['v9', 'invalid-argument', 'CONSENT_VERSION_UNSUPPORTED'],
      [undefined, 'failed-precondition', 'CONSENT_VERSION_MISSING']]) {
      NOW = START - 3600e3; seed(invite());
      await rejects(call(req('w1', {applicationId: 'a1', documentAccessConsentVersion: v})), code, dcode);
      assert.strictEqual(WRITES.length, 0, String(v));
      assert.strictEqual(READS, 0, String(v) + ' 는 읽기 전에 거절');
    }
  });
  await cell('I-D4', '화면 불일치 — INVITED+v4 / PENDING+invite-v2 → SCREEN_MISMATCH, 쓰기 0', async () => {
    NOW = START - 3600e3; seed(invite());
    await rejects(call(req('w1', {applicationId: 'a1', documentAccessConsentVersion: V4})),
        'invalid-argument', 'CONSENT_VERSION_SCREEN_MISMATCH');
    seed(invite({status: 'PENDING', inviteExpiresAt: undefined}));
    await rejects(call(req('w1', {applicationId: 'a1', documentAccessConsentVersion: INV2})),
        'invalid-argument', 'CONSENT_VERSION_SCREEN_MISMATCH');
    assert.strictEqual(WRITES.length, 0);
  });
  await cell('I-D5', 'v3 기록 + 새 v4 동의 → v4 로 새로 기록(자동 승격 0) · 기존 값은 이력 prev*', async () => {
    NOW = START + 99e7;
    seed(invite({status: 'PENDING', inviteExpiresAt: undefined, documentAccessConsentGiven: true,
      documentAccessConsentVersion: V3, documentAccessConsentAt: new Ts(T0),
      documentAccessConsentSource: 'APPLY'}));
    const out = await call(req('w1', {applicationId: 'a1', documentAccessConsentVersion: V4}));
    assert.strictEqual(out.alreadyConsented, false);
    const h = histOf(WRITES[0]);
    assert.strictEqual(h.prevConsentVersion, V3);
    assert.strictEqual(h.prevConsentAtMs, T0);
    assert.strictEqual(h.prevConsentGiven, true);
    assert.strictEqual(h.prevConsentSource, 'APPLY');
    assert.strictEqual(STORE.get('applications/a1').documentAccessConsentVersion, V4);
    assert.strictEqual(STORE.get('applications/a1').documentAccessConsentAt.toMillis(), NOW);
  });
  await cell('I-D6', '같은 세대 유효(At 유효·비미래) → no-op · INVITED + 저장 v4 에 invite-v2 도 canonical 보존', async () => {
    NOW = START - 3600e3;
    seed(invite({status: 'CONFIRMED', documentAccessConsentGiven: true,
      documentAccessConsentVersion: V4, documentAccessConsentAt: new Ts(T0)}));
    assert.strictEqual((await call(req('w1', {applicationId: 'a1', documentAccessConsentVersion: V4}))).alreadyConsented, true);
    seed(invite({documentAccessConsentGiven: true, documentAccessConsentVersion: V4,
      documentAccessConsentAt: new Ts(T0)}));
    assert.strictEqual((await call(req('w1', {applicationId: 'a1', documentAccessConsentVersion: INV2}))).alreadyConsented, true);
    assert.strictEqual(STORE.get('applications/a1').documentAccessConsentVersion, V4);
    assert.strictEqual(WRITES.length, 0);
  });
  await cell('I-D7', '[C-R4-2] 같은 세대인데 At 결손·형식오류·미래 → no-op 이 아니라 새로 기록 · prev* 에 표시', async () => {
    for (const [at, prevKey] of [[undefined, null], ['2026-11-10', 'prevConsentAtMalformed'],
      [new Ts(START + DAY), 'prevConsentAtMs']]) {
      NOW = START - 3600e3;
      const stored = {documentAccessConsentGiven: true, documentAccessConsentVersion: INV2};
      if (at !== undefined) stored.documentAccessConsentAt = at;
      seed(invite(stored));
      const out = await call(req('w1', {applicationId: 'a1', documentAccessConsentVersion: INV2}));
      assert.strictEqual(out.alreadyConsented, false, String(at));
      assert.strictEqual(STORE.get('applications/a1').documentAccessConsentAt.toMillis(), NOW);
      const h = histOf(WRITES[0]);
      if (prevKey) assert.ok(prevKey in h, prevKey);
      else assert.ok(!('prevConsentAtMs' in h) && !('prevConsentAtMalformed' in h));
    }
  });
  await cell('I-D8', '[C-R4-2] 낡은 승계 표시 위 새 명시 동의 → inheritedFrom 삭제 · prev 에 출처/parent · 출처 CONSENT_ONLY', async () => {
    NOW = START + 99e7;
    seed(invite({status: 'PENDING', inviteExpiresAt: undefined, documentAccessConsentGiven: true,
      documentAccessConsentVersion: V3, documentAccessConsentAt: new Ts(T0),
      documentAccessConsentSource: 'REASSIGN_INHERITED', documentAccessConsentInheritedFrom: 'a0'}));
    await call(req('w1', {applicationId: 'a1', documentAccessConsentVersion: V4}));
    assert.strictEqual(WRITES[0].patch.documentAccessConsentInheritedFrom, DELETE);
    const a = STORE.get('applications/a1');
    assert.ok(!('documentAccessConsentInheritedFrom' in a), '낡은 parent 가 남았다');
    assert.strictEqual(a.documentAccessConsentSource, 'CONSENT_ONLY');
    const h = histOf(WRITES[0]);
    assert.strictEqual(h.prevConsentSource, 'REASSIGN_INHERITED');
    assert.strictEqual(h.prevConsentInheritedFrom, 'a0');
  });
  await cell('I-D9', '다른 사람·끝난 관계·기한 지난 초대 → 기존 오류 그대로, 쓰기 0', async () => {
    NOW = START - 3600e3; seed(invite());
    await rejects(call(req('x9', {applicationId: 'a1', documentAccessConsentVersion: INV2})), 'permission-denied');
    for (const st of ['EXPIRED', 'REJECTED', 'CANCELED']) {
      seed(invite({status: st}));
      await rejects(call(req('w1', {applicationId: 'a1', documentAccessConsentVersion: INV2})), 'failed-precondition');
    }
    NOW = START + 1; seed(invite());
    await rejects(call(req('w1', {applicationId: 'a1', documentAccessConsentVersion: INV2})), 'failed-precondition');
    assert.strictEqual(WRITES.length, 0);
  });

  console.log('\n[I-E] 저장 이력 읽기 — 은퇴 판본은 근거가 아니다');
  const lastDay = kst(2026, 11, 20);
  const conf = (v) => ({status: 'CONFIRMED', type: 'short', workDate: new Ts(lastDay),
    documentAccessConsentGiven: true, documentAccessConsentVersion: v});
  await cell('I-E1', '신분증 창: v4·invite-v2 = 마지막 근무일 0시 + 7일(−1ms 열림·정각 닫힘)', () => {
    const end = lastDay + 7 * DAY;
    for (const v of [V4, INV2]) {
      assert.strictEqual(R.srvIdWindowOpen(conf(v), end - 1), true, v);
      assert.strictEqual(R.srvIdWindowOpen(conf(v), end), false, v);
    }
  });
  await cell('I-E2', '신분증 창: v1·v2·v3·invite-v1·없음 → 닫힘', () => {
    for (const v of [V1, V2, V3, INV1, undefined]) {
      assert.strictEqual(R.srvIdWindowOpen(conf(v), lastDay + HOUR), false, String(v));
    }
  });
  await cell('I-E3', '검토 접근: v3 동의 PENDING → 최신 버전 필요 / v4 → 허용', () => {
    const p = (v) => ({uid: 'w1', businessId: 'b1', status: 'PENDING',
      documentAccessConsentGiven: true, documentAccessConsentVersion: v});
    assert.match(R.srvApplicantReviewAccessBlock(p(V3), 'b1', 'w1', NOW), /최신 버전/);
    assert.strictEqual(R.srvApplicantReviewAccessBlock(p(V4), 'b1', 'w1', NOW), null);
  });
  await cell('I-E4', '초대 수락 준비: v3 동의 초대 → CONSENT_REQUIRED, invite-v2 → REVIEW_PENDING', () => {
    const u = {idCardImagePath: 'id/w1.jpg', idDocumentVersion: 2};
    assert.strictEqual(R.srvInviteAcceptReadiness(invite({documentAccessConsentGiven: true,
      documentAccessConsentVersion: V3}), u, undefined), 'CONSENT_REQUIRED');
    assert.strictEqual(R.srvInviteAcceptReadiness(invite({documentAccessConsentGiven: true,
      documentAccessConsentVersion: INV2}), u, undefined), 'REVIEW_PENDING');
  });

  console.log('\n[I-F] 덮어쓰기 전 원시 증거(형식 맞는 값만 — 모든 원시값 보존이 아니다)');
  await cell('I-F1', '형식이 맞는 값만 · 길이 상한 · At 형식오류는 표시만', () => {
    assert.deepStrictEqual(R.srvPrevConsentEvidence({}), {});
    assert.deepStrictEqual(R.srvPrevConsentEvidence({documentAccessConsentGiven: false}), {prevConsentGiven: false});
    assert.deepStrictEqual(R.srvPrevConsentEvidence({documentAccessConsentAt: 'x'}), {prevConsentAtMalformed: true});
    assert.strictEqual(R.srvPrevConsentEvidence({documentAccessConsentVersion: 'v'.repeat(100)}).prevConsentVersion.length, 64);
    assert.strictEqual(R.srvPrevConsentEvidence({documentAccessConsentSource: 's'.repeat(100)}).prevConsentSource.length, 64);
    assert.strictEqual(R.srvPrevConsentEvidence({documentAccessConsentInheritedFrom: 'p'.repeat(200)}).prevConsentInheritedFrom.length, 128);
    assert.deepStrictEqual(R.srvPrevConsentEvidence({documentAccessConsentSource: 7, documentAccessConsentInheritedFrom: 9}), {},
      '형식이 다른 출처·parent 는 남기지 않는다(원시값 전부 보존이라고 주장하지 않음)');
  });

  console.log('\n[I-H] 초대 수락 보존(O3 새 세대 · r4 P-H 를 index.ts 함수로 옮김)');
  const plan = (fr, now = T0 + DAY) => R.srvInviteAcceptConsentPlan(fr, now);
  const inv = (o = {}) => invite(Object.assign({documentAccessConsentGiven: true,
    documentAccessConsentVersion: INV2, documentAccessConsentAt: new Ts(T0)}, o));
  await cell('I-H1', '같은 세대 유효 → 보존 · At == 판정 시각 → 보존', () => {
    assert.deepStrictEqual(plan(inv()), {preserve: true, reason: 'SAME_GENERATION_VALID'});
    assert.strictEqual(plan(inv({documentAccessConsentVersion: V4})).preserve, true);
    assert.strictEqual(plan(inv(), T0).preserve, true);
  });
  await cell('I-H2', '동의 없음/false/은퇴/At 결손·형식·미래 → 새로 기록', () => {
    const cases = [
      [invite(), 'NONE'], [inv({documentAccessConsentGiven: false}), 'GIVEN_NOT_TRUE'],
      [inv({documentAccessConsentVersion: undefined}), 'VERSION_MISSING'],
      [inv({documentAccessConsentVersion: INV1}), 'VERSION_OTHER_GENERATION'],
      [inv({documentAccessConsentAt: undefined}), 'AT_MISSING'],
      [inv({documentAccessConsentAt: 'x'}), 'AT_MALFORMED'],
      [inv({documentAccessConsentAt: new Ts(T0 + 2 * DAY)}), 'AT_FUTURE'],
    ];
    for (const [fr, why] of cases) assert.deepStrictEqual(plan(fr), {preserve: false, reason: why}, why);
  });

  console.log('\n[I-S] 순서·모양 — 실행으로 못 보는 자리');
  const apply = callableSrc('callableApplyToTO');
  const acceptInv = callableSrc('callableAcceptTOInvitation');
  const reassign = callableSrc('callableAcceptConfirmedReassignment');
  const bankbook = callableSrc('callableGetBankbookSignedUrl');
  const account = callableSrc('callableGetWorkerPayrollAccount');
  const batch = callableSrc('callableGetUsersBatch');
  const review = callableSrc('callableGetApplicantDocumentReview');
  const consentOnly = callableSrc('callableGiveApplicationDocumentConsent');
  await cell('I-S0', '[C-R4-1] 동의 전용 writer: given 판정이 판본 판정·첫 읽기보다 먼저', () => {
    const g = consentOnly.indexOf('if (documentAccessConsentGiven !== true) {');
    const v = consentOnly.indexOf('srvConsentVersionReject(documentAccessConsentVersion, null)');
    const rd = consentOnly.indexOf('.get()');
    assert.ok(g > 0 && v > g && (rd < 0 || rd > v), [g, v, rd].join(','));
  });
  await cell('I-S1', '지원: payload given 을 넘기고 좌석 트랜잭션보다 먼저 판정', () => {
    const g = apply.indexOf('srvResolveCommitmentConsentVersion(');
    assert.ok(g > 0 && g < apply.indexOf('runTransaction'));
    assert.ok(/srvResolveCommitmentConsentVersion\(\s*data\.documentAccessConsentVersion,\s*data\.documentAccessConsentGiven === true\s*\)/.test(apply));
  });
  await cell('I-S2', '초대 수락: resolver 가 완료 no-op 보다 먼저 · 보존 판정 = srvInviteAcceptConsentPlan(트랜잭션 안 판정 시각) · 새 동의만 쓰기', () => {
    const res = acceptInv.indexOf('srvResolveCommitmentConsentVersion(');
    const done = acceptInv.indexOf('currentStatus === "CONFIRMED"');
    assert.ok(res > 0 && done > res);
    const plan = acceptInv.indexOf('srvInviteAcceptConsentPlan(');
    assert.ok(!acceptInv.includes('cr4InviteAcceptConsentPlan('), 'r4 순수 모듈 판정이 남았다');
    assert.ok(/srvInviteAcceptConsentPlan\(\s*freshData,\s*Math\.max\(confirmedAt\.toMillis\(\),\s*Date\.now\(\)\)\)/.test(acceptInv));
    const assign = acceptInv.indexOf('Object.assign(acceptUpdate, acceptNewConsent)');
    const write = acceptInv.indexOf('tx.update(appRef, acceptUpdate);');
    assert.ok(plan > 0 && plan < assign && assign < write);
    const lit = acceptInv.slice(acceptInv.indexOf('const acceptUpdate: Record<string, unknown> = {'),
        acceptInv.indexOf('const acceptNewConsent'));
    assert.ok(!lit.includes('documentAccessConsentAt:'), '수락 시각으로 At 을 무조건 덮지 않는다');
    const nc = acceptInv.slice(acceptInv.indexOf('const acceptNewConsent'), assign);
    assert.ok(nc.includes('documentAccessConsentInheritedFrom: admin.firestore.FieldValue.delete()'));
  });
  await cell('I-S3', '재배치: 방식 판정·resolver 가 제안 읽기·완료 no-op 보다 먼저', () => {
    const mode = reassign.indexOf('crConsentMode !== "INHERIT" && crConsentMode !== "EXPLICIT"');
    const read = reassign.indexOf('await acProposalRef.get()');
    const done = reassign.indexOf('acStatus === CR_ACCEPTED');
    assert.ok(mode > 0 && mode < read && read < done);
  });
  await cell('I-S3b', '[r4c · PP-R4B-INHERIT] INHERIT 는 명시 동의 키 존재 자체를 거절(값 무관) — 읽기 전', () => {
    for (const k of ['"documentAccessConsentGiven"', '"documentAccessConsentVersion"', '"consentShown"']) {
      assert.ok(reassign.includes('crHasKey(' + k + ')'), k);
    }
    assert.ok(reassign.includes('Object.prototype.hasOwnProperty.call(request.data, k)'));
    const chk = reassign.indexOf('crHasKey("consentShown")');
    assert.ok(chk > 0 && chk < reassign.indexOf('await acProposalRef.get()'));
  });
  await cell('I-S4', '재배치: 계보 → 대상/정원/겹침 → 동의 판정 → 첫 쓰기, 그 사이 쓰기·lock 0', () => {
    const lin = reassign.indexOf('cr4LineageBlock(');
    const full = reassign.indexOf('return unavailable("TARGET_FULL"');
    const ovl = reassign.indexOf('srvCollectSeatCommitOverlap(');
    const inh = reassign.indexOf('cr4ConsentInheritance(');
    const ret = reassign.indexOf('code: "CONSENT_REQUIRED"');
    const first = reassign.indexOf('srvApplySeatCommitOverlap(tx');
    assert.ok(lin > 0 && lin < full && full < ovl && ovl < inh && inh < ret && ret < first,
      [lin, full, ovl, inh, ret, first].join(','));
    const between = reassign.slice(ovl, ret);
    for (const w of ['tx.update(', 'tx.set(', 'srvCloseCrProposal(', 'acLockRef', 'srvWriteCrNotification(']) {
      assert.ok(!between.includes(w), w);
    }
  });
  await cell('I-S5', '재배치: CONSENT_REQUIRED 는 알림보다 먼저 · 세부 이유 포함', () => {
    const blk = reassign.slice(reassign.indexOf('if (!acResult.ok) {'));
    const cr = blk.indexOf('acResult.code === "CONSENT_REQUIRED"');
    const nt = blk.indexOf('srvWriteCrNotification(');
    assert.ok(cr > 0 && nt > cr);
    assert.ok(reassign.includes('consentReason: inh.detail ? `${inh.reason}:${inh.detail}` : inh.reason'));
    assert.ok(blk.includes('{code: "CONSENT_REQUIRED", reason: acResult.consentReason ?? null}'));
  });
  await cell('I-S6', '재배치: 새 시각 At 은 EXPLICIT 분기 한 곳뿐 · 승계 분기는 원값 + 계보 + 출처', () => {
    assert.strictEqual(reassign.split('documentAccessConsentAt: acNow').length - 1, 1);
    const i = reassign.indexOf('if (crConsentMode === "INHERIT") {');
    const inhBranch = reassign.slice(i, reassign.indexOf('} else {', i));
    assert.ok(inhBranch.includes('documentAccessConsentInheritedFrom: acSourceId'));
    assert.ok(inhBranch.includes('documentAccessConsentSource: "REASSIGN_INHERITED"'));
    assert.ok(!inhBranch.includes('acNow,'));
  });
  await cell('I-S7', '확정자 통장사본: 판본 → 기간 판정(계약은 NO_END 일 때만 · 사업장 문서) → 서명 직전 재판정 → 서명 · 1시간 고정 0', () => {
    const v = bankbook.indexOf('CONSENT_VERSION_NOT_READABLE');
    const need = bankbook.indexOf('cr4NeedsCurrentWorkEvidence(appData)');
    const w = bankbook.indexOf('cr4BankWindow(bbInput)');
    const re = bankbook.indexOf('cr4SignableExpiryMs(bbInput, Date.now())');
    const s = bankbook.indexOf('getSignedUrl(');
    assert.ok(v > 0 && v < need && need < w && w < re && re < s, [v, need, w, re, s].join(','));
    assert.ok(bankbook.includes('expires: bbSign.expiresMs,'));
    assert.ok(bankbook.includes('business: bizData,'));
    assert.ok(bankbook.includes('applicationId,\n'));
    assert.ok(!bankbook.includes('Date.now() + 60 * 60 * 1000'));
    assert.ok(bankbook.includes('closedKind: cr4ClosedKind('));
    // [r4c · F-R4B-2] 통장 경로와 보완 판본이 같은 사용자 snapshot — users 읽기는 한 번, 기간 입력에 판본.
    assert.strictEqual(bankbook.split('db.collection("users").doc(appUid).get()').length - 1, 1);
    assert.ok(bankbook.includes('docVersions: cr4DocVersionsOf(workerData),'));
    assert.ok(bankbook.indexOf('const workerData = workerDoc.data()!;') < bankbook.indexOf('const bbInput = {'));
  });
  await cell('I-S8', 'generic batch: 목적 미지정이면 계좌 3필드 제외(역할 무관)', () => {
    assert.ok(batch.includes('if (purpose === undefined && BANK_ONLY_FIELDS.has(key)) continue;'));
  });
  await cell('I-S9', '검토 DTO: 계좌 3필드 = canSeeDocs AND consentBlock == null', () => {
    assert.ok(review.includes('...(canSeeDocs && consentBlock == null ? {'));
  });
  await cell('I-S10', '은퇴 상수는 선언과 은퇴 집합 말고 쓰이지 않는다', () => {
    for (const n of ['DOCUMENT_ACCESS_CONSENT_V1', 'DOCUMENT_ACCESS_CONSENT_V2',
      'DOCUMENT_ACCESS_CONSENT_V3', 'DOCUMENT_ACCESS_CONSENT_INVITE_V1']) {
      const uses = SRC.split(new RegExp(`\\b${n}\\b`)).length - 1;
      assert.strictEqual(uses, 2, `${n} 사용 ${uses}회(선언 1 + 은퇴 집합 1 이어야 한다)`);
    }
  });
  await cell('I-S11', '[C-R4-4] 목적별 계좌 reader: 인가 → SUPER_ADMIN 제외 → 지원서 → 확정·동의·판본 → 기간 → 미등록 → 응답 직전 재판정 → 감사 기록(실패면 거절) → 응답', () => {
    // [r4c · F-R4B-4] 로그(접근 판정·응답 준비 사건) **뒤** 최종 재판정 — 마지막 await 뒤 동기 판정.
    const order = ['srvAssertPayrollDocumentAccess(callerUid, businessId)', '=== "SUPER_ADMIN"',
      'db.collection("applications").doc(applicationId).get()', 'deny("NOT_CONFIRMED")',
      'deny("CONSENT_MISSING")', 'deny("CONSENT_VERSION_NOT_READABLE")', 'docVersions: cr4DocVersionsOf(u),',
      'cr4BankWindow(paInput)', 'status: "NOT_REGISTERED"', 'collection("payroll_account_access_logs").add(',
      'event: "ACCOUNT_ACCESS_DECISION_PREPARED"', 'throw new HttpsError("internal"',
      'const paFinal = cr4SignableExpiryMs(paInput, Date.now());', 'status: "OK"', 'paFinal.window.state'];
    let last = -1;
    for (const k of order) {
      const i = account.indexOf(k);
      assert.ok(i > last, `${k} 위치 ${i} (앞 ${last})`);
      last = i;
    }
    assert.ok(account.includes('business: paBizSnap.exists ? (paBizSnap.data() ?? null) : null,'));
    assert.ok(account.includes('closedKind: cr4ClosedKind(w)'));
    // [r4d · F-R4C-2] 판정 시각은 조회 await **뒤** — 무계좌 응답도 그 window.
    assert.ok(account.indexOf('await Promise.all([') < account.indexOf('const paNowMs = Date.now();'));
    assert.ok(account.indexOf('const paNowMs = Date.now();') < account.indexOf('status: "NOT_REGISTERED"'));
    assert.ok(bankbook.indexOf('const [bbAttSnap') < bankbook.indexOf('const bbNowMs = Date.now();'));
    assert.ok(!/await[^;]*;\s*return \{\s*status: "OK"/.test(account.slice(account.indexOf('const paFinal'))),
      '최종 재판정과 반환 사이에 await 가 없다');
    assert.ok(!/accountNumber:\s*decrypt/.test(account), '서버는 저장 암호문 그대로 돌려준다');
  });
  await cell('I-S12', '두 reader 가 같은 정책 상수·같은 조회 상한을 쓴다(기간 판정 한 벌)', () => {
    for (const body of [bankbook, account]) {
      for (const k of ['CR4_BANK_WINDOW_POLICY_DRAFT', 'CR4_ATTENDANCE_QUERY_LIMIT',
        'CR4_CORRECTION_QUERY_LIMIT', 'CR4_CONTRACT_QUERY_LIMIT', 'cr4NeedsCurrentWorkEvidence(']) {
        assert.ok(body.includes(k), k);
      }
    }
  });

  summary();
})();
