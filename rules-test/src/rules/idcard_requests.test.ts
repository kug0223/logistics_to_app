// rules-test/src/rules/idcard_requests.test.ts
// idCardAccessRequests 컬렉션 보안 규칙 검증 (22개 시나리오)
import { RulesTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc } from 'firebase/firestore';
import {
  createTestEnv, getAuth, seedDoc, seedCommonFixtures,
  assertFails, assertSucceeds, IDS,
} from '../helpers/test-env';

let env: RulesTestEnvironment;

const ICAR = 'icar-001';

const baseReq = {
  requesterId: IDS.admin,
  requesterBusinessId: IDS.business,
  targetUserId: IDS.user,
  applicationId: 'app-icar-001',
  status: 'pending',
  requestedAt: '2024-01-15T09:00:00Z',
};

beforeAll(async () => {
  env = await createTestEnv('idcard_requests');
  await seedCommonFixtures(env);

  await seedDoc(env, 'idCardAccessRequests', ICAR, baseReq);

  // approved 상태 (역변조 차단 검증)
  await seedDoc(env, 'idCardAccessRequests', 'icar-approved', {
    ...baseReq, status: 'approved', expiresAt: '2024-01-22T09:00:00Z',
  });

  // 타 사업장 요청
  await seedDoc(env, 'idCardAccessRequests', 'icar-biz2', {
    ...baseReq,
    requesterId: IDS.admin2,
    requesterBusinessId: IDS.business2,
    targetUserId: IDS.user2,
  });
});

afterAll(async () => { await env.cleanup(); });

// ─── ICAR-GET ─────────────────────────────────────────────────────────

describe('ICAR-GET: 단건 읽기', () => {
  test('ICAR-GET-01 요청자(requesterId)는 자신의 요청을 읽을 수 있다', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(getDoc(doc(db, 'idCardAccessRequests', ICAR)));
  });

  test('ICAR-GET-02 수신자(targetUserId)는 자신에게 온 요청을 읽을 수 있다', async () => {
    const db = getAuth(env, IDS.user);
    await assertSucceeds(getDoc(doc(db, 'idCardAccessRequests', ICAR)));
  });

  test('ICAR-GET-03 슈퍼어드민은 모든 요청을 읽을 수 있다', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertSucceeds(getDoc(doc(db, 'idCardAccessRequests', ICAR)));
  });

  test('ICAR-GET-04 관계없는 관리자(타 사업장)는 읽을 수 없다', async () => {
    // admin2는 requesterId도 targetUserId도 아님
    const db = getAuth(env, IDS.admin2, { businessId: IDS.business2 });
    await assertFails(getDoc(doc(db, 'idCardAccessRequests', ICAR)));
  });

  test('ICAR-GET-05 관계없는 일반유저는 읽을 수 없다', async () => {
    const db = getAuth(env, IDS.user2);
    await assertFails(getDoc(doc(db, 'idCardAccessRequests', ICAR)));
  });

  test('ICAR-GET-06 미인증 사용자는 읽을 수 없다', async () => {
    const db = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, 'idCardAccessRequests', ICAR)));
  });
});

// ─── ICAR-CREATE ──────────────────────────────────────────────────────

describe('ICAR-CREATE: 신분증 열람 요청 생성', () => {
  test('ICAR-CREATE-01 관리자가 본인 requesterId, 소속 businessId로 요청 생성 허용', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(
      setDoc(doc(db, 'idCardAccessRequests', 'icar-admin-new'), {
        requesterId: IDS.admin,
        requesterBusinessId: IDS.business,
        targetUserId: IDS.user,
        applicationId: 'app-001',
        status: 'pending',
      }),
    );
  });

  test('ICAR-CREATE-02 서브어드민도 요청 생성 허용', async () => {
    const db = getAuth(env, IDS.subAdmin, { subAdminOf: IDS.business });
    await assertSucceeds(
      setDoc(doc(db, 'idCardAccessRequests', 'icar-sub-new'), {
        requesterId: IDS.subAdmin,
        requesterBusinessId: IDS.business,
        targetUserId: IDS.user,
        applicationId: 'app-001',
        status: 'pending',
      }),
    );
  });

  test('ICAR-CREATE-03 requesterId 위조 차단 (H-7)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      setDoc(doc(db, 'idCardAccessRequests', 'icar-fake-requester'), {
        requesterId: IDS.user,  // 타인 명의로 위조
        requesterBusinessId: IDS.business,
        targetUserId: IDS.user2,
        applicationId: 'app-001',
        status: 'pending',
      }),
    );
  });

  test('ICAR-CREATE-04 타 사업장 명의로 요청 생성 차단', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      setDoc(doc(db, 'idCardAccessRequests', 'icar-cross-biz'), {
        requesterId: IDS.admin,
        requesterBusinessId: IDS.business2,  // 소속 아닌 사업장
        targetUserId: IDS.user,
        applicationId: 'app-001',
        status: 'pending',
      }),
    );
  });

  test('ICAR-CREATE-05 일반유저는 신분증 열람 요청 생성 차단', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      setDoc(doc(db, 'idCardAccessRequests', 'icar-user-create'), {
        requesterId: IDS.user,
        requesterBusinessId: IDS.business,
        targetUserId: IDS.user2,
        applicationId: 'app-001',
        status: 'pending',
      }),
    );
  });

  test('ICAR-CREATE-06 관리자가 status=approved로 직접 생성 차단 (SEC-81)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      setDoc(doc(db, 'idCardAccessRequests', 'icar-fake-approved'), {
        requesterId: IDS.admin,
        requesterBusinessId: IDS.business,
        targetUserId: IDS.user,
        applicationId: 'app-001',
        status: 'approved',  // pending이 아닌 상태로 직접 생성 시도
      }),
    );
  });

  test('ICAR-CREATE-07 관리자가 expiresAt 포함하여 직접 생성 차단 (SEC-81)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      setDoc(doc(db, 'idCardAccessRequests', 'icar-fake-expires'), {
        requesterId: IDS.admin,
        requesterBusinessId: IDS.business,
        targetUserId: IDS.user,
        applicationId: 'app-001',
        status: 'pending',
        expiresAt: '2099-01-01T00:00:00Z',  // 만료일 직접 설정로 동의 없이 열람 시도
      }),
    );
  });
});

