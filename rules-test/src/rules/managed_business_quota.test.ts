// rules-test/src/rules/managed_business_quota.test.ts
//
// [R8-P3B.3B] 사업장 생성 쿼터 + koreanName write 경계.
//
//   Q-*  users/{uid}.managedBusinessIds 는 businesses create 의 [RATE-01] 쿼터
//        (배열 길이 < 5)가 그대로 읽는 값이다. 본인이 자유롭게 쓸 수 있으면
//        "비우고 다시 만들기"로 5개 제한이 사실상 없는 것과 같았다.
//        이제 쓰기 경로는 [BIZ-CREATE-FIX] 브랜치 하나뿐이고
//        "기존 전부 유지 + 정확히 1개 증가 + 증가 전 5개 미만"만 통과한다.
//
//   FK-* koreanName 은 [PII-B4-R1.4.3] denylist 에 있다.
//        클라이언트 직접 write 는 본인 문서든 타인 문서든 막히고,
//        저장은 callableFinalizeForeignIdentity(Admin SDK)만 한다.
//        CF 쪽 실제 저장은 에뮬레이터에서 돌릴 수 없으므로 DEV 런타임에서 확인한다.
import { RulesTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, setDoc, updateDoc } from 'firebase/firestore';
import {
  createTestEnv, getAuth, seedUser, seedBusiness,
  assertFails, assertSucceeds,
} from '../helpers/test-env';

const ADMIN = 'mbq-admin';
const OTHER = 'mbq-other';
const FOREIGN = 'mbq-foreign';

let env: RulesTestEnvironment;

/** managedBusinessIds 를 n개 가진 BUSINESS_ADMIN 으로 다시 시드한다. */
async function seedAdminWith(ids: string[]) {
  await seedUser(env, ADMIN, {
    role: 'BUSINESS_ADMIN',
    name: '관리자',
    isBlacklisted: false,
    managedBusinessIds: ids,
  });
}

const bizPayload = (ownerId: string) => ({
  ownerId,
  adminIds: [ownerId],
  name: '신규사업장',
  businessNumber: '1234567890',  // [LOW-1] 10자리 숫자
  isApproved: false,             // [SEC-89] 서버 승인 전
  rating: 0,
  reviewCount: 0,
});

beforeAll(async () => {
  env = await createTestEnv('managed_business_quota');
});

afterAll(async () => {
  await env.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  await Promise.all([
    seedUser(env, OTHER, { role: 'BUSINESS_ADMIN', name: '타인', isBlacklisted: false, managedBusinessIds: [] }),
    seedAdminWith([]),
    seedUser(env, FOREIGN, {
      role: 'USER', name: '외국인', isBlacklisted: false,
      legalName: 'NGUYEN VAN A',
      koreanName: '응웬반아',
      accountStatus: 'registration_pending',
    }),
  ]);
});

// ═══════════════════════════════════════════════════════════════
// Q-1 ~ Q-3  businesses create 쿼터 ([RATE-01])
// ═══════════════════════════════════════════════════════════════
describe('Q 사업장 생성 쿼터', () => {
  test('Q-1 0 → 1 생성 허용', async () => {
    await seedAdminWith([]);
    const db = getAuth(env, ADMIN);
    await assertSucceeds(setDoc(doc(db, 'businesses', 'mbq-biz-1'), bizPayload(ADMIN)));
  });

  test('Q-2 4 → 5 생성 허용 (마지막 한 자리)', async () => {
    await seedAdminWith(['b1', 'b2', 'b3', 'b4']);
    const db = getAuth(env, ADMIN);
    await assertSucceeds(setDoc(doc(db, 'businesses', 'mbq-biz-5'), bizPayload(ADMIN)));
  });

  test('Q-3 5 → 6 생성 차단', async () => {
    await seedAdminWith(['b1', 'b2', 'b3', 'b4', 'b5']);
    const db = getAuth(env, ADMIN);
    await assertFails(setDoc(doc(db, 'businesses', 'mbq-biz-6'), bizPayload(ADMIN)));
  });
});

