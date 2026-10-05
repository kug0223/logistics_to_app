/**
 * 장기 약속의 **날짜 판정** — canonical 한 곳.
 *
 * [R7-APPLICATION-LIFECYCLE.1C.1]
 *
 * ── 감사 경위 ───────────────────────────────────────────────────
 *   같은 장기 약속의 시작일을 네 자리가 서로 다르게 읽고 있었다.
 *
 *     근태·배치 (`srvLongTermEligibleOnDay`)
 *       desiredStartDate ?? workDate, 희망일이 없으면 confirmedAt 으로 보정
 *     좌석 확정 엔진 (`_isConflictShortTerm`/`_isConflictLongTerm`)
 *       desiredStartDate ?? workDate 의 **raw millis**, 확정일 보정 없음
 *     지원 충돌 (`callableApplyToTO` Policy X)
 *       **workDate** 만 — 희망 시작일을 아예 보지 않았다
 *
 *   그래서 10/15 부터 시작하는 약속을 지원 서버만 10/01 부터라고 추측해
 *   10/10 의 정상 지원을 "일정 충돌" 로 거부할 수 있었다. 약속의 시작일은
 *   하나여야 한다 — 같은 사건을 네 코드가 다르게 말하면 어느 쪽이 맞는지
 *   사용자가 알 길이 없다.
 *
 *   날짜 비교도 두 벌이었다. 이 모듈의 자(尺)는 **KST 달력일**이다
 *   (`contract_period.ts` 와 같은 기준). 서버 로컬 시간대의 달력 성분
 *   (`getFullYear`/`getMonth`/`getDate`)을 business date 로 쓰지 않는다 —
 *   KST 자정으로 저장된 instant 는 UTC 로 **전날**이고, `confirmedAt` 처럼
 *   시각이 있는 값은 00:00~09:00 KST 구간에서 하루가 갈린다.
 *
 * ── 규칙 ────────────────────────────────────────────────────────
 *   effectiveStart = desiredStartDate ?? workDate
 *     desiredStartDate 가 **없을 때만** confirmedAt(KST 일)로 한 번 더 민다
 *   effectiveEnd   = actualResignDate ?? workEndDate   (양끝 inclusive)
 *   추가근무일(extraWorkDates)이 휴무일(leaveDates)보다 먼저다
 *   그 외에는 workDays(한글 요일) 멤버십
 *
 * 이 파일은 **순수**하다 — Firestore·admin SDK 를 쓰지 않고 `toDate()` 만
 * 요구한다. 그래서 행동을 직접 테스트할 수 있다
 * (`node functions/test/commitment_dates.test.js`).
 */

/** `Timestamp` 처럼 `toDate()` 를 주는 값. admin SDK 에 묶이지 않는다. */
export interface DateLike {
  toDate(): Date;
}

export const KST_OFFSET_MS = 9 * 3600 * 1000;

export const KST_WEEKDAY_KO = ["일", "월", "화", "수", "목", "금", "토"];

/** 종료일을 **모르는** 약속의 방어적 상한 — 열린 구간으로 본다. */
export const OPEN_ENDED_DAY_NUM = 99991231;

/**
 * KST 달력일을 `YYYYMMDD` 정수로. 비교·저장에 쓰는 canonical 자(尺).
 * @param {Date} d 대상 instant
 * @return {number} KST 달력일 YYYYMMDD
 */
export function kstDateNum(d: Date): number {
  const kst = new Date(d.getTime() + KST_OFFSET_MS);
  return (
    kst.getUTCFullYear() * 10000 +
    (kst.getUTCMonth() + 1) * 100 +
    kst.getUTCDate()
  );
}

/**
 * KST 달력일의 한글 요일.
 * @param {Date} d 대상 instant
 * @return {string} 한글 요일
 */
export function kstWeekdayKo(d: Date): string {
  const kst = new Date(d.getTime() + KST_OFFSET_MS);
  return KST_WEEKDAY_KO[kst.getUTCDay()];
}

const asDate = (v: unknown): Date | undefined => {
  const t = v as DateLike | undefined;
  if (!t || typeof t.toDate !== "function") return undefined;
  const d = t.toDate();
  return d instanceof Date && !isNaN(d.getTime()) ? d : undefined;
};

