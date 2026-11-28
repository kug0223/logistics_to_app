'use strict';
/**
 * [L56 · I7 · 판정291 B5 · C08 · C06] 알림 영속 작업(outbox) · FCM trigger 보완.
 *
 *   A index.ts 원문 폐포(auth_kakao_index_harness) + 가짜 저장소 — 네트워크·실제 Firestore·FCM 0.
 *   L56_NEGCTL=1 이면 이전 원문(7f37434b) 사본에서 FCM 전량 실패 처리·PublishTO await fan-out 반례만 확인한다.
 */
const {test} = require('node:test');
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const {createFakeFirestore} = require('./consent_r4d_fakestore');
const {loadIndexClosure} = require('./auth_kakao_index_harness');

const NEG = process.env.L56_NEGCTL === '1';
const RealDate = Date;
const H = 3600 * 1000; const DAY = 24 * H; const KST = 9 * H;
const kstMid = (y, m, d) => RealDate.UTC(y, m - 1, d) - KST;
let NOW = kstMid(2026, 11, 26) + 10 * H;
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

// FCM 대용 — 호출 기록 · 응답 각본
const FCM = {calls: [], plan: null};
F.admin.messaging = () => ({
  sendEachForMulticast: async (msg) => {
    FCM.calls.push(msg);
    if (FCM.plan) return FCM.plan(msg);
    return {successCount: msg.tokens.length, responses: msg.tokens.map(() => ({success: true}))};
  },
});

const ROOTS = NEG ? ['onNotificationCreated', 'callableRejectResignation', 'callableApproveTermination'] : [
  'onNotificationCreated', 'onNotificationJobCreated', 'notificationJobSweeper', 'srvRunNotificationJob',
  'srvEnqueueNotificationJobInTx', 'srvNotificationJobDoc', 'callableApproveInterimSettlement', 'NOTIF_JOB_COL',
  'callableRejectResignation', 'callableRejectTermination', 'callableApproveTermination',
];
const {exports: X, info} = loadIndexClosure(ROOTS, F, {HttpsError, console: QCON, Date: FakeDate});
console.log('[폐포] ' + info + (NEG ? ' · NEGCTL' : ''));
const SRC = fs.readFileSync(path.join(__dirname, '..', 'src', 'index.ts'), 'utf8');
const bodyOf = (name) => {
  const i = SRC.indexOf(`export const ${name} = `);
  assert.ok(i > 0, name);
  return SRC.slice(i, SRC.indexOf('\n);\n', i));
};
const call = (fn, data, uid) => fn({data, auth: uid ? {uid, token: {}} : undefined});
const notifs = (uid) => Object.keys(F.dump()).filter((k) => k.startsWith(`users/${uid}/notifications/`));
const fcmEvent = (uid, nid, ageMs = 0) => ({
  data: {data: () => F.get(`users/${uid}/notifications/${nid}`)},
  params: {userId: uid, notificationId: nid},
  time: new RealDate(NOW - ageMs).toISOString(),
});
function resetAll() {
  F.reset(); LOGS.length = 0; FCM.calls.length = 0; FCM.plan = null;
}

// ── FCM trigger(이전 원문에도 있는 함수) ──────────────────────────────────────
function seedFcm(tokens = ['t1', 't2']) {
  F.put('users/u1', {role: 'USER', accountStatus: 'active', name: '근로자', fcmTokens: tokens});
  F.put('users/u1/notifications/n1', {userId: 'u1', type: 'toMatch', title: '제목', body: '본문', fcmSent: false});
}

