// [R7-LEGAL.1C] 공개 /terms · /privacy 가 현재 발행본을 읽는가 — **행동** 테스트.
//
//   실행:  cd functions && node test/public_legal_reader.test.js
//   (대상은 `public/legal-reader.js` 다. node 러너가 여기 있어 함께 둔다.)
//
//   고정하는 것
//     · 본문은 **발행본**에서 온다 — 고쳐 쓸 수 없는 쪽이 증거다
//     · 못 읽었으면 못 읽었다고 말한다 — 옛 전문을 현재 정책으로 위장하지 않는다
//     · 시행일·버전을 코드에 박지 않는다
//     · 앱과 공개 페이지가 같은 item id 를 본다
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', '..');
const L = require(path.join(ROOT, 'public', 'legal-reader.js'));

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

const read = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8');

// ── Firestore REST 모양 만들기 ───────────────────────────────────────
const sv = (s) => ({stringValue: s});
const bv = (b) => ({booleanValue: b});
const itemMap = (o) => ({
  mapValue: {
    fields: Object.assign(
      {
        id: sv(o.id), title: sv(o.title || ''), content: sv(o.content || ''),
        version: sv(o.version || ''), isRequired: bv(o.isRequired !== false),
        isActive: bv(o.isActive !== false),
      },
      o.revisionId ? {revisionId: sv(o.revisionId)} : {}),
  },
});
const termsDoc = (items) => ({
  fields: {items: {arrayValue: {values: items.map(itemMap)}}},
});
const revisionDoc = (o) => ({
  fields: {
    itemId: sv(o.itemId), version: sv(o.version), title: sv(o.title || ''),
    content: sv(o.content || ''),
    publishedAt: {timestampValue: o.publishedAt || '2026-10-06T00:00:00Z'},
  },
});

// ── Terms 1~5 ───────────────────────────────────────────────────────
t('PT1 현재 발행본의 본문을 보여 준다 — 본문 출처는 발행본이다', () => {
  const v = L.buildLegalView({
    itemId: 'service_terms',
    termsDoc: termsDoc([{
      id: 'service_terms', version: '2026.11',
      revisionId: 'service_terms__2026.11',
      content: '포인터에 남아 있는 사본',
    }]),
    revisionDoc: revisionDoc({
      itemId: 'service_terms', version: '2026.11',
      content: '발행본 전문',
    }),
  });
  assert.strictEqual(v.state, 'SUCCESS_CURRENT');
  assert.strictEqual(v.verified, true);
  assert.strictEqual(v.content, '발행본 전문');
  assert.strictEqual(v.revisionId, 'service_terms__2026.11');
});

t('PT2 버전·발행일은 발행본이 말한다 — 코드에 박지 않는다', () => {
  const v = L.buildLegalView({
    itemId: 'service_terms',
    termsDoc: termsDoc([{
      id: 'service_terms', version: '2026.11',
      revisionId: 'service_terms__2026.11',
    }]),
    revisionDoc: revisionDoc({
      itemId: 'service_terms', version: '2026.11',
      publishedAt: '2026-11-02T03:00:00Z',
    }),
  });
  const label = L.versionLabel(v);
  assert.ok(label.includes('버전 2026.11'), label);
  assert.ok(label.includes('2026-11-02'), label);
  assert.ok(!label.includes('2025'), '옛 시행일이 남아 있다');
});

t('PT3 옛 상수 fallback 이 소스에 없다', () => {
  // "예전에는 이랬다" 는 주석이 계약 판정을 흔들지 않게 코드만 본다.
  const codeOnly = (s) => s
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/<!--[\s\S]*?-->/g, ' ')
    .split('\n').filter((l) => !l.trimStart().startsWith('//')).join('\n');
  for (const p of ['public/terms.html', 'public/privacy.html',
    'public/legal-reader.js']) {
    const s = codeOnly(read(p));
    assert.ok(!s.includes('v2025.01'), `${p} 에 v2025.01 이 남아 있다`);
    assert.ok(!s.includes('2025년 1월 1일'), `${p} 에 옛 시행일이 남아 있다`);
  }
});

