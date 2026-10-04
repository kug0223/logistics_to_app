// rules-test/src/rules/deletion_dual_axis_barrier.test.ts
//
// [R7-P4.4E.11C.0C.0a.4.2] 한 문서가 두 사람을 가리킨다
//
// .0a.4 는 "받는 사람"만 막았다. 그런데 탈퇴 cleanup 은 두 축을 모두 본다.
//
//   member_invitations     targetUid(받는 근로자) · invitedBy(보낸 관리자)
//   idCardAccessRequests   targetUserId(열람 대상) · requesterId(요청 관리자)
//   monthly_reviews        targetUserId(평가 대상) · reviewerId(평가자)
//   review_requests        workerId
//
// 그래서 **삭제 중인 관리자가 정상 근로자에게** 새 문서를 만들면, cleanup 이
// 지나간 뒤 그 관리자의 uid 가 다시 생긴다. 받는 쪽만 막아서는 닫히지 않는다.
//
// 그리고 USER_TO_BUSINESS 리뷰는 익명이라 deletion-owned UID 를 만들지 않는다 —
// "삭제 중인 사용자는 아무 리뷰도 못 쓴다"로 정책을 넓히지 않는다.
//
// 고정하는 것
//   INV-DUAL-*   초대 양축
//   ICAR-DUAL-*  열람요청 양축
//   MR-DUAL-*    월간리뷰 양축 + USER_TO_BUSINESS 비변경
//   RR-DUAL-*    리뷰요청 workerId
//   DUAL-COMMIT  commit 시점 평가
import { RulesTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, setDoc, serverTimestamp } from 'firebase/firestore';
import {
  createTestEnv, getAuth, seedDoc, seedCommonFixtures,
  assertFails, assertSucceeds, IDS,
} from '../helpers/test-env';

let env: RulesTestEnvironment;

// 전용 uid — 다른 스위트가 같은 경로를 먼저 만들면 create 규칙을 검증하지 못한다.
const ADMIN_OK = 'uid-da-admin';        // 정상 관리자
const ADMIN_DEL = 'uid-da-admin-del';   // 삭제 중 관리자 (tombstone)
const SUPER_DEL = 'uid-da-super-del';   // 삭제 중 SUPER_ADMIN
const WORKER_OK = 'uid-da-worker';      // 정상 근로자
const WORKER_DEL = 'uid-da-worker-del'; // 삭제 중 근로자 (tombstone)
const UNRELATED_DEL = 'uid-da-unrelated-del';
const BIZ = 'biz-da-001';

const tomb = () => ({ barrierAt: new Date(), schemaVersion: 1 });

beforeAll(async () => {
  env = await createTestEnv('deletion_dual_axis_barrier');
  await seedCommonFixtures(env);

  await Promise.all([
    seedDoc(env, 'users', ADMIN_OK, {
      role: 'BUSINESS_ADMIN', name: '정상관리자', isBlacklisted: false,
    }),
    seedDoc(env, 'users', ADMIN_DEL, {
      role: 'BUSINESS_ADMIN', name: '삭제중관리자',
      accountStatus: 'deleting', isBlacklisted: false,
    }),
    seedDoc(env, 'users', SUPER_DEL, {
      role: 'SUPER_ADMIN', name: '삭제중슈퍼', isBlacklisted: false,
    }),
    seedDoc(env, 'users', WORKER_OK, {
      role: 'USER', name: '정상근로자', isBlacklisted: false,
    }),
    seedDoc(env, 'users', WORKER_DEL, {
      role: 'USER', name: '삭제중근로자',
      accountStatus: 'deleting', isBlacklisted: false,
    }),
  ]);

  // 두 관리자가 모두 이 사업장의 adminIds 에 있어야 isAdminOf 가 통과한다.
  await seedDoc(env, 'businesses', BIZ, {
    ownerId: ADMIN_OK, adminIds: [ADMIN_OK, ADMIN_DEL],
    name: '양축테스트사업장', status: 'approved',
  });

  await Promise.all([
    seedDoc(env, 'account_deletion_tombstones', ADMIN_DEL, tomb()),
    seedDoc(env, 'account_deletion_tombstones', SUPER_DEL, tomb()),
    seedDoc(env, 'account_deletion_tombstones', WORKER_DEL, tomb()),
    seedDoc(env, 'account_deletion_tombstones', UNRELATED_DEL, tomb()),
  ]);

  // ADMIN_TO_USER 리뷰 생성에 필요한 review_request binding 두 벌.
  const future = new Date(Date.now() + 7 * 24 * 3600 * 1000);
  await Promise.all([
    seedDoc(env, 'review_requests', 'da-rr-ok', {
      requestKey: 'da-rr-ok', businessId: BIZ, workerId: WORKER_OK,
      workerName: '정상근로자', adminStatus: 'pending', workerStatus: 'pending',
      deadline: future, isPublished: false,
    }),
    seedDoc(env, 'review_requests', 'da-rr-del', {
      requestKey: 'da-rr-del', businessId: BIZ, workerId: WORKER_DEL,
      workerName: '삭제중근로자', adminStatus: 'pending', workerStatus: 'pending',
      deadline: future, isPublished: false,
    }),
  ]);
});

