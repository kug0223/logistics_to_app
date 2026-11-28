/**
 * [ALFIT-AUTH-KAKAO-ONBOARDING.1] 새 가입(카카오 1차) 순수 판정 모듈.
 *
 *   이 파일은 Firestore·Auth·네트워크를 모른다. `crypto` 만 쓴다.
 *   판정이 writer 안에 인라인으로 있으면 조건 하나를 바꿔도 시험이 깨지지
 *   않는다 — 그래서 상태 전이·제한·allowlist·KG 응답 해석·신원 키 형식을
 *   전부 여기서 정하고, writer(auth_kakao.ts / index.ts)는 이 답을 따른다.
 *
 *   clean cutover(판정278): 옛 SHA ciHash · 외국인 등록번호 HMAC ·
 *   deleted_accounts · 옛 pending 은 이 모듈의 어떤 판정에도 들어오지 않는다.
 */
import * as crypto from "crypto";

// ── 역할·상수 ───────────────────────────────────────────────────────────
export const SIGNUP_ROLES = ["USER", "BUSINESS_ADMIN"] as const;
export type SignupRole = typeof SIGNUP_ROLES[number];

/** @param {unknown} r 값 @return {boolean} 가입 가능한 역할인가 */
export function isSignupRole(r: unknown): r is SignupRole {
  return r === "USER" || r === "BUSINESS_ADMIN";
}

/** 서버 세대 표시 — 이 값이 있는 users 문서만 새 흐름 계정이다(클라 쓰기 0). */
export const SIGNUP_SOURCE_KAKAO_V1 = "kakao_v1";
export const PROVIDER_KAKAO = "kakao";

export const MIN = 60 * 1000;
export const HOUR = 60 * MIN;
export const DAY = 24 * HOUR;
/** 정확한 30일 — 기존 PreData 계산(Date.now() + 30*24*60*60*1000)과 같은 식. */
export const REREGISTER_COOLDOWN_MS = 30 * DAY;
export const SESSION_TTL_MS = 24 * HOUR;
export const SESSION_SECRET_TTL_MS = 2 * HOUR;
export const CERT_TTL_MS = 20 * MIN;
export const PASS_FRESH_MS = 30 * MIN;
export const CERT_MAX_ATTEMPTS = 5;
export const DELETION_PROOF_TTL_MS = 10 * MIN;
/** PortOne certified_at 과 서버 발급 시각 사이 허용 오차(기기·서버 시계). */
export const CERT_CLOCK_SKEW_MS = 2 * MIN;

// ── 문서 id ─────────────────────────────────────────────────────────────
/**
 * 문서 id 조각으로 써도 되는 값인가 — `/`·`..`·빈 값·과도한 길이 거부.
 * @param {unknown} v 값
 * @return {boolean} 안전하면 true
 */
export function isSafeIdPart(v: unknown): v is string {
  return typeof v === "string" && /^[A-Za-z0-9_-]{1,128}$/.test(v);
}

/** @return {string} `{provider}_{appNs}_{subject}` — authSubjects · signupSessions id */
export function providerSubjectKey(
  provider: string, appNs: string, subject: string): string {
  return `${provider}_${appNs}_${subject}`;
}
/** @return {string} `{provider}_{appNs}_{subject}_{role}` — authLinks id */
export function authLinkId(
  provider: string, appNs: string, subject: string, role: SignupRole): string {
  return `${providerSubjectKey(provider, appNs, subject)}_${role}`;
}
/** @return {string} `{uid}_{provider}` — authLinkOwners id */
export function authLinkOwnerId(uid: string, provider: string): string {
  return `${uid}_${provider}`;
}
/** 탈퇴 재확인 KG 의 세션 키(passCertifications 귀속용). */
export function deletionSessionKey(uid: string): string {
  return `deletion_${uid}`;
}

/** @param {string} s 원문 @return {string} sha256 hex */
export function sha256Hex(s: string): string {
  return crypto.createHash("sha256").update(s, "utf8").digest("hex");
}

