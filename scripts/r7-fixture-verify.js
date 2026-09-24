/**
 * [R7-PRE0] canonical sanity check.
 *
 * "문서가 만들어졌다"로 끝내지 않는다. 각 fixture 가 말하기로 한 **업무 사실**이
 * 실제 저장된 상태와 맞는지 본다. 화면을 근거로 쓰지 않는다 — Firestore 를 읽는다.
 */
'use strict';

const {db, kstDateKey} = require('./r7-fixture-lib');

const NAMES = ['월', '화', '수', '목', '금', '토', '일'];
const CONFIRMED = new Set(['CONFIRMED', 'CONTRACT_PENDING']);

function dayKeyOf(ts) {
  return new Date(ts.toDate().getTime() + 9 * 3600e3).toISOString().slice(0, 10);
}

/** application.isWorkingOnDate 의 replica (장기 경로). */
function isWorkingOn(app, key) {
  const end = app.actualResignDate || app.workEndDate;
  if (!end) return false;
  const start = dayKeyOf(app.desiredStartDate || app.workDate);
  if (key < start || key > dayKeyOf(end)) return false;
  const dow = new Date(key + 'T00:00:00Z').getUTCDay();
  return (app.workDays || []).includes(NAMES[dow === 0 ? 6 : dow - 1]);
}

const checks = {};

checks.R7_FIX_POST_SHORTAGE = async (e, say) => {
  const slots = await db.collection('tos').doc(e.toId).collection('slots').get();
  let ok = slots.size === e.dates.length;
  say(`     슬롯 ${slots.size}개 (기대 ${e.dates.length})`);
  for (const s of slots.docs) {
    const wd = (s.data().workDetails || [])[0] || {};
    const conf = (s.data().confirmedCount) || 0;
    const remaining = (wd.requiredCount || 0) - conf;
    say(`     ${dayKeyOf(s.data().date)}  정원 ${wd.requiredCount} · 확정 ${conf} · 잔여 ${remaining}`);
    if (remaining <= 0) ok = false;
  }
  return ok;
};

checks.R7_FIX_POST_MIXED = async (e, say) => {
  const slots = await db.collection('tos').doc(e.toId)
      .collection('slots').orderBy('date').get();
  const rows = slots.docs.map((s) => {
    const d = s.data();
    const wd = (d.workDetails || [])[0] || {};
    return {
      key: dayKeyOf(d.date),
      required: wd.requiredCount || 0,
      confirmed: d.confirmedCount || 0,
    };
  });
  rows.forEach((r) => say(
      `     ${r.key}  ${r.confirmed}/${r.required}  ${r.confirmed >= r.required ? 'FULL' : '부족 ' + (r.required - r.confirmed)}`));
  const full = rows.filter((r) => r.confirmed >= r.required).length;
  const short = rows.filter((r) => r.confirmed < r.required).length;
  const to = (await db.collection('tos').doc(e.toId).get()).data();
  say(`     공고 status=${to.status} · isManualClosed=${to.isManualClosed === true}`);
  // 한 날짜가 찼다고 공고 전체가 닫히면 안 된다.
  const notClosed = to.isManualClosed !== true && to.status !== 'CLOSED';
  return full >= 1 && short >= 1 && notClosed;
};

checks.R7_FIX_POST_CLOSED = async (e, say) => {
  const to = (await db.collection('tos').doc(e.toId).get()).data();
  say(`     status=${to.status} · isManualClosed=${to.isManualClosed === true} · isPublished=${to.isPublished === true}`);
  return to.isManualClosed === true && to.status === 'CLOSED';
};

/**
 * [BLOCKER-PRE0-FIXTURE-SCHEDULER-CONTAMINATION]
 *
 *   이 fixture 는 원래 "오늘도 근무일"을 요구했다. 그런데 아무도
 *   체크인하지 않는다 — fixture 니까. 그것이 정확히 auto NO_SHOW 의
 *   조건이었고, 실제로 매일 하나씩 쌓였다.
 *
 *   검증이 그것을 못 잡은 이유도 같다. 검증은 **오늘** 문서가 없는지만
 *   봤는데 scheduler 는 **어제** 자리에 쓴다. 그래서 오염이 늘어나는
 *   동안에도 7/7 이었다.
 *
 *   이제 anchor 는 이미 끝난 관계이고, 검증은 scheduler 흔적을 직접
 *   찾는다.
 */
