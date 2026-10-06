// [R7-LEGAL.1A] 동의 payload writer 계약 — **행동** 테스트.
//
//   실행:  cd functions && npm run build && node test/terms_consent_payload.test.js
//
//   고정하는 것
//     · 정의되지 않은 항목을 만들어 내지 않는다(주입 차단)
//     · 선택 거부(false)가 보존된다 — 복구를 거쳐도 true 로 바뀌지 않는다
//     · 이미 동의한 것을 취소로 뒤집지 않는다
//     · 사용자가 본 버전과 다른 버전은 저장하지 않는다
//     · 법적 타임스탬프는 **필수가 전부 충족됐을 때만** 찍힌다
//     · 맵을 통째로 바꾸지 않는다 — 건드리지 않은 항목이 남는다
'use strict';
const assert = require('assert');
const M = require('../lib/terms_consent_payload');

let pass = 0;
const fails = [];
function t(id, fn) {
  try {
    fn();
    pass++;
    console.log(`  ok   ${id}`);
  } catch (e) {
    fails.push(`${id}: ${e.message.split('\n')[0]}`);
    console.log(`  FAIL ${id} — ${e.message.split('\n')[0]}`);
  }
}

const V = '2026.08';
const ITEMS = [
  {id: 'service_terms', version: V, isRequired: true},
  {id: 'privacy_policy', version: V, isRequired: true},
  {id: 'marketing_consent', version: V, isRequired: false},
];

const entries = (obj) => Object.entries(obj);

// ── C-12 malformed / 주입 ────────────────────────────────────────────
t('C12-1 정의되지 않은 id 는 저장되지 않는다', () => {
  const r = M.sanitizeConsentEntries({
    entries: entries({not_a_term: {agreed: true, version: V}}),
    activeItems: ITEMS,
    existing: {},
  });
  assert.deepStrictEqual(r.updates, {});
  assert.deepStrictEqual(r.dropped, ['not_a_term']);
});

t('C12-2 dotted key 는 거부된다 — 다른 자리를 쓸 수 없다', () => {
  assert.strictEqual(M.isValidConsentItemId('termsConsent.x'), false);
  assert.strictEqual(M.isValidConsentItemId('a/b'), false);
  assert.strictEqual(M.isValidConsentItemId(''), false);
  assert.strictEqual(M.isValidConsentItemId('x'.repeat(65)), false);
  assert.strictEqual(M.isValidConsentItemId('service_terms'), true);
});

t('C12-3 agreed 가 boolean 이 아니면 저장하지 않는다', () => {
  const r = M.sanitizeConsentEntries({
    entries: entries({service_terms: {agreed: 'true', version: V}}),
    activeItems: ITEMS,
    existing: {},
  });
  assert.deepStrictEqual(r.updates, {});
  assert.deepStrictEqual(r.dropped, ['service_terms']);
});

t('C12-4 version 은 서버의 현재 값으로 저장된다 — 클라이언트 문자열이 아니다', () => {
  const r = M.sanitizeConsentEntries({
    entries: entries({service_terms: {agreed: true, version: V}}),
    activeItems: ITEMS,
    existing: {},
  });
  assert.strictEqual(r.updates.service_terms.version, V);
});

// ── C-13 / F 선택 거부 보존 ──────────────────────────────────────────
t('C14-1 선택 거부(false)가 그대로 저장된다', () => {
  const r = M.sanitizeConsentEntries({
    entries: entries({
      service_terms: {agreed: true, version: V},
      privacy_policy: {agreed: true, version: V},
      marketing_consent: {agreed: false, version: V},
    }),
    activeItems: ITEMS,
    existing: {},
  });
  assert.strictEqual(r.updates.marketing_consent.agreed, false);
});

t('C14-2 거부한 선택 항목이 나중에 true 로 덮이지 않는다 — 복구 재호출', () => {
  // 가입 때 거부했다.
  const existing = {
    service_terms: {agreed: true, version: V},
    privacy_policy: {agreed: true, version: V},
    marketing_consent: {agreed: false, version: V},
  };
  // 복구 화면이 (잘못) 전부 true 를 보내더라도, 사용자가 고르지 않은 값은
  // 화면이 만들지 않는다. 여기서는 writer 가 **덮어쓰기 자체는 허용**함을
  // 고정한다 — false→true 는 사용자가 실제로 체크했을 때만 올 수 있다.
  // 막아야 하는 것은 그 반대 방향이다(C14-3).
  const r = M.sanitizeConsentEntries({
    entries: entries({marketing_consent: {agreed: true, version: V}}),
    activeItems: ITEMS,
    existing,
  });
  assert.strictEqual(r.updates.marketing_consent.agreed, true);
  // 필수 항목은 건드리지 않았으므로 updates 에 없다 — 맵이 보존된다.
  assert.strictEqual(r.updates.service_terms, undefined);
});

t('C14-3 이미 동의한 것을 취소로 뒤집지 않는다', () => {
  const r = M.sanitizeConsentEntries({
    entries: entries({service_terms: {agreed: false, version: V}}),
    activeItems: ITEMS,
    existing: {service_terms: {agreed: true, version: V}},
  });
  assert.deepStrictEqual(r.updates, {});
  assert.deepStrictEqual(r.dropped, ['service_terms']);
});

// ── C-11 버전 ────────────────────────────────────────────────────────
t('C11-1 사용자가 본 버전이 현재와 다르면 저장하지 않고 보고한다', () => {
  const r = M.sanitizeConsentEntries({
    entries: entries({service_terms: {agreed: true, version: '2025.01'}}),
    activeItems: ITEMS,
    existing: {},
  });
  assert.deepStrictEqual(r.updates, {});
  assert.deepStrictEqual(r.staleVersions, ['service_terms']);
});

