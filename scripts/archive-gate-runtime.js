/**
 * [BUSINESS-ARCHIVE 4단계] 운영 종료 사전 처리 게이트 · 종료 뒤 출근·갱신 · 정산 탈퇴 · 구 앱 중복 공고.
 *
 *   G-*  사전 해결 필수(진행 중 출근·진행 중 장기 근무)면 종료 거절, 사전 조회와 원장이
 *        다르면 새 결과를 돌려주고 종료 거절, 같으면 종료
 *   C-*  장기 근무 본인 출근: 종료 전 날짜 허용 · 종료일부터 거절 · 이미 출근한 날 퇴근 허용
 *   B-*  관리자 일괄 출근: 종료일 당일 기록 허용 · 다음 날부터 거절
 *   R-*  계약 연장 제안 거절 · D-15 연장 알림 미발송(대조: 열린 사업장 발송)
 *   W-*  소유자 탈퇴 최종 검사: 승인 대기·승인된 중간정산(닫힌 사업장)
 *   P-*  구 앱 + 시간 초과 재시도(원장 관찰) — 예약 공개 모드에서 공개 공고 2개
 *
 *   실행: functions+firestore+storage 에뮬레이터 기동 후  node scripts/archive-gate-runtime.js
 *         BUNDLE=<DEV 번들 lib/index.js> 로 이전 동작 대조(게이트·가드가 없는 쪽)
 */
'use strict';
process.env.TZ = 'UTC';
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
const {Timestamp} = admin.firestore;

const RUN = 'ag' + Date.now().toString(36);
const K = 9 * 3600e3;
const REAL_NOW = Date.now();
const kstMidnight = (ms) => { const d = new Date(ms + K); return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()) - K; };
const TODAY = kstMidnight(REAL_NOW);
const DAY = 86400e3;
const ALL_DAYS = ['일', '월', '화', '수', '목', '금', '토'];
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
const call = async (name, uidv, data, token = {}) => {
  try { return {ok: await fn[name].run({auth: {uid: uidv, token}, rawRequest: {headers: {}}, data})}; } catch (e) {
    return {err: (e.code || '') + ':' + e.message, details: e.details};
  }
};
async function runSchedulerAt(kstHour, kstMin) {
  const at = TODAY + (kstHour * 60 + kstMin) * 60e3;
  const orig = Date.now; Date.now = () => at;
  try { await fn.masterScheduler.run({}); } catch (_) { /* allSettled */ } finally { Date.now = orig; }
}
const LOC = {latitude: 37.0, longitude: 127.0};
async function biz(o = {}) {
  const b = uid('b'); const owner = uid('o');
  await db.doc(`users/${owner}`).set({role: 'BUSINESS_ADMIN', businessId: b, name: 'owner', accountStatus: 'active'});
  await db.doc(`businesses/${b}`).set(Object.assign({isApproved: true, ownerId: owner, adminIds: [owner], name: 'biz',
    attendanceType: 'gps', gpsRadius: 100}, LOC, o));
  return {b, owner};
}
const closedFields = (daysAgo) => ({isApproved: false, deactivatedAt: Timestamp.fromMillis(TODAY - daysAgo * DAY + 3600e3),
  archivedAt: Timestamp.fromMillis(TODAY - daysAgo * DAY + 3600e3), archiveReason: 'OWNER_CLOSED'});
async function longTermApp(b, o = {}) {
  const a = uid('a'); const w = uid('w');
  await db.doc(`users/${w}`).set({role: 'USER', name: 'worker', accountStatus: 'active'});
  await db.doc(`applications/${a}`).set(Object.assign({status: 'CONFIRMED', type: 'long_term', uid: w, userId: w, businessId: b,
    toId: uid('t'), workDays: ALL_DAYS, workDate: Timestamp.fromMillis(TODAY - 10 * DAY),
    desiredStartDate: Timestamp.fromMillis(TODAY - 10 * DAY), workEndDate: Timestamp.fromMillis(TODAY + 30 * DAY),
    startTime: '00:00', endTime: '23:59', selectedWorkType: 'QA', appliedAt: Timestamp.now(),
    confirmedAt: Timestamp.fromMillis(TODAY - 11 * DAY)}, o));
  return {a, w};
}
const checkIn = (w, b, a, dayMs) => call('callableCheckIn', w, {applicationId: a, businessId: b, businessName: 'biz',
  workDateMs: dayMs, workType: 'QA', method: 'gps', ...LOC});

