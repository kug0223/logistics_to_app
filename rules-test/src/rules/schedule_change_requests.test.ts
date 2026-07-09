// rules-test/src/rules/schedule_change_requests.test.ts
// schedule_change_requests 컬렉션 보안 규칙 검증 (22개 시나리오)
import { RulesTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc } from 'firebase/firestore';
import {
  createTestEnv, getAuth, seedDoc, seedCommonFixtures,
  assertFails, assertSucceeds, IDS,
} from '../helpers/test-env';

let env: RulesTestEnvironment;

const SCR = 'scr-001';

const baseReq = {
  applicantUid: IDS.user,
  businessId: IDS.business,
  applicationId: 'app-scr-001',
  type: 'ADDITIONAL_WORK',
  status: 'PENDING',
  requestedAt: '2024-01-15T09:00:00Z',
};

beforeAll(async () => {
  env = await createTestEnv('schedule_change_requests');
  await seedCommonFixtures(env);

  // user에 businessId 세팅 (소속 검증)
  await seedDoc(env, 'users', IDS.user, {
    role: 'USER', username: 'user1', name: '유저1',
    email: 'user@test.com', isBlacklisted: false,
    businessId: IDS.business,
  });

  await seedDoc(env, 'schedule_change_requests', SCR, baseReq);

  // 블랙리스트된 유저 (SCR-CREATE-06 검증용)
  await seedDoc(env, 'users', 'uid-blacklisted', {
    role: 'USER', username: 'blocked', name: '블랙리스트',
    email: 'blocked@test.com', isBlacklisted: true,
    businessId: IDS.business,
  });

  // APPROVED 상태 (역변조 차단 검증)
  await seedDoc(env, 'schedule_change_requests', 'scr-approved', {
    ...baseReq, status: 'APPROVED',
  });

  // 타 사업장 요청
  await seedDoc(env, 'schedule_change_requests', 'scr-biz2', {
    ...baseReq, applicantUid: IDS.user2, businessId: IDS.business2,
  });
});

afterAll(async () => { await env.cleanup(); });

// ─── SCR-GET ──────────────────────────────────────────────────────────

describe('SCR-GET: 단건 읽기', () => {
  test('SCR-GET-01 지원자 본인은 자신의 요청을 읽을 수 있다', async () => {
    const db = getAuth(env, IDS.user);
    await assertSucceeds(getDoc(doc(db, 'schedule_change_requests', SCR)));
  });

  test('SCR-GET-02 소속 관리자는 요청을 읽을 수 있다', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(getDoc(doc(db, 'schedule_change_requests', SCR)));
  });

  test('SCR-GET-03 서브어드민도 읽을 수 있다', async () => {
    const db = getAuth(env, IDS.subAdmin, { subAdminOf: IDS.business });
    await assertSucceeds(getDoc(doc(db, 'schedule_change_requests', SCR)));
  });

  test('SCR-GET-04 타 사업장 관리자는 읽을 수 없다', async () => {
    const db = getAuth(env, IDS.admin2, { businessId: IDS.business2 });
    await assertFails(getDoc(doc(db, 'schedule_change_requests', SCR)));
  });

  test('SCR-GET-05 관계없는 일반유저는 읽을 수 없다', async () => {
    const db = getAuth(env, IDS.user2);
    await assertFails(getDoc(doc(db, 'schedule_change_requests', SCR)));
  });
});

// ─── SCR-CREATE ───────────────────────────────────────────────────────

