#!/usr/bin/env node
/**
 * [R7-PRE0] DEV Product Fixture Pack — seed / verify / cleanup
 *
 * R7 실기기 검증에서 같은 상태를 반복 재현하기 위한 고정 시나리오 세트.
 * 예쁜 테스트 데이터를 많이 만드는 것이 목적이 아니다. 각 fixture 는
 * "무엇을 확인하려는가"가 분명해야 하고, canonical writer 로만 만든다.
 *
 * ─────────────────────────────────────────────────────────────────────
 * 왜 canonical writer(CF)만 쓰는가
 *
 *   Admin SDK 로 문서를 직접 쓰면 서버 guard 를 전부 우회한다. 그러면
 *   실제로는 존재할 수 없는 조합(취소된 지원서 + 완료된 계약 같은)이
 *   조용히 만들어지고, R7 에서 그것을 보고 "제품 버그"라고 부르게 된다.
 *   CF 를 통과시키면 그런 상태는 애초에 만들어지지 않는다.
 *
 *   직접 쓰기는 오직 manifest 파일(로컬 JSON)뿐이다.
 *
 * ─────────────────────────────────────────────────────────────────────
 * 사용
 *
 *   node scripts/seed-r7-fixtures-dev.js --project alfit-89567            (dry-run)
 *   node scripts/seed-r7-fixtures-dev.js --project alfit-89567 --execute
 *   node scripts/seed-r7-fixtures-dev.js --project alfit-89567 --verify
 *   node scripts/seed-r7-fixtures-dev.js --project alfit-89567 --cleanup --execute
 *
 *   --project alfit-89567 은 필수다. 다른 값이면 즉시 종료한다.
 *
 * ─────────────────────────────────────────────────────────────────────
 * idempotency
 *
 *   manifest 에 기록된 entity 가 살아 있으면 다시 만들지 않는다.
 *   seed → seed 를 두 번 해도 같은 논리 상태가 된다.
 *
 * cleanup
 *
 *   manifest 에 적힌 것만, 만든 역순으로 지운다. 쿼리로 훑어서 지우지
 *   않는다 — DEV 에는 이 스크립트가 만들지 않은 실사용 데이터가 있고,
 *   그것들에는 fixture 표식이 없다.
 */
'use strict';

const fs = require('fs');
const path = require('path');

// ─── CLI ────────────────────────────────────────────────────────────
const argv = process.argv.slice(2);
const args = {};
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (!a.startsWith('--')) continue;
  const k = a.slice(2);
  const next = argv[i + 1];
  if (next && !next.startsWith('--')) { args[k] = next; i++; } else { args[k] = true; }
}

const EXPECTED_DEV_PROJECT = 'alfit-89567';
const PROD_PROJECT_ID = 'alfit-prod';

const projectId = args['project'] || null;
const EXECUTE = args['execute'] === true;
const MODE = args['cleanup'] ? 'cleanup' : (args['verify'] ? 'verify' : 'seed');
// [CORRECTION-PRE0-LONGTERM-BACKDATED-ATTENDANCE-SEED] 한 시나리오만 손본다.
//   fixture 하나가 어긋났다고 전체를 다시 만들면, 멀쩡한 나머지의 id 가
//   전부 바뀌어 그것을 참조하던 검증 근거가 같이 날아간다.
const ONLY = typeof args['only'] === 'string' ? args['only'] : null;

// ─── HARD BLOCK: PROD ───────────────────────────────────────────────
if (!projectId) {
  console.error('--project <projectId> 가 필요합니다. DEV: --project ' + EXPECTED_DEV_PROJECT);
  process.exit(2);
}
if (projectId !== EXPECTED_DEV_PROJECT) {
  console.error('이 스크립트는 DEV 전용입니다.');
  console.error(`  기대: "${EXPECTED_DEV_PROJECT}"   받음: "${projectId}"`);
  if (projectId === PROD_PROJECT_ID) {
    console.error('  PROD 프로젝트가 지정됐습니다. 실행하지 않습니다.');
  }
  process.exit(2);
}

// ─── DEV 고정 상수 ──────────────────────────────────────────────────
const ROOT = path.resolve(__dirname, '..');
const MANIFEST_PATH = path.join(ROOT, 'scripts', 'r7-fixture-manifest-dev.json');

