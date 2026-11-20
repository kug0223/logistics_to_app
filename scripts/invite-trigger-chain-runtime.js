/**
 * [INVITE-TERMINAL] **실제 트리거 연쇄** — Functions 에뮬레이터가 트리거를 스스로 실행한다.
 *
 *   이 스크립트는 번들을 require 하지 않는다. Firestore 에뮬레이터에 **writer 가 쓰는 것과
 *   같은 문서 변경**을 쓰고, 에뮬레이터의 onTOStatusChanged·onSlotInviteUnitEnded·
 *   onBusinessDeactivated·syncTOStats 가 연쇄로 만든 결과를 경계 있는 대기로 읽는다.
 *   (invite-terminal-runtime.js 는 트리거 본문을 직접 호출한다 — 증거 수준이 다르다.)
 *
 *   실행(격리 CLI 15.31.0 + scripts/r7-audit 패치, demo 프로젝트):
 *     npm --prefix functions run build
 *     FUNCTIONS_DISCOVERY_TIMEOUT=300 <격리CLI>/firebase emulators:start --only functions,firestore \
 *       --project demo-alfit-r7 --config firebase.r7audit.json
 *     node scripts/invite-trigger-chain-runtime.js
 *   외부 부작용: functions/.env.demo-alfit-r7 이 실자격증명을 덮고 ADC 가 없다 — FCM 등은 인증 실패.
 */
'use strict';
const path = require('path');
const assert = require('assert');
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:6070';
process.env.GCLOUD_PROJECT = 'demo-alfit-r7';
const admin = require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin'));
if (!admin.apps.length) admin.initializeApp({projectId: 'demo-alfit-r7'});
const db = admin.firestore();
const {Timestamp, FieldValue} = admin.firestore;

const RUN = 'tc' + Date.now().toString(36);
const K = 9 * 3600e3;
const NOW = Date.now();
const kstMidnight = (ms) => { const d = new Date(ms + K); return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()) - K; };
const D2 = kstMidnight(NOW + 2 * 86400e3);
let seq = 0;
const uid = (p) => `${p}-${RUN}-${++seq}`;
const read = async (p) => (await db.doc(p).get()).data();
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
/** 조건이 맞을 때까지(최대 timeout) 기다린다 — 고정 sleep 으로 판정하지 않는다. */
async function until(fn, timeout = 30000) {
  const t0 = Date.now(); let last;
  while (Date.now() - t0 < timeout) { last = await fn(); if (last.ok) return last; await sleep(400); }
  return Object.assign({timedOut: true}, last);
}
/** 연쇄가 가라앉을 때까지(문서 updateTime 이 quietMs 동안 안 바뀜) 기다린다. */
async function settle(paths, quietMs = 3000, timeout = 30000) {
  const t0 = Date.now(); let prev = ''; let stableSince = Date.now();
  while (Date.now() - t0 < timeout) {
    const snaps = await Promise.all(paths.map((p) => db.doc(p).get()));
    const key = snaps.map((s) => s.exists ? s.updateTime.toMillis() : 0).join(',');
    if (key !== prev) { prev = key; stableSince = Date.now(); } else if (Date.now() - stableSince >= quietMs) return true;
    await sleep(300);
  }
  return false;
}