afterAll(async () => { await env.cleanup(); });

const as = (uid: string, role: string) => getAuth(env, uid, { role });

// ─── INV-DUAL: member_invitations 양축 ──────────────────────────────────

const invitation = (inviter: string, target: string) => ({
  businessId: BIZ, businessName: '양축테스트사업장',
  targetUid: target, targetName: '이름', targetPhone: '010-0000-0000',
  invitedBy: inviter, invitedByName: '관리자',
  permissions: {}, status: 'pending', createdAt: serverTimestamp(),
});

describe('INV-DUAL: 초대는 두 축 모두 막는다', () => {
  test('INV-DUAL-01 정상 관리자 + 정상 근로자 → 허용 (기존 동작)', async () => {
    await assertSucceeds(setDoc(
      doc(as(ADMIN_OK, 'BUSINESS_ADMIN'), 'member_invitations', 'da-inv-01'),
      invitation(ADMIN_OK, WORKER_OK)));
  });

  test('INV-DUAL-02 정상 관리자 + 삭제 중 근로자 → 거부', async () => {
    await assertFails(setDoc(
      doc(as(ADMIN_OK, 'BUSINESS_ADMIN'), 'member_invitations', 'da-inv-02'),
      invitation(ADMIN_OK, WORKER_DEL)));
  });

  test('INV-DUAL-03 삭제 중 관리자 + 정상 근로자 → 거부', async () => {
    // .0a.4 가 닫지 못한 축이다 — 보낸 사람의 uid 가 문서에 남는다.
    await assertFails(setDoc(
      doc(as(ADMIN_DEL, 'BUSINESS_ADMIN'), 'member_invitations', 'da-inv-03'),
      invitation(ADMIN_DEL, WORKER_OK)));
  });

  test('INV-DUAL-04 삭제 중 SUPER_ADMIN + 정상 근로자 → 거부', async () => {
    await assertFails(setDoc(
      doc(as(SUPER_DEL, 'SUPER_ADMIN'), 'member_invitations', 'da-inv-04'),
      invitation(SUPER_DEL, WORKER_OK)));
  });

  test('INV-DUAL-05 무관한 tombstone 은 영향이 없다', async () => {
    await assertSucceeds(setDoc(
      doc(as(ADMIN_OK, 'BUSINESS_ADMIN'), 'member_invitations', 'da-inv-05'),
      invitation(ADMIN_OK, WORKER_OK)));
  });
});

// ─── ICAR-DUAL: idCardAccessRequests 양축 (client direct) ───────────────

const icar = (requester: string, target: string) => ({
  requesterId: requester, requesterBusinessId: BIZ,
  targetUserId: target, applicationId: 'da-app', status: 'pending',
});

describe('ICAR-DUAL: 열람요청은 두 축 모두 막는다', () => {
  test('ICAR-DUAL-01 정상 요청자 + 정상 대상 → 허용 (기존 동작)', async () => {
    await assertSucceeds(setDoc(
      doc(as(ADMIN_OK, 'BUSINESS_ADMIN'), 'idCardAccessRequests', 'da-icar-01'),
      icar(ADMIN_OK, WORKER_OK)));
  });

  test('ICAR-DUAL-02 삭제 중 요청자 → 거부', async () => {
    await assertFails(setDoc(
      doc(as(ADMIN_DEL, 'BUSINESS_ADMIN'), 'idCardAccessRequests', 'da-icar-02'),
      icar(ADMIN_DEL, WORKER_OK)));
  });

  test('ICAR-DUAL-03 삭제 중 대상 → 거부', async () => {
    await assertFails(setDoc(
      doc(as(ADMIN_OK, 'BUSINESS_ADMIN'), 'idCardAccessRequests', 'da-icar-03'),
      icar(ADMIN_OK, WORKER_DEL)));
  });

  test('ICAR-DUAL-04 삭제 중 SUPER_ADMIN 요청자 → 거부', async () => {
    await assertFails(setDoc(
      doc(as(SUPER_DEL, 'SUPER_ADMIN'), 'idCardAccessRequests', 'da-icar-04'),
      icar(SUPER_DEL, WORKER_OK)));
  });
});

// ─── MR-DUAL: monthly_reviews 양축 + USER_TO_BUSINESS 비변경 ───────────

const adminReview = (reviewer: string, target: string, requestId: string) => ({
  reviewType: 'ADMIN_TO_USER',
  reviewerId: reviewer,
  targetUserId: target,
  businessId: BIZ,
  requestId,
  rating: 5,
  isPublished: false,
});

