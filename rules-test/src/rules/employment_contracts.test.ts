// rules-test/src/rules/employment_contracts.test.ts
// employment_contracts 컬렉션 보안 규칙 검증 (35개 시나리오)
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

const CONTRACT = 'contract-001';
const CONTRACT2 = 'contract-002';
const APP_ID = 'app-ec-001';

// 기본 계약서 픽스처
const baseContract = {
  businessId: IDS.business,
  workerId: IDS.user,
  applicationId: APP_ID,
  status: 'pending_employer',
  slots: [{ slotId: 's1', startTime: '09:00', endTime: '18:00' }],
  articles: [{ title: '근무 조건', content: '주 5일' }],
  templateId: 'tmpl-001',
  workerSignedAt: null,
  terminationStatus: null,
};

beforeAll(async () => {
  env = await createTestEnv('employment_contracts');
  await seedCommonFixtures(env);

  // 지원서 시드 (workerId 위조 검증에 사용)
  await seedDoc(env, 'applications', APP_ID, {
    uid: IDS.user,
    businessId: IDS.business,
    toId: IDS.to,
    status: 'CONFIRMED',
  });

  // 기본 계약서
  await seedDoc(env, 'employment_contracts', CONTRACT, baseContract);

  // 서명 전 slots 수정 테스트 전용 (EC-S-H1-01 — 다른 테스트에 오염되지 않아야 함)
  await seedDoc(env, 'employment_contracts', 'contract-before-sign', {
    ...baseContract,
    workerSignedAt: null,
  });

  // 완료된 계약서
  await seedDoc(env, 'employment_contracts', 'contract-completed', {
    ...baseContract,
    status: 'completed',
  });

  // voided 계약서
  await seedDoc(env, 'employment_contracts', 'contract-voided', {
    ...baseContract,
    status: 'voided',
  });

  // 근무자 서명 완료 계약서 (S-H1 검증용) — 워커 서명 완료 → status: active
  await seedDoc(env, 'employment_contracts', 'contract-signed', {
    ...baseContract,
    status: 'active',
    workerSignedAt: '2024-01-01T09:00:00Z',
  });

  // terminationStatus=PENDING 계약서
  await seedDoc(env, 'employment_contracts', 'contract-termination', {
    ...baseContract,
    status: 'active',
    terminationStatus: 'PENDING',
  });

  // 타 사업장 계약서
  await seedDoc(env, 'employment_contracts', 'contract-biz2', {
    ...baseContract,
    businessId: IDS.business2,
    workerId: IDS.user2,
    applicationId: 'app-biz2-001',
  });
});

afterAll(async () => {
  await env.cleanup();
});

// ─── EC-GET: 단건 읽기 ────────────────────────────────────────────────

describe('EC-GET: 단건 읽기', () => {
  test('EC-GET-01 근무자 본인은 자신의 계약서를 읽을 수 있다', async () => {
    const db = getAuth(env, IDS.user);
    await assertSucceeds(getDoc(doc(db, 'employment_contracts', CONTRACT)));
  });

  test('EC-GET-02 사업장 관리자(isAdminOf)는 계약서를 읽을 수 있다', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(getDoc(doc(db, 'employment_contracts', CONTRACT)));
  });

  test('EC-GET-03 서브어드민은 소속 사업장 계약서를 읽을 수 있다', async () => {
    const db = getAuth(env, IDS.subAdmin, { subAdminOf: IDS.business });
    await assertSucceeds(getDoc(doc(db, 'employment_contracts', CONTRACT)));
  });

  test('EC-GET-04 슈퍼어드민은 모든 계약서를 읽을 수 있다', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertSucceeds(getDoc(doc(db, 'employment_contracts', CONTRACT)));
  });

  test('EC-GET-05 타 사업장 관리자는 계약서를 읽을 수 없다', async () => {
    const db = getAuth(env, IDS.admin2, { businessId: IDS.business2 });
    await assertFails(getDoc(doc(db, 'employment_contracts', CONTRACT)));
  });

  test('EC-GET-06 관계없는 일반유저는 타인 계약서를 읽을 수 없다', async () => {
    const db = getAuth(env, IDS.user2);
    await assertFails(getDoc(doc(db, 'employment_contracts', CONTRACT)));
  });

  test('EC-GET-07 미인증 사용자는 계약서를 읽을 수 없다', async () => {
    const db = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, 'employment_contracts', CONTRACT)));
  });
});

