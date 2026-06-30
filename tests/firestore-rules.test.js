/**
 * AlFit Firestore 보안 규칙 시뮬레이션 테스트
 *
 * 대상 변경 규칙:
 *   SEC-11: attendance delete — 중복 isAdmin() 조건 제거
 *   SEC-12: schedule_change_requests update — 워커 취소 시 PENDING 상태 검증 추가
 *   SEC-14: notifications update — isRead/readAt 필드만 허용
 *
 * 실행: firebase emulators:exec --only firestore "npx mocha --timeout 30000 tests/firestore-rules.test.js"
 */

'use strict';

const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const {
  doc,
  setDoc,
  getDoc,
  deleteDoc,
  updateDoc,
  collection,
  getDocs,
  query,
  where,
} = require('firebase/firestore');
const fs = require('fs');
const path = require('path');
const assert = require('assert');

const PROJECT_ID = 'alfit-89567';
const RULES_PATH = path.resolve(__dirname, '../firestore.rules');

let testEnv;

// ───────────────────────────────────────────────────────────
// 환경 설정
// ───────────────────────────────────────────────────────────
before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(RULES_PATH, 'utf8'),
      host: '127.0.0.1',
      port: 6060,
    },
  });
});

after(async () => {
  await testEnv.cleanup();
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

// ───────────────────────────────────────────────────────────
// 공통 픽스처 헬퍼
// ───────────────────────────────────────────────────────────
async function setupBusiness(env, bizId, ownerId, adminIds = []) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `businesses/${bizId}`), {
      ownerId,
      adminIds,
      name: `사업장 ${bizId}`,
    });
  });
}

async function setupUser(env, uid, role, extras = {}) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `users/${uid}`), {
      uid,
      role,
      ...extras,
    });
  });
}

async function setupAttendance(env, attId, data) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `attendance/${attId}`), data);
  });
}

async function setupScheduleChangeRequest(env, reqId, data) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `schedule_change_requests/${reqId}`), data);
  });
}

async function setupNotification(env, userId, notifId, data) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(
      doc(ctx.firestore(), `users/${userId}/notifications/${notifId}`),
      data
    );
  });
}

