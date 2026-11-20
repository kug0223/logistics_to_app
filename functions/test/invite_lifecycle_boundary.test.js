/**
 * [INVITE-LIFECYCLE] 이미 발송된 초대의 수명 — 실제 소스 실행.
 *
 *   문제(2026-10-15 READ): 지원 마감 시각에 스케줄러가 업무 closedAt·슬롯
 *   closed(TIME_EXPIRED)를 쓰면 수락 tx 만 거절했고, 동의·검토·카드는 초대
 *   기한(min(+24h, 근무 시작))까지 열려 있었다. 한 단계만 닫힌 창이었다.
 *
 *   계약: 공개 지원 접수의 **자동** 마감은 이미 발송된 초대를 끝내지 않는다.
 *   수동 마감·사유 없는 closed·부모 공고 만료·게시 만료·사업장 비활성·삭제는
 *   계속 끝낸다. 동의·검토·수락이 **같은 함수**(srvInviteRecruitClosureBlock)로
 *   판정한다. 신규 초대는 근무 시작 뒤에 만들지 않는다. 삭제는 관계가 있으면
 *   막혀 INVITED 가 남지 않는다.
 *
 *   index.ts 에서 함수·상수를 원문 그대로 꺼내 실행한다(재구현 아님).
 *
 *     IL-A  모집 종료 판정 행렬(공고·슬롯·업무 × 자동·수동·사유)
 *     IL-B  같은 기한 — 동의(tx)·검토(열람 창)·수락 판정이 같은 시각에 같은 답
 *     IL-C  수락 tx 계약 — 옛 개별 검사가 남지 않고 공통 판정만 쓴다, FULL 은 정원
 *     IL-D  신규 초대 — 근무 시작 경과 거절이 모든 쓰기보다 앞
 *     IL-E  삭제 — 관계 가드가 상태 무관(INVITED 포함)이라 INVITED 가 남지 않는다
 */
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const ts = require('typescript');

const SRC = fs.readFileSync(path.join(__dirname, '..', 'src', 'index.ts'), 'utf8');
const AST = ts.createSourceFile('index.ts', SRC, ts.ScriptTarget.ES2020, true);
const FN_DECLS = new Map();
for (const st of AST.statements) {
  if (ts.isFunctionDeclaration(st) && st.name) FN_DECLS.set(st.name.text, st.getText(AST));
}
const cutFn = (n) => { const t = FN_DECLS.get(n); assert.ok(t, `함수 원문 없음: ${n}`); return t; };
function cutConst(name) {
  const m = new RegExp(`^const\\s+${name}\\b[^=]*=`, 'm').exec(SRC);
  assert.ok(m, `상수 원문 없음: ${name}`);
  let k = m.index + m[0].length; let d = 0;
  for (; k < SRC.length; k++) {
    const c = SRC[k];
    if (c === '"' || c === '\'' || c === '`') { const q = c; k++; while (SRC[k] !== q) { if (SRC[k] === '\\') k++; k++; } continue; }
    if ('([{'.includes(c)) d++; else if (')]}'.includes(c)) d--;
    else if (c === ';' && d === 0) return SRC.slice(m.index, k + 1);
  }
  throw new Error('상수 끝 없음: ' + name);
}
function bodyOfCallable(name) {
  const i = SRC.indexOf(`export const ${name} = onCall(`);
  assert.ok(i >= 0, name);
  return SRC.slice(i, SRC.indexOf('\nexport const ', i + 10));
}

const CONSTS = ['SRV_KST_MS', 'SRV_INTAKE_AUTO_UNIT_REASON', 'SRV_INTAKE_AUTO_TO_REASONS',
  'SRV_INVITE_RECRUIT_ENDED_MESSAGE'];
