import {onSchedule} from "firebase-functions/v2/scheduler";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {initializeApp} from "firebase-admin/app";
import {getFirestore, Timestamp, Firestore} from "firebase-admin/firestore";
import * as admin from "firebase-admin";
import * as nodemailer from "nodemailer";

initializeApp();
const db = getFirestore();

// ═══════════════════════════════════════════════════════════
// 📧 이메일 인증 코드 발송
// ═══════════════════════════════════════════════════════════

export const sendEmailVerificationCode = onCall(
  {
    region: "asia-northeast3",
  },
  async (request) => {
    const email = request.data.email as string | undefined;

    if (!email || !email.includes("@")) {
      throw new HttpsError("invalid-argument", "올바른 이메일을 입력해주세요.");
    }

    const gmailUser = process.env.GMAIL_USER;
    const gmailPassword = process.env.GMAIL_APP_PASSWORD;

    if (!gmailUser || !gmailPassword) {
      throw new HttpsError("internal", "이메일 서비스 설정이 누락되었습니다.");
    }

    // 6자리 인증 코드 생성
    const code = Math.floor(100000 + Math.random() * 900000).toString();
    const expiresAt = new Date(Date.now() + 5 * 60 * 1000); // 5분 후 만료

    // Firestore에 코드 저장
    await db.collection("emailVerificationCodes").doc(email).set({
      code,
      expiresAt: Timestamp.fromDate(expiresAt),
      createdAt: Timestamp.now(),
      attempts: 0,
    });

    // 이메일 발송
    const transporter = nodemailer.createTransport({
      service: "gmail",
      auth: {
        user: gmailUser,
        pass: gmailPassword,
      },
    });

    await transporter.sendMail({
      from: `"AlFit" <${gmailUser}>`,
      to: email,
      subject: "[AlFit] 이메일 인증 코드",
      html: `
        <div style="font-family: sans-serif; max-width: 480px; margin: 0 auto;">
          <h2 style="color: #1976D2;">AlFit 이메일 인증</h2>
          <p>아래 인증 코드를 입력해주세요.</p>
          <div style="background: #f5f5f5; padding: 24px; text-align: center;
                      border-radius: 8px; margin: 24px 0;">
            <span style="font-size:36px;font-weight:bold;
                         letter-spacing:8px;color:#1976D2;">${code}</span>
          </div>
          <p style="color: #888; font-size: 13px;">
            인증 코드는 발송 후 5분 동안 유효합니다.<br>
            본인이 요청하지 않은 경우 이 메일을 무시하세요.
          </p>
        </div>
      `,
    });

    console.log(`✅ [이메일 인증] 코드 발송 완료: ${email}`);
    return {success: true};
  }
);

// ═══════════════════════════════════════════════════════════
// 📧 이메일 인증 코드 검증
// ═══════════════════════════════════════════════════════════

export const verifyEmailCode = onCall(
  {
    region: "asia-northeast3",
  },
  async (request) => {
    const email = request.data.email as string | undefined;
    const code = request.data.code as string | undefined;

    if (!email || !code) {
      throw new HttpsError("invalid-argument", "이메일과 코드를 입력해주세요.");
    }

    const docRef = db.collection("emailVerificationCodes").doc(email);
    const doc = await docRef.get();

    if (!doc.exists) {
      return {valid: false, reason: "not_found"};
    }

    // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
    const data = doc.data()!;
    const expiresAt = (data.expiresAt as Timestamp).toDate();
    const attempts = (data.attempts as number) ?? 0;

    // 5회 초과 시도 차단
    if (attempts >= 5) {
      return {valid: false, reason: "too_many_attempts"};
    }

    if (new Date() > expiresAt) {
      await docRef.delete();
      return {valid: false, reason: "expired"};
    }

    if (data.code !== code) {
      await docRef.update({attempts: attempts + 1});
      return {valid: false, reason: "wrong_code"};
    }

    // 검증 성공 → 코드 삭제
    await docRef.delete();
    console.log(`✅ [이메일 인증] 검증 성공: ${email}`);
    return {valid: true};
  }
);

// ═══════════════════════════════════════════════════════════
// 🔑 비밀번호 재설정 코드 발송
// ═══════════════════════════════════════════════════════════

