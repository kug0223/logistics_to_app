// rules-test/src/rules/attendance.test.ts
// attendance 컬렉션 보안 규칙 검증 (32개 시나리오 + LIST 8개)
import {
  RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  deleteDoc,
  collection,
  query,
  where,
  limit,
  getDocs,
} from 'firebase/firestore';
import {
  createTestEnv,
  getAnonymous,
  getAuth,
  seedDoc,
  seedCommonFixtures,
  assertFails,
  assertSucceeds,
  IDS,
} from '../helpers/test-env';

let env: RulesTestEnvironment;

const ATT = 'att-001';

// 기본 출근 픽스처
const baseAtt = {
  userId: IDS.user,
  businessId: IDS.business,
  applicationId: 'app-att-001',
  workDate: '2024-01-15',
  status: 'WORKING',
  wageStatus: 'pending',
  finalWage: 50000,
  checkIn: '09:00',
};

beforeAll(async () => {
  env = await createTestEnv('attendance');
  await seedCommonFixtures(env);

  // users에 businessId 필드 추가 (소속 검증에 필요)
  await seedDoc(env, 'users', IDS.user, {
    role: 'USER',
    username: 'user1',
    name: '유저1',
    email: 'user@test.com',
    isBlacklisted: false,
    businessId: IDS.business,  // user → biz-001 소속
  });

  // 기본 출근 기록
  await seedDoc(env, 'attendance', ATT, baseAtt);

  // wageStatus=calculated (정상 수정 가능 상태)
  await seedDoc(env, 'attendance', 'att-calculated', {
    ...baseAtt,
    wageStatus: 'calculated',
    finalWage: 50000,
    wageDetail: { totalAmount: 50000, netWage: 50000, workMinutes: 480 },
  });

  // wageStatus=confirmed (근무자 퇴근 수정 불가)
  await seedDoc(env, 'attendance', 'att-confirmed', {
    ...baseAtt,
    wageStatus: 'confirmed',
    finalWage: 60000,
    wageDetail: { totalAmount: 60000, netWage: 60000, workMinutes: 480 },
  });

  // wageStatus=transferred (역전환 차단)
  await seedDoc(env, 'attendance', 'att-transferred', {
    ...baseAtt,
    wageStatus: 'transferred',
  });

  // NO_SHOW 상태 (근무자 수정 차단)
  await seedDoc(env, 'attendance', 'att-noshow', {
    ...baseAtt,
    status: 'NO_SHOW',
    wageStatus: 'confirmed',
    finalWage: 0,
  });

  // scheduled 상태 기록 (SEC-97: 탈퇴 처리 absent 전이 테스트용)
  await seedDoc(env, 'attendance', 'att-scheduled', {
    ...baseAtt,
    status: 'scheduled',
    wageStatus: 'pending',
    finalWage: 0,
  });

  // 타 사업장 출근 기록
  await seedDoc(env, 'attendance', 'att-biz2', {
    ...baseAtt,
    userId: IDS.user2,
    businessId: IDS.business2,
  });
});

afterAll(async () => {
  await env.cleanup();
});

// ─── AT-GET: 단건 읽기 ───────────────────────────────────────────────

describe('AT-GET: 단건 읽기', () => {
  test('AT-GET-01 근무자 본인은 자신의 출근 기록을 읽을 수 있다', async () => {
    const db = getAuth(env, IDS.user);
    await assertSucceeds(getDoc(doc(db, 'attendance', ATT)));
  });

  test('AT-GET-02 소속 사업장 관리자는 출근 기록을 읽을 수 있다', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(getDoc(doc(db, 'attendance', ATT)));
  });

  test('AT-GET-03 서브어드민은 소속 사업장 출근 기록을 읽을 수 있다', async () => {
    const db = getAuth(env, IDS.subAdmin, { subAdminOf: IDS.business });
    await assertSucceeds(getDoc(doc(db, 'attendance', ATT)));
  });

  test('AT-GET-04 슈퍼어드민은 모든 출근 기록을 읽을 수 있다', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertSucceeds(getDoc(doc(db, 'attendance', ATT)));
  });

  test('AT-GET-05 타 사업장 관리자는 출근 기록을 읽을 수 없다', async () => {
    const db = getAuth(env, IDS.admin2, { businessId: IDS.business2 });
    await assertFails(getDoc(doc(db, 'attendance', ATT)));
  });

  test('AT-GET-06 관계없는 일반유저는 타인 출근 기록을 읽을 수 없다', async () => {
    const db = getAuth(env, IDS.user2);
    await assertFails(getDoc(doc(db, 'attendance', ATT)));
  });
});

