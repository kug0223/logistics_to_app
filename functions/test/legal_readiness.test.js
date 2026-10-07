// [R7-LEGAL.1B.1] 재동의 상태 소비 계약 — **행동** 테스트.
//
//   실행:  cd functions && npm run build && node test/legal_readiness.test.js
//
//   고정하는 것
//     · 새 판(발행본 실재)과 옛 기록(발행본 없음)을 다른 사건으로 가른다
//     · 막는 것은 새 판 하나다 — 옛 기록으로 앱을 잠그지 않는다
//     · 선택 항목은 막지도, 자동 true 도 아니다
//     · 조회 실패를 미동의로 바꾸지 않는다(통과시킨다)
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const R = require('../lib/legal_readiness');

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

const item = (id, version, isRequired, isActive = true) => ({
  id, version, isRequired, isActive, revisionId: `${id}__${version}`,
});
const acc = (id, version, agreed = true) =>
  ({[id]: {agreed, version, revisionId: `${id}__${version}`}});
const published = (...ids) => new Set(ids);

// ── 1. 현재 ─────────────────────────────────────────────────────────
t('S1 현재 판을 수락했으면 CURRENT — 할 일 없음', () => {
  const r = R.evaluateLegalReadiness({
    activeItems: [item('service_terms', '2026.08', true)],
    consent: acc('service_terms', '2026.08'),
    publishedRevisionIds: published('service_terms__2026.08'),
  });
  assert.strictEqual(r.status, 'CURRENT');
  assert.strictEqual(R.allowsNewCommitment(r.status), true);
});

// ── 2. 새 판 ────────────────────────────────────────────────────────
t('S2 새 판이 발행됐고 미동의면 RECONSENT_REQUIRED — 새 약속을 막는다', () => {
  const r = R.evaluateLegalReadiness({
    activeItems: [item('service_terms', '2026.11', true)],
    consent: acc('service_terms', '2026.08'),
    publishedRevisionIds: published('service_terms__2026.11'),
  });
  assert.strictEqual(r.status, 'RECONSENT_REQUIRED');
  assert.deepStrictEqual(r.reconsentRequired, ['service_terms']);
  assert.deepStrictEqual(r.legacyUnknown, []);
  assert.strictEqual(R.allowsNewCommitment(r.status), false);
});

// ── 3. 옛 기록 ──────────────────────────────────────────────────────
t('S3 발행본이 없으면 LEGACY_CONSENT_UNKNOWN — 막지 않는다', () => {
  const r = R.evaluateLegalReadiness({
    activeItems: [item('service_terms', '2026.08', true)],
    consent: {},                       // 기록 없음
    publishedRevisionIds: published(), // 1B 이전 — 발행본 자체가 없다
  });
  assert.strictEqual(r.status, 'LEGACY_CONSENT_UNKNOWN');
  assert.deepStrictEqual(r.legacyUnknown, ['service_terms']);
  assert.deepStrictEqual(r.reconsentRequired, []);
  // 발행이 아직 새 경로를 거치지 않았다면 **모든 사용자**가 이 상태다.
  // 이걸로 막으면 제품이 멈춘다.
  assert.strictEqual(R.allowsNewCommitment(r.status), true);
});

t('S3b revisionId 없는 옛 동의도 LEGACY — 동의로 세지 않는다', () => {
  const r = R.evaluateLegalReadiness({
    activeItems: [item('service_terms', '2026.08', true)],
    consent: {service_terms: {agreed: true, version: '2026.08'}},
    publishedRevisionIds: published(),
  });
  assert.strictEqual(r.status, 'LEGACY_CONSENT_UNKNOWN');
});

// ── 4. 선택 ─────────────────────────────────────────────────────────
t('S4 선택만 미응답이면 OPTIONAL_UNANSWERED — 막지 않는다', () => {
  const r = R.evaluateLegalReadiness({
    activeItems: [
      item('service_terms', '2026.08', true),
      item('marketing_consent', '2026.11', false),
    ],
    consent: {
      ...acc('service_terms', '2026.08'),
      ...acc('marketing_consent', '2026.08', false),
    },
    publishedRevisionIds: published(
      'service_terms__2026.08', 'marketing_consent__2026.11'),
  });
  assert.strictEqual(r.status, 'OPTIONAL_UNANSWERED');
  assert.deepStrictEqual(r.optionalUnanswered, ['marketing_consent']);
  assert.strictEqual(R.allowsNewCommitment(r.status), true);
  // 과거 거부가 새 판의 동의로 승격되지 않는다.
  assert.deepStrictEqual(r.reconsentRequired, []);
});

// ── 5. 우선순위 ─────────────────────────────────────────────────────
t('S5 새 판이 옛 기록·선택보다 먼저 말해진다', () => {
  const r = R.evaluateLegalReadiness({
    activeItems: [
      item('a', '2', true),   // 발행본 있음 → 새 판
      item('b', '1', true),   // 발행본 없음 → 옛 기록
      item('c', '1', false),  // 선택 미응답
    ],
    consent: acc('a', '1'),
    publishedRevisionIds: published('a__2'),
  });
  assert.strictEqual(r.status, 'RECONSENT_REQUIRED');
  assert.deepStrictEqual(r.reconsentRequired, ['a']);
  assert.deepStrictEqual(r.legacyUnknown, ['b']);
  assert.deepStrictEqual(r.optionalUnanswered, ['c']);
});

t('S6 비활성 항목은 판정에서 빠진다', () => {
  const r = R.evaluateLegalReadiness({
    activeItems: [item('retired', '1', true, false)],
    consent: {},
    publishedRevisionIds: published(),
  });
  assert.strictEqual(r.status, 'CURRENT');
});

