/**
 * [ALFIT-AUTH-KAKAO-ONBOARDING.1 §6] 카카오 가입·로그인·역할 추가·탈퇴 재확인 — 서버 원문 실행 시험.
 *
 *   실행:  npm --prefix functions run build && node --test --test-concurrency=1 test/auth_kakao_signup_callables.test.js
 *
 *   무엇을 실행하나: **컴파일된 원문** lib/auth_kakao.js 의 createAuthKakao(deps) 에 가짜 의존을 주입한다.
 *     · Firestore = test/consent_r4d_fakestore.js(거래 버퍼·create 충돌·커밋 훅)
 *     · Firebase Auth = 가짜(getUser/createUser/createCustomToken · 실패 주입 · 호출 순서 기록)
 *     · 카카오 토큰 검증·PortOne 조회 = 가짜 어댑터(실제 외부 호출 0 — http/https/net/dns/fetch 차단)
 *   그래서 결과는 전부 **모의 · PENDING VERIFICATION**(실 카카오/KG 아님). 판정278 검증 목록에 맞춘다.
 *
 *   묶음: AK-N 정상 · AK-A 부분 실패/응답 유실 · AK-K 카카오 검증 · AK-P KG 결합/replay ·
 *         AK-D 동일인/경쟁/충돌 · AK-R 세션 재개/취소 · AK-Q 역할 추가 · AK-B 블랙/30일 ·
 *         AK-X 탈퇴 재확인/삭제 재개 · AK-L4 옛 QA 미연결
 */
'use strict';
const NET = [];
for (const [m, ks] of [['http', ['request', 'get']], ['https', ['request', 'get']], ['net', ['connect', 'createConnection']],
  ['tls', ['connect']], ['dns', ['lookup', 'resolve', 'resolve4', 'resolve6']]]) {
  const mod = require(m);
  for (const k of ks) mod[k] = () => { NET.push(`${m}.${k}`); throw new Error(`[차단] ${m}.${k}`); };
}
globalThis.fetch = () => { NET.push('fetch'); throw new Error('[차단] fetch'); };

const assert = require('assert');
const path = require('path');
const {createFakeFirestore} = require('./consent_r4d_fakestore');
const {createAuthKakao} = require(path.join(__dirname, '..', 'lib', 'auth_kakao.js'));
const CORE = require(path.join(__dirname, '..', 'lib', 'signup_core.js'));

const MIN = 60e3;
const DAY = 24 * 3600e3;
let NOW = Date.UTC(2026, 10, 25, 3, 0);
const F = createFakeFirestore({now: () => NOW});

class HttpsError extends Error {
  constructor(code, message, details) { super(message); this.code = code; this.details = details; }
}
const GLOG = [];
F.hooks.beforeCommit = (tx, buf) => GLOG.push(['commit', tx, buf.map((w) => w.path)]);

// ── 가짜 Auth ──────────────────────────────────────────────────────────
const AUTH = {users: new Set(), fail: {createUser: 0, token: 0, getUser: 0}};
const authApi = {
  async getUser(uid) {
    GLOG.push(['getUser', uid]);
    if (AUTH.fail.getUser > 0) { AUTH.fail.getUser--; const e = new Error('x'); e.code = 'auth/internal-error'; throw e; }
    if (!AUTH.users.has(uid)) { const e = new Error('nf'); e.code = 'auth/user-not-found'; throw e; }
    return {uid};
  },
  async createUser(p) {
    GLOG.push(['createUser', p]);
    if (AUTH.fail.createUser > 0) { AUTH.fail.createUser--; throw new Error('boom'); }
    if (AUTH.users.has(p.uid)) { const e = new Error('dup'); e.code = 'auth/uid-already-exists'; throw e; }
    AUTH.users.add(p.uid);
    return {uid: p.uid};
  },
  async createCustomToken(...a) {
    GLOG.push(['createCustomToken', ...a]);
    if (AUTH.fail.token > 0) { AUTH.fail.token--; throw new Error('sign'); }
    return 'tok:' + a[0];
  },
};

// ── 가짜 카카오·PortOne ────────────────────────────────────────────────
const APP = '111';
const KAKAO = new Map(); // token → info
const kakao = {async verify(t) { return KAKAO.get(t) ?? {ok: false, reason: 'KAKAO_TOKEN_INVALID'}; }};
const PORTONE = new Map(); // impUid → raw | () => raw
let PORTONE_READS = 0;
const portone = {async read({impUid}) {
  PORTONE_READS++;
  const v = PORTONE.get(impUid);
  if (v === undefined) return {ok: true, raw: {code: -1, response: null}};
  return {ok: true, raw: typeof v === 'function' ? v() : v};
}};
const ENV = {KAKAO_APP_ID: APP};
const NOTIFY = [];
const svc = createAuthKakao({
  db: F.db, FieldValue: F.FieldValue, Timestamp: F.Ts, HttpsError,
  auth: () => authApi, kakao, portone, env: () => ENV, now: () => NOW,
  notify: async (uid, p) => { NOTIFY.push([uid, p.type]); },
});
const KEYS = {impKey: 'k', impSecret: 's', ciHmacKey: 'h'.repeat(32)};

// ── 장면 ─────────────────────────────────────────────────────────────
function seedLegal() {
  F.put('app_settings/legal_terms', {items: [
    {id: 'terms', version: 'v1', isRequired: true, isActive: true},
    {id: 'privacy', version: 'v1', isRequired: true, isActive: true},
    {id: 'marketing', version: 'v1', isRequired: false, isActive: true},
  ]});
}
function reset() {
  F.reset(); GLOG.length = 0; AUTH.users.clear(); AUTH.fail = {createUser: 0, token: 0, getUser: 0};
  KAKAO.clear(); PORTONE.clear(); PORTONE_READS = 0; NOTIFY.length = 0; NOW = Date.UTC(2026, 10, 25, 3, 0);
  F.hooks.beforeCommit = (tx, buf) => GLOG.push(['commit', tx, buf.map((w) => w.path)]);
  seedLegal();
}
function kakaoUser(subject, o = {}) {
  const token = `tok-${subject}-${Math.random().toString(36).slice(2)}`;
  KAKAO.set(token, Object.assign({ok: true, subject: String(subject), appId: APP, expiresInSec: 3600}, o));
  return token;
}
const CONSENT = {terms: {agreed: true, version: 'v1'}, privacy: {agreed: true, version: 'v1'},
  marketing: {agreed: false, version: 'v1'}};
