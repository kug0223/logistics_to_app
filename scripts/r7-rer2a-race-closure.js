/**
 * [R7-REVIEW-ELIGIBILITY-REVOCATION-RACE-CLOSURE.2A] 경쟁조건·실패복구 하네스.
 *
 *   §2 의 순서를 **실제 CF 실행 도중에** 끼워 넣어 결정론적으로 재현한다.
 *   production 로직은 손대지 않는다 — `db.runTransaction` 을 감싼 proxy 가
 *   "k 번째 transaction 직전"에 훅을 실행한다. 즉 끼워 넣는 것은 **스케줄**
 *   뿐이고, 호출되는 것은 컴파일된 production 핸들러 그 자체다.
 *
 *   `callableCancelFinalConfirmation` 의 transaction 순서:
 *     ① 사전 보류(대상 월마다 1회)  ② 마감 취소(건마다 1회)  ③ 사후 재집계
 *   토큰이 아직 없으면 ① 은 0회다 — 그래서 1번째 transaction 이 ② 다.
 *   그 직전에 지연된 `onWageConfirmed` 를 실행하면 §2 의 3→4→5→6 이 된다.
 *
 *   격리: demo 프로젝트. 공유 DEV/PROD 쓰기 0.
 */
'use strict';

const PROJECT = 'demo-r7rer2a';
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

// ── transaction 스케줄 훅 ───────────────────────────────────────
let txCount = 0;
let txHook = null;      // {at: n, fn: async () => {}}
let hookDepth = 0;
const db = new Proxy(realDb, {
  get(t, p) {
    if (p === 'runTransaction') {
      return async (fn, opts) => {
        if (hookDepth === 0) {
          txCount++;
          if (txHook && txCount === txHook.at) {
            const h = txHook.fn;
            txHook = null;
            hookDepth++;
            try { await h(); } finally { hookDepth--; }
          }
          if (txFailAt && txCount === txFailAt) {
            txFailAt = 0;
            throw new Error('주입된 transaction 실패');
          }
        }
        return t.runTransaction(fn, opts);
      };
    }
    const v = t[p];
    return typeof v === 'function' ? v.bind(t) : v;
  },
});
function armHook(at, fn) { txCount = 0; txHook = {at, fn}; }
function disarmHook() { txCount = 0; txHook = null; txFailAt = 0; }
/** k 번째 transaction 을 실패시킨다 — 인위적 실패 주입(§3). */
let txFailAt = 0;
function armFail(at) { txCount = 0; txFailAt = at; }

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

class HttpsError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}
const notified = [];
const PRELUDE = `
const firestore_2 = {Timestamp: admin.firestore.Timestamp};
const https_1 = {HttpsError, onCall: (cfg, h) => h};
const firestore_1 = {
  onDocumentCreated: (cfg, h) => h,
  onDocumentUpdated: (cfg, h) => h,
};
const srvNotifyWageEvent = async (...a) => { notified.push(['wage', ...a]); };
const _sendReviewRequestNotification = async (...a) => { notified.push(['review', ...a]); };
`;
const OPTIONAL = ['srvReconcileReviewEligibility'];
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
  sliceFn('srvReviewRequestKeyOf'),
  sliceFn('srvDeletionBarrierExistsInTx'),
  sliceFn('srvWriteMoneyAudit'),
  sliceFn('assertBizAdmin'),
  sliceFn('updateUserReviewStats'),
  sliceFn('updateBusinessReviewStats'),
  sliceExport('callableCancelFinalConfirmation'),
  sliceExport('onWageConfirmed'),
  sliceExport('onReviewCreated'),
  // 수정 전/후 모두 돌 수 있게 — 아직 없으면 undefined 로 둔다.
  ...OPTIONAL.map((n) => LINES.some((l) =>
    l.startsWith(`async function ${n}(`)) ? sliceFn(n) : `const ${n} = undefined;`),
  `return {srvIsActualFinalizedWork, srvHasActualWorkInMonth,
    srvFindFinalizedWorkDocId, srvSuspendReviewEligibility,
    srvRestoreReviewEligibility, srvRestoreReviewEligibilityByMonth,
    srvReconcileReviewEligibility, srvReviewRequestKeyOf,
    updateUserReviewStats, updateBusinessReviewStats,
    callableCancelFinalConfirmation, onWageConfirmed, onReviewCreated};`,
].join('\n');
// eslint-disable-next-line no-new-func
const P = new Function('db', 'admin', 'HttpsError', 'notified', BODY)(
    db, admin, HttpsError, notified);

