/**
 * [ALFIT-AUTH-KAKAO-ONBOARDING.1 · 판정280] 서버 교정 시험 — 감사 모의 반례 3 + 관련 경계.
 *
 *   실행:  npm --prefix functions run build && node --test --test-concurrency=1 test/auth_kakao_b280.test.js
 *
 *   fixture 는 auth_kakao_signup_callables.test.js 의 실행기 앞부분(가짜 Firestore·Auth·카카오·PortOne,
 *   lib/auth_kakao.js 원문 주입, 외부 호출 차단)을 **그대로** 읽어 쓴다 — 감사 server_repro.js 와 같은 방식.
 *   감사 반례 3개는 같은 조작을 하고 **반대 결과**(교정 후 기대)를 단언한다. 모의 · PENDING VERIFICATION.
 *
 *   B1-*  B280-01 삭제 역할 잔존 링크 소유 대조 정리
 *   B2-*  B280-02 서버 쪽 삭제 재확인·문서 없는 재개·blacklisted+deleting·unlink 범위
 *   B3-*  B280-03 완료 거래 안 최신 필수동의·시행 판본·KG 결합
 *   B4-*  B280-04 미완료 세션 선택 true→false 반영(기존 회원 보호 불변)
 */
'use strict';
const fs = require('fs');
const path = require('path');
const fixtureFile = path.join(__dirname, 'auth_kakao_signup_callables.test.js');
const fixture = fs.readFileSync(fixtureFile, 'utf8').split('// ── 실행기')[0];

