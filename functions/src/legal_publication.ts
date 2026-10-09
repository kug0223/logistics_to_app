// [R7-LEGAL.1B] 세 가지 사실을 분리한다.
//
//   1. 지금 공개 중인 법적 문서
//   2. 사용자가 과거에 실제로 동의한 문서의 증거
//   3. 지금 다시 동의가 필요한가
//
//   예전 구조는 셋을 한 값에 얹고 있었다. `app_settings/legal_terms.items[]`
//   의 `content` 를 SUPER_ADMIN 이 **같은 version 문자열 그대로** 고칠 수
//   있었고, 동의 기록은 그 version 문자열만 가리켰다. 그래서
//   `{version: "2026.08"}` 라는 증거가 남아 있어도 그것이 어떤 글이었는지
//   나중에 확정할 수 없었다.
//
//   고치는 방법은 발행본을 **고쳐 쓸 수 없게** 만드는 것이다.
//
//     legal_revisions/{itemId}__{version}
//
//   문서 id 가 (항목, 버전)이므로 같은 version 으로 다른 본문을 발행하려면
//   이미 있는 문서를 덮어써야 하는데, writer 가 그것을 거절한다. 본문을
//   바꾸려면 **새 version** 을 발행해야 한다. 그러면 "같은 version 이면 같은
//   글"이 시간이 지나도 참이 된다.
//
//   DEV 실측(2026-10-06)에서 `2026.08` 을 네 항목이 공유하고 있었다 —
//   version 은 전역 식별자가 아니라 **항목 안에서만** 뜻이 있다. 그래서
//   revision id 에 itemId 를 함께 넣는다.
//
//   이 모듈은 순수하다(Firestore·admin SDK 없음).

import * as crypto from "crypto";

/** 발행된 한 판. 고쳐 쓰지 않는다. */
export type LegalRevision = {
  itemId: string;
  version: string;
  contentHash: string;
  /** [R7-PAYROLL-POLICY.5A] 이 판이 실제로 적용되기 시작하는 시각. */
  effectiveAtMs?: number | null;
};

/**
 * [R7-PAYROLL-POLICY.5A] 아직 시행되지 않은 발행본 하나.
 *
 *   발행은 "공개/고지" 이고 시행은 "적용" 이다. 둘 사이의 기간이 사전고지
 *   기간이다. 그 기간 동안 이 포인터가 **대기** 자리에 있고, 효력은 아직
 *   base 에 있다.
 */
export type UpcomingRevision = {
  version: string;
  revisionId: string;
  effectiveAtMs: number;
  /**
   * 예정 판의 제목·본문도 함께 들고 있다.
   *
   * 들고 있지 않으면 시행 시각이 지난 뒤 **승격되기 전까지** 읽는 쪽이
   * 새 버전 번호와 옛 본문을 섞어 보여 준다. 그 조합은 어느 글에도
   * 해당하지 않으므로, 승격은 포인터가 아니라 한 벌 전체를 옮기는 일이다.
   * 그리고 사전고지 기간 동안 "시행 예정 약관" 을 보여 줄 수 있어야 한다.
   */
  title?: string;
  content?: string;
  contentHash?: string;
};

/** 현재 공개 중인 항목 — projection. base 는 **항상 시행 중인 판**이다. */
export type ProjectionItem = {
  id: string;
  version: string;
  revisionId?: string;
  contentHash?: string;
  isRequired: boolean;
  isActive: boolean;
  /** base 가 시행된 시각. 1B 이전 항목에는 없다(그때부터 시행 중으로 본다). */
  effectiveAtMs?: number | null;
  /** 시행 예정 판. 없으면 예정된 변경이 없다. */
  upcoming?: UpcomingRevision | null;
};

/** 사용자의 현재 동의 상태 — projection. */
export type ConsentProjection = Record<string, {
  agreed?: unknown;
  version?: unknown;
  revisionId?: unknown;
}>;

/**
 * id 로 쓸 수 있는 모양인가. dotted path·슬래시를 막는다.
 *
 * @param {unknown} v 검사할 값
 * @return {boolean} 쓸 수 있으면 true
 */
export function isValidLegalToken(v: unknown): v is string {
  return typeof v === "string" && /^[A-Za-z0-9_.-]{1,64}$/.test(v) &&
    v !== "." && v !== "..";
}

/**
 * 발행본 문서 id. (항목, 버전) 한 쌍에 하나다.
 *
 * @param {string} itemId 약관 항목 id
 * @param {string} version 버전 문자열
 * @return {string} 문서 id
 */
export function legalRevisionId(itemId: string, version: string): string {
  return `${itemId}__${version}`;
}

/**
 * 본문의 신원. 같은 글이면 같은 값이다.
 *
 * 장식이 아니다 — 이미 발행된 version 에 다른 글을 밀어 넣으려는 시도를
 * 이 값으로 가려낸다.
 *
 * @param {string} content 약관 본문
 * @return {string} sha256 hex
 */
export function contentHashOf(content: string): string {
  return crypto.createHash("sha256").update(content, "utf8").digest("hex");
}

export type PublishVerdict =
  | {ok: true; reason: "CREATE"}
  | {ok: true; reason: "IDENTICAL"}
  | {ok: false; reason: "VERSION_REUSED"}
  | {ok: false; reason: "INVALID_ID"}
  | {ok: false; reason: "INVALID_VERSION"}
  | {ok: false; reason: "EMPTY_CONTENT"};

