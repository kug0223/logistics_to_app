// [R7-PAYROLL-POLICY.5B.1] 필수 약관 발행본 무결성 — **행동** 테스트.
//
//   실행:  cd functions && npm run build && node test/legal_required_integrity.test.js
//
//   무엇이 틀려 있었나
//
//     `.5B` 는 발행본 포인터가 어긋나면 `verified:false` 로 말했다. 그런데
//       · 앱은 그 필드를 **읽지 않았다**
//       · 동의 writer 는 `legal_revisions` 를 **한 번도 읽지 않았다**
//     두 겹 모두 비어 있었다. 그래서 포인터가 가리키는 발행본이 사라져도
//     동의가 기록됐고, 그 기록의 `revisionId` 는 존재하지 않는 글을
//     가리켰다 — 사용자가 무엇에 동의했는지 영구히 말할 수 없다.
//
//     그리고 성질이 다른 두 상태가 같은 값으로 뭉개져 있었다.
//       legacy   포인터 자체가 없다(1B 이전). 막으면 옛 사용자 전원이 멈춘다.
//       mismatch 포인터는 있는데 가리키는 글이 없거나 다르다. 막아야 한다.
//
//   고정하는 것
//     RI-1  출처 분류 — legacy / published / mismatch
//     RI-2  필수 항목 무결성 판정 (legacy 통과, mismatch·빈 본문 차단)
//     RI-3  선택 항목 오류가 전체를 막지 않는다
//     RI-4  동의 writer 가 **독립적으로** 발행본을 확인한다
//     RI-5  callable 응답이 판정을 함께 내려 준다
//     RI-6  §9 매트릭스
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

function callableBody(name) {
  const s = indexSrc();
  const i = s.indexOf('export const ' + name);
  assert.ok(i > 0, name + ' 을 찾지 못했다');
  const j = s.indexOf('\nexport const ', i + 10);
  return s.slice(i, j > 0 ? j : s.length);
}

const ITEM = {
  id: 'privacy_policy', version: '2026-09-26',
  revisionId: 'privacy_policy__2026-09-26',
};
const GOOD_REV = {
  itemId: 'privacy_policy', version: '2026-09-26',
  title: '개인정보 처리방침', content: 'P 본문(발행본)', contentHash: 'hashP',
};

// ══════════════════════════════════════════════════════════════════
// RI-1  출처 분류
// ══════════════════════════════════════════════════════════════════

t('RI1-1 포인터가 가리키는 글이 맞으면 published', () => {
  assert.strictEqual(
    M.classifyRevisionProvenance({item: ITEM, revision: GOOD_REV}),
    'published');
});

t('RI1-2 포인터가 아예 없으면 legacy — 확인할 대상이 없다', () => {
  for (const rid of [undefined, null, '']) {
    assert.strictEqual(
      M.classifyRevisionProvenance({
        item: {...ITEM, revisionId: rid}, revision: undefined,
      }), 'legacy', String(rid));
  }
  // 포인터가 없으면 발행본이 **있어도** legacy 다 — 그 글을 가리킨다고
  // 말할 근거가 항목 쪽에 없다.
  assert.strictEqual(
    M.classifyRevisionProvenance({
      item: {...ITEM, revisionId: null}, revision: GOOD_REV,
    }), 'legacy');
});

t('RI1-3 포인터는 있는데 글이 없으면 mismatch', () => {
  assert.strictEqual(
    M.classifyRevisionProvenance({item: ITEM, revision: undefined}),
    'mismatch');
});

t('RI1-4 다른 항목·다른 버전을 가리키면 mismatch', () => {
  assert.strictEqual(
    M.classifyRevisionProvenance({
      item: ITEM,
      revision: {...GOOD_REV, itemId: 'location_terms'},
    }), 'mismatch', '다른 항목');
  assert.strictEqual(
    M.classifyRevisionProvenance({
      item: ITEM,
      revision: {...GOOD_REV, version: '2026.08'},
    }), 'mismatch', '다른 버전');
  assert.strictEqual(
    M.classifyRevisionProvenance({item: ITEM, revision: {}}),
    'mismatch', '빈 문서');
});

t('RI1-5 legacy 와 mismatch 가 구별된다 — 같은 값으로 뭉개지지 않는다', () => {
  const legacy = M.classifyRevisionProvenance({
    item: {...ITEM, revisionId: null}, revision: undefined,
  });
  const broken = M.classifyRevisionProvenance({
    item: ITEM, revision: undefined,
  });
  assert.notStrictEqual(legacy, broken,
    '`.5B` 에서는 둘 다 verified:false 였다');
});

