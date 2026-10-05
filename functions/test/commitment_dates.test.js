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
// [1C.1A] 승인된 추가근무·휴무의 날짜도 KST 달력일로 비교해야 한다 —
//   UTC 전날 15:00 로 저장된 값이 들어온다.
const ovA = {
  type: 'long_term', workDays: ['월','화','수','목','금'],
  workDate: kstMidnight(2026,10,1), workEndDate: kstMidnight(2026,11,30),
  extraWorkDates: [{toDate: () => new Date('2026-10-09T15:00:00Z')}],
};
const ovB = {
  type: 'long_term', workDays: ['토'],
  workDate: kstMidnight(2026,10,1), workEndDate: kstMidnight(2026,11,30),
};
const ovHit = M.longTermConflictDay(ovA, ovB);
console.log(JSON.stringify([
  M.kstDateNum(new Date('2026-10-04T15:00:00Z')),
  M.kstDateNum(new Date('2026-10-04T14:59:59.999Z')),
  M.kstWeekdayKo(new Date('2026-10-04T15:00:00Z')),
  M.longTermEffectiveStartNum(app),
  M.longTermCommitmentOnDay(app, 20261010, '토'),
  M.longTermCommitmentOnDay(app, 20261017, '토'),
  M.longTermCommitmentRange(app).endNum,
  ovHit && ovHit.dayNum,
  ovHit && ovHit.viaOverride,
]));
`;

t('TZ1 서버 시간대가 달라도 같은 KST 달력일을 말한다', () => {
  const expected = JSON.stringify(
      [20261005, 20261004, '월', 20261012, false, true, 20261130,
        20261010, true]);
  for (const tz of ['UTC', 'America/New_York', 'Asia/Kolkata', 'Asia/Seoul']) {
    const out = execFileSync(process.execPath, ['-e', TZ_PROBE], {
      cwd: `${__dirname}/..`,
      env: {...process.env, TZ: tz},
      encoding: 'utf8',
    }).trim();
    assert.strictEqual(out, expected, `TZ=${tz}`);
  }
});

// ══ [R7-APPLICATION-LIFECYCLE.1C.1A] 승인된 추가근무·휴무 ═══════════════════
//
//   장기 근무의 실제 약속은 "원래 근무요일" 만으로 결정되지 않는다.
//   관리자가 승인한 EXTRA_WORK 는 비근무일을 근무일로 만들고,
//   NO_WORK/LEAVE 는 근무일을 지운다. 겹침 판정도 그 진실을 써야 한다.

/** 월~금 09:00~18:00 장기 약속. */
const weekdayApp = (over = {}) => ({
  type: 'long_term',
  workDays: ['월', '화', '수', '목', '금'],
  startTime: '09:00',
  endTime: '18:00',
  workDate: kstMidnight(2026, 10, 1),
  workEndDate: kstMidnight(2026, 11, 30),
  ...over,
});

console.log('\n[CD-OV] 추가근무·휴무 — per-day 진실');

t('O1 정규 근무요일 → 약속이 있다', () => {
  // 2026-10-12 는 월요일.
  assert.strictEqual(wkd(2026, 10, 12), '월');
  assert.strictEqual(onDay(weekdayApp(), 2026, 10, 12), true);
});

t('O3 비정규일(토)에 추가근무가 없으면 약속이 없다', () => {
  assert.strictEqual(wkd(2026, 10, 10), '토');
  assert.strictEqual(onDay(weekdayApp(), 2026, 10, 10), false);
});

t('O4 비정규일 + EXTRA_WORK → 약속이 생긴다', () => {
  const app = weekdayApp({extraWorkDates: [kstMidnight(2026, 10, 10)]});
  assert.strictEqual(onDay(app, 2026, 10, 10), true);
  // 다른 토요일은 여전히 아니다.
  assert.strictEqual(onDay(app, 2026, 10, 17), false);
});

t('O6 정규일 + LEAVE → 그 날 약속이 없다', () => {
  const app = weekdayApp({leaveDates: [kstMidnight(2026, 10, 12)]});
  assert.strictEqual(onDay(app, 2026, 10, 12), false);
});

t('O7 휴무 하나가 다음 정규일을 지우지 않는다', () => {
  const app = weekdayApp({leaveDates: [kstMidnight(2026, 10, 12)]});
  assert.strictEqual(wkd(2026, 10, 19), '월');
  assert.strictEqual(onDay(app, 2026, 10, 19), true);
});

t('O8 효력 구간 밖의 추가근무는 약속이 아니다', () => {
  const app = weekdayApp({
    desiredStartDate: kstMidnight(2026, 10, 15),
    extraWorkDates: [kstMidnight(2026, 10, 10), kstMidnight(2026, 12, 5)],
  });
  assert.strictEqual(onDay(app, 2026, 10, 10), false, '시작 이전');
  assert.strictEqual(onDay(app, 2026, 12, 5), false, '종료 이후');
  // 구간 안의 토요일 추가근무는 약속이다.
  const app2 = weekdayApp({
    desiredStartDate: kstMidnight(2026, 10, 15),
    extraWorkDates: [kstMidnight(2026, 10, 17)],
  });
  assert.strictEqual(onDay(app2, 2026, 10, 17), true);
});

t('O9 구간 밖 휴무는 아무 것도 바꾸지 않는다', () => {
  const app = weekdayApp({leaveDates: [kstMidnight(2026, 12, 7)]});
  assert.strictEqual(onDay(app, 2026, 12, 7), false, '이미 종료 이후');
  assert.strictEqual(onDay(app, 2026, 10, 12), true);
});

t('O10 퇴사일 당일의 추가근무는 약속이다 (D inclusive)', () => {
  const app = weekdayApp({
    actualResignDate: kstMidnight(2026, 10, 17),
    extraWorkDates: [kstMidnight(2026, 10, 17)],
  });
  assert.strictEqual(onDay(app, 2026, 10, 17), true);
});

t('O11 퇴사일 다음 날의 추가근무는 약속이 아니다', () => {
  const app = weekdayApp({
    actualResignDate: kstMidnight(2026, 10, 17),
    extraWorkDates: [kstMidnight(2026, 10, 18)],
  });
  assert.strictEqual(onDay(app, 2026, 10, 18), false);
});

t('O-PRE 추가근무·휴무가 겹치면 추가근무가 먼저다 (canonical precedence)', () => {
  // 정상 writer 는 이 dual-state 를 만들지 않는다 — 규칙만 고정한다.
  const app = weekdayApp({
    extraWorkDates: [kstMidnight(2026, 10, 10)],
    leaveDates: [kstMidnight(2026, 10, 10)],
  });
  assert.strictEqual(onDay(app, 2026, 10, 10), true);
});

t('O-KST 추가근무 날짜도 KST 달력일로 비교한다', () => {
  // UTC 전날 15:00 로 저장된 10/11(일) — 로컬(UTC) 성분으로 읽으면 10/10 이다.
  //   두 날 모두 정규 근무요일이 아니므로 추가근무만이 차이를 만든다.
  const raw = {toDate: () => new Date('2026-10-10T15:00:00Z')};
  const app = weekdayApp({extraWorkDates: [raw]});
  assert.strictEqual(wkd(2026, 10, 11), '일');
  assert.strictEqual(wkd(2026, 10, 10), '토');
  assert.strictEqual(onDay(app, 2026, 10, 11), true);
  assert.strictEqual(onDay(app, 2026, 10, 10), false);
});

// ── 장기 ↔ 장기 ───────────────────────────────────────────────────────────
/** 후보 장기 — 기본은 토요일 반복. */
const candLong = (over = {}) => ({
  type: 'long_term',
  workDays: ['토'],
  workDate: kstMidnight(2026, 10, 1),
  workEndDate: kstMidnight(2026, 11, 30),
  ...over,
});
const clash = (a, b) => M.longTermConflictDay(a, b);

t('O18 장기↔장기 반복 근무요일이 겹치면 충돌이다', () => {
  const hit = clash(weekdayApp(), candLong({workDays: ['월', '토']}));
  assert.ok(hit, '월요일에서 겹친다');
  assert.strictEqual(hit.viaOverride, false);
  assert.strictEqual(hit.wkd, '월');
});

t('O18b 요일 교집합이 없으면 충돌이 아니다', () => {
  assert.strictEqual(clash(weekdayApp(), candLong()), null);
});

t('O18c 기간이 떨어져 있으면 충돌이 아니다', () => {
  const far = candLong({
    workDays: ['월'],
    workDate: kstMidnight(2027, 1, 4),
    workEndDate: kstMidnight(2027, 2, 28),
  });
  assert.strictEqual(clash(weekdayApp(), far), null);
});

t('O19 장기↔장기 — 추가근무 하루만으로도 충돌이다', () => {
  const a = weekdayApp({extraWorkDates: [kstMidnight(2026, 10, 10)]});
  const hit = clash(a, candLong()); // 후보는 토요일 반복
  assert.ok(hit);
  assert.strictEqual(hit.viaOverride, true);
  assert.strictEqual(hit.dayNum, num(2026, 10, 10));
});

t('O19b 후보 쪽 추가근무로도 충돌이다 (대칭)', () => {
  const b = candLong({
    workDays: ['일'],
    extraWorkDates: [kstMidnight(2026, 10, 12)], // 월요일
  });
  const hit = clash(weekdayApp(), b);
  assert.ok(hit);
  assert.strictEqual(hit.viaOverride, true);
  assert.strictEqual(hit.dayNum, num(2026, 10, 12));
});

t('O19c 추가근무 날짜가 상대 구간 밖이면 충돌이 아니다', () => {
  const a = weekdayApp({extraWorkDates: [kstMidnight(2026, 10, 10)]});
  const b = candLong({
    workDate: kstMidnight(2026, 11, 1),
    workEndDate: kstMidnight(2026, 11, 30),
  });
  assert.strictEqual(clash(a, b), null);
});

t('O20 휴무 하루가 장기↔장기 충돌 전체를 지우지 않는다', () => {
  const a = weekdayApp({leaveDates: [kstMidnight(2026, 10, 12)]});
  const b = candLong({workDays: ['월']});
  const hit = clash(a, b);
  assert.ok(hit, '10/19 등 다른 월요일이 남아 있다');
  assert.strictEqual(hit.viaOverride, false);
  assert.notStrictEqual(hit.dayNum, num(2026, 10, 12));
});

t('O20b 겹치는 날이 하나뿐이고 그 날이 휴무면 충돌이 아니다', () => {
  // 후보 구간을 10/12 한 주로 좁힌다 — 공통 월요일은 10/12 뿐이다.
  const a = weekdayApp({leaveDates: [kstMidnight(2026, 10, 12)]});
  const b = candLong({
    workDays: ['월'],
    workDate: kstMidnight(2026, 10, 12),
    workEndDate: kstMidnight(2026, 10, 16),
  });
  assert.strictEqual(clash(a, b), null);
});

t('O20c 휴무가 여러 날이어도 생존하는 날을 찾는다 (상계 안에서)', () => {
  const a = weekdayApp({
    leaveDates: [
      kstMidnight(2026, 10, 5), kstMidnight(2026, 10, 12),
      kstMidnight(2026, 10, 19),
    ],
  });
  const b = candLong({workDays: ['월']});
  const hit = clash(a, b);
  assert.ok(hit);
  assert.strictEqual(hit.dayNum, num(2026, 10, 26));
});

t('O20d 양쪽 휴무가 같은 날을 지우면 그 날은 충돌이 아니다', () => {
  const a = weekdayApp({leaveDates: [kstMidnight(2026, 10, 12)]});
  const b = candLong({
    workDays: ['월'],
    workDate: kstMidnight(2026, 10, 12),
    workEndDate: kstMidnight(2026, 10, 20),
    leaveDates: [kstMidnight(2026, 10, 19)],
  });
  assert.strictEqual(clash(a, b), null);
});

t('O-WIN 공통요일 스캔은 **효력 시작 이후**부터 본다', () => {
  // 후보 구간은 10/1~11/30 월요일, 기존 약속은 10/20 부터 효력.
  //   창을 교집합(10/20~)이 아니라 더 이른 날부터 열면, 상계(휴무 0 → 1개)가
  //   효력 이전의 10/5 에서 소진돼 **진짜 충돌(10/26)을 놓친다**.
  const a = weekdayApp({desiredStartDate: kstMidnight(2026, 10, 20)});
  const b = candLong({workDays: ['월']});
  const hit = clash(a, b);
  assert.ok(hit, '효력 시작 이후 첫 월요일에서 겹친다');
  assert.strictEqual(hit.dayNum, num(2026, 10, 26));
});

t('O-CAND 후보 쪽 약속 여부도 본다 — 한쪽만 보면 과잉 차단', () => {
  // 기존은 월요일 근무, 후보는 그 월요일이 휴무다 → 겹치지 않는다.
  const a = weekdayApp();
  const b = candLong({
    workDays: ['월'],
    workDate: kstMidnight(2026, 10, 12),
    workEndDate: kstMidnight(2026, 10, 16),
    leaveDates: [kstMidnight(2026, 10, 12)],
  });
  assert.strictEqual(clash(a, b), null);
});

t('O-OVKST 추가근무 날짜의 달력일도 KST 다 (장기↔장기)', () => {
  // UTC 전날 15:00 로 저장된 토요일 10/10.
  const raw = {toDate: () => new Date('2026-10-09T15:00:00Z')};
  const a = weekdayApp({extraWorkDates: [raw]});
  const hit = clash(a, candLong()); // 후보는 토요일 반복
  assert.ok(hit, '로컬 성분으로 읽으면 금요일이 되어 이 충돌을 놓친다');
  assert.strictEqual(hit.viaOverride, true);
  assert.strictEqual(hit.dayNum, num(2026, 10, 10));
});

t('O-RANGE 장기↔장기도 효력 시작·종료를 지킨다', () => {
  const a = weekdayApp({desiredStartDate: kstMidnight(2026, 10, 20)});
  const b = candLong({
    workDays: ['월'],
    workDate: kstMidnight(2026, 10, 1),
    workEndDate: kstMidnight(2026, 10, 15),
  });
  assert.strictEqual(clash(a, b), null, '후보 구간이 효력 시작 이전에 끝난다');
});

t('O-RESIGN 퇴사일 이후는 장기↔장기 충돌에서도 빠진다', () => {
  const a = weekdayApp({actualResignDate: kstMidnight(2026, 10, 13)});
  const b = candLong({
    workDays: ['월'],
    workDate: kstMidnight(2026, 10, 19),
    workEndDate: kstMidnight(2026, 11, 30),
  });
  assert.strictEqual(clash(a, b), null);
});

console.log(`\n=== [CD] ${pass}/${pass + fails.length} PASS` +
  `${fails.length ? ` · FAIL ${fails.length}` : ''} ===`);
if (fails.length) {
  for (const f of fails) console.error(`  - ${f}`);
  process.exit(1);
}
