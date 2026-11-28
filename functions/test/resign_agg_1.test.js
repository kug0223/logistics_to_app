'use strict';
/**
 * [BL284-01 · C288-01 · 판정288] 퇴사 요청 집계 A안 — writer 전이 · KST 경계 · 재시도 · scheduler 재검증 · 홈 3 aggregate.
 *
 *   대상: A index.ts 원문 폐포를 auth_kakao_index_harness.loadIndexClosure 로 실행한다(재구현 0) + 순수 모듈 lib/resign_agg.js.
 *   가짜 저장소(consent_r4d_fakestore) 위에서만 돈다 — 네트워크·실제 Firestore 0.
 *   가짜 저장소 보강(이 파일 안에서만): ① tx.get(count()) 집계 읽기 ② runTransaction 옵션 기록(readOnly) ③ 1회 재시도 모사.
 *   한계: 가짜 저장소의 범위 비교는 null < Timestamp 로 본다(실제 Firestore 는 형이 다르면 범위 필터에 안 잡힌다).
 *         그래서 'false + null' 같은 형 불량은 순수 분류(T02)와 backfill 시험에서 다루고 홈 count 시험에는 넣지 않는다.
 *
 *   RA1_NEGCTL=1 이면 음성 대조 모드 — 이 파일을 판정288 이전 index.ts(bd0d042a) 사본 옆에서 돌려 C288-01 반례가
 *   실제로 재현되는지(과거 요청 A 의 후보로 새 요청 B 가 조기 승인)만 확인한다.
 */
process.env.TZ = 'UTC';
const {test} = require('node:test');
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const {createFakeFirestore} = require('./consent_r4d_fakestore');
const {loadIndexClosure} = require('./auth_kakao_index_harness');

const NEGCTL = process.env.RA1_NEGCTL === '1';
const RealDate = Date;
const H = 3600 * 1000;
const DAY = 24 * H;
const KST = 9 * H;
const kstMid = (y, m, d) => RealDate.UTC(y, m - 1, d) - KST; // KST y-m-d 00:00 의 UTC ms
let NOW = kstMid(2026, 11, 26) + 12 * H;
class FakeDate extends RealDate {
  constructor(...a) { if (a.length === 0) super(NOW); else super(...a); }
  static now() { return NOW; }
}
class HttpsError extends Error {
  constructor(code, message, details) { super(message); this.code = code; this.details = details; }
}
const LOGS = [];
const QCON = {};
for (const k of ['log', 'info', 'warn', 'error', 'debug']) QCON[k] = (...a) => LOGS.push(a.map(String).join(' '));
const F = createFakeFirestore({now: () => NOW});
const Ts = F.Ts;

// ── 가짜 저장소 보강: 집계 읽기 · 거래 옵션 · 재시도 모사 ─────────────────────────
const TXLOG = [];
const plan = {retryOnce: null, aggFail: null, aggOverride: null};
const origRT = F.db.runTransaction;
F.db.runTransaction = async (cb, opts) => {
  const rec = {opts: opts || null, aggReads: 0, writes: 0, attempts: 0};
  TXLOG.push(rec);
  const wrap = (tx) => {
    const t2 = Object.assign({}, tx);
    t2.get = async (x) => {
      if (x && !x.__kind && typeof x.get === 'function') { // count() 집계 쿼리
        const n = ++rec.aggReads; // 호출 순서(1=전체 · 2=manual · 3=soon) — await 전에 고정
        if (plan.aggFail && plan.aggFail(n)) throw new Error('synthetic aggregate failure');
        const r = await x.get();
        if (plan.aggOverride) return {data: () => ({count: plan.aggOverride(n, r.data().count)})};
        return r;
      }
      return tx.get(x);
    };
    for (const k of ['set', 'update', 'create', 'delete']) {
      t2[k] = (...a) => {
        if (opts && opts.readOnly) throw new Error('read-only transaction write');
        rec.writes++; tx[k](...a); return t2;
      };
    }
    return t2;
  };
  if (plan.retryOnce) {
    const nextNow = plan.retryOnce;
    plan.retryOnce = null;
    F.hooks.beforeCommit = () => { F.hooks.beforeCommit = null; throw Object.assign(new Error('ABORTED (synthetic)'), {code: 10}); };
    rec.attempts++;
    try { await origRT((tx) => cb(wrap(tx))); } catch (e) { /* 첫 attempt 폐기 */ }
    NOW = nextNow;
  }
  rec.attempts++;
  return origRT((tx) => cb(wrap(tx)));
};

const ROOTS = NEGCTL ? ['processContractRenewalChecks'] : [
  'callableRequestResignation', 'callableCancelResignRequest', 'callableRejectResignation', 'callableApproveResignation',
  'processContractRenewalChecks', 'srvHomeResignRequest', 'srvResignDerivedFields', 'srvProcessResignAutoApproveD3',
];
const {exports: X, info} = loadIndexClosure(ROOTS, F, {HttpsError, console: QCON, Date: FakeDate});
console.log('[폐포] ' + info + (NEGCTL ? ' · NEGCTL' : ''));
const SRC = fs.readFileSync(path.join(__dirname, '..', 'src', 'index.ts'), 'utf8');
const AG = NEGCTL ? null : require(path.join(__dirname, '..', 'lib', 'resign_agg.js'));

