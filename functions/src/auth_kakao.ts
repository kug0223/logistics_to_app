/**
 * [ALFIT-AUTH-KAKAO-ONBOARDING.1] 카카오 1차 가입·로그인·역할 추가·탈퇴 재확인 서버 로직.
 *
 *   index.ts 는 이 모듈의 핸들러를 `onCall` 로 감싸기만 한다. 의존(Firestore·
 *   FieldValue·Timestamp·HttpsError·Auth·외부 어댑터·시계·환경)은 전부 주입이다 —
 *   그래서 시험이 가짜 저장소·가짜 Auth·가짜 어댑터로 **이 원문 그대로** 실행한다.
 *   이 파일은 `crypto` 와 로컬 순수 모듈만 가져온다(모듈 평가 시점 네트워크·SDK 0).
 *
 *   계약(판정277 B277-01~06 · 판정278 clean cutover):
 *     · 완료는 Firestore 한 거래(UID·users·identity·양방향 링크·동의 사건·세션 결과),
 *       Auth 생성·custom token 은 커밋 **뒤** 별도·재시도 가능한 단계(같은 UID 회복).
 *     · 카카오 subject/app 는 서버가 토큰에서 꺼낸다. 세션 자격 = 서버 발급 bearer secret.
 *     · KG 사건은 서버 requestId·세션·세대·목적·역할에 결합, imp_uid 최초 귀속 1회.
 *     · 옛 SHA ciHash · 외국인 등록번호 HMAC · deleted_accounts · 옛 pending 은 읽지 않는다.
 */
import type {
  Firestore, Transaction, DocumentReference, DocumentSnapshot,
} from "firebase-admin/firestore";
import {
  SIGNUP_ROLES, isSignupRole, type SignupRole, PROVIDER_KAKAO,
  SESSION_TTL_MS, SESSION_SECRET_TTL_MS, CERT_TTL_MS, PASS_FRESH_MS,
  CERT_MAX_ATTEMPTS, DELETION_PROOF_TTL_MS, DAY,
  isSafeIdPart, providerSubjectKey, authLinkId, authLinkOwnerId, deletionSessionKey,
  sha256Hex, computeCiKeyV1, isCiKeyV1, CI_KEY_VERSION, toMs,
  parsePortOneCertification, checkKgBinding, ageKst, maskPhone,
  normalizeRestriction, restrictionVerdict, restrictionAfterBlacklist,
  restrictionAfterUnblacklist, restrictionAfterDeletion, restrictionForStore,
  type Restriction, accountStateVerdict, OPEN_STATES,
  sessionSecretVerdict, randomHex, buildNewUserDoc, isNewCohortUser,
} from "./signup_core";
import {
  mockKakaoVerifier, mockPortOneReader,
  type KakaoTokenVerifier, type PortOneCertReader,
} from "./auth_adapters";
import {
  sanitizeConsentEntries, allRequiredSatisfied, type ActiveLegalItem,
} from "./terms_consent_payload";
import {
  resolveProjectionItems, requiredRevisionPointers, gateRequiredRevisions,
} from "./legal_publication";

// ── 주입 의존 ───────────────────────────────────────────────────────────
type AuthAdmin = {
  getUser(uid: string): Promise<unknown>;
  createUser(p: {uid: string}): Promise<unknown>;
  createCustomToken(uid: string): Promise<string>;
};
type HttpsErrorCtor = new (code: never, message: string, details?: unknown) => Error;

export type AuthKakaoDeps = {
  db: Firestore;
  FieldValue: {serverTimestamp(): unknown};
  Timestamp: {fromMillis(ms: number): unknown};
  HttpsError: HttpsErrorCtor;
  auth: () => AuthAdmin;
  kakao: KakaoTokenVerifier;
  portone: PortOneCertReader;
  env: () => Record<string, string | undefined>;
  now: () => number;
  /** 알림 저장(탈퇴 barrier 를 지키는 index.ts 의 srvPersistNotification). best-effort. */
  notify?: (uid: string, payload: Record<string, unknown>) => Promise<unknown>;
};

export type CallReq = {
  auth?: {uid: string} | null;
  data?: unknown;
};

/** verifyPassAuth 핸들러가 **자기 안에서** 읽어 넘기는 비밀(PSB ④). */
export type PassKeys = {impKey?: string; impSecret?: string; ciHmacKey?: string};

const COL = {
  identities: "identities",
  authLinks: "authLinks",
  authLinkOwners: "authLinkOwners",
  authSubjects: "authSubjects",
  sessions: "signupSessions",
  passCerts: "passCertifications",
  proofs: "deletionReauthProofs",
  users: "users",
  tombstones: "account_deletion_tombstones",
  legal: "app_settings",
  revisions: "legal_revisions",
} as const;

type Doc = Record<string, unknown>;

/**
 * 의존을 받아 핸들러 묶음을 만든다. 모듈 최상위에서 불러도 외부 호출 0.
 * @param {AuthKakaoDeps} d 의존
 * @return {object} 핸들러
 */