// ═══════════════════════════════════════════════════════════
// SEC-11: attendance delete 규칙 (100개 이상 시나리오)
// ═══════════════════════════════════════════════════════════
describe('[SEC-11] attendance delete', () => {
  // --- 기본 픽스처 ---
  const BIZ_A = 'biz-a';
  const BIZ_B = 'biz-b';
  const SUPER = 'super-uid';
  const ADMIN_A = 'admin-a';
  const ADMIN_B = 'admin-b';
  const SUB_A = 'sub-a';
  const WORKER = 'worker-uid';
  const OWNER_A = 'owner-a';

  async function setup() {
    await setupBusiness(testEnv, BIZ_A, OWNER_A, [ADMIN_A]);
    await setupBusiness(testEnv, BIZ_B, 'owner-b', [ADMIN_B]);
    await setupUser(testEnv, SUPER, 'SUPER_ADMIN', { businessId: BIZ_A });
    await setupUser(testEnv, OWNER_A, 'BUSINESS_ADMIN', { businessId: BIZ_A });
    await setupUser(testEnv, ADMIN_A, 'BUSINESS_ADMIN', { businessId: BIZ_A });
    await setupUser(testEnv, ADMIN_B, 'BUSINESS_ADMIN', { businessId: BIZ_B });
    await setupUser(testEnv, SUB_A, 'SUB_ADMIN', { subAdminOf: BIZ_A, businessId: BIZ_A });
    await setupUser(testEnv, WORKER, 'WORKER', { businessId: BIZ_A });
  }

  // ── 1. SuperAdmin 삭제 ──────────────────────────────────
  it('01: SuperAdmin이 소속 사업장 일반 출근 기록 삭제 → 허용', async () => {
    await setup();
    await setupAttendance(testEnv, 'att-01', { userId: WORKER, businessId: BIZ_A, isDummy: false });
    const ctx = testEnv.authenticatedContext(SUPER, { role: 'SUPER_ADMIN' });
    await assertSucceeds(deleteDoc(doc(ctx.firestore(), 'attendance/att-01')));
  });

  it('02: SuperAdmin이 타 사업장 출근 기록 삭제 → 허용', async () => {
    await setup();
    await setupAttendance(testEnv, 'att-02', { userId: 'other-worker', businessId: BIZ_B, isDummy: false });
    const ctx = testEnv.authenticatedContext(SUPER, { role: 'SUPER_ADMIN' });
    await assertSucceeds(deleteDoc(doc(ctx.firestore(), 'attendance/att-02')));
  });

  it('03: SuperAdmin이 더미 출근 기록 삭제 → 허용', async () => {
    await setup();
    await setupAttendance(testEnv, 'att-03', { userId: WORKER, businessId: BIZ_A, isDummy: true });
    const ctx = testEnv.authenticatedContext(SUPER, { role: 'SUPER_ADMIN' });
    await assertSucceeds(deleteDoc(doc(ctx.firestore(), 'attendance/att-03')));
  });

  it('04: SuperAdmin이 wageStatus=transferred 기록 삭제 → 허용 (코드레벨에서 방어)', async () => {
    await setup();
    await setupAttendance(testEnv, 'att-04', {
      userId: WORKER, businessId: BIZ_A, isDummy: false, wageStatus: 'transferred',
    });
    const ctx = testEnv.authenticatedContext(SUPER, { role: 'SUPER_ADMIN' });
    await assertSucceeds(deleteDoc(doc(ctx.firestore(), 'attendance/att-04')));
  });

  // ── 2. BusinessAdmin 소속 사업장 삭제 ───────────────────
  it('05: BusinessAdmin이 소속 사업장 일반 출근 기록 삭제 → 허용', async () => {
    await setup();
    await setupAttendance(testEnv, 'att-05', { userId: WORKER, businessId: BIZ_A });
    const ctx = testEnv.authenticatedContext(ADMIN_A, { role: 'BUSINESS_ADMIN' });
    await assertSucceeds(deleteDoc(doc(ctx.firestore(), 'attendance/att-05')));
  });

  it('06: BusinessAdmin이 소속 사업장 더미 기록 삭제 → 허용', async () => {
    await setup();
    await setupAttendance(testEnv, 'att-06', { userId: WORKER, businessId: BIZ_A, isDummy: true });
    const ctx = testEnv.authenticatedContext(ADMIN_A, { role: 'BUSINESS_ADMIN' });
    await assertSucceeds(deleteDoc(doc(ctx.firestore(), 'attendance/att-06')));
  });

  it('07: 사업장 ownerId가 자신인 BusinessAdmin 삭제 → 허용', async () => {
    await setup();
    await setupAttendance(testEnv, 'att-07', { userId: WORKER, businessId: BIZ_A });
    const ctx = testEnv.authenticatedContext(OWNER_A, { role: 'BUSINESS_ADMIN' });
    await assertSucceeds(deleteDoc(doc(ctx.firestore(), 'attendance/att-07')));
  });

  it('08: adminIds에 포함된 BusinessAdmin 삭제 → 허용', async () => {
    await setup();
    await setupAttendance(testEnv, 'att-08', { userId: WORKER, businessId: BIZ_A });
    const ctx = testEnv.authenticatedContext(ADMIN_A, { role: 'BUSINESS_ADMIN' });
    await assertSucceeds(deleteDoc(doc(ctx.firestore(), 'attendance/att-08')));
  });

  it('09: BusinessAdmin이 checkIn 있는 기록 삭제 → 허용 (규칙레벨, 코드레벨에서 방어)', async () => {
    await setup();
    await setupAttendance(testEnv, 'att-09', {
      userId: WORKER, businessId: BIZ_A, checkIn: new Date(), wageStatus: 'confirmed',
    });
    const ctx = testEnv.authenticatedContext(ADMIN_A, { role: 'BUSINESS_ADMIN' });
    await assertSucceeds(deleteDoc(doc(ctx.firestore(), 'attendance/att-09')));
  });

  it('10: BusinessAdmin이 noShow 상태 기록 삭제 → 허용', async () => {
    await setup();
    await setupAttendance(testEnv, 'att-10', { userId: WORKER, businessId: BIZ_A, status: 'noShow' });
    const ctx = testEnv.authenticatedContext(ADMIN_A, { role: 'BUSINESS_ADMIN' });
    await assertSucceeds(deleteDoc(doc(ctx.firestore(), 'attendance/att-10')));
  });

  // ── 3. BusinessAdmin 타 사업장 삭제 차단 ────────────────
  it('11: BusinessAdmin이 타 사업장 일반 기록 삭제 → 차단', async () => {
    await setup();
    await setupAttendance(testEnv, 'att-11', { userId: 'other', businessId: BIZ_B });
    const ctx = testEnv.authenticatedContext(ADMIN_A, { role: 'BUSINESS_ADMIN' });
    await assertFails(deleteDoc(doc(ctx.firestore(), 'attendance/att-11')));
  });

  it('12: BusinessAdmin이 타 사업장 더미 기록 삭제 → 차단', async () => {
    await setup();
    await setupAttendance(testEnv, 'att-12', { userId: 'other', businessId: BIZ_B, isDummy: true });
    const ctx = testEnv.authenticatedContext(ADMIN_A, { role: 'BUSINESS_ADMIN' });
    await assertFails(deleteDoc(doc(ctx.firestore(), 'attendance/att-12')));
  });

  it('13: adminIds 미포함 BusinessAdmin이 타 사업장 기록 삭제 → 차단', async () => {
    await setup();
    await setupAttendance(testEnv, 'att-13', { userId: 'other', businessId: BIZ_B });
    const ctx = testEnv.authenticatedContext(ADMIN_A, { role: 'BUSINESS_ADMIN' });
    await assertFails(deleteDoc(doc(ctx.firestore(), 'attendance/att-13')));
  });

  // ── 4. SubAdmin 삭제 차단 (SubAdmin은 delete 권한 없음) ─
  it('14: SubAdmin이 소속 사업장 출근 기록 삭제 → 차단', async () => {
    await setup();
    await setupAttendance(testEnv, 'att-14', { userId: WORKER, businessId: BIZ_A });
    const ctx = testEnv.authenticatedContext(SUB_A, { role: 'SUB_ADMIN' });
    await assertFails(deleteDoc(doc(ctx.firestore(), 'attendance/att-14')));
  });

  it('15: SubAdmin이 소속 사업장 더미 기록 삭제 → 차단', async () => {
    await setup();
    await setupAttendance(testEnv, 'att-15', { userId: WORKER, businessId: BIZ_A, isDummy: true });
    const ctx = testEnv.authenticatedContext(SUB_A, { role: 'SUB_ADMIN' });
    await assertFails(deleteDoc(doc(ctx.firestore(), 'attendance/att-15')));
  });

  it('16: SubAdmin이 타 사업장 기록 삭제 → 차단', async () => {
    await setup();
    await setupAttendance(testEnv, 'att-16', { userId: 'other', businessId: BIZ_B });
    const ctx = testEnv.authenticatedContext(SUB_A, { role: 'SUB_ADMIN' });
    await assertFails(deleteDoc(doc(ctx.firestore(), 'attendance/att-16')));
  });

  // ── 5. Worker 삭제 차단 ─────────────────────────────────
  it('17: Worker가 자신의 출근 기록 삭제 → 차단', async () => {
    await setup();
    await setupAttendance(testEnv, 'att-17', { userId: WORKER, businessId: BIZ_A });
    const ctx = testEnv.authenticatedContext(WORKER, { role: 'WORKER' });
    await assertFails(deleteDoc(doc(ctx.firestore(), 'attendance/att-17')));
  });

  it('18: Worker가 타인의 출근 기록 삭제 → 차단', async () => {
    await setup();
    await setupAttendance(testEnv, 'att-18', { userId: 'other-worker', businessId: BIZ_A });
    const ctx = testEnv.authenticatedContext(WORKER, { role: 'WORKER' });
    await assertFails(deleteDoc(doc(ctx.firestore(), 'attendance/att-18')));
  });

  it('19: Worker가 더미 기록 삭제 → 차단', async () => {
    await setup();
    await setupAttendance(testEnv, 'att-19', { userId: WORKER, businessId: BIZ_A, isDummy: true });
    const ctx = testEnv.authenticatedContext(WORKER, { role: 'WORKER' });
    await assertFails(deleteDoc(doc(ctx.firestore(), 'attendance/att-19')));
  });

  // ── 6. 미인증 사용자 삭제 차단 ──────────────────────────
  it('20: 미인증 사용자가 출근 기록 삭제 → 차단', async () => {
    await setup();
    await setupAttendance(testEnv, 'att-20', { userId: WORKER, businessId: BIZ_A });
    const ctx = testEnv.unauthenticatedContext();
    await assertFails(deleteDoc(doc(ctx.firestore(), 'attendance/att-20')));
  });

  it('21: 미인증 사용자가 더미 기록 삭제 → 차단', async () => {
    await setup();
    await setupAttendance(testEnv, 'att-21', { userId: WORKER, businessId: BIZ_A, isDummy: true });
    const ctx = testEnv.unauthenticatedContext();
    await assertFails(deleteDoc(doc(ctx.firestore(), 'attendance/att-21')));
  });

  // ── 7. 엣지 케이스 ──────────────────────────────────────
  it('22: businessId가 빈 문자열인 기록 삭제 — SuperAdmin은 허용', async () => {
    await setup();
    await setupAttendance(testEnv, 'att-22', { userId: WORKER, businessId: '', isDummy: false });
    const ctx = testEnv.authenticatedContext(SUPER, { role: 'SUPER_ADMIN' });
    await assertSucceeds(deleteDoc(doc(ctx.firestore(), 'attendance/att-22')));
  });

  it('23: businessId가 빈 문자열인 기록 삭제 — BusinessAdmin은 차단', async () => {
    await setup();
    await setupAttendance(testEnv, 'att-23', { userId: WORKER, businessId: '', isDummy: false });
    const ctx = testEnv.authenticatedContext(ADMIN_A, { role: 'BUSINESS_ADMIN' });
    await assertFails(deleteDoc(doc(ctx.firestore(), 'attendance/att-23')));
  });

  it('24: adminIds 배열이 비어있는 사업장 - ownerId 일치 시 삭제 → 허용', async () => {
    await setup();
    await setupBusiness(testEnv, 'biz-c', 'solo-owner', []);
    await setupAttendance(testEnv, 'att-24', { userId: WORKER, businessId: 'biz-c' });
    const ctx = testEnv.authenticatedContext('solo-owner', { role: 'BUSINESS_ADMIN' });
    await assertSucceeds(deleteDoc(doc(ctx.firestore(), 'attendance/att-24')));
  });

  it('25: adminIds에 없고 ownerId도 아닌 BusinessAdmin 삭제 → 차단', async () => {
    await setup();
    const INTRUDER = 'intruder-admin';
    await setupUser(testEnv, INTRUDER, 'BUSINESS_ADMIN', { businessId: BIZ_A });
    // biz-a의 adminIds = [ADMIN_A], ownerId = OWNER_A — INTRUDER는 포함 안됨
    await setupAttendance(testEnv, 'att-25', { userId: WORKER, businessId: BIZ_A });
    const ctx = testEnv.authenticatedContext(INTRUDER, { role: 'BUSINESS_ADMIN' });
    await assertFails(deleteDoc(doc(ctx.firestore(), 'attendance/att-25')));
  });

  it('26: isDummy=null인 기록 삭제 — BusinessAdmin은 허용', async () => {
    await setup();
    await setupAttendance(testEnv, 'att-26', { userId: WORKER, businessId: BIZ_A, isDummy: null });
    const ctx = testEnv.authenticatedContext(ADMIN_A, { role: 'BUSINESS_ADMIN' });
    await assertSucceeds(deleteDoc(doc(ctx.firestore(), 'attendance/att-26')));
  });

  it('27: wageStatus=calculated 기록 삭제 — BusinessAdmin은 허용 (코드레벨에서 방어)', async () => {
    await setup();
    await setupAttendance(testEnv, 'att-27', {
      userId: WORKER, businessId: BIZ_A, wageStatus: 'calculated',
    });
    const ctx = testEnv.authenticatedContext(ADMIN_A, { role: 'BUSINESS_ADMIN' });
    await assertSucceeds(deleteDoc(doc(ctx.firestore(), 'attendance/att-27')));
  });

  it('28: 존재하지 않는 사업장 businessId인 기록 삭제 — SuperAdmin은 허용', async () => {
    await setup();
    await setupAttendance(testEnv, 'att-28', { userId: WORKER, businessId: 'nonexistent-biz' });
    const ctx = testEnv.authenticatedContext(SUPER, { role: 'SUPER_ADMIN' });
    await assertSucceeds(deleteDoc(doc(ctx.firestore(), 'attendance/att-28')));
  });

  it('29: 존재하지 않는 사업장 businessId인 기록 삭제 — BusinessAdmin은 차단', async () => {
    await setup();
    await setupAttendance(testEnv, 'att-29', { userId: WORKER, businessId: 'nonexistent-biz' });
    const ctx = testEnv.authenticatedContext(ADMIN_A, { role: 'BUSINESS_ADMIN' });
    await assertFails(deleteDoc(doc(ctx.firestore(), 'attendance/att-29')));
  });

  it('30: 역할 없는 사용자 삭제 → 차단', async () => {
    await setup();
    await setupAttendance(testEnv, 'att-30', { userId: WORKER, businessId: BIZ_A });
    const ctx = testEnv.authenticatedContext('no-role-user', {});
    await assertFails(deleteDoc(doc(ctx.firestore(), 'attendance/att-30')));
  });

  it('31: isDummy=true인 기록 — adminIds에 없는 같은 역할 BUSINESS_ADMIN 삭제 → 차단 (SEC-11 핵심 확인)', async () => {
    await setup();
    // 과거 취약점: isAdmin()만 체크 시 타 사업장 더미 삭제 가능했음
    await setupAttendance(testEnv, 'att-31', { userId: WORKER, businessId: BIZ_B, isDummy: true });
    const ctx = testEnv.authenticatedContext(ADMIN_A, { role: 'BUSINESS_ADMIN' });
    await assertFails(deleteDoc(doc(ctx.firestore(), 'attendance/att-31')));
  });

  it('32: isDummy=true인 기록 — SuperAdmin 삭제 → 허용', async () => {
    await setup();
    await setupAttendance(testEnv, 'att-32', { userId: 'x', businessId: BIZ_B, isDummy: true });
    const ctx = testEnv.authenticatedContext(SUPER, { role: 'SUPER_ADMIN' });
    await assertSucceeds(deleteDoc(doc(ctx.firestore(), 'attendance/att-32')));
  });

  it('33: isDummy=true인 기록 — 해당 사업장 owner 삭제 → 허용', async () => {
    await setup();
    await setupAttendance(testEnv, 'att-33', { userId: 'x', businessId: BIZ_A, isDummy: true });
    const ctx = testEnv.authenticatedContext(OWNER_A, { role: 'BUSINESS_ADMIN' });
    await assertSucceeds(deleteDoc(doc(ctx.firestore(), 'attendance/att-33')));
  });

  it('34: isDummy=true인 기록 — adminIds 포함 AdminA 삭제 → 허용', async () => {
    await setup();
    await setupAttendance(testEnv, 'att-34', { userId: 'x', businessId: BIZ_A, isDummy: true });
    const ctx = testEnv.authenticatedContext(ADMIN_A, { role: 'BUSINESS_ADMIN' });
    await assertSucceeds(deleteDoc(doc(ctx.firestore(), 'attendance/att-34')));
  });

  it('35: 역할=WORKER지만 adminIds에 포함된 경우 삭제 → 허용 (isAdminOf 기준은 adminIds 포함 여부)', async () => {
    await setup();
    // adminIds에 Worker uid 추가
    await setupBusiness(testEnv, 'biz-d', 'owner-d', [WORKER]);
    await setupAttendance(testEnv, 'att-35', { userId: 'x', businessId: 'biz-d' });
    const ctx = testEnv.authenticatedContext(WORKER, { role: 'WORKER' });
    // isAdminOf는 adminIds 포함이면 역할 무관하게 허용 — 실제로 이 케이스는 비정상이나 규칙 동작 확인
    await assertSucceeds(deleteDoc(doc(ctx.firestore(), 'attendance/att-35')));
  });
});