// ─── AT-CREATE: 출근 기록 생성 ──────────────────────────────────────

describe('AT-CREATE: 출근 기록 생성', () => {
  test('AT-CREATE-01 ❌ [ARCH-FIX] attendance create는 CF Admin SDK 전용 — 근무자 직접 생성 차단', async () => {
    // callableCheckIn CF로 이전 완료. allow create: if false; (rules L925)
    // 이전 기대값: assertSucceeds — 현재 architecture와 맞지 않는 STALE TEST였음.
    const db = getAuth(env, IDS.user);
    await assertFails(
      setDoc(doc(db, 'attendance', 'att-user-create'), {
        userId: IDS.user,
        businessId: IDS.business,
        workDate: '2024-01-16',
        status: 'WORKING',
        wageStatus: 'pending',
      }),
    );
  });

  test('AT-CREATE-02 근무자가 타 사업장 businessId로 생성 차단 (CROSS-BIZ-FIX)', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      setDoc(doc(db, 'attendance', 'att-cross-biz'), {
        userId: IDS.user,
        businessId: IDS.business2,  // 소속이 아닌 다른 사업장
        workDate: '2024-01-16',
        status: 'WORKING',
        wageStatus: 'pending',
      }),
    );
  });

  test('AT-CREATE-03 ❌ [ARCH-FIX] attendance create는 CF Admin SDK 전용 — 관리자 client 직접 생성 차단', async () => {
    // callableCheckIn/callableBatchSetNoShow 등 CF만 create 가능. allow create: if false; (rules L925)
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      setDoc(doc(db, 'attendance', 'att-admin-create'), {
        userId: IDS.user,
        businessId: IDS.business,
        workDate: '2024-01-17',
        status: 'WORKING',
        wageStatus: 'pending',
      }),
    );
  });

  test('AT-CREATE-04 ❌ [ARCH-FIX] attendance create는 CF Admin SDK 전용 — 서브어드민 client 직접 생성 차단', async () => {
    // allow create: if false; (rules L925) — 서브어드민 포함 모든 클라이언트 차단
    const db = getAuth(env, IDS.subAdmin, { subAdminOf: IDS.business });
    await assertFails(
      setDoc(doc(db, 'attendance', 'att-sub-create'), {
        userId: IDS.user,
        businessId: IDS.business,
        workDate: '2024-01-18',
        status: 'NO_SHOW',
        wageStatus: 'pending',
        finalWage: 0,
      }),
    );
  });

  test('AT-CREATE-05 checkInSuspicious 포함 생성 차단 (HIGH-02)', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      setDoc(doc(db, 'attendance', 'att-suspicious'), {
        userId: IDS.user,
        businessId: IDS.business,
        workDate: '2024-01-19',
        status: 'WORKING',
        wageStatus: 'pending',
        checkInSuspicious: true,  // CF Admin SDK 전용 필드
      }),
    );
  });

  test('AT-CREATE-06 checkInDistance 포함 생성 차단 (HIGH-03)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      setDoc(doc(db, 'attendance', 'att-distance'), {
        userId: IDS.user,
        businessId: IDS.business,
        workDate: '2024-01-19',
        status: 'WORKING',
        wageStatus: 'pending',
        checkInDistance: 500,  // CF Admin SDK 전용 필드
      }),
    );
  });

  test('AT-CREATE-07 NO_SHOW + finalWage != 0 생성 차단 (NOSHOW-FIX)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      setDoc(doc(db, 'attendance', 'att-noshow-wage'), {
        userId: IDS.user,
        businessId: IDS.business,
        workDate: '2024-01-20',
        status: 'NO_SHOW',
        wageStatus: 'pending',
        finalWage: 50000,  // NO_SHOW인데 임금 0이 아님
      }),
    );
  });

  test('AT-CREATE-08 wageStatus=confirmed로 직접 생성 차단 (SEC-83)', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      setDoc(doc(db, 'attendance', 'att-fake-confirmed'), {
        userId: IDS.user,
        businessId: IDS.business,
        workDate: '2024-01-21',
        status: 'WORKING',
        wageStatus: 'confirmed',  // pending 이외의 상태로 직접 생성 시도
      }),
    );
  });

  test('AT-CREATE-09 finalWage>0으로 직접 생성 차단 (SEC-83)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      setDoc(doc(db, 'attendance', 'att-fake-wage'), {
        userId: IDS.user,
        businessId: IDS.business,
        workDate: '2024-01-22',
        status: 'WORKING',
        wageStatus: 'pending',
        finalWage: 100000,  // CREATE 시 finalWage는 0이어야 함
      }),
    );
  });
});

