// [GATE B] 번들 로드가 안전한가 — **비파괴적** boot smoke.
//
//   실행:  cd functions && npm run build && node test/boot_smoke.test.js
//
// ── 왜 필요한가 ───────────────────────────────────────────────────────
//   `callableApplyToTO`·`callableInviteWorker` 두 함수만 선택 배포해도
//   **번들 전체**가 그 함수의 런타임에 올라간다. 지금 로컬 번들에는 아직
//   배포되지 않은 다른 Phase 코드가 약 2,027줄 들어 있다(배포본 45,459줄
//   vs 로컬 47,486줄). 소스 diff 상 모듈 top-level 변경은 0건이지만,
//   **그것만으로 로드 부작용이 없다고 단정하지 않는다**(§B-1).
//
// ── 어떻게 비파괴적으로 보는가 ────────────────────────────────────────
//   로드 전에 `https`/`http` 요청과 `net.Socket.connect` 를 가로채
//   **실제로 나가는 모든 트래픽을 기록하고 차단**한다. 모듈을 그대로
//   `require` 하므로 코드 경로는 production 그대로이고, 바깥으로 나가는
//   writer 나 알림이 있으면 그 자리에서 잡힌다.
//
//   `GOOGLE_APPLICATION_CREDENTIALS` 는 설정하지 않는다 — 자격 없이도
//   `admin.initializeApp()` 은 통과하고(lazy), 실제 호출만 실패한다.
//
// ── mock 범위 (정직하게) ──────────────────────────────────────────────
//   가로챈 것: outbound 네트워크(https.request/get, http.request/get,
//   net.Socket.prototype.connect). 그 외 코드는 전부 실제다.
//   이 테스트는 **모듈 로드 시점**만 본다 — 함수 본문 실행은 보지 않는다.
'use strict';
const assert = require('assert');
const https = require('https');
const http = require('http');
const net = require('net');
const path = require('path');

const outbound = [];
function trap(mod, name) {
  const orig = mod[name];
  mod[name] = function (...args) {
    const a = args[0];
    const where = typeof a === 'string' ? a :
      (a && (a.hostname || a.host)) ? (a.hostname || a.host) + (a.path || '') : '(unknown)';
    outbound.push(name + ' ' + where);
    throw new Error('[boot_smoke] outbound blocked: ' + name + ' ' + where);
  };
  return () => { mod[name] = orig; };
}
const restores = [
  trap(https, 'request'), trap(https, 'get'),
  trap(http, 'request'), trap(http, 'get'),
];
const origConnect = net.Socket.prototype.connect;
net.Socket.prototype.connect = function (...args) {
  const a = args[0];
  const where = typeof a === 'object' ? ((a.host || '?') + ':' + (a.port || '?')) : String(a);
  outbound.push('socket ' + where);
  throw new Error('[boot_smoke] socket blocked: ' + where);
};

// [GATE B 2026-10-15] 선택 배포 대상. callableApplyToTO·callableInviteWorker 는
//   10-14 GATE 1 대상, callableAcceptTOInvitation 은 이번 E2 가드 배포 대상이다.
// [E2 11-callable 2026-10-15] 초대 사전 동의·검토·수락 동등성 배포 대상 11개를 더한다.
const DEPLOY_TARGETS = ['callableApplyToTO', 'callableInviteWorker', 'callableAcceptTOInvitation',
  'callableGetMyApplications', 'callableGiveApplicationDocumentConsent',
  'callableGetApplicantDocumentReview', 'callableGetApplicantDocumentUrl',
  'callableReviewApplicantDocument', 'callableRequestDocumentCorrection',
  'callableGetTaxIdentityIdCardUrl', 'callableAcceptConfirmedReassignment',
  'callableConfirmApplication',
  // [INVITE-CLOSURE 2026-10-16] 초대 투영·마감 writer·정원 단위 변경이 닿는 callable.
  //   (트리거 syncTOStats 는 callable 이 아니라 BOOT-4 형식이 달라 여기 넣지 않는다.)
  'callableGetDayStaffingDetail', 'callableUpdateTO', 'callableRecalculateTOStats',
  'callableBatchCancelNoShow',
  // [INVITE-TERMINAL 2026-10-16] 예약 공개 재확인·재오픈 FULL 규칙.
  'callablePublishTO', 'callableReopenSlots'];

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

console.log('[BOOT] 컴파일된 번들 로드');

let mod = null;
let loadErr = null;
const t0 = Date.now();
try {
  mod = require(path.join(__dirname, '..', 'lib', 'index.js'));
} catch (e) {
  loadErr = e;
}
const loadMs = Date.now() - t0;

// 로드가 끝났으면 네트워크 가로채기를 되돌린다.
for (const r of restores) r();
net.Socket.prototype.connect = origConnect;

t('BOOT-1 모듈 로드가 예외 없이 끝난다', () => {
  assert.strictEqual(loadErr, null,
      loadErr ? ('로드 실패: ' + loadErr.message) : '');
  assert.ok(mod, 'exports 가 비어 있다');
});