// ══════════════════════════════════════════════════════════════════
// RI-2 / RI-3  필수 항목 무결성
// ══════════════════════════════════════════════════════════════════

const item = (id, required, provenance, content = '본문') =>
  ({itemId: id, isRequired: required, provenance, content});

t('RI2-1 필수가 전부 published 면 ok', () => {
  const v = M.evaluateRequiredIntegrity([
    item('service_terms', true, 'published'),
    item('privacy_policy', true, 'published'),
    item('marketing_consent', false, 'published'),
  ]);
  assert.strictEqual(v.ok, true);
  assert.deepStrictEqual(v.mismatched, []);
  assert.deepStrictEqual(v.empty, []);
});

t('RI2-2 필수 하나가 mismatch 면 ok:false', () => {
  const v = M.evaluateRequiredIntegrity([
    item('service_terms', true, 'published'),
    item('privacy_policy', true, 'mismatch'),
    item('privacy_third_party', true, 'published'),
  ]);
  assert.strictEqual(v.ok, false);
  assert.deepStrictEqual(v.mismatched, ['privacy_policy']);
});

t('RI2-3 legacy 는 통과시킨다 — 막으면 옛 사용자 전원이 멈춘다', () => {
  const v = M.evaluateRequiredIntegrity([
    item('service_terms', true, 'legacy'),
    item('privacy_policy', true, 'legacy'),
  ]);
  assert.strictEqual(v.ok, true,
    '1B 이전 항목은 사용자가 만든 상태가 아니다');
});

t('RI2-4 필수 본문이 비어 있으면 ok:false', () => {
  for (const body of ['', '   ', '\n\t ']) {
    const v = M.evaluateRequiredIntegrity([
      item('service_terms', true, 'published', body),
    ]);
    assert.strictEqual(v.ok, false, JSON.stringify(body));
    assert.deepStrictEqual(v.empty, ['service_terms']);
  }
  // 문자열이 아니어도 비어 있는 것으로 본다.
  const bad = M.evaluateRequiredIntegrity([
    {itemId: 'x', isRequired: true, provenance: 'published', content: null},
  ]);
  assert.strictEqual(bad.ok, false);
});

t('RI3-1 선택 항목 오류는 전체를 막지 않는다', () => {
  const v = M.evaluateRequiredIntegrity([
    item('service_terms', true, 'published'),
    item('marketing_consent', false, 'mismatch', ''),
  ]);
  assert.strictEqual(v.ok, true,
    '선택 하나가 깨졌다고 가입을 막으면 안 된다');
  assert.deepStrictEqual(v.mismatched, []);
  assert.deepStrictEqual(v.empty, []);
});

t('RI3-2 필수·선택이 섞여 깨지면 필수만 센다', () => {
  const v = M.evaluateRequiredIntegrity([
    item('service_terms', true, 'mismatch'),
    item('privacy_policy', true, 'published', ''),
    item('marketing_consent', false, 'mismatch', ''),
  ]);
  assert.deepStrictEqual(v.mismatched, ['service_terms']);
  assert.deepStrictEqual(v.empty, ['privacy_policy']);
  assert.strictEqual(v.ok, false);
});

t('RI3-3 빈 목록은 무결성 문제가 아니다 — 완전성은 다른 축이다', () => {
  const v = M.evaluateRequiredIntegrity([]);
  assert.strictEqual(v.ok, true,
    '필수가 하나도 없는 것은 앱의 hasRequiredItems 가 따로 막는다');
});

// ══════════════════════════════════════════════════════════════════
// RI-4  동의 writer 가 독립적으로 확인한다
// ══════════════════════════════════════════════════════════════════

/** `activeItems` 모양 하나. */
const act = (id, version, required, revisionId) =>
  ({id, version, isRequired: required, revisionId});

t('RI4-1 읽을 대상은 필수 + 포인터 있는 것뿐이다 — 최소 read', () => {
  const ptr = M.requiredRevisionPointers([
    act('service_terms', '2026.08', true, 'service_terms__2026.08'),
    act('privacy_policy', '2026-09-26', true, null),      // legacy
    act('marketing_consent', '2026.08', false, 'marketing_consent__2026.08'),
    act('location_terms', '2026.08', true, ''),            // 빈 포인터
  ]);
  assert.deepStrictEqual(ptr.map((p) => p.id), ['service_terms'],
    '선택 항목이나 포인터 없는 legacy 까지 읽고 있다');
  assert.strictEqual(ptr[0].revisionId, 'service_terms__2026.08');
  assert.strictEqual(ptr[0].version, '2026.08');
  // 아무것도 읽지 않아도 되는 경우
  assert.deepStrictEqual(M.requiredRevisionPointers([]), []);
  assert.deepStrictEqual(M.requiredRevisionPointers([
    act('a', 'v', true, undefined),
  ]), []);
});