describe('SCR-CREATE: 요청 생성', () => {
  test('SCR-CREATE-01 본인이 소속 사업장 businessId로 생성 허용', async () => {
    const db = getAuth(env, IDS.user);
    await assertSucceeds(
      setDoc(doc(db, 'schedule_change_requests', 'scr-user-new'), {
        applicantUid: IDS.user,
        requestedByUid: IDS.user,  // SEC-80: 규칙 필수 필드
        businessId: IDS.business,  // users/{user}.businessId 와 일치
        applicationId: 'app-001',
        type: 'ADDITIONAL_WORK',
        status: 'PENDING',
      }),
    );
  });

  test('SCR-CREATE-02 본인이 타 사업장 businessId로 생성 차단 (SEC-72)', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      setDoc(doc(db, 'schedule_change_requests', 'scr-cross-biz'), {
        applicantUid: IDS.user,
        businessId: IDS.business2,  // 소속 아닌 사업장
        applicationId: 'app-001',
        type: 'ADDITIONAL_WORK',
        status: 'PENDING',
      }),
    );
  });

  test('SCR-CREATE-03 빈 businessId로 생성 차단 (MED-BYPASS-FIX)', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      setDoc(doc(db, 'schedule_change_requests', 'scr-empty-biz'), {
        applicantUid: IDS.user,
        businessId: '',  // 빈 문자열 bypass 차단
        applicationId: 'app-001',
        type: 'ADDITIONAL_WORK',
        status: 'PENDING',
      }),
    );
  });

  test('SCR-CREATE-04 관리자는 추가근무 요청을 직접 생성할 수 있다', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(
      setDoc(doc(db, 'schedule_change_requests', 'scr-admin-new'), {
        applicantUid: IDS.user,
        businessId: IDS.business,
        applicationId: 'app-001',
        type: 'NO_SHOW',
        status: 'PENDING',
      }),
    );
  });

  test('SCR-CREATE-05 서브어드민도 요청을 생성할 수 있다', async () => {
    const db = getAuth(env, IDS.subAdmin, { subAdminOf: IDS.business });
    await assertSucceeds(
      setDoc(doc(db, 'schedule_change_requests', 'scr-sub-new'), {
        applicantUid: IDS.user,
        businessId: IDS.business,
        applicationId: 'app-001',
        type: 'ADDITIONAL_WORK',
        status: 'PENDING',
      }),
    );
  });

  test('SCR-CREATE-06 블랙리스트 사용자는 요청을 생성할 수 없다', async () => {
    // isNotBlacklisted() 검사 — isBlacklisted:true 인 사용자는 create 차단
    const db = getAuth(env, 'uid-blacklisted');
    await assertFails(
      setDoc(doc(db, 'schedule_change_requests', 'scr-blacklisted-new'), {
        applicantUid: 'uid-blacklisted',
        requestedByUid: 'uid-blacklisted',
        businessId: IDS.business,
        applicationId: 'app-001',
        type: 'ADDITIONAL_WORK',
        status: 'PENDING',
      }),
    );
  });
});

// ─── SCR-UPDATE ───────────────────────────────────────────────────────

