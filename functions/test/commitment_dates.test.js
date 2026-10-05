// [R7-APPLICATION-LIFECYCLE.1C.1] 장기 약속 날짜 판정 — **행동** 테스트.
//
//   실행:  cd functions && npm run build && node test/commitment_dates.test.js
//
//   소스 문자열 검색이 아니라 실제 함수를 불러 값을 비교한다. 이 모듈은
//   순수하므로(Firestore·admin SDK 없음) emulator 없이 돌아간다.
//
//   고정하는 것
//     · effectiveStart = desiredStartDate ?? workDate
//       desiredStartDate 가 없을 때만 confirmedAt(KST 일)로 밀린다
//     · effectiveEnd = actualResignDate ?? workEndDate, 양끝 inclusive
//     · 모든 달력일은 **KST** 다 — 서버 로컬/UTC 성분이 아니다
//     · 종료일을 모르면 근무일 판정은 NO_END, 겹침 판정은 열린 구간
'use strict';
const assert = require('assert');
const {execFileSync} = require('child_process');
const M = require('../lib/commitment_dates');

let pass = 0;
const fails = [];
function t(id, fn) {
  try {
    fn();
    pass++;
    console.log(`  ok   ${id}`);
  } catch (e) {
    fails.push(`${id}: ${e.message.split('\n')[0]}`);
    console.log(`  FAIL ${id} — ${e.message.split('\n')[0]}`);
  }
}

// ── fixture ────────────────────────────────────────────────────────────────
/** KST 자정 instant — Firestore 저장 규약(UTC 로는 전날 15:00). */
const kstMidnight = (y, m, d) =>
  ({toDate: () => new Date(Date.UTC(y, m - 1, d) - 9 * 3600 * 1000)});
/** KST 시각 instant. */
const kstAt = (y, m, d, hh, mm) => ({
  toDate: () =>
    new Date(Date.UTC(y, m - 1, d, hh, mm) - 9 * 3600 * 1000),
});
const num = (y, m, d) => y * 10000 + m * 100 + d;
const WKD = ['일', '월', '화', '수', '목', '금', '토'];
const wkd = (y, m, d) => WKD[new Date(Date.UTC(y, m - 1, d)).getUTCDay()];

/** 장기 약속 — 토요일 근무, 09:00~18:00. */
const longApp = (over = {}) => ({
  type: 'long_term',
  workDays: ['토'],
  startTime: '09:00',
  endTime: '18:00',
  workDate: kstMidnight(2026, 10, 1),
  workEndDate: kstMidnight(2026, 11, 30),
  ...over,
});

const onDay = (app, y, m, d) =>
  M.longTermCommitmentOnDay(app, num(y, m, d), wkd(y, m, d));
const eligible = (app, y, m, d) =>
  M.longTermEligibleOnDay(app, num(y, m, d), wkd(y, m, d));

console.log('\n[CD] 장기 약속 날짜 판정 — 행동');

// ── T1~T5 effectiveStart / effectiveEnd ───────────────────────────────────
t('T1 desiredStartDate 가 늦으면 그 이전 날짜는 약속이 아니다', () => {
  // workDate 10/01, desiredStart 10/15 → 10/10(토) 는 충돌 아님
  const app = longApp({desiredStartDate: kstMidnight(2026, 10, 15)});
  assert.strictEqual(wkd(2026, 10, 10), '토');
  assert.strictEqual(onDay(app, 2026, 10, 10), false);
  assert.strictEqual(
      eligible(app, 2026, 10, 10).reason, 'BEFORE_START');
});

t('T2 효력 시작일 이후의 근무요일은 약속이다', () => {
  const app = longApp({desiredStartDate: kstMidnight(2026, 10, 15)});
  assert.strictEqual(wkd(2026, 10, 17), '토');
  assert.strictEqual(onDay(app, 2026, 10, 17), true);
  // 시작일 자체가 근무요일이면 그 날도 포함(10/17 이 첫 토요일)
  assert.strictEqual(onDay(app, 2026, 10, 15), false, '10/15 는 목요일');
});

t('T3 confirmedAt 보정 — 희망일이 없으면 확정일 이전은 약속이 아니다', () => {
  const app = longApp({confirmedAt: kstAt(2026, 10, 12, 14, 30)});
  assert.strictEqual(onDay(app, 2026, 10, 3), false, '10/03 토 — 확정 이전');
  assert.strictEqual(onDay(app, 2026, 10, 17), true, '10/17 토 — 확정 이후');
});

t('T4 명시적 희망 시작일을 confirmedAt 이 덮지 않는다', () => {
  const app = longApp({
    desiredStartDate: kstMidnight(2026, 10, 5),
    confirmedAt: kstAt(2026, 10, 20, 9, 0),
  });
  assert.strictEqual(
      M.longTermEffectiveStartNum(app), num(2026, 10, 5));
  assert.strictEqual(onDay(app, 2026, 10, 10), true, '10/10 토 — 희망일 이후');
});

