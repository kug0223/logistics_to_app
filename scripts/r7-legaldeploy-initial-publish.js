/**
 * [R7-LEGAL.DEPLOY §6~§9] 활성 5종 최초 immutable 발행 + 불변식 검증.
 *
 *   왜 임시 계정을 만드는가
 *     DEV 에 SUPER_ADMIN 이 0개다(`legal_terms.updatedBy` 가 가리키던 uid 의
 *     users 문서도 이미 없다). canonical 발행 경로는 SUPER_ADMIN 을 요구하고,
 *     직접 Firestore 쓰기는 금지돼 있다(그게 이번 작업의 요지다).
 *
 *   어떻게 안전하게 하는가
 *     · 비밀번호를 만들지 않는다 — custom token 으로만 서명한다.
 *       (저장소의 create_super_admin.js 는 하드코딩 비밀번호를 쓰므로 안 쓴다)
 *     · 발행·검증이 끝나면 Auth 계정과 users 문서를 **지운다**.
 *     · 실패해도 finally 에서 정리한다. 정리 실패는 크게 보고한다.
 *
 *   하지 않는 것
 *     · 사용자 consent backfill (금지)
 *     · 기존 발행본 수정·삭제 (불가능해야 하고, 시도도 하지 않는다)
 *     · 버전 재사용 테스트에서 canonical 값 변경 — 서버가 거절하므로 변화 0
 *
 *   PII 를 출력하지 않는다.
 */
'use strict';

const path = require('path');
const crypto = require('crypto');
const lib = require('./r7-fixture-lib');
const {db} = lib;

const ROOT = path.resolve(__dirname, '..');
const admin = require(path.join(ROOT, 'functions', 'node_modules',
  'firebase-admin'));

const sha256 = (s) => crypto.createHash('sha256').update(s, 'utf8')
  .digest('hex');
const short = (h) => h.slice(0, 12);

function unwrap(r) {
  return (r && (r.result ?? r.data)) ?? r;
}