// ── 신원 키(versioned · domain-separated HMAC) ──────────────────────────
export const CI_KEY_VERSION = 1;
export const CI_KEY_PREFIX_V1 = "ci1_";
export const CI_KEY_DOMAIN_V1 = "alfit:identity:ci:v1:";

/**
 * `identities/{ciKey}` 의 id.
 *
 *   용도 접두(`alfit:identity:ci:v1:`)로 외국인 등록번호 HMAC·세무 HMAC 과
 *   같은 비밀이 쓰여도 값이 섞이지 않게 한다. 키 버전은 id 접두와 문서
 *   필드 둘 다에 둔다. 키 회전(v2)은 이 판 범위 밖이며, version 필드가
 *   미래 이관을 자동으로 해결하지 않는다(판정278 §2).
 *
 * @param {string} hmacKey 서버 Secret(CI_HMAC_KEY_V1) 값
 * @param {string} ci KG 가 준 CI 원문(메모리에서만)
 * @return {string} `ci1_` + hex
 */
export function computeCiKeyV1(hmacKey: string, ci: string): string {
  if (typeof hmacKey !== "string" || hmacKey.length < 16) {
    throw new Error("CI_KEY_UNAVAILABLE");
  }
  if (typeof ci !== "string" || ci.length === 0) {
    throw new Error("KG_CI_MISSING");
  }
  return CI_KEY_PREFIX_V1 + crypto.createHmac("sha256", hmacKey)
    .update(CI_KEY_DOMAIN_V1 + ci, "utf8").digest("hex");
}

/** @param {unknown} k 값 @return {boolean} v1 신원 키 형식인가 */
export function isCiKeyV1(k: unknown): k is string {
  return typeof k === "string" && /^ci1_[0-9a-f]{64}$/.test(k);
}

// ── 시각 ───────────────────────────────────────────────────────────────
/**
 * 저장된 시각을 epoch ms 로. 읽을 수 없으면 null — 모르는 값을 0 으로 만들지 않는다.
 * @param {unknown} v Timestamp 류 · Date · number
 * @return {number | null} ms
 */
export function toMs(v: unknown): number | null {
  if (v && typeof (v as {toMillis?: unknown}).toMillis === "function") {
    const n = (v as {toMillis: () => number}).toMillis();
    return Number.isFinite(n) ? n : null;
  }
  if (v instanceof Date) return v.getTime();
  if (typeof v === "number" && Number.isFinite(v)) return v;
  return null;
}

// ── KG(PortOne V1) 응답 해석 ─────────────────────────────────────────────
export type KgCert = {
  ci: string;
  name: string;
  /** YYYYMMDD */
  birthDate: string;
  phone: string;
  /** '남성' | '여성' | null(미제공 — 폴백 없음) */
  gender: "남성" | "여성" | null;
  merchantUid: string | null;
  certifiedAtMs: number | null;
  pgProvider: string | null;
};
export type KgParse =
  | {ok: true; cert: KgCert}
  | {ok: false; reason: "KG_NOT_CERTIFIED" | "KG_CI_MISSING" | "KG_DATA_INCOMPLETE"};

/**
 * PortOne `/certifications/{imp_uid}` 응답을 **엄격하게** 해석한다.
 *
 *   · `code === 0` 이고 `certified === true`(boolean 엄격 — 문자열 "true" 거부).
 *   · `unique_key`(CI) 없음 = 실패. DEV 전화 대체 CI(`DEV-CI-{phone}`) 는 만들지 않는다.
 *   · 성별은 'male'/'female' 만 인정, 그 밖은 null(여성 폴백 금지 · K4).
 *
 * @param {unknown} raw 응답 JSON
 * @return {KgParse} 해석 결과
 */
