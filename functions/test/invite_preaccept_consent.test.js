/**
 * [INVITE-PREACCEPT] 초대 수락 전 서류 동의 → 사업장 검토 → 수락 — 실제 소스 실행.
 *
 *   2026-10-15 DEV 실측: 자동 판정이 MATCHED 가 아닌 근로자는 초대를 수락할
 *   수 없었다. 수락 tx 의 신분증 확인 문턱은 사업장 수동 검토를 요구하는데,
 *   수동 검토는 지원서의 V3 서류 열람 동의를 요구하고, 초대의 동의는 수락 tx
 *   안에서만(그것도 문턱 뒤에서) 기록됐다. 교착이었다.
 *
 *   이 파일은 `index.ts` 에서 판정 함수·상수와 동의 writer 본문을 **원문 그대로**
 *   꺼내 TypeScript 로 컴파일하고 가짜 Firestore 위에서 실행한다. 재구현이 아니다.
 *
 *     PA-A  수락 기간 판정(srvInviteWindowClosed) — 모르면 닫힘
 *     PA-B  열람·검토 접근(srvApplicantReviewAccessBlock) — 초대 기간·동의·사업장
 *     PA-C  근로자 쪽 수락 준비 상태(srvInviteAcceptReadiness) — 낡은 검토 재사용 금지
 *     PA-D  동의 기간 판정(srvInviteConsentWindowBlock) — slot 기준 fail-closed
 *     PA-E  동의 writer 실행 — 상태·좌석 불변, 중복 안전, 기한·타인·종료 거절
 *     PA-F  수락 tx·목록 reader 계약(실행으로 못 보는 자리)
 */
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const ts = require('typescript');

const SRC = fs.readFileSync(path.join(__dirname, '..', 'src', 'index.ts'), 'utf8');

// ── 원문 추출 ────────────────────────────────────────────────────────────
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
// 최상위 함수 선언은 TypeScript 파서로 찾는다 — 반환형이 `{a: number}` 같은
//   객체 타입이면 중괄호 세기로는 본문을 잘못 자른다(실제로 그랬다).
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

const CONSTS = ['SRV_KST_MS', 'CONFIRMED_STATUSES', 'DOC_MATCH_MISSING',
  'DOC_MATCH_UNASSESSED', 'DOC_MATCH_MATCHED', 'DOC_MATCH_MISMATCH',
  'DOC_MATCH_OCR_UNCERTAIN', 'SRV_DOC_MATCH_MISSING', 'REVIEW_NOT_REVIEWED',
  'REVIEW_OK', 'MR_READY_AUTO', 'MR_READY_MANUAL', 'MR_ID_MISSING',
  'MR_ID_MISMATCH', 'MR_ID_OCR_UNCERTAIN', 'MR_ID_UNASSESSED',
  'DOCUMENT_ACCESS_CONSENT_V3', 'DOCUMENT_ACCESS_CONSENT_INVITE_V1',
  'REVIEW_PURPOSE_CONSENT_VERSIONS', 'DOCUMENT_ACCESS_CONSENT_V1',
  'DOCUMENT_ACCESS_CONSENT_V2', 'SUPPORTED_DOCUMENT_ACCESS_CONSENT_VERSIONS',
  'APPLICANT_REVIEW_STATUSES', 'ACCOUNT_STATUS_DELETING',
  'SRV_INVITE_READINESS_WORKER_MESSAGE',
  // [INVITE-LIFECYCLE] 동의·검토·수락 공통 모집 종료 판정
  'SRV_INTAKE_AUTO_UNIT_REASON', 'SRV_INTAKE_AUTO_TO_REASONS',
  'SRV_INVITE_RECRUIT_ENDED_MESSAGE'];
const FNS = ['srvDocumentVersionsOf', 'srvBuildMatchingProvenance',
  'srvAssertNotDeletingAccount',
  'resolveDocumentAccessConsentVersion', 'srvResolveCommitmentConsentVersion',
  'srvConsentCoversApplicantReview', 'srvInviteReviewWindowOpen',
  'srvApplicantReviewAccessBlockAsync', 'srvHasActiveIdentityDocumentPurpose',
  'srvKstDayStartMs', 'srvShiftStartMsFrom', 'srvIsLongTermInvite',
  'srvResolveGuardShiftStart', 'srvResolveIdCardMatch',
  'srvResolveMatchingReadiness', 'srvInviteAcceptReadiness',
  'srvInviteWindowClosed', 'srvApplicantReviewAccessBlock',
  'srvInviteConsentWindowBlock', 'srvInviteConsentWindowBlockTx',
  'srvInviteRecruitClosureBlock', 'srvToClosedByApplicationDeadline'];

// ── 스텁 ────────────────────────────────────────────────────────────────
class HttpsError extends Error {
  constructor(code, message, details) { super(message); this.code = code; this.details = details; }
}
class Ts {
  constructor(ms) { this.ms = ms; }
  toMillis() { return this.ms; }
  get seconds() { return Math.floor(this.ms / 1000); }
  get nanoseconds() { return (this.ms % 1000) * 1e6; }
}
let NOW = 0;
class FakeDate extends Date {
  constructor(...a) { if (a.length === 0) super(NOW); else super(...a); }
  static now() { return NOW; }
}
const admin = {firestore: {
  Timestamp: {now: () => new Ts(NOW), fromMillis: (ms) => new Ts(ms)},
  FieldValue: {arrayUnion: (...x) => ({__arrayUnion: x})},
}};

