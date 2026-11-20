/**
 * [BUSINESS-ARCHIVE · CREATE-ROLLBACK] 운영 종료 뒤 지나간 근무 · 슬롯 미완성 공고 공개.
 *
 *   A-*  callableArchiveOwnBusiness(preview → 실행) → **실제** onBusinessDeactivated 연쇄
 *        (Functions 에뮬레이터). 예정 시작이 지난 확정은 보존, 시작 전 확정은 취소+알림,
 *        대기 지원은 마감+알림, 보존 건의 미서명 계약은 유지·취소 건 계약은 무효.
 *   S-*  슬롯 생성이 끝나지 않은 슬롯 공고(totalSlots 0)를 masterScheduler(.run) 와
 *        callablePublishTO 가 공개하는가 — BUNDLE 로 이전 번들과 비교한다.
 *
 *   실행: functions+firestore+storage 에뮬레이터 기동 후
 *     node scripts/archive-postop-runtime.js                  (후보: A + S)
 *     MODE=sched BUNDLE=<이전 lib/index.js> node scripts/archive-postop-runtime.js   (S 만)
 */
'use strict';
const fs = require('fs');
const path = require('path');
const ROOT = path.join(__dirname, '..');
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:6070';
process.env.GCLOUD_PROJECT = 'demo-alfit-r7';
process.env.FIREBASE_CONFIG = JSON.stringify({projectId: 'demo-alfit-r7', storageBucket: 'demo-alfit-r7.appspot.com'});
process.env.FIREBASE_STORAGE_EMULATOR_HOST = '127.0.0.1:6071';
delete process.env.GOOGLE_APPLICATION_CREDENTIALS;
for (const line of fs.readFileSync(path.join(ROOT, 'functions', '.env.demo-alfit-r7'), 'utf8').split(/\r?\n/)) {
  const m = /^([A-Z0-9_]+)=(.*)$/.exec(line); if (m) process.env[m[1]] = m[2];
}
const log = console.log; console.error = () => {}; console.warn = () => {}; console.log = () => {};
process.env.NODE_PATH = path.join(ROOT, 'functions', 'node_modules');
require('module').Module._initPaths();
const BUNDLE = process.env.BUNDLE || path.join(ROOT, 'functions', 'lib', 'index.js');
const MODE = process.env.MODE || 'all';
const fn = require(BUNDLE);
const admin = require(path.join(ROOT, 'functions', 'node_modules', 'firebase-admin'));
const db = admin.firestore();
const {Timestamp} = admin.firestore;

const RUN = 'ap' + Date.now().toString(36);
const K = 9 * 3600e3;
const NOW = Date.now();
const kstMidnight = (ms) => { const d = new Date(ms + K); return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()) - K; };
const hhmm = (ms) => new Date(ms + K).toISOString().slice(11, 16);
const RULES = {earlyWindow: 30, earlyArrivalUnit: 10, lateGrace: 5, lateUnit: 10, lateWindow: 60, overtimeUnit: 10, earlyLeaveUnit: 10};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let seq = 0;
const uid = (p) => `${p}-${RUN}-${++seq}`;
const rows = []; let pass = 0; let fail = 0;
const check = (id, ok, detail) => { ok ? pass++ : fail++; rows.push(`  ${ok ? 'ok  ' : 'FAIL'} ${id} ${detail}`); };
const read = async (p) => (await db.doc(p).get()).data();
async function until(pred, ms) { const t0 = Date.now(); while (Date.now() - t0 < ms) { if (await pred()) return true; await sleep(1000); } return false; }
const call = async (name, uidv, data) => { try { return {ok: await fn[name].run({auth: {uid: uidv, token: {}}, rawRequest: {headers: {}}, data})}; } catch (e) { return {err: (e.code || '') + ':' + e.message}; } };

