'use strict';
/**
 * [판정293 (3) · directmany_spec.md §4 · §6 S-D/S-E/S-H/S-I] 여러 수신자 작업 consumer — producer 0 판.
 *
 *   A index.ts 원문 폐포 + 가짜 저장소. 작업 문서는 시험이 직접 만든다(이 판에는 작업을 만드는 producer 가 없다).
 *   DM_EXPECT_OLD=1 이면 이전 원문(be3108c0 사본)에서 '구 실행기가 모르는 kind 를 done 으로 닫는다' 반례만 확인한다.
 */
const {test} = require('node:test');
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const {createFakeFirestore} = require('./consent_r4d_fakestore');
const {loadIndexClosure} = require('./auth_kakao_index_harness');

const OLD = process.env.DM_EXPECT_OLD === '1';
const RealDate = Date;
const MIN = 60 * 1000;
let NOW = RealDate.UTC(2026, 10, 27, 3, 0);
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
const ROOTS = OLD ? ['srvRunNotificationJob'] : ['srvRunNotificationJob', 'srvRunNotificationJobMany',
  'onNotificationJobManyCreated', 'notificationJobSweeper', 'srvSweepNotificationJobs', 'onNotificationJobCreated'];
const {exports: X} = loadIndexClosure(ROOTS, F, {HttpsError, console: QCON, Date: FakeDate});
const SRC = fs.readFileSync(path.join(__dirname, '..', 'src', 'index.ts'), 'utf8');

const pl = (uid, i) => ({userId: uid, type: 'workCanceled', title: '근무 취소', body: `공고가 취소되어 근무가 취소되었습니다 ${i}`,
  isRead: false, fcmSent: false});
const items = (n, pre = 'n') => Array.from({length: n}, (_, i) => ({recipientUid: `u${i}`, notificationId: `${pre}${i}`,
  payload: pl(`u${i}`, i)}));
const manyJob = (over = {}) => Object.assign({kind: 'directMany', kindVersion: 1, schemaVersion: 1, sourceKind: 'toDeleted',
  sourceId: 't1', businessId: 'b1', mode: 'items', items: items(3), chunkIndex: 0, chunkCount: 1, chunkGroupId: 'g1',
  status: 'pending', attempts: 0, leaseUntil: null, lastError: null, progress: null, createdAt: new Ts(NOW),
  startedAt: null, finishedAt: null}, over);