t('RI4-2 발행본이 맞으면 통과한다', () => {
  const g = M.gateRequiredRevisions({
    pointers: [{id: 'privacy_policy', version: '2026-09-26',
      revisionId: 'privacy_policy__2026-09-26'}],
    revisions: new Map([['privacy_policy__2026-09-26', GOOD_REV]]),
  });
  assert.strictEqual(g.ok, true);
});

t('RI4-3 발행본이 없으면 거절하고 어느 항목인지 말한다', () => {
  const g = M.gateRequiredRevisions({
    pointers: [
      {id: 'service_terms', version: '2026.08',
        revisionId: 'service_terms__2026.08'},
      {id: 'privacy_policy', version: '2026-09-26',
        revisionId: 'privacy_policy__2026-09-26'},
    ],
    revisions: new Map([['service_terms__2026.08',
      {itemId: 'service_terms', version: '2026.08'}]]),
  });
  assert.strictEqual(g.ok, false);
  assert.strictEqual(g.reason, 'LEGAL_REQUIRED_REVISION_MISMATCH');
  assert.deepStrictEqual(g.itemIds, ['privacy_policy']);
});

t('RI4-4 다른 항목·다른 버전을 가리켜도 거절한다', () => {
  for (const rev of [
    {itemId: 'location_terms', version: '2026-09-26'},
    {itemId: 'privacy_policy', version: '2026.08'},
    {},
  ]) {
    const g = M.gateRequiredRevisions({
      pointers: [{id: 'privacy_policy', version: '2026-09-26',
        revisionId: 'privacy_policy__2026-09-26'}],
      revisions: new Map([['privacy_policy__2026-09-26', rev]]),
    });
    assert.strictEqual(g.ok, false, JSON.stringify(rev));
  }
});

t('RI4-5 확인할 것이 없으면 통과한다 — legacy 전원을 막지 않는다', () => {
  const g = M.gateRequiredRevisions({
    pointers: M.requiredRevisionPointers([
      act('service_terms', '2026.08', true, null),
      act('privacy_policy', '2026-09-26', true, undefined),
    ]),
    revisions: new Map(),
  });
  assert.strictEqual(g.ok, true,
    '1B 이전 항목은 사용자가 만든 상태가 아니다');
});

t('RI4-6 writer 가 그 둘을 쓰고, transaction 전에 멈춘다', () => {
  const body = callableBody('callableRecordTermsConsent');
  assert.ok(body.includes('lpRequiredRevisionPointers('),
    '읽을 대상을 writer 가 자기 규칙으로 고르고 있다');
  assert.ok(body.includes('lpGateRequiredRevisions('),
    '동의 writer 가 발행본을 확인하지 않는다 — 공개 목록만 믿고 있다');
  assert.ok(body.includes('collection("legal_revisions")'),
    '발행본을 읽지 않는다');
  assert.ok(body.includes('db.getAll('), '항목마다 따로 읽고 있다');
  const guard = body.indexOf('if (!revisionGate.ok)');
  const tx = body.indexOf('db.runTransaction(');
  assert.ok(guard > 0, '판정을 쓰지 않는다');
  assert.ok(tx > 0);
  assert.ok(guard < tx,
    '검증이 transaction 뒤에 있으면 부분 기록이 남을 수 있다');
  const slice = body.slice(guard, guard + 420);
  assert.ok(slice.includes('throw new HttpsError'), '거절하지 않는다');
  assert.ok(slice.includes('failed-precondition'));
  assert.ok(slice.includes('revisionGate.reason'), '이유 코드를 안 내려 준다');
  assert.ok(slice.includes('revisionGate.itemIds'),
    '어느 항목인지 말하지 않는다');
});

t('RI4-7 가드를 죽은 코드로 꺼 두지 않았다', () => {
  // 변이 I5·I10 이 `if (false)` / `&& false` 로 가드를 무력화하고 빠져나갔다.
  //   그 모양은 소스로 잡는다 — 호출 여부는 실행으로 확인할 수 없다.
  const body = callableBody('callableRecordTermsConsent');
  for (const dead of ['if (false', '&& false', '|| true', 'if (0 ',
    'return;  //']) {
    assert.ok(!body.includes(dead), `가드가 꺼져 있다: ${dead}`);
  }
  // 포인터 계산과 판정이 조건 없이 매번 실행된다.
  const p = body.indexOf('const requiredPointers =');
  const g = body.indexOf('const revisionGate =');
  assert.ok(p > 0 && g > p, '판정이 포인터 계산보다 앞에 있다');
  const between = body.slice(p, g);
  // 그 사이에 판정을 건너뛰게 하는 early return 이 없다.
  assert.ok(!/\n\s*return\s/.test(between), '판정 전에 빠져나가는 길이 있다');
});

