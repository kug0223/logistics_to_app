#!/usr/bin/env node
/**
 * Firestore 구성 drift 체커 — READ ONLY.
 *
 *   `firebase deploy --only firestore:indexes` (특히 `--force`) 는 repo 에
 *   선언되지 않은 remote 구성을 **삭제한다**. firebase-tools 14.20.0
 *   `lib/firestore/api.js` 의 `deleteField(field)` 는 field 문서 전체를
 *   빈 body 로 PATCH 하므로, 그 field 에 붙어 있던 `ttlConfig` 까지 함께
 *   사라진다. ("spec 에 ttl:false 가 아니면 TTL 을 지우지 않는다" 는
 *   안전장치는 **같은 field 의 spec 이 존재할 때만** 적용된다.)
 *
 *   실제로 그 일이 일어났다: `passTokens.expiresAt` 의 TTL 정책이
 *   index 배포 한 번으로 사라졌다. 그 TTL 은 만료된 PASS 토큰(이름·생년·
 *   전화번호·ciHash 를 들고 있다)을 지우는 **유일한 주인**이다 —
 *   `cleanExpiredPassTokens` 스케줄러는 TTL 로 대체되며 삭제됐다.
 *
 *   그래서 배포 전에 이 체커를 돌린다. repo 가 remote 의 superset 이
 *   아니면 배포는 파괴적이다.
 *
 * 사용법:
 *   node scripts/check-firestore-config-drift.js --project <dev-project-id>
 *   node scripts/check-firestore-config-drift.js --self-test
 *
 * 인증: `--key <service-account.json>` 또는 `GOOGLE_APPLICATION_CREDENTIALS`,
 *       없으면 ADC. 키 내용은 출력하지 않는다.
 *
 * 종료 코드:
 *   0  safe — repo 가 remote 를 모두 설명한다
 *   1  remote-only composite index 또는 remote-only fieldOverride 존재
 *   2  사용법/인증/대상 프로젝트 오류
 *   3  remote TTL 이 repo 에 표현되지 않음
 *   4  금지된 TTL 발견 (account_deletion_tombstones)
 */
'use strict';

const fs = require('fs');
const path = require('path');

/** 이 체커로 PROD 를 다루지 않는다 — 파괴적 배포 판단에 쓰이는 도구다. */
const FORBIDDEN_PROJECTS = ['alfit-prod'];

/**
 * TTL 을 절대 붙이면 안 되는 자리.
 *
 *   tombstone 이 사라지면 Auth-tail 재개의 증거가 사라진다
 *   (R7-P4.4E.11C.0C.1). 자동 삭제는 금지다.
 */
const FORBIDDEN_TTL = [
  {collectionGroup: 'account_deletion_tombstones', fieldPath: 'barrierAt'},
];

// ───────────────────────────────────────────────────────────── 정규화 / diff

/** composite index 서명. `__name__` 은 Firestore 가 항상 붙이므로 제외한다. */
function compositeSignature(collectionGroup, fields, queryScope) {
  const body = (fields || [])
    .filter((f) => f.fieldPath !== '__name__')
    .map((f) => `${f.fieldPath}:${f.order || f.arrayConfig || f.vectorConfig || '?'}`)
    .join(',');
  return `${collectionGroup} [${body}] ${queryScope || 'COLLECTION'}`;
}

/** fieldOverride 키 = 컬렉션그룹 + 필드경로. */
const overrideKey = (cg, fieldPath) => `${cg}.${fieldPath}`;

/** fieldOverride 모양 = 정렬된 (scope:mode) 목록 + ttl 여부. */
function overrideShape(indexes, ttl) {
  const modes = (indexes || [])
    .map((ix) => {
      const first = Array.isArray(ix.fields) ? ix.fields[0] : undefined;
      const mode = ix.order || ix.arrayConfig ||
        (first && (first.order || first.arrayConfig)) || '?';
      return `${ix.queryScope || 'COLLECTION'}:${mode}`;
    })
    .sort();
  return `{${modes.join(',')}} ttl=${ttl ? 'yes' : 'no'}`;
}

/**
 * repo 선언과 remote 상태를 네 범주로 가른다.
 *
 * @param {object} repo {composites:Map, overrides:Map}
 * @param {object} remote {composites:Map, overrides:Map}
 * @return {object} 범주별 목록
 */
