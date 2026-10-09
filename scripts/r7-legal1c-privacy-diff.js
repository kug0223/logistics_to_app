/**
 * [R7-LEGAL.1C §10] 공개 `/privacy` 정적 전문과 canonical `privacy_policy`
 * 를 **실제로** 비교한다. 버전 라벨 비교가 아니다. READ ONLY · 쓰기 0.
 *
 *   본문 전문은 출력하지 않는다 — 길이·해시·문단 단위 차이만 본다.
 */
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const {db} = require('./r7-fixture-lib');

const sha12 = (s) =>
  crypto.createHash('sha256').update(s, 'utf8').digest('hex').slice(0, 12);

/** HTML 에서 사람이 읽는 텍스트만 뽑는다. */
function htmlToText(html) {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/(p|div|h1|h2|h3|li|tr)>/gi, '\n')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>');
}

const norm = (s) => s
  .split('\n')
  .map((l) => l.replace(/\s+/g, ' ').trim())
  .filter((l) => l.length > 0);

(async () => {
  const snap = await db.collection('app_settings').doc('legal_terms').get();
  const items = (snap.data()?.items ?? []);
  const item = items.find((i) => String(i?.id ?? '') === 'privacy_policy');
  if (!item) {
    console.log('canonical privacy_policy 없음 → 비교 불가');
    process.exit(0);
  }
  const canonical = String(item.content ?? '');

  const htmlPath = path.join(__dirname, '..', 'public', 'privacy.html');
  const publicText = htmlToText(fs.readFileSync(htmlPath, 'utf8'));

  const a = norm(canonical);
  const b = norm(publicText);

  console.log('=== 길이 ===');
  console.log('  canonical(Firestore) chars:', canonical.length,
    '| 줄:', a.length, '| hash:', sha12(canonical));
  console.log('  public/privacy.html  chars:', publicText.length,
    '| 줄:', b.length, '| hash:', sha12(publicText));

  const setA = new Set(a);
  const setB = new Set(b);
  const onlyA = a.filter((l) => !setB.has(l));
  const onlyB = b.filter((l) => !setA.has(l));
  const shared = a.filter((l) => setB.has(l));

  console.log('\n=== 문단(줄) 단위 ===');
  console.log('  공통         :', shared.length);
  console.log('  canonical 전용:', onlyA.length);
  console.log('  public 전용   :', onlyB.length);

  const overlap = a.length === 0 ? 0 : shared.length / a.length;
  console.log('  canonical 覆盖율:', (overlap * 100).toFixed(1) + '%');

  let verdict;
  if (onlyA.length === 0 && onlyB.length === 0) verdict = 'IDENTICAL';
  else if (overlap >= 0.6) verdict = 'CONTENT-DIVERGENT';
  else verdict = 'STRUCTURE-DIVERGENT';
  console.log('\n판정:', verdict);

  // 어떤 성격의 차이인지 **머리말만** 보여 준다(전문 미출력).
  const head = (arr, n) => arr.slice(0, n)
    .map((l) => '    · ' + (l.length > 60 ? l.slice(0, 60) + '…' : l));
  if (onlyA.length) {
    console.log('\n  canonical 에만 있는 줄 (상위 6):');
    console.log(head(onlyA, 6).join('\n'));
  }
  if (onlyB.length) {
    console.log('\n  public 에만 있는 줄 (상위 6):');
    console.log(head(onlyB, 6).join('\n'));
  }

  console.log('\n(쓰기 0)');
  process.exit(0);
})().catch((e) => {
  console.error('실패:', e.message);
  process.exit(1);
});