if (NEG) {
  test('NEG-F 이전 원문 — FCM 전량 일시 실패여도 fcmSent=true 로 끝난다(반례 재현)', async () => {
    resetAll(); seedFcm();
    FCM.plan = (m) => ({successCount: 0, responses: m.tokens.map(() => ({success: false, error: {code: 'messaging/internal-error'}}))});
    await X.onNotificationCreated(fcmEvent('u1', 'n1'));
    assert.strictEqual(F.get('users/u1/notifications/n1').fcmSent, true, '전량 실패가 발송됨으로 기록(반례)');
  });
  test('NEG-R 이전 원문 — 퇴사 거절 알림 쓰기가 실패하면 알림이 유실된다(응답 성공 · 작업 0)', async () => {
    resetAll();
    F.put('users/own1', {role: 'BUSINESS_ADMIN', accountStatus: 'active', name: '사장', businessId: 'b1'});
    F.put('businesses/b1', {name: '평택 물류', ownerId: 'own1', adminIds: ['own1']});
    F.put('applications/ap1', {uid: 'w1', businessId: 'b1', businessName: '평택 물류', resignStatus: 'PENDING', status: 'CONFIRMED'});
    F.hooks.beforeCommit = (txId, buf) => {
      if (buf.some((w) => w.path.startsWith('users/w1/notifications/'))) throw new Error('UNAVAILABLE');
    };
    const out = await call(X.callableRejectResignation, {applicationId: 'ap1', rejectReason: '사유'}, 'own1');
    F.hooks.beforeCommit = null;
    assert.deepStrictEqual(out, {success: true});
    assert.strictEqual(notifs('w1').length, 0);
    assert.strictEqual(Object.keys(F.dump()).filter((k) => k.startsWith('notification_jobs/')).length, 0, '재시도 주인 없음(유실)');
  });
  test('NEG-T 이전 원문 — 해지 승인 알림을 응답 뒤 await 없이 실행한다(원문 · 금지 패턴)', () => {
    const b = bodyOf('callableApproveTermination');
    assert.ok(b.includes('    Promise.all(notifPromises).catch((e) =>'));
  });
  test('NEG-P 이전 원문 — PublishTO 가 커밋 뒤 fan-out 을 await 한다(원문)', () => {
    assert.ok(bodyOf('callablePublishTO').includes('await _dispatchToMatchNotifications('));
  });
} else {
  test('F1 FCM 성공 — fcmSent=true · 점유 해제 · 1회 발송', async () => {
    resetAll(); seedFcm();
    await X.onNotificationCreated(fcmEvent('u1', 'n1'));
    const n = F.get('users/u1/notifications/n1');
    assert.strictEqual(n.fcmSent, true);
    assert.strictEqual(n.fcmClaimUntil, undefined);
    assert.strictEqual(FCM.calls.length, 1);
    await X.onNotificationCreated(fcmEvent('u1', 'n1')); // 중복 전달
    assert.strictEqual(FCM.calls.length, 1, '두 번째 전달은 보내지 않는다');
  });

  test('F2 전량 영구 실패(만료 토큰뿐) — fcmSent=false · 사유 기록 · 재시도 throw 0 · 토큰 정리', async () => {
    resetAll(); seedFcm();
    FCM.plan = (m) => ({successCount: 0, responses: m.tokens.map(() => ({success: false, error: {code: 'messaging/registration-token-not-registered'}}))});
    await X.onNotificationCreated(fcmEvent('u1', 'n1'));
    const n = F.get('users/u1/notifications/n1');
    assert.strictEqual(n.fcmSent, false);
    assert.strictEqual(n.fcmFailure, 'NO_VALID_TOKEN');
    assert.strictEqual(n.fcmClaimUntil, undefined);
  });

  test('F3 전량 일시 실패 — throw(platform 재시도) · 점유 해제 · fcmSent 미기록 · 재시도에서 성공', async () => {
    resetAll(); seedFcm();
    FCM.plan = (m) => ({successCount: 0, responses: m.tokens.map(() => ({success: false, error: {code: 'messaging/internal-error'}}))});
    await assert.rejects(X.onNotificationCreated(fcmEvent('u1', 'n1')), /전량 실패/);
    const n = F.get('users/u1/notifications/n1');
    assert.notStrictEqual(n.fcmSent, true);
    assert.strictEqual(n.fcmClaimUntil, undefined, '점유 해제 — 재시도가 바로 보낼 수 있다');
    FCM.plan = null;
    await X.onNotificationCreated(fcmEvent('u1', 'n1'));
    assert.strictEqual(F.get('users/u1/notifications/n1').fcmSent, true);
  });

  test('F4 부분 성공(1/2) — fcmSent=true', async () => {
    resetAll(); seedFcm();
    FCM.plan = (m) => ({successCount: 1, responses: [{success: true}, {success: false, error: {code: 'messaging/internal-error'}}]});
    await X.onNotificationCreated(fcmEvent('u1', 'n1'));
    assert.strictEqual(F.get('users/u1/notifications/n1').fcmSent, true);
  });

  test('F5 동시 실행 — 유효 점유가 있으면 보내지 않는다 · 만료되면 보낸다 · 1시간 넘은 이벤트는 재시도 안 함', async () => {
    resetAll(); seedFcm();
    F.put('users/u1/notifications/n1', Object.assign(F.get('users/u1/notifications/n1'), {fcmClaimUntil: new Ts(NOW + 60 * 1000)}));
    await X.onNotificationCreated(fcmEvent('u1', 'n1'));
    assert.strictEqual(FCM.calls.length, 0);
    F.put('users/u1/notifications/n1', Object.assign(F.get('users/u1/notifications/n1'), {fcmClaimUntil: new Ts(NOW - 1)}));
    await X.onNotificationCreated(fcmEvent('u1', 'n1', 2 * H));
    assert.strictEqual(FCM.calls.length, 0, '1시간 초과 이벤트');
    await X.onNotificationCreated(fcmEvent('u1', 'n1'));
    assert.strictEqual(FCM.calls.length, 1);
  });

  // ── toMatch 작업 ─────────────────────────────────────────────────────────
  const DATE_KEY = '2026-11-28';
  function seedToMatch({published = true, deleted = false, workers = ['w1', 'w2']} = {}) {
    resetAll();
    F.put('tos/to1', {businessId: 'b1', isPublished: published, isDeleted: deleted, status: 'ACTIVE', type: 'short'});
    F.put('tos/to1/slots/s1', {status: 'open', date: new Ts(kstMid(2026, 11, 28)),
      workDetails: [{wdId: 'wd1', workType: '포장', startTime: '09:00', endTime: '18:00', requiredCount: 2}],
      workDetailCounts: {wd1: {confirmedCount: 0}}});
    for (const w of workers) {
      F.put(`worker_availability/${w}`, {city: '평택시', dates: [DATE_KEY]});
      F.put(`users/${w}`, {role: 'USER', accountStatus: 'active', name: w});
    }
    F.put('notification_jobs/toMatch__to1', X.srvNotificationJobDoc('toMatch',
      {toId: 'to1', businessId: 'b1', businessCity: '평택시', businessName: '평택 물류'}));
    // FieldValue.serverTimestamp 는 가짜 저장소가 Ts 로 바꾸지 않을 수 있다 — 접수 시각을 명시한다.
    F.put('notification_jobs/toMatch__to1', Object.assign(F.get('notification_jobs/toMatch__to1'), {createdAt: new Ts(NOW - 5 * 60 * 1000)}));
  }
  const job = () => F.get('notification_jobs/toMatch__to1');
  const jobEvent = (id = 'toMatch__to1', ageMs = 0) => ({params: {jobId: id}, time: new RealDate(NOW - ageMs).toISOString()});

  test('J1 작업 실행 — 수신자마다 결정적 알림 1개 · done · 진행 수 기록', async () => {
    seedToMatch();
    await X.onNotificationJobCreated(jobEvent());
    assert.deepStrictEqual(notifs('w1'), ['users/w1/notifications/toMatch_to1']);
    assert.deepStrictEqual(notifs('w2'), ['users/w2/notifications/toMatch_to1']);
    assert.strictEqual(job().status, 'done');
    assert.deepStrictEqual(job().progress, {created: 2, skipped: 0, suppressed: 0, failed: 0});
    assert.strictEqual(job().attempts, 1);
  });

  test('J2 중복 전달(trigger 2회 · sweeper 겹침) — 알림 그대로 1개씩 · 작업 재실행 0', async () => {
    seedToMatch();
    await X.onNotificationJobCreated(jobEvent());
    await X.onNotificationJobCreated(jobEvent());
    await X.notificationJobSweeper({});
    assert.strictEqual(notifs('w1').length + notifs('w2').length, 2);
    assert.strictEqual(job().attempts, 1);
  });

  test('J3 동시 실행 — 유효 lease 가 있으면 busy(손대지 않음)', async () => {
    seedToMatch();
    F.put('notification_jobs/toMatch__to1', Object.assign(job(), {status: 'running', leaseUntil: new Ts(NOW + 60 * 1000), leaseToken: 'other'}));
    assert.strictEqual(await X.srvRunNotificationJob('toMatch__to1'), 'busy');
    assert.strictEqual(notifs('w1').length, 0);
  });

  test('J4 부분 실패 → 재시도 — 실패한 수신자만 다음 실행에서 채워진다 · trigger 는 throw(재시도)', async () => {
    seedToMatch();
    let fail = true;
    F.hooks.beforeCommit = (txId, buf) => {
      if (fail && buf.some((w) => w.path === 'users/w2/notifications/toMatch_to1')) throw Object.assign(new Error('UNAVAILABLE'), {code: 14});
    };
    await assert.rejects(X.onNotificationJobCreated(jobEvent()), /재시도/);
    assert.strictEqual(job().status, 'pending');
    assert.ok(/부분 실패 1건/.test(job().lastError));
    assert.strictEqual(notifs('w1').length, 1);
    assert.strictEqual(notifs('w2').length, 0);
    fail = false;
    F.hooks.beforeCommit = null;
    await X.onNotificationJobCreated(jobEvent());
    assert.strictEqual(job().status, 'done');
    assert.deepStrictEqual(job().progress, {created: 1, skipped: 1, suppressed: 0, failed: 0}, 'w1 은 이미 있음(skip) · w2 생성');
    assert.strictEqual(notifs('w1').length + notifs('w2').length, 2);
  });

  test('J5 최대 시도 초과 — failed(관측) · trigger throw 0 · 재공개(재접수)로만 다시 pending', async () => {
    seedToMatch({workers: ['w1']});
    F.hooks.beforeCommit = (txId, buf) => {
      if (buf.some((w) => w.path.startsWith('users/w1/notifications/'))) throw new Error('UNAVAILABLE');
    };
    for (let i = 0; i < 4; i++) await assert.rejects(X.onNotificationJobCreated(jobEvent()));
    await X.onNotificationJobCreated(jobEvent()); // 5번째 — failed, throw 0
    F.hooks.beforeCommit = null;
    assert.strictEqual(job().status, 'failed');
    assert.strictEqual(job().attempts, 5);
    assert.ok(LOGS.some((l) => l.includes('FAILED(최대 시도)')));
    assert.strictEqual(await X.srvRunNotificationJob('toMatch__to1'), 'failed', 'sweeper·중복 전달로는 다시 돌지 않는다');
    // 재공개 = 같은 작업 재접수
    await F.db.runTransaction(async (tx) => {
      const ref = F.db.collection('notification_jobs').doc('toMatch__to1');
      const snap = await tx.get(ref);
      X.srvEnqueueNotificationJobInTx(tx, ref, snap, 'toMatch', {});
    });
    assert.strictEqual(job().status, 'pending');
    await X.srvRunNotificationJob('toMatch__to1');
    assert.strictEqual(job().status, 'done');
    assert.strictEqual(notifs('w1').length, 1);
  });

  test('J6 공개 뒤 삭제·비공개 — 알림 0 · done(skippedReason)', async () => {
    for (const o of [{published: false}, {deleted: true}]) {
      seedToMatch(o);
      await X.onNotificationJobCreated(jobEvent());
      assert.strictEqual(job().status, 'done');
      assert.strictEqual(job().skippedReason, 'TO_NOT_PUBLISHED');
      assert.strictEqual(notifs('w1').length + notifs('w2').length, 0);
    }
  });

  test('J7 수신자 탈퇴 진행 중(tombstone) — 그 수신자 알림 0 · suppressed 수', async () => {
    seedToMatch();
    F.put('account_deletion_tombstones/w2', {uid: 'w2'});
    await X.onNotificationJobCreated(jobEvent());
    assert.strictEqual(notifs('w2').length, 0);
    assert.strictEqual(job().progress.suppressed, 1);
    assert.strictEqual(job().status, 'done');
  });

  test('J8 유실 복구 — trigger 가 돌지 못한 pending · lease 만료 running 을 sweeper 가 실행 · 접수 2분 이내는 기다린다', async () => {
    seedToMatch();
    F.put('notification_jobs/toMatch__to1', Object.assign(job(), {createdAt: new Ts(NOW - 30 * 1000)}));
    await X.notificationJobSweeper({});
    assert.strictEqual(job().status, 'pending', '방금 접수된 작업은 trigger 몫');
    F.put('notification_jobs/toMatch__to1', Object.assign(job(), {status: 'running', leaseUntil: new Ts(NOW - 1), leaseToken: 'dead', attempts: 1}));
    await X.notificationJobSweeper({});
    assert.strictEqual(job().status, 'done');
    assert.strictEqual(job().attempts, 2);
    assert.strictEqual(notifs('w1').length + notifs('w2').length, 2);
  });

  test('J9 늦은 결과 — lease 가 넘어간 뒤 끝난 실행은 상태를 덮지 않는다', async () => {
    seedToMatch({workers: []});
    // 실행 중에 다른 실행이 lease 를 가져간 상황: claim 직후 leaseToken 을 바꾼다
    F.hooks.afterGet = (p, txId) => {
      if (p === 'tos/to1') {
        F.put('notification_jobs/toMatch__to1', Object.assign(job(), {leaseToken: 'stolen'}));
        F.hooks.afterGet = null;
      }
    };
    await X.srvRunNotificationJob('toMatch__to1');
    assert.strictEqual(job().status, 'running', '내 lease 가 아니면 done 을 쓰지 않는다');
    assert.strictEqual(job().leaseToken, 'stolen');
  });

  // ── 해지·퇴사 거절 알림(L56 r2) ───────────────────────────────────────────
  function seedReject() {
    resetAll();
    F.put('users/own1', {role: 'BUSINESS_ADMIN', accountStatus: 'active', name: '사장', businessId: 'b1'});
    F.put('businesses/b1', {name: '평택 물류', ownerId: 'own1', adminIds: ['own1']});
    F.put('users/w1', {role: 'USER', accountStatus: 'active', name: '근로자'});
    F.put('applications/ap1', {uid: 'w1', businessId: 'b1', businessName: '평택 물류', resignStatus: 'PENDING',
      terminationStatus: 'PENDING', terminationRequestedByUid: 'w1', status: 'CONFIRMED'});
  }
  const jobsNow = () => Object.keys(F.dump()).filter((k) => k.startsWith('notification_jobs/')).map((k) => k.split('/')[1]);

  for (const [label, fn, field, type] of [
    ['RJ1 퇴사 거절', 'callableRejectResignation', 'resignStatus', 'resignRejected'],
    ['RJ2 해지 거절', 'callableRejectTermination', 'terminationStatus', 'terminationRejected'],
  ]) {
    test(`${label} — 알림 작업이 거절과 같은 거래 · 알림 쓰기가 실패해도 작업이 남아 재시도로 채워진다(유실 0)`, async () => {
      seedReject();
      const before = F.W.commits.length;
      const out = await call(X[fn], {applicationId: 'ap1', rejectReason: '사유'}, 'own1');
      assert.deepStrictEqual(out, {success: true});
      assert.strictEqual(F.get('applications/ap1')[field], 'REJECTED');
      const c = F.W.commits.slice(before).find((x) => x.writes.some((w) => w.path === 'applications/ap1'));
      assert.ok(c.writes.some((w) => w.path.startsWith('notification_jobs/') && w.op === 'create'), '같은 거래');
      assert.strictEqual(notifs('w1').length, 0, '커밋 뒤 직접 쓰기 0');
      const [jobId] = jobsNow();
      // 첫 실행: 알림 쓰기 실패 → 작업 pending(재시도 대상) · trigger throw
      F.hooks.beforeCommit = (txId, buf) => {
        if (buf.some((w) => w.path.startsWith('users/w1/notifications/'))) throw new Error('UNAVAILABLE');
      };
      await assert.rejects(X.onNotificationJobCreated({params: {jobId}, time: new RealDate(NOW).toISOString()}));
      F.hooks.beforeCommit = null;
      assert.strictEqual(F.get('notification_jobs/' + jobId).status, 'pending');
      await X.onNotificationJobCreated({params: {jobId}, time: new RealDate(NOW).toISOString()});
      const ns = notifs('w1');
      assert.strictEqual(ns.length, 1);
      assert.strictEqual(F.get(ns[0]).type, type);
      assert.ok(F.get(ns[0]).body.includes('사유: 사유'));
    });
  }

  test('AT1 해지 승인(관리자 요청) — 근무자·관리자 알림 작업 2건이 승인과 같은 거래 · 응답 뒤 실행 0 · worker 가 1개씩', async () => {
    resetAll();
    F.put('users/own1', {role: 'BUSINESS_ADMIN', accountStatus: 'active', name: '사장', businessId: 'b1'});
    F.put('users/own2', {role: 'BUSINESS_ADMIN', accountStatus: 'active', name: '공동', businessId: 'b1'});
    F.put('businesses/b1', {name: '평택 물류', ownerId: 'own1', adminIds: ['own1', 'own2']});
    F.put('users/w1', {role: 'USER', accountStatus: 'active', name: '근로자'});
    F.put('applications/ap1', {uid: 'w1', businessId: 'b1', businessName: '평택 물류', status: 'CONFIRMED',
      terminationStatus: 'PENDING', terminationRequestedByUid: 'own2', terminationEffectiveDate: new Ts(kstMid(2026, 11, 30))});
    const before = F.W.commits.length;
    const out = await call(X.callableApproveTermination, {applicationId: 'ap1'}, 'w1');
    assert.deepStrictEqual(out, {success: true});
    const c = F.W.commits.slice(before).find((x) => x.writes.some((w) => w.path === 'applications/ap1'));
    const jobWrites = c.writes.filter((w) => w.path.startsWith('notification_jobs/') && w.op === 'create');
    assert.strictEqual(jobWrites.length, 2, '근무자 + 요청 관리자');
    assert.strictEqual(notifs('w1').length + notifs('own2').length, 0, '응답 전 직접 쓰기 0');
    for (const id of Object.keys(F.dump()).filter((k) => k.startsWith('notification_jobs/')).map((k) => k.split('/')[1])) {
      await X.onNotificationJobCreated({params: {jobId: id}, time: new RealDate(NOW).toISOString()});
    }
    const w = F.get(notifs('w1')[0]); const a = F.get(notifs('own2')[0]);
    assert.strictEqual(w.data.action, 'terminationDetail');
    assert.strictEqual(a.data.screen, 'fixedWorker');
    assert.ok(w.body.includes('해지일: 11/30'));
  });

  test('AT2 해지 승인(근무자 요청) — 근무자 1건만(중복 방지 분기 그대로)', async () => {
    resetAll();
    F.put('users/own1', {role: 'BUSINESS_ADMIN', accountStatus: 'active', name: '사장', businessId: 'b1'});
    F.put('businesses/b1', {name: '평택 물류', ownerId: 'own1', adminIds: ['own1']});
    F.put('users/w1', {role: 'USER', accountStatus: 'active', name: '근로자'});
    F.put('applications/ap1', {uid: 'w1', businessId: 'b1', businessName: '평택 물류', status: 'CONFIRMED',
      terminationStatus: 'PENDING', terminationRequestedByUid: 'w1', terminationEffectiveDate: new Ts(kstMid(2026, 11, 30))});
    await call(X.callableApproveTermination, {applicationId: 'ap1'}, 'own1');
    assert.strictEqual(Object.keys(F.dump()).filter((k) => k.startsWith('notification_jobs/')).length, 1);
    assert.ok(!bodyOf('callableApproveTermination').includes('    Promise.all(notifPromises).catch((e) =>'), '응답 뒤 fire-and-forget 문장 0');
  });

  // ── C08 · C06 · PublishTO 원문 ───────────────────────────────────────────
  function seedSettlement() {
    resetAll();
    F.put('users/own1', {role: 'BUSINESS_ADMIN', accountStatus: 'active', name: '사장', businessId: 'b1'});
    F.put('businesses/b1', {name: '평택 물류', ownerId: 'own1', adminIds: ['own1']});
    F.put('users/w1', {role: 'USER', accountStatus: 'active', name: '근로자'});
    F.put('interim_settlement_requests/r1', {businessId: 'b1', businessName: '평택 물류', status: 'PENDING', workerId: 'w1',
      attendanceIds: ['a1'], periodStart: new Ts(kstMid(2026, 11, 1)), periodEnd: new Ts(kstMid(2026, 11, 15)),
      requestedAmount: 1, netAmount: 999});
    F.put('attendance/a1', {userId: 'w1', businessId: 'b1', wageStatus: 'confirmed', finalWage: 100000, wageDetail: {netWage: 96700}});
  }

  test('C08 중간정산 승인 — 알림 작업이 승인과 같은 거래 · 커밋 뒤 알림 쓰기 0 · 금액은 승인 확정값 · worker 가 알림 1개', async () => {
    seedSettlement();
    const before = F.W.commits.length;
    const out = await call(X.callableApproveInterimSettlement,
      {settlementRequestId: 'r1', businessId: 'b1', scheduledTransferDate: '2026-11-30'}, 'own1');
    assert.deepStrictEqual(out, {success: true});
    const commits = F.W.commits.slice(before);
    const approveCommit = commits.find((c) => c.writes.some((w) => w.path === 'interim_settlement_requests/r1'));
    assert.ok(approveCommit.writes.some((w) => w.path.startsWith('notification_jobs/') && w.op === 'create'), '같은 거래의 작업');
    assert.strictEqual(notifs('w1').length, 0, '응답 전 커밋 뒤 알림 쓰기 0');
    const jobId = Object.keys(F.dump()).find((k) => k.startsWith('notification_jobs/')).split('/')[1];
    const j = F.get('notification_jobs/' + jobId);
    assert.strictEqual(j.kind, 'direct');
    assert.strictEqual(j.payload.data.netAmount, '96700', '승인 거래가 확정한 실수령액(요청 시점 999 아님)');
    await X.onNotificationJobCreated({params: {jobId}, time: new RealDate(NOW).toISOString()});
    assert.strictEqual(notifs('w1').length, 1);
    await X.onNotificationJobCreated({params: {jobId}, time: new RealDate(NOW).toISOString()});
    assert.strictEqual(notifs('w1').length, 1, '재실행 1개 그대로');
  });

  test('C08b 승인 거래가 실패하면 작업도 없다(원자)', async () => {
    seedSettlement();
    F.put('attendance/a1', Object.assign(F.get('attendance/a1'), {wageStatus: 'pending'}));
    await assert.rejects(call(X.callableApproveInterimSettlement,
      {settlementRequestId: 'r1', businessId: 'b1', scheduledTransferDate: '2026-11-30'}, 'own1'));
    assert.strictEqual(Object.keys(F.dump()).filter((k) => k.startsWith('notification_jobs/')).length, 0);
  });

  test('P1/C06 원문 — PublishTO 는 공개 거래에서 작업을 접수하고 fan-out 을 기다리지 않는다 · 지원 알림 id = 저장 id', () => {
    const pub = bodyOf('callablePublishTO');
    assert.ok(!pub.includes('_dispatchToMatchNotifications('), '응답 경로의 fan-out 0');
    assert.ok(pub.includes('const toMatchJobSnap = toMatchJobRef ? await tx.get(toMatchJobRef) : null;'));
    assert.ok(pub.indexOf('await tx.get(toMatchJobRef)') < pub.indexOf('tx.update(toRef, publishUpdates);'), '읽기 구간');
    assert.ok(pub.includes('srvEnqueueNotificationJobInTx(tx, toMatchJobRef, toMatchJobSnap, "toMatch"'));
    const apply = bodyOf('callableApplyToTO');
    assert.ok(apply.includes('applicationId: applyDocId,'));
    assert.ok(!/applicationId: complexId,\n\s+toId,/.test(apply));
    const appr = bodyOf('callableApproveInterimSettlement');
    assert.ok(!appr.includes('await srvPersistNotification('), '커밋 뒤 알림 await 0');
  });
}
