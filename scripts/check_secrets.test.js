/**
 * [R7-SECURITY-P0-CONTAINMENT] 비밀값 탐지기 회귀 테스트.
 *
 *   이 검사기는 실제 사고를 한 번 놓쳤다 — `console.log(\`비밀번호: <평문>\`)`.
 *   그 형태를 **다시 놓치지 않는다는 것**을 고정한다.
 *
 *   테스트 입력은 전부 **가상의 더미값**이다. 실제로 노출된 값은 쓰지 않는다
 *   (테스트 파일 자체가 추적되므로, 진짜 값을 쓰면 같은 사고를 반복한다).
 *
 *   실행: node scripts/check_secrets.test.js
 */
'use strict';

const {scanLine} = require('./check_secrets');

// 더미값 — 의미 없는 자리표시자. 길이만 탐지 대상이 되게 한다.
const D16 = 'DUMMY-not-a-real-secret-0001';
const D10 = 'dummyvalue';

const CASES = [
  // ── 반드시 걸려야 하는 것 ─────────────────────────────────────
  {hit: true, why: '과거 사고 형태: 템플릿 + 한국어 레이블',
    line: 'console.log(`비밀번호: ' + D16 + '`);'},
  {hit: true, why: '작은따옴표 + 한국어 레이블',
    line: "console.log('비밀번호: " + D16 + "');"},
  {hit: true, why: '암호 레이블',
    line: 'console.error(`암호: ' + D10 + '`);'},
  {hit: true, why: '영문 레이블 + 로그',
    line: 'console.log(`password: ' + D16 + '`);'},
  {hit: true, why: '키=값 (기존 규칙)',
    line: "const password = '" + D16 + "';"},
  {hit: true, why: '객체 속성',
    line: 'auth.createUser({email, password: "' + D16 + '"});'},
  {hit: true, why: '주석 안의 자격증명',
    line: '// 비밀번호: ' + D16},
  {hit: true, why: '비번 축약 레이블',
    line: 'console.log(`비번: ' + D16 + '`);'},

  // ── 걸리면 안 되는 것(오탐) ───────────────────────────────────
  {hit: false, why: '환경변수 읽기',
    line: "const password = process.env.SUPER_ADMIN_PASSWORD || '';"},
  {hit: false, why: 'JS 보간 — 값은 코드 밖에서 온다',
    line: 'console.log(`비밀번호: ${password}`);'},
  {hit: false, why: 'Dart 보간',
    line: "print('비밀번호: \$password');"},
  {hit: false, why: '환경변수 이름 안내 문구',
    line: "console.error('SEED_PASSWORD 가 필요하다 (8자 이상)');"},
  {hit: false, why: '시크릿 이름을 언급하는 산문',
    line: "console.info(`TAX_ID_HMAC_SECRET 이 FOREIGN_HMAC_SECRET 과 같다`);"},
  {hit: false, why: '식별자 이름 일부(암호화)',
    line: "expect(s, contains('암호화된 값은 저장하지 않는다'));"},
  {hit: false, why: 'App Check 토큰 **이름** 언급',
    line: 'console.log(`App Check token 교환 실패`);'},
  {hit: false, why: '레이블 없는 일반 문자열',
    line: "const title = '골든패스 테스트 사업장';"},
];

let fail = 0;
for (const c of CASES) {
  const hits = scanLine(c.line);
  const got = hits.length > 0;
  const ok = got === c.hit;
  if (!ok) fail++;
  // 입력 줄은 출력하지 않는다 — 더미라도 형태만 말한다.
  console.log('  [' + (ok ? 'PASS' : 'FAIL') + '] ' +
    (c.hit ? '탐지 기대' : '오탐 금지').padEnd(10) + ' ' + c.why +
    (ok ? '' : '  → 실제 ' + (got ? '탐지됨(' + hits.map((h) => h.id).join(',') + ')' : '미탐지')));
}

console.log('\n' + CASES.length + '건 · 실패 ' + fail + '건');
process.exit(fail === 0 ? 0 : 1);