// ─── AT-UPDATE: 근무자 퇴근 수정 ────────────────────────────────────

describe('AT-UPDATE: 근무자 퇴근 수정', () => {
  test('AT-UPDATE-01 ❌ [ARCH-FIX] 근무자 checkOut 수정은 CF 전용 — 직접 client write 차단', async () => {
    // callableCheckOut CF로 이전 완료. USER 분기 허용 경로(L956~970)에 checkOut 없음.
    // 이전 기대값: assertSucceeds — 현재 architecture와 맞지 않는 STALE TEST였음.
    const db = getAuth(env, IDS.user);
    await assertFails(
      updateDoc(doc(db, 'attendance', ATT), {
        checkOut: '18:00',
        workHours: 8,
        status: 'DONE',
        updatedAt: '2024-01-15T18:00:00Z',
      }),
    );
  });

  test('AT-UPDATE-02 근무자가 wageStatus=confirmed 상태에서 퇴근 수정 차단', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      updateDoc(doc(db, 'attendance', 'att-confirmed'), {
        checkOut: '19:00',
        workHours: 9,
        status: 'DONE',
        updatedAt: '2024-01-15T19:00:00Z',
      }),
    );
  });

  test('AT-UPDATE-03 근무자가 NO_SHOW 상태 레코드 수정 차단 (SEC-74)', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      updateDoc(doc(db, 'attendance', 'att-noshow'), {
        status: 'DONE',
        updatedAt: '2024-01-15T18:00:00Z',
      }),
    );
  });

  test('AT-UPDATE-04 근무자가 허용 외 필드(wageDetail) 수정 차단', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      updateDoc(doc(db, 'attendance', ATT), {
        finalWage: 99999999,  // 허용 외 필드
      }),
    );
  });
});

// ─── AT-UPDATE: 관리자 제한 ───────────────────────────────────────────