/** 공개 준비가 끝난 사업장(등록증 파일·활성 업무·계약 템플릿·근태 기준 확인). */
async function readyBusiness() {
  const biz = uid('b'); const owner = uid('o');
  await db.doc(`users/${owner}`).set({role: 'BUSINESS_ADMIN', sealBase64: 'x', businessId: biz, name: 'owner'});
  const licPath = `businesses/${biz}/license/license.jpg`;
  await admin.storage().bucket().file(licPath).save(Buffer.from('x'));
  await db.doc(`businesses/${biz}`).set({isApproved: true, ownerId: owner, adminIds: [owner], name: 'biz',
    city: '평택시', address: '경기도 평택시 1', attendanceRules: RULES,
    attendancePolicyConfirmation: Object.assign({confirmedAt: Timestamp.now(), confirmedBy: owner, actorRole: 'business_admin'}, RULES),
    businessLicenseImageUrl: `https://firebasestorage.googleapis.com/v0/b/demo-alfit-r7.appspot.com/o/${encodeURIComponent(licPath)}?alt=media`});
  await db.doc(`businesses/${biz}/workTypes/wt1`).set({isActive: true, name: 'QA'});
  await db.doc(`businesses/${biz}/contract_templates/tpl`).set({templateType: 'daily'});
  return {biz, owner};
}

async function schedCells() {
  const {biz, owner} = await readyBusiness();
  const mk = async (o) => {
    const id = uid('t');
    await db.doc(`tos/${id}`).set(Object.assign({businessId: biz, creatorUID: owner, status: 'SCHEDULED', type: 'flex',
      isPublished: false, publishMode: 'scheduled', publishAt: Timestamp.fromMillis(NOW - 60e3), title: 't',
      totalRequired: 0, totalConfirmed: 0, totalPending: 0, createdAt: Timestamp.now()}, o));
    return id;
  };
  // 부분 슬롯 1개가 남았지만 생성은 끝나지 않았다(totalSlots 0) — 구 앱 직접 삭제가 403 으로 막힌 모양
  const partial = await mk({totalSlots: 0});
  await db.doc(`tos/${partial}/slots/s1`).set({status: 'open', date: Timestamp.fromMillis(kstMidnight(NOW + 3 * 86400e3))});
  const empty = await mk({totalSlots: 0}); // 앱 종료 — 슬롯 0
  const done = await mk({totalSlots: 1, totalRequired: 1}); // 대조: 생성 완료
  const legacy = await mk({}); // 필드 없는 레거시 — 판정하지 않는다
  let err = null;
  try { await fn.masterScheduler.run({}); } catch (e) { err = e.message; }
  const [p, e, d, l] = await Promise.all([partial, empty, done, legacy].map((id) => read(`tos/${id}`)));
  const pub = (x) => `${x.status}/게시 ${x.isPublished}`;
  rows.push(`  · 스케줄러: 부분 ${pub(p)} · 빈 ${pub(e)} · 완료 ${pub(d)} · 레거시 ${pub(l)}${err ? ' · 오류 ' + err.slice(0, 50) : ''}`);
  return {p, e, d, l, biz, owner};
}

async function publishCell(biz, owner) {
  const draft = uid('t');
  await db.doc(`tos/${draft}`).set({businessId: biz, creatorUID: owner, status: 'DRAFT', type: 'flex', isPublished: false,
    publishMode: 'draft', title: 't', totalSlots: 0, totalRequired: 0, totalConfirmed: 0, totalPending: 0, createdAt: Timestamp.now()});
  const r = await call('callablePublishTO', owner, {toId: draft});
  const t = await read(`tos/${draft}`);
  return {r, t};
}

