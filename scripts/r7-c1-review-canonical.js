/**
 * [R7-GOLDEN-PATH-DEV-E2E.1 §C] 리뷰 — canonical identity + 원자적 커밋.
 *
 *   §12 — 리뷰 쓰기의 유일한 경계는 Firestore rules 다(CF 없음). Admin SDK 로
 *   쓰면 rules 를 건너뛴다. 그래서 **사용자 ID 토큰 + Firestore REST** 로 쓴다.
 *
 *   직전 Phase 와 달라진 것:
 *     1) 문서 ID 를 production 규칙대로 만든다.
 *        ADMIN_TO_USER      : {businessId}_{targetUserId}_{year}_{month}
 *        USER_TO_BUSINESS   : biz_{businessId}_{year}_{month}_{sha256(..)[0:16]}
 *        (직전에는 `{biz}_{uid}_..._U` 로 써서 **작성자 uid 가 ID 에 노출**됐다)
 *     2) 리뷰 문서와 review_requests 상태를 **한 commit** 에 넣는다 —
 *        Dart 의 runTransaction 이 만드는 원자적 결과와 같은 결과다.
 *     3) createdAt 을 서버 시각 transform 으로 쓴다 (Dart 와 같은 의미).
 *     4) 직렬화 필드는 MonthlyReviewModel.toMap() 과 같게 맞춘다 —
 *        USER_TO_BUSINESS 는 reviewerId 없음 · targetUserId 는 키만 있고 null.
 *
 *   여전히 Dart 코드 자체가 실행되는 것은 아니다(그 사실은 보고에 남긴다).
 */
'use strict';
const https = require('https');
const crypto = require('crypto');
const fs = require('fs');
const lib = require('./r7-fixture-lib');
const {db} = lib;

const PROJECT = lib.EXPECTED_PROJECT;
const DOCS = `projects/${PROJECT}/databases/(default)/documents`;