(async () => {
  log(`[RUN ${RUN}] Functions ${(process.env.BUNDLE || 'functions/lib/index.js').replace(/\\/g, '/').split('/').slice(-4).join('/')}`);

  // ── G: 운영 종료 사전 처리 게이트 ──
  await cell('G-1', '진행 중인 장기 근무가 있으면 종료하지 않는다(일괄 취소 금지) — 원장 그대로', async () => {
    const x = await biz(); const l = await longTermApp(x.b);
    const pv = await call('callableArchiveOwnBusiness', x.owner, {businessId: x.b, preview: true});
    const P = pv.ok && pv.ok.preview;
    must(P && P.ongoingLongTerm === 1, `사전 조회 ${JSON.stringify(P || pv.err)}`);
    const r = await call('callableArchiveOwnBusiness', x.owner, {businessId: x.b, expected: P});
    must(r.details && r.details.code === 'ARCHIVE_BLOCKED', `결과 ${JSON.stringify(r.ok || r.details || r.err)}`);
    const b = await read(`businesses/${x.b}`); const a = await read(`applications/${l.a}`);
    must(b.isApproved === true && b.deactivatedAt == null && a.status === 'CONFIRMED', '상태가 바뀜');
    return `ARCHIVE_BLOCKED · 사업장 그대로 · 장기 ${a.status}`;
  });
  await cell('G-2', '출근 후 퇴근 전 근무가 있으면 종료하지 않는다', async () => {
    const x = await biz();
    await db.doc(`attendance/${uid('att')}`).set({businessId: x.b, userId: uid('w'), applicationId: uid('a'),
      workDate: Timestamp.fromMillis(TODAY), checkIn: Timestamp.fromMillis(REAL_NOW - 3600e3), status: 'present', wageStatus: 'pending'});
    const pv = await call('callableArchiveOwnBusiness', x.owner, {businessId: x.b, preview: true});
    const P = pv.ok && pv.ok.preview;
    const r = await call('callableArchiveOwnBusiness', x.owner, {businessId: x.b, expected: P});
    must(P && P.inProgressShifts === 1 && r.details && r.details.code === 'ARCHIVE_BLOCKED', `${JSON.stringify(P)} / ${r.err}`);
    return `inProgressShifts 1 → ARCHIVE_BLOCKED`;
  });
  await cell('G-3', '사전 조회 뒤 원장이 바뀌면 종료하지 않고 새 결과를 돌려준다', async () => {
    const x = await biz();
    const pv = await call('callableArchiveOwnBusiness', x.owner, {businessId: x.b, preview: true});
    const P = pv.ok.preview;
    // 확인 화면을 보는 사이 대기 지원이 생겼다(공고 + 지원)
    const t = uid('t');
    await db.doc(`tos/${t}`).set({businessId: x.b, status: 'ACTIVE', type: 'flex', isPublished: true, title: 't'});
    await db.doc(`applications/${uid('a')}`).set({toId: t, businessId: x.b, uid: uid('w'), status: 'PENDING'});
    const r = await call('callableArchiveOwnBusiness', x.owner, {businessId: x.b, expected: P});
    must(r.details && r.details.code === 'ARCHIVE_PREVIEW_CHANGED', `결과 ${JSON.stringify(r.ok || r.err)}`);
    must(r.details.preview.openPostings === 1 && r.details.preview.pendingApplications === 1, JSON.stringify(r.details.preview));
    must((await read(`businesses/${x.b}`)).deactivatedAt == null, '종료됨');
    // 새 결과로 다시 확인하면 종료된다
    const r2 = await call('callableArchiveOwnBusiness', x.owner, {businessId: x.b, expected: r.details.preview});
    must(r2.ok && r2.ok.success, `재확인 실행 ${r2.err}`);
    return `PREVIEW_CHANGED(공고 0→1·대기 0→1) → 새 결과로 재확인 시 종료`;
  });
  await cell('G-4', '사전 조회 없이(expected 없음) 실행하면 종료하지 않는다', async () => {
    const x = await biz();
    const r = await call('callableArchiveOwnBusiness', x.owner, {businessId: x.b});
    must(r.details && r.details.code === 'ARCHIVE_PREVIEW_CHANGED', `결과 ${JSON.stringify(r.ok || r.err)}`);
    must((await read(`businesses/${x.b}`)).deactivatedAt == null, '종료됨');
    return 'ARCHIVE_PREVIEW_CHANGED';
  });
  await cell('G-5', '종료 뒤 보존·처리 항목(미지급·정산·지난 근무)은 종료를 막지 않고 건수로만 보인다', async () => {
    const x = await biz();
    await db.doc(`attendance/${uid('att')}`).set({businessId: x.b, userId: uid('w'), wageStatus: 'confirmed', finalWage: 1000,
      status: 'present', workDate: Timestamp.fromMillis(TODAY - 3 * DAY), checkIn: Timestamp.fromMillis(TODAY - 3 * DAY), checkOut: Timestamp.fromMillis(TODAY - 3 * DAY + 3600e3)});
    await db.doc(`interim_settlement_requests/${uid('isr')}`).set({businessId: x.b, status: 'APPROVED'});
    const pv = await call('callableArchiveOwnBusiness', x.owner, {businessId: x.b, preview: true});
    const P = pv.ok.preview;
    must(P.unpaidWages === 1 && P.interimApproved === 1 && P.inProgressShifts === 0, JSON.stringify(P));
    const r = await call('callableArchiveOwnBusiness', x.owner, {businessId: x.b, expected: P});
    must(r.ok && r.ok.success, `실행 ${r.err}`);
    return `미지급 1 · 승인 정산 1 → 종료 허용`;
  });

  // ── C: 장기 근무 본인 출근 ──
  const closed = await biz(closedFields(1)); // 어제 종료
  const lt = await longTermApp(closed.b);
  await cell('C-1', '종료 전 날짜(그저께)의 출근은 허용', async () => {
    const r = await checkIn(lt.w, closed.b, lt.a, TODAY - 2 * DAY);
    must(!r.err || !/운영을 종료/.test(r.err), `거절 ${r.err}`);
    return r.err ? `다른 사유 ${r.err.slice(0, 50)}` : '출근 기록';
  });
  await cell('C-2', '종료일(어제)·오늘 새 출근은 거절', async () => {
    const r1 = await checkIn(lt.w, closed.b, lt.a, TODAY - DAY);
    const r2 = await checkIn(lt.w, closed.b, lt.a, TODAY);
    must(r1.details && r1.details.code === 'BUSINESS_CLOSED', `종료일 ${r1.err || 'OK'}`);
    must(r2.details && r2.details.code === 'BUSINESS_CLOSED', `오늘 ${r2.err || 'OK'}`);
    return r2.err.slice(0, 60);
  });
  await cell('C-3', '대조: 열린 사업장 같은 장기 근무 오늘 출근은 된다(판별력)', async () => {
    const o = await biz(); const l = await longTermApp(o.b);
    const r = await checkIn(l.w, o.b, l.a, TODAY);
    must(r.ok, `열린 사업장 출근 실패 ${r.err}`);
    return '출근 기록';
  });
  await cell('C-4', '종료 전에 출근한 날의 퇴근은 종료 뒤에도 된다', async () => {
    const x = await biz(); const l = await longTermApp(x.b);
    const ci = await checkIn(l.w, x.b, l.a, TODAY);
    must(ci.ok, `출근 ${ci.err}`);
    await db.doc(`businesses/${x.b}`).update({isApproved: false, deactivatedAt: Timestamp.now(), archivedAt: Timestamp.now(), archiveReason: 'OWNER_CLOSED'});
    const attId = (await db.collection('attendance').where('applicationId', '==', l.a).get()).docs[0].id;
    const co = await call('callableCheckOut', l.w, {attendanceId: attId, workDateMs: TODAY, method: 'gps', ...LOC});
    must(co.ok, `퇴근 ${co.err}`);
    return '퇴근 기록';
  });

  // ── B: 관리자 일괄 출근 ──
  await cell('B-1', '관리자 일괄 출근: 종료일 당일은 종료 시각 **이전** 출근만, 종료 시각 이후·다음 날은 거절', async () => {
    // 종료 시각 = 그저께 KST 01:00 (closedFields(2))
    const x = await biz(closedFields(2));
    const before = await longTermApp(x.b); const after = await longTermApp(x.b); const next = await longTermApp(x.b);
    const closeDay = TODAY - 2 * DAY;
    const entry = (l, dayMs, ciMs) => ({applicationId: l.a, workDateMs: dayMs, userId: l.w, businessName: 'biz', workType: 'QA',
      status: 'present', checkInMs: ciMs});
    const r = await call('callableBatchCheckIn', x.owner, {businessId: x.b, entries: [
      entry(before, closeDay, closeDay + 30 * 60e3), // 00:30 — 종료 전에 시작한 근무
      entry(after, closeDay, closeDay + 9 * 3600e3), // 09:00 — 종료 뒤 새 근무
      entry(next, TODAY - DAY, TODAY - DAY + 9 * 3600e3), // 다음 날
    ]}, {role: 'BUSINESS_ADMIN'});
    const has = async (l) => !(await db.collection('attendance').where('applicationId', '==', l.a).get()).empty;
    const [hb, ha, hn] = [await has(before), await has(after), await has(next)];
    const reasons = (r.ok && r.ok.failures || []).map((f) => f.reason);
    must(hb, `종료 전 시작 근무가 기록되지 않음 ${JSON.stringify(r.ok || r.err)}`);
    must(!ha && !hn, `종료 뒤 새 근무 기록됨 (당일 이후 ${ha} · 다음 날 ${hn})`);
    must(reasons.filter((x) => x === 'businessClosed').length === 2, `사유 ${reasons}`);
    return `종료 전 기록 · 종료 뒤·다음 날 거절(businessClosed 2)`;
  });

  // ── R: 계약 연장 ──
  await cell('R-1', '운영 종료 사업장은 연장 제안을 만들지 않는다', async () => {
    const x = await biz(closedFields(1)); const l = await longTermApp(x.b);
    const r = await call('callableCreateRenewalProposal', x.owner, {oldApplicationId: l.a,
      effectiveStartMs: TODAY + 31 * DAY, effectiveEndMs: TODAY + 90 * DAY}, {role: 'BUSINESS_ADMIN'});
    must(r.details && r.details.code === 'BUSINESS_CLOSED', `결과 ${r.err || JSON.stringify(r.ok)}`);
    return r.err.slice(0, 50);
  });
  await cell('R-2', 'D-15 연장 검토 알림: 닫힌 사업장 미발송 · 열린 사업장 발송', async () => {
    const c = await biz(closedFields(1)); const o = await biz();
    const lc = await longTermApp(c.b, {workEndDate: Timestamp.fromMillis(TODAY + 15 * DAY + 3600e3)});
    const lo = await longTermApp(o.b, {workEndDate: Timestamp.fromMillis(TODAY + 15 * DAY + 3600e3)});
    await runSchedulerAt(0, 5);
    const [ac, ao] = [await read(`applications/${lc.a}`), await read(`applications/${lo.a}`)];
    must(ao.renewalNotifiedAt != null, '대조 미발송 — 판별력 없음');
    must(ac.renewalNotifiedAt == null, '닫힌 사업장 발송됨');
    return '닫힘 없음 · 열림 발송';
  });

  // ── W: 소유자 탈퇴 최종 검사 ──
  const ownerWithdraw = async (status) => {
    const x = await biz(closedFields(1));
    await db.doc(`interim_settlement_requests/${uid('isr')}`).set({businessId: x.b, status, workerId: uid('w'), amount: 1000});
    const pre = await call('callableGetWithdrawBlockers', x.owner, {}, {role: 'BUSINESS_ADMIN'});
    const fin = await call('callableDeleteAccountPreData', x.owner, {}, {role: 'BUSINESS_ADMIN', auth_time: Math.floor(Date.now() / 1000)});
    return {pre: (pre.ok && pre.ok.hardBlocks || []).map((h) => h.type), fin: fin.err || 'OK(통과)'};
  };
  await cell('W-3', '승인 대기(PENDING) 정산(닫힌 사업장) — 사전 조회는 막고 최종 검사는 기존 결정(WBP-SUB-02)대로 세지 않는다(관찰)', async () => {
    const r = await ownerWithdraw('PENDING');
    must(r.pre.includes('INTERIM_PENDING'), `사전 ${r.pre}`);
    must(!/INTERIM_PENDING/.test(r.fin), `최종이 PENDING 으로 막음(되돌린 수정이 남았다) ${r.fin.slice(0, 80)}`);
    return `사전 ${r.pre.join(',')} · 최종 ${r.fin.slice(0, 50)}`;
  });
  await cell('W-4', '승인된(APPROVED) 정산 — 사전 조회와 최종 검사가 모두 막는다', async () => {
    const r = await ownerWithdraw('APPROVED');
    must(r.pre.includes('INTERIM_SETTLEMENT_UNPROCESSED'), `사전 ${r.pre}`);
    must(/INTERIM_SETTLEMENT_UNPROCESSED/.test(r.fin), `최종 ${r.fin.slice(0, 80)}`);
    return `사전 ${r.pre.join(',')} · 최종 ${r.fin.slice(0, 50)}`;
  });

  await cell('W-5', '열린 사업장의 승인 대기 정산 — 사전 조회만 막고 최종 검사는 통과(기준 차이 관찰·제품 결정 OPEN)', async () => {
    const x = await biz();
    await db.doc(`interim_settlement_requests/${uid('isr')}`).set({businessId: x.b, status: 'PENDING', workerId: uid('w'), amount: 1000});
    const pre = await call('callableGetWithdrawBlockers', x.owner, {}, {role: 'BUSINESS_ADMIN'});
    const fin = await call('callableDeleteAccountPreData', x.owner, {}, {role: 'BUSINESS_ADMIN', auth_time: Math.floor(Date.now() / 1000)});
    const p = (pre.ok && pre.ok.hardBlocks || []).map((h) => h.type);
    must(p.includes('INTERIM_PENDING'), `사전 ${p}`);
    must(!/INTERIM_PENDING/.test(fin.err || ''), `최종이 PENDING 으로 막음 ${fin.err}`);
    return `사전 ${p.join(',')} · 최종 ${(fin.err || 'OK(통과)').slice(0, 40)}`;
  });

  // ── N: 앱이 만든 사업장(deactivatedAt: null)도 운영 종료 연쇄가 돈다 ──
  await cell('N-1', '앱 생성 모양(deactivatedAt: null) 사업장 — 트리거 핸들러가 운영 종료를 처리한다(연쇄 전에 끊기지 않는다)', async () => {
    const x = await biz({deactivatedAt: null});
    const t = uid('t');
    await db.doc(`tos/${t}`).set({businessId: x.b, status: 'ACTIVE', type: 'flex', isPublished: true, title: 't'});
    const a = uid('a');
    await db.doc(`applications/${a}`).set({toId: t, businessId: x.b, uid: uid('w'), status: 'CONFIRMED', type: 'short',
      workDate: Timestamp.fromMillis(TODAY + 3 * DAY), startTime: '09:00', endTime: '18:00', appliedAt: Timestamp.now()});
    const before = {...(await read(`businesses/${x.b}`))};
    const after = {...before, isApproved: false, deactivatedAt: Timestamp.now(), archivedAt: Timestamp.now(), archiveReason: 'OWNER_CLOSED'};
    // 트리거 핸들러를 같은 모양의 이벤트로 직접 부른다 — BUNDLE 로 배포본과 비교한다
    await fn.onBusinessDeactivated.run({params: {businessId: x.b},
      data: {before: {data: () => before, exists: true}, after: {data: () => after, exists: true}}});
    const [td, ad] = [await read(`tos/${t}`), await read(`applications/${a}`)];
    must(td.status === 'CLOSED' && ad.status === 'CANCELED', `공고 ${td.status} · 확정 ${ad.status} — 연쇄가 돌지 않음`);
    return `공고 ${td.status} · 시작 전 확정 ${ad.status}`;
  });

  // ── T: 함께 나가는 변경 표적 역검증 — 탈퇴 barrier 가 알림을 막는다 ──
  await cell('T-1', '탈퇴 진행 중(tombstone) 근로자에게는 운영 종료 취소 알림을 남기지 않는다 · 대조 근로자는 받는다', async () => {
    const x = await biz();
    const t = uid('t');
    await db.doc(`tos/${t}`).set({businessId: x.b, status: 'ACTIVE', type: 'flex', isPublished: true, title: 't'});
    const mkFuture = async () => {
      const a = uid('a'); const w = uid('w');
      await db.doc(`users/${w}`).set({role: 'USER', name: 'worker', accountStatus: 'active'});
      await db.doc(`applications/${a}`).set({toId: t, businessId: x.b, uid: w, status: 'CONFIRMED', type: 'short',
        workDate: Timestamp.fromMillis(TODAY + 3 * DAY), startTime: '09:00', endTime: '18:00', appliedAt: Timestamp.now()});
      return {a, w};
    };
    const del = await mkFuture(); const ctl = await mkFuture();
    await db.doc(`account_deletion_tombstones/${del.w}`).set({createdAt: Timestamp.now()});
    const pv = await call('callableArchiveOwnBusiness', x.owner, {businessId: x.b, preview: true});
    const r = await call('callableArchiveOwnBusiness', x.owner, {businessId: x.b, expected: pv.ok.preview});
    must(r.ok && r.ok.success, `종료 ${r.err}`);
    // 실제 트리거 연쇄(Functions 에뮬레이터)를 기다린다
    for (let i = 0; i < 90; i++) {
      if ((await read(`applications/${ctl.a}`)).status === 'CANCELED') break;
      await new Promise((res) => setTimeout(res, 1000));
    }
    await new Promise((res) => setTimeout(res, 4000));
    const nd = await db.doc(`users/${del.w}/notifications/biz_end_${del.a}`).get();
    const nc = await db.doc(`users/${ctl.w}/notifications/biz_end_${ctl.a}`).get();
    must(nc.exists, '대조 근로자 알림 없음 — 판별력 없음');
    must(!nd.exists, '탈퇴 진행 중 근로자에게 알림이 남았다');
    return `탈퇴 중 없음 · 대조 ${nc.get('type')}`;
  });

  // ── P: 구 앱 시간 초과 재시도(관찰) ──
  await cell('P-1', '구 앱: 예약 공개 모드에서 슬롯 생성 응답만 끊기고 재시도하면 공개 공고 2개(관찰·OPEN)', async () => {
    const x = await biz({city: '평택시', address: '경기도 평택시 1'});
    // 공개 준비(등록증 파일·업무·템플릿·인감·근태 기준)
    const RULES = {earlyWindow: 30, earlyArrivalUnit: 10, lateGrace: 5, lateUnit: 10, lateWindow: 60, overtimeUnit: 10, earlyLeaveUnit: 10};
    const lic = `businesses/${x.b}/license/license.jpg`;
    await admin.storage().bucket().file(lic).save(Buffer.from('x'));
    await db.doc(`businesses/${x.b}`).update({attendanceRules: RULES, businessLicenseImageUrl:
      `https://firebasestorage.googleapis.com/v0/b/demo-alfit-r7.appspot.com/o/${encodeURIComponent(lic)}?alt=media`,
    attendancePolicyConfirmation: Object.assign({confirmedAt: Timestamp.now(), confirmedBy: x.owner, actorRole: 'business_admin'}, RULES)});
    await db.doc(`users/${x.owner}`).update({sealBase64: 'x'});
    await db.doc(`businesses/${x.b}/workTypes/wt1`).set({isActive: true, name: 'QA'});
    await db.doc(`businesses/${x.b}/contract_templates/tpl`).set({templateType: 'daily'});
    const dateStr = new Date(TODAY + 4 * DAY + K).toISOString().slice(0, 10);
    const mk = async () => {
      const t = uid('t');
      // callableCreateTO 가 남기는 예약 공개 모양(totalSlots 0) → callableCreateFlexSlots 성공(응답만 끊김)
      await db.doc(`tos/${t}`).set({businessId: x.b, creatorUID: x.owner, status: 'SCHEDULED', type: 'flex', isPublished: false,
        publishMode: 'scheduled', publishAt: Timestamp.fromMillis(REAL_NOW - 60e3), title: '같은 공고', totalRequired: 0,
        totalSlots: 0, totalConfirmed: 0, totalPending: 0, createdAt: Timestamp.now()});
      const r = await call('callableCreateFlexSlots', x.owner, {toId: t, businessId: x.b, dates: [dateStr],
        workDetails: [{workType: 'QA', startTime: '14:00', endTime: '15:00', requiredCount: 1, wage: 12000, wageType: 'hourly', payScheduleType: 'next_day'}],
        deadlineType: 'HOURS_BEFORE', hoursBeforeStart: 1});
      must(r.ok, `슬롯 생성 ${r.err}`);
      return t; // 구 앱은 응답을 못 받고 직접 삭제를 시도 → 후보 Rules 403(행렬에서 측정) → 공고 남음
    };
    const t1 = await mk(); const t2 = await mk(); // 사용자가 다시 만든다
    await runSchedulerAt(new Date(REAL_NOW + K).getUTCHours(), 40);
    const [a, b] = [await read(`tos/${t1}`), await read(`tos/${t2}`)];
    return `첫 공고 ${a.status}/게시 ${a.isPublished} · 재시도 공고 ${b.status}/게시 ${b.isPublished}` +
      (a.isPublished && b.isPublished ? ' → 중복 공개 재현' : '');
  });

  for (const r of rows) log(r);
  log(`\n통과 ${pass} / 실패 ${fails.length}`);
  log(`바깥 트래픽 시도: ${outbound.length ? [...new Set(outbound)].join(', ') : '0'}`);
  process.exit(fails.length ? 1 : 0);
})().catch((e) => { log('ERR ' + e.stack); process.exit(2); });