function kg(impUid, requestId, o = {}) {
  PORTONE.set(impUid, () => ({code: 0, response: Object.assign({
    certified: true, unique_key: 'CI-PERSON-A', name: '홍길동', birthday: '1990-01-15',
    phone: '01012345678', gender: 'male', merchant_uid: requestId,
    certified_at: Math.floor(NOW / 1000), pg_provider: 'inicis_unified'}, o)}));
}
const S = (sess) => ({sessionId: sess.sessionId, secret: sess.secret});
async function begin(subject, role = 'USER') {
  const r = await svc.authKakao({data: {accessToken: kakaoUser(subject)}});
  assert.strictEqual(r.status, 'SIGNUP_REQUIRED');
  const sess = r.session;
  await svc.sessionSetPurpose({data: {...S(sess), role}});
  await svc.sessionConsent({data: {...S(sess), consentRecord: CONSENT}});
  return sess;
}
async function toPass(sess, impUid, kgOver = {}) {
  const p = await svc.sessionPrepareCertification({data: S(sess)});
  kg(impUid, p.requestId, kgOver);
  return svc.verifyPassSignup({data: {...S(sess), imp_uid: impUid}}, KEYS);
}
async function fullSignup(subject, role, impUid, kgOver = {}) {
  const sess = await begin(subject, role);
  await toPass(sess, impUid, kgOver);
  const out = await svc.completeSignup({data: S(sess)});
  return {sess, out};
}
async function rejects(p, reason) {
  try { await p; } catch (e) {
    assert.strictEqual(e.details && e.details.reason, reason, `reason ${e.details && e.details.reason} ≠ ${reason} (${e.message})`);
    return e;
  }
  throw new Error(`거절 ${reason} 기대 — 성공함`);
}
const docs = (prefix) => Object.keys(F.dump()).filter((k) => k.startsWith(prefix + '/') &&
  k.split('/').length === prefix.split('/').length + 1);
const ciKeyOf = (ci) => CORE.computeCiKeyV1(KEYS.ciHmacKey, ci);

// ── 실행기 ───────────────────────────────────────────────────────────
const CELLS = [];
const cell = (name, fn) => CELLS.push([name, fn]);
let pass = 0;
const fails = [];

// ═══ AK-N 정상 신규 ═════════════════════════════════════════════════
cell('AK-N1 USER 신규 — 한 커밋에 identity·subject·양방향 링크·users·consentEvents·세션 결과, Auth 는 커밋 뒤', async () => {
  const {out} = await fullSignup('9001', 'USER', 'imp-n1');
  assert.strictEqual(out.status, 'COMMITTED');
  assert.strictEqual(out.authPending, false);
  const uid = out.uid;
  assert.strictEqual(out.customToken, 'tok:' + uid);
  const k = ciKeyOf('CI-PERSON-A');
  const ident = F.get('identities/' + k);
  assert.strictEqual(ident.keyVersion, 1);
  assert.strictEqual(ident.roles.USER.uid, uid);
  assert.strictEqual(ident.roles.USER.state, 'active');
  assert.deepStrictEqual(ident.providerSubjects.kakao, {appNs: APP, subject: '9001'});
  assert.deepStrictEqual(F.get(`authSubjects/kakao_${APP}_9001`).roles, {USER: uid});
  assert.strictEqual(F.get(`authLinks/kakao_${APP}_9001_USER`).uid, uid);
  assert.strictEqual(F.get(`authLinkOwners/${uid}_kakao`).linkId, `kakao_${APP}_9001_USER`);
  const u = F.get('users/' + uid);
  // authProvisionedAt 은 커밋 **뒤** Auth 준비 단계가 남기는 정보용 시각(gate 아님) — allowlist 는 커밋 시점 문서.
  for (const key of Object.keys(u)) {
    assert.ok(CORE.NEW_USER_DOC_KEYS.includes(key) || key === 'authProvisionedAt', `allowlist 밖 ${key}`);
  }
  for (const key of ['bankName', 'accountNumber', 'accountHolder', 'homeRegion', 'ciHash']) assert.ok(!(key in u), key);
  assert.strictEqual(u.identityKey, k);
  assert.strictEqual(u.identityEvidence, 'kg');
  assert.strictEqual(u.nationalityStatus, 'unknown');
  assert.strictEqual(u.gender, '남성');
  assert.strictEqual(u.identityBasisSource, 'PASS');
  assert.ok(u.passVerifiedAt && u.termsConsentAt, '법적 타임스탬프');
  assert.strictEqual(u.termsConsent.terms.version, 'v1');
  const ev = docs(`users/${uid}/consentEvents`).map((p) => F.get(p));
  assert.strictEqual(ev.length, 3, '동의 사건 = 보낸 항목 수(거부 포함)');
  assert.ok(ev.every((e) => e.source === 'signup_session' && typeof e.revisionId === 'string'));
  assert.ok(ev.some((e) => e.itemId === 'marketing' && e.agreed === false));
  // 커밋 순서: users 를 쓴 커밋이 createUser 보다 먼저.
  const ci = GLOG.findIndex((g) => g[0] === 'commit' && g[2].includes('users/' + uid));
  const ai = GLOG.findIndex((g) => g[0] === 'createUser');
  assert.ok(ci >= 0 && ai > ci, 'Auth 생성이 커밋 뒤가 아니다');
  const tokCall = GLOG.find((g) => g[0] === 'createCustomToken');
  assert.strictEqual(tokCall.length, 2, 'custom token 에 claims 가 붙었다');
  const sessDoc = F.get(`signupSessions/kakao_${APP}_9001`);
  assert.strictEqual(sessDoc.state, 'committed');
  assert.strictEqual(sessDoc.result.uid, uid);
  assert.strictEqual(sessDoc.pass, null, 'KG 결과(PII)는 커밋 때 지운다');
  assert.strictEqual(F.get('passCertifications/' + CORE.sha256Hex('imp-n1')).outcomeRef, 'users/' + uid);
});
cell('AK-N2 BUSINESS_ADMIN 신규 · KG 성별 미제공 → gender 키 없음(여성 폴백 0)', async () => {
  const {out} = await fullSignup('9002', 'BUSINESS_ADMIN', 'imp-n2', {gender: undefined});
  const u = F.get('users/' + out.uid);
  assert.strictEqual(u.role, 'BUSINESS_ADMIN');
  assert.ok(!('gender' in u));
  assert.ok(!('identityBasisSource' in u));
});

