/**
 * [R7-DEV-CONTROLLED-GOLDEN-PATH.1 잔여 무결성] 두 계약을 실제 함수로 검증한다.
 *
 *   ① 슬롯 모집 상태(open↔full)의 주인은 카운터를 센 그 트랜잭션이다.
 *      DEV 실측 결함: 트리거 두 번이 겹치면 **낡은 스냅샷이 slot.status만**
 *      open 으로 덮었다(TO 합계는 fence 가 막았다). 그 경쟁을 그대로 재현한다.
 *
 *   ② 아직 시작하지 않은 근무는 노쇼가 아니다.
 *      DEV 실측 결함: 23:50 근무를 23:01 에 NO_SHOW + finalWage 0 으로 썼다.
 *      경계 = **예정 시작 + 사업장 지각 유예(`lateGrace`, 기본 5분)**.
 *      근로자 취소 정책의 "예정 시작 5분 **전**" 기준을 빌려 쓰지 않는다 —
 *      그러면 시작도 안 한 근무를 미출근으로 확정할 수 있다. 두 사건은 다르다:
 *      취소는 스스로 약속을 깬 것이고, 노쇼는 오기로 한 시각에 오지 않은 것이다.
 *      (5분 전 cutoff 의 주인은 `callableCancelConfirmedApplication` 이다.)
 *
 *   production 로직은 손대지 않는다. 바꾸는 것은 스케줄과 시계뿐이다.
 *   격리: demo 프로젝트. 공유 DEV/PROD 쓰기 0.
 */
'use strict';

const PROJECT = 'demo-r7slotns';
process.env.GCLOUD_PROJECT = PROJECT;
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:6060';

const fs = require('fs');
const path = require('path');
const ROOT = path.join(__dirname, '..');
const admin = require(path.join(ROOT, 'functions', 'node_modules', 'firebase-admin'));
if (!admin.apps.length) admin.initializeApp({projectId: PROJECT});
const realDb = admin.firestore();
const T = admin.firestore.Timestamp;

let fail = 0;
const rows = [];
function check(label, actual, expected, note) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) fail++;
  rows.push({label, ok});
  console.log(`  [${ok ? 'PASS' : 'FAIL'}] ${label}` +
    (ok ? '' : `  기대=${JSON.stringify(expected)} 실제=${JSON.stringify(actual)}`) +
    (note ? `  ${note}` : ''));
}

// ── 주입: transaction 직전 hook + 가짜 시계 ──────────────────────
let txCount = 0; let txHook = null; let hookDepth = 0;
const db = new Proxy(realDb, {
  get(t, p) {
    if (p === 'runTransaction') {
      return async (fn, opts) => {
        if (hookDepth === 0) {
          txCount++;
          if (txHook && txCount === txHook.at) {
            const h = txHook.fn; txHook = null;
            hookDepth++;
            try { await h(); } finally { hookDepth--; }
          }
        }
        return t.runTransaction(fn, opts);
      };
    }
    const v = t[p];
    return typeof v === 'function' ? v.bind(t) : v;
  },
});
const armHook = (at, fn) => { txCount = 0; txHook = {at, fn}; };
const disarm = () => { txCount = 0; txHook = null; };

// 시계는 **production 슬라이스 안에서만** 바꾼다.
//   전역 Date 를 갈아끼우면 gRPC 가 deadline 을 만들 때 깨진다(실측).
//   그래서 생성 함수의 인자 이름으로 `Date` 를 가려 그 범위에만 적용한다.
let nowOverride = null;
const RealDate = Date;
class FakeDate extends RealDate {
  constructor(...a) {
    super(...(a.length ? a : [nowOverride ?? RealDate.now()]));
  }
  static now() { return nowOverride ?? RealDate.now(); }
  static UTC(...a) { return RealDate.UTC(...a); }
  static parse(...a) { return RealDate.parse(...a); }
}

// ── production 슬라이스 ─────────────────────────────────────────
const SRC = fs.readFileSync(path.join(ROOT, 'functions', 'lib', 'index.js'), 'utf8');
const LINES = SRC.split('\n');
function sliceFn(name) {
  const i = LINES.findIndex((l) =>
    l.startsWith(`function ${name}(`) || l.startsWith(`async function ${name}(`));
  if (i < 0) throw new Error(`함수 없음: ${name}`);
  const j = LINES.findIndex((l, k) => k > i && l === '}');
  return LINES.slice(i, j + 1).join('\n');
}
function sliceExport(name) {
  const i = LINES.findIndex((l) => l.startsWith(`exports.${name} = `));
  if (i < 0) throw new Error(`export 없음: ${name}`);
  const j = LINES.findIndex((l, k) => k > i && l === '});');
  return LINES.slice(i, j + 1).join('\n').replace(`exports.${name} = `, `const ${name} = `);
}
const sliceConst = (decl) => {
  const line = LINES.find((l) => l.startsWith(decl));
  if (!line) throw new Error(`상수 없음: ${decl}`);
  return line;
};
/** 여러 줄 선언(배열·객체 리터럴) — 닫는 `];`/`};` 까지 가져온다. */
const sliceBlockConst = (decl) => {
  const i = LINES.findIndex((l) => l.startsWith(decl));
  if (i < 0) throw new Error(`상수 없음: ${decl}`);
  const j = LINES.findIndex((l, k) => k > i && /^(\];|\};)$/.test(l.trim()));
  return LINES.slice(i, j + 1).join('\n');
};