/** 근무 대상이 아닌 이유. caller 의 기존 문구를 보존하기 위해 구분한다. */
export type WorkerDayReason =
  | "ELIGIBLE"
  | "BEFORE_START"
  | "AFTER_RESIGN"
  | "AFTER_END"
  | "NO_END"
  | "LEAVE"
  | "NON_WORKDAY";

/**
 * 장기 약속의 **시작일**(KST YYYYMMDD).
 *
 * 날짜를 하나도 모르면 0 — 모든 날짜가 "시작 이후" 가 된다(기존 동작).
 * @param {Record<string, unknown>} appData 지원서 문서
 * @return {number} KST YYYYMMDD
 */
export function longTermEffectiveStartNum(
  appData: Record<string, unknown>
): number {
  const desired = asDate(appData["desiredStartDate"]);
  const workDate = asDate(appData["workDate"]);
  let startNum = desired ?
    kstDateNum(desired) :
    (workDate ? kstDateNum(workDate) : 0);
  if (!desired) {
    const confirmed = asDate(appData["confirmedAt"]);
    if (confirmed) {
      const cNum = kstDateNum(confirmed);
      if (cNum > startNum) startNum = cNum;
    }
  }
  return startNum;
}

/**
 * 겹침 판정용 장기 약속 구간(KST YYYYMMDD).
 *
 * 근무일 판정과 **시작·종료 식은 같다**. 다른 것은 종료일을 모르는 경우뿐이다.
 *   근무일 판정: 종료를 모르면 근무일이 아니다(`NO_END`) — 모르는 것을
 *     근거로 출근·급여를 만들지 않는다.
 *   겹침 판정: 종료를 모르면 **끝났다고 단정하지 않는다** — 열린 구간이다.
 *     `callableApplyToTO` 는 장기 지원에 `workEndDateMs` 를 요구하지 않으므로
 *     종료 없는 장기 약속이 writer 로 도달 가능하고, 그것을 "약속 없음" 으로
 *     보면 같은 시간 이중 약속이 성립한다.
 * @param {Record<string, unknown>} appData 지원서 문서
 * @return {{startNum: number, endNum: number, endKnown: boolean}} KST 구간
 */
export function longTermCommitmentRange(
  appData: Record<string, unknown>
): {startNum: number; endNum: number; endKnown: boolean} {
  const end = asDate(appData["actualResignDate"]) ??
    asDate(appData["workEndDate"]);
  return {
    startNum: longTermEffectiveStartNum(appData),
    endNum: end ? kstDateNum(end) : OPEN_ENDED_DAY_NUM,
    endKnown: !!end,
  };
}

/**
 * 이 장기 지원서의 근로자가 그 KST 날짜에 **근무 대상인가.**
 *
 * status(CONFIRMED·CONTRACT_PENDING)는 보지 않는다 — lifecycle gate 는
 * caller 의 책임이고, 여기에 넣으면 같은 정책이 두 곳에 생긴다.
 * @param {Record<string, unknown>} appData 지원서 문서
 * @param {number} dayNum 대상 날짜 KST YYYYMMDD
 * @param {string} dayWkd 대상 날짜 KST 요일 한글
 * @return {{eligible: boolean, reason: WorkerDayReason}} 판정과 이유
 */
export function longTermEligibleOnDay(
  appData: Record<string, unknown>,
  dayNum: number,
  dayWkd: string
): {eligible: boolean; reason: WorkerDayReason} {
  if (dayNum < longTermEffectiveStartNum(appData)) {
    return {eligible: false, reason: "BEFORE_START"};
  }

  const resign = asDate(appData["actualResignDate"]);
  const end = resign ?? asDate(appData["workEndDate"]);
  if (!end) return {eligible: false, reason: "NO_END"};
  if (dayNum > kstDateNum(end)) {
    return {eligible: false, reason: resign ? "AFTER_RESIGN" : "AFTER_END"};
  }

  // 추가근무가 휴무보다 먼저다. 승인 writer 가 교집합을 지우지만, legacy
  //   dual-state 가 남아 있어도 기존 reader 와 같은 답을 낸다.
  const hasDay = (k: string): boolean => {
    const arr = appData[k];
    if (!Array.isArray(arr)) return false;
    return (arr as unknown[]).some((t) => {
      const d = asDate(t);
      return !!d && kstDateNum(d) === dayNum;
    });
  };
  if (hasDay("extraWorkDates")) return {eligible: true, reason: "ELIGIBLE"};
  if (hasDay("leaveDates")) return {eligible: false, reason: "LEAVE"};

  const wd = appData["workDays"] as string[] | undefined;
  if (!Array.isArray(wd) || wd.length === 0 || !wd.includes(dayWkd)) {
    return {eligible: false, reason: "NON_WORKDAY"};
  }
  return {eligible: true, reason: "ELIGIBLE"};
}

