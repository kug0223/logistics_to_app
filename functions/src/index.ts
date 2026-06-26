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
    const storedEmail = userData.email as string | undefined;

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
    const now = admin.firestore.Timestamp.now();
    await db.runTransaction(async (tx) => {
      const doc = await tx.get(docRef);
      if (!doc.exists) {
        throw new HttpsError("not-found", "인증 코드를 먼저 요청해주세요.");
      }
      const data = doc.data();
      if (!data) {
        throw new HttpsError("not-found", "인증 코드를 찾을 수 없습니다.");
      }
      const expiresAtRaw = data.expiresAt;
      if (!expiresAtRaw || !(expiresAtRaw instanceof Timestamp)) {
        throw new HttpsError("internal", "만료 시간 데이터 오류");
      }
      const expiresAt = expiresAtRaw.toDate();
      const attempts = (data.attempts as number) ?? 0;

      // 이미 사용된 코드 거부
      if (data.used === true) {
        throw new HttpsError("invalid-argument", "이미 사용된 인증 코드입니다. 다시 요청해주세요.");
      }
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
      // 검증 성공 → 즉시 삭제 대신 used 마킹 (원자성 보장)
      // 비밀번호 변경 성공 후 최종 삭제
      tx.update(docRef, {used: true, usedAt: now});
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
    // [특이사항] SHA-256 단순 해시로 비밀번호 이력 저장 — 강화가 필요하다면 PBKDF2 사용 권장
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

    // 비밀번호 변경 성공 → 코드 문서 최종 삭제 (used 마킹 해제 불가 보장)
    await docRef.delete();

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
// 🔔 알림 생성 Callable — 클라이언트 직접 write 차단 후 이 함수로 단일화
// Admin SDK로 쓰므로 Firestore 보안 규칙(allow create: if false)을 우회
// ═══════════════════════════════════════════════════════════

export const createNotification = onCall(
  {region: "asia-northeast3"},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    }
    const data = request.data as Record<string, unknown>;
    const userId = data.userId as string | undefined;
    if (!userId || typeof userId !== "string") {
      throw new HttpsError("invalid-argument", "userId가 필요합니다.");
    }

    // [특이사항] 알림은 항상 타인에게도 보낼 수 있어야 함 (지원자→관리자, 관리자→지원자).
    // Admin SDK 우회이므로 최상위 필드와 data 서브필드 모두 화이트리스트로 임의 저장을 차단한다.
    // data 서브필드 허용 키: FCM 딥링크 라우팅에서 실제 사용되는 키만 포함.
    // 허용 외 키는 자동 제거 — XSS·딥링크 조작 방지.
    const rawData = (data.data as Record<string, unknown> | undefined) ?? {};
    const allowedDataKeys = new Set([
      "screen", "action", "applicationId", "businessId", "toId",
      "requestId", "reviewId", "contractId", "attendanceId", "invitationId",
    ]);
    const filteredData: Record<string, unknown> = {};
    for (const key of Object.keys(rawData)) {
      if (allowedDataKeys.has(key)) filteredData[key] = String(rawData[key]);
    }

    const payload: Record<string, unknown> = {
      userId,
      title: data.title as string | undefined,
      body: data.body as string | undefined,
      type: (data.type as string | undefined) ?? "general",
      data: filteredData,
      isRead: false,
      createdAt: Timestamp.now(),
    };

    const docRef = await db
      .collection("users")
      .doc(userId)
      .collection("notifications")
      .add(payload);

    console.log(`✅ [알림 생성] userId=${userId}, id=${docRef.id}`);
    return {id: docRef.id};
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

    // [SEC-001] before 값 사용 — after는 수신자가 targetUid/businessId를 변조했을 수 있음
    const targetUid = before.targetUid as string | undefined;
    const businessId = before.businessId as string | undefined;
    if (!targetUid || !businessId) {
      console.error("⚠️ [초대수락 트리거] targetUid 또는 businessId 누락", before);
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
    document: "users/{userId}/notifications/{notificationId}",
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
    // userId는 경로 변수에서 직접 추출 — 문서 내 필드보다 신뢰성 높음
    const userId = event.params.userId as string;
    const title = notificationData.title as string | undefined;
    const body = notificationData.body as string | undefined;
    const type = notificationData.type as string | undefined;

    if (!title) {
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
    const notifRef = db.collection("users").doc(userId).collection("notifications").doc(notificationId);
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

      // fcmTokens 배열 우선, 없으면 단일 fcmToken으로 폴백 (하위 호환)
      const tokenArray = userData?.fcmTokens as string[] | undefined;
      const singleToken = userData?.fcmToken as string | undefined;
      const fcmTokens: string[] = tokenArray && tokenArray.length > 0
        ? tokenArray
        : (singleToken ? [singleToken] : []);

      if (fcmTokens.length === 0) {
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

      // 멀티 디바이스: 토큰 배열 순회 발송
      let successCount = 0;
      for (const token of fcmTokens) {
        try {
          await admin.messaging().send({
            token: token,
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
          successCount++;
        } catch (tokenError: unknown) {
          const errMsg = tokenError instanceof Error ? tokenError.message : "";
          if (
            errMsg.includes("not-registered") ||
            errMsg.includes("invalid-registration-token")
          ) {
            // 만료 토큰: fcmToken 단일 필드 + fcmTokens 배열 양쪽 정리
            console.log(`⚠️ [알림 트리거] 만료 토큰 정리: ${userId}, token=...${token.slice(-6)}`);
            await db.collection("users").doc(userId).update({
              fcmToken: admin.firestore.FieldValue.delete(),
              fcmTokens: admin.firestore.FieldValue.arrayRemove(token),
            });
          } else {
            console.error(`❌ [알림 트리거] FCM 실패 (${userId}):`, tokenError);
          }
        }
      }

      if (successCount > 0) {
        console.log(`✅ [알림 트리거] FCM 발송 완료: ${userId} (${successCount}/${fcmTokens.length}디바이스)`);
      }
    } catch (error: unknown) {
      console.error(`❌ [알림 트리거] 예외 (${userId}):`, error);
    }
  }
);

// ═══════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════
// 🔥 통합 마스터 스케줄러 (매 시간 정각 실행)
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
    // [특이사항] Cloud Scheduler 재시도 시 minute < 10 윈도우 내 동일 작업 중복 실행 가능 — 각 작업은 idempotency로 자체 방어
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

      // [TODO] idCardAccessExpiringSoon: 신분증 열람 권한 만료 D-1 알림 미구현
      // approvedAccess 중 expiresAt이 내일인 항목 조회 → 근무자에게 알림 발송 필요
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
    if (data.status === "NO_SHOW" || data.status === "missed_checkout" || data.canceledWithApplication === true) continue;
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
        // 이미 존재 — workerName 누락인 경우만 보완 (구버전 CF가 workerName 없이 생성한 문서)
        try {
          const existing = await requestRef.get();
          if (existing.exists && !existing.data()?.workerName) {
            await requestRef.update({ workerName });
          }
        } catch {
          // 무시
        }
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
        // 이미 존재 — workerName 누락인 경우만 보완 (구버전 CF가 workerName 없이 생성한 문서)
        try {
          const existing = await requestRef.get();
          if (existing.exists && !existing.data()?.workerName) {
            await requestRef.update({ workerName });
          }
        } catch {
          // 무시
        }
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

    let batch = db.batch();
    let batchCount = 0;

    for (const reqDoc of snap.docs) {
      const req = reqDoc.data();
      const reviewIds: string[] = [];

      if (req.adminReviewId) reviewIds.push(req.adminReviewId as string);
      if (req.workerReviewId) reviewIds.push(req.workerReviewId as string);

      // [특이사항] reqDoc 1건당 최대 3연산(리뷰2 + 요청1). 루프 진입 전에 헤드룸 확인하여
      // 500 초과 방지. 기존 코드는 추가 후에 체크해 최대 501까지 도달 가능했음.
      if (batchCount + reviewIds.length + 1 > 499) {
        await batch.commit();
        batch = db.batch();
        batchCount = 0;
      }

      if (reviewIds.length === 0) {
        // 양쪽 다 작성 안 함 → 요청만 만료 처리
        batch.update(reqDoc.ref, {isPublished: true, publishedAt: now});
        batchCount++;
      } else {
        // 작성된 리뷰 공개
        for (const rid of reviewIds) {
          batch.update(db.collection("monthly_reviews").doc(rid), {
            isPublished: true,
            publishedAt: now,
          });
          batchCount++;
        }
        batch.update(reqDoc.ref, {isPublished: true, publishedAt: now});
        batchCount++;
      }

      // 통계 업데이트 대상 수집
      if (req.adminReviewId && req.workerId) {
        userStatsToUpdate.add(req.workerId as string);
      }
      if (req.workerReviewId && req.businessId) {
        businessStatsToUpdate.add(req.businessId as string);
      }

      console.log(`    → ${reqDoc.id} 자동 공개`);
    }

    if (batchCount > 0) await batch.commit();

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

    await db.collection("users").doc(userId).collection("notifications").add({
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
  const publishedTOIds: string[] = [];
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
    publishedTOIds.push(doc.id);

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

  // [008] 공개된 TO의 슬롯 중 visibleFrom이 이미 지난 것은 삭제 — 즉시 노출
  // (publishMode 변경이나 조기 게시로 visibleFrom이 과거 일자에 남아있는 경우 대응)
  for (const toId of publishedTOIds) {
    try {
      const slotsSnap = await db
        .collection("tos").doc(toId)
        .collection("slots").get();
      if (slotsSnap.empty) continue;
      let slotBatch = db.batch();
      let slotCount = 0;
      for (const slot of slotsSnap.docs) {
        const vf = slot.data().visibleFrom as Timestamp | undefined;
        if (vf && vf.toMillis() <= now.toMillis()) {
          slotBatch.update(slot.ref, { visibleFrom: admin.firestore.FieldValue.delete() });
          slotCount++;
          if (slotCount >= 499) {
            await slotBatch.commit();
            slotBatch = db.batch();
            slotCount = 0;
          }
        }
      }
      if (slotCount > 0) await slotBatch.commit();
    } catch (e) {
      console.error(`  ⚠️ [예약공개] ${toId} 슬롯 visibleFrom 정리 실패:`, e);
    }
  }

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

  let batch = db.batch();
  let batchCount = 0;

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

    batch.update(toDoc.ref, {workDetails: updatedWorkDetails});
    batchCount++;
    if (batchCount >= 499) {
      await batch.commit();
      batch = db.batch();
      batchCount = 0;
    }

    totalClosed += expiredItems.length;
    affectedTOIds.add(toId);
    expiredItems.forEach((wd: any) =>
      console.log(`    → ${toId}/${wd.workType} WorkDetail 마감`)
    );
    if (toData.groupId) affectedGroupIds.add(toData.groupId);
  }

  if (batchCount > 0) await batch.commit();

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

    // [특이사항] 개별 슬롯 업데이트 실패 시 try/catch 없으면 나머지 슬롯 처리가 중단됨.
    // 1건 실패를 로그로 남기고 계속 진행한다.
    try {
      await slotDoc.ref.update(slotUpdate);
    } catch (e) {
      console.error(`⚠️ [슬롯 WorkDetail 마감] 슬롯 ${slotDoc.id} 업데이트 실패:`, e);
      if (allDetailsClosed) totalClosedSlots--; // 실패했으므로 카운트 롤백
      continue;
    }
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
      .collectionGroup("notifications")
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
        await db.collection("users").doc(userId).collection("notifications").add({
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
          // [G-001] fcmTokens 배열 우선 사용, 없으면 레거시 fcmToken 단일 필드 폴백
          const tokens: string[] =
            (userData?.fcmTokens as string[] | undefined)?.filter(Boolean) ??
            (userData?.fcmToken ? [userData.fcmToken as string] : []);
          const fcmPayload = {
            title: "내일 근무 알림 📅",
            body: fcmBody,
            data: { type: "workReminder", applicationId: jobs[0].id },
          };
          await Promise.all(tokens.map((token) => sendFCMToUser(userId, fcmPayload, token)));
          if (tokens.length === 0) {
            console.log(`    ⚠️ FCM 토큰 없음 (리마인더 스킵): ${userId}`);
          }
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

    let integrityBatch = db.batch();
    let integrityBatchCount = 0;

    for (const toDoc of activeTOs.docs) {
      const toData = toDoc.data();

      // closedBy 있음 = 관리자 직접마감 → 정합성 검사 대상 아님
      if (toData.closedBy != null) continue;

      const deadline = toData.applicationDeadline as Timestamp | null;
      if (deadline && deadline.toMillis() <= now.toMillis()) {
        integrityBatch.update(toDoc.ref, {
          status: "CLOSED",
          closedAt: now,
          closedReason: "INTEGRITY_CHECK",
          statusUpdatedAt: now,
        });
        integrityBatchCount++;
        if (integrityBatchCount >= 499) {
          await integrityBatch.commit();
          integrityBatch = db.batch();
          integrityBatchCount = 0;
        }
        fixedCount++;
        console.log(`    → TO ${toDoc.id} 상태 수정`);
      }
    }

    if (integrityBatchCount > 0) await integrityBatch.commit();

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
    applicationConfirmed:      "applicationUpdate",   // 수정: applicationApproved → applicationConfirmed
    applicationRejected:       "applicationUpdate",
    applicationCanceled:       "applicationUpdate",
    confirmationCanceled:      "applicationUpdate",   // 추가: 확정 취소
    applicationCanceledAdmin:  "applicationUpdate",
    autoApplicationCanceled:   "applicationUpdate",
    REVIEW_REQUEST:            "reviewAlert",
    reviewAvailable:           "reviewAlert",
    reviewReceived:            "reviewAlert",          // 추가
    contractSignRequested:     "contractAlert",
    contractExpiringReminder:  "contractAlert",
    contractRenewed:           "contractAlert",
    contractTerminating:       "contractAlert",
    terminationRequested:      "contractAlert",        // 추가
    terminationApproved:       "contractAlert",        // 추가
    resignRequested:           "contractAlert",        // 추가
    resignApproved:            "contractAlert",        // 추가
    resignRejected:            "contractAlert",        // 추가
    wageConfirmed:             "wageAlert",
    wageCancelConfirmed:       "wageAlert",            // 추가
    attendanceWageChanged:     "wageAlert",
    wageTransferred:           "wageAlert",            // 추가: 임금 지급 완료
    retroactiveDeductionAlert: "wageAlert",            // 추가: 소급 공제 알림
    terminationRejected:       "contractAlert",        // 추가: 계약 종료 거절
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
  let fcmToken: string | undefined;  // catch 블록에서도 접근 가능하도록 try 밖 선언
  try {
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
      console.log(`    ⚠️ 만료된 FCM 토큰 정리: ${userId}`);
      const updates: Record<string, unknown> = {
        fcmToken: admin.firestore.FieldValue.delete(),
      };
      if (fcmToken) {
        updates.fcmTokens = admin.firestore.FieldValue.arrayRemove(fcmToken);
      }
      await db.collection("users").doc(userId).update(updates);
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

    // [특이사항] 루프 안에서 users/businesses를 개별 순차 조회하면 N×2 I/O → 타임아웃 위험.
    // 처리 대상을 먼저 필터링한 뒤 고유 uid/businessId를 병렬 pre-fetch로 해결한다.
    const d15Candidates = d15Snap.docs.filter((doc) => {
      const app = doc.data();
      return app.workDays?.length > 0 && !app.renewalDecision && !app.renewalNotifiedAt;
    });

    const uidsNeedingLookup = [...new Set(
      d15Candidates
        .filter((doc) => !doc.data().applicantName && doc.data().uid)
        .map((doc) => doc.data().uid as string),
    )];
    const d15BizIds = [...new Set(
      d15Candidates
        .filter((doc) => doc.data().businessId)
        .map((doc) => doc.data().businessId as string),
    )];

    const [prefetchedUsers, prefetchedBiz] = await Promise.all([
      uidsNeedingLookup.length > 0
        ? Promise.all(uidsNeedingLookup.map((uid) => db.collection("users").doc(uid).get()))
        : Promise.resolve([]),
      d15BizIds.length > 0
        ? Promise.all(d15BizIds.map((id) => db.collection("businesses").doc(id).get()))
        : Promise.resolve([]),
    ]);

    const d15UserMap = new Map(prefetchedUsers.map((doc) => [doc.id, doc.data()]));
    const d15BizMap = new Map(prefetchedBiz.map((doc) => [doc.id, doc.data()]));

    for (const doc of d15Candidates) {
      const app = doc.data();
      const expiryDateKST = new Date((app.workEndDate as Timestamp).toDate().getTime() + KST_OFFSET_MS);

      // 사용자 이름 (pre-fetched map 사용)
      let workerName: string = app.applicantName ?? "";
      if (!workerName && app.uid) {
        const userData = d15UserMap.get(app.uid as string);
        workerName = userData?.name ?? "근무자";
      }
      if (!workerName) workerName = "근무자";

      // 사업장 관리자 목록 (pre-fetched map 사용)
      const bizData = d15BizMap.get(app.businessId as string);
      const adminIds: string[] = (bizData?.adminIds as string[]) ?? [];

      // notifRef를 트랜잭션 외부에서 미리 생성 — 재시도 시 동일 ID 재사용으로 중복 알림 방지
      const notifRefs = adminIds.map((adminId) =>
        db.collection("users").doc(adminId).collection("notifications").doc()
      );

      // 트랜잭션으로 중복 발송 방지
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(doc.ref);
        if (snap.data()?.renewalNotifiedAt) return; // 이미 발송됨

        // 관리자 전원에게 알림
        for (let i = 0; i < adminIds.length; i++) {
          const adminId = adminIds[i];
          const notifRef = notifRefs[i];
          tx.set(notifRef, {
            userId: adminId,
            type: "contractExpiringReminder",
            title: "계약 만료 임박",
            body: `${workerName}님의 계약이 ` +
              `${expiryDateKST.getUTCMonth() + 1}/${expiryDateKST.getUTCDate()}에 ` +
              "만료됩니다. 연장 또는 종료를 선택해 주세요.",
            data: {
              applicationId: doc.id,
              businessId: app.businessId,
              expiryDate: new Date(expiryDateKST.getTime() - KST_OFFSET_MS).toISOString(),
              screen: "contractRenewal",
            },
            isRead: false,
            createdAt: now,
          });
        }
        tx.update(doc.ref, {renewalNotifiedAt: now});
      });
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
      const origWorkDate = (app.workDate as Timestamp).toDate();

      // [BUG-FIX] L-4: Use desiredStartDate (if present) as the base for month calculation,
      // matching Flutter's createRenewedApplication() logic (application_firestore.dart:2236).
      const startDate = app.desiredStartDate
        ? (app.desiredStartDate as Timestamp).toDate()
        : origWorkDate;

      // Flutter와 동일한 개월 수 기반 계산
      const contractMonths =
        (oldEndDate.getFullYear() - startDate.getFullYear()) * 12 +
        (oldEndDate.getMonth() - startDate.getMonth());
      const renewalMonths = contractMonths > 0 ? contractMonths : 1;

      // 새 계약 시작: 다음날
      const newStartDate = new Date(oldEndDate);
      newStartDate.setDate(newStartDate.getDate() + 1);

      // 새 계약 종료: 기존 종료일 기준 renewalMonths 개월 후 (같은 날짜, 월말 clamp)
      const rawEndYear = oldEndDate.getFullYear() + Math.floor((oldEndDate.getMonth() + renewalMonths) / 12);
      const rawEndMonthZero = (oldEndDate.getMonth() + renewalMonths) % 12; // 0-based
      const lastDayOfMonth = new Date(rawEndYear, rawEndMonthZero + 1, 0).getDate();
      const newEndDate = new Date(rawEndYear, rawEndMonthZero, Math.min(oldEndDate.getDate(), lastDayOfMonth));

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
        resignApprovedAt: null,
        resignApprovedBy: null,
        resignRejectReason: null,
        actualResignDate: null,
        terminationStatus: null,
        terminationRequestedAt: null,
        terminationReason: null,
        terminationEffectiveDate: null,
        terminationRequestedByUid: null,
        terminationRespondedAt: null,
        terminationRejectReason: null,
        // [BUG-FIX] H-3: Reset leaveDates and extraWorkDates so previous contract's
        // leave/extra-work days are not inherited into the renewed contract.
        // Matches Flutter's createRenewedApplication() (application_firestore.dart:2236-2238).
        leaveDates: [],
        extraWorkDates: [],
      });
      // 기존 Application 갱신 — 배치 실패 시 둘 다 미커밋 → 중복 연장 방지
      renewBatch.update(doc.ref, {renewalDecision: "EXTEND"});
      await renewBatch.commit();

      // 근무자에게 연장 알림
      await db.collection("users").doc(app.uid as string).collection("notifications").add({
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

    // ── D-0 종료 결정 완료 알림 ──────────────────────────────
    // renewalDecision='TERMINATE' + 어제 만료된 계약 → 근무자에게 종료 완료 알림
    // [특이사항] (status, renewalDecision, workEndDate) 복합 인덱스 필요 — firestore.indexes.json에 추가 완료.
    let terminateD0Count = 0;
    const d0TerminateSnap = await db.collection("applications")
      .where("status", "in", CONFIRMED_STATUSES)
      .where("renewalDecision", "==", "TERMINATE")
      .where("workEndDate", ">=", d0Start)
      .where("workEndDate", "<", d0End)
      .get();

    for (const doc of d0TerminateSnap.docs) {
      const app = doc.data();
      if (!app.workDays || app.workDays.length === 0) continue;
      // 이미 종료 알림 보낸 경우 스킵 (terminationNotifiedAt 필드로 중복 방지)
      // [특이사항] 중복 방지 체크가 트랜잭션 없이 read-then-write — 스케줄 함수 동시 실행 시
      // 이론적으로 중복 발송 가능. 그러나 Cloud Scheduler는 동일 잡을 겹쳐 실행하지 않으므로 저위험.
      if (app.terminationCompletionNotifiedAt) continue;

      await db.collection("users").doc(app.uid as string).collection("notifications").add({
        userId: app.uid,
        type: "contractTerminating",
        title: "계약 종료 완료",
        body: `${app.businessName} 계약이 종료되었습니다. 이용해 주셔서 감사합니다.`,
        data: {applicationId: doc.id, screen: "mySchedule"},
        isRead: false,
        createdAt: now,
      });
      await doc.ref.update({terminationCompletionNotifiedAt: now});
      terminateD0Count++;
    }
    console.log(`  ✅ [D-0 종료알림] ${terminateD0Count}건 처리`);

    // ── D+3 퇴사 요청 자동 승인 ──────────────────────────────
    const threeDaysAgo = new Date(todayKST.getTime() - 3 * 24 * 60 * 60 * 1000);
    const threeDaysAgoUTC = Timestamp.fromDate(
      new Date(threeDaysAgo.getTime() - KST_OFFSET_MS)
    );

    // [특이사항] (resignStatus, resignRequestedAt) 복합 인덱스 필요 — firestore.indexes.json에 추가 완료.
    let autoResignCount = 0;
    const pendingResignSnap = await db.collection("applications")
      .where("resignStatus", "==", "PENDING")
      .where("resignRequestedAt", "<=", threeDaysAgoUTC)
      .get();

    for (const doc of pendingResignSnap.docs) {
      try {
        const app = doc.data();

        // actualResignDate: 근무자가 희망한 날짜 or 요청일+1일
        let actualResignDate: Date;
        if (app.resignRequestDate) {
          actualResignDate = (app.resignRequestDate as Timestamp).toDate();
        } else {
          actualResignDate = new Date(
            (app.resignRequestedAt as Timestamp).toDate().getTime() + 24 * 60 * 60 * 1000
          );
        }

        await db.runTransaction(async (tx) => {
          const snap = await tx.get(doc.ref);
          if (snap.data()?.resignStatus !== "PENDING") return; // 이미 처리됨
          tx.update(doc.ref, {
            resignStatus: "AUTO_APPROVED",
            resignApprovedAt: now,
            actualResignDate: Timestamp.fromDate(actualResignDate),
            status: "CANCELED",
          });
        });

        // 근무자에게 자동 승인 알림
        await db.collection("users").doc(app.uid as string).collection("notifications").add({
          userId: app.uid,
          type: "resignApproved",
          title: "퇴사 요청 자동 승인",
          body: `${app.businessName} 퇴사 요청이 자동 승인되었습니다.`,
          data: {applicationId: doc.id, screen: "mySchedule"},
          isRead: false,
          createdAt: now,
        });

        // 관리자에게도 알림
        const bizDoc = await db.collection("businesses").doc(app.businessId).get();
        const adminIds: string[] = bizDoc.exists ?
          (bizDoc.data()?.adminIds as string[] ?? []) : [];
        await Promise.all(adminIds.map((adminId) => db.collection("users").doc(adminId).collection("notifications").add({
          userId: adminId,
          type: "resignApproved",
          title: "퇴사 요청 자동 승인됨",
          body: `${app.applicantName ?? "근무자"}님의 퇴사 요청이 자동 승인되었습니다.`,
          data: {applicationId: doc.id, screen: "fixedWorker"},
          isRead: false,
          createdAt: now,
        })));

        autoResignCount++;
      } catch (err) {
        console.error(`[D+3 퇴사 자동승인] 문서 ${doc.id} 처리 실패 — 나머지 계속 진행:`, err);
      }
    }
    console.log(`  ✅ [D+3 퇴사 자동승인] ${autoResignCount}건 처리`);

    // ── D+3 계약해지 요청 자동 승인 ──────────────────────────
    // [특이사항] (terminationStatus, terminationRequestedAt) 복합 인덱스 필요 — firestore.indexes.json에 추가 완료.
    let autoTerminationCount = 0;
    const pendingTerminationSnap = await db.collection("applications")
      .where("terminationStatus", "==", "PENDING")
      .where("terminationRequestedAt", "<=", threeDaysAgoUTC)
      .get();

    for (const doc of pendingTerminationSnap.docs) {
      try {
        const app = doc.data();

        // effectiveDate: 요청일+1일 (근무자 응답 없으면 바로 다음날 효력)
        const effectiveDate = new Date(
          (app.terminationRequestedAt as Timestamp).toDate().getTime() + 24 * 60 * 60 * 1000
        );

        await db.runTransaction(async (tx) => {
          const snap = await tx.get(doc.ref);
          if (snap.data()?.terminationStatus !== "PENDING") return;
          tx.update(doc.ref, {
            terminationStatus: "AUTO_APPROVED",
            terminationRespondedAt: now,
            terminationEffectiveDate: Timestamp.fromDate(effectiveDate),
            status: "CANCELED",
          });
        });

        // 근무자에게 자동 승인 알림
        await db.collection("users").doc(app.uid as string).collection("notifications").add({
          userId: app.uid,
          type: "terminationApproved",
          title: "계약해지 자동 승인",
          body: `${app.businessName} 계약해지 요청이 자동 승인되었습니다.`,
          data: {applicationId: doc.id, screen: "mySchedule"},
          isRead: false,
          createdAt: now,
        });

        autoTerminationCount++;
      } catch (err) {
        console.error(`[D+3 계약해지 자동승인] 문서 ${doc.id} 처리 실패 — 나머지 계속 진행:`, err);
      }
    }
    console.log(`  ✅ [D+3 계약해지 자동승인] ${autoTerminationCount}건 처리`);

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
        timeout: 10000,
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
    req.on("timeout", () => { req.destroy(); reject(new Error("SENS API timeout")); });
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
      // [특이사항] 인증 코드 평문 저장 — Firestore 보안 규칙으로 클라이언트 직접 접근 차단 필수
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

      const expiredAtRaw = data.expiredAt;
      if (!expiredAtRaw || !(expiredAtRaw instanceof Timestamp)) {
        result = {valid: false, reason: "expired"};
        return;
      }
      const expiredAt = expiredAtRaw.toDate();
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

    // [BB-001] 수락된 멤버의 subAdminOf 초기화 + 초대 문서 삭제
    const acceptedInviteSnap = await db
      .collection("member_invitations")
      .where("businessId", "==", businessId)
      .where("status", "==", "accepted")
      .get();
    if (!acceptedInviteSnap.empty) {
      let userBatch = db.batch();
      let userCount = 0;
      for (const doc of acceptedInviteSnap.docs) {
        const targetUid = doc.data().targetUid as string | undefined;
        if (targetUid) {
          userBatch.update(db.collection("users").doc(targetUid), {
            subAdminOf: admin.firestore.FieldValue.delete(),
          });
          userCount++;
          if (userCount % 500 === 0) {
            await userBatch.commit();
            userBatch = db.batch();
          }
        }
      }
      if (userCount % 500 !== 0) await userBatch.commit();
    }
    // [BB-002] member_invitations 전체 삭제 (pending 포함)
    const allInviteSnap = await db
      .collection("member_invitations")
      .where("businessId", "==", businessId)
      .get();
    if (!allInviteSnap.empty) {
      let invBatch = db.batch();
      let invCount = 0;
      for (const doc of allInviteSnap.docs) {
        invBatch.delete(doc.ref);
        invCount++;
        if (invCount % 500 === 0) {
          await invBatch.commit();
          invBatch = db.batch();
        }
      }
      if (invCount % 500 !== 0) await invBatch.commit();
    }

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
          // [특이사항] 30개 TO × 다수 지원서 = 500건 초과 가능 → 500건 단위로 분할 커밋
          const batchSize = 499;
          for (let k = 0; k < appsSnap.docs.length; k += batchSize) {
            const appBatch = db.batch();
            const slice = appsSnap.docs.slice(k, k + batchSize);
            for (const doc of slice) {
              appBatch.update(doc.ref, {
                status: "CANCELED",
                cancelReason: "BUSINESS_DELETED",
                canceledAt: Timestamp.now(),
              });
            }
            await appBatch.commit();
          }

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
              // attSnap도 500건 초과 가능하면 같은 방식으로 분할
              for (let m = 0; m < attSnap.docs.length; m += batchSize) {
                const attBatch = db.batch();
                for (const doc of attSnap.docs.slice(m, m + batchSize)) {
                  attBatch.update(doc.ref, {status: "absent", updatedAt: Timestamp.now()});
                }
                await attBatch.commit();
              }
            }
          }
        }
      }

      // TO 문서 삭제 (500건 분할)
      let tosBatch = db.batch();
      let tosCount = 0;
      for (const doc of tosSnap.docs) {
        tosBatch.delete(doc.ref);
        tosCount++;
        if (tosCount % 500 === 0) {
          await tosBatch.commit();
          tosBatch = db.batch();
        }
      }
      if (tosCount % 500 !== 0) await tosBatch.commit();
    }

    console.log(`사업장 삭제 cascade 완료: ${businessId}`);
  }
);

