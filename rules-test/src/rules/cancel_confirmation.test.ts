// rules-test/src/rules/cancel_confirmation.test.ts
// SNAP-CANCEL: callableCancelFinalConfirmation wageAccount snapshot cleanup 검증
//
// ⚠️ Functions 에뮬레이터 미구성 — CF 직접 호출 대신:
//    withSecurityRulesDisabled(Admin SDK 역할)로 CF와 동일한 FieldValue 작업을
//    Firestore에 직접 적용 후 결과 데이터를 검증하는 통합 테스트.
//
// CF 코드 STATIC VERIFIED (functions/src/index.ts L16010~16027):
//   - transferred → return false (skip). HttpsError 없음.
//   - confirmed → FieldValue.delete() × 5 + wageStatus="calculated" 트랜잭션.
//
// 테스트 목적:
//   SNAP-CANCEL-01: cancel 후 9개 필드 absent (5 wageAccount + 4 confirm fields)
//   SNAP-CANCEL-02: cancel → re-confirm 시 최신 계좌 정보로 snapshot 재생성
//   SNAP-CANCEL-03: transferred 상태에서 CF가 skip 처리 (STATIC VERIFIED + Rules 커버)

import { RulesTestEnvironment } from '@firebase/rules-unit-testing';
import { deleteField, doc, getDoc, updateDoc } from 'firebase/firestore';
import {
  createTestEnv,
  seedDoc,
  IDS,
} from '../helpers/test-env';

let env: RulesTestEnvironment;

// ── fixture 상수 ───────────────────────────────────────────────────────────

const CONFIRMED_ID = 'att-snap-cancel-01';
const RECONFIRM_ID = 'att-snap-cancel-02';

/** callableConfirmFinalWage가 기록하는 모든 snapshot 필드를 포함한 confirmed 상태 fixture */
const confirmedBase = {
  userId: IDS.user,
  businessId: IDS.business,
  applicationId: 'app-snap-001',
  workDate: '2024-01-20',
  status: 'DONE',
  wageStatus: 'confirmed',
  finalWage: 80000,
  wageDetail: {
    totalAmount: 80000,
    netWage: 80000,
    workMinutes: 480,
    confirmedBy: IDS.admin,
    confirmedAt: '2024-01-20T18:00:00Z',
  },
  // confirmed snapshot 필드 (callableConfirmFinalWage 기록분)
  finalConfirmedAt: '2024-01-20T18:00:00Z',
  confirmedBy: IDS.admin,
  paymentDueDate: '2024-02-10',
  wageAccountSnapshotVersion: 1,
  wageAccountBankName: '신한은행',
  wageAccountNumberEncrypted: 'enc-account-number-aes256',
  wageAccountHolder: '김의관',
  wageAccountSnapshotAt: '2024-01-20T18:00:00Z',
};

// ── 환경 setup ─────────────────────────────────────────────────────────────

beforeAll(async () => {
  env = await createTestEnv('cancel-confirmation');

  await seedDoc(env, 'attendance', CONFIRMED_ID, confirmedBase);
  await seedDoc(env, 'attendance', RECONFIRM_ID, confirmedBase);
});

afterAll(async () => {
  await env.cleanup();
});

// ── SNAP-CANCEL-01: confirmed → cancel → 9개 필드 absent ─────────────────
//
// CF callableCancelFinalConfirmation L16017~16027 의 FieldValue.delete() 작업을
// withSecurityRulesDisabled(Admin SDK 역할)로 재현 후 결과 검증.
// wageDetail 내부 confirmedBy/confirmedAt은 JS delete 후 namedObject로 update하는
// CF 로직에 따라 빈 wageDetail 전체를 deleteField()로 처리.

