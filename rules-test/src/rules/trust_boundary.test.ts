// rules-test/src/rules/trust_boundary.test.ts
//
// [R8-P3B.3A] Trust boundary — BLOCKER-1 / BLOCKER-2 회귀 고정.
//
//   BLOCKER-1  users.subAdminBusinessIds/subAdminOf 클라이언트 update 브랜치
//              → BUSINESS_ADMIN이 타 사업장 SubAdmin 권한을 스스로 부여할 수 있었다.
//   BLOCKER-2  SubAdmin이 권한 종류와 무관하게
//              · 확정 근무를 PENDING으로 되돌리고
//              · TO/slot/workDetails를 수정·삭제할 수 있었다.
//
//   이 파일의 fixture는 기존 seedCommonFixtures를 쓰지 않는다.
//   공통 fixture는 subAdmin을 businesses.adminIds에도 넣어 두어서
//   isAdminOf가 true가 되고, 그러면 capability 검증이 가려진다.
//   여기서는 SubAdmin을 adminIds에서 제외한 독립 fixture를 쓴다.
import { RulesTestEnvironment } from '@firebase/rules-unit-testing';
import {
  createTestEnv,
  getAuth,
  seedUser,
  seedBusiness,
  seedDoc,
  assertFails,
  assertSucceeds,
} from '../helpers/test-env';

const BIZ = 'tb-biz';
const BIZ_B = 'tb-biz-b';
const TO = 'tb-to';
const SLOT = 'tb-slot';
const WD = 'tb-wd';

const ADMIN = 'tb-admin';          // BIZ 소유 BUSINESS_ADMIN
const ADMIN_B = 'tb-admin-b';      // BIZ_B 소유 BUSINESS_ADMIN (타 사업장)
const SUB_WORKERS = 'tb-sub-workers';
const SUB_TO = 'tb-sub-to';
const SUB_WAGE = 'tb-sub-wage';
const SUB_CONTRACT = 'tb-sub-contract';
const SUB_NONE = 'tb-sub-none';    // 멤버 문서에 permissions 없음
const SUB_BOTH = 'tb-sub-both';    // canManageTo + canManageWorkers
const WORKER = 'tb-worker';

const APP_CONFIRMED = 'tb-app-confirmed';
const APP_CONTRACT_PENDING = 'tb-app-cp';

let env: RulesTestEnvironment;

async function seedMember(
  businessId: string,
  uid: string,
  permissions: Record<string, boolean>,
) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore()
      .collection('businesses').doc(businessId)
      .collection('members').doc(uid)
      .set({ uid, permissions, addedAt: new Date() });
  });
}

async function seedSubDoc(
  path: string[],
  data: Record<string, unknown>,
) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    let ref: any = ctx.firestore();
    for (let i = 0; i < path.length; i += 2) {
      ref = ref.collection(path[i]).doc(path[i + 1]);
    }
    await ref.set(data);
  });
}

beforeAll(async () => {
  env = await createTestEnv('trust_boundary');
});

