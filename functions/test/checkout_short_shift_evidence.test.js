// [R7-ATTENDANCE-SHORT-SHIFT-BOUNDARY.2] 퇴근 증거 보존 — **행동** 테스트.
//
//   실행:  cd functions && npm run build && node test/checkout_short_shift_evidence.test.js
//
//   무엇이 틀려 있었나
//
//     보정 퇴근이 보정 출근 이하로 역전되면 `callableCheckOut` 이 throw 했다.
//     그 throw 는 유일한 쓰기(`tx.update`) 보다 앞이라 **실제 퇴근 증거가
//     함께 버려졌다** — `originalCheckOut`·GPS·거리가 하나도 남지 않았고,
//     근로자는 근무를 끝낼 방법이 없었다.
//
//     역전은 두 원인에서 오고 **둘 다 허용된 설정**이다:
//       · earlyLeaveUnit 이 남은 근무보다 크다        (20분 근무 · 단위 30)
//       · lateUnit 이 보정 출근을 예정 종료 뒤로 민다 (유예초과 지각 · 단위 30)
//     기본 설정(30/30)에서 30분 이하 근무가 해당된다.
//
//   고정하는 것
//     SS-1  계산식은 그대로다 (서버 본문을 잘라 실행해 확인)
//     SS-2  정상 양수 구간은 기존과 동일하게 동작한다
//     SS-3  역전 구간은 clamp 되어 0분이 되고 음수가 저장되지 않는다
//     SS-4  writer 가 증거를 버리지 않는다 (소스 계약)
//     SS-5  `checkOut` 이 null 로 남지 않는다 → 자정 재분류 없음
//     SS-6  기존 canonical 판정이 그 기록을 검토 대상으로 잡는다
//     SS-7  급여가 자동 정상 확정되지 않는다
//     SS-8  7개 설정·허용 범위를 바꾸지 않았다
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const IDX = path.join(__dirname, '..', 'lib', 'index.js');
const SRC = path.join(__dirname, '..', 'src', 'index.ts');
const idx = fs.readFileSync(IDX, 'utf8');
const ts = fs.readFileSync(SRC, 'utf8');

let pass = 0;
const fails = [];
function t(id, fn) {
  try {
    fn();
    pass++;
    console.log(`  ok   ${id}`);
  } catch (e) {
    fails.push(`${id}: ${e.message.split('\n')[0]}`);
    console.log(`  FAIL ${id} — ${e.message.split('\n')[0]}`);
  }
}

// ── 서버 본문을 잘라 그대로 실행한다 (계산식 복제 금지) ──────────
function sliceFn(name) {
  const i = idx.indexOf('function ' + name + '(');
  assert.ok(i >= 0, name + ' 를 번들에서 찾지 못했다');
  const open = idx.indexOf('{', i);
  let d = 0; let j = open;
  for (; j < idx.length; j++) {
    if (idx[j] === '{') d++;
    else if (idx[j] === '}') { d--; if (d === 0) break; }
  }
  return idx.slice(i, j + 1);
}
// eslint-disable-next-line no-eval
const M = eval('(function(){' + sliceFn('_processCheckin') +
  sliceFn('_processCheckout') + sliceFn('_clampAttendanceRules') +
  'return {_processCheckin,_processCheckout,_clampAttendanceRules};})()');

const KST = 9 * 3600 * 1000;
const dayMs = Date.UTC(2026, 9, 15) - KST;
const mins = (s) => {
  const [h, m] = s.split(':').map(Number);
  return h * 60 + m;
};
const hhmm = (d) => {
  const t2 = new Date(d.getTime() + KST);
  return String(t2.getUTCHours()).padStart(2, '0') + ':' +
    String(t2.getUTCMinutes()).padStart(2, '0');
};

const BASE = {earlyWindow: 30, earlyArrivalUnit: 30, lateGrace: 5,
  lateUnit: 30, lateWindow: 30, overtimeUnit: 10, earlyLeaveUnit: 30};

/**
 * `callableCheckOut` 의 순서를 그대로 재생한다 — 보정 계산 → **clamp** →
 * workMins → 저장될 필드. 교대가 자정을 넘으면 시작보다 이른 시계값은
 * 다음날로 읽는다(서버가 cEnd 에 하는 보정과 같은 축).
 */
