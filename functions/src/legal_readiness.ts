// [R7-LEGAL.1B.1] 계산된 상태를 제품 행동으로 잇는다.
//
//   1B 가 "다시 받아야 하는가" 를 판정할 수 있게 만들었지만, 그것을 읽는
//   곳이 하나도 없었다. 상태는 소비되지 않으면 없는 것과 같다.
//
//   이 모듈은 그 판정을 **하나의 상태**로 정리한다. 화면은 이 값을 받아
//   그리기만 하고, 스스로 버전을 비교하지 않는다. 비교 규칙이 두 곳에
//   생기면 두 곳이 다른 답을 말하게 된다.
//
//   ── 왜 두 가지 "미충족" 을 나누는가 ────────────────────────────
//
//   같은 "동의가 없다" 라도 사건이 다르다.
//
//     · 새 판이 나왔다        — 발행본이 실제로 있고, 사용자가 **다른 판**에
//                              동의했거나 아직 이 판에 답하지 않았다.
//                              제품이 다시 물어야 하는 정상 흐름이다.
//     · 옛 기록이라 모른다    — 1B 이전에는 같은 version 의 본문을 고칠 수
//                              있었다. 그 시절 기록은 무엇을 가리키는지
//                              증명할 수 없다. 사용자 잘못이 아니다.
//
//   둘을 같은 문장으로 말하면 안 되고(§14), 같은 강도로 막아도 안 된다.
//
//   ── 판별 기준을 고친 이유 (R7-LEGAL.DEPLOY §12) ────────────────
//
//   처음에는 **발행본 문서가 있는가** 로 갈랐다. 1B 이전 항목은
//   `legal_revisions` 에 문서가 없으니 구별된다고 봤다.
//
//   그 기준은 **최초 발행 전에만** 맞았다. DEV 에서 활성 5종을 발행하자마자
//   기존 사용자 8명이 전원 `RECONSENT_REQUIRED` 로 뒤집혔고 지원이 막혔다.
//   당연하다 — 발행본이 생겼으니 "발행본이 있다" 는 조건이 모두 참이 된다.
//   우리가 약관을 바꾼 적이 없는데 사용자에게 "변경되었습니다" 라고 말하고
//   길을 막은 것이다.
//
//   사건의 차이는 **사용자 기록 쪽**에 있다.
//
//     기록에 revisionId 가 있고 지금 판과 다르다  → 다른 판에 동의했다(새 판)
//     기록에 revisionId 가 없다                   → 1B 이전 기록(증명 불가)
//     기록이 아예 없다                            → 이 사람이 1B 이후 사람인가로 가른다
//
//   마지막 갈래가 필요한 이유: 새 필수 항목이 추가되면 1B 이후 사용자에게는
//   기록이 없는 것이 정상적인 "새 항목" 이지만, 1B 이전 사용자에게는 그냥
//   증명할 수 없는 상태다. 둘을 같게 다루면 또 전원을 막게 된다.
//
//   순수 모듈이다(Firestore·admin SDK 없음).

import {legalRevisionId} from "./legal_publication";
import type {ProjectionItem, ConsentProjection} from "./legal_publication";

export type LegalReadinessStatus =
  /** 현재 필수 약관을 전부 수락했다. */
  | "CURRENT"
  /** 새 판이 발행됐고 아직 그 판에 동의하지 않았다. */
  | "RECONSENT_REQUIRED"
  /** 옛 기록이라 무엇에 동의했는지 증명할 수 없다. */
  | "LEGACY_CONSENT_UNKNOWN"
  /** 필수는 전부 충족. 선택 항목만 답하지 않았다. */
  | "OPTIONAL_UNANSWERED";

export type LegalReadiness = {
  status: LegalReadinessStatus;
  /** 새 판이라 다시 받아야 하는 필수 항목. */
  reconsentRequired: string[];
  /** 증명할 수 없는 옛 기록인 필수 항목. */
  legacyUnknown: string[];
  /** 이 판에 답한 적 없는 선택 항목. */
  optionalUnanswered: string[];
};

