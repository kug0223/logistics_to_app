/**
 * [BUSINESS-ARCHIVE · CREATE-ROLLBACK · INVITE-DECLINE-INTENT] 이번 단계 펜스의 실제 실행 검증.
 *
 *   F-*  운영 종료 사업장의 장기 근무 — 자동 노쇼(06시)·내일 근무 알림(20시)을 쓰지 않는다
 *        (masterScheduler.run, Date.now 를 그 시각으로 고정 — 대조군은 열린 사업장)
 *   L-*  장기 근무의 "시작 전" 판정은 canonical 시작일(desiredStartDate)을 따른다(사전 조회)
 *   W-*  탈퇴 차단: 닫힌 사업장의 미지급(소유자) · 일했지만 계산 전(근로자)
 *   S-*  totalSlots 없는 옛 슬롯 공고: 날짜 목록으로 증명되면 공개, 아니면 보류+이유
 *   D-*  초대 거절: 의도 표시 없는(구 앱) 요청 × 정원 찬/열린 초대
 *   X-*  삭제된 공고의 슬롯은 만료 마감을 쓰지 않는다
 *
 *   실행: functions+firestore+storage 에뮬레이터 기동 후  node scripts/fence-runtime.js
 */
'use strict';
process.env.TZ = 'UTC'; // 스케줄러는 Cloud Functions(UTC)에서 KST 시각을 +9h 로 계산한다
const fs = require('fs');
const path = require('path');
const net = require('net');
const http = require('http');
const https = require('https');
const ROOT = path.join(__dirname, '..');
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:6070';
process.env.GCLOUD_PROJECT = 'demo-alfit-r7';
process.env.FIREBASE_CONFIG = JSON.stringify({projectId: 'demo-alfit-r7', storageBucket: 'demo-alfit-r7.appspot.com'});
process.env.FIREBASE_STORAGE_EMULATOR_HOST = '127.0.0.1:6071';
delete process.env.GOOGLE_APPLICATION_CREDENTIALS;
for (const line of fs.readFileSync(path.join(ROOT, 'functions', '.env.demo-alfit-r7'), 'utf8').split(/\r?\n/)) {
  const m = /^([A-Z0-9_]+)=(.*)$/.exec(line); if (m) process.env[m[1]] = m[2];
}
// 바깥 트래픽 차단(FCM 등) — 로컬만
const outbound = [];
const isLocal = (h) => h === '127.0.0.1' || h === 'localhost' || h === '::1';
const origConnect = net.Socket.prototype.connect;
net.Socket.prototype.connect = function(...args) {
  let a = args[0]; if (Array.isArray(a)) a = a[0];
  if (a && typeof a === 'object' && a.path) return origConnect.apply(this, args);
  const host = a && typeof a === 'object' ? (a.host || 'localhost') : (typeof args[1] === 'string' ? args[1] : 'localhost');
  if (!isLocal(host)) { outbound.push(host); throw new Error('outbound blocked ' + host); }
  return origConnect.apply(this, args);
};
for (const [mod, name] of [[https, 'request'], [https, 'get'], [http, 'request'], [http, 'get']]) {
  const orig = mod[name];
  mod[name] = function(...args) {
    const a = args[0];
    const host = typeof a === 'string' ? new URL(a).hostname : (a && (a.hostname || a.host)) || '';
    if (!isLocal(host)) { outbound.push(host); throw new Error('outbound blocked ' + host); }
    return orig.apply(this, args);
  };
}
const log = console.log; console.error = () => {}; console.warn = () => {}; console.log = () => {}; console.info = () => {};
process.env.NODE_PATH = path.join(ROOT, 'functions', 'node_modules');
require('module').Module._initPaths();
const fn = require(process.env.BUNDLE || path.join(ROOT, 'functions', 'lib', 'index.js'));
const admin = require(path.join(ROOT, 'functions', 'node_modules', 'firebase-admin'));
const db = admin.firestore();
const {Timestamp, FieldValue} = admin.firestore;

