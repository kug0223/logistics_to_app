/**
 * [ALFIT-AUTH-KAKAO-ONBOARDING.1 · 판정281] 서버 교정 시험 — 탈퇴 중 계정의 실제 권한 경계 · cert 거래 재판정.
 *
 *   실행:  npm --prefix functions run build && node --test --test-concurrency=1 test/auth_kakao_b281.test.js
 *
 *   F-*  B280-02 잔여 BLOCKER — index.ts 원문 폐포(auth_kakao_index_harness)로 실제 callable 을 실행한다.
 *        감사281 반례(blacklisted+deleting+tombstone UID 의 callableSaveSeal 성공)를 그대로 옮겨 거부를 단언.
 *   R-*  rules 원문 계약(에뮬레이터 실행 아님 — 정적 · PENDING).
 *   C-*  C281-02 — 외부 조회 뒤·거래 시도 시각에 cert 만료면 미소비·미발급(가입 cert 도 같은 경계).
 *   모의 · PENDING VERIFICATION. 외부 호출 차단.
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

process.env.FOREIGN_HMAC_SECRET = 'synthetic-foreign-hmac-secret-000';
process.env.TAX_ID_HMAC_SECRET = 'synthetic-tax-hmac-secret-0000000';
process.env.TAX_ID_ENCRYPT_KEY = Buffer.alloc(32, 7).toString('base64');
process.env.KAKAO_APP_ID = '111';
delete process.env.AUTH_MOCK_MODE;

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

const ROOTS = ['callableSaveSeal', 'callableUpdateBankAccount', 'callableMarkIdCardVerified',
  'callableSignupSessionStartAddRole', 'callableGetAccountDeletionRecoveryState', 'callableDeletionReauthStart',
  'callableGetWithdrawBlockers', 'revokeUserSession', 'callableSignupSessionGet', 'callableFindUsername'];
const {exports: X, info} = loadIndexClosure(ROOTS, F, {HttpsError, console: QCON, Date: FakeDate});
console.log('[폐포] ' + info);

const KEY = 'ci1_' + 'a'.repeat(64);
function kakaoUser(uid, role, o = {}) {
  F.put('users/' + uid, Object.assign({username: '', email: '', name: '홍길동', role, accountStatus: 'active',
    identityKey: KEY, signupSource: 'kakao_v1', nationalityStatus: 'domestic', isBlacklisted: false}, o));
  const linkId = `kakao_111_SUB_${role}`;
  F.put('authLinks/' + linkId, {uid, identityKey: KEY, provider: 'kakao', appNs: '111', subject: 'SUB', role});
  F.put(`authLinkOwners/${uid}_kakao`, {linkId});
}
function freeze(uid, o = {}) {
  F.put('users/' + uid, Object.assign(F.get('users/' + uid), {accountStatus: 'deleting'}, o));
  F.put('account_deletion_tombstones/' + uid, {barrierAt: new F.Ts(NOW)});
}
const call = (fn, data, uid) => fn({data, auth: uid ? {uid, token: {}} : undefined});
async function rejects(p, reason, label) {
  try { await p; } catch (e) {
    const r = e.details && e.details.reason;
    assert.strictEqual(r, reason, `${label || ''} 기대 ${reason} · 실제 ${r} / ${e.code} ${e.message}`);
    return e;
  }
  throw new Error(`${label || ''} 거절 ${reason} 기대 — 성공함`);
}

const CELLS = [];
const cell = (n, fn) => CELLS.push([n, fn]);

// ═══ F — 실제 권한 경계 ═══════════════════════════════════════════════
cell('F-1 [감사281 반례] blacklisted+deleting+tombstone UID 의 callableSaveSeal → ACCOUNT_DELETION_IN_PROGRESS · 쓰기 0', async () => {
  kakaoUser('ADM1', 'BUSINESS_ADMIN');
  freeze('ADM1', {isBlacklisted: true});
  const before = F.get('users/ADM1');
  await rejects(call(X.callableSaveSeal, {sealBase64: 'QUJD', sealType: 'stamp'}, 'ADM1'), 'ACCOUNT_DELETION_IN_PROGRESS');
  assert.deepStrictEqual(F.get('users/ADM1'), before, '봉인이 저장됐다');
});
cell('F-2 freeze 전에 받은 일반 토큰도 같다 — 블랙 아님·users 문서 있음·옛 비밀번호 계정 포함', async () => {
  F.put('users/QA1', {role: 'USER', accountStatus: 'active', username: 'qa1', name: '옛'});
  freeze('QA1');
  await rejects(call(X.callableSaveSeal, {sealBase64: null, sealType: 'stamp'}, 'QA1'), 'ACCOUNT_DELETION_IN_PROGRESS');
  await rejects(call(X.callableUpdateBankAccount, {bankName: '국민', accountNumber: '1'}, 'QA1'), 'ACCOUNT_DELETION_IN_PROGRESS');
  await rejects(call(X.callableMarkIdCardVerified, {storagePath: 'users/QA1/idCard_1700000000001.jpg'}, 'QA1'),
    'ACCOUNT_DELETION_IN_PROGRESS');
  assert.ok(!('bankName' in F.get('users/QA1')));
});
cell('F-3 users 문서가 이미 없는 deleting(Auth-tail) 도 비삭제 callable 거부', async () => {
  kakaoUser('U3', 'USER');
  freeze('U3');
  F.del('users/U3');
  await rejects(call(X.callableSaveSeal, {sealBase64: null, sealType: 'stamp'}, 'U3'), 'ACCOUNT_DELETION_IN_PROGRESS');
  assert.ok(!F.has('users/U3'), '문서가 되살아났다');
});
cell('F-4 역할 추가(로그인 uid 사용) 도 거부 — bearer-secret 가입 callable 은 uid 를 쓰지 않아 판정 대상 아님', async () => {
  kakaoUser('U4', 'USER');
  freeze('U4');
  await rejects(call(X.callableSignupSessionStartAddRole, {role: 'BUSINESS_ADMIN'}, 'U4'), 'ACCOUNT_DELETION_IN_PROGRESS');
  // 세션 callable 은 uid 대신 secret 으로 권한을 본다 — 펜스가 아니라 자기 판정(SESSION_INVALID)으로 거절.
  await rejects(call(X.callableSignupSessionGet, {sessionId: 'kakao_111_SUB', secret: 'ab'.repeat(32)}, 'U4'),
    'SESSION_INVALID');
});
cell('F-5 삭제 흐름은 허용 — 재개 상태·재확인 시작·탈퇴 차단 미리보기·세션 무효화', async () => {
  kakaoUser('U5', 'USER');
  freeze('U5', {isBlacklisted: true});
  const st = await call(X.callableGetAccountDeletionRecoveryState, {}, 'U5');
  assert.deepStrictEqual(st, {deletionInProgress: true, userDocExists: true, accountStatus: 'deleting', reauthMethod: 'kakao_kg'});
  const r = await call(X.callableDeletionReauthStart, {}, 'U5');
  assert.ok(/^alfit_del_[0-9a-f]{24}$/.test(r.requestId));
  let wbErr = null;
  try { await call(X.callableGetWithdrawBlockers, {}, 'U5'); } catch (e) { wbErr = e; }
  assert.ok(!wbErr || (wbErr.details || {}).reason !== 'ACCOUNT_DELETION_IN_PROGRESS', '탈퇴 미리보기가 펜스에 막혔다');
  let rvErr = null;
  try { await call(X.revokeUserSession, {}, 'U5'); } catch (e) { rvErr = e; }
  assert.ok(!rvErr || (rvErr.details || {}).reason !== 'ACCOUNT_DELETION_IN_PROGRESS');
});
cell('F-6 같은 사람의 생존 역할(UID 다름 · tombstone 없음) 은 정상 업무 그대로', async () => {
  kakaoUser('DEL6', 'USER');
  freeze('DEL6');
  kakaoUser('ADM6', 'BUSINESS_ADMIN');
  const r = await call(X.callableSaveSeal, {sealBase64: 'QUJD', sealType: 'stamp'}, 'ADM6');
  assert.deepStrictEqual(r, {success: true});
  assert.strictEqual(F.get('users/ADM6').sealBase64, 'QUJD');
});
cell('F-7 인증 없는 호출은 판정하지 않는다(각 callable 의 자체 권한) · 판정 읽기 실패는 fail-closed', async () => {
  const r = await call(X.callableFindUsername, {name: '없음', phone: '0'});
  assert.deepStrictEqual(r.accounts, []);
  try {
    await call(X.callableSaveSeal, {sealBase64: null, sealType: 'stamp'}, 'bad/uid');
    throw new Error('통과');
  } catch (e) { assert.strictEqual(e.code, 'unavailable', `${e.code} ${e.message}`); }
});
cell('F-8 원문 배선 — 모든 export 가 같은 래퍼를 지나고, 허용 목록은 삭제 흐름 16개뿐', async () => {
  const src = fs.readFileSync(path.join(__dirname, '..', 'src', 'index.ts'), 'utf8');
  assert.ok(src.includes('onCall as fbOnCall'), 'firebase onCall 을 직접 쓰는 이름이 남았다');
  assert.strictEqual((src.match(/\bfbOnCall\(/g) || []).length, 2, 'fbOnCall 은 래퍼 안 두 곳에서만');
  const exportsAll = [...src.matchAll(/^export const (\w+) = (on\w+)\(/gm)];
  const callables = exportsAll.filter((m) => m[2] === 'onCall').map((m) => m[1]);
  assert.ok(callables.length > 250, 'callable 수가 줄었다: ' + callables.length);
  const allowed = callables.filter((n) => {
    const i = src.indexOf(`export const ${n} = onCall(`);
    const head = src.slice(i, i + 800);
    return /^export const \w+ = onCall\(\s*(\/\/[^\n]*\n\s*)*(allowDuringAccountDeletion\(|AK_DELETION_SAFE_OPTS\(\))/.test(head);
  }).sort();
  assert.deepStrictEqual(allowed, ['callableAuthKakao', 'callableCompleteSignup', 'callableDeleteAccountApplications',
    'callableDeleteAccountFinal', 'callableDeleteAccountPreData', 'callableDeletionReauthStart',
    'callableGetAccountDeletionRecoveryState', 'callableGetWithdrawBlockers', 'callableSignupFinalizeAuth',
    'callableSignupSessionCancel', 'callableSignupSessionConsent', 'callableSignupSessionGet',
    'callableSignupSessionPrepareCertification', 'callableSignupSessionSetPurpose', 'revokeUserSession',
    'verifyPassAuth'].sort());
});

// ═══ R — rules(정적) ═════════════════════════════════════════════════
const RULES = fs.readFileSync(path.join(__dirname, '..', '..', 'firestore.rules'), 'utf8').replace(/\r/g, '');
cell('R-1 모든 비-false 클라 쓰기 allow 가 callerNotDeleting() 로 시작(users 본인 update 만 로그인·FCM 예외)', async () => {
  const re = /allow\s+((?:write|create|update|delete)(?:\s*,\s*(?:write|create|update|delete))*)\s*:\s*if\s+([^;]*);/g;
  let n = 0;
  let m;
  while ((m = re.exec(RULES)) !== null) {
    const e = m[2].trim();
    if (e === 'false') continue;
    n++;
    // [storage_301 · rules_297 §B-5 갱신] 판정297 이 schedule_change_requests delete 를 `callerNotDeleting() && isSuperAdmin()`
    //   (괄호 없는 단일 호출)으로 좁혔다. 단일 호출 뒤에는 최상위 `||` 가 없어 `callerNotDeleting() && (isSuperAdmin())` 과 같은 뜻 —
    //   펜스가 맨 앞이라는 보호 의도는 그대로다. 그 꼴(펜스 && 인자 없는 단일 helper 호출)만 추가로 받는다.
    const ok = e.startsWith('callerNotDeleting() && (') || e.startsWith('(callerNotDeleting() ||') ||
      /^callerNotDeleting\(\) && [A-Za-z_]\w*\(\)$/.test(e);
    assert.ok(ok, '펜스 없는 쓰기 규칙: ' + e.slice(0, 90));
  }
  assert.ok(n >= 61, '쓰기 규칙 수: ' + n);
  assert.strictEqual((RULES.match(/\(callerNotDeleting\(\) \|\|/g) || []).length, 1);
  assert.ok(/\(callerNotDeleting\(\) \|\|\s*request\.resource\.data\.diff\(resource\.data\)\.affectedKeys\(\)\s*\.hasOnly\(\['lastLoginAt', 'fcmToken', 'fcmTokens', 'fcmTokenUpdatedAt'\]\)\) && \(isLoggedIn\(\) &&\s*isOwner\(userId\)/.test(RULES));
});
cell('R-2 사업장 소유권 기반 규칙(감사 지적 isAdminOf · 사업장 update) 이 펜스 뒤에 있다', async () => {
  assert.ok(/function callerNotDeleting\(\) \{\s*return request\.auth == null \|\| !accountDeletionBarrierExists\(request\.auth\.uid\);\s*\}/.test(RULES));
  assert.ok(/allow update: if callerNotDeleting\(\) && \(\(isAdminOf\(businessId\) \|\| isSuperAdmin\(\)\) &&/.test(RULES));
});

// ═══ C — cert 거래 재판정(서비스 수준 · 기존 fixture) ════════════════
const fixture = fs.readFileSync(path.join(__dirname, 'auth_kakao_signup_callables.test.js'), 'utf8').split('// ── 실행기')[0];
const SERVICE_CASES = String.raw`
const out = [];
async function run(name, fn) { reset(); try { await fn(); out.push([name, null]); } catch (e) { out.push([name, e]); } }
return (async () => {
  await run('C-1 탈퇴 재확인 — 만료 1ms 전 입장 · KG 조회 뒤 만료 → CERT_EXPIRED · passCert/proof 0', async () => {
    const a = await fullSignup('8901', 'USER', 'imp-8901');
    const uid = a.out.uid;
    const s = await svc.deletionReauthStart({auth: {uid}});
    NOW = s.expiresAtMs - 1;
    PORTONE.set('imp-del', () => { NOW += 2; return {code: 0, response: {certified: true, unique_key: 'CI-PERSON-A',
      name: '홍길동', birthday: '1990-01-15', phone: '01012345678', gender: 'male', merchant_uid: s.requestId,
      certified_at: Math.floor((NOW - 2) / 1000)}}; });
    await rejects(svc.verifyPassDeletion({auth: {uid}, data: {imp_uid: 'imp-del'}}, KEYS), 'CERT_EXPIRED');
    assert.ok(!F.has('passCertifications/' + CORE.sha256Hex('imp-del')), '만료 cert 로 KG 사건이 소비됐다');
    assert.strictEqual(F.get('deletionReauthProofs/' + uid).proof, null, '만료 cert 로 proof 가 발급됐다');
    await rejects(svc.assertDeletionProofIfProvider(uid), 'DELETION_REAUTH_REQUIRED');
  });
  await run('C-2 가입 cert — 같은 경계(KG 조회 뒤 만료 → CERT_EXPIRED · 미결합)', async () => {
    const sess = await begin('8902');
    const p = await svc.sessionPrepareCertification({data: S(sess)});
    NOW = p.expiresAtMs - 1;
    PORTONE.set('imp-sg', () => { NOW += 2; return {code: 0, response: {certified: true, unique_key: 'CI-PERSON-A',
      name: '홍길동', birthday: '1990-01-15', phone: '01012345678', merchant_uid: p.requestId,
      certified_at: Math.floor((NOW - 2) / 1000)}}; });
    await rejects(svc.verifyPassSignup({data: {...S(sess), imp_uid: 'imp-sg'}}, KEYS), 'CERT_EXPIRED');
    assert.ok(!F.has('passCertifications/' + CORE.sha256Hex('imp-sg')));
    assert.strictEqual(F.get('signupSessions/kakao_' + APP + '_8902').pass, null);
  });
  await run('C-3 유효 창 안이면 그대로 발급(회귀) — proof 10분', async () => {
    const a = await fullSignup('8903', 'USER', 'imp-8903');
    const uid = a.out.uid;
    const s = await svc.deletionReauthStart({auth: {uid}});
    kg('imp-ok', s.requestId);
    const r = await svc.verifyPassDeletion({auth: {uid}, data: {imp_uid: 'imp-ok'}}, KEYS);
    assert.strictEqual(r.proven, true);
  });
  return out;
})();
`;

(async () => {
  let pass = 0;
  const fails = [];
  for (const [name, fn] of CELLS) {
    F.reset(); LOGS.length = 0; NOW = Date.UTC(2026, 10, 25, 3, 0);
    try { await fn(); pass++; console.log('  ok   ' + name); } catch (e) {
      fails.push(name);
      console.log('  FAIL ' + name + ' — ' + (e.stack || e.message).split('\n').slice(0, 2).join(' | '));
    }
  }
  // eslint-disable-next-line no-new-func
  const svcResults = await new Function('require', '__dirname', fixture + SERVICE_CASES)(require, __dirname);
  for (const [name, e] of svcResults) {
    if (!e) { pass++; console.log('  ok   ' + name); } else {
      fails.push(name);
      console.log('  FAIL ' + name + ' — ' + (e.stack || e.message).split('\n').slice(0, 2).join(' | '));
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
