/**
 * [SRV-BC r2 · 판정178 §4 · 판정180 §5 보완] 운영 종료 사업장 가드(BUSINESS_CLOSED) 별도 검증 — 현 가드 **같은 바이트**를 원문 그대로 실행한다.
 *
 *   대상(가드 삭제 · 소스 fork · 시험 완화 0): A functions/src/index.ts 의
 *     G1 srvBizClosedForNewCommitment · G2 srvAssertBizOpenInTx · G3 ARCHIVE_NEW_WORK_MESSAGE
 *     G4 callableApplyToTO 트랜잭션 안 사업장 종료 판정 블록 · G5 callableAcceptConfirmedReassignment 트랜잭션 첫 문장
 *   다섯 조각 fullSHA 는 A(b9b39ec3)와 .75 정합 후보(3dd19e09)에서 같다(../out/guard_bytes.json) — BC-G01 이 실행 때 다시 본다.
 *   실행 순서(판정180 §5): 허용된 MW LOCAL 성공 뒤 **그 성공 상태(index.ts = 3dd19e09 · mw_local_done.json 핀)** 에서 직렬 실행.
 *
 *   하네스: 60–701행은 consent_r4d_callables.test.js(f419329d…)와 같고 **두 줄만** 다르다(빌더가 단언):
 *     ROOTS 에 callableApplyToTO 추가 · WANT_CONSTS 에 srvAttendancePolicyFingerprint · ARCHIVE_NEW_WORK_MESSAGE 추가.
 *   같은 가짜 Firestore(consent_r4d_fakestore · 재시도 없음 A8) — 트랜잭션 재시도는 이 파일의 감싸기(withRetryOnce)가
 *   '첫 커밋 직전 경합(ABORTED 10) → 버퍼 폐기 → 콜백 다시 실행' 으로 흉내 낸다(시험 seam · 실 SDK 경합·잠금·백오프 검증 아님).
 *
 *   사례: 문서 없음 / deactivatedAt(Timestamp · 문자열 · true · null) / 정상 운영 / 사전 검사 뒤 종료 · 삭제 / tx 재시도(종료 · 경합만) /
 *         중복 · 이미 확정 · 초대 · 재지원 / 이미 수락 · 종결 제안 · 만료 · 대상 불가 우선순위 / 관리자(주입 실행 단언) · 서브관리자
 *         (운영/종료 seed 쌍) · 다른 근로자 권한 / 다른 확정 근무 · 계약 · 카운터 · 알림 보존 / 거절 쓰기 0 / 원문 순서 · 가드 바이트 /
 *         외부 · 관대 스텁 접촉 0.
 *   [OBS] 는 원문 순서의 진단 기대다 — 실행 관측 · 운영정책 승인 · 잔여 종결이 아니다(예: 종료가 만료·대상 정리보다 먼저라 제안 PROPOSED 잔류).
 *   셀 실패는 원문(시험 · seed · 제품)으로 분류한다 — 이 파일이 원인을 스스로 정하지 않는다.
 *
 *   실행(판정 전 실행 0): cd functions && node --test --test-concurrency=1 --test-reporter=tap test/bc_guard_verify_r2.test.js
 *   성공 = 마지막 줄 '통과 33 / 실패 0' · rc 0 · '[r5 차단]' 0. 입력: ../src/*.ts · ./consent_r4d_fakestore · node_modules/typescript.
 *   네트워크 · 실제 Firestore · 에뮬레이터 · DEV 0. 쓰기 0(메모리 가짜 저장소만).
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
  'srvAttendancePolicyFingerprint', 'ARCHIVE_NEW_WORK_MESSAGE'];
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

// ════════════════════════════════════════════════════════════════════════════
// [SRV-BC r2] 여기부터 이 파일의 몫 — 위 60–701행은 consent_r4d_callables.test.js 와 같다(ROOTS · WANT_CONSTS 두 줄만 다름).
//   r1(c6fe2284 · 보존) 대비: BC-A11 실제 종료 seed 쌍 · 주입 실행 단언 / BC-R09 정리 보장 문구 삭제 / BC-Z01 접촉 0 단언.
// ════════════════════════════════════════════════════════════════════════════
const GUARD_SHA = {
  G1_srvBizClosedForNewCommitment: '2dccca6cab97533c350a624a4c5f9c6df239f3d704c1ae3c14c2f2b8983a3eed',
  G2_srvAssertBizOpenInTx: '9b855c4cb90b9374c005852dd5e6e5164b16efff85982594563af708182c1814',
  G3_ARCHIVE_NEW_WORK_MESSAGE: '4c69586305243a69a20f8de624bd586b95467ed1effea82dbe4f5e84a8fe02f5',
  G4_apply_tx_guard: '23db3084a98134a6af56516f76bc8fb78ba1be409305ea93e6946a9b374fef5b',
  G5_reassign_tx_guard: '772115bdfbeee7b2dc6bde90c61a0d35e1cc76ece4ff64b2cdbc9c2ac79d04fe',
};
const GUARD_PIECES = [
  ['G1_srvBizClosedForNewCommitment', 'function srvBizClosedForNewCommitment(', 'fn'],
  ['G2_srvAssertBizOpenInTx', 'async function srvAssertBizOpenInTx(', 'fn'],
  ['G3_ARCHIVE_NEW_WORK_MESSAGE', 'const ARCHIVE_NEW_WORK_MESSAGE =', 'semi'],
  ['G4_apply_tx_guard', 'const applyTxBizSnap =', 'const applyTxRules ='],
  ['G5_reassign_tx_guard', '// [ARCHIVE-WRITER-FENCE] 재배치 수락은 새 업무 단위에 CONFIRMED 를 만든다',
    'const [freshP, freshSrc, freshTarget, freshTo, freshSlot, freshUser] ='],
];
function guardCut(start, rule) {
  const a = SRC.indexOf(start);
  assert.ok(a >= 0 && SRC.indexOf(start, a + 1) < 0, '시작 표지 1회 아님: ' + start.slice(0, 40));
  if (rule === 'fn') return SRC.slice(a, SRC.indexOf('\n}\n', a) + 2);
  if (rule === 'semi') return SRC.slice(a, SRC.indexOf(';', a) + 1);
  const b = SRC.indexOf(rule, a);
  assert.ok(b > a, '끝 표지 없음: ' + rule.slice(0, 40));
  return SRC.slice(a, b);
}
function bodyOf(name) {
  const head = `export const ${name} = onCall(`;
  const i = SRC.indexOf(head);
  assert.ok(i >= 0 && SRC.indexOf(head, i + 1) < 0, `${name} 머리가 정확히 1개가 아니다`);
  const j = SRC.indexOf('\nexport const ', i + 10);
  return SRC.slice(i, j < 0 ? SRC.length : j);
}

const BIZ = 'businesses/b1';
const APPLY_ID = 't1_s1_wd-1_w1';
const MSG_APPLY_CLOSED = '운영을 종료한 사업장에는 지원할 수 없습니다.';
const MSG_WORK_CLOSED = '운영을 종료한 사업장에서는 새 근무 약속을 만들 수 없습니다.';
const MSG_NOT_ACCEPTING = '지금은 지원을 받지 않는 공고예요.\n잠시 후 다시 확인해주세요.';
const APPLY_REQ = (o = {}) => over({toId: 't1', slotId: 's1', businessId: 'b1', businessName: '테스트사업장',
  toTitle: '물류 센터 단기', workDateMs: WORK_DAY, selectedWorkType: '피킹', workDetailId: 'wd-1',
  startTime: '09:00', endTime: '18:00', wage: 12000, idCardConsentGiven: true,
  documentAccessConsentGiven: true, documentAccessConsentVersion: V4,
  expectedAttendancePolicy: R.srvAttendancePolicyFingerprint(SEED.business().attendanceRules)}, o);
function seedApply(o = {}) {
  F.reset();
  NOW = o.now !== undefined ? o.now : T1;
  seedBase();
  if (o.worker) F.put('users/w1', SEED.worker(o.worker));
  if (o.biz) F.put(BIZ, SEED.business(o.biz));
  F.put('tos/t1', SEED.to(Object.assign({isPublished: true}, o.to || {})));
  F.put(SLOT_PATH, SEED.slot(o.slot || {}));
  for (const [p, d] of o.extra || []) F.put(p, d);
  F.clearLog();
}
const callApply = (data, uid = 'w1') => R.callableApplyToTO({auth: {uid}, data});
/** 트랜잭션 밖 첫 읽기 직후 한 번 — '사전 검사 뒤, 트랜잭션 전' 에 다른 writer 가 커밋한 상황. */
function afterFirstOuterRead(path, fn) {
  F.hooks.afterGet = (p, txId) => {
    if (txId === null && p === path) {
      F.hooks.afterGet = null;
      fn();
    }
  };
}
/** 트랜잭션 안 첫 읽기 직후 한 번 — 트랜잭션이 읽기 시작한 시점에 이미 커밋돼 있던 다른 writer 의 결과. */
function afterFirstTxRead(path, fn) {
  F.hooks.afterGet = (p, txId) => {
    if (txId !== null && p === path) {
      F.hooks.afterGet = null;
      fn();
    }
  };
}
const closeBiz = (v) => () => F.put(BIZ, Object.assign(F.get(BIZ), {deactivatedAt: v}));
/** 시그니처 경로를 쓰는 트랜잭션의 첫 커밋 직전에 mutate → ABORTED(10) → 콜백 재실행(SDK 재시도 흉내). */
function withRetryOnce(sigPath, mutate) {
  const orig = F.db.runTransaction;
  const st = {injected: false, attempts: 0};
  F.db.runTransaction = async (cb) => {
    for (let k = 0; k < 5; k++) {
      let mine = false;
      F.hooks.beforeCommit = (txId, buf) => {
        if (!st.injected && buf.some((w) => w.path === sigPath)) {
          st.injected = true;
          mine = true;
          mutate();
          throw Object.assign(new Error('ABORTED: 주입된 경합'), {code: 10});
        }
      };
      st.attempts++;
      try {
        return await orig(cb);
      } catch (e) {
        if (!mine) throw e;
      } finally {
        F.hooks.beforeCommit = null;
      }
    }
    throw new Error('재시도 한도');
  };
  st.restore = () => { F.db.runTransaction = orig; };
  return st;
}
/** 사업장 문서만 바뀌고(주입) 그 밖 저장소는 그대로인지. */
function sameExceptBiz(before, label) {
  const now = F.dump();
  const b = Object.assign({}, before); const n = Object.assign({}, now);
  delete b[BIZ]; delete n[BIZ];
  assert.deepStrictEqual(n, b, label + ': 사업장 밖 저장소가 바뀌었다');
}
function noCommit(label) {
  assert.strictEqual(committed().length, 0, `${label}: 커밋된 쓰기 — ${ops(committed()).join(', ')}`);
  assert.strictEqual(W.direct.length, 0, `${label}: 트랜잭션 밖 쓰기 — ${ops(W.direct).join(', ')}`);
  assert.strictEqual(notifs().length, 0, `${label}: 알림`);
}
const obs = (id, s) => console.log(`       OBS ${id}: ${s}`);

