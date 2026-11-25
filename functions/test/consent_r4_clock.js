/**
 * [CONSENT-R4] 시험 공용 시계·fixture — 실행 0(이번 배정). LOCAL 에서 A_copy/functions/test/ 에 둔다.
 *
 *   · 시각은 전부 주입한다. 실제 Date.now() 를 읽지 않는다.
 *   · Ts 는 Firestore Timestamp 의 최소 모양(toMillis)만 흉내 낸다 — admin SDK 를 쓰지 않는다.
 *   · KST 날짜는 Firestore 저장 규약(그 날 KST 0시 instant)과 같다.
 */
'use strict';

const K = 9 * 3600e3;
const DAY = 24 * 3600e3;
const HOUR = 3600e3;
const MIN = 60e3;

class Ts {
  constructor(ms) { this.ms = ms; }
  toMillis() { return this.ms; }
  toDate() { return new Date(this.ms); }
  get seconds() { return Math.floor(this.ms / 1000); }
  get nanoseconds() { return (this.ms % 1000) * 1e6; }
}

/** KST 벽시계 → epoch ms. */
const kst = (y, mo, d, h = 0, mi = 0) => Date.UTC(y, mo - 1, d, h, mi) - K;
/** KST 날짜 0시의 Ts. */
const kstDay = (y, mo, d) => new Ts(kst(y, mo, d));

/** 새 세대 판본(후보 index.ts 에서 읽어 확인한다 — 여기 값은 기대값이다). */
const V4 = '2026-11-18-v4';
const INV2 = '2026-11-18-invite-v2';
/** 은퇴 판본. */
const V1 = '2026-08-21-v1';
const V2 = '2026-09-12-v2';
const V3 = '2026-09-18-v3';
const INV1 = '2026-10-15-invite-v1';
const RETIRED = [V1, V2, V3, INV1];
const CR_KIND = 'CONFIRMED_WORK_REASSIGNMENT';

/** 고정 장면: 단기 근무 2026-11-20(KST), 확정 2026-11-10. */
const WORK_DAY = kst(2026, 11, 20);
const T0 = kst(2026, 11, 10, 9, 0);   // 최초 동의(지원/사전 동의)
const T1 = kst(2026, 11, 12, 15, 0);  // 수락·재배치 시각
const PAY1 = kst(2026, 11, 25, 10, 0); // 첫 이체 완료
const PAY2 = kst(2026, 11, 27, 18, 30); // 마지막 이체 완료

const app = (o = {}) => Object.assign({
  uid: 'w1', businessId: 'b1', toId: 't1', slotId: 's1', wdId: 'wd-1',
  status: 'CONFIRMED', type: 'short', workDate: new Ts(WORK_DAY),
  documentAccessConsentGiven: true, documentAccessConsentVersion: V4,
  documentAccessConsentAt: new Ts(T0),
  idCardConsentGiven: true, idCardConsentAt: new Ts(T0),
}, o);

const att = (id, o = {}) => Object.assign({
  id, applicationId: 'a1', userId: 'w1', businessId: 'b1',
  status: 'present', wageStatus: 'transferred', finalWage: 80000,
  transferDate: new Ts(PAY1),
}, o);

const corr = (o = {}) => Object.assign({
  businessId: 'b1', workerUid: 'w1', documentType: 'BANKBOOK',
  sourceDomain: 'PAYROLL', status: 'OPEN',
}, o);

let pass = 0;
const fails = [];
async function cell(id, name, fn) {
  try {
    await fn();
    pass++;
    console.log(`  ok   ${id} ${name}`);
  } catch (e) {
    fails.push(`${id} ${name}: ${String(e && e.message).split('\n')[0]}`);
    console.log(`  FAIL ${id} ${name} — ${String(e && e.message).split('\n')[0]}`);
  }
}
function summary() {
  console.log(`\n통과 ${pass} / 실패 ${fails.length}`);
  if (fails.length) {
    fails.forEach((f) => console.log('  - ' + f));
    process.exit(1);
  }
}

module.exports = {
  K, DAY, HOUR, MIN, Ts, kst, kstDay,
  V4, INV2, V1, V2, V3, INV1, RETIRED, CR_KIND,
  WORK_DAY, T0, T1, PAY1, PAY2, app, att, corr, cell, summary,
};