// 아주 작은 Firestore: path → data
let STORE = new Map();
let WRITES = [];
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
let READS = 0;
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
        const v = STORE.get(r.path);
        return {exists: v !== undefined, data: () => v, get: (k) => (v || {})[k]};
      },
      update: (r, patch) => pending.push({path: r.path, patch}),
    };
    const out = await cb(tx);
    for (const w of pending) {
      WRITES.push(w);
      STORE.set(w.path, Object.assign({}, STORE.get(w.path), w.patch));
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
    ', callableGiveApplicationDocumentConsent, SRV_INVITE_READINESS_WORKER_MESSAGE,' +
    ' REVIEW_PURPOSE_CONSENT_VERSIONS, SUPPORTED_DOCUMENT_ACCESS_CONSENT_VERSIONS,' +
    ' srvResolveCommitmentConsentVersion, srvBuildMatchingProvenance,' +
    ' srvAssertNotDeletingAccount};',
].join('\n\n');
const js = ts.transpileModule(harness, {compilerOptions: {
  target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS}}).outputText;
const mod = {exports: {}};
// eslint-disable-next-line no-new-func
new Function('module', 'exports', 'admin', 'db', 'HttpsError', 'onCall', 'Date',
    'console', js)(mod, mod.exports, admin, db, HttpsError, onCall, FakeDate,
    {error: () => {}, log: () => {}, warn: () => {}});
const R = mod.exports;

// ── 공용 fixture ────────────────────────────────────────────────────────
const K = 9 * 3600e3;
const kst = (y, mo, d, h = 0, mi = 0) => Date.UTC(y, mo - 1, d, h, mi) - K;
const DAY = kst(2026, 10, 20);
const START = kst(2026, 10, 20, 20);
const V3 = '2026-09-18-v3';
const INV = '2026-10-15-invite-v1';
const SLOT = {date: new Ts(DAY), workDetails: [
  {wdId: 'wd-1', workType: 'QA', startTime: '20:00', endTime: '22:00'}]};
const invite = (o = {}) => Object.assign({
  uid: 'w1', businessId: 'b1', toId: 't1', slotId: 's1', wdId: 'wd-1',
  status: 'INVITED', type: 'short', startTime: '20:00', endTime: '22:00',
  workDate: new Ts(DAY), inviteExpiresAt: new Ts(START),
}, o);
const consented = (o = {}) => invite(Object.assign(
    {documentAccessConsentGiven: true, documentAccessConsentVersion: V3}, o));
const userWith = (o = {}) => Object.assign(
    {idCardImagePath: 'id/w1.jpg', idDocumentVersion: 2}, o);

let pass = 0; const fails = [];
async function cell(id, name, fn) {
  try { await fn(); pass++; console.log(`  ok   ${id} ${name}`); } catch (e) { fails.push(`${id} ${name}: ${e.message}`); console.log(`  FAIL ${id} ${name} — ${e.message}`); }
}