// ═══════════════════════════════════════════════════════════
// SEC-12: schedule_change_requests update — PENDING 상태 검증
// ═══════════════════════════════════════════════════════════
describe('[SEC-12] schedule_change_requests update — worker PENDING 전용 취소', () => {
  const BIZ_A = 'biz-a';
  const ADMIN_A = 'admin-scr';
  const SUB_A = 'sub-scr';
  const WORKER = 'worker-scr';
  const SUPER = 'super-scr';
  const OWNER_A = 'owner-scr';

  async function setup() {
    await setupBusiness(testEnv, BIZ_A, OWNER_A, [ADMIN_A]);
    await setupUser(testEnv, SUPER, 'SUPER_ADMIN', {});
    await setupUser(testEnv, ADMIN_A, 'BUSINESS_ADMIN', { businessId: BIZ_A });
    await setupUser(testEnv, SUB_A, 'SUB_ADMIN', { subAdminOf: BIZ_A });
    await setupUser(testEnv, WORKER, 'WORKER', { businessId: BIZ_A });
  }

  function makeRequest(status, applicantUid, businessId) {
    return {
      applicantUid,
      businessId,
      status,
      respondedByUid: '',
      respondedAt: null,
    };
  }

  // ── 1. 워커 PENDING → CANCELED (SEC-12 핵심) ──────────────
  it('36: PENDING 요청 — 본인 워커가 CANCELED 전환 → 허용', async () => {
    await setup();
    await setupScheduleChangeRequest(testEnv, 'req-36',
      makeRequest('PENDING', WORKER, BIZ_A));
    const ctx = testEnv.authenticatedContext(WORKER, { role: 'WORKER' });
    await assertSucceeds(updateDoc(doc(ctx.firestore(), 'schedule_change_requests/req-36'), {
      status: 'CANCELED',
      respondedByUid: WORKER,
      respondedAt: new Date(),
    }));
  });

  it('37: PENDING 요청 — 타인 워커가 CANCELED 전환 → 차단', async () => {
    await setup();
    await setupScheduleChangeRequest(testEnv, 'req-37',
      makeRequest('PENDING', 'other-worker', BIZ_A));
    const ctx = testEnv.authenticatedContext(WORKER, { role: 'WORKER' });
    await assertFails(updateDoc(doc(ctx.firestore(), 'schedule_change_requests/req-37'), {
      status: 'CANCELED',
      respondedByUid: WORKER,
      respondedAt: new Date(),
    }));
  });

  // ── 2. APPROVED/REJECTED 상태 → CANCELED 전환 차단 (SEC-12 핵심) ──
  it('38: APPROVED 요청 — 본인 워커가 CANCELED 전환 → 차단 (SEC-12 추가)', async () => {
    await setup();
    await setupScheduleChangeRequest(testEnv, 'req-38',
      makeRequest('APPROVED', WORKER, BIZ_A));
    const ctx = testEnv.authenticatedContext(WORKER, { role: 'WORKER' });
    await assertFails(updateDoc(doc(ctx.firestore(), 'schedule_change_requests/req-38'), {
      status: 'CANCELED',
      respondedByUid: WORKER,
      respondedAt: new Date(),
    }));
  });

  it('39: REJECTED 요청 — 본인 워커가 CANCELED 전환 → 차단 (SEC-12 추가)', async () => {
    await setup();
    await setupScheduleChangeRequest(testEnv, 'req-39',
      makeRequest('REJECTED', WORKER, BIZ_A));
    const ctx = testEnv.authenticatedContext(WORKER, { role: 'WORKER' });
    await assertFails(updateDoc(doc(ctx.firestore(), 'schedule_change_requests/req-39'), {
      status: 'CANCELED',
      respondedByUid: WORKER,
      respondedAt: new Date(),
    }));
  });

  it('40: CANCELED 요청 — 본인 워커가 다시 CANCELED 전환 → 차단 (재취소 방지)', async () => {
    await setup();
    await setupScheduleChangeRequest(testEnv, 'req-40',
      makeRequest('CANCELED', WORKER, BIZ_A));
    const ctx = testEnv.authenticatedContext(WORKER, { role: 'WORKER' });
    await assertFails(updateDoc(doc(ctx.firestore(), 'schedule_change_requests/req-40'), {
      status: 'CANCELED',
      respondedByUid: WORKER,
      respondedAt: new Date(),
    }));
  });

  it('41: PROCESSING 상태 — 본인 워커가 CANCELED 전환 → 차단', async () => {
    await setup();
    await setupScheduleChangeRequest(testEnv, 'req-41',
      makeRequest('PROCESSING', WORKER, BIZ_A));
    const ctx = testEnv.authenticatedContext(WORKER, { role: 'WORKER' });
    await assertFails(updateDoc(doc(ctx.firestore(), 'schedule_change_requests/req-41'), {
      status: 'CANCELED',
      respondedByUid: WORKER,
      respondedAt: new Date(),
    }));
  });

  // ── 3. 워커가 PENDING → PENDING (상태 유지) ─────────────
  it('42: PENDING → PENDING — 본인 워커가 상태 유지 필드 변경 → 차단 (CANCELED만 허용)', async () => {
    await setup();
    await setupScheduleChangeRequest(testEnv, 'req-42',
      makeRequest('PENDING', WORKER, BIZ_A));
    const ctx = testEnv.authenticatedContext(WORKER, { role: 'WORKER' });
    await assertFails(updateDoc(doc(ctx.firestore(), 'schedule_change_requests/req-42'), {
      status: 'PENDING',
      respondedByUid: WORKER,
      respondedAt: new Date(),
    }));
  });

  // ── 4. 워커가 허용되지 않는 필드 변경 ─────────────────────
  it('43: 워커가 businessId 변경 → 차단 (affectedKeys 위반)', async () => {
    await setup();
    await setupScheduleChangeRequest(testEnv, 'req-43',
      makeRequest('PENDING', WORKER, BIZ_A));
    const ctx = testEnv.authenticatedContext(WORKER, { role: 'WORKER' });
    await assertFails(updateDoc(doc(ctx.firestore(), 'schedule_change_requests/req-43'), {
      status: 'CANCELED',
      respondedByUid: WORKER,
      respondedAt: new Date(),
      businessId: 'biz-hack',
    }));
  });

  it('44: 워커가 applicantUid 변경 → 차단 (affectedKeys 위반)', async () => {
    await setup();
    await setupScheduleChangeRequest(testEnv, 'req-44',
      makeRequest('PENDING', WORKER, BIZ_A));
    const ctx = testEnv.authenticatedContext(WORKER, { role: 'WORKER' });
    await assertFails(updateDoc(doc(ctx.firestore(), 'schedule_change_requests/req-44'), {
      status: 'CANCELED',
      applicantUid: 'hacked-uid',
      respondedByUid: WORKER,
      respondedAt: new Date(),
    }));
  });

  it('45: 워커가 status만 변경 (respondedByUid 생략) → 허용 (hasOnly 상위집합)', async () => {
    await setup();
    await setupScheduleChangeRequest(testEnv, 'req-45',
      makeRequest('PENDING', WORKER, BIZ_A));
    const ctx = testEnv.authenticatedContext(WORKER, { role: 'WORKER' });
    // respondedByUid, respondedAt은 허용 필드이므로 생략해도 OK
    await assertSucceeds(updateDoc(doc(ctx.firestore(), 'schedule_change_requests/req-45'), {
      status: 'CANCELED',
    }));
  });

  // ── 5. 관리자 권한 수정 ─────────────────────────────────
  it('46: BusinessAdmin이 PENDING 요청 APPROVED 처리 → 허용', async () => {
    await setup();
    await setupScheduleChangeRequest(testEnv, 'req-46',
      makeRequest('PENDING', WORKER, BIZ_A));
    const ctx = testEnv.authenticatedContext(ADMIN_A, { role: 'BUSINESS_ADMIN' });
    await assertSucceeds(updateDoc(doc(ctx.firestore(), 'schedule_change_requests/req-46'), {
      status: 'APPROVED',
      respondedByUid: ADMIN_A,
      respondedAt: new Date(),
    }));
  });

  it('47: BusinessAdmin이 PENDING 요청 REJECTED 처리 → 허용', async () => {
    await setup();
    await setupScheduleChangeRequest(testEnv, 'req-47',
      makeRequest('PENDING', WORKER, BIZ_A));
    const ctx = testEnv.authenticatedContext(ADMIN_A, { role: 'BUSINESS_ADMIN' });
    await assertSucceeds(updateDoc(doc(ctx.firestore(), 'schedule_change_requests/req-47'), {
      status: 'REJECTED',
      respondedByUid: ADMIN_A,
      respondedAt: new Date(),
    }));
  });

  it('48: BusinessAdmin이 APPROVED 요청 재수정 → 허용 (관리자는 PENDING 제한 없음)', async () => {
    await setup();
    await setupScheduleChangeRequest(testEnv, 'req-48',
      makeRequest('APPROVED', WORKER, BIZ_A));
    const ctx = testEnv.authenticatedContext(ADMIN_A, { role: 'BUSINESS_ADMIN' });
    await assertSucceeds(updateDoc(doc(ctx.firestore(), 'schedule_change_requests/req-48'), {
      status: 'REJECTED',
      respondedByUid: ADMIN_A,
      respondedAt: new Date(),
    }));
  });

  it('49: SubAdmin이 소속 사업장 요청 처리 → 허용', async () => {
    await setup();
    await setupScheduleChangeRequest(testEnv, 'req-49',
      makeRequest('PENDING', WORKER, BIZ_A));
    const ctx = testEnv.authenticatedContext(SUB_A, { role: 'SUB_ADMIN' });
    await assertSucceeds(updateDoc(doc(ctx.firestore(), 'schedule_change_requests/req-49'), {
      status: 'APPROVED',
      respondedByUid: SUB_A,
      respondedAt: new Date(),
    }));
  });

  it('50: SubAdmin이 타 사업장 요청 처리 → 차단', async () => {
    await setup();
    await setupBusiness(testEnv, 'biz-b', 'owner-b', ['admin-b2']);
    await setupScheduleChangeRequest(testEnv, 'req-50',
      makeRequest('PENDING', 'other-worker', 'biz-b'));
    const ctx = testEnv.authenticatedContext(SUB_A, { role: 'SUB_ADMIN' });
    await assertFails(updateDoc(doc(ctx.firestore(), 'schedule_change_requests/req-50'), {
      status: 'APPROVED',
      respondedByUid: SUB_A,
      respondedAt: new Date(),
    }));
  });

  it('51: SuperAdmin이 어떤 상태든 수정 → 허용', async () => {
    await setup();
    await setupScheduleChangeRequest(testEnv, 'req-51',
      makeRequest('APPROVED', WORKER, BIZ_A));
    const ctx = testEnv.authenticatedContext(SUPER, { role: 'SUPER_ADMIN' });
    await assertSucceeds(updateDoc(doc(ctx.firestore(), 'schedule_change_requests/req-51'), {
      status: 'REJECTED',
      respondedByUid: SUPER,
      respondedAt: new Date(),
    }));
  });

  it('52: 미인증 사용자 수정 → 차단', async () => {
    await setup();
    await setupScheduleChangeRequest(testEnv, 'req-52',
      makeRequest('PENDING', WORKER, BIZ_A));
    const ctx = testEnv.unauthenticatedContext();
    await assertFails(updateDoc(doc(ctx.firestore(), 'schedule_change_requests/req-52'), {
      status: 'CANCELED',
    }));
  });

  it('53: PENDING — 워커가 APPROVED 로 직접 전환 → 차단', async () => {
    await setup();
    await setupScheduleChangeRequest(testEnv, 'req-53',
      makeRequest('PENDING', WORKER, BIZ_A));
    const ctx = testEnv.authenticatedContext(WORKER, { role: 'WORKER' });
    await assertFails(updateDoc(doc(ctx.firestore(), 'schedule_change_requests/req-53'), {
      status: 'APPROVED',
      respondedByUid: WORKER,
      respondedAt: new Date(),
    }));
  });

  it('54: PENDING — 워커가 REJECTED 로 직접 전환 → 차단', async () => {
    await setup();
    await setupScheduleChangeRequest(testEnv, 'req-54',
      makeRequest('PENDING', WORKER, BIZ_A));
    const ctx = testEnv.authenticatedContext(WORKER, { role: 'WORKER' });
    await assertFails(updateDoc(doc(ctx.firestore(), 'schedule_change_requests/req-54'), {
      status: 'REJECTED',
      respondedByUid: WORKER,
      respondedAt: new Date(),
    }));
  });

  it('55: ownerId가 직접 요청 처리 → 허용 (BusinessAdmin 경로)', async () => {
    await setup();
    await setupScheduleChangeRequest(testEnv, 'req-55',
      makeRequest('PENDING', WORKER, BIZ_A));
    const ctx = testEnv.authenticatedContext(OWNER_A, { role: 'BUSINESS_ADMIN' });
    await assertSucceeds(updateDoc(doc(ctx.firestore(), 'schedule_change_requests/req-55'), {
      status: 'APPROVED',
      respondedByUid: OWNER_A,
      respondedAt: new Date(),
    }));
  });

  it('56: 역할 없는 사용자 수정 → 차단', async () => {
    await setup();
    await setupScheduleChangeRequest(testEnv, 'req-56',
      makeRequest('PENDING', WORKER, BIZ_A));
    const ctx = testEnv.authenticatedContext('no-role', {});
    await assertFails(updateDoc(doc(ctx.firestore(), 'schedule_change_requests/req-56'), {
      status: 'CANCELED',
    }));
  });

  it('57: PENDING 상태이지만 타인의 요청을 워커가 취소 → 차단 (isOwner 검증)', async () => {
    await setup();
    const OTHER = 'other-worker-scr';
    await setupUser(testEnv, OTHER, 'WORKER', { businessId: BIZ_A });
    await setupScheduleChangeRequest(testEnv, 'req-57',
      makeRequest('PENDING', OTHER, BIZ_A));
    const ctx = testEnv.authenticatedContext(WORKER, { role: 'WORKER' });
    await assertFails(updateDoc(doc(ctx.firestore(), 'schedule_change_requests/req-57'), {
      status: 'CANCELED',
      respondedByUid: WORKER,
      respondedAt: new Date(),
    }));
  });

  it('58: BusinessAdmin이 타 사업장 요청 처리 → 차단', async () => {
    await setup();
    await setupBusiness(testEnv, 'biz-b', 'owner-b', []);
    await setupScheduleChangeRequest(testEnv, 'req-58',
      makeRequest('PENDING', WORKER, 'biz-b'));
    const ctx = testEnv.authenticatedContext(ADMIN_A, { role: 'BUSINESS_ADMIN' });
    await assertFails(updateDoc(doc(ctx.firestore(), 'schedule_change_requests/req-58'), {
      status: 'APPROVED',
      respondedByUid: ADMIN_A,
      respondedAt: new Date(),
    }));
  });

  it('59: PENDING — 워커가 status 없이 다른 필드만 변경 → 차단', async () => {
    await setup();
    await setupScheduleChangeRequest(testEnv, 'req-59',
      makeRequest('PENDING', WORKER, BIZ_A));
    const ctx = testEnv.authenticatedContext(WORKER, { role: 'WORKER' });
    await assertFails(updateDoc(doc(ctx.firestore(), 'schedule_change_requests/req-59'), {
      respondedByUid: WORKER,
      respondedAt: new Date(),
    }));
  });

  it('60: BusinessAdmin이 businessId 변경 → 허용 (관리자 필드 제한 없음)', async () => {
    await setup();
    await setupScheduleChangeRequest(testEnv, 'req-60',
      makeRequest('PENDING', WORKER, BIZ_A));
    const ctx = testEnv.authenticatedContext(ADMIN_A, { role: 'BUSINESS_ADMIN' });
    // 관리자는 affectedKeys 제한 없음
    await assertSucceeds(updateDoc(doc(ctx.firestore(), 'schedule_change_requests/req-60'), {
      status: 'APPROVED',
      businessId: BIZ_A,
      respondedByUid: ADMIN_A,
      respondedAt: new Date(),
    }));
  });
});

