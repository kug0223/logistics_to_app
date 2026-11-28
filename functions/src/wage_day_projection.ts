// [SERVER-MERGE-1 §3차 2026-11-26] DEV 11-05 배포 callableGetAdminAttendances(lib ee151358)에 실린
//   `lib/wage_day_projection.js`(DU1 candB v4 · TS 원본 없음)를 이름·식·출력 그대로 TS 로 옮겼다.
//   앱 `lib/screens/business_admin/dialogs/wage_day_candidate.dart` 가 응답의 wageDay·wageApplication·wageWorkDetail 을 읽는다.
//
// [DU1 candB v4 · 후속18 §1.1] v3 + 부모 TO 소유사업장 guard(selectLiveWorkDetail 의 businessId 인자). 그 밖은 v3 그대로.
// [DU1 candB · followup_7 §3] 후보 B — W 급여 일자 요청에 한해, 근태 응답에 **관계 검증된** 지원서·업무 projection 을 붙인다.
//   Firestore 읽기/쓰기 없음 — 지원서·live 업무는 호출자가 주입한다(실제 CF 에서는 서버가 Admin SDK 로 읽어 넣는다). 저장·알림 경로 없음.
import {Timestamp} from "firebase-admin/firestore";
// [v2] 장기 시작/종료는 production 모듈을 그대로 쓴다(복제 없음) — confirmedAt 보정 포함
import {isLongTermCommitment, longTermCommitmentRange, kstDateNum} from "./commitment_dates";

type Doc = Record<string, unknown>;

/** 지원서 projection 후보 allowlist (앱 WageDayClassification.candidateApplicationProjection 과 같은 집합). */
export const WAGE_DAY_APP_FIELDS = [
  "workDate", "appliedAt", "uid", "businessId", "status",
  "toId", "slotId", "workDetailId", "wdId", "selectedWorkType", "startTime", "endTime", "businessName",
  "wage", "wageType", "baseHourlyWage", "baseHourlyWageMode", "breakMinutes",
  "nightAllowanceApplied", "nightIncluded", "taxDeductionType",
];
/** live 업무 정의 projection — 급여창 workDetailTimeMap 소비 필드 + 레거시 지급일정 fallback. */
export const WAGE_DAY_WD_FIELDS = [
  "workType", "startTime", "endTime", "wage", "wageType", "breakMinutes", "shiftType",
  "baseHourlyWage", "baseHourlyWageMode", "nightAllowanceApplied", "nightIncluded", "taxDeductionType",
  "payScheduleType", "payScheduleDay", "payScheduleTime",
];
const KST_MS = 9 * 3600 * 1000;
const DAY_MS = 24 * 3600 * 1000;

/** [start,end) 가 정확히 KST 자정→다음 KST 자정인가. 길이 24h 만으로는 통과시키지 않는다. */
export function isKstDayWindow(startMs: unknown, endMs: unknown): boolean {
  return typeof startMs === "number" && typeof endMs === "number" &&
    Number.isInteger(startMs) && (startMs + KST_MS) % DAY_MS === 0 && endMs - startMs === DAY_MS;
}
const kstDayKey = (ms: number): number => Math.floor((ms + KST_MS) / DAY_MS);
const msOf = (v: unknown): number | undefined =>
  v instanceof Timestamp ? v.toMillis() : (typeof v === "number" ? v : undefined);

export type WageDayReq = {purpose?: unknown; businessId?: unknown; startMs?: unknown; endMs?: unknown; yearMonthGte?: unknown};

/** projection 을 붙여도 되는 요청인가 — 아니면 기존 응답을 **그대로** 둔다(K-only·월·일반 요청 축소 경로 보존). */
export function wageDayOptIn(req: WageDayReq, caller: {canManageWage: boolean}): {ok: true} | {ok: false; reason: string} {
  if (req.purpose !== "wageDay") return {ok: false, reason: "notWagePurpose"};
  if (req.yearMonthGte !== undefined) return {ok: false, reason: "monthRequest"};
  if (!caller.canManageWage) return {ok: false, reason: "notWageAuthority"};
  if (!isKstDayWindow(req.startMs, req.endMs)) return {ok: false, reason: "notKstDay"};
  return {ok: true};
}
const pick = (m: Doc, keys: string[]): Doc => {
  const o: Doc = {};
  for (const k of keys) if (m[k] !== undefined) o[k] = m[k];
  return o;
};