function replay({start, end, inAt, outAt, rules = BASE}) {
  const r = M._clampAttendanceRules(rules);
  const sM = mins(start);
  let eM = mins(end);
  const crosses = eM < sM;
  if (crosses) eM += 1440;
  const cStart = new Date(dayMs + sM * 60000);
  const cEnd = new Date(dayMs + eM * 60000);
  const lift = (x) => {
    let m = mins(x);
    if (crosses && m < sM) m += 1440;
    return new Date(dayMs + m * 60000);
  };

  const rawIn = lift(inAt);
  const rawOut = lift(outAt);
  const checkIn = M._processCheckin(rawIn, cStart, r).effectiveCheckIn;
  const ro = M._processCheckout(rawOut, cEnd, r);
  let effOut = ro.effectiveCheckOut;

  // ── 패치가 추가한 단 한 줄의 의미 ──
  const reversedByPolicy = effOut.getTime() <= checkIn.getTime();
  if (reversedByPolicy) effOut = checkIn;

  const workMins = Math.floor((effOut.getTime() - checkIn.getTime()) / 60000);
  return {
    rawIn, rawOut, checkIn, effOut, reversedByPolicy, workMins,
    workHours: workMins / 60,
    isZeroWork: workMins <= 0,
    isEarlyLeave: ro.isEarlyLeave,
    // 저장되는 원본 증거 (writer 가 rawOut 을 originalCheckOut 에 넣는다)
    originalCheckOut: rawOut,
  };
}

console.log('[R7-ATTENDANCE-SHORT-SHIFT-BOUNDARY.2] 퇴근 증거 보존');

// ═══════════════════════════════════════════════════════════
// SS-1 계산식 불변
// ═══════════════════════════════════════════════════════════
t('SS1-1 조퇴는 ceil, 연장은 floor, 창 이내는 0 — 공식 그대로', () => {
  const r = M._clampAttendanceRules(BASE);
  const end = new Date(dayMs + 18 * 60 * 60000);
  const out = (off) => M._processCheckout(
      new Date(end.getTime() + off * 60000), end, r).effectiveCheckOut
      .getTime() - end.getTime();
  assert.strictEqual(out(-1) / 60000, -30, '1분 조퇴 → 30분 (ceil)');
  assert.strictEqual(out(-30) / 60000, -30, '30분 조퇴 → 30분');
  assert.strictEqual(out(-31) / 60000, -60, '31분 조퇴 → 60분 (ceil)');
  assert.strictEqual(out(0) / 60000, 0, '정시');
  assert.strictEqual(out(30) / 60000, 0, '창 경계는 정시');
  assert.strictEqual(out(59) / 60000, 50, '59분 연장 → 50분 (floor·단위10)');
});

t('SS1-2 허용 범위(clamp)를 바꾸지 않았다', () => {
  const c = M._clampAttendanceRules({earlyWindow: 999, earlyArrivalUnit: 0,
    lateGrace: 999, lateUnit: 0, lateWindow: 999, overtimeUnit: 0,
    earlyLeaveUnit: 0});
  assert.deepStrictEqual(c, {earlyWindow: 120, earlyArrivalUnit: 1,
    lateGrace: 60, lateUnit: 1, lateWindow: 120, overtimeUnit: 1,
    earlyLeaveUnit: 1});
});

// ═══════════════════════════════════════════════════════════
// SS-2 정상 양수 구간은 기존과 동일
// ═══════════════════════════════════════════════════════════
t('SS2-1 20분 근무 정시 퇴근 — 20분, clamp 미발동', () => {
  const o = replay({start: '10:00', end: '10:20', inAt: '10:00',
    outAt: '10:20'});
  assert.strictEqual(o.reversedByPolicy, false);
  assert.strictEqual(o.workMins, 20);
  assert.strictEqual(o.isZeroWork, false);
});

t('SS2-2 8시간 정상 근무 — 계산·상태 변경 없음', () => {
  const o = replay({start: '09:00', end: '18:00', inAt: '09:00',
    outAt: '18:00'});
  assert.strictEqual(o.reversedByPolicy, false);
  assert.strictEqual(o.workMins, 540);
  assert.strictEqual(o.workHours, 9);
  assert.strictEqual(o.isZeroWork, false);
});