t('PT4 공개 중이 아닌 항목은 MISSING — 본문을 지어내지 않는다', () => {
  const gone = L.buildLegalView({
    itemId: 'service_terms',
    termsDoc: termsDoc([{id: 'privacy_policy', version: '1'}]),
  });
  assert.strictEqual(gone.state, 'MISSING');
  assert.strictEqual(gone.content, undefined);

  const inactive = L.buildLegalView({
    itemId: 'service_terms',
    termsDoc: termsDoc([{id: 'service_terms', version: '1', isActive: false}]),
  });
  assert.strictEqual(inactive.state, 'MISSING');
});

t('PT5 조회 실패는 ERROR 다 — 옛 전문을 현재 정책으로 위장하지 않는다', () => {
  const v = L.buildLegalView({
    itemId: 'service_terms', fetchError: new Error('network'),
  });
  assert.strictEqual(v.state, 'ERROR');
  assert.strictEqual(v.content, undefined);
  assert.strictEqual(L.versionLabel(v), '', '실패 상태에 버전 라벨을 달지 않는다');
});

// ── Privacy 6~9 ─────────────────────────────────────────────────────
t('PP6 privacy 도 같은 reader·같은 계약을 쓴다', () => {
  const v = L.buildLegalView({
    itemId: 'privacy_policy',
    termsDoc: termsDoc([{
      id: 'privacy_policy', version: '2026-09-26',
      revisionId: 'privacy_policy__2026-09-26',
    }]),
    revisionDoc: revisionDoc({
      itemId: 'privacy_policy', version: '2026-09-26', content: '처리방침 전문',
    }),
  });
  assert.strictEqual(v.state, 'SUCCESS_CURRENT');
  assert.strictEqual(v.content, '처리방침 전문');
});

t('PP7 정적 전문이 제거됐다 — 수동 복사 단계가 남지 않았다', () => {
  const s = read('public/privacy.html');
  assert.ok(s.includes('legal-reader.js'), 'reader 를 쓰지 않는다');
  assert.ok(s.includes("itemId: 'privacy_policy'"));
  // 253줄짜리 조문 본문이 다시 들어오면 길이로 먼저 걸린다.
  assert.ok(s.length < 2500, `정적 본문이 남아 있다 (${s.length}B)`);
  assert.ok(!s.includes('수집하는 개인정보'), '조문 전문이 하드코딩돼 있다');
  assert.ok(!/시행일\s*\d{4}년/.test(s), '시행일이 박혀 있다');
});

t('PP8/PT-mismatch 포인터가 가리키는 발행본이 없으면 본문을 내지 않는다', () => {
  const missing = L.buildLegalView({
    itemId: 'privacy_policy',
    termsDoc: termsDoc([{
      id: 'privacy_policy', version: '1', revisionId: 'privacy_policy__1',
      content: '포인터 사본',
    }]),
    revisionDoc: null,
  });
  assert.strictEqual(missing.state, 'REVISION_MISMATCH');
  assert.strictEqual(missing.content, undefined);

  const wrong = L.buildLegalView({
    itemId: 'privacy_policy',
    termsDoc: termsDoc([{
      id: 'privacy_policy', version: '2', revisionId: 'privacy_policy__2',
    }]),
    revisionDoc: revisionDoc({itemId: 'privacy_policy', version: '1'}),
  });
  assert.strictEqual(wrong.state, 'REVISION_MISMATCH');
});

t('PP9 아직 발행본이 없는 항목은 공개하되 검증되지 않았다고 말한다', () => {
  // DEV 현황이 이것이다 — 5개 항목 전부 revisionId 가 없다.
  const v = L.buildLegalView({
    itemId: 'service_terms',
    termsDoc: termsDoc([{
      id: 'service_terms', version: '2026.08', content: '현재 전문',
    }]),
  });
  assert.strictEqual(v.state, 'SUCCESS_CURRENT');
  assert.strictEqual(v.verified, false);
  assert.strictEqual(v.content, '현재 전문');
  assert.ok(L.versionLabel(v).includes('발행본 미등록'));
});

