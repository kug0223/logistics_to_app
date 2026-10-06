// [R7-CROSSCUT-TIME.1C] schedule-change 서버 날짜 비교 — **실제 프로세스 TZ** 통제.
//
//   실행:  cd functions && npm run build && node test/schedule_change_kst.test.js
//
//   왜 자식 프로세스인가: 한 프로세스의 TZ 는 바꿀 수 없고 이 호스트는 KST 다.
//   그래서 TZ 를 바꾼 자식에서 **production 모듈을 import** 해 돌린다.
//   식을 베껴 쓴 runner 는 드리프트를 못 잡는다 — `commitment_dates` 를
//   그대로 require 한다.
//
//   고정하는 것
//     · 업무 날짜의 진실은 KST 다 — 서버 프로세스 시간대가 아니다.
//     · 저장 관례 두 가지(UTC 자정 / KST 자정)가 같은 업무일로 수렴한다.
//     · 범위는 양끝 포함, 인접일은 밖.
//     · 배열의 "같은 날" 제거/추가는 정확히 그 날만 건드린다.
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const {execFileSync} = require('child_process');

const SRC = path.join(__dirname, '..', 'src', 'index.ts');
const MOD = path.join(__dirname, '..', 'lib', 'commitment_dates.js');
const TZS = ['Asia/Seoul', 'UTC', 'America/Los_Angeles',
  'Asia/Kolkata', 'Pacific/Kiritimati'];

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

const KST = 9 * 3600 * 1000;
/** KST 달력일 D 의 자정 instant(ms) — Dart `toKstDate` 가 저장하는 모양. */
const kstMid = (y, m, d) => Date.UTC(y, m - 1, d) - KST;
/** DATE_ONLY 비교 키(ms) = UTC 자정 — 관리자 다이얼로그가 저장하는 모양. */
const utcMid = (y, m, d) => Date.UTC(y, m - 1, d);

const M = require(MOD);
/** 서버가 쓰는 자(尺). index.ts 의 `srvKstDateNum` 이 이 함수를 위임한다. */
const dayNum = (ms) => M.kstDateNum(new Date(ms));

// 자식에서 돌릴 코드 — production 모듈을 import 한다.
const CHILD = `
const M = require(${JSON.stringify(MOD)});
const KST = 9 * 3600 * 1000;
const kstMid = (y, m, d) => Date.UTC(y, m - 1, d) - KST;
const utcMid = (y, m, d) => Date.UTC(y, m - 1, d);
const dayNum = (ms) => M.kstDateNum(new Date(ms));
const cases = JSON.parse(process.argv[1]);
const out = {tz: process.env.TZ, offsetMin: new Date().getTimezoneOffset(), num: {}};
for (const [label, [kind, y, m, d]] of Object.entries(cases)) {
  const ms = kind === 'kst' ? kstMid(y, m, d) : utcMid(y, m, d);
  out.num[label] = dayNum(ms);
}
process.stdout.write(JSON.stringify(out));
`;

const CASES = {
  // §39 UTC representation boundary (2026-10-05 00:00 KST = 10-04 15:00Z)
  'kst_20261005': ['kst', 2026, 10, 5],
  'utc_20261005': ['utc', 2026, 10, 5],
  // §37 month boundary
  'kst_20261031': ['kst', 2026, 10, 31],
  'kst_20261101': ['kst', 2026, 11, 1],
  'utc_20261101': ['utc', 2026, 11, 1],
  // §38 year boundary
  'kst_20261231': ['kst', 2026, 12, 31],
  'kst_20270101': ['kst', 2027, 1, 1],
  'utc_20270101': ['utc', 2027, 1, 1],
  // §36 leap day
  'kst_20280229': ['kst', 2028, 2, 29],
  'utc_20280229': ['utc', 2028, 2, 29],
  // 미국 DST 전환 주변 — `new Date(y,m,d)` 식이 흔들리던 구간
  'kst_20260308': ['kst', 2026, 3, 8],
  'kst_20261101b': ['kst', 2026, 11, 1],
};
const EXPECT = {
  'kst_20261005': 20261005, 'utc_20261005': 20261005,
  'kst_20261031': 20261031, 'kst_20261101': 20261101,
  'utc_20261101': 20261101,
  'kst_20261231': 20261231, 'kst_20270101': 20270101,
  'utc_20270101': 20270101,
  'kst_20280229': 20280229, 'utc_20280229': 20280229,
  'kst_20260308': 20260308, 'kst_20261101b': 20261101,
};

