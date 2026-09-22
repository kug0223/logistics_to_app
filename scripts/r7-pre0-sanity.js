#!/usr/bin/env node
/**
 * [R7-PRE0] cross-surface sanity.
 *
 * 문서 개수를 세지 않는다. **같은 사실을 여러 표면이 같게 말하는가**를 본다.
 * 그래서 가능한 곳에서는 화면이 쓰는 바로 그 canonical reader(CF)를 부른다 —
 * 판정식을 여기서 다시 써 놓으면 내 복제본을 검증하게 된다.
 *
 * CF 가 없는(클라이언트 안에서만 도는) 판정은 출처를 주석으로 명시하고
 * 옮겨 적는다. 그 경우 "이 스크립트가 옮긴 규칙"임을 보고에 남긴다.
 *
 *   node scripts/r7-pre0-sanity.js --project alfit-89567
 *
 * 읽기 전용이다. 아무것도 쓰지 않는다.
 */
'use strict';

const fs = require('fs');
const path = require('path');

const EXPECTED_DEV_PROJECT = 'alfit-89567';
const argv = process.argv.slice(2);
const projectId = (() => {
  const i = argv.indexOf('--project');
  return i >= 0 ? argv[i + 1] : null;
})();
if (projectId !== EXPECTED_DEV_PROJECT) {
  console.error(`이 스크립트는 DEV 전용입니다. --project ${EXPECTED_DEV_PROJECT}`);
  process.exit(2);
}

const {db, callAs, kstDateKey} = require('./r7-fixture-lib');

const ROOT = path.resolve(__dirname, '..');
const MANIFEST = JSON.parse(fs.readFileSync(
    path.join(ROOT, 'scripts', 'r7-fixture-manifest-dev.json'), 'utf8'));

const BIZ = 'fLmSOHVKUwmBHcbwQE0I';
const ADMIN = 'BErRdiWP1xbgyoTovxwAPNEsuD72';
const WORKER = 'tJ8izfP2nNYN79aPTLb6YARiPqC3';

const KST = 9 * 3600e3;
const DAY = 24 * 3600e3;
const KR = ['일', '월', '화', '수', '목', '금', '토'];

const log = (...a) => console.log(...a);
const head = (s) => console.log(`\n${'─'.repeat(72)}\n${s}\n`);

/** 판정 결과 누적 — 끝에서 한 번에 요약한다. */
const findings = [];
const record = (level, id, text) => {
  findings.push({level, id, text});
  log(`   ${level === 'OK' ? 'OK      ' : level.padEnd(8)} ${text}`);
};

function kstMidnightOf(ms) {
  const k = new Date(ms + KST);
  return Date.UTC(k.getUTCFullYear(), k.getUTCMonth(), k.getUTCDate()) - KST;
}
const dayKey = (ms) => new Date(kstMidnightOf(ms) + KST).toISOString().slice(0, 10);
const weekdayOf = (key) => KR[new Date(key + 'T00:00:00Z').getUTCDay()];

// ── 지원서 조회 — fetchApplicationsByBizPaged 와 같은 CF·같은 페이징 ──
async function appsByBiz(params) {
  const out = [];
  let cursor = null;
  for (let page = 0; page < 50; page++) {
    const r = await callAs(ADMIN, 'callableGetApplicationsByBiz',
        {...params, ...(cursor ? {startAfterDocId: cursor} : {})});
    out.push(...(r.applications || []));
    if (r.hasMore !== true) return out;
    cursor = r.lastDocId;
    if (!cursor) return out;
  }
  throw new Error('appsByBiz: 50페이지를 넘겼습니다.');
}

/**
 * 당일명단(AttendanceStatusDialog._getConfirmedWorkersForDate) 의 판정.
 *
 * CF 가 아니라 다이얼로그 안에 있는 규칙이라 여기에 옮겨 적는다.
 * 출처: lib/screens/business_admin/dialogs/attendance_status_dialog.dart:404
 */
