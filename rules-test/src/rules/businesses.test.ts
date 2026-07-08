// rules-test/src/rules/businesses.test.ts
// businesses + workTypes + contract_templates + members 서브컬렉션 (40개 시나리오)
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
  env = await createTestEnv('businesses');
  await seedCommonFixtures(env);

  // workTypes
  await seedDoc(env, `businesses/${IDS.business}/workTypes`, 'wt-001', {
    name: '홀서빙', businessId: IDS.business,
  });

  // contract_templates
  await seedDoc(env, `businesses/${IDS.business}/contract_templates`, 'tmpl-001', {
    businessId: IDS.business,
    name: '기본 계약서',
    templateType: 'standard',
    articles: [{ title: '근무 조건', content: '주 5일' }],
    createdAt: '2024-01-01T00:00:00Z',
    updatedAt: '2024-01-01T00:00:00Z',
  });

  // member_invitations (members 생성 규칙에 필요)
  await seedDoc(env, 'member_invitations', 'inv-001', {
    targetUid: IDS.subAdmin,
    businessId: IDS.business,
    status: 'pending',
    invitedBy: IDS.admin,
  });

  // members 서브컬렉션
  await seedDoc(env, `businesses/${IDS.business}/members`, IDS.subAdmin, {
    role: 'SUB_ADMIN',
    joinedAt: '2024-01-01T00:00:00Z',
  });

  // 단독 관리자 사업장 (SEC-95: 탈퇴 시 deactivatedAt 허용 테스트용)
  await seedDoc(env, 'businesses', 'biz-sole', {
    ownerId: IDS.admin,
    adminIds: [IDS.admin],  // 단독 관리자 — size()==1
    name: '단독관리자사업장',
    isApproved: true,
  });
});

afterAll(async () => {
  await env.cleanup();
});

// ─── BIZ-GET / BIZ-LIST ──────────────────────────────────────────────

describe('BIZ-GET/LIST: 사업장 읽기', () => {
  test('BIZ-GET-01 로그인 유저는 사업장을 단건 조회할 수 있다', async () => {
    const db = getAuth(env, IDS.user);
    await assertSucceeds(getDoc(doc(db, 'businesses', IDS.business)));
  });

  test('BIZ-GET-02 미인증 사용자는 단건 조회도 차단', async () => {
    const db = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, 'businesses', IDS.business)));
  });

  // LIST는 슈퍼어드민만 허용 — 에뮬레이터 filters 한계로 assertSucceeds 불가
  // 프로덕션 동작: BUSINESS_ADMIN list → PERMISSION_DENIED (callableGetMyBusiness CF로 대체)
  test('BIZ-LIST-01 슈퍼어드민 외 list 차단 검증', async () => {
    // 일반유저 list 차단
    const db = getAuth(env, IDS.user);
    const { getDocs, collection, query } = await import('firebase/firestore');
    await assertFails(getDocs(query(collection(db, 'businesses'))));
  });
});

// ─── BIZ-CREATE ──────────────────────────────────────────────────────

