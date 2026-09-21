// rules-test/src/rules/misc_requests.test.ts
// member_invitations + payment_change_requests + interim_settlement_requests
// + app_settings + id_card_copy_logs + CF전용 차단 (40개 시나리오)
import { RulesTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc, serverTimestamp } from 'firebase/firestore';
import {
  createTestEnv, getAuth, seedDoc, seedCommonFixtures,
  assertFails, assertSucceeds, IDS,
} from '../helpers/test-env';

let env: RulesTestEnvironment;

beforeAll(async () => {
  env = await createTestEnv('misc_requests');
  await seedCommonFixtures(env);

  // user에 businessId 세팅 (소속 검증)
  await seedDoc(env, 'users', IDS.user, {
    role: 'USER', username: 'user1', name: '유저1',
    email: 'user@test.com', isBlacklisted: false,
    businessId: IDS.business,
  });

  // member_invitations
  await seedDoc(env, 'member_invitations', 'inv-test', {
    targetUid: IDS.user,
    invitedBy: IDS.admin,
    businessId: IDS.business,
    status: 'pending',
    createdAt: '2024-01-01T00:00:00Z',
  });
  await seedDoc(env, 'member_invitations', 'inv-accepted', {
    targetUid: IDS.user,
    invitedBy: IDS.admin,
    businessId: IDS.business,
    status: 'accepted',
    createdAt: '2024-01-01T00:00:00Z',
  });

  // payment_change_requests
  await seedDoc(env, 'payment_change_requests', 'pcr-001', {
    workerId: IDS.user,
    businessId: IDS.business,
    status: 'PENDING',
    requestedAt: '2024-01-15T09:00:00Z',
  });
  await seedDoc(env, 'payment_change_requests', 'pcr-approved', {
    workerId: IDS.user,
    businessId: IDS.business,
    status: 'APPROVED',
    requestedAt: '2024-01-15T09:00:00Z',
  });

  // interim_settlement_requests
  await seedDoc(env, 'interim_settlement_requests', 'isr-001', {
    workerId: IDS.user,
    businessId: IDS.business,
    status: 'PENDING',
    requestedAt: '2024-01-15T09:00:00Z',
  });

  // app_settings
  await seedDoc(env, 'app_settings', 'terms', {
    version: '1.0',
    content: '약관 내용',
    updatedAt: '2024-01-01T00:00:00Z',
  });

  // id_card_copy_logs
  await seedDoc(env, 'id_card_copy_logs', 'log-001', {
    viewerId: IDS.admin,
    businessId: IDS.business,
    targetUserId: IDS.user,
    viewedAt: '2024-01-15T09:00:00Z',
  });
});

afterAll(async () => { await env.cleanup(); });

// ═══════════════════════════════════════════════════════════════════════
// MEMBER_INVITATIONS
// ═══════════════════════════════════════════════════════════════════════