export function parsePortOneCertification(raw: unknown): KgParse {
  const r = (raw ?? {}) as {code?: unknown; response?: Record<string, unknown> | null};
  const res = r.response;
  if (r.code !== 0 || !res || typeof res !== "object" || res["certified"] !== true) {
    return {ok: false, reason: "KG_NOT_CERTIFIED"};
  }
  const ci = typeof res["unique_key"] === "string" ? (res["unique_key"] as string).trim() : "";
  if (ci.length === 0) return {ok: false, reason: "KG_CI_MISSING"};
  const name = typeof res["name"] === "string" ? (res["name"] as string).trim() : "";
  const birthDate = typeof res["birthday"] === "string" ?
    (res["birthday"] as string).replace(/-/g, "").trim() : "";
  const phone = typeof res["phone"] === "string" ?
    (res["phone"] as string).replace(/[-\s]/g, "") : "";
  if (!name || !/^\d{8}$/.test(birthDate) || !/^\d{9,12}$/.test(phone)) {
    return {ok: false, reason: "KG_DATA_INCOMPLETE"};
  }
  const g = res["gender"];
  const gender = g === "male" ? "남성" : (g === "female" ? "여성" : null);
  const mu = typeof res["merchant_uid"] === "string" && res["merchant_uid"] ?
    res["merchant_uid"] as string : null;
  const ca = res["certified_at"];
  const certifiedAtMs = typeof ca === "number" && Number.isFinite(ca) && ca > 0 ?
    Math.round(ca * 1000) : null;
  const pg = typeof res["pg_provider"] === "string" ? res["pg_provider"] as string : null;
  return {ok: true, cert: {ci, name, birthDate, phone, gender,
    merchantUid: mu, certifiedAtMs, pgProvider: pg}};
}

/**
 * KG 결과가 **이 서버 요청**의 것인가.
 *
 *   merchant_uid 는 서버가 발급한 requestId 와 같아야 하고, certified_at 은
 *   발급 시각(오차 허용) 이후·지금 이전이어야 한다. 두 값이 응답에 없으면
 *   결합을 확인할 수 없으므로 **통과로 쓰지 않는다**(실 MID 필드 확인은 X1 PENDING).
 *   pg_provider 는 설정값이 있을 때만 대조하고, 없으면 'unchecked' 로 기록한다.
 *
 * @param {KgCert} c 해석된 결과
 * @param {object} want 기대값
 * @return {{ok: boolean, pgCheck: string}} 판정
 */
export function checkKgBinding(c: KgCert, want: {
  requestId: string; issuedAtMs: number; nowMs: number; pgProvider?: string | null;
}): {ok: boolean; pgCheck: "matched" | "unchecked" | "mismatch"} {
  let pgCheck: "matched" | "unchecked" | "mismatch" = "unchecked";
  if (want.pgProvider) pgCheck = c.pgProvider === want.pgProvider ? "matched" : "mismatch";
  const ok = c.merchantUid !== null && c.merchantUid === want.requestId &&
    c.certifiedAtMs !== null &&
    c.certifiedAtMs >= want.issuedAtMs - CERT_CLOCK_SKEW_MS &&
    c.certifiedAtMs <= want.nowMs + CERT_CLOCK_SKEW_MS &&
    pgCheck !== "mismatch";
  return {ok, pgCheck};
}

/**
 * 만 나이(KST). verifyPassAuth 의 기존 계산(CF:12235-12250)과 같은 식.
 * @param {string} yyyymmdd 생년월일
 * @param {number} nowMs 서버 시각
 * @return {number} 만 나이(형식 오류면 -1)
 */
export function ageKst(yyyymmdd: string, nowMs: number): number {
  if (!/^\d{8}$/.test(yyyymmdd)) return -1;
  const today = new Date(nowMs + 9 * HOUR);
  const by = parseInt(yyyymmdd.substring(0, 4), 10);
  const bm = parseInt(yyyymmdd.substring(4, 6), 10);
  const bd = parseInt(yyyymmdd.substring(6, 8), 10);
  return today.getUTCFullYear() - by -
    (today.getUTCMonth() + 1 < bm ||
      (today.getUTCMonth() + 1 === bm && today.getUTCDate() < bd) ? 1 : 0);
}

