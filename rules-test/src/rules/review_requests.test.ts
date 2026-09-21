// rules-test/src/rules/review_requests.test.ts
// review_requests 컬렉션 보안 규칙 검증
import { RulesTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, getDoc, getDocs, collection, query, where, setDoc, updateDoc, deleteDoc } from 'firebase/firestore';
import {
  createTestEnv, getAuth, seedDoc, seedUser, seedCommonFixtures,
  assertFails, assertSucceeds, IDS,
} from '../helpers/test-env';

let env: RulesTestEnvironment;

const RR = 'rr-001';
const RR2 = 'rr-002';

const rrBase = {
  businessId: IDS.business,
  workerId: IDS.user,
  workerName: '유저1',
  workerStatus: 'PENDING',
  adminStatus: 'PENDING',
};

beforeAll(async () => {
  env = await createTestEnv('review_requests');
  await seedCommonFixtures(env);
  await seedDoc(env, 'review_requests', RR, rrBase);
  await seedDoc(env, 'review_requests', RR2, { ...rrBase, businessId: IDS.business2, workerStatus: 'SUBMITTED' });
});

afterAll(async () => { await env.cleanup(); });

// ─── RR-GET ──────────────────────────────────────────────────────

describe('RR-GET: 단건 읽기', () => {
  test('RR-GET-01 해당 워커 본인 읽기 허용', async () => {
    const db = getAuth(env, IDS.user);
    await assertSucceeds(getDoc(doc(db, 'review_requests', RR)));
  });

  test('RR-GET-02 소속 관리자 읽기 허용', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(getDoc(doc(db, 'review_requests', RR)));
  });

  test('RR-GET-03 서브어드민 읽기 허용', async () => {
    const db = getAuth(env, IDS.subAdmin, { subAdminOf: IDS.business });
    await assertSucceeds(getDoc(doc(db, 'review_requests', RR)));
  });

  test('RR-GET-04 슈퍼어드민 읽기 허용', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertSucceeds(getDoc(doc(db, 'review_requests', RR)));
  });

  test('RR-GET-05 타 유저(관계없음) 읽기 차단', async () => {
    const db = getAuth(env, IDS.user2);
    await assertFails(getDoc(doc(db, 'review_requests', RR)));
  });
});

// ─── RR-LIST ─────────────────────────────────────────────────────

describe('RR-LIST: 목록 조회', () => {
  // xtest: 에뮬레이터에서 request.query.filters가 undefined로 평가됨 — 에뮬레이터 알려진 한계
  xtest('RR-LIST-01 USER: workerId == auth.uid 쿼리 허용', async () => {
    const db = getAuth(env, IDS.user);
    const q = query(collection(db, 'review_requests'), where('workerId', '==', IDS.user));
    await assertSucceeds(getDocs(q));
  });

  test('RR-LIST-02 USER: workerId != auth.uid 쿼리 차단', async () => {
    const db = getAuth(env, IDS.user);
    const q = query(collection(db, 'review_requests'), where('workerId', '==', IDS.user2));
    await assertFails(getDocs(q));
  });

  // xtest: 에뮬레이터 filters 이슈
  xtest('RR-LIST-03 BUSINESS_ADMIN: businessId 필터 쿼리 허용', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    const q = query(collection(db, 'review_requests'), where('businessId', '==', IDS.business));
    await assertSucceeds(getDocs(q));
  });

  test('RR-LIST-04 슈퍼어드민: 필터 없이 쿼리 허용', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertSucceeds(getDocs(collection(db, 'review_requests')));
  });
});

// ─── RR-CREATE ───────────────────────────────────────────────────

describe('RR-CREATE: 생성', () => {
  // [R8-P3B.3A.1] skip 해제 + 기대값 반전.
  //   기존 사유("에뮬레이터에서 isAdminOf() evaluation error")는 더 이상 맞지 않는다 —
  //   같은 연산이 trust_and_simple.test.ts에서 정상 평가된다.
  //   그리고 현재 정책은 review_requests create = isSuperAdmin() 전용이다.
  //   리뷰 요청 슬롯은 스케줄러/CF가 만든다. 관리자가 임의로 만들 수 있으면
  //   리뷰 대상·시점을 직접 고를 수 있게 된다.
  test('RR-CREATE-01 관리자는 리뷰 요청을 직접 생성할 수 없다 (CF/슈퍼어드민 전용)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      setDoc(doc(db, 'review_requests', 'rr-new-admin'), {
        businessId: IDS.business,
        workerId: IDS.user,
        workerName: '유저1',
        workerStatus: 'pending',
        adminStatus: 'pending',
      }),
    );
  });

  test('RR-CREATE-02 서브어드민도 리뷰 요청을 생성할 수 없다', async () => {
    const db = getAuth(env, IDS.subAdmin, { subAdminOf: IDS.business });
    await assertFails(
      setDoc(doc(db, 'review_requests', 'rr-new-sub'), {
        businessId: IDS.business,
        workerId: IDS.user,
        workerName: '유저1',
        workerStatus: 'pending',
        adminStatus: 'pending',
      }),
    );
  });

  test('RR-CREATE-03 일반 유저가 직접 생성 차단', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      setDoc(doc(db, 'review_requests', 'rr-user-hack'), {
        businessId: IDS.business,
        workerId: IDS.user,
        workerName: '유저1',
        workerStatus: 'PENDING',
        adminStatus: 'PENDING',
      }),
    );
  });
});

// ─── RR-UPDATE ───────────────────────────────────────────────────

