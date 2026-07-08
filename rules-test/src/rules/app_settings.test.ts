// rules-test/src/rules/app_settings.test.ts
// app_settings 컬렉션 보안 규칙 시나리오
//
// 검증 항목:
//   AS-READ-*  : 읽기 접근 제어 (legal_terms 비인증 공개 여부 포함)
//   AS-WRITE-* : 쓰기 권한 (슈퍼어드민 전용)

import { RulesTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc } from 'firebase/firestore';
import {
  createTestEnv, getAuth, seedDoc, seedCommonFixtures,
  assertFails, assertSucceeds, IDS,
} from '../helpers/test-env';

let env: RulesTestEnvironment;

beforeAll(async () => {
  env = await createTestEnv('app_settings');
  await seedCommonFixtures(env);
  await seedDoc(env, 'app_settings', 'legal_terms', { version: '1.0', content: '서비스 이용약관' });
  await seedDoc(env, 'app_settings', 'app_config', { maxActiveTOPerBusiness: 4 });
});

afterAll(async () => {
  await env.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  await seedCommonFixtures(env);
  await seedDoc(env, 'app_settings', 'legal_terms', { version: '1.0', content: '서비스 이용약관' });
  await seedDoc(env, 'app_settings', 'app_config', { maxActiveTOPerBusiness: 4 });
});

// ─────────────────────────────────────────────────────
// AS-READ: 읽기 접근 제어
// ─────────────────────────────────────────────────────
describe('AS-READ: app_settings 읽기', () => {
  test('AS-READ-01 ✅ 비인증 사용자도 legal_terms는 읽을 수 있다 (회원가입 화면 약관 표시)', async () => {
    // 회원가입 화면은 로그인 전에 약관을 표시해야 함 → 비인증 읽기 허용 필수
    const db = env.unauthenticatedContext().firestore();
    await assertSucceeds(getDoc(doc(db, 'app_settings', 'legal_terms')));
  });

  test('AS-READ-02 ❌ 비인증 사용자는 legal_terms 외 문서(app_config 등)를 읽을 수 없다', async () => {
    const db = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, 'app_settings', 'app_config')));
  });

  test('AS-READ-03 ✅ 로그인 사용자는 legal_terms를 읽을 수 있다', async () => {
    const db = getAuth(env, IDS.user);
    await assertSucceeds(getDoc(doc(db, 'app_settings', 'legal_terms')));
  });

  test('AS-READ-04 ✅ 로그인 사용자는 app_config를 읽을 수 있다', async () => {
    const db = getAuth(env, IDS.user);
    await assertSucceeds(getDoc(doc(db, 'app_settings', 'app_config')));
  });

  test('AS-READ-05 ✅ 사업장관리자는 app_config를 읽을 수 있다 (공고 한도 조회용)', async () => {
    const db = getAuth(env, IDS.admin);
    await assertSucceeds(getDoc(doc(db, 'app_settings', 'app_config')));
  });
});

// ─────────────────────────────────────────────────────
// AS-WRITE: 쓰기 권한 (슈퍼어드민 전용)
// ─────────────────────────────────────────────────────
describe('AS-WRITE: app_settings 쓰기', () => {
  test('AS-WRITE-01 ✅ 슈퍼어드민은 app_config를 수정할 수 있다', async () => {
    const db = getAuth(env, IDS.superAdmin);
    await assertSucceeds(setDoc(doc(db, 'app_settings', 'app_config'), { maxActiveTOPerBusiness: 5 }));
  });

  test('AS-WRITE-02 ✅ 슈퍼어드민은 legal_terms를 수정할 수 있다', async () => {
    const db = getAuth(env, IDS.superAdmin);
    await assertSucceeds(setDoc(doc(db, 'app_settings', 'legal_terms'), { version: '2.0', content: '개정 약관' }));
  });

  test('AS-WRITE-03 ❌ 일반 사용자는 app_settings를 수정할 수 없다', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(setDoc(doc(db, 'app_settings', 'app_config'), { maxActiveTOPerBusiness: 99 }));
  });

  test('AS-WRITE-04 ❌ 사업장관리자는 app_settings를 수정할 수 없다 (TO 한도 자체 상향 차단)', async () => {
    const db = getAuth(env, IDS.admin);
    await assertFails(setDoc(doc(db, 'app_settings', 'app_config'), { maxActiveTOPerBusiness: 99 }));
  });

  test('AS-WRITE-05 ❌ 비인증 사용자는 legal_terms를 수정할 수 없다', async () => {
    const db = env.unauthenticatedContext().firestore();
    await assertFails(setDoc(doc(db, 'app_settings', 'legal_terms'), { version: '9.9' }));
  });
});
