#!/usr/bin/env node
/**
 * [R8-P5.2] 배포 drift 검사 — "고쳤다"와 "배포됐다"는 다르다.
 *
 * 2026-09-21 감사에서, repo 에 있는 보안 수정이 DEV 에 없는 채로 몇 주가 지난 것이
 * 여러 건 확인됐다. 사업자등록증 관문 수정(323c438), Storage rules 의
 * 사업장/계약서 직접 업로드 차단(2026-07-17), 카운터 스키마 전환(Phase 8.1E),
 * 그리고 앱이 실제로 호출하는 callable 3개가 아예 배포되지 않은 상태였다.
 * 배포 시각만 보면 최신이라 아무 문제 없어 보였기 때문에 오래 드러나지 않았다.
 *
 * 이 스크립트는 시각이 아니라 내용을 본다:
 *   1. 배포된 각 함수의 source artifact(zip 안의 src/index.ts)를 실제로 내려받아
 *      HEAD 의 같은 export 블록과 코드 단위로 비교한다 (주석·공백 제외).
 *   2. 함수가 참조하는 공유 helper 까지 전이적으로 따라가 비교한다.
 *   3. HEAD 에 있는데 배포되지 않은 함수(DEPLOY MISSING)를 찾는다.
 *   4. firestore.rules / storage.rules 의 배포본과 로컬 파일을 바이트로 비교한다.
 *
 * 사용:  node scripts/check_deploy_parity.js
 * 종료코드: drift 가 하나라도 있으면 1, 없으면 0.
 *
 * 인증: functions/ 아래의 admin SDK 키(gitignore 대상)를 쓴다.
 *      키가 없으면 무엇이 필요한지 알려주고 종료한다.
 */
const fs = require('fs');
const os = require('os');
const path = require('path');
const https = require('https');
const cp = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const PROJECT = 'alfit-89567';
const WORK = fs.mkdtempSync(path.join(os.tmpdir(), 'parity-'));

function loadAdmin() {
  const dir = path.join(ROOT, 'functions');
  const keyFile = fs.readdirSync(dir).find((f) => /-adminsdk-.*\.json$/.test(f));
  if (!keyFile) {
    console.error('admin SDK 키를 functions/ 에서 찾지 못했습니다 (functions/*-adminsdk-*.json).');
    process.exit(2);
  }
  const key = require(path.join(dir, keyFile));
  if (key.project_id !== PROJECT) {
    console.error(`키의 project_id 가 ${PROJECT} 가 아닙니다: ${key.project_id}`);
    process.exit(2);
  }
  const admin = require(path.join(dir, 'node_modules', 'firebase-admin'));
  if (!admin.apps.length) admin.initializeApp({credential: admin.credential.cert(key)});
  return {admin, key};
}

const download = (url, tok, file) => new Promise((res, rej) => {
  https.get(url, {headers: {Authorization: 'Bearer ' + tok}}, (s) => {
    if (s.statusCode === 301 || s.statusCode === 302) {
      s.resume(); return download(s.headers.location, tok, file).then(res, rej);
    }
    if (s.statusCode !== 200) { s.resume(); return rej(new Error('HTTP ' + s.statusCode)); }
    const w = fs.createWriteStream(file);
    s.pipe(w); w.on('finish', () => res(file)); w.on('error', rej);
  }).on('error', rej);
});

const getJson = (host, p, tok) => new Promise((res, rej) => {
  https.get({host, path: p, headers: {Authorization: 'Bearer ' + tok}}, (s) => {
    s.setEncoding('utf8'); // 멀티바이트가 청크 경계에서 깨지면 없는 drift 가 보인다
    let b = ''; s.on('data', (c) => b += c);
    s.on('end', () => { try { res(JSON.parse(b)); } catch (e) { rej(new Error('HTTP ' + s.statusCode)); } });
  }).on('error', rej);
});

/** 주석과 공백을 지운다 — 문자열 리터럴은 남긴다. */
function codeOnly(src) {
  let out = ''; let i = 0; const n = src.length; let inS = null;
  while (i < n) {
    const c = src[i]; const c2 = src[i + 1];
    if (inS) {
      out += c;
      if (c === '\\') { out += (c2 === undefined ? '' : c2); i += 2; continue; }
      if (c === inS) inS = null;
      i++; continue;
    }
    if (c === '"' || c === "'" || c === '`') { inS = c; out += c; i++; continue; }
    if (c === '/' && c2 === '/') { while (i < n && src[i] !== '\n') i++; continue; }
    if (c === '/' && c2 === '*') { i += 2; while (i < n && !(src[i] === '*' && src[i + 1] === '/')) i++; i += 2; out += ' '; continue; }
    out += c; i++;
  }
  return out.replace(/\s+/g, ' ').trim();
}

const BOUND = /^(?:export\s+)?(?:const|let|function|async function|class|interface|type|enum)\s+([A-Za-z0-9_]+)/gm;
function slice(file) {
  const marks = []; BOUND.lastIndex = 0; let m;
  while ((m = BOUND.exec(file)) !== null) marks.push({i: m.index, name: m[1], isExport: m[0].startsWith('export')});
  const exp = {}; const sh = {};
  for (let k = 0; k < marks.length; k++) {
    const b = codeOnly(file.slice(marks[k].i, k + 1 < marks.length ? marks[k + 1].i : file.length));
    if (marks[k].isExport) exp[marks[k].name] = b; else sh[marks[k].name] = b;
  }
  return {exp, sh};
}