checks.R7_FIX_LT_WORKER = async (e, say) => {
  const app = (await db.collection('applications').doc(e.applicationId).get()).data();
  if (!app) { say('     지원서 없음'); return false; }

  const today = kstDateKey(0);
  say(`     지원서 ${app.status} · ${app.type} · ${app.startTime}-${app.endTime}`);
  say(`     기간 ${dayKeyOf(app.workDate)} ~ ${app.workEndDate ? dayKeyOf(app.workEndDate) : '없음'}`);

  const confirmedOk = CONFIRMED.has(app.status);

  // ── PRE0-SCHED-05 · 오늘과 그 이후 어느 날도 근무일이 아니다 ──────
  //   오늘 하루만 보지 않는다. 계약 종료일까지(그리고 그 너머로 여유를
  //   두고) 훑어서 mutation 대상이 되는 날이 하나도 없음을 증명한다.
  const horizon = 45;
  const eligibleDays = [];
  for (let i = 0; i <= horizon; i++) {
    const k = kstDateKey(i);
    if (isWorkingOn(app, k)) eligibleDays.push(k);
  }
  const schedIsolatedOk = eligibleDays.length === 0;
  say(`     PRE0-SCHED-05 오늘~+${horizon}일 근무 가능일 ${eligibleDays.length}일` +
      `${eligibleDays.length ? ` (${eligibleDays.slice(0, 3).join(', ')}…)` : ''}`);

  // ── 마지막 근무일이 완결돼 있다 ──────────────────────────────────
  const lastId = e.lastWorkAttendanceId || e.yesterdayAttendanceId;
  const lDoc = await db.collection('attendance').doc(lastId).get();
  const l = lDoc.exists ? lDoc.data() : null;
  const lastDoneOk = !!l && l.checkOut != null;
  say(`     마지막 근무 ${lastId.slice(-8)} ${l ? l.status : '없음'} · ` +
      `checkOut ${l && l.checkOut ? '있음' : '없음'}`);

  // ── PRE0-SCHED-01/02 · scheduler 흔적이 하나도 없어야 한다 ────────
  const p = e.payroll || {};
  const anchorIds = new Set(Object.values(p));
  const attSnap = await db.collection('attendance')
      .where('applicationId', '==', e.applicationId).get();
  const extra = attSnap.docs.filter((d) => !anchorIds.has(d.id));
  const noShow = attSnap.docs.filter((d) => d.data().status === 'NO_SHOW');
  const autoMade = attSnap.docs.filter((d) => !!d.data().autoNoShowAt);
  const noExtraOk = extra.length === 0;
  const noNoShowOk = noShow.length === 0 && autoMade.length === 0;
  say(`     PRE0-SCHED-01 예상 밖 근태 ${extra.length}건` +
      `${extra.length ? ` (${extra.map((d) => d.id.slice(-8)).join(', ')})` : ''}`);
  say(`     PRE0-SCHED-02 NO_SHOW ${noShow.length}건 · 자동생성 ${autoMade.length}건`);

  // ── PRE0-SCHED-03/04 · 신뢰도·지원제한에 기여하지 않는다 ──────────
  const user = (await db.collection('users').doc(app.uid).get()).data() || {};
  const ownedPenalties = attSnap.docs
      .filter((d) => d.data().noShowPenaltyTimestamp).length;
  const noPenaltyOk = ownedPenalties === 0;
  say(`     PRE0-SCHED-03 fixture 발 신뢰도 사건 ${ownedPenalties}건`);
  // 지원 제한이 걸려 있다면 그 근거가 fixture 밖에 있어야 한다.
  let restrictionOk = true;
  if (user.restrictedUntil && user.restrictedUntil.toDate() > new Date()) {
    restrictionOk = ownedPenalties === 0;
    say(`     PRE0-SCHED-04 지원 제한 있음 — fixture 기여 ${ownedPenalties}건`);
  } else {
    say('     PRE0-SCHED-04 지원 제한 없음');
  }

  // ── 급여 4상태 ───────────────────────────────────────────────────
  const states = {};
  for (const [k, id] of Object.entries(p)) {
    const v = (await db.collection('attendance').doc(id).get()).data();
    states[k] = v ? `${v.wageStatus}/${v.finalWage || 0}원` : '없음';
  }
  say(`     급여 ${JSON.stringify(states)}`);
  const wagesOk =
    (states.pendingAttendanceId || '').startsWith('pending') &&
    (states.calculatedAttendanceId || '').startsWith('calculated') &&
    (states.confirmedAttendanceId || '').startsWith('confirmed') &&
    (states.transferredAttendanceId || '').startsWith('transferred');

  void today;
  return confirmedOk && schedIsolatedOk && lastDoneOk && noExtraOk &&
      noNoShowOk && noPenaltyOk && restrictionOk && wagesOk;
};

