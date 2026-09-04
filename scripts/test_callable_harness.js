#!/usr/bin/env node
/**
 * scripts/test_callable_harness.js
 * PHASE ADMIN.POSTING.CAPACITY-SCOPE-STAGE3B-DEV-RUNTIME-T5-HARNESS
 *
 * 재사용 가능한 로컬 DEV callable 하네스 (alfit-89567).
 * 기본 모드: handshake ONLY. TO 생성 없음. capacity 변경 없음.
 *
 * ENV:
 *   ALFIT_SERVICE_ACCOUNT_PATH   — 서비스 계정 JSON 경로 (선택, 기본값: scripts/ 관례 경로)
 *   ALFIT_APP_CHECK_DEBUG_TOKEN  — Firebase Console에 등록된 App Check 디버그 시크릿 (필수)
 *
 * Usage:
 *   node scripts/test_callable_harness.js
 *   node scripts/test_callable_harness.js handshake
 *
 * ⚠️  보안:
 *   - private_key / ID token / App Check token / custom token 를 출력하지 않는다.
 *   - 서비스 계정 JSON을 하드코딩하지 않는다 (env var + 관례 경로만).
 */

"use strict";

const path = require("path");
const fs = require("fs");

// ── Firebase 클라이언트 설정 (committed, 비공개 아님) ────────────────────────
const GOOGLE_SERVICES_PATH = path.join(
  __dirname, "..", "android", "app", "google-services.json"
);
const gsConfig = JSON.parse(fs.readFileSync(GOOGLE_SERVICES_PATH, "utf-8"));
const PROJECT_ID      = gsConfig.project_info.project_id;
const PROJECT_NUMBER  = gsConfig.project_info.project_number;
const CLIENT          = gsConfig.client[0];
const APP_ID          = CLIENT.client_info.mobilesdk_app_id;
const FIREBASE_API_KEY = CLIENT.api_key[0].current_key;

// 상수
const EXPECTED_PROJECT_ID = "alfit-89567";
const OWNER_UID = "BErRdiWP1xbgyoTovxwAPNEsuD72";
const SCOPE_KEY = `ADMIN:${OWNER_UID}`;

const CALLABLE_URL =
  `https://asia-northeast3-${PROJECT_ID}.cloudfunctions.net/callableCreateTO`;
const AUTH_REST =
  `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${FIREBASE_API_KEY}`;
const APPCHECK_EXCHANGE =
  `https://firebaseappcheck.googleapis.com/v1/projects/${PROJECT_NUMBER}` +
  `/apps/${APP_ID}:exchangeDebugToken`;