// ─── EC-CREATE: 계약서 생성 ──────────────────────────────────────────

describe('EC-CREATE: 계약서 생성', () => {
  test('EC-CREATE-01 관리자가 올바른 applicationId/workerId로 생성 허용', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(
      setDoc(doc(db, 'employment_contracts', 'contract-new-admin'), {
        businessId: IDS.business,
        workerId: IDS.user,   // APP_ID.uid == IDS.user ✓
        applicationId: APP_ID,
        status: 'pending_employer',
      }),
    );
  });

  test('EC-CREATE-02 서브어드민도 생성 허용 (HIGH-FIX 검증)', async () => {
    const db = getAuth(env, IDS.subAdmin, { subAdminOf: IDS.business });
    await assertSucceeds(
      setDoc(doc(db, 'employment_contracts', 'contract-new-sub'), {
        businessId: IDS.business,
        workerId: IDS.user,
        applicationId: APP_ID,
        status: 'pending_employer',
      }),
    );
  });

  test('EC-CREATE-03 workerId 위조 차단 — applicationId 실제 uid와 불일치', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      setDoc(doc(db, 'employment_contracts', 'contract-fake'), {
        businessId: IDS.business,
        workerId: IDS.user2,   // APP_ID.uid=IDS.user 와 불일치
        applicationId: APP_ID,
        status: 'pending_employer',
      }),
    );
  });

  test('EC-CREATE-04 타 사업장 관리자는 생성 차단', async () => {
    const db = getAuth(env, IDS.admin2, { businessId: IDS.business2 });
    await assertFails(
      setDoc(doc(db, 'employment_contracts', 'contract-cross'), {
        businessId: IDS.business,  // 다른 사업장
        workerId: IDS.user,
        applicationId: APP_ID,
        status: 'pending_employer',
      }),
    );
  });

  test('EC-CREATE-05 일반유저는 계약서 생성 차단', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      setDoc(doc(db, 'employment_contracts', 'contract-user-create'), {
        businessId: IDS.business,
        workerId: IDS.user,
        applicationId: APP_ID,
        status: 'pending_employer',
      }),
    );
  });

  test('EC-CREATE-06 슈퍼어드민은 applicationId 검증 없이 생성 허용', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertSucceeds(
      setDoc(doc(db, 'employment_contracts', 'contract-super-create'), {
        businessId: IDS.business2,
        workerId: IDS.user2,
        applicationId: 'any-app-id',
        status: 'pending_employer',
      }),
    );
  });
});

// ─── EC-UPDATE: 근무자 서명 필드 수정 ────────────────────────────────

