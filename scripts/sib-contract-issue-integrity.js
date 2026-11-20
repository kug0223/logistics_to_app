/**
 * [SERVER-INTEGRITY §4] 계약 발행 서버의 두 경계 — **저장된 문서로** 확인한다.
 *
 *   BLOCKER 1  클라이언트가 보낸 서버 소유 필드가 **저장되는가**
 *   BLOCKER 2  좌석을 반납한 지원서에 계약이 **발행되는가**
 *
 *   정제 함수를 직접 부르지 않는다. `functions/lib/index.js` 에서
 *   `callableFinalizeEmployerSignature` **핸들러를 그대로 떼어** 에뮬레이터
 *   Firestore 위에서 돌리고, 끝난 뒤 `employment_contracts` 문서를 읽는다.
 *
 *   격리: demo 프로젝트(127.0.0.1:6060). 공유 DEV 쓰기 0. Storage 는 stub.
 */
'use strict';

const PROJECT = 'demo-sib';
process.env.GCLOUD_PROJECT = PROJECT;
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:6060';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const admin = require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin'));

admin.initializeApp({projectId: PROJECT});
const db = admin.firestore();

// ── production 슬라이스 ────────────────────────────────────────────────
const LIB = fs.readFileSync(
    path.join(__dirname, '..', 'functions', 'lib', 'index.js'), 'utf8');

function sliceExport(name) {
  const re = new RegExp(`^exports\\.${name} = `, 'm');
  const m = re.exec(LIB);
  if (!m) throw new Error(`export ${name} 없음`);
  const from = m.index;
  const rest = LIB.slice(from + m[0].length);
  const next = /^exports\.[A-Za-z0-9_]+ = /m.exec(rest);
  return LIB.slice(from, next ? from + m[0].length + next.index : LIB.length);
}
function sliceFn(name) {
  const re = new RegExp(`^(?:async )?function ${name}\\(`, 'm');
  const m = re.exec(LIB);
  if (!m) throw new Error(`function ${name} 없음`);
  const from = m.index;
  const rest = LIB.slice(from);
  const end = /^\}/m.exec(rest.slice(1));
  return rest.slice(0, end ? end.index + 2 : rest.length);
}
function sliceConst(name) {
  const re = new RegExp(`^const ${name} = [\\s\\S]*?;\\n`, 'm');
  const m = re.exec(LIB);
  if (!m) throw new Error(`const ${name} 없음`);
  return m[0];
}
/** `onCall(opts, async (request) => {…})` 에서 핸들러만. 중괄호로 센다. */
function handlerOf(name) {
  const src = sliceExport(name);
  const i = src.indexOf('async (request)');
  if (i < 0) throw new Error(name + ' 핸들러 시작 없음');
  const open = src.indexOf('{', i);
  let depth = 0; let quote = null;
  for (let k = open; k < src.length; k++) {
    const c = src[k];
    if (quote) {
      if (c === '\\') { k++; continue; }
      if (c === quote) quote = null;
      continue;
    }
    if (c === '"' || c === '\'' || c === '`') { quote = c; continue; }
    if (c === '{') depth++;
    else if (c === '}') { depth--; if (depth === 0) return src.slice(i, k + 1); }
  }
  throw new Error(name + ' 본문 끝 없음');
}

class HttpsError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}

// Storage·알림은 stub — 이 하네스가 보는 것은 **Firestore 최종 문서**다.
const uploads = [];
// 핸들러는 `admin.storage().bucket()` 으로 버킷 **이름만** 쓴다(URL 조립).
//   실제 Storage 는 쓰지 않으므로 이름만 주는 stub 으로 충분하다.
const adminStub = new Proxy(admin, {
  get: (t, k) => k === 'storage'
      ? () => ({bucket: () => ({name: `${PROJECT}.appspot.com`})})
      : t[k],
});

const deps = {
  db, admin: adminStub, crypto,
  https_1: {HttpsError}, HttpsError,
  console: {log: () => {}, error: () => {}, warn: () => {}},
  // 업로드는 토큰만 돌려준다(실제 Storage 없음).
  _saveContractArtifact: async (p, bytes, type, token) => {
    uploads.push({path: p, bytes: bytes.length, type, token});
    return {path: p, token};
  },
  _deleteOwnAttemptArtifact: async () => {},
  srvPersistNotification: async () => {},
  assertBizAdmin: async () => ({callerData: {role: 'BUSINESS_ADMIN'}}),
  srvReadPaySchedule: () => null,
};

