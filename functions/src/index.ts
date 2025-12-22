import {onSchedule} from "firebase-functions/v2/scheduler";
import {initializeApp} from "firebase-admin/app";
import {getFirestore, Timestamp, Firestore} from "firebase-admin/firestore";

initializeApp();
const db = getFirestore();

// ═══════════════════════════════════════════════════════════
// 🔥 스케줄러 1: 주기적 작업 (10분마다)
// - 예약 공개 처리
// - WorkDetail 마감 처리
// - TO 마감 처리
// ═══════════════════════════════════════════════════════════

export const periodicTasks = onSchedule(
  {
    schedule: "*/10 * * * *",
    timeZone: "Asia/Seoul",
    region: "asia-northeast3",
  },
  async () => {
    console.log("🚀 [주기적 작업] 시작...");
    const now = Timestamp.now();

    try {
      // 1️⃣ 예약 공개 처리
      await processScheduledPublish(now);

      // 2️⃣ WorkDetail 마감 처리
      await processWorkDetailExpiry(now);

      // 3️⃣ TO 마감 처리
      await processTOExpiry(now);

      console.log("✅ [주기적 작업] 완료!");
    } catch (error) {
      console.error("❌ [주기적 작업] 실패:", error);
    }
  }
);

// ═══════════════════════════════════════════════════════════
// 🔥 스케줄러 2: 일일 정합성 검사 (매일 새벽 3시)
// ═══════════════════════════════════════════════════════════

export const dailyIntegrityCheck = onSchedule(
  {
    schedule: "0 3 * * *",
    timeZone: "Asia/Seoul",
    region: "asia-northeast3",
  },
  async () => {
    console.log("🔍 [정합성 검사] 시작...");

    try {
      const now = Timestamp.now();
      let fixedCount = 0;

      // 1. 마감되어야 하는데 ACTIVE인 TO 수정
      const activeTOs = await db
        .collection("tos")
        .where("status", "==", "ACTIVE")
        .get();

      for (const toDoc of activeTOs.docs) {
        const toData = toDoc.data();

        if (toData.isManualClosed === true) continue;

        const deadline = toData.applicationDeadline as Timestamp | null;
        if (deadline && deadline.toMillis() <= now.toMillis()) {
          await toDoc.ref.update({
            status: "CLOSED",
            closedAt: now,
            closedReason: "INTEGRITY_CHECK",
            statusUpdatedAt: now,
          });
          fixedCount++;
          console.log(`  → TO ${toDoc.id} 상태 수정`);
        }
      }

      // 2. 모든 그룹 마스터 상태 재동기화
      const masterTOs = await db
        .collection("tos")
        .where("isGroupMaster", "==", true)
        .get();

      const processedGroupIds = new Set<string>();

      for (const masterDoc of masterTOs.docs) {
        const groupId = masterDoc.data().groupId as string | undefined;
        if (groupId && !processedGroupIds.has(groupId)) {
          await syncGroupMasterStatus(db, groupId);
          processedGroupIds.add(groupId);
        }
      }

      console.log(
        `✅ [정합성 검사] 완료: ${fixedCount}개 수정, ` +
        `${processedGroupIds.size}개 그룹 동기화`
      );
    } catch (error) {
      console.error("❌ [정합성 검사] 실패:", error);
    }
  }
);

// ═══════════════════════════════════════════════════════════
// 📦 작업 처리 함수들
// ═══════════════════════════════════════════════════════════

/**
 * 1️⃣ 예약 공개 TO 처리
 * @param {Timestamp} now - 현재 시간
 */
async function processScheduledPublish(now: Timestamp): Promise<void> {
  console.log("  📢 [예약공개] 처리 중...");

  const snapshot = await db
    .collection("tos")
    .where("publishMode", "==", "scheduled")
    .where("isPublished", "==", false)
    .where("publishAt", "<=", now)
    .get();

  if (snapshot.empty) {
    console.log("  ✅ [예약공개] 공개할 TO 없음");
    return;
  }

  console.log(`  📋 [예약공개] 대상 TO: ${snapshot.size}개`);

  const batch = db.batch();
  const affectedGroupIds = new Set<string>();

  snapshot.docs.forEach((doc) => {
    const data = doc.data();

    batch.update(doc.ref, {
      isPublished: true,
      publishedAt: now,
      status: "ACTIVE",
      statusUpdatedAt: now,
    });
    console.log(`    → ${doc.id} 공개 처리`);

    if (data.groupId) {
      affectedGroupIds.add(data.groupId);
    }
  });

  await batch.commit();
  console.log(`  ✅ [예약공개] ${snapshot.size}개 TO 공개 완료!`);

  // 그룹 마스터 상태 동기화
  for (const groupId of affectedGroupIds) {
    await syncGroupMasterStatus(db, groupId);
  }
}

