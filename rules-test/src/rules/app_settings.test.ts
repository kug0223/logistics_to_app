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

  // [R7-LEGAL.1B] 계약이 바뀌었다.
  //
  //   예전에는 슈퍼어드민이 이 문서를 직접 고쳤다. 그래서 **이미 동의를 받은
  //   version 의 본문**을 그 자리에서 바꿀 수 있었고, 그 순간 과거 동의
  //   증거가 어떤 글을 가리키는지 알 수 없게 됐다.
  //
  //   이제 발행은 callablePublishLegalRevision 한 곳이다. 그 함수가
  //   immutable 발행본(legal_revisions)을 만들고 이 목록이 그것을 가리키게
  //   한다 — 둘은 한 transaction 이어야 하므로 클라이언트가 끼어들 수 없다.
  test('AS-WRITE-02 ❌ 슈퍼어드민도 legal_terms를 직접 수정할 수 없다 (CF 전용)', async () => {
    const db = getAuth(env, IDS.superAdmin);
    await assertFails(setDoc(doc(db, 'app_settings', 'legal_terms'), { version: '2.0', content: '개정 약관' }));
  });

  test('AS-WRITE-02b ✅ legal_terms 외 문서는 여전히 슈퍼어드민이 수정한다', async () => {
    const db = getAuth(env, IDS.superAdmin);
    await assertSucceeds(setDoc(doc(db, 'app_settings', 'app_config'), { maxActiveTOPerBusiness: 7 }));
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

// ─────────────────────────────────────────────────────
// LR: legal_revisions — 발행본은 고쳐 쓰지 않는다
// ─────────────────────────────────────────────────────
describe('LR: legal_revisions 발행본', () => {
  test('LR-01 ✅ 비인증 사용자도 발행본을 읽을 수 있다 (가입 화면·공개 페이지)', async () => {
    await seedDoc(env, 'legal_revisions', 'service_terms__2026.08',
      { itemId: 'service_terms', version: '2026.08', content: '본문' });
    const db = env.unauthenticatedContext().firestore();
    await assertSucceeds(getDoc(doc(db, 'legal_revisions', 'service_terms__2026.08')));
  });

  test('LR-02 ❌ 슈퍼어드민도 발행본을 만들 수 없다 (CF 전용)', async () => {
    const db = getAuth(env, IDS.superAdmin);
    await assertFails(setDoc(doc(db, 'legal_revisions', 'service_terms__2026.11'),
      { itemId: 'service_terms', version: '2026.11', content: '새 본문' }));
  });

  test('LR-03 ❌ 발행된 본문을 덮어쓸 수 없다 — 이것이 이 Phase 의 핵심이다', async () => {
    await seedDoc(env, 'legal_revisions', 'service_terms__2026.08',
      { itemId: 'service_terms', version: '2026.08', content: '본문' });
    const db = getAuth(env, IDS.superAdmin);
    await assertFails(setDoc(doc(db, 'legal_revisions', 'service_terms__2026.08'),
      { itemId: 'service_terms', version: '2026.08', content: '몰래 바꾼 본문' }));
  });
});

// ─────────────────────────────────────────────────────
// CE: consentEvents — 증거는 당사자가 만들 수 없다
// ─────────────────────────────────────────────────────
describe('CE: 동의 증거', () => {
  test('CE-01 ✅ 본인은 자기 동의 이력을 읽을 수 있다', async () => {
    await seedDoc(env, `users/${IDS.user}/consentEvents`, 'e1',
      { itemId: 'service_terms', agreed: true });
    const db = getAuth(env, IDS.user);
    await assertSucceeds(getDoc(doc(db, `users/${IDS.user}/consentEvents`, 'e1')));
  });

  test('CE-02 ❌ 본인도 자기 동의 이력을 쓸 수 없다 (증거를 당사자가 만들면 증거가 아니다)', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(setDoc(doc(db, `users/${IDS.user}/consentEvents`, 'e2'),
      { itemId: 'service_terms', agreed: true }));
  });

  test('CE-03 ❌ 남의 동의 이력은 읽을 수 없다', async () => {
    await seedDoc(env, `users/${IDS.user}/consentEvents`, 'e1',
      { itemId: 'service_terms', agreed: true });
    const db = getAuth(env, IDS.admin);
    await assertFails(getDoc(doc(db, `users/${IDS.user}/consentEvents`, 'e1')));
  });
});
