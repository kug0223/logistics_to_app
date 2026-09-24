#!/usr/bin/env node
/**
 * [BLOCKER-RENEWAL-DECISION-QUEUE-POPULATION-PARITY §15~§22]
 *
 * 같은 미결정 Application 이 Home 에서는 존재하고 목적지에서는 날짜
 * cutoff 때문에 사라지는가 — 그것 하나만 본다.
 *
 * 180일 경계 양쪽(179 / 181)과 훨씬 오래된 건(400)을 직접 때린다.
 *
 *   node scripts/lt-renewal-population-parity-runtime.js --project alfit-89567
 *   node scripts/lt-renewal-population-parity-runtime.js --project alfit-89567 --execute
 *   node scripts/lt-renewal-population-parity-runtime.js --project alfit-89567 --cleanup --execute
 */
'use strict';

const EXPECTED_DEV_PROJECT = 'alfit-89567';
const PROD_PROJECT_ID = 'alfit-prod';
const argv = process.argv.slice(2);
const projectId = (() => {
  const i = argv.indexOf('--project');
  return i >= 0 ? argv[i + 1] : null;
})();
if (projectId === PROD_PROJECT_ID) {
  console.error('PROD 프로젝트입니다. 실행하지 않습니다.');
  process.exit(2);
}
if (projectId !== EXPECTED_DEV_PROJECT) {
  console.error(`DEV 전용입니다. --project ${EXPECTED_DEV_PROJECT}`);
  process.exit(2);
}
const EXECUTE = argv.includes('--execute');
const CLEANUP = argv.includes('--cleanup');

const fs = require('fs');
const path = require('path');
const {admin, db, callAs, kstMidnightMs, kstDateKey} =
  require('./r7-fixture-lib');
const admin_ts = (ms) => admin.firestore.Timestamp.fromMillis(ms);

const BIZ = 'fLmSOHVKUwmBHcbwQE0I';
const OTHER_BIZ = '0GweEvbpP6KA7v14FMLb'; // ADMIN 이 관리하지 않는 사업장
const ADMIN = 'BErRdiWP1xbgyoTovxwAPNEsuD72';
// 장기(슬롯 없는) 공고라 isIdVerified gate 대상이 아니다.
// tJ8iz… 는 오늘 masterScheduler 자동 NO_SHOW 로 1일 지원 제한이 걸려
// 있어 쓸 수 없다 — 그 제한을 우회하지 않고 다른 근무자를 쓴다.
const WORKER = 'J6lVRGSFsBewqvWy0gFE46YQI9z1';
const NS = 'LTPOP';
const STATE = path.join(__dirname, '.lt-population-parity-state.json');

const UPCOMING_WINDOW_DAYS = 15;

/**
 * 경계 fixture — §15·§18·§19
 *
 * [§18 DEV EXACT-WRITE — product mutation 증거 아님]
 *   canonical 지원 writer 로는 오늘 이 fixture 들을 만들 수 없다.
 *   180/400일 전 종료 계약을 만들려면 그 기간의 공고에 지원해야 하는데,
 *   쓸 수 있는 근무자(tJ8iz…)는 오늘 masterScheduler 가 만든 자동
 *   NO_SHOW 때문에 1일 지원 제한이 걸려 있다. 그 제한을 풀거나 다른
 *   근무자의 서류 심사를 통과시키는 것은 PRE0/제품 상태를 건드리는
 *   일이라 하지 않는다.
 *
 *   이번 Phase 가 보는 것은 **reader 의 population** 이다. reader 는
 *   businessId · status · workEndDate · renewalDecision · type ·
 *   workDays 만 본다. 그래서 canonical 장기 지원서 문서를 그대로
 *   복제하고 그 여섯 가지만 바꿔 exact-id 로 쓴다.
 *
 *   이 문서들은 **writer 경로를 증명하지 않는다.** writer 는 .4B 에서
 *   canonical 경로로 이미 증명했고 이번 Phase 는 write 를 하지 않는다.
 */
const FIXTURE_SOURCE_APP =
  'zqaJEjUVPA6O1FWajlTX_사무업무_tJ8izfP2nNYN79aPTLb6YARiPqC3';
const FIXTURES = [
  {key: 'd179', endOffset: -179, status: 'CONFIRMED',
    title: '179일 전 미결정', resolve: null},
  {key: 'd181', endOffset: -181, status: 'CONTRACT_PENDING',
    title: '181일 전 미결정', resolve: null},
  {key: 'd400', endOffset: -400, status: 'CONFIRMED',
    title: '400일 전 미결정', resolve: null},
  {key: 'd300x', endOffset: -300, status: 'CONFIRMED',
    title: '300일 전 연장완료', resolve: 'EXTEND'},
];
const fixtureDocId = (key) => `${NS}_${key}_dev_fixture`;

