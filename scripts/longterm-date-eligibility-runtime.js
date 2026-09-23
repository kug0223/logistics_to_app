#!/usr/bin/env node
/**
 * [LONGTERM-DATE-ELIGIBILITY] DEV 런타임 검증 — 서버 mutation gate.
 *
 * 이 BLOCKER는 "화면은 근무 아님이라는데 서버가 attendance를 만들어 준다"는
 * 것이었다. 그러므로 코드 테스트만으로 닫지 않는다. **배포된 CF를 실제로
 * 불러서** 거절/허용을 본다.
 *
 * 기존 DEV 장기 entity 하나로는 before-start / after-end 를 만들 수 없다
 * (그 계약 기간이 출근 허용 창을 전부 덮는다). 그래서 DEV 전용 synthetic
 * fixture를 쓴다 — 전부 `LTDE_` 접두사의 결정적 id이고, 끝나면 정확히
 * 그 id들만 지운다. 기존 데이터는 건드리지 않는다.
 *
 *   node scripts/longterm-date-eligibility-runtime.js --project alfit-89567
 *
 * 쓰는 것: LTDE_* applications (+ 허용 케이스의 LTDE_* attendance)
 * 지우는 것: 같은 id들뿐.
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
const keepFixtures = argv.includes('--keep');

const {admin, db, callAs} = require('./r7-fixture-lib');

const BIZ = 'fLmSOHVKUwmBHcbwQE0I';
const ADMIN = 'BErRdiWP1xbgyoTovxwAPNEsuD72';
const WORKER = 'tJ8izfP2nNYN79aPTLb6YARiPqC3';
const TO_ID = 'zqaJEjUVPA6O1FWajlTX';
const LAT = 37.1432540168018;
const LNG = 127.060063542351;
const PREFIX = 'LTDE_';

const KST = 9 * 3600e3;
const DAY = 86400e3;
const ALL_DAYS = ['월', '화', '수', '목', '금', '토', '일'];
const WK = ['일', '월', '화', '수', '목', '금', '토'];

/** KST 달력 기준 offset일의 KST 자정 epoch ms. */
function kstMidnight(offset = 0) {
  const k = new Date(Date.now() + KST);
  return Date.UTC(k.getUTCFullYear(), k.getUTCMonth(), k.getUTCDate() + offset) - KST;
}
const ts = (ms) => admin.firestore.Timestamp.fromMillis(ms);
const key = (ms) => new Date(ms + KST).toISOString().slice(0, 10);
const wkd = (ms) => WK[new Date(ms + KST).getUTCDay()];

const TODAY = kstMidnight(0);
const todayWkd = wkd(TODAY);
const otherWkd = ALL_DAYS.filter((d) => d !== todayWkd);