export const sendPasswordResetCode = onCall(
  {region: "asia-northeast3"},
  async (request) => {
    const username = request.data.username as string | undefined;
    const email = request.data.email as string | undefined;

    if (!username || !email) {
      throw new HttpsError("invalid-argument", "아이디와 이메일을 입력해주세요.");
    }

    // Firestore에서 username으로 사용자 조회
    const snapshot = await db
      .collection("users")
      .where("username", "==", username)
      .limit(1)
      .get();

    if (snapshot.empty) {
      throw new HttpsError("not-found", "존재하지 않는 아이디입니다.");
    }

    const userData = snapshot.docs[0].data();
    const storedEmail = userData.userEmail as string | undefined;

    if (!storedEmail || storedEmail.toLowerCase() !== email.toLowerCase()) {
      throw new HttpsError("invalid-argument", "아이디와 이메일이 일치하지 않습니다.");
    }

    const gmailUser = process.env.GMAIL_USER;
    const gmailPassword = process.env.GMAIL_APP_PASSWORD;

    if (!gmailUser || !gmailPassword) {
      throw new HttpsError("internal", "이메일 서비스 설정이 누락되었습니다.");
    }

    const code = Math.floor(100000 + Math.random() * 900000).toString();
    const expiresAt = new Date(Date.now() + 5 * 60 * 1000);

    await db.collection("passwordResetCodes").doc(username).set({
      code,
      expiresAt: Timestamp.fromDate(expiresAt),
      createdAt: Timestamp.now(),
      attempts: 0,
    });

    const transporter = nodemailer.createTransport({
      service: "gmail",
      auth: {user: gmailUser, pass: gmailPassword},
    });

    await transporter.sendMail({
      from: `"ALfit" <${gmailUser}>`,
      to: storedEmail,
      subject: "[ALfit] 비밀번호 재설정 인증 코드",
      html: `
        <div style="font-family: sans-serif; max-width: 480px; margin: 0 auto;">
          <h2 style="color: #1565C0;">ALfit 비밀번호 재설정</h2>
          <p>아래 인증 코드를 입력해주세요.</p>
          <div style="background: #E3F2FD; padding: 24px; text-align: center;
                      border-radius: 12px; margin: 24px 0;">
            <span style="font-size:36px;font-weight:bold;
                         letter-spacing:8px;color:#1565C0;">${code}</span>
          </div>
          <p style="color: #888; font-size: 13px;">
            인증 코드는 발송 후 5분 동안 유효합니다.<br>
            본인이 요청하지 않은 경우 이 메일을 무시하세요.
          </p>
        </div>
      `,
    });

    console.log(`✅ [비밀번호 재설정] 코드 발송 완료: ${username}`);
    return {success: true};
  }
);

// ═══════════════════════════════════════════════════════════
// 🔑 비밀번호 재설정 코드 검증 및 변경
// ═══════════════════════════════════════════════════════════

export const resetPasswordWithCode = onCall(
  {region: "asia-northeast3"},
  async (request) => {
    const username = request.data.username as string | undefined;
    const code = request.data.code as string | undefined;
    const newPassword = request.data.newPassword as string | undefined;

    if (!username || !code || !newPassword) {
      throw new HttpsError("invalid-argument", "필수 항목이 누락되었습니다.");
    }

    if (newPassword.length < 6) {
      throw new HttpsError("invalid-argument", "비밀번호는 6자 이상이어야 합니다.");
    }

    const docRef = db.collection("passwordResetCodes").doc(username);
    const doc = await docRef.get();

    if (!doc.exists) {
      throw new HttpsError("not-found", "인증 코드를 먼저 요청해주세요.");
    }

    const data = doc.data();
    if (!data) {
      throw new HttpsError("not-found", "인증 코드를 찾을 수 없습니다.");
    }
    const expiresAt = (data.expiresAt as Timestamp).toDate();
    const attempts = (data.attempts as number) ?? 0;

    if (attempts >= 5) {
      await docRef.delete();
      throw new HttpsError(
        "resource-exhausted",
        "인증 시도 횟수를 초과했습니다. 다시 시도해주세요."
      );
    }

    if (new Date() > expiresAt) {
      await docRef.delete();
      throw new HttpsError("deadline-exceeded", "인증 코드가 만료되었습니다. 다시 요청해주세요.");
    }

    if (data.code !== code) {
      await docRef.update({attempts: attempts + 1});
      throw new HttpsError("invalid-argument", "인증번호가 일치하지 않습니다.");
    }

    // 코드 검증 성공 → 사용자 UID 조회
    const userSnapshot = await db
      .collection("users")
      .where("username", "==", username)
      .limit(1)
      .get();

    if (userSnapshot.empty) {
      throw new HttpsError("not-found", "사용자를 찾을 수 없습니다.");
    }

    const uid = userSnapshot.docs[0].id;

    // Firebase Admin SDK로 비밀번호 변경
    await admin.auth().updateUser(uid, {password: newPassword});

    // 코드 삭제
    await docRef.delete();

    console.log(`✅ [비밀번호 재설정] 완료: ${username}`);
    return {success: true};
  }
);

