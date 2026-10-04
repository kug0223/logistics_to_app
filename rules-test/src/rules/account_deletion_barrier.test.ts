// rules-test/src/rules/account_deletion_barrier.test.ts
//
// [R7-P4.4E.11C.0C.0a.4] 탈퇴 cleanup 이 지나간 뒤 다시 생기는 행들
//
// Final 이 MUST_DELETE 를 fail-closed 로 치우게 만들어도, 그 행을 **클라이언트
// Rules 가 canonical writer 로 다시 만들 수 있으면** 완결성은 깨진다. 그리고
// 그때는 되돌릴 주인이 없다 — uid 는 더 이상 인증할 수 없고, 이 프로젝트는
// 전역 sweeper 를 만들지 않는다.
//
// 그래서 barrier 의 source of truth 는 `accountStatus` 가 아니라
// `account_deletion_tombstones/{uid}` 다. accountStatus 는 user 문서와 함께
// 사라지지만 tombstone 은 살아남는다.
//
// 그리고 members 에는 별도의 문제가 있었다.
//
//   권위    `members/$(request.auth.uid)` — **경로의 uid**
//   cleanup `collectionGroup("members").where("uid","==",uid)` — **data field**
//
// 둘이 어긋난 문서를 만들 수 있으면 cleanup 이 그 행을 영원히 못 찾는다.
//
// 고정하는 것
//   MEM-DEL-0x   members create tombstone barrier (모든 분기)
//   MEM-ID-0x    members path ↔ data identity binding
//   INV-DEL-0x   member_invitations create barrier
//   ICAR-DEL-0x  idCardAccessRequests create barrier
//   BAR-0x       tombstone 자체의 접근 계약
import { RulesTestEnvironment } from '@firebase/rules-unit-testing';
import {
  doc, getDoc, setDoc, updateDoc, deleteDoc, serverTimestamp,
} from 'firebase/firestore';
import {
  createTestEnv, getAuth, seedDoc, seedCommonFixtures,
  assertFails, assertSucceeds, IDS,
} from '../helpers/test-env';

let env: RulesTestEnvironment;

// 탈퇴 진행 중인 사용자 — tombstone 보유
const DELETING = 'uid-deleting';
// tombstone 이 없는 정상 사용자 — 정상 흐름 회귀용.
//
//   전용 uid 를 쓴다. 처음에는 `IDS.user2` 를 썼는데 businesses.test.ts 의
//   MEM-CREATE-01 이 같은 `members/{IDS.user2}` 경로를 먼저 만든다. 그러면
//   여기의 setDoc 이 create 가 아니라 **update** 가 되어 create 규칙을
//   전혀 검증하지 않고, 실행 순서에 따라 결과가 바뀐다.
const NORMAL = 'uid-barrier-normal';

const INV_NORMAL = 'inv-normal';
const INV_DELETING = 'inv-deleting';

beforeAll(async () => {
  env = await createTestEnv('account_deletion_barrier');
  await seedCommonFixtures(env);

  // 정상 사용자 — 이 스위트 전용.
  await seedDoc(env, 'users', NORMAL, {
    role: 'USER', username: 'barriernormal', name: '정상',
    accountStatus: 'active', isBlacklisted: false,
  });

  // 탈퇴 진행 중 사용자: user 문서는 아직 살아 있고 tombstone 이 서 있다.
  await seedDoc(env, 'users', DELETING, {
    role: 'USER', username: 'deleting', name: '탈퇴중',
    accountStatus: 'deleting', isBlacklisted: false,
  });
  await seedDoc(env, 'account_deletion_tombstones', DELETING, {
    barrierAt: new Date(), schemaVersion: 1,
  });

  // 정상 사용자용 pending 초대 (self create 경로 검증)
  await seedDoc(env, 'member_invitations', INV_NORMAL, {
    businessId: IDS.business, businessName: '테스트사업장',
    targetUid: NORMAL, targetName: '유저2', targetPhone: '010-0000-0002',
    invitedBy: IDS.admin, invitedByName: '관리자',
    permissions: {}, status: 'pending', createdAt: new Date(),
  });

  // 탈퇴 진행 중 사용자용 pending 초대 — cleanup 이 놓친 경우를 모사한다.
  await seedDoc(env, 'member_invitations', INV_DELETING, {
    businessId: IDS.business, businessName: '테스트사업장',
    targetUid: DELETING, targetName: '탈퇴중', targetPhone: '010-0000-0003',
    invitedBy: IDS.admin, invitedByName: '관리자',
    permissions: {}, status: 'pending', createdAt: new Date(),
  });
});

afterAll(async () => { await env.cleanup(); });

const memberDoc = (uid: string, businessId: string) => ({
  uid, businessId, name: '이름', phone: '010-0000-0000',
  role: 'WORKER', permissions: {}, addedAt: new Date(),
});

// ─── MEM-DEL: members create tombstone barrier ──────────────────────────

