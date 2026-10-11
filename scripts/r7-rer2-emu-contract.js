/**
 * [R7-REVIEW-ELIGIBILITY-REVOCATION-PATCH.2 §6] 계약 테스트 —
 *   **실제 writer · 실제 Rules** 로 writer → stored state → authority → reader 를
 *   한 줄로 측정한다.
 *
 *   - writer: 컴파일된 `functions/lib/index.js` 의 production 핸들러를
 *     그대로 떼어내 호출한다. 계산식을 테스트에 복제하지 않는다.
 *       · callableCancelFinalConfirmation (마감 취소)
 *       · onWageConfirmed               (요청 생성 · 재확정 복구)
 *       · onReviewCreated               (제출 backstop)
 *     트리거 등록 함수(onCall/onDocumentCreated/onDocumentUpdated)만 핸들러를
 *     그대로 돌려주는 stub 으로 바꾼다 — 로직은 손대지 않는다.
 *   - authority: 실제 `firestore.rules` 를 지나는 REST 쓰기로 allow/deny 측정.
 *   - 격리: demo 프로젝트. 공유 DEV/PROD 를 건드리지 않는다.
 *
 *   실행: firebase emulators:exec --only firestore (포트 6060)
 */
'use strict';

const PROJECT = 'demo-r7rer2';
process.env.GCLOUD_PROJECT = PROJECT;
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:6060';

const fs = require('fs');
const path = require('path');
const ROOT = path.join(__dirname, '..');
const admin = require(path.join(ROOT, 'functions', 'node_modules', 'firebase-admin'));
if (!admin.apps.length) admin.initializeApp({projectId: PROJECT});
const db = admin.firestore();

const REST = `http://127.0.0.1:6060/v1/projects/${PROJECT}/databases/(default)/documents`;

// ── 판정 ────────────────────────────────────────────────────────
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

// ── production 슬라이스 ─────────────────────────────────────────
const SRC = fs.readFileSync(path.join(ROOT, 'functions', 'lib', 'index.js'), 'utf8');
const LINES = SRC.split('\n');

/** `function NAME(` ... 다음 최상위 `}` 까지. */
function sliceFn(name) {
  const i = LINES.findIndex((l) =>
    l.startsWith(`function ${name}(`) || l.startsWith(`async function ${name}(`));
  if (i < 0) throw new Error(`함수 없음: ${name}`);
  const j = LINES.findIndex((l, k) => k > i && l === '}');
  if (j < 0) throw new Error(`끝 못 찾음: ${name}`);
  return LINES.slice(i, j + 1).join('\n');
}
/** `exports.NAME = ` ... 다음 최상위 `});` 까지. */
function sliceExport(name) {
  const i = LINES.findIndex((l) => l.startsWith(`exports.${name} = `));
  if (i < 0) throw new Error(`export 없음: ${name}`);
  const j = LINES.findIndex((l, k) => k > i && l === '});');
  if (j < 0) throw new Error(`끝 못 찾음: ${name}`);
  return LINES.slice(i, j + 1).join('\n').replace(`exports.${name} = `, `const ${name} = `);
}
function sliceConst(decl) {
  const line = LINES.find((l) => l.startsWith(decl));
  if (!line) throw new Error(`상수 없음: ${decl}`);
  return line;
}

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
const updateUserReviewStats = async () => {};
const updateBusinessReviewStats = async () => {};
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
  sliceExport('callableCancelFinalConfirmation'),
  sliceExport('onWageConfirmed'),
  sliceExport('onReviewCreated'),
  `return {srvIsActualFinalizedWork, srvHasActualWorkInMonth,
    srvFindFinalizedWorkDocId, srvSuspendReviewEligibility,
    srvRestoreReviewEligibility, srvRestoreReviewEligibilityByMonth,
    srvReviewRequestKeyOf, callableCancelFinalConfirmation,
    onWageConfirmed, onReviewCreated};`,
].join('\n');

// eslint-disable-next-line no-new-func
const P = new Function('db', 'admin', 'HttpsError', 'notified', BODY)(
    db, admin, HttpsError, notified);