/** @param {string} p 숫자 전화번호 @return {string} 010-****-1234 형식 */
export function maskPhone(p: string): string {
  const d = (p ?? "").replace(/\D/g, "");
  if (d.length < 7) return "***";
  return `${d.slice(0, 3)}-****-${d.slice(-4)}`;
}

// ── 재가입 제한(identities.restriction) ──────────────────────────────────
export type Restriction = {
  state: "none" | "cooldown" | "blacklisted";
  /** cooldown 해제 시각(ms) */
  canReregisterAtMs?: number | null;
  /** 블랙 계정이 탈퇴로 사라짐 → 영구. 해제 writer 가 없다. */
  permanent?: boolean;
  /** 아직 살아 있는(해제 가능한) 블랙 계정 uid */
  blacklistedUids?: string[];
  sourceUid?: string | null;
  updatedAtMs?: number | null;
};

/**
 * 저장된 restriction 을 정규형으로. 모르는 모양은 **블랙으로** 읽는다
 * (fail-closed: 제한 기록이 깨졌다고 제한을 잃지 않는다).
 * @param {unknown} raw 저장값
 * @return {Restriction} 정규형
 */
export function normalizeRestriction(raw: unknown): Restriction {
  if (raw === undefined || raw === null) return {state: "none"};
  if (typeof raw !== "object") return {state: "blacklisted", permanent: true};
  const r = raw as Record<string, unknown>;
  const uids = Array.isArray(r["blacklistedUids"]) ?
    (r["blacklistedUids"] as unknown[]).filter((u): u is string => typeof u === "string") : [];
  const permanent = r["permanent"] === true;
  const st = r["state"];
  if (st !== "none" && st !== "cooldown" && st !== "blacklisted") {
    return {state: "blacklisted", permanent: true, blacklistedUids: uids};
  }
  const until = toMs(r["canReregisterAt"] ?? r["canReregisterAtMs"]);
  if (st === "cooldown" && until === null) {
    // 해제 시각을 모르는 cooldown — 영구로 접지 않고 판정 불가로 막는다.
    return {state: "blacklisted", permanent: true, blacklistedUids: uids};
  }
  return {
    state: (permanent || uids.length > 0) ? "blacklisted" : st,
    canReregisterAtMs: until,
    permanent,
    blacklistedUids: uids,
    sourceUid: typeof r["sourceUid"] === "string" ? r["sourceUid"] as string : null,
  };
}

export type RestrictionVerdict =
  | {kind: "OK"}
  | {kind: "BLACKLISTED"}
  | {kind: "COOLDOWN"; canReregisterAtMs: number};

/**
 * 새 가입·역할 추가가 이 사람에게 허용되는가. 정확한 경계: `now >= canReregisterAt` 이면 허용.
 * @param {Restriction} r 정규형
 * @param {number} nowMs 서버 시각
 * @return {RestrictionVerdict} 판정
 */
export function restrictionVerdict(r: Restriction, nowMs: number): RestrictionVerdict {
  if (r.state === "blacklisted" || r.permanent ||
      (r.blacklistedUids && r.blacklistedUids.length > 0)) {
    return {kind: "BLACKLISTED"};
  }
  if (r.state === "cooldown" && typeof r.canReregisterAtMs === "number" &&
      nowMs < r.canReregisterAtMs) {
    return {kind: "COOLDOWN", canReregisterAtMs: r.canReregisterAtMs};
  }
  return {kind: "OK"};
}

/**
 * 블랙 등록이 identity 제한에 반영된 모양. 이미 있는 영구·다른 계정 블랙은 보존.
 * @param {Restriction} prev 정규형
 * @param {string} uid 블랙된 계정
 * @param {number} nowMs 시각
 * @return {Restriction} 새 값
 */
export function restrictionAfterBlacklist(
  prev: Restriction, uid: string, nowMs: number): Restriction {
  const uids = Array.from(new Set([...(prev.blacklistedUids ?? []), uid]));
  return {state: "blacklisted", permanent: prev.permanent === true,
    canReregisterAtMs: prev.canReregisterAtMs ?? null,
    blacklistedUids: uids, sourceUid: uid, updatedAtMs: nowMs};
}

