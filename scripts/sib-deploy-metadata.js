#!/usr/bin/env node
/**
 * [SERVER-INTEGRITY-DEV-DEPLOY] 배포 **전후** 메타데이터 스냅샷 — READ ONLY.
 *
 *   `check_deploy_parity.js` 는 배포 zip 안의 `src/index.ts` 를 본다. 그런데
 *   패키징 축소 Phase 에서 `firebase.json` ignore 에 `src` 가 들어가 **zip 에
 *   소스가 없다**(그 스크립트가 바로 그 지점에서 멈춘다). 그래서 여기서는
 *   컴파일된 `lib/index.js` 를 본다.
 *
 *   무엇을 남기는가
 *     · 함수별 updateTime · 상태 · source zip 의 sha256 · 런타임/메모리/타임아웃
 *     · 서비스 계정 · env var **키 이름만**(값은 남기지 않는다)
 *     · 대상 함수의 배포된 번들에 이번 수정의 표지가 있는가
 *
 *   사용: node scripts/sib-deploy-metadata.js before|after
 */
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const https = require('https');
const crypto = require('crypto');
const cp = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const PROJECT = 'alfit-89567';
const REGION = 'asia-northeast3';
const TARGET = 'callableFinalizeEmployerSignature';
const WATCH = [
  TARGET,
  'callableGetContractPdfSignedUrl',
  'callableGetContractSignatureUrl',
  'callableFinalizeWorkerSignature',
  'getMyContracts',
  'callableGetContractsByBiz',
  'callableGetHistoricalContractById',
];
/** 이번 수정이 **배포본에 들어갔는지** 가릴 표지. */
const MARKERS = [
  'CONTRACT_CLIENT_OWNED_FIELDS',
  'srvAppEligibleForContractIssue',
];

const phase = (process.argv[2] || 'before').toLowerCase();
const OUT = path.join(ROOT, 'scripts', `sib-deploy-${phase}.json`);

function loadAdmin() {
  const dir = path.join(ROOT, 'functions');
  const keyFile = fs.readdirSync(dir).find((f) => /-adminsdk-.*\.json$/.test(f));
  if (!keyFile) { console.error('admin SDK 키 없음'); process.exit(2); }
  const key = require(path.join(dir, keyFile));
  if (key.project_id !== PROJECT) {
    console.error(`키 project_id 불일치: ${key.project_id}`); process.exit(2);
  }
  const admin = require(path.join(dir, 'node_modules', 'firebase-admin'));
  if (!admin.apps.length) {
    admin.initializeApp({credential: admin.credential.cert(key)});
  }
  return {admin, key};
}

const getJson = (host, p, tok) => new Promise((res, rej) => {
  https.get({host, path: p, headers: {Authorization: 'Bearer ' + tok}}, (s) => {
    s.setEncoding('utf8');
    let b = '';
    s.on('data', (c) => (b += c));
    s.on('end', () => {
      try { res(JSON.parse(b)); } catch (e) { rej(new Error('HTTP ' + s.statusCode + ' ' + b.slice(0, 200))); }
    });
  }).on('error', rej);
});

/** v2 `generateDownloadUrl` 은 **POST** 다 — GET 으로는 받지 못한다. */
const postJson = (host, p, tok) => new Promise((res, rej) => {
  const req = https.request({
    host, path: p, method: 'POST',
    headers: {
      Authorization: 'Bearer ' + tok,
      'Content-Type': 'application/json',
      'Content-Length': 2,
    },
  }, (s) => {
    s.setEncoding('utf8');
    let b = '';
    s.on('data', (c) => (b += c));
    s.on('end', () => {
      try { res(JSON.parse(b)); } catch (e) { rej(new Error('HTTP ' + s.statusCode + ' ' + b.slice(0, 200))); }
    });
  });
  req.on('error', rej);
  req.end('{}');
});

const download = (url, tok, file) => new Promise((res, rej) => {
  https.get(url, {headers: {Authorization: 'Bearer ' + tok}}, (s) => {
    if (s.statusCode === 301 || s.statusCode === 302) {
      s.resume();
      return download(s.headers.location, tok, file).then(res, rej);
    }
    if (s.statusCode !== 200) { s.resume(); return rej(new Error('HTTP ' + s.statusCode)); }
    const w = fs.createWriteStream(file);
    s.pipe(w);
    w.on('finish', () => res(file));
    w.on('error', rej);
  }).on('error', rej);
});