// ═══════════════════════════════════════════════════════════
// 🔔 알림 생성 시 FCM 푸시 자동 발송 (onCreate 트리거)
// ═══════════════════════════════════════════════════════════

export const onNotificationCreated = onDocumentCreated(
  {
    document: "notifications/{notificationId}",
    region: "asia-northeast3",
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      console.log("⚠️ [알림 트리거] 데이터 없음");
      return;
    }

    const notificationData = snapshot.data();
    const notificationId = event.params.notificationId;

    console.log(`🔔 [알림 트리거] 새 알림 감지: ${notificationId}`);

    // 필수 필드 확인
    const userId = notificationData.userId as string | undefined;
    const title = notificationData.title as string | undefined;
    const body = notificationData.body as string | undefined;
    const type = notificationData.type as string | undefined;

    if (!userId || !title) {
      console.log("⚠️ [알림 트리거] 필수 필드 누락");
      return;
    }

    // 근무 리마인더는 masterScheduler에서 이미 FCM 발송하므로 스킵
    if (type === "workReminder") {
      console.log("ℹ️ [알림 트리거] workReminder는 스킵 (이미 발송됨)");
      return;
    }

    // FCM 푸시 발송
    try {
      const userDoc = await db.collection("users").doc(userId).get();
      if (!userDoc.exists) {
        console.log(`⚠️ [알림 트리거] 사용자 없음: ${userId}`);
        return;
      }

      const userData = userDoc.data();
      const fcmToken = userData?.fcmToken as string | undefined;

      if (!fcmToken) {
        console.log(`⚠️ [알림 트리거] FCM 토큰 없음: ${userId}`);
        return;
      }

      // data 필드 준비 (문자열만 허용)
      const fcmData: Record<string, string> = {
        notificationId: notificationId,
        type: type || "general",
      };

      // 추가 data 필드가 있으면 병합
      if (notificationData.data) {
        const extraData = notificationData.data as Record<string, unknown>;
        for (const [key, value] of Object.entries(extraData)) {
          if (typeof value === "string") {
            fcmData[key] = value;
          } else if (value !== null && value !== undefined) {
            fcmData[key] = String(value);
          }
        }
      }

      // FCM 메시지 전송
      await admin.messaging().send({
        token: fcmToken,
        notification: {
          title: title,
          body: body || "",
        },
        data: fcmData,
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

      console.log(`✅ [알림 트리거] FCM 발송 완료: ${userId}`);
    } catch (error: unknown) {
      const errorMessage = error instanceof Error ? error.message : "";

      // 토큰 만료 시 삭제
      if (
        errorMessage.includes("not-registered") ||
        errorMessage.includes("invalid-registration-token")
      ) {
        console.log(`⚠️ [알림 트리거] 만료 토큰 삭제: ${userId}`);
        await db.collection("users").doc(userId).update({
          fcmToken: admin.firestore.FieldValue.delete(),
        });
      } else {
        console.error(`❌ [알림 트리거] FCM 실패 (${userId}):`, error);
      }
    }
  }
);

// ═══════════════════════════════════════════════════════════

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

      // 2️⃣ WorkDetail 마감 처리 (contract TO)
      await processWorkDetailExpiry(timestamp);

      // 2-2️⃣ 슬롯 WorkDetail 마감 처리 (flex TO)
      await processSlotWorkDetailExpiry(timestamp);

      // 3️⃣ TO 마감 처리
      await processTOExpiry(timestamp);
      // ═══════════════════════════════════════════════════════
      // ✅ 자정에만 실행 (00:00 ~ 00:09)
      // ═══════════════════════════════════════════════════════
      if (hour === 0 && minute < 10) {
        // 전날 근무 완료된 단기 지원자 리뷰 요청 생성 (14일 윈도우)
        console.log("📋 [리뷰 요청] 처리 시작...");
        await createPendingReviewRequests(timestamp);
        // 기한 만료 리뷰 요청 자동 공개
        console.log("📝 [리뷰 공개] 처리 시작...");
        await processExpiredReviewRequests(timestamp);
      }

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
  // 📦 리뷰 공개 처리 (매일 자정)
  // ═══════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════
// 📋 전날 완료된 단기 근무 → review_requests 자동 생성
// ═══════════════════════════════════════════════════════════

/**
 * 전날 workDate인 CONFIRMED 지원서를 조회해 review_requests 생성
 * - doc ID = requestKey(businessId_workerId_year_month) → 멱등성 보장
 * - 이미 존재하는 요청은 set({ merge: false }) 무시됨
 */
async function createPendingReviewRequests(now: Timestamp): Promise<void> {
  try {
    const yesterday = new Date(now.toDate());
    yesterday.setDate(yesterday.getDate() - 1);
    const dayStart = new Date(yesterday);
    dayStart.setHours(0, 0, 0, 0);
    const dayEnd = new Date(yesterday);
    dayEnd.setHours(23, 59, 59, 999);

    const snap = await db
      .collection("applications")
      .where("status", "==", "CONFIRMED")
      .where("workDate", ">=", Timestamp.fromDate(dayStart))
      .where("workDate", "<=", Timestamp.fromDate(dayEnd))
      .get();

    if (snap.empty) {
      console.log("  ✅ [리뷰 요청] 생성 대상 없음");
      return;
    }

    const deadline = new Date(yesterday);
    deadline.setDate(deadline.getDate() + 14); // 근무일 + 14일

    const year = yesterday.getFullYear();
    const month = yesterday.getMonth() + 1;

    let created = 0;

    for (const doc of snap.docs) {
      const data = doc.data();
      const workerId = data.uid as string;
      const businessId = data.businessId as string;
      if (!workerId || !businessId) continue;

      const requestKey = `${businessId}_${workerId}_${year}_${month}`;
      const requestRef = db.collection("review_requests").doc(requestKey);

      // create() → 이미 존재하면 예외(중복 방지)
      try {
        await requestRef.create({
          requestKey,
          businessId,
          businessName: data.businessName ?? "",
          workerId,
          workerName: data.applicantName ?? "",
          reviewYear: year,
          reviewMonth: month,
          deadline: Timestamp.fromDate(deadline),
          adminStatus: "pending",
          workerStatus: "pending",
          adminReviewId: null,
          workerReviewId: null,
          isPublished: false,
          publishedAt: null,
          createdAt: Timestamp.now(),
        });
        created++;

        // 관리자 알림
        await _sendReviewRequestNotification(
          businessId,
          data.applicantName ?? "근무자",
          requestKey,
          year,
          month,
          "admin"
        );
        // 근무자 알림
        await _sendReviewRequestNotification(
          workerId,
          data.businessName ?? "사업장",
          requestKey,
          year,
          month,
          "worker"
        );
      } catch {
        // 이미 존재 — 무시
      }
    }

    console.log(`  ✅ [리뷰 요청] ${created}개 생성 완료`);
  } catch (error) {
    console.error("❌ [리뷰 요청 생성] 실패:", error);
  }
}

// ═══════════════════════════════════════════════════════════
// 📝 기한 만료 리뷰 요청 자동 공개
// ═══════════════════════════════════════════════════════════

/**
 * deadline이 지난 review_requests 처리
 * - submitted 상태인 리뷰만 isPublished=true 로 변경
 * - 통계 업데이트
 */
async function processExpiredReviewRequests(now: Timestamp): Promise<void> {
  try {
    const snap = await db
      .collection("review_requests")
      .where("isPublished", "==", false)
      .where("deadline", "<=", now)
      .get();

    if (snap.empty) {
      console.log("  ✅ [리뷰 공개] 만료된 요청 없음");
      return;
    }

    console.log(`  📋 [리뷰 공개] 만료 요청 ${snap.size}개 처리`);

    const userStatsToUpdate = new Set<string>();
    const businessStatsToUpdate = new Set<string>();

    for (const reqDoc of snap.docs) {
      const req = reqDoc.data();
      const reviewIds: string[] = [];

      if (req.adminReviewId) reviewIds.push(req.adminReviewId as string);
      if (req.workerReviewId) reviewIds.push(req.workerReviewId as string);

      if (reviewIds.length === 0) {
        // 양쪽 다 작성 안 함 → 요청만 만료 처리
        await reqDoc.ref.update({ isPublished: true, publishedAt: now });
        continue;
      }

      // 작성된 리뷰 공개
      const batch = db.batch();
      for (const rid of reviewIds) {
        batch.update(db.collection("monthly_reviews").doc(rid), {
          isPublished: true,
          publishedAt: now,
        });
      }
      batch.update(reqDoc.ref, { isPublished: true, publishedAt: now });
      await batch.commit();

      // 통계 업데이트 대상 수집
      if (req.adminReviewId && req.workerId) {
        userStatsToUpdate.add(req.workerId as string);
      }
      if (req.workerReviewId && req.businessId) {
        businessStatsToUpdate.add(req.businessId as string);
      }

      console.log(`    → ${reqDoc.id} 자동 공개`);
    }

    for (const uid of userStatsToUpdate) await updateUserReviewStats(uid);
    for (const bid of businessStatsToUpdate) await updateBusinessReviewStats(bid);

    console.log(`  ✅ [리뷰 공개] 만료 처리 완료`);
  } catch (error) {
    console.error("❌ [리뷰 공개] 실패:", error);
  }
}

// ═══════════════════════════════════════════════════════════
// 🔔 리뷰 작성 완료 트리거 → 양방향 동시 공개
// ═══════════════════════════════════════════════════════════

/**
 * monthly_reviews 문서 생성 시 실행
 * requestId가 있고 양쪽 모두 submitted이면 즉시 동시 공개
 */
export const onReviewCreated = onDocumentCreated(
  { document: "monthly_reviews/{reviewId}", region: "asia-northeast3" },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const requestId = data.requestId as string | undefined;
    if (!requestId) return;

    const reqRef = db.collection("review_requests").doc(requestId);
    const reqSnap = await reqRef.get();
    if (!reqSnap.exists) return;

    const req = reqSnap.data()!;
    if (req.isPublished) return;

    const bothSubmitted =
      req.adminStatus === "submitted" && req.workerStatus === "submitted";
    if (!bothSubmitted) return;

    const now = Timestamp.now();
    const reviewIds: string[] = [];
    if (req.adminReviewId) reviewIds.push(req.adminReviewId as string);
    if (req.workerReviewId) reviewIds.push(req.workerReviewId as string);

    const batch = db.batch();
    for (const rid of reviewIds) {
      batch.update(db.collection("monthly_reviews").doc(rid), {
        isPublished: true,
        publishedAt: now,
      });
    }
    batch.update(reqRef, { isPublished: true, publishedAt: now });
    await batch.commit();

    // 통계 업데이트
    if (req.workerId) await updateUserReviewStats(req.workerId as string);
    if (req.businessId) await updateBusinessReviewStats(req.businessId as string);

    console.log(`✅ [리뷰 동시공개] ${requestId} 양방향 즉시 공개 완료`);
  }
);