describe('BIZ-CREATE: 사업장 생성', () => {
  test('BIZ-CREATE-01 BUSINESS_ADMIN이 ownerId=본인, adminIds에 본인 포함으로 생성 허용', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(
      setDoc(doc(db, 'businesses', 'biz-new-admin'), {
        ownerId: IDS.admin,
        adminIds: [IDS.admin],
        name: '신규사업장',
        status: 'pending',
      }),
    );
  });

  test('BIZ-CREATE-02 ownerId가 자신이 아닌 경우 생성 차단', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      setDoc(doc(db, 'businesses', 'biz-fake-owner'), {
        ownerId: IDS.user,       // 타인을 ownerId로 설정
        adminIds: [IDS.admin],
        name: '사기사업장',
        status: 'pending',
      }),
    );
  });

  test('BIZ-CREATE-03 adminIds에 본인 uid 없으면 생성 차단', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      setDoc(doc(db, 'businesses', 'biz-no-adminids'), {
        ownerId: IDS.admin,
        adminIds: [IDS.user],   // 자신이 adminIds에 없음
        name: '사업장',
        status: 'pending',
      }),
    );
  });

  test('BIZ-CREATE-04 일반유저는 사업장 생성 차단', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      setDoc(doc(db, 'businesses', 'biz-user-create'), {
        ownerId: IDS.user,
        adminIds: [IDS.user],
        name: '사업장',
        status: 'pending',
      }),
    );
  });

  test('BIZ-CREATE-05 슈퍼어드민은 ownerId/adminIds 제약 없이 생성 허용', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertSucceeds(
      setDoc(doc(db, 'businesses', 'biz-super-create'), {
        ownerId: IDS.admin2,
        adminIds: [IDS.admin2],
        name: '슈퍼관리사업장',
        status: 'approved',
      }),
    );
  });

  test('BIZ-CREATE-06 isApproved=true로 직접 생성 차단 — 승인 절차 우회 방지 (SEC-89)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      setDoc(doc(db, 'businesses', 'biz-approved-hack'), {
        ownerId: IDS.admin,
        adminIds: [IDS.admin],
        isApproved: true,  // 서버 레벨 강제: false 또는 미포함만 허용
        name: '무승인사업장',
        status: 'pending',
      }),
    );
  });

  test('BIZ-CREATE-07 adminIds에 타인 UID 삽입 차단 — 비동의 관리자 부여 방지 (SEC-90)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      setDoc(doc(db, 'businesses', 'biz-extra-admin'), {
        ownerId: IDS.admin,
        adminIds: [IDS.admin, IDS.user],  // 창설자 UID 외 추가 UID 차단
        name: '사업장',
        status: 'pending',
      }),
    );
  });
});

// ─── BIZ-UPDATE ──────────────────────────────────────────────────────