t('SS2-3 8시간 근무 · 30분 조퇴 — 기존 반올림 그대로', () => {
  const o = replay({start: '09:00', end: '18:00', inAt: '09:00',
    outAt: '17:30'});
  assert.strictEqual(o.reversedByPolicy, false);
  assert.strictEqual(hhmm(o.effOut), '17:30');
  assert.strictEqual(o.workMins, 510);
});

t('SS2-4 연장 근무 — 기존 floor 그대로', () => {
  const o = replay({start: '09:00', end: '18:00', inAt: '09:00',
    outAt: '19:00'});
  assert.strictEqual(o.reversedByPolicy, false);
  assert.strictEqual(hhmm(o.effOut), '19:00');
  assert.strictEqual(o.workMins, 600);
});

t('SS2-5 자정을 넘는 근무 — 정상 인정 (재분류 아님)', () => {
  const a = replay({start: '22:00', end: '00:20', inAt: '22:00',
    outAt: '00:20'});
  assert.strictEqual(a.reversedByPolicy, false);
  assert.strictEqual(a.workMins, 140);
  const b = replay({start: '22:00', end: '06:00', inAt: '22:00',
    outAt: '05:30'});
  assert.strictEqual(b.reversedByPolicy, false);
  assert.strictEqual(b.workMins, 450);
});

// ═══════════════════════════════════════════════════════════
// SS-3 역전 구간 — clamp 되고 음수가 저장되지 않는다
// ═══════════════════════════════════════════════════════════
t('SS3-1 20분 근무 · 10분 조퇴 (단위30) — 예전엔 거부, 이제 0분', () => {
  const o = replay({start: '10:00', end: '10:20', inAt: '10:00',
    outAt: '10:10'});
  assert.strictEqual(o.reversedByPolicy, true, '역전이 일어나야 한다');
  assert.strictEqual(o.workMins, 0, '0분');
  assert.ok(o.workMins >= 0, '음수가 저장되지 않는다');
  assert.strictEqual(o.isZeroWork, true);
  // 보정 퇴근이 보정 출근과 같아진다 — 그 이전이 아니다
  assert.strictEqual(o.effOut.getTime(), o.checkIn.getTime());
});

t('SS3-2 20분 근무 · 1분 조퇴 — 같은 처리', () => {
  const o = replay({start: '10:00', end: '10:20', inAt: '10:00',
    outAt: '10:19'});
  assert.strictEqual(o.reversedByPolicy, true);
  assert.strictEqual(o.workMins, 0);
});

t('SS3-3 60분 근무 · 지각단위 60 · 정시퇴근 — 두 번째 원인도 clamp', () => {
  const o = replay({start: '10:00', end: '11:00', inAt: '10:06',
    outAt: '11:00', rules: {...BASE, lateUnit: 60}});
  assert.strictEqual(o.reversedByPolicy, true);
  assert.strictEqual(o.workMins, 0);
  assert.ok(o.workMins >= 0);
});

t('SS3-4 120분 근무 · 지각단위 120 · 정시퇴근', () => {
  const o = replay({start: '10:00', end: '12:00', inAt: '10:06',
    outAt: '12:00', rules: {...BASE, lateUnit: 120}});
  assert.strictEqual(o.reversedByPolicy, true);
  assert.strictEqual(o.workMins, 0);
});

t('SS3-5 어떤 허용 조합에서도 음수 근무시간이 생기지 않는다', () => {
  const units = [1, 5, 10, 30, 60];
  for (const len of [5, 10, 20, 30, 60, 120]) {
    for (const el of units) {
      for (const lu of [1, 5, 10, 30, 60, 120]) {
        const eM = 600 + len;
        const end = String(Math.floor(eM / 60)).padStart(2, '0') + ':' +
          String(eM % 60).padStart(2, '0');
        for (const inAt of ['10:00', '10:06']) {
          for (const dOut of [0, -1, -len + 1 > 0 ? -(len - 1) : 0]) {
            const om = eM + dOut;
            const outAt = String(Math.floor(om / 60)).padStart(2, '0') + ':' +
              String(om % 60).padStart(2, '0');
            const o = replay({start: '10:00', end, inAt, outAt,
              rules: {...BASE, earlyLeaveUnit: el, lateUnit: lu}});
            assert.ok(o.workMins >= 0,
              `음수 발생: len=${len} el=${el} lu=${lu} in=${inAt} out=${outAt}` +
              ` → ${o.workMins}`);
            assert.ok(o.effOut.getTime() >= o.checkIn.getTime(),
              `역전 잔존: len=${len} el=${el} lu=${lu}`);
          }
        }
      }
    }
  }
});