const cases = String.raw`
const CELLS = [];
const cell = (n, fn) => CELLS.push([n, fn]);

// ═══ B280-01 ══════════════════════════════════════════════════════════
async function twoRoles(sub) {
  const a = await fullSignup(sub, 'USER', 'imp-' + sub + 'a');
  const add = await svc.sessionStartAddRole({auth: {uid: a.out.uid}, data: {role: 'BUSINESS_ADMIN'}});
  await svc.sessionConsent({data: {...S(add.session), consentRecord: CONSENT}});
  await toPass(add.session, 'imp-' + sub + 'b');
  const b = await svc.completeSignup({data: S(add.session)});
  return {userUid: a.out.uid, adminUid: b.uid};
}
async function deleteUntilAuth(uid) {
  await F.db.runTransaction(async (tx) => {
    const ref = F.db.collection('users').doc(uid);
    const snap = await tx.get(ref);
    const apply = await svc.freezeIdentityReadInTx(tx, uid, snap.data());
    tx.set(F.db.collection('account_deletion_tombstones').doc(uid), {barrierAt: F.FieldValue.serverTimestamp()});
    tx.update(ref, {accountStatus: 'deleting'});
    if (apply) apply(tx);
  });
  assert.strictEqual((await svc.cleanupNewIdentityState(uid)).failed, 0);
  F.del('users/' + uid);
  AUTH.users.delete(uid);
}
cell('B1-1 [감사 반례1] 두 역할 중 USER 탈퇴·Auth 뒤 링크 정리 실패 → 삭제 역할 재로그인 = ACCOUNT_DELETED · 생존 ADMIN 링크/owner/로그인 보존', async () => {
  const {userUid, adminUid} = await twoRoles('8801');
  await deleteUntilAuth(userUid);
  const survivorLink = 'authLinks/kakao_' + APP + '_8801_BUSINESS_ADMIN';
  const deletedLink = 'authLinks/kakao_' + APP + '_8801_USER';
  assert.ok(F.has(deletedLink) && F.has(survivorLink));
  await rejects(svc.authKakao({data: {accessToken: kakaoUser('8801'), role: 'USER'}}), 'ACCOUNT_DELETED');
  assert.strictEqual(F.has(deletedLink), false, '삭제 UID 링크는 정리돼야 한다');
  assert.strictEqual(F.has('authLinkOwners/' + userUid + '_kakao'), false);
  assert.strictEqual(F.get(survivorLink).uid, adminUid, '생존 역할 링크가 지워졌다');
  assert.ok(F.has('authLinkOwners/' + adminUid + '_kakao'));
  assert.ok(F.has('users/' + adminUid));
  const login = await svc.authKakao({data: {accessToken: kakaoUser('8801')}});
  assert.strictEqual(login.status, 'TOKEN');
  assert.strictEqual(login.uid, adminUid);
});
cell('B1-2 Final 정상 경로(cleanupAfterAuthDeleted) 도 삭제 UID 링크만 — 생존 역할 보존', async () => {
  const {userUid, adminUid} = await twoRoles('8811');
  await deleteUntilAuth(userUid);
  await svc.cleanupAfterAuthDeleted(userUid);
  assert.ok(!F.has('authLinks/kakao_' + APP + '_8811_USER'));
  assert.strictEqual(F.get('authLinks/kakao_' + APP + '_8811_BUSINESS_ADMIN').uid, adminUid);
  assert.ok(F.has('authLinkOwners/' + adminUid + '_kakao'));
  assert.deepStrictEqual(F.get('authSubjects/kakao_' + APP + '_8811').roles, {BUSINESS_ADMIN: adminUid});
});
cell('B1-3 남의 UID 를 가리키는 링크 id 를 넘겨도 지우지 않는다(소유 대조)', async () => {
  const {userUid, adminUid} = await twoRoles('8812');
  await deleteUntilAuth(userUid);
  // 정리 대상 목록이 잘못 넓어져도(두 역할 id) helper 가 uid 소유를 다시 본다.
  await svc.cleanupDeletedLinksForUid(userUid, ['kakao_' + APP + '_8812_USER', 'kakao_' + APP + '_8812_BUSINESS_ADMIN']);
  assert.ok(!F.has('authLinks/kakao_' + APP + '_8812_USER'));
  assert.strictEqual(F.get('authLinks/kakao_' + APP + '_8812_BUSINESS_ADMIN').uid, adminUid);
});
cell('B1-4 한 역할만 있던 카카오 — 삭제 뒤 로그인 정리 → 다음은 가입(30일 제한은 완료에서)', async () => {
  const a = await fullSignup('8813', 'USER', 'imp-8813');
  await deleteUntilAuth(a.out.uid);
  await rejects(svc.authKakao({data: {accessToken: kakaoUser('8813')}}), 'ACCOUNT_DELETED');
  assert.ok(!F.has('authLinks/kakao_' + APP + '_8813_USER'));
  const r = await svc.authKakao({data: {accessToken: kakaoUser('8813')}});
  assert.strictEqual(r.status, 'SIGNUP_REQUIRED');
});

// ═══ B280-02 서버 ═════════════════════════════════════════════════════
async function proveDeletion(uid, impUid, kgOver = {}) {
  const s = await svc.deletionReauthStart({auth: {uid}});
  kg(impUid, s.requestId, kgOver);
  return svc.verifyPassDeletion({auth: {uid}, data: {imp_uid: impUid}}, KEYS);
}
cell('B2-1 blacklisted+deleting → DELETION_RECOVERY(scope DELETION_ONLY) · 문서 없어도 KG 재확인 → proof → 삭제 precondition 통과', async () => {
  const a = await fullSignup('8821', 'USER', 'imp-8821');
  const uid = a.out.uid;
  F.put('users/' + uid, Object.assign(F.get('users/' + uid), {isBlacklisted: true, accountStatus: 'deleting'}));
  F.put('account_deletion_tombstones/' + uid, {barrierAt: 1});
  const r = await svc.authKakao({data: {accessToken: kakaoUser('8821')}});
  assert.strictEqual(r.status, 'DELETION_RECOVERY');
  assert.strictEqual(r.scope, 'DELETION_ONLY');
  assert.strictEqual(r.uid, uid);
  F.del('users/' + uid);
  const r2 = await svc.authKakao({data: {accessToken: kakaoUser('8821')}});
  assert.strictEqual(r2.status, 'DELETION_RECOVERY', '문서 없는 deleting 도 재개');
  await rejects(svc.assertDeletionProofIfProvider(uid), 'DELETION_REAUTH_REQUIRED');
  const p = await proveDeletion(uid, 'imp-8821d');
  assert.strictEqual(p.proven, true);
  assert.strictEqual(await svc.assertDeletionProofIfProvider(uid), true);
});
cell('B2-2 재확인 cert 만료(20분) · 다른 사람 KG · 10분 proof 만료 — 전부 비밀번호 대용 없이 거절', async () => {
  const a = await fullSignup('8822', 'USER', 'imp-8822');
  const uid = a.out.uid;
  const s = await svc.deletionReauthStart({auth: {uid}});
  kg('imp-8822x', s.requestId);
  NOW += 21 * MIN;
  await rejects(svc.verifyPassDeletion({auth: {uid}, data: {imp_uid: 'imp-8822x'}}, KEYS), 'CERT_EXPIRED');
  await rejects(proveDeletion(uid, 'imp-8822y', {unique_key: 'CI-PERSON-Z'}), 'IDENTITY_MISMATCH');
  await proveDeletion(uid, 'imp-8822z');
  NOW += 10 * MIN;
  await rejects(svc.assertDeletionProofIfProvider(uid), 'DELETION_REAUTH_REQUIRED');
});
cell('B2-3 unlink 범위 — 같은 카카오 생존 역할이 있으면 KEEP_OTHER_ROLE, 없으면 ALLOWED, 옛 계정 null', async () => {
  const {userUid, adminUid} = await twoRoles('8823');
  assert.strictEqual(await svc.providerUnlinkScope(userUid), 'KEEP_OTHER_ROLE');
  await deleteUntilAuth(userUid);
  await svc.cleanupAfterAuthDeleted(userUid);
  assert.strictEqual(await svc.providerUnlinkScope(adminUid), 'ALLOWED');
  assert.strictEqual(await svc.providerUnlinkScope('QA_OLD'), null);
});

cell('B2-4 Final 배선 — unlink 범위를 Auth 삭제 전(링크 존재 시점)에 계산해 성공 응답에 싣는다', async () => {
  const src = require('fs').readFileSync(path.join(__dirname, '..', 'src', 'index.ts'), 'utf8');
  const i = src.indexOf('export const callableDeleteAccountFinal');
  const body = src.slice(i, src.indexOf('\nexport const ', i + 10));
  const scope = body.indexOf('const providerUnlink = await authKakaoSvc.providerUnlinkScope(uid);');
  const authDel = body.indexOf('await admin.auth().deleteUser(uid);');
  const linkCleanup = body.indexOf('await authKakaoSvc.cleanupAfterAuthDeleted(uid);');
  assert.ok(scope > 0 && scope < authDel && authDel < linkCleanup, '순서: 범위 계산 → Auth 삭제 → 링크 정리');
  assert.ok(body.includes('return providerUnlink === null ? {success: true} : {success: true, providerUnlink};'));
});

// ═══ B280-03 ══════════════════════════════════════════════════════════
cell('B3-1 [감사 반례2] 완료 사전검사 뒤 새 필수 판본 시행 + 세션 동의 갱신 → TERMS_VERSION_STALE · active 생성 0', async () => {
  const sess = await begin('8802');
  await toPass(sess, 'imp-consent');
  const originalTx = F.db.runTransaction.bind(F.db);
  let publicationBeforeCompletionTx = true;
  F.db.runTransaction = async (callback) => {
    if (publicationBeforeCompletionTx) {
      publicationBeforeCompletionTx = false;
      F.put('app_settings/legal_terms', {items: [
        {id: 'terms', version: 'v2', isRequired: true, isActive: true},
        {id: 'privacy', version: 'v1', isRequired: true, isActive: true},
      ]});
      await svc.sessionConsent({data: {...S(sess), consentRecord: {}}});
    }
    return originalTx(callback);
  };
  try {
    await rejects(svc.completeSignup({data: S(sess)}), 'TERMS_VERSION_STALE');
  } finally { F.db.runTransaction = originalTx; }
  assert.strictEqual(docs('users').length, 0, '미충족 active 계정이 생겼다');
  // v2 에 동의하면 같은 세션으로 완료된다 — 저장 판본 v2, 필수 시각 존재.
  await svc.sessionConsent({data: {...S(sess), consentRecord: {terms: {agreed: true, version: 'v2'}}}});
  const out = await svc.completeSignup({data: S(sess)});
  const u = F.get('users/' + out.uid);
  assert.strictEqual(u.termsConsent.terms.version, 'v2');
  assert.ok(u.termsConsentAt && typeof u.termsConsentAt.toMillis === 'function');
});
cell('B3-2 새 필수 판본이 사전검사 뒤·거래 전에 시행(세션 갱신 없음) → 거래 안에서 STALE', async () => {
  const sess = await begin('8831');
  await toPass(sess, 'imp-8831');
  const originalTx = F.db.runTransaction.bind(F.db);
  let once = true;
  F.db.runTransaction = async (cb) => {
    if (once) {
      once = false;
      F.put('app_settings/legal_terms', {items: [
        {id: 'terms', version: 'v1', isRequired: true, isActive: true},
        {id: 'privacy', version: 'v1', isRequired: true, isActive: true},
        {id: 'location', version: 'v1', isRequired: true, isActive: true},
      ]});
    }
    return originalTx(cb);
  };
  try {
    await rejects(svc.completeSignup({data: S(sess)}), 'CONSENT_REQUIRED');
  } finally { F.db.runTransaction = originalTx; }
  assert.strictEqual(docs('users').length, 0);
});
cell('B3-3 완료 거래는 legal_terms·필수 발행본을 거래 read-set 으로 읽는다(시행 변경과 경합 직렬화)', async () => {
  F.put('app_settings/legal_terms', {items: [
    {id: 'terms', version: 'v1', isRequired: true, isActive: true, revisionId: 'terms__v1'},
    {id: 'privacy', version: 'v1', isRequired: true, isActive: true},
  ]});
  F.put('legal_revisions/terms__v1', {itemId: 'terms', version: 'v1'});
  const sess = await begin('8832');
  await toPass(sess, 'imp-8832');
  F.clearLog();
  const out = await svc.completeSignup({data: S(sess)});
  const tx = F.W.commits.find((c) => c.writes.some((w) => w.path === 'users/' + out.uid)).tx;
  const reads = F.W.reads.filter((r) => r.tx === tx).map((r) => r.path);
  assert.ok(reads.includes('app_settings/legal_terms'), '시행 약관을 거래 안에서 읽지 않는다');
  assert.ok(reads.includes('legal_revisions/terms__v1'), '필수 발행본을 거래 안에서 읽지 않는다');
});
cell('B3-4 KG 신선도는 거래 시각으로 — 사전검사 통과 뒤 30분 경계를 넘으면 PASS_RESULT_STALE', async () => {
  const sess = await begin('8833');
  await toPass(sess, 'imp-8833');
  NOW += 30 * MIN - 1;
  const originalTx = F.db.runTransaction.bind(F.db);
  let once = true;
  F.db.runTransaction = async (cb) => { if (once) { once = false; NOW += 2; } return originalTx(cb); };
  try {
    await rejects(svc.completeSignup({data: S(sess)}), 'PASS_RESULT_STALE');
  } finally { F.db.runTransaction = originalTx; }
  assert.strictEqual(docs('users').length, 0);
});
cell('B3-5 termsConsentAt = 현재 필수 항목 동의 시각 중 가장 늦은 것', async () => {
  const r = await svc.authKakao({data: {accessToken: kakaoUser('8834')}});
  const sess = r.session;
  await svc.sessionSetPurpose({data: {...S(sess), role: 'USER'}});
  await svc.sessionConsent({data: {...S(sess), consentRecord: {terms: {agreed: true, version: 'v1'}}}});
  const t1 = NOW;
  NOW += 5 * MIN;
  await svc.sessionConsent({data: {...S(sess), consentRecord: {privacy: {agreed: true, version: 'v1'}}}});
  const t2 = NOW;
  NOW += MIN;
  await svc.sessionConsent({data: {...S(sess), consentRecord: {marketing: {agreed: true, version: 'v1'}}}});
  await toPass(sess, 'imp-8834');
  const out = await svc.completeSignup({data: S(sess)});
  const u = F.get('users/' + out.uid);
  assert.strictEqual(u.termsConsentAt.toMillis(), t2, '필수 충족 시각이 아니다');
  assert.ok(t2 > t1);
});

// ═══ B280-04 ══════════════════════════════════════════════════════════
cell('B4-1 [감사 반례3] 같은 세션 선택 marketing true→false → 최종 users·consentEvents 는 false', async () => {
  const optSess = await begin('8803');
  await svc.sessionConsent({data: {...S(optSess), consentRecord: {marketing: {agreed: true, version: 'v1'}}}});
  await svc.sessionConsent({data: {...S(optSess), consentRecord: {marketing: {agreed: false, version: 'v1'}}}});
  await toPass(optSess, 'imp-optout');
  const optOut = await svc.completeSignup({data: S(optSess)});
  const u = F.get('users/' + optOut.uid);
  assert.strictEqual(u.termsConsent.marketing.agreed, false, '마지막 선택이 저장되지 않았다');
  const ev = docs('users/' + optOut.uid + '/consentEvents').map((p) => F.get(p)).filter((e) => e.itemId === 'marketing');
  assert.strictEqual(ev.length, 1);
  assert.strictEqual(ev[0].agreed, false);
});
cell('B4-2 같은 세션 필수 true→false → 충족 해제 · KG 준비/완료 CONSENT_REQUIRED · 다시 true 면 완료', async () => {
  const sess = await begin('8841');
  await toPass(sess, 'imp-8841');
  const c = await svc.sessionConsent({data: {...S(sess), consentRecord: {terms: {agreed: false, version: 'v1'}}}});
  assert.strictEqual(c.requiredSatisfied, false);
  await rejects(svc.completeSignup({data: S(sess)}), 'CONSENT_REQUIRED');
  await svc.sessionConsent({data: {...S(sess), consentRecord: {terms: {agreed: true, version: 'v1'}}}});
  const out = await svc.completeSignup({data: S(sess)});
  assert.strictEqual(F.get('users/' + out.uid).termsConsent.terms.agreed, true);
});
cell('B4-3 기존 회원 재동의 보호는 그대로 — 공유 sanitizer 의 확정 동의 true→false 차단 불변', async () => {
  const TC = require(path.join(__dirname, '..', 'lib', 'terms_consent_payload.js'));
  const r = TC.sanitizeConsentEntries({entries: [['marketing', {agreed: false, version: 'v1'}]],
    activeItems: [{id: 'marketing', version: 'v1', isRequired: false}],
    existing: {marketing: {agreed: true, version: 'v1'}}});
  assert.deepStrictEqual(r.updates, {});
  assert.deepStrictEqual(r.dropped, ['marketing']);
});

(async () => {
  let pass = 0;
  const fails = [];
  for (const [name, fn] of CELLS) {
    reset();
    try { await fn(); pass++; console.log('  ok   ' + name); } catch (e) {
      fails.push(name);
      console.log('  FAIL ' + name + ' — ' + (e.stack || e.message).split('\n').slice(0, 2).join(' | '));
    }
  }
  console.log('─'.repeat(30));
  if (NET.length) { console.log('[차단] 외부 진입 시도: ' + NET.join(', ')); process.exitCode = 1; }
  if (fails.length) {
    console.log('총 ' + (pass + fails.length) + '건 · 실패 ' + fails.length + '건 (모의 · PENDING VERIFICATION)');
    process.exit(1);
  }
  console.log('총 ' + pass + '건 · 실패 0건 (모의 · PENDING VERIFICATION)');
})();
`;
// eslint-disable-next-line no-new-func
new Function('require', '__dirname', fixture + cases)(require, __dirname);
