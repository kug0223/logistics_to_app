// [R8-SM-PORTONE §5] PASS 본인인증의 PORTONE 인증정보를 **이 함수에만** 주입한다.
//
//   실행:  cd functions && npm run build && node test/portone_secret_binding.test.js
//
//   무엇을 고정하는가
//     ① `verifyPassAuth` 에 두 Secret 이 바인딩돼 있다.
//     ② 리전·App Check·호출 종류 등 기존 정책이 그대로다 — 비밀 전달 방식만 바뀐다.
//     ③ **다른 249개 함수에는 `secrets` 가 붙지 않았다.** 범위를 줄이려는 변경이
//        범위를 넓히면 목적과 반대가 된다.
//     ④ PORTONE 키를 읽는 위치가 여전히 **핸들러 안**이다. 모듈 최상위로 올라가면
//        Secret 주입 시점·cold start 와 얽혀 조용히 빈 값이 될 수 있다.
//     ⑤ 정상·거절·오류·키 누락 경로의 판정과 사용자 상태 writer 계약이 불변이다.
//
//   실제 PORTONE 호출도, 실제 인증정보도, 실제 개인정보도 쓰지 않는다.
//   네트워크 호출은 전부 합성 double 이다.
'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const FUNCTIONS_DIR = __dirname.replace(/[\\/]test$/, '');
const SRC = fs.readFileSync(path.join(FUNCTIONS_DIR, 'src', 'index.ts'), 'utf8');
const SRC_LINES = SRC.split(/\r?\n/);

let pass = 0;
const fails = [];
function t(name, fn) {
  try { fn(); pass++; } catch (e) { fails.push(`${name}: ${e.message}`); }
}