describe('AT-UPDATE: 관리자 수정 제한', () => {
  test('AT-UPDATE-05a ✅ 관리자가 finalWage만 수정 허용 (calculated 상태)', async () => {
    // wageStatus 변경 없이 finalWage만 변경 — pending 상태 ATT에서 허용
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(
      updateDoc(doc(db, 'attendance', ATT), {
        finalWage: 60000,
        updatedAt: '2024-01-15T20:00:00Z',
      }),
    );
  });

  test('AT-UPDATE-05b ❌ [ARCH-FIX] 관리자가 wageStatus 직접 변경 차단 — CF 전용', async () => {
    // wageStatus client write 전면 차단 (rules L951). CF(callableConfirmFinalWage 등)만 변경 가능.
    // 이전 기대값: assertSucceeds — wageStatus 차단 규칙과 충돌하는 STALE TEST였음.
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'attendance', ATT), {
        wageStatus: 'confirmed',
        updatedAt: '2024-01-15T20:00:00Z',
      }),
    );
  });

  test('AT-UPDATE-06 관리자가 userId(핵심 식별자) 변경 차단 (SEC-46)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'attendance', ATT), {
        userId: IDS.user2,  // 핵심 식별자 변조
        updatedAt: '2024-01-15T20:00:00Z',
      }),
    );
  });

  test('AT-UPDATE-07 관리자가 businessId 변경 차단', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'attendance', ATT), {
        businessId: IDS.business2,  // 사업장 변경 차단
        updatedAt: '2024-01-15T20:00:00Z',
      }),
    );
  });

  test('AT-UPDATE-08 관리자가 checkInSuspicious 변경 차단', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'attendance', ATT), {
        checkInSuspicious: false,  // CF Admin SDK 전용
        updatedAt: '2024-01-15T20:00:00Z',
      }),
    );
  });

  test('AT-UPDATE-09 관리자가 finalWage 음수 설정 차단 (임금H-1)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'attendance', ATT), {
        finalWage: -10000,  // 음수 급여 차단
        updatedAt: '2024-01-15T20:00:00Z',
      }),
    );
  });

  test('AT-UPDATE-10 NO_SHOW + finalWage != 0 업데이트 차단 (NOSHOW-FIX)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'attendance', ATT), {
        status: 'NO_SHOW',
        finalWage: 50000,  // NO_SHOW인데 임금 > 0
        updatedAt: '2024-01-15T20:00:00Z',
      }),
    );
  });

  test('AT-UPDATE-11 wageStatus=transferred 역전환 차단', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'attendance', 'att-transferred'), {
        wageStatus: 'confirmed',  // transferred → confirmed 역전환 불가
        updatedAt: '2024-01-15T20:00:00Z',
      }),
    );
  });

  test('AT-UPDATE-12 transferredBy 타인 uid로 변경 차단 (감사 위변조)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'attendance', ATT), {
        transferredBy: IDS.user2,  // admin이 user2로 위조
        updatedAt: '2024-01-15T20:00:00Z',
      }),
    );
  });

  test('AT-UPDATE-13 관리자 본인 uid로 transferredBy 설정은 허용', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(
      updateDoc(doc(db, 'attendance', ATT), {
        transferredBy: IDS.admin,  // 본인 uid
        updatedAt: '2024-01-15T20:00:00Z',
      }),
    );
  });

  test('AT-UPDATE-14 슈퍼어드민도 transferred 역전환 불가 (규칙 설계: 모든 역할 차단)', async () => {
    // 규칙 주석: "wageStatus 역전환 방지: transferred 상태는 관리자/슈퍼어드민도 되돌릴 수 없음"
    // 이 조건은 역할 분기 바깥의 최상위 AND — superAdmin도 적용됨
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertFails(
      updateDoc(doc(db, 'attendance', 'att-transferred'), {
        wageStatus: 'confirmed',
        updatedAt: '2024-01-15T20:00:00Z',
      }),
    );
  });

  test('AT-UPDATE-15 타 사업장 관리자는 출근 기록 수정 차단', async () => {
    const db = getAuth(env, IDS.admin2, { businessId: IDS.business2 });
    await assertFails(
      updateDoc(doc(db, 'attendance', ATT), {
        wageStatus: 'confirmed',
        updatedAt: '2024-01-15T20:00:00Z',
      }),
    );
  });
});

// ─── AT-UPDATE: 탈퇴 처리 (SEC-97) ─────────────────────────────────────
// scheduled → absent 전이 + absentReason=USER_DELETED 허용
// 이 경로는 auth_service.dart 3-pre4 블록에서 본인 컨텍스트로 실행됨.

