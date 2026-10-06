// [R7-CROSSCUT-TIME.1B] 휴무 승인 guard 의 날짜 키 — **실제 프로세스 TZ** 통제.
//
//   실행:  cd functions && node test/leave_guard_date_key.test.js
//
//   왜 자식 프로세스인가: 한 프로세스의 TZ 는 바꿀 수 없고, 이 호스트는 KST
//   (UTC+9) 다. 그래서 TZ 를 바꾼 자식을 띄워 **같은 식**을 실행시킨다.
//   KST 호스트에서는 로컬 성분을 쓰는 결함이 보이지 않는다 — 그 사실 자체가
//   이 셀이 존재하는 이유다.
//
//   고정하는 것
//     · `callableApproveScheduleChangeRequest` 의 LEAVE-GUARD 키 식은
//       `+9h` → `getUTC*` 이므로 런타임 TZ 와 무관하다.
//     · 로컬 성분(`getFullYear/getMonth/getDate`)을 쓰는 식은 TZ 에 끌려간다.
//     · 두 저장 관례(KST 자정 instant / DATE_ONLY UTC 자정) 모두에서 같은 키.
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const {execFileSync} = require('child_process');

const SRC = path.join(__dirname, '..', 'src', 'index.ts');
const TZS = ['Asia/Seoul', 'UTC', 'America/Los_Angeles',
  'Pacific/Kiritimati', 'Asia/Kolkata'];

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

// 자식에서 돌릴 코드. **실제 canonical owner 를 import** 한다 — 포팅한 사본이
//   아니다. 그래서 그 함수가 바뀌면 이 셀이 바로 깨진다.
const CHILD = `
const M = require(${JSON.stringify(
    path.join(__dirname, '..', 'lib', 'commitment_dates.js'))});
// guard 는 \`srvKstDateKey(d)\` = \`String(srvKstDateNum(d))\` = \`String(kstDateNum(d))\`.
function guardKey(ms) {
  return String(M.kstDateNum(new Date(ms)));
}
// 대조군 — 런타임 로컬 성분을 쓰는 식.
function localKey(ms) {
  const d = new Date(ms);
  return String(d.getFullYear()) +
    String(d.getMonth() + 1).padStart(2, "0") +
    String(d.getDate()).padStart(2, "0");
}
const cases = JSON.parse(process.argv[1]);
const out = {tz: process.env.TZ, offsetMin: new Date().getTimezoneOffset(),
  guard: {}, local: {}};
for (const [label, ms] of Object.entries(cases)) {
  out.guard[label] = guardKey(ms);
  out.local[label] = localKey(ms);
}
process.stdout.write(JSON.stringify(out));
`;

/** KST 달력일 D 의 자정 instant(ms). */
const kstMidnight = (y, m, d) => Date.UTC(y, m - 1, d) - 9 * 3600 * 1000;
/** 관리자 다이얼로그가 저장하는 DATE_ONLY 비교 키(ms) = UTC 자정. */
const dateOnly = (y, m, d) => Date.UTC(y, m - 1, d);

const CASES = {
  // §12 통제 타임스탬프
  'kst_20261005': kstMidnight(2026, 10, 5),
  'dateonly_20261005': dateOnly(2026, 10, 5),
  // §40 월 경계
  'kst_20261101': kstMidnight(2026, 11, 1),
  'dateonly_20261101': dateOnly(2026, 11, 1),
  // §41 연 경계
  'kst_20270101': kstMidnight(2027, 1, 1),
  'dateonly_20270101': dateOnly(2027, 1, 1),
  // 윤년
  'kst_20280229': kstMidnight(2028, 2, 29),
  // 미국 DST 전환 주변(현지 3/8)
  'kst_20260308': kstMidnight(2026, 3, 8),
};
const EXPECT = {
  'kst_20261005': '20261005', 'dateonly_20261005': '20261005',
  'kst_20261101': '20261101', 'dateonly_20261101': '20261101',
  'kst_20270101': '20270101', 'dateonly_20270101': '20270101',
  'kst_20280229': '20280229',
  'kst_20260308': '20260308',
};

function runIn(tz) {
  const raw = execFileSync(process.execPath,
      ['-e', CHILD, JSON.stringify(CASES)],
      {env: {...process.env, TZ: tz}, encoding: 'utf8'});
  return JSON.parse(raw);
}

console.log('\n── TZ1 서버 guard 키는 런타임 TZ 와 무관하다 ──');
const results = {};
for (const tz of TZS) {
  t(`TZ1 ${tz}`, () => {
    const r = runIn(tz);
    results[tz] = r;
    for (const [label, want] of Object.entries(EXPECT)) {
      assert.strictEqual(r.guard[label], want,
          `${tz}: ${label} → ${r.guard[label]} (기대 ${want})`);
    }
  });
}

t('TZ1b 모든 TZ 의 guard 키가 서로 같다', () => {
  const sets = Object.entries(results).map(([tz, r]) =>
    [tz, JSON.stringify(r.guard)]);
  const uniq = new Set(sets.map(([, s]) => s));
  assert.strictEqual(uniq.size, 1,
      `TZ 별로 키가 갈렸다: ${JSON.stringify(sets, null, 1)}`);
});