function runIn(tz) {
  const raw = execFileSync(process.execPath,
      ['-e', CHILD, JSON.stringify(CASES)],
      {env: {...process.env, TZ: tz}, encoding: 'utf8'});
  return JSON.parse(raw);
}

// ══ K1 · K11~K15 — TZ 매트릭스 + 경계 ═══════════════════════════════════
console.log('\n── K1 canonical KST helper: TZ 5곳에서 같은 D ──');
const results = {};
for (const tz of TZS) {
  t(`K1 ${tz}`, () => {
    const r = runIn(tz);
    results[tz] = r;
    for (const [label, want] of Object.entries(EXPECT)) {
      assert.strictEqual(r.num[label], want,
          `${tz}: ${label} → ${r.num[label]} (기대 ${want})`);
    }
  });
}
t('K1b 모든 TZ 결과가 서로 같다', () => {
  const uniq = new Set(Object.values(results).map((r) => JSON.stringify(r.num)));
  assert.strictEqual(uniq.size, 1,
      `TZ 별로 갈렸다: ${JSON.stringify(Object.entries(results)
          .map(([tz, r]) => [tz, r.num]))}`);
});
t('K1c 자식이 실제로 다른 TZ 로 떴다 — 통제가 작동했다', () => {
  const off = Object.fromEntries(
      Object.entries(results).map(([tz, r]) => [tz, r.offsetMin]));
  assert.strictEqual(off['Asia/Seoul'], -540, JSON.stringify(off));
  assert.strictEqual(off['UTC'], 0, JSON.stringify(off));
  assert.ok(off['America/Los_Angeles'] > 0, JSON.stringify(off));
  assert.ok(new Set(Object.values(off)).size >= 4, JSON.stringify(off));
});
// §47 — 측정만 한다. fix 는 이 값에 의존하지 않는다.
t('K1d 이 테스트 호스트의 TZ 를 기록한다 (fix 는 이 값에 의존하지 않는다)', () => {
  console.log(`       host TZ=${process.env.TZ ?? '(unset)'} ` +
      `offsetMin=${new Date().getTimezoneOffset()}`);
  assert.ok(true);
});

console.log('\n── K11·K12 저장 관례 두 가지가 같은 업무일로 수렴 ──');
t('K11 UTC-자정 저장 관례', () => {
  for (const [y, m, d] of [[2026, 10, 5], [2026, 11, 1], [2027, 1, 1],
    [2028, 2, 29], [2026, 1, 5]]) {
    assert.strictEqual(dayNum(utcMid(y, m, d)),
        y * 10000 + m * 100 + d, `utc ${y}-${m}-${d}`);
  }
});
t('K12 KST-자정 저장 관례', () => {
  for (const [y, m, d] of [[2026, 10, 5], [2026, 11, 1], [2027, 1, 1],
    [2028, 2, 29], [2026, 1, 5]]) {
    assert.strictEqual(dayNum(kstMid(y, m, d)),
        y * 10000 + m * 100 + d, `kst ${y}-${m}-${d}`);
  }
});
t('K12b 두 관례는 9시간 다른 instant 인데 같은 업무일이다', () => {
  const a = kstMid(2026, 10, 5);
  const b = utcMid(2026, 10, 5);
  assert.notStrictEqual(a, b, '두 관례가 같은 instant 면 이 셀의 의미가 없다');
  assert.strictEqual(b - a, KST);
  assert.strictEqual(dayNum(a), dayNum(b));
});
t('K13 월 경계', () => {
  assert.strictEqual(dayNum(kstMid(2026, 10, 31)), 20261031);
  assert.strictEqual(dayNum(kstMid(2026, 11, 1)), 20261101);
  assert.notStrictEqual(dayNum(kstMid(2026, 10, 31)), dayNum(kstMid(2026, 11, 1)));
});
t('K14 연 경계', () => {
  assert.strictEqual(dayNum(kstMid(2026, 12, 31)), 20261231);
  assert.strictEqual(dayNum(kstMid(2027, 1, 1)), 20270101);
});
t('K15 윤일', () => {
  assert.strictEqual(dayNum(kstMid(2028, 2, 29)), 20280229);
  assert.strictEqual(dayNum(kstMid(2028, 3, 1)), 20280301);
});

