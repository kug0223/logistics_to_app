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

const {db} = require('./r7-fixture-lib');

/** manifest 한 시나리오분을 지운다. 지운 개수를 돌려준다. */
async function removeScenario(entities, {execute}) {
  const removed = {attendance: 0, applications: 0, slots: 0, tos: 0};
  if (!entities) return removed;

  const attIds = new Set();
  for (const k of ['yesterdayAttendanceId']) {
    if (entities[k]) attIds.add(entities[k]);
  }
  for (const v of Object.values(entities.payroll || {})) {
    if (typeof v === 'string') attIds.add(v);
  }

  // 1. 근태 — application 보다 먼저. 남으면 고아가 된다.
  for (const id of attIds) {
    const ref = db.collection('attendance').doc(id);
    if (!(await ref.get()).exists) continue;
    if (execute) await ref.delete();
    removed.attendance++;
  }

  // 2. 지원서 — 이 TO 에 달린 것 전부(fixture TO 이므로 범위가 닫혀 있다).
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