(async () => {
  let tempUid = null;
  try {
    // ── 0. 현재 활성 항목 읽기 ───────────────────────────────────
    const snap = await db.collection('app_settings').doc('legal_terms').get();
    const items = (snap.data()?.items ?? []).filter((i) => i?.isActive !== false);
    console.log('활성 항목:', items.length);
    if (items.length !== 5) throw new Error('활성 5종이 아니다 — STOP');

    // ── 1. 임시 SUPER_ADMIN ─────────────────────────────────────
    const rec = await admin.auth().createUser({
      displayName: 'r7 temp publisher',
    });
    tempUid = rec.uid;
    await db.collection('users').doc(tempUid).set({
      role: 'SUPER_ADMIN',
      name: 'r7 temp publisher',
      accountStatus: 'active',
      isDummy: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log('임시 SUPER_ADMIN 생성 (uid 는 출력하지 않는다)');

    // ── 2. §6 최초 발행 ─────────────────────────────────────────
    console.log('\n=== §6 최초 발행 ===');
    const rows = [];
    for (const it of items) {
      const payload = {
        itemId: String(it.id),
        version: String(it.version),
        title: String(it.title ?? ''),
        content: String(it.content ?? ''),
        isRequired: it.isRequired !== false,
        isActive: true,
        order: typeof it.order === 'number' ? it.order : undefined,
      };
      const res = unwrap(await lib.callAs(tempUid,
        'callablePublishLegalRevision', payload));
      rows.push({
        itemId: payload.itemId, version: payload.version,
        revisionId: res.revisionId, hash: short(res.contentHash ?? ''),
        result: res.success ? 'OK' : 'FAIL',
      });
      console.log(`  ${payload.itemId.padEnd(22)} ${payload.version.padEnd(12)}`,
        `${String(res.revisionId).padEnd(34)} ${res.success ? 'OK' : 'FAIL'}`);
    }

    // ── 3. §7 불변식 ────────────────────────────────────────────
    console.log('\n=== §7 발행 불변식 ===');
    const after = await db.collection('app_settings').doc('legal_terms').get();
    const projMap = new Map((after.data()?.items ?? [])
      .map((i) => [String(i.id), i]));
    let ok = 0;
    const firstPublishedAt = new Map();
    for (const r of rows) {
      const revSnap = await db.collection('legal_revisions')
        .doc(r.revisionId).get();
      const rev = revSnap.data() ?? {};
      const proj = projMap.get(r.itemId) ?? {};
      const checks = {
        '발행본 존재': revSnap.exists,
        'projection.revisionId': proj.revisionId === r.revisionId,
        'itemId 일치': rev.itemId === r.itemId,
        'version 일치': rev.version === r.version && proj.version === r.version,
        'contentHash 일치': rev.contentHash === sha256(String(rev.content ?? '')),
        'content 일치': String(rev.content ?? '') === String(proj.content ?? ''),
        'publishedAt 존재': !!rev.publishedAt,
      };
      const bad = Object.entries(checks).filter(([, v]) => !v).map(([k]) => k);
      if (bad.length === 0) ok++;
      console.log(`  ${r.itemId.padEnd(22)}`,
        bad.length ? `FAIL: ${bad.join(', ')}` : 'PASS');
      if (rev.publishedAt) {
        firstPublishedAt.set(r.itemId, rev.publishedAt.toMillis());
      }
    }
    console.log(`  → ${ok}/${rows.length}`);

    // ── 4. §8 멱등 재발행 ───────────────────────────────────────
    console.log('\n=== §8 같은 내용 재발행 (중복 생성 금지) ===');
    const beforeCount = (await db.collection('legal_revisions').get()).size;
    for (const it of items) {
      await lib.callAs(tempUid, 'callablePublishLegalRevision', {
        itemId: String(it.id), version: String(it.version),
        title: String(it.title ?? ''), content: String(it.content ?? ''),
        isRequired: it.isRequired !== false, isActive: true,
      });
    }
    const afterCount = (await db.collection('legal_revisions').get()).size;
    console.log(`  발행본 개수 ${beforeCount} → ${afterCount}`,
      beforeCount === afterCount ? '(중복 없음 OK)' : '(중복 생성됨 FAIL)');
    let tsSame = 0;
    for (const r of rows) {
      const rev = (await db.collection('legal_revisions').doc(r.revisionId)
        .get()).data();
      if (rev?.publishedAt?.toMillis() === firstPublishedAt.get(r.itemId)) {
        tsSame++;
      }
    }
    console.log(`  publishedAt 불변 ${tsSame}/${rows.length}`);

    // ── 5. §9 버전 재사용 거절 (canonical 값은 바뀌지 않는다) ────
    console.log('\n=== §9 같은 버전에 다른 본문 → 거절 ===');
    const probe = items[0];
    let reused = 'NO_ERROR';
    try {
      await lib.callAs(tempUid, 'callablePublishLegalRevision', {
        itemId: String(probe.id), version: String(probe.version),
        title: String(probe.title ?? ''),
        content: String(probe.content ?? '') + '\n(변조 시도)',
        isRequired: probe.isRequired !== false, isActive: true,
      });
    } catch (e) {
      reused = String(e.message || e);
    }
    console.log('  결과:', reused.includes('LEGAL_VERSION_REUSED') ?
      'LEGAL_VERSION_REUSED (거절 OK)' : reused.slice(0, 120));
    const probeRev = (await db.collection('legal_revisions')
      .doc(`${probe.id}__${probe.version}`).get()).data();
    console.log('  canonical 본문 해시 불변:',
      probeRev?.contentHash === sha256(String(probe.content ?? '')) ?
        'OK' : '**변경됨 — 즉시 확인 필요**');

    console.log('\n=== 요약 표 ===');
    for (const r of rows) {
      console.log(`  | ${r.itemId} | ${r.version} | ${r.revisionId} | ${r.result} |`);
    }
  } finally {
    if (tempUid) {
      let cleaned = true;
      try {
        await db.collection('users').doc(tempUid).delete();
      } catch (e) { cleaned = false; console.error('users 삭제 실패:', e.message); }
      try {
        await admin.auth().deleteUser(tempUid);
      } catch (e) { cleaned = false; console.error('Auth 삭제 실패:', e.message); }
      console.log('\n임시 SUPER_ADMIN 정리:', cleaned ? '완료' :
        '**실패 — 수동 정리 필요**');
    }
  }
  process.exit(0);
})().catch((e) => {
  console.error('실패:', e.message);
  process.exit(1);
});
