// [R8-RELEASE-BASELINE §E] 배포 소스에 운영자 스크립트·테스트가 다시 끼지 않게 못박는다.
//
//   실행:  cd functions && node test/deploy_package_exclusion.test.js
//
//   왜 필요한가
//     2026-10-10 배포 아카이브에는 `create_super_admin.js`(한때 평문 비밀번호를
//     들고 있었다)·`seed_*.js`·`test/`·`src/` 가 들어 있었다. 고친 것은
//     `firebase.json` 의 `functions.ignore` **한 줄**이고, 그 설정에는 아무
//     회귀 가드가 없었다 — 누가 firebase.json 을 다시 만들면 조용히 되돌아간다.
//
//   무엇을 고정하는가
//     ① CLI 의 실제 규칙을 그대로 재현해 "무엇이 패키지에 들어가는지"를 센다.
//        firebase-tools 15.31.0 기준:
//          prepareFunctionsUpload.js:77  const ignore = config.ignore || ["node_modules",".git"]
//          prepareFunctionsUpload.js:78  ignore.push("firebase-debug.log","firebase-debug.*.log",".runtimeconfig.json")
//          fsAsync.js                    minimatch(절대경로, glob, {matchBase:true, dot:true})
//        `.gcloudignore`·`.gitignore` 는 **보지 않는다**. 레버는 이 배열뿐이다.
//     ② 런타임에 필요한 것이 빠지지 않았는지도 같이 센다 — 제외가 과해도 사고다.
//
//   이 테스트는 네트워크를 쓰지 않는다. 배포하지 않는다.
'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const minimatchNs = require('minimatch');
const minimatch = typeof minimatchNs === 'function' ? minimatchNs : minimatchNs.minimatch;

const FUNCTIONS_DIR = __dirname.replace(/[\\/]test$/, '');
const ROOT = path.dirname(FUNCTIONS_DIR);

let pass = 0;
const fails = [];
function t(name, fn) {
  try {
    fn();
    pass++;
  } catch (e) {
    fails.push(`${name}: ${e.message}`);
  }
}

// firebase.json 에는 BOM 이 있다 — CLI 는 처리하지만 JSON.parse 는 걸린다.
const cfg = JSON.parse(
    fs.readFileSync(path.join(ROOT, 'firebase.json'), 'utf8').replace(/^﻿/, ''));
const fnCfg = (cfg.functions || []).find((c) => c.source === 'functions');

// ── CLI 와 같은 규칙으로 패키지 목록을 만든다 ──────────────────────────
function packagedFiles() {
  assert.ok(fnCfg, 'firebase.json 에 functions(source=functions) 항목이 없다');
  const ignore = [...(fnCfg.ignore || ['node_modules', '.git']),
    'firebase-debug.log', 'firebase-debug.*.log', '.runtimeconfig.json'];
  const opts = {matchBase: true, dot: true};
  const ignored = (p) => ignore.some((g) => minimatch(p, g, opts));

  const out = [];
  (function walk(dir) {
    for (const e of fs.readdirSync(dir, {withFileTypes: true})) {
      const p = path.join(dir, e.name);
      if (ignored(p)) continue;
      if (e.isDirectory()) walk(p);
      else out.push(path.relative(FUNCTIONS_DIR, p).split(path.sep).join('/'));
    }
  })(FUNCTIONS_DIR);
  return new Set(out);
}

const packaged = packagedFiles();

// ① 들어가면 안 되는 것 — 운영자 도구·시드·테스트·TS 원본
const MUST_NOT = [
  ['bootstrap 스크립트', 'create_super_admin.js'],
  ['시드 스크립트(PASS 토큰)', 'seed_pass_token.js'],
  ['시드 스크립트(TO)', 'seed_tos.js'],
  ['벤치마크', 'benchmark_synthetic.js'],
  ['이 테스트 자신', 'test/deploy_package_exclusion.test.js'],
  ['서버 테스트', 'test/commitment_dates.test.js'],
  ['TS 원본', 'src/index.ts'],
  ['소스맵', 'lib/index.js.map'],
  ['빌드 설정', 'tsconfig.json'],
  ['린트 설정', '.eslintrc.js'],
];
for (const [label, rel] of MUST_NOT) {
  t(`DPE-01 ${label} 은 패키지에 없다 (${rel})`, () => {
    assert.ok(!packaged.has(rel), `${rel} 이 배포 소스에 들어간다`);
  });
}

// ② 빠지면 안 되는 것 — 런타임 진입점과 의존성 메타
const MUST = ['package.json', 'package-lock.json', 'lib/index.js'];
for (const rel of MUST) {
  t(`DPE-02 런타임 필수 파일이 남아 있다 (${rel})`, () => {
    assert.ok(packaged.has(rel), `${rel} 이 배포 소스에서 빠졌다`);
  });
}

t('DPE-03 컴파일된 모듈이 전부 남아 있다', () => {
  // src 를 제외하므로 lib 쪽이 유일한 실행 코드다. 하나라도 빠지면 require 가 깨진다.
  const libFiles = fs.readdirSync(path.join(FUNCTIONS_DIR, 'lib'))
      .filter((f) => f.endsWith('.js'));
  assert.ok(libFiles.length > 0, 'lib 에 컴파일 산출물이 없다 — 먼저 빌드해야 한다');
  for (const f of libFiles) {
    assert.ok(packaged.has(`lib/${f}`), `lib/${f} 이 빠졌다`);
  }
});

// ③ `ignore` 를 지정하면 CLI 기본값이 **대체된다** — 직접 적어 둔 것이 유지되는지
t('DPE-04 ignore 를 쓰면 기본값이 대체되므로 직접 적은 항목이 남아 있어야 한다', () => {
  const ig = fnCfg.ignore || [];
  for (const must of ['node_modules', '.git', '.env', '.env.*', '*-adminsdk-*.json']) {
    assert.ok(ig.includes(must),
        `ignore 에서 ${must} 가 사라졌다 — 지정 시 기본값은 복구되지 않는다`);
  }
});

t('DPE-05 비밀 파일은 애초에 패키지에 없다', () => {
  // 이 둘은 `ignore` 규칙으로 막혀 있고, 실제로 2026-10-10 번들에도 없었다.
  for (const rel of ['.env', '.env.demo-alfit-r7']) {
    assert.ok(!packaged.has(rel), `${rel} 이 배포 소스에 들어간다`);
  }
  const adminsdk = [...packaged].filter((p) => /-adminsdk-.*\.json$/.test(p));
  assert.deepStrictEqual(adminsdk, [], '서비스계정 키가 배포 소스에 들어간다');
});

t('DPE-06 패키지에 들어가는 파일 수가 과하지 않다', () => {
  // 지금은 12개다. 갑자기 늘면 새 디렉터리가 제외 없이 추가된 것이다.
  // 상한만 둔다 — 정확한 수를 못박으면 파일 하나 늘 때마다 깨진다.
  assert.ok(packaged.size <= 40,
      `패키지 파일이 ${packaged.size}개다 — 제외 규칙을 다시 봐야 한다`);
});

console.log('─'.repeat(30));
if (fails.length) {
  fails.forEach((f) => console.log('  FAIL ' + f));
  console.log(`총 ${pass + fails.length}건 · 실패 ${fails.length}건`);
  process.exit(1);
}
console.log(`총 ${pass}건 · 실패 0건`);