(async () => {
  console.log('\n[H] 하네스');
  await cell('BC-H0', '폐포에 두 callable · 가드 · 지원 기준 토큰 함수가 있고 묶지 못한 비전역 이름 0', () => {
    assert.strictEqual(typeof R.callableApplyToTO, 'function');
    assert.strictEqual(typeof R.callableAcceptConfirmedReassignment, 'function');
    assert.strictEqual(typeof R.srvAttendancePolicyFingerprint, 'function');
    assert.strictEqual(R.ARCHIVE_NEW_WORK_MESSAGE, MSG_WORK_CLOSED);
    for (const n of ['srvBizClosedForNewCommitment', 'srvAssertBizOpenInTx', 'assertBusinessCanAcceptApplications']) {
      assert.ok(NEED.has(n), `폐포에 ${n} 없음`);
    }
    assert.deepStrictEqual(UNRESOLVED_NON_GLOBAL, [], '묶지 못한 비전역 이름');
  });

  console.log('\n[G] 검증 대상 바이트');
  await cell('BC-G01', '가드 조각 5 의 fullSHA = 준비 때 고정값(A b9b39ec3 · 후보 3dd19e09 공통)', () => {
    for (const [name, start, rule] of GUARD_PIECES) {
      const t = guardCut(start, rule);
      assert.strictEqual(crypto.createHash('sha256').update(t, 'utf8').digest('hex'), GUARD_SHA[name], name);
    }
  });
  await cell('BC-G02', '지원은 트랜잭션 밖 사전 검사(assertBusinessCanAcceptApplications → deactivatedAt 이면 BUSINESS_NOT_APPROVED)가 트랜잭션보다 앞', () => {
    const ap = bodyOf('callableApplyToTO');
    const pre = ap.indexOf('await assertBusinessCanAcceptApplications(');
    const tx = ap.indexOf('await db.runTransaction(');
    assert.ok(pre > 0 && pre < tx, [pre, tx].join(','));
    const ev = guardCut('async function evaluateContractCapability(', 'fn');
    assert.ok(ev.includes('if (!bizData?.isApproved || bizData?.deactivatedAt) {'));
  });

  console.log('\n[A] 지원 — callableApplyToTO');
  await cell('BC-A01', '정상 운영 → PENDING 생성 · 공고/슬롯 대기 +1 · 트랜잭션 안 사업장 읽기(writer → state)', async () => {
    seedApply();
    const out = await callApply(APPLY_REQ());
    await settle();
    assert.deepStrictEqual(out, {success: true, applicationId: APPLY_ID, isReactivation: false});
    const a = F.get(appPath(APPLY_ID));
    assert.ok(a, '지원서가 없다');
    assert.strictEqual(a.status, 'PENDING');
    assert.strictEqual(a.wdId, 'wd-1');
    assert.strictEqual(F.get('tos/t1').totalPending, 1);
    const s = F.get(SLOT_PATH);
    assert.strictEqual(s.pendingCount, 1);
    assert.strictEqual(s.workDetailCounts['wd-1'].pendingCount, 1);
    assert.ok(W.reads.some((r) => r.tx !== null && r.path === BIZ), '트랜잭션 안 사업장 읽기 0');
  });
  await cell('BC-A01b', 'deactivatedAt: null → 운영 중으로 본다 → PENDING', async () => {
    seedApply({biz: {deactivatedAt: null}});
    const out = await callApply(APPLY_REQ());
    await settle();
    assert.strictEqual(out && out.success, true);
    assert.strictEqual(F.get(appPath(APPLY_ID)).status, 'PENDING');
  });
  await cell('BC-A02', '호출 전에 이미 종료(deactivatedAt) → 트랜잭션 밖 사전 검사 거절(BUSINESS_CLOSED 코드 아님) · 트랜잭션 0 · 쓰기 0', async () => {
    seedApply({biz: {deactivatedAt: at(T1 - DAY)}});
    const before = F.dump();
    const e = await rejectsWith(callApply(APPLY_REQ()), 'failed-precondition');
    assert.strictEqual(e.message, MSG_NOT_ACCEPTING);
    assert.ok(!e.details || e.details.code !== 'BUSINESS_CLOSED');
    assert.strictEqual(W.commits.length + W.aborts.length, 0, '트랜잭션이 열렸다');
    assertNoWrites('A02');
    assert.deepStrictEqual(F.dump(), before);
  });
  await cell('BC-A03', '호출 전에 사업장 문서 없음 → not-found(사전 검사) · 쓰기 0', async () => {
    seedApply();
    F.del(BIZ);
    F.clearLog();
    const before = F.dump();
    const e = await rejectsWith(callApply(APPLY_REQ()), 'not-found');
    assert.strictEqual(e.message, '사업장 정보를 찾을 수 없습니다.');
    assertNoWrites('A03');
    assert.deepStrictEqual(F.dump(), before);
  });
  await cell('BC-A04', '사전 검사 뒤 종료(Timestamp · 문자열 · true) → 트랜잭션 안 BUSINESS_CLOSED · 쓰기 0 · 지원서 없음', async () => {
    for (const v of [at(T1), '2026-11-12', true]) {
      seedApply();
      const before = F.dump();
      afterFirstOuterRead(BIZ, closeBiz(v));
      const e = await rejectsWith(callApply(APPLY_REQ()), 'failed-precondition', 'BUSINESS_CLOSED');
      assert.strictEqual(e.message, MSG_APPLY_CLOSED, String(v));
      assertNoWrites('A04 ' + String(v));
      sameExceptBiz(before, 'A04');
      assert.ok(!F.has(appPath(APPLY_ID)));
      assert.ok(W.reads.some((r) => r.tx !== null && r.path === BIZ));
    }
  });
  await cell('BC-A05', '사전 검사 뒤 사업장 문서 삭제 → 트랜잭션 안 BUSINESS_CLOSED(!exists) · 쓰기 0', async () => {
    seedApply();
    const before = F.dump();
    afterFirstOuterRead(BIZ, () => F.del(BIZ));
    await rejectsWith(callApply(APPLY_REQ()), 'failed-precondition', 'BUSINESS_CLOSED');
    assertNoWrites('A05');
    sameExceptBiz(before, 'A05');
  });
  await cell('BC-A06', 'tx 재시도 — 첫 커밋 직전 종료가 커밋되어 경합 → 다시 실행한 콜백이 BUSINESS_CLOSED · 커밋 0 · 지원서 없음', async () => {
    seedApply();
    const before = F.dump();
    const st = withRetryOnce(appPath(APPLY_ID), closeBiz(at(T1)));
    try {
      await rejectsWith(callApply(APPLY_REQ()), 'failed-precondition', 'BUSINESS_CLOSED');
    } finally {
      st.restore();
    }
    assert.strictEqual(st.injected, true, '경합 주입이 일어나지 않았다');
    assert.strictEqual(st.attempts, 2);
    noCommit('A06');
    sameExceptBiz(before, 'A06');
    assert.ok(W.aborts.some((x) => x.atCommit) && W.aborts.length >= 2);
    obs('BC-A06', `첫 시도 쓰기 시도 ${W.attempts.length}건(커밋 전 버림) · 재실행에서 가드가 막음`);
  });
  await cell('BC-A06b', 'tx 재시도 — 경합만(종료 없음) → 재실행 성공 PENDING(감싸기 자체가 정상 흐름을 바꾸지 않음)', async () => {
    seedApply();
    const st = withRetryOnce(appPath(APPLY_ID), () => {});
    let out;
    try {
      out = await callApply(APPLY_REQ());
      await settle();
    } finally {
      st.restore();
    }
    assert.strictEqual(st.injected, true);
    assert.strictEqual(out && out.success, true);
    assert.strictEqual(F.get(appPath(APPLY_ID)).status, 'PENDING');
    assert.strictEqual(F.get('tos/t1').totalPending, 1, '재시도가 두 번 셌다');
  });
  async function dupFirst(label, status, msg) {
    seedApply();
    const before = F.dump();
    // 트랜잭션 첫 읽기(계정 freeze · users/w1) 직후 — 사전 검사·겹침 조회는 이미 지나갔다
    afterFirstTxRead('users/w1', () => {
      F.put(appPath(APPLY_ID), {uid: 'w1', businessId: 'b1', toId: 't1', slotId: 's1', wdId: 'wd-1', status,
        type: 'short', startTime: '09:00', endTime: '18:00', workDate: at(WORK_DAY), activationGeneration: 0});
      closeBiz(at(T1))();
    });
    const e = await rejectsWith(callApply(APPLY_REQ()), 'already-exists');
    assert.strictEqual(e.message, msg);
    assert.ok(!e.details || e.details.code !== 'BUSINESS_CLOSED', label + ': 종료로 분류했다');
    assertNoWrites(label);
    const now = F.dump();
    assert.strictEqual(now[appPath(APPLY_ID)].status, status, '기존 지원서가 바뀌었다');
    delete now[appPath(APPLY_ID)]; delete now[BIZ];
    const b = Object.assign({}, before); delete b[BIZ];
    assert.deepStrictEqual(now, b);
  }
  await cell('BC-A07', '중복이 종료보다 먼저 — 트랜잭션 중 PENDING 이 보이고 종료 → 트랜잭션 안 "이미 지원한 업무"(재시도 멱등 계약) · 쓰기 0', async () => {
    await dupFirst('A07', 'PENDING', '이미 지원한 업무입니다.');
  });
  await cell('BC-A08', '이미 확정이 종료보다 먼저 — CONFIRMED + 종료 → "이미 지원한 업무" · 쓰기 0', async () => {
    await dupFirst('A08', 'CONFIRMED', '이미 지원한 업무입니다.');
  });
  await cell('BC-A09', '초대가 종료보다 먼저 — INVITED + 종료 → "이미 초대를 받은 근무" · 쓰기 0', async () => {
    await dupFirst('A09', 'INVITED', '이미 초대를 받은 근무입니다. 내 지원 내역에서 초대를 확인해주세요.');
  });
  await cell('BC-A10', '재지원(CANCELED 문서) + 사전 검사 뒤 종료 → BUSINESS_CLOSED · 기존 문서 CANCELED 그대로 · 쓰기 0', async () => {
    seedApply({extra: [[appPath(APPLY_ID), {uid: 'w1', businessId: 'b1', toId: 't1', slotId: 's1', wdId: 'wd-1',
      status: 'CANCELED', type: 'short', startTime: '09:00', endTime: '18:00', workDate: at(WORK_DAY),
      activationGeneration: 1}]]});
    const before = F.dump();
    afterFirstOuterRead(BIZ, closeBiz(at(T1)));
    await rejectsWith(callApply(APPLY_REQ()), 'failed-precondition', 'BUSINESS_CLOSED');
    assertNoWrites('A10');
    sameExceptBiz(before, 'A10');
    assert.strictEqual(F.get(appPath(APPLY_ID)).status, 'CANCELED');
  });
  await cell('BC-A11', '권한 — 관리자(이해충돌 읽기 뒤 종료 주입 · 주입 실행 단언) · 서브관리자(운영/종료 seed 쌍 · 사업장 읽기 0) → 모두 permission-denied · 쓰기 0', async () => {
    const MSG_ADMIN = '관리자로 등록된 사업장의 공고에는 지원할 수 없습니다.';
    // (1) 관리자 — 이해충돌 판정이 사업장 문서를 읽는다 → 그 첫 읽기 뒤 종료를 주입하고, 주입이 실제로 일어났는지 본다.
    seedApply({worker: {role: 'BUSINESS_ADMIN'}, biz: {adminIds: ['admin1', 'w1']}});
    let before = F.dump();
    afterFirstOuterRead(BIZ, closeBiz(at(T1)));
    let e = await rejectsWith(callApply(APPLY_REQ()), 'permission-denied');
    assert.strictEqual(e.message, MSG_ADMIN);
    assert.ok(F.get(BIZ).deactivatedAt != null, '관리자 사례의 종료 주입이 실행되지 않았다');
    assertNoWrites('관리자');
    sameExceptBiz(before, '관리자');
    // (2) 서브관리자 — 사업장 문서를 읽기 전에 거절된다(그래서 '읽기 뒤 종료' 주입은 도달 불가 → 쓰지 않는다). 운영/종료 seed 쌍으로 본다.
    const seeds = [['운영 중', {}], ['이미 종료', {deactivatedAt: at(T1 - DAY)}]];
    const msgs = [];
    for (const [label, bizO] of seeds) {
      seedApply({worker: {subAdminBusinessIds: ['b1']}, biz: bizO});
      before = F.dump();
      e = await rejectsWith(callApply(APPLY_REQ()), 'permission-denied');
      assert.strictEqual(e.message, MSG_ADMIN, label);
      assert.ok(!e.details || e.details.code !== 'BUSINESS_CLOSED', label);
      assert.strictEqual(W.reads.filter((r) => r.path === BIZ).length, 0, label + ': 사업장을 읽었다');
      assertNoWrites('서브관리자 ' + label);
      assert.deepStrictEqual(F.dump(), before, label + ': 저장소가 바뀌었다');
      if (bizO.deactivatedAt) assert.strictEqual(ms(F.get(BIZ).deactivatedAt), T1 - DAY, '종료값이 바뀌었다');
      msgs.push(e.message);
    }
    assert.strictEqual(msgs[0], msgs[1], '운영/종료에 따라 권한 거절이 달라졌다');
  });
  await cell('BC-A12', '다른 확정 근무 · 계약 · 그 슬롯 카운터 · 기존 알림 보존 — 사전 검사 뒤 종료로 거절되어도 그대로', async () => {
    seedApply({extra: [
      ['applications/o1', {uid: 'w1', businessId: 'b2', toId: 't2', slotId: 's2', wdId: 'wd-9', status: 'CONFIRMED',
        type: 'short', startTime: '09:00', endTime: '18:00', workDate: at(WORK_DAY + 2 * DAY), activationGeneration: 0}],
      ['tos/t2/slots/s2', {date: at(WORK_DAY + 2 * DAY), workDetailCounts: {'wd-9': {confirmedCount: 1, pendingCount: 0}}}],
      ['employment_contracts/c1', {applicationId: 'o1', businessId: 'b2', uid: 'w1', status: 'SIGNED'}],
      ['users/w1/notifications/n0', {userId: 'w1', type: 'info', isRead: false}],
    ]});
    const before = F.dump();
    afterFirstOuterRead(BIZ, closeBiz(at(T1)));
    await rejectsWith(callApply(APPLY_REQ()), 'failed-precondition', 'BUSINESS_CLOSED');
    assertNoWrites('A12');
    sameExceptBiz(before, 'A12');
  });
  await cell('BC-A13', '[S] 지원 tx 순서 — 지원서 재확인 · 중복 거절 < 사업장 tx 읽기 < 종료 판정 < 기준 판정 < 첫 쓰기(같은 읽기로 snapshot)', () => {
    const ap = bodyOf('callableApplyToTO');
    const s0 = ap.indexOf('await db.runTransaction(async (tx) => {');
    const at0 = (s) => { const i = ap.indexOf(s, s0); assert.ok(i > s0, '없음: ' + s); return i; };
    const w = Math.min(...['tx.update(', 'tx.set(', 'tx.create(', 'tx.delete('].map((s) => { const i = ap.indexOf(s, s0); return i < 0 ? Infinity : i; }));
    const seq = [at0('const existingInTx = await tx.get(appRef);'), at0('throw new HttpsError("already-exists", "이미 지원한 업무입니다.");'),
      at0('await tx.get(db.collection("businesses").doc(businessId));'), at0('if (srvBizClosedForNewCommitment(applyTxBizSnap)) {'),
      at0('if (!srvHasCanonicalAttendancePolicy(applyTxRules)) {'), at0('srvBuildAttendancePolicySnapshot(applyTxBizSnap.data())'), w];
    for (let k = 1; k < seq.length; k++) assert.ok(seq[k - 1] < seq[k], seq.join(','));
  });

  console.log('\n[R] 재배치 수락 — callableAcceptConfirmedReassignment');
  function reassignClosedNoWrites(label, before) {
    assertNoWrites(label);
    sameExceptBiz(before, label);
    assert.strictEqual(F.get(propPath(P1)).status, 'PROPOSED', '제안이 정리됐다');
    assert.strictEqual(F.get(lockPath(A_ID)).activeProposalId, P1, 'lock 이 풀렸다');
    assert.strictEqual(F.get(appPath(A_ID)).status, 'CONFIRMED', '기존 근무가 바뀌었다');
    assert.ok(!F.has(appPath(B_ID)), 'B 가 생겼다');
  }
  await cell('BC-R01', '정상 운영 → 수락 성공(B CONFIRMED · 제안 ACCEPTED · lock 해제) · 트랜잭션 첫 읽기 = 사업장', async () => {
    seedReassign();
    const out = await callReassign(INHERIT());
    await settle();
    assert.deepStrictEqual(out, {success: true, targetApplicationId: B_ID});
    assert.strictEqual(F.get(appPath(B_ID)).status, 'CONFIRMED');
    assert.strictEqual(F.get(propPath(P1)).status, 'ACCEPTED');
    assert.strictEqual(F.get(lockPath(A_ID)).activeProposalId, null);
    const first = W.reads.find((r) => r.tx !== null);
    assert.strictEqual(first && first.path, BIZ, '트랜잭션 첫 읽기가 사업장이 아니다');
  });
  await cell('BC-R02', '호출 전에 이미 종료 → BUSINESS_CLOSED(트랜잭션 첫 문장) · 트랜잭션 읽기 1 · 쓰기 0 · 제안/lock/A/정원 그대로', async () => {
    seedReassign();
    F.put(BIZ, SEED.business({deactivatedAt: at(T1 - DAY)}));
    F.clearLog();
    const before = F.dump();
    const e = await rejectsWith(callReassign(INHERIT()), 'failed-precondition', 'BUSINESS_CLOSED');
    assert.strictEqual(e.message, MSG_WORK_CLOSED);
    assert.deepStrictEqual(W.reads.filter((r) => r.tx !== null).map((r) => r.path), [BIZ]);
    reassignClosedNoWrites('R02', before);
  });
  await cell('BC-R03', '사업장 문서 없음 → BUSINESS_CLOSED · 쓰기 0', async () => {
    seedReassign();
    F.del(BIZ);
    F.clearLog();
    const before = F.dump();
    await rejectsWith(callReassign(INHERIT()), 'failed-precondition', 'BUSINESS_CLOSED');
    reassignClosedNoWrites('R03', before);
  });
  await cell('BC-R04', 'deactivatedAt: null → 운영 중 → 수락 성공', async () => {
    seedReassign();
    F.put(BIZ, SEED.business({deactivatedAt: null}));
    F.clearLog();
    const out = await callReassign(INHERIT());
    await settle();
    assert.deepStrictEqual(out, {success: true, targetApplicationId: B_ID});
  });
  await cell('BC-R05', '트랜잭션 밖 제안 읽기 뒤 종료 → BUSINESS_CLOSED · 쓰기 0', async () => {
    seedReassign();
    const before = F.dump();
    afterFirstOuterRead(propPath(P1), closeBiz(at(T1)));
    await rejectsWith(callReassign(INHERIT()), 'failed-precondition', 'BUSINESS_CLOSED');
    reassignClosedNoWrites('R05', before);
  });
  await cell('BC-R06', 'tx 재시도 — 첫 커밋 직전 종료 → 재실행 BUSINESS_CLOSED · 커밋 0 · 알림 0 · 제안 PROPOSED', async () => {
    seedReassign();
    const before = F.dump();
    const st = withRetryOnce(propPath(P1), closeBiz(at(T1)));
    try {
      await rejectsWith(callReassign(INHERIT()), 'failed-precondition', 'BUSINESS_CLOSED');
    } finally {
      st.restore();
    }
    assert.strictEqual(st.injected, true);
    noCommit('R06');
    sameExceptBiz(before, 'R06');
    assert.strictEqual(F.get(propPath(P1)).status, 'PROPOSED');
    assert.ok(!F.has(appPath(B_ID)));
  });
  await cell('BC-R06b', 'tx 재시도 — 경합만 → 재실행 성공(정원 이동 한 번)', async () => {
    seedReassign();
    const st = withRetryOnce(propPath(P1), () => {});
    let out;
    try {
      out = await callReassign(INHERIT());
      await settle();
    } finally {
      st.restore();
    }
    assert.strictEqual(st.injected, true);
    assert.deepStrictEqual(out, {success: true, targetApplicationId: B_ID});
    const s = F.get(SLOT_PATH);
    assert.strictEqual(s.workDetailCounts['wd-1'].confirmedCount, 0);
    assert.strictEqual(s.workDetailCounts['wd-2'].confirmedCount, 1);
  });
  await cell('BC-R07', '이미 수락(ACCEPTED) + 종료 → alreadyAccepted(멱등 · 트랜잭션 전 반환) · 쓰기 0 · 읽기 = 제안 1', async () => {
    seedReassign({p: {status: 'ACCEPTED', resultApplicationId: 'B-prev', decidedAt: at(T1 - HOUR)}});
    F.put(BIZ, SEED.business({deactivatedAt: at(T1 - DAY)}));
    F.clearLog();
    const before = F.dump();
    const out = await callReassign(INHERIT());
    await settle();
    assert.deepStrictEqual(out, {success: true, alreadyAccepted: true, targetApplicationId: 'B-prev'});
    assertNoWrites('R07');
    assert.deepStrictEqual(W.reads.map((r) => r.path), [propPath(P1)]);
    assert.deepStrictEqual(F.dump(), before);
  });
  await cell('BC-R08', '종결 제안(CANCELED) + 종료 → "이미 종료된 제안"(트랜잭션 전) · 쓰기 0', async () => {
    seedReassign({p: {status: 'CANCELED'}});
    F.put(BIZ, SEED.business({deactivatedAt: at(T1 - DAY)}));
    F.clearLog();
    const before = F.dump();
    const e = await rejectsWith(callReassign(INHERIT()), 'failed-precondition');
    assert.strictEqual(e.message, '이미 종료된 제안입니다.');
    assertNoWrites('R08');
    assert.deepStrictEqual(F.dump(), before);
  });
  await cell('BC-R09', '[OBS] 만료 + 종료 → 종료가 만료 정리보다 먼저: BUSINESS_CLOSED · 제안 PROPOSED 로 남음(EXPIRED 정리 쓰기 0) · 알림 0', async () => {
    seedReassign({p: {expiresAt: at(T1 - MIN)}});
    F.put(BIZ, SEED.business({deactivatedAt: at(T1 - DAY)}));
    F.clearLog();
    const before = F.dump();
    await rejectsWith(callReassign(INHERIT()), 'failed-precondition', 'BUSINESS_CLOSED');
    reassignClosedNoWrites('R09', before);
    obs('BC-R09', '종료 사업장에서는 이 호출이 만료 제안을 정리하지 않는다 — 다른 경로가 나중에 정리한다는 보장은 이 셀이 보지 않는다(잔여)');
  });
  await cell('BC-R09b', '대조 — 만료 + 운영 중 → EXPIRED 정리 · 알림 1(기존 동작)', async () => {
    seedReassign({p: {expiresAt: at(T1 - MIN)}});
    const e = await rejectsWith(callReassign(INHERIT()), 'failed-precondition');
    assert.match(e.message, /변경 가능 시간이 지나/);
    assert.strictEqual(F.get(propPath(P1)).status, 'EXPIRED');
    assert.strictEqual(notifs().length, 1);
  });
  await cell('BC-R10', '권한 — 다른 근로자(w2)의 수락 → permission-denied(트랜잭션 전 · 종료 무관) · 쓰기 0', async () => {
    seedReassign();
    F.put(BIZ, SEED.business({deactivatedAt: at(T1 - DAY)}));
    F.clearLog();
    const before = F.dump();
    const e = await rejectsWith(callReassign(INHERIT(), 'w2'), 'permission-denied');
    assert.strictEqual(e.message, '본인의 제안만 수락할 수 있습니다.');
    assertNoWrites('R10');
    assert.deepStrictEqual(F.dump(), before);
  });
  await cell('BC-R11', '[OBS] 대상 마감(슬롯 closed) + 종료 → 종료가 먼저: BUSINESS_CLOSED(TARGET_UNAVAILABLE 정리 아님) · 쓰기 0', async () => {
    seedReassign({slot: {status: 'closed'}});
    F.put(BIZ, SEED.business({deactivatedAt: at(T1 - DAY)}));
    F.clearLog();
    const before = F.dump();
    await rejectsWith(callReassign(INHERIT()), 'failed-precondition', 'BUSINESS_CLOSED');
    reassignClosedNoWrites('R11', before);
  });
  await cell('BC-R12', '[S] 재배치 tx 순서 — 가드가 tx 첫 문장(제안·원 근무·대상 읽기보다 앞) · 기존 근무 사전 확인은 tx 밖', () => {
    const rb = bodyOf('callableAcceptConfirmedReassignment');
    const t0 = rb.indexOf('const acResult: AcOutcome = await db.runTransaction(async (tx) => {');
    const g = rb.indexOf('await srvAssertBizOpenInTx(tx, acBizId, ARCHIVE_NEW_WORK_MESSAGE);');
    const reads = rb.indexOf('const [freshP, freshSrc, freshTarget, freshTo, freshSlot, freshUser] =');
    const exp = rb.indexOf('const pExpires = p.expiresAt');
    const pre = rb.indexOf('const acSrcPre = await acSrcRef.get();');
    assert.ok(pre > 0 && pre < t0 && t0 < g && g < reads && reads < exp, [pre, t0, g, reads, exp].join(','));
    assert.strictEqual(rb.split('srvAssertBizOpenInTx(').length - 1, 1);
  });

  console.log('\n[Z] 접촉');
  await cell('BC-Z01', '외부 진입 0 · 스텁 없는 외부 이름 0 · 관대 스텁 접촉 0(있으면 이 셀 실패 = 목록 보고 · 처분 대상 — 조용한 성공 0)', () => {
    assert.deepStrictEqual(R5_NET, []);
    assert.deepStrictEqual(EXT_WARN, [], 'EXT_WARN: ' + EXT_WARN.join(', '));
    assert.deepStrictEqual(F.EXT_TOUCHED.slice(0, 20), [], 'EXT_TOUCHED: ' + F.EXT_TOUCHED.slice(0, 20).join(', '));
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
