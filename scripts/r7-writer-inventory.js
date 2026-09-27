/**
 * R7 §3B — staffing 카운트 writer 인벤토리.
 *
 * functions/src/index.ts 를 훑어, 원장(applications)·슬롯 카운터
 * (workDetailCounts)·TO 합계(totalConfirmed/totalPending/totalRequired)를
 * **쓰는** 지점을 찾아 각각이 속한 export 함수로 묶는다.
 *
 * 읽기 전용 정적 분석이다. Firestore 에 접속하지 않는다.
 *   node scripts/r7-writer-inventory.js            → 표
 *   node scripts/r7-writer-inventory.js --json     → JSON
 */
const fs = require('fs');
const path = require('path');

const SRC = path.join(__dirname, '..', 'functions', 'src', 'index.ts');
const lines = fs.readFileSync(SRC, 'utf8').split(/\r?\n/);

// export const <name> = onCall / onDocumentWritten / onSchedule ...
const DECL = /^export\s+(?:const|async\s+function|function)\s+([A-Za-z0-9_]+)/;

/** 각 줄이 속한 최상위 export 이름 */
const ownerOf = new Array(lines.length).fill(null);
let current = null;
lines.forEach((l, i) => {
  const m = DECL.exec(l);
  if (m) current = m[1];
  ownerOf[i] = current;
});

/** 그 export 가 어떤 종류인지 — 선언 줄 이후 몇 줄 안에서 판단 */
function kindOf(name) {
  const at = lines.findIndex((l) => DECL.exec(l)?.[1] === name);
  if (at < 0) return 'unknown';
  const head = lines.slice(at, at + 6).join(' ');
  if (head.includes('onCall(')) return 'callable';
  if (head.includes('onDocumentWritten') || head.includes('onDocumentCreated') ||
      head.includes('onDocumentUpdated') || head.includes('onDocumentDeleted')) return 'trigger';
  if (head.includes('onSchedule')) return 'scheduler';
  if (head.includes('onRequest')) return 'http';
  return 'helper';
}

/** 쓰기로 볼 표현 */
const WRITE_VERBS = /\.(set|update|create|delete)\(|FieldValue\.increment|FieldValue\.arrayUnion|FieldValue\.arrayRemove|FieldValue\.delete\(/;

const TARGETS = [
  {key: 'ledger:applications', re: /collection\("applications"\)/},
  {key: 'counter:workDetailCounts', re: /workDetailCounts/},
  {key: 'to:totalConfirmed', re: /totalConfirmed/},
  {key: 'to:totalPending', re: /totalPending/},
  {key: 'to:totalRequired', re: /totalRequired/},
];

/** 같은 문장(또는 인접 4줄)에 쓰기 동사가 있으면 write 로 본다 — 보수적으로 넓게 잡는다. */
function nearWrite(i) {
  for (let j = Math.max(0, i - 4); j <= Math.min(lines.length - 1, i + 4); j++) {
    if (WRITE_VERBS.test(lines[j])) return true;
  }
  return false;
}

const byOwner = new Map();
lines.forEach((l, i) => {
  if (l.trimStart().startsWith('//') || l.trimStart().startsWith('*')) return;
  for (const t of TARGETS) {
    if (!t.re.test(l)) continue;
    const isWrite = nearWrite(i);
    const owner = ownerOf[i] ?? '(top-level)';
    if (!byOwner.has(owner)) {
      byOwner.set(owner, {owner, kind: kindOf(owner), targets: new Map()});
    }
    const rec = byOwner.get(owner);
    if (!rec.targets.has(t.key)) rec.targets.set(t.key, {write: 0, read: 0, lines: []});
    const e = rec.targets.get(t.key);
    if (isWrite) e.write++; else e.read++;
    if (e.lines.length < 6) e.lines.push(i + 1);
  }
});

/** transaction / batch 안인지 — 원자성 근거 */
function atomicityOf(owner) {
  const at = lines.findIndex((l) => DECL.exec(l)?.[1] === owner);
  if (at < 0) return '-';
  // 다음 export 선언까지를 본문으로 본다
  let end = lines.length;
  for (let j = at + 1; j < lines.length; j++) {
    if (DECL.test(lines[j])) { end = j; break; }
  }
  const body = lines.slice(at, end).join('\n');
  const tx = /runTransaction\(/.test(body);
  const batch = /\.batch\(\)/.test(body);
  const bulk = /bulkWriter|BulkWriter/.test(body);
  const parts = [];
  if (tx) parts.push('transaction');
  if (batch) parts.push('batch');
  if (bulk) parts.push('bulkWriter');
  return parts.length ? parts.join('+') : 'single-write';
}

const rows = [...byOwner.values()]
  .map((r) => ({
    owner: r.owner,
    kind: r.kind,
    atomicity: atomicityOf(r.owner),
    targets: [...r.targets.entries()].map(([k, v]) => ({
      target: k, write: v.write, read: v.read, lines: v.lines,
    })),
    writes: [...r.targets.values()].reduce((s, v) => s + v.write, 0),
  }))
  .filter((r) => r.writes > 0)
  .sort((a, b) => b.writes - a.writes);

if (process.argv.includes('--json')) {
  console.log(JSON.stringify(rows, null, 2));
} else {
  console.log(`writer 후보 ${rows.length}개 (쓰기 표현이 인접한 것만)\n`);
  console.log('| owner | 종류 | 원자성 | 대상(쓰기수) |');
  console.log('|---|---|---|---|');
  for (const r of rows) {
    const t = r.targets.filter((x) => x.write > 0)
      .map((x) => `${x.target}(${x.write})`).join(' · ');
    console.log(`| ${r.owner} | ${r.kind} | ${r.atomicity} | ${t} |`);
  }
}
