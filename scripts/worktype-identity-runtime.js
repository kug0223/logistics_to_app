/**
 * [WORKTYPE-IDENTITY] 업무유형 id 연결 · D7 서버 경계 · D4 공개 관문 · 사진 정리 CF · 원장 불변 + Rules.
 *
 *   서버 셀은 BEFORE / AFTER 번들 각각 자식 프로세스에서 같은 seed 로 돈다(번들마다 initializeApp).
 *   Rules 셀은 REST(서명 없는 에뮬레이터 토큰)로 구·새 앱이 실제로 보내는 요청 모양을 잰다.
 *     BEFORE=<lib/index.js> AFTER=<lib/index.js> RULES_DEV=<DEV 원문> node scripts/worktype-identity-runtime.js
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
const bucket = () => admin.storage().bucket();

const RUN = 'wi' + Date.now().toString(36);
const K = 9 * 3600e3; const NOW = Date.now(); const DAY = 86400e3;
const kstMidnight = (ms) => { const d = new Date(ms + K); return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()) - K; };
const TODAY = kstMidnight(NOW);
const ymdDash = (ms) => new Date(ms + K).toISOString().slice(0, 10);
let seq = 0;
const uid = (p) => `${p}-${RUN}-${++seq}`;
const read = async (p) => (await db.doc(p).get()).data();
async function call(name, who, data) {
  if (!fn[name]) return {err: 'NO_FUNCTION'};
  try { return {ok: await fn[name].run({auth: {uid: who, token: {}}, rawRequest: {headers: {}}, data})}; } catch (e) {
    return {err: (e.details && (e.details.code || e.details.reason)) || `${e.code || ''}:${String(e.message).slice(0, 60)}`};
  }
}
const RULES = {earlyWindow: 30, earlyArrivalUnit: 10, lateGrace: 5, lateUnit: 10, lateWindow: 600, overtimeUnit: 10, earlyLeaveUnit: 10};
async function biz(wts = [['wt1', 'QA', true]]) {
  const b = uid('b'); const owner = uid('o');
  await db.doc(`users/${owner}`).set({role: 'BUSINESS_ADMIN', sealBase64: 'x', businessId: b, name: 'owner'});
  const lic = `businesses/${b}/license/license.jpg`;
  await bucket().file(lic).save(Buffer.from('x'));
  await db.doc(`businesses/${b}`).set({isApproved: true, ownerId: owner, adminIds: [owner], name: 'biz', city: '평택시', district: '평택시',
    address: '경기도 평택시 1', attendanceRules: RULES, latitude: 37, longitude: 127, gpsRadius: 100, deactivatedAt: null,
    attendancePolicyConfirmation: Object.assign({confirmedAt: Timestamp.now(), confirmedBy: owner, actorRole: 'business_admin'}, RULES),
    businessLicenseImageUrl: `https://firebasestorage.googleapis.com/v0/b/demo-alfit-r7.appspot.com/o/${encodeURIComponent(lic)}?alt=media`});
  for (const [id, name, act] of wts) {
    await db.doc(`businesses/${b}/workTypes/${id}`).set({isActive: act, name, businessId: b, icon: '📦', displayOrder: 0, createdAt: Timestamp.now()});
  }
  await db.doc(`businesses/${b}/contract_templates/tpl`).set({templateType: 'daily'});
  return {b, owner};
}
const wd = (o = {}) => Object.assign({workType: 'QA', startTime: '09:00', endTime: '18:00', requiredCount: 1, wage: 12000, wageType: 'hourly',
  payScheduleType: 'next_day', workTypeIcon: '📦'}, o);
const toData = (x, o = {}) => Object.assign({businessId: x.b, businessName: 'biz', type: 'contract', title: `[${RUN}]`, description: 'wi',
  workDetails: [wd()], totalSlots: 0, totalRequired: 1, totalConfirmed: 0, totalPending: 0,
  rangeStart: Timestamp.fromMillis(TODAY + 3 * DAY), rangeEnd: Timestamp.fromMillis(TODAY + 30 * DAY), workDays: ['월', '화', '수', '목', '금', '토', '일'],
  deadlineType: 'HOURS_BEFORE', hoursBeforeStart: 2, contractPeriodType: 'custom', postingDurationDays: 30,
  creatorUID: x.owner, isPublished: true, status: 'ACTIVE', isManualClosed: false, editRevision: 0, createdAt: Timestamp.now()}, o);
const createInput = (x, wds) => Object.assign(toData(x, {publishMode: 'immediate', workDetails: wds || [wd()]}),
  {rangeStart: TODAY + 3 * DAY, rangeEnd: TODAY + 30 * DAY});
async function seedTo(x, o = {}) { const t = uid('t'); await db.doc(`tos/${t}`).set(toData(x, o)); return t; }
const tosOf = async (x) => (await db.collection('tos').where('businessId', '==', x.b).get()).docs;
const ids = (wds) => (wds || []).map((w) => w.workTypeId || '∅').join(',');
async function seedApp(x, t, status) {
  const a = uid('a'); const w = uid('w');
  await db.doc(`applications/${a}`).set({uid: w, businessId: x.b, toId: t, status, type: 'long_term', isLongTerm: true, selectedWorkType: 'QA',
    workDetailId: 'QA_09:00_18:00', wage: 12000, wageType: 'hourly', startTime: '09:00', endTime: '18:00',
    workDate: Timestamp.fromMillis(TODAY + 3 * DAY), appliedAt: Timestamp.now(), businessName: 'biz'});
  if (status === 'CONFIRMED') await db.doc(`tos/${t}`).update({totalConfirmed: 1});
  return a;
}
const imgUrl = (p) => `https://firebasestorage.googleapis.com/v0/b/demo-alfit-r7.appspot.com/o/${encodeURIComponent(p)}?alt=media&token=t1`;
const fileExists = async (p) => (await bucket().file(p).exists())[0];

const CELLS = {
  // ── 업무유형 id 기록
  ID1: async () => {
    const x = await biz();
    const r = await call('callableCreateTO', x.owner, {toData: createInput(x)});
    const t = (await tosOf(x))[0];
    return `구 앱 모양(id 없음) 생성 ${r.err || 'OK'} → 근무 id [${t ? ids(t.get('workDetails')) : '-'}]`;
  },
  ID2: async () => {
    const x = await biz([['wt1', 'QA', true], ['wt2', 'B', true]]);
    const ok = await call('callableCreateTO', x.owner, {toData: createInput(x, [wd({workTypeId: 'wt1'})])});
    const bad = await call('callableCreateTO', x.owner, {toData: createInput(x, [wd({workTypeId: 'wt2'})])});
    const ghost = await call('callableCreateTO', x.owner, {toData: createInput(x, [wd({workTypeId: 'nope'})])});
    const docs = await tosOf(x);
    return `새 앱 id=wt1 ${ok.err || 'OK'} · 이름 다른 id(wt2) ${bad.err || 'OK'} · 없는 id ${ghost.err || 'OK'} → 공고 ${docs.length}건 id [${docs.map((d) => ids(d.get('workDetails'))).join(' | ')}]`;
  },
  ID3: async () => {
    const x = await biz([['wt1', 'QA', true], ['wt9', 'QA', true]]);
    const r = await call('callableCreateTO', x.owner, {toData: createInput(x)});
    const t = (await tosOf(x))[0];
    return `같은 이름 활성 2개 · id 없음 생성 ${r.err || 'OK'} → 근무 id [${t ? ids(t.get('workDetails')) : '-'}] (모호하면 찍지 않음)`;
  },
  ID4: async () => {
    const x = await biz(); const t = uid('t');
    await db.doc(`tos/${t}`).set({businessId: x.b, creatorUID: x.owner, status: 'SCHEDULED', type: 'flex', isPublished: false, publishMode: 'scheduled',
      publishAt: Timestamp.fromMillis(NOW + DAY), title: 't', totalRequired: 0, totalSlots: 0, totalConfirmed: 0, totalPending: 0, createdAt: Timestamp.now()});
    const r = await call('callableCreateFlexSlots', x.owner, {toId: t, businessId: x.b, dates: [ymdDash(TODAY + 4 * DAY)],
      workDetails: [wd({startTime: '14:00', endTime: '15:00'})], deadlineType: 'HOURS_BEFORE', hoursBeforeStart: 1});
    const sl = (await db.collection(`tos/${t}/slots`).get()).docs;
    return `슬롯 생성 ${r.err || 'OK'} → 슬롯 근무 id [${sl.map((s) => ids(s.get('workDetails'))).join(' | ')}]`;
  },
  ID5: async () => {
    const x = await biz([['wt1', 'QA', true], ['wt2', 'B', true]]);
    const t = await seedTo(x, {workDetails: [wd({workTypeId: 'wt1'})]});
    const r = await call('callableUpdateTO', x.owner, {toId: t, expectedEditRevision: 0,
      updates: {workDetails: [wd({workTypeId: 'wt2'}), wd({workType: 'B', startTime: '19:00', endTime: '22:00'})]}});
    const d = await read(`tos/${t}`);
    return `기존 근무 id 바꿔치기 + 새 근무(id 없음) ${r.err || 'OK'} → [${(d.workDetails || []).map((w) => `${w.workType}:${w.workTypeId || '∅'}`).join(', ')}]`;
  },
  // ── D7 서버 경계: 근무 업무를 A→B 로 보내면
  D7: async () => {
    const out = [];
    for (const st of [null, 'PENDING', 'CONFIRMED']) {
      const x = await biz([['wt1', 'QA', true], ['wt2', 'B', true]]);
      const t = await seedTo(x);
      if (st) await seedApp(x, t, st);
      const r = await call('callableUpdateTO', x.owner, {toId: t, expectedEditRevision: 0, updates: {workDetails: [wd({workType: 'B', wage: 13000})]}});
      const d = await read(`tos/${t}`);
      out.push(`${st || '지원 없음'}: ${r.err ? '거절' : 'OK'} → ${(d.workDetails || []).map((w) => `${w.workType}·${w.wage}`).join(',')}`);
    }
    return out.join(' · ');
  },
  // ── D4: 마지막 활성 업무유형 비활성화 뒤
  D4: async () => {
    const x = await biz();
    const tSch = await seedTo(x, {status: 'SCHEDULED', isPublished: false, publishMode: 'scheduled', publishAt: Timestamp.fromMillis(NOW - 60e3)});
    const tDraft = await seedTo(x, {status: 'DRAFT', isPublished: false, publishMode: 'draft'});
    await db.doc(`businesses/${x.b}/workTypes/wt1`).update({isActive: false});
    const create = await call('callableCreateTO', x.owner, {toData: createInput(x)});
    const pub = await call('callablePublishTO', x.owner, {toId: tDraft});
    try { await fn.masterScheduler.run({}); } catch (_) { /* allSettled */ }
    const s = await read(`tos/${tSch}`); const dr = await read(`tos/${tDraft}`);
    return `새 공고 ${create.err ? '막힘' : '생성'} · 초안 공개 ${pub.err ? '막힘(' + String(pub.err).slice(0, 40) + ')' : 'OK'}→${dr.status} · 예약 공개 → ${s.status}/막힘 ${s.publishBlockedReason || '-'}`;
  },
  D4b: async () => {
    // 다른 공개 조건은 그대로 — 근태 기준 확인이 없으면 초안 공개는 여전히 막힌다
    const x = await biz();
    await db.doc(`businesses/${x.b}`).update({attendancePolicyConfirmation: admin.firestore.FieldValue.delete()});
    const tDraft = await seedTo(x, {status: 'DRAFT', isPublished: false, publishMode: 'draft'});
    await db.doc(`businesses/${x.b}/workTypes/wt1`).update({isActive: false});
    const pub = await call('callablePublishTO', x.owner, {toId: tDraft});
    return `근태 기준 미확인 + 업무 비활성 → 초안 공개 ${pub.err ? '막힘(' + String(pub.err).slice(0, 50) + ')' : 'OK'}`;
  },
  // ── 사진 정리 CF
  IMG: async () => {
    const x = await biz();
    const p1 = `businesses/${x.b}/${RUN}-thumb.jpg`; const p2 = `businesses/${x.b}/${RUN}-img.jpg`; const p3 = `businesses/${x.b}/${RUN}-new.jpg`;
    const p4 = `businesses/${x.b}/${RUN}-bizphoto.jpg`;
    for (const p of [p1, p2, p3, p4]) await bucket().file(p).save(Buffer.from('x'));
    await db.doc(`businesses/${x.b}/workTypes/wt1`).update({thumbnailUrl: imgUrl(p1), images: [imgUrl(p2)]});
    // 구 앱 비활성화: isActive:false 뒤 문서의 사진을 CF 로 지운다
    await db.doc(`businesses/${x.b}/workTypes/wt1`).update({isActive: false});
    const r1 = await call('callableDeleteBusinessImage', x.owner, {imageUrl: imgUrl(p1)});
    const r2 = await call('callableDeleteBusinessImage', x.owner, {imageUrl: imgUrl(p2).replace('token=t1', 'token=other')});
    const afterDeact = `대표 ${await fileExists(p1) ? '남음' : '삭제'} · 추가 ${await fileExists(p2) ? '남음' : '삭제'}`;
    // 사진 교체: 문서를 새 사진으로 먼저 고친 뒤 옛 대표 사진 정리
    await db.doc(`businesses/${x.b}/workTypes/wt1`).update({thumbnailUrl: imgUrl(p3)});
    const r3 = await call('callableDeleteBusinessImage', x.owner, {imageUrl: imgUrl(p1)});
    const r4 = await call('callableDeleteBusinessImage', x.owner, {imageUrl: imgUrl(p4)});
    void r1; void r2; void r3; void r4;
    return `비활성화 뒤 사진 삭제 요청 → ${afterDeact} | 교체 뒤 옛 대표 ${await fileExists(p1) ? '남음' : '삭제'} · 새 대표 ${await fileExists(p3) ? '남음' : '삭제'} · 업무와 무관한 사업장 사진 ${await fileExists(p4) ? '남음' : '삭제'}`;
  },
  // ── 원장 불변: 업무유형 설명·사진 수정 + 비활성화 뒤 공고·지원·계약·근태
  INV: async () => {
    const x = await biz(); const t = await seedTo(x, {workDetails: [wd({workTypeId: 'wt1'})]});
    const a = await seedApp(x, t, 'CONFIRMED'); const c = uid('c');
    await db.doc(`employment_contracts/${c}`).set({businessId: x.b, applicationId: a, workType: 'QA', wage: 12000, wageType: 'hourly', workDetailId: 'QA_09:00_18:00', status: 'completed'});
    await db.doc(`attendance/${a}_d`).set({applicationId: a, businessId: x.b, workType: 'QA', wageStatus: 'confirmed', wageDetail: {netWage: 100000}});
    const snap = async () => JSON.stringify([(await read(`tos/${t}`)).workDetails, await read(`applications/${a}`), await read(`employment_contracts/${c}`), await read(`attendance/${a}_d`)]);
    const before = await snap();
    await db.doc(`businesses/${x.b}/workTypes/wt1`).update({description: '새 설명', images: ['x'], thumbnailUrl: 'y', isActive: false});
    try { await fn.masterScheduler.run({}); } catch (_) { /* allSettled */ }
    return `업무유형 설명·사진 수정 + 비활성화 + 스케줄러 뒤 공고 근무·지원서·계약·근태 원장 ${before === await snap() ? '동일' : '변경됨'}`;
  },
};

