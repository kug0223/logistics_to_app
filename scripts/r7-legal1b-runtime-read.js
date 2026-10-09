/**
 * [R7-LEGAL.1B §2 · §22] DEV 런타임 확인 — **READ ONLY. 쓰기 0.**
 *
 *   확인하는 것
 *     · `app_settings/legal_terms` 존재 · items · active 개수
 *     · id 중복 · 빈 content · version 중복 의미
 *     · users 의 동의 population (집계만)
 *
 *   개인 식별값은 출력하지 않는다 — uid·이름·연락처 전부 쓰지 않는다.
 *   항목 본문도 출력하지 않고 길이와 해시 앞자리만 본다.
 */
'use strict';

const crypto = require('crypto');
const {db} = require('./r7-fixture-lib');

const sha12 = (s) =>
  crypto.createHash('sha256').update(s, 'utf8').digest('hex').slice(0, 12);

(async () => {
  console.log('=== [1] app_settings/legal_terms ===');
  const snap = await db.collection('app_settings').doc('legal_terms').get();
  if (!snap.exists) {
    console.log('  문서 존재: **NO** → BLOCKER CONFIRMED');
    process.exit(0);
  }
  const data = snap.data() || {};
  const items = Array.isArray(data.items) ? data.items : null;
  console.log('  문서 존재: YES');
  console.log('  updatedAt :', data.updatedAt ? 'present' : '(없음)');
  console.log('  updatedBy :', data.updatedBy ?? '(없음)');
  if (!items) {
    console.log('  items[] : **배열 아님/없음** → BLOCKER CONFIRMED');
    process.exit(0);
  }
  console.log('  items 개수:', items.length);

  const ids = [];
  const activeItems = [];
  for (const it of items) {
    const id = String(it?.id ?? '');
    const version = String(it?.version ?? '');
    const content = typeof it?.content === 'string' ? it.content : '';
    const isActive = it?.isActive !== false;
    const isRequired = it?.isRequired !== false;
    ids.push(id);
    if (isActive) activeItems.push({id, version});
    console.log(
      `   - id=${id || '(빈값)'}`,
      `| active=${isActive}`,
      `| required=${isRequired}`,
      `| version=${version || '(빈값)'}`,
      `| contentLen=${content.length}`,
      `| contentHash=${content ? sha12(content) : '(빈본문)'}`,
      `| order=${it?.order ?? '(없음)'}`);
  }

  const dupIds = ids.filter((v, i) => ids.indexOf(v) !== i);
  console.log('  active 개수:', activeItems.length);
  console.log('  중복 id :', dupIds.length ? [...new Set(dupIds)] : '없음');
  console.log('  빈 content 항목:',
    items.filter((i) => !String(i?.content ?? '').trim()).length);
  const emptyVersion = items.filter((i) => !String(i?.version ?? '').trim());
  console.log('  빈 version 항목:', emptyVersion.length);

  // 같은 version 문자열을 쓰는 서로 다른 item 이 있는가 (의미 충돌 아님,
  // 다만 version 이 전역 식별자가 아님을 보여 준다).
  const byVersion = {};
  for (const it of items) {
    const v = String(it?.version ?? '');
    (byVersion[v] ||= []).push(String(it?.id ?? ''));
  }
  for (const [v, list] of Object.entries(byVersion)) {
    if (list.length > 1) {
      console.log(`  version "${v}" 를 공유하는 item: ${list.join(', ')}`);
    }
  }

  console.log('\n=== [2] users 동의 population (집계만) ===');
  const users = await db.collection('users').get();
  const activeIds = activeItems.map((i) => i.id);
  const stat = {
    total: 0, noConsentMap: 0, noConsentAt: 0,
    partial: 0, full: 0,
    marketingTrue: 0, marketingFalse: 0, marketingAbsent: 0,
    malformed: 0,
  };
  const byItemVersion = {};   // itemId → {version → count}
  const roleStat = {};

  users.forEach((d) => {
    const u = d.data() || {};
    stat.total++;
    roleStat[u.role ?? '(없음)'] = (roleStat[u.role ?? '(없음)'] ?? 0) + 1;
    if (!u.termsConsentAt) stat.noConsentAt++;
    const tc = u.termsConsent;
    if (!tc || typeof tc !== 'object' || Array.isArray(tc)) {
      stat.noConsentMap++;
      stat.marketingAbsent++;
      return;
    }
    let present = 0;
    for (const id of activeIds) {
      const rec = tc[id];
      if (!rec || typeof rec !== 'object') continue;
      if (typeof rec.agreed !== 'boolean') { stat.malformed++; continue; }
      present++;
      const v = String(rec.version ?? '(없음)');
      ((byItemVersion[id] ||= {})[v] ??= 0);
      byItemVersion[id][v]++;
    }
    if (present === 0) stat.noConsentMap++;
    else if (present < activeIds.length) stat.partial++;
    else stat.full++;

    const mk = tc['marketing_consent'];
    if (!mk || typeof mk.agreed !== 'boolean') stat.marketingAbsent++;
    else if (mk.agreed) stat.marketingTrue++;
    else stat.marketingFalse++;
  });

  console.log('  total users        :', stat.total);
  console.log('  role 분포          :', JSON.stringify(roleStat));
  console.log('  termsConsentAt 없음:', stat.noConsentAt);
  console.log('  consent 없음       :', stat.noConsentMap);
  console.log('  partial            :', stat.partial);
  console.log('  full               :', stat.full);
  console.log('  malformed 항목     :', stat.malformed);
  console.log('  marketing true     :', stat.marketingTrue);
  console.log('  marketing false    :', stat.marketingFalse);
  console.log('  marketing 기록없음 :', stat.marketingAbsent);
  console.log('\n  item 별 version 분포:');
  for (const [id, vmap] of Object.entries(byItemVersion)) {
    console.log(`   - ${id}:`, JSON.stringify(vmap));
  }

  console.log('\n(쓰기 0 — 이 스크립트는 읽기만 한다)');
  process.exit(0);
})().catch((e) => {
  console.error('실패:', e.message);
  process.exit(1);
});
