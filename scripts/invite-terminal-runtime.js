/**
 * [INVITE-TERMINAL] 런타임 계약 — 효력이 끝난 초대의 원장·대기 인원, 공개 지원 마감 후 새 초대,
 * 재오픈, 조회 실패, 스케줄러 재실행. 번들(functions/lib/index.js)의 실제 callable·트리거·스케줄러
 * 본문을 격리 Firestore 에뮬레이터(demo-alfit-r7, 127.0.0.1:6070)에서 실행한다.
 *
 *   실행: firebase emulators:start --only firestore --project demo-alfit-r7 --config firebase.r7audit.json
 *         npm --prefix functions run build && node scripts/invite-terminal-runtime.js
 *   트리거(onTOStatusChanged·onSlotInviteUnitEnded·onBusinessDeactivated·syncTOStats)는 이 스크립트가
 *   같은 이벤트 모양으로 **직접** 호출한다 — 실제 트리거 연쇄가 아니다. masterScheduler 는 .run() 으로
 *   실제 본문 전체를 돈다. 격리·범위 밖 항목은 invite-closure-runtime.js 머리말과 같다.
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
// 사업자등록증 확인(예약 공개의 준비 조건)이 Storage 를 보므로 Storage 에뮬레이터도 쓴다.
process.env.FIREBASE_STORAGE_EMULATOR_HOST = '127.0.0.1:6071';
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

const RUN = 'it' + Date.now().toString(36);
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


const snapOf = (d) => ({exists: d != null, data: () => d});
const runToTrigger = (toId, before, after) =>
  fn.onTOStatusChanged.run({params: {toId}, data: {before: snapOf(before), after: snapOf(after)}});
const runSlotTrigger = (toId, slotId, before, after) =>
  fn.onSlotInviteUnitEnded.run({params: {toId, slotId}, data: {before: snapOf(before), after: snapOf(after)}});
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
const notesOf = async (u) => (await db.collection(`users/${u}/notifications`).get()).docs.map((d) => d.data());

/** 공고 1 · 슬롯 1(업무 wd1, 필요 2) · 초대 1 — 대기 집계는 초대가 만든 모양 그대로. */
async function world(o = {}) {
  const {biz, owner} = await seedBusiness();
  const to = uid('t');
  await db.doc(`tos/${to}`).set(Object.assign({businessId: biz, status: 'ACTIVE', type: 'flex', isPublished: true,
    title: '테스트 공고', totalRequired: 2, totalConfirmed: 0, totalPending: 1, editRevision: 0}, o.to || {}));
  const s = await seedSlot(to, Object.assign({day: D2, req: 2, conf: 0, pend: 1}, o.slotArgs || {}));
  const w = await seedWorker();
  const a = await seedInvite({biz, owner, w, to, slot: s, day: D2, extra: {toTitle: '테스트 공고'}});
  return {biz, owner, to, s, w, a};
}
const ledger = async (x) => {
  const [app, slot, t] = await Promise.all([read(`applications/${x.a}`), read(`tos/${x.to}/slots/${x.s}`), read(`tos/${x.to}`)]);
  return {status: app.status, reason: app.cancelReason ?? null, by: app.canceledBy ?? null,
    wdPend: slot.workDetailCounts.wd1.pendingCount, slotPend: slot.pendingCount, toPend: t.totalPending, toStatus: t.status};
};
const fmt = (l) => `지원서 ${l.status}${l.reason ? '/' + l.reason : ''} · 업무 대기 ${l.wdPend} · 슬롯 대기 ${l.slotPend} · 공고 대기 ${l.toPend}`;