// ═══════════════════════════════════════════════════════════
// 🔐 PASS 본인인증 (다날)
// ═══════════════════════════════════════════════════════════
//
// DANAL_MOCK_MODE=true 환경변수 설정 시 mock 데이터 반환 (다날 계약 전 테스트용).
// 배포 후 Firebase Functions 환경변수: firebase functions:secrets:set DANAL_MOCK_MODE

// ── initiatePassAuth ─────────────────────────────────────
// 다날 txSeq + 인증 URL 발급
// Input:  { purpose: 'register'|'resetPassword', role?: string }
// Output: { txSeq, authUrl, isMock? }
export const initiatePassAuth = onCall(
  {region: "asia-northeast3"},
  async (request) => {
    const purpose = request.data.purpose as string | undefined;
    if (!purpose || !["register", "resetPassword"].includes(purpose)) {
      throw new HttpsError("invalid-argument", "purpose는 'register' 또는 'resetPassword'여야 합니다.");
    }

    const isMock = process.env.DANAL_MOCK_MODE === "true";
    if (isMock) {
      return {
        txSeq: `MOCK-${Date.now()}`,
        authUrl: "https://mock.danal.example.com/auth",
        isMock: true,
      };
    }

    // [TODO-DANAL] 실제 다날 API 호출 — txSeq + authUrl 발급
    // 계약 완료 후 다날 SDK / REST API 연동 필요
    throw new HttpsError("unimplemented", "다날 계약 완료 후 구현 예정입니다.");
  }
);

