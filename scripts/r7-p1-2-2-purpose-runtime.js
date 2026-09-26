'use strict';
// [R7-P1-2.2] staffing applicant-read 서버 권한 확인.
//
//   d2f8206 에서 확인된 것: canManageTo=false 인 멤버가
//   callableGetApplicationsByBiz 로 지원서 50건을 그대로 받았다.
//   UI 는 감췄지만 payload 는 이미 기기에 도착해 있었다 — authorization 이 아니다.
//
//   서버에는 이미 맞는 계약이 있었다: purpose=applicantReview → canManageTo strict.
//   staffing caller 가 그 purpose 를 넘기지 않아 membership-only 분기로 빠진 것이
//   root cause 다. 여기서 확인하는 것은 둘이다.
//
//     1. purpose 를 넘기면 실제로 payload 전에 막히는가 (배포본 기준)
//     2. purpose 없는 다른 목적 reader 가 함께 깨지지 않는가
//
//   권한 fixture 만 바꾸고 끝나면 정확히 되돌린다.
//
//   실행:  node scripts/r7-p1-2-2-purpose-runtime.js

const {db, callAs, EXPECTED_PROJECT} = require('./r7-fixture-lib.js');

const BIZ = 'fLmSOHVKUwmBHcbwQE0I';
const OWNER = 'BErRdiWP1xbgyoTovxwAPNEsuD72';
const SUB_ADMIN = 'kN2gNpEhLLVjQD7KLGSnNFJHd2v2';
const OUTSIDER = 'JK7GjLnacDczmdJjT3GIQENz87c2';

const APPLICANT_REVIEW = 'applicantReview';

const memberRef = db
    .collection('businesses').doc(BIZ)
    .collection('members').doc(SUB_ADMIN);

let failed = 0;
const line = (k, v) => console.log(`  ${String(k).padEnd(40)} ${v}`);
const check = (label, actual, expected) => {
  const ok = actual === expected;
  if (!ok) failed++;
  line(label, `${actual}   ${ok ? 'PASS' : `FAIL (expected ${expected})`}`);
};

async function readApps(uid, extra = {}) {
  try {
    const r = await callAs(uid, 'callableGetApplicationsByBiz',
        {businessId: BIZ, limit: 50, ...extra});
    const rows = r.applications || r.items || [];
    return {ok: true, count: Array.isArray(rows) ? rows.length : -1};
  } catch (e) {
    return {ok: false, code: e.wireCode || null, message: e.message};
  }
}

/** 한 시나리오를 DENY 로 확정한다 — row 가 1개라도 오면 FAIL. */
function expectDeny(label, r) {
  check(`${label} — denied`, r.ok, false);
  check(`${label} — code`, r.code, 'PERMISSION_DENIED');
  if (r.ok) {
    line(`${label} — 전달된 row`, `${r.count}  ← payload 가 이미 나갔다`);
  }
}

