/**
 * [R7-P4.4E §2/§18/§19] DEV Functions 메타데이터 inventory — READ ONLY.
 *
 * 주의: `firebase functions:list --json` 출력에는 각 함수의 **환경변수 시크릿이
 * 평문으로** 들어온다. 이 스크립트는 메타 필드만 뽑고 원본 파일을 즉시
 * 삭제한다. 어떤 값도 stdout 에 남기지 않는다.
 *
 * 사용: node scripts/r7-p44e-fn-inventory.js <out.json> [--diff <before.json>]
 */
'use strict';

const {execFileSync} = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const outPath = process.argv[2];
if (!outPath) {
  console.error('사용: node scripts/r7-p44e-fn-inventory.js <out.json> [--diff <before.json>]');
  process.exit(1);
}
const diffIdx = process.argv.indexOf('--diff');
const beforePath = diffIdx > 0 ? process.argv[diffIdx + 1] : null;

const raw = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'fnlist-')),
  'raw.json'
);

let parsed;
try {
  const stdout = execFileSync(
    'npx firebase functions:list --json --project alfit-89567',
    {maxBuffer: 256 * 1024 * 1024, encoding: 'utf8', shell: true}
  );
  fs.writeFileSync(raw, stdout, 'utf8');
  parsed = JSON.parse(stdout);
} catch (e) {
  console.error('functions:list 실패:', e.message ? e.message.slice(0, 200) : '(없음)');
  try { fs.rmSync(path.dirname(raw), {recursive: true, force: true}); } catch (_) {}
  process.exit(1);
} finally {
  // 원본(시크릿 포함)을 바로 지운다.
  try { fs.rmSync(path.dirname(raw), {recursive: true, force: true}); } catch (_) {}
}

const list = Array.isArray(parsed && parsed.result) ? parsed.result :
  (Array.isArray(parsed) ? parsed : []);

// 메타만 — env/secretEnvironmentVariables/serviceConfig 전체는 절대 담지 않는다.
const meta = list.map((f) => ({
  id: f.id || f.name || '(이름없음)',
  platform: f.platform || null,
  region: f.region || (Array.isArray(f.regions) ? f.regions[0] : null) || null,
  runtime: f.runtime || null,
  state: (f.serviceConfig && f.serviceConfig.state) || f.state || null,
  updateTime: f.updateTime || null,
  buildId: (f.buildConfig && f.buildConfig.build) || null,
  sourceGen: (f.buildConfig && f.buildConfig.source &&
    f.buildConfig.source.storageSource &&
    f.buildConfig.source.storageSource.generation) || null,
  entryPoint: (f.buildConfig && f.buildConfig.entryPoint) || f.entryPoint || null,
})).sort((a, b) => a.id.localeCompare(b.id));

fs.writeFileSync(outPath, JSON.stringify(meta, null, 2), 'utf8');
console.log('함수 총', meta.length, '개 → 메타만 저장:', outPath);

const nonActive = meta.filter((m) => m.state && m.state !== 'ACTIVE');
console.log('ACTIVE 아닌 함수:', nonActive.length,
  nonActive.length ? nonActive.map((m) => `${m.id}(${m.state})`).join(', ') : '');

if (beforePath && fs.existsSync(beforePath)) {
  const before = JSON.parse(fs.readFileSync(beforePath, 'utf8'));
  const byId = new Map(before.map((m) => [m.id, m]));

  // 가변 identity 축이 아예 없으면 "변경 없음" 이라고 말할 수 없다.
  //   firebase CLI(functions:list)는 updateTime/buildId/sourceGen 를 주지 않고
  //   이 환경에는 gcloud 가 없다. null == null 을 "그대로" 로 읽으면 근거
  //   없는 PASS 가 된다 — 그래서 축이 비면 UNKNOWN 으로 보고한다.
  const mutableAxis = meta.some(
    (m) => m.updateTime != null || m.buildId != null || m.sourceGen != null
  );
  if (!mutableAxis) {
    const beforeIds = before.map((m) => m.id).sort().join('|');
    const afterIds = meta.map((m) => m.id).sort().join('|');
    console.log('\n=== 배포 전/후 대조 ===');
    console.log('가변 identity 축(updateTime/buildId/sourceGen): **CLI 미제공**');
    console.log('  → 개별 함수가 바뀌었는지는 이 경로로 판정 불가 (NOT SEEN)');
    console.log('확인 가능한 것만:');
    console.log('  함수 총수     ', before.length, '→', meta.length,
      before.length === meta.length ? '(동일)' : '(변동)');
    console.log('  함수 집합     ', beforeIds === afterIds ? '동일' : '변동');
    console.log('  ACTIVE 아님   ', meta.filter((m) => m.state !== 'ACTIVE').length, '개');
    const rtDrift = meta.filter((m) => {
      const b = byId.get(m.id);
      return b && (b.runtime !== m.runtime || b.platform !== m.platform);
    });
    console.log('  runtime/platform 변동', rtDrift.length, '개',
      rtDrift.map((m) => m.id).join(', '));
    process.exit(0);
  }
  const changed = [];
  const unchanged = [];
  const added = [];
  for (const m of meta) {
    const b = byId.get(m.id);
    if (!b) { added.push(m.id); continue; }
    const same = b.updateTime === m.updateTime &&
      b.sourceGen === m.sourceGen && b.buildId === m.buildId;
    (same ? unchanged : changed).push(m.id);
  }
  const removed = before.map((m) => m.id).filter((id) => !meta.some((m) => m.id === id));
  console.log('\n=== 배포 전/후 대조 ===');
  console.log('변경된 함수', changed.length, '개:', changed.join(', ') || '(없음)');
  console.log('그대로인 함수', unchanged.length, '개');
  console.log('새로 생긴 함수', added.length, '개:', added.join(', ') || '(없음)');
  console.log('사라진 함수', removed.length, '개:', removed.join(', ') || '(없음)');
}