/**
 * 이 발행을 허용할 수 있는가.
 *
 *   · 같은 (항목, 버전) 이 없으면 → 새로 만든다
 *   · 있고 본문이 **같으면** → 아무 일도 하지 않는다(재발행은 무해)
 *   · 있고 본문이 **다르면** → 거절한다. 발행본은 고쳐 쓰지 않는다.
 *
 * @param {object} input 입력
 * @param {string} input.itemId 항목 id
 * @param {string} input.version 버전
 * @param {string} input.content 본문
 * @param {LegalRevision | null} input.existing 같은 id 의 기존 발행본
 * @return {PublishVerdict} 판정
 */
export function evaluatePublish(input: {
  itemId: string;
  version: string;
  content: string;
  existing: LegalRevision | null;
}): PublishVerdict {
  const {itemId, version, content, existing} = input;
  if (!isValidLegalToken(itemId)) return {ok: false, reason: "INVALID_ID"};
  if (!isValidLegalToken(version)) {
    return {ok: false, reason: "INVALID_VERSION"};
  }
  if (typeof content !== "string" || content.trim() === "") {
    return {ok: false, reason: "EMPTY_CONTENT"};
  }
  if (!existing) return {ok: true, reason: "CREATE"};
  return existing.contentHash === contentHashOf(content) ?
    {ok: true, reason: "IDENTICAL"} :
    {ok: false, reason: "VERSION_REUSED"};
}

// ──────────────────────────────────────────────────────────────────
// [R7-PAYROLL-POLICY.5A] 발행 ≠ 시행 ≠ 재동의
//
//   예전에는 셋이 한 순간이었다. `callablePublishLegalRevision` 이
//   발행본을 만들고 **같은 transaction 에서** projection 을 교체했으므로,
//   발행하는 순간 모든 reader 가 새 판을 현재 약관으로 말했고
//   `evaluateReconsent` 가 즉시 재동의를 요구했다.
//
//   그런데 service_terms 제3조 ② 는 이렇게 약속한다.
//
//     이용자에게 유리하거나 중립적인 변경: 최소 7일 전 앱 내 공지
//     이용자에게 불리한 변경:            최소 30일 전
//
//   약속과 동작이 어긋나 있었다. 약속을 지우는 쪽으로 맞추지 않는다 —
//   개인정보 보호법 제30조 제3항도 처리방침과 계약이 다르면 **정보주체에게
//   유리한 것**을 적용하라고 한다. 그래서 동작을 약속에 맞춘다.
//
//   법정 최소 기간은 없다. 전자상거래법은 적용 근거를 확인하지 못했고
//   (R7-PAYROLL-POLICY.5), 개인정보 보호법 제30조 제2항·시행령 제31조
//   제2항은 "변경한 처리방침을 홈페이지에 지속 게재" 만 요구한다.
//   전자금융거래법 제24조 제3항이 "시행일 1월 전 게시" 라는 **같은 모양**
//   을 쓰지만 금융회사·전자금융업자 전용이라 ALfit 에 직접 적용되지 않는다 —
//   설계 참조일 뿐 근거로 쓰지 않는다.
//
//   그래서 기간의 출처는 **ALfit 자기약속** 하나다.
// ──────────────────────────────────────────────────────────────────

/**
 * 이 변경이 이용자에게 어떤 방향인가.
 *
 *   `initial`  이 항목의 **첫 발행**. 아직 시행 중인 판이 없으므로 고지할
 *              이전 내용도 없다. caller 가 주장하는 값이 아니라 서버가
 *              projection 에 항목이 없음을 보고 허용한다 — 주장만으로
 *              즉시 시행하는 구멍을 만들지 않기 위해서다.
 *   `neutral`  유리하거나 중립적인 변경.
 *   `adverse`  이용자에게 불리할 수 있는 변경. 판단이 갈리면 이쪽을 쓴다.
 */
export type LegalChangeType = "initial" | "neutral" | "adverse";

/**
 * 변경 방향별 최소 사전고지 기간(일).
 *
 * 법정 최소가 아니다 — `service_terms` 제3조 ② 가 약속한 기간이다.
 * 약관 문구를 고치지 않는 한 이 표를 줄일 수 없다.
 */
export const LEGAL_NOTICE_DAYS: Record<LegalChangeType, number> = {
  initial: 0,
  neutral: 7,
  adverse: 30,
};

const DAY_MS = 24 * 60 * 60 * 1000;
const KST_OFFSET_MS = 9 * 60 * 60 * 1000;

/**
 * 그 시각이 속한 **KST 날짜의 자정** (UTC epoch ms).
 *
 * 법적 시행일은 날짜 단위다("2026년 11월 7일부터"). 시각을 끌고 다니면
 * 발행 시각에 따라 사용자가 보는 날짜가 달라진다. UTC 자정으로 만들면
 * 국내 사용자에게 하루 어긋난다 — 그래서 KST 자정으로 고정한다.
 *
 * @param {number} ms 기준 시각 (epoch ms)
 * @return {number} 그 KST 날짜의 자정 (epoch ms)
 */
export function kstMidnightMs(ms: number): number {
  return Math.floor((ms + KST_OFFSET_MS) / DAY_MS) * DAY_MS - KST_OFFSET_MS;
}

/**
 * 이 변경을 지금 발행한다면 가장 이른 시행일은 언제인가.
 *
 * 고지기간을 **온전히** 채운 뒤의 첫 KST 자정이다. 자정으로 내림하면
 * 기간이 모자라므로, 모자라면 다음 날로 올린다.
 *
 * @param {LegalChangeType} changeType 변경 방향
 * @param {number} publishedAtMs 발행 시각
 * @return {number} 가장 이른 시행 시각 (KST 자정)
 */