describe('BIZ-UPDATE: 사업장 수정', () => {
  test('BIZ-UPDATE-01 관리자는 일반 필드를 수정할 수 있다', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(
      updateDoc(doc(db, 'businesses', IDS.business), {
        name: '수정된사업장명',
        address: '서울시 강남구',
      }),
    );
  });

  test('BIZ-UPDATE-02 관리자는 ownerId 변경 차단 (권한 탈취 방지)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'businesses', IDS.business), {
        ownerId: IDS.user,  // 소유권 이전 차단
      }),
    );
  });

  test('BIZ-UPDATE-03 관리자는 adminIds 변경 차단', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'businesses', IDS.business), {
        adminIds: [IDS.admin, IDS.user],  // 임의 관리자 추가 차단
      }),
    );
  });

  test('BIZ-UPDATE-04 슈퍼어드민은 ownerId/adminIds 변경 허용', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertSucceeds(
      updateDoc(doc(db, 'businesses', IDS.business), {
        adminIds: [IDS.admin, IDS.admin2],
      }),
    );
    // 원복
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('businesses').doc(IDS.business).update({
        adminIds: [IDS.admin, IDS.subAdmin],
      });
    });
  });

  test('BIZ-UPDATE-05 타 사업장 관리자는 수정 차단', async () => {
    const db = getAuth(env, IDS.admin2, { businessId: IDS.business2 });
    await assertFails(
      updateDoc(doc(db, 'businesses', IDS.business), {
        name: '해킹된사업장',
      }),
    );
  });

  test('BIZ-UPDATE-06 일반유저는 사업장 수정 차단', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      updateDoc(doc(db, 'businesses', IDS.business), {
        name: '유저수정',
      }),
    );
  });

  // [SEC-95] 단독 관리자 탈퇴 시 deactivatedAt 설정 허용
  // adminIds.size() <= 1이고 deactivatedAt 필드만 변경하는 경우만 허용
  test('BIZ-UPDATE-07 ✅ 단독 관리자가 deactivatedAt 필드만 설정 허용 (SEC-95)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: 'biz-sole' });
    await assertSucceeds(
      updateDoc(doc(db, 'businesses', 'biz-sole'), {
        deactivatedAt: '2024-01-15T18:00:00Z',
      }),
    );
  });

  test('BIZ-UPDATE-08 ❌ 이중 관리자 사업장에서 deactivatedAt 설정 차단 (SEC-95)', async () => {
    // biz-001의 adminIds == [admin, subAdmin] → size()==2 → 차단
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, 'businesses', IDS.business), {
        deactivatedAt: '2024-01-15T18:00:00Z',
      }),
    );
  });

  test('BIZ-UPDATE-09 ❌ 단독 관리자도 deactivatedAt + 다른 필드 함께 변경 차단 (SEC-95)', async () => {
    // deactivatedAt.hasOnly 조건: deactivatedAt 외 필드 포함 시 차단
    await seedDoc(env, 'businesses', 'biz-sole-b', {
      ownerId: IDS.admin, adminIds: [IDS.admin], name: '단독B', isApproved: true,
    });
    const db = getAuth(env, IDS.admin, { businessId: 'biz-sole-b' });
    await assertFails(
      updateDoc(doc(db, 'businesses', 'biz-sole-b'), {
        deactivatedAt: '2024-01-15T18:00:00Z',
        name: '비활성됨',  // deactivatedAt 외 필드 포함 → 차단
      }),
    );
  });

  // [SEC-100] 공동 관리자 탈퇴: 본인 uid만 adminIds에서 제거 허용
  test('BIZ-UPDATE-10 ✅ 공동 관리자가 본인 uid만 adminIds에서 제거 허용 (SEC-100)', async () => {
    await seedDoc(env, 'businesses', 'biz-joint', {
      ownerId: IDS.admin, adminIds: [IDS.admin, IDS.admin2], name: '공동관리', isApproved: true,
    });
    // admin이 자신의 uid를 adminIds에서 제거 (admin2만 남음)
    const db = getAuth(env, IDS.admin, { businessId: 'biz-joint' });
    await assertSucceeds(
      updateDoc(doc(db, 'businesses', 'biz-joint'), {
        adminIds: [IDS.admin2],  // 본인 uid 제거
      }),
    );
  });

  test('BIZ-UPDATE-11 ❌ 타인 uid를 adminIds에서 제거 차단 (SEC-100)', async () => {
    await seedDoc(env, 'businesses', 'biz-joint-b', {
      ownerId: IDS.admin, adminIds: [IDS.admin, IDS.admin2], name: '공동관리B', isApproved: true,
    });
    // admin이 타인(admin2)을 adminIds에서 제거 시도 — 차단
    const db = getAuth(env, IDS.admin, { businessId: 'biz-joint-b' });
    await assertFails(
      updateDoc(doc(db, 'businesses', 'biz-joint-b'), {
        adminIds: [IDS.admin],  // 타인(admin2) 제거, 자신은 유지 → 차단
      }),
    );
  });

  test('BIZ-UPDATE-12 ❌ adminIds 제거 + 다른 필드 동시 변경 차단 (SEC-100)', async () => {
    await seedDoc(env, 'businesses', 'biz-joint-c', {
      ownerId: IDS.admin, adminIds: [IDS.admin, IDS.admin2], name: '공동관리C', isApproved: true,
    });
    const db = getAuth(env, IDS.admin, { businessId: 'biz-joint-c' });
    await assertFails(
      updateDoc(doc(db, 'businesses', 'biz-joint-c'), {
        adminIds: [IDS.admin2],
        name: '변경시도',  // adminIds 외 필드 포함 → 차단
      }),
    );
  });
});

// ─── BIZ-DELETE ──────────────────────────────────────────────────────