// ─── 리뷰 요청 알림 헬퍼 ────────────────────────────────────────
async function _sendReviewRequestNotification(
  targetId: string,
  counterpartName: string,
  requestKey: string,
  year: number,
  month: number,
  role: "admin" | "worker"
): Promise<void> {
  try {
    const title = "리뷰 작성 요청";
    const body =
      role === "admin"
        ? `${counterpartName}님에 대한 ${year}년 ${month}월 리뷰를 작성해주세요.`
        : `${counterpartName}에 대한 ${year}년 ${month}월 리뷰를 작성해주세요.`;

    await db.collection("notifications").add({
      userId: targetId,
      type: "REVIEW_REQUEST",
      title,
      body,
      data: { requestKey, action: "writeReview" },
      isRead: false,
      createdAt: Timestamp.now(),
    });
  } catch (e) {
    console.log(`  ⚠️ 리뷰 알림 실패 (${targetId}):`, e);
  }
}

/**
   * 사용자 리뷰 통계 업데이트
   * @param {string} userId - 사용자 UID
   */
async function updateUserReviewStats(userId: string): Promise<void> {
  try {
    const snapshot = await db
      .collection("monthly_reviews")
      .where("targetUserId", "==", userId)
      .where("reviewType", "==", "ADMIN_TO_USER")
      .where("isPublished", "==", true)
      .get();

    if (snapshot.empty) return;

    let totalRating = 0;
    let rehireYesCount = 0;

    for (const doc of snapshot.docs) {
      const data = doc.data();
      totalRating += (data.rating as number) || 0;
      if (data.wouldRehire === true) rehireYesCount++;
    }

    const avgRating = totalRating / snapshot.size;
    const rehireRate = rehireYesCount / snapshot.size;

    await db.collection("users").doc(userId).update({
      averageRating: avgRating,
      reviewCount: snapshot.size,
      rehireRate: rehireRate,
    });

    console.log(`    ✓ 사용자 ${userId} 통계 업데이트`);
  } catch (error) {
    console.log(`    ⚠️ 사용자 통계 업데이트 실패 (${userId}):`, error);
  }
}

