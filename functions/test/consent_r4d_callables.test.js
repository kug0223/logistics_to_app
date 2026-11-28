/**
 * [CONSENT-R4b · Codex 감사 C-R4-5] 두 callable 을 **원문 그대로** 꺼내 가짜 Firestore 위에서 실행한다.
 *
 *   대상: 후보 index.ts 의 `callableAcceptTOInvitation` · `callableAcceptConfirmedReassignment`
 *         (첫 작성 기준 후보 sha256 b9480f37… · 이후 H15 판정 시각=max(confirmedAt, Date.now()) 와
 *         기간 판정 블록 교체가 있었다 — 이 파일의 시나리오 기대는 바뀌지 않는다(정적 대조:
 *         r4b_changes.md §3). 줄 번호 주석은 첫 작성 기준이다). 문자열 순서 검사가 아니라
 *         callable 본문과 그 **의존 폐포 전체**(최상위 함수·상수·가져온 이름)를 TypeScript 로
 *         변환해 실행하고, 읽기·트랜잭션 쓰기 시도·커밋·트랜잭션 밖 쓰기·알림을 따로 센다.
 *
 *   방식(기존 test/invite_preaccept_consent.test.js 와 같은 계열 — 원문 추출 → ts.transpileModule →
 *   new Function 주입). 두 callable 이 각 800·480줄이고 helper 가 많으므로 폐포는 **AST 로 자동 계산**한다:
 *     1) index.ts 를 파싱해 최상위 선언표(함수·const/let·class·enum)와 import 표를 만든다.
 *     2) 두 callable 문장에서 출발해, 값 위치의 식별자를 TypeScript 검사기(getSymbolAtLocation ·
 *        getShorthandAssignmentValueSymbol)로 선언에 묶는다. 선언이 최상위면 그 문장을 넣고 재귀.
 *        (검사기를 만들 수 없거나 R4B_CLOSURE=names 면 이름 기반 과포함으로 떨어진다.)
 *     3) `./x` 에서 가져온 이름은 ../src/x.ts 를 CommonJS 로 변환해 그 export 를 가져온 지역 이름
 *        (`import {a as b}` 의 b)으로 주입한다. 외부 패키지(firebase-admin·firebase-functions/*)는 스텁.
 *     4) 함수 선언(끌어올림)을 먼저, 그 밖의 선언은 **원본 순서**로 낸다 — 원본이 그 순서로 평가돼 왔으므로
 *        모듈 평가 시점에 참조되는 상수는 항상 먼저 정의된다.
 *     5) 폐포가 모르는 최상위 이름·로컬 모듈 export 를 만나면 그 이름으로 assert 실패한다.
 *
 *   실행(이번 배정 실행 0 · 작성자가 실행하지 않았다 · 통과를 주장하지 않는다):
 *     cwd = <격리 사본>/functions        (../src/index.ts = 후보 적용본, ../src/consent_r4.ts 포함)
 *     "C:/Program Files/nodejs/node.exe" test/consent_r4b_callables.test.js
 *     둘 다 test/ 에 둔다: consent_r4b_callables.test.js · consent_r4b_fakestore.js
 *   입력: ../src/index.ts · ../src/consent_r4.ts · ../src/{commitment_dates,activation_generation,…}.ts
 *         (폐포가 실제로 가져오는 것만 읽는다) · node_modules/typescript. 네트워크·실제 Firestore 0.
 *   사용 모듈: assert · fs · path · crypto · typescript · ./consent_r4b_fakestore 만.
 *   출력: 첫 줄에 index.ts·consent_r4.ts sha256, 폐포 요약, 셀마다 `  ok   ID 이름` / `  FAIL ID 이름 — 이유`.
 *   성공 = 마지막 줄 '통과 N / 실패 0' · rc 0. 실패가 하나라도 있으면 목록을 찍고 process.exit(1).
 *   환경 변수: R4B_CLOSURE=names(검사기 대신 이름 기반 폐포) · R4B_VERBOSE=1(폐포 선언 이름 전부 출력).
 *
 *   [가정] — 첫 실행에서 깨질 수 있는 자리(아래 SEED 의 행 주석에 후보 index.ts 줄 번호를 단다)
 *     A1. 최상위 `const db = getFirestore();`(index.ts:202)를 그대로 평가하고 getFirestore 스텁이 가짜 db 를
 *         돌려준다. `initializeApp()` 같은 최상위 실행문은 선언이 아니므로 폐포에 넣지 않는다.
 *     A2. 폐포 계산은 TS 검사기를 noLib·noResolve 로 이 파일 하나에 만든다(3MB 바인딩 1회).
 *         검사기 생성이 실패하면 이름 기반으로 떨어지고 그 사실을 첫머리에 찍는다.
 *     A3. 함수 선언 먼저 · 그 밖은 원본 순서. 모듈 평가 시점 부수효과가 있는 최상위 const 가 끌려오면
 *         외부 스텁(관대 Proxy)이 받는다 — 닿은 기록은 CL-9 가 실패로 드러낸다.
 *     A4. 근로자 문서에 idCardObjectState:'PRESENT'(+버전)을 두어 예전 업로드 Storage 확인
 *         (srvProbeLegacyIdCardObject → admin.storage(), index.ts:2002-2011)을 타지 않는다.
 *     A5. 세무 수집 스위치 app_settings/tax_identity_collection 을 두지 않는다 → 꺼짐(index.ts:2865-2874).
 *     A6. 근태 기준은 지원서의 attendancePolicySnapshot + attendancePolicyAcknowledgement
 *         (actorRole business_admin, index.ts:41389-41406)로 통과 → 초대 수락이 새 snapshot 을 쓰지 않는다.
 *     A7. 신분증 자동 판정 MATCHED(현재 버전) → READY_AUTO(index.ts:2090). 사업장 검토 문서는 없다.
 *     A8. 가짜 트랜잭션은 경합·재시도를 흉내 내지 않는다(콜백 1회). 쓰기 뒤 tx.get · undefined 값 ·
 *         없는 문서 update · 있는 문서 create 는 실제 SDK 처럼 실패시킨다.
 *     A9. 초대 수락 뒤 관리자 알림은 await 되지 않는다(index.ts:48352 `.catch`) → 호출 뒤 setImmediate 로
 *         몇 번 비운 다음 본다(settle).
 *     A10. 알림은 커밋된 쓰기 중 경로 `users/{uid}/notifications/*` 로 센다 — 별도 트랜잭션 create
 *          (index.ts:52343-52346) · 호출자 트랜잭션 set(index.ts:52461-52464) 둘 다.
 *     A11. 시각: 인자 없는 new Date()·Date.now()(FakeDate)와 Timestamp.now() 를 같은 NOW 로 묶는다.
 *          로컬 모듈(consent_r4·commitment_dates 등)에도 같은 Date 를 주입한다.
 *     A12. 'At 형식 오류'는 문자열 값으로 만든다(toMillis 없음).
 *     A13. RA-8d SOURCE_GONE 은 트랜잭션 밖 사전 읽기 직후 훅으로 A 를 지워 재현한다(실제로는 다른 writer).
 *     A14. 계약서·근태 문서는 두지 않는다(계약 없음·근무 시작 전). 겹침 정리(IA-11)만 다른 공고의
 *          PENDING 한 건과 그 슬롯을 둔다.
 */
'use strict';
// [r5 · 판정 consent1121 §3] 외부 HTTP · 소켓 · DNS · fetch 진입점 차단 — 닿으면 그 자리에서 throw 하고 기록한다.
//   에뮬레이터 · DEV · 네트워크 0. 기록이 하나라도 있으면 끝에서 그 사실을 마지막 줄로 남기고 rc 1(성공 줄 '통과 N / 실패 0' 이 마지막 줄이 아니게 된다).
const R5_NET = [];
const R5_LOCAL_EXT_OK = new Set(['crypto']);
for (const [m, ks] of [['http', ['request', 'get']], ['https', ['request', 'get']], ['net', ['connect', 'createConnection']],
  ['tls', ['connect']], ['dns', ['lookup', 'resolve', 'resolve4', 'resolve6']]]) {
  const mod = require(m);
  for (const k of ks) {
    mod[k] = () => { R5_NET.push(`${m}.${k}`); throw new Error(`[r5 차단] ${m}.${k}`); };
  }
}
globalThis.fetch = () => { R5_NET.push('fetch'); throw new Error('[r5 차단] fetch'); };
process.on('exit', () => {
  if (R5_NET.length) {
    console.log('[r5 차단] 외부 진입 시도: ' + R5_NET.join(', '));
    process.exitCode = 1;
  }
});
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const ts = require('typescript');
const {createFakeFirestore} = require('./consent_r4d_fakestore');

const SRC_DIR = path.join(__dirname, '..', 'src');
const IDX = path.join(SRC_DIR, 'index.ts');
const CR4 = path.join(SRC_DIR, 'consent_r4.ts');
const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
console.log('index.ts sha256=' + sha(IDX));
console.log('consent_r4.ts sha256=' + sha(CR4));

// ── 시계·스텁 ─────────────────────────────────────────────────────────────
let NOW = 0;
const RealDate = Date;
class FakeDate extends RealDate {
  constructor(...a) {
    if (a.length === 0) super(NOW);
    else super(...a);
  }
  static now() { return NOW; }
}
class HttpsError extends Error {
  constructor(code, message, details) {
    super(message);
    this.code = code;
    this.details = details;
  }
}
const LOGS = [];
const QCON = {};
for (const k of ['log', 'info', 'warn', 'error', 'debug']) {
  QCON[k] = (...a) => LOGS.push(`[${k}] ` + a.map((x) =>
    (x instanceof Error ? `${x.name}: ${x.message}` : typeof x === 'string' ? x : safeJson(x))).join(' '));
}
function safeJson(x) {
  try { return JSON.stringify(x); } catch (e) { return String(x); }
}

const F = createFakeFirestore({now: () => NOW});
const {W, Ts} = F;

// ── 원문 폐포 추출 ────────────────────────────────────────────────────────
const SRC = fs.readFileSync(IDX, 'utf8');
const SF = ts.createSourceFile(IDX, SRC, ts.ScriptTarget.ES2022, true, ts.ScriptKind.TS);
const SK = ts.SyntaxKind;
// [r4c] 목적별 계좌 reader 도 원문 폐포로 실행한다(F-R4B-4 · 로그 대기 중 경계 · 무계좌).
const ROOTS = ['callableAcceptTOInvitation', 'callableAcceptConfirmedReassignment',
  'callableGetWorkerPayrollAccount'];

/** 최상위 값 선언: 이름 → {kind:'fn'|'val', stmts:[]} */
const TOP = new Map();
/** 가져온 지역 이름 → {module, kind:'named'|'ns'|'default', imported} */
const IMPORTS = new Map();
const modsOf = (st) => st.modifiers || [];
const hasMod = (st, kind) => modsOf(st).some((m) => m.kind === kind);
function boundNames(name, out) {
  if (ts.isIdentifier(name)) out.push(name.text);
  else if (ts.isObjectBindingPattern(name) || ts.isArrayBindingPattern(name)) {
    for (const el of name.elements) if (!ts.isOmittedExpression(el)) boundNames(el.name, out);
  }
  return out;
}
function addTop(n, st, kind) {
  if (!TOP.has(n)) TOP.set(n, {kind, stmts: []});
  const e = TOP.get(n);
  if (!e.stmts.includes(st)) e.stmts.push(st);
}
for (const st of SF.statements) {
  if (ts.isImportDeclaration(st)) {
    const mod = st.moduleSpecifier.text;
    const ic = st.importClause;
    if (!ic || ic.isTypeOnly) continue;
    if (ic.name) IMPORTS.set(ic.name.text, {module: mod, kind: 'default', imported: 'default'});
    const nb = ic.namedBindings;
    if (nb && ts.isNamespaceImport(nb)) {
      IMPORTS.set(nb.name.text, {module: mod, kind: 'ns', imported: null});
    } else if (nb && ts.isNamedImports(nb)) {
      for (const el of nb.elements) {
        if (el.isTypeOnly) continue;
        IMPORTS.set(el.name.text, {module: mod, kind: 'named', imported: (el.propertyName || el.name).text});
      }
    }
    continue;
  }
  if (hasMod(st, SK.DeclareKeyword)) continue;
  if (ts.isFunctionDeclaration(st)) {
    if (st.name && st.body) addTop(st.name.text, st, 'fn');
    continue;
  }
  if (ts.isVariableStatement(st)) {
    for (const d of st.declarationList.declarations) for (const n of boundNames(d.name, [])) addTop(n, st, 'val');
    continue;
  }
  if ((ts.isClassDeclaration(st) || ts.isEnumDeclaration(st) || ts.isModuleDeclaration(st)) &&
      st.name && ts.isIdentifier(st.name)) {
    addTop(st.name.text, st, 'val');
  }
}

