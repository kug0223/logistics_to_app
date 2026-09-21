// rules-test/src/rules/tos.test.ts
// tos(공고) 컬렉션 보안 규칙 검증 (27개 시나리오)
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

const TO_ID = 'to-tos-001';

// 기본 공개 TO 픽스처
const baseTO = {
  businessId: IDS.business,
  isPublished: true,
  status: 'OPEN',
  workDetailId: 'wd-001',
  totalRequired: 5,
  totalConfirmed: 2,
  totalPending: 1,
  workTypeConfirmedCounts: { 'wt-001': 2 },
  startDate: '2024-02-01',
  endDate: '2024-12-31',
  workDays: ['MON', 'TUE', 'WED', 'THU', 'FRI'],
  workTypeIds: ['wt-001'],
};

beforeAll(async () => {
  env = await createTestEnv('tos');
  await seedCommonFixtures(env);

  // 공개 TO
  await seedDoc(env, 'tos', TO_ID, baseTO);

  // 비공개 TO (S-M3-FIX 검증)
  await seedDoc(env, 'tos', 'to-private', {
    ...baseTO,
    isPublished: false,
  });

  // CLOSED 상태 TO (핵심 필드 변경 차단)
  await seedDoc(env, 'tos', 'to-closed', {
    ...baseTO,
    status: 'CLOSED',
  });

  // EXPIRED 상태 TO
  await seedDoc(env, 'tos', 'to-expired', {
    ...baseTO,
    status: 'EXPIRED',
  });
});

afterAll(async () => {
  await env.cleanup();
});

// ─── TO-GET: 단건 읽기 ──────────────────────────────────────────────

describe('TO-GET: 단건 읽기', () => {
  test('TO-GET-01 로그인 유저는 공개 TO를 읽을 수 있다', async () => {
    const db = getAuth(env, IDS.user);
    await assertSucceeds(getDoc(doc(db, 'tos', TO_ID)));
  });

  test('TO-GET-02 관리자는 비공개 TO를 읽을 수 있다 (S-M3-FIX)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(getDoc(doc(db, 'tos', 'to-private')));
  });

  test('TO-GET-03 일반유저는 비공개 TO를 읽을 수 없다 (S-M3-FIX)', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(getDoc(doc(db, 'tos', 'to-private')));
  });

  test('TO-GET-04 슈퍼어드민은 비공개 TO도 읽을 수 있다', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertSucceeds(getDoc(doc(db, 'tos', 'to-private')));
  });

  test('TO-GET-05 서브어드민은 소속 사업장의 비공개 TO를 읽을 수 있다', async () => {
    const db = getAuth(env, IDS.subAdmin, { subAdminOf: IDS.business });
    await assertSucceeds(getDoc(doc(db, 'tos', 'to-private')));
  });

  test('TO-GET-06 타 사업장 관리자는 비공개 TO를 읽을 수 없다', async () => {
    const db = getAuth(env, IDS.admin2, { businessId: IDS.business2 });
    await assertFails(getDoc(doc(db, 'tos', 'to-private')));
  });

  test('TO-GET-07 미인증 사용자는 TO를 읽을 수 없다', async () => {
    const db = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, 'tos', TO_ID)));
  });
});

// ─── TO-CREATE: 공고 생성 ─────────────────────────────────────────────

describe('TO-CREATE: 공고 생성', () => {
  // [R8-P3B.3A.1] 기대값 반전 — [HIGH-02] tos create = if false.
  //   공고 생성은 callableCreateTO(Admin SDK) 전용이다. CF가 등록 개수 제한을
  //   트랜잭션으로 강제하고 serverTimestamp를 찍는다. 클라이언트 직접 create를
  //   열어 두면 개수 제한(MAX_ACTIVE_TO_LIMIT)을 그냥 우회할 수 있다.
  test('TO-CREATE-01 관리자도 공고를 직접 생성할 수 없다 (callableCreateTO 전용)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      setDoc(doc(db, 'tos', 'to-admin-new'), {
        businessId: IDS.business,
        isPublished: false,
        status: 'OPEN',
        totalRequired: 3,
        totalConfirmed: 0,
        totalPending: 0,
      }),
    );
  });

  test('TO-CREATE-02 서브어드민도 공고를 직접 생성할 수 없다 (CF 전용)', async () => {
    const db = getAuth(env, IDS.subAdmin, { subAdminOf: IDS.business });
    await assertFails(
      setDoc(doc(db, 'tos', 'to-sub-new'), {
        businessId: IDS.business,
        isPublished: false,
        status: 'OPEN',
        totalRequired: 2,
        totalConfirmed: 0,
        totalPending: 0,
      }),
    );
  });

  test('TO-CREATE-03 일반유저는 공고를 생성할 수 없다', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      setDoc(doc(db, 'tos', 'to-user-new'), {
        businessId: IDS.business,
        isPublished: false,
        status: 'OPEN',
      }),
    );
  });

  test('TO-CREATE-04 타 사업장 관리자는 다른 사업장에 공고를 생성할 수 없다', async () => {
    const db = getAuth(env, IDS.admin2, { businessId: IDS.business2 });
    await assertFails(
      setDoc(doc(db, 'tos', 'to-cross-biz'), {
        businessId: IDS.business,  // admin2는 biz-001 관리자 아님
        isPublished: false,
        status: 'OPEN',
      }),
    );
  });
});