// ══ K2 · K3 — sameDay 의미 ══════════════════════════════════════════════
//   서버의 `sameDay` 는 `srvKstDateNum(a) === srvKstDateNum(b)` 한 줄이다.
//   여기서는 그 합성을 import 한 helper 로 만들어 의미를 고정한다
//   (날짜 산술 자체는 복제하지 않는다).
const sameDay = (msA, msB) => dayNum(msA) === dayNum(msB);

console.log('\n── K2·K3 sameDay ──');
t('K2 KST 같은 날 / UTC 성분은 다름 → true', () => {
  const a = kstMid(2026, 10, 5); // 2026-10-04T15:00Z
  const b = utcMid(2026, 10, 5); // 2026-10-05T00:00Z
  // UTC 성분이 실제로 다르다는 것부터 확인한다.
  assert.notStrictEqual(new Date(a).getUTCDate(), new Date(b).getUTCDate());
  assert.strictEqual(sameDay(a, b), true);
});
t('K2b 하루 안의 다른 시각도 같은 날이다', () => {
  const base = kstMid(2026, 10, 5);
  for (const h of [0, 1, 9, 12, 23]) {
    assert.strictEqual(sameDay(base, base + h * 3600000), true, `+${h}h`);
  }
  // 하루 경계를 넘으면 다른 날.
  assert.strictEqual(sameDay(base, base + 24 * 3600000), false);
});
t('K3 KST 인접일 → false', () => {
  const d = kstMid(2026, 10, 5);
  assert.strictEqual(sameDay(d, kstMid(2026, 10, 4)), false);
  assert.strictEqual(sameDay(d, kstMid(2026, 10, 6)), false);
  // 관례를 섞어도 인접일은 인접일이다.
  assert.strictEqual(sameDay(d, utcMid(2026, 10, 4)), false);
  assert.strictEqual(sameDay(d, utcMid(2026, 10, 6)), false);
});

// ══ K4~K7 — 범위 (양끝 포함) ════════════════════════════════════════════
//   서버: `targetNum < startNum` → reject / `targetNum > endNum` → reject.
const inRange = (target, start, end) => {
  const tn = dayNum(target);
  if (tn < dayNum(start)) return false;
  if (end != null && tn > dayNum(end)) return false;
  return true;
};

