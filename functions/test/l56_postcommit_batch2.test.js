'use strict';
/**
 * [L56 r5 · 묶음2] 커밋 뒤 알림 → 같은 거래 direct 작업 — 동치 · 누락 0.
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
const NEW = SRC.includes('[L56 r5]');
const FNS = ['callableCancelTOInvitation', 'callableDeclineTOInvitation', 'callableRequestResignation',
  'callableApproveScheduleChangeRequest', 'callableCreateScheduleChangeRequest', 'callableAcceptInvitation'];
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
  ['CI 초대 취소(관리자)', () => {
    base();
    F.put('tos/t1', {businessId: 'b1', title: '물류'});
    F.put('tos/t1/slots/s1', {workDetailCounts: {wd1: {pendingCount: 1}}});
    F.put('applications/a1', {uid: 'w1', businessId: 'b1', businessName: '평택', toId: 't1', slotId: 's1', wdId: 'wd1',
      toTitle: '물류', status: 'INVITED', invitedBy: 'own1', invitedAt: new Ts(NOW - 3600000)});
  }, () => call(X.callableCancelTOInvitation, {applicationId: 'a1'}, 'own1'), 'applications/a1'],
  ['DI 초대 거절(근로자 · 슬롯)', () => {
    base();
    F.put('tos/t1', {businessId: 'b1', title: '물류', totalPending: 1});
    F.put('tos/t1/slots/s1', {pendingCount: 1, confirmedCount: 0, status: 'open', date: new Ts(NOW + 2 * DAY),
      workDetails: [{wdId: 'wd1', workType: '포장', startTime: '09:00', endTime: '18:00', requiredCount: 2, wage: 12000, wageType: 'hourly'}],
      workDetailCounts: {wd1: {pendingCount: 1, confirmedCount: 0}}});
    F.put('applications/a1', {uid: 'w1', businessId: 'b1', businessName: '평택', toId: 't1', slotId: 's1', wdId: 'wd1',
      toTitle: '물류', status: 'INVITED', invitedBy: 'own1', invitedAt: new Ts(NOW - 3600000),
      inviteExpiresAt: new Ts(NOW + 20 * 3600000), selectedWorkType: '포장', startTime: '09:00', endTime: '18:00', applicantName: '근로자'});
  }, () => call(X.callableDeclineTOInvitation, {applicationId: 'a1', declineIntent: 'EXPLICIT'}, 'w1'), 'applications/a1'],
  ['RR 퇴사 요청(관리자·부관리자 fan-out)', () => {
    base();
    F.put('businesses/b1/members/sub1', {uid: 'sub1', permissions: {canManageWorkers: true}});
    F.put('applications/a1', {uid: 'w1', businessId: 'b1', businessName: '평택', status: 'CONFIRMED', type: 'long_term',
      workEndDate: new Ts(NOW + 40 * DAY)});
  }, () => call(X.callableRequestResignation, {applicationId: 'a1', resignDateIso: new RealDate(NOW + 14 * DAY).toISOString()}, 'w1'),
  'applications/a1'],
  ['SA 스케줄 변경 거절', () => {
    base();
    F.put('applications/a1', {uid: 'w1', businessId: 'b1', status: 'CONFIRMED', type: 'long_term'});
    F.put('schedule_change_requests/q1', {applicationId: 'a1', businessId: 'b1', applicantUid: 'w1', requestType: 'LEAVE',
      // [server_296 판정297] 실제 writer 가 만드는 모양(rules 근로자 갈래 = requestedBy 'APPLICANT' · requestedByUid 본인).
      //   예전 'WORKER' 는 어떤 writer 도 쓰지 않는 값이라 이제 생성 주체 유형 검증(SCR_TYPE_INVALID)에 걸린다.
      targetDate: new Ts(NOW + 5 * DAY), status: 'PENDING', requestedBy: 'APPLICANT', requestedByUid: 'w1'});
  }, () => call(X.callableApproveScheduleChangeRequest, {requestId: 'q1', action: 'REJECTED', rejectReason: '인원 부족'}, 'own1'),
  'schedule_change_requests/q1'],
  ['SC 스케줄 변경 요청 생성(관리자 → 근로자)', () => {
    base();
    F.put('applications/a1', {uid: 'w1', businessId: 'b1', status: 'CONFIRMED', type: 'long_term'});
  }, () => call(X.callableCreateScheduleChangeRequest, {applicationId: 'a1', businessId: 'b1', targetDateMs: NOW + 6 * DAY,
    requestType: 'EXTRA_WORK', reason: '물량 증가'}, 'own1'), null],
  ['MI 관리자 초대 수락', () => {
    base();
    F.put('member_invitations/m1', {businessId: 'b1', businessName: '평택', targetUid: 'w1', targetName: '근로자', status: 'pending',
      invitedBy: 'own1', permissions: {canManageTo: true}, createdAt: new Ts(NOW - DAY)});
  }, () => call(X.callableAcceptInvitation, {invitationId: 'm1'}, 'w1'), 'member_invitations/m1'],
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
  test(`B2 ${id}`, async () => {
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
        const dom = domainPath ? c.writes.some((w) => w.path === domainPath) :
          c.writes.some((w) => w.path.startsWith('schedule_change_requests/'));
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
  test('B2-NEG 알림 쓰기가 한 번 실패해도 작업이 남아 다음 실행에서 만든다(예전: 유실)', async () => {
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
  if (process.env.L56B2_OUT) fs.writeFileSync(process.env.L56B2_OUT, JSON.stringify(OUT, null, 2));
  assert.strictEqual(Object.keys(OUT).length, SCEN.length);
  for (const [id] of SCEN) assert.ok(OUT[id].length >= 1, `${id} 알림이 0건`);
});
if (process.env.L56B2_COMPARE) {
  test('EQ 이전 원문(커밋 뒤 직접 쓰기)과 수신자·id 모양·본문이 같다 — 누락 0', () => {
    const old = JSON.parse(fs.readFileSync(process.env.L56B2_COMPARE, 'utf8'));
    for (const k of Object.keys(old)) assert.deepStrictEqual(OUT[k], old[k], k);
  });
}


if (NEW) {
  test('B2-IDEM 취소: 그 사이 수락돼 취소하지 않은 경우 알림 0(예전: 알림)', async () => {
    SCEN[0][1]();
    F.hooks.afterGet = (p, txId) => {
      if (txId != null && p === 'applications/a1') { F.hooks.afterGet = null; }
    };
    // 사전 읽기 뒤 거래 전에 수락된 상황: 거래 안 fresh 가 CONFIRMED
    const orig = F.db.runTransaction;
    F.db.runTransaction = async (fn) => {
      F.put('applications/a1', Object.assign(F.get('applications/a1'), {status: 'CONFIRMED'}));
      F.db.runTransaction = orig;
      return orig(fn);
    };
    await call(X.callableCancelTOInvitation, {applicationId: 'a1'}, 'own1');
    F.db.runTransaction = orig;
    assert.strictEqual([...F.STORE.keys()].filter((k) => k.startsWith('notification_jobs/')).length, 0);
  });
  // 함수 본문만(뒤에 이어지는 비공개 helper 제외) — 첫 '\n);\n' 까지.
  const body = (name) => { const i = SRC.indexOf(`export const ${name} = onCall(`); return SRC.slice(i, SRC.indexOf('\n);\n', i)); };
  test('B2-S 무거운 세 writer: 같은 거래 작업 · 직접 쓰기 0 · 본문 필드 · 결정적 id', () => {
    const acc = body('callableAcceptTOInvitation');
    assert.ok(acc.includes('tx.create(accJobRef, srvNotificationJobDoc("direct", {'));
    for (const k of ['"workReassignmentAccepted" : "toInviteAccepted"', '"제안한 업무로 확정됐습니다" : "초대를 수락했습니다 ✅"',
      'action: "applicationDetail",']) assert.ok(acc.includes(k), k);
    const inv = body('callableInviteWorker');
    assert.ok(inv.includes('invTx.create(invJobRef, srvNotificationJobDoc("direct", {'));
    assert.ok(inv.includes('notificationId: `to_invite_${newAppRef.id}_${inviteTime.toMillis()}`,'));
    const ap = body('callableApplyToTO');
    assert.ok(ap.includes('tx.create(naJobRef, srvNotificationJobDoc("direct", {'));
    assert.ok(ap.includes('applicationId: applyDocId,') && ap.includes('type: "newApplication",'));
    const rv = body('callableApproveApplicationForReview');
    assert.strictEqual(rv.split('queueApproveNotice(tx);').length - 1, 2, '승인 · 멱등 재호출 두 자리');
    assert.ok(rv.includes('const notifDocId = `application_confirmed_${applicationId}`;'));
    for (const b of [acc, inv, ap, rv]) assert.ok(!/srvPersistNotification(WithId)?\(/.test(b), '직접 알림 쓰기가 남았다');
  });
}
