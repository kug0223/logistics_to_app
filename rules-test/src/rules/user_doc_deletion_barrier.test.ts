// rules-test/src/rules/user_doc_deletion_barrier.test.ts
//
// [R7-P4.4E.11C.0C.1] user 문서가 없다 = Final 이 모든 gate 를 통과했다
//
// Auth-tail 재개는 이 추론을 쓴다.
//
//   tombstone 있음 + users/{uid} 없음
//   → Final 이 도메인·개인·identity·Storage·사업장·금전 gate 를 모두
//     통과한 뒤 user 문서를 지웠다
//   → 남은 비가역 작업은 Auth 삭제 하나뿐
//
// 그 추론은 **그 조합을 만들 수 있는 주인이 하나**일 때만 성립한다. 그래서
// 클라이언트가 그것을 만들어 낼 수 있는 두 경로를 막는다.
//
//   DELETE  SUPER_ADMIN 클라이언트가 임의 user 문서를 지울 수 있었다
//           → gate 를 거치지 않고 "user 문서 없음" 을 만들 수 있다
//
//   CREATE  같은 uid 로 문서를 다시 만들 수 있었다
//           → `registration_pending` 으로 만든 뒤
//             `callableAbortForeignRegistration` 으로 지우면
//             역시 gate 없이 같은 조합이 된다
//
// 권한을 통째로 걷어내지 않는다 — **삭제가 시작된 계정에만** 막는다.
// Admin SDK(Final)는 rules 를 우회하므로 정상 탈퇴에는 영향이 없다.
//
// 고정하는 것
//   UDEL-DEL-0x  tombstone 있는 user 문서 삭제 차단 / 없으면 기존 권한 유지
//   UDEL-NEW-0x  tombstone 있는 uid 의 user 문서 재생성 차단
//   UDEL-REG-0x  정상 가입·정상 삭제 회귀
import { RulesTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, setDoc, deleteDoc } from 'firebase/firestore';
import {
  createTestEnv, getAuth, seedDoc, seedCommonFixtures,
  assertFails, assertSucceeds, IDS,
} from '../helpers/test-env';

let env: RulesTestEnvironment;

// 탈퇴 freeze 가 선 계정 — user 문서는 아직 살아 있다(S2).
const DELETING = 'uid-udel-deleting';
// freeze 가 선 뒤 user 문서가 사라진 계정 — 재생성 시도 대상(S3).
const TAIL = 'uid-udel-tail';
// tombstone 이 없는 정상 계정 — 기존 권한 회귀용.
const NORMAL = 'uid-udel-normal';

const newUserDoc = (username: string, accountStatus: string) => ({
  role: 'USER',
  username,
  name: '신규',
  phone: '010-0000-0100',
  accountStatus,
  isBlacklisted: false,
  createdAt: new Date(),
});

beforeAll(async () => {
  env = await createTestEnv('user_doc_deletion_barrier');
  await seedCommonFixtures(env);

  await seedDoc(env, 'users', NORMAL, {
    role: 'USER', username: 'udelnormal', name: '정상',
    accountStatus: 'active', isBlacklisted: false,
  });

  await seedDoc(env, 'users', DELETING, {
    role: 'USER', username: 'udeldeleting', name: '탈퇴중',
    accountStatus: 'deleting', isBlacklisted: false,
  });
  await seedDoc(env, 'account_deletion_tombstones', DELETING, {
    barrierAt: new Date(), schemaVersion: 1,
  });

  // S3: user 문서는 만들지 않는다 — tombstone 만 둔다.
  await seedDoc(env, 'account_deletion_tombstones', TAIL, {
    barrierAt: new Date(), schemaVersion: 1,
  });
});

afterAll(async () => { await env.cleanup(); });

// ─── UDEL-DEL: user 문서 삭제 권위 ──────────────────────────────────────

