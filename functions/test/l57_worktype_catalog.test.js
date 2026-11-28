'use strict';
/**
 * [L57 r5 · 판정291 B7] 업무유형 목록 요청 단위 1회(srvWorkTypeCatalog) 동등성.
 *
 *   같은 입력으로 호출부 순서(이름 검증 → id 결합)를 두 방식으로 돌린다:
 *     A = catalog 없이(예전 그대로 · 각 helper 가 따로 읽음) · B = 같은 catalog 를 두 helper 에 넘김.
 *   A 와 B 의 결과(성공·코드·문구·세부 코드·찍힌 workTypeId)가 같고, B 의 업무유형 읽기가 A 보다 많지 않아야 한다.
 *   A 결과는 L57_OUT 에 남겨 이전 원문 사본(catalog 없는 판)의 A 와도 비교한다(L57_COMPARE).
 */
const {test} = require('node:test');
const assert = require('assert');
const fs = require('fs');
const {createFakeFirestore} = require('./consent_r4d_fakestore');
const {loadIndexClosure} = require('./auth_kakao_index_harness');

class HttpsError extends Error {
  constructor(code, message, details) { super(message); this.code = code; this.details = details; }
}
const QCON = {};
for (const k of ['log', 'info', 'warn', 'error', 'debug']) QCON[k] = () => {};
const F = createFakeFirestore({now: () => Date.UTC(2026, 10, 26)});
const SRC_HAS_CATALOG = fs.readFileSync(require.resolve('../src/index.ts'), 'utf8').includes('function srvWorkTypeCatalog(');
const roots = ['assertWorkTypesInBusiness', 'srvBindWorkTypeIds', 'evaluatePostingReadinessFirestore', 'dbReadinessReader']
  .concat(SRC_HAS_CATALOG ? ['srvWorkTypeCatalog'] : []);
const SRC_HAS_READY_CATALOG = SRC_HAS_CATALOG &&
  fs.readFileSync(require.resolve('../src/index.ts'), 'utf8').includes('opts: {existingPosting?: boolean; workTypeCatalog?: SrvWorkTypeCatalog} = {},');
const {exports: X} = loadIndexClosure(roots, F, {HttpsError, console: QCON});

const WT = (id, name, isActive) => ({id, d: {name, isActive}});
const SCEN = [
  // [id, workTypes, names(이름 검증 입력), newWds, oldWds, isSuper]
  ['w1-none', [], ['포장'], [{workType: '포장', startTime: '09:00', endTime: '18:00'}], [], false],
  ['w2-inactive-only', [WT('t1', '포장', false)], ['포장'], [{workType: '포장', startTime: '09:00', endTime: '18:00'}], [], false],
  ['w3-stamp', [WT('t1', '포장', true), WT('t2', '분류', true)], ['포장'], [{workType: '포장', startTime: '09:00', endTime: '18:00'}], [], false],
  ['w4-sent-id-ok', [WT('t1', '포장', true)], ['포장'], [{workType: '포장', startTime: '09:00', endTime: '18:00', workTypeId: 't1'}], [], false],
  ['w5-sent-id-name-mismatch', [WT('t1', '포장', true), WT('t2', '분류', true)], ['포장'],
    [{workType: '포장', startTime: '09:00', endTime: '18:00', workTypeId: 't2'}], [], false],
  ['w6-sent-id-inactive', [WT('t1', '포장', true), WT('t9', '포장', false)], ['포장'],
    [{workType: '포장', startTime: '09:00', endTime: '18:00', workTypeId: 't9'}], [], false],
  ['w6b-sent-id-inactive-super', [WT('t9', '포장', false)], [],
    [{workType: '포장', startTime: '09:00', endTime: '18:00', workTypeId: 't9'}], [], true],
  ['w7-same-name-twice', [WT('t1', '포장', true), WT('t3', '포장', true)], ['포장'], [{workType: '포장', startTime: '09:00', endTime: '18:00'}], [], false],
  ['w8-old-keeps-id', [WT('t1', '포장', true)], [],
    [{workType: '포장', startTime: '09:00', endTime: '18:00', workTypeId: 'tX'}], [{workType: '포장', startTime: '09:00', endTime: '18:00', workTypeId: 't1'}], false],
  ['w9-bind-only', [WT('t1', '포장', true)], [], [{workType: '포장', startTime: '10:00', endTime: '19:00'}], [], false],
  ['w10-string-true', [{id: 't1', d: {name: '포장', isActive: 'true'}}], ['포장'], [{workType: '포장', startTime: '09:00', endTime: '18:00'}], [], false],
  ['w11-unregistered-name', [WT('t1', '포장', true)], ['포장', '검수'], [{workType: '검수', startTime: '09:00', endTime: '18:00'}], [], false],
  ['w12-multi-new', [WT('t1', '포장', true), WT('t2', '분류', true), WT('t4', '분류', false)], ['포장', '분류'],
    [{workType: '포장', startTime: '09:00', endTime: '18:00'}, {workType: '분류', startTime: '13:00', endTime: '22:00'}], [], false],
  ['w13-no-new-wds', [WT('t1', '포장', true)], ['포장'], [], [], false],
];