const FNS = ['srvKstDayStartMs', 'srvShiftStartMsFrom', 'srvIsLongTermInvite',
  'srvResolveGuardShiftStart', 'srvInviteWindowClosed', 'srvInviteRecruitClosureBlock', 'srvToClosedByApplicationDeadline', 'srvInviteUnitBlock', 'srvBusinessSideInviteEndReason',
  'srvInviteReviewWindowOpen', 'srvInviteConsentWindowBlock',
  'srvInviteConsentWindowBlockTx', 'assertNoPostingRelations', 'assertNoSlotRelations',
  'getWorkDetailCount', 'srvInviteUnitProjection'];

class Ts { constructor(ms) { this.ms = ms; } toMillis() { return this.ms; } toDate() { return new Date(this.ms); } }
let STORE = new Map();
let READS = 0;
function ref(p) {
  return {path: p, collection: (c) => ({doc: (d) => ref(`${p}/${c}/${d}`)}),
    get: async () => { READS++; const v = STORE.get(p); return {exists: v !== undefined, data: () => v}; }};
}
function query(col, filters = [], lim = 1e9) {
  return {
    where: (f, op, v) => query(col, [...filters, [f, op, v]], lim),
    limit: (n) => query(col, filters, n),
    get: async () => {
      READS++;
      const docs = [...STORE.entries()]
        .filter(([k]) => k.startsWith(col + '/') && k.split('/').length === 2)
        .filter(([, v]) => filters.every(([f, op, x]) => (op === 'in' ? x.includes(v[f]) : v[f] === x)))
        .slice(0, lim).map(([k, v]) => ({id: k.split('/')[1], data: () => v}));
      return {docs, empty: docs.length === 0, size: docs.length};
    },
  };
}
const db = {collection: (c) => Object.assign(query(c), {doc: (d) => ref(`${c}/${d}`)})};
const tx = {get: async (r) => { const v = STORE.get(r.path); return {exists: v !== undefined, data: () => v}; }};
const admin = {firestore: {Timestamp: {fromMillis: (ms) => new Ts(ms)}}};

const harness = [...CONSTS.map(cutConst), ...FNS.map(cutFn),
  'module.exports = {' + FNS.join(',') + ', SRV_INVITE_RECRUIT_ENDED_MESSAGE};'].join('\n\n');
const js = ts.transpileModule(harness, {compilerOptions: {
  target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS}}).outputText;
const mod = {exports: {}};
class HttpsError extends Error { constructor(code, msg) { super(msg); this.code = code; } }
new Function('module', 'exports', 'db', 'admin', 'console', 'HttpsError', js)(
  mod, mod.exports, db, admin, {error: () => {}, log: () => {}, warn: () => {}}, HttpsError);
const R = mod.exports;

const K = 9 * 3600e3;
const kst = (y, mo, d, h = 0, mi = 0) => Date.UTC(y, mo - 1, d, h, mi) - K;
const DAY = kst(2026, 10, 20);
const START = kst(2026, 10, 20, 20);
const DEADLINE = kst(2026, 10, 20, 19);
const wdOpen = {wdId: 'wd-1', startTime: '20:00', endTime: '22:00', requiredCount: 2};
const SLOT = {date: new Ts(DAY), status: 'open', workDetails: [wdOpen]};
const TO = {status: 'ACTIVE'};
const invite = (o = {}) => Object.assign({
  status: 'INVITED', toId: 't1', slotId: 's1', wdId: 'wd-1', businessId: 'b1', uid: 'w1',
  workDate: new Ts(DAY), startTime: '20:00', endTime: '22:00', type: 'short',
  inviteExpiresAt: new Ts(START),
}, o);
// 스케줄러가 지원 마감에 쓰는 모양(processWorkDetailExpiry)
const autoClosedSlot = () => ({date: new Ts(DAY), status: 'closed', closedReason: 'TIME_EXPIRED',
  workDetails: [Object.assign({}, wdOpen, {closedAt: new Ts(DEADLINE), closedReason: 'TIME_EXPIRED'})]});
const autoClosedTo = () => ({status: 'CLOSED', closedReason: 'ALL_SLOTS_EXPIRED'});