// ── Cross-surface 10~13 ─────────────────────────────────────────────
t('PX10 공개 페이지와 앱이 같은 item id 를 본다', () => {
  const model = read('lib/models/core/legal_terms_model.dart');
  for (const [page, id] of [
    ['public/terms.html', 'service_terms'],
    ['public/privacy.html', 'privacy_policy'],
  ]) {
    assert.ok(read(page).includes(`itemId: '${id}'`), `${page} 가 ${id} 를 안 본다`);
    assert.ok(model.includes(`id: '${id}'`), `앱 모델에 ${id} 가 없다`);
  }
});

t('PX11 공개 페이지는 projection 을 포인터로만 쓴다', () => {
  const s = read('public/legal-reader.js');
  assert.ok(s.includes('app_settings/legal_terms'), 'current pointer 를 안 읽는다');
  assert.ok(s.includes('legal_revisions/'), '발행본을 안 읽는다');
  // 발행본이 있으면 본문은 거기서 온다.
  assert.ok(s.includes('content: rev.content'), '본문 출처가 발행본이 아니다');
});

t('PX12 공개 페이지는 발행본을 쓰지 않는다 — 읽기 전용이다', () => {
  const s = read('public/legal-reader.js') + read('public/terms.html') +
    read('public/privacy.html');
  for (const bad of ['PATCH', 'DELETE', ':commit', 'method: \'POST\'',
    'method: "POST"']) {
    assert.ok(!s.includes(bad), `쓰기 경로가 있다: ${bad}`);
  }
});

t('PX13 URL 은 그대로다 — 외부 링크를 깨지 않는다', () => {
  for (const p of ['public/terms.html', 'public/privacy.html',
    'public/account-deletion.html', 'public/index.html']) {
    assert.ok(fs.existsSync(path.join(ROOT, p)), `${p} 가 사라졌다`);
  }
  const cfg = JSON.parse(read('firebase.json').replace(/^﻿/, ''));
  assert.strictEqual(cfg.hosting.public, 'public');
  assert.strictEqual(cfg.hosting.cleanUrls, true,
    'cleanUrls 가 꺼지면 /terms 가 깨진다');
});

// ── Security 14~16 ──────────────────────────────────────────────────
t('PS14 비로그인도 현재 법적 문서를 읽을 수 있다', () => {
  const r = read('firestore.rules')
    .split('\n').filter((l) => !l.trimStart().startsWith('//')).join('\n');
  assert.ok(r.includes("allow read: if docId == 'legal_terms' || isLoggedIn();"),
    'legal_terms 공개 읽기가 없다');
  const i = r.indexOf('match /legal_revisions/{revisionId} {');
  assert.ok(i > 0);
  const block = r.slice(i, i + 200);
  assert.ok(block.includes('allow read: if true;'), '발행본 공개 읽기가 없다');
});

t('PS15 비로그인 쓰기는 막혀 있다', () => {
  const r = read('firestore.rules')
    .split('\n').filter((l) => !l.trimStart().startsWith('//')).join('\n');
  const i = r.indexOf('match /legal_revisions/{revisionId} {');
  const block = r.slice(i, r.indexOf('match ', i + 10));
  assert.ok(block.includes('allow write: if false;'));
});