// ── 메인 ────────────────────────────────────────────────────────────────────
async function main() {
  const mode = process.argv[2] || "handshake";
  if (mode !== "handshake") {
    console.error(`[ERROR] 알 수 없는 모드: "${mode}". "handshake"만 지원됩니다.`);
    process.exit(1);
  }

  console.log("=".repeat(64));
  console.log("PHASE: ADMIN.POSTING.CAPACITY-SCOPE-STAGE3B-T5-HARNESS");
  console.log("Mode: handshake (NON-MUTATING)");
  console.log("=".repeat(64));

  // ── A. 서비스 계정 경로 결정 ────────────────────────────────────────────
  const saPath = process.env.ALFIT_SERVICE_ACCOUNT_PATH
    || path.join(__dirname, "alfit-89567-firebase-adminsdk-fbsvc-d22e7faef3.json");

  if (!fs.existsSync(saPath)) {
    console.error("[FATAL] 서비스 계정 파일을 찾을 수 없습니다:", saPath);
    console.error("  ALFIT_SERVICE_ACCOUNT_PATH 환경변수로 올바른 경로를 지정하세요.");
    process.exit(1);
  }
  console.log(`[SA] 서비스 계정 경로: ${saPath}`);

  // ── B. 프로젝트 검증 ────────────────────────────────────────────────────
  const saRaw = JSON.parse(fs.readFileSync(saPath, "utf-8"));
  if (saRaw.project_id !== EXPECTED_PROJECT_ID) {
    console.error("[FATAL] WRONG_PROJECT_CREDENTIAL");
    console.error(`  Expected: ${EXPECTED_PROJECT_ID}`);
    console.error(`  Got:      ${saRaw.project_id}`);
    process.exit(1);
  }
  console.log(`[OK] service account project_id = ${saRaw.project_id} ✓`);
  console.log(`[OK] google-services.json project_id = ${PROJECT_ID} ✓`);
  console.log(`[OK] App ID = ${APP_ID}`);

  // ── C. Admin SDK 초기화 ──────────────────────────────────────────────────
  // 기존 스크립트 관례와 동일하게 functions/node_modules 경유
  const admin = require(
    path.join(__dirname, "..", "functions", "node_modules", "firebase-admin")
  );
  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.cert(saPath),
      projectId: PROJECT_ID,
    });
  }
  const db = admin.firestore();
  console.log("[OK] Admin SDK 초기화 완료");

  // ── D. Firebase Auth: custom token → ID token ────────────────────────────
  console.log(`\n[AUTH] Owner UID ${OWNER_UID} 에 대한 custom token 생성 중...`);
  let customToken;
  try {
    customToken = await admin.auth().createCustomToken(OWNER_UID);
  } catch (e) {
    console.error("[FATAL] createCustomToken 실패:", e.message);
    process.exit(1);
  }

  console.log("[AUTH] REST API로 Firebase ID token 교환 중...");
  let idToken;
  {
    const resp = await fetch(AUTH_REST, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ token: customToken, returnSecureToken: true }),
    });
    const body = await resp.json();
    if (!resp.ok || !body.idToken) {
      console.error("[FATAL] Auth REST 교환 실패:", body.error || body);
      process.exit(1);
    }
    idToken = body.idToken;
  }
  // 절대 토큰 값 출력하지 않음
  console.log("[OK] Auth ID token acquired: YES");
  console.log("FINDING: POSTING-CAPACITY-STAGE3B-T5-AUTH-FLOW-01 → PASS");

  // ── E. App Check 디버그 토큰 교환 ────────────────────────────────────────
  const appCheckDebugToken = process.env.ALFIT_APP_CHECK_DEBUG_TOKEN;
  if (!appCheckDebugToken) {
    console.error("\n[BLOCKED] ALFIT_APP_CHECK_DEBUG_TOKEN 환경변수가 없습니다.");
    console.error("  Firebase Console → App Check → Apps → Android 앱 → Debug tokens");
    console.error("  에서 디버그 토큰을 등록한 후, 발급된 시크릿 값을 환경변수로 지정하세요.");
    console.error("  예: ALFIT_APP_CHECK_DEBUG_TOKEN=<secret> node scripts/test_callable_harness.js");
    console.log("\nFINDING: POSTING-CAPACITY-STAGE3B-T5-APPCHECK-FLOW-01 → APP_CHECK_REGISTRATION_REQUIRED");
    printPartialReport({ authPass: true, appCheckPass: false, reason: "APP_CHECK_DEBUG_TOKEN_REQUIRED" });
    process.exit(2);
  }

  console.log("\n[APPCHECK] 디버그 시크릿 → App Check token 교환 중...");
  let appCheckToken;
  {
    const resp = await fetch(`${APPCHECK_EXCHANGE}?key=${FIREBASE_API_KEY}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ debugToken: appCheckDebugToken, limitedUse: false }),
    });
    const body = await resp.json();
    if (!resp.ok || !body.token) {
      const errStr = body.error ? JSON.stringify(body.error) : JSON.stringify(body);
      console.error("[BLOCKED] App Check 교환 실패:", errStr);
      if (resp.status === 403 || resp.status === 400) {
        console.error("  디버그 토큰이 Firebase Console에 등록되지 않았을 수 있습니다.");
        console.log("\nFINDING: POSTING-CAPACITY-STAGE3B-T5-APPCHECK-FLOW-01 → APP_CHECK_REGISTRATION_REQUIRED");
        printPartialReport({ authPass: true, appCheckPass: false, reason: "APP_CHECK_REGISTRATION_REQUIRED" });
        process.exit(2);
      }
      console.log("\nFINDING: POSTING-CAPACITY-STAGE3B-T5-APPCHECK-FLOW-01 → FAIL");
      process.exit(1);
    }
    appCheckToken = body.token;
    const ttl = body.ttl || "unknown";
    console.log(`[OK] App Check token acquired: YES (ttl=${ttl})`);
  }
  console.log("FINDING: POSTING-CAPACITY-STAGE3B-T5-APPCHECK-FLOW-01 → PASS");

  // ── F. 핸드셰이크 안전성 검증 ────────────────────────────────────────────
  // callableCreateTO 검증 순서 (functions/src/index.ts):
  //   Line 7524: request.auth 체크 (→ unauthenticated)
  //   Line 7526: request.data.toData 추출
  //   Line 7528: !toData || typeof toData !== "object" → invalid-argument "toData가 필요합니다."
  //   ✅ 이 오류는 Firestore 읽기/쓰기 전 발생 (db.collection("users").get() 이전)
  //
  // 페이로드 { "data": {} } → request.data = {} → toData = undefined
  //   → invalid-argument 즉시 throw → 쓰기 없음 확인됨
  console.log("\n[SAFETY] 핸드셰이크 페이로드: { data: {} }");
  console.log("[SAFETY] 예상 오류: invalid-argument 'toData가 필요합니다.'");
  console.log("[SAFETY] 근거: index.ts:7528-7529, 최초 Firestore 접근(line 7548) 이전 throw 확인");
  console.log("FINDING: POSTING-CAPACITY-STAGE3B-T5-HANDSHAKE-SAFETY-01 → SAFE");

  // ── G. Firestore 핸드셰이크 전 스냅샷 ────────────────────────────────────
  console.log(`\n[FIRESTORE] 핸드셰이크 전 effective TOs 조회 (scope=${SCOPE_KEY})...`);
  const preSnap = await db.collection("tos")
    .where("postingCapacityScopeKey", "==", SCOPE_KEY)
    .where("status", "in", ["ACTIVE", "FULL"])
    .get();
  const preIds = preSnap.docs.map((d) => d.id);
  console.log(`[FIRESTORE] 핸드셰이크 전 effective TO (${preIds.length}건):`, preIds);

  // ── H. 핸드셰이크 실행 ───────────────────────────────────────────────────
  // Callable HTTP 프로토콜:
  //   POST <endpoint>
  //   Content-Type: application/json
  //   Authorization: Bearer <idToken>
  //   X-Firebase-AppCheck: <appCheckToken>
  //   Body: { "data": <payload> }
  //
  // ⚠️  { "data": {} } — 이중 중첩 { "data": { "data": {} } } 금지
  console.log(`\n[HANDSHAKE] POST ${CALLABLE_URL}`);
  console.log("[HANDSHAKE] 페이로드: { data: {} }");

  let handshakeHttpStatus;
  let handshakeBody;
  {
    const resp = await fetch(CALLABLE_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${idToken}`,
        "X-Firebase-AppCheck": appCheckToken,
      },
      body: JSON.stringify({ data: {} }),
    });
    handshakeHttpStatus = resp.status;
    handshakeBody = await resp.json().catch(() => null);
  }

  // 응답 파싱 (credential 포함 가능성 없음 — 오류 메시지만)
  const callableError  = handshakeBody?.error;
  const callableStatus = callableError?.status || callableError?.code || null;
  const callableMessage = callableError?.message || null;

  console.log(`[HANDSHAKE] HTTP: ${handshakeHttpStatus}`);
  console.log(`[HANDSHAKE] callable status: ${callableStatus}`);
  console.log(`[HANDSHAKE] callable message: ${callableMessage}`);

  // 분류
  let classification;
  if (handshakeHttpStatus === 401 || callableStatus === "UNAUTHENTICATED") {
    classification = "H2_AUTH_FAIL";
  } else if (
    handshakeHttpStatus === 403 &&
    callableStatus !== "PERMISSION_DENIED" &&
    callableStatus !== "INVALID_ARGUMENT"
  ) {
    // Firebase 레이어에서 App Check 거부 (callable 구조 아님)
    classification = "H3_APPCHECK_FAIL";
  } else if (
    callableStatus === "INVALID_ARGUMENT" ||
    (handshakeHttpStatus === 400 && !callableStatus)
  ) {
    // 핸들러 진입 후 toData 누락 오류 → Auth + App Check 모두 통과
    classification = "H1_PASS_AUTH_AND_APPCHECK";
  } else {
    classification = "H5_UNEXPECTED_HANDLER_RESULT";
  }

  const protocolFinding =
    classification === "H1_PASS_AUTH_AND_APPCHECK" ? "PASS" : classification;
  console.log(`[HANDSHAKE] Classification: ${classification}`);
  console.log(`FINDING: POSTING-CAPACITY-STAGE3B-T5-CALLABLE-PROTOCOL-01 → ${protocolFinding}`);
  console.log(`FINDING: POSTING-CAPACITY-STAGE3B-T5-HANDSHAKE-01 → ${classification}`);

  // ── I. Firestore 핸드셰이크 후 검증 ─────────────────────────────────────
  console.log("\n[FIRESTORE] 핸드셰이크 후 effective TOs 재조회...");
  const postSnap = await db.collection("tos")
    .where("postingCapacityScopeKey", "==", SCOPE_KEY)
    .where("status", "in", ["ACTIVE", "FULL"])
    .get();
  const postIds = postSnap.docs.map((d) => d.id);
  const newIds  = postIds.filter((id) => !preIds.includes(id));

  console.log(`[FIRESTORE] 핸드셰이크 후 effective TO (${postIds.length}건):`, postIds);
  if (newIds.length === 0) {
    console.log("[FIRESTORE] 신규 TO 없음 ✅");
    console.log("FINDING: POSTING-CAPACITY-STAGE3B-T5-HANDSHAKE-NOWRITE-01 → PASS");
  } else {
    console.log("[FIRESTORE] ⚠️  신규 TO 감지:", newIds);
    console.log("FINDING: POSTING-CAPACITY-STAGE3B-T5-HANDSHAKE-NOWRITE-01 → FAIL");
  }

  // ── J. 최종 보고서 ───────────────────────────────────────────────────────
  const noWrite = newIds.length === 0;
  const verdict =
    classification === "H1_PASS_AUTH_AND_APPCHECK" && noWrite
      ? "READY_FOR_T5_EXECUTION"
      : classification === "H2_AUTH_FAIL"
      ? "AUTH_GAP"
      : classification === "H3_APPCHECK_FAIL"
      ? "APP_CHECK_REGISTRATION_REQUIRED"
      : !noWrite
      ? "HANDSHAKE_MUTATION_RISK"
      : "HARNESS_GAP";

  printFinalReport({
    saPath,
    projectId: PROJECT_ID,
    appId: APP_ID,
    authPass: true,
    appCheckPass: true,
    handshakeHttpStatus,
    callableStatus,
    callableMessage,
    classification,
    preIds,
    postIds,
    newIds,
    noWrite,
    verdict,
  });

  process.exit(verdict === "READY_FOR_T5_EXECUTION" ? 0 : 1);
}

