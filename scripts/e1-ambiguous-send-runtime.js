/**
 * [ALFIT-E1-AMBIGUOUS-INVITE-SEND-CANARY-PREFLIGHT.1] 응답 불명확 초대 — 로컬 에뮬레이터 재현.
 *
 *   "서버는 정확히 한 번 저장했는데 클라이언트는 응답을 받지 못했다"를 이렇게 만든다:
 *     실제 번들의 callableInviteWorker 핸들러를 실행해 에뮬레이터 원장에 커밋시키고,
 *     그 반환값을 **버린다**(클라이언트 입장에서는 시간 초과/연결 끊김과 같다).
 *   이어서 앱이 저장 확인에 쓰는 **바로 그 서버 읽기**(callableGetApplicationsByBiz,
 *   purpose: applicantReview, {businessId,toId,uid})와, 공고 카드가 대기 수를 세는
 *   읽기(purpose: capacity, {businessId,toId,slotId})를 실제 핸들러로 받아 fixture 로
 *   남긴다. Dart 테스트(e1_ambiguous_emulator_fixture_test)가 그 응답으로 실제
 *   InviteSaveVerifier·좌석 집계를 돌린다.
 *
 *   한계(보고서에 그대로 쓴다):
 *     - 네트워크 응답 유실 자체는 재현하지 않는다(HTTP 계층 없음 — 핸들러 반환을 버림).
 *       클라이언트가 그 오류를 어떻게 분류하는지는 위젯 테스트(IAS-*)가 모의 오류로 본다.
 *     - 트리거(syncTOStats 등)는 런타임이 없어 자동으로 돌지 않는다 — 공고 totalPending 은
 *       callable 이 직접 쓴 값만 본다.
 *
 *   실행: firestore 에뮬레이터(6070) 위에서  node scripts/e1-ambiguous-send-runtime.js
 */
'use strict';
const fs = require('fs');
const path = require('path');
const net = require('net');
const http = require('http');
const https = require('https');
const assert = require('assert');
const ROOT = path.join(__dirname, '..');

process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:6070';
process.env.GCLOUD_PROJECT = 'demo-alfit-r7';
process.env.FIREBASE_CONFIG = JSON.stringify({projectId: 'demo-alfit-r7', storageBucket: 'demo-alfit-r7.appspot.com'});
process.env.FIREBASE_STORAGE_EMULATOR_HOST = '127.0.0.1:6071';
delete process.env.GOOGLE_APPLICATION_CREDENTIALS;
for (const line of fs.readFileSync(path.join(ROOT, 'functions', '.env.demo-alfit-r7'), 'utf8').split(/\r?\n/)) {
  const m = /^([A-Z0-9_]+)=(.*)$/.exec(line); if (m) process.env[m[1]] = m[2];
}
// 외부 발송 0 — 로컬 밖으로 나가는 연결은 막고 센다(FCM·Slack 등).
const outbound = [];
const isLocal = (h) => h === '127.0.0.1' || h === 'localhost' || h === '::1';
const origConnect = net.Socket.prototype.connect;
net.Socket.prototype.connect = function(...args) {
  let a = args[0]; if (Array.isArray(a)) a = a[0];
  if (a && typeof a === 'object' && a.path) return origConnect.apply(this, args);
  const host = a && typeof a === 'object' ? (a.host || 'localhost') : (typeof args[1] === 'string' ? args[1] : 'localhost');
  if (!isLocal(host)) { outbound.push('socket ' + host); throw new Error('outbound blocked ' + host); }
  return origConnect.apply(this, args);
};
for (const [mod, name] of [[https, 'request'], [https, 'get'], [http, 'request'], [http, 'get']]) {
  const orig = mod[name];
  mod[name] = function(...args) {
    const a = args[0];
    const host = typeof a === 'string' ? new URL(a).hostname : (a && (a.hostname || a.host)) || '';
    if (!isLocal(host)) { outbound.push(name + ' ' + host); throw new Error('outbound blocked ' + host); }
    return orig.apply(this, args);
  };
}
const log = console.log;
console.error = () => {}; console.warn = () => {}; console.log = () => {}; console.info = () => {};