// ══════════════════════════════════════════════════════════════════
// fixture 정의 — 전부 오늘(KST) 출근을 시도한다. 다른 조건은 동일하고
// 날짜 규칙 하나씩만 다르다.
// ══════════════════════════════════════════════════════════════════
const CASES = [
  {
    id: `${PREFIX}OK`, expect: 'ALLOW',
    why: '정상 근무일 — 기간 안 · 요일 일치',
    fields: {workDate: ts(kstMidnight(-5)), workEndDate: ts(kstMidnight(5)), workDays: ALL_DAYS},
  },
  {
    id: `${PREFIX}AFTER_END`, expect: 'REJECT',
    why: '계약 종료 이후 — BLOCKER-1',
    fields: {workDate: ts(kstMidnight(-60)), workEndDate: ts(kstMidnight(-10)), workDays: ALL_DAYS},
  },
  {
    id: `${PREFIX}BEFORE_START`, expect: 'REJECT',
    why: '계약 시작 이전 · desiredStartDate 없음 — BLOCKER-2',
    fields: {workDate: ts(kstMidnight(10)), workEndDate: ts(kstMidnight(60)), workDays: ALL_DAYS},
  },
  {
    id: `${PREFIX}CONFIRMED_LATER`, expect: 'REJECT',
    why: '공고 시작은 지났지만 확정이 내일 — 확정일 보정',
    fields: {
      workDate: ts(kstMidnight(-30)), workEndDate: ts(kstMidnight(30)),
      workDays: ALL_DAYS, confirmedAt: ts(kstMidnight(1)),
    },
  },
  {
    id: `${PREFIX}RESIGN_D`, expect: 'ALLOW',
    why: '퇴사 효력일 당일 — 마지막 근무 가능일이다',
    fields: {
      workDate: ts(kstMidnight(-20)), workEndDate: ts(kstMidnight(20)),
      workDays: ALL_DAYS, actualResignDate: ts(TODAY),
    },
  },
  {
    id: `${PREFIX}RESIGN_D1`, expect: 'REJECT',
    why: '퇴사 효력일 다음날',
    fields: {
      workDate: ts(kstMidnight(-20)), workEndDate: ts(kstMidnight(20)),
      workDays: ALL_DAYS, actualResignDate: ts(kstMidnight(-1)),
    },
  },
  {
    id: `${PREFIX}LEAVE`, expect: 'REJECT',
    why: '승인된 휴무일',
    fields: {
      workDate: ts(kstMidnight(-5)), workEndDate: ts(kstMidnight(5)),
      workDays: ALL_DAYS, leaveDates: [ts(TODAY)],
    },
  },
  {
    id: `${PREFIX}NON_WORKDAY`, expect: 'REJECT',
    why: '오늘 요일이 근무요일이 아님',
    fields: {workDate: ts(kstMidnight(-5)), workEndDate: ts(kstMidnight(5)), workDays: otherWkd},
  },
  {
    id: `${PREFIX}EXTRA`, expect: 'ALLOW',
    why: '비근무요일이지만 추가근무 승인일',
    fields: {
      workDate: ts(kstMidnight(-5)), workEndDate: ts(kstMidnight(5)),
      workDays: otherWkd, extraWorkDates: [ts(TODAY)],
    },
  },
  {
    id: `${PREFIX}NO_END`, expect: 'REJECT',
    why: '기간 미정 — 무기한으로 해석하지 않는다',
    fields: {workDate: ts(kstMidnight(-5)), workDays: ALL_DAYS},
  },
];

const base = () => ({
  toId: TO_ID,
  businessId: BIZ,
  businessName: '위워커',
  toTitle: '[LTDE] 날짜 자격 검증',
  uid: WORKER,
  applicantName: 'LTDE 테스트',
  status: 'CONFIRMED',
  type: 'long_term',
  selectedWorkType: '사무업무',
  startTime: '06:00',
  endTime: '08:00',
  wage: 12000,
  wageType: 'hourly',
  appliedAt: admin.firestore.Timestamp.now(),
  confirmedAt: ts(kstMidnight(-90)),
  idCardConsentGiven: true,
  isLtdeFixture: true,
});

const rows = [];

