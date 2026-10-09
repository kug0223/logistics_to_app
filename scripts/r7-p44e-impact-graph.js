/**
 * [R7-P4.4E §3/§4] 배포 영향 export 계산 — READ ONLY.
 *
 *   commit range 를 배포 대상으로 그대로 쓰지 않는다. 변경된 **라인**이
 *   어느 top-level 심볼 안에 있는지 찾고, 그 심볼이 export 가 아니면
 *   호출자를 따라 올라가 최종 Cloud Function export 집합을 만든다.
 *
 * 사용: node scripts/r7-p44e-impact-graph.js <baseRef>
 */
'use strict';

const {execFileSync} = require('child_process');
const fs = require('fs');

const base = process.argv[2];
if (!base) { console.error('사용: node scripts/r7-p44e-impact-graph.js <baseRef>'); process.exit(1); }

const FILE = 'functions/src/index.ts';
const src = fs.readFileSync(FILE, 'utf8');
const lines = src.split('\n');

// ── 1. top-level 심볼 경계 수집 (0-indent 선언부터 다음 0-indent 선언까지)
const decl = /^(?:export\s+)?(?:const|let|var|function|async\s+function|class|type|interface|enum)\s+([A-Za-z_$][\w$]*)/;
const symbols = []; // {name, start, end, exported, isFunctionExport}
for (let i = 0; i < lines.length; i++) {
  const m = decl.exec(lines[i]);
  if (!m) continue;
  symbols.push({
    name: m[1],
    start: i + 1,
    end: null,
    exported: /^export\s/.test(lines[i]),
  });
}
// 끝은 **중괄호 균형**으로 정한다. 다음 선언 직전까지로 잡으면 함수 사이의
// 주석 블록이 창 안에 들어와, 바뀌지도 않은 함수가 영향 집합에 섞인다
// (hasValidBusinessLicense 가 실제로 그렇게 오탐됐다).
for (let i = 0; i < symbols.length; i++) {
  const hardEnd = i + 1 < symbols.length ? symbols[i + 1].start - 1 : lines.length;
  let depth = 0;
  let started = false;
  let end = symbols[i].start;
  for (let ln = symbols[i].start; ln <= hardEnd; ln++) {
    const text = lines[ln - 1];
    for (const ch of text) {
      if (ch === '{' || ch === '(' || ch === '[') { depth++; started = true; } else
      if (ch === '}' || ch === ')' || ch === ']') depth--;
    }
    end = ln;
    if (started && depth <= 0) break;
  }
  // 선언 한 줄로 끝나는 type/interface 별칭도 자기 줄만 갖는다.
  symbols[i].end = Math.max(end, symbols[i].start);
}

// Cloud Function export 판별 — 선언 본문에 trigger factory 가 있어야 한다.
const TRIGGER = /\b(onCall|onRequest|onSchedule|onDocumentWritten|onDocumentCreated|onDocumentUpdated|onDocumentDeleted|onObjectFinalized|beforeUserCreated|onTaskDispatched|onMessagePublished)\s*\(/;
for (const s of symbols) {
  const body = lines.slice(s.start - 1, Math.min(s.end, s.start + 40)).join('\n');
  s.isFn = s.exported && TRIGGER.test(body);
}

const byName = new Map(symbols.map((s) => [s.name, s]));
const symbolAt = (lineNo) =>
  symbols.find((s) => lineNo >= s.start && lineNo <= s.end) || null;

// ── 2. 변경 라인 (HEAD 쪽 라인번호)
const diff = execFileSync(
  `git diff -U0 ${base}..HEAD -- ${FILE}`,
  {encoding: 'utf8', maxBuffer: 64 * 1024 * 1024, shell: true}
);
const changedLines = new Set();
for (const hunk of diff.split('\n')) {
  const m = /^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/.exec(hunk);
  if (!m) continue;
  const start = Number(m[1]);
  const count = m[2] == null ? 1 : Number(m[2]);
  for (let i = 0; i < Math.max(count, 1); i++) changedLines.add(start + i);
}

const touched = new Set();
for (const ln of changedLines) {
  const s = symbolAt(ln);
  if (s) touched.add(s.name);
}

// ── 3. 호출 그래프 — 변경 심볼이 helper 면 소비 export 까지 올린다
const callersOf = (name) => {
  const re = new RegExp(`\\b${name}\\s*\\(`);
  const out = [];
  for (const s of symbols) {
    if (s.name === name) continue;
    const body = lines.slice(s.start - 1, s.end).join('\n');
    if (re.test(body)) out.push(s.name);
  }
  return out;
};

const exportsHit = new Set();
const helperChain = new Map(); // helper -> [소비 export]
const seen = new Set();
const walk = (name, depth) => {
  if (seen.has(name) || depth > 6) return;
  seen.add(name);
  const s = byName.get(name);
  if (!s) return;
  if (s.isFn) { exportsHit.add(name); return; }
  const callers = callersOf(name);
  for (const c of callers) {
    const cs = byName.get(c);
    if (cs && cs.isFn) {
      exportsHit.add(c);
      if (!helperChain.has(name)) helperChain.set(name, []);
      helperChain.get(name).push(c);
    } else {
      walk(c, depth + 1);
    }
  }
};

for (const t of touched) {
  seen.clear();
  walk(t, 0);
}

// ── 4. 보고
console.log('=== 기준:', base, '→ HEAD ===');
console.log('변경 라인:', changedLines.size, '줄');
console.log('\n=== 변경이 닿은 top-level 심볼 ===');
for (const t of [...touched].sort()) {
  const s = byName.get(t);
  console.log(' ', t, s && s.isFn ? '  [Cloud Function export]' : '  (helper/기타)');
}

console.log('\n=== helper → 소비 export ===');
if (helperChain.size === 0) console.log('  (helper 경유 없음)');
for (const [h, cs] of helperChain) {
  console.log(' ', h, '→', [...new Set(cs)].sort().join(', '));
}

const finalSet = [...exportsHit].sort();
console.log('\n=== 배포 후보 export', finalSet.length, '개 ===');
for (const e of finalSet) console.log(' ', e);
console.log('\n--targets--');
console.log(finalSet.map((e) => `functions:${e}`).join(','));
