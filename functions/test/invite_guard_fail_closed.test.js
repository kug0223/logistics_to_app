/**
 * [ISG2] 초대 수락 guard — **실제 소스를 실행해서** 경계를 확인한다.
 *
 *   앞선 판(invite_start_guard.test.js)은 만료 계산과 소스 계약을 봤다.
 *   이번 판은 그걸로 끝내지 않는다: `index.ts` 에서 guard 함수들과
 *   트랜잭션 안의 guard 블록 **원문을 꺼내 TypeScript 로 컴파일하고
 *   스텁 위에서 돌린다.** 재구현이 아니라 배포될 바로 그 코드다.
 *
 *   확인 대상
 *     FC-A  분류: slotId 가 있으면 언제나 단기(writer 와 같은 식)
 *     FC-B  신뢰 순서: slot.date → slot workDetail → (slot 없을 때만) 지원서
 *     FC-C  fail-closed: 모르면 거절(slot 누락·wdId 불일치·오염 workDate)
 *     FC-D  시각 경계: 시작 1분 전 허용 / 정각·이후 거절
 *     FC-E  guard 블록 실행: 좌석 쓰기 전에 throw, 장기는 통과
 */
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const ts = require('typescript');

const SRC = fs.readFileSync(
    path.join(__dirname, '..', 'src', 'index.ts'), 'utf8');

// ── 원문 추출 ────────────────────────────────────────────────────────────
/** 선언 시작부터 중괄호 균형이 맞는 지점까지 잘라낸다. */
function cutDecl(src, header) {
  const i = src.indexOf(header);
  assert.ok(i >= 0, `원문을 찾지 못했다: ${header}`);
  const open = src.indexOf('{', i);
  let depth = 0;
  for (let j = open; j < src.length; j++) {
    if (src[j] === '{') depth++;
    else if (src[j] === '}') {
      depth--;
      if (depth === 0) return src.slice(i, j + 1);
    }
  }
  throw new Error(`중괄호가 닫히지 않았다: ${header}`);
}

function cutBetween(src, startMark, endMark) {
  const a = src.indexOf(startMark);
  const b = src.indexOf(endMark);
  assert.ok(a >= 0 && b > a, '가드 블록 마커를 찾지 못했다');
  return src.slice(a + startMark.length, b);
}

const typeDecls = (() => {
  const a = SRC.indexOf('type GuardShiftReason =');
  const b = SRC.indexOf('function srvResolveGuardShiftStart');
  assert.ok(a >= 0 && b > a, 'Guard 타입 선언을 찾지 못했다');
  return SRC.slice(a, b);
})();

const harnessTs = [
  'const SRV_KST_MS = 9 * 60 * 60 * 1000;',
  cutDecl(SRC, 'function srvKstDayStartMs('),
  cutDecl(SRC, 'function srvShiftStartMsFrom('),
  typeDecls,
  cutDecl(SRC, 'function srvResolveGuardShiftStart('),
  cutDecl(SRC, 'function srvIsLongTermInvite('),
  'module.exports = {srvResolveGuardShiftStart, srvIsLongTermInvite,',
  '  srvKstDayStartMs, srvShiftStartMsFrom};',
].join('\n\n');

/** 실제 소스를 컴파일해 실행 가능한 모듈로 만든다. */
function loadReal(tsSource, extraHeader) {
  const js = ts.transpileModule(
      (extraHeader || '') + tsSource,
      {compilerOptions: {target: ts.ScriptTarget.ES2020,
        module: ts.ModuleKind.CommonJS}}).outputText;
  const mod = {exports: {}};
  // eslint-disable-next-line no-new-func
  new Function('module', 'exports', 'admin', 'db', 'HttpsError', 'console',
      'appRef', 'tx', 'freshData', js)(
      mod, mod.exports, FAKE_ADMIN, FAKE_DB, FakeHttpsError, FAKE_CONSOLE,
      undefined, undefined, undefined);
  return mod.exports;
}

// ── 스텁 ────────────────────────────────────────────────────────────────
class FakeHttpsError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}
const FAKE_CONSOLE = {error: () => {}, log: () => {}, warn: () => {}};
const FAKE_ADMIN = {firestore: {Timestamp: {
  fromMillis: (ms) => ({toMillis: () => ms}),
}}};
const FAKE_DB = {collection: () => ({doc: () => ({
  collection: () => ({doc: () => ({__ref: true})}),
})})};

