/**
 * [R7-REVIEW-ELIGIBILITY-ISSUANCE-GATE.2B] Scheduler·Backfill 발급 경계.
 *
 *   RER.2A 는 `onWageConfirmed` 의 발급 경쟁조건을 닫았다. 남은 발급 경로는
 *   `createPendingReviewRequests` 단기·장기와 그것에 위임하는
 *   `backfillReviewRequests` 다. 이 하네스는 **실제 함수**를 떼어 호출하고,
 *   자격 검사와 `tx.create` 사이에 마감 취소를 끼워 넣는다.
 *
 *   주입 도구 둘:
 *     armHook(k, fn)   — k 번째 transaction **직전**
 *     armInTx(k, fn)   — transaction **안에서** k 번째 읽기 직후
 *   production 로직은 손대지 않는다. 바꾸는 것은 스케줄뿐이다.
 *
 *   격리: demo 프로젝트. 공유 DEV/PROD 쓰기 0.
 */
'use strict';

const PROJECT = 'demo-r7rer2b';
process.env.GCLOUD_PROJECT = PROJECT;
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:6060';

const fs = require('fs');
const path = require('path');
const ROOT = path.join(__dirname, '..');
const admin = require(path.join(ROOT, 'functions', 'node_modules', 'firebase-admin'));
if (!admin.apps.length) admin.initializeApp({projectId: PROJECT});
const realDb = admin.firestore();
const REST = `http://127.0.0.1:6060/v1/projects/${PROJECT}/databases/(default)/documents`;

const rows = [];
let fail = 0;
function check(label, actual, expected, note) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) fail++;
  rows.push({label, ok});
  console.log(`  [${ok ? 'PASS' : 'FAIL'}] ${label}` +
      (ok ? '' : `  기대=${JSON.stringify(expected)} 실제=${JSON.stringify(actual)}`) +
      (note ? `  ${note}` : ''));
}

// ── 주입 도구 ───────────────────────────────────────────────────
let txCount = 0;
let txHook = null;
let inTxHook = null;
let hookDepth = 0;
let txBodyRuns = 0;      // transaction 본문 실행 횟수(재시도 관찰용)
const db = new Proxy(realDb, {
  get(t, p) {
    if (p === 'runTransaction') {
      return async (fn, opts) => {
        if (hookDepth === 0) {
          txCount++;
          if (txHook && txCount === txHook.at) {
            const h = txHook.fn; txHook = null;
            hookDepth++;
            try { await h(); } finally { hookDepth--; }
          }
        }
        return t.runTransaction(async (tx) => {
          txBodyRuns++;
          const myRun = txBodyRuns;
          let gets = 0;
          const wrapped = new Proxy(tx, {
            get(tt, pp) {
              if (pp === 'get') {
                return async (...args) => {
                  const res = await tt.get(...args);
                  gets++;
                  if (inTxHook && hookDepth === 0 &&
                      gets === inTxHook.at && myRun === 1) {
                    const h = inTxHook.fn; inTxHook = null;
                    hookDepth++;
                    try { await h(); } finally { hookDepth--; }
                  }
                  return res;
                };
              }
              const v = tt[pp];
              return typeof v === 'function' ? v.bind(tt) : v;
            },
          });
          return fn(wrapped);
        }, opts);
      };
    }
    const v = t[p];
    return typeof v === 'function' ? v.bind(t) : v;
  },
});
function armHook(at, fn) { txCount = 0; txHook = {at, fn}; }
function armInTx(at, fn) { inTxHook = {at, fn}; }
function disarm() { txCount = 0; txHook = null; inTxHook = null; }
function resetRuns() { txBodyRuns = 0; }

// ── production 슬라이스 ─────────────────────────────────────────
const SRC = fs.readFileSync(path.join(ROOT, 'functions', 'lib', 'index.js'), 'utf8');
const LINES = SRC.split('\n');
function sliceFn(name) {
  const i = LINES.findIndex((l) =>
    l.startsWith(`function ${name}(`) || l.startsWith(`async function ${name}(`));
  if (i < 0) throw new Error(`함수 없음: ${name}`);
  const j = LINES.findIndex((l, k) => k > i && l === '}');
  return LINES.slice(i, j + 1).join('\n');
}
function sliceExport(name) {
  const i = LINES.findIndex((l) => l.startsWith(`exports.${name} = `));
  if (i < 0) throw new Error(`export 없음: ${name}`);
  const j = LINES.findIndex((l, k) => k > i && l === '});');
  return LINES.slice(i, j + 1).join('\n')
      .replace(`exports.${name} = `, `const ${name} = `);
}
const sliceConst = (decl) => {
  const line = LINES.find((l) => l.startsWith(decl));
  if (!line) throw new Error(`상수 없음: ${decl}`);
  return line;
};
/** 소스 그대로 — 위임 관계 정적 확인용. */
const BACKFILL_SRC = sliceExport('backfillReviewRequests');
const SCHED_SRC = sliceFn('createPendingReviewRequests');