(async () => {
  const {admin, key} = loadAdmin();
  const tok = (await admin.credential.cert(key).getAccessToken()).access_token;

  const list = await getJson('cloudfunctions.googleapis.com',
      `/v2/projects/${PROJECT}/locations/${REGION}/functions?pageSize=500`, tok);
  const fns = list.functions || [];
  console.log(`함수 ${fns.length}개 (${REGION})`);

  const snap = {phase, at: new Date().toISOString(), project: PROJECT, functions: {}};
  for (const f of fns) {
    const name = f.name.split('/').pop();
    const sc = f.serviceConfig || {};
    snap.functions[name] = {
      state: f.state,
      updateTime: f.updateTime,
      runtime: (f.buildConfig || {}).runtime,
      revision: sc.revision,
      memory: sc.availableMemory,
      timeout: sc.timeoutSeconds,
      serviceAccount: sc.serviceAccountEmail,
      ingress: sc.ingressSettings,
      vpc: sc.vpcConnector ?? null,
      // 값은 남기지 않는다 — **키 이름만**.
      envKeys: Object.keys(sc.environmentVariables || {}).sort(),
      secretKeys: (sc.secretEnvironmentVariables || []).map((s) => s.key).sort(),
      sourceBucket: ((f.buildConfig || {}).source || {}).storageSource || null,
    };
  }

  // ── 대상 함수 번들에 표지가 있는가 ──
  const target = fns.find((f) => f.name.endsWith('/' + TARGET));
  if (!target) {
    console.log(`⚠️ ${TARGET} 를 찾지 못했다`);
  } else {
    const gen = await postJson('cloudfunctions.googleapis.com',
        `/v2/projects/${PROJECT}/locations/${REGION}/functions/${TARGET}:generateDownloadUrl`,
        tok).catch(() => null);
    let url = gen && gen.downloadUrl;
    if (!url) {
      console.log('  (download URL 미취득 — 번들 검사 건너뜀)');
    } else {
      const work = fs.mkdtempSync(path.join(os.tmpdir(), 'sib-'));
      const zip = path.join(work, 'fn.zip');
      await download(url, tok, zip);
      const sha = crypto.createHash('sha256')
          .update(fs.readFileSync(zip)).digest('hex');
      snap.targetZipSha256 = sha;
      let lib = '';
      try {
        lib = cp.execSync(`unzip -p "${zip}" lib/index.js`,
            {maxBuffer: 256 * 1024 * 1024}).toString('utf8');
      } catch (e) {
        console.log('  lib/index.js 추출 실패:', e.message.split('\n')[0]);
      }
      snap.targetBundle = {
        sha256: sha,
        bytes: fs.statSync(zip).size,
        markers: Object.fromEntries(
            MARKERS.map((m) => [m, lib.includes(m)])),
        // 트랜잭션 재조회가 번들에 있는가(컴파일 후 모양).
        txAppRead: /tx\.get\(db\.collection\("applications"\)\.doc\(dupAppId\)\)/
            .test(lib),
        allowlistLoop: /for \(const f of CONTRACT_CLIENT_OWNED_FIELDS\)/.test(lib),
      };
    }
  }

  fs.writeFileSync(OUT, JSON.stringify(snap, null, 2));
  console.log(`\n── ${phase.toUpperCase()} 스냅샷 → ${path.relative(ROOT, OUT)}`);
  for (const n of WATCH) {
    const f = snap.functions[n];
    console.log(`  ${f ? f.state : '없음'}  ${n}` +
      (f ? `  rev=${f.revision} upd=${f.updateTime}` : ''));
  }
  if (snap.targetBundle) {
    console.log('\n── 대상 번들 표지');
    console.log('  sha256:', snap.targetBundle.sha256.slice(0, 16) + '…',
        `(${snap.targetBundle.bytes}B)`);
    for (const [k, v] of Object.entries(snap.targetBundle.markers)) {
      console.log(`  ${v ? '있음' : '없음'}  ${k}`);
    }
    console.log(`  ${snap.targetBundle.txAppRead ? '있음' : '없음'}  트랜잭션 지원서 재조회`);
    console.log(`  ${snap.targetBundle.allowlistLoop ? '있음' : '없음'}  허용 목록 루프`);
  }
  process.exit(0);
})().catch((e) => {
  console.log('오류:', e && e.stack ? e.stack.split('\n').slice(0, 5).join('\n') : e);
  process.exit(1);
});