t('S7 필수를 거부했으면 충족이 아니다', () => {
  const r = R.evaluateLegalReadiness({
    activeItems: [item('service_terms', '2026.08', true)],
    consent: acc('service_terms', '2026.08', false),
    publishedRevisionIds: published('service_terms__2026.08'),
  });
  assert.strictEqual(r.status, 'RECONSENT_REQUIRED');
});

// ── 최초 발행 이후 (R7-LEGAL.DEPLOY §12 에서 실제로 터진 경우) ──────
//
//   DEV 에서 활성 5종을 처음 발행하자마자 기존 사용자 8명이 전원
//   RECONSENT_REQUIRED 로 뒤집히고 지원이 막혔다. 우리가 약관을 바꾼 적이
//   없는데 "변경되었습니다" 라고 말한 것이다. 아래 네 셀이 그 경우를 고정한다.
t('S11 발행본이 생긴 뒤에도 revisionId 없는 옛 기록은 LEGACY 다', () => {
  const r = R.evaluateLegalReadiness({
    activeItems: [item('service_terms', '2026.08', true)],
    // 1B 이전 기록 — 무엇에 동의했는지 증명할 수 없다.
    consent: {service_terms: {agreed: true, version: '2026.08'}},
    publishedRevisionIds: published('service_terms__2026.08'),
  });
  assert.strictEqual(r.status, 'LEGACY_CONSENT_UNKNOWN');
  assert.deepStrictEqual(r.reconsentRequired, []);
  assert.strictEqual(R.allowsNewCommitment(r.status), true,
    '판을 바꾼 적이 없는데 길을 막으면 안 된다');
});

t('S12 기록이 아예 없는 옛 사용자도 발행 뒤에 LEGACY 다', () => {
  const r = R.evaluateLegalReadiness({
    activeItems: [item('service_terms', '2026.08', true)],
    consent: {},
    publishedRevisionIds: published('service_terms__2026.08'),
  });
  assert.strictEqual(r.status, 'LEGACY_CONSENT_UNKNOWN');
  assert.strictEqual(R.allowsNewCommitment(r.status), true);
});

t('S13 1B 이후 사용자에게 새 필수 항목이 생기면 RECONSENT_REQUIRED', () => {
  const r = R.evaluateLegalReadiness({
    activeItems: [item('service_terms', '2026.08', true),
      item('new_required', '2026.11', true)],
    // 이 사람은 발행본을 가리키는 기록을 갖고 있다 — 1B 이후 사용자다.
    consent: acc('service_terms', '2026.08'),
    publishedRevisionIds: published('service_terms__2026.08',
      'new_required__2026.11'),
  });
  assert.strictEqual(r.status, 'RECONSENT_REQUIRED');
  assert.deepStrictEqual(r.reconsentRequired, ['new_required']);
  assert.strictEqual(R.allowsNewCommitment(r.status), false);
});

t('S14 다른 판에 동의한 기록이 있으면 새 판으로 센다', () => {
  const r = R.evaluateLegalReadiness({
    activeItems: [item('service_terms', '2026.11', true)],
    consent: acc('service_terms', '2026.08'),   // 식별 가능한 과거 동의
    publishedRevisionIds: published('service_terms__2026.11'),
  });
  assert.strictEqual(r.status, 'RECONSENT_REQUIRED');
  assert.deepStrictEqual(r.legacyUnknown, []);
});

// ── 소스 계약 ───────────────────────────────────────────────────────
t('S8 지원 직전에 canonical 판정을 소비한다', () => {
  const s = indexSrc();
  const i = s.indexOf('export const callableApplyToTO');
  assert.ok(i > 0);
  const body = s.slice(i, i + 20000);
  assert.ok(body.includes('srvLegalReadiness(uid)'), '지원 경로가 판정을 읽지 않는다');
  assert.ok(body.includes('lrAllowsNewCommitment'), '정책을 직접 비교하면 안 된다');
  assert.ok(body.includes('LEGAL_RECONSENT_REQUIRED'));
  // 조회 실패를 미동의로 바꾸지 않는다 — 통과시킨다.
  assert.ok(/catch \(e\) \{[\s\S]{0,200}?if \(e instanceof HttpsError\) throw e;/
    .test(body), '조회 실패가 지원을 막으면 안 된다');
});

t('S9 판정 읽기 경로는 인증을 요구하고 실패를 삼키지 않는다', () => {
  const s = indexSrc();
  const i = s.indexOf('export const callableGetLegalReadiness');
  assert.ok(i > 0, '판정 읽기 callable 이 없다');
  const body = s.slice(i, i + 1500);
  assert.ok(body.includes('if (!request.auth)'));
  assert.ok(body.includes('srvLegalReadiness(request.auth.uid)'),
    '호출자 본인 상태만 돌려줘야 한다');
  assert.ok(!/catch/.test(body), '조회 실패를 삼키면 모름이 정상으로 바뀐다');
});

t('S10 판정은 한 곳에서만 계산된다', () => {
  const s = indexSrc();
  // evaluate 를 부르는 곳은 서버 헬퍼 하나뿐이어야 한다.
  const calls = s.match(/lrEvaluate\(/g) || [];
  assert.strictEqual(calls.length, 1,
    `판정 계산이 ${calls.length} 곳에 있다 — 한 곳이어야 한다`);
});

console.log(`\n${pass} passed, ${fails.length} failed`);
if (fails.length) {
  for (const f of fails) console.log('  - ' + f);
  process.exit(1);
}
