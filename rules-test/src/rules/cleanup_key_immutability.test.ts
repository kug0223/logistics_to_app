// rules-test/src/rules/cleanup_key_immutability.test.ts
//
// [R7-P4.4E.11C.0C.0a.4.1] create 를 막는 것만으로는 부족했다
//
// 탈퇴 cleanup 은 행을 **field 로** 찾는다.
//
//   members                 collectionGroup where uid == 삭제대상
//   member_invitations      where targetUid / invitedBy == 삭제대상
//   idCardAccessRequests    where targetUserId / requesterId == 삭제대상
//   review_requests         where workerId == 삭제대상
//   applications            where uid == 삭제대상
//   attendance              where userId == 삭제대상
//
// 그 field 를 기존 행에서 다른 값으로 바꿀 수 있으면 cleanup 쿼리가 그 행을
// 영원히 못 찾는다. 삭제는 "성공"하고, 이름·전화번호·관계는 남는다.
//
// 그리고 그 경로는 하나였다 — 여섯 컬렉션의 `allow update` 가 모두
// **필드 제한 없는 `isSuperAdmin()` 분기**로 끝나거나(members, 초대,
// 열람요청, review_requests, applications) SUPER_ADMIN 분기에서 그 key 를
// 빼먹고 있었다(attendance).
//
// 그래서 불변 조건을 **분기 괄호 앞**에 둔다. 역할로 우회할 수 없다.
//
// 이 파일이 고정하는 것
//   MEM-UPD-*     members 정상 update 보존 + uid/businessId 불변
//   MEM-CLEAN-01  cleanup 회피 시나리오
//   INV-KEY-*     member_invitations
//   ICAR-KEY-*    idCardAccessRequests
//   REV-KEY-*     review_requests
//   MONTH-KEY-*   monthly_reviews (이미 불변 — 계약 고정)
//   TRUST-KEY-*   trust_score_history (update 자체 없음)
//   APP-KEY-*     applications
//   ATT-KEY-*     attendance
import { RulesTestEnvironment } from '@firebase/rules-unit-testing';
import {
  doc, setDoc, updateDoc, deleteField, serverTimestamp,
} from 'firebase/firestore';
import {
  createTestEnv, getAuth, seedDoc, seedCommonFixtures,
  assertFails, assertSucceeds, IDS,
} from '../helpers/test-env';

let env: RulesTestEnvironment;

// 이 스위트 전용 — 다른 파일이 같은 경로를 먼저 만들면 setDoc 이 update 가
// 되어 create 규칙을 검증하지 못한다(.0a.4 에서 겪었다).
const WORKER = 'uid-ck-worker';
const OTHER = 'uid-ck-other';
const MEMBER_DOC = 'uid-ck-member';

beforeAll(async () => {
  env = await createTestEnv('cleanup_key_immutability');
  await seedCommonFixtures(env);

  await seedDoc(env, 'users', WORKER, {
    role: 'USER', username: 'ckworker', name: '근로자',
    accountStatus: 'active', isBlacklisted: false,
  });
  await seedDoc(env, 'users', OTHER, {
    role: 'USER', username: 'ckother', name: '타인',
    accountStatus: 'active', isBlacklisted: false,
  });

  // members — canonical 행
  await seedDoc(env, `businesses/${IDS.business}/members`, MEMBER_DOC, {
    uid: MEMBER_DOC, businessId: IDS.business,
    name: '구성원', phone: '010-1111-2222',
    role: 'WORKER', permissions: { canManageTo: false },
    addedAt: new Date(),
  });

  // member_invitations
  await seedDoc(env, 'member_invitations', 'ck-inv', {
    businessId: IDS.business, businessName: '테스트사업장',
    targetUid: WORKER, targetName: '근로자', targetPhone: '010-3333-4444',
    invitedBy: IDS.admin, invitedByName: '관리자',
    permissions: {}, status: 'pending', createdAt: new Date(),
  });

  // idCardAccessRequests
  await seedDoc(env, 'idCardAccessRequests', 'ck-icar', {
    requesterId: IDS.admin, requesterBusinessId: IDS.business,
    targetUserId: WORKER, applicationId: 'ck-app', status: 'pending',
  });

  // review_requests
  await seedDoc(env, 'review_requests', 'ck-rev', {
    businessId: IDS.business, workerId: WORKER, workerName: '근로자',
    workerStatus: 'pending', adminStatus: 'pending', isPublished: false,
  });

  // monthly_reviews
  await seedDoc(env, 'monthly_reviews', 'ck-month', {
    businessId: IDS.business, requestId: 'ck-rev',
    reviewType: 'ADMIN_TO_USER', reviewerId: IDS.admin,
    targetUserId: WORKER, targetUserName: '근로자',
    rating: 5, comment: '좋음', isPublished: false,
  });

  // trust_score_history
  await seedDoc(env, 'trust_score_history', 'ck-trust', {
    userId: WORKER, delta: -5, reason: 'NO_SHOW', createdAt: new Date(),
  });

  // applications
  await seedDoc(env, 'applications', 'ck-application', {
    uid: WORKER, businessId: IDS.business, toId: IDS.to,
    status: 'PENDING', appliedAt: new Date(),
  });

  // attendance
  await seedDoc(env, 'attendance', 'ck-attendance', {
    userId: WORKER, businessId: IDS.business, applicationId: 'ck-application',
    workDate: '2026-01-15', status: 'scheduled', wageStatus: 'pending',
  });
});