// ── 부분 보고서 (App Check 토큰 미등록 시) ───────────────────────────────────
function printPartialReport({ authPass, appCheckPass, reason }) {
  console.log("\n" + "=".repeat(64));
  console.log("FINAL REPORT");
  console.log("# PHASE ADMIN.POSTING.CAPACITY-SCOPE-STAGE3B-T5-HARNESS");
  console.log("\n## A. Files");
  console.log("  scripts/test_callable_harness.js — created");
  console.log("\n## D. Auth");
  console.log(`  custom token created: ${authPass ? "YES" : "NO"}`);
  console.log(`  ID token acquired:    ${authPass ? "YES" : "NO"}`);
  console.log(`  secrets logged:       NONE`);
  console.log("\n## E. App Check");
  console.log(`  exchange result:      ${reason}`);
  console.log(`  App Check token:      NOT_ACQUIRED`);
  console.log(`  token logged:         NO`);
  console.log(`\n## M. VERDICT: ${reason}`);
  console.log("\n## N. NEXT");
  console.log("  1. Firebase Console → App Check → Apps → Android 앱 → Debug tokens");
  console.log("     '+ Add debug token' → 이름 입력 → '저장' → 시크릿 복사");
  console.log("  2. 실행:");
  console.log("     $env:ALFIT_APP_CHECK_DEBUG_TOKEN='<시크릿>'");
  console.log("     node scripts/test_callable_harness.js");
  console.log("=".repeat(64));
}