/**
   * 사업장 리뷰 통계 업데이트
   * @param {string} businessId - 사업장 ID
   */
async function updateBusinessReviewStats(businessId: string): Promise<void> {
  try {
    const snapshot = await db
      .collection("monthly_reviews")
      .where("businessId", "==", businessId)
      .where("reviewType", "==", "USER_TO_BUSINESS")
      .where("isPublished", "==", true)
      .get();

    if (snapshot.empty) return;

    let totalRating = 0;

    for (const doc of snapshot.docs) {
      const data = doc.data();
      totalRating += (data.rating as number) || 0;
    }

    const avgRating = totalRating / snapshot.size;

    await db.collection("businesses").doc(businessId).update({
      rating: avgRating,
      reviewCount: snapshot.size,
    });

    console.log(`    ✓ 사업장 ${businessId} 통계 업데이트`);
  } catch (error) {
    console.log(`    ⚠️ 사업장 통계 업데이트 실패 (${businessId}):`, error);
  }
}

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
  let processedCount = 0;

  snapshot.docs.forEach((doc) => {
    const data = doc.data();

    // 관리자가 수동마감한 SCHEDULED TO는 공개 대상 아님
    if (data.closedBy != null) {
      console.log(`    ⏭ ${doc.id} 수동마감 상태 — 공개 건너뜀`);
      return;
    }

    batch.update(doc.ref, {
      isPublished: true,
      publishedAt: now,
      status: "ACTIVE",
      statusUpdatedAt: now,
    });
    console.log(`    → ${doc.id} 공개 처리`);
    processedCount++;

    if (data.groupId) {
      affectedGroupIds.add(data.groupId);
    }
  });

  await batch.commit();
  console.log(`  ✅ [예약공개] ${processedCount}개 TO 공개 완료! (건너뜀: ${snapshot.size - processedCount}개)`);

  // 그룹 마스터 상태 동기화
  for (const groupId of affectedGroupIds) {
    await syncGroupMasterStatus(db, groupId);
  }
}