class HttpsError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}
const notified = [];
const PRELUDE = `
const firestore_2 = {Timestamp: admin.firestore.Timestamp};
const Timestamp = admin.firestore.Timestamp;
const https_1 = {HttpsError, onCall: (cfg, h) => h};
const firestore_1 = {
  onDocumentCreated: (cfg, h) => h,
  onDocumentUpdated: (cfg, h) => h,
};
const srvNotifyWageEvent = async (...a) => {};
const _sendReviewRequestNotification = async (targetId, counterpart, key,
    y, m, role) => { notified.push({targetId, key, role}); };
`;
const BODY = [
  PRELUDE,
  sliceConst('const ACTUAL_WORK_STATUSES'),
  sliceConst('const FINALIZED_WAGE_STATUSES'),
  sliceConst('const CONFIRMED_STATUSES'),
  sliceConst('const ACCOUNT_DELETION_TOMBSTONE_COL'),
  sliceConst('const MONEY_AUDIT_SUB'),
  sliceFn('srvIsActualFinalizedWork'),
  sliceFn('srvHasActualWorkInMonth'),
  sliceFn('srvFindFinalizedWorkDocId'),
  sliceFn('srvMonthWorkQuery'),
  sliceFn('srvHasActualWorkInMonthTx'),
  sliceFn('srvSuspendReviewEligibility'),
  sliceFn('srvRestoreReviewEligibility'),
  sliceFn('srvRestoreReviewEligibilityByMonth'),
  sliceFn('srvReconcileReviewEligibility'),
  sliceFn('srvReviewRequestKeyOf'),
  sliceFn('srvDeletionBarrierExistsInTx'),
  sliceFn('srvWriteMoneyAudit'),
  sliceFn('assertBizAdmin'),
  sliceFn('createPendingReviewRequests'),
  sliceExport('callableCancelFinalConfirmation'),
  sliceExport('onWageConfirmed'),
  sliceExport('backfillReviewRequests'),
  `return {srvIsActualFinalizedWork, srvHasActualWorkInMonth,
    srvHasActualWorkInMonthTx, createPendingReviewRequests,
    callableCancelFinalConfirmation, onWageConfirmed,
    backfillReviewRequests};`,
].join('\n');
// eslint-disable-next-line no-new-func
const P = new Function('db', 'admin', 'HttpsError', 'notified', BODY)(
    db, admin, HttpsError, notified);