async function world(o = {}) {
  const biz = uid('b'); const owner = uid('o'); const to = uid('t'); const s = uid('s');
  await db.doc(`users/${owner}`).set({role: 'BUSINESS_ADMIN', businessId: biz});
  await db.doc(`businesses/${biz}`).set({isApproved: true, ownerId: owner, adminIds: [owner], name: 'biz'});
  await db.doc(`tos/${to}`).set(Object.assign({businessId: biz, status: 'ACTIVE', type: 'flex', isPublished: true,
    title: '연쇄 공고', totalRequired: 2, totalConfirmed: 0, totalPending: 0}, o.to || {}));
  const wds = [{wdId: 'wd1', workType: 'QA', startTime: '14:00', endTime: '15:00', requiredCount: 2}];
  if (o.twoWd) wds.push({wdId: 'wd2', workType: 'QB', startTime: '16:00', endTime: '17:00', requiredCount: 1});
  await db.doc(`tos/${to}/slots/${s}`).set({date: Timestamp.fromMillis(D2), status: 'open', workDetails: wds,
    confirmedCount: 0, pendingCount: 0, workDetailCounts: Object.fromEntries(wds.map((w) => [w.wdId, {confirmedCount: 0, pendingCount: 0}]))});
  const apps = [];
  for (const [wdId, status] of (o.apps || [['wd1', 'INVITED']])) {
    const w = uid('w'); const a = uid('a');
    await db.doc(`users/${w}`).set({role: 'USER', name: 'worker', accountStatus: 'active'});
    await db.doc(`applications/${a}`).set({status, uid: w, businessId: biz, toId: to, slotId: s, wdId,
      selectedWorkType: wdId === 'wd1' ? 'QA' : 'QB', startTime: wdId === 'wd1' ? '14:00' : '16:00', endTime: wdId === 'wd1' ? '15:00' : '17:00',
      workDate: Timestamp.fromMillis(D2), type: 'short', toTitle: '연쇄 공고', invitedBy: owner, invitedAt: Timestamp.now(),
      inviteExpiresAt: Timestamp.fromMillis(NOW + 3600e3),
      ...(status === 'CONFIRMED' ? {confirmedAt: Timestamp.now()} : {})});
    apps.push({a, w, wdId});
  }
  // 초대가 만든 대기 집계(트리거가 다시 센다) — 연쇄가 0 으로 내려가는지 본다
  await db.doc(`tos/${to}/slots/${s}`).update(Object.fromEntries((o.apps || [['wd1', 'INVITED']])
    .filter(([, st]) => st === 'INVITED').map(([wd]) => [`workDetailCounts.${wd}.pendingCount`, FieldValue.increment(1)])));
  await settle([`tos/${to}`, `tos/${to}/slots/${s}`]);
  return {biz, owner, to, s, apps};
}
const appState = async (a) => {
  const d = await read(`applications/${a}`);
  const hist = (d.statusHistory || []).filter((h) => h.action === 'INVITE_WITHDRAWN_BY_CLOSURE').length;
  return {status: d.status, reason: d.cancelReason ?? null, by: d.canceledBy ?? null, hist};
};
const counters = async (x) => {
  const [t, s] = await Promise.all([read(`tos/${x.to}`), read(`tos/${x.to}/slots/${x.s}`)]);
  return {toPend: t.totalPending, slotPend: s.pendingCount, wd1: s.workDetailCounts.wd1.pendingCount,
    wd2: s.workDetailCounts.wd2?.pendingCount, toStatus: t.status};
};
const notes = async (u, type) => (await db.collection(`users/${u}/notifications`).get()).docs
  .filter((d) => !type || d.data().type === type).length;

let pass = 0; const fails = []; const rows = [];
async function cell(id, name, f) {
  try { const note = await f(); pass++; rows.push(`  ok   ${id} ${name}${note ? ' — ' + note : ''}`); } catch (e) {
    fails.push(id); rows.push(`  FAIL ${id} ${name} — ${String(e.message).split('\n')[0]}`);
  }
}