function seed(wts) {
  F.reset();
  for (const w of wts) F.put(`businesses/b1/workTypes/${w.id}`, w.d);
}
async function runMode(sc, useCatalog) {
  const [, wts, names, newWds, oldWds, isSuper] = sc;
  seed(wts);
  const wds = JSON.parse(JSON.stringify(newWds));
  const before = F.W.reads.length;
  const cat = useCatalog ? X.srvWorkTypeCatalog('b1') : undefined;
  let out;
  try {
    if (!isSuper && names.length > 0) await X.assertWorkTypesInBusiness('b1', names, cat);
    await X.srvBindWorkTypeIds('b1', wds, JSON.parse(JSON.stringify(oldWds)), isSuper, cat);
    out = {ok: true};
  } catch (e) {
    out = {ok: false, code: e.code ?? null, message: String(e.message), detail: e.details?.code ?? null};
  }
  out.ids = wds.map((w) => w.workTypeId ?? null);
  out.wtReads = F.W.reads.slice(before).filter((r) => String(r.path).includes('/workTypes')).length;
  return out;
}

const OUT = {};
for (const sc of SCEN) {
  test(`WT ${sc[0]}`, async () => {
    const a = await runMode(sc, false);
    OUT[sc[0]] = a;
    if (!SRC_HAS_CATALOG) return;
    const b = await runMode(sc, true);
    const strip = ({wtReads, ...rest}) => rest;
    assert.deepStrictEqual(strip(b), strip(a), `${sc[0]} catalog 결과가 다르다`);
    assert.ok(b.wtReads <= a.wtReads, `${sc[0]} 읽기 ${a.wtReads}→${b.wtReads}`);
    if (a.wtReads === 2) assert.strictEqual(b.wtReads, 1, `${sc[0]} 이름 검증+결합이 한 번으로 합쳐져야 한다`);
  });
}

if (SRC_HAS_CATALOG) {
  test('WT-F 읽기 실패는 기억하지 않는다 — 다음 호출이 다시 읽어 성공한다', async () => {
    seed([WT('t1', '포장', true)]);
    let fail = 1;
    const orig = F.db.collection;
    // 첫 업무유형 컬렉션 읽기만 일시 장애로 만든다(쿼리 읽기는 afterGet 훅을 타지 않는다).
    F.db.collection = (c) => (c === 'businesses' && fail-- > 0) ?
      {doc: () => ({collection: () => ({get: async () => { throw new Error('UNAVAILABLE'); }})})} : orig(c);
    const cat = X.srvWorkTypeCatalog('b1');
    try {
      await assert.rejects(() => cat(), /UNAVAILABLE/);
      const m = await cat();
      assert.strictEqual(m.get('t1').name, '포장');
    } finally {
      F.db.collection = orig;
    }
    // 성공한 목록은 같은 로더에서 다시 읽지 않는다.
    const before = F.W.reads.length;
    await cat();
    assert.strictEqual(F.W.reads.length, before);
  });
  test('WT-S 호출부: 거래 안 두 자리는 attempt 마다 새 목록 · UpdateTO 는 요청 하나', () => {
    const s = fs.readFileSync(require.resolve('../src/index.ts'), 'utf8');
    const body = (name) => { const i = s.indexOf(`export const ${name} = onCall(`); return s.slice(i, s.indexOf('\n);\n', i)); };
    const slot = body('callableUpdateSlotWorkDetails');
    for (const v of ['singleWtCatalog', 'batchWtCatalog']) {
      const decl = slot.indexOf(`const ${v} = srvWorkTypeCatalog(businessId);`);
      assert.ok(decl > 0, v);
      const tx = slot.lastIndexOf('await db.runTransaction(async (tx) => {', decl);
      assert.ok(tx > 0 && decl - tx < 200, `${v} 는 거래 콜백 첫머리에서 만든다`);
      assert.strictEqual((slot.match(new RegExp(`, ${v}\\)`, 'g')) || []).length, 2, `${v} 를 이름 검증·결합 둘 다 쓴다`);
    }
    const upd = body('callableUpdateTO');
    assert.ok(upd.includes('const updWtCatalog = srvWorkTypeCatalog(businessId);'));
    assert.strictEqual((upd.match(/, updWtCatalog\)/g) || []).length, 2);
  });
}