// ══════════════════════════════════════════════════════════════════
// RI-5  callable 응답
// ══════════════════════════════════════════════════════════════════

t('RI5-1 응답에 판정이 함께 온다', () => {
  const body = callableBody('callableGetEffectiveLegalTerms');
  assert.ok(body.includes('lpEvaluateRequiredIntegrity('),
    '서버가 판정하지 않는다');
  assert.ok(body.includes('requiredIntegrity:'), '판정을 내려 주지 않는다');
  assert.ok(body.includes('mismatchedItemIds'));
  assert.ok(body.includes('emptyItemIds'));
});

t('RI5-2 항목마다 출처를 말한다', () => {
  const one = M.composeEffectiveLegalItem({
    item: ITEM, raw: {title: '사본', content: '사본 본문', order: 1},
    revision: undefined,
  });
  assert.strictEqual(one.provenance, 'mismatch');
  assert.strictEqual(one.verified, false);
  // `verified` 는 published 와 같은 뜻으로 남는다(공개 웹 계약 호환).
  const ok = M.composeEffectiveLegalItem({
    item: ITEM, raw: {order: 1}, revision: GOOD_REV,
  });
  assert.strictEqual(ok.provenance, 'published');
  assert.strictEqual(ok.verified, true);
  assert.strictEqual(ok.content, 'P 본문(발행본)');
});

t('RI5-3 앱이 판정을 읽는다', () => {
  const dart = fs.readFileSync(
    path.join(__dirname, '..', '..', 'lib', 'models', 'core',
      'legal_terms_model.dart'), 'utf8');
  assert.ok(dart.includes("'requiredIntegrity'"), '앱이 판정을 읽지 않는다');
  assert.ok(dart.includes('RequiredLegalIntegrity.parse'),
    '판정 해석기가 없다');
  // 판정이 없으면 "문제 없음" 으로 읽지 않는다.
  assert.ok(dart.includes('약관 무결성 판정이 응답에 없습니다'),
    '판정 누락을 조용히 통과시킨다');
  // 필수 완전성 검사가 판정과 묶여 있다.
  assert.ok(dart.includes('integrity.ok && activeItems.any'),
    'hasRequiredItems 가 판정을 보지 않는다');
});

// ══════════════════════════════════════════════════════════════════
// RI-6  §9 매트릭스
// ══════════════════════════════════════════════════════════════════

/** 서버가 내보낼 항목들 → 동의 가능 여부. */
function canConsent(items) {
  return M.evaluateRequiredIntegrity(items).ok;
}

t('RI6 §9 매트릭스', () => {
  const cases = [
    ['A1 모든 필수 정상', [
      item('service_terms', true, 'published'),
      item('privacy_policy', true, 'published'),
    ], true],
    ['A2 필수 한 건 실제 mismatch', [
      item('service_terms', true, 'published'),
      item('privacy_policy', true, 'mismatch'),
    ], false],
    ['A3 필수 revision 없음', [
      item('service_terms', true, 'mismatch'),
    ], false],
    ['A4 필수 본문 없음', [
      item('service_terms', true, 'published', ''),
    ], false],
    ['A5 itemId/revisionId 불일치', [
      // 분류 단계에서 mismatch 가 된다 (RI1-4)
      item('service_terms', true, 'mismatch'),
    ], false],
    ['B3 선택 한 건 오류', [
      item('service_terms', true, 'published'),
      item('marketing_consent', false, 'mismatch', ''),
    ], true],
    ['C1 정상 legacy 호환', [
      item('service_terms', true, 'legacy'),
      item('privacy_policy', true, 'legacy'),
    ], true],
    ['E1 필수 하나만 깨져도 부분 성공 금지', [
      item('service_terms', true, 'published'),
      item('privacy_policy', true, 'published'),
      item('privacy_third_party', true, 'mismatch'),
    ], false],
  ];
  for (const [label, items, want] of cases) {
    assert.strictEqual(canConsent(items), want, label);
  }
});

console.log(`\n${pass} passed, ${fails.length} failed`);
if (fails.length) {
  for (const f of fails) console.log('  - ' + f);
  process.exit(1);
}
