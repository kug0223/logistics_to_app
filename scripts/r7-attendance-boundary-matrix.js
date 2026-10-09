/**
 * [R7-ATTENDANCE-CLOCK-IN-OUT-INTEGRITY §9 §10 §11 §15]
 *
 *   경계표를 손으로 적지 않는다. CF 의 `_processCheckin` / `_processCheckout`
 *   과 **같은 식**을 옮겨 계산한다. 규칙값은 DEV 사업장 실측값이다.
 *
 *   옮긴 식이 원본과 같은지 눈으로 확인할 수 있게 주석에 원본 분기를 적는다.
 */
'use strict';

// DEV 사업장 실측 (businesses/{id}.attendanceRules)
const R = {
  earlyWindow: 30,
  earlyArrivalUnit: 30,
  lateGrace: 5,
  lateUnit: 30,
  lateWindow: 30,
  overtimeUnit: 30,
  earlyLeaveUnit: 30,
};

const hhmm = (m) => `${String(Math.floor(((m % 1440) + 1440) % 1440 / 60))
  .padStart(2, '0')}:${String(((m % 60) + 60) % 60).padStart(2, '0')}`;
const mins = (s) => {
  const [h, m] = s.split(':').map(Number);
  return h * 60 + m;
};

/** _processCheckin — 원본과 같은 분기 순서. */
function checkin(nowM, startM) {
  const offset = Math.trunc(nowM - startM);
  let rounded;
  if (offset < -R.earlyWindow) {
    rounded = Math.trunc(offset / R.earlyArrivalUnit) * R.earlyArrivalUnit;
  } else if (offset <= R.lateGrace) {
    rounded = 0;
  } else {
    rounded = Math.ceil(offset / R.lateUnit) * R.lateUnit;
  }
  return {effective: startM + rounded, isLate: offset > R.lateGrace};
}

/** _processCheckout — 원본과 같은 분기 순서. */
function checkout(nowM, endM) {
  const offset = Math.trunc(nowM - endM);
  let rounded;
  if (offset > R.lateWindow) {
    rounded = Math.floor(offset / R.overtimeUnit) * R.overtimeUnit;
  } else if (offset >= 0) {
    rounded = 0;
  } else {
    rounded = -(Math.ceil(-offset / R.earlyLeaveUnit) * R.earlyLeaveUnit);
  }
  return {effective: endM + rounded, isEarlyLeave: offset < 0};
}

console.log('규칙(DEV 실측):', JSON.stringify(R));
console.log('\n═══ §9 출근 경계 — 근무 14:00 시작 ═══');
console.log('실제    수락?  원본    해석    상태     급여 시작');
const startM = mins('14:00');
for (const t of ['13:29', '13:30', '13:59', '14:00', '14:05', '14:06',
  '14:29', '14:30', '14:31', '15:00']) {
  const nowM = mins(t);
  // 출근 하한: 약속시작 − earlyWindow 이전은 거절
  const admitted = nowM >= startM - R.earlyWindow;
  if (!admitted) {
    console.log(`${t}   거절    —       —       —        —   (아직 출근할 수 있는 시간이 아닙니다)`);
    continue;
  }
  const r = checkin(nowM, startM);
  console.log(`${t}   수락    ${t}   ${hhmm(r.effective)}   ` +
    `${(r.isLate ? 'late' : 'present').padEnd(8)} ${hhmm(r.effective)}`);
}

console.log('\n═══ §10 퇴근 경계 — 근무 14:00~18:00, 출근 14:00 기록 ═══');
console.log('실제    수락?  원본    해석    상태         급여 종료');
const endM = mins('18:00');
const ciM = mins('14:00');
for (const t of ['14:20', '15:40', '17:29', '17:30', '17:49', '17:50',
  '18:00', '18:29', '18:30', '18:40']) {
  const nowM = mins(t);
  const r = checkout(nowM, endM);
  // 반올림 결과가 출근보다 이르거나 같으면 거절
  if (r.effective <= ciM) {
    console.log(`${t}   거절    ${t}   (${hhmm(r.effective)})  —            —   (출근 시각보다 이릅니다)`);
    continue;
  }
  console.log(`${t}   수락    ${t}   ${hhmm(r.effective)}   ` +
    `${(r.isEarlyLeave ? 'early_leave' : 'present').padEnd(12)} ${hhmm(r.effective)}`);
}

console.log('\n═══ §15 짧은 근무 × 반올림 단위 ═══');
console.log('근무시간  정시퇴근(종료+1분)  조퇴 가능 최초 시각  판정');
for (const dur of [10, 20, 30, 45, 60]) {
  const s = mins('15:00');
  const e = s + dur;
  // 정시 퇴근: 종료 직후(+1분)
  const onTime = checkout(e + 1, e);
  const onTimeOk = onTime.effective > s;
  // 조퇴: 종료 전 어느 시각부터 성공하는가
  let firstEarly = null;
  for (let t = s + 1; t < e; t++) {
    const r = checkout(t, e);
    if (r.effective > s) { firstEarly = t; break; }
  }
  console.log(
    `${String(dur).padStart(4)}분    ${onTimeOk ? 'OK  ' + hhmm(onTime.effective) : '거절'}` +
    `            ${firstEarly == null ? '불가 (전 구간 거절)  ' : hhmm(firstEarly) + '              '}` +
    `  ${firstEarly == null ? '조퇴 self 불가 — 관리자 보정만' : '조퇴 가능'}`);
}

console.log('\n═══ §11 반올림 방향 ═══');
console.log('  조출(유예 밖)  trunc (0 방향)      — 근로자에게 유리/불리 중립');
console.log('  정시 유예      0 (시작시각으로)    — 유예 안은 정시');
console.log('  지각           ceil  (올림)        — **근로자 불리**');
console.log('  조퇴           ceil  (더 빼기)     — **근로자 불리**');
console.log('  연장           floor (내림)        — **근로자 불리**');
console.log('  정시 퇴근 유예  0 (종료시각으로)    — 종료 후 lateWindow 안은 정시');