// ── Rules
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
      const bufs = []; x.on('data', (c) => bufs.push(c)); x.on('end', () => res({status: x.statusCode, body: Buffer.concat(bufs).toString('utf8')}));
    });
    r.on('error', rej); if (data) r.write(data); r.end();
  });
}
const DBP = `projects/${PROJECT}/databases/(default)`;
const sv = (v) => typeof v === 'boolean' ? {booleanValue: v} : typeof v === 'number' ? {integerValue: String(v)} : Array.isArray(v) ?
  {arrayValue: {values: v.map(sv)}} : v === null ? {nullValue: null} : {stringValue: v};
const fields = (f) => Object.fromEntries(Object.entries(f).map(([k, v]) => [k, sv(v)]));
const commitW = async (writes, who) => (await req('POST', `/v1/${DBP}/documents:commit`, {writes}, emuToken(who))).status === 200 ? 'ALLOW' : 'DENY';
const updW = (p, f) => ({update: {name: `${DBP}/documents/${p}`, fields: fields(f)}, updateMask: {fieldPaths: Object.keys(f)}, currentDocument: {exists: true}});
const createW = (p, f) => ({update: {name: `${DBP}/documents/${p}`, fields: fields(f)}, currentDocument: {exists: false}});
const delW = (p) => ({delete: `${DBP}/documents/${p}`});
async function getAs(p, who) { return (await req('GET', `/v1/${DBP}/documents/${p}`, null, emuToken(who))).status === 200 ? 'ALLOW' : 'DENY'; }
async function listAs(parent, coll, who) {
  const r = await req('POST', `/v1/${DBP}/documents/${parent}:runQuery`, {structuredQuery: {from: [{collectionId: coll}], limit: 300}}, emuToken(who));
  return r.status === 200 ? 'ALLOW' : 'DENY';
}

