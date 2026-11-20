/**
 * [BUSINESS-ARCHIVE] callableArchiveOwnBusiness — 주체·멱등·실제 onBusinessDeactivated 연쇄.
 *   (functions+firestore 에뮬레이터 기동 후) node scripts/business-archive-runtime.js
 */
'use strict';
const fs = require('fs');
const path = require('path');
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
const fn = require(path.join(ROOT, 'functions', 'lib', 'index.js'));
const admin = require(path.join(ROOT, 'functions', 'node_modules', 'firebase-admin'));
const db = admin.firestore();
const {Timestamp} = admin.firestore;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const RUN = 'ba' + Date.now().toString(36);
let pass = 0; let fail = 0;
const check = (id, ok, detail) => { (ok ? pass++ : fail++); log(`${ok ? 'PASS' : 'FAIL'} ${id} ${detail}`); };
const call = async (uid, data) => { try { return {ok: await fn.callableArchiveOwnBusiness.run({auth: {uid, token: {}}, rawRequest: {headers: {}}, data})}; } catch (e) { return {err: e.code || e.message}; } };
async function until(pred, ms) { const t0 = Date.now(); while (Date.now() - t0 < ms) { if (await pred()) return true; await sleep(1000); } return false; }

(async () => {
  const biz = `b-${RUN}`; const owner = `o-${RUN}`; const co = `c-${RUN}`; const sub = `s-${RUN}`; const w = `w-${RUN}`; const to = `t-${RUN}`;
  await db.doc(`users/${owner}`).set({role: 'BUSINESS_ADMIN', businessId: biz});
  await db.doc(`users/${co}`).set({role: 'BUSINESS_ADMIN', businessId: biz});
  await db.doc(`users/${sub}`).set({role: 'USER', subAdminBusinessIds: [biz]});
  await db.doc(`businesses/${biz}`).set({isApproved: true, ownerId: owner, adminIds: [owner, co], name: 'biz'});
  const workDate = Timestamp.fromMillis(Date.now() + 3 * 86400e3);
  await db.doc(`tos/${to}`).set({businessId: biz, creatorUID: owner, status: 'ACTIVE', type: 'contract', isPublished: true,
    title: 't', totalRequired: 2, totalConfirmed: 1, totalPending: 0, createdAt: Timestamp.now()});
  await db.doc(`applications/a-${RUN}`).set({toId: to, businessId: biz, uid: w, status: 'CONFIRMED', workDate,
    startTime: '09:00', endTime: '18:00', appliedAt: Timestamp.now(), statusHistory: []});

  const r0 = await call(owner, {});
  check('BA-1', !!r0.err, `businessId 없음 → ${r0.err}`);
  const r1 = await call(co, {businessId: biz});
  check('BA-2', r1.err === 'permission-denied', `공동관리자 → ${r1.err}`);
  const r2 = await call(sub, {businessId: biz});
  check('BA-3', r2.err === 'permission-denied', `SubAdmin → ${r2.err}`);
  const r3 = await call(`x-${RUN}`, {businessId: `none-${RUN}`});
  check('BA-4', !!r3.err, `없는 사업장 → ${r3.err}`);
  const before = (await db.doc(`businesses/${biz}`).get()).data();
  check('BA-5', before.isApproved === true && !before.archivedAt, '거부 후 사업장 변화 없음');
  // [BUSINESS-ARCHIVE] 앱과 같이 사전 조회를 먼저 받고 그 결과를 expected 로 보낸다.
  const pv = await call(owner, {businessId: biz, preview: true});
  const r4 = await call(owner, {businessId: biz, expected: pv.ok && pv.ok.preview});
  const b4 = (await db.doc(`businesses/${biz}`).get()).data();
  check('BA-6', r4.ok && r4.ok.success && b4.isApproved === false && b4.archiveReason === 'OWNER_CLOSED' && !!b4.deactivatedAt,
    `소유자 → ${JSON.stringify(r4.ok)} isApproved=${b4.isApproved} reason=${b4.archiveReason}`);
  const r5 = await call(owner, {businessId: biz});
  check('BA-7', r5.ok && r5.ok.alreadyArchived === true, `재호출 멱등 → ${JSON.stringify(r5.ok)}`);
  const chained = await until(async () => (await db.doc(`applications/a-${RUN}`).get()).data().status === 'CANCELED', 90000);
  const app = (await db.doc(`applications/a-${RUN}`).get()).data();
  const toD = (await db.doc(`tos/${to}`).get()).data();
  check('BA-8', chained && toD.status === 'CLOSED', `실제 연쇄: TO ${toD.status}/${toD.closedReason} · 확정 → ${app.status}`);
  await sleep(4000);
  const notes = await db.collection(`users/${w}/notifications`).get();
  check('BA-9', notes.size === 1, `확정 근로자 알림 ${notes.size}건 (${notes.docs.map((d) => d.id.split('_').slice(0, 2).join('_')).join(',')})`);
  check('BA-10', (await db.doc(`businesses/${biz}`).get()).exists && (await db.doc(`tos/${to}`).get()).exists && (await db.doc(`applications/a-${RUN}`).get()).exists,
    '사업장·공고·지원서 문서 모두 존재(기록 보존)');
  log(`\n${pass} pass / ${fail} fail`);
  process.exit(fail ? 1 : 0);
})().catch((e) => { log('ERR ' + e.stack); process.exit(2); });
