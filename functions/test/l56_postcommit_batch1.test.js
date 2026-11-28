'use strict';
/**
 * [L56 r4 · 묶음1] 커밋 뒤 알림 → 같은 거래 direct 작업 — 동치 · 누락 0.
 *
 *   같은 시나리오를 이전 원문 사본(커밋 뒤 직접 쓰기)과 새 원문에서 돌려, 최종 알림 문서(수신자·문서 id 모양·본문 필드)를 비교한다.
 *     · 이전 원문: 호출이 끝나면 알림이 이미 있다(직접 쓰기).
 *     · 새 원문: 호출 직후 알림 0 · 작업이 도메인 쓰기와 **같은 커밋**에 있다 → 작업 실행기를 돌리면 같은 알림이 생긴다.
 *   L56B1_OUT 로 이전 원문 결과를 남기고 L56B1_COMPARE 로 새 원문과 비교한다(createdAt/readAt · 임의 id 는 비교에서 뺀다).
 *   음성: 알림 쓰기가 실패하면 이전 원문은 알림 0(유실) · 새 원문은 작업이 남아 다음 실행에서 만든다.
 */
const {test} = require('node:test');
const assert = require('assert');
const fs = require('fs');
const {createFakeFirestore} = require('./consent_r4d_fakestore');
const {loadIndexClosure} = require('./auth_kakao_index_harness');

const RealDate = Date;
const NOW = RealDate.UTC(2026, 10, 26, 3, 0);
class FakeDate extends RealDate {
  constructor(...a) { if (a.length === 0) super(NOW); else super(...a); }
  static now() { return NOW; }
}
class HttpsError extends Error {
  constructor(code, message, details) { super(message); this.code = code; this.details = details; }
}
const QCON = {};
for (const k of ['log', 'info', 'warn', 'error', 'debug']) QCON[k] = () => {};
const F = createFakeFirestore({now: () => NOW});
const SRC = fs.readFileSync(require.resolve('../src/index.ts'), 'utf8');
const NEW = SRC.includes('[L56 r4]');
const FNS = ['callableRejectApplication', 'callableApproveResignation', 'callableRequestTermination',
  'callableRejectInterimSettlement', 'callableProcessInterimSettlement', 'callableAdminDirectInterimSettlement',
  'callableRequestInterimSettlement'];
const {exports: X} = loadIndexClosure(FNS.concat(['srvRunNotificationJob']), F,
  {HttpsError, console: QCON, Date: FakeDate});
const call = (fn, data, uid) => fn({data, auth: {uid, token: {}}});
const Ts = F.Ts;
const DAY = 86400000;

function base() {
  F.reset();
  F.put('users/own1', {role: 'BUSINESS_ADMIN', accountStatus: 'active', name: '사장'});
  F.put('users/sub1', {role: 'USER', accountStatus: 'active', name: '부', subAdminBusinessIds: ['b1']});
  F.put('businesses/b1/members/sub1', {uid: 'sub1', permissions: {canManageWage: true}});
  F.put('users/w1', {role: 'USER', accountStatus: 'active', name: '근로자', bankAccountVersion: 1, bankbookDocumentVersion: 1});
  F.put('businesses/b1', {name: '평택', ownerId: 'own1', adminIds: ['own1']});
}
const ACCT = {wageAccountSnapshotVersion: 1, wageAccountBankName: '국민', wageAccountNumberEncrypted: 'enc',
  wageAccountHolder: '근로자', wageAccountSnapshotAt: new Ts(NOW - 5 * DAY),
  wageAccountSourceBankAccountVersion: 1, wageAccountSourceBankbookDocumentVersion: 1};
function att(id, o = {}) {
  F.put(`attendance/${id}`, Object.assign({userId: 'w1', businessId: 'b1', applicationId: 'a1', wageStatus: 'confirmed',
    finalWage: 96000, wageDetail: {netWage: 93000}, workDate: new Ts(NOW - 7 * DAY), status: 'completed'}, ACCT, o));
}

