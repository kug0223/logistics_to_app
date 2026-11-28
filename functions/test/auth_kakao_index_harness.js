/**
 * [ALFIT-AUTH-KAKAO-ONBOARDING.1] index.ts 원문 폐포 로더 — auth_kakao_index_integration.test.js 보조.
 *
 *   방식은 consent_r4d_callables.test.js 와 같다(원문 추출 → 의존 폐포 AST 계산 → ts.transpileModule
 *   → new Function 주입). 다른 점: 루트 목록과 가짜 저장소를 인자로 받는 **함수**로 묶었다.
 *     1) index.ts 최상위 선언표·import 표를 만든다.
 *     2) 루트에서 출발해 값 위치 식별자를 TS 검사기로 최상위 선언에 묶고 재귀로 폐포를 모은다.
 *     3) `./x` 로컬 모듈은 ../src/x.ts 를 CommonJS 로 변환해 주입(바깥 require 는 crypto 만).
 *        외부 패키지(firebase-admin·firebase-functions/*)는 스텁.
 *     4) 함수 선언 먼저, 그 밖은 원본 순서.
 *   네트워크·실제 Firestore·Auth 0. 원문 수정 0.
 */
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const ts = require('typescript');

const SRC_DIR = path.join(__dirname, '..', 'src');
const IDX = path.join(SRC_DIR, 'index.ts');

/**
 * @param {string[]} roots 최상위 선언 이름
 * @param {object} F createFakeFirestore 결과
 * @param {object} o {HttpsError, console, Date}
 * @return {{exports: object, info: string}} 폐포 실행 결과
 */