// ── 에뮬레이터 토큰(서명 없음 — Firestore 에뮬레이터는 claim 만 읽는다) ──
function tok(uid) {
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

/** Rules 를 지나는 monthly_reviews create. HTTP 코드를 돌려준다. */
async function restCreateReview(uid, id, fields) {
  const r = await fetch(
      `${REST}/monthly_reviews?documentId=${encodeURIComponent(id)}`,
      {method: 'POST',
        headers: {Authorization: `Bearer ${tok(uid)}`,
          'Content-Type': 'application/json'},
        body: JSON.stringify({fields})});
  return r.status;
}
async function restPatch(uid, docPath, fields) {
  const mask = Object.keys(fields)
      .map((k) => `updateMask.fieldPaths=${encodeURIComponent(k)}`).join('&');
  const r = await fetch(`${REST}/${docPath}?${mask}`,
      {method: 'PATCH',
        headers: {Authorization: `Bearer ${tok(uid)}`,
          'Content-Type': 'application/json'},
        body: JSON.stringify({fields})});
  return r.status;
}

// ── 고정물 ──────────────────────────────────────────────────────
const RUN = 'rer' + Date.now().toString(36);
const BIZ = `${RUN}biz`;
const BIZ2 = `${RUN}biz2`;
const ADMIN = `${RUN}admin`;
const SUB = `${RUN}sub`;
const WORKER = `${RUN}worker`;
const T = admin.firestore.Timestamp;

/**
 * 고정물 근무일은 **현재 기준 상대 시각**이다.
 *
 *   고정 날짜(2026-03)를 쓰면 `deadline = workDate + 14일` 이 이미 지나
 *   관리자 arm 이 기존 deadline 규칙으로 거부된다 — 자격 보류와 무관한
 *   이유로 테스트가 틀린다. 월 경계도 피한다: 같은 달이어야 하는 두 건은
 *   같은 날의 다른 시각으로 둔다.
 */
const kstParts = (d) => {
  const k = new Date(d.getTime() + 9 * 36e5);
  return {year: k.getUTCFullYear(), month: k.getUTCMonth() + 1};
};
const BASE = new Date(Date.now() - 2 * 864e5);
const {year: YEAR, month: MONTH} = kstParts(BASE);
const YM = `${YEAR}-${String(MONTH).padStart(2, '0')}`;
const KEY = `${BIZ}_${WORKER}_${YEAR}_${MONTH}`;
/** 같은 달 안에서 시각만 다른 근무일. */
const workDay = (hourOffset) =>
  T.fromDate(new Date(BASE.getTime() + hourOffset * 36e5));
/** 다른 달 고정물 — 월·yearMonth·key 를 한 식에서 뽑는다. */
function otherMonth(daysBack) {
  const d = new Date(Date.now() - daysBack * 864e5);
  const {year, month} = kstParts(d);
  return {
    date: T.fromDate(d),
    ym: `${year}-${String(month).padStart(2, '0')}`,
    key: `${BIZ}_${WORKER}_${year}_${month}`,
  };
}

const created = [];
function track(p) { created.push(p); return p; }

async function putAttendance(id, over) {
  await db.doc(track(`attendance/${id}`)).set({
    userId: WORKER, businessId: BIZ, yearMonth: YM,
    workDate: workDay(0), status: 'present', wageStatus: 'confirmed',
    finalWage: 90000, applicationId: `${RUN}app`,
    createdAt: T.now(), ...over,
  });
}
async function putRequest(over) {
  await db.doc(track(`review_requests/${KEY}`)).set({
    requestKey: KEY, businessId: BIZ, businessName: 'biz', workerId: WORKER,
    workerName: 'worker', reviewYear: YEAR, reviewMonth: MONTH,
    deadline: T.fromDate(new Date(Date.now() + 7 * 864e5)),
    adminStatus: 'pending', workerStatus: 'pending',
    adminReviewId: null, workerReviewId: null,
    isPublished: false, publishedAt: null, createdAt: T.now(), ...over,
  });
}
const workerReviewFields = (reqId) => ({
  reviewType: str('USER_TO_BUSINESS'), businessId: str(BIZ),
  requestId: str(reqId), rating: int(5), isPublished: bool(false),
  reviewYear: int(YEAR), reviewMonth: int(MONTH), reviewerName: str('익명'),
});
const adminReviewFields = (reqId) => ({
  reviewType: str('ADMIN_TO_USER'), businessId: str(BIZ),
  reviewerId: str(ADMIN), targetUserId: str(WORKER),
  requestId: str(reqId), rating: int(5), isPublished: bool(false),
  reviewYear: int(YEAR), reviewMonth: int(MONTH),
});

const suspendedAt = async () => {
  const s = await db.doc(`review_requests/${KEY}`).get();
  return s.exists ? (s.data().eligibilitySuspendedAt != null) : null;
};
const cancelCall = (ids, uid = ADMIN, biz = BIZ) =>
  P.callableCancelFinalConfirmation(
      {auth: {uid}, data: {businessId: biz, attendanceIds: ids}});

async function fireWageConfirmed(attId) {
  const snap = await db.doc(`attendance/${attId}`).get();
  const after = snap.data();
  await P.onWageConfirmed({
    params: {attendanceId: attId},
    data: {
      before: {data: () => ({...after, wageStatus: 'calculated'})},
      after: {data: () => after},
    },
  });
}

(async () => {
  console.log(`프로젝트: ${PROJECT} (격리 에뮬레이터)`);
  console.log('writer: 컴파일된 production 핸들러 슬라이스 · authority: 실제 rules\n');

  // 공통 고정물
  await db.doc(track(`users/${WORKER}`)).set({uid: WORKER, name: 'worker',
    role: 'USER', accountStatus: 'active', isBlacklisted: false});
  await db.doc(track(`users/${ADMIN}`)).set({uid: ADMIN, name: 'admin',
    role: 'BUSINESS_ADMIN', accountStatus: 'active'});
  await db.doc(track(`users/${SUB}`)).set({uid: SUB, name: 'sub', role: 'USER',
    accountStatus: 'active', isBlacklisted: false, subAdminBusinessIds: [BIZ]});
  await db.doc(track(`businesses/${BIZ}`)).set({businessId: BIZ, name: 'biz',
    ownerId: ADMIN, adminIds: [ADMIN]});
  await db.doc(track(`businesses/${BIZ2}`)).set({businessId: BIZ2, name: 'biz2',
    ownerId: `${RUN}other`, adminIds: [`${RUN}other`]});
  await db.doc(track(`businesses/${BIZ}/members/${SUB}`)).set({
    uid: SUB, permissions: {canManageWorkers: true, canManageWage: false}});
  await db.doc(track(`applications/${RUN}app`)).set({
    uid: WORKER, businessId: BIZ, businessName: 'biz', status: 'CONFIRMED',
    applicantName: 'worker'});

  // ═══ §6-1 단일 확정 근무 → 리뷰 요청 생성 (real onWageConfirmed) ═══
  console.log('=== §6-1 단일 확정 근무 → 리뷰 요청 생성 ===');
  await putAttendance('a1');
  await fireWageConfirmed('a1');
  const req1 = await db.doc(`review_requests/${KEY}`).get();
  track(`review_requests/${KEY}`);
  check('RER-01a 요청 생성됨(canonical writer)', req1.exists, true);
  check('RER-01b 보류 아님', req1.data().eligibilitySuspendedAt ?? null, null);
  check('RER-01c 지원자 제출 허용(기준선)',
      await restCreateReview(WORKER, `${RUN}r1`, workerReviewFields(KEY)), 200);
  await db.doc(`monthly_reviews/${RUN}r1`).delete();
  await db.doc(`review_requests/${KEY}`).update(
      {workerStatus: 'pending', workerReviewId: null});

  // ═══ §6-2 마지막 확정 근무 마감 취소 → 미제출 리뷰 차단 ═══
  console.log('\n=== §6-2 마지막 확정 근무 마감 취소 → 차단 ===');
  const c2 = await cancelCall(['a1']);
  check('RER-02a 마감 취소 1건 처리', c2.processed, 1);
  const a1 = await db.doc('attendance/a1').get();
  check('RER-02b wageStatus=calculated', a1.data().wageStatus, 'calculated');
  check('RER-02c 요청 보류됨', await suspendedAt(), true);
  check('RER-02d 지원자 제출 DENY(rules)',
      await restCreateReview(WORKER, `${RUN}r2`, workerReviewFields(KEY)), 403);
  check('RER-02e 관리자 제출 DENY(rules)',
      await restCreateReview(ADMIN, `${RUN}r2a`, adminReviewFields(KEY)), 403);
  check('RER-02f 근태 기록 보존(삭제 아님)', a1.exists, true);

  // ═══ §6-4 재확정 → 자격 복구 ═══
  console.log('\n=== §6-4 마감 취소 → 재확정 → 자격 복구 ===');
  await db.doc('attendance/a1').update({wageStatus: 'confirmed'});
  await fireWageConfirmed('a1');
  check('RER-04a 보류 해제', await suspendedAt(), false);
  const rq4 = await db.doc(`review_requests/${KEY}`).get();
  check('RER-04b deadline 불변(연장·초기화 없음)',
      rq4.data().deadline.toMillis() === req1.data().deadline.toMillis(), true);
  check('RER-04c 제출 허용',
      await restCreateReview(WORKER, `${RUN}r4`, workerReviewFields(KEY)), 200);
  await db.doc(`monthly_reviews/${RUN}r4`).delete();

  // ═══ §6-6 재확정 → scheduler 중복 실행 ═══
  console.log('\n=== §6-6 재확정 + scheduler 중복 실행 ===');
  await fireWageConfirmed('a1');
  await P.srvRestoreReviewEligibilityByMonth(KEY, BIZ, WORKER, YM);
  await P.srvRestoreReviewEligibilityByMonth(KEY, BIZ, WORKER, YM);
  const rq6 = await db.doc(`review_requests/${KEY}`).get();
  check('RER-06a 요청 1개 유지(중복 생성 없음)',
      (await db.collection('review_requests')
          .where('requestKey', '==', KEY).get()).size, 1);
  check('RER-06b createdAt 불변',
      rq6.data().createdAt.toMillis() === req1.data().createdAt.toMillis(), true);
  check('RER-06c deadline 불변',
      rq6.data().deadline.toMillis() === req1.data().deadline.toMillis(), true);

  // ═══ §6-3 같은 달 다른 확정 근무 존재 → 자격 유지 ═══
  console.log('\n=== §6-3 같은 달 다른 확정 근무 존재 → 자격 유지 ===');
  await putAttendance('a2', {workDate: workDay(1)});
  const c3 = await cancelCall(['a1']);
  check('RER-03a 취소 1건', c3.processed, 1);
  check('RER-03b 오차단 없음 — 보류 해제 수렴', await suspendedAt(), false);
  check('RER-03c 제출 허용',
      await restCreateReview(WORKER, `${RUN}r3`, workerReviewFields(KEY)), 200);
  await db.doc(`monthly_reviews/${RUN}r3`).delete();
  check('RER-03d 둘 다 취소하면 보류',
      (await cancelCall(['a2'])).processed, 1);
  check('RER-03e 보류 상태', await suspendedAt(), true);
  check('RER-03f 제출 DENY',
      await restCreateReview(WORKER, `${RUN}r3b`, workerReviewFields(KEY)), 403);

  // ═══ §6-5 마감 취소 ↔ 제출 동시 경쟁 (backstop) ═══
  console.log('\n=== §6-5 동시 경쟁 — rules 를 통과한 제출의 backstop ===');
  //   rules 의 get() 과 보류 쓰기의 직렬화는 보장되지 않는다. 그 창에서
  //   들어온 제출을 Admin SDK 쓰기로 재현하고(= rules 우회), production
  //   onReviewCreated 가 그것을 되돌리는지 본다.
  const raceId = `${RUN}race`;
  await db.doc(`monthly_reviews/${raceId}`).set({
    reviewKey: raceId, reviewType: 'USER_TO_BUSINESS', businessId: BIZ,
    requestId: KEY, rating: 5, isPublished: false,
    reviewYear: YEAR, reviewMonth: MONTH, createdAt: T.now()});
  await P.onReviewCreated({
    params: {reviewId: raceId},
    data: {
      data: () => ({reviewType: 'USER_TO_BUSINESS', businessId: BIZ,
        requestId: KEY, rating: 5}),
      ref: db.doc(`monthly_reviews/${raceId}`),
    },
  });
  check('RER-05a 자격 없는 리뷰 삭제됨(onReviewCreated)',
      (await db.doc(`monthly_reviews/${raceId}`).get()).exists, false);
  const rq5 = await db.doc(`review_requests/${KEY}`).get();
  check('RER-05b 요청 상태 오염 없음', rq5.data().workerStatus, 'pending');

  // ═══ §4 늦게 도착한 생성 트리거 — 근거가 사라진 뒤 ═══
  console.log('\n=== §4 늦게 도착한 onWageConfirmed 는 토큰을 새로 만들지 않는다 ===');
  //   마감 취소가 **요청이 없던 달**을 되돌리면 세울 토큰이 없다. 그 뒤
  //   늦게 도착한 생성 트리거가 근거 없는 토큰을 만들면 보류도 안 걸린다.
  //   event 는 confirmed 를 들고 오지만 문서는 이미 calculated 인 상황.
  const MLATE = otherMonth(150);
  await db.doc(track('attendance/aLate')).set({
    userId: WORKER, businessId: BIZ, yearMonth: MLATE.ym,
    workDate: MLATE.date, status: 'present', wageStatus: 'confirmed',
    finalWage: 50000, applicationId: `${RUN}app`, createdAt: T.now()});
  const lateEvent = {
    params: {attendanceId: 'aLate'},
    data: {
      before: {data: () => ({wageStatus: 'calculated', status: 'present'})},
      after: {data: () => ({
        userId: WORKER, businessId: BIZ, yearMonth: MLATE.ym,
        workDate: MLATE.date, status: 'present', wageStatus: 'confirmed',
        applicationId: `${RUN}app`})},
    },
  };
  await db.doc('attendance/aLate').update({wageStatus: 'calculated'});
  await P.onWageConfirmed(lateEvent);
  check('RER-17a 근거가 사라진 뒤 도착한 트리거는 요청을 만들지 않는다',
      (await db.doc(`review_requests/${MLATE.key}`).get()).exists, false);
  await db.doc('attendance/aLate').update({wageStatus: 'confirmed'});
  await P.onWageConfirmed(lateEvent);
  check('RER-17b 근거가 살아 있으면 정상 생성(기능 보존)',
      (await db.doc(track(`review_requests/${MLATE.key}`)).get()).exists, true);

  // ═══ §6-11 이체 취소(transferred → confirmed)는 자격 유지 ═══
  console.log('\n=== §6-11 이체 취소는 자격 유지 ===');
  await db.doc('attendance/a2').update({wageStatus: 'transferred'});
  await P.srvRestoreReviewEligibilityByMonth(KEY, BIZ, WORKER, YM);
  check('RER-11a transferred 도 확정 근무', await suspendedAt(), false);
  const c11 = await cancelCall(['a2']);
  check('RER-11b 마감 취소는 transferred 를 건너뛴다', c11.processed, 0);
  check('RER-11c 보류하지 않음', await suspendedAt(), false);
  await db.doc('attendance/a2').update({wageStatus: 'confirmed'});
  check('RER-11d 이체 취소 후(confirmed) 제출 허용',
      await restCreateReview(WORKER, `${RUN}r11`, workerReviewFields(KEY)), 200);
  await db.doc(`monthly_reviews/${RUN}r11`).delete();

  // ═══ §6-7 관리자만 제출한 뒤 마감 취소 ═══
  console.log('\n=== §6-7 관리자만 제출 후 마감 취소 ===');
  const adminRid = `${RUN}adm7`;
  check('RER-07a 관리자 제출 허용(취소 전)',
      await restCreateReview(ADMIN, adminRid, adminReviewFields(KEY)), 200);
  await db.doc(`review_requests/${KEY}`).update(
      {adminStatus: 'submitted', adminReviewId: adminRid});
  await db.doc('attendance/a1').update({wageStatus: 'calculated'});
  const c7 = await cancelCall(['a2']);
  check('RER-07b 취소 1건', c7.processed, 1);
  check('RER-07c 미제출 쪽 보류', await suspendedAt(), true);
  check('RER-07d 제출된 관리자 리뷰 보존(삭제 아님)',
      (await db.doc(`monthly_reviews/${adminRid}`).get()).exists, true);
  check('RER-07e 지원자 제출 DENY',
      await restCreateReview(WORKER, `${RUN}r7`, workerReviewFields(KEY)), 403);

  // ═══ §6-8 지원자만 제출한 뒤 마감 취소 ═══
  console.log('\n=== §6-8 지원자만 제출 후 마감 취소 ===');
  await db.doc(`review_requests/${KEY}`).update({
    adminStatus: 'pending', adminReviewId: null,
    eligibilitySuspendedAt: admin.firestore.FieldValue.delete()});
  await db.doc('attendance/a2').update({wageStatus: 'confirmed'});
  const workerRid = `${RUN}wrk8`;
  check('RER-08a 지원자 제출 허용(취소 전)',
      await restCreateReview(WORKER, workerRid, workerReviewFields(KEY)), 200);
  await db.doc(`review_requests/${KEY}`).update(
      {workerStatus: 'submitted', workerReviewId: workerRid});
  const c8 = await cancelCall(['a2']);
  check('RER-08b 취소 1건', c8.processed, 1);
  check('RER-08c 미제출 쪽 보류', await suspendedAt(), true);
  check('RER-08d 제출된 지원자 리뷰 보존',
      (await db.doc(`monthly_reviews/${workerRid}`).get()).exists, true);
  check('RER-08e 관리자 제출 DENY',
      await restCreateReview(ADMIN, `${RUN}r8`, adminReviewFields(KEY)), 403);

  // ═══ §6-9 양쪽 제출 완료 이후 마감 취소 ═══
  console.log('\n=== §6-9 양쪽 제출 완료 이후 마감 취소 ===');
  await db.doc(`review_requests/${KEY}`).update({
    adminStatus: 'submitted', adminReviewId: adminRid,
    workerStatus: 'submitted', workerReviewId: workerRid,
    eligibilitySuspendedAt: admin.firestore.FieldValue.delete()});
  await db.doc('attendance/a2').update({wageStatus: 'confirmed'});
  const c9 = await cancelCall(['a2']);
  check('RER-09a 취소 1건', c9.processed, 1);
  check('RER-09b 보류하지 않음(미제출 권한 없음)', await suspendedAt(), false);
  check('RER-09c 양쪽 리뷰 보존', [
    (await db.doc(`monthly_reviews/${adminRid}`).get()).exists,
    (await db.doc(`monthly_reviews/${workerRid}`).get()).exists,
  ], [true, true]);

  // ═══ §6-10 만료 요청의 재확정 처리 ═══
  console.log('\n=== §6-10 만료 요청의 재확정 ===');
  await db.doc(`review_requests/${KEY}`).update({
    adminStatus: 'pending', adminReviewId: null,
    workerStatus: 'pending', workerReviewId: null,
    deadline: T.fromDate(new Date(Date.now() - 3 * 864e5)),
    eligibilitySuspendedAt: T.now()});
  await db.doc('attendance/a2').update({wageStatus: 'confirmed'});
  await fireWageConfirmed('a2');
  check('RER-10a 보류는 풀린다', await suspendedAt(), false);
  const rq10 = await db.doc(`review_requests/${KEY}`).get();
  check('RER-10b deadline 은 과거 그대로(연장 없음)',
      rq10.data().deadline.toMillis() < Date.now(), true);
  check('RER-10c 관리자 제출 DENY(rules deadline)',
      await restCreateReview(ADMIN, `${RUN}r10a`, adminReviewFields(KEY)), 403);
  const expiredRid = `${RUN}r10w`;
  const wStatus = await restCreateReview(
      WORKER, expiredRid, workerReviewFields(KEY));
  check('RER-10d 지원자 rules 는 deadline 을 보지 않는다(기존 계약)',
      wStatus, 200);
  await P.onReviewCreated({
    params: {reviewId: expiredRid},
    data: {
      data: () => ({reviewType: 'USER_TO_BUSINESS', businessId: BIZ,
        requestId: KEY, rating: 5}),
      ref: db.doc(`monthly_reviews/${expiredRid}`),
    },
  });
  check('RER-10e 기한 경과 제출은 서버가 되돌린다(기존 계약)',
      (await db.doc(`monthly_reviews/${expiredRid}`).get()).exists, false);

  // ═══ §6-12 NO_SHOW/ABSENT 만 있는 월 ═══
  console.log('\n=== §6-12 NO_SHOW/ABSENT 만 있는 월 ===');
  const M12 = otherMonth(60);
  await db.doc(track('attendance/a12')).set({
    userId: WORKER, businessId: BIZ, yearMonth: M12.ym,
    workDate: M12.date,
    status: 'NO_SHOW', wageStatus: 'confirmed', finalWage: 0,
    applicationId: `${RUN}app`, createdAt: T.now()});
  await fireWageConfirmed('a12');
  check('RER-12a 요청 미생성',
      (await db.doc(`review_requests/${M12.key}`).get()).exists, false);
  check('RER-12b canonical 술어가 false',
      P.srvIsActualFinalizedWork('NO_SHOW', 'confirmed'), false);
  check('RER-12c 월 자격 없음',
      await P.srvHasActualWorkInMonth(BIZ, WORKER, M12.ym), false);

  // ═══ §6-13 0분 인정 · 근태 검토 중 ═══
  console.log('\n=== §6-13 0분 인정·근태 검토 중 ===');
  const M13 = otherMonth(110);
  await db.doc(track('attendance/a13')).set({
    userId: WORKER, businessId: BIZ, yearMonth: M13.ym,
    workDate: M13.date,
    status: 'present', wageStatus: 'pending', isZeroWork: true,
    applicationId: `${RUN}app`, createdAt: T.now()});
  check('RER-13a 미확정은 자격 없음',
      await P.srvHasActualWorkInMonth(BIZ, WORKER, M13.ym), false);
  check('RER-13b 요청 미생성',
      (await db.doc(`review_requests/${M13.key}`).get()).exists, false);
  check('RER-13c isZeroWork 단독으로 판정하지 않는다 — status·wageStatus 가 술어',
      P.srvIsActualFinalizedWork('present', 'pending'), false);

  // ═══ §6-14 SubAdmin 권한 · 다른 사업장 경계 ═══
  console.log('\n=== §6-14 SubAdmin 권한 · 사업장 경계 ===');
  await db.doc('attendance/a2').update({wageStatus: 'confirmed'});
  await db.doc(`review_requests/${KEY}`).update({
    eligibilitySuspendedAt: admin.firestore.FieldValue.delete(),
    deadline: T.fromDate(new Date(Date.now() + 7 * 864e5))});
  let subDenied = null;
  try {
    await cancelCall(['a2'], SUB);
    subDenied = 'allowed';
  } catch (e) { subDenied = e.code; }
  check('RER-14a canManageWage 없는 SubAdmin 거부', subDenied,
      'permission-denied');
  check('RER-14b 거부 후 보류 없음(쓰기 0)', await suspendedAt(), false);
  let crossDenied = null;
  try {
    await cancelCall(['a2'], ADMIN, BIZ2);
    crossDenied = 'allowed';
  } catch (e) { crossDenied = e.code; }
  check('RER-14c 소속 아닌 사업장 호출 거부', crossDenied, 'permission-denied');
  // 소속 사업장으로 호출하되 **다른 사업장의 근태 id** 를 섞는다 —
  //   businessId 교차검증이 자격 보류까지 막는지 본다.
  await db.doc(track('attendance/aOther')).set({
    userId: WORKER, businessId: BIZ2, yearMonth: YM, workDate: workDay(0),
    status: 'present', wageStatus: 'confirmed', finalWage: 10,
    applicationId: `${RUN}app`, createdAt: T.now()});
  const c14 = await cancelCall(['aOther'], ADMIN, BIZ);
  check('RER-14d 타 사업장 근태는 처리 0건', c14.processed, 0);
  check('RER-14e 타 사업장 근태가 이 달을 보류시키지 않음',
      await suspendedAt(), false);
  check('RER-14f 타 사업장 근태 보존',
      (await db.doc('attendance/aOther').get()).data().wageStatus, 'confirmed');

  // ═══ §6-15 기존 정상 흐름 회귀 — 필드 없는 레거시 문서 ═══
  console.log('\n=== §6-15 레거시 문서 회귀(migration 불필요) ===');
  const LEG = `${BIZ}_${WORKER}_2025_12`;
  await db.doc(track(`review_requests/${LEG}`)).set({
    requestKey: LEG, businessId: BIZ, workerId: WORKER, workerName: 'worker',
    reviewYear: 2025, reviewMonth: 12,
    deadline: T.fromDate(new Date(Date.now() + 7 * 864e5)),
    adminStatus: 'pending', workerStatus: 'pending',
    isPublished: false, createdAt: T.now()});
  check('RER-15a 필드 부재 문서로 지원자 제출 허용',
      await restCreateReview(WORKER, `${RUN}r15`, {
        ...workerReviewFields(LEG), reviewYear: int(2025), reviewMonth: int(12),
      }), 200);
  check('RER-15b 필드 부재 문서로 관리자 제출 허용',
      await restCreateReview(ADMIN, `${RUN}r15a`, {
        ...adminReviewFields(LEG), reviewYear: int(2025), reviewMonth: int(12),
      }), 200);

  // ═══ §4 클라이언트가 보류를 지울 수 없다 ═══
  console.log('\n=== §4 보류 필드는 서버 전용 ===');
  await db.doc(`review_requests/${KEY}`).update({eligibilitySuspendedAt: T.now()});
  check('RER-16a 지원자가 보류 필드 삭제 시도 DENY',
      await restPatch(WORKER, `review_requests/${KEY}`,
          {eligibilitySuspendedAt: {nullValue: null}}), 403);
  check('RER-16b 관리자가 보류 필드 삭제 시도 DENY',
      await restPatch(ADMIN, `review_requests/${KEY}`,
          {eligibilitySuspendedAt: {nullValue: null}}), 403);
  check('RER-16c 보류 유지', await suspendedAt(), true);

  // ═══ 집계 ═══
  console.log(`\n판정 ${rows.filter((r) => r.ok).length}/${rows.length} PASS` +
      (fail ? `  실패 ${fail}건` : ''));

  console.log('\n=== teardown (격리 에뮬레이터) ===');
  const extra = (await db.collection('monthly_reviews').get()).docs
      .map((d) => d.ref.path);
  for (const p of [...new Set([...created, ...extra])]) {
    await db.doc(p).delete().catch(() => {});
  }
  const subcol = await db.collection(`businesses/${BIZ}/members`).get();
  for (const d of subcol.docs) await d.ref.delete().catch(() => {});
  console.log('  완료 · 공유 DEV/PROD 쓰기 0');
  process.exit(fail ? 1 : 0);
})().catch((e) => {
  console.error('하네스 실패:', e && e.stack ? e.stack : e);
  process.exit(1);
});