process.env.NODE_PATH = path.join(ROOT, 'functions', 'node_modules');
require('module').Module._initPaths();
const BUNDLE = process.env.BUNDLE || path.join(ROOT, 'functions', 'lib', 'index.js');
const fn = require(BUNDLE);
const admin = require(path.join(ROOT, 'functions', 'node_modules', 'firebase-admin'));
const db = admin.firestore();
const {Timestamp} = admin.firestore;

const RUN = 'e1' + Date.now().toString(36);
const K = 9 * 3600e3;
const NOW = Date.now();
const kstMidnight = (ms) => { const d = new Date(ms + K); return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()) - K; };
const D2 = kstMidnight(NOW + 2 * 86400e3);
const DK = new Date(D2 + K).toISOString().slice(0, 10);
const RULES = {earlyWindow: 30, earlyArrivalUnit: 10, lateGrace: 5, lateUnit: 10, lateWindow: 60, overtimeUnit: 10, earlyLeaveUnit: 10};
let seq = 0;
const uid = (p) => `${p}-${RUN}-${++seq}`;
const read = async (p) => (await db.doc(p).get()).data();
const call = (name, caller, data) =>
  fn[name].run({auth: {uid: caller, token: {}}, rawRequest: {headers: {}}, data});

/** 사업장·공고·슬롯(업무 wd1, 필요 2, 대기 0) · 초대 받을 준비가 된 근로자(가능일 D2). */
async function world({availability = true} = {}) {
  const biz = uid('b'); const owner = uid('o'); const to = uid('t'); const s = uid('s'); const w = uid('w');
  await db.doc(`users/${owner}`).set({role: 'BUSINESS_ADMIN', sealBase64: 'x', businessId: biz, name: 'owner'});
  await db.doc(`businesses/${biz}`).set({isApproved: true, ownerId: owner, adminIds: [owner], name: 'biz',
    city: '평택시', address: '경기도 평택시 1', attendanceRules: RULES,
    attendancePolicyConfirmation: Object.assign({confirmedAt: Timestamp.now(), confirmedBy: owner, actorRole: 'business_admin'}, RULES)});
  await db.doc(`tos/${to}`).set({businessId: biz, status: 'ACTIVE', type: 'flex', isPublished: true,
    title: 'E1 공고', totalRequired: 2, totalConfirmed: 0, totalPending: 0, editRevision: 0});
  await db.doc(`tos/${to}/slots/${s}`).set({date: Timestamp.fromMillis(D2), status: 'open',
    workDetails: [{wdId: 'wd1', workType: 'QA', startTime: '14:00', endTime: '15:00', requiredCount: 2, wage: 12000, wageType: 'hourly'}],
    confirmedCount: 0, pendingCount: 0, workDetailCounts: {wd1: {confirmedCount: 0, pendingCount: 0}}});
  await db.doc(`users/${w}`).set({role: 'USER', name: 'worker', accountStatus: 'active', passVerifiedAt: Timestamp.now(),
    idCardImagePath: 'p', isIdVerified: true, bankName: 'b', accountNumber: 'n', accountHolder: 'h', bankbookImagePath: 'bp'});
  if (availability) {
    await db.doc(`worker_availability/${w}`).set({inviteEnabled: true, inviteRegionKeys: ['경기도|평택시'], dates: [DK],
      inviteKeys: [`경기도|평택시#${DK}`]});
  }
  return {biz, owner, to, s, w};
}
const invitePayload = (x) => ({toId: x.to, businessId: x.biz, targetUid: x.w, slotId: x.s,
  workDate: new Date(D2).toISOString(), selectedWorkType: 'QA', workDetailStartTime: '14:00', workDetailEndTime: '15:00'});