/**
 * 블랙 해제. 그 uid 만 뺀다 — 영구(탈퇴한 블랙 계정)나 다른 계정의 블랙은 남는다.
 * 남은 cooldown 이 미래면 cooldown 으로, 아니면 none.
 * @param {Restriction} prev 정규형
 * @param {string} uid 해제 대상
 * @param {number} nowMs 시각
 * @return {Restriction} 새 값
 */
export function restrictionAfterUnblacklist(
  prev: Restriction, uid: string, nowMs: number): Restriction {
  const uids = (prev.blacklistedUids ?? []).filter((u) => u !== uid);
  if (prev.permanent || uids.length > 0) {
    return {...prev, state: "blacklisted", blacklistedUids: uids, updatedAtMs: nowMs};
  }
  const until = prev.canReregisterAtMs ?? null;
  if (until !== null && until > nowMs) {
    return {state: "cooldown", canReregisterAtMs: until, permanent: false,
      blacklistedUids: [], sourceUid: prev.sourceUid ?? null, updatedAtMs: nowMs};
  }
  return {state: "none", canReregisterAtMs: until, permanent: false,
    blacklistedUids: [], sourceUid: prev.sourceUid ?? null, updatedAtMs: nowMs};
}

/**
 * 한 역할 계정의 탈퇴가 끝날 때의 제한. **블랙은 절대 내려가지 않는다**
 * (영구블랙이 일반탈퇴에 가려지는 문제 — B277-04).
 *
 *   · 탈퇴 계정이 블랙이었거나(문서/동결 시점 기록/identity uid 목록 중 하나라도)
 *     → state blacklisted · permanent true(해제 writer 가 사라졌으므로).
 *   · 아니면 cooldown, 해제 시각 = max(기존 미래 해제 시각, 기준시각 + 30일).
 *
 * @param {Restriction} prev 정규형
 * @param {object} e 사건
 * @return {Restriction} 새 값
 */
export function restrictionAfterDeletion(prev: Restriction, e: {
  uid: string; wasBlacklisted: boolean; baseMs: number; nowMs: number;
}): Restriction {
  const uidWasListed = (prev.blacklistedUids ?? []).includes(e.uid);
  const others = (prev.blacklistedUids ?? []).filter((u) => u !== e.uid);
  const until = Math.max(prev.canReregisterAtMs ?? 0, e.baseMs + REREGISTER_COOLDOWN_MS);
  if (e.wasBlacklisted || uidWasListed || prev.permanent) {
    return {state: "blacklisted", permanent: true, canReregisterAtMs: until,
      blacklistedUids: others, sourceUid: e.uid, updatedAtMs: e.nowMs};
  }
  if (others.length > 0) {
    return {state: "blacklisted", permanent: false, canReregisterAtMs: until,
      blacklistedUids: others, sourceUid: e.uid, updatedAtMs: e.nowMs};
  }
  return {state: "cooldown", permanent: false, canReregisterAtMs: until,
    blacklistedUids: [], sourceUid: e.uid, updatedAtMs: e.nowMs};
}

/**
 * 저장용 모양(ms → 호출자가 Timestamp 로 바꾼다).
 * @param {Restriction} r 정규형
 * @return {object} 저장 필드(canReregisterAtMs 는 숫자)
 */
export function restrictionForStore(r: Restriction): Record<string, unknown> {
  return {
    state: r.state,
    permanent: r.permanent === true,
    blacklistedUids: r.blacklistedUids ?? [],
    canReregisterAtMs: r.canReregisterAtMs ?? null,
    sourceUid: r.sourceUid ?? null,
    updatedAtMs: r.updatedAtMs ?? null,
  };
}

// ── 계정 상태 판정(K7 — 로그인·자동 복원 공통) ───────────────────────────
export type AccountVerdict =
  | {kind: "OK"}
  | {kind: "DELETION_RECOVERY"}
  | {kind: "BLOCKED_BLACKLIST"; reason: string}
  | {kind: "REJECTED"}
  | {kind: "RESTRICTED"; untilMs: number; source: string | null}
  | {kind: "INCOMPLETE_LEGACY"; status: string};