const real = loadReal(harnessTs);
const {srvResolveGuardShiftStart, srvIsLongTermInvite} = real;

const KST = 9 * 3600e3;
const ts2 = (ms) => ({toMillis: () => ms});
/** 그 KST 날짜의 자정 instant. */
const kstMidnight = (y, m, d) => Date.UTC(y, m - 1, d) - KST;

const DAY = kstMidnight(2026, 10, 15);          // 2026-10-15 KST 00:00
const START = DAY + 20 * 3600e3;                // 20:00 KST
const SLOT_OK = {
  date: ts2(DAY),
  workDetails: [
    {wdId: 'wd-A', workType: '피킹', startTime: '09:00', endTime: '12:00'},
    {wdId: 'wd-B', workType: '검수', startTime: '20:00', endTime: '22:00'},
  ],
};
const APP_SHORT = {
  toId: 'to1', slotId: 'slot1', wdId: 'wd-B',
  type: 'short', startTime: '20:00', endTime: '22:00',
  workDate: ts2(DAY),
};

let pass = 0;
let fail = 0;
function cell(id, name, fn) {
  try {
    fn();
    pass++;
    console.log(`  ✓ ${id} ${name}`);
  } catch (e) {
    fail++;
    console.log(`  ✗ ${id} ${name}\n      ${e.message}`);
  }
}

// ── FC-A 분류 ───────────────────────────────────────────────────────────
console.log('\nFC-A 장기/단기 분류 — writer(isLong) 와 같은 식');

cell('FC-01', 'slotId 가 있으면 workDays 가 실려 있어도 단기다', () => {
  // 이전 판은 `type==="long_term" || workDays.length>0` 만 봤다.
  // writer 는 workDays 를 isLong 과 무관하게 저장하므로 이 조합이 만들어진다.
  assert.strictEqual(srvIsLongTermInvite(
      {...APP_SHORT, workDays: ['월', '화']}), false);
});
cell('FC-02', 'slotId 가 있으면 type=long_term 이라도 단기다', () => {
  assert.strictEqual(srvIsLongTermInvite(
      {...APP_SHORT, type: 'long_term'}), false);
});
cell('FC-03', 'slot 없고 workDays 있으면 장기', () => {
  assert.strictEqual(srvIsLongTermInvite(
      {toId: 't', type: 'short', workDays: ['월']}), true);
});
cell('FC-04', 'slot 없고 workEndDate 있으면 장기', () => {
  assert.strictEqual(srvIsLongTermInvite(
      {toId: 't', type: 'short', workEndDate: ts2(DAY)}), true);
});
cell('FC-05', 'slot 없고 단서도 없으면 단기(= guard 적용)', () => {
  assert.strictEqual(srvIsLongTermInvite(
      {toId: 't', type: 'short', startTime: '20:00', workDate: ts2(DAY)}),
  false);
});

// ── FC-B 신뢰 순서 ──────────────────────────────────────────────────────
console.log('\nFC-B 신뢰 순서 — slot 이 canonical');

cell('FC-06', 'wdId 로 matched workDetail 의 시작시각을 쓴다', () => {
  const r = srvResolveGuardShiftStart(APP_SHORT, true, SLOT_OK);
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.source, 'SLOT_WD');
  assert.strictEqual(r.startMs, START);
});
cell('FC-07', '오염된 app.workDate(+9h)가 있어도 slot.date 로 판정한다', () => {
  // DEV 실측 오염 형태: app.workDate 가 KST 09:00(=UTC 자정).
  const contaminated = {...APP_SHORT, workDate: ts2(DAY + 9 * 3600e3)};
  const r = srvResolveGuardShiftStart(contaminated, true, SLOT_OK);
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.startMs, START, '지원서 snapshot 이 판정을 밀면 안 된다');
});
cell('FC-08', 'wdId 가 없으면 workDetailId 합성키로 찾는다', () => {
  const legacy = {...APP_SHORT, wdId: undefined,
    workDetailId: '검수_20:00_22:00'};
  const r = srvResolveGuardShiftStart(legacy, true, SLOT_OK);
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.startMs, START);
});
cell('FC-09', 'workDetail 의 시간이 지원서와 다르면 slot 쪽을 쓴다', () => {
  const skewed = {...APP_SHORT, startTime: '23:30'};
  const r = srvResolveGuardShiftStart(skewed, true, SLOT_OK);
  assert.strictEqual(r.startMs, START);
});