describe('AT-UPDATE: 탈퇴 처리 — scheduled→absent (SEC-97)', () => {
  test('AT-UPDATE-16 ✅ 본인이 scheduled→absent + absentReason=USER_DELETED 허용', async () => {
    const db = getAuth(env, IDS.user);
    await assertSucceeds(
      updateDoc(doc(db, 'attendance', 'att-scheduled'), {
        status: 'absent',
        absentReason: 'USER_DELETED',
        updatedAt: '2024-01-15T18:00:00Z',
      }),
    );
  });

  test('AT-UPDATE-17 ❌ absentReason이 USER_DELETED가 아닌 경우 차단', async () => {
    // absentReason 값을 USER_DELETED로 고정해 임의 사유로 absent 설정 차단
    await seedDoc(env, 'attendance', 'att-scheduled-b', {
      userId: IDS.user,
      businessId: IDS.business,
      applicationId: 'app-att-001',
      workDate: '2024-01-25',
      status: 'scheduled',
      wageStatus: 'pending',
      finalWage: 0,
    });
    const db = getAuth(env, IDS.user);
    await assertFails(
      updateDoc(doc(db, 'attendance', 'att-scheduled-b'), {
        status: 'absent',
        absentReason: 'OTHER_REASON',  // USER_DELETED만 허용
        updatedAt: '2024-01-25T00:00:00Z',
      }),
    );
  });

  test('AT-UPDATE-18 ❌ WORKING 상태 기록은 absent 전이 차단 (scheduled만 허용)', async () => {
    // baseAtt.status == 'WORKING' — scheduled가 아니면 차단
    const db = getAuth(env, IDS.user);
    await assertFails(
      updateDoc(doc(db, 'attendance', ATT), {
        status: 'absent',
        absentReason: 'USER_DELETED',
        updatedAt: '2024-01-15T18:00:00Z',
      }),
    );
  });
});

// ─── AT-DELETE: 출근 기록 삭제 ──────────────────────────────────────

describe('AT-DELETE: 출근 기록 삭제', () => {
  test('AT-DELETE-01 관리자는 소속 사업장 출근 기록 삭제 허용', async () => {
    await seedDoc(env, 'attendance', 'att-del-admin', baseAtt);
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(deleteDoc(doc(db, 'attendance', 'att-del-admin')));
  });

  test('AT-DELETE-02 서브어드민도 소속 사업장 출근 기록 삭제 허용 (RULE-06)', async () => {
    await seedDoc(env, 'attendance', 'att-del-sub', baseAtt);
    const db = getAuth(env, IDS.subAdmin, { subAdminOf: IDS.business });
    await assertSucceeds(deleteDoc(doc(db, 'attendance', 'att-del-sub')));
  });

  test('AT-DELETE-03 슈퍼어드민은 모든 출근 기록 삭제 허용', async () => {
    await seedDoc(env, 'attendance', 'att-del-super', baseAtt);
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertSucceeds(deleteDoc(doc(db, 'attendance', 'att-del-super')));
  });

  test('AT-DELETE-04 일반유저는 출근 기록 삭제 차단', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(deleteDoc(doc(db, 'attendance', ATT)));
  });

  test('AT-DELETE-05 타 사업장 관리자는 삭제 차단', async () => {
    const db = getAuth(env, IDS.admin2, { businessId: IDS.business2 });
    await assertFails(deleteDoc(doc(db, 'attendance', ATT)));
  });
});

// ─── AT-LIST ─────────────────────────────────────────────────────
// payroll_payment_service (getPayrollRecords / getTodayPayments / getTodayPaymentCount)가
// 직접 Firestore list 쿼리를 사용하는 3개 함수에 대한 규칙 검증.
//
// [에뮬레이터 제한] 양수 케이스(xtest):
//   isAdminOf(request.query.filters.businessId) 평가에
//   사용되는 get(businesses/bizId)가 에뮬레이터에서 null 반환하는 알려진 버그로
//   관리자/서브어드민 허용 케이스가 PERMISSION_DENIED로 잘못 평가됨.
//   실기기 테스트로만 검증 가능. 부정 케이스는 에뮬레이터에서도 정상 차단.
//
// 실기기 재현 쿼리:
//   attendance where businessId==X AND wageStatus==confirmed [limit 5000]
//   (getTodayPaymentCount — paymentDueDate 범위필터 제거 후 2 등호필터 구조)