// ═══ AK-A 부분 실패·응답 유실 ════════════════════════════════════════
cell('AK-A1 createUser 실패 → COMMITTED+authPending · FinalizeAuth 재호출 → 같은 uid', async () => {
  AUTH.fail.createUser = 1;
  const {sess, out} = await fullSignup('9003', 'USER', 'imp-a1');
  assert.strictEqual(out.status, 'COMMITTED');
  assert.strictEqual(out.authPending, true);
  assert.ok(!out.customToken);
  const r = await svc.finalizeAuth({data: S(sess)});
  assert.strictEqual(r.uid, out.uid);
  assert.strictEqual(r.customToken, 'tok:' + out.uid);
  assert.strictEqual(docs('users').length, 1);
});
cell('AK-A2 응답 유실 → 같은 세션 재호출 멱등 · 카카오 재로그인 → 같은 uid TOKEN', async () => {
  AUTH.fail.token = 1;
  const {sess, out} = await fullSignup('9004', 'USER', 'imp-a2');
  assert.strictEqual(out.authPending, true);
  const again = await svc.completeSignup({data: S(sess)});
  assert.strictEqual(again.uid, out.uid);
  assert.strictEqual(again.customToken, 'tok:' + out.uid);
  const login = await svc.authKakao({data: {accessToken: kakaoUser('9004')}});
  assert.strictEqual(login.status, 'TOKEN');
  assert.strictEqual(login.uid, out.uid);
  assert.strictEqual(docs('users').length, 1, '새 계정이 생기면 안 된다');
  assert.strictEqual(GLOG.filter((g) => g[0] === 'createUser').length, 1);
});
cell('AK-A3 거래 커밋 시점에 Auth 호출 0 — 외부 작업은 거래 콜백 밖', async () => {
  let authAtCommit = -1;
  F.hooks.beforeCommit = (tx, buf) => {
    if (buf.some((w) => w.path.startsWith('users/'))) {
      authAtCommit = GLOG.filter((g) => g[0] === 'createUser' || g[0] === 'getUser').length;
    }
  };
  await fullSignup('9005', 'USER', 'imp-a3');
  assert.strictEqual(authAtCommit, 0);
});

// ═══ AK-K 카카오 검증 ═══════════════════════════════════════════════
cell('AK-K1 다른 앱 토큰 → KAKAO_APP_MISMATCH · 쓰기 0', async () => {
  const before = F.W.commits.length;
  await rejects(svc.authKakao({data: {accessToken: kakaoUser('9101', {appId: '999'})}}), 'KAKAO_APP_MISMATCH');
  assert.strictEqual(F.W.commits.length, before);
});
cell('AK-K2 만료 토큰(expires_in 0) · 무효 토큰 → KAKAO_TOKEN_INVALID', async () => {
  await rejects(svc.authKakao({data: {accessToken: kakaoUser('9102', {expiresInSec: 0})}}), 'KAKAO_TOKEN_INVALID');
  await rejects(svc.authKakao({data: {accessToken: 'unknown-token'}}), 'KAKAO_TOKEN_INVALID');
});
cell('AK-K3 클라가 보낸 kakaoId/uid 는 무시 — 세션 키는 서버 추출 subject', async () => {
  const r = await svc.authKakao({data: {accessToken: kakaoUser('9103'), kakaoId: '666', uid: 'victim'}});
  assert.strictEqual(r.session.sessionId, `kakao_${APP}_9103`);
  assert.ok(!F.has(`signupSessions/kakao_${APP}_666`));
});
cell('AK-K4 앱 id 설정 없음 → KAKAO_NOT_CONFIGURED', async () => {
  const save = ENV.KAKAO_APP_ID;
  delete ENV.KAKAO_APP_ID;
  try { await rejects(svc.authKakao({data: {accessToken: kakaoUser('9104')}}), 'KAKAO_NOT_CONFIGURED'); } finally { ENV.KAKAO_APP_ID = save; }
});