async function rulesCells(label, file) {
  const r = await req('PUT', `/emulator/v1/projects/${PROJECT}:securityRules`, {rules: {files: [{name: 'firestore.rules', content: fs.readFileSync(file, 'utf8')}]}});
  if (r.status !== 200) throw new Error('rules ' + r.status + ' ' + label);
  const x = await biz([['wt1', 'QA', true], ['wt2', 'B', true]]);
  const subOk = uid('sub'); const subNo = uid('sub'); const worker = uid('w');
  await db.doc(`users/${subOk}`).set({role: 'USER', subAdminBusinessIds: [x.b], subAdminOf: [x.b]});
  await db.doc(`users/${subNo}`).set({role: 'USER', subAdminBusinessIds: [x.b], subAdminOf: [x.b]});
  await db.doc(`businesses/${x.b}/members/${subOk}`).set({permissions: {canManageTo: true}, canManageTo: true});
  await db.doc(`businesses/${x.b}/members/${subNo}`).set({permissions: {canManageTo: false}, canManageTo: false});
  await db.doc(`users/${worker}`).set({role: 'USER'});
  const wt = (id) => `businesses/${x.b}/workTypes/${id}`;
  const rows = [];
  for (const [who, u] of [['소유자', x.owner], ['SubAdmin(업무권한)', subOk], ['SubAdmin(권한 없음)', subNo]]) {
    const cells = [
      `추가 ${await commitW([createW(wt(uid('n')), {name: uid('N'), icon: '📦', isActive: true, businessId: x.b, displayOrder: 9})], u)}`,
      `같은 이름 추가 ${await commitW([createW(wt(uid('d')), {name: 'QA', icon: '📦', isActive: true, businessId: x.b, displayOrder: 9})], u)}`,
      // 구 앱 '아이콘수정' 시트는 name·icon·color·backgroundColor 네 칸을 항상 보낸다
      `구 앱 시트(값 그대로) ${await commitW([updW(wt('wt1'), {name: 'QA', icon: '📦'})], u)}`,
      `이름 변경 ${await commitW([updW(wt('wt1'), {name: 'QA-renamed'})], u)}`,
      `아이콘 변경 ${await commitW([updW(wt('wt1'), {icon: '🚚'})], u)}`,
      `색 변경 ${await commitW([updW(wt('wt1'), {color: '#FF0000'})], u)}`,
      `안내·사진 ${await commitW([updW(wt('wt1'), {description: 'd', oneLineIntro: 'o', thumbnailUrl: 'https://x/a.jpg', images: ['https://x/b.jpg']})], u)}`,
      `순서 ${await commitW([updW(wt('wt1'), {displayOrder: 3})], u)}`,
      `비활성 ${await commitW([updW(wt('wt2'), {isActive: false})], u)}`,
      `재활성 ${await commitW([updW(wt('wt2'), {isActive: true})], u)}`,
      `단건 delete ${await commitW([delW(wt('wt2'))], u)}`,
    ];
    if (!(await db.doc(wt('wt2')).get()).exists) await db.doc(wt('wt2')).set({isActive: true, name: 'B', businessId: x.b, icon: '📦', createdAt: Timestamp.now()});
    if ((await read(wt('wt1'))).name !== 'QA') await db.doc(wt('wt1')).update({name: 'QA', icon: '📦'});
    rows.push(`  ${who}: ${cells.join(' · ')}`);
  }
  // 구 앱 사업장 삭제 batch(업무유형+멤버) — 업무유형 delete 가 막히면 batch 통째로 거절
  const y = await biz([['wt1', 'QA', true]]); const ys = uid('sub');
  await db.doc(`businesses/${y.b}/members/${ys}`).set({permissions: {}});
  const batch = await commitW([delW(`businesses/${y.b}/workTypes/wt1`), delW(`businesses/${y.b}/members/${ys}`)], y.owner);
  const z = await biz([]); const zs = uid('sub');
  await db.doc(`businesses/${z.b}/members/${zs}`).set({permissions: {}});
  const membersOnly = await commitW([delW(`businesses/${z.b}/members/${zs}`)], z.owner);
  const bizDel = await commitW([delW(`businesses/${z.b}`)], z.owner);
  rows.push(`  구 앱 사업장 삭제: 업무유형+멤버 batch ${batch} · (업무유형 0개 사업장) 멤버만 batch ${membersOnly} → 사업장 delete ${bizDel}`);
  // 기존 공고 읽기: 근로자가 비활성 업무유형 문서·전체 목록을 읽을 수 있나
  await db.doc(wt('wt2')).update({isActive: false});
  rows.push(`  근로자 읽기: 비활성 문서 get ${await getAs(wt('wt2'), worker)} · 전체 목록(필터 없음) ${await listAs(`businesses/${x.b}`, 'workTypes', worker)}`);
  log(`\n━━ Rules(${label})`); for (const l of rows) log(l);
}