export function earliestEffectiveAtMs(
  changeType: LegalChangeType,
  publishedAtMs: number,
): number {
  // 첫 발행은 고지할 이전 내용이 없다. 그리고 **즉시 시행이어야** 한다 —
  // 미래로 미루면 그 항목은 시행 중인 판이 없는 상태로 존재하게 된다.
  if (changeType === "initial") return kstMidnightMs(publishedAtMs);
  const need = publishedAtMs + LEGAL_NOTICE_DAYS[changeType] * DAY_MS;
  const m = kstMidnightMs(need);
  return m >= need ? m : m + DAY_MS;
}

export type NoticeVerdict =
  | {ok: true; changeType: LegalChangeType; effectiveAtMs: number}
  | {ok: false; reason:
      | "INVALID_CHANGE_TYPE"
      | "INITIAL_NOT_ALLOWED"
      | "INITIAL_REQUIRED"
      | "INITIAL_MUST_BE_IMMEDIATE"
      | "EFFECTIVE_AT_REQUIRED"
      | "EFFECTIVE_AT_NOT_KST_MIDNIGHT"
      | "NOTICE_PERIOD_TOO_SHORT"
      | "EFFECTIVE_AT_IMMUTABLE";
      earliestEffectiveAtMs?: number; storedEffectiveAtMs?: number};

/**
 * 이 발행의 시행일을 받아들일 수 있는가.
 *
 *   · `changeType` 은 세 값 중 하나여야 한다.
 *   · 첫 발행인지는 **서버가** 판단한다(`hasExistingEffective`). caller 가
 *     `initial` 이라고 주장해도 이미 시행 중인 판이 있으면 거절한다.
 *   · 시행일은 **생략할 수 없다**. 기본값을 "즉시" 로 두면 실수 한 번이
 *     사전고지 약속을 깨고, "최소기간 후" 로 두면 caller 가 어떤 날짜를
 *     약속한 것인지 기록에 남지 않는다.
 *   · 이미 발행된 판의 시행일은 바꿀 수 없다. 바꿀 수 있으면 고지기간
 *     자체를 나중에 줄일 수 있다.
 *
 * @param {object} input 입력
 * @param {unknown} input.changeType caller 가 보낸 변경 방향
 * @param {number} input.publishedAtMs 서버 기준 발행 시각
 * @param {number | null} input.effectiveAtMs caller 가 보낸 시행 시각
 * @param {boolean} input.hasExistingEffective 이미 시행 중인 판이 있는가
 * @param {number | null | undefined} input.storedEffectiveAtMs
 *   같은 (항목, 버전) 이 이미 발행돼 있다면 그때 확정된 시행 시각
 * @return {NoticeVerdict} 판정
 */
export function evaluateNoticePeriod(input: {
  changeType: unknown;
  publishedAtMs: number;
  effectiveAtMs: number | null;
  hasExistingEffective: boolean;
  storedEffectiveAtMs?: number | null;
}): NoticeVerdict {
  const {publishedAtMs, effectiveAtMs, hasExistingEffective} = input;
  const ct = input.changeType;
  if (ct !== "initial" && ct !== "neutral" && ct !== "adverse") {
    return {ok: false, reason: "INVALID_CHANGE_TYPE"};
  }
  if (ct === "initial" && hasExistingEffective) {
    return {ok: false, reason: "INITIAL_NOT_ALLOWED"};
  }
  if (ct !== "initial" && !hasExistingEffective) {
    return {ok: false, reason: "INITIAL_REQUIRED"};
  }
  if (effectiveAtMs == null || !Number.isFinite(effectiveAtMs)) {
    return {ok: false, reason: "EFFECTIVE_AT_REQUIRED",
      earliestEffectiveAtMs: earliestEffectiveAtMs(ct, publishedAtMs)};
  }
  // 이미 발행된 판이면 그때 확정된 시행일이 canonical 이다.
  const stored = input.storedEffectiveAtMs;
  if (stored != null && stored !== effectiveAtMs) {
    return {ok: false, reason: "EFFECTIVE_AT_IMMUTABLE",
      storedEffectiveAtMs: stored};
  }
  // 이미 발행된 판을 **그 시행일 그대로** 다시 보내는 경우 — 노출 토글처럼
  //   본문이 아니라 공개 목록만 손대는 호출이다. 고지기간은 처음 발행할 때
  //   이미 지켰으므로 다시 요구하지 않는다. 다시 요구하면 발행 다음 날
  //   노출을 끄는 일조차 불가능해진다.
  if (stored != null && stored === effectiveAtMs) {
    return {ok: true, changeType: ct, effectiveAtMs};
  }
  if (effectiveAtMs !== kstMidnightMs(effectiveAtMs)) {
    return {ok: false, reason: "EFFECTIVE_AT_NOT_KST_MIDNIGHT"};
  }
  // 첫 발행은 고지할 이전 내용이 없다 — 즉시 시행을 허용하되, 그 판단은
  // 서버가 항목 부재를 보고 한 것이다. 그리고 미래로 미룰 수 없다:
  // 미루면 그 항목은 **시행 중인 판이 없는 채로** 공개 목록에 들어간다.
  if (ct === "initial") {
    const today = kstMidnightMs(publishedAtMs);
    if (effectiveAtMs !== today) {
      return {ok: false, reason: "INITIAL_MUST_BE_IMMEDIATE",
        earliestEffectiveAtMs: today};
    }
    return {ok: true, changeType: ct, effectiveAtMs};
  }

  const earliest = earliestEffectiveAtMs(ct, publishedAtMs);
  if (effectiveAtMs < earliest) {
    return {ok: false, reason: "NOTICE_PERIOD_TOO_SHORT",
      earliestEffectiveAtMs: earliest};
  }
  return {ok: true, changeType: ct, effectiveAtMs};
}