// ═══════════════════════════════════════════════════════════
// SS-4 writer 가 증거를 버리지 않는다 (소스 계약)
// ═══════════════════════════════════════════════════════════
function checkoutSrc() {
  const i = ts.indexOf('export const callableCheckOut');
  assert.ok(i >= 0);
  const j = ts.indexOf('\nexport const ', i + 10);
  return ts.slice(i, j < 0 ? ts.length : j);
}

t('SS4-1 역전에서 더는 throw 하지 않는다', () => {
  const b = checkoutSrc();
  assert.ok(!b.includes('퇴근 처리 불가: 계산된 퇴근 시각이'),
    '옛 거부 문구가 남아 있다');
  assert.ok(b.includes('const reversedByPolicy ='),
    'clamp 판정이 없다');
  assert.ok(b.includes('if (reversedByPolicy) effectiveCheckOut = checkInAt;'),
    'clamp 가 없다');
});

t('SS4-2 원본 퇴근·위치 증거를 그대로 저장한다', () => {
  const b = checkoutSrc();
  // 원본은 없을 때만 1회 — 절대 불변
  assert.ok(b.includes('if (data.originalCheckOut == null)'),
    'originalCheckOut 불변 보장이 없다');
  assert.ok(b.includes('update.originalCheckOut ='));
  assert.ok(b.includes('update.checkOutLat = latitude;'));
  assert.ok(b.includes('update.checkOutLng = longitude;'));
  assert.ok(b.includes('update.checkOutDistance = checkOutLoc.distanceMeters;'));
  // clamp 가 원본을 덮지 않는다 — 덮는 건 effectiveCheckOut 뿐이다
  assert.ok(!/reversedByPolicy\)\s*(update\.)?originalCheckOut/.test(b),
    'clamp 가 원본을 건드린다');
});

t('SS4-3 인증·권한·위치·중복 게이트가 그대로다', () => {
  const b = checkoutSrc();
  for (const must of [
    '"unauthenticated", "로그인이 필요합니다."',
    '본인의 출근 기록만 퇴근할 수 있습니다.',
    '이미 퇴근하셨습니다.',
    '미퇴근 처리된 기록입니다.',
    '임금이 확정된 기록은 수정할 수 없습니다.',
    'srvAssertSelfAttendanceLocation(',
  ]) {
    assert.ok(b.includes(must), `게이트 소실: ${must}`);
  }
});

t('SS4-4 게이트들이 유일한 쓰기보다 앞이다', () => {
  const b = checkoutSrc();
  const w = b.indexOf('tx.update(ref, update)');
  assert.ok(w > 0);
  for (const must of ['srvAssertSelfAttendanceLocation(',
    '이미 퇴근하셨습니다.', '임금이 확정된 기록은 수정할 수 없습니다.']) {
    assert.ok(b.indexOf(must) < w, `${must} 가 쓰기 뒤에 있다`);
  }
  // 쓰기는 한 곳뿐이다
  assert.strictEqual((b.match(/tx\.update\(/g) || []).length, 1);
});

t('SS4-5 clamp 가 정상 양수 분기를 건드리지 않는다', () => {
  const b = checkoutSrc();
  // clamp 는 조건부 한 줄이고, workMins 계산은 그 뒤 한 번만 있다
  assert.strictEqual(
    (b.match(/if \(reversedByPolicy\) effectiveCheckOut = checkInAt;/g) || [])
        .length, 1);
  assert.strictEqual((b.match(/const workMins = Math\.floor/g) || []).length, 1);
});

// ═══════════════════════════════════════════════════════════
// SS-5 checkOut 이 null 로 남지 않는다 → 자정 재분류 없음
// ═══════════════════════════════════════════════════════════
t('SS5-1 clamp 뒤에도 checkOut 이 반드시 기록된다', () => {
  const b = checkoutSrc();
  assert.ok(b.includes('checkOut: admin.firestore.Timestamp.fromDate(effectiveCheckOut)'),
    'checkOut 쓰기가 없다');
  // 역전 분기에서 조기 return 하지 않는다
  assert.ok(!/reversedByPolicy\)\s*return/.test(b), '역전에서 빠져나간다');
});

