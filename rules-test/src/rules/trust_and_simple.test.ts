// rules-test/src/rules/trust_and_simple.test.ts
// trust_score_history + review_requests + badges/work_types/settings 보안 규칙 검증 (30개 시나리오)
import { RulesTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc } from 'firebase/firestore';
import {
  createTestEnv, getAuth, seedDoc, seedCommonFixtures,
  assertFails, assertSucceeds, IDS,
} from '../helpers/test-env';

let env: RulesTestEnvironment;

beforeAll(async () => {
  env = await createTestEnv('trust_and_simple');
  await seedCommonFixtures(env);

  // trust_score_history
  await seedDoc(env, 'trust_score_history', 'tsh-001', {
    userId: IDS.user,
    businessId: IDS.business,
    delta: -10,
    reason: 'LATE_ARRIVAL',
    createdAt: '2024-01-15T09:00:00Z',
  });

  // review_requests
  await seedDoc(env, 'review_requests', 'rr-001', {
    workerId: IDS.user,
    businessId: IDS.business,
    workerStatus: 'PENDING',
    adminStatus: 'PENDING',
    workerReviewId: null,
    adminReviewId: null,
  });
  await seedDoc(env, 'review_requests', 'rr-biz2', {
    workerId: IDS.user2,
    businessId: IDS.business2,
    workerStatus: 'PENDING',
    adminStatus: 'PENDING',
    workerReviewId: null,
    adminReviewId: null,
  });

  // badges, work_types, settings
  await seedDoc(env, 'badges', 'badge-001', { name: '우수직원', criteria: {} });
  await seedDoc(env, 'work_types', 'wt-001', { name: '창고', category: 'logistics' });
  await seedDoc(env, 'settings', 'wage_config', { minimumWage: 10320 });
});

afterAll(async () => { await env.cleanup(); });

// ═══════════════════════════════════════════════════════════════════
// trust_score_history — 신뢰도 변동 이력 (SEC-03 완료: CF 전용 create)
// ═══════════════════════════════════════════════════════════════════

describe('TSH-GET: trust_score_history 단건 읽기', () => {
  test('TSH-GET-01 본인(userId)은 자신의 이력 읽기 허용', async () => {
    const db = getAuth(env, IDS.user);
    await assertSucceeds(getDoc(doc(db, 'trust_score_history', 'tsh-001')));
  });

  test('TSH-GET-02 슈퍼어드민 읽기 허용', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertSucceeds(getDoc(doc(db, 'trust_score_history', 'tsh-001')));
  });

  test('TSH-GET-03 관계없는 유저 읽기 차단', async () => {
    const db = getAuth(env, IDS.user2);
    await assertFails(getDoc(doc(db, 'trust_score_history', 'tsh-001')));
  });

  test('TSH-GET-04 소속 관리자는 GET 차단 (list만 허용되는 설계)', async () => {
    // 규칙: get = isLoggedIn() && (isSuperAdmin() || (resource != null && isOwner(userId)))
    // 관리자(IDS.admin)는 isOwner 아님, isSuperAdmin 아님 → DENIED
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(getDoc(doc(db, 'trust_score_history', 'tsh-001')));
  });
});

describe('TSH-CREATE/UPDATE/DELETE: trust_score_history 쓰기', () => {
  test('TSH-WRITE-01 클라이언트 create 차단 (CF Admin SDK 전용 — SEC-03)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      setDoc(doc(db, 'trust_score_history', 'tsh-client-create'), {
        userId: IDS.user,
        businessId: IDS.business,
        delta: 10,
        reason: 'BONUS',
      }),
    );
  });

  test('TSH-WRITE-02 일반 유저 create 차단', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      setDoc(doc(db, 'trust_score_history', 'tsh-user-create'), {
        userId: IDS.user,
        businessId: IDS.business,
        delta: 100,
        reason: 'FAKE',
      }),
    );
  });

  test('TSH-WRITE-03 슈퍼어드민은 create 허용 (긴급 수정)', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertSucceeds(
      setDoc(doc(db, 'trust_score_history', 'tsh-super-create'), {
        userId: IDS.user,
        businessId: IDS.business,
        delta: 5,
        reason: 'MANUAL_ADJUST',
      }),
    );
  });

  test('TSH-WRITE-04 슈퍼어드민만 update/delete 허용', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertSucceeds(
      updateDoc(doc(db, 'trust_score_history', 'tsh-001'), { delta: -5 }),
    );
  });

  test('TSH-WRITE-05 관리자 update 차단 (감사 이력 불변 보호)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'trust_score_history', 'tsh-001'), { delta: 0 }),
    );
  });
});

// ═══════════════════════════════════════════════════════════════════
// review_requests — 리뷰 요청 (workerStatus/adminStatus 필드 분리)
// ═══════════════════════════════════════════════════════════════════

describe('RR-GET: review_requests 단건 읽기', () => {
  test('RR-GET-01 워커(workerId) 읽기 허용', async () => {
    const db = getAuth(env, IDS.user);
    await assertSucceeds(getDoc(doc(db, 'review_requests', 'rr-001')));
  });

  test('RR-GET-02 소속 관리자 읽기 허용', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(getDoc(doc(db, 'review_requests', 'rr-001')));
  });

  test('RR-GET-03 타 사업장 관리자 읽기 차단', async () => {
    const db = getAuth(env, IDS.admin2, { businessId: IDS.business2 });
    await assertFails(getDoc(doc(db, 'review_requests', 'rr-001')));
  });
});

