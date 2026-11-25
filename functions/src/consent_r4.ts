/**
 * [CONSENT-R4b] 서류 열람 동의 새 세대(일반 v4 · 초대 invite-v2) — 순수 판정 모듈.
 *
 *   후보(DRAFT)다. A 에 반영되지 않았고 실행·발급하지 않았다.
 *   Firestore·admin SDK 를 import 하지 않는다 — 문서 데이터와 시각(ms)을 주입받는다.
 *   판본 문자열은 여기 두지 않는다(단일 소유자 = index.ts 상수).
 *
 *   r4 대비(r4 감사 C-R4-2·C-R4-3 · 대표 답 A1–A4 · 질문1 확인 답 '응' · 후속 six_answers §2)
 *     · 승계 계보를 출처(documentAccessConsentSource)와 **양방향**으로 본다.
 *     · 근태·보완·계약 집합의 잘림을 입력으로 받고 각각 드러낸다.
 *     · A1 — 지원서 종료일이 **결손**인 장기에서 현재 근무가 **별도로** 확인되는 예외만
 *       (N-EP2 #4 · two_answers 판정 §2). 같은 관계의 서명 완료 계약 기간이 오늘을 포함해야 한다
 *       (cr4CurrentWork · 확인 방법 = Claude 기술 후보 · Codex 판정 요청). NO_END·클라이언트 값·시작일
 *       형식만으로 열지 않고, 미시작 근무에는 새 열람을 만들지 않는다. 현재/미시작/종료/근거불명을 나눈다.
 *     · A2(종료·지급 이력 없음) · A3(확인된 미결+지급 기록 불명 / 불명만) · A4(지급 종결 뒤
 *       계좌서류 보완만)는 **아직 줄 급여가 있어도** 마지막 근무 기준 **유한 30일**(L30).
 *       그 밖(일반 순수 미결 · 보완 없는 지급 종결 · 선지급 T_ONLY)은 기존 '마지막 급여 지급 후 30일'
 *       규칙(T30 · 지급 전 미결은 아직 기산하지 않음) = **확정**(대표 답 '응' · two_answers 판정 §2).
 *       min/max/OR 합성 0 · 검증된 사례 분류가 규칙을 정한다. r4b 앞판의 CLOSED/OPEN_UNCAPPED/
 *       UNDECIDED 스위치는 없앴다(이력: history/consent_r4.ts.pre-answer1.ff217dde.ts).
 *     · L30 의 날짜 경계 = KST(L) 0시 + 30×24h 배타 — **채택(PP-DELEGATION-20261118 · 위임 Codex 결정)**.
 *       (아래 두 줄은 채택 전 이력이다.) 'L+30일 말일까지'
 *       (하루 더 긴 식)는 대안 값으로만 둔다 — 대표가 수식을 말하지 않았다. Codex 판정 대상.
 *     · 반환 = 상태 · 허용 · 기산 종류(L/T/현재근무) · L · T · 현재근무 근거 · 닫히는 시각 ·
 *       재판정 시각 · 불명 사유 · 집합 완전성. 기존 권한·관계·목적·동의 gate 와 **AND** 로만 쓴다.
 *     · 서명 직전 재판정(cr4SignableExpiryMs).
 *     · 초대 수락 보존 판정은 index.ts 로 옮겼다(동의 전용 writer 와 같은 함수 하나).
 */

const KST_MS = 9 * 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;

/** 확정자 통장사본·계좌 열람 상한 — 30×24h. */
export const CR4_BANK_WINDOW_MS = 30 * DAY_MS;
/** 서명 URL 기본 수명(기존 1시간). */
export const CR4_URL_TTL_MS = 60 * 60 * 1000;
/** 근태 조회 상한 — 닿으면 잘렸을 수 있으므로 증거 불명. */
export const CR4_ATTENDANCE_QUERY_LIMIT = 1000;
/** 열린 보완 조회 상한 — 닿으면 잘렸을 수 있으므로 증거 불명. */
export const CR4_CORRECTION_QUERY_LIMIT = 200;
/** 계약 조회 상한(applicationId 한 갈래 · applicationIds 한 갈래 각각) — 닿으면 근거 불명. */
export const CR4_CONTRACT_QUERY_LIMIT = 20;

const CR4_CORRECTION_LIVE = ["OPEN", "RESUBMITTED"];
const CR4_ENDED_DECISIONS = ["APPROVED", "AUTO_APPROVED"];
/** index.ts DOC_TYPE_ID / DOC_TYPE_BANKBOOK(:1621–1622)와 같은 값. */
const CR4_DOC_TYPE_ID = "ID";
const CR4_DOC_TYPE_BANKBOOK = "BANKBOOK";

type Doc = Record<string, unknown>;

/**
 * Firestore Timestamp 처럼 `toMillis()` 를 가진 값만 받는다.
 *
 * @param {unknown} v 저장값
 * @return {number | null} 유한 ms
 */
export function cr4ValidTsMs(v: unknown): number | null {
  if (v === null || typeof v !== "object") return null;
  const f = (v as {toMillis?: unknown}).toMillis;
  if (typeof f !== "function") return null;
  let ms: unknown;
  try {
    ms = (f as () => unknown).call(v);
  } catch {
    return null;
  }
  return typeof ms === "number" && Number.isFinite(ms) ? ms : null;
}

/**
 * KST 날짜 0시(ms).
 *
 * @param {number} ms 시각
 * @return {number} KST 자정
 */
export function cr4KstMidnightMs(ms: number): number {
  return Math.floor((ms + KST_MS) / DAY_MS) * DAY_MS - KST_MS;
}

export type Cr4LastWorkDay =
  | {kind: "KNOWN"; ms: number; field: string}
  | {kind: "NO_END"}
  | {kind: "MALFORMED"; field: string}
  | {kind: "MISSING"; field: string};

/**
 * 마지막 근무일 L(index.ts srvIdWindowLastWorkDay 의 선택 순서 + 형식 검증).
 *
 * @param {Doc} app 지원서
 * @return {Cr4LastWorkDay} 판정
 */
export function cr4LastWorkDay(app: Doc): Cr4LastWorkDay {
  const pick = (k: string): Cr4LastWorkDay | null => {
    const raw = app[k];
    if (raw === undefined || raw === null) return null;
    const ms = cr4ValidTsMs(raw);
    return ms === null ? {kind: "MALFORMED", field: k} : {kind: "KNOWN", ms, field: k};
  };
  const resign = pick("actualResignDate");
  if (resign) return resign;
  const t = app["type"];
  if (t === "short" || t === "flex") {
    return pick("workDate") ?? {kind: "MISSING", field: "workDate"};
  }
  if (t === "long_term" || t === "contract") {
    return pick("workEndDate") ?? {kind: "NO_END"};
  }
  const w = pick("workDate");
  const we = pick("workEndDate");
  if (w && w.kind === "MALFORMED") return w;
  if (we && we.kind === "MALFORMED") return we;
  const wd = app["workDays"];
  if (w && w.kind === "KNOWN" && we && we.kind === "KNOWN" &&
      Array.isArray(wd) && wd.length > 0 &&
      cr4KstMidnightMs(we.ms) !== cr4KstMidnightMs(w.ms)) {
    return we;
  }
  return w ?? {kind: "MISSING", field: "workDate"};
}

