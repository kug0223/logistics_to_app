/**
 * [R7-SECURITY-P0] Git 추적 파일에 비밀값이 다시 들어가는 것을 막는 검사.
 *
 *   이 저장소는 **공개**다(github.com/kug0223/logistics_to_app). 한 번
 *   커밋되면 이력에서 지우기 어렵고, 지워도 이미 읽힌 것은 되돌릴 수 없다.
 *   그래서 커밋 **전에** 본다.
 *
 *   검사 대상은 `git ls-files` — 즉 **추적되는 파일만**이다. 서비스계정 키나
 *   `.env` 처럼 gitignore 로 막아 둔 파일은 애초에 대상이 아니고, 그 사실을
 *   함께 확인해 준다(무시 규칙이 풀리면 여기서 걸린다).
 *
 *   값은 출력하지 않는다 — 파일·행·종류·길이만 말한다. 검사 결과를 로그나
 *   보고서에 붙여도 비밀이 새지 않아야 한다.
 *
 *   실행: node scripts/check_secrets.js
 *   종료코드: 0 깨끗함 / 1 의심 발견
 */
'use strict';

const fs = require('fs');
const {execSync} = require('child_process');

// 값이 **리터럴로 박힌** 경우만 본다. process.env 읽기는 정상이다.
const RULES = [
  {id: 'SEC-PW', desc: '평문 비밀번호 리터럴',
    re: /(password|passwd|pwd)\s*[:=]\s*(['"`])([^'"`\n]{4,})\2/i, group: 3},
  {id: 'SEC-SECRET', desc: '시크릿·토큰 리터럴',
    re: /(secret|clientSecret|api_secret|apiSecret|accessToken|refreshToken)\s*[:=]\s*(['"`])([^'"`\n]{8,})\2/i,
    group: 3},
  {id: 'SEC-KEY', desc: '사설키 블록',
    re: /-----BEGIN [A-Z ]*PRIVATE KEY-----/, group: 0},
  {id: 'SEC-SA', desc: '서비스계정 JSON(private_key 필드)',
    re: /"private_key"\s*:/, group: 0},
  {id: 'SEC-APPCHECK', desc: 'App Check 디버그 토큰 리터럴',
    re: /(debugToken|appCheckDebugToken|APP_CHECK_DEBUG[A-Z_]*)\s*[:=]\s*(['"`])([0-9a-fA-F-]{20,})\2/,
    group: 3},
  {id: 'SEC-ENVVAL', desc: '.env 형식 값 할당(키 이름이 시크릿류)',
    re: /^(?!#)\s*[A-Z0-9_]*(SECRET|PASSWORD|PRIVATE_KEY|ENCRYPT_KEY|TOKEN)[A-Z0-9_]*\s*=\s*\S+/,
    group: 0},
];

// ── 문자열 **안쪽**에 박힌 자격증명 ────────────────────────────────
//
//   [R7-SECURITY-P0-CONTAINMENT] 이 검사기는 실제 사고를 놓쳤다.
//   놓친 형태는 `키 = "값"` 이 아니었다:
//
//       console.log(`비밀번호: <평문>`);
//
//   한국어 레이블 + 템플릿 문자열 안의 리터럴이라 위 RULES 의 어떤 패턴에도
//   걸리지 않았다. 그 하나의 맹점이 전수 스캔·이력 검색·공개 URL 검사를
//   동시에 오염시켰다 — 같은 정규식을 셋이 함께 썼기 때문이다.
//
//   그래서 **문자열 리터럴을 꺼내서** 그 안을 본다. 판정 규칙:
//     · 레이블(비밀번호·암호·password…) 뒤에 값이 오고
//     · 그 값이 `${...}` 보간이 아니라 **리터럴 토큰**이면 의심.
//   보간은 값이 코드 밖에서 오므로 정상이다 — 그것까지 막으면 로그를 못 쓴다.
//   오탐의 유일한 원인은 **이름을 언급한 문장**이었다:
//   `SEED_PASSWORD`, `HMAC_SECRET`, `DEBUG_TOKEN`, `nHmacSecret`, `App Check token`
//   — 환경변수·심볼 이름을 안내하는 문구다. 그래서 세 가지를 함께 본다:
//     ① 레이블이 식별자의 일부면 제외(앞 글자가 영숫자·_·$)
//     ② 값이 ENV 이름 형태(ALL_CAPS_WITH_UNDERSCORE)면 제외 — 안내 문구다
//     ③ `${...}` 와 Dart 의 `$name` 보간은 값이 아니다
const CRED_LABEL =
  /(?:^|[^A-Za-z0-9_$])(비밀번호|비번|암호|패스워드|password|passwd|pwd|secret|시크릿)\s*[:=]?\s*[::]?\s*$/i;
/** 환경변수·상수 이름을 값으로 오인하지 않는다. */
const LOOKS_LIKE_ENV_NAME = /^[A-Z][A-Z0-9_]{5,}$/;
/** 한 줄에서 '…' "…" `…` 리터럴을 모두 꺼낸다(중첩·이스케이프는 다루지 않는다). */
function stringLiterals(line) {
  const out = [];
  const re = /(['"`])((?:\\.|(?!\1)[\s\S])*)\1/g;
  let m;
  while ((m = re.exec(line)) !== null) out.push(m[2]);
  return out;
}
/** 주석 본문 — 비밀번호는 주석에도 적힌다("// 비밀번호: …"). */
function commentText(line) {
  const slash = line.indexOf('//');
  const hash = line.search(/(^|\s)#\s/);
  const star = /^\s*\*/.test(line) ? line.indexOf('*') + 1 : -1;
  const at = [slash, hash, star].filter((i) => i >= 0).sort((a, b) => a - b)[0];
  return at == null ? null : line.slice(at);
}

/** 문자열 안의 '레이블 + 리터럴 값' 탐지. 값 길이만 돌려준다. */
function credentialInString(line) {
  const comment = commentText(line);
  for (const lit of [...stringLiterals(line), ...(comment ? [comment] : [])]) {
    // 보간 구간은 값이 아니다 — JS `${...}` 와 Dart `$name` 모두 비운다.
    const masked = lit
        .replace(/\$\{[^}]*\}/g, '\u0000')
        .replace(/\$[A-Za-z_][A-Za-z0-9_]*/g, '\u0000');
    const parts = masked.split(/[::]|=/);
    for (let i = 0; i < parts.length - 1; i++) {
      if (!CRED_LABEL.test(parts[i] + ':')) continue;
      const rest = parts.slice(i + 1).join(':');
      const token = (rest.match(/[^\s\u0000'"`,){}]{6,}/) || [])[0];
      if (token && !LOOKS_LIKE_ENV_NAME.test(token)) return token.length;
    }
  }
  return null;
}

// 벤더 코드·바이너리·골든 파일은 보지 않는다. 오탐이 많아 신호를 덮는다.
const SKIP = /(^|\/)(node_modules|build|\.dart_tool|\.gradle|coverage)\//;
const BINARY = /\.(png|jpe?g|gif|webp|ico|pdf|jar|ttf|otf|woff2?|zip|keystore|jks|mp4|aab|apk)$/i;
// 순수 함수 테스트의 더미 입력은 라이브 자격증명이 아니다 —
//   네트워크를 쓰지 않는 시뮬레이션 테스트만 면제하고, 면제 사실을 출력한다.
const TEST_FIXTURE = /^test\/simulation\//;

function tracked() {
  return execSync('git ls-files', {encoding: 'utf8', maxBuffer: 64 * 1024 * 1024})
    .split(/\r?\n/).filter(Boolean);
}

/** gitignore 로 막혀 있어야 하는 것들 — 풀렸으면 그 자체가 사고다. */
const MUST_IGNORE = [
  'functions/.env',
  'functions/*-adminsdk-*.json',
  'scripts/*-adminsdk-*.json',
];

/**
 * 한 줄을 검사한다 — 규칙 표 + 문자열 내부 탐지.
 *
 * @param {string} line 소스 한 줄
 * @return {Array<{id: string, desc: string, len: number}>} 의심 목록(값 미포함)
 */
function scanLine(line) {
  const out = [];
  for (const r of RULES) {
    const m = line.match(r.re);
    if (!m) continue;
    out.push({id: r.id, desc: r.desc,
      len: r.group ? String(m[r.group] || '').length : 0});
  }
  const inStr = credentialInString(line);
  if (inStr != null) {
    out.push({id: 'SEC-INSTR', desc: '문자열·로그 안의 자격증명 리터럴', len: inStr});
  }
  return out;
}

function main() {
  const files = tracked().filter((f) => !SKIP.test(f) && !BINARY.test(f));
  const hits = [];
  const exempt = [];
  for (const f of files) {
    let text;
    try {
      text = fs.readFileSync(f, 'utf8');
    } catch (e) {
      continue;
    }
    const lines = text.split(/\r?\n/);
    for (let i = 0; i < lines.length; i++) {
      for (const row of scanLine(lines[i])) {
        const full = Object.assign({file: f, line: i + 1}, row);
        if (TEST_FIXTURE.test(f)) exempt.push(full);
        else hits.push(full);
      }
    }
  }

  console.log('=== 비밀값 검사 (추적 파일 ' + files.length + '개) ===');
  for (const h of hits) {
    console.log('  [의심] ' + h.id + ' ' + h.file + ':' + h.line +
      '  ' + h.desc + (h.len ? ' (값 길이 ' + h.len + ', 값 미출력)' : ''));
  }
  if (exempt.length > 0) {
    console.log('  (면제 ' + exempt.length + '건: test/simulation 순수 함수 테스트의 더미 입력)');
  }

  // 무시 규칙 확인 — 비밀 파일이 추적으로 넘어오지 않았는지.
  console.log('\n--- gitignore 유지 확인 ---');
  let ignoreBroken = 0;
  for (const pat of MUST_IGNORE) {
    let out = '';
    try {
      out = execSync('git ls-files -- "' + pat + '"', {encoding: 'utf8'}).trim();
    } catch (e) {
      out = '';
    }
    if (out) {
      ignoreBroken++;
      console.log('  [의심] 추적되고 있다: ' + pat + ' → ' + out.split(/\r?\n/).join(', '));
    } else {
      console.log('  [OK] 미추적: ' + pat);
    }
  }

  const total = hits.length + ignoreBroken;
  console.log('\n===========================');
  if (total === 0) {
    console.log('[OK] 추적 파일에 비밀값 없음');
  } else {
    console.log('[WARNING] 총 ' + total + '건 — 커밋 전에 제거하거나 환경변수로 옮겨라');
  }
  process.exit(total === 0 ? 0 : 1);
}

// 회귀 테스트가 판정 함수만 불러 쓸 수 있게 진입점을 분리한다.
module.exports = {scanLine, credentialInString};
if (require.main === module) main();