console.log('\n── K4~K7 범위 ──');
const START = kstMid(2026, 10, 1);
const END = kstMid(2026, 10, 31);
t('K4 D == effectiveStart → 안쪽 (§17 inclusive)', () => {
  assert.strictEqual(inRange(kstMid(2026, 10, 1), START, END), true);
  // 저장 관례가 섞여도 같다.
  assert.strictEqual(inRange(utcMid(2026, 10, 1), START, END), true);
  assert.strictEqual(inRange(kstMid(2026, 10, 1), utcMid(2026, 10, 1), END), true);
});
t('K5 D == effectiveEnd → 안쪽 (§17 inclusive)', () => {
  assert.strictEqual(inRange(kstMid(2026, 10, 31), START, END), true);
  assert.strictEqual(inRange(utcMid(2026, 10, 31), START, END), true);
  assert.strictEqual(inRange(kstMid(2026, 10, 31), START, utcMid(2026, 10, 31)), true);
});
t('K6 D == start - 1 → 밖', () => {
  assert.strictEqual(inRange(kstMid(2026, 9, 30), START, END), false);
  assert.strictEqual(inRange(utcMid(2026, 9, 30), START, END), false);
});
t('K7 D == end + 1 → 밖', () => {
  assert.strictEqual(inRange(kstMid(2026, 11, 1), START, END), false);
  assert.strictEqual(inRange(utcMid(2026, 11, 1), START, END), false);
});
t('K7b 종료일이 없으면 끝은 열려 있다 (기존 정책 유지)', () => {
  assert.strictEqual(inRange(kstMid(2030, 1, 1), START, null), true);
  assert.strictEqual(inRange(kstMid(2026, 9, 30), START, null), false);
});
t('K7c 범위 비교가 TZ 에 무관하다 — DST 구간 포함', () => {
  // `new Date(y,mo,d)` 식은 DST 경계에서 하루 간격이 23/25시간이 됐다.
  //   정수 비교는 그 영향을 받지 않는다.
  const s = kstMid(2026, 3, 1);
  const e = kstMid(2026, 3, 31);
  for (const d of [1, 7, 8, 9, 31]) {
    assert.strictEqual(inRange(kstMid(2026, 3, d), s, e), true, `3/${d}`);
  }
  assert.strictEqual(inRange(kstMid(2026, 2, 28), s, e), false);
  assert.strictEqual(inRange(kstMid(2026, 4, 1), s, e), false);
});

// ══ K8~K10 — 배열 동등성 ════════════════════════════════════════════════
const removeDay = (arr, target) =>
  arr.filter((ms) => dayNum(ms) !== dayNum(target));
const hasDay = (arr, target) => arr.some((ms) => dayNum(ms) === dayNum(target));

console.log('\n── K8~K10 배열 동등성 ──');
t('K8 leaveDates 에서 정확히 D 만 제거된다', () => {
  const arr = [kstMid(2026, 10, 4), kstMid(2026, 10, 5), kstMid(2026, 10, 6)];
  const out = removeDay(arr, kstMid(2026, 10, 5));
  assert.deepStrictEqual(out.map(dayNum), [20261004, 20261006]);
});
t('K8b 관례가 섞인 배열에서도 정확히 D 만 제거된다', () => {
  const arr = [utcMid(2026, 10, 4), kstMid(2026, 10, 5), utcMid(2026, 10, 5),
    kstMid(2026, 10, 6)];
  const out = removeDay(arr, utcMid(2026, 10, 5));
  // 같은 업무일의 두 표현이 **둘 다** 제거된다 — 잔재가 남지 않는다.
  assert.deepStrictEqual(out.map(dayNum), [20261004, 20261006]);
});
t('K8c D-1 · D+1 은 남는다 (§32)', () => {
  const arr = [kstMid(2026, 10, 4), kstMid(2026, 10, 6)];
  assert.deepStrictEqual(removeDay(arr, kstMid(2026, 10, 5)).map(dayNum),
      [20261004, 20261006]);
});
t('K9 extraWorkDates 도 같은 자(尺) 다', () => {
  const arr = [kstMid(2026, 10, 5), utcMid(2026, 11, 1)];
  assert.deepStrictEqual(removeDay(arr, kstMid(2026, 11, 1)).map(dayNum),
      [20261005]);
});
t('K9b 중복 추가하지 않는다 — 이미 있으면 push 안 함', () => {
  const arr = [utcMid(2026, 10, 5)];
  assert.strictEqual(hasDay(arr, kstMid(2026, 10, 5)), true,
      '관례가 달라도 이미 있는 것으로 읽어야 한다');
  assert.strictEqual(hasDay(arr, kstMid(2026, 10, 6)), false);
});
t('K10 cross-type 전환 — 같은 D identity 가 유지된다 (§35)', () => {
  // NO_WORK 승인: leave 에 D 추가 + extra 에서 D 제거
  let leave = [kstMid(2026, 10, 4)];
  let extra = [utcMid(2026, 10, 5), kstMid(2026, 10, 7)];
  const D = kstMid(2026, 10, 5);
  if (!hasDay(leave, D)) leave = [...leave, D];
  extra = removeDay(extra, D);
  assert.deepStrictEqual(leave.map(dayNum), [20261004, 20261005]);
  assert.deepStrictEqual(extra.map(dayNum), [20261007]);
  // §20 상호배타
  const inter = leave.map(dayNum).filter((n) => extra.map(dayNum).includes(n));
  assert.deepStrictEqual(inter, []);

  // EXTRA_WORK 승인: 반대 방향
  let leave2 = [utcMid(2026, 10, 5)];
  let extra2 = [];
  if (!hasDay(extra2, D)) extra2 = [...extra2, D];
  leave2 = removeDay(leave2, D);
  assert.deepStrictEqual(extra2.map(dayNum), [20261005]);
  assert.deepStrictEqual(leave2.map(dayNum), []);
});