// 검사기 — 이 파일 하나, lib·모듈 해석 없음.
const normF = (f) => path.resolve(String(f)).replace(/\\/g, '/').toLowerCase();
let CHECKER = null;
let RESOLVER = 'names';
if (process.env.R4B_CLOSURE !== 'names') {
  try {
    const want = normF(IDX);
    const host = {
      getSourceFile: (f) => (normF(f) === want ? SF : undefined),
      getDefaultLibFileName: () => 'lib.d.ts',
      writeFile: () => {},
      getCurrentDirectory: () => SRC_DIR,
      getDirectories: () => [],
      getCanonicalFileName: (f) => normF(f),
      useCaseSensitiveFileNames: () => false,
      getNewLine: () => '\n',
      fileExists: (f) => normF(f) === want,
      readFile: (f) => (normF(f) === want ? SRC : undefined),
      directoryExists: () => true,
    };
    const program = ts.createProgram({
      rootNames: [IDX],
      options: {noLib: true, noResolve: true, types: [], noEmit: true, skipLibCheck: true,
        target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS},
      host,
    });
    // 검사기가 **이 SF 객체**를 바인딩했는지 확인한다 — 다른 객체로 다시 읽었다면 이 트리의
    //   식별자는 묶이지 않으므로 이름 기반으로 떨어진다.
    const bound = program.getSourceFiles().some((f) => f === SF);
    if (bound) {
      CHECKER = program.getTypeChecker();
      RESOLVER = 'checker';
    } else {
      console.log('[폐포] 검사기가 다른 SourceFile 을 읽었다 → 이름 기반으로 계산');
    }
  } catch (e) {
    console.log('[폐포] 검사기 생성 실패 → 이름 기반으로 계산: ' + e.message);
  }
}
const BIND_KINDS = new Set([SK.VariableDeclaration, SK.VariableDeclarationList,
  SK.ObjectBindingPattern, SK.ArrayBindingPattern, SK.BindingElement]);
function topStmtOf(n) {
  while (n.parent && n.parent.kind !== SK.SourceFile) n = n.parent;
  return n;
}
function isTopLevelDecl(d) {
  if (!d || !d.parent) return false;
  if (d.kind === SK.ImportSpecifier || d.kind === SK.NamespaceImport ||
      d.kind === SK.ImportClause || d.kind === SK.ImportEqualsDeclaration) return true;
  const st = topStmtOf(d);
  if (d.kind === SK.FunctionDeclaration || d.kind === SK.ClassDeclaration ||
      d.kind === SK.EnumDeclaration || d.kind === SK.ModuleDeclaration) return d === st;
  if (d.kind === SK.VariableDeclaration || d.kind === SK.BindingElement) {
    if (!ts.isVariableStatement(st)) return false;
    for (let n = d; n !== st; n = n.parent) if (!BIND_KINDS.has(n.kind)) return false;
    return true;
  }
  return false;
}
/** 값으로 쓰인 식별자인가(선언 이름·속성 이름·레이블 제외). */
function isRefPosition(id) {
  const p = id.parent;
  if (!p) return false;
  if (ts.isShorthandPropertyAssignment(p)) return p.name === id || p.objectAssignmentInitializer === id;
  if (p.name === id) return false;
  if (p.propertyName === id) return false;
  if ((ts.isLabeledStatement(p) || ts.isBreakOrContinueStatement(p)) && p.label === id) return false;
  if (ts.isQualifiedName(p) || ts.isMetaProperty(p)) return false;
  return true;
}
const UNRESOLVED = new Set();
function resolveRef(id) {
  const name = id.text;
  if (!CHECKER) return TOP.has(name) || IMPORTS.has(name) ? name : null;
  let sym;
  try {
    sym = ts.isShorthandPropertyAssignment(id.parent) && id.parent.name === id ?
      CHECKER.getShorthandAssignmentValueSymbol(id.parent) : CHECKER.getSymbolAtLocation(id);
  } catch (e) {
    sym = undefined;
  }
  if (!sym || !sym.declarations || sym.declarations.length === 0) {
    if (TOP.has(name) || IMPORTS.has(name)) return name; // 묶지 못한 최상위 이름 — 과포함 쪽으로
    UNRESOLVED.add(name);
    return null;
  }
  return isTopLevelDecl(sym.declarations[0]) ? name : null;
}
function collectRefs(stmt, out) {
  const visit = (node) => {
    if (!node) return;
    if (ts.isInterfaceDeclaration(node) || ts.isTypeAliasDeclaration(node)) return;
    if (ts.isExpressionWithTypeArguments(node)) {
      const hc = node.parent;
      if (hc && ts.isHeritageClause(hc) && hc.token === SK.ExtendsKeyword &&
          hc.parent && ts.isClassLike(hc.parent)) visit(node.expression);
      return;
    }
    if (ts.isTypeNode(node)) return;
    if (ts.isIdentifier(node)) {
      if (isRefPosition(node)) {
        const r = resolveRef(node);
        if (r) out.add(r);
      }
      return;
    }
    ts.forEachChild(node, visit);
  };
  visit(stmt);
}
const NEED = new Set();
const USED_IMPORTS = new Set();
{
  const queue = [...ROOTS];
  while (queue.length) {
    const n = queue.shift();
    if (NEED.has(n) || USED_IMPORTS.has(n)) continue;
    if (IMPORTS.has(n)) { USED_IMPORTS.add(n); continue; }
    const e = TOP.get(n);
    assert.ok(e, `[폐포] 최상위 선언을 찾을 수 없다: ${n}`);
    NEED.add(n);
    for (const st of e.stmts) {
      const refs = new Set();
      collectRefs(st, refs);
      for (const r of refs) if (!NEED.has(r) && !USED_IMPORTS.has(r)) queue.push(r);
    }
  }
}
const lineOf = (st) => SF.getLineAndCharacterOfPosition(st.getStart(SF)).line + 1;
function declText(st) {
  const exp = modsOf(st).find((m) => m.kind === SK.ExportKeyword);
  assert.ok(!modsOf(st).some((m) => m.kind === SK.DefaultKeyword), 'export default 는 다루지 않는다');
  const start = exp ? exp.end : st.getStart(SF);
  return `/* index.ts:${lineOf(st)} */\n` + SRC.slice(start, st.end).replace(/^\s+/, '');
}
const FN_STMTS = [];
const VAL_STMTS = [];
for (const n of NEED) {
  const e = TOP.get(n);
  for (const st of e.stmts) {
    const bucket = e.kind === 'fn' ? FN_STMTS : VAL_STMTS;
    if (!bucket.includes(st)) bucket.push(st);
  }
}
FN_STMTS.sort((a, b) => a.pos - b.pos);
VAL_STMTS.sort((a, b) => a.pos - b.pos);

// 가져온 이름 주입
const onX = (a, b) => (typeof a === 'function' ? a : b);
const EXT = {
  'firebase-functions/v2/https': {onCall: onX, onRequest: onX, HttpsError},
  'firebase-functions/v2/scheduler': {onSchedule: onX},
  'firebase-functions/v2/firestore': {onDocumentCreated: onX, onDocumentUpdated: onX,
    onDocumentDeleted: onX, onDocumentWritten: onX},
  'firebase-admin/app': {initializeApp: () => ({})},
  'firebase-admin/firestore': {getFirestore: () => F.db, Timestamp: Ts, FieldValue: F.FieldValue,
    FieldPath: F.FieldPath, Firestore: class FakeFirestoreClass {}},
  'firebase-admin': {__ns: F.admin, default: F.admin},
  'crypto': {__ns: crypto, default: crypto},
};
const EXT_WARN = [];
const LOCAL = new Map();
function loadLocal(spec) {
  const file = path.join(SRC_DIR, spec.replace(/^\.\//, '') + '.ts');
  if (LOCAL.has(file)) return LOCAL.get(file).exports;
  assert.ok(fs.existsSync(file), `[폐포] 로컬 모듈 파일이 없다: ${file}`);
  const js = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
    compilerOptions: {target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS},
    fileName: file,
  }).outputText;
  const m = {exports: {}, sha: sha(file)};
  LOCAL.set(file, m);
  // [r5 · 판정 consent1121 §3 loader:335] 로컬 모듈 안의 바깥 require 는 순수 내장 허용 목록(crypto)만 실제 require — 그 밖은 차단(throw · R5_NET 기록).
  const req = (s) => (s.startsWith('.') ? loadLocal(s) : (R5_LOCAL_EXT_OK.has(s) ? require(s) :
    (() => { R5_NET.push('require ' + s); throw new Error('[r5 차단] 로컬 모듈의 바깥 require: ' + s); })()));
  // eslint-disable-next-line no-new-func
  new Function('exports', 'require', 'module', '__filename', '__dirname', 'Date', js)(
    m.exports, req, m, file, path.dirname(file), FakeDate);
  return m.exports;
}
function __imp(mod, kind, imported, local) {
  if (mod.startsWith('.')) {
    const ex = loadLocal(mod);
    if (kind === 'ns') return ex;
    const key = kind === 'default' ? 'default' : imported;
    assert.ok(Object.prototype.hasOwnProperty.call(ex, key),
      `[폐포] 로컬 모듈 ${mod} 에 export '${key}' 가 없다(지역 이름 ${local})`);
    return ex[key];
  }
  const m = EXT[mod];
  if (kind === 'ns' || kind === 'default') {
    const v = m && (kind === 'ns' ? m.__ns : (m.default || m.__ns));
    if (v) return v;
  } else if (m && Object.prototype.hasOwnProperty.call(m, imported)) {
    return m[imported];
  }
  EXT_WARN.push(`${mod}#${imported || kind} (지역 ${local})`);
  return F.lenient(`${mod}#${imported || kind}`);
}

const WANT_CONSTS = ['DOCUMENT_ACCESS_CONSENT_V4', 'DOCUMENT_ACCESS_CONSENT_INVITE_V2',
  'DOCUMENT_ACCESS_CONSENT_V3', 'DOCUMENT_ACCESS_CONSENT_INVITE_V1',
  'SUPPORTED_DOCUMENT_ACCESS_CONSENT_VERSIONS', 'RETIRED_DOCUMENT_ACCESS_CONSENT_VERSIONS',
  'CR_TYPE', 'CR_PROPOSAL_COL', 'CR_LOCK_COL', 'ACCOUNT_DELETION_TOMBSTONE_COL'];
const EXPORT_NAMES = [...ROOTS, ...WANT_CONSTS.filter((n) => NEED.has(n))];
const HARNESS = [
  '// [CONSENT-R4b] 자동 생성 — 후보 index.ts 원문 폐포(수정 0).',
  ...[...USED_IMPORTS].sort().map((local) => {
    const im = IMPORTS.get(local);
    return `const ${local} = __imp(${JSON.stringify(im.module)}, ${JSON.stringify(im.kind)}, ` +
      `${JSON.stringify(im.imported)}, ${JSON.stringify(local)});`;
  }),
  ...FN_STMTS.map(declText),
  ...VAL_STMTS.map(declText),
  `module.exports = {${EXPORT_NAMES.join(', ')}};`,
].join('\n\n');
const TR = ts.transpileModule(HARNESS, {
  compilerOptions: {target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS},
  fileName: 'consent_r4b_harness.ts',
  reportDiagnostics: true,
});
// 1208 = '전역 스크립트라 isolatedModules 로 못 엮는다' — 하네스는 일부러 스크립트다(무해).
const TR_ERRORS = (TR.diagnostics || []).filter((d) =>
  d.category === ts.DiagnosticCategory.Error && d.code !== 1208);