describe('UDEL-DEL: user 문서 삭제', () => {
  test('UDEL-DEL-01 본인은 자기 user 문서를 지울 수 없다 (기존 계약)', async () => {
    const db = getAuth(env, NORMAL);
    await assertFails(deleteDoc(doc(db, 'users', NORMAL)));
  });

  test('UDEL-DEL-02 일반 관리자도 타인 user 문서를 지울 수 없다', async () => {
    const db = getAuth(env, IDS.admin);
    await assertFails(deleteDoc(doc(db, 'users', NORMAL)));
  });

  test('UDEL-DEL-03 SUPER_ADMIN 은 tombstone 없는 문서를 지울 수 있다 (권한 유지)', async () => {
    await seedDoc(env, 'users', 'uid-udel-victim', {
      role: 'USER', username: 'udelvictim', name: '대상',
      accountStatus: 'active', isBlacklisted: false,
    });
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertSucceeds(deleteDoc(doc(db, 'users', 'uid-udel-victim')));
  });

  test('UDEL-DEL-04 SUPER_ADMIN 도 tombstone 있는 문서는 지울 수 없다', async () => {
    // 이것이 Auth-tail 증거를 위조하는 경로였다.
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertFails(deleteDoc(doc(db, 'users', DELETING)));
  });

  test('UDEL-DEL-05 SUPER_ADMIN 자기 문서 삭제 차단은 그대로다', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertFails(deleteDoc(doc(db, 'users', IDS.superAdmin)));
  });
});

// ─── UDEL-NEW: user 문서 재생성 ─────────────────────────────────────────

describe('UDEL-NEW: user 문서 생성', () => {
  test('UDEL-NEW-01 tombstone 없는 신규 가입은 그대로 된다', async () => {
    const db = getAuth(env, 'uid-udel-fresh');
    await assertSucceeds(setDoc(
      doc(db, 'users', 'uid-udel-fresh'),
      newUserDoc('udelfresh', 'active')));
  });

  test('UDEL-NEW-02 tombstone 있는 uid 는 문서를 다시 만들 수 없다 (S3)', async () => {
    // 재생성이 허용되면 `registration_pending` 으로 만든 뒤 다시 지워
    //   gate 없이 "tombstone + user 없음" 을 만들 수 있다.
    const db = getAuth(env, TAIL);
    await assertFails(setDoc(
      doc(db, 'users', TAIL),
      newUserDoc('udeltail', 'registration_pending')));
  });

  test('UDEL-NEW-03 active 로 만들려 해도 막힌다 — 상태값과 무관하다', async () => {
    const db = getAuth(env, TAIL);
    await assertFails(setDoc(
      doc(db, 'users', TAIL),
      newUserDoc('udeltail2', 'active')));
  });

  test('UDEL-NEW-04 SUPER_ADMIN 더미 생성도 tombstone uid 에는 막힌다', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertFails(setDoc(
      doc(db, 'users', TAIL),
      newUserDoc('udeltail3', 'active')));
  });
});

// ─── UDEL-REG: 회귀 ────────────────────────────────────────────────────

describe('UDEL-REG: 기존 계약 회귀', () => {
  test('UDEL-REG-01 tombstone 컬렉션은 여전히 클라이언트가 못 읽는다', async () => {
    const db = getAuth(env, DELETING);
    await assertFails(
      setDoc(doc(db, 'account_deletion_tombstones', DELETING), { x: 1 }));
    await assertFails(
      deleteDoc(doc(db, 'account_deletion_tombstones', DELETING)));
  });

  test('UDEL-REG-02 탈퇴 중 계정이 자기 문서를 되살려 쓰지 못한다', async () => {
    // user 문서가 살아 있는 S2 에서도 create 경로는 막힌다(이미 존재하므로
    //   create 가 아니지만, 삭제 뒤 재생성 시나리오를 같은 규칙이 막는다).
    const db = getAuth(env, DELETING);
    await assertFails(setDoc(
      doc(db, 'users', DELETING),
      newUserDoc('udeldeleting2', 'active')));
  });
});
