/**
 * [WORKTYPE-MUTATION] 운영 중 사업장의 업무유형 이름 변경·비활성화·같은 이름 재사용 — 기존 공고·지원서 스냅샷과
 *   서버 판정(이름 대조 assertWorkTypesInBusiness · 공고 준비 NO_ACTIVE_WORK_TYPE)이 어떻게 갈리는가.
 *
 *   업무유형 변경은 앱이 Firestore 에 직접 쓴다(update name / isActive:false). 하네스는 그 결과 상태를 Admin SDK 로
 *   만들고(같은 필드), 서버 writer 는 번들의 `.run` 으로 부른다. R 셀만 REST(서명 없는 에뮬레이터 토큰)로 Rules 를 잰다.
 *   번들마다 initializeApp → 자식 프로세스 하나씩.
 *     DEV=<DEV 배포본 lib/index.js> LOCAL=<작업 트리 lib/index.js> RULES_DEV=<DEV 원문> node scripts/worktype-mutation-snapshot-runtime.js
 */
'use strict';
const fs = require('fs');
const path = require('path');
const http = require('http');
const ROOT = path.join(__dirname, '..');
const PROJECT = 'demo-alfit-r7';
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:6070';
process.env.GCLOUD_PROJECT = PROJECT;
process.env.FIREBASE_CONFIG = JSON.stringify({projectId: PROJECT, storageBucket: 'demo-alfit-r7.appspot.com'});
process.env.FIREBASE_STORAGE_EMULATOR_HOST = '127.0.0.1:6071';
delete process.env.GOOGLE_APPLICATION_CREDENTIALS;
for (const line of fs.readFileSync(path.join(ROOT, 'functions', '.env.demo-alfit-r7'), 'utf8').split(/\r?\n/)) {
  const m = /^([A-Z0-9_]+)=(.*)$/.exec(line); if (m) process.env[m[1]] = m[2];
}
const log = console.log; console.error = () => {}; console.warn = () => {}; console.log = () => {}; console.info = () => {};
process.env.NODE_PATH = path.join(ROOT, 'functions', 'node_modules');
require('module').Module._initPaths();
const admin = require(path.join(ROOT, 'functions', 'node_modules', 'firebase-admin'));
const LABEL = process.env.LABEL;
const fn = LABEL ? require(process.env[LABEL]) : null;
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
const {Timestamp} = admin.firestore;

const RUN = 'wm' + Date.now().toString(36);
const K = 9 * 3600e3; const NOW = Date.now(); const DAY = 86400e3;
const kstMidnight = (ms) => { const d = new Date(ms + K); return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()) - K; };
const TODAY = kstMidnight(NOW);
let seq = 0;
const uid = (p) => `${p}-${RUN}-${++seq}`;
const read = async (p) => (await db.doc(p).get()).data();
async function call(name, who, data) {
  if (!fn[name]) return {err: 'NO_FUNCTION'};
  try { return {ok: await fn[name].run({auth: {uid: who, token: {}}, rawRequest: {headers: {}}, data})}; } catch (e) {
    return {err: (e.details && (e.details.code || e.details.reason)) || `${e.code || ''}:${String(e.message).slice(0, 70)}`};
  }
}
const RULES = {earlyWindow: 30, earlyArrivalUnit: 10, lateGrace: 5, lateUnit: 10, lateWindow: 600, overtimeUnit: 10, earlyLeaveUnit: 10};
/** 공개 준비가 끝난 사업장. wts: [[id, name, isActive]] */
async function biz(wts = [['wt1', 'QA', true]]) {
  const b = uid('b'); const owner = uid('o');
  await db.doc(`users/${owner}`).set({role: 'BUSINESS_ADMIN', sealBase64: 'x', businessId: b, name: 'owner'});
  const lic = `businesses/${b}/license/license.jpg`;
  await admin.storage().bucket().file(lic).save(Buffer.from('x'));
  await db.doc(`businesses/${b}`).set({isApproved: true, ownerId: owner, adminIds: [owner], name: 'biz', city: '평택시',
    address: '경기도 평택시 1', attendanceRules: RULES, latitude: 37, longitude: 127, gpsRadius: 100, deactivatedAt: null,
    attendancePolicyConfirmation: Object.assign({confirmedAt: Timestamp.now(), confirmedBy: owner, actorRole: 'business_admin'}, RULES),
    businessLicenseImageUrl: `https://firebasestorage.googleapis.com/v0/b/demo-alfit-r7.appspot.com/o/${encodeURIComponent(lic)}?alt=media`});
  for (const [id, name, act] of wts) await db.doc(`businesses/${b}/workTypes/${id}`).set({isActive: act, name, businessId: b, icon: '📦', displayOrder: 0});
  await db.doc(`businesses/${b}/contract_templates/tpl`).set({templateType: 'daily'});
  return {b, owner};
}
const wd = (o = {}) => Object.assign({workType: 'QA', startTime: '09:00', endTime: '18:00', requiredCount: 1, wage: 12000, wageType: 'hourly',
  payScheduleType: 'next_day', workTypeIcon: '📦'}, o);