describe('MEM-DEL: 탈퇴 barrier 는 members create 의 모든 분기를 막는다', () => {
  test('MEM-DEL-01 tombstone 없음 + 관리자 create → 허용 (정상 흐름 보존)', async () => {
    const db = getAuth(env, IDS.admin, { role: 'BUSINESS_ADMIN' });
    await assertSucceeds(setDoc(
      doc(db, 'businesses', IDS.business, 'members', 'uid-fresh-01'),
      memberDoc('uid-fresh-01', IDS.business)));
  });

  test('MEM-DEL-02 tombstone 없음 + 유효 초대 본인 create → 허용', async () => {
    const db = getAuth(env, NORMAL);
    await assertSucceeds(setDoc(
      doc(db, 'businesses', IDS.business, 'members', NORMAL),
      { ...memberDoc(NORMAL, IDS.business), invitationId: INV_NORMAL }));
  });

  test('MEM-DEL-03 tombstone 존재 + 관리자 create → 거부', async () => {
    const db = getAuth(env, IDS.admin, { role: 'BUSINESS_ADMIN' });
    await assertFails(setDoc(
      doc(db, 'businesses', IDS.business, 'members', DELETING),
      memberDoc(DELETING, IDS.business)));
  });

  test('MEM-DEL-04 tombstone 존재 + 본인 초대 수락 create → 거부', async () => {
    // 초대가 유효해도 막힌다 — cleanup 이 지나간 뒤 이름·전화번호가
    // 다시 생기는 것을 허용할 수 없다.
    const db = getAuth(env, DELETING);
    await assertFails(setDoc(
      doc(db, 'businesses', IDS.business, 'members', DELETING),
      { ...memberDoc(DELETING, IDS.business), invitationId: INV_DELETING }));
  });

  test('MEM-DEL-05 tombstone 존재 + SUPER_ADMIN create → 거부', async () => {
    // tombstone 은 deletion lifecycle authority 다. 역할로 우회되지 않는다.
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertFails(setDoc(
      doc(db, 'businesses', IDS.business, 'members', DELETING),
      memberDoc(DELETING, IDS.business)));
  });

  test('MEM-DEL-06 남의 tombstone 은 영향이 없다', async () => {
    const db = getAuth(env, IDS.admin, { role: 'BUSINESS_ADMIN' });
    await assertSucceeds(setDoc(
      doc(db, 'businesses', IDS.business, 'members', 'uid-fresh-06'),
      memberDoc('uid-fresh-06', IDS.business)));
  });

  test('MEM-DEL-07 tombstone 존재 + 다른 사업장 관리자 create → 거부', async () => {
    const db = getAuth(env, IDS.admin2, { role: 'BUSINESS_ADMIN' });
    await assertFails(setDoc(
      doc(db, 'businesses', IDS.business2, 'members', DELETING),
      memberDoc(DELETING, IDS.business2)));
  });
});

// ─── MEM-ID: path ↔ data identity binding ───────────────────────────────

describe('MEM-ID: 권위가 보는 identity 와 cleanup 이 보는 identity 가 같다', () => {
  test('MEM-ID-01 경로 uid != data.uid → 거부', async () => {
    // 이것이 허용되면 cleanup 쿼리(data.uid 기준)가 이 행을 못 찾는다.
    const db = getAuth(env, IDS.admin, { role: 'BUSINESS_ADMIN' });
    await assertFails(setDoc(
      doc(db, 'businesses', IDS.business, 'members', 'uid-mismatch-01'),
      memberDoc(IDS.user, IDS.business)));
  });

  test('MEM-ID-02 경로 businessId != data.businessId → 거부', async () => {
    const db = getAuth(env, IDS.admin, { role: 'BUSINESS_ADMIN' });
    await assertFails(setDoc(
      doc(db, 'businesses', IDS.business, 'members', 'uid-mismatch-02'),
      memberDoc('uid-mismatch-02', IDS.business2)));
  });

  test('MEM-ID-03 uid field 누락 → 거부', async () => {
    const db = getAuth(env, IDS.admin, { role: 'BUSINESS_ADMIN' });
    const { uid: _omit, ...noUid } = memberDoc('uid-mismatch-03', IDS.business);
    await assertFails(setDoc(
      doc(db, 'businesses', IDS.business, 'members', 'uid-mismatch-03'),
      noUid));
  });

  test('MEM-ID-04 canonical 값 → 기존 동작 유지', async () => {
    const db = getAuth(env, IDS.admin, { role: 'BUSINESS_ADMIN' });
    await assertSucceeds(setDoc(
      doc(db, 'businesses', IDS.business, 'members', 'uid-canon-04'),
      memberDoc('uid-canon-04', IDS.business)));
  });
});

// ─── INV-DEL: member_invitations create barrier ──────────────────────────

const invitationDoc = (targetUid: string) => ({
  businessId: IDS.business, businessName: '테스트사업장',
  targetUid, targetName: '이름', targetPhone: '010-0000-0000',
  invitedBy: IDS.admin, invitedByName: '관리자',
  permissions: {}, status: 'pending',
});