/**
 * 'yyyy-MM-dd' → 그 KST 날짜 0시(ms). 형식·실재 날짜가 아니면 null.
 *
 * @param {unknown} s 계약 스냅샷 날짜 문자열
 * @return {number | null} KST 0시
 */
export function cr4KstYmdMs(s: unknown): number | null {
  if (typeof s !== "string") return null;
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  if (!m) return null;
  const y = Number(m[1]);
  const mo = Number(m[2]);
  const d = Number(m[3]);
  const utc = Date.UTC(y, mo - 1, d);
  const back = new Date(utc);
  if (back.getUTCFullYear() !== y || back.getUTCMonth() !== mo - 1 || back.getUTCDate() !== d) {
    return null;
  }
  return utc - KST_MS;
}

export type Cr4StartDay =
  | {kind: "KNOWN"; ms: number; field: string}
  | {kind: "MALFORMED"; field: string}
  | {kind: "MISSING"};

/**
 * 장기 약속의 효력 시작일(KST 0시) — A/functions/src/commitment_dates.ts
 * `longTermEffectiveStartNum`(:99–115)과 같은 식에 **형식 검증**을 더했다:
 *   desiredStartDate ?? workDate, 희망일이 없을 때만 confirmedAt(KST 일)로 한 번 더 민다.
 *   기존 helper 는 날짜를 모르면 0(=언제나 시작 이후)을 돌려준다 — 여기서는 MISSING 으로 드러낸다.
 *
 * @param {Doc} app 지원서
 * @return {Cr4StartDay} 판정
 */
export function cr4StartDay(app: Doc): Cr4StartDay {
  const has = (k: string) => app[k] !== undefined && app[k] !== null;
  const field = has("desiredStartDate") ? "desiredStartDate" : has("workDate") ? "workDate" : null;
  if (field === null) return {kind: "MISSING"};
  const ms = cr4ValidTsMs(app[field]);
  if (ms === null) return {kind: "MALFORMED", field};
  let start = cr4KstMidnightMs(ms);
  if (field !== "desiredStartDate") {
    const c = cr4ValidTsMs(app["confirmedAt"]);
    if (c !== null && cr4KstMidnightMs(c) > start) start = cr4KstMidnightMs(c);
  }
  return {kind: "KNOWN", ms: start, field};
}

export type Cr4CurrentWorkState = "CURRENT" | "NOT_STARTED" | "ENDED" | "UNKNOWN";

export interface Cr4CurrentWork {
  state: Cr4CurrentWorkState;
  /** 확인 출처 — CURRENT 에서만 값이 있다. */
  source: "SIGNED_CONTRACT_IN_FORCE" | null;
  /** 근거 계약 id(CURRENT) 또는 종료 근거 계약 id(ENDED · 계약 사유). */
  contractId: string | null;
  /** 효력 시작(KST 0시). */
  effectiveStartMs: number | null;
  /** 근거 계약의 근로자 서명 시각. */
  workerSignedAtMs: number | null;
  /** 근거 계약 기간의 마지막 날 KST 0시(CURRENT) — 그 다음 날 0시에 다시 판정한다. L 로 쓰지 않는다. */
  contractPeriodEndMs: number | null;
  reasons: string[];
}

export interface Cr4CurrentWorkInput {
  app: Doc;
  applicationId: string;
  /** employment_contracts — applicationId == X 또는 applicationIds array-contains X 로 읽은 행. */
  contracts: ReadonlyArray<Doc & {id: string}> | null;
  contractSetComplete: boolean;
  /** businesses/{app.businessId} 문서(deactivatedAt). 없으면 null. */
  business: Doc | null;
  nowMs: number;
}

/**
 * [A1 · 결손 데이터 예외(N-EP2 #4 · 후속 two_answers §2)] 지원서 종료일이 **결손**인 장기 관계에서
 *   현재 근무가 **별도로** 확인되는가. 정상 NO_END 상품은 없다(N-EP2 #4) — 종료일 없음만으로,
 *   또는 미시작 근무에 새 열람을 만들지 않는다.
 *
 *   확인 방법은 Claude 기술 후보다(Codex 판정 요청). A 에 '지금 일하고 있음'을 직접 쓰는 writer 는
 *   없다 — 종료일 없는 장기는 출근 자체가 막힌다(A/functions/src/index.ts:41573–41581 · :454–455 ·
 *   commitment_dates.ts:161–163). 그래서 독립 근거를 **같은 관계의 서명 완료 근로계약 기간**에서 찾는다:
 *     ① 종료 전이 없음 — 퇴사/해지 승인(index.ts:57299 CONTRACT_ENDED_STATUSES 와 같은 값) ·
 *        좌석 반납(staffingReleasedAt · :57413) · 사업장 운영 종료(deactivatedAt · :41589–41594)
 *     ② 지원서 효력 시작일이 지났다(cr4StartDay) — 아니면 NOT_STARTED(새 열람 근거 아님)
 *     ③ 같은 지원서·근로자·사업장에 묶인 양측 서명 완료 계약(출근 gate srvContractConsentState
 *        :41426–41462 와 같은 연결·서명 조건)의 스냅샷 기간이 **오늘을 포함**한다
 *        (contractStart ≤ 오늘 ≤ contractEnd · 'yyyy-MM-dd' KST · **양 경계 필수** · 역전은 불명).
 *        계약에 시작·종료 중 하나라도 없으면 근거가 아니다(정상 NO_END 없음 · r4c F-R4B-1).
 *        = PP-R4B-A1(대표 위임 Codex 결정) — 운영상 증거이지 오늘 근태 관측·출근 허용이 아니다. 계약 종료일은 **L 로 쓰지 않는다** — 다음 날 0시에 다시 판정할 뿐이다.
 *   클라이언트 true · 종료일 결손 · 과거 출근 1건 · 시작일 형식만으로 CURRENT 를 만들지 않는다.
 *   이 근거로 '실제로 오늘 일한다'를 관측하지는 못한다 — 부족하면 별도 최소 writer 후보
 *   (r4b_policy_A1_A4.md §2.3)를 Codex 가 판정한다.
 *
 * @param {Cr4CurrentWorkInput} input 입력
 * @return {Cr4CurrentWork} 판정
 */
