/**
 * [INVITE-DELETE-GUARD] tos·slots 직접 삭제 — **실제 firestore.rules 평가**.
 *
 *   격리 Firestore 에뮬레이터(demo-alfit-r7, 127.0.0.1:6070)에 rules 를 올리고
 *   서명 없는 에뮬레이터 토큰(r7-e11c0b-emu-rules.js 와 같은 방식)으로 REST 요청을
 *   보내 allow/deny 를 잰다. 같은 요청을 **이전 rules**(삭제 차단 세 곳을 되돌린
 *   사본), **철회된 호환 후보**(구 앱 롤백 모양만 허용하던 직전 후보 — 원문 복원)와
 *   **현재 rules** 에 차례로 보낸다 — 우회가 있었다는 것과 닫혔다는 것을 같은 셀로 보인다.
 *   Functions 에뮬레이터가 함께 떠 있으면 하드 삭제 뒤 실제 onTODeleted 연쇄도 관찰한다.
 *
 *   실행: firebase emulators:start --only firestore --project demo-alfit-r7 --config firebase.r7audit.json
 *         node scripts/invite-delete-rules-runtime.js
 *   끝나면 현재 firestore.rules 를 다시 올려 둔다.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const http = require('http');
const PROJECT = 'demo-alfit-r7';
process.env.GCLOUD_PROJECT = PROJECT;
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:6070';
const admin = require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin'));
if (!admin.apps.length) admin.initializeApp({projectId: PROJECT});
const db = admin.firestore();
const RULES_PATH = path.join(__dirname, '..', 'firestore.rules');
const RUN = 'dr' + Date.now().toString(36);

function emuToken(uid) {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  return `${b64({alg: 'none', typ: 'JWT'})}.${b64({iss: `https://securetoken.google.com/${PROJECT}`, aud: PROJECT,
    auth_time: now, user_id: uid, sub: uid, iat: now, exp: now + 3600, firebase: {identities: {}, sign_in_provider: 'custom'}})}.`;
}
function req(method, p, body, token) {
  return new Promise((res, rej) => {
    const data = body ? JSON.stringify(body) : null;
    const r = http.request({host: '127.0.0.1', port: 6070, method, path: p,
      headers: Object.assign({'Content-Type': 'application/json'}, token ? {Authorization: 'Bearer ' + token} : {},
        data ? {'Content-Length': Buffer.byteLength(data)} : {})}, (x) => {
      const bufs = []; x.on('data', (c) => bufs.push(c)); x.on('end', () => res({status: x.statusCode, body: Buffer.concat(bufs).toString('utf8')}));
    });
    r.on('error', rej); if (data) r.write(data); r.end();
  });
}
const loadRules = async (content) => {
  const r = await req('PUT', `/emulator/v1/projects/${PROJECT}:securityRules`, {rules: {files: [{name: 'firestore.rules', content}]}});
  if (r.status !== 200) throw new Error('rules 적재 실패 ' + r.status + ' ' + r.body.slice(0, 200));
};
const docPath = (p) => `/v1/projects/${PROJECT}/databases/(default)/documents/${p}`;

const CURRENT = fs.readFileSync(RULES_PATH, 'utf8');
// 이전 rules — 삭제 차단 세 곳(tos·slots·businesses)을 HEAD 문장으로 되돌린 사본(비교 기준)
const TO_BLOCK = /( *)\/\/ \[INVITE-DELETE-GUARD\] 공고 문서의[\s\S]*?allow delete: if false;/;
const SLOT_BLOCK = /( *)\/\/ \[INVITE-DELETE-GUARD\] 슬롯 문서의[\s\S]*?allow delete: if false;/;
const BIZ_BLOCK = /( *)\/\/ \[BUSINESS-ARCHIVE 2026-10-16\][\s\S]*?allow delete: if false;/;
function assertMarks(src) {
  for (const r of [TO_BLOCK, SLOT_BLOCK, BIZ_BLOCK]) if (!r.test(src)) throw new Error('현재 rules 에 수정 표지가 없다 ' + r);
}
const TO_HEAD = (i) => `${i}allow delete: if isLoggedIn() &&\n${i}                 (isAdminOf(resource.data.businessId) ||\n${i}                  (isSubAdminOf(resource.data.businessId) &&\n${i}                   subAdminCanManageTo(resource.data.businessId)) ||\n${i}                  isSuperAdmin());`;
function previousRules(src) {
  assertMarks(src);
  return src
    .replace(TO_BLOCK, (m, i) => TO_HEAD(i))
    .replace(SLOT_BLOCK, (m, i) => `${i}allow delete: if isLoggedIn() && (isToWriteAdmin(toId) || isSuperAdmin());`)
    .replace(BIZ_BLOCK, (m, i) => `${i}allow delete: if (isAdminOf(businessId) && resource.data.ownerId == request.auth.uid) || isSuperAdmin();`);
}
/** 철회된 호환 후보 — 직전 단계의 srvOldAppRollbackTarget 원문. rules 는 지원서를 못 보므로
 *  합계 0 이지만 REJECTED/CANCELED 이력이 있는 공고를 구별하지 못한다(§2 반례). */