const DEV = {
  businessId: 'fLmSOHVKUwmBHcbwQE0I',
  adminUid: 'BErRdiWP1xbgyoTovxwAPNEsuD72',
  workerUid: 'tJ8izfP2nNYN79aPTLb6YARiPqC3',
  // 체크인 GPS 게이트 통과용 — 사업장 좌표를 그대로 쓴다(거리 0).
  lat: 37.1432540168018,
  lng: 127.060063542351,
};

const FIXTURE_TAG = 'R7FIX';

// ─── manifest ───────────────────────────────────────────────────────
function loadManifest() {
  if (!fs.existsSync(MANIFEST_PATH)) {
    return {project: EXPECTED_DEV_PROJECT, createdAt: null, scenarios: {}};
  }
  return JSON.parse(fs.readFileSync(MANIFEST_PATH, 'utf8'));
}

function saveManifest(m) {
  if (!EXECUTE) return;
  m.project = EXPECTED_DEV_PROJECT;
  m.updatedAt = new Date().toISOString();
  fs.writeFileSync(MANIFEST_PATH, JSON.stringify(m, null, 2) + '\n', 'utf8');
}

// ─── 로그 ───────────────────────────────────────────────────────────
const log = (...a) => console.log(...a);
const step = (s) => console.log(`\n── ${s}`);
function plan(what) {
  if (!EXECUTE) { console.log(`   [dry-run] ${what}`); return false; }
  console.log(`   ${what}`);
  return true;
}

// ─── 시나리오 정의 ──────────────────────────────────────────────────
//
//   각 항목은 "무엇을 확인하려는가"(expected)를 함께 들고 다닌다.
//   R7 에서 스크린샷·버그 보고가 이 id 를 그대로 참조한다.
const SCENARIOS = [
  {
    id: 'R7_FIX_POST_SHORTAGE',
    domain: 'posting',
    expected: '여러 날짜 중 최소 한 날짜에 remaining > 0. 모집 진행 중으로 보인다.',
    surfaces: ['Posting', 'Home', 'Staffing', 'Worker Jobs'],
  },
  {
    id: 'R7_FIX_POST_MIXED',
    domain: 'posting',
    expected: '한 날짜 FULL, 다른 날짜 부족. 공고 전체를 FULL/종료로 닫지 않는다.',
    surfaces: ['Posting', 'Worker Jobs'],
  },
  {
    id: 'R7_FIX_POST_CLOSED',
    domain: 'posting',
    expected: '수동 전체 종료. 종료 탭에만 보이고 슬롯 preload 대상에서 빠진다.',
    surfaces: ['Posting'],
  },
  {
    id: 'R7_FIX_LT_WORKER',
    domain: 'attendance',
    expected:
      '장기 확정 근무자. 오늘도 근무일이다. 어제 근무 완료(checkOut 있음) + ' +
      '오늘 attendance 문서 없음 → 오늘 카드와 체크인 CTA 가 살아 있어야 한다. ' +
      '급여 pending/calculated/confirmed/transferred 네 상태가 각각 하루씩.',
    surfaces: ['Worker Today', 'Admin Attendance', 'Payroll', 'Worker wage'],
  },
  {
    id: 'R7_FIX_APP_PENDING',
    domain: 'application',
    expected: '지원 = 관심. 확정 아님.',
    surfaces: ['DayApplicants', 'WorkApplicants', 'Worker My Applications'],
  },
  {
    id: 'R7_FIX_CONTRACT_PW',
    domain: 'contract',
    expected: 'pending_worker — 근로자 서명 CTA 가 보인다.',
    surfaces: ['Worker My Applications', 'Contract', 'Admin contract'],
  },
  {
    id: 'R7_FIX_CONTRACT_DONE',
    domain: 'contract',
    expected:
      'completed — 그리고 이때 지원서가 CONFIRMED 가 된다. ' +
      'confirmed-family 커버리지를 이 경로로 대신한다(독립 CONFIRMED 생성 경로 없음).',
    surfaces: ['Contract', 'Posting card', 'WorkApplicants', 'Home'],
  },
];