// ═══ AK-P KG 결합·replay ═══════════════════════════════════════════
cell('AK-P1 같은 세션 같은 imp_uid 재호출 → 멱등(재조회 0)', async () => {
  const sess = await begin('9201');
  await toPass(sess, 'imp-p1');
  const reads = PORTONE_READS;
  const again = await svc.verifyPassSignup({data: {...S(sess), imp_uid: 'imp-p1'}}, KEYS);
  assert.strictEqual(again.name, '홍길동');
  assert.strictEqual(PORTONE_READS, reads);
});
cell('AK-P2 다른 세션이 같은 imp_uid → IMP_UID_BOUND_ELSEWHERE', async () => {
  const a = await begin('9202');
  await toPass(a, 'imp-p2');
  const b = await begin('9203');
  await svc.sessionPrepareCertification({data: S(b)});
  await rejects(svc.verifyPassSignup({data: {...S(b), imp_uid: 'imp-p2'}}, KEYS), 'IMP_UID_BOUND_ELSEWHERE');
});
cell('AK-P3 cert 만료(코드 비교 · TTL 비의존) → CERT_EXPIRED', async () => {
  const sess = await begin('9204');
  const p = await svc.sessionPrepareCertification({data: S(sess)});
  kg('imp-p3', p.requestId);
  NOW += 21 * MIN;
  await rejects(svc.verifyPassSignup({data: {...S(sess), imp_uid: 'imp-p3'}}, KEYS), 'CERT_EXPIRED');
});
cell('AK-P4 역할 변경 → 옛 KG 폐기 · 완료 거부', async () => {
  const sess = await begin('9205', 'USER');
  await toPass(sess, 'imp-p4');
  const r = await svc.sessionSetPurpose({data: {...S(sess), role: 'BUSINESS_ADMIN'}});
  assert.strictEqual(r.session.passDone, false);
  assert.strictEqual(r.session.state, 'consented');
  await rejects(svc.completeSignup({data: S(sess)}), 'PASS_REQUIRED');
});
cell('AK-P5 CI 없음 → KG_CI_MISSING (DEV 전화 대체 0) · 세션 pass 없음', async () => {
  const sess = await begin('9206');
  await rejects(toPass(sess, 'imp-p5', {unique_key: ''}), 'KG_CI_MISSING');
  assert.strictEqual(F.get(`signupSessions/kakao_${APP}_9206`).pass, null);
  assert.ok(!F.has('passCertifications/' + CORE.sha256Hex('imp-p5')));
});
cell('AK-P6 certified 가 문자열 → KG_NOT_CERTIFIED', async () => {
  const sess = await begin('9207');
  await rejects(toPass(sess, 'imp-p6', {certified: 'true'}), 'KG_NOT_CERTIFIED');
});
cell('AK-P7 merchant_uid ≠ 서버 requestId → KG_BINDING_MISMATCH', async () => {
  const sess = await begin('9208');
  await svc.sessionPrepareCertification({data: S(sess)});
  kg('imp-p7', 'alfit_cert_other');
  await rejects(svc.verifyPassSignup({data: {...S(sess), imp_uid: 'imp-p7'}}, KEYS), 'KG_BINDING_MISMATCH');
});
cell('AK-P8 CI HMAC 키 없음 → CI_KEY_UNAVAILABLE (PortOne 조회 전)', async () => {
  const sess = await begin('9209');
  const p = await svc.sessionPrepareCertification({data: S(sess)});
  kg('imp-p8', p.requestId);
  const reads = PORTONE_READS;
  await rejects(svc.verifyPassSignup({data: {...S(sess), imp_uid: 'imp-p8'}}, {...KEYS, ciHmacKey: ''}),
    'CI_KEY_UNAVAILABLE');
  assert.strictEqual(PORTONE_READS, reads);
});
cell('AK-P9 만 19세 미만 → UNDER_AGE', async () => {
  const sess = await begin('9210');
  await rejects(toPass(sess, 'imp-p9', {birthday: '2008-01-01'}), 'UNDER_AGE');
});
cell('AK-P10 KG 시도 5회 상한 → CERT_ATTEMPTS_EXCEEDED', async () => {
  const sess = await begin('9211');
  for (let i = 0; i < 5; i++) await svc.sessionPrepareCertification({data: S(sess)});
  await rejects(svc.sessionPrepareCertification({data: S(sess)}), 'CERT_ATTEMPTS_EXCEEDED');
});

// ═══ AK-D 동일인·경쟁·충돌 ═════════════════════════════════════════
cell('AK-D1 같은 CI·같은 역할·다른 카카오 → IDENTITY_ROLE_TAKEN · 세션 종결 · Auth 0 · 기존 계정 알림', async () => {
  const first = await fullSignup('9301', 'USER', 'imp-d1a');
  const sess = await begin('9302', 'USER');
  await toPass(sess, 'imp-d1b');
  const createBefore = GLOG.filter((g) => g[0] === 'createUser').length;
  const e = await rejects(svc.completeSignup({data: S(sess)}), 'IDENTITY_ROLE_TAKEN');
  assert.strictEqual(e.code, 'already-exists');
  assert.strictEqual(docs('users').length, 1);
  assert.strictEqual(GLOG.filter((g) => g[0] === 'createUser').length, createBefore);
  assert.strictEqual(F.get(`signupSessions/kakao_${APP}_9302`).state, 'blocked_existing');
  assert.ok(!F.has(`authLinks/kakao_${APP}_9302_USER`));
  await new Promise((r) => setImmediate(r));
  assert.deepStrictEqual(NOTIFY, [[first.out.uid, 'signupAttemptExistingAccount']]);
});
cell('AK-D2 같은 사람이 다른 카카오로 다른 역할 → IDENTITY_PROVIDER_MISMATCH(자동 연결 0)', async () => {
  await fullSignup('9303', 'USER', 'imp-d2a');
  const sess = await begin('9304', 'BUSINESS_ADMIN');
  await toPass(sess, 'imp-d2b');
  await rejects(svc.completeSignup({data: S(sess)}), 'IDENTITY_PROVIDER_MISMATCH');
  assert.strictEqual(docs('users').length, 1);
});
cell('AK-D3 다른 사람 KG 로 같은 카카오에 역할 추가 → ADD_ROLE_IDENTITY_MISMATCH', async () => {
  const a = await fullSignup('9305', 'USER', 'imp-d3a');
  const st = await svc.sessionStartAddRole({auth: {uid: a.out.uid}, data: {role: 'BUSINESS_ADMIN'}});
  const sess = st.session;
  await svc.sessionConsent({data: {...S(sess), consentRecord: CONSENT}});
  await toPass(sess, 'imp-d3b', {unique_key: 'CI-PERSON-B'});
  await rejects(svc.completeSignup({data: S(sess)}), 'ADD_ROLE_IDENTITY_MISMATCH');
  assert.strictEqual(docs('users').length, 1);
});
cell('AK-D4 역방향 링크(UID→카카오) 점유 → LINK_CONFLICT(자동 교체 0)', async () => {
  const sess = await begin('9306');
  await toPass(sess, 'imp-d4');
  const p = `signupSessions/kakao_${APP}_9306`;
  F.put(p, Object.assign(F.get(p), {reservedUid: 'UFIXED'}));
  F.put('authLinkOwners/UFIXED_kakao', {linkId: 'kakao_111_other_USER'});
  await rejects(svc.completeSignup({data: S(sess)}), 'LINK_CONFLICT');
  assert.ok(!F.has('users/UFIXED'));
});
cell('AK-D5 경합 근거 — 완료 거래 read-set 에 identities/{ciKey}·authLinks·authLinkOwners·users 포함', async () => {
  F.clearLog();
  const {out} = await fullSignup('9307', 'USER', 'imp-d5');
  const k = ciKeyOf('CI-PERSON-A');
  const commitTx = F.W.commits.find((c) => c.writes.some((w) => w.path === 'users/' + out.uid)).tx;
  const reads = F.W.reads.filter((r) => r.tx === commitTx).map((r) => r.path);
  for (const want of ['identities/' + k, `authLinks/kakao_${APP}_9307_USER`, `authLinkOwners/${out.uid}_kakao`,
    'users/' + out.uid, 'account_deletion_tombstones/' + out.uid]) {
    assert.ok(reads.includes(want), `거래가 ${want} 를 읽지 않는다`);
  }
  const writes = F.W.commits.find((c) => c.tx === commitTx).writes.map((w) => w.path);
  assert.ok(writes.includes('identities/' + k), '같은 거래가 identity 를 쓰지 않는다(경합 직렬화 근거)');
});
cell('AK-D6 같은 세션 연속 완료(경합 재실행 흉내) → users 1 · 두 번째는 멱등', async () => {
  const sess = await begin('9308');
  await toPass(sess, 'imp-d6');
  const [x, y] = [await svc.completeSignup({data: S(sess)}), await svc.completeSignup({data: S(sess)})];
  assert.strictEqual(x.uid, y.uid);
  assert.strictEqual(docs('users').length, 1);
});

