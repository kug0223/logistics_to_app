// rules-test/src/rules/schedule_change_requests.test.ts
// schedule_change_requests 컬렉션 보안 규칙 검증 (22개 시나리오)
import { RulesTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc, serverTimestamp } from 'firebase/firestore';
import {
  createTestEnv, getAuth, seedDoc, seedCommonFixtures,
  assertFails, assertSucceeds, IDS,
} from '../helpers/test-env';

let env: RulesTestEnvironment;

const SCR = 'scr-001';
const SCR_APP = 'app-scr-001';

// [R8-P3B.3A.1] 계약 유효 범위 — targetDate는 이 사이에 있어야 한다.
const CONTRACT_START = new Date('2024-01-01T00:00:00Z');
const CONTRACT_END = new Date('2024-12-31T00:00:00Z');
const TARGET_DATE = new Date('2024-06-15T00:00:00Z');

const baseReq = {
  applicantUid: IDS.user,
  businessId: IDS.business,
  applicationId: SCR_APP,
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

  // [R8-P3B.3A.1] create 규칙이 참조하는 지원서를 실제로 만든다.
  //   [5B.3A.2-SCR-RANGE] isInsideEffectiveContractRange()가
  //   applications/{applicationId}의 businessId·workDate·workEndDate를 읽어
  //   targetDate가 계약 유효 범위 안인지 본다. 지원서가 없으면 어떤 요청도 생성되지 않는다.
  //   이전 테스트는 이 문서를 만들지 않고 통과를 기대하고 있었다.
  await seedDoc(env, 'applications', SCR_APP, {
    uid: IDS.user,
    businessId: IDS.business,
    status: 'CONFIRMED',
    workDate: CONTRACT_START,
    workEndDate: CONTRACT_END,
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
        applicationId: SCR_APP,    // [SCR-RANGE] 실재하는 지원서여야 한다
        targetDate: TARGET_DATE,   // [SCR-RANGE] 계약 유효 범위 안
        requestedAt: serverTimestamp(),  // [B6-FIX] 서버 타임스탬프 강제
        type: 'ADDITIONAL_WORK',
        status: 'PENDING',
      }),
    );
  });

  // [R8-P3B.3A.1] 신규 — 범위 밖 targetDate 차단 확인 ([5B.3A.2-SCR-RANGE])
  test('SCR-CREATE-01b 계약 유효 범위 밖 targetDate는 차단된다', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      setDoc(doc(db, 'schedule_change_requests', 'scr-user-outofrange'), {
        applicantUid: IDS.user,
        requestedByUid: IDS.user,
        businessId: IDS.business,
        applicationId: SCR_APP,
        targetDate: new Date('2025-06-15T00:00:00Z'),  // workEndDate 이후
        requestedAt: serverTimestamp(),
        type: 'ADDITIONAL_WORK',
        status: 'PENDING',
      }),
    );
  });

  // [R8-P3B.3A.1] 신규 — requestedAt 클라이언트 시각 차단 확인 ([B6-FIX])
  test('SCR-CREATE-01c requestedAt을 클라이언트 시각으로 쓰면 차단된다', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      setDoc(doc(db, 'schedule_change_requests', 'scr-user-clocktime'), {
        applicantUid: IDS.user,
        requestedByUid: IDS.user,
        businessId: IDS.business,
        applicationId: SCR_APP,
        targetDate: TARGET_DATE,
        requestedAt: new Date(2020, 0, 1),
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
        requestedByUid: IDS.admin,       // [RULE-FIX-M3] 관리자 경로도 본인 UID 강제
        businessId: IDS.business,
        applicationId: SCR_APP,
        targetDate: TARGET_DATE,
        requestedAt: serverTimestamp(),  // [TS-FIX] 관리자 경로 소급 방지
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
        requestedByUid: IDS.subAdmin,
        businessId: IDS.business,
        applicationId: SCR_APP,
        targetDate: TARGET_DATE,
        requestedAt: serverTimestamp(),
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

// [R8-P3B.3A.1] 이 describe 전체가 기대값 반전 대상이다.
//
//   schedule_change_requests update = **if false**. 모든 상태 전이가 CF Admin SDK 전용이다:
//     · 승인/거절 — callableApproveScheduleChangeRequest
//     · 취소      — callableCancelScheduleChangeRequest
//   [SCR-S1-FIX] 특히 APPROVED→CANCELED를 클라이언트가 직접 쓰면
//   applications.leaveDates/extraWorkDates 역산이 실행되지 않아 근무일 배열이 어긋난다.
//
//   "누가 어떤 전이를 할 수 있는가"는 이제 CF 내부 검증의 몫이고,
//   Rules 층에서는 **아무도 못 쓴다**가 정답이다. 그래서 아래는 전부 차단 확인이다.
describe('SCR-UPDATE: 상태 전이 — 전부 CF 전용 (client write 차단)', () => {
  test('SCR-UPDATE-01 워커의 PENDING→CANCELED도 직접 쓸 수 없다 (callableCancelScheduleChangeRequest 전용)', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
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

  test('SCR-UPDATE-04 관리자의 PENDING→APPROVED도 직접 쓸 수 없다 (callableApproveScheduleChangeRequest 전용)', async () => {
    await seedDoc(env, 'schedule_change_requests', 'scr-admin-approve', baseReq);
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'schedule_change_requests', 'scr-admin-approve'), {
        status: 'APPROVED',
        respondedByUid: IDS.admin,
        respondedAt: '2024-01-15T10:00:00Z',
      }),
    );
  });

  test('SCR-UPDATE-05 관리자의 PENDING→REJECTED도 직접 쓸 수 없다 (CF 전용)', async () => {
    await seedDoc(env, 'schedule_change_requests', 'scr-admin-reject', baseReq);
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
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

  test('SCR-UPDATE-08 관리자의 APPROVED→CANCELED도 직접 쓸 수 없다 (날짜 역산 미실행 방지)', async () => {
    await seedDoc(env, 'schedule_change_requests', 'scr-admin-cancel-approved', {
      ...baseReq, status: 'APPROVED',
    });
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'schedule_change_requests', 'scr-admin-cancel-approved'), {
        status: 'CANCELED',
        respondedByUid: IDS.admin,
        respondedAt: '2024-01-15T10:00:00Z',
      }),
    );
  });

  test('SCR-UPDATE-09 서브어드민의 APPROVED→CANCELED도 직접 쓸 수 없다 (CF 전용)', async () => {
    await seedDoc(env, 'schedule_change_requests', 'scr-sub-cancel-approved', {
      ...baseReq, status: 'APPROVED',
    });
    const db = getAuth(env, IDS.subAdmin, { subAdminOf: IDS.business });
    await assertFails(
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
  // [R8-P3B.3A.1] 기대값 분화 — [M-8] PENDING 삭제 차단이 추가됐다.
  //   관리자가 불리한 요청을 "거절 기록 없이" 지워 버리는 남용을 막는 규칙이다.
  //   PENDING은 거절(CF)로 처리해야 하고, 삭제는 처리 끝난 요청의 정리용이다.
  //   (TO 삭제 cascade는 CF Admin SDK라 rules를 우회하므로 영향 없다.)
  test('SCR-DELETE-01 관리자도 PENDING 요청은 삭제할 수 없다 (거절 기록 우회 방지)', async () => {
    await seedDoc(env, 'schedule_change_requests', 'scr-del-admin', baseReq);
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(deleteDoc(doc(db, 'schedule_change_requests', 'scr-del-admin')));
  });

  test('SCR-DELETE-01b 관리자는 처리 완료(REJECTED) 요청을 삭제할 수 있다', async () => {
    await seedDoc(env, 'schedule_change_requests', 'scr-del-admin-done', {
      ...baseReq, status: 'REJECTED',
    });
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(deleteDoc(doc(db, 'schedule_change_requests', 'scr-del-admin-done')));
  });

  test('SCR-DELETE-02 서브어드민도 PENDING 요청은 삭제할 수 없다', async () => {
    await seedDoc(env, 'schedule_change_requests', 'scr-del-sub', baseReq);
    const db = getAuth(env, IDS.subAdmin, { subAdminOf: IDS.business });
    await assertFails(deleteDoc(doc(db, 'schedule_change_requests', 'scr-del-sub')));
  });

  test('SCR-DELETE-02b 서브어드민은 처리 완료 요청을 삭제할 수 있다', async () => {
    await seedDoc(env, 'schedule_change_requests', 'scr-del-sub-done', {
      ...baseReq, status: 'APPROVED',
    });
    const db = getAuth(env, IDS.subAdmin, { subAdminOf: IDS.business });
    await assertSucceeds(deleteDoc(doc(db, 'schedule_change_requests', 'scr-del-sub-done')));
  });

  test('SCR-DELETE-03 워커는 요청 삭제 차단', async () => {
    await seedDoc(env, 'schedule_change_requests', 'scr-del-user', baseReq);
    const db = getAuth(env, IDS.user);
    await assertFails(deleteDoc(doc(db, 'schedule_change_requests', 'scr-del-user')));
  });
});