export function cr4CurrentWork(input: Cr4CurrentWorkInput): Cr4CurrentWork {
  const {app, applicationId, nowMs} = input;
  const reasons: string[] = [];
  const res = (state: Cr4CurrentWorkState, extra: Partial<Cr4CurrentWork> = {}): Cr4CurrentWork => ({
    state, source: null, contractId: null, effectiveStartMs: null, workerSignedAtMs: null,
    contractPeriodEndMs: null, reasons, ...extra,
  });
  const has = (k: string) => app[k] !== undefined && app[k] !== null;
  const t = app["type"];
  if (t !== "long_term" && t !== "contract") {
    reasons.push("NOT_LONG_TERM");
    return res("UNKNOWN");
  }
  // 호출 전제 방어 — 호출부가 이미 CONFIRMED 를 확인하고, NO_END 일 때만 부른다.
  if (app["status"] !== "CONFIRMED") {
    reasons.push("STATUS_NOT_CONFIRMED");
    return res("UNKNOWN");
  }
  if (has("workEndDate") || has("actualResignDate")) {
    reasons.push("HAS_END_DATE_NOT_NO_END");
    return res("UNKNOWN");
  }
  // ① 종료 전이(날짜 없이 결정만 있는 경우 — 정상 writer 는 actualResignDate 를 함께 쓴다 :10087 · :31335).
  if (CR4_ENDED_DECISIONS.includes(app["resignStatus"] as string)) {
    reasons.push("RESIGN_APPROVED_WITHOUT_DATE");
    return res("ENDED");
  }
  if (CR4_ENDED_DECISIONS.includes(app["terminationStatus"] as string)) {
    reasons.push("TERMINATION_APPROVED_WITHOUT_DATE");
    return res("ENDED");
  }
  if (has("staffingReleasedAt")) {
    reasons.push("SEAT_RELEASED");
    return res("ENDED");
  }
  const todayMs = cr4KstMidnightMs(nowMs);
  if (input.business === null) {
    reasons.push("BUSINESS_MISSING");
    return res("UNKNOWN");
  }
  const deact = input.business["deactivatedAt"];
  if (deact !== undefined && deact !== null) {
    const dm = cr4ValidTsMs(deact);
    if (dm === null) {
      reasons.push("BUSINESS_DEACTIVATED_AT_MALFORMED");
      return res("UNKNOWN");
    }
    if (cr4KstMidnightMs(dm) <= todayMs) {
      reasons.push("BUSINESS_CLOSED");
      return res("ENDED");
    }
  }
  // ② 효력 시작.
  const sd = cr4StartDay(app);
  if (sd.kind === "MISSING") {
    reasons.push("START_MISSING");
    return res("UNKNOWN");
  }
  if (sd.kind === "MALFORMED") {
    reasons.push(`START_MALFORMED_${sd.field}`);
    return res("UNKNOWN");
  }
  if (todayMs < sd.ms) {
    reasons.push("BEFORE_EFFECTIVE_START");
    return res("NOT_STARTED", {effectiveStartMs: sd.ms});
  }
  // ③ 서명 완료 계약.
  if (input.contracts === null) {
    reasons.push("CONTRACTS_NOT_READ");
    return res("UNKNOWN", {effectiveStartMs: sd.ms});
  }
  if (!input.contractSetComplete) {
    reasons.push("CONTRACT_SET_TRUNCATED");
    return res("UNKNOWN", {effectiveStartMs: sd.ms});
  }
  const seen = new Set<string>();
  let best: {id: string; signedMs: number; endMs: number} | null = null;
  let endedBy: string | null = null;
  let notStartedBy: {id: string; startMs: number} | null = null;
  let blocking = false;
  let expired = false;
  for (const c of input.contracts) {
    if (seen.has(c.id)) continue;
    seen.add(c.id);
    const ids = Array.isArray(c["applicationIds"]) ? (c["applicationIds"] as unknown[]) : [];
    if (c["applicationId"] !== applicationId && !ids.includes(applicationId)) {
      reasons.push(`CONTRACT_${c.id}_NOT_LINKED`);
      continue;
    }
    if (c["workerId"] !== app["uid"] || c["businessId"] !== app["businessId"]) {
      // 다른 사람·다른 사업장 계약이 이 지원서를 가리킨다 — 관계 무결성 결손(완화 0).
      reasons.push(`CONTRACT_${c.id}_FOREIGN_ROW`);
      return res("UNKNOWN", {effectiveStartMs: sd.ms});
    }
    const st = c["status"];
    if (st === "completed") {
      const em = cr4ValidTsMs(c["employerSignedAt"]);
      const wm = cr4ValidTsMs(c["workerSignedAt"]);
      if (em === null || wm === null) {
        reasons.push(`CONTRACT_${c.id}_SIGNATURE_TIME_INVALID`);
        continue;
      }
      if (em > nowMs || wm > nowMs) {
        reasons.push(`CONTRACT_${c.id}_SIGNATURE_TIME_FUTURE`);
        blocking = true;
        continue;
      }
      const snap = c["snapshot"];
      const sv = (k: string): unknown => snap !== null && typeof snap === "object" ?
        (snap as Doc)[k] : undefined;
      const blank = (v: unknown) => v === undefined || v === null || v === "";
      // [r4d · F-R4C-1 · PP-R4C-A1-BOUNDS] 양 날짜의 **필수 · 형식 · 순서**를 종료일 비교보다 먼저 본다.
      //   결손(undefined·null·빈값) = 근거 아님 · 형식오류·역전 = 불명(blocking) — 그 뒤에만 종료/미시작/현재.
      //   (r4c 는 종료일이 지난 계약을 시작 검증 전에 ENDED 로 넘겨 역전·형식오류가 숨었다.)
      const endRaw = sv("contractEnd");
      const startRaw = sv("contractStart");
      if (blank(endRaw)) {
        // 계약에도 끝이 없다 — 정상 NO_END 사례는 없다(N-EP2 #4) · 장기 snapshot end=null 경로 실재
        //   (A lib/services/contract_service.dart:1391–1397). 현재 근무의 독립 근거가 아니다.
        reasons.push(`CONTRACT_${c.id}_END_MISSING_NOT_EVIDENCE`);
        continue;
      }
      if (blank(startRaw)) {
        reasons.push(`CONTRACT_${c.id}_START_MISSING_NOT_EVIDENCE`);
        continue;
      }
      const endMs = cr4KstYmdMs(endRaw);
      const cs = cr4KstYmdMs(startRaw);
      if (endMs === null) {
        reasons.push(`CONTRACT_${c.id}_END_MALFORMED`);
        blocking = true;
        continue;
      }
      if (cs === null) {
        reasons.push(`CONTRACT_${c.id}_START_MALFORMED`);
        blocking = true;
        continue;
      }
      if (cs > endMs) {
        // 시작 > 끝(역전) — 종료일이 지났더라도 어긋난 계약 자료로 열지도 닫지도 않는다(불명).
        reasons.push(`CONTRACT_${c.id}_RANGE_REVERSED`);
        blocking = true;
        continue;
      }
      if (endMs < todayMs) {
        reasons.push(`CONTRACT_${c.id}_PERIOD_ENDED`);
        endedBy = endedBy ?? c.id;
        continue;
      }
      if (cs > todayMs) {
        reasons.push(`CONTRACT_${c.id}_NOT_STARTED`);
        if (notStartedBy === null || cs < notStartedBy.startMs) notStartedBy = {id: c.id, startMs: cs};
        continue;
      }
      if (best === null || wm > best.signedMs) best = {id: c.id, signedMs: wm, endMs};
      continue;
    }
    if (st === "expired") {
      expired = true;
      reasons.push(`CONTRACT_${c.id}_EXPIRED`);
      continue;
    }
    reasons.push(`CONTRACT_${c.id}_STATUS_${typeof st === "string" ? st : "INVALID"}_NOT_EVIDENCE`);
  }
  if (blocking) return res("UNKNOWN", {effectiveStartMs: sd.ms});
  if (best !== null) {
    reasons.push("SIGNED_CONTRACT_PERIOD_COVERS_TODAY");
    return res("CURRENT", {
      source: "SIGNED_CONTRACT_IN_FORCE", contractId: best.id,
      effectiveStartMs: sd.ms, workerSignedAtMs: best.signedMs, contractPeriodEndMs: best.endMs,
    });
  }
  if (notStartedBy !== null) {
    return res("NOT_STARTED", {contractId: notStartedBy.id, effectiveStartMs: notStartedBy.startMs});
  }
  if (endedBy !== null) return res("ENDED", {contractId: endedBy, effectiveStartMs: sd.ms});
  if (expired) return res("ENDED", {effectiveStartMs: sd.ms});
  reasons.push("NO_SIGNED_CONTRACT_COVERING_TODAY");
  return res("UNKNOWN", {effectiveStartMs: sd.ms});
}

