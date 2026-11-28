/**
 * [ALFIT-AUTH-KAKAO-ONBOARDING.1] signup_core 순수 판정 — 컴파일된 원문(lib/signup_core.js)을 그대로 돌린다.
 *
 *   실행:  npm --prefix functions run build && node --test --test-concurrency=1 test/signup_core_pure.test.js
 *   네트워크 0 · Firestore 0. 모의/합성 입력만 쓴다(PENDING VERIFICATION 대상 아님 — 순수 계약).
 *
 *   묶음: SC-R* 재가입 제한 · SC-V* 계정 상태 판정 · SC-K* KG 응답/결합 · SC-I* 신원 키 ·
 *         SC-U* 새 users allowlist · SC-D* 서류 종류(unknown) · SC-S* 세션 secret
 */
'use strict';
const assert = require('assert');
const path = require('path');
const crypto = require('crypto');
const C = require(path.join(__dirname, '..', 'lib', 'signup_core.js'));

let pass = 0;
const fails = [];
function t(name, fn) {
  try { fn(); pass++; console.log('  ok   ' + name); } catch (e) { fails.push(`${name}: ${e.message}`); console.log('  FAIL ' + name + ' — ' + e.message); }
}
const DAY = 24 * 3600e3;
const T0 = Date.UTC(2026, 10, 25, 3, 0); // KST 2026-11-25 12:00

// ── 재가입 제한 ─────────────────────────────────────────────────────────
t('SC-R1 블랙 계정이 탈퇴하면 영구(permanent) — 일반 탈퇴 기록에 가려지지 않는다', () => {
  let r = C.normalizeRestriction(undefined);
  r = C.restrictionAfterBlacklist(r, 'uA', T0);
  r = C.restrictionAfterDeletion(r, {uid: 'uA', wasBlacklisted: false, baseMs: T0, nowMs: T0});
  assert.strictEqual(r.state, 'blacklisted');
  assert.strictEqual(r.permanent, true);
  // 이후 같은 사람의 다른 역할 일반 탈퇴 — 블랙은 내려가지 않는다.
  r = C.restrictionAfterDeletion(C.normalizeRestriction(C.restrictionForStore(r)),
    {uid: 'uB', wasBlacklisted: false, baseMs: T0 + DAY, nowMs: T0 + DAY});
  assert.strictEqual(r.state, 'blacklisted');
  assert.strictEqual(C.restrictionVerdict(r, T0 + 400 * DAY).kind, 'BLACKLISTED');
});
t('SC-R2 정확 30일 경계 — 해제 시각 1ms 전은 COOLDOWN, 정각은 OK', () => {
  const r = C.restrictionAfterDeletion(C.normalizeRestriction(null),
    {uid: 'u', wasBlacklisted: false, baseMs: T0, nowMs: T0});
  assert.strictEqual(r.canReregisterAtMs, T0 + 30 * DAY);
  assert.strictEqual(C.restrictionVerdict(r, T0 + 30 * DAY - 1).kind, 'COOLDOWN');
  assert.strictEqual(C.restrictionVerdict(r, T0 + 30 * DAY).kind, 'OK');
});
t('SC-R3 cooldown 연장은 max — 더 늦은 기존 해제 시각을 당기지 않는다', () => {
  const prev = {state: 'cooldown', canReregisterAtMs: T0 + 50 * DAY, blacklistedUids: []};
  const r = C.restrictionAfterDeletion(prev, {uid: 'u2', wasBlacklisted: false, baseMs: T0, nowMs: T0});
  assert.strictEqual(r.canReregisterAtMs, T0 + 50 * DAY);
});
t('SC-R4 블랙 해제는 그 uid 만 — 영구·다른 계정 블랙은 남는다', () => {
  let r = C.restrictionAfterBlacklist({state: 'none'}, 'u1', T0);
  r = C.restrictionAfterBlacklist(r, 'u2', T0);
  r = C.restrictionAfterUnblacklist(r, 'u1', T0);
  assert.strictEqual(r.state, 'blacklisted');
  r = C.restrictionAfterUnblacklist(r, 'u2', T0);
  assert.strictEqual(r.state, 'none');
  const perm = {state: 'blacklisted', permanent: true, blacklistedUids: ['u3']};
  assert.strictEqual(C.restrictionAfterUnblacklist(perm, 'u3', T0).state, 'blacklisted');
});
t('SC-R5 모르는 모양의 제한 기록은 블랙으로 읽는다(fail-closed)', () => {
  assert.strictEqual(C.normalizeRestriction('x').state, 'blacklisted');
  assert.strictEqual(C.normalizeRestriction({state: 'weird'}).state, 'blacklisted');
  assert.strictEqual(C.normalizeRestriction({state: 'cooldown'}).state, 'blacklisted', '해제 시각 없는 cooldown');
  assert.strictEqual(C.normalizeRestriction({state: 'none'}).state, 'none');
});
t('SC-R6 해제 뒤 남은 미래 cooldown 은 유지', () => {
  const r = C.restrictionAfterUnblacklist({state: 'blacklisted', blacklistedUids: ['u'],
    canReregisterAtMs: T0 + DAY}, 'u', T0);
  assert.strictEqual(r.state, 'cooldown');
});

