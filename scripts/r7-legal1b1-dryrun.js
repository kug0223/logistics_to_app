/**
 * [R7-LEGAL.1B.1 §22] 새 consumer 가 배포됐다면 DEV 사용자가 어떻게
 * 분류될지 **읽기만으로** 미리 본다. 쓰기 0 · 배포 0.
 *
 *   판정은 서버와 **같은 모듈**을 불러서 한다 — 스크립트가 자기 규칙을
 *   따로 만들면 dry-run 이 실제와 다른 답을 말한다.
 *
 *   개인 식별값은 출력하지 않는다.
 */
'use strict';

const path = require('path');
const {db} = require('./r7-fixture-lib');
const R = require(path.join(__dirname, '..', 'functions', 'lib',
  'legal_readiness'));
const P = require(path.join(__dirname, '..', 'functions', 'lib',
  'legal_publication'));

(async () => {
  const termsSnap = await db.collection('app_settings').doc('legal_terms').get();
  const rawItems = termsSnap.data()?.items;
  const activeItems = (Array.isArray(rawItems) ? rawItems : [])
    .map((i) => ({
      id: String(i?.id ?? ''),
      version: String(i?.version ?? ''),
      revisionId: typeof i?.revisionId === 'string' && i.revisionId !== ''
        ? i.revisionId : undefined,
      isRequired: i?.isRequired !== false,
      isActive: i?.isActive !== false,
    }))
    .filter((i) => i.id && i.version && i.isActive);

  console.log('=== 활성 항목 ===');
  for (const i of activeItems) {
    console.log(`  ${i.id} | required=${i.isRequired} | version=${i.version}`,
      `| revisionId=${i.revisionId ?? '(없음 — 1B 이전)'}`);
  }

  const wanted = activeItems.map((i) =>
    i.revisionId ?? P.legalRevisionId(i.id, i.version));
  const published = new Set();
  if (wanted.length) {
    const snaps = await db.getAll(
      ...wanted.map((id) => db.collection('legal_revisions').doc(id)));
    for (const s of snaps) if (s.exists) published.add(s.id);
  }
  console.log('\n=== 발행본(legal_revisions) 실재 ===');
  console.log('  기대:', wanted.length, '| 실재:', published.size);
  if (published.size === 0) {
    console.log('  → 아직 새 발행 경로를 거친 항목이 없다.',
      '모든 사용자가 LEGACY_CONSENT_UNKNOWN 으로 분류된다(막지 않음).');
  }

  const users = await db.collection('users').get();
  const byStatus = {};
  let blocked = 0;
  users.forEach((d) => {
    const consent = d.data()?.termsConsent ?? {};
    const r = R.evaluateLegalReadiness({
      activeItems, consent,
      publishedRevisionIds: published,
    });
    byStatus[r.status] = (byStatus[r.status] ?? 0) + 1;
    if (!R.allowsNewCommitment(r.status)) blocked++;
  });

  console.log('\n=== dry-run 분류 (총', users.size, '명) ===');
  for (const [k, v] of Object.entries(byStatus)) console.log(`  ${k}: ${v}`);
  console.log('\n  새 약속(지원)이 막히는 사용자:', blocked);
  console.log('  홈 할 일이 뜨는 사용자      :',
    (byStatus['RECONSENT_REQUIRED'] ?? 0) +
    (byStatus['LEGACY_CONSENT_UNKNOWN'] ?? 0));

  console.log('\n(쓰기 0 — 이 스크립트는 읽기만 한다)');
  process.exit(0);
})().catch((e) => {
  console.error('실패:', e.message);
  process.exit(1);
});
