// [R7-LEGAL.1A] 저장되는 동의는 **사용자가 실제로 고른 것**이어야 한다.
//
//   writer 가 클라이언트 payload 를 그대로 받아 `termsConsent` 맵을 통째로
//   교체하고 있었다. 그래서 두 가지가 깨졌다.
//
//     · 이번 호출에 없는 항목은 기록에서 사라진다(맵 교체).
//     · 어떤 id·어떤 version 이든 그대로 저장된다(정의되지 않은 항목 주입).
//
//   그리고 `termsConsentAt` 은 호출이 성공하기만 하면 찍혔다 — 필수 약관을
//   전부 거부해도 "동의 시각"이 생겼고, 외국인 가입은 그 값을 보고 계정을
//   active 로 올린다.
//
//   이 모듈은 그 세 판단만 한다. Firestore·admin SDK 를 쓰지 않는 순수
//   함수라 실행으로 확인할 수 있다.
//
//   동의 **이력**(버전별 누적)은 여기서 만들지 않는다 — LEGAL.1B 의 몫이다.
//   지금은 항목당 한 건을 유지하되, 건드리지 않은 항목을 보존한다.

/** `app_settings/legal_terms.items[]` 중 이 판단에 필요한 것만. */
export type ActiveLegalItem = {
  id: string;
  version: string;
  isRequired: boolean;
  /** [LEGAL-1B] 이 항목이 지금 가리키는 **발행본**. 증거가 참조할 신원이다. */
  revisionId?: string;
};

/** 클라이언트가 보낸 한 건. 무엇이든 올 수 있다고 본다. */
export type IncomingConsent = {agreed?: unknown; version?: unknown};

/** 이미 저장돼 있는 한 건. */
export type StoredConsent = {agreed?: unknown; version?: unknown};

/** 저장이 확정된 한 건. */
export type ConsentUpdate = {
  agreed: boolean;
  version: string;
  /** [LEGAL-1B] 어떤 발행본에 대한 선택인가. 없으면 version 으로 유도한다. */
  revisionId: string;
};

export type SanitizeResult = {
  /** 저장할 항목. key 는 검증된 legal item id 다. */
  updates: Record<string, ConsentUpdate>;
  /** 정의되지 않았거나 모양이 틀려 버린 key. */
  dropped: string[];
  /** 현재 활성 버전과 다른 버전을 보낸 key. */
  staleVersions: string[];
};

/**
 * legal item id 로 쓸 수 있는 모양인가.
 *
 * Firestore dotted field path 로 쓰이므로 `.` 과 대괄호를 허용하지 않는다.
 * 허용하면 `termsConsent.a.b` 같은 경로로 엉뚱한 자리를 쓸 수 있다.
 *
 * @param {unknown} id 검사할 값
 * @return {boolean} 쓸 수 있으면 true
 */
export function isValidConsentItemId(id: unknown): id is string {
  return typeof id === "string" && /^[A-Za-z0-9_-]{1,64}$/.test(id);
}

/**
 * 클라이언트 payload 를 현재 활성 약관에 비춰 걸러 낸다.
 *
 * 규칙:
 *   · 정의되지 않은 id → 버린다(주입 차단). 호출 자체는 실패시키지 않는다.
 *   · `agreed` 가 boolean 이 아니면 버린다 — 모르는 것을 동의로 읽지 않는다.
 *   · version 이 현재 활성 버전과 다르면 `staleVersions` 로 보고한다.
 *     사용자가 본 글과 지금 글이 다르다는 뜻이므로 저장하지 않는다.
 *   · 이미 `agreed=true` 인 항목을 false 로 내리는 요청은 버린다(기존 보호).
 *
 * @param {object} input 입력
 * @param {Array<[string, IncomingConsent]>} input.entries 클라이언트 payload
 * @param {ActiveLegalItem[]} input.activeItems 현재 활성 약관
 * @param {Record<string, StoredConsent>} input.existing 저장된 동의
 * @return {SanitizeResult} 걸러 낸 결과
 */