// ── 계정 상태 판정(K7) ─────────────────────────────────────────────────
t('SC-V1 tombstone/deleting 은 막지 않고 삭제 재개로', () => {
  assert.strictEqual(C.accountStateVerdict(undefined, true, T0).kind, 'DELETION_RECOVERY');
  assert.strictEqual(C.accountStateVerdict({accountStatus: 'deleting', isBlacklisted: true}, false, T0).kind,
    'DELETION_RECOVERY');
});
t('SC-V2 블랙 · 거절 · 제재 · 미완료 — 아이디 로그인(AS:113-158)과 같은 분류', () => {
  assert.deepStrictEqual(C.accountStateVerdict({isBlacklisted: true, accountStatus: 'active'}, false, T0),
    {kind: 'BLOCKED_BLACKLIST', reason: '이용 정책 위반'});
  assert.strictEqual(C.accountStateVerdict({accountStatus: 'rejected'}, false, T0).kind, 'REJECTED');
  assert.strictEqual(C.accountStateVerdict({accountStatus: 'pending'}, false, T0).kind, 'INCOMPLETE_LEGACY');
  assert.strictEqual(C.accountStateVerdict({accountStatus: 'registration_pending'}, false, T0).kind, 'INCOMPLETE_LEGACY');
  const v = C.accountStateVerdict({accountStatus: 'active', restrictedUntil: {toMillis: () => T0 + 1},
    restrictionSource: 'auto'}, false, T0);
  assert.strictEqual(v.kind, 'RESTRICTED');
  assert.strictEqual(C.accountStateVerdict({accountStatus: 'active', restrictedUntil: {toMillis: () => T0}},
    false, T0).kind, 'OK', '해제 시각 정각이면 OK');
});

// ── KG 응답 ───────────────────────────────────────────────────────────
const RES = (o) => ({code: 0, response: Object.assign({certified: true, unique_key: 'SYNTH-CI-1',
  name: ' 홍길동 ', birthday: '1990-01-15', phone: '010-1234-5678', gender: 'male',
  merchant_uid: 'req1', certified_at: Math.floor(T0 / 1000), pg_provider: 'inicis_unified'}, o)});
t('SC-K1 엄격 해석 — 정상 · 이름/전화 정규화 · 성별', () => {
  const p = C.parsePortOneCertification(RES({}));
  assert.ok(p.ok);
  assert.strictEqual(p.cert.name, '홍길동');
  assert.strictEqual(p.cert.phone, '01012345678');
  assert.strictEqual(p.cert.birthDate, '19900115');
  assert.strictEqual(p.cert.gender, '남성');
});
t('SC-K2 CI 없음 = 실패(DEV 전화 대체 없음) · certified 비 boolean = 실패', () => {
  assert.deepStrictEqual(C.parsePortOneCertification(RES({unique_key: ''})), {ok: false, reason: 'KG_CI_MISSING'});
  assert.deepStrictEqual(C.parsePortOneCertification(RES({unique_key: undefined})), {ok: false, reason: 'KG_CI_MISSING'});
  assert.deepStrictEqual(C.parsePortOneCertification(RES({certified: 'true'})), {ok: false, reason: 'KG_NOT_CERTIFIED'});
  assert.deepStrictEqual(C.parsePortOneCertification(RES({certified: 1})), {ok: false, reason: 'KG_NOT_CERTIFIED'});
  assert.deepStrictEqual(C.parsePortOneCertification(RES({birthday: '1990'})), {ok: false, reason: 'KG_DATA_INCOMPLETE'});
});
t('SC-K3 성별 미제공·모름은 null — 여성 폴백 금지(K4)', () => {
  for (const g of [undefined, null, '', 'unknown', 'F']) {
    const p = C.parsePortOneCertification(RES({gender: g}));
    assert.strictEqual(p.ok && p.cert.gender, null, String(g));
  }
  assert.strictEqual(C.parsePortOneCertification(RES({gender: 'female'})).cert.gender, '여성');
});
t('SC-K4 결합 — merchant_uid=서버 requestId · certified_at 창 · 없으면 통과로 쓰지 않음', () => {
  const c = C.parsePortOneCertification(RES({})).cert;
  const want = {requestId: 'req1', issuedAtMs: T0 - 60e3, nowMs: T0 + 60e3};
  assert.strictEqual(C.checkKgBinding(c, want).ok, true);
  assert.strictEqual(C.checkKgBinding({...c, merchantUid: 'other'}, want).ok, false);
  assert.strictEqual(C.checkKgBinding({...c, merchantUid: null}, want).ok, false, 'merchant_uid 없음');
  assert.strictEqual(C.checkKgBinding({...c, certifiedAtMs: null}, want).ok, false, 'certified_at 없음');
  assert.strictEqual(C.checkKgBinding({...c, certifiedAtMs: T0 - 3600e3}, want).ok, false, '발급 전 인증');
  assert.strictEqual(C.checkKgBinding(c, {...want, pgProvider: 'other'}).ok, false, 'PG 불일치');
  assert.strictEqual(C.checkKgBinding(c, want).pgCheck, 'unchecked', 'PG 설정 없으면 미대조 기록');
});
t('SC-K5 만 19세(KST) 경계', () => {
  assert.strictEqual(C.ageKst('20071125', T0), 19);
  assert.strictEqual(C.ageKst('20071126', T0), 18);
  assert.strictEqual(C.ageKst('bad', T0), -1);
});