describe('MEMBER_INVITATIONS: 초대장 접근 제어', () => {
  test('INV-GET-01 수신자(targetUid)는 초대장을 읽을 수 있다', async () => {
    const db = getAuth(env, IDS.user);
    await assertSucceeds(getDoc(doc(db, 'member_invitations', 'inv-test')));
  });

  test('INV-GET-02 발신자(invitedBy)는 초대장을 읽을 수 있다', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(getDoc(doc(db, 'member_invitations', 'inv-test')));
  });

  test('INV-GET-03 관계없는 유저는 초대장을 읽을 수 없다', async () => {
    const db = getAuth(env, IDS.user2);
    await assertFails(getDoc(doc(db, 'member_invitations', 'inv-test')));
  });

  // [R8-P3B.3A.1] 정책은 그대로다 — fixture에 createdAt이 없었다.
  //   [LOW-FIX] createdAt == request.time 강제. 미래 날짜를 주입해
  //   초대 유효기간(3일)을 무한정 늘리는 것을 막는다.
  test('INV-CREATE-01 관리자가 본인 invitedBy로 초대장 생성 허용 (SEC-31)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(
      setDoc(doc(db, 'member_invitations', 'inv-new'), {
        targetUid: IDS.user2,
        invitedBy: IDS.admin,
        businessId: IDS.business,
        status: 'pending',
        createdAt: serverTimestamp(),
      }),
    );
  });

  // [R8-P3B.3A.1] 신규 — createdAt 위조 차단 확인 ([LOW-FIX])
  test('INV-CREATE-01b createdAt을 미래 날짜로 심으면 차단된다', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      setDoc(doc(db, 'member_invitations', 'inv-future'), {
        targetUid: IDS.user2,
        invitedBy: IDS.admin,
        businessId: IDS.business,
        status: 'pending',
        createdAt: new Date(2099, 0, 1),
      }),
    );
  });

  test('INV-CREATE-02 invitedBy 위조 차단 (SEC-31)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      setDoc(doc(db, 'member_invitations', 'inv-fake'), {
        targetUid: IDS.user2,
        invitedBy: IDS.admin2,  // 타인 명의 위조
        businessId: IDS.business,
        status: 'pending',
      }),
    );
  });

  test('INV-CREATE-03 일반유저는 초대장 생성 차단', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      setDoc(doc(db, 'member_invitations', 'inv-user'), {
        targetUid: IDS.user2,
        invitedBy: IDS.user,
        businessId: IDS.business,
        status: 'pending',
      }),
    );
  });

  test('INV-UPDATE-01 수신자가 pending→accepted 전환 허용 (SEC-FIX)', async () => {
    const db = getAuth(env, IDS.user);
    await assertSucceeds(
      updateDoc(doc(db, 'member_invitations', 'inv-test'), {
        status: 'accepted',
        respondedAt: '2024-01-15T10:00:00Z',
      }),
    );
  });

  test('INV-UPDATE-02 accepted 상태에서 rejected로 재변경 차단 (SEC-FIX)', async () => {
    // inv-accepted는 status=accepted
    const db = getAuth(env, IDS.user);
    await assertFails(
      updateDoc(doc(db, 'member_invitations', 'inv-accepted'), {
        status: 'rejected',
        respondedAt: '2024-01-15T10:00:00Z',
      }),
    );
  });

  test('INV-UPDATE-03 관리자가 pending 초대장 취소 허용', async () => {
    await seedDoc(env, 'member_invitations', 'inv-cancel', {
      targetUid: IDS.user2, invitedBy: IDS.admin,
      businessId: IDS.business, status: 'pending',
    });
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(
      updateDoc(doc(db, 'member_invitations', 'inv-cancel'), {
        status: 'cancelled',
        canceledAt: '2024-01-15T10:00:00Z',
      }),
    );
  });

  test('INV-DELETE-01 발신자(invitedBy)는 초대장 삭제 허용 (SEC-44)', async () => {
    await seedDoc(env, 'member_invitations', 'inv-del', {
      targetUid: IDS.user2, invitedBy: IDS.admin,
      businessId: IDS.business, status: 'pending',
    });
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(deleteDoc(doc(db, 'member_invitations', 'inv-del')));
  });
});

// ═══════════════════════════════════════════════════════════════════════
// PAYMENT_CHANGE_REQUESTS
// ═══════════════════════════════════════════════════════════════════════