export type Cr4AttClass = "PAID" | "NONPAYABLE_ZERO" | "ZERO_PAID" | "OPEN" | "UNKNOWN";

/**
 * 근태 한 건의 배타 5분류(r4 와 같다).
 *
 * @param {Doc} a 근태
 * @param {Doc} app 지원서
 * @param {number} nowMs 판정 시각
 * @return {object} 분류
 */
export function cr4ClassifyAttendance(
  a: Doc, app: Doc, nowMs: number
): {cls: Cr4AttClass; reason: string; transferMs: number | null} {
  if (a["businessId"] !== app["businessId"] || a["userId"] !== app["uid"]) {
    return {cls: "UNKNOWN", reason: "FOREIGN_ROW", transferMs: null};
  }
  const ws = a["wageStatus"];
  const st = a["status"];
  const fw = a["finalWage"];
  const nonPayable = (st === "NO_SHOW" || st === "absent") && ((fw ?? 0) === 0);
  const locked = a["activeInterimSettlementId"] !== undefined &&
    a["activeInterimSettlementId"] !== null && a["activeInterimSettlementId"] !== "";
  if (ws === "transferred") {
    const ms = cr4ValidTsMs(a["transferDate"]);
    if (ms === null) return {cls: "UNKNOWN", reason: "TRANSFER_DATE_INVALID", transferMs: null};
    if (ms > nowMs) return {cls: "UNKNOWN", reason: "TRANSFER_DATE_FUTURE", transferMs: null};
    if (locked) return {cls: "UNKNOWN", reason: "TRANSFERRED_LOCKED", transferMs: null};
    if (nonPayable) return {cls: "UNKNOWN", reason: "TRANSFERRED_NONPAYABLE", transferMs: null};
    if (typeof fw === "number" && Number.isFinite(fw) && fw > 0) {
      return {cls: "PAID", reason: "TRANSFERRED", transferMs: ms};
    }
    if (fw === 0) return {cls: "ZERO_PAID", reason: "TRANSFERRED_ZERO", transferMs: ms};
    return {cls: "UNKNOWN", reason: "FINAL_WAGE_INVALID", transferMs: null};
  }
  if (ws === "confirmed") {
    if (nonPayable && !locked) {
      return {cls: "NONPAYABLE_ZERO", reason: "NONPAYABLE_ZERO", transferMs: null};
    }
    return {cls: "OPEN", reason: locked ? "SETTLEMENT_LOCK" : "CONFIRMED_UNPAID", transferMs: null};
  }
  if (ws === "pending" || ws === "calculated") {
    return {cls: "OPEN", reason: String(ws).toUpperCase(), transferMs: null};
  }
  return {cls: "UNKNOWN", reason: "WAGE_STATUS_UNKNOWN", transferMs: null};
}

/**
 * 정책 — 질문1 확정(A2–A4 = L30 · 그 밖 = T30 · two_answers 판정 §2) 뒤에 남은 기술 선택만 둔다.
 *   r4b 앞판의 noPayment/unknownEvidence/mixedPendingUnknown/settledWithOpenCorrection
 *   (CLOSED · OPEN_UNCAPPED · KEEP_WHILE_PENDING · MAX · UNDECIDED)는 대표 답으로 대체돼 없앴다.
 */
export interface Cr4BankWindowPolicy {
  /**
   * L30 의 닫히는 시각(배타) — **채택: 대표 위임에 따른 Codex 결정(PP-DELEGATION-20261118 · 후속 §2-5)**.
   *   KST_L_PLUS_30D = KST(L) 0시 + 30×24h  (L=11-18 → 12-18 00:00 KST 부터 닫힘)
   *                    신분증 창 `nowMs < KST(L)+7d`(A/functions/src/index.ts:3833)와 같은 모양.
   *   채택하지 않은 식(값으로 두지 않는다 · 이력 history/): 'L+30일 말일까지'(KST(L)+31×24h) ·
   *   실제 종료시각 + 720h.
   */
  lastWorkBoundary: "KST_L_PLUS_30D";
  /** 선지급 — T_ONLY 유지(r4 감사 §6 · two_answers 판정 §2 표). */
  prepaid: "T_ONLY";
}

/**
 * 후보 정책 값 — 질문1 확정(two_answers) · L30 수식 채택(PP-DELEGATION-20261118) · 선지급 T_ONLY.
 *   (r4b 중간판의 noEndNotStarted 'OPEN_SEPARATE_PROPOSAL' 은 two_answers 판정 §2 '미시작 근무의 새 열람
 *   허용으로 확대하지 않는다'에 따라 없앴다 — 미시작 NO_END 는 항상 닫힘. 이력: history/.)
 */
export const CR4_BANK_WINDOW_POLICY_DRAFT: Cr4BankWindowPolicy = {
  lastWorkBoundary: "KST_L_PLUS_30D",
  prepaid: "T_ONLY",
};

/**
 * L30 의 닫히는 시각(배타).
 *
 * @param {number} lMidnightMs 마지막 근무일 KST 0시
 * @param {Cr4BankWindowPolicy["lastWorkBoundary"]} b 경계 수식
 * @return {number} 닫히는 시각(ms) — 이 시각부터 닫힘
 */
export function cr4LastWorkCloseMs(
  lMidnightMs: number, b: Cr4BankWindowPolicy["lastWorkBoundary"]
): number {
  if (b !== "KST_L_PLUS_30D") throw new Error("unknown lastWorkBoundary");
  return lMidnightMs + CR4_BANK_WINDOW_MS;
}

export type Cr4BankState =
  /** L 유효 · 마지막 근무일이 지나지 않음(시작 전 포함 — r4 S1 과 같다). */
  | "S1_WORKING"
  /** 종료일 결손 · 현재 근무 별도 확인(A1 결손 예외). */
  | "A1_CURRENT"
  /** 종료일 결손 · 효력 시작 전 — 새 열람 없음(닫힘). */
  | "A1_NOT_STARTED"
  /** 미결 ≥1 · 지급 기록 모두 확인 → 기존 T 규칙(지급 전이라 30일을 아직 세지 않음 · '나머지'). */
  | "S2_PENDING"
  /** 지급 종결 · 계좌서류 보완 없음 → T + 30×24h('나머지'). */
  | "S3_SETTLED_T30"
  /** 근무 끝 · 지급 이력 없음(근태 0건 또는 비지급 0원만) → L30(A2). */
  | "A2_NO_PAYMENT_L30"
  /** 지급 기록 불명(미결 확인 여부 무관) 또는 종결 뒤 보완 기록 불명 → L30(A3). */
  | "A3_UNKNOWN_L30"
  /** 지급 종결 뒤 이 계좌의 서류 보완 요청만 남음 → L30(A4). */
  | "A4_CORRECTION_L30"
  /** L30 이 필요한데 L 자체가 불명 → 계산 불가(닫힘 · 근거 보완 경로를 사유로 드러냄). */
  | "L_UNKNOWN"
  /** 이 관계 조회에 다른 사람·사업장 행이 섞임 → 닫힘('기록 불명'으로 완화하지 않음). */
  | "INTEGRITY";

