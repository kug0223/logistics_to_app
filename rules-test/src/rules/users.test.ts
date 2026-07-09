// rules-test/src/rules/users.test.ts
// users 컬렉션 보안 규칙 시나리오
//
// 검증 항목:
//   U-READ-*  : get/list 접근 제어
//   U-CREATE-*: create 민감 필드 차단
//   U-UPDATE-*: update 필드별 차단/허용
//   U-DELETE-*: delete 권한 제어

import { RulesTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc, collection, query, limit, getDocs, deleteField } from 'firebase/firestore';
import {
  createTestEnv, getAnonymous, getAuth,
  seedCommonFixtures, seedUser, seedDoc,
  IDS,
} from '../helpers/test-env';

let env: RulesTestEnvironment;

beforeAll(async () => {
  env = await createTestEnv('users');
  await seedCommonFixtures(env);
});

afterAll(async () => {
  await env.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  await seedCommonFixtures(env);
});

// ─────────────────────────────────────────────────────
// U-READ: GET
// ─────────────────────────────────────────────────────
describe('U-READ-GET: users 문서 읽기', () => {
  test('U-READ-01 ✅ 본인 문서는 본인이 읽을 수 있다', async () => {
    const db = getAuth(env, IDS.user);
    await assertSucceeds(getDoc(doc(db, 'users', IDS.user)));
  });

  test('U-READ-02 ✅ 슈퍼어드민은 아무 문서나 읽을 수 있다', async () => {
    const db = getAuth(env, IDS.superAdmin);
    await assertSucceeds(getDoc(doc(db, 'users', IDS.user)));
  });

  test('U-READ-03 ✅ 사업장관리자는 USER 역할 문서를 읽을 수 있다', async () => {
    const db = getAuth(env, IDS.admin);
    await assertSucceeds(getDoc(doc(db, 'users', IDS.user)));
  });

  test('U-READ-04 ✅ 서브어드민도 USER 역할 문서를 읽을 수 있다', async () => {
    const db = getAuth(env, IDS.subAdmin);
    await assertSucceeds(getDoc(doc(db, 'users', IDS.user)));
  });

  test('U-READ-05 ❌ 비로그인 상태에서는 읽기 불가', async () => {
    const db = getAnonymous(env);
    await assertFails(getDoc(doc(db, 'users', IDS.user)));
  });

  test('U-READ-06 ❌ 일반 유저는 다른 USER 문서를 읽을 수 없다', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(getDoc(doc(db, 'users', IDS.user2)));
  });

  test('U-READ-07 ❌ 사업장관리자는 다른 BUSINESS_ADMIN 문서를 읽을 수 없다', async () => {
    const db = getAuth(env, IDS.admin);
    await assertFails(getDoc(doc(db, 'users', IDS.admin2)));
  });

  test('U-READ-08 ❌ 사업장관리자는 SUPER_ADMIN 문서를 읽을 수 없다', async () => {
    const db = getAuth(env, IDS.admin);
    await assertFails(getDoc(doc(db, 'users', IDS.superAdmin)));
  });
});

// ─────────────────────────────────────────────────────
// U-READ: LIST
// ─────────────────────────────────────────────────────
describe('U-READ-LIST: users 목록 쿼리', () => {
  test('U-LIST-01 ✅ limit=1 쿼리는 비로그인도 가능 (중복 체크용)', async () => {
    const db = getAnonymous(env);
    await assertSucceeds(getDocs(query(collection(db, 'users'), limit(1))));
  });

  test('U-LIST-02 ✅ 슈퍼어드민은 limit 제한 없이 목록 조회 가능', async () => {
    const db = getAuth(env, IDS.superAdmin);
    await assertSucceeds(getDocs(query(collection(db, 'users'), limit(100))));
  });

  test('U-LIST-03 ❌ 일반 유저는 limit>1 목록 조회 불가', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(getDocs(query(collection(db, 'users'), limit(10))));
  });

  test('U-LIST-04 ❌ 사업장관리자는 limit>1 목록 조회 불가', async () => {
    const db = getAuth(env, IDS.admin);
    await assertFails(getDocs(query(collection(db, 'users'), limit(10))));
  });

  test('U-LIST-05 ❌ 비로그인 limit>1 불가', async () => {
    const db = getAnonymous(env);
    await assertFails(getDocs(query(collection(db, 'users'), limit(2))));
  });
});