// ─── ICAR-UPDATE: 근무자 승인/거절 ────────────────────────────────────

describe('ICAR-UPDATE: 수신자 승인/거절', () => {
  test('ICAR-UPDATE-01 수신자(근무자)가 pending→approved 전환 허용', async () => {
    const db = getAuth(env, IDS.user);
    // expiresAt은 앱 코드에서 Timestamp로 기록 — 테스트에서는 생략 (H-1 조건: !hasAny(['expiresAt']) = true)
    await assertSucceeds(
      updateDoc(doc(db, 'idCardAccessRequests', ICAR), {
        status: 'approved',
        respondedAt: '2024-01-15T10:00:00Z',
      }),
    );
  });

  test('ICAR-UPDATE-02 수신자가 approved→rejected 역변조 차단 (SEC-27)', async () => {
    // icar-approved는 status=approved 상태
    const db = getAuth(env, IDS.user);
    await assertFails(
      updateDoc(doc(db, 'idCardAccessRequests', 'icar-approved'), {
        status: 'rejected',
        respondedAt: '2024-01-15T10:00:00Z',
      }),
    );
  });

  test('ICAR-UPDATE-03 수신자가 허용 외 필드(requesterId) 변경 차단', async () => {
    await seedDoc(env, 'idCardAccessRequests', 'icar-field-hack', baseReq);
    const db = getAuth(env, IDS.user);
    await assertFails(
      updateDoc(doc(db, 'idCardAccessRequests', 'icar-field-hack'), {
        status: 'approved',
        requesterId: IDS.user,  // 요청자 위조 시도
        respondedAt: '2024-01-15T10:00:00Z',
      }),
    );
  });

  test('ICAR-UPDATE-04 관리자가 status=canceled 처리 허용 (취소 경로)', async () => {
    await seedDoc(env, 'idCardAccessRequests', 'icar-cancel', baseReq);
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(
      updateDoc(doc(db, 'idCardAccessRequests', 'icar-cancel'), {
        status: 'canceled',
      }),
    );
  });

  test('ICAR-UPDATE-05 관리자가 status=approved 직접 설정 차단 (SEC-33)', async () => {
    await seedDoc(env, 'idCardAccessRequests', 'icar-admin-approve', baseReq);
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'idCardAccessRequests', 'icar-admin-approve'), {
        status: 'approved',  // 관리자 스스로 승인 차단
      }),
    );
  });

  test('ICAR-UPDATE-06 타 사업장 관리자는 수정 차단', async () => {
    const db = getAuth(env, IDS.admin2, { businessId: IDS.business2 });
    await assertFails(
      updateDoc(doc(db, 'idCardAccessRequests', ICAR), {
        status: 'canceled',
      }),
    );
  });

  test('ICAR-UPDATE-07 슈퍼어드민은 모든 수정 허용', async () => {
    await seedDoc(env, 'idCardAccessRequests', 'icar-super-update', baseReq);
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertSucceeds(
      updateDoc(doc(db, 'idCardAccessRequests', 'icar-super-update'), {
        status: 'expired',
      }),
    );
  });
});

// ─── ICAR-DELETE ──────────────────────────────────────────────────────

describe('ICAR-DELETE: 신분증 요청 삭제', () => {
  test('ICAR-DELETE-01 슈퍼어드민만 삭제 허용', async () => {
    await seedDoc(env, 'idCardAccessRequests', 'icar-del', baseReq);
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertSucceeds(deleteDoc(doc(db, 'idCardAccessRequests', 'icar-del')));
  });

  test('ICAR-DELETE-02 관리자도 삭제 차단 (슈퍼어드민만)', async () => {
    await seedDoc(env, 'idCardAccessRequests', 'icar-del-admin', baseReq);
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(deleteDoc(doc(db, 'idCardAccessRequests', 'icar-del-admin')));
  });
});