/**
 * 앱 아이디 로그인(AuthService.signIn AS:113-158)과 1:1 인 서버 판정.
 *   deleting/tombstone 은 막지 않고 삭제 재개로 보낸다(B277-06).
 *
 * @param {Record<string, unknown> | undefined} u users 문서(없으면 undefined)
 * @param {boolean} tombstone account_deletion_tombstones/{uid} 존재
 * @param {number} nowMs 서버 시각
 * @return {AccountVerdict} 판정
 */
export function accountStateVerdict(
  u: Record<string, unknown> | undefined, tombstone: boolean, nowMs: number): AccountVerdict {
  if (tombstone || u?.["accountStatus"] === "deleting") return {kind: "DELETION_RECOVERY"};
  if (!u) return {kind: "INCOMPLETE_LEGACY", status: "missing"};
  if (u["isBlacklisted"] === true) {
    const r = u["blacklistReason"];
    return {kind: "BLOCKED_BLACKLIST", reason: typeof r === "string" && r ? r : "이용 정책 위반"};
  }
  const st = typeof u["accountStatus"] === "string" ? u["accountStatus"] as string : "active";
  if (st === "rejected") return {kind: "REJECTED"};
  if (st !== "active") return {kind: "INCOMPLETE_LEGACY", status: st};
  const until = toMs(u["restrictedUntil"]);
  if (until !== null && until > nowMs) {
    const src = u["restrictionSource"];
    return {kind: "RESTRICTED", untilMs: until, source: typeof src === "string" ? src : null};
  }
  return {kind: "OK"};
}

// ── 가입 세션 상태 ──────────────────────────────────────────────────────
export type SessionState = "started" | "purpose_selected" | "consented" | "cert_issued" |
  "pass_verified" | "committed" | "blocked_existing" | "canceled";
export const OPEN_STATES: ReadonlySet<string> = new Set([
  "started", "purpose_selected", "consented", "cert_issued", "pass_verified",
]);
/** 이 상태에서 카카오 재로그인이 오면 새 세대를 연다. */
export const TERMINAL_STATES: ReadonlySet<string> = new Set([
  "committed", "blocked_existing", "canceled",
]);

/**
 * 세션 bearer secret 판정. sessionId 만 아는 호출자는 아무것도 못 한다(B277-02).
 * @param {Record<string, unknown> | undefined} s 세션 문서
 * @param {unknown} secret 클라가 보낸 secret
 * @param {number} nowMs 서버 시각
 * @return {"OK" | "SESSION_INVALID" | "SESSION_EXPIRED"} 판정
 */
export function sessionSecretVerdict(
  s: Record<string, unknown> | undefined, secret: unknown, nowMs: number,
): "OK" | "SESSION_INVALID" | "SESSION_EXPIRED" {
  if (!s || typeof secret !== "string" || secret.length < 32 || secret.length > 128) {
    return "SESSION_INVALID";
  }
  const want = s["secretHash"];
  if (typeof want !== "string") return "SESSION_INVALID";
  const got = sha256Hex(secret);
  const a = Buffer.from(got, "hex");
  const b = Buffer.from(want, "hex");
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return "SESSION_INVALID";
  const exp = toMs(s["expiresAt"]);
  const secExp = toMs(s["secretExpiresAt"]);
  if (exp === null || secExp === null || nowMs >= exp || nowMs >= secExp) {
    return "SESSION_EXPIRED";
  }
  return "OK";
}

/** @param {number} n 바이트 수 @return {string} 무작위 hex */
export function randomHex(n: number): string {
  return crypto.randomBytes(n).toString("hex");
}