describe('INV-DEL: 탈퇴 대상에게 새 초대를 보낼 수 없다', () => {
  test('INV-DEL-01 tombstone 없음 → 기존 초대 발송 동작 유지', async () => {
    // 기존 rule 이 `createdAt == request.time` 을 요구한다(소급 생성 차단).
    // 그래서 정상 경로는 serverTimestamp() 다 — barrier 와 무관한 기존 계약.
    const db = getAuth(env, IDS.admin, { role: 'BUSINESS_ADMIN' });
    await assertSucceeds(setDoc(
      doc(db, 'member_invitations', 'inv-new-01'),
      { ...invitationDoc(NORMAL), createdAt: serverTimestamp() }));
  });

  test('INV-DEL-02 tombstone 존재 → 거부', async () => {
    const db = getAuth(env, IDS.admin, { role: 'BUSINESS_ADMIN' });
    await assertFails(setDoc(
      doc(db, 'member_invitations', 'inv-new-02'),
      { ...invitationDoc(DELETING), createdAt: serverTimestamp() }));
  });

  test('INV-DEL-03 SUPER_ADMIN 분기도 거부', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertFails(setDoc(
      doc(db, 'member_invitations', 'inv-new-03'),
      { ...invitationDoc(DELETING), createdAt: serverTimestamp() }));
  });

  test('INV-DEL-04 기존 초대의 update semantics 는 바뀌지 않았다', async () => {
    // barrier 는 create 에만 걸린다. 이미 있는 초대의 수락/거절 경로는
    // 그대로다 — 그 흐름을 깨면 정상 사용자가 막힌다.
    const db = getAuth(env, NORMAL);
    await assertSucceeds(updateDoc(
      doc(db, 'member_invitations', INV_NORMAL),
      { status: 'rejected', respondedAt: new Date() }));
  });

  test('INV-DEL-05 targetUid 누락 → 거부', async () => {
    const db = getAuth(env, IDS.admin, { role: 'BUSINESS_ADMIN' });
    const { targetUid: _omit, ...noTarget } = invitationDoc(NORMAL);
    await assertFails(setDoc(
      doc(db, 'member_invitations', 'inv-new-05'),
      { ...noTarget, createdAt: serverTimestamp() }));
  });
});

// ─── ICAR-DEL: idCardAccessRequests create barrier ──────────────────────

const icarDoc = (targetUserId: string) => ({
  requesterId: IDS.admin,
  requesterBusinessId: IDS.business,
  targetUserId,
  applicationId: 'app-barrier-001',
  status: 'pending',
});

describe('ICAR-DEL: 탈퇴 대상의 신분증 열람 요청을 새로 만들 수 없다', () => {
  test('ICAR-DEL-01 tombstone 없음 → 기존 create 동작 유지', async () => {
    const db = getAuth(env, IDS.admin, { role: 'BUSINESS_ADMIN' });
    await assertSucceeds(setDoc(
      doc(db, 'idCardAccessRequests', 'icar-barrier-01'),
      icarDoc(NORMAL)));
  });

  test('ICAR-DEL-02 tombstone 존재 → 거부', async () => {
    const db = getAuth(env, IDS.admin, { role: 'BUSINESS_ADMIN' });
    await assertFails(setDoc(
      doc(db, 'idCardAccessRequests', 'icar-barrier-02'),
      icarDoc(DELETING)));
  });

  test('ICAR-DEL-03 SUPER_ADMIN 분기도 거부', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertFails(setDoc(
      doc(db, 'idCardAccessRequests', 'icar-barrier-03'),
      icarDoc(DELETING)));
  });

  test('ICAR-DEL-04 targetUserId 누락 → 거부', async () => {
    const db = getAuth(env, IDS.admin, { role: 'BUSINESS_ADMIN' });
    const { targetUserId: _omit, ...noTarget } = icarDoc(NORMAL);
    await assertFails(setDoc(
      doc(db, 'idCardAccessRequests', 'icar-barrier-04'),
      noTarget));
  });
});

// ─── BAR: tombstone 자체의 접근 계약 ────────────────────────────────────

describe('BAR: barrier 문서는 클라이언트에게 닫혀 있다', () => {
  test('BAR-01 본인도 읽을 수 없다', async () => {
    const db = getAuth(env, DELETING);
    await assertFails(getDoc(
      doc(db, 'account_deletion_tombstones', DELETING)));
  });

  test('BAR-02 SUPER_ADMIN 도 읽을 수 없다', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertFails(getDoc(
      doc(db, 'account_deletion_tombstones', DELETING)));
  });

  test('BAR-03 스스로 barrier 를 만들 수 없다 (가용성 공격 차단)', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(setDoc(
      doc(db, 'account_deletion_tombstones', IDS.user),
      { barrierAt: new Date(), schemaVersion: 1 }));
  });

  test('BAR-04 barrier 를 걷어낼 수 없다 (경합 되살리기 차단)', async () => {
    const db = getAuth(env, DELETING);
    await assertFails(deleteDoc(
      doc(db, 'account_deletion_tombstones', DELETING)));
  });
});