const KST = 9 * 3600e3;
const iso = (ts) => ts ?
  new Date(ts.toMillis() + KST).toISOString().slice(0, 10) : null;

const log = (...a) => console.log(...a);
const head = (s) => log(`\n${'─'.repeat(74)}\n${s}\n${'─'.repeat(74)}`);
const results = [];
const check = (label, ok, detail) => {
  results.push({label, ok});
  log(`${ok ? 'PASS' : 'FAIL'}  ${label}${detail ? `\n        ${detail}` : ''}`);
};
const readState = () =>
  fs.existsSync(STATE) ? JSON.parse(fs.readFileSync(STATE, 'utf8')) : {};
const writeState = (s) => fs.writeFileSync(STATE, JSON.stringify(s, null, 2));
const loadApp = async (id) =>
  (await db.collection('applications').doc(id).get()).data();

/** 클라이언트 renewalDecisionStateOf 의 거울. */
function decisionState(app, todayNum) {
  const dn = (ts) => Number(new Date(ts.toMillis() + KST)
      .toISOString().slice(0, 10).replace(/-/g, ''));
  const isLong = app.type === 'long_term' ||
    (Array.isArray(app.workDays) && app.workDays.length > 0);
  if (!isLong) return 'NOT_APPLICABLE';
  if (app.renewalDecision) return 'RESOLVED';
  const done = ['APPROVED', 'AUTO_APPROVED'];
  if (done.includes(app.resignStatus) || done.includes(app.terminationStatus)) {
    return 'RESOLVED';
  }
  if (!['CONFIRMED', 'CONTRACT_PENDING'].includes(app.status)) {
    return 'NOT_APPLICABLE';
  }
  const end = app.actualResignDate || app.workEndDate;
  if (!end) return 'NOT_APPLICABLE';
  const endNum = dn(end);
  if (endNum < todayNum) return 'EXPIRED';
  const p = (n) => Date.UTC(Math.floor(n / 10000),
      Math.floor((n % 10000) / 100) - 1, n % 100);
  return (p(endNum) - p(todayNum)) / 86400000 <= UPCOMING_WINDOW_DAYS ?
    'UPCOMING' : 'NOT_APPLICABLE';
}

/** Home 의 계약 결정 섹션(서버 집계). */
async function homeContractSection() {
  const r = await callAs(ADMIN, 'callableGetAdminHomeSummary', {});
  return (r && r.upcoming && r.upcoming.expiringContract) || null;
}

/**
 * ExpiringContracts 가 실제로 쓰는 조회의 거울 —
 * getExpiringLongTermApplications 와 같은 파라미터·같은 union.
 */
async function expiringCandidates(bizId = BIZ) {
  const endBeforeMs = kstMidnightMs(UPCOMING_WINDOW_DAYS + 1);
  const stats = {queries: 0, returned: 0};
  const byId = new Map();
  for (const status of ['CONFIRMED', 'CONTRACT_PENDING']) {
    let cursor = null;
    for (let page = 0; page < 50; page++) {
      stats.queries++;
      const r = await callAs(ADMIN, 'callableGetApplicationsByBiz', {
        businessId: bizId, status, workEndDateLtMs: endBeforeMs, limit: 200,
        ...(cursor ? {startAfterDocId: cursor} : {}),
      });
      const apps = (r && r.applications) || [];
      stats.returned += apps.length;
      apps.forEach((a) => byId.set(a.id, a));
      if (r.hasMore !== true || !r.lastDocId) break;
      cursor = r.lastDocId;
    }
  }
  return {docs: [...byId.values()], stats};
}

async function inventory(label) {
  const [ap, ec, at, tos] = await Promise.all([
    db.collection('applications').get(),
    db.collection('employment_contracts').get(),
    db.collection('attendance').get(),
    db.collection('tos').get(),
  ]);
  const inv = {applications: ap.size, contracts: ec.size,
    attendance: at.size, tos: tos.size};
  log(`${label}  ${JSON.stringify(inv)}`);
  return inv;
}

async function cleanup() {
  const st = readState();
  head('cleanup — state 에 적힌 id 만 (broad 조건 삭제 없음)');
  const before = await inventory('BEFORE');
  // exact id 만 — workEndDate < cutoff 같은 broad 조건은 쓰지 않는다.
  for (const f of FIXTURES) {
    const id = st[`${f.key}App`] || fixtureDocId(f.key);
    const ref = db.collection('applications').doc(id);
    if (!(await ref.get()).exists) continue;
    log(`   지원서 ${id}`);
    if (EXECUTE) await ref.delete();
  }
  if (!EXECUTE) { log('\ndry-run — 아무것도 지우지 않았습니다.'); return; }
  const after = await inventory('AFTER ');
  log(JSON.stringify({
    applications: after.applications - before.applications,
    contracts: after.contracts - before.contracts,
    attendance: after.attendance - before.attendance,
    tos: after.tos - before.tos,
  }));
  if (fs.existsSync(STATE)) fs.unlinkSync(STATE);
}