cell('AK-D7 이미 역할이 연결된 카카오로 일반 가입 완료(다른 기기 경합) → ROLE_ADD_REQUIRED', async () => {
  const sess = await begin('9309', 'USER');
  await toPass(sess, 'imp-d7');
  F.put(`authSubjects/kakao_${APP}_9309`, {provider: 'kakao', appNs: APP, subject: '9309',
    identityKey: ciKeyOf('CI-PERSON-A'), roles: {BUSINESS_ADMIN: 'OTHERUID'}});
  await rejects(svc.completeSignup({data: S(sess)}), 'ROLE_ADD_REQUIRED');
  assert.strictEqual(docs('users').length, 0);
});

// ═══ AK-R 세션 재개·취소 ═══════════════════════════════════════════
cell('AK-R1 재로그인 → secret 회전 · 옛 secret 거부 · 단계 유지', async () => {
  const sess = await begin('9401');
  const r = await svc.authKakao({data: {accessToken: kakaoUser('9401')}});
  assert.strictEqual(r.session.sessionId, sess.sessionId);
  assert.notStrictEqual(r.session.secret, sess.secret);
  assert.strictEqual(r.session.state, 'consented');
  await rejects(svc.sessionGet({data: S(sess)}), 'SESSION_INVALID');
  const ok = await svc.sessionGet({data: S(r.session)});
  assert.strictEqual(ok.session.consentDone, true);
});
cell('AK-R2 취소 → cert·pass 삭제 · 재로그인 → 새 세대', async () => {
  const sess = await begin('9402');
  await toPass(sess, 'imp-r2');
  const c = await svc.sessionCancel({data: S(sess)});
  assert.strictEqual(c.session.state, 'canceled');
  const doc = F.get(`signupSessions/kakao_${APP}_9402`);
  assert.strictEqual(doc.pass, null);
  assert.strictEqual(doc.cert, null);
  const r = await svc.authKakao({data: {accessToken: kakaoUser('9402')}});
  assert.strictEqual(r.session.generation, 2);
  assert.strictEqual(r.session.state, 'started');
});
cell('AK-R3 24h 만료 → 읽을 때 만료 판정 · 재로그인 → 새 세대', async () => {
  const sess = await begin('9403');
  NOW += DAY + 1;
  await rejects(svc.sessionGet({data: S(sess)}), 'SESSION_EXPIRED');
  const r = await svc.authKakao({data: {accessToken: kakaoUser('9403')}});
  assert.strictEqual(r.session.generation, 2);
});
cell('AK-R4 KG 30분 경과 뒤 완료 → PASS_RESULT_STALE', async () => {
  const sess = await begin('9404');
  await toPass(sess, 'imp-r4');
  NOW += 31 * MIN;
  await rejects(svc.completeSignup({data: S(sess)}), 'PASS_RESULT_STALE');
});
cell('AK-R5 sessionId 만 아는 호출자 → 읽기·완료 불가', async () => {
  const sess = await begin('9405');
  const fake = {sessionId: sess.sessionId, secret: 'ab'.repeat(32)};
  await rejects(svc.sessionGet({data: fake}), 'SESSION_INVALID');
  await rejects(svc.completeSignup({data: fake}), 'SESSION_INVALID');
  await rejects(svc.sessionGet({data: {sessionId: '../users/x', secret: sess.secret}}), 'SESSION_INVALID');
});
cell('AK-R6 약관 판 바뀜 → 완료 거부 TERMS_VERSION_STALE · 옛 판 동의 → STALE', async () => {
  const sess = await begin('9406');
  await toPass(sess, 'imp-r6');
  F.put('app_settings/legal_terms', {items: [
    {id: 'terms', version: 'v2', isRequired: true, isActive: true},
    {id: 'privacy', version: 'v1', isRequired: true, isActive: true},
  ]});
  await rejects(svc.completeSignup({data: S(sess)}), 'TERMS_VERSION_STALE');
  await rejects(svc.sessionConsent({data: {...S(sess), consentRecord: {terms: {agreed: true, version: 'v1'}}}}),
    'TERMS_VERSION_STALE');
  await svc.sessionConsent({data: {...S(sess), consentRecord: {terms: {agreed: true, version: 'v2'}}}});
  const out = await svc.completeSignup({data: S(sess)});
  assert.strictEqual(F.get('users/' + out.uid).termsConsent.terms.version, 'v2');
});
cell('AK-R7 필수 동의 없이 KG 준비 → CONSENT_REQUIRED', async () => {
  const r = await svc.authKakao({data: {accessToken: kakaoUser('9407')}});
  await svc.sessionSetPurpose({data: {...S(r.session), role: 'USER'}});
  await svc.sessionConsent({data: {...S(r.session), consentRecord: {terms: {agreed: true, version: 'v1'}}}});
  await rejects(svc.sessionPrepareCertification({data: S(r.session)}), 'CONSENT_REQUIRED');
});

