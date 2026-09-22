/**
 * [R7-PRE0] manifest 기록분만 정리한다.
 *
 * 쿼리로 훑어서 지우지 않는다. DEV 에는 이 스크립트가 만들지 않은 실사용
 * 데이터가 있고, 그것들에는 fixture 표식이 없다. manifest 에 적힌 id 만,
 * 만든 역순으로 지운다.
 *
 * 삭제는 Admin SDK 로 한다 — 되돌리는 canonical writer 가 없는 전이가 있고
 * (이체 완료 등), fixture 를 남겨 두는 편이 더 나쁘다.
 */
'use strict';

const {db, admin, callAs} = require('./r7-fixture-lib');

/**
 * NO_SHOW 근태는 **지우기 전에 취소**해야 한다.
 *
 * 노쇼는 attendance 문서 하나로 끝나지 않는다. onAttendance… 트리거가
 * users.noShowDates 에 시각을 넣고 recentNoShowCount 를 올리고, 90일 내
 * 3회가 되면 restrictedUntil 을 세워 그 계정의 **지원 자체를 막는다.**
 * 되돌리는 것은 노쇼 취소(noshowOff 분기)뿐이다 — 문서를 그냥 지우면
 * 트리거가 돌지 않아 사용자 쪽 제재만 영구히 남는다.
 *
 * 실제로 한 번 그렇게 남겨서 DEV 근로자가 하루 동안 지원 불가가 됐고,
 * 그 계정이 막히니 fixture 를 다시 seed 할 수 없었다.
 */
async function cancelNoShowIfNeeded(snap, {execute, admin: adminUid, businessId}) {
  if (!snap.exists || snap.data().status !== 'NO_SHOW') return;
  if (!execute || !adminUid) return;
  try {
    await callAs(adminUid, 'callableBatchCancelNoShow',
        {businessId, attendanceIds: [snap.id]});
  } catch (e) {
    // 취소가 안 되면 지우지 않는 편이 낫다 — 제재만 남기는 것보다.
    throw new Error(
        `노쇼 취소 실패(${snap.id}): ${e.message} — 사용자 제재가 남을 수 있어 중단합니다.`);
  }
}

/** manifest 한 시나리오분을 지운다. 지운 개수를 돌려준다. */
async function removeScenario(entities, {execute, months, adminUid, businessId}) {
  const removed = {attendance: 0, applications: 0, slots: 0, tos: 0, contracts: 0};
  if (!entities) return removed;

  /**
   * 지우려는 근태가 급여 집계에 반영돼 있으면 그 달을 기록해 둔다.
   *
   * payroll_summaries 는 onAttendanceWageChanged 가 delta 로 유지하는
   * 증분 집계다. 문서를 Admin SDK 로 지우면 delta 가 돌지 않아 그만큼
   * 영구히 부풀어 남는다 — 실제로 DEV 에서 1,183,998원 / 17일 로 부푼 채
   * 있었고, cross-surface sanity 가 그것을 제품 결함으로 오인할 뻔했다.
   * 정리가 끝나면 canonical 복구 CF 로 되돌린다.
   */
  const note = (snap) => {
    if (!months || !snap.exists) return;
    const d = snap.data();
    if (!['confirmed', 'transferred'].includes(d.wageStatus)) return;
    const ym = d.yearMonth ||
        new Date(d.workDate.toMillis() + 9 * 3600e3).toISOString().slice(0, 7);
    months.add(ym);
  };

  const attIds = new Set();
  for (const k of ['yesterdayAttendanceId']) {
    if (entities[k]) attIds.add(entities[k]);
  }
  for (const id of entities.attendanceIds || []) attIds.add(id);
  for (const v of Object.values(entities.payroll || {})) {
    if (typeof v === 'string') attIds.add(v);
  }

  // 0. 계약서 — 지원서보다 먼저. 계약서만 남으면 지원서 없는 고아가 된다.
  //    Storage 산출물(서명·PDF)은 contracts/{contractId}/ 아래에 남는데,
  //    fixture 는 DEV 버킷에만 쓰고 재seed 때 새 contractId 를 받으므로
  //    누적되지 않게 함께 지운다.
  if (entities.contractId) {
    const ref = db.collection('employment_contracts').doc(entities.contractId);
    if ((await ref.get()).exists) {
      if (execute) {
        await ref.delete();
        try {
          await admin.storage().bucket()
              .deleteFiles({prefix: `contracts/${entities.contractId}/`});
        } catch (_) { /* 파일이 없으면 그만이다 */ }
      }
      removed.contracts++;
    }
  }

  // 1. 근태 — application 보다 먼저. 남으면 고아가 된다.
  for (const id of attIds) {
    const ref = db.collection('attendance').doc(id);
    const snap = await ref.get();
    if (!snap.exists) continue;
    note(snap);
    await cancelNoShowIfNeeded(snap, {execute, admin: adminUid, businessId});
    if (execute) await ref.delete();
    removed.attendance++;
  }

  // 2. 지원서 — 이 TO 에 달린 것 전부(fixture TO 이므로 범위가 닫혀 있다).
  //    sharedToId 인 시나리오는 자기 지원서만 지운다. 그 공고는 다른
  //    시나리오의 것이고, 아직 살아 있어야 한다.
  const appIds = new Set();
  if (entities.applicationId) appIds.add(entities.applicationId);
  if (entities.confirmedApplicationId) appIds.add(entities.confirmedApplicationId);
  if (entities.toId) {
    const snap = await db.collection('applications')
        .where('toId', '==', entities.toId).get();
    snap.docs.forEach((d) => appIds.add(d.id));
  }
  for (const id of appIds) {
    const ref = db.collection('applications').doc(id);
    if (!(await ref.get()).exists) continue;
    // 그 지원서에 달린 근태가 더 있으면 함께 지운다.
    const atts = await db.collection('attendance')
        .where('applicationId', '==', id).get();
    for (const a of atts.docs) {
      note(a);
      await cancelNoShowIfNeeded(a, {execute, admin: adminUid, businessId});
      if (execute) await a.ref.delete();
      removed.attendance++;
    }
    if (execute) await ref.delete();
    removed.applications++;
  }

  // 3. 슬롯 → 4. TO
  if (entities.toId) {
    const toRef = db.collection('tos').doc(entities.toId);
    const slots = await toRef.collection('slots').get();
    for (const s of slots.docs) {
      if (execute) await s.ref.delete();
      removed.slots++;
    }
    if ((await toRef.get()).exists) {
      if (execute) await toRef.delete();
      removed.tos++;
    }
  }

  return removed;
}

module.exports = {removeScenario};