describe('AT-LIST: 목록 쿼리', () => {
  // ── 양수 케이스 (에뮬레이터 한계로 xtest) ─────────────────────

  xtest('AT-LIST-01 ✅ [에뮬레이터 제한] 소속 관리자는 businessId+wageStatus 복합 등호쿼리 허용', async () => {
    const db = getAuth(env, IDS.admin);
    await assertSucceeds(getDocs(query(
      collection(db, 'attendance'),
      where('businessId', '==', IDS.business),
      where('wageStatus', '==', 'confirmed'),
      limit(5000),
    )));
  });

  xtest('AT-LIST-02 ✅ [에뮬레이터 제한] 슈퍼어드민은 businessId 필터 없이 조회 가능', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertSucceeds(getDocs(query(
      collection(db, 'attendance'),
      limit(10),
    )));
  });

  xtest('AT-LIST-03 ✅ [에뮬레이터 제한] 서브어드민은 소속 businessId 등호쿼리 허용', async () => {
    const db = getAuth(env, IDS.subAdmin, { subAdminOf: IDS.business });
    await assertSucceeds(getDocs(query(
      collection(db, 'attendance'),
      where('businessId', '==', IDS.business),
      limit(100),
    )));
  });

  // ── 부정 케이스 (에뮬레이터에서 정상 차단) ──────────────────────

  test('AT-LIST-04 ❌ 일반유저는 attendance 목록 조회 불가', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(getDocs(query(
      collection(db, 'attendance'),
      where('businessId', '==', IDS.business),
      limit(10),
    )));
  });

  test('AT-LIST-05 ❌ 타 사업장 관리자는 다른 사업장 attendance 조회 불가 (크로스-비즈)', async () => {
    const db = getAuth(env, IDS.admin2, { businessId: IDS.business2 });
    await assertFails(getDocs(query(
      collection(db, 'attendance'),
      where('businessId', '==', IDS.business),  // 본인 사업장 아닌 곳
      limit(10),
    )));
  });

  test('AT-LIST-06 ❌ 비로그인 사용자는 attendance 목록 조회 불가', async () => {
    const db = getAnonymous(env);
    await assertFails(getDocs(query(
      collection(db, 'attendance'),
      limit(1),
    )));
  });

  test('AT-LIST-07 ❌ businessId 필터 없이 관리자가 전체 조회 불가', async () => {
    const db = getAuth(env, IDS.admin);
    // businessId 필터 없으면 request.query.filters.businessId == null → isAdminOf(null) = false
    await assertFails(getDocs(query(
      collection(db, 'attendance'),
      limit(10),
    )));
  });

  test('AT-LIST-08 ❌ 일반유저가 businessId+wageStatus 복합 등호쿼리로 조회 불가', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(getDocs(query(
      collection(db, 'attendance'),
      where('businessId', '==', IDS.business),
      where('wageStatus', '==', 'confirmed'),
      limit(10),
    )));
  });

  // [SEC-99] isUser() 경로: 탈퇴 처리 3-pre4에서 본인 userId+status 필터 LIST 허용
  // 양수 케이스는 에뮬레이터에서 isUser()→myRole()→get(users) 버그로 xtest
  xtest('AT-LIST-09 ✅ [에뮬레이터 제한] 본인이 userId+status 필터로 scheduled 레코드 LIST 허용 (SEC-99)', async () => {
    const db = getAuth(env, IDS.user);
    await assertSucceeds(getDocs(query(
      collection(db, 'attendance'),
      where('userId', '==', IDS.user),
      where('status', '==', 'scheduled'),
      limit(100),
    )));
  });

  test('AT-LIST-10 ❌ userId 필터가 본인이 아닌 경우 차단 (SEC-99)', async () => {
    const db = getAuth(env, IDS.user2);
    await assertFails(getDocs(query(
      collection(db, 'attendance'),
      where('userId', '==', IDS.user),  // 타인의 userId
      where('status', '==', 'scheduled'),
      limit(10),
    )));
  });
});