(async () => {
  console.log(`project=${EXPECTED_PROJECT} biz=${BIZ} purpose=${APPLICANT_REVIEW}`);

  const before = await memberRef.get();
  if (!before.exists) {
    console.error('member 문서가 없습니다 — fixture 전제 불충족. 중단.');
    process.exit(1);
  }
  const restore = JSON.parse(JSON.stringify(before.get('permissions') || {}));
  console.log('\n[0] fixture 원본 보존');
  line('permissions.canManageTo', restore.canManageTo);

  try {
    // ── A. owner ────────────────────────────────────────────────────
    console.log('\n[A] owner + applicantReview');
    const a = await readApps(OWNER, {purpose: APPLICANT_REVIEW});
    check('allowed', a.ok, true);
    line('count', a.count);

    // ── B. SubAdmin canManageTo=true ───────────────────────────────
    console.log('\n[B] SubAdmin canManageTo=true + applicantReview');
    await memberRef.update({'permissions.canManageTo': true});
    const b = await readApps(SUB_ADMIN, {purpose: APPLICANT_REVIEW});
    check('allowed', b.ok, true);
    line('count', b.count);

    // ── C. 같은 SubAdmin, canManageTo 회수 — 핵심 ──────────────────
    console.log('\n[C] 같은 SubAdmin canManageTo=false + applicantReview');
    await memberRef.update({'permissions.canManageTo': false});
    check('member.permissions.canManageTo',
        (await memberRef.get()).get('permissions')?.canManageTo, false);
    const c = await readApps(SUB_ADMIN, {purpose: APPLICANT_REVIEW});
    expectDeny('applicantReview', c);
    line('message', c.message || '-');

    // ── F. purpose 생략/무효로 우회되는가 ──────────────────────────
    console.log('\n[F] 같은 상태에서 우회 시도');
    const omitted = await readApps(SUB_ADMIN);
    line('purpose 생략 — ok', omitted.ok);
    line('purpose 생략 — count', omitted.count);
    line('  ↑ 이 경로는 membership + 네 권한 중 하나. canManageTo 외의',
        '');
    line('    권한이 남아 있으면 통과가 정상이다(근태·급여·계약 reader).', '');
    const bogus = await readApps(SUB_ADMIN, {purpose: 'staffing'});
    check('무효 purpose 거부', bogus.ok, false);
    check('무효 purpose code', bogus.code, 'INVALID_ARGUMENT');

    // 네 권한을 모두 회수하면 purpose 없이도 막혀야 한다.
    const stripped = {...restore};
    for (const k of ['canManageTo', 'canManageWorkers',
      'canManageWage', 'canManageContract']) stripped[k] = false;
    await memberRef.update({permissions: stripped});
    const none = await readApps(SUB_ADMIN);
    expectDeny('권한 0 + purpose 생략', none);

    // ── D. membership 제거 ─────────────────────────────────────────
    console.log('\n[D] membership 없는 사업장 (other-business actor)');
    const d = await readApps(OUTSIDER, {purpose: APPLICANT_REVIEW});
    expectDeny('other-business', d);

    // ── H. 권한 복구 후 재조회 ──────────────────────────────────────
    console.log('\n[H] canManageTo 복구 후 재조회');
    await memberRef.update({permissions: restore});
    const h = await readApps(SUB_ADMIN, {purpose: APPLICANT_REVIEW});
    check('allowed', h.ok, true);
    line('count', h.count);

    // ── 12. 비-staffing purpose 회귀 ───────────────────────────────
    console.log('\n[12] 다른 목적 reader 회귀 (purpose 없음)');
    const onlyWorkers = {...restore, canManageTo: false};
    onlyWorkers.canManageWorkers = true;
    await memberRef.update({permissions: onlyWorkers});
    const workforce = await readApps(SUB_ADMIN, {
      workDateGteMs: Date.now() - 86400000 * 7,
      workDateLtMs: Date.now() + 86400000 * 7,
    });
    check('canManageWorkers 만 있어도 근무자 조회 가능', workforce.ok, true);
    line('count', workforce.count);
    const stillDenied = await readApps(SUB_ADMIN, {purpose: APPLICANT_REVIEW});
    expectDeny('그 상태에서 applicantReview', stillDenied);

    // ── G. pagination 유지 ─────────────────────────────────────────
    console.log('\n[G] pagination / cursor 유지');
    await memberRef.update({permissions: restore});
    const p1 = await callAs(OWNER, 'callableGetApplicationsByBiz',
        {businessId: BIZ, limit: 5, purpose: APPLICANT_REVIEW});
    const rows1 = p1.applications || p1.items || [];
    line('page1 rows', rows1.length);
    const cursor = p1.nextCursor || p1.lastDocId ||
        (rows1.length ? rows1[rows1.length - 1].id : null);
    line('cursor', cursor ? String(cursor).slice(0, 12) + '…' : '(none)');
    if (cursor) {
      const p2 = await callAs(OWNER, 'callableGetApplicationsByBiz', {
        businessId: BIZ, limit: 5, purpose: APPLICANT_REVIEW,
        startAfterDocId: cursor,
      });
      const rows2 = p2.applications || p2.items || [];
      line('page2 rows', rows2.length);
      const overlap = rows1.filter((r) => rows2.some((x) => x.id === r.id));
      check('페이지 중복 0', overlap.length, 0);
    }

  } finally {
    console.log('\n[원복] fixture');
    await memberRef.update({permissions: restore});
    const after = (await memberRef.get()).get('permissions') || {};
    const same = JSON.stringify(Object.keys(after).sort().map((k) => [k, after[k]])) ===
        JSON.stringify(Object.keys(restore).sort().map((k) => [k, restore[k]]));
    line('permissions 원복 일치', same ? 'PASS' : 'FAIL');
    line('canManageTo', after.canManageTo);
    if (!same) failed++;
  }

  console.log(`\n결과: ${failed === 0 ? 'ALL PASS' : `${failed} FAIL`}`);
  process.exit(failed === 0 ? 0 : 1);
})();
