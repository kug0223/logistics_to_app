import {onSchedule} from "firebase-functions/v2/scheduler";
import {initializeApp} from "firebase-admin/app";
import {getFirestore, Timestamp, Firestore} from "firebase-admin/firestore";

initializeApp();
const db = getFirestore();

/**
 * 예약 공개 TO 자동 처리
 * 매 시간 정각에 실행 (06:00, 07:00, ...)
 */
export const publishScheduledTOs = onSchedule(
  {
    schedule: "0 * * * *",
    timeZone: "Asia/Seoul",
    region: "asia-northeast3",
  },
  async () => {
    console.log("🕐 예약 공개 TO 처리 시작...");

    try {
      const now = Timestamp.now();

      const snapshot = await db
        .collection("tos")
        .where("publishMode", "==", "scheduled")
        .where("isPublished", "==", false)
        .where("publishAt", "<=", now)
        .get();

      if (snapshot.empty) {
        console.log("✅ 공개할 TO 없음");
        return;
      }

      console.log(`📋 공개 대상 TO: ${snapshot.size}개`);

      const batch = db.batch();
      const affectedGroupIds = new Set<string>();

      snapshot.docs.forEach((doc) => {
        const data = doc.data();

        batch.update(doc.ref, {
          isPublished: true,
          publishedAt: now,
        });
        console.log(`  → ${doc.id} 공개 처리`);

        if (data.groupId) {
          affectedGroupIds.add(data.groupId);
        }
      });

      await batch.commit();
      console.log(`✅ ${snapshot.size}개 TO 공개 완료!`);

      for (const groupId of affectedGroupIds) {
        await updateGroupMasterPublishStatus(db, groupId);
      }
    } catch (error) {
      console.error("❌ 예약 공개 처리 실패:", error);
    }
  }
);

/**
 * 마감된 TO 자동 처리
 * 매 시간 정각에 실행
 */
export const closeExpiredTOs = onSchedule(
  {
    schedule: "0 * * * *",
    timeZone: "Asia/Seoul",
    region: "asia-northeast3",
  },
  async () => {
    console.log("🔒 마감 TO 처리 시작...");

    try {
      const now = Timestamp.now();

      const snapshot = await db
        .collection("tos")
        .where("applicationDeadline", "<=", now)
        .where("status", "==", "ACTIVE")
        .get();

      if (snapshot.empty) {
        console.log("✅ 처리할 TO 없음");
        return;
      }

      const tosToClose = snapshot.docs.filter((doc) => {
        const data = doc.data();
        return !data.isManualClosed;
      });

      if (tosToClose.length === 0) {
        console.log("✅ 새로 마감할 TO 없음");
        return;
      }

      console.log(`📋 마감 대상 TO: ${tosToClose.length}개`);

      const batch = db.batch();
      const affectedGroupIds = new Set<string>();

      tosToClose.forEach((doc) => {
        const data = doc.data();

        batch.update(doc.ref, {
          isClosed: true,
          closedAt: now,
          closedReason: "TIME_EXPIRED",
          status: "CLOSED",
          statusUpdatedAt: now,
        });
        console.log(`  → ${doc.id} 마감 처리`);

        if (data.groupId) {
          affectedGroupIds.add(data.groupId);
        }
      });

      await batch.commit();
      console.log(`✅ ${tosToClose.length}개 TO 마감 완료!`);

      for (const groupId of affectedGroupIds) {
        await updateGroupMasterCloseStatus(db, groupId);
      }
    } catch (error) {
      console.error("❌ 마감 처리 실패:", error);
    }
  }
);

/**
 * 그룹 마스터 공개 상태 업데이트
 * - 그룹 내 하나라도 공개되면 마스터도 공개
 * @param {Firestore} firestore - Firestore 인스턴스
 * @param {string} groupId - 그룹 ID
 */
async function updateGroupMasterPublishStatus(
  firestore: Firestore,
  groupId: string
): Promise<void> {
  try {
    const groupSnapshot = await firestore
      .collection("tos")
      .where("groupId", "==", groupId)
      .get();

    if (groupSnapshot.empty) return;

    const hasPublished = groupSnapshot.docs.some(
      (doc) => doc.data().isPublished === true
    );

    const masterDoc = groupSnapshot.docs.find(
      (doc) => doc.data().isGroupMaster === true
    );

    if (masterDoc && hasPublished && !masterDoc.data().isPublished) {
      await masterDoc.ref.update({isPublished: true});
      console.log(`  ✓ 그룹 마스터 공개: ${masterDoc.id}`);
    }
  } catch (error) {
    console.error(`❌ 그룹 마스터 공개 업데이트 실패 (${groupId}):`, error);
  }
}

/**
 * 그룹 마스터 마감 상태 업데이트
 * - 그룹 내 모든 TO가 마감되면 마스터도 마감
 * - 하나라도 ACTIVE면 마스터는 ACTIVE 유지
 * @param {Firestore} firestore - Firestore 인스턴스
 * @param {string} groupId - 그룹 ID
 */
async function updateGroupMasterCloseStatus(
  firestore: Firestore,
  groupId: string
): Promise<void> {
  try {
    const groupSnapshot = await firestore
      .collection("tos")
      .where("groupId", "==", groupId)
      .get();

    if (groupSnapshot.empty) return;

    const hasActiveTO = groupSnapshot.docs.some((doc) => {
      const data = doc.data();
      return !data.isGroupMaster && data.status === "ACTIVE";
    });

    const masterDoc = groupSnapshot.docs.find(
      (doc) => doc.data().isGroupMaster === true
    );

    if (!masterDoc) {
      console.log(`  ⚠️ 그룹 마스터 없음: ${groupId}`);
      return;
    }

    const masterData = masterDoc.data();

    if (masterData.isManualClosed) {
      return;
    }

    if (hasActiveTO) {
      if (masterData.status !== "ACTIVE") {
        await masterDoc.ref.update({
          status: "ACTIVE",
          statusUpdatedAt: Timestamp.now(),
        });
        console.log(`  ✓ 그룹 마스터 ACTIVE 유지: ${masterDoc.id}`);
      }
    } else {
      if (masterData.status !== "CLOSED") {
        await masterDoc.ref.update({
          status: "CLOSED",
          isClosed: true,
          closedAt: Timestamp.now(),
          closedReason: "ALL_CHILDREN_CLOSED",
          statusUpdatedAt: Timestamp.now(),
        });
        console.log(`  ✓ 그룹 마스터 마감: ${masterDoc.id}`);
      }
    }
  } catch (error) {
    console.error(`❌ 그룹 마스터 마감 업데이트 실패 (${groupId}):`, error);
  }
}
