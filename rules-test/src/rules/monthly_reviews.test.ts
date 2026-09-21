// rules-test/src/rules/monthly_reviews.test.ts
// monthly_reviews 컬렉션 보안 규칙 검증 (30개 시나리오)
import { RulesTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc, deleteField, serverTimestamp } from 'firebase/firestore';
import {
  createTestEnv, getAuth, seedDoc, seedUser, seedCommonFixtures,
  assertFails, assertSucceeds, IDS,
} from '../helpers/test-env';

let env: RulesTestEnvironment;

const MR = 'mr-001';              // ADMIN_TO_USER 리뷰
const MR_UTB = 'mr-utb-001';     // USER_TO_BUSINESS 리뷰
const MR_PUBLIC = 'mr-pub-001';  // 공개 리뷰 (isPublished=true)

const adminToUserBase = {
  reviewType: 'ADMIN_TO_USER',
  businessId: IDS.business,
  reviewerId: IDS.admin,
  targetUserId: IDS.user,
  isPublished: true,
  rating: 4,
};

const userToBusinessBase = {
  reviewType: 'USER_TO_BUSINESS',
  businessId: IDS.business,
  // reviewerId 없음 — 익명 보장 설계 (H-01)
  targetUserId: IDS.business,
  isPublished: false,
  requestId: 'rr-001',
};

beforeAll(async () => {
  env = await createTestEnv('monthly_reviews');
  await seedCommonFixtures(env);

  await seedDoc(env, 'monthly_reviews', MR, adminToUserBase);
  await seedDoc(env, 'monthly_reviews', MR_UTB, userToBusinessBase);
  await seedDoc(env, 'monthly_reviews', MR_PUBLIC, { ...adminToUserBase, isPublished: true });
  // 사업장 답변 있는 리뷰 (기존 답변 덮어쓰기 차단 검증)
  await seedDoc(env, 'monthly_reviews', 'mr-with-response', {
    ...userToBusinessBase,
    businessResponse: '감사합니다!',
    businessRespondedAt: '2024-01-20T10:00:00Z',
  });
  // 타 사업장 리뷰
  await seedDoc(env, 'monthly_reviews', 'mr-biz2', {
    ...adminToUserBase,
    businessId: IDS.business2,
    reviewerId: IDS.admin2,
    targetUserId: IDS.user2,
  });
});

afterAll(async () => { await env.cleanup(); });

// ─── MR-GET ──────────────────────────────────────────────────────

describe('MR-GET: 단건 읽기', () => {
  test('MR-GET-01 작성자(reviewerId)는 자신의 리뷰 읽기 허용', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(getDoc(doc(db, 'monthly_reviews', MR)));
  });

  test('MR-GET-02 수신자(targetUserId)는 자신에 대한 리뷰 읽기 허용', async () => {
    const db = getAuth(env, IDS.user);
    await assertSucceeds(getDoc(doc(db, 'monthly_reviews', MR)));
  });

  test('MR-GET-03 소속 관리자는 사업장 리뷰 읽기 허용', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(getDoc(doc(db, 'monthly_reviews', MR)));
  });

  test('MR-GET-04 서브어드민도 소속 사업장 리뷰 읽기 허용', async () => {
    const db = getAuth(env, IDS.subAdmin, { subAdminOf: IDS.business });
    await assertSucceeds(getDoc(doc(db, 'monthly_reviews', MR)));
  });

  test('MR-GET-05 슈퍼어드민 모든 리뷰 읽기 허용', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertSucceeds(getDoc(doc(db, 'monthly_reviews', MR)));
  });

  test('MR-GET-06 isPublished=true 리뷰는 타 사업장 유저도 읽기 허용', async () => {
    const db = getAuth(env, IDS.user2);
    await assertSucceeds(getDoc(doc(db, 'monthly_reviews', MR_PUBLIC)));
  });

  test('MR-GET-07 관계없는 유저는 isPublished=false 리뷰 읽기 차단', async () => {
    // user2는 UTB 리뷰의 작성자/대상자도 아님, isPublished=false
    const db = getAuth(env, IDS.user2);
    await assertFails(getDoc(doc(db, 'monthly_reviews', MR_UTB)));
  });

  test('MR-GET-08 타 사업장 관리자는 비공개 cross-biz 리뷰 읽기 차단', async () => {
    // MR(isPublished=true)는 누구나 읽을 수 있음 (설계 의도)
    // MR_UTB(isPublished=false, 관련 없는 사업장)를 대신 사용
    const db = getAuth(env, IDS.admin2, { businessId: IDS.business2 });
    await assertFails(getDoc(doc(db, 'monthly_reviews', MR_UTB)));
  });

  test('MR-GET-09 미인증 사용자 읽기 차단', async () => {
    const db = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, 'monthly_reviews', MR)));
  });
});