const toData = (x, o = {}) => Object.assign({businessId: x.b, businessName: 'biz', type: 'contract', title: `[${RUN}]`, description: 'wm',
  workDetails: [wd()], totalSlots: 0, totalRequired: 1, totalConfirmed: 0, totalPending: 0,
  rangeStart: Timestamp.fromMillis(TODAY + 3 * DAY), rangeEnd: Timestamp.fromMillis(TODAY + 30 * DAY), workDays: ['월', '화', '수', '목', '금', '토', '일'],
  deadlineType: 'HOURS_BEFORE', hoursBeforeStart: 2, contractPeriodType: 'custom', postingDurationDays: 30,
  creatorUID: x.owner, isPublished: true, status: 'ACTIVE', isManualClosed: false, editRevision: 0, createdAt: Timestamp.now()}, o);
const createInput = (x) => {
  const d = toData(x, {publishMode: 'immediate'});
  return Object.assign(d, {rangeStart: TODAY + 3 * DAY, rangeEnd: TODAY + 30 * DAY});
};
const rename = (x, id, name) => db.doc(`businesses/${x.b}/workTypes/${id}`).update({name});
const deactivate = (x, id) => db.doc(`businesses/${x.b}/workTypes/${id}`).update({isActive: false});
async function seedTo(x, o = {}) { const t = uid('t'); await db.doc(`tos/${t}`).set(toData(x, o)); return t; }
async function seedApp(x, t, status) {
  const a = uid('a'); const w = uid('w');
  await db.doc(`applications/${a}`).set({uid: w, businessId: x.b, toId: t, status, type: 'long_term', isLongTerm: true, selectedWorkType: 'QA',
    workDetailId: 'QA_09:00_18:00', wage: 12000, wageType: 'hourly', startTime: '09:00', endTime: '18:00', workTypeIcon: '📦',
    workDate: Timestamp.fromMillis(TODAY + 3 * DAY), appliedAt: Timestamp.now(), businessName: 'biz'});
  return a;
}
const snap = async (t, apps) => {
  const d = await read(`tos/${t}`);
  const as = await Promise.all(apps.map((a) => read(`applications/${a}`)));
  return `공고 ${d.status}/${(d.workDetails || []).map((w) => `${w.workType}·${w.startTime}·${w.wage}`).join('+')} · 지원서 ${as.map((a) => `${a.status}:${a.selectedWorkType}·${a.wage}`).join(',')}`;
};
const editWd = (x, t, wds) => call('callableUpdateTO', x.owner, {toId: t, updates: {workDetails: wds}, expectedEditRevision: 0});