describe('RR-CREATE: review_requests 생성', () => {
  test('RR-CREATE-01 관리자가 소속 사업장으로 생성 허용', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(
      setDoc(doc(db, 'review_requests', 'rr-new-admin'), {
        workerId: IDS.user,
        businessId: IDS.business,
        workerStatus: 'PENDING',
        adminStatus: 'PENDING',
      }),
    );
  });

  test('RR-CREATE-02 서브어드민도 생성 허용', async () => {
    const db = getAuth(env, IDS.subAdmin, { subAdminOf: IDS.business });
    await assertSucceeds(
      setDoc(doc(db, 'review_requests', 'rr-new-sub'), {
        workerId: IDS.user,
        businessId: IDS.business,
        workerStatus: 'PENDING',
        adminStatus: 'PENDING',
      }),
    );
  });

  test('RR-CREATE-03 일반 유저는 생성 차단', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      setDoc(doc(db, 'review_requests', 'rr-user-create'), {
        workerId: IDS.user,
        businessId: IDS.business,
        workerStatus: 'PENDING',
        adminStatus: 'PENDING',
      }),
    );
  });
});

describe('RR-UPDATE: review_requests 필드 분리 수정', () => {
  test('RR-UPDATE-01 워커는 workerStatus/workerReviewId만 수정 허용', async () => {
    const db = getAuth(env, IDS.user);
    await assertSucceeds(
      updateDoc(doc(db, 'review_requests', 'rr-001'), {
        workerStatus: 'SUBMITTED',
        workerReviewId: 'mr-utb-001',
      }),
    );
  });

  test('RR-UPDATE-02 워커는 adminStatus 수정 차단 (역할 분리)', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      updateDoc(doc(db, 'review_requests', 'rr-001'), {
        adminStatus: 'SUBMITTED',  // 워커가 관리자 필드 수정 시도
      }),
    );
  });

  test('RR-UPDATE-03 관리자는 adminStatus/adminReviewId만 수정 허용', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(
      updateDoc(doc(db, 'review_requests', 'rr-001'), {
        adminStatus: 'SUBMITTED',
        adminReviewId: 'mr-admin-001',
      }),
    );
  });

  test('RR-UPDATE-04 관리자는 workerStatus 수정 차단 (역할 분리)', async () => {
    // 별도 문서 사용: rr-001은 RR-UPDATE-01에서 workerStatus='SUBMITTED'으로 변경됨
    // 같은 값으로 업데이트하면 affectedKeys()가 빈 세트 → hasOnly([...]) = true 오탐
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('review_requests').doc('rr-worker-lock').set({
        workerId: IDS.user,
        businessId: IDS.business,
        workerStatus: 'PENDING',
        adminStatus: 'PENDING',
      });
    });
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'review_requests', 'rr-worker-lock'), {
        workerStatus: 'SUBMITTED',  // 관리자가 워커 필드 수정 시도 — 차단
      }),
    );
  });
});

// ═══════════════════════════════════════════════════════════════════
// badges — 배지 설정 (로그인 읽기, 슈퍼어드민 쓰기)
// ═══════════════════════════════════════════════════════════════════

describe('BADGE: badges 컬렉션', () => {
  test('BADGE-01 로그인 유저 읽기 허용', async () => {
    const db = getAuth(env, IDS.user);
    await assertSucceeds(getDoc(doc(db, 'badges', 'badge-001')));
  });

  test('BADGE-02 미인증 읽기 차단', async () => {
    const db = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, 'badges', 'badge-001')));
  });

  test('BADGE-03 슈퍼어드민만 쓰기 허용', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertSucceeds(
      setDoc(doc(db, 'badges', 'badge-new'), { name: '새배지', criteria: {} }),
    );
  });

  test('BADGE-04 관리자 쓰기 차단', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      setDoc(doc(db, 'badges', 'badge-admin'), { name: '해킹배지' }),
    );
  });
});

// ═══════════════════════════════════════════════════════════════════
// work_types — 플랫폼 공용 업무 유형 (로그인 읽기, 슈퍼어드민 쓰기)
// ═══════════════════════════════════════════════════════════════════

describe('WT: work_types 컬렉션', () => {
  test('WT-01 로그인 유저 읽기 허용', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(getDoc(doc(db, 'work_types', 'wt-001')));
  });

  test('WT-02 미인증 읽기 차단', async () => {
    const db = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, 'work_types', 'wt-001')));
  });

  test('WT-03 슈퍼어드민 쓰기 허용 (플랫폼 전체 영향 — 슈퍼어드민 전용)', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertSucceeds(
      setDoc(doc(db, 'work_types', 'wt-new'), { name: '새업종', category: 'etc' }),
    );
  });

  test('WT-04 일반 관리자 쓰기 차단 (전사업장 영향 방지)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      setDoc(doc(db, 'work_types', 'wt-admin'), { name: '관리자추가업종' }),
    );
  });
});

// ═══════════════════════════════════════════════════════════════════
// settings — 앱 공통 설정 (로그인 읽기, 슈퍼어드민 쓰기)
// ═══════════════════════════════════════════════════════════════════

describe('SETTINGS: settings 컬렉션', () => {
  test('SETTINGS-01 로그인 유저 읽기 허용 (최저임금·보험요율 공개)', async () => {
    const db = getAuth(env, IDS.user);
    await assertSucceeds(getDoc(doc(db, 'settings', 'wage_config')));
  });

  test('SETTINGS-02 미인증 읽기 차단', async () => {
    const db = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, 'settings', 'wage_config')));
  });

  test('SETTINGS-03 슈퍼어드민 쓰기 허용', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertSucceeds(
      updateDoc(doc(db, 'settings', 'wage_config'), { minimumWage: 11000 }),
    );
  });

  test('SETTINGS-04 관리자 쓰기 차단 (설정 조작 방지)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'settings', 'wage_config'), { minimumWage: 99999 }),
    );
  });
});
