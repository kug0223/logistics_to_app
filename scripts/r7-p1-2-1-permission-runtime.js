'use strict';
// [R7-P1-2.1] WorkApplicants 권한 회수 DEV 런타임 확인.
//
//   확인하려는 것은 둘이다.
//     1. canManageTo 회수가 어느 신호로 도달하는가 (member 문서인가, CF 거부인가)
//     2. membership 이 없는 호출자에게 CF 가 실제로 무슨 code 를 주는가
//
//   product code 에 테스트용 분기를 넣지 않는다. 여기서는 권한 fixture 만
//   바꾸고, 끝나면 읽어둔 원본으로 정확히 되돌린다.
//
//   실행:  node scripts/r7-p1-2-1-permission-runtime.js

const {admin, db, callAs, EXPECTED_PROJECT} = require('./r7-fixture-lib.js');

const BIZ = 'fLmSOHVKUwmBHcbwQE0I';
const SUB_ADMIN = 'kN2gNpEhLLVjQD7KLGSnNFJHd2v2';
const OTHER_BIZ_OWNER = 'JK7GjLnacDczmdJjT3GIQENz87c2';

const memberRef = db
    .collection('businesses').doc(BIZ)
    .collection('members').doc(SUB_ADMIN);

const line = (k, v) => console.log(`  ${String(k).padEnd(34)} ${v}`);

/** dialog 가 쓰는 바로 그 호출. purpose 를 넘기지 않는다. */
async function queryApplicants(uid) {
  try {
    const r = await callAs(uid, 'callableGetApplicationsByBiz', {
      businessId: BIZ, limit: 50,
    });
    const n = Array.isArray(r.applications) ? r.applications.length
        : Array.isArray(r.items) ? r.items.length : -1;
    return {ok: true, count: n};
  } catch (e) {
    return {ok: false, code: e.wireCode || null, message: e.message};
  }
}

/** 지원자 이름·연락처를 채우는 호출. */
async function queryUsers(uid, uids) {
  try {
    const r = await callAs(uid, 'callableGetUsersBatch', {
      uids, businessId: BIZ, purpose: 'workerDirectory',
    });
    const users = r.users || r.items || {};
    return {ok: true, count: Array.isArray(users) ? users.length : Object.keys(users).length};
  } catch (e) {
    return {ok: false, code: e.wireCode || null};
  }
}

(async () => {
  if (admin.app().options.projectId !== EXPECTED_PROJECT &&
      process.env.GCLOUD_PROJECT !== EXPECTED_PROJECT) {
    // r7-fixture-lib 가 이미 DEV 를 강제하지만 한 번 더 못 박는다.
    console.error('DEV 프로젝트가 아닙니다. 중단.');
    process.exit(1);
  }
  console.log(`project=${EXPECTED_PROJECT} biz=${BIZ}`);

  const before = await memberRef.get();
  if (!before.exists) {
    console.error('member 문서가 없습니다 — fixture 전제 불충족. 중단.');
    process.exit(1);
  }
  const originalPerms = before.get('permissions') || {};
  console.log('\n[0] fixture 원본 보존');
  line('permissions.canManageTo', originalPerms.canManageTo);
  const restore = JSON.parse(JSON.stringify(originalPerms));

  let failed = 0;
  const check = (label, actual, expected) => {
    const ok = actual === expected;
    if (!ok) failed++;
    line(label, `${actual}   ${ok ? 'PASS' : `FAIL (expected ${expected})`}`);
  };

  try {
    // ── 1. 권한 있음 — 명단이 보인다 ────────────────────────────────
    console.log('\n[1] canManageTo=true — baseline');
    const base = await queryApplicants(SUB_ADMIN);
    check('applicants query ok', base.ok, true);
    line('applicants count', base.count);
    const permA = (await memberRef.get()).get('permissions')?.canManageTo;
    check('member.permissions.canManageTo', permA, true);

    // ── 2. canManageTo 회수 ────────────────────────────────────────
    console.log('\n[2] canManageTo 회수');
    await memberRef.update({'permissions.canManageTo': false});
    const permB = (await memberRef.get()).get('permissions')?.canManageTo;
    check('member.permissions.canManageTo', permB, false);
    line('→ 클라이언트 watch 가 읽는 값', 'canManageTo=false → checkForBusiness=denied');

    const afterRevoke = await queryApplicants(SUB_ADMIN);
    line('applicants query ok', afterRevoke.ok);
    line('applicants code', afterRevoke.code || '-');
    line('applicants count', afterRevoke.count);
    console.log('  ↑ 이 CF 는 purpose 없이 membership 만 본다 —');
    console.log('    canManageTo 회수만으로는 서버가 거부하지 않는다.');
    console.log('    그래서 이 경로의 canonical 신호는 member 문서 watch 다.');

    const usersAfter = await queryUsers(SUB_ADMIN, [OTHER_BIZ_OWNER]);
    line('usersBatch ok', usersAfter.ok);
    line('usersBatch code', usersAfter.code || '-');

    // ── 3. membership 없는 호출자 — 실제 denial code ────────────────
    console.log('\n[3] membership 없는 호출자 — CF denial code');
    const outsider = await queryApplicants(OTHER_BIZ_OWNER);
    check('applicants query ok', outsider.ok, false);
    check('error wire code', outsider.code, 'PERMISSION_DENIED');
    line('message', outsider.message || '-');
    console.log('  ↑ wire PERMISSION_DENIED ↔ Firebase SDK permission-denied 는');
    console.log('    같은 값의 다른 표기다. 제품 코드의 isPermissionDenial() 은');
    console.log('    SDK 쪽 `.code` 를 본다 — 어느 쪽도 메시지를 읽지 않는다.');

    const outsiderUsers = await queryUsers(OTHER_BIZ_OWNER, [SUB_ADMIN]);
    check('usersBatch ok', outsiderUsers.ok, false);
    line('usersBatch code', outsiderUsers.code || '-');

  } finally {
    // ── 4. 정확 원복 ────────────────────────────────────────────────
    console.log('\n[4] fixture 원복');
    await memberRef.update({permissions: restore});
    const after = (await memberRef.get()).get('permissions') || {};
    const same = JSON.stringify(Object.keys(after).sort().map((k) => [k, after[k]])) ===
        JSON.stringify(Object.keys(restore).sort().map((k) => [k, restore[k]]));
    line('permissions 원복 일치', same ? 'PASS' : 'FAIL');
    line('canManageTo', after.canManageTo);
    if (!same) failed++;
  }

  // ── 5. 권한 복구 후 재조회 ────────────────────────────────────────
  console.log('\n[5] 권한 복구 후 재조회');
  const restored = await queryApplicants(SUB_ADMIN);
  check('applicants query ok', restored.ok, true);
  line('applicants count', restored.count);

  console.log(`\n결과: ${failed === 0 ? 'ALL PASS' : `${failed} FAIL`}`);
  process.exit(failed === 0 ? 0 : 1);
})();
