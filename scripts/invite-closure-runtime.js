/**
 * [INVITE-CLOSURE-PROJECTION · INVITE-CAPACITY · INVITE-CLOSURE-WRITER · INVITE-DELETE-GUARD]
 * 런타임 계약 — 번들(functions/lib/index.js)의 **실제 callable·트리거 본문**을
 * 격리 Firestore 에뮬레이터(demo-alfit-r7, 127.0.0.1:6070)에서 실행한다.
 *
 *   실행:
 *     firebase emulators:start --only firestore --project demo-alfit-r7 --config firebase.r7audit.json
 *     npm --prefix functions run build
 *     node scripts/invite-closure-runtime.js            # 후보 번들
 *     BUNDLE=<배포본 lib/index.js> node scripts/invite-closure-runtime.js   # 같은 셀을 다른 번들로
 *
 *   격리: DEV·PROD 접근 없음. 127.0.0.1 외 소켓·http(s) 전부 차단·기록.
 *     자격증명 미설정, .env 는 dummy 사본(functions/.env.demo-alfit-r7)만 로드.
 *   범위 밖(정직하게): App Check·인증 토큰 검증 층(.run 은 그 뒤를 부른다),
 *     실제 동시 트랜잭션 경합(에뮬레이터는 충돌 감지가 없다), FCM 발송.
 *   트리거는 자동으로 돌지 않는다 — syncTOStats·onTODeleted 는 이 스크립트가
 *     같은 이벤트 모양으로 **직접** 호출한다(그 호출을 셀에 적는다).
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
process.env.FIREBASE_CONFIG = JSON.stringify({projectId: 'demo-alfit-r7'});
delete process.env.GOOGLE_APPLICATION_CREDENTIALS;
for (const line of fs.readFileSync(path.join(ROOT, 'functions', '.env.demo-alfit-r7'), 'utf8').split(/\r?\n/)) {
  const m = /^([A-Z0-9_]+)=(.*)$/.exec(line); if (m) process.env[m[1]] = m[2];
}
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
console.error = () => {}; console.warn = () => {}; console.log = () => {};

process.env.NODE_PATH = path.join(ROOT, 'functions', 'node_modules');
require('module').Module._initPaths();
const BUNDLE = process.env.BUNDLE || path.join(ROOT, 'functions', 'lib', 'index.js');
const fn = require(BUNDLE);
const admin = require(path.join(ROOT, 'functions', 'node_modules', 'firebase-admin'));
const db = admin.firestore();
const {Timestamp} = admin.firestore;

const RUN = 'ic' + Date.now().toString(36);
const K = 9 * 3600e3;
const NOW = Date.now();
const kstMidnight = (ms) => { const d = new Date(ms + K); return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()) - K; };
const hhmm = (ms) => new Date(ms + K).toISOString().slice(11, 16);
const D2 = kstMidnight(NOW + 2 * 86400e3);
const D3 = kstMidnight(NOW + 3 * 86400e3);
const RULES = {earlyWindow: 30, earlyArrivalUnit: 10, lateGrace: 5, lateUnit: 10, lateWindow: 60, overtimeUnit: 10, earlyLeaveUnit: 10};
const AUTO_SLOT = {status: 'closed', closedReason: 'TIME_EXPIRED'};
const AUTO_WD = {closedReason: 'TIME_EXPIRED'};
const AUTO_TO = {status: 'CLOSED', closedReason: 'ALL_SLOTS_EXPIRED'};

let seq = 0;
const uid = (p) => `${p}-${RUN}-${++seq}`;

/** 사업장·관리자 — 계약 능력·근태 기준 확인까지 갖춘 최소 모양. */
async function seedBusiness() {
  const biz = uid('b'); const owner = uid('o');
  await db.doc(`users/${owner}`).set({role: 'BUSINESS_ADMIN', sealBase64: 'x', businessId: biz, name: 'owner'});
  await db.doc(`businesses/${biz}`).set({isApproved: true, ownerId: owner, adminIds: [owner], name: 'biz',
    city: '평택시', address: '경기도 평택시 1', attendanceRules: RULES,
    attendancePolicyConfirmation: Object.assign({confirmedAt: Timestamp.now(), confirmedBy: owner, actorRole: 'business_admin'}, RULES)});
  await db.doc(`businesses/${biz}/contract_templates/tpl`).set({templateType: 'daily'});
  return {biz, owner};
}
/** 수락 준비가 끝난 근로자(자동판정 MATCHED — 에뮬레이터 합성값). */
async function seedWorker(o = {}) {
  const w = uid('w');
  await db.doc(`users/${w}`).set(Object.assign({role: 'USER', name: 'worker', accountStatus: 'active',
    passVerifiedAt: Timestamp.now(), idCardImagePath: 'p', isIdVerified: true, bankName: 'b', accountNumber: 'n',
    accountHolder: 'h', bankbookImagePath: 'bp', idDocumentVersion: 1, idCardMatchStatus: 'MATCHED',
    idCardMatchDocumentVersion: 1}, o));
  return w;
}
/** 슬롯 1개(업무 1개). 카운터는 실제 원장 모양 그대로. */
async function seedSlot(to, {day, req = 2, conf = 0, pend = 0, wdId = 'wd1', start = '14:00', end = '15:00', slot = {}, wd = {}}) {
  const s = uid('s');
  const w = Object.assign({wdId, workType: 'QA', startTime: start, endTime: end, requiredCount: req, wage: 12000, wageType: 'hourly'}, wd);
  await db.doc(`tos/${to}/slots/${s}`).set(Object.assign({date: Timestamp.fromMillis(day), status: conf >= req ? 'full' : 'open',
    workDetails: [w], confirmedCount: conf, pendingCount: pend, workDetailCounts: {[wdId]: {confirmedCount: conf, pendingCount: pend}}}, slot));
  return s;
}
async function seedInvite({biz, owner, w, to, slot, day, wdId = 'wd1', start = '14:00', end = '15:00', exp = NOW + 3600e3, extra = {}}) {
  const a = uid('a');
  await db.doc(`applications/${a}`).set(Object.assign({status: 'INVITED', uid: w, businessId: biz, toId: to, slotId: slot, wdId,
    selectedWorkType: 'QA', startTime: start, endTime: end, workDate: Timestamp.fromMillis(day), type: 'short', invitedBy: owner,
    invitedAt: Timestamp.now(), inviteExpiresAt: Timestamp.fromMillis(exp), documentAccessConsentGiven: true,
    documentAccessConsentVersion: '2026-10-15-invite-v1'}, extra));
  return a;
}
const accept = (w, a) => fn.callableAcceptTOInvitation.run({auth: {uid: w, token: {}}, rawRequest: {headers: {}},
  data: {applicationId: a, documentAccessConsentGiven: true, documentAccessConsentVersion: '2026-10-15-invite-v1'}});