/** §18 DEV exact-write — canonical 장기 지원서를 복제하고 6개 필드만 바꾼다. */
async function buildFixture(st, f, source) {
  const kApp = `${f.key}App`;
  const id = fixtureDocId(f.key);
  const ref = db.collection('applications').doc(id);
  if (!(await ref.get()).exists) {
    const doc = {...source};
    // 실행마다 달라지는 흔적은 지운다 — reader 가 보지 않는 값들이다.
    for (const k of ['reminderSentDate', 'matchingAutoMatchStatus',
      'matchingReadinessState']) delete doc[k];
    doc.statusHistory = [];
    doc.toId = `${NS}_${f.key}_to`; // 실제 공고를 건드리지 않는다
    doc.toTitle = `[${NS}] ${f.title}`;
    doc.workDate =
      admin_ts(kstMidnightMs(f.endOffset - 30));
    doc.workEndDate = admin_ts(kstMidnightMs(f.endOffset));
    doc.status = f.status;
    if (f.resolve) doc.renewalDecision = f.resolve;
    await ref.set(doc);
    st[kApp] = id; writeState(st);
  } else if (!st[kApp]) {
    st[kApp] = id; writeState(st);
  }
  return loadApp(id);
}

async function main() {
  if (CLEANUP) return cleanup();
  log(`\nDEV=${projectId}  ${EXECUTE ? '' : '(dry-run)'}`);
  const todayNum = Number(kstDateKey(0).replace(/-/g, ''));

  head('기준선');
  const invBefore = await inventory('BEFORE');
  const homeBefore = await homeContractSection();
  const listBefore = await expiringCandidates();
  log(`Home    ${JSON.stringify(homeBefore)}`);
  log(`조회    ${listBefore.docs.length}건 · query ${listBefore.stats.queries}회`);
  if (!EXECUTE) { log('\ndry-run 종료.'); return; }

  const st = readState();
  if (FIXTURES.some((f) => st[`${f.key}App`])) {
    head('이미 실행된 fixture — --cleanup --execute 후 재실행');
    process.exitCode = 2; return;
  }

  // ── §15·§18·§19 fixtures ───────────────────────────────────────
  head('§15 경계 fixture — 180일 양쪽 · 400일 · 오래된 해결건');
  log('   [§18 DEV EXACT-WRITE] canonical 장기 지원서 복제 + 6필드 교체.');
  log('   writer 경로 증명 아님 — 이번 Phase 는 reader population 만 본다.');
  const srcSnap =
    await db.collection('applications').doc(FIXTURE_SOURCE_APP).get();
  if (!srcSnap.exists) {
    throw new Error(`복제 원본이 없다: ${FIXTURE_SOURCE_APP}`);
  }
  const source = srcSnap.data();
  const built = {};
  for (const f of FIXTURES) {
    built[f.key] = await buildFixture(st, f, source);
    log(`   ${f.key.padEnd(6)} ${st[`${f.key}App`]}`);
    log(`          종료 ${iso(built[f.key].workEndDate)} · ` +
        `status ${built[f.key].status} · ` +
        `renewalDecision ${built[f.key].renewalDecision ?? 'null'} · ` +
        `판정 ${decisionState(built[f.key], todayNum)}`);
  }
  check('§15 179일 fixture = EXPIRED',
      decisionState(built.d179, todayNum) === 'EXPIRED');
  check('§15 181일 fixture = EXPIRED',
      decisionState(built.d181, todayNum) === 'EXPIRED');
  check('§18 400일 fixture = EXPIRED',
      decisionState(built.d400, todayNum) === 'EXPIRED');
  check('§19 300일 EXTEND fixture = RESOLVED',
      decisionState(built.d300x, todayNum) === 'RESOLVED');

  // ── §17 Home population ────────────────────────────────────────
  head('§17 Home population');
  const homeAfter = await homeContractSection();
  log(`   BEFORE ${JSON.stringify(homeBefore)}`);
  log(`   AFTER  ${JSON.stringify(homeAfter)}`);
  check('§17 Home 이 미결정 3건을 더 센다 — 해결건은 세지 않는다',
      homeAfter.count === (homeBefore.count || 0) + 3,
      `${homeBefore.count} → ${homeAfter.count}`);
  check('§17 셋 다 만료로 센다',
      homeAfter.expiredCount === (homeBefore.expiredCount || 0) + 3,
      `${homeBefore.expiredCount} → ${homeAfter.expiredCount}`);

  // ── §17·§20 조회 population ────────────────────────────────────
  head('§17·§20 목적지 population — applicationId 집합 비교');
  const listAfter = await expiringCandidates();
  const listIds = new Set(listAfter.docs.map((d) => d.id));
  for (const key of ['d179', 'd181', 'd400']) {
    check(`§17 ${key} 가 목적지 조회에 들어온다`,
        listIds.has(st[`${key}App`]), st[`${key}App`]);
  }
  check('§19 오래된 해결건은 후보로 조회돼도 결정 대상이 아니다',
      listIds.has(st.d300xApp) &&
      decisionState(built.d300x, todayNum) === 'RESOLVED');

  // Home 이 센 것과 목적지가 보여줄 것의 집합 일치.
  const listDecisionIds = new Set(listAfter.docs
      .filter((d) => {
        const ts = (v) => v && v._seconds !== undefined ?
          {toMillis: () => v._seconds * 1000} : v;
        return decisionState({
          ...d,
          workEndDate: ts(d.workEndDate),
          actualResignDate: ts(d.actualResignDate),
        }, todayNum) !== 'NOT_APPLICABLE' &&
        ['EXPIRED', 'UPCOMING'].includes(decisionState({
          ...d,
          workEndDate: ts(d.workEndDate),
          actualResignDate: ts(d.actualResignDate),
        }, todayNum));
      })
      .map((d) => d.id));
  log(`   Home count=${homeAfter.count} · 목적지 결정대상=${listDecisionIds.size}`);
  check('§20 Home count == 목적지 결정 대상 수',
      homeAfter.count === listDecisionIds.size,
      `${homeAfter.count} vs ${listDecisionIds.size}`);
  check('§21 Home 이 센 건은 모두 목적지에서 찾을 수 있다',
      [...listDecisionIds].length === homeAfter.count &&
      ['d179', 'd181', 'd400'].every((k) => listDecisionIds.has(st[`${k}App`])));

  // ── §22 business scope ─────────────────────────────────────────
  head('§22 business scope — 하한 제거가 범위를 느슨하게 만들지 않았다');
  check('§22 조회 결과가 전부 이 사업장 문서다',
      listAfter.docs.every((d) => d.businessId === BIZ),
      `${listAfter.docs.length}건`);
  check('§22 Home byBusiness 도 이 사업장뿐',
      (homeAfter.byBusiness || []).every((b) => b.businessId === BIZ));
  const crossErr = await callAs(ADMIN, 'callableGetApplicationsByBiz', {
    businessId: OTHER_BIZ, status: 'CONFIRMED',
    workEndDateLtMs: kstMidnightMs(16), limit: 200,
  }).then(() => null).catch((e) => e.message);
  check('§22 타 사업장 조회는 거절된다', !!crossErr, crossErr || '통과해버림');

  // ── §23 permission ─────────────────────────────────────────────
  head('§23 permission — NO_PERMISSION ≠ ZERO');
  const noPerm = await callAs(WORKER, 'callableGetApplicationsByBiz', {
    businessId: BIZ, status: 'CONFIRMED',
    workEndDateLtMs: kstMidnightMs(16), limit: 200,
  }).then((r) => `통과해버림 (${(r.applications || []).length}건)`)
      .catch((e) => e.message);
  check('§23 권한 없는 호출은 거절 — 0건인 척하지 않는다',
      noPerm.includes('[') , noPerm);

  // ── §31 read evidence ──────────────────────────────────────────
  head('§31 read 증거');
  log(`   query ${listAfter.stats.queries}회 · 서버 반환 ${listAfter.stats.returned}건`);
  log(`   중복 제거 후 ${listAfter.docs.length}건 · 결정 대상 ${listDecisionIds.size}건`);
  log(`   상한 workEndDate < ${kstDateKey(UPCOMING_WINDOW_DAYS + 1)} · 하한 없음`);
  check('§31 status·business 로 서버에서 좁힌다 — 전체 scan 아님',
      listAfter.stats.queries === 2 &&
      listAfter.docs.every((d) => d.businessId === BIZ));

  head('요약');
  await inventory('AFTER ');
  log(`   기준선 ${JSON.stringify(invBefore)}`);
  const failed = results.filter((r) => !r.ok);
  log(`\n   ${results.length - failed.length}/${results.length} PASS`);
  failed.forEach((r) => log(`     · ${r.label}`));
  if (failed.length > 0) process.exitCode = 1;
  log('\n   정리: --cleanup --execute');
}

main().then(() => process.exit(process.exitCode || 0)).catch((e) => {
  console.error('\n실패:', e && e.message ? e.message : e);
  process.exit(1);
});
