// [R7-LEGAL.1B] 발행 불변성 · 동의 이력 · 재동의 판정 — **행동** 테스트.
//
//   실행:  cd functions && npm run build && node test/legal_publication.test.js
//
//   고정하는 것
//     · 발행본은 고쳐 쓸 수 없다 — 본문을 바꾸려면 새 버전
//     · 증거는 덧붙이기만 한다 — projection 갱신이 과거를 지우지 않는다
//     · 필수 항목의 발행본이 바뀌면 재동의가 필요하다
//     · 선택 항목은 새 판이 나와도 자동 true 가 되지 않는다
//     · 증명할 수 없는 옛 기록을 동의로 승격하지 않는다
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const M = require('../lib/legal_publication');

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

const indexSrc = () => fs
  .readFileSync(path.join(__dirname, '..', 'src', 'index.ts'), 'utf8')
  .split('\n').filter((l) => !l.trimStart().startsWith('//')).join('\n');
const rulesSrc = () => fs
  .readFileSync(path.join(__dirname, '..', '..', 'firestore.rules'), 'utf8')
  .split('\n').filter((l) => !l.trimStart().startsWith('//')).join('\n');

/**
 * rules 의 한 match 블록만 떼어 낸다.
 *
 * `[\s\S]*?` 로 느슨하게 보면 **다음 블록의 `allow write: if false;` 까지**
 * 삼켜서, 이 블록이 열려 있어도 통과한다(변이 B2 가 그것을 잡아냈다).
 * 그래서 다음 `match ` 가 나오기 전까지로 끊는다.
 */
function rulesBlock(header) {
  const s = rulesSrc();
  const i = s.indexOf(header);
  if (i < 0) throw new Error(`블록을 찾지 못했다: ${header}`);
  const rest = s.slice(i + header.length);
  const end = rest.indexOf('match ');
  return rest.slice(0, end < 0 ? rest.length : end);
}

const CONTENT = '제1조 목적\n이 약관은 ...';
const OTHER = '제1조 목적\n이 약관은 바뀌었다 ...';

// ── Publication 1~5 ─────────────────────────────────────────────────
t('P1 발행본은 고쳐 쓸 수 없다 — rules 가 전면 차단', () => {
  const rev = rulesBlock('match /legal_revisions/{revisionId} {');
  assert.ok(rev.includes('allow write: if false;'),
    'legal_revisions 쓰기가 열려 있다');
  assert.ok(!/allow (write|create|update|delete): if (?!false;)/.test(rev),
    'legal_revisions 에 다른 쓰기 경로가 있다');
  // projection 도 클라이언트가 직접 못 고친다 — 발행과 한 묶음이어야 한다.
  const app = rulesBlock('match /app_settings/{docId} {');
  assert.ok(app.includes("allow write: if docId != 'legal_terms' && isSuperAdmin();"),
    'legal_terms 직접 쓰기가 남아 있다');
});

t('P2 같은 버전에 다른 본문 → 거절 (새 버전으로만 바꾼다)', () => {
  const v = M.evaluatePublish({
    itemId: 'service_terms', version: '2026.08', content: OTHER,
    existing: {itemId: 'service_terms', version: '2026.08',
      contentHash: M.contentHashOf(CONTENT)},
  });
  assert.strictEqual(v.ok, false);
  assert.strictEqual(v.reason, 'VERSION_REUSED');
});

t('P3 새 버전이면 같은 항목이라도 새 발행본이 된다', () => {
  const v = M.evaluatePublish({
    itemId: 'service_terms', version: '2026.11', content: OTHER, existing: null,
  });
  assert.deepStrictEqual(v, {ok: true, reason: 'CREATE'});
  assert.strictEqual(M.legalRevisionId('service_terms', '2026.11'),
    'service_terms__2026.11');
  // 버전 문자열은 항목 안에서만 뜻이 있다 — DEV 에서 네 항목이 2026.08 을
  // 공유하고 있었다. 그래서 id 에 itemId 가 함께 들어간다.
  assert.notStrictEqual(M.legalRevisionId('a', '2026.08'),
    M.legalRevisionId('b', '2026.08'));
});

t('P4 같은 본문 재발행은 무해하다 (idempotent)', () => {
  const v = M.evaluatePublish({
    itemId: 'service_terms', version: '2026.08', content: CONTENT,
    existing: {itemId: 'service_terms', version: '2026.08',
      contentHash: M.contentHashOf(CONTENT)},
  });
  assert.deepStrictEqual(v, {ok: true, reason: 'IDENTICAL'});
});