class HttpsError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}
const PRELUDE = `
const Timestamp = admin.firestore.Timestamp;
const https_1 = {HttpsError, onCall: (cfg, h) => h};
const firestore_1 = {onDocumentWritten: (cfg, h) => h};
const commitment_dates_1 = commitmentDates;
`;
const BODY = [
  PRELUDE,
  sliceConst('const PENDING_STATUSES'),
  sliceConst('const CONFIRMED_STATUSES'),
  sliceConst('const IMMUTABLE_TO_STATUSES'),
  sliceBlockConst('const ATTENDANCE_POLICY_MATERIAL_FIELDS'),
  sliceBlockConst('const ATTENDANCE_POLICY_DEFAULTS'),
  sliceFn('srvAttendancePolicyValue'),
  sliceFn('srvEffectiveAttendanceRules'),
  sliceFn('srvNoShowJudgeableFromMs'),
  sliceFn('srvKstDateNum'),
  sliceFn('srvKstWeekdayKo'),
  sliceFn('srvOccupiesSeatToday'),
  sliceFn('srvTsAtLeast'),
  sliceFn('srvEarliestReadAt'),
  sliceFn('srvCommitToTotals'),
  sliceFn('srvSyncToStatusSafely'),
  sliceFn('srvResolveAppWdId'),
  sliceFn('srvBuildWdCountsUpdate'),
  sliceFn('srvSyncSlotCountersTx'),
  sliceFn('_syncTOCounters'),
  sliceConst('const srvLongTermEligibleOnDay'),
  sliceFn('_resolveAttendanceWorkContext'),
  sliceFn('assertBizAdmin'),
  sliceFn('srvShiftStartMsFrom'),
  sliceFn('srvResolveShiftStartMs'),
  sliceExport('syncTOStats'),
  sliceExport('callableBatchSetNoShow'),
  `return {_syncTOCounters, srvSyncSlotCountersTx, syncTOStats,
    callableBatchSetNoShow, srvResolveShiftStartMs};`,
].join('\n');
const commitmentDates =
  require(path.join(ROOT, 'functions', 'lib', 'commitment_dates.js'));
// eslint-disable-next-line no-new-func
const P = new Function('db', 'admin', 'HttpsError', 'commitmentDates', 'Date', BODY)(
    db, admin, HttpsError, commitmentDates, FakeDate);

// ── fixture ────────────────────────────────────────────────────
const BIZ = 'biz_slotns';
const ADMIN_UID = 'admin_slotns';
const KST = 9 * 36e5;
const kstMidnightMs = (ms) => {
  const d = new RealDate(ms + KST);
  return RealDate.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()) - KST;
};
const wipe = async (col) => {
  const s = await realDb.collection(col).get();
  await Promise.all(s.docs.map((d) => d.ref.delete()));
};
async function resetAll() {
  for (const c of ['tos', 'applications', 'attendance', 'users', 'businesses']) {
    const s = await realDb.collection(c).get();
    for (const d of s.docs) {
      const subs = await d.ref.listCollections();
      for (const sub of subs) {
        const ss = await sub.get();
        await Promise.all(ss.docs.map((x) => x.ref.delete()));
      }
      await d.ref.delete();
    }
  }
  await realDb.collection('users').doc(ADMIN_UID).set({role: 'BUSINESS_ADMIN'});
  await realDb.collection('businesses').doc(BIZ).set(
      {ownerId: ADMIN_UID, adminIds: [ADMIN_UID], name: 'QA 사업장'});
}

/** 단일 슬롯·단일/복수 업무 공고를 만든다. wds: [{wdId, required, start, end}] */
async function mkTO(toId, slotId, wds, dayMs, opts = {}) {
  await realDb.collection('tos').doc(toId).set({
    businessId: BIZ, type: 'flex', status: opts.toStatus ?? 'ACTIVE',
    totalRequired: wds.reduce((a, w) => a + w.required, 0),
    totalConfirmed: 0, totalPending: 0,
    isManualClosed: false, isDeleted: false,
  });
  await realDb.collection('tos').doc(toId).collection('slots').doc(slotId).set({
    date: T.fromMillis(dayMs), status: opts.slotStatus ?? 'open',
    isManualClosed: opts.isManualClosed ?? false,
    confirmedCount: 0, pendingCount: 0,
    workDetails: wds.map((w) => ({
      wdId: w.wdId, requiredCount: w.required, workType: w.type ?? 'QA',
      startTime: w.start ?? '09:00', endTime: w.end ?? '18:00',
    })),
    workDetailCounts: Object.fromEntries(
        wds.map((w) => [w.wdId, {confirmedCount: 0, pendingCount: 0}])),
  });
}
async function mkApp(id, toId, slotId, wdId, uid, status, dayMs, extra = {}) {
  await realDb.collection('applications').doc(id).set(Object.assign({
    toId, slotId, wdId, uid, userId: uid, businessId: BIZ, status, type: 'short',
    workDate: T.fromMillis(dayMs), selectedWorkType: 'QA',
    startTime: extra.startTime ?? '09:00', endTime: '18:00',
  }, extra));
}
const slotOf = async (toId, slotId) =>
  (await realDb.collection('tos').doc(toId).collection('slots').doc(slotId).get()).data();