const tryAccept = async (w, a) => { try { await accept(w, a); return 'OK'; } catch (e) { return 'ERR:' + e.message; } };
/** syncTOStats 를 실제 이벤트 모양으로 부른다(에뮬레이터에 트리거 런타임이 없다). */
async function runSyncTOStats(appId, before, after) {
  const snap = (d) => ({exists: d != null, data: () => d});
  await fn.syncTOStats.run({params: {applicationId: appId}, data: {before: snap(before), after: snap(after)}});
}
const read = async (p) => (await db.doc(p).get()).data();

let pass = 0; const fails = []; const rows = [];
async function cell(id, name, f) {
  try { const note = await f(); pass++; rows.push(`  ok   ${id} ${name}${note ? ' — ' + note : ''}`); } catch (e) {
    fails.push(id); rows.push(`  FAIL ${id} ${name} — ${String(e.message).split('\n')[0]}`);
  }
}

(async () => {
  log(`[RUN ${RUN}] 번들 ${BUNDLE.replace(/\\/g, '/').split('/').slice(-4).join('/')}`);

  // ── A. 여러 날짜 공고의 정원 불변식 ─────────────────────────────────────
  //   닫힌 날 0/2(자동 접수 마감, 그 날의 기존 초대 IA) + 열린 날 X/2(초대 IB).
  //   totalRequired 는 스케줄러(TO-M-06)가 닫힌 날 2를 뺀 값 = 2.
  async function twoDay(openConf) {
    const {biz, owner} = await seedBusiness();
    const to = uid('t');
    await db.doc(`tos/${to}`).set({businessId: biz, status: 'ACTIVE', type: 'flex', isPublished: true, title: 't',
      totalRequired: 2, totalConfirmed: openConf, totalPending: 2});
    const sA = await seedSlot(to, {day: D2, req: 2, conf: 0, pend: 1, slot: AUTO_SLOT, wd: Object.assign({closedAt: Timestamp.now()}, AUTO_WD)});
    const sB = await seedSlot(to, {day: D3, req: 2, conf: openConf, pend: 1});
    const wA = await seedWorker(); const wB = await seedWorker();
    const iA = await seedInvite({biz, owner, w: wA, to, slot: sA, day: D2});
    const iB = await seedInvite({biz, owner, w: wB, to, slot: sB, day: D3});
    // 열린 날의 확정은 **실제 CONFIRMED 지원서**로 둔다 — syncTOStats 는 원장을 다시 센다.
    for (let i = 0; i < openConf; i++) {
      const wc = await seedWorker();
      await seedInvite({biz, owner, w: wc, to, slot: sB, day: D3, extra: {status: 'CONFIRMED', confirmedAt: Timestamp.now()}});
    }
    return {to, sA, sB, wA, wB, iA, iB};
  }
  const state = async (x) => {
    const [t, a, b] = await Promise.all([read(`tos/${x.to}`), read(`tos/${x.to}/slots/${x.sA}`), read(`tos/${x.to}/slots/${x.sB}`)]);
    return `TO ${t.status} conf ${t.totalConfirmed} pend ${t.totalPending} | A ${a.status} ${a.workDetailCounts.wd1.confirmedCount}/2 대기${a.workDetailCounts.wd1.pendingCount} | B ${b.status} ${b.workDetailCounts.wd1.confirmedCount}/2 대기${b.workDetailCounts.wd1.pendingCount}`;
  };
  const capRows = [];
  for (const [openConf, order] of [[2, 'AB'], [2, 'BA'], [1, 'AB'], [1, 'BA']]) {
    const x = await twoDay(openConf);
    // 시작 상태에서 syncTOStats 가 공고 FULL 을 어떻게 정하는가(옛 합계식이면 2>=2 → FULL)
    await runSyncTOStats(x.iB, null, await read(`applications/${x.iB}`));
    const s0 = await state(x);
    const steps = [];
    for (const k of order) {
      const r = k === 'A' ? await tryAccept(x.wA, x.iA) : await tryAccept(x.wB, x.iB);
      const appId = k === 'A' ? x.iA : x.iB;
      await runSyncTOStats(appId, {status: 'INVITED'}, await read(`applications/${appId}`));
      steps.push(`${k}:${r.startsWith('OK') ? '수락' : r.replace('ERR:', '거절 ')} ⇒ ${await state(x)}`);
    }
    capRows.push({openConf, order, s0, steps, x});
  }
  await cell('CAP-1', '닫힌 0/2 + 열린 2/2 — 시작 상태(공고 FULL 은 열린 날 기준, 닫힌 날 초대는 살아 있다)', async () => {
    const c = capRows.find((r) => r.openConf === 2 && r.order === 'AB');
    return c.s0;
  });
  for (const c of capRows) {
    await cell(`CAP-${c.openConf}${c.order}`, `열린 날 ${c.openConf}/2 · 수락 순서 ${c.order}`, async () => {
      const iA = await read(`applications/${c.x.iA}`); const iB = await read(`applications/${c.x.iB}`);
      assert.strictEqual(iA.status, 'CONFIRMED', '닫힌 날 초대(IA)는 단위 자리가 있으니 수락돼야 한다');
      if (c.openConf === 2) assert.strictEqual(iB.status, 'INVITED', '꽉 찬 열린 날 초대(IB)는 단위 정원으로 거절');
      else assert.strictEqual(iB.status, 'CONFIRMED');
      const a = await read(`tos/${c.x.to}/slots/${c.x.sA}`); const b = await read(`tos/${c.x.to}/slots/${c.x.sB}`);
      assert.ok(a.workDetailCounts.wd1.confirmedCount <= 2 && b.workDetailCounts.wd1.confirmedCount <= 2, '단위 초과 확정');
      return c.steps.join('  →  ');
    });
  }
  await cell('CAP-9', '열린 날이 꽉 차면 공고 FULL, 닫힌 날 수락은 그와 무관(슬롯 status 파생)', async () => {
    const c = capRows.find((r) => r.openConf === 2 && r.order === 'BA');
    const t = await read(`tos/${c.x.to}`);
    return `최종 TO ${t.status}`;
  });

  await cell('CAP-F', '닫힌 날 확정 2/2(필요 인원 차감) + 열린 날 0/2 → 공고 FULL 이 아니다(옛 합계식이면 FULL → 열린 날 초대·비슬롯 관문이 막힘)', async () => {
    const {biz, owner} = await seedBusiness();
    const to = uid('t');
    await db.doc(`tos/${to}`).set({businessId: biz, status: 'ACTIVE', type: 'flex', isPublished: true, title: 't',
      totalRequired: 2, totalConfirmed: 2, totalPending: 0});
    const sA = await seedSlot(to, {day: D2, req: 2, conf: 2, slot: AUTO_SLOT, wd: Object.assign({closedAt: Timestamp.now()}, AUTO_WD)});
    await seedSlot(to, {day: D3, req: 2, conf: 0});
    let lastApp = null;
    for (let i = 0; i < 2; i++) {
      const wc = await seedWorker();
      lastApp = await seedInvite({biz, owner, w: wc, to, slot: sA, day: D2, extra: {status: 'CONFIRMED', confirmedAt: Timestamp.now()}});
    }
    await runSyncTOStats(lastApp, null, await read(`applications/${lastApp}`));
    const t = await read(`tos/${to}`);
    assert.strictEqual(t.status, 'ACTIVE', `TO ${t.status} (totalConfirmed ${t.totalConfirmed} ≥ totalRequired ${t.totalRequired})`);
    return `TO ${t.status} · 합계 ${t.totalConfirmed}/${t.totalRequired}(옛 식이면 FULL)`;
  });

  // ── B. 근로자 목록 투영 → 실제 응답 ─────────────────────────────────────
  async function projection(o) {
    const {biz, owner} = await seedBusiness();
    const to = uid('t');
    if (!o.noTo) await db.doc(`tos/${to}`).set(Object.assign({businessId: biz, status: 'ACTIVE', type: 'flex', isPublished: true, title: 't', totalRequired: 2, totalPending: 1}, o.to || {}));
    const s = await seedSlot(to, Object.assign({day: o.day || D2, req: 2, conf: o.conf || 0, pend: 1}, o.slotArgs || {}));
    const w = await seedWorker(o.worker || {});
    const a = await seedInvite({biz, owner, w, to, slot: s, day: o.day || D2, start: (o.slotArgs || {}).start, end: (o.slotArgs || {}).end, exp: o.exp, extra: o.extra});
    const r = await fn.callableGetMyApplications.run({auth: {uid: w, token: {}}, rawRequest: {headers: {}}, data: {}});
    const row = (r.applications || []).find((x) => x.id === a) || {};
    return {row, w, a, to, s, biz, owner};
  }
  const show = (row) => `cap=${row.workInstanceCapacityState} intake=${row.publicIntakeClosed} ended=${row.inviteEndedReason ?? '-'} deadline=${row.inviteAcceptDeadlineMs ? new Date(row.inviteAcceptDeadlineMs + K).toISOString().slice(5, 16) : '없음'} readiness=${row.inviteAcceptReadiness}`;
  const projRows = [];
  for (const [id, name, o, expect] of [
    ['PJ-1', '마감 전(열림)', {}, {cap: 'available', intake: false, deadline: true}],
    ['PJ-2', '공개 접수 자동 마감 후', {to: AUTO_TO, slotArgs: {slot: AUTO_SLOT, wd: Object.assign({closedAt: Timestamp.now()}, AUTO_WD)}}, {cap: 'available', intake: true, deadline: true}],
    ['PJ-3', '수동 마감', {slotArgs: {slot: {status: 'closed', isManualClosed: true, closedBy: 'o'}}}, {cap: 'closed', ended: 'RECRUIT_ENDED', deadline: false}],
    ['PJ-4', '관리자 앱 모양 사유 없는 CLOSED(DEV 3건 모양)', {to: {status: 'CLOSED'}}, {cap: 'closed', ended: 'RECRUIT_ENDED', deadline: false}],
    ['PJ-5', '공고 삭제(soft)', {to: {isDeleted: true}}, {cap: 'closed', ended: 'POSTING_DELETED', deadline: false}],
    ['PJ-6', '공고 FULL 이지만 이 단위 자리 있음', {to: {status: 'FULL'}}, {cap: 'available', deadline: true}],
    ['PJ-7', '이 단위 정원 소진(자동 마감 후)', {conf: 2, to: AUTO_TO, slotArgs: {slot: AUTO_SLOT, wd: Object.assign({closedAt: Timestamp.now()}, AUTO_WD)}}, {cap: 'full', intake: true, deadline: true}],
    ['PJ-8', '서류 검토 대기(자동판정 없음·검토 없음)', {worker: {idCardMatchStatus: null}}, {cap: 'available', readiness: 'REVIEW_PENDING'}],
  ]) {
    await cell(id, name, async () => {
      const {row} = await projection(o);
      assert.strictEqual(row.workInstanceCapacityState, expect.cap);
      if ('intake' in expect) assert.strictEqual(row.publicIntakeClosed, expect.intake);
      if ('ended' in expect) assert.strictEqual(row.inviteEndedReason, expect.ended);
      if ('deadline' in expect) assert.strictEqual(row.inviteAcceptDeadlineMs != null, expect.deadline);
      if ('readiness' in expect) assert.strictEqual(row.inviteAcceptReadiness, expect.readiness);
      projRows.push(`${id} ${show(row)}`);
      return show(row);
    });
  }
  // 투영 ↔ 수락 tx 역검증: 투영이 available(+READY)이면 실제 수락이 되고, closed 면 거절된다.
  await cell('PJ-X', '투영과 수락 결과가 같다(자동 마감 → 수락됨 / 수동 마감 → 거절)', async () => {
    const auto = await projection({to: AUTO_TO, slotArgs: {slot: AUTO_SLOT, wd: Object.assign({closedAt: Timestamp.now()}, AUTO_WD)}});
    const manual = await projection({slotArgs: {slot: {status: 'closed', isManualClosed: true, closedBy: 'o'}}});
    const ra = await tryAccept(auto.w, auto.a); const rm = await tryAccept(manual.w, manual.a);
    assert.strictEqual(ra, 'OK'); assert.ok(rm.startsWith('ERR:'));
    return `auto→${ra} · manual→${rm}`;
  });
  await cell('PJ-T', '근무 시작 정각: 수락 기한 = 시작 시각, 그 시각 이후 수락 거절', async () => {
    // 오늘 지금 -1분 시작 → 이미 시작(정각 경과). 기한은 시작 시각과 같다.
    const startMs = NOW - 60e3; const today = kstMidnight(startMs);
    if (today !== kstMidnight(NOW)) return 'SKIP(자정 경계)';
    const p = await projection({day: today, slotArgs: {start: hhmm(startMs), end: '23:59', day: today}, exp: NOW + 3600e3});
    const r = await tryAccept(p.w, p.a);
    assert.ok(r.includes('근무가 이미 시작'), r);
    return `deadline=${new Date(p.row.inviteAcceptDeadlineMs + K).toISOString().slice(11, 16)} · 수락 ${r.replace('ERR:', '거절 ')}`;
  });

  // ── C. 관리자 날짜별 명단 row ───────────────────────────────────────────
  await cell('DS-1', '날짜별 row: 자동 마감 → isClosed=true · inviteEnded=false / 수동 → true·true', async () => {
    const {biz, owner} = await seedBusiness();
    const to = uid('t');
    await db.doc(`tos/${to}`).set({businessId: biz, status: 'ACTIVE', type: 'flex', isPublished: true, title: 't', totalRequired: 4});
    await seedSlot(to, {day: D2, slot: AUTO_SLOT, wd: Object.assign({closedAt: Timestamp.now()}, AUTO_WD)});
    await seedSlot(to, {day: D2, wdId: 'wd2', start: '16:00', end: '17:00', slot: {status: 'closed', isManualClosed: true, closedBy: owner}});
    const r = await fn.callableGetDayStaffingDetail.run({auth: {uid: owner, token: {}}, rawRequest: {headers: {}}, data: {businessId: biz, dateMs: D2}});
    const rows2 = (r.rows || []).filter((x) => x.toId === to).map((x) => `${x.wdId}:closed=${x.isClosed},inviteEnded=${x.inviteEnded}`);
    assert.deepStrictEqual(rows2.sort(), ['wd1:closed=true,inviteEnded=false', 'wd2:closed=true,inviteEnded=true']);
    return rows2.join(' · ');
  });

  // ── D. 마감 canonical writer — callableUpdateTO({status: CLOSED}) ───────
  async function closeReq(owner, to, updates = {status: 'CLOSED'}) {
    try {
      const r = await fn.callableUpdateTO.run({auth: {uid: owner, token: {}}, rawRequest: {headers: {}}, data: {toId: to, updates, expectedEditRevision: 0}});
      return 'OK ' + JSON.stringify(r);
    } catch (e) { return 'ERR:' + e.message; }
  }
  const toShape = async (to) => { const t = await read(`tos/${to}`); return `${t.status}/${t.closedReason ?? '사유없음'}/${t.closedAt ? 'closedAt' : '-'}/${t.closedBy ? 'closedBy' : '-'}`; };
  await cell('CW-1', '앱이 먼저(슬롯 아직 열림) → 쓰지 않음 · 스케줄러가 닫은 뒤 다시 → ALL_SLOTS_EXPIRED', async () => {
    const {biz, owner} = await seedBusiness(); const to = uid('t');
    await db.doc(`tos/${to}`).set({businessId: biz, status: 'ACTIVE', type: 'flex', isPublished: true, title: 't', totalRequired: 2, editRevision: 0});
    const s = await seedSlot(to, {day: D2});
    const r1 = await closeReq(owner, to); const after1 = await toShape(to);
    assert.strictEqual(after1.split('/')[0], 'ACTIVE');
    await db.doc(`tos/${to}/slots/${s}`).update(AUTO_SLOT); // 스케줄러가 슬롯을 닫음
    const r2 = await closeReq(owner, to); const after2 = await toShape(to);
    assert.strictEqual(after2, 'CLOSED/ALL_SLOTS_EXPIRED/closedAt/-');
    return `1차 ${r1} ⇒ ${after1} · 2차 ⇒ ${after2}`;
  });
  await cell('CW-2', '스케줄러가 먼저 닫음 → 앱 요청은 아무것도 바꾸지 않음', async () => {
    const {biz, owner} = await seedBusiness(); const to = uid('t');
    await db.doc(`tos/${to}`).set({businessId: biz, status: 'CLOSED', closedReason: 'ALL_SLOTS_EXPIRED', closedAt: Timestamp.now(), type: 'flex', title: 't', editRevision: 0});
    await seedSlot(to, {day: D2, slot: AUTO_SLOT});
    const before = await toShape(to); const r = await closeReq(owner, to); const after = await toShape(to);
    assert.strictEqual(after, before);
    return `${r} ⇒ ${after}`;
  });
  await cell('CW-3', '수동 마감과 경합 — 수동 마감이 있으면 자동 사유로 덮지 않음', async () => {
    const {biz, owner} = await seedBusiness(); const to = uid('t');
    await db.doc(`tos/${to}`).set({businessId: biz, status: 'ACTIVE', isManualClosed: true, closedBy: owner, type: 'flex', title: 't', editRevision: 0});
    await seedSlot(to, {day: D2, slot: {status: 'closed', isManualClosed: true, closedBy: owner}});
    const r = await closeReq(owner, to); const after = await toShape(to);
    assert.strictEqual(after.split('/')[0], 'ACTIVE');
    return `${r} ⇒ ${after}`;
  });
  await cell('CW-4', '마감을 다른 수정과 함께 보내면 거부, closedReason 주입은 무시', async () => {
    const {biz, owner} = await seedBusiness(); const to = uid('t');
    await db.doc(`tos/${to}`).set({businessId: biz, status: 'ACTIVE', type: 'flex', title: 't', editRevision: 0});
    await seedSlot(to, {day: D2, slot: AUTO_SLOT});
    const r1 = await closeReq(owner, to, {status: 'CLOSED', closedReason: 'ALL_SLOTS_EXPIRED'});
    assert.ok(r1.startsWith('ERR:'), r1);
    const r2 = await closeReq(owner, to, {title: 't2', closedReason: 'ALL_SLOTS_EXPIRED'});
    const t = await read(`tos/${to}`);
    assert.strictEqual(t.closedReason, undefined, '클라이언트 closedReason 이 저장됐다');
    return `혼합 ${r1.slice(0, 40)} · 주입 ${r2.slice(0, 30)} ⇒ closedReason ${t.closedReason ?? '없음'}`;
  });

  // ── E. 직접 삭제가 남기는 것(Admin SDK 로 rules 를 지나지 않고 재현) ────────
  await cell('DEL-1', '공고 하드 삭제 → onTODeleted 가 INVITED·PENDING·CONFIRMED 지원서를 지운다(우회 경로의 결과)', async () => {
    const {biz, owner} = await seedBusiness(); const to = uid('t');
    const toDoc = {businessId: biz, status: 'ACTIVE', type: 'flex', title: 't'};
    await db.doc(`tos/${to}`).set(toDoc);
    const s = await seedSlot(to, {day: D2});
    const w = await seedWorker();
    const ids = [];
    for (const st of ['INVITED', 'PENDING', 'CONFIRMED']) ids.push(await seedInvite({biz, owner, w, to, slot: s, day: D2, extra: {status: st}}));
    await db.doc(`tos/${to}`).delete();
    await fn.onTODeleted.run({params: {toId: to}, data: {exists: true, data: () => toDoc}});
    const left = await Promise.all(ids.map((i) => db.doc(`applications/${i}`).get()));
    return `지원서 ${left.filter((x) => x.exists).length}/3 남음`;
  });
  await cell('DEL-2', '슬롯 하드 삭제 → 초대는 남고 수락은 fail-closed, 목록은 UNKNOWN, 공고 대기 집계는 그대로', async () => {
    const p = await projection({});
    const before = (await read(`tos/${p.to}`)).totalPending;
    await db.doc(`tos/${p.to}/slots/${p.s}`).delete();
    const r = await tryAccept(p.w, p.a);
    const g = await fn.callableGetMyApplications.run({auth: {uid: p.w, token: {}}, rawRequest: {headers: {}}, data: {}});
    const row = (g.applications || []).find((x) => x.id === p.a) || {};
    assert.ok(r.startsWith('ERR:'));
    return `수락 ${r.replace('ERR:', '거절 ')} · 목록 ${row.workInstanceCapacityState} · 지원서 ${(await read(`applications/${p.a}`)).status} · TO 대기 ${before}→${(await read(`tos/${p.to}`)).totalPending}`;
  });

  await cell('DEL-3', '공식 삭제(callableDeleteTO): 관계 0 → soft delete(생성 실패 롤백 경로) / INVITED 1건 → 거부', async () => {
    const {biz, owner} = await seedBusiness();
    const t0 = uid('t');
    await db.doc(`tos/${t0}`).set({businessId: biz, status: 'SCHEDULED', type: 'flex', isPublished: false, publishMode: 'deferred', title: 't'});
    await seedSlot(t0, {day: D2});
    const r0 = await fn.callableDeleteTO.run({auth: {uid: owner, token: {}}, rawRequest: {headers: {}}, data: {toId: t0}});
    const d0 = await read(`tos/${t0}`);
    assert.strictEqual(d0.isDeleted, true);
    const p = await projection({});
    let r1;
    try { await fn.callableDeleteTO.run({auth: {uid: p.owner, token: {}}, rawRequest: {headers: {}}, data: {toId: p.to}}); r1 = '삭제됨'; } catch (e) { r1 = '거부 ' + e.message; }
    assert.ok(r1.startsWith('거부'));
    return `관계 0 → ${JSON.stringify(r0).slice(0, 30)} isDeleted=${d0.isDeleted} · INVITED → ${r1} · 지원서 ${(await read(`applications/${p.a}`)).status}`;
  });
  await cell('DEL-4', '공식 슬롯 삭제(callableDeleteSlots): INVITED 가 있으면 거부', async () => {
    const p = await projection({});
    let r;
    try { await fn.callableDeleteSlots.run({auth: {uid: p.owner, token: {}}, rawRequest: {headers: {}}, data: {toId: p.to, businessId: p.biz, slotIds: [p.s]}}); r = '삭제됨'; } catch (e) { r = '거부 ' + e.message; }
    assert.ok(r.startsWith('거부'), r);
    return r;
  });

  for (const r of rows) log(r);
  log(`\n통과 ${pass} / 실패 ${fails.length}`);
  log(`바깥 트래픽 시도: ${outbound.length ? [...new Set(outbound)].join(', ') : '0'}`);
  process.exit(fails.length ? 1 : 0);
})().catch((e) => { log('ERR ' + e.stack); process.exit(2); });