export type ResolvedItem = {
  /** 지금 **시행 중인** 판으로 평탄화된 항목. */
  item: ProjectionItem;
  /** 아직 시행되지 않은 예정 판. 없으면 null. */
  pendingUpcoming: UpcomingRevision | null;
  /** 예정 판이 시행 시각을 지나 승격됐는가 — projection 을 고쳐야 한다. */
  promoted: boolean;
};

/**
 * 지금 시행 중인 판은 무엇인가.
 *
 *   **이 함수가 유일한 기준이다.** 공개 웹·앱·readiness·동의 writer 가
 *   각자 "현재 약관" 을 계산하면 넷이 다른 답을 말하게 된다. 실제로
 *   그것이 `.5A` 가 고치는 결함이다.
 *
 *   `nowMs` 는 **서버 시각**이어야 한다. 기기 시계를 넣으면 시계를 돌린
 *   사용자에게 아직 시행되지 않은 약관이 적용된다.
 *
 * @param {ProjectionItem} item projection 항목 하나
 * @param {number} nowMs 서버 기준 현재 시각
 * @return {ResolvedItem} 시행 중인 판과 예정 판
 */
export function resolveEffectiveItem(
  item: ProjectionItem,
  nowMs: number,
): ResolvedItem {
  const up = item.upcoming;
  if (up && Number.isFinite(up.effectiveAtMs) && up.effectiveAtMs <= nowMs) {
    return {
      item: {
        ...item,
        version: up.version,
        revisionId: up.revisionId,
        contentHash: up.contentHash,
        effectiveAtMs: up.effectiveAtMs,
        upcoming: null,
      },
      pendingUpcoming: null,
      promoted: true,
    };
  }
  return {
    item: {...item, upcoming: up ?? null},
    pendingUpcoming: up ?? null,
    promoted: false,
  };
}

/** 승격 때 base 로 옮겨지는 자리들. 포인터만 옮기면 본문이 어긋난다. */
const UPCOMING_CARRIED = [
  "version", "revisionId", "title", "content", "contentHash", "effectiveAt",
] as const;

/**
 * 시행 시각이 지난 예정 판을 base 로 옮긴다.
 *
 *   발행 writer 와 정기 reconciliation 이 **같은 이 함수**를 쓴다. 두 곳이
 *   각자 자리를 옮기면 한쪽만 고쳐졌을 때 base 의 버전과 본문이 서로 다른
 *   글을 가리킨다.
 *
 *   저장된 값(`Timestamp` 등)은 해석하지 않고 **그대로 옮긴다** — 시각
 *   비교에 쓸 ms 만 caller 가 변환해 넘긴다. 그래서 변환 규칙이 한 곳에
 *   머문다.
 *
 * @param {object} input 입력
 * @param {Record<string, unknown>} input.raw 저장된 항목 하나
 * @param {number | null} input.upcomingEffectiveAtMs
 *   예정 판의 시행 시각(ms). 예정 판이 없으면 null
 * @param {number} input.nowMs 서버 기준 현재 시각
 * @return {{raw: Record<string, unknown>, promoted: boolean}} 결과
 */
export function promoteDueUpcoming(input: {
  raw: Record<string, unknown>;
  upcomingEffectiveAtMs: number | null;
  nowMs: number;
}): {raw: Record<string, unknown>; promoted: boolean} {
  const {raw, upcomingEffectiveAtMs, nowMs} = input;
  const up = raw["upcoming"];
  if (up == null || typeof up !== "object" || Array.isArray(up)) {
    return {raw, promoted: false};
  }
  if (upcomingEffectiveAtMs == null ||
      !Number.isFinite(upcomingEffectiveAtMs) ||
      upcomingEffectiveAtMs > nowMs) {
    return {raw, promoted: false};
  }
  const src = up as Record<string, unknown>;
  const next: Record<string, unknown> = {...raw};
  for (const k of UPCOMING_CARRIED) {
    if (src[k] !== undefined) next[k] = src[k];
  }
  next["upcoming"] = null;
  return {raw: next, promoted: true};
}

export type PlacementVerdict =
  | {ok: true; items: Array<Record<string, unknown>>;
      placed: "base" | "upcoming"}
  | {ok: false; reason: "EFFECTIVE_AT_IN_PAST"};