async function main() {
  console.log(`\nDEV=${projectId}  오늘(KST)=${key(TODAY)} (${todayWkd})`);
  console.log(`비근무요일 fixture의 workDays=${JSON.stringify(otherWkd)}\n`);

  // ── 0. 사전 inventory ────────────────────────────────────────
  const preApps = (await db.collection('applications').get()).size;
  const preAtt = (await db.collection('attendance').get()).size;
  console.log(`사전 inventory — applications ${preApps} / attendance ${preAtt}`);

  // ── 1. fixture 생성 ─────────────────────────────────────────
  const batch = db.batch();
  for (const c of CASES) {
    batch.set(db.collection('applications').doc(c.id), {...base(), ...c.fields});
  }
  await batch.commit();
  console.log(`fixture ${CASES.length}건 생성 (전부 ${PREFIX} 접두사)\n`);

  // ── 2. 개별 출근 ────────────────────────────────────────────
  console.log('─'.repeat(74));
  console.log('callableCheckIn (근로자 본인)');
  console.log('─'.repeat(74));
  for (const c of CASES) {
    let outcome; let detail = '';
    try {
      await callAs(WORKER, 'callableCheckIn', {
        applicationId: c.id, businessId: BIZ, businessName: '위워커',
        workDateMs: TODAY, workType: '사무업무',
        latitude: LAT, longitude: LNG, method: 'gps',
      });
      outcome = 'ALLOW';
    } catch (e) {
      outcome = 'REJECT';
      detail = String(e.message).replace(/^callableCheckIn 실패 /, '');
    }
    const ok = outcome === c.expect;
    rows.push({id: c.id, why: c.why, expect: c.expect, direct: outcome, ok});
    console.log(`${ok ? 'PASS' : 'FAIL'}  ${c.id.padEnd(22)} ${outcome.padEnd(6)} ${c.why}`);
    if (detail) console.log(`        ${detail}`);
  }

  // ── 3. 관리자 배치 출근 — 같은 지원서·같은 날짜 ──────────────
  console.log('\n' + '─'.repeat(74));
  console.log('callableBatchCheckIn (관리자) — direct와 같은 답이어야 한다');
  console.log('─'.repeat(74));
  const nowMs = Date.now();
  for (const c of CASES) {
    let outcome; let detail = '';
    try {
      const r = await callAs(ADMIN, 'callableBatchCheckIn', {
        businessId: BIZ,
        entries: [{
          applicationId: c.id, workDateMs: TODAY, userId: WORKER,
          businessId: BIZ, businessName: '위워커', workType: '사무업무',
          status: 'present', checkInMs: nowMs,
        }],
      });
      const skipped = (r && (r.skipped || r.failed || [])) || [];
      const invalid = JSON.stringify(r).includes('invalidWorkContext') ||
        (Array.isArray(skipped) && skipped.length > 0);
      outcome = invalid ? 'REJECT' : 'ALLOW';
      detail = JSON.stringify(r).slice(0, 150);
    } catch (e) {
      outcome = 'REJECT';
      detail = String(e.message).slice(0, 150);
    }
    const row = rows.find((x) => x.id === c.id);
    row.batch = outcome;
    row.parity = outcome === row.direct;
    console.log(
      `${row.parity ? 'PARITY' : 'SPLIT '}  ${c.id.padEnd(22)} ` +
      `direct=${row.direct.padEnd(6)} batch=${outcome}`);
    if (!row.parity) console.log(`        ${detail}`);
  }

  // ── 4. 요약 ─────────────────────────────────────────────────
  console.log('\n' + '═'.repeat(74));
  const failed = rows.filter((r) => !r.ok);
  const split = rows.filter((r) => r.parity === false);
  console.log(`날짜 게이트   : ${rows.length - failed.length}/${rows.length} 기대와 일치`);
  console.log(`direct↔batch : ${rows.length - split.length}/${rows.length} 동일`);
  if (failed.length) console.log('불일치:', failed.map((r) => r.id).join(', '));
  if (split.length) console.log('갈린 것:', split.map((r) => r.id).join(', '));

  // ── 5. cleanup — 정확히 LTDE_ 접두사만 ───────────────────────
  if (keepFixtures) {
    console.log('\n--keep — fixture를 남깁니다.');
    return;
  }
  const attSnap = await db.collection('attendance').get();
  const madeAtt = attSnap.docs.filter((d) => d.id.startsWith(PREFIX));
  console.log(`\ncleanup — attendance ${madeAtt.length}건 / applications ${CASES.length}건`);
  madeAtt.forEach((d) => console.log(`   attendance ${d.id} (status=${d.data().status})`));
  const del = db.batch();
  madeAtt.forEach((d) => del.delete(d.ref));
  CASES.forEach((c) => del.delete(db.collection('applications').doc(c.id)));
  await del.commit();

  const postApps = (await db.collection('applications').get()).size;
  const postAtt = (await db.collection('attendance').get()).size;
  console.log(`사후 inventory — applications ${postApps} / attendance ${postAtt}`);
  console.log(
    postApps === preApps && postAtt === preAtt ?
      'RESTORED — 사전과 동일. 다른 문서는 건드리지 않았습니다.' :
      `DRIFT — apps ${postApps - preApps} / att ${postAtt - preAtt}`);
}

main().then(() => process.exit(0)).catch((e) => {
  console.error('FAIL', e);
  process.exit(1);
});