// ── FC-C fail-closed ────────────────────────────────────────────────────
console.log('\nFC-C 모르면 거절한다');

cell('FC-10', 'slot 문서가 없으면 거절', () => {
  const r = srvResolveGuardShiftStart(APP_SHORT, false, undefined);
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.reason, 'SLOT_MISSING');
});
cell('FC-11', 'slotId 는 있는데 toId 가 없으면 거절', () => {
  const r = srvResolveGuardShiftStart(
      {...APP_SHORT, toId: undefined}, true, SLOT_OK);
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.reason, 'SLOT_REF_BROKEN');
});
cell('FC-12', 'slot 에 date 가 없으면 거절', () => {
  const r = srvResolveGuardShiftStart(
      APP_SHORT, true, {workDetails: SLOT_OK.workDetails});
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.reason, 'SLOT_DATE_MISSING');
});
cell('FC-13', 'workDetails 는 있는데 이 초대의 업무가 없으면 거절', () => {
  const r = srvResolveGuardShiftStart(
      {...APP_SHORT, wdId: 'wd-ZZZ', workDetailId: undefined},
      true, SLOT_OK);
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.reason, 'WD_MISMATCH');
});
cell('FC-14', 'wdId 불일치에서 지원서 startTime 으로 되돌아가지 않는다', () => {
  // 되돌아갔다면 ok:true 가 나왔을 것이다(지원서에 startTime 이 있다).
  const r = srvResolveGuardShiftStart(
      {...APP_SHORT, wdId: 'wd-ZZZ', workDetailId: 'none_1:00_2:00'},
      true, SLOT_OK);
  assert.strictEqual(r.ok, false);
});
cell('FC-15', 'slot 없는 단기 — workDate 가 KST 자정이 아니면 거절', () => {
  const r = srvResolveGuardShiftStart(
      {toId: 't', type: 'short', startTime: '20:00',
        workDate: ts2(DAY + 9 * 3600e3)}, false, undefined);
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.reason, 'WORKDATE_NONCANONICAL');
});
cell('FC-16', 'slot 없는 단기 — canonical workDate 면 정상 legacy 로 쓴다', () => {
  const r = srvResolveGuardShiftStart(
      {toId: 't', type: 'short', startTime: '20:00', workDate: ts2(DAY)},
      false, undefined);
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.source, 'APP_LEGACY');
  assert.strictEqual(r.startMs, START);
});
cell('FC-17', 'workDate 자체가 없으면 거절', () => {
  const r = srvResolveGuardShiftStart(
      {toId: 't', type: 'short', startTime: '20:00'}, false, undefined);
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.reason, 'WORKDATE_MISSING');
});
cell('FC-18', 'startTime 이 "HH:MM" 이 아니면 거절', () => {
  const r = srvResolveGuardShiftStart(
      {toId: 't', type: 'short', startTime: '밤', workDate: ts2(DAY)},
      false, undefined);
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.reason, 'START_TIME_INVALID');
});
cell('FC-19', 'workDetails 가 빈 슬롯은 부재지 불일치가 아니다 — ' +
    'slot.date + 지원서 시각', () => {
  const r = srvResolveGuardShiftStart(
      APP_SHORT, true, {date: ts2(DAY), workDetails: []});
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.source, 'SLOT_LEGACY');
  assert.strictEqual(r.startMs, START);
});

// ── FC-D/E guard 블록 실행 ──────────────────────────────────────────────
console.log('\nFC-D·E 트랜잭션 guard 블록을 실제로 실행한다');

const blockTs = cutBetween(SRC, '// [ISG2-BLOCK-START]', '// [ISG2-BLOCK-END]');

/**
 * 블록 원문을 그대로 async 함수 몸통으로 감싸 실행한다.
 * @param {object} opt 실행 조건
 * @return {Promise<object>} {threw, code, message, slotReads}
 */