const CELLS = {
  // 사용 중인 업무유형 이름 변경 → 기존 공고 편집
  N1: async () => {
    const x = await biz(); const t = await seedTo(x);
    const apps = [await seedApp(x, t, 'PENDING'), await seedApp(x, t, 'CONFIRMED')];
    await rename(x, 'wt1', 'QA2');
    const before = await snap(t, apps);
    const desc = await call('callableUpdateTO', x.owner, {toId: t, updates: {description: '수정'}, expectedEditRevision: 0});
    return {out: `이름 변경 뒤 스냅샷: ${before}\n         설명만 수정 ${desc.err || 'OK'} → ${await snap(t, apps)}`};
  },
  N2: async () => {
    const x = await biz(); const t = await seedTo(x);
    await rename(x, 'wt1', 'QA2');
    const addOld = await editWd(x, t, [wd(), wd({startTime: '19:00', endTime: '22:00'})]);
    const t2 = await seedTo(x);
    const timeOld = await editWd(x, t2, [wd({startTime: '10:00'})]);
    const t3 = await seedTo(x);
    const addNew = await editWd(x, t3, [wd(), wd({workType: 'QA2', startTime: '19:00', endTime: '22:00'})]);
    return {out: `(지원자 없음) 기존 이름 QA 로 근무 추가 ${addOld.err || 'OK'} · QA 시간 변경 ${timeOld.err || 'OK'} · 새 이름 QA2 근무 추가 ${addNew.err || 'OK'}`};
  },
  // 마지막 활성 업무유형 비활성화
  L1: async () => {
    const x = await biz(); const tAct = await seedTo(x); const apps = [await seedApp(x, tAct, 'CONFIRMED')];
    const tSch = await seedTo(x, {status: 'SCHEDULED', isPublished: false, publishMode: 'scheduled', publishAt: Timestamp.fromMillis(NOW - 60e3)});
    const tDraft = await seedTo(x, {status: 'DRAFT', isPublished: false, publishMode: 'draft'});
    await deactivate(x, 'wt1');
    const create = await call('callableCreateTO', x.owner, {toData: createInput(x)});
    const pub = await call('callablePublishTO', x.owner, {toId: tDraft});
    try { await fn.masterScheduler.run({}); } catch (_) { /* allSettled */ }
    const s = await read(`tos/${tSch}`);
    return {out: `새 공고 생성 ${create.err || 'OK'} · 초안 공개 ${pub.err || 'OK'} · 예약 공고(시각 지남) → ${s.status}/게시 ${s.isPublished}/막힘 ${s.publishBlockedReason || '-'}\n` +
      `         운영 중 공고 ${await snap(tAct, apps)}`};
  },
  // 다른 활성 업무가 있을 때 — 자기 업무가 비활성인 예약 공고
  L2: async () => {
    const x = await biz([['wt1', 'QA', true], ['wt2', 'B', true]]);
    const tSch = await seedTo(x, {status: 'SCHEDULED', isPublished: false, publishMode: 'scheduled', publishAt: Timestamp.fromMillis(NOW - 60e3)});
    await deactivate(x, 'wt1');
    try { await fn.masterScheduler.run({}); } catch (_) { /* allSettled */ }
    const s = await read(`tos/${tSch}`);
    return {out: `QA 비활성 · B 활성 → 예약 공고(QA) ${s.status}/게시 ${s.isPublished}/막힘 ${s.publishBlockedReason || '-'}`};
  },
  // 같은 이름 재사용
  S1: async () => {
    const x = await biz(); const t = await seedTo(x);
    await deactivate(x, 'wt1');
    const before = await editWd(x, t, [wd(), wd({startTime: '19:00', endTime: '22:00'})]);
    await db.doc(`businesses/${x.b}/workTypes/wt9`).set({isActive: true, name: 'QA', businessId: x.b, icon: '🚚', displayOrder: 1});
    const t2 = await seedTo(x);
    const after = await editWd(x, t2, [wd(), wd({startTime: '19:00', endTime: '22:00'})]);
    return {out: `QA 비활성 뒤 QA 근무 추가 ${before.err || 'OK'} · 같은 이름 새 문서(wt9) 생성 뒤 ${after.err || 'OK'} (공고는 문서 id 를 들고 있지 않다)`};
  },
};