t('TZ1c 자식이 실제로 다른 TZ 로 떴다 — 통제가 작동했다', () => {
  const offsets = Object.fromEntries(
      Object.entries(results).map(([tz, r]) => [tz, r.offsetMin]));
  // Asia/Seoul = -540, UTC = 0 (분, getTimezoneOffset 부호 규약)
  assert.strictEqual(offsets['Asia/Seoul'], -540, JSON.stringify(offsets));
  assert.strictEqual(offsets['UTC'], 0, JSON.stringify(offsets));
  assert.ok(offsets['America/Los_Angeles'] > 0, JSON.stringify(offsets));
  assert.strictEqual(new Set(Object.values(offsets)).size >= 4, true,
      `오프셋이 충분히 다르지 않다: ${JSON.stringify(offsets)}`);
});

console.log('\n── TZ2 로컬 성분 식은 TZ 에 끌려간다 (대조군) ──');
t('TZ2 같은 순간인데 TZ 마다 다른 날짜가 나온다', () => {
  const seoul = results['Asia/Seoul'].local['kst_20261005'];
  const utc = results['UTC'].local['kst_20261005'];
  const la = results['America/Los_Angeles'].local['kst_20261005'];
  assert.strictEqual(seoul, '20261005');
  assert.strictEqual(utc, '20261004', `UTC → ${utc}`);
  assert.strictEqual(la, '20261004', `LA → ${la}`);
  assert.ok(new Set([seoul, utc, la]).size > 1, '대조군이 갈리지 않았다');
});

console.log('\n── SRC guard 식이 소스에 그대로 있다 ──');
t('SRC1 LEAVE-GUARD 가 canonical owner 를 부른다 — 인라인 조립 0', () => {
  const src = fs.readFileSync(SRC, 'utf8');
  const i = src.indexOf('// [LEAVE-GUARD]');
  assert.ok(i > 0, 'LEAVE-GUARD 블록을 찾지 못했다');
  // 창을 1400자로 잡으면 이웃 코드까지 먹는다 — 끝 마커로 경계를 조인다.
  const e = src.indexOf('// 요청 상태 업데이트', i);
  assert.ok(e > i, 'guard 의 끝 경계를 찾지 못했다');
  const block = src.slice(i, e);
  assert.ok(
      block.includes('const leaveDateStr = srvKstDateKey(targetDateTs.toDate());'),
      'guard 가 canonical owner 를 쓰지 않는다');
  // `targetDateTs` 안에 `getDate` 가 부분문자열로 들어 있다 — 메서드 호출
  //   형태로 금지어를 쓴다.
  for (const banned of ['KST_OFFSET_MS', 'padStart', '.getUTC',
    '.getFullYear(', '.getMonth(', '.getDate(', '86400000']) {
    assert.ok(!block.includes(banned), `guard 에 ${banned} 가 남아 있다`);
  }
  // owner 본문도 고정 — 여기서 날짜를 옮기면 모든 소비자가 함께 틀어진다.
  assert.ok(/function srvKstDateKey\(d: Date\): string \{\r?\n  return String\(srvKstDateNum\(d\)\);\r?\n\}/
      .test(src), 'srvKstDateKey 본문이 바뀌었다');
});

t('SRC2 attendance writer 와 같은 키 포맷이다 — writer/reader parity', () => {
  const src = fs.readFileSync(SRC, 'utf8');
  // canonical writer (`callableCheckIn`) 는 아직 인라인 식을 쓴다.
  //   값은 같다(아래 PAR1 이 behavioral 로 확인) — 식의 수렴은 잔여 과제다.
  const w = src.indexOf('const workDateKST = new Date(workDateMs + KST_OFFSET_MS);');
  assert.ok(w > 0, 'writer 의 KST 변환을 찾지 못했다');
  assert.ok(src.includes('${workDateKST.getUTCFullYear()}'));
  const pads = (src.match(/getUTCMonth\(\) \+ 1\)\.padStart\(2, "0"\)/g) || []).length;
  assert.ok(pads >= 4, `zero padding 지점이 적다: ${pads}`);
});

t('PAR1 writer 인라인 식과 canonical owner 가 같은 값을 낸다', () => {
  const M = require('../lib/commitment_dates');
  const KST_OFFSET_MS = 9 * 3600 * 1000;
  // writer 가 쓰는 식 그대로.
  const writerKey = (ms) => {
    const k = new Date(ms + KST_OFFSET_MS);
    return String(k.getUTCFullYear()) +
      String(k.getUTCMonth() + 1).padStart(2, '0') +
      String(k.getUTCDate()).padStart(2, '0');
  };
  for (const [label, ms] of Object.entries(CASES)) {
    assert.strictEqual(writerKey(ms), String(M.kstDateNum(new Date(ms))),
        `${label}: writer 와 guard 의 키가 갈렸다`);
  }
  // 한 자리 월·일에서도 (padStart vs 산술) 같은지 확인.
  for (const [y, m, d] of [[2026, 1, 5], [2026, 9, 9], [2026, 12, 31]]) {
    const ms = Date.UTC(y, m - 1, d) - KST_OFFSET_MS;
    assert.strictEqual(writerKey(ms), String(M.kstDateNum(new Date(ms))));
    assert.strictEqual(writerKey(ms).length, 8);
  }
});

console.log(`\n${pass} pass, ${fails.length} fail`);
if (fails.length > 0) {
  for (const f of fails) console.log(`  - ${f}`);
  process.exit(1);
}