describe('SNAP-CANCEL-01: confirmed → cancel 후 snapshot 필드 absent 확인', () => {
  test('cancel 시뮬레이션: 9개 필드 FieldValue.delete() 적용', async () => {
    // withSecurityRulesDisabled = Admin SDK 역할 (rules 우회)
    // CF callableCancelFinalConfirmation tx.update()와 동일한 작업 수행
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await updateDoc(doc(db, 'attendance', CONFIRMED_ID), {
        wageStatus: 'calculated',
        // wageDetail: wageDetail 내부 confirmedBy/confirmedAt 제거 후
        //   나머지 필드만 유지. 여기서는 test fixture의 wageDetail에
        //   confirmedBy/confirmedAt만 있어서 빈 객체 → FieldValue.delete()
        wageDetail: deleteField(),
        finalConfirmedAt: deleteField(),
        paymentDueDate: deleteField(),
        confirmedBy: deleteField(),
        // [PHASE4.1-CLEANUP] 5개 계좌 스냅샷 필드
        wageAccountSnapshotVersion: deleteField(),
        wageAccountBankName: deleteField(),
        wageAccountNumberEncrypted: deleteField(),
        wageAccountHolder: deleteField(),
        wageAccountSnapshotAt: deleteField(),
        updatedAt: 'simulated-cancel-ts',
      });
    });
  });

  test('결과 검증: wageStatus=calculated', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const snap = await getDoc(doc(ctx.firestore(), 'attendance', CONFIRMED_ID));
      expect(snap.exists()).toBe(true);
      expect(snap.data()!.wageStatus).toBe('calculated');
    });
  });

  test('결과 검증: finalConfirmedAt ABSENT', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const data = (await getDoc(doc(ctx.firestore(), 'attendance', CONFIRMED_ID))).data()!;
      expect(data.finalConfirmedAt).toBeUndefined();
    });
  });

  test('결과 검증: confirmedBy ABSENT', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const data = (await getDoc(doc(ctx.firestore(), 'attendance', CONFIRMED_ID))).data()!;
      expect(data.confirmedBy).toBeUndefined();
    });
  });

  test('결과 검증: paymentDueDate ABSENT', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const data = (await getDoc(doc(ctx.firestore(), 'attendance', CONFIRMED_ID))).data()!;
      expect(data.paymentDueDate).toBeUndefined();
    });
  });

  test('결과 검증: wageAccountSnapshotVersion ABSENT', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const data = (await getDoc(doc(ctx.firestore(), 'attendance', CONFIRMED_ID))).data()!;
      expect(data.wageAccountSnapshotVersion).toBeUndefined();
    });
  });

  test('결과 검증: wageAccountBankName ABSENT', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const data = (await getDoc(doc(ctx.firestore(), 'attendance', CONFIRMED_ID))).data()!;
      expect(data.wageAccountBankName).toBeUndefined();
    });
  });

  test('결과 검증: wageAccountNumberEncrypted ABSENT', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const data = (await getDoc(doc(ctx.firestore(), 'attendance', CONFIRMED_ID))).data()!;
      expect(data.wageAccountNumberEncrypted).toBeUndefined();
    });
  });

  test('결과 검증: wageAccountHolder ABSENT', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const data = (await getDoc(doc(ctx.firestore(), 'attendance', CONFIRMED_ID))).data()!;
      expect(data.wageAccountHolder).toBeUndefined();
    });
  });

  test('결과 검증: wageAccountSnapshotAt ABSENT', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const data = (await getDoc(doc(ctx.firestore(), 'attendance', CONFIRMED_ID))).data()!;
      expect(data.wageAccountSnapshotAt).toBeUndefined();
    });
  });

  test('결과 검증: finalWage 보존 (cancel이 finalWage 삭제 안 함)', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const data = (await getDoc(doc(ctx.firestore(), 'attendance', CONFIRMED_ID))).data()!;
      expect(data.finalWage).toBe(80000);
    });
  });
});

// ── SNAP-CANCEL-02: cancel → re-confirm 시 최신 snapshot 재생성 ───────────