/**
 * 지금 이 사용자의 법적 준비 상태.
 *
 * 조회 실패는 여기서 다루지 않는다 — 호출자가 ERROR 로 따로 말한다.
 * **모르는 것을 미동의로 바꾸지 않기 위해서다.**
 *
 * @param {object} input 입력
 * @param {ProjectionItem[]} input.activeItems 현재 공개 중인 항목
 * @param {ConsentProjection} input.consent 사용자의 현재 동의 projection
 * @param {Set<string>} input.publishedRevisionIds 실재하는 발행본 id 들
 * @return {LegalReadiness} 판정
 */
export function evaluateLegalReadiness(input: {
  activeItems: ProjectionItem[];
  consent: ConsentProjection;
  publishedRevisionIds: Set<string>;
}): LegalReadiness {
  const {activeItems, consent, publishedRevisionIds} = input;
  const reconsentRequired: string[] = [];
  const legacyUnknown: string[] = [];
  const optionalUnanswered: string[] = [];

  /** 발행본을 가리키는 기록인가 — 무엇에 동의했는지 증명할 수 있는가. */
  const identified = (r: {revisionId?: unknown} | undefined) =>
    typeof r?.revisionId === "string" && r.revisionId !== "";

  // 이 사람이 1B 이후에 동의한 적이 있는가. 하나라도 있으면 기록 없는
  // 항목은 "새로 생긴 항목" 이고, 하나도 없으면 그냥 옛 사용자다.
  const postIdentityUser = Object.values(consent).some(identified);

  for (const item of activeItems) {
    if (!item.isActive) continue;
    const want = item.revisionId ?? legalRevisionId(item.id, item.version);
    const rec = consent[item.id];
    const accepted = rec?.agreed === true &&
      typeof rec?.revisionId === "string" && rec.revisionId === want;

    if (item.isRequired) {
      if (accepted) continue;

      // 다른 판에 동의한 기록이 있다 — 우리가 판을 바꿨다는 뜻이다.
      if (identified(rec)) { reconsentRequired.push(item.id); continue; }

      // 기록은 있는데 어떤 판인지 모른다 — 1B 이전 기록이다.
      if (rec !== undefined) { legacyUnknown.push(item.id); continue; }

      // 기록 자체가 없다. 1B 이후 사용자에게만 "새 항목" 으로 센다.
      if (postIdentityUser && publishedRevisionIds.has(want)) {
        reconsentRequired.push(item.id);
      } else {
        legacyUnknown.push(item.id);
      }
      continue;
    }

    const answered = typeof rec?.revisionId === "string" &&
      rec.revisionId === want && typeof rec?.agreed === "boolean";
    if (!answered) optionalUnanswered.push(item.id);
  }

  // 우선순위 — 제품이 먼저 말해야 하는 것부터.
  const status: LegalReadinessStatus =
    reconsentRequired.length > 0 ? "RECONSENT_REQUIRED" :
      legacyUnknown.length > 0 ? "LEGACY_CONSENT_UNKNOWN" :
        optionalUnanswered.length > 0 ? "OPTIONAL_UNANSWERED" : "CURRENT";

  return {status, reconsentRequired, legacyUnknown, optionalUnanswered};
}

/**
 * 이 상태에서 **새 법적 약속**을 만들 수 있는가.
 *
 *   막는 것은 `RECONSENT_REQUIRED` 하나다. 발행본이 실재하므로 사용자가
 *   무엇에 동의해야 하는지 정확히 보여 줄 수 있고, 다시 받는 것이 정상
 *   흐름이기 때문이다.
 *
 *   `LEGACY_CONSENT_UNKNOWN` 은 **막지 않는다.** 그 상태는 사용자가 만든
 *   것이 아니라 예전 구조가 남긴 것이고, 발행이 아직 새 경로를 거치지
 *   않았다면 **모든 사용자**가 이 상태다. 그걸로 앱을 잠그면 제품이 멈춘다.
 *   대신 할 일로 남겨 다음에 받는다(soft migration).
 *
 *   `OPTIONAL_UNANSWERED` 도 막지 않는다 — 선택은 선택이다.
 *
 * @param {LegalReadinessStatus} status 현재 상태
 * @return {boolean} 새 약속을 만들 수 있으면 true
 */
export function allowsNewCommitment(status: LegalReadinessStatus): boolean {
  return status !== "RECONSENT_REQUIRED";
}