(async () => {
  if (LABEL) {
    const out = {};
    for (const id of Object.keys(CELLS)) { try { out[id] = await CELLS[id](); } catch (e) { out[id] = 'THROW ' + e.message; } }
    log('@@' + JSON.stringify(out)); process.exit(0);
  }
  const {execFileSync} = require('child_process');
  const got = {};
  for (const L of ['BEFORE', 'AFTER']) {
    const o = execFileSync(process.execPath, [__filename], {env: Object.assign({}, process.env, {LABEL: L}), maxBuffer: 1 << 26}).toString();
    got[L] = JSON.parse(o.split('@@').pop());
  }
  for (const id of Object.keys(CELLS)) log(`${id}\n   BEFORE → ${got.BEFORE[id]}\n   AFTER  → ${got.AFTER[id]}`);
  for (const [label, file] of [['DEV 원문', process.env.RULES_DEV], ['후보 worktype-identity', path.join(ROOT, 'rules_candidates', 'firestore.worktype-identity.rules')],
    ['후보 worktype-identity-containment', path.join(ROOT, 'rules_candidates', 'firestore.worktype-identity-containment.rules')],
    ['작업 트리 firestore.rules', path.join(ROOT, 'firestore.rules')]]) await rulesCells(label, file);
  await req('PUT', `/emulator/v1/projects/${PROJECT}:securityRules`, {rules: {files: [{name: 'firestore.rules', content: fs.readFileSync(path.join(ROOT, 'firestore.rules'), 'utf8')}]}});
  process.exit(0);
})().catch((e) => { log('ERR ' + e.stack); process.exit(2); });