export function createAuthKakao(d: AuthKakaoDeps) {
  const E = (code: string, reason: string, msg: string, extra?: Doc): Error =>
    new d.HttpsError(code as never, `${reason} ${msg}`, {reason, ...(extra ?? {})});
  const col = (n: string) => d.db.collection(n);
  const ts = (ms: number) => d.Timestamp.fromMillis(ms);
  const sv = () => d.FieldValue.serverTimestamp();
  const dataOf = (s: DocumentSnapshot): Doc | undefined =>
    s.exists ? (s.data() as Doc) : undefined;
  const asObj = (v: unknown): Doc =>
    (v && typeof v === "object" && !Array.isArray(v) ? v as Doc : {});

  // ── 설정 ────────────────────────────────────────────────────────────
  type Cfg = {mock: boolean; appNs: string; pgProvider: string | null};
  function cfg(): Cfg {
    const env = d.env();
    const mock = env["AUTH_MOCK_MODE"] === "true";
    if (mock && env["GCLOUD_PROJECT"] === "alfit-prod") {
      throw E("unavailable", "AUTH_MOCK_FORBIDDEN", "모의 모드는 production 에서 사용할 수 없습니다.");
    }
    const appNs = (env["KAKAO_APP_ID"] ?? "").trim() || (mock ? "0" : "");
    return {mock, appNs, pgProvider: (env["PORTONE_PG_PROVIDER"] ?? "").trim() || null};
  }
  function requireAppNs(c: Cfg): string {
    if (!isSafeIdPart(c.appNs)) {
      throw E("failed-precondition", "KAKAO_NOT_CONFIGURED", "카카오 로그인 설정이 없습니다.");
    }
    return c.appNs;
  }

  // ── 세션 ────────────────────────────────────────────────────────────
  type SessionDoc = Doc & {
    provider: string; appNs: string; subject: string; generation: number;
    purpose: "signup" | "add_role"; fromUid?: string | null;
    role: SignupRole | null; state: string;
    consents: Record<string, Doc>; consentRequiredAt: unknown | null;
    cert: Doc | null; certAttempts: number; pass: Doc | null;
    reservedUid: string | null; result: Doc | null;
  };

  function sessionView(s: SessionDoc, key: string, nowMs: number, secret?: string): Doc {
    const exp = toMs(s["expiresAt"]) ?? 0;
    const state = OPEN_STATES.has(s.state) && nowMs >= exp ? "expired" : s.state;
    const cert = s.cert ? {
      requestId: s.cert["requestId"],
      expiresAtMs: toMs(s.cert["expiresAt"]),
      attempts: s.certAttempts ?? 0,
    } : null;
    const pass = s.pass ? {
      name: s.pass["name"], birthDate: s.pass["birthDate"],
      phoneMasked: maskPhone(String(s.pass["phone"] ?? "")),
    } : null;
    return {
      sessionId: key,
      ...(secret ? {secret} : {}),
      generation: s.generation,
      state,
      purpose: s.purpose,
      role: s.role ?? null,
      consentDone: !!s.consentRequiredAt,
      passDone: !!s.pass,
      cert,
      pass,
      result: s.result ? {uid: s.result["uid"], role: s.result["role"]} : null,
      expiresAtMs: exp,
      secretExpiresAtMs: toMs(s["secretExpiresAt"]),
    };
  }

  function parseSessionInput(data: unknown): {key: string; secret: string; data: Doc} {
    const dd = asObj(data);
    const key = dd["sessionId"];
    const secret = dd["secret"];
    if (typeof key !== "string" || !/^kakao_[A-Za-z0-9-]{1,64}_[A-Za-z0-9-]{1,64}$/.test(key) ||
        typeof secret !== "string") {
      throw E("permission-denied", "SESSION_INVALID", "가입 세션이 올바르지 않습니다.");
    }
    return {key, secret, data: dd};
  }

  function assertSecret(s: Doc | undefined, secret: string, nowMs: number): SessionDoc {
    const v = sessionSecretVerdict(s, secret, nowMs);
    if (v === "SESSION_INVALID") {
      throw E("permission-denied", "SESSION_INVALID", "가입 세션이 올바르지 않습니다. 카카오로 다시 시작해 주세요.");
    }
    if (v === "SESSION_EXPIRED") {
      throw E("deadline-exceeded", "SESSION_EXPIRED", "가입 세션이 만료되었습니다. 카카오로 다시 시작해 주세요.");
    }
    return s as SessionDoc;
  }

  function assertOpen(s: SessionDoc): void {
    if (!OPEN_STATES.has(s.state)) {
      throw E("failed-precondition", "SESSION_STATE", "지금 단계에서는 할 수 없는 요청입니다.",
        {state: s.state});
    }
  }

  /**
   * 세션 문서를 거래 안에서 읽고 secret 을 검증한 뒤 mutate 를 적용한다.
   * mutate 는 쓰기 전에 필요한 다른 읽기를 끝내야 한다(reads-before-writes).
   */
  async function withSession<T>(
    key: string, secret: string,
    fn: (tx: Transaction, s: SessionDoc, ref: DocumentReference, nowMs: number) => Promise<T>,
  ): Promise<T> {
    const ref = col(COL.sessions).doc(key);
    return d.db.runTransaction(async (tx) => {
      const nowMs = d.now();
      const s = assertSecret(dataOf(await tx.get(ref)), secret, nowMs);
      return fn(tx, s, ref, nowMs);
    });
  }

  function freshSecret(nowMs: number): {secret: string; patch: Doc} {
    const secret = randomHex(32);
    return {secret, patch: {
      secretHash: sha256Hex(secret),
      secretIssuedAt: ts(nowMs),
      secretExpiresAt: ts(nowMs + SESSION_SECRET_TTL_MS),
    }};
  }

  function newGeneration(prev: Doc | undefined, base: {
    appNs: string; subject: string; purpose: "signup" | "add_role";
    fromUid: string | null; role: SignupRole | null; nowMs: number;
  }): SessionDoc {
    return {
      provider: PROVIDER_KAKAO,
      appNs: base.appNs,
      subject: base.subject,
      generation: ((prev?.["generation"] as number | undefined) ?? 0) + 1,
      purpose: base.purpose,
      fromUid: base.fromUid,
      role: base.role,
      state: base.role ? "purpose_selected" : "started",
      consents: {},
      consentRequiredAt: null,
      cert: null,
      certAttempts: 0,
      pass: null,
      reservedUid: null,
      result: null,
      createdAt: ts(base.nowMs),
      updatedAt: ts(base.nowMs),
      expiresAt: ts(base.nowMs + SESSION_TTL_MS),
    };
  }

  // ── 약관(시행본) — callableRecordTermsConsent 와 같은 순수 판정 ─────────
  async function loadActiveLegal(): Promise<{items: ActiveLegalItem[]}> {
    const nowMs = d.now();
    const legalSnap = await col(COL.legal).doc("legal_terms").get();
    const items: ActiveLegalItem[] = resolveProjectionItems({
      rawItems: (legalSnap.data() as Doc | undefined)?.["items"], nowMs, toMs,
    }).effective.map((i) => ({id: i.id, version: i.version, isRequired: i.isRequired,
      revisionId: i.revisionId}));
    if (items.length === 0) {
      throw E("failed-precondition", "TERMS_UNAVAILABLE", "약관 정보를 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.");
    }
    const pointers = requiredRevisionPointers(items);
    const revisions = new Map<string, Record<string, unknown>>();
    if (pointers.length > 0) {
      const snaps = await d.db.getAll(...pointers.map((p) => col(COL.revisions).doc(p.revisionId)));
      for (const s of snaps) if (s.exists) revisions.set(s.id, s.data() as Record<string, unknown>);
    }
    const gate = gateRequiredRevisions({pointers, revisions});
    if (!gate.ok) {
      throw E("failed-precondition", "LEGAL_REQUIRED_REVISION_MISMATCH",
        "약관 원문을 확인할 수 없습니다. 잠시 후 다시 시도해 주세요.",
        {gateReason: gate.reason, itemIds: gate.itemIds});
    }
    return {items};
  }

  function consentStatus(items: ActiveLegalItem[], consents: Record<string, Doc>):
    {ok: boolean; stale: string[]; missing: string[]} {
    const stale: string[] = [];
    const missing: string[] = [];
    for (const i of items.filter((x) => x.isRequired)) {
      const c = consents[i.id];
      if (!c || c["agreed"] !== true) missing.push(i.id);
      else if (c["version"] !== i.version ||
        // [B280-03] 발행본 결합 — 같은 버전 문자열이라도 다른 발행본을 가리키면 다른 글이다.
        c["revisionId"] !== (i.revisionId ?? `${i.id}__${i.version}`)) stale.push(i.id);
    }
    return {ok: stale.length === 0 && missing.length === 0, stale, missing};
  }

  /**
   * [판정280 B280-03] 시행 약관 권위를 **거래 안에서** 읽는다 — legal_terms 와 필수 발행본이
   * 이 거래의 read-set 에 들어가 시행·발행 변경과 경합하면 재시도된다.
   */
  async function readActiveLegalInTx(tx: Transaction, nowMs: number): Promise<ActiveLegalItem[]> {
    const legalSnap = await tx.get(col(COL.legal).doc("legal_terms"));
    const items: ActiveLegalItem[] = resolveProjectionItems({
      rawItems: dataOf(legalSnap)?.["items"], nowMs, toMs,
    }).effective.map((i) => ({id: i.id, version: i.version, isRequired: i.isRequired,
      revisionId: i.revisionId}));
    if (items.length === 0) {
      throw E("failed-precondition", "TERMS_UNAVAILABLE", "약관 정보를 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.");
    }
    const pointers = requiredRevisionPointers(items);
    const revisions = new Map<string, Record<string, unknown>>();
    for (const p of pointers) {
      const rs = await tx.get(col(COL.revisions).doc(p.revisionId));
      if (rs.exists) revisions.set(rs.id, rs.data() as Record<string, unknown>);
    }
    const gate = gateRequiredRevisions({pointers, revisions});
    if (!gate.ok) {
      throw E("failed-precondition", "LEGAL_REQUIRED_REVISION_MISMATCH",
        "약관 원문을 확인할 수 없습니다. 잠시 후 다시 시도해 주세요.",
        {gateReason: gate.reason, itemIds: gate.itemIds});
    }
    return items;
  }

  /**
   * [판정280 B280-03] 커밋 직전 최종 판정 — 최신 세션의 필수동의(판본·발행본)·필수 시각·KG.
   * @return {unknown} users.termsConsentAt 로 쓸 값 = 현재 필수 항목 동의 시각 중 가장 늦은 것
   */
  function assertCommitConsentAndPass(s: SessionDoc, items: ActiveLegalItem[], nowMs: number,
    ciKey: string, mockAllowed: boolean): unknown {
    const consents = s.consents ?? {};
    const cs = consentStatus(items, consents);
    if (!cs.ok) {
      throw E("failed-precondition", cs.stale.length > 0 ? "TERMS_VERSION_STALE" : "CONSENT_REQUIRED",
        "필수 약관 동의를 다시 확인해 주세요.", {itemIds: [...cs.stale, ...cs.missing]});
    }
    if (!s.consentRequiredAt) {
      throw E("failed-precondition", "CONSENT_REQUIRED", "필수 약관 동의를 다시 확인해 주세요.");
    }
    let latest: unknown = null;
    let latestMs = -1;
    for (const i of items.filter((x) => x.isRequired)) {
      const at = consents[i.id]?.["agreedAt"];
      const ms = toMs(at);
      if (ms === null) {
        throw E("failed-precondition", "CONSENT_REQUIRED", "필수 약관 동의 시각을 확인할 수 없습니다.");
      }
      if (ms > latestMs) { latestMs = ms; latest = at; }
    }
    const pass = s.pass;
    const cert = s.cert;
    const passAt = toMs(pass?.["verifiedAt"]);
    if (!pass || passAt === null || nowMs - passAt > PASS_FRESH_MS) {
      throw E("deadline-exceeded", "PASS_RESULT_STALE", "본인인증 후 시간이 지났습니다. 다시 인증해 주세요.");
    }
    if (!cert || pass["requestId"] !== cert["requestId"] || cert["role"] !== s.role ||
        pass["role"] !== s.role || cert["purpose"] !== s.purpose || pass["ciKey"] !== ciKey) {
      throw E("failed-precondition", "PASS_ROLE_MISMATCH", "역할이 바뀌었습니다. 다시 인증해 주세요.");
    }
    if (pass["evidence"] === "mock" && !mockAllowed) {
      throw E("failed-precondition", "MOCK_EVIDENCE_FORBIDDEN", "모의 인증 결과는 사용할 수 없습니다.");
    }
    return latest;
  }

  // ── Auth 준비·토큰(커밋 뒤 · 재시도 가능) ──────────────────────────────
  async function ensureAuthAndToken(uid: string, opts: {deletionRecovery?: boolean} = {}):
    Promise<string> {
    if (!isSafeIdPart(uid)) throw E("internal", "AUTH_PROVISION_RETRY", "계정 준비에 실패했습니다.");
    const [uSnap, tSnap] = await Promise.all([
      col(COL.users).doc(uid).get(), col(COL.tombstones).doc(uid).get(),
    ]);
    const u = dataOf(uSnap);
    const deleting = tSnap.exists || u?.["accountStatus"] === "deleting";
    if (!opts.deletionRecovery) {
      if (!u || !isNewCohortUser(u) || deleting) {
        throw E("failed-precondition", "ACCOUNT_INCOMPLETE", "계정 상태를 확인할 수 없습니다.");
      }
    }
    const a = d.auth();
    let exists = true;
    try {
      await a.getUser(uid);
    } catch (e) {
      if ((e as {code?: string})?.code === "auth/user-not-found") exists = false;
      else throw E("unavailable", "AUTH_PROVISION_RETRY", "계정 준비가 지연되고 있습니다. 잠시 후 다시 시도해 주세요.");
    }
    if (!exists) {
      // [B277-04] 삭제 중/삭제된 UID 는 다시 만들지 않는다.
      if (deleting || opts.deletionRecovery) {
        throw E("failed-precondition", "ACCOUNT_DELETED", "탈퇴가 완료된 계정입니다.");
      }
      try {
        await a.createUser({uid});
      } catch (e) {
        if ((e as {code?: string})?.code !== "auth/uid-already-exists") {
          throw E("unavailable", "AUTH_PROVISION_RETRY", "계정 준비가 지연되고 있습니다. 잠시 후 다시 시도해 주세요.");
        }
      }
    }
    let token: string;
    try {
      token = await a.createCustomToken(uid);
    } catch (_e) {
      throw E("unavailable", "AUTH_PROVISION_RETRY", "계정 준비가 지연되고 있습니다. 잠시 후 다시 시도해 주세요.");
    }
    if (u && !u["authProvisionedAt"] && !deleting) {
      try {
        await col(COL.users).doc(uid).update({authProvisionedAt: sv()});
      } catch (_e) {/* 정보용 — gate 아님 */}
    }
    return token;
  }

  // ── 카카오 토큰 → subject ─────────────────────────────────────────────
  async function kakaoSubject(accessToken: unknown, c: Cfg, appNs: string): Promise<string> {
    if (typeof accessToken !== "string" || accessToken.length < 8 || accessToken.length > 4096) {
      throw E("unauthenticated", "KAKAO_TOKEN_INVALID", "카카오 로그인 정보가 올바르지 않습니다.");
    }
    const verifier = c.mock ? mockKakaoVerifier(appNs) : d.kakao;
    const info = await verifier.verify(accessToken);
    if (!info.ok) {
      if (info.reason === "KAKAO_UNAVAILABLE") {
        throw E("unavailable", "KAKAO_UNAVAILABLE", "카카오 확인이 지연되고 있습니다. 잠시 후 다시 시도해 주세요.");
      }
      throw E("unauthenticated", "KAKAO_TOKEN_INVALID", "카카오 로그인 정보가 올바르지 않습니다.");
    }
    if (info.appId !== appNs) {
      throw E("permission-denied", "KAKAO_APP_MISMATCH", "허용되지 않은 앱의 카카오 로그인입니다.");
    }
    if (!(info.expiresInSec > 0) || !isSafeIdPart(info.subject)) {
      throw E("unauthenticated", "KAKAO_TOKEN_INVALID", "카카오 로그인 정보가 만료되었습니다.");
    }
    return info.subject;
  }

  function verdictError(v: ReturnType<typeof accountStateVerdict>): Error | null {
    switch (v.kind) {
    case "BLOCKED_BLACKLIST":
      return E("permission-denied", "ACCOUNT_BLACKLISTED", "계정 이용 차단 상태입니다.",
        {blacklistReason: v.reason});
    case "REJECTED":
      return E("permission-denied", "ACCOUNT_REJECTED", "이용할 수 없는 계정입니다.");
    case "RESTRICTED":
      return E("permission-denied", "ACCOUNT_RESTRICTED", "이용 제한 기간입니다.",
        {restrictedUntilMs: v.untilMs, restrictionSource: v.source});
    case "INCOMPLETE_LEGACY":
      return E("failed-precondition", "ACCOUNT_INCOMPLETE", "계정 상태를 확인할 수 없습니다.");
    default:
      return null;
    }
  }

  /**
   * [판정280 B280-01] 삭제된 UID 의 잔존 링크만 지운다 — **링크마다 소유(uid) 를 거래 안에서 대조**.
   *   같은 카카오의 다른 역할(생존 UID) 링크는 목록에 잘못 들어와도 지우지 않는다.
   *   uid 키 문서(authLinkOwners/{uid}_kakao · deletionReauthProofs/{uid})는 이 UID 것이다.
   */
  async function cleanupDeletedLinksForUid(uid: string, linkIds: string[]): Promise<void> {
    if (!isSafeIdPart(uid)) return;
    try {
      await d.db.runTransaction(async (tx) => {
        const refs = [...new Set(linkIds)].filter((id) => /^[A-Za-z0-9_-]{1,300}$/.test(id))
          .map((id) => col(COL.authLinks).doc(id));
        const snaps = await Promise.all(refs.map((r) => tx.get(r)));
        snaps.forEach((s, i) => {
          if (s.exists && (s.data() as Doc)["uid"] === uid) tx.delete(refs[i]);
        });
        tx.delete(col(COL.authLinkOwners).doc(authLinkOwnerId(uid, PROVIDER_KAKAO)));
        tx.delete(col(COL.proofs).doc(uid));
      });
    } catch (_e) {/* 다음 로그인에서 다시 시도 */}
  }

  /**
   * [판정280 B280-02] 탈퇴 뒤 카카오 SDK 연결 해제(unlink) 범위.
   *   같은 카카오(subject)에 이 UID 말고 살아 있는 역할 링크가 있으면 unlink 하면 그 역할 로그인이 끊긴다.
   * @return {Promise<"ALLOWED" | "KEEP_OTHER_ROLE" | null>} 옛(비밀번호) 계정이면 null
   */
  async function providerUnlinkScope(uid: string): Promise<"ALLOWED" | "KEEP_OTHER_ROLE" | null> {
    const who = await identityOf(uid);
    if (!who) return null;
    const others = SIGNUP_ROLES.filter((r) => r !== who.role)
      .map((r) => col(COL.authLinks).doc(authLinkId(PROVIDER_KAKAO, who.appNs, who.subject, r)));
    const snaps = await d.db.getAll(...others);
    const alive = snaps.some((s) => s.exists && (s.data() as Doc)["uid"] !== uid);
    return alive ? "KEEP_OTHER_ROLE" : "ALLOWED";
  }

  // ════════════════════════════════════════════════════════════════════
  // callableAuthKakao
  // ════════════════════════════════════════════════════════════════════
  async function authKakao(req: CallReq): Promise<Doc> {
    const c = cfg();
    const appNs = requireAppNs(c);
    const data = asObj(req.data);
    const wantRole = data["role"];
    if (wantRole !== undefined && wantRole !== null && !isSignupRole(wantRole)) {
      throw E("invalid-argument", "ROLE_INVALID", "역할이 올바르지 않습니다.");
    }
    const subject = await kakaoSubject(data["accessToken"], c, appNs);

    const linkRefs = SIGNUP_ROLES.map((r) =>
      col(COL.authLinks).doc(authLinkId(PROVIDER_KAKAO, appNs, subject, r)));
    const linkSnaps = await d.db.getAll(...linkRefs);
    const links = new Map<SignupRole, Doc>();
    linkSnaps.forEach((s, i) => {
      const v = dataOf(s);
      if (v && typeof v["uid"] === "string") links.set(SIGNUP_ROLES[i], v);
    });

    if (links.size > 0) {
      const linked = [...links.keys()];
      let role: SignupRole;
      if (isSignupRole(wantRole)) {
        if (!links.has(wantRole)) return {status: "ROLE_NOT_LINKED", roles: linked};
        role = wantRole;
      } else if (linked.length > 1) {
        return {status: "ROLE_SELECTION_REQUIRED", roles: linked};
      } else {
        role = linked[0];
      }
      const uid = links.get(role)!["uid"] as string;
      const [uSnap, tSnap] = await Promise.all([
        col(COL.users).doc(uid).get(), col(COL.tombstones).doc(uid).get(),
      ]);
      const u = dataOf(uSnap);
      const verdict = accountStateVerdict(u, tSnap.exists, d.now());
      if (verdict.kind === "DELETION_RECOVERY") {
        try {
          const customToken = await ensureAuthAndToken(uid, {deletionRecovery: true});
          // [B280-02] 삭제 중(블랙이어도)은 삭제 복구만 — 업무 writer 는 deleting 계정을 이미 거부한다.
          return {status: "DELETION_RECOVERY", scope: "DELETION_ONLY", uid, role, customToken};
        } catch (e) {
          if ((e as {details?: Doc})?.details?.["reason"] === "ACCOUNT_DELETED" && !u) {
            // Auth 까지 삭제가 끝난 뒤 남은 링크 — **이 역할(삭제 UID) 링크만** 정리한다(재생성 0 · B280-01).
            await cleanupDeletedLinksForUid(uid, [linkRefs[SIGNUP_ROLES.indexOf(role)].id]);
          }
          throw e;
        }
      }
      const ve = verdictError(verdict);
      if (ve) throw ve;
      const customToken = await ensureAuthAndToken(uid);
      try {
        await Promise.all([
          col(COL.users).doc(uid).update({lastLoginAt: sv()}),
          linkRefs[SIGNUP_ROLES.indexOf(role)].update({lastLoginAt: sv()}),
        ]);
      } catch (_e) {/* 정보용 */}
      return {status: "TOKEN", uid, role, customToken};
    }

    // 연결 없음 → 가입 세션 열기/재개(secret 회전)
    const key = providerSubjectKey(PROVIDER_KAKAO, appNs, subject);
    const ref = col(COL.sessions).doc(key);
    const out = await d.db.runTransaction(async (tx) => {
      const nowMs = d.now();
      const prev = dataOf(await tx.get(ref));
      const exp = toMs(prev?.["expiresAt"]) ?? 0;
      const reuse = !!prev && OPEN_STATES.has(prev["state"] as string) && nowMs < exp;
      const base: SessionDoc = reuse ? prev as SessionDoc : newGeneration(prev, {
        appNs, subject, purpose: "signup", fromUid: null,
        role: isSignupRole(wantRole) ? wantRole : null, nowMs,
      });
      const {secret, patch} = freshSecret(nowMs);
      const next = {...base, ...patch, updatedAt: ts(nowMs)} as SessionDoc;
      tx.set(ref, next);
      return {next, secret, nowMs};
    });
    return {status: "SIGNUP_REQUIRED", session: sessionView(out.next, key, out.nowMs, out.secret)};
  }

  // ════════════════════════════════════════════════════════════════════
  // 세션 callable
  // ════════════════════════════════════════════════════════════════════
  async function sessionGet(req: CallReq): Promise<Doc> {
    const {key, secret} = parseSessionInput(req.data);
    const snap = await col(COL.sessions).doc(key).get();
    const nowMs = d.now();
    const s = assertSecret(dataOf(snap), secret, nowMs);
    return {session: sessionView(s, key, nowMs)};
  }

  async function sessionSetPurpose(req: CallReq): Promise<Doc> {
    const {key, secret, data} = parseSessionInput(req.data);
    const role = data["role"];
    if (!isSignupRole(role)) throw E("invalid-argument", "ROLE_INVALID", "역할이 올바르지 않습니다.");
    return withSession(key, secret, async (tx, s, ref, nowMs) => {
      assertOpen(s);
      if (s.purpose !== "signup") {
        throw E("failed-precondition", "PURPOSE_FIXED", "역할 추가 세션은 역할을 바꿀 수 없습니다.");
      }
      const patch: Doc = {role, updatedAt: ts(nowMs)};
      if (s.role !== role) {
        // [B277-02 role 결합] 역할이 바뀌면 이전 KG 준비·결과는 무효.
        patch["cert"] = null;
        patch["pass"] = null;
        patch["state"] = s.consentRequiredAt ? "consented" : "purpose_selected";
      } else if (s.state === "started") {
        patch["state"] = "purpose_selected";
      }
      tx.update(ref, patch);
      return {session: sessionView({...s, ...patch} as SessionDoc, key, nowMs)};
    });
  }

  async function sessionConsent(req: CallReq): Promise<Doc> {
    const {key, secret, data} = parseSessionInput(req.data);
    const rec = data["consentRecord"];
    if (!rec || typeof rec !== "object" || Array.isArray(rec)) {
      throw E("invalid-argument", "CONSENT_INVALID", "동의 내용이 필요합니다.");
    }
    const entries = Object.entries(rec as Doc);
    if (entries.length > 20) throw E("invalid-argument", "CONSENT_INVALID", "동의 항목이 너무 많습니다.");
    const {items} = await loadActiveLegal();
    return withSession(key, secret, async (tx, s, ref, nowMs) => {
      assertOpen(s);
      const existing = s.consents ?? {};
      // [판정280 B280-04] 미완료 가입 세션은 **마지막 선택이 이긴다** — 아직 회원도, 확정된 동의
      //   기록도 없다. 그래서 공유 sanitizer 의 '확정 동의 true→false 버림' 보호(기존 회원 재동의 계약)를
      //   여기에는 적용하지 않는다: existing 을 비워 넘기면 id·버전·boolean 검증은 그대로 하고
      //   철회 차단만 빠진다. 공유 함수(terms_consent_payload.ts)와 callableRecordTermsConsent 는 불변.
      //   필수 충족 판정은 아래에서 저장된 세션 선택(existing)과 이번 선택(updates)을 합쳐 다시 한다.
      const {updates, staleVersions} = sanitizeConsentEntries({
        entries: entries as Array<[string, {agreed?: unknown; version?: unknown}]>,
        activeItems: items, existing: {},
      });
      if (staleVersions.length > 0) {
        throw E("failed-precondition", "TERMS_VERSION_STALE", "약관이 변경되었습니다. 다시 확인하고 동의해 주세요.");
      }
      const merged: Record<string, Doc> = {...existing};
      for (const [itemId, v] of Object.entries(updates)) {
        const item = items.find((i) => i.id === itemId);
        merged[itemId] = {agreed: v.agreed, version: v.version, revisionId: v.revisionId,
          agreedAt: sv(), requiredAtConsentTime: item?.isRequired === true};
      }
      const requiredOk = allRequiredSatisfied({activeItems: items, existing, updates});
      const patch: Doc = {consents: merged, updatedAt: ts(nowMs)};
      if (requiredOk && !s.consentRequiredAt) patch["consentRequiredAt"] = sv();
      if (!requiredOk) patch["consentRequiredAt"] = null;
      if (requiredOk && s.state === "purpose_selected") patch["state"] = "consented";
      tx.update(ref, patch);
      const st = consentStatus(items, merged);
      return {
        session: sessionView({...s, ...patch,
          consentRequiredAt: requiredOk ? (s.consentRequiredAt ?? true) : null} as SessionDoc,
        key, nowMs),
        requiredSatisfied: requiredOk,
        reconsentRequired: [...st.missing, ...st.stale],
      };
    });
  }

  async function sessionPrepareCertification(req: CallReq): Promise<Doc> {
    const {key, secret} = parseSessionInput(req.data);
    return withSession(key, secret, async (tx, s, ref, nowMs) => {
      assertOpen(s);
      if (!s.role || !["consented", "cert_issued", "pass_verified"].includes(s.state)) {
        throw E("failed-precondition", s.consentRequiredAt ? "SESSION_STATE" : "CONSENT_REQUIRED",
          "필수 약관 동의 후 본인인증을 진행할 수 있습니다.");
      }
      if (!s.consentRequiredAt) {
        throw E("failed-precondition", "CONSENT_REQUIRED", "필수 약관 동의 후 본인인증을 진행할 수 있습니다.");
      }
      const attempts = (s.certAttempts ?? 0) + 1;
      if (attempts > CERT_MAX_ATTEMPTS) {
        throw E("resource-exhausted", "CERT_ATTEMPTS_EXCEEDED", "본인인증 시도 횟수를 초과했습니다. 카카오로 다시 시작해 주세요.");
      }
      const requestId = "alfit_cert_" + randomHex(12);
      const cert = {requestId, purpose: s.purpose, role: s.role,
        issuedAt: ts(nowMs), expiresAt: ts(nowMs + CERT_TTL_MS)};
      const patch: Doc = {cert, certAttempts: attempts, pass: null, state: "cert_issued",
        updatedAt: ts(nowMs)};
      tx.update(ref, patch);
      return {session: sessionView({...s, ...patch} as SessionDoc, key, nowMs),
        requestId, expiresAtMs: nowMs + CERT_TTL_MS};
    });
  }

  async function sessionCancel(req: CallReq): Promise<Doc> {
    const {key, secret} = parseSessionInput(req.data);
    return withSession(key, secret, async (tx, s, ref, nowMs) => {
      if (!OPEN_STATES.has(s.state)) return {session: sessionView(s, key, nowMs)};
      const patch: Doc = {state: "canceled", cert: null, pass: null, updatedAt: ts(nowMs)};
      tx.update(ref, patch);
      return {session: sessionView({...s, ...patch} as SessionDoc, key, nowMs)};
    });
  }

  /** 호출 uid 에 묶인 카카오 링크(역방향 → 정방향). */
  async function providerLinkOf(uid: string): Promise<{linkId: string; link: Doc} | null> {
    if (!isSafeIdPart(uid)) return null;
    const own = dataOf(await col(COL.authLinkOwners).doc(authLinkOwnerId(uid, PROVIDER_KAKAO)).get());
    const linkId = own?.["linkId"];
    if (typeof linkId !== "string") return null;
    const link = dataOf(await col(COL.authLinks).doc(linkId).get());
    if (!link || link["uid"] !== uid) return null;
    return {linkId, link};
  }

  async function sessionStartAddRole(req: CallReq): Promise<Doc> {
    const uid = req.auth?.uid;
    if (!uid) throw E("unauthenticated", "LOGIN_REQUIRED", "로그인이 필요합니다.");
    const role = asObj(req.data)["role"];
    if (!isSignupRole(role)) throw E("invalid-argument", "ROLE_INVALID", "역할이 올바르지 않습니다.");
    const c = cfg();
    const appNs = requireAppNs(c);
    const pl = await providerLinkOf(uid);
    if (!pl || pl.link["appNs"] !== appNs) {
      throw E("failed-precondition", "NO_PROVIDER_LINK", "카카오로 연결된 계정에서만 역할을 추가할 수 있습니다.");
    }
    const subject = pl.link["subject"] as string;
    if (pl.link["role"] === role) {
      throw E("already-exists", "ROLE_ALREADY_LINKED", "이미 이 역할의 계정이 있습니다.");
    }
    const otherLink = await col(COL.authLinks).doc(authLinkId(PROVIDER_KAKAO, appNs, subject, role)).get();
    if (otherLink.exists) throw E("already-exists", "ROLE_ALREADY_LINKED", "이미 이 역할의 계정이 있습니다.");
    const [uSnap, tSnap] = await Promise.all([
      col(COL.users).doc(uid).get(), col(COL.tombstones).doc(uid).get(),
    ]);
    const v = accountStateVerdict(dataOf(uSnap), tSnap.exists, d.now());
    if (v.kind !== "OK") {
      throw E("permission-denied", "ROLE_ADD_BLOCKED", "지금 계정 상태에서는 역할을 추가할 수 없습니다.", {verdict: v.kind});
    }
    const key = providerSubjectKey(PROVIDER_KAKAO, appNs, subject);
    const ref = col(COL.sessions).doc(key);
    const out = await d.db.runTransaction(async (tx) => {
      const nowMs = d.now();
      const prev = dataOf(await tx.get(ref));
      const base = newGeneration(prev, {appNs, subject, purpose: "add_role", fromUid: uid, role, nowMs});
      const {secret, patch} = freshSecret(nowMs);
      const next = {...base, ...patch} as SessionDoc;
      tx.set(ref, next);
      return {next, secret, nowMs};
    });
    return {session: sessionView(out.next, key, out.nowMs, out.secret)};
  }

  // ════════════════════════════════════════════════════════════════════
  // KG 결과 확인(verifyPassAuth 의 새 목적)
  // ════════════════════════════════════════════════════════════════════
  type KgOk = {ci: string; name: string; birthDate: string; phone: string;
    gender: "남성" | "여성" | null; pgCheck: string; evidence: "kg" | "mock"};

  async function readKg(impUid: string, keys: PassKeys, c: Cfg, cert: Doc): Promise<KgOk> {
    const requestId = cert["requestId"] as string;
    const issuedAtMs = toMs(cert["issuedAt"]) ?? 0;
    const nowMs = d.now();
    let reader: PortOneCertReader;
    if (c.mock) {
      reader = mockPortOneReader(() => ({requestId, nowMs}));
    } else {
      if (!keys.impKey || !keys.impSecret) {
        throw E("internal", "PORTONE_NOT_CONFIGURED", "본인인증 설정이 없습니다.");
      }
      reader = d.portone;
    }
    const r = await reader.read({impKey: keys.impKey ?? "", impSecret: keys.impSecret ?? "", impUid});
    if (!r.ok) throw E("unavailable", "PORTONE_UNAVAILABLE", "본인인증 결과 확인이 지연되고 있습니다. 잠시 후 다시 시도해 주세요.");
    const p = parsePortOneCertification(r.raw);
    if (!p.ok) {
      if (p.reason === "KG_NOT_CERTIFIED") throw E("permission-denied", p.reason, "본인인증에 실패했습니다.");
      if (p.reason === "KG_CI_MISSING") {
        throw E("failed-precondition", p.reason, "본인확인 정보를 받지 못했습니다. 다른 인증 수단으로 다시 시도해 주세요.");
      }
      throw E("failed-precondition", p.reason, "본인인증 데이터가 불완전합니다.");
    }
    const b = checkKgBinding(p.cert, {requestId, issuedAtMs, nowMs, pgProvider: c.pgProvider});
    if (!b.ok) throw E("permission-denied", "KG_BINDING_MISMATCH", "이번 요청의 본인인증 결과가 아닙니다. 다시 인증해 주세요.");
    if (ageKst(p.cert.birthDate, nowMs) < 19) {
      throw E("permission-denied", "UNDER_AGE", "만 19세 이상만 가입할 수 있습니다.");
    }
    return {ci: p.cert.ci, name: p.cert.name, birthDate: p.cert.birthDate, phone: p.cert.phone,
      gender: p.cert.gender, pgCheck: b.pgCheck, evidence: c.mock ? "mock" : "kg"};
  }

  function ciKeyOf(keys: PassKeys, ci: string): string {
    try {
      return computeCiKeyV1(keys.ciHmacKey ?? "", ci);
    } catch (_e) {
      throw E("internal", "CI_KEY_UNAVAILABLE", "본인확인 처리 설정이 없습니다.");
    }
  }

  function sameBinding(pc: Doc | undefined, b: {sessionKey: string; generation: number; requestId: string}): boolean {
    return !!pc && pc["sessionKey"] === b.sessionKey && pc["generation"] === b.generation &&
      pc["requestId"] === b.requestId;
  }

  async function verifyPassSignup(req: CallReq, keys: PassKeys): Promise<Doc> {
    const c = cfg();
    const {key, secret, data} = parseSessionInput(req.data);
    const impUid = data["imp_uid"];
    if (typeof impUid !== "string" || impUid.length < 1 || impUid.length > 128) {
      throw E("invalid-argument", "IMP_UID_REQUIRED", "본인인증 결과가 필요합니다.");
    }
    const impHash = sha256Hex(impUid);
    const pcRef = col(COL.passCerts).doc(impHash);
    const sRef = col(COL.sessions).doc(key);
    const nowMs0 = d.now();
    const s0 = assertSecret(dataOf(await sRef.get()), secret, nowMs0);
    assertOpen(s0);
    const pc0 = dataOf(await pcRef.get());
    const binding0 = {sessionKey: key, generation: s0.generation,
      requestId: (s0.cert?.["requestId"] as string | undefined) ?? ""};
    const idem = (s: SessionDoc, nowMs: number, roleTaken: boolean) => ({
      session: sessionView(s, key, nowMs),
      name: s.pass?.["name"], birthDate: s.pass?.["birthDate"],
      phoneMasked: maskPhone(String(s.pass?.["phone"] ?? "")), roleTaken,
    });
    if (pc0) {
      if (sameBinding(pc0, binding0) && s0.pass?.["impUidHash"] === impHash) {
        return idem(s0, nowMs0, false);
      }
      throw E("permission-denied", "IMP_UID_BOUND_ELSEWHERE", "이미 사용된 본인인증 결과입니다. 다시 인증해 주세요.");
    }
    if (s0.state !== "cert_issued" || !s0.cert) {
      throw E("failed-precondition", "CERT_NOT_ISSUED", "본인인증 준비가 필요합니다.");
    }
    if (nowMs0 >= (toMs(s0.cert["expiresAt"]) ?? 0)) {
      throw E("deadline-exceeded", "CERT_EXPIRED", "본인인증 시간이 지났습니다. 다시 인증해 주세요.");
    }
    if (!keys.ciHmacKey || keys.ciHmacKey.length < 16) {
      throw E("internal", "CI_KEY_UNAVAILABLE", "본인확인 처리 설정이 없습니다.");
    }
    const kg = await readKg(impUid, keys, c, s0.cert);
    const ciKey = ciKeyOf(keys, kg.ci);

    return d.db.runTransaction(async (tx) => {
      const nowMs = d.now();
      const s = assertSecret(dataOf(await tx.get(sRef)), secret, nowMs);
      const pc = dataOf(await tx.get(pcRef));
      const role = s.role as SignupRole;
      const ident = dataOf(await tx.get(col(COL.identities).doc(ciKey)));
      const binding = {sessionKey: key, generation: s.generation,
        requestId: (s.cert?.["requestId"] as string | undefined) ?? ""};
      const roleTaken = !!asObj(ident?.["roles"])[role];
      if (pc) {
        if (sameBinding(pc, binding) && s.pass?.["impUidHash"] === impHash) return idem(s, nowMs, roleTaken);
        throw E("permission-denied", "IMP_UID_BOUND_ELSEWHERE", "이미 사용된 본인인증 결과입니다. 다시 인증해 주세요.");
      }
      if (s.state !== "cert_issued" || !s.cert || s.generation !== s0.generation ||
          binding.requestId !== binding0.requestId ||
          s.cert["purpose"] !== s.purpose || s.cert["role"] !== role) {
        throw E("failed-precondition", "SESSION_STATE", "본인인증 준비가 바뀌었습니다. 다시 인증해 주세요.");
      }
      // [판정281 C281-02] 가입 cert 도 같은 경계 — 거래 시도 시각에 만료면 미소비·미결합.
      if (nowMs >= (toMs(s.cert["expiresAt"]) ?? 0)) {
        throw E("deadline-exceeded", "CERT_EXPIRED", "본인인증 시간이 지났습니다. 다시 인증해 주세요.");
      }
      tx.create(pcRef, {
        sessionKey: key, generation: s.generation, requestId: binding.requestId,
        purpose: s.purpose, role, ciKey, evidence: kg.evidence, pgCheck: kg.pgCheck,
        consumedAt: sv(), outcomeRef: null,
      });
      const pass = {impUidHash: impHash, ciKey, name: kg.name, birthDate: kg.birthDate,
        phone: kg.phone, gender: kg.gender, verifiedAt: sv(), requestId: binding.requestId,
        role, evidence: kg.evidence, pgCheck: kg.pgCheck};
      const patch: Doc = {pass, state: "pass_verified", updatedAt: ts(nowMs)};
      tx.update(sRef, patch);
      return idem({...s, ...patch} as SessionDoc, nowMs, roleTaken);
    });
  }

  // ════════════════════════════════════════════════════════════════════
  // callableCompleteSignup — Firestore 커밋 단계(B277-01)
  // ════════════════════════════════════════════════════════════════════
  async function completeSignup(req: CallReq): Promise<Doc> {
    const c = cfg();
    const appNs = requireAppNs(c);
    const {key, secret} = parseSessionInput(req.data);
    const sRef = col(COL.sessions).doc(key);
    const nowMs0 = d.now();
    const s0 = assertSecret(dataOf(await sRef.get()), secret, nowMs0);
    if (s0.state === "committed" && s0.result) {
      return withToken(s0.result["uid"] as string, s0.result["role"] as SignupRole);
    }
    if (s0.state !== "pass_verified" || !s0.pass || !s0.cert || !s0.role) {
      throw E("failed-precondition", OPEN_STATES.has(s0.state) ? "PASS_REQUIRED" : "SESSION_STATE",
        "본인인증을 먼저 완료해 주세요.", {state: s0.state});
    }
    if (s0.appNs !== appNs) throw E("permission-denied", "SESSION_INVALID", "가입 세션이 올바르지 않습니다.");
    const passAt = toMs(s0.pass["verifiedAt"]);
    if (passAt === null || nowMs0 - passAt > PASS_FRESH_MS) {
      throw E("deadline-exceeded", "PASS_RESULT_STALE", "본인인증 후 시간이 지났습니다. 다시 인증해 주세요.");
    }
    if (s0.pass["requestId"] !== s0.cert["requestId"] || s0.cert["role"] !== s0.role ||
        s0.pass["role"] !== s0.role || s0.cert["purpose"] !== s0.purpose) {
      throw E("failed-precondition", "PASS_ROLE_MISMATCH", "역할이 바뀌었습니다. 다시 인증해 주세요.");
    }
    if (s0.pass["evidence"] === "mock" && !c.mock) {
      throw E("failed-precondition", "MOCK_EVIDENCE_FORBIDDEN", "모의 인증 결과는 사용할 수 없습니다.");
    }
    const ciKey = s0.pass["ciKey"];
    if (!isCiKeyV1(ciKey)) throw E("failed-precondition", "PASS_REQUIRED", "본인인증을 먼저 완료해 주세요.");
    const {items} = await loadActiveLegal();
    const cs = consentStatus(items, s0.consents ?? {});
    if (!cs.ok) {
      throw E("failed-precondition", cs.stale.length > 0 ? "TERMS_VERSION_STALE" : "CONSENT_REQUIRED",
        "필수 약관 동의를 다시 확인해 주세요.", {itemIds: [...cs.stale, ...cs.missing]});
    }
    const role = s0.role;
    const subject = s0.subject;
    const subjectKey = providerSubjectKey(PROVIDER_KAKAO, appNs, subject);
    const linkKey = authLinkId(PROVIDER_KAKAO, appNs, subject, role);
    const genUid = s0.reservedUid ?? col(COL.users).doc().id;
    const pcRef = col(COL.passCerts).doc(s0.pass["impUidHash"] as string);

    type Out = {kind: "committed" | "idempotent"; uid: string} |
      {kind: "blocked"; reason: string; details: Doc; notifyUid?: string};
    const out: Out = await d.db.runTransaction(async (tx): Promise<Out> => {
      const nowMs = d.now();
      const s = assertSecret(dataOf(await tx.get(sRef)), secret, nowMs);
      if (s.state === "committed" && s.result) return {kind: "idempotent", uid: s.result["uid"] as string};
      if (s.state !== "pass_verified" || !s.pass || s.generation !== s0.generation ||
          s.pass["requestId"] !== s0.pass!["requestId"] || s.role !== role) {
        throw E("failed-precondition", "SESSION_STATE", "가입 정보가 바뀌었습니다. 다시 시도해 주세요.");
      }
      // [판정280 B280-03] 사전검사(s0·거래 밖 약관)로 끝내지 않는다. **실제로 커밋할 최신 세션 s** 의
      //   필수동의·판본·필수 시각과 KG 신선도·결합을, 이 거래가 읽는 시행 약관 권위(legal_terms ·
      //   필수 발행본)에 대해 다시 판정한다. 약관 문서를 거래 read-set 에 넣었으므로 그 사이 시행본이
      //   바뀌면 거래가 재시도되어 새 판본으로 다시 판정된다 — 미충족 active 생성 0.
      const legalItems = await readActiveLegalInTx(tx, nowMs);
      const commitConsentAt = assertCommitConsentAndPass(s, legalItems, nowMs, ciKey, c.mock);
      const uid = s.reservedUid ?? genUid;
      const idRef = col(COL.identities).doc(ciKey);
      const subRef = col(COL.authSubjects).doc(subjectKey);
      const linkRef = col(COL.authLinks).doc(linkKey);
      const ownerRef = col(COL.authLinkOwners).doc(authLinkOwnerId(uid, PROVIDER_KAKAO));
      const userRef = col(COL.users).doc(uid);
      const tombRef = col(COL.tombstones).doc(uid);
      const fromRef = s.purpose === "add_role" && s.fromUid ? col(COL.users).doc(s.fromUid) : null;
      const fromTombRef = fromRef ? col(COL.tombstones).doc(s.fromUid as string) : null;
      const [idSnap, subSnap, linkSnap, ownerSnap, userSnap, tombSnap, pcSnap] = await Promise.all([
        tx.get(idRef), tx.get(subRef), tx.get(linkRef), tx.get(ownerRef),
        tx.get(userRef), tx.get(tombRef), tx.get(pcRef),
      ]);
      const fromSnap = fromRef ? await tx.get(fromRef) : null;
      const fromTomb = fromTombRef ? await tx.get(fromTombRef) : null;

      // [§2.7 · B277-04] 역할 추가 KG 는 기존 계정 본인의 것이어야 한다 — 가장 먼저 본다.
      if (s.purpose === "add_role") {
        const fu0 = fromSnap ? dataOf(fromSnap) : undefined;
        if (!fu0 || fu0["identityKey"] !== ciKey) {
          throw E("permission-denied", "ADD_ROLE_IDENTITY_MISMATCH", "기존 계정 본인의 본인인증이 아닙니다.");
        }
      }
      const ident = dataOf(idSnap);
      const roles = asObj(ident?.["roles"]);
      const restriction = normalizeRestriction(ident?.["restriction"]);
      const rv = restrictionVerdict(restriction, nowMs);
      if (rv.kind === "BLACKLISTED") {
        throw E("permission-denied", "REREGISTER_BLACKLISTED", "이용 정책 위반으로 가입이 제한되었습니다.");
      }
      if (rv.kind === "COOLDOWN") {
        throw E("permission-denied", "REREGISTER_COOLDOWN", "탈퇴 후 30일이 지나야 다시 가입할 수 있습니다.",
          {canReregisterAtMs: rv.canReregisterAtMs});
      }
      const slot = asObj(roles[role]);
      if (roles[role]) {
        if (slot["state"] === "deleting") {
          throw E("failed-precondition", "IDENTITY_ROLE_DELETING", "같은 역할의 계정이 탈퇴 처리 중입니다.");
        }
        // [§2.6] 다른 카카오로 이미 가입 — 연결이 아니라 거부·안내. 세션은 종결.
        tx.update(sRef, {state: "blocked_existing", pass: null, cert: null, updatedAt: ts(nowMs)});
        const since = toMs(slot["since"]);
        const joinedMonth = since === null ? null :
          new Date(since + 9 * 3600e3).toISOString().slice(0, 7);
        return {kind: "blocked", reason: "IDENTITY_ROLE_TAKEN",
          details: {role, joinedMonth},
          notifyUid: typeof slot["uid"] === "string" ? slot["uid"] as string : undefined};
      }
      const ps = asObj(asObj(ident?.["providerSubjects"])[PROVIDER_KAKAO]);
      if (ident && ps["subject"] && (ps["subject"] !== subject || ps["appNs"] !== appNs)) {
        throw E("already-exists", "IDENTITY_PROVIDER_MISMATCH",
          "다른 카카오 계정으로 이미 가입되어 있습니다. 그 카카오로 로그인한 뒤 역할을 추가해 주세요.");
      }
      const sub = dataOf(subSnap);
      if (sub && s.purpose === "signup" && Object.keys(asObj(sub["roles"])).length > 0) {
        // 이미 역할이 연결된 카카오 — 새 역할은 로그인 뒤 '역할 추가'(기존 계정 상태 확인 포함)로만.
        throw E("failed-precondition", "ROLE_ADD_REQUIRED", "이미 가입된 카카오 계정입니다. 로그인한 뒤 역할을 추가해 주세요.");
      }
      if (sub && sub["identityKey"] !== ciKey) {
        throw E("permission-denied", "SUBJECT_IDENTITY_MISMATCH", "이 카카오 계정은 다른 본인확인 정보에 연결되어 있습니다.");
      }
      if (s.purpose === "add_role") {
        const fu = fromSnap ? dataOf(fromSnap) : undefined;
        if (!fu || fu["identityKey"] !== ciKey) {
          throw E("permission-denied", "ADD_ROLE_IDENTITY_MISMATCH", "기존 계정 본인의 본인인증이 아닙니다.");
        }
        const fv = accountStateVerdict(fu, !!fromTomb?.exists, nowMs);
        if (fv.kind !== "OK") {
          throw E("permission-denied", "ROLE_ADD_BLOCKED", "지금 계정 상태에서는 역할을 추가할 수 없습니다.", {verdict: fv.kind});
        }
        if (!sub) {
          throw E("permission-denied", "SUBJECT_IDENTITY_MISMATCH", "카카오 연결 정보를 확인할 수 없습니다.");
        }
      }
      if (linkSnap.exists || ownerSnap.exists || userSnap.exists || tombSnap.exists ||
          asObj(sub?.["roles"])[role]) {
        throw E("already-exists", "LINK_CONFLICT", "로그인 연결 정보가 충돌합니다. 고객센터로 문의해 주세요.");
      }
      const pc = dataOf(pcSnap);
      if (!pc || pc["sessionKey"] !== key || pc["generation"] !== s.generation ||
          pc["requestId"] !== s.pass["requestId"] || pc["ciKey"] !== ciKey) {
        throw E("permission-denied", "IMP_UID_BOUND_ELSEWHERE", "본인인증 결과를 확인할 수 없습니다. 다시 인증해 주세요.");
      }

      // ── 쓰기 ─────────────────────────────────────────────────────
      const termsConsent: Record<string, {agreed: boolean; version: string; revisionId: string; agreedAt: unknown}> = {};
      for (const [id, v] of Object.entries(s.consents ?? {})) {
        termsConsent[id] = {agreed: v["agreed"] === true, version: String(v["version"]),
          revisionId: String(v["revisionId"]), agreedAt: v["agreedAt"] ?? null};
      }
      const bd = s.pass["birthDate"] as string;
      const bdTs = /^\d{8}$/.test(bd) ?
        ts(Date.UTC(+bd.slice(0, 4), +bd.slice(4, 6) - 1, +bd.slice(6, 8))) : null;
      const userDoc = buildNewUserDoc({
        role, name: s.pass["name"] as string, phone: s.pass["phone"] as string,
        birthDate: bd, gender: (s.pass["gender"] as "남성" | "여성" | null) ?? null,
        identityKey: ciKey, evidence: s.pass["evidence"] === "mock" ? "mock" : "kg",
        termsConsent, serverNow: sv(), passVerifiedAt: s.pass["verifiedAt"],
        termsConsentAt: commitConsentAt, birthDateTs: bdTs,
      });
      const nextRoles = {...roles, [role]: {uid, state: "active", since: sv()}};
      const nextRestriction: Restriction = rv.kind === "OK" && restriction.state === "cooldown" ?
        {...restriction, state: "none"} : restriction;
      tx.set(idRef, {
        keyVersion: CI_KEY_VERSION,
        roles: nextRoles,
        restriction: restrictionForStore(nextRestriction),
        providerSubjects: {[PROVIDER_KAKAO]: {appNs, subject}},
        createdAt: ident?.["createdAt"] ?? sv(),
        updatedAt: sv(),
      });
      tx.set(subRef, {
        provider: PROVIDER_KAKAO, appNs, subject, identityKey: ciKey,
        roles: {...asObj(sub?.["roles"]), [role]: uid},
        createdAt: sub?.["createdAt"] ?? sv(), updatedAt: sv(),
      });
      tx.create(linkRef, {uid, identityKey: ciKey, provider: PROVIDER_KAKAO, appNs, subject, role,
        linkSource: s.purpose === "add_role" ? "add_role" : "signup", linkedAt: sv(), lastLoginAt: sv()});
      tx.create(ownerRef, {linkId: linkKey, provider: PROVIDER_KAKAO, appNs, subject, role});
      tx.create(userRef, userDoc);
      for (const [itemId, v] of Object.entries(s.consents ?? {})) {
        tx.create(userRef.collection("consentEvents").doc(), {
          itemId, revisionId: v["revisionId"], version: v["version"], agreed: v["agreed"],
          agreedAt: v["agreedAt"] ?? null, recordedAt: sv(),
          requiredAtConsentTime: v["requiredAtConsentTime"] === true,
          source: "signup_session",
        });
      }
      tx.update(pcRef, {outcomeRef: `users/${uid}`});
      tx.update(sRef, {state: "committed", reservedUid: uid,
        result: {uid, role, committedAt: sv()}, pass: null, cert: null, updatedAt: ts(nowMs)});
      return {kind: "committed", uid};
    });

    if (out.kind === "blocked") {
      if (out.notifyUid && d.notify) {
        d.notify(out.notifyUid, {
          userId: out.notifyUid, type: "signupAttemptExistingAccount",
          title: "가입 시도 안내",
          body: "회원님의 본인확인 정보로 다른 카카오 계정에서 가입을 시도했어요. 본인이 아니라면 고객센터로 알려 주세요.",
          data: {action: "none"}, isRead: false, createdAt: sv(), readAt: null,
        }).catch(() => undefined);
      }
      throw E("already-exists", out.reason,
        "이미 가입된 계정이 있어요. 처음 가입한 카카오 계정으로 로그인해 주세요.", out.details);
    }
    return withToken(out.uid, role);
  }

  async function withToken(uid: string, role: SignupRole): Promise<Doc> {
    try {
      const customToken = await ensureAuthAndToken(uid);
      return {status: "COMMITTED", uid, role, customToken, authPending: false};
    } catch (_e) {
      // 커밋은 유효하다 — FinalizeAuth 재호출 또는 카카오 재로그인으로 같은 UID.
      return {status: "COMMITTED", uid, role, authPending: true};
    }
  }

  async function finalizeAuth(req: CallReq): Promise<Doc> {
    const {key, secret} = parseSessionInput(req.data);
    const nowMs = d.now();
    const s = assertSecret(dataOf(await col(COL.sessions).doc(key).get()), secret, nowMs);
    if (s.state !== "committed" || !s.result) {
      throw E("failed-precondition", "SESSION_STATE", "가입이 아직 완료되지 않았습니다.");
    }
    const uid = s.result["uid"] as string;
    return {uid, role: s.result["role"], customToken: await ensureAuthAndToken(uid)};
  }

  // ════════════════════════════════════════════════════════════════════
  // 탈퇴 재확인(B277-06) — 작업·UID 결합 최근 증명
  // ════════════════════════════════════════════════════════════════════
  /** uid 의 새 신원 키 — users 문서 → 없으면 링크에서. */
  async function identityOf(uid: string): Promise<{identityKey: string; role: SignupRole;
    linkId: string; appNs: string; subject: string} | null> {
    const pl = await providerLinkOf(uid);
    if (!pl) return null;
    const ik = pl.link["identityKey"];
    const role = pl.link["role"];
    if (!isCiKeyV1(ik) || !isSignupRole(role)) return null;
    return {identityKey: ik, role, linkId: pl.linkId,
      appNs: String(pl.link["appNs"]), subject: String(pl.link["subject"])};
  }

  async function isProviderAccount(uid: string): Promise<boolean> {
    if (!isSafeIdPart(uid)) return false;
    const own = await col(COL.authLinkOwners).doc(authLinkOwnerId(uid, PROVIDER_KAKAO)).get();
    return own.exists;
  }

  async function deletionReauthStart(req: CallReq): Promise<Doc> {
    const uid = req.auth?.uid;
    if (!uid) throw E("unauthenticated", "LOGIN_REQUIRED", "로그인이 필요합니다.");
    if (!(await identityOf(uid))) {
      throw E("failed-precondition", "NOT_PROVIDER_ACCOUNT", "이 계정은 비밀번호로 본인을 다시 확인합니다.");
    }
    const ref = col(COL.proofs).doc(uid);
    return d.db.runTransaction(async (tx) => {
      const nowMs = d.now();
      const cur = dataOf(await tx.get(ref)) ?? {};
      const windowStart = toMs(cur["attemptWindowStart"]);
      const fresh = windowStart === null || nowMs - windowStart > DAY;
      const attempts = (fresh ? 0 : (cur["certAttempts"] as number | undefined) ?? 0) + 1;
      if (attempts > CERT_MAX_ATTEMPTS) {
        throw E("resource-exhausted", "CERT_ATTEMPTS_EXCEEDED", "본인확인 시도 횟수를 초과했습니다. 내일 다시 시도해 주세요.");
      }
      const requestId = "alfit_del_" + randomHex(12);
      tx.set(ref, {
        uid,
        cert: {requestId, purpose: "account_deletion", issuedAt: ts(nowMs), expiresAt: ts(nowMs + CERT_TTL_MS)},
        certAttempts: attempts,
        attemptWindowStart: fresh ? ts(nowMs) : cur["attemptWindowStart"],
        proof: cur["proof"] ?? null,
        updatedAt: ts(nowMs),
      });
      return {requestId, expiresAtMs: nowMs + CERT_TTL_MS};
    });
  }

  async function verifyPassDeletion(req: CallReq, keys: PassKeys): Promise<Doc> {
    const uid = req.auth?.uid;
    if (!uid) throw E("unauthenticated", "LOGIN_REQUIRED", "로그인이 필요합니다.");
    const c = cfg();
    const impUid = asObj(req.data)["imp_uid"];
    if (typeof impUid !== "string" || impUid.length < 1 || impUid.length > 128) {
      throw E("invalid-argument", "IMP_UID_REQUIRED", "본인인증 결과가 필요합니다.");
    }
    const who = await identityOf(uid);
    if (!who) throw E("failed-precondition", "NOT_PROVIDER_ACCOUNT", "이 계정은 비밀번호로 본인을 다시 확인합니다.");
    const ref = col(COL.proofs).doc(uid);
    const cur0 = dataOf(await ref.get());
    const cert0 = cur0?.["cert"] as Doc | null | undefined;
    if (!cert0) throw E("failed-precondition", "DELETION_REAUTH_NOT_STARTED", "본인확인을 다시 시작해 주세요.");
    if (d.now() >= (toMs(cert0["expiresAt"]) ?? 0)) {
      throw E("deadline-exceeded", "CERT_EXPIRED", "본인확인 시간이 지났습니다. 다시 시작해 주세요.");
    }
    const impHash = sha256Hex(impUid);
    const pcRef = col(COL.passCerts).doc(impHash);
    const binding = {sessionKey: deletionSessionKey(uid), generation: 0, requestId: cert0["requestId"] as string};
    if ((await pcRef.get()).exists) {
      throw E("permission-denied", "IMP_UID_BOUND_ELSEWHERE", "이미 사용된 본인인증 결과입니다. 다시 인증해 주세요.");
    }
    if (!keys.ciHmacKey || keys.ciHmacKey.length < 16) {
      throw E("internal", "CI_KEY_UNAVAILABLE", "본인확인 처리 설정이 없습니다.");
    }
    const kg = await readKg(impUid, keys, c, cert0);
    const ciKey = ciKeyOf(keys, kg.ci);
    if (ciKey !== who.identityKey) {
      throw E("permission-denied", "IDENTITY_MISMATCH", "계정 본인의 본인인증이 아닙니다.");
    }
    return d.db.runTransaction(async (tx) => {
      const nowMs = d.now();
      const cur = dataOf(await tx.get(ref));
      const pc = await tx.get(pcRef);
      const cert = cur?.["cert"] as Doc | null | undefined;
      if (pc.exists) {
        throw E("permission-denied", "IMP_UID_BOUND_ELSEWHERE", "이미 사용된 본인인증 결과입니다. 다시 인증해 주세요.");
      }
      if (!cert || cert["requestId"] !== binding.requestId || cert["purpose"] !== "account_deletion") {
        throw E("failed-precondition", "DELETION_REAUTH_NOT_STARTED", "본인확인을 다시 시작해 주세요.");
      }
      // [판정281 C281-02] 외부 조회 전 검사로 끝내지 않는다 — **이 거래 시도 시각**에 cert 가 유효해야
      //   소비(passCertifications)·proof 발급을 한다. 만료면 아무것도 쓰지 않고 다시 시작하게 한다.
      if (nowMs >= (toMs(cert["expiresAt"]) ?? 0)) {
        throw E("deadline-exceeded", "CERT_EXPIRED", "본인확인 시간이 지났습니다. 다시 시작해 주세요.");
      }
      tx.create(pcRef, {...binding, purpose: "account_deletion", role: who.role, ciKey,
        evidence: kg.evidence, pgCheck: kg.pgCheck, consumedAt: sv(), outcomeRef: `deletionReauthProofs/${uid}`});
      tx.update(ref, {
        cert: null,
        proof: {ciKey, requestId: binding.requestId, provenAt: sv(),
          expiresAt: ts(nowMs + DELETION_PROOF_TTL_MS), evidence: kg.evidence},
        updatedAt: ts(nowMs),
      });
      return {proven: true, expiresAtMs: nowMs + DELETION_PROOF_TTL_MS};
    });
  }

  /**
   * 카카오 계정의 탈퇴 precondition. auth_time 만으로 통과시키지 않는다.
   * 비밀번호(옛 QA) 계정이면 false 를 돌려 호출자가 기존 auth_time 검사를 한다.
   */
  async function assertDeletionProofIfProvider(uid: string): Promise<boolean> {
    const who = await identityOf(uid);
    if (!who) {
      if (await isProviderAccount(uid)) {
        throw E("failed-precondition", "DELETION_REAUTH_REQUIRED", "본인확인을 다시 진행해 주세요.");
      }
      return false;
    }
    const proof = asObj(dataOf(await col(COL.proofs).doc(uid).get())?.["proof"]);
    const exp = toMs(proof["expiresAt"]);
    if (proof["ciKey"] !== who.identityKey || exp === null || d.now() >= exp) {
      throw E("failed-precondition", "DELETION_REAUTH_REQUIRED",
        "탈퇴하려면 본인확인을 다시 진행해 주세요(10분 안에 완료).");
    }
    return true;
  }

  /**
   * 탈퇴 freeze 거래 안에서 identity 역할 슬롯을 'deleting' 으로 — 가입 tx 가
   * 이 슬롯을 점유로 본다(탈퇴↔가입 경합 차단). reads 만 여기서 하고 apply 로 쓴다.
   */
  async function freezeIdentityReadInTx(tx: Transaction, uid: string, u: Doc | undefined):
    Promise<((tx2: Transaction) => void) | null> {
    if (!u || !isNewCohortUser(u)) return null;
    const ik = u["identityKey"];
    const role = u["role"];
    if (!isCiKeyV1(ik) || !isSignupRole(role)) return null;
    const ref = col(COL.identities).doc(ik);
    const ident = dataOf(await tx.get(ref));
    const roles = asObj(ident?.["roles"]);
    const slot = asObj(roles[role]);
    if (!ident || slot["uid"] !== uid || slot["state"] === "deleting") return null;
    const nowMs = d.now();
    return (tx2: Transaction) => {
      tx2.update(ref, {
        [`roles.${role}.state`]: "deleting",
        [`roles.${role}.deletingSince`]: ts(nowMs),
        [`roles.${role}.blacklistedAtFreeze`]: u["isBlacklisted"] === true,
        updatedAt: sv(),
      });
    };
  }

  /**
   * Final: 새 identity 상태 정리. **제한 기록과 슬롯 해제가 같은 거래**다(판정278 §2).
   * 링크(authLinks/authLinkOwners)와 proof 는 Auth 삭제 뒤에 지운다 — 그 전까지는
   * 문서 없는 deleting 계정의 카카오 로그인 → 삭제 재개 열쇠다.
   */
  async function cleanupNewIdentityState(uid: string): Promise<{applicable: boolean; failed: number}> {
    const who = await identityOf(uid);
    if (!who) return {applicable: await isProviderAccount(uid), failed: (await isProviderAccount(uid)) ? 1 : 0};
    let failed = 0;
    try {
      await d.db.runTransaction(async (tx) => {
        const nowMs = d.now();
        const idRef = col(COL.identities).doc(who.identityKey);
        const subRef = col(COL.authSubjects).doc(providerSubjectKey(PROVIDER_KAKAO, who.appNs, who.subject));
        const [idSnap, subSnap, uSnap] = await Promise.all([
          tx.get(idRef), tx.get(subRef), tx.get(col(COL.users).doc(uid)),
        ]);
        const ident = dataOf(idSnap);
        const u = dataOf(uSnap);
        if (ident) {
          const roles = {...asObj(ident["roles"])};
          const slot = asObj(roles[who.role]);
          if (slot["uid"] === uid) {
            const prev = normalizeRestriction(ident["restriction"]);
            const next = restrictionAfterDeletion(prev, {
              uid,
              wasBlacklisted: u?.["isBlacklisted"] === true || slot["blacklistedAtFreeze"] === true,
              baseMs: toMs(slot["deletingSince"]) ?? nowMs,
              nowMs,
            });
            delete roles[who.role];
            const rest: Doc = {...ident, roles, restriction: restrictionForStore(next), updatedAt: sv()};
            if (Object.keys(roles).length === 0) rest["providerSubjects"] = {};
            tx.set(idRef, rest);
          }
        }
        const sub = dataOf(subSnap);
        if (sub) {
          const sr = {...asObj(sub["roles"])};
          if (sr[who.role] === uid) {
            delete sr[who.role];
            if (Object.keys(sr).length === 0) tx.delete(subRef);
            else tx.set(subRef, {...sub, roles: sr, updatedAt: sv()});
          }
        }
      });
    } catch (_e) {
      failed++;
    }
    try {
      const sRef = col(COL.sessions).doc(providerSubjectKey(PROVIDER_KAKAO, who.appNs, who.subject));
      const s = dataOf(await sRef.get());
      if (s && (asObj(s["result"])["uid"] === uid || s["fromUid"] === uid || s["reservedUid"] === uid)) {
        await sRef.delete();
      }
    } catch (_e) {
      failed++;
    }
    return {applicable: true, failed};
  }

  /** 잔존 계수 — 0 이 **확인**되기 전에는 Auth 를 지우지 않는다. */
  async function countNewIdentityResidual(uid: string): Promise<{applicable: boolean; residual: number; unknown: boolean}> {
    try {
      const who = await identityOf(uid);
      if (!who) {
        const prov = await isProviderAccount(uid);
        return {applicable: prov, residual: 0, unknown: prov};
      }
      let n = 0;
      const [idSnap, subSnap, sSnap] = await Promise.all([
        col(COL.identities).doc(who.identityKey).get(),
        col(COL.authSubjects).doc(providerSubjectKey(PROVIDER_KAKAO, who.appNs, who.subject)).get(),
        col(COL.sessions).doc(providerSubjectKey(PROVIDER_KAKAO, who.appNs, who.subject)).get(),
      ]);
      if (asObj(asObj(dataOf(idSnap)?.["roles"])[who.role])["uid"] === uid) n++;
      if (asObj(dataOf(subSnap)?.["roles"])[who.role] === uid) n++;
      const s = dataOf(sSnap);
      if (s && (asObj(s["result"])["uid"] === uid || s["fromUid"] === uid || s["reservedUid"] === uid)) n++;
      return {applicable: true, residual: n, unknown: false};
    } catch (_e) {
      return {applicable: true, residual: -1, unknown: true};
    }
  }

  /** Auth 삭제가 확인된 뒤 — 링크·proof 정리(best-effort, 남으면 로그인 경로가 정리). */
  async function cleanupAfterAuthDeleted(uid: string): Promise<void> {
    const who = await identityOf(uid);
    await cleanupDeletedLinksForUid(uid, who ? [who.linkId] : []);
  }

  /**
   * 블랙 등록·해제가 identity 제한에 즉시 반영되게 — 호출자 거래 안에서 읽고 쓴다.
   * @return {Promise<((tx: Transaction) => void) | null>} 쓰기 적용 함수(대상 아님이면 null)
   */
  async function blacklistReadInTx(tx: Transaction, uid: string, u: Doc | undefined,
    mode: "add" | "remove"): Promise<((tx2: Transaction) => void) | null> {
    if (!u || !isNewCohortUser(u) || !isCiKeyV1(u["identityKey"])) return null;
    const ref = col(COL.identities).doc(u["identityKey"] as string);
    const ident = dataOf(await tx.get(ref));
    if (!ident) return null;
    const nowMs = d.now();
    const prev = normalizeRestriction(ident["restriction"]);
    const next = mode === "add" ? restrictionAfterBlacklist(prev, uid, nowMs) :
      restrictionAfterUnblacklist(prev, uid, nowMs);
    return (tx2: Transaction) => {
      tx2.update(ref, {restriction: restrictionForStore(next), updatedAt: sv()});
    };
  }

  return {
    authKakao, sessionGet, sessionSetPurpose, sessionConsent, sessionPrepareCertification,
    sessionCancel, sessionStartAddRole, verifyPassSignup, completeSignup, finalizeAuth,
    deletionReauthStart, verifyPassDeletion,
    // 탈퇴·블랙 통합(index.ts 가 기존 흐름 안에서 부른다)
    isProviderAccount, assertDeletionProofIfProvider, freezeIdentityReadInTx,
    cleanupDeletedLinksForUid, providerUnlinkScope,
    cleanupNewIdentityState, countNewIdentityResidual, cleanupAfterAuthDeleted,
    blacklistReadInTx, identityOf,
    // 시험·내부
    ensureAuthAndToken,
  };
}

export type AuthKakaoService = ReturnType<typeof createAuthKakao>;