async function rosterForDate(dateKey) {
  const start = Date.parse(dateKey + 'T00:00:00Z') - KST;
  const end = start + DAY;
  const CONFIRMED = new Set(['CONFIRMED', 'CONTRACT_PENDING']);
  const seen = new Set();
  const out = [];

  const [shortRaw, longRaw] = await Promise.all([
    appsByBiz({businessId: BIZ, workDateGteMs: start, workDateLtMs: end, limit: 2000}),
    appsByBiz({businessId: BIZ, type: 'long_term', limit: 2000}),
  ]);

  for (const a of shortRaw) {
    if (!CONFIRMED.has(a.status)) continue;
    if (a.workDays && a.workDays.length > 0) continue;   // 장기 경로에서 처리
    if (!seen.has(a.id)) { seen.add(a.id); out.push(a); }
  }

  const ms = (v) => (v == null ? null
    : typeof v === 'number' ? v
    : v._seconds != null ? v._seconds * 1000
    : v.seconds != null ? v.seconds * 1000
    : Date.parse(v));

  for (const a of longRaw) {
    if (!CONFIRMED.has(a.status)) continue;
    const endMs = ms(a.actualResignDate) ?? ms(a.workEndDate);
    let startMs = ms(a.desiredStartDate) ?? ms(a.workDate);
    const confirmedAt = ms(a.confirmedAt);
    if (confirmedAt != null && ms(a.desiredStartDate) == null &&
        kstMidnightOf(confirmedAt) > kstMidnightOf(ms(a.workDate))) {
      startMs = confirmedAt;
    }
    const startKey = dayKey(startMs);
    if (endMs != null) {
      if (dateKey < startKey || dateKey > dayKey(endMs)) continue;
    } else {
      if (dateKey < startKey) continue;
      if (a.isTerminationApproved === true) continue;
    }
    const inList = (arr) => (arr || []).some((t) => dayKey(ms(t)) === dateKey);
    if (inList(a.leaveDates)) continue;
    const extra = inList(a.extraWorkDates);
    const wd = a.workDays || [];
    if (extra || wd.length === 0 || wd.includes(weekdayOf(dateKey))) {
      if (!seen.has(a.id)) { seen.add(a.id); out.push(a); }
    }
  }
  return out;
}

/** 그 날 그 사람에게 아직 할 일이 남았는가 — Home 의 마감 조건과 같다. */
function isClosed(att) {
  if (!att) return false;
  const ws = att.wageStatus || '';
  return ws === 'confirmed' || ws === 'transferred' || att.status === 'NO_SHOW';
}