const HMOD = {exports: {}};
try {
  // eslint-disable-next-line no-new-func
  new Function('module', 'exports', '__imp', 'Date', 'console', TR.outputText)(
    HMOD, HMOD.exports, __imp, FakeDate, QCON);
} catch (e) {
  // 모듈 평가 단계 실패(문법·TDZ·스텁 누락) — 셀을 돌릴 수 없다. 원인을 찍고 끝낸다.
  console.log('[폐포] 하네스 평가 실패: ' + (e && e.stack ? e.stack.split('\n').slice(0, 6).join(' | ') : e));
  for (const l of LOGS.slice(-6)) console.log('       ' + l.slice(0, 300));
  console.log('\n통과 0 / 실패 1');
  process.exit(1);
}
const R = HMOD.exports;
// [판정281] 공통 진입 판정(탈퇴 fence) 읽기를 검증 뒤 분리 — 업무 읽기 계약은 그대로(deletion_fence_observer.js).
const FENCE_READS = require('./deletion_fence_observer').separateFenceReads(R, ROOTS, F.W);

const GLOBAL_OK = new Set(['undefined', 'arguments', 'NaN', 'Infinity', 'Date', 'console',
  'module', 'exports', '__imp']);
const UNRESOLVED_NON_GLOBAL = [...UNRESOLVED].filter((n) => !GLOBAL_OK.has(n) && !(n in globalThis));
console.log(`[폐포] 방식=${RESOLVER} · 선언 ${NEED.size}개(함수 ${FN_STMTS.length} · 그 밖 ${VAL_STMTS.length}) · ` +
  `가져온 이름 ${USED_IMPORTS.size}개: ${[...USED_IMPORTS].sort().join(', ')}`);
for (const [file, m] of LOCAL) console.log(`[폐포] 로컬 모듈 ${path.basename(file)} sha256=${m.sha}`);
if (TR_ERRORS.length) {
  console.log(`[폐포] 변환 진단 ${TR_ERRORS.length}건(첫 3): ` + TR_ERRORS.slice(0, 3)
    .map((d) => ts.flattenDiagnosticMessageText(d.messageText, ' ')).join(' | '));
}
if (EXT_WARN.length) console.log('[폐포] 스텁 없는 외부 이름: ' + EXT_WARN.join(', '));
if (UNRESOLVED_NON_GLOBAL.length) console.log('[폐포] 묶지 못한 비전역 이름: ' + UNRESOLVED_NON_GLOBAL.join(', '));
if (process.env.R4B_VERBOSE) console.log('[폐포] 선언: ' + [...NEED].sort().join(', '));

// ── 고정 장면 ─────────────────────────────────────────────────────────────
const MIN = 60e3;
const HOUR = 3600e3;
const DAY = 24 * HOUR;
const KST = 9 * HOUR;
const kst = (y, mo, d, h = 0, mi = 0) => RealDate.UTC(y, mo - 1, d, h, mi) - KST;
const WORK_DAY = kst(2026, 11, 20);       // 단기 근무일 KST 0시
const T0 = kst(2026, 11, 10, 9, 0);       // 최초 동의(지원 · 초대 사전 동의)
const T1 = kst(2026, 11, 12, 15, 0);      // 수락 시각
const V4 = '2026-11-18-v4';
const INV2 = '2026-11-18-invite-v2';
const V3 = '2026-09-18-v3';
const INV1 = '2026-10-15-invite-v1';
const CR_KIND = 'CONFIRMED_WORK_REASSIGNMENT';
const at = (ms) => new Ts(ms);
const ms = (v) => (v && typeof v.toMillis === 'function' ? v.toMillis() : v);
const DEL = Symbol('삭제');
function over(base, o) {
  const out = Object.assign({}, base);
  for (const k of Object.keys(o || {})) {
    if (o[k] === DEL) delete out[k];
    else out[k] = o[k];
  }
  return out;
}

const INV_ID = 'inv1';
const A_ID = 't1_s1_wd-1_w1';
const B_ID = 't1_s1_wd-2_w1';
const C_ID = 't1_s1_wd-3_w1';
const P1 = `${A_ID}__p1`;
const P2 = `${B_ID}__p2`;
const appPath = (id) => `applications/${id}`;
const propPath = (id) => `confirmedReassignmentProposals/${id}`;
const lockPath = (id) => `confirmedReassignmentLocks/${id}`;
const INV_PATH = appPath(INV_ID);
const SLOT_PATH = 'tos/t1/slots/s1';
const CONSENT_KEYS = ['documentAccessConsentGiven', 'documentAccessConsentVersion',
  'documentAccessConsentAt', 'idCardConsentGiven', 'idCardConsentAt',
  'documentAccessConsentSource', 'documentAccessConsentInheritedFrom'];

const POLICY7 = {earlyWindow: 30, earlyArrivalUnit: 30, lateGrace: 5, lateUnit: 30,
  lateWindow: 30, overtimeUnit: 10, earlyLeaveUnit: 30};
const WT = {'wd-1': '피킹', 'wd-2': '포장', 'wd-3': '검수'};
const WDS = () => Object.keys(WT).map((id) => ({wdId: id, workType: WT[id], startTime: '09:00',
  endTime: '18:00', requiredCount: 3, wage: 12000, wageType: 'hourly', breakMinutes: 60}));
/** workDetailCounts — 기본 0/0, 덮을 것만 [confirmed, pending]. */
function wdc(o = {}) {
  const out = {};
  for (const id of Object.keys(WT)) {
    const [c, p] = o[id] || [0, 0];
    out[id] = {confirmedCount: c, pendingCount: p};
  }
  return out;
}

// ── SEED — 행 주석은 그 필드를 요구하는 후보 index.ts 줄 ────────────────────
const SEED = {
  worker: (o) => over({
    name: '김근로',
    accountStatus: 'active',                       // 47855-47858 · 49420 (deleting·비활성 아님)
    isBlacklisted: false,                          // 47879 · 49423
    passVerifiedAt: at(T0 - 30 * DAY),             // 47889 · 49432 (내국인 — 4374-4382 외국인 아님)
    idCardImagePath: 'users/w1/idCard_1700000000000.jpg', // 47892 · 1465
    isIdVerified: true,                            // 47896(슬롯 초대) · 49435
    bankName: '국민은행', accountNumber: '000000-00-000000', accountHolder: '김근로', // 1808 (47903)
    bankbookImagePath: 'users/w1/bankbook_1700000000000.jpg', // 1811
    idDocumentVersion: 2,                          // 1477 · 2048
    idCardMatchStatus: 'MATCHED',                  // 1468 → 2090 READY_AUTO
    idCardMatchDocumentVersion: 2,                 // 1476-1478 (낡지 않음)
    idCardMatchEvidenceSource: 'CLIENT_OCR',       // 2164-2165
    idCardObjectState: 'PRESENT',                  // 1978 (예전 문서 아님 → Storage 확인 0) [가정 A4]
    idCardObjectStateVersion: 2,                   // 2076-2079
  }, o),
  owner: () => ({role: 'BUSINESS_ADMIN', name: '사업주', sealBase64: 'U0VBTA=='}), // 28615-28619
  business: (o) => over({
    name: '테스트사업장',
    isApproved: true,                              // 28575 (deactivatedAt 없음 — 1042 · 28575)
    ownerId: 'owner1',                             // 28615
    adminIds: ['admin1'],
    attendanceRules: Object.assign({policySource: 'ALFIT_DEFAULT'}, POLICY7),
    attendancePolicyConfirmation: Object.assign({confirmedAt: at(T0 - 10 * DAY),
      confirmedBy: 'admin1', actorRole: 'business_admin'}, POLICY7), // 41408-41412(보조 경로)
  }, o),
  template: () => ({templateType: 'daily', name: '일용 기본'}),        // 28582-28588
  to: (o) => over({
    businessId: 'b1', title: '물류 센터 단기',
    status: 'ACTIVE',                              // 48048-48067 · 49476-49480
    totalRequired: 9, totalConfirmed: 0, totalPending: 0,
  }, o),
  slot: (o) => over({
    date: at(WORK_DAY),                            // 34038-34043 (canonical 근무일)
    status: 'open',                                // 3347 · 49485
    workDetails: WDS(),                            // 34044-34068 · 48082 · 49488-49494
    confirmedCount: 0, pendingCount: 0,            // 48101-48104
    workDetailCounts: wdc(),                       // 18228-18248 (없으면 fail-closed throw)
  }, o),
  policySnap: () => Object.assign({policySource: 'ALFIT_DEFAULT', capturedAt: at(T0 - 5 * DAY)}, POLICY7),
  policyAck: () => Object.assign({acknowledgedAt: at(T0 - 5 * DAY), acknowledgedBy: 'admin1',
    actorRole: 'business_admin'}, POLICY7),       // 41339-41356 (actorRole · 7개 값 일치)
  invite: (o) => over({
    uid: 'w1',                                     // 47595
    businessId: 'b1', businessName: '테스트사업장', toId: 't1', toTitle: '물류 센터 단기',
    slotId: 's1', wdId: 'wd-1', workDetailId: 'wd-1', selectedWorkType: '피킹',
    status: 'INVITED',                             // 47600-47613 · 47749-47751
    type: 'short', startTime: '09:00', endTime: '18:00',
    workDate: at(WORK_DAY),
    inviteExpiresAt: at(WORK_DAY + 9 * HOUR),      // 47616-47617 · 47756-47760 (> 수락 시각)
    invitedBy: 'admin1', invitedAt: at(T0 - DAY),  // 48333 · 48351 (관리자 알림)
    applicantName: '김근로',                         // 48335 → 23844 (users 재조회 0)
    attendancePolicySnapshot: SEED.policySnap(),   // 41393 · 48275 (이미 있음 → snapshot 쓰기 0) [가정 A6]
    attendancePolicyAcknowledgement: SEED.policyAck(), // 41402-41406
    activationGeneration: 0,
    statusHistory: [{status: 'INVITED', at: at(T0 - DAY), by: 'admin1', action: 'INVITED'}],
  }, o),
  confirmedA: (o) => over({
    uid: 'w1',                                     // 4483 cr4LineageBlock UID
    businessId: 'b1', businessName: '테스트사업장', toId: 't1', toTitle: '물류 센터 단기',
    slotId: 's1', wdId: 'wd-1', workDetailId: 'wd-1', selectedWorkType: '피킹',
    status: 'CONFIRMED',                           // 48727 srvConfirmedReassignSourceBlock
    type: 'short',                                 // 48733-48737 (장기 아님)
    startTime: '09:00', endTime: '18:00',
    workDate: at(WORK_DAY),                        // 48738 · consent_r4.ts:489-491
    wage: 12000, wageType: 'hourly', breakMinutes: 60,
    applicantName: '김근로',                         // 49595 (트랜잭션 쓰기 뒤 users 재조회 0)
    appliedAt: at(T0), confirmedAt: at(T0 + HOUR),
    documentAccessConsentGiven: true,              // consent_r4.ts:419
    documentAccessConsentVersion: V4,              // consent_r4.ts:420-424 (저장 이력 읽기 집합)
    documentAccessConsentAt: at(T0),               // consent_r4.ts:425-429
    idCardConsentGiven: true, idCardConsentAt: at(T0), // consent_r4.ts:463-466
    documentAccessConsentSource: 'APPLY',          // consent_r4.ts:430-442 (승계 아님 · parent 없음)
    attendancePolicySnapshot: SEED.policySnap(),
    attendancePolicyAcknowledgement: SEED.policyAck(),
    activationGeneration: 0,
    statusHistory: [{status: 'CONFIRMED', at: at(T0 + HOUR), by: 'admin1', action: 'CONFIRMED'}],
  }, o),
  proposal: (srcId, srcWdId, tgtWdId, o) => over({
    type: CR_KIND,                                 // 49279
    status: 'PROPOSED',                            // 49282-49293 · 49357
    uid: 'w1',                                     // 49276 · consent_r4.ts:483
    businessId: 'b1', businessName: '테스트사업장', toTitle: '물류 센터 단기',
    sourceApplicationId: srcId,                    // 49295 · consent_r4.ts:482
    sourceWdId: srcWdId,                           // consent_r4.ts:487-488
    sourceWorkType: WT[srcWdId],
    sourcePromiseSnapshot: {applicationId: srcId, wdId: srcWdId, workType: WT[srcWdId],
      startTime: '09:00', endTime: '18:00', wage: 12000, wageType: 'hourly', breakMinutes: 60,
      baseHourlyWage: null, baseHourlyWageMode: 'AUTO'},
    targetToId: 't1', targetSlotId: 's1', targetWdId: tgtWdId, // 49296-49298 · consent_r4.ts:485-486
    targetApplicationId: `t1_s1_${tgtWdId}_w1`,    // 48967 규칙과 같은 id
    targetPromiseSnapshot: {wdId: tgtWdId, workType: WT[tgtWdId], startTime: '09:00',
      endTime: '18:00', wage: 12000, wageType: 'hourly', breakMinutes: 60}, // 49517-49518 · 49602-49616
    compensationOption: 'TARGET_BASE',
    baseCompensationSnapshotAtProposal: {breakMinutes: 60, wage: 12000, wageType: 'hourly'},
    compensationSource: 'CONFIRMED_REASSIGNMENT_TARGET_BASE',
    workDate: at(WORK_DAY),                        // consent_r4.ts:489-491
    createdBy: 'admin1',                           // 49640 · 49697 · 49742 (알림 수신자)
    createdAt: at(NOW - HOUR),
    expiresAt: at(NOW + 23 * HOUR),                // 49361-49369 (> 지금 · ≤ 근무 시작)
    decidedAt: null, resultApplicationId: null,
    history: [{status: 'PROPOSED', at: at(NOW - HOUR), by: 'admin1', action: 'PROPOSED'}],
  }, o),
  lock: (srcId, pid) => ({activeProposalId: pid, uid: 'w1', businessId: 'b1',
    sourceApplicationId: srcId, updatedAt: at(NOW - HOUR)}), // 49215
};