(async () => {
  const label = BUNDLE.replace(/\\/g, '/').split('/').slice(-4).join('/');
  log(`[RUN ${RUN}] Functions ${label}`);
  // ── S: 슬롯 미완성 공고 공개 ──
  const s = await schedCells();
  const cand = MODE !== 'sched';
  if (cand) {
    check('S-1', s.p.isPublished === false && s.e.isPublished === false, '슬롯 생성 미완료(부분·빈) 예약 공고는 공개되지 않는다');
    check('S-2', s.d.isPublished === true, '대조: 생성 완료 예약 공고는 공개된다(판별력)');
    // [3단계] 필드 없음은 완성 증거가 아니다 — 날짜 목록도 없으면 보류하고 이유를 적는다(fence-runtime S-1 이 증명 경로를 잰다).
    check('S-3', s.l.isPublished === false && s.l.publishBlockedReason === 'SLOTS_UNVERIFIED',
      `레거시(totalSlots·dates 없음)는 보류 — ${s.l.status}/${s.l.publishBlockedReason}`);
  } else {
    rows.push(`  · [이전 번들 관찰] 부분 슬롯 공고 게시=${s.p.isPublished} · 빈 공고 게시=${s.e.isPublished} · 대조 게시=${s.d.isPublished}`);
  }
  // 즉시 공개는 **다른 소유자**로 잰다 — 위 스케줄러가 공개한 공고로 활성 한도(4)가 차면 판별력이 없다.
  const fresh = await readyBusiness();
  const pc = await publishCell(fresh.biz, fresh.owner);
  if (cand) check('S-4', !!pc.r.err && pc.t.isPublished === false, `즉시 공개(callablePublishTO)도 거절 — ${(pc.r.err || 'OK').slice(0, 70)}`);
  else rows.push(`  · [이전 번들 관찰] 미완성 초안 즉시 공개 → ${pc.r.err ? '거절 ' + pc.r.err.slice(0, 50) : '공개됨'} · 게시=${pc.t.isPublished}`);

  if (cand) {
    // ── A: 운영 종료 뒤 지나간 근무 ──
    const {biz, owner} = await readyBusiness();
    const to = uid('t');
    await db.doc(`tos/${to}`).set({businessId: biz, creatorUID: owner, status: 'ACTIVE', type: 'flex', isPublished: true,
      title: '종료 공고', totalRequired: 9, totalConfirmed: 7, totalPending: 1, createdAt: Timestamp.now()});
    const past = kstMidnight(NOW - 2 * 86400e3);
    const future = kstMidnight(NOW + 3 * 86400e3);
    const today = kstMidnight(NOW);
    const sameDay = (ms) => kstMidnight(ms) === today;
    const apps = {};
    const mkApp = async (key, status, o) => {
      const id = uid('a'); apps[key] = id;
      await db.doc(`applications/${id}`).set(Object.assign({toId: to, businessId: biz, uid: uid('w'), status,
        toTitle: '종료 공고', startTime: '09:00', endTime: '18:00', appliedAt: Timestamp.now(), statusHistory: []}, o));
    };
    await mkApp('past', 'CONFIRMED', {workDate: Timestamp.fromMillis(past)});
    await mkApp('pastUtc', 'CONFIRMED', {workDate: Timestamp.fromMillis(past + K)}); // UTC 자정 오염 모양
    await mkApp('worked', 'CONFIRMED', {workDate: Timestamp.fromMillis(past)});
    await mkApp('future', 'CONFIRMED', {workDate: Timestamp.fromMillis(future)});
    const canToday = sameDay(NOW + 2 * 3600e3) && sameDay(NOW - 3600e3);
    if (canToday) {
      await mkApp('todayLater', 'CONFIRMED', {workDate: Timestamp.fromMillis(today), startTime: hhmm(NOW + 2 * 3600e3)});
      await mkApp('todayStarted', 'CONFIRMED', {workDate: Timestamp.fromMillis(today), startTime: hhmm(NOW - 3600e3)});
    }
    await mkApp('pending', 'PENDING', {workDate: Timestamp.fromMillis(future)});
    await mkApp('cpFuture', 'CONTRACT_PENDING', {workDate: Timestamp.fromMillis(future)});
    await mkApp('cpPast', 'CONTRACT_PENDING', {workDate: Timestamp.fromMillis(past)});
    // 실근무 — 출근 기록
    const d8 = new Date(past + K).toISOString().slice(0, 10).replace(/-/g, '');
    await db.doc(`attendance/${apps.worked}_${d8}`).set({applicationId: apps.worked, businessId: biz,
      checkIn: Timestamp.fromMillis(past + 9 * 3600e3), status: 'CHECKED_OUT'});
    const cFuture = uid('c'); const cPast = uid('c');
    await db.doc(`employment_contracts/${cFuture}`).set({businessId: biz, toId: to, applicationIds: [apps.cpFuture], status: 'pending_worker'});
    await db.doc(`employment_contracts/${cPast}`).set({businessId: biz, toId: to, applicationIds: [apps.cpPast], status: 'pending_worker'});

    // A-1 사전 조회 — 실제 연쇄가 할 일을 센다
    const pv = await call('callableArchiveOwnBusiness', owner, {businessId: biz, preview: true});
    const P = pv.ok && pv.ok.preview;
    const expFuture = 2 + (canToday ? 1 : 0); // future, cpFuture (+ todayLater)
    const expKept = 4 + (canToday ? 1 : 0); // past, pastUtc, worked, cpPast (+ todayStarted)
    check('A-1', !!P && P.openPostings === 1 && P.pendingApplications === 1 && P.invites === 0 &&
      P.futureConfirmed === expFuture && P.keptStarted === expKept && P.truncated === false,
    `사전 조회 ${JSON.stringify(P)} (기대 시작 전 ${expFuture} · 유지 ${expKept})`);
    const bizBefore = await read(`businesses/${biz}`);
    check('A-2', bizBefore.isApproved === true && bizBefore.deactivatedAt == null, '사전 조회는 쓰지 않는다');
    const other = uid('o');
    const pvDenied = await call('callableArchiveOwnBusiness', other, {businessId: biz, preview: true});
    check('A-3', /permission-denied/.test(pvDenied.err || ''), `소유자가 아니면 사전 조회도 거부 — ${(pvDenied.err || 'OK').slice(0, 40)}`);

    // A-4.. 실행 → 실제 연쇄
    // 앱과 같이 확인한 사전 조회(A-1)를 expected 로 보낸다 — 서버가 원장을 다시 세어 대조한다.
    const r = await call('callableArchiveOwnBusiness', owner, {businessId: biz, expected: P});
    check('A-4', r.ok && r.ok.success === true, `운영 종료 ${JSON.stringify(r.ok || r.err)}`);
    await until(async () => (await read(`applications/${apps.future}`)).status === 'CANCELED' &&
      (await read(`employment_contracts/${cFuture}`)).status === 'voided', 120000);
    await sleep(5000);
    const st = {};
    for (const [k, id] of Object.entries(apps)) st[k] = (await read(`applications/${id}`)).status;
    check('A-5', st.past === 'CONFIRMED' && st.pastUtc === 'CONFIRMED' && st.worked === 'CONFIRMED' && st.cpPast === 'CONTRACT_PENDING' &&
      (!canToday || st.todayStarted === 'CONFIRMED'),
    `예정 시작이 지난 확정은 보존(근태 기록 없어도) — ${JSON.stringify({past: st.past, pastUtc: st.pastUtc, worked: st.worked, cpPast: st.cpPast, todayStarted: st.todayStarted})}`);
    check('A-6', st.future === 'CANCELED' && st.cpFuture === 'CANCELED' && (!canToday || st.todayLater === 'CANCELED'),
      `시작 전 확정은 취소 — ${JSON.stringify({future: st.future, cpFuture: st.cpFuture, todayLater: st.todayLater})}`);
    check('A-7', st.pending === 'REJECTED', `대기 지원 → ${st.pending}`);
    const [cf, cp] = [await read(`employment_contracts/${cFuture}`), await read(`employment_contracts/${cPast}`)];
    check('A-8', cf.status === 'voided' && cp.status === 'pending_worker', `미서명 계약: 취소 건 ${cf.status} · 보존 건 ${cp.status}(서명으로 마무리 가능)`);
    const noteOf = async (key) => {
      const a = await read(`applications/${apps[key]}`);
      const n = await db.doc(`users/${a.uid}/notifications/biz_end_${apps[key]}`).get();
      return n.exists ? n.get('type') : '없음';
    };
    const nf = await noteOf('future'); const np = await noteOf('pending'); const nk = await noteOf('past');
    check('A-9', nf === 'confirmationCanceled' && np === 'applicationRejected' && nk === '없음',
      `알림: 취소 ${nf} · 대기 ${np} · 보존 ${nk}`);
    const toD = await read(`tos/${to}`);
    check('A-10', toD.status === 'CLOSED' && toD.closedReason === 'BUSINESS_DEACTIVATED', `공고 ${toD.status}/${toD.closedReason}`);
    const re = await call('callableArchiveOwnBusiness', owner, {businessId: biz, preview: true});
    check('A-11', re.ok && re.ok.alreadyArchived === true && re.ok.preview.futureConfirmed === 0,
      `종료 뒤 사전 조회: 이미 종료 · 시작 전 확정 ${re.ok && re.ok.preview.futureConfirmed}`);
  }
  for (const r of rows) log(r);
  log(`\n통과 ${pass} / 실패 ${fail}`);
  process.exit(fail ? 1 : 0);
})().catch((e) => { log('ERR ' + e.stack); process.exit(2); });
