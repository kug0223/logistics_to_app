#!/usr/bin/env node
/**
 * [BLOCKER-PRE0-FIXTURE-SCHEDULER-CONTAMINATION] 보호 fixture 격리.
 *
 * 무엇이 문제였나.
 *
 *   보호 fixture `R7_FIX_LT_WORKER` 는 **오늘도 근무일**이어야 한다고
 *   적혀 있다. 그래야 "오늘 카드와 체크인 CTA 가 보인다"를 증명한다.
 *   그리고 아무도 체크인하지 않는다 — fixture 니까.
 *
 *   그런데 그것이 정확히 auto NO_SHOW 의 조건이다.
 *
 *       영원히 보호되는 fixture
 *       AND
 *       영원히 근태 대상
 *
 *   둘은 원천적으로 충돌한다. scheduler 는 잘못하지 않았다 — fixture 의
 *   현재 일정을 보고 정상적으로 행동했다. 고칠 것은 제품이 아니라
 *   fixture 다.
 *
 * 그래서 역할을 나눈다.
 *
 *   안정 anchor  → 이미 끝난 장기 근무관계 + 급여 4상태.
 *                  오늘·미래 어느 날도 근무일이 아니다.
 *   활성 시나리오 → 필요한 Phase 가 runtime 에 만들고 정확히 지운다.
 *
 * 이 스크립트는 **이미 seed 된 DEV 데이터**를 그 모양으로 옮기고,
 * 지금까지 쌓인 fixture 소유 오염을 정리한다.
 *
 *   node scripts/pre0-fixture-scheduler-isolation.js --project alfit-89567
 *   node scripts/pre0-fixture-scheduler-isolation.js --project alfit-89567 --execute
 */
'use strict';

const EXPECTED_DEV_PROJECT = 'alfit-89567';
const PROD_PROJECT_ID = 'alfit-prod';
const argv = process.argv.slice(2);
const projectId = (() => {
  const i = argv.indexOf('--project');
  return i >= 0 ? argv[i + 1] : null;
})();
if (projectId === PROD_PROJECT_ID) {
  console.error('PROD 프로젝트입니다. 실행하지 않습니다.');
  process.exit(2);
}
if (projectId !== EXPECTED_DEV_PROJECT) {
  console.error(`DEV 전용입니다. --project ${EXPECTED_DEV_PROJECT}`);
  process.exit(2);
}
const EXECUTE = argv.includes('--execute');

const {admin, db, kstMidnightMs} = require('./r7-fixture-lib');
const manifest = require('./r7-fixture-manifest-dev.json');

const KST = 9 * 3600e3;
const iso = (t) => t ? new Date(t.toMillis() + KST).toISOString().slice(0, 16) : null;
const day = (t) => t ? new Date(t.toMillis() + KST).toISOString().slice(0, 10) : null;
const log = (...a) => console.log(...a);
const head = (s) => log(`\n${'─'.repeat(74)}\n${s}\n${'─'.repeat(74)}`);

/** 보호 fixture 의 정확한 identity — manifest 가 진실이다. 추측하지 않는다. */
function fixtureIdentity() {
  const s = manifest.scenarios && manifest.scenarios.R7_FIX_LT_WORKER;
  if (!s || !s.entities || !s.entities.applicationId) {
    throw new Error('manifest 에 R7_FIX_LT_WORKER 가 없다. 먼저 seed 가 필요하다.');
  }
  const e = s.entities;
  const payroll = Object.values(e.payroll || {});
  if (payroll.length !== 4) {
    throw new Error(`급여 anchor 4건이어야 한다 — ${payroll.length}건`);
  }
  return {
    applicationId: e.applicationId,
    toId: e.toId,
    payrollIds: payroll,
    lastWorkAttendanceId: e.payroll.pendingAttendanceId,
  };
}

