/**
 * [ALFIT-AUTH-KAKAO-ONBOARDING.1 §6 · 판정278 §5] index.ts 원문 폐포 실행 — 옛 표면 처분 · 서버 세대 경계 ·
 * unknown 도달 consumer · 탈퇴/블랙 lifecycle 통합 · rules 계약.
 *
 *   실행:  npm --prefix functions run build && node --test --test-concurrency=1 test/auth_kakao_index_integration.test.js
 *   index.ts 의 해당 callable·helper 를 의존 폐포째 TS→JS 변환해 가짜 Firestore 위에서 실행한다
 *   (test/auth_kakao_index_harness.js). 네트워크·실제 Firestore·Auth·Storage 0 — 모의 · PENDING VERIFICATION.
 *
 *   묶음: IX-L 옛 표면 거절 · IX-C 세대 경계 · IX-U unknown 첫 서류/번호/계좌/이름/성별 ·
 *         IX-X 탈퇴 precondition/freeze · IX-B 블랙 writer · IX-G 지원/초대/재배치 gate · IX-R rules
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
const fs = require('fs');
const path = require('path');
const {createFakeFirestore} = require('./consent_r4d_fakestore');
const {loadIndexClosure} = require('./auth_kakao_index_harness');
const CORE = require(path.join(__dirname, '..', 'lib', 'signup_core.js'));

// 합성 비밀(모듈 평가 시점에 읽히는 상수) — 실제 값 아님.
process.env.FOREIGN_HMAC_SECRET = 'synthetic-foreign-hmac-secret-000';
process.env.TAX_ID_HMAC_SECRET = 'synthetic-tax-hmac-secret-0000000';
process.env.TAX_ID_ENCRYPT_KEY = Buffer.alloc(32, 7).toString('base64');
delete process.env.AUTH_MOCK_MODE;
delete process.env.PORTONE_IMP_KEY;
delete process.env.PORTONE_IMP_SECRET;

let NOW = Date.UTC(2026, 10, 25, 3, 0);
const RealDate = Date;
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
  'verifyPassAuth', 'finalizeRegistration', 'finalizePassReauth', 'recordDeletedAccount',
  'resetPasswordWithPass', 'callablePrecheckForeignIdentity', 'callableFinalizeForeignIdentity',
  'callableRecordTermsConsent', 'srvIsForeignIdentity', 'callableMarkIdCardVerified',
  'callableRegisterForeignIdDocument', 'callableUpdateBankAccount', 'srvValidateKoreanTaxIdentifierOrThrow',
  'callableRecoverForeignTaxIdentity', 'srvAssertAccountDeletionAllowed', 'srvEnsureAccountDeletionTombstone',
  'callableBlacklistUser', 'callableUnblacklistUser', 'callableAbortForeignRegistration',
  'callableSendOtpForPasswordReset', 'callableResetPasswordWithOtp', 'adminResetForeignPassword',
  'callableGetAccountDeletionRecoveryState', 'callableFindUsername',
];
const {exports: X, info} = loadIndexClosure(ROOTS, F, {HttpsError, console: QCON, Date: FakeDate});
console.log('[폐포] ' + info);

const SRC = fs.readFileSync(path.join(__dirname, '..', 'src', 'index.ts'), 'utf8');
const RULES = fs.readFileSync(path.join(__dirname, '..', '..', 'firestore.rules'), 'utf8');
const call = (fn, data, uid, token) => fn({data, auth: uid ? {uid, token: token || {}} : undefined});
async function rejects(p, pred, label) {
  try { await p; } catch (e) {
    const reason = e.details && e.details.reason;
    if (typeof pred === 'string') {
      assert.ok(reason === pred || String(e.message).startsWith(pred),
        `${label || ''} 기대 ${pred} · 실제 ${reason} / ${e.message}`);
    } else assert.ok(pred(e), `${label || ''} 실제 ${e.code} ${e.message}`);
    return e;
  }
  throw new Error(`${label || ''} 거절 기대 — 성공함`);
}

const APP = '111';
const KEY = 'ci1_' + 'a'.repeat(64);
const bd = (y, m, d) => new F.Ts(RealDate.UTC(y, m - 1, d));
function newUser(uid, o = {}) {
  F.put('users/' + uid, Object.assign({username: '', email: '', name: '홍길동', phone: '01012345678',
    role: 'USER', accountStatus: 'active', identityKey: KEY, identityEvidence: 'kg',
    passVerifiedAt: new F.Ts(NOW), nationalityStatus: 'unknown', authProviders: ['kakao'],
    signupSource: 'kakao_v1', birthDate: bd(1990, 1, 15), gender: '남성', isBlacklisted: false}, o));
  const linkId = `kakao_${APP}_${uid}sub_${o.role || 'USER'}`;
  F.put('authLinks/' + linkId, {uid, identityKey: KEY, provider: 'kakao', appNs: APP,
    subject: uid + 'sub', role: o.role || 'USER'});
  F.put(`authLinkOwners/${uid}_kakao`, {linkId});
  F.put('identities/' + KEY, {keyVersion: 1, roles: {[o.role || 'USER']: {uid, state: 'active', since: new F.Ts(NOW)}},
    restriction: {state: 'none'}, providerSubjects: {kakao: {appNs: APP, subject: uid + 'sub'}}});
}
function legacyUser(uid, o = {}) {
  F.put('users/' + uid, Object.assign({username: 'qa_' + uid, email: `qa_${uid}@alfit.local`, name: '김옛',
    phone: '01099998888', role: 'USER', accountStatus: 'active', ciHash: 'legacysha', passVerifiedAt: 1}, o));
}
const tokenFresh = () => ({auth_time: Math.floor(NOW / 1000) - 10});
const tokenStale = () => ({auth_time: Math.floor(NOW / 1000) - 3600});

const CELLS = [];
const cell = (n, fn) => CELLS.push([n, fn]);

// ═══ IX-L 옛 표면 ════════════════════════════════════════════════════
cell('IX-L1 verifyPassAuth 옛 목적 3개 거절 · 이 함수는 쓰기 0', async () => {
  await rejects(call(X.verifyPassAuth, {purpose: 'register', imp_uid: 'x'}), 'LEGACY_SIGNUP_CLOSED');
  await rejects(call(X.verifyPassAuth, {purpose: 'reauth', imp_uid: 'x'}, 'u1'), 'LEGACY_PASS_FLOW_CLOSED');
  await rejects(call(X.verifyPassAuth, {purpose: 'resetPassword', imp_uid: 'x'}), 'LEGACY_PASS_FLOW_CLOSED');
  await rejects(call(X.verifyPassAuth, {purpose: 'signup', sessionId: 's', secret: 'x', imp_uid: 'x'}),
    'PORTONE_NOT_CONFIGURED', 'PortOne 키 없음');
  assert.strictEqual(F.W.commits.length + F.W.direct.length, 0);
});
cell('IX-L2 닫힌 옛 writer 6개 — 직접 호출해도 거절 · 쓰기 0', async () => {
  legacyUser('QA1');
  F.put('passTokens/tok1', {purpose: 'register', ciHash: 'h', role: 'USER', expiresAt: new F.Ts(NOW + 1e6)});
  const before = F.dump();
  for (const [fn, reason] of [[X.finalizeRegistration, 'LEGACY_SIGNUP_CLOSED'], [X.finalizePassReauth, 'LEGACY_PASS_FLOW_CLOSED'],
    [X.recordDeletedAccount, 'LEGACY_SIGNUP_CLOSED'], [X.resetPasswordWithPass, 'LEGACY_PASS_FLOW_CLOSED'],
    [X.callablePrecheckForeignIdentity, 'LEGACY_SIGNUP_CLOSED'], [X.callableFinalizeForeignIdentity, 'LEGACY_SIGNUP_CLOSED']]) {
    await rejects(call(fn, {passToken: 'tok1', username: 'qa_QA1', rawForeignId: '9001155123456', role: 'USER'}, 'QA1'), reason);
  }
  assert.deepStrictEqual(F.dump(), before, '닫힌 writer 가 무언가를 썼다');
});
cell('IX-L3 RecordTermsConsent — 동의 기록은 유지 · 옛 pending→active 자동 전환 0', async () => {
  F.put('app_settings/legal_terms', {items: [{id: 'terms', version: 'v1', isRequired: true, isActive: true}]});
  F.put('users/PEND', {role: 'USER', accountStatus: 'registration_pending', foreignIdentityFingerprint: 'fp',
    idCardImagePath: 'users/PEND/idCard_1700000000001.jpg', isIdVerified: true, homeRegion: {city: '서울'}});
  const r = await call(X.callableRecordTermsConsent, {consentRecord: {terms: {agreed: true, version: 'v1'}}}, 'PEND');
  assert.strictEqual(r.success, true);
  const u = F.get('users/PEND');
  assert.ok(u.termsConsentAt, '동의 시각은 기록');
  assert.strictEqual(u.accountStatus, 'registration_pending', '옛 pending 이 active 로 올라갔다');
});
cell('IX-L4 가입 중단(abort) — tombstone UID · 카카오 계정은 거부(Storage·Auth 무접촉)', async () => {
  F.put('account_deletion_tombstones/T1', {barrierAt: 1});
  await rejects(call(X.callableAbortForeignRegistration, {}, 'T1'), (e) => e.code === 'failed-precondition');
  newUser('K1');
  await rejects(call(X.callableAbortForeignRegistration, {}, 'K1'), (e) => e.code === 'failed-precondition');
  assert.deepStrictEqual(F.STORAGE_CALLS, []);
  assert.ok(F.has('users/K1'));
});
cell('IX-L5 옛 비밀번호 복구(OTP·관리자) — 새 계정 대상 아님 · 빈 아이디 거부', async () => {
  newUser('K2', {username: 'planted', nationalityStatus: 'foreign', contactPhone: '01011112222'});
  await rejects(call(X.callableSendOtpForPasswordReset, {username: 'planted'}), (e) => e.code === 'permission-denied');
  await rejects(call(X.callableResetPasswordWithOtp, {username: 'planted', code: '123456'}), (e) => e.code === 'permission-denied');
  await rejects(call(X.callableResetPasswordWithOtp, {username: '   ', code: '123456'}), (e) => e.code === 'invalid-argument');
  F.put('users/SA', {role: 'SUPER_ADMIN', accountStatus: 'active'});
  await rejects(call(X.adminResetForeignPassword, {userId: 'K2'}, 'SA'), (e) => /비밀번호가 없습니다/.test(e.message));
  assert.ok(!F.has('sms_verifications/01011112222'));
});

// ═══ IX-C 서버 세대 경계 ════════════════════════════════════════════
cell('IX-C1 srvIsForeignIdentity — 옛 계정 판정 불변 · 새 계정은 서버 분류만(심은 foreignIdNumber 무시)', async () => {
  assert.strictEqual(X.srvIsForeignIdentity({foreignIdentityFingerprint: 'fp'}), true);
  assert.strictEqual(X.srvIsForeignIdentity({foreignIdNumber: '900115-5******'}), true);
  assert.strictEqual(X.srvIsForeignIdentity({ciHash: 'x'}), false);
  assert.strictEqual(X.srvIsForeignIdentity({signupSource: 'kakao_v1', nationalityStatus: 'unknown',
    foreignIdNumber: 'planted'}), false);
  assert.strictEqual(X.srvIsForeignIdentity({signupSource: 'kakao_v1', nationalityStatus: 'foreign'}), true);
  assert.strictEqual(X.srvIsForeignIdentity({signupSource: 'kakao_v1', nationalityStatus: 'domestic'}), false);
});
cell('IX-C2 아이디 찾기 — 카카오 계정은 아이디 대신 역할만(providerAccounts)', async () => {
  newUser('K3', {name: '이카카', phone: '01033334444'});
  legacyUser('Q3', {name: '이카카', phone: '01033334444'});
  const r = await call(X.callableFindUsername, {name: '이카카', phone: '01033334444'});
  assert.deepStrictEqual(r.accounts, [{username: 'qa_Q3', role: 'USER'}]);
  assert.deepStrictEqual(r.providerAccounts, [{provider: 'kakao', role: 'USER'}]);
});
cell('IX-C3 삭제 재개 상태 — reauthMethod(문서 없어도 링크로 판별)', async () => {
  newUser('K4');
  F.del('users/K4');
  F.put('account_deletion_tombstones/K4', {barrierAt: 1});
  const r = await call(X.callableGetAccountDeletionRecoveryState, {}, 'K4');
  assert.deepStrictEqual(r, {deletionInProgress: true, userDocExists: false, accountStatus: null, reauthMethod: 'kakao_kg'});
  legacyUser('Q4');
  assert.strictEqual((await call(X.callableGetAccountDeletionRecoveryState, {}, 'Q4')).reauthMethod, 'password');
});

// ═══ IX-U unknown 도달 consumer ═════════════════════════════════════
const RAW_FOREIGN = '9001155123456';
cell('IX-U1 첫 신분증 제출 — unknown+종류 없음 거부 · 외국인등록증은 등록번호 먼저 · 거부 시 업로드 정리', async () => {
  newUser('U1');
  const p = 'users/U1/idCard_1700000000001.jpg';
  await rejects(call(X.callableMarkIdCardVerified, {storagePath: p, attemptSeq: 1}, 'U1'), 'DOCUMENT_KIND_REQUIRED');
  await rejects(call(X.callableMarkIdCardVerified, {storagePath: p, attemptSeq: 1, documentKind: 'foreign_registration'}, 'U1'),
    'FOREIGN_ID_DOCUMENT_REQUIRED');
  assert.strictEqual(F.get('users/U1').nationalityStatus, 'unknown');
  assert.ok(!('idCardImagePath' in F.get('users/U1')));
  // 거부된 업로드 정리 시도(srvDeleteOrQueueOrphan) — 가짜 Storage 에 getMetadata 가 없어 실제 삭제까지는
  //   이 시험 범위 밖이다(그 helper 자체는 기존 시험 대상). 시도했다는 것만 본다.
  assert.ok(LOGS.some((l) => l.includes('[orphan]')), '거부된 업로드 정리를 시도하지 않았다');
});
cell('IX-U2 첫 신분증 제출 — 주민등록증 선택 → 국내 후보필터 + 커밋 시 domestic(신고 서류 출처)', async () => {
  newUser('U2');
  try {
    await call(X.callableMarkIdCardVerified, {storagePath: 'users/U2/idCard_1700000000001.jpg', attemptSeq: 1,
      documentKind: 'resident_id', selfCheck: {name: 'MATCHED', identifierCandidates: ['9001151234567']}}, 'U2');
  } catch (e) { /* 커밋 뒤 Storage 확정 단계는 가짜 Storage 범위 밖 — 커밋 결과만 본다 */ }
  const u = F.get('users/U2');
  assert.strictEqual(u.nationalityStatus, 'domestic');
  assert.strictEqual(u.nationalitySource, 'id_document_declared');
  assert.strictEqual(u.idCardImagePath, 'users/U2/idCard_1700000000001.jpg');
});
// [server_296 · AUD-6 후보] 0바이트 신분증 객체는 '정상 업로드'로 인정하지 않는다(크기가 확실히 0 일 때만 · 메타 모르면 기존 동작).
cell('IX-U2b 0바이트 신분증 — ID_CARD_EMPTY · 저장 0', async () => {
  newUser('U2B');
  const orig = F.admin.storage;
  F.admin.storage = () => ({bucket: () => ({name: 'fake-bucket', file: (p) => ({name: p,
    exists: async () => [true], getMetadata: async () => [{size: '0'}], setMetadata: async () => [],
    delete: async () => [], getSignedUrl: async () => ['https://fake/' + p]})})});
  try {
    await rejects(call(X.callableMarkIdCardVerified, {storagePath: 'users/U2B/idCard_1700000000001.jpg', attemptSeq: 1,
      documentKind: 'resident_id'}, 'U2B'), (e) => e.details && e.details.code === 'ID_CARD_EMPTY');
  } finally { F.admin.storage = orig; }
  assert.ok(!F.get('users/U2B').idCardImagePath, '빈 파일로 신분증 경로를 기록하면 안 된다');
});
cell('IX-U3 옛 계정 — 종류 입력 무시, 기존 fingerprint 기준 그대로', async () => {
  legacyUser('Q5', {foreignIdentityFingerprint: 'fpX'});
  try {
    await call(X.callableMarkIdCardVerified, {storagePath: 'users/Q5/idCard_1700000000001.jpg', attemptSeq: 1,
      documentKind: 'resident_id'}, 'Q5');
  } catch (e) { /* 위와 같음 */ }
  const u = F.get('users/Q5');
  assert.strictEqual(u.idCardImagePath, 'users/Q5/idCard_1700000000001.jpg');
  assert.ok(!('nationalityStatus' in u), '옛 계정에 분류 필드를 쓰면 안 된다');
});
cell('IX-U4 외국인등록증 최초 등록 — foreign 분류 · 옛 sentinel/지문 0 · 13자리 원문 저장 0', async () => {
  newUser('U4');
  const r = await call(X.callableRegisterForeignIdDocument, {rawForeignId: RAW_FOREIGN, legalName: 'HONG GILDONG',
    koreanName: '홍길동', visaType: 'E-9', stayExpiryDate: '2028-01-01'}, 'U4');
  assert.deepStrictEqual(r, {success: true, nationalityStatus: 'foreign'});
  const u = F.get('users/U4');
  assert.strictEqual(u.nationalityStatus, 'foreign');
  assert.strictEqual(u.nationalitySource, 'foreign_id_document');
  assert.ok(typeof u.foreignIdDocumentFingerprint === 'string' && u.foreignIdDocumentFingerprint.length === 64);
  assert.ok(!('foreignIdentityFingerprint' in u), '옛 가입 지문 필드를 쓰면 안 된다');
  assert.strictEqual(u.legalName, 'HONG GILDONG');
  assert.strictEqual(u.koreanName, '홍길동');
  assert.strictEqual(u.name, '홍길동', 'KG 이름(name) 은 그대로 — 이름 3종 독립');
  assert.ok(!Object.keys(F.dump()).some((k) => k.startsWith('foreignIdFingerprints/')));
  assert.ok(!JSON.stringify(F.dump()).includes(RAW_FOREIGN), '13자리 원문이 저장됐다');
  assert.ok(!LOGS.join('\n').includes(RAW_FOREIGN), '13자리 원문이 로그에 남았다');
  assert.strictEqual(X.srvIsForeignIdentity(u), true);
});
cell('IX-U5 등록증 생년 ≠ KG 생년 → FOREIGN_ID_BIRTHDATE_MISMATCH · 성별 불일치 → FOREIGN_ID_GENDER_MISMATCH', async () => {
  newUser('U5');
  await rejects(call(X.callableRegisterForeignIdDocument, {rawForeignId: '9101155123456'}, 'U5'), 'FOREIGN_ID_BIRTHDATE_MISMATCH');
  await rejects(call(X.callableRegisterForeignIdDocument, {rawForeignId: '9001156123456'}, 'U5'), 'FOREIGN_ID_GENDER_MISMATCH');
  assert.strictEqual(F.get('users/U5').nationalityStatus, 'unknown');
  legacyUser('Q6');
  await rejects(call(X.callableRegisterForeignIdDocument, {rawForeignId: RAW_FOREIGN}, 'Q6'), 'LEGACY_ACCOUNT');
});
cell('IX-U6 KG 성별 누락 → 등록번호에서 보완 + 기준 표시(FOREIGN_IDENTITY) · 여성 폴백 0', async () => {
  newUser('U6', {gender: undefined});
  const u0 = F.get('users/U6'); delete u0.gender; F.put('users/U6', u0);
  await call(X.callableRegisterForeignIdDocument, {rawForeignId: RAW_FOREIGN}, 'U6');
  const u = F.get('users/U6');
  assert.strictEqual(u.gender, '남성');
  assert.strictEqual(u.identityBasisSource, 'FOREIGN_IDENTITY');
});
cell('IX-U7 외국인 분류 뒤 등록증 사진 제출 — 종류 일치면 통과(5–8 필터) · 주민등록증 선택은 불일치', async () => {
  newUser('U7', {nationalityStatus: 'foreign'});
  await rejects(call(X.callableMarkIdCardVerified, {storagePath: 'users/U7/idCard_1700000000001.jpg', attemptSeq: 1,
    documentKind: 'resident_id'}, 'U7'), 'DOCUMENT_KIND_MISMATCH');
  try {
    await call(X.callableMarkIdCardVerified, {storagePath: 'users/U7/idCard_1700000000002.jpg', attemptSeq: 2,
      documentKind: 'foreign_registration'}, 'U7');
  } catch (e) { /* 커밋 뒤 단계 */ }
  assert.strictEqual(F.get('users/U7').idCardImagePath, 'users/U7/idCard_1700000000002.jpg');
});
cell('IX-U8 unknown 계좌 등록 → NATIONALITY_UNCONFIRMED(내국 예금주 기본값 0) · 세무 국내 번호 → 같은 거절', async () => {
  newUser('U8');
  await rejects(call(X.callableUpdateBankAccount, {bankName: '국민', accountNumber: '123-456'}, 'U8'), 'NATIONALITY_UNCONFIRMED');
  assert.ok(!('bankName' in F.get('users/U8')));
  await rejects(X.srvValidateKoreanTaxIdentifierOrThrow('9001151234567', F.get('users/U8')), 'NATIONALITY_UNCONFIRMED');
});
cell('IX-U9 새 외국인 최초 세무 등록 ≠ 옛 fingerprint 복구 — 등록증 서류 지문으로 회복 경로', async () => {
  F.put('app_settings/tax_identity_collection', {enabled: true});
  newUser('U9');
  await call(X.callableRegisterForeignIdDocument, {rawForeignId: RAW_FOREIGN}, 'U9');
  const tax = F.get('taxIdentities/U9');
  assert.strictEqual(tax.registrationSource, 'FOREIGN_ID_DOCUMENT', '수집 ON 이면 등록증과 함께 세무 등록');
  F.del('taxIdentities/U9');
  await rejects(call(X.callableRecoverForeignTaxIdentity, {rawForeignIdentifier: '9001155654321'}, 'U9'),
    (e) => /가입 시 등록한 번호와 다릅니다/.test(e.message));
  const r = await call(X.callableRecoverForeignTaxIdentity, {rawForeignIdentifier: RAW_FOREIGN}, 'U9');
  assert.ok(r && F.has('taxIdentities/U9'));
});