t('SS5-2 scheduler 는 checkOut == null 만 본다 — 재분류 조건에 걸리지 않는다', () => {
  const s = ts.indexOf('async function processMissedCheckouts');
  assert.ok(s >= 0);
  const body = ts.slice(s, s + 2000);
  assert.ok(body.includes('.where("checkOut", "==", null)'),
    'scheduler 조건이 바뀌었다 — 이 테스트의 전제가 깨졌다');
  // 그러므로 checkOut 이 채워진 기록은 질의에 잡히지 않는다.
  const o = replay({start: '10:00', end: '10:20', inAt: '10:00',
    outAt: '10:10'});
  assert.ok(o.effOut instanceof Date, 'checkOut 값이 존재한다');
});

// ═══════════════════════════════════════════════════════════
// SS-6 기존 canonical 판정이 검토 대상으로 잡는다
// ═══════════════════════════════════════════════════════════
t('SS6-1 조퇴 원인 — 보정 퇴근이 예정 종료보다 이르다 (isEarlyLeave 축)', () => {
  const o = replay({start: '10:00', end: '10:20', inAt: '10:00',
    outAt: '10:10'});
  const endM = mins('10:20');
  const outM = mins(hhmm(o.effOut));
  assert.ok(outM < endM,
    `보정 퇴근 ${hhmm(o.effOut)} 이 예정 종료 10:20 보다 이르지 않다`);
});

t('SS6-2 지각 원인 — 보정 출근이 지각이다 (isLate 축)', () => {
  const o = replay({start: '10:00', end: '11:00', inAt: '10:06',
    outAt: '11:00', rules: {...BASE, lateUnit: 60}});
  const startM = mins('10:00');
  const inM = mins(hhmm(o.checkIn));
  assert.ok(inM > startM,
    `보정 출근 ${hhmm(o.checkIn)} 이 예정 시작보다 늦지 않다`);
});

t('SS6-3 판정 술어를 새로 만들지 않았다 — 기존 공용 판정을 쓴다', () => {
  const helper = fs.readFileSync(
      path.join(__dirname, '..', '..', 'lib', 'utils',
        'attendance_review_helper.dart'), 'utf8');
  assert.ok(helper.includes('static bool requiresReviewNow('),
    '공용 판정이 없다');
  // 두 축을 모두 본다
  assert.ok(helper.includes('return isLate || isEarlyLeave;'),
    '검토 판정이 두 축을 보지 않는다');
  // 관리자 다이얼로그·Home 이 같은 것을 쓴다
  const dlg = fs.readFileSync(
      path.join(__dirname, '..', '..', 'lib', 'screens', 'business_admin',
        'dialogs', 'attendance_status_dialog.dart'), 'utf8');
  assert.ok(dlg.includes('AttendanceReviewHelper.requiresReviewNow('),
    '관리자 검토 탭이 공용 판정을 쓰지 않는다');
});

t('SS6-4 새 status·새 필드를 만들지 않았다', () => {
  const b = checkoutSrc();
  // VALID_ATTENDANCE_STATUS 밖의 값을 쓰지 않는다
  for (const bad of ['"policy_reversed"', '"needs_review"', '"zero_work"',
    'reviewRequired']) {
    assert.ok(!b.includes(bad), `새 상태를 만들었다: ${bad}`);
  }
  const valid = ts.indexOf('const VALID_ATTENDANCE_STATUS');
  const set = ts.slice(valid, valid + 140);
  assert.ok(set.includes('"present"') && set.includes('"late"') &&
    set.includes('"early_leave"') && set.includes('"absent"'),
  '허용 status 집합이 바뀌었다');
});