// ── verifyPassAuth ───────────────────────────────────────
// 다날 encData 복호화 → 연령/CI 중복/재가입 검증 → passToken(15분) 발급
// Input:  { encData, txSeq, purpose, role? }
// Output: { passToken, name, gender, birthDate, phone }
export const verifyPassAuth = onCall(
  {region: "asia-northeast3"},
  async (request) => {
    const {purpose, role = "USER"} = request.data as {
      encData?: string;
      txSeq?: string;
      purpose?: string;
      role?: string;
    };

    if (!purpose || !["register", "resetPassword"].includes(purpose)) {
      throw new HttpsError("invalid-argument", "purpose가 올바르지 않습니다.");
    }

    const isMock = process.env.DANAL_MOCK_MODE === "true";

    let ci: string;
    let name: string;
    let gender: string;
    let birthDateStr: string; // YYYYMMDD
    let phone: string;

    if (isMock) {
      ci = "MOCK-CI-ABCDEF123456";
      name = "홍길동";
      gender = "남성";
      birthDateStr = "19900115";
      phone = "01012345678";
    } else {
      const {encData, txSeq} = request.data as {encData?: string; txSeq?: string};
      if (!encData || !txSeq) {
        throw new HttpsError("invalid-argument", "encData, txSeq 필수입니다.");
      }
      // [TODO-DANAL] 다날 복호화 로직 — AES 키는 Functions Secret으로 관리
      throw new HttpsError("unimplemented", "다날 계약 완료 후 구현 예정입니다.");
    }

    // 만 19세 미만 차단
    const today = new Date();
    const by = parseInt(birthDateStr.substring(0, 4));
    const bm = parseInt(birthDateStr.substring(4, 6));
    const bd = parseInt(birthDateStr.substring(6, 8));
    const age =
      today.getFullYear() -
      by -
      (today.getMonth() + 1 < bm ||
      (today.getMonth() + 1 === bm && today.getDate() < bd)
        ? 1
        : 0);
    if (age < 19) {
      throw new HttpsError("permission-denied", "만 19세 이상만 가입 가능합니다.");
    }

    const ciHash = crypto.createHash("sha256").update(ci).digest("hex");

    if (purpose === "register") {
      // CI + role 중복 체크
      const dupSnap = await db
        .collection("users")
        .where("ciHash", "==", ciHash)
        .where("role", "==", role)
        .limit(1)
        .get();
      if (!dupSnap.empty) {
        throw new HttpsError(
          "already-exists",
          "이미 동일 역할로 가입된 계정이 있습니다."
        );
      }

      // 탈퇴 후 1개월 이내 재가입 차단
      const deletedSnap = await db
        .collection("deleted_accounts")
        .where("ciHash", "==", ciHash)
        .limit(1)
        .get();
      if (!deletedSnap.empty) {
        const deletedAt = (
          deletedSnap.docs[0].data().deletedAt as Timestamp
        ).toDate();
        const oneMonthAgo = new Date();
        oneMonthAgo.setMonth(oneMonthAgo.getMonth() - 1);
        if (deletedAt > oneMonthAgo) {
          throw new HttpsError(
            "permission-denied",
            "탈퇴 후 1개월이 지난 후 재가입 가능합니다."
          );
        }
      }
    }

    // passToken 발급 (15분 유효)
    // [주의] 가입(register) 경로에서 발급된 토큰은 현재 소비되지 않음.
    //   → resetPasswordWithPass에서만 토큰 소비(삭제)가 이루어짐.
    //   → 가입 완료 후 passTokens 문서가 15분간 잔류 → 배포 전 TTL 정책 또는
    //      Cloud Scheduler 정리 Job 추가 필요.
    // [TODO-DANAL] 가입 완료 시 해당 passToken의 ciHash를 users/{uid}에 복사하는
    //   별도 CF(예: finalizeRegistration) 추가 필요.
    const passToken = crypto.randomBytes(32).toString("hex");
    await db
      .collection("passTokens")
      .doc(passToken)
      .set({
        ciHash,
        name,
        gender,
        birthDate: birthDateStr,
        phone,
        purpose,
        role,
        expiresAt: Timestamp.fromDate(new Date(Date.now() + 15 * 60 * 1000)),
        createdAt: Timestamp.now(),
      });

    return {passToken, name, gender, birthDate: birthDateStr, phone};
  }
);

