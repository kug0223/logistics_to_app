#!/usr/bin/env node
/**
 * [CORRECTION-PRE0-LONGTERM-BACKDATED-ATTENDANCE-SEED]
 *
 * PRE0 장기 fixture 의 **연대기**만 바로잡는다.
 *
 *   confirmedAt 2026-09-23 01:10  ← seed 실행 시각
 *   attendance  9/16 · 9/18 · 9/20 · 9/22
 *
 * 오늘 확정된 사람이 지난주에 일했다는 상태는 제품 경로로 만들어지지 않는다.
 * fixture 가 표현하려는 것은 "이미 확정되어 일해 온 장기 근로자"이므로,
 * 고칠 것은 근태 날짜가 아니라 **확정 시각**이다(OPTION A).
 *
 * 왜 cleanup + reseed 가 아닌가
 * ─────────────────────────────
 * reseed 는 공고를 지운다. 그런데 이 fixture 공고에는 다른 DEV 계정이
 * 지원했다가 취소한 기록이 달려 있다. 그것은 fixture 소유가 아니다 —
 * 공고가 같다는 이유로 남의 기록을 지우지 않는다. 확정·이체까지 간
 * 근태 4건과 그에 딸린 급여 집계도 그대로 두는 편이 옳다.
 * 어긋난 것은 타임스탬프 두 개뿐이고, 그것만 고친다.
 *
 *   node scripts/pre0-longterm-chronology-fix.js --project alfit-89567
 *   node scripts/pre0-longterm-chronology-fix.js --project alfit-89567 --execute
 *
 * manifest 에 적힌 id 만 읽고 쓴다. 쿼리로 훑어 고치지 않는다.
 * 여러 번 실행해도 결과가 같다.
 */
'use strict';

const EXPECTED_DEV_PROJECT = 'alfit-89567';
const argv = process.argv.slice(2);
const projectId = (() => {
  const i = argv.indexOf('--project');
  return i >= 0 ? argv[i + 1] : null;
})();
if (projectId !== EXPECTED_DEV_PROJECT) {
  console.error(`DEV 전용입니다. --project ${EXPECTED_DEV_PROJECT}`);
  process.exit(2);
}
const EXECUTE = argv.includes('--execute');

const path = require('path');
const {admin, db} = require('./r7-fixture-lib');

const SCENARIO = 'R7_FIX_LT_WORKER';
const MANIFEST = path.join(__dirname, 'r7-fixture-manifest-dev.json');
const KST = 9 * 3600e3;

const dayNum = (ms) =>
  Number(new Date(ms + KST).toISOString().slice(0, 10).replace(/-/g, ''));
const stamp = (ms) =>
  new Date(ms + KST).toISOString().replace('T', ' ').slice(0, 19) + ' KST';
/** 그 시각이 속한 KST 날짜의 자정(UTC epoch ms). */
const kstMidnightOf = (ms) => {
  const k = new Date(ms + KST);
  return Date.UTC(k.getUTCFullYear(), k.getUTCMonth(), k.getUTCDate()) - KST;
};
const WK = ['일', '월', '화', '수', '목', '금', '토'];

/** 서버 srvLongTermEligibleOnDay 와 같은 규칙. */
function eligibility(app, attDayMs) {
  const day = dayNum(attDayMs);
  const at = (k) => app[k];
  let startNum = at('desiredStartDate') ?
    dayNum(at('desiredStartDate').toMillis()) :
    (at('workDate') ? dayNum(at('workDate').toMillis()) : 0);
  if (!at('desiredStartDate') && at('confirmedAt')) {
    const c = dayNum(at('confirmedAt').toMillis());
    if (c > startNum) startNum = c;
  }
  if (day < startNum) return 'BEFORE_START';
  const resign = at('actualResignDate');
  const end = resign || at('workEndDate');
  if (!end) return 'NO_END';
  if (day > dayNum(end.toMillis())) return resign ? 'AFTER_RESIGN' : 'AFTER_END';
  const has = (k) => Array.isArray(app[k]) &&
    app[k].some((t) => t && t.toDate && dayNum(t.toMillis()) === day);
  if (has('extraWorkDates')) return 'ELIGIBLE';
  if (has('leaveDates')) return 'LEAVE';
  const wd = app.workDays;
  const w = WK[new Date(attDayMs + KST).getUTCDay()];
  if (!Array.isArray(wd) || wd.length === 0 || !wd.includes(w)) {
    return 'NON_WORKDAY';
  }
  return 'ELIGIBLE';
}