t('T5 퇴사일이 종료를 당긴다 — 그 날은 포함, 다음 날은 제외', () => {
  const app = longApp({actualResignDate: kstMidnight(2026, 10, 24)});
  assert.strictEqual(wkd(2026, 10, 24), '토');
  assert.strictEqual(onDay(app, 2026, 10, 24), true, 'D 는 inclusive');
  assert.strictEqual(onDay(app, 2026, 10, 31), false, 'D+ 는 제외');
  assert.strictEqual(
      eligible(app, 2026, 10, 31).reason, 'AFTER_RESIGN');
});

t('T5b workEndDate 도 inclusive', () => {
  const app = longApp({workEndDate: kstMidnight(2026, 10, 24)});
  assert.strictEqual(onDay(app, 2026, 10, 24), true);
  assert.strictEqual(eligible(app, 2026, 10, 31).reason, 'AFTER_END');
});

// ── T6~T8 KST 경계 ────────────────────────────────────────────────────────
t('T6 KST 자정은 UTC 전날 15:00 — business date 는 KST 다', () => {
  const inst = new Date('2026-10-04T15:00:00Z');
  assert.strictEqual(M.kstDateNum(inst), num(2026, 10, 5));
  assert.strictEqual(M.kstWeekdayKo(inst), wkd(2026, 10, 5));
  // 서버 로컬(UTC) 성분으로 읽으면 10/04 가 된다 — 그 길로 가지 않는다.
  assert.strictEqual(inst.getUTCDate(), 4);
});

t('T7 KST 자정 1밀리초 전은 전날이다', () => {
  assert.strictEqual(
      M.kstDateNum(new Date('2026-10-04T14:59:59.999Z')),
      num(2026, 10, 4));
  assert.strictEqual(
      M.kstDateNum(new Date('2026-10-04T15:00:00.000Z')),
      num(2026, 10, 5));
});

t('T8 해 경계 — KST 12/31 23:30 과 1/1 00:30', () => {
  assert.strictEqual(
      M.kstDateNum(new Date(Date.UTC(2026, 11, 31, 14, 30))),
      num(2026, 12, 31));
  assert.strictEqual(
      M.kstDateNum(new Date(Date.UTC(2026, 11, 31, 15, 30))),
      num(2027, 1, 1));
});

t('T8b confirmedAt 이 KST 새벽이면 보정일도 KST 달력일이다', () => {
  // 2026-10-12 02:00 KST = 2026-10-11T17:00Z. 로컬(UTC)로 읽으면 10/11.
  const app = longApp({confirmedAt: kstAt(2026, 10, 12, 2, 0)});
  assert.strictEqual(
      M.longTermEffectiveStartNum(app), num(2026, 10, 12));
  assert.strictEqual(onDay(app, 2026, 10, 10), false);
});

// ── T9~T10 요일·예외 ─────────────────────────────────────────────────────
t('T16 근무요일이 아니면 기간 안이어도 약속이 아니다', () => {
  const app = longApp();
  assert.strictEqual(wkd(2026, 10, 13), '화');
  assert.strictEqual(onDay(app, 2026, 10, 13), false);
  assert.strictEqual(eligible(app, 2026, 10, 13).reason, 'NON_WORKDAY');
});

t('T17 추가근무일은 요일을 이긴다', () => {
  const app = longApp({extraWorkDates: [kstMidnight(2026, 10, 13)]});
  assert.strictEqual(onDay(app, 2026, 10, 13), true);
});

t('T18 휴무일은 근무요일을 지운다', () => {
  const app = longApp({leaveDates: [kstMidnight(2026, 10, 17)]});
  assert.strictEqual(onDay(app, 2026, 10, 17), false);
  assert.strictEqual(eligible(app, 2026, 10, 17).reason, 'LEAVE');
});

t('T18b 추가근무가 휴무보다 먼저다 (legacy dual-state)', () => {
  const app = longApp({
    extraWorkDates: [kstMidnight(2026, 10, 13)],
    leaveDates: [kstMidnight(2026, 10, 13)],
  });
  assert.strictEqual(onDay(app, 2026, 10, 13), true);
});

// ── open-ended ───────────────────────────────────────────────────────────
t('OE1 종료를 모르면 근무일 판정은 NO_END', () => {
  const app = longApp({workEndDate: undefined});
  assert.strictEqual(eligible(app, 2026, 10, 17).eligible, false);
  assert.strictEqual(eligible(app, 2026, 10, 17).reason, 'NO_END');
});

t('OE2 종료를 모르면 겹침 판정은 열린 구간이다 (끝났다고 단정하지 않는다)', () => {
  const app = longApp({workEndDate: undefined});
  assert.strictEqual(onDay(app, 2026, 10, 17), true);
  assert.strictEqual(onDay(app, 2030, 1, 5), true, '2030/1/5 는 토');
  // 시작 이전은 여전히 아니다.
  assert.strictEqual(onDay(app, 2026, 9, 26), false);
  // 요일도 여전히 본다.
  assert.strictEqual(onDay(app, 2026, 10, 13), false);
});