// ══ 소스 계약 ═══════════════════════════════════════════════════════════
console.log('\n── SRC schedule-change 소스 계약 ──');
const src = fs.readFileSync(SRC, 'utf8');
const span = (startMark, endMark) => {
  const a = src.indexOf(startMark);
  assert.ok(a > 0, `시작 마커 없음: ${startMark}`);
  const b = src.indexOf(endMark, a);
  assert.ok(b > a, `끝 마커 없음: ${endMark}`);
  return src.slice(a, b);
};

t('SRC1 승인 범위 재검증이 KST 날짜 수를 쓴다', () => {
  const b = span('[5B.3A.2-APPROVE-RANGE]', '[LEAVE-GUARD]');
  assert.ok(b.includes('const targetNum = srvKstDateNum(targetTs.toDate());'));
  assert.ok(b.includes('const startNum = srvKstDateNum(effectiveStart.toDate());'));
  assert.ok(b.includes('const endNum = srvKstDateNum(effectiveEnd.toDate());'));
  assert.ok(b.includes('if (targetNum < startNum) {'), '시작 경계가 양끝 포함이 아니다');
  assert.ok(b.includes('if (targetNum > endNum) {'), '종료 경계가 양끝 포함이 아니다');
  for (const banned of ['_kstToMs', '_tsToKST', '.getFullYear(', '.getMonth(',
    '.getDate(', 'new Date(']) {
    assert.ok(!b.includes(banned), `범위 재검증에 ${banned} 가 남아 있다`);
  }
  // effectiveStart/End 정의는 그대로다(§15·§16).
  assert.ok(b.includes('(appDataPre.desiredStartDate ?? appDataPre.workDate)'));
  assert.ok(b.includes('(appDataPre.actualResignDate ?? appDataPre.workEndDate ?? null)'));
});