// [R7-PAYROLL-POLICY.5A] 고정 길이 창(5000자)으로 잘라 보고 있었다.
//   함수가 자라자 `tx.set(termsRef` 가 창 밖으로 밀려나 "projection 갱신이
//   없다" 고 틀린 말을 했다. 다음 `export const` 까지로 자른다.
function publishBody() {
  const s = indexSrc();
  const i = s.indexOf('export const callablePublishLegalRevision');
  assert.ok(i > 0, '발행 callable 을 찾지 못했다');
  const j = s.indexOf('\nexport const ', i + 10);
  return s.slice(i, j > 0 ? j : s.length);
}

t('P4b 공개 목록은 발행본을 가리킨다 (current pointer)', () => {
  const body = publishBody();
  assert.ok(body.includes('tx.create(revRef'), '발행본은 create 로만 만든다');
  assert.ok(!/tx\.(set|update)\(revRef/.test(body),
    '발행본을 덮어쓰는 경로가 있다');
  assert.ok(body.includes('revisionId,'), 'projection 이 발행본을 가리켜야 한다');
  assert.ok(body.includes('tx.set(termsRef'), 'projection 갱신이 없다');
});

t('P5 슈퍼관리자가 아니면 발행할 수 없다', () => {
  const s = indexSrc();
  const i = s.indexOf('export const callablePublishLegalRevision');
  const body = s.slice(i, i + 2000);
  assert.ok(body.includes('!== "SUPER_ADMIN"'), '역할 검사가 없다');
  assert.ok(body.includes('permission-denied'));
});

t('P5b 형식이 깨진 id·버전·빈 본문은 발행하지 않는다', () => {
  assert.strictEqual(M.isValidLegalToken('a/b'), false);
  assert.strictEqual(M.isValidLegalToken('..'), false);
  assert.strictEqual(M.isValidLegalToken('2026.08'), true);
  assert.strictEqual(M.evaluatePublish({
    itemId: 'x', version: 'v', content: '   ', existing: null,
  }).reason, 'EMPTY_CONTENT');
});

// ── Consent history 6~10 ────────────────────────────────────────────
t('C6 동의 한 건마다 사건을 남긴다', () => {
  const s = indexSrc();
  const i = s.indexOf('export const callableRecordTermsConsent');
  const body = s.slice(i, i + 6000);
  assert.ok(body.includes('tx.create(userRef.collection("consentEvents").doc()'),
    '증거 append 가 없다');
  assert.ok(body.includes('requiredAtConsentTime'),
    '그 시점의 필수 여부를 남겨야 한다');
  assert.ok(body.includes('revisionId: value.revisionId'),
    '증거가 발행본을 가리켜야 한다');
});

t('C7/C8 증거는 덧붙이기만 한다 — 수정·삭제 경로 없음', () => {
  const s = indexSrc();
  assert.ok(!/consentEvents[\s\S]{0,200}?\.delete\(/.test(s),
    '증거 삭제 경로가 있다');
  assert.ok(!/tx\.(update|set)\(userRef\.collection\("consentEvents"\)/.test(s),
    '증거를 덮어쓰는 경로가 있다');
  const ev = rulesBlock('match /users/{userId}/consentEvents/{eventId} {');
  assert.ok(ev.includes('allow write: if false;'),
    '클라이언트가 증거를 쓸 수 있다');
  assert.ok(!/allow (write|create|update|delete): if (?!false;)/.test(ev),
    '증거에 다른 쓰기 경로가 있다');
});

t('C9 projection 은 최신만 갱신한다 — 경로 단위', () => {
  const s = indexSrc();
  assert.ok(s.includes('tcToDottedUpdate(updates, serverTime)'));
  // 맵 통째 교체가 돌아오면 안 된다(1A 회귀 방지).
  assert.ok(!/\{termsConsent: /.test(s));
});

t('C10 거부도 사건으로 남는다', () => {
  const s = indexSrc();
  const i = s.indexOf('for (const [itemId, value] of Object.entries(updates))');
  assert.ok(i > 0, '사건 생성 루프가 없다');
  const body = s.slice(i, i + 800);
  // agreed 를 그대로 쓴다 — true 인 것만 남기지 않는다.
  assert.ok(body.includes('agreed: value.agreed'));
  assert.ok(!/if \(value\.agreed\)/.test(body), '동의한 것만 남기면 안 된다');
});

// ── Reconsent 11~15 ─────────────────────────────────────────────────
const item = (id, version, isRequired, isActive = true) => ({
  id, version, isRequired, isActive,
  revisionId: M.legalRevisionId(id, version),
});
const acc = (id, version, agreed = true) => ({
  [id]: {agreed, version, revisionId: M.legalRevisionId(id, version)},
});

t('R11 필수 항목이 같은 발행본이면 READY', () => {
  const v = M.evaluateReconsent({
    activeItems: [item('service_terms', '2026.08', true)],
    consent: acc('service_terms', '2026.08'),
  });
  assert.deepStrictEqual(v.required, []);
});

t('R12 필수 항목의 발행본이 바뀌면 재동의가 필요하다', () => {
  const v = M.evaluateReconsent({
    activeItems: [item('service_terms', '2026.11', true)],
    consent: acc('service_terms', '2026.08'),
  });
  assert.deepStrictEqual(v.required, ['service_terms']);
});

t('R13 선택 항목은 새 판이 나와도 자동 true 가 아니고 막지도 않는다', () => {
  const v = M.evaluateReconsent({
    activeItems: [item('marketing_consent', '2026.11', false)],
    consent: acc('marketing_consent', '2026.08', false),
  });
  assert.deepStrictEqual(v.required, [], '선택이 진행을 막으면 안 된다');
  assert.deepStrictEqual(v.optionalUnanswered, ['marketing_consent']);
  // 과거 거부가 새 판의 동의로 승격되지 않는다.
  const again = M.evaluateReconsent({
    activeItems: [item('marketing_consent', '2026.08', false)],
    consent: acc('marketing_consent', '2026.08', false),
  });
  assert.deepStrictEqual(again.optionalUnanswered, [],
    '같은 판에 대해 거부로 답했으면 다시 묻지 않는다');
});

t('R14 새로 생긴 필수 항목은 재동의 대상이다', () => {
  const v = M.evaluateReconsent({
    activeItems: [item('service_terms', '2026.08', true),
      item('new_required', '2026.11', true)],
    consent: acc('service_terms', '2026.08'),
  });
  assert.deepStrictEqual(v.required, ['new_required']);
});

t('R15 비활성 항목은 판정에서 빠진다', () => {
  const v = M.evaluateReconsent({
    activeItems: [item('retired_terms', '2025.01', true, false)],
    consent: {},
  });
  assert.deepStrictEqual(v.required, []);
  assert.deepStrictEqual(v.optionalUnanswered, []);
});

t('R12b 동의가 아니라 거부였으면 필수는 충족되지 않는다', () => {
  const v = M.evaluateReconsent({
    activeItems: [item('service_terms', '2026.08', true)],
    consent: acc('service_terms', '2026.08', false),
  });
  assert.deepStrictEqual(v.required, ['service_terms']);
});

// ── Migration 16~18 ─────────────────────────────────────────────────
const KNOWN = new Set(['service_terms__2026.08']);

t('M16 기록이 없으면 동의로 추정하지 않는다', () => {
  assert.strictEqual(
    M.classifyLegacyConsent({record: undefined, knownRevisionIds: KNOWN}),
    'MISSING');
  assert.strictEqual(
    M.classifyLegacyConsent({record: {version: '2026.08'},
      knownRevisionIds: KNOWN}),
    'MISSING', 'agreed 가 없으면 기록이 아니다');
});

t('M17 버전만 있고 발행본을 모르면 AMBIGUOUS — 동의로 바꾸지 않는다', () => {
  assert.strictEqual(
    M.classifyLegacyConsent({
      record: {agreed: true, version: '2026.08'},
      knownRevisionIds: KNOWN,
    }),
    'AMBIGUOUS');
  // 존재하지 않는 발행본을 가리켜도 AMBIGUOUS 다.
  assert.strictEqual(
    M.classifyLegacyConsent({
      record: {agreed: true, version: 'x', revisionId: 'service_terms__9999'},
      knownRevisionIds: KNOWN,
    }),
    'AMBIGUOUS');
});

t('M18 발행본을 가리키고 그 발행본이 실제로 있으면 KNOWN', () => {
  assert.strictEqual(
    M.classifyLegacyConsent({
      record: {agreed: true, version: '2026.08',
        revisionId: 'service_terms__2026.08'},
      knownRevisionIds: KNOWN,
    }),
    'KNOWN');
  // 거부도 KNOWN 이다 — 분류는 "증명 가능한가"이지 "동의했는가"가 아니다.
  assert.strictEqual(
    M.classifyLegacyConsent({
      record: {agreed: false, version: '2026.08',
        revisionId: 'service_terms__2026.08'},
      knownRevisionIds: KNOWN,
    }),
    'KNOWN');
});

t('M16b revisionId 없는 옛 기록은 재동의 판정에서 수락으로 세지 않는다', () => {
  const v = M.evaluateReconsent({
    activeItems: [item('service_terms', '2026.08', true)],
    consent: {service_terms: {agreed: true, version: '2026.08'}},
  });
  assert.deepStrictEqual(v.required, ['service_terms'],
    '무엇에 동의했는지 모르면 충족이 아니다');
});

console.log(`\n${pass} passed, ${fails.length} failed`);
if (fails.length) {
  for (const f of fails) console.log('  - ' + f);
  process.exit(1);
}
