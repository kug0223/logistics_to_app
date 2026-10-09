'use strict';
// [R7-P1-2 DEVICE.1C §8·§9] 실제 확정 mutation 으로 정원 경계를 확인한다.
//
//   이전 보고서는 카운터 값 + 가드 산술로 1st/2nd/3rd 를 **유도**했다.
//   여기서는 실제 확정 writer 를 돌린다.
//
//   실물 R7FIX 공고는 건드리지 않는다. 같은 모양의 격리 fixture 를 만들고
//   끝나면 정확히 지운다.
//
//     required = 2
//     끝난 장기 확정 1건 (workEndDate = 어제-3)  ← 이력
//     현재 좌석 0
//     확정 대기 후보 3건
//
//   실행:  node scripts/r7-1c-confirm-capacity-runtime.js

const {admin, db, callAs} = require('./r7-fixture-lib.js');

const BIZ = 'fLmSOHVKUwmBHcbwQE0I';
const OWNER = 'BErRdiWP1xbgyoTovxwAPNEsuD72';
const WORKERS = [
  'tJ8izfP2nNYN79aPTLb6YARiPqC3',
  'kN2gNpEhLLVjQD7KLGSnNFJHd2v2',
  'J6lVRGSFsBewqvWy0gFE46YQI9z1',
];
const ENDED_WORKER = 'JK7GjLnacDczmdJjT3GIQENz87c2';

const TO_ID = 'R7C1C_CAPACITY_FIXTURE';
const WORK_TYPE = '사무업무';
const TS = (d) => admin.firestore.Timestamp.fromDate(d);
const KST = 9 * 3600 * 1000;
/** KST 달력일 기준 오프셋의 KST 자정 instant. */
const kstDay = (off) => {
  const k = new Date(Date.now() + KST);
  return new Date(Date.UTC(k.getUTCFullYear(), k.getUTCMonth(),
      k.getUTCDate() + off) - KST);
};

let failed = 0;
const line = (k, v) => console.log(`  ${String(k).padEnd(44)} ${v}`);
const check = (label, actual, expected) => {
  const ok = String(actual) === String(expected);
  if (!ok) failed++;
  line(label, `${actual}   ${ok ? 'PASS' : `FAIL (expected ${expected})`}`);
};

const toRef = db.collection('tos').doc(TO_ID);
const appId = (uid) => `${TO_ID}_${WORK_TYPE}_${uid}`;
const created = [];

async function counters() {
  const d = (await toRef.get()).data() || {};
  return {
    total: d.totalConfirmed ?? 0,
    byWt: (d.workTypeConfirmedCounts || {})[WORK_TYPE] ?? 0,
    required: d.workDetails?.[0]?.requiredCount ?? 0,
  };
}

/** syncTOStats 는 status 변경 트리거다 — 반영까지 잠시 기다린다. */
const settle = (ms = 9000) => new Promise((r) => setTimeout(r, ms));

async function confirm(uid) {
  try {
    await callAs(OWNER, 'callableConfirmApplication', {
      applicationId: appId(uid),
      businessId: BIZ,
    });
    return {ok: true};
  } catch (e) {
    return {ok: false, code: e.wireCode || null, msg: e.message};
  }
}

async function cleanup() {
  console.log('\n[cleanup]');
  const batch = db.batch();
  for (const id of created) batch.delete(db.collection('applications').doc(id));
  batch.delete(toRef);
  await batch.commit();
  const left = await db.collection('applications')
      .where('toId', '==', TO_ID).get();
  check('fixture 지원서 잔존', left.size, 0);
  check('fixture TO 잔존', (await toRef.get()).exists, false);
}