// ═══ IX-X 탈퇴 ═════════════════════════════════════════════════════
cell('IX-X1 카카오 계정 탈퇴 precondition — 갓 받은 custom token(auth_time) 만으로 통과 0 · proof 10분이면 통과', async () => {
  newUser('X1');
  await rejects(X.srvAssertAccountDeletionAllowed('X1', tokenFresh()), 'DELETION_REAUTH_REQUIRED');
  F.put('deletionReauthProofs/X1', {proof: {ciKey: KEY, expiresAt: new F.Ts(NOW + 5 * 60e3)}});
  await X.srvAssertAccountDeletionAllowed('X1', tokenStale());
  F.put('deletionReauthProofs/X1', {proof: {ciKey: 'ci1_' + 'b'.repeat(64), expiresAt: new F.Ts(NOW + 5 * 60e3)}});
  await rejects(X.srvAssertAccountDeletionAllowed('X1', tokenFresh()), 'DELETION_REAUTH_REQUIRED', '다른 사람 증명');
});
cell('IX-X2 옛 QA(비밀번호) 탈퇴 precondition — 기존 auth_time 10분 규칙 그대로', async () => {
  legacyUser('Q7');
  await X.srvAssertAccountDeletionAllowed('Q7', tokenFresh());
  await rejects(X.srvAssertAccountDeletionAllowed('Q7', tokenStale()), (e) => /재인증 후 10분/.test(e.message));
});
cell('IX-X3 탈퇴 freeze — 같은 거래에서 identity 역할 슬롯 deleting(+동결 시점 블랙 기록)', async () => {
  newUser('X3', {isBlacklisted: true});
  assert.strictEqual(await X.srvEnsureAccountDeletionTombstone('X3'), true);
  const ident = F.get('identities/' + KEY);
  assert.strictEqual(ident.roles.USER.state, 'deleting');
  assert.strictEqual(ident.roles.USER.blacklistedAtFreeze, true);
  assert.strictEqual(F.get('users/X3').accountStatus, 'deleting');
  const tx = F.W.commits.find((c) => c.writes.some((w) => w.path === 'account_deletion_tombstones/X3'));
  assert.ok(tx.writes.some((w) => w.path === 'identities/' + KEY), 'freeze 와 슬롯이 다른 거래다');
});