checks.R7_FIX_APP_PENDING = async (e, say) => {
  const app = (await db.collection('applications').doc(e.applicationId).get()).data();
  if (!app) { say('     지원서 없음'); return false; }
  const slot = (await db.collection('tos').doc(e.sharedToId)
      .collection('slots').doc(e.slotId).get()).data();
  const required = ((slot.workDetails || [])[0] || {}).requiredCount || 0;
  say(`     ${e.dateKey} 지원서 ${app.status} · 이 슬롯 확정 ${slot.confirmedCount || 0}/${required}`);
  // 지원은 확정이 아니다 — 이 날짜의 확정 카운터가 움직이면 안 된다.
  return app.status === 'PENDING' && (slot.confirmedCount || 0) === 0;
};

/** 계약 상태 + 지원서 상태가 짝이 맞는지. */
async function contractCheck(e, say, wantStatus, wantAppStatus) {
  const c = (await db.collection('employment_contracts').doc(e.contractId).get()).data();
  if (!c) { say('     계약서 없음'); return false; }
  const app = (await db.collection('applications').doc(e.applicationId).get()).data();
  say(`     계약 status=${c.status} · 사업주서명 ${c.employerSignatureUrl ? '있음' : '없음'}` +
      ` · 근로자서명 ${c.workerSignatureUrl ? '있음' : '없음'} · PDF ${c.pdfUrl ? '있음' : '없음'}`);
  say(`     지원서 ${app ? app.status : '없음'}`);
  const snap = c.snapshot || {};
  say(`     스냅샷 사업장="${snap.businessName || ''}" 대표="${snap.ownerName || ''}"` +
      ` 근로자="${snap.workerName ? '있음' : '비어있음'}" 임금=${snap.wage}`);
  const snapOk = !!snap.businessName && !!snap.ownerName && !!snap.workerName &&
      (snap.wage || 0) > 0;
  return c.status === wantStatus && !!app && app.status === wantAppStatus && snapOk;
}

checks.R7_FIX_CONTRACT_PW = (e, say) =>
  contractCheck(e, say, 'pending_worker', 'CONTRACT_PENDING');

checks.R7_FIX_CONTRACT_DONE = async (e, say) => {
  const ok = await contractCheck(e, say, 'completed', 'CONFIRMED');
  const c = (await db.collection('employment_contracts').doc(e.contractId).get()).data();
  // 계약 완료가 지원서 CONFIRMED 를 만든 유일한 경로임을 이력으로 확인한다.
  const app = (await db.collection('applications').doc(e.applicationId).get()).data();
  const via = (app.statusHistory || [])
      .filter((h) => h.status === 'CONFIRMED')
      .map((h) => h.action).join(',');
  say(`     CONFIRMED 경로: ${via || '(이력 없음)'}`);
  return ok && !!c.workerSignatureUrl && !!c.pdfUrl && via.includes('CONTRACT_SIGNED');
};

async function verifyAll(manifest, log) {
  let allOk = true;
  for (const [id, rec] of Object.entries(manifest.scenarios || {})) {
    const fn = checks[id];
    if (!fn) { log(`   ?  ${id}  (검증기 없음)`); continue; }
    let ok = false;
    try {
      ok = await fn(rec.entities, (s) => log(s));
    } catch (e) {
      log(`     오류: ${e.message}`);
    }
    log(`   ${ok ? 'OK  ' : '실패'} ${id}`);
    if (!ok) allOk = false;
  }
  return allOk;
}

module.exports = {verifyAll, checks};