describe('MR-DUAL: 월간리뷰는 두 축 모두 막는다', () => {
  test('MR-DUAL-01 정상 평가자 + 정상 대상 → 허용 (기존 동작)', async () => {
    await assertSucceeds(setDoc(
      doc(as(ADMIN_OK, 'BUSINESS_ADMIN'), 'monthly_reviews', 'da-mr-01'),
      adminReview(ADMIN_OK, WORKER_OK, 'da-rr-ok')));
  });

  test('MR-DUAL-02 삭제 중 평가자 → 거부', async () => {
    await assertFails(setDoc(
      doc(as(ADMIN_DEL, 'BUSINESS_ADMIN'), 'monthly_reviews', 'da-mr-02'),
      adminReview(ADMIN_DEL, WORKER_OK, 'da-rr-ok')));
  });

  test('MR-DUAL-03 삭제 중 대상 → 거부', async () => {
    await assertFails(setDoc(
      doc(as(ADMIN_OK, 'BUSINESS_ADMIN'), 'monthly_reviews', 'da-mr-03'),
      adminReview(ADMIN_OK, WORKER_DEL, 'da-rr-del')));
  });

  test('MR-DUAL-04 삭제 중 SUPER_ADMIN 평가자 → 거부', async () => {
    await assertFails(setDoc(
      doc(as(SUPER_DEL, 'SUPER_ADMIN'), 'monthly_reviews', 'da-mr-04'),
      adminReview(SUPER_DEL, WORKER_OK, 'da-rr-ok')));
  });

  test('MR-DUAL-05 USER_TO_BUSINESS 정상 흐름이 그대로다', async () => {
    // 익명 리뷰다 — reviewerId 가 없고 targetUserId 도 없다. 그래서
    // deletion-owned UID 를 만들지 않으므로 barrier 가 걸리지 않아야 한다.
    const db = getAuth(env, WORKER_OK, { role: 'USER' });
    await assertSucceeds(setDoc(
      doc(db, 'monthly_reviews', 'da-mr-05'),
      {
        reviewType: 'USER_TO_BUSINESS',
        businessId: BIZ,
        requestId: 'da-rr-ok',
        rating: 4,
        isPublished: false,
      }));
  });

  test('MR-DUAL-06 삭제 중 근로자의 USER_TO_BUSINESS 도 막지 않는다 (§34)', async () => {
    // 정책을 넓히지 않는다 — 이 문서에는 삭제 대상 UID 가 남지 않는다.
    const db = getAuth(env, WORKER_DEL, { role: 'USER' });
    await assertSucceeds(setDoc(
      doc(db, 'monthly_reviews', 'da-mr-06'),
      {
        reviewType: 'USER_TO_BUSINESS',
        businessId: BIZ,
        requestId: 'da-rr-del',
        rating: 3,
        isPublished: false,
      }));
  });
});

// ─── RR-DUAL: review_requests workerId (client SUPER_ADMIN 경로) ────────

describe('RR-DUAL: 리뷰요청의 workerId 축', () => {
  test('RR-DUAL-01 정상 근로자 → 기존 SUPER_ADMIN create 유지', async () => {
    await assertSucceeds(setDoc(
      doc(as(IDS.superAdmin, 'SUPER_ADMIN'), 'review_requests', 'da-rr-new-01'),
      {
        requestKey: 'da-rr-new-01', businessId: BIZ, workerId: WORKER_OK,
        workerName: '정상근로자', adminStatus: 'pending',
        workerStatus: 'pending', isPublished: false,
      }));
  });

  test('RR-DUAL-02 삭제 중 근로자 → 거부 (SUPER_ADMIN 예외 없음)', async () => {
    await assertFails(setDoc(
      doc(as(IDS.superAdmin, 'SUPER_ADMIN'), 'review_requests', 'da-rr-new-02'),
      {
        requestKey: 'da-rr-new-02', businessId: BIZ, workerId: WORKER_DEL,
        workerName: '삭제중근로자', adminStatus: 'pending',
        workerStatus: 'pending', isPublished: false,
      }));
  });
});

// ─── DUAL-COMMIT: commit 시점 평가 ─────────────────────────────────────

describe('DUAL-COMMIT: barrier 가 commit 시점에 평가된다 (§67)', () => {
  test('DUAL-COMMIT-01 freeze 가 먼저 commit 되면 그 뒤 write 는 거부', async () => {
    const LATE = 'uid-da-late';
    await seedDoc(env, 'users', LATE, {
      role: 'USER', name: '늦은대상', isBlacklisted: false,
    });
    // barrier 없음 — 먼저 통과하는지 확인한다(단정이 공허하지 않게).
    await assertSucceeds(setDoc(
      doc(as(ADMIN_OK, 'BUSINESS_ADMIN'), 'member_invitations', 'da-late-ok'),
      invitation(ADMIN_OK, LATE)));
    // 이제 freeze 가 commit 된다.
    await seedDoc(env, 'account_deletion_tombstones', LATE, tomb());
    // 같은 모양의 write 가 이제는 거부된다 — Rules 는 commit 시점에 평가된다.
    await assertFails(setDoc(
      doc(as(ADMIN_OK, 'BUSINESS_ADMIN'), 'member_invitations', 'da-late-deny'),
      invitation(ADMIN_OK, LATE)));
  });
});