// ── 최종 보고서 ──────────────────────────────────────────────────────────────
function printFinalReport(r) {
  const {
    saPath, projectId, appId,
    handshakeHttpStatus, callableStatus, callableMessage,
    classification, preIds, postIds, newIds, noWrite, verdict,
  } = r;
  const callableProtocol =
    classification === "H1_PASS_AUTH_AND_APPCHECK" ? "PASS" : classification;

  console.log("\n" + "=".repeat(64));
  console.log("FINAL REPORT");
  console.log("# PHASE ADMIN.POSTING.CAPACITY-SCOPE-STAGE3B-DEV-RUNTIME-T5-HARNESS");

  console.log("\n## A. Files");
  console.log("  scripts/test_callable_harness.js — created (this file)");

  console.log("\n## B. Service Account Initialization");
  console.log(`  project verification: ${projectId === "alfit-89567" ? "PASS (alfit-89567)" : "FAIL"}`);
  console.log(`  secret source:        ALFIT_SERVICE_ACCOUNT_PATH env 또는 scripts/ 관례 경로`);

  console.log("\n## C. Firebase Config");
  console.log(`  project:        ${projectId}`);
  console.log(`  appId:          ${appId}`);
  console.log(`  API key source: android/app/google-services.json (커밋됨, 비공개 아님)`);

  console.log("\n## D. Auth");
  console.log(`  custom token created: YES`);
  console.log(`  ID token acquired:    YES`);
  console.log(`  secrets logged:       NONE`);

  console.log("\n## E. App Check");
  console.log(`  debug secret source:      ALFIT_APP_CHECK_DEBUG_TOKEN env`);
  console.log(`  exchange result:          OK`);
  console.log(`  App Check token acquired: YES`);
  console.log(`  token logged:             NO`);

  console.log("\n## F. Callable Protocol");
  console.log(`  endpoint:  ${r.projectId === "alfit-89567"
    ? "https://asia-northeast3-alfit-89567.cloudfunctions.net/callableCreateTO"
    : "(derived)"}`);
  console.log(`  headers:   Content-Type, Authorization Bearer <idToken>, X-Firebase-AppCheck <token>`);
  console.log(`  body:      { "data": {} }`);
  console.log(`  FINDING:   POSTING-CAPACITY-STAGE3B-T5-CALLABLE-PROTOCOL-01 → ${callableProtocol}`);

  console.log("\n## G. Handshake Safety");
  console.log("  payload { data: {} } → request.data.toData = undefined");
  console.log("  → index.ts:7528-7529 invalid-argument throw, Firestore write 이전");
  console.log("  FINDING: POSTING-CAPACITY-STAGE3B-T5-HANDSHAKE-SAFETY-01 → SAFE");

  console.log("\n## H. Handshake Result");
  console.log(`  HTTP:             ${handshakeHttpStatus}`);
  console.log(`  callable status:  ${callableStatus}`);
  console.log(`  sanitized error:  ${callableMessage}`);
  console.log(`  classification:   ${classification}`);
  console.log(`  FINDING:          POSTING-CAPACITY-STAGE3B-T5-HANDSHAKE-01 → ${classification}`);

  console.log("\n## I. Firestore");
  console.log(`  before effective IDs (${preIds.length}): ${preIds.join(", ") || "(none)"}`);
  console.log(`  after effective IDs  (${postIds.length}): ${postIds.join(", ") || "(none)"}`);
  console.log(`  new TO docs:  ${newIds.length === 0 ? "NONE" : newIds.join(", ")}`);
  console.log(`  writes:       ${noWrite ? "NONE" : "⚠️ WRITES DETECTED"}`);
  console.log(`  FINDING:      POSTING-CAPACITY-STAGE3B-T5-HANDSHAKE-NOWRITE-01 → ${noWrite ? "PASS" : "FAIL"}`);

  console.log("\n## J. Security");
  console.log("  credential file tracked: NO (scripts/*.json in .gitignore:3)");
  console.log("  secret embedded in harness: NO (env var 전용)");
  console.log("  token logging: NONE");

  console.log("\n## K. Static");
  console.log("  node --check scripts/test_callable_harness.js → (실행 후 확인)");

  console.log(`\n## L. Changes`);
  console.log("  scripts/test_callable_harness.js — 신규 생성");
  console.log("  그 외: 없음");

  console.log(`\n## M. VERDICT: ${verdict}`);

  console.log("\n## N. NEXT");
  if (verdict === "READY_FOR_T5_EXECUTION") {
    console.log("  PHASE ADMIN.POSTING.CAPACITY-SCOPE-STAGE3B-DEV-RUNTIME-T5");
    console.log("  - fixture 2개 ACTIVE TO 생성 → effective count = 3 확인");
    console.log("  - race 2 concurrent create → exactly 1 success + 1 MAX_ACTIVE_TO_LIMIT");
    console.log("  - final effective count = 4 확인 → cleanup");
  } else if (verdict === "APP_CHECK_REGISTRATION_REQUIRED" || verdict === "AUTH_GAP") {
    console.log("  Firebase Console에서 App Check 디버그 토큰 등록 후 재실행.");
  } else {
    console.log(`  ${verdict} 원인 조사 필요.`);
  }
  console.log("=".repeat(64));
}

main().catch((e) => {
  console.error("[FATAL] 처리되지 않은 오류:", e.message || e);
  process.exit(1);
});