(async () => {
  console.log(`project=alfit-89567  fixture=${TO_ID}`);
  try {
    // ── 0. fixture ───────────────────────────────────────────────
    await toRef.set({
      businessId: BIZ, businessName: '위워커',
      title: '[R7C1C] 정원 경계 fixture',
      type: 'contract', status: 'ACTIVE',
      rangeStart: TS(kstDay(-30)), rangeEnd: TS(kstDay(30)),
      workDays: ['월', '화', '수', '목', '금', '토', '일'],
      workDetails: [{
        workType: WORK_TYPE, workTypeIcon: '📋',
        startTime: '06:00', endTime: '08:00',
        requiredCount: 2, wage: 12000, wageType: 'hourly',
        breakMinutes: 0, payScheduleType: 'same_day',
      }],
      totalRequired: 2, totalConfirmed: 0, totalPending: 0,
      workTypeConfirmedCounts: {[WORK_TYPE]: 0},
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const baseApp = (uid) => ({
      toId: TO_ID, toTitle: '[R7C1C] 정원 경계 fixture',
      businessId: BIZ, businessName: '위워커', uid,
      type: 'long_term', selectedWorkType: WORK_TYPE,
      startTime: '06:00', endTime: '08:00', wage: 12000,
      workDays: ['월', '화', '수', '목', '금', '토', '일'],
      appliedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 끝난 관계 — 이력. 어제보다 더 전에 끝났다.
    const endedId = appId(ENDED_WORKER);
    await db.collection('applications').doc(endedId).set({
      ...baseApp(ENDED_WORKER),
      status: 'CONTRACT_PENDING',
      workDate: TS(kstDay(-20)),
      workEndDate: TS(kstDay(-5)),
      confirmedAt: TS(kstDay(-18)),
      renewalDecision: 'TERMINATE',
    });
    created.push(endedId);

    // 확정 후보 3명 — 현재 기간.
    for (const uid of WORKERS) {
      const id = appId(uid);
      await db.collection('applications').doc(id).set({
        ...baseApp(uid),
        status: 'PENDING',
        workDate: TS(kstDay(0)),
        workEndDate: TS(kstDay(20)),
      });
      created.push(id);
    }

    await settle();
    let c = await counters();
    console.log('\n[0] 초기 상태');
    line('required', c.required);
    check('workTypeConfirmedCounts (현재 좌석)', c.byWt, 0);
    line('  ↑ 끝난 확정 1건이 있지만 좌석은 0', '');

    // ── A. 첫 대체 확정 ──────────────────────────────────────────
    console.log('\n[A] 첫 대체 확정');
    const a = await confirm(WORKERS[0]);
    check('confirm #1 성공', a.ok, true);
    if (!a.ok) line('code', `${a.code} ${a.msg}`);
    await settle();
    c = await counters();
    check('좌석', c.byWt, 1);
    check('부족', Math.max(c.required - c.byWt, 0), 1);

    // ── B·C. 두 번째 이후 ────────────────────────────────────────
    //
    //   DEV 에 확정 가능한 근로자가 1명뿐이다(나머지는 신분증 확인 미완료).
    //   그리고 신분증 게이트가 정원 가드보다 **먼저** 돈다(index.ts 28267
    //   vs 28394). 그래서 2번째·3번째 시도는 정원이 아니라 신원 사유로
    //   막힌다 — 그 거부를 `정원 초과 확인` 으로 기록하지 않는다.
    //
    //   신원 확인 상태를 만들어 통과시키지 않는다. 그건 시험 대상이 아닌
    //   전제를 손봐서 원하는 결과를 얻는 일이다.
    console.log('\n[B/C] 두 번째 이후 — 정원 경계 미검증');
    const b = await confirm(WORKERS[1]);
    line('confirm #2 성공', b.ok);
    line('거부 사유', b.msg || '-');
    const capacityReason = (b.msg || '').includes('정원이 초과');
    line('거부가 정원 사유인가', capacityReason);
    if (!capacityReason) {
      console.log('  → NOT PROVEN: 신분증 게이트가 먼저 막았다.');
      console.log('    §9 B·C 는 이 fixture 로 검증할 수 없다.');
    } else {
      check('정원 사유로 거부', capacityReason, true);
    }
    await settle();
    c = await counters();
    line('좌석(변화 없음 기대)', c.byWt);

    // ── D·E. 이력 보존 ───────────────────────────────────────────
    console.log('\n[D] 이력');
    const ended = await db.collection('applications').doc(endedId).get();
    check('끝난 지원서 존재', ended.exists, true);
    check('끝난 지원서 status 불변', ended.get('status'), 'CONTRACT_PENDING');
    check('과거 확정 시각 보존', ended.get('confirmedAt') != null, true);
    check('renewalDecision 보존', ended.get('renewalDecision'), 'TERMINATE');
    const all = await db.collection('applications')
        .where('toId', '==', TO_ID).get();
    check('지원서 총 건수 (삭제 0)', all.size, 4);

  } catch (e) {
    failed++;
    console.error('\n실행 오류:', e.message);
  } finally {
    await cleanup();
  }

  console.log(`\n결과: ${failed === 0 ? 'ALL PASS' : `${failed} FAIL`}`);
  process.exit(failed === 0 ? 0 : 1);
})();