t('PS16 공개되는 것은 발행본뿐이다 — draft 개념이 없다', () => {
  const s = read('functions/src/index.ts');
  const i = s.indexOf('export const callablePublishLegalRevision');
  const body = s.slice(i, i + 5000);
  // 발행 외의 상태를 legal_revisions 에 쓰지 않는다.
  assert.ok(!/status:\s*["']DRAFT["']/.test(body));
  assert.ok(!/isDraft/.test(body));
  assert.ok(body.includes('publishedAt'), '발행 시각이 없다');
});

// ── 렌더 경로 (DOM glue) ────────────────────────────────────────────
//
//   `buildLegalView` 만 재면 "판정은 맞는데 화면에 안 그려지는" 경우를
//   놓친다. 가짜 document·fetch 로 실제 그리는 경로까지 돌린다.
function fakeDom() {
  const nodes = {
    'content-card': {innerHTML: ''},
    'version-info': {textContent: ''},
  };
  globalThis.document = {getElementById: (id) => nodes[id] || null};
  return nodes;
}

function fakeFetch(routes) {
  globalThis.fetch = async (url) => {
    for (const [frag, body] of routes) {
      if (url.includes(frag)) {
        if (body instanceof Error) throw body;
        return {ok: true, json: async () => body};
      }
    }
    return {ok: false, status: 404, json: async () => ({})};
  };
}

async function runAsync(id, fn) {
  try {
    await fn();
    pass++;
    console.log(`  ok   ${id}`);
  } catch (e) {
    fails.push(`${id}: ${e.message.split('\n')[0]}`);
    console.log(`  FAIL ${id} — ${e.message.split('\n')[0]}`);
  }
}

(async () => {
  await runAsync('PR1 성공하면 본문과 버전 라벨이 그려진다', async () => {
    const nodes = fakeDom();
    fakeFetch([
      ['/__/firebase/init.json', {projectId: 'p', apiKey: 'k'}],
      ['app_settings/legal_terms', termsDoc([{
        id: 'service_terms', version: '2026.11',
        revisionId: 'service_terms__2026.11',
      }])],
      ['legal_revisions/', revisionDoc({
        itemId: 'service_terms', version: '2026.11', content: '본문 <b>이스케이프</b>',
      })],
    ]);
    const v = await L.loadAndRender({itemId: 'service_terms'});
    assert.strictEqual(v.state, 'SUCCESS_CURRENT');
    assert.ok(nodes['content-card'].innerHTML.includes('content-text'));
    assert.ok(nodes['content-card'].innerHTML.includes('&lt;b&gt;'),
      'HTML 을 그대로 넣으면 안 된다');
    assert.ok(nodes['version-info'].textContent.includes('버전 2026.11'));
  });

  await runAsync('PR2 실패하면 오류만 그린다 — 본문도 버전도 없다', async () => {
    const nodes = fakeDom();
    fakeFetch([['/__/firebase/init.json', new Error('offline')]]);
    const v = await L.loadAndRender({itemId: 'service_terms'});
    assert.strictEqual(v.state, 'ERROR');
    assert.ok(nodes['content-card'].innerHTML.includes('class="error"'));
    assert.ok(!nodes['content-card'].innerHTML.includes('content-text'));
    assert.strictEqual(nodes['version-info'].textContent, '',
      '실패에 버전 라벨을 달면 현재 정책처럼 보인다');
  });

  await runAsync('PR3 발행본 조회가 실패하면 포인터 사본을 대신 쓰지 않는다',
    async () => {
      const nodes = fakeDom();
      fakeFetch([
        ['/__/firebase/init.json', {projectId: 'p', apiKey: 'k'}],
        ['app_settings/legal_terms', termsDoc([{
          id: 'service_terms', version: '1', revisionId: 'service_terms__1',
          content: '포인터에 남은 사본',
        }])],
        ['legal_revisions/', new Error('boom')],
      ]);
      const v = await L.loadAndRender({itemId: 'service_terms'});
      assert.strictEqual(v.state, 'REVISION_MISMATCH');
      assert.ok(!nodes['content-card'].innerHTML.includes('포인터에 남은 사본'));
    });

  console.log(`\n${pass} passed, ${fails.length} failed`);
  if (fails.length) {
    for (const f of fails) console.log('  - ' + f);
    process.exit(1);
  }
})();
if (fails.length) {
  for (const f of fails) console.log('  - ' + f);
  process.exit(1);
}