/**
 * 2️⃣ WorkDetail 시간 마감 처리
 * @param {Timestamp} now - 현재 시간
 */
async function processWorkDetailExpiry(now: Timestamp): Promise<void> {
  console.log("  🔒 [WorkDetail 마감] 처리 중...");

  const tosSnapshot = await db
    .collection("tos")
    .where("status", "==", "ACTIVE")
    .get();

  if (tosSnapshot.empty) {
    console.log("  ✅ [WorkDetail 마감] 활성 TO 없음");
    return;
  }

  console.log(`  📋 [WorkDetail 마감] 활성 TO: ${tosSnapshot.size}개 검사`);

  let totalClosed = 0;
  const affectedTOIds = new Set<string>();
  const affectedGroupIds = new Set<string>();

  for (const toDoc of tosSnapshot.docs) {
    const toData = toDoc.data();
    const toId = toDoc.id;

    const workDetailsSnapshot = await db
      .collection("tos")
      .doc(toId)
      .collection("workDetails")
      .where("closedAt", "==", null)
      .get();

    if (workDetailsSnapshot.empty) continue;

    const batch = db.batch();
    let closedInThisTO = 0;

    for (const wdDoc of workDetailsSnapshot.docs) {
      const wdData = wdDoc.data();

      if (wdData.isEmergencyOpen === true) continue;

      const deadline = wdData.applicationDeadline as Timestamp | null;
      if (deadline && deadline.toMillis() <= now.toMillis()) {
        batch.update(wdDoc.ref, {
          closedAt: now,
          closedReason: "TIME_EXPIRED",
        });
        closedInThisTO++;
        console.log(`    → ${toId}/${wdDoc.id} WorkDetail 마감`);
      }
    }

    if (closedInThisTO > 0) {
      await batch.commit();
      totalClosed += closedInThisTO;
      affectedTOIds.add(toId);

      if (toData.groupId) {
        affectedGroupIds.add(toData.groupId);
      }
    }
  }

  console.log(`  ✅ [WorkDetail 마감] ${totalClosed}개 마감 완료`);

  // 영향받은 TO들의 status 동기화
  for (const toId of affectedTOIds) {
    await syncTOStatusFromWorkDetails(db, toId);
  }

  // 영향받은 그룹 마스터 동기화
  for (const groupId of affectedGroupIds) {
    await syncGroupMasterStatus(db, groupId);
  }
}

/**
 * 3️⃣ TO 시간 마감 처리
 * @param {Timestamp} now - 현재 시간
 */
async function processTOExpiry(now: Timestamp): Promise<void> {
  console.log("  🔒 [TO 마감] 처리 중...");

  const snapshot = await db
    .collection("tos")
    .where("status", "==", "ACTIVE")
    .where("applicationDeadline", "<=", now)
    .get();

  if (snapshot.empty) {
    console.log("  ✅ [TO 마감] 처리할 TO 없음");
    return;
  }

  const tosToClose = snapshot.docs.filter((doc) => {
    const data = doc.data();
    return !data.isManualClosed;
  });

  if (tosToClose.length === 0) {
    console.log("  ✅ [TO 마감] 새로 마감할 TO 없음");
    return;
  }

  console.log(`  📋 [TO 마감] 대상: ${tosToClose.length}개`);

  const batch = db.batch();
  const affectedGroupIds = new Set<string>();

  for (const doc of tosToClose) {
    const data = doc.data();

    batch.update(doc.ref, {
      status: "CLOSED",
      closedAt: now,
      closedReason: "TIME_EXPIRED",
      statusUpdatedAt: now,
    });

    console.log(`    → ${doc.id} TO 마감`);

    if (data.groupId) {
      affectedGroupIds.add(data.groupId);
    }

    // 해당 TO의 모든 WorkDetails도 마감
    const wdSnapshot = await db
      .collection("tos")
      .doc(doc.id)
      .collection("workDetails")
      .where("closedAt", "==", null)
      .get();

    for (const wdDoc of wdSnapshot.docs) {
      const wdData = wdDoc.data();
      if (wdData.isEmergencyOpen !== true) {
        batch.update(wdDoc.ref, {
          closedAt: now,
          closedReason: "PARENT_TO_CLOSED",
        });
      }
    }
  }

  await batch.commit();
  console.log(`  ✅ [TO 마감] ${tosToClose.length}개 완료!`);

  // 그룹 마스터 동기화
  for (const groupId of affectedGroupIds) {
    await syncGroupMasterStatus(db, groupId);
  }
}