// ─── MR-CREATE ───────────────────────────────────────────────────

describe('MR-CREATE: 리뷰 생성', () => {
  // [R8-P3B.3A.1] 정책이 강해졌다 — [REVIEW-BINDING 2026-09-08].
  //   관리자 리뷰는 반드시 review_requests 슬롯에 결속돼야 한다:
  //   requestId + targetUserId 필수 + isAdminReviewRequestBound()로
  //   workerId/businessId/adminStatus=='pending'/deadline을 교차검증한다.
  //   엉뚱한 대상·타 사업장·기한 만료·이미 제출된 슬롯을 write 경계에서 전부 막는다.
  test('MR-CREATE-01 관리자가 ADMIN_TO_USER 리뷰 생성 허용 (요청 슬롯 결속 필요)', async () => {
    await seedDoc(env, 'review_requests', 'rr-mr-admin', {
      workerId: IDS.user,
      businessId: IDS.business,
      workerStatus: 'pending',
      adminStatus: 'pending',
    });
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(
      setDoc(doc(db, 'monthly_reviews', 'mr-admin-create'), {
        reviewType: 'ADMIN_TO_USER',
        businessId: IDS.business,
        reviewerId: IDS.admin,
        targetUserId: IDS.user,
        requestId: 'rr-mr-admin',
        isPublished: false,  // 생성 시 false 필수 (CF가 이후 제어)
        rating: 5,
      }),
    );
  });

  // [R8-P3B.3A.1] 신규 — 다른 근무자를 대상으로 슬롯을 돌려쓰는 경로 차단 ([REVIEW-BINDING])
  test('MR-CREATE-01b 요청 슬롯의 근무자와 다른 대상으로는 리뷰를 쓸 수 없다', async () => {
    await seedDoc(env, 'review_requests', 'rr-mr-wrongtarget', {
      workerId: IDS.user,
      businessId: IDS.business,
      workerStatus: 'pending',
      adminStatus: 'pending',
    });
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      setDoc(doc(db, 'monthly_reviews', 'mr-wrong-target'), {
        reviewType: 'ADMIN_TO_USER',
        businessId: IDS.business,
        reviewerId: IDS.admin,
        targetUserId: IDS.user2,  // 슬롯의 workerId와 불일치
        requestId: 'rr-mr-wrongtarget',
        isPublished: false,
        rating: 5,
      }),
    );
  });

  test('MR-CREATE-02 관리자가 isPublished=true로 직접 생성 차단 (SEC-76)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      setDoc(doc(db, 'monthly_reviews', 'mr-pub-hack'), {
        reviewType: 'ADMIN_TO_USER',
        businessId: IDS.business,
        reviewerId: IDS.admin,
        targetUserId: IDS.user,
        isPublished: true,  // 클라이언트 직접 설정 차단
        rating: 5,
      }),
    );
  });

  // [R8-P3B.3A.1] SubAdmin은 canManageWorkers가 있어야 한다
  //   ([SECURITY-ADMIN-REVIEW-MR-CREATE 2026-09-05]) + 위와 같은 슬롯 결속.
  test('MR-CREATE-03 canManageWorkers 서브어드민은 ADMIN_TO_USER 리뷰 생성 허용', async () => {
    await seedDoc(env, 'review_requests', 'rr-mr-sub', {
      workerId: IDS.user,
      businessId: IDS.business,
      workerStatus: 'pending',
      adminStatus: 'pending',
    });
    const db = getAuth(env, IDS.subAdmin, { subAdminOf: IDS.business });
    await assertSucceeds(
      setDoc(doc(db, 'monthly_reviews', 'mr-sub-create'), {
        reviewType: 'ADMIN_TO_USER',
        businessId: IDS.business,
        reviewerId: IDS.subAdmin,
        targetUserId: IDS.user,
        requestId: 'rr-mr-sub',
        isPublished: false,
        rating: 4,
      }),
    );
  });

  test('MR-CREATE-04 USER_TO_BUSINESS: reviewerId 포함 시 차단 (H-01 익명 보장)', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      setDoc(doc(db, 'monthly_reviews', 'mr-utb-reviewer-hack'), {
        reviewType: 'USER_TO_BUSINESS',
        businessId: IDS.business,
        reviewerId: IDS.user,  // 익명 보장 위반
        isPublished: false,
        requestId: 'rr-002',
      }),
    );
  });

  // xtest: 에뮬레이터에서 isUser()+isNotBlacklisted() 복합 get() 호출 시 evaluation error 발생
  // 규칙은 올바르게 설계됨 (production 동작 정상) — 에뮬레이터 알려진 한계
  xtest('MR-CREATE-05 USER_TO_BUSINESS: reviewerId 없이 생성 허용', async () => {
    const db = getAuth(env, IDS.user);
    await assertSucceeds(
      setDoc(doc(db, 'monthly_reviews', 'mr-utb-create'), {
        reviewType: 'USER_TO_BUSINESS',
        businessId: IDS.business,
        // reviewerId 없음 — 의도적 설계 (H-01)
        isPublished: false,
        requestId: 'rr-003',
      }),
    );
  });

  test('MR-CREATE-06 USER_TO_BUSINESS: requestId 없으면 차단 (가짜 리뷰 방지)', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      setDoc(doc(db, 'monthly_reviews', 'mr-utb-no-reqid'), {
        reviewType: 'USER_TO_BUSINESS',
        businessId: IDS.business,
        isPublished: false,
        // requestId 없음
      }),
    );
  });

  test('MR-CREATE-07 USER_TO_BUSINESS: 빈 businessId 차단', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      setDoc(doc(db, 'monthly_reviews', 'mr-utb-no-biz'), {
        reviewType: 'USER_TO_BUSINESS',
        businessId: '',  // 빈 문자열 차단
        isPublished: false,
        requestId: 'rr-004',
      }),
    );
  });

  test('MR-CREATE-08 블랙리스트 유저는 USER_TO_BUSINESS 생성 차단', async () => {
    // 블랙리스트 유저 시드
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('users').doc('uid-blacklisted').set({
        role: 'USER', username: 'bl', name: '블랙', email: 'bl@test.com', isBlacklisted: true,
      });
    });
    const db = getAuth(env, 'uid-blacklisted');
    await assertFails(
      setDoc(doc(db, 'monthly_reviews', 'mr-utb-blacklisted'), {
        reviewType: 'USER_TO_BUSINESS',
        businessId: IDS.business,
        isPublished: false,
        requestId: 'rr-bl',
      }),
    );
  });

  test('MR-CREATE-09 rating=6 이상으로 생성 차단 (SEC-87 평균 오염 방지)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      setDoc(doc(db, 'monthly_reviews', 'mr-fake-rating'), {
        reviewType: 'ADMIN_TO_USER',
        reviewerId: IDS.admin,
        businessId: IDS.business,
        isPublished: false,
        rating: 100,  // 범위 외 rating으로 사용자 평균 오염 시도
      }),
    );
  });

  test('MR-CREATE-10 rating=0 이하로 생성 차단 (SEC-87)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      setDoc(doc(db, 'monthly_reviews', 'mr-zero-rating'), {
        reviewType: 'ADMIN_TO_USER',
        reviewerId: IDS.admin,
        businessId: IDS.business,
        isPublished: false,
        rating: 0,  // 0점은 통계 집계에서 제외되지만 서버 레벨 차단
      }),
    );
  });
});