// ═══ AK-Q 역할 추가 ════════════════════════════════════════════════
cell('AK-Q1 역할 추가 = 새 KG → 별도 uid · 같은 identity · 로그인 시 역할 선택', async () => {
  const a = await fullSignup('9501', 'USER', 'imp-q1a');
  const st = await svc.sessionStartAddRole({auth: {uid: a.out.uid}, data: {role: 'BUSINESS_ADMIN'}});
  await svc.sessionConsent({data: {...S(st.session), consentRecord: CONSENT}});
  await toPass(st.session, 'imp-q1b');
  const b = await svc.completeSignup({data: S(st.session)});
  assert.notStrictEqual(b.uid, a.out.uid);
  const ident = F.get('identities/' + ciKeyOf('CI-PERSON-A'));
  assert.strictEqual(ident.roles.USER.uid, a.out.uid);
  assert.strictEqual(ident.roles.BUSINESS_ADMIN.uid, b.uid);
  assert.deepStrictEqual(F.get(`authSubjects/kakao_${APP}_9501`).roles, {USER: a.out.uid, BUSINESS_ADMIN: b.uid});
  const login = await svc.authKakao({data: {accessToken: kakaoUser('9501')}});
  assert.strictEqual(login.status, 'ROLE_SELECTION_REQUIRED');
  assert.deepStrictEqual(login.roles.sort(), ['BUSINESS_ADMIN', 'USER']);
  const l2 = await svc.authKakao({data: {accessToken: kakaoUser('9501'), role: 'BUSINESS_ADMIN'}});
  assert.strictEqual(l2.uid, b.uid);
});
cell('AK-Q2 같은 역할 추가 → ROLE_ALREADY_LINKED · 카카오 링크 없는 계정 → NO_PROVIDER_LINK', async () => {
  const a = await fullSignup('9502', 'USER', 'imp-q2');
  await rejects(svc.sessionStartAddRole({auth: {uid: a.out.uid}, data: {role: 'USER'}}), 'ROLE_ALREADY_LINKED');
  F.put('users/QA1', {role: 'USER', accountStatus: 'active', username: 'qa1'});
  await rejects(svc.sessionStartAddRole({auth: {uid: 'QA1'}, data: {role: 'BUSINESS_ADMIN'}}), 'NO_PROVIDER_LINK');
});
cell('AK-Q3 블랙 계정의 역할 추가 → ROLE_ADD_BLOCKED', async () => {
  const a = await fullSignup('9503', 'USER', 'imp-q3');
  F.put('users/' + a.out.uid, Object.assign(F.get('users/' + a.out.uid), {isBlacklisted: true}));
  await rejects(svc.sessionStartAddRole({auth: {uid: a.out.uid}, data: {role: 'BUSINESS_ADMIN'}}), 'ROLE_ADD_BLOCKED');
});
cell('AK-Q4 로그인 지정 역할이 연결 없음 → ROLE_NOT_LINKED', async () => {
  await fullSignup('9504', 'USER', 'imp-q4');
  const r = await svc.authKakao({data: {accessToken: kakaoUser('9504'), role: 'BUSINESS_ADMIN'}});
  assert.deepStrictEqual(r, {status: 'ROLE_NOT_LINKED', roles: ['USER']});
});

