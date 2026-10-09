/**
 * [R7-PAYROLL-POLICY.3 §25] snapshot 숫자가 **실제 계산에 쓰였는가**.
 *
 *   시나리오 B 는 snapshot 내용이 낡았다는 것만 보였다. 3분 조출은
 *   5/30 과 10/10 에서 같은 결과(정시)라 구분력이 없었다.
 *
 *   worker B 의 snapshot 은 10/10 이고 사업장 live 정책은 5/30 으로
 *   원복돼 있다. START + 6분에 출근하면 두 정책이 갈린다.
 *
 *     snapshot 10/10 → grace 10 ≥ 6 → **정시(START)**
 *     live     5/30  → grace 5  < 6 → 지각 ceil(6/30)*30 → **START+30**
 *
 *   적용된 checkIn 이 START 면 snapshot 이 쓰인 것이다.
 */
'use strict';
const fs = require('fs');
const lib = require('./r7-fixture-lib');
const {db} = lib;
const unwrap = (r) => (r && (r.result ?? r.data)) ?? r;
const KST = 9 * 3600000;

(async () => {
  const P = JSON.parse(fs.readFileSync('.p3fixture.json', 'utf8'));
  const biz = (await db.collection('businesses').doc(P.businessId).get()).data();
  const app = (await db.collection('applications').doc(P.appC).get()).data();
  const snap = app.attendancePolicySnapshot;
  const live = biz.attendanceRules;
  console.log('worker B snapshot : grace', snap.lateGrace,
    '/ lateUnit', snap.lateUnit);
  console.log('사업장 live 정책  : grace', live.lateGrace,
    '/ lateUnit', live.lateUnit);
  if (snap.lateGrace === live.lateGrace) {
    throw new Error('두 정책이 같아 구분할 수 없다');
  }

  const START = app.startTime;
  const [sh, sm] = START.split(':').map(Number);
  const startMs = P.workDateMs + (sh * 60 + sm) * 60000;
  const targetMs = startMs + 6 * 60000 + 15000; // START + 6분 15초
  const hhmm = (ms) => new Date(ms + KST).toISOString().slice(11, 16);
  console.log('근무 시작:', START, '| 목표 출근:', hhmm(targetMs),
    '(START + 6분)');

  while (Date.now() < targetMs) {
    await new Promise((r) => setTimeout(r, 5000));
  }
  console.log('KST 지금:', new Date(Date.now() + KST).toISOString().slice(11, 19));

  const ci = unwrap(await lib.callAs(P.uidB, 'callableCheckIn', {
    applicationId: P.appC, businessId: P.businessId,
    businessName: biz.name, workDateMs: P.workDateMs,
    workType: app.selectedWorkType, method: 'gps',
    latitude: biz.latitude, longitude: biz.longitude,
    scheduledStartTime: START,
  }));
  const att = (await db.collection('attendance').doc(ci.attendanceId).get())
    .data();
  const t = (v) => v && v.toMillis ?
    new Date(v.toMillis() + KST).toISOString().slice(11, 16) : '(없음)';
  const appliedMs = att.checkIn.toMillis();
  console.log('\n원본 출근:', t(att.originalCheckIn),
    '→ 적용:', t(att.checkIn), '| status:', att.status);
  console.log('  snapshot(10/10) 기대 :', hhmm(startMs), '(정시)');
  console.log('  live(5/30) 기대      :', hhmm(startMs + 30 * 60000), '(지각)');
  console.log('\n판정:', appliedMs === startMs ?
    '**snapshot 이 계산에 쓰였다**' :
    (appliedMs === startMs + 30 * 60000 ?
      '**live 정책이 쓰였다 — 회귀**' : '예상 밖 값'));
  process.exit(0);
})().catch((e) => { console.error('실패:', e.message); process.exit(1); });