// ── resetPasswordWithPass ────────────────────────────────
// passToken + username → CI 매칭 → Firebase Custom Token 발급
// Input:  { passToken, username }
// Output: { customToken }
//
// [설계 제약] 내국인(ciHash 보유) 전용. 외국인은 ciHash 없으므로 CI 매칭 실패.
//   외국인 비밀번호 재설정 경로는 별도 지원 필요 (예: 이메일 또는 관리자 직접 처리).
// [보안] passToken은 소비 즉시 삭제(일회용) — 재사용 불가.
export const resetPasswordWithPass = onCall(
  {region: "asia-northeast3"},
  async (request) => {
    const {passToken, username} = request.data as {
      passToken?: string;
      username?: string;
    };
    if (!passToken || !username) {
      throw new HttpsError("invalid-argument", "passToken, username 필수입니다.");
    }

    // passToken 원자적 소비 — 트랜잭션으로 동시 요청 레이스 컨디션 방어
    // [특이사항] 트랜잭션 내에서 collection query 불가 → 검증 후 토큰 삭제 + ciHash 반환,
    //           username 쿼리·CI 매칭·customToken 발급은 트랜잭션 외부에서 순서대로 수행.
    const tokenRef = db.collection("passTokens").doc(passToken);
    const {ciHash} = await db.runTransaction(async (tx) => {
      const tokenDoc = await tx.get(tokenRef);
      if (!tokenDoc.exists) {
        throw new HttpsError("not-found", "유효하지 않은 인증 토큰입니다.");
      }
      const data = tokenDoc.data()!;
      if (data.purpose !== "resetPassword") {
        throw new HttpsError("invalid-argument", "비밀번호 찾기용 토큰이 아닙니다.");
      }
      const tokenExpiresAt = data.expiresAt;
      if (!tokenExpiresAt || !(tokenExpiresAt instanceof Timestamp) || tokenExpiresAt.toDate() < new Date()) {
        throw new HttpsError(
          "deadline-exceeded",
          "인증 토큰이 만료되었습니다. 다시 본인인증을 진행해주세요."
        );
      }
      // 토큰을 트랜잭션 내에서 즉시 삭제 → 동시 요청 시 두 번째 요청은 not-found
      tx.delete(tokenRef);
      return {ciHash: data.ciHash as string};
    });

    // username으로 내국인 사용자 찾기
    const userSnap = await db
      .collection("users")
      .where("username", "==", username)
      .limit(1)
      .get();
    if (userSnap.empty) {
      throw new HttpsError("not-found", "존재하지 않는 아이디입니다.");
    }
    const userDoc = userSnap.docs[0];
    const userData = userDoc.data();

    // CI 해시 매칭
    if (userData.ciHash !== ciHash) {
      throw new HttpsError(
        "permission-denied",
        "본인인증 정보가 계정 정보와 일치하지 않습니다."
      );
    }

    // Firebase Custom Token 발급 → 앱에서 signInWithCustomToken 사용
    const customToken = await admin.auth().createCustomToken(userDoc.id);
    return {customToken};
  }
);