afterAll(async () => { await env.cleanup(); });

const asSuper = () => getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
const asAdmin = () => getAuth(env, IDS.admin, { role: 'BUSINESS_ADMIN' });

// ─── MEM-UPD: members ───────────────────────────────────────────────────

describe('MEM-UPD: members 정상 update 보존 + identity key 불변', () => {
  test('MEM-UPD-01 BUSINESS_ADMIN permissions update → 허용 (기존 동작)', async () => {
    await assertSucceeds(updateDoc(
      doc(asAdmin(), `businesses/${IDS.business}/members`, MEMBER_DOC),
      { permissions: { canManageTo: true } }));
  });

  test('MEM-UPD-02 SUPER_ADMIN 의 non-key update → 기존 동작 유지', async () => {
    // SUPER_ADMIN 의 전체 update 권한을 없애는 것이 목적이 아니다(§10).
    // name 같은 운영 필드는 그대로 바꿀 수 있어야 한다.
    await assertSucceeds(updateDoc(
      doc(asSuper(), `businesses/${IDS.business}/members`, MEMBER_DOC),
      { name: '구성원-수정' }));
  });

  test('MEM-UPD-10 SUPER_ADMIN uid 변경 → 거부', async () => {
    await assertFails(updateDoc(
      doc(asSuper(), `businesses/${IDS.business}/members`, MEMBER_DOC),
      { uid: OTHER }));
  });

  test('MEM-UPD-11 SUPER_ADMIN businessId 변경 → 거부', async () => {
    await assertFails(updateDoc(
      doc(asSuper(), `businesses/${IDS.business}/members`, MEMBER_DOC),
      { businessId: IDS.business2 }));
  });

  test('MEM-UPD-12 BUSINESS_ADMIN uid 변경 → 거부', async () => {
    await assertFails(updateDoc(
      doc(asAdmin(), `businesses/${IDS.business}/members`, MEMBER_DOC),
      { uid: OTHER }));
  });

  test('MEM-UPD-13 BUSINESS_ADMIN businessId 변경 → 거부', async () => {
    await assertFails(updateDoc(
      doc(asAdmin(), `businesses/${IDS.business}/members`, MEMBER_DOC),
      { businessId: IDS.business2 }));
  });

  test('MEM-UPD-14 tombstone 과 무관하게 거부된다 (§57)', async () => {
    // identity key 불변은 계정삭제 여부와 독립이다. 이 행의 uid 에는
    // tombstone 이 없는데도 거부되어야 한다.
    await assertFails(updateDoc(
      doc(asSuper(), `businesses/${IDS.business}/members`, MEMBER_DOC),
      { uid: OTHER, name: '같이 바꿔도' }));
  });

  test('MEM-UPD-15 uid field 삭제도 거부 (쿼리에서 사라진다)', async () => {
    await assertFails(updateDoc(
      doc(asSuper(), `businesses/${IDS.business}/members`, MEMBER_DOC),
      { uid: deleteField() }));
  });
});