export type Cr4Basis = "LAST_WORK_DAY" | "LAST_PAYMENT" | "CURRENT_WORK" | "NONE";

/**
 * [r4c · F-R4B-2 · PP-R4B-A4] 열린 보완 한 건이 **현재** 계좌·통장 문서에 결속되는 근거.
 *   PAYROLL_BOTH_VERSIONS   지급 보완(PAYROLL) · 요청의 계좌·통장 두 판본 = 현재 두 판본(유효 정수 정확 일치)
 *                           — 출처가 다른 근태이거나 없는(수동) 요청이어도 인정한다(공통 지급 보완)
 *   REVIEW_BANKBOOK_VERSION X 에 명시 연결된 지원자 보완(sourceApplicationId == X) · 요청 통장 판본 = 현재
 *                           — 지원 보완에는 계좌 판본이 없다(A :15984–15992) · 계좌 판본을 추정하지 않는다
 */
export type Cr4CorrectionBinding = "PAYROLL_BOTH_VERSIONS" | "REVIEW_BANKBOOK_VERSION";

/** 현재 사용자 문서의 판본(같은 snapshot 에서 읽은 값). 결손·오류는 null. */
export interface Cr4DocVersions {
  account: number | null;
  bankbook: number | null;
}

export interface Cr4BankWindow {
  state: Cr4BankState;
  open: boolean;
  /** 이번 판정의 기산 종류. */
  basis: Cr4Basis;
  /** 규칙 이름(시험·로그용). */
  rule: string;
  /** 마지막 근무일 KST 0시(유효할 때만) · 고른 필드. */
  lMs: number | null;
  lField: string | null;
  /** 마지막 유효 지급(①∪③ transferDate 최댓값). 지급 기록에 불명이 있으면 null. */
  tMs: number | null;
  /** NO_END 일 때만 — 현재 근무 근거. */
  currentWork: Cr4CurrentWork | null;
  /** 닫히는 시각(배타). 정해지지 않으면 null(S1 · A1 · S2). */
  closesAtMs: number | null;
  /** 이 시각 이후에는 상태가 바뀔 수 있어 다시 판정해야 한다(S1 = L 다음 날 0시). */
  reevaluateAtMs: number | null;
  /** 불명 사유(L · 현재근무 · 지급 기록 · 보완 기록 · 무결성). */
  unknownReasons: string[];
  reasons: string[];
  evidence: {
    attendanceComplete: boolean;
    correctionComplete: boolean;
    /** NO_END 가 아니면 null(계약을 읽지 않는다). */
    contractComplete: boolean | null;
    foreignAttendanceRows: number;
    foreignCorrections: number;
    /** 현재 계좌·통장 판본(입력 그대로) — 결속 판정의 기준. */
    docVersions: Cr4DocVersions;
  };
  counts: Record<Cr4AttClass, number> & {
    /** 현재 문서에 결속된 계좌서류 보완(A4 근거). */
    accountCorrections: number;
    /** 구판본(요청 판본 ≠ 현재) — 이 계좌의 현재 문제가 아니다. */
    staleCorrections: number;
    /** 다른 관계 전용(다른 지원서의 지원자 보완). */
    otherRelationCorrections: number;
    /** 신분증·세무 요청. */
    nonAccountCorrections: number;
    /** 판본·연결·유형 불명 → A3(PP-R4B-UNKNOWN). */
    unknownCorrections: number;
    binding: Record<Cr4CorrectionBinding, number>;
  };
}

export interface Cr4BankWindowInput {
  app: Doc;
  /** 지원서 X 의 문서 id(보완 출처 · 계약 연결 대조). */
  applicationId: string;
  attendances: ReadonlyArray<Doc & {id: string}>;
  attendanceSetComplete: boolean;
  corrections: ReadonlyArray<Doc>;
  /** 열린 보완 조회가 상한에 닿지 않았는가(C-R4-3). */
  correctionSetComplete: boolean;
  /** [r4c] 계좌·통장을 돌려주는 바로 그 사용자 snapshot 의 판본(cr4DocVersionsOf). */
  docVersions: Cr4DocVersions;
  /** NO_END 일 때만 필요 — 아니면 null 로 넘긴다(cr4NeedsCurrentWorkEvidence). */
  contracts: ReadonlyArray<Doc & {id: string}> | null;
  contractSetComplete: boolean;
  /** businesses/{app.businessId}. */
  business: Doc | null;
  nowMs: number;
  policy: Cr4BankWindowPolicy;
}

/**
 * 이 지원서의 기간 판정에 계약(현재 근무 근거)을 읽어야 하는가 — NO_END 일 때만.
 *
 * @param {Doc} app 지원서
 * @return {boolean} 읽어야 하면 true
 */
export function cr4NeedsCurrentWorkEvidence(app: Doc): boolean {
  return cr4LastWorkDay(app).kind === "NO_END";
}

const cr4VerInt = (v: unknown): number | null =>
  typeof v === "number" && Number.isInteger(v) && v >= 0 ? v : null;

/**
 * 사용자 문서 → 현재 판본. 결손·오류는 null — A 의 srvDocumentVersionsOf(:1670–1679)처럼 0 으로
 * 채우지 않는다(결손을 '판본 0 과 일치'로 합성하지 않는다 · F-R4B-2).
 *
 * @param {Doc} u users/{uid}
 * @return {Cr4DocVersions} 판본
 */
export function cr4DocVersionsOf(u: Doc): Cr4DocVersions {
  return {account: cr4VerInt(u["bankAccountVersion"]), bankbook: cr4VerInt(u["bankbookDocumentVersion"])};
}

/**
 * 열린 보완 요청 한 건의 분류 — [r4c · PP-R4B-A4] **현재 문서 판본 결속**으로 본다.
 *   r4b 의 'BANKBOOK 이면 전부 연결'은 폐기했다(오래된 요청이 현재 X 의 T30 을 A4 로 바꾸던 결손).
 *
 *   FOREIGN      다른 사업장·근로자(조회 조건상 나오면 무결성)
 *   NOT_LIVE     OPEN·RESUBMITTED 아님
 *   NOT_ACCOUNT  신분증·세무(documentType ID)
 *   ACCOUNT      현재 문서 결속 확인(binding)
 *   STALE        판본이 유효한데 현재와 다르다(구판본 — 이미 다른 문제)
 *   OTHER        다른 지원서 전용 지원자 보완(명확한 타관계 전용)
 *   UNKNOWN      판본 결손·오류 · 현재 판본 불명 · 출처/도메인 불명 · 모르는 문서종류
 *
 * @param {Doc} cr 보완 요청
 * @param {Doc} app 지원서 X
 * @param {string} applicationId X 의 id
 * @param {Cr4DocVersions} cur 현재 판본(같은 사용자 snapshot)
 * @return {object} 분류 · 결속 · 사유
 */