describe('EC-UPDATE: 근무자 서명 (pending 상태)', () => {
  // SEC-91: pending_worker → completed 전이만 허용 (이전: status 목표값 무제한)
  test('EC-UPDATE-01 근무자가 pending_worker에서 completed로 서명 완료 허용 (SEC-91)', async () => {
    await seedDoc(env, 'employment_contracts', 'contract-worker-sign', {
      businessId: IDS.business,
      workerId: IDS.user,
      applicationId: APP_ID,
      status: 'pending_worker',
      employerSignatureUrl: 'https://sig.example.com/employer.png',
      employerSignatureHash: 'employer-hash-abc',
    });
    const db = getAuth(env, IDS.user);
    await assertSucceeds(
      updateDoc(doc(db, 'employment_contracts', 'contract-worker-sign'), {
        workerSignatureUrl: 'https://sig.example.com/worker.png',
        workerSignatureHash: 'abc123',
        workerSignedAt: '2024-01-01T09:00:00Z',
        status: 'completed',
        updatedAt: '2024-01-01T09:00:00Z',
      }),
    );
  });

  test('EC-UPDATE-01b pending_employer에서 근무자 completed 직접 전환 차단 (SEC-91)', async () => {
    // pending_employer = 관리자 서명 전 — 근무자가 직접 completed로 점프 불가
    const db = getAuth(env, IDS.user);
    await assertFails(
      updateDoc(doc(db, 'employment_contracts', CONTRACT), {
        workerSignatureUrl: 'https://sig.example.com/worker.png',
        workerSignatureHash: 'abc123',
        workerSignedAt: '2024-01-01T09:00:00Z',
        status: 'completed',
        updatedAt: '2024-01-01T09:00:00Z',
      }),
    );
  });

  test('EC-UPDATE-01c pending_employer에서 근무자 voided 직접 전환 차단 (SEC-91)', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      updateDoc(doc(db, 'employment_contracts', CONTRACT), {
        status: 'voided',
        updatedAt: '2024-01-01T09:00:00Z',
      }),
    );
  });

  test('EC-UPDATE-02 근무자가 계약 내용(articles) 수정 차단', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      updateDoc(doc(db, 'employment_contracts', CONTRACT), {
        articles: [{ title: '수정된 조건', content: '임의 변경' }],
      }),
    );
  });

  test('EC-UPDATE-03 근무자가 slots 수정 차단', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      updateDoc(doc(db, 'employment_contracts', CONTRACT), {
        slots: [{ slotId: 'hacked', startTime: '00:00', endTime: '23:59' }],
      }),
    );
  });

  test('EC-UPDATE-04 근무자가 templateId 수정 차단', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      updateDoc(doc(db, 'employment_contracts', CONTRACT), {
        templateId: 'fake-tmpl',
      }),
    );
  });
});

// ─── EC-UPDATE: S-H1 — 근무자 서명 후 slots/articles/templateId 불변 ──

describe('EC-UPDATE: S-H1 — 근무자 서명 후 핵심 필드 불변', () => {
  test('EC-S-H1-01 관리자가 근무자 서명 전 slots 수정 허용', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    // contract-before-sign: workerSignedAt=null 전용 문서 (다른 테스트 오염 방지)
    await assertSucceeds(
      updateDoc(doc(db, 'employment_contracts', 'contract-before-sign'), {
        slots: [{ slotId: 's1', startTime: '10:00', endTime: '19:00' }],
        updatedAt: '2024-01-01T10:00:00Z',
      }),
    );
  });

  test('EC-S-H1-02 관리자가 근무자 서명 후 slots 수정 차단', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'employment_contracts', 'contract-signed'), {
        slots: [{ slotId: 'hacked', startTime: '00:00', endTime: '23:59' }],
        updatedAt: '2024-01-01T10:00:00Z',
      }),
    );
  });

  test('EC-S-H1-03 관리자가 근무자 서명 후 articles 수정 차단', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'employment_contracts', 'contract-signed'), {
        articles: [{ title: '변경', content: '위변조' }],
        updatedAt: '2024-01-01T10:00:00Z',
      }),
    );
  });

  test('EC-S-H1-04 관리자가 근무자 서명 후 templateId 수정 차단', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'employment_contracts', 'contract-signed'), {
        templateId: 'evil-tmpl',
        updatedAt: '2024-01-01T10:00:00Z',
      }),
    );
  });

  test('EC-S-H1-05 슈퍼어드민은 서명 후에도 모든 필드 수정 허용', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertSucceeds(
      updateDoc(doc(db, 'employment_contracts', 'contract-signed'), {
        slots: [{ slotId: 'super-fix', startTime: '09:00', endTime: '18:00' }],
        updatedAt: '2024-01-01T10:00:00Z',
      }),
    );
  });
});

// ─── EC-UPDATE: 완료/voided 상태 차단 ────────────────────────────────