// ── fixture 로 만들지 않는 것 ────────────────────────────────────────
//
//   canonical writer 가 없거나, seed 가 그 writer 를 대신할 수 없는 것들이다.
//   "라벨을 채우려고" 문서를 만들지 않는다 — 만들면 제품이 만들 수 없는
//   상태가 DEV 에 생기고, R7 에서 그것을 제품 버그로 읽게 된다.
const NOT_SEEDED = [
  ['APP_CONFIRMED (독립)',
    'callableConfirmApplication 은 CONTRACT_PENDING 까지만 간다. ' +
    'CONFIRMED 는 근로자 서명·초대 수락이 만든다 → R7_FIX_CONTRACT_DONE 이 대신한다.'],
  ['REVIEW (작성된 리뷰)',
    'canonical writer 가 CF 가 아니라 rules 로 보호되는 클라이언트 트랜잭션이다 ' +
    '(monthly_review_service.createReviewForUser). Admin SDK 로 쓰면 rules 를 우회한다. ' +
    'review_requests 는 스케줄 CF 가 완료 근무에서 자동 생성하므로 LT fixture 가 그 대상이 된다.'],
  ['SubAdmin membership',
    '실제 계정 초대 + 수락이 필요하고, 계정 생성은 본인인증을 거친다. ' +
    'DEV 계정은 관리자 1 · 근로자 1 뿐이다. seed 로 우회하지 않는다.'],
  ['NOTIFICATION (독립)',
    'domain event 의 부수 효과다. 위 fixture 를 만드는 과정에서 실제로 발생한다 ' +
    '(예: 계약 발송 → contractSignRequested). 독립 문서로 만들지 않는다.'],
  ['CAP-UNKNOWN · USERMAP-PARTIAL',
    'canonical state 를 깨는 synthetic document 다. R7 의 오류/실패 상태 확인 항목으로 남긴다.'],
  ['RELIABILITY (새 노쇼)',
    'canonical writer(callableBatchSetNoShow)는 있고 실제로 동작한다. 그런데 그 부수 효과가 ' +
    'DEV 를 못 쓰게 만든다 — 90일 내 3회가 되면 users.restrictedUntil 이 서고 ' +
    '그 계정은 지원 자체가 막힌다(callableApplyToTO PERMISSION_DENIED). ' +
    'DEV 근로자 계정은 하나뿐이고 이미 노쇼 2건이 있어서, 한 건만 더 만들면 ' +
    '나머지 fixture 를 seed 할 수 없다. 실제로 한 번 그렇게 막혔다. ' +
    '기존 노쇼 2건(2026-09-14 · 2026-09-18)을 reliability 참조로 쓴다 — 새로 만들지 않는다.'],
];