/**
 * 이 장기 약속이 그 KST 날짜를 **차지하는가** — 겹침 판정용.
 *
 * canonical 근무일 판정을 그대로 쓴다. 종료일을 모르는 경우만 열린 구간으로
 * 보정한다(위 `longTermCommitmentRange` 주석의 이유).
 * @param {Record<string, unknown>} appData 지원서 문서
 * @param {number} dayNum 대상 날짜 KST YYYYMMDD
 * @param {string} dayWkd 대상 날짜 KST 요일 한글
 * @return {boolean} 그 날짜에 이 약속이 있는가
 */
export function longTermCommitmentOnDay(
  appData: Record<string, unknown>,
  dayNum: number,
  dayWkd: string
): boolean {
  const r = longTermEligibleOnDay(appData, dayNum, dayWkd);
  if (r.eligible) return true;
  if (r.reason !== "NO_END") return false;
  const openEnded: DateLike = {
    toDate: () => new Date(Date.UTC(9999, 11, 31)),
  };
  return longTermEligibleOnDay(
    {...appData, workEndDate: openEnded, actualResignDate: undefined},
    dayNum,
    dayWkd
  ).eligible;
}

/**
 * `YYYYMMDD` → 그 달력일의 UTC 자정 ms. 날짜 산술에만 쓴다.
 * @param {number} n KST 달력일 YYYYMMDD
 * @return {number} 그 달력일의 UTC 자정 ms
 */
function dayNumToUtcMs(n: number): number {
  const y = Math.floor(n / 10000);
  const m = Math.floor(n / 100) % 100;
  return Date.UTC(y, m - 1, n % 100);
}

/**
 * UTC 자정 ms → `YYYYMMDD`. 그 날의 요일은 `getUTCDay()` 가 바로 준다.
 * @param {number} ms UTC 자정 ms
 * @return {number} 달력일 YYYYMMDD
 */
function utcMsToDayNum(ms: number): number {
  const d = new Date(ms);
  return d.getUTCFullYear() * 10000 + (d.getUTCMonth() + 1) * 100 +
    d.getUTCDate();
}

const DAY_MS = 24 * 3600 * 1000;

/**
 * 그 달력일의 한글 요일 — 날짜 산술용(UTC 자정 기준).
 * @param {number} dayNum 달력일 YYYYMMDD
 * @return {string} 한글 요일
 */
function wkdOfDayNum(dayNum: number): string {
  return KST_WEEKDAY_KO[new Date(dayNumToUtcMs(dayNum)).getUTCDay()];
}

/**
 * 지원서의 날짜 배열(`extraWorkDates`·`leaveDates`)을 KST 달력일로.
 * @param {Record<string, unknown>} appData 지원서 문서
 * @param {string} key 배열 필드 이름
 * @return {number[]} KST 달력일 목록
 */
function overrideDayNums(
  appData: Record<string, unknown>, key: string
): number[] {
  const arr = appData[key];
  if (!Array.isArray(arr)) return [];
  const out: number[] = [];
  for (const t of arr as unknown[]) {
    const d = asDate(t);
    if (d) out.push(kstDateNum(d));
  }
  return out;
}