async function runGuard(opt) {
  const src = [
    'const SRV_KST_MS = 9 * 60 * 60 * 1000;',
    cutDecl(SRC, 'function srvKstDayStartMs('),
    cutDecl(SRC, 'function srvShiftStartMsFrom('),
    typeDecls,
    cutDecl(SRC, 'function srvResolveGuardShiftStart('),
    cutDecl(SRC, 'function srvIsLongTermInvite('),
    'module.exports.run = async function(' +
      'tx, db, HttpsError, appRef, freshData, Date) {',
    blockTs,
    '  return "PASSED_GUARD";',
    '};',
  ].join('\n\n');
  const js = ts.transpileModule(src, {compilerOptions: {
    target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS}}).outputText;
  const mod = {exports: {}};
  // eslint-disable-next-line no-new-func
  new Function('module', 'exports', 'admin', 'console', js)(
      mod, mod.exports, FAKE_ADMIN, FAKE_CONSOLE);

  const reads = [];
  const tx = {get: async (ref) => {
    reads.push(ref);
    return {exists: opt.slotExists, data: () => opt.slotData};
  }};
  const db = {collection: (c) => ({doc: (d) => ({
    collection: (c2) => ({doc: (d2) => `${c}/${d}/${c2}/${d2}`}),
  })})};
  const FakeDate = {now: () => opt.now};
  try {
    const out = await mod.exports.run(
        tx, db, FakeHttpsError, {id: 'app1'}, opt.app, FakeDate);
    return {threw: false, out, slotReads: reads.length};
  } catch (e) {
    return {threw: true, code: e.code, message: e.message,
      slotReads: reads.length};
  }
}

/** 비동기 셀. */
const asyncCells = [];
function acell(id, name, fn) {
  asyncCells.push([id, name, fn]);
}

acell('FC-20', '시작 1분 전 — 통과', async () => {
  const r = await runGuard({app: APP_SHORT, slotExists: true,
    slotData: SLOT_OK, now: START - 60000});
  assert.strictEqual(r.threw, false);
  assert.strictEqual(r.out, 'PASSED_GUARD');
});
acell('FC-21', '정각 — 거절', async () => {
  const r = await runGuard({app: APP_SHORT, slotExists: true,
    slotData: SLOT_OK, now: START});
  assert.strictEqual(r.threw, true);
  assert.strictEqual(r.code, 'failed-precondition');
  assert.ok(r.message.includes('이미 시작'), r.message);
});
acell('FC-22', '시작 1분 후 — 거절', async () => {
  const r = await runGuard({app: APP_SHORT, slotExists: true,
    slotData: SLOT_OK, now: START + 60000});
  assert.strictEqual(r.threw, true);
});
acell('FC-23', '근무 종료 12시간 뒤 — 거절(이전 판이 열어 두던 창)', async () => {
  const r = await runGuard({app: APP_SHORT, slotExists: true,
    slotData: SLOT_OK, now: START + 14 * 3600e3});
  assert.strictEqual(r.threw, true);
});
acell('FC-24', 'slot 이 사라졌으면 시작 전이라도 거절(fail-closed)', async () => {
  const r = await runGuard({app: APP_SHORT, slotExists: false,
    slotData: undefined, now: START - 3600e3});
  assert.strictEqual(r.threw, true);
  assert.strictEqual(r.code, 'failed-precondition');
  assert.ok(r.message.includes('근무 일정을 확인할 수 없어'), r.message);
});
acell('FC-25', 'wdId 불일치 — 시작 전이라도 거절', async () => {
  const r = await runGuard({
    app: {...APP_SHORT, wdId: 'wd-ZZZ', workDetailId: undefined},
    slotExists: true, slotData: SLOT_OK, now: START - 3600e3});
  assert.strictEqual(r.threw, true);
  assert.ok(r.message.includes('근무 일정을 확인할 수 없어'));
});
acell('FC-26', '오염 workDate + slot 정상 — slot 으로 정확히 판정', async () => {
  const contaminated = {...APP_SHORT, workDate: ts2(DAY + 9 * 3600e3)};
  // 이전 판이라면 app.workDate(+9h) 를 먼저 쓰지 않았지만, slot 이 없을 때
  // 되돌아갔다. 지금은 slot 이 있으면 되돌아가지 않는다.
  const before = await runGuard({app: contaminated, slotExists: true,
    slotData: SLOT_OK, now: START - 60000});
  const after = await runGuard({app: contaminated, slotExists: true,
    slotData: SLOT_OK, now: START + 60000});
  assert.strictEqual(before.threw, false);
  assert.strictEqual(after.threw, true);
});
acell('FC-27', '장기 초대 — slot 을 읽지도 않고 통과', async () => {
  const r = await runGuard({
    app: {toId: 't', type: 'long_term', workDays: ['월'],
      startTime: '09:00', workDate: ts2(DAY)},
    slotExists: false, slotData: undefined, now: START + 86400e3});
  assert.strictEqual(r.threw, false);
  assert.strictEqual(r.slotReads, 0, '장기는 추가 읽기가 없어야 한다');
});
acell('FC-28', '단기 초대는 slot 을 정확히 1회 읽는다(tx.get)', async () => {
  const r = await runGuard({app: APP_SHORT, slotExists: true,
    slotData: SLOT_OK, now: START - 60000});
  assert.strictEqual(r.slotReads, 1);
});
acell('FC-29', 'slotId 와 workDays 가 함께 있는 초대도 guard 를 받는다', async () => {
  const r = await runGuard({
    app: {...APP_SHORT, workDays: ['월', '화']},
    slotExists: true, slotData: SLOT_OK, now: START + 60000});
  assert.strictEqual(r.threw, true,
      'slotId 가 있으면 단기다 — 장기로 새어 나가면 안 된다');
});

