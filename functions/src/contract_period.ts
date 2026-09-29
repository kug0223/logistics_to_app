/**
 * [CONTRACT-PERIOD-RULE] 계약 기간 종료일 — **하나의 규칙**(서버 쪽 구현).
 *
 * 종료일을 만드는 식이 두 벌이었다. 확정 핸들러가 `d.setMonth(d.getMonth() + N)`
 * 만으로 계산해서 `- 1일` 도 월말 clamp 도 없었고, 게다가 **UTC 성분**으로
 * 계산해 KST 자정 기산일이 전날로 읽혔다. 지원자는 확정 전에 본 날짜와
 * 다른 날짜로 계약서를 받았다.
 * (감사: `docs/r7-contract-monthend-audit.md`)
 *
 * 언어가 둘이라 구현 파일은 둘일 수밖에 없다. 그래서 **규칙에 버전을 박고
 * 검증 벡터를 공유한다** — 한쪽만 바뀌면 벡터 대조가 깨진다.
 *   · 이 파일 (TypeScript)
 *   · `lib/utils/contract_period.dart` (Dart)
 *   · 공유 벡터 `test/fixtures/contract_period_vectors.json`
 *
 * ## 규칙 v2 — KST 달력일 · 초일산입 · 민법 160②③
 *
 *   일 단위 (`15days`)
 *     마지막 유효일 = 시작일 + (15 - 1)일        · 시작일 포함 15일
 *
 *   월·연 단위 (`1month`/`3months`/`6months`/`1year`) — 민법 제160조
 *     ② 해당일이 있으면 → 마지막 유효일 = **해당일의 전일**
 *     ③ 최종 월에 해당일이 없으면 → 마지막 유효일 = **그 월의 말일**
 *
 *   `custom` 은 이 규칙을 쓰지 않는다 — `rangeEnd` 가 고정값이다.
 *
 * 계산의 자(尺)는 **KST 달력일**이다. 저장된 instant 의 UTC 성분을 그대로
 * 읽지 않는다 — `slot.date`/`workDate` 처럼 KST 자정으로 저장된 값은 UTC 로
 * 전날이기 때문이다. 결과도 KST 자정 instant 로 돌려준다(저장소의 DATE_ONLY
 * 관례이고, Dart 쪽 `contractPeriodEndInstant` 와 같은 값이다).
 */

export const CONTRACT_PERIOD_RULE_VERSION = "v2-kst-civil-160";

const KST_OFFSET_MS = 9 * 60 * 60 * 1000;

const MONTHS_OF: Record<string, number> = {
  "1month": 1,
  "3months": 3,
  "6months": 6,
  "1year": 12,
};

const DAYS_OF: Record<string, number> = {
  "15days": 15,
};

export const CONTRACT_PRESET_PERIOD_TYPES = new Set<string>([
  ...Object.keys(DAYS_OF),
  ...Object.keys(MONTHS_OF),
]);

/** KST 달력일 성분. */
export interface KstDay {
  year: number;
  month: number; // 1-12
  day: number;
}

/**
 * instant(ms) → KST 달력일 성분.
 * @param {number} ms 절대 시각(epoch ms).
 * @return {KstDay} 그 순간의 KST 달력일.
 */
export function kstDayOfMs(ms: number): KstDay {
  const shifted = new Date(ms + KST_OFFSET_MS);
  return {
    year: shifted.getUTCFullYear(),
    month: shifted.getUTCMonth() + 1,
    day: shifted.getUTCDate(),
  };
}

/**
 * KST 달력일 → 그 날의 KST 자정 instant(ms).
 * `srvKstDayStartMs` 가 돌려주는 값과 같다.
 * @param {KstDay} d KST 달력일.
 * @return {number} 그 날 KST 00:00 의 epoch ms.
 */
export function kstDayToMs(d: KstDay): number {
  return Date.UTC(d.year, d.month - 1, d.day) - KST_OFFSET_MS;
}

/**
 * 그 달의 말일.
 * @param {number} year 연.
 * @param {number} month 월(1-12).
 * @return {number} 말일의 일자.
 */
function lastDayOfMonth(year: number, month: number): number {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

/**
 * 계약 기간의 **마지막 유효일**을 KST 달력일로 돌려준다.
 * @param {KstDay} start 계약 시작일(KST 달력일). 초일산입 — 이 날이 첫날이다.
 * @param {string|undefined|null} periodType TO 의 `contractPeriodType`.
 * @return {KstDay|null} 마지막 유효일. 규칙 밖의 유형(`custom`, 알 수 없는
 *   값)이면 null — 모르는 것을 지어내지 않는다.
 */
export function contractPeriodEndKstDay(
  start: KstDay,
  periodType: string | undefined | null
): KstDay | null {
  if (!periodType) return null;

  const days = DAYS_OF[periodType];
  if (days !== undefined) {
    // 초일산입 — 시작일이 첫날이므로 마지막 날은 +(N-1).
    const ms = Date.UTC(start.year, start.month - 1, start.day + days - 1);
    const d = new Date(ms);
    return {
      year: d.getUTCFullYear(),
      month: d.getUTCMonth() + 1,
      day: d.getUTCDate(),
    };
  }

  const months = MONTHS_OF[periodType];
  if (months === undefined) return null;

  // 해당일(anniversary) — 원 기산일의 **일자를 보존**한다.
  const rawMonth = start.month + months;
  const targetYear = start.year + Math.floor((rawMonth - 1) / 12);
  const targetMonth = ((rawMonth - 1) % 12) + 1;
  const lastDay = lastDayOfMonth(targetYear, targetMonth);

  if (start.day > lastDay) {
    // ③ 최종 월에 해당일이 없다 → 그 월의 말일로 만료.
    return {year: targetYear, month: targetMonth, day: lastDay};
  }
  // ② 해당일의 전일.
  const prev = new Date(
    Date.UTC(targetYear, targetMonth - 1, start.day) - 24 * 60 * 60 * 1000
  );
  return {
    year: prev.getUTCFullYear(),
    month: prev.getUTCMonth() + 1,
    day: prev.getUTCDate(),
  };
}

/**
 * 시작 instant(ms) → 종료일의 **KST 자정 instant(ms)**.
 * @param {number} startMs 계약 시작일에 해당하는 절대 시각.
 * @param {string|undefined|null} periodType TO 의 `contractPeriodType`.
 * @return {number|null} 마지막 유효일 KST 00:00 의 epoch ms.
 *   규칙 밖의 유형이면 null.
 */
export function contractPeriodEndMs(
  startMs: number,
  periodType: string | undefined | null
): number | null {
  const end = contractPeriodEndKstDay(kstDayOfMs(startMs), periodType);
  return end === null ? null : kstDayToMs(end);
}