// ═══════════════════════════════════════════════════════════
// 🔧 동기화 헬퍼 함수들
// ═══════════════════════════════════════════════════════════

/**
 * WorkDetail 상태 기반으로 TO status 동기화
 * @param {Firestore} firestore - Firestore 인스턴스
 * @param {string} toId - TO 문서 ID
 */
async function syncTOStatusFromWorkDetails(
  firestore: Firestore,
  toId: string
): Promise<void> {
  try {
    const wdSnapshot = await firestore
      .collection("tos")
      .doc(toId)
      .collection("workDetails")
      .get();

    if (wdSnapshot.empty) return;

    const hasOpenWorkDetail = wdSnapshot.docs.some((doc) => {
      const data = doc.data();
      if (data.isEmergencyOpen === true) return true;
      return data.closedAt == null;
    });

    const toDoc = await firestore.collection("tos").doc(toId).get();
    if (!toDoc.exists) return;

    const toData = toDoc.data();
    if (!toData) return;

    if (toData.isManualClosed === true) return;

    const currentStatus = toData.status;
    const newStatus = hasOpenWorkDetail ? "ACTIVE" : "CLOSED";

    if (currentStatus !== newStatus) {
      await firestore.collection("tos").doc(toId).update({
        status: newStatus,
        statusUpdatedAt: Timestamp.now(),
        ...(newStatus === "CLOSED" && {
          closedAt: Timestamp.now(),
          closedReason: "ALL_WORKDETAILS_CLOSED",
        }),
      });
      console.log(
        `    ✓ TO ${toId} status: ${currentStatus} → ${newStatus}`
      );
    }
  } catch (error) {
    console.error(`❌ TO status 동기화 실패 (${toId}):`, error);
  }
}

/**
 * 그룹 마스터 상태 동기화
 * @param {Firestore} firestore - Firestore 인스턴스
 * @param {string} groupId - 그룹 ID
 */
async function syncGroupMasterStatus(
  firestore: Firestore,
  groupId: string
): Promise<void> {
  try {
    const groupSnapshot = await firestore
      .collection("tos")
      .where("groupId", "==", groupId)
      .get();

    if (groupSnapshot.empty) return;

    const masterDoc = groupSnapshot.docs.find(
      (doc) => doc.data().isGroupMaster === true
    );

    if (!masterDoc) {
      console.log(`    ⚠️ 그룹 마스터 없음: ${groupId}`);
      return;
    }

    const masterData = masterDoc.data();

    if (masterData.isManualClosed === true) return;

    const hasActiveTO = groupSnapshot.docs.some((doc) => {
      const data = doc.data();
      return data.isGroupMaster !== true && data.status === "ACTIVE";
    });

    const allScheduled = groupSnapshot.docs
      .filter((doc) => doc.data().isGroupMaster !== true)
      .every((doc) => {
        const data = doc.data();
        return data.isPublished === false;
      });

    const currentStatus = masterData.status;
    let newStatus: string;

    if (hasActiveTO) {
      newStatus = "ACTIVE";
    } else if (allScheduled) {
      newStatus = "SCHEDULED";
    } else {
      newStatus = "CLOSED";
    }

    if (currentStatus !== newStatus) {
      const updateData: Record<string, unknown> = {
        status: newStatus,
        statusUpdatedAt: Timestamp.now(),
      };

      if (newStatus === "CLOSED") {
        updateData.closedAt = Timestamp.now();
        updateData.closedReason = "ALL_CHILDREN_CLOSED";
      }

      await masterDoc.ref.update(updateData);
      console.log(
        `    ✓ 그룹 마스터 ${masterDoc.id}: ${currentStatus} → ${newStatus}`
      );
    }
  } catch (error) {
    console.error(`❌ 그룹 마스터 동기화 실패 (${groupId}):`, error);
  }
}