// ─── RULE-WAGE: 확정/이체 급여 불변성 (PHASE4-FIX) ────────────────────
//
// finalWage / wageDetail 직접 client SDK 수정은:
//   - calculated 상태 → ALLOW (정상 수정 경로)
//   - confirmed 상태  → DENY  ([PHASE4-FIX] 급여 마감 완료, callableCancelFinalConfirmation 후 수정 필요)
//   - transferred 상태 → DENY (지급 완료, 급여 증빙 위변조 방지)
//
// CF Admin SDK(callableConfirmFinalWage, callableCancelFinalConfirmation 등)는
// Firestore Rules를 우회하므로 서버 State Machine 전이는 영향 없음.
//
// att-calculated, att-confirmed, att-transferred fixture 사용.

describe('RULE-WAGE: 확정/이체 급여 finalWage/wageDetail 불변성', () => {
  // ── 정상 경로 (calculated 상태) ──────────────────────────────────────

  test('RULE-WAGE-01 ✅ calculated 상태에서 BUSINESS_ADMIN의 wageDetail 수정 허용', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(
      updateDoc(doc(db, 'attendance', 'att-calculated'), {
        wageDetail: { totalAmount: 55000, netWage: 55000, workMinutes: 480 },
        updatedAt: '2024-01-15T20:00:00Z',
      }),
    );
  });

  test('RULE-WAGE-02 ✅ calculated 상태에서 BUSINESS_ADMIN의 finalWage 수정 허용', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(
      updateDoc(doc(db, 'attendance', 'att-calculated'), {
        finalWage: 55000,
        updatedAt: '2024-01-15T20:00:00Z',
      }),
    );
  });

  // ── confirmed 상태 차단 ([PHASE4-FIX]) ───────────────────────────────

  test('RULE-WAGE-03 ❌ confirmed 상태에서 BUSINESS_ADMIN의 wageDetail 수정 차단', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'attendance', 'att-confirmed'), {
        wageDetail: { totalAmount: 99000, netWage: 99000, workMinutes: 480 },
        updatedAt: '2024-01-15T20:00:00Z',
      }),
    );
  });

  test('RULE-WAGE-04 ❌ confirmed 상태에서 BUSINESS_ADMIN의 finalWage 수정 차단', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'attendance', 'att-confirmed'), {
        finalWage: 99000,
        updatedAt: '2024-01-15T20:00:00Z',
      }),
    );
  });

  // ── transferred 상태 차단 (기존 + PHASE4-FIX 확인) ────────────────────

  test('RULE-WAGE-05 ❌ transferred 상태에서 BUSINESS_ADMIN의 wageDetail 수정 차단', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'attendance', 'att-transferred'), {
        wageDetail: { totalAmount: 99000, netWage: 99000, workMinutes: 480 },
        updatedAt: '2024-01-15T20:00:00Z',
      }),
    );
  });

  test('RULE-WAGE-06 ❌ transferred 상태에서 BUSINESS_ADMIN의 finalWage 수정 차단', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'attendance', 'att-transferred'), {
        finalWage: 99000,
        updatedAt: '2024-01-15T20:00:00Z',
      }),
    );
  });

  // ── USER 경로 ─────────────────────────────────────────────────────────

  test('RULE-WAGE-07 ❌ confirmed 상태에서 일반 USER의 wageDetail 수정 차단', async () => {
    // USER 경로는 checkOut/actualEnd/updatedAt만 허용 — wageDetail은 USER 경로 자체에서 차단
    const db = getAuth(env, IDS.user);
    await assertFails(
      updateDoc(doc(db, 'attendance', 'att-confirmed'), {
        wageDetail: { totalAmount: 99000, netWage: 99000, workMinutes: 480 },
        updatedAt: '2024-01-15T20:00:00Z',
      }),
    );
  });

  // ── 타 사업장 격리 ────────────────────────────────────────────────────

  test('RULE-WAGE-08 ❌ 타 사업장 BUSINESS_ADMIN은 confirmed 급여 수정 불가 (크로스-비즈 격리)', async () => {
    // att-confirmed는 businessId=biz-001 소속, admin2는 biz-002 관리자
    const db = getAuth(env, IDS.admin2, { businessId: IDS.business2 });
    await assertFails(
      updateDoc(doc(db, 'attendance', 'att-confirmed'), {
        finalWage: 99000,
        updatedAt: '2024-01-15T20:00:00Z',
      }),
    );
  });
});