(async () => {
  log(`[RUN ${RUN}] 번들 ${BUNDLE.replace(/\\/g, '/').split('/').slice(-4).join('/')}`);

  // ── 1. 효력이 끝난 초대의 원장·대기 인원 ─────────────────────────────────
  await cell('TW-1', '공고 수동 마감 → 트리거가 CANCELED/RECRUIT_CLOSED(마감한 관리자) + 업무 대기 -1, syncTOStats 후 슬롯·공고 대기 0', async () => {
    const x = await world();
    const before = await read(`tos/${x.to}`);
    await fn.callableCloseTOManually.run({auth: {uid: x.owner, token: {}}, rawRequest: {headers: {}}, data: {toId: x.to}});
    const after = await read(`tos/${x.to}`);
    await runToTrigger(x.to, before, after);
    const l1 = await ledger(x);
    await runSyncTOStats(x.a, {status: 'INVITED'}, await read(`applications/${x.a}`));
    const l2 = await ledger(x);
    await wait(300);
    const notes = await notesOf(x.w);
    assert.deepStrictEqual([l1.status, l1.reason, l1.by, l1.wdPend], ['CANCELED', 'RECRUIT_CLOSED', x.owner, 0]);
    assert.deepStrictEqual([l2.slotPend, l2.toPend], [0, 0]);
    assert.ok(notes.some((n) => n.type === 'toInviteCanceled' && /모집을 마감/.test(n.body)), '근로자 알림');
    // 재실행 멱등
    await runToTrigger(x.to, before, after);
    const l3 = await ledger(x);
    assert.deepStrictEqual(l3, l2);
    return `직후 ${fmt(l1)} → 재집계 ${fmt(l2)} · 알림 ${notes.length} · 재실행 불변`;
  });
  await cell('TW-2', '날짜 수동 마감(callableCloseSlots) → 슬롯 트리거가 철회', async () => {
    const x = await world();
    const before = await read(`tos/${x.to}/slots/${x.s}`);
    await fn.callableCloseSlots.run({auth: {uid: x.owner, token: {}}, rawRequest: {headers: {}}, data: {toId: x.to, businessId: x.biz, slotIds: [x.s]}});
    await runSlotTrigger(x.to, x.s, before, await read(`tos/${x.to}/slots/${x.s}`));
    const l = await ledger(x);
    assert.deepStrictEqual([l.status, l.reason, l.by, l.wdPend], ['CANCELED', 'RECRUIT_CLOSED', x.owner, 0]);
    return fmt(l);
  });
  await cell('TW-3', '업무 수동 마감(앱이 슬롯 문서 직접 수정) → 그 업무 초대만 철회', async () => {
    const x = await world();
    // 같은 슬롯에 다른 업무와 그 초대
    const slotPath = `tos/${x.to}/slots/${x.s}`;
    const s0 = await read(slotPath);
    s0.workDetails.push({wdId: 'wd2', workType: 'QB', startTime: '16:00', endTime: '17:00', requiredCount: 1});
    s0.workDetailCounts.wd2 = {confirmedCount: 0, pendingCount: 1};
    await db.doc(slotPath).set(s0);
    const w2 = await seedWorker();
    const a2 = await seedInvite({biz: x.biz, owner: x.owner, w: w2, to: x.to, slot: x.s, day: D2, wdId: 'wd2', start: '16:00', end: '17:00'});
    const before = await read(slotPath);
    const after = JSON.parse(JSON.stringify(before));
    after.workDetails[0] = Object.assign({}, before.workDetails[0], {isManualClosed: true, closedBy: x.owner});
    after.workDetails[0].closedAt = Timestamp.now();
    after.date = before.date;
    await db.doc(slotPath).update({workDetails: [Object.assign({}, before.workDetails[0], {isManualClosed: true, closedBy: x.owner, closedAt: Timestamp.now()}), before.workDetails[1]]});
    await runSlotTrigger(x.to, x.s, before, await read(slotPath));
    const st1 = (await read(`applications/${x.a}`)).status; const st2 = (await read(`applications/${a2}`)).status;
    assert.deepStrictEqual([st1, st2], ['CANCELED', 'INVITED']);
    return `wd1 초대 ${st1} · wd2 초대 ${st2}`;
  });
  await cell('TW-4', '사업장 비활성 — 이미 자동 마감된 공고의 유효 초대까지 CANCELED/BUSINESS_DEACTIVATED', async () => {
    const x = await world({to: {status: 'CLOSED', closedReason: 'ALL_SLOTS_EXPIRED', closedAt: Timestamp.now()},
      slotArgs: {slot: AUTO_SLOT, wd: Object.assign({closedAt: Timestamp.now()}, AUTO_WD)}});
    const before = await read(`businesses/${x.biz}`);
    await db.doc(`businesses/${x.biz}`).update({deactivatedAt: Timestamp.now()});
    await fn.onBusinessDeactivated.run({params: {businessId: x.biz}, data: {before: snapOf(before), after: snapOf(await read(`businesses/${x.biz}`))}});
    const l = await ledger(x);
    assert.deepStrictEqual([l.status, l.reason, l.by], ['CANCELED', 'BUSINESS_DEACTIVATED', 'SYSTEM']);
    return fmt(l) + ` · canceledBy ${l.by}`;
  });
  await cell('TW-5', '자동 접수 마감(슬롯 TIME_EXPIRED·공고 ALL_SLOTS_EXPIRED) → 철회하지 않는다', async () => {
    const x = await world();
    const sb = await read(`tos/${x.to}/slots/${x.s}`);
    await db.doc(`tos/${x.to}/slots/${x.s}`).update(Object.assign({}, AUTO_SLOT, {closedAt: Timestamp.now()}));
    await runSlotTrigger(x.to, x.s, sb, await read(`tos/${x.to}/slots/${x.s}`));
    const tb = await read(`tos/${x.to}`);
    await db.doc(`tos/${x.to}`).update({status: 'CLOSED', closedReason: 'ALL_SLOTS_EXPIRED', closedAt: Timestamp.now()});
    await runToTrigger(x.to, tb, await read(`tos/${x.to}`));
    const l = await ledger(x);
    assert.strictEqual(l.status, 'INVITED');
    return fmt(l);
  });
  await cell('TW-6', '정원 소진(FULL)은 철회가 아니다', async () => {
    const x = await world({slotArgs: {conf: 2}});
    const tb = await read(`tos/${x.to}`);
    await db.doc(`tos/${x.to}`).update({status: 'FULL'});
    await runToTrigger(x.to, tb, await read(`tos/${x.to}`));
    assert.strictEqual((await read(`applications/${x.a}`)).status, 'INVITED');
    return 'INVITED 유지';
  });
  await cell('TW-7', '경합: 먼저 수락됐으면 철회 안 함 / 트리거 전에 재오픈됐으면 철회 안 함', async () => {
    const x = await world();
    assert.strictEqual(await tryAccept(x.w, x.a), 'OK');
    const tb = await read(`tos/${x.to}`);
    await fn.callableCloseTOManually.run({auth: {uid: x.owner, token: {}}, rawRequest: {headers: {}}, data: {toId: x.to}});
    await runToTrigger(x.to, tb, await read(`tos/${x.to}`));
    const s1 = (await read(`applications/${x.a}`)).status;
    const y = await world();
    const yb = await read(`tos/${y.to}`);
    await fn.callableCloseTOManually.run({auth: {uid: y.owner, token: {}}, rawRequest: {headers: {}}, data: {toId: y.to}});
    const ya = await read(`tos/${y.to}`);
    await db.doc(`tos/${y.to}`).update({status: 'ACTIVE', isManualClosed: false, closedBy: admin.firestore.FieldValue.delete()}); // 재오픈
    await runToTrigger(y.to, yb, ya); // 늦게 도착한 트리거(낡은 after)
    const s2 = (await read(`applications/${y.a}`)).status;
    assert.deepStrictEqual([s1, s2], ['CONFIRMED', 'INVITED']);
    return `수락 먼저 → ${s1} · 재오픈 먼저 → ${s2}`;
  });

  // ── 3. 공개 지원 마감 후 관리자 새 초대 ───────────────────────────────────
  async function inviteWorld(o) {
    const x = await world(o);
    await db.doc(`applications/${x.a}`).delete(); // 초대 전
    await db.doc(`tos/${x.to}/slots/${x.s}`).update({pendingCount: 0, 'workDetailCounts.wd1.pendingCount': 0});
    await db.doc(`tos/${x.to}`).update({totalPending: 0});
    const day = o.day || D2;
    const dk = new Date(day + K).toISOString().slice(0, 10);
    await db.doc(`worker_availability/${x.w}`).set({inviteEnabled: true, inviteRegionKeys: ['경기도|평택시'], dates: [dk], inviteKeys: [`경기도|평택시#${dk}`]});
    return x;
  }
  const invite = (x, o) => fn.callableInviteWorker.run({auth: {uid: x.owner, token: {}}, rawRequest: {headers: {}}, data: {
    toId: x.to, businessId: x.biz, targetUid: x.w, slotId: x.s, workDate: new Date(o.day || D2).toISOString(),
    selectedWorkType: 'QA', workDetailStartTime: (o.slotArgs || {}).start || '14:00', workDetailEndTime: (o.slotArgs || {}).end || '15:00'}});
  const DL = Timestamp.fromMillis(NOW - 3600e3);
  const today = kstMidnight(NOW); const startedHm = hhmm(NOW - 10 * 60e3);
  for (const [id, name, o, expectOk] of [
    ['NI-1', '슬롯 자동 마감(TIME_EXPIRED)·공고 ALL_SLOTS_EXPIRED · 시작 전 → 발송', {to: AUTO_TO, slotArgs: {slot: AUTO_SLOT, wd: Object.assign({closedAt: Timestamp.now()}, AUTO_WD)}}, true],
    ['NI-2', '공고 applicationDeadline 마감(processTOExpiry 모양) → 발송', {to: {status: 'CLOSED', closedReason: 'TIME_EXPIRED', applicationDeadline: DL, closedAt: Timestamp.now(), isPublished: false},
      slotArgs: {slot: {status: 'closed', closedReason: 'PARENT_TO_EXPIRED'}, wd: {closedAt: Timestamp.now(), closedReason: 'PARENT_TO_CLOSED'}}}, true],
    ['NI-3', '날짜 수동 마감 → 거절', {slotArgs: {slot: {status: 'closed', isManualClosed: true, closedBy: 'x'}}}, false],
    ['NI-4', '사업장 비활성으로 닫힌 공고 → 거절', {to: {status: 'CLOSED', closedReason: 'BUSINESS_DEACTIVATED'}}, false],
    ['NI-5', '사유 없는 CLOSED → 거절', {to: {status: 'CLOSED'}}, false],
    ['NI-6', 'INTEGRITY_CHECK CLOSED → 거절', {to: {status: 'CLOSED', closedReason: 'INTEGRITY_CHECK', applicationDeadline: DL, closedAt: Timestamp.now()}}, false],
    ['NI-7', '자동 마감 + 단위 정원 소진 → 거절', {to: AUTO_TO, slotArgs: {conf: 2, slot: AUTO_SLOT}}, false],
    ['NI-8', `근무 시작 경과(오늘 ${startedHm}) · 자동 마감 → 거절`, {day: today, to: AUTO_TO, slotArgs: {day: today, start: startedHm, end: '23:59', slot: AUTO_SLOT}}, false],
  ]) {
    await cell(id, name, async () => {
      if (id === 'NI-8' && kstMidnight(NOW - 10 * 60e3) !== today) return 'SKIP(자정 경계)';
      const x = await inviteWorld(o);
      const before = await Promise.all([db.collection('applications').where('uid', '==', x.w).get(), read(`tos/${x.to}/slots/${x.s}`)]);
      let r; try { await invite(x, o); r = 'OK'; } catch (e) { r = 'ERR:' + e.message; }
      const apps = await db.collection('applications').where('uid', '==', x.w).get();
      const slot = await read(`tos/${x.to}/slots/${x.s}`);
      if (expectOk) {
        assert.strictEqual(r, 'OK', r);
        assert.strictEqual(apps.docs[0].data().status, 'INVITED');
        assert.strictEqual(slot.workDetailCounts.wd1.pendingCount, 1);
      } else {
        assert.ok(r.startsWith('ERR:'), '발송됐다');
        assert.strictEqual(apps.size, before[0].size, '거절인데 지원서가 생겼다');
        assert.strictEqual(slot.workDetailCounts.wd1.pendingCount, before[1].workDetailCounts.wd1.pendingCount);
      }
      return r === 'OK' ? `발송 · 업무 대기 ${slot.workDetailCounts.wd1.pendingCount}` : `${r.replace('ERR:', '거절 ')} · 쓰기 0`;
    });
  }
  await cell('NI-9', '날짜별 명단 inviteOpen: 자동 마감 → true / 수동 → false / 시작 경과 → false', async () => {
    const out = [];
    for (const [label, o] of [['자동', {to: AUTO_TO, slotArgs: {slot: AUTO_SLOT, wd: Object.assign({closedAt: Timestamp.now()}, AUTO_WD)}}],
      ['수동', {slotArgs: {slot: {status: 'closed', isManualClosed: true, closedBy: 'x'}}}],
      ['시작경과', {day: today, slotArgs: {day: today, start: startedHm, end: '23:59', slot: AUTO_SLOT}}]]) {
      const x = await inviteWorld(o);
      const r = await fn.callableGetDayStaffingDetail.run({auth: {uid: x.owner, token: {}}, rawRequest: {headers: {}}, data: {businessId: x.biz, dateMs: o.day || D2}});
      const row = (r.rows || []).find((y) => y.toId === x.to) || {};
      out.push(`${label}:closed=${row.isClosed},ended=${row.inviteEnded},open=${row.inviteOpen}`);
    }
    assert.ok(out[0].endsWith('closed=true,ended=false,open=true'), out[0]);
    assert.ok(out[1].endsWith('ended=true,open=false'), out[1]);
    if (kstMidnight(NOW - 10 * 60e3) === today) assert.ok(out[2].endsWith('open=false'), out[2]);
    return out.join(' · ');
  });

  // ── 2·4. 재오픈·FULL·조회 실패 ───────────────────────────────────────────
  await cell('RO-1', 'FULL(열린 날 다 참) 공고에서 수동 마감한 미충원 날짜 재오픈 → 성공, 공고 ACTIVE', async () => {
    const {biz, owner} = await seedBusiness();
    const to = uid('t');
    await db.doc(`tos/${to}`).set({businessId: biz, status: 'FULL', type: 'flex', isPublished: true, title: 't', totalRequired: 4, editRevision: 0});
    await seedSlot(to, {day: D3, req: 2, conf: 2});
    const sClosed = await seedSlot(to, {day: D2, req: 2, conf: 0, slot: {status: 'closed', isManualClosed: true, closedBy: owner, closedAt: Timestamp.now()}});
    let r; try { r = await fn.callableReopenSlots.run({auth: {uid: owner, token: {}}, rawRequest: {headers: {}}, data: {toId: to, businessId: biz, slotIds: [sClosed]}}); } catch (e) { r = 'ERR:' + e.message; }
    const t = await read(`tos/${to}`); const s = await read(`tos/${to}/slots/${sClosed}`);
    assert.ok(typeof r === 'object' && r.reopenedCount === 1, JSON.stringify(r));
    assert.strictEqual(s.status, 'open');
    assert.strictEqual(t.status, 'ACTIVE');
    return `재오픈 ${r.reopenedCount} · 슬롯 ${s.status} · 공고 ${t.status}`;
  });
  await cell('GM-1', '근로자 목록: 공고 조회 실패 → UNKNOWN(closed·full·available 로 바꾸지 않음) · 읽기 수', async () => {
    const x = await world({to: AUTO_TO, slotArgs: {slot: AUTO_SLOT}});
    const DocRef = db.doc('a/b').constructor;
    const orig = DocRef.prototype.get;
    let reads = 0; let injected = 0;
    DocRef.prototype.get = function(...a) {
      reads++;
      if (this.path === `tos/${x.to}`) { injected++; return Promise.reject(new Error('injected')); }
      return orig.apply(this, a);
    };
    let row;
    try {
      const g = await fn.callableGetMyApplications.run({auth: {uid: x.w, token: {}}, rawRequest: {headers: {}}, data: {}});
      row = (g.applications || []).find((y) => y.id === x.a) || {};
    } finally { DocRef.prototype.get = orig; }
    assert.strictEqual(row.workInstanceCapacityState, 'unknown');
    assert.strictEqual(row.inviteAcceptDeadlineMs, undefined);
    return `cap=${row.workInstanceCapacityState} · 문서 읽기 ${reads}회(공고 실패 주입 ${injected}) · 재시도 없음(화면의 다시 확인이 재조회)`;
  });

  // ── 5. 스케줄러 재실행 — 철회·유효 초대·삭제된 예약 공고 ──────────────────
  await cell('SC-1', 'masterScheduler 실제 실행 후: 철회 건 CANCELED 유지, 자동 마감 유효 초대 INVITED 유지, 삭제된 예약 공고 미공개', async () => {
    const x = await world();
    const tb = await read(`tos/${x.to}`);
    await fn.callableCloseTOManually.run({auth: {uid: x.owner, token: {}}, rawRequest: {headers: {}}, data: {toId: x.to}});
    await runToTrigger(x.to, tb, await read(`tos/${x.to}`));
    const y = await world({to: AUTO_TO, slotArgs: {slot: AUTO_SLOT, wd: Object.assign({closedAt: Timestamp.now()}, AUTO_WD)}});
    const {biz, owner} = await seedBusiness();
    // 대조 공고가 **실제로 공개되도록** 준비 조건을 채운다 — 사업자등록증 파일(Storage)과
    //   활성 업무. 그래야 삭제된 공고가 공개되지 않은 이유가 isDeleted 검사라고 말할 수 있다.
    const licPath = `businesses/${biz}/license/license.jpg`;
    await admin.storage().bucket().file(licPath).save(Buffer.from('x'));
    await db.doc(`businesses/${biz}`).update({businessLicenseImageUrl:
      `https://firebasestorage.googleapis.com/v0/b/demo-alfit-r7.appspot.com/o/${encodeURIComponent(licPath)}?alt=media`});
    await db.doc(`businesses/${biz}/workTypes/wt1`).set({isActive: true, name: 'QA'});
    const sched = uid('t');
    await db.doc(`tos/${sched}`).set({businessId: biz, status: 'SCHEDULED', type: 'flex', isPublished: false, publishMode: 'scheduled',
      publishAt: Timestamp.fromMillis(NOW - 60e3), title: '삭제된 예약', isDeleted: true, totalRequired: 1});
    const ctl = uid('t');
    await db.doc(`tos/${ctl}`).set({businessId: biz, status: 'SCHEDULED', type: 'flex', isPublished: false, publishMode: 'scheduled',
      publishAt: Timestamp.fromMillis(NOW - 60e3), title: '대조 예약', totalRequired: 1,
      // [CREATE-ROLLBACK 3단계] 대조는 슬롯 생성이 끝난 공고여야 한다(필드 없는 공고는 이제 보류된다).
      totalSlots: 1});
    let err = null;
    try { await fn.masterScheduler.run({}); } catch (e) { err = e.message; }
    const [xa, ya, sd, cd] = await Promise.all([read(`applications/${x.a}`), read(`applications/${y.a}`), read(`tos/${sched}`), read(`tos/${ctl}`)]);
    assert.strictEqual(cd.isPublished, true, '대조 예약 공고가 공개되지 않았다 — 판별력 없음');
    assert.strictEqual(sd.isPublished, false, `삭제된 예약 공고가 공개됐다 (${sd.status}/게시 ${sd.isPublished})`);
    assert.strictEqual(sd.status, 'SCHEDULED');
    assert.strictEqual(xa.status, 'CANCELED');
    assert.strictEqual(ya.status, 'INVITED');
    assert.strictEqual(cd.isPublished, true, '대조 예약 공고가 공개되지 않았다 — 판별력 없음');
    return `철회 ${xa.status} · 유효 ${ya.status} · 삭제 예약 ${sd.status}/게시 ${sd.isPublished} · 대조 예약 ${cd.status}/게시 ${cd.isPublished}${err ? ' · 스케줄러 오류 ' + err.slice(0, 60) : ''}`;
  });

  for (const r of rows) log(r);
  log(`\n통과 ${pass} / 실패 ${fails.length}`);
  log(`바깥 트래픽 시도: ${outbound.length ? [...new Set(outbound)].join(', ') : '0'}`);
  process.exit(fails.length ? 1 : 0);
})().catch((e) => { log('ERR ' + e.stack); process.exit(2); });