// ═══════════════════════════════════════════════════════════════
// Q-4 ~ Q-8  managedBusinessIds 쓰기 경계
// ═══════════════════════════════════════════════════════════════
describe('Q managedBusinessIds 쓰기 경계', () => {
  test('Q-4 3 → 0 (비우기) 차단 — 쿼터 우회의 핵심 경로', async () => {
    await seedAdminWith(['b1', 'b2', 'b3']);
    const db = getAuth(env, ADMIN);
    await assertFails(
      updateDoc(doc(db, 'users', ADMIN), { managedBusinessIds: [] }),
    );
  });

  test('Q-5 3 → 2 (축소) 차단', async () => {
    await seedAdminWith(['b1', 'b2', 'b3']);
    const db = getAuth(env, ADMIN);
    await assertFails(
      updateDoc(doc(db, 'users', ADMIN), { managedBusinessIds: ['b1', 'b2'] }),
    );
  });

  test('Q-6 기존 id 교체 차단 (길이는 같고 내용만 바뀜)', async () => {
    await seedAdminWith(['b1', 'b2', 'b3']);
    const db = getAuth(env, ADMIN);
    await assertFails(
      updateDoc(doc(db, 'users', ADMIN), { managedBusinessIds: ['b1', 'b2', 'bX'] }),
    );
  });

  test('Q-6b 길이는 +1이지만 기존 id를 하나 빼면 차단', async () => {
    await seedAdminWith(['b1', 'b2', 'b3']);
    const db = getAuth(env, ADMIN);
    await assertFails(
      updateDoc(doc(db, 'users', ADMIN), { managedBusinessIds: ['b1', 'b2', 'bX', 'bY'] }),
    );
  });

  test('Q-7 한 번에 +2 차단', async () => {
    await seedAdminWith(['b1']);
    const db = getAuth(env, ADMIN);
    await assertFails(
      updateDoc(doc(db, 'users', ADMIN), { managedBusinessIds: ['b1', 'b2', 'b3'] }),
    );
  });

  test('Q-8 기존 배열 유지 + 정확히 1개 추가 허용', async () => {
    await seedAdminWith(['b1', 'b2']);
    const db = getAuth(env, ADMIN);
    await assertSucceeds(
      updateDoc(doc(db, 'users', ADMIN), { managedBusinessIds: ['b1', 'b2', 'b3'] }),
    );
  });

  test('Q-9 5개에서 +1도 차단 (쓰기 시점 쿼터 이중 방어)', async () => {
    await seedAdminWith(['b1', 'b2', 'b3', 'b4', 'b5']);
    const db = getAuth(env, ADMIN);
    await assertFails(
      updateDoc(doc(db, 'users', ADMIN), { managedBusinessIds: ['b1', 'b2', 'b3', 'b4', 'b5', 'b6'] }),
    );
  });

  test('Q-10 타인의 managedBusinessIds는 건드릴 수 없다', async () => {
    await seedAdminWith(['b1']);
    const db = getAuth(env, ADMIN);
    await assertFails(
      updateDoc(doc(db, 'users', OTHER), { managedBusinessIds: ['b1'] }),
    );
  });

  test('Q-11 managedBusinessIds에 다른 필드를 얹으면 차단', async () => {
    await seedAdminWith(['b1']);
    const db = getAuth(env, ADMIN);
    await assertFails(
      updateDoc(doc(db, 'users', ADMIN), {
        managedBusinessIds: ['b1', 'b2'],
        phone: '01011112222',
      }),
    );
  });

  test('Q-12 BUSINESS_ADMIN이 아니면 추가도 불가', async () => {
    await seedUser(env, ADMIN, {
      role: 'USER', name: '일반', isBlacklisted: false, managedBusinessIds: [],
    });
    const db = getAuth(env, ADMIN);
    await assertFails(
      updateDoc(doc(db, 'users', ADMIN), { managedBusinessIds: ['b1'] }),
    );
  });

  test('Q-13 빈 문자열 id 추가 차단', async () => {
    await seedAdminWith(['b1']);
    const db = getAuth(env, ADMIN);
    await assertFails(
      updateDoc(doc(db, 'users', ADMIN), { managedBusinessIds: ['b1', ''] }),
    );
  });
});

// ═══════════════════════════════════════════════════════════════
// Q-14  사업장 생성 배치 회귀 — 실제 생성 흐름이 깨지지 않는지
// ═══════════════════════════════════════════════════════════════
describe('Q 사업장 생성 배치 회귀', () => {
  // 실제 흐름(business_form_screen)은 businesses.set 과 users.update 를
  // 하나의 WriteBatch 로 보낸다. 규칙은 각 write 를 커밋 전 상태 기준으로 본다 —
  // 그래서 users.update 쪽에서 isAdminOf(새 businessId) 를 요구하면 절대 통과할 수 없다
  // (그 사업장 문서가 아직 없다). 이 두 테스트가 그 조합을 고정한다.
  test('Q-14 business 문서가 아직 없어도 managedBusinessIds +1은 통과한다', async () => {
    await seedAdminWith([]);
    const db = getAuth(env, ADMIN);
    await assertSucceeds(
      updateDoc(doc(db, 'users', ADMIN), { managedBusinessIds: ['mbq-biz-new'] }),
    );
  });

  test('Q-15 이미 등록된 사업장 id를 다시 arrayUnion 해도(no-op) 통과한다', async () => {
    await seedAdminWith(['b1']);
    await seedBusiness(env, 'b1', { ownerId: ADMIN, adminIds: [ADMIN], name: '기존', isApproved: true });
    const db = getAuth(env, ADMIN);
    // 값이 같으면 affectedKeys 가 비어 diff 가 없다 — denylist 에 걸리지 않는다.
    await assertSucceeds(
      updateDoc(doc(db, 'users', ADMIN), { managedBusinessIds: ['b1'] }),
    );
  });
});