function seedBase() {
  F.put('users/w1', SEED.worker());
  F.put('users/owner1', SEED.owner());
  F.put('users/admin1', {role: 'BUSINESS_ADMIN', name: '관리자'});
  F.put('businesses/b1', SEED.business());                     // 1154-1157 · 47818-47819
  F.put('businesses/b1/contract_templates/tpl1', SEED.template());
}
/** 초대 수락 장면 — INVITED 1건이 대기 1을 잡고 있다(48296-48319 대칭 감소). */
function seedInvite(appOver, opts = {}) {
  F.reset();
  NOW = opts.now !== undefined ? opts.now : T1;
  seedBase();
  F.put('tos/t1', SEED.to({totalPending: 1}));
  F.put(SLOT_PATH, SEED.slot({pendingCount: 1, workDetailCounts: wdc({'wd-1': [0, 1]})}));
  F.put(INV_PATH, SEED.invite(appOver));
  F.clearLog();
}
/** 재배치 수락 장면 — A(wd-1) CONFIRMED · 제안 P1(→ wd-2) PROPOSED · lock. */
function seedReassign(o = {}) {
  F.reset();
  NOW = o.now !== undefined ? o.now : T1;
  seedBase();
  F.put('tos/t1', SEED.to({totalConfirmed: 1}));
  F.put(SLOT_PATH, SEED.slot(Object.assign({confirmedCount: 1,
    workDetailCounts: wdc({'wd-1': [1, 0]})}, o.slot || {})));
  F.put(appPath(A_ID), SEED.confirmedA(o.a));
  F.put(propPath(P1), SEED.proposal(A_ID, 'wd-1', 'wd-2', o.p));
  F.put(lockPath(A_ID), SEED.lock(A_ID, P1));
  F.clearLog();
}

// ── 호출·계측 도우미 ──────────────────────────────────────────────────────
const callInvite = (data, uid = 'w1') => R.callableAcceptTOInvitation({auth: {uid}, data});
const callReassign = (data, uid = 'w1') => R.callableAcceptConfirmedReassignment({auth: {uid}, data});
/** version 에 DEL 을 주면 판본 키 자체가 없다. */
const INV_REQ = (version, o = {}) => over(over({applicationId: INV_ID, documentAccessConsentGiven: true},
  {documentAccessConsentVersion: version}), o);
const INHERIT = (pid = P1, o = {}) => over({proposalId: pid, consentMode: 'INHERIT'}, o);
const EXPLICIT = (pid = P1, o = {}) => over({proposalId: pid, consentMode: 'EXPLICIT',
  documentAccessConsentGiven: true, documentAccessConsentVersion: V4, consentShown: true}, o);

async function settle() {
  for (let i = 0; i < 10; i++) await new Promise((r) => setImmediate(r));
}
async function rejectsWith(p, code, detailsCode) {
  let err = null;
  try {
    await p;
  } catch (e) {
    err = e;
  }
  await settle();
  assert.ok(err, `거절되어야 하는데 성공했다(기대 ${code}/${detailsCode})`);
  assert.ok(err instanceof HttpsError,
    `HttpsError 가 아니다: ${err && err.stack ? err.stack.split('\n').slice(0, 4).join(' | ') : err}`);
  assert.strictEqual(err.code, code, `code ${err.code} ≠ ${code} (${err.message})`);
  if (detailsCode !== undefined) {
    assert.strictEqual(err.details && err.details.code, detailsCode,
      `details ${safeJson(err.details)} ≠ ${detailsCode} (${err.message})`);
  }
  return err;
}
/** 커밋된 쓰기 전부(트랜잭션 + 트랜잭션 밖 성공분). */
const committed = () => [
  ...W.commits.flatMap((c) => c.writes.map((w) => Object.assign({via: 'tx' + c.tx}, w))),
  ...W.direct.filter((d) => d.ok).map((d) => Object.assign({via: d.batch ? 'batch' : 'direct'}, d)),
];
const NOTIF_RE = /^users\/[^/]+\/notifications\/[^/]+$|^notifications\/[^/]+$/;
const notifs = () => committed().filter((w) => NOTIF_RE.test(w.path));
const commitsWith = (p) => W.commits.filter((c) => c.writes.some((w) => w.path === p));
const writeIn = (c, p, op) => c.writes.find((w) => w.path === p && (!op || w.op === op));
const ops = (ws) => ws.map((w) => `${w.op} ${w.path}`);
function assertNoWrites(label) {
  assert.strictEqual(W.attempts.length, 0,
    `${label}: 트랜잭션 쓰기 시도 ${W.attempts.length}건 — ${ops(W.attempts).join(', ')}`);
  assert.strictEqual(committed().length, 0, `${label}: 커밋된 쓰기 — ${ops(committed()).join(', ')}`);
  assert.strictEqual(W.direct.length, 0, `${label}: 트랜잭션 밖 쓰기 — ${ops(W.direct).join(', ')}`);
  assert.strictEqual(notifs().length, 0, `${label}: 알림이 남았다`);
}
const lastHistory = (doc, action) => (doc.statusHistory || []).filter((h) => h.action === action).pop();
const prevOf = (h) => {
  const o = {};
  for (const k of Object.keys(h).sort()) if (k.startsWith('prevConsent')) o[k] = h[k];
  return o;
};

let pass = 0;
const fails = [];
async function cell(id, name, fn) {
  LOGS.length = 0;
  try {
    await fn();
    pass++;
    console.log(`  ok   ${id} ${name}`);
  } catch (e) {
    const msg = String(e && e.message).split('\n')[0];
    fails.push(`${id} ${name}: ${msg}`);
    console.log(`  FAIL ${id} ${name} — ${msg}`);
    if (e && !(e instanceof assert.AssertionError) && e.stack) {
      console.log('       ' + e.stack.split('\n').slice(1, 4).map((s) => s.trim()).join(' | '));
    }
    for (const l of LOGS.slice(-6)) console.log('       ' + l.slice(0, 300));
  }
}