// 마지막 활성 업무 비활성화 / 직접 삭제 뒤 기존 공고의 지원·확정·초대
const F7 = ['earlyWindow', 'earlyArrivalUnit', 'lateGrace', 'lateUnit', 'lateWindow', 'overtimeUnit', 'earlyLeaveUnit'];
const FP = F7.map((k) => `${k}=${RULES[k]}`).join('|');
const ymdDash = (ms) => new Date(ms + K).toISOString().slice(0, 10);
async function worker(b, availDate) {
  const w = uid('w');
  await db.doc(`users/${w}`).set({uid: w, name: 'w', role: 'USER', accountStatus: 'active', passVerifiedAt: Timestamp.now(),
    isIdVerified: true, idCardImagePath: `id_cards/${w}/id.jpg`, bankName: '국민', accountNumber: 'enc', accountHolder: 'w',
    bankbookImagePath: `bankbooks/${w}/b.jpg`, termsConsentAt: Timestamp.now(), isBlacklisted: false, isForeign: false,
    idDocumentVersion: 1, bankbookDocumentVersion: 1, bankAccountVersion: 1, homeRegion: '경기도|평택시'});
  await db.doc(`businessApplicantDocumentReviews/${b}_${w}`).set({businessId: b, workerUid: w, idDecision: 'REVIEWED_OK', reviewedIdDocumentVersion: 1,
    bankDecision: 'REVIEWED_OK', reviewedBankbookDocumentVersion: 1, reviewedBankAccountVersion: 1});
  if (availDate) await db.doc(`worker_availability/${w}`).set({uid: w, inviteEnabled: true, inviteRegionKeys: ['경기도|평택시'], dates: [availDate]});
  return w;
}
const FWD = {wdId: 'wdA', workType: 'QA', startTime: '14:00', endTime: '15:00', requiredCount: 2, wage: 12000, wageType: 'hourly', payScheduleType: 'next_day'};
async function flexWorld(mutate) {
  const x = await biz(); await db.doc(`businesses/${x.b}`).update({district: '평택시'});
  const t = uid('t'); const d1 = TODAY + 2 * DAY;
  await db.doc(`tos/${t}`).set({businessId: x.b, businessName: 'biz', creatorUID: x.owner, type: 'flex', title: 't', status: 'ACTIVE', isPublished: true,
    publishMode: 'immediate', totalSlots: 1, totalRequired: 2, totalConfirmed: 0, totalPending: 0, dates: [ymdDash(d1)], workDetails: [FWD],
    businessCity: '평택시', createdAt: Timestamp.now(), editRevision: 0});
  await db.doc(`tos/${t}/slots/s1`).set({toId: t, status: 'open', isManualClosed: false, date: Timestamp.fromMillis(d1), workDetails: [FWD],
    workDetailCounts: {wdA: {pendingCount: 0, confirmedCount: 0}}, pendingCount: 0, confirmedCount: 0, editRevision: 0});
  await mutate(x);
  const wa = await worker(x.b, null);
  const ap = await call('callableApplyToTO', wa, {toId: t, slotId: 's1', businessId: x.b, businessName: 'biz', toTitle: 't', workDateMs: d1,
    selectedWorkType: 'QA', workDetailId: 'wdA', startTime: '14:00', endTime: '15:00', wage: 12000, wageType: 'hourly',
    idCardConsentGiven: true, documentAccessConsentGiven: true, documentAccessConsentVersion: '2026-09-18-v3', expectedAttendancePolicy: FP});
  const appId = ap.ok && (ap.ok.applicationId || ap.ok.id);
  const cf = appId ? await call('callableConfirmApplication', x.owner, {applicationId: appId, businessId: x.b}) : {err: '지원 없음'};
  const wi = await worker(x.b, ymdDash(d1));
  const iv = await call('callableInviteWorker', x.owner, {toId: t, businessId: x.b, targetUid: wi, slotId: 's1', workDate: ymdDash(d1),
    selectedWorkType: 'QA', workDetailStartTime: '14:00', workDetailEndTime: '15:00'});
  const app = appId ? await read(`applications/${appId}`) : null;
  return `지원 ${ap.err || 'OK'} · 확정 ${cf.err || 'OK'} → ${app ? `${app.status}:${app.selectedWorkType}·${app.wage}·${app.workDetailId || app.wdId}` : '-'} · 초대 ${iv.err || 'OK'} · ` +
    `새 공고 ${(await call('callableCreateTO', x.owner, {toData: createInput(x)})).err ? '막힘' : '생성됨'}`;
}
CELLS.L3 = async () => ({out: `유일한 업무 비활성화 → ${await flexWorld((x) => deactivate(x, 'wt1'))}`});
CELLS.L4 = async () => ({out: `유일한 업무 직접 삭제(Admin SDK, 앱의 직접 delete 와 같은 상태) → ${await flexWorld((x) => db.doc(`businesses/${x.b}/workTypes/wt1`).delete())}`});
CELLS.L0 = async () => ({out: `대조: 업무 그대로 → ${await flexWorld(async () => {})}`});