afterAll(async () => {
  await env.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();

  await Promise.all([
    seedUser(env, ADMIN, { role: 'BUSINESS_ADMIN', name: '관리자', isBlacklisted: false, managedBusinessIds: [BIZ] }),
    seedUser(env, ADMIN_B, { role: 'BUSINESS_ADMIN', name: '타사관리자', isBlacklisted: false, managedBusinessIds: [BIZ_B] }),
    seedUser(env, SUB_WORKERS, { role: 'USER', name: '서브인력', isBlacklisted: false, subAdminBusinessIds: [BIZ] }),
    seedUser(env, SUB_TO, { role: 'USER', name: '서브공고', isBlacklisted: false, subAdminBusinessIds: [BIZ] }),
    seedUser(env, SUB_WAGE, { role: 'USER', name: '서브급여', isBlacklisted: false, subAdminBusinessIds: [BIZ] }),
    seedUser(env, SUB_CONTRACT, { role: 'USER', name: '서브계약', isBlacklisted: false, subAdminBusinessIds: [BIZ] }),
    seedUser(env, SUB_NONE, { role: 'USER', name: '서브무권한', isBlacklisted: false, subAdminBusinessIds: [BIZ] }),
    seedUser(env, SUB_BOTH, { role: 'USER', name: '서브둘다', isBlacklisted: false, subAdminBusinessIds: [BIZ] }),
    seedUser(env, WORKER, { role: 'USER', name: '근무자', isBlacklisted: false }),
    // SubAdmin은 adminIds에 넣지 않는다 — isAdminOf로 가려지면 capability 검증이 무의미해진다.
    seedBusiness(env, BIZ, { ownerId: ADMIN, adminIds: [ADMIN], name: '테스트사업장', isApproved: true }),
    seedBusiness(env, BIZ_B, { ownerId: ADMIN_B, adminIds: [ADMIN_B], name: '타사업장', isApproved: true }),
  ]);

  await Promise.all([
    seedMember(BIZ, SUB_WORKERS, { canManageWorkers: true }),
    seedMember(BIZ, SUB_TO, { canManageTo: true }),
    seedMember(BIZ, SUB_WAGE, { canManageWage: true }),
    seedMember(BIZ, SUB_CONTRACT, { canManageContract: true }),
    seedMember(BIZ, SUB_NONE, {}),
    seedMember(BIZ, SUB_BOTH, { canManageTo: true, canManageWorkers: true }),
    seedDoc(env, 'tos', TO, {
      businessId: BIZ, title: '테스트공고', status: 'ACTIVE', isPublished: true,
      totalRequired: 3, totalSlots: 1, totalPending: 0, totalConfirmed: 0,
    }),
    seedDoc(env, 'applications', APP_CONFIRMED, {
      uid: WORKER, businessId: BIZ, toId: TO, slotId: SLOT,
      status: 'CONFIRMED', statusHistory: [],
    }),
    seedDoc(env, 'applications', APP_CONTRACT_PENDING, {
      uid: WORKER, businessId: BIZ, toId: TO, slotId: SLOT,
      status: 'CONTRACT_PENDING', statusHistory: [],
    }),
  ]);

  await Promise.all([
    seedSubDoc(['tos', TO, 'slots', SLOT], {
      startTime: '09:00', endTime: '18:00',
      confirmedCount: 0, pendingCount: 0, status: 'open',
    }),
    seedSubDoc(['tos', TO, 'workDetails', WD], {
      businessId: BIZ, toId: TO, workType: '홀서빙', wage: 12000,
    }),
  ]);
});

// ═══════════════════════════════════════════════════════════════
// TB-1 / TB-2  BLOCKER-1 — subAdmin 권한 자가 부여 차단
// ═══════════════════════════════════════════════════════════════
describe('TB-1 subAdmin self-grant denied', () => {
  test('BUSINESS_ADMIN이 자기 문서에 타 사업장 subAdminOf를 넣을 수 없다', async () => {
    const db = getAuth(env, ADMIN);
    await assertFails(
      db.collection('users').doc(ADMIN).update({ subAdminOf: BIZ_B }),
    );
  });

  test('BUSINESS_ADMIN이 자기 문서의 subAdminBusinessIds를 직접 수정할 수 없다', async () => {
    const db = getAuth(env, ADMIN);
    await assertFails(
      db.collection('users').doc(ADMIN).update({ subAdminBusinessIds: [BIZ_B] }),
    );
  });

  test('자기 사업장 ID라도 subAdminOf 자가 부여는 차단된다', async () => {
    const db = getAuth(env, ADMIN);
    await assertFails(
      db.collection('users').doc(ADMIN).update({ subAdminOf: BIZ }),
    );
  });
});