// ─────────────────────────────────────────────────────
// U-CREATE: 계정 생성
// ─────────────────────────────────────────────────────
describe('U-CREATE: users 문서 생성 (회원가입)', () => {
  const newUid = 'uid-new-user';

  const safeData = {
    username: 'newuser',
    name: '새유저',
    email: 'new@test.com',
    phone: '01012345678',
  };

  test('U-CREATE-01 ✅ 본인 uid로 민감 필드 없이 생성 가능', async () => {
    const db = getAuth(env, newUid);
    await assertSucceeds(setDoc(doc(db, 'users', newUid), safeData));
  });

  test('U-CREATE-02 ❌ 비로그인 상태에서 생성 불가', async () => {
    const db = getAnonymous(env);
    await assertFails(setDoc(doc(db, 'users', newUid), safeData));
  });

  test('U-CREATE-03 ❌ 타인 uid 문서를 생성할 수 없다 (isOwner 체크)', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(setDoc(doc(db, 'users', newUid), safeData));
  });

  test('U-CREATE-04 ❌ role 필드를 포함한 생성 차단 (권한 상승 방지)', async () => {
    const db = getAuth(env, newUid);
    await assertFails(setDoc(doc(db, 'users', newUid), { ...safeData, role: 'SUPER_ADMIN' }));
  });

  test('U-CREATE-05 ✅ role=BUSINESS_ADMIN 포함 생성 허용 (사업장관리자 자기 등록 — AUTH-H1/M6 FIX)', async () => {
    // 이전 규칙은 role 키 자체를 차단했으나, UserModel.toMap()이 항상 role 필드를 포함해 전송하므로
    // 현재 규칙은 키 존재는 허용하되 SUPER_ADMIN 승격만 차단 (in ['USER', 'BUSINESS_ADMIN'])
    const db = getAuth(env, newUid);
    await assertSucceeds(setDoc(doc(db, 'users', newUid), { ...safeData, role: 'BUSINESS_ADMIN' }));
  });

  test('U-CREATE-06 ❌ isBlacklisted=true 포함 생성 차단 (초기값 false만 허용)', async () => {
    // isBlacklisted: false는 허용, true는 차단 (가입 즉시 블랙리스트 등재 우회 방지)
    const db = getAuth(env, newUid);
    await assertFails(setDoc(doc(db, 'users', newUid), { ...safeData, isBlacklisted: true }));
  });

  test('U-CREATE-07 ❌ ciHash 포함 생성 차단 (PASS 인증 우회 방지)', async () => {
    const db = getAuth(env, newUid);
    await assertFails(setDoc(doc(db, 'users', newUid), { ...safeData, ciHash: 'fakehash' }));
  });

  test('U-CREATE-08 ✅ accountStatus=active 포함 생성 허용 (한국인 가입), ❌ approved는 차단', async () => {
    // 'active'/'pending'은 허용 (한국인/외국인 가입), 그 외 값(approved 등)은 차단
    const db = getAuth(env, newUid);
    await assertSucceeds(setDoc(doc(db, 'users', newUid), { ...safeData, accountStatus: 'active' }));
    // approved는 슈퍼관리자 승인 우회 시도 → 차단
    const db2 = getAuth(env, newUid + '2');
    await assertFails(setDoc(doc(db2, 'users', newUid + '2'), { ...safeData, accountStatus: 'approved' }));
  });

  test('U-CREATE-09 ❌ sealBase64 포함 생성 차단 (계약서 위변조 방지)', async () => {
    const db = getAuth(env, newUid);
    await assertFails(setDoc(doc(db, 'users', newUid), { ...safeData, sealBase64: 'data:...' }));
  });

  test('U-CREATE-10 ✅ restrictedUntil=null 포함 생성 허용, ❌ 날짜값은 차단 (제재 우회 방지)', async () => {
    // null은 "미설정"이므로 허용 (UserModel.toMap()이 null로 전송), 실제 날짜값(제재 기간)은 차단
    const db = getAuth(env, newUid);
    await assertSucceeds(setDoc(doc(db, 'users', newUid), { ...safeData, restrictedUntil: null }));
    // 가입 시 제재 날짜 설정은 CF Admin SDK 전용 → 차단
    const db2 = getAuth(env, newUid + 'r');
    await assertFails(setDoc(doc(db2, 'users', newUid + 'r'), {
      ...safeData, restrictedUntil: new Date(Date.now() + 86400000),
    }));
  });

  test('U-CREATE-11 ❌ subAdminOf 포함 생성 차단', async () => {
    const db = getAuth(env, newUid);
    await assertFails(setDoc(doc(db, 'users', newUid), { ...safeData, subAdminOf: IDS.business }));
  });

  test('U-CREATE-12 ❌ trustScore 포함 생성 차단', async () => {
    const db = getAuth(env, newUid);
    await assertFails(setDoc(doc(db, 'users', newUid), { ...safeData, trustScore: 100 }));
  });

  // SEC-102: foreignIdNumber(외국인 등록번호)가 있으면 accountStatus=pending만 허용
  test('U-CREATE-13 ❌ foreignIdNumber + accountStatus=active 조합 차단 (SEC-102)', async () => {
    const db = getAuth(env, newUid);
    await assertFails(setDoc(doc(db, 'users', newUid), {
      ...safeData,
      foreignIdNumber: 'F123456',
      accountStatus: 'active',  // pending만 허용 — 외국인 신원 검증 전 승인 우회 차단
    }));
  });

  // SEC-105: isDummy=true는 관리자 경로로만 생성 가능 — 일반 가입 경로 차단
  test('U-CREATE-14 ❌ isDummy=true 포함 생성 차단 (SEC-105)', async () => {
    const db = getAuth(env, newUid);
    await assertFails(setDoc(doc(db, 'users', newUid), {
      ...safeData,
      isDummy: true,  // CF Admin SDK 전용 — 일반 가입 경로에서 차단
    }));
  });

  // SEC-102 회귀: Dart UserModel.toMap()은 한국인도 foreignIdNumber:null 키를 항상 포함
  // !('foreignIdNumber' in data) 조건 대신 get('foreignIdNumber', null)==null 로 수정 검증
  test('U-CREATE-15 ✅ 한국인 가입 시 foreignIdNumber:null 포함해도 생성 가능 (SEC-102 회귀)', async () => {
    const db = getAuth(env, newUid);
    await assertSucceeds(setDoc(doc(db, 'users', newUid), {
      ...safeData,
      foreignIdNumber: null,   // Dart toMap()이 항상 포함 — 한국인은 null
      accountStatus: 'active', // 한국인은 active로 가입 가능
    }));
  });

  test('U-CREATE-16 ❌ foreignIdNumber 실제 값 + accountStatus=active 차단 (SEC-102)', async () => {
    const db = getAuth(env, newUid);
    await assertFails(setDoc(doc(db, 'users', newUid), {
      ...safeData,
      foreignIdNumber: 'ENCRYPTED_VALUE',  // 실제 외국인 등록번호
      accountStatus: 'active',             // 외국인은 pending만 허용
    }));
  });
});