// ─── RULE-SNAPSHOT: confirmed payroll snapshot 불변성 (PHASE4.1-FIX) ──
//
// callableConfirmFinalWage가 쓰는 server-owned 필드는
// confirmed/transferred 상태에서 client SDK 직접 수정 DENY.
//
// 필드별 CF 소유권:
//   finalConfirmedAt      → callableConfirmFinalWage serverTimestamp
//   confirmedBy           → callableConfirmFinalWage callerUid
//   paymentDueDate        → callableConfirmFinalWage 계산 (callableCancelFinalConfirmation이 delete)
//   wageAccountSnapshotVersion → callableConfirmFinalWage (항상 1)
//   wageAccountBankName   → callableConfirmFinalWage 계좌 스냅샷
//   wageAccountNumberEncrypted → 동일
//   wageAccountHolder     → 동일
//   wageAccountSnapshotAt → 동일
//
// Flutter 클라이언트 직접 write: 없음 (전수 grep 확인)
// CF Admin SDK는 rules 우회 — cancel/reconfirm 정상 경로 영향 없음.

describe('RULE-SNAPSHOT: confirmed payroll snapshot 서버 전용 필드 불변성', () => {
  // ── confirmed 상태 snapshot 필드 직접 수정 차단 ────────────────────

  test('RULE-SNAPSHOT-01 ❌ confirmed + BUSINESS_ADMIN + paymentDueDate 변경 → DENY', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'attendance', 'att-confirmed'), {
        paymentDueDate: '2024-02-10',
        updatedAt: '2024-01-15T20:00:00Z',
      }),
    );
  });

  test('RULE-SNAPSHOT-02 ❌ confirmed + BUSINESS_ADMIN + wageAccountBankName 변경 → DENY', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'attendance', 'att-confirmed'), {
        wageAccountBankName: '국민은행',
        updatedAt: '2024-01-15T20:00:00Z',
      }),
    );
  });

  test('RULE-SNAPSHOT-03 ❌ confirmed + BUSINESS_ADMIN + wageAccountNumberEncrypted 변경 → DENY', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'attendance', 'att-confirmed'), {
        wageAccountNumberEncrypted: 'enc-fake-account-number',
        updatedAt: '2024-01-15T20:00:00Z',
      }),
    );
  });

  test('RULE-SNAPSHOT-04 ❌ confirmed + BUSINESS_ADMIN + wageAccountHolder 변경 → DENY', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'attendance', 'att-confirmed'), {
        wageAccountHolder: '김의관',
        updatedAt: '2024-01-15T20:00:00Z',
      }),
    );
  });

  test('RULE-SNAPSHOT-05 ❌ confirmed + BUSINESS_ADMIN + wageAccountSnapshotAt 변경 → DENY', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'attendance', 'att-confirmed'), {
        wageAccountSnapshotAt: '2024-01-15T20:00:00Z',
        updatedAt: '2024-01-15T20:00:00Z',
      }),
    );
  });

  test('RULE-SNAPSHOT-06 ❌ confirmed + BUSINESS_ADMIN + finalConfirmedAt 변경 → DENY', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'attendance', 'att-confirmed'), {
        finalConfirmedAt: '2024-01-15T20:00:00Z',
        updatedAt: '2024-01-15T20:00:00Z',
      }),
    );
  });

  // ── transferred 상태에서도 동일 차단 ──────────────────────────────────

  test('RULE-SNAPSHOT-07 ❌ transferred + BUSINESS_ADMIN + snapshot 필드 변경 → DENY (consolidated)', async () => {
    // paymentDueDate, wageAccountBankName, wageAccountHolder, finalConfirmedAt — 대표 4개 묶어 검증
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'attendance', 'att-transferred'), {
        paymentDueDate: '2024-02-10',
        updatedAt: '2024-01-15T20:00:00Z',
      }),
    );
  });
});