// ═══ IX-B 블랙 writer ═══════════════════════════════════════════════
cell('IX-B1 블랙 등록 → identity 제한 같은 거래 · 해제 → 그 uid 만 빠짐', async () => {
  F.put('users/SA', {role: 'SUPER_ADMIN', accountStatus: 'active'});
  newUser('B1');
  await call(X.callableBlacklistUser, {targetUid: 'B1', blacklistReason: '사유'}, 'SA');
  let r = F.get('identities/' + KEY).restriction;
  assert.strictEqual(r.state, 'blacklisted');
  assert.deepStrictEqual(r.blacklistedUids, ['B1']);
  assert.strictEqual(CORE.restrictionVerdict(CORE.normalizeRestriction(r), NOW).kind, 'BLACKLISTED');
  const tx = F.W.commits.find((c) => c.writes.some((w) => w.path === 'users/B1'));
  assert.ok(tx.writes.some((w) => w.path === 'identities/' + KEY));
  await call(X.callableUnblacklistUser, {targetUid: 'B1'}, 'SA');
  r = F.get('identities/' + KEY).restriction;
  assert.strictEqual(r.state, 'none');
  assert.strictEqual(F.get('users/B1').isBlacklisted, false);
});
cell('IX-B2 옛 QA 블랙 — identity 쓰기 0(옛 cohort 에 새 identity 발급 0)', async () => {
  F.put('users/SA', {role: 'SUPER_ADMIN', accountStatus: 'active'});
  legacyUser('Q8');
  await call(X.callableBlacklistUser, {targetUid: 'Q8', blacklistReason: '사유'}, 'SA');
  assert.ok(!Object.keys(F.dump()).some((k) => k.startsWith('identities/')));
});