async function main() {
  log(`\nDEV=${projectId}  ${EXECUTE ? '' : '(dry-run — 아무것도 쓰지 않는다)'}`);
  const id = fixtureIdentity();

  head('1. 보호 fixture identity');
  log(`   application  ${id.applicationId}`);
  log(`   posting      ${id.toId}`);
  log(`   급여 anchor   ${id.payrollIds.length}건`);

  const appRef = db.collection('applications').doc(id.applicationId);
  const appSnap = await appRef.get();
  if (!appSnap.exists) throw new Error('보호 fixture 지원서가 없다.');
  const app = appSnap.data();
  const workerUid = app.uid;
  const businessId = app.businessId;
  log(`   worker       ${workerUid}`);
  log(`   business     ${businessId}`);
  log(`   상태         ${app.status} · ${app.type}`);
  log(`   기간         ${day(app.workDate)} ~ ${day(app.workEndDate)}`);
  log(`   workDays     ${(app.workDays || []).join('')}`);

  // ── 2. fixture 소유 근태 전수 ───────────────────────────────────
  head('2. fixture 소유 근태 (삭제 전 snapshot)');
  const attSnap = await db.collection('attendance')
      .where('applicationId', '==', id.applicationId).get();
  const owned = attSnap.docs.map((d) => ({id: d.id, ...d.data()}));
  owned.sort((a, b) => a.id.localeCompare(b.id));
  for (const a of owned) {
    const anchor = id.payrollIds.includes(a.id) ? 'ANCHOR' : '      ';
    log(`   ${anchor} ${a.id.slice(-8)}  ${String(a.status).padEnd(9)}` +
        ` wage=${a.wageStatus || '-'}` +
        ` auto=${a.autoNoShowAt ? 'Y' : '-'}` +
        ` penaltyTs=${iso(a.noShowPenaltyTimestamp) || '-'}`);
  }

  // scheduler 가 만든 것만 오염이다. 급여 anchor 는 fixture 의 일부다.
  const contamination = owned.filter((a) =>
    !id.payrollIds.includes(a.id) && a.status === 'NO_SHOW' && a.autoNoShowAt);
  const unexpected = owned.filter((a) =>
    !id.payrollIds.includes(a.id) && !contamination.includes(a));
  log(`\n   오염(scheduler 생성 NO_SHOW) ${contamination.length}건`);
  log(`   설명되지 않는 나머지          ${unexpected.length}건`);
  if (unexpected.length > 0) {
    // 소유는 증명됐지만 출처를 모르는 문서는 지우지 않는다.
    unexpected.forEach((a) => log(`     ? ${a.id} ${a.status}`));
    log('   → 출처를 모르는 문서는 건드리지 않는다. 먼저 조사해야 한다.');
  }

  // ── 3. 소유권 증명 ─────────────────────────────────────────────
  head('3. 소유권 증명 (하나라도 어긋나면 중단)');
  for (const a of contamination) {
    const okApp = a.applicationId === id.applicationId;
    const okUser = a.userId === workerUid;
    const okBiz = a.businessId === businessId;
    const okAuto = !!a.autoNoShowAt;
    log(`   ${a.id.slice(-8)}  app=${okApp} user=${okUser} biz=${okBiz} auto=${okAuto}`);
    if (!(okApp && okUser && okBiz && okAuto)) {
      throw new Error(`소유권 증명 실패: ${a.id}`);
    }
  }

  // ── 4. 같은 근로자의 다른 NO_SHOW — 보존 대상 ──────────────────
  head('4. 같은 근로자의 NO_SHOW 전체 (fixture 소유 / 그 외)');
  const allAtt = await db.collection('attendance')
      .where('userId', '==', workerUid).get();
  const allNoShow = allAtt.docs
      .map((d) => ({id: d.id, ...d.data()}))
      .filter((a) => a.status === 'NO_SHOW');
  const foreign = allNoShow.filter(
      (a) => a.applicationId !== id.applicationId);
  log(`   전체 NO_SHOW      ${allNoShow.length}건`);
  log(`   fixture 소유      ${contamination.length}건 (삭제 대상)`);
  log(`   다른 runtime 소유 ${foreign.length}건 (보존)`);
  foreign.forEach((a) =>
    log(`     보존 ${a.id.slice(0, 22)}… penaltyTs=${iso(a.noShowPenaltyTimestamp) || '-'}`));

  // ── 5. 신뢰도 현재 상태 ────────────────────────────────────────
  head('5. 신뢰도 · 지원 제한 (현재)');
  const userRef = db.collection('users').doc(workerUid);
  const user = (await userRef.get()).data();
  log(`   noShowCount       ${user.noShowCount}`);
  log(`   recentNoShowCount ${user.recentNoShowCount}`);
  log(`   noShowDates       ${(user.noShowDates || []).map(iso).join(' | ')}`);
  log(`   restrictedUntil   ${iso(user.restrictedUntil) || '없음'}`);

  // canonical 재계산 — 산술 보정이 아니라 **남은 사건**에서 다시 센다.
  const remaining = foreign
      .map((a) => a.noShowPenaltyTimestamp)
      .filter(Boolean);
  const cutoff = new Date(Date.now() - 90 * 24 * 60 * 60 * 1000);
  const recent = remaining.filter((t) => t.toDate() >= cutoff).length;
  const nextRestriction = recent >= 3 ? user.restrictedUntil ?? null : null;
  head('6. 재계산 결과 (남은 canonical 사건 기준)');
  log(`   noShowCount       ${user.noShowCount} → ${foreign.length}`);
  log(`   recentNoShowCount ${user.recentNoShowCount} → ${recent}`);
  log(`   noShowDates       ${remaining.length}건 (fixture 사건 제거)`);
  log(`   restrictedUntil   ${iso(user.restrictedUntil) || '없음'} → ` +
      `${nextRestriction ? iso(nextRestriction) : '없음 (최근 90일 3회 미만)'}`);

  // ── 7. fixture 기간을 닫는다 ───────────────────────────────────
  //
  //   마지막 급여 anchor 날짜를 계약 종료일로 삼는다. 그러면 그 날까지의
  //   근무 이력은 그대로 말이 되고, 그 다음 날부터는 어떤 scheduler 도
  //   근무일을 찾지 못한다(AFTER_END).
  const lastWorkKey = id.lastWorkAttendanceId.slice(-8);
  const lastWorkMs = Date.UTC(
      Number(lastWorkKey.slice(0, 4)),
      Number(lastWorkKey.slice(4, 6)) - 1,
      Number(lastWorkKey.slice(6, 8))) - KST;
  head('7. 계약 기간 마감');
  log(`   마지막 근무일   ${lastWorkKey}`);
  log(`   workEndDate     ${day(app.workEndDate)} → ${lastWorkKey}`);
  log('   renewalDecision 없음 → TERMINATE');
  log('     (끝났고 연장하지 않은 관계다. 이렇게 두지 않으면 관리자');
  log('      화면에 "계약 확인 필요"로 영원히 남는다.)');
  if (lastWorkMs >= kstMidnightMs(0)) {
    throw new Error('마지막 근무일이 오늘 이후다 — 격리되지 않는다.');
  }

  if (!EXECUTE) {
    log('\ndry-run 종료. 쓰려면 --execute');
    return;
  }

  head('8. 실행');
  for (const a of contamination) {
    log(`   삭제 attendance ${a.id}`);
    await db.collection('attendance').doc(a.id).delete();
  }
  // 삭제는 onDocumentWritten(noshowOff)도 태운다. 그 경로는 after 가 없어
  //   noShowDates 를 정확히 되돌리지 못하므로, 여기서 canonical 값을
  //   명시적으로 다시 쓴다. 나중 쓰기가 이긴다.
  await new Promise((r) => setTimeout(r, 3000));
  const patch = {
    noShowCount: foreign.length,
    recentNoShowCount: recent,
    noShowDates: remaining,
  };
  if (!nextRestriction) {
    patch.restrictedUntil = admin.firestore.FieldValue.delete();
  }
  log(`   users/${workerUid.slice(0, 10)}… 신뢰도 재계산 반영`);
  await userRef.update(patch);

  log('   지원서 기간 마감 + renewalDecision=TERMINATE');
  await appRef.update({
    workEndDate: admin.firestore.Timestamp.fromMillis(lastWorkMs),
    renewalDecision: 'TERMINATE',
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  head('9. 사후 확인');
  const after = (await userRef.get()).data();
  log(`   noShowCount       ${after.noShowCount}`);
  log(`   recentNoShowCount ${after.recentNoShowCount}`);
  log(`   noShowDates       ${(after.noShowDates || []).map(iso).join(' | ') || '없음'}`);
  log(`   restrictedUntil   ${iso(after.restrictedUntil) || '없음'}`);
  const afterApp = (await appRef.get()).data();
  log(`   기간              ${day(afterApp.workDate)} ~ ${day(afterApp.workEndDate)}`);
  log(`   renewalDecision   ${afterApp.renewalDecision}`);
  const afterAtt = await db.collection('attendance')
      .where('applicationId', '==', id.applicationId).get();
  const stillNoShow = afterAtt.docs.filter((d) => d.data().status === 'NO_SHOW');
  log(`   fixture 근태      ${afterAtt.size}건 · NO_SHOW ${stillNoShow.length}건`);
  const foreignAfter = (await db.collection('attendance')
      .where('userId', '==', workerUid).get()).docs
      .filter((d) => d.data().status === 'NO_SHOW' &&
        d.data().applicationId !== id.applicationId);
  log(`   다른 runtime NO_SHOW 보존 ${foreignAfter.length}건 ` +
      `(기대 ${foreign.length}건)`);
  if (foreignAfter.length !== foreign.length) {
    throw new Error('무관한 NO_SHOW 가 사라졌다.');
  }
}

main().then(() => process.exit(0)).catch((e) => {
  console.error('\n실패:', e && e.message ? e.message : e);
  process.exit(1);
});
