/**
 * [R7-LEGAL.DEPLOY §10·§11] 공개 페이지가 읽는 **바로 그 경로**를 익명으로
 * 그대로 타서, 앱 projection 과 같은 발행본을 말하는지 확인한다. READ ONLY.
 *
 *   curl 은 JS 를 실행하지 않는다. 그래서 `legal-reader.js` 가 하는 일을
 *   그대로 한다 — init.json → projection → revision → buildLegalView.
 *   실제 reader 모듈을 불러서 쓴다(스크립트가 자기 규칙을 만들지 않는다).
 */
'use strict';

const https = require('https');
const path = require('path');
const crypto = require('crypto');
const {db} = require('./r7-fixture-lib');
const L = require(path.join(__dirname, '..', 'public', 'legal-reader.js'));

const HOST = 'alfit-89567.web.app';
const sha12 = (s) => crypto.createHash('sha256').update(s, 'utf8')
  .digest('hex').slice(0, 12);

function get(host, p) {
  return new Promise((resolve) => {
    https.get({host, path: p}, (res) => {
      // [중요] 청크를 그대로 이어 붙이면 멀티바이트 문자가 청크 경계에서
      //   깨진다(한글·■ 등). setEncoding 이 경계를 처리한다.
      res.setEncoding('utf8');
      let d = '';
      res.on('data', (c) => (d += c));
      res.on('end', () => resolve({status: res.statusCode, body: d}));
    }).on('error', (e) => resolve({status: -1, body: String(e)}));
  });
}

(async () => {
  console.log('=== 공개 reader 가 하는 일을 그대로 (익명) ===');
  const init = await get(HOST, '/__/firebase/init.json');
  if (init.status !== 200) throw new Error('init.json 실패 ' + init.status);
  const cfg = JSON.parse(init.body);
  const fsBase = `/v1/projects/${cfg.projectId}/databases/(default)/documents`;

  const terms = await get('firestore.googleapis.com',
    `${fsBase}/app_settings/legal_terms?key=${cfg.apiKey}`);
  console.log('  projection 익명 읽기:', terms.status);
  const termsDoc = JSON.parse(terms.body);

  let pass = 0;
  const fails = [];
  for (const [page, itemId] of [['/terms', 'service_terms'],
    ['/privacy', 'privacy_policy']]) {
    const item = L.pickItem(termsDoc, itemId);
    if (!item) { fails.push(`${page} projection 항목 없음`); continue; }

    const rev = await get('firestore.googleapis.com',
      `${fsBase}/legal_revisions/${encodeURIComponent(item.revisionId)}` +
      `?key=${cfg.apiKey}`);
    const view = L.buildLegalView({
      termsDoc, revisionDoc: rev.status === 200 ? JSON.parse(rev.body) : null,
      itemId,
    });

    // 앱이 읽는 projection(Admin SDK)과 비교한다.
    const appSnap = await db.collection('app_settings').doc('legal_terms').get();
    const appItem = (appSnap.data()?.items ?? [])
      .find((i) => String(i.id) === itemId);

    const checks = {
      '발행본 익명 읽기': rev.status === 200,
      'state=SUCCESS_CURRENT': view.state === 'SUCCESS_CURRENT',
      'verified': view.verified === true,
      'version 동일(app↔public)': view.version === String(appItem?.version),
      'revisionId 동일': view.revisionId === String(appItem?.revisionId),
      'content 동일': sha12(view.content ?? '') ===
        sha12(String(appItem?.content ?? '')),
      '본문 비어있지 않음': (view.content ?? '').length > 100,
    };
    const bad = Object.entries(checks).filter(([, v]) => !v).map(([k]) => k);
    if (bad.length === 0) pass++; else fails.push(`${page}: ${bad.join(', ')}`);

    console.log(`\n  ${page}`);
    console.log('    version   :', view.version);
    console.log('    revisionId:', view.revisionId);
    console.log('    라벨      :', L.versionLabel(view));
    console.log('    본문 길이 :', (view.content ?? '').length,
      '| hash:', sha12(view.content ?? ''));
    console.log('    판정      :', bad.length ? `FAIL(${bad.join(', ')})` : 'PASS');
  }

  console.log('\n=== 전달 바이트에 옛 상수 없음 ===');
  for (const p of ['/terms', '/privacy']) {
    const r = await get(HOST, p);
    const stale = /v2025\.01|2025년 1월 1일/.test(r.body);
    console.log(`  ${p.padEnd(10)} ${r.status} | 옛 상수:`, stale ? '**있음**' : '없음');
    if (stale) fails.push(`${p} 옛 상수`);
  }

  console.log(`\n${pass}/2 페이지 PASS`);
  for (const f of fails) console.log('  - ' + f);
  process.exit(fails.length ? 1 : 0);
})().catch((e) => {
  console.error('실패:', e.message);
  process.exit(1);
});