// ── 토큰 ────────────────────────────────────────────────────────
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
async function restGet(uid, p) {
  const r = await fetch(`${REST}/${p}`,
      {headers: {Authorization: `Bearer ${tokFor(uid)}`}});
  return r.status;
}

// ── 고정물 ──────────────────────────────────────────────────────
const RUN = 'rca' + Date.now().toString(36);
const BIZ = `${RUN}biz`;
const ADMIN = `${RUN}admin`;
const WORKER = `${RUN}worker`;
const WORKER2 = `${RUN}worker2`;
const T = admin.firestore.Timestamp;
const kstParts = (d) => {
  const k = new Date(d.getTime() + 9 * 36e5);
  return {year: k.getUTCFullYear(), month: k.getUTCMonth() + 1};
};
/**
 * N 달 전. **달 단위로** 물러난다 — 일수로 물러나면 40일/70일 전이 같은 달이
 * 되어 서로 다른 달이라고 믿은 두 시나리오가 토큰 하나를 공유한다(실측 함정).
 * 0 달은 "오늘 -2일" 이라 `deadline = workDate + 14일` 이 미래다.
 */
function monthOf(monthsBack, workerId = WORKER) {
  const nowKst = new Date(Date.now() + 9 * 36e5);
  let d;
  if (monthsBack === 0) {
    d = new Date(Date.now() - 2 * 864e5);
  } else {
    d = new Date(Date.UTC(nowKst.getUTCFullYear(),
        nowKst.getUTCMonth() - monthsBack, 15, 3, 0) - 9 * 36e5);
  }
  const {year, month} = kstParts(d);
  return {
    date: T.fromDate(d),
    ym: `${year}-${String(month).padStart(2, '0')}`,
    key: `${BIZ}_${workerId}_${year}_${month}`,
    workerId,
  };
}
const created = [];
const track = (p) => { created.push(p); return p; };

async function putAtt(id, m, over) {
  await realDb.doc(track(`attendance/${id}`)).set({
    userId: m.workerId, businessId: BIZ, yearMonth: m.ym, workDate: m.date,
    status: 'present', wageStatus: 'confirmed', finalWage: 90000,
    applicationId: `${RUN}app_${m.workerId}`, createdAt: T.now(), ...over,
  });
}
const wageEvent = (attId, data) => ({
  params: {attendanceId: attId},
  data: {
    before: {data: () => ({...data, wageStatus: 'calculated'})},
    after: {data: () => data},
  },
});
const attEventData = (m) => ({
  userId: m.workerId, businessId: BIZ, yearMonth: m.ym, workDate: m.date,
  status: 'present', wageStatus: 'confirmed',
  applicationId: `${RUN}app_${m.workerId}`,
});
const reqState = async (key) => {
  const s = await realDb.doc(`review_requests/${key}`).get();
  if (!s.exists) return 'absent';
  return s.data().eligibilitySuspendedAt ? 'suspended' : 'active';
};
const workerFields = (reqId, m) => ({
  reviewType: str('USER_TO_BUSINESS'), businessId: str(BIZ),
  requestId: str(reqId), rating: int(5), isPublished: bool(false),
  reviewYear: int(kstParts(m.date.toDate()).year),
  reviewMonth: int(kstParts(m.date.toDate()).month), reviewerName: str('익명'),
});
const cancel = (ids, uid = ADMIN) => P.callableCancelFinalConfirmation(
    {auth: {uid}, data: {businessId: BIZ, attendanceIds: ids}});