// ── 신원 키 ───────────────────────────────────────────────────────────
t('SC-I1 ci1_ + HMAC(key, 용도 접두 + CI) — 무키 SHA·등록번호 HMAC 과 다르다', () => {
  const key = 'k'.repeat(32);
  const k = C.computeCiKeyV1(key, 'CI-X');
  assert.strictEqual(k, 'ci1_' + crypto.createHmac('sha256', key).update('alfit:identity:ci:v1:CI-X').digest('hex'));
  assert.ok(C.isCiKeyV1(k));
  assert.notStrictEqual(k.slice(4), crypto.createHash('sha256').update('CI-X').digest('hex'));
  assert.notStrictEqual(k.slice(4), crypto.createHmac('sha256', key).update('CI-X').digest('hex'));
  assert.throws(() => C.computeCiKeyV1('', 'CI-X'), /CI_KEY_UNAVAILABLE/);
  assert.throws(() => C.computeCiKeyV1(key, ''), /KG_CI_MISSING/);
});
t('SC-I2 문서 id 조각 검증 — 경로 주입 거부', () => {
  for (const bad of ['', 'a/b', '..', 'a b', 'x'.repeat(129), 1]) assert.strictEqual(C.isSafeIdPart(bad), false, String(bad));
  assert.strictEqual(C.isSafeIdPart('123456789'), true);
  assert.strictEqual(C.authLinkId('kakao', '111', '222', 'USER'), 'kakao_111_222_USER');
  assert.strictEqual(C.authLinkOwnerId('uid1', 'kakao'), 'uid1_kakao');
});

// ── 새 users allowlist ────────────────────────────────────────────────
const BASE = {role: 'USER', name: '홍길동', phone: '01012345678', birthDate: '19900115',
  gender: '남성', identityKey: 'ci1_' + 'a'.repeat(64), evidence: 'kg', termsConsent: {},
  serverNow: 'NOW', passVerifiedAt: 'PV', termsConsentAt: 'TC', birthDateTs: 'BD'};
t('SC-U1 allowlist 밖 키 0 · 계좌 3필드·서류·제재·homeRegion 없음(K8)', () => {
  const doc = C.buildNewUserDoc(BASE);
  for (const k of Object.keys(doc)) assert.ok(C.NEW_USER_DOC_KEYS.includes(k), `allowlist 밖 키 ${k}`);
  for (const k of ['bankName', 'accountNumber', 'accountHolder', 'idCardImagePath', 'bankbookImagePath',
    'homeRegion', 'restrictedUntil', 'ciHash', 'foreignIdentityFingerprint', 'trustScore']) {
    assert.ok(!(k in doc), `${k} 가 있다`);
  }
  assert.strictEqual(doc.accountStatus, 'active');
  assert.strictEqual(doc.nationalityStatus, 'unknown');
  assert.strictEqual(doc.signupSource, 'kakao_v1');
  assert.strictEqual(doc.username, '');
  assert.strictEqual(doc.email, '');
  assert.strictEqual(doc.identityBasisSource, 'PASS');
});
t('SC-U2 성별 없음 → gender 키 없음 · identityBasis 없음', () => {
  const doc = C.buildNewUserDoc({...BASE, gender: null});
  assert.ok(!('gender' in doc));
  assert.ok(!('identityBasisSource' in doc));
});
t('SC-U3 세대 경계 — signupSource 만 본다', () => {
  assert.strictEqual(C.isNewCohortUser({signupSource: 'kakao_v1'}), true);
  assert.strictEqual(C.isNewCohortUser({ciHash: 'x', passVerifiedAt: 1}), false);
  assert.strictEqual(C.isNewCohortUser(undefined), false);
});