/**
 * 발행된 판을 공개 목록의 **어느 자리**에 둘 것인가.
 *
 *   시행 중이면 base, 아직 아니면 대기 자리다. 이 판단이 writer 안에
 *   인라인으로 있으면 실행으로 확인할 수 없고, 변이 테스트에서 실제로
 *   빠져나갔다(`.5A` M12). 그래서 꺼냈다.
 *
 *   base 에 쓰는 경우는 둘뿐이다.
 *     · 그 항목이 공개 목록에 아직 없다 — 첫 발행
 *     · 지금 base 인 판을 그대로 다시 보냈다 — 노출 토글 등
 *
 *   그 밖에 이미 지난 시행일로 base 를 바꾸는 것은 거절한다. 고지 없이
 *   적용 중인 약관을 바꾸는 일이고, 사용자가 이미 동의한 새 판을 낡은
 *   것으로 만든다.
 *
 *   대기 자리에 쓸 때 base 는 **건드리지 않는다**. 그리고 base 에 쓸 때
 *   대기 자리를 지우지 않는다 — 노출 토글이 예고된 변경을 조용히 취소해
 *   버리면 고지가 사라진다.
 *
 *   저장된 값(`Timestamp` 등)은 해석하지 않는다 — caller 가 만들어 넘긴
 *   자리들을 그대로 놓는다.
 *
 * @param {object} input 입력
 * @param {Array<Record<string, unknown>>} input.items 현재 공개 목록
 * @param {string} input.itemId 항목 id
 * @param {string} input.revisionId 이번 발행본 id
 * @param {Record<string, unknown>} input.baseFields base 에 쓸 자리들
 * @param {Record<string, unknown>} input.upcomingFields 대기 자리에 쓸 값
 * @param {number} input.effectiveAtMs 확정된 시행 시각
 * @param {number} input.nowMs 서버 기준 현재 시각
 * @return {PlacementVerdict} 판정과 새 목록
 */
export function placePublishedRevision(input: {
  items: Array<Record<string, unknown>>;
  itemId: string;
  revisionId: string;
  baseFields: Record<string, unknown>;
  upcomingFields: Record<string, unknown>;
  effectiveAtMs: number;
  nowMs: number;
}): PlacementVerdict {
  const {itemId, revisionId, baseFields, upcomingFields} = input;
  const items = input.items.map((x) => ({...x}));
  const at = items.findIndex((x) => String(x["id"] ?? "") === itemId);

  // 시행 여부를 caller 가 불리언으로 넘기면, 그 한 줄이 실행으로 확인되지
  // 않는 자리가 된다(`.5A` 변이 M12b 가 그렇게 빠져나갔다). 시각 둘을
  // 받아 여기서 판단한다.
  if (input.effectiveAtMs <= input.nowMs) {
    if (at >= 0 && String(items[at]["revisionId"] ?? "") !== revisionId) {
      return {ok: false, reason: "EFFECTIVE_AT_IN_PAST"};
    }
    const next: Record<string, unknown> = {
      ...baseFields,
      upcoming: at >= 0 ? (items[at]["upcoming"] ?? null) : null,
    };
    if (at >= 0) items[at] = next; else items.push(next);
    return {ok: true, items, placed: "base"};
  }

  // 시행 예정. 대기 자리만 바꾼다 — 대기 중이던 판이 있으면 교체된다.
  //   그 판은 한 번도 시행된 적이 없고, 새 판은 자기 고지기간을 처음부터
  //   다시 채운다(`evaluateNoticePeriod` 가 이미 확인했다).
  if (at < 0) return {ok: false, reason: "EFFECTIVE_AT_IN_PAST"};
  items[at] = {...items[at], upcoming: {...upcomingFields}};
  return {ok: true, items, placed: "upcoming"};
}

/** [R7-PAYROLL-POLICY.5B] 저장된 시각 하나를 epoch ms 로. caller 가 준다. */
export type LegalTimeReader = (v: unknown) => number | null;

export type ResolvedProjection = {
  /** 지금 **시행 중인** 활성 항목. 모든 판정의 기준이다. */
  effective: ProjectionItem[];
  /**
   * 시행 중인 항목의 제목·본문·순서. 순서가 `effective` 와 같다.
   *
   * 승격이 적용됐으면 **예정 판 쪽** 값이 들어 있다 — 버전만 바꾸고 본문을
   * 남기면 어느 글에도 해당하지 않는 조합이 된다.
   */
  effectiveRaw: Array<Record<string, unknown>>;
  /** 고지는 됐지만 아직 시행되지 않은 것. 판정 기준이 **아니다**. */
  upcoming: Array<{itemId: string; version: string; revisionId: string;
    effectiveAtMs: number}>;
};

/**
 * [R7-PAYROLL-POLICY.5B] 공개 목록 전체를 **서버 시각 기준**으로 해석한다.
 *
 *   `.5A` 에서는 이 일이 `index.ts` 안에 있었다. `resolveEffectiveItem`
 *   하나만 순수했고, 그것을 감싸 저장 모양을 읽는 부분(시각 변환, 예정 판
 *   유효성, 어느 쪽 본문을 쓸지)은 실행으로 확인할 수 없었다. `.5B` 변이
 *   B7·B8 이 바로 그 자리로 빠져나갔다 — 예정 판 버전을 시행 중으로
 *   올려도, 본문을 발행본 대신 사본에서 가져와도 아무 테스트가 깨지지
 *   않았다. 그래서 꺼냈다.
 *
 *   `toMs` 를 받는 이유: 이 모듈은 admin SDK 를 쓰지 않는다(순수). 저장된
 *   `Timestamp` 를 읽는 방법은 caller 가 넘긴다.
 *
 * @param {object} input 입력
 * @param {unknown} input.rawItems `app_settings/legal_terms.items`
 * @param {number} input.nowMs 서버 기준 현재 시각
 * @param {LegalTimeReader} input.toMs 저장된 시각을 ms 로 바꾸는 함수
 * @return {ResolvedProjection} 시행 중인 것과 예정된 것
 */