/** 원장 — 이 사람·이 공고 지원서 수, 집계, 알림. */
async function ledger(x) {
  const [apps, slot, t, notes] = await Promise.all([
    db.collection('applications').where('toId', '==', x.to).where('uid', '==', x.w).get(),
    read(`tos/${x.to}/slots/${x.s}`), read(`tos/${x.to}`),
    db.collection(`users/${x.w}/notifications`).get()]);
  return {apps: apps.size, statuses: apps.docs.map((d) => d.data().status), wdPend: slot.workDetailCounts.wd1.pendingCount,
    slotPend: slot.pendingCount, toPend: t.totalPending, notes: notes.size};
}
/** 앱의 저장 확인 읽기 — InviteSaveVerifier.check 가 보내는 것과 같은 인자. */
const verifyRead = (x, caller) => call('callableGetApplicationsByBiz', caller || x.owner,
  {businessId: x.biz, toId: x.to, uid: x.w, purpose: 'applicantReview', limit: 20});
/** 카드의 좌석 읽기 — loadTOWorkDetails 가 보내는 것과 같은 인자. */
const capacityRead = (x) => call('callableGetApplicationsByBiz', x.owner,
  {businessId: x.biz, toId: x.to, slotId: x.s, purpose: 'capacity', limit: 2000});
/** callable 응답은 JSON 으로 직렬화돼 앱에 간다 — 같은 모양으로 남긴다. */
const wire = (v) => JSON.parse(JSON.stringify(v));
/** fixture 에서 id 를 일반화(실행마다 바뀌는 값 제거). */
const norm = (rows, x) => rows.map((r) => {
  const m = JSON.parse(JSON.stringify(r).split(x.w).join('W').split(x.to).join('TO').split(x.s).join('S').split(x.biz).join('BIZ').split(x.owner).join('OWNER'));
  return m;
});

const fixture = {};
let pass = 0; const fails = []; const rows = [];
async function cell(id, name, f) {
  try { const note = await f(); pass++; rows.push(`  ok   ${id} ${name}${note ? ' — ' + note : ''}`); } catch (e) {
    fails.push(id); rows.push(`  FAIL ${id} ${name} — ${String(e.stack || e.message).split('\n').slice(0, 2).join(' | ')}`);
  }
}