describe('PAYMENT_CHANGE_REQUESTS: 지급방식 변경 요청', () => {
  test('PCR-GET-01 요청자 본인은 자신의 요청을 읽을 수 있다', async () => {
    const db = getAuth(env, IDS.user);
    await assertSucceeds(getDoc(doc(db, 'payment_change_requests', 'pcr-001')));
  });

  test('PCR-GET-02 서브어드민도 읽을 수 있다 (HIGH-FIX)', async () => {
    const db = getAuth(env, IDS.subAdmin, { subAdminOf: IDS.business });
    await assertSucceeds(getDoc(doc(db, 'payment_change_requests', 'pcr-001')));
  });

  test('PCR-GET-03 타 사업장 관리자는 읽을 수 없다', async () => {
    const db = getAuth(env, IDS.admin2, { businessId: IDS.business2 });
    await assertFails(getDoc(doc(db, 'payment_change_requests', 'pcr-001')));
  });

  // [R8-P3B.3A.1] 정책은 그대로다 — fixture가 허용 필드 목록 밖의 requestedAt을 보냈다.
  //   [LOW-FIX] keys().hasOnly([...]) 화이트리스트가 붙어 processedBy/processedAt 등
  //   처리 결과 필드를 create 시점에 심지 못하게 한다. requestedAt은 그 목록에 없다.
  test('PCR-CREATE-01 근무자 본인이 소속 사업장으로 생성 허용', async () => {
    const db = getAuth(env, IDS.user);
    await assertSucceeds(
      setDoc(doc(db, 'payment_change_requests', 'pcr-user-new'), {
        workerId: IDS.user,
        businessId: IDS.business,  // 소속 사업장
        status: 'PENDING',
        createdAt: serverTimestamp(),  // [TS-FIX] 서버 시각 강제
      }),
    );
  });

  // [R8-P3B.3A.1] 신규 — 처리 결과 필드 선주입 차단 확인 ([LOW-FIX] 화이트리스트)
  test('PCR-CREATE-01b 생성 시 processedBy/processedAt을 심을 수 없다', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      setDoc(doc(db, 'payment_change_requests', 'pcr-preprocessed'), {
        workerId: IDS.user,
        businessId: IDS.business,
        status: 'PENDING',
        createdAt: serverTimestamp(),
        processedBy: IDS.user,
        processedAt: new Date(),
      }),
    );
  });

  test('PCR-CREATE-02 타 사업장 businessId로 생성 차단 (MED-BYPASS-FIX)', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      setDoc(doc(db, 'payment_change_requests', 'pcr-cross'), {
        workerId: IDS.user,
        businessId: IDS.business2,  // 소속 아닌 사업장
        status: 'PENDING',
        requestedAt: '2024-01-15T09:00:00Z',
      }),
    );
  });

  test('PCR-CREATE-03 빈 businessId로 생성 차단 (MED-BYPASS-FIX)', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      setDoc(doc(db, 'payment_change_requests', 'pcr-empty-biz'), {
        workerId: IDS.user,
        businessId: '',
        status: 'PENDING',
        requestedAt: '2024-01-15T09:00:00Z',
      }),
    );
  });

  test('PCR-CREATE-04 USER가 status=APPROVED로 직접 생성 차단 (SEC-84)', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      setDoc(doc(db, 'payment_change_requests', 'pcr-fake-approved'), {
        workerId: IDS.user,
        businessId: IDS.business,
        status: 'APPROVED',  // PENDING이 아닌 상태로 직접 생성 시도
        requestedAt: '2024-01-15T09:00:00Z',
      }),
    );
  });

  test('PCR-UPDATE-01 관리자가 PENDING→APPROVED 처리 허용 (SEC-61)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(
      updateDoc(doc(db, 'payment_change_requests', 'pcr-001'), {
        status: 'APPROVED',
        processedBy: IDS.admin,
        processedAt: '2024-01-15T10:00:00Z',
        updatedAt: '2024-01-15T10:00:00Z',
      }),
    );
  });

  test('PCR-UPDATE-02 APPROVED 상태에서 상태 변경 차단 (SEC-61 역변조)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'payment_change_requests', 'pcr-approved'), {
        status: 'REJECTED',
        processedBy: IDS.admin,
        processedAt: '2024-01-15T10:00:00Z',
        updatedAt: '2024-01-15T10:00:00Z',
      }),
    );
  });

  test('PCR-DELETE-01 슈퍼어드민만 삭제 허용', async () => {
    await seedDoc(env, 'payment_change_requests', 'pcr-del', {
      workerId: IDS.user, businessId: IDS.business, status: 'PENDING',
    });
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertSucceeds(deleteDoc(doc(db, 'payment_change_requests', 'pcr-del')));
  });
});

// ═══════════════════════════════════════════════════════════════════════
// INTERIM_SETTLEMENT_REQUESTS
// ═══════════════════════════════════════════════════════════════════════