function diffConfig(repo, remote) {
  const out = {
    composite: {repoOnly: [], remoteOnly: [], same: [], shapeMismatch: []},
    override: {repoOnly: [], remoteOnly: [], same: [], shapeMismatch: []},
  };

  for (const sig of repo.composites.keys()) {
    if (remote.composites.has(sig)) out.composite.same.push(sig);
    else out.composite.repoOnly.push(sig);
  }
  for (const sig of remote.composites.keys()) {
    if (!repo.composites.has(sig)) out.composite.remoteOnly.push(sig);
  }

  for (const [key, shape] of repo.overrides) {
    if (!remote.overrides.has(key)) {
      out.override.repoOnly.push(`${key} ${shape}`);
    } else if (remote.overrides.get(key) !== shape) {
      out.override.shapeMismatch.push(
        `${key} repo=${shape} remote=${remote.overrides.get(key)}`);
    } else {
      out.override.same.push(`${key} ${shape}`);
    }
  }
  for (const [key, shape] of remote.overrides) {
    if (!repo.overrides.has(key)) out.override.remoteOnly.push(`${key} ${shape}`);
  }
  return out;
}

/**
 * TTL 축을 따로 본다.
 *
 * @param {Map} repoOverrides repo 선언
 * @param {Array} remoteTtlFields remote 에서 ttlConfig 를 가진 field 목록
 * @return {object} {unrepresented, forbidden, represented}
 */
function diffTtl(repoOverrides, remoteTtlFields) {
  const out = {unrepresented: [], forbidden: [], represented: []};
  for (const f of remoteTtlFields) {
    const key = overrideKey(f.collectionGroup, f.fieldPath);
    const declared = repoOverrides.get(key);
    if (declared && /ttl=yes/.test(declared)) out.represented.push(key);
    else out.unrepresented.push(key);
  }
  for (const f of FORBIDDEN_TTL) {
    const key = overrideKey(f.collectionGroup, f.fieldPath);
    if (remoteTtlFields.some((r) =>
      overrideKey(r.collectionGroup, r.fieldPath) === key)) {
      out.forbidden.push(key);
    }
    if (/ttl=yes/.test(repoOverrides.get(key) || '')) out.forbidden.push(`repo:${key}`);
  }
  return out;
}

// ───────────────────────────────────────────────────────────── repo 읽기

/**
 * `firestore.indexes.json` 을 읽어 비교 가능한 모양으로 만든다.
 *
 * @param {string} file 경로
 * @return {object} {composites, overrides}
 */
function parseRepoConfig(file) {
  const raw = JSON.parse(fs.readFileSync(file, 'utf8'));
  const composites = new Map();
  for (const ix of raw.indexes || []) {
    composites.set(
      compositeSignature(ix.collectionGroup, ix.fields, ix.queryScope), true);
  }
  const overrides = new Map();
  for (const fo of raw.fieldOverrides || []) {
    overrides.set(
      overrideKey(fo.collectionGroup, fo.fieldPath),
      overrideShape(fo.indexes, fo.ttl === true));
  }
  return {composites, overrides};
}

// ───────────────────────────────────────────────────────────── remote 읽기

/**
 * remote 구성을 읽는다. 메타만 다룬다 — 문서 내용도 시크릿도 읽지 않는다.
 *
 * @param {string} project 프로젝트 id
 * @param {string|undefined} keyFile 서비스 계정 키 경로
 * @return {Promise<object>} {composites, overrides, ttlFields, rawCounts}
 */
async function fetchRemoteConfig(project, keyFile) {
  const {GoogleAuth} = require(resolveGoogleAuth());
  const auth = new GoogleAuth({
    keyFile: keyFile || undefined,
    scopes: ['https://www.googleapis.com/auth/cloud-platform'],
  });
  const client = await auth.getClient();
  const base =
    `https://firestore.googleapis.com/v1/projects/${project}` +
    '/databases/(default)';

  // composite index 전수 (페이지네이션)
  const rawIndexes = [];
  let token;
  do {
    const url = `${base}/collectionGroups/-/indexes` +
      (token ? `?pageToken=${encodeURIComponent(token)}` : '');
    const res = await client.request({url});
    rawIndexes.push(...((res.data && res.data.indexes) || []));
    token = res.data && res.data.nextPageToken;
  } while (token);

  const composites = new Map();
  for (const ix of rawIndexes) {
    const cg = String(ix.name).split('/collectionGroups/')[1].split('/')[0];
    composites.set(compositeSignature(cg, ix.fields, ix.queryScope), ix.state || '?');
  }

  // fieldOverride 전수.
  //   filter 는 firebase-tools 가 쓰는 것과 **같아야** 한다. TTL 만 걸린
  //   field 는 `usesAncestorConfig=false` 만으로는 보이지 않는다.
  const filter = encodeURIComponent(
    'indexConfig.usesAncestorConfig=false OR ttlConfig:*');
  const fRes = await client.request({
    url: `${base}/collectionGroups/-/fields?filter=${filter}`,
  });
  const overrides = new Map();
  const ttlFields = [];
  for (const f of (fRes.data && fRes.data.fields) || []) {
    const tail = String(f.name).split('/collectionGroups/')[1] || '';
    const cg = tail.split('/')[0];
    const fieldPath = tail.split('/fields/')[1];
    if (!cg || !fieldPath) continue;
    // `__default__/fields/*` 는 데이터베이스 기본 구성이다 — 선언 대상이 아니다.
    if (cg === '__default__') continue;
    const hasTtl = !!f.ttlConfig;
    overrides.set(
      overrideKey(cg, fieldPath),
      overrideShape((f.indexConfig || {}).indexes, hasTtl));
    if (hasTtl) {
      ttlFields.push({
        collectionGroup: cg, fieldPath,
        state: (f.ttlConfig && f.ttlConfig.state) || '?',
      });
    }
  }
  return {
    composites, overrides, ttlFields,
    rawCounts: {indexes: rawIndexes.length, fields: overrides.size},
  };
}

