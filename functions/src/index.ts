import {onSchedule} from "firebase-functions/v2/scheduler";
import {initializeApp} from "firebase-admin/app";
import {getFirestore, Timestamp, Firestore} from "firebase-admin/firestore";
import * as admin from "firebase-admin";

initializeApp();
const db = getFirestore();

// ═══════════════════════════════════════════════════════════
// 🔥 통합 마스터 스케줄러 (10분마다 실행)
// ═══════════════════════════════════════════════════════════
// - Cloud Scheduler 1개만 사용 (비용 최적화)
// - 시간대별로 필요한 작업 분기 처리
// ═══════════════════════════════════════════════════════════

export const masterScheduler = onSchedule(
  {
    schedule: "*/10 * * * *",
    timeZone: "Asia/Seoul",
    region: "asia-northeast3",
  },
  async () => {
    const now = new Date();
    const hour = now.getHours();
    const minute = now.getMinutes();
    const timestamp = Timestamp.now();

    console.log(`🚀 [마스터 스케줄러] 시작: ${hour}시 ${minute}분`);

    try {
      // ═══════════════════════════════════════════════════════
      // ✅ 매 10분마다 실행
      // ═══════════════════════════════════════════════════════

      // 1️⃣ 예약 공개 처리
      await processScheduledPublish(timestamp);

      // 2️⃣ WorkDetail 마감 처리
      await processWorkDetailExpiry(timestamp);

      // 3️⃣ TO 마감 처리
      await processTOExpiry(timestamp);

      // ═══════════════════════════════════════════════════════
      // ✅ 저녁 8시에만 실행 (20:00 ~ 20:09)
      // ═══════════════════════════════════════════════════════
      if (hour === 20 && minute < 10) {
        console.log("📢 [리마인더] 내일 근무 알림 시작...");
        await sendWorkReminders(timestamp);
      }

      // ═══════════════════════════════════════════════════════
      // ✅ 새벽 3시에만 실행 (03:00 ~ 03:09)
      // ═══════════════════════════════════════════════════════
      if (hour === 3 && minute < 10) {
        console.log("🔍 [정합성 검사] 시작...");
        await runIntegrityCheck(timestamp);
      }

      console.log("✅ [마스터 스케줄러] 완료!");
    } catch (error) {
      console.error("❌ [마스터 스케줄러] 실패:", error);
    }
  }
);

// ═══════════════════════════════════════════════════════════
// 📦 예약 공개 처리
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

// ═══════════════════════════════════════════════════════════
// 📦 WorkDetail 마감 처리
// ═══════════════════════════════════════════════════════════

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

// ═══════════════════════════════════════════════════════════
// 📦 TO 마감 처리
// ═══════════════════════════════════════════════════════════

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
// 📦 근무 리마인더 (NEW)
// ═══════════════════════════════════════════════════════════

/**
 * 내일 근무 예정자에게 리마인더 알림 전송
 * @param {Timestamp} now - 현재 시간
 */