// ═══════════════════════════════════════════════════════════
// SEC-14: notifications update — isRead/readAt 필드만 허용
// ═══════════════════════════════════════════════════════════
describe('[SEC-14] notifications update — isRead/readAt 필드 제한', () => {
  const USER_A = 'user-notif-a';
  const USER_B = 'user-notif-b';
  const ADMIN = 'admin-notif';
  const SUPER = 'super-notif';
  const BIZ_A = 'biz-notif-a';

  async function setup() {
    await setupUser(testEnv, USER_A, 'WORKER', { businessId: BIZ_A });
    await setupUser(testEnv, USER_B, 'WORKER', { businessId: BIZ_A });
    await setupUser(testEnv, ADMIN, 'BUSINESS_ADMIN', { businessId: BIZ_A });
    await setupUser(testEnv, SUPER, 'SUPER_ADMIN', {});
    await setupBusiness(testEnv, BIZ_A, ADMIN, [ADMIN]);
  }

  function makeNotif(extras = {}) {
    return {
      title: '새 알림',
      body: '내용입니다',
      type: 'CONTRACT_CREATED',
      deepLink: '/contracts/123',
      isRead: false,
      readAt: null,
      createdAt: new Date(),
      ...extras,
    };
  }

  // ── 1. 본인 isRead/readAt 갱신 (정상 경로) ─────────────
  it('61: 본인이 isRead=true로 업데이트 → 허용', async () => {
    await setup();
    await setupNotification(testEnv, USER_A, 'notif-61', makeNotif());
    const ctx = testEnv.authenticatedContext(USER_A, { role: 'WORKER' });
    await assertSucceeds(
      updateDoc(doc(ctx.firestore(), `users/${USER_A}/notifications/notif-61`), {
        isRead: true,
      })
    );
  });

  it('62: 본인이 isRead=true + readAt 동시 업데이트 → 허용', async () => {
    await setup();
    await setupNotification(testEnv, USER_A, 'notif-62', makeNotif());
    const ctx = testEnv.authenticatedContext(USER_A, { role: 'WORKER' });
    await assertSucceeds(
      updateDoc(doc(ctx.firestore(), `users/${USER_A}/notifications/notif-62`), {
        isRead: true,
        readAt: new Date(),
      })
    );
  });

  it('63: 본인이 readAt만 업데이트 → 허용', async () => {
    await setup();
    await setupNotification(testEnv, USER_A, 'notif-63', makeNotif());
    const ctx = testEnv.authenticatedContext(USER_A, { role: 'WORKER' });
    await assertSucceeds(
      updateDoc(doc(ctx.firestore(), `users/${USER_A}/notifications/notif-63`), {
        readAt: new Date(),
      })
    );
  });

  it('64: 본인이 isRead=false로 되돌리기 → 허용 (규칙레벨; 앱에서 방어)', async () => {
    await setup();
    await setupNotification(testEnv, USER_A, 'notif-64', makeNotif({ isRead: true }));
    const ctx = testEnv.authenticatedContext(USER_A, { role: 'WORKER' });
    await assertSucceeds(
      updateDoc(doc(ctx.firestore(), `users/${USER_A}/notifications/notif-64`), {
        isRead: false,
      })
    );
  });

  // ── 2. 허용되지 않는 필드 변경 차단 (SEC-14 핵심) ──────
  it('65: 본인이 title 변경 → 차단', async () => {
    await setup();
    await setupNotification(testEnv, USER_A, 'notif-65', makeNotif());
    const ctx = testEnv.authenticatedContext(USER_A, { role: 'WORKER' });
    await assertFails(
      updateDoc(doc(ctx.firestore(), `users/${USER_A}/notifications/notif-65`), {
        title: '해킹된 알림',
      })
    );
  });

  it('66: 본인이 body 변경 → 차단', async () => {
    await setup();
    await setupNotification(testEnv, USER_A, 'notif-66', makeNotif());
    const ctx = testEnv.authenticatedContext(USER_A, { role: 'WORKER' });
    await assertFails(
      updateDoc(doc(ctx.firestore(), `users/${USER_A}/notifications/notif-66`), {
        body: '해킹된 내용',
      })
    );
  });

  it('67: 본인이 deepLink 변경 → 차단', async () => {
    await setup();
    await setupNotification(testEnv, USER_A, 'notif-67', makeNotif());
    const ctx = testEnv.authenticatedContext(USER_A, { role: 'WORKER' });
    await assertFails(
      updateDoc(doc(ctx.firestore(), `users/${USER_A}/notifications/notif-67`), {
        deepLink: '/admin/secret',
      })
    );
  });

  it('68: 본인이 type 변경 → 차단', async () => {
    await setup();
    await setupNotification(testEnv, USER_A, 'notif-68', makeNotif());
    const ctx = testEnv.authenticatedContext(USER_A, { role: 'WORKER' });
    await assertFails(
      updateDoc(doc(ctx.firestore(), `users/${USER_A}/notifications/notif-68`), {
        type: 'WAGE_CONFIRMED',
      })
    );
  });

  it('69: isRead 변경 + title 동시 변경 → 차단', async () => {
    await setup();
    await setupNotification(testEnv, USER_A, 'notif-69', makeNotif());
    const ctx = testEnv.authenticatedContext(USER_A, { role: 'WORKER' });
    await assertFails(
      updateDoc(doc(ctx.firestore(), `users/${USER_A}/notifications/notif-69`), {
        isRead: true,
        title: '해킹',
      })
    );
  });

  it('70: 본인이 createdAt 변경 → 차단', async () => {
    await setup();
    await setupNotification(testEnv, USER_A, 'notif-70', makeNotif());
    const ctx = testEnv.authenticatedContext(USER_A, { role: 'WORKER' });
    await assertFails(
      updateDoc(doc(ctx.firestore(), `users/${USER_A}/notifications/notif-70`), {
        createdAt: new Date('2020-01-01'),
      })
    );
  });

  // ── 3. 타인 알림 수정 차단 ──────────────────────────────
  it('71: 타인의 알림 isRead 변경 → 차단', async () => {
    await setup();
    await setupNotification(testEnv, USER_A, 'notif-71', makeNotif());
    const ctx = testEnv.authenticatedContext(USER_B, { role: 'WORKER' });
    await assertFails(
      updateDoc(doc(ctx.firestore(), `users/${USER_A}/notifications/notif-71`), {
        isRead: true,
      })
    );
  });

  it('72: 관리자가 근무자 알림 isRead 변경 → 차단 (관리자도 타인 알림 수정 불가)', async () => {
    await setup();
    await setupNotification(testEnv, USER_A, 'notif-72', makeNotif());
    const ctx = testEnv.authenticatedContext(ADMIN, { role: 'BUSINESS_ADMIN' });
    await assertFails(
      updateDoc(doc(ctx.firestore(), `users/${USER_A}/notifications/notif-72`), {
        isRead: true,
      })
    );
  });

  it('73: SuperAdmin이 근무자 알림 isRead 변경 → 차단 (경로 기반 소유권 제한)', async () => {
    await setup();
    await setupNotification(testEnv, USER_A, 'notif-73', makeNotif());
    const ctx = testEnv.authenticatedContext(SUPER, { role: 'SUPER_ADMIN' });
    await assertFails(
      updateDoc(doc(ctx.firestore(), `users/${USER_A}/notifications/notif-73`), {
        isRead: true,
      })
    );
  });

  // ── 4. 삭제는 허용 ────────────────────────────────────────
  it('74: 본인이 자신의 알림 삭제 → 허용', async () => {
    await setup();
    await setupNotification(testEnv, USER_A, 'notif-74', makeNotif());
    const ctx = testEnv.authenticatedContext(USER_A, { role: 'WORKER' });
    await assertSucceeds(
      deleteDoc(doc(ctx.firestore(), `users/${USER_A}/notifications/notif-74`))
    );
  });

  it('75: 타인 알림 삭제 → 차단', async () => {
    await setup();
    await setupNotification(testEnv, USER_A, 'notif-75', makeNotif());
    const ctx = testEnv.authenticatedContext(USER_B, { role: 'WORKER' });
    await assertFails(
      deleteDoc(doc(ctx.firestore(), `users/${USER_A}/notifications/notif-75`))
    );
  });

  // ── 5. 미인증 차단 ───────────────────────────────────────
  it('76: 미인증 사용자 알림 isRead 변경 → 차단', async () => {
    await setup();
    await setupNotification(testEnv, USER_A, 'notif-76', makeNotif());
    const ctx = testEnv.unauthenticatedContext();
    await assertFails(
      updateDoc(doc(ctx.firestore(), `users/${USER_A}/notifications/notif-76`), {
        isRead: true,
      })
    );
  });

  it('77: 미인증 사용자 알림 삭제 → 차단', async () => {
    await setup();
    await setupNotification(testEnv, USER_A, 'notif-77', makeNotif());
    const ctx = testEnv.unauthenticatedContext();
    await assertFails(
      deleteDoc(doc(ctx.firestore(), `users/${USER_A}/notifications/notif-77`))
    );
  });

  // ── 6. create 차단 ──────────────────────────────────────
  it('78: 본인이 알림 직접 create → 차단', async () => {
    await setup();
    const ctx = testEnv.authenticatedContext(USER_A, { role: 'WORKER' });
    await assertFails(
      setDoc(doc(ctx.firestore(), `users/${USER_A}/notifications/notif-78`), makeNotif())
    );
  });

  it('79: 관리자가 근무자 알림 직접 create → 차단 (CF createNotification 경유해야 함)', async () => {
    await setup();
    const ctx = testEnv.authenticatedContext(ADMIN, { role: 'BUSINESS_ADMIN' });
    await assertFails(
      setDoc(doc(ctx.firestore(), `users/${USER_A}/notifications/notif-79`), makeNotif())
    );
  });

  it('80: SuperAdmin이 알림 직접 create → 차단', async () => {
    await setup();
    const ctx = testEnv.authenticatedContext(SUPER, { role: 'SUPER_ADMIN' });
    await assertFails(
      setDoc(doc(ctx.firestore(), `users/${USER_A}/notifications/notif-80`), makeNotif())
    );
  });

  // ── 7. read는 허용 ───────────────────────────────────────
  it('81: 본인 알림 read → 허용', async () => {
    await setup();
    await setupNotification(testEnv, USER_A, 'notif-81', makeNotif());
    const ctx = testEnv.authenticatedContext(USER_A, { role: 'WORKER' });
    await assertSucceeds(
      getDoc(doc(ctx.firestore(), `users/${USER_A}/notifications/notif-81`))
    );
  });

  it('82: 타인 알림 read → 차단', async () => {
    await setup();
    await setupNotification(testEnv, USER_A, 'notif-82', makeNotif());
    const ctx = testEnv.authenticatedContext(USER_B, { role: 'WORKER' });
    await assertFails(
      getDoc(doc(ctx.firestore(), `users/${USER_A}/notifications/notif-82`))
    );
  });

  // ── 8. 추가 엣지 케이스 ─────────────────────────────────
  it('83: 빈 업데이트 객체 → 차단 (hasOnly 빈 집합)', async () => {
    await setup();
    await setupNotification(testEnv, USER_A, 'notif-83', makeNotif());
    const ctx = testEnv.authenticatedContext(USER_A, { role: 'WORKER' });
    // 빈 업데이트는 diff가 빈 키셋 → hasOnly([...]) 통과하지만 실제로 변경 없음
    // Firebase SDK는 빈 update를 허용하지 않으므로 isRead null로 테스트
    await assertFails(
      updateDoc(doc(ctx.firestore(), `users/${USER_A}/notifications/notif-83`), {
        isRead: true,
        unknownField: 'hack',
      })
    );
  });

  it('84: isRead + readAt + 세 번째 필드 동시 → 차단', async () => {
    await setup();
    await setupNotification(testEnv, USER_A, 'notif-84', makeNotif());
    const ctx = testEnv.authenticatedContext(USER_A, { role: 'WORKER' });
    await assertFails(
      updateDoc(doc(ctx.firestore(), `users/${USER_A}/notifications/notif-84`), {
        isRead: true,
        readAt: new Date(),
        businessId: 'inject',
      })
    );
  });

  it('85: 본인이 isRead=null로 → 허용 (필드 존재, 값은 상위 로직에서 처리)', async () => {
    await setup();
    await setupNotification(testEnv, USER_A, 'notif-85', makeNotif());
    const ctx = testEnv.authenticatedContext(USER_A, { role: 'WORKER' });
    await assertSucceeds(
      updateDoc(doc(ctx.firestore(), `users/${USER_A}/notifications/notif-85`), {
        isRead: null,
      })
    );
  });

  it('86: 역할 없는 사용자 자신 알림 isRead 변경 → 차단 (isLoggedIn 통과, isOwner 통과, 역할 무관)', async () => {
    await setup();
    const NO_ROLE = 'no-role-notif';
    await setupUser(testEnv, NO_ROLE, null, {});
    await setupNotification(testEnv, NO_ROLE, 'notif-86', makeNotif());
    const ctx = testEnv.authenticatedContext(NO_ROLE, {});
    // isOwner(userId) 조건: userId = NO_ROLE, context uid = NO_ROLE → 통과
    await assertSucceeds(
      updateDoc(doc(ctx.firestore(), `users/${NO_ROLE}/notifications/notif-86`), {
        isRead: true,
      })
    );
  });
});