// ── FC-F 소스 계약(실행으로 못 보는 것만) ───────────────────────────────
console.log('\nFC-F 자리 계약');

cell('FC-30', 'guard 블록은 좌석·계약 쓰기보다 **앞**에 있다', () => {
  const blockAt = SRC.indexOf('// [ISG2-BLOCK-START]');
  const capAt = SRC.indexOf('evaluateContractCapability(\n        invBizId');
  assert.ok(blockAt > 0, 'guard 블록이 없다');
  assert.ok(capAt > blockAt,
      '계약 능력 검사·좌석 쓰기가 guard 보다 먼저면 안 된다');
});
cell('FC-31', '만료 스케줄러 쿼리는 그대로다(저장값이 좁아져 따라온다)', () => {
  const body = cutDecl(SRC, 'async function processExpiredTOInvitations(');
  assert.ok(body.includes('"status", "==", "INVITED"'), 'status 조건');
  assert.ok(body.includes('"inviteExpiresAt", "<="'), 'inviteExpiresAt 조건');
  assert.ok(!body.includes('workDate'),
      '스케줄러는 근무일을 보지 않는다 — 저장된 만료값만 따른다');
});
cell('FC-32', '초대 guard 경로의 시작시각 식은 한 벌이다', () => {
  // index.ts 전체에는 같은 산술이 2곳 있다. 두 번째는 **취소 패널티**
  //   경로(`cancelPenalty`)로, 소유자가 다르고 `workDate` 를 직접 쓴다
  //   (= 오염 snapshot 노출이 남아 있는 별개 자리 — 이번 범위 밖).
  //   3곳이 되면 이 셀이 깨져 새 복제를 알린다.
  const n = (SRC.match(/\(hh \* 60 \+ mm\) \* 60000/g) || []).length;
  assert.strictEqual(n, 2, `시작시각 공식이 ${n}곳에 있다(기대 2)`);
  const guardFn = cutDecl(SRC, 'function srvResolveGuardShiftStart(');
  assert.ok(!guardFn.includes('* 60000'),
      'guard 는 식을 직접 적지 않고 srvShiftStartMsFrom 을 쓴다');
});

(async () => {
  for (const [id, name, fn] of asyncCells) {
    try {
      await fn();
      pass++;
      console.log(`  ✓ ${id} ${name}`);
    } catch (e) {
      fail++;
      console.log(`  ✗ ${id} ${name}\n      ${e.message}`);
    }
  }
  console.log(`\n[ISG2] ${pass} pass / ${fail} fail`);
  process.exit(fail === 0 ? 0 : 1);
})();