// ── 새 users 문서 allowlist(srvBuildNewUserDoc) ─────────────────────────
/** 새 계정 users 문서에 허용되는 최상위 키 — 이 밖의 키는 쓰지 않는다. */
export const NEW_USER_DOC_KEYS: readonly string[] = [
  "username", "email", "name", "phone", "authPhone", "phoneVerificationLevel",
  "role", "accountStatus", "identityKey", "identityEvidence",
  "passVerifiedAt", "termsConsentAt", "termsConsent", "signupCompletedAt",
  "createdAt", "lastLoginAt", "birthDate", "gender",
  "identityBasisSource", "identityBasisAt",
  "nationalityStatus", "authProviders", "signupSource",
  "managedBusinessIds", "isBlacklisted", "isIdVerified",
  "notifyNewTO", "notifyApplicationResult", "notifyCheckInReminder",
  "notifyWageConfirmed", "notifyScheduleChange", "notifyNotice",
];

export type NewUserDocInput = {
  role: SignupRole;
  name: string;
  phone: string;
  /** YYYYMMDD */
  birthDate: string;
  gender: "남성" | "여성" | null;
  identityKey: string;
  evidence: "kg" | "mock";
  /** 항목별 동의 — termsConsent 맵 그대로 */
  termsConsent: Record<string, {agreed: boolean; version: string; revisionId: string; agreedAt: unknown}>;
  /** 서버 시각 값(Timestamp 류) */
  serverNow: unknown;
  /** KG 인증 시각 */
  passVerifiedAt: unknown;
  /** 필수 동의 충족 시각(세션 동의 시각 · D-1) */
  termsConsentAt: unknown;
  /** 생년월일 Timestamp(UTC 자정) — 파싱 실패면 null */
  birthDateTs: unknown | null;
};

/**
 * 새 계정 users 문서. **계좌 3 필드·서류 경로·버전·제재·통계·homeRegion 없음**(K8).
 *   성별이 없으면 키 자체가 없다. identityBasis 는 성별·생년 둘 다 있을 때만.
 *   임의 비밀번호 Auth 계정을 만들지 않으므로 username/email 은 빈 문자열(UM `?? ''` 계약).
 *
 * @param {NewUserDocInput} i 입력
 * @return {Record<string, unknown>} 문서
 */
export function buildNewUserDoc(i: NewUserDocInput): Record<string, unknown> {
  const doc: Record<string, unknown> = {
    username: "",
    email: "",
    name: i.name,
    phone: i.phone,
    authPhone: i.phone,
    phoneVerificationLevel: "identity_verified",
    role: i.role,
    accountStatus: "active",
    identityKey: i.identityKey,
    identityEvidence: i.evidence,
    passVerifiedAt: i.passVerifiedAt,
    termsConsentAt: i.termsConsentAt,
    termsConsent: i.termsConsent,
    signupCompletedAt: i.serverNow,
    createdAt: i.serverNow,
    lastLoginAt: i.serverNow,
    nationalityStatus: "unknown",
    authProviders: [PROVIDER_KAKAO],
    signupSource: SIGNUP_SOURCE_KAKAO_V1,
    managedBusinessIds: [],
    isBlacklisted: false,
    isIdVerified: false,
    notifyNewTO: true,
    notifyApplicationResult: true,
    notifyCheckInReminder: true,
    notifyWageConfirmed: true,
    notifyScheduleChange: true,
    notifyNotice: true,
  };
  if (i.birthDateTs) doc["birthDate"] = i.birthDateTs;
  if (i.gender) doc["gender"] = i.gender;
  if (i.gender && i.birthDateTs) {
    doc["identityBasisSource"] = "PASS";
    doc["identityBasisAt"] = i.serverNow;
  }
  return doc;
}

/**
 * 새 흐름 계정인가(서버 세대 경계). 클라는 이 값을 쓸 수 없다(rules denylist · create false).
 * @param {Record<string, unknown> | undefined} u users 문서
 * @return {boolean} 새 흐름 계정이면 true
 */
export function isNewCohortUser(u: Record<string, unknown> | undefined): boolean {
  return !!u && u["signupSource"] === SIGNUP_SOURCE_KAKAO_V1;
}

