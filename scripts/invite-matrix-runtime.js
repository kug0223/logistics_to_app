/**
 * [E2 초대 10개 선택 배포] 서버(구/새) × 앱 요청 모양(구/새) × 초대 상태 — 원장·응답 실측.
 *
 *   서버 = 번들. 구 서버 = DEV 배포본(callableGetMyApplications·callableAcceptTOInvitation 이 같은
 *   e06c 번들), 새 서버 = 후보 lib. 거절(callableDeclineTOInvitation)은 10개 밖이라 **두 경우 모두
 *   DEV 배포본(e93a)** 이다 → MODE=decline 로 따로 잰다.
 *
 *   앱 = 요청 모양. 구 앱(HEAD 1.0.20 소스): 사전 동의 없음 + 수락 시 동의 버전 '2026-09-18-v3'.
 *   새 앱: 사전 동의(초대 v1) 뒤 수락 시 '2026-10-15-invite-v1'. 화면 버튼은 이 응답 필드로
 *   클라이언트 코드가 정한다(보고서에서 CODE 로 매핑).
 *
 *   실행: (firestore 에뮬레이터)
 *     BUNDLE=<e06c lib/index.js> node scripts/invite-matrix-runtime.js    # 구 서버
 *     node scripts/invite-matrix-runtime.js                               # 새 서버
 *     MODE=decline BUNDLE=<e93a lib/index.js> node scripts/invite-matrix-runtime.js
 */
'use strict';
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');
const ROOT = path.join(__dirname, '..');
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:6070';
process.env.GCLOUD_PROJECT = 'demo-alfit-r7';
process.env.FIREBASE_CONFIG = JSON.stringify({projectId: 'demo-alfit-r7', storageBucket: 'demo-alfit-r7.appspot.com'});
delete process.env.GOOGLE_APPLICATION_CREDENTIALS;
for (const line of fs.readFileSync(path.join(ROOT, 'functions', '.env.demo-alfit-r7'), 'utf8').split(/\r?\n/)) {
  const m = /^([A-Z0-9_]+)=(.*)$/.exec(line); if (m) process.env[m[1]] = m[2];
}
const log = console.log; console.error = () => {}; console.warn = () => {}; console.log = () => {}; console.info = () => {};
process.env.NODE_PATH = path.join(ROOT, 'functions', 'node_modules');
require('module').Module._initPaths();
const BUNDLE = process.env.BUNDLE || path.join(ROOT, 'functions', 'lib', 'index.js');
const MODE = process.env.MODE || 'main';
const fn = require(BUNDLE);
const admin = require(path.join(ROOT, 'functions', 'node_modules', 'firebase-admin'));
const db = admin.firestore();
const {Timestamp} = admin.firestore;
const RUN = 'im' + Date.now().toString(36);
const K = 9 * 3600e3; const NOW = Date.now();
const kstMidnight = (ms) => { const d = new Date(ms + K); return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()) - K; };
const D2 = kstMidnight(NOW + 2 * 86400e3);
const RULES = {earlyWindow: 30, earlyArrivalUnit: 10, lateGrace: 5, lateUnit: 10, lateWindow: 60, overtimeUnit: 10, earlyLeaveUnit: 10};
let seq = 0; const uid = (p) => `${p}-${RUN}-${++seq}`;
const read = async (p) => (await db.doc(p).get()).data();
const V3 = '2026-09-18-v3'; const INV1 = '2026-10-15-invite-v1';

