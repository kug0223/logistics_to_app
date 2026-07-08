// rules-test/src/rules/payroll.test.ts
// payroll_summaries + deleted_accounts + _processedWageEvents + passwordResetCodes (20개 시나리오)
import {
  RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  deleteDoc,
} from 'firebase/firestore';
import {
  createTestEnv,
  getAuth,
  seedDoc,
  seedCommonFixtures,
  assertFails,
  assertSucceeds,
  IDS,
} from '../helpers/test-env';

let env: RulesTestEnvironment;

beforeAll(async () => {
  env = await createTestEnv('payroll');
  await seedCommonFixtures(env);

  // payroll_summaries 시드
  await seedDoc(env, 'payroll_summaries', 'ps-2024-01', {
    businessId: IDS.business,
    month: '2024-01',
    totalWage: 5000000,
    workerCount: 5,
  });

  await seedDoc(env, 'payroll_summaries', 'ps-2024-01-biz2', {
    businessId: IDS.business2,
    month: '2024-01',
    totalWage: 3000000,
    workerCount: 3,
  });

  // deleted_accounts 시드
  await seedDoc(env, 'deleted_accounts', 'del-user-001', {
    uid: 'ex-user-001',
    username: 'deleted_user',
    deletedAt: '2024-01-01T00:00:00Z',
    reason: 'user_request',
  });

  // _processedWageEvents 시드
  await seedDoc(env, '_processedWageEvents', 'evt-001', {
    eventId: 'wage-evt-001',
    processedAt: '2024-01-01T00:00:00Z',
  });

  // passwordResetCodes 시드
  await seedDoc(env, 'passwordResetCodes', 'test-user', {
    code: '123456',
    expiresAt: '2024-01-01T00:10:00Z',
  });
});

afterAll(async () => {
  await env.cleanup();
});

// ─── PAYROLL_SUMMARIES: 급여 집계 읽기 ──────────────────────────────

describe('PAYROLL_SUMMARIES: 급여 집계 단건 읽기', () => {
  test('PS-GET-01 소속 사업장 관리자는 급여 집계를 읽을 수 있다', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(getDoc(doc(db, 'payroll_summaries', 'ps-2024-01')));
  });

  test('PS-GET-02 서브어드민도 급여 집계를 읽을 수 있다', async () => {
    const db = getAuth(env, IDS.subAdmin, { subAdminOf: IDS.business });
    await assertSucceeds(getDoc(doc(db, 'payroll_summaries', 'ps-2024-01')));
  });

  test('PS-GET-03 슈퍼어드민은 모든 급여 집계를 읽을 수 있다', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertSucceeds(getDoc(doc(db, 'payroll_summaries', 'ps-2024-01')));
  });

  test('PS-GET-04 타 사업장 관리자는 급여 집계를 읽을 수 없다', async () => {
    const db = getAuth(env, IDS.admin2, { businessId: IDS.business2 });
    await assertFails(getDoc(doc(db, 'payroll_summaries', 'ps-2024-01')));
  });

  test('PS-GET-05 일반유저는 급여 집계를 읽을 수 없다', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(getDoc(doc(db, 'payroll_summaries', 'ps-2024-01')));
  });

  test('PS-GET-06 미인증 사용자는 급여 집계를 읽을 수 없다', async () => {
    const db = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, 'payroll_summaries', 'ps-2024-01')));
  });
});

// ─── PAYROLL_SUMMARIES: CF 전용 쓰기 차단 ────────────────────────────

describe('PAYROLL_SUMMARIES: CF Admin SDK 전용 쓰기 차단', () => {
  test('PS-WRITE-01 관리자도 payroll_summaries 생성 차단 (CF 전용)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      setDoc(doc(db, 'payroll_summaries', 'ps-fake'), {
        businessId: IDS.business,
        month: '2024-02',
        totalWage: 9999999,
      }),
    );
  });

  test('PS-WRITE-02 슈퍼어드민도 payroll_summaries 직접 수정 차단', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertFails(
      updateDoc(doc(db, 'payroll_summaries', 'ps-2024-01'), {
        totalWage: 0,
      }),
    );
  });

  test('PS-WRITE-03 슈퍼어드민도 payroll_summaries 직접 삭제 차단', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertFails(
      deleteDoc(doc(db, 'payroll_summaries', 'ps-2024-01')),
    );
  });
});

// ─── DELETED_ACCOUNTS: 탈퇴 계정 보호 ───────────────────────────────

describe('DELETED_ACCOUNTS: 탈퇴 계정 접근 제어', () => {
  test('DA-READ-01 슈퍼어드민은 탈퇴 계정을 읽을 수 있다', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertSucceeds(getDoc(doc(db, 'deleted_accounts', 'del-user-001')));
  });

  test('DA-READ-02 관리자는 탈퇴 계정을 읽을 수 없다 (AUTH-H2)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(getDoc(doc(db, 'deleted_accounts', 'del-user-001')));
  });

  test('DA-READ-03 일반유저는 탈퇴 계정을 읽을 수 없다', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(getDoc(doc(db, 'deleted_accounts', 'del-user-001')));
  });

  test('DA-CREATE-01 클라이언트는 deleted_accounts 생성 완전 차단 (AUTH-H2)', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertFails(
      setDoc(doc(db, 'deleted_accounts', 'del-fake'), {
        uid: 'fake-uid',
        deletedAt: '2024-01-01T00:00:00Z',
      }),
    );
  });

  test('DA-UPDATE-01 슈퍼어드민은 탈퇴 계정을 수정할 수 있다', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertSucceeds(
      updateDoc(doc(db, 'deleted_accounts', 'del-user-001'), {
        note: '블랙리스트 추가',
      }),
    );
  });

  test('DA-UPDATE-02 관리자는 탈퇴 계정을 수정할 수 없다', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'deleted_accounts', 'del-user-001'), {
        note: '임의 수정',
      }),
    );
  });
});

// ─── _PROCESSEDWAGEEVENTS: CF 내부 컬렉션 완전 차단 ─────────────────

describe('_PROCESSEDWAGEEVENTS: CF 내부 컬렉션 접근 완전 차단 (SEC-01)', () => {
  test('PWE-READ-01 슈퍼어드민도 _processedWageEvents를 읽을 수 없다', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertFails(getDoc(doc(db, '_processedWageEvents', 'evt-001')));
  });

  test('PWE-READ-02 관리자도 _processedWageEvents를 읽을 수 없다', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(getDoc(doc(db, '_processedWageEvents', 'evt-001')));
  });

  test('PWE-WRITE-01 모든 클라이언트의 _processedWageEvents 쓰기 차단', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertFails(
      setDoc(doc(db, '_processedWageEvents', 'evt-fake'), {
        eventId: 'fake-event',
      }),
    );
  });
});

// ─── PASSWORDRESETCODES: CF 전용 접근 차단 ───────────────────────────

describe('PASSWORDRESETCODES: 비밀번호 재설정 코드 접근 차단', () => {
  test('PRC-READ-01 슈퍼어드민도 passwordResetCodes를 읽을 수 없다', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertFails(getDoc(doc(db, 'passwordResetCodes', 'test-user')));
  });

  test('PRC-WRITE-01 모든 클라이언트의 passwordResetCodes 쓰기 차단', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertFails(
      setDoc(doc(db, 'passwordResetCodes', 'fake-user'), {
        code: '999999',
      }),
    );
  });
});