(async () => {
  log(`[RUN ${RUN}] 번들 ${BUNDLE.replace(/\\/g, '/').split('/').slice(-3).join('/')} · 근무일 ${DK}`);

  await cell('E1-A', '서버가 한 번 저장 → 응답 버림(불명확) → 확인 읽기에 초대가 보인다', async () => {
    const x = await world();
    const before = await ledger(x);
    const pre = wire(await verifyRead(x));                     // 저장 전(늦게 보이는 저장의 '이전')
    let thrown = null;
    try { await call('callableInviteWorker', x.owner, invitePayload(x)); } catch (e) { thrown = e.message; }
    assert.strictEqual(thrown, null, '서버가 저장하지 못했다: ' + thrown);
    // ↑ 반환값을 버린다 — 앱은 timeout/연결 끊김을 받은 것과 같다.
    const after = await ledger(x);
    const post = wire(await verifyRead(x));
    const cap = wire(await capacityRead(x));
    assert.deepStrictEqual([before.apps, after.apps], [0, 1], '정확히 1건');
    assert.deepStrictEqual(after.statuses, ['INVITED']);
    assert.strictEqual(after.wdPend, 1); assert.strictEqual(after.slotPend, 1);
    fixture.saved = {pre: norm(pre.applications, x), post: norm(post.applications, x), capacity: norm(cap.applications, x),
      ledger: after};
    return `원장 지원서 ${before.apps}→${after.apps}(INVITED) · 업무/슬롯/공고 대기 ${after.wdPend}/${after.slotPend}/${after.toPend} · 알림 ${before.notes}→${after.notes} · 확인 읽기 ${pre.applications.length}→${post.applications.length}행`;
  });

  await cell('E1-B', '불명확 뒤 같은 사람 재발송 → already-exists, 두 번째 지원서 없음', async () => {
    const x = await world();
    await call('callableInviteWorker', x.owner, invitePayload(x));
    let err = null;
    try { await call('callableInviteWorker', x.owner, invitePayload(x)); } catch (e) { err = e; }
    const l = await ledger(x);
    assert.ok(err && err.code === 'already-exists', '재발송이 거절되지 않았다: ' + (err && err.code));
    assert.strictEqual(l.apps, 1); assert.strictEqual(l.wdPend, 1);
    return `재발송 ${err.code} · 지원서 ${l.apps} · 업무 대기 ${l.wdPend} · 알림 ${l.notes}`;
  });

  await cell('E1-C', '대조 — 요청을 보내지 않았다 → 확인 읽기 0행', async () => {
    const x = await world();
    const r = wire(await verifyRead(x));
    const l = await ledger(x);
    assert.strictEqual(r.applications.length, 0); assert.strictEqual(l.apps, 0);
    fixture.notSent = {post: norm(r.applications, x), ledger: l};
    return `확인 읽기 0행 · 원장 0`;
  });

  await cell('E1-D', '대조 — 서버가 쓰기 전에 거절(가능일 없음) → 명확한 거절 코드 · 쓰기 0', async () => {
    const x = await world({availability: false});
    let err = null;
    try { await call('callableInviteWorker', x.owner, invitePayload(x)); } catch (e) { err = e; }
    const l = await ledger(x);
    const r = wire(await verifyRead(x));
    assert.ok(err, '거절되지 않았다');
    assert.strictEqual(l.apps, 0); assert.strictEqual(l.wdPend, 0); assert.strictEqual(r.applications.length, 0);
    fixture.rejected = {code: err.code, post: norm(r.applications, x)};
    return `${err.code} · 지원서 0 · 대기 0 · 알림 ${l.notes}`;
  });

  await cell('E1-E', '대조 — 확인 읽기 자체가 실패(권한 없는 호출자 · 목적 누락)', async () => {
    const x = await world();
    await call('callableInviteWorker', x.owner, invitePayload(x));
    const stranger = uid('o');
    await db.doc(`users/${stranger}`).set({role: 'BUSINESS_ADMIN', businessId: 'other', name: 'stranger'});
    const errs = [];
    try { await verifyRead(x, stranger); errs.push('통과?'); } catch (e) { errs.push(e.code); }
    try { await call('callableGetApplicationsByBiz', x.owner, {businessId: x.biz, toId: x.to, uid: x.w, limit: 20}); errs.push('통과?'); } catch (e) { errs.push(e.code); }
    assert.ok(!errs.includes('통과?'), errs.join(','));
    fixture.readFailCodes = errs;
    const l = await ledger(x);
    return `실패 코드 ${errs.join(' · ')} · 원장은 저장됨(지원서 ${l.apps}) — 모름 ≠ 미저장`;
  });

  await cell('E1-F', '카드 좌석 읽기(capacity) — 초대 1건이 대기로 보인다', async () => {
    const cap = fixture.saved && fixture.saved.capacity;
    assert.ok(cap && cap.length === 1, '좌석 읽기 행');
    assert.strictEqual(cap[0].status, 'INVITED');
    assert.ok('appliedAt' in cap[0] && 'workDate' in cap[0], '파서 필수 필드');
    return `capacity 행 ${cap.length} · status ${cap[0].status} · uid 필드 ${'uid' in cap[0] ? '있음' : '없음'}`;
  });

  const out = path.join(ROOT, 'test', 'fixtures', 'e1_emulator_ambiguous.json');
  fs.writeFileSync(out, JSON.stringify(Object.assign({run: RUN, bundle: path.basename(path.dirname(path.dirname(BUNDLE))), workDateKey: DK}, fixture), null, 1));
  for (const r of rows) log(r);
  log(`\n${pass} pass · ${fails.length} fail${fails.length ? ' (' + fails.join(',') + ')' : ''} · 외부 연결 시도 ${outbound.length}${outbound.length ? ' ' + [...new Set(outbound)].join(',') : ''}`);
  log(`fixture → ${path.relative(ROOT, out)}`);
  process.exit(fails.length ? 1 : 0);
})().catch((e) => { log('ERR ' + e.stack); process.exit(2); });
