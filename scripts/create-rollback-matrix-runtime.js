/**
 * [INVITE-DELETE-GUARD] 공고 생성 실패 롤백 호환 행렬 — 구 앱·새 앱 × 이전/후보 Functions × 이전/후보 Rules.
 *
 *   한 번의 실행 = (BUNDLE 의 Functions) × (RULES=old|new 의 Rules). 앱 행동은 두 가지를 모두 잰다:
 *     구 앱 롤백 = 부분 슬롯·공고를 **클라이언트 직접 삭제**(REST + 에뮬레이터 토큰, 실제 rules 평가)
 *     새 앱 롤백 = callableDeleteTO(공식 soft delete)
 *   Functions 에뮬레이터가 함께 떠 있으면 onTODeleted 등 **실제 트리거**가 하드 삭제 뒤에 돈다.
 *
 *   실행: (functions+firestore 에뮬레이터 기동 후)
 *     RULES=new node scripts/create-rollback-matrix-runtime.js
 *     RULES=old BUNDLE=<이전 번들 lib/index.js> node scripts/create-rollback-matrix-runtime.js
 */
'use strict';
const fs = require('fs');
const path = require('path');
const http = require('http');
const ROOT = path.join(__dirname, '..');
const PROJECT = 'demo-alfit-r7';
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:6070';
process.env.GCLOUD_PROJECT = PROJECT;
process.env.FIREBASE_CONFIG = JSON.stringify({projectId: PROJECT});
delete process.env.GOOGLE_APPLICATION_CREDENTIALS;
for (const line of fs.readFileSync(path.join(ROOT, 'functions', '.env.demo-alfit-r7'), 'utf8').split(/\r?\n/)) {
  const m = /^([A-Z0-9_]+)=(.*)$/.exec(line); if (m) process.env[m[1]] = m[2];
}
const log = console.log; console.error = () => {}; console.warn = () => {}; console.log = () => {};
process.env.NODE_PATH = path.join(ROOT, 'functions', 'node_modules');
require('module').Module._initPaths();
const BUNDLE = process.env.BUNDLE || path.join(ROOT, 'functions', 'lib', 'index.js');
const RULES = process.env.RULES === 'old' ? 'old' : 'new';
const fn = require(BUNDLE);
const admin = require(path.join(ROOT, 'functions', 'node_modules', 'firebase-admin'));
const db = admin.firestore();
const {Timestamp} = admin.firestore;