// ═══ IX-G 지원·초대·재배치 gate(원문 위치) ════════════════════════
cell('IX-G1 지원·초대 수락·재배치 수락 — 신분증 검사 뒤 NATIONALITY_UNCONFIRMED · PASS gate 는 그대로', async () => {
  const body = (name) => {
    const i = SRC.indexOf('export const ' + name + ' = onCall(');
    const j = SRC.indexOf('\nexport const ', i + 10);
    return SRC.slice(i, j);
  };
  for (const [name, anchor] of [
    ['callableApplyToTO', '"본인인증 후 지원할 수 있습니다. 설정 > 본인인증에서 완료해주세요."'],
    ['callableAcceptTOInvitation', '"신분증 등록이 필요합니다."'],
    ['callableAcceptConfirmedReassignment', '"신분증 인증 후 수락할 수 있습니다."'],
  ]) {
    const b = body(name);
    const a = b.indexOf(anchor);
    const g = b.indexOf('NATIONALITY_UNCONFIRMED');
    assert.ok(a > 0 && g > a, `${name}: gate 가 없거나 신분증/PASS 검사 앞이다`);
  }
});

// ═══ IX-R rules 계약 ════════════════════════════════════════════════
const block = (header) => {
  const i = RULES.indexOf(header);
  assert.ok(i >= 0, header);
  return RULES.slice(i, RULES.indexOf('\n    }', i));
};
cell('IX-R1 users create 전면 거부 — 클라 가입·계좌 3필드 create(K8)·tombstone uid 재생성 함께 종결', async () => {
  const u = RULES.slice(RULES.indexOf('match /users/{userId} {'), RULES.indexOf('match /notifications/{notificationId}', RULES.indexOf('match /users/{userId} {')));
  const creates = u.split('\n').filter((l) => /^\s*allow create/.test(l));
  assert.deepStrictEqual(creates.map((l) => l.trim()), ['allow create: if false;']);
});
cell('IX-R2 새 컬렉션 7개 — 클라 read/write 0 명시', async () => {
  for (const c of ['identities/{ciKey}', 'authLinks/{linkId}', 'authLinkOwners/{ownerId}', 'authSubjects/{subjectId}',
    'signupSessions/{sessionId}', 'passCertifications/{certId}', 'deletionReauthProofs/{uid}']) {
    const b = block(`match /${c} {`);
    assert.ok(/allow read, write: if false;/.test(b), c);
    assert.ok(!/allow (read|write|create|update|delete|get|list): if (?!false)/.test(b), c);
  }
});
cell('IX-R3 users update denylist(본인·SUPER_ADMIN) — 세대·신원 키·서류 분류 필드 CF 전용', async () => {
  const u = RULES.slice(RULES.indexOf('match /users/{userId} {'), RULES.indexOf('match /notifications/{notificationId}', RULES.indexOf('match /users/{userId} {')));
  const updates = u.split('allow update:').slice(1);
  const sa = updates.find((x) => (x.trimStart().startsWith('if isSuperAdmin()') ||
    x.trimStart().startsWith('if callerNotDeleting() && (isSuperAdmin()')));
  const own = updates.find((x) => x.includes('isOwner(userId) &&') && x.includes("'ciHash'"));
  for (const f of ['signupSource', 'identityKey', 'identityEvidence', 'nationalityStatus', 'nationalitySource',
    'nationalityAt', 'authProviders', 'signupCompletedAt', 'authProvisionedAt', 'foreignIdDocumentFingerprint']) {
    assert.ok(sa && sa.includes(`'${f}'`), `SUPER_ADMIN denylist 에 ${f} 없음`);
    assert.ok(own && own.includes(`'${f}'`), `본인 denylist 에 ${f} 없음`);
  }
});