// ── 서류 종류(unknown) ─────────────────────────────────────────────────
t('SC-D1 unknown — 종류 없으면 거부 · 외국인등록증은 등록번호 writer 선행 · 주민등록증은 국내', () => {
  const u = {nationalityStatus: 'unknown'};
  assert.deepStrictEqual(C.decideIdDocumentKind(u, undefined), {kind: 'REJECT', reason: 'DOCUMENT_KIND_REQUIRED'});
  assert.deepStrictEqual(C.decideIdDocumentKind(u, 'foreign_registration'),
    {kind: 'REJECT', reason: 'FOREIGN_ID_DOCUMENT_REQUIRED'});
  assert.deepStrictEqual(C.decideIdDocumentKind(u, 'resident_id'), {kind: 'OK', foreign: false, setDomestic: true});
});
t('SC-D2 분류 뒤 — 종류 불일치 거부 · 같은 종류는 기존 필터', () => {
  assert.deepStrictEqual(C.decideIdDocumentKind({nationalityStatus: 'domestic'}, 'foreign_registration'),
    {kind: 'REJECT', reason: 'DOCUMENT_KIND_MISMATCH'});
  assert.deepStrictEqual(C.decideIdDocumentKind({nationalityStatus: 'foreign'}, 'resident_id'),
    {kind: 'REJECT', reason: 'DOCUMENT_KIND_MISMATCH'});
  assert.deepStrictEqual(C.decideIdDocumentKind({nationalityStatus: 'foreign'}, undefined),
    {kind: 'OK', foreign: true, setDomestic: false});
});
t('SC-D3 옛 계정(필드 없음)은 기존 fingerprint 기준 — 종류 입력 무시', () => {
  assert.deepStrictEqual(C.decideIdDocumentKind({foreignIdentityFingerprint: 'fp'}, 'resident_id'),
    {kind: 'LEGACY', foreign: true});
  assert.deepStrictEqual(C.decideIdDocumentKind({}, 'foreign_registration'), {kind: 'LEGACY', foreign: false});
});
t('SC-D4 등록번호 파생 — 5~8 만 · 날짜 실재', () => {
  assert.deepStrictEqual(C.deriveFromForeignId('9001155123456'), {birthDate: '19900115', gender: '남성'});
  assert.deepStrictEqual(C.deriveFromForeignId('0102038123456'), {birthDate: '20010203', gender: '여성'});
  assert.strictEqual(C.deriveFromForeignId('9001151123456'), null, '내국인 코드');
  assert.strictEqual(C.deriveFromForeignId('9002305123456'), null, '없는 날짜');
});

// ── 세션 secret ───────────────────────────────────────────────────────
t('SC-S1 secret — 해시 일치·만료·자격 만료·길이', () => {
  const secret = 'ab'.repeat(32);
  const s = {secretHash: C.sha256Hex(secret), expiresAt: T0 + 1000, secretExpiresAt: T0 + 500};
  assert.strictEqual(C.sessionSecretVerdict(s, secret, T0), 'OK');
  assert.strictEqual(C.sessionSecretVerdict(s, 'cd'.repeat(32), T0), 'SESSION_INVALID');
  assert.strictEqual(C.sessionSecretVerdict(s, secret, T0 + 500), 'SESSION_EXPIRED', '자격 2h 만료');
  assert.strictEqual(C.sessionSecretVerdict(s, 'short', T0), 'SESSION_INVALID');
  assert.strictEqual(C.sessionSecretVerdict(undefined, secret, T0), 'SESSION_INVALID');
});

console.log('─'.repeat(30));
if (fails.length) {
  fails.forEach((f) => console.log('  FAIL ' + f));
  console.log(`총 ${pass + fails.length}건 · 실패 ${fails.length}건`);
  process.exit(1);
}
console.log(`총 ${pass}건 · 실패 0건`);