// ═══════════════════════════════════════════════════════════════════
async function sectionA() {
  head('A. Home 「마감 필요」 ↔ 당일명단 actionable membership');

  const summary = await callAs(ADMIN, 'callableGetAdminHomeSummary',
      {selectedBusinessId: BIZ});
  const unclosed = (summary.actions || {}).unclosed || {};
  log(`   Home  : 마감 필요 ${unclosed.count}일 · 가장 오래된 ${unclosed.oldestDate}` +
      ` · available=${unclosed.available}`);

  const queue = await callAs(ADMIN, 'callableGetUnclosedActionQueue', {});
  log(`   Queue : available=${queue.available} · rows ${(queue.rows || []).length}건`);
  if (queue.available !== true) {
    record('BLOCKER', 'A', 'Unclosed Queue 가 available=false 다 — rows 를 믿을 수 없다.');
    return;
  }

  const rows = (queue.rows || []).filter((r) => r.businessId === BIZ);
  const dates = rows.map((r) => r.workDateStr).sort();
  log(`   이 사업장 rows: ${rows.length}건  (${dates[0]} ~ ${dates[dates.length - 1]})`);

  if (unclosed.count !== rows.length) {
    record('CORRECTION', 'A',
        `Home count(${unclosed.count}일) ≠ Queue rows(${rows.length}건). ` +
        '둘 다 business×date 가 단위여야 한다.');
  } else {
    record('OK', 'A', `Home ${unclosed.count}일 = Queue ${rows.length}건 (단위 일치)`);
  }

  // 각 행이 실제로 처리할 사람을 갖고 있는가 — 없으면 "없는 업무"다.
  log('\n   날짜별 대조 (Queue remainingCount ↔ 당일명단에서 아직 안 닫힌 사람 수)');
  let emptyTasks = 0;
  let mismatched = 0;
  const sample = rows.slice().sort((a, b) => a.workDateStr.localeCompare(b.workDateStr));
  for (const r of sample) {
    const roster = await rosterForDate(r.workDateStr);
    const ids = roster.map((a) => `${a.id}_${r.workDateStr.replace(/-/g, '')}`);
    const snaps = ids.length
      ? await db.getAll(...ids.map((i) => db.collection('attendance').doc(i)))
      : [];
    const open = snaps.filter((s) => !isClosed(s.exists ? s.data() : null)).length;
    const mark = open === 0 ? '  ← 처리할 사람 0' : (open === r.remainingCount ? '' : '  ← 불일치');
    log(`     ${r.workDateStr}  Queue ${r.closedCount}/${r.totalConfirmed} 남음 ${r.remainingCount}` +
        ` · 당일명단 ${roster.length}명 중 미마감 ${open}명${mark}`);
    if (open === 0) emptyTasks++;
    else if (open !== r.remainingCount) mismatched++;
  }

  if (emptyTasks > 0) {
    record('BLOCKER', 'A',
        `실제 처리할 사람이 0인 날짜가 ${emptyTasks}건 — Home 이 없는 업무를 만든다.`);
  } else {
    record('OK', 'A', '모든 마감 필요 날짜에 실제 처리 대상이 있다 (없는 업무 0건).');
  }
  if (mismatched > 0) {
    record('CORRECTION', 'A',
        `Queue remainingCount 와 당일명단 미마감 인원이 다른 날짜 ${mismatched}건.`);
  } else {
    record('OK', 'A', 'Queue remainingCount = 당일명단 미마감 인원 (모든 날짜).');
  }
}

// ═══════════════════════════════════════════════════════════════════
async function sectionB() {
  head('B. FLEX canonical date ↔ 각 reader');

  const flexIds = ['R7_FIX_POST_SHORTAGE', 'R7_FIX_POST_MIXED', 'R7_FIX_POST_CLOSED']
      .map((k) => (MANIFEST.scenarios[k] || {}).entities)
      .filter(Boolean);

  for (const e of flexIds) {
    const toSnap = await db.collection('tos').doc(e.toId).get();
    const to = toSnap.data();
    const slots = await db.collection('tos').doc(e.toId)
        .collection('slots').orderBy('date').get();
    const slotDates = slots.docs.map((d) => dayKey(d.data().date.toMillis()));

    log(`   ${to.title}`);
    log(`     TO.dates        : ${to.dates ? JSON.stringify(to.dates) : '없음 ← TO 레벨 날짜 필드 부재'}`);
    log(`     슬롯 날짜        : ${JSON.stringify(slotDates)}`);
    log(`     rangeStart/End  : ${dayKey(to.rangeStart.toMillis())} ~ ${dayKey(to.rangeEnd.toMillis())}`);
    log(`     status          : ${to.status} · isManualClosed=${to.isManualClosed === true}`);

    const rangeCovers = slotDates.every((d) =>
      d >= dayKey(to.rangeStart.toMillis()) && d <= dayKey(to.rangeEnd.toMillis()));
    if (!rangeCovers) {
      record('CORRECTION', 'B',
          `${to.title}: rangeStart~rangeEnd 가 슬롯 날짜를 덮지 못한다.`);
    }
    if (!to.dates) {
      record('NOTE', 'B',
          `${to.title}: TO 문서에 dates 가 없다 — 날짜 truth 는 슬롯뿐이다. ` +
          'TO 레벨 dates 를 읽는 reader 가 있으면 그 화면은 날짜를 모른다.');
    }
  }

  // staffing reader — 화면이 쓰는 canonical CF 를 그대로 부른다.
  const sh = MANIFEST.scenarios.R7_FIX_POST_SHORTAGE.entities;
  log('\n   날짜별 staffing (callableGetDayStaffingDetail — 당일명단·지원자 화면과 같은 출처)');
  for (const d of sh.dates) {
    const dayStart = Date.parse(d + 'T00:00:00Z') - KST;
    const r = await callAs(ADMIN, 'callableGetDayStaffingDetail',
        {businessId: BIZ, dateMs: dayStart});
    const mine = (r.rows || []).filter((x) => x.toId === sh.toId);
    log(`     ${d}  rows ${(r.rows || []).length}건 (이 공고 ${mine.length}건)` +
        mine.map((x) => ` [${x.workType} ${x.confirmedCount}/${x.requiredCount}` +
          ` closed=${x.isClosed}]`).join(''));
    if (mine.length === 0) {
      record('CORRECTION', 'B',
          `${d}: staffing reader 가 SHORTAGE 공고의 모집 단위를 돌려주지 않는다.`);
    }
  }

  // 근로자 쪽 노출 — 공개 공고 목록이 쓰는 필드 기준.
  log('\n   근로자 노출 판정 재료 (worker Jobs / Home 날짜칩)');
  for (const k of ['R7_FIX_POST_SHORTAGE', 'R7_FIX_POST_MIXED', 'R7_FIX_POST_CLOSED']) {
    const e = MANIFEST.scenarios[k].entities;
    const to = (await db.collection('tos').doc(e.toId).get()).data();
    const slots = await db.collection('tos').doc(e.toId).collection('slots').get();
    const today = kstDateKey(0);
    const live = slots.docs.filter((s) => {
      const sd = s.data();
      return dayKey(sd.date.toMillis()) >= today && sd.isClosed !== true;
    }).length;
    log(`     ${k.padEnd(22)} isPublished=${to.isPublished === true}` +
        ` status=${to.status} manualClosed=${to.isManualClosed === true}` +
        ` · 오늘 이후 살아있는 슬롯 ${live}개`);
  }
}