describe('RR-UPDATE: 수정', () => {
  test('RR-UPDATE-01 워커가 workerStatus·workerReviewId 변경 허용', async () => {
    await seedDoc(env, 'review_requests', 'rr-worker-update', { ...rrBase });
    const db = getAuth(env, IDS.user);
    await assertSucceeds(
      updateDoc(doc(db, 'review_requests', 'rr-worker-update'), {
        workerStatus: 'submitted',  // [MEDIUM-FIX 29차] 값 화이트리스트는 소문자다
        workerReviewId: 'mr-123',
      }),
    );
  });

  test('RR-UPDATE-02 워커가 adminStatus 변경 차단', async () => {
    await seedDoc(env, 'review_requests', 'rr-worker-admin-hack', { ...rrBase });
    const db = getAuth(env, IDS.user);
    await assertFails(
      updateDoc(doc(db, 'review_requests', 'rr-worker-admin-hack'), {
        adminStatus: 'APPROVED',
      }),
    );
  });

  // [R8-P3B.3A.1] [REVIEW-BINDING 2026-09-08] adminStatus를 submitted로 바꾸려면
  //   adminReviewId가 가리키는 monthly_reviews 문서가 실제로 존재하고
  //   requestId·businessId가 맞아야 한다(getAfter 교차검증).
  //   리뷰를 안 쓰고 "작성 완료"로만 마킹하는 경로를 write 경계에서 막는다.
  test('RR-UPDATE-03 관리자가 adminStatus·adminReviewId 변경 허용 (리뷰 문서 결속 필요)', async () => {
    await seedDoc(env, 'review_requests', 'rr-admin-update', { ...rrBase });
    await seedDoc(env, 'monthly_reviews', 'mr-456', {
      requestId: 'rr-admin-update',
      businessId: IDS.business,
      targetUserId: IDS.user,
      reviewType: 'ADMIN_TO_USER',
    });
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(
      updateDoc(doc(db, 'review_requests', 'rr-admin-update'), {
        adminStatus: 'submitted',  // [MEDIUM-FIX 29차] 허용 값은 pending/submitted 뿐이다
        adminReviewId: 'mr-456',
      }),
    );
  });

  test('RR-UPDATE-04 관리자가 workerStatus 변경 차단 (워커 전용 필드)', async () => {
    await seedDoc(env, 'review_requests', 'rr-admin-worker-hack', { ...rrBase });
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'review_requests', 'rr-admin-worker-hack'), {
        workerStatus: 'SUBMITTED',
      }),
    );
  });

  // SEC-88: 탈퇴 익명화 — users 문서 삭제 전에 처리하므로 isUser() 통과
  // [R8-P3B.3A.1] [SEC-88] isDeletingAccount 교차검증 추가 — 탈퇴 처리 중인 계정만 익명화 가능.
  test('RR-UPDATE-05 탈퇴 익명화: 본인이 workerName만 변경 허용 (SEC-88)', async () => {
    await seedDoc(env, 'review_requests', 'rr-anonymize', { ...rrBase });
    await seedUser(env, IDS.user, {
      role: 'USER', username: 'user1', name: '유저1',
      email: 'user@test.com', isBlacklisted: false, isDeletingAccount: true,
    });
    const db = getAuth(env, IDS.user);
    await assertSucceeds(
      updateDoc(doc(db, 'review_requests', 'rr-anonymize'), {
        workerName: '탈퇴한 회원',
      }),
    );
  });

  test('RR-UPDATE-06 탈퇴 익명화 시 workerName 외 다른 필드 포함 차단 (SEC-88)', async () => {
    await seedDoc(env, 'review_requests', 'rr-anonymize-plus', { ...rrBase });
    const db = getAuth(env, IDS.user);
    await assertFails(
      updateDoc(doc(db, 'review_requests', 'rr-anonymize-plus'), {
        workerName: '탈퇴한 회원',
        workerStatus: 'SUBMITTED',  // workerName만 허용, 추가 필드 차단
      }),
    );
  });

  test('RR-UPDATE-07 타 유저가 workerName 변경 차단', async () => {
    await seedDoc(env, 'review_requests', 'rr-other-name-hack', { ...rrBase });
    const db = getAuth(env, IDS.user2);
    await assertFails(
      updateDoc(doc(db, 'review_requests', 'rr-other-name-hack'), {
        workerName: '해킹',
      }),
    );
  });

  test('RR-UPDATE-08 슈퍼어드민은 모든 필드 수정 허용', async () => {
    await seedDoc(env, 'review_requests', 'rr-super-update', { ...rrBase });
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertSucceeds(
      updateDoc(doc(db, 'review_requests', 'rr-super-update'), {
        workerName: '테스트',
        adminStatus: 'COMPLETED',
      }),
    );
  });
});

// ─── RR-DELETE ───────────────────────────────────────────────────

describe('RR-DELETE: 삭제', () => {
  test('RR-DELETE-01 슈퍼어드민만 삭제 허용', async () => {
    await seedDoc(env, 'review_requests', 'rr-del', rrBase);
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertSucceeds(deleteDoc(doc(db, 'review_requests', 'rr-del')));
  });

  test('RR-DELETE-02 관리자 삭제 차단', async () => {
    await seedDoc(env, 'review_requests', 'rr-del-admin', rrBase);
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(deleteDoc(doc(db, 'review_requests', 'rr-del-admin')));
  });

  test('RR-DELETE-03 워커 삭제 차단', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(deleteDoc(doc(db, 'review_requests', RR)));
  });
});
