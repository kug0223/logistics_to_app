'use strict';
// [R7-P1-2.3] callableGetApplicationsByBiz 최소권한 매트릭스.
//
//   1a61876 까지의 상태: purpose 를 생략하면 네 권한 중 하나로 통과했고,
//   통과한 호출은 applicantReview 와 **같은 전체 payload** 를 받았다.
//   즉 canManageWorkers 만 가진 SubAdmin 이 purpose 를 빼는 것만으로
//   지원자 명단 전체를 가져갈 수 있었다. 권한이 caller 의 정직함 위에
//   서 있었다.
//
//   이제 purpose 는 필수이고 목적마다 capability 가 다르다.
//   여기서 확인하는 것은 그 경계가 **실제 배포본에서** 서는가이다.
//
//   실행:  node scripts/r7-p1-2-3-least-privilege-runtime.js

const {db, callAs, EXPECTED_PROJECT} = require('./r7-fixture-lib.js');

const BIZ = 'fLmSOHVKUwmBHcbwQE0I';
const OWNER = 'BErRdiWP1xbgyoTovxwAPNEsuD72';
const SUB = 'kN2gNpEhLLVjQD7KLGSnNFJHd2v2';
const OUTSIDER = 'JK7GjLnacDczmdJjT3GIQENz87c2';

const CAPS = ['canManageTo', 'canManageWorkers',
  'canManageWage', 'canManageContract'];

/** 정원 조회에서 나와서는 안 되는 field — 사람을 식별하는 값들. */
const IDENTIFYING = ['uid', 'userName', 'name', 'phone', 'contactPhone',
  'wage', 'wageType', 'snapshotWage', 'idCardConsentGiven', 'trustScore'];

const memberRef = db.collection('businesses').doc(BIZ)
    .collection('members').doc(SUB);

let failed = 0;
const line = (k, v) => console.log(`  ${String(k).padEnd(46)} ${v}`);
const check = (label, actual, expected) => {
  const ok = actual === expected;
  if (!ok) failed++;
  line(label, `${actual}   ${ok ? 'PASS' : `FAIL (expected ${expected})`}`);
};

async function read(uid, data) {
  try {
    const r = await callAs(uid, 'callableGetApplicationsByBiz',
        {businessId: BIZ, limit: 20, ...data});
    return {ok: true, rows: r.applications || [], lastDocId: r.lastDocId,
      hasMore: r.hasMore};
  } catch (e) {
    return {ok: false, code: e.wireCode || null, message: e.message};
  }
}

/** 오직 이 capability 하나만 true 로 만든다. */
async function only(cap) {
  const perms = {};
  for (const c of CAPS) perms[c] = (c === cap);
  await memberRef.update({permissions: perms});
}

function expectDeny(label, r, code = 'PERMISSION_DENIED') {
  check(`${label} — denied`, r.ok, false);
  check(`${label} — code`, r.code, code);
  if (r.ok) line(`${label} — 전달된 row`, `${r.rows.length}  ← payload 가 나갔다`);
}