/**
 * 두 **장기** 약속이 실제로 같은 날 겹치는가 — 겹치는 **첫 날**을 돌려준다.
 *
 * [R7-APPLICATION-LIFECYCLE.1C.1A]
 *
 * ── 왜 필요했나 ─────────────────────────────────────────────────
 *   장기 ↔ 장기 겹침을 "기간 교집합 + 근무요일 교집합" 으로만 보고 있었다.
 *   그런데 장기 근무의 실제 약속은 원래 근무요일만으로 결정되지 않는다 —
 *   관리자가 승인한 **추가근무(EXTRA_WORK)** 는 비근무일을 실제 근무일로
 *   만들고, **휴무(NO_WORK/LEAVE)** 는 근무일을 지운다. 근태·좌석·배치는
 *   이미 그 사실을 반영하는데(`longTermEligibleOnDay`) 겹침 판정만 몰랐다.
 *
 *     추가근무 토요일에 겹치는 약속을 **놓치고**(이중 약속 성립)
 *     휴무로 비워진 월요일의 정상 지원을 **막는다**(과잉 차단)
 *
 * ── 무한 iteration 을 하지 않는다 ───────────────────────────────
 *   두 기간의 교집합을 수년간 하루씩 훑지 않는다. 두 축으로 나눈다.
 *
 *   ① 공통 근무요일 — 교집합 안에서 그 요일의 날은 **휴무가 아니면** 반드시
 *      둘 다 근무다. 실패는 휴무로만 생기므로, 공통 요일 날짜를
 *      `|leaveA| + |leaveB| + 1` 개만 보면 생존하는 날이 있는지 결정된다.
 *   ② 추가근무 날짜 — 양쪽 배열의 합집합(유한)만 확인한다. 공통 요일이
 *      아니어도 이쪽에서 잡힌다.
 *
 *   그래서 비용은 두 배열 크기에 비례하고 기간 길이와 무관하다.
 *
 * @param {Record<string, unknown>} a 기존 약속
 * @param {Record<string, unknown>} b 후보(신규 장기)
 * @return {{dayNum: number, wkd: string, viaOverride: boolean} | null}
 *   겹치는 첫 날(KST YYYYMMDD)과 그 요일. 없으면 null.
 */
export function longTermConflictDay(
  a: Record<string, unknown>,
  b: Record<string, unknown>
): {dayNum: number; wkd: string; viaOverride: boolean} | null {
  const ra = longTermCommitmentRange(a);
  const rb = longTermCommitmentRange(b);
  const lo = Math.max(ra.startNum, rb.startNum);
  const hi = Math.min(ra.endNum, rb.endNum);
  if (lo > hi) return null;

  const both = (dayNum: number, wkd: string): boolean =>
    longTermCommitmentOnDay(a, dayNum, wkd) &&
    longTermCommitmentOnDay(b, dayNum, wkd);

  // ── ① 공통 근무요일 ────────────────────────────────────────────
  const daysA = Array.isArray(a["workDays"]) ? (a["workDays"] as string[]) : [];
  const daysB = Array.isArray(b["workDays"]) ? (b["workDays"] as string[]) : [];
  const common = daysA.filter((d) => daysB.includes(d));
  if (common.length > 0) {
    const budget = overrideDayNums(a, "leaveDates").length +
      overrideDayNums(b, "leaveDates").length + 1;
    let seen = 0;
    for (let ms = dayNumToUtcMs(lo);
      ms <= dayNumToUtcMs(hi) && seen < budget;
      ms += DAY_MS) {
      const wkd = KST_WEEKDAY_KO[new Date(ms).getUTCDay()];
      if (!common.includes(wkd)) continue;
      seen++;
      const dayNum = utcMsToDayNum(ms);
      if (both(dayNum, wkd)) return {dayNum, wkd, viaOverride: false};
    }
  }

  // ── ② 추가근무 날짜 ────────────────────────────────────────────
  const extras = [
    ...overrideDayNums(a, "extraWorkDates"),
    ...overrideDayNums(b, "extraWorkDates"),
  ].sort((x, y) => x - y);
  for (const dayNum of extras) {
    if (dayNum < lo || dayNum > hi) continue;
    const wkd = wkdOfDayNum(dayNum);
    if (both(dayNum, wkd)) return {dayNum, wkd, viaOverride: true};
  }

  return null;
}

/**
 * 이 지원서가 **장기 약속**인가 — 분류도 한 곳이다.
 *
 * 좌석 엔진은 `applicationType === "longTerm"` 를 보고 있었는데 Firestore
 * 필드는 `type`(`"long_term"`)이다. 그 조건은 실제 문서에서 한 번도 맞지
 * 않았고 `workDays` 폴백에만 의존했다.
 * @param {Record<string, unknown>} appData 지원서 문서
 * @return {boolean} 장기 약속 여부
 */
export function isLongTermCommitment(
  appData: Record<string, unknown>
): boolean {
  return appData["type"] === "long_term" ||
    (Array.isArray(appData["workDays"]) &&
      (appData["workDays"] as string[]).length > 0);
}