function loadIndexClosure(roots, F, o) {
  const SRC = fs.readFileSync(IDX, 'utf8');
  const SF = ts.createSourceFile(IDX, SRC, ts.ScriptTarget.ES2022, true, ts.ScriptKind.TS);
  const SK = ts.SyntaxKind;
  const TOP = new Map();
  const IMPORTS = new Map();
  const modsOf = (st) => st.modifiers || [];
  const hasMod = (st, kind) => modsOf(st).some((m) => m.kind === kind);
  const boundNames = (name, out) => {
    if (ts.isIdentifier(name)) out.push(name.text);
    else if (ts.isObjectBindingPattern(name) || ts.isArrayBindingPattern(name)) {
      for (const el of name.elements) if (!ts.isOmittedExpression(el)) boundNames(el.name, out);
    }
    return out;
  };
  const addTop = (n, st, kind) => {
    if (!TOP.has(n)) TOP.set(n, {kind, stmts: []});
    const e = TOP.get(n);
    if (!e.stmts.includes(st)) e.stmts.push(st);
  };
  for (const st of SF.statements) {
    if (ts.isImportDeclaration(st)) {
      const mod = st.moduleSpecifier.text;
      const ic = st.importClause;
      if (!ic || ic.isTypeOnly) continue;
      if (ic.name) IMPORTS.set(ic.name.text, {module: mod, kind: 'default', imported: 'default'});
      const nb = ic.namedBindings;
      if (nb && ts.isNamespaceImport(nb)) IMPORTS.set(nb.name.text, {module: mod, kind: 'ns', imported: null});
      else if (nb && ts.isNamedImports(nb)) {
        for (const el of nb.elements) {
          if (el.isTypeOnly) continue;
          IMPORTS.set(el.name.text, {module: mod, kind: 'named', imported: (el.propertyName || el.name).text});
        }
      }
      continue;
    }
    if (hasMod(st, SK.DeclareKeyword)) continue;
    if (ts.isFunctionDeclaration(st)) { if (st.name && st.body) addTop(st.name.text, st, 'fn'); continue; }
    if (ts.isVariableStatement(st)) {
      for (const d of st.declarationList.declarations) for (const n of boundNames(d.name, [])) addTop(n, st, 'val');
      continue;
    }
    if ((ts.isClassDeclaration(st) || ts.isEnumDeclaration(st) || ts.isModuleDeclaration(st)) &&
        st.name && ts.isIdentifier(st.name)) addTop(st.name.text, st, 'val');
  }
  const normF = (f) => path.resolve(String(f)).replace(/\\/g, '/').toLowerCase();
  const want = normF(IDX);
  const host = {
    getSourceFile: (f) => (normF(f) === want ? SF : undefined),
    getDefaultLibFileName: () => 'lib.d.ts', writeFile: () => {}, getCurrentDirectory: () => SRC_DIR,
    getDirectories: () => [], getCanonicalFileName: (f) => normF(f), useCaseSensitiveFileNames: () => false,
    getNewLine: () => '\n', fileExists: (f) => normF(f) === want,
    readFile: (f) => (normF(f) === want ? SRC : undefined), directoryExists: () => true,
  };
  const program = ts.createProgram({rootNames: [IDX], options: {noLib: true, noResolve: true, types: [],
    noEmit: true, skipLibCheck: true, target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS}, host});
  const CHECKER = program.getSourceFiles().some((f) => f === SF) ? program.getTypeChecker() : null;
  const BIND_KINDS = new Set([SK.VariableDeclaration, SK.VariableDeclarationList,
    SK.ObjectBindingPattern, SK.ArrayBindingPattern, SK.BindingElement]);
  const topStmtOf = (n) => { while (n.parent && n.parent.kind !== SK.SourceFile) n = n.parent; return n; };
  const isTopLevelDecl = (d) => {
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
  };
  const isRefPosition = (id) => {
    const p = id.parent;
    if (!p) return false;
    if (ts.isShorthandPropertyAssignment(p)) return p.name === id || p.objectAssignmentInitializer === id;
    if (p.name === id) return false;
    if (p.propertyName === id) return false;
    if ((ts.isLabeledStatement(p) || ts.isBreakOrContinueStatement(p)) && p.label === id) return false;
    if (ts.isQualifiedName(p) || ts.isMetaProperty(p)) return false;
    return true;
  };
  const resolveRef = (id) => {
    const name = id.text;
    if (!CHECKER) return TOP.has(name) || IMPORTS.has(name) ? name : null;
    let sym;
    try {
      sym = ts.isShorthandPropertyAssignment(id.parent) && id.parent.name === id ?
        CHECKER.getShorthandAssignmentValueSymbol(id.parent) : CHECKER.getSymbolAtLocation(id);
    } catch (e) { sym = undefined; }
    if (!sym || !sym.declarations || sym.declarations.length === 0) {
      return TOP.has(name) || IMPORTS.has(name) ? name : null;
    }
    return isTopLevelDecl(sym.declarations[0]) ? name : null;
  };
  const collectRefs = (stmt, out) => {
    const visit = (node) => {
      if (!node) return;
      if (ts.isInterfaceDeclaration(node) || ts.isTypeAliasDeclaration(node)) return;
      if (ts.isExpressionWithTypeArguments(node)) {
        const hc = node.parent;
        if (hc && ts.isHeritageClause(hc) && hc.token === SK.ExtendsKeyword && hc.parent && ts.isClassLike(hc.parent)) {
          visit(node.expression);
        }
        return;
      }
      if (ts.isTypeNode(node)) return;
      if (ts.isIdentifier(node)) {
        if (isRefPosition(node)) { const r = resolveRef(node); if (r) out.add(r); }
        return;
      }
      ts.forEachChild(node, visit);
    };
    visit(stmt);
  };
  const NEED = new Set();
  const USED_IMPORTS = new Set();
  const queue = [...roots];
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
  const lineOf = (st) => SF.getLineAndCharacterOfPosition(st.getStart(SF)).line + 1;
  const declText = (st) => {
    const exp = modsOf(st).find((m) => m.kind === SK.ExportKeyword);
    const start = exp ? exp.end : st.getStart(SF);
    return `/* index.ts:${lineOf(st)} */\n` + SRC.slice(start, st.end).replace(/^\s+/, '');
  };
  const FN = [];
  const VAL = [];
  for (const n of NEED) {
    const e = TOP.get(n);
    for (const st of e.stmts) {
      const b = e.kind === 'fn' ? FN : VAL;
      if (!b.includes(st)) b.push(st);
    }
  }
  FN.sort((a, b) => a.pos - b.pos);
  VAL.sort((a, b) => a.pos - b.pos);

  const onX = (a, b) => (typeof a === 'function' ? a : b);
  const EXT = {
    'firebase-functions/v2/https': {onCall: onX, onRequest: onX, HttpsError: o.HttpsError},
    'firebase-functions/v2/scheduler': {onSchedule: onX},
    'firebase-functions/v2/firestore': {onDocumentCreated: onX, onDocumentUpdated: onX,
      onDocumentDeleted: onX, onDocumentWritten: onX},
    'firebase-admin/app': {initializeApp: () => ({})},
    'firebase-admin/firestore': {getFirestore: () => F.db, Timestamp: F.Ts, FieldValue: F.FieldValue,
      FieldPath: F.FieldPath, Firestore: class FakeFirestoreClass {}},
    'firebase-admin': {__ns: F.admin, default: F.admin},
    'crypto': {__ns: crypto, default: crypto},
  };
  const LOCAL = new Map();
  const loadLocal = (spec) => {
    const file = path.join(SRC_DIR, spec.replace(/^\.\//, '') + '.ts');
    if (LOCAL.has(file)) return LOCAL.get(file).exports;
    assert.ok(fs.existsSync(file), `[폐포] 로컬 모듈 파일이 없다: ${file}`);
    const js = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
      compilerOptions: {target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS}, fileName: file,
    }).outputText;
    const m = {exports: {}};
    LOCAL.set(file, m);
    const req = (s) => (s.startsWith('.') ? loadLocal(s) : (s === 'crypto' ? crypto :
      (() => { throw new Error('[차단] 로컬 모듈의 바깥 require: ' + s); })()));
    // eslint-disable-next-line no-new-func
    new Function('exports', 'require', 'module', '__filename', '__dirname', 'Date', js)(
      m.exports, req, m, file, path.dirname(file), o.Date || Date);
    return m.exports;
  };
  const EXT_WARN = [];
  const __imp = (mod, kind, imported, local) => {
    if (mod.startsWith('.')) {
      const ex = loadLocal(mod);
      if (kind === 'ns') return ex;
      const key = kind === 'default' ? 'default' : imported;
      assert.ok(Object.prototype.hasOwnProperty.call(ex, key), `[폐포] ${mod} 에 '${key}' 없음(${local})`);
      return ex[key];
    }
    const m = EXT[mod];
    if (kind === 'ns' || kind === 'default') {
      const v = m && (kind === 'ns' ? m.__ns : (m.default || m.__ns));
      if (v) return v;
    } else if (m && Object.prototype.hasOwnProperty.call(m, imported)) {
      return m[imported];
    }
    EXT_WARN.push(`${mod}#${imported || kind}`);
    return F.lenient(`${mod}#${imported || kind}`);
  };
  const HARNESS = [
    ...[...USED_IMPORTS].sort().map((local) => {
      const im = IMPORTS.get(local);
      return `const ${local} = __imp(${JSON.stringify(im.module)}, ${JSON.stringify(im.kind)}, ` +
        `${JSON.stringify(im.imported)}, ${JSON.stringify(local)});`;
    }),
    ...FN.map(declText),
    ...VAL.map(declText),
    `module.exports = {${roots.join(', ')}};`,
  ].join('\n\n');
  const TR = ts.transpileModule(HARNESS, {
    compilerOptions: {target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS},
    fileName: 'auth_kakao_index_harness.ts',
  });
  const HMOD = {exports: {}};
  // eslint-disable-next-line no-new-func
  new Function('module', 'exports', '__imp', 'Date', 'console', TR.outputText)(
    HMOD, HMOD.exports, __imp, o.Date || Date, o.console || console);
  return {exports: HMOD.exports,
    info: `선언 ${NEED.size}개 · 가져온 이름 ${USED_IMPORTS.size}개 · 검사기=${!!CHECKER}` +
      (EXT_WARN.length ? ` · 스텁 없는 외부: ${EXT_WARN.join(', ')}` : '')};
}

module.exports = {loadIndexClosure};