describe('MEM-CLEAN: cleanup 회피 불가', () => {
  test('MEM-CLEAN-01 writer-first 행의 uid 를 바꿔 cleanup 을 피할 수 없다', async () => {
    // 시나리오: members/U 가 data.uid = U 로 존재한다.
    //   SUPER_ADMIN 이 data.uid = X 로 바꾸면 Final 의
    //   `where("uid","==",U)` 가 이 행을 놓친다.
    // 그 전이가 DENY 이므로, writer-first 행은 항상 cleanup 술어에 걸린다.
    await assertFails(updateDoc(
      doc(asSuper(), `businesses/${IDS.business}/members`, MEMBER_DOC),
      { uid: OTHER }));
    // 그리고 .0a.4 의 create barrier 회귀 — 삭제 중 계정에는 새로 못 만든다.
    await seedDoc(env, 'account_deletion_tombstones', 'uid-ck-deleting', {
      barrierAt: new Date(), schemaVersion: 1,
    });
    await assertFails(setDoc(
      doc(asAdmin(), `businesses/${IDS.business}/members`, 'uid-ck-deleting'),
      {
        uid: 'uid-ck-deleting', businessId: IDS.business,
        name: 'x', phone: 'y', role: 'WORKER', permissions: {},
        addedAt: new Date(),
      }));
  });
});

// ─── INV-KEY: member_invitations ────────────────────────────────────────

describe('INV-KEY: 초대의 cleanup key 불변 + lifecycle 보존', () => {
  test('INV-KEY-01 targetUid 변경 → 거부 (SUPER_ADMIN 포함)', async () => {
    await assertFails(updateDoc(
      doc(asSuper(), 'member_invitations', 'ck-inv'), { targetUid: OTHER }));
  });

  test('INV-KEY-02 invitedBy 변경 → 거부', async () => {
    await assertFails(updateDoc(
      doc(asSuper(), 'member_invitations', 'ck-inv'), { invitedBy: OTHER }));
  });

  test('INV-KEY-03 pending → rejected 정상 (수신자)', async () => {
    const db = getAuth(env, WORKER);
    await assertSucceeds(updateDoc(
      doc(db, 'member_invitations', 'ck-inv'),
      { status: 'rejected', respondedAt: new Date() }));
  });

  test('INV-KEY-04 pending → cancelled 정상 (관리자)', async () => {
    await seedDoc(env, 'member_invitations', 'ck-inv2', {
      businessId: IDS.business, businessName: '테스트사업장',
      targetUid: WORKER, targetName: '근로자', targetPhone: '010-3333-4444',
      invitedBy: IDS.admin, invitedByName: '관리자',
      permissions: {}, status: 'pending', createdAt: new Date(),
    });
    await assertSucceeds(updateDoc(
      doc(asAdmin(), 'member_invitations', 'ck-inv2'),
      { status: 'cancelled', canceledAt: new Date() }));
  });
});

// ─── ICAR-KEY: idCardAccessRequests ────────────────────────────────────

describe('ICAR-KEY: 열람요청의 cleanup key 불변 + 상태전이 보존', () => {
  test('ICAR-KEY-01 targetUserId 변경 → 거부', async () => {
    await assertFails(updateDoc(
      doc(asSuper(), 'idCardAccessRequests', 'ck-icar'),
      { targetUserId: OTHER }));
  });

  test('ICAR-KEY-02 requesterId 변경 → 거부', async () => {
    await assertFails(updateDoc(
      doc(asSuper(), 'idCardAccessRequests', 'ck-icar'),
      { requesterId: OTHER }));
  });

  test('ICAR-KEY-03 수신자 pending → approved 정상', async () => {
    const db = getAuth(env, WORKER);
    await assertSucceeds(updateDoc(
      doc(db, 'idCardAccessRequests', 'ck-icar'),
      { status: 'approved', respondedAt: new Date() }));
  });

  test('ICAR-KEY-04 관리자 cancel 정상', async () => {
    await seedDoc(env, 'idCardAccessRequests', 'ck-icar2', {
      requesterId: IDS.admin, requesterBusinessId: IDS.business,
      targetUserId: WORKER, applicationId: 'ck-app', status: 'pending',
    });
    await assertSucceeds(updateDoc(
      doc(asAdmin(), 'idCardAccessRequests', 'ck-icar2'),
      { status: 'canceled' }));
  });
});

// ─── REV-KEY: review_requests ──────────────────────────────────────────

describe('REV-KEY: review_requests 의 workerId 불변', () => {
  test('REV-KEY-01 workerId 재지정 → 거부 (SUPER_ADMIN 포함)', async () => {
    await assertFails(updateDoc(
      doc(asSuper(), 'review_requests', 'ck-rev'), { workerId: OTHER }));
  });

  test('REV-KEY-02 근로자 리뷰 제출 필드는 그대로 허용', async () => {
    const db = getAuth(env, WORKER);
    await assertSucceeds(updateDoc(
      doc(db, 'review_requests', 'ck-rev'),
      { workerStatus: 'submitted', workerReviewId: 'ck-month' }));
  });

  test('REV-KEY-03 SUPER_ADMIN 의 non-key update 는 유지', async () => {
    await assertSucceeds(updateDoc(
      doc(asSuper(), 'review_requests', 'ck-rev'), { isPublished: true }));
  });
});