// ═══════════════════════════════════════════════════════════════
// FK-1 / FK-3 / FK-4  koreanName write 경계
// ═══════════════════════════════════════════════════════════════
describe('FK koreanName 클라이언트 write 차단', () => {
  test('FK-1 본인도 koreanName을 직접 쓸 수 없다 (CF 전용)', async () => {
    const db = getAuth(env, FOREIGN);
    await assertFails(
      updateDoc(doc(db, 'users', FOREIGN), { koreanName: '새이름' }),
    );
  });

  test('FK-3 타인의 koreanName은 더더욱 쓸 수 없다', async () => {
    const db = getAuth(env, ADMIN);
    await assertFails(
      updateDoc(doc(db, 'users', FOREIGN), { koreanName: '남의이름' }),
    );
  });

  test('FK-4 legalName도 같은 denylist에 있다 (이름 축 전체가 CF 전용)', async () => {
    const db = getAuth(env, FOREIGN);
    await assertFails(
      updateDoc(doc(db, 'users', FOREIGN), { legalName: 'FAKE NAME' }),
    );
  });

  test('FK-4b name도 직접 쓸 수 없다', async () => {
    const db = getAuth(env, FOREIGN);
    await assertFails(
      updateDoc(doc(db, 'users', FOREIGN), { name: '바꾼이름' }),
    );
  });

  test('FK-4c 이름 축 밖의 프로필 필드는 여전히 본인이 쓸 수 있다', async () => {
    const db = getAuth(env, FOREIGN);
    await assertSucceeds(
      updateDoc(doc(db, 'users', FOREIGN), { phone: '01033334444' }),
    );
  });
});

// ═══════════════════════════════════════════════════════════════
// BL-1 ~ BL-3  사업자등록증 metadata write 경계
//
//   users/{uid}.businessLicenseImageUrl 은 표시용이 아니다.
//   checkBusinessLicense → 사업장 자동승인 / assertBusinessPostingReady 를 거쳐
//   공고 등록 선행조건을 연다. 그런데 본인이 직접 쓸 수 있었고,
//   레거시 분기는 경로 검증도 없었다 — 아무 이미지 URL 한 줄로 관문이 열렸다
//   (DEV 실측으로 확인). 이제 callableRegisterBusinessLicense 전용이다.
// ═══════════════════════════════════════════════════════════════
describe('BL 사업자등록증 metadata 는 CF 전용', () => {
  test('BL-1 본인도 businessLicenseImageUrl 을 직접 쓸 수 없다', async () => {
    const db = getAuth(env, ADMIN);
    await assertFails(
      updateDoc(doc(db, 'users', ADMIN), {
        businessLicenseImageUrl: 'https://example.com/anything.jpg',
      }),
    );
  });

  test('BL-1b businessLicenseImagePath 도 직접 쓸 수 없다', async () => {
    const db = getAuth(env, ADMIN);
    await assertFails(
      updateDoc(doc(db, 'users', ADMIN), {
        businessLicenseImagePath: `users/${ADMIN}/businessLicense_fake.jpg`,
      }),
    );
  });

  test('BL-1c businessLicenseUploadedAt 도 직접 쓸 수 없다', async () => {
    const db = getAuth(env, ADMIN);
    await assertFails(
      updateDoc(doc(db, 'users', ADMIN), {
        businessLicenseUploadedAt: new Date(),
      }),
    );
  });

  test('BL-2 관계없는 프로필 필드는 여전히 본인이 쓸 수 있다', async () => {
    const db = getAuth(env, ADMIN);
    await assertSucceeds(
      updateDoc(doc(db, 'users', ADMIN), { phone: '01055556666' }),
    );
  });

  test('BL-3 타인의 사업자등록증 필드는 더더욱 쓸 수 없다', async () => {
    const db = getAuth(env, ADMIN);
    await assertFails(
      updateDoc(doc(db, 'users', OTHER), {
        businessLicenseImagePath: `users/${OTHER}/businessLicense_x.jpg`,
      }),
    );
  });
});