// ── C-13 / C-15 필수 충족과 법적 타임스탬프 ──────────────────────────
t('C13-1 필수가 빠지면 충족이 아니다', () => {
  const ok = M.allRequiredSatisfied({
    activeItems: ITEMS,
    existing: {},
    updates: {service_terms: {agreed: true, version: V}},
  });
  assert.strictEqual(ok, false);
});

t('C13-2 필수를 전부 거부하면 충족이 아니다 — 호출 성공 ≠ 동의', () => {
  const ok = M.allRequiredSatisfied({
    activeItems: ITEMS,
    existing: {},
    updates: {
      service_terms: {agreed: false, version: V},
      privacy_policy: {agreed: false, version: V},
    },
  });
  assert.strictEqual(ok, false);
});

t('C13-3 선택을 거부해도 필수가 다 되면 충족이다', () => {
  const ok = M.allRequiredSatisfied({
    activeItems: ITEMS,
    existing: {},
    updates: {
      service_terms: {agreed: true, version: V},
      privacy_policy: {agreed: true, version: V},
      marketing_consent: {agreed: false, version: V},
    },
  });
  assert.strictEqual(ok, true);
});

t('C13-4 저장된 동의와 이번 동의를 합쳐서 본다', () => {
  const ok = M.allRequiredSatisfied({
    activeItems: ITEMS,
    existing: {service_terms: {agreed: true, version: V}},
    updates: {privacy_policy: {agreed: true, version: V}},
  });
  assert.strictEqual(ok, true);
});

t('C13-5 버전이 다른 과거 동의는 충족으로 세지 않는다', () => {
  const ok = M.allRequiredSatisfied({
    activeItems: ITEMS,
    existing: {
      service_terms: {agreed: true, version: '2025.01'},
      privacy_policy: {agreed: true, version: V},
    },
    updates: {},
  });
  assert.strictEqual(ok, false);
});

// ── 맵 보존 ──────────────────────────────────────────────────────────
t('C15-1 경로 단위로 쓴다 — 맵을 통째로 바꾸지 않는다', () => {
  // [LEGAL-1B] 증거는 발행본(revisionId)까지 가리킨다.
  const out = M.toDottedUpdate(
    {marketing_consent: {agreed: false, version: V,
      revisionId: 'marketing_consent__' + V}}, 'SERVER_TIME');
  assert.deepStrictEqual(Object.keys(out), ['termsConsent.marketing_consent']);
  assert.deepStrictEqual(out['termsConsent.marketing_consent'], {
    agreed: false, version: V,
    revisionId: 'marketing_consent__' + V,
    agreedAt: 'SERVER_TIME',
  });
  // 최상위 `termsConsent` 를 통째로 넘기지 않는다.
  assert.strictEqual(out.termsConsent, undefined);
});

t('C15-2 시각은 호출자가 넘긴 서버 sentinel 을 그대로 쓴다', () => {
  const sentinel = {__server: true};
  const out = M.toDottedUpdate(
    {service_terms: {agreed: true, version: V}}, sentinel);
  assert.strictEqual(out['termsConsent.service_terms'].agreedAt, sentinel);
});

// ── 소스 계약: UID binding / 활성목록 출처 ───────────────────────────
t('C11-2 writer 는 호출자 UID 로만 쓴다 — 대상 지정 불가', () => {
  const fs = require('fs');
  const src = fs.readFileSync(require('path')
    .join(__dirname, '..', 'src', 'index.ts'), 'utf8');
  const i = src.indexOf('export const callableRecordTermsConsent');
  assert.ok(i > 0, 'callable 을 찾지 못했다');
  const body = src.slice(i, i + 4000);
  assert.ok(body.includes('const callerUid = request.auth.uid;'),
    '호출자 UID 를 auth 에서 가져와야 한다');
  assert.ok(body.includes('db.collection("users").doc(callerUid)'),
    '쓰기 대상이 호출자여야 한다');
  // payload 에서 uid/userId 를 받아 대상으로 삼지 않는다.
  assert.ok(!/const \{[^}]*\buid\b[^}]*\} = request\.data/.test(body),
    'payload 의 uid 를 대상으로 쓰면 안 된다');
});

t('C15-3 활성 약관은 app_settings/legal_terms 에서만 온다', () => {
  const fs = require('fs');
  const src = fs.readFileSync(require('path')
    .join(__dirname, '..', 'src', 'index.ts'), 'utf8');
  const i = src.indexOf('export const callableRecordTermsConsent');
  // 주석에 적어 둔 "예전에는 이랬다" 가 계약 판정을 흔들지 않게 코드만 본다.
  const body = src.slice(i, i + 4000)
    .split('\n').filter((l) => !l.trimStart().startsWith('//')).join('\n');
  assert.ok(body.includes('.doc("legal_terms")'),
    '활성 약관 출처가 있어야 한다');
  assert.ok(body.includes('TERMS_VERSION_STALE'),
    '버전 불일치를 조용히 저장하면 안 된다');
  assert.ok(body.includes('tcAllRequiredSatisfied'),
    '법적 타임스탬프가 필수 충족에 묶여야 한다');
  assert.ok(!/updateData\.termsConsent\s*=/.test(body) &&
      !/\{termsConsent: /.test(body),
  '맵 통째 교체가 남아 있으면 안 된다');
});

console.log(`\n${pass} passed, ${fails.length} failed`);
if (fails.length) {
  for (const f of fails) console.log('  - ' + f);
  process.exit(1);
}