// ── [L57 r7] 준비 판정(활성 업무유형) — 목록을 넘겨도 같은 이유 코드 · CreateTO 순서(준비 → 이름 → 결합) 읽기 3→1 ─────
const POL = {earlyWindow: 30, earlyArrivalUnit: 30, lateGrace: 5, lateUnit: 30, lateWindow: 30, overtimeUnit: 10, earlyLeaveUnit: 30};
const BIZ = (o = {}) => Object.assign({isApproved: true, ownerId: 'own1', attendanceRules: Object.assign({policySource: 'ALFIT_DEFAULT'}, POL),
  attendancePolicyConfirmation: Object.assign({confirmedAt: new F.Ts(Date.UTC(2026, 9, 1)), confirmedBy: 'own1', actorRole: 'business_admin'}, POL)}, o);
const READY = [
  // [id, workTypes, bizOverride, existingPosting]
  ['r1-no-worktype', [], {}, false],
  ['r2-inactive-only', [WT('t1', '포장', false)], {}, false],
  ['r3-string-true', [{id: 't1', d: {name: '포장', isActive: 'true'}}], {}, false],
  ['r4-ready', [WT('t1', '포장', true)], {}, false],
  ['r5-not-approved', [WT('t1', '포장', true)], {isApproved: false}, false],
  ['r6-existing-no-worktype', [], {}, true],
  ['r7-no-template', [WT('t1', '포장', true)], {}, false, true],
];
function seedReady(wts, noTpl) {
  seed(wts);
  F.put('users/own1', {role: 'BUSINESS_ADMIN', sealBase64: 'U0VBTA=='});
  if (!noTpl) F.put('businesses/b1/contract_templates/k1', {templateType: 'daily'});
}
for (const [id, wts, bo, existing, noTpl] of READY) {
  test(`READY ${id}`, async () => {
    seedReady(wts, noTpl);
    const before = F.W.reads.length;
    const a = await X.evaluatePostingReadinessFirestore('b1', BIZ(bo), X.dbReadinessReader, {existingPosting: existing});
    const aReads = F.W.reads.slice(before).filter((r) => String(r.path).includes('/workTypes')).length;
    OUT[`ready:${id}`] = {reason: a, wtReads: aReads};
    if (!SRC_HAS_READY_CATALOG) return;
    seedReady(wts, noTpl);
    const cat = X.srvWorkTypeCatalog('b1');
    const b = await X.evaluatePostingReadinessFirestore('b1', BIZ(bo), X.dbReadinessReader, {existingPosting: existing, workTypeCatalog: cat});
    assert.strictEqual(b, a, `${id} 이유 코드가 다르다`);
  });
}
if (SRC_HAS_READY_CATALOG) {
  test('CREATE-SEQ CreateTO 순서(준비 → 이름 검증 → id 결합)가 목록 1회로 같은 결과', async () => {
    const run = async (useCat) => {
      seedReady([WT('t1', '포장', true), WT('t2', '분류', true)]);
      const wds = [{workType: '포장', startTime: '09:00', endTime: '18:00'}];
      const cat = useCat ? X.srvWorkTypeCatalog('b1') : undefined;
      const before = F.W.reads.length;
      const r = await X.evaluatePostingReadinessFirestore('b1', BIZ(), X.dbReadinessReader, useCat ? {workTypeCatalog: cat} : {});
      await X.assertWorkTypesInBusiness('b1', ['포장'], cat);
      await X.srvBindWorkTypeIds('b1', wds, [], false, cat);
      return {r, ids: wds.map((w) => w.workTypeId), wt: F.W.reads.slice(before).filter((x) => String(x.path).includes('/workTypes')).length};
    };
    const a = await run(false); const b = await run(true);
    assert.deepStrictEqual({r: b.r, ids: b.ids}, {r: a.r, ids: a.ids});
    assert.strictEqual(a.wt, 3); assert.strictEqual(b.wt, 1);
  });
}

test('OUT 기록', () => {
  if (process.env.L57_OUT) fs.writeFileSync(process.env.L57_OUT, JSON.stringify(OUT, null, 2));
  assert.strictEqual(Object.keys(OUT).length, SCEN.length + READY.length);
});
if (process.env.L57_COMPARE) {
  test('EQ catalog 없는 경로가 이전 원문과 같다(결과·코드·문구·세부 코드·id·읽기 수)', () => {
    const old = JSON.parse(fs.readFileSync(process.env.L57_COMPARE, 'utf8'));
    for (const k of Object.keys(OUT)) assert.deepStrictEqual(OUT[k], old[k], k);
  });
}