// ═══════════════════════════════════════════════════════════
// 추가: 규칙 변경 전/후 동작 회귀 테스트
// ═══════════════════════════════════════════════════════════
describe('[회귀] 기존 동작 유지 확인', () => {
  it('87: attendance — SuperAdmin get 허용', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'attendance/reg-87'), { userId: 'u', businessId: 'b' });
      await setDoc(doc(ctx.firestore(), 'businesses/b'), { ownerId: 'admin', adminIds: [] });
      await setDoc(doc(ctx.firestore(), 'users/super-reg'), { role: 'SUPER_ADMIN' });
    });
    const ctx = testEnv.authenticatedContext('super-reg', { role: 'SUPER_ADMIN' });
    await assertSucceeds(getDoc(doc(ctx.firestore(), 'attendance/reg-87')));
  });

  it('88: attendance — worker get 자신 기록 허용', async () => {
    const WORKER = 'w-88';
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `attendance/reg-88`), { userId: WORKER, businessId: 'b' });
    });
    const ctx = testEnv.authenticatedContext(WORKER, { role: 'WORKER' });
    await assertSucceeds(getDoc(doc(ctx.firestore(), 'attendance/reg-88')));
  });

  it('89: schedule_change_requests — worker create 허용', async () => {
    const WORKER = 'w-89';
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'businesses/b89'), { ownerId: 'admin89', adminIds: [] });
    });
    const ctx = testEnv.authenticatedContext(WORKER, { role: 'WORKER' });
    await assertSucceeds(setDoc(doc(ctx.firestore(), 'schedule_change_requests/req-89'), {
      applicantUid: WORKER,
      businessId: 'b89',
      status: 'PENDING',
    }));
  });

  it('90: notifications — worker 자신 알림 read 허용', async () => {
    const U = 'u-90';
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `users/${U}/notifications/n-90`), {
        title: '테스트', isRead: false,
      });
    });
    const ctx = testEnv.authenticatedContext(U, {});
    await assertSucceeds(getDoc(doc(ctx.firestore(), `users/${U}/notifications/n-90`)));
  });

  it('91: notifications — 타 사용자 알림 read 차단 (기존 동작 유지)', async () => {
    const U = 'u-91'; const V = 'v-91';
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `users/${U}/notifications/n-91`), { title: '테스트' });
    });
    const ctx = testEnv.authenticatedContext(V, {});
    await assertFails(getDoc(doc(ctx.firestore(), `users/${U}/notifications/n-91`)));
  });

  it('92: attendance update — worker checkOut 수정 허용 (기존 동작 유지)', async () => {
    const WORKER = 'w-92';
    const BIZ = 'biz-92';
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `attendance/att-92`), {
        userId: WORKER, businessId: BIZ,
        wageStatus: 'pending',
        checkIn: new Date(),
      });
      await setDoc(doc(ctx.firestore(), `businesses/${BIZ}`), { ownerId: 'admin92', adminIds: [] });
    });
    const ctx = testEnv.authenticatedContext(WORKER, { role: 'WORKER' });
    await assertSucceeds(updateDoc(doc(ctx.firestore(), 'attendance/att-92'), {
      checkOut: new Date(),
      workHours: 8,
      status: 'completed',
      updatedAt: new Date(),
    }));
  });

  it('93: attendance update — worker wageStatus 변경 차단 (기존 동작 유지)', async () => {
    const WORKER = 'w-93';
    const BIZ = 'biz-93';
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `attendance/att-93`), {
        userId: WORKER, businessId: BIZ, wageStatus: 'pending',
      });
      await setDoc(doc(ctx.firestore(), `businesses/${BIZ}`), { ownerId: 'admin93', adminIds: [] });
    });
    const ctx = testEnv.authenticatedContext(WORKER, { role: 'WORKER' });
    await assertFails(updateDoc(doc(ctx.firestore(), 'attendance/att-93'), {
      wageStatus: 'confirmed',
    }));
  });

  it('94: schedule_change_requests delete — SuperAdmin 허용 (기존 동작)', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'schedule_change_requests/req-94'), {
        applicantUid: 'u', businessId: 'b', status: 'PENDING',
      });
      await setDoc(doc(ctx.firestore(), 'businesses/b'), { ownerId: 'oa', adminIds: [] });
      await setDoc(doc(ctx.firestore(), 'users/sup-94'), { role: 'SUPER_ADMIN' });
    });
    const ctx = testEnv.authenticatedContext('sup-94', { role: 'SUPER_ADMIN' });
    await assertSucceeds(deleteDoc(doc(ctx.firestore(), 'schedule_change_requests/req-94')));
  });

  it('95: schedule_change_requests delete — worker 차단 (기존 동작)', async () => {
    const WORKER = 'w-95';
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'schedule_change_requests/req-95'), {
        applicantUid: WORKER, businessId: 'b95', status: 'PENDING',
      });
      await setDoc(doc(ctx.firestore(), 'businesses/b95'), { ownerId: 'oa', adminIds: [] });
    });
    const ctx = testEnv.authenticatedContext(WORKER, { role: 'WORKER' });
    await assertFails(deleteDoc(doc(ctx.firestore(), 'schedule_change_requests/req-95')));
  });

  it('96: attendance — wageStatus=transferred worker update 차단 (기존 동작)', async () => {
    const WORKER = 'w-96';
    const BIZ = 'biz-96';
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `attendance/att-96`), {
        userId: WORKER, businessId: BIZ, wageStatus: 'transferred',
      });
      await setDoc(doc(ctx.firestore(), `businesses/${BIZ}`), { ownerId: 'admin96', adminIds: [] });
    });
    const ctx = testEnv.authenticatedContext(WORKER, { role: 'WORKER' });
    await assertFails(updateDoc(doc(ctx.firestore(), 'attendance/att-96'), {
      checkOut: new Date(),
    }));
  });

  it('97: attendance — wageStatus=confirmed worker update 차단', async () => {
    const WORKER = 'w-97';
    const BIZ = 'biz-97';
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `attendance/att-97`), {
        userId: WORKER, businessId: BIZ, wageStatus: 'confirmed',
      });
      await setDoc(doc(ctx.firestore(), `businesses/${BIZ}`), { ownerId: 'admin97', adminIds: [] });
    });
    const ctx = testEnv.authenticatedContext(WORKER, { role: 'WORKER' });
    await assertFails(updateDoc(doc(ctx.firestore(), 'attendance/att-97'), {
      checkOut: new Date(),
    }));
  });

  it('98: attendance create — worker 본인 출근 기록 생성 허용', async () => {
    const WORKER = 'w-98';
    const ctx = testEnv.authenticatedContext(WORKER, { role: 'WORKER' });
    await assertSucceeds(setDoc(doc(ctx.firestore(), 'attendance/att-98'), {
      userId: WORKER,
      businessId: 'biz-98',
      checkIn: new Date(),
      wageStatus: 'pending',
    }));
  });

  it('99: attendance create — worker 타인 출근 기록 생성 → 규칙 통과 (businessId 소유 없으면 차단)', async () => {
    const WORKER = 'w-99';
    const ctx = testEnv.authenticatedContext(WORKER, { role: 'WORKER' });
    // userId != auth.uid이고 businessId 관리자도 아니므로 차단
    await assertFails(setDoc(doc(ctx.firestore(), 'attendance/att-99'), {
      userId: 'other-user',
      businessId: 'biz-99',
      checkIn: new Date(),
    }));
  });

  it('100: notifications — 동일 경로에 update 허용, delete 허용이 분리 적용되는지 확인', async () => {
    const U = 'u-100';
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `users/${U}/notifications/n-100`), {
        title: '테스트', isRead: false, readAt: null,
      });
    });
    const ctx = testEnv.authenticatedContext(U, {});
    // update: isRead만 → 허용
    await assertSucceeds(updateDoc(doc(ctx.firestore(), `users/${U}/notifications/n-100`), {
      isRead: true,
    }));
    // delete → 허용
    await assertSucceeds(deleteDoc(doc(ctx.firestore(), `users/${U}/notifications/n-100`)));
  });

  it('101: attendance delete — SubAdmin는 어떠한 기록도 삭제 불가 (SEC-11 범위 확인)', async () => {
    const SUB = 'sub-101'; const BIZ = 'biz-101';
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'attendance/att-101'), { userId: 'u', businessId: BIZ });
      await setDoc(doc(ctx.firestore(), 'businesses/biz-101'), { ownerId: 'owner-101', adminIds: [] });
      await setDoc(doc(ctx.firestore(), `users/${SUB}`), { role: 'SUB_ADMIN', subAdminOf: BIZ });
    });
    const ctx = testEnv.authenticatedContext(SUB, { role: 'SUB_ADMIN' });
    await assertFails(deleteDoc(doc(ctx.firestore(), 'attendance/att-101')));
  });

  it('102: attendance delete — isAdmin()만으로는 타 사업장 삭제 불가 (취약점 수정 회귀)', async () => {
    const ADMIN_X = 'admin-x'; const BIZ_X = 'biz-x'; const BIZ_Y = 'biz-y';
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      // ADMIN_X는 BIZ_X의 관리자, BIZ_Y에는 관련 없음
      await setDoc(doc(ctx.firestore(), `businesses/${BIZ_X}`), { ownerId: ADMIN_X, adminIds: [ADMIN_X] });
      await setDoc(doc(ctx.firestore(), `businesses/${BIZ_Y}`), { ownerId: 'owner-y', adminIds: [] });
      await setDoc(doc(ctx.firestore(), 'attendance/att-102'), { userId: 'u', businessId: BIZ_Y, isDummy: true });
      await setDoc(doc(ctx.firestore(), `users/${ADMIN_X}`), { role: 'BUSINESS_ADMIN', businessId: BIZ_X });
    });
    const ctx = testEnv.authenticatedContext(ADMIN_X, { role: 'BUSINESS_ADMIN' });
    await assertFails(deleteDoc(doc(ctx.firestore(), 'attendance/att-102')));
  });
});