/** 근태 ↔ 지원서 관계. 하나라도 어긋나면 projection 을 붙이지 않는다. */
export function relationOf(att: Doc, app: Doc, businessId: unknown): string | null {
  if (att["businessId"] !== businessId) return "attendanceBusiness";
  if (app["businessId"] !== businessId) return "business";
  if (app["uid"] !== att["userId"]) return "uid";
  const attMs = msOf(att["workDate"]);
  if (attMs === undefined) return "workDate";
  const appType = app["type"];
  const hasWorkDays = Array.isArray(app["workDays"]) && (app["workDays"] as unknown[]).length > 0;
  // 명시 단기('short')인데 workDays 가 있다 — 앱은 단기, 서버 isLongTermCommitment 는 장기. 고르지 않는다.
  if (appType === "short" && hasWorkDays) return "legacyTypeUnknown";
  if (isLongTermCommitment(app)) {
    const r = longTermCommitmentRange(app);
    const dayNum = kstDateNum(new Date(attMs));
    // 종료를 모르면 열린 구간(겹침 판정 의미) — 근무일 판정의 NO_END 를 과거 근태 급여 read 에 붙이지 않는다
    if (dayNum < r.startNum || dayNum > r.endNum) return "longTermRange";
    return null;
  }
  // type·workDays 가 없는데 workEndDate 가 workDate 와 다른 날 — 앱은 장기로 본다, 서버는 단기로 본다. 미지원으로 남긴다.
  // type 이 **없을 때만** — 명시 단기('short')는 앱도 단기라 종료일이 달라도 단기로 본다.
  if (appType === undefined || appType === null) {
    const wdMs = msOf(app["workDate"]);
    const weMs = msOf(app["workEndDate"]);
    if (wdMs !== undefined && weMs !== undefined && kstDayKey(wdMs) !== kstDayKey(weMs)) return "legacyTypeUnknown";
  }
  const appMs = msOf(app["workDate"]);
  if (appMs === undefined || kstDayKey(appMs) !== kstDayKey(attMs)) return "workDate";
  return null;
}
/** 모델 파싱 필수(ApplicationModel.fromMap) — 관계가 맞아도 없으면 후보 입력 불완전. */
export const WAGE_DAY_APP_REQUIRED = ["workDate", "appliedAt"];
/** 급여 입력에 필요한 live 업무 값 — 예정 시각·급여형태·금액. */
export const WAGE_DAY_WD_REQUIRED = ["startTime", "endTime", "wageType", "wage"];

export type WdSelection = {wd: Doc} | {error: string};
/**
 * 지원서가 가리키는 **해당 업무**를 고른다 — 슬롯 workDetails 우선, 비면 TO.
 *   매칭은 production srvMatchWorkDetail 을 그대로 받는다(wdId → composite → 유일 workType, 어긋나면 throw = fail-closed).
 */
export function selectLiveWorkDetail(
  app: Doc, docs: {slot?: Doc; to?: Doc},
  match: (list: unknown[], id: string | undefined, workType: string | undefined) => Doc,
  businessId?: unknown,
): WdSelection {
  // [v4] 부모 소유관계 — app 이 가리키는 TO 가 다른 사업장이면 그 TO·하위 slot 의 업무를 쓰지 않는다.
  if (businessId !== undefined) {
    if (!docs.to) return {error: "parentMissing"};
    if (docs.to["businessId"] !== businessId) return {error: "parentBusinessMismatch"};
  }
  const slotWds = Array.isArray(docs.slot?.["workDetails"]) ? docs.slot!["workDetails"] as unknown[] : [];
  const toWds = Array.isArray(docs.to?.["workDetails"]) ? docs.to!["workDetails"] as unknown[] : [];
  const list = slotWds.length > 0 ? slotWds : toWds;
  if (!docs.slot && !docs.to) return {error: "workDetailDocMissing"};
  const id = (typeof app["workDetailId"] === "string" && app["workDetailId"] as string) ||
    (typeof app["wdId"] === "string" && app["wdId"] as string) || undefined;
  try {
    const wd = match(list, id, app["selectedWorkType"] as string | undefined);
    return Object.keys(wd).length === 0 ? {error: "workDetailNotFound"} : {wd};
  } catch (_e) {
    return {error: "workDetailMismatch"};
  }
}