let pass = 0; const fails = [];
async function cell(id, name, fn) {
  try { await fn(); pass++; console.log(`  ok   ${id} ${name}`); } catch (e) {
    fails.push(`${id}: ${e.message.split('\n')[0]}`); console.log(`  FAIL ${id} ${name} — ${e.message.split('\n')[0]}`);
  }
}

(async () => {
  const B = R.srvInviteRecruitClosureBlock;
  const ENDED = R.SRV_INVITE_RECRUIT_ENDED_MESSAGE;

  console.log('[IL-A] 모집 종료 판정 행렬');
  await cell('IL-01', '열린 공고·슬롯·업무 → 진행 가능', () => {
    assert.strictEqual(B(TO, SLOT, 'wd-1'), null);
  });
  await cell('IL-02', '자동 접수 마감(스케줄러 모양) → 진행 가능', () => {
    assert.strictEqual(B(autoClosedTo(), autoClosedSlot(), 'wd-1'), null);
    for (const reason of ['ALL_SLOTS_EXPIRED', 'ALL_WORKDETAILS_CLOSED', 'ALL_CHILDREN_CLOSED']) {
      assert.strictEqual(B({status: 'CLOSED', closedReason: reason}, undefined, undefined), null, reason);
    }
  });
  await cell('IL-03', '공고 수동 마감·사유 없는 CLOSED·그 밖 사유 → 끝', () => {
    assert.strictEqual(B({status: 'CLOSED', isManualClosed: true, closedBy: 'a'}, SLOT, 'wd-1'), ENDED);
    assert.strictEqual(B({status: 'CLOSED', closedReason: 'ALL_SLOTS_EXPIRED', closedBy: 'a'}, SLOT, 'wd-1'), ENDED,
      'closedBy 가 있으면 자동이 아니다');
    assert.strictEqual(B({status: 'CLOSED'}, SLOT, 'wd-1'), ENDED, '사유 없음 → fail-closed');
    for (const reason of ['TIME_EXPIRED', 'BUSINESS_DEACTIVATED', 'INTEGRITY_CHECK', 'ALL_SLOTS_DELETED', 'POSTING_EXPIRED']) {
      assert.strictEqual(B({status: 'CLOSED', closedReason: reason}, SLOT, 'wd-1'), ENDED, reason);
    }
    assert.strictEqual(B({status: 'ACTIVE', isManualClosed: true}, SLOT, 'wd-1'), ENDED);
    assert.strictEqual(B({status: 'POSTING_EXPIRED'}, SLOT, 'wd-1'), ENDED);
    assert.strictEqual(B({status: 'DELETED'}, SLOT, 'wd-1'), ENDED);
  });
  await cell('IL-04', '삭제·없는 공고 → 끝(삭제 문구)', () => {
    assert.match(B(undefined, SLOT, 'wd-1'), /삭제/);
    assert.match(B({status: 'ACTIVE', isDeleted: true}, SLOT, 'wd-1'), /삭제/);
  });
  await cell('IL-05', '슬롯 수동 마감·부모 만료·사유 없음 → 끝', () => {
    assert.strictEqual(B(TO, Object.assign({}, SLOT, {isManualClosed: true, status: 'closed', closedBy: 'a'}), 'wd-1'), ENDED);
    assert.strictEqual(B(TO, Object.assign({}, SLOT, {status: 'closed', closedReason: 'PARENT_TO_EXPIRED'}), 'wd-1'), ENDED);
    assert.strictEqual(B(TO, Object.assign({}, SLOT, {status: 'closed'}), 'wd-1'), ENDED);
    assert.strictEqual(B(TO, Object.assign({}, SLOT, {status: 'closed', closedReason: 'TIME_EXPIRED', closedBy: 'a'}), 'wd-1'), ENDED);
  });
  await cell('IL-06', '업무 수동 마감·다른 사유 closedAt → 끝, 다른 업무의 마감은 무관', () => {
    const wdManual = Object.assign({}, wdOpen, {isManualClosed: true});
    assert.strictEqual(B(TO, Object.assign({}, SLOT, {workDetails: [wdManual]}), 'wd-1'), ENDED);
    const wdParent = Object.assign({}, wdOpen, {closedAt: new Ts(1), closedReason: 'PARENT_TO_CLOSED'});
    assert.strictEqual(B(TO, Object.assign({}, SLOT, {workDetails: [wdParent]}), 'wd-1'), ENDED);
    const other = {wdId: 'wd-2', isManualClosed: true};
    assert.strictEqual(B(TO, Object.assign({}, SLOT, {workDetails: [wdOpen, other]}), 'wd-1'), null);
  });

  console.log('\n[IL-B] 같은 기한 — 동의·검토·수락이 같은 시각에 같은 답');
  const seed = (to, slot) => { STORE = new Map(); READS = 0; if (to) STORE.set('tos/t1', to); if (slot) STORE.set('tos/t1/slots/s1', slot); };
  const answers = async (to, slot, at) => {
    seed(to, slot);
    const consent = await R.srvInviteConsentWindowBlockTx(tx, invite(), at);
    const review = await R.srvInviteReviewWindowOpen(invite(), at);
    // 수락 tx 의 종료 판정은 공통 함수 + 기한(IL-C 가 소스로 확인).
    const accept = B(to, slot, 'wd-1') == null && !R.srvInviteWindowClosed(invite(), at);
    return {consent: consent == null, review, accept};
  };
  for (const c of [
    {id: 'IL-07', name: '지원 마감 전(18:59) — 셋 다 열림', to: TO, slot: SLOT, at: kst(2026, 10, 20, 18, 59), open: true},
    {id: 'IL-08', name: '자동 접수 마감 후(19:30, closedAt 저장됨) — 셋 다 열림', to: autoClosedTo(), slot: autoClosedSlot(), at: kst(2026, 10, 20, 19, 30), open: true},
    {id: 'IL-09', name: '근무 시작(20:00) — 셋 다 닫힘', to: autoClosedTo(), slot: autoClosedSlot(), at: START, open: false},
    {id: 'IL-10', name: '관리자 수동 마감(19:30) — 셋 다 닫힘', to: TO,
      slot: Object.assign({}, SLOT, {isManualClosed: true, status: 'closed', closedBy: 'a'}), at: kst(2026, 10, 20, 19, 30), open: false},
    {id: 'IL-11', name: '공고 삭제(19:30) — 셋 다 닫힘', to: {status: 'ACTIVE', isDeleted: true}, slot: SLOT, at: kst(2026, 10, 20, 19, 30), open: false},
  ]) {
    await cell(c.id, c.name, async () => {
      const a = await answers(c.to, c.slot, c.at);
      assert.deepStrictEqual(a, {consent: c.open, review: c.open, accept: c.open});
    });
  }
  await cell('IL-12', '동의 거절 사유는 모집 종료 문구(기한 문구와 구분)', async () => {
    seed(TO, Object.assign({}, SLOT, {isManualClosed: true, status: 'closed', closedBy: 'a'}));
    assert.strictEqual(await R.srvInviteConsentWindowBlockTx(tx, invite(), kst(2026, 10, 20, 19, 30)), ENDED);
  });
  await cell('IL-13', '장기 초대 — 공고 수동 마감이면 검토 창도 닫힌다', async () => {
    seed({status: 'CLOSED', isManualClosed: true, closedBy: 'a'}, null);
    const lt = invite({slotId: undefined, type: 'long_term', workDays: ['월']});
    assert.strictEqual(await R.srvInviteReviewWindowOpen(lt, kst(2026, 10, 20, 10)), false);
    seed({status: 'ACTIVE'}, null);
    assert.strictEqual(await R.srvInviteReviewWindowOpen(lt, kst(2026, 10, 20, 10)), true);
  });

  console.log('\n[IL-C] 수락 tx 계약');
  const accept = bodyOfCallable('callableAcceptTOInvitation');
  await cell('IL-14', '옛 개별 종료 검사가 남지 않고 공통 판정을 두 번(공고·슬롯) 쓴다', () => {
    assert.ok(!accept.includes('const invalidStatuses = ["CLOSED", "POSTING_EXPIRED", "DELETED", "FULL"]'));
    assert.ok(!/freshSlotData\.status === "closed"/.test(accept));
    assert.ok(!/acceptWd\["closedAt"\] != null/.test(accept));
    assert.strictEqual((accept.match(/srvInviteRecruitClosureBlock\(/g) || []).length, 2);
    assert.ok(/srvInviteRecruitClosureBlock\(\s*freshToData, freshSlotData as Record<string, unknown>, acceptWdId\)/.test(accept));
  });
  await cell('IL-15', '[INVITE-CAPACITY] 공고 FULL·합계 가드는 슬롯 없는 공고에만 — 슬롯 초대는 단위 가드', () => {
    assert.ok(/if \(freshToStatus === "FULL" && !acceptIsSlotBased\) \{\s*throw new HttpsError/.test(accept));
    assert.ok(/if \(!acceptIsSlotBased && toRequired > 0 && toConfirmed >= toRequired\)/.test(accept));
    // 대체 불변식: 슬롯 합계·업무 정원 가드가 남아 있다
    assert.ok(accept.includes('if (slotTotalReq > 0 && slotConfirmed >= slotTotalReq)'));
    assert.ok(accept.includes('if (wtReq > 0 && wtConf >= wtReq)'));
  });
  await cell('IL-16', '정원·충돌·기한 검사는 그대로 있다(완화한 것은 자동 마감뿐)', () => {
    for (const s of ['슬롯 정원이 초과되어 초대를 수락할 수 없습니다.', 'const freshExp =', '[ISG2-BLOCK-START]',
      'srvCollectSeatCommitOverlap(tx, {']) {
      assert.ok(accept.includes(s), s);
    }
  });

  console.log('\n[IL-D] 신규 초대 — 근무 시작 경과');
  const inv = bodyOfCallable('callableInviteWorker');
  await cell('IL-17', '시작 경과 거절이 첫 쓰기(트랜잭션)보다 앞', () => {
    const guard = inv.indexOf('if (inviteShiftStartMs != null && Date.now() >= inviteShiftStartMs)');
    const firstWrite = inv.indexOf('await db.runTransaction(');
    assert.ok(guard > 0 && firstWrite > 0 && guard < firstWrite);
    assert.ok(inv.includes('"근무가 이미 시작되어 초대할 수 없습니다."'));
  });
  await cell('IL-18', '장기 초대는 이 검사 대상이 아니다(시작 시각 null)', () => {
    assert.ok(/const inviteShiftStartMs = isLong \?\s*null :/.test(inv));
  });

  console.log('\n[IL-E] 삭제 — INVITED 가 남지 않는다');
  await cell('IL-19', '공고 삭제 가드: INVITED 한 건이면 막힌다(상태 무관)', async () => {
    STORE = new Map();
    STORE.set('applications/a1', {toId: 't1', businessId: 'b1', status: 'INVITED'});
    assert.deepStrictEqual(await R.assertNoPostingRelations('t1', 'b1'), {blocked: true, reason: 'APPLICATION_EXISTS'});
    STORE = new Map();
    assert.deepStrictEqual(await R.assertNoPostingRelations('t1', 'b1'), {blocked: false, reason: ''});
  });
  await cell('IL-20', '슬롯 삭제 가드: 그 슬롯의 INVITED 한 건이면 막힌다', async () => {
    STORE = new Map();
    STORE.set('applications/a1', {toId: 't1', businessId: 'b1', slotId: 's1', status: 'INVITED'});
    const r = await R.assertNoSlotRelations('t1', 'b1', ['s1'], []);
    assert.strictEqual(r.blocked, true);
    assert.strictEqual(r.reason, 'APPLICATION_EXISTS');
  });
  await cell('IL-21', '두 삭제 callable 이 쓰기 전에 가드를 부른다', () => {
    const del = bodyOfCallable('callableDeleteTO');
    assert.ok(del.indexOf('await assertNoPostingRelations(') < del.indexOf('batch.update('));
    const delSlots = bodyOfCallable('callableDeleteSlots');
    assert.ok(delSlots.includes('await assertNoSlotRelations('));
  });

  console.log('\n[IL-F] 초대 단위 투영 — 근로자 목록·관리자 명단이 수락 tx 와 같은 답');
  const P = R.srvInviteUnitProjection;
  const counted = (slot, conf) => Object.assign({}, slot, {confirmedCount: conf,
    workDetailCounts: {'wd-1': {confirmedCount: conf, pendingCount: 1}}});
  await cell('IL-22', '열린 단위 → available, 공개 접수 열림', () => {
    assert.deepStrictEqual(P(TO, counted(SLOT, 0), 'wd-1'), {state: 'available', endedReason: null, publicIntakeClosed: false});
  });
  await cell('IL-23', '자동 접수 마감 → closed 가 아니라 available + publicIntakeClosed', () => {
    assert.deepStrictEqual(P(autoClosedTo(), counted(autoClosedSlot(), 0), 'wd-1'),
      {state: 'available', endedReason: null, publicIntakeClosed: true});
  });
  await cell('IL-24', '자동 마감이어도 단위 정원이 차면 full(초대는 끝나지 않음)', () => {
    assert.strictEqual(P(autoClosedTo(), counted(autoClosedSlot(), 2), 'wd-1').state, 'full');
  });
  await cell('IL-25', '수동 마감·비활성·사유 없음 → closed(RECRUIT_ENDED), 삭제 → closed(POSTING_DELETED)', () => {
    assert.deepStrictEqual(P(TO, counted(Object.assign({}, SLOT, {status: 'closed', isManualClosed: true, closedBy: 'a'}), 0), 'wd-1'),
      {state: 'closed', endedReason: 'RECRUIT_ENDED', publicIntakeClosed: true});
    assert.strictEqual(P({status: 'CLOSED', closedReason: 'BUSINESS_DEACTIVATED'}, counted(SLOT, 0), 'wd-1').endedReason, 'RECRUIT_ENDED');
    assert.strictEqual(P({status: 'CLOSED'}, counted(SLOT, 0), 'wd-1').state, 'closed');
    assert.strictEqual(P(undefined, counted(SLOT, 0), 'wd-1').endedReason, 'POSTING_DELETED');
  });
  await cell('IL-26', '공고 FULL 은 초대 투영에 쓰지 않는다(단위 자리 있으면 available)', () => {
    assert.strictEqual(P({status: 'FULL'}, counted(SLOT, 0), 'wd-1').state, 'available');
  });
  await cell('IL-27', '슬롯 없음·업무 없음·카운터 누락 → unknown(목록 전체를 실패로 만들지 않는다)', () => {
    assert.strictEqual(P(TO, undefined, 'wd-1').state, 'unknown');
    assert.strictEqual(P(TO, counted(SLOT, 0), 'wd-x').state, 'unknown');
    assert.strictEqual(P(TO, SLOT, 'wd-1').state, 'unknown');
  });
  await cell('IL-28', '투영과 수락 판정이 같은 종료 함수를 쓴다(종료 행렬 전 칸 일치)', () => {
    const tos = [TO, autoClosedTo(), {status: 'CLOSED'}, {status: 'CLOSED', isManualClosed: true, closedBy: 'a'},
      {status: 'CLOSED', closedReason: 'TIME_EXPIRED'}, {status: 'POSTING_EXPIRED'}, undefined];
    const slots = [counted(SLOT, 0), counted(autoClosedSlot(), 0),
      counted(Object.assign({}, SLOT, {status: 'closed', closedReason: 'PARENT_TO_EXPIRED'}), 0)];
    for (const t of tos) for (const s of slots) {
      assert.strictEqual(P(t, s, 'wd-1').state === 'closed', B(t, s, 'wd-1') != null, JSON.stringify([t, s.status]));
    }
  });
  await cell('IL-29', '근로자 목록 응답이 투영 함수를 쓰고, 공고 문서를 읽는다', () => {
    const gm = bodyOfCallable('callableGetMyApplications');
    assert.ok(gm.includes('srvInviteUnitProjection('));
    assert.ok(gm.includes('db.collection("tos").doc(id).get()'));
    assert.ok(gm.includes('publicIntakeClosed: intakeClosedSet.has(d.id)'));
    assert.ok(!/sd\["status"\] === "closed"\) \{\s*capStateMap\[d\.id\] = "closed"/.test(gm), '옛 사유 무관 closed 투영이 남아 있다');
  });
  await cell('IL-30', '관리자 날짜별 row 가 초대 종료를 따로 싣는다', () => {
    const ds = bodyOfCallable('callableGetDayStaffingDetail');
    assert.ok(ds.includes('inviteEnded: srvInviteRecruitClosureBlock(to.data, sd, wdId) != null'));
  });

  console.log('\n[IL-G] 공고 단위 지원 마감(applicationDeadline) — 출처까지 맞을 때만 자동 접수 마감');
  const DL = kst(2026, 10, 19, 23);
  const deadlineTo = (o = {}) => Object.assign({status: 'CLOSED', closedReason: 'TIME_EXPIRED',
    applicationDeadline: new Ts(DL), closedAt: new Ts(DL + 60e3)}, o);
  const parentSlot = () => counted(Object.assign({}, SLOT, {status: 'closed', closedReason: 'PARENT_TO_EXPIRED',
    workDetails: [Object.assign({}, wdOpen, {closedAt: new Ts(DL + 60e3), closedReason: 'PARENT_TO_CLOSED'})]}), 0);
  await cell('IL-31', 'processTOExpiry 모양(TIME_EXPIRED + deadline ≤ closedAt, closedBy 없음) → 초대 유효', () => {
    assert.strictEqual(R.srvToClosedByApplicationDeadline(deadlineTo()), true);
    assert.strictEqual(B(deadlineTo(), parentSlot(), 'wd-1'), null);
    assert.deepStrictEqual(P(deadlineTo(), parentSlot(), 'wd-1'),
      {state: 'available', endedReason: null, publicIntakeClosed: true});
  });
  await cell('IL-32', '출처가 다르거나 모르면 막는다 — deadline 없음·closedAt<deadline·closedBy·수동·INTEGRITY_CHECK·사유 없음', () => {
    for (const t of [deadlineTo({applicationDeadline: undefined}), deadlineTo({closedAt: new Ts(DL - 60e3)}),
      deadlineTo({closedBy: 'a'}), deadlineTo({isManualClosed: true}), deadlineTo({closedReason: 'INTEGRITY_CHECK'}),
      deadlineTo({closedReason: undefined})]) {
      assert.strictEqual(B(t, parentSlot(), 'wd-1'), ENDED, JSON.stringify(Object.keys(t)));
    }
  });
  await cell('IL-33', 'PARENT_TO_EXPIRED·PARENT_TO_CLOSED 는 부모가 공고 지원 마감일 때만 자동', () => {
    assert.strictEqual(B(TO, parentSlot(), 'wd-1'), ENDED, '열린 공고 아래의 PARENT_TO_EXPIRED 는 출처 불명');
    assert.strictEqual(B({status: 'CLOSED', closedReason: 'ALL_SLOTS_EXPIRED'}, parentSlot(), 'wd-1'), ENDED);
  });

  console.log('\n[IL-H] 새 초대가 들어갈 자리 — 수락과 같은 판정');
  const U = R.srvInviteUnitBlock;
  await cell('IL-34', '자동 접수 마감 후 자리 있음 → 보낼 수 있다(근무 시작은 writer 가 따로 본다)', () => {
    assert.strictEqual(U(autoClosedTo(), counted(autoClosedSlot(), 0), 'wd-1'), null);
    assert.strictEqual(U(deadlineTo(), parentSlot(), 'wd-1'), null);
  });
  await cell('IL-35', '수동 마감·비활성·사유 불명 → 막음, 정원 소진 → 막음, 카운터 없음 → 막음', () => {
    assert.match(U(TO, counted(Object.assign({}, SLOT, {status: 'closed', isManualClosed: true, closedBy: 'a'}), 0), 'wd-1'), /모집이 종료/);
    assert.match(U({status: 'CLOSED', closedReason: 'BUSINESS_DEACTIVATED'}, counted(SLOT, 0), 'wd-1'), /모집이 종료/);
    assert.match(U({status: 'CLOSED'}, counted(SLOT, 0), 'wd-1'), /모집이 종료/);
    assert.match(U(autoClosedTo(), counted(autoClosedSlot(), 2), 'wd-1'), /정원이 찬/);
    assert.match(U(TO, SLOT, 'wd-1'), /인원 정보/);
    assert.match(U(TO, counted(SLOT, 0), 'wd-x'), /찾을 수 없/);
  });
  await cell('IL-36', '새 초대 writer 가 같은 판정을 사전·트랜잭션 안에서 두 번 쓴다', () => {
    const inv = bodyOfCallable('callableInviteWorker');
    assert.ok(inv.includes('if (srvInviteRecruitClosureBlock(toData, undefined, undefined) != null)'));
    assert.ok(inv.includes('srvInviteUnitBlock(toData, inviteSlotData, inviteResolvedWdId)'));
    assert.ok(inv.includes('srvInviteUnitBlock(txTo.data()!, txSlot.data()!, inviteResolvedWdId)'));
    assert.ok(/if \(toStatus === "FULL" && !inviteIsSlotBased\)/.test(inv));
    assert.ok(!inv.includes('const closedStatuses = ["CLOSED", "POSTING_EXPIRED", "DELETED"];'), '옛 사유 무관 CLOSED 차단이 남았다');
    const tx = inv.indexOf('await db.runTransaction(');
    assert.ok(inv.indexOf('srvInviteUnitBlock(txTo.data()!', tx) > tx, '재검증이 트랜잭션 안에 있다');
    assert.ok(inv.indexOf('srvInviteUnitBlock(txTo.data()!', tx) < inv.indexOf('invTx.set(newAppRef', tx), '쓰기보다 앞');
  });

  console.log('\n[IL-I] 사업장 쪽 종료 사유 — 아는 것만 철회한다');
  const E = R.srvBusinessSideInviteEndReason;
  await cell('IL-37', '삭제·비활성·수동 → 사유 코드, 자동·사유 없음·INTEGRITY_CHECK → null(철회 안 함)', () => {
    assert.strictEqual(E({status: 'ACTIVE', isDeleted: true}), 'TO_DELETED');
    assert.strictEqual(E({status: 'CLOSED', closedReason: 'BUSINESS_DEACTIVATED'}), 'BUSINESS_DEACTIVATED');
    assert.strictEqual(E({status: 'CLOSED', isManualClosed: true, closedBy: 'a'}), 'RECRUIT_CLOSED');
    for (const t of [autoClosedTo(), deadlineTo(), {status: 'CLOSED'}, {status: 'CLOSED', closedReason: 'INTEGRITY_CHECK'}]) {
      assert.strictEqual(E(t), null, JSON.stringify(t));
    }
  });

  console.log(`\n통과 ${pass} / 실패 ${fails.length}`);
  if (fails.length) { for (const f of fails) console.log('  - ' + f); process.exit(1); }
})();