export function resolveProjectionItems(input: {
  rawItems: unknown;
  nowMs: number;
  toMs: LegalTimeReader;
}): ResolvedProjection {
  const {rawItems, nowMs, toMs} = input;
  const effective: ProjectionItem[] = [];
  const effectiveRaw: Array<Record<string, unknown>> = [];
  const upcoming: ResolvedProjection["upcoming"] = [];

  for (const raw of Array.isArray(rawItems) ? rawItems : []) {
    if (!raw || typeof raw !== "object") continue;
    const i = raw as Record<string, unknown>;
    const id = String(i["id"] ?? "");
    if (id === "") continue;

    const upRaw = i["upcoming"];
    const up = upRaw != null && typeof upRaw === "object" &&
      !Array.isArray(upRaw) ? upRaw as Record<string, unknown> : null;
    const upEffMs = up ? toMs(up["effectiveAt"]) : null;
    const upRevisionId = up && typeof up["revisionId"] === "string" ?
      up["revisionId"] : "";
    const upVersion = up ? String(up["version"] ?? "") : "";

    const resolved = resolveEffectiveItem({
      id,
      version: String(i["version"] ?? ""),
      revisionId: typeof i["revisionId"] === "string" &&
        i["revisionId"] !== "" ? i["revisionId"] : undefined,
      isRequired: i["isRequired"] !== false,
      isActive: i["isActive"] !== false,
      effectiveAtMs: toMs(i["effectiveAt"]),
      // 모양이 깨진 예정 판은 **없는 것으로 친다** — 모르는 것을 시행
      // 중으로 올리지 않는다.
      upcoming: up && upEffMs != null && upRevisionId !== "" &&
        upVersion !== "" ?
        {version: upVersion, revisionId: upRevisionId,
          effectiveAtMs: upEffMs} : null,
    }, nowMs);

    const item = resolved.item;
    if (item.version !== "" && item.isActive) {
      effective.push(item);
      const src = resolved.promoted && up ? up : i;
      effectiveRaw.push({
        title: src["title"] ?? i["title"],
        content: src["content"] ?? i["content"],
        contentHash: src["contentHash"] ?? i["contentHash"],
        order: i["order"],
      });
    }
    if (resolved.pendingUpcoming) {
      upcoming.push({
        itemId: id,
        version: resolved.pendingUpcoming.version,
        revisionId: resolved.pendingUpcoming.revisionId,
        effectiveAtMs: resolved.pendingUpcoming.effectiveAtMs,
      });
    }
  }
  return {effective, effectiveRaw, upcoming};
}

/**
 * [R7-PAYROLL-POLICY.5B.1] 이 항목의 글이 **어디서 왔는가**.
 *
 *   `.5B` 까지는 `verified: boolean` 하나였다. 그래서 성질이 전혀 다른 두
 *   상태가 같은 값으로 뭉개졌다.
 *
 *     `legacy`    포인터 자체가 없다(1B 이전 항목). 지금 공개 중인 글은
 *                 맞지만 그 글이 고쳐지지 않았다는 증거가 없다. **정상
 *                 호환 상태**이고 막으면 모든 옛 사용자가 멈춘다.
 *     `mismatch`  포인터는 있는데 가리키는 발행본이 없거나 다른 항목·다른
 *                 버전이다. **무결성 실패**다 — 사용자가 본 글과 동의
 *                 기록이 가리키는 글이 같다고 말할 수 없다.
 *
 *   둘을 한 값으로 두면 "막아야 하는 것" 과 "막으면 안 되는 것" 을 구별할
 *   수 없다. 실제로 `.5B.1` 재현에서 양쪽 다 동의가 성공했다.
 */
export type RevisionProvenance = "published" | "legacy" | "mismatch";

/**
 * 포인터가 가리키는 발행본이 **이 항목·이 버전**인가.
 *
 * @param {object} input 입력
 * @param {object} input.item 항목(id·version·revisionId)
 * @param {Record<string, unknown> | undefined} input.revision 읽어 온 발행본
 * @return {RevisionProvenance} 분류
 */
export function classifyRevisionProvenance(input: {
  item: {id: string; version: string; revisionId?: string | null};
  revision: Record<string, unknown> | undefined;
}): RevisionProvenance {
  const {item, revision} = input;
  const pointer = typeof item.revisionId === "string" &&
    item.revisionId !== "" ? item.revisionId : null;
  // 포인터가 없으면 1B 이전 항목이다 — 확인할 대상 자체가 없다.
  if (pointer == null) return "legacy";
  if (revision == null) return "mismatch";
  if (String(revision["itemId"] ?? "") !== item.id) return "mismatch";
  if (String(revision["version"] ?? "") !== item.version) return "mismatch";
  return "published";
}

export type EffectiveLegalItem = {
  itemId: string;
  version: string;
  revisionId: string | null;
  title: string;
  content: string;
  contentHash: string;
  /** `provenance === "published"` 와 같다. 공개 웹 계약 호환으로 남긴다. */
  verified: boolean;
  /** [R7-PAYROLL-POLICY.5B.1] 글의 출처. 막을지 말지는 이 값으로 가른다. */
  provenance: RevisionProvenance;
  isRequired: boolean;
  isActive: boolean;
  order: number;
  effectiveAtMs: number | null;
};

export type RequiredIntegrityVerdict = {
  /** 발행본이 어긋난 **필수** 항목. 하나라도 있으면 동의를 받을 수 없다. */
  mismatched: string[];
  /** 본문이 비어 있는 **필수** 항목. 읽을 수 없는 글에 동의받지 않는다. */
  empty: string[];
  ok: boolean;
};