// ═══════════════════════════════════════════════════════════
// SS-9 관리자 정정 — 증거 불변 · 검토 표식 갱신 · 게이트 유지
// ═══════════════════════════════════════════════════════════
function adjustSrc() {
  const i = ts.indexOf('export const callableBatchAdjustAttendanceTime');
  assert.ok(i >= 0);
  const j = ts.indexOf('\nexport const ', i + 10);
  return ts.slice(i, j < 0 ? ts.length : j);
}

t('SS9-1 정정이 원본 증거를 건드리지 않는다', () => {
  const b = adjustSrc();
  assert.ok(!b.includes('updates["originalCheckOut"]'),
    '정정이 originalCheckOut 을 덮는다');
  assert.ok(!b.includes('updates["originalCheckIn"]'),
    '정정이 originalCheckIn 을 덮는다');
  // 보정값만 바꾼다
  assert.ok(b.includes('updates["checkOut"] ='));
  assert.ok(b.includes('updates["checkOutMethod"] = "manual"'),
    '관리자 입력임을 표시하지 않는다');
});

t('SS9-2 정정이 isZeroWork 를 갱신한다 — 낡은 0분 표식이 남지 않는다', () => {
  const b = adjustSrc();
  assert.ok(b.includes('updates["isZeroWork"]'),
    '정정 후 0분 표식이 갱신되지 않는다');
  // 양수 구간이면 false 로 내려간다
  assert.ok(b.includes('checkOutMs <= checkInMs'),
    '표식 판정이 시각 비교가 아니다');
});

t('SS9-3 권한·사유·소급 제한이 그대로다', () => {
  const b = adjustSrc();
  for (const must of ['canManageWorkers', 'ADJUST_REASON_MAX',
    'ninetyDaysAgo', 'VALID_ATTENDANCE_STATUS']) {
    assert.ok(b.includes(must), `정정 게이트 소실: ${must}`);
  }
  // 역전 입력 자체는 여전히 거부한다 — 관리자도 음수를 만들 수 없다
  assert.ok(b.includes('checkInMs >= checkOutMs'),
    '관리자 역전 입력 거부가 사라졌다');
});

t('SS9-4 정정이 선택할 status 는 허용 집합 안이다', () => {
  const helper = fs.readFileSync(
      path.join(__dirname, '..', '..', 'lib', 'utils',
        'attendance_status_helper.dart'), 'utf8');
  const i = helper.indexOf('static String deriveStatus(');
  const b = helper.slice(i, i + 1400);
  // 파생값 셋 — 모두 VALID_ATTENDANCE_STATUS 안이다
  assert.ok(b.includes('statusEarlyLeave'));
  assert.ok(b.includes('statusLate'));
  assert.ok(b.includes('statusPresent'));
  assert.ok(!b.includes('missed_checkout'),
    '정정이 missed_checkout 을 되돌려 보내면 조용히 skip 된다');
});

t('SS9-5 정정 뒤에도 조퇴 기록은 검토 대상으로 남는다', () => {
  // 실제 시각(10:00~10:10, 예정 종료 10:20)으로 고치면 여전히 조퇴다.
  //   `requiresReviewNow` 의 마지막 분기가 isEarlyLeave 로 잡는다 →
  //   관리자가 `adminConfirmed` 또는 급여 계산으로 닫을 때까지 남는다.
  const helper = fs.readFileSync(
      path.join(__dirname, '..', '..', 'lib', 'utils',
        'attendance_review_helper.dart'), 'utf8');
  assert.ok(helper.includes('if (att.adminConfirmed) return true;'),
    'adminConfirmed 가 검토를 닫지 않는다');
  assert.ok(helper.includes('att.wageStatus == AttendanceModel.wageCalculated'),
    '급여 계산이 검토를 닫지 않는다');
});