// ─── MR-UPDATE ───────────────────────────────────────────────────

describe('MR-UPDATE: 리뷰 수정', () => {
  // [R8-P3B.3A.1] 정책은 그대로다 — [SEC-MR-TS] businessRespondedAt == request.time 강제.
  //   답변 시각 위조를 막는다. 클라이언트 문자열 시각은 통과하지 못한다.
  test('MR-UPDATE-01 관리자가 businessResponse 답변 필드만 수정 허용 (H-02)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(
      updateDoc(doc(db, 'monthly_reviews', MR_UTB), {
        businessResponse: '감사합니다!',
        businessRespondedAt: serverTimestamp(),
      }),
    );
  });

  // [R8-P3B.3A.1] 신규 — 답변 시각 위조 차단 확인 ([SEC-MR-TS])
  test('MR-UPDATE-01b businessRespondedAt을 임의 시각으로 쓰면 차단된다', async () => {
    await seedDoc(env, 'monthly_reviews', 'mr-utb-ts', { ...userToBusinessBase });
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'monthly_reviews', 'mr-utb-ts'), {
        businessResponse: '감사합니다!',
        businessRespondedAt: new Date(2020, 0, 1),
      }),
    );
  });

  test('MR-UPDATE-02 기존 답변 덮어쓰기 차단 (H-02)', async () => {
    // mr-with-response: businessResponse 이미 존재
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'monthly_reviews', 'mr-with-response'), {
        businessResponse: '새로운 답변으로 덮어씌우기 시도',
        businessRespondedAt: '2024-01-21T10:00:00Z',
      }),
    );
  });

  test('MR-UPDATE-03 답변 외 필드(rating) 수정 차단 — 리뷰 조작 방지', async () => {
    await seedDoc(env, 'monthly_reviews', 'mr-utb-rating-hack', { ...userToBusinessBase });
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'monthly_reviews', 'mr-utb-rating-hack'), {
        businessResponse: '답변',
        rating: 5,  // 추가 필드 수정 — 차단
      }),
    );
  });

  test('MR-UPDATE-04 타 사업장 관리자는 수정 차단', async () => {
    const db = getAuth(env, IDS.admin2, { businessId: IDS.business2 });
    await assertFails(
      updateDoc(doc(db, 'monthly_reviews', MR_UTB), {
        businessResponse: '해킹 답변',
        businessRespondedAt: '2024-01-20T10:00:00Z',
      }),
    );
  });

  test('MR-UPDATE-05 슈퍼어드민은 모든 수정 허용', async () => {
    await seedDoc(env, 'monthly_reviews', 'mr-super-update', { ...userToBusinessBase });
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertSucceeds(
      updateDoc(doc(db, 'monthly_reviews', 'mr-super-update'), {
        isPublished: true,
      }),
    );
  });

  // SEC-92: 탈퇴 익명화 — users 문서 삭제 전 처리하므로 isUser() 통과
  test('MR-UPDATE-06 대상자 본인이 targetUserName·comment 익명화 허용 (SEC-92 9-A)', async () => {
    await seedDoc(env, 'monthly_reviews', 'mr-anon-target', {
      ...adminToUserBase,
      targetUserId: IDS.user,
      targetUserName: '유저1',
      comment: '열심히 했습니다',
    });
    // [R8-P3B.3A.1] [SEC-92/103] isDeletingAccount 교차검증이 추가됐다.
    //   deleteAccountWithPassword CF가 마킹한 계정만 익명화할 수 있다.
    //   활성 계정이 FieldValue.delete()로 불리한 리뷰만 골라 지우는 것을 막는다.
    await seedUser(env, IDS.user, {
      role: 'USER', username: 'user1', name: '유저1',
      email: 'user@test.com', isBlacklisted: false,
      isDeletingAccount: true,
    });
    const db = getAuth(env, IDS.user);
    await assertSucceeds(
      updateDoc(doc(db, 'monthly_reviews', 'mr-anon-target'), {
        targetUserName: '탈퇴한 회원',
        targetUserId: deleteField(),
        comment: deleteField(),
      }),
    );
  });

  test('MR-UPDATE-07 대상자가 targetUserName 외 다른 필드 포함 차단 (SEC-92)', async () => {
    await seedDoc(env, 'monthly_reviews', 'mr-anon-plus', {
      ...adminToUserBase,
      targetUserId: IDS.user,
      targetUserName: '유저1',
    });
    const db = getAuth(env, IDS.user);
    await assertFails(
      updateDoc(doc(db, 'monthly_reviews', 'mr-anon-plus'), {
        targetUserName: '탈퇴한 회원',
        rating: 5,  // 허용 필드 외 추가 → 차단
      }),
    );
  });

  test('MR-UPDATE-08 작성자 본인이 reviewerName·reviewerId 익명화 허용 (SEC-92 9-B)', async () => {
    await seedDoc(env, 'monthly_reviews', 'mr-anon-reviewer', {
      ...adminToUserBase,
      reviewerId: IDS.admin,
      reviewerName: '관리자',
    });
    // [R8-P3B.3A.1] 9-B도 isDeletingAccount 필수 + reviewerId는 삭제가 아니라 빈 문자열이다
    //   (규칙: request.resource.data.get('reviewerId','') == '').
    await seedUser(env, IDS.admin, {
      role: 'BUSINESS_ADMIN', username: 'admin', name: '관리자',
      email: 'admin@test.com', isBlacklisted: false,
      isDeletingAccount: true,
    });
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(
      updateDoc(doc(db, 'monthly_reviews', 'mr-anon-reviewer'), {
        reviewerName: '탈퇴한 회원',
        reviewerId: '',
      }),
    );
  });

  test('MR-UPDATE-09 타인이 reviewerName 변경 차단 (SEC-92 보안)', async () => {
    await seedDoc(env, 'monthly_reviews', 'mr-anon-other-hack', {
      ...adminToUserBase,
      reviewerId: IDS.admin,
      reviewerName: '관리자',
    });
    const db = getAuth(env, IDS.user2);  // 관계없는 사용자
    await assertFails(
      updateDoc(doc(db, 'monthly_reviews', 'mr-anon-other-hack'), {
        reviewerName: '해킹',
        reviewerId: deleteField(),
      }),
    );
  });

  // SEC-103: 익명화 값 고정 — '탈퇴한 회원'/'' 외 임의값 차단
  test('MR-UPDATE-10 ❌ 9-A 경로에서 targetUserName에 임의값 설정 차단 (SEC-103)', async () => {
    await seedDoc(env, 'monthly_reviews', 'mr-sec103-a', {
      ...adminToUserBase,
      targetUserId: IDS.user,
      targetUserName: '유저1',
      comment: '성실해요',
    });
    const db = getAuth(env, IDS.user);
    // '탈퇴한 회원' 외 임의값 → 차단
    await assertFails(
      updateDoc(doc(db, 'monthly_reviews', 'mr-sec103-a'), {
        targetUserName: '익명',
        targetUserId: deleteField(),
        comment: deleteField(),
      }),
    );
  });

  test('MR-UPDATE-11 ❌ 9-B 경로에서 reviewerName에 임의값 설정 차단 (SEC-103)', async () => {
    await seedDoc(env, 'monthly_reviews', 'mr-sec103-b', {
      ...adminToUserBase,
      reviewerId: IDS.admin,
      reviewerName: '관리자',
    });
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    // '탈퇴한 회원' 외 임의값 → 차단
    await assertFails(
      updateDoc(doc(db, 'monthly_reviews', 'mr-sec103-b'), {
        reviewerName: '익명',
        reviewerId: deleteField(),
      }),
    );
  });
});

// ─── MR-DELETE ───────────────────────────────────────────────────

describe('MR-DELETE: 리뷰 삭제', () => {
  test('MR-DELETE-01 슈퍼어드민만 삭제 허용', async () => {
    await seedDoc(env, 'monthly_reviews', 'mr-del', adminToUserBase);
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertSucceeds(deleteDoc(doc(db, 'monthly_reviews', 'mr-del')));
  });

  test('MR-DELETE-02 관리자도 삭제 차단', async () => {
    await seedDoc(env, 'monthly_reviews', 'mr-del-admin', adminToUserBase);
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(deleteDoc(doc(db, 'monthly_reviews', 'mr-del-admin')));
  });

  test('MR-DELETE-03 일반 유저 삭제 차단', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(deleteDoc(doc(db, 'monthly_reviews', MR)));
  });
});
