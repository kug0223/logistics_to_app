/**
 * [SRV75-MW r3 · 판정190 M2] base index.ts 3dd19e09 원문 + M2/판정190 선언만 정합한 후보의 원문을 실행하는 시험.
 *
 *   r2 후보(srv75_min_wage_r2.test.js e7358a04 · 미적용 · 보존)를 대체하는 새 바이트다. r2 대비 바뀐 것:
 *     · MW-A12 — 임의 오류 허용을 없애고 정확 말단(error 0 · {success:true} · CONFIRMED · 임금·시각 · 카운터)을 단언(F180-MW-A12-ORACLE)
 *     · MW-AP01–AP07 — 지원 callable 원문 폐포 실행: 정상 저장 필드 보존 · 사전 읽기 → 공고 삭제 → tx 재확인 → not-found · 쓰기 0 ·
 *       호출 전 삭제 대조 · 제한 문구(P1) · 공유 판정식 미달 · 2028 확인 불가(F180-MW-CHAIN-SCOPE)
 *     · MW-S08 — 급여 확정 writer 의 기준 → 저장 필드(appliedMinimumWage · appliedSupplementWage) 원문 대응
 *     · 원문 조각 자르기 — 끝 표지도 본문에서 정확 1회(시작·끝 각각 1회 계약)
 *
 *   대상(실행 시점 A functions/src/index.ts = 후보 적용본):
 *     · 순수 판정 — SRV_MINIMUM_WAGE_BY_YEAR · srvMinWageFromCfg52 · srvLoadMinimumWage · srvValidateMinimumWagePromise
 *       · srvParseTime/srvMinutesBetween · srvKstDateKey52 · srvMinWageSlotViolations52 · srvAssertAppPromiseMinWageInTx52
 *       · srvGetMinimumWage(급여 확정이 쓰는 옛 선택식 — 표만 공유)
 *     · 원문 조각 실행 — 지원 제한 문구 블록(P1) · 지원 트랜잭션 삭제 공고 재확인(P2) · 급여 확정 설정 해석 블록
 *     · callable — callableAcceptTOInvitation(P3) · callableApplyToTO(P1 · P2 · 공유 로더) 를 의존 폐포째 가짜 Firestore 위에서
 *     · 원문 순서·소비처 — 가드 자리 · 공유 helper 소비처 4 · 선언 모양(M2 max20) · 급여 확정 경로 · 저장 필드 대응
 *
 *   하네스: consent_r4d_callables.test.js(f419329d…) 60–701행 사본 + **두 줄 치환**(빌더 단언 · BC r1 과 같은 치환):
 *     ROOTS 에 callableApplyToTO 추가 · WANT_CONSTS 에 srvAttendancePolicyFingerprint 추가(지원 요청의 기준 토큰 계산용).
 *     같은 SEED · 같은 계측(W) · 같은 외부 차단(R5_NET). 순수 조각은 AST 최상위 선언을 이름마다 **정확히 1개** 잘라 transpile 해
 *     실행한다(재구현 0). 원문 조각은 시작·끝 표지가 그 callable 본문에서 각각 정확히 1번일 때만 자른다.
 *
 *   [OBS] 표시 셀 10개(C12 · V06 · V10 · T01 · K04 · X12 · D04 · S07 · A11 · A12)는 **현재 동작에 대한 진단 기대**다 —
 *   실행 관측 · 정책 승인 · 제품 수정 요구가 아니다(판정180 §4 처분표). F178-MW-NAN-TIME 은 OPEN 으로 남는다.
 *   10,700 의 법적 정확성 · 실급여 결과를 이 시험이 승인하지 않는다(보존 배포판과의 소스 정합만).
 *
 *   실행(판정 전 실행 0): cd functions && node --test --test-concurrency=1 --test-reporter=tap … test/srv75_min_wage_r3.test.js
 *   성공 = 마지막 줄 '통과 108 / 실패 0' · rc 0 · '[r5 차단]' 0. 실패가 하나라도 있으면 목록을 찍고 process.exit(1).
 *   셀 실패는 원문(시험 · seed · 제품)으로 분류한다 — 이 파일이 원인을 스스로 정하지 않는다.
 *   입력: ../src/index.ts · ../src/*.ts(폐포 로컬 모듈) · ./consent_r4d_fakestore · node_modules/typescript.
 *   네트워크 · 실제 Firestore · 에뮬레이터 0. 쓰기 0(메모리 가짜 저장소만).
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
  'callableGetWorkerPayrollAccount', 'callableApplyToTO'];

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
  'CR_TYPE', 'CR_PROPOSAL_COL', 'CR_LOCK_COL', 'ACCOUNT_DELETION_TOMBSTONE_COL',
  'srvAttendancePolicyFingerprint'];
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

// ════════════════════════════════════════════════════════════════════════════
// [SRV75-MW r3] 여기부터 이 파일의 몫 — 위 하네스는 consent_r4d_callables.test.js 60–701행과 같고 두 줄만 다르다
//   (ROOTS 에 callableApplyToTO · WANT_CONSTS 에 srvAttendancePolicyFingerprint — 지원 삭제 경합 사례 MW-AP 용).
// ════════════════════════════════════════════════════════════════════════════

// ── [P] 순수 원문 조각 하네스 ────────────────────────────────────────────────
const P_FNS = ['srvParseTime', 'srvMinutesBetween', 'srvGetMinimumWage', 'srvLoadMinimumWage',
  'srvValidateMinimumWagePromise', 'srvMinWageFromCfg52', 'srvMinWageUnavailableError52',
  'srvKstDateKey52', 'srvMinWageSlotViolations52', 'srvAssertAppPromiseMinWageInTx52'];
const P_VALS = ['SRV_MINIMUM_WAGE_BY_YEAR'];
const PSTORE = new Map();
const PREADS = [];
const pSnap = (p) => {
  const v = PSTORE.get(p);
  return {exists: v !== undefined, data: () => v};
};
const pdb = {collection: (c) => ({doc: (d) => {
  const p = `${c}/${d}`;
  return {path: p, get: async () => { PREADS.push({tx: false, path: p}); return pSnap(p); }};
}})};
const ptx = {get: async (r) => { PREADS.push({tx: true, path: r.path}); return pSnap(r.path); }};
function pTop(name, kind) {
  const hits = SF.statements.filter((st) => (kind === 'fn' ?
    (ts.isFunctionDeclaration(st) && !!st.name && st.name.text === name && !!st.body) :
    (ts.isVariableStatement(st) && st.declarationList.declarations.some((d) =>
      ts.isIdentifier(d.name) && d.name.text === name))));
  assert.strictEqual(hits.length, 1, `[P] 최상위 ${name} 선언 ${hits.length}개`);
  return `/* index.ts:${lineOf(hits[0])} */\n` + hits[0].getText(SF);
}
function bodyOf(name) {
  const head = `export const ${name} = onCall(`;
  const i = SRC.indexOf(head);
  assert.ok(i >= 0 && SRC.indexOf(head, i + 1) < 0, `${name} 머리가 정확히 1개가 아니다`);
  const j = SRC.indexOf('\nexport const ', i + 10);
  return SRC.slice(i, j < 0 ? SRC.length : j);
}
function sliceOnce(text, startMark, endMark, label) {
  const a = text.indexOf(startMark);
  assert.ok(a >= 0, `[${label}] 시작 표지 없음`);
  assert.strictEqual(text.indexOf(startMark, a + 1), -1, `[${label}] 시작 표지가 둘 이상`);
  const b = text.indexOf(endMark, a);
  assert.ok(b > a, `[${label}] 끝 표지 없음`);
  // [r3 · 판정180] 끝 표지도 그 본문에서 정확 1회 — 시작·끝 각각 1회 계약
  assert.strictEqual(text.indexOf(endMark), b, `[${label}] 끝 표지가 시작 앞에도 있다`);
  assert.strictEqual(text.indexOf(endMark, b + 1), -1, `[${label}] 끝 표지가 둘 이상`);
  return text.slice(a, b);
}
function runTs(src, names, inject) {
  const js = ts.transpileModule(src + `\nmodule.exports = {${names.join(', ')}};`, {compilerOptions: {
    target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS}}).outputText;
  const m = {exports: {}};
  const keys = Object.keys(inject);
  // eslint-disable-next-line no-new-func
  new Function('module', 'exports', ...keys, js)(m, m.exports, ...keys.map((k) => inject[k]));
  return m.exports;
}
let P = null;
let RS = null; // 지원 제한 문구 조각(P1)
let DG = null; // 지원 트랜잭션 삭제 공고 재확인 조각(P2)
let PC = null; // 급여 확정 설정 해석 조각
let P_ERR = null;
try {
  P = runTs([...P_VALS.map((n) => pTop(n, 'val')), ...P_FNS.map((n) => pTop(n, 'fn'))].join('\n\n'),
    [...P_FNS, ...P_VALS], {db: pdb, HttpsError, console: QCON, Date: FakeDate});
  const applyBody = bodyOf('callableApplyToTO');
  RS = runTs('function __restrict(userData: any) {\n' + sliceOnce(applyBody,
    'const restrictedUntilTs = userData["restrictedUntil"] as admin.firestore.Timestamp | undefined;',
    '// [CONFLICT-OF-INTEREST] 서브어드민이 자신이 관리하는 사업장 공고에 지원 차단', 'RS') +
    '\n  return null;\n}', ['__restrict'], {HttpsError, Date: FakeDate});
  DG = runTs('async function __delGuard(tx: any, toRef: any) {\n' + sliceOnce(applyBody,
    '// [POSTING-RACE-46] 공고 삭제와 같은 문서로 직렬화한다.',
    '// TOCTOU 방지: 트랜잭션 내 최종 마감·정원 재검증', 'DG') +
    '\n  return "PASS";\n}', ['__delGuard'], {HttpsError});
  PC = runTs('function __payrollCfg(cfgSnap: any) {\n' + sliceOnce(bodyOf('callableCalculateAndConfirmWage'),
    'const cfg = cfgSnap.data() ?? {};',
    'const fsRates: Record<number, Partial<SrvInsuranceRates>> = {};', 'PC') +
    '\n  return fsMinWages;\n}', ['__payrollCfg'], {});
} catch (e) {
  P_ERR = e;
}

// ── 공용 도우미 ─────────────────────────────────────────────────────────────
const kstMs = (y, mo, d, h = 0, mi = 0, s = 0, x = 0) => RealDate.UTC(y, mo - 1, d, h, mi, s, x) - KST;
const loc = (n) => n.toLocaleString();
const hourlyMsg = (w, m) => `시급 ${loc(w)}원은 최저임금 ${loc(m)}원 미만입니다.`;
const dailyMsg = (w, work, m) => `일급 ${loc(w)}원은 소정근로시간 ${(work / 60).toFixed(1)}시간 기준 최저일급 ` +
  `${loc(Math.ceil(m * work / 60))}원 미만입니다.`;
const MSG_WAGE_UNKNOWN = '임금을 확인할 수 없어 최저임금을 판정할 수 없습니다.';
const MSG_WORK_UNKNOWN = '일급 근무시간(시작·종료·휴게)으로 소정근로시간을 확인할 수 없어 최저임금을 판정할 수 없습니다.';
const TAIL_INVITE = ' 근무일 기준 최저임금에 못 미치는 초대라 수락할 수 없습니다. 사업장에 조건 수정이나 새 초대를 요청해 주세요.';
const TAIL_OTHER = ' 근무일 기준 최저임금에 못 미쳐 확정하지 않았습니다. 업무 임금을 고친 뒤 새로 지원·초대를 받아 주세요.';
const WCFG = 'settings/wage_config';
const V = (o) => P.srvValidateMinimumWagePromise(Object.assign({wageType: 'hourly', wage: 0, minimumWage: 10320,
  startTime: '09:00', endTime: '18:00', breakMinutes: 60}, o));
const VD = (o) => V(Object.assign({wageType: 'daily'}, o));
const pick = (y, cfg) => P.srvMinWageFromCfg52(y, cfg);
const mw = (o) => ({minimumWages: o});
function sync(fn) {
  try { fn(); } catch (e) { return e; }
  return null;
}
async function aw(p) {
  try { await p; } catch (e) { return e; }
  return null;
}
function isUnavailable(e, year, reason) {
  assert.ok(e instanceof HttpsError, '기준 확인 불가 오류가 아니다: ' + (e && e.message));
  assert.strictEqual(e.code, 'failed-precondition');
  assert.deepStrictEqual(e.details, {code: 'MIN_WAGE_UNAVAILABLE', year, reason});
  assert.strictEqual(e.message, `${year}년 최저임금 기준을 확인할 수 없어 처리하지 않았습니다. 관리자에게 문의해 주세요.`);
}
async function load(year, cfgDoc) {
  PSTORE.clear(); PREADS.length = 0;
  if (cfgDoc !== undefined) PSTORE.set(WCFG, cfgDoc);
  let v; let err = null;
  try { v = await P.srvLoadMinimumWage(year); } catch (e) { err = e; }
  return {v, err, reads: PREADS.slice()};
}
async function txGuard(app, kind = 'INVITE_ACCEPT', cfgDoc) {
  PSTORE.clear(); PREADS.length = 0;
  if (cfgDoc !== undefined) PSTORE.set(WCFG, cfgDoc);
  const err = await aw(P.srvAssertAppPromiseMinWageInTx52(ptx, app, kind));
  return {err, reads: PREADS.slice()};
}
const app27 = (o) => over({workDate: at(kstMs(2027, 3, 2)), wage: 10500, wageType: 'hourly',
  selectedWorkType: '피킹', startTime: '09:00', endTime: '18:00'}, o);
const payMin = (year, cfg) => P.srvGetMinimumWage(year, PC.__payrollCfg({data: () => cfg}));
const restrict = (ud) => sync(() => { const r = RS.__restrict(ud); assert.strictEqual(r, null); });
function delTx(doc) {
  const reads = [];
  return {reads, tx: {get: async (r) => { reads.push(r.path); return {exists: doc !== undefined, data: () => doc}; }}};
}
const firstWriteAfter = (text, from) => Math.min(...['tx.update(', 'tx.set(', 'tx.create(', 'tx.delete(']
  .map((s) => { const i = text.indexOf(s, from); return i < 0 ? Infinity : i; }));
const txReadsOf = (p) => W.reads.filter((r) => r.tx !== null && r.path === p).length;
const anyReadsOf = (p) => W.reads.filter((r) => r.path === p).length;
const cfgPut = (doc) => { F.put(WCFG, doc); F.clearLog(); };
function proj() {
  const a = F.get(INV_PATH);
  for (const k of ['wage', 'wageType', 'compensationSnapshot']) delete a[k];
  return F.canon({a, to: F.get('tos/t1'), slot: F.get(SLOT_PATH), w1: F.get('users/w1'), n: notifs().length});
}
let BASE_PROJ = null;
const obs = (id, s) => console.log(`       OBS ${id}: ${s}`);

// ── [r3] 지원 callable 장면(P1 · P2 · 공유 로더의 실제 writer 경로) ─────────────
const TO_PATH = 'tos/t1';
const APPLY_ID = 't1_s1_wd-1_w1';
const APPLY_REQ = (o = {}) => over({toId: 't1', slotId: 's1', businessId: 'b1', businessName: '테스트사업장',
  toTitle: '물류 센터 단기', workDateMs: WORK_DAY, selectedWorkType: '피킹', workDetailId: 'wd-1',
  startTime: '09:00', endTime: '18:00', wage: 12000, idCardConsentGiven: true,
  documentAccessConsentGiven: true, documentAccessConsentVersion: V4,
  expectedAttendancePolicy: R.srvAttendancePolicyFingerprint(SEED.business().attendanceRules)}, o);
/** wd-1 만 바꾼 슬롯 업무 목록(나머지 기본값). */
const WDS_WITH = (o) => WDS().map((w) => (w.wdId === 'wd-1' ? Object.assign({}, w, o) : w));
function seedApply(o = {}) {
  F.reset();
  NOW = o.now !== undefined ? o.now : T1;
  seedBase();
  if (o.worker) F.put('users/w1', SEED.worker(o.worker));
  F.put(TO_PATH, SEED.to(Object.assign({isPublished: true}, o.to || {})));
  F.put(SLOT_PATH, SEED.slot(o.slot || {}));
  if (o.cfg !== undefined) F.put(WCFG, o.cfg);
  F.clearLog();
}
const callApply = (data, uid = 'w1') => R.callableApplyToTO({auth: {uid}, data});
function afterFirstOuterRead(p0, fn) {
  F.hooks.afterGet = (p, txId) => {
    if (txId === null && p === p0) {
      F.hooks.afterGet = null;
      fn();
    }
  };
}
/** 공고 문서만 주입으로 바뀌었고 그 밖 저장소는 그대로인지. */
function sameExceptTo(before, label) {
  const now = F.dump();
  const b = Object.assign({}, before); const n = Object.assign({}, now);
  delete b[TO_PATH]; delete n[TO_PATH];
  assert.deepStrictEqual(n, b, label + ': 공고 밖 저장소가 바뀌었다');
}

(async () => {
  console.log('\n[P] 원문 조각 하네스');
  await cell('P-0', '순수 선언 11 · 제한·삭제·급여설정 조각 3 을 원문에서 정확히 1번씩 잘라 실행 준비 · 표 값', () => {
    assert.strictEqual(P_ERR, null, '조각 하네스 실패: ' + (P_ERR && (P_ERR.stack || P_ERR.message)));
    for (const n of P_FNS) assert.strictEqual(typeof P[n], 'function', n);
    assert.strictEqual(typeof RS.__restrict, 'function');
    assert.strictEqual(typeof DG.__delGuard, 'function');
    assert.strictEqual(typeof PC.__payrollCfg, 'function');
    assert.deepStrictEqual(P.SRV_MINIMUM_WAGE_BY_YEAR, {2020: 8590, 2021: 8720, 2022: 9160, 2023: 9620,
      2024: 9860, 2025: 10030, 2026: 10320, 2027: 10700});
  });

  console.log('\n[C] 연도 기준 선택 — srvMinWageFromCfg52');
  await cell('MW-C01', '설정 없음 → 그 해 내장값(2026 10,320 · 2027 10,700) · 내장 없는 해(2028 · 2019) ABSENT', () => {
    assert.deepStrictEqual(pick(2026, {}), {wage: 10320, source: 'BUILTIN'});
    assert.deepStrictEqual(pick(2027, {}), {wage: 10700, source: 'BUILTIN'});
    assert.deepStrictEqual(pick(2027, undefined), {wage: 10700, source: 'BUILTIN'});
    assert.deepStrictEqual(pick(2028, {}), {wage: null, reason: 'ABSENT'});
    assert.deepStrictEqual(pick(2019, {}), {wage: null, reason: 'ABSENT'});
  });
  await cell('MW-C02', 'minimumWages 가 객체가 아니면(문자열 · 숫자 · null) 없는 것으로 본다', () => {
    for (const v of ['10800', 10800, null]) assert.deepStrictEqual(pick(2027, {minimumWages: v}), {wage: 10700, source: 'BUILTIN'});
  });
  await cell('MW-C03', '문서값 > 고시 → 문서값(DOC)', () => {
    assert.deepStrictEqual(pick(2027, mw({'2027': 11000})), {wage: 11000, source: 'DOC'});
  });
  await cell('MW-C04', '문서값 < 고시 → 고시값(BUILTIN_FLOOR · 법정 하한은 설정으로 내려가지 않는다)', () => {
    assert.deepStrictEqual(pick(2027, mw({'2027': 10500})), {wage: 10700, source: 'BUILTIN_FLOOR'});
    assert.deepStrictEqual(pick(2026, mw({'2026': 1})), {wage: 10320, source: 'BUILTIN_FLOOR'});
  });
  await cell('MW-C05', '문서값 = 고시 → DOC', () => {
    assert.deepStrictEqual(pick(2027, mw({'2027': 10700})), {wage: 10700, source: 'DOC'});
  });
  await cell('MW-C06', '문자열 숫자 "10800" → CORRUPT', () => {
    assert.deepStrictEqual(pick(2027, mw({'2027': '10800'})), {wage: null, reason: 'CORRUPT'});
  });
  await cell('MW-C07', '0 → CORRUPT', () => {
    assert.deepStrictEqual(pick(2027, mw({'2027': 0})), {wage: null, reason: 'CORRUPT'});
  });
  await cell('MW-C08', '음수 → CORRUPT', () => {
    assert.deepStrictEqual(pick(2027, mw({'2027': -10700})), {wage: null, reason: 'CORRUPT'});
  });
  await cell('MW-C09', '소수 10,700.5 → CORRUPT', () => {
    assert.deepStrictEqual(pick(2027, mw({'2027': 10700.5})), {wage: null, reason: 'CORRUPT'});
  });
  await cell('MW-C10', 'NaN · Infinity · 불리언 · 객체 → CORRUPT', () => {
    for (const v of [NaN, Infinity, -Infinity, true, {v: 1}]) {
      assert.deepStrictEqual(pick(2027, mw({'2027': v})), {wage: null, reason: 'CORRUPT'}, String(v));
    }
  });
  await cell('MW-C11', 'null 은 부재로 본다(2027 → 내장 10,700 · 2028 → ABSENT)', () => {
    assert.deepStrictEqual(pick(2027, mw({'2027': null})), {wage: 10700, source: 'BUILTIN'});
    assert.deepStrictEqual(pick(2028, mw({'2028': null})), {wage: null, reason: 'ABSENT'});
  });
  await cell('MW-C12', '[OBS] 내장 없는 해(2028)의 문서값은 하한 없이 DOC(11,000 · 1)', () => {
    assert.deepStrictEqual(pick(2028, mw({'2028': 11000})), {wage: 11000, source: 'DOC'});
    assert.deepStrictEqual(pick(2028, mw({'2028': 1})), {wage: 1, source: 'DOC'});
    obs('MW-C12', '내장값 없는 해는 문서값 1 도 채택 — 하한은 내장 연도에만 있다');
  });
  await cell('MW-C13', '정확한 연도 키만 본다("2027x" · " 2027" · "02027" 무시 — 옛 parseInt 키 해석과 다름) · 숫자 키는 같은 키', () => {
    for (const k of ['2027x', ' 2027', '02027']) {
      assert.deepStrictEqual(pick(2027, mw({[k]: 11000})), {wage: 10700, source: 'BUILTIN'}, k);
    }
    assert.deepStrictEqual(pick(2027, mw({2027: 11000})), {wage: 11000, source: 'DOC'});
  });
  await cell('MW-C14', '확인 불가 오류 모양(failed-precondition · MIN_WAGE_UNAVAILABLE · year · reason · 문구)', () => {
    isUnavailable(P.srvMinWageUnavailableError52(2028, 'ABSENT'), 2028, 'ABSENT');
    isUnavailable(P.srvMinWageUnavailableError52(2027, 'CORRUPT'), 2027, 'CORRUPT');
  });

  console.log('\n[L] 공유 로더 — srvLoadMinimumWage(지원·초대 발송·대체근무 제안·재배치 제안이 쓴다)');
  await cell('MW-L01', '설정 문서 없음 · 2026 → 10,320 · 읽기 = settings/wage_config 1건(트랜잭션 밖)', async () => {
    const r = await load(2026);
    assert.strictEqual(r.err, null);
    assert.strictEqual(r.v, 10320);
    assert.deepStrictEqual(r.reads, [{tx: false, path: WCFG}]);
  });
  await cell('MW-L02', '설정 문서 없음 · 2027 → 10,700(옛 판: 최근 내장 10,320 대체)', async () => {
    const r = await load(2027);
    assert.strictEqual(r.err, null);
    assert.strictEqual(r.v, 10700);
  });
  await cell('MW-L03', '설정 문서 없음 · 2028 → MIN_WAGE_UNAVAILABLE ABSENT(옛 판: 10,320 대체 통과)', async () => {
    const r = await load(2028);
    isUnavailable(r.err, 2028, 'ABSENT');
  });
  await cell('MW-L04', '문서 2027 = "10500"(문자열) → CORRUPT 거절(옛 판: 무시하고 내장 대체)', async () => {
    const r = await load(2027, mw({'2027': '10500'}));
    isUnavailable(r.err, 2027, 'CORRUPT');
  });
  await cell('MW-L05', '문서 2027 = 10,500 → 10,700(고시 하한 · 옛 판: 10,500 그대로)', async () => {
    const r = await load(2027, mw({'2027': 10500}));
    assert.strictEqual(r.err, null);
    assert.strictEqual(r.v, 10700);
  });
  await cell('MW-L06', '문서 2026 = 0 → CORRUPT 거절(옛 판: 기준 0 → 판정 생략 통과)', async () => {
    const r = await load(2026, mw({'2026': 0}));
    isUnavailable(r.err, 2026, 'CORRUPT');
  });
  await cell('MW-L07', '문서에 다른 해만 있음(2026 = 11,000) · 2027 요청 → 그 해 내장 10,700(다른 해 값으로 대신하지 않음)', async () => {
    const r = await load(2027, mw({'2026': 11000}));
    assert.strictEqual(r.err, null);
    assert.strictEqual(r.v, 10700);
  });

  console.log('\n[V] 판정식 — srvValidateMinimumWagePromise');
  await cell('MW-V01', '시급 경계 — 같으면 통과 · 1원 모자라면 미달 문구', () => {
    assert.strictEqual(V({wage: 10320}), null);
    assert.strictEqual(V({wage: 10319}), hourlyMsg(10319, 10320));
  });
  await cell('MW-V02', '기준 ≤ 0 이면 판정하지 않는다(null · 그대로)', () => {
    assert.strictEqual(V({wage: 1, minimumWage: 0}), null);
    assert.strictEqual(V({wage: 1, minimumWage: -1}), null);
  });
  await cell('MW-V03', '임금이 유한 숫자가 아니면 판정 불가 문구(NaN · 문자열 · ±Infinity · undefined · null · 객체 · 일급도) — 옛 판: 통과', () => {
    for (const w of [NaN, '12000', Infinity, -Infinity, undefined, null, {}]) {
      assert.strictEqual(V({wage: w}), MSG_WAGE_UNKNOWN, String(w));
    }
    assert.strictEqual(VD({wage: NaN}), MSG_WAGE_UNKNOWN);
  });
  await cell('MW-V04', '일급 정수 경계(09–18 · 휴게 60 · 2026 → 480분 · 최저일급 82,560)', () => {
    assert.strictEqual(VD({wage: 82560}), null);
    assert.strictEqual(VD({wage: 82559}), dailyMsg(82559, 480, 10320));
  });
  await cell('MW-V05', '일급 정수 동치 — 481분 · 2027(10,700): 정수 임금이면 새 식(일급×60 < 시급×분) = 옛 올림 식', () => {
    const minD = Math.ceil(10700 * 481 / 60);
    for (let w = minD - 3; w <= minD + 3; w++) {
      const got = VD({wage: w, minimumWage: 10700, endTime: '18:01'});
      assert.strictEqual(got !== null, w < minD, `w=${w} minD=${minD}`);
    }
  });
  await cell('MW-V06', '[OBS] 일급 소수 85,778.5원(481분 · 2027) → 새 식 통과 · 옛 올림 식이면 85,779 미달 — 소수 임금 완화 관측', () => {
    assert.ok(85778.5 < Math.ceil(10700 * 481 / 60), '옛 식이면 미달이어야 의미 있는 사례');
    assert.strictEqual(VD({wage: 85778.5, minimumWage: 10700, endTime: '18:01'}), null);
    obs('MW-V06', '정수 임금은 동치 · 소수 임금은 before 보다 완화(판정178 §2 Q3)');
  });
  await cell('MW-V07', '소정 0분(시작 = 종료) → 판정 불가(옛 판: 통과)', () => {
    assert.strictEqual(VD({wage: 1, startTime: '09:00', endTime: '09:00', breakMinutes: 0}), MSG_WORK_UNKNOWN);
  });
  await cell('MW-V08', '휴게 ≥ 총 시간(60/60 · 120/60) → 판정 불가', () => {
    assert.strictEqual(VD({wage: 1, startTime: '09:00', endTime: '10:00', breakMinutes: 60}), MSG_WORK_UNKNOWN);
    assert.strictEqual(VD({wage: 1, startTime: '09:00', endTime: '10:00', breakMinutes: 120}), MSG_WORK_UNKNOWN);
  });
  await cell('MW-V09', '시작·종료가 비었거나 시·분 범위 밖("" · "9" · "25:00" · "09:60" · "24:00") → 판정 불가', () => {
    for (const [s, e] of [['', '18:00'], ['09:00', ''], ['9', '18:00'], ['25:00', '18:00'],
      ['09:60', '18:00'], ['24:00', '18:00']]) {
      assert.strictEqual(VD({wage: 1, startTime: s, endTime: e}), MSG_WORK_UNKNOWN, `${s}-${e}`);
    }
  });
  await cell('MW-V10', '[OBS · F178-MW-NAN-TIME] 숫자가 아닌 시·분(xx:yy · 9:xx · xx:00 · 끝 ab:cd) → 소정분 NaN → 통과(null) — 판정 불가 전부 차단 아님', () => {
    for (const [s, e] of [['xx:yy', '18:00'], ['9:xx', '18:00'], ['xx:00', '18:00'], ['09:00', 'ab:cd']]) {
      assert.strictEqual(VD({wage: 1, startTime: s, endTime: e}), null, `${s}-${e}`);
    }
    obs('MW-V10', 'srvParseTime 이 NaN 을 null 로 바꾸지 않아 1원 일급도 통과 — parser 수정은 이 셀 권한 밖');
  });
  await cell('MW-V11', '휴게가 숫자가 아니면 0 으로 본다("abc" · undefined → 540분 판정 · 옛 판: NaN 으로 통과)', () => {
    assert.strictEqual(VD({wage: 10000, breakMinutes: 'abc'}), dailyMsg(10000, 540, 10320));
    assert.strictEqual(VD({wage: 10000, breakMinutes: undefined}), dailyMsg(10000, 540, 10320));
  });
  await cell('MW-V12', '자정 넘김(22:00–06:00 · 휴게 60 → 420분 · 72,240)', () => {
    assert.strictEqual(VD({wage: 72240, startTime: '22:00', endTime: '06:00'}), null);
    assert.strictEqual(VD({wage: 72239, startTime: '22:00', endTime: '06:00'}), dailyMsg(72239, 420, 10320));
  });
  await cell('MW-V13', '시급·일급 밖 형태(monthly · undefined · "" · HOURLY) → 판정하지 않는다(null · 그대로)', () => {
    for (const t of ['monthly', undefined, '', 'HOURLY']) assert.strictEqual(V({wageType: t, wage: 1}), null, String(t));
  });
  await cell('MW-V14', '시급 소수 — 10,320.5 통과 · 10,319.9 미달(시급 비교식 그대로)', () => {
    assert.strictEqual(V({wage: 10320.5}), null);
    assert.strictEqual(V({wage: 10319.9}), hourlyMsg(10319.9, 10320));
  });

  console.log('\n[T] 시각 파서 관측 — srvParseTime · srvMinutesBetween(변경 0 · 영향 분류용)');
  await cell('MW-T01', '[OBS] srvParseTime("xx:yy") · ("9:xx") = NaN(null 아님) → srvMinutesBetween = NaN', () => {
    assert.ok(Number.isNaN(P.srvParseTime('xx:yy')));
    assert.ok(Number.isNaN(P.srvParseTime('9:xx')));
    assert.ok(Number.isNaN(P.srvMinutesBetween('xx:yy', '18:00')));
    obs('MW-T01', 'NaN 반환 경로 — 호출 전제: 지원은 HH:MM 정규식 선검사(작성 시 원문) · 초대/제안/수락은 저장값 그대로');
  });
  await cell('MW-T02', '정상·경계 파싱("" · undefined · "24:00" → null · "23:59" 1439 · "00:00" 0 · "09:00:30" 540 · 23→01 120분)', () => {
    assert.strictEqual(P.srvParseTime(''), null);
    assert.strictEqual(P.srvParseTime(undefined), null);
    assert.strictEqual(P.srvParseTime('24:00'), null);
    assert.strictEqual(P.srvParseTime('23:59'), 1439);
    assert.strictEqual(P.srvParseTime('00:00'), 0);
    assert.strictEqual(P.srvParseTime('09:00:30'), 540);
    assert.strictEqual(P.srvMinutesBetween('23:00', '01:00'), 120);
    assert.strictEqual(P.srvMinutesBetween('', '01:00'), 0);
  });

  console.log('\n[K] KST 날짜 라벨·연도 — srvKstDateKey52 · srvMinWageSlotViolations52');
  await cell('MW-K01', '연말 경계 — UTC 2026-12-31 14:59:59.999 = KST 12/31 · +1ms = 2027-01-01', () => {
    const t = RealDate.UTC(2026, 11, 31, 14, 59, 59, 999);
    assert.strictEqual(P.srvKstDateKey52(t), '2026-12-31');
    assert.strictEqual(P.srvKstDateKey52(t + 1), '2027-01-01');
  });
  await cell('MW-K02', '월말 경계 — KST 2027-02-28 마지막 ms → 다음 ms 2027-03-01', () => {
    const t = kstMs(2027, 3, 1) - 1;
    assert.strictEqual(P.srvKstDateKey52(t), '2027-02-28');
    assert.strictEqual(P.srvKstDateKey52(t + 1), '2027-03-01');
  });
  await cell('MW-K03', '윤일 — KST 2028-02-29(정오 · 전날 마지막 ms+1)', () => {
    assert.strictEqual(P.srvKstDateKey52(kstMs(2028, 2, 29, 12)), '2028-02-29');
    assert.strictEqual(P.srvKstDateKey52(kstMs(2028, 2, 29) - 1 + 1), '2028-02-29');
    assert.strictEqual(P.srvKstDateKey52(kstMs(2028, 2, 29) - 1), '2028-02-28');
  });
  await cell('MW-K04', '[OBS] 유효하지 않은 ms(NaN · 범위 밖) → RangeError(호출 전제 = 유효 유한 ms · 모든 입력 보증 아님)', () => {
    assert.throws(() => P.srvKstDateKey52(NaN), RangeError);
    assert.throws(() => P.srvKstDateKey52(8.64e15), RangeError);
  });
  const WDH = (wage) => ({wageType: 'hourly', wage, workType: '피킹'});
  await cell('MW-K05', '위반 수집 연도는 KST — 12/31 23:59 KST 10,500 통과 · 1/1 00:00 KST 10,500 미달(라벨 2027-01-01)', () => {
    const out = P.srvMinWageSlotViolations52({}, [{dateMs: kstMs(2026, 12, 31, 23, 59), wd: WDH(10500)},
      {dateMs: kstMs(2027, 1, 1), wd: WDH(10500)}]);
    assert.deepStrictEqual(out, [{date: '2027-01-01', workType: '피킹', reason: hourlyMsg(10500, 10700)}]);
  });
  await cell('MW-K06', '내장 없는 해(2028) 항목 → 그 자리에서 MIN_WAGE_UNAVAILABLE(앞 항목 위반이 있어도 부분 반환 0)', () => {
    isUnavailable(sync(() => P.srvMinWageSlotViolations52({}, [{dateMs: kstMs(2028, 1, 1), wd: WDH(20000)}])), 2028, 'ABSENT');
    isUnavailable(sync(() => P.srvMinWageSlotViolations52({}, [{dateMs: kstMs(2027, 3, 2), wd: WDH(1)},
      {dateMs: kstMs(2028, 1, 1), wd: WDH(20000)}])), 2028, 'ABSENT');
  });
  await cell('MW-K07', '항목 업무가 없으면(wd undefined) 임금 확인 불가 위반 · workType null', () => {
    assert.deepStrictEqual(P.srvMinWageSlotViolations52({}, [{dateMs: kstMs(2027, 3, 2), wd: undefined}]),
      [{date: '2027-03-02', workType: null, reason: MSG_WAGE_UNKNOWN}]);
  });
  await cell('MW-K08', '여러 항목 위반을 모두 순서대로 모은다(시급 미달 · 통과 · 일급 미달)', () => {
    const out = P.srvMinWageSlotViolations52({}, [
      {dateMs: kstMs(2027, 3, 2), wd: WDH(10500)},
      {dateMs: kstMs(2027, 3, 3), wd: WDH(11000)},
      {dateMs: kstMs(2027, 3, 4), wd: {wageType: 'daily', wage: 80000, workType: '포장', startTime: '09:00',
        endTime: '18:00', breakMinutes: 60}},
    ]);
    assert.deepStrictEqual(out, [
      {date: '2027-03-02', workType: '피킹', reason: hourlyMsg(10500, 10700)},
      {date: '2027-03-04', workType: '포장', reason: dailyMsg(80000, 480, 10700)},
    ]);
  });

  console.log('\n[X] 트랜잭션 가드 — srvAssertAppPromiseMinWageInTx52');
  await cell('MW-X01', 'workDate 없음 → 판정하지 않음 · 읽기 0', async () => {
    const r = await txGuard(app27({workDate: DEL}));
    assert.strictEqual(r.err, null); assert.deepStrictEqual(r.reads, []);
  });
  await cell('MW-X02', 'workDate 가 Timestamp 가 아님(문자열) → 판정하지 않음 · 읽기 0', async () => {
    const r = await txGuard(app27({workDate: '2027-03-02'}));
    assert.strictEqual(r.err, null); assert.deepStrictEqual(r.reads, []);
  });
  await cell('MW-X03', '금액 없는 옛 기록(wage · snapshot.wage 없음) → 기존 동작 · 읽기 0', async () => {
    const r = await txGuard(app27({wage: DEL}));
    assert.strictEqual(r.err, null); assert.deepStrictEqual(r.reads, []);
  });
  await cell('MW-X04', '급여 형태 없음 · 금액 null → 판정하지 않음 · 읽기 0', async () => {
    for (const o of [{wageType: DEL}, {wage: null}]) {
      const r = await txGuard(app27(o));
      assert.strictEqual(r.err, null); assert.deepStrictEqual(r.reads, []);
    }
  });
  await cell('MW-X05', '미달(초대 수락) → MIN_WAGE_BELOW · 사유+초대 꼬리 · items · 트랜잭션 읽기 1(wage_config)', async () => {
    const r = await txGuard(app27());
    const e = r.err;
    assert.ok(e instanceof HttpsError, '거절되지 않았다');
    assert.strictEqual(e.code, 'failed-precondition');
    const reason = hourlyMsg(10500, 10700);
    assert.strictEqual(e.message, reason + TAIL_INVITE);
    assert.deepStrictEqual(e.details, {code: 'MIN_WAGE_BELOW', items: [{date: '2027-03-02', workType: '피킹', reason}],
      kind: 'INVITE_ACCEPT'});
    assert.deepStrictEqual(r.reads, [{tx: true, path: WCFG}]);
  });
  await cell('MW-X06', '다른 kind → 확정 꼬리 · details.kind 그대로', async () => {
    const r = await txGuard(app27(), 'APPLY_CONFIRM');
    assert.strictEqual(r.err.message, hourlyMsg(10500, 10700) + TAIL_OTHER);
    assert.strictEqual(r.err.details.kind, 'APPLY_CONFIRM');
  });
  await cell('MW-X07', '통과(10,700) → 반환 · 트랜잭션 읽기 1', async () => {
    const r = await txGuard(app27({wage: 10700}));
    assert.strictEqual(r.err, null); assert.deepStrictEqual(r.reads, [{tx: true, path: WCFG}]);
  });
  await cell('MW-X08', '지원서 필드 없으면 compensationSnapshot 값으로 판정(일급 80,000 · 2026 → 미달)', async () => {
    const r = await txGuard({workDate: at(kstMs(2026, 11, 20)), selectedWorkType: '피킹',
      compensationSnapshot: {wageType: 'daily', wage: 80000, startTime: '09:00', endTime: '18:00', breakMinutes: 60}});
    assert.strictEqual(r.err.details.code, 'MIN_WAGE_BELOW');
    assert.strictEqual(r.err.details.items[0].reason, dailyMsg(80000, 480, 10320));
  });
  await cell('MW-X09', '휴게는 snapshot 값이 지원서 값보다 먼저(60 → 480분 · 82,560 통과 — 0 이면 540분 미달)', async () => {
    const r = await txGuard({workDate: at(kstMs(2026, 11, 20)), wage: 82560, wageType: 'daily', startTime: '09:00',
      endTime: '18:00', breakMinutes: 0, compensationSnapshot: {breakMinutes: 60}});
    assert.strictEqual(r.err, null);
  });
  await cell('MW-X10', '2028 근무일 · 설정 없음 → MIN_WAGE_UNAVAILABLE(ABSENT)', async () => {
    isUnavailable((await txGuard(app27({workDate: at(kstMs(2028, 3, 2))}))).err, 2028, 'ABSENT');
  });
  await cell('MW-X11', '설정 손상(2027 = "x") → MIN_WAGE_UNAVAILABLE(CORRUPT)', async () => {
    isUnavailable((await txGuard(app27(), 'INVITE_ACCEPT', mw({'2027': 'x'}))).err, 2027, 'CORRUPT');
  });
  await cell('MW-X12', '[OBS] 일급 시작·종료 없음 → 판정 불가 사유가 MIN_WAGE_BELOW 코드로 나간다', async () => {
    const r = await txGuard(app27({wageType: 'daily', wage: 90000, startTime: DEL, endTime: DEL}));
    assert.strictEqual(r.err.details.code, 'MIN_WAGE_BELOW');
    assert.strictEqual(r.err.details.items[0].reason, MSG_WORK_UNKNOWN);
    obs('MW-X12', '판정 불가와 미달이 같은 code — 앱은 서버 문구만 표시(분기 0)');
  });

  console.log('\n[G] 급여 확정 경로 — 표만 공유 · 옛 선택식 유지(srvGetMinimumWage + 원문 설정 해석 조각)');
  await cell('MW-G01', '급여 확정 · 설정 없음 · 2026 → 10,320', () => {
    assert.strictEqual(payMin(2026, undefined), 10320);
  });
  await cell('MW-G02', '급여 확정 · 설정 없음 · 2027 → 10,700(표 공유 효과 · 옛 판 10,320)', () => {
    assert.strictEqual(payMin(2027, {}), 10700);
  });
  await cell('MW-G03', '급여 확정 · 내장 없는 해(2028 · 2030) → 최근 내장 10,700 대체(옛 판 10,320) — 공유 로더는 같은 해에 거절', async () => {
    assert.strictEqual(payMin(2028, {}), 10700);
    assert.strictEqual(payMin(2030, {}), 10700);
    isUnavailable((await load(2028)).err, 2028, 'ABSENT');
  });
  await cell('MW-G04', '급여 확정 · 표 밖 과거 해(2019) → 최근 내장 10,700', () => {
    assert.strictEqual(payMin(2019, {}), 10700);
  });
  await cell('MW-G05', '급여 확정 · 문서 2027 = 10,500 → 10,500 그대로(공유 선택은 10,700 하한) — 같은 정책 아님', () => {
    assert.strictEqual(payMin(2027, mw({'2027': 10500})), 10500);
    assert.deepStrictEqual(pick(2027, mw({'2027': 10500})), {wage: 10700, source: 'BUILTIN_FLOOR'});
  });
  await cell('MW-G06', '급여 확정 · 문서 "10800"(문자열) → 무시하고 내장 10,700(공유 선택은 CORRUPT)', () => {
    assert.strictEqual(payMin(2027, mw({'2027': '10800'})), 10700);
    assert.deepStrictEqual(pick(2027, mw({'2027': '10800'})), {wage: null, reason: 'CORRUPT'});
  });
  await cell('MW-G07', '급여 확정 · 문서 0 → 0(급여 확정의 기준>0 판정 생략 조건으로 감) · 공유 선택은 CORRUPT', () => {
    assert.strictEqual(payMin(2027, mw({'2027': 0})), 0);
    assert.deepStrictEqual(pick(2027, mw({'2027': 0})), {wage: null, reason: 'CORRUPT'});
  });
  await cell('MW-G08', '급여 확정 · 키 "2027x" → parseInt 로 2027 문서값 11,000(공유 선택은 정확 키만 → 10,700)', () => {
    assert.strictEqual(payMin(2027, mw({'2027x': 11000})), 11000);
    assert.deepStrictEqual(pick(2027, mw({'2027x': 11000})), {wage: 10700, source: 'BUILTIN'});
  });

  console.log('\n[R] 지원 제한 문구 — 원문 조각(P1 · 판정·기간 식 그대로)');
  const until = (o) => Object.assign({}, o.until !== undefined ? {restrictedUntil: at(o.until)} : {},
    o.src !== undefined ? {restrictionSource: o.src} : {});
  function denied(e, msg) {
    assert.ok(e instanceof HttpsError, '거절되지 않았다');
    assert.strictEqual(e.code, 'permission-denied');
    assert.strictEqual(e.message, msg);
  }
  const PERM = Date.UTC(9999, 0, 1) - KST;
  await cell('MW-R01', '제한 없음 → 통과', () => {
    NOW = T1;
    assert.strictEqual(restrict({}), null);
  });
  await cell('MW-R02', '지난 제한(1시간 전 · auto) → 통과', () => {
    NOW = T1;
    assert.strictEqual(restrict(until({until: T1 - HOUR, src: 'auto'})), null);
  });
  await cell('MW-R03', 'auto · 3일 → 무단 결근 문구(일수 그대로)', () => {
    NOW = T1;
    denied(restrict(until({until: T1 + 3 * DAY, src: 'auto'})), '무단 결근 페널티로 3일 동안 지원이 제한됩니다.');
  });
  await cell('MW-R04', 'manual · 3일 → 관리자 조치 문구', () => {
    NOW = T1;
    denied(restrict(until({until: T1 + 3 * DAY, src: 'manual'})), '관리자 조치로 3일 동안 지원이 제한됩니다.');
  });
  await cell('MW-R05', '출처 없음 · 그 밖("legacy" · "") → 출처를 단정하지 않는 문구', () => {
    NOW = T1;
    for (const o of [{until: T1 + 3 * DAY}, {until: T1 + 3 * DAY, src: 'legacy'}, {until: T1 + 3 * DAY, src: ''}]) {
      denied(restrict(until(o)), '3일 동안 지원이 제한됩니다.');
    }
  });
  await cell('MW-R06', 'permanent → 영구 문구', () => {
    NOW = T1;
    denied(restrict(until({until: T1 + 3 * DAY, src: 'permanent'})), '지원이 영구 제한된 계정입니다. 고객센터에 문의해 주세요.');
  });
  await cell('MW-R07', '해제 시각 ≥ KST 9999-01-01 00:00 → 출처가 auto 여도 영구 문구', () => {
    NOW = T1;
    denied(restrict(until({until: PERM, src: 'auto'})), '지원이 영구 제한된 계정입니다. 고객센터에 문의해 주세요.');
  });
  await cell('MW-R08', '영구 경계 1ms 전 · auto → 일수 문구(올림 일수)', () => {
    NOW = T1;
    const n = Math.ceil((PERM - 1 - T1) / DAY);
    denied(restrict(until({until: PERM - 1, src: 'auto'})), `무단 결근 페널티로 ${n}일 동안 지원이 제한됩니다.`);
  });
  await cell('MW-R09', '일수는 올림(1.2일 → 2일)', () => {
    NOW = T1;
    denied(restrict(until({until: T1 + 1.2 * DAY, src: 'auto'})), '무단 결근 페널티로 2일 동안 지원이 제한됩니다.');
  });
  await cell('MW-R10', '[S] 일수 올림 식 원문 1회 · 제한 블록이 공고 읽기·트랜잭션보다 앞(거절 = 쓰기 전)', () => {
    const ap = bodyOf('callableApplyToTO');
    const re = /const remainDays = Math\.ceil\(\s*\(restrictedUntilTs\.toDate\(\)\.getTime\(\) - Date\.now\(\)\) \/ \(1000 \* 60 \* 60 \* 24\)\s*\);/g;
    assert.strictEqual((ap.match(re) || []).length, 1);
    const r0 = ap.indexOf('const restrictedUntilTs = userData["restrictedUntil"]');
    const t0 = ap.indexOf('const toSnap = await db.collection("tos").doc(toId).get();');
    const x0 = ap.indexOf('await db.runTransaction(');
    assert.ok(r0 > 0 && r0 < t0 && t0 < x0, [r0, t0, x0].join(','));
  });

  console.log('\n[D] 지원 트랜잭션 삭제 공고 재확인 — 원문 조각(P2)');
  await cell('MW-D01', '공고 정상 → 통과 · 트랜잭션 읽기 1(공고 문서)', async () => {
    const {reads, tx} = delTx({isDeleted: false, status: 'ACTIVE'});
    assert.strictEqual(await DG.__delGuard(tx, {path: 'tos/t1'}), 'PASS');
    assert.deepStrictEqual(reads, ['tos/t1']);
  });
  await cell('MW-D02', '공고 문서 없음 → not-found "삭제된 공고입니다."', async () => {
    const e = await aw(DG.__delGuard(delTx(undefined).tx, {path: 'tos/t1'}));
    assert.ok(e instanceof HttpsError); assert.strictEqual(e.code, 'not-found'); assert.strictEqual(e.message, '삭제된 공고입니다.');
  });
  await cell('MW-D03', 'isDeleted true → not-found "삭제된 공고입니다."', async () => {
    const e = await aw(DG.__delGuard(delTx({isDeleted: true}).tx, {path: 'tos/t1'}));
    assert.ok(e instanceof HttpsError); assert.strictEqual(e.code, 'not-found'); assert.strictEqual(e.message, '삭제된 공고입니다.');
  });
  await cell('MW-D04', '[OBS] isDeleted "true"(문자열) → 통과(엄격 비교 · 트랜잭션 밖 검사와 같은 식)', async () => {
    assert.strictEqual(await DG.__delGuard(delTx({isDeleted: 'true'}).tx, {path: 'tos/t1'}), 'PASS');
    assert.ok(bodyOf('callableApplyToTO').includes('if (toData["isDeleted"] === true) {'));
  });

  console.log('\n[S] 원문 순서·소비처');
  await cell('MW-S01', '초대 수락 tx 순서 — CONFIRMED 반환 < INVITED 검사 < 기한 재확인 < 최저임금 재판정 < 시작 가드 < 첫 쓰기 · 호출 1', () => {
    const acc = bodyOf('callableAcceptTOInvitation');
    const t0 = acc.indexOf('const fresh = await tx.get(appRef);');
    assert.ok(t0 > 0 && acc.indexOf('const fresh = await tx.get(appRef);', t0 + 1) < 0, '수락 tx 시작 표지 1');
    const at0 = (s) => { const i = acc.indexOf(s, t0); assert.ok(i > t0, '없음: ' + s); return i; };
    const a = [at0('if (freshStatus === "CONFIRMED") return;'), at0('if (freshStatus !== "INVITED")'),
      at0('const freshExp ='), at0('await srvAssertAppPromiseMinWageInTx52(tx, freshData, "INVITE_ACCEPT");'),
      at0('// [INVITE-START-GUARD]'), firstWriteAfter(acc, t0)];
    for (let k = 1; k < a.length; k++) assert.ok(a[k - 1] < a[k], a.join(','));
    assert.strictEqual(acc.split('srvAssertAppPromiseMinWageInTx52(').length - 1, 1);
    assert.strictEqual(SRC.split('srvAssertAppPromiseMinWageInTx52(').length - 1, 2, '선언 1 + 호출 1(승인·확정 호출 자리 0)');
  });
  await cell('MW-S02', '지원 tx 순서 — freeze < 지원서 재확인 < 사업장 종료 < 삭제 공고 재확인 < 마감·정원 재확인 < 첫 쓰기', () => {
    const ap = bodyOf('callableApplyToTO');
    const s0 = ap.indexOf('await db.runTransaction(async (tx) => {');
    assert.ok(s0 > 0 && ap.indexOf('await db.runTransaction(', s0 + 1) < 0, '지원 tx 1');
    const at0 = (s) => { const i = ap.indexOf(s, s0); assert.ok(i > s0, '없음: ' + s); return i; };
    const b = [at0('await srvAssertAccountNotFrozenInTx(tx, uid, "사용자");'), at0('const existingInTx = await tx.get(appRef);'),
      at0('if (srvBizClosedForNewCommitment(applyTxBizSnap)) {'), at0('const txToSnap = await tx.get(toRef);'),
      at0('// TOCTOU 방지: 트랜잭션 내 최종 마감·정원 재검증'), firstWriteAfter(ap, s0)];
    for (let k = 1; k < b.length; k++) assert.ok(b[k - 1] < b[k], b.join(','));
    assert.strictEqual(SRC.split('const txToSnap = await tx.get(toRef);').length - 1, 1);
  });
  await cell('MW-S03', '공유 helper 소비처 4(지원 · 초대 발송 · 대체근무 제안 · 재배치 제안) — 각 본문에 로더·판정식 정확 1회', () => {
    assert.strictEqual(SRC.split('await srvLoadMinimumWage(').length - 1, 4);
    for (const n of ['callableApplyToTO', 'callableInviteWorker', 'callableOfferAlternativeWork',
      'callableProposeConfirmedReassignment']) {
      const b = bodyOf(n);
      assert.strictEqual(b.split('await srvLoadMinimumWage(').length - 1, 1, n);
      assert.strictEqual(b.split('srvValidateMinimumWagePromise({').length - 1, 1, n);
    }
  });
  await cell('MW-S04', '선언 모양 = .75 배포판(BOOT-6) — 지원·초대 수락 선언에 maxInstances: 20 정확 1회(M2)', () => {
    for (const n of ['callableApplyToTO', 'callableAcceptTOInvitation']) {
      assert.ok(SRC.includes(`export const ${n} = onCall(\n  {region: "asia-northeast3", enforceAppCheck: true, maxInstances: 20},\n`), n);
      assert.strictEqual(bodyOf(n).slice(0, 200).split('maxInstances').length - 1, 1, n);
    }
  });
  await cell('MW-S05', '급여 확정은 옛 선택식(srvGetMinimumWage) 유지 · 공유 선택 helper 미사용', () => {
    const w = bodyOf('callableCalculateAndConfirmWage');
    assert.strictEqual(SRC.split('srvGetMinimumWage(workYear2, fsMinWages)').length - 1, 1);
    assert.ok(w.includes('srvGetMinimumWage(workYear2, fsMinWages)'));
    assert.strictEqual(SRC.split('function srvGetMinimumWage(').length - 1, 1);
    assert.ok(!w.includes('srvMinWageFromCfg52('));
    assert.ok(!w.includes('srvLoadMinimumWage('));
  });
  await cell('MW-S06', '날짜 라벨은 위반 항목 date 에만(선언 1 + 사용 1)', () => {
    assert.strictEqual(SRC.split('srvKstDateKey52(').length - 1, 2);
    assert.ok(SRC.includes('if (v) out.push({date: srvKstDateKey52(e.dateMs), workType: w.workType ?? null, reason: v});'));
  });
  await cell('MW-S07', '[OBS] 위반 수집 helper 의 형태 기본값 "hourly" — 유일 호출(초대 수락)은 형태 없으면 먼저 반환(도달 0)', () => {
    assert.ok(SRC.includes('wageType: String(w.wageType ?? "hourly")'));
    assert.strictEqual(SRC.split('srvMinWageSlotViolations52(').length - 1, 2, '선언 1 + 호출 1');
    assert.ok(SRC.includes('if (w.wage === undefined || w.wage === null || !w.wageType) return;'));
  });

  await cell('MW-S08', '[S] 급여 확정 writer 저장 필드 대응 — 기준(minimumWage2) → srvWageCalculate → wageDetail.appliedMinimumWage · appliedSupplementWage(일급 = max(통상, 기준))', () => {
    const w = bodyOf('callableCalculateAndConfirmWage');
    assert.ok(w.includes('const minimumWage2 = srvGetMinimumWage(workYear2, fsMinWages);'));
    assert.ok(w.includes('minimumWage: minimumWage2,'), '계산 입력이 기준을 받지 않는다');
    assert.ok(w.includes('appliedMinimumWage: wageResult2.appliedMinimumWage,'), '저장 필드 대응이 없다');
    const calc = sliceOnce(SRC, 'function srvWageCalculate(p: {', 'function srvApplyEmpIncomeTax(', 'CALC');
    assert.ok(calc.includes('appliedMinimumWage: p.minimumWage, appliedSupplementWage,'));
    assert.ok(calc.includes('appliedSupplementWage = p.baseHourlyWage ?? Math.max(rawOrd, p.minimumWage);'));
  });

  console.log('\n[A] 초대 수락 callable — 원문 폐포 · 가짜 Firestore(P3)');
  await cell('MW-A01', '금액 없는 옛 초대(기존 SEED) → 수락 성공 · wage_config 읽기 0(가드 조기 반환)', async () => {
    seedInvite({});
    const out = await callInvite(INV_REQ(INV2));
    await settle();
    assert.strictEqual(out && out.success, true);
    assert.strictEqual(F.get(INV_PATH).status, 'CONFIRMED');
    assert.strictEqual(anyReadsOf(WCFG), 0);
    BASE_PROJ = proj();
  });
  await cell('MW-A02', '금액 통과(12,000 시급 · 2026) → 성공 · tx 안 wage_config 읽기 1 · 결과 상태 = A01(금액 필드 제외) · 카운터 이동', async () => {
    assert.ok(BASE_PROJ, 'A01 기준이 없다');
    seedInvite({wage: 12000, wageType: 'hourly'});
    const out = await callInvite(INV_REQ(INV2));
    await settle();
    assert.strictEqual(out && out.success, true);
    assert.strictEqual(txReadsOf(WCFG), 1);
    assert.strictEqual(anyReadsOf(WCFG), 1);
    assert.deepStrictEqual(proj(), BASE_PROJ, '가드 통과가 쓰기 결과를 바꿨다');
    const a = F.get(INV_PATH);
    assert.strictEqual(a.status, 'CONFIRMED');
    assert.strictEqual(a.wage, 12000);
    const to = F.get('tos/t1');
    const s = F.get(SLOT_PATH);
    assert.deepStrictEqual([to.totalConfirmed, to.totalPending], [1, 0]);
    assert.deepStrictEqual(s.workDetailCounts['wd-1'], {confirmedCount: 1, pendingCount: 0});
  });
  async function belowCase(label, appOver, cfgDoc, reason, date) {
    seedInvite(appOver);
    if (cfgDoc !== undefined) cfgPut(cfgDoc);
    const before = F.dump();
    const e = await rejectsWith(callInvite(INV_REQ(INV2)), 'failed-precondition', 'MIN_WAGE_BELOW');
    assert.strictEqual(e.message, reason + TAIL_INVITE);
    assert.deepStrictEqual(e.details, {code: 'MIN_WAGE_BELOW', items: [{date, workType: '피킹', reason}], kind: 'INVITE_ACCEPT'});
    assertNoWrites(label);
    assert.deepStrictEqual(F.dump(), before, label + ': 저장소가 바뀌었다');
    assert.strictEqual(F.get(INV_PATH).status, 'INVITED');
    assert.strictEqual(txReadsOf(WCFG), 1);
    return e;
  }
  async function unavailableCase(label, appOver, cfgDoc, year, reason) {
    seedInvite(appOver);
    if (cfgDoc !== undefined) cfgPut(cfgDoc);
    const before = F.dump();
    const e = await rejectsWith(callInvite(INV_REQ(INV2)), 'failed-precondition', 'MIN_WAGE_UNAVAILABLE');
    isUnavailable(e, year, reason);
    assertNoWrites(label);
    assert.deepStrictEqual(F.dump(), before, label + ': 저장소가 바뀌었다');
    assert.strictEqual(F.get(INV_PATH).status, 'INVITED');
  }
  await cell('MW-A03', '미달(10,000 시급 · 2026 10,320) → MIN_WAGE_BELOW · kind INVITE_ACCEPT · 쓰기 0 · 저장소 그대로 · INVITED 유지', async () => {
    await belowCase('A03', {wage: 10000, wageType: 'hourly'}, undefined, hourlyMsg(10000, 10320), '2026-11-20');
  });
  await cell('MW-A04', '근무일 2028 · 설정 없음 → MIN_WAGE_UNAVAILABLE(ABSENT · 2028) · 쓰기 0', async () => {
    await unavailableCase('A04', {wage: 12000, wageType: 'hourly', workDate: at(kst(2028, 3, 2))}, undefined, 2028, 'ABSENT');
  });
  await cell('MW-A05', '설정 손상(2026 = "10320" 문자열) → MIN_WAGE_UNAVAILABLE(CORRUPT) · 쓰기 0', async () => {
    await unavailableCase('A05', {wage: 12000, wageType: 'hourly'}, mw({'2026': '10320'}), 2026, 'CORRUPT');
  });
  await cell('MW-A06', '설정 2026 = 9,000(고시 아래) → 고시 10,320 으로 판정 · 10,000 미달', async () => {
    await belowCase('A06', {wage: 10000, wageType: 'hourly'}, mw({'2026': 9000}), hourlyMsg(10000, 10320), '2026-11-20');
  });
  await cell('MW-A07', '설정 2026 = 12,500(고시 위) → 문서값으로 판정 · 12,000 미달', async () => {
    await belowCase('A07', {wage: 12000, wageType: 'hourly'}, mw({'2026': 12500}), hourlyMsg(12000, 12500), '2026-11-20');
  });
  await cell('MW-A08', '근무일 KST 2027-01-01 00:00 · 10,500 → 2027 기준 10,700 미달 · 라벨 2027-01-01', async () => {
    await belowCase('A08', {wage: 10500, wageType: 'hourly', workDate: at(kst(2027, 1, 1))}, undefined,
      hourlyMsg(10500, 10700), '2027-01-01');
  });
  await cell('MW-A09', '이미 CONFIRMED(트랜잭션 밖 판정) + 미달 금액 → alreadyConfirmed · 쓰기 0 · wage_config 읽기 0(멱등)', async () => {
    seedInvite({status: 'CONFIRMED', confirmedAt: at(T0), documentAccessConsentGiven: true,
      documentAccessConsentVersion: INV2, documentAccessConsentAt: at(T0), wage: 1, wageType: 'hourly'});
    const before = F.dump();
    const out = await callInvite(INV_REQ(INV2));
    await settle();
    assert.deepStrictEqual(out, {success: true, alreadyConfirmed: true});
    assertNoWrites('완료 no-op');
    assert.deepStrictEqual(F.dump(), before);
    assert.strictEqual(anyReadsOf(WCFG), 0);
  });
  await cell('MW-A10', 'tx 안 기한 재확인이 최저임금 재판정보다 먼저 — 그 사이 만료 → 만료 문구(MIN_WAGE 아님) · wage_config 읽기 0 · 쓰기 0', async () => {
    seedInvite({wage: 10000, wageType: 'hourly'});
    const before = F.dump();
    F.hooks.afterGet = (p, txId) => {
      if (txId && p === INV_PATH) NOW = WORK_DAY + 9 * HOUR; // = inviteExpiresAt
    };
    const e = await rejectsWith(callInvite(INV_REQ(INV2)), 'failed-precondition');
    assert.strictEqual(e.message, '초대 수락 가능 시간이 지났습니다.');
    assert.ok(!e.details || !/^MIN_WAGE_/.test(String(e.details.code)), 'MIN_WAGE 로 분류했다');
    assert.strictEqual(anyReadsOf(WCFG), 0);
    assertNoWrites('tx 안 만료');
    assert.deepStrictEqual(F.dump(), before);
  });
  await cell('MW-A11', '[OBS] 일급 · 시작·종료 없음 → MIN_WAGE_BELOW(사유 = 소정근로시간 확인 불가) · 쓰기 0', async () => {
    seedInvite({wage: 90000, wageType: 'daily', startTime: DEL, endTime: DEL});
    const before = F.dump();
    const e = await rejectsWith(callInvite(INV_REQ(INV2)), 'failed-precondition', 'MIN_WAGE_BELOW');
    assert.strictEqual(e.details.items[0].reason, MSG_WORK_UNKNOWN);
    assertNoWrites('A11');
    assert.deepStrictEqual(F.dump(), before);
  });
  await cell('MW-A12', '[OBS · F178-MW-NAN-TIME] 일급 1원 · 시작 "xx:yy" → 가드 통과 → 수락 성공(정확 말단: error 0 · {success:true} · CONFIRMED · 임금·시각 보존 · 카운터 이동 · 가드 읽기 1)', async () => {
    // 기대 근거(원문): 가드 뒤 시작 가드는 슬롯 업무 시각(09:00)을 쓰고, tx 안 겹침 재검증은 확정 근무가 없으면 비교 0 —
    //   'xx:yy' 를 해석하는 다른 판정이 없다. 그래서 정확 결과는 '성공'이다(그 밖 결과면 이 셀 실패 = 원문 분류 대상).
    seedInvite({wage: 1, wageType: 'daily', startTime: 'xx:yy'});
    let err = null;
    let out = null;
    try {
      out = await callInvite(INV_REQ(INV2));
    } catch (e) {
      err = e;
    }
    await settle();
    assert.strictEqual(err, null, '수락이 실패했다: ' + (err && `${err.code} ${err.message}`));
    assert.deepStrictEqual(out, {success: true});
    assert.strictEqual(txReadsOf(WCFG), 1, '가드가 돌지 않았다');
    const a = F.get(INV_PATH);
    assert.strictEqual(a.status, 'CONFIRMED');
    assert.strictEqual(a.wage, 1);
    assert.strictEqual(a.wageType, 'daily');
    assert.strictEqual(a.startTime, 'xx:yy', '저장 시각이 바뀌었다');
    assert.strictEqual(a.endTime, '18:00');
    const to = F.get('tos/t1');
    const s = F.get(SLOT_PATH);
    assert.deepStrictEqual([to.totalConfirmed, to.totalPending], [1, 0]);
    assert.deepStrictEqual(s.workDetailCounts['wd-1'], {confirmedCount: 1, pendingCount: 0});
    obs('MW-A12', '판정 불가(NaN) 일급 1원이 callable 수준에서 확정된다 — F178-MW-NAN-TIME OPEN(parser 수정 0)');
  });

  console.log('\n[AP] 지원 callable — 원문 폐포 · 가짜 Firestore(P1 · P2 · 공유 로더의 실제 writer)');
  await cell('MW-AP01', '지원 정상(2026 · 12,000 시급) → PENDING · 저장 약속 필드 보존(wage · wageType · 휴게 · 통상시급 mode · 근태 기준 · 시각 · 근무일) · 대기 +1 · tx 안 공고 재읽기', async () => {
    seedApply();
    const out = await callApply(APPLY_REQ());
    await settle();
    assert.deepStrictEqual(out, {success: true, applicationId: APPLY_ID, isReactivation: false});
    const a = F.get(appPath(APPLY_ID));
    assert.ok(a, '지원서가 없다');
    assert.strictEqual(a.status, 'PENDING');
    assert.strictEqual(a.wage, 12000);
    assert.strictEqual(a.wageType, 'hourly');
    assert.strictEqual(a.breakMinutes, 60);
    assert.strictEqual(a.baseHourlyWageMode, 'AUTO');
    assert.strictEqual(a.startTime, '09:00');
    assert.strictEqual(a.endTime, '18:00');
    assert.strictEqual(ms(a.workDate), WORK_DAY);
    assert.strictEqual(a.attendancePolicySnapshot && a.attendancePolicySnapshot.policySource, 'ALFIT_DEFAULT');
    assert.strictEqual(F.get(TO_PATH).totalPending, 1);
    assert.strictEqual(F.get(SLOT_PATH).workDetailCounts['wd-1'].pendingCount, 1);
    assert.ok(W.reads.some((r) => r.tx !== null && r.path === TO_PATH), 'tx 안 공고 재읽기 0');
    assert.strictEqual(anyReadsOf(WCFG), 1, '공유 로더 설정 읽기 1(tx 밖)');
    assert.strictEqual(txReadsOf(WCFG), 0);
  });
  await cell('MW-AP02', 'P2 — 사전 읽기 뒤 공고 삭제(isDeleted true) → tx 재확인 not-found "삭제된 공고입니다." · 쓰기 0 · 지원서 없음 · 카운터 그대로', async () => {
    seedApply();
    const before = F.dump();
    afterFirstOuterRead(TO_PATH, () => F.put(TO_PATH, Object.assign(F.get(TO_PATH), {isDeleted: true})));
    const e = await rejectsWith(callApply(APPLY_REQ()), 'not-found');
    assert.strictEqual(e.message, '삭제된 공고입니다.');
    assertNoWrites('AP02');
    sameExceptTo(before, 'AP02');
    assert.ok(!F.has(appPath(APPLY_ID)));
    assert.ok(W.reads.some((r) => r.tx !== null && r.path === TO_PATH), 'tx 재확인 읽기가 없다');
    assert.strictEqual(F.get(TO_PATH).totalPending, 0);
  });
  await cell('MW-AP03', 'P2 — 사전 읽기 뒤 공고 문서 자체 삭제 → tx 재확인 not-found · 쓰기 0', async () => {
    seedApply();
    const before = F.dump();
    afterFirstOuterRead(TO_PATH, () => F.del(TO_PATH));
    const e = await rejectsWith(callApply(APPLY_REQ()), 'not-found');
    assert.strictEqual(e.message, '삭제된 공고입니다.');
    assertNoWrites('AP03');
    sameExceptTo(before, 'AP03');
    assert.ok(!F.has(appPath(APPLY_ID)));
  });
  await cell('MW-AP04', '대조 — 호출 전에 이미 삭제(isDeleted) → 트랜잭션 밖 같은 문구 · 트랜잭션 0 · 쓰기 0', async () => {
    seedApply({to: {isDeleted: true}});
    const before = F.dump();
    const e = await rejectsWith(callApply(APPLY_REQ()), 'not-found');
    assert.strictEqual(e.message, '삭제된 공고입니다.');
    assert.strictEqual(W.commits.length + W.aborts.length, 0, '트랜잭션이 열렸다');
    assertNoWrites('AP04');
    assert.deepStrictEqual(F.dump(), before);
  });
  await cell('MW-AP05', 'P1 — 지원 제한(auto · 3일) → callable 수준 permission-denied 문구 · 공고 읽기 0 · 쓰기 0', async () => {
    seedApply({worker: {restrictedUntil: at(T1 + 3 * DAY), restrictionSource: 'auto'}});
    const before = F.dump();
    const e = await rejectsWith(callApply(APPLY_REQ()), 'permission-denied');
    assert.strictEqual(e.message, '무단 결근 페널티로 3일 동안 지원이 제한됩니다.');
    assert.strictEqual(anyReadsOf(TO_PATH), 0, '제한 판정 전에 공고를 읽었다');
    assertNoWrites('AP05');
    assert.deepStrictEqual(F.dump(), before);
  });
  await cell('MW-AP06', '공유 판정식 — 공고 임금 10,000 시급(2026 10,320) → failed-precondition 미달 문구 · 트랜잭션 0 · 쓰기 0', async () => {
    seedApply({slot: {workDetails: WDS_WITH({wage: 10000})}});
    const before = F.dump();
    const e = await rejectsWith(callApply(APPLY_REQ({wage: 10000})), 'failed-precondition');
    assert.strictEqual(e.message, hourlyMsg(10000, 10320));
    assert.strictEqual(W.commits.length + W.aborts.length, 0);
    assertNoWrites('AP06');
    assert.deepStrictEqual(F.dump(), before);
  });
  await cell('MW-AP07', '공유 로더 — 근무일 2028 · 설정 없음 → MIN_WAGE_UNAVAILABLE(ABSENT) · 트랜잭션 0 · 쓰기 0', async () => {
    const d28 = kst(2028, 3, 2);
    seedApply({slot: {date: at(d28)}});
    const before = F.dump();
    const e = await rejectsWith(callApply(APPLY_REQ({workDateMs: d28})), 'failed-precondition', 'MIN_WAGE_UNAVAILABLE');
    isUnavailable(e, 2028, 'ABSENT');
    assert.strictEqual(W.commits.length + W.aborts.length, 0);
    assertNoWrites('AP07');
    assert.deepStrictEqual(F.dump(), before);
  });

  console.log('\n[Z] 접촉');
  await cell('MW-Z01', '외부 진입 0 · 관대 스텁 접촉 0 · 묶지 못한 비전역 이름 0 · 새 helper 가 수락 폐포에 있다', () => {
    assert.deepStrictEqual(R5_NET, []);
    assert.deepStrictEqual(EXT_WARN, []);
    assert.deepStrictEqual(F.EXT_TOUCHED.slice(0, 10), []);
    assert.deepStrictEqual(UNRESOLVED_NON_GLOBAL, []);
    for (const n of ['srvAssertAppPromiseMinWageInTx52', 'srvMinWageSlotViolations52', 'srvMinWageFromCfg52',
      'srvKstDateKey52', 'srvMinWageUnavailableError52', 'srvValidateMinimumWagePromise', 'SRV_MINIMUM_WAGE_BY_YEAR']) {
      assert.ok(NEED.has(n), `폐포에 ${n} 없음`);
    }
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