t('SRC2 승인 배열 동등성이 같은 자(尺) 다', () => {
  const b = span('const targetDayNum =\n          srvKstDateNum(', '5. 알림 전송');
  // 비교 기준이 **어느 필드에서** 오는지까지 고정한다 — `createdAt` 같은 true
  //   instant 를 먹이면 전혀 다른 날을 건드린다(§25·§26).
  assert.ok(b.includes(
      'const targetDayNum =\n' +
      '          srvKstDateNum((scrData.targetDate as admin.firestore.Timestamp).toDate());'),
  'targetDayNum 이 scrData.targetDate 에서 오지 않는다');
  assert.ok(b.includes(
      'const sameDay = (ts: admin.firestore.Timestamp): boolean =>\n' +
      '          srvKstDateNum(ts.toDate()) === targetDayNum;'));
  for (const banned of ['.getFullYear(', '.getMonth(', '.getDate(',
    '.getUTCFullYear(', '.getUTCMonth(', '.getUTCDate(']) {
    assert.ok(!b.includes(banned), `배열 동등성에 ${banned} 가 남아 있다`);
  }
  // §18·§20 mutation 결과는 그대로다.
  assert.strictEqual(
      (b.match(/tx\.update\(appRef, \{leaveDates, extraWorkDates\}\);/g) || []).length,
      2, '상호배타 갱신이 두 분기 모두에 있어야 한다');
  // 반대 배열에서 같은 날을 **실제로 걷어내는** 식까지 고정한다 —
  //   `tx.update` 줄만 보면 filter 가 빠져도 통과한다(§20).
  assert.strictEqual(
      (b.match(/\.filter\(\(ts\) => !sameDay\(ts\)\)/g) || []).length, 4,
      'LEAVE·EXTRA 두 분기 + 취소 두 분기에서 같은 날을 걷어내야 한다');
  assert.ok(b.includes(
      'const extraWorkDates = parseDates("extraWorkDates").filter((ts) => !sameDay(ts));'),
  'LEAVE 승인이 extraWorkDates 에서 같은 날을 걷어내지 않는다');
  assert.ok(b.includes(
      'const leaveDates = parseDates("leaveDates").filter((ts) => !sameDay(ts));'),
  'EXTRA_WORK 승인이 leaveDates 에서 같은 날을 걷어내지 않는다');
  assert.ok(b.includes('tx.update(appRef, {leaveDates});'));
  assert.ok(b.includes('tx.update(appRef, {extraWorkDates});'));
});

t('SRC3 취소 경로가 같은 자(尺) 다', () => {
  const b = span('// APPROVED 상태 취소: applications 문서에서 날짜 역산',
      'tx.update(requestRef, {');
  assert.ok(b.includes('const toDayNum = (ts: admin.firestore.Timestamp) =>\n' +
      '            srvKstDateNum(ts.toDate());'));
  assert.ok(b.includes('const targetDayNum = srvKstDateNum(targetDate);'));
  assert.strictEqual((b.match(/toDayNum\(ts\) !== targetDayNum/g) || []).length, 2);
  assert.strictEqual((b.match(/toDayNum\(ts\) === targetDayNum/g) || []).length, 2);
  for (const banned of ['toDateOnly', '.getFullYear(', '.getMonth(', '.getDate(',
    'new Date(']) {
    assert.ok(!b.includes(banned), `취소 경로에 ${banned} 가 남아 있다`);
  }
  // §19 제거/복원 semantics 그대로.
  assert.ok(b.includes('tx.update(appRef, {leaveDates: filtered});'));
  assert.ok(b.includes('tx.update(appRef, {extraWorkDates: filtered});'));
  assert.ok(b.includes('tx.update(appRef, {leaveDates: rawLeave});'));
  assert.ok(b.includes('tx.update(appRef, {extraWorkDates: rawExtra});'));
});

t('SRC4 생성 중복 판정이 KST 업무일이다', () => {
  const b = span('// ── 4. 대상 날짜 계산', '// ── 6.');
  assert.ok(b.includes('const targetDayNum = srvKstDateNum(targetDate);'));
  assert.ok(b.includes(
      'const sameKstDay = (ts: admin.firestore.Timestamp): boolean =>\n' +
      '      srvKstDateNum(ts.toDate()) === targetDayNum;'));
  assert.ok(!b.includes('sameDayUTC'), 'UTC 성분 판정이 남아 있다');
  assert.ok(b.includes('sameKstDay(td)'));
  // 저장값 관례는 바꾸지 않았다(§7).
  assert.ok(src.includes('targetDate: admin.firestore.Timestamp.fromDate(targetDate),'));
});