function emuToken(uid) {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  return `${b64({alg: 'none', typ: 'JWT'})}.${b64({iss: `https://securetoken.google.com/${PROJECT}`, aud: PROJECT,
    auth_time: now, user_id: uid, sub: uid, iat: now, exp: now + 3600, firebase: {identities: {}, sign_in_provider: 'custom'}})}.`;
}
function req(method, p, body, token) {
  return new Promise((res, rej) => {
    const data = body ? JSON.stringify(body) : null;
    const r = http.request({host: '127.0.0.1', port: 6070, method, path: p,
      headers: Object.assign({'Content-Type': 'application/json'}, token ? {Authorization: 'Bearer ' + token} : {},
        data ? {'Content-Length': Buffer.byteLength(data)} : {})}, (x) => {
      const bufs = []; x.on('data', (c) => bufs.push(c)); x.on('end', () => res({status: x.statusCode, body: Buffer.concat(bufs).toString('utf8')}));
    });
    r.on('error', rej); if (data) r.write(data); r.end();
  });
}
const docPath = (p) => `/v1/projects/${PROJECT}/databases/(default)/documents/${p}`;
/** 이전 rules = 현재 파일에서 이번 단계의 삭제 차단 세 곳을 이전 문장으로 되돌린 것. */
function previousRules(src) {
  const toBlock = /( *)\/\/ \[INVITE-DELETE-GUARD\] 공고 문서의[\s\S]*?allow delete: if false;/;
  const slotBlock = /( *)\/\/ \[INVITE-DELETE-GUARD\] 슬롯 문서의[\s\S]*?allow delete: if false;/;
  const bizBlock = /( *)\/\/ \[BUSINESS-ARCHIVE 2026-10-16\][\s\S]*?allow delete: if false;/;
  for (const r of [toBlock, slotBlock, bizBlock]) if (!r.test(src)) throw new Error('표지 없음 ' + r);
  return src
    .replace(toBlock, (m, i) => `${i}allow delete: if isLoggedIn() &&\n${i}                 (isAdminOf(resource.data.businessId) ||\n${i}                  (isSubAdminOf(resource.data.businessId) &&\n${i}                   subAdminCanManageTo(resource.data.businessId)) ||\n${i}                  isSuperAdmin());`)
    .replace(slotBlock, (m, i) => `${i}allow delete: if isLoggedIn() && (isToWriteAdmin(toId) || isSuperAdmin());`)
    .replace(bizBlock, (m, i) => `${i}allow delete: if (isAdminOf(businessId) && resource.data.ownerId == request.auth.uid) || isSuperAdmin();`);
}
const CURRENT = fs.readFileSync(path.join(ROOT, 'firestore.rules'), 'utf8');
const loadRules = async (content) => {
  const r = await req('PUT', `/emulator/v1/projects/${PROJECT}:securityRules`, {rules: {files: [{name: 'firestore.rules', content}]}});
  if (r.status !== 200) throw new Error('rules 적재 실패 ' + r.status);
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const RUN = 'cr' + Date.now().toString(36);
let seq = 0;
const uid = (p) => `${p}-${RUN}-${++seq}`;
const RULESET = {earlyWindow: 30, earlyArrivalUnit: 10, lateGrace: 5, lateUnit: 10, lateWindow: 60, overtimeUnit: 10, earlyLeaveUnit: 10};
const ymd = (ms) => new Date(ms + 9 * 3600e3).toISOString().slice(0, 10);

async function seedCreated(o = {}) {
  const biz = uid('b'); const owner = uid('o'); const to = uid('t');
  await db.doc(`users/${owner}`).set({role: 'BUSINESS_ADMIN', businessId: biz, sealBase64: 'x'});
  await db.doc(`businesses/${biz}`).set({isApproved: true, ownerId: owner, adminIds: [owner], name: 'biz', city: '평택시',
    address: '경기도 평택시 1', attendanceRules: RULESET,
    attendancePolicyConfirmation: Object.assign({confirmedAt: Timestamp.now(), confirmedBy: owner, actorRole: 'business_admin'}, RULESET)});
  await db.doc(`businesses/${biz}/workTypes/wt1`).set({isActive: true, name: 'QA'});
  // callableCreateTO 가 남기는 생성 직후 모양(deferred 공개 대기)
  await db.doc(`tos/${to}`).set(Object.assign({businessId: biz, creatorUID: owner, status: 'SCHEDULED', type: 'flex',
    isPublished: false, publishMode: 'deferred', title: 't', totalRequired: 0, totalConfirmed: 0, totalPending: 0,
    createdAt: Timestamp.now(), editRevision: 0}, o.to || {}));
  if (o.partialSlot) await db.doc(`tos/${to}/slots/s-partial`).set({status: 'open', date: Timestamp.fromMillis(Date.now() + 86400e3)});
  if (o.historyApp) await db.doc(`applications/a-${to}`).set({toId: to, businessId: biz, status: o.historyApp, uid: uid('w')});
  return {biz, owner, to};
}
const flexArgs = (x, dates) => ({toId: x.to, businessId: x.biz, dates,
  workDetails: [{workType: 'QA', startTime: '14:00', endTime: '15:00', requiredCount: 1, wage: 12000, wageType: 'hourly', payScheduleType: 'next_day'}],
  deadlineType: 'HOURS_BEFORE', hoursBeforeStart: 1});
const callFlex = async (x, dates) => { try { const r = await fn.callableCreateFlexSlots.run({auth: {uid: x.owner, token: {}}, rawRequest: {headers: {}}, data: flexArgs(x, dates)}); return 'OK ' + JSON.stringify(r); } catch (e) { return 'ERR:' + e.message; } };
async function oldAppRollback(x) {
  const slots = await db.collection(`tos/${x.to}/slots`).get();
  const slotRes = [];
  for (const s of slots.docs) slotRes.push((await req('DELETE', docPath(`tos/${x.to}/slots/${s.id}`), null, emuToken(x.owner))).status);
  const toRes = (await req('DELETE', docPath(`tos/${x.to}`), null, emuToken(x.owner))).status;
  return {slotRes, toRes};
}
async function newAppRollback(x) {
  try { await fn.callableDeleteTO.run({auth: {uid: x.owner, token: {}}, rawRequest: {headers: {}}, data: {toId: x.to}}); return 'OK'; } catch (e) { return 'ERR:' + e.message; }
}
const toShape = async (to) => { const s = await db.doc(`tos/${to}`).get(); if (!s.exists) return '하드삭제됨'; const d = s.data(); return d.isDeleted ? 'soft삭제' : `${d.status}/미삭제`; };

(async () => {
  await loadRules(RULES === 'old' ? previousRules(CURRENT) : CURRENT);
  const rows = [];
  const pastDate = ymd(Date.now() - 2 * 86400e3);
  const futureDate = ymd(Date.now() + 3 * 86400e3);
  for (const app of ['구 앱', '새 앱']) {
    // 1. 생성 성공 — 롤백 경로를 타지 않는다
    const s1 = await seedCreated();
    const r1 = await callFlex(s1, [futureDate]);
    const n1 = (await db.collection(`tos/${s1.to}/slots`).get()).size;
    rows.push([app, '생성 성공', `${r1.startsWith('OK') ? '성공' : r1.slice(0, 60)} · 슬롯 ${n1} · 공고 ${await toShape(s1.to)}`]);
    // 2. 생성 실패 롤백(과거 날짜 → 서버 거절)
    const s2 = await seedCreated({partialSlot: true});
    const r2 = await callFlex(s2, [pastDate]);
    const afterServer = await toShape(s2.to);
    let appRes;
    if (app === '구 앱') { const o = await oldAppRollback(s2); appRes = `직접삭제 슬롯 ${o.slotRes.join('/') || '-'} · 공고 ${o.toRes}`; } else appRes = `callableDeleteTO ${(await newAppRollback(s2)).slice(0, 40)}`;
    rows.push([app, '생성 실패 롤백', `서버 ${r2.startsWith('ERR') ? '거절' : r2} → 서버 직후 공고 ${afterServer} → 앱 ${appRes} → 최종 ${await toShape(s2.to)}`]);
    // 3. 과거 관계 보호 — 거절된 지원서 이력이 있는 미공개·합계 0 공고
    for (const hist of ['REJECTED', 'CANCELED']) {
      const s3 = await seedCreated({historyApp: hist});
      let r3;
      if (app === '구 앱') { const o = await oldAppRollback(s3); r3 = `직접삭제 공고 ${o.toRes}`; } else r3 = `callableDeleteTO ${(await newAppRollback(s3)).slice(0, 30)}`;
      // 실제 onTODeleted 연쇄 — 공고가 하드 삭제됐으면 최대 60초 관찰(고정 대기는 첫 기동을 놓친다)
      let hasHist = true;
      const hard = !(await db.doc(`tos/${s3.to}`).get()).exists;
      for (let k = 0; k < (hard ? 60 : 3) && hasHist; k++) { hasHist = (await db.doc(`applications/a-${s3.to}`).get()).exists; if (hasHist) await sleep(1000); }
      rows.push([app, `과거 관계(${hist}) 보호`, `${r3} → 공고 ${await toShape(s3.to)} · 지원서 이력 ${hasHist ? '남음' : '★사라짐'}`]);
    }
  }
  // 4. 직접 삭제 차단 — 게시 중 공고(관계 있음)에 클라이언트 직접 삭제
  const s4 = await seedCreated({to: {status: 'ACTIVE', isPublished: true, publishMode: 'immediate', totalPending: 1}, historyApp: 'INVITED'});
  const o4 = await oldAppRollback(s4);
  for (let k = 0; k < 60 && (await db.doc(`applications/a-${s4.to}`).get()).exists && !(await db.doc(`tos/${s4.to}`).get()).exists; k++) await sleep(1000);
  rows.push(['(직접 요청)', '관계 있는 공고 직접 삭제', `공고 ${o4.toRes} → ${await toShape(s4.to)} · INVITED ${(await db.doc(`applications/a-${s4.to}`).get()).exists ? '남음' : '★사라짐'}`]);
  // 5. 사업장 직접 삭제
  const s5 = await seedCreated();
  const b5 = await req('DELETE', docPath(`businesses/${s5.biz}`), null, emuToken(s5.owner));
  rows.push(['(직접 요청)', '사업장 직접 삭제(소유자)', `HTTP ${b5.status} → 사업장 ${(await db.doc(`businesses/${s5.biz}`).get()).exists ? '남음' : '★삭제됨'}`]);

  await loadRules(CURRENT);
  log(`[Functions ${BUNDLE.replace(/\\/g, '/').split('/').slice(-4).join('/')} × Rules ${RULES === 'old' ? '이전' : '후보'}]`);
  for (const [a, k, v] of rows) log(`  ${a.padEnd(8)} | ${k.padEnd(20)} | ${v}`);
  process.exit(0);
})().catch((e) => { log('ERR ' + e.stack); process.exit(2); });