function compatCandidateRules(src) {
  assertMarks(src);
  const fnText = `    function srvOldAppRollbackTarget(d) {
      return d != null &&
        d.get('isPublished', false) == false &&
        d.get('status', '') in ['SCHEDULED', 'DRAFT'] &&
        d.get('totalPending', 0) == 0 &&
        d.get('totalConfirmed', 0) == 0 &&
        d.get('isDeleted', false) != true &&
        d.get('createdAt', null) is timestamp &&
        request.time < d.createdAt + duration.value(15, 'm');
    }

    function isToWriteAdmin(toId) {`;
  if (!src.includes('    function isToWriteAdmin(toId) {')) throw new Error('isToWriteAdmin 표지 없음');
  return src
    .replace('    function isToWriteAdmin(toId) {', fnText)
    .replace(TO_BLOCK, (m, i) => `${i}allow delete: if isLoggedIn() && srvOldAppRollbackTarget(resource.data) &&\n${i}                 (isAdminOf(resource.data.businessId) ||\n${i}                  (isSubAdminOf(resource.data.businessId) &&\n${i}                   subAdminCanManageTo(resource.data.businessId)));`)
    .replace(SLOT_BLOCK, (m, i) => `${i}allow delete: if isLoggedIn() && isToWriteAdmin(toId) &&\n${i}                 srvOldAppRollbackTarget(get(/databases/$(database)/documents/tos/$(toId)).data);`);
}