// ── 서류 종류 · 국적 단계 ───────────────────────────────────────────────
export type DocumentKind = "resident_id" | "foreign_registration";
export type NationalityDocDecision =
  | {kind: "LEGACY"; foreign: boolean}
  | {kind: "OK"; foreign: boolean; setDomestic: boolean}
  | {kind: "REJECT"; reason: "DOCUMENT_KIND_REQUIRED" | "FOREIGN_ID_DOCUMENT_REQUIRED" |
      "DOCUMENT_KIND_MISMATCH"};

/**
 * 신분증 제출(callableMarkIdCardVerified) 의 후보 종류 결정.
 *   unknown 은 **내국인 false 가 아니다**(판정278 §3) — 종류 없이 들어오면 거부.
 *   옛 계정(nationalityStatus 없음)은 기존대로 fingerprint 기준.
 *
 * @param {Record<string, unknown> | undefined} u users 문서
 * @param {unknown} documentKind 클라가 고른 종류
 * @return {NationalityDocDecision} 결정
 */
export function decideIdDocumentKind(
  u: Record<string, unknown> | undefined, documentKind: unknown): NationalityDocDecision {
  const ns = u?.["nationalityStatus"];
  if (ns === undefined || ns === null) {
    const fp = u?.["foreignIdentityFingerprint"];
    return {kind: "LEGACY", foreign: typeof fp === "string" && fp.length > 0};
  }
  const dk = documentKind === "resident_id" || documentKind === "foreign_registration" ?
    documentKind as DocumentKind : null;
  if (ns === "unknown") {
    if (dk === null) return {kind: "REJECT", reason: "DOCUMENT_KIND_REQUIRED"};
    if (dk === "foreign_registration") return {kind: "REJECT", reason: "FOREIGN_ID_DOCUMENT_REQUIRED"};
    return {kind: "OK", foreign: false, setDomestic: true};
  }
  if (ns === "domestic") {
    if (dk === "foreign_registration") return {kind: "REJECT", reason: "DOCUMENT_KIND_MISMATCH"};
    return {kind: "OK", foreign: false, setDomestic: false};
  }
  if (ns === "foreign") {
    if (dk === "resident_id") return {kind: "REJECT", reason: "DOCUMENT_KIND_MISMATCH"};
    return {kind: "OK", foreign: true, setDomestic: false};
  }
  // 모르는 값 — 추측하지 않는다.
  return {kind: "REJECT", reason: "DOCUMENT_KIND_REQUIRED"};
}

/**
 * 외국인등록번호에서 파생한 생년·성별(7번째 자리 5–8). 형식 오류면 null.
 * @param {string} n 정규화 13자리
 * @return {{birthDate: string, gender: "남성"|"여성"} | null} 파생값(YYYYMMDD)
 */
export function deriveFromForeignId(
  n: string): {birthDate: string; gender: "남성" | "여성"} | null {
  if (!/^\d{13}$/.test(n)) return null;
  const code = Number(n[6]);
  if (code < 5 || code > 8) return null;
  const yy = Number(n.slice(0, 2));
  const mm = Number(n.slice(2, 4));
  const dd = Number(n.slice(4, 6));
  const year = (code === 7 || code === 8) ? 2000 + yy : 1900 + yy;
  const d = new Date(Date.UTC(year, mm - 1, dd));
  if (d.getUTCFullYear() !== year || d.getUTCMonth() !== mm - 1 || d.getUTCDate() !== dd) {
    return null;
  }
  const pad = (x: number) => String(x).padStart(2, "0");
  return {birthDate: `${year}${pad(mm)}${pad(dd)}`,
    gender: (code === 5 || code === 7) ? "남성" : "여성"};
}

/**
 * @param {unknown} ts Timestamp 류(UTC 자정)
 * @return {string | null} YYYYMMDD
 */
export function tsToYmd(ts: unknown): string | null {
  const ms = toMs(ts);
  if (ms === null) return null;
  const d = new Date(ms);
  const pad = (x: number) => String(x).padStart(2, "0");
  return `${d.getUTCFullYear()}${pad(d.getUTCMonth() + 1)}${pad(d.getUTCDate())}`;
}