// ─────────────────────────────────────────────────────
// U-UPDATE: 본인 문서 수정
// ─────────────────────────────────────────────────────
describe('U-UPDATE: users 문서 수정', () => {
  test('U-UPDATE-01 ✅ 본인은 일반 필드(name, phone 등)를 수정할 수 있다', async () => {
    const db = getAuth(env, IDS.user);
    await assertSucceeds(updateDoc(doc(db, 'users', IDS.user), { name: '수정됨', phone: '01099999999' }));
  });

  test('U-UPDATE-02 ✅ 슈퍼어드민은 모든 필드를 수정할 수 있다', async () => {
    const db = getAuth(env, IDS.superAdmin);
    await assertSucceeds(updateDoc(doc(db, 'users', IDS.user), { role: 'BUSINESS_ADMIN' }));
  });

  test('U-UPDATE-03 ❌ 비로그인은 수정 불가', async () => {
    const db = getAnonymous(env);
    await assertFails(updateDoc(doc(db, 'users', IDS.user), { name: '해킹' }));
  });

  test('U-UPDATE-04 ❌ 본인이 role을 변경할 수 없다 (권한 상승 차단)', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(updateDoc(doc(db, 'users', IDS.user), { role: 'BUSINESS_ADMIN' }));
  });

  test('U-UPDATE-05 ❌ 블랙리스트 유저가 isBlacklisted를 false로 자체 해제 불가', async () => {
    // isBlacklisted=true로 시드 → false로 바꾸는 실제 공격 시나리오
    // diff()는 값이 변경될 때만 affectedKeys 포함 — false→false는 diff 없음(설계상 정상)
    await seedUser(env, IDS.user, {
      role: 'USER', username: 'user1', name: '유저1', email: 'user@test.com',
      isBlacklisted: true,  // 실제 차단 상태로 시드
    });
    const db = getAuth(env, IDS.user);
    await assertFails(updateDoc(doc(db, 'users', IDS.user), { isBlacklisted: false }));
  });

  test('U-UPDATE-06 ❌ 본인이 noShowCount를 수정할 수 없다', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(updateDoc(doc(db, 'users', IDS.user), { noShowCount: 0 }));
  });

  test('U-UPDATE-07 ❌ 본인이 trustScore를 수정할 수 없다', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(updateDoc(doc(db, 'users', IDS.user), { trustScore: 100 }));
  });

  test('U-UPDATE-08 ❌ 본인이 restrictedUntil을 삭제해 제재를 우회할 수 없다', async () => {
    await seedUser(env, IDS.user, {
      role: 'USER', username: 'user1', name: '유저1', email: 'user@test.com',
      isBlacklisted: false,
      restrictedUntil: new Date(Date.now() + 86400000),
    });
    const db = getAuth(env, IDS.user);
    await assertFails(updateDoc(doc(db, 'users', IDS.user), { restrictedUntil: null }));
  });

  test('U-UPDATE-09 ❌ 본인이 businessId를 변경할 수 없다 (소속 교차검증 우회 방지)', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(updateDoc(doc(db, 'users', IDS.user), { businessId: IDS.business }));
  });

  test('U-UPDATE-10 ❌ 본인이 sealBase64를 변경할 수 없다 (계약서 위변조 방지)', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(updateDoc(doc(db, 'users', IDS.user), { sealBase64: 'data:fake' }));
  });

  test('U-UPDATE-11 ❌ 본인이 accountStatus를 변경할 수 없다 (외국인 승인 우회 방지)', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(updateDoc(doc(db, 'users', IDS.user), { accountStatus: 'active' }));
  });

  test('U-UPDATE-12 ❌ 일반 유저는 타인 문서를 수정할 수 없다', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(updateDoc(doc(db, 'users', IDS.user2), { name: '수정시도' }));
  });

  test('U-UPDATE-13 ❌ 사업장관리자가 일반 유저 문서의 role을 변경할 수 없다', async () => {
    const db = getAuth(env, IDS.admin);
    await assertFails(updateDoc(doc(db, 'users', IDS.user), { role: 'BUSINESS_ADMIN' }));
  });

  test('U-UPDATE-14 ✅ 사업장관리자는 자기 사업장 서브어드민의 subAdminOf를 제거할 수 있다', async () => {
    const db = getAuth(env, IDS.admin);
    // 모듈식 SDK v9+: deleteField() 사용 (FieldValue.delete() 아님)
    await assertSucceeds(updateDoc(doc(db, 'users', IDS.subAdmin), {
      subAdminOf: deleteField(),
    }));
  });

  test('U-UPDATE-15 ❌ 사업장관리자는 다른 사업장 서브어드민의 subAdminOf를 제거할 수 없다', async () => {
    await seedUser(env, 'uid-sub2', {
      role: 'USER', subAdminOf: IDS.business2, username: 'sub2', name: '서브2', email: 'sub2@test.com', isBlacklisted: false,
    });
    const db = getAuth(env, IDS.admin);
    await assertFails(updateDoc(doc(db, 'users', 'uid-sub2'), {
      subAdminOf: deleteField(),
    }));
  });

  // ─── [BIZ-CREATE-FIX] 첫 사업장 등록 관련 규칙 검증 ──────────────────
  // [아키텍처 변경] BUSINESS_ADMIN은 businessId 단일 필드 미사용 → managedBusinessIds 배열만 사용
  test('U-UPDATE-16 ✅ BUSINESS_ADMIN이 첫 사업장 등록 시 managedBusinessIds만 업데이트 허용', async () => {
    await seedUser(env, 'uid-new-biz-admin', {
      role: 'BUSINESS_ADMIN', username: 'newbizadmin', name: '신규관리자',
      email: 'nba@test.com', isBlacklisted: false,
    });
    const db = getAuth(env, 'uid-new-biz-admin');
    await assertSucceeds(updateDoc(doc(db, 'users', 'uid-new-biz-admin'), {
      managedBusinessIds: ['biz-first'],
    }));
  });

  test('U-UPDATE-16b ❌ BUSINESS_ADMIN은 businessId 단일 필드를 직접 변경할 수 없다', async () => {
    await seedUser(env, 'uid-new-biz-admin2', {
      role: 'BUSINESS_ADMIN', username: 'newbizadmin2', name: '신규관리자2',
      email: 'nba2@test.com', isBlacklisted: false,
    });
    const db = getAuth(env, 'uid-new-biz-admin2');
    await assertFails(updateDoc(doc(db, 'users', 'uid-new-biz-admin2'), {
      businessId: 'biz-first',
    }));
  });

  test('U-UPDATE-17 ✅ BUSINESS_ADMIN이 두 번째 사업장 추가 시 managedBusinessIds만 업데이트 허용', async () => {
    await seedUser(env, 'uid-admin-multi', {
      role: 'BUSINESS_ADMIN', managedBusinessIds: ['biz-first'],
      username: 'multiadmin', name: '멀티관리자', email: 'ma@test.com', isBlacklisted: false,
    });
    const db = getAuth(env, 'uid-admin-multi');
    await assertSucceeds(updateDoc(doc(db, 'users', 'uid-admin-multi'), {
      managedBusinessIds: ['biz-first', 'biz-second'],
    }));
  });

  test('U-UPDATE-18 ❌ BUSINESS_ADMIN이 businessId 이미 설정된 경우 변경 차단 (1회성 보호)', async () => {
    await seedUser(env, 'uid-admin-existing-biz', {
      role: 'BUSINESS_ADMIN', businessId: 'biz-existing',
      username: 'existadmin', name: '기존관리자', email: 'ea@test.com', isBlacklisted: false,
    });
    const db = getAuth(env, 'uid-admin-existing-biz');
    // businessId가 이미 null이 아니므로 새 규칙 조건 불충족 → 기존 차단 규칙 적용
    await assertFails(updateDoc(doc(db, 'users', 'uid-admin-existing-biz'), {
      businessId: 'biz-other',
    }));
  });

  // SEC-107: CF 전용 통계 필드 — 클라이언트 직접 위조 차단
  test('U-UPDATE-19 ❌ 본인이 averageRating을 직접 위조할 수 없다 (SEC-107)', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(updateDoc(doc(db, 'users', IDS.user), { averageRating: 5.0 }));
  });

  test('U-UPDATE-20 ❌ 본인이 reviewCount를 직접 위조할 수 없다 (SEC-107)', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(updateDoc(doc(db, 'users', IDS.user), { reviewCount: 9999 }));
  });

  test('U-UPDATE-21 ❌ 본인이 rehireRate를 직접 위조할 수 없다 (SEC-107)', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(updateDoc(doc(db, 'users', IDS.user), { rehireRate: 1.0 }));
  });

  // SEC-109: CF resetPasswordWithCode 전용 비밀번호 이력 — 클라이언트 직접 삭제 차단
  test('U-UPDATE-22 ❌ 본인이 passwordHistory를 직접 삭제해 재사용 이력 우회 불가 (SEC-109)', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(updateDoc(doc(db, 'users', IDS.user), { passwordHistory: [] }));
  });
});