const build = new Function(...Object.keys(deps),
    sliceConst('CONTRACT_SEAT_STATUSES') +
    sliceConst('CONTRACT_ENDED_STATUSES') +
    sliceConst('CONTRACT_CLIENT_OWNED_FIELDS') +
    sliceFn('srvAppEligibleForContractIssue') +
    sliceFn('srvContractNotIssuedYet') +
    sliceFn('srvIssuedContractExists') +
    sliceFn('_newContractAttemptPrefix') +
    'return ' + handlerOf('callableFinalizeEmployerSignature') + ';');
const finalizeEmployer = build(...Object.values(deps));

// ── 판정 ────────────────────────────────────────────────────────────
const results = [];
let failures = 0;
function check(label, actual, expected, note) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) failures++;
  results.push({label, ok, actual, expected, ...(note ? {note} : {})});
}
const observe = (label, actual, note) =>
  results.push({label, ok: null, actual, expected: '관측(판정 보류)',
    ...(note ? {note} : {})});

const BIZ = 'biz_sib';
const ADMIN = 'admin_sib';
const WORKER = 'worker_sib';
let seq = 0;

const PNG = Buffer.from(
    '89504e470d0a1a0a0000000d49484452', 'hex').toString('base64');

async function makeApp(over = {}) {
  seq++;
  const id = `app_${String(seq).padStart(2, '0')}`;
  await db.collection('applications').doc(id).set({
    uid: WORKER, businessId: BIZ, toId: 'to1', slotId: 'slot1',
    workDetailId: 'wd1', status: 'CONTRACT_PENDING',
    startTime: '09:00', endTime: '18:00', wage: 12000, wageType: 'hourly',
    ...over,
  });
  return id;
}

/** 정상 클라이언트가 보내는 `contractData` + 주입값. */
function contractData(appId, inject = {}) {
  return {
    applicationId: appId, businessId: BIZ, workerId: WORKER,
    isLongTerm: false, toId: 'to1', workDetailId: 'wd1',
    slots: [{applicationId: appId, workDate: '2026-10-20',
      startTime: '09:00', endTime: '18:00', wage: 12000, wageType: 'hourly'}],
    applicationIds: [appId],
    snapshot: {businessName: 'QA', workerName: '근로자', workType: '홀서빙'},
    articles: [{title: '제1조', content: '내용'}],
    templateId: 'tpl1',
    ...inject,
  };
}

async function issue(contractId, data) {
  return finalizeEmployer({
    auth: {uid: ADMIN},
    data: {
      contractId, signatureBase64: PNG,
      isNewUnsaved: true, contractData: data,
    },
  });
}
const docOf = async (id) =>
  (await db.collection('employment_contracts').doc(id).get()).data();

async function reset() {
  for (const col of ['applications', 'employment_contracts']) {
    const s = await db.collection(col).get();
    for (const d of s.docs) await d.ref.delete();
  }
}

