'use strict';
/**
 * [L56 r6 · 묶음3a] 커밋 뒤 알림 → 같은 거래 direct 작업 — 동치 · 누락 0.
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
const NEW = SRC.includes('[L56 r6]');
const FNS = ['callableReviewUserDocument', 'callableRespondIdCardAccessRequest', 'srvWithdrawInvitesByBusinessEnd'];
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
  ['WI 사업장 비활성 초대 철회(2건)', () => {
    base();
    F.put('businesses/b1', Object.assign(F.get('businesses/b1'), {deactivatedAt: new Ts(NOW - 60000)}));
    F.put('tos/t1', {businessId: 'b1', title: '물류'});
    for (const [id, uid] of [['a1', 'w1'], ['a2', 'w2']]) {
      F.put(`users/${uid}`, {role: 'USER', accountStatus: 'active', name: uid});
      F.put(`applications/${id}`, {uid, businessId: 'b1', toId: 't1', toTitle: '물류', status: 'INVITED'});
    }
  }, () => X.srvWithdrawInvitesByBusinessEnd({businessId: 'b1', reason: 'BUSINESS_DEACTIVATED', actor: null}).then((n) => ({success: n === 2, n})),
  'applications/a1'],
  ['RV 서류 검토 반려(슈퍼관리자)', () => {
    base();
    F.put('users/su1', {role: 'SUPER_ADMIN', accountStatus: 'active'});
    F.put('users/w1', Object.assign(F.get('users/w1'), {idCardImagePath: 'users/w1/id.png', isIdVerified: true}));
  }, () => call(X.callableReviewUserDocument, {targetUserId: 'w1', documentType: 'ID_CARD', decision: 'REJECT', note: '흐림'}, 'su1'),
  'users/w1'],
  ['IC 신분증 열람 요청 승인(근로자)', () => {
    base();
    F.put('idCardAccessRequests/q1', {targetUserId: 'w1', targetUserName: '근로자', requesterId: 'own1', requesterBusinessId: 'b1',
      status: 'pending'});
  }, () => call(X.callableRespondIdCardAccessRequest, {requestId: 'q1', action: 'approve'}, 'w1'), 'idCardAccessRequests/q1'],
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
  test(`B3 ${id}`, async () => {
    seed();
    const r = await run();
    // 예전 원문의 fire-and-forget 알림(.catch)이 끝나도록 이벤트 루프를 몇 번 돌린다(새 원문엔 영향 없음).
    for (let i = 0; i < 30; i++) await new Promise((res) => setImmediate(res));
    assert.ok(r && r.success !== false, `${id} 호출 실패: ${JSON.stringify(r)}`);
    if (NEW) {
      assert.deepStrictEqual(notifDocs(), [], `${id} 응답 전에 알림을 직접 썼다`);
      const jobKeys = [...F.STORE.keys()].filter((k) => k.startsWith('notification_jobs/'));
      assert.ok(jobKeys.length >= 1, `${id} 작업이 없다`);
      for (const k of jobKeys) {
        const c = F.W.commits.find((x) => x.writes.some((w) => w.path === k));
        const dom = id.startsWith('WI') ? c.writes.some((w) => /^applications\//.test(w.path)) :
          c.writes.some((w) => w.path === domainPath);
        assert.ok(dom, `${id} 작업이 도메인 쓰기와 다른 커밋`);
      }
      await runJobs();
      // 다시 돌려도 알림은 늘지 않는다(작업 done · 결정적 id).
      const n1 = notifDocs().length; await runJobs(); assert.strictEqual(notifDocs().length, n1);
    }
    OUT[id] = notifDocs().map((p) => ({at: shape(p), doc: strip(F.get(p))})).sort((a, b) => a.at.localeCompare(b.at));
  });
}

if (NEW) {
  test('B3-NEG 알림 쓰기가 한 번 실패해도 작업이 남아 다음 실행에서 만든다(예전: 유실)', async () => {
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
  if (process.env.L56B3_OUT) fs.writeFileSync(process.env.L56B3_OUT, JSON.stringify(OUT, null, 2));
  assert.strictEqual(Object.keys(OUT).length, SCEN.length);
  for (const [id] of SCEN) assert.ok(OUT[id].length >= 1, `${id} 알림이 0건`);
});
if (process.env.L56B3_COMPARE) {
  test('EQ 이전 원문(커밋 뒤 직접 쓰기)과 수신자·id 모양·본문이 같다 — 누락 0', () => {
    const old = JSON.parse(fs.readFileSync(process.env.L56B3_COMPARE, 'utf8'));
    for (const k of Object.keys(old)) assert.deepStrictEqual(OUT[k], old[k], k);
  });
}


if (NEW) {
  const body = (name) => { const i = SRC.indexOf(`export const ${name} = onCall(`); return SRC.slice(i, SRC.indexOf('\n);\n', i)); };
  test('B3-S 서류 보완 요청: 새로 연 요청의 거래 안 작업 · 결정적 id 그대로 · 직접 쓰기 0', () => {
    const b = body('callableRequestDocumentCorrection');
    const job = b.indexOf('tx.create(dcJobRef, srvNotificationJobDoc("direct", {');
    assert.ok(job > 0 && job < b.indexOf('      return true;\n    });'));
    assert.ok(b.includes('notificationId: `doc_correction_${reqId}_${now.toMillis()}`,'));
    assert.ok(!/srvPersistNotification(WithId)?\(/.test(b));
  });
  test('B3-IDEM 이미 처리된 열람 요청 응답은 작업 0', async () => {
    SCEN[2][1]();
    F.put('idCardAccessRequests/q1', Object.assign(F.get('idCardAccessRequests/q1'), {status: 'approved'}));
    const r = await call(X.callableRespondIdCardAccessRequest, {requestId: 'q1', action: 'approve'}, 'w1');
    assert.strictEqual(r.alreadyHandled, true);
    assert.strictEqual([...F.STORE.keys()].filter((k) => k.startsWith('notification_jobs/')).length, 0);
  });
}