// ═══════════════════════════════════════════════════════════════════
async function sectionC() {
  head('C. Payroll — money truth 와 worked-day/hour metric 분리 판정');

  // [범위 주의] payroll_summaries 는 사업장×월×근로자 전체 집계다.
  //   fixture 문서만 골라 비교하면 DEV 의 기존 근태가 차이로 나타나 오탐이 된다.
  //   그래서 같은 범위(이 근로자 · 이 사업장 · 이 달) 전체를 센다.
  const month = kstDateKey(0).slice(0, 7);
  const mStart = Date.parse(`${month}-01T00:00:00Z`) - KST;
  const mEnd = Date.parse(`${month}-01T00:00:00Z`) + 32 * DAY;
  const q = await db.collection('attendance')
      .where('businessId', '==', BIZ)
      .where('userId', '==', WORKER)
      .where('workDate', '>=', new Date(mStart))
      .where('workDate', '<', new Date(mEnd - (mEnd % DAY)))
      .get();
  const snaps = q.docs.filter((d) => dayKey(d.data().workDate.toMillis()).startsWith(month));

  let actualDays = 0; let actualHours = 0;
  let settledDays = 0; let settledAmount = 0; let transferredAmount = 0;
  log(`   ${month} · 이 근로자 · 이 사업장 근태 ${snaps.length}건`);
  for (const s of snaps) {
    const a = s.data();
    const key = dayKey(a.workDate.toMillis());
    const hrs = a.workHours || 0;
    log(`     ${key}  status=${String(a.status).padEnd(8)} wageStatus=${String(a.wageStatus).padEnd(12)}` +
        ` finalWage=${a.finalWage || 0} checkIn=${a.checkIn ? '있음' : '없음'} workHours=${hrs}`);
    if (a.checkIn) { actualDays++; actualHours += hrs; }
    if (['confirmed', 'transferred'].includes(a.wageStatus) && a.status !== 'NO_SHOW') {
      settledDays++; settledAmount += a.finalWage || 0;
    }
    if (a.wageStatus === 'transferred') transferredAmount += a.finalWage || 0;
  }
  log(`\n   실근무(체크인 기준)      : ${actualDays}일 / ${actualHours}시간`);
  log(`   정산 완료(confirmed+)   : ${settledDays}일 / ${settledAmount.toLocaleString()}원`);
  log(`   이체 완료               : ${transferredAmount.toLocaleString()}원`);

  // 화면이 읽는 집계 문서 (payroll_summaries/{biz}_{YYYY-MM}/workers/{uid})
  log('\n   payroll_summaries (Payroll 화면이 읽는 집계)');
  let sumDays = 0; let sumPayout = 0;
  {
    const w = await db.collection('payroll_summaries').doc(`${BIZ}_${month}`)
        .collection('workers').doc(WORKER).get();
    const root = await db.collection('payroll_summaries').doc(`${BIZ}_${month}`).get();
    if (!w.exists) {
      log(`     ${month}  workers/{uid} 없음`);
    } else {
      const d = w.data();
      log(`     ${month}  workDays=${d.workDays} ` +
          `totalPayout=${(d.totalPayout || 0).toLocaleString()}원` +
          ` · root notTransferred=${root.data().notTransferredCount}` +
          (root.data().repairedAt ? ' (repair 이력 있음)' : ''));
      sumDays += d.workDays || 0; sumPayout += d.totalPayout || 0;
    }
  }

  // 돈과 실적을 따로 본다.
  if (sumPayout === settledAmount) {
    record('OK', 'C',
        `money truth 일치: 집계 ${sumPayout.toLocaleString()}원 = 확정 근태 합계 ` +
        `${settledAmount.toLocaleString()}원.`);
  } else {
    record('BLOCKER', 'C',
        `집계 금액 ${sumPayout.toLocaleString()}원 ≠ 근태 합계 ` +
        `${settledAmount.toLocaleString()}원.`);
  }

  if (sumDays !== actualDays) {
    record('CORRECTION', 'C',
        `worked-day metric 과소: 집계 workDays=${sumDays} vs 실근무 ${actualDays}일. ` +
        'onAttendanceWageChanged 가 wageStatus∈{confirmed,transferred} 인 건만 ' +
        '+1 하므로 "근무일"이 아니라 "정산 완료일"이다 — 돈은 맞고 라벨이 틀렸다. ' +
        '(functions/src/index.ts:4643 confirmedCountDelta)');
  } else {
    record('OK', 'C', `worked-day metric 일치: ${sumDays}일 = 실근무 ${actualDays}일.`);
  }

  // 같은 필드를 쓰는 두 writer 가 NO_SHOW 를 다르게 센다.
  const noShowSettled = snaps.filter((s) =>
    s.data().status === 'NO_SHOW' &&
    ['confirmed', 'transferred'].includes(s.data().wageStatus)).length;
  if (noShowSettled > 0) {
    record('CORRECTION', 'C',
        `NO_SHOW ${noShowSettled}건에 대해 두 writer 가 다르게 센다 — ` +
        '증분 트리거 onAttendanceWageChanged 는 status==="absent" 만 걸러서 ' +
        'NO_SHOW 를 workDays+1 로 세고(index.ts:4581), 복구 CF ' +
        'callableRepairPayrollSummaries 는 NO_SHOW 를 제외한다(index.ts:29819). ' +
        'repair 를 한 번 돌리면 같은 데이터에서 숫자가 달라진다. 금액은 0원이라 동일.');
  }
}