const notifCount = () => Object.keys(F.dump()).filter((k) => /^users\/[^/]+\/notifications\//.test(k)).length;
const ev = (id, ageMs = 0) => ({params: {jobId: id}, time: new RealDate(NOW - ageMs).toISOString()});
function reset() { F.reset(); LOGS.length = 0; NOW = RealDate.UTC(2026, 10, 27, 3, 0); }

test('H1 혼재 장벽 — 기존 실행기는 모르는 kind(directMany)를 done 으로 닫지 않는다(failed · 알림 0)', async () => {
  reset();
  F.put('notification_jobs/m1', manyJob());
  const o = await X.srvRunNotificationJob('m1');
  const j = F.get('notification_jobs/m1');
  assert.strictEqual(notifCount(), 0);
  if (OLD) {
    assert.strictEqual(o, 'skipped');
    assert.strictEqual(j.status, 'done', '음성 대조: 이전 원문은 모르는 작업을 done 으로 닫는다(유실이 숨는다)');
    assert.strictEqual(j.skippedReason, 'UNKNOWN_KIND');
    return;
  }
  assert.strictEqual(o, 'failed');
  assert.strictEqual(j.status, 'failed');
  assert.strictEqual(j.lastError, 'UNSUPPORTED_KIND:directMany');
});

if (!OLD) {
  test('H2 혼재 장벽 — 구 trigger·구 sweeper 는 새 컬렉션을 보지 않는다(경로 · 동작)', async () => {
    reset();
    assert.match(SRC, /const NOTIF_JOB_COL = "notification_jobs";/);
    assert.match(SRC, /const NOTIF_JOB_MANY_COL = "notification_jobs_many";/);
    const trig = SRC.slice(SRC.indexOf('export const onNotificationJobCreated = '), SRC.indexOf('\n);\n', SRC.indexOf('export const onNotificationJobCreated = ')));
    assert.ok(trig.includes('{document: `${NOTIF_JOB_COL}/{jobId}`'));
    F.put('notification_jobs_many/m1', manyJob({createdAt: new Ts(NOW - 10 * MIN)}));
    await X.srvSweepNotificationJobs(NOW);
    assert.strictEqual(F.get('notification_jobs_many/m1').status, 'pending', '구 sweeper 가 새 컬렉션 작업을 건드렸다');
    assert.strictEqual(notifCount(), 0);
  });

  test('M1 정상 — 항목마다 결정적 id 알림 1 · done · 집계 · 다시 돌려도 수신자당 1', async () => {
    reset();
    F.put('notification_jobs_many/m1', manyJob());
    await X.onNotificationJobManyCreated(ev('m1'));
    const j = F.get('notification_jobs_many/m1');
    assert.strictEqual(j.status, 'done');
    assert.deepStrictEqual(j.progress, {total: 3, created: 3, suppressed: 0, skipped: 0, failed: 0, invalid: 0});
    for (let i = 0; i < 3; i++) assert.deepStrictEqual(F.get(`users/u${i}/notifications/n${i}`), pl(`u${i}`, i));
    assert.ok(LOGS.some((l) => l.includes('notifJobMany consumer v1 ready')), '관측 표식');
    await X.onNotificationJobManyCreated(ev('m1')); // 중복 전달
    assert.strictEqual(notifCount(), 3);
  });

  test('S-D 부분 실패 — 한 수신자 쓰기 실패 → pending 재시도 → 그 1건만 생성 · 합계 = 대상 수', async () => {
    reset();
    F.put('notification_jobs_many/m1', manyJob());
    let fail = true;
    F.hooks.beforeCommit = (txId, buf) => {
      if (fail && buf.some((w) => w.path === 'users/u1/notifications/n1')) { fail = false; throw new Error('UNAVAILABLE'); }
    };
    await assert.rejects(X.onNotificationJobManyCreated(ev('m1')), /재시도/);
    F.hooks.beforeCommit = null;
    let j = F.get('notification_jobs_many/m1');
    assert.strictEqual(j.status, 'pending');
    assert.strictEqual(j.attempts, 1);
    assert.match(j.lastError, /부분 실패 1건/);
    assert.strictEqual(notifCount(), 2);
    await X.onNotificationJobManyCreated(ev('m1'));
    j = F.get('notification_jobs_many/m1');
    assert.strictEqual(j.status, 'done');
    assert.deepStrictEqual(j.progress, {total: 3, created: 1, suppressed: 0, skipped: 2, failed: 0, invalid: 0});
    assert.strictEqual(notifCount(), 3);
  });

  test('S-D2 최대 시도 — 5번째 실패는 failed · throw 0', async () => {
    reset();
    F.put('notification_jobs_many/m1', manyJob({attempts: 4}));
    F.hooks.beforeCommit = (txId, buf) => {
      if (buf.some((w) => w.path === 'users/u2/notifications/n2')) throw new Error('UNAVAILABLE');
    };
    await X.onNotificationJobManyCreated(ev('m1'));
    F.hooks.beforeCommit = null;
    assert.strictEqual(F.get('notification_jobs_many/m1').status, 'failed');
    assert.strictEqual(F.get('notification_jobs_many/m1').attempts, 5);
  });

  test('S-E 중복 — 유효 lease 점유 중이면 busy · 쓰기 0', async () => {
    reset();
    F.put('notification_jobs_many/m1', manyJob({status: 'running', leaseToken: 'other', leaseUntil: new Ts(NOW + MIN)}));
    assert.strictEqual(await X.srvRunNotificationJobMany('m1'), 'busy');
    assert.strictEqual(notifCount(), 0);
    await X.notificationJobSweeper({}); // lease 유효 → sweeper 도 건드리지 않음
    assert.strictEqual(F.get('notification_jobs_many/m1').leaseToken, 'other');
    assert.strictEqual(notifCount(), 0);
  });

  test('S-E2 lease 를 잃은 실행 — 남은 항목 중단 · 결과 기록 0 · 이어 받은 실행이 빠진 것만 생성', async () => {
    reset();
    F.put('notification_jobs_many/m1', manyJob({items: items(25)}));
    let n = 0;
    F.hooks.beforeCommit = (txId, buf) => {
      if (buf.some((w) => /^users\/[^/]+\/notifications\//.test(w.path)) && ++n === 10) {
        NOW += 4 * MIN; // 첫 묶음 처리 중 4분 경과 — 다음 묶음 전 lease 갱신 시점
        F.put('notification_jobs_many/m1', Object.assign(F.get('notification_jobs_many/m1'),
          {leaseToken: 'taker', leaseUntil: new Ts(NOW + 9 * MIN)})); // 다른 실행이 lease 를 가져감
      }
    };
    const o = await X.srvRunNotificationJobMany('m1');
    F.hooks.beforeCommit = null;
    assert.strictEqual(o, 'busy');
    const j = F.get('notification_jobs_many/m1');
    assert.strictEqual(j.leaseToken, 'taker', '늦은 실행이 남의 lease 결과를 덮었다');
    assert.strictEqual(j.status, 'running');
    assert.strictEqual(notifCount(), 10, 'lease 를 잃은 뒤 항목을 계속 만들었다');
    // 이어 받은 실행(lease 만료 뒤 sweeper) — 빠진 15 건만 생성
    NOW += 10 * MIN;
    await X.notificationJobSweeper({});
    const j2 = F.get('notification_jobs_many/m1');
    assert.strictEqual(j2.status, 'done');
    assert.deepStrictEqual(j2.progress, {total: 25, created: 15, suppressed: 0, skipped: 10, failed: 0, invalid: 0});
    assert.strictEqual(notifCount(), 25);
  });

  test('S-E3 오래 걸리면 lease 갱신 — 소유 유지 시 끝까지 · done', async () => {
    reset();
    F.put('notification_jobs_many/m1', manyJob({items: items(25)}));
    let n = 0;
    F.hooks.beforeCommit = (txId, buf) => {
      if (buf.some((w) => /^users\/[^/]+\/notifications\//.test(w.path)) && ++n === 10) NOW += 4 * MIN;
    };
    const o = await X.srvRunNotificationJobMany('m1');
    F.hooks.beforeCommit = null;
    assert.strictEqual(o, 'done');
    assert.strictEqual(notifCount(), 25);
    assert.ok(F.W.commits.some((c) => c.writes.some((w) => w.path === 'notification_jobs_many/m1' &&
      w.data && w.data.leaseUntil && Object.keys(w.data).length === 1)), 'lease 갱신 쓰기');
  });

  test('S-I 탈퇴 barrier — 그 1건 suppressed · 나머지 생성 · done', async () => {
    reset();
    F.put('account_deletion_tombstones/u1', {uid: 'u1'});
    F.put('notification_jobs_many/m1', manyJob());
    await X.onNotificationJobManyCreated(ev('m1'));
    const j = F.get('notification_jobs_many/m1');
    assert.strictEqual(j.status, 'done');
    assert.deepStrictEqual(j.progress, {total: 3, created: 2, suppressed: 1, skipped: 0, failed: 0, invalid: 0});
    assert.strictEqual(F.get('users/u1/notifications/n1'), undefined);
    assert.strictEqual(notifCount(), 2);
  });

  test('U1 지원 밖 kindVersion·mode·kind — failed(UNSUPPORTED_*) · 알림 0 · done 0', async () => {
    reset();
    F.put('notification_jobs_many/v2', manyJob({kindVersion: 2}));
    F.put('notification_jobs_many/q1', manyJob({mode: 'query', items: undefined, query: {toId: 't1'}}));
    F.put('notification_jobs_many/k1', manyJob({kind: 'direct'}));
    F.put('notification_jobs_many/x1', manyJob({items: 'nope'}));
    for (const id of ['v2', 'q1', 'k1', 'x1']) assert.strictEqual(await X.srvRunNotificationJobMany(id), 'failed', id);
    assert.strictEqual(F.get('notification_jobs_many/v2').lastError, 'UNSUPPORTED_KIND:directMany@2');
    assert.strictEqual(F.get('notification_jobs_many/q1').lastError, 'UNSUPPORTED_MODE:query');
    assert.strictEqual(F.get('notification_jobs_many/k1').lastError, 'UNSUPPORTED_KIND:direct');
    assert.strictEqual(F.get('notification_jobs_many/x1').lastError, 'INVALID_ITEMS:not-array');
    assert.strictEqual(notifCount(), 0);
  });

  test('U2 모양이 틀린 항목(결정적 id 없음 · 경로 문자) — 나머지 생성 · 작업 failed(INVALID_ITEMS) · 재시도 0', async () => {
    reset();
    const it = items(3);
    it.push({recipientUid: 'u9', payload: pl('u9', 9)});
    it.push({recipientUid: 'u8/x', notificationId: 'n8', payload: pl('u8', 8)});
    F.put('notification_jobs_many/m1', manyJob({items: it}));
    await X.onNotificationJobManyCreated(ev('m1')); // throw 0
    const j = F.get('notification_jobs_many/m1');
    assert.strictEqual(j.status, 'failed');
    assert.strictEqual(j.lastError, 'INVALID_ITEMS:2');
    assert.strictEqual(notifCount(), 3);
  });

  test('W1 sweeper — 접수 2분 지난 pending · lease 만료 running 을 새 컬렉션에서도 재구동 · 구 컬렉션도 그대로', async () => {
    reset();
    F.put('notification_jobs_many/m1', manyJob({createdAt: new Ts(NOW - 3 * MIN)}));
    F.put('notification_jobs_many/m2', manyJob({items: items(2, 'k'), status: 'running', leaseToken: 'dead',
      leaseUntil: new Ts(NOW - 1), attempts: 1}));
    F.put('notification_jobs_many/m3', manyJob({items: items(1, 'z'), createdAt: new Ts(NOW - 30 * 1000)})); // 2분 안 = trigger 몫
    F.put('notification_jobs/d1', {kind: 'direct', recipientUid: 'w1', notificationId: 'dn1', payload: pl('w1', 0),
      status: 'pending', attempts: 0, createdAt: new Ts(NOW - 3 * MIN), schemaVersion: 1});
    await X.notificationJobSweeper({});
    assert.strictEqual(F.get('notification_jobs_many/m1').status, 'done');
    assert.strictEqual(F.get('notification_jobs_many/m2').status, 'done');
    assert.strictEqual(F.get('notification_jobs_many/m3').status, 'pending');
    assert.strictEqual(F.get('notification_jobs/d1').status, 'done');
    assert.ok(F.get('users/w1/notifications/dn1'));
    assert.ok(LOGS.some((l) => l === 'notifJobMany consumer v1 ready'));
  });

  test('W2 sweeper — 한 컬렉션 조회 실패가 다른 컬렉션 재구동을 막지 않는다(실패는 끝에 다시 던짐)', async () => {
    reset();
    F.put('notification_jobs_many/m1', manyJob({createdAt: new Ts(NOW - 3 * MIN)}));
    const orig = F.db.collection;
    F.db.collection = (c) => {
      const r = orig(c);
      if (c !== 'notification_jobs') return r;
      return new Proxy(r, {get: (t, k) => (k === 'where' ? () => ({limit: () => ({get: async () => { throw new Error('UNAVAILABLE'); }})}) :
        (typeof t[k] === 'function' ? t[k].bind(t) : t[k]))});
    };
    try {
      await assert.rejects(X.notificationJobSweeper({}), /UNAVAILABLE/);
    } finally { F.db.collection = orig; }
    assert.strictEqual(F.get('notification_jobs_many/m1').status, 'done');
  });

  test('T1 오래된 trigger 이벤트(1시간 초과) — 실행 0 · sweeper 몫', async () => {
    reset();
    F.put('notification_jobs_many/m1', manyJob());
    await X.onNotificationJobManyCreated(ev('m1', 61 * MIN));
    assert.strictEqual(F.get('notification_jobs_many/m1').status, 'pending');
    assert.strictEqual(notifCount(), 0);
  });

  test('P1 producer 0 — 이 판에는 notification_jobs_many 작업을 만드는 코드가 없다', () => {
    const uses = SRC.match(/NOTIF_JOB_MANY_COL/g).length;
    // 선언 1 · trigger 경로 1 · 실행기 1 · sweeper 1
    assert.strictEqual(uses, 4, `NOTIF_JOB_MANY_COL 사용 ${uses}`);
    assert.ok(!/collection\("notification_jobs_many"\)/.test(SRC));
  });
}