cell('IX-R4 새 계정 — 본인 username/email 쓰기 0 · SUPER_ADMIN 클라 문서 삭제 0(탈퇴 흐름만)', async () => {
  const u = RULES.slice(RULES.indexOf('match /users/{userId} {'), RULES.indexOf('match /notifications/{notificationId}',
    RULES.indexOf('match /users/{userId} {')));
  assert.ok(/resource\.data\.get\('signupSource', null\) == null \|\|\s*!request\.resource\.data\.diff\(resource\.data\)\.affectedKeys\(\)\s*\.hasAny\(\['username', 'email'\]\)\)\)?;/.test(u),
    'username/email 조건 없음');
  // [판정281] 쓰기 규칙 전부가 callerNotDeleting() && ( … ) 로 감싸졌다 — 원래 조건은 그대로 안에 있다.
  assert.ok(/allow delete: if (?:callerNotDeleting\(\) && \()?isSuperAdmin\(\) && request\.auth\.uid != userId &&\s*!accountDeletionBarrierExists\(userId\) &&[\s\S]*?resource\.data\.get\('signupSource', null\) == null\)?;/.test(u),
    'SA 삭제 조건 없음');
});

(async () => {
  let pass = 0;
  const fails = [];
  for (const [name, fn] of CELLS) {
    F.reset(); LOGS.length = 0; NOW = Date.UTC(2026, 10, 25, 3, 0);
    try { await fn(); pass++; console.log('  ok   ' + name); } catch (e) {
      fails.push(name);
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