// ─── TO-UPDATE: 관리자 공고 수정 ─────────────────────────────────────

describe('TO-UPDATE: 관리자 공고 수정', () => {
  test('TO-UPDATE-01 관리자는 OPEN 공고의 일반 필드를 수정할 수 있다', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(
      updateDoc(doc(db, 'tos', TO_ID), {
        isPublished: true,
        totalRequired: 8,
      }),
    );
  });

  test('TO-UPDATE-02 CLOSED 상태에서 workDetailId 변경 차단', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'tos', 'to-closed'), {
        workDetailId: 'wd-hacked',
      }),
    );
  });

  // [R8-P3B.3A.1] 기대값 반전 — [SLOT-SYNC 2026-07-15] totalRequired 단독 예외.
  //
  //   일반 TO 수정은 callableUpdateTO(Admin SDK)로 전부 넘어갔고, 거기서
  //   LOCKED_FIELDS·상태 검증·감사 로그를 처리한다. 다만 슬롯을 고칠 때
  //   tos.totalRequired를 같은 배치에서 increment해야 해서, **totalRequired만**
  //   바꾸는 경우에 한해 클라이언트 경로를 남겼다(>= 0 만 확인).
  //
  //   상태 가드를 여기 두지 않은 이유: totalRequired는 syncTOStats의 FULL 판정
  //   입력값일 뿐이고, 정원 게이트는 슬롯 단위(callableApplyToTO의 confirmedCount
  //   >= requiredCount)에 있다. 또 ACTIVE와 FULL은 둘 다 등록 개수 제한에
  //   포함되므로 FULL↔ACTIVE가 뒤집혀도 쿼터가 늘지 않는다.
  test('TO-UPDATE-03 CLOSED 상태에서도 totalRequired 단독 변경은 허용 (슬롯 동기화 예외)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(
      updateDoc(doc(db, 'tos', 'to-closed'), {
        totalRequired: 10,
      }),
    );
  });

  // [R8-P3B.3A.1] 신규 — 예외는 "totalRequired 단독"일 때만이라는 점을 고정한다.
  test('TO-UPDATE-03b totalRequired에 다른 필드를 얹으면 차단된다', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'tos', 'to-closed'), {
        totalRequired: 11,
        title: '몰래 바꾸기',
      }),
    );
  });

  test('TO-UPDATE-03c 음수 totalRequired는 차단된다', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'tos', 'to-closed'), {
        totalRequired: -1,
      }),
    );
  });

  test('TO-UPDATE-04 CLOSED 상태에서 startDate 변경 차단', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'tos', 'to-closed'), {
        startDate: '2025-01-01',
      }),
    );
  });

  test('TO-UPDATE-05 EXPIRED 상태에서 workDays 변경 차단', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'tos', 'to-expired'), {
        workDays: ['SAT', 'SUN'],
      }),
    );
  });

  test('TO-UPDATE-06 businessId는 항상 불변 (SEC-45)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'tos', TO_ID), {
        businessId: IDS.business2,
      }),
    );
  });

  test('TO-UPDATE-07 슈퍼어드민은 CLOSED 상태 필드도 변경 허용', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertSucceeds(
      updateDoc(doc(db, 'tos', 'to-closed'), {
        totalRequired: 10,
      }),
    );
  });

  // [R8-P3B.3A.1] 기대값 반전 — TO-H1 가드는 Rules가 아니라 CF에 있다.
  //   callableUpdateTO(functions/src/index.ts)가
  //   "totalRequired(N)는 확정 인원(M) 이상이어야 합니다"를 throw한다.
  //   Rules의 [SLOT-SYNC] 예외는 >= 0 만 본다 — 슬롯 동기화 increment 전용이기 때문이다.
  //   이 값이 확정 인원보다 낮아지면 syncTOStats가 공고를 FULL로 판정한다(보수적 방향).
  test('TO-UPDATE-08 totalRequired를 totalConfirmed 미만으로 낮추는 것은 Rules가 아닌 callableUpdateTO가 막는다', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    // totalConfirmed=2, totalRequired=5 → 1로 낮추기: rules 층에서는 통과한다
    await assertSucceeds(
      updateDoc(doc(db, 'tos', TO_ID), {
        totalRequired: 1,
      }),
    );
  });

  test('TO-UPDATE-09 totalRequired=0(무제한)으로 변경은 항상 허용', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(
      updateDoc(doc(db, 'tos', TO_ID), {
        totalRequired: 0,  // 무제한 설정은 예외 허용
      }),
    );
  });

  test('TO-UPDATE-10 타 사업장 관리자는 공고를 수정할 수 없다', async () => {
    const db = getAuth(env, IDS.admin2, { businessId: IDS.business2 });
    await assertFails(
      updateDoc(doc(db, 'tos', TO_ID), {
        isPublished: false,
      }),
    );
  });
});