describe('TB-2 arbitrary user subAdmin mutation denied', () => {
  test('BUSINESS_ADMIN이 타인의 subAdminOf를 변경할 수 없다', async () => {
    const db = getAuth(env, ADMIN);
    await assertFails(
      db.collection('users').doc(WORKER).update({ subAdminOf: BIZ }),
    );
  });

  test('BUSINESS_ADMIN이 타인의 subAdminBusinessIds를 비울 수 없다', async () => {
    const db = getAuth(env, ADMIN);
    await assertFails(
      db.collection('users').doc(SUB_TO).update({ subAdminBusinessIds: [] }),
    );
  });

  test('타 사업장 BUSINESS_ADMIN도 남의 SubAdmin을 해제할 수 없다', async () => {
    const db = getAuth(env, ADMIN_B);
    await assertFails(
      db.collection('users').doc(SUB_TO).update({ subAdminBusinessIds: [] }),
    );
  });

  test('SubAdmin 본인도 자기 subAdminBusinessIds를 직접 수정할 수 없다', async () => {
    const db = getAuth(env, SUB_TO);
    await assertFails(
      db.collection('users').doc(SUB_TO).update({ subAdminBusinessIds: [BIZ, BIZ_B] }),
    );
  });
});

describe('TB-3 canonical leave/remove still valid', () => {
  // callableRemoveMember / callableLeaveAsSubAdmin 은 CF Admin SDK writer다.
  // Admin SDK는 Rules를 평가하지 않는다 — 이 테스트는 그 경로가
  // Rules 변경과 무관하게 동일하게 동작함을 확인한다.
  test('Admin SDK(=CF) 경로는 subAdminBusinessIds를 그대로 제거할 수 있다', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('users').doc(SUB_TO)
        .update({ subAdminBusinessIds: [] });
    });
    await env.withSecurityRulesDisabled(async (ctx) => {
      const snap = await ctx.firestore().collection('users').doc(SUB_TO).get();
      expect(snap.data()?.subAdminBusinessIds).toEqual([]);
    });
  });

  test('Admin SDK(=CF) 경로는 subAdminBusinessIds를 부여할 수 있다', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('users').doc(WORKER)
        .update({ subAdminBusinessIds: [BIZ] });
    });
    await env.withSecurityRulesDisabled(async (ctx) => {
      const snap = await ctx.firestore().collection('users').doc(WORKER).get();
      expect(snap.data()?.subAdminBusinessIds).toEqual([BIZ]);
    });
  });
});

// ═══════════════════════════════════════════════════════════════
// TB-4 / TB-5  BLOCKER-2 — 확정 되돌리기 capability
// ═══════════════════════════════════════════════════════════════
const rollback = () => ({
  status: 'PENDING',
  statusHistory: [{ status: 'PENDING', at: new Date(), by: 'x', action: 'CONFIRM_ROLLBACK' }],
});

describe('TB-4 rollback capability denied without canManageWorkers', () => {
  test('canManageWage만 있는 SubAdmin: CONFIRMED → PENDING 차단', async () => {
    const db = getAuth(env, SUB_WAGE);
    await assertFails(
      db.collection('applications').doc(APP_CONFIRMED).update(rollback()),
    );
  });

  test('canManageTo만 있는 SubAdmin: CONFIRMED → PENDING 차단', async () => {
    const db = getAuth(env, SUB_TO);
    await assertFails(
      db.collection('applications').doc(APP_CONFIRMED).update(rollback()),
    );
  });

  test('canManageContract만 있는 SubAdmin: CONTRACT_PENDING → PENDING 차단', async () => {
    const db = getAuth(env, SUB_CONTRACT);
    await assertFails(
      db.collection('applications').doc(APP_CONTRACT_PENDING).update(rollback()),
    );
  });

  test('권한 없는 SubAdmin: CONTRACT_PENDING → PENDING 차단', async () => {
    const db = getAuth(env, SUB_NONE);
    await assertFails(
      db.collection('applications').doc(APP_CONTRACT_PENDING).update(rollback()),
    );
  });
});

describe('TB-5 rollback allowed with canManageWorkers', () => {
  test('canManageWorkers SubAdmin: CONFIRMED → PENDING 허용', async () => {
    const db = getAuth(env, SUB_WORKERS);
    await assertSucceeds(
      db.collection('applications').doc(APP_CONFIRMED).update(rollback()),
    );
  });

  test('canManageWorkers SubAdmin: CONTRACT_PENDING → PENDING 허용', async () => {
    const db = getAuth(env, SUB_WORKERS);
    await assertSucceeds(
      db.collection('applications').doc(APP_CONTRACT_PENDING).update(rollback()),
    );
  });

  test('statusHistory 동반 write가 막히지 않는다 (client writer 실제 필드 구성)', async () => {
    const db = getAuth(env, SUB_WORKERS);
    await assertSucceeds(
      db.collection('applications').doc(APP_CONFIRMED).update({
        status: 'PENDING',
        statusHistory: [
          { status: 'PENDING', at: new Date(), by: SUB_WORKERS, action: 'CONFIRM_ROLLBACK' },
        ],
      }),
    );
  });

  test('capability가 있어도 CF 전용 전이(CONFIRMED → CANCELED)는 여전히 차단', async () => {
    const db = getAuth(env, SUB_WORKERS);
    await assertFails(
      db.collection('applications').doc(APP_CONFIRMED).update({ status: 'CANCELED' }),
    );
  });
});

