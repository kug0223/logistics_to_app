import {onSchedule} from "firebase-functions/v2/scheduler";
import {initializeApp} from "firebase-admin/app";
import {getFirestore, Timestamp} from "firebase-admin/firestore";

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

      snapshot.docs.forEach((doc) => {
        batch.update(doc.ref, {
          isPublished: true,
          publishedAt: now,
        });
        console.log(`  → ${doc.id} 공개 처리`);
      });

      await batch.commit();

      console.log(`✅ ${snapshot.size}개 TO 공개 완료!`);
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
        .get();

      if (snapshot.empty) {
        console.log("✅ 처리할 TO 없음");
        return;
      }

      const tosToClose = snapshot.docs.filter((doc) => {
        const data = doc.data();
        return !data.isManualClosed && !data.isClosed;
      });

      if (tosToClose.length === 0) {
        console.log("✅ 새로 마감할 TO 없음");
        return;
      }

      console.log(`📋 마감 대상 TO: ${tosToClose.length}개`);

      const batch = db.batch();

      tosToClose.forEach((doc) => {
        batch.update(doc.ref, {
          isClosed: true,
          closedAt: now,
          closedReason: "TIME_EXPIRED",
        });
        console.log(`  → ${doc.id} 마감 처리`);
      });

      await batch.commit();

      console.log(`✅ ${tosToClose.length}개 TO 마감 완료!`);
    } catch (error) {
      console.error("❌ 마감 처리 실패:", error);
    }
  }
);