/**
 * [R7-PAYROLL-POLICY.5B.1] 필수 약관을 **지금 동의받을 수 있는가**.
 *
 *   보는 것은 "필수가 하나라도 있는가" 가 아니다. 들어온 필수 항목이
 *   **빠짐없이 쓸 수 있는 상태인가** 다.
 *
 *   `legacy` 는 통과시킨다 — 1B 이전 항목을 막으면 옛 사용자 전원이
 *   멈추고, 그 상태는 사용자가 만든 것이 아니다(기존 soft migration
 *   계약과 같은 판단). 막는 것은 `mismatch` 와 빈 본문이다.
 *
 *   선택 항목은 전체를 막지 않는다. 선택은 선택이고, 그 하나가 깨졌다고
 *   필수 동의까지 못 하게 하면 가입이 멈춘다. 다만 화면은 그 항목을
 *   정상으로 그리지 않는다(클라이언트 쪽 계약).
 *
 * @param {Array<object>} items 서버가 내보낼 시행 중 항목들
 * @return {RequiredIntegrityVerdict} 판정
 */
export function evaluateRequiredIntegrity(items: Array<{
  itemId: string;
  isRequired: boolean;
  provenance: RevisionProvenance;
  content: string;
}>): RequiredIntegrityVerdict {
  const mismatched: string[] = [];
  const empty: string[] = [];
  for (const i of items) {
    if (!i.isRequired) continue;
    if (i.provenance === "mismatch") {
      mismatched.push(i.itemId);
      continue;
    }
    if (typeof i.content !== "string" || i.content.trim() === "") {
      empty.push(i.itemId);
    }
  }
  return {mismatched, empty,
    ok: mismatched.length === 0 && empty.length === 0};
}

/**
 * [R7-PAYROLL-POLICY.5B] 시행 중인 항목 하나를 앱·웹에 내보낼 모양으로.
 *
 *   본문은 **발행본에서** 온다. 공개 목록의 `content` 는 포인터가 가리키는
 *   글의 사본일 뿐이고, 증거는 고쳐 쓸 수 없는 쪽에 있다. 공개 웹
 *   (`legal-reader.js`)도 같은 규칙을 쓰므로 앱과 웹이 같은 글을 본다.
 *
 *   포인터가 가리키는 발행본이 **이 항목·이 버전**인지 확인한다. 어긋나면
 *   그 글을 쓰지 않고, 사본을 쓰되 `verified: false` 로 말한다 — 포인터만
 *   믿고 아무 글을 현재 약관으로 내지 않는다.
 *
 * @param {object} input 입력
 * @param {ProjectionItem} input.item 해석된 시행 중 항목
 * @param {Record<string, unknown>} input.raw 그 항목의 제목·본문·순서
 * @param {Record<string, unknown> | undefined} input.revision 발행본
 * @return {EffectiveLegalItem} 내보낼 한 건
 */
export function composeEffectiveLegalItem(input: {
  item: ProjectionItem;
  raw: Record<string, unknown>;
  revision: Record<string, unknown> | undefined;
}): EffectiveLegalItem {
  const {item, raw, revision} = input;
  const provenance = classifyRevisionProvenance({item, revision});
  const matched = provenance === "published";
  // `published` 면 revision 이 반드시 있다(분류의 정의) — 그래도 타입으로
  // 증명되지 않으므로 여기서 한 번 더 고른다.
  const src: Record<string, unknown> =
    matched && revision != null ? revision : raw;
  return {
    itemId: item.id,
    version: item.version,
    revisionId: item.revisionId ?? null,
    title: String(src["title"] ?? ""),
    content: String(src["content"] ?? ""),
    contentHash: String(src["contentHash"] ?? ""),
    verified: matched,
    provenance,
    isRequired: item.isRequired,
    isActive: item.isActive,
    order: typeof raw["order"] === "number" ? raw["order"] : 0,
    effectiveAtMs: item.effectiveAtMs ?? null,
  };
}

/** [R7-PAYROLL-POLICY.5B.1] 발행본을 확인해야 하는 필수 항목 포인터. */
export type RequiredRevisionPointer = {
  id: string;
  version: string;
  revisionId: string;
};

/**
 * 동의를 받기 전에 **발행본을 읽어 봐야 하는** 항목들.
 *
 *   필수이고, 포인터가 있는 것만이다. 선택 항목은 전체를 막지 않으므로
 *   읽지 않고, 포인터가 없는 1B 이전 항목은 확인할 대상 자체가 없다.
 *   그래서 추가 read 가 최소로 유지된다.
 *
 * @param {Array<object>} activeItems 시행 중인 활성 항목
 * @return {RequiredRevisionPointer[]} 읽어야 할 포인터들
 */
export function requiredRevisionPointers(activeItems: Array<{
  id: string;
  version: string;
  isRequired: boolean;
  revisionId?: string | null;
}>): RequiredRevisionPointer[] {
  const out: RequiredRevisionPointer[] = [];
  for (const i of activeItems) {
    if (!i.isRequired) continue;
    if (typeof i.revisionId !== "string" || i.revisionId === "") continue;
    out.push({id: i.id, version: i.version, revisionId: i.revisionId});
  }
  return out;
}

export type RequiredRevisionGate =
  | {ok: true}
  | {ok: false; reason: "LEGAL_REQUIRED_REVISION_MISMATCH"; itemIds: string[]};