t('OE3 구간 helper 는 모름을 열린 상한으로 알린다', () => {
  const r = M.longTermCommitmentRange(longApp({workEndDate: undefined}));
  assert.strictEqual(r.endKnown, false);
  assert.strictEqual(r.endNum, M.OPEN_ENDED_DAY_NUM);
  const r2 = M.longTermCommitmentRange(longApp());
  assert.strictEqual(r2.endKnown, true);
  assert.strictEqual(r2.endNum, num(2026, 11, 30));
  assert.strictEqual(r2.startNum, num(2026, 10, 1));
});

t('OE4 퇴사일이 종료일을 이긴다', () => {
  const r = M.longTermCommitmentRange(longApp({
    workEndDate: kstMidnight(2026, 12, 31),
    actualResignDate: kstMidnight(2026, 11, 15),
  }));
  assert.strictEqual(r.endNum, num(2026, 11, 15));
});

// ── 분류 ─────────────────────────────────────────────────────────────────
t('CL1 type=long_term 이면 workDays 가 없어도 장기다', () => {
  assert.strictEqual(M.isLongTermCommitment({type: 'long_term'}), true);
  // 예전 좌석 엔진은 `applicationType === "longTerm"` 를 봤다 — 실제 필드가
  // 아니므로 한 번도 맞지 않았다.
  assert.strictEqual(
      M.isLongTermCommitment({applicationType: 'longTerm'}), false);
});

t('CL2 workDays 가 있으면 장기다 (legacy)', () => {
  assert.strictEqual(M.isLongTermCommitment({workDays: ['월']}), true);
  assert.strictEqual(M.isLongTermCommitment({workDays: []}), false);
  assert.strictEqual(M.isLongTermCommitment({type: 'short'}), false);
});

// ── 손상된 값 ─────────────────────────────────────────────────────────────
t('BD1 날짜 필드가 Timestamp 가 아니면 무시한다 (throw 하지 않는다)', () => {
  const app = longApp({desiredStartDate: '2026-10-15'});
  // 문자열은 날짜로 읽지 않는다 — workDate 로 떨어진다.
  assert.strictEqual(M.longTermEffectiveStartNum(app), num(2026, 10, 1));
  const app2 = longApp({workEndDate: {toDate: () => new Date(NaN)}});
  assert.strictEqual(eligible(app2, 2026, 10, 17).reason, 'NO_END');
});

t('BD2 날짜를 하나도 모르면 시작은 0 — 모든 날짜가 시작 이후다', () => {
  assert.strictEqual(M.longTermEffectiveStartNum({}), 0);
});

// ── 서버 시간대 독립성 ────────────────────────────────────────────────────
//
//   **이 기기는 UTC+9 다.** 그래서 `getFullYear/getMonth/getDate`(서버 로컬
//   달력일)와 KST 달력일이 같은 값을 내고, 로컬 성분으로 바꿔 놓아도 위
//   셀들에서는 차이가 보이지 않는다. 판정이 실행 지역에 의존하지 않는지는
//   **다른 시간대의 Node 프로세스**에서 같은 값을 다시 재야 알 수 있다.
const TZ_PROBE = `
const M = require('./lib/commitment_dates');
const kstMidnight = (y,m,d) => ({toDate: () => new Date(Date.UTC(y,m-1,d) - 9*3600*1000)});
const kstAt = (y,m,d,hh,mm) => ({toDate: () => new Date(Date.UTC(y,m-1,d,hh,mm) - 9*3600*1000)});
const app = {
  type: 'long_term', workDays: ['토'], startTime: '09:00', endTime: '18:00',
  workDate: kstMidnight(2026,10,1), workEndDate: kstMidnight(2026,11,30),
  confirmedAt: kstAt(2026,10,12,2,0),
};
console.log(JSON.stringify([
  M.kstDateNum(new Date('2026-10-04T15:00:00Z')),
  M.kstDateNum(new Date('2026-10-04T14:59:59.999Z')),
  M.kstWeekdayKo(new Date('2026-10-04T15:00:00Z')),
  M.longTermEffectiveStartNum(app),
  M.longTermCommitmentOnDay(app, 20261010, '토'),
  M.longTermCommitmentOnDay(app, 20261017, '토'),
  M.longTermCommitmentRange(app).endNum,
]));
`;

t('TZ1 서버 시간대가 달라도 같은 KST 달력일을 말한다', () => {
  const expected = JSON.stringify(
      [20261005, 20261004, '월', 20261012, false, true, 20261130]);
  for (const tz of ['UTC', 'America/New_York', 'Asia/Kolkata', 'Asia/Seoul']) {
    const out = execFileSync(process.execPath, ['-e', TZ_PROBE], {
      cwd: `${__dirname}/..`,
      env: {...process.env, TZ: tz},
      encoding: 'utf8',
    }).trim();
    assert.strictEqual(out, expected, `TZ=${tz}`);
  }
});

console.log(`\n=== [CD] ${pass}/${pass + fails.length} PASS` +
  `${fails.length ? ` · FAIL ${fails.length}` : ''} ===`);
if (fails.length) {
  for (const f of fails) console.error(`  - ${f}`);
  process.exit(1);
}