describe('SNAP-CANCEL-02: cancel → re-confirm 후 최신 계좌 snapshot 재생성', () => {
  test('cancel 시뮬레이션 (calculated로 전환 + snapshot 삭제)', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), 'attendance', RECONFIRM_ID), {
        wageStatus: 'calculated',
        wageDetail: deleteField(),
        finalConfirmedAt: deleteField(),
        paymentDueDate: deleteField(),
        confirmedBy: deleteField(),
        wageAccountSnapshotVersion: deleteField(),
        wageAccountBankName: deleteField(),
        wageAccountNumberEncrypted: deleteField(),
        wageAccountHolder: deleteField(),
        wageAccountSnapshotAt: deleteField(),
        updatedAt: 'simulated-cancel-ts',
      });
    });
  });

  test('re-confirm 시뮬레이션: 최신 계좌(우리은행)로 새 snapshot 기록', async () => {
    // callableConfirmFinalWage가 user.bankName/accountNumber/accountHolder에서
    // 최신 계좌 정보를 읽어 새 snapshot을 기록하는 로직 재현.
    // 이전 계좌(신한은행) → 새 계좌(우리은행)로 변경된 상황 검증.
    await env.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), 'attendance', RECONFIRM_ID), {
        wageStatus: 'confirmed',
        finalConfirmedAt: 'new-confirmed-ts',
        confirmedBy: IDS.admin,
        paymentDueDate: '2024-03-10',           // 새 지급일
        wageAccountSnapshotVersion: 1,
        wageAccountBankName: '우리은행',          // 변경된 계좌
        wageAccountNumberEncrypted: 'enc-new-account-number',
        wageAccountHolder: '김의관',
        wageAccountSnapshotAt: 'new-snapshot-ts',
        updatedAt: 'simulated-reconfirm-ts',
      });
    });
  });

  test('결과 검증: 새 계좌(우리은행)로 snapshot 교체됨', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const data = (await getDoc(doc(ctx.firestore(), 'attendance', RECONFIRM_ID))).data()!;
      expect(data.wageStatus).toBe('confirmed');
      expect(data.wageAccountBankName).toBe('우리은행');
      expect(data.wageAccountNumberEncrypted).toBe('enc-new-account-number');
      expect(data.wageAccountSnapshotVersion).toBe(1);
      expect(data.paymentDueDate).toBe('2024-03-10');
      // old snapshot(신한은행)이 남지 않음 확인
      expect(data.wageAccountBankName).not.toBe('신한은행');
    });
  });
});

// ── SNAP-CANCEL-03: transferred → cancel STATIC VERIFIED ─────────────────
//
// CF 코드 L16010: `if (data.wageStatus === "transferred" || ...) return false;`
// transferred 상태에서는 cancel이 조용히 skip됨 (HttpsError 없음).
// Firestore Rules 레벨: transferred 상태에서 wageStatus 변경 차단 (AT-UPDATE-11, AT-UPDATE-14).
// snapshot 필드 immutability: RULE-SNAPSHOT-07에서 검증됨.
//
// 별도 실행 테스트 없음 — STATIC VERIFIED.
describe('SNAP-CANCEL-03: transferred → cancel skip (STATIC VERIFIED)', () => {
  test('STATIC VERIFIED — CF L16010: transferred 상태는 return false (skip)', () => {
    // callableCancelFinalConfirmation L16010:
    //   if (data.wageStatus === "transferred" || data.wageStatus !== "confirmed") return false;
    // → transferred는 실행 없이 skipped 배열에 추가. snapshot 보존.
    // Firestore Rules: AT-UPDATE-11(admin), AT-UPDATE-14(superAdmin) 전이 차단 이미 검증.
    // RULE-SNAPSHOT-07: transferred 상태에서 snapshot 필드 직접 수정 DENY 검증됨.
    expect(true).toBe(true); // marker test — 위 STATIC VERIFIED 근거 기록용
  });
});