export function sanitizeConsentEntries(input: {
  entries: Array<[string, IncomingConsent]>;
  activeItems: ActiveLegalItem[];
  existing: Record<string, StoredConsent>;
}): SanitizeResult {
  const {entries, activeItems, existing} = input;
  const byId = new Map(activeItems.map((i) => [i.id, i]));

  const updates: Record<string, ConsentUpdate> = {};
  const dropped: string[] = [];
  const staleVersions: string[] = [];

  for (const [rawKey, rawValue] of entries) {
    if (!isValidConsentItemId(rawKey)) {
      dropped.push(String(rawKey).slice(0, 64));
      continue;
    }
    const item = byId.get(rawKey);
    if (!item) {
      // 현재 활성 약관이 아니다 — 정의되지 않은 항목을 만들지 않는다.
      dropped.push(rawKey);
      continue;
    }
    const agreed = rawValue?.agreed;
    if (typeof agreed !== "boolean") {
      dropped.push(rawKey);
      continue;
    }
    const version = rawValue?.version;
    if (typeof version !== "string" || version !== item.version) {
      // 사용자가 본 버전과 지금 버전이 다르다. 지금 버전으로 바꿔 저장하면
      // 보지 않은 글에 동의한 것이 된다.
      staleVersions.push(rawKey);
      continue;
    }
    // 이미 동의한 것을 취소로 뒤집지 않는다(기존 writer 의 보호를 유지).
    if (existing[rawKey]?.agreed === true && !agreed) {
      dropped.push(rawKey);
      continue;
    }
    updates[rawKey] = {
      agreed,
      version: item.version,
      // [LEGAL-1B] 증거는 버전 문자열이 아니라 **발행본**을 가리켜야 한다.
      //   DEV 에서 한 버전 문자열을 네 항목이 공유하고 있었다.
      revisionId: item.revisionId ?? `${item.id}__${item.version}`,
    };
  }

  return {updates, dropped, staleVersions};
}

/**
 * 현재 필수 약관이 **전부** 충족됐는가.
 *
 * 저장된 것과 이번에 저장할 것을 합쳐서 본다. 버전이 다른 과거 동의는
 * 충족으로 세지 않는다 — 그 동의는 다른 글에 대한 것이다.
 *
 * `termsConsentAt`(법적 타임스탬프)과 외국인 active 전환이 이 값에 달려
 * 있다. 호출이 성공했다는 사실만으로 찍으면, 전부 거부해도 시각이 생긴다.
 *
 * @param {object} input 입력
 * @param {ActiveLegalItem[]} input.activeItems 현재 활성 약관
 * @param {Record<string, StoredConsent>} input.existing 저장된 동의
 * @param {Record<string, ConsentUpdate>} input.updates
 *   이번에 저장할 동의
 * @return {boolean} 필수가 전부 충족되면 true
 */
export function allRequiredSatisfied(input: {
  activeItems: ActiveLegalItem[];
  existing: Record<string, StoredConsent>;
  updates: Record<string, ConsentUpdate>;
}): boolean {
  const {activeItems, existing, updates} = input;
  return activeItems
    .filter((i) => i.isRequired)
    .every((i) => {
      const fresh = updates[i.id];
      if (fresh) return fresh.agreed === true && fresh.version === i.version;
      const prev = existing[i.id];
      return prev?.agreed === true && prev?.version === i.version;
    });
}

/**
 * `tx.update` 에 넘길 dotted field path 로 바꾼다.
 *
 * 맵을 통째로 넘기면 이번 호출에 없는 항목이 사라진다. 경로 단위로 쓰면
 * 건드리지 않은 항목이 그대로 남는다.
 *
 * @param {Record<string, ConsentUpdate>} updates 저장할 동의
 * @param {unknown} agreedAt 서버 타임스탬프 sentinel
 * @return {Record<string, unknown>} dotted path → 값
 */
export function toDottedUpdate(
  updates: Record<string, ConsentUpdate>,
  agreedAt: unknown,
): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [id, value] of Object.entries(updates)) {
    // id 는 sanitize 를 통과한 것만 들어온다 — `.` 이 없음이 보장된다.
    out[`termsConsent.${id}`] = {
      agreed: value.agreed,
      version: value.version,
      revisionId: value.revisionId,
      agreedAt,
    };
  }
  return out;
}