async function world(state, appShape) {
  const biz = uid('b'); const owner = uid('o'); const to = uid('t'); const s = uid('s'); const w = uid('w'); const a = uid('a');
  await db.doc(`users/${owner}`).set({role: 'BUSINESS_ADMIN', sealBase64: 'x', businessId: biz, name: 'owner'});
  await db.doc(`businesses/${biz}`).set({isApproved: true, ownerId: owner, adminIds: [owner], name: 'biz', city: '평택시',
    address: '경기도 평택시 1', attendanceRules: RULES,
    attendancePolicyConfirmation: Object.assign({confirmedAt: Timestamp.now(), confirmedBy: owner, actorRole: 'business_admin'}, RULES)});
  await db.doc(`businesses/${biz}/contract_templates/tpl`).set({templateType: 'daily'});
  const ready = state !== 'readinessNotReady';
  await db.doc(`users/${w}`).set(Object.assign({role: 'USER', name: 'worker', accountStatus: 'active', passVerifiedAt: Timestamp.now(),
    idCardImagePath: 'p', isIdVerified: true, bankName: 'b', accountNumber: 'n', accountHolder: 'h', bankbookImagePath: 'bp',
    idDocumentVersion: 1}, ready ? {idCardMatchStatus: 'MATCHED', idCardMatchDocumentVersion: 1} : {}));
  const full = state === 'full';
  const toDoc = {businessId: biz, status: 'ACTIVE', type: 'flex', isPublished: true, title: '초대 공고', totalRequired: 2,
    totalConfirmed: full ? 2 : 0, totalPending: 1};
  if (state === 'endedUnknown') Object.assign(toDoc, {status: 'CLOSED', closedAt: Timestamp.now()}); // 사유 없음
  if (state === 'autoIntakeClosed') Object.assign(toDoc, {status: 'CLOSED', closedReason: 'ALL_SLOTS_EXPIRED', closedAt: Timestamp.now()});
  await db.doc(`tos/${to}`).set(toDoc);
  const wd = {wdId: 'wd1', workType: 'QA', startTime: '14:00', endTime: '15:00', requiredCount: 2, wage: 12000, wageType: 'hourly'};
  const slot = {date: Timestamp.fromMillis(D2), status: full ? 'full' : 'open', workDetails: [wd],
    confirmedCount: full ? 2 : 0, pendingCount: 1, workDetailCounts: {wd1: {confirmedCount: full ? 2 : 0, pendingCount: 1}}};
  if (state === 'autoIntakeClosed') {
    Object.assign(slot, {status: 'closed', closedReason: 'TIME_EXPIRED'});
    slot.workDetails = [{...wd, closedAt: Timestamp.now(), closedReason: 'TIME_EXPIRED'}];
  }
  await db.doc(`tos/${to}/slots/${s}`).set(slot);
  const exp = state === 'expired' ? NOW - 60e3 : NOW + 3600e3;
  await db.doc(`applications/${a}`).set(Object.assign({status: 'INVITED', uid: w, businessId: biz, toId: to, slotId: s, wdId: 'wd1',
    selectedWorkType: 'QA', startTime: '14:00', endTime: '15:00', workDate: Timestamp.fromMillis(D2), type: 'short', invitedBy: owner,
    invitedAt: Timestamp.now(), inviteExpiresAt: Timestamp.fromMillis(exp), appliedAt: Timestamp.now()},
  appShape === 'new' ? {documentAccessConsentGiven: true, documentAccessConsentVersion: INV1} : {}));
  return {w, a, to, s};
}
const callAs = async (name, w, data) => { try { return {ok: await fn[name].run({auth: {uid: w, token: {}}, rawRequest: {headers: {}}, data})}; } catch (e) { return {err: e.message}; } };
const STATES = ['normal', 'autoIntakeClosed', 'full', 'endedUnknown', 'expired', 'readinessNotReady'];

(async () => {
  const label = BUNDLE.replace(/\\/g, '/').split('/').slice(-4).join('/');
  if (MODE === 'decline') {
    log(`[decline · ${label}] 구 앱 '초대 정리'/'거절'(의도 표시 없음)`);
    for (const st of STATES) {
      const x = await world(st, 'old');
      const r = await callAs('callableDeclineTOInvitation', x.w, {applicationId: x.a});
      const d = await read(`applications/${x.a}`);
      const h = (d.statusHistory || []).slice(-1)[0];
      log(`  ${st.padEnd(18)} | ${r.ok ? 'OK' : 'ERR ' + r.err.slice(0, 40)} | 원장 ${d.status}${h ? ' · ' + h.action : ''}`);
    }
    process.exit(0);
  }
  log(`[server · ${label}]`);
  log('  상태               | 목록 응답(capacity · intakeClosed · endedReason · readiness) | 구 앱 수락(v3) | 새 앱 수락(사전 동의+v1)');
  for (const st of STATES) {
    const xo = await world(st, 'old'); const xn = await world(st, 'new');
    const list = await callAs('callableGetMyApplications', xo.w, {});
    const row = list.ok && (list.ok.applications || []).find((x) => x.id === xo.a || x.applicationId === xo.a);
    const proj = row ? `${row.workInstanceCapacityState ?? '—'} · ${row.publicIntakeClosed ?? '—'} · ${row.inviteEndedReason ?? '—'} · ${row.inviteAcceptReadiness ?? '—'}` :
      `목록 실패/없음 ${list.err ? list.err.slice(0, 40) : ''}`;
    const ro = await callAs('callableAcceptTOInvitation', xo.w, {applicationId: xo.a, documentAccessConsentGiven: true, documentAccessConsentVersion: V3});
    const rn = await callAs('callableAcceptTOInvitation', xn.w, {applicationId: xn.a, documentAccessConsentGiven: true, documentAccessConsentVersion: INV1});
    const [ao, an] = [await read(`applications/${xo.a}`), await read(`applications/${xn.a}`)];
    const fmt = (r, d) => `${r.ok ? 'OK' : 'ERR ' + r.err.slice(0, 34)} → ${d.status}`;
    log(`  ${st.padEnd(18)} | ${proj} | ${fmt(ro, ao)} | ${fmt(rn, an)}`);
  }
  process.exit(0);
})().catch((e) => { log('ERR ' + e.stack); process.exit(2); });
