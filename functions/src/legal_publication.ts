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
};

/** 현재 공개 중인 항목 — projection. */
export type ProjectionItem = {
  id: string;
  version: string;
  revisionId?: string;
  contentHash?: string;
  isRequired: boolean;
  isActive: boolean;
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
