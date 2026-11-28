/**
 * [BL284-01 · 판정288 A안] 퇴사 요청 집계용 서버 전용 파생 필드 — 순수 계산(외부 import 0).
 *
 *   application 문서의 두 필드:
 *     resignRetroRequest  : boolean          — 소급 요청(효력일 KST 일 < 접수 KST 일)
 *     resignAutoApproveAt : Timestamp | null — 비소급이면 ceilKSTMidnight(r + 72h), 소급이면 null
 *
 *   r = 성공한 요청 거래 attempt 안에서 서버가 한 번 취한 접수시각(= resignRequestedAt 에 같은 값).
 *   ceil 은 이미 KST 00:00:00.000000000 이면 그 자정을 유지하고, 아니면 바로 다음 KST 자정이다.
 *   scheduler 는 autoAt <= 오늘 KST 자정, 홈 '곧 자동 승인' 은 autoAt <= 다음 KST 자정.
 *   (동등식: ceil(r+3d) <= T ⇔ r <= T−3d · 판정288 resign_boundary_probe.py)
 *
 *   이 모듈은 Timestamp 클래스를 몰라도 되게 {seconds, nanoseconds} 만 본다.
 *   Timestamp 판정(instanceof)은 호출자가 isTs 로 넘긴다 — index.ts · backfill 스크립트가 같은 식을 쓴다.
 */

export interface ResignTsLike {
  readonly seconds: number;
  readonly nanoseconds: number;
}

const DAY_S = 86400;
const KST_S = 9 * 3600;
export const RESIGN_AUTO_APPROVE_DELAY_S = 3 * DAY_S;
// Firestore Timestamp 의 유효 범위(0001-01-01T00:00:00Z ~ 9999-12-31T23:59:59.999999999Z).
const TS_MIN_S = -62135596800;
const TS_MAX_S = 253402300799;

/** KST 달력 일 번호(UTC epoch 일 + 9h 이동). nanoseconds 는 같은 초 안이라 일 경계를 바꾸지 않는다. */
export function resignKstDayNumber(t: ResignTsLike): number {
  return Math.floor((t.seconds + KST_S) / DAY_S);
}

/** (seconds, nanoseconds) 이상인 가장 이른 KST 자정의 UTC epoch 초. 정확히 자정이면 그대로. */
export function resignCeilKstMidnightSeconds(seconds: number, nanoseconds: number): number {
  const k = seconds + KST_S;
  const rem = ((k % DAY_S) + DAY_S) % DAY_S;
  const midK = rem === 0 && nanoseconds === 0 ? k : k - rem + DAY_S;
  return midK - KST_S;
}

/** 비소급 요청의 자동 승인 경계(UTC epoch 초) = ceilKSTMidnight(r + 72h). */
export function resignAutoApproveAtSeconds(r: ResignTsLike): number {
  return resignCeilKstMidnightSeconds(r.seconds + RESIGN_AUTO_APPROVE_DELAY_S, r.nanoseconds);
}

/** 소급 요청 = 효력일 KST 일 < 접수 KST 일. */
export function resignIsRetro(effectiveDate: ResignTsLike, requestedAt: ResignTsLike): boolean {
  return resignKstDayNumber(effectiveDate) < resignKstDayNumber(requestedAt);
}

/** 두 파생값(Timestamp 생성은 호출자). */
export function resignDerived(
  effectiveDate: ResignTsLike, requestedAt: ResignTsLike
): {retro: boolean; autoAtSeconds: number | null} {
  const retro = resignIsRetro(effectiveDate, requestedAt);
  return {retro, autoAtSeconds: retro ? null : resignAutoApproveAtSeconds(requestedAt)};
}

/** 요청 주기 — 필드 부재/null 은 기록 도입 전 요청(0). 그 밖에 음이 아닌 정수가 아니면 NaN(불명). */
export function resignCycleOf(v: unknown): number {
  if (v === undefined || v === null) return 0;
  return typeof v === "number" && Number.isInteger(v) && v >= 0 ? v : NaN;
}