(async () => {
  console.log(`project=${EXPECTED_PROJECT} biz=${BIZ}`);
  const before = await memberRef.get();
  if (!before.exists) {
    console.error('member 문서 없음 — 중단.'); process.exit(1);
  }
  const restore = JSON.parse(JSON.stringify(before.get('permissions') || {}));
  console.log('\n[0] fixture 원본 보존');
  line('permissions', CAPS.map((c) => `${c}=${restore[c]}`).join(' '));

  try {
    // ── A. owner ────────────────────────────────────────────────
    console.log('\n[A] owner + applicantReview');
    const a = await read(OWNER, {purpose: 'applicantReview'});
    check('allowed', a.ok, true);
    line('rows', a.rows.length);

    // ── B. canManageTo only ─────────────────────────────────────
    console.log('\n[B] canManageTo only + applicantReview');
    await only('canManageTo');
    const b = await read(SUB, {purpose: 'applicantReview'});
    check('allowed', b.ok, true);
    line('rows', b.rows.length);

    // ── C. canManageWorkers only + applicantReview → DENY ───────
    console.log('\n[C] canManageWorkers only + applicantReview');
    await only('canManageWorkers');
    expectDeny('applicantReview', await read(SUB, {purpose: 'applicantReview'}));

    // ── D. purpose 생략 → 우회 불가 ─────────────────────────────
    console.log('\n[D] canManageWorkers only + purpose 생략');
    expectDeny('purpose 생략', await read(SUB, {}), 'INVALID_ARGUMENT');
    console.log('  ↑ 더 이상 broad four-capability fallback 이 없다.');

    // ── E. attendance reader 정상 ───────────────────────────────
    console.log('\n[E] canManageWorkers only + workerOperation');
    const e = await read(SUB, {purpose: 'workerOperation'});
    check('allowed', e.ok, true);
    line('rows', e.rows.length);

    // ── F. contract reader ──────────────────────────────────────
    console.log('\n[F] canManageContract only + contractReview');
    await only('canManageContract');
    const f = await read(SUB, {purpose: 'contractReview'});
    check('allowed', f.ok, true);
    line('rows', f.rows.length);
    expectDeny('그 상태에서 workerOperation',
        await read(SUB, {purpose: 'workerOperation'}));

    // ── G. wage capability ──────────────────────────────────────
    console.log('\n[G] canManageWage only');
    await only('canManageWage');
    const g = await read(SUB, {purpose: 'capacity'});
    check('capacity allowed', g.ok, true);
    line('rows', g.rows.length);
    expectDeny('applicantReview', await read(SUB, {purpose: 'applicantReview'}));
    console.log('  ↑ wage 전용 Application reader 는 현재 없다 —');
    console.log('    급여는 attendance/payroll 쪽 reader 를 쓴다. 그래서');
    console.log('    wage purpose 를 만들지 않았고, 정원 조회만 열어 둔다.');

    // ── 정원 projection 격리 ────────────────────────────────────
    console.log('\n[11] capacity projection 격리');
    if (g.rows.length > 0) {
      const leaked = new Set();
      for (const row of g.rows) {
        for (const k of IDENTIFYING) if (k in row) leaked.add(k);
      }
      check('식별 field 유출 0', leaked.size, 0);
      if (leaked.size) line('유출된 field', [...leaked].join(', '));
      line('정원 row 예시 key', Object.keys(g.rows[0]).join(','));
      // 정원 계산에 필요한 값은 남아 있어야 한다.
      const need = ['status', 'workDetailId', 'wdId', 'slotId'];
      const present = need.filter((k) => g.rows.some((r) => k in r));
      line('정원 계산 field 존재', present.join(',') || '(없음)');
      check('status 는 있다', g.rows.some((r) => 'status' in r), true);
    } else {
      line('정원 row', '0건 — projection 확인 불가');
    }

    // full purpose 는 여전히 전체를 준다.
    await only('canManageTo');
    const full = await read(SUB, {purpose: 'applicantReview'});
    if (full.rows.length > 0) {
      check('applicantReview 는 uid 를 포함한다',
          'uid' in full.rows[0], true);
    }

    // ── H. 권한 0 ───────────────────────────────────────────────
    console.log('\n[H] capability 0개');
    await memberRef.update({
      permissions: Object.fromEntries(CAPS.map((c) => [c, false])),
    });
    for (const p of ['applicantReview', 'workerOperation',
      'contractReview', 'capacity']) {
      expectDeny(`zero-cap + ${p}`, await read(SUB, {purpose: p}));
    }

    // ── I. 다른 사업장 ──────────────────────────────────────────
    console.log('\n[I] 다른 사업장 actor');
    expectDeny('other-business', await read(OUTSIDER, {purpose: 'capacity'}));

    // ── J. 무효 purpose ─────────────────────────────────────────
    console.log('\n[J] 무효/누락 purpose');
    await memberRef.update({permissions: restore});
    expectDeny('알 수 없는 purpose', await read(SUB, {purpose: 'staffing'}),
        'INVALID_ARGUMENT');
    expectDeny('빈 문자열', await read(SUB, {purpose: ''}), 'INVALID_ARGUMENT');
    expectDeny('숫자', await read(SUB, {purpose: 1}), 'INVALID_ARGUMENT');
    expectDeny('owner 도 생략 불가', await read(OWNER, {}), 'INVALID_ARGUMENT');
    console.log('  ↑ owner 도 예외가 아니다 — 목적 없는 조회 자체를 받지 않는다.');

    // ── K. pagination ───────────────────────────────────────────
    console.log('\n[K] pagination + purpose 유지');
    const p1 = await read(OWNER, {purpose: 'capacity', limit: 5});
    check('page1 allowed', p1.ok, true);
    line('page1 rows', p1.rows.length);
    if (p1.lastDocId) {
      const p2 = await read(OWNER,
          {purpose: 'capacity', limit: 5, startAfterDocId: p1.lastDocId});
      check('page2 allowed', p2.ok, true);
      line('page2 rows', p2.rows.length);
      const dup = p1.rows.filter((r) => p2.rows.some((x) => x.id === r.id));
      check('페이지 중복 0', dup.length, 0);
      // 2페이지도 같은 projection 이어야 한다 — 중간에 목적이 사라지지 않는다.
      const leaked2 = p2.rows.some((r) => IDENTIFYING.some((k) => k in r));
      check('page2 projection 유지', leaked2, false);
    }

  } finally {
    console.log('\n[원복] fixture');
    await memberRef.update({permissions: restore});
    const after = (await memberRef.get()).get('permissions') || {};
    const same = CAPS.every((c) => after[c] === restore[c]);
    line('permissions 원복 일치', same ? 'PASS' : 'FAIL');
    line('현재', CAPS.map((c) => `${c}=${after[c]}`).join(' '));
    if (!same) failed++;
  }

  console.log(`\n결과: ${failed === 0 ? 'ALL PASS' : `${failed} FAIL`}`);
  process.exit(failed === 0 ? 0 : 1);
})();
