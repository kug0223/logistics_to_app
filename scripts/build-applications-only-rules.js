/**
 * [APP-TRANSITION-ISOLATED] DEV 에 적용 중인 ruleset 원문에 **applications 블록만** 바꿔 넣은
 * 배포 후보를 만든다. 작업 트리 firestore.rules 전체를 복사하지 않는다(그 파일에는 배포 순서가
 * 다른 미배포 변경 — 사업장·공고·슬롯 삭제 금지 등 — 이 함께 있다).
 *
 *   node scripts/build-applications-only-rules.js <DEV ruleset 원문> <출력 경로>
 *
 *   증명: 주석·빈 줄을 뺀 코드 줄 비교에서 DEV 원문과 후보의 차이가 전부 applications
 *   블록 범위 안에 있어야 한다. 아니면 실패로 끝난다.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const [devPath, outPath] = process.argv.slice(2);
if (!devPath || !outPath) throw new Error('사용: <DEV ruleset> <출력>');
const SRC = path.join(__dirname, '..', 'firestore.rules');
const norm = (t) => t.replace(/\r\n/g, '\n');
const dev = norm(fs.readFileSync(devPath, 'utf8'));
const wt = norm(fs.readFileSync(SRC, 'utf8'));
const devEol = fs.readFileSync(devPath, 'utf8').includes('\r\n') ? '\r\n' : '\n';

const OPEN = 'match /applications/{applicationId} {';
/** 블록 [시작 줄, 끝 줄] — `//` 뒤는 세지 않고 중괄호 짝으로 닫힘을 찾는다. */
function blockRange(lines) {
  const s = lines.findIndex((l) => l.includes(OPEN));
  if (s < 0) throw new Error('applications 블록 없음');
  let depth = 0;
  for (let i = s; i < lines.length; i++) {
    const code = lines[i].split('//')[0];
    // 경로 안의 {applicationId} 같은 와일드카드도 중괄호 짝이 맞으므로 그대로 센다.
    for (const ch of code) { if (ch === '{') depth++; else if (ch === '}') depth--; }
    if (i > s && depth === 0) return [s, i];
    if (i === s && depth === 0) throw new Error('여는 줄에서 닫혔다');
  }
  throw new Error('블록이 닫히지 않는다');
}
const D = dev.split('\n'); const W = wt.split('\n');
const [ds, de] = blockRange(D); const [ws, we] = blockRange(W);
const out = [...D.slice(0, ds), ...W.slice(ws, we + 1), ...D.slice(de + 1)];
fs.writeFileSync(outPath, out.join(devEol));

// ── 증명: 코드 줄 차이가 applications 블록 안에만 있다
const codeLines = (lines, from, to) => lines.map((l, i) => ({i, c: l.split('//')[0].replace(/\s+$/, '')}))
  .filter((x) => x.c.trim() !== '' && (from == null || (x.i >= from && x.i <= to)));
const [os, oe] = blockRange(out);
const outsideDev = [...codeLines(D, 0, ds - 1), ...codeLines(D, de + 1, D.length)].map((x) => x.c);
const outsideOut = [...codeLines(out, 0, os - 1), ...codeLines(out, oe + 1, out.length)].map((x) => x.c);
const sameOutside = outsideDev.length === outsideOut.length && outsideDev.every((c, k) => c === outsideOut[k]);
// 블록 밖은 주석까지 바이트 동일해야 한다(원문 그대로 붙였으므로)
const rawOutside = D.slice(0, ds).join('\n') === out.slice(0, os).join('\n') &&
  D.slice(de + 1).join('\n') === out.slice(oe + 1).join('\n');
const inDev = codeLines(D, ds, de).map((x) => x.c); const inOut = codeLines(out, os, oe).map((x) => x.c);
console.log(`DEV applications 블록 ${ds + 1}~${de + 1}행(코드 ${inDev.length}줄) → 후보 ${os + 1}~${oe + 1}행(코드 ${inOut.length}줄)`);
console.log(`블록 밖 코드 줄 동일: ${sameOutside} (${outsideDev.length}줄) · 블록 밖 원문(주석 포함) 바이트 동일: ${rawOutside}`);
console.log(`후보 ${out.length}줄 → ${outPath}`);
if (!sameOutside || !rawOutside) { console.log('FAIL: applications 블록 밖에 차이가 있다'); process.exit(1); }