// ─── MONTH-KEY: monthly_reviews (이미 불변) ────────────────────────────

describe('MONTH-KEY: monthly_reviews 는 이미 불변이었다', () => {
  test('MONTH-KEY-01 targetUserId 재지정 → 거부', async () => {
    await assertFails(updateDoc(
      doc(asSuper(), 'monthly_reviews', 'ck-month'),
      { targetUserId: OTHER }));
  });

  test('MONTH-KEY-02 reviewerId 재지정 → 거부', async () => {
    await assertFails(updateDoc(
      doc(asSuper(), 'monthly_reviews', 'ck-month'),
      { reviewerId: OTHER }));
  });

  test('MONTH-KEY-03 SUPER_ADMIN 의 허용 필드는 유지', async () => {
    // 기존 분기는 rating·comment·tags·reviewType·reviewerId·targetUserId·
    // businessId 를 제외한다. 그 밖(isPublished 등)은 바꿀 수 있다.
    await assertSucceeds(updateDoc(
      doc(asSuper(), 'monthly_reviews', 'ck-month'), { isPublished: true }));
  });
});

// ─── TRUST-KEY: trust_score_history (update 자체 없음) ─────────────────

describe('TRUST-KEY: 신뢰이력은 update surface 가 없다', () => {
  test('TRUST-KEY-01 userId 재지정 → 거부 (SUPER_ADMIN 포함)', async () => {
    await assertFails(updateDoc(
      doc(asSuper(), 'trust_score_history', 'ck-trust'), { userId: OTHER }));
  });

  test('TRUST-KEY-02 어떤 update 도 불가 (append-only)', async () => {
    await assertFails(updateDoc(
      doc(asSuper(), 'trust_score_history', 'ck-trust'), { reason: 'OTHER' }));
  });
});

// ─── APP-KEY / ATT-KEY: domain residual 술어 ───────────────────────────

describe('APP-KEY: applications.uid 불변', () => {
  test('APP-KEY-01 SUPER_ADMIN uid 재지정 → 거부', async () => {
    await assertFails(updateDoc(
      doc(asSuper(), 'applications', 'ck-application'), { uid: OTHER }));
  });

  test('APP-KEY-02 SUPER_ADMIN 의 non-key update 는 유지', async () => {
    await assertSucceeds(updateDoc(
      doc(asSuper(), 'applications', 'ck-application'),
      { adminMemo: '검토' }));
  });
});

describe('ATT-KEY: attendance.userId 불변', () => {
  test('ATT-KEY-01 SUPER_ADMIN userId 재지정 → 거부', async () => {
    await assertFails(updateDoc(
      doc(asSuper(), 'attendance', 'ck-attendance'), { userId: OTHER }));
  });

  test('ATT-KEY-02 SUPER_ADMIN 의 non-key update 는 유지', async () => {
    // 금액 필드가 아니고 wageStatus 도 건드리지 않는다 — 기존 허용 범위.
    await assertSucceeds(updateDoc(
      doc(asSuper(), 'attendance', 'ck-attendance'),
      { adminNote: '확인' }));
  });

  test('ATT-KEY-03 BUSINESS_ADMIN userId 재지정 → 거부 (기존 동작)', async () => {
    await assertFails(updateDoc(
      doc(asAdmin(), 'attendance', 'ck-attendance'), { userId: OTHER }));
  });
});

// ─── 공통: serverTimestamp 가 필요한 경로가 깨지지 않았는지 ────────────

describe('CK-REG: 불변 조건이 기존 서버시각 강제와 충돌하지 않는다', () => {
  test('CK-REG-01 초대 create 정상 경로 유지', async () => {
    await assertSucceeds(setDoc(
      doc(asAdmin(), 'member_invitations', 'ck-inv3'),
      {
        businessId: IDS.business, businessName: '테스트사업장',
        targetUid: WORKER, targetName: '근로자',
        invitedBy: IDS.admin, invitedByName: '관리자',
        permissions: {}, status: 'pending', createdAt: serverTimestamp(),
      }));
  });
});