/** google-auth-library 위치 — 루트 또는 functions/ 중 있는 쪽. */
function resolveGoogleAuth() {
  const candidates = [
    path.join(__dirname, '..', 'node_modules', 'google-auth-library'),
    path.join(__dirname, '..', 'functions', 'node_modules', 'google-auth-library'),
  ];
  for (const c of candidates) if (fs.existsSync(c)) return c;
  return 'google-auth-library';
}

// ───────────────────────────────────────────────────────────── 보고 / 판정

/**
 * diff 결과로 종료 코드를 정한다.
 *
 * @param {object} d diffConfig 결과
 * @param {object} t diffTtl 결과
 * @return {object} {code, reasons}
 */
function verdict(d, t) {
  const reasons = [];
  if (t.forbidden.length > 0) {
    reasons.push(`금지된 TTL: ${t.forbidden.join(', ')}`);
    return {code: 4, reasons};
  }
  if (d.composite.remoteOnly.length > 0 || d.override.remoteOnly.length > 0) {
    if (d.composite.remoteOnly.length > 0) {
      reasons.push(`remote-only composite ${d.composite.remoteOnly.length}건`);
    }
    if (d.override.remoteOnly.length > 0) {
      reasons.push(`remote-only fieldOverride ${d.override.remoteOnly.length}건`);
    }
    return {code: 1, reasons};
  }
  if (t.unrepresented.length > 0) {
    reasons.push(`repo 에 표현되지 않은 remote TTL: ${t.unrepresented.join(', ')}`);
    return {code: 3, reasons};
  }
  return {code: 0, reasons: ['repo 가 remote 구성을 모두 설명한다']};
}

function printReport(d, t, remote, v) {
  const line = (label, arr) => {
    console.log(`  ${label.padEnd(18)}${arr.length}`);
    arr.forEach((x) => console.log(`      ${x}`));
  };
  console.log('=== composite indexes ===');
  console.log(`  remote 총계        ${remote.rawCounts.indexes}`);
  console.log(`  same              ${d.composite.same.length}`);
  line('repo-only', d.composite.repoOnly);
  line('remote-only', d.composite.remoteOnly);
  console.log('=== field overrides ===');
  console.log(`  same              ${d.override.same.length}`);
  line('repo-only', d.override.repoOnly);
  line('remote-only', d.override.remoteOnly);
  line('shape-mismatch', d.override.shapeMismatch);
  console.log('=== TTL ===');
  remote.ttlFields.forEach((f) =>
    console.log(`  remote ttl: ${f.collectionGroup}.${f.fieldPath} state=${f.state}`));
  line('repo 표현됨', t.represented);
  line('repo 미표현', t.unrepresented);
  line('금지 TTL', t.forbidden);
  console.log(`=== VERDICT: exit ${v.code} — ${v.reasons.join(' / ')} ===`);
}

// ───────────────────────────────────────────────────────────── self-test