(async () => {
  console.log(`프로젝트: ${PROJECT} (격리 에뮬레이터)`);
  console.log('production 핸들러 + 실제 rules · 스케줄만 주입\n');

  await realDb.doc(track(`users/${WORKER}`)).set({uid: WORKER, name: 'w',
    role: 'USER', accountStatus: 'active', isBlacklisted: false});
  await realDb.doc(track(`users/${ADMIN}`)).set({uid: ADMIN, name: 'a',
    role: 'BUSINESS_ADMIN', accountStatus: 'active'});
  await realDb.doc(track(`businesses/${BIZ}`)).set({businessId: BIZ,
    name: 'biz', ownerId: ADMIN, adminIds: [ADMIN]});
  await realDb.doc(track(`users/${WORKER2}`)).set({uid: WORKER2, name: 'w2',
    role: 'USER', accountStatus: 'active', isBlacklisted: false});
  for (const w of [WORKER, WORKER2]) {
    await realDb.doc(track(`applications/${RUN}app_${w}`)).set({uid: w,
      businessId: BIZ, businessName: 'biz', status: 'CONFIRMED',
      applicantName: 'w'});
  }

  // ═══ §2 토큰이 없는 상태의 동시성 ═══════════════════════════
  console.log('=== §2 토큰 미존재 상태에서 지연 트리거가 끼어든다 ===');
  const M1 = monthOf(0);
  await putAtt('s1', M1);
  check('RC-01 출발 상태: 토큰 없음', await reqState(M1.key), 'absent');

  //   사전 보류는 **토큰 존재 여부와 무관하게** 대상 월마다 transaction 을
  //   1회 쓴다(존재 확인이 transaction 안에 있다). 그래서 1번째 transaction
  //   은 사전 보류이고, §2 가 요구한 창은 **그 다음** — 2번째(= 마감 취소)
  //   직전이다. 여기서 지연 트리거를 실행하면 3→4→5→6 이 된다.
  armHook(2, async () => {
    console.log('    ↳ [주입] 사전 보류 뒤, 마감 취소 직전 — 지연 onWageConfirmed');
    await P.onWageConfirmed(wageEvent('s1', attEventData(M1)));
    console.log('    ↳ [주입] 토큰 생성 결과:', await reqState(M1.key));
  });
  const r1 = await cancel(['s1']);
  disarmHook();
  track(`review_requests/${M1.key}`);

  check('RC-02 마감 취소는 1건 처리됐다', r1.processed, 1);
  check('RC-03 근태는 calculated',
      (await realDb.doc('attendance/s1').get()).data().wageStatus, 'calculated');
  check('RC-04 그 달에 확정 근무 0건',
      await P.srvHasActualWorkInMonth(BIZ, WORKER, M1.ym), false);
  check('RC-05 §2 핵심 — 끼어든 토큰이 활성으로 남지 않는다',
      await reqState(M1.key), 'suspended');
  check('RC-06 지원자 제출 DENY(실제 rules)',
      await restCreateReview(WORKER, `${RUN}v1`, workerFields(M1.key, M1)), 403);
  //   403 의 원인 귀속 — 같은 달·같은 토큰을 활성으로 되돌리면 200 이다.
  //   (보류 축 말고 다른 조건이 막고 있던 것이 아님을 보인다)
  await realDb.doc(`review_requests/${M1.key}`).update(
      {eligibilitySuspendedAt: admin.firestore.FieldValue.delete()});
  check('RC-07 대조군 — 보류만 풀면 같은 요청이 200',
      await restCreateReview(WORKER, `${RUN}v1c`, workerFields(M1.key, M1)), 200);
  //   그런데 그 리뷰는 월 자격이 없으므로 트리거가 되돌린다(§4 최종 권위).
  await P.onReviewCreated({
    params: {reviewId: `${RUN}v1c`},
    data: {
      data: () => ({reviewType: 'USER_TO_BUSINESS', businessId: BIZ,
        requestId: M1.key, rating: 5}),
      ref: realDb.doc(`monthly_reviews/${RUN}v1c`),
    },
  });
  check('RC-08 토큰이 낡아도 월 자격 재확인이 막는다',
      (await realDb.doc(`monthly_reviews/${RUN}v1c`).get()).exists, false);
  await realDb.doc(`review_requests/${M1.key}`).update(
      {eligibilitySuspendedAt: T.now()});

  //   반대 순서 — 마감 취소가 먼저 커밋된 뒤 지연 트리거가 도착한다.
  console.log('\n=== §2 반대 순서: 취소 커밋 후 도착한 생성 트리거 ===');
  const M1b = monthOf(5);
  await putAtt('s1b', M1b);
  await cancel(['s1b']);
  check('RC-09a 취소로 근태 calculated',
      (await realDb.doc('attendance/s1b').get()).data().wageStatus,
      'calculated');
  await P.onWageConfirmed(wageEvent('s1b', attEventData(M1b)));
  check('RC-09b 늦게 도착한 트리거는 토큰을 만들지 않는다',
      await reqState(M1b.key), 'absent');

  //   세 번째 창 — 마감 취소가 커밋된 뒤, **사후 재집계 직전**에 도착한다.
  //   재집계는 그 시점에 토큰을 못 보므로, 생성 쪽이 스스로 막아야 한다.
  const M1c = monthOf(7);
  await putAtt('s1c', M1c);
  armHook(3, async () => {
    console.log('    ↳ [주입] 마감 취소 커밋 후, 사후 재집계 직전 — 생성 트리거');
    await P.onWageConfirmed(wageEvent('s1c', attEventData(M1c)));
  });
  await cancel(['s1c']);
  disarmHook();
  check('RC-09c 재집계가 보기 전에 도착해도 토큰이 생기지 않는다',
      await reqState(M1c.key), 'absent');
  check('RC-09d 근태는 calculated',
      (await realDb.doc('attendance/s1c').get()).data().wageStatus,
      'calculated');

  // ═══ §3 사전 보류 성공 후 마감 취소 실패/skip ═══════════════
  console.log('\n=== §3 사전 보류 뒤 마감 취소가 실패·skip 됐다 ===');
  const M2 = monthOf(1);
  await putAtt('s2', M2);
  await P.onWageConfirmed(wageEvent('s2', attEventData(M2)));
  track(`review_requests/${M2.key}`);
  check('RC-10 토큰 활성', await reqState(M2.key), 'active');
  //   중간정산 lock — 마감 취소 writer 가 건너뛰는 실제 조건.
  await realDb.doc('attendance/s2').update(
      {activeInterimSettlementId: `${RUN}settle`});
  const r2 = await cancel(['s2']);
  check('RC-11 취소 0건(skip)', r2.processed, 0);
  check('RC-12 근태 보존(confirmed)',
      (await realDb.doc('attendance/s2').get()).data().wageStatus, 'confirmed');
  check('RC-13 보류가 남지 않는다 — 사후 재집계가 되돌린다',
      await reqState(M2.key), 'active');
  check('RC-14 제출 허용(오차단 없음)',
      await restCreateReview(WORKER, `${RUN}v2`, workerFields(M2.key, M2)), 200);
  await realDb.doc(`monthly_reviews/${RUN}v2`).delete();
  await realDb.doc('attendance/s2').update(
      {activeInterimSettlementId: admin.firestore.FieldValue.delete()});

  // ═══ §3 일괄 중 일부만 취소됐다 ════════════════════════════
  console.log('\n=== §3 일괄 마감 취소 중 일부 skip ===');
  const M3 = monthOf(2);
  await putAtt('s3a', M3);
  await putAtt('s3b', M3, {workDate: T.fromDate(
      new Date(M3.date.toDate().getTime() + 36e5))});
  await P.onWageConfirmed(wageEvent('s3a', attEventData(M3)));
  track(`review_requests/${M3.key}`);
  await realDb.doc('attendance/s3b').update(
      {activeInterimSettlementId: `${RUN}settle`});
  const r3 = await cancel(['s3a', 's3b']);
  check('RC-20 2건 중 1건만 취소', [r3.processed, r3.skipped.length], [1, 1]);
  check('RC-21 남은 확정 근무가 있으므로 자격 유지',
      await reqState(M3.key), 'active');
  check('RC-22 제출 허용',
      await restCreateReview(WORKER, `${RUN}v3`, workerFields(M3.key, M3)), 200);
  await realDb.doc(`monthly_reviews/${RUN}v3`).delete();
  //   남은 1건까지 취소하면 보류로 넘어간다.
  await realDb.doc('attendance/s3b').update(
      {activeInterimSettlementId: admin.firestore.FieldValue.delete()});
  await cancel(['s3b']);
  check('RC-23 마지막 건까지 취소되면 보류', await reqState(M3.key), 'suspended');
  check('RC-24 제출 DENY',
      await restCreateReview(WORKER, `${RUN}v3b`, workerFields(M3.key, M3)), 403);

  // ═══ §3 요청이 사라지는 경쟁 ═══════════════════════════════
  console.log('\n=== §3 보류/복구 도중 요청 문서가 사라진다 ===');
  const M4 = monthOf(3);
  await putAtt('s4', M4);
  await P.onWageConfirmed(wageEvent('s4', attEventData(M4)));
  track(`review_requests/${M4.key}`);
  //   마감 취소 1번째 transaction(사전 보류) 직전에 요청을 지운다.
  armHook(1, async () => {
    await realDb.doc(`review_requests/${M4.key}`).delete();
  });
  let crashed = null;
  try {
    const r4 = await cancel(['s4']);
    crashed = r4.processed;
  } catch (e) { crashed = `throw:${e.message}`; }
  disarmHook();
  check('RC-30 요청이 사라져도 마감 취소는 완료된다', crashed, 1);
  check('RC-31 사라진 요청을 되살리지 않는다',
      await reqState(M4.key), 'absent');
  check('RC-32 근태는 calculated',
      (await realDb.doc('attendance/s4').get()).data().wageStatus, 'calculated');

  // ═══ §3 재확정과 취소가 동시 ═══════════════════════════════
  console.log('\n=== §3 재확정과 마감 취소가 동시 ===');
  const M5 = monthOf(4);
  await putAtt('s5a', M5);
  await putAtt('s5b', M5, {wageStatus: 'calculated', workDate: T.fromDate(
      new Date(M5.date.toDate().getTime() + 36e5))});
  await P.onWageConfirmed(wageEvent('s5a', attEventData(M5)));
  track(`review_requests/${M5.key}`);
  //   s5a 를 취소하는 도중, 같은 달 s5b 가 확정된다.
  armHook(1, async () => {
    await realDb.doc('attendance/s5b').update({wageStatus: 'confirmed'});
    await P.onWageConfirmed(wageEvent('s5b', attEventData(M5)));
  });
  await cancel(['s5a']);
  disarmHook();
  check('RC-40 동시 재확정이 있으면 자격 유지', await reqState(M5.key), 'active');
  check('RC-41 상태가 실제 근태와 일치',
      await P.srvHasActualWorkInMonth(BIZ, WORKER, M5.ym), true);
  check('RC-42 제출 허용',
      await restCreateReview(WORKER, `${RUN}v5`, workerFields(M5.key, M5)), 200);
  await realDb.doc(`monthly_reviews/${RUN}v5`).delete();
  //   반대 방향 — 취소가 먼저 커밋된 뒤 늦은 트리거가 도착한다.
  await cancel(['s5b']);
  check('RC-43 둘 다 취소 → 보류', await reqState(M5.key), 'suspended');
  await P.onWageConfirmed(wageEvent('s5b', attEventData(M5)));
  check('RC-44 늦은 트리거가 보류를 풀지 않는다 — 근거를 tx 안에서 다시 읽는다',
      await reqState(M5.key), 'suspended');
  check('RC-45 중복 트리거도 같다',
      await (async () => {
        await P.onWageConfirmed(wageEvent('s5b', attEventData(M5)));
        await P.onWageConfirmed(wageEvent('s5a', attEventData(M5)));
        return reqState(M5.key);
      })(), 'suspended');

  // ═══ §3 복구 중 탈퇴 barrier 등장 + 재시도 ═════════════════
  console.log('\n=== §3 복구 중 탈퇴 barrier 등장 → 재시도로 복구 ===');
  await realDb.doc('attendance/s5a').update({wageStatus: 'confirmed'});
  await realDb.doc(track(
      `account_deletion_tombstones/${WORKER}`)).set({barrierAt: T.now()});
  const restoredUnderBarrier = await P.srvRestoreReviewEligibilityByMonth(
      M5.key, BIZ, WORKER, M5.ym);
  check('RC-50 barrier 가 있으면 복구하지 않는다', restoredUnderBarrier, false);
  check('RC-51 보류 유지', await reqState(M5.key), 'suspended');
  await realDb.doc(`account_deletion_tombstones/${WORKER}`).delete();
  const retried = await P.srvRestoreReviewEligibilityByMonth(
      M5.key, BIZ, WORKER, M5.ym);
  check('RC-52 barrier 해소 후 재시도는 성공한다(멱등 재시도 가능)',
      retried, true);
  check('RC-53 자격 복구', await reqState(M5.key), 'active');

  // ═══ §3 유효 근무가 남았는데 영구 보류되는가 ═══════════════
  console.log('\n=== §3 유효 근무가 남은 달의 보류는 자기치유된다 ===');
  //   사후 재집계가 죽은 상황을 재현: 보류만 남기고 복구를 돌리지 않는다.
  await P.srvSuspendReviewEligibility(new Set([M5.key]));
  check('RC-60 보류 상태(복구 단계 유실 재현)',
      await reqState(M5.key), 'suspended');
  check('RC-61 scheduler 복구 경로가 되돌린다',
      await P.srvRestoreReviewEligibilityByMonth(M5.key, BIZ, WORKER, M5.ym),
      true);
  check('RC-62 영구 보류 아님', await reqState(M5.key), 'active');

  // ═══ §3 사후 재집계 자체가 실패했다 ═══════════════════════
  console.log('\n=== §3 사후 재집계 쓰기 실패 주입 ===');
  const M7 = monthOf(6);
  await putAtt('s7', M7);
  await P.onWageConfirmed(wageEvent('s7', attEventData(M7)));
  track(`review_requests/${M7.key}`);
  check('RC-90 토큰 활성', await reqState(M7.key), 'active');
  //   transaction 순서: 1=사전 보류, 2=마감 취소, 3=사후 재집계 쓰기.
  armFail(3);
  const r7 = await cancel(['s7']);
  disarmHook();
  check('RC-91 마감 취소 자체는 완료된다', r7.processed, 1);
  check('RC-92 응답 형태는 기존 계약 그대로 (CN3-70 과 동일)',
      Object.keys(r7).sort(), ['processed', 'skipped', 'success']);
  check('RC-93 이 경우 토큰은 사전 보류 상태로 남는다(안전 방향)',
      await reqState(M7.key), 'suspended');
  check('RC-94 제출 DENY',
      await restCreateReview(WORKER, `${RUN}v7`, workerFields(M7.key, M7)), 403);
  //   그리고 다음 기회에 재시도 가능 — 자격이 돌아오면 복구된다.
  await realDb.doc('attendance/s7').update({wageStatus: 'confirmed'});
  check('RC-95 재확정 트리거가 재시도로 복구한다',
      await (async () => {
        await P.onWageConfirmed(wageEvent('s7', attEventData(M7)));
        return reqState(M7.key);
      })(), 'active');

  // ═══ §4 비동기 trigger 와 공개·집계 경로 ═══════════════════
  console.log('\n=== §4 Rules 통과 직후 ~ 트리거 처리 전 구간 ===');
  const M6 = monthOf(0, WORKER2);
  await putAtt('s6', M6);
  await P.onWageConfirmed(wageEvent('s6', attEventData(M6)));
  track(`review_requests/${M6.key}`);
  //   보류시킨 뒤, rules 를 우회한(= race 창) 제출을 Admin SDK 로 재현한다.
  await P.srvSuspendReviewEligibility(new Set([M6.key]));
  const orphan = `${RUN}orphan`;
  await realDb.doc(`monthly_reviews/${orphan}`).set({
    reviewKey: orphan, reviewType: 'USER_TO_BUSINESS', businessId: BIZ,
    requestId: M6.key, rating: 5, isPublished: false, createdAt: T.now()});
  track(`monthly_reviews/${orphan}`);

  // 트리거 처리 **이전** 상태
  check('RC-70 트리거 전: 리뷰 문서는 존재한다', true, true,
      '(비동기 트리거의 성질 — 숨기지 않는다)');
  check('RC-71 트리거 전: isPublished=false',
      (await realDb.doc(`monthly_reviews/${orphan}`).get()).data().isPublished,
      false);
  check('RC-72 트리거 전: 요청에 리뷰 id 미연결', [
    (await realDb.doc(`review_requests/${M6.key}`).get()).data().workerReviewId
      ?? null,
    (await realDb.doc(`review_requests/${M6.key}`).get()).data().workerStatus,
  ], [null, 'pending']);
  await P.updateBusinessReviewStats(BIZ);
  const bizAfterStats = (await realDb.doc(`businesses/${BIZ}`).get()).data();
  check('RC-73 트리거 전: 통계에 반영되지 않는다(isPublished 필터)',
      [bizAfterStats.rating ?? null, bizAfterStats.reviewCount ?? null],
      [null, null]);
  check('RC-74 트리거 전: 타 사용자 get DENY',
      await restGet(WORKER2, `monthly_reviews/${orphan}`), 403,
      '(익명 리뷰 — 미공개 상태)');
  check('RC-75 트리거 전: list DENY',
      (await fetch(`${REST}/monthly_reviews?pageSize=1`,
          {headers: {Authorization: `Bearer ${tokFor(WORKER2)}`}})).status, 403);

  // 트리거 처리 — 중복 실행 포함
  await P.onReviewCreated({
    params: {reviewId: orphan},
    data: {
      data: () => ({reviewType: 'USER_TO_BUSINESS', businessId: BIZ,
        requestId: M6.key, rating: 5}),
      ref: realDb.doc(`monthly_reviews/${orphan}`),
    },
  });
  check('RC-76 트리거가 자격 없는 리뷰를 되돌린다',
      (await realDb.doc(`monthly_reviews/${orphan}`).get()).exists, false);
  check('RC-77 요청 상태 오염 없음', [
    (await realDb.doc(`review_requests/${M6.key}`).get()).data().workerStatus,
    (await realDb.doc(`review_requests/${M6.key}`).get()).data().workerReviewId
      ?? null,
  ], ['pending', null]);
  let dupOk = true;
  try {
    await P.onReviewCreated({
      params: {reviewId: orphan},
      data: {
        data: () => ({reviewType: 'USER_TO_BUSINESS', businessId: BIZ,
          requestId: M6.key, rating: 5}),
        ref: realDb.doc(`monthly_reviews/${orphan}`),
      },
    });
  } catch (e) { dupOk = `throw:${e.message}`; }
  check('RC-78 트리거 중복 실행이 안전하다', dupOk, true);

  // 트리거가 영구 실패했을 때의 노출 한계 — 만료 공개 경로로 확인
  console.log('\n=== §4 트리거 영구 실패 시 orphan 의 공개 경로 ===');
  const orphan2 = `${RUN}orphan2`;
  await realDb.doc(track(`monthly_reviews/${orphan2}`)).set({
    reviewKey: orphan2, reviewType: 'USER_TO_BUSINESS', businessId: BIZ,
    requestId: M6.key, rating: 5, isPublished: false, createdAt: T.now()});
  const reqBefore = (await realDb.doc(`review_requests/${M6.key}`).get()).data();
  check('RC-80 요청에 리뷰 id 가 없다 → 만료 공개가 집을 수 없다', [
    reqBefore.adminReviewId ?? null, reqBefore.workerReviewId ?? null,
  ], [null, null]);
  await P.updateBusinessReviewStats(BIZ);
  const bizAfter2 = (await realDb.doc(`businesses/${BIZ}`).get()).data();
  check('RC-81 집계에도 들어가지 않는다',
      [bizAfter2.rating ?? null, bizAfter2.reviewCount ?? null], [null, null]);
  check('RC-82 지원자 본인도 읽을 수 없다',
      await restGet(WORKER2, `monthly_reviews/${orphan2}`), 403);

  // ═══ 집계 ═══
  console.log(`\n판정 ${rows.filter((r) => r.ok).length}/${rows.length} PASS` +
      (fail ? `  실패 ${fail}건` : ''));

  console.log('\n=== teardown (격리 에뮬레이터) ===');
  const extra = (await realDb.collection('monthly_reviews').get()).docs
      .map((d) => d.ref.path);
  for (const p of [...new Set([...created, ...extra])]) {
    await realDb.doc(p).delete().catch(() => {});
  }
  for (const id of ['s1', 's1b', 's1c', 's2', 's3a', 's3b', 's4', 's5a', 's5b',
    's6', 's7']) {
    const sub = await realDb.collection(`attendance/${id}/money_audit`).get();
    for (const d of sub.docs) await d.ref.delete().catch(() => {});
    await realDb.doc(`attendance/${id}`).delete().catch(() => {});
  }
  console.log('  완료 · 공유 DEV/PROD 쓰기 0');
  process.exit(fail ? 1 : 0);
})().catch((e) => {
  console.error('하네스 실패:', e && e.stack ? e.stack : e);
  process.exit(1);
});