// ── REST (실제 rules) ───────────────────────────────────────────
function tokFor(uid) {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  return `${b64({alg: 'none', typ: 'JWT'})}.${b64({
    iss: `https://securetoken.google.com/${PROJECT}`, aud: PROJECT,
    auth_time: now, user_id: uid, sub: uid, iat: now, exp: now + 3600,
    firebase: {identities: {}, sign_in_provider: 'custom'},
  })}.`;
}
const str = (v) => ({stringValue: v});
const int = (v) => ({integerValue: String(v)});
const bool = (v) => ({booleanValue: v});
async function restCreateReview(uid, id, fields) {
  const r = await fetch(
      `${REST}/monthly_reviews?documentId=${encodeURIComponent(id)}`,
      {method: 'POST',
        headers: {Authorization: `Bearer ${tokFor(uid)}`,
          'Content-Type': 'application/json'},
        body: JSON.stringify({fields})});
  return r.status;
}

// ── 고정물 ──────────────────────────────────────────────────────
const RUN = 'rig' + Date.now().toString(36);
const BIZ = `${RUN}biz`;
const ADMIN = `${RUN}admin`;
const SUPER = `${RUN}super`;
const T = admin.firestore.Timestamp;
const KST = 9 * 36e5;
const kstYm = (d) => {
  const k = new Date(d.getTime() + KST);
  return {year: k.getUTCFullYear(), month: k.getUTCMonth() + 1};
};
/** 창(어제~14일 전) 안의 근무일. daysAgo 는 3 이상 권장. */
function workDay(daysAgo) {
  // KST 정오로 고정 — 창 경계·월 성분 모두 안전하다.
  const k = new Date(Date.now() + KST - daysAgo * 864e5);
  const d = new Date(Date.UTC(k.getUTCFullYear(), k.getUTCMonth(),
      k.getUTCDate(), 12, 0) - KST);
  const {year, month} = kstYm(d);
  return {
    ts: T.fromDate(d), year, month,
    ym: `${year}-${String(month).padStart(2, '0')}`,
  };
}
const created = [];
const track = (p) => { created.push(p); return p; };

async function putWorker(uid) {
  await realDb.doc(track(`users/${uid}`)).set({uid, name: 'w', role: 'USER',
    accountStatus: 'active', isBlacklisted: false});
}
async function putShortApp(id, uid, w) {
  await realDb.doc(track(`applications/${id}`)).set({
    uid, businessId: BIZ, businessName: 'biz', status: 'CONFIRMED',
    applicantName: 'w', workDate: w.ts});
}
async function putLongApp(id, uid, start, end) {
  await realDb.doc(track(`applications/${id}`)).set({
    uid, businessId: BIZ, businessName: 'biz', status: 'CONFIRMED',
    applicantName: 'w', workDate: start.ts, workEndDate: end.ts,
    workDays: ['월', '화', '수', '목', '금', '토', '일']});
}
async function putAtt(id, uid, w, over) {
  await realDb.doc(track(`attendance/${id}`)).set({
    userId: uid, businessId: BIZ, yearMonth: w.ym, workDate: w.ts,
    status: 'present', wageStatus: 'confirmed', finalWage: 90000,
    applicationId: `${RUN}any`, createdAt: T.now(), ...over});
}
const keyOf = (uid, w) => `${BIZ}_${uid}_${w.year}_${w.month}`;
const reqState = async (key) => {
  const s = await realDb.doc(`review_requests/${key}`).get();
  if (!s.exists) return 'absent';
  return s.data().eligibilitySuspendedAt ? 'suspended' : 'active';
};
const workerFields = (reqId, w) => ({
  reviewType: str('USER_TO_BUSINESS'), businessId: str(BIZ),
  requestId: str(reqId), rating: int(5), isPublished: bool(false),
  reviewYear: int(w.year), reviewMonth: int(w.month), reviewerName: str('익명'),
});
const cancel = (ids) => P.callableCancelFinalConfirmation(
    {auth: {uid: ADMIN}, data: {businessId: BIZ, attendanceIds: ids}});

(async () => {
  console.log(`프로젝트: ${PROJECT} (격리 에뮬레이터)`);
  console.log('writer: createPendingReviewRequests · backfillReviewRequests 실물\n');

  await realDb.doc(track(`users/${ADMIN}`)).set({uid: ADMIN, name: 'a',
    role: 'BUSINESS_ADMIN', accountStatus: 'active'});
  await realDb.doc(track(`users/${SUPER}`)).set({uid: SUPER, name: 's',
    role: 'SUPER_ADMIN', accountStatus: 'active'});
  await realDb.doc(track(`businesses/${BIZ}`)).set({businessId: BIZ,
    name: 'biz', ownerId: ADMIN, adminIds: [ADMIN]});

  // ═══ §2 위임 관계 정적 확인 ════════════════════════════════
  console.log('=== §2 Backfill 위임 · 자격 검사 위치 ===');
  check('IG-01 Backfill 은 공용 경로에 위임한다',
      BACKFILL_SRC.includes('createPendingReviewRequests(now)'), true);
  check('IG-02 Backfill 은 자격 검사를 복제하지 않는다', [
    BACKFILL_SRC.includes('srvHasActualWorkInMonth'),
    BACKFILL_SRC.includes('srvMonthWorkQuery'),
    BACKFILL_SRC.includes('review_requests'),
  ], [false, false, false]);
  check('IG-03 Scheduler 가 공용 eligibility 를 쓴다',
      SCHED_SRC.includes('srvHasActualWorkInMonth'), true);
  //   생성 transaction 의 read-set 에 근태가 들어 있는가 — 이것이 핵심이다.
  check('IG-04 생성 transaction 이 근태 자격을 tx 안에서 읽는다',
      SCHED_SRC.includes("srvHasActualWorkInMonthTx"), true,
      '(transaction 밖 precheck 만으로는 낡은 자격을 막지 못한다)');

  // ═══ §3-A Scheduler 선행 검사 후 마감 취소 (단기) ══════════
  console.log('\n=== §3-A 단기: 선행 자격 검사 → 마감 취소 → tx.create ===');
  const WA = `${RUN}wa`;
  const WD = workDay(3);
  await putWorker(WA);
  await putShortApp(`${RUN}appA`, WA, WD);
  await putAtt('attA', WA, WD);
  const KEY_A = keyOf(WA, WD);
  track(`review_requests/${KEY_A}`);
  check('IG-10 출발: 토큰 없음', await reqState(KEY_A), 'absent');

  //   Scheduler 의 1번째 transaction(= barrier+create) **직전**에
  //   마감 취소를 커밋한다. 자격 질의는 이미 끝난 상태다.
  notified.length = 0;
  resetRuns();
  armHook(1, async () => {
    console.log('    ↳ [주입] 자격 질의 뒤, tx.create 직전 — 마감 취소 커밋');
    const r = await cancel(['attA']);
    console.log('    ↳ [주입] 취소 결과:', JSON.stringify(r));
  });
  await P.createPendingReviewRequests(T.now());
  disarm();

  check('IG-11 근태는 calculated',
      (await realDb.doc('attendance/attA').get()).data().wageStatus,
      'calculated');
  check('IG-12 그 달 확정 근무 0건',
      await P.srvHasActualWorkInMonth(BIZ, WA, WD.ym), false);
  check('IG-13 §3-A 핵심 — 낡은 자격으로 활성 토큰이 생기지 않는다',
      await reqState(KEY_A), 'absent');
  check('IG-14 제출 DENY(실제 rules)',
      await restCreateReview(WA, `${RUN}ra`, workerFields(KEY_A, WD)), 403);
  check('IG-15 알림도 발송되지 않는다', notified.length, 0);

  // ═══ §3-A 장기 경로 ═══════════════════════════════════════
  console.log('\n=== §3-A 장기: 같은 순서 ===');
  const WB = `${RUN}wb`;
  const WStart = workDay(10);
  const WEnd = workDay(3);
  await putWorker(WB);
  await putLongApp(`${RUN}appB`, WB, WStart, WEnd);
  await putAtt('attB', WB, WEnd);
  const KEY_B = keyOf(WB, WEnd);
  track(`review_requests/${KEY_B}`);
  notified.length = 0;
  //   단기 지원서가 없으므로 장기 루프의 1번째 transaction 이 대상이다.
  armHook(1, async () => {
    console.log('    ↳ [주입] 장기 — 자격 질의 뒤, tx.create 직전 마감 취소');
    await cancel(['attB']);
  });
  await P.createPendingReviewRequests(T.now());
  disarm();
  check('IG-20 장기 — 활성 토큰이 생기지 않는다',
      await reqState(KEY_B), 'absent');
  check('IG-21 장기 — 제출 DENY',
      await restCreateReview(WB, `${RUN}rb`, workerFields(KEY_B, WEnd)), 403);
  check('IG-22 장기 — 알림 없음', notified.length, 0);

  // ═══ §3-B transaction 내부 경합 ════════════════════════════
  console.log('\n=== §3-B 생성 transaction 안에서 근태가 바뀐다 ===');
  const WC = `${RUN}wc`;
  const WDc = workDay(4);
  await putWorker(WC);
  await putShortApp(`${RUN}appC`, WC, WDc);
  await putAtt('attC', WC, WDc);
  const KEY_C = keyOf(WC, WDc);
  track(`review_requests/${KEY_C}`);
  notified.length = 0;
  resetRuns();
  //   transaction 안에서 **첫 읽기 직후** 근태를 떨어뜨린다.
  //   중첩 transaction 으로 교착되지 않도록 단건 쓰기만 던지고 기다리지 않는다.
  armInTx(1, async () => {
    console.log('    ↳ [B1 주입] tx 자격 질의 **전** — 근태 calculated 쓰기');
    realDb.doc('attendance/attC').update({wageStatus: 'calculated'})
        .catch(() => {});
  });
  await P.createPendingReviewRequests(T.now());
  disarm();
  const stateC = await reqState(KEY_C);
  const eligibleC = await P.srvHasActualWorkInMonth(BIZ, WC, WDc.ym);
  console.log(`    [관찰] B1 tx 본문 ${txBodyRuns}회 · 자격=${eligibleC}` +
      ` · 토큰=${stateC}`);
  check('IG-30 B1 — tx 가 직접 보고 발급하지 않는다',
      [eligibleC, stateC], [false, 'absent']);

  //   B2: 자격 질의 **후** 에 마감 취소가 시작된다. 이때 create 는 커밋될 수
  //   있다 — 그 경우를 막는 것은 RER.2A 의 사후 재집계다. 중첩 교착을 피해
  //   취소를 await 하지 않고 던지고, tx 가 커밋한 뒤 결과를 받는다.
  const WJ = `${RUN}wj`;
  const WDj = workDay(12);
  await putWorker(WJ);
  await putShortApp(`${RUN}appJ`, WJ, WDj);
  await putAtt('attJ', WJ, WDj);
  const KEY_J = keyOf(WJ, WDj);
  track(`review_requests/${KEY_J}`);
  resetRuns();
  let cancelLate = null;
  armInTx(2, async () => {
    console.log('    ↳ [B2 주입] tx 자격 질의 **후** — 마감 취소 시작(비대기)');
    cancelLate = cancel(['attJ']);
  });
  await P.createPendingReviewRequests(T.now());
  disarm();
  const lateRes = cancelLate ? await cancelLate : null;
  const stateJ = await reqState(KEY_J);
  const eligibleJ = await P.srvHasActualWorkInMonth(BIZ, WJ, WDj.ym);
  console.log(`    [관찰] B2 tx 본문 ${txBodyRuns}회 · 취소=` +
      `${JSON.stringify(lateRes)} · 자격=${eligibleJ} · 토큰=${stateJ}`);
  check('IG-31 B2 불변식 — 자격 없는 **활성** 토큰은 없다',
      eligibleJ === false && stateJ === 'active', false);
  check('IG-32 B2 — 자격이 없으면 토큰은 보류이거나 없다',
      eligibleJ ? true : (stateJ !== 'active'), true);
  check('IG-33 B2 — 제출 DENY',
      eligibleJ ? 200 :
        await restCreateReview(WJ, `${RUN}rj`, workerFields(KEY_J, WDj)),
      eligibleJ ? 200 : 403);

  // ═══ §3-C Backfill ═══════════════════════════════════════
  console.log('\n=== §3-C Backfill 도 같은 경계를 갖는다 ===');
  const WDd = `${RUN}wd`;
  const WDd2 = workDay(5);
  await putWorker(WDd);
  await putShortApp(`${RUN}appD`, WDd, WDd2);
  await putAtt('attD', WDd, WDd2);
  const KEY_D = keyOf(WDd, WDd2);
  track(`review_requests/${KEY_D}`);
  notified.length = 0;
  armHook(1, async () => {
    console.log('    ↳ [주입] Backfill — 자격 질의 뒤 마감 취소');
    await cancel(['attD']);
  });
  const bf = await P.backfillReviewRequests({auth: {uid: SUPER}, data: {}});
  disarm();
  check('IG-40 Backfill 호출 성공', bf.success, true);
  check('IG-41 Backfill 도 활성 토큰을 만들지 않는다',
      await reqState(KEY_D), 'absent');
  check('IG-42 Backfill — 제출 DENY',
      await restCreateReview(WDd, `${RUN}rd`, workerFields(KEY_D, WDd2)), 403);
  let bfDenied = null;
  try {
    await P.backfillReviewRequests({auth: {uid: ADMIN}, data: {}});
    bfDenied = 'allowed';
  } catch (e) { bfDenied = e.code; }
  check('IG-43 Backfill 은 SUPER_ADMIN 전용(기존 계약)', bfDenied,
      'permission-denied');

  // ═══ §5 정상 발급 회귀 ════════════════════════════════════
  console.log('\n=== §5 정상 발급 · 중복 방지 · 제외 조건 ===');
  const WE = `${RUN}we`;
  const WDe = workDay(6);
  await putWorker(WE);
  await putShortApp(`${RUN}appE`, WE, WDe);
  await putAtt('attE', WE, WDe);
  const KEY_E = keyOf(WE, WDe);
  track(`review_requests/${KEY_E}`);
  notified.length = 0;
  await P.createPendingReviewRequests(T.now());
  check('IG-50 단기 정상 발급', await reqState(KEY_E), 'active');
  check('IG-51 양쪽 알림 1회씩', notified.filter((n) => n.key === KEY_E)
      .map((n) => n.role).sort(), ['admin', 'worker']);
  check('IG-52 제출 허용',
      await restCreateReview(WE, `${RUN}re`, workerFields(KEY_E, WDe)), 200);
  await realDb.doc(`monthly_reviews/${RUN}re`).delete();

  // 장기 정상 발급
  const WF = `${RUN}wf`;
  const WFs = workDay(11);
  const WFe = workDay(6);
  await putWorker(WF);
  await putLongApp(`${RUN}appF`, WF, WFs, WFe);
  await putAtt('attF', WF, WFe);
  const KEY_F = keyOf(WF, WFe);
  track(`review_requests/${KEY_F}`);
  notified.length = 0;
  await P.createPendingReviewRequests(T.now());
  check('IG-53 장기 정상 발급', await reqState(KEY_F), 'active');
  check('IG-54 장기 양쪽 알림 1회씩', notified.filter((n) => n.key === KEY_F)
      .map((n) => n.role).sort(), ['admin', 'worker']);

  // §3-D 중복 실행
  notified.length = 0;
  await P.createPendingReviewRequests(T.now());
  await P.createPendingReviewRequests(T.now());
  const dupCount = (await realDb.collection('review_requests')
      .where('requestKey', '==', KEY_E).get()).size;
  check('IG-60 §3-D 반복 실행에도 요청 1개', dupCount, 1);
  check('IG-61 §3-D 반복 실행에 알림 중복 없음',
      notified.filter((n) => n.key === KEY_E || n.key === KEY_F).length, 0);
  const reqE = (await realDb.doc(`review_requests/${KEY_E}`).get()).data();
  check('IG-62 createdAt·deadline 불변', [
    reqE.createdAt != null, reqE.deadline != null,
  ], [true, true]);

  // NO_SHOW / 미확정 제외
  const WG = `${RUN}wg`;
  const WDg = workDay(7);
  await putWorker(WG);
  await putShortApp(`${RUN}appG`, WG, WDg);
  await putAtt('attG', WG, WDg, {status: 'NO_SHOW', finalWage: 0});
  const WH = `${RUN}wh`;
  const WDh = workDay(8);
  await putWorker(WH);
  await putShortApp(`${RUN}appH`, WH, WDh);
  await putAtt('attH', WH, WDh, {wageStatus: 'pending'});
  await P.createPendingReviewRequests(T.now());
  check('IG-70 NO_SHOW 만 있는 월 발급 없음',
      await reqState(keyOf(WG, WDg)), 'absent');
  check('IG-71 급여 미확정 월 발급 없음',
      await reqState(keyOf(WH, WDh)), 'absent');

  // 다른 확정 근무가 남은 달 유지
  const WI = `${RUN}wi`;
  const WDi = workDay(9);
  await putWorker(WI);
  await putShortApp(`${RUN}appI`, WI, WDi);
  await putAtt('attI1', WI, WDi);
  await putAtt('attI2', WI, WDi);
  const KEY_I = keyOf(WI, WDi);
  track(`review_requests/${KEY_I}`);
  await P.createPendingReviewRequests(T.now());
  check('IG-80 발급됨', await reqState(KEY_I), 'active');
  await cancel(['attI1']);
  check('IG-81 다른 확정 근무가 남으면 자격 유지', await reqState(KEY_I),
      'active');
  await cancel(['attI2']);
  check('IG-82 마지막 건까지 취소되면 보류', await reqState(KEY_I), 'suspended');
  check('IG-83 보류 후 Scheduler 가 되살리지 않는다',
      await (async () => {
        await P.createPendingReviewRequests(T.now());
        return reqState(KEY_I);
      })(), 'suspended');
  check('IG-84 재확정되면 Scheduler 가 복구한다',
      await (async () => {
        await realDb.doc('attendance/attI2').update({wageStatus: 'confirmed'});
        await P.createPendingReviewRequests(T.now());
        return reqState(KEY_I);
      })(), 'active');

  console.log(`\n판정 ${rows.filter((r) => r.ok).length}/${rows.length} PASS` +
      (fail ? `  실패 ${fail}건` : ''));

  console.log('\n=== teardown (격리 에뮬레이터) ===');
  for (const col of ['review_requests', 'monthly_reviews', 'applications',
    'attendance']) {
    const snap = await realDb.collection(col).get();
    for (const d of snap.docs) {
      const sub = await d.ref.collection('money_audit').get();
      for (const s of sub.docs) await s.ref.delete().catch(() => {});
      await d.ref.delete().catch(() => {});
    }
  }
  for (const p of [...new Set(created)]) {
    await realDb.doc(p).delete().catch(() => {});
  }
  console.log('  완료 · 공유 DEV/PROD 쓰기 0');
  process.exit(fail ? 1 : 0);
})().catch((e) => {
  console.error('하네스 실패:', e && e.stack ? e.stack : e);
  process.exit(1);
});