// ═══════════════════════════════════════════════════════════════
// TB-6 ~ TB-9  BLOCKER-2 — TO / slot / workDetails capability
// ═══════════════════════════════════════════════════════════════
describe('TB-6 TO denied without canManageTo', () => {
  test('canManageWorkers만 있는 SubAdmin: TO update 차단', async () => {
    const db = getAuth(env, SUB_WORKERS);
    await assertFails(
      db.collection('tos').doc(TO).update({ totalRequired: 5 }),
    );
  });

  test('canManageWorkers만 있는 SubAdmin: TO delete 차단', async () => {
    const db = getAuth(env, SUB_WORKERS);
    await assertFails(db.collection('tos').doc(TO).delete());
  });

  test('canManageWage만 있는 SubAdmin: TO delete 차단', async () => {
    const db = getAuth(env, SUB_WAGE);
    await assertFails(db.collection('tos').doc(TO).delete());
  });

  test('canManageWorkers만 있는 SubAdmin: workDetails update 차단', async () => {
    const db = getAuth(env, SUB_WORKERS);
    await assertFails(
      db.collection('tos').doc(TO).collection('workDetails').doc(WD)
        .update({ wage: 20000 }),
    );
  });
});

describe('TB-7 TO allowed with canManageTo', () => {
  test('canManageTo SubAdmin: TO update 허용', async () => {
    const db = getAuth(env, SUB_TO);
    await assertSucceeds(
      db.collection('tos').doc(TO).update({ totalRequired: 5 }),
    );
  });

  test('canManageTo SubAdmin: TO delete 허용', async () => {
    const db = getAuth(env, SUB_TO);
    await assertSucceeds(db.collection('tos').doc(TO).delete());
  });

  test('canManageTo SubAdmin: workDetails update 허용', async () => {
    const db = getAuth(env, SUB_TO);
    await assertSucceeds(
      db.collection('tos').doc(TO).collection('workDetails').doc(WD)
        .update({ wage: 20000 }),
    );
  });

  test('canManageTo SubAdmin도 TO 읽기는 권한과 무관하게 가능하다', async () => {
    const db = getAuth(env, SUB_WAGE);
    await assertSucceeds(db.collection('tos').doc(TO).get());
  });
});

describe('TB-8 slot denied without canManageTo', () => {
  test('canManageWage만 있는 SubAdmin: slot create 차단', async () => {
    const db = getAuth(env, SUB_WAGE);
    await assertFails(
      db.collection('tos').doc(TO).collection('slots').doc('tb-slot-new').set({
        startTime: '09:00', endTime: '18:00',
        confirmedCount: 0, pendingCount: 0, status: 'open',
      }),
    );
  });

  test('canManageWage만 있는 SubAdmin: slot update 차단', async () => {
    const db = getAuth(env, SUB_WAGE);
    await assertFails(
      db.collection('tos').doc(TO).collection('slots').doc(SLOT)
        .update({ startTime: '10:00' }),
    );
  });

  test('canManageWorkers만 있는 SubAdmin: slot delete 차단', async () => {
    const db = getAuth(env, SUB_WORKERS);
    await assertFails(
      db.collection('tos').doc(TO).collection('slots').doc(SLOT).delete(),
    );
  });

  test('권한 없는 SubAdmin: slot update 차단', async () => {
    const db = getAuth(env, SUB_NONE);
    await assertFails(
      db.collection('tos').doc(TO).collection('slots').doc(SLOT)
        .update({ startTime: '10:00' }),
    );
  });
});