// ═══════════════════════════════════════════════════════════
// 👤 외국인 근로자 계정 승인/거절 (슈퍼관리자 전용)
// ═══════════════════════════════════════════════════════════

// ── approveForeignWorker ─────────────────────────────────
// Input:  { userId }
// Output: { success: true }
//
// [설계 제약] pending 상태에서만 처리 가능. 이미 active/rejected 계정은 재처리 불가.
//   재검토가 필요하면 Firestore를 직접 수정하거나 별도 CF(resetAccountStatus) 추가 필요.
export const approveForeignWorker = onCall(
  {region: "asia-northeast3"},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    }
    const callerDoc = await db.collection("users").doc(request.auth.uid).get();
    if (callerDoc.data()?.role !== "SUPER_ADMIN") {
      throw new HttpsError("permission-denied", "슈퍼관리자만 승인할 수 있습니다.");
    }

    const {userId} = request.data as {userId?: string};
    if (!userId) throw new HttpsError("invalid-argument", "userId 필수입니다.");

    const userRef = db.collection("users").doc(userId);
    const userDoc = await userRef.get();
    if (!userDoc.exists) {
      throw new HttpsError("not-found", "사용자를 찾을 수 없습니다.");
    }
    if (userDoc.data()?.accountStatus !== "pending") {
      throw new HttpsError("failed-precondition", "승인 대기 중인 계정이 아닙니다.");
    }

    await userRef.update({
      accountStatus: "active",
      approvedAt: Timestamp.now(),
      approvedBy: request.auth.uid,
    });

    // FCM 알림 전송
    // [특이사항] 단일 fcmToken 필드만 사용 — onNotificationCreated의 fcmTokens 배열 방식과 불일치.
    //           외국인 계정은 단일 기기 로그인만 허용하는 설계이므로 배열 불필요 (의도된 단순화).
    const fcmToken = userDoc.data()?.fcmToken as string | undefined;
    if (fcmToken) {
      try {
        await admin.messaging().send({
          token: fcmToken,
          notification: {
            title: "AlFit",
            body: "계정이 승인되었습니다. 이제 AlFit을 이용하실 수 있습니다.",
          },
          data: {type: "foreignAccountApproved"},
        });
      } catch (e) {
        // FCM 실패는 승인 자체를 롤백하지 않음 (fire-and-forget)
        console.error("FCM 전송 실패 (approveForeignWorker):", e);
      }
    }

    return {success: true};
  }
);

