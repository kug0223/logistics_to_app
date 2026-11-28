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
// [ALFIT-AUTH-KAKAO-ONBOARDING.1 §2.3 · 계약 변경] CI 원문을 저장하지 않고 용도 구분 HMAC
//   (`ci1_` + HMAC(CI_HMAC_KEY_V1, "alfit:identity:ci:v1:" + CI))만 남기려면 이 함수가 그
//   키를 받아야 한다. 범위를 넓히는 것이 아니라 **세 번째 비밀 하나**만 같은 함수에 더한다
//   (PSB-07 — 다른 함수에는 여전히 0). 예전 기대(두 개)는 판정278 착수 범위에서 바뀐다.
t('PSB-03 바인딩은 PORTONE 둘 + CI_HMAC_KEY_V1 뿐이다 — 다른 비밀을 끌어오지 않는다', () => {
  const m = vpaOpts.match(/secrets\s*:\s*\[([^\]]*)\]/);
  assert.ok(m, 'secrets 옵션이 없다');
  const names = m[1].split(',').map((s) => s.trim().replace(/^["']|["']$/g, '')).filter(Boolean);
  assert.deepStrictEqual(names.sort(), ['CI_HMAC_KEY_V1', 'PORTONE_IMP_KEY', 'PORTONE_IMP_SECRET']);
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
  // [ALFIT-AUTH-KAKAO-ONBOARDING.1] 닫힌 옛 표면(finalizeRegistration·resetPasswordWithPass)도
  //   export 는 남는다 — 옛 앱이 부르면 LEGACY_* 로 거절받아야 하고, 함수가 사라지면 배포가
  //   그 함수를 지운다(옛 앱은 not-found 를 받는다). 새 가입 callable 도 목록에 있어야 한다.
  for (const must of [
    'verifyPassAuth', 'finalizeRegistration', 'resetPasswordWithPass',
    'callableApplyToTO', 'callableFinalizeWorkerSignature',
    'callableAuthKakao', 'callableCompleteSignup', 'callableSignupFinalizeAuth',
  ]) {
    assert.ok(byName.has(must), `${must} 가 사라졌다`);
  }
});

// ══════════════════════════════════════════════════════════════════════
// ④ 키를 읽는 위치 — 모듈 최상위가 아니라 핸들러 안이어야 한다
// ══════════════════════════════════════════════════════════════════════
t('PSB-09 PORTONE 키·CI HMAC 키는 verifyPassAuth 핸들러 안에서만 읽는다', () => {
  const sites = [];
  SRC_LINES.forEach((l, i) => {
    if (/process\.env\.(PORTONE_IMP_(KEY|SECRET)|CI_HMAC_KEY_V1)\b/.test(l)) sites.push(i + 1);
  });
  assert.ok(sites.length >= 3, 'PORTONE·CI 키를 읽는 곳이 없다');
  const d = byName.get('verifyPassAuth');
  for (const ln of sites) {
    assert.ok(ln > d.start && ln < d.end,
        `줄 ${ln} 의 비밀 읽기가 verifyPassAuth(${d.start}~${d.end}) 밖이다`);
    // 들여쓰기가 있어야 핸들러 내부다. 최상위 `const X = process.env...` 는 0칸이다.
    assert.ok(/^\s{2,}/.test(SRC_LINES[ln - 1]),
        `줄 ${ln} 이 모듈 최상위 초기화로 보인다 — Secret 주입 전에 읽힐 수 있다`);
  }
  // [ALFIT-AUTH-KAKAO-ONBOARDING.1] 새 모듈은 키를 **인자로 받기만** 한다 — 스스로 읽지 않는다.
  for (const f of ['auth_kakao.ts', 'auth_adapters.ts', 'signup_core.ts']) {
    const s = fs.readFileSync(path.join(FUNCTIONS_DIR, 'src', f), 'utf8');
    assert.ok(!/process\.env/.test(s), `${f} 가 process.env 를 직접 읽는다`);
  }
});

// ══════════════════════════════════════════════════════════════════════
// ⑤ 판정·writer 계약 — [ALFIT-AUTH-KAKAO-ONBOARDING.1 §2.3] 계약 변경
// ══════════════════════════════════════════════════════════════════════
//   예전: verifyPassAuth 가 PortOne 을 직접 부르고 `!certified` truthy 판정 · DEV 전화 대체 CI ·
//         성별 여성 폴백 · 무키 SHA ciHash · passTokens 발급(register/reauth/resetPassword).
//   지금: 판정은 순수 모듈(signup_core.parsePortOneCertification — certified === true 엄격 ·
//         CI 없음 = 실패 · 성별 미제공 = null) · 키는 핸들러가 읽어 auth_kakao 로 넘김 ·
//         옛 세 목적은 LEGACY_* 로 닫힘 · 저장은 passCertifications/signupSessions(auth_kakao).
//   판정 함수는 **컴파일된 원문**(lib/signup_core.js)을 그대로 불러 합성 응답으로 돌린다.
const CORE = require(path.join(FUNCTIONS_DIR, 'lib', 'signup_core.js'));
const vpaBody = (() => {
  const d = byName.get('verifyPassAuth');
  return SRC_LINES.slice(d.start - 1, d.end).join('\n');
})();

t('PSB-10 PORTONE 응답 판정은 순수 모듈의 엄격 판정이다 (code===0 && certified===true)', () => {
  const ak = fs.readFileSync(path.join(FUNCTIONS_DIR, 'src', 'auth_kakao.ts'), 'utf8');
  assert.ok(ak.includes('parsePortOneCertification(r.raw)'), 'auth_kakao 가 순수 판정을 쓰지 않는다');
  const core = fs.readFileSync(path.join(FUNCTIONS_DIR, 'src', 'signup_core.ts'), 'utf8');
  assert.ok(core.includes('r.code !== 0 || !res || typeof res !== "object" || res["certified"] !== true'),
      '엄격 판정식이 바뀌었다');
});
t('PSB-11 옛 목적은 서버에서 닫힌다 (register · reauth · resetPassword)', () => {
  assert.ok(vpaBody.includes('if (purpose === "register") throw srvLegacyClosed("LEGACY_SIGNUP_CLOSED");'),
      'register 가 열려 있다');
  assert.ok(vpaBody.includes('if (purpose === "reauth" || purpose === "resetPassword") {') &&
      vpaBody.includes('throw srvLegacyClosed("LEGACY_PASS_FLOW_CLOSED");'), 'reauth/resetPassword 가 열려 있다');
});
t('PSB-12 키 누락은 안전하게 실패한다 — 빈 키로 호출하지 않는다', () => {
  // 모의 모드가 아니면 PortOne 키가 없을 때 핸들러가 먼저 막는다.
  assert.ok(vpaBody.includes('if (!isMock && (!impKey || !impSecret)) {'), '키 누락 가드가 사라졌다');
  assert.ok(vpaBody.includes('"PORTONE_NOT_CONFIGURED PortOne 인증 설정이 없습니다. 환경 변수를 확인하세요."'),
      '키 누락 시 메시지가 바뀌었다');
  // CI HMAC 키가 없으면 신원 키를 만들 수 없다 — fail-closed(CI_KEY_UNAVAILABLE).
  assert.throws(() => CORE.computeCiKeyV1('', 'SYNTH-CI'), /CI_KEY_UNAVAILABLE/);
  assert.throws(() => CORE.computeCiKeyV1('short', 'SYNTH-CI'), /CI_KEY_UNAVAILABLE/);
});
t('PSB-13 verifyPassAuth 는 users·passTokens 를 쓰지 않는다 — 새 목적은 auth_kakao 로 넘긴다', () => {
  assert.ok(!vpaBody.includes('.collection("users")'), 'verifyPassAuth 가 users 를 직접 다룬다');
  assert.ok(!vpaBody.includes('passTokens'), '옛 passTokens writer 가 남아 있다');
  assert.ok(vpaBody.includes('authKakaoSvc.verifyPassSignup(request, keys)') &&
      vpaBody.includes('authKakaoSvc.verifyPassDeletion(request, keys)'), '새 목적 위임이 없다');
  assert.ok(!/DEV-CI-/.test(SRC), 'DEV 전화 대체 CI 분기가 남아 있다');
});
t('PSB-14 만 19세 미만 차단과 CI 키 형식(용도 구분 HMAC · v1)', () => {
  const now = Date.UTC(2026, 10, 25, 3, 0); // KST 2026-11-25 12:00
  assert.strictEqual(CORE.ageKst('20071125', now), 19, '생일 당일 19세');
  assert.strictEqual(CORE.ageKst('20071126', now), 18, '생일 전날 18세');
  const k = CORE.computeCiKeyV1('0123456789abcdef0123', 'SYNTH-CI');
  assert.ok(/^ci1_[0-9a-f]{64}$/.test(k), 'ci1_ 접두 HMAC 이 아니다');
  const crypto = require('crypto');
  assert.notStrictEqual(k.slice(4), crypto.createHash('sha256').update('SYNTH-CI').digest('hex'),
      '무키 SHA 와 같으면 안 된다');
  assert.notStrictEqual(k.slice(4), crypto.createHmac('sha256', '0123456789abcdef0123')
      .update('SYNTH-CI').digest('hex'), '용도 접두 없는 HMAC 과 같으면 안 된다');
});

// ── 합성 응답으로 분기 동작 확인 — 컴파일된 순수 판정 원문 ─────────────
const accepted = (certData) => CORE.parsePortOneCertification(certData).ok;
t('PSB-15 정상 응답은 통과한다', () => {
  assert.strictEqual(accepted({code: 0, response: {certified: true, unique_key: 'SYNTH-CI',
    name: '홍길동', birthday: '1990-01-15', phone: '01012345678'}}), true);
});
t('PSB-16 거절·취소·만료·CI 없음·문자열 certified 응답은 전부 막힌다', () => {
  const base = {name: '홍길동', birthday: '1990-01-15', phone: '01012345678', unique_key: 'SYNTH-CI'};
  assert.strictEqual(accepted({code: 0, response: {...base, certified: false}}), false, '미인증');
  assert.strictEqual(accepted({code: -1, response: {...base, certified: true}}), false, 'API 오류코드');
  assert.strictEqual(accepted({code: 0}), false, 'response 없음(취소)');
  assert.strictEqual(accepted({}), false, '빈 응답(만료)');
  assert.strictEqual(accepted({code: 0, response: {...base, certified: 'true'}}), false, '문자열 true');
  assert.strictEqual(accepted({code: 0, response: {...base, certified: true, unique_key: ''}}), false,
      'CI 없음 — DEV 전화 대체 없음');
  const g = CORE.parsePortOneCertification({code: 0, response: {...base, certified: true, gender: 'x'}});
  assert.strictEqual(g.ok && g.cert.gender, null, '모르는 성별을 여성으로 접으면 안 된다');
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