describe('INTERIM_SETTLEMENT_REQUESTS: 중간정산 요청', () => {
  test('ISR-GET-01 요청자 본인은 자신의 중간정산 요청을 읽을 수 있다', async () => {
    const db = getAuth(env, IDS.user);
    await assertSucceeds(getDoc(doc(db, 'interim_settlement_requests', 'isr-001')));
  });

  test('ISR-GET-02 서브어드민도 읽을 수 있다 (CRITICAL-FIX)', async () => {
    const db = getAuth(env, IDS.subAdmin, { subAdminOf: IDS.business });
    await assertSucceeds(getDoc(doc(db, 'interim_settlement_requests', 'isr-001')));
  });

  // [R8-P3B.3A.1] 정책은 그대로다 — PCR과 같은 화이트리스트 문제(requestedAt).
  test('ISR-CREATE-01 근무자 본인이 소속 사업장으로 생성 허용', async () => {
    const db = getAuth(env, IDS.user);
    await assertSucceeds(
      setDoc(doc(db, 'interim_settlement_requests', 'isr-user-new'), {
        workerId: IDS.user,
        businessId: IDS.business,
        status: 'PENDING',
        createdAt: serverTimestamp(),
      }),
    );
  });

  // [R8-P3B.3A.1] 기대값 반전 — [ISR-CREATE-01 2026-09-01] SUB_ADMIN direct CREATE 제거.
  //   관리자 생성 경로는 callableAdminDirectInterimSettlement(CF) 하나다.
  //   SubAdmin에게는 worker/amount/attendance 바인딩도, 정상 UX도 없어 최소권한으로 닫았다.
  test('ISR-CREATE-02 서브어드민은 중간정산 요청을 직접 생성할 수 없다 (CF 전용)', async () => {
    const db = getAuth(env, IDS.subAdmin, { subAdminOf: IDS.business });
    await assertFails(
      setDoc(doc(db, 'interim_settlement_requests', 'isr-sub-new'), {
        workerId: IDS.user,
        businessId: IDS.business,
        status: 'PENDING',
        createdAt: serverTimestamp(),
      }),
    );
  });

  // [R8-P3B.3A.1] 신규 — BUSINESS_ADMIN 경로는 열려 있는지 함께 고정
  test('ISR-CREATE-02b 사업장 관리자는 생성할 수 있다', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(
      setDoc(doc(db, 'interim_settlement_requests', 'isr-admin-new'), {
        workerId: IDS.user,
        businessId: IDS.business,
        status: 'PENDING',
        createdAt: serverTimestamp(),
      }),
    );
  });

  test('ISR-CREATE-03 타 사업장 businessId로 생성 차단', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      setDoc(doc(db, 'interim_settlement_requests', 'isr-cross'), {
        workerId: IDS.user,
        businessId: IDS.business2,
        status: 'PENDING',
        requestedAt: '2024-01-15T09:00:00Z',
      }),
    );
  });

  test('ISR-CREATE-04 USER가 status=PROCESSED로 직접 생성 차단 (SEC-85)', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      setDoc(doc(db, 'interim_settlement_requests', 'isr-fake-processed'), {
        workerId: IDS.user,
        businessId: IDS.business,
        status: 'PROCESSED',  // PENDING이 아닌 상태로 직접 생성 시도
        requestedAt: '2024-01-15T09:00:00Z',
      }),
    );
  });

  // [R8-P3B.3A.1] 상태 기계가 바뀌었다 — PENDING에서 바로 PROCESSED로 가지 않는다.
  //   [SEC-52] PENDING → APPROVED/REJECTED → (APPROVED만) PROCESSED.
  //   이체 실행(PROCESSED)은 승인된 건에만 붙는다.
  test('ISR-UPDATE-01 관리자가 PENDING→APPROVED 승인 허용 (SEC-52)', async () => {
    await seedDoc(env, 'interim_settlement_requests', 'isr-approve', {
      workerId: IDS.user, businessId: IDS.business, status: 'PENDING',
    });
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(
      updateDoc(doc(db, 'interim_settlement_requests', 'isr-approve'), {
        status: 'APPROVED',
        processedBy: IDS.admin,
        processedAt: '2024-01-15T10:00:00Z',
        updatedAt: '2024-01-15T10:00:00Z',
      }),
    );
  });

  // [R8-P3B.3A.1] 신규 — 단계 건너뛰기 차단
  test('ISR-UPDATE-01b PENDING에서 PROCESSED로 건너뛸 수 없다 (승인 단계 우회)', async () => {
    await seedDoc(env, 'interim_settlement_requests', 'isr-skip', {
      workerId: IDS.user, businessId: IDS.business, status: 'PENDING',
    });
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'interim_settlement_requests', 'isr-skip'), {
        status: 'PROCESSED',
        processedBy: IDS.admin,
        processedAt: '2024-01-15T10:00:00Z',
        updatedAt: '2024-01-15T10:00:00Z',
      }),
    );
  });

  // [R8-P3B.3A.1] 이전 테스트는 앞 테스트가 isr-001을 PROCESSED로 만들어 놓는 것에
  //   의존하고 있었다(순서 의존). 자기 fixture를 직접 만들어 독립시킨다.
  test('ISR-UPDATE-02 PROCESSED 상태에서 재처리 차단 (SEC-52 역변조)', async () => {
    await seedDoc(env, 'interim_settlement_requests', 'isr-processed', {
      workerId: IDS.user, businessId: IDS.business, status: 'PROCESSED',
    });
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'interim_settlement_requests', 'isr-processed'), {
        status: 'REJECTED',
        processedBy: IDS.admin,
        processedAt: '2024-01-15T11:00:00Z',
        updatedAt: '2024-01-15T11:00:00Z',
      }),
    );
  });
});

// ═══════════════════════════════════════════════════════════════════════
// APP_SETTINGS
// ═══════════════════════════════════════════════════════════════════════

