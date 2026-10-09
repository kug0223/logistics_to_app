/**
 * [R7-PAYROLL-ROUNDING-POLICY §18 §19 §20] 영향 산출.
 *
 *   CF 의 `_processCheckin` / `_processCheckout` 과 **같은 식**으로 계산한다.
 *   급여 인정시간은 현재 구조에서 근태 적용시간과 **같다**
 *   (wage_confirm_dialog 가 attendance.checkIn/checkOut 을 보낸다).
 */
'use strict';

const R = {
  earlyWindow: 30, earlyArrivalUnit: 30, lateGrace: 5, lateUnit: 30,
  lateWindow: 30, overtimeUnit: 30, earlyLeaveUnit: 30,
};
const WAGE_PER_HOUR = 12000;
const perMin = WAGE_PER_HOUR / 60;

const m = (s) => {
  const [h, x] = s.split(':').map(Number);
  return h * 60 + x;
};
const hhmm = (v) => `${String(Math.floor(v / 60)).padStart(2, '0')}:` +
  `${String(v % 60).padStart(2, '0')}`;
const signed = (minForWorker) => {
  if (minForWorker === 0) return ['    0분', '0원'];
  const sgn = minForWorker > 0 ? '+' : '-';
  return [
    (sgn + Math.abs(minForWorker) + '분').padStart(6),
    sgn + Math.round(Math.abs(minForWorker) * perMin).toLocaleString('ko-KR') + '원',
  ];
};
const won = (v) => `${Math.round(v).toLocaleString('ko-KR')}원`;

function checkin(now, start) {
  const off = Math.trunc(now - start);
  let r;
  if (off < -R.earlyWindow) {
    r = Math.trunc(off / R.earlyArrivalUnit) * R.earlyArrivalUnit;
  } else if (off <= R.lateGrace) r = 0;
  else r = Math.ceil(off / R.lateUnit) * R.lateUnit;
  return {eff: start + r, late: off > R.lateGrace};
}
function checkout(now, end) {
  const off = Math.trunc(now - end);
  let r;
  if (off > R.lateWindow) r = Math.floor(off / R.overtimeUnit) * R.overtimeUnit;
  else if (off >= 0) r = 0;
  else r = -(Math.ceil(-off / R.earlyLeaveUnit) * R.earlyLeaveUnit);
  return {eff: end + r, early: off < 0};
}

const START = m('14:00');
const END = m('18:00');

console.log(`규칙: lateGrace ${R.lateGrace} · lateUnit ${R.lateUnit} · ` +
  `earlyLeaveUnit ${R.earlyLeaveUnit} · overtimeUnit ${R.overtimeUnit} · ` +
  `시급 ${won(WAGE_PER_HOUR)}`);
console.log('\n═══ §18 출근 (근무 14:00 시작) ═══');
console.log('실제    수락  상태     근태적용  급여인정  실제대비   금액차이');
for (const t of ['13:30', '13:59', '14:00', '14:05', '14:06',
  '14:29', '14:30', '14:31']) {
  const now = m(t);
  if (now < START - R.earlyWindow) {
    console.log(`${t}   거절   —        —        —        —          —`);
    continue;
  }
  const r = checkin(now, START);
  // 실제 근로로 볼 수 있는 시작은 max(실제 punch, 약속 시작) —
  //   약속 전 대기는 §8 에서 따로 정의할 문제라 여기서는 분리해 적는다.
  const payableIfActual = Math.max(now, START);
  // 근로자 기준 증감(분): 인정 − 실제. 음수면 손실, 양수면 더 인정.
  const delta = payableIfActual - r.eff;
  const [dm, dw] = signed(delta);
  console.log(`${t}   수락   ${(r.late ? 'late' : 'present').padEnd(8)}` +
    ` ${hhmm(r.eff)}     ${hhmm(r.eff)}     ${dm}   ${dw}`);
}

console.log('\n═══ §18 퇴근 (근무 ~18:00 종료, 출근 14:00 기록) ═══');
console.log('실제    수락  상태         근태적용  급여인정  실제대비   금액차이');
for (const t of ['17:29', '17:30', '17:49', '17:50', '18:00',
  '18:29', '18:30', '18:40']) {
  const now = m(t);
  const r = checkout(now, END);
  if (r.eff <= START) {
    console.log(`${t}   거절   —            (${hhmm(r.eff)})   —        —          —`);
    continue;
  }
  // 실제 근로 종료로 볼 수 있는 값 — 연장 승인 문제는 §9 에서 따로 본다.
  const payableIfActual = now;
  const delta = r.eff - payableIfActual;
  const [dm, dw] = signed(delta);
  console.log(`${t}   수락   ${(r.early ? 'early_leave' : 'present').padEnd(12)}` +
    ` ${hhmm(r.eff)}     ${hhmm(r.eff)}     ${dm}   ${dw}`);
}

console.log('\n═══ §19 대표 사례의 1회 금액 ═══');
const cases = [
  ['6분 지각 (14:06 출근)', 24],
  ['31분 조퇴 (17:29 퇴근)', 29],
  ['10분 조퇴 (17:50 퇴근)', 20],
  ['40분 연장 (18:40 퇴근)', 10],
  ['29분 연장 (18:29 퇴근)', 29],
  ['6분 지각 + 31분 조퇴', 53],
];
for (const [label, lost] of cases) {
  console.log(`  ${label.padEnd(26)} ${String(lost).padStart(2)}분 미지급 ` +
    `= ${won(lost * perMin)}`);
}

console.log('\n═══ §20 누적 (같은 패턴 반복) ═══');
console.log('패턴                        월 10회        월 20회');
for (const [label, lost] of cases) {
  console.log(`  ${label.padEnd(26)} ${won(lost * perMin * 10).padStart(10)}` +
    `  ${won(lost * perMin * 20).padStart(10)}`);
}

console.log('\n═══ 방향 비대칭 요약 ═══');
console.log('  지각 ceil  · 조퇴 ceil · 연장 floor → 세 방향 모두 근로자 불리');
console.log('  유리하게 작동하는 구간: 종료 후 lateWindow(30분) 이내는 정시 처리');
const gain = 29; // 18:29 퇴근 → 18:00 인정이 아니라, 18:00~18:29 는 미지급
console.log(`  (그 구간은 '더 받는' 것이 아니라 ${gain}분까지 '안 받는' 것이다 —`);
console.log('   정시보다 일찍 끝나도 종료시각으로 올려 주는 보정은 없다)');