const call = (fn, data, uid) => fn({data, auth: uid ? {uid, token: {}} : undefined});
const like = (ms, ns) => ({seconds: Math.floor(ms / 1000), nanoseconds: ns != null ? ns : ((ms % 1000) + 1000) % 1000 * 1e6});
const isTs = (v) => v instanceof Ts;
function reset() {
  F.reset();
  TXLOG.length = 0; LOGS.length = 0;
  plan.retryOnce = null; plan.aggFail = null; plan.aggOverride = null;
}
function seedBiz(bid = 'b1') {
  F.put('businesses/' + bid, {name: '사업장', ownerId: 'own1', adminIds: ['own1']});
  F.put('users/own1', {role: 'BUSINESS_ADMIN', accountStatus: 'active', name: '사장', businessId: bid});
  F.put('users/w1', {role: 'USER', accountStatus: 'active', name: '근로자'});
}
function seedApp(id, o) {
  F.put('applications/' + id, Object.assign({uid: 'w1', businessId: 'b1', businessName: '사업장', applicantName: '근로자',
    status: 'CONFIRMED', toId: 't1'}, o));
}
const notifDocs = () => Object.keys(F.dump()).filter((k) => /^users\/[^/]+\/notifications\//.test(k));
const exitLogs = () => Object.keys(F.dump()).filter((k) => k.startsWith('exit_decision_log/'));
/** 비소급 PENDING 문서 — 원필드에서 정확한 파생값을 함께 만든다. */
function pendingDoc(rMs, effMs, cycle, extra) {
  const r = new Ts(rMs); const eff = new Ts(effMs);
  const d = X.srvResignDerivedFields ? X.srvResignDerivedFields(eff, r) : {};
  return Object.assign({resignStatus: 'PENDING', resignRequestedAt: r, resignRequestDate: eff, resignDecisionCycle: cycle}, d, extra || {});
}
async function runScheduler(nowMs) {
  NOW = nowMs;
  await X.processContractRenewalChecks(new Ts(nowMs));
}

if (NEGCTL) {
  // ── 음성 대조: 판정288 이전 원문에서 C288-01 반례가 재현되는가 ─────────────────
  test('NEG-C288 이전 원문 — 후보 A 를 읽은 뒤 취소→새 요청 B 로 바뀌면 B 가 A 효력일로 조기 승인된다(반례 재현)', async () => {
    reset(); seedBiz();
    const T = kstMid(2026, 11, 26);
    const aEff = kstMid(2026, 11, 28);
    F.put('applications/c1', {uid: 'w1', businessId: 'b1', businessName: '사업장', applicantName: '근로자', status: 'CONFIRMED',
      resignStatus: 'PENDING', resignRequestedAt: new Ts(T - 4 * DAY), resignRequestDate: new Ts(aEff), resignDecisionCycle: 1});
    const bReq = T + 60 * 1000;
    let swapped = false;
    F.hooks.afterGet = (p) => {
      if (!swapped && p === 'businesses/b1') {
        swapped = true;
        F.put('applications/c1', {uid: 'w1', businessId: 'b1', businessName: '사업장', applicantName: '근로자', status: 'CONFIRMED',
          resignStatus: 'PENDING', resignRequestedAt: new Ts(bReq), resignRequestDate: new Ts(kstMid(2026, 12, 20)), resignDecisionCycle: 2});
      }
    };
    await runScheduler(T + 5 * 60 * 1000);
    F.hooks.afterGet = null;
    const a = F.get('applications/c1');
    assert.ok(swapped, '교체 hook 이 실행됨');
    assert.strictEqual(a.resignStatus, 'AUTO_APPROVED', '이전 원문은 새 요청 B 를 자동 승인한다(반례)');
    assert.strictEqual(a.actualResignDate.toMillis(), aEff, '효력일은 거래 밖 후보 A 의 값');
  });
} else {
  // ── 1. 순수 계산 · 경계 ─────────────────────────────────────────────────────
  test('T01 ceilKSTMidnight(r+72h) — 정각 유지 · +1ms/+1ns 다음 자정 · 정오 · 자정 직전 (판정288 표)', () => {
    const at = (ms, ns) => AG.resignAutoApproveAtSeconds(like(ms, ns)) * 1000;
    const m26 = kstMid(2026, 11, 26);
    assert.strictEqual(at(m26), kstMid(2026, 11, 29), '정각 → 요청일+3일 시작');
    assert.strictEqual(at(m26 + 1), kstMid(2026, 11, 30), '+1ms');
    assert.strictEqual(AG.resignAutoApproveAtSeconds({seconds: m26 / 1000, nanoseconds: 1}) * 1000, kstMid(2026, 11, 30), '+1ns');
    assert.strictEqual(at(m26 + 12 * H), kstMid(2026, 11, 30), '정오');
    assert.strictEqual(AG.resignAutoApproveAtSeconds({seconds: (kstMid(2026, 11, 27) / 1000) - 1, nanoseconds: 999999999}) * 1000,
      kstMid(2026, 11, 30), '23:59:59.999999999');
    // 말일·연말·윤일
    assert.strictEqual(at(kstMid(2026, 12, 30) + H), kstMid(2027, 1, 3));
    assert.strictEqual(at(kstMid(2028, 2, 27) + H), kstMid(2028, 3, 2), '윤년 2/29 포함');
    assert.strictEqual(at(kstMid(2028, 2, 26)), kstMid(2028, 2, 29), '윤일 정각');
  });

  test('T02 동등식 전수 — ceil(r+3d)<=T ⇔ r<=T−3d · ceil(r+3d)<=T+1d ⇔ r<=T−2d (자정±1ms·정오·말일/연말/윤일)', () => {
    const Ts0 = [kstMid(2026, 11, 26), kstMid(2026, 12, 1), kstMid(2027, 1, 1), kstMid(2028, 2, 29), kstMid(2028, 3, 1)];
    let n = 0;
    for (const T of Ts0) {
      for (let dd = -6; dd <= 1; dd++) {
        for (const off of [0, 1, -1, 12 * H, DAY - 1, 9 * H, 15 * H]) {
          const r = T + dd * DAY + off;
          const a = AG.resignAutoApproveAtSeconds(like(r)) * 1000;
          assert.strictEqual(a <= T, r <= T - 3 * DAY, `scheduler r=${r} T=${T}`);
          assert.strictEqual(a <= T + DAY, r <= T - 2 * DAY, `home r=${r} T=${T}`);
          n++;
        }
      }
    }
    assert.ok(n >= 280, String(n));
  });

  test('T03 분류 — VALID/MISMATCH(누락·형·값)/SOURCE_INVALID(누락·형·주기·overflow) · false+null · true+Timestamp', () => {
    const r = new Ts(kstMid(2026, 11, 26) + 12 * H);
    const eff = new Ts(kstMid(2026, 12, 10));
    const effRetro = new Ts(kstMid(2026, 11, 20));
    const auto = new Ts(kstMid(2026, 11, 30));
    const C = (d) => AG.resignClassifyPending(d, isTs);
    const base = {resignStatus: 'PENDING', resignRequestedAt: r, resignRequestDate: eff, resignDecisionCycle: 1};
    assert.deepStrictEqual(C(Object.assign({}, base, {resignRetroRequest: false, resignAutoApproveAt: auto})),
      {state: 'VALID', retro: false, autoAtSeconds: auto.seconds});
    assert.deepStrictEqual(C(Object.assign({}, base, {resignRequestDate: effRetro, resignRetroRequest: true, resignAutoApproveAt: null})),
      {state: 'VALID', retro: true, autoAtSeconds: null});
    const mm = (d) => { const c = C(Object.assign({}, base, d)); assert.strictEqual(c.state, 'MISMATCH', JSON.stringify(d)); return c.reasons; };
    assert.deepStrictEqual(mm({}), ['RETRO_MISSING', 'AUTO_AT_MISSING']);
    assert.deepStrictEqual(mm({resignRetroRequest: 'false', resignAutoApproveAt: auto}), ['RETRO_TYPE']);
    assert.deepStrictEqual(mm({resignRetroRequest: true, resignAutoApproveAt: auto}), ['RETRO_VALUE']);
    assert.deepStrictEqual(mm({resignRetroRequest: false, resignAutoApproveAt: null}), ['AUTO_AT_VALUE'], 'false + null');
    assert.deepStrictEqual(mm({resignRetroRequest: false, resignAutoApproveAt: 123}), ['AUTO_AT_TYPE']);
    assert.deepStrictEqual(mm({resignRetroRequest: false, resignAutoApproveAt: new Ts(auto.toMillis() - DAY)}), ['AUTO_AT_VALUE']);
    assert.deepStrictEqual(mm({resignRetroRequest: false, resignAutoApproveAt: new Ts(auto.toMillis() + 1)}), ['AUTO_AT_VALUE'], '자정 아님');
    assert.deepStrictEqual(mm({resignRequestDate: effRetro, resignRetroRequest: true, resignAutoApproveAt: auto}), ['AUTO_AT_VALUE'], 'true + Timestamp');
    const si = (d) => { const c = C(Object.assign({}, base, d)); assert.strictEqual(c.state, 'SOURCE_INVALID', JSON.stringify(d)); return c.reasons; };
    assert.deepStrictEqual(si({resignRequestedAt: undefined}), ['SOURCE_REQUESTED_AT_MISSING']);
    assert.deepStrictEqual(si({resignRequestedAt: '2026-11-26'}), ['SOURCE_REQUESTED_AT_TYPE']);
    assert.deepStrictEqual(si({resignRequestDate: null}), ['SOURCE_REQUEST_DATE_MISSING']);
    assert.deepStrictEqual(si({resignRequestDate: 1764000000000}), ['SOURCE_REQUEST_DATE_TYPE']);
    assert.deepStrictEqual(si({resignDecisionCycle: '1'}), ['SOURCE_CYCLE_TYPE']);
    assert.deepStrictEqual(si({resignDecisionCycle: 1.5}), ['SOURCE_CYCLE_TYPE']);
    assert.deepStrictEqual(AG.resignClassifyPending({resignRequestedAt: {seconds: 253402300799, nanoseconds: 0}, resignRequestDate: eff},
      (v) => v === eff || (v && v.seconds === 253402300799)).reasons, ['SOURCE_REQUESTED_AT_TYPE'], 'overflow');
    assert.strictEqual(C(Object.assign({}, base, {resignDecisionCycle: undefined, resignRetroRequest: false, resignAutoApproveAt: auto})).state,
      'VALID', '주기 부재 = 기록 도입 전(0) — 역사 주기 발명 0');
  });

  // ── 2. writer 전이 ─────────────────────────────────────────────────────────
  test('W01 요청 — 같은 거래에 r 하나로 요청시각·두 파생 필드 · 보조 표식 초기화 · 결정로그에 같은 값', async () => {
    reset(); seedBiz();
    NOW = kstMid(2026, 11, 26) + 12 * H;
    seedApp('a1', {resignAutoApproveSkipped: {reason: 'RETROACTIVE_REQUEST'}, resignManualReviewNotifiedDate: '2026-11-20'});
    await call(X.callableRequestResignation, {applicationId: 'a1', resignDateIso: new RealDate(kstMid(2026, 12, 10)).toISOString()}, 'w1');
    const a = F.get('applications/a1');
    assert.strictEqual(a.resignStatus, 'PENDING');
    assert.ok(a.resignRequestedAt instanceof Ts && a.resignRequestedAt.toMillis() === NOW, '요청시각 = 이 attempt 의 r');
    assert.strictEqual(a.resignRetroRequest, false);
    assert.strictEqual(a.resignAutoApproveAt.toMillis(), kstMid(2026, 11, 30));
    assert.strictEqual(a.resignAutoApproveSkipped, null);
    assert.strictEqual(a.resignManualReviewNotifiedDate, null);
    assert.strictEqual(a.resignDecisionCycle, 1);
    const log = F.get('exit_decision_log/a1__RESIGN__1__REQUEST');
    assert.ok(log && log.changes.resignAutoApproveAt.toMillis() === kstMid(2026, 11, 30) && log.changes.resignRequestedAt.toMillis() === NOW);
    const tx = TXLOG.find((t) => t.writes > 0);
    // [L56 r5] 같은 거래에 관리자 알림 작업(수신자별)이 더 실린다 — 지원서 + 결정로그 + 작업 수.
    const jobs = [...F.STORE.keys()].filter((k) => /^notification_jobs\//.test(k)).length;
    assert.ok(tx && tx.writes === 2 + jobs, '지원서 + 결정로그(+ 알림 작업)가 한 거래');
    assert.strictEqual(AG.resignClassifyPending(a, isTs).state, 'VALID');
  });

  test('W02 소급·같은 KST 일·미래 효력일 — retro 판정과 autoAt(null/자정)', async () => {
    const cases = [
      ['소급(전일 효력)', kstMid(2026, 11, 20), true, null],
      ['같은 KST 일 00:00 효력', kstMid(2026, 11, 26), false, kstMid(2026, 11, 30)],
      ['전날 23:59:59.999 효력', kstMid(2026, 11, 26) - 1, true, null],
      ['미래 효력', kstMid(2027, 1, 15), false, kstMid(2026, 11, 30)],
    ];
    for (const [label, eff, retro, auto] of cases) {
      reset(); seedBiz();
      NOW = kstMid(2026, 11, 26) + 12 * H;
      seedApp('a2', {});
      await call(X.callableRequestResignation, {applicationId: 'a2', resignDateIso: new RealDate(eff).toISOString()}, 'w1');
      const a = F.get('applications/a2');
      assert.strictEqual(a.resignRetroRequest, retro, label);
      assert.strictEqual(a.resignAutoApproveAt === null ? null : a.resignAutoApproveAt.toMillis(), auto, label);
    }
  });

  test('W03 KST 자정 경계 — 정각 요청은 +3일 시작 · +1ms 와 자정 직전은 +4일 시작', async () => {
    for (const [r, auto] of [[kstMid(2026, 11, 26), kstMid(2026, 11, 29)], [kstMid(2026, 11, 26) + 1, kstMid(2026, 11, 30)],
      [kstMid(2026, 11, 27) - 1, kstMid(2026, 11, 30)]]) {
      reset(); seedBiz(); NOW = r;
      seedApp('a3', {});
      await call(X.callableRequestResignation, {applicationId: 'a3', resignDateIso: new RealDate(kstMid(2026, 12, 31)).toISOString()}, 'w1');
      const a = F.get('applications/a3');
      assert.strictEqual(a.resignRequestedAt.toMillis(), r);
      assert.strictEqual(a.resignAutoApproveAt.toMillis(), auto, new RealDate(r).toISOString());
    }
  });

  test('W04 효력일 fallback — workEndDate Timestamp 는 그대로 · 문자열 workEndDate 는 r(접수시각) · 없으면 r', async () => {
    for (const [wed, expEff] of [[new Ts(kstMid(2026, 12, 31)), kstMid(2026, 12, 31)], ['2026-12-31', null], [undefined, null]]) {
      reset(); seedBiz(); NOW = kstMid(2026, 11, 26) + 12 * H;
      seedApp('a4', wed === undefined ? {} : {workEndDate: wed});
      await call(X.callableRequestResignation, {applicationId: 'a4'}, 'w1');
      const a = F.get('applications/a4');
      assert.ok(a.resignRequestDate instanceof Ts);
      assert.strictEqual(a.resignRequestDate.toMillis(), expEff == null ? NOW : expEff, String(wed));
      assert.strictEqual(a.resignRetroRequest, false);
      assert.strictEqual(AG.resignClassifyPending(a, isTs).state, 'VALID');
    }
  });

  test('W05 반려 → 재요청 — 이전 파생값·보조 표식 재사용 0 · 주기 +1', async () => {
    reset(); seedBiz(); NOW = kstMid(2026, 11, 26) + 12 * H;
    seedApp('a5', {resignStatus: 'REJECTED', resignDecisionCycle: 2, resignRequestedAt: new Ts(kstMid(2026, 11, 1)),
      resignRequestDate: new Ts(kstMid(2026, 10, 25)), resignRetroRequest: true, resignAutoApproveAt: null,
      resignAutoApproveSkipped: {reason: 'RETROACTIVE_REQUEST'}, resignManualReviewNotifiedDate: '2026-11-26'});
    await call(X.callableRequestResignation, {applicationId: 'a5', resignDateIso: new RealDate(kstMid(2026, 12, 5)).toISOString()}, 'w1');
    const a = F.get('applications/a5');
    assert.strictEqual(a.resignDecisionCycle, 3);
    assert.strictEqual(a.resignRetroRequest, false);
    assert.strictEqual(a.resignAutoApproveAt.toMillis(), kstMid(2026, 11, 30));
    assert.strictEqual(a.resignAutoApproveSkipped, null);
    assert.strictEqual(a.resignManualReviewNotifiedDate, null, '같은 날 새 소급 요청이 날짜 표식으로 묻히지 않게');
  });

  test('W06 거래 재시도가 자정을 넘으면 — 마지막 성공 attempt 의 r 로 요청시각·retro·autoAt 을 모두 다시 계산', async () => {
    reset(); seedBiz();
    const first = kstMid(2026, 11, 27) - 1;
    const second = kstMid(2026, 11, 27) + 1;
    NOW = first;
    seedApp('a6', {});
    plan.retryOnce = second;
    // 효력일 = 11-26(첫 attempt 기준 같은 날 → 비소급 · 둘째 attempt 기준 전날 → 소급)
    await call(X.callableRequestResignation, {applicationId: 'a6', resignDateIso: new RealDate(kstMid(2026, 11, 26) + 6 * H).toISOString()}, 'w1');
    const a = F.get('applications/a6');
    assert.strictEqual(a.resignRequestedAt.toMillis(), second, '요청시각 = 둘째 attempt');
    assert.strictEqual(a.resignRetroRequest, true, '둘째 attempt 의 r 기준 소급');
    assert.strictEqual(a.resignAutoApproveAt, null);
    assert.ok(TXLOG.some((t) => t.attempts === 2), '재시도 모사가 실제로 2 attempt');
  });

  test('W07 취소 — 두 파생 필드 명시 초기화(false/null) · 반려/승인은 해당 요청의 역사값 보존', async () => {
    reset(); seedBiz(); NOW = kstMid(2026, 11, 26) + 12 * H;
    const pend = pendingDoc(kstMid(2026, 11, 25) + H, kstMid(2026, 12, 10), 1, {resignAutoApproveSkipped: {reason: 'x'}});
    seedApp('c1', pend);
    await call(X.callableCancelResignRequest, {applicationId: 'c1'}, 'w1');
    const c = F.get('applications/c1');
    assert.strictEqual(c.resignStatus, null);
    assert.strictEqual(c.resignRetroRequest, false);
    assert.strictEqual(c.resignAutoApproveAt, null);
    assert.strictEqual(c.resignAutoApproveSkipped, null);
    assert.ok(F.get('exit_decision_log/c1__RESIGN__1__CANCEL').changes.resignAutoApproveAt === null);

    seedApp('j1', pend);
    await call(X.callableRejectResignation, {applicationId: 'j1', reason: '사유'}, 'own1');
    const j = F.get('applications/j1');
    assert.strictEqual(j.resignStatus, 'REJECTED');
    assert.ok(j.resignAutoApproveAt.isEqual(pend.resignAutoApproveAt) && j.resignRetroRequest === false, '반려: 역사값 보존');

    seedApp('p1', pend);
    await call(X.callableApproveResignation, {applicationId: 'p1'}, 'own1');
    const p = F.get('applications/p1');
    assert.strictEqual(p.resignStatus, 'APPROVED');
    assert.ok(p.resignAutoApproveAt.isEqual(pend.resignAutoApproveAt), '승인: 역사값 보존');
    assert.strictEqual(p.actualResignDate.toMillis(), kstMid(2026, 12, 10), '효력일·종료 D+1 경로 보존(승인=결정만)');
  });

  test('W08 원문 배선 — 재지원·연장 새 문서 reset · 요청 writer 의 serverTimestamp 요청시각 제거', () => {
    const reapply = SRC.slice(SRC.indexOf('resignStatus: null, resignRequestedAt: null, resignRequestDate: null,'));
    assert.ok(reapply.startsWith('resignStatus: null, resignRequestedAt: null, resignRequestDate: null,\n          ...SRV_RESIGN_DERIVED_RESET,'));
    const iR = SRC.indexOf('export const callableAcceptRenewalProposal = ');
    const ren = SRC.slice(iR, SRC.indexOf('\nexport const ', iR + 10));
    assert.ok(ren.includes('        resignRequestDate: null,\n        // [BL284-01] 원관계의 파생 필드·보조 표식이 ...freshData 로 복사되지 않게\n        ...SRV_RESIGN_DERIVED_RESET,'));
    const iQ = SRC.indexOf('export const callableRequestResignation = ');
    const rq = SRC.slice(iQ, SRC.indexOf('\nexport const ', iQ + 10));
    assert.ok(!rq.includes('resignRequestedAt: admin.firestore.FieldValue.serverTimestamp()'));
    assert.ok(rq.includes('const requestedAt = Timestamp.now();') && rq.includes('...srvResignDerivedFields(effectiveDate, requestedAt),'));
    // resignStatus 를 PENDING 으로 만드는 writer 는 요청 하나뿐
    assert.strictEqual((SRC.match(/resignStatus: "PENDING"/g) || []).length, 1);
  });

  // ── 3. scheduler D+3 · C288-01 ──────────────────────────────────────────────
  test('S01 D+3 — due(정각 포함) 자동 승인 · 미도래/소급/필드누락/비확정/파생값 불일치는 승인 0', async () => {
    reset(); seedBiz();
    const T = kstMid(2026, 11, 26);
    seedApp('s1', pendingDoc(kstMid(2026, 11, 22) + 12 * H, kstMid(2026, 12, 10), 1));      // autoAt = 11-26 → due
    seedApp('s2', pendingDoc(kstMid(2026, 11, 23), kstMid(2026, 12, 10), 1));               // 정각 → autoAt 11-26 → due
    seedApp('s3', pendingDoc(kstMid(2026, 11, 23) + 1, kstMid(2026, 12, 10), 1));           // autoAt 11-27 → 아직
    seedApp('s4', pendingDoc(kstMid(2026, 11, 20) + H, kstMid(2026, 11, 18), 1));           // 소급
    seedApp('s5', {resignStatus: 'PENDING', resignRequestedAt: new Ts(kstMid(2026, 11, 20)), resignRequestDate: new Ts(kstMid(2026, 12, 10))}); // 필드 누락(전환 전 backfill 대상)
    seedApp('s6', pendingDoc(kstMid(2026, 11, 20) + H, kstMid(2026, 12, 10), 1, {status: 'CANCELED'}));
    seedApp('s7', pendingDoc(kstMid(2026, 11, 23) + H, kstMid(2026, 12, 10), 1, {resignAutoApproveAt: new Ts(T)})); // 위조/오류 autoAt(정답 11-27)
    await runScheduler(T + 5 * 60 * 1000);
    const st = (id) => F.get('applications/' + id).resignStatus;
    assert.strictEqual(st('s1'), 'AUTO_APPROVED');
    assert.strictEqual(st('s2'), 'AUTO_APPROVED', '정각 요청은 그날 시작부터 대상');
    for (const id of ['s3', 's4', 's5', 's6', 's7']) assert.strictEqual(st(id), 'PENDING', id);
    assert.strictEqual(F.get('applications/s1').actualResignDate.toMillis(), kstMid(2026, 12, 10));
    assert.ok(F.get('exit_decision_log/s1__RESIGN__1__AUTO_APPROVE'));
    assert.ok(!F.get('exit_decision_log/s7__RESIGN__1__AUTO_APPROVE'));
    const ids = notifDocs();
    assert.ok(ids.some((k) => k.startsWith('users/w1/notifications/') && k.includes('resign_auto_approved_worker')), ids.join(','));
    assert.ok(ids.some((k) => k.startsWith('users/own1/notifications/') && k.includes('resign_manual_review')), '소급: 수동 심사 알림');
    assert.ok(F.get('applications/s4').resignAutoApproveSkipped, '소급 skip 표식');
    assert.ok(!ids.some((k) => k.includes('s3') || k.includes('s5') || k.includes('s6') || k.includes('s7')), '미대상 알림 0');
    assert.ok(LOGS.some((l) => l.includes('[D+3 퇴사 자동승인] 2건 처리')), LOGS.filter((l) => l.includes('D+3')).join(' | '));
  });

  test('S02 C288-01 반례 — 후보 A 를 읽은 뒤 취소→새 요청 B: B 승인 0 · 알림 0 · 결정로그 0', async () => {
    for (const bRetro of [false, true]) {
      reset(); seedBiz();
      const T = kstMid(2026, 11, 26);
      seedApp('c1', pendingDoc(T - 4 * DAY, kstMid(2026, 11, 28), 1));
      const bReq = T + 60 * 1000;
      const bDoc = pendingDoc(bReq, bRetro ? kstMid(2026, 11, 20) : kstMid(2026, 12, 20), 2);
      let swapped = false;
      F.hooks.afterGet = (p) => {
        if (!swapped && p === 'businesses/b1') { swapped = true; seedApp('c1', bDoc); }
      };
      const before = notifDocs().length;
      await runScheduler(T + 5 * 60 * 1000);
      F.hooks.afterGet = null;
      assert.ok(swapped);
      const a = F.get('applications/c1');
      assert.strictEqual(a.resignStatus, 'PENDING', 'B 는 승인되지 않는다');
      assert.strictEqual(a.resignRequestedAt.toMillis(), bReq);
      assert.strictEqual(a.actualResignDate, undefined);
      assert.strictEqual(exitLogs().length, 0);
      assert.strictEqual(notifDocs().filter((k) => k.includes('resign_auto_approved')).length, 0);
      assert.strictEqual(notifDocs().length, before);
    }
  });

  test('S03 같은 요청이 그대로면 승인 · 재실행은 무부작용(알림·로그 중복 0)', async () => {
    reset(); seedBiz();
    const T = kstMid(2026, 11, 26);
    seedApp('d1', pendingDoc(T - 4 * DAY, kstMid(2026, 11, 28), 1));
    await runScheduler(T + 60 * 1000);
    const n1 = notifDocs().length; const l1 = exitLogs().length;
    assert.strictEqual(F.get('applications/d1').resignStatus, 'AUTO_APPROVED');
    await runScheduler(T + 2 * 60 * 1000);
    assert.strictEqual(notifDocs().length, n1);
    assert.strictEqual(exitLogs().length, l1);
    assert.ok(n1 >= 2 && l1 === 1);
  });

  test('S04 scheduler 후보 쿼리 shape — 새 필드 · orderBy · 페이지(색인과 같은 필드)', () => {
    const i = SRC.indexOf('async function srvProcessResignAutoApproveD3(');
    const body = SRC.slice(i, SRC.indexOf('\n}\n', i));
    assert.ok(body.includes('.where("resignRetroRequest", "==", false)\n    .where("resignAutoApproveAt", "<=", cutoff)\n    .orderBy("resignAutoApproveAt")'));
    assert.ok(body.includes('.where("resignRetroRequest", "==", true)\n    .where("resignRequestedAt", "<=", retroBoundary)\n    .orderBy("resignRequestedAt")'));
    assert.ok(body.includes('if (!resignSameRequest(cand, fresh, isTs)) return false;'));
    const IDX = JSON.parse(fs.readFileSync(path.join(__dirname, '..', '..', 'firestore.indexes.json'), 'utf8')).indexes;
    const has = (...f) => IDX.some((x) => x.collectionGroup === 'applications' && x.queryScope === 'COLLECTION' &&
      JSON.stringify(x.fields.map((y) => y.fieldPath)) === JSON.stringify(f) && x.fields.every((y) => y.order === 'ASCENDING'));
    assert.ok(has('resignStatus', 'resignRetroRequest', 'resignAutoApproveAt'));
    assert.ok(has('resignStatus', 'resignRetroRequest', 'resignRequestedAt'));
    assert.ok(has('businessId', 'resignStatus', 'resignRetroRequest'));
    assert.ok(has('businessId', 'resignStatus', 'resignRetroRequest', 'resignAutoApproveAt'));
    assert.ok(has('resignStatus', 'resignRequestedAt'), 'D+1/D+2 기존 색인 보존');
  });

  // ── 4. 홈 3 aggregate ─────────────────────────────────────────────────────
  test('H01 홈 — 정확 3 aggregate(같은 read-only 거래) · 문서 읽기 0 · 다음 자정 경계 · overdue 포함 · 필드 누락은 총수에만', async () => {
    reset();
    const T = kstMid(2026, 11, 26);
    NOW = T + 10 * H;
    F.put('applications/h1', pendingDoc(T - 2 * DAY - 12 * H, kstMid(2026, 12, 10), 1, {businessId: 'bH'})); // autoAt = T+1d(다음 자정) → soon
    F.put('applications/h2', pendingDoc(T - 3 * DAY, kstMid(2026, 12, 10), 1, {businessId: 'bH'}));          // autoAt = T(overdue) → soon
    F.put('applications/h3', pendingDoc(T - 2 * DAY + 1, kstMid(2026, 12, 10), 1, {businessId: 'bH'}));     // autoAt = T+2d(경계 +1ms) → 아님
    F.put('applications/h4', pendingDoc(T - 5 * DAY, kstMid(2026, 11, 1), 1, {businessId: 'bH'}));            // 소급 → manual
    F.put('applications/h5', {businessId: 'bH', resignStatus: 'PENDING', resignRequestedAt: new Ts(T - 5 * DAY), resignRequestDate: new Ts(T)}); // 누락
    F.put('applications/h6', pendingDoc(T - 5 * DAY, kstMid(2026, 11, 1), 1, {businessId: 'bH', resignStatus: 'REJECTED'}));
    F.put('applications/h7', pendingDoc(T - 5 * DAY, kstMid(2026, 12, 1), 1, {businessId: 'bOther'}));
    const before = F.W.reads.length;
    const r = await X.srvHomeResignRequest('bH', new RealDate(T));
    assert.deepStrictEqual(r, {count: 5, soonCount: 2, manualReviewCount: 1});
    const reads = F.W.reads.slice(before);
    assert.strictEqual(reads.length, 3, '읽기는 집계 3개뿐');
    assert.ok(reads.every((x) => x.kind === 'query' && x.limit === undefined));
    assert.strictEqual(TXLOG.length, 1);
    assert.deepStrictEqual(TXLOG[0].opts, {readOnly: true});
    assert.strictEqual(TXLOG[0].aggReads, 3, '세 집계가 같은 거래');
    const flt = reads.map((x) => x.filters.map((f) => f[0] + f[1]).join('&'));
    assert.deepStrictEqual(flt, ['businessId==&resignStatus==', 'businessId==&resignStatus==&resignRetroRequest==',
      'businessId==&resignStatus==&resignRetroRequest==&resignAutoApproveAt<=']);
    assert.ok(reads[2].filters[3][2] && reads[2].filters[3][2].__ts === T + DAY, '다음 KST 자정');
  });

  test('H02 홈 — 0건 정상 객체 · 집계 실패/검산 실패는 throw(호출자 available=false)', async () => {
    reset();
    const T = kstMid(2026, 11, 26);
    assert.deepStrictEqual(await X.srvHomeResignRequest('bEmpty', new RealDate(T)), {count: 0, soonCount: 0, manualReviewCount: 0});
    for (const k of [1, 2, 3]) {
      reset(); plan.aggFail = (n) => n === k;
      await assert.rejects(X.srvHomeResignRequest('bEmpty', new RealDate(T)), /synthetic aggregate failure/);
    }
    reset(); plan.aggOverride = (n, c) => (n === 1 ? 1 : 1); // count1 · manual1 · soon1 → manual+soon > count
    await assert.rejects(X.srvHomeResignRequest('bEmpty', new RealDate(T)), /검산 실패/);
    reset(); plan.aggOverride = (n, c) => (n === 2 ? -1 : c);
    await assert.rejects(X.srvHomeResignRequest('bEmpty', new RealDate(T)), /검산 실패/);
    // 호출자: rejected → resignRequest undefined → 권한 있는 사업장 실패면 available=false (기존 배선 그대로)
    assert.ok(SRC.includes('resignRequest:     resignR.status   === "fulfilled" ? resignR.value   : undefined,'));
  });

  test('H03 홈·scheduler 같은 식 — 같은 문서 집합에서 soon == 다음 자정 scheduler 대상 · 오늘 대상 ⊆ soon', async () => {
    reset(); seedBiz();
    const T = kstMid(2026, 11, 26);
    const rs = [T - 4 * DAY, T - 3 * DAY, T - 3 * DAY + 1, T - 2 * DAY, T - 2 * DAY + 1, T - 2 * DAY + 12 * H, T - DAY];
    rs.forEach((r, i) => seedApp('q' + i, pendingDoc(r, kstMid(2026, 12, 20), 1)));
    const home = await X.srvHomeResignRequest('b1', new RealDate(T));
    const expectSoon = rs.filter((r) => r <= T - 2 * DAY).length;
    assert.strictEqual(home.soonCount, expectSoon);
    await runScheduler(T + DAY + 60 * 1000); // 다음 자정 실행
    const approved = rs.filter((_, i) => F.get('applications/q' + i).resignStatus === 'AUTO_APPROVED').length;
    assert.strictEqual(approved, expectSoon, '홈 임박 수 = 다음 자정 scheduler 승인 수');
  });
}
