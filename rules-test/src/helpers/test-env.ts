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
    seedBusiness(env, business, { ownerId: admin, adminIds: [admin, subAdmin], name: '테스트사업장', status: 'approved' }),
    // 사업장 biz-002 (admin2 소유)
    seedBusiness(env, business2, { ownerId: admin2, adminIds: [admin2], name: '다른사업장', status: 'approved' }),
  ]);
}