describe('EC-UPDATE: 완료·voided 상태 보호', () => {
  test('EC-UPDATE-05 completed 계약서는 관리자도 수정 차단', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'employment_contracts', 'contract-completed'), {
        employerSignatureUrl: 'https://sig.example.com/employer.png',
        updatedAt: '2024-01-01T10:00:00Z',
      }),
    );
  });

  test('EC-UPDATE-06 voided 계약서는 관리자 일반 수정 차단', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'employment_contracts', 'contract-voided'), {
        status: 'active',
        updatedAt: '2024-01-01T10:00:00Z',
      }),
    );
  });

  test('EC-UPDATE-07 voided 계약서에서 voidFailedAppIds만 수정 허용', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(
      updateDoc(doc(db, 'employment_contracts', 'contract-voided'), {
        voidFailedAppIds: ['app-fail-1'],
      }),
    );
  });

  test('EC-UPDATE-08 슈퍼어드민은 completed 계약서도 수정 허용', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertSucceeds(
      updateDoc(doc(db, 'employment_contracts', 'contract-completed'), {
        status: 'active',
      }),
    );
  });
});

// ─── EC-UPDATE: 계약해지 근무자 수락 ────────────────────────────────

describe('EC-UPDATE: 근무자 계약해지 수락 (terminationStatus)', () => {
  test('EC-TERM-01 terminationStatus=PENDING 시 근무자가 voided 전환 허용', async () => {
    const db = getAuth(env, IDS.user);
    await assertSucceeds(
      updateDoc(doc(db, 'employment_contracts', 'contract-termination'), {
        status: 'voided',
        contractVoidedAt: '2024-01-01T10:00:00Z',
        voidReason: '계약해지 수락',
      }),
    );
  });

  test('EC-TERM-02 terminationStatus 없으면 근무자 직접 voided 차단', async () => {
    const db = getAuth(env, IDS.user);
    // CONTRACT는 terminationStatus=null
    await assertFails(
      updateDoc(doc(db, 'employment_contracts', CONTRACT), {
        status: 'voided',
        contractVoidedAt: '2024-01-01T10:00:00Z',
        voidReason: '임의 무효화',
      }),
    );
  });
});

// ─── EC-UPDATE: applicationIds 수정 제한 (SEC-104) ───────────────────

describe('EC-UPDATE: applicationIds 수정 제한 (SEC-104)', () => {
  test('EC-SEC104-01 ✅ pending_employer 상태에서 관리자가 applicationIds 수정 허용', async () => {
    // CONTRACT는 status='pending_employer' — applicationIds 수정 가능
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(
      updateDoc(doc(db, 'employment_contracts', CONTRACT), {
        applicationIds: ['app-001', 'app-002'],
        updatedAt: '2024-01-01T10:00:00Z',
      }),
    );
  });

  test('EC-SEC104-02 ❌ pending_worker 이후 상태에서 applicationIds 수정 차단 (SEC-104)', async () => {
    // contract-signed: status='active' (근무자 서명 완료) — applicationIds 재귀속 공격 차단
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'employment_contracts', 'contract-signed'), {
        applicationIds: ['hijacked-app'],
        updatedAt: '2024-01-01T10:00:00Z',
      }),
    );
  });
});

// ─── EC-DELETE ────────────────────────────────────────────────────────

describe('EC-DELETE: 계약서 삭제', () => {
  test('EC-DELETE-01 슈퍼어드민은 계약서 삭제 허용', async () => {
    // 삭제용 별도 문서 생성
    await seedDoc(env, 'employment_contracts', 'contract-to-delete', baseContract);
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertSucceeds(
      deleteDoc(doc(db, 'employment_contracts', 'contract-to-delete')),
    );
  });

  test('EC-DELETE-02 관리자는 계약서 삭제 차단 (슈퍼어드민만 허용)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      deleteDoc(doc(db, 'employment_contracts', CONTRACT)),
    );
  });

  test('EC-DELETE-03 일반유저는 계약서 삭제 차단', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      deleteDoc(doc(db, 'employment_contracts', CONTRACT)),
    );
  });
});