describe('APP_SETTINGS: 앱 설정 접근 제어', () => {
  test('ASET-READ-01 로그인 유저는 앱 설정을 읽을 수 있다', async () => {
    const db = getAuth(env, IDS.user);
    await assertSucceeds(getDoc(doc(db, 'app_settings', 'terms')));
  });

  test('ASET-WRITE-01 슈퍼어드민은 앱 설정을 수정할 수 있다', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertSucceeds(
      updateDoc(doc(db, 'app_settings', 'terms'), { version: '1.1' }),
    );
  });

  test('ASET-WRITE-02 관리자는 앱 설정을 수정할 수 없다', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'app_settings', 'terms'), { version: '2.0' }),
    );
  });

  test('ASET-WRITE-03 일반유저는 앱 설정을 수정할 수 없다', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      setDoc(doc(db, 'app_settings', 'fake-setting'), { value: 'hacked' }),
    );
  });
});

// ═══════════════════════════════════════════════════════════════════════
// ID_CARD_COPY_LOGS (감사 로그 불변 보장)
// ═══════════════════════════════════════════════════════════════════════

describe('ID_CARD_COPY_LOGS: 신분증 열람 감사 로그', () => {
  // [R8-P3B.3A.1] 기대값 반전 — [GAP-ID-02] 클라이언트 create 완전 차단.
  //   신분증 열람 감사 로그는 열람을 수행하는 CF가 직접 남긴다:
  //   callableGetIdCardSignedUrl / callableLogResidentNumberCopy (Admin SDK).
  //   클라이언트가 쓰게 두면 열람하고도 로그를 안 남기는 선택이 가능해진다.
  //   worker_detail_dialog._logResidentNumberCopy의 client write는 제거 완료.
  test('ICCL-CREATE-01 관리자도 열람 로그를 직접 쓸 수 없다 (CF가 기록)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      setDoc(doc(db, 'id_card_copy_logs', 'log-admin-new'), {
        viewerId: IDS.admin,
        businessId: IDS.business,
        targetUserId: IDS.user,
        viewedAt: '2024-01-15T09:00:00Z',
      }),
    );
  });

  test('ICCL-CREATE-02 viewerId 위조 차단 (SEC-FIX)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      setDoc(doc(db, 'id_card_copy_logs', 'log-fake-viewer'), {
        viewerId: IDS.admin2,  // 타인 명의 위조
        businessId: IDS.business,
        targetUserId: IDS.user,
        viewedAt: '2024-01-15T09:00:00Z',
      }),
    );
  });

  test('ICCL-CREATE-03 타 사업장 businessId로 로그 생성 차단 (SEC-FIX)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      setDoc(doc(db, 'id_card_copy_logs', 'log-cross-biz'), {
        viewerId: IDS.admin,
        businessId: IDS.business2,  // 소속 아닌 사업장
        targetUserId: IDS.user,
        viewedAt: '2024-01-15T09:00:00Z',
      }),
    );
  });

  test('ICCL-READ-01 슈퍼어드민만 감사 로그를 읽을 수 있다', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertSucceeds(getDoc(doc(db, 'id_card_copy_logs', 'log-001')));
  });

  test('ICCL-READ-02 관리자는 감사 로그를 읽을 수 없다', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(getDoc(doc(db, 'id_card_copy_logs', 'log-001')));
  });

  test('ICCL-UPDATE-01 감사 로그 수정 완전 차단 (불변 보장)', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertFails(
      updateDoc(doc(db, 'id_card_copy_logs', 'log-001'), {
        viewedAt: '2099-01-01T00:00:00Z',
      }),
    );
  });

  test('ICCL-DELETE-01 감사 로그 삭제 완전 차단 (불변 보장)', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertFails(deleteDoc(doc(db, 'id_card_copy_logs', 'log-001')));
  });
});

// ═══════════════════════════════════════════════════════════════════════
// CF전용 컬렉션 완전 차단 검증
// ═══════════════════════════════════════════════════════════════════════

describe('CF전용 컬렉션: sms_verifications·passTokens·emailVerificationCodes 완전 차단', () => {
  test('CF-BLOCK-01 슈퍼어드민도 sms_verifications 읽기 차단', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('sms_verifications').doc('+82-010-1234').set({ code: '123456' });
    });
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertFails(getDoc(doc(db, 'sms_verifications', '+82-010-1234')));
  });

  test('CF-BLOCK-02 슈퍼어드민도 sms_verifications 쓰기 차단', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertFails(
      setDoc(doc(db, 'sms_verifications', '+82-010-9999'), { code: 'fake' }),
    );
  });

  test('CF-BLOCK-03 슈퍼어드민도 passTokens 읽기 차단', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('passTokens').doc('token-001').set({ uid: 'test' });
    });
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertFails(getDoc(doc(db, 'passTokens', 'token-001')));
  });

  test('CF-BLOCK-04 모든 클라이언트의 passTokens 쓰기 차단', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      setDoc(doc(db, 'passTokens', 'fake-token'), { uid: 'hacked' }),
    );
  });
});