(async () => {
  const biz = `b-${RUN}`;
  const A = {owner: `own-${RUN}`, sub: `sub-${RUN}`, subNo: `subno-${RUN}`, sup: `sup-${RUN}`, other: `oth-${RUN}`};
  await db.doc(`businesses/${biz}`).set({ownerId: A.owner, adminIds: [A.owner], name: 'b'});
  await db.doc(`users/${A.owner}`).set({role: 'BUSINESS_ADMIN'});
  await db.doc(`users/${A.sub}`).set({role: 'USER', subAdminBusinessIds: [biz]});
  await db.doc(`users/${A.subNo}`).set({role: 'USER', subAdminBusinessIds: [biz]});
  await db.doc(`users/${A.sup}`).set({role: 'SUPER_ADMIN'});
  await db.doc(`users/${A.other}`).set({role: 'USER'});
  await db.doc(`businesses/${biz}/members/${A.sub}`).set({permissions: {canManageTo: true}});
  await db.doc(`businesses/${biz}/members/${A.subNo}`).set({permissions: {canManageTo: false}});

  // 관계 조합: INVITED / PENDING / CONFIRMED / 없음 — rules 는 지원서를 볼 수 없으므로
  //   결과가 관계와 무관하다는 것 자체가 측정 대상이다.
  const RELS = ['INVITED', 'PENDING', 'CONFIRMED', 'NONE'];
  async function seedTo(rel, tag) {
    const to = `t-${RUN}-${tag}-${rel}`;
    await db.doc(`tos/${to}`).set({businessId: biz, status: 'ACTIVE', type: 'flex', title: 't', isPublished: true,
      createdAt: admin.firestore.Timestamp.now(), totalPending: rel === 'NONE' ? 0 : 1, totalConfirmed: rel === 'CONFIRMED' ? 1 : 0});
    await db.doc(`tos/${to}/slots/s1`).set({status: 'open'});
    if (rel !== 'NONE') await db.doc(`applications/${to}-a`).set({toId: to, slotId: 's1', businessId: biz, status: rel, uid: A.other});
    return to;
  }
  const actors = [['관리자', A.owner], ['SubAdmin(canManageTo)', A.sub], ['SubAdmin(권한 없음)', A.subNo], ['SUPER_ADMIN', A.sup], ['무관 USER', A.other]];
  const table = {};
  for (const [label, content] of [['이전', previousRules(CURRENT)], ['현재', CURRENT]]) {
    await loadRules(content);
    for (const rel of RELS) {
      for (const [an, au] of actors) {
        const tag = `${label === '이전' ? 'p' : 'c'}${an.length}`;
        const toA = await seedTo(rel, tag + 'x' + au.slice(0, 3));
        const slot = await req('DELETE', docPath(`tos/${toA}/slots/s1`), null, emuToken(au));
        const to = await req('DELETE', docPath(`tos/${toA}`), null, emuToken(au));
        const key = `${an} · 관계 ${rel}`;
        table[key] = table[key] || {};
        table[key][label] = `공고 ${to.status === 200 ? '삭제됨' : 'DENY'} / 슬롯 ${slot.status === 200 ? '삭제됨' : 'DENY'}`;
      }
    }
  }
  // [OLD-APP-COMPAT] 구 앱 생성 실패 롤백 모양 — 철회된 호환 후보와 현재 rules 에서 잰다.
  //   현재 rules 는 모두 DENY 다(rules 가 과거 관계 부재를 증명할 수 없어 예외를 철회).
  //   후보 쪽은 §2 반례: 합계 0 이지만 거절·취소 이력이 있는 공고도 허용되고,
  //   실제 onTODeleted 가 그 이력을 지운다.
  const T = admin.firestore.Timestamp;
  const rollbackShape = (o = {}) => Object.assign({businessId: biz, status: 'SCHEDULED', type: 'flex', title: 't',
    isPublished: false, publishMode: 'deferred', totalPending: 0, totalConfirmed: 0, createdAt: T.now()}, o);
  const CASES = [
    // [label, to 덮어쓰기, 행위자, 이력 지원서 status|null, 후보 기대, 현재 기대]
    ['롤백 모양 · 관리자', {}, A.owner, null, 'ALLOW', 'DENY'],
    ['롤백 모양 · SubAdmin(canManageTo)', {}, A.sub, null, 'ALLOW', 'DENY'],
    ['롤백 모양 · SubAdmin(권한 없음)', {}, A.subNo, null, 'DENY', 'DENY'],
    ['롤백 모양 · SUPER_ADMIN', {}, A.sup, null, 'DENY', 'DENY'],
    ['롤백 모양 · 무관 USER', {}, A.other, null, 'DENY', 'DENY'],
    ['초안(DRAFT) 롤백 모양 · 관리자', {status: 'DRAFT'}, A.owner, null, 'ALLOW', 'DENY'],
    ['★ 거절(REJECTED) 이력 · 합계 0 · 관리자', {}, A.owner, 'REJECTED', 'ALLOW', 'DENY'],
    ['★ 취소(CANCELED) 이력 · 합계 0 · 관리자', {}, A.owner, 'CANCELED', 'ALLOW', 'DENY'],
    ['초대 1건(totalPending 1) · 관리자', {totalPending: 1}, A.owner, 'INVITED', 'DENY', 'DENY'],
    ['확정 1건(totalConfirmed 1) · 관리자', {totalConfirmed: 1}, A.owner, 'CONFIRMED', 'DENY', 'DENY'],
    ['생성 20분 뒤 · 관리자', {createdAt: T.fromMillis(Date.now() - 20 * 60e3)}, A.owner, null, 'DENY', 'DENY'],
    ['공개된 공고 · 관리자', {isPublished: true, status: 'ACTIVE'}, A.owner, null, 'DENY', 'DENY'],
    ['soft delete 된 공고 · 관리자', {isDeleted: true}, A.owner, null, 'DENY', 'DENY'],
    ['createdAt 없음 · 관리자', {createdAt: null}, A.owner, null, 'DENY', 'DENY'],
  ];
  const compat = [];
  for (const [rulesLabel, content, idx] of [['철회된 후보', compatCandidateRules(CURRENT), 4], ['현재', CURRENT, 5]]) {
    await loadRules(content);
    for (const c of CASES) {
      const [label, o, who, hist] = c;
      const to = `t-${RUN}-compat-${compat.length}`;
      const d = rollbackShape(o); if (d.createdAt === null) delete d.createdAt;
      await db.doc(`tos/${to}`).set(d);
      await db.doc(`tos/${to}/slots/s1`).set({status: 'open'});
      if (hist) await db.doc(`applications/${to}-h`).set({toId: to, slotId: 's1', businessId: biz, status: hist, uid: A.other});
      const slot = await req('DELETE', docPath(`tos/${to}/slots/s1`), null, emuToken(who));
      const toR = await req('DELETE', docPath(`tos/${to}`), null, emuToken(who));
      const got = (slot.status === 200 && toR.status === 200) ? 'ALLOW' : (slot.status !== 200 && toR.status !== 200 ? 'DENY' : `MIXED(${slot.status}/${toR.status})`);
      compat.push({rulesLabel, label, expect: c[idx], got, to, hist});
    }
  }
  // 하드 삭제된 이력 공고 — 실제 onTODeleted 가 이력을 지우는지(Functions 에뮬레이터가 있을 때만 의미)
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  for (const c of compat.filter((x) => x.hist && x.got === 'ALLOW')) {
    let gone = false;
    for (let k = 0; k < 60 && !gone; k++) { gone = !(await db.doc(`applications/${c.to}-h`).get()).exists; if (!gone) await sleep(1000); }
    c.history = gone ? '★이력 삭제됨(onTODeleted)' : '이력 남음(60초 관찰 — 트리거 미기동 가능)';
  }
  // 사업장 직접 삭제 — 이전/현재
  const bizTable = [];
  for (const [rulesLabel, content] of [['이전', previousRules(CURRENT)], ['현재', CURRENT]]) {
    await loadRules(content);
    for (const [an, au] of [['소유자', A.owner], ['SUPER_ADMIN', A.sup], ['무관 USER', A.other]]) {
      const b = `b-${RUN}-del-${bizTable.length}`;
      await db.doc(`businesses/${b}`).set({ownerId: A.owner, adminIds: [A.owner], name: 'b'});
      const r = await req('DELETE', docPath(`businesses/${b}`), null, emuToken(au));
      bizTable.push({rulesLabel, an, got: r.status === 200 ? 'ALLOW' : 'DENY'});
    }
  }
  await loadRules(CURRENT); // 현재 rules 로 돌려 둔다
  let fail = 0;
  console.log('행위자 · 관계                         | 이전 rules              | 현재 rules');
  for (const [k, v] of Object.entries(table)) {
    console.log(`${k.padEnd(34)} | ${v['이전'].padEnd(22)} | ${v['현재']}`);
    if (v['현재'] !== '공고 DENY / 슬롯 DENY') fail++;
  }
  console.log(`\n현재 rules 에서 관계 있는 공고·슬롯 직접 삭제가 허용된 조합: ${fail}`);
  console.log('\n[구 앱 롤백 모양 — 철회된 호환 후보 vs 현재 rules]');
  for (const c of compat) {
    const ok = c.got === c.expect;
    if (!ok) fail++;
    console.log(`  ${ok ? 'ok  ' : 'FAIL'} [${c.rulesLabel}] ${c.label.padEnd(36)} 기대 ${c.expect} · 실제 ${c.got}${c.history ? ' · ' + c.history : ''}`);
  }
  console.log('\n[사업장 직접 삭제]');
  for (const b of bizTable) {
    const expect = b.rulesLabel === '현재' ? 'DENY' : (b.an === '무관 USER' ? 'DENY' : 'ALLOW');
    const ok = b.got === expect; if (!ok) fail++;
    console.log(`  ${ok ? 'ok  ' : 'FAIL'} [${b.rulesLabel}] ${b.an.padEnd(12)} 기대 ${expect} · 실제 ${b.got}`);
  }
  console.log(`\n실패 ${fail}`);
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.log('ERR ' + e.stack); process.exit(2); });