const SCEN = [
  ['RA 지원 거절', () => {
    base();
    F.put('tos/t1', {businessId: 'b1', totalPending: 1});
    F.put('applications/a1', {uid: 'w1', businessId: 'b1', businessName: '평택', selectedWorkType: '포장', toId: 't1',
      status: 'PENDING', workDate: new Ts(NOW + 3 * DAY)});
  }, () => call(X.callableRejectApplication, {applicationId: 'a1', message: '정원 초과'}, 'own1'), 'applications/a1'],
  ['AR 퇴사 승인', () => {
    base();
    F.put('applications/a1', {uid: 'w1', businessId: 'b1', businessName: '평택', status: 'CONFIRMED', type: 'long_term',
      resignStatus: 'PENDING', resignRequestDate: new Ts(NOW + 10 * DAY), resignRequestedAt: new Ts(NOW - DAY)});
  }, () => call(X.callableApproveResignation, {applicationId: 'a1'}, 'own1'), 'applications/a1'],
  ['TR 해지 요청', () => {
    base();
    F.put('applications/a1', {uid: 'w1', businessId: 'b1', businessName: '평택', status: 'CONFIRMED', type: 'long_term',
      workEndDate: new Ts(NOW + 20 * DAY)});
  }, () => call(X.callableRequestTermination, {applicationId: 'a1', reason: '사유'}, 'own1'), 'applications/a1'],
  ['IR 중간정산 반려', () => {
    base();
    F.put('interim_settlement_requests/r1', {businessId: 'b1', businessName: '평택', workerId: 'w1', status: 'PENDING',
      periodStart: new Ts(NOW - 9 * DAY), periodEnd: new Ts(NOW - 2 * DAY)});
  }, () => call(X.callableRejectInterimSettlement, {businessId: 'b1', requestId: 'r1', rejectReason: '확인 필요'}, 'own1'),
  'interim_settlement_requests/r1'],
  ['IP 중간정산 이체 처리', () => {
    base();
    att('at1', {activeInterimSettlementId: 'r1'});
    F.put('interim_settlement_requests/r1', {businessId: 'b1', businessName: '평택', workerId: 'w1', status: 'APPROVED',
      attendanceIds: ['at1'], requestedAmount: 96000, netAmount: 93000,
      periodStart: new Ts(NOW - 9 * DAY), periodEnd: new Ts(NOW - 2 * DAY)});
  }, () => call(X.callableProcessInterimSettlement, {businessId: 'b1', settlementRequestId: 'r1', transferNote: '이체'}, 'own1'),
  'interim_settlement_requests/r1'],
  ['ID 관리자 직접 중간정산', () => {
    base();
    att('at1'); att('at2', {finalWage: 48000});
  }, () => call(X.callableAdminDirectInterimSettlement, {businessId: 'b1', workerId: 'w1', workerName: '근로자', businessName: '평택',
    applicationId: 'a1', attendanceIds: ['at1', 'at2'], netAmount: 144000}, 'own1'), 'attendance/at1'],
  ['IQ 중간정산 요청(관리자·부관리자 fan-out)', () => {
    base();
    F.put('applications/a1', {uid: 'w1', businessId: 'b1', status: 'CONFIRMED'});
    att('at1');
  }, () => call(X.callableRequestInterimSettlement, {businessId: 'b1', applicationId: 'a1', businessName: '평택', workerName: '근로자',
    periodStart: '2026-11-17', periodEnd: '2026-11-24', attendanceIds: ['at1'], requestedAmount: 96000, netAmount: 93000}, 'w1'),
  null],
];

const notifDocs = () => [...F.STORE.keys()].filter((k) => /^users\/[^/]+\/notifications\/[^/]+$/.test(k)).sort();
const strip = (d) => { const o = JSON.parse(JSON.stringify(d)); delete o.createdAt; delete o.readAt; return o; };
/** 알림 문서 id 모양: 결정적이면 그대로, 임의 id 면 'random' 으로(새 원문의 `${kind}_${source}_${jobId}` 도 'perJob'). */
function shape(path) {
  const [, uid, , id] = path.split('/');
  // 사건마다 새로 만든 id(예전 임의 id · 새 `${kind}_${source}_${jobId}`·`…_${uid}`)는 임의 토큰을 품는다 → 'perEvent'.
  if (/(^|_)(auto\d+|[A-Za-z0-9]{20})(_|$)/.test(id)) return `${uid}/perEvent`;
  return `${uid}/${id}`;
}
async function runJobs() {
  const jobs = [...F.STORE.keys()].filter((k) => /^notification_jobs\/[^/]+$/.test(k));
  for (const k of jobs) await X.srvRunNotificationJob(k.split('/')[1]);
  return jobs.length;
}

const OUT = {};
for (const [id, seed, run, domainPath] of SCEN) {
  test(`B1 ${id}`, async () => {
    seed();
    const r = await run();
    // 예전 원문의 fire-and-forget 알림(.catch)이 끝나도록 이벤트 루프를 몇 번 돌린다(새 원문엔 영향 없음).
    for (let i = 0; i < 30; i++) await new Promise((res) => setImmediate(res));
    assert.ok(r && r.success !== false, `${id} 호출 실패: ${JSON.stringify(r)}`);
    if (NEW) {
      assert.deepStrictEqual(notifDocs(), [], `${id} 응답 전에 알림을 직접 썼다`);
      const jobKeys = [...F.STORE.keys()].filter((k) => k.startsWith('notification_jobs/'));
      assert.ok(jobKeys.length >= 1, `${id} 작업이 없다`);
      if (domainPath) {
        const c = F.W.commits.find((x) => x.writes.some((w) => w.path === domainPath));
        for (const k of jobKeys) assert.ok(c.writes.some((w) => w.path === k), `${id} 작업이 도메인 쓰기와 다른 커밋`);
      } else {
        for (const k of jobKeys) {
          const c = F.W.commits.find((x) => x.writes.some((w) => w.path === k));
          assert.ok(c.writes.some((w) => w.path.startsWith('interim_settlement_requests/')), `${id} 작업이 요청 생성과 다른 커밋`);
        }
      }
      await runJobs();
      // 다시 돌려도 알림은 늘지 않는다(작업 done · 결정적 id).
      const n1 = notifDocs().length; await runJobs(); assert.strictEqual(notifDocs().length, n1);
    }
    OUT[id] = notifDocs().map((p) => ({at: shape(p), doc: strip(F.get(p))})).sort((a, b) => a.at.localeCompare(b.at));
  });
}