describe('TB-9 slot allowed with canManageTo', () => {
  test('canManageTo SubAdmin: slot create 허용', async () => {
    const db = getAuth(env, SUB_TO);
    await assertSucceeds(
      db.collection('tos').doc(TO).collection('slots').doc('tb-slot-new').set({
        startTime: '09:00', endTime: '18:00',
        confirmedCount: 0, pendingCount: 0, status: 'open',
      }),
    );
  });

  test('canManageTo SubAdmin: slot update 허용', async () => {
    const db = getAuth(env, SUB_TO);
    await assertSucceeds(
      db.collection('tos').doc(TO).collection('slots').doc(SLOT)
        .update({ startTime: '10:00' }),
    );
  });

  test('canManageTo SubAdmin: slot delete 허용', async () => {
    const db = getAuth(env, SUB_TO);
    await assertSucceeds(
      db.collection('tos').doc(TO).collection('slots').doc(SLOT).delete(),
    );
  });

  test('canManageTo가 있어도 slot 카운터 ±1 제한은 유지된다', async () => {
    const db = getAuth(env, SUB_TO);
    await assertFails(
      db.collection('tos').doc(TO).collection('slots').doc(SLOT)
        .update({ confirmedCount: 99 }),
    );
  });
});

// ═══════════════════════════════════════════════════════════════
// TB-9b  권한 조합 — 두 capability를 모두 가진 SubAdmin (§26)
// ═══════════════════════════════════════════════════════════════
describe('TB-9b canManageTo + canManageWorkers 조합', () => {
  test('TO update 허용', async () => {
    const db = getAuth(env, SUB_BOTH);
    await assertSucceeds(db.collection('tos').doc(TO).update({ totalRequired: 4 }));
  });

  test('slot update 허용', async () => {
    const db = getAuth(env, SUB_BOTH);
    await assertSucceeds(
      db.collection('tos').doc(TO).collection('slots').doc(SLOT)
        .update({ startTime: '10:00' }),
    );
  });

  test('확정 되돌리기 허용', async () => {
    const db = getAuth(env, SUB_BOTH);
    await assertSucceeds(
      db.collection('applications').doc(APP_CONFIRMED).update(rollback()),
    );
  });

  test('두 권한을 가져도 CF 전용 전이는 여전히 차단', async () => {
    const db = getAuth(env, SUB_BOTH);
    await assertFails(
      db.collection('applications').doc(APP_CONFIRMED).update({ status: 'CANCELED' }),
    );
  });
});

// ═══════════════════════════════════════════════════════════════
// TB-10  BUSINESS_ADMIN 회귀 없음
// ═══════════════════════════════════════════════════════════════
describe('TB-10 BUSINESS_ADMIN unchanged', () => {
  test('TO update', async () => {
    const db = getAuth(env, ADMIN);
    await assertSucceeds(db.collection('tos').doc(TO).update({ totalRequired: 7 }));
  });

  test('TO delete', async () => {
    const db = getAuth(env, ADMIN);
    await assertSucceeds(db.collection('tos').doc(TO).delete());
  });

  test('slot create/update/delete', async () => {
    const db = getAuth(env, ADMIN);
    const slots = db.collection('tos').doc(TO).collection('slots');
    await assertSucceeds(slots.doc('tb-slot-admin').set({
      startTime: '09:00', endTime: '18:00',
      confirmedCount: 0, pendingCount: 0, status: 'open',
    }));
    await assertSucceeds(slots.doc(SLOT).update({ startTime: '11:00' }));
    await assertSucceeds(slots.doc(SLOT).delete());
  });

  test('workDetails update', async () => {
    const db = getAuth(env, ADMIN);
    await assertSucceeds(
      db.collection('tos').doc(TO).collection('workDetails').doc(WD)
        .update({ wage: 15000 }),
    );
  });

  test('확정 되돌리기 (CONFIRMED → PENDING)', async () => {
    const db = getAuth(env, ADMIN);
    await assertSucceeds(
      db.collection('applications').doc(APP_CONFIRMED).update(rollback()),
    );
  });

  test('members permissions 수정은 그대로 가능하다', async () => {
    const db = getAuth(env, ADMIN);
    await assertSucceeds(
      db.collection('businesses').doc(BIZ).collection('members').doc(SUB_TO)
        .update({ permissions: { canManageTo: true, canManageWorkers: true } }),
    );
  });
});