// ── rejectForeignWorker ──────────────────────────────────
// Input:  { userId, reason }
// Output: { success: true }
export const rejectForeignWorker = onCall(
  {region: "asia-northeast3"},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    }
    const callerDoc = await db.collection("users").doc(request.auth.uid).get();
    if (callerDoc.data()?.role !== "SUPER_ADMIN") {
      throw new HttpsError("permission-denied", "슈퍼관리자만 거절할 수 있습니다.");
    }

    const {userId, reason} = request.data as {userId?: string; reason?: string};
    if (!userId || !reason) {
      throw new HttpsError("invalid-argument", "userId, reason 필수입니다.");
    }

    const userRef = db.collection("users").doc(userId);
    const userDoc = await userRef.get();
    if (!userDoc.exists) {
      throw new HttpsError("not-found", "사용자를 찾을 수 없습니다.");
    }
    if (userDoc.data()?.accountStatus !== "pending") {
      throw new HttpsError("failed-precondition", "승인 대기 중인 계정이 아닙니다.");
    }

    await userRef.update({
      accountStatus: "rejected",
      rejectedAt: Timestamp.now(),
      rejectedBy: request.auth.uid,
      rejectionReason: reason,
    });

    // FCM 알림 전송
    const fcmToken = userDoc.data()?.fcmToken as string | undefined;
    if (fcmToken) {
      try {
        await admin.messaging().send({
          token: fcmToken,
          notification: {
            title: "AlFit",
            body: `계정 승인이 거절되었습니다. 사유: ${reason}`,
          },
          data: {type: "foreignAccountRejected", reason},
        });
      } catch (e) {
        console.error("FCM 전송 실패 (rejectForeignWorker):", e);
      }
    }

    return {success: true};
  }
);

