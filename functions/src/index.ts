import {onSchedule} from "firebase-functions/v2/scheduler";
import {
  onDocumentCreated,
  onDocumentUpdated,
  onDocumentDeleted,
} from "firebase-functions/v2/firestore";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {initializeApp} from "firebase-admin/app";
import {getFirestore, Timestamp, Firestore} from "firebase-admin/firestore";
import * as admin from "firebase-admin";
import * as nodemailer from "nodemailer";
import * as crypto from "crypto";
import * as https from "https";

initializeApp();
const db = getFirestore();

// 확정 상태 그룹 (CONFIRMED + CONTRACT_PENDING 동일 처리)
const CONFIRMED_STATUSES = ["CONFIRMED", "CONTRACT_PENDING"];

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

    // 6자리 인증 코드 생성 (트랜잭션 전에 미리 생성)
    const code = String(crypto.randomInt(100000, 999999));
    const expiresAt = new Date(Date.now() + 5 * 60 * 1000); // 5분 후 만료

    // 1분 재발송 방지 + set을 트랜잭션으로 묶어 동시 요청 차단
    const emailVerDoc = db.collection("emailVerificationCodes").doc(email);
    await db.runTransaction(async (tx) => {
      const existing = await tx.get(emailVerDoc);
      if (existing.exists) {
        const createdAt = (existing.data()?.createdAt as Timestamp)?.toDate();
        if (createdAt && Date.now() - createdAt.getTime() < 60_000) {
          throw new HttpsError("resource-exhausted", "1분 후 다시 시도해주세요.");
        }
      }
      tx.set(emailVerDoc, {
        code,
        expiresAt: Timestamp.fromDate(expiresAt),
        createdAt: Timestamp.now(),
        attempts: 0,
      });
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

    // 읽기+업데이트를 트랜잭션으로 묶어 병렬 요청에 의한 브루트포스 제한 우회 차단
    let result: {valid: boolean; reason?: string} = {valid: false, reason: "not_found"};
    await db.runTransaction(async (tx) => {
      const doc = await tx.get(docRef);
      if (!doc.exists) {
        result = {valid: false, reason: "not_found"};
        return;
      }
      // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
      const data = doc.data()!;
      const expiresAt = (data.expiresAt as Timestamp).toDate();
      const attempts = (data.attempts as number) ?? 0;

      if (attempts >= 5) {
        result = {valid: false, reason: "too_many_attempts"};
        return;
      }
      if (new Date() > expiresAt) {
        tx.delete(docRef);
        result = {valid: false, reason: "expired"};
        return;
      }
      if (data.code !== code) {
        tx.update(docRef, {attempts: admin.firestore.FieldValue.increment(1)});
        result = {valid: false, reason: "wrong_code"};
        return;
      }
      // 검증 성공 → 코드 삭제
      tx.delete(docRef);
      result = {valid: true};
    });
    console.log(`✅ [이메일 인증] 검증 결과: ${email} → ${result.reason ?? "success"}`);
    return result;
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

    // 열거 공격 방지: username 존재 여부와 무관하게 동일 메시지 반환
    if (snapshot.empty) {
      throw new HttpsError("not-found", "아이디 또는 이메일이 일치하지 않습니다.");
    }

    const userData = snapshot.docs[0].data();
    const storedEmail = userData.userEmail as string | undefined;

    if (!storedEmail || storedEmail.toLowerCase() !== email.toLowerCase()) {
      throw new HttpsError("invalid-argument", "아이디 또는 이메일이 일치하지 않습니다.");
    }

    const gmailUser = process.env.GMAIL_USER;
    const gmailPassword = process.env.GMAIL_APP_PASSWORD;

    if (!gmailUser || !gmailPassword) {
      throw new HttpsError("internal", "이메일 서비스 설정이 누락되었습니다.");
    }

    const code = String(crypto.randomInt(100000, 999999));
    const expiresAt = new Date(Date.now() + 5 * 60 * 1000);

    // 60초 재발송 쿨다운 체크 + set을 트랜잭션으로 묶어 동시 요청 차단
    const pwResetDoc = db.collection("passwordResetCodes").doc(username);
    await db.runTransaction(async (tx) => {
      const existingDoc = await tx.get(pwResetDoc);
      if (existingDoc.exists) {
        const existingData = existingDoc.data();
        const createdAt =
          (existingData?.createdAt as Timestamp | undefined)?.toDate();
        if (createdAt && Date.now() - createdAt.getTime() < 60 * 1000) {
          throw new HttpsError(
            "resource-exhausted",
            "인증번호는 1분 후에 다시 요청할 수 있습니다."
          );
        }
      }
      tx.set(pwResetDoc, {
        code,
        expiresAt: Timestamp.fromDate(expiresAt),
        createdAt: Timestamp.now(),
        attempts: 0,
      });
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

    const pwRegex = /^(?=.*[a-zA-Z])(?=.*\d)(?=.*[!@#$%^&*(),.?":{}|<>]).{8,}$/;
    if (!pwRegex.test(newPassword)) {
      throw new HttpsError(
        "invalid-argument",
        "비밀번호는 8자 이상이며 영문·숫자·특수문자를 포함해야 합니다."
      );
    }

    const docRef = db.collection("passwordResetCodes").doc(username);

    // 읽기+업데이트를 트랜잭션으로 묶어 병렬 요청에 의한 브루트포스 제한 우회 차단
    await db.runTransaction(async (tx) => {
      const doc = await tx.get(docRef);
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
        tx.delete(docRef);
        throw new HttpsError(
          "resource-exhausted",
          "인증 시도 횟수를 초과했습니다. 다시 시도해주세요."
        );
      }
      if (new Date() > expiresAt) {
        tx.delete(docRef);
        throw new HttpsError("deadline-exceeded", "인증 코드가 만료되었습니다. 다시 요청해주세요.");
      }
      if (data.code !== code) {
        tx.update(docRef, {attempts: admin.firestore.FieldValue.increment(1)});
        throw new HttpsError("invalid-argument", "인증번호가 일치하지 않습니다.");
      }
      // 검증 성공 → 트랜잭션 내에서 코드 삭제
      tx.delete(docRef);
    });

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

    // 비밀번호 재사용 금지 — 최근 5개 이력 비교
    const newPwHash = crypto.createHash("sha256")
      .update(newPassword + uid)
      .digest("hex");

    const userDoc = await db.collection("users").doc(uid).get();
    const pwHistory: string[] = (userDoc.data()?.passwordHistory as string[]) ?? [];

    if (pwHistory.includes(newPwHash)) {
      throw new HttpsError(
        "already-exists",
        "이전에 사용한 비밀번호는 사용할 수 없습니다. 다른 비밀번호를 입력해주세요."
      );
    }

    // Firebase Admin SDK로 비밀번호 변경
    await admin.auth().updateUser(uid, {password: newPassword});

    // 기존 세션(리프레시 토큰) 무효화 — 다른 디바이스 강제 로그아웃
    await admin.auth().revokeRefreshTokens(uid);

    // 비밀번호 이력 업데이트 (최근 5개 유지)
    const updatedHistory = [newPwHash, ...pwHistory].slice(0, 5);
    await db.collection("users").doc(uid).update({passwordHistory: updatedHistory});

    console.log(`✅ [비밀번호 재설정] 완료: ${username}`);
    return {success: true};
  }
);

// ═══════════════════════════════════════════════════════════
// 🔄 재시작 프로그램 적용 (Admin SDK — 클라이언트 규칙 우회)
// 워커 본인만 호출 가능 (request.auth.uid == userId)
// ═══════════════════════════════════════════════════════════

export const applyRestartProgram = onCall(
  {region: "asia-northeast3"},
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");

    // 설정값 조회 (없으면 기본값 사용)
    const settingsDoc = await db.collection("settings").doc("trust_rules").get();
    const restartSettings = settingsDoc.exists
      ? (settingsDoc.data()?.restartProgram ?? {})
      : {};
    const resetScore: number = restartSettings.resetScore ?? 50;
    const noshowReduction: number = restartSettings.noshowReduction ?? 1;
    const lateReduction: number = restartSettings.lateReduction ?? 1;
    const cooldownDays: number = restartSettings.cooldownDays ?? 60;

    let applied = false;
    await db.runTransaction(async (tx) => {
      const userRef = db.collection("users").doc(userId);
      const userDoc = await tx.get(userRef);
      if (!userDoc.exists) throw new HttpsError("not-found", "사용자를 찾을 수 없습니다.");

      const userData = userDoc.data()!;

      // 쿨타임 체크
      const lastRestartAt = userData.lastRestartAt as Timestamp | undefined;
      if (lastRestartAt) {
        const cooldownEnd = new Date(lastRestartAt.toDate().getTime() + cooldownDays * 24 * 60 * 60 * 1000);
        if (new Date() < cooldownEnd) {
          const daysRemaining = Math.ceil((cooldownEnd.getTime() - Date.now()) / (24 * 60 * 60 * 1000));
          throw new HttpsError("failed-precondition", `쿨타임 중입니다. ${daysRemaining}일 후 신청 가능합니다.`);
        }
      }

      const currentNoShow: number = (userData.noShowCount as number) ?? 0;
      const currentLate: number = (userData.lateCount as number) ?? 0;
      const previousScore: number = (userData.trustScore as number) ?? 50;

      tx.update(userRef, {
        trustScore: resetScore,
        noShowCount: Math.max(0, currentNoShow - noshowReduction),
        lateCount: Math.max(0, currentLate - lateReduction),
        lastRestartAt: Timestamp.now(),
      });

      const historyRef = db.collection("restart_program_history").doc();
      tx.set(historyRef, {
        userId,
        previousScore,
        newScore: resetScore,
        noshowReduced: noshowReduction,
        lateReduced: lateReduction,
        createdAt: Timestamp.now(),
      });

      applied = true;
    });

    console.log(`✅ [재시작 프로그램] 적용 완료: uid=${userId}`);
    return {applied};
  }
);

// ═══════════════════════════════════════════════════════════
// 🕐 서버 시각 반환 (기기 시간 변조 감지용)
// ═══════════════════════════════════════════════════════════

export const getServerTime = onCall(
  {region: "asia-northeast3"},
  async () => {
    return {serverTimeMs: Date.now()};
  }
);

// ═══════════════════════════════════════════════════════════
// 👥 초대 수락 시 user.subAdminOf 설정 (Admin SDK, 클라이언트 규칙 우회)
// ═══════════════════════════════════════════════════════════

export const onMemberInvitationAccepted = onDocumentUpdated(
  {document: "member_invitations/{invitationId}", region: "asia-northeast3"},
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    if (before.status !== "pending" || after.status !== "accepted") return;

    const targetUid = after.targetUid as string | undefined;
    const businessId = after.businessId as string | undefined;
    if (!targetUid || !businessId) {
      console.error("⚠️ [초대수락 트리거] targetUid 또는 businessId 누락", after);
      return;
    }

    await db.collection("users").doc(targetUid).update({subAdminOf: businessId});
    console.log(`✅ [초대수락 트리거] subAdminOf 설정 완료: uid=${targetUid}, bizId=${businessId}`);
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

    // 필수 필드 확인 (트랜잭션 전에 빠른 검증)
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

    // 멱등성: 트랜잭션으로 fcmSent 플래그 선점 → FCM 중복 발송 방지
    // (FCM 발송 후 플래그 저장 시 함수 재시도 → 중복 발송 위험 제거)
    const notifRef = db.collection("notifications").doc(notificationId);
    const alreadySent = await db.runTransaction(async (tx) => {
      const doc = await tx.get(notifRef);
      if (doc.data()?.fcmSent === true) return true;
      tx.update(notifRef, {
        fcmSent: true,
        fcmSentAt: admin.firestore.Timestamp.now(),
      });
      return false;
    });
    if (alreadySent) {
      console.log(`ℹ️ [알림 트리거] 이미 발송됨 (스킵): ${notificationId}`);
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

      // 알림 카테고리별 수신 설정 체크
      const notifPrefs = userData?.notifPrefs as Record<string, boolean> | undefined;
      if (notifPrefs) {
        const category = _getNotifCategory(type ?? "");
        if (category && notifPrefs[category] === false) {
          console.log(`ℹ️ [알림 트리거] FCM 스킵 (수신 차단): ${userId}, type=${type}, category=${category}`);
          return;
        }
      }

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
    schedule: "0 * * * *",
    timeZone: "Asia/Seoul",
    region: "asia-northeast3",
    maxInstances: 1,
    timeoutSeconds: 300,
  },
  async () => {
    const timestamp = Timestamp.now();
    // Cloud Functions는 UTC로 실행 — KST(UTC+9) 기준으로 시간 판단
    const KST_OFFSET_MS = 9 * 60 * 60 * 1000;
    const nowKST = new Date(timestamp.toDate().getTime() + KST_OFFSET_MS);
    const hour = nowKST.getHours();
    const minute = nowKST.getMinutes();

    console.log(`🚀 [마스터 스케줄러] 시작: ${hour}시 ${minute}분`);

    // ═══════════════════════════════════════════════════════
    // ✅ 매 시간 실행 — 각 함수 독립 try-catch (한 실패가 나머지 차단 방지)
    // ═══════════════════════════════════════════════════════

    // 1️⃣ 예약 공개 처리
    try { await processScheduledPublish(timestamp); }
    catch (e) { console.error("❌ [예약 공개] 실패:", e); }

    // 2️⃣ WorkDetail 마감 처리 (contract TO)
    try { await processWorkDetailExpiry(timestamp); }
    catch (e) { console.error("❌ [WorkDetail 마감] 실패:", e); }

    // 2-2️⃣ 슬롯 WorkDetail 마감 처리 (flex TO)
    try { await processSlotWorkDetailExpiry(timestamp); }
    catch (e) { console.error("❌ [슬롯 WorkDetail 마감] 실패:", e); }

    // 3️⃣ TO 마감 처리
    try { await processTOExpiry(timestamp); }
    catch (e) { console.error("❌ [TO 마감] 실패:", e); }

    // ═══════════════════════════════════════════════════════
    // ✅ 자정에만 실행 (00:00 ~ 00:09)
    // ═══════════════════════════════════════════════════════
    if (hour === 0 && minute < 10) {
      // 24시간 미퇴근 attendance 자동 처리
      console.log("⏰ [미퇴근 처리] 시작...");
      try { await processMissedCheckouts(timestamp); }
      catch (e) { console.error("❌ [미퇴근 처리] 실패:", e); }

      // 전날 근무 완료된 단기 지원자 리뷰 요청 생성 (14일 윈도우)
      console.log("📋 [리뷰 요청] 처리 시작...");
      try { await createPendingReviewRequests(timestamp); }
      catch (e) { console.error("❌ [리뷰 요청] 실패:", e); }

      // 기한 만료 리뷰 요청 자동 공개
      console.log("📝 [리뷰 공개] 처리 시작...");
      try { await processExpiredReviewRequests(timestamp); }
      catch (e) { console.error("❌ [리뷰 공개] 실패:", e); }

      // 고정근무 계약 만료 D-15 알림 및 D-0 자동 연장
      console.log("🔄 [계약 연장] 처리 시작...");
      try { await processContractRenewalChecks(timestamp); }
      catch (e) { console.error("❌ [계약 연장] 실패:", e); }
    }

    // ═══════════════════════════════════════════════════════
    // ✅ 저녁 8시에만 실행 (20:00 ~ 20:09)
    // ═══════════════════════════════════════════════════════
    if (hour === 20 && minute < 10) {
      console.log("📢 [리마인더] 내일 근무 알림 시작...");
      try { await sendWorkReminders(timestamp); }
      catch (e) { console.error("❌ [리마인더] 실패:", e); }
    }

    // ═══════════════════════════════════════════════════════
    // ✅ 새벽 3시에만 실행 (03:00 ~ 03:09)
    // ═══════════════════════════════════════════════════════
    if (hour === 3 && minute < 10) {
      console.log("🔍 [정합성 검사] 시작...");
      try { await runIntegrityCheck(timestamp); }
      catch (e) { console.error("❌ [정합성 검사] 실패:", e); }
    }

    console.log("✅ [마스터 스케줄러] 완료!");
  }
);
// ═══════════════════════════════════════════════════════════
  // 📦 리뷰 공개 처리 (매일 자정)
  // ═══════════════════════════════════════════════════════════

// ─── 24시간 이상 미퇴근 자동 처리 ───────────────────────────
/**
 * 자정 실행: checkIn은 있으나 checkOut이 없고 24시간 이상 경과한
 * attendance 문서를 "missed_checkout" 상태로 마킹.
 * 실제 퇴근 시각은 null 유지 → 관리자가 수동 수정.
 */
async function processMissedCheckouts(now: Timestamp): Promise<void> {
  const cutoff = new Date(now.toDate().getTime() - 24 * 60 * 60 * 1000);
  const snap = await db
    .collection("attendance")
    .where("checkOut", "==", null)
    .where("checkIn", "!=", null)
    .where("createdAt", "<=", Timestamp.fromDate(cutoff))
    .limit(200)
    .get();

  if (snap.empty) return;

  const batch = db.batch();
  let count = 0;
  for (const doc of snap.docs) {
    const data = doc.data();
    if (data.status === "NO_SHOW" || data.status === "missed_checkout") continue;
    batch.update(doc.ref, {
      status: "missed_checkout",  // 관리자 확인 필요 상태
      updatedAt: now,
    });
    count++;
    if (count >= 499) break;
  }
  if (count > 0) {
    await batch.commit();
    console.log(`⏰ [미퇴근 처리] ${count}건 missed_checkout 처리 완료`);
  }
}

// ═══════════════════════════════════════════════════════════
// 📋 전날 완료된 단기 근무 → review_requests 자동 생성
// ═══════════════════════════════════════════════════════════

/**
 * 전날 workDate인 CONFIRMED 지원서를 조회해 review_requests 생성
 * - doc ID = requestKey(businessId_workerId_year_month) → 멱등성 보장
 * - 이미 존재하는 요청은 set({ merge: false }) 무시됨
 * @param {Timestamp} now - 현재 시간
 */
async function createPendingReviewRequests(now: Timestamp): Promise<void> {
  try {
    // 14일 윈도우 소급 적용 — create()가 멱등적이므로 중복 없음
    // workDate는 KST로 생성되어 UTC Timestamp로 저장 → KST 기준으로 윈도우 계산 후 UTC 역변환
    const KST_OFFSET_MS = 9 * 60 * 60 * 1000;
    const nowKST = new Date(now.toDate().getTime() + KST_OFFSET_MS);

    const windowEndKST = new Date(nowKST);
    windowEndKST.setDate(windowEndKST.getDate() - 1); // 어제
    windowEndKST.setHours(23, 59, 59, 999);
    const windowStartKST = new Date(nowKST);
    windowStartKST.setDate(windowStartKST.getDate() - 14); // 14일 전
    windowStartKST.setHours(0, 0, 0, 0);

    const windowEnd = new Date(windowEndKST.getTime() - KST_OFFSET_MS);
    const windowStart = new Date(windowStartKST.getTime() - KST_OFFSET_MS);

    const [snap, longTermSnap] = await Promise.all([
      db.collection("applications")
        .where("status", "in", CONFIRMED_STATUSES)
        .where("workDate", ">=", Timestamp.fromDate(windowStart))
        .where("workDate", "<=", Timestamp.fromDate(windowEnd))
        .get(),
      db.collection("applications")
        .where("status", "in", CONFIRMED_STATUSES)
        .where("workEndDate", ">=", Timestamp.fromDate(windowStart))
        .where("workEndDate", "<=", Timestamp.fromDate(windowEnd))
        .get(),
    ]);

    const allDocs = [...snap.docs, ...longTermSnap.docs];
    if (allDocs.length === 0) {
      console.log("  ✅ [리뷰 요청] 처리할 지원서 없음");
      return;
    }

    // ── 배치 사전 조회: users (applicantName 없는 경우) ──────────────────
    const missingNameWorkerIds = new Set<string>();
    for (const doc of allDocs) {
      const data = doc.data();
      if (!(data.applicantName as string | undefined) && data.uid) {
        missingNameWorkerIds.add(data.uid as string);
      }
    }
    const userNameMap = new Map<string, string>();
    if (missingNameWorkerIds.size > 0) {
      const workerIdList = [...missingNameWorkerIds];
      // getAll은 최대 30개 제한 — 30개씩 청크 처리
      for (let i = 0; i < workerIdList.length; i += 30) {
        const chunk = workerIdList.slice(i, i + 30);
        const refs = chunk.map((id) => db.collection("users").doc(id));
        const docs = await db.getAll(...refs);
        for (const d of docs) {
          if (d.exists) userNameMap.set(d.id, (d.data() as any)?.name ?? "근무자");
        }
      }
    }

    // ── 배치 사전 조회: monthly_reviews ─────────────────────────────────
    const reviewKeys = new Set<string>();
    for (const doc of allDocs) {
      const data = doc.data();
      const workerId = data.uid as string;
      const businessId = data.businessId as string;
      if (!workerId || !businessId) continue;
      // workDate 기반 키 (단기) 또는 workEndDate 기반 키 (장기) 모두 수집
      const dateField = snap.docs.includes(doc) ? data.workDate : data.workEndDate;
      if (!dateField) continue;
      const dateKST = new Date((dateField as Timestamp).toDate().getTime() + KST_OFFSET_MS);
      const y = dateKST.getUTCFullYear();
      const m = dateKST.getUTCMonth() + 1;
      reviewKeys.add(`${businessId}_${workerId}_${y}_${m}`);
    }
    const existingReviewSet = new Set<string>();
    if (reviewKeys.size > 0) {
      const reviewKeyList = [...reviewKeys];
      for (let i = 0; i < reviewKeyList.length; i += 30) {
        const chunk = reviewKeyList.slice(i, i + 30);
        const refs = chunk.map((k) => db.collection("monthly_reviews").doc(k));
        const docs = await db.getAll(...refs);
        for (const d of docs) {
          if (d.exists) existingReviewSet.add(d.id);
        }
      }
    }

    let created = 0;

    // ── 단기 지원서 처리 ─────────────────────────────────────────────────
    for (const doc of snap.docs) {
      const data = doc.data();
      const workerId = data.uid as string;
      const businessId = data.businessId as string;
      if (!workerId || !businessId) continue;

      const workDate = (data.workDate as Timestamp).toDate();
      const workDateKST = new Date(workDate.getTime() + KST_OFFSET_MS);
      const year = workDateKST.getUTCFullYear();
      const month = workDateKST.getUTCMonth() + 1;

      const requestKey = `${businessId}_${workerId}_${year}_${month}`;
      const requestRef = db.collection("review_requests").doc(requestKey);

      const deadline = new Date(workDate);
      deadline.setDate(deadline.getDate() + 14);

      const adminAlreadyReviewed = existingReviewSet.has(requestKey);
      const workerName = (data.applicantName as string | undefined)
        || userNameMap.get(workerId)
        || "근무자";

      try {
        await requestRef.create({
          requestKey,
          businessId,
          businessName: data.businessName ?? "",
          workerId,
          workerName,
          reviewYear: year,
          reviewMonth: month,
          deadline: Timestamp.fromDate(deadline),
          adminStatus: adminAlreadyReviewed ? "submitted" : "pending",
          workerStatus: "pending",
          adminReviewId: adminAlreadyReviewed ? requestKey : null,
          workerReviewId: null,
          isPublished: false,
          publishedAt: null,
          createdAt: Timestamp.now(),
        });
        created++;

        if (!adminAlreadyReviewed) {
          await _sendReviewRequestNotification(
            businessId, workerName,
            requestKey, year, month, "admin"
          );
        }
        await _sendReviewRequestNotification(
          workerId, data.businessName ?? "사업장",
          requestKey, year, month, "worker"
        );
      } catch {
        // 이미 존재 — 무시
      }
    }

    // ── 장기 근무자: workEndDate가 윈도우 내인 CONFIRMED/CONTRACT_PENDING 지원서 ──
    for (const doc of longTermSnap.docs) {
      const data = doc.data();
      const workerId = data.uid as string;
      const businessId = data.businessId as string;
      if (!workerId || !businessId) continue;

      const endDate = (data.workEndDate as Timestamp).toDate();
      const endDateKST = new Date(endDate.getTime() + KST_OFFSET_MS);
      const endYear = endDateKST.getUTCFullYear();
      const endMonth = endDateKST.getUTCMonth() + 1;

      const requestKey = `${businessId}_${workerId}_${endYear}_${endMonth}`;
      const requestRef = db.collection("review_requests").doc(requestKey);

      const deadlineDate = new Date(endDate);
      deadlineDate.setDate(deadlineDate.getDate() + 14);

      const adminAlreadyReviewed = existingReviewSet.has(requestKey);
      const workerName = (data.applicantName as string | undefined)
        || userNameMap.get(workerId)
        || "근무자";

      try {
        await requestRef.create({
          requestKey,
          businessId,
          businessName: data.businessName ?? "",
          workerId,
          workerName,
          reviewYear: endYear,
          reviewMonth: endMonth,
          deadline: Timestamp.fromDate(deadlineDate),
          adminStatus: adminAlreadyReviewed ? "submitted" : "pending",
          workerStatus: "pending",
          adminReviewId: adminAlreadyReviewed ? requestKey : null,
          workerReviewId: null,
          isPublished: false,
          publishedAt: null,
          createdAt: Timestamp.now(),
        });
        created++;
        if (!adminAlreadyReviewed) {
          await _sendReviewRequestNotification(
            businessId, workerName,
            requestKey, endYear, endMonth, "admin"
          );
        }
        await _sendReviewRequestNotification(
          workerId, data.businessName ?? "사업장",
          requestKey, endYear, endMonth, "worker"
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
 * @param {Timestamp} now - 현재 시간
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
        await reqDoc.ref.update({isPublished: true, publishedAt: now});
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
      batch.update(reqDoc.ref, {isPublished: true, publishedAt: now});
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

    for (const uid of userStatsToUpdate) {
      try { await updateUserReviewStats(uid); }
      catch (e) { console.error(`⚠️ [리뷰 공개] 사용자 통계 업데이트 실패 (${uid}):`, e); }
    }
    for (const bid of businessStatsToUpdate) {
      try { await updateBusinessReviewStats(bid); }
      catch (e) { console.error(`⚠️ [리뷰 공개] 사업장 통계 업데이트 실패 (${bid}):`, e); }
    }

    console.log("  ✅ [리뷰 공개] 만료 처리 완료");
  } catch (error) {
    console.error("❌ [리뷰 공개] 실패:", error);
  }
}

// ═══════════════════════════════════════════════════════════
// 🔔 리뷰 작성 완료 트리거 → 양방향 동시 공개
// ═══════════════════════════════════════════════════════════

/**
 * monthly_reviews 문서 생성 시 실행
 * - 트랜잭션으로 review_requests 상태를 원자적으로 업데이트
 * - 양쪽 모두 submitted이면 즉시 동시 공개
 * (기존 코드는 클라이언트가 adminStatus를 업데이트하기 전에 CF가 실행되는
 * 레이스 컨디션이 있었음 → 트랜잭션에서 CF가 직접 상태를 업데이트하도록 수정)
 */
export const onReviewCreated = onDocumentCreated(
  {document: "monthly_reviews/{reviewId}", region: "asia-northeast3"},
  async (event) => {
    const reviewId = event.params.reviewId;
    const data = event.data?.data();
    if (!data) return;

    const requestId = data.requestId as string | undefined;
    if (!requestId) return;

    const reviewType = data.reviewType as string | undefined;
    const isAdminReview = reviewType === "ADMIN_TO_USER";
    const statusField = isAdminReview ? "adminStatus" : "workerStatus";
    const reviewIdField = isAdminReview ? "adminReviewId" : "workerReviewId";
    const otherStatusField = isAdminReview ? "workerStatus" : "adminStatus";

    const reqRef = db.collection("review_requests").doc(requestId);
    const now = Timestamp.now();

    let shouldPublish = false;
    let otherReviewId: string | null = null;

    // 트랜잭션: 이 리뷰 측 상태를 원자적으로 업데이트하고 동시 공개 여부 확인
    await db.runTransaction(async (tx) => {
      const reqSnap = await tx.get(reqRef);
      if (!reqSnap.exists) return;

      const req = reqSnap.data()!;
      if (req.isPublished) return;

      tx.update(reqRef, {
        [statusField]: "submitted",
        [reviewIdField]: reviewId,
      });

      shouldPublish =
        (req[otherStatusField] as string | undefined) === "submitted";
      otherReviewId = (
        isAdminReview ? req.workerReviewId : req.adminReviewId
      ) as string | null;
    });

    if (!shouldPublish) {
      console.log(`📝 [리뷰 생성] ${requestId} - ${statusField} 제출 (상대방 대기 중)`);
      return;
    }

    // 양쪽 모두 제출 → 즉시 동시 공개
    const reviewIds: string[] = [reviewId];
    if (otherReviewId) reviewIds.push(otherReviewId);

    const batch = db.batch();
    for (const rid of reviewIds) {
      batch.update(db.collection("monthly_reviews").doc(rid), {
        isPublished: true,
        publishedAt: now,
      });
    }
    batch.update(reqRef, {isPublished: true, publishedAt: now});
    await batch.commit();

    // 통계 업데이트
    const reqSnap = await reqRef.get();
    const req = reqSnap.data();
    if (req?.workerId) await updateUserReviewStats(req.workerId as string);
    if (req?.businessId) {
      await updateBusinessReviewStats(req.businessId as string);
    }

    console.log(`✅ [리뷰 동시공개] ${requestId} 양방향 즉시 공개 완료`);
  }
);

// ═══════════════════════════════════════════════════════════
// 💰 임금 확정 시 리뷰 요청 자동 생성
// ═══════════════════════════════════════════════════════════

/**
 * attendance.wageStatus가 'confirmed'로 변경될 때 review_requests 자동 생성
 * 자정 CF를 기다리지 않고 마감 처리 즉시 미작성 탭에 노출
 */
export const onWageConfirmed = onDocumentUpdated(
  {document: "attendance/{attendanceId}", region: "asia-northeast3"},
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;

    // wageStatus가 confirmed로 최초 변경될 때만 처리
    if (
      before.wageStatus === "confirmed" ||
      after.wageStatus !== "confirmed"
    ) return;

    const applicationId = after.applicationId as string | undefined;
    if (!applicationId) return;

    const appDoc = await db.collection("applications").doc(applicationId).get();
    if (!appDoc.exists) return;

    const app = appDoc.data()!;
    const workerId = app.uid as string | undefined;
    const businessId = app.businessId as string | undefined;
    if (!workerId || !businessId) return;

    const workDate =
      (after.workDate as Timestamp | undefined)?.toDate() ?? new Date();
    const KST_OFFSET_MS = 9 * 60 * 60 * 1000;
    const workDateKST = new Date(workDate.getTime() + KST_OFFSET_MS);
    const year = workDateKST.getUTCFullYear();
    const month = workDateKST.getUTCMonth() + 1;

    const requestKey = `${businessId}_${workerId}_${year}_${month}`;
    const requestRef = db.collection("review_requests").doc(requestKey);

    const deadline = new Date(workDate);
    deadline.setDate(deadline.getDate() + 14);

    // workerName 보완
    let workerName3 = (app.applicantName as string | undefined) ?? "";
    if (!workerName3 && workerId) {
      const userDoc3 = await db.collection("users").doc(workerId).get();
      workerName3 = userDoc3.exists ? ((userDoc3.data() as any)?.name ?? "근무자") : "근무자";
    }
    if (!workerName3) workerName3 = "근무자";

    try {
      await requestRef.create({
        requestKey,
        businessId,
        businessName: app.businessName ?? "",
        workerId,
        workerName: workerName3,
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
      await _sendReviewRequestNotification(
        businessId, workerName3,
        requestKey, year, month, "admin"
      );
      await _sendReviewRequestNotification(
        workerId, app.businessName ?? "사업장",
        requestKey, year, month, "worker"
      );
      console.log(`✅ [임금 확정] 리뷰 요청 생성: ${requestKey}`);
    } catch {
      // 이미 존재 — 무시 (동일 월 중복 마감 처리 등)
      console.log(`  ℹ️ [임금 확정] 리뷰 요청 이미 존재: ${requestKey}`);
    }
  }
);

// ═══════════════════════════════════════════════════════════
// 💰 급여 summary 자동 집계 (wageStatus 변경 시)
// ═══════════════════════════════════════════════════════════

/**
 * attendance.wageStatus 변경 시 payroll_summaries 문서를 트랜잭션으로 갱신.
 * - * → confirmed : finalWage 더하기, workDays +1
 * - confirmed → * : finalWage 빼기, workDays -1
 * - confirmed → confirmed (금액 수정) : delta 적용
 */
export const onAttendanceWageChanged = onDocumentUpdated(
  {document: "attendance/{attendanceId}", region: "asia-northeast3"},
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;

    const beforeStatus = (before.wageStatus as string | undefined) ?? "pending";
    const afterStatus = (after.wageStatus as string | undefined) ?? "pending";

    // confirmed + transferred 모두 집계 대상
    // transferred 전환 시 summary에서 제거되지 않도록 동일 그룹으로 처리
    const SUMMARY_STATUSES = ["confirmed", "transferred"];
    const wasConfirmed = SUMMARY_STATUSES.includes(beforeStatus);
    const isConfirmed = SUMMARY_STATUSES.includes(afterStatus);

    if (!wasConfirmed && !isConfirmed) return;

    const businessId = after.businessId as string | undefined;
    const userId = after.userId as string | undefined;
    if (!businessId || !userId) return;

    const rawDate = after.workDate as Timestamp | undefined;
    const workDate = rawDate?.toDate() ?? new Date();
    const KST_OFFSET_MS_W = 9 * 60 * 60 * 1000;
    const workDateKST = new Date(workDate.getTime() + KST_OFFSET_MS_W);
    const year = workDateKST.getUTCFullYear();
    const monthNum = workDateKST.getUTCMonth() + 1;
    const monthStr = monthNum.toString().padStart(2, "0");
    const yearMonth = `${year}-${monthStr}`;
    const summaryId = `${businessId}_${yearMonth}`;
    const summaryRef = db.collection("payroll_summaries").doc(summaryId);

    // 근무자 이름 조회 (트랜잭션 외부)
    let workerName = "";
    try {
      const userDoc = await db.collection("users").doc(userId).get();
      if (userDoc.exists) {
        workerName = (userDoc.data()?.name as string) ?? "";
      }
    } catch {
      // 이름 없으면 빈 문자열 유지
    }

    const beforeWage =
      wasConfirmed ? ((before.finalWage as number | undefined) ?? 0) : 0;
    const afterWage =
      isConfirmed ? ((after.finalWage as number | undefined) ?? 0) : 0;
    const payoutDelta = afterWage - beforeWage;
    const confirmedCountDelta = (isConfirmed ? 1 : 0) - (wasConfirmed ? 1 : 0);

    type WorkerEntry = {name: string; totalPayout: number; workDays: number};

    await db.runTransaction(async (tx) => {
      const summarySnap = await tx.get(summaryRef);
      const now = Timestamp.now();

      if (!summarySnap.exists) {
        if (!isConfirmed) return;
        tx.set(summaryRef, {
          businessId,
          yearMonth,
          year,
          month: monthNum,
          totalPayout: afterWage,
          confirmedCount: 1,
          workerCount: 1,
          workers: {
            [userId]: {name: workerName, totalPayout: afterWage, workDays: 1},
          },
          updatedAt: now,
        });
        return;
      }

      const data = summarySnap.data() as Record<string, unknown>;
      const rawWorkers = (data.workers ?? {}) as Record<string, WorkerEntry>;
      const workers: Record<string, WorkerEntry> = {...rawWorkers};

      const existing: WorkerEntry =
        workers[userId] ?? {name: workerName, totalPayout: 0, workDays: 0};
      const newPayout = existing.totalPayout + payoutDelta;
      const newDays = existing.workDays + confirmedCountDelta;

      if (newDays <= 0) {
        delete workers[userId];
      } else {
        workers[userId] = {
          name: workerName || existing.name,
          totalPayout: Math.max(0, newPayout),
          workDays: Math.max(0, newDays),
        };
      }

      const prevTotal = (data.totalPayout as number) ?? 0;
      const prevCount = (data.confirmedCount as number) ?? 0;
      tx.update(summaryRef, {
        totalPayout: Math.max(0, prevTotal + payoutDelta),
        confirmedCount: Math.max(0, prevCount + confirmedCountDelta),
        workerCount: Object.keys(workers).length,
        workers,
        updatedAt: now,
      });
    });

    console.log(`✅ [급여 summary] ${summaryId} 갱신 완료 (delta: ${payoutDelta}원)`);
  }
);

// ═══════════════════════════════════════════════════════════
// 🔧 리뷰 요청 즉시 생성 (수동 백필용 callable)
// ═══════════════════════════════════════════════════════════

/**
 * 과거 14일 내 CONFIRMED 지원서의 review_requests를 즉시 생성
 * - 자정 스케줄러를 기다리지 않고 앱/콘솔에서 수동 트리거 가능
 * - 이미 작성된 리뷰가 있으면 adminStatus='submitted'로 자동 연동
 */
export const backfillReviewRequests = onCall(
  {region: "asia-northeast3"},
  async (request) => {
    // SUPER_ADMIN만 호출 가능 — 권한 없으면 즉시 차단
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    }
    const callerDoc = await db.collection("users").doc(request.auth.uid).get();
    if (callerDoc.data()?.role !== "SUPER_ADMIN") {
      throw new HttpsError("permission-denied", "슈퍼관리자만 실행할 수 있습니다.");
    }
    const now = Timestamp.now();
    await createPendingReviewRequests(now);
    return {success: true};
  }
);

// ─── 리뷰 요청 알림 헬퍼 ────────────────────────────────────────
/**
 * 리뷰 작성 요청 알림 전송
 * @param {string} targetId - admin role: businessId, worker role: 근무자 uid
 * @param {string} counterpartName - 상대방 이름
 * @param {string} requestKey - 리뷰 요청 문서 ID
 * @param {number} year - 리뷰 연도
 * @param {number} month - 리뷰 월
 * @param {"admin" | "worker"} role - 수신자 역할
 */
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
      role === "admin" ?
        `${counterpartName}님에 대한 ${year}년 ${month}월 리뷰를 작성해주세요.` :
        `${counterpartName}에 대한 ${year}년 ${month}월 리뷰를 작성해주세요.`;

    // admin role: targetId = businessId → ownerId(사업주 UID)로 변환
    let userId = targetId;
    if (role === "admin") {
      const bizDoc = await db.collection("businesses").doc(targetId).get();
      const ownerId = bizDoc.data()?.ownerId as string | undefined;
      if (!ownerId) {
        console.log(`  ⚠️ 리뷰 알림 스킵 — ownerId 없음 (bizId=${targetId})`);
        return;
      }
      userId = ownerId;
    }

    await db.collection("notifications").add({
      userId,
      type: "REVIEW_REQUEST",
      title,
      body,
      data: {requestKey, action: "writeReview"},
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
    let ratedCount = 0;
    let rehireYesCount = 0;

    for (const doc of snapshot.docs) {
      const data = doc.data();
      const r = (data.rating as number) || 0;
      if (r > 0) { totalRating += r; ratedCount++; }
      if (data.wouldRehire === true) rehireYesCount++;
    }

    const avgRating = ratedCount > 0 ? totalRating / ratedCount : null;
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
    let ratedCount = 0;

    for (const doc of snapshot.docs) {
      const data = doc.data();
      const r = (data.rating as number) || 0;
      if (r > 0) { totalRating += r; ratedCount++; }
    }

    const avgRating = ratedCount > 0 ? totalRating / ratedCount : null;

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

  let batch = db.batch();
  let batchCount = 0;
  const affectedGroupIds = new Set<string>();
  let processedCount = 0;

  for (const doc of snapshot.docs) {
    const data = doc.data();

    // 관리자가 수동마감한 SCHEDULED TO는 공개 대상 아님
    if (data.closedBy != null) {
      console.log(`    ⏭ ${doc.id} 수동마감 상태 — 공개 건너뜀`);
      continue;
    }

    batch.update(doc.ref, {
      isPublished: true,
      publishedAt: now,
      status: "ACTIVE",
      statusUpdatedAt: now,
    });
    console.log(`    → ${doc.id} 공개 처리`);
    processedCount++;
    batchCount++;

    if (data.groupId) {
      affectedGroupIds.add(data.groupId);
    }

    if (batchCount >= 499) {
      await batch.commit();
      batch = db.batch();
      batchCount = 0;
    }
  }

  if (batchCount > 0) await batch.commit();
  const skipped = snapshot.size - processedCount;
  console.log(`  ✅ [예약공개] ${processedCount}개 TO 공개 완료! (건너뜀: ${skipped}개)`);

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

  let batch = db.batch();
  let batchCount = 0;
  const affectedGroupIds = new Set<string>();

  for (const doc of tosToClose) {
    const data = doc.data();

    // workDetails embedded array — 부모 TO 마감 시 open 항목 일괄 닫기
    const workDetails: any[] = data.workDetails ?? [];
    const updateData: Record<string, any> = {
      status: "CLOSED",
      closedAt: now,
      closedReason: "TIME_EXPIRED",
      statusUpdatedAt: now,
    };
    if (workDetails.length > 0) {
      const hasOpenItems = workDetails.some(
        (wd: any) => wd.isEmergencyOpen !== true && wd.closedAt == null
      );
      if (hasOpenItems) {
        updateData.workDetails = workDetails.map((wd: any) =>
          (wd.isEmergencyOpen === true || wd.closedAt != null) ?
            wd :
            {...wd, closedAt: now, closedReason: "PARENT_TO_CLOSED"}
        );
      }
    }

    batch.update(doc.ref, updateData);
    console.log(`    → ${doc.id} TO 마감`);
    batchCount++;

    if (data.groupId) {
      affectedGroupIds.add(data.groupId);
    }

    if (batchCount >= 499) {
      await batch.commit();
      batch = db.batch();
      batchCount = 0;
    }
  }

  if (batchCount > 0) await batch.commit();
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
    // workDate는 Flutter에서 DateTime(y,m,d) 로컬(KST)로 생성 후 UTC Timestamp로 저장됨
    const KST_OFFSET_MS = 9 * 60 * 60 * 1000;
    const nowKST = new Date(now.toDate().getTime() + KST_OFFSET_MS);
    const tomorrowKST = new Date(nowKST);
    tomorrowKST.setDate(tomorrowKST.getDate() + 1);
    tomorrowKST.setHours(0, 0, 0, 0);
    const tomorrowKSTEnd = new Date(tomorrowKST);
    tomorrowKSTEnd.setHours(23, 59, 59, 999);

    // Firestore 쿼리용: KST 경계를 UTC로 역변환
    const tomorrow = new Date(tomorrowKST.getTime() - KST_OFFSET_MS);
    const tomorrowEnd = new Date(tomorrowKSTEnd.getTime() - KST_OFFSET_MS);

    // 내일 근무 확정된 지원서 조회
    const applicationsSnapshot = await db
      .collection("applications")
      .where("status", "in", CONFIRMED_STATUSES)
      .where("workDate", ">=", Timestamp.fromDate(tomorrow))
      .where("workDate", "<=", Timestamp.fromDate(tomorrowEnd))
      .get();

    if (applicationsSnapshot.empty) {
      console.log("  ✅ [리마인더] 내일 근무 예정자 없음");
      return;
    }

    console.log(`  📋 [리마인더] 대상 지원서: ${applicationsSnapshot.size}건`);

    // 오늘(KST) 이미 발송된 workReminder userId 조회 — 재시도 시 중복 방지
    const todayKSTStart = new Date(nowKST);
    todayKSTStart.setHours(0, 0, 0, 0);
    const todayUTC = new Date(todayKSTStart.getTime() - KST_OFFSET_MS);
    const alreadySentSnap = await db
      .collection("notifications")
      .where("type", "==", "workReminder")
      .where("createdAt", ">=", Timestamp.fromDate(todayUTC))
      .get();
    const alreadySentUsers = new Set(
      alreadySentSnap.docs.map((d) => d.data().userId as string)
    );

    // userId별로 근무 목록 묶기 — 이미 발송된 사용자는 제외
    const userJobsMap = new Map<string, admin.firestore.QueryDocumentSnapshot[]>();
    for (const appDoc of applicationsSnapshot.docs) {
      const uid = appDoc.data().uid as string;
      if (alreadySentUsers.has(uid)) continue;
      if (!userJobsMap.has(uid)) userJobsMap.set(uid, []);
      userJobsMap.get(uid)!.push(appDoc);
    }

    if (userJobsMap.size === 0) {
      console.log("  ✅ [리마인더] 신규 발송 대상 없음 (모두 이미 발송됨)");
      return;
    }

    // user 문서 배치 읽기 (최대 30개 단위) — notifPrefs + fcmToken 동시 취득
    const userIds = [...userJobsMap.keys()];
    const userDataMap = new Map<string, admin.firestore.DocumentData>();
    for (let i = 0; i < userIds.length; i += 30) {
      const chunk = userIds.slice(i, i + 30);
      const refs = chunk.map((uid) => db.collection("users").doc(uid));
      const docs = await db.getAll(...refs);
      for (const doc of docs) {
        if (doc.exists && doc.data()) userDataMap.set(doc.id, doc.data()!);
      }
    }

    let sentCount = 0;

    for (const [userId, jobs] of userJobsMap.entries()) {
      try {
        const userData = userDataMap.get(userId);

        // 알림 본문 구성 — 여러 근무가 있으면 모두 표시
        let notifBody: string;
        let fcmBody: string;
        if (jobs.length === 1) {
          const d = jobs[0].data();
          notifBody =
            `${d.businessName}에서 내일 ${d.selectedWorkType} ` +
            `근무가 있습니다.\n시간: ${d.startTime}~${d.endTime}`;
          fcmBody = `${d.businessName} ${d.startTime} 출근`;
        } else {
          notifBody =
            `내일 ${jobs.length}건의 근무가 예정되어 있습니다.\n` +
            jobs
              .map((j) => `• ${j.data().businessName} ${j.data().startTime}~${j.data().endTime}`)
              .join("\n");
          fcmBody = `내일 ${jobs.length}건의 근무가 예정되어 있습니다`;
        }

        // 앱 내 알림 저장
        await db.collection("notifications").add({
          userId,
          type: "workReminder",
          title: "내일 근무 알림",
          body: notifBody,
          data: { applicationId: jobs[0].id, action: "applicationDetail" },
          isRead: false,
          createdAt: now,
        });

        // FCM 푸시 — workReminder 수신 설정 확인 (onNotificationCreated가 workReminder 스킵하므로 여기서 직접 처리)
        const notifPrefs = userData?.notifPrefs as Record<string, boolean> | undefined;
        if (notifPrefs?.["workReminder"] === false) {
          console.log(`    ⚠️ 근무 리마인더 FCM 스킵 (수신 차단): ${userId}`);
        } else {
          const fcmToken = userData?.fcmToken as string | undefined;
          await sendFCMToUser(
            userId,
            {
              title: "내일 근무 알림 📅",
              body: fcmBody,
              data: { type: "workReminder", applicationId: jobs[0].id },
            },
            fcmToken ?? null
          );
        }

        sentCount++;
      } catch (err) {
        console.error(`    ❌ [리마인더] userId ${userId} 처리 실패:`, err);
      }
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
// 📦 FCM 푸시 알림
// ═══════════════════════════════════════════════════════════

// 알림 type → notifPrefs 카테고리 키 매핑
// 매핑되지 않은 type(null 반환)은 항상 발송
function _getNotifCategory(type: string): string | null {
  const map: Record<string, string> = {
    workReminder:              "workReminder",
    newApplication:            "applicationUpdate",
    applicationApproved:       "applicationUpdate",
    applicationRejected:       "applicationUpdate",
    applicationCanceled:       "applicationUpdate",
    applicationCanceledAdmin:  "applicationUpdate",
    autoApplicationCanceled:   "applicationUpdate",
    REVIEW_REQUEST:            "reviewAlert",
    reviewAvailable:           "reviewAlert",
    contractSignRequested:     "contractAlert",
    contractExpiringReminder:  "contractAlert",
    contractRenewed:           "contractAlert",
    contractTerminating:       "contractAlert",
    wageConfirmed:             "wageAlert",
    attendanceWageChanged:     "wageAlert",
  };
  return map[type] ?? null;
}

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
  payload: FCMPayload,
  existingToken?: string | null
): Promise<void> {
  try {
    let fcmToken: string | undefined;
    if (existingToken !== undefined) {
      fcmToken = existingToken ?? undefined;
    } else {
      // 토큰이 전달되지 않은 경우에만 user 문서 읽기
      const userDoc = await db.collection("users").doc(userId).get();
      if (!userDoc.exists) return;
      fcmToken = userDoc.data()?.fcmToken as string | undefined;
    }

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

// ═══════════════════════════════════════════════════════════
// 🔄 고정근무 계약 만료 D-15 알림 및 D-0 자동 연장
// ═══════════════════════════════════════════════════════════

/**
 * 매 자정 실행:
 *   - D-15: 만료 15일 전 관리자에게 연장/종료 선택 알림
 *   - D-0 (무응답): 관리자 미결정 시 자동 1개월 연장 + 근무자 통보
 * @param {Timestamp} now - 현재 시간
 */
async function processContractRenewalChecks(now: Timestamp): Promise<void> {
  // Cloud Functions는 UTC로 실행 — KST(UTC+9) 기준 날짜 계산 필요
  // workEndDate는 Flutter에서 KST로 생성 후 UTC Timestamp로 저장됨
  const KST_OFFSET_MS = 9 * 60 * 60 * 1000;
  const nowKST = new Date(now.toDate().getTime() + KST_OFFSET_MS);
  const todayKST = new Date(nowKST);
  todayKST.setHours(0, 0, 0, 0);

  // D-15 기준일 (KST 하루 전체 → UTC 변환)
  const d15StartKST = new Date(todayKST);
  d15StartKST.setDate(d15StartKST.getDate() + 15);
  const d15EndKST = new Date(d15StartKST);
  d15EndKST.setHours(23, 59, 59, 999);
  const d15Start = Timestamp.fromDate(new Date(d15StartKST.getTime() - KST_OFFSET_MS));
  const d15End = Timestamp.fromDate(new Date(d15EndKST.getTime() - KST_OFFSET_MS));

  // D-0 기준일 (어제 KST 만료 = 오늘 새벽 자정 처리)
  const d0StartKST = new Date(todayKST);
  d0StartKST.setDate(d0StartKST.getDate() - 1); // 어제
  const d0Start = Timestamp.fromDate(new Date(d0StartKST.getTime() - KST_OFFSET_MS));
  const d0End = Timestamp.fromDate(new Date(todayKST.getTime() - KST_OFFSET_MS));

  let d15Count = 0;
  let d0Count = 0;

  try {
    // ── D-15: 만료 15일 전 알림 ──────────────────────────────
    const d15Snap = await db.collection("applications")
      .where("status", "in", CONFIRMED_STATUSES)
      .where("workEndDate", ">=", d15Start)
      .where("workEndDate", "<", d15End)
      .get();

    for (const doc of d15Snap.docs) {
      const app = doc.data();
      // 장기(workDays 있음) + 아직 알림 안 보낸 경우만
      if (!app.workDays || app.workDays.length === 0) continue;
      if (app.renewalNotifiedAt) continue;

      const expiryDateKST = new Date((app.workEndDate as Timestamp).toDate().getTime() + KST_OFFSET_MS);

      // 사용자 이름 조회 (applicantName 없을 경우 users 컬렉션 폴백)
      let workerName: string = app.applicantName ?? "";
      if (!workerName && app.uid) {
        const userDoc = await db.collection("users").doc(app.uid).get();
        workerName = userDoc.exists ? (userDoc.data()?.name ?? "근무자") : "근무자";
      }
      if (!workerName) workerName = "근무자";

      // 사업장 관리자 목록 조회
      const bizDoc = await db
        .collection("businesses").doc(app.businessId).get();
      const adminIds: string[] = bizDoc.exists ?
        (bizDoc.data()?.adminIds as string[] ?? []) :
        [];

      // 관리자 전원에게 알림
      for (const adminId of adminIds) {
        await db.collection("notifications").add({
          userId: adminId,
          type: "contractExpiringReminder",
          title: "계약 만료 임박",
          body: `${workerName}님의 계약이 ` +
            `${expiryDateKST.getUTCMonth() + 1}/${expiryDateKST.getUTCDate()}에 ` +
            "만료됩니다. 연장 또는 종료를 선택해 주세요.",
          data: {
            applicationId: doc.id,
            expiryDate: new Date(expiryDateKST.getTime() - KST_OFFSET_MS).toISOString(),
            screen: "contractRenewal",
          },
          isRead: false,
          createdAt: now,
        });
      }

      // renewalNotifiedAt 기록
      await doc.ref.update({renewalNotifiedAt: now});
      d15Count++;
    }

    console.log(`  ✅ [D-15 알림] ${d15Count}건 발송`);

    // ── D-0: 무응답 자동 연장 ────────────────────────────────
    const d0Snap = await db.collection("applications")
      .where("status", "in", CONFIRMED_STATUSES)
      .where("workEndDate", ">=", d0Start)
      .where("workEndDate", "<", d0End)
      .get();

    for (const doc of d0Snap.docs) {
      const app = doc.data();
      if (!app.workDays || app.workDays.length === 0) continue;
      if (app.renewalDecision) continue; // 이미 결정됨

      const oldEndDate = (app.workEndDate as Timestamp).toDate();
      // 새 계약: 다음날 시작, 31일 후 종료
      const newStartDate = new Date(oldEndDate);
      newStartDate.setDate(newStartDate.getDate() + 1);
      const newEndDate = new Date(newStartDate);
      newEndDate.setDate(newEndDate.getDate() + 30);

      // 새 Application 생성 + 기존 Application 갱신 — 원자적 배치
      const newAppRef = db.collection("applications").doc();
      const renewBatch = db.batch();
      renewBatch.set(newAppRef, {
        ...app,
        workDate: Timestamp.fromDate(newStartDate),
        workEndDate: Timestamp.fromDate(newEndDate),
        confirmedAt: now,
        appliedAt: now,
        renewedFromApplicationId: doc.id,
        renewalDecision: null,
        renewalNotifiedAt: null,
        desiredStartDate: null,
        statusHistory: [],
        resignStatus: null,
        resignRequestedAt: null,
        resignRequestDate: null,
        actualResignDate: null,
        terminationStatus: null,
        terminationRequestedAt: null,
        terminationEffectiveDate: null,
        terminationRejectReason: null,
      });
      // 기존 Application 갱신 — 배치 실패 시 둘 다 미커밋 → 중복 연장 방지
      renewBatch.update(doc.ref, {renewalDecision: "EXTEND"});
      await renewBatch.commit();

      // 근무자에게 연장 알림
      await db.collection("notifications").add({
        userId: app.uid,
        type: "contractRenewed",
        title: "계약 자동 연장",
        body: `${app.businessName} 계약이 ` +
          `${new Date(newEndDate.getTime() + KST_OFFSET_MS).getUTCMonth() + 1}/${new Date(newEndDate.getTime() + KST_OFFSET_MS).getUTCDate()}` +
          "까지 자동 연장되었습니다.",
        data: {
          applicationId: newAppRef.id,
          screen: "mySchedule",
        },
        isRead: false,
        createdAt: now,
      });

      d0Count++;
    }

    console.log(`  ✅ [D-0 자동연장] ${d0Count}건 처리`);
  } catch (error) {
    console.error("❌ [계약 연장 처리] 오류:", error);
  }
}

// ═══════════════════════════════════════════════════════════
// 🔧 사업장/TO 주소 필드 마이그레이션 (1회성)
// ═══════════════════════════════════════════════════════════

/**
 * 주소 문자열에서 시/군/구 추출
 * @param {string | undefined} address 전체 주소 문자열
 * @return {string | null} 시/군/구 문자열 또는 null
 */
function parseAddressCity(address: string | undefined): string | null {
  if (!address) return null;
  const parts = address.split(" ");
  if (parts.length < 2) return null;
  for (let i = 0; i < parts.length; i++) {
    const part = parts[i];
    const isCityLike = part.endsWith("시") ||
      part.endsWith("구") || part.endsWith("군");
    if (isCityLike) {
      const isTopLevel = part.includes("특별") ||
        part.includes("광역") || part.endsWith("도");
      if (i > 0 || !isTopLevel) return part;
    }
  }
  return parts.length > 1 ? parts[1] : null;
}

/**
 * 주소 문자열에서 읍/면/동 추출
 * @param {string | undefined} address 전체 주소 문자열
 * @return {string | null} 읍/면/동 문자열 또는 null
 */
function parseAddressDistrict(address: string | undefined): string | null {
  if (!address) return null;
  const parts = address.split(" ");
  for (const part of parts) {
    const isDistrictLike = part.endsWith("동") ||
      part.endsWith("읍") || part.endsWith("면") || part.endsWith("리");
    if (isDistrictLike && !/\d/.test(part)) return part;
  }
  return null;
}

export const migrateAddressFields = onCall(
  {region: "asia-northeast3"},
  async (request) => {
    // SUPER_ADMIN만 호출 가능
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    }
    const callerRole = (await db.collection("users").doc(request.auth.uid).get()).data()?.role;
    if (callerRole !== "SUPER_ADMIN") {
      throw new HttpsError("permission-denied", "슈퍼관리자만 실행할 수 있습니다.");
    }
    const db2: Firestore = getFirestore();
    const BATCH_LIMIT = 499;
    let bizUpdated = 0;
    let toUpdated = 0;

    /**
     * 누적된 업데이트를 500개 단위로 나눠 커밋
     * @param {Array} ops - 업데이트 대상 목록
     */
    async function commitInChunks(
      ops: Array<{
        ref: FirebaseFirestore.DocumentReference;
        fields: Record<string, string>;
      }>
    ): Promise<void> {
      for (let i = 0; i < ops.length; i += BATCH_LIMIT) {
        const chunk = ops.slice(i, i + BATCH_LIMIT);
        const batch = db2.batch();
        for (const op of chunk) batch.update(op.ref, op.fields);
        await batch.commit();
      }
    }

    // 1. businesses 마이그레이션
    const bizSnap = await db2.collection("businesses").get();
    const bizOps: Array<{
      ref: FirebaseFirestore.DocumentReference;
      fields: Record<string, string>;
    }> = [];
    for (const doc of bizSnap.docs) {
      const data = doc.data();
      if (data.city || data.district) continue;
      const address = data.address as string | undefined;
      const city = parseAddressCity(address);
      const district = parseAddressDistrict(address);
      if (city || district) {
        bizOps.push({
          ref: doc.ref,
          fields: {
            ...(city ? {city} : {}),
            ...(district ? {district} : {}),
          },
        });
        bizUpdated++;
      }
    }
    await commitInChunks(bizOps);

    // 2. tos 마이그레이션 — businessCity가 없는 TO만 처리
    const tosSnap = await db2.collection("tos").get();
    const tosOps: Array<{
      ref: FirebaseFirestore.DocumentReference;
      fields: Record<string, string>;
    }> = [];
    for (const doc of tosSnap.docs) {
      const data = doc.data();
      if (data.businessCity || data.businessDistrict) continue;
      const address = data.businessAddress as string | undefined;
      const city = parseAddressCity(address);
      const district = parseAddressDistrict(address);
      if (city || district) {
        tosOps.push({
          ref: doc.ref,
          fields: {
            ...(city ? {businessCity: city} : {}),
            ...(district ? {businessDistrict: district} : {}),
          },
        });
        toUpdated++;
      }
    }
    await commitInChunks(tosOps);

    console.log(`✅ 마이그레이션 완료: businesses=${bizUpdated}, tos=${toUpdated}`);
    return {bizUpdated, toUpdated};
  }
);

// ═══════════════════════════════════════════════════════════
// 📱 NCP SENS SMS 인증 (휴대폰 문자 인증)
// ═══════════════════════════════════════════════════════════
//
// 🔧 연결 방법:
//   firebase functions:config:set \
//     sens.service_id="YOUR_SERVICE_ID" \
//     sens.access_key="YOUR_ACCESS_KEY" \
//     sens.secret_key="YOUR_SECRET_KEY" \
//     sens.from_number="01000000000"
//
//   또는 .env 파일:
//     SENS_SERVICE_ID=...
//     SENS_ACCESS_KEY=...
//     SENS_SECRET_KEY=...
//     SENS_FROM_NUMBER=...
// ═══════════════════════════════════════════════════════════

// NCP SENS API 설정 — 나중에 환경변수로 주입
const SENS_SERVICE_ID = process.env.SENS_SERVICE_ID ?? "PLACEHOLDER_SERVICE_ID";
const SENS_ACCESS_KEY = process.env.SENS_ACCESS_KEY ?? "PLACEHOLDER_ACCESS_KEY";
const SENS_SECRET_KEY = process.env.SENS_SECRET_KEY ?? "PLACEHOLDER_SECRET_KEY";
const SENS_FROM_NUMBER = process.env.SENS_FROM_NUMBER ?? "01000000000";
const SENS_ENABLED = SENS_SERVICE_ID !== "PLACEHOLDER_SERVICE_ID";

/** NCP SENS HMAC-SHA256 서명 생성 */
function makeSensSignature(
  method: string,
  url: string,
  timestamp: string
): string {
  const message = `${method} ${url}\n${timestamp}\n${SENS_ACCESS_KEY}`;
  return crypto
    .createHmac("sha256", SENS_SECRET_KEY)
    .update(message)
    .digest("base64");
}

/** NCP SENS로 SMS 발송 (promise wrapper) */
async function sendSensSms(to: string, content: string): Promise<void> {
  if (!SENS_ENABLED) {
    console.log(`[SENS MOCK] SMS to ${to}: ${content}`);
    return;
  }

  const timestamp = Date.now().toString();
  const urlPath = `/sms/v2/services/${SENS_SERVICE_ID}/messages`;
  const signature = makeSensSignature("POST", urlPath, timestamp);

  const body = JSON.stringify({
    type: "SMS",
    contentType: "COMM",
    countryCode: "82",
    from: SENS_FROM_NUMBER,
    content,
    messages: [{to: to.replace(/^0/, "").replace(/-/g, "")}],
  });

  await new Promise<void>((resolve, reject) => {
    const req = https.request(
      {
        hostname: "sens.apigw.ntruss.com",
        path: urlPath,
        method: "POST",
        headers: {
          "Content-Type": "application/json; charset=utf-8",
          "x-ncp-apigw-timestamp": timestamp,
          "x-ncp-iam-access-key": SENS_ACCESS_KEY,
          "x-ncp-apigw-signature-v2": signature,
        },
      },
      (res) => {
        let data = "";
        res.on("data", (chunk) => (data += chunk));
        res.on("end", () => {
          if (res.statusCode === 202) {
            resolve();
          } else {
            reject(new Error(`SENS API error ${res.statusCode}: ${data}`));
          }
        });
      }
    );
    req.on("error", reject);
    req.write(body);
    req.end();
  });
}

/**
 * 휴대폰 SMS 인증번호 발송
 * - 6자리 난수 생성
 * - Firestore sms_verifications/{phone}에 코드 저장 (5분 유효)
 * - NCP SENS로 문자 발송 (SENS_ENABLED=false이면 콘솔 출력만)
 */
export const sendSmsVerificationCode = onCall(
  {region: "asia-northeast3"},
  async (request) => {
    const phone = (request.data.phone as string | undefined)?.replace(/-/g, "");

    if (!phone || !/^01[0-9]{8,9}$/.test(phone)) {
      throw new HttpsError(
        "invalid-argument",
        "올바른 휴대폰 번호를 입력해주세요."
      );
    }

    // 6자리 코드 생성 (트랜잭션 전에 미리 생성)
    const code = String(crypto.randomInt(100000, 999999));
    const expiredAt = new Date(Date.now() + 5 * 60 * 1000); // 5분 유효

    // 1분 내 재발송 방지 + set을 트랜잭션으로 묶어 동시 요청 차단
    const verDoc = db.collection("sms_verifications").doc(phone);
    await db.runTransaction(async (tx) => {
      const existing = await tx.get(verDoc);
      if (existing.exists) {
        const createdAt = (existing.data()?.createdAt as Timestamp)?.toDate();
        if (createdAt && Date.now() - createdAt.getTime() < 60_000) {
          throw new HttpsError(
            "resource-exhausted",
            "1분 후 다시 시도해주세요."
          );
        }
      }
      tx.set(verDoc, {
        code,
        expiredAt: Timestamp.fromDate(expiredAt),
        createdAt: Timestamp.now(),
        attempts: 0,
        verified: false,
      });
    });

    await sendSensSms(phone, `[ALFit] 인증번호: ${code} (5분 유효)`);

    console.log(`✅ SMS 발송 완료: ${phone} (SENS_ENABLED=${SENS_ENABLED})`);
    return {success: true};
  }
);

/**
 * 휴대폰 SMS 인증번호 확인
 * - 코드 일치/만료/시도횟수 초과 검사
 * - 성공 시 verified: true 업데이트
 */
export const verifySmsCode = onCall(
  {region: "asia-northeast3"},
  async (request) => {
    const phone = (request.data.phone as string | undefined)?.replace(/-/g, "");
    const code = request.data.code as string | undefined;

    if (!phone || !code) {
      throw new HttpsError("invalid-argument", "전화번호와 인증번호를 입력해주세요.");
    }

    const docRef = db.collection("sms_verifications").doc(phone);

    // 읽기+업데이트를 트랜잭션으로 묶어 병렬 요청에 의한 브루트포스 제한 우회 차단
    let result: {valid: boolean; reason?: string} = {valid: false, reason: "no_code"};
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(docRef);
      if (!snap.exists) {
        result = {valid: false, reason: "no_code"};
        return;
      }

      const data = snap.data()!;
      const attempts: number = data.attempts ?? 0;

      if (attempts >= 5) {
        result = {valid: false, reason: "too_many_attempts"};
        return;
      }

      const expiredAt = (data.expiredAt as Timestamp).toDate();
      if (new Date() > expiredAt) {
        result = {valid: false, reason: "expired"};
        return;
      }

      if (data.code !== code) {
        tx.update(docRef, {attempts: admin.firestore.FieldValue.increment(1)});
        result = {valid: false, reason: "wrong_code"};
        return;
      }

      // 인증 성공 — 코드 무효화
      tx.update(docRef, {verified: true, attempts: admin.firestore.FieldValue.increment(1)});
      result = {valid: true};
    });
    return result;
  }
);

// ═══════════════════════════════════════════════════════════
// 🗑️ 사업장 삭제 시 연관 데이터 정리 (BUG-5)
// ═══════════════════════════════════════════════════════════

export const onBusinessDeleted = onDocumentDeleted(
  {
    document: "businesses/{businessId}",
    region: "asia-northeast3",
  },
  async (event) => {
    const businessId = event.params.businessId;
    console.log(`사업장 삭제 cascade 시작: ${businessId}`);

    async function deleteSubcollection(collPath: string) {
      const snap = await db.collection(collPath).get();
      const batches: FirebaseFirestore.WriteBatch[] = [];
      let batch = db.batch();
      let count = 0;
      for (const doc of snap.docs) {
        batch.delete(doc.ref);
        count++;
        if (count % 500 === 0) {
          batches.push(batch);
          batch = db.batch();
        }
      }
      if (count % 500 !== 0) batches.push(batch);
      await Promise.all(batches.map((b) => b.commit()));
    }

    // 서브컬렉션 삭제
    await deleteSubcollection(`businesses/${businessId}/workTypes`);
    await deleteSubcollection(`businesses/${businessId}/members`);

    // 해당 사업장의 TO 목록
    const tosSnap = await db
      .collection("tos")
      .where("businessId", "==", businessId)
      .get();

    if (!tosSnap.empty) {
      const toIds = tosSnap.docs.map((d) => d.id);
      const chunkSize = 30;

      for (let i = 0; i < toIds.length; i += chunkSize) {
        const chunk = toIds.slice(i, i + chunkSize);

        // CONFIRMED 지원서 → CANCELED
        const appsSnap = await db
          .collection("applications")
          .where("toId", "in", chunk)
          .where("status", "in", ["CONFIRMED", "CONTRACT_PENDING"])
          .get();

        if (!appsSnap.empty) {
          const appBatch = db.batch();
          for (const doc of appsSnap.docs) {
            appBatch.update(doc.ref, {
              status: "CANCELED",
              cancelReason: "BUSINESS_DELETED",
              canceledAt: Timestamp.now(),
            });
          }
          await appBatch.commit();

          // scheduled attendance → absent
          const appIds = appsSnap.docs.map((d) => d.id);
          for (let j = 0; j < appIds.length; j += chunkSize) {
            const appChunk = appIds.slice(j, j + chunkSize);
            const attSnap = await db
              .collection("attendance")
              .where("applicationId", "in", appChunk)
              .where("status", "==", "scheduled")
              .get();
            if (!attSnap.empty) {
              const attBatch = db.batch();
              for (const doc of attSnap.docs) {
                attBatch.update(doc.ref, {status: "absent", updatedAt: Timestamp.now()});
              }
              await attBatch.commit();
            }
          }
        }
      }

      // TO 문서 삭제
      const tosBatch = db.batch();
      for (const doc of tosSnap.docs) {
        tosBatch.delete(doc.ref);
      }
      await tosBatch.commit();
    }

    console.log(`사업장 삭제 cascade 완료: ${businessId}`);
  }
);