describe('BIZ-DELETE: 사업장 삭제', () => {
  test('BIZ-DELETE-01 소속 관리자는 사업장 삭제 허용', async () => {
    await seedDoc(env, 'businesses', 'biz-del', { ownerId: IDS.admin, adminIds: [IDS.admin], name: '삭제용' });
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(deleteDoc(doc(db, 'businesses', 'biz-del')));
  });

  test('BIZ-DELETE-02 일반유저는 사업장 삭제 차단', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(deleteDoc(doc(db, 'businesses', IDS.business)));
  });
});

// ─── WORK_TYPES 서브컬렉션 ───────────────────────────────────────────

describe('WORK_TYPES: 근무 유형 서브컬렉션', () => {
  test('WT-READ-01 로그인 유저는 workTypes를 읽을 수 있다', async () => {
    const db = getAuth(env, IDS.user);
    await assertSucceeds(getDoc(doc(db, `businesses/${IDS.business}/workTypes`, 'wt-001')));
  });

  test('WT-WRITE-01 관리자는 workTypes를 쓸 수 있다', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(
      setDoc(doc(db, `businesses/${IDS.business}/workTypes`, 'wt-new'), {
        name: '주방보조',
        businessId: IDS.business,
      }),
    );
  });

  test('WT-WRITE-02 서브어드민도 workTypes를 쓸 수 있다', async () => {
    const db = getAuth(env, IDS.subAdmin, { subAdminOf: IDS.business });
    await assertSucceeds(
      setDoc(doc(db, `businesses/${IDS.business}/workTypes`, 'wt-sub'), {
        name: '청소',
        businessId: IDS.business,
      }),
    );
  });

  test('WT-WRITE-03 일반유저는 workTypes를 쓸 수 없다', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      setDoc(doc(db, `businesses/${IDS.business}/workTypes`, 'wt-user'), {
        name: '불법추가',
      }),
    );
  });
});

// ─── CONTRACT_TEMPLATES 서브컬렉션 ───────────────────────────────────

describe('CONTRACT_TEMPLATES: 계약서 템플릿', () => {
  // [SEC-106] 이전 규칙: isLoggedIn() → 타 사업장 관리자도 임금 구조·계약 내용 열람 가능
  // 변경: 소속 관리자/서브어드민/슈퍼어드민으로 제한 — 근무자는 employment_contracts를 통해 열람
  test('CT-READ-01 ✅ 소속 관리자는 템플릿을 읽을 수 있다 (SEC-106)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(getDoc(doc(db, `businesses/${IDS.business}/contract_templates`, 'tmpl-001')));
  });

  test('CT-READ-02 ❌ 일반 유저는 템플릿 읽기 차단 (SEC-106)', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(getDoc(doc(db, `businesses/${IDS.business}/contract_templates`, 'tmpl-001')));
  });

  test('CT-READ-03 ❌ 타 사업장 관리자는 템플릿 읽기 차단 (SEC-106)', async () => {
    const db = getAuth(env, IDS.admin2, { businessId: IDS.business2 });
    await assertFails(getDoc(doc(db, `businesses/${IDS.business}/contract_templates`, 'tmpl-001')));
  });

  test('CT-CREATE-01 관리자는 템플릿을 생성할 수 있다', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(
      setDoc(doc(db, `businesses/${IDS.business}/contract_templates`, 'tmpl-new'), {
        businessId: IDS.business,
        name: '신규템플릿',
        templateType: 'custom',
        articles: [],
        createdAt: '2024-01-01T00:00:00Z',
        updatedAt: '2024-01-01T00:00:00Z',
      }),
    );
  });

  test('CT-UPDATE-01 관리자가 허용 필드(name·articles·updatedAt)만 수정 허용 (SEC-78)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(
      updateDoc(doc(db, `businesses/${IDS.business}/contract_templates`, 'tmpl-001'), {
        name: '수정된템플릿',
        articles: [{ title: '수정', content: '내용' }],
        updatedAt: '2024-01-02T00:00:00Z',
      }),
    );
  });

  test('CT-UPDATE-02 관리자가 businessId 변경 차단 (SEC-78 불변 필드)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, `businesses/${IDS.business}/contract_templates`, 'tmpl-001'), {
        businessId: IDS.business2,  // 불변 필드
      }),
    );
  });

  test('CT-UPDATE-03 관리자가 createdAt 변경 차단', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      updateDoc(doc(db, `businesses/${IDS.business}/contract_templates`, 'tmpl-001'), {
        createdAt: '2099-01-01T00:00:00Z',  // 불변 필드
      }),
    );
  });

  test('CT-DELETE-01 관리자는 템플릿을 삭제할 수 있다', async () => {
    await seedDoc(env, `businesses/${IDS.business}/contract_templates`, 'tmpl-del', {
      businessId: IDS.business, name: '삭제용', articles: [], createdAt: '2024-01-01T00:00:00Z',
    });
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(deleteDoc(doc(db, `businesses/${IDS.business}/contract_templates`, 'tmpl-del')));
  });

  test('CT-DELETE-02 일반유저는 템플릿을 삭제할 수 없다', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(deleteDoc(doc(db, `businesses/${IDS.business}/contract_templates`, 'tmpl-001')));
  });
});