const RUN = 'fx' + Date.now().toString(36);
const K = 9 * 3600e3;
const REAL_NOW = Date.now();
const kstMidnight = (ms) => { const d = new Date(ms + K); return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()) - K; };
const ymd8 = (ms) => new Date(ms + K).toISOString().slice(0, 10).replace(/-/g, '');
const ymd = (ms) => new Date(ms + K).toISOString().slice(0, 10);
const TODAY = kstMidnight(REAL_NOW);
const ALL_DAYS = ['일', '월', '화', '수', '목', '금', '토'];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let seq = 0;
const uid = (p) => `${p}-${RUN}-${++seq}`;
const read = async (p) => (await db.doc(p).get()).data();
const rows = []; let pass = 0; const fails = [];
async function cell(id, name, f) {
  try { const note = await f(); pass++; rows.push(`  ok   ${id} ${name}${note ? ' — ' + note : ''}`); } catch (e) {
    fails.push(id); rows.push(`  FAIL ${id} ${name} — ${String(e.message).split('\n')[0]}`);
  }
}
const must = (c, m) => { if (!c) throw new Error(m); };
const call = async (name, uidv, data, token = {}) => { try { return {ok: await fn[name].run({auth: {uid: uidv, token}, rawRequest: {headers: {}}, data})}; } catch (e) { return {err: (e.code || '') + ':' + e.message, details: e.details}; } };
/** 스케줄러를 그 KST 시각으로 돌린다(Date.now 고정). */
async function runSchedulerAt(kstHour, kstMin) {
  const at = TODAY + (kstHour * 60 + kstMin) * 60e3;
  const orig = Date.now;
  Date.now = () => at;
  try { await fn.masterScheduler.run({}); } catch (e) { /* 개별 단계 오류는 allSettled 로 삼켜진다 */ } finally { Date.now = orig; }
}

async function biz(o = {}) {
  const b = uid('b'); const owner = uid('o');
  await db.doc(`users/${owner}`).set({role: 'BUSINESS_ADMIN', businessId: b, name: 'owner', accountStatus: 'active'});
  await db.doc(`businesses/${b}`).set(Object.assign({isApproved: true, ownerId: owner, adminIds: [owner], name: 'biz'}, o));
  return {b, owner};
}
async function longTermApp(b, o = {}) {
  const a = uid('a'); const w = uid('w');
  await db.doc(`users/${w}`).set({role: 'USER', name: 'worker', accountStatus: 'active'});
  await db.doc(`applications/${a}`).set(Object.assign({status: 'CONFIRMED', type: 'long_term', uid: w, userId: w, businessId: b,
    toId: uid('t'), workDays: ALL_DAYS, workDate: Timestamp.fromMillis(TODAY - 10 * 86400e3),
    desiredStartDate: Timestamp.fromMillis(TODAY - 10 * 86400e3), workEndDate: Timestamp.fromMillis(TODAY + 30 * 86400e3),
    startTime: '09:00', endTime: '18:00', selectedWorkType: 'QA', appliedAt: Timestamp.now(), confirmedAt: Timestamp.fromMillis(TODAY - 11 * 86400e3)}, o));
  return {a, w};
}

