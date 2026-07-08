// rules-test/src/rules/review_requests.test.ts
// review_requests 컬렉션 보안 규칙 검증
import { RulesTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, getDoc, getDocs, collection, query, where, setDoc, updateDoc, deleteDoc } from 'firebase/firestore';
import {
  createTestEnv, getAuth, seedDoc, seedCommonFixtures,
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
  // xtest: 에뮬레이터에서 isAdminOf() get() 호출 시 evaluation error — 에뮬레이터 한계
  xtest('RR-CREATE-01 관리자가 소속 사업장에 생성 허용', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(
      setDoc(doc(db, 'review_requests', 'rr-new-admin'), {
        businessId: IDS.business,
        workerId: IDS.user,
        workerName: '유저1',
        workerStatus: 'PENDING',
        adminStatus: 'PENDING',
      }),
    );
  });

  // xtest: 에뮬레이터 isSubAdminOf() evaluation error
  xtest('RR-CREATE-02 서브어드민도 소속 사업장에 생성 허용', async () => {
    const db = getAuth(env, IDS.subAdmin, { subAdminOf: IDS.business });
    await assertSucceeds(
      setDoc(doc(db, 'review_requests', 'rr-new-sub'), {
        businessId: IDS.business,
        workerId: IDS.user,
        workerName: '유저1',
        workerStatus: 'PENDING',
        adminStatus: 'PENDING',
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
        workerStatus: 'SUBMITTED',
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

  test('RR-UPDATE-03 관리자가 adminStatus·adminReviewId 변경 허용', async () => {
    await seedDoc(env, 'review_requests', 'rr-admin-update', { ...rrBase });
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(
      updateDoc(doc(db, 'review_requests', 'rr-admin-update'), {
        adminStatus: 'COMPLETED',
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
  test('RR-UPDATE-05 탈퇴 익명화: 본인이 workerName만 변경 허용 (SEC-88)', async () => {
    await seedDoc(env, 'review_requests', 'rr-anonymize', { ...rrBase });
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
