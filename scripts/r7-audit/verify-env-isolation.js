/**
 * R7 §3 — 감사 실행 시 env/secret 격리 검증. **값은 출력하지 않는다.**
 *
 * 확인하는 것:
 *   1. `functions/.env` 의 모든 키가 `functions/.env.<project>` 로 덮였는가.
 *   2. 덮은 값이 원본과 실제로 다른가 (해시 비교 — 값 노출 없음).
 *   3. 감사 override 가 실서비스로 새지 않는가 (파일명이 demo 프로젝트 한정인가).
 *
 *   node scripts/r7-audit/verify-env-isolation.js [projectId]
 *   기본 projectId = demo-alfit-r7
 */
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const PROJECT = process.argv[2] || 'demo-alfit-r7';
const FUNCTIONS = path.join(__dirname, '..', '..', 'functions');
const BASE = path.join(FUNCTIONS, '.env');
const OVERRIDE = path.join(FUNCTIONS, `.env.${PROJECT}`);

function parse(file) {
  if (!fs.existsSync(file)) return null;
  const out = new Map();
  for (const line of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    const t = line.trim();
    if (!t || t.startsWith('#')) continue;
    const i = t.indexOf('=');
    if (i <= 0) continue;
    out.set(t.slice(0, i).trim(), t.slice(i + 1));
  }
  return out;
}

/** 값 자체는 절대 찍지 않는다 — 같은지 다른지만 본다. */
const digest = (v) => crypto.createHash('sha256').update(v).digest('hex').slice(0, 12);

const base = parse(BASE);
const over = parse(OVERRIDE);

if (!base) { console.error(`functions/.env 없음 — 확인할 것이 없다`); process.exit(1); }
if (!over) {
  console.error(`functions/.env.${PROJECT} 없음 — 실자격증명이 그대로 로드된다. 감사 실행 금지.`);
  process.exit(1);
}

const rows = [];
let bad = 0;
for (const [k, v] of base) {
  const has = over.has(k);
  const differs = has && digest(over.get(k)) !== digest(v);
  if (!has || !differs) bad++;
  rows.push({
    key: k,
    overridden: has,
    differs,
    verdict: !has ? '덮이지 않음 — 실값 로드' : (differs ? 'OK' : '같은 값 — 덮은 의미 없음'),
  });
}
const extra = [...over.keys()].filter((k) => !base.has(k));

console.log(`프로젝트: ${PROJECT}`);
console.log(`base: functions/.env (${base.size} keys)`);
console.log(`override: functions/.env.${PROJECT} (${over.size} keys)\n`);
console.log('| key | override | 값이 다른가 | 판정 |');
console.log('|---|---|---|---|');
for (const r of rows) {
  console.log(`| ${r.key} | ${r.overridden ? 'Y' : 'N'} | ${r.differs ? 'Y' : 'N'} | ${r.verdict} |`);
}
if (extra.length) console.log(`\noverride 에만 있는 키(무해): ${extra.join(', ')}`);

console.log('\n로드 순서는 firebase-tools 가 출력한다:');
console.log('  "Loaded environment variables from functions\\.env, functions\\.env.<project>"');
console.log('  뒤에 오는 파일이 키 단위로 이긴다.');

if (!PROJECT.startsWith('demo-')) {
  console.log('\n⚠️ projectId 가 demo- 로 시작하지 않는다 — 비에뮬 서비스 접근이 차단되지 않는다.');
  process.exit(1);
}
if (bad > 0) { console.log(`\n✘ ${bad}개 키가 격리되지 않았다.`); process.exit(1); }
console.log(`\n✔ ${rows.length}개 키 전부 감사 전용 값으로 격리됨.`);