(async () => {
  log(`[RUN ${RUN}]`);
  // ── F: 닫힌 사업장의 장기 근무 ──
  const closed = await biz({isApproved: false, deactivatedAt: Timestamp.fromMillis(TODAY - 3 * 86400e3),
    archivedAt: Timestamp.fromMillis(TODAY - 3 * 86400e3), archiveReason: 'OWNER_CLOSED'});
  const open = await biz();
  const cA = await longTermApp(closed.b); const oA = await longTermApp(open.b);
  await runSchedulerAt(6, 5);
  const yday = ymd8(TODAY - 86400e3);
  await cell('F-1', '닫힌 사업장 장기 근무: 종료일 이후 어제는 자동 노쇼를 쓰지 않는다', async () => {
    const c = await db.doc(`attendance/${cA.a}_${yday}`).get();
    const o = await db.doc(`attendance/${oA.a}_${yday}`).get();
    must(o.exists && o.get('status') === 'NO_SHOW', `대조(열린 사업장) NO_SHOW 없음 — 판별력 없음 (${o.exists})`);
    must(!c.exists, `닫힌 사업장에 ${c.get('status')} 기록됨`);
    return `닫힘 기록 없음 · 열림 NO_SHOW`;
  });
  await runSchedulerAt(20, 5);
  await cell('F-2', '닫힌 사업장 장기 근무: 내일 근무 알림을 보내지 않는다', async () => {
    const c = await read(`applications/${cA.a}`); const o = await read(`applications/${oA.a}`);
    must(o.reminderSentDate === ymd(TODAY), `대조 알림 표시 없음 (${o.reminderSentDate})`);
    must(c.reminderSentDate == null, `닫힌 사업장에 알림 ${c.reminderSentDate}`);
    return `닫힘 미발송 · 열림 ${o.reminderSentDate}`;
  });

  // ── L: 장기 시작 판정 ──
  await cell('L-1', 'workDate 는 지났지만 시작일(desiredStartDate)이 미래인 장기 확정은 "시작 전"으로 센다', async () => {
    const x = await biz();
    await longTermApp(x.b, {workDate: Timestamp.fromMillis(TODAY - 5 * 86400e3),
      desiredStartDate: Timestamp.fromMillis(TODAY + 5 * 86400e3), confirmedAt: Timestamp.fromMillis(TODAY - 6 * 86400e3)});
    await longTermApp(x.b); // 이미 시작한 장기(대조)
    const r = await call('callableArchiveOwnBusiness', x.owner, {businessId: x.b, preview: true});
    const p = r.ok && r.ok.preview;
    // [4단계] 이미 시작한 장기(대조)는 "유지"가 아니라 **사전 해결 필수(진행 중 장기 근무)**로 센다.
    must(p && p.futureConfirmed === 1 && p.ongoingLongTerm === 1 && p.keptStarted === 0,
      `사전 조회 ${JSON.stringify(p || r.err)}`);
    return `시작 전 ${p.futureConfirmed} · 진행 중 장기 ${p.ongoingLongTerm}`;
  });

  // ── W: 탈퇴 차단 ──
  await cell('W-1', '소유자: 운영 종료한 사업장의 미지급 확정 급여가 탈퇴 사전 조회에 잡힌다', async () => {
    const x = await biz({isApproved: false, deactivatedAt: Timestamp.now(), archivedAt: Timestamp.now(), archiveReason: 'OWNER_CLOSED'});
    await db.doc(`attendance/${uid('att')}`).set({businessId: x.b, userId: uid('w'), wageStatus: 'confirmed', finalWage: 50000,
      status: 'present', workDate: Timestamp.fromMillis(TODAY - 2 * 86400e3)});
    const r = await call('callableGetWithdrawBlockers', x.owner, {}, {role: 'BUSINESS_ADMIN'});
    const hb = r.ok && r.ok.hardBlocks || [];
    must(hb.some((h) => h.type === 'UNPAID_WAGES' && h.count >= 1), `차단 없음 ${JSON.stringify(r.ok || r.err)}`);
    const pre = await call('callableDeleteAccountPreData', x.owner, {}, {role: 'BUSINESS_ADMIN', auth_time: Math.floor(Date.now() / 1000)});
    must(!!pre.err, `서버 탈퇴 gate 통과됨 ${JSON.stringify(pre.ok)}`);
    return `사전 조회 ${hb.map((h) => h.type).join(',')} · 서버 gate ${pre.err.slice(0, 70)}`;
  });
  await cell('W-2', '근로자: 일했지만 계산 전(pending + 출근 기록) 급여가 탈퇴를 막는다 · 미래 예정은 막지 않는다', async () => {
    const w = uid('w');
    await db.doc(`users/${w}`).set({role: 'USER', name: 'worker', accountStatus: 'active'});
    const r0 = await call('callableGetWithdrawBlockers', w, {}, {role: 'USER'});
    const base = (r0.ok && r0.ok.hardBlocks || []).filter((h) => h.type === 'PENDING_WAGES').length;
    await db.doc(`attendance/${uid('att')}`).set({businessId: uid('b'), userId: w, wageStatus: 'pending',
      checkIn: Timestamp.fromMillis(TODAY - 86400e3 + 9 * 3600e3), status: 'present', workDate: Timestamp.fromMillis(TODAY - 86400e3)});
    await db.doc(`attendance/${uid('att')}`).set({businessId: uid('b'), userId: w, wageStatus: 'pending',
      status: 'scheduled', workDate: Timestamp.fromMillis(TODAY + 3 * 86400e3)});
    const r = await call('callableGetWithdrawBlockers', w, {}, {role: 'USER'});
    const pw = (r.ok && r.ok.hardBlocks || []).find((h) => h.type === 'PENDING_WAGES');
    must(base === 0, '기준선에 이미 차단');
    must(pw && pw.count === 1, `PENDING_WAGES ${JSON.stringify(pw || r.err)} (일한 1건만 기대)`);
    return `PENDING_WAGES ${pw.count}건(미래 예정 제외)`;
  });

  // ── S: 옛 슬롯 공고 ──
  const ready = await biz({city: '평택시', address: '경기도 평택시 1',
    attendanceRules: {earlyWindow: 30, earlyArrivalUnit: 10, lateGrace: 5, lateUnit: 10, lateWindow: 60, overtimeUnit: 10, earlyLeaveUnit: 10}});
  {
    const RULES = (await read(`businesses/${ready.b}`)).attendanceRules;
    const licPath = `businesses/${ready.b}/license/license.jpg`;
    await admin.storage().bucket().file(licPath).save(Buffer.from('x'));
    await db.doc(`businesses/${ready.b}`).update({businessLicenseImageUrl:
      `https://firebasestorage.googleapis.com/v0/b/demo-alfit-r7.appspot.com/o/${encodeURIComponent(licPath)}?alt=media`,
    attendancePolicyConfirmation: Object.assign({confirmedAt: Timestamp.now(), confirmedBy: ready.owner, actorRole: 'business_admin'}, RULES)});
    await db.doc(`users/${ready.owner}`).update({sealBase64: 'x'});
    await db.doc(`businesses/${ready.b}/workTypes/wt1`).set({isActive: true, name: 'QA'});
    await db.doc(`businesses/${ready.b}/contract_templates/tpl`).set({templateType: 'daily'});
  }
  const d1 = ymd(TODAY + 4 * 86400e3); const d2 = ymd(TODAY + 5 * 86400e3);
  const legacyTo = async (o, slotDates) => {
    const t = uid('t');
    await db.doc(`tos/${t}`).set(Object.assign({businessId: ready.b, creatorUID: ready.owner, status: 'SCHEDULED', type: 'flex',
      isPublished: false, publishMode: 'scheduled', publishAt: Timestamp.fromMillis(REAL_NOW - 2 * 3600e3), title: 't', // 스케줄러 고정 시각(시:30)보다 앞이어야 한다
      totalRequired: 1, totalConfirmed: 0, totalPending: 0, createdAt: Timestamp.now()}, o));
    for (const dd of slotDates) {
      await db.doc(`tos/${t}/slots/${uid('s')}`).set({status: 'open', date: Timestamp.fromMillis(Date.parse(dd + 'T00:00:00+09:00'))});
    }
    return t;
  };
  const proven = await legacyTo({dates: [d1, d2]}, [d1, d2]);
  const noDates = await legacyTo({}, [d1]);
  const gap = await legacyTo({dates: [d1, d2]}, [d1]);
  await runSchedulerAt(new Date(REAL_NOW + K).getUTCHours(), 30);
  await cell('S-1', 'totalSlots 없는 옛 공고: 날짜 목록과 슬롯이 일치하면 공개, 아니면 보류하고 이유를 적는다', async () => {
    const [p, n, g] = await Promise.all([proven, noDates, gap].map((t) => read(`tos/${t}`)));
    must(p.isPublished === true, `증명된 공고 미공개 (${p.status}/${p.publishBlockedReason})`);
    must(n.isPublished === false && n.publishBlockedReason === 'SLOTS_UNVERIFIED', `날짜 목록 없음: ${n.isPublished}/${n.publishBlockedReason}`);
    must(g.isPublished === false && g.publishBlockedReason === 'SLOTS_UNVERIFIED', `빠진 날짜: ${g.isPublished}/${g.publishBlockedReason}`);
    return `증명 공개 · 목록 없음 ${n.publishBlockedReason} · 빠진 날짜 ${g.publishBlockedReason}`;
  });
  await cell('S-2', '즉시 공개도 같은 판정 — 증명 못 하면 관리자에게 이유를 돌려준다', async () => {
    const other = await biz(); // 활성 한도 영향 없는 다른 소유자는 준비가 안 돼 있어 같은 사업장으로 잰다
    void other;
    const t = uid('t');
    await db.doc(`tos/${t}`).set({businessId: ready.b, creatorUID: ready.owner, status: 'DRAFT', type: 'flex', isPublished: false,
      publishMode: 'draft', title: 't', totalRequired: 1, totalConfirmed: 0, totalPending: 0, createdAt: Timestamp.now()});
    const r = await call('callablePublishTO', ready.owner, {toId: t});
    must(!!r.err && /확인할 수 없어/.test(r.err), `거절 문구 ${r.err || 'OK(공개됨)'}`);
    must((await read(`tos/${t}`)).isPublished === false, '공개됨');
    return r.err.slice(0, 60);
  });

  // ── D: 초대 거절 의도 ──
  const inviteWorld = async (full) => {
    const x = await biz(); const t = uid('t'); const s = uid('s');
    await db.doc(`tos/${t}`).set({businessId: x.b, status: full ? 'FULL' : 'ACTIVE', type: 'flex', isPublished: true, title: '초대 공고',
      totalRequired: 1, totalConfirmed: full ? 1 : 0, totalPending: 1});
    await db.doc(`tos/${t}/slots/${s}`).set({date: Timestamp.fromMillis(TODAY + 3 * 86400e3), status: full ? 'full' : 'open',
      workDetails: [{wdId: 'wd1', workType: 'QA', startTime: '14:00', endTime: '15:00', requiredCount: 1}],
      confirmedCount: full ? 1 : 0, pendingCount: 1, workDetailCounts: {wd1: {confirmedCount: full ? 1 : 0, pendingCount: 1}}});
    const w = uid('w'); const a = uid('a');
    await db.doc(`users/${w}`).set({role: 'USER', name: 'worker', accountStatus: 'active'});
    await db.doc(`applications/${a}`).set({status: 'INVITED', uid: w, businessId: x.b, toId: t, slotId: s, wdId: 'wd1',
      selectedWorkType: 'QA', startTime: '14:00', endTime: '15:00', workDate: Timestamp.fromMillis(TODAY + 3 * 86400e3),
      type: 'short', invitedBy: x.owner, invitedAt: Timestamp.now(), inviteExpiresAt: Timestamp.fromMillis(REAL_NOW + 3600e3)});
    return {a, w};
  };
  await cell('D-1', '구 앱(의도 표시 없음) × 정원 찬 초대 → 업데이트 안내, 상태는 INVITED 그대로', async () => {
    const x = await inviteWorld(true);
    const r = await call('callableDeclineTOInvitation', x.w, {applicationId: x.a});
    must(!!r.err && /업데이트/.test(r.err), `결과 ${r.err || 'OK'}`);
    must(r.details && r.details.code === 'INVITE_DECLINE_UPDATE_REQUIRED', `details ${JSON.stringify(r.details)}`);
    must((await read(`applications/${x.a}`)).status === 'INVITED', '상태가 바뀜');
    return r.err.slice(0, 70);
  });
  await cell('D-2', '새 앱(declineIntent EXPLICIT) × 정원 찬 초대 → 거절 기록', async () => {
    const x = await inviteWorld(true);
    const r = await call('callableDeclineTOInvitation', x.w, {applicationId: x.a, declineIntent: 'EXPLICIT'});
    must(r.ok && r.ok.success, `결과 ${r.err}`);
    const d = await read(`applications/${x.a}`);
    must(d.status === 'REJECTED', d.status);
    return `REJECTED · 이력 ${d.statusHistory.slice(-1)[0].action}`;
  });
  await cell('D-3', '구 앱(의도 표시 없음) × 열린 초대 → 정상 거절(구 앱도 "거절"이라고 말했다)', async () => {
    const x = await inviteWorld(false);
    const r = await call('callableDeclineTOInvitation', x.w, {applicationId: x.a});
    must(r.ok && r.ok.success, `결과 ${r.err}`);
    must((await read(`applications/${x.a}`)).status === 'REJECTED', '상태');
    return 'REJECTED';
  });
  await cell('D-4', '사업장이 이미 철회한 초대(CANCELED) → 거절로 덮지 않는다', async () => {
    const x = await inviteWorld(false);
    await db.doc(`applications/${x.a}`).update({status: 'CANCELED', cancelReason: 'RECRUIT_CLOSED'});
    const r = await call('callableDeclineTOInvitation', x.w, {applicationId: x.a});
    must(!!r.err, 'OK 로 통과');
    must((await read(`applications/${x.a}`)).status === 'CANCELED', '상태가 바뀜');
    return r.err.slice(0, 60);
  });

  // ── X: 삭제된 공고의 슬롯 만료 ──
  await cell('X-1', '삭제된 공고의 슬롯은 만료 마감·공고 상태 전이를 쓰지 않는다(대조: 살아 있는 공고는 마감)', async () => {
    const x = await biz();
    const mk = async (isDeleted) => {
      const t = uid('t'); const s = uid('s');
      await db.doc(`tos/${t}`).set({businessId: x.b, status: 'ACTIVE', type: 'flex', isPublished: !isDeleted, isDeleted, title: 't',
        totalRequired: 1, totalConfirmed: 0, totalPending: 0, totalSlots: 1});
      await db.doc(`tos/${t}/slots/${s}`).set({toId: t, date: Timestamp.fromMillis(TODAY), status: 'open', confirmedCount: 0, pendingCount: 0,
        workDetails: [{wdId: 'wd1', workType: 'QA', requiredCount: 1, applicationDeadline: Timestamp.fromMillis(REAL_NOW - 3600e3)}],
        workDetailCounts: {wd1: {confirmedCount: 0, pendingCount: 0}}});
      return {t, s};
    };
    const del = await mk(true); const live = await mk(false);
    await runSchedulerAt(new Date(REAL_NOW + K).getUTCHours(), 35);
    const [ds, dt, ls] = [await read(`tos/${del.t}/slots/${del.s}`), await read(`tos/${del.t}`), await read(`tos/${live.t}/slots/${live.s}`)];
    must(ls.workDetails[0].closedAt != null, '대조 공고 슬롯 미마감 — 판별력 없음');
    must(ds.workDetails[0].closedAt == null && ds.status === 'open', `삭제 공고 슬롯 마감됨 (${ds.status})`);
    must(dt.status === 'ACTIVE' && dt.totalRequired === 1, `삭제 공고 상태 ${dt.status}/${dt.totalRequired}`);
    return `삭제 공고 슬롯 ${ds.status} · 공고 ${dt.status}/${dt.totalRequired} · 대조 마감`;
  });

  for (const r of rows) log(r);
  log(`\n통과 ${pass} / 실패 ${fails.length}`);
  log(`바깥 트래픽 시도: ${outbound.length ? [...new Set(outbound)].join(', ') : '0'}`);
  process.exit(fails.length ? 1 : 0);
})().catch((e) => { log('ERR ' + e.stack); process.exit(2); });
