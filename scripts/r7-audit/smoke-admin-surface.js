/**
 * R7 §2 — CLI 수선의 부작용 smoke.
 *
 * `Proxied.getOriginal` 수선이 `admin.firestore.Timestamp` 하나만 되살린 것이
 * 아니라, **bind 로 잃었던 own property 전반**을 원본과 같게 돌려놓았는지,
 * 그리고 binding 자체(this·호출 가능성)를 망가뜨리지 않았는지 본다.
 *
 * 에뮬레이터가 없어도 돈다 — CLI 의 그 함수만 떼어 원본/수선을 비교한다.
 *   node scripts/r7-audit/smoke-admin-surface.js <firebase-tools 설치 경로>
 */
const path = require('path');
const admin = require(path.join(__dirname, '..', '..', 'functions', 'node_modules', 'firebase-admin'));

/** CLI 원본 구현 (bind 만) */
function getOriginal_orig(target, key) {
  const value = target[key];
  if (value === undefined || value === null) return undefined;
  if (typeof value !== 'function') return value;
  return value.bind(target);
}

/** 수선본 — own descriptor 복원 */
function getOriginal_patched(target, key) {
  const value = target[key];
  if (value === undefined || value === null) return undefined;
  if (typeof value !== 'function') return value;
  const bound = value.bind(target);
  for (const [k, d] of Object.entries(Object.getOwnPropertyDescriptors(value))) {
    if (k === 'length' || k === 'name' || k === 'prototype') continue;
    try { Object.defineProperty(bound, k, d); } catch { /* 복원 불가 속성은 건너뛴다 */ }
  }
  return bound;
}

const fail = [];
const ok = [];
const check = (name, cond, detail) => (cond ? ok : fail).push(`${name}${detail ? ' — ' + detail : ''}`);

for (const key of ['firestore', 'auth', 'database', 'storage', 'messaging']) {
  const raw = admin[key];
  if (typeof raw !== 'function') continue;

  const orig = getOriginal_orig(admin, key);
  const patched = getOriginal_patched(admin, key);

  const rawProps = Object.getOwnPropertyNames(raw)
    .filter((k) => !['length', 'name', 'prototype'].includes(k));
  const origProps = Object.getOwnPropertyNames(orig)
    .filter((k) => !['length', 'name', 'prototype'].includes(k));
  const patchedProps = Object.getOwnPropertyNames(patched)
    .filter((k) => !['length', 'name', 'prototype'].includes(k));

  const lostByOrig = rawProps.filter((k) => !origProps.includes(k));
  const missingAfterPatch = rawProps.filter((k) => !patchedProps.includes(k));
  const extraAfterPatch = patchedProps.filter((k) => !rawProps.includes(k));

  check(`[${key}] 수선 후 원본 own property 를 모두 되살렸다`,
    missingAfterPatch.length === 0,
    missingAfterPatch.length ? `누락: ${missingAfterPatch.join(',')}` : `${rawProps.length}개`);
  check(`[${key}] 원본에 없던 것을 덧붙이지 않았다`,
    extraAfterPatch.length === 0,
    extraAfterPatch.join(',') || '없음');
  check(`[${key}] 각 property 가 원본과 **같은 객체**다`,
    rawProps.every((k) => patched[k] === raw[k]),
    '동일성 비교');
  check(`[${key}] 여전히 호출 가능한 함수다`, typeof patched === 'function');

  if (lostByOrig.length) {
    ok.push(`[${key}] (참고) 수선 전 bind 가 잃던 property ${lostByOrig.length}개: ` +
      lostByOrig.slice(0, 6).join(',') + (lostByOrig.length > 6 ? ' …' : ''));
  }
}

// binding 정체성 — this 가 여전히 admin 모듈로 묶여 있는지
{
  const probeTarget = {
    tag: 'target',
    fn: function () { return this && this.tag; },
  };
  probeTarget.fn.STATIC = 'kept';
  const patched = getOriginal_patched(probeTarget, 'fn');
  check('binding this 가 유지된다', patched() === 'target', `= ${patched()}`);
  check('static 이 살아 있다', patched.STATIC === 'kept');
}

console.log('── PASS ──');
ok.forEach((l) => console.log('  ✔ ' + l));
if (fail.length) {
  console.log('── FAIL ──');
  fail.forEach((l) => console.log('  ✘ ' + l));
  process.exit(1);
}
console.log(`\n모두 통과 (${ok.length}건).`);