function validTs(v: unknown, isTs: (x: unknown) => x is ResignTsLike): v is ResignTsLike {
  if (!isTs(v)) return false;
  const s = v.seconds;
  const n = v.nanoseconds;
  return Number.isInteger(s) && s >= TS_MIN_S && s <= TS_MAX_S &&
    Number.isInteger(n) && n >= 0 && n <= 999999999 &&
    // ceil(r+72h) 도 유효 범위 안이어야 한다(overflow 방지).
    s + RESIGN_AUTO_APPROVE_DELAY_S + DAY_S <= TS_MAX_S;
}

export type ResignPendingClass =
  | {state: "VALID"; retro: boolean; autoAtSeconds: number | null}
  | {state: "MISMATCH"; retro: boolean; autoAtSeconds: number | null; reasons: string[]}
  | {state: "SOURCE_INVALID"; reasons: string[]};

/**
 * PENDING 퇴사 요청 문서의 완전성 분류.
 *   SOURCE_INVALID : 원필드(요청시각·효력일·주기) 자체가 불량 — 파생값을 만들지 않는다(가짜값 0).
 *   MISMATCH       : 원필드는 정상인데 두 파생 필드가 없거나·형이 틀리거나·값이 다르다 — backfill 이 고칠 대상.
 *   VALID          : 원필드·파생 필드가 모두 정확하다.
 * resignStatus 판정은 호출자가 한다(이 함수는 PENDING 문서라는 전제).
 */
export function resignClassifyPending(
  d: Record<string, unknown>, isTs: (x: unknown) => x is ResignTsLike
): ResignPendingClass {
  const src: string[] = [];
  const req = d["resignRequestedAt"];
  const eff = d["resignRequestDate"];
  if (!validTs(req, isTs)) src.push(req === undefined || req === null ? "SOURCE_REQUESTED_AT_MISSING" : "SOURCE_REQUESTED_AT_TYPE");
  if (!validTs(eff, isTs)) src.push(eff === undefined || eff === null ? "SOURCE_REQUEST_DATE_MISSING" : "SOURCE_REQUEST_DATE_TYPE");
  if (Number.isNaN(resignCycleOf(d["resignDecisionCycle"]))) src.push("SOURCE_CYCLE_TYPE");
  if (src.length > 0) return {state: "SOURCE_INVALID", reasons: src};

  const exp = resignDerived(eff as ResignTsLike, req as ResignTsLike);
  const bad: string[] = [];
  const hasRetro = Object.prototype.hasOwnProperty.call(d, "resignRetroRequest");
  const hasAuto = Object.prototype.hasOwnProperty.call(d, "resignAutoApproveAt");
  const r = d["resignRetroRequest"];
  const a = d["resignAutoApproveAt"];
  if (!hasRetro) bad.push("RETRO_MISSING");
  else if (typeof r !== "boolean") bad.push("RETRO_TYPE");
  else if (r !== exp.retro) bad.push("RETRO_VALUE");
  if (!hasAuto) bad.push("AUTO_AT_MISSING");
  else if (exp.autoAtSeconds === null) {
    if (a !== null) bad.push(isTs(a) ? "AUTO_AT_VALUE" : "AUTO_AT_TYPE");
  } else if (!isTs(a)) {
    bad.push(a === null ? "AUTO_AT_VALUE" : "AUTO_AT_TYPE");
  } else if (a.seconds !== exp.autoAtSeconds || a.nanoseconds !== 0) {
    bad.push("AUTO_AT_VALUE");
  }
  if (bad.length > 0) return {state: "MISMATCH", retro: exp.retro, autoAtSeconds: exp.autoAtSeconds, reasons: bad};
  return {state: "VALID", retro: exp.retro, autoAtSeconds: exp.autoAtSeconds};
}

/** 후보(스캔 시점)와 거래 fresh 가 같은 퇴사 요청인가 — 주기 + 요청시각(정확 일치). */
export function resignSameRequest(
  cand: Record<string, unknown>, fresh: Record<string, unknown>, isTs: (x: unknown) => x is ResignTsLike
): boolean {
  const c0 = resignCycleOf(cand["resignDecisionCycle"]);
  const c1 = resignCycleOf(fresh["resignDecisionCycle"]);
  if (Number.isNaN(c0) || Number.isNaN(c1) || c0 !== c1) return false;
  const r0 = cand["resignRequestedAt"];
  const r1 = fresh["resignRequestedAt"];
  if (!isTs(r0) || !isTs(r1)) return false;
  return r0.seconds === r1.seconds && r0.nanoseconds === r1.nanoseconds;
}