/** 네트워크 없이 diff/판정 논리만 검증한다 (§41 D1~D5). */
function selfTest() {
  const mk = (composites, overrides) => ({
    composites: new Map(composites.map((c) => [c, true])),
    overrides: new Map(overrides),
  });
  const cases = [];

  // D1 repo == remote → PASS
  {
    const repo = mk(['a [x:ASCENDING] COLLECTION'], [['m.uid', '{COLLECTION_GROUP:ASCENDING} ttl=no']]);
    const remote = mk(['a [x:ASCENDING] COLLECTION'], [['m.uid', '{COLLECTION_GROUP:ASCENDING} ttl=no']]);
    const v = verdict(diffConfig(repo, remote), diffTtl(repo.overrides, []));
    cases.push(['D1 repo==remote → 0', v.code === 0, v.code]);
  }
  // D2 remote-only composite → STOP
  {
    const repo = mk([], []);
    const remote = mk(['ghost [y:ASCENDING] COLLECTION'], []);
    const v = verdict(diffConfig(repo, remote), diffTtl(repo.overrides, []));
    cases.push(['D2 remote-only composite → 1', v.code === 1, v.code]);
  }
  // D3 remote-only fieldOverride → STOP
  {
    const repo = mk([], []);
    const remote = mk([], [['ghost.field', '{COLLECTION:ASCENDING} ttl=no']]);
    const v = verdict(diffConfig(repo, remote), diffTtl(repo.overrides, []));
    cases.push(['D3 remote-only override → 1', v.code === 1, v.code]);
  }
  // D4 remote TTL 이 repo 에 없다 → FAIL
  {
    const repo = mk([], [['passTokens.expiresAt', '{COLLECTION:ASCENDING} ttl=no']]);
    const remote = mk([], [['passTokens.expiresAt', '{COLLECTION:ASCENDING} ttl=yes']]);
    const t = diffTtl(repo.overrides,
      [{collectionGroup: 'passTokens', fieldPath: 'expiresAt', state: 'ACTIVE'}]);
    const v = verdict(diffConfig(repo, remote), t);
    cases.push(['D4 remote TTL 미표현 → 3', v.code === 3, v.code]);
  }
  // D5 tombstone TTL 등장 → STOP
  {
    const repo = mk([], [['account_deletion_tombstones.barrierAt', '{COLLECTION:ASCENDING} ttl=yes']]);
    const remote = mk([], [['account_deletion_tombstones.barrierAt', '{COLLECTION:ASCENDING} ttl=yes']]);
    const t = diffTtl(repo.overrides, [{
      collectionGroup: 'account_deletion_tombstones',
      fieldPath: 'barrierAt', state: 'ACTIVE',
    }]);
    const v = verdict(diffConfig(repo, remote), t);
    cases.push(['D5 tombstone TTL → 4', v.code === 4, v.code]);
  }
  // D6 PROD 프로젝트는 거부한다
  cases.push(['D6 PROD 거부', FORBIDDEN_PROJECTS.includes('alfit-prod'), 'denylist']);

  let failed = 0;
  for (const [name, ok, got] of cases) {
    console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${name}  (got ${got})`);
    if (!ok) failed++;
  }
  console.log(`=== self-test ${cases.length - failed}/${cases.length} ===`);
  return failed === 0 ? 0 : 1;
}

// ───────────────────────────────────────────────────────────── main

async function main(argv) {
  const arg = (name) => {
    const i = argv.indexOf(name);
    return i >= 0 ? argv[i + 1] : undefined;
  };
  if (argv.includes('--self-test')) return selfTest();

  const project = arg('--project') || process.env.FIRESTORE_DRIFT_PROJECT;
  if (!project) {
    console.error('usage: --project <project-id> [--key <sa.json>] | --self-test');
    return 2;
  }
  if (FORBIDDEN_PROJECTS.includes(project)) {
    console.error(`거부: ${project} 는 이 체커의 대상이 아니다 (PROD).`);
    return 2;
  }
  const keyFile = arg('--key') || process.env.GOOGLE_APPLICATION_CREDENTIALS;
  const repoFile = arg('--indexes') ||
    path.join(__dirname, '..', 'firestore.indexes.json');

  console.log(`project=${project}`);
  console.log(`repo indexes=${path.basename(repoFile)}`);
  const repo = parseRepoConfig(repoFile);
  let remote;
  try {
    remote = await fetchRemoteConfig(project, keyFile);
  } catch (e) {
    const st = e.response && e.response.status;
    console.error(`remote 조회 실패 status=${st || '?'} — 조회 실패를 "drift 없음"으로 읽지 않는다`);
    return 2;
  }
  const d = diffConfig(repo, remote);
  const t = diffTtl(repo.overrides, remote.ttlFields);
  const v = verdict(d, t);
  printReport(d, t, remote, v);
  if (arg('--out')) {
    fs.writeFileSync(arg('--out'), JSON.stringify({
      project, at: new Date().toISOString(),
      remote: {
        composites: [...remote.composites.entries()],
        overrides: [...remote.overrides.entries()],
        ttlFields: remote.ttlFields,
      },
      diff: d, ttl: t, verdict: v,
    }, null, 1), 'utf8');
    console.log(`snapshot → ${arg('--out')}`);
  }
  return v.code;
}

if (require.main === module) {
  main(process.argv.slice(2))
    .then((code) => process.exit(code))
    .catch((e) => {
      console.error('CHECKER ERROR', (e.message || String(e)).slice(0, 300));
      process.exit(2);
    });
}

module.exports = {
  compositeSignature, overrideKey, overrideShape,
  diffConfig, diffTtl, verdict, parseRepoConfig,
  FORBIDDEN_PROJECTS, FORBIDDEN_TTL,
};