// ═══ AK-B 블랙·30일·삭제 경합 ═════════════════════════════════════
async function deleteAccount(uid, {blacklisted = false} = {}) {
  // index.ts 탈퇴 흐름의 새 identity 단계를 같은 순서로: freeze(슬롯 deleting) → Final 정리 → Auth 삭제 → 링크 정리
  if (blacklisted) {
    await F.db.runTransaction(async (tx) => {
      const ref = F.db.collection('users').doc(uid);
      const s = await tx.get(ref);
      const ap = await svc.blacklistReadInTx(tx, uid, s.data(), 'add');
      if (ap) ap(tx);
      tx.update(ref, {isBlacklisted: true});
    });
  }
  await F.db.runTransaction(async (tx) => {
    const ref = F.db.collection('users').doc(uid);
    const s = await tx.get(ref);
    const ap = await svc.freezeIdentityReadInTx(tx, uid, s.data());
    tx.set(F.db.collection('account_deletion_tombstones').doc(uid), {barrierAt: F.FieldValue.serverTimestamp()});
    tx.update(ref, {accountStatus: 'deleting'});
    if (ap) ap(tx);
  });
  const c = await svc.cleanupNewIdentityState(uid);
  assert.strictEqual(c.failed, 0);
  const res = await svc.countNewIdentityResidual(uid);
  assert.deepStrictEqual(res, {applicable: true, residual: 0, unknown: false});
  F.del('users/' + uid);
  AUTH.users.delete(uid);
  await svc.cleanupAfterAuthDeleted(uid);
}
cell('AK-B1 블랙 → 탈퇴 → 31일 뒤 재가입도 영구 차단(REREGISTER_BLACKLISTED)', async () => {
  const a = await fullSignup('9601', 'USER', 'imp-b1a');
  await deleteAccount(a.out.uid, {blacklisted: true});
  const r = F.get('identities/' + ciKeyOf('CI-PERSON-A')).restriction;
  assert.strictEqual(r.state, 'blacklisted');
  assert.strictEqual(r.permanent, true);
  NOW += 31 * DAY;
  const sess = await begin('9601');
  await toPass(sess, 'imp-b1b');
  await rejects(svc.completeSignup({data: S(sess)}), 'REREGISTER_BLACKLISTED');
});
cell('AK-B2 일반 탈퇴 → 정확 30일 경계(1ms 전 COOLDOWN · 정각 허용) · 새 uid', async () => {
  const a = await fullSignup('9602', 'USER', 'imp-b2a');
  const T = NOW;
  await deleteAccount(a.out.uid);
  NOW = T + 30 * DAY - 10 * MIN; // KG 30분 신선도 안에서 경계에 닿게
  const sess = await begin('9602');
  await toPass(sess, 'imp-b2b');
  NOW = T + 30 * DAY - 1;
  const e = await rejects(svc.completeSignup({data: S(sess)}), 'REREGISTER_COOLDOWN');
  assert.strictEqual(e.details.canReregisterAtMs, T + 30 * DAY);
  NOW = T + 30 * DAY;
  const out = await svc.completeSignup({data: S(sess)});
  assert.notStrictEqual(out.uid, a.out.uid, '삭제 UID 를 되살리면 안 된다');
  assert.strictEqual(F.get('identities/' + ciKeyOf('CI-PERSON-A')).restriction.state, 'none');
});
cell('AK-B3 탈퇴 freeze(슬롯 deleting) 중 같은 역할 가입 → IDENTITY_ROLE_DELETING', async () => {
  const a = await fullSignup('9603', 'USER', 'imp-b3a');
  await F.db.runTransaction(async (tx) => {
    const ref = F.db.collection('users').doc(a.out.uid);
    const s = await tx.get(ref);
    const ap = await svc.freezeIdentityReadInTx(tx, a.out.uid, s.data());
    tx.update(ref, {accountStatus: 'deleting'});
    if (ap) ap(tx);
  });
  // 같은 사람이 다른 카카오로 같은 역할 — 슬롯이 deleting 이면 점유로 본다.
  const sess = await begin('9604', 'USER');
  await toPass(sess, 'imp-b3b');
  await rejects(svc.completeSignup({data: S(sess)}), 'IDENTITY_ROLE_DELETING');
});
cell('AK-B4 활성 계정 블랙 → 같은 사람의 역할 추가 완료도 차단(identity 제한 즉시 반영)', async () => {
  const a = await fullSignup('9605', 'USER', 'imp-b4a');
  const st = await svc.sessionStartAddRole({auth: {uid: a.out.uid}, data: {role: 'BUSINESS_ADMIN'}});
  await svc.sessionConsent({data: {...S(st.session), consentRecord: CONSENT}});
  await toPass(st.session, 'imp-b4b');
  await F.db.runTransaction(async (tx) => {
    const ref = F.db.collection('users').doc(a.out.uid);
    const s = await tx.get(ref);
    const ap = await svc.blacklistReadInTx(tx, a.out.uid, s.data(), 'add');
    if (ap) ap(tx);
    tx.update(ref, {isBlacklisted: true});
  });
  await rejects(svc.completeSignup({data: S(st.session)}), 'REREGISTER_BLACKLISTED');
});
cell('AK-B5 블랙 로그인 → ACCOUNT_BLACKLISTED · 토큰 0', async () => {
  const a = await fullSignup('9606', 'USER', 'imp-b5');
  F.put('users/' + a.out.uid, Object.assign(F.get('users/' + a.out.uid), {isBlacklisted: true, blacklistReason: '사유'}));
  const tokBefore = GLOG.filter((g) => g[0] === 'createCustomToken').length;
  const e = await rejects(svc.authKakao({data: {accessToken: kakaoUser('9606')}}), 'ACCOUNT_BLACKLISTED');
  assert.strictEqual(e.details.blacklistReason, '사유');
  assert.strictEqual(GLOG.filter((g) => g[0] === 'createCustomToken').length, tokBefore);
});

// ═══ AK-X 탈퇴 재확인·삭제 재개 ═══════════════════════════════════
async function proveDeletion(uid, impUid, kgOver = {}) {
  const s = await svc.deletionReauthStart({auth: {uid}});
  kg(impUid, s.requestId, kgOver);
  return svc.verifyPassDeletion({auth: {uid}, data: {imp_uid: impUid}}, KEYS);
}
cell('AK-X1 카카오 계정 — proof 없으면 DELETION_REAUTH_REQUIRED · 옛 QA(링크 없음) 는 기존 auth_time 경로', async () => {
  const a = await fullSignup('9701', 'USER', 'imp-x1');
  await rejects(svc.assertDeletionProofIfProvider(a.out.uid), 'DELETION_REAUTH_REQUIRED');
  assert.strictEqual(await svc.assertDeletionProofIfProvider('QA_UID'), false);
  await rejects(svc.deletionReauthStart({auth: {uid: 'QA_UID'}}), 'NOT_PROVIDER_ACCOUNT');
});
cell('AK-X2 본인 KG 재확인 → proof 10분 · 경과 뒤 다시 필요 · 다른 사람 KG → IDENTITY_MISMATCH', async () => {
  const a = await fullSignup('9702', 'USER', 'imp-x2a');
  await rejects(proveDeletion(a.out.uid, 'imp-x2b', {unique_key: 'CI-PERSON-B'}), 'IDENTITY_MISMATCH');
  const ok = await proveDeletion(a.out.uid, 'imp-x2c');
  assert.strictEqual(ok.proven, true);
  assert.strictEqual(await svc.assertDeletionProofIfProvider(a.out.uid), true);
  NOW += 10 * MIN;
  await rejects(svc.assertDeletionProofIfProvider(a.out.uid), 'DELETION_REAUTH_REQUIRED');
});
cell('AK-X3 users 문서 없는 deleting(tombstone) → 카카오 로그인 = DELETION_RECOVERY(같은 uid · Auth 재생성 0)', async () => {
  const a = await fullSignup('9703', 'USER', 'imp-x3');
  F.put('account_deletion_tombstones/' + a.out.uid, {barrierAt: 1});
  F.del('users/' + a.out.uid);
  const r = await svc.authKakao({data: {accessToken: kakaoUser('9703')}});
  assert.strictEqual(r.status, 'DELETION_RECOVERY');
  assert.strictEqual(r.uid, a.out.uid);
  assert.strictEqual(GLOG.filter((g) => g[0] === 'createUser').length, 1);
});
cell('AK-X4 Final·Auth 삭제 뒤 로그인 → ACCOUNT_DELETED · 링크 정리 · 다음은 가입(30일 제한 유지)', async () => {
  const a = await fullSignup('9704', 'USER', 'imp-x4');
  await deleteAccount(a.out.uid);
  // 정상 Final 은 링크를 이미 정리 — 링크가 남은 경우(정리 실패) 도 흉내 낸다.
  F.put(`authLinks/kakao_${APP}_9704_USER`, {uid: a.out.uid, identityKey: ciKeyOf('CI-PERSON-A'),
    provider: 'kakao', appNs: APP, subject: '9704', role: 'USER'});
  F.put('account_deletion_tombstones/' + a.out.uid, {barrierAt: 1});
  await rejects(svc.authKakao({data: {accessToken: kakaoUser('9704')}}), 'ACCOUNT_DELETED');
  assert.ok(!F.has(`authLinks/kakao_${APP}_9704_USER`), '남은 링크를 정리해야 한다');
  const r = await svc.authKakao({data: {accessToken: kakaoUser('9704')}});
  assert.strictEqual(r.status, 'SIGNUP_REQUIRED');
  assert.strictEqual(GLOG.filter((g) => g[0] === 'createUser').length, 1, '삭제 UID 재생성 0');
});
cell('AK-X5 잔존 계수 — 정리 전 >0 · 정리 뒤 0 · 링크는 Auth 삭제 뒤까지 남는다', async () => {
  const a = await fullSignup('9705', 'USER', 'imp-x5');
  const before = await svc.countNewIdentityResidual(a.out.uid);
  assert.ok(before.residual > 0);
  await svc.cleanupNewIdentityState(a.out.uid);
  assert.strictEqual((await svc.countNewIdentityResidual(a.out.uid)).residual, 0);
  assert.ok(F.has(`authLinks/kakao_${APP}_9705_USER`), 'Auth 삭제 전 링크(삭제 재개 열쇠)가 사라졌다');
  assert.ok(!F.has(`authSubjects/kakao_${APP}_9705`));
});