export function cr4ClassifyCorrection(
  cr: Doc, app: Doc, applicationId: string, cur: Cr4DocVersions
): {kind: "ACCOUNT" | "STALE" | "OTHER" | "NOT_ACCOUNT" | "NOT_LIVE" | "FOREIGN" | "UNKNOWN";
    binding: Cr4CorrectionBinding | null; reason: string} {
  const r = (kind: "ACCOUNT" | "STALE" | "OTHER" | "NOT_ACCOUNT" | "NOT_LIVE" | "FOREIGN" | "UNKNOWN",
    reason: string, binding: Cr4CorrectionBinding | null = null) => ({kind, binding, reason});
  if (!CR4_CORRECTION_LIVE.includes(cr["status"] as string)) return r("NOT_LIVE", "NOT_LIVE");
  if (cr["businessId"] !== app["businessId"] || cr["workerUid"] !== app["uid"]) return r("FOREIGN", "FOREIGN_ROW");
  const dt = cr["documentType"];
  if (dt === CR4_DOC_TYPE_ID) return r("NOT_ACCOUNT", "ID_DOCUMENT");
  if (dt !== CR4_DOC_TYPE_BANKBOOK) return r("UNKNOWN", "DOCUMENT_TYPE_UNKNOWN");
  const dom = cr["sourceDomain"];
  const reqBb = cr["documentVersionAtRequest"];
  if (dom === "PAYROLL") {
    // 자동(sourceAttendanceId 있음)·수동(없음) 모두 같은 결정적 id 의 공통 지급 보완(:3150–3155 · :38532–38553).
    const reqAcc = cr4VerInt(cr["bankAccountVersionAtRequest"]);
    const reqB = cr4VerInt(reqBb);
    if (reqAcc === null || reqB === null) return r("UNKNOWN", "PAYROLL_REQUEST_VERSION_INVALID");
    if (cur.account === null || cur.bankbook === null) return r("UNKNOWN", "CURRENT_VERSION_UNKNOWN");
    if (reqAcc !== cur.account || reqB !== cur.bankbook) return r("STALE", "PAYROLL_VERSION_STALE");
    return r("ACCOUNT", "PAYROLL_CURRENT", "PAYROLL_BOTH_VERSIONS");
  }
  if (dom === undefined || dom === null) {
    // 지원자 서류 검토 보완(:15975–15992 — sourceDomain 없음 · sourceApplicationId · 통장 판본만).
    const sp = cr["sourceApplicationId"];
    if (typeof sp !== "string" || sp === "") return r("UNKNOWN", "REVIEW_SOURCE_UNKNOWN");
    if (sp !== applicationId) return r("OTHER", "REVIEW_OF_OTHER_RELATION");
    const reqB = cr4VerInt(reqBb);
    if (reqB === null) return r("UNKNOWN", "REVIEW_REQUEST_VERSION_INVALID");
    if (cur.bankbook === null) return r("UNKNOWN", "CURRENT_VERSION_UNKNOWN");
    if (reqB !== cur.bankbook) return r("STALE", "REVIEW_VERSION_STALE");
    return r("ACCOUNT", "REVIEW_CURRENT", "REVIEW_BANKBOOK_VERSION");
  }
  return r("UNKNOWN", "SOURCE_DOMAIN_UNKNOWN");
}

/**
 * 지원서 X 의 확정자 통장사본·현재 계좌 열람 기간. **기존 권한·관계·목적·확정·동의/판본 gate 와
 * AND** 로만 쓴다 — 여기서 열림이어도 그 앞의 검사를 건너뛰지 않는다.
 *
 *   순서(위에서부터 처음 맞는 것):
 *     0. [r4c · F-R4B-3] 관계 무결성 선검증 — 근태·보완에 다른 사람·사업장 행 → INTEGRITY(닫힘).
 *        S1·A1 의 열린 조기 반환보다 **먼저**다.
 *     1. L 유효 ∧ now < KST(L)+24h                       → S1(열림 · 재판정 = L 다음 날 0시 · 시작 전 포함)
 *     2. NO_END → cr4CurrentWork
 *          CURRENT → A1(열림) · NOT_STARTED → 닫힘(미시작 새 열람 0) · ENDED/UNKNOWN → L 불명으로 계속
 *     3. 지급 기록 불명(⑤ ≥1 · 근태 잘림)                  → A3 L30(미결이 있어도)
 *     4. 미결 ≥1                                          → S2(T 규칙 · 보완 불명만으로 재분류 0)
 *     5. 지급 종결(T) ∧ 보완 기록 불명(잘림 · 유형/판본/연결 불명) → A3 L30(PP-R4B-UNKNOWN)
 *        지급 종결(T) ∧ 현재 문서에 결속된 계좌서류 보완 ≥1  → A4 L30(T<L·T>L 무관 · 재시작 0)
 *        지급 종결(T)                                      → S3 T30
 *     6. 근태 0건 또는 비지급 0원만                        → A2 L30
 *   L30 이 필요한데 L 이 불명이면 L_UNKNOWN(닫힘). T30·S2 는 L 이 없어도 계산된다.
 *   min/max/OR 합성 0. L 에 현재 시각·일부 지급 시각을 넣지 않는다.
 *
 * @param {Cr4BankWindowInput} input 입력
 * @return {Cr4BankWindow} 상태
 */