// ── Rules: 업무유형 직접 쓰기(DEV 원문)
function emuToken(u) {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url'); const now = Math.floor(Date.now() / 1000);
  return `${b64({alg: 'none', typ: 'JWT'})}.${b64({iss: `https://securetoken.google.com/${PROJECT}`, aud: PROJECT, auth_time: now, user_id: u, sub: u,
    iat: now, exp: now + 3600, firebase: {identities: {}, sign_in_provider: 'custom'}})}.`;
}
function req(method, p, body, token) {
  return new Promise((res, rej) => {
    const data = body ? JSON.stringify(body) : null;
    const r = http.request({host: '127.0.0.1', port: 6070, method, path: p, headers: Object.assign({'Content-Type': 'application/json'},
      token ? {Authorization: 'Bearer ' + token} : {}, data ? {'Content-Length': Buffer.byteLength(data)} : {})}, (x) => {
      const bufs = []; x.on('data', (c) => bufs.push(c)); x.on('end', () => res({status: x.statusCode}));
    });
    r.on('error', rej); if (data) r.write(data); r.end();
  });
}
const DBP = `projects/${PROJECT}/databases/(default)`;
const upd = async (p, fields, who) => (await req('POST', `/v1/${DBP}/documents:commit`, {writes: [{update: {name: `${DBP}/documents/${p}`,
  fields: Object.fromEntries(Object.entries(fields).map(([k, v]) => [k, typeof v === 'boolean' ? {booleanValue: v} : {stringValue: v}]))},
updateMask: {fieldPaths: Object.keys(fields)}, currentDocument: {exists: true}}]}, emuToken(who))).status === 200 ? 'ALLOW' : 'DENY';

(async () => {
  if (LABEL) {
    const out = {};
    for (const id of Object.keys(CELLS)) { try { out[id] = await CELLS[id](); } catch (e) { out[id] = {out: 'THROW ' + e.message}; } }
    log('@@' + JSON.stringify(out)); process.exit(0);
  }
  const {execFileSync} = require('child_process');
  for (const L of ['DEV', 'LOCAL']) {
    const o = execFileSync(process.execPath, [__filename], {env: Object.assign({}, process.env, {LABEL: L}), maxBuffer: 1 << 26}).toString();
    const got = JSON.parse(o.split('@@').pop());
    log(`\n━━ 서버 번들 ${L}`);
    for (const [id, v] of Object.entries(got)) log(`  ${id} ${v.out}`);
  }
  // Rules — 구·현재 앱이 실제로 보내는 요청 모양(같은 코드) + UI 에 없는 직접 요청
  const commitW = async (writes, who) => (await req('POST', `/v1/${DBP}/documents:commit`, {writes}, emuToken(who))).status === 200 ? 'ALLOW' : 'DENY';
  const sv = (v) => typeof v === 'boolean' ? {booleanValue: v} : typeof v === 'number' ? {integerValue: String(v)} : {stringValue: v};
  const createW = (p, f) => ({update: {name: `${DBP}/documents/${p}`, fields: Object.fromEntries(Object.entries(f).map(([k, v]) => [k, sv(v)]))},
    currentDocument: {exists: false}});
  for (const [label, file] of [['DEV 원문', process.env.RULES_DEV], ['작업 트리 firestore.rules', path.join(ROOT, 'firestore.rules')]]) {
    const r = await req('PUT', `/emulator/v1/projects/${PROJECT}:securityRules`, {rules: {files: [{name: 'firestore.rules', content: fs.readFileSync(file, 'utf8')}]}});
    if (r.status !== 200) throw new Error('rules ' + r.status);
    const x = await biz([['wt1', 'QA', true], ['wt2', 'B', true], ['wt3', 'C', true]]);
    const subOk = uid('sub'); const subNo = uid('sub'); const other = uid('o');
    await db.doc(`users/${subOk}`).set({role: 'USER', subAdminBusinessIds: [x.b], subAdminOf: [x.b]});
    await db.doc(`users/${subNo}`).set({role: 'USER', subAdminBusinessIds: [x.b], subAdminOf: [x.b]});
    await db.doc(`businesses/${x.b}/members/${subOk}`).set({permissions: {canManageTo: true}, canManageTo: true});
    await db.doc(`businesses/${x.b}/members/${subNo}`).set({permissions: {canManageTo: false}, canManageTo: false});
    await db.doc(`users/${other}`).set({role: 'BUSINESS_ADMIN'});
    const wt = (id) => `businesses/${x.b}/workTypes/${id}`;
    const row = {};
    for (const [who, u] of [['소유자', x.owner], ['SubAdmin(업무권한)', subOk], ['SubAdmin(권한 없음)', subNo], ['다른 사업장 관리자', other]]) {
      row[who] = [
        `추가 ${await commitW([createW(wt(uid('n')), {name: uid('N'), icon: '📦', isActive: true, businessId: x.b, displayOrder: 9})], u)}`,
        `이름·아이콘 ${await upd(wt('wt1'), {name: 'QA', icon: '🚚'}, u)}`,
        `안내 ${await upd(wt('wt1'), {description: 'd'}, u)}`,
        `순서 ${await commitW([{update: {name: `${DBP}/documents/${wt('wt1')}`, fields: {displayOrder: sv(1)}}, updateMask: {fieldPaths: ['displayOrder']}}], u)}`,
        `비활성 ${await upd(wt('wt3'), {isActive: false}, u)}`,
        `재활성(UI 없음) ${await upd(wt('wt3'), {isActive: true}, u)}`,
        `단건 delete(UI 없음) ${await commitW([{delete: `${DBP}/documents/${wt('wt2')}`}], u)}`,
      ].join(' · ');
      if ((await db.doc(wt('wt2')).get()).exists === false) await db.doc(wt('wt2')).set({isActive: true, name: 'B', businessId: x.b});
    }
    const dup = await upd(wt('wt2'), {name: 'QA'}, x.owner);
    const move = await upd(wt('wt1'), {businessId: 'elsewhere'}, x.owner);
    const active = (await db.collection(`businesses/${x.b}/workTypes`).where('isActive', '==', true).get()).docs.map((d) => d.get('name')).filter((n) => !/^N-/.test(n));
    log(`\n━━ Rules(${label})`);
    for (const [k, v] of Object.entries(row)) log(`  ${k}: ${v}`);
    log(`  소유자: 다른 활성 업무를 같은 이름으로 ${dup} · 다른 사업장으로 이동 ${move} → 활성 이름 [${active.join(', ')}]`);
  }
  await req('PUT', `/emulator/v1/projects/${PROJECT}:securityRules`, {rules: {files: [{name: 'firestore.rules', content: fs.readFileSync(path.join(ROOT, 'firestore.rules'), 'utf8')}]}});
  process.exit(0);
})().catch((e) => { log('ERR ' + e.stack); process.exit(2); });