// ═══════════════════════════════════════════════════════════════
// TB-11  cross-business (BLOCKER-1 + BLOCKER-2 결합)
// ═══════════════════════════════════════════════════════════════
describe('TB-11 cross-business escalation denied', () => {
  test('타 사업장 BUSINESS_ADMIN: subAdminOf 위조 차단 (공격 진입점)', async () => {
    const db = getAuth(env, ADMIN_B);
    await assertFails(
      db.collection('users').doc(ADMIN_B).update({ subAdminOf: BIZ }),
    );
  });

  test('타 사업장 BUSINESS_ADMIN: TO update 차단', async () => {
    const db = getAuth(env, ADMIN_B);
    await assertFails(db.collection('tos').doc(TO).update({ totalRequired: 9 }));
  });

  test('타 사업장 BUSINESS_ADMIN: TO delete 차단', async () => {
    const db = getAuth(env, ADMIN_B);
    await assertFails(db.collection('tos').doc(TO).delete());
  });

  test('타 사업장 BUSINESS_ADMIN: slot update 차단', async () => {
    const db = getAuth(env, ADMIN_B);
    await assertFails(
      db.collection('tos').doc(TO).collection('slots').doc(SLOT)
        .update({ startTime: '10:00' }),
    );
  });

  test('타 사업장 BUSINESS_ADMIN: 확정 되돌리기 차단', async () => {
    const db = getAuth(env, ADMIN_B);
    await assertFails(
      db.collection('applications').doc(APP_CONFIRMED).update(rollback()),
    );
  });

  test('타 사업장 BUSINESS_ADMIN: 남의 사업장 member permissions 수정 차단', async () => {
    const db = getAuth(env, ADMIN_B);
    await assertFails(
      db.collection('businesses').doc(BIZ).collection('members').doc(SUB_TO)
        .update({ permissions: { canManageTo: true } }),
    );
  });
});

// ═══════════════════════════════════════════════════════════════
// TB-12  잔여 위험(legacy subAdminOf 읽기) 방어 깊이
//
//   [OPEN-R8P3B3-LEGACY-SUBADMINOF] isSubAdminOf()는 아직 레거시
//   subAdminOf(String)를 인정한다. 이번 Phase는 "클라이언트가 그 필드를
//   쓰는 경로"만 닫았고 읽기는 그대로 둔다(마이그레이션 완료 미확인).
//
//   그래서 확인한다 — 만약 그 필드가 어떤 경로로든 이미 설정돼 있다면
//   (레거시 데이터, 과거 침해) capability gate가 2차 방어로 서는가.
//   members 문서가 없으면 subAdminCanManage*가 전부 false이므로 막혀야 한다.
// ═══════════════════════════════════════════════════════════════
describe('TB-12 legacy subAdminOf residual — capability gate가 2차 방어', () => {
  beforeEach(async () => {
    // Admin SDK로 레거시/침해 상태를 재현 (클라이언트 경로로는 더 이상 불가능)
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('users').doc(ADMIN_B)
        .update({ subAdminOf: BIZ });
    });
  });

  test('subAdminOf가 이미 설정돼 있어도 members 문서가 없으면 TO update 차단', async () => {
    const db = getAuth(env, ADMIN_B);
    await assertFails(db.collection('tos').doc(TO).update({ totalRequired: 9 }));
  });

  test('subAdminOf가 이미 설정돼 있어도 slot update 차단', async () => {
    const db = getAuth(env, ADMIN_B);
    await assertFails(
      db.collection('tos').doc(TO).collection('slots').doc(SLOT)
        .update({ startTime: '10:00' }),
    );
  });

  test('subAdminOf가 이미 설정돼 있어도 확정 되돌리기 차단', async () => {
    const db = getAuth(env, ADMIN_B);
    await assertFails(
      db.collection('applications').doc(APP_CONFIRMED).update(rollback()),
    );
  });
});