(async () => {
  await reset();

  // ══ 1. 정상 발행 ══
  {
    const appId = await makeApp();
    const cid = 'ct_ok';
    const res = await issue(cid, contractData(appId));
    const doc = await docOf(cid);
    check('SIB-01 유효한 CONTRACT_PENDING — 정상 발행',
        {success: res.success, status: doc.status, appId: doc.applicationId},
        {success: true, status: 'pending_worker', appId});
    check('SIB-02 업무 데이터는 그대로 저장된다',
        {slots: doc.slots.length, templateId: doc.templateId,
          articles: doc.articles.length, snapshot: doc.snapshot.workerName,
          isLongTerm: doc.isLongTerm, wdId: doc.workDetailId,
          appIds: doc.applicationIds},
        {slots: 1, templateId: 'tpl1', articles: 1, snapshot: '근로자',
          isLongTerm: false, wdId: 'wd1', appIds: [appId]});
    check('SIB-03 서버가 만든 경로·URL·시각이 들어간다',
        {hasPath: typeof doc.employerSignatureStoragePath === 'string' &&
            doc.employerSignatureStoragePath.startsWith(`contracts/${cid}/attempts/`),
        hasUrl: typeof doc.employerSignatureUrl === 'string' &&
            doc.employerSignatureUrl.includes('token='),
        hasHash: typeof doc.employerSignatureHash === 'string',
        signedAt: doc.employerSignedAt != null},
        {hasPath: true, hasUrl: true, hasHash: true, signedAt: true},
        '단계 A 구버전 호환 — URL 은 서버가 만들어 남긴다');
  }
  {
    const appId = await makeApp({status: 'CONFIRMED'});
    const res = await issue('ct_confirmed', contractData(appId));
    check('SIB-04 CONFIRMED 도 발행 대상이다', res.success, true);
  }

  // ══ 2. BLOCKER 1 — 주입 차단 (최종 문서 기준) ══
  {
    const appId = await makeApp();
    const cid = 'ct_inject';
    const evil = {
      pdfUrl: 'https://attacker.example/contract.pdf',
      pdfStoragePath: 'contracts/other/attempts/x/contract.pdf',
      employerSignatureStoragePath: 'contracts/other/attempts/x/sig.png',
      workerSignatureStoragePath: 'contracts/other/attempts/x/sigw.png',
      employerSignatureUrl: 'https://attacker.example/sig.png',
      workerSignatureUrl: 'https://attacker.example/sigw.png',
      employerSignatureHash: 'deadbeef',
      workerSignatureHash: 'deadbeef',
      status: 'completed',
      employerSignedAt: new Date(2000, 0, 1),
      workerSignedAt: new Date(2000, 0, 1),
      createdAt: new Date(2000, 0, 1),
      updatedAt: new Date(2000, 0, 1),
      pdfMigration: {revokedAt: new Date(2000, 0, 1)},
      signatureMigration: {employer: {revokedAt: new Date(2000, 0, 1)}},
      qaCanaryAt: new Date(2000, 0, 1),
      historicalOwnerUid: 'attacker',
      terminationStatus: 'APPROVED',
    };
    await issue(cid, contractData(appId, evil));
    const doc = await docOf(cid);
    check('SIB-10 임의 pdfUrl 이 저장되지 않는다',
        doc.pdfUrl === undefined, true,
        `실제=${JSON.stringify(doc.pdfUrl)}`);
    check('SIB-11 임의 Storage 경로가 저장되지 않는다',
        {pdf: doc.pdfStoragePath === undefined,
          worker: doc.workerSignatureStoragePath === undefined,
          employer: doc.employerSignatureStoragePath
              .startsWith(`contracts/${cid}/attempts/`)},
        {pdf: true, worker: true, employer: true},
        '사업주 서명 경로는 **서버가 만든 값**이어야 한다');
    check('SIB-12 서명 URL·hash 는 서버 값이다',
        {empUrl: !doc.employerSignatureUrl.includes('attacker'),
          wrkUrl: doc.workerSignatureUrl === undefined,
          empHash: doc.employerSignatureHash !== 'deadbeef',
          wrkHash: doc.workerSignatureHash === undefined},
        {empUrl: true, wrkUrl: true, empHash: true, wrkHash: true});
    check('SIB-13 상태·서명 시각을 주입할 수 없다',
        {status: doc.status,
          workerSignedAt: doc.workerSignedAt === undefined,
          employerSignedAtYear:
            doc.employerSignedAt.toDate().getFullYear() >= 2026},
        {status: 'pending_worker', workerSignedAt: true,
          employerSignedAtYear: true});
    check('SIB-14 생성·수정 시각은 서버 시계다',
        doc.createdAt.toDate().getFullYear() >= 2026, true);
    check('SIB-15 이관·QA metadata 를 심을 수 없다',
        {pdfMigration: doc.pdfMigration === undefined,
          signatureMigration: doc.signatureMigration === undefined,
          qaCanaryAt: doc.qaCanaryAt === undefined,
          historicalOwnerUid: doc.historicalOwnerUid === undefined},
        {pdfMigration: true, signatureMigration: true,
          qaCanaryAt: true, historicalOwnerUid: true});
    check('SIB-16 허용 목록 밖의 임의 필드도 들어가지 않는다',
        doc.terminationStatus === undefined, true,
        '지원서 소유 필드를 계약 문서에 심는 경로');
  }

  // ══ 3. BLOCKER 2 — 발행 자격 ══
  {
    const appId = await makeApp({staffingReleasedAt: new Date()});
    let code = null;
    try { await issue('ct_released', contractData(appId)); }
    catch (e) { code = e.code; }
    const doc = await docOf('ct_released');
    check('SIB-20 좌석 반납 지원서 — 발행 거부 + 문서 없음',
        {code, created: doc !== undefined},
        {code: 'failed-precondition', created: false});
  }
  for (const [label, over] of [
    ['취소', {status: 'CANCELED'}],
    ['자동취소', {status: 'AUTO_CANCELED'}],
    ['대기', {status: 'PENDING'}],
    ['해지 승인', {terminationStatus: 'APPROVED'}],
    ['퇴사 자동승인', {resignStatus: 'AUTO_APPROVED'}],
  ]) {
    const appId = await makeApp(over);
    const cid = `ct_rej_${seq}`;
    let code = null;
    try { await issue(cid, contractData(appId)); } catch (e) { code = e.code; }
    check(`SIB-21/${label} 발행 거부`,
        {code, created: (await docOf(cid)) !== undefined},
        {code: 'failed-precondition', created: false});
  }
  {
    // 해지 **요청**만 올라온 상태는 아직 끝난 관계가 아니다.
    const appId = await makeApp({terminationStatus: 'PENDING'});
    const res = await issue('ct_term_pending', contractData(appId));
    check('SIB-22 해지 요청 중(PENDING)은 여전히 발행 대상', res.success, true);
  }

  // ══ 4. 중복 발행 방지 ══
  for (const st of ['pending_worker', 'completed']) {
    const appId = await makeApp();
    await db.collection('employment_contracts').doc(`pre_${st}_${seq}`).set({
      businessId: BIZ, workerId: WORKER, applicationId: appId, status: st,
    });
    const cid = `ct_dup_${seq}`;
    let code = null;
    try { await issue(cid, contractData(appId)); } catch (e) { code = e.code; }
    check(`SIB-30/${st} 이미 발행됨 — 중복 차단`,
        {code, created: (await docOf(cid)) !== undefined},
        {code: 'already-exists', created: false});
  }

  // ══ 5. 교차 발행 차단 ══
  {
    const appId = await makeApp();
    let code = null;
    try {
      await issue('ct_cross', contractData(appId, {businessId: 'other_biz'}));
    } catch (e) { code = e.code; }
    check('SIB-40 다른 사업장 id 로는 발행할 수 없다', code,
        'permission-denied', '지원서의 businessId 와 불일치');
  }
  {
    let code = null;
    try {
      await issue('ct_noapp', contractData('app_does_not_exist'));
    } catch (e) { code = e.code; }
    check('SIB-41 없는 지원서 — not-found', code, 'not-found');
  }
  {
    const appId = await makeApp();
    let code = null;
    try {
      await issue('ct_crossworker', contractData(appId, {workerId: 'other_worker'}));
    } catch (e) { code = e.code; }
    check('SIB-42 다른 근로자 id 로는 발행할 수 없다', code, 'permission-denied');
  }

  // ══ 6. PREAUTH 이후 좌석 반납 — 트랜잭션 재검증 ══
  {
    const appId = await makeApp();
    const cid = 'ct_race';
    // 업로드 단계(=PREAUTH 이후, 트랜잭션 이전)에 좌석을 반납시킨다.
    const original = deps._saveContractArtifact;
    let fired = false;
    deps._saveContractArtifact = async (...a) => {
      if (!fired) {
        fired = true;
        await db.collection('applications').doc(appId)
            .update({staffingReleasedAt: new Date()});
      }
      return original(...a);
    };
    // 주입된 stub 을 쓰는 새 핸들러를 만든다.
    const h = build(...Object.values(deps));
    let code = null;
    try {
      await h({auth: {uid: ADMIN}, data: {contractId: cid,
        signatureBase64: PNG, isNewUnsaved: true,
        contractData: contractData(appId)}});
    } catch (e) { code = e.code; }
    deps._saveContractArtifact = original;
    check('SIB-50 PREAUTH 통과 뒤 좌석이 반납되면 트랜잭션이 막는다',
        {code, created: (await docOf(cid)) !== undefined},
        {code: 'failed-precondition', created: false},
        '트랜잭션 안에서 지원서를 다시 읽는다');
  }
  observe('SIB-51 실제 동시 커밋 경쟁',
      {reproduced: false},
      '이 에뮬레이터는 트랜잭션 충돌을 감지하지 않는다(RA-X0 기록). ' +
      'SIB-50 은 **순차** 상태 변경을 재현한 것이고, 두 트랜잭션이 같은 ' +
      '순간에 커밋하는 경쟁은 여기서 입증할 수 없다 → [C01] 은 OPEN 유지');

  // ── 출력 ──
  console.log('\n' + '═'.repeat(74));
  for (const r of results) {
    console.log(`${r.ok === null ? '관측' : (r.ok ? 'PASS' : 'FAIL')}  ${r.label}`);
    if (r.ok === null) console.log(`        ${JSON.stringify(r.actual)}`);
    if (r.ok === false) {
      console.log(`        기대: ${JSON.stringify(r.expected)}`);
      console.log(`        실제: ${JSON.stringify(r.actual)}`);
    }
    if (r.note) console.log(`        · ${r.note}`);
  }
  console.log('═'.repeat(74));
  console.log(`총 ${results.length}판정 / 실패 ${failures}`);
  process.exit(failures ? 1 : 0);
})().catch((e) => {
  console.log('오류:', e && e.stack ? e.stack.split('\n').slice(0, 10).join('\n') : e);
  process.exit(1);
});