async function main() {
  const manifest = require(MANIFEST);
  const rec = (manifest.scenarios || {})[SCENARIO];
  if (!rec) throw new Error(`manifest 에 ${SCENARIO} 기록이 없습니다.`);
  const appId = rec.entities.applicationId;
  console.log(`\n${SCENARIO}  ${EXECUTE ? '' : '(dry-run — --execute 로 반영)'}`);
  console.log(`application ${appId}\n`);

  // ── 1. fixture 소유 근태만 모은다 (manifest 에 적힌 id) ─────────
  const attIds = [...new Set([
    rec.entities.yesterdayAttendanceId,
    ...Object.values(rec.entities.payroll || {}),
  ].filter((v) => typeof v === 'string'))];

  const appRef = db.collection('applications').doc(appId);
  const appSnap = await appRef.get();
  if (!appSnap.exists) throw new Error('지원서가 없습니다. seed 부터 하세요.');
  const app = appSnap.data();

  const atts = [];
  for (const id of attIds) {
    const s = await db.collection('attendance').doc(id).get();
    if (!s.exists) { console.log(`   없음  ${id}`); continue; }
    atts.push({id, data: s.data()});
  }
  if (atts.length === 0) throw new Error('fixture 근태가 하나도 없습니다.');

  // ── 2. 현재 상태 ────────────────────────────────────────────────
  console.log('BEFORE');
  console.log(`   appliedAt    ${stamp(app.appliedAt.toMillis())}`);
  console.log(`   confirmedAt  ${stamp(app.confirmedAt.toMillis())}`);
  console.log(`   workDate     ${dayNum(app.workDate.toMillis())}` +
    `   workEndDate ${app.workEndDate ? dayNum(app.workEndDate.toMillis()) : '-'}`);
  const before = {};
  for (const a of atts) {
    const v = eligibility(app, a.data.workDate.toMillis());
    before[v] = (before[v] || 0) + 1;
    console.log(`   ${v.padEnd(13)} ${a.id.split('_').pop()}  ` +
      `wage=${a.data.wageStatus}`);
  }

  // ── 3. 되돌릴 시각 — 가장 이른 근무일 아침 ──────────────────────
  //   그날 06:00 근무 시작 전이어야 한다. 근태에서 직접 뽑으므로
  //   이 스크립트를 언제 돌려도 같은 값이 나온다.
  const earliestMs = Math.min(...atts.map((a) => a.data.workDate.toMillis()));
  const confirmedAtMs = kstMidnightOf(earliestMs) + 5 * 3600e3;
  const appliedAtMs = kstMidnightOf(earliestMs) - 24 * 3600e3 + 9 * 3600e3;

  const already = app.confirmedAt.toMillis() === confirmedAtMs &&
    app.appliedAt.toMillis() === appliedAtMs;
  console.log(`\n되돌릴 값 (가장 이른 근무일 ${dayNum(earliestMs)} 기준)`);
  console.log(`   appliedAt    ${stamp(appliedAtMs)}`);
  console.log(`   confirmedAt  ${stamp(confirmedAtMs)}`);
  if (already) console.log('   이미 적용돼 있습니다 — 다시 쓰지 않습니다.');

  // ── 4. 적용 후 판정 ─────────────────────────────────────────────
  const after = {...app, confirmedAt: admin.firestore.Timestamp.fromMillis(confirmedAtMs)};
  const tally = {};
  for (const a of atts) {
    const v = eligibility(after, a.data.workDate.toMillis());
    tally[v] = (tally[v] || 0) + 1;
  }
  console.log(`\nBEFORE ${JSON.stringify(before)}`);
  console.log(`AFTER  ${JSON.stringify(tally)}`);
  const bad = Object.keys(tally).filter((k) => k !== 'ELIGIBLE');
  if (bad.length > 0) {
    throw new Error(`보정해도 ${bad.join(',')} 가 남습니다 — 쓰지 않습니다.`);
  }

  // ── 5. 쓰기 — 타임스탬프 두 개뿐 ────────────────────────────────
  if (!EXECUTE) { console.log('\ndry-run — 아무것도 쓰지 않았습니다.'); return; }
  if (already) { console.log('\n변경 없음.'); return; }
  await appRef.update({
    appliedAt: admin.firestore.Timestamp.fromMillis(appliedAtMs),
    confirmedAt: admin.firestore.Timestamp.fromMillis(confirmedAtMs),
  });
  console.log('\n반영했습니다 — appliedAt · confirmedAt 두 필드만.');
  console.log('약속(workDate·workEndDate·workDays·임금·시간)은 그대로입니다.');
}

main().then(() => process.exit(0)).catch((e) => {
  console.error('\n실패:', e && e.message ? e.message : e);
  process.exit(1);
});