describe('SCR-UPDATE: 상태 전이', () => {
  test('SCR-UPDATE-01 워커는 PENDING→CANCELED 전환 허용 (SEC-12)', async () => {
    const db = getAuth(env, IDS.user);
    await assertSucceeds(
      updateDoc(doc(db, 'schedule_change_requests', SCR), {
        status: 'CANCELED',
        respondedByUid: IDS.user,
        respondedAt: '2024-01-15T10:00:00Z',
      }),
    );
  });

  test('SCR-UPDATE-02 워커는 APPROVED 상태에서 CANCELED 전환 차단 (SEC-12)', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      updateDoc(doc(db, 'schedule_change_requests', 'scr-approved'), {
        status: 'CANCELED',
        respondedByUid: IDS.user,
        respondedAt: '2024-01-15T10:00:00Z',
      }),
    );
  });

  test('SCR-UPDATE-03 워커는 PENDING→APPROVED 직접 전환 차단', async () => {
    // SCR은 이미 CANCELED로 바뀌었으므로 별도 문서 사용
    await seedDoc(env, 'schedule_change_requests', 'scr-worker-approve', baseReq);
    const db = getAuth(env, IDS.user);
    await assertFails(
      updateDoc(doc(db, 'schedule_change_requests', 'scr-worker-approve'), {
        status: 'APPROVED',
        respondedByUid: IDS.user,
        respondedAt: '2024-01-15T10:00:00Z',
      }),
    );
  });

  test('SCR-UPDATE-04 관리자는 PENDING→APPROVED 허용', async () => {
    await seedDoc(env, 'schedule_change_requests', 'scr-admin-approve', baseReq);
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(
      updateDoc(doc(db, 'schedule_change_requests', 'scr-admin-approve'), {
        status: 'APPROVED',
        respondedByUid: IDS.admin,
        respondedAt: '2024-01-15T10:00:00Z',
      }),
    );
  });

  test('SCR-UPDATE-05 관리자는 PENDING→REJECTED 허용', async () => {
    await seedDoc(env, 'schedule_change_requests', 'scr-admin-reject', baseReq);
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(
      updateDoc(doc(db, 'schedule_change_requests', 'scr-admin-reject'), {
        status: 'REJECTED',
        respondedByUid: IDS.admin,
        respondedAt: '2024-01-15T10:00:00Z',
        rejectReason: '인원 초과',
      }),
    );
  });

  test('SCR-UPDATE-06 관리자는 APPROVED→REJECTED 역변조 차단 (SEC-51)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'schedule_change_requests', 'scr-approved'), {
        status: 'REJECTED',
        respondedByUid: IDS.admin,
        respondedAt: '2024-01-15T10:00:00Z',
      }),
    );
  });

  test('SCR-UPDATE-07 타 사업장 관리자는 상태 변경 차단', async () => {
    await seedDoc(env, 'schedule_change_requests', 'scr-cross-update', baseReq);
    const db = getAuth(env, IDS.admin2, { businessId: IDS.business2 });
    await assertFails(
      updateDoc(doc(db, 'schedule_change_requests', 'scr-cross-update'), {
        status: 'APPROVED',
        respondedByUid: IDS.admin2,
        respondedAt: '2024-01-15T10:00:00Z',
      }),
    );
  });

  test('SCR-UPDATE-08 관리자는 APPROVED→CANCELED 허용 (승인 취소)', async () => {
    await seedDoc(env, 'schedule_change_requests', 'scr-admin-cancel-approved', {
      ...baseReq, status: 'APPROVED',
    });
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(
      updateDoc(doc(db, 'schedule_change_requests', 'scr-admin-cancel-approved'), {
        status: 'CANCELED',
        respondedByUid: IDS.admin,
        respondedAt: '2024-01-15T10:00:00Z',
      }),
    );
  });

  test('SCR-UPDATE-09 서브어드민도 APPROVED→CANCELED 허용', async () => {
    await seedDoc(env, 'schedule_change_requests', 'scr-sub-cancel-approved', {
      ...baseReq, status: 'APPROVED',
    });
    const db = getAuth(env, IDS.subAdmin, { subAdminOf: IDS.business });
    await assertSucceeds(
      updateDoc(doc(db, 'schedule_change_requests', 'scr-sub-cancel-approved'), {
        status: 'CANCELED',
        respondedByUid: IDS.subAdmin,
        respondedAt: '2024-01-15T10:00:00Z',
      }),
    );
  });
});

// ─── SCR-DELETE ───────────────────────────────────────────────────────

describe('SCR-DELETE: 요청 삭제', () => {
  test('SCR-DELETE-01 관리자는 소속 사업장 요청 삭제 허용', async () => {
    await seedDoc(env, 'schedule_change_requests', 'scr-del-admin', baseReq);
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(deleteDoc(doc(db, 'schedule_change_requests', 'scr-del-admin')));
  });

  test('SCR-DELETE-02 서브어드민도 삭제 허용', async () => {
    await seedDoc(env, 'schedule_change_requests', 'scr-del-sub', baseReq);
    const db = getAuth(env, IDS.subAdmin, { subAdminOf: IDS.business });
    await assertSucceeds(deleteDoc(doc(db, 'schedule_change_requests', 'scr-del-sub')));
  });

  test('SCR-DELETE-03 워커는 요청 삭제 차단', async () => {
    await seedDoc(env, 'schedule_change_requests', 'scr-del-user', baseReq);
    const db = getAuth(env, IDS.user);
    await assertFails(deleteDoc(doc(db, 'schedule_change_requests', 'scr-del-user')));
  });
});