export function cr4BankWindow(input: Cr4BankWindowInput): Cr4BankWindow {
  const {app, attendances, corrections, nowMs, policy} = input;
  const counts = {
    PAID: 0, NONPAYABLE_ZERO: 0, ZERO_PAID: 0, OPEN: 0, UNKNOWN: 0,
    accountCorrections: 0, staleCorrections: 0, otherRelationCorrections: 0,
    nonAccountCorrections: 0, unknownCorrections: 0,
    binding: {PAYROLL_BOTH_VERSIONS: 0, REVIEW_BANKBOOK_VERSION: 0} as Record<Cr4CorrectionBinding, number>,
  };
  const reasons: string[] = [];
  const unknownReasons: string[] = [];
  const evidence = {
    attendanceComplete: input.attendanceSetComplete,
    correctionComplete: input.correctionSetComplete,
    contractComplete: null as boolean | null,
    foreignAttendanceRows: 0,
    foreignCorrections: 0,
    docVersions: {account: input.docVersions.account, bankbook: input.docVersions.bankbook},
  };
  const lwd = cr4LastWorkDay(app);
  let lMs: number | null = lwd.kind === "KNOWN" ? cr4KstMidnightMs(lwd.ms) : null;
  let lField: string | null = lwd.kind === "KNOWN" ? lwd.field : null;
  let tMs: number | null = null;
  let currentWork: Cr4CurrentWork | null = null;
  const out = (state: Cr4BankState, rule: string, basis: Cr4Basis, open: boolean,
    closesAtMs: number | null = null, reevaluateAtMs: number | null = null): Cr4BankWindow => {
    // 닫히는 시각 정각부터 닫힘.
    const o = open && (closesAtMs === null || nowMs < closesAtMs);
    return {
      state, open: o, basis, rule, lMs, lField, tMs, currentWork, closesAtMs, reevaluateAtMs,
      unknownReasons, reasons, evidence, counts,
    };
  };

  // ── 0. 관계 무결성 선검증 + 분류(근태 · 보완) — 어떤 반환보다 먼저 ──
  const settledMs: number[] = [];
  const paymentUnknown: string[] = [];
  const correctionUnknown: string[] = [];
  for (const a of attendances) {
    const c = cr4ClassifyAttendance(a, app, nowMs);
    if (c.reason === "FOREIGN_ROW") {
      evidence.foreignAttendanceRows++;
      reasons.push(`ATT_${a.id}_FOREIGN_ROW`);
      continue;
    }
    counts[c.cls]++;
    if (c.cls === "UNKNOWN") paymentUnknown.push(`ATT_${a.id}_${c.reason}`);
    if ((c.cls === "PAID" || c.cls === "ZERO_PAID") && c.transferMs !== null) {
      settledMs.push(c.transferMs);
    }
  }
  if (!input.attendanceSetComplete) paymentUnknown.push("ATTENDANCE_SET_TRUNCATED");
  for (const cr of corrections) {
    const k = cr4ClassifyCorrection(cr, app, input.applicationId, input.docVersions);
    switch (k.kind) {
    case "NOT_LIVE": break;
    case "FOREIGN": evidence.foreignCorrections++; break;
    case "NOT_ACCOUNT": counts.nonAccountCorrections++; break;
    case "STALE": counts.staleCorrections++; break;
    case "OTHER": counts.otherRelationCorrections++; break;
    case "UNKNOWN":
      counts.unknownCorrections++;
      correctionUnknown.push(`CORRECTION_${k.reason}`);
      break;
    case "ACCOUNT":
      counts.accountCorrections++;
      if (k.binding !== null) counts.binding[k.binding]++;
      break;
    }
  }
  if (!input.correctionSetComplete) correctionUnknown.push("CORRECTION_SET_TRUNCATED");
  if (evidence.foreignAttendanceRows > 0 || evidence.foreignCorrections > 0) {
    unknownReasons.push("RELATION_INTEGRITY_FOREIGN_ROWS");
    return out("INTEGRITY", "INTEGRITY_FOREIGN_ROWS", "NONE", false);
  }

  // 장기에서 퇴사/해지 결정이 승인됐는데 실제 종료일이 없다 — 남은 종료일(workEndDate)을
  //   L 로 쓰면 끝난 관계를 '근무 중'으로 연다. 정상 writer 는 날짜를 함께 쓴다(:10087 · :31335).
  const longTerm = app["type"] === "long_term" || app["type"] === "contract";
  const resignMissing = app["actualResignDate"] === undefined || app["actualResignDate"] === null;
  if (lMs !== null && longTerm && resignMissing &&
      (CR4_ENDED_DECISIONS.includes(app["resignStatus"] as string) ||
       CR4_ENDED_DECISIONS.includes(app["terminationStatus"] as string))) {
    unknownReasons.push("L_ENDED_DECISION_WITHOUT_RESIGN_DATE");
    lMs = null;
    lField = null;
  }
  const l30 = lMs === null ? null : cr4LastWorkCloseMs(lMs, policy.lastWorkBoundary);

  // 1. S1
  if (lMs !== null && nowMs < lMs + DAY_MS) {
    reasons.push("LAST_WORK_DAY_NOT_PASSED");
    return out("S1_WORKING", "S1", "LAST_WORK_DAY", true, null, lMs + DAY_MS);
  }

  // 2. NO_END
  if (lwd.kind === "NO_END") {
    evidence.contractComplete = input.contracts === null ? null : input.contractSetComplete;
    currentWork = cr4CurrentWork({
      app, applicationId: input.applicationId, contracts: input.contracts,
      contractSetComplete: input.contractSetComplete, business: input.business, nowMs,
    });
    if (currentWork.state === "CURRENT") {
      // 근거 계약 기간의 다음 날 0시에 다시 판정한다(그 끝을 L 로 쓰지 않는다).
      reasons.push("A1_CURRENT_WORK_CONFIRMED");
      const pe = currentWork.contractPeriodEndMs;
      return out("A1_CURRENT", "A1_CURRENT_WORK", "CURRENT_WORK", true, null,
        pe === null ? null : pe + DAY_MS);
    }
    if (currentWork.state === "NOT_STARTED") {
      // 미시작 근무에 새 열람을 만들지 않는다(PP-R4B-PRESTART).
      reasons.push("A1_NOT_STARTED_CLOSED");
      return out("A1_NOT_STARTED", "A1_NOT_STARTED_CLOSED", "NONE", false);
    }
    unknownReasons.push(`L_NO_END_CURRENT_WORK_${currentWork.state}`);
  } else if (lwd.kind !== "KNOWN") {
    unknownReasons.push(`L_${lwd.kind}_${lwd.field}`);
  }

  const byL = (state: Cr4BankState, rule: string): Cr4BankWindow => {
    if (l30 === null) {
      // L 자체 불명 — 계산 불가. 근거 보완 경로: 지원서의 종료일/퇴사일 정정(관리자) 뒤 재판정.
      reasons.push(`${rule}_NEEDS_LAST_WORK_DAY`);
      return out("L_UNKNOWN", `${rule}_L_UNKNOWN`, "NONE", false);
    }
    return out(state, rule, "LAST_WORK_DAY", true, l30);
  };
  const pending = counts.OPEN > 0;
  if (paymentUnknown.length > 0) {
    unknownReasons.push(...paymentUnknown);
    return byL("A3_UNKNOWN_L30", pending ? "A3_PENDING_AND_UNKNOWN" : "A3_UNKNOWN_ONLY");
  }
  if (pending) {
    // 보완 요청·보완 불명은 미결이 아니다 — 일반 순수 미결을 재분류하지 않는다.
    reasons.push("PENDING_T_RULE");
    return out("S2_PENDING", "T_RULE_PENDING", "LAST_PAYMENT", true);
  }
  if (settledMs.length > 0) {
    tMs = Math.max(...settledMs);
    if (correctionUnknown.length > 0) {
      // PP-R4B-UNKNOWN — 보완 없음이 확인되지 않으면 종결 뒤 A3 L30.
      unknownReasons.push(...correctionUnknown);
      return byL("A3_UNKNOWN_L30", "A3_SETTLED_CORRECTION_RECORD_UNKNOWN");
    }
    if (counts.accountCorrections > 0) {
      // T·L 을 다시 시작하지 않는다 — T 는 지급 기록 그대로, 닫힘은 L30(T>L 조기 닫힘 수용).
      reasons.push("SETTLED_WITH_CURRENT_ACCOUNT_CORRECTION");
      return byL("A4_CORRECTION_L30", "A4_SETTLED_CORRECTION_ONLY");
    }
    reasons.push("SETTLED");
    return out("S3_SETTLED_T30", "T30", "LAST_PAYMENT", true, tMs + CR4_BANK_WINDOW_MS);
  }
  reasons.push(attendances.length === 0 ? "NO_ATTENDANCE" : "NONPAYABLE_ONLY");
  return byL("A2_NO_PAYMENT_L30", attendances.length === 0 ? "A2_NO_ATTENDANCE" : "A2_NONPAYABLE_ONLY");
}

/**
 * 새 서명 URL 의 만료 절대시각. 닫혀 있거나 정각 이후면 null(발급 0).
 *   min(now+1h, 닫히는 시각, 재판정 시각) — S1 에서 받은 URL 이 L 다음 날로 넘어가지 않는다.
 *
 * @param {Cr4BankWindow} w 상태
 * @param {number} nowMs 발급 시각
 * @return {number | null} expires(ms)
 */
export function cr4BankbookUrlExpiryMs(w: Cr4BankWindow, nowMs: number): number | null {
  if (!w.open) return null;
  let exp = nowMs + CR4_URL_TTL_MS;
  if (w.closesAtMs !== null) {
    if (nowMs >= w.closesAtMs) return null;
    exp = Math.min(exp, w.closesAtMs);
  }
  if (w.reevaluateAtMs !== null && w.reevaluateAtMs > nowMs) {
    exp = Math.min(exp, w.reevaluateAtMs);
  }
  return exp;
}

