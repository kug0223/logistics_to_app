/**
 * [INVITE-DECLINE-INTENT] 초대 거절 writer 원장 계약 — 상태 × 의도 표시(없음/EXPLICIT) × 번들.
 *
 *   셀마다 새 세계를 만들고 callableDeclineTOInvitation 을 부른 뒤 **전후값**을 비교한다:
 *   지원서 status · statusHistory 마지막 action · 슬롯/업무/공고 대기 집계 · 초대한 관리자 알림 수.
 *
 *   실행: (firestore 에뮬레이터)
 *     node scripts/decline-matrix-runtime.js                         # 후보
 *     BUNDLE=<DEV 배포본 lib/index.js> node scripts/decline-matrix-runtime.js
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
const fn = require(BUNDLE);
const admin = require(path.join(ROOT, 'functions', 'node_modules', 'firebase-admin'));
const db = admin.firestore();
const {Timestamp} = admin.firestore;
const RUN = 'dm' + Date.now().toString(36);
const K = 9 * 3600e3; const NOW = Date.now();
const kstMidnight = (ms) => { const d = new Date(ms + K); return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()) - K; };
const D2 = kstMidnight(NOW + 2 * 86400e3);
let seq = 0; const uid = (p) => `${p}-${RUN}-${++seq}`;
const read = async (p) => (await db.doc(p).get()).data();

async function world(state) {
  const biz = uid('b'); const owner = uid('o'); const to = uid('t'); const s = uid('s'); const w = uid('w'); const a = uid('a');
  await db.doc(`users/${owner}`).set({role: 'BUSINESS_ADMIN', businessId: biz, name: 'owner'});
  await db.doc(`businesses/${biz}`).set({isApproved: true, ownerId: owner, adminIds: [owner], name: 'biz'});
  await db.doc(`users/${w}`).set({role: 'USER', name: 'worker', accountStatus: 'active'});
  const full = state === 'full';
  const toDoc = {businessId: biz, status: 'ACTIVE', type: 'flex', isPublished: true, title: '초대 공고', totalRequired: 2,
    totalConfirmed: full ? 2 : 0, totalPending: 1};
  if (state === 'endedUnknown') Object.assign(toDoc, {status: 'CLOSED', closedAt: Timestamp.now()});
  if (state === 'manualClosed') Object.assign(toDoc, {status: 'CLOSED', closedReason: 'MANUAL', isManualClosed: true, closedBy: owner, closedAt: Timestamp.now()});
  if (state === 'autoIntakeClosed') Object.assign(toDoc, {status: 'CLOSED', closedReason: 'ALL_SLOTS_EXPIRED', closedAt: Timestamp.now()});
  await db.doc(`tos/${to}`).set(toDoc);
  const wd = {wdId: 'wd1', workType: 'QA', startTime: '14:00', endTime: '15:00', requiredCount: 2};
  const slot = {date: Timestamp.fromMillis(D2), status: full ? 'full' : 'open', workDetails: [wd],
    confirmedCount: full ? 2 : 0, pendingCount: 1, workDetailCounts: {wd1: {confirmedCount: full ? 2 : 0, pendingCount: 1}}};
  if (state === 'autoIntakeClosed') {
    Object.assign(slot, {status: 'closed', closedReason: 'TIME_EXPIRED'});
    slot.workDetails = [{...wd, closedAt: Timestamp.now(), closedReason: 'TIME_EXPIRED'}];
  }
  await db.doc(`tos/${to}/slots/${s}`).set(slot);
  const app = {status: 'INVITED', uid: w, businessId: biz, toId: to, slotId: s, wdId: state === 'unknown' ? 'wd-missing' : 'wd1',
    selectedWorkType: 'QA', startTime: '14:00', endTime: '15:00', workDate: Timestamp.fromMillis(D2), type: 'short',
    invitedBy: owner, invitedAt: Timestamp.now(), inviteExpiresAt: Timestamp.fromMillis(NOW + 3600e3), toTitle: '초대 공고',
    statusHistory: []};
  if (state === 'withdrawn') Object.assign(app, {status: 'CANCELED', cancelReason: 'RECRUIT_CLOSED'});
  if (state === 'expiredInvited') app.inviteExpiresAt = Timestamp.fromMillis(NOW - 60e3);
  if (state === 'expiredStatus') Object.assign(app, {status: 'EXPIRED', inviteExpiresAt: Timestamp.fromMillis(NOW - 60e3)});
  if (state === 'confirmed') Object.assign(app, {status: 'CONFIRMED', confirmedAt: Timestamp.now()});
  if (state === 'rejected') Object.assign(app, {status: 'REJECTED', statusHistory: [{status: 'REJECTED', action: 'INVITE_DECLINED'}]});
  await db.doc(`applications/${a}`).set(app);
  return {biz, owner, to, s, w, a};
}
async function snap(x) {
  const [ap, sl, t] = await Promise.all([read(`applications/${x.a}`), read(`tos/${x.to}/slots/${x.s}`), read(`tos/${x.to}`)]);
  const n = (await db.collection(`users/${x.owner}/notifications`).get()).size;
  const h = (ap.statusHistory || []).slice(-1)[0];
  return {st: ap.status, act: h ? h.action : '-', slotP: sl.pendingCount, wdP: (sl.workDetailCounts.wd1 || {}).pendingCount, toP: t.totalPending, notif: n};
}
const STATES = ['open', 'autoIntakeClosed', 'full', 'manualClosed', 'endedUnknown', 'unknown', 'withdrawn',
  'expiredInvited', 'expiredStatus', 'confirmed', 'rejected'];
const MODE = process.env.MODE || 'matrix';
const XFILE = path.join(require('os').tmpdir(), 'alfit-decline-partial.json');
(async () => {
  // ── 배포 중간 상태: 목록 함수(구) → 같은 원장 → 거절 함수(새) — 번들마다 프로세스가 다르다 ──
  if (MODE === 'seed-list') {
    const out = [];
    for (const st of ['autoIntakeClosed', 'full', 'manualClosed', 'endedUnknown', 'open']) {
      const x = await world(st);
      let cap = '—';
      try {
        const r = await fn.callableGetMyApplications.run({auth: {uid: x.w, token: {}}, rawRequest: {headers: {}}, data: {}});
        const row = (r.applications || []).find((a) => a.id === x.a || a.applicationId === x.a);
        cap = row ? row.workInstanceCapacityState : '없음';
      } catch (e) { cap = 'ERR ' + e.message.slice(0, 30); }
      const oldAppButton = cap === 'full' || cap === 'closed' ? "'초대 정리'" : cap === 'available' ? "'수락하기'+'거절'" : "'거절'";
      out.push({st, x, cap, oldAppButton, before: await snap(x)});
    }
    fs.writeFileSync(XFILE, JSON.stringify(out));
    log(`[목록 ${BUNDLE.replace(/\\/g, '/').split('/').slice(-4).join('/')}] ${out.length}건 → ${XFILE}`);
    process.exit(0);
  }
  if (MODE === 'decline-from') {
    const rows = JSON.parse(fs.readFileSync(XFILE, 'utf8'));
    log(`[거절 ${BUNDLE.replace(/\\/g, '/').split('/').slice(-4).join('/')}] 구 앱(의도 없음) — 구 목록이 보여 준 버튼을 누른 경우`);
    for (const r of rows) {
      let res;
      try { await fn.callableDeclineTOInvitation.run({auth: {uid: r.x.w, token: {}}, rawRequest: {headers: {}}, data: {applicationId: r.x.a}}); res = 'OK'; } catch (e) {
        res = `ERR ${(e.details && e.details.code) || e.code}`;
      }
      await new Promise((ok) => setTimeout(ok, 300));
      const a = await snap(r.x);
      const f = (v) => `${v.st}·${v.act}·${v.slotP}/${v.wdP}/${v.toP}·${v.notif}`;
      log(`  ${r.st.padEnd(17)} | 구 목록 ${String(r.cap).padEnd(9)} → 구 앱 ${r.oldAppButton.padEnd(16)} | ${res.padEnd(36)} | ${f(r.before)} → ${f(a)}`);
    }
    process.exit(0);
  }
  if (MODE === 'extra') {
    // 권한 없는 호출 · 탈퇴 중 관리자 알림 생략(대조: 정상 관리자)
    const x = await world('open');
    const stranger = uid('x');
    await db.doc(`users/${stranger}`).set({role: 'USER', name: 'x', accountStatus: 'active'});
    const b = await snap(x);
    let r1;
    try { await fn.callableDeclineTOInvitation.run({auth: {uid: stranger, token: {}}, rawRequest: {headers: {}}, data: {applicationId: x.a, declineIntent: 'EXPLICIT'}}); r1 = 'OK(!)'; } catch (e) { r1 = e.code; }
    const a = await snap(x);
    log(`  권한 없는 호출(다른 근로자) | ${r1} | 변화 ${JSON.stringify(a) === JSON.stringify(b) ? '없음' : '있음(!)'}`);
    for (const [label, tomb] of [['정상 관리자', false], ['탈퇴 중 관리자(tombstone)', true]]) {
      const y = await world('open');
      if (tomb) await db.doc(`account_deletion_tombstones/${y.owner}`).set({createdAt: Timestamp.now()});
      await fn.callableDeclineTOInvitation.run({auth: {uid: y.w, token: {}}, rawRequest: {headers: {}}, data: {applicationId: y.a, declineIntent: 'EXPLICIT'}});
      await new Promise((ok) => setTimeout(ok, 800));
      const n = (await db.collection(`users/${y.owner}/notifications`).get()).size;
      log(`  거절 알림 → ${label} | 지원서 ${(await read(`applications/${y.a}`)).status} · 알림 ${n}건`);
    }
    process.exit(0);
  }
  log(`[${BUNDLE.replace(/\\/g, '/').split('/').slice(-4).join('/')}]`);
  log('  상태              | 의도     | 응답                                   | 전 → 후 (status·action·슬롯/업무/공고 대기·관리자 알림)');
  for (const st of STATES) {
    for (const intent of [undefined, 'EXPLICIT']) {
      const x = await world(st);
      const b = await snap(x);
      let res;
      try { await fn.callableDeclineTOInvitation.run({auth: {uid: x.w, token: {}}, rawRequest: {headers: {}},
        data: intent ? {applicationId: x.a, declineIntent: intent} : {applicationId: x.a}}); res = 'OK'; } catch (e) {
        res = `ERR ${(e.details && e.details.code) || e.code}`;
      }
      await new Promise((r) => setTimeout(r, 300)); // 알림은 fire-and-forget
      const a = await snap(x);
      const f = (v) => `${v.st}·${v.act}·${v.slotP}/${v.wdP}/${v.toP}·${v.notif}`;
      const changed = JSON.stringify(b) !== JSON.stringify(a);
      log(`  ${st.padEnd(17)} | ${(intent || '없음').padEnd(8)} | ${res.padEnd(38)} | ${f(b)} → ${f(a)}${changed ? '' : ' (변화 없음)'}`);
    }
  }
  process.exit(0);
})().catch((e) => { log('ERR ' + e.stack); process.exit(2); });