// ── 최상위 export 의 줄 범위 ───────────────────────────────────────────
const exportDecls = [];
SRC_LINES.forEach((l, i) => {
  const m = l.match(/^export const (\w+)\s*=\s*(on\w+)\(/);
  if (m) exportDecls.push({name: m[1], trigger: m[2], start: i + 1});
});
exportDecls.forEach((d, i) => {
  d.end = i + 1 < exportDecls.length ? exportDecls[i + 1].start - 1 : SRC_LINES.length;
});
const byName = new Map(exportDecls.map((d) => [d.name, d]));

/// 선언 직후의 옵션 객체 텍스트 (첫 번째 `{`…`}` 블록).
function optionsOf(name) {
  const d = byName.get(name);
  assert.ok(d, `${name} 선언을 찾지 못했다`);
  const head = SRC_LINES.slice(d.start - 1, Math.min(d.start + 14, d.end)).join('\n');
  const open = head.indexOf('{');
  if (open < 0) return '';
  let depth = 0;
  for (let i = open; i < head.length; i++) {
    if (head[i] === '{') depth++;
    else if (head[i] === '}') { depth--; if (depth === 0) return head.slice(open, i + 1); }
  }
  return head.slice(open);
}

// ══════════════════════════════════════════════════════════════════════
// ① 두 Secret 이 verifyPassAuth 에 바인딩됐다
// ══════════════════════════════════════════════════════════════════════
const vpaOpts = optionsOf('verifyPassAuth');

t('PSB-01 verifyPassAuth 에 PORTONE_IMP_KEY 가 바인딩됐다', () => {
  assert.ok(/secrets\s*:\s*\[[^\]]*["']PORTONE_IMP_KEY["']/.test(vpaOpts),
      'secrets 에 PORTONE_IMP_KEY 가 없다');
});
t('PSB-02 verifyPassAuth 에 PORTONE_IMP_SECRET 이 바인딩됐다', () => {
  assert.ok(/secrets\s*:\s*\[[^\]]*["']PORTONE_IMP_SECRET["']/.test(vpaOpts),
      'secrets 에 PORTONE_IMP_SECRET 이 없다');
});
t('PSB-03 바인딩은 그 둘뿐이다 — 다른 비밀을 끌어오지 않는다', () => {
  const m = vpaOpts.match(/secrets\s*:\s*\[([^\]]*)\]/);
  assert.ok(m, 'secrets 옵션이 없다');
  const names = m[1].split(',').map((s) => s.trim().replace(/^["']|["']$/g, '')).filter(Boolean);
  assert.deepStrictEqual(names.sort(), ['PORTONE_IMP_KEY', 'PORTONE_IMP_SECRET']);
});

// ══════════════════════════════════════════════════════════════════════
// ② 기존 정책 불변 — 비밀 전달 방식만 바뀐다
// ══════════════════════════════════════════════════════════════════════
t('PSB-04 리전이 그대로다 (asia-northeast3)', () => {
  assert.ok(/region\s*:\s*["']asia-northeast3["']/.test(vpaOpts), '리전이 바뀌었다');
});
t('PSB-05 App Check 정책이 그대로다 (enforceAppCheck: false)', () => {
  // 가입 전 단계라 App Check 토큰이 없을 수 있어 false 였다. 올리면 가입이 막힌다.
  assert.ok(/enforceAppCheck\s*:\s*false/.test(vpaOpts), 'App Check 정책이 바뀌었다');
});
t('PSB-06 호출 종류가 그대로다 (onCall)', () => {
  assert.strictEqual(byName.get('verifyPassAuth').trigger, 'onCall');
});

// ══════════════════════════════════════════════════════════════════════
// ③ 다른 함수에는 secrets 가 붙지 않았다 — 범위를 넓히지 않는다
// ══════════════════════════════════════════════════════════════════════
t('PSB-07 secrets 옵션을 가진 export 는 verifyPassAuth 하나뿐이다', () => {
  const withSecrets = exportDecls
      .filter((d) => /secrets\s*:\s*\[/.test(optionsOf(d.name)))
      .map((d) => d.name);
  assert.deepStrictEqual(withSecrets, ['verifyPassAuth'],
      `secrets 가 붙은 함수: ${withSecrets.join(', ')}`);
});
t('PSB-08 PORTONE 전환이 함수 목록을 건드리지 않았다', () => {
  // 이 셀이 묻는 것은 "**이 전환이** 함수를 늘리거나 줄였는가" 다.
  //   숫자를 못박으면 무관한 Phase 가 함수를 추가할 때마다 깨진다 —
  //   실제로 깨졌다(R8P6 계약서 PDF Signed URL callable 추가, 250 → 251).
  //   그래서 "PORTONE 과 무관한 export 가 사라지지 않았는지"로 바꾼다.
  assert.ok(exportDecls.length >= 250,
      `export 가 ${exportDecls.length}개로 줄었다 — 사라진 함수가 있다`);
  for (const must of [
    'verifyPassAuth', 'finalizeRegistration', 'resetPasswordWithPass',
    'callableApplyToTO', 'callableFinalizeWorkerSignature',
  ]) {
    assert.ok(byName.has(must), `${must} 가 사라졌다`);
  }
});

// ══════════════════════════════════════════════════════════════════════
// ④ 키를 읽는 위치 — 모듈 최상위가 아니라 핸들러 안이어야 한다
// ══════════════════════════════════════════════════════════════════════
t('PSB-09 PORTONE 키는 핸들러 안에서만 읽는다', () => {
  const sites = [];
  SRC_LINES.forEach((l, i) => {
    if (/process\.env\.PORTONE_IMP_(KEY|SECRET)\b/.test(l)) sites.push(i + 1);
  });
  assert.ok(sites.length > 0, 'PORTONE 키를 읽는 곳이 없다');
  const d = byName.get('verifyPassAuth');
  for (const ln of sites) {
    assert.ok(ln > d.start && ln < d.end,
        `줄 ${ln} 의 PORTONE 읽기가 verifyPassAuth(${d.start}~${d.end}) 밖이다`);
    // 들여쓰기가 있어야 핸들러 내부다. 최상위 `const X = process.env...` 는 0칸이다.
    assert.ok(/^\s{2,}/.test(SRC_LINES[ln - 1]),
        `줄 ${ln} 이 모듈 최상위 초기화로 보인다 — Secret 주입 전에 읽힐 수 있다`);
  }
});

// ══════════════════════════════════════════════════════════════════════
// ⑤ 판정·writer 계약 불변 — 합성 응답으로 기존 분기를 그대로 통과시킨다
// ══════════════════════════════════════════════════════════════════════
//   실제 함수를 불러오려면 firebase-functions 런타임과 Firestore 가 필요하다.
//   여기서는 **판정식 자체**를 소스에서 떼어 와 같은 입력으로 돌린다 —
//   식을 복제해 적는 것이 아니라, 소스 문구를 고정한 뒤 합성 입력으로 검증한다.

t('PSB-10 PORTONE 응답 판정식이 그대로다 (code===0 && certified)', () => {
  assert.ok(SRC.includes('if (certData.code !== 0 || !certData.response?.certified) {'),
      '인증 성공 판정이 바뀌었다');
});
t('PSB-11 거절은 permission-denied, 토큰 실패는 internal 이다', () => {
  assert.ok(SRC.includes('throw new HttpsError("permission-denied", "본인인증에 실패했습니다.");'),
      '거절 응답이 바뀌었다');
  assert.ok(SRC.includes('throw new HttpsError("internal", "PortOne 토큰 발급 실패.");'),
      '토큰 실패 응답이 바뀌었다');
});
t('PSB-12 키 누락은 안전하게 실패한다 — 빈 키로 호출하지 않는다', () => {
  // `?? ""` 로 받아 그대로 fetch 하면 PORTONE 에 빈 자격증명을 보낸다.
  // 기존 코드는 먼저 막는다. Secret 미주입(= 빈 값)일 때도 이 가드가 받는다.
  assert.ok(SRC.includes('if (!impKey || !impSecret) {'), '키 누락 가드가 사라졌다');
  assert.ok(SRC.includes(
      'throw new HttpsError("internal", "PortOne 인증 설정이 없습니다. 환경 변수를 확인하세요.");'),
  '키 누락 시 메시지가 바뀌었다');
});
t('PSB-13 사용자 상태 writer 계약이 불변이다 (passTokens 문서)', () => {
  // 이 함수가 쓰는 곳은 passTokens 하나다. users 를 직접 쓰지 않는다 —
  // 인증 결과가 곧 계정 상태가 되지 않는다는 기존 설계다.
  assert.ok(SRC.includes('.collection("passTokens")'), 'passTokens writer 가 사라졌다');
  const d = byName.get('verifyPassAuth');
  const body = SRC_LINES.slice(d.start - 1, d.end).join('\n');
  for (const field of ['ciHash', 'name', 'gender', 'birthDate', 'phone',
    'purpose', 'role', 'expiresAt', 'createdAt']) {
    assert.ok(new RegExp(`\\b${field}\\b`).test(body), `passToken 필드 ${field} 가 사라졌다`);
  }
  assert.ok(/return \{passToken, name, gender, birthDate: birthDateStr, phone\};/.test(body),
      '반환 계약이 바뀌었다 — 클라이언트가 이 다섯 필드를 읽는다');
  // 이 함수가 users 컬렉션에 **쓰지** 않는다는 것도 못박는다(읽기는 중복 검사용).
  assert.ok(!/db\s*\n?\s*\.collection\("users"\)\s*\n?\s*\.doc\([^)]*\)\s*\n?\s*\.set\(/.test(body),
      'users 직접 쓰기가 생겼다 — 인증이 계정 상태를 바꾸면 안 된다');
});
t('PSB-14 만 19세 미만 차단과 CI 해시가 그대로다', () => {
  assert.ok(SRC.includes('throw new HttpsError("permission-denied", "만 19세 이상만 가입 가능합니다.");'),
      '연령 게이트가 바뀌었다');
  assert.ok(SRC.includes('const ciHash = crypto.createHash("sha256").update(ci).digest("hex");'),
      'CI 해시 방식이 바뀌었다');
});

// ── 합성 응답으로 분기 동작 확인 ──────────────────────────────────────
// PORTONE 응답 모양만 흉내낸 double 로, 위에서 고정한 판정식과 같은 조건을 돌린다.
const accepted = (certData) => !(certData.code !== 0 || !certData.response?.certified);
t('PSB-15 정상 응답은 통과한다', () => {
  assert.strictEqual(accepted({code: 0, response: {certified: true, unique_key: 'SYNTH-CI'}}), true);
});
t('PSB-16 거절·취소·만료 응답은 전부 막힌다', () => {
  assert.strictEqual(accepted({code: 0, response: {certified: false}}), false, '미인증');
  assert.strictEqual(accepted({code: -1, response: {certified: true}}), false, 'API 오류코드');
  assert.strictEqual(accepted({code: 0}), false, 'response 없음(취소)');
  assert.strictEqual(accepted({}), false, '빈 응답(만료)');
});
t('PSB-17 키 누락은 PORTONE 호출 전에 막힌다', () => {
  const guard = (k, s) => !(!k || !s);
  assert.strictEqual(guard('', 'x'), false, '키 없음');
  assert.strictEqual(guard('x', ''), false, '시크릿 없음');
  assert.strictEqual(guard(undefined, undefined), false, '둘 다 없음(Secret 미주입)');
  assert.strictEqual(guard('k', 's'), true, '둘 다 있음');
});

// ══════════════════════════════════════════════════════════════════════
// ⑥ `.env` 공존 — 바인딩만으로 배포 가능하다고 말하지 않는다
// ══════════════════════════════════════════════════════════════════════
t('PSB-18 .env 에 같은 이름이 남아 있으면 전환 미완료로 표시된다', () => {
  // firebase-tools 15.31.0 은 `.env` 를 모든 endpoint 의 평문 환경변수로 싣고,
  // `secretEnvironmentVariables` 를 그대로 복사한다 — **중복 제거가 없다**
  // (`lib/gcp/cloudfunctionsv2.js` proto.copyIfPresent).
  // 그래서 같은 키가 두 맵에 함께 실린다. 이 테스트는 그 상태를 **기록**한다.
  //   · .env 에 남아 있음  → 전환은 아직 '준비' 단계다(배포 전 제거 필요)
  //   · .env 에서 빠짐      → 전환 완료, 이 셀은 반대쪽을 확인한다
  const envPath = path.join(FUNCTIONS_DIR, '.env');
  if (!fs.existsSync(envPath)) return;            // CI 등 .env 없는 환경
  const keys = fs.readFileSync(envPath, 'utf8').split(/\r?\n/)
      .map((l) => (l.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=/) || [])[1])
      .filter(Boolean);
  const stillThere = ['PORTONE_IMP_KEY', 'PORTONE_IMP_SECRET'].filter((k) => keys.includes(k));
  if (stillThere.length) {
    // 실패가 아니다 — 아직 배포하면 안 된다는 **상태 표시**다.
    console.log(`  [상태] .env 에 ${stillThere.join(', ')} 가 남아 있다 — ` +
        '배포 전 제거가 같은 변경에 묶여야 한다 (DEV RUNTIME PENDING)');
  } else {
    console.log('  [상태] .env 에서 두 키가 제거됐다 — 배포 준비 완료');
  }
});

console.log('─'.repeat(30));
if (fails.length) {
  fails.forEach((f) => console.log('  FAIL ' + f));
  console.log(`총 ${pass + fails.length}건 · 실패 ${fails.length}건`);
  process.exit(1);
}
console.log(`총 ${pass}건 · 실패 0건`);