// ─── TO-UPDATE: 지원자 카운터 수정 ───────────────────────────────────

describe('TO-UPDATE: 지원자 카운터 수정', () => {
  test('TO-UPDATE-11 지원자가 totalPending +1 허용', async () => {
    // 현재 totalPending=1 → 2
    const db = getAuth(env, IDS.user);
    await assertSucceeds(
      updateDoc(doc(db, 'tos', TO_ID), {
        totalPending: 2,
      }),
    );
  });

  test('TO-UPDATE-12 지원자가 totalPending -1 허용 (취소)', async () => {
    // 현재 totalPending=2 (직전 테스트에서 2로 변경됨) → 1
    const db = getAuth(env, IDS.user);
    await assertSucceeds(
      updateDoc(doc(db, 'tos', TO_ID), {
        totalPending: 1,
      }),
    );
  });

  test('TO-UPDATE-13 지원자가 totalPending +2 한번에 변경 차단 (MEDIUM-FIX)', async () => {
    // 현재 totalPending=1 → 3 (±1 초과)
    const db = getAuth(env, IDS.user);
    await assertFails(
      updateDoc(doc(db, 'tos', TO_ID), {
        totalPending: 3,
      }),
    );
  });

  test('TO-UPDATE-14 지원자가 totalPending 음수 설정 차단', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      updateDoc(doc(db, 'tos', TO_ID), {
        totalPending: -1,
      }),
    );
  });

  test('TO-UPDATE-15 지원자가 totalPending과 함께 다른 필드 수정 차단', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      updateDoc(doc(db, 'tos', TO_ID), {
        totalPending: 2,
        isPublished: false,  // 허용 외 필드
      }),
    );
  });

  test('TO-UPDATE-16 지원자가 totalConfirmed 직접 감소 차단 (C-HIGH-FIX: CF Admin SDK 전용)', async () => {
    // [C-HIGH-FIX] USER가 totalConfirmed를 직접 감소시키는 것 차단
    // callableDecrementSlotConfirmed CF(Admin SDK)가 유일한 감소 경로
    const db = getAuth(env, IDS.user);
    await assertFails(
      updateDoc(doc(db, 'tos', TO_ID), {
        totalConfirmed: 1,
        workTypeConfirmedCounts: { 'wt-001': 1 },
      }),
    );
  });

  test('TO-UPDATE-17 지원자가 totalConfirmed +1 차단 (MED-04-FIX)', async () => {
    // totalConfirmed=1 (직전에서 변경) → 2 (+1) 차단
    const db = getAuth(env, IDS.user);
    await assertFails(
      updateDoc(doc(db, 'tos', TO_ID), {
        totalConfirmed: 2,
        workTypeConfirmedCounts: { 'wt-001': 2 },
      }),
    );
  });
});

// ─── TO-DELETE: 공고 삭제 ─────────────────────────────────────────────

describe('TO-DELETE: 공고 삭제', () => {
  test('TO-DELETE-01 관리자는 소속 사업장 공고를 삭제할 수 있다', async () => {
    await seedDoc(env, 'tos', 'to-del-admin', baseTO);
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(deleteDoc(doc(db, 'tos', 'to-del-admin')));
  });

  test('TO-DELETE-02 서브어드민도 공고를 삭제할 수 있다', async () => {
    await seedDoc(env, 'tos', 'to-del-sub', baseTO);
    const db = getAuth(env, IDS.subAdmin, { subAdminOf: IDS.business });
    await assertSucceeds(deleteDoc(doc(db, 'tos', 'to-del-sub')));
  });

  test('TO-DELETE-03 슈퍼어드민은 모든 공고를 삭제할 수 있다', async () => {
    await seedDoc(env, 'tos', 'to-del-super', { ...baseTO, businessId: IDS.business2 });
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertSucceeds(deleteDoc(doc(db, 'tos', 'to-del-super')));
  });

  test('TO-DELETE-04 일반유저는 공고를 삭제할 수 없다', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(deleteDoc(doc(db, 'tos', TO_ID)));
  });

  test('TO-DELETE-05 타 사업장 관리자는 공고를 삭제할 수 없다', async () => {
    const db = getAuth(env, IDS.admin2, { businessId: IDS.business2 });
    await assertFails(deleteDoc(doc(db, 'tos', TO_ID)));
  });
});