t('SRC5 날짜별 조회의 이중 확인도 같은 자(尺) 다', () => {
  const b = span('const requestedDayNum = srvKstDateNum(new Date(dateMs!));',
      'return {items};');
  assert.ok(b.includes('if (srvKstDateNum(td.toDate()) === requestedDayNum) {'));
  for (const banned of ['.getFullYear(', '.getMonth(', '.getDate(']) {
    assert.ok(!b.includes(banned), `이중 확인에 ${banned} 가 남아 있다`);
  }
  // 쿼리 경계는 그대로 KST 하루다.
  assert.ok(b.includes('.where("targetDate", ">=", startTs)'));
  assert.ok(b.includes('.where("targetDate", "<", endTs)'));
});

t('SRC6 런타임 로컬 생성자 helper 가 제거됐다', () => {
  // 선언 형태로 본다 — 제거 사실을 적어 둔 주석은 이름을 언급해도 된다.
  assert.ok(!src.includes('function _kstToMs('), '_kstToMs 가 남아 있다');
  assert.ok(!src.includes('function _tsToKST('), '_tsToKST 가 남아 있다');
  assert.ok(!src.includes('const _KST_OFFSET_MS ='), '_KST_OFFSET_MS 가 남아 있다');
  // 호출부도 0.
  assert.ok(!/_kstToMs\(/.test(src.replace(/\/\/[^\n]*/g, '')), '_kstToMs 호출이 남아 있다');
  assert.ok(!/_tsToKST\(/.test(src.replace(/\/\/[^\n]*/g, '')), '_tsToKST 호출이 남아 있다');
});

t('K16 true instant 필드는 건드리지 않았다 (§7·§64)', () => {
  // respondedAt/requestedAt 은 serverTimestamp 그대로, KST 변환 대상 아니다.
  assert.ok(src.includes('respondedAt: admin.firestore.FieldValue.serverTimestamp()'));
  assert.ok(src.includes('requestedAt: admin.firestore.FieldValue.serverTimestamp()'));
  // 그 필드들에 날짜 수를 씌우지 않았다.
  assert.ok(!src.includes('srvKstDateNum(respondedAt'));
  assert.ok(!src.includes('srvKstDateNum(requestedAt'));
  assert.ok(!src.includes('srvKstDateNum(createdAt'));
});

t('K16b wall-clock 시간 축은 그대로다 (§8)', () => {
  // startTime/endTime 은 HH:mm 문자열 — 날짜 정규화 대상이 아니다.
  const b = span('[5B.3A.2-APPROVE-RANGE]', '5. 알림 전송');
  assert.ok(!b.includes('startTime'), '범위·동등성 판정이 wall-clock 을 건드린다');
  assert.ok(!b.includes('endTime'));
});

t('SRC7 알림 문구·권한·attendance guard 는 변경 0', () => {
  // §80 알림 — KST 라벨 그대로.
  assert.ok(src.includes('const dateStr = `${targetDateKST.getUTCMonth() + 1}월 ${targetDateKST.getUTCDate()}일`;'));
  // §21 1B attendance guard 그대로.
  assert.ok(src.includes('const leaveDateStr = srvKstDateKey(targetDateTs.toDate());'));
  assert.ok(src.includes('if (attSnap.exists && attSnap.data()?.checkIn != null) {'));
  // 권한 — **실제 검사 줄**을 고정한다. 이름이 주석에도 있어서 단순 등장
  //   검사는 주석만 남아도 통과한다.
  assert.ok(src.includes(
      'if (!scrPerms.canManageWorkers) throw new HttpsError(' +
      '"permission-denied", "근로자 관리 권한이 없습니다.");'),
  'schedule-change 권한 검사 줄이 바뀌었다');
});

console.log(`\n${pass} pass, ${fails.length} fail`);
if (fails.length > 0) {
  for (const f of fails) console.log(`  - ${f}`);
  process.exit(1);
}