(async () => {
  console.log('\n[PA-A] 수락 기간 — 모르면 닫힘');
  await cell('PA-01', '시작 1분 전은 열림', () => {
    assert.strictEqual(R.srvInviteWindowClosed(invite(), START - 60000), false);
  });
  await cell('PA-02', '저장 만료 정각부터 닫힘', () => {
    assert.strictEqual(R.srvInviteWindowClosed(invite(), START), true);
  });
  await cell('PA-03', '만료가 남았어도 snapshot 근무 시작이 지났으면 닫힘', () => {
    const late = invite({inviteExpiresAt: new Ts(START + 10 * 3600e3)});
    assert.strictEqual(R.srvInviteWindowClosed(late, START + 1), true);
  });
  await cell('PA-04', 'inviteExpiresAt 없으면 닫힘(fail-closed)', () => {
    assert.strictEqual(R.srvInviteWindowClosed(invite({inviteExpiresAt: undefined}), DAY), true);
  });
  await cell('PA-05', 'workDate 가 KST 자정이 아니면 닫힘(오염 snapshot)', () => {
    assert.strictEqual(R.srvInviteWindowClosed(invite({workDate: new Ts(DAY + K)}), DAY), true);
  });
  await cell('PA-06', '장기 초대는 저장 만료만 본다', () => {
    const lt = {status: 'INVITED', type: 'long_term', workDays: ['월'],
      inviteExpiresAt: new Ts(START), workDate: new Ts(DAY + K), startTime: '09:00'};
    assert.strictEqual(R.srvInviteWindowClosed(lt, START - 1), false);
  });

  console.log('\n[PA-B] 열람·검토 접근 — 4개 callable 공용');
  const block = R.srvApplicantReviewAccessBlock;
  await cell('PA-07', '동의한 초대 · 기간 안 · 같은 사업장 → 허용', () => {
    assert.strictEqual(block(consented(), 'b1', 'w1', START - 3600e3), null);
  });
  await cell('PA-08', '동의 전 초대 → 거절(동의 없이 열람 없음)', () => {
    assert.match(block(invite(), 'b1', 'w1', START - 3600e3), /동의하지 않았습니다/);
  });
  await cell('PA-09', '기간이 지난 초대(status 아직 INVITED) → 거절', () => {
    assert.match(block(consented(), 'b1', 'w1', START), /기한이 지나/);
  });
  await cell('PA-10', '다른 사업장 → 거절', () => {
    assert.match(block(consented(), 'b2', 'w1', START - 3600e3), /찾을 수 없습니다/);
  });
  await cell('PA-11', '거절·만료·취소된 초대 → 거절', () => {
    for (const st of ['REJECTED', 'EXPIRED', 'CANCELED', 'AUTO_CANCELED']) {
      assert.match(block(consented({status: st}), 'b1', 'w1', DAY), /검토 중인 지원서가 아닙니다/, st);
    }
  });
  await cell('PA-12', 'v2 동의는 검토 목적 열람에 쓰지 않는다', () => {
    assert.match(block(consented({documentAccessConsentVersion: '2026-09-12-v2'}),
        'b1', 'w1', START - 3600e3), /최신 버전/);
  });
  await cell('PA-13', '직접 지원(PENDING)은 초대 기간 검사를 받지 않는다(기존 계약 유지)', () => {
    const p = consented({status: 'PENDING', inviteExpiresAt: undefined});
    assert.strictEqual(block(p, 'b1', 'w1', START + 99e7), null);
  });

  console.log('\n[PA-C] 근로자 쪽 수락 준비 상태');
  const rd = R.srvInviteAcceptReadiness;
  await cell('PA-14', '자동 판정 MATCHED(같은 버전) → READY(동의 없이도)', () => {
    const u = userWith({idCardMatchStatus: 'MATCHED', idCardMatchDocumentVersion: 2});
    assert.strictEqual(rd(invite(), u, undefined), 'READY');
  });
  await cell('PA-15', '신분증 없음 → DOCUMENT_REQUIRED', () => {
    assert.strictEqual(rd(invite(), {}, undefined), 'DOCUMENT_REQUIRED');
  });
  await cell('PA-16', '판정 없음 · 동의 전 → CONSENT_REQUIRED', () => {
    assert.strictEqual(rd(invite(), userWith(), undefined), 'CONSENT_REQUIRED');
  });
  await cell('PA-17', '동의함 · 검토 없음 → REVIEW_PENDING', () => {
    assert.strictEqual(rd(consented(), userWith(), undefined), 'REVIEW_PENDING');
  });
  await cell('PA-18', '동의함 · 현재 버전 검토 OK → READY', () => {
    const rv = {idDecision: 'REVIEWED_OK', reviewedIdDocumentVersion: 2};
    assert.strictEqual(rd(consented(), userWith(), rv), 'READY');
  });
  await cell('PA-19', '검토 후 근로자가 신분증을 다시 올렸다 → 이전 검토 재사용 금지', () => {
    const rv = {idDecision: 'REVIEWED_OK', reviewedIdDocumentVersion: 2};
    assert.strictEqual(rd(consented(), userWith({idDocumentVersion: 3}), rv), 'REVIEW_PENDING');
  });
  await cell('PA-20', '재등록 요청 상태는 READY 가 아니다', () => {
    const rv = {idDecision: 'REUPLOAD_REQUIRED', reviewedIdDocumentVersion: 2};
    assert.strictEqual(rd(consented(), userWith(), rv), 'REVIEW_PENDING');
  });
  await cell('PA-21', '근로자용 문구는 관리자 행동("지원자 상세")을 시키지 않는다', () => {
    for (const [k, v] of Object.entries(R.SRV_INVITE_READINESS_WORKER_MESSAGE)) {
      assert.ok(!v.includes('지원자 상세'), k);
    }
  });

  console.log('\n[PA-D] 동의 기간 — slot 기준 fail-closed');
  const cw = R.srvInviteConsentWindowBlock;
  await cell('PA-22', '기간 안 · slot 정상 → 허용', () => {
    assert.strictEqual(cw(invite(), true, SLOT, START - 3600e3), null);
  });
  await cell('PA-23', 'slot 없음 → 거절', () => {
    assert.match(cw(invite(), false, undefined, START - 3600e3), /일정을 확인할 수 없어/);
  });
  await cell('PA-24', 'wdId 불일치 → 거절', () => {
    assert.match(cw(invite({wdId: 'zzz'}), true, SLOT, START - 3600e3), /일정을 확인할 수 없어/);
  });
  await cell('PA-25', 'slot 상 근무 시작 이후 → 거절', () => {
    const early = {date: new Ts(DAY), workDetails: [{wdId: 'wd-1', startTime: '19:00', endTime: '22:00'}]};
    assert.match(cw(invite(), true, early, kst(2026, 10, 20, 19, 30)), /이미 시작/);
  });
  await cell('PA-26', '저장 만료 이후 → 거절', () => {
    assert.match(cw(invite(), true, SLOT, START + 1), /기한이 지나/);
  });

  console.log('\n[PA-E] 동의 writer 실행 — 상태·좌석 불변, 중복 안전');
  const call = R.callableGiveApplicationDocumentConsent;
  const seed = (app, slot = SLOT) => {
    STORE = new Map(); WRITES = [];
    STORE.set('applications/a1', app);
    STORE.set('tos/t1/slots/s1', Object.assign({pendingCount: 1, confirmedCount: 0,
      workDetailCounts: {'wd-1': {pendingCount: 1, confirmedCount: 0}}}, slot));
    STORE.set('tos/t1', {totalPending: 1, totalConfirmed: 0});
  };
  const req = (uid, data) => ({auth: {uid}, data});
  await cell('PA-27', '기간 안 초대 → 동의 필드만 기록, status·집계 불변', async () => {
    NOW = START - 3600e3; seed(invite());
    const out = await call(req('w1', {applicationId: 'a1', documentAccessConsentVersion: INV}));
    assert.strictEqual(out.alreadyConsented, false);
    assert.strictEqual(WRITES.length, 1);
    assert.strictEqual(WRITES[0].path, 'applications/a1');
    const keys = Object.keys(WRITES[0].patch).sort();
    assert.deepStrictEqual(keys, ['documentAccessConsentAt', 'documentAccessConsentGiven',
      'documentAccessConsentVersion', 'idCardConsentAt', 'idCardConsentGiven', 'statusHistory']);
    const a = STORE.get('applications/a1');
    assert.strictEqual(a.status, 'INVITED');
    assert.strictEqual(STORE.get('tos/t1/slots/s1').pendingCount, 1);
    assert.strictEqual(STORE.get('tos/t1').totalPending, 1);
  });
  await cell('PA-28', '같은 요청 반복 → 쓰기 0, 처음 동의 시각 보존', async () => {
    NOW = START - 3000e3;
    const before = STORE.get('applications/a1').documentAccessConsentAt;
    const out = await call(req('w1', {applicationId: 'a1', documentAccessConsentVersion: INV}));
    assert.strictEqual(out.alreadyConsented, true);
    assert.strictEqual(WRITES.length, 1, '두 번째 호출이 쓰기를 남겼다');
    assert.strictEqual(STORE.get('applications/a1').documentAccessConsentAt, before);
  });
  await cell('PA-29', '다른 사람의 초대 → permission-denied, 쓰기 0', async () => {
    NOW = START - 3600e3; seed(invite());
    await assert.rejects(call(req('x9', {applicationId: 'a1', documentAccessConsentVersion: INV})),
        (e) => e.code === 'permission-denied');
    assert.strictEqual(WRITES.length, 0);
  });
  await cell('PA-30', '기한 지난 초대(status 아직 INVITED) → 거절, 쓰기 0', async () => {
    NOW = START + 1; seed(invite());
    await assert.rejects(call(req('w1', {applicationId: 'a1', documentAccessConsentVersion: INV})),
        (e) => e.code === 'failed-precondition' && /기한/.test(e.message));
    assert.strictEqual(WRITES.length, 0);
  });
  await cell('PA-31', 'slot 이 사라진 초대 → 거절, 쓰기 0', async () => {
    NOW = START - 3600e3; seed(invite());
    STORE.delete('tos/t1/slots/s1');
    await assert.rejects(call(req('w1', {applicationId: 'a1', documentAccessConsentVersion: INV})),
        (e) => e.code === 'failed-precondition');
    assert.strictEqual(WRITES.length, 0);
  });
  await cell('PA-32', '끝난 초대(EXPIRED·REJECTED) → 거절, 쓰기 0', async () => {
    for (const st of ['EXPIRED', 'REJECTED', 'CANCELED']) {
      NOW = START - 3600e3; seed(invite({status: st}));
      await assert.rejects(call(req('w1', {applicationId: 'a1', documentAccessConsentVersion: INV})),
          (e) => e.code === 'failed-precondition', st);
      assert.strictEqual(WRITES.length, 0, st);
    }
  });
  await cell('PA-33', 'V3 가 아닌 버전 → 거절(구 클라이언트·변조)', async () => {
    NOW = START - 3600e3; seed(invite());
    for (const v of [undefined, '2026-09-12-v2', 'v9']) {
      await assert.rejects(call(req('w1', {applicationId: 'a1', documentAccessConsentVersion: v})),
          (e) => e.code === 'invalid-argument', String(v));
    }
    assert.strictEqual(WRITES.length, 0);
  });
  await cell('PA-34', '직접 지원(PENDING) v2→v3 재동의는 기존대로 기록된다', async () => {
    NOW = START + 99e7;
    seed(invite({status: 'PENDING', inviteExpiresAt: undefined,
      documentAccessConsentGiven: true, documentAccessConsentVersion: '2026-09-12-v2'}));
    const out = await call(req('w1', {applicationId: 'a1', documentAccessConsentVersion: V3}));
    assert.strictEqual(out.alreadyConsented, false);
    assert.strictEqual(STORE.get('applications/a1').documentAccessConsentVersion, V3);
  });
  await cell('PA-35', '동의 후에는 열람 접근이 열리고 준비 상태는 REVIEW_PENDING', async () => {
    NOW = START - 3600e3; seed(invite());
    await call(req('w1', {applicationId: 'a1', documentAccessConsentVersion: INV}));
    const a = STORE.get('applications/a1');
    assert.strictEqual(block(a, 'b1', 'w1', NOW), null);
    assert.strictEqual(rd(a, userWith(), undefined), 'REVIEW_PENDING');
  });

  console.log('\n[PA-F] 수락 tx · 목록 reader 계약');
  const accept = (() => {
    const i = SRC.indexOf('export const callableAcceptTOInvitation = onCall(');
    return SRC.slice(i, balancedFrom(SRC, SRC.indexOf('(', i + 40), '(', ')'));
  })();
  await cell('PA-36', '수락 tx 는 저장 기한을 트랜잭션 안에서 다시 본다(좌석 쓰기 전)', () => {
    const exp = accept.indexOf('const freshExp =');
    const seat = accept.indexOf('tx.update(appRef, acceptUpdate)');
    assert.ok(exp > 0 && seat > exp);
  });
  await cell('PA-37', '수락 거절은 근로자용 문구 + 상태 코드(details)로 돌려준다', () => {
    assert.ok(accept.includes('srvInviteAcceptReadiness('));
    assert.ok(accept.includes('{inviteAcceptReadiness: acceptReadinessCode}'));
    assert.ok(!/acceptReadiness\.reason \?\?/.test(accept), '관리자용 reason 을 그대로 던진다');
  });
  await cell('PA-38', '수락 요청에 동의가 없으면 여전히 거절(fail-closed)', () => {
    assert.ok(accept.includes('if (!acceptDocConsentGiven) {'));
    assert.ok(accept.includes('srvResolveCommitmentConsentVersion('));
  });
  await cell('PA-39', '목록 reader 는 수락과 같은 판정 함수를 쓰고, 모르면 필드를 싣지 않는다', () => {
    const i = SRC.indexOf('export const callableGetMyApplications = onCall(');
    const body = SRC.slice(i, balancedFrom(SRC, SRC.indexOf('(', i + 40), '(', ')'));
    assert.ok(body.includes('srvInviteAcceptReadiness(d.data(), userSnap.data(), rv.data())'));
    assert.ok(body.includes('...(readiness ? {inviteAcceptReadiness: readiness} : {})'));
  });

  console.log('\n[PA-G] 동의 버전 — 한 토큰 = 한 문장, 상태별 허용 버전');
  await cell('PA-40', '초대 v1 은 허용 목록·검토 목적 집합에 있고, V1·V2 는 검토 목적이 아니다', () => {
    assert.ok(R.SUPPORTED_DOCUMENT_ACCESS_CONSENT_VERSIONS.includes(INV));
    assert.ok(R.SUPPORTED_DOCUMENT_ACCESS_CONSENT_VERSIONS.includes(V3));
    assert.deepStrictEqual([...R.REVIEW_PURPOSE_CONSENT_VERSIONS].sort(), [INV, V3].sort());
    for (const v of ['2026-08-21-v1', '2026-09-12-v2']) {
      assert.strictEqual(R.srvConsentCoversApplicantReview(
          {documentAccessConsentGiven: true, documentAccessConsentVersion: v}), false, v);
    }
  });
  await cell('PA-41', '초대 사전 동의는 초대 v1 을 기록한다', async () => {
    NOW = START - 3600e3; seed(invite());
    await call(req('w1', {applicationId: 'a1', documentAccessConsentVersion: INV}));
    assert.strictEqual(STORE.get('applications/a1').documentAccessConsentVersion, INV);
    assert.strictEqual(WRITES[0].patch.statusHistory.__arrayUnion[0].reason, INV);
  });
  await cell('PA-42', '초대에 V3 를 보내면 거절 — 본 문장과 기록이 어긋난다', async () => {
    NOW = START - 3600e3; seed(invite());
    await assert.rejects(call(req('w1', {applicationId: 'a1', documentAccessConsentVersion: V3})),
        (e) => e.code === 'invalid-argument');
    assert.strictEqual(WRITES.length, 0);
  });
  await cell('PA-43', '직접 지원에 초대 v1 을 보내면 거절', async () => {
    NOW = START; seed(invite({status: 'PENDING', inviteExpiresAt: undefined}));
    await assert.rejects(call(req('w1', {applicationId: 'a1', documentAccessConsentVersion: INV})),
        (e) => e.code === 'invalid-argument');
    assert.strictEqual(WRITES.length, 0);
  });
  await cell('PA-44', '기존 V3 로 동의된 초대(구 수락 경로)도 검토 목적으로 인정 · 재동의는 쓰기 0', async () => {
    NOW = START - 3600e3; seed(consented());
    const out = await call(req('w1', {applicationId: 'a1', documentAccessConsentVersion: INV}));
    assert.strictEqual(out.alreadyConsented, true);
    assert.strictEqual(WRITES.length, 0);
    assert.strictEqual(STORE.get('applications/a1').documentAccessConsentVersion, V3,
        '이미 본 문장의 기록을 바꾸지 않는다');
  });
  await cell('PA-45', '확정 후 신분증 접근창: 초대 v1 은 V3 와 같은 기준점(마지막 근무일)을 쓴다', () => {
    const i = SRC.indexOf('function srvIdWindowOpen(');
    const body = SRC.slice(i, SRC.indexOf('\n}\n', i));
    assert.ok(/v === DOCUMENT_ACCESS_CONSENT_V2 \|\| v === DOCUMENT_ACCESS_CONSENT_V3 \|\|\s*v === DOCUMENT_ACCESS_CONSENT_INVITE_V1\) \{\s*base = srvIdWindowLastWorkDay\(app\);/.test(body));
  });
  await cell('PA-46', '초대 v1 으로 동의한 초대도 열람 접근이 열린다(기간 안)', () => {
    assert.strictEqual(block(invite({documentAccessConsentGiven: true,
      documentAccessConsentVersion: INV}), 'b1', 'w1', START - 3600e3), null);
  });

  await cell('PA-59', '초대 v1 은 초대 수락만 기록할 수 있다(지원·재배치 수락은 거절)', () => {
    const f = R.srvResolveCommitmentConsentVersion;
    assert.strictEqual(f(INV, true, true), INV);
    assert.throws(() => f(INV, true, false), (e) => e.code === 'invalid-argument');
    assert.throws(() => f(INV, true), (e) => e.code === 'invalid-argument');
    assert.strictEqual(f(V3, true, false), V3, '지원은 V3');
    assert.strictEqual(f(V3, true, true), V3, '구 앱의 초대 수락은 V3 호환');
  });
  await cell('PA-60', '호출부: 초대 수락만 allowInviteCopy=true', () => {
    const at = (name) => {
      const i = SRC.indexOf(`export const ${name} = onCall(`);
      return SRC.slice(i, SRC.indexOf('\nexport const ', i + 10));
    };
    assert.ok(/srvResolveCommitmentConsentVersion\(\s*acceptDocConsentVersionRaw, acceptDocConsentGiven, true\)/
        .test(at('callableAcceptTOInvitation')));
    // 인자 개수로 본다 — 두 번째 인자 `given` 도 true 일 수 있다.
    const argsOf = (b) => {
      const i = b.indexOf('srvResolveCommitmentConsentVersion(');
      const open = i + 'srvResolveCommitmentConsentVersion'.length;
      const close = balancedFrom(b, open, '(', ')');
      const inner = b.slice(open + 1, close);
      let d = 0; let n = inner.trim() ? 1 : 0;
      for (const c of inner) {
        if ('([{'.includes(c)) d++;
        else if (')]}'.includes(c)) d--;
        else if (c === ',' && d === 0) n++;
      }
      return n;
    };
    assert.strictEqual(argsOf(at('callableAcceptTOInvitation')), 3);
    for (const n of ['callableApplyToTO', 'callableAcceptConfirmedReassignment']) {
      assert.strictEqual(argsOf(at(n)), 2, n + ' 가 초대 문구 허용 인자를 넘긴다');
    }
  });

  console.log('\n[PA-J] 약속 조건 동등성 — 확정과 초대 수락');
  const prov = R.srvBuildMatchingProvenance;
  await cell('PA-61', '자동 판정 근거: 사람 검토자 필드는 비운다(남아 있던 이전 검토자를 쓰지 않는다)', () => {
    const u = userWith({idCardMatchStatus: 'MATCHED', idCardMatchDocumentVersion: 2,
      idCardMatchEvidenceSource: 'OCR', bankbookDocumentVersion: 1, bankAccountVersion: 3});
    const rv = {idDecision: 'REVIEWED_OK', reviewedIdDocumentVersion: 1,
      reviewedBy: 'oldAdmin', reviewedAt: new Ts(1)};
    const r = R.srvResolveMatchingReadiness(u, rv);
    const p = prov('b1', u, rv, r);
    assert.strictEqual(p.documentReviewBasis, 'AUTO');
    assert.strictEqual(p.documentReviewedBy, null);
    assert.strictEqual(p.documentReviewedAt, null);
    assert.strictEqual(p.documentReviewedIdVersion, null);
    assert.strictEqual(p.matchingAutoEvidenceSource, 'OCR');
    assert.strictEqual(p.matchingAutoEvaluatedIdVersion, 2);
    assert.deepStrictEqual([p.documentReviewIdVersion, p.documentReviewBankbookVersion,
      p.documentReviewBankAccountVersion], [2, 1, 3]);
  });
  await cell('PA-62', '사람 검토 근거: 검토자·시각·검토한 문서 버전, 자동 근거는 비운다', () => {
    const u = userWith();
    const rv = {idDecision: 'REVIEWED_OK', reviewedIdDocumentVersion: 2,
      reviewedBy: 'admin7', reviewedAt: new Ts(5)};
    const r = R.srvResolveMatchingReadiness(u, rv);
    assert.strictEqual(r.ready, true);
    const p = prov('b1', u, rv, r);
    assert.strictEqual(p.documentReviewBasis, 'MANUAL');
    assert.strictEqual(p.documentReviewedBy, 'admin7');
    assert.strictEqual(p.documentReviewedIdVersion, 2);
    assert.strictEqual(p.documentReviewIdVersion, 2, '현재 문서 버전 = 검토한 버전');
    assert.strictEqual(p.matchingAutoEvidenceSource, null);
    assert.strictEqual(p.matchingReadinessState, 'READY_MANUAL');
  });
  await cell('PA-63', '오래된 사람 검토(문서 재업로드)는 준비되지 않음 — 근거를 만들 단계에 가지 않는다', () => {
    const rv = {idDecision: 'REVIEWED_OK', reviewedIdDocumentVersion: 2, reviewedBy: 'admin7'};
    const r = R.srvResolveMatchingReadiness(userWith({idDocumentVersion: 3}), rv);
    assert.strictEqual(r.ready, false);
  });
  await cell('PA-64', '탈퇴 동결(deleting) 계정은 공용 판정에서 거절', () => {
    assert.throws(() => R.srvAssertNotDeletingAccount({accountStatus: 'deleting'}),
        (e) => e.code === 'failed-precondition' && /탈퇴/.test(e.message));
    assert.doesNotThrow(() => R.srvAssertNotDeletingAccount({accountStatus: 'active'}));
  });
  const acceptSrc = (() => {
    const i = SRC.indexOf('export const callableAcceptTOInvitation = onCall(');
    return SRC.slice(i, SRC.indexOf('\nexport const ', i + 10));
  })();
  const confirmSrc = (() => {
    const i = SRC.indexOf('export const callableConfirmApplication = onCall(');
    return SRC.slice(i, SRC.indexOf('\nexport const ', i + 10));
  })();
  await cell('PA-65', '초대 수락: 동결·제재·서류 문턱·기한이 **모든 쓰기보다 먼저**(트랜잭션 안)', () => {
    const firstWrite = acceptSrc.indexOf('tx.update(');
    for (const gate of ['srvAssertNotDeletingAccount(freshUserData);',
      'const freshExp =', 'const acceptReadiness =',
      '{inviteAcceptReadiness: acceptReadinessCode}', '[ISG2-BLOCK-START]']) {
      const at = acceptSrc.indexOf(gate);
      assert.ok(at > 0, gate);
      assert.ok(at < firstWrite, `${gate} 이 첫 쓰기보다 뒤에 있다`);
    }
    // 같은 트랜잭션의 read-set 에 users 문서가 있다(동결 fence).
    assert.ok(acceptSrc.indexOf('await tx.get(db.collection("users").doc(callerUid))') <
      acceptSrc.indexOf('srvAssertNotDeletingAccount(freshUserData);'));
  });
  await cell('PA-66', '두 경로가 같은 근거 함수를 쓰고, 수락은 트랜잭션이 읽은 문서로 만든다', () => {
    assert.ok(confirmSrc.includes('srvBuildMatchingProvenance(\n        businessId, workerSnap.data(), reviewSnap.data(), readiness)') ||
      /srvBuildMatchingProvenance\(\s*businessId, workerSnap\.data\(\), reviewSnap\.data\(\), readiness\)/.test(confirmSrc));
    assert.ok(/srvBuildMatchingProvenance\(\s*\(freshData\.businessId as string \| undefined\) \?\? "",\s*freshUserData, acceptReviewSnap\.data\(\), acceptReadiness\)/.test(acceptSrc));
    // 근거는 CONFIRMED 와 같은 쓰기에 실린다(따로 쓰지 않는다).
    const upd = acceptSrc.indexOf('const acceptUpdate');
    const provAt = acceptSrc.indexOf('...srvBuildMatchingProvenance(');
    const write = acceptSrc.indexOf('tx.update(appRef, acceptUpdate);');
    assert.ok(upd < provAt && provAt < write);
  });
  await cell('PA-67', '초대 수락은 계약을 만들지 않는다(계약 발행은 관리자의 별도 행동)', () => {
    assert.ok(!/collection\("employment_contracts"\)[^;]*\.(set|create|add)\(/.test(acceptSrc));
  });

  console.log('\n[PA-H] 열람 창 — canonical slot 기준(누락·불일치·오염·정각)');
  const win = R.srvInviteReviewWindowOpen;
  const seedSlot = (slot) => {
    STORE = new Map(); WRITES = []; READS = 0;
    // [INVITE-LIFECYCLE] 열람 창은 공고도 읽는다 — 없으면 삭제로 보고 닫는다.
    STORE.set('tos/t1', {status: 'ACTIVE'});
    if (slot) STORE.set('tos/t1/slots/s1', slot);
  };
  await cell('PA-47', 'slot 시작 1ms 전 열림 · 정각 닫힘', async () => {
    seedSlot(SLOT);
    assert.strictEqual(await win(consented(), START - 1), true);
    assert.strictEqual(await win(consented(), START), false);
  });
  await cell('PA-48', 'snapshot 보다 slot 업무 시작이 이르면 slot 기준으로 닫힌다', async () => {
    seedSlot({date: new Ts(DAY), workDetails: [{wdId: 'wd-1', startTime: '18:00', endTime: '22:00'}]});
    // 저장 만료·snapshot(20:00)은 아직이지만 slot 상 근무는 18:00 에 시작했다.
    assert.strictEqual(await win(consented(), kst(2026, 10, 20, 18, 30)), false);
  });
  await cell('PA-49', 'slot 없음·업무 불일치 → 닫힘(fail-closed)', async () => {
    seedSlot(null);
    assert.strictEqual(await win(consented(), START - 3600e3), false);
    seedSlot(SLOT);
    assert.strictEqual(await win(consented({wdId: 'zzz'}), START - 3600e3), false);
  });
  await cell('PA-50', '오염 snapshot(workDate KST 09:00) → 닫힘', async () => {
    seedSlot(SLOT);
    assert.strictEqual(await win(consented({workDate: new Ts(DAY + K)}), START - 3600e3), false);
  });
  await cell('PA-51', '장기 초대는 slot 을 읽지 않고 저장 만료(+공고 종료)만 본다', async () => {
    seedSlot(null);
    const lt = consented({slotId: undefined, type: 'long_term', workDays: ['월'],
      inviteExpiresAt: new Ts(START)});
    assert.strictEqual(await win(lt, START - 1), true);
    assert.strictEqual(await win(lt, START), false);
    // [INVITE-LIFECYCLE] 공고 1회만 읽는다(slot 은 읽지 않는다).
    assert.strictEqual(READS, 1);
  });
  await cell('PA-52', 'INVITED 가 아니면 이 창의 대상이 아니다(직접 지원 계약 유지)', async () => {
    seedSlot(null);
    assert.strictEqual(await win(consented({status: 'PENDING'}), START + 99e7), true);
  });
  await cell('PA-53', '열람·검토 4개 callable 공용 판정(async)도 slot 창을 따른다', async () => {
    seedSlot({date: new Ts(DAY), workDetails: [{wdId: 'wd-1', startTime: '18:00', endTime: '22:00'}]});
    const at = kst(2026, 10, 20, 18, 30);
    assert.strictEqual(block(consented(), 'b1', 'w1', at), null, '동기 판정만으로는 열려 있다');
    assert.match(await R.srvApplicantReviewAccessBlockAsync(consented(), 'b1', 'w1', at), /기한이 지나/);
  });
  await cell('PA-54', '4개 callable 이 모두 async 판정을 쓴다', () => {
    for (const name of ['callableGetApplicantDocumentReview', 'callableGetApplicantDocumentUrl',
      'callableReviewApplicantDocument', 'callableRequestDocumentCorrection']) {
      const i = SRC.indexOf(`export const ${name} = onCall(`);
      const body = SRC.slice(i, SRC.indexOf('\nexport const ', i + 10));
      assert.ok(body.includes('await srvApplicantReviewAccessBlockAsync('), name);
      assert.ok(!/[^c]srvApplicantReviewAccessBlock\(/.test(body.replace(/srvApplicantReviewAccessBlockAsync/g, '')), name);
    }
  });
  await cell('PA-55', '원본 신분증 목적: 기한 지난 초대(status 아직 INVITED)로는 열리지 않는다', async () => {
    STORE = new Map(); READS = 0;
    STORE.set('applications/a1', consented());
    STORE.set('tos/t1', {status: 'ACTIVE'});
    STORE.set('tos/t1/slots/s1', SLOT);
    assert.strictEqual(await R.srvHasActiveIdentityDocumentPurpose('b1', 'w1', START - 3600e3), true);
    assert.strictEqual(await R.srvHasActiveIdentityDocumentPurpose('b1', 'w1', START), false);
  });
  await cell('PA-56', '원본 신분증 목적: 초대 v1 동의도 기간 안에서는 목적이 된다', async () => {
    STORE = new Map();
    STORE.set('applications/a1', invite({documentAccessConsentGiven: true, documentAccessConsentVersion: INV}));
    STORE.set('tos/t1', {status: 'ACTIVE'});
    STORE.set('tos/t1/slots/s1', SLOT);
    assert.strictEqual(await R.srvHasActiveIdentityDocumentPurpose('b1', 'w1', START - 3600e3), true);
  });

  console.log('\n[PA-I] 목록 reader — 조회 실패를 READY 와 구분, canonical 마감');
  const lst = (() => {
    const i = SRC.indexOf('export const callableGetMyApplications = onCall(');
    return SRC.slice(i, SRC.indexOf('\nexport const ', i + 10));
  })();
  await cell('PA-57', '검토 문서·근로자 문서 조회 실패는 UNAVAILABLE 로 명시한다', () => {
    assert.ok(lst.includes('readinessMap[d.id] = "UNAVAILABLE";'));
    assert.ok(lst.includes('for (const d of invitedDocs) readinessMap[d.id] = "UNAVAILABLE";'));
  });
  await cell('PA-58', '수락 마감은 같은 리졸버(slot)로 계산하고, 못 하면 싣지 않는다', () => {
    assert.ok(lst.includes('const g = srvResolveGuardShiftStart(d.data(), true, sd);'));
    assert.ok(lst.includes('deadlineMap[d.id] = Math.min(exp.toMillis(), g.startMs);'));
    assert.ok(lst.includes('{inviteAcceptDeadlineMs: deadlineMap[d.id]}'));
  });

  console.log(`\n통과 ${pass} / 실패 ${fails.length}`);
  if (fails.length) { fails.forEach((f) => console.log('  - ' + f)); process.exit(1); }
})();
