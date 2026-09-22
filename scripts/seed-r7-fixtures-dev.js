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
    id: 'R7_FIX_LT_POSTING',
    domain: 'posting',
    expected: '장기(contract) 공고. LT 근무자 fixture 의 출처.',
    surfaces: ['Posting'],
  },
  {
    id: 'R7_FIX_APP_PENDING',
    domain: 'application',
    expected: '지원 = 관심. 확정 아님.',
    surfaces: ['DayApplicants', 'WorkApplicants', 'Worker My Applications'],
  },
  {
    id: 'R7_FIX_APP_CONFIRMED',
    domain: 'application',
    expected: '확정 = 약속. 모든 표면에서 같은 확정 수.',
    surfaces: ['Posting card', 'DayApplicants', 'WorkApplicants', 'Home'],
  },
  {
    id: 'R7_FIX_CONTRACT_PW',
    domain: 'contract',
    expected: 'pending_worker — 근로자 서명 CTA 가 보인다.',
    surfaces: ['Worker My Applications', 'Contract', 'Admin contract'],
  },
  {
    id: 'R7_FIX_LT_WORKER',
    domain: 'attendance',
    expected: '장기 확정 근무자. 오늘도 근무일이다.',
    surfaces: ['Worker Today', 'Admin Attendance'],
  },
  {
    id: 'R7_FIX_ATT_YESTERDAY_COMPLETE',
    domain: 'attendance',
    expected:
      '어제 근무 완료(checkOut 있음) + 오늘 attendance 문서 없음. ' +
      '오늘 근무 카드와 체크인 CTA 가 살아 있어야 한다. ' +
      '어제 기록을 오늘 기록으로 쓰지 않는다.',
    surfaces: ['Worker Today'],
  },
  {
    id: 'R7_FIX_PAY_PENDING',
    domain: 'payroll',
    expected: '근무는 있고 급여 미확정. 0원 지급완료처럼 보이면 안 된다.',
    surfaces: ['Payroll', 'Worker wage'],
  },
  {
    id: 'R7_FIX_PAY_CONFIRMED',
    domain: 'payroll',
    expected: '확정 금액 존재, 미이체.',
    surfaces: ['Payroll'],
  },
  {
    id: 'R7_FIX_PAY_TRANSFERRED',
    domain: 'payroll',
    expected: '이체 완료.',
    surfaces: ['Payroll'],
  },
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
  const ctx = {
    db,
    businessId: DEV.businessId,
    businessName: DEV.businessName,
    adminUid: DEV.adminUid,
    workerUid: DEV.workerUid,
    lat: DEV.lat,
    lng: DEV.lng,
    titleOf: {},
  };

  /** manifest 에 적힌 entity 가 실제로 살아 있는가. */
  async function stillAlive(entities) {
    if (!entities || !entities.toId) return false;
    return (await db.collection('tos').doc(entities.toId).get()).exists;
  }

  if (MODE === 'seed') {
    step('시나리오');
    for (const s of SCENARIOS) {
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
  } else if (MODE === 'verify') {
    step('canonical sanity check');
    const {verifyAll} = require('./r7-fixture-verify');
    const ok = await verifyAll(manifest, log);
    if (!ok) { log('\n검증 실패.'); process.exit(1); }
  } else if (MODE === 'cleanup') {
    step('정리 (manifest 기록분만)');
    for (const [id, rec] of Object.entries(manifest.scenarios || {})) {
      const n = await removeScenario(rec.entities, {execute: EXECUTE});
      log(`   ${EXECUTE ? '삭제' : '[dry-run]'} ${id.padEnd(28)} ` +
          `근태 ${n.attendance} · 지원서 ${n.applications} · 슬롯 ${n.slots} · 공고 ${n.tos}`);
      if (EXECUTE) delete manifest.scenarios[id];
    }
    log('   쿼리로 훑어 지우지 않는다 — manifest 에 없는 것은 건드리지 않는다.');
  }

  saveManifest(manifest);
  log('\n완료.');
}

main().catch((e) => {
  console.error('\n실패:', e && e.message ? e.message : e);
  process.exit(1);
});