async function sendWorkReminders(now: Timestamp): Promise<void> {
  console.log("  📢 [리마인더] 처리 중...");

  try {
    // 내일 날짜 계산 (KST 기준)
    const tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);
    tomorrow.setHours(0, 0, 0, 0);

    const tomorrowEnd = new Date(tomorrow);
    tomorrowEnd.setHours(23, 59, 59, 999);

    // 내일 근무 확정된 지원서 조회
    const applicationsSnapshot = await db
      .collection("applications")
      .where("status", "==", "CONFIRMED")
      .where("workDate", ">=", Timestamp.fromDate(tomorrow))
      .where("workDate", "<=", Timestamp.fromDate(tomorrowEnd))
      .get();

    if (applicationsSnapshot.empty) {
      console.log("  ✅ [리마인더] 내일 근무 예정자 없음");
      return;
    }

    console.log(`  📋 [리마인더] 대상: ${applicationsSnapshot.size}명`);

    let sentCount = 0;
    // 중복 방지
    const processedUsers = new Set<string>();

    for (const appDoc of applicationsSnapshot.docs) {
      const appData = appDoc.data();
      const userId = appData.uid as string;

      // 같은 사용자에게 여러 근무가 있으면 한 번만 전송
      if (processedUsers.has(userId)) {
        continue;
      }
      processedUsers.add(userId);

      // 앱 내 알림 생성
      const notificationBody =
        `${appData.businessName}에서 내일 ${appData.selectedWorkType} ` +
        `근무가 있습니다.\n시간: ${appData.startTime}~${appData.endTime}`;

      await db.collection("notifications").add({
        userId: userId,
        type: "workReminder",
        title: "내일 근무 알림",
        body: notificationBody,
        data: {
          applicationId: appDoc.id,
          action: "applicationDetail",
        },
        isRead: false,
        createdAt: now,
      });

      // FCM 푸시 전송
      await sendFCMToUser(userId, {
        title: "내일 근무 알림 📅",
        body: `${appData.businessName} ${appData.startTime} 출근`,
        data: {
          type: "workReminder",
          applicationId: appDoc.id,
        },
      });

      sentCount++;
    }

    console.log(`  ✅ [리마인더] ${sentCount}명에게 알림 전송 완료`);
  } catch (error) {
    console.error("❌ [리마인더] 실패:", error);
  }
}

// ═══════════════════════════════════════════════════════════
// 📦 정합성 검사
// ═══════════════════════════════════════════════════════════

/**
 * 일일 정합성 검사 (새벽 3시 실행)
 * @param {Timestamp} now - 현재 시간
 */
async function runIntegrityCheck(now: Timestamp): Promise<void> {
  try {
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
        console.log(`    → TO ${toDoc.id} 상태 수정`);
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
      `  ✅ [정합성 검사] 완료: ${fixedCount}개 수정, ` +
        `${processedGroupIds.size}개 그룹 동기화`
    );
  } catch (error) {
    console.error("❌ [정합성 검사] 실패:", error);
  }
}

// ═══════════════════════════════════════════════════════════
// 📦 FCM 푸시 알림 (NEW)
// ═══════════════════════════════════════════════════════════

interface FCMPayload {
  title: string;
  body: string;
  data?: Record<string, string>;
}

/**
 * 특정 사용자에게 FCM 푸시 전송
 * @param {string} userId - 사용자 UID
 * @param {FCMPayload} payload - 알림 내용
 */
async function sendFCMToUser(
  userId: string,
  payload: FCMPayload
): Promise<void> {
  try {
    // 사용자의 FCM 토큰 조회
    const userDoc = await db.collection("users").doc(userId).get();
    if (!userDoc.exists) return;

    const userData = userDoc.data();
    const fcmToken = userData?.fcmToken as string | undefined;

    if (!fcmToken) {
      console.log(`    ⚠️ FCM 토큰 없음: ${userId}`);
      return;
    }

    // FCM 메시지 전송
    await admin.messaging().send({
      token: fcmToken,
      notification: {
        title: payload.title,
        body: payload.body,
      },
      data: payload.data,
      android: {
        priority: "high",
        notification: {
          channelId: "alfit_notifications",
          sound: "default",
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: 1,
          },
        },
      },
    });

    console.log(`    ✓ FCM 전송: ${userId}`);
  } catch (error: unknown) {
    // 토큰 만료 시 토큰 삭제
    const errorMessage = error instanceof Error ? error.message : "";
    if (
      errorMessage.includes("not-registered") ||
      errorMessage.includes("invalid-registration-token")
    ) {
      console.log(`    ⚠️ 만료된 FCM 토큰 삭제: ${userId}`);
      await db.collection("users").doc(userId).update({
        fcmToken: admin.firestore.FieldValue.delete(),
      });
    } else {
      console.log(`    ⚠️ FCM 전송 실패 (${userId}):`, error);
    }
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