/**
 * 기존 응답 `{items, limitReached}` 에 opt-in 일 때만 `wageApplication`·`wageWorkDetail` 을 붙인다.
 *   items 는 기존과 같은 근태 문서(id 포함). 원문 TO/slot/지원서는 반환하지 않는다.
 */
export function attachWageDayProjection(args: {
  req: WageDayReq; caller: {canManageWage: boolean}; items: Doc[]; limitReached: unknown;
  appsById: Map<string, Doc | undefined>; liveWorkDetailOf: (app: Doc) => WdSelection | Doc | undefined;
}): {items: Doc[]; limitReached: unknown; wageDay?: Doc} {
  const gate = wageDayOptIn(args.req, args.caller);
  if (!gate.ok) return {items: args.items, limitReached: args.limitReached};
  let missing = 0;
  let mismatch = 0;
  let wdMissing = 0;
  let incomplete = 0;
  const reasons: Record<string, number> = {};
  const incReasons: Record<string, number> = {};
  const inc = (k: string): void => { incomplete++; incReasons[k] = (incReasons[k] ?? 0) + 1; };
  const out = args.items.map((att) => {
    const appId = att["applicationId"];
    const app = typeof appId === "string" ? args.appsById.get(appId) : undefined;
    if (!app) { missing++; return att; }
    const rel = relationOf(att, app, args.req.businessId);
    if (rel) { mismatch++; reasons[rel] = (reasons[rel] ?? 0) + 1; return att; }
    const missingApp = WAGE_DAY_APP_REQUIRED.filter((k) => app[k] === undefined || app[k] === null);
    if (missingApp.length > 0) { inc("app:" + missingApp.join("+")); return att; }
    // 존재만으로 부족하다 — 문자열·숫자 날짜는 앱 모델 파싱이 null 이 된다. 명시 불완전으로 막는다.
    const badDate = WAGE_DAY_APP_REQUIRED.filter((k) => !(app[k] instanceof Timestamp));
    if (badDate.length > 0) { inc("app:" + badDate.join("+") + ":notTimestamp"); return att; }
    const sel = args.liveWorkDetailOf(app);
    const wdSel: WdSelection | undefined = sel === undefined ? undefined :
      ("wd" in sel || "error" in sel) ? sel as WdSelection : {wd: sel as Doc};
    if (!wdSel) { wdMissing++; return att; }
    if ("error" in wdSel) { inc(wdSel.error); return att; }
    const wd = wdSel.wd;
    const missingWd = WAGE_DAY_WD_REQUIRED.filter((k) => wd[k] === undefined || wd[k] === null);
    if (missingWd.length > 0) { inc("workDetail:" + missingWd.join("+")); return att; }
    return {
      ...att,
      // envelope: 문서 id 는 attendance.applicationId 와 같은 값으로 따로 준다
      wageApplication: {applicationId: appId, ...pick(app, WAGE_DAY_APP_FIELDS)},
      wageWorkDetail: pick(wd, WAGE_DAY_WD_FIELDS),
    };
  });
  return {
    items: out, limitReached: args.limitReached,
    wageDay: {applied: true, applicationMissing: missing, applicationMismatch: mismatch, mismatchReasons: reasons,
      workDetailMissing: wdMissing, inputIncomplete: incomplete, incompleteReasons: incReasons,
      complete: !args.limitReached && missing === 0 && mismatch === 0 && wdMissing === 0 && incomplete === 0},
  };
}