t('BOOT-2 모듈 로드만으로 바깥 트래픽이 나가지 않는다', () => {
  assert.deepStrictEqual(outbound, [],
      '로드 중 outbound 시도: ' + JSON.stringify(outbound.slice(0, 5)));
});

t('BOOT-3 배포 대상 함수가 export 된다', () => {
  for (const name of DEPLOY_TARGETS) assert.ok(mod[name], name + ' 가 없다');
});

t('BOOT-4 두 함수의 리전·옵션 계약이 유지된다', () => {
  for (const name of DEPLOY_TARGETS) {
    const f = mod[name];
    const opts = f.__endpoint || {};
    assert.ok(opts.region && opts.region.includes('asia-northeast3'),
        name + ' 리전=' + JSON.stringify(opts.region));
    assert.ok(opts.platform === 'gcfv2', name + ' platform=' + opts.platform);
    assert.ok(opts.callableTrigger !== undefined,
        name + ' 이 callable 이 아니다');
  }
});

t('BOOT-5 두 함수에 secret 의존이 생기지 않았다', () => {
  // 현재 배포본은 secrets 없음 — 새로 생기면 배포 설정이 달라진다.
  for (const name of DEPLOY_TARGETS) {
    const sec = (mod[name].__endpoint || {}).secretEnvironmentVariables || [];
    assert.strictEqual(sec.length, 0,
        name + ' secrets=' + JSON.stringify(sec.map((s) => s.key)));
  }
});

t('BOOT-6 App Check 강제·운영 옵션 선언이 의도값이다', () => {
  // `enforceAppCheck` 는 `__endpoint` 에 실리지 않는다(실측: callableTrigger={}).
  //   그래서 **선언부**로 확인한다 — 배포 설정이 아니라 코드 계약이다.
  // [M2 · 판정190] 선택배포 기존 12개는 DEV 기존값 `maxInstances: 20` 을 명시한다.
  //   선언이 없으면 SDK 가 maxInstances 에 RESET 을 실어 DEV 의 20 보존이 보장되지 않는다(판정188 M2).
  //   선언 줄은 함수마다 정확히 이 한 줄이어야 하고(줄 끝까지), 20 은 __endpoint 에도 실려야 한다.
  const MAX20 = new Set([
    'callableGetApplicantDocumentReview',
    'callableGetApplicantDocumentUrl',
    'callableReviewApplicantDocument',
    'callableRequestDocumentCorrection',
    'callableGiveApplicationDocumentConsent',
    'callableGetBankbookSignedUrl',
    'callableGetUsersBatch',
    'callableGetTaxIdentityIdCardUrl',
    'callableApplyToTO',
    'callableGetMyApplications',
    'callableAcceptTOInvitation',
    'callableAcceptConfirmedReassignment',
  ]);
  // 기존 BOOT 대상 18개와 MAX20 12개의 합집합은 20개다(겹침10·추가2).
  // 기존18 중 나머지8은 원래 region/AppCheck 옵션 줄을 유지한다.
  const OPTION_TARGETS = [...new Set([...DEPLOY_TARGETS, ...MAX20])];
  const src = require('fs').readFileSync(
      path.join(__dirname, '..', 'src', 'index.ts'), 'utf8');
  for (const name of OPTION_TARGETS) {
    const opt = MAX20.has(name) ?
        '  {region: "asia-northeast3", enforceAppCheck: true, maxInstances: 20},' :
        '  {region: "asia-northeast3", enforceAppCheck: true},';
    const decl = `export const ${name} = onCall(\n` + opt + '\n';
    assert.ok(src.includes(decl),
        name + ' 의 region/enforceAppCheck/maxInstances 선언이 의도값과 다르다');
    if (MAX20.has(name)) {
      const ep = (mod && mod[name] && mod[name].__endpoint) || {};
      assert.strictEqual(ep.maxInstances, 20,
          name + ' __endpoint.maxInstances=' + JSON.stringify(ep.maxInstances));
    }
  }
});

t('BOOT-7 다른 함수 등록 때문에 discovery 가 깨지지 않는다', () => {
  const exported = Object.keys(mod).filter((k) => mod[k] && mod[k].__endpoint);
  assert.ok(exported.length > 100,
      '등록된 함수 수가 비정상: ' + exported.length);
  for (const name of DEPLOY_TARGETS) assert.ok(exported.includes(name), name);
  console.log('       (등록된 함수 ' + exported.length + '개, 로드 ' + loadMs + 'ms)');
});

t('BOOT-8 로드 시간이 discovery 타임아웃 안에 들어온다', () => {
  // 배포는 FUNCTIONS_DISCOVERY_TIMEOUT=300(초)으로 돌린다.
  assert.ok(loadMs < 60000, '로드 ' + loadMs + 'ms');
});

console.log('');
console.log(`통과 ${pass} / 실패 ${fails.length}`);
if (fails.length) {
  for (const f of fails) console.log('  - ' + f);
  process.exit(1);
}
