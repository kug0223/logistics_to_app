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

checks.R7_FIX_LT_WORKER = async (e, say) => {
  const app = (await db.collection('applications').doc(e.applicationId).get()).data();
  if (!app) { say('     지원서 없음'); return false; }

  const today = kstDateKey(0);
  const yest = kstDateKey(-1);
  say(`     지원서 ${app.status} · ${app.type} · ${app.startTime}-${app.endTime}`);
  say(`     기간 ${dayKeyOf(app.workDate)} ~ ${app.workEndDate ? dayKeyOf(app.workEndDate) : '없음'}`);

  const confirmedOk = CONFIRMED.has(app.status);
  const workTodayOk = isWorkingOn(app, today);
  say(`     오늘(${today}) 근무일? ${workTodayOk}`);

  const yDoc = await db.collection('attendance').doc(e.yesterdayAttendanceId).get();
  const y = yDoc.exists ? yDoc.data() : null;
  const yesterdayDoneOk = !!y && y.checkOut != null;
  say(`     어제(${yest}) 근태 ${y ? y.status : '없음'} · checkOut ${y && y.checkOut ? '있음' : '없음'}`);

  const todayId = `${e.applicationId}_${today.replace(/-/g, '')}`;
  const todayMissing = !(await db.collection('attendance').doc(todayId).get()).exists;
  say(`     오늘 근태 문서 없음? ${todayMissing}`);

  // 어제 기록이 오늘의 답으로 쓰이지 않아야 한다.
  const finished = !!y && (y.checkOut != null ||
      ['missed_checkout', 'NO_SHOW', 'absent'].includes(y.status));
  say(`     → getTodayAttendance 는 ${todayMissing && finished ? 'null (어제 건너뜀)' : '?'} 을 돌려준다`);

  // 급여 4상태
  const p = e.payroll || {};
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

  return confirmedOk && workTodayOk && yesterdayDoneOk && todayMissing &&
      finished && wagesOk;
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
