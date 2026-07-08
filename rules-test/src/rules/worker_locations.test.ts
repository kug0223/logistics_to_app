// rules-test/src/rules/worker_locations.test.ts
// worker_locations 컬렉션 보안 규칙 검증 (18개 시나리오)
// 위치 정보는 개인정보보호법 상 민감 정보 — 엄격한 소속 검증
import { RulesTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc } from 'firebase/firestore';
import {
  createTestEnv, getAuth, seedDoc, seedCommonFixtures,
  assertFails, assertSucceeds, IDS,
} from '../helpers/test-env';

let env: RulesTestEnvironment;

const LOC = 'app-loc-001';  // 문서 ID = applicationId

const baseLoc = {
  userId: IDS.user,
  businessId: IDS.business,
  applicationId: LOC,
  latitude: 37.5665,
  longitude: 126.978,
  updatedAt: '2024-01-15T09:30:00Z',
};

beforeAll(async () => {
  env = await createTestEnv('worker_locations');
  await seedCommonFixtures(env);

  // user에 businessId 세팅 (SEC-34 businessId 소속 검증용)
  await env.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('users').doc(IDS.user).set({
      role: 'USER', username: 'user1', name: '유저1',
      email: 'user@test.com', isBlacklisted: false,
      businessId: IDS.business,
    });
  });

  await seedDoc(env, 'worker_locations', LOC, baseLoc);

  // LOC-CREATE-01 검증용 지원서 (규칙이 applications/{applicationId}.uid == auth.uid 검증)
  await seedDoc(env, 'applications', 'app-loc-new', {
    uid: IDS.user,
    businessId: IDS.business,
    toId: IDS.to,
    status: 'CONFIRMED',
  });

  // 타 사업장 위치
  await seedDoc(env, 'worker_locations', 'app-loc-biz2', {
    ...baseLoc,
    userId: IDS.user2,
    businessId: IDS.business2,
    applicationId: 'app-loc-biz2',
  });
});

afterAll(async () => { await env.cleanup(); });

// ─── LOC-GET ─────────────────────────────────────────────────────

describe('LOC-GET: 단건 읽기', () => {
  test('LOC-GET-01 본인(userId)은 자신의 위치 읽기 허용', async () => {
    const db = getAuth(env, IDS.user);
    await assertSucceeds(getDoc(doc(db, 'worker_locations', LOC)));
  });

  test('LOC-GET-02 소속 관리자는 읽기 허용', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(getDoc(doc(db, 'worker_locations', LOC)));
  });

  test('LOC-GET-03 서브어드민도 읽기 허용', async () => {
    const db = getAuth(env, IDS.subAdmin, { subAdminOf: IDS.business });
    await assertSucceeds(getDoc(doc(db, 'worker_locations', LOC)));
  });

  test('LOC-GET-04 슈퍼어드민 읽기 허용', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertSucceeds(getDoc(doc(db, 'worker_locations', LOC)));
  });

  test('LOC-GET-05 타 사업장 관리자는 cross-biz 위치 읽기 차단', async () => {
    const db = getAuth(env, IDS.admin2, { businessId: IDS.business2 });
    await assertFails(getDoc(doc(db, 'worker_locations', LOC)));
  });

  test('LOC-GET-06 관계없는 유저는 타인 위치 읽기 차단', async () => {
    const db = getAuth(env, IDS.user2);
    await assertFails(getDoc(doc(db, 'worker_locations', LOC)));
  });
});

// ─── LOC-CREATE ──────────────────────────────────────────────────

describe('LOC-CREATE: 위치 생성', () => {
  test('LOC-CREATE-01 본인이 소속 businessId로 위치 생성 허용 (SEC-34)', async () => {
    const db = getAuth(env, IDS.user);
    await assertSucceeds(
      setDoc(doc(db, 'worker_locations', 'app-loc-new'), {
        userId: IDS.user,
        businessId: IDS.business,  // users/{user}.businessId 와 일치
        applicationId: 'app-loc-new',
        latitude: 37.5665,
        longitude: 126.978,
      }),
    );
  });

  test('LOC-CREATE-02 타인의 userId로 위치 생성 차단', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      setDoc(doc(db, 'worker_locations', 'app-loc-fake-user'), {
        userId: IDS.user2,  // 타인 명의 위조
        businessId: IDS.business,
        applicationId: 'app-loc-fake-user',
        latitude: 37.5665,
        longitude: 126.978,
      }),
    );
  });

  test('LOC-CREATE-03 타 사업장 businessId로 위치 생성 차단 (SEC-34)', async () => {
    // user의 실제 businessId는 IDS.business — biz-002로는 차단
    const db = getAuth(env, IDS.user);
    await assertFails(
      setDoc(doc(db, 'worker_locations', 'app-loc-cross-biz'), {
        userId: IDS.user,
        businessId: IDS.business2,  // 소속 아닌 사업장
        applicationId: 'app-loc-cross-biz',
        latitude: 37.5665,
        longitude: 126.978,
      }),
    );
  });
});

// ─── LOC-UPDATE ──────────────────────────────────────────────────

describe('LOC-UPDATE: 위치 수정', () => {
  test('LOC-UPDATE-01 본인은 위치 데이터 수정 허용', async () => {
    const db = getAuth(env, IDS.user);
    await assertSucceeds(
      updateDoc(doc(db, 'worker_locations', LOC), {
        latitude: 37.567,
        longitude: 126.979,
        updatedAt: '2024-01-15T10:00:00Z',
      }),
    );
  });

  test('LOC-UPDATE-02 userId 변경 차단 (M-1 식별자 불변)', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      updateDoc(doc(db, 'worker_locations', LOC), {
        userId: IDS.user2,  // userId 변조 차단
        latitude: 37.567,
      }),
    );
  });

  test('LOC-UPDATE-03 businessId 변경 차단 (M-1 식별자 불변)', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      updateDoc(doc(db, 'worker_locations', LOC), {
        businessId: IDS.business2,  // businessId 변조 차단
        latitude: 37.567,
      }),
    );
  });

  test('LOC-UPDATE-04 applicationId 변경 차단 (M-1 식별자 불변)', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      updateDoc(doc(db, 'worker_locations', LOC), {
        applicationId: 'fake-app-id',  // applicationId 변조 차단
        latitude: 37.567,
      }),
    );
  });

  test('LOC-UPDATE-05 관리자는 직접 수정 차단 (본인 또는 슈퍼어드민만 허용)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'worker_locations', LOC), {
        latitude: 37.0,
      }),
    );
  });
});

// ─── LOC-DELETE ──────────────────────────────────────────────────

describe('LOC-DELETE: 위치 삭제', () => {
  test('LOC-DELETE-01 본인은 자신의 위치 삭제 허용', async () => {
    await seedDoc(env, 'worker_locations', 'loc-del-own', baseLoc);
    const db = getAuth(env, IDS.user);
    await assertSucceeds(deleteDoc(doc(db, 'worker_locations', 'loc-del-own')));
  });

  test('LOC-DELETE-02 슈퍼어드민은 삭제 허용', async () => {
    await seedDoc(env, 'worker_locations', 'loc-del-super', baseLoc);
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertSucceeds(deleteDoc(doc(db, 'worker_locations', 'loc-del-super')));
  });

  test('LOC-DELETE-03 관리자는 삭제 차단', async () => {
    await seedDoc(env, 'worker_locations', 'loc-del-admin', baseLoc);
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(deleteDoc(doc(db, 'worker_locations', 'loc-del-admin')));
  });
});