(async () => {
  console.log('\n[CL] 폐포 · 판본 상수');
  await cell('CL-1', '폐포에 동의·좌석·재배치 핵심 선언과 consent_r4 가져온 이름이 있다', () => {
    for (const n of ['srvResolveCommitmentConsentVersion', 'srvConsentVersionReject',
      'resolveDocumentAccessConsentVersion', 'srvInviteAcceptConsentPlan',
      'srvConsentValidSameGeneration', 'srvConsentAtValidMs', 'srvPrevConsentEvidence',
      'srvCollectSeatCommitOverlap', 'srvApplySeatCommitOverlap', 'srvAssertBizOpenInTx',
      'srvCloseCrProposal', 'srvWriteCrNotification', 'srvPersistNotificationWithId',
      'srvResolveMatchingReadiness', 'srvBuildMatchingProvenance', 'getWorkDetailCount', 'db']) {
      assert.ok(NEED.has(n), `폐포에 ${n} 없음`);
    }
    // [판정281] firebase onCall 은 fbOnCall 로 가져오고, 같은 이름 onCall 은 탈퇴 fence 래퍼다 — 둘 다 폐포에 있어야 한다.
    for (const n of ['onCall', 'srvAssertCallerNotInDeletion']) assert.ok(NEED.has(n), `폐포에 ${n} 없음`);
    for (const n of ['cr4ConsentInheritance', 'cr4LineageBlock', 'fbOnCall', 'HttpsError']) {
      assert.ok(USED_IMPORTS.has(n), `가져온 이름에 ${n} 없음`);
    }
    assert.strictEqual(typeof R.callableAcceptTOInvitation, 'function');
    assert.strictEqual(typeof R.callableAcceptConfirmedReassignment, 'function');
    assert.deepStrictEqual(UNRESOLVED_NON_GLOBAL, [], '묶지 못한 비전역 이름');
  });
  await cell('CL-2', '판본 상수가 기대값과 같다(v4 · invite-v2 · 저장 이력 읽기 = 새 세대 둘)', () => {
    assert.strictEqual(R.DOCUMENT_ACCESS_CONSENT_V4, V4);
    assert.strictEqual(R.DOCUMENT_ACCESS_CONSENT_INVITE_V2, INV2);
    assert.deepStrictEqual([...R.SUPPORTED_DOCUMENT_ACCESS_CONSENT_VERSIONS].sort(), [INV2, V4].sort());
    assert.ok(R.RETIRED_DOCUMENT_ACCESS_CONSENT_VERSIONS.includes(V3));
    assert.ok(R.RETIRED_DOCUMENT_ACCESS_CONSENT_VERSIONS.includes(INV1));
    assert.strictEqual(R.CR_TYPE, CR_KIND);
  });

  // ════════════════════════════════════════════════════════════════════════
  console.log('\n[IA] 초대 수락 — callableAcceptTOInvitation');
  await cell('IA-1', '저장된 같은 세대 유효 동의(invite-v2 · At t0) → CONFIRMED · Given/Version/At 그대로 · 수락 사건은 confirmedAt·이력에만', async () => {
    seedInvite({documentAccessConsentGiven: true, documentAccessConsentVersion: INV2,
      documentAccessConsentAt: at(T0), idCardConsentGiven: true, idCardConsentAt: at(T0),
      documentAccessConsentSource: 'CONSENT_ONLY'});
    const out = await callInvite(INV_REQ(INV2));
    await settle();
    assert.deepStrictEqual(out, {success: true});
    const a = F.get(INV_PATH);
    assert.strictEqual(a.status, 'CONFIRMED');
    assert.strictEqual(ms(a.confirmedAt), T1, 'confirmedAt = 수락 시각');
    assert.strictEqual(a.documentAccessConsentGiven, true);
    assert.strictEqual(a.documentAccessConsentVersion, INV2);
    assert.strictEqual(ms(a.documentAccessConsentAt), T0, '최초 동의 시각 보존');
    assert.strictEqual(ms(a.idCardConsentAt), T0);
    assert.strictEqual(a.documentAccessConsentSource, 'CONSENT_ONLY');
    const h = lastHistory(a, 'INVITE_ACCEPTED');
    assert.ok(h, '수락 이력 줄이 없다');
    assert.strictEqual(h.consentPreserved, true);
    assert.strictEqual(h.consentShownVersion, INV2);
    assert.strictEqual(h.consentPlanReason, 'SAME_GENERATION_VALID');
    assert.strictEqual(ms(h.at), T1);
    assert.deepStrictEqual(prevOf(h), {}, '보존인데 prev* 증거가 있다');
    const cs = commitsWith(INV_PATH);
    assert.strictEqual(cs.length, 1, '지원서를 쓴 커밋이 하나가 아니다');
    const patch = writeIn(cs[0], INV_PATH, 'update').data;
    for (const k of CONSENT_KEYS) assert.ok(!(k in patch), `보존인데 커밋 패치에 ${k}`);
  });

  await cell('IA-2', '저장 v4 유효 → v4/t0 보존 · 이번 화면 invite-v2 는 consentShownVersion 으로만', async () => {
    seedInvite({documentAccessConsentGiven: true, documentAccessConsentVersion: V4,
      documentAccessConsentAt: at(T0), idCardConsentGiven: true, idCardConsentAt: at(T0),
      documentAccessConsentSource: 'CONSENT_ONLY'});
    await callInvite(INV_REQ(INV2));
    await settle();
    const a = F.get(INV_PATH);
    assert.strictEqual(a.status, 'CONFIRMED');
    assert.strictEqual(a.documentAccessConsentVersion, V4, 'v4 가 invite-v2 로 바뀌었다');
    assert.strictEqual(ms(a.documentAccessConsentAt), T0);
    const h = lastHistory(a, 'INVITE_ACCEPTED');
    assert.strictEqual(h.consentPreserved, true);
    assert.strictEqual(h.consentShownVersion, INV2);
    const patch = writeIn(commitsWith(INV_PATH)[0], INV_PATH, 'update').data;
    for (const k of CONSENT_KEYS) assert.ok(!(k in patch), `보존인데 커밋 패치에 ${k}`);
  });

  await cell('IA-3', '저장 동의 없음 → 새 동의(Given true · At = confirmedAt · invite-v2 · INVITE_ACCEPT · idCard 필드)', async () => {
    seedInvite({});
    await callInvite(INV_REQ(INV2));
    await settle();
    const a = F.get(INV_PATH);
    assert.strictEqual(a.status, 'CONFIRMED');
    assert.strictEqual(a.documentAccessConsentGiven, true);
    assert.strictEqual(a.documentAccessConsentVersion, INV2);
    assert.strictEqual(ms(a.documentAccessConsentAt), T1);
    assert.strictEqual(ms(a.documentAccessConsentAt), ms(a.confirmedAt));
    assert.strictEqual(a.documentAccessConsentSource, 'INVITE_ACCEPT');
    assert.strictEqual(a.idCardConsentGiven, true);
    assert.strictEqual(ms(a.idCardConsentAt), T1);
    assert.ok(!('documentAccessConsentInheritedFrom' in a));
    const h = lastHistory(a, 'INVITE_ACCEPTED');
    assert.strictEqual(h.consentPreserved, false);
    assert.strictEqual(h.consentPlanReason, 'NONE');
    assert.strictEqual(h.consentShownVersion, INV2);
    assert.deepStrictEqual(prevOf(h), {});
    const patch = writeIn(commitsWith(INV_PATH)[0], INV_PATH, 'update').data;
    assert.ok(!('documentAccessConsentInheritedFrom' in patch), '지울 parent 가 없는데 delete 를 썼다');
  });

  const IA_OVERWRITE = [
    ['IA-4', 'At 없음',
      {documentAccessConsentGiven: true, documentAccessConsentVersion: INV2,
        documentAccessConsentSource: 'CONSENT_ONLY'},
      'AT_MISSING', {prevConsentGiven: true, prevConsentSource: 'CONSENT_ONLY', prevConsentVersion: INV2}],
    ['IA-5', 'At 형식 오류(문자열)',
      {documentAccessConsentGiven: true, documentAccessConsentVersion: INV2,
        documentAccessConsentAt: '2026-11-10T09:00:00+09:00', documentAccessConsentSource: 'CONSENT_ONLY'},
      'AT_MALFORMED', {prevConsentAtMalformed: true, prevConsentGiven: true,
        prevConsentSource: 'CONSENT_ONLY', prevConsentVersion: INV2}],
    ['IA-6', 'At 미래(수락 시각 + 1시간)',
      {documentAccessConsentGiven: true, documentAccessConsentVersion: INV2,
        documentAccessConsentAt: at(T1 + HOUR), documentAccessConsentSource: 'CONSENT_ONLY'},
      'AT_FUTURE', {prevConsentAtMs: T1 + HOUR, prevConsentGiven: true,
        prevConsentSource: 'CONSENT_ONLY', prevConsentVersion: INV2}],
    ['IA-7', '은퇴 판본 v3',
      {documentAccessConsentGiven: true, documentAccessConsentVersion: V3,
        documentAccessConsentAt: at(T0), documentAccessConsentSource: 'APPLY'},
      'VERSION_OTHER_GENERATION', {prevConsentAtMs: T0, prevConsentGiven: true,
        prevConsentSource: 'APPLY', prevConsentVersion: V3}],
    ['IA-7b', '은퇴 판본 + 낡은 승계 parent(documentAccessConsentInheritedFrom)',
      {documentAccessConsentGiven: true, documentAccessConsentVersion: V3,
        documentAccessConsentAt: at(T0), documentAccessConsentSource: 'REASSIGN_INHERITED',
        documentAccessConsentInheritedFrom: 'a-old'},
      'VERSION_OTHER_GENERATION', {prevConsentAtMs: T0, prevConsentGiven: true,
        prevConsentInheritedFrom: 'a-old', prevConsentSource: 'REASSIGN_INHERITED',
        prevConsentVersion: V3}],
  ];
  for (const [id, label, stored, reason, prev] of IA_OVERWRITE) {
    await cell(id, `저장 동의 ${label} → 새 동의 기록 + 이력 prev* 증거`, async () => {
      seedInvite(stored);
      await callInvite(INV_REQ(INV2));
      await settle();
      const a = F.get(INV_PATH);
      assert.strictEqual(a.status, 'CONFIRMED');
      assert.strictEqual(a.documentAccessConsentGiven, true);
      assert.strictEqual(a.documentAccessConsentVersion, INV2);
      assert.strictEqual(ms(a.documentAccessConsentAt), T1, 'At = 이번 수락 시각');
      assert.strictEqual(a.documentAccessConsentSource, 'INVITE_ACCEPT');
      assert.strictEqual(a.idCardConsentGiven, true);
      assert.strictEqual(ms(a.idCardConsentAt), T1);
      const h = lastHistory(a, 'INVITE_ACCEPTED');
      assert.strictEqual(h.consentPreserved, false);
      assert.strictEqual(h.consentPlanReason, reason);
      assert.strictEqual(h.consentShownVersion, INV2);
      assert.deepStrictEqual(F.canon(prevOf(h)), F.canon(prev));
      const patch = writeIn(commitsWith(INV_PATH)[0], INV_PATH, 'update').data;
      assert.ok('documentAccessConsentAt' in patch);
      if ('documentAccessConsentInheritedFrom' in stored) {
        assert.ok(F.isFV(patch.documentAccessConsentInheritedFrom, 'delete'),
          '낡은 parent 를 FieldValue.delete() 로 지우지 않았다');
        assert.ok(!('documentAccessConsentInheritedFrom' in a), '커밋 뒤에도 parent 가 남았다');
      } else {
        assert.ok(!('documentAccessConsentInheritedFrom' in patch));
      }
    });
  }

  await cell('IA-8', 'Given false · 없음 · 문자열 "true" → invalid-argument CONSENT_NOT_GIVEN · 읽기 0 · 쓰기 0', async () => {
    const cases = [
      ['false', INV_REQ(INV2, {documentAccessConsentGiven: false})],
      ['없음', INV_REQ(INV2, {documentAccessConsentGiven: DEL})],
      ['문자열', INV_REQ(INV2, {documentAccessConsentGiven: 'true'})],
    ];
    for (const [label, data] of cases) {
      seedInvite({});
      const before = F.dump();
      await rejectsWith(callInvite(data), 'invalid-argument', 'CONSENT_NOT_GIVEN');
      assert.strictEqual(W.reads.length, 0, `${label}: 읽기 ${W.reads.length}건(지원서 포함)`);
      assertNoWrites(label);
      assert.deepStrictEqual(F.dump(), before, `${label}: 저장소가 바뀌었다`);
    }
  });

  await cell('IA-9', '은퇴 토큰(invite-v1·v3) · 판본 없음 · v4(일반 판본) → 정확한 code · 쓰기 0', async () => {
    const cases = [
      [INV1, 'invalid-argument', 'CONSENT_VERSION_RETIRED'],
      [V3, 'invalid-argument', 'CONSENT_VERSION_RETIRED'],
      [DEL, 'failed-precondition', 'CONSENT_VERSION_MISSING'],
      [V4, 'invalid-argument', 'CONSENT_VERSION_SCREEN_MISMATCH'],
      ['2026-12-01-v9', 'invalid-argument', 'CONSENT_VERSION_UNSUPPORTED'],
    ];
    for (const [v, code, dcode] of cases) {
      seedInvite({});
      const before = F.dump();
      await rejectsWith(callInvite(INV_REQ(v)), code, dcode);
      assert.strictEqual(W.reads.length, 0, `${String(v)}: 읽기가 있었다`);
      assertNoWrites(String(v));
      assert.deepStrictEqual(F.dump(), before);
    }
  });

  await cell('IA-10', '이미 CONFIRMED + 유효 요청 → alreadyConfirmed 쓰기 0 · 은퇴 토큰은 완료 no-op 보다 먼저 거절', async () => {
    seedInvite({status: 'CONFIRMED', confirmedAt: at(T0), documentAccessConsentGiven: true,
      documentAccessConsentVersion: INV2, documentAccessConsentAt: at(T0)});
    const before = F.dump();
    const out = await callInvite(INV_REQ(INV2));
    await settle();
    assert.deepStrictEqual(out, {success: true, alreadyConfirmed: true});
    assertNoWrites('완료 no-op');
    assert.deepStrictEqual(F.dump(), before);
    F.clearLog();
    await rejectsWith(callInvite(INV_REQ(INV1)), 'invalid-argument', 'CONSENT_VERSION_RETIRED');
    assert.strictEqual(W.reads.length, 0, '판본 판정 전에 지원서를 읽었다');
    assertNoWrites('은퇴 토큰');
  });

  await cell('IA-11', '좌석·동의 원자성 — 동의 필드·CONFIRMED·카운터·겹침 정리가 한 커밋 · 커밋 실패면 동의도 0', async () => {
    seedInvite({});
    // 겹치는 다른 공고의 PENDING 한 건(같은 날 10:00-12:00) — 같은 커밋에서 AUTO_CANCELED(27224-27313).
    F.put('applications/p-other', {uid: 'w1', businessId: 'b2', toId: 't2', slotId: 's2', wdId: 'wd-9',
      status: 'PENDING', type: 'short', startTime: '10:00', endTime: '12:00', workDate: at(WORK_DAY),
      activationGeneration: 0});
    F.put('tos/t2/slots/s2', {date: at(WORK_DAY), workDetailCounts: {'wd-9': {confirmedCount: 0, pendingCount: 1}}});
    F.clearLog();
    await callInvite(INV_REQ(INV2));
    await settle();
    const cs = commitsWith(INV_PATH);
    assert.strictEqual(cs.length, 1);
    const main = cs[0];
    const paths = main.writes.map((w) => w.path);
    for (const p of [INV_PATH, 'tos/t1', SLOT_PATH, 'applications/p-other', 'tos/t2/slots/s2',
      'users/w1/notifications/schedule_conflict_autocancel_p-other_g0']) {
      assert.ok(paths.includes(p), `${p} 가 수락 커밋에 없다 — ${paths.join(', ')}`);
    }
    const patch = writeIn(main, INV_PATH, 'update').data;
    assert.strictEqual(patch.status, 'CONFIRMED');
    for (const k of ['documentAccessConsentGiven', 'documentAccessConsentVersion', 'documentAccessConsentAt',
      'idCardConsentGiven', 'idCardConsentAt', 'documentAccessConsentSource']) {
      assert.ok(k in patch, `동의 필드 ${k} 가 좌석 커밋에 없다`);
    }
    // 이 트랜잭션의 시도 = 이 커밋의 쓰기(다른 경로로 새는 쓰기 없음)
    assert.deepStrictEqual(ops(W.attempts.filter((w) => w.tx === main.tx)), ops(main.writes));
    const others = committed().filter((w) => w.via !== 'tx' + main.tx);
    // [L56 r5] 관리자 알림은 수락 커밋 안의 direct 작업이다(커밋 밖 쓰기 0) — 예전 모양(커밋 밖 관리자 알림 1건)도 받는다.
    const jobsInMain = main.writes.filter((w) => /^notification_jobs\//.test(w.path));
    if (jobsInMain.length > 0) {
      assert.strictEqual(others.length, 0, '수락 커밋 밖 쓰기가 있다 — ' + ops(others).join(', '));
      assert.strictEqual(jobsInMain.length, 1, '관리자 알림 작업 1건');
      assert.strictEqual(jobsInMain[0].data.recipientUid, 'admin1');
    } else {
      assert.ok(others.every((w) => /^users\/admin1\/notifications\//.test(w.path)),
        '수락 커밋 밖 쓰기는 관리자 알림뿐이어야 한다 — ' + ops(others).join(', '));
      assert.strictEqual(others.length, 1, '관리자 알림 1건');
    }
    const to = F.get('tos/t1');
    const s = F.get(SLOT_PATH);
    assert.deepStrictEqual([to.totalConfirmed, to.totalPending], [1, 0]);
    assert.deepStrictEqual([s.confirmedCount, s.pendingCount], [1, 0]);
    assert.deepStrictEqual(s.workDetailCounts['wd-1'], {confirmedCount: 1, pendingCount: 0});
    assert.strictEqual(F.get('applications/p-other').status, 'AUTO_CANCELED');
    assert.strictEqual(F.get('tos/t2/slots/s2').workDetailCounts['wd-9'].pendingCount, 0);

    // 커밋 실패 주입 — 동의만 따로 남는 길이 없다.
    seedInvite({});
    const before = F.dump();
    F.hooks.beforeCommit = (txId, buf) => {
      if (buf.some((w) => w.path === INV_PATH)) throw Object.assign(new Error('주입된 커밋 실패'), {code: 10});
    };
    let err = null;
    try {
      await callInvite(INV_REQ(INV2));
    } catch (e) {
      err = e;
    }
    await settle();
    assert.ok(err && /주입된 커밋 실패/.test(err.message), '주입한 실패가 전파되지 않았다');
    assert.deepStrictEqual(F.dump(), before, '커밋 실패인데 저장소가 바뀌었다');
    assert.strictEqual(W.direct.length, 0, '트랜잭션 밖에서 동의를 썼다');
    assert.strictEqual(notifs().length, 0);
  });

  // ════════════════════════════════════════════════════════════════════════
  console.log('\n[RA] 재배치 수락 — callableAcceptConfirmedReassignment');
  await cell('RA-1', 'INHERIT · A 유효 동의(v4 · t0) → B 가 같은 Given/Version/At + 계보 · A 종료 · ACCEPTED · lock 해제 · 정원 이동', async () => {
    seedReassign();
    const out = await callReassign(INHERIT());
    await settle();
    assert.deepStrictEqual(out, {success: true, targetApplicationId: B_ID});
    const a = F.get(appPath(A_ID));
    const b = F.get(appPath(B_ID));
    assert.ok(b, 'B 가 만들어지지 않았다');
    assert.strictEqual(b.status, 'CONFIRMED');
    assert.strictEqual(b.wdId, 'wd-2');
    assert.strictEqual(b.documentAccessConsentGiven, true);
    assert.strictEqual(b.documentAccessConsentVersion, V4);
    assert.strictEqual(ms(b.documentAccessConsentAt), T0, 'At 은 A 의 값 그대로(t0)');
    assert.strictEqual(b.idCardConsentGiven, true);
    assert.strictEqual(ms(b.idCardConsentAt), T0);
    assert.strictEqual(b.documentAccessConsentInheritedFrom, A_ID);
    assert.strictEqual(b.documentAccessConsentSource, 'REASSIGN_INHERITED');
    assert.strictEqual(ms(b.confirmedAt), T1, '재배치 수락 시각은 confirmedAt 에');
    assert.strictEqual(b.sourceApplicationId, A_ID);
    assert.strictEqual(b.offerKind, CR_KIND);
    assert.strictEqual(b.reassignmentProposalId, P1);
    assert.strictEqual(a.status, 'AUTO_CANCELED');
    assert.strictEqual(a.cancelReason, 'CONFIRMED_REASSIGNMENT_ACCEPTED');
    assert.strictEqual(a.reassignedToApplicationId, B_ID);
    assert.strictEqual(ms(a.documentAccessConsentAt), T0, 'A 의 동의 값은 바뀌지 않는다');
    const p = F.get(propPath(P1));
    assert.strictEqual(p.status, 'ACCEPTED');
    assert.strictEqual(p.resultApplicationId, B_ID);
    assert.strictEqual(ms(p.decidedAt), T1);
    assert.strictEqual(F.get(lockPath(A_ID)).activeProposalId, null);
    const s = F.get(SLOT_PATH);
    assert.strictEqual(s.workDetailCounts['wd-1'].confirmedCount, 0);
    assert.strictEqual(s.workDetailCounts['wd-2'].confirmedCount, 1);
    assert.strictEqual(s.confirmedCount, 1, '집계는 순증 0(쓰지 않는다)');
    const cs = commitsWith(appPath(B_ID));
    assert.strictEqual(cs.length, 1);
    const paths = cs[0].writes.map((w) => w.path);
    for (const q of [appPath(A_ID), appPath(B_ID), SLOT_PATH, propPath(P1), lockPath(A_ID)]) {
      assert.ok(paths.includes(q), `${q} 가 같은 커밋에 없다`);
    }
    assert.deepStrictEqual(notifs().map((n) => n.path), [`users/admin1/notifications/cr_accepted_${P1}`]);
  });

  await cell('RA-2', 'A→B→C 두 번 INHERIT → C 의 At 도 t0(B 의 appliedAt·confirmedAt 하한 없음)', async () => {
    seedReassign();
    await callReassign(INHERIT());
    await settle();
    NOW = T1 + HOUR;
    F.put(propPath(P2), SEED.proposal(B_ID, 'wd-2', 'wd-3'));
    F.put(lockPath(B_ID), SEED.lock(B_ID, P2));
    F.clearLog();
    const out = await callReassign(INHERIT(P2));
    await settle();
    assert.deepStrictEqual(out, {success: true, targetApplicationId: C_ID});
    const b = F.get(appPath(B_ID));
    const c = F.get(appPath(C_ID));
    assert.ok(c, 'C 가 만들어지지 않았다');
    assert.strictEqual(b.status, 'AUTO_CANCELED');
    assert.strictEqual(c.status, 'CONFIRMED');
    assert.strictEqual(ms(c.documentAccessConsentAt), T0);
    assert.ok(ms(c.documentAccessConsentAt) < ms(b.appliedAt) &&
      ms(c.documentAccessConsentAt) < ms(b.confirmedAt), 'At 이 B 생성 시각 하한으로 당겨졌다');
    assert.strictEqual(c.documentAccessConsentVersion, V4);
    assert.strictEqual(c.documentAccessConsentInheritedFrom, B_ID);
    assert.strictEqual(c.documentAccessConsentSource, 'REASSIGN_INHERITED');
    assert.strictEqual(c.sourceApplicationId, B_ID);
    assert.strictEqual(ms(c.confirmedAt), T1 + HOUR);
    assert.strictEqual(F.get(propPath(P2)).status, 'ACCEPTED');
  });

  const RA3 = [
    ['a', 'Given false', {documentAccessConsentGiven: false}, 'GIVEN_NOT_TRUE'],
    ['b', '판본 없음', {documentAccessConsentVersion: DEL}, 'VERSION_MISSING'],
    ['c', '은퇴 판본 v3', {documentAccessConsentVersion: V3}, 'VERSION_NOT_INHERITABLE'],
    ['d', 'At 없음', {documentAccessConsentAt: DEL}, 'AT_MISSING'],
    ['e', 'At 형식 오류(문자열)', {documentAccessConsentAt: '2026-11-10'}, 'AT_MALFORMED'],
    ['f', 'At 미래', {documentAccessConsentAt: at(T1 + MIN)}, 'AT_FUTURE'],
    ['g', 'Source=REASSIGN_INHERITED · inheritedFrom null',
      {documentAccessConsentSource: 'REASSIGN_INHERITED', documentAccessConsentInheritedFrom: null},
      'LINEAGE_INCONSISTENT:INHERITED_WITHOUT_PARENT'],
    ['h', 'inheritedFrom 있음 · Source≠REASSIGN_INHERITED',
      {documentAccessConsentSource: 'APPLY', documentAccessConsentInheritedFrom: 'a-old'},
      'LINEAGE_INCONSISTENT:PARENT_WITHOUT_INHERITED_SOURCE'],
  ];
  for (const [k, label, aOver, reason] of RA3) {
    await cell(`RA-3${k}`, `INHERIT · 승계 불가(${label}) → CONSENT_REQUIRED · 시도 0 · 커밋 0 · 알림 0 · 제안/lock/A/정원 그대로`, async () => {
      seedReassign({a: aOver});
      const before = F.dump();
      const e = await rejectsWith(callReassign(INHERIT()), 'failed-precondition', 'CONSENT_REQUIRED');
      assert.strictEqual(e.details.reason, reason);
      const txReads = W.reads.filter((r) => r.tx !== null);
      assert.ok(txReads.some((r) => r.path === SLOT_PATH) && txReads.some((r) => r.path === 'tos/t1'),
        '대상 공고·슬롯을 읽기 전에 동의를 판정했다');
      assert.ok(txReads.some((r) => r.kind === 'query' && r.path === 'applications'),
        '겹침 쿼리를 읽기 전에 동의를 판정했다');
      assertNoWrites(label);
      assert.deepStrictEqual(F.dump(), before, '저장소가 바뀌었다');
      assert.strictEqual(F.get(propPath(P1)).status, 'PROPOSED');
      assert.strictEqual(F.get(lockPath(A_ID)).activeProposalId, P1);
      assert.ok(!F.has(appPath(B_ID)));
    });
  }

  await cell('RA-4', 'A 가 EXPLICIT 재배치 관계(Source REASSIGN_EXPLICIT · parent 없음 · offerKind 재배치) → INHERIT 성공', async () => {
    seedReassign({a: {documentAccessConsentSource: 'REASSIGN_EXPLICIT', offerKind: CR_KIND,
      reassignmentProposalId: 'P0', sourceApplicationId: 'A0'}});
    const out = await callReassign(INHERIT());
    await settle();
    assert.deepStrictEqual(out, {success: true, targetApplicationId: B_ID});
    const b = F.get(appPath(B_ID));
    assert.strictEqual(b.documentAccessConsentInheritedFrom, A_ID);
    assert.strictEqual(b.documentAccessConsentSource, 'REASSIGN_INHERITED');
    assert.strictEqual(b.documentAccessConsentVersion, V4);
    assert.strictEqual(ms(b.documentAccessConsentAt), T0);
  });

  await cell('RA-5', 'CONSENT_REQUIRED 뒤 EXPLICIT(v4 · consentShown) → B 에 새 명시 동의(At = 수락 시각 · REASSIGN_EXPLICIT · parent 없음)', async () => {
    seedReassign({a: {documentAccessConsentVersion: V3}});
    await rejectsWith(callReassign(INHERIT()), 'failed-precondition', 'CONSENT_REQUIRED');
    NOW = T1 + 5 * MIN;
    F.clearLog();
    const out = await callReassign(EXPLICIT());
    await settle();
    assert.deepStrictEqual(out, {success: true, targetApplicationId: B_ID});
    const b = F.get(appPath(B_ID));
    assert.strictEqual(b.documentAccessConsentGiven, true);
    assert.strictEqual(b.documentAccessConsentVersion, V4);
    assert.strictEqual(ms(b.documentAccessConsentAt), T1 + 5 * MIN);
    assert.strictEqual(b.idCardConsentGiven, true);
    assert.strictEqual(ms(b.idCardConsentAt), T1 + 5 * MIN);
    assert.strictEqual(b.documentAccessConsentSource, 'REASSIGN_EXPLICIT');
    assert.ok(!('documentAccessConsentInheritedFrom' in b), 'EXPLICIT 인데 parent 가 있다');
    assert.strictEqual(F.get(appPath(A_ID)).documentAccessConsentVersion, V3, 'A 의 원 동의는 건드리지 않는다');
    assert.strictEqual(F.get(propPath(P1)).status, 'ACCEPTED');
  });

  await cell('RA-6', '프로토콜 거절(읽기 전) — 방식 없음·혼합·미표시·미동의·화면 불일치·은퇴·판본 없음 → 정확한 code · 읽기 0 · 쓰기 0', async () => {
    const cases = [
      ['방식 없음', {proposalId: P1}, 'invalid-argument', 'CONSENT_MODE_MISSING'],
      ['방식 소문자', {proposalId: P1, consentMode: 'inherit'}, 'invalid-argument', 'CONSENT_MODE_MISSING'],
      ['INHERIT+Given', INHERIT(P1, {documentAccessConsentGiven: true}), 'invalid-argument', 'CONSENT_MODE_PAYLOAD_MISMATCH'],
      ['INHERIT+판본', INHERIT(P1, {documentAccessConsentVersion: V4}), 'invalid-argument', 'CONSENT_MODE_PAYLOAD_MISMATCH'],
      ['INHERIT+Given null', INHERIT(P1, {documentAccessConsentGiven: null}), 'invalid-argument', 'CONSENT_MODE_PAYLOAD_MISMATCH'],
      ['EXPLICIT 미표시', EXPLICIT(P1, {consentShown: DEL}), 'invalid-argument', 'CONSENT_NOT_SHOWN'],
      ['EXPLICIT 표시 문자열', EXPLICIT(P1, {consentShown: 'true'}), 'invalid-argument', 'CONSENT_NOT_SHOWN'],
      ['EXPLICIT Given false', EXPLICIT(P1, {documentAccessConsentGiven: false}), 'invalid-argument', 'CONSENT_NOT_GIVEN'],
      ['EXPLICIT invite-v2', EXPLICIT(P1, {documentAccessConsentVersion: INV2}), 'invalid-argument', 'CONSENT_VERSION_SCREEN_MISMATCH'],
      ['EXPLICIT v3', EXPLICIT(P1, {documentAccessConsentVersion: V3}), 'invalid-argument', 'CONSENT_VERSION_RETIRED'],
      ['EXPLICIT invite-v1', EXPLICIT(P1, {documentAccessConsentVersion: INV1}), 'invalid-argument', 'CONSENT_VERSION_RETIRED'],
      ['EXPLICIT 판본 없음', EXPLICIT(P1, {documentAccessConsentVersion: DEL}), 'failed-precondition', 'CONSENT_VERSION_MISSING'],
    ];
    for (const [label, data, code, dcode] of cases) {
      seedReassign();
      const before = F.dump();
      await rejectsWith(callReassign(data), code, dcode);
      assert.strictEqual(W.reads.length, 0, `${label}: 읽기 ${W.reads.length}건`);
      assertNoWrites(label);
      assert.deepStrictEqual(F.dump(), before, `${label}: 저장소가 바뀌었다`);
    }
  });

  const RA7 = [
    ['a', 'A.toId ≠ 제안 targetToId', {toId: 't9'}, 'TO'],
    ['b', 'A.uid ≠ 호출자', {uid: 'w2'}, 'UID'],
    ['c', 'A.workDate ≠ 제안 workDate', {workDate: at(WORK_DAY + DAY)}, 'WORK_DATE'],
  ];
  for (const [k, label, aOver, reason] of RA7) {
    await cell(`RA-7${k}`, `계보 불일치(${label}) → REASSIGN_LINEAGE_MISMATCH · 커밋 0 · 알림 0`, async () => {
      seedReassign({a: aOver});
      const before = F.dump();
      const e = await rejectsWith(callReassign(INHERIT()), 'failed-precondition', 'REASSIGN_LINEAGE_MISMATCH');
      assert.strictEqual(e.details.reason, reason);
      assertNoWrites(label);
      assert.ok(W.aborts.length >= 1, '트랜잭션이 던지지 않았다');
      assert.deepStrictEqual(F.dump(), before);
    });
  }

  await cell('RA-8a', '기존 종료 결과 보존 — 제안 만료(expiresAt ≤ now) → EXPIRED·lock 해제 커밋 + 알림 1 + failed-precondition', async () => {
    seedReassign({p: {expiresAt: at(T1)}});
    const before = F.dump();
    const e = await rejectsWith(callReassign(INHERIT()), 'failed-precondition');
    assert.match(e.message, /변경 가능 시간이 지나/);
    assert.ok(!e.details, 'terminal 결과에 details 가 붙었다');
    const p = F.get(propPath(P1));
    assert.strictEqual(p.status, 'EXPIRED');
    assert.strictEqual(ms(p.decidedAt), T1);
    assert.strictEqual(p.history[p.history.length - 1].action, 'EXPIRED_AT_ACCEPT');
    assert.strictEqual(F.get(lockPath(A_ID)).activeProposalId, null);
    assert.deepStrictEqual(F.canon(F.get(appPath(A_ID))), before[appPath(A_ID)], 'A 가 바뀌었다');
    assert.ok(!F.has(appPath(B_ID)));
    const cs = commitsWith(propPath(P1));
    assert.strictEqual(cs.length, 1);
    assert.deepStrictEqual(ops(cs[0].writes).sort(),
      [`set ${lockPath(A_ID)}`, `update ${propPath(P1)}`].sort());
    const ns = notifs();
    assert.deepStrictEqual(ns.map((n) => n.path), [`users/admin1/notifications/cr_superseded_${P1}`]);
    assert.strictEqual(ns[0].data.data.reasonCode, 'EXPIRED');
  });

  await cell('RA-8b', '기존 종료 결과 보존 — 대상 정원 참 → TARGET_UNAVAILABLE(SUPERSEDED · TARGET_FULL) 커밋 + 알림', async () => {
    seedReassign({slot: {confirmedCount: 4, workDetailCounts: wdc({'wd-1': [1, 0], 'wd-2': [3, 0]})}});
    const before = F.dump();
    const e = await rejectsWith(callReassign(INHERIT()), 'failed-precondition');
    assert.match(e.message, /현재 변경할 자리가 없어/);
    const p = F.get(propPath(P1));
    assert.strictEqual(p.status, 'SUPERSEDED');
    assert.strictEqual(p.supersededReason, 'TARGET_FULL');
    assert.strictEqual(F.get(lockPath(A_ID)).activeProposalId, null);
    assert.deepStrictEqual(F.canon(F.get(appPath(A_ID))), before[appPath(A_ID)]);
    assert.deepStrictEqual(F.canon(F.get(SLOT_PATH)), before[SLOT_PATH], '정원이 바뀌었다');
    assert.ok(!F.has(appPath(B_ID)));
    const ns = notifs();
    assert.strictEqual(ns.length, 1);
    assert.strictEqual(ns[0].data.data.reasonCode, 'TARGET_UNAVAILABLE');
  });

  await cell('RA-8c', 'A 가 첫 사전 읽기에서 없음 → 트랜잭션 전 거절(종료 커밋 없음 · 제안 PROPOSED 유지 · 알림 0)', async () => {
    seedReassign();
    F.del(appPath(A_ID));
    const before = F.dump();
    const e = await rejectsWith(callReassign(INHERIT()), 'failed-precondition');
    assert.match(e.message, /기존 근무를 찾을 수 없습니다/);
    assert.strictEqual(W.commits.length + W.aborts.length, 0, '트랜잭션이 열렸다');
    assertNoWrites('A 없음');
    assert.deepStrictEqual(F.dump(), before);
    assert.strictEqual(F.get(propPath(P1)).status, 'PROPOSED');
  });

  await cell('RA-8d', 'SOURCE_GONE terminal 은 사전 읽기와 트랜잭션 사이에 A 가 사라질 때만(훅 재현) → SUPERSEDED·lock 해제 + 알림', async () => {
    seedReassign();
    F.hooks.afterGet = (p, txId) => {
      if (txId === null && p === appPath(A_ID)) {
        F.del(p);
        F.hooks.afterGet = null;
      }
    };
    const e = await rejectsWith(callReassign(INHERIT()), 'failed-precondition');
    assert.match(e.message, /기존 근무 정보를 찾을 수 없습니다/);
    const p = F.get(propPath(P1));
    assert.strictEqual(p.status, 'SUPERSEDED');
    assert.strictEqual(p.supersededReason, 'SOURCE_GONE');
    assert.strictEqual(F.get(lockPath(A_ID)).activeProposalId, null);
    assert.ok(!F.has(appPath(B_ID)));
    const ns = notifs();
    assert.strictEqual(ns.length, 1);
    assert.strictEqual(ns[0].data.data.reasonCode, 'SOURCE_GONE');
  });

  await cell('RA-9', '판정 순서 — 대상 불가 + 승계 불가 동시 → terminal TARGET_UNAVAILABLE(CONSENT_REQUIRED 아님)', async () => {
    seedReassign({a: {documentAccessConsentVersion: V3},
      slot: {confirmedCount: 4, workDetailCounts: wdc({'wd-1': [1, 0], 'wd-2': [3, 0]})}});
    const e = await rejectsWith(callReassign(INHERIT()), 'failed-precondition');
    assert.ok(!e.details || e.details.code !== 'CONSENT_REQUIRED', '동의 결손으로 분류했다');
    assert.match(e.message, /현재 변경할 자리가 없어/);
    assert.strictEqual(F.get(propPath(P1)).supersededReason, 'TARGET_FULL');
    assert.strictEqual(notifs().length, 1);
  });

  await cell('RA-10', 'CONSENT_REQUIRED 뒤 재호출 EXPLICIT 도 모든 문턱을 다시 넘는다 — 그 사이 만료 → EXPIRED terminal(성공 아님)', async () => {
    seedReassign({a: {documentAccessConsentVersion: V3}});
    await rejectsWith(callReassign(INHERIT()), 'failed-precondition', 'CONSENT_REQUIRED');
    assert.strictEqual(F.get(propPath(P1)).status, 'PROPOSED');
    NOW = T1 + 23 * HOUR; // = expiresAt
    F.clearLog();
    const e = await rejectsWith(callReassign(EXPLICIT()), 'failed-precondition');
    assert.match(e.message, /변경 가능 시간이 지나/);
    assert.strictEqual(F.get(propPath(P1)).status, 'EXPIRED');
    assert.ok(!F.has(appPath(B_ID)), '만료인데 B 가 생겼다');
    assert.strictEqual(F.get(appPath(A_ID)).status, 'CONFIRMED');
    const ns = notifs();
    assert.strictEqual(ns.length, 1);
    assert.strictEqual(ns[0].data.data.reasonCode, 'EXPIRED');
  });

  await cell('RA-11', '중복 — ACCEPTED + INHERIT → alreadyAccepted 쓰기 0 · ACCEPTED + 은퇴 토큰 EXPLICIT → 읽기 전 명시 거절', async () => {
    seedReassign({p: {status: 'ACCEPTED', resultApplicationId: 'B-prev', decidedAt: at(T1 - HOUR)}});
    const before = F.dump();
    const out = await callReassign(INHERIT());
    await settle();
    assert.deepStrictEqual(out, {success: true, alreadyAccepted: true, targetApplicationId: 'B-prev'});
    assertNoWrites('ACCEPTED no-op');
    assert.deepStrictEqual(W.reads.map((r) => r.path), [propPath(P1)], '제안 한 건만 읽어야 한다');
    assert.deepStrictEqual(F.dump(), before);
    F.clearLog();
    await rejectsWith(callReassign(EXPLICIT(P1, {documentAccessConsentVersion: V3})),
      'invalid-argument', 'CONSENT_VERSION_RETIRED');
    assert.strictEqual(W.reads.length, 0);
    assertNoWrites('ACCEPTED + 은퇴 토큰');
  });

  // ════════════════════════════════════════════════════════════════════════
  console.log('\n[r4c] H15 판정 시각 · INHERIT 키 · 계좌 reader 마지막 경계');
  await cell('IA-12', '[r4c] 트랜잭션 앞 confirmedAt < 저장 At ≤ 트랜잭션 안 현재 → 원 At 보존(미래로 보고 덮지 않음)', async () => {
    seedInvite({documentAccessConsentGiven: true, documentAccessConsentVersion: INV2,
      documentAccessConsentAt: at(T1 + 5000), documentAccessConsentSource: 'CONSENT_ONLY'});
    F.hooks.afterGet = (p, txId) => {
      if (txId && p === INV_PATH) NOW = T1 + 10000; // 트랜잭션 안 첫 읽기에서 시계가 앞으로 간다
    };
    await callInvite(INV_REQ(INV2));
    await settle();
    const a = F.get(INV_PATH);
    assert.strictEqual(a.status, 'CONFIRMED');
    assert.strictEqual(ms(a.documentAccessConsentAt), T1 + 5000, '원 At 이 덮였다');
    assert.strictEqual(ms(a.confirmedAt), T1, 'confirmedAt 은 트랜잭션 앞 시각');
    const h = lastHistory(a, 'INVITE_ACCEPTED');
    assert.strictEqual(h.consentPreserved, true);
    assert.strictEqual(h.consentPlanReason, 'SAME_GENERATION_VALID');
  });
  await cell('IA-12b', '[r4c] 판정 시각(max)보다도 미래인 저장 At → AT_FUTURE 로 새로 기록(진짜 미래 거절)', async () => {
    seedInvite({documentAccessConsentGiven: true, documentAccessConsentVersion: INV2,
      documentAccessConsentAt: at(T1 + HOUR), documentAccessConsentSource: 'CONSENT_ONLY'});
    F.hooks.afterGet = (p, txId) => {
      if (txId && p === INV_PATH) NOW = T1 + 10000;
    };
    await callInvite(INV_REQ(INV2));
    await settle();
    const a = F.get(INV_PATH);
    assert.strictEqual(ms(a.documentAccessConsentAt), T1, '새 동의 At = confirmedAt');
    const h = lastHistory(a, 'INVITE_ACCEPTED');
    assert.strictEqual(h.consentPreserved, false);
    assert.strictEqual(h.consentPlanReason, 'AT_FUTURE');
    assert.strictEqual(h.prevConsentAtMs, T1 + HOUR);
  });
  await cell('RA-12', '[r4c · PP-R4B-INHERIT] INHERIT + 명시 동의 키 존재(true/false/null/undefined) → CONSENT_MODE_PAYLOAD_MISMATCH · 읽기 0 · 쓰기 0 · 알림 0', async () => {
    for (const extra of [{consentShown: true}, {consentShown: false}, {consentShown: null},
      {consentShown: undefined}, {documentAccessConsentGiven: null}, {documentAccessConsentVersion: undefined}]) {
      seedReassign();
      const before = F.dump();
      await rejectsWith(callReassign(INHERIT(P1, extra)), 'invalid-argument', 'CONSENT_MODE_PAYLOAD_MISMATCH');
      assert.strictEqual(W.reads.length, 0, JSON.stringify(Object.keys(extra)));
      assertNoWrites('INHERIT 혼합 ' + Object.keys(extra)[0]);
      assert.deepStrictEqual(F.dump(), before);
    }
    // 정상 INHERIT(키 생략)는 그대로 성공 경로(RA-1 과 같은 장면).
    seedReassign();
    await callReassign(INHERIT(P1));
    await settle();
    assert.strictEqual(F.get(propPath(P1)).status, 'ACCEPTED');
  });

  // ── 계좌 reader ────────────────────────────────────────────────────────
  const AR_APP = 'ar1';
  const L30 = WORK_DAY + 30 * DAY; // 근태 0건 단기 = A2 · KST(L)+30×24h 배타
  function seedAccount(o = {}) {
    F.reset();
    NOW = o.now !== undefined ? o.now : L30 - MIN;
    seedBase();
    F.put('users/w1', SEED.worker(Object.assign({bankAccountVersion: 1, bankbookDocumentVersion: 1}, o.worker || {})));
    F.put(appPath(AR_APP), SEED.confirmedA({toId: 't9', slotId: 's9'}));
    F.clearLog();
  }
  const callAccount = (uid = 'admin1') =>
    R.callableGetWorkerPayrollAccount({auth: {uid}, data: {businessId: 'b1', applicationId: AR_APP}});
  const logs = () => committed().filter((w) => w.path.startsWith('payroll_account_access_logs/'));
  await cell('AR-1', '[r4c · F-R4B-4] 열림 → OK · window = 최종 재판정 · 기록 = 접근 판정/응답 준비(계좌 값 0)', async () => {
    seedAccount();
    const r = await callAccount();
    assert.strictEqual(r.status, 'OK');
    assert.strictEqual(r.window.state, 'A2_NO_PAYMENT_L30');
    assert.strictEqual(r.window.closesAtMs, L30);
    const lg = logs();
    assert.strictEqual(lg.length, 1);
    assert.strictEqual(lg[0].data.event, 'ACCOUNT_ACCESS_DECISION_PREPARED');
    for (const k of ['bankName', 'accountNumber', 'accountHolder']) assert.ok(!(k in lg[0].data), k);
  });
  await cell('AR-2', '[r4c · F-R4B-4] 로그 대기 중 L30 정각을 넘음 → 계좌 미전달(BANK_WINDOW_CLOSED) · 앞선 기록은 미전달과 모순 아님', async () => {
    seedAccount();
    F.hooks.afterDirect = (rec) => {
      if (rec.path.startsWith('payroll_account_access_logs/')) NOW = L30; // 기록이 끝나는 동안 정각
    };
    const r = await callAccount();
    assert.strictEqual(r.status, 'DENIED');
    assert.strictEqual(r.reason, 'BANK_WINDOW_CLOSED');
    assert.strictEqual(r.closedKind, 'PERIOD_ENDED');
    assert.ok(!('account' in r), '계좌가 실렸다');
    assert.strictEqual(logs().length, 1, '접근 판정 사건은 남는다(전달 증거 아님)');
  });
  await cell('AR-2b', '[r4c] 로그 대기 중 정각 1ms 전까지만 → OK(경계 −1ms 열림)', async () => {
    seedAccount();
    F.hooks.afterDirect = (rec) => {
      if (rec.path.startsWith('payroll_account_access_logs/')) NOW = L30 - 1;
    };
    const r = await callAccount();
    assert.strictEqual(r.status, 'OK');
  });
  await cell('AR-3', '[r4c] 무계좌(은행 3필드 결손) → NOT_REGISTERED · 기록 0 · 계좌 0', async () => {
    seedAccount({worker: {bankName: DEL, accountNumber: DEL}});
    const r = await callAccount();
    assert.strictEqual(r.status, 'NOT_REGISTERED');
    assert.ok(!('account' in r));
    assert.strictEqual(logs().length, 0);
  });
  await cell('AR-4', '[r4c] 이미 닫힌 기간 → DENIED · 기록 0 · 권한 없는 사용자는 지원서 읽기 전 거절', async () => {
    seedAccount({now: L30});
    const r = await callAccount();
    assert.strictEqual(r.status, 'DENIED'); assert.strictEqual(logs().length, 0);
    seedAccount();
    F.put('users/x9', {role: 'USER', name: '남'});
    F.clearLog();
    await rejectsWith(callAccount('x9'), 'permission-denied');
    assert.ok(!W.reads.some((x) => x.path === appPath(AR_APP)), '권한 없는데 지원서를 읽었다');
  });

  await cell('AR-5', '[r4d · F-R4C-2] 조회 대기 중 L30 정각을 넘은 무계좌 → NOT_REGISTERED 아님(기한 밖 · DENIED) · 기록 0', async () => {
    seedAccount({worker: {bankName: DEL, accountNumber: DEL}});
    F.hooks.afterGet = (p, txId) => {
      if (!txId && p === 'users/w1') NOW = L30; // 근로자 문서 조회가 끝나는 동안 정각
    };
    const r = await callAccount();
    assert.strictEqual(r.status, 'DENIED'); assert.strictEqual(r.reason, 'BANK_WINDOW_CLOSED');
    assert.strictEqual(logs().length, 0);
  });
  await cell('AR-5b', '[r4d] 조회 대기 중 정각 1ms 전 무계좌 → NOT_REGISTERED · window = 조회 뒤 판정', async () => {
    seedAccount({worker: {bankName: DEL, accountNumber: DEL}});
    F.hooks.afterGet = (p, txId) => {
      if (!txId && p === 'users/w1') NOW = L30 - 1;
    };
    const r = await callAccount();
    assert.strictEqual(r.status, 'NOT_REGISTERED');
    assert.strictEqual(r.window.closesAtMs, L30);
  });
  await cell('AR-6', '[r4d] T30 — 지급 종결 관계에서 기록 대기 중 T+30×24h 정각 → 미전달', async () => {
    const PAY = WORK_DAY + 5 * DAY;
    seedAccount({now: PAY + 30 * DAY - MIN});
    F.put('attendance/at1', {applicationId: AR_APP, userId: 'w1', businessId: 'b1', status: 'present',
      wageStatus: 'transferred', finalWage: 80000, transferDate: at(PAY)});
    F.clearLog();
    F.hooks.afterDirect = (rec) => {
      if (rec.path.startsWith('payroll_account_access_logs/')) NOW = PAY + 30 * DAY;
    };
    const r = await callAccount();
    assert.strictEqual(r.status, 'DENIED'); assert.strictEqual(r.reason, 'BANK_WINDOW_CLOSED');
    assert.strictEqual(logs().length, 1);
  });
  await cell('AR-7', '[r4d] A1 — 종료일 결손 관계 · 계약 기간 마지막 날 → 기록 대기 중 다음 날 0시 → 미전달', async () => {
    const END = kst(2027, 3, 31);
    seedAccount({now: END + 23 * HOUR});
    F.put(appPath(AR_APP), SEED.confirmedA({toId: 't9', slotId: 's9', type: 'long_term', workDays: ['월'],
      desiredStartDate: at(kst(2026, 11, 2)), workDate: at(kst(2026, 11, 2))}));
    F.put('employment_contracts/c1', {applicationId: AR_APP, applicationIds: [], workerId: 'w1', businessId: 'b1',
      status: 'completed', employerSignedAt: at(kst(2026, 11, 1, 10)), workerSignedAt: at(kst(2026, 11, 1, 12)),
      snapshot: {contractStart: '2026-11-02', contractEnd: '2027-03-31'}});
    F.clearLog();
    F.hooks.afterDirect = (rec) => {
      if (rec.path.startsWith('payroll_account_access_logs/')) NOW = END + DAY;
    };
    const r = await callAccount();
    assert.strictEqual(r.status, 'DENIED'); assert.strictEqual(r.reason, 'BANK_WINDOW_CLOSED');
    assert.strictEqual(r.closedKind, 'NEEDS_CONFIRMATION', '계약 끝 다음 날 = L 불명(계약 끝을 L 로 쓰지 않음)');
  });

  console.log('\n[CL] 스텁 접촉');
  await cell('CL-9', '외부 관대 스텁에 닿지 않았다(모르는 외부 기능을 탄 경로 0)', () => {
    assert.deepStrictEqual(EXT_WARN, [], '스텁 없는 외부 이름이 폐포에 있다');
    assert.deepStrictEqual(F.EXT_TOUCHED.slice(0, 10), [], '관대 스텁에 닿았다');
  });

  console.log(`\n통과 ${pass} / 실패 ${fails.length}`);
  if (fails.length) {
    fails.forEach((f) => console.log('  - ' + f));
    process.exit(1);
  }
})().catch((e) => {
  console.log('시험 실행기 자체 오류: ' + (e && e.stack ? e.stack : e));
  process.exit(1);
});