// ═══ AK-L4 옛 QA 보존·미연결 ═════════════════════════════════════
cell('AK-L4 옛 QA(같은 이름·전화·ciHash) 와 연결 0 — 새 uid · QA 문서 무변경 (DEV 예외: 같은 사람 2계정 가능)', async () => {
  const qa = {role: 'USER', accountStatus: 'active', username: 'qa_user', name: '홍길동',
    phone: '01012345678', ciHash: 'legacysha', passVerifiedAt: 1};
  F.put('users/QA_OLD', qa);
  F.put('nativeIdentityFingerprints/legacysha_USER', {uid: 'QA_OLD', role: 'USER'});
  const {out} = await fullSignup('9801', 'USER', 'imp-l4');
  assert.notStrictEqual(out.uid, 'QA_OLD');
  assert.deepStrictEqual(F.get('users/QA_OLD'), qa);
  assert.deepStrictEqual(F.get('nativeIdentityFingerprints/legacysha_USER'), {uid: 'QA_OLD', role: 'USER'});
  const touched = F.W.reads.filter((r) => /nativeIdentityFingerprints|foreignIdFingerprints|deleted_accounts/.test(r.path));
  assert.deepStrictEqual(touched, [], '새 흐름이 옛 저장소를 읽었다');
});
cell('AK-M1 모의 모드(비 prod) — mock-kakao/mock-imp 로 가입 · evidence mock 표시 · prod 이름이면 거부', async () => {
  ENV.AUTH_MOCK_MODE = 'true';
  try {
    const r = await svc.authKakao({data: {accessToken: 'mock-kakao:4242'}});
    const sess = r.session;
    await svc.sessionSetPurpose({data: {...S(sess), role: 'USER'}});
    await svc.sessionConsent({data: {...S(sess), consentRecord: CONSENT}});
    await svc.sessionPrepareCertification({data: S(sess)});
    await svc.verifyPassSignup({data: {...S(sess), imp_uid: 'mock-imp:seedA'}}, KEYS);
    const out = await svc.completeSignup({data: S(sess)});
    assert.strictEqual(F.get('users/' + out.uid).identityEvidence, 'mock');
    ENV.GCLOUD_PROJECT = 'alfit-prod';
    await rejects(svc.authKakao({data: {accessToken: 'mock-kakao:4243'}}), 'AUTH_MOCK_FORBIDDEN');
  } finally {
    delete ENV.AUTH_MOCK_MODE; delete ENV.GCLOUD_PROJECT;
  }
});
cell('AK-M2 모의 증거 세션을 비모의 환경에서 완료 → MOCK_EVIDENCE_FORBIDDEN', async () => {
  ENV.AUTH_MOCK_MODE = 'true';
  let sess;
  try {
    const r = await svc.authKakao({data: {accessToken: 'mock-kakao:4244'}});
    sess = r.session;
    await svc.sessionSetPurpose({data: {...S(sess), role: 'USER'}});
    await svc.sessionConsent({data: {...S(sess), consentRecord: CONSENT}});
    await svc.sessionPrepareCertification({data: S(sess)});
    await svc.verifyPassSignup({data: {...S(sess), imp_uid: 'mock-imp:seedB'}}, KEYS);
  } finally { delete ENV.AUTH_MOCK_MODE; }
  await rejects(svc.completeSignup({data: S(sess)}), 'MOCK_EVIDENCE_FORBIDDEN');
});

(async () => {
  for (const [name, fn] of CELLS) {
    reset();
    try { await fn(); pass++; console.log('  ok   ' + name); } catch (e) {
      fails.push(`${name}: ${e.message}`);
      console.log('  FAIL ' + name + ' — ' + (e.stack || e.message).split('\n').slice(0, 3).join(' | '));
    }
  }
  console.log('─'.repeat(30));
  if (NET.length) { console.log('[차단] 외부 진입 시도: ' + NET.join(', ')); process.exitCode = 1; }
  if (fails.length) {
    console.log(`총 ${pass + fails.length}건 · 실패 ${fails.length}건 (모의 · PENDING VERIFICATION)`);
    process.exit(1);
  }
  console.log(`총 ${pass}건 · 실패 0건 (모의 · PENDING VERIFICATION)`);
})();