// ─── 진입 ───────────────────────────────────────────────────────────
async function main() {
  log('R7-PRE0 DEV Product Fixture Pack');
  log(`  project : ${projectId}`);
  log(`  mode    : ${MODE}${EXECUTE ? '' : '  (dry-run — --execute 로 실제 반영)'}`);
  log(`  manifest: ${path.relative(ROOT, MANIFEST_PATH)}`);

  const manifest = loadManifest();
  const known = Object.keys(manifest.scenarios || {}).length;
  log(`  기록된 시나리오: ${known}건`);

  const {builders} = require('./r7-fixture-build');
  const {removeScenario} = require('./r7-fixture-cleanup');
  const {db} = require('./r7-fixture-lib');

  // 사업장·근로자 정보는 DEV 문서에서 읽는다. 상수로 박아 두면 실제 값과
  // 어긋나고(businessName 이 비어 있던 것이 그랬다), 공고 카드·계약서
  // 스냅샷이 빈 이름으로 보인다.
  const bizSnap = await db.collection('businesses').doc(DEV.businessId).get();
  if (!bizSnap.exists) throw new Error('DEV 사업장 문서를 찾을 수 없습니다.');
  const workerSnap = await db.collection('users').doc(DEV.workerUid).get();
  if (!workerSnap.exists) throw new Error('DEV 근로자 문서를 찾을 수 없습니다.');
  const biz = bizSnap.data();

  const ctx = {
    db,
    businessId: DEV.businessId,
    businessName: biz.name || '',
    biz,
    worker: workerSnap.data(),
    adminUid: DEV.adminUid,
    workerUid: DEV.workerUid,
    lat: DEV.lat,
    lng: DEV.lng,
    titleOf: {},
    manifest,
  };
  if (!ctx.businessName) throw new Error('사업장 이름이 비어 있습니다.');

  /** manifest 에 적힌 entity 가 실제로 살아 있는가. */
  async function stillAlive(entities) {
    if (!entities) return false;
    if (entities.toId) {
      return (await db.collection('tos').doc(entities.toId).get()).exists;
    }
    // 공고를 새로 만들지 않는 시나리오는 자기 문서로 판정한다.
    // 근태가 먼저다 — 노쇼 시나리오의 applicationId 는 다른 시나리오의
    // 지원서라서 그것만 보면 항상 "살아 있음"이 된다.
    for (const id of entities.attendanceIds || []) {
      return (await db.collection('attendance').doc(id).get()).exists;
    }
    if (entities.applicationId) {
      return (await db.collection('applications')
          .doc(entities.applicationId).get()).exists;
    }
    return false;
  }

  if (MODE === 'seed') {
    step('시나리오');
    for (const s of SCENARIOS) {
      if (ONLY && s.id !== ONLY) continue;
      const builder = builders[s.id];
      if (!builder) { log(`   건너뜀  ${s.id}  (빌더 없음)`); continue; }

      const recorded = manifest.scenarios[s.id];
      if (recorded && await stillAlive(recorded.entities)) {
        log(`   있음    ${s.id}  (다시 만들지 않는다)`);
        continue;
      }
      if (!plan(`만든다  ${s.id}`)) continue;

      const r = await builder(ctx);
      manifest.scenarios[s.id] = {
        domain: s.domain,
        surfaces: s.surfaces,
        entities: r.entities,
        expected: r.expected,
        seededAt: new Date().toISOString(),
      };
      saveManifest(manifest);           // 중간 실패에도 기록은 남긴다
      log(`           → ${JSON.stringify(r.entities).slice(0, 110)}`);
    }
    step('fixture 로 만들지 않는 것 (canonical writer 없음 / seed 가 대신할 수 없음)');
    for (const [what, why] of NOT_SEEDED) log(`   ·  ${what}\n        ${why}`);
  } else if (MODE === 'verify') {
    step('canonical sanity check');
    const {verifyAll} = require('./r7-fixture-verify');
    const ok = await verifyAll(manifest, log);
    if (!ok) { log('\n검증 실패.'); process.exit(1); }
  } else if (MODE === 'cleanup') {
    step('정리 (manifest 기록분만)');
    // 남의 공고를 빌려 쓴 시나리오부터 지운다. 공고 소유 시나리오를 먼저
    // 지우면 그 공고에 달린 남의 지원서까지 함께 사라져 집계가 틀어진다.
    const order = Object.entries(manifest.scenarios || {})
        .filter(([id]) => !ONLY || id === ONLY)
        .sort((a, b) => ((b[1].entities || {}).sharedToId ? 1 : 0) -
                        ((a[1].entities || {}).sharedToId ? 1 : 0));
    if (ONLY) log(`   --only ${ONLY} — 나머지 기록은 건드리지 않는다.`);
    const touchedMonths = new Set();
    for (const [id, rec] of order) {
      const n = await removeScenario(rec.entities, {
        execute: EXECUTE, months: touchedMonths,
        adminUid: DEV.adminUid, businessId: DEV.businessId,
      });
      log(`   ${EXECUTE ? '삭제' : '[dry-run]'} ${id.padEnd(28)} ` +
          `근태 ${n.attendance} · 지원서 ${n.applications} · 슬롯 ${n.slots} · ` +
          `공고 ${n.tos} · 계약 ${n.contracts}`);
      if (n.foreign > 0) {
        log(`            fixture 소유가 아닌 지원서 ${n.foreign}건 — 남겼다. ` +
            '그래서 공고도 남긴다(고아 방지).');
      }
      if (EXECUTE) delete manifest.scenarios[id];
    }
    log('   쿼리로 훑어 지우지 않는다 — manifest 에 없는 것은 건드리지 않는다.');

    // 삭제는 증분 집계를 되돌리지 않는다 — canonical 복구 CF 로 맞춘다.
    if (touchedMonths.size > 0) {
      step('급여 집계 복구 (확정 근태를 지웠으므로)');
      const {callAs} = require('./r7-fixture-lib');
      for (const ym of [...touchedMonths].sort()) {
        if (!EXECUTE) { log(`   [dry-run] repairPayrollSummaries ${ym}`); continue; }
        const r = await callAs(DEV.adminUid, 'callableRepairPayrollSummaries',
            {businessId: DEV.businessId, yearMonth: ym});
        log(`   ${ym}  → ${r.workerCount}명 / ${r.confirmedCount}건 / ` +
            `${(r.totalPayout || 0).toLocaleString()}원`);
      }
    }
  }

  saveManifest(manifest);
  log('\n완료.');
}

main().catch((e) => {
  console.error('\n실패:', e && e.message ? e.message : e);
  process.exit(1);
});
