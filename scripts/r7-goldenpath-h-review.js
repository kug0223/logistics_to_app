/**
 * [R7-GOLDEN-PATH-DEV-E2E] Step H — 양방향 리뷰.
 *
 *   리뷰 쓰기의 canonical 경계는 **Firestore rules** 다(CF 없음).
 *   따라서 Admin SDK 로 쓰면 rules 를 통째로 건너뛴다 — §27 위반이다.
 *   사용자 ID 토큰으로 Firestore REST commit 을 보내 **앱과 같은 경로**로
 *   쓴다. rules 가 그대로 평가된다.
 */
'use strict';
const https = require('https');
const fs = require('fs');
const lib = require('./r7-fixture-lib');
const {db} = lib;

const PROJECT = lib.EXPECTED_PROJECT;
const DOCS = `/v1/projects/${PROJECT}/databases/(default)/documents`;

function req(method, path, body, idToken) {
  return new Promise((resolve, reject) => {
    const payload = body ? JSON.stringify(body) : null;
    const r = https.request({
      host: 'firestore.googleapis.com', path, method,
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer ' + idToken,
        ...(payload ? {'Content-Length': Buffer.byteLength(payload)} : {}),
      },
    }, (res) => {
      res.setEncoding('utf8');
      let buf = '';
      res.on('data', (c) => { buf += c; });
      res.on('end', () => resolve({status: res.statusCode, body: buf}));
    });
    r.on('error', reject);
    if (payload) r.write(payload);
    r.end();
  });
}

// JS 값 → Firestore REST Value
function val(v) {
  if (v === null || v === undefined) return {nullValue: null};
  if (typeof v === 'boolean') return {booleanValue: v};
  if (typeof v === 'number') {
    return Number.isInteger(v) ? {integerValue: String(v)} : {doubleValue: v};
  }
  if (typeof v === 'string') return {stringValue: v};
  if (Array.isArray(v)) return {arrayValue: {values: v.map(val)}};
  if (v instanceof Date) return {timestampValue: v.toISOString()};
  return {mapValue: {fields: fields(v)}};
}
function fields(o) {
  const f = {};
  for (const [k, v] of Object.entries(o)) {
    if (v !== undefined) f[k] = val(v);
  }
  return f;
}

/** rules 가 평가되는 경로로 문서 생성(존재하면 실패). */
async function createAs(uid, col, docId, data) {
  const token = await lib.idTokenFor(uid);
  const r = await req('POST',
    `${DOCS}/${col}?documentId=${encodeURIComponent(docId)}`,
    {fields: fields(data)}, token);
  return r;
}

(async () => {
  const L = JSON.parse(fs.readFileSync('.goldenpath.json', 'utf8'));
  const requestId = `${L.businessId}_${L.applicantUid}_2026_10`;
  const rr = (await db.collection('review_requests').doc(requestId).get())
    .data();
  const to = (await db.collection('tos').doc(L.toId).get()).data();
  const worker = (await db.collection('users').doc(L.applicantUid).get()).data();

  // ── ADMIN_TO_USER: 관리자가 근로자를 평가 ──────────────────────
  const adminKey = `${L.businessId}_${L.applicantUid}_2026_10`;
  console.log('— ADMIN_TO_USER 생성 (관리자 ID 토큰, rules 평가)');
  let r = await createAs(L.adminUid, 'monthly_reviews', adminKey, {
    reviewKey: adminKey,
    reviewType: 'ADMIN_TO_USER',
    reviewerId: L.adminUid,
    reviewerName: rr.businessName ?? to.businessName,
    businessId: L.businessId,
    businessName: rr.businessName ?? to.businessName,
    targetUserId: L.applicantUid,
    targetUserName: worker.name ?? '근무자',
    reviewYear: 2026, reviewMonth: 10,
    workDaysInMonth: 1, normalAttendanceDays: 1, lateDays: 0,
    rating: 5, wouldRehire: true,
    positiveTags: ['성실함'], improvementTags: [],
    comment: '[GOLDEN PATH] 테스트 평가',
    requestId,
    isPublished: false,
  });
  console.log('  status:', r.status,
    r.status === 200 ? '(생성)' : r.body.slice(0, 200));

  // rating 범위 밖은 rules 가 막아야 한다 — 같은 경로로 확인.
  console.log('\n— rating=9 (rules 가 막아야 한다)');
  const bad = await createAs(L.adminUid, 'monthly_reviews',
    adminKey + '_zzbad', {
      reviewKey: adminKey + '_zzbad', reviewType: 'ADMIN_TO_USER',
      reviewerId: L.adminUid, reviewerName: 'x',
      businessId: L.businessId, businessName: 'x',
      targetUserId: L.applicantUid, targetUserName: 'x',
      reviewYear: 2026, reviewMonth: 10,
      workDaysInMonth: 1, normalAttendanceDays: 1, lateDays: 0,
      rating: 9, wouldRehire: true,
      positiveTags: [], improvementTags: [], requestId,
      isPublished: false,
    });
  console.log('  status:', bad.status,
    bad.status === 403 ? '(차단 — 기대대로)' : bad.body.slice(0, 160));

  // ── USER_TO_BUSINESS: 근로자가 사업장을 평가(익명) ────────────
  const userKey = `${L.businessId}_${L.applicantUid}_2026_10_U`;
  console.log('\n— USER_TO_BUSINESS 생성 (근로자 ID 토큰)');
  r = await createAs(L.applicantUid, 'monthly_reviews', userKey, {
    reviewKey: userKey,
    reviewType: 'USER_TO_BUSINESS',
    businessId: L.businessId,
    businessName: rr.businessName ?? to.businessName,
    reviewYear: 2026, reviewMonth: 10,
    rating: 4, wouldRehire: true,
    positiveTags: ['급여 정확'], improvementTags: [],
    comment: '[GOLDEN PATH] 테스트 평가',
    requestId,
    isPublished: false,
  });
  console.log('  status:', r.status,
    r.status === 200 ? '(생성)' : r.body.slice(0, 250));

  // ── 결과 확인 (읽기만) ────────────────────────────────────────
  const mr = await db.collection('monthly_reviews').get();
  console.log('\n=== Step H 결과 ===');
  console.log('  monthly_reviews:', mr.size);
  mr.forEach((d) => {
    const v = d.data();
    console.log('  ', v.reviewType, '| rating', v.rating,
      '| isPublished =', v.isPublished,
      '| reviewerId 있음 =', v.reviewerId !== undefined);
  });
  const rr2 = (await db.collection('review_requests').doc(requestId).get())
    .data();
  console.log('  요청 상태: adminStatus =', rr2.adminStatus,
    '| workerStatus =', rr2.workerStatus);

  process.exit(0);
})().catch((e) => { console.error('실패:', e.message); process.exit(1); });