(async () => {
  const {admin, key} = loadAdmin();
  const tok = (await admin.credential.cert(key).getAccessToken()).access_token;
  const drift = [];

  // ── 1. Rules ───────────────────────────────────────────────
  console.log('── Rules');
  const rel = await getJson('firebaserules.googleapis.com', `/v1/projects/${PROJECT}/releases`, tok);
  for (const r of rel.releases || []) {
    const short = r.name.split('/').pop();
    const local = short.includes('firestore') ? 'firestore.rules' : short.includes('storage') ? 'storage.rules' : null;
    if (!local) continue;
    const rs = await getJson('firebaserules.googleapis.com', '/v1/' + r.rulesetName, tok);
    const remote = ((rs.source || {}).files || [])[0];
    if (!remote) continue;
    const norm = (s) => s.replace(/^﻿/, '').replace(/\r\n/g, '\n').replace(/[ \t]+$/gm, '').trim();
    const same = norm(fs.readFileSync(path.join(ROOT, local), 'utf8')) === norm(remote.content);
    console.log(`   ${same ? 'OK  ' : 'DRIFT'} ${local}  (배포 ${String(r.updateTime).slice(0, 10)})`);
    if (!same) drift.push({what: local, kind: 'rules'});
  }

  // ── 2. Functions ───────────────────────────────────────────
  console.log('── Functions');
  const listed = JSON.parse(cp.execSync(
      `firebase functions:list --project ${PROJECT} --json`,
      {cwd: ROOT, maxBuffer: 1 << 28, encoding: 'utf8'})).result || [];
  const ours = listed.filter((f) => f.source && f.source.storageSource && f.codebase === 'default');

  const byHash = {};
  ours.forEach((f) => { if (!byHash[f.hash]) byHash[f.hash] = f; });
  const src = {};
  for (const [h, f] of Object.entries(byHash)) {
    const ss = f.source.storageSource;
    const zip = path.join(WORK, h + '.zip');
    await download(`https://storage.googleapis.com/storage/v1/b/${ss.bucket}/o/` +
      `${encodeURIComponent(ss.object)}?alt=media&generation=${ss.generation}`, tok, zip);
    const ts = cp.execSync(`unzip -p "${zip}" src/index.ts`, {maxBuffer: 1 << 28, encoding: 'utf8'});
    src[h] = slice(ts);
  }

  const H = slice(fs.readFileSync(path.join(ROOT, 'functions/src/index.ts'), 'utf8'));
  const names = Object.keys(H.sh).filter((n) => n.length > 3);
  const re = {}; names.forEach((n) => re[n] = new RegExp('\\b' + n.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '\\b'));
  const closure = (body) => {
    const seen = new Set(); const stack = [body];
    while (stack.length) {
      const b = stack.pop();
      for (const n of names) if (!seen.has(n) && re[n].test(b)) { seen.add(n); if (H.sh[n]) stack.push(H.sh[n]); }
    }
    return seen;
  };

  for (const f of ours) {
    const D = src[f.hash];
    if (!H.exp[f.entryPoint]) { drift.push({what: f.id, kind: 'DEPLOYED ONLY'}); continue; }
    if (!D.exp[f.entryPoint] || H.exp[f.entryPoint] !== D.exp[f.entryPoint]) {
      drift.push({what: f.id, kind: 'CODE DRIFT', since: String(new Date(Number(f.source.storageSource.generation) / 1000).toISOString()).slice(0, 10)});
      continue;
    }
    const bad = [...closure(H.exp[f.entryPoint])].filter((n) => H.sh[n] !== D.sh[n]);
    if (bad.length) drift.push({what: f.id, kind: 'SHARED DRIFT', detail: bad.slice(0, 5).join(',')});
  }

  // HEAD 에만 있는 onCall/onDocument… = 배포 누락
  const deployed = new Set(ours.map((f) => f.entryPoint));
  for (const [name, body] of Object.entries(H.exp)) {
    if (deployed.has(name)) continue;
    if (!/\b(onCall|onRequest|onDocument\w+|onSchedule)\s*\(/.test(body)) continue; // 테스트용 export helper 는 제외
    drift.push({what: name, kind: 'DEPLOY MISSING'});
  }

  console.log(`   검사 ${ours.length}개 / drift ${drift.length}개`);
  if (drift.length) {
    console.log('\n배포본이 HEAD 와 다릅니다:');
    drift.forEach((d) => console.log(`   ${d.kind.padEnd(15)} ${d.what}${d.since ? '  (배포 ' + d.since + ')' : ''}${d.detail ? '  ← ' + d.detail : ''}`));
    console.log('\n해당 항목을 배포하십시오:');
    const fns = drift.filter((d) => d.kind !== 'rules').map((d) => 'functions:' + d.what);
    if (fns.length) console.log(`   FUNCTIONS_DISCOVERY_TIMEOUT=180 firebase deploy --only ${fns.slice(0, 10).join(',')} --project ${PROJECT}`);
    drift.filter((d) => d.kind === 'rules').forEach((d) => console.log(
        `   firebase deploy --only ${d.what === 'storage.rules' ? 'storage' : 'firestore:rules'} --project ${PROJECT}`));
  } else {
    console.log('\n배포본이 HEAD 와 일치합니다.');
  }
  fs.rmSync(WORK, {recursive: true, force: true});
  process.exit(drift.length ? 1 : 0);
})().catch((e) => { console.error(e.message); process.exit(2); });