function request(method, path, body, idToken) {
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

function val(v) {
  if (v === null || v === undefined) return {nullValue: null};
  if (typeof v === 'boolean') return {booleanValue: v};
  if (typeof v === 'number') {
    return Number.isInteger(v) ? {integerValue: String(v)} : {doubleValue: v};
  }
  if (typeof v === 'string') return {stringValue: v};
  if (Array.isArray(v)) return {arrayValue: {values: v.map(val)}};
  return {mapValue: {fields: fields(v)}};
}
function fields(o) {
  const f = {};
  for (const [k, v] of Object.entries(o)) f[k] = val(v);
  return f;
}

/** MonthlyReviewModel.generateKeyForBusiness 와 같은 계산. */
function keyForBusiness(businessId, reviewerId, year, month) {
  const raw = `${businessId}_${reviewerId}_${year}_${month}`;
  const hash = crypto.createHash('sha256').update(raw, 'utf8')
    .digest('hex').slice(0, 16);
  return `biz_${businessId}_${year}_${month}_${hash}`;
}

/** 리뷰 + 요청 상태를 한 commit 으로 — Dart 트랜잭션과 같은 원자성. */
async function commitReview(uid, reviewId, reviewFields, requestId, reqPatch) {
  const token = await lib.idTokenFor(uid);
  return request('POST', `/v1/${DOCS}:commit`, {
    writes: [
      {
        update: {
          name: `${DOCS}/monthly_reviews/${reviewId}`,
          fields: fields(reviewFields),
        },
        updateTransforms: [
          {fieldPath: 'createdAt', setToServerValue: 'REQUEST_TIME'},
        ],
        currentDocument: {exists: false},
      },
      {
        update: {
          name: `${DOCS}/review_requests/${requestId}`,
          fields: fields(reqPatch),
        },
        updateMask: {fieldPaths: Object.keys(reqPatch)},
      },
    ],
  }, token);
}

(async () => {
  const B = JSON.parse(fs.readFileSync('.b1fixture.json', 'utf8'));
  const requestId = `${B.businessId}_${B.uid}_2026_10`;
  const rrSnap = await db.collection('review_requests').doc(requestId).get();
  if (!rrSnap.exists) {
    throw new Error('review_request 없음 — 급여 확정이 선행돼야 한다');
  }
  const rr = rrSnap.data();
  console.log('요청:', requestId.slice(0, 28) + '…',
    '| adminStatus', rr.adminStatus, '| workerStatus', rr.workerStatus);

  const worker = (await db.collection('users').doc(B.uid).get()).data();
  const bizName = rr.businessName;

  // ── ADMIN_TO_USER ───────────────────────────────────────────
  const adminKey = `${B.businessId}_${B.uid}_2026_10`;
  console.log('\n— ADMIN_TO_USER');
  console.log('  문서 ID:', adminKey.slice(0, 30) + '…');
  let r = await commitReview(B.adminUid, adminKey, {
    reviewKey: adminKey,
    reviewType: 'ADMIN_TO_USER',
    reviewerName: bizName,
    reviewerId: B.adminUid,
    businessId: B.businessId,
    businessName: bizName,
    targetUserId: B.uid,
    targetUserName: worker.name ?? '근무자',
    targetUserGender: null,
    targetUserAge: null,
    reviewYear: 2026, reviewMonth: 10,
    workDaysInMonth: 1, normalAttendanceDays: 1, lateDays: 0,
    rating: 5, wouldRehire: true,
    positiveTags: ['성실함'], improvementTags: [],
    comment: '[BOUNDARY C] 테스트 평가',
    isPublished: false, publishAt: null,
    requestId,
  }, requestId, {adminStatus: 'submitted', adminReviewId: adminKey});
  console.log('  status:', r.status,
    r.status === 200 ? '(생성)' : r.body.slice(0, 220));

  // ── USER_TO_BUSINESS (익명) ─────────────────────────────────
  const userKey = keyForBusiness(B.businessId, B.uid, 2026, 10);
  console.log('\n— USER_TO_BUSINESS');
  console.log('  문서 ID:', userKey);
  console.log('  ID 에 작성자 uid 포함:', userKey.includes(B.uid));
  r = await commitReview(B.uid, userKey, {
    reviewKey: userKey,
    reviewType: 'USER_TO_BUSINESS',
    reviewerName: '익명',
    businessId: B.businessId,
    businessName: bizName,
    // toMap() 과 같게 — 키는 있고 값은 null
    targetUserId: null, targetUserName: null,
    targetUserGender: null, targetUserAge: null,
    reviewYear: 2026, reviewMonth: 10,
    workDaysInMonth: 1, normalAttendanceDays: null, lateDays: null,
    rating: 4, wouldRehire: true,
    positiveTags: ['급여 정확'], improvementTags: [],
    comment: '[BOUNDARY C] 테스트 평가',
    isPublished: false, publishAt: null,
    requestId,
  }, requestId, {workerStatus: 'submitted', workerReviewId: userKey});
  console.log('  status:', r.status,
    r.status === 200 ? '(생성)' : r.body.slice(0, 300));

  // ── 중복 제출 — 같은 키로 다시 ──────────────────────────────
  console.log('\n— 같은 달 재제출 (중복이어야 막힌다)');
  r = await commitReview(B.uid, userKey, {
    reviewKey: userKey, reviewType: 'USER_TO_BUSINESS', reviewerName: '익명',
    businessId: B.businessId, businessName: bizName,
    reviewYear: 2026, reviewMonth: 10, workDaysInMonth: 1,
    rating: 1, wouldRehire: false,
    positiveTags: [], improvementTags: [], isPublished: false,
    requestId,
  }, requestId, {workerStatus: 'submitted'});
  console.log('  status:', r.status,
    r.status === 409 || r.status === 400 ? '(차단 — 기대대로)' :
      r.body.slice(0, 160));

  process.exit(0);
})().catch((e) => { console.error('실패:', e.message); process.exit(1); });