// ═══════════════════════════════════════════════════════════
// 📦 WorkDetail 마감 처리
// ═══════════════════════════════════════════════════════════

/**
 * 2️⃣ WorkDetail 시간 마감 처리 — contract TO 전용
 *    flex TO의 workDetail 마감은 processSlotWorkDetailExpiry에서 처리
 * @param {Timestamp} now - 현재 시간
 */
async function processWorkDetailExpiry(now: Timestamp): Promise<void> {
  console.log("  🔒 [WorkDetail 마감] 처리 중...");

  const tosSnapshot = await db
    .collection("tos")
    .where("status", "==", "ACTIVE")
    .where("type", "==", "contract")
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

    // workDetails는 TO 문서에 embedded array로 저장 (서브컬렉션 제거됨)
    const workDetails: any[] = toData.workDetails ?? [];
    if (workDetails.length === 0) continue;

    const expiredItems = workDetails.filter((wd: any) => {
      if (wd.isEmergencyOpen === true) return false;
      if (wd.closedAt != null) return false;
      const deadline = wd.applicationDeadline as Timestamp | null | undefined;
      return deadline != null && typeof deadline.toMillis === "function" &&
        deadline.toMillis() <= now.toMillis();
    });

    if (expiredItems.length === 0) continue;

    const expiredTypes = new Set(expiredItems.map((wd: any) => wd.workType));
    const updatedWorkDetails = workDetails.map((wd: any) =>
      expiredTypes.has(wd.workType) ?
        {...wd, closedAt: now, closedReason: "TIME_EXPIRED"} :
        wd
    );

    const batch = db.batch();
    batch.update(toDoc.ref, {workDetails: updatedWorkDetails});
    await batch.commit();

    totalClosed += expiredItems.length;
    affectedTOIds.add(toId);
    expiredItems.forEach((wd: any) =>
      console.log(`    → ${toId}/${wd.workType} WorkDetail 마감`)
    );
    if (toData.groupId) affectedGroupIds.add(toData.groupId);
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
// 📦 슬롯 WorkDetail 마감 처리 (flex TO 전용)
// ═══════════════════════════════════════════════════════════

/**
 * 2-2️⃣ flex TO 슬롯의 WorkDetail 시간 마감 처리
 *
 * flex TO는 workDetails가 슬롯 서브컬렉션에 저장됨.
 * 각 슬롯의 workDetail.applicationDeadline이 지나면 closedAt을 기록하고,
 * 슬롯 내 모든 workDetail이 마감되면 슬롯 status를 'closed'로 갱신.
 * isManualClosed는 건드리지 않음 — 자동 만료와 수동 마감을 구분해야
 * 재오픈 가능 여부를 올바르게 판단할 수 있음.
 *
 * @param {Timestamp} now - 현재 시간
 */
async function processSlotWorkDetailExpiry(now: Timestamp): Promise<void> {
  console.log("  🔒 [슬롯 WorkDetail 마감] 처리 중...");

  // 열린 슬롯 전체 조회 (collection group)
  const slotsSnap = await db
    .collectionGroup("slots")
    .where("status", "==", "open")
    .get();

  if (slotsSnap.empty) {
    console.log("  ✅ [슬롯 WorkDetail 마감] 처리할 슬롯 없음");
    return;
  }

  console.log(`  📋 [슬롯 WorkDetail 마감] 오픈 슬롯: ${slotsSnap.size}개 검사`);

  let totalClosedDetails = 0;
  let totalClosedSlots = 0;
  const affectedTOIds = new Set<string>();

  for (const slotDoc of slotsSnap.docs) {
    const slotData = slotDoc.data();

    // 관리자 직접마감 슬롯은 건너뜀 (closedBy 있음 = 직접마감)
    if (slotData.closedBy != null) continue;

    const workDetails: any[] = slotData.workDetails ?? [];
    if (workDetails.length === 0) continue;

    // 마감 시간이 지난 workDetail 탐색
    const expiredItems = workDetails.filter((wd: any) => {
      if (wd.isEmergencyOpen === true) return false;
      if (wd.closedAt != null) return false;
      const deadline = wd.applicationDeadline as Timestamp | null | undefined;
      return (
        deadline != null &&
        typeof deadline.toMillis === "function" &&
        deadline.toMillis() <= now.toMillis()
      );
    });

    if (expiredItems.length === 0) continue;

    // 만료된 workDetail에 closedAt 기록
    const expiredTypes = new Set(
      expiredItems.map((wd: any) => wd.workType as string)
    );
    const updatedWorkDetails = workDetails.map((wd: any) =>
      expiredTypes.has(wd.workType) ?
        {...wd, closedAt: now, closedReason: "TIME_EXPIRED"} :
        wd
    );

    // 슬롯 내 모든 workDetail이 마감됐는지 확인 (긴급공개 제외)
    const allDetailsClosed = updatedWorkDetails.every(
      (wd: any) => wd.isEmergencyOpen === true || wd.closedAt != null
    );

    const slotUpdate: Record<string, any> = {workDetails: updatedWorkDetails};
    if (allDetailsClosed) {
      // isManualClosed는 false 유지 — 자동 만료 슬롯은 재오픈 목록에 나타나지 않아야 함
      slotUpdate.status = "closed";
      slotUpdate.closedAt = now;
      slotUpdate.closedReason = "TIME_EXPIRED";
      totalClosedSlots++;
    }

    await slotDoc.ref.update(slotUpdate);
    totalClosedDetails += expiredItems.length;

    const toId =
      (slotData.toId as string | undefined) ??
      slotDoc.ref.parent.parent?.id;
    if (toId) {
      affectedTOIds.add(toId);
      expiredItems.forEach((wd: any) =>
        console.log(`    → ${toId}/${slotDoc.id}/${wd.workType} 마감`)
      );
    }
  }

  console.log(
    `  ✅ [슬롯 WorkDetail 마감] 업무상세 ${totalClosedDetails}개, ` +
      `슬롯 ${totalClosedSlots}개 마감 완료`
  );

  // 영향받은 TO status를 슬롯 상태 기반으로 동기화
  for (const toId of affectedTOIds) {
    await syncTOStatusFromSlots(db, toId, now);
  }
}

/**
 * flex TO의 status를 하위 슬롯 상태 기반으로 동기화
 * 열린 슬롯이 하나라도 있으면 ACTIVE, 모두 닫혔으면 CLOSED.
 *
 * @param {Firestore} firestore
 * @param {string} toId
 * @param {Timestamp} now
 */
async function syncTOStatusFromSlots(
  firestore: Firestore,
  toId: string,
  now: Timestamp
): Promise<void> {
  try {
    const toDoc = await firestore.collection("tos").doc(toId).get();
    if (!toDoc.exists) return;
    const toData = toDoc.data()!;
    // closedBy 있음 = 관리자 직접마감 → cascade 평가 대상 아님 (Flutter 불변식과 일치)
    if (toData.closedBy != null) return;

    const slotsSnap = await firestore
      .collection("tos")
      .doc(toId)
      .collection("slots")
      .get();

    if (slotsSnap.empty) return;

    const hasOpenSlot = slotsSnap.docs.some((doc) => {
      const d = doc.data();
      return !d.isManualClosed && d.status === "open";
    });

    const currentStatus = toData.status as string;
    const newStatus = hasOpenSlot ? "ACTIVE" : "CLOSED";

    if (currentStatus !== newStatus) {
      const updateData: Record<string, any> = {
        status: newStatus,
        statusUpdatedAt: now,
      };
      if (newStatus === "CLOSED") {
        updateData.closedAt = now;
        updateData.closedReason = "ALL_SLOTS_EXPIRED";
      }
      await firestore.collection("tos").doc(toId).update(updateData);
      console.log(`    ✓ TO ${toId} status: ${currentStatus} → ${newStatus}`);

      const groupId = toData.groupId as string | undefined;
      if (groupId) {
        await syncGroupMasterStatus(firestore, groupId);
      }
    }
  } catch (error) {
    console.error(`❌ 슬롯 기반 TO status 동기화 실패 (${toId}):`, error);
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
    // closedBy 있음 = 관리자 직접마감 → 자동만료 대상 아님
    return data.closedBy == null;
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

    // workDetails embedded array — 부모 TO 마감 시 open 항목 일괄 닫기
    const workDetails: any[] = data.workDetails ?? [];
    if (workDetails.length > 0) {
      const hasOpenItems = workDetails.some(
        (wd: any) => wd.isEmergencyOpen !== true && wd.closedAt == null
      );
      if (hasOpenItems) {
        const updated = workDetails.map((wd: any) =>
          wd.isEmergencyOpen === true || wd.closedAt != null ?
            wd :
            {...wd, closedAt: now, closedReason: "PARENT_TO_CLOSED"}
        );
        batch.update(doc.ref, {workDetails: updated});
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

      // closedBy 있음 = 관리자 직접마감 → 정합성 검사 대상 아님
      if (toData.closedBy != null) continue;

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

    // 2. 슬롯 workDetail 만료 정합성 — 10분 스케줄러에서 못 잡은 케이스 보정
    await processSlotWorkDetailExpiry(now);

    // 3. 모든 그룹 마스터 상태 재동기화
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
    // workDetails는 TO 문서에 embedded array로 저장 (서브컬렉션 제거됨)
    const toDoc = await firestore.collection("tos").doc(toId).get();
    if (!toDoc.exists) return;

    const toData = toDoc.data();
    if (!toData) return;

    // closedBy 있음 = 관리자 직접마감 → cascade 평가 대상 아님 (Flutter 불변식과 일치)
    if (toData.closedBy != null) return;

    const workDetails: any[] = toData.workDetails ?? [];
    if (workDetails.length === 0) return;

    const hasOpenWorkDetail = workDetails.some((wd: any) => {
      if (wd.isEmergencyOpen === true) return true;
      return wd.closedAt == null;
    });

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

    const now = Timestamp.now();
    const updateData: Record<string, unknown> = {
      status: newStatus,
      statusUpdatedAt: now,
    };

    if (newStatus === "CLOSED") {
      updateData.closedAt = now;
      updateData.closedReason = "ALL_CHILDREN_CLOSED";
    }

    // tos 컬렉션 마스터 TO 업데이트
    if (currentStatus !== newStatus) {
      await masterDoc.ref.update(updateData);
      console.log(
        `    ✓ 그룹 마스터 ${masterDoc.id}: ${currentStatus} → ${newStatus}`
      );
    }

    // groups 컬렉션은 독립적으로 비교해서 업데이트 (tos와 groups가 불일치한 기존 데이터 보정)
    const groupDocRef = firestore.collection("groups").doc(groupId);
    const groupDoc = await groupDocRef.get();
    if (groupDoc.exists && groupDoc.data()?.status !== newStatus) {
      await groupDocRef.update(updateData);
      console.log(
        `    ✓ groups 컬렉션 ${groupId}: ${groupDoc.data()?.status} → ${newStatus}`
      );
    }
  } catch (error) {
    console.error(`❌ 그룹 마스터 동기화 실패 (${groupId}):`, error);
  }
}
