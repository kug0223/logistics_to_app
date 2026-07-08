// rules-test/src/rules/notifications.test.ts
// users/{userId}/notifications 서브컬렉션 (12개 시나리오)
import {
  RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  doc,
  getDoc,
  getDocs,
  collection,
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

const NOTIF_ID = 'notif-001';

beforeAll(async () => {
  env = await createTestEnv('notifications');
  await seedCommonFixtures(env);

  // 본인 알림 문서
  await seedDoc(env, `users/${IDS.user}/notifications`, NOTIF_ID, {
    title: '근무 확정 알림',
    body: '근무가 확정되었습니다.',
    deepLink: '/attendance',
    isRead: false,
    readAt: null,
    createdAt: '2024-01-15T09:00:00Z',
  });

  // 다른 유저 알림 문서
  await seedDoc(env, `users/${IDS.user2}/notifications`, 'notif-user2', {
    title: '타인 알림',
    body: '타인의 알림입니다.',
    isRead: false,
    readAt: null,
    createdAt: '2024-01-15T09:00:00Z',
  });
});

afterAll(async () => {
  await env.cleanup();
});

// ─── NOTIF-READ ──────────────────────────────────────────────────────

describe('NOTIF-READ: 알림 읽기 (본인만)', () => {
  test('NOTIF-READ-01 본인은 자신의 알림을 단건 조회할 수 있다', async () => {
    const db = getAuth(env, IDS.user);
    await assertSucceeds(getDoc(doc(db, `users/${IDS.user}/notifications`, NOTIF_ID)));
  });

  test('NOTIF-READ-02 본인은 자신의 알림 목록을 조회할 수 있다', async () => {
    const db = getAuth(env, IDS.user);
    await assertSucceeds(getDocs(collection(db, `users/${IDS.user}/notifications`)));
  });

  test('NOTIF-READ-03 타 사용자는 남의 알림을 읽을 수 없다', async () => {
    const db = getAuth(env, IDS.user2);
    await assertFails(getDoc(doc(db, `users/${IDS.user}/notifications`, NOTIF_ID)));
  });

  test('NOTIF-READ-04 관리자도 근무자 알림을 읽을 수 없다 (개인정보 보호)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(getDoc(doc(db, `users/${IDS.user}/notifications`, NOTIF_ID)));
  });

  test('NOTIF-READ-05 슈퍼어드민도 개인 알림을 읽을 수 없다', async () => {
    const db = getAuth(env, IDS.superAdmin, { role: 'SUPER_ADMIN' });
    await assertFails(getDoc(doc(db, `users/${IDS.user}/notifications`, NOTIF_ID)));
  });

  test('NOTIF-READ-06 미인증 사용자는 알림을 읽을 수 없다', async () => {
    const db = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, `users/${IDS.user}/notifications`, NOTIF_ID)));
  });
});

// ─── NOTIF-CREATE: CF Admin SDK 전용 ─────────────────────────────────

describe('NOTIF-CREATE: 클라이언트 직접 생성 완전 차단 (SEC-14)', () => {
  test('NOTIF-CREATE-01 본인도 자신의 알림을 직접 생성할 수 없다', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      setDoc(doc(db, `users/${IDS.user}/notifications`, 'notif-self-create'), {
        title: '자가 생성 알림',
        body: '허용되어선 안 됨',
        isRead: false,
        createdAt: '2024-01-15T09:00:00Z',
      }),
    );
  });

  test('NOTIF-CREATE-02 타인에게 임의 알림 발송 차단', async () => {
    // 악의적 사용자가 타인 경로에 알림 삽입 시도
    const db = getAuth(env, IDS.user);
    await assertFails(
      setDoc(doc(db, `users/${IDS.user2}/notifications`, 'notif-injected'), {
        title: '피싱 알림',
        body: '악성 링크를 클릭하세요',
        deepLink: 'http://evil.example.com',
        isRead: false,
        createdAt: '2024-01-15T09:00:00Z',
      }),
    );
  });

  test('NOTIF-CREATE-03 관리자도 근무자 알림을 직접 생성할 수 없다 (CF 전용)', async () => {
    const db = getAuth(env, IDS.admin, { businessId: IDS.business });
    await assertFails(
      setDoc(doc(db, `users/${IDS.user}/notifications`, 'notif-admin-create'), {
        title: '관리자 생성',
        body: '직접 생성 시도',
        isRead: false,
        createdAt: '2024-01-15T09:00:00Z',
      }),
    );
  });
});

// ─── NOTIF-UPDATE: isRead/readAt 필드만 허용 ─────────────────────────

describe('NOTIF-UPDATE: 읽음 처리 필드만 수정 허용 (SEC-14)', () => {
  test('NOTIF-UPDATE-01 본인은 isRead/readAt 필드만 수정할 수 있다', async () => {
    const db = getAuth(env, IDS.user);
    await assertSucceeds(
      updateDoc(doc(db, `users/${IDS.user}/notifications`, NOTIF_ID), {
        isRead: true,
        readAt: '2024-01-15T10:00:00Z',
      }),
    );
  });

  test('NOTIF-UPDATE-02 본인도 title 수정은 차단 (내용 변조 방지)', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      updateDoc(doc(db, `users/${IDS.user}/notifications`, NOTIF_ID), {
        title: '수정된 알림 제목',
      }),
    );
  });

  test('NOTIF-UPDATE-03 본인도 deepLink 수정은 차단 (피싱 링크 삽입 방지)', async () => {
    const db = getAuth(env, IDS.user);
    await assertFails(
      updateDoc(doc(db, `users/${IDS.user}/notifications`, NOTIF_ID), {
        deepLink: 'http://evil.example.com',
      }),
    );
  });

  test('NOTIF-UPDATE-04 타인은 알림 수정 차단', async () => {
    const db = getAuth(env, IDS.user2);
    await assertFails(
      updateDoc(doc(db, `users/${IDS.user}/notifications`, NOTIF_ID), {
        isRead: true,
        readAt: '2024-01-15T10:00:00Z',
      }),
    );
  });
});

// ─── NOTIF-DELETE ────────────────────────────────────────────────────

describe('NOTIF-DELETE: 알림 삭제 (본인만)', () => {
  test('NOTIF-DELETE-01 본인은 자신의 알림을 삭제할 수 있다', async () => {
    await seedDoc(env, `users/${IDS.user}/notifications`, 'notif-to-del', {
      title: '삭제예정', isRead: false,
    });
    const db = getAuth(env, IDS.user);
    await assertSucceeds(deleteDoc(doc(db, `users/${IDS.user}/notifications`, 'notif-to-del')));
  });

  test('NOTIF-DELETE-02 타인은 알림을 삭제할 수 없다', async () => {
    const db = getAuth(env, IDS.user2);
    await assertFails(deleteDoc(doc(db, `users/${IDS.user}/notifications`, NOTIF_ID)));
  });
});