/**
 * [R7-PAYROLL-POLICY.5B.1] 이 동의를 기록해도 되는가 — **writer 쪽 확인**.
 *
 *   `.5B` 까지 동의 writer 는 `legal_revisions` 를 한 번도 읽지 않았다.
 *   공개 목록의 버전 문자열만 비교했으므로, 포인터가 가리키는 발행본이
 *   사라졌거나 다른 항목·다른 버전을 가리켜도 동의가 그대로 기록됐다.
 *   그 기록의 `revisionId` 는 **존재하지 않는 글**을 가리킨다.
 *
 *   클라이언트가 막는 것으로는 부족하다. 동의는 법적 기록이고, 그 기록을
 *   만드는 쪽이 스스로 확인해야 한다.
 *
 *   판단을 순수 함수로 두는 이유: writer 안에 인라인으로 있으면 조건 하나를
 *   `false` 로 바꿔도 아무 테스트가 깨지지 않는다(`.5B.1` 변이 I5·I10 이
 *   그렇게 빠져나갔다).
 *
 * @param {object} input 입력
 * @param {RequiredRevisionPointer[]} input.pointers 확인 대상
 * @param {object} input.revisions 읽어 온 발행본들 (id → 문서)
 * @return {RequiredRevisionGate} 판정
 */
export function gateRequiredRevisions(input: {
  pointers: RequiredRevisionPointer[];
  revisions: {get(id: string): Record<string, unknown> | undefined};
}): RequiredRevisionGate {
  const itemIds: string[] = [];
  for (const p of input.pointers) {
    const provenance = classifyRevisionProvenance({
      item: {id: p.id, version: p.version, revisionId: p.revisionId},
      revision: input.revisions.get(p.revisionId),
    });
    if (provenance === "mismatch") itemIds.push(p.id);
  }
  return itemIds.length === 0 ?
    {ok: true} :
    {ok: false, reason: "LEGAL_REQUIRED_REVISION_MISMATCH", itemIds};
}

export type ReconsentVerdict = {
  /** 다시 받아야 하는 **필수** 항목. 비어 있으면 READY. */
  required: string[];
  /** 아직 고른 적 없는 **선택** 항목. 막지 않는다 — 자동 true 도 아니다. */
  optionalUnanswered: string[];
};

/**
 * 지금 다시 동의가 필요한가.
 *
 *   필수 항목은 **활성 revision 과 사용자가 수락한 revision 이 같아야** 한다.
 *   하나라도 다르면 그 항목은 다시 받아야 한다. 새로 생긴 필수 항목도 같다.
 *
 *   선택 항목은 새 판이 나왔다고 해서 막지 않는다. 그리고 과거 거부를 새
 *   버전의 동의로 추정하지 않는다 — 고른 적이 없으면 `optionalUnanswered`
 *   일 뿐, `agreed` 가 아니다.
 *
 *   비활성 항목은 아예 보지 않는다.
 *
 *   `revisionId` 가 없는 **옛 기록**은 수락으로 세지 않는다. 그 기록이 어떤
 *   글을 가리키는지 증명할 수 없기 때문이다(UNKNOWN ≠ AGREED).
 *
 * @param {object} input 입력
 * @param {ProjectionItem[]} input.activeItems 현재 공개 항목
 * @param {ConsentProjection} input.consent 사용자의 현재 동의 projection
 * @return {ReconsentVerdict} 판정
 */
export function evaluateReconsent(input: {
  activeItems: ProjectionItem[];
  consent: ConsentProjection;
}): ReconsentVerdict {
  const {activeItems, consent} = input;
  const required: string[] = [];
  const optionalUnanswered: string[] = [];

  for (const item of activeItems) {
    if (!item.isActive) continue;
    const want = item.revisionId ?? legalRevisionId(item.id, item.version);
    const rec = consent[item.id];
    const accepted = rec?.agreed === true &&
      typeof rec?.revisionId === "string" && rec.revisionId === want;

    if (item.isRequired) {
      if (!accepted) required.push(item.id);
      continue;
    }
    // 선택 — 이 판에 대해 **고른 적이 있는가**만 본다(동의든 거부든).
    const answered = typeof rec?.revisionId === "string" &&
      rec.revisionId === want && typeof rec?.agreed === "boolean";
    if (!answered) optionalUnanswered.push(item.id);
  }

  return {required, optionalUnanswered};
}

/**
 * 옛 기록 한 건이 **무엇을 증명하는가**.
 *
 *   `KNOWN`     — 발행본을 가리키고 그 발행본이 실제로 있다. 그대로 이력으로
 *                 옮길 수 있다.
 *   `AMBIGUOUS` — 버전 문자열만 있고 어떤 글이었는지 알 수 없다. 그 시절에는
 *                 같은 버전의 본문을 고칠 수 있었다. **동의로 바꾸지 않는다.**
 *   `MISSING`   — 기록이 없다. 이력을 만들지 않는다.
 *
 *   `AMBIGUOUS` 와 `MISSING` 을 "동의함" 으로 승격하는 경로를 두지 않는 것이
 *   이 함수의 존재 이유다. 모르는 것은 모르는 것이다.
 *
 * @param {object} input 입력
 * @param {object | undefined} input.record 사용자의 기존 동의 한 건
 * @param {Set<string>} input.knownRevisionIds 실제로 존재하는 발행본 id 들
 * @return {"KNOWN" | "AMBIGUOUS" | "MISSING"} 분류
 */
export function classifyLegacyConsent(input: {
  record: {agreed?: unknown; version?: unknown; revisionId?: unknown} |
    undefined | null;
  knownRevisionIds: Set<string>;
}): "KNOWN" | "AMBIGUOUS" | "MISSING" {
  const {record, knownRevisionIds} = input;
  if (!record || typeof record !== "object") return "MISSING";
  if (typeof record.agreed !== "boolean") return "MISSING";
  const rev = record.revisionId;
  if (typeof rev === "string" && knownRevisionIds.has(rev)) return "KNOWN";
  return "AMBIGUOUS";
}
