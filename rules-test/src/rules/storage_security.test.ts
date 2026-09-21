// rules-test/src/rules/storage_security.test.ts
//
// [R8-P5.3] storage.rules 보안 회귀 (§34)
//
//   2026-09-21 감사에서, 배포된 Storage Rules 가 2026-07-09 판이었다.
//   그 사이 커밋된 보안 수정이 live 가 아니어서, 어느 사업장과도 무관한
//   근로자 계정으로 남의 사업자등록증을 읽고, 근로계약서 서명 이미지와
//   PDF 를 올리고, 사업장 파일을 지울 수 있었다. DEV 에서 6건 전부 재현했다.
//
//   배포한 뒤에도 등록증 "읽기"만 열려 있었다. Storage Rules 는 매칭되는
//   모든 블록을 OR 로 합치기 때문에, license/ 전용 블록의 read:false 가
//   일반 블록의 get:isLoggedIn() 에 덮였다. 소스 주석은 "더 구체적인 규칙이
//   우선 적용됨" 이라고 단언하고 있었지만 사실이 아니었다.
//
//   아래 7건은 그때 확인한 것을 그대로 고정한 것이다.
//   클라이언트 직접 경로는 전부 막혀 있고, 쓰기는 CF Admin SDK 전용이다
//   (Admin SDK 는 규칙을 우회하므로 이 테스트 범위 밖이다).
import { RulesTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { ref, uploadBytes, getBytes, deleteObject } from 'firebase/storage';
import { createStorageTestEnv } from '../helpers/test-env';

const BIZ = 'biz-001';
const OUTSIDER = 'outsider-uid';   // 어느 사업장과도 무관한 로그인 사용자
const CONTRACT = 'contract-001';
const BLOB = new Uint8Array([0xff, 0xd8, 0xff, 0xd9]); // 최소 JPEG — 합성, 개인정보 없음

let env: RulesTestEnvironment;

/** 규칙을 끈 채로 파일을 심는다 — CF Admin SDK 가 올려 둔 상태를 재현 */
async function seedFile(path: string) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await uploadBytes(ref(ctx.storage(), path), BLOB, { contentType: 'image/jpeg' });
  });
}

beforeAll(async () => {
  env = await createStorageTestEnv();
});

afterAll(async () => {
  await env.cleanup();
});

beforeEach(async () => {
  await env.clearStorage();
});

describe('[R8-P5.3] storage.rules — 클라이언트 직접 경로 차단', () => {
  // ── 쓰기 ──────────────────────────────────────────────
  it('SR-1 무관한 사용자는 사업자등록증 경로에 올릴 수 없다', async () => {
    const s = env.authenticatedContext(OUTSIDER).storage();
    await assertFails(
      uploadBytes(ref(s, `businesses/${BIZ}/license/probe.jpg`), BLOB, { contentType: 'image/jpeg' }),
    );
  });

  it('SR-2 무관한 사용자는 일반 사업장 이미지도 올릴 수 없다 (CF 전용)', async () => {
    const s = env.authenticatedContext(OUTSIDER).storage();
    await assertFails(
      uploadBytes(ref(s, `businesses/${BIZ}/main.jpg`), BLOB, { contentType: 'image/jpeg' }),
    );
  });

  it('SR-3 클라이언트는 근로계약서 서명 이미지를 올릴 수 없다', async () => {
    const s = env.authenticatedContext(OUTSIDER).storage();
    await assertFails(
      uploadBytes(ref(s, `contracts/${CONTRACT}/signature_worker.png`), BLOB, { contentType: 'image/png' }),
    );
    await assertFails(
      uploadBytes(ref(s, `contracts/${CONTRACT}/signature_employer.png`), BLOB, { contentType: 'image/png' }),
    );
  });

  it('SR-4 클라이언트는 근로계약서 PDF 를 올릴 수 없다', async () => {
    const s = env.authenticatedContext(OUTSIDER).storage();
    await assertFails(
      uploadBytes(ref(s, `contracts/${CONTRACT}/contract.pdf`), BLOB, { contentType: 'application/pdf' }),
    );
  });

  // ── 읽기 ──────────────────────────────────────────────
  it('SR-5 사업자등록증은 로그인해도 읽을 수 없다 (CF Signed URL 전용)', async () => {
    const path = `businesses/${BIZ}/license/20260101.jpg`;
    await seedFile(path);
    const s = env.authenticatedContext(OUTSIDER).storage();
    await assertFails(getBytes(ref(s, path)));
  });

  // ── 삭제 ──────────────────────────────────────────────
  it('SR-6 무관한 사용자는 남의 사업장 파일을 지울 수 없다', async () => {
    const path = `businesses/${BIZ}/main.jpg`;
    await seedFile(path);
    const s = env.authenticatedContext(OUTSIDER).storage();
    await assertFails(deleteObject(ref(s, path)));
  });

  // ── Golden Path ───────────────────────────────────────
  it('SR-7 일반 사업장 이미지는 로그인 사용자가 읽을 수 있다', async () => {
    const path = `businesses/${BIZ}/main.jpg`;
    await seedFile(path);
    const s = env.authenticatedContext(OUTSIDER).storage();
    await assertSucceeds(getBytes(ref(s, path)));
  });
});

describe('[R8-P5.3] storage.rules — 민감 파일은 본인만', () => {
  it('SR-8 신분증·통장 경로는 본인만 읽는다', async () => {
    const path = 'users/owner-uid/idCard_1.jpg';
    await seedFile(path);
    await assertSucceeds(getBytes(ref(env.authenticatedContext('owner-uid').storage(), path)));
    await assertFails(getBytes(ref(env.authenticatedContext(OUTSIDER).storage(), path)));
  });

  it('SR-9 남의 경로에는 올릴 수 없다', async () => {
    const s = env.authenticatedContext(OUTSIDER).storage();
    await assertFails(
      uploadBytes(ref(s, 'users/owner-uid/idCard_2.jpg'), BLOB, { contentType: 'image/jpeg' }),
    );
  });
});