if (NEW) {
  test('B1-NEG 알림 쓰기가 한 번 실패해도 작업이 남아 다음 실행에서 만든다(예전: 유실)', async () => {
    SCEN[0][1]();
    await SCEN[0][2]();
    let fail = 1;
    F.hooks.beforeCommit = (txId, buf) => {
      if (buf.some((w) => /^users\/w1\/notifications\//.test(w.path)) && fail-- > 0) throw new Error('UNAVAILABLE');
    };
    const k = [...F.STORE.keys()].find((x) => x.startsWith('notification_jobs/')).split('/')[1];
    assert.strictEqual(await X.srvRunNotificationJob(k), 'retry');
    F.hooks.beforeCommit = null;
    assert.strictEqual(notifDocs().length, 0);
    assert.strictEqual(await X.srvRunNotificationJob(k), 'done');
    assert.strictEqual(notifDocs().length, 1);
  });
}

test('OUT 기록', () => {
  if (process.env.L56B1_OUT) fs.writeFileSync(process.env.L56B1_OUT, JSON.stringify(OUT, null, 2));
  assert.strictEqual(Object.keys(OUT).length, SCEN.length);
  for (const [id] of SCEN) assert.ok(OUT[id].length >= 1, `${id} 알림이 0건`);
});
if (process.env.L56B1_COMPARE) {
  test('EQ 이전 원문(커밋 뒤 직접 쓰기)과 수신자·id 모양·본문이 같다 — 누락 0', () => {
    const old = JSON.parse(fs.readFileSync(process.env.L56B1_COMPARE, 'utf8'));
    for (const k of Object.keys(old)) assert.deepStrictEqual(OUT[k], old[k], k);
  });
}

// ── 실행 시험으로 재현이 무거운 두 writer(확정 · 사업주 서명)는 원문 구조로 본다 ─────────────────────
if (NEW) {
  const body = (name) => { const i = SRC.indexOf(`export const ${name} = onCall(`); return SRC.slice(i, SRC.indexOf('\nexport const ', i + 10)); };
  test('B1-S1 확정: 작업이 batch2(확정 완료 쓰기)에 실리고 commit 보다 앞 · 결정적 알림 id 그대로 · 직접 쓰기 0', () => {
    const b = body('callableConfirmApplication');
    const job = b.indexOf('batch2.create(cfJobRef, srvNotificationJobDoc("direct", {');
    const commit = b.indexOf('await batch2.commit();');
    assert.ok(job > 0 && commit > job);
    assert.ok(b.includes('notificationId: `application_confirmed_${applicationId}`,'));
    for (const k of ['type: "applicationConfirmed",', 'title: "지원 확정",', 'screen: "applicationDetail",',
      'body: `[${businessName}] ${selectedWorkType ?? ""} 지원이 확정되었습니다.`,']) assert.ok(b.includes(k), k);
    assert.ok(!/srvPersistNotification(WithId)?\(/.test(b), '확정 본문에 직접 알림 쓰기가 남았다');
  });
  test('B1-S2 사업주 서명: 두 거래(새 계약 · 기존 계약) 모두 같은 거래에서 작업 · 커밋 뒤 재읽기·직접 쓰기 0', () => {
    const b = body('callableFinalizeEmployerSignature');
    assert.strictEqual(b.split('tx.create(signJobRef, srvNotificationJobDoc("direct", {').length - 1, 2);
    assert.ok(b.indexOf('tx.set(contractRef, data);') < b.indexOf('tx.create(signJobRef'));
    for (const k of ['type: "contractSignRequested",', 'title: "근로계약서 서명 요청",', 'screen: "contractSign",',
      '`[${notifBizName}] 근로계약서를 확인하고 서명해 주세요.`']) assert.ok(b.includes(k), k);
    assert.ok(!/srvPersistNotification(WithId)?\(/.test(b));
    assert.ok(!b.includes('const notifSnap = await contractRef.get();'));
  });
}
