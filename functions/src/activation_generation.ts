// [R7-APPLICATION-LIFECYCLE.1E.1] 관계 문서 identity ≠ 관계 사건 identity.
//
//   canonical Apply writer 는 inactive 관계(CANCELED·AUTO_CANCELED·REJECTED)를
//   **같은 결정적 docId 에서** 되살린다. 그래서 한 문서가
//
//     PENDING → 자동취소(겹침) → 재지원 → PENDING → 자동취소(겹침)
//
//   를 겪을 수 있고, 두 자동취소는 서로 다른 domain event 다.
//
//   docId 만으로 알림 identity 를 만들면 두 사건이 한 알림 문서를 공유한다.
//   그리고 FCM dispatcher 는 `onDocumentCreated` 다 — 같은 문서를 덮어써도
//   **재발송되지 않는다**. 첫 알림의 읽음·삭제 상태까지 재사용된다. 결과는
//   "두 번째 실제 취소가 조용히 사라지는 것"이다.
//
//   그래서 "이 관계가 몇 번째로 활성화됐는가"를 세대로 센다.
//
//   이 모듈은 순수하다(Firestore·admin SDK 없음). snapshot 은 duck type 으로
//   받는다 — `exists` 와 `data()` 만 쓴다.

/** 관계 문서 데이터 — 필요한 것은 한 필드뿐이다. */
export type ActivationData =
  {activationGeneration?: unknown} | undefined | null;

/** transaction 에서 읽은 관계 문서 — `exists` 와 `data()` 만 본다. */
export type ActivationSnapshot = {
  exists: boolean;
  data(): ActivationData;
} | null | undefined;

/** 알림 id 접두어. 사건 종류를 말한다. */
export const SCHEDULE_CONFLICT_NOTIF_PREFIX = "schedule_conflict_autocancel";

/**
 * 관계 문서의 활성화 세대. 필드가 없는 legacy 문서는 0 으로 읽는다 —
 * backfill 을 요구하지 않는다.
 *
 * 숫자가 아니거나 음수·NaN 이면 0 으로 떨어진다. 사건 id 가 `NaN` 이나
 * `undefined` 같은 문자열을 품으면 그 자체로 충돌 원인이 된다.
 *
 * @param {ActivationData} d 관계 문서 데이터
 * @return {number} 활성화 세대 (없으면 0)
 */
export function activationGeneration(d: ActivationData): number {
  const raw = d?.activationGeneration;
  if (typeof raw !== "number") return 0;
  if (!Number.isFinite(raw) || raw < 0) return 0;
  return Math.floor(raw);
}

/**
 * 이번 활성화가 쓸 세대.
 *
 * 문서가 없으면 0(첫 활성화), 있으면 이전 값 + 1.
 *
 * **읽은 snapshot 에서 계산한다** — `increment(1)` 이 아니다. 그래야
 * contention 으로 transaction 이 재실행돼도 같은 snapshot 에서 같은 값이
 * 나오고, 같은 사건의 알림 id 도 같다. callable 재시도는 호출부의 중복
 * guard(`already-exists`)가 막으므로 세대가 두 번 오르지 않는다.
 *
 * @param {ActivationSnapshot} snap 같은 transaction 에서 읽은 관계 문서
 * @return {number} 이번 활성화의 세대
 */
export function nextActivationGeneration(snap: ActivationSnapshot): number {
  if (!snap || !snap.exists) return 0;
  return activationGeneration(snap.data()) + 1;
}

/**
 * 일정 겹침 자동취소 알림의 **사건 id**.
 *
 * 문서 identity 하나로는 부족하다(위 설명). 세대를 붙여 사건마다 다른 문서가
 * 되게 하고, 같은 사건의 재시도는 같은 문서로 수렴하게 한다. id 구성의 주인은
 * 이 함수 하나다 — writer 별로 문자열을 짓지 않는다.
 *
 * 무작위 값을 섞지 않는다. 재시도마다 새 id 가 생기면 중복 푸시가 된다.
 *
 * @param {string} applicationId 접힌 관계 문서 id
 * @param {number} generation 그 관계의 활성화 세대
 * @return {string} 결정적 알림 문서 id
 */
export function scheduleConflictNotificationId(
  applicationId: string, generation: number
): string {
  const g = Number.isFinite(generation) && generation >= 0 ?
    Math.floor(generation) : 0;
  return `${SCHEDULE_CONFLICT_NOTIF_PREFIX}_${applicationId}_g${g}`;
}