// ── cleanExpiredPassTokens ───────────────────────────────────
// 30분마다 만료된 passTokens 문서 정리 (ISSUE-02)
// [특이사항] Firestore 콘솔 TTL 정책 대안 — passTokens는 소량이므로 배치 1회로 충분
export const cleanExpiredPassTokens = onSchedule(
  {
    schedule: "every 30 minutes",
    timeZone: "Asia/Seoul",
    region: "asia-northeast3",
    maxInstances: 1,
  },
  async () => {
    const now = Timestamp.now();
    const expiredSnap = await db
      .collection("passTokens")
      .where("expiresAt", "<=", now)
      .limit(499)
      .get();

    if (expiredSnap.empty) {
      console.log("✅ [passTokens 정리] 만료 문서 없음");
      return;
    }

    const batch = db.batch();
    expiredSnap.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();

    console.log(`✅ [passTokens 정리] ${expiredSnap.size}건 삭제`);
  }
);

// ── adminResetForeignPassword ────────────────────────────────
// 슈퍼어드민 전용 — 외국인 근로자 비밀번호 임시 초기화 (ISSUE-03)
// Input:  { userId: string }
// Output: { tempPassword: string }
export const adminResetForeignPassword = onCall(
  {region: "asia-northeast3"},
  async (request) => {
    const callerUid = request.auth?.uid;
    if (!callerUid) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");

    const callerDoc = await db.collection("users").doc(callerUid).get();
    if (callerDoc.data()?.role !== "SUPER_ADMIN") {
      throw new HttpsError("permission-denied", "슈퍼어드민 권한이 필요합니다.");
    }

    const {userId} = request.data as {userId?: string};
    if (!userId) throw new HttpsError("invalid-argument", "userId가 필요합니다.");

    const targetDoc = await db.collection("users").doc(userId).get();
    if (!targetDoc.exists) throw new HttpsError("not-found", "사용자를 찾을 수 없습니다.");

    const userData = targetDoc.data()!;
    // [특이사항] 내국인은 PASS CI 기반 비밀번호 찾기 사용 — 이 CF는 외국인 전용
    if (!userData.foreignIdNumber) {
      throw new HttpsError("failed-precondition", "내국인 사용자는 이 기능을 사용할 수 없습니다.");
    }

    // 혼동 없는 문자만 사용 (O/0, I/l/1 제외), crypto.randomInt으로 암호학적 안전성 보장
    const chars = "ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789";
    let tempPassword = "";
    for (let i = 0; i < 8; i++) {
      tempPassword += chars[crypto.randomInt(0, chars.length)];
    }

    await admin.auth().updateUser(userId, {password: tempPassword});

    console.log(`[adminResetForeignPassword] 슈퍼어드민 ${callerUid}가 ${userId}(${userData.name})의 비밀번호 초기화`);
    return {tempPassword};
  }
);