// ═══════════════════════════════════════════════════════════
// SS-10 근로자 안내 — 두 사실을 구분한다
// ═══════════════════════════════════════════════════════════
t('SS10-1 0분이면 "퇴근 완료" 로만 말하지 않는다', () => {
  const scr = fs.readFileSync(
      path.join(__dirname, '..', '..', 'lib', 'screens', 'user',
        'attendance_check_screen.dart'), 'utf8');
  const i = scr.indexOf('Future<void> _checkOut(');
  const j = scr.indexOf('\n  Future<void> _respondToReconfirm', i);
  const b = scr.slice(i, j < 0 ? i + 4000 : j);
  assert.ok(b.includes("att?.isZeroWork == true"),
    '0분 여부로 분기하지 않는다');
  assert.ok(b.includes('퇴근 시각은 기록됐어요'),
    '실제 퇴근이 기록됐다는 사실을 말하지 않는다');
  assert.ok(b.includes('관리자 확인이 필요합니다'),
    '관리자 확인 필요를 말하지 않는다');
  // 0분 분기에서는 성공 토스트가 뜨지 않는다
  const zi = b.indexOf("att?.isZeroWork == true");
  const ei = b.indexOf('} else {', zi);
  assert.ok(zi > 0 && ei > zi);
  assert.ok(!b.slice(zi, ei).includes('퇴근이 완료되었습니다'),
    '0분인데 완료라고 말한다');
});

t('SS10-2 정상 경로의 기존 안내는 그대로다', () => {
  const scr = fs.readFileSync(
      path.join(__dirname, '..', '..', 'lib', 'screens', 'user',
        'attendance_check_screen.dart'), 'utf8');
  assert.ok(scr.includes("ToastHelper.showSuccess('퇴근이 완료되었습니다!')"),
    '정상 완료 토스트가 사라졌다');
  assert.ok(scr.includes('_showRoundingFeedback(work.id, isCheckIn: false)'),
    '기존 반올림 안내가 사라졌다');
});

t('SS10-3 모델이 이미 isZeroWork 를 읽는다 — 새 필드를 만들지 않았다', () => {
  const m = fs.readFileSync(
      path.join(__dirname, '..', '..', 'lib', 'models', 'core',
        'attendance_model.dart'), 'utf8');
  assert.ok(m.includes("isZeroWork:       map['isZeroWork'] as bool? ?? false"),
    '모델이 isZeroWork 를 파싱하지 않는다');
});

// ═══════════════════════════════════════════════════════════
// SS-7 급여가 자동 정상 확정되지 않는다
// ═══════════════════════════════════════════════════════════
t('SS7-1 확정은 wageStatus=calculated 만 받는다 (관리자 계산 선행)', () => {
  const i = ts.indexOf('export const callableConfirmFinalWage');
  assert.ok(i >= 0);
  const b = ts.slice(i, i + 20000);
  assert.ok(/wageStatus\s*!==\s*"calculated"/.test(b) ||
    b.includes('calculated 아님'),
  '확정이 calculated 전제를 보지 않는다');
});

t('SS7-2 isZeroWork 가 금액을 만들지 않는다 — 급여 산식 미변경', () => {
  // 패치는 급여 쪽을 건드리지 않는다.
  const wage = ts.indexOf('export const callableCalculateAndConfirmWage');
  assert.ok(wage >= 0);
  const b = ts.slice(wage, wage + 40000);
  assert.ok(!b.includes('isZeroWork'),
    '급여 계산이 isZeroWork 에 의존하기 시작했다');
});

// ═══════════════════════════════════════════════════════════
// SS-8 설정·고지 불변
// ═══════════════════════════════════════════════════════════
t('SS8-1 7개 설정 목록이 그대로다', () => {
  const i = ts.indexOf('const ATTENDANCE_POLICY_MATERIAL_FIELDS');
  const b = ts.slice(i, i + 400);
  for (const f of ['earlyWindow', 'earlyArrivalUnit', 'lateGrace', 'lateUnit',
    'lateWindow', 'overtimeUnit', 'earlyLeaveUnit']) {
    assert.ok(b.includes(`"${f}"`), `설정 누락: ${f}`);
  }
});

t('SS8-2 최소 근무시간을 강제하지 않았다', () => {
  const b = checkoutSrc();
  for (const bad of ['minWorkMinutes', 'MIN_WORK', '최소 근무']) {
    assert.ok(!b.includes(bad), `최소 근무시간 강제: ${bad}`);
  }
});

console.log('');
if (fails.length) {
  console.log(`${pass} passed, ${fails.length} failed`);
  for (const f of fails) console.log('  - ' + f);
  process.exit(1);
}
console.log(`${pass} passed, 0 failed`);