(async () => {
  console.log(`[RUN ${RUN}] 실제 트리거 연쇄(Functions 에뮬레이터)`);
  await cell('CH-1', '공고 수동 마감 쓰기 → onTOStatusChanged → 철회 → syncTOStats 재집계 → 알림 1건', async () => {
    const x = await world();
    await db.doc(`tos/${x.to}`).update({status: 'CLOSED', isManualClosed: true, closedBy: x.owner, closedAt: Timestamp.now()});
    // 첫 트리거는 에뮬레이터가 번들을 처음 올리는 냉시작이라 오래 걸린다.
    const r = await until(async () => { const s = await appState(x.apps[0].a); return {ok: s.status === 'CANCELED', s}; }, 90000);
    assert.ok(!r.timedOut, '철회가 일어나지 않았다');
    await settle([`applications/${x.apps[0].a}`, `tos/${x.to}`, `tos/${x.to}/slots/${x.s}`]);
    const s = await appState(x.apps[0].a); const c = await counters(x); const n = await notes(x.apps[0].w, 'toInviteCanceled');
    assert.deepStrictEqual([s.reason, s.by, s.hist], ['RECRUIT_CLOSED', x.owner, 1]);
    assert.deepStrictEqual([c.wd1, c.slotPend, c.toPend], [0, 0, 0]);
    assert.strictEqual(n, 1);
    return `CANCELED/${s.reason} · 이력 ${s.hist} · 업무·슬롯·공고 대기 ${c.wd1}/${c.slotPend}/${c.toPend} · 알림 ${n}`;
  });
  await cell('CH-2', '중복 실행: 마감 직후 공고를 다시 두 번 수정 → 철회·이력·대기 감소가 한 번뿐', async () => {
    const x = await world();
    await db.doc(`tos/${x.to}`).update({status: 'CLOSED', isManualClosed: true, closedBy: x.owner, closedAt: Timestamp.now()});
    await db.doc(`tos/${x.to}`).update({title: '수정 1'});
    await db.doc(`tos/${x.to}`).update({title: '수정 2'});
    await until(async () => ({ok: (await appState(x.apps[0].a)).status === 'CANCELED'}));
    await settle([`applications/${x.apps[0].a}`, `tos/${x.to}`, `tos/${x.to}/slots/${x.s}`]);
    const s = await appState(x.apps[0].a); const c = await counters(x); const n = await notes(x.apps[0].w, 'toInviteCanceled');
    assert.deepStrictEqual([s.hist, c.wd1, n], [1, 0, 1]);
    return `이력 ${s.hist} · 업무 대기 ${c.wd1}(음수 아님) · 알림 ${n}`;
  });
  await cell('CH-3', '순서·경합: 날짜 수동 마감과 공고 수동 마감을 거의 동시에 → 두 트리거가 같은 초대를 보지만 한 번만 철회', async () => {
    const x = await world();
    await Promise.all([
      db.doc(`tos/${x.to}/slots/${x.s}`).update({status: 'closed', isManualClosed: true, closedBy: x.owner, closedAt: Timestamp.now()}),
      db.doc(`tos/${x.to}`).update({status: 'CLOSED', isManualClosed: true, closedBy: x.owner, closedAt: Timestamp.now()}),
    ]);
    await until(async () => ({ok: (await appState(x.apps[0].a)).status === 'CANCELED'}));
    await settle([`applications/${x.apps[0].a}`, `tos/${x.to}`, `tos/${x.to}/slots/${x.s}`]);
    const s = await appState(x.apps[0].a); const c = await counters(x); const n = await notes(x.apps[0].w, 'toInviteCanceled');
    assert.deepStrictEqual([s.hist, c.wd1, n], [1, 0, 1]);
    return `이력 ${s.hist} · 업무 대기 ${c.wd1} · 알림 ${n}`;
  });
  await cell('CH-4', '업무 단위 수동 마감(앱이 슬롯 직접 수정) → onSlotInviteUnitEnded → 그 업무 초대만', async () => {
    const x = await world({twoWd: true, apps: [['wd1', 'INVITED'], ['wd2', 'INVITED']]});
    const slot = await read(`tos/${x.to}/slots/${x.s}`);
    const wds = slot.workDetails.map((w) => w.wdId === 'wd1' ? Object.assign({}, w, {isManualClosed: true, closedBy: x.owner, closedAt: Timestamp.now()}) : w);
    await db.doc(`tos/${x.to}/slots/${x.s}`).update({workDetails: wds});
    await until(async () => ({ok: (await appState(x.apps[0].a)).status === 'CANCELED'}));
    await settle([`applications/${x.apps[0].a}`, `applications/${x.apps[1].a}`, `tos/${x.to}/slots/${x.s}`]);
    const s1 = await appState(x.apps[0].a); const s2 = await appState(x.apps[1].a); const c = await counters(x);
    assert.deepStrictEqual([s1.status, s2.status, c.wd1, c.wd2], ['CANCELED', 'INVITED', 0, 1]);
    return `wd1 ${s1.status} · wd2 ${s2.status} · 업무 대기 wd1 ${c.wd1} / wd2 ${c.wd2}`;
  });
  await cell('CH-5', '재오픈 경합: 마감 직후 곧바로 재오픈 → 트리거가 늦게 읽으면 철회 안 함(관측)', async () => {
    const x = await world();
    await db.doc(`tos/${x.to}`).update({status: 'CLOSED', isManualClosed: true, closedBy: x.owner, closedAt: Timestamp.now()});
    await db.doc(`tos/${x.to}`).update({status: 'ACTIVE', isManualClosed: false, closedBy: FieldValue.delete(), closedAt: FieldValue.delete()});
    await settle([`applications/${x.apps[0].a}`, `tos/${x.to}`, `tos/${x.to}/slots/${x.s}`], 4000);
    const s = await appState(x.apps[0].a); const c = await counters(x);
    // 어느 쪽이든 원장과 집계가 서로 맞아야 한다(철회됐으면 대기 0, 아니면 1)
    assert.ok((s.status === 'INVITED' && c.wd1 === 1) || (s.status === 'CANCELED' && c.wd1 === 0), JSON.stringify([s, c]));
    return `관측: ${s.status} · 업무 대기 ${c.wd1} (원장·집계 일치)`;
  });
  await cell('CH-6', '자동 접수 마감(슬롯 TIME_EXPIRED · 공고 ALL_SLOTS_EXPIRED) → 연쇄가 철회하지 않는다', async () => {
    const x = await world();
    await db.doc(`tos/${x.to}/slots/${x.s}`).update({status: 'closed', closedReason: 'TIME_EXPIRED', closedAt: Timestamp.now()});
    await db.doc(`tos/${x.to}`).update({status: 'CLOSED', closedReason: 'ALL_SLOTS_EXPIRED', closedAt: Timestamp.now()});
    await settle([`applications/${x.apps[0].a}`, `tos/${x.to}`, `tos/${x.to}/slots/${x.s}`], 4000);
    const s = await appState(x.apps[0].a); const c = await counters(x);
    assert.deepStrictEqual([s.status, c.wd1], ['INVITED', 1]);
    return `${s.status} · 업무 대기 ${c.wd1}`;
  });
  await cell('CH-7', '사업장 비활성(archive 와 같은 쓰기) → onBusinessDeactivated → 공고 CLOSED·초대 철회·확정 취소+알림, 연쇄 중복 없음', async () => {
    const x = await world({apps: [['wd1', 'INVITED'], ['wd1', 'CONFIRMED']]});
    await db.doc(`businesses/${x.biz}`).update({isApproved: false, deactivatedAt: Timestamp.now(), deactivatedBy: x.owner,
      archivedAt: Timestamp.now(), archivedBy: x.owner, archiveReason: 'OWNER_CLOSED'});
    await until(async () => {
      const [i, c] = await Promise.all([appState(x.apps[0].a), appState(x.apps[1].a)]);
      return {ok: i.status === 'CANCELED' && c.status === 'CANCELED'};
    }, 45000);
    await settle([`applications/${x.apps[0].a}`, `applications/${x.apps[1].a}`, `tos/${x.to}`, `tos/${x.to}/slots/${x.s}`], 4000, 45000);
    const inv = await appState(x.apps[0].a); const conf = await read(`applications/${x.apps[1].a}`);
    const t = await read(`tos/${x.to}`); const c = await counters(x);
    const nInv = await notes(x.apps[0].w, 'toInviteCanceled'); const nConf = await notes(x.apps[1].w, 'confirmationCanceled');
    assert.deepStrictEqual([t.status, t.closedReason], ['CLOSED', 'BUSINESS_DEACTIVATED']);
    assert.deepStrictEqual([inv.status, inv.reason, inv.hist], ['CANCELED', 'BUSINESS_DEACTIVATED', 1]);
    assert.deepStrictEqual([conf.status, conf.cancelReason], ['CANCELED', 'BUSINESS_DEACTIVATED']);
    assert.deepStrictEqual([nInv, nConf, c.wd1], [1, 1, 0]);
    return `공고 ${t.status}/${t.closedReason} · 초대 ${inv.status}(이력 ${inv.hist}) · 확정 ${conf.status} · 알림 초대 ${nInv}/확정 ${nConf} · 업무 대기 ${c.wd1}`;
  });

  for (const r of rows) console.log(r);
  console.log(`\n통과 ${pass} / 실패 ${fails.length}`);
  process.exit(fails.length ? 1 : 0);
})().catch((e) => { console.log('ERR ' + e.stack); process.exit(2); });