// ─────────────────────────────────────────────────────
// U-DELETE: 계정 삭제
// ─────────────────────────────────────────────────────
describe('U-DELETE: users 문서 삭제', () => {
  test('U-DELETE-01 ✅ 슈퍼어드민은 아무 문서나 삭제할 수 있다', async () => {
    const db = getAuth(env, IDS.superAdmin);
    await assertSucceeds(deleteDoc(doc(db, 'users', IDS.user)));
  });

  test('U-DELETE-02 ✅ 관리자는 isDummy=true 문서를 삭제할 수 있다', async () => {
    await seedUser(env, 'uid-dummy', { role: 'USER', isDummy: true, username: 'dummy', name: '더미', email: 'd@test.com', isBlacklisted: false });
    const db = getAuth(env, IDS.admin);
    await assertSucceeds(deleteDoc(doc(db, 'users', 'uid-dummy')));
  });

  test('U-DELETE-03 ❌ 일반 유저는 삭제 불가', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(deleteDoc(doc(db, 'users', IDS.user)));
  });

  test('U-DELETE-04 ❌ 비로그인은 삭제 불가', async () => {
    const db = getAnonymous(env);
    await assertFails(deleteDoc(doc(db, 'users', IDS.user)));
  });

  test('U-DELETE-05 ❌ 관리자라도 isDummy=false 문서는 삭제 불가', async () => {
    const db = getAuth(env, IDS.admin);
    await assertFails(deleteDoc(doc(db, 'users', IDS.user)));
  });
});