// ─── MEMBERS 서브컬렉션 ──────────────────────────────────────────────

describe('MEMBERS: 멤버 서브컬렉션', () => {
  test('MEM-GET-01 관리자는 멤버를 단건 조회할 수 있다', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(getDoc(doc(db, `businesses/${IDS.business}/members`, IDS.subAdmin)));
  });

  test('MEM-GET-02 멤버 본인은 자신의 문서를 조회할 수 있다', async () => {
    const db = getAuth(env, IDS.subAdmin, { subAdminOf: IDS.business });
    await assertSucceeds(getDoc(doc(db, `businesses/${IDS.business}/members`, IDS.subAdmin)));
  });

  test('MEM-GET-03 관계없는 일반유저는 멤버 조회 차단', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(getDoc(doc(db, `businesses/${IDS.business}/members`, IDS.subAdmin)));
  });

  test('MEM-CREATE-01 관리자는 멤버를 직접 추가할 수 있다', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertSucceeds(
      setDoc(doc(db, `businesses/${IDS.business}/members`, IDS.user2), {
        role: 'USER',
        joinedAt: '2024-01-01T00:00:00Z',
      }),
    );
  });

  test('MEM-CREATE-02 유효한 초대장으로 본인 멤버 등록 허용 (MEDIUM-FIX)', async () => {
    const db = getAuth(env, IDS.subAdmin, { subAdminOf: IDS.business });
    await assertSucceeds(
      setDoc(doc(db, `businesses/${IDS.business}/members`, IDS.subAdmin), {
        role: 'SUB_ADMIN',
        joinedAt: '2024-01-01T00:00:00Z',
        invitationId: 'inv-001',  // 유효한 초대 (targetUid=subAdmin, businessId=biz-001)
      }),
    );
  });

  test('MEM-CREATE-03 초대 없이 타 사업장에 자기 등록 차단 (MEDIUM-FIX 핵심)', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      setDoc(doc(db, `businesses/${IDS.business}/members`, IDS.user), {
        role: 'USER',
        joinedAt: '2024-01-01T00:00:00Z',
        // invitationId 없음 — 직접 등록 시도
      }),
    );
  });

  test('MEM-DELETE-01 멤버 본인이 자진 탈퇴 허용', async () => {
    await seedDoc(env, `businesses/${IDS.business}/members`, 'uid-resign', { role: 'USER' });
    const db = getAuth(env, 'uid-resign');
    await assertSucceeds(deleteDoc(doc(db, `businesses/${IDS.business}/members`, 'uid-resign')));
  });

  test('MEM-DELETE-02 타 사업장 일반유저는 멤버 삭제 차단', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(deleteDoc(doc(db, `businesses/${IDS.business}/members`, IDS.subAdmin)));
  });
});