// ═══════════════════════════════════════════════════════════════════
async function sectionD() {
  head('D. 같은 사람·같은 근무를 표면들이 같게 말하는가 (Posting / Application / Contract / Attendance)');

  const rows = [];
  for (const [id, rec] of Object.entries(MANIFEST.scenarios)) {
    const e = rec.entities || {};
    if (!e.applicationId) continue;
    const app = (await db.collection('applications').doc(e.applicationId).get()).data();
    if (!app) { record('BLOCKER', 'D', `${id}: 지원서가 없다.`); continue; }

    // 계약 — 관리자 화면이 쓰는 CF 와 같은 컬렉션·같은 키
    const cSnap = await db.collection('employment_contracts')
        .where('applicationId', '==', e.applicationId).get();
    const contracts = cSnap.docs.map((d) => d.data().status);

    // 근무 — 이 지원서에 달린 근태
    const att = await db.collection('attendance')
        .where('applicationId', '==', e.applicationId).get();

    // 공고 쪽 확정 수
    const toId = e.toId || e.sharedToId;
    let slotLine = '';
    if (toId && e.slotId) {
      const s = (await db.collection('tos').doc(toId)
          .collection('slots').doc(e.slotId).get()).data();
      const req = ((s.workDetails || [])[0] || {}).requiredCount || 0;
      slotLine = ` 슬롯 ${s.confirmedCount || 0}/${req}`;
    }
    rows.push({id, status: app.status, contracts, att: att.size, slotLine});
    log(`   ${id.padEnd(26)} 지원서=${String(app.status).padEnd(17)}` +
        ` 계약=[${contracts.join(',') || '없음'}] 근태 ${att.size}건${slotLine}`);
  }

  // 계약 완료 ↔ 지원서 CONFIRMED 는 같이 움직여야 한다.
  for (const r of rows) {
    const done = r.contracts.includes('completed');
    if (done && r.status !== 'CONFIRMED') {
      record('BLOCKER', 'D',
          `${r.id}: 계약 completed 인데 지원서가 ${r.status} 다.`);
    }
    if (!done && r.status === 'CONFIRMED' && r.contracts.length > 0) {
      record('CORRECTION', 'D',
          `${r.id}: 지원서 CONFIRMED 인데 계약이 [${r.contracts.join(',')}] 다.`);
    }
  }
  if (!findings.some((f) => f.id === 'D' && f.level !== 'OK')) {
    record('OK', 'D', '계약 상태와 지원서 상태가 모든 fixture 에서 짝이 맞는다.');
  }

  // 공고 카드 확정 수 ↔ 지원서 집계
  log('\n   공고 확정 카운터 ↔ 실제 확정 지원서');
  for (const key of ['R7_FIX_POST_SHORTAGE', 'R7_FIX_POST_MIXED', 'R7_FIX_LT_WORKER']) {
    const e = MANIFEST.scenarios[key].entities;
    const to = (await db.collection('tos').doc(e.toId).get()).data();
    const apps = await db.collection('applications').where('toId', '==', e.toId).get();
    const confirmed = apps.docs.filter((d) =>
      ['CONFIRMED', 'CONTRACT_PENDING'].includes(d.data().status) &&
      !d.data().staffingReleasedAt).length;
    const pending = apps.docs.filter((d) => d.data().status === 'PENDING').length;
    const ok = (to.totalConfirmed || 0) === confirmed;
    log(`     ${key.padEnd(24)} TO.totalConfirmed=${to.totalConfirmed || 0}` +
        ` 실제 확정=${confirmed} · TO.totalPending=${to.totalPending || 0} 실제=${pending}` +
        (ok ? '' : '  ← 불일치'));
    if (!ok) {
      record('BLOCKER', 'D',
          `${key}: TO.totalConfirmed(${to.totalConfirmed || 0}) ≠ 실제 확정 지원서(${confirmed}).`);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
async function main() {
  log('R7-PRE0 cross-surface sanity  (읽기 전용)');
  log(`  project : ${projectId}`);
  log(`  fixture : ${Object.keys(MANIFEST.scenarios).length}건`);
  log(`  오늘(KST): ${kstDateKey(0)}`);

  await sectionA();
  await sectionB();
  await sectionC();
  await sectionD();

  head('판정 요약');
  const by = (l) => findings.filter((f) => f.level === l);
  for (const l of ['BLOCKER', 'CORRECTION', 'NOTE']) {
    for (const f of by(l)) log(`   [${l}] (${f.id}) ${f.text}`);
  }
  log(`\n   OK ${by('OK').length} · CORRECTION ${by('CORRECTION').length} ·` +
      ` NOTE ${by('NOTE').length} · BLOCKER ${by('BLOCKER').length}`);
  process.exit(by('BLOCKER').length > 0 ? 1 : 0);
}

main().catch((e) => {
  console.error('\n실패:', e && e.message ? e.message : e);
  process.exit(1);
});