export type Cr4ClosedKind = "PERIOD_ENDED" | "NEEDS_CONFIRMATION" | "NOT_STARTED";

/**
 * 닫힌 이유의 화면용 구분 — '기간이 끝남'·'기록 확인 필요'·'근무 시작 전'을 같은 '-'로 숨기지 않는다.
 *   권한 없음·동의 없음·미등록은 이 함수 앞의 gate 가 따로 돌려준다.
 *
 * @param {Cr4BankWindow} w 닫힌 상태
 * @return {Cr4ClosedKind | null} 열려 있으면 null
 */
export function cr4ClosedKind(w: Cr4BankWindow): Cr4ClosedKind | null {
  if (w.open) return null;
  if (w.state === "A1_NOT_STARTED") return "NOT_STARTED";
  if (w.state === "L_UNKNOWN" || w.state === "INTEGRITY") return "NEEDS_CONFIRMATION";
  return "PERIOD_ENDED";
}

/**
 * [C-R4-3] 서명 **직전** 재판정 — 앞선 판정 뒤 I/O 동안 경계를 넘었으면 발급 0.
 *   같은 입력을 지금 시각으로 다시 판정한다(S1 의 날짜 경계 · L30/T30 정각 · A1 시작일 모두).
 *
 * @param {Cr4BankWindowInput} input 앞선 판정의 입력
 * @param {number} signNowMs 서명 직전 시각
 * @return {{window: Cr4BankWindow, expiresMs: number | null}} 재판정
 */
export function cr4SignableExpiryMs(
  input: Cr4BankWindowInput, signNowMs: number
): {window: Cr4BankWindow; expiresMs: number | null} {
  const window = cr4BankWindow({...input, nowMs: signNowMs});
  return {window, expiresMs: cr4BankbookUrlExpiryMs(window, signNowMs)};
}

export type Cr4InheritReason =
  | "GIVEN_NOT_TRUE" | "VERSION_MISSING" | "VERSION_NOT_INHERITABLE"
  | "AT_MISSING" | "AT_MALFORMED" | "AT_FUTURE" | "LINEAGE_INCONSISTENT";

/**
 * 확정 재배치(A→B)에서 A 의 저장 동의를 B 로 승계할 수 있는가.
 *   [C-R4-2] 출처와 계보를 **양방향**으로 본다:
 *     Source=REASSIGN_INHERITED  ⇔  inheritedFrom 있음(비어 있지 않은 문자열)
 *     inheritedFrom 있으면: == sourceApplicationId ∧ offerKind == 재배치 ∧ reassignmentProposalId 있음
 *   EXPLICIT 로 생긴 재배치 관계(Source=REASSIGN_EXPLICIT · parent 없음)는 정상 직접 동의다 —
 *   offerKind 만으로 승계를 강제하지 않는다. At 하한(새 관계 생성시각)은 두지 않는다.
 *
 * @param {Doc} src 트랜잭션이 읽은 A
 * @param {number} nowMs 판정 시각
 * @param {ReadonlyArray<string>} inheritable 승계 자격 판본
 * @param {string} reassignOfferKind 재배치 관계의 offerKind
 * @return {object} ok + B 에 쓸 필드, 또는 실패 이유(+세부)
 */
export function cr4ConsentInheritance(
  src: Doc, nowMs: number, inheritable: ReadonlyArray<string>, reassignOfferKind: string
): {ok: true; fields: Doc} | {ok: false; reason: Cr4InheritReason; detail?: string} {
  if (src["documentAccessConsentGiven"] !== true) return {ok: false, reason: "GIVEN_NOT_TRUE"};
  const v = src["documentAccessConsentVersion"];
  if (v === undefined || v === null) return {ok: false, reason: "VERSION_MISSING"};
  if (typeof v !== "string" || !inheritable.includes(v)) {
    return {ok: false, reason: "VERSION_NOT_INHERITABLE"};
  }
  const atRaw = src["documentAccessConsentAt"];
  if (atRaw === undefined || atRaw === null) return {ok: false, reason: "AT_MISSING"};
  const atMs = cr4ValidTsMs(atRaw);
  if (atMs === null) return {ok: false, reason: "AT_MALFORMED"};
  if (atMs > nowMs) return {ok: false, reason: "AT_FUTURE"};
  const source = src["documentAccessConsentSource"];
  if (source !== undefined && source !== null && typeof source !== "string") {
    return {ok: false, reason: "LINEAGE_INCONSISTENT", detail: "SOURCE_MALFORMED"};
  }
  const from = src["documentAccessConsentInheritedFrom"];
  const hasFrom = from !== undefined && from !== null;
  const inherited = source === "REASSIGN_INHERITED";
  if (inherited && !hasFrom) {
    return {ok: false, reason: "LINEAGE_INCONSISTENT", detail: "INHERITED_WITHOUT_PARENT"};
  }
  if (hasFrom && !inherited) {
    return {ok: false, reason: "LINEAGE_INCONSISTENT", detail: "PARENT_WITHOUT_INHERITED_SOURCE"};
  }
  if (hasFrom) {
    const pid = src["reassignmentProposalId"];
    if (typeof from !== "string" || from === "") {
      return {ok: false, reason: "LINEAGE_INCONSISTENT", detail: "PARENT_MALFORMED"};
    }
    if (from !== src["sourceApplicationId"]) {
      return {ok: false, reason: "LINEAGE_INCONSISTENT", detail: "PARENT_NOT_SOURCE"};
    }
    if (src["offerKind"] !== reassignOfferKind) {
      return {ok: false, reason: "LINEAGE_INCONSISTENT", detail: "OFFER_KIND"};
    }
    if (typeof pid !== "string" || pid === "") {
      return {ok: false, reason: "LINEAGE_INCONSISTENT", detail: "PROPOSAL_ID"};
    }
  }
  const fields: Doc = {
    documentAccessConsentGiven: true,
    documentAccessConsentVersion: v,
    documentAccessConsentAt: atRaw,
  };
  if (src["idCardConsentGiven"] === true && cr4ValidTsMs(src["idCardConsentAt"]) !== null) {
    fields["idCardConsentGiven"] = true;
    fields["idCardConsentAt"] = src["idCardConsentAt"];
  }
  return {ok: true, fields};
}

/**
 * 재배치 제안(서버 저장값) ↔ 지금 원 근무 A 계보(r4 와 같다).
 *
 * @param {Doc} p 제안
 * @param {Doc} src A
 * @param {string} callerUid 호출자
 * @param {string} sourceId A 문서 id
 * @return {string | null} 불일치 항목
 */
export function cr4LineageBlock(
  p: Doc, src: Doc, callerUid: string, sourceId: string
): string | null {
  if (p["sourceApplicationId"] !== sourceId) return "SOURCE_ID";
  if (p["uid"] !== callerUid || src["uid"] !== callerUid) return "UID";
  if (src["businessId"] !== p["businessId"]) return "BUSINESS";
  if (src["toId"] !== p["targetToId"]) return "TO";
  if (src["slotId"] !== p["targetSlotId"]) return "SLOT";
  const pw = p["sourceWdId"];
  if (pw !== undefined && pw !== null && src["wdId"] !== pw) return "SOURCE_WD";
  const pm = cr4ValidTsMs(p["workDate"]);
  const sm = cr4ValidTsMs(src["workDate"]);
  if (pm === null || sm === null || pm !== sm) return "WORK_DATE";
  return null;
}
