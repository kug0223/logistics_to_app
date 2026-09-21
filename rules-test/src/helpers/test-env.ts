// rules-test/src/helpers/test-env.ts
// 역할별 Firestore 클라이언트 팩토리 + 공통 테스트 데이터
import {
  RulesTestEnvironment,
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import * as fs from 'fs';
import * as path from 'path';

export { assertFails, assertSucceeds };

// ── 에뮬레이터 연결 정보 ────────────────────────────────────────
const PROJECT_ID = 'alfit-89567';
const FIRESTORE_HOST = '127.0.0.1';
const FIRESTORE_PORT = 6060;
const RULES_PATH = path.resolve(__dirname, '../../../firestore.rules');

// ── 테스트 환경 팩토리 ──────────────────────────────────────────
export async function createTestEnv(suiteName: string): Promise<RulesTestEnvironment> {
  return initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      host: FIRESTORE_HOST,
      port: FIRESTORE_PORT,
      rules: fs.readFileSync(RULES_PATH, 'utf8'),
    },
  });
}

// ── 역할별 인증 컨텍스트 ─────────────────────────────────────────
// users/{uid} 문서를 시드한 뒤 해당 uid로 인증된 Firestore 클라이언트 반환
export function getAnonymous(env: RulesTestEnvironment) {
  return env.unauthenticatedContext().firestore();
}

export function getAuth(env: RulesTestEnvironment, uid: string, extra?: Record<string, unknown>) {
  return env.authenticatedContext(uid, extra).firestore();
}

// ── 테스트용 시드 데이터 (Admin SDK 역할 — 규칙 우회해서 사전 데이터 삽입) ──
export async function seedUser(
  env: RulesTestEnvironment,
  uid: string,
  data: Record<string, unknown>,
) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('users').doc(uid).set(data);
  });
}

export async function seedBusiness(
  env: RulesTestEnvironment,
  businessId: string,
  data: Record<string, unknown>,
) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('businesses').doc(businessId).set(data);
  });
}

export async function seedDoc(
  env: RulesTestEnvironment,
  collection: string,
  docId: string,
  data: Record<string, unknown>,
) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection(collection).doc(docId).set(data);
  });
}

// [R8-P3B.3A.1] SubAdmin 세부 권한 문서(businesses/{bizId}/members/{uid}).
//
//   Rules의 subAdminCanManageTo/Workers/Wage/Contract 는 전부 이 문서를 읽는다.
//   이 문서가 없으면 SubAdmin은 "소속은 있으나 권한은 없는" 상태다.
export async function seedSubAdminMember(
  env: RulesTestEnvironment,
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

// ── 공통 uid/id 상수 ─────────────────────────────────────────────
export const IDS = {
  superAdmin: 'uid-super',
  admin: 'uid-admin',
  admin2: 'uid-admin2',      // 다른 사업장 관리자
  subAdmin: 'uid-subadmin',
  user: 'uid-user',
  user2: 'uid-user2',        // 다른 일반 유저
  stranger: 'uid-stranger',  // 아무 역할 없음
  business: 'biz-001',
  business2: 'biz-002',      // 다른 사업장
  to: 'to-001',
  app: 'app-001',
  contract: 'contract-001',
};

// ── 공통 시드 픽스처 ─────────────────────────────────────────────
export async function seedCommonFixtures(env: RulesTestEnvironment) {
  const { superAdmin, admin, admin2, subAdmin, user, user2, business, business2 } = IDS;

  await Promise.all([
    // 슈퍼어드민
    seedUser(env, superAdmin, { role: 'SUPER_ADMIN', username: 'super', name: '슈퍼', email: 'super@test.com', isBlacklisted: false }),
    // 사업장 관리자 (biz-001 소유)
    seedUser(env, admin, { role: 'BUSINESS_ADMIN', username: 'admin', name: '관리자', email: 'admin@test.com', isBlacklisted: false }),
    // 다른 사업장 관리자 (biz-002 소유)
    seedUser(env, admin2, { role: 'BUSINESS_ADMIN', username: 'admin2', name: '관리자2', email: 'admin2@test.com', isBlacklisted: false }),
    // 서브어드민 (biz-001 소속)
    seedUser(env, subAdmin, { role: 'USER', subAdminOf: business, username: 'sub', name: '서브', email: 'sub@test.com', isBlacklisted: false }),
    // 일반 유저
    seedUser(env, user, { role: 'USER', username: 'user1', name: '유저1', email: 'user@test.com', isBlacklisted: false }),
    // 다른 일반 유저
    seedUser(env, user2, { role: 'USER', username: 'user2', name: '유저2', email: 'user2@test.com', isBlacklisted: false }),
    // 사업장 biz-001 (admin 소유)
    // [R8-P3B.3A.1] adminIds에서 subAdmin 제거.
    //   이전에는 subAdmin이 adminIds에도 들어 있어 isAdminOf(biz-001) == true 였다.
    //   그러면 SubAdmin 테스트가 사실은 BUSINESS_ADMIN을 검증하게 되어
    //   capability(canManageTo/Workers/…) 검증이 전부 가려진다.
    seedBusiness(env, business, { ownerId: admin, adminIds: [admin], name: '테스트사업장', status: 'approved' }),
    // 사업장 biz-002 (admin2 소유)
    seedBusiness(env, business2, { ownerId: admin2, adminIds: [admin2], name: '다른사업장', status: 'approved' }),
  ]);

  // [R8-P3B.3A.1] 공통 subAdmin은 "권한을 모두 가진 정상 서브관리자"로 둔다.
  //   개별 capability 경계(권한별 허용/차단)는 trust_boundary.test.ts가 전담한다.
  //   여기서는 "SubAdmin이라서 되는 일"과 "BUSINESS_ADMIN이라서 되는 일"을 섞지 않는 것이 목적이다.
  await seedSubAdminMember(env, business, subAdmin, {
    canManageTo: true,
    canManageWorkers: true,
    canManageWage: true,
    canManageContract: true,
  });
}

// ─────────────────────────────────────────────────────────────
// [R8-P5.3] Storage Rules 테스트 환경 (§34 §35)
//
//   storage.rules 에는 회귀 스위트가 없었다. 그 사이 2026-07-17 의
//   보안 수정이 두 달 넘게 배포되지 않았고, 아무도 알아차리지 못했다.
//   R8-P5.2 의 런타임 probe 를 여기로 옮겨 고정한다.
// ─────────────────────────────────────────────────────────────
const STORAGE_HOST = '127.0.0.1';
const STORAGE_PORT = 6061;
const STORAGE_RULES_PATH = path.resolve(__dirname, '../../../storage.rules');

export async function createStorageTestEnv(): Promise<RulesTestEnvironment> {
  return initializeTestEnvironment({
    projectId: PROJECT_ID,
    storage: {
      host: STORAGE_HOST,
      port: STORAGE_PORT,
      rules: fs.readFileSync(STORAGE_RULES_PATH, 'utf8'),
    },
  });
}