const toOf = async (toId) => (await realDb.collection('tos').doc(toId).get()).data();
const shape = async (toId, slotId, wdId) => {
  const s = await slotOf(toId, slotId); const t = await toOf(toId);
  return {toStatus: t.status, toConf: t.totalConfirmed, slotStatus: s.status,
    slotConf: s.confirmedCount, wdcConf: s.workDetailCounts[wdId].confirmedCount};
};

(async () => {
  console.log('\n════ ① 슬롯 모집 상태 — 확정 경로별 동일성 ════\n');
  const DAY = kstMidnightMs(RealDate.now());

  // 1. 초대 수락으로 정원 충족
  await resetAll();
  await mkTO('to1', 's1', [{wdId: 'w1', required: 1}], DAY);
  await mkApp('a1', 'to1', 's1', 'w1', 'u1', 'CONFIRMED', DAY, {invitedAt: T.now()});
  await P._syncTOCounters('to1', 's1');
  check('1. 초대 수락 정원 충족 → TO·slot·wdc 전부 FULL',
      await shape('to1', 's1', 'w1'),
      {toStatus: 'FULL', toConf: 1, slotStatus: 'full', slotConf: 1, wdcConf: 1});

  // 2. 직접 확정(CONTRACT_PENDING 좌석)으로 정원 충족 — 같은 사건, 같은 결과
  await resetAll();
  await mkTO('to2', 's2', [{wdId: 'w1', required: 1}], DAY);
  await mkApp('a2', 'to2', 's2', 'w1', 'u1', 'CONTRACT_PENDING', DAY);
  await P._syncTOCounters('to2', 's2');
  check('2. 직접 확정 정원 충족 → 동일 결과',
      await shape('to2', 's2', 'w1'),
      {toStatus: 'FULL', toConf: 1, slotStatus: 'full', slotConf: 1, wdcConf: 1});

  // 3. 정원 미충족 → open 유지
  await resetAll();
  await mkTO('to3', 's3', [{wdId: 'w1', required: 2}], DAY);
  await mkApp('a3', 'to3', 's3', 'w1', 'u1', 'CONFIRMED', DAY);
  await P._syncTOCounters('to3', 's3');
  check('3. 인원 부족 → slot open 유지',
      await shape('to3', 's3', 'w1'),
      {toStatus: 'ACTIVE', toConf: 1, slotStatus: 'open', slotConf: 1, wdcConf: 1});

  // 4. 확정 취소 → 재개방
  await resetAll();
  await mkTO('to4', 's4', [{wdId: 'w1', required: 1}], DAY, {slotStatus: 'full'});
  await mkApp('a4', 'to4', 's4', 'w1', 'u1', 'CANCELED', DAY);
  await P._syncTOCounters('to4', 's4');
  check('4. 확정 취소 → slot 재개방',
      await shape('to4', 's4', 'w1'),
      {toStatus: 'ACTIVE', toConf: 0, slotStatus: 'open', slotConf: 0, wdcConf: 0});

  // 5. NO_SHOW 좌석 반납 → 재개방 (status 는 CONFIRMED 그대로)
  await resetAll();
  await mkTO('to5', 's5', [{wdId: 'w1', required: 1}], DAY, {slotStatus: 'full'});
  await mkApp('a5', 'to5', 's5', 'w1', 'u1', 'CONFIRMED', DAY,
      {staffingReleasedAt: T.now()});
  await P._syncTOCounters('to5', 's5');
  check('5. 좌석 반납 → 재개방 (이력 보존)',
      await shape('to5', 's5', 'w1'),
      {toStatus: 'ACTIVE', toConf: 0, slotStatus: 'open', slotConf: 0, wdcConf: 0});

  // 6. 대체충원 → 다시 FULL (반납 건은 세지 않는다)
  await mkApp('a5b', 'to5', 's5', 'w1', 'u2', 'CONFIRMED', DAY, {invitedAt: T.now()});
  await P._syncTOCounters('to5', 's5');
  check('6. 대체충원 → FULL · 반납 건 제외',
      await shape('to5', 's5', 'w1'),
      {toStatus: 'FULL', toConf: 1, slotStatus: 'full', slotConf: 1, wdcConf: 1});

  // 7. 같은 날짜 여러 업무 중 일부만 충족
  await resetAll();
  await mkTO('to7', 's7', [{wdId: 'wA', required: 1}, {wdId: 'wB', required: 2}], DAY);
  await mkApp('a7', 'to7', 's7', 'wA', 'u1', 'CONFIRMED', DAY);
  await P._syncTOCounters('to7', 's7');
  {
    const s = await slotOf('to7', 's7');
    check('7. 업무 일부만 충족 → 슬롯 전체는 open',
        {slotStatus: s.status, wA: s.workDetailCounts.wA.confirmedCount,
          wB: s.workDetailCounts.wB.confirmedCount},
        {slotStatus: 'open', wA: 1, wB: 0});
  }

  // 8. 여러 날짜의 FULL/부족 혼재 — 날짜별 독립
  await resetAll();
  const DAY2 = DAY + 864e5;
  await mkTO('to8', 's8a', [{wdId: 'w1', required: 1}], DAY);
  await realDb.collection('tos').doc('to8').collection('slots').doc('s8b').set({
    date: T.fromMillis(DAY2), status: 'open', isManualClosed: false,
    confirmedCount: 0, pendingCount: 0,
    workDetails: [{wdId: 'w2', requiredCount: 2, workType: 'QA',
      startTime: '09:00', endTime: '18:00'}],
    workDetailCounts: {w2: {confirmedCount: 0, pendingCount: 0}},
  });
  await realDb.collection('tos').doc('to8').update({totalRequired: 3});
  await mkApp('a8a', 'to8', 's8a', 'w1', 'u1', 'CONFIRMED', DAY);
  await mkApp('a8b', 'to8', 's8b', 'w2', 'u2', 'CONFIRMED', DAY2);
  await P._syncTOCounters('to8', 's8a');
  await P._syncTOCounters('to8', 's8b');
  check('8. 날짜별 FULL/부족 독립',
      {a: (await slotOf('to8', 's8a')).status, b: (await slotOf('to8', 's8b')).status},
      {a: 'full', b: 'open'});

  // 9. 중복 수락(재집계 반복) → 좌석·상태 재증가 없음
  await resetAll();
  await mkTO('to9', 's9', [{wdId: 'w1', required: 1}], DAY);
  await mkApp('a9', 'to9', 's9', 'w1', 'u1', 'CONFIRMED', DAY);
  for (let i = 0; i < 3; i++) await P._syncTOCounters('to9', 's9');
  check('9. 재집계 3회 → 좌석 1 유지(멱등)',
      await shape('to9', 's9', 'w1'),
      {toStatus: 'FULL', toConf: 1, slotStatus: 'full', slotConf: 1, wdcConf: 1});

  // 10. ★ 낡은 트리거 실행이 최신 FULL 을 open 으로 덮지 못한다 (실측 결함 재현)
  await resetAll();
  await mkTO('to10', 's10', [{wdId: 'w1', required: 1}], DAY);
  // run B 가 "지원서 없음"을 읽은 뒤, 커밋 전에 수락이 일어나고 run A 가 먼저 끝난다.
  armHook(1, async () => {
    await mkApp('a10', 'to10', 's10', 'w1', 'u1', 'CONFIRMED', DAY,
        {invitedAt: T.now()});
    disarm();
    await P._syncTOCounters('to10', 's10'); // run A — 최신 읽기
  });
  await P._syncTOCounters('to10', 's10'); // run B — 낡은 읽기
  disarm();
  check('10. 낡은 실행이 slot.status 를 되돌리지 않는다',
      await shape('to10', 's10', 'w1'),
      {toStatus: 'FULL', toConf: 1, slotStatus: 'full', slotConf: 1, wdcConf: 1});

  // 11. 사람이 마감한 슬롯은 집계가 건드리지 않는다
  await resetAll();
  await mkTO('to11', 's11', [{wdId: 'w1', required: 2}], DAY,
      {slotStatus: 'closed', isManualClosed: true});
  await mkApp('a11', 'to11', 's11', 'w1', 'u1', 'CONFIRMED', DAY);
  await P._syncTOCounters('to11', 's11');
  check('11. 수동 마감 슬롯 → closed 유지', (await slotOf('to11', 's11')).status, 'closed');

  // 12. 트리거 가드 — 좌석 표식만 바뀐 쓰기도 재집계를 깨운다
  await resetAll();
  await mkTO('to12', 's12', [{wdId: 'w1', required: 1}], DAY, {slotStatus: 'full'});
  await mkApp('a12', 'to12', 's12', 'w1', 'u1', 'CONFIRMED', DAY,
      {staffingReleasedAt: T.now()});
  const appSnap = await realDb.collection('applications').doc('a12').get();
  await P.syncTOStats({data: {
    before: {data: () => Object.assign({}, appSnap.data(), {staffingReleasedAt: null})},
    after: {data: () => appSnap.data()},
  }});
  check('12. 트리거: 반납 표식 변화 → 재개방', (await slotOf('to12', 's12')).status, 'open');

  console.log('\n════ ② 수동 NO_SHOW 시간 경계 ════\n');
  const callNoShow = (uid, entries, bizId) => P.callableBatchSetNoShow({
    auth: {uid}, data: {businessId: bizId ?? BIZ, entries},
  });
  const nsEntry = (appId, uid, dayMs, extra = {}) => Object.assign({
    applicationId: appId, workDateMs: dayMs, userId: uid,
    businessName: 'QA 사업장', workType: 'QA',
  }, extra);
  const attOf = async (id) => {
    const d = await realDb.collection('attendance').doc(id).get();
    return d.exists ? d.data() : null;
  };
  // 근무일 = 오늘(KST), 근무 23:50~23:59
  const setupShift = async (tag, start, end, appExtra = {}) => {
    await resetAll();
    await mkTO('n' + tag, 'sn', [{wdId: 'w1', required: 1, start, end}], DAY);
    await mkApp('ap' + tag, 'n' + tag, 'sn', 'w1', 'u1', 'CONFIRMED', DAY,
        Object.assign({startTime: start}, appExtra));
    return 'ap' + tag;
  };
  const atKst = (hhmm) => {
    const [h, m] = hhmm.split(':').map(Number);
    return DAY + (h * 60 + m) * 60000;
  };

  const DAY_STAMP = new RealDate(DAY + KST).toISOString().slice(0, 10).replace(/-/g, '');
  // 사업장 지각 유예 — 관리자 판정 경계의 출처. 기본값(5분)을 그대로 쓴다.
  const setGrace = async (min) => {
    await realDb.collection('businesses').doc(BIZ).set(
        {attendanceRules: {lateGrace: min}}, {merge: true});
  };

  // B1. 시작 49분 전 — DEV 실측 사례 그대로
  {
    const id = await setupShift('1', '23:50', '23:59');
    nowOverride = atKst('23:01');
    const r = await callNoShow(ADMIN_UID, [nsEntry(id, 'u1', DAY)]);
    nowOverride = null;
    check('B1. 시작 49분 전 거부 (processed 0)',
        {processed: r.processed, skipped: r.skipped.length}, {processed: 0, skipped: 1});
    check('B1. 근태 문서 미생성', await attOf(id + '_' + DAY_STAMP), null);
  }
  // B2. 시작 6분 전 — 거부
  {
    const id = await setupShift('2', '23:50', '23:59');
    nowOverride = atKst('23:44');
    const r = await callNoShow(ADMIN_UID, [nsEntry(id, 'u1', DAY)]);
    nowOverride = null;
    check('B2. 시작 6분 전 거부', r.processed, 0);
  }
  // B3. 시작 **5분 전** — 거부. 근로자 취소 정책의 5분 전 기준을 빌려 쓰지 않는다.
  {
    const id = await setupShift('3', '23:50', '23:59');
    nowOverride = atKst('23:45');
    const r = await callNoShow(ADMIN_UID, [nsEntry(id, 'u1', DAY)]);
    nowOverride = null;
    check('B3. 시작 5분 전 거부 (취소 정책 차용 아님)', r.processed, 0);
    check('B3. 근태 문서 미생성', await attOf(id + '_' + DAY_STAMP), null);
  }
  // B3b. 시작 1초 전 — 거부
  {
    const id = await setupShift('3b', '23:50', '23:59');
    nowOverride = atKst('23:50') - 1000;
    const r = await callNoShow(ADMIN_UID, [nsEntry(id, 'u1', DAY)]);
    nowOverride = null;
    check('B3b. 시작 1초 전 거부', r.processed, 0);
  }
  // B3c. 시작 정각 — 유예(5분) 안이므로 아직 거부
  {
    const id = await setupShift('3c', '23:50', '23:59');
    nowOverride = atKst('23:50');
    const r = await callNoShow(ADMIN_UID, [nsEntry(id, 'u1', DAY)]);
    nowOverride = null;
    check('B3c. 시작 정각 — 지각 유예 내 거부', r.processed, 0);
  }
  // B3d. 시작 + 유예 1초 전 → 거부 / 유예 경과 → 허용
  {
    const id = await setupShift('3d', '09:00', '18:00');
    nowOverride = atKst('09:05') - 1000;
    const before = await callNoShow(ADMIN_UID, [nsEntry(id, 'u1', DAY)]);
    nowOverride = atKst('09:05');
    const after = await callNoShow(ADMIN_UID, [nsEntry(id, 'u1', DAY)]);
    nowOverride = null;
    check('B3d. 유예 경계 — 1초 전 거부 / 경과 허용',
        [before.processed, after.processed], [0, 1]);
    check('B3d. 기록 내용', (await attOf(id + '_' + DAY_STAMP)) ?
      [(await attOf(id + '_' + DAY_STAMP)).status,
        (await attOf(id + '_' + DAY_STAMP)).wageStatus,
        (await attOf(id + '_' + DAY_STAMP)).finalWage] : null,
    ['NO_SHOW', 'confirmed', 0]);
  }
  // B3e. 사업장이 유예를 20분으로 정했으면 그 기준을 따른다
  {
    const id = await setupShift('3e', '09:00', '18:00');
    await setGrace(20);
    nowOverride = atKst('09:10');
    const mid = await callNoShow(ADMIN_UID, [nsEntry(id, 'u1', DAY)]);
    nowOverride = atKst('09:20');
    const past = await callNoShow(ADMIN_UID, [nsEntry(id, 'u1', DAY)]);
    nowOverride = null;
    check('B3e. 사업장 유예 20분 적용 — 10분 거부 / 20분 허용',
        [mid.processed, past.processed], [0, 1]);
  }
  // B3f. 건별 snapshot 이 사업장 현재 설정을 이긴다
  {
    await resetAll();
    await setGrace(60); // 사업장 현재 설정은 60분
    await mkTO('n3f', 'sn', [{wdId: 'w1', required: 1, start: '09:00', end: '18:00'}], DAY);
    await mkApp('ap3f', 'n3f', 'sn', 'w1', 'u1', 'CONFIRMED', DAY,
        {startTime: '09:00', attendancePolicySnapshot: {lateGrace: 5}});
    nowOverride = atKst('09:06');
    const r = await callNoShow(ADMIN_UID, [nsEntry('ap3f', 'u1', DAY)]);
    nowOverride = null;
    check('B3f. 확정 시 snapshot(유예 5분) 우선 → 허용', r.processed, 1);
  }
  // B4. 근무 시작·유예 경과 후 — 허용
  {
    const id = await setupShift('4', '09:00', '18:00');
    nowOverride = atKst('12:00');
    const r = await callNoShow(ADMIN_UID, [nsEntry(id, 'u1', DAY)]);
    nowOverride = null;
    check('B4. 근무 시작 후 허용', r.processed, 1);
  }
  // B5. 출근 기록이 있으면 시작 후에도 오판하지 않는다
  {
    const id = await setupShift('5', '09:00', '18:00');
    const stamp = new RealDate(DAY + KST).toISOString().slice(0, 10).replace(/-/g, '');
    await realDb.collection('attendance').doc(id + '_' + stamp).set({
      applicationId: id, userId: 'u1', businessId: BIZ, status: 'present',
      wageStatus: 'pending', checkIn: T.fromMillis(atKst('09:05')),
      workDate: T.fromMillis(DAY), createdAt: T.now(),
    });
    nowOverride = atKst('12:00');
    const r = await callNoShow(ADMIN_UID, [nsEntry(id, 'u1', DAY)]);
    nowOverride = null;
    const a = await attOf(id + '_' + stamp);
    check('B5. 출근 기록 있음 → skip', r.processed, 0);
    check('B5. present 보존', [a.status, a.wageStatus], ['present', 'pending']);
  }
  // B6. 급여 확정 건 보호
  {
    const id = await setupShift('6', '09:00', '18:00');
    const stamp = new RealDate(DAY + KST).toISOString().slice(0, 10).replace(/-/g, '');
    await realDb.collection('attendance').doc(id + '_' + stamp).set({
      applicationId: id, userId: 'u1', businessId: BIZ, status: 'present',
      wageStatus: 'confirmed', finalWage: 90000, workDate: T.fromMillis(DAY),
      createdAt: T.now(),
    });
    nowOverride = atKst('12:00');
    const r = await callNoShow(ADMIN_UID, [nsEntry(id, 'u1', DAY, {attendanceId: id + '_' + stamp})]);
    nowOverride = null;
    check('B6. 급여 확정 건 skip · 금액 보존',
        [r.processed, (await attOf(id + '_' + stamp)).finalWage], [0, 90000]);
  }
  // B7. 미래 날짜 — 기존 guard 유지
  {
    const id = await setupShift('7', '09:00', '18:00');
    nowOverride = atKst('12:00');
    const r = await callNoShow(ADMIN_UID, [nsEntry(id, 'u1', DAY + 864e5)]);
    nowOverride = null;
    check('B7. 미래 날짜 skip', r.processed, 0);
  }
  // B8. 지난 날짜 근무 — 시각 경계가 막지 않는다
  {
    await resetAll();
    const PREV = DAY - 864e5;
    await mkTO('n8', 'sn', [{wdId: 'w1', required: 1, start: '09:00', end: '18:00'}], PREV);
    await mkApp('ap8', 'n8', 'sn', 'w1', 'u1', 'CONFIRMED', PREV, {startTime: '09:00'});
    nowOverride = atKst('02:00');
    const r = await callNoShow(ADMIN_UID, [nsEntry('ap8', 'u1', PREV)]);
    nowOverride = null;
    check('B8. 전날 근무 노쇼 허용', r.processed, 1);
  }
  // B9. 시작 시각 확정 불가 → **skip**. 모르는 시각을 유효하다고 보지 않는다.
  //   단기는 slot 참조가 없으면 기존 근무 컨텍스트 guard 가 먼저 막으므로
  //   (missing_slot_ref) 이 분기는 장기·startTime 없음으로 겨냥한다.
  {
    await resetAll();
    await realDb.collection('applications').doc('ap9').set({
      toId: 'n9', slotId: null, uid: 'u1', userId: 'u1', businessId: BIZ,
      status: 'CONFIRMED', type: 'long_term', selectedWorkType: 'QA',
      workDate: T.fromMillis(DAY), workEndDate: T.fromMillis(DAY + 30 * 864e5),
      workDays: ['월', '화', '수', '목', '금', '토', '일'],
    });
    nowOverride = atKst('23:30');
    const r = await callNoShow(ADMIN_UID, [nsEntry('ap9', 'u1', DAY)]);
    nowOverride = null;
    check('B9. 시작 시각 미확정 → skip',
        {processed: r.processed, skipped: r.skipped.length}, {processed: 0, skipped: 1});
    check('B9. 근태·급여 미생성', await attOf('ap9_' + DAY_STAMP), null);
    const u = await realDb.collection('users').doc('u1').get();
    check('B9. 신뢰도 미변경', u.exists ? (u.get('noShowCount') ?? 0) : 0, 0);
  }
  // B10. 장기 근무 — 지원서 startTime 으로 경계 판정
  {
    await resetAll();
    await realDb.collection('applications').doc('ap10').set({
      toId: 'n10', slotId: null, uid: 'u1', userId: 'u1', businessId: BIZ,
      status: 'CONFIRMED', type: 'long_term', startTime: '14:00', endTime: '20:00',
      workDate: T.fromMillis(DAY), workEndDate: T.fromMillis(DAY + 30 * 864e5),
      workDays: ['월', '화', '수', '목', '금', '토', '일'], selectedWorkType: 'QA',
    });
    nowOverride = atKst('10:00');
    const before = await callNoShow(ADMIN_UID, [nsEntry('ap10', 'u1', DAY)]);
    nowOverride = atKst('15:00');
    const after = await callNoShow(ADMIN_UID, [nsEntry('ap10', 'u1', DAY)]);
    nowOverride = null;
    check('B10. 장기 — 시작 전 거부 / 시작 후 허용',
        [before.processed, after.processed], [0, 1]);
  }
  // B11. 타 사업장 지원서 — 권한·소속 차단 유지
  {
    const id = await setupShift('11', '09:00', '18:00');
    await realDb.collection('businesses').doc('biz_other').set(
        {ownerId: ADMIN_UID, adminIds: [ADMIN_UID], name: '타 사업장'});
    nowOverride = atKst('12:00');
    const r = await callNoShow(ADMIN_UID, [nsEntry(id, 'u1', DAY)], 'biz_other');
    nowOverride = null;
    check('B11. 타 사업장 businessId → skip', r.processed, 0);
  }
  // B12. 권한 없는 호출자
  {
    const id = await setupShift('12', '09:00', '18:00');
    await realDb.collection('users').doc('stranger').set({role: 'USER'});
    nowOverride = atKst('12:00');
    let code = null;
    try { await callNoShow('stranger', [nsEntry(id, 'u1', DAY)]); } catch (e) { code = e.code; }
    nowOverride = null;
    check('B12. 비관리자 호출 거부', code != null, true);
  }
  // B13. 대상자 교차검증 — applicationId 와 userId 불일치
  {
    const id = await setupShift('13', '09:00', '18:00');
    nowOverride = atKst('12:00');
    const r = await callNoShow(ADMIN_UID, [nsEntry(id, 'u_other', DAY)]);
    nowOverride = null;
    check('B13. 대상자 불일치 → skip', r.processed, 0);
  }
  // B14. 야간 근무 — 자정을 넘는 근무의 시작은 근무일 23:00 이다.
  //   날짜가 다음날로 바뀌었다는 이유로 "시작했다"고 보지 않는다.
  {
    await resetAll();
    await mkTO('n14', 'sn', [{wdId: 'w1', required: 1, start: '23:00', end: '06:00'}], DAY);
    await mkApp('ap14', 'n14', 'sn', 'w1', 'u1', 'CONFIRMED', DAY, {startTime: '23:00'});
    nowOverride = atKst('00:10'); // 근무일 당일 새벽 — 아직 시작 전
    const early = await callNoShow(ADMIN_UID, [nsEntry('ap14', 'u1', DAY)]);
    nowOverride = atKst('23:06'); // 시작 + 유예 경과
    const late = await callNoShow(ADMIN_UID, [nsEntry('ap14', 'u1', DAY)]);
    nowOverride = null;
    check('B14. 야간 근무 — 당일 00:10 거부 / 23:06 허용',
        [early.processed, late.processed], [0, 1]);
  }
  // B15. 같은 날짜 여러 업무 — 업무별 시작시각으로 각각 판정한다.
  {
    await resetAll();
    await mkTO('n15', 'sn', [
      {wdId: 'wAM', required: 1, start: '09:00', end: '12:00'},
      {wdId: 'wPM', required: 1, start: '18:00', end: '22:00'},
    ], DAY);
    await mkApp('ap15am', 'n15', 'sn', 'wAM', 'u1', 'CONFIRMED', DAY, {startTime: '09:00'});
    await mkApp('ap15pm', 'n15', 'sn', 'wPM', 'u2', 'CONFIRMED', DAY, {startTime: '18:00'});
    nowOverride = atKst('13:00');
    const r = await callNoShow(ADMIN_UID, [
      nsEntry('ap15am', 'u1', DAY), nsEntry('ap15pm', 'u2', DAY)]);
    nowOverride = null;
    check('B15. 업무별 구분 — 오전 처리 / 오후 skip',
        {processed: r.processed, skipped: r.skipped.length}, {processed: 1, skipped: 1});
    check('B15. 오전만 기록', [
      (await attOf('ap15am_' + DAY_STAMP)) != null,
      (await attOf('ap15pm_' + DAY_STAMP)) != null], [true, false]);
  }
  // B16. 일괄 처리 — 정상/skip 혼재에서 정상 건이 함께 죽지 않는다.
  {
    await resetAll();
    await mkTO('n16', 'sn', [{wdId: 'w1', required: 3, start: '09:00', end: '18:00'}], DAY);
    await mkApp('okA', 'n16', 'sn', 'w1', 'u1', 'CONFIRMED', DAY, {startTime: '09:00'});
    await mkApp('okB', 'n16', 'sn', 'w1', 'u2', 'CONFIRMED', DAY, {startTime: '09:00'});
    await mkTO('n16b', 'sn', [{wdId: 'w1', required: 1, start: '22:00', end: '23:30'}], DAY);
    await mkApp('future', 'n16b', 'sn', 'w1', 'u3', 'CONFIRMED', DAY, {startTime: '22:00'});
    // 이미 출근한 사람도 한 명 섞는다.
    await realDb.collection('attendance').doc('okB_' + DAY_STAMP).set({
      applicationId: 'okB', userId: 'u2', businessId: BIZ, status: 'present',
      wageStatus: 'pending', checkIn: T.fromMillis(atKst('09:02')),
      workDate: T.fromMillis(DAY), createdAt: T.now(),
    });
    nowOverride = atKst('12:00');
    const r = await callNoShow(ADMIN_UID, [
      nsEntry('okA', 'u1', DAY), nsEntry('okB', 'u2', DAY), nsEntry('future', 'u3', DAY)]);
    nowOverride = null;
    check('B16. 혼재 배치 — 1건 처리 / 2건 skip',
        {processed: r.processed, skipped: r.skipped.length}, {processed: 1, skipped: 2});
    check('B16. 정상 1건만 NO_SHOW', (await attOf('okA_' + DAY_STAMP)).status, 'NO_SHOW');
    check('B16. 출근자 present 보존', (await attOf('okB_' + DAY_STAMP)).status, 'present');
    check('B16. 시작 전 대상 미생성', await attOf('future_' + DAY_STAMP), null);
  }
  // B17. 근로자 직전 취소 정책은 건드리지 않았다 — 소스 정적 확인.
  //   5분 **전** cutoff 의 주인은 `callableCancelConfirmedApplication`
  //   (SAME_DAY_CANCEL 분류)이고, `callableApplyNoShowPenalty` 는 그 뒤
  //   TrustScore 를 매긴다(자체 시간 재검증은 -24h~+48h 창).
  {
    const cancelSrc = sliceExport('callableCancelConfirmedApplication');
    const penaltySrc = sliceExport('callableApplyNoShowPenalty');
    check('B17. 취소 정책의 5분 전 cutoff 유지',
        /noShowEquivalent\s*=\s*Date\.now\(\)\s*>=\s*scheduledStartMs\s*-\s*5\s*\*\s*60\s*\*\s*1000/
            .test(cancelSrc), true);
    check('B17. 취소 경로가 관리자 판정 경계를 쓰지 않는다',
        /srvNoShowJudgeableFromMs/.test(cancelSrc + penaltySrc), false);
    check('B17. 취소 패널티의 시간 창(-24h~+48h) 유지',
        /diffMs\s*<\s*-\(24 \* 60 \* 60 \* 1000\)/.test(penaltySrc), true);
  }

  console.log('\n──────────────────────────────────────────────');
  console.log(`총 ${rows.length}건 · 실패 ${fail}건`);
  process.exit(fail > 0 ? 1 : 0);
})().catch((e) => { console.error('\n하네스 오류:', e); process.exit(2); });
