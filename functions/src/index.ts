import {onSchedule} from "firebase-functions/v2/scheduler";
import {
  onDocumentCreated,
  onDocumentUpdated,
  onDocumentDeleted,
  onDocumentWritten,
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
  {region: "asia-northeast3", enforceAppCheck: true},
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
        uid: snapshot.docs[0].id,
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

    console.log(`✅ [비밀번호 재설정] 코드 발송 완료: ${username.slice(0, 2)}***`);
    return {success: true};
  }
);

// ═══════════════════════════════════════════════════════════
// 🔑 비밀번호 재설정 코드 검증 및 변경
// ═══════════════════════════════════════════════════════════

export const resetPasswordWithCode = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    const username = request.data.username as string | undefined;
    const code = request.data.code as string | undefined;
    const newPassword = request.data.newPassword as string | undefined;

    if (!username || !code || !newPassword) {
      throw new HttpsError("invalid-argument", "필수 항목이 누락되었습니다.");
    }
    if (username.length > 50) {
      throw new HttpsError("invalid-argument", "아이디 형식이 올바르지 않습니다.");
    }
    if (!/^\d{6}$/.test(code)) {
      throw new HttpsError("invalid-argument", "인증코드는 6자리 숫자여야 합니다.");
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
    let resolvedUid: string | undefined;
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
      // 검증 성공 → sendPasswordResetCode가 저장한 uid 추출 (users 재조회 불필요)
      resolvedUid = data.uid as string | undefined;
      tx.update(docRef, {used: true, usedAt: now});
    });

    if (!resolvedUid) {
      // [특이사항] 이전에 발급된 코드(uid 필드 없는 레거시 문서)에 대한 폴백 처리
      // sendPasswordResetCode 배포 후 5분(코드 만료) 이내에만 발생 가능
      const userSnapshot = await db
        .collection("users")
        .where("username", "==", username)
        .limit(1)
        .get();
      if (userSnapshot.empty) {
        throw new HttpsError("not-found", "사용자를 찾을 수 없습니다.");
      }
      resolvedUid = userSnapshot.docs[0].id;
    }
    const uid = resolvedUid;

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

    // [마스킹] username 전체 노출 방지 (sendPasswordResetCode와 동일 기준 적용)
    console.log(`✅ [비밀번호 재설정] 완료: ${username.slice(0, 2)}***`);
    return {success: true};
  }
);

// ═══════════════════════════════════════════════════════════
// 🔄 재시작 프로그램 적용 (Admin SDK — 클라이언트 규칙 우회)
// 워커 본인만 호출 가능 (request.auth.uid == userId)
// ═══════════════════════════════════════════════════════════

export const applyRestartProgram = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
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
  {region: "asia-northeast3", enforceAppCheck: true},
  async () => {
    return {serverTimeMs: Date.now()};
  }
);

// ═══════════════════════════════════════════════════════════
// 🔔 알림 생성 Callable — 클라이언트 직접 write 차단 후 이 함수로 단일화
// Admin SDK로 쓰므로 Firestore 보안 규칙(allow create: if false)을 우회
// ═══════════════════════════════════════════════════════════

export const createNotification = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
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
    //
    const rawData = (data.data as Record<string, unknown> | undefined) ?? {};
    // [E-1a 수정] workDetailId·workType — 관리자 알림 탭 시 WorkApplicantsDialog 딥링크에 필요
    // [E-1b 수정] expiryDate — createContractExpiringReminder FCM payload 보존
    // [E-1D/E 수정] reason — createApplicationAutoCanceled·createTOCanceled의 reason 필드 보존
    const allowedDataKeys = new Set([
      "screen", "action", "applicationId", "businessId", "toId",
      "requestId", "reviewId", "contractId", "attendanceId", "invitationId",
      "workDetailId", "workType", "expiryDate", "reason",
    ]);
    const filteredData: Record<string, unknown> = {};
    for (const key of Object.keys(rawData)) {
      if (!allowedDataKeys.has(key)) continue;
      const strVal = String(rawData[key]);
      // SEC-12: 값 길이 제한 (FCM data payload는 256자 이하 권장)
      if (strVal.length > 256) continue;
      filteredData[key] = strVal;
    }

    // ── 발신자-수신자 관계 검증 ─────────────────────────────────
    // 타인에게 알림을 보낼 때: 발신자 또는 수신자가 해당 사업장의 관리자여야 한다.
    // · 관리자→근무자: 발신자(callerUid)가 adminIds에 있음 → 허용
    // · 근무자→관리자: 수신자(userId)가 adminIds에 있음 → 허용
    // · 근무자→근무자: 둘 다 adminIds에 없음 → 차단
    // SUPER_ADMIN은 모든 수신자 허용. 본인 알림(userId == callerUid)은 검증 생략.
    const callerUid = request.auth.uid;
    if (userId !== callerUid) {
      const callerSnap = await db.collection("users").doc(callerUid).get();
      const callerRole = callerSnap.data()?.role as string | undefined;

      // SEC-56: SUPER_ADMIN도 수신자 존재 확인 — 존재하지 않는 userId로 알림 문서 생성 차단
      if (callerRole === "SUPER_ADMIN") {
        const recipientSnap = await db.collection("users").doc(userId).get();
        if (!recipientSnap.exists) {
          throw new HttpsError("not-found", "수신자를 찾을 수 없습니다.");
        }
      } else {
        const targetBusinessId = filteredData.businessId as string | undefined;
        if (!targetBusinessId) {
          throw new HttpsError("permission-denied", "타인에게 알림 발송 시 businessId가 필요합니다.");
        }

        const bizSnap = await db.collection("businesses").doc(targetBusinessId).get();
        if (!bizSnap.exists) {
          throw new HttpsError("not-found", "사업장을 찾을 수 없습니다.");
        }
        const adminIds = (bizSnap.data()?.adminIds as string[] | undefined) ?? [];
        const ownerId = bizSnap.data()?.ownerId as string | undefined;
        const callerSubAdminOf = callerSnap.data()?.subAdminOf as string | undefined;

        const callerIsAdmin = adminIds.includes(callerUid) ||
                              ownerId === callerUid ||
                              callerSubAdminOf === targetBusinessId;

        // [BUG-CF-01 수정] 수신자 조회를 앞으로 이동 — subAdminOf 체크에 필요
        // SubAdmin이 수신자인 경우(근무자→SubAdmin 알림) 기존 코드는 recipientIsAdmin=false로 판단해 차단됨
        const recipientSnap = await db.collection("users").doc(userId).get();
        if (!recipientSnap.exists) {
          throw new HttpsError("not-found", "수신자를 찾을 수 없습니다.");
        }
        const recipientSubAdminOf = recipientSnap.data()?.subAdminOf as string | undefined;
        const recipientIsAdmin = adminIds.includes(userId) || ownerId === userId
          || recipientSubAdminOf === targetBusinessId;

        // 관리자 ↔ 근무자 방향 알림만 허용 — 근무자↔근무자 스팸 차단
        if (!callerIsAdmin && !recipientIsAdmin) {
          throw new HttpsError("permission-denied", "해당 사업장 관리자와 근무자 간 알림만 허용됩니다.");
        }
        // [SEC-SENDER-VERIFY] 근무자→관리자 알림: 발신자가 해당 사업장 소속인지 검증
        // callerIsAdmin=false + recipientIsAdmin=true 케이스 — 발신자가 타 사업장 근무자이면 차단
        // 주의: 초대 수락(acceptInvitation) 흐름에서 users.businessId가 아직 미설정일 수 있음
        //   → members 서브컬렉션 존재 여부를 병행 확인 (batch.commit 직후 members에 이미 추가됨)
        if (!callerIsAdmin && recipientIsAdmin) {
          const callerBusinessId = callerSnap.data()?.businessId as string | undefined;
          const memberSnap = await db.collection("businesses").doc(targetBusinessId)
              .collection("members").doc(callerUid).get();
          if (callerBusinessId !== targetBusinessId && !memberSnap.exists) {
            throw new HttpsError("permission-denied", "발신자가 해당 사업장 소속이 아닙니다.");
          }
        }
        // [SEC-48] 관리자→근무자 알림: 수신자가 해당 사업장 소속인지 검증
        // callerIsAdmin=true + !recipientIsAdmin 케이스 — 관리자가 타 사업장 근무자에게 알림 발송 차단
        if (callerIsAdmin && !recipientIsAdmin) {
          const recipientBusinessId = recipientSnap.data()?.businessId as string | undefined;
          if (recipientBusinessId !== targetBusinessId) {
            const recipMemberSnap = await db.collection("businesses").doc(targetBusinessId)
                .collection("members").doc(userId).get();
            if (!recipMemberSnap.exists) {
              throw new HttpsError("permission-denied", "수신자가 해당 사업장 소속이 아닙니다.");
            }
          }
        }
      }
    }
    // ────────────────────────────────────────────────────────────

    // SEC-21: title/body 길이 제한, type enum 검증
    const rawTitle = data.title as string | undefined;
    const rawBody = data.body as string | undefined;
    const rawType = (data.type as string | undefined) ?? "general";
    if (!rawTitle || rawTitle.length > 100) {
      throw new HttpsError("invalid-argument", "title은 1~100자여야 합니다.");
    }
    if (rawBody && rawBody.length > 500) {
      throw new HttpsError("invalid-argument", "body는 500자 이하여야 합니다.");
    }
    // type: 영문자·숫자·언더스코어만 허용 (XSS·injection 차단), 최대 50자
    if (!/^[A-Za-z_][A-Za-z0-9_]{0,49}$/.test(rawType)) {
      throw new HttpsError("invalid-argument", "알림 타입 형식이 올바르지 않습니다.");
    }
    // [MEDIUM] 허용 목록 화이트리스트 — 임의 type 저장 차단
    const ALLOWED_NOTIFICATION_TYPES = new Set([
      "general", "contractRequested", "contractApproved", "contractRejected",
      "applicationConfirmed", "applicationCanceled", "applicationReconfirmed",
      "idCardAccessRequest", "idCardAccessApproved", "idCardAccessRejected",
      "resignApproved", "resignRejected", "paymentTransferred",
      "toPublished", "noShow", "latePenalty", "trustScoreChanged",
      "scheduleChangeRequest", "scheduleChangeApproved", "scheduleChangeRejected",
      "terminationApproved", "terminationRejected", "renewalReminder",
    ]);
    if (!ALLOWED_NOTIFICATION_TYPES.has(rawType)) {
      throw new HttpsError("invalid-argument", "허용되지 않는 알림 타입입니다.");
    }
    // [A4-FIX] contractRequested 타입: applicationId 기반 24h 서버 쿨다운
    // SharedPreferences 기반 클라이언트 쿨다운은 재설치·타기기로 우회 가능 → 서버 강제로 전환
    // [A4-LOOP-FIX] 다수 관리자 사업장에서 Dart가 adminIds 루프로 CF를 반복 호출 시:
    //   1번째 호출이 lastContractRequestedAt을 설정하면 2번째 호출이 쿨다운에 걸림
    //   → loopGraceMs(60초) 이내 호출은 동일 루프로 간주, 에러 없이 알림만 발송
    if (rawType === "contractRequested") {
      const appId = filteredData.applicationId as string | undefined;
      if (appId) {
        const appRef = db.collection("applications").doc(appId);
        const appSnap = await appRef.get();
        if (appSnap.exists) {
          const lastReq = appSnap.data()?.lastContractRequestedAt as FirebaseFirestore.Timestamp | undefined;
          if (lastReq) {
            const diffMs = Date.now() - lastReq.toMillis();
            const cooldownMs = 24 * 60 * 60 * 1000;
            const loopGraceMs = 60 * 1000; // 루프 내 연속 호출 허용 (다수 관리자 알림 발송)
            if (diffMs >= loopGraceMs && diffMs < cooldownMs) {
              // 1분 초과 + 24시간 미만 → 실제 재요청 쿨다운
              const remainHours = Math.ceil((cooldownMs - diffMs) / (60 * 60 * 1000));
              throw new HttpsError("resource-exhausted", `${remainHours}시간 후 재요청 가능합니다.`);
            }
            // diffMs < loopGraceMs: 루프 내 호출 — 타임스탬프 업데이트 없이 알림만 발송
          } else {
            // 첫 번째 요청: lastContractRequestedAt 설정
            await appRef.update({lastContractRequestedAt: admin.firestore.FieldValue.serverTimestamp()});
          }
        }
      }
    }

    const payload: Record<string, unknown> = {
      userId,
      title: rawTitle,
      body: rawBody,
      type: rawType,
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

    try {
      await db.collection("users").doc(targetUid).update({subAdminOf: businessId});
      console.log(`✅ [초대수락 트리거] subAdminOf 설정 완료: uid=${targetUid}, bizId=${businessId}`);
    } catch (e: any) {
      // [INVITE-RETRY-FIX] NOT_FOUND(code 5): 탈퇴 사용자 — 재시도해도 동일하게 실패하므로 중단
      if ((e as any)?.code === 5) {
        console.error(`⚠️ [초대수락 트리거] 사용자 없음 — 재시도 없음: uid=${targetUid}`, e);
        return;
      }
      throw e; // 그 외(네트워크 오류 등)는 재전파 → CF 재시도
    }
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

      // 추가 data 필드가 있으면 병합 — FCM data payload 4KB 한계 초과 방지
      if (notificationData.data) {
        const extraData = notificationData.data as Record<string, unknown>;
        for (const [key, value] of Object.entries(extraData)) {
          if (typeof value === "string") {
            fcmData[key] = value;
          } else if (value !== null && value !== undefined) {
            fcmData[key] = String(value);
          }
        }
        // FCM data payload 직렬화 크기가 3KB 초과 시 로그 (4KB 한계 접근 경고)
        const payloadSize = Buffer.byteLength(JSON.stringify(fcmData), "utf8");
        if (payloadSize > 3000) {
          console.error(`⚠️ [FCM] data payload 크기 초과 위험: ${payloadSize}B (userId=${userId}, type=${type})`);
        }
      }

      // 멀티 디바이스: sendEachForMulticast로 한 번의 HTTP 요청에 일괄 발송
      const multicastResponse = await admin.messaging().sendEachForMulticast({
        tokens: fcmTokens,
        notification: {title, body: body || ""},
        data: fcmData,
        android: {
          priority: "high",
          notification: {channelId: "alfit_notifications", sound: "default"},
        },
        apns: {payload: {aps: {sound: "default", badge: 1}}},
      });

      const successCount = multicastResponse.successCount;

      // 실패 토큰 중 만료 토큰만 추려서 정리
      const expiredTokens = fcmTokens.filter((_, i) => {
        const errCode = multicastResponse.responses[i].error?.code ?? "";
        return (
          errCode === "messaging/invalid-registration-token" ||
          errCode === "messaging/registration-token-not-registered"
        );
      });
      if (expiredTokens.length > 0) {
        console.log(`⚠️ [알림 트리거] 만료 토큰 ${expiredTokens.length}개 정리: ${userId}`);
        const updates: Record<string, unknown> = {
          fcmTokens: admin.firestore.FieldValue.arrayRemove(...expiredTokens),
        };
        // 단일 토큰 필드도 만료된 경우 삭제
        if (expiredTokens.some((t) => t === fcmTokens[0])) {
          updates.fcmToken = admin.firestore.FieldValue.delete();
        }
        await db.collection("users").doc(userId).update(updates);
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
      // [RECOVERY-001 수정] 순차 실행 → Promise.allSettled 병렬 실행
      // 순차 실행 시 앞 함수가 타임아웃을 소모하면 뒤 함수가 minute<10 윈도우를 놓칠 수 있음
      // allSettled: 한 함수 실패가 나머지 실행을 차단하지 않음 (기존 개별 try-catch와 동일 격리 수준)
      // [I-1 수정] processExpiredIdCardAccess 추가 — 만료된 신분증 요청 자동 정리
      console.log("⏰ [자정 작업] 병렬 실행 시작 (미퇴근처리·리뷰요청·리뷰공개·계약연장·신분증만료)...");
      const midnightResults = await Promise.allSettled([
        processMissedCheckouts(timestamp),
        createPendingReviewRequests(timestamp),
        processExpiredReviewRequests(timestamp),
        processContractRenewalChecks(timestamp),
        processExpiredIdCardAccess(timestamp),
      ]);
      const midnightNames = ["미퇴근 처리", "리뷰 요청", "리뷰 공개", "계약 연장", "신분증 만료"];
      midnightResults.forEach((r, i) => {
        if (r.status === "rejected") console.error(`❌ [${midnightNames[i]}] 실패:`, r.reason);
        else console.log(`✅ [${midnightNames[i]}] 완료`);
      });

      // [TODO] idCardAccessExpiringSoon: 신분증 열람 권한 만료 D-1 알림 미구현
      // approvedAccess 중 expiresAt이 내일인 항목 조회 → 근무자에게 알림 발송 필요
    }

    // ═══════════════════════════════════════════════════════
    // ✅ 매 시간 실행 — pending_token_revocations 재처리 (세션 무효화 실패 retry)
    // ═══════════════════════════════════════════════════════
    try {
      const pendingRevocations = await db.collection("pending_token_revocations").limit(50).get();
      if (!pendingRevocations.empty) {
        let revokeSuccessCount = 0;
        for (const revDoc of pendingRevocations.docs) {
          const data = revDoc.data();
          const targetUid = data.uid as string | undefined;
          if (!targetUid) { await revDoc.ref.delete(); continue; }
          try {
            await admin.auth().revokeRefreshTokens(targetUid);
            await revDoc.ref.delete();
            revokeSuccessCount++;
          } catch (retryErr) {
            // 재시도 실패 — 다음 실행까지 유지
            console.warn(`[세션무효화-retry] 재시도 실패 uid=${targetUid}:`, retryErr);
          }
        }
        if (revokeSuccessCount > 0) {
          console.log(`✅ [세션무효화-retry] ${revokeSuccessCount}건 성공`);
        }
      }
    } catch (e) { console.error("❌ [세션무효화-retry] 실패:", e); }

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

// ─── 신분증 열람 만료 자동 정리 ──────────────────────────────
/**
 * [I-1 수정] 자정 실행: idCardAccessRequests 컬렉션에서 status='approved'이고
 * expiresAt이 현재 시각 이전인 문서를 'expired'로 갱신.
 * approved 상태로 영구 잔류하면 만료된 권한이 UI에서 유효하게 보이는 UX 버그 발생.
 */
// [NEW-14] masterScheduler는 00:00~00:09 윈도우에서 재시도 가능 — 멱등성 보장:
// where(status=="approved")로 이미 expired 처리된 건은 재조회 안 됨 (safe idempotent)
async function processExpiredIdCardAccess(now: Timestamp): Promise<void> {
  const snap = await db
    .collection("idCardAccessRequests")
    .where("status", "==", "approved")
    .where("expiresAt", "<=", now)
    .limit(200)
    .get();

  if (snap.empty) return;

  const batch = db.batch();
  snap.docs.forEach((doc) => {
    batch.update(doc.ref, {
      status: "expired",
      expiredAt: now,
    });
  });
  await batch.commit();
  // limit(200)에 도달했으면 미처리 항목이 남아 있을 수 있음 — 다음 실행 시 처리됨 (멱등성 보장)
  if (snap.size >= 200) {
    console.warn(`⚠️ [신분증 만료] limit(200) 도달 — 미처리 항목이 남아 있을 수 있습니다. 다음 실행에서 재처리됩니다.`);
  }
  console.log(`⏰ [신분증 만료] ${snap.size}건 expired 처리 완료`);
}

// ─── 24시간 이상 미퇴근 자동 처리 ───────────────────────────
/**
 * 자정 실행: checkIn은 있으나 checkOut이 없고 24시간 이상 경과한
 * attendance 문서를 "missed_checkout" 상태로 마킹.
 * 실제 퇴근 시각은 null 유지 → 관리자가 수동 수정.
 */
async function processMissedCheckouts(now: Timestamp): Promise<void> {
  const cutoff = new Date(now.toDate().getTime() - 24 * 60 * 60 * 1000);
  // [A-1-1 수정] checkIn!=null 조건 제거 — Firestore는 inequality filter(!=, <=)를
  // 단일 필드에만 허용하므로 checkIn!=null + createdAt<= 복합 사용 시 FAILED_PRECONDITION.
  // checkIn==null인 문서(체크인 없는 출근기록)는 아래 JS 필터에서 걸러냄.
  const snap = await db
    .collection("attendance")
    .where("checkOut", "==", null)
    .where("createdAt", "<=", Timestamp.fromDate(cutoff))
    .limit(499) // [BUG-ATT-01 수정] break(>=499)와 limit 일치 — 500번째 문서가 매번 누락되는 현상 방지
    .get();

  if (snap.empty) return;

  const batch = db.batch();
  let count = 0;
  for (const doc of snap.docs) {
    const data = doc.data();
    // checkIn이 없는 문서는 JS에서 후처리로 제외 (쿼리에서 !=null 조건 제거 보완)
    if (!data.checkIn) continue;
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
        .limit(500)
        .get(),
      db.collection("applications")
        .where("status", "in", CONFIRMED_STATUSES)
        .where("workEndDate", ">=", Timestamp.fromDate(windowStart))
        .where("workEndDate", "<=", Timestamp.fromDate(windowEnd))
        .limit(500)
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
            requestKey, year, month, "admin", businessId
          );
        }
        await _sendReviewRequestNotification(
          workerId, data.businessName ?? "사업장",
          requestKey, year, month, "worker", businessId
        );
      } catch (err: any) {
        // ALREADY_EXISTS(gRPC 코드 6)만 처리 — 다른 에러는 상위로 전파
        if (err?.code !== 6) throw err;
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
            requestKey, endYear, endMonth, "admin", businessId
          );
        }
        await _sendReviewRequestNotification(
          workerId, data.businessName ?? "사업장",
          requestKey, endYear, endMonth, "worker", businessId
        );
      } catch (err: any) {
        // ALREADY_EXISTS(gRPC 코드 6)만 처리 — 다른 에러는 상위로 전파
        if (err?.code !== 6) throw err;
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
      .limit(300)
      .get();

    if (snap.empty) {
      console.log("  ✅ [리뷰 공개] 만료된 요청 없음");
      return;
    }

    if (snap.size >= 300) {
      console.warn("  ⚠️ [리뷰 공개] 300건 limit 도달 — 다음 자정 실행에서 잔여 처리");
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
    const reviewType = data.reviewType as string | undefined;
    const reviewerId = data.reviewerId as string | undefined;

    // [특이사항] requestId 없는 리뷰는 Firestore 규칙이 근무 이력을 검증하지 못해
    // 가짜 리뷰가 Firestore에 잔류할 수 있음. 공개는 안 되지만 데이터 오염 방지 위해 삭제.
    if (!requestId) {
      try { await event.data?.ref.delete(); } catch (e) {
        console.error(`[가짜 리뷰 차단] requestId 없음 삭제 실패 (reviewId=${reviewId}):`, e);
      }
      console.log(`❌ [가짜 리뷰 차단] requestId 없음 → 삭제: ${reviewId}`);
      return;
    }

    // [특이사항] 타인의 requestId로 리뷰를 주입해 review_request를 오염시키는 공격 차단.
    // USER_TO_BUSINESS: review_requests.workerId == reviewerId 검증 (소유자 확인).
    // ADMIN_TO_USER는 adminUid 필드가 없으므로 Firestore 규칙의 isAdminOf(businessId)에 위임.
    // 검증과 상태 업데이트를 단일 트랜잭션으로 합쳐 review_requests 읽기를 1회로 절약.
    const isAdminReview = reviewType === "ADMIN_TO_USER";
    const statusField = isAdminReview ? "adminStatus" : "workerStatus";
    const reviewIdField = isAdminReview ? "adminReviewId" : "workerReviewId";
    const otherStatusField = isAdminReview ? "workerStatus" : "adminStatus";

    const reqRef = db.collection("review_requests").doc(requestId);
    const now = Timestamp.now();

    let shouldPublish = false;
    let otherReviewId: string | null = null;
    let blocked = false;

    // 트랜잭션: 가짜 리뷰 차단 검증 + 상태 원자적 업데이트 + 동시 공개 여부 확인
    await db.runTransaction(async (tx) => {
      const reqSnap = await tx.get(reqRef);
      if (!reqSnap.exists) {
        blocked = true;
        return;
      }

      const req = reqSnap.data()!;

      // 소유자 검증 (트랜잭션 안에서 수행 — 외부 읽기 제거)
      // USER_TO_BUSINESS: 익명 리뷰라 reviewerId 필드 없음 — Firestore rules에서 작성자 검증
      // ADMIN_TO_USER: reviewerId가 review_request.workerId와 일치해야 함 (J-2 버그 수정)
      if (reviewType !== "USER_TO_BUSINESS" && req.workerId !== reviewerId) {
        blocked = true;
        return;
      }

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

    if (blocked) {
      try { await event.data?.ref.delete(); } catch (e) {
        console.error(`[가짜 리뷰 차단] workerId 불일치 삭제 실패 (reviewId=${reviewId}):`, e);
      }
      console.log(`❌ [가짜 리뷰 차단] review_request 미존재 또는 workerId 불일치 → 삭제: ${reviewId}`);
      return;
    }

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

    // 통계 업데이트 — reqRef.get() 실패해도 공개는 이미 완료됐으므로 오류 격리
    try { // [CF-TRY-03 수정]
      const reqSnap = await reqRef.get();
      const req = reqSnap.data();
      if (req?.workerId) await updateUserReviewStats(req.workerId as string);
      if (req?.businessId) await updateBusinessReviewStats(req.businessId as string);
    } catch (err) {
      console.error(`[리뷰 통계 업데이트] ${requestId} 실패 — 공개는 완료:`, err);
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
    // [특이사항] 급여 확정 후 지원서가 취소/거절된 극히 드문 경쟁 조건에서
    // 무효한 review_request가 생성되지 않도록 상태 검증.
    if (!CONFIRMED_STATUSES.includes(app.status as string)) {
      console.log(
        `ℹ️ [임금 확정] 지원서 상태 불일치 — review_request 생성 스킵 (id=${applicationId}, status=${app.status})`
      );
      return;
    }
    const workerId = app.uid as string | undefined;
    const businessId = app.businessId as string | undefined;
    if (!workerId || !businessId) return;

    // [BUG-ATT-12 수정] workDate 누락 시 new Date() 폴백 → 서버 UTC 기준으로 잘못된 월에 review_request 생성.
    // 없으면 건너뛴다 — attendance에 workDate 없는 케이스는 데이터 무결성 문제이므로 스킵이 맞음.
    const workDate = (after.workDate as Timestamp | undefined)?.toDate();
    if (!workDate) {
      console.error(`[임금 확정] workDate 없음 → 리뷰 요청 생성 스킵: ${event.params.attendanceId}`);
      return;
    }
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
        requestKey, year, month, "admin", businessId
      );
      await _sendReviewRequestNotification(
        workerId, app.businessName ?? "사업장",
        requestKey, year, month, "worker", businessId
      );
      console.log(`✅ [임금 확정] 리뷰 요청 생성: ${requestKey}`);
    } catch (e: any) {
      // [WAGE-1-FIX] AlreadyExists(code 6) 외 오류는 재전파 → CF 런타임 재시도
      //   기존: catch {} 로 모든 오류 소거 → 네트워크 오류도 무시됨
      if ((e as any)?.code !== 6) throw e;
      // 이미 존재 (동일 월 중복 마감 처리 또는 CF 재시도)
      console.log(`  ℹ️ [임금 확정] 리뷰 요청 이미 존재: ${requestKey}`);
    }
  }
);

// ═══════════════════════════════════════════════════════════
// 💰 급여 summary 자동 집계 (wageStatus 변경 시)
// ═══════════════════════════════════════════════════════════

/**
 * attendance.wageStatus 변경 시 payroll_summaries 집계를 트랜잭션으로 갱신.
 * - 루트 문서: totalPayout, confirmedCount, workerCount (집계 필드만)
 * - 서브컬렉션 workers/{userId}: 근무자별 상세 (1MB 문서 한계 회피)
 * - * → confirmed : finalWage 더하기, workDays +1
 * - confirmed → * : finalWage 빼기, workDays -1
 * - confirmed → confirmed (금액 수정) : delta 적용
 */
export const onAttendanceWageChanged = onDocumentUpdated(
  {document: "attendance/{attendanceId}", region: "asia-northeast3"},
  async (event) => {
    // [M-003 수정] CF at-least-once 전달 보장으로 동일 이벤트 재실행 가능 → 중복 집계 방지
    // event.id를 _processedWageEvents 컬렉션에 기록해 멱등성 보장
    const eventId = event.id;
    const processedRef = db.collection("_processedWageEvents").doc(eventId);

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
    if (!rawDate) {
      console.warn(`[onAttendanceWageChanged] workDate 없음 — 월별 집계 생략 docId=${event.params.attendanceId}`);
      return;
    }
    const workDate = rawDate.toDate();
    const KST_OFFSET_MS_W = 9 * 60 * 60 * 1000;
    const workDateKST = new Date(workDate.getTime() + KST_OFFSET_MS_W);
    const year = workDateKST.getUTCFullYear();
    const monthNum = workDateKST.getUTCMonth() + 1;
    const monthStr = monthNum.toString().padStart(2, "0");
    const yearMonth = `${year}-${monthStr}`;
    const summaryId = `${businessId}_${yearMonth}`;
    const summaryRef = db.collection("payroll_summaries").doc(summaryId);
    const workerRef = summaryRef.collection("workers").doc(userId);

    // 근무자 이름 조회 (트랜잭션 외부 — Admin SDK read는 트랜잭션 밖에서 허용)
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
      // 중복 이벤트 체크 — 이미 처리된 eventId이면 즉시 반환
      const processedSnap = await tx.get(processedRef);
      if (processedSnap.exists) {
        console.log(`ℹ️ [급여집계] 이미 처리된 이벤트 스킵: ${eventId}`);
        return;
      }

      const summarySnap = await tx.get(summaryRef);
      const workerSnap = await tx.get(workerRef);
      const now = Timestamp.now();

      // 서브컬렉션에서 기존 근무자 데이터 조회
      const existingWorker: WorkerEntry = workerSnap.exists
        ? (workerSnap.data() as WorkerEntry)
        : {name: workerName, totalPayout: 0, workDays: 0};
      const newPayout = existingWorker.totalPayout + payoutDelta;
      const newDays = existingWorker.workDays + confirmedCountDelta;

      if (!summarySnap.exists) {
        if (!isConfirmed) return;
        // 루트 문서: 집계 필드만 (workers Map 없음)
        tx.set(summaryRef, {
          businessId,
          yearMonth,
          year,
          month: monthNum,
          totalPayout: afterWage,
          confirmedCount: 1,
          workerCount: 1,
          createdAt: now,
          updatedAt: now,
        });
        // 서브컬렉션에 근무자 상세 기록
        tx.set(workerRef, {
          name: workerName,
          totalPayout: afterWage,
          workDays: 1,
          updatedAt: now,
        });
        tx.set(processedRef, {processedAt: now, attendanceId: event.params.attendanceId});
        return;
      }

      const data = summarySnap.data() as Record<string, unknown>;
      const prevTotal = (data.totalPayout as number) ?? 0;
      const prevCount = (data.confirmedCount as number) ?? 0;
      const prevWorkerCount = (data.workerCount as number) ?? 0;

      // workerCount delta: 신규 근무자 +1, 마지막 근무 취소 -1, 기타 0
      const wasPresent = workerSnap.exists;
      const willPresent = newDays > 0;
      const workerCountDelta = (willPresent ? 1 : 0) - (wasPresent ? 1 : 0);

      tx.update(summaryRef, {
        totalPayout: Math.max(0, prevTotal + payoutDelta),
        confirmedCount: Math.max(0, prevCount + confirmedCountDelta),
        workerCount: Math.max(0, prevWorkerCount + workerCountDelta),
        updatedAt: now,
      });

      if (newDays <= 0) {
        // 해당 월 근무 확정 0건 → 서브컬렉션 문서 삭제
        if (wasPresent) tx.delete(workerRef);
      } else {
        tx.set(workerRef, {
          name: workerName || existingWorker.name,
          totalPayout: Math.max(0, newPayout),
          workDays: Math.max(0, newDays),
          updatedAt: now,
        });
      }

      // 처리 완료 표시 — TTL 정책으로 30일 후 자동 삭제 권장
      tx.set(processedRef, {processedAt: now, attendanceId: event.params.attendanceId});
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
  {region: "asia-northeast3", enforceAppCheck: true},
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
 * @param {string} businessId - CF 발신자-수신자 검증 및 딥링크 라우팅용
 */
async function _sendReviewRequestNotification(
  targetId: string,
  counterpartName: string,
  requestKey: string,
  year: number,
  month: number,
  role: "admin" | "worker",
  businessId: string
): Promise<void> {
  try {
    const title = "리뷰 작성 요청";
    const body =
      role === "admin" ?
        `${counterpartName}님에 대한 ${year}년 ${month}월 리뷰를 작성해주세요.` :
        `${counterpartName}에 대한 ${year}년 ${month}월 리뷰를 작성해주세요.`;

    // admin role: targetId = businessId → adminIds 배열 전체에 발송 (ownerId fallback)
    if (role === "admin") {
      const bizDoc = await db.collection("businesses").doc(targetId).get();
      const bizData = bizDoc.data();
      let adminIds: string[] = Array.isArray(bizData?.adminIds) ? (bizData!.adminIds as string[]) : [];
      if (adminIds.length === 0 && bizData?.ownerId) {
        adminIds = [bizData.ownerId as string];
      }
      if (adminIds.length === 0) {
        console.log(`  ⚠️ 리뷰 알림 스킵 — adminIds 없음 (bizId=${targetId})`);
        return;
      }
      for (const adminUid of adminIds) {
        await db.collection("users").doc(adminUid).collection("notifications").add({
          userId: adminUid,
          type: "REVIEW_REQUEST",
          title,
          body,
          data: {requestKey, action: "writeReview", businessId},
          isRead: false,
          createdAt: Timestamp.now(),
        });
      }
      return;
    }

    // worker role: targetId = workerUid
    const userId = targetId;
    await db.collection("users").doc(userId).collection("notifications").add({
      userId,
      type: "REVIEW_REQUEST",
      title,
      body,
      data: {requestKey, action: "writeReview", businessId},
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
    // [특이사항] limit(1000): 리뷰가 1000개 초과 시 통계가 부분적으로만 집계됨.
    // 현실적 최대치(앱 규모상 초과 가능성 낮음)이며, 초과 시 서버사이드 aggregation으로 개선 필요
    const snapshot = await db
      .collection("monthly_reviews")
      .where("targetUserId", "==", userId)
      .where("reviewType", "==", "ADMIN_TO_USER")
      .where("isPublished", "==", true)
      .limit(1000)
      .get();

    if (snapshot.empty) return;

    let totalRating = 0;
    let ratedCount = 0;
    let rehireYesCount = 0;
    let rehireRatedCount = 0;

    for (const doc of snapshot.docs) {
      const data = doc.data();
      const r = (data.rating as number) || 0;
      if (r > 0) { totalRating += r; ratedCount++; }
      // wouldRehire가 null/undefined인 리뷰는 분모에서 제외 (미응답으로 취급)
      if (data.wouldRehire != null) {
        rehireRatedCount++;
        if (data.wouldRehire === true) rehireYesCount++;
      }
    }

    const avgRating = ratedCount > 0 ? totalRating / ratedCount : null;
    // [특이사항] 재고용 의사(wouldRehire)를 미입력한 리뷰는 분모에서 제외.
    // snapshot.size(전체 리뷰 수)로 나누면 미응답이 '재고용 거부'로 계산되어 재고용률이 낮게 나옴.
    const rehireRate = rehireRatedCount > 0 ? rehireYesCount / rehireRatedCount : null;

    // [BUG-REV-05 수정] snapshot.size → ratedCount: rating=0 미입력 리뷰를 카운트에서 제외
    await db.collection("users").doc(userId).update({
      averageRating: avgRating,
      reviewCount: ratedCount,
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
    // [특이사항] limit(1000): 리뷰 1000개 초과 시 통계가 부분적으로만 집계됨 (updateUserReviewStats와 동일 제약)
    const snapshot = await db
      .collection("monthly_reviews")
      .where("businessId", "==", businessId)
      .where("reviewType", "==", "USER_TO_BUSINESS")
      .where("isPublished", "==", true)
      .limit(1000)
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
      reviewCount: ratedCount, // [CF-BUG-05] snapshot.size 대신 ratedCount — rating=0 미입력 건 제외
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
    .limit(500)
    .get();
  if (snapshot.size >= 500) {
    console.warn("  ⚠️ [예약공개] 500건 limit 도달 — 다음 실행에서 잔여 처리");
  }

  if (snapshot.empty) {
    console.log("  ✅ [예약공개] 공개할 TO 없음");
    return;
  }

  console.log(`  📋 [예약공개] 대상 TO: ${snapshot.size}개`);

  // [H-2] active TO 한도 — 예약 공개 시 사업장별 한도 초과 방지
  // 각 사업장의 현재 ACTIVE/FULL TO 수를 캐시해 N번 중복 Firestore 조회 방지
  const appConfigSnap = await db.collection("settings").doc("app_config").get();
  const maxActiveTOPerBusiness: number = (appConfigSnap.data()?.maxActiveTOPerBusiness as number | undefined) ?? 4;
  const bizActiveCounts = new Map<string, number>();

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

    // [H-2] 사업장별 active TO 한도 체크
    const bizId = data.businessId as string | undefined;
    if (bizId) {
      if (!bizActiveCounts.has(bizId)) {
        const countSnap = await db.collection("tos")
          .where("businessId", "==", bizId)
          .where("status", "in", ["ACTIVE", "FULL"])
          .count().get();
        bizActiveCounts.set(bizId, countSnap.data().count);
        // [W-2] 스냅샷 시점 카운트 — 다른 CF/클라이언트가 동시에 공개하면 실제 값과 차이 가능
        console.warn(`    ⚠️ [W-2] bizId=${bizId} active count 캐시=${countSnap.data().count} (TOCTOU — 동시 공개 시 한도 미초과 가능)`);
      }
      const currentActive = bizActiveCounts.get(bizId)!;
      if (currentActive >= maxActiveTOPerBusiness) {
        console.log(`    ⚠️ ${doc.id} 한도 초과(${currentActive}/${maxActiveTOPerBusiness}) — 공개 건너뜀`);
        continue;
      }
      bizActiveCounts.set(bizId, currentActive + 1);
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

  // 그룹 마스터 상태 동기화 — 병렬 처리로 N번 순차 쿼리 단축
  await Promise.all([...affectedGroupIds].map((gid) => syncGroupMasterStatus(db, gid)));
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
    .limit(500)
    .get();

  if (tosSnapshot.empty) {
    console.log("  ✅ [WorkDetail 마감] 활성 TO 없음");
    return;
  }

  if (tosSnapshot.size >= 500) {
    console.warn("  ⚠️ [WorkDetail 마감] 500건 limit 도달 — 다음 실행에서 잔여 처리");
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

    // [L001 수정] 만료된 workType의 PENDING 지원서를 AUTO_CANCELED로 처리
    // CF syncTOStats가 status 변경 시 totalPending을 자동 재계산하므로 카운터 직접 수정 불필요.
    // [CF-TRY-04 수정] per-workType try-catch — 단일 실패로 나머지 workType 처리 중단 방지
    for (const workType of expiredTypes) {
      try {
        const pendingApps = await db
          .collection("applications")
          .where("toId", "==", toId)
          .where("selectedWorkType", "==", workType)
          .where("status", "==", "PENDING")
          .get();
        if (!pendingApps.empty) {
          // [CF-PERF-01] 500건 초과 배치 분할 처리 — 상태+알림 원자성을 위해 249건씩 (2 ops/건)
          // [CF-NOTIF-01 수정] 알림을 배치에 포함 — commit 실패 시 상태·알림 모두 롤백되어 재시도 안전
          const BATCH_SIZE = 249;
          for (let bi = 0; bi < pendingApps.docs.length; bi += BATCH_SIZE) {
            const cancelBatch = db.batch();
            for (const appDoc of pendingApps.docs.slice(bi, bi + BATCH_SIZE)) {
              const d = appDoc.data();
              cancelBatch.update(appDoc.ref, {
                status: "AUTO_CANCELED",
                canceledAt: now,
                cancelReason: "WORK_DETAIL_EXPIRED",
              });
              if (d.uid) {
                cancelBatch.set(
                  db.collection("users").doc(d.uid as string).collection("notifications").doc(),
                  {
                    userId: d.uid,
                    type: "confirmationCanceled",
                    title: "지원 자동 취소",
                    body: `${d.businessName ?? "사업장"} 업무 상세가 마감되어 지원이 자동 취소되었습니다.`,
                    data: {applicationId: appDoc.id, businessId: (d.businessId as string) ?? "", screen: "mySchedule", reason: "WORK_DETAIL_EXPIRED"},
                    isRead: false,
                    createdAt: now,
                  }
                );
              }
            }
            await cancelBatch.commit();
          }
          console.log(`    → ${toId}/${workType} PENDING ${pendingApps.size}건 AUTO_CANCELED`);
        }
      } catch (err) {
        console.error(`[WorkDetail 마감] ${toId}/${workType} AUTO_CANCELED 처리 실패 — 나머지 계속:`, err);
      }
    }
  }

  if (batchCount > 0) await batch.commit();

  console.log(`  ✅ [WorkDetail 마감] ${totalClosed}개 마감 완료`);

  // 영향받은 TO들의 status 동기화
  // [CF-TRY-04 수정] per-TO try-catch — 단일 실패로 나머지 동기화 중단 방지
  for (const toId of affectedTOIds) {
    try {
      await syncTOStatusFromWorkDetails(db, toId);
    } catch (err) {
      console.error(`[WorkDetail 마감] TO ${toId} status 동기화 실패 — 나머지 계속:`, err);
    }
  }

  // 영향받은 그룹 마스터 동기화 — 병렬 처리
  await Promise.all([...affectedGroupIds].map((gid) => syncGroupMasterStatus(db, gid)));
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
  // limit(5000): 무제한 조회 시 비용 폭탄 방지 — 5000개 초과 슬롯은 다음 실행에서 처리됨
  // [SLOT-001 수정] "full" 슬롯도 포함 — full 슬롯도 PENDING 지원서가 있을 수 있음
  const slotsSnap = await db
    .collectionGroup("slots")
    .where("status", "in", ["open", "full"])
    .limit(5000)
    .get();

  if (slotsSnap.empty) {
    console.log("  ✅ [슬롯 WorkDetail 마감] 처리할 슬롯 없음");
    return;
  }

  console.log(`  📋 [슬롯 WorkDetail 마감] 오픈 슬롯: ${slotsSnap.size}개 검사`);

  let totalClosedDetails = 0;
  let totalClosedSlots = 0;
  const affectedTOIds = new Set<string>();

  // 1단계: 각 슬롯의 업데이트 내용 계산 (동기)
  type SlotPending = {
    slotDoc: FirebaseFirestore.QueryDocumentSnapshot;
    slotData: FirebaseFirestore.DocumentData;
    slotUpdate: Record<string, any>;
    expiredItems: any[];
    allDetailsClosed: boolean;
    toId: string | undefined;
  };
  const pending: SlotPending[] = [];

  for (const slotDoc of slotsSnap.docs) {
    const slotData = slotDoc.data();
    if (slotData.closedBy != null) continue;

    const workDetails: any[] = slotData.workDetails ?? [];
    if (workDetails.length === 0) continue;

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

    const expiredTypes = new Set(expiredItems.map((wd: any) => wd.workType as string));
    const updatedWorkDetails = workDetails.map((wd: any) =>
      expiredTypes.has(wd.workType) ? {...wd, closedAt: now, closedReason: "TIME_EXPIRED"} : wd
    );

    const allDetailsClosed = updatedWorkDetails.every(
      (wd: any) => wd.isEmergencyOpen === true || wd.closedAt != null
    );

    const slotUpdate: Record<string, any> = {workDetails: updatedWorkDetails};
    if (allDetailsClosed) {
      slotUpdate.status = "closed";
      slotUpdate.closedAt = now;
      slotUpdate.closedReason = "TIME_EXPIRED";
    }

    const toId =
      (slotData.toId as string | undefined) ?? slotDoc.ref.parent.parent?.id;

    pending.push({slotDoc, slotData, slotUpdate, expiredItems, allDetailsClosed, toId});
  }

  // 2단계: 병렬 업데이트 (Promise.allSettled → 개별 실패에도 나머지 계속 진행)
  const results = await Promise.allSettled(
    pending.map(({slotDoc, slotUpdate}) => slotDoc.ref.update(slotUpdate))
  );

  // 3단계: 결과 집계
  for (let i = 0; i < pending.length; i++) {
    const {slotDoc, expiredItems, allDetailsClosed, toId} = pending[i];
    const result = results[i];
    if (result.status === "rejected") {
      console.error(`⚠️ [슬롯 WorkDetail 마감] 슬롯 ${slotDoc.id} 업데이트 실패:`, result.reason);
      continue;
    }
    totalClosedDetails += expiredItems.length;
    if (allDetailsClosed) totalClosedSlots++;
    if (toId) {
      affectedTOIds.add(toId);
      expiredItems.forEach((wd: any) =>
        console.log(`    → ${toId}/${slotDoc.id}/${wd.workType} 마감`)
      );
    }
  }

  // [L003 수정] 만료된 슬롯 workType의 PENDING 지원서 → AUTO_CANCELED
  // processWorkDetailExpiry(L001)의 flex TO 버전 — 슬롯 단위 처리
  // slotId+selectedWorkType+status 복합 인덱스 사용 (firestore.indexes.json A02/S42 인덱스)
  // [CF-TRY-05 수정] per-workType try-catch — 단일 실패로 나머지 슬롯/workType 처리 중단 방지
  for (let i = 0; i < pending.length; i++) {
    if (results[i].status === "rejected") continue; // 슬롯 업데이트 실패 시 건너뜀
    const {slotDoc, expiredItems, toId} = pending[i];
    if (!toId) continue;
    const expiredTypes = [...new Set(expiredItems.map((wd: any) => wd.workType as string).filter(Boolean))];
    for (const workType of expiredTypes) {
      try {
        const pendingApps = await db
          .collection("applications")
          .where("toId", "==", toId)
          .where("slotId", "==", slotDoc.id)
          .where("selectedWorkType", "==", workType)
          .where("status", "==", "PENDING")
          .get();
        if (!pendingApps.empty) {
          // [CF-PERF-01] 500건 초과 배치 분할 처리 — 상태+알림 원자성을 위해 249건씩 (2 ops/건)
          // [CF-NOTIF-01 수정] 알림을 배치에 포함 — commit 실패 시 상태·알림 모두 롤백되어 재시도 안전
          const BATCH_SIZE = 249;
          for (let bi = 0; bi < pendingApps.docs.length; bi += BATCH_SIZE) {
            const cancelBatch = db.batch();
            for (const appDoc of pendingApps.docs.slice(bi, bi + BATCH_SIZE)) {
              const d = appDoc.data();
              cancelBatch.update(appDoc.ref, {
                status: "AUTO_CANCELED",
                canceledAt: now,
                cancelReason: "SLOT_WORK_DETAIL_EXPIRED",
              });
              if (d.uid) {
                cancelBatch.set(
                  db.collection("users").doc(d.uid as string).collection("notifications").doc(),
                  {
                    userId: d.uid,
                    type: "confirmationCanceled",
                    title: "지원 자동 취소",
                    body: `${d.businessName ?? "사업장"} 슬롯 업무 상세가 마감되어 지원이 자동 취소되었습니다.`,
                    data: {applicationId: appDoc.id, businessId: (d.businessId as string) ?? "", screen: "mySchedule", reason: "SLOT_WORK_DETAIL_EXPIRED"},
                    isRead: false,
                    createdAt: now,
                  }
                );
              }
            }
            await cancelBatch.commit();
          }
          console.log(`    → [L003] ${toId}/${slotDoc.id}/${workType} PENDING ${pendingApps.size}건 → AUTO_CANCELED`);
        }
      } catch (err) {
        console.error(`[슬롯 WorkDetail 마감] ${toId}/${slotDoc.id}/${workType} AUTO_CANCELED 처리 실패 — 나머지 계속:`, err);
      }
    }
  }

  console.log(
    `  ✅ [슬롯 WorkDetail 마감] 업무상세 ${totalClosedDetails}개, ` +
      `슬롯 ${totalClosedSlots}개 마감 완료`
  );

  // 영향받은 TO status를 슬롯 상태 기반으로 동기화
  // [CF-TRY-05 수정] per-TO try-catch
  for (const toId of affectedTOIds) {
    try {
      await syncTOStatusFromSlots(db, toId, now);
    } catch (err) {
      console.error(`[슬롯 WorkDetail 마감] TO ${toId} status 동기화 실패 — 나머지 계속:`, err);
    }
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

    // Flutter _maybeCascadeCloseExpiredTO와 동일 조건: open + full 모두 활성으로 판단
    const hasOpenSlot = slotsSnap.docs.some((doc) => {
      const d = doc.data();
      return !d.isManualClosed && (d.status === "open" || d.status === "full");
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
    .limit(500)
    .get();
  if (snapshot.size >= 500) {
    console.warn("  ⚠️ [TO 마감] 500건 limit 도달 — 다음 실행에서 잔여 처리");
  }

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

    // [CRITICAL-07 수정] flex TO: 슬롯 서브컬렉션도 함께 CLOSED 처리
    // processSlotWorkDetailExpiry는 applicationDeadline 기준으로 슬롯 workDetail을 닫지만,
    // TO 레벨 applicationDeadline이 슬롯 개별 마감보다 먼저 오면 슬롯이 open으로 남을 수 있음
    if (data.type === "flex" || data.toType === "flex") {
      const slotsSnap = await db.collection("tos").doc(doc.id).collection("slots")
        .where("status", "in", ["open", "full"]).get();
      if (!slotsSnap.empty) {
        const slotBatch = db.batch();
        for (const slotDoc of slotsSnap.docs) {
          slotBatch.update(slotDoc.ref, {
            status: "closed",
            closedAt: now,
            closedReason: "PARENT_TO_EXPIRED",
          });
        }
        await slotBatch.commit();
        console.log(`    → ${doc.id} flex 슬롯 ${slotsSnap.size}개 CLOSED`);
      }
    }

    // [L002 수정] TO 마감 시 남은 PENDING 지원서 AUTO_CANCELED 처리
    // processWorkDetailExpiry가 먼저 실행되므로 대부분은 이미 처리됨.
    // 이 블록은 안전망 역할 (processWorkDetailExpiry 실패·skip 시에도 처리 보장).
    // [CF-TRY-06 수정] try-catch — 단일 TO 처리 실패 시 나머지 TO 계속 처리
    try {
      const pendingApps = await db
        .collection("applications")
        .where("toId", "==", doc.id)
        .where("status", "==", "PENDING")
        .get();
      if (!pendingApps.empty) {
        // [CF-PERF-02] 500건 초과 배치 분할 처리 — 상태+알림 원자성을 위해 249건씩 (2 ops/건)
        // [CF-NOTIF-01 수정] 알림을 배치에 포함 — commit 실패 시 상태·알림 모두 롤백되어 재시도 안전
        const BATCH_SIZE = 249;
        for (let bi = 0; bi < pendingApps.docs.length; bi += BATCH_SIZE) {
          const cancelBatch = db.batch();
          for (const appDoc of pendingApps.docs.slice(bi, bi + BATCH_SIZE)) {
            const d = appDoc.data();
            cancelBatch.update(appDoc.ref, {
              status: "AUTO_CANCELED",
              canceledAt: now,
              cancelReason: "TO_EXPIRED",
            });
            if (d.uid) {
              cancelBatch.set(
                db.collection("users").doc(d.uid as string).collection("notifications").doc(),
                {
                  userId: d.uid,
                  type: "confirmationCanceled",
                  title: "지원 자동 취소",
                  body: `${d.businessName ?? "사업장"} 공고가 마감되어 지원이 자동 취소되었습니다.`,
                  data: {applicationId: appDoc.id, businessId: (d.businessId as string) ?? "", screen: "mySchedule", reason: "TO_EXPIRED"},
                  isRead: false,
                  createdAt: now,
                }
              );
            }
          }
          await cancelBatch.commit();
        }
        console.log(`    → ${doc.id} PENDING ${pendingApps.size}건 AUTO_CANCELED`);
      }
    } catch (err) {
      console.error(`[TO 마감] ${doc.id} PENDING AUTO_CANCELED 처리 실패 — 나머지 계속:`, err);
    }
  }

  if (batchCount > 0) await batch.commit();
  console.log(`  ✅ [TO 마감] ${tosToClose.length}개 완료!`);

  // 그룹 마스터 동기화 — 병렬 처리
  await Promise.all([...affectedGroupIds].map((gid) => syncGroupMasterStatus(db, gid)));
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

    // [BUG-ATT-03 수정] 단기+장기 근무자 모두 조회 — 기존엔 workDate==내일인 단기만 처리됨
    // 장기 근무자는 workDate가 계약 시작일로 고정되어 내일 날짜와 매칭되지 않음
    const KR_WEEKDAYS = ["일", "월", "화", "수", "목", "금", "토"];
    const tomorrowWeekday = KR_WEEKDAYS[tomorrowKST.getDay()];

    const [applicationsSnapshot, longTermSnap] = await Promise.all([
      // 단기 근무자: workDate == 내일
      db.collection("applications")
        .where("status", "in", CONFIRMED_STATUSES)
        .where("workDate", ">=", Timestamp.fromDate(tomorrow))
        .where("workDate", "<=", Timestamp.fromDate(tomorrowEnd))
        .limit(500)
        .get(),
      // 장기 근무자: workEndDate >= 내일 (만료되지 않은 계약)
      // [특이사항] workEndDate=null 무기한 계약은 이 쿼리에서 제외됨 (Firestore null 필터 불가)
      db.collection("applications")
        .where("status", "in", CONFIRMED_STATUSES)
        .where("workEndDate", ">=", Timestamp.fromDate(tomorrow))
        .limit(2000)
        .get(),
    ]);

    if (applicationsSnapshot.empty && longTermSnap.empty) {
      console.log("  ✅ [리마인더] 내일 근무 예정자 없음");
      return;
    }

    console.log(`  📋 [리마인더] 단기: ${applicationsSnapshot.size}건, 장기후보: ${longTermSnap.size}건`);

    // 오늘 KST 날짜 문자열 — applications.reminderSentDate 필드로 중복 방지
    // (collectionGroup("notifications") 전수 스캔 대신 이미 읽어온 applications 메모리 필터로 대체)
    const todayStr = `${nowKST.getFullYear()}-${String(nowKST.getMonth() + 1).padStart(2, "0")}-${String(nowKST.getDate()).padStart(2, "0")}`;

    // userId별로 근무 목록 묶기 — 오늘 이미 발송된 application은 제외
    const userJobsMap = new Map<string, admin.firestore.QueryDocumentSnapshot[]>();
    for (const appDoc of applicationsSnapshot.docs) {
      if (appDoc.data().reminderSentDate === todayStr) continue; // 재시도 시 중복 방지
      const uid = appDoc.data().uid as string;
      if (!uid) continue;
      if (!userJobsMap.has(uid)) userJobsMap.set(uid, []);
      userJobsMap.get(uid)!.push(appDoc);
    }
    // 장기 근무자 후보 — workDays 포함 여부·계약 시작일·중복 방지 후처리
    for (const appDoc of longTermSnap.docs) {
      const d = appDoc.data();
      const workDays = d.workDays as string[] | undefined;
      if (!workDays || workDays.length === 0) continue; // 단기 근무자 제외
      if (!workDays.includes(tomorrowWeekday)) continue; // 내일 요일 불일치
      const contractStart = (d.workDate as Timestamp | undefined)?.toDate();
      if (!contractStart || contractStart > tomorrowEnd) continue; // 아직 시작 안 된 계약
      if (d.reminderSentDate === todayStr) continue; // 오늘 이미 발송됨
      const uid = d.uid as string | undefined;
      if (!uid) continue;
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

        // [STRUCT-02] Firestore 먼저 (알림 저장 + reminderSentDate 배치 통합) → FCM fire-and-forget
        // 수정 전: FCM await 성공 → Firestore 배치 실패 시 재실행에서 중복 알림 발송
        // 수정 후: Firestore 커밋 성공 후 FCM 발송 → 실패해도 앱 내 알림은 보존, 재실행 시 중복 없음
        const reminderBatch = db.batch();
        const notifRef = db.collection("users").doc(userId).collection("notifications").doc();
        reminderBatch.set(notifRef, {
          userId,
          type: "workReminder",
          title: "내일 근무 알림",
          body: notifBody,
          data: { applicationId: jobs[0].id, action: "applicationDetail", businessId: jobs[0].data().businessId ?? "" },
          isRead: false,
          createdAt: now,
        });
        for (const appDoc of jobs) {
          reminderBatch.update(appDoc.ref, {reminderSentDate: todayStr});
        }
        await reminderBatch.commit(); // Firestore 원자적 기록 완료 → 이후 재실행 시 reminderSentDate 필터로 중복 방지

        // FCM 푸시 — fire-and-forget (실패해도 Firestore에 이미 기록됨)
        // workReminder 수신 설정 확인 (onNotificationCreated가 workReminder 스킵하므로 여기서 직접 처리)
        const notifPrefs = userData?.notifPrefs as Record<string, boolean> | undefined;
        if (notifPrefs?.["workReminder"] !== false) {
          // [G-001] fcmTokens 배열 우선 사용, 없으면 레거시 fcmToken 단일 필드 폴백
          const tokens: string[] =
            (userData?.fcmTokens as string[] | undefined)?.filter(Boolean) ??
            (userData?.fcmToken ? [userData.fcmToken as string] : []);
          if (tokens.length > 0) {
            // sendEachForMulticast: 단일 HTTP 요청으로 멀티 디바이스 발송
            admin.messaging().sendEachForMulticast({
              tokens,
              notification: {title: "내일 근무 알림 📅", body: fcmBody},
              // [FCM-05 수정] screen 필드 추가 — 탭 시 _navigateByPayload가 mySchedule로 이동
              // 기존엔 screen 없어 default → 알림 목록으로만 이동했음
              data: {type: "workReminder", applicationId: jobs[0].id, screen: "mySchedule",
                businessId: jobs[0].data().businessId ?? ""},
              android: {priority: "high", notification: {channelId: "alfit_notifications", sound: "default"}},
              apns: {payload: {aps: {sound: "default", badge: 1}}},
            }).then((multicastResp) => {
              const expiredReminderTokens = tokens.filter((_, i) => {
                const errCode = multicastResp.responses[i].error?.code ?? "";
                return (
                  errCode === "messaging/invalid-registration-token" ||
                  errCode === "messaging/registration-token-not-registered"
                );
              });
              if (expiredReminderTokens.length > 0) {
                db.collection("users").doc(userId).update({
                  fcmTokens: admin.firestore.FieldValue.arrayRemove(...expiredReminderTokens),
                }).catch((e) => console.error(`[리마인더] FCM 만료 토큰 정리 실패 userId=${userId}:`, e));
              }
            }).catch((e) => console.error(`    ❌ [리마인더] FCM 발송 실패 userId=${userId}:`, e));
          } else {
            console.log(`    ⚠️ FCM 토큰 없음 (리마인더 스킵): ${userId}`);
          }
        } else {
          console.log(`    ⚠️ 근무 리마인더 FCM 스킵 (수신 차단): ${userId}`);
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
    // applicationDeadline <= now 조건으로 범위를 좁혀 전수 조회 방지
    // (applicationDeadline이 없는 무기한 TO는 정합성 검사 대상 아님 → 필터 안전)
    const activeTOs = await db
      .collection("tos")
      .where("status", "==", "ACTIVE")
      .where("applicationDeadline", "<=", now)
      .limit(500)
      .get();
    if (activeTOs.size >= 500) {
      console.warn("  ⚠️ [정합성 검사] ACTIVE→CLOSED 대상 500건 limit 도달 — 다음 실행에서 나머지 처리");
    }

    let integrityBatch = db.batch();
    let integrityBatchCount = 0;

    for (const toDoc of activeTOs.docs) {
      const toData = toDoc.data();

      // closedBy 있음 = 관리자 직접마감 → 정합성 검사 대상 아님
      if (toData.closedBy != null) continue;

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

    if (integrityBatchCount > 0) await integrityBatch.commit();

    // 2. 슬롯 workDetail 만료 정합성 제거 — masterScheduler가 매 시간 processSlotWorkDetailExpiry를
    // 이미 실행하므로 새벽 3시 정합성 검사에서 재호출하면 이중 실행이 됨

    // 3. 모든 그룹 마스터 상태 재동기화
    const masterTOs = await db
      .collection("tos")
      .where("isGroupMaster", "==", true)
      .limit(500)
      .get();
    if (masterTOs.size >= 500) {
      console.warn("  ⚠️ [정합성 검사] 마스터 TO 500건 limit 도달 — 일부 누락 가능");
    }

    const processedGroupIds = new Set<string>();

    for (const masterDoc of masterTOs.docs) {
      const groupId = masterDoc.data().groupId as string | undefined;
      if (groupId) processedGroupIds.add(groupId);
    }
    // 병렬 동기화 — 중복 groupId는 Set이 제거
    await Promise.all([...processedGroupIds].map((gid) => syncGroupMasterStatus(db, gid)));

    // [IC-01 수정] _processedWageEvents 오래된 레코드 정리 (TTL 대용)
    // Firestore Native TTL은 콘솔 설정 필요 — 그 전까지 자정 작업에서 7일 이상 된 레코드를 삭제.
    // onAttendanceWageChanged 멱등성 보장용 컬렉션이므로 7일이면 재시도 윈도우를 충분히 커버.
    try {
      const sevenDaysAgo = Timestamp.fromMillis(now.toMillis() - 7 * 24 * 60 * 60 * 1000);
      const oldEvents = await db
        .collection("_processedWageEvents")
        .where("processedAt", "<=", sevenDaysAgo)
        .limit(500)
        .get();
      if (!oldEvents.empty) {
        const cleanBatch = db.batch();
        oldEvents.docs.forEach((doc) => cleanBatch.delete(doc.ref));
        await cleanBatch.commit();
        console.log(`  🧹 [정합성 검사] _processedWageEvents ${oldEvents.size}건 정리`);
      }
    } catch (cleanErr) {
      // 정리 실패는 비치명적 — 다음 자정 작업에서 재시도
      console.warn("  ⚠️ [정합성 검사] _processedWageEvents 정리 실패:", cleanErr);
    }

    // [F-2 보완] CONTRACT_PENDING limbo 탐지 — 배치 커밋 실패+롤백 실패 시 영구 limbo 가능성
    // 24시간 이상 CONTRACT_PENDING 상태인 지원서를 탐지해 콘솔 경고 출력 (자동 롤백은 위험 — 정상 처리 가능성)
    // 수동 수정 대상 목록을 로그로 남겨 슈퍼어드민이 확인하도록 함
    try {
      const oneDayAgo = Timestamp.fromMillis(now.toMillis() - 24 * 60 * 60 * 1000);
      const limboApps = await db
        .collection("applications")
        .where("status", "==", "CONTRACT_PENDING")
        .where("confirmedAt", "<=", oneDayAgo)
        .limit(50)
        .get();
      if (!limboApps.empty) {
        console.warn(`  ⚠️ [정합성 검사] CONTRACT_PENDING 24h+ limbo 의심 ${limboApps.size}건 — 수동 확인 필요:`);
        limboApps.docs.forEach((d) => {
          const data = d.data();
          console.warn(`    applicationId=${d.id} businessId=${data.businessId} uid=${data.uid} confirmedAt=${data.confirmedAt?.toDate().toISOString()}`);
        });
      }
    } catch (limboErr) {
      console.warn("  ⚠️ [정합성 검사] CONTRACT_PENDING limbo 탐지 실패:", limboErr);
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
      .limit(100)
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
      .where("workEndDate", "<=", d15End)
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

    // allSettled: users 또는 businesses 조회 일부 실패 시 나머지가 중단되지 않도록 개선
    const [usersResult, bizResult] = await Promise.allSettled([
      uidsNeedingLookup.length > 0
        ? Promise.all(uidsNeedingLookup.map((uid) => db.collection("users").doc(uid).get()))
        : Promise.resolve([]),
      d15BizIds.length > 0
        ? Promise.all(d15BizIds.map((id) => db.collection("businesses").doc(id).get()))
        : Promise.resolve([]),
    ]);
    const prefetchedUsers = usersResult.status === "fulfilled" ? usersResult.value : [];
    const prefetchedBiz = bizResult.status === "fulfilled" ? bizResult.value : [];

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

      // 사업장 관리자 목록 (pre-fetched map 사용, ownerId fallback)
      const bizData = d15BizMap.get(app.businessId as string);
      const adminIds: string[] = (() => {
        const ids = (bizData?.adminIds as string[] | undefined) ?? [];
        if (ids.length > 0) return ids;
        const fallback = bizData?.ownerId as string | undefined;
        return fallback ? [fallback] : [];
      })();

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
      .limit(200)
      .get();
    if (d0Snap.size >= 200) {
      console.warn("  ⚠️ [D-0] 200건 limit 도달 — 잔여 건 다음 실행에서 처리");
    }

    for (const doc of d0Snap.docs) {
      try { // [CF-TRY-01 수정] per-document 오류 격리 — 한 건 실패해도 나머지 계속 처리
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

      // [BUG-F-03 수정] KST 기준으로 날짜 계산 — Firestore Timestamp는 UTC이므로
      // Flutter가 DateTime(y,m,d) KST 자정으로 저장 → UTC 전날 15:00이 됨.
      // UTC 기준 getDate()는 전날을 반환해 newStartDate와 newEndDate가 1일 오차 발생.
      const oldEndDateKST = new Date(oldEndDate.getTime() + KST_OFFSET_MS);

      // 새 계약 시작: 다음날 (KST 기준 +1일 후 UTC로 복원)
      const newStartDateKST = new Date(oldEndDateKST);
      newStartDateKST.setDate(newStartDateKST.getDate() + 1);
      const newStartDate = new Date(newStartDateKST.getTime() - KST_OFFSET_MS);

      // 새 계약 종료: 기존 종료일 기준 renewalMonths 개월 후 (같은 날짜, 월말 clamp) — KST 기준
      const rawEndYear = oldEndDateKST.getFullYear() + Math.floor((oldEndDateKST.getMonth() + renewalMonths) / 12);
      const rawEndMonthZero = (oldEndDateKST.getMonth() + renewalMonths) % 12; // 0-based
      const lastDayOfMonth = new Date(rawEndYear, rawEndMonthZero + 1, 0).getDate();
      const newEndDateKST = new Date(rawEndYear, rawEndMonthZero, Math.min(oldEndDateKST.getDate(), lastDayOfMonth));
      const newEndDate = new Date(newEndDateKST.getTime() - KST_OFFSET_MS);

      // 새 Application 생성 + 기존 Application 갱신 — 원자적 배치
      const newAppRef = db.collection("applications").doc();
      const renewBatch = db.batch();
      // [CF-11 수정] ...app 스프레드 제거 → 화이트리스트 방식으로 필요 필드만 명시적 복사.
      // 이전에는 ...app으로 wageDetail·finalWage·wageStatus 등 집계 필드가 새 application에
      // 그대로 복사되었음. Flutter createRenewedApplication()도 copyWith+toMap() 화이트리스트 방식.
      renewBatch.set(newAppRef, {
        // ── 사업장/공고 식별 ──
        businessId: app.businessId,
        businessName: app.businessName,
        toTitle: app.toTitle ?? null,
        toId: app.toId ?? null,
        workDetailId: app.workDetailId ?? null,
        slotId: app.slotId ?? null,
        groupId: app.groupId ?? null,
        // ── 근무자 식별 ──
        uid: app.uid,
        applicantName: app.applicantName ?? null,
        // ── 근무 스케줄 (날짜는 새 기간으로 교체) ──
        workDate: Timestamp.fromDate(newStartDate),
        workEndDate: Timestamp.fromDate(newEndDate),
        workDays: app.workDays ?? null,
        startTime: app.startTime ?? null,
        endTime: app.endTime ?? null,
        // ── 업무 유형 ──
        selectedWorkType: app.selectedWorkType ?? null,
        originalWorkType: app.originalWorkType ?? null,
        originalWage: app.originalWage ?? null,
        changedAt: app.changedAt ?? null,
        changedBy: app.changedBy ?? null,
        workTypeIcon: app.workTypeIcon ?? null,
        workTypeColor: app.workTypeColor ?? null,
        workTypeBackgroundColor: app.workTypeBackgroundColor ?? null,
        // ── 임금 기본값 (TO 레벨 고정값 유지, 집계 필드는 초기화) ──
        wage: app.wage ?? 0,
        wageType: app.wageType ?? null,
        wageStatus: "pending",          // [CF-11] 집계 필드 초기화
        finalWage: null,                // [CF-11] 집계 필드 초기화
        wageDetail: null,               // [CF-11] 집계 필드 초기화
        wageConfirmedAt: null,          // [CF-11] 집계 필드 초기화
        wageTransferredAt: null,        // [CF-11] 집계 필드 초기화
        interimSettledAmount: 0,        // [CF-11] 집계 필드 초기화
        // ── 상태 ──
        status: "CONFIRMED",
        appliedAt: now,
        confirmedAt: now,
        confirmedBy: "SYSTEM",
        // ── 지원/확정 메시지 (이전 계약 승계 안 함) ──
        applicationMessage: null,
        confirmMessage: null,
        rejectMessage: null,
        cancelMessage: null,
        // ── 취소 관련 (초기화) ──
        canceledAt: null,
        cancelReason: null,
        conflictingAppId: null,
        conflictingBusiness: null,
        conflictingTime: null,
        // ── 연장 추적 ──
        renewedFromApplicationId: doc.id,
        renewalDecision: null,
        renewalNotifiedAt: null,
        renewedToApplicationId: null,
        // ── 희망 시작일 (초기화) ──
        desiredStartDate: null,
        // ── 휴무/추가근무 (이전 계약 날짜 승계 안 함) ──
        // [BUG-FIX] H-3: Flutter createRenewedApplication()과 동일하게 초기화.
        leaveDates: [],
        extraWorkDates: [],
        // ── 퇴사/계약해지 (초기화) ──
        resignStatus: null,
        resignRequestedAt: null,
        resignRequestDate: null,
        resignApprovedAt: null,
        resignApprovedBy: null,
        resignRejectedAt: null,
        resignRejectedBy: null,
        resignRejectReason: null,
        actualResignDate: null,
        terminationStatus: null,
        terminationRequestedAt: null,
        terminationReason: null,
        terminationEffectiveDate: null,
        terminationRequestedByUid: null,
        terminationRespondedAt: null,
        terminationRejectReason: null,
        // ── 기타 ──
        statusHistory: [],
        type: app.type ?? null,
        isStarred: false,
      });
      // 기존 Application 갱신 — 배치 실패 시 둘 다 미커밋 → 중복 연장 방지
      // [RENEWAL-001 수정] renewedToApplicationId 역참조 추가 — 원본→연장 양방향 추적
      //
      // [F-3 특이사항] 이전 application의 status가 CONFIRMED 그대로 남는 설계상 한계.
      // RENEWED 전용 상태가 없으므로 status를 변경하지 않는다.
      // 앱에서는 renewedToApplicationId != null 조건으로 "갱신된 이전 계약"을 식별 가능.
      // sendWorkReminders는 workDate=내일 쿼리이므로 기간 만료된 이전 계약은 자연히 제외됨.
      // processContractRenewalChecks도 workEndDate 기준이므로 다음 D-15/D-0에 이전 계약이 다시
      // 걸리지 않음 (renewalDecision="EXTEND" 필드로 이미 처리 완료 표시됨).
      // TODO: RENEWED 상태 추가 후 이전 application status 전환 필요 (Flutter+CF 동시 배포 필요)
      // [STRUCT-08] 알림을 배치에 포함 — commit 후 별도 .add() 발송 시 중간 실패로 알림 누락 방지
      const renewNotifRef = db.collection("users").doc(app.uid as string).collection("notifications").doc();
      renewBatch.set(renewNotifRef, {
        userId: app.uid,
        type: "contractRenewed",
        title: "계약 자동 연장",
        body: `${app.businessName} 계약이 ` +
          `${new Date(newEndDate.getTime() + KST_OFFSET_MS).getUTCMonth() + 1}/${new Date(newEndDate.getTime() + KST_OFFSET_MS).getUTCDate()}` +
          "까지 자동 연장되었습니다.",
        data: {
          applicationId: newAppRef.id,
          businessId: app.businessId,
          screen: "mySchedule",
        },
        isRead: false,
        createdAt: now,
      });
      renewBatch.update(doc.ref, {renewalDecision: "EXTEND", renewedToApplicationId: newAppRef.id});
      await renewBatch.commit(); // 새 application + 알림 + 기존 상태 변경 원자적 처리

      d0Count++;
      } catch (err) {
        console.error(`[D-0 자동연장] 문서 ${doc.id} 처리 실패 — 나머지 계속:`, err);
      }
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
      .limit(200)
      .get();

    for (const doc of d0TerminateSnap.docs) {
      try { // [CF-TRY-02 수정] per-document 오류 격리 — 한 건 실패해도 나머지 계속 처리
      const app = doc.data();
      if (!app.workDays || app.workDays.length === 0) continue;
      // 이미 종료 알림 보낸 경우 스킵 (terminationNotifiedAt 필드로 중복 방지)
      // [특이사항] 중복 방지 체크가 트랜잭션 없이 read-then-write — 스케줄 함수 동시 실행 시
      // 이론적으로 중복 발송 가능. 그러나 Cloud Scheduler는 동일 잡을 겹쳐 실행하지 않으므로 저위험.
      if (app.terminationCompletionNotifiedAt) continue;

      // [CF-NOTIF-01 수정] 알림+플래그를 배치로 원자 처리 — 알림 성공 후 update 실패 시 다음 실행에서 중복 발송 방지
      const termBatch = db.batch();
      termBatch.set(
        db.collection("users").doc(app.uid as string).collection("notifications").doc(),
        {
          userId: app.uid,
          type: "contractTerminating",
          title: "계약 종료 완료",
          body: `${app.businessName} 계약이 종료되었습니다. 이용해 주셔서 감사합니다.`,
          data: {applicationId: doc.id, businessId: app.businessId, screen: "mySchedule"},
          isRead: false,
          createdAt: now,
        }
      );
      termBatch.update(doc.ref, {terminationCompletionNotifiedAt: now});
      await termBatch.commit();
      terminateD0Count++;
      } catch (err) {
        console.error(`[D-0 종료알림] 문서 ${doc.id} 처리 실패 — 나머지 계속:`, err);
      }
    }
    console.log(`  ✅ [D-0 종료알림] ${terminateD0Count}건 처리`);

    // ── D+1 퇴사 대기 알림 (관리자에게 2일 남은 경고) ────────
    {
      const d1Start = new Date(todayKST.getTime() - 2 * 24 * 60 * 60 * 1000);
      const d1End   = new Date(todayKST.getTime() - 1 * 24 * 60 * 60 * 1000);
      const d1Snap = await db.collection("applications")
        .where("resignStatus", "==", "PENDING")
        .where("resignRequestedAt", ">=", Timestamp.fromDate(new Date(d1Start.getTime() - KST_OFFSET_MS)))
        .where("resignRequestedAt", "<",  Timestamp.fromDate(new Date(d1End.getTime()   - KST_OFFSET_MS)))
        .limit(200).get();
      await Promise.all(d1Snap.docs.map(async (d1Doc) => {
        try {
          const app = d1Doc.data();
          const bizSnap = await db.collection("businesses").doc(app.businessId).get();
          const bizData = bizSnap.exists ? bizSnap.data() : undefined;
          const adminIds: string[] = (() => {
            const ids = (bizData?.adminIds as string[] | undefined) ?? [];
            if (ids.length > 0) return ids;
            const fb = bizData?.ownerId as string | undefined;
            return fb ? [fb] : [];
          })();
          await Promise.all(adminIds.map((aid) =>
            db.collection("users").doc(aid).collection("notifications").add({
              userId: aid,
              type: "resignReminder",
              title: "⏰ 퇴사 요청 미처리 알림",
              body: `${app.applicantName ?? "근무자"}님의 퇴사 요청 후 1일이 지났습니다. 2일 내 미처리 시 자동 승인됩니다.`,
              data: {applicationId: d1Doc.id, businessId: app.businessId, screen: "fixedWorker"},
              isRead: false,
              createdAt: now,
            })
          ));
        } catch (e) {
          console.error(`[D+1 퇴사 알림] 실패 ${d1Doc.id}:`, e);
        }
      }));
    }

    // ── D+2 퇴사 긴급 알림 (내일 자동 승인 경고) ─────────────
    {
      const d2Start = new Date(todayKST.getTime() - 3 * 24 * 60 * 60 * 1000);
      const d2End   = new Date(todayKST.getTime() - 2 * 24 * 60 * 60 * 1000);
      const d2Snap = await db.collection("applications")
        .where("resignStatus", "==", "PENDING")
        .where("resignRequestedAt", ">=", Timestamp.fromDate(new Date(d2Start.getTime() - KST_OFFSET_MS)))
        .where("resignRequestedAt", "<",  Timestamp.fromDate(new Date(d2End.getTime()   - KST_OFFSET_MS)))
        .limit(200).get();
      await Promise.all(d2Snap.docs.map(async (d2Doc) => {
        try {
          const app = d2Doc.data();
          const bizSnap = await db.collection("businesses").doc(app.businessId).get();
          const bizData = bizSnap.exists ? bizSnap.data() : undefined;
          const adminIds: string[] = (() => {
            const ids = (bizData?.adminIds as string[] | undefined) ?? [];
            if (ids.length > 0) return ids;
            const fb = bizData?.ownerId as string | undefined;
            return fb ? [fb] : [];
          })();
          await Promise.all(adminIds.map((aid) =>
            db.collection("users").doc(aid).collection("notifications").add({
              userId: aid,
              type: "resignReminder",
              title: "⚠️ 퇴사 요청 긴급 처리 필요",
              body: `${app.applicantName ?? "근무자"}님의 퇴사 요청이 내일 자동 승인됩니다. 지금 바로 처리해 주세요.`,
              data: {applicationId: d2Doc.id, businessId: app.businessId, screen: "fixedWorker"},
              isRead: false,
              createdAt: now,
            })
          ));
        } catch (e) {
          console.error(`[D+2 퇴사 알림] 실패 ${d2Doc.id}:`, e);
        }
      }));
    }

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
      .limit(200)
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
          // [RESIGNATION-001 수정] status="CANCELED" 설정 시 cancelReason 명시
          // cancelReason 없으면 일반 취소와 구분 불가 → 퇴사 처리 원인 추적 불가
          tx.update(doc.ref, {
            resignStatus: "AUTO_APPROVED",
            resignApprovedAt: now,
            actualResignDate: Timestamp.fromDate(actualResignDate),
            status: "CANCELED",
            canceledAt: now,
            cancelReason: "RESIGNATION_APPROVED",
          });
        });

        // 퇴직 확정 → Auth 토큰 즉시 무효화 (로그아웃 없이도 접근 차단)
        try {
          await admin.auth().revokeRefreshTokens(app.uid as string);
        } catch (tokenErr) {
          console.warn(`[퇴직] revokeRefreshTokens 실패 uid=${app.uid}: ${tokenErr}`);
          await db.collection("pending_token_revocations").doc(app.uid as string).set({
            uid: app.uid,
            reason: "RESIGNATION_AUTO_APPROVED",
            applicationId: app.id,
            failedAt: now,
          }).catch(() => {/* 기록 실패는 무시 */});
        }

        // [R-H4/H5/H6-FIX] AUTO_APPROVED 수동 approveResignation()과 동일하게 3가지 정리 추가
        // 수동 승인 경로에만 있던 처리(카운터·계약서·attendance)를 AUTO_APPROVED에도 적용
        try {
          const resignPendingContractStatuses = ["pending_employer", "pending_worker"];
          const resignConfirmedStatuses = ["CONFIRMED", "CONTRACT_PENDING"];
          const resignCleanupBatch = db.batch();

          // [R-H6] TO totalConfirmed 카운터 감소 — 이전 status가 확정 상태였던 경우만
          if (app.toId && resignConfirmedStatuses.includes(app.status as string)) {
            const toRef = db.collection("tos").doc(app.toId as string);
            const toCounterUpdate: {[key: string]: admin.firestore.FieldValue} = {
              totalConfirmed: admin.firestore.FieldValue.increment(-1),
            };
            if (!app.slotId && app.selectedWorkType) {
              toCounterUpdate[`workTypeConfirmedCounts.${app.selectedWorkType}`] =
                admin.firestore.FieldValue.increment(-1);
            }
            resignCleanupBatch.update(toRef, toCounterUpdate);
            if (app.slotId) {
              const slotRef = toRef.collection("slots").doc(app.slotId as string);
              const slotCounterUpdate: {[key: string]: admin.firestore.FieldValue} = {
                confirmedCount: admin.firestore.FieldValue.increment(-1),
              };
              if (app.selectedWorkType) {
                slotCounterUpdate[`workTypeCounts.${app.selectedWorkType}.confirmedCount`] =
                  admin.firestore.FieldValue.increment(-1);
              }
              resignCleanupBatch.update(slotRef, slotCounterUpdate);
            }
          }

          // [R-H5] 서명 대기 계약서 voided 전환 (applicationId 직접 매칭 → applicationIds arrayContains 순서)
          const resignContractQ1 = await db.collection("employment_contracts")
            .where("applicationId", "==", doc.id)
            .where("businessId", "==", app.businessId)
            .limit(5).get();
          let resignContractsToVoid = resignContractQ1.docs.filter(
            (d) => resignPendingContractStatuses.includes(d.data().status as string)
          );
          if (resignContractsToVoid.length === 0) {
            const resignContractQ2 = await db.collection("employment_contracts")
              .where("applicationIds", "array-contains", doc.id)
              .where("businessId", "==", app.businessId)
              .limit(5).get();
            resignContractsToVoid = resignContractQ2.docs.filter(
              (d) => resignPendingContractStatuses.includes(d.data().status as string)
            );
          }
          for (const contractDoc of resignContractsToVoid) {
            resignCleanupBatch.update(contractDoc.ref, {
              status: "voided", contractVoidedAt: now, voidReason: "RESIGNATION",
            });
          }
          await resignCleanupBatch.commit();

          // [R-H4] actualResignDate 이후 scheduled attendance → absent 처리 (orphan 방지)
          const resignScheduledSnap = await db.collection("attendance")
            .where("applicationId", "==", doc.id)
            .where("status", "==", "scheduled").get();
          if (!resignScheduledSnap.empty) {
            let attBatch = db.batch();
            let attCount = 0;
            for (const attDoc of resignScheduledSnap.docs) {
              const workDate = (attDoc.data().workDate as {toDate(): Date} | undefined)?.toDate();
              if (workDate && workDate >= actualResignDate) {
                attBatch.update(attDoc.ref, {status: "absent", updatedAt: now});
                attCount++;
                if (attCount >= 499) {
                  await attBatch.commit();
                  attBatch = db.batch();
                  attCount = 0;
                }
              }
            }
            if (attCount > 0) await attBatch.commit();
          }
        } catch (cleanupErr) {
          // 정리 실패 시에도 알림은 발송 (CF reconcileTOStats가 카운터를 교정함)
          console.error(`[D+3 퇴사 AUTO_APPROVED] 정리 실패 ${doc.id}:`, cleanupErr);
        }

        // 근무자에게 자동 승인 알림
        // [FCM-03 수정] businessId 누락 → notification_screen resignApproved 분기에서
        // IntegratedWorkforceScreen(initialBusinessId: null)로 열리는 버그 방지
        await db.collection("users").doc(app.uid as string).collection("notifications").add({
          userId: app.uid,
          type: "resignApproved",
          title: "퇴사 요청 자동 승인",
          body: `${app.businessName} 퇴사 요청이 자동 승인되었습니다.`,
          data: {applicationId: doc.id, businessId: app.businessId, action: "resignDetail"},
          isRead: false,
          createdAt: now,
        });

        // 관리자에게도 알림 (ownerId fallback)
        const bizDoc = await db.collection("businesses").doc(app.businessId).get();
        const bizDocData = bizDoc.exists ? bizDoc.data() : undefined;
        const resignAdminIds: string[] = (() => {
          const ids = (bizDocData?.adminIds as string[] | undefined) ?? [];
          if (ids.length > 0) return ids;
          const fallback = bizDocData?.ownerId as string | undefined;
          return fallback ? [fallback] : [];
        })();
        await Promise.all(resignAdminIds.map((adminId) => db.collection("users").doc(adminId).collection("notifications").add({
          userId: adminId,
          type: "resignApproved",
          title: "퇴사 요청 자동 승인됨",
          body: `${app.applicantName ?? "근무자"}님의 퇴사 요청이 자동 승인되었습니다.`,
          // [E-1-B 수정] businessId 추가 — notification_screen resignApproved 케이스에서
          // initialBusinessId를 인자로 전달할 때 null이 되는 버그 방지
          // [FCM-01] screen: "fixedWorker" — FCM background 딥링크로 관리자 IntegratedWorkforceScreen 직접 이동
          data: {applicationId: doc.id, businessId: app.businessId, screen: "fixedWorker"},
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
      .limit(200)
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

        // 퇴직 확정 → Auth 토큰 즉시 무효화 (로그아웃 없이도 접근 차단)
        try {
          await admin.auth().revokeRefreshTokens(app.uid as string);
        } catch (tokenErr) {
          console.warn(`[퇴직] revokeRefreshTokens 실패 uid=${app.uid}: ${tokenErr}`);
          await db.collection("pending_token_revocations").doc(app.uid as string).set({
            uid: app.uid,
            reason: "TERMINATION_AUTO_APPROVED",
            applicationId: app.id,
            failedAt: now,
          }).catch(() => {/* 기록 실패는 무시 */});
        }

        // [R-H5/H6-FIX] AUTO_APPROVED 수동 approveTermination()과 동일하게 계약서+카운터 정리
        // [C04 설계 의도] 계약해지는 terminationEffectiveDate 기반 isWorkingOnDate 처리
        //                 → scheduled attendance 정리는 불필요 (퇴사와 다름)
        try {
          const termPendingStatuses = ["pending_employer", "pending_worker"];
          const termConfirmedStatuses = ["CONFIRMED", "CONTRACT_PENDING"];
          const termCleanupBatch = db.batch();

          // [R-H6] TO totalConfirmed 카운터 감소 — 이전 status가 확정 상태였던 경우만
          if (app.toId && termConfirmedStatuses.includes(app.status as string)) {
            const toRef = db.collection("tos").doc(app.toId as string);
            const toCounterUpdate: {[key: string]: admin.firestore.FieldValue} = {
              totalConfirmed: admin.firestore.FieldValue.increment(-1),
            };
            if (!app.slotId && app.selectedWorkType) {
              toCounterUpdate[`workTypeConfirmedCounts.${app.selectedWorkType}`] =
                admin.firestore.FieldValue.increment(-1);
            }
            termCleanupBatch.update(toRef, toCounterUpdate);
            if (app.slotId) {
              const slotRef = toRef.collection("slots").doc(app.slotId as string);
              const slotCounterUpdate: {[key: string]: admin.firestore.FieldValue} = {
                confirmedCount: admin.firestore.FieldValue.increment(-1),
              };
              if (app.selectedWorkType) {
                slotCounterUpdate[`workTypeCounts.${app.selectedWorkType}.confirmedCount`] =
                  admin.firestore.FieldValue.increment(-1);
              }
              termCleanupBatch.update(slotRef, slotCounterUpdate);
            }
          }

          // [R-H5] 서명 대기 계약서 voided 전환
          const termContractQ1 = await db.collection("employment_contracts")
            .where("applicationId", "==", doc.id)
            .where("businessId", "==", app.businessId)
            .limit(5).get();
          let termContractsToVoid = termContractQ1.docs.filter(
            (d) => termPendingStatuses.includes(d.data().status as string)
          );
          if (termContractsToVoid.length === 0) {
            const termContractQ2 = await db.collection("employment_contracts")
              .where("applicationIds", "array-contains", doc.id)
              .where("businessId", "==", app.businessId)
              .limit(5).get();
            termContractsToVoid = termContractQ2.docs.filter(
              (d) => termPendingStatuses.includes(d.data().status as string)
            );
          }
          for (const contractDoc of termContractsToVoid) {
            termCleanupBatch.update(contractDoc.ref, {
              status: "voided", contractVoidedAt: now, voidReason: "TERMINATION",
            });
          }
          await termCleanupBatch.commit();
        } catch (cleanupErr) {
          console.error(`[D+3 계약해지 AUTO_APPROVED] 정리 실패 ${doc.id}:`, cleanupErr);
        }

        // 근무자에게 자동 승인 알림
        await db.collection("users").doc(app.uid as string).collection("notifications").add({
          userId: app.uid,
          type: "terminationApproved",
          title: "계약해지 자동 승인",
          body: `${app.businessName} 계약해지 요청이 자동 승인되었습니다.`,
          // [E-1-A 수정] businessId 추가 — mySchedule 딥링크 라우팅 일관성 보장
          data: {applicationId: doc.id, businessId: app.businessId, action: "terminationDetail"},
          isRead: false,
          createdAt: now,
        });

        // [BUG-CF-03 수정] 관리자에게도 계약해지 자동승인 알림 — 퇴사(resignApproved)와 일관성 유지 (ownerId fallback)
        const terminationBizDoc = await db.collection("businesses").doc(app.businessId as string).get();
        const terminationBizData = terminationBizDoc.exists ? terminationBizDoc.data() : undefined;
        const terminationAdminIds: string[] = (() => {
          const ids = (terminationBizData?.adminIds as string[] | undefined) ?? [];
          if (ids.length > 0) return ids;
          const fallback = terminationBizData?.ownerId as string | undefined;
          return fallback ? [fallback] : [];
        })();
        await Promise.all(terminationAdminIds.map((adminId) =>
          db.collection("users").doc(adminId).collection("notifications").add({
            userId: adminId,
            type: "terminationApproved",
            title: "계약해지 자동 승인됨",
            body: `${app.applicantName ?? "근무자"}님의 계약해지 요청이 자동 승인되었습니다.`,
            // [FCM-01] screen: "fixedWorker" — FCM background 딥링크로 관리자 IntegratedWorkforceScreen 직접 이동
            data: {applicationId: doc.id, businessId: app.businessId, screen: "fixedWorker"},
            isRead: false,
            createdAt: now,
          })
        ));

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
  {region: "asia-northeast3", enforceAppCheck: true},
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
    console.log(`[SENS MOCK] SMS to ${to.slice(0, 3)}****${to.slice(-4)}: [코드 마스킹]`);
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
  {region: "asia-northeast3", enforceAppCheck: true},
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

    // [마스킹] 전화번호 전체 Cloud Logging 노출 방지 (개인정보처리방침)
    console.log(`✅ SMS 발송 완료: ${phone.slice(0, 3)}****${phone.slice(-4)} (SENS_ENABLED=${SENS_ENABLED})`);
    return {success: true};
  }
);

/**
 * 휴대폰 SMS 인증번호 확인
 * - 코드 일치/만료/시도횟수 초과 검사
 * - 성공 시 문서 즉시 삭제 (코드 재사용 차단)
 */
export const verifySmsCode = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    const phone = (request.data.phone as string | undefined)?.replace(/-/g, "");
    const code = request.data.code as string | undefined;

    if (!phone || !code) {
      throw new HttpsError("invalid-argument", "전화번호와 인증번호를 입력해주세요.");
    }

    // 한국 휴대폰 번호 형식 강제 — 브루트포스로 임의 문서 ID 접근 차단
    if (!/^01[0-9]{8,9}$/.test(phone)) {
      throw new HttpsError("invalid-argument", "유효하지 않은 전화번호 형식입니다.");
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

      // 인증 성공 — 문서 즉시 삭제로 코드 재사용 원천 차단.
      // verified: true 업데이트 대신 삭제: TTL 만료 전 동일 코드로 재시도 가능했던 취약점 수정.
      // 삭제 후 가입/비밀번호재설정 CF는 별도 상태(passToken, passwordResetCodes)로 완료 여부를 관리한다.
      tx.delete(docRef);
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
    // retry: true 필수 — cascade 중 실패 시 서브컬렉션이 부분 정리된 채로 남을 수 있음.
    // 재시도 시 이미 삭제된 문서는 delete()가 no-op이므로 멱등하게 처리됨.
    retry: true,
  },
  async (event) => {
    const businessId = event.params.businessId;
    console.log(`사업장 삭제 cascade 시작: ${businessId}`);

    // [STRUCT-07] limit 없는 get()은 수만 건 문서 시 CF 메모리 초과 위험 — 500건 단위 페이지네이션으로 안전 삭제
    const PAGE = 499; // Firestore batch 500건 제한 안전 마진
    async function deleteSubcollection(collPath: string) {
      let last: FirebaseFirestore.DocumentSnapshot | undefined;
      while (true) {
        let q: FirebaseFirestore.Query = db.collection(collPath).limit(PAGE);
        if (last) q = q.startAfter(last);
        const snap = await q.get();
        if (snap.empty) break;
        const batch = db.batch();
        snap.docs.forEach((doc) => batch.delete(doc.ref));
        await batch.commit();
        if (snap.docs.length < PAGE) break;
        last = snap.docs[snap.docs.length - 1];
      }
    }
    // [M-3] businessId 필드 기준 페이지네이션 삭제 헬퍼
    async function deleteByBusinessId(collectionPath: string) {
      let last: FirebaseFirestore.DocumentSnapshot | undefined;
      while (true) {
        let q: FirebaseFirestore.Query = db.collection(collectionPath)
          .where("businessId", "==", businessId)
          .limit(PAGE);
        if (last) q = q.startAfter(last);
        const snap = await q.get();
        if (snap.empty) break;
        const batch = db.batch();
        snap.docs.forEach((doc) => batch.delete(doc.ref));
        await batch.commit();
        if (snap.docs.length < PAGE) break;
        last = snap.docs[snap.docs.length - 1];
      }
    }

    // 서브컬렉션 삭제
    await deleteSubcollection(`businesses/${businessId}/workTypes`);
    await deleteSubcollection(`businesses/${businessId}/members`);
    await deleteSubcollection(`businesses/${businessId}/contract_templates`); // [B-M1-FIX]

    // [BB-001] 수락된 멤버의 subAdminOf 초기화 + 초대 문서 삭제
    const acceptedInviteSnap = await db
      .collection("member_invitations")
      .where("businessId", "==", businessId)
      .where("status", "==", "accepted")
      .limit(2000)
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
      .limit(2000)
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

    // 해당 사업장의 TO 목록 — [STRUCT-07 FIX] 200건씩 페이지네이션으로 OOM 방지
    const TO_PAGE_SIZE = 200;
    let lastToDoc: FirebaseFirestore.QueryDocumentSnapshot | undefined;
    const allGroupIds = new Set<string>();

    while (true) {
      const baseToQuery = db
        .collection("tos")
        .where("businessId", "==", businessId)
        .limit(TO_PAGE_SIZE);
      const tosPage = await (lastToDoc ? baseToQuery.startAfter(lastToDoc) : baseToQuery).get();
      if (tosPage.empty) break;

      const toIds = tosPage.docs.map((d) => d.id);
      const chunkSize = 30;

      for (let i = 0; i < toIds.length; i += chunkSize) {
        const chunk = toIds.slice(i, i + chunkSize);

        // CONFIRMED/CONTRACT_PENDING 지원서 → CANCELED
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

        // [D-BIZ-01] PENDING 지원서 → AUTO_CANCELED (사업장 삭제로 인한 자동 취소)
        const pendingAppsSnap = await db
          .collection("applications")
          .where("toId", "in", chunk)
          .where("status", "==", "PENDING")
          .get();

        if (!pendingAppsSnap.empty) {
          const batchSize = 499;
          for (let k = 0; k < pendingAppsSnap.docs.length; k += batchSize) {
            const pendingBatch = db.batch();
            const slice = pendingAppsSnap.docs.slice(k, k + batchSize);
            for (const doc of slice) {
              pendingBatch.update(doc.ref, {
                status: "AUTO_CANCELED",
                cancelReason: "BUSINESS_DELETED",
                canceledAt: Timestamp.now(),
              });
            }
            await pendingBatch.commit();
          }
        }
      }

      // [D-BIZ-05] TO 삭제 전 slots 서브컬렉션 orphan 방지 — 각 TO의 slots를 먼저 정리
      for (const toDoc of tosPage.docs) {
        await deleteSubcollection(`tos/${toDoc.id}/slots`);
      }

      // [NEW-06] groups 수집 (전체 페이지 완료 후 일괄 삭제)
      for (const toDoc of tosPage.docs) {
        const gid = toDoc.data().groupId as string | undefined;
        if (gid) allGroupIds.add(gid);
      }

      // TO 문서 삭제 (500건 분할)
      let tosBatch = db.batch();
      let tosCount = 0;
      for (const doc of tosPage.docs) {
        tosBatch.delete(doc.ref);
        tosCount++;
        if (tosCount % 500 === 0) {
          await tosBatch.commit();
          tosBatch = db.batch();
        }
      }
      if (tosCount % 500 !== 0) await tosBatch.commit();

      if (tosPage.size < TO_PAGE_SIZE) break;
      lastToDoc = tosPage.docs[tosPage.docs.length - 1];
    }

    // [NEW-06] groups 컬렉션 정리 — 모든 페이지에서 수집한 groupId 일괄 삭제
    if (allGroupIds.size > 0) {
      let groupBatch = db.batch();
      let groupCount = 0;
      for (const gid of allGroupIds) {
        groupBatch.delete(db.collection("groups").doc(gid));
        groupCount++;
        if (groupCount % 500 === 0) {
          await groupBatch.commit();
          groupBatch = db.batch();
        }
      }
      if (groupCount % 500 !== 0) await groupBatch.commit();
    }

    // [SEC-32] idCardAccessRequests 정리 — 신분증 열람 요청 기록 삭제
    const idCardSnap = await db
      .collection("idCardAccessRequests")
      .where("requesterBusinessId", "==", businessId)
      .get();
    if (!idCardSnap.empty) {
      let idCardBatch = db.batch();
      let idCardCount = 0;
      for (const doc of idCardSnap.docs) {
        idCardBatch.delete(doc.ref);
        idCardCount++;
        if (idCardCount % 500 === 0) {
          await idCardBatch.commit();
          idCardBatch = db.batch();
        }
      }
      if (idCardCount % 500 !== 0) await idCardBatch.commit();
    }

    // [M-3] 고아 데이터 cascade — schedule_change_requests, employment_contracts,
    //       monthly_reviews, payment_change_requests, interim_settlement_requests
    await deleteByBusinessId("schedule_change_requests");
    await deleteByBusinessId("employment_contracts");
    await deleteByBusinessId("monthly_reviews");
    await deleteByBusinessId("payment_change_requests");
    await deleteByBusinessId("interim_settlement_requests");

    // [NEW-08] review_requests 정리 — 사업장 연관 리뷰 요청 삭제
    const reviewRequestsSnap = await db
      .collection("review_requests")
      .where("businessId", "==", businessId)
      .get();
    if (!reviewRequestsSnap.empty) {
      let rrBatch = db.batch();
      let rrCount = 0;
      for (const doc of reviewRequestsSnap.docs) {
        rrBatch.delete(doc.ref);
        rrCount++;
        if (rrCount % 500 === 0) {
          await rrBatch.commit();
          rrBatch = db.batch();
        }
      }
      if (rrCount % 500 !== 0) await rrBatch.commit();
    }

    // [BB-003] 모든 관리자의 managedBusinessIds에서 삭제된 사업장 ID 제거 (adminIds 기준)
    const deletedData = event.data?.data();
    const allAdminIds: string[] = deletedData
      ? (Array.isArray(deletedData.adminIds) ? deletedData.adminIds
        : (deletedData.ownerId ? [deletedData.ownerId as string] : []))
      : [];
    if (allAdminIds.length > 0) {
      const adminBatch = db.batch();
      for (const adminUid of allAdminIds) {
        adminBatch.update(db.collection("users").doc(adminUid), {
          managedBusinessIds: admin.firestore.FieldValue.arrayRemove(businessId),
        });
      }
      await adminBatch.commit();
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
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    const purpose = request.data.purpose as string | undefined;
    if (!purpose || !["register", "resetPassword"].includes(purpose)) {
      throw new HttpsError("invalid-argument", "purpose는 'register' 또는 'resetPassword'여야 합니다.");
    }

    const isMock = process.env.DANAL_MOCK_MODE === "true";
    // [SEC-MOCK] production에서 mock 모드 사용 차단 — GCLOUD_PROJECT로 prod 감지
    if (isMock && process.env.GCLOUD_PROJECT === "alfit-prod") {
      throw new HttpsError("unavailable", "DANAL_MOCK_MODE는 production에서 사용할 수 없습니다.");
    }
    if (isMock) {
      return {
        txSeq: `MOCK-${Date.now()}`,
        authUrl: "https://mock.danal.example.com/auth",
        isMock: true,
      };
    }

    // [TODO-DANAL] 실제 다날 API 호출 — txSeq + authUrl 발급
    // 계약 완료 후 다날 SDK / REST API 연동 필요
    throw new HttpsError("unimplemented", "서비스 준비 중입니다.");
  }
);

// ── callableBlacklistUser ────────────────────────────────
// 블랙리스트 등록 + Firebase Auth 세션 즉시 무효화 (슈퍼어드민 전용)
// revokeRefreshTokens는 Admin SDK 필요 → CF 경유 필수
// Input:  { targetUid: string, blacklistReason: string }
// Output: { success: true }
export const callableBlacklistUser = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;
    const callerSnap = await db.collection("users").doc(callerUid).get();
    if (callerSnap.data()?.role !== "SUPER_ADMIN") {
      throw new HttpsError("permission-denied", "슈퍼어드민만 사용 가능합니다.");
    }
    const {targetUid, blacklistReason} = request.data as {targetUid: string; blacklistReason: string};
    if (!targetUid || typeof targetUid !== "string") {
      throw new HttpsError("invalid-argument", "targetUid가 올바르지 않습니다.");
    }
    if (!blacklistReason || typeof blacklistReason !== "string" || blacklistReason.length > 500) {
      throw new HttpsError("invalid-argument", "사유가 올바르지 않습니다 (최대 500자).");
    }
    // targetUid 존재 여부 사전 확인 (없으면 update가 NOT_FOUND 에러 — 의미 있는 메시지로 대체)
    const targetSnap = await db.collection("users").doc(targetUid).get();
    if (!targetSnap.exists) {
      throw new HttpsError("not-found", "대상 사용자를 찾을 수 없습니다.");
    }
    await db.collection("users").doc(targetUid).update({
      isBlacklisted: true,
      blacklistReason,
      blacklistedBy: callerUid,
      blacklistedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    try {
      await admin.auth().revokeRefreshTokens(targetUid);
    } catch (err) {
      console.error(`[블랙리스트] revokeRefreshTokens 실패: ${targetUid}`, err);
      await db.collection("pending_token_revocations").add({
        uid: targetUid,
        reason: "blacklist",
        failedAt: admin.firestore.FieldValue.serverTimestamp(),
        callerUid,
      });
    }
    return {success: true};
  }
);

// ── callableUnblacklistUser ───────────────────────────────
// 블랙리스트 해제 — callableBlacklistUser의 대칭 역방향 CF (슈퍼어드민 전용)
// 등록은 revokeRefreshTokens 필요, 해제는 세션 유지 (재로그인 불필요)
// Firestore rules의 클라이언트 직접 isBlacklisted write 차단을 우회하기 위해 Admin SDK 사용
// Input:  { targetUid: string }
// Output: { success: true }
export const callableUnblacklistUser = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;
    const callerSnap = await db.collection("users").doc(callerUid).get();
    if (callerSnap.data()?.role !== "SUPER_ADMIN") {
      throw new HttpsError("permission-denied", "슈퍼어드민만 사용 가능합니다.");
    }
    const {targetUid} = request.data as {targetUid: string};
    if (!targetUid || typeof targetUid !== "string") {
      throw new HttpsError("invalid-argument", "targetUid가 올바르지 않습니다.");
    }
    const targetSnap = await db.collection("users").doc(targetUid).get();
    if (!targetSnap.exists) {
      throw new HttpsError("not-found", "대상 사용자를 찾을 수 없습니다.");
    }
    if (!(targetSnap.data()?.isBlacklisted as boolean | undefined)) {
      throw new HttpsError("failed-precondition", "블랙리스트 상태가 아닙니다.");
    }
    await db.collection("users").doc(targetUid).update({
      isBlacklisted: false,
      blacklistReason: admin.firestore.FieldValue.delete(),
      unblacklistedBy: callerUid, // 서버 검증된 UID — 클라이언트 위조 불가
      unblacklistedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return {success: true};
  }
);

// ── callableResetPenalty ──────────────────────────────────
// 노쇼 제재 해제 + noShowCount 초기화 (슈퍼어드민 전용)
// noShowCount·restrictedUntil은 CF Admin SDK 전용 필드 (규칙에서 클라이언트 차단)
// Input:  { targetUid: string }
// Output: { success: true }
export const callableResetPenalty = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;
    const callerSnap = await db.collection("users").doc(callerUid).get();
    if (callerSnap.data()?.role !== "SUPER_ADMIN") {
      throw new HttpsError("permission-denied", "슈퍼어드민만 사용 가능합니다.");
    }
    const {targetUid} = request.data as {targetUid: string};
    if (!targetUid || typeof targetUid !== "string") {
      throw new HttpsError("invalid-argument", "targetUid가 올바르지 않습니다.");
    }
    const targetSnap = await db.collection("users").doc(targetUid).get();
    if (!targetSnap.exists) {
      throw new HttpsError("not-found", "대상 사용자를 찾을 수 없습니다.");
    }
    if (!targetSnap.data()?.restrictedUntil) {
      throw new HttpsError("failed-precondition", "제재 상태가 아닙니다.");
    }
    await db.collection("users").doc(targetUid).update({
      restrictedUntil: admin.firestore.FieldValue.delete(),
      noShowCount: 0,
      restrictionReleasedBy: callerUid, // 서버 검증된 UID
      restrictionReleasedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return {success: true};
  }
);

// ── callableAdjustTrustScore ──────────────────────────────
// 신뢰도 점수 수동 조정 (슈퍼어드민 전용)
// trustScore는 CF Admin SDK 전용 필드 (규칙에서 클라이언트 차단)
// Input:  { targetUid: string, score: number (0~100) }
// Output: { success: true }
export const callableAdjustTrustScore = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;
    const callerSnap = await db.collection("users").doc(callerUid).get();
    if (callerSnap.data()?.role !== "SUPER_ADMIN") {
      throw new HttpsError("permission-denied", "슈퍼어드민만 사용 가능합니다.");
    }
    const {targetUid, score} = request.data as {targetUid: string; score: number};
    if (!targetUid || typeof targetUid !== "string") {
      throw new HttpsError("invalid-argument", "targetUid가 올바르지 않습니다.");
    }
    if (typeof score !== "number" || !Number.isInteger(score) || score < 0 || score > 100) {
      throw new HttpsError("invalid-argument", "score는 0~100 사이 정수여야 합니다.");
    }
    const targetSnap = await db.collection("users").doc(targetUid).get();
    if (!targetSnap.exists) {
      throw new HttpsError("not-found", "대상 사용자를 찾을 수 없습니다.");
    }
    await db.collection("users").doc(targetUid).update({
      trustScore: score,
      trustScoreAdjustedBy: callerUid, // 서버 검증된 UID
      trustScoreAdjustedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return {success: true};
  }
);

// ── callableSaveSeal ─────────────────────────────────────
// 인감/서명 등록·삭제 — Admin SDK 경유로 sealBase64 필드를 저장.
// firestore.rules에서 클라이언트 직접 쓰기를 차단하므로 반드시 이 CF 경유 필요.
// Input:  { sealBase64: string|null, sealType: 'stamp'|'signature' }
// Output: { success: true }
export const callableSaveSeal = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const uid = request.auth.uid;
    const {sealBase64, sealType} = request.data as {sealBase64: string | null; sealType: string};

    if (!["stamp", "signature"].includes(sealType)) {
      throw new HttpsError("invalid-argument", "sealType이 올바르지 않습니다.");
    }

    // base64 500KB 원본 기준 → base64 문자열 최대 ~670KB
    if (sealBase64 && sealBase64.length > 700000) {
      throw new HttpsError("invalid-argument", "이미지 크기가 너무 큽니다 (최대 500KB).");
    }
    // base64 포맷 검증 — 임의 바이너리/스크립트 저장 방지 (data URI 접두어 포함 허용)
    if (sealBase64) {
      const b64Body = sealBase64.startsWith("data:") ? sealBase64.split(",")[1] : sealBase64;
      if (!b64Body || !/^[A-Za-z0-9+/]+=*$/.test(b64Body)) {
        throw new HttpsError("invalid-argument", "sealBase64가 유효한 Base64 형식이 아닙니다.");
      }
    }

    await db.collection("users").doc(uid).update({
      sealBase64: sealBase64 ?? null,
      sealType: sealBase64 ? sealType : "stamp",
    });

    return {success: true};
  }
);

// ── verifyPassAuth ───────────────────────────────────────
// 다날 encData 복호화 → 연령/CI 중복/재가입 검증 → passToken(15분) 발급
// Input:  { encData, txSeq, purpose, role? }
// Output: { passToken, name, gender, birthDate, phone }
export const verifyPassAuth = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    const {purpose, role = "USER"} = request.data as {
      encData?: string;
      txSeq?: string;
      purpose?: string;
      role?: string;
    };

    if (!purpose || !["register", "resetPassword", "reauth"].includes(purpose)) {
      throw new HttpsError("invalid-argument", "purpose가 올바르지 않습니다.");
    }

    if (!["USER", "BUSINESS_ADMIN"].includes(role)) {
      throw new HttpsError("invalid-argument", "role이 올바르지 않습니다.");
    }

    const isMock = process.env.DANAL_MOCK_MODE === "true";
    // [SEC-MOCK] production에서 mock 모드 사용 차단
    if (isMock && process.env.GCLOUD_PROJECT === "alfit-prod") {
      throw new HttpsError("unavailable", "DANAL_MOCK_MODE는 production에서 사용할 수 없습니다.");
    }

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
      throw new HttpsError("unimplemented", "서비스 준비 중입니다.");
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

// ── finalizeRegistration ─────────────────────────────────
// 가입 완료 후 passToken 소비 (삭제) + ciHash를 users/{uid}에 복사
// [AUTH-H3] verifyPassAuth의 register 토큰은 가입 경로에서 소비되지 않아 15분 재사용 가능.
//   가입 성공 직후 이 CF를 호출하여 토큰을 즉시 무효화한다.
// Input:  { passToken }
// Output: { success: true }
export const finalizeRegistration = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "로그인 필요");
    }
    const {passToken} = request.data as {passToken?: string};
    if (!passToken || typeof passToken !== "string") {
      throw new HttpsError("invalid-argument", "passToken 필수");
    }
    // mock 토큰은 개발 환경에서만 허용 — production에서는 차단
    if (passToken.startsWith("mock-")) {
      if (process.env.GCLOUD_PROJECT === "alfit-prod") {
        throw new HttpsError("unavailable", "mock 토큰은 production에서 사용할 수 없습니다.");
      }
      return {success: true};
    }

    const tokenRef = db.collection("passTokens").doc(passToken);
    const tokenSnap = await tokenRef.get();
    if (!tokenSnap.exists) {
      // 이미 소비됐거나 만료된 토큰 — 멱등 처리
      return {success: true};
    }
    const tokenData = tokenSnap.data() ?? {};
    if (tokenData["purpose"] !== "register") {
      throw new HttpsError("permission-denied", "register 토큰만 소비 가능");
    }

    // ciHash를 users/{uid}에 복사 (비밀번호 찾기 CI 매칭에 필요)
    const ciHash = tokenData["ciHash"] as string | undefined;
    if (ciHash) {
      await db.collection("users").doc(request.auth.uid).update({ciHash});
    }
    // 토큰 즉시 삭제 (일회용)
    await tokenRef.delete();
    return {success: true};
  }
);

// ── finalizePassReauth ───────────────────────────────────
// 재인증(설정 > 본인인증) 완료 후 passToken 소비 + ciHash/passVerifiedAt Admin SDK로 저장
// [H-5] 클라이언트 직접 ci/passVerifiedAt write → CF Admin SDK 경유로 전환
//   → passVerifiedAt에 serverTimestamp 강제 (법적 타임스탬프 위조 차단)
//   → ciHash 교체 차단: 기존 ciHash 일치 여부 CF에서 검증
// Input:  { passToken }
// Output: { success: true }
export const finalizePassReauth = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인 필요");
    const uid = request.auth.uid;
    const {passToken} = request.data as {passToken?: string};
    if (!passToken || typeof passToken !== "string") {
      throw new HttpsError("invalid-argument", "passToken 필수");
    }

    // mock 토큰 — 개발 환경 전용
    if (passToken.startsWith("mock-")) {
      if (process.env.GCLOUD_PROJECT === "alfit-prod") {
        throw new HttpsError("unavailable", "mock 토큰은 production에서 사용할 수 없습니다.");
      }
      await db.collection("users").doc(uid).update({
        passVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return {success: true};
    }

    const tokenRef = db.collection("passTokens").doc(passToken);
    const tokenSnap = await tokenRef.get();
    if (!tokenSnap.exists) {
      throw new HttpsError("not-found", "유효하지 않거나 이미 소비된 인증 토큰입니다.");
    }
    const tokenData = tokenSnap.data() ?? {};

    // 만료 체크
    const expiresAt = (tokenData["expiresAt"] as Timestamp | undefined)?.toDate();
    if (!expiresAt || new Date() > expiresAt) {
      await tokenRef.delete();
      throw new HttpsError("deadline-exceeded", "인증 토큰이 만료되었습니다. 다시 인증해주세요.");
    }

    const ciHash = tokenData["ciHash"] as string | undefined;
    if (!ciHash) {
      throw new HttpsError("internal", "인증 토큰에 ciHash 정보가 없습니다.");
    }

    // 기존 ciHash가 있으면 일치 여부 검증 — 타인 CI로 계정 乗っ取り 차단
    const userSnap = await db.collection("users").doc(uid).get();
    if (!userSnap.exists) {
      throw new HttpsError("not-found", "사용자를 찾을 수 없습니다.");
    }
    const existingCiHash = (userSnap.data() ?? {})["ciHash"] as string | undefined;
    if (existingCiHash && existingCiHash !== ciHash) {
      throw new HttpsError("permission-denied", "본인 계정의 CI와 일치하지 않습니다.");
    }

    // Admin SDK로 ciHash, passVerifiedAt(서버 시각) 저장
    await db.collection("users").doc(uid).update({
      ciHash,
      passVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    // passToken 일회용 소비
    await tokenRef.delete();

    return {success: true};
  }
);

// [SEC-CONTRACT-PDF-HASH] 계약서 Storage 파일 롤백 헬퍼
// storage.rules contracts/ 경로: allow delete: if false → 클라이언트 삭제 불가.
// CF 실패 시 Admin SDK로만 정리 가능. 파일별 실패는 경고만 — 전체 흐름 중단 않음.
async function _cleanupContractFiles(contractId: string): Promise<void> {
  const bkt = admin.storage().bucket();
  for (const p of [
    `contracts/${contractId}/signature_worker.png`,
    `contracts/${contractId}/contract.pdf`,
  ]) {
    try {
      await bkt.file(p).delete();
    } catch (err) {
      console.warn(`⚠️ [K-006] Storage 정리 실패 (고아 파일 주의) — ${p}:`, err);
    }
  }
}

// ── callableFinalizeWorkerSignature ─────────────────────
// 근무자 서명 완료 + application CONTRACT_PENDING→CONFIRMED 원자 처리
// [SEC-CONTRACT-H1] firestore.rules에서 클라이언트 직접 전이 차단 — CF Admin SDK 전용 경로.
// [SEC-CONTRACT-PDF-HASH] CF가 Storage에서 PDF를 직접 다운로드 → SHA-256(pdfHash) 계산 →
//   pdfUrl + pdfHash를 Firestore에 저장. 클라이언트가 pdfUrl을 전달하지 않으므로
//   조작된 URL·다른 파일로 교체 불가.
//   한계: PDF 내용 자체는 클라이언트 ContractPdfBuilder 생성 — 서버 사이드 PDF 생성 시 완전 차단.
//   현재 설계: pdfHash와 Firestore articles를 대조하면 향후 분쟁 시 불일치 감지 가능.
// [NOTE-DELETE-RULES] storage.rules contracts/ 경로는 allow delete: if false.
//   CF 실패 시 클라이언트 롤백 불가 → 이 함수 내부에서 Admin SDK로 직접 정리.
// Input:  { contractId, sigUrl, workerSignatureHash }
// Output: { success: true, pdfUrl: string }
export const callableFinalizeWorkerSignature = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");

    const {contractId, sigUrl, workerSignatureHash} = request.data;
    if (!contractId || typeof contractId !== "string") {
      throw new HttpsError("invalid-argument", "contractId가 필요합니다.");
    }
    if (!sigUrl || typeof sigUrl !== "string" || sigUrl.length > 2048) {
      throw new HttpsError("invalid-argument", "sigUrl이 필요합니다.");
    }
    // [M-03-FIX] sigUrl이 해당 contractId 경로인지 검증
    //   → 타인 서명 URL 주입으로 타인 서명이 계약서에 등록되는 공격 차단
    const sigPathMatch = sigUrl.match(/\/o\/([^?#]+)/);
    if (!sigPathMatch) {
      throw new HttpsError("invalid-argument", "유효하지 않은 서명 이미지 URL 형식입니다.");
    }
    const sigStoragePath = decodeURIComponent(sigPathMatch[1]);
    if (!sigStoragePath.startsWith(`contracts/${contractId}/`)) {
      throw new HttpsError("permission-denied", "해당 계약서의 서명 이미지만 등록 가능합니다.");
    }
    if (!workerSignatureHash || typeof workerSignatureHash !== "string") {
      throw new HttpsError("invalid-argument", "workerSignatureHash가 필요합니다.");
    }

    const bucket = admin.storage().bucket();

    // ── PDF 다운로드 + 해시 계산 (트랜잭션 외부 — Storage 읽기는 tx 불가)
    // 클라이언트가 업로드한 contracts/{contractId}/contract.pdf를 Admin SDK로 직접 읽음.
    // pdfUrl을 클라이언트에서 전달받지 않으므로 URL 위·변조 불가.
    let pdfHash: string;
    let computedPdfUrl: string;
    try {
      const pdfFile = bucket.file(`contracts/${contractId}/contract.pdf`);
      const [exists] = await pdfFile.exists();
      if (!exists) {
        throw new HttpsError(
          "not-found",
          "PDF 파일을 찾을 수 없습니다. Storage 업로드 후 다시 시도하세요."
        );
      }

      const [buffer] = await pdfFile.download();
      pdfHash = crypto.createHash("sha256").update(buffer).digest("hex");

      // Firebase Storage 다운로드 URL — 업로드 시 자동 발급된 토큰 기반
      const [metadata] = await pdfFile.getMetadata();
      const token = (metadata.metadata as Record<string, string>)
        ?.firebaseStorageDownloadTokens;
      if (!token) {
        throw new HttpsError("internal", "PDF 다운로드 토큰을 가져올 수 없습니다.");
      }
      const encodedPath = encodeURIComponent(`contracts/${contractId}/contract.pdf`);
      computedPdfUrl =
        `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/` +
        `${encodedPath}?alt=media&token=${token}`;
    } catch (e) {
      // PDF 다운로드/해시 실패 → Storage 파일 Admin SDK로 정리 (클라이언트 삭제는 rules 차단)
      await _cleanupContractFiles(contractId);
      throw e;
    }

    const contractRef = db.collection("employment_contracts").doc(contractId);

    try {
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(contractRef);
        if (!snap.exists) {
          throw new HttpsError("not-found", "계약서를 찾을 수 없습니다.");
        }
        const data = snap.data()!;

        // 본인 계약서 검증 (타인 계약서 서명 차단)
        if (data["workerId"] !== uid) {
          throw new HttpsError("permission-denied", "본인의 계약서만 서명할 수 있습니다.");
        }

        // 상태 검증 (race condition 방어 — Storage 업로드 후 상태 역전 대응)
        const status = data["status"] as string;
        if (status === "voided") {
          throw new HttpsError("failed-precondition", "무효 처리된 계약서에는 서명할 수 없습니다.");
        }
        if (status === "completed") {
          throw new HttpsError("failed-precondition", "이미 완료된 계약서입니다.");
        }
        if (status === "pending_employer") {
          throw new HttpsError("failed-precondition", "사업주 서명이 완료되기 전에는 근무자가 서명할 수 없습니다.");
        }
        if (data["workerSignatureUrl"]) {
          throw new HttpsError("failed-precondition", "이미 근무자 서명이 완료된 계약서입니다.");
        }

        // employment_contracts 완료 처리
        tx.update(contractRef, {
          status: "completed",
          workerSignatureUrl: sigUrl,
          workerSignatureHash: workerSignatureHash,
          workerSignedAt: admin.firestore.FieldValue.serverTimestamp(),
          pdfUrl: computedPdfUrl,
          // [SEC-CONTRACT-PDF-HASH] CF가 직접 계산 — 클라이언트 전달 값 불사용
          pdfHash: pdfHash,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // applications CONTRACT_PENDING → CONFIRMED (Admin SDK 전용 경로)
        const applicationIds: string[] = Array.isArray(data["applicationIds"])
          ? (data["applicationIds"] as string[])
          : [];
        for (const appId of applicationIds) {
          const appRef = db.collection("applications").doc(appId);
          const appSnap = await tx.get(appRef);
          if (appSnap.exists && appSnap.data()?.["status"] === "CONTRACT_PENDING") {
            tx.update(appRef, {
              status: "CONFIRMED",
              statusHistory: admin.firestore.FieldValue.arrayUnion({
                status: "CONFIRMED",
                at: admin.firestore.Timestamp.now(),
                by: "SYSTEM",
                action: "CONTRACT_SIGNED",
              }),
            });
          }
        }
      });
    } catch (e) {
      // 트랜잭션 실패 → Storage 파일 Admin SDK로 정리 (클라이언트 삭제는 rules 차단)
      await _cleanupContractFiles(contractId);
      throw e;
    }

    return {success: true, pdfUrl: computedPdfUrl};
  }
);

// ── recordDeletedAccount ────────────────────────────────
// 탈퇴 기록을 deleted_accounts에 Admin SDK로 저장
// [AUTH-H2] 클라이언트가 deleted_accounts에 직접 쓰면 탈퇴 안 한 상태에서 임의 문서를
//   심을 수 있어 재가입 차단 우회 가능. Admin SDK 경유로 전환하고 rules는 if false로 차단.
// Input:  {} (호출자 uid로 users 문서를 직접 조회)
// Output: { success: true }
export const recordDeletedAccount = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "로그인 필요");
    }
    const uid = request.auth.uid;

    const userSnap = await db.collection("users").doc(uid).get();
    if (!userSnap.exists) {
      return {success: true}; // 이미 삭제됨 — 멱등 처리
    }
    const data = userSnap.data() ?? {};

    // ciHash: finalizeRegistration CF가 다날 연동 후 설정 (없으면 null)
    const ciHash = data["ciHash"] as string | undefined;
    // phoneHash: phone 필드를 SHA-256으로 해시 (폴백)
    const phone = data["phone"] as string | undefined;
    const phoneHash = phone
      ? crypto.createHash("sha256").update(phone).digest("hex")
      : undefined;

    if (!ciHash && !phoneHash) {
      return {success: true}; // 식별자 없음 — 기록 불필요
    }

    const isBlacklisted = data["isBlacklisted"] === true;
    const docData: Record<string, unknown> = {
      uid,
      deletedAt: admin.firestore.FieldValue.serverTimestamp(),
      isBlacklisted,
      noShowCount: data["noShowCount"] ?? 0,
      role: data["role"] ?? "USER",
    };
    if (ciHash) docData["ciHash"] = ciHash;
    if (phoneHash) docData["phoneHash"] = phoneHash;
    if (!isBlacklisted) {
      docData["canReregisterAt"] = admin.firestore.Timestamp.fromDate(
        new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)
      );
    }

    await db.collection("deleted_accounts").add(docData);
    return {success: true};
  }
);

// ── revokeUserSession ───────────────────────────────────
// 본인 세션 무효화 — 비밀번호 변경 후 다른 기기 강제 로그아웃
// [AUTH-M1] 클라이언트 updatePassword()는 다른 기기 리프레시 토큰을 무효화하지 않음.
//   Admin SDK를 통해 revokeRefreshTokens를 호출해야 다른 기기 세션이 만료됨.
export const revokeUserSession = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "로그인 필요");
    }
    await admin.auth().revokeRefreshTokens(request.auth.uid);
    return {success: true};
  }
);

// ── callableRecordTermsConsent ───────────────────────────
// [D1] 법적 타임스탬프(termsConsentAt)를 서버에서 강제 발급 — Charter: 법적 타임스탬프 CF 필수
// 클라이언트는 동의 여부(agreed)와 버전(version)만 전달, 시각은 Admin SDK serverTimestamp 사용
// 호출 시점: 가입 완료 직후 (Auth UID 확보 후)
export const callableRecordTermsConsent = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;
    const {consentRecord} = request.data as {
      consentRecord: Record<string, {agreed: boolean; version: string}>;
    };
    if (!consentRecord || typeof consentRecord !== "object" || Array.isArray(consentRecord)) {
      throw new HttpsError("invalid-argument", "consentRecord가 필요합니다.");
    }
    // [M-04-FIX] 항목 수·키 길이 제한 — 무제한 입력으로 Firestore 문서 크기 초과 방지
    const entries = Object.entries(consentRecord);
    if (entries.length > 20) {
      throw new HttpsError("invalid-argument", "consentRecord 항목이 너무 많습니다.");
    }

    const serverTime = admin.firestore.FieldValue.serverTimestamp();
    const consentWithTimestamps: Record<string, unknown> = {};
    for (const [key, value] of entries) {
      if (typeof key !== "string" || key.length > 100) continue; // 비정상 키 skip
      consentWithTimestamps[key] = {
        agreed: !!value.agreed,
        version: String(value.version ?? "").slice(0, 50),
        agreedAt: serverTime,  // 서버 타임스탬프 강제
      };
    }

    await db.collection("users").doc(callerUid).update({
      termsConsent: consentWithTimestamps,
      termsConsentAt: serverTime,  // 법적 타임스탬프 — Admin SDK에서만 설정
    });

    return {success: true};
  }
);

// ── callableMarkIdCardVerified ───────────────────────────
// [HIGH-01] isIdVerified/idCardVerifiedAt를 CF Admin SDK로만 설정 — 클라이언트 직접 쓰기 차단
// 신분증 이미지 Storage 업로드 완료 후 호출 — 본인 경로 URL 검증 후 Firestore 업데이트
// Input:  { imageUrl: string }  — Storage 다운로드 URL (본인 경로만 허용)
// Output: { success: true }
export const callableMarkIdCardVerified = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;
    const {imageUrl} = request.data as {imageUrl?: string};

    if (!imageUrl || typeof imageUrl !== "string" || imageUrl.length > 2048) {
      throw new HttpsError("invalid-argument", "imageUrl이 필요합니다.");
    }
    // [M-01-FIX] includes()는 쿼리 파라미터/프래그먼트에도 매칭 → 경로 우회 가능
    //   → /o/{encoded_path} 부분만 추출 후 startsWith로 정확히 검증
    const pathMatch = imageUrl.match(/\/o\/([^?#]+)/);
    if (!pathMatch) {
      throw new HttpsError("invalid-argument", "유효하지 않은 Storage URL 형식입니다.");
    }
    const storagePath = decodeURIComponent(pathMatch[1]);
    if (!storagePath.startsWith(`users/${callerUid}/`)) {
      throw new HttpsError("permission-denied", "본인 신분증 이미지만 등록 가능합니다.");
    }

    await db.collection("users").doc(callerUid).update({
      idCardImageUrl: imageUrl,
      isIdVerified: true,
      idCardVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {success: true};
  }
);

// ── callableDeleteIdCard ─────────────────────────────────
// 신분증 삭제 — Firestore 먼저 업데이트(Admin SDK), 이후 Storage best-effort 삭제
// Input:  {}
// Output: { success: true }
export const callableDeleteIdCard = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;

    // 삭제 전 기존 URL 수집
    const userSnap = await db.collection("users").doc(callerUid).get();
    const oldImageUrl = userSnap.data()?.idCardImageUrl as string | undefined;

    // 1. Firestore 먼저 업데이트 (실패 시 Storage 건드리지 않음 — 설계 원칙 준수)
    await db.collection("users").doc(callerUid).update({
      idCardImageUrl: admin.firestore.FieldValue.delete(),
      isIdVerified: false,
      idCardVerifiedAt: admin.firestore.FieldValue.delete(),
    });

    // 2. Storage 삭제 best-effort (Firestore 성공 후)
    if (oldImageUrl) {
      try {
        const pathMatch = oldImageUrl.match(/\/o\/(.+?)(\?|$)/);
        if (pathMatch) {
          const filePath = decodeURIComponent(pathMatch[1]);
          await admin.storage().bucket().file(filePath).delete();
        }
      } catch (e) {
        console.warn(`[callableDeleteIdCard] Storage 삭제 실패 (무시): ${e}`);
      }
    }

    return {success: true};
  }
);

// ── callableDeleteBusinessImage ──────────────────────────
// [LOW-STORAGE] businesses/ 경로 삭제 소속 검증 — 로그인 사용자 누구나 삭제 가능한 취약점 차단
// Storage rules에서 Firestore 읽기 불가(프로젝트 특이사항)이므로 CF Admin SDK로 소속 검증 후 삭제
// Input:  { imageUrl: string }  — Firebase Storage download URL
// Output: { success: true }
export const callableDeleteBusinessImage = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;
    const {imageUrl} = request.data as {imageUrl?: string};

    if (!imageUrl || typeof imageUrl !== "string" || imageUrl.length > 2048) {
      throw new HttpsError("invalid-argument", "imageUrl이 필요합니다.");
    }

    // Storage 다운로드 URL에서 경로 추출
    const pathMatch = imageUrl.match(/\/o\/(.+?)(\?|$)/);
    if (!pathMatch) {
      // 다운로드 URL이 아닌 경우 이미 없거나 잘못된 URL — 무시
      return {success: true};
    }
    const filePath = decodeURIComponent(pathMatch[1]);

    // businesses/ 경로만 허용
    if (!filePath.startsWith("businesses/")) {
      throw new HttpsError("permission-denied", "businesses 이미지 경로만 삭제 가능합니다.");
    }

    // businessId 추출: businesses/{businessId}/...
    const parts = filePath.split("/");
    if (parts.length < 3) {
      throw new HttpsError("invalid-argument", "유효하지 않은 Storage 경로입니다.");
    }
    const businessId = parts[1];

    // 소속 검증 — 슈퍼어드민 또는 해당 사업장 관리자만 삭제 허용
    const callerSnap = await db.collection("users").doc(callerUid).get();
    const callerData = callerSnap.data();
    const role = callerData?.role as string | undefined;
    if (role !== "SUPER_ADMIN") {
      const managedIds = (callerData?.managedBusinessIds as string[] | undefined) ?? [];
      if (!managedIds.includes(businessId)) {
        throw new HttpsError("permission-denied", "소속 사업장의 이미지만 삭제 가능합니다.");
      }
    }

    // Admin SDK로 삭제 — 404는 이미 없으므로 성공 처리
    try {
      await admin.storage().bucket().file(filePath).delete();
    } catch (e: any) {
      if (e.code === 404 || e.message?.includes("No such object")) {
        return {success: true};
      }
      throw new HttpsError("internal", `Storage 삭제 실패: ${e.message}`);
    }

    return {success: true};
  }
);

// ── callableCreateTO ─────────────────────────────────────
// [HIGH-02] TO 생성 개수 제한 서버 강제 — 클라이언트 Firestore.add() 직접 호출 우회 차단
// 1) 관리자·소속 사업장 교차검증  2) draft 아닌 경우 개수 제한 체크  3) TO 문서 생성(serverTimestamp 강제)
// 슬롯 생성은 클라이언트가 반환된 toId로 직접 처리 (flex TO의 복잡한 배치 커밋 유지)
// Input:  { toData: object }  — TOModel.toMap() 결과 (createdAt/statusUpdatedAt 제외)
// Output: { toId: string }
export const callableCreateTO = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;
    const {toData} = request.data as {toData: Record<string, unknown>};

    if (!toData || typeof toData !== "object" || Array.isArray(toData)) {
      throw new HttpsError("invalid-argument", "toData가 필요합니다.");
    }

    const businessId = String(toData.businessId ?? "");
    const creatorUID = String(toData.creatorUID ?? "");
    const publishMode = String(toData.publishMode ?? "immediate");

    if (!businessId) throw new HttpsError("invalid-argument", "businessId가 필요합니다.");
    // 호출자와 creatorUID 일치 검증 — 타인 명의 TO 생성 차단
    if (callerUid !== creatorUID) {
      throw new HttpsError("permission-denied", "creatorUID 불일치.");
    }

    // 관리자 검증
    const callerSnap = await db.collection("users").doc(callerUid).get();
    const callerData = callerSnap.data();
    const role = callerData?.role as string;
    if (role !== "BUSINESS_ADMIN" && role !== "SUPER_ADMIN") {
      throw new HttpsError("permission-denied", "관리자만 공고를 생성할 수 있습니다.");
    }

    // 소속 사업장 교차검증 (슈퍼어드민 예외)
    // [HIGH-04-FIX] managedBusinessIds는 클라이언트가 arrayUnion으로 임의 businessId 추가 가능
    //   → 타 사업장 TO 생성 권한 탈취 위험. businesses 문서의 adminIds/ownerId로 서버 검증 교체.
    if (role !== "SUPER_ADMIN") {
      const bizAuthSnap = await db.collection("businesses").doc(businessId).get();
      if (!bizAuthSnap.exists) {
        throw new HttpsError("not-found", "사업장을 찾을 수 없습니다.");
      }
      const bizAdminIds = (bizAuthSnap.data()?.adminIds as string[] | undefined) ?? [];
      const bizOwnerId = bizAuthSnap.data()?.ownerId as string | undefined;
      if (!bizAdminIds.includes(callerUid) && bizOwnerId !== callerUid) {
        throw new HttpsError("permission-denied", "소속 사업장만 공고를 생성할 수 있습니다.");
      }
    }

    // 개수 제한 체크 (draft 제외)
    // [HIGH-05-MITIGATE] TOCTOU 완전 방어는 카운터 문서 필요 — 현재는 businessId 직접 쿼리로
    //   managedBusinessIds 의존성 제거 + 단일 사업장 기준으로 단순화
    if (publishMode !== "draft") {
      const quotaSnap = await db.collection("tos")
        .where("businessId", "==", businessId)
        .where("isPublished", "==", true)
        .get();
      const totalActive = quotaSnap.size;

      // 한도: users.maxActiveTOs 우선, settings/app_config.maxActiveTOPerBusiness 폴백, 기본 4
      let limit = 4;
      const perAdminLimit = callerData?.maxActiveTOs as number | undefined;
      if (perAdminLimit && perAdminLimit > 0) {
        limit = perAdminLimit;
      } else {
        try {
          const configSnap = await db.collection("settings").doc("app_config").get();
          const v = configSnap.data()?.maxActiveTOPerBusiness as number | undefined;
          if (v && v > 0) limit = v;
        } catch (_) { /* 조회 실패 시 기본값 유지 */ }
      }

      if (totalActive >= limit) {
        throw new HttpsError("resource-exhausted", `MAX_ACTIVE_TO_LIMIT:${limit}`);
      }
    }

    // TO 문서 생성 — serverTimestamp 강제, 클라이언트 전달 timestamp 필드 사용
    const serverTime = admin.firestore.FieldValue.serverTimestamp();
    const finalData: Record<string, unknown> = {
      ...toData,
      createdAt: serverTime,         // 클라이언트 전달값 오버라이드
      statusUpdatedAt: serverTime,   // 클라이언트 전달값 오버라이드
    };
    // creatorUID 재확인 (callerUid 기준으로 고정)
    finalData.creatorUID = callerUid;
    // [S5-FIX] 서버 전용 집계 카운터 — 클라이언트 주입 값 무시하고 0으로 강제
    finalData.totalConfirmed = 0;
    finalData.totalPending = 0;
    // [HIGH-03-FIX] draft 모드에서 isPublished:true 전송 시 쿼터 우회 가능 → 반드시 false 강제
    if (publishMode === "draft") {
      finalData.isPublished = false;
    }

    const toRef = await db.collection("tos").add(finalData);
    return {toId: toRef.id};
  }
);

// ── callablePublishTO ─────────────────────────────────────
// draft/scheduled TO를 즉시공개로 전환 — maxActiveTOs 서버 강제
// 이전 이유:
//   - 클라이언트 assertActiveTOLimit() 우회 시 TO 개수 제한 무력화
//   - updateTO() 직접 호출로 isPublished:true 주입 가능 (REST API)
// Input:  { toId: string }
// Output: { success: true, alreadyPublished?: true }
export const callablePublishTO = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;
    const {toId} = request.data as {toId?: string};
    if (!toId || typeof toId !== "string" || toId.trim() === "") {
      throw new HttpsError("invalid-argument", "toId가 필요합니다.");
    }

    const toRef = db.collection("tos").doc(toId);
    const toSnap = await toRef.get();
    if (!toSnap.exists) throw new HttpsError("not-found", "공고를 찾을 수 없습니다.");
    const toData = toSnap.data()!;
    const businessId = toData.businessId as string | undefined;
    if (!businessId) throw new HttpsError("invalid-argument", "공고에 businessId가 없습니다.");

    // 권한 검증 (사업장 관리자 또는 SUPER_ADMIN)
    await assertBizAdmin(callerUid, businessId);

    // 이미 공개된 경우 멱등 응답
    if (toData.isPublished === true) {
      return {success: true, alreadyPublished: true};
    }

    // [HIGH-TO-PUB] maxActiveTOs 서버 강제 — callableCreateTO와 동일 로직
    const [callerSnap, quotaSnap] = await Promise.all([
      db.collection("users").doc(callerUid).get(),
      db.collection("tos")
        .where("businessId", "==", businessId)
        .where("isPublished", "==", true)
        .get(),
    ]);
    const callerData = callerSnap.data() ?? {};
    const totalActive = quotaSnap.size;

    let limit = 4;
    const perAdminLimit = callerData.maxActiveTOs as number | undefined;
    if (perAdminLimit && perAdminLimit > 0) {
      limit = perAdminLimit;
    } else {
      try {
        const configSnap = await db.collection("settings").doc("app_config").get();
        const v = configSnap.data()?.maxActiveTOPerBusiness as number | undefined;
        if (v && v > 0) limit = v;
      } catch (_) { /* 조회 실패 시 기본값 유지 */ }
    }

    if (totalActive >= limit) {
      throw new HttpsError("resource-exhausted", `MAX_ACTIVE_TO_LIMIT:${limit}`);
    }

    await toRef.update({
      isPublished: true,
      publishMode: "immediate",
      status: "ACTIVE",
      statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log(`✅ [publishTO] TO ${toId} 공개 전환 완료 (businessId: ${businessId})`);
    return {success: true};
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
  {region: "asia-northeast3", enforceAppCheck: true},
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
  {region: "asia-northeast3", enforceAppCheck: true},
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
  {region: "asia-northeast3", enforceAppCheck: true},
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
    if (typeof reason !== "string" || reason.length > 200) {
      throw new HttpsError("invalid-argument", "거절 사유는 200자 이하여야 합니다.");
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
            // [M-02] 거절 사유를 알림 본문에서 제거 — 잠금 화면 등에서 개인정보 노출 방지
            body: "계정 승인이 거절되었습니다. 앱에서 확인하세요.",
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

// ── callableResetAccountStatus ───────────────────────────────────────────────
// 슈퍼관리자 전용 — active/rejected 외국인 계정을 pending(재검토 대기)으로 되돌림 (ISSUE-05)
// Input:  { userId: string }
// Output: { success: true }
export const callableResetAccountStatus = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    const callerUid = request.auth?.uid;
    if (!callerUid) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");

    const callerDoc = await db.collection("users").doc(callerUid).get();
    if (callerDoc.data()?.role !== "SUPER_ADMIN") {
      throw new HttpsError("permission-denied", "슈퍼관리자만 사용할 수 있습니다.");
    }

    const {userId} = request.data as {userId?: string};
    if (!userId) throw new HttpsError("invalid-argument", "userId 필수입니다.");

    const userRef = db.collection("users").doc(userId);
    const userDoc = await userRef.get();
    if (!userDoc.exists) throw new HttpsError("not-found", "사용자를 찾을 수 없습니다.");

    const currentStatus = userDoc.data()?.accountStatus as string | undefined;
    if (currentStatus !== "active" && currentStatus !== "rejected") {
      throw new HttpsError(
        "failed-precondition",
        "active 또는 rejected 상태에서만 재검토 전환이 가능합니다."
      );
    }

    await userRef.update({
      accountStatus: "pending",
      resetAt: Timestamp.now(),
      resetBy: callerUid,
    });

    return {success: true};
  }
);

// cleanExpiredPassTokens 제거 — Firestore TTL 정책으로 대체
// 설정: Firebase 콘솔 → Firestore → TTL → passTokens 컬렉션, expiresAt 필드

// ── adminResetForeignPassword ────────────────────────────────
// 슈퍼어드민 전용 — 외국인 근로자 비밀번호 임시 초기화 (ISSUE-03)
// Input:  { userId: string }
// Output: { tempPassword: string }
export const adminResetForeignPassword = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
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
    // [MEDIUM-3] USER 역할만 허용 — 데이터 이상으로 BUSINESS_ADMIN에 foreignIdNumber가 있어도 차단
    if (userData.role !== "USER") {
      throw new HttpsError("failed-precondition", "USER 역할 계정만 비밀번호 초기화가 가능합니다.");
    }
    // [특이사항] 내국인은 PASS CI 기반 비밀번호 찾기 사용 — 이 CF는 외국인 전용
    if (!userData.foreignIdNumber) {
      throw new HttpsError("failed-precondition", "내국인 사용자는 이 기능을 사용할 수 없습니다.");
    }
    // [LOW-01] active 상태가 아닌 계정 비밀번호 초기화 차단 — rejected 계정 재활성화 오용 방지
    if (userData.accountStatus !== "active") {
      throw new HttpsError("failed-precondition", "승인된 계정만 비밀번호를 초기화할 수 있습니다.");
    }

    // 혼동 없는 문자만 사용 (O/0, I/l/1 제외), crypto.randomInt으로 암호학적 안전성 보장
    const chars = "ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789";
    let tempPassword = "";
    for (let i = 0; i < 8; i++) {
      tempPassword += chars[crypto.randomInt(0, chars.length)];
    }

    await admin.auth().updateUser(userId, {password: tempPassword});

    // [SEC-07] 사용자 이름 평문 로그 제거 (PII 마스킹)
    console.log(`[adminResetForeignPassword] 슈퍼어드민 ${callerUid}가 ${userId}의 비밀번호 초기화`);
    // [HIGH-02] tempPassword 반환 — 클라이언트가 관리자에게 임시 비밀번호를 표시해야 함
    return {success: true, tempPassword};
  }
);

// ─── Firestore 직렬화 헬퍼 ───────────────────────────────────────────────────
// CF onCall 응답 시 Firestore Timestamp는 자동으로 {_seconds, _nanoseconds} Map으로
// JSON 직렬화됨. 중첩 Map/Array 내부도 재귀 처리한다.
function serializeFirestoreData(
  data: Record<string, unknown>
): Record<string, unknown> {
  const result: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(data)) {
    if (value instanceof Timestamp) {
      result[key] = {_seconds: value.seconds, _nanoseconds: value.nanoseconds};
    } else if (Array.isArray(value)) {
      result[key] = value.map((item) =>
        item instanceof Timestamp
          ? {_seconds: item.seconds, _nanoseconds: item.nanoseconds}
          : typeof item === "object" && item !== null
          ? serializeFirestoreData(item as Record<string, unknown>)
          : item
      );
    } else if (typeof value === "object" && value !== null) {
      result[key] = serializeFirestoreData(value as Record<string, unknown>);
    } else {
      result[key] = value;
    }
  }
  return result;
}

// ─── getMyMonthlyAttendances ─────────────────────────────────────────────────
// USER 본인의 월별 출근 기록 조회 — Firestore list 규칙에서 isUser() 제거 후 이 CF 사용
export const getMyMonthlyAttendances = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const uid = request.auth.uid;
    const {year, month} = request.data as {year: number; month: number};
    if (!year || !month) {
      throw new HttpsError("invalid-argument", "year, month 파라미터가 필요합니다.");
    }
    // SEC-50: year/month 범위 검증 — 비정상 값으로 과도한 범위 쿼리 차단
    if (!Number.isInteger(year) || year < 2020 || year > 2100) {
      throw new HttpsError("invalid-argument", "year는 2020~2100 사이여야 합니다.");
    }
    if (!Number.isInteger(month) || month < 1 || month > 12) {
      throw new HttpsError("invalid-argument", "month는 1~12 사이여야 합니다.");
    }

    // [BUG-ATT-06 수정] workDate는 Flutter DateTime(y,m,d) KST → UTC 전날 15:00으로 저장됨.
    // new Date(year, month-1, 1)은 Node.js UTC 자정 → KST 1일 00:00과 9시간 차이.
    // KST 1일 기록이 UTC 기준으로 이전 달 말일 15:00이므로 쿼리에서 누락됨.
    const KST_OFFSET_MS = 9 * 60 * 60 * 1000;
    const monthStart = new Date(Date.UTC(year, month - 1, 1) - KST_OFFSET_MS);
    const monthEnd = new Date(Date.UTC(year, month, 1) - KST_OFFSET_MS);

    const snap = await db
      .collection("attendance")
      .where("userId", "==", uid)
      .where("workDate", ">=", Timestamp.fromDate(monthStart))
      .where("workDate", "<", Timestamp.fromDate(monthEnd))
      .orderBy("workDate", "asc")
      .get();

    return {
      items: snap.docs.map((d) => ({id: d.id, ...serializeFirestoreData(d.data())})),
    };
  }
);

// ─── callableGetAdminAttendances ──────────────────────────────────────────────
// 관리자용 출근 기록 목록 조회 — Admin SDK 서버사이드 권한 검증
// 모드 A (날짜 범위): startMs + endMs 필수, yearMonth 불가
// 모드 B (월 조회):  yearMonth("YYYY-MM") 필수, startMs/endMs 불가
// 공통 선택 파라미터: userId (특정 근무자 필터)
// [이전 완료 callers] getTodayAttendanceByBusiness · getAttendanceByDate ·
//   getWeeklyAttendanceByBusiness · payroll_overview_screen · payroll_worker_detail ·
//   admin_stats_service · attendance_status_dialog · tax_deduction_service ·
//   admin_review_list_screen · notification_screen(관리자 경로)
export const callableGetAdminAttendances = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;

    const {
      businessId,
      startMs,
      endMs,
      userId: filterUserId,
      yearMonth: filterYearMonth,
      yearMonthGte: filterYearMonthGte,
      yearMonthLte: filterYearMonthLte,
      wageStatus: filterWageStatus,
      paymentDueDateLteMs,
    } = (request.data ?? {}) as {
      businessId?: string;
      startMs?: number;
      endMs?: number;
      userId?: string;
      yearMonth?: string;
      yearMonthGte?: string;
      yearMonthLte?: string;
      wageStatus?: string;
      paymentDueDateLteMs?: number;
    };

    if (!businessId || typeof businessId !== "string" || businessId.trim().length === 0) {
      throw new HttpsError("invalid-argument", "businessId가 필요합니다.");
    }

    const hasDateRange = Number.isFinite(startMs) && Number.isFinite(endMs);
    const hasYearMonth = typeof filterYearMonth === "string" && /^\d{4}-\d{2}$/.test(filterYearMonth);
    const hasYearMonthRange =
      typeof filterYearMonthGte === "string" && /^\d{4}-\d{2}$/.test(filterYearMonthGte) &&
      typeof filterYearMonthLte === "string" && /^\d{4}-\d{2}$/.test(filterYearMonthLte);
    const hasPaymentDueFilter = Number.isFinite(paymentDueDateLteMs);

    const dateModesCount = [hasDateRange, hasYearMonth, hasYearMonthRange].filter(Boolean).length;
    if (dateModesCount > 1) {
      throw new HttpsError("invalid-argument", "날짜 필터 모드는 하나만 사용할 수 있습니다.");
    }
    if (!hasDateRange && !hasYearMonth && !hasYearMonthRange && !hasPaymentDueFilter) {
      throw new HttpsError("invalid-argument", "startMs/endMs, yearMonth, yearMonthGte+Lte, paymentDueDateLteMs 중 하나가 필요합니다.");
    }
    if (hasDateRange) {
      if (startMs! >= endMs!) {
        throw new HttpsError("invalid-argument", "startMs < endMs이어야 합니다.");
      }
      const TWO_YEARS_MS = 2 * 365 * 24 * 60 * 60 * 1000;
      if (endMs! - startMs! > TWO_YEARS_MS) {
        throw new HttpsError("invalid-argument", "날짜 범위는 최대 2년까지 허용됩니다.");
      }
    }

    // 권한 검증: 슈퍼어드민 OR 해당 사업장 관리자/하위관리자
    const [callerSnap, bizSnap] = await Promise.all([
      db.collection("users").doc(callerUid).get(),
      db.collection("businesses").doc(businessId).get(),
    ]);

    const callerRole = callerSnap.data()?.role as string | undefined;
    const isSuperAdmin = callerRole === "SUPER_ADMIN";

    if (!isSuperAdmin) {
      if (!bizSnap.exists) {
        throw new HttpsError("not-found", "사업장을 찾을 수 없습니다.");
      }
      const adminIds = (bizSnap.data()?.adminIds as string[] | undefined) ?? [];
      const ownerId = bizSnap.data()?.ownerId as string | undefined;
      const callerSubAdminOf = callerSnap.data()?.subAdminOf as string | undefined;
      const isAuthorized =
        adminIds.includes(callerUid) ||
        ownerId === callerUid ||
        callerSubAdminOf === businessId;
      if (!isAuthorized) {
        throw new HttpsError("permission-denied", "해당 사업장에 대한 권한이 없습니다.");
      }
    }

    // 쿼리 실행 (Admin SDK — Firestore 보안 규칙 미적용)
    let q: admin.firestore.Query = db
      .collection("attendance")
      .where("businessId", "==", businessId);

    if (hasYearMonth) {
      q = q.where("yearMonth", "==", filterYearMonth);
    } else if (hasYearMonthRange) {
      q = q.where("yearMonth", ">=", filterYearMonthGte!).where("yearMonth", "<=", filterYearMonthLte!);
    } else if (hasDateRange) {
      q = q
        .where("workDate", ">=", Timestamp.fromMillis(startMs!))
        .where("workDate", "<", Timestamp.fromMillis(endMs!));
    }

    if (filterWageStatus && typeof filterWageStatus === "string" && filterWageStatus.trim().length > 0) {
      q = q.where("wageStatus", "==", filterWageStatus);
    }
    if (hasPaymentDueFilter) {
      q = q.where("paymentDueDate", "<=", Timestamp.fromMillis(paymentDueDateLteMs!));
    }
    if (filterUserId && typeof filterUserId === "string" && filterUserId.trim().length > 0) {
      q = q.where("userId", "==", filterUserId);
    }

    if (hasPaymentDueFilter) {
      q = q.orderBy("paymentDueDate", "asc").orderBy("workDate", "asc");
    } else if (!hasYearMonth && !hasYearMonthRange) {
      q = q.orderBy("workDate", "asc");
    }
    q = q.limit(10001);
    const snap = await q.get();

    const limitReached = snap.size > 10000;
    const docs = limitReached ? snap.docs.slice(0, 10000) : snap.docs;

    return {
      items: docs.map((d) => ({id: d.id, ...serializeFirestoreData(d.data())})),
      limitReached,
    };
  }
);

// ─── getMyContracts ──────────────────────────────────────────────────────────
// USER 본인의 계약서 목록 조회 (커서 페이지네이션)
// lastDocId: 이전 페이지 마지막 문서 ID, pageSize: 페이지 크기 (기본 20)
export const getMyContracts = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const uid = request.auth.uid;
    const {statusFilter, lastDocId, pageSize: rawPageSize = 20} = (request.data ?? {}) as {
      statusFilter?: string;
      lastDocId?: string;
      pageSize?: number;
    };
    const pageSize = Math.min(Math.max(1, rawPageSize ?? 20), 100); // SEC-21: 1~100 제한

    const VALID_CONTRACT_STATUSES = new Set([
      "pending_employer", "pending_worker", "active",
      "completed", "voided", "expired",
    ]);
    if (statusFilter && !VALID_CONTRACT_STATUSES.has(statusFilter)) {
      throw new HttpsError("invalid-argument", "유효하지 않은 statusFilter입니다.");
    }

    let q: FirebaseFirestore.Query = db
      .collection("employment_contracts")
      .where("workerId", "==", uid);
    if (statusFilter) {
      q = q.where("status", "==", statusFilter);
    }
    q = q.orderBy("createdAt", "desc").limit(pageSize + 1);

    if (lastDocId) {
      const lastSnap = await db.collection("employment_contracts").doc(lastDocId).get();
      if (!lastSnap.exists) {
        throw new HttpsError("invalid-argument", "유효하지 않은 커서입니다.");
      }
      // 타 사용자의 문서를 커서로 사용해 열람 범위를 우회하는 것 차단
      if (lastSnap.data()?.workerId !== uid) {
        throw new HttpsError("permission-denied", "접근 권한이 없는 커서입니다.");
      }
      q = q.startAfter(lastSnap);
    }

    const snap = await q.get();
    const hasMore = snap.docs.length > pageSize;
    const docs = hasMore ? snap.docs.slice(0, pageSize) : snap.docs;

    return {
      items: docs.map((d) => ({id: d.id, ...serializeFirestoreData(d.data())})),
      lastDocId: docs.length > 0 ? docs[docs.length - 1].id : null,
      hasMore,
    };
  }
);

// ═══════════════════════════════════════════════════════════
// 🏢 사업장 비활성화 시 TO·지원서 자동 정리
//
// 트리거: businesses/{businessId} 문서에 deactivatedAt 필드가 새로 추가될 때
// 처리 대상:
//   - 활성 TO (ACTIVE / FULL / SCHEDULED) → CLOSED (closedReason: BUSINESS_DEACTIVATED)
//   - 각 TO의 PENDING 지원서 → REJECTED (cancelReason: BUSINESS_DEACTIVATED)
//   - CONFIRMED / CONTRACT_PENDING 지원서는 급여 데이터 포함 가능 →
//     근로기준법 제42조 3년 보존 의무로 현재 미처리 (TODO: 별도 관리자 정리 워크플로 필요)
//
// 실시간 처리 특성:
//   - Firestore onDocumentUpdated 트리거는 문서 변경 후 통상 1~5초 이내 실행
//   - CF 실행 전 짧은 창(수 초) 동안 CLOSED 전 TO에 새 지원이 접수될 수 있음
//     → 대응: 탈퇴 직후 deactivatedAt 기반으로 UI에서 비활성 사업장 TO 숨김 처리 권장
//   - retry: true → 실패 시 최대 7회 지수 백오프 재시도 (멱등성 보장 필수)
//   - 멱등성 보장: where('status', '==', 'ACTIVE') 조건으로 이미 처리된 TO는 재조회 안 됨
//
// 처리 제한:
//   - Firestore batch: 500건 제한 → BATCH_LIMIT=400으로 여유 확보
//   - 타임아웃: timeoutSeconds=300 (기본 60초 → 5분으로 상향)
//   - whereIn 사용 불가(보안 규칙 충돌) → ACTIVE/FULL/SCHEDULED 각각 별도 쿼리
// ═══════════════════════════════════════════════════════════
export const onBusinessDeactivated = onDocumentUpdated(
  {
    document: "businesses/{businessId}",
    region: "asia-northeast3",
    timeoutSeconds: 300,
    retry: true,
  },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    const businessId = event.params.businessId;

    // deactivatedAt이 이번 업데이트에서 새로 추가됐을 때만 처리 (멱등성 보장)
    if (!before || !after) return;
    if (before.deactivatedAt !== undefined || after.deactivatedAt === undefined) return;

    console.log(`🏢 [사업장 비활성화] 처리 시작: ${businessId}`);

    // 1) 활성 TO 조회 — whereIn 미사용(보안 규칙 충돌), 상태별 3개 병렬 쿼리
    const [activeSnap, fullSnap, scheduledSnap] = await Promise.all([
      db.collection("tos").where("businessId", "==", businessId).where("status", "==", "ACTIVE").limit(500).get(),
      db.collection("tos").where("businessId", "==", businessId).where("status", "==", "FULL").limit(500).get(),
      db.collection("tos").where("businessId", "==", businessId).where("status", "==", "SCHEDULED").limit(500).get(),
    ]);

    const activeTos = [...activeSnap.docs, ...fullSnap.docs, ...scheduledSnap.docs];
    console.log(`📋 [사업장 비활성화] 활성 TO ${activeTos.length}건 발견: ${businessId}`);

    if (activeTos.length === 0) {
      console.log(`ℹ️ [사업장 비활성화] 활성 TO 없음 — employment_contracts만 처리: ${businessId}`);
    }

    if (activeTos.length > 0) {
    // 2) TO별 처리: TO → CLOSED, 소속 PENDING 지원서 → REJECTED
    const BATCH_LIMIT = 400; // Firestore batch 500건 제한 안전 마진
    let totalRejected = 0;

    for (const toDoc of activeTos) {
      const toId = toDoc.id;

      // PENDING + CONTRACT_PENDING + CONFIRMED 지원서 병렬 조회
      const [pendingAppsSnap, contractPendingSnap, confirmedSnap] = await Promise.all([
        db.collection("applications").where("toId", "==", toId).where("status", "==", "PENDING").limit(500).get(),
        db.collection("applications").where("toId", "==", toId).where("status", "==", "CONTRACT_PENDING").limit(500).get(),
        db.collection("applications").where("toId", "==", toId).where("status", "==", "CONFIRMED").limit(500).get(),
      ]);

      // batch에 TO 업데이트 + 전체 지원서 처리
      // [특이사항/CRITICAL-003] CONTRACT_PENDING·CONFIRMED도 포함 — 비활성화 사업장의 좀비 상태 계약 방지
      // 근로기준법 제42조 "3년 보존" 의무는 계약서 문서에 적용 (자동 삭제 금지), 지원서 상태는 별개
      const allUpdates: Array<{ref: FirebaseFirestore.DocumentReference; data: Record<string, unknown>}> = [
        {
          ref: toDoc.ref,
          data: {
            status: "CLOSED",
            closedReason: "BUSINESS_DEACTIVATED",
            closedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
        },
        ...pendingAppsSnap.docs.map((appDoc) => ({
          ref: appDoc.ref,
          data: {
            status: "REJECTED",
            cancelReason: "BUSINESS_DEACTIVATED",
            rejectedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
        })),
        ...contractPendingSnap.docs.map((appDoc) => ({
          ref: appDoc.ref,
          data: {
            status: "CANCELED",
            cancelReason: "BUSINESS_DEACTIVATED",
            canceledAt: admin.firestore.FieldValue.serverTimestamp(),
          },
        })),
        ...confirmedSnap.docs.map((appDoc) => ({
          ref: appDoc.ref,
          data: {
            status: "CANCELED",
            cancelReason: "BUSINESS_DEACTIVATED",
            canceledAt: admin.firestore.FieldValue.serverTimestamp(),
          },
        })),
      ];

      // 청크 단위 batch 커밋
      // [WARNING-007] race condition으로 TO 문서가 동시 삭제된 경우 배치 전체 실패 가능
      // → try-catch 격리 후 개별 update로 전환하여 나머지 지원서 처리 보장
      for (let i = 0; i < allUpdates.length; i += BATCH_LIMIT) {
        const chunk = allUpdates.slice(i, i + BATCH_LIMIT);
        const batch = db.batch();
        chunk.forEach(({ref, data}) => batch.update(ref, data));
        try {
          await batch.commit();
        } catch (err) {
          console.warn(`⚠️ [사업장 비활성화] 배치 커밋 실패 — 개별 처리 전환 (TO ${toId}):`, err);
          await Promise.allSettled(chunk.map(({ref, data}) => ref.update(data)));
        }
      }

      const canceledCount = contractPendingSnap.size + confirmedSnap.size;
      totalRejected += pendingAppsSnap.size + canceledCount;
      console.log(
        `✅ [사업장 비활성화] TO ${toId} → CLOSED, ` +
        `PENDING ${pendingAppsSnap.size}건 → REJECTED, ` +
        `CONTRACT_PENDING+CONFIRMED ${canceledCount}건 → CANCELED`
      );
    }

    console.log(`✅ [사업장 비활성화] 완료: ${businessId} — TO ${activeTos.length}건, 지원서 ${totalRejected}건 처리`);
    } // if (activeTos.length > 0)

    // [SEC-98] 3) employment_contracts 처리 — TO 유무와 무관하게 항상 실행
    // pending_employer / pending_worker 상태 계약서가 좀비로 잔류하는 것 방지.
    // Dart Step 11은 users 삭제 후 isBusinessAdmin() 실패로 TO LIST에서 막혀
    // employment_contracts 블록에 도달하지 못함 → CF 위임.
    // 근로기준법 제42조: 계약서 문서는 삭제 금지 — voided 상태로 표시.
    const contractSnap = await db
      .collection("employment_contracts")
      .where("businessId", "==", businessId)
      .where("status", "in", ["pending_employer", "pending_worker"])
      .get();

    if (contractSnap.size > 0) {
      const CONTRACT_BATCH_LIMIT = 400;
      for (let i = 0; i < contractSnap.docs.length; i += CONTRACT_BATCH_LIMIT) {
        const chunk = contractSnap.docs.slice(i, i + CONTRACT_BATCH_LIMIT);
        const batch = db.batch();
        chunk.forEach((docRef) => batch.update(docRef.ref, {
          status: "voided",
          voidReason: "BUSINESS_DEACTIVATED",
          contractVoidedAt: admin.firestore.FieldValue.serverTimestamp(),
        }));
        try {
          await batch.commit();
        } catch (err) {
          console.warn(`⚠️ [사업장 비활성화] employment_contracts 배치 실패 — 개별 처리:`, err);
          await Promise.allSettled(chunk.map((docRef) => docRef.ref.update({
            status: "voided",
            voidReason: "BUSINESS_DEACTIVATED",
            contractVoidedAt: admin.firestore.FieldValue.serverTimestamp(),
          })));
        }
      }
      console.log(`✅ [사업장 비활성화] employment_contracts ${contractSnap.size}건 → voided: ${businessId}`);
    }
  }
);

// ═══════════════════════════════════════════════════════════
// 📊 TO 통계 자동 동기화 트리거
// ═══════════════════════════════════════════════════════════

/**
 * applications 문서의 status가 변경될 때마다 TO 카운터를 실제 데이터 기준으로 재계산.
 * - 앱 코드의 +1/-1 증감이 실패해도 CF가 자동으로 정확한 값으로 수렴시킴
 * - statsBatch 분리 문제(S36) 원천 해결
 */
export const syncTOStats = onDocumentWritten(
  {document: "applications/{applicationId}", region: "asia-northeast3"},
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();

    const beforeStatus = before?.status as string | undefined;
    const afterStatus = after?.status as string | undefined;

    // 상태 변경이 없으면 카운터 변화 없음 → 불필요한 집계 skip
    if (beforeStatus === afterStatus) return;

    const toId = (after?.toId ?? before?.toId) as string | undefined;
    const slotId = (after?.slotId ?? before?.slotId) as string | undefined;

    if (!toId) return;

    await _syncTOCounters(toId, slotId);
  }
);

/**
 * TO 카운터 재계산 — 모든 읽기를 병렬로, 쓰기를 1번 배치로 처리
 *
 * [비용 특이사항]
 * - contract TO(slotId 없음): count() 2번 + 쓰기 1번
 * - flex TO(slotId 있음):    count() (4 + workType수 × 2)번 + 문서 읽기 1번 + 배치 쓰기 1번
 *   workType이 늘어날수록 Firestore 읽기 비용 증가. 현재 슬롯당 최대 5~6가지 업무 가정.
 *
 * [설계 결정] 낙관적 카운터 + CF 교정 이중 구조
 *   앱: FieldValue.increment(±1)으로 즉각 UI 반영 (낙관적 업데이트)
 *   CF: count()로 절대값 덮어쓰기 → 앱 증감 실패·경쟁 조건 모두 자동 교정
 *
 * [특이사항] workTypeConfirmedCounts (TO 문서, contract TO 전용):
 *   TO 문서의 workDetails 배열에서 workType 목록을 읽어 count() 재계산.
 *   flex TO의 workTypeCounts(슬롯 문서)와 달리 slotAppsRef가 없으므로 appsRef(toId 기준)로 집계.
 *   인덱스: applications[toId + selectedWorkType + status] 필요.
 */
async function _syncTOCounters(toId: string, slotId?: string): Promise<void> {
  const toRef = db.collection("tos").doc(toId);

  // TO 삭제된 경우 update()가 NOT_FOUND 예외 → 7번 재시도 루프 방지
  const toSnap = await toRef.get();
  if (!toSnap.exists) {
    console.warn(`[syncTOStats] TO 문서 없음 — skip: ${toId}`);
    return;
  }

  const appsRef = db.collection("applications").where("toId", "==", toId);

  if (!slotId) {
    // contract TO: TO 카운터 + 업무별 확정 카운터 재계산
    // workTypeConfirmedCounts.$workType은 applyToTO 정원 초과 체크에서 직접 읽으므로
    // 앱 increment 실패 시 영구 불일치 방지를 위해 CF가 count()로 교정.
    const toData = toSnap.data();
    const contractWorkDetails =
      (toData?.workDetails as Array<{workType?: string}> | undefined) ?? [];
    const contractWorkTypes = [
      ...new Set(
        contractWorkDetails.map((d) => d.workType).filter((w): w is string => !!w)
      ),
    ];

    const [confirmedSnap, pendingSnap, ...wtSnaps] = await Promise.all([
      appsRef.where("status", "in", CONFIRMED_STATUSES).count().get(),
      appsRef.where("status", "==", "PENDING").count().get(),
      ...contractWorkTypes.map((wt) =>
        appsRef
          .where("selectedWorkType", "==", wt)
          .where("status", "in", CONFIRMED_STATUSES)
          .count()
          .get()
      ),
    ]);

    const workTypeConfirmedUpdate: Record<string, number> = {};
    contractWorkTypes.forEach((wt, i) => {
      workTypeConfirmedUpdate[`workTypeConfirmedCounts.${wt}`] = wtSnaps[i].data().count;
    });

    await toRef.update({
      totalConfirmed: confirmedSnap.data().count,
      totalPending: pendingSnap.data().count,
      statsUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      ...workTypeConfirmedUpdate,
    });
    return;
  }

  // flex TO: TO + 슬롯 집계 전체 병렬 실행 후 배치 쓰기
  const slotRef = toRef.collection("slots").doc(slotId);
  const slotAppsRef = appsRef.where("slotId", "==", slotId);

  const [
    toConfirmedSnap,
    toPendingSnap,
    slotConfirmedSnap,
    slotPendingSnap,
    slotDoc,
  ] = await Promise.all([
    appsRef.where("status", "in", CONFIRMED_STATUSES).count().get(),
    appsRef.where("status", "==", "PENDING").count().get(),
    slotAppsRef.where("status", "in", CONFIRMED_STATUSES).count().get(),
    slotAppsRef.where("status", "==", "PENDING").count().get(),
    slotRef.get(),
  ]);

  const confirmedCount = slotConfirmedSnap.data().count;
  // 슬롯 문서는 workDetails[].requiredCount 합계로 총 필요 인원 계산
  const workDetails =
    (slotDoc.data()?.workDetails as
      Array<{workType?: string; requiredCount?: number}> | undefined) ?? [];
  const required = workDetails.reduce((acc, d) => acc + (d.requiredCount ?? 0), 0);
  const newStatus = required > 0 && confirmedCount >= required ? "full" : "open";
  // [BUG-E-01 수정] 수동 마감 슬롯 여부 사전 확인 — status를 덮어쓰지 않기 위해
  const isManualClosed = slotDoc.data()?.isManualClosed === true;
  const currentSlotStatus = slotDoc.data()?.status as string | undefined;

  // 업무별(workType) 카운터 재계산 — applyToTO 정원 초과 체크(workTypeCounts.$wt.confirmedCount)가
  // 이 값을 직접 읽으므로 CF가 재계산하지 않으면 앱 increment 실패 시 정원 초과 체크 오동작 발생.
  // [비용] workType 1개당 count() 2회 추가 발생 (슬롯당 최대 ~10회 추가 예상).
  const workTypes = [
    ...new Set(
      workDetails.map((d) => d.workType).filter((w): w is string => !!w)
    ),
  ];
  const wtCountResults = await Promise.all(
    workTypes.map((wt) =>
      Promise.all([
        slotAppsRef
          .where("selectedWorkType", "==", wt)
          .where("status", "in", CONFIRMED_STATUSES)
          .count()
          .get(),
        slotAppsRef
          .where("selectedWorkType", "==", wt)
          .where("status", "==", "PENDING")
          .count()
          .get(),
      ])
    )
  );
  const workTypeCountsUpdate: Record<string, number> = {};
  workTypes.forEach((wt, i) => {
    workTypeCountsUpdate[`workTypeCounts.${wt}.confirmedCount`] =
      wtCountResults[i][0].data().count;
    workTypeCountsUpdate[`workTypeCounts.${wt}.pendingCount`] =
      wtCountResults[i][1].data().count;
  });

  const writeBatch = db.batch();
  writeBatch.update(toRef, {
    totalConfirmed: toConfirmedSnap.data().count,
    totalPending: toPendingSnap.data().count,
    statsUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  if (slotDoc.exists) {
    writeBatch.update(slotRef, {
      confirmedCount,
      pendingCount: slotPendingSnap.data().count,
      // [BUG-E-01 수정] 수동 마감(isManualClosed) 또는 closed 슬롯은 status 덮어쓰기 금지
      // Flutter _recalculateSlotStatus(dart 2175줄)와 동일한 가드 — CF에만 누락되어 있었음
      ...(isManualClosed || currentSlotStatus === "closed" ? {} : {status: newStatus}),
      ...workTypeCountsUpdate,
    });
  }
  await writeBatch.commit();
}

// ═══════════════════════════════════════════════════════════
// 🔗 그룹 마스터 TO 자동 동기화 트리거
// ═══════════════════════════════════════════════════════════

/**
 * [SM-01 수정] 멤버 TO의 status가 바뀔 때 그룹 마스터 TO 상태 자동 동기화.
 *
 * 문제: Flutter batchReopenSlots → _syncTOCascadeStatus가 TO status를 업데이트해도
 *       CF의 syncGroupMasterStatus는 자정 작업에서만 직접 호출되므로
 *       슬롯 재오픈 후 그룹 마스터가 ACTIVE로 복구되지 않는 상태 불일치 발생.
 *
 * 해결: Firestore 트리거로 TO 상태 변경 → 그룹 마스터 자동 동기화.
 *       isGroupMaster === true인 마스터 TO 업데이트는 skip(무한 루프 방지).
 */
export const onTOStatusChanged = onDocumentUpdated(
  {document: "tos/{toId}", region: "asia-northeast3"},
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;

    // 상태 변경이 없으면 skip — 불필요한 그룹 동기화 방지
    if (before.status === after.status) return;

    // 마스터 TO 자체가 변경된 경우 skip — 무한 루프 방지
    if (after.isGroupMaster === true) return;

    const groupId = after.groupId as string | undefined;
    if (!groupId) return;

    await syncGroupMasterStatus(db, groupId);
  }
);

// ═══════════════════════════════════════════════════════════
// 🗑️ TO 삭제 cascade (H-10 서버 사이드 안전망)
// ═══════════════════════════════════════════════════════════
/**
 * 클라이언트의 deleteTO()가 네트워크 단절 등으로 미완료됐을 때 고아 데이터 방지.
 * 처리 순서: slots → applications → attendance → schedule_change_requests → notifications
 * - wageTransferred / wageConfirmed 상태 attendance는 임금 정산 완료이므로 보존.
 * - 이미 삭제된 문서에 대한 batch.delete()는 Firestore가 no-op 처리 → 멱등 보장.
 */
export const onTODeleted = onDocumentDeleted(
  {
    document: "tos/{toId}",
    region: "asia-northeast3",
    retry: true,
  },
  async (event) => {
    const toId = event.params.toId;
    const snap = event.data;
    if (!snap) return;
    const toData = snap.data();
    const businessId = toData?.businessId as string | undefined;

    console.log(`[onTODeleted] cascade 시작: toId=${toId}, businessId=${businessId}`);

    const PAGE = 499;

    // ── 1. slots 서브컬렉션 삭제 ──
    {
      const slotsRef = db.collection(`tos/${toId}/slots`);
      let last: FirebaseFirestore.DocumentSnapshot | undefined;
      while (true) {
        let q: FirebaseFirestore.Query = slotsRef.limit(PAGE);
        if (last) q = q.startAfter(last);
        const snap2 = await q.get();
        if (snap2.empty) break;
        const batch = db.batch();
        snap2.docs.forEach((d) => batch.delete(d.ref));
        await batch.commit();
        if (snap2.docs.length < PAGE) break;
        last = snap2.docs[snap2.docs.length - 1];
      }
    }

    // ── 2. applications 수집 ──
    const appQuery = db.collection("applications").where("toId", "==", toId);
    const appSnap = await appQuery.get();
    const appIds: string[] = appSnap.docs.map((d) => d.id);

    // applications 삭제
    if (appSnap.docs.length > 0) {
      let batch = db.batch();
      let count = 0;
      for (const d of appSnap.docs) {
        batch.delete(d.ref);
        count++;
        if (count >= PAGE) {
          await batch.commit();
          batch = db.batch();
          count = 0;
        }
      }
      if (count > 0) await batch.commit();
    }

    // ── 3. attendance 삭제 (wageTransferred / wageConfirmed 보존) ──
    const WAGE_DONE = ["wageTransferred", "wageConfirmed"];
    for (let i = 0; i < appIds.length; i += 30) {
      const chunk = appIds.slice(i, i + 30);
      const attSnaps = await Promise.all(
        chunk.map((appId) =>
          db.collection("attendance")
            .where("applicationId", "==", appId)
            .get()
        )
      );
      const attDocs = attSnaps.flatMap((s) => s.docs);
      if (attDocs.length > 0) {
        let batch = db.batch();
        let count = 0;
        for (const d of attDocs) {
          const wageStatus = d.data().wageStatus as string | undefined;
          if (wageStatus && WAGE_DONE.includes(wageStatus)) continue;
          batch.delete(d.ref);
          count++;
          if (count >= PAGE) {
            await batch.commit();
            batch = db.batch();
            count = 0;
          }
        }
        if (count > 0) await batch.commit();
      }
    }

    // ── 4. schedule_change_requests 삭제 ──
    for (let i = 0; i < appIds.length; i += 30) {
      const chunk = appIds.slice(i, i + 30);
      const reqSnaps = await Promise.all(
        chunk.map((appId) =>
          db.collection("schedule_change_requests")
            .where("applicationId", "==", appId)
            .get()
        )
      );
      const reqDocs = reqSnaps.flatMap((s) => s.docs);
      if (reqDocs.length > 0) {
        let batch = db.batch();
        let count = 0;
        for (const d of reqDocs) {
          batch.delete(d.ref);
          count++;
          if (count >= PAGE) {
            await batch.commit();
            batch = db.batch();
            count = 0;
          }
        }
        if (count > 0) await batch.commit();
      }
    }

    // ── 5. notifications 삭제 (toId 기준) ──
    if (businessId) {
      let last: FirebaseFirestore.DocumentSnapshot | undefined;
      while (true) {
        let q: FirebaseFirestore.Query = db.collection("notifications")
          .where("toId", "==", toId)
          .where("businessId", "==", businessId)
          .limit(PAGE);
        if (last) q = q.startAfter(last);
        const notifSnap = await q.get();
        if (notifSnap.empty) break;
        const batch = db.batch();
        notifSnap.docs.forEach((d) => batch.delete(d.ref));
        await batch.commit();
        if (notifSnap.docs.length < PAGE) break;
        last = notifSnap.docs[notifSnap.docs.length - 1];
      }
    }

    console.log(`[onTODeleted] cascade 완료: toId=${toId}, apps=${appIds.length}`);
  }
);

// ═══════════════════════════════════════════════════════════
// 🪪 신분증 서명 URL 발급 (ID-1 보안: Firestore 평문 URL 직접 노출 차단)
// ═══════════════════════════════════════════════════════════
/**
 * 승인된 idCardAccessRequests를 확인 후 1시간 만료 Storage Signed URL 반환.
 * - SUPER_ADMIN: 항상 허용
 * - BUSINESS_ADMIN / SUB_ADMIN: 유효한(approved + expiresAt > now) 요청 필수
 * - idCardImageUrl에서 Storage 경로 파싱 (기존 데이터 호환)
 * - 응답: { signedUrl: string } (1시간 만료)
 */
export const callableGetIdCardSignedUrl = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    }

    const {targetUserId} = request.data as {targetUserId?: string};
    if (!targetUserId) {
      throw new HttpsError("invalid-argument", "targetUserId가 필요합니다.");
    }

    const callerDoc = await db.collection("users").doc(request.auth.uid).get();
    const callerRole = (callerDoc.data()?.role as string | undefined) ?? "";
    const isSuperAdmin = callerRole === "SUPER_ADMIN";

    if (!isSuperAdmin) {
      // 유효한 신분증 접근 승인 확인
      const now = Timestamp.now();
      const accessSnap = await db
        .collection("idCardAccessRequests")
        .where("requesterId", "==", request.auth.uid)
        .where("targetUserId", "==", targetUserId)
        .where("status", "==", "approved")
        .where("expiresAt", ">", now)
        .limit(1)
        .get();

      if (accessSnap.empty) {
        throw new HttpsError(
          "permission-denied",
          "신분증 열람 권한이 없거나 만료되었습니다."
        );
      }

      // [MEDIUM] 퇴직 관리자 stale access 방어 — 승인 당시 사업장에 여전히 소속인지 재검증
      const approvedForBiz = accessSnap.docs[0].data().businessId as string | undefined;
      if (approvedForBiz) {
        const callerBizId = callerDoc.data()?.businessId as string | undefined;
        // [M-02-FIX] subAdminOf는 단일 businessId 문자열 — string[]로 잘못 캐스팅 시
        //   Array.isArray(string) = false → SubAdmin 신분증 열람 전면 차단 버그 수정
        const callerSubAdminOf = callerDoc.data()?.subAdminOf as string | undefined;
        const stillMember =
          callerBizId === approvedForBiz ||
          callerSubAdminOf === approvedForBiz;
        if (!stillMember) {
          throw new HttpsError("permission-denied", "현재 해당 사업장 소속이 아닙니다.");
        }
      }
    }

    // 대상자 문서에서 Storage 경로 조회
    const targetDoc = await db.collection("users").doc(targetUserId).get();
    if (!targetDoc.exists) {
      throw new HttpsError("not-found", "사용자를 찾을 수 없습니다.");
    }
    const targetData = targetDoc.data()!;

    // idCardImagePath 우선, 없으면 idCardImageUrl에서 경로 파싱 (기존 데이터 호환)
    let storagePath = targetData.idCardImagePath as string | undefined;
    if (!storagePath) {
      const downloadUrl = targetData.idCardImageUrl as string | undefined;
      if (!downloadUrl) {
        throw new HttpsError("not-found", "신분증 이미지가 등록되지 않았습니다.");
      }
      try {
        const url = new URL(downloadUrl);
        const match = url.pathname.match(/\/o\/(.+)$/);
        if (!match) throw new Error("경로 파싱 실패");
        storagePath = decodeURIComponent(match[1]);
      } catch {
        throw new HttpsError("internal", "신분증 Storage 경로를 파싱할 수 없습니다.");
      }
    }

    // 1시간 만료 Signed URL 생성
    const bucket = admin.storage().bucket();
    const file = bucket.file(storagePath);
    const [exists] = await file.exists();
    if (!exists) {
      throw new HttpsError("not-found", "신분증 파일이 Storage에 존재하지 않습니다.");
    }

    const [signedUrl] = await file.getSignedUrl({
      action: "read",
      expires: Date.now() + 60 * 60 * 1000, // 1시간
    });

    console.log(
      `[callableGetIdCardSignedUrl] ${request.auth.uid} → ${targetUserId}` +
      ` (superAdmin=${isSuperAdmin})`
    );
    return {signedUrl};
  }
);

// ═══════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════
// 📍 근로자 위치 일괄 조회 (크로스-사업장 방지)
// ═══════════════════════════════════════════════════════════
/**
 * applicationId 목록으로 worker_locations를 Admin SDK로 일괄 조회.
 *
 * 배경: 클라이언트 whereIn + FieldPath.documentId() 복합쿼리 시 Firestore 보안 규칙의
 *   request.query.filters가 null을 반환하여 businessId 필터 강제 불가.
 *   CF Admin SDK 경유로 전환하여 서버 사이드에서 businessId 소속 검증 후 조회.
 *
 * Input:  { applicationIds: string[], businessId: string }
 * Output: { locations: Record<applicationId, WorkerLocationData> }
 */
export const callableGetLocationsForApplications = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인 필요");
    const uid = request.auth.uid;
    const {applicationIds, businessId} = request.data as {
      applicationIds?: unknown;
      businessId?: unknown;
    };

    if (!businessId || typeof businessId !== "string" || businessId.length === 0) {
      throw new HttpsError("invalid-argument", "businessId 필수");
    }
    if (!Array.isArray(applicationIds)) {
      throw new HttpsError("invalid-argument", "applicationIds는 배열이어야 합니다");
    }
    if (applicationIds.length === 0) return {locations: {}};
    if (applicationIds.length > 500) {
      throw new HttpsError("invalid-argument", "applicationIds 최대 500개");
    }

    // 역할 검증: 해당 businessId의 BUSINESS_ADMIN 또는 SUB_ADMIN인지 확인
    const bizSnap = await db.collection("businesses").doc(businessId).get();
    if (!bizSnap.exists) throw new HttpsError("not-found", "사업장을 찾을 수 없습니다.");
    const bizData = bizSnap.data() ?? {};
    const isAdmin =
      bizData["ownerId"] === uid ||
      (Array.isArray(bizData["adminIds"]) && (bizData["adminIds"] as string[]).includes(uid));

    if (!isAdmin) {
      const userSnap = await db.collection("users").doc(uid).get();
      const userData = userSnap.data() ?? {};
      const isSuperAdmin = userData["role"] === "SUPER_ADMIN";
      const isSub = userData["subAdminOf"] === businessId;
      if (!isSuperAdmin && !isSub) {
        throw new HttpsError("permission-denied", "해당 사업장의 관리자 권한이 없습니다.");
      }
    }

    // Admin SDK로 개별 get() — whereIn+FieldPath.documentId() 대신 병렬 조회
    const validIds = applicationIds.filter((id): id is string => typeof id === "string");
    const snaps = await Promise.all(
      validIds.map((id) => db.collection("worker_locations").doc(id).get())
    );

    const locations: Record<string, unknown> = {};
    for (const snap of snaps) {
      if (snap.exists) {
        const data = snap.data() ?? {};
        // businessId 불일치 문서 필터링 — 다른 사업장 데이터 유출 차단
        if (data["businessId"] === businessId) {
          locations[snap.id] = serializeFirestoreData(data);
        }
      }
    }

    return {locations};
  }
);

// 👥 사용자 배치 조회 (서버 사이드 소속 검증)
// ═══════════════════════════════════════════════════════════
/**
 * 관리자가 자신의 사업장 소속 근무자 정보를 일괄 조회하는 CF.
 *
 * 보안:
 *   - 호출자 역할(BUSINESS_ADMIN / SUB_ADMIN / SUPER_ADMIN) 서버 검증
 *   - 요청 UID 중 해당 businessId 소속 아닌 것 제외 (SUPER_ADMIN 예외)
 *   - ci, residentNumber, foreignIdNumber, idCardImageUrl,
 *     signatureBase64, sealBase64, bankbookImageUrl 필드 제거
 *   - accountNumber는 민감 필드로 제거하여 반환하지 않음
 *
 * 입력: { uids: string[], businessId: string }  (uids 최대 30개)
 * 출력: { users: Record<uid, SafeUserData> }
 */
export const callableGetUsersBatch = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    }

    const uids = request.data.uids as string[] | undefined;
    const businessId = request.data.businessId as string | undefined;

    if (!uids || !Array.isArray(uids) || uids.length === 0) return {users: {}};
    if (uids.length > 30) {
      throw new HttpsError("invalid-argument", "uid는 최대 30개까지 요청 가능합니다.");
    }
    if (!uids.every((u) => typeof u === "string" && u.length > 0)) {
      throw new HttpsError("invalid-argument", "uids 배열의 모든 요소는 비어있지 않은 문자열이어야 합니다.");
    }
    if (!businessId) {
      throw new HttpsError("invalid-argument", "businessId가 필요합니다.");
    }

    // 호출자 역할 검증
    const callerUid = request.auth.uid;
    const callerSnap = await db.collection("users").doc(callerUid).get();
    const callerData = callerSnap.data();
    if (!callerData) {
      throw new HttpsError("not-found", "호출자 정보를 찾을 수 없습니다.");
    }

    const callerRole = callerData.role as string | undefined;
    const callerSubAdminOf = callerData.subAdminOf as string | undefined;

    const isSuperAdmin = callerRole === "SUPER_ADMIN";
    // H-07: users.managedBusinessIds 대신 businesses.adminIds 기준으로 검증 (단일 진실 소스)
    let isAdmin = false;
    if (callerRole === "BUSINESS_ADMIN") {
      const bizSnap = await db.collection("businesses").doc(businessId).get();
      const bizData = bizSnap.data();
      const adminIds: string[] = bizData
        ? (Array.isArray(bizData.adminIds) ? bizData.adminIds : (bizData.ownerId ? [bizData.ownerId as string] : []))
        : [];
      isAdmin = adminIds.includes(callerUid);
    }
    // SEC-26: SubAdmin은 role="USER" + subAdminOf 필드로 구별 ("SUB_ADMIN" 문자열 없음)
    const isSubAdmin = callerRole === "USER" && !!callerSubAdminOf && callerSubAdminOf === businessId;

    if (!isSuperAdmin && !isAdmin && !isSubAdmin) {
      throw new HttpsError("permission-denied", "해당 사업장 조회 권한이 없습니다.");
    }

    // Admin SDK 배치 조회 (Firestore 보안 규칙 우회 — 서버 검증으로 대체)
    const refs = uids.map((uid) => db.collection("users").doc(uid));
    const snaps = await db.getAll(...refs);

    // 반환 제외 민감 필드 (FCM 토큰은 서버 전송 전용 — 클라이언트 노출 금지)
    // SEC-41: passwordHistory·ciHash·phoneHash·accountNumber 누락으로 관리자에게 노출되던 문제 수정
    const SENSITIVE_FIELDS = new Set([
      "ci", "residentNumber", "foreignIdNumber",
      "idCardImageUrl", "signatureBase64", "sealBase64", "bankbookImageUrl",
      "fcmToken", "fcmTokens",
      "passwordHistory",  // 비밀번호 해시 이력 — 오프라인 딕셔너리 공격에 활용 가능
      "ciHash",           // CI 해시 — 개인식별정보
      "phoneHash",        // 전화번호 해시 — 개인정보
      "accountNumber",    // 계좌번호 암호화 원문 — 금융정보
    ]);

    const users: Record<string, Record<string, unknown>> = {};
    for (const snap of snaps) {
      if (!snap.exists) continue;
      const data = snap.data()!;

      // 소속 검증: SUPER_ADMIN 외에는 해당 businessId 소속만 반환
      if (!isSuperAdmin && data.businessId !== businessId) continue;

      // 민감 필드 제거 후 반환
      const safeData: Record<string, unknown> = {};
      for (const [key, value] of Object.entries(data)) {
        if (!SENSITIVE_FIELDS.has(key)) safeData[key] = value;
      }
      users[snap.id] = safeData;
    }

    return {users};
  }
);

// ═══════════════════════════════════════════════════════════
// 🏢 내 사업장 목록 조회 (adminIds arrayContains — list 권한 불필요)
// ═══════════════════════════════════════════════════════════

// ─── TrustScore 노쇼 패널티 계산 헬퍼 ───────────────────────
function getNoshowPenaltyFromRules(
  count: number,
  rules: Record<string, number>,
): number {
  if (count === 1) return rules["noshow_1"] ?? -5;
  if (count === 2) return rules["noshow_2"] ?? -8;
  return rules["noshow_3plus"] ?? -10;
}

// ─── [HIGH-02] TrustRule 배열 → lookup 맵 변환 ──────────────
// Firestore에 [{type, points, description, ...}] 배열로 저장되므로
// CF에서 type-keyed 맵으로 변환해 사용해야 함.
// 이전에 Record<string, number>로 직접 캐스팅하면 항상 {} (빈 맵)이 반환되어
// 모든 신뢰도 규칙 설정이 무시되고 하드코딩 기본값만 사용되는 버그 방지.
function ruleArrayToMap(rules: unknown): Record<string, number> {
  if (!Array.isArray(rules)) return {};
  const map: Record<string, number> = {};
  for (const r of rules) {
    if (r && typeof r === "object" && "type" in r && "points" in r) {
      map[r.type as string] = (r.points as number) ?? 0;
    }
  }
  return map;
}

// ═══════════════════════════════════════════════════════════
// 📊 attendance 문서 변경 → totalWorkDays + TrustScore 서버 자동 처리
//
// 설계 원칙:
//   - confirmed 전환(비노쇼): totalWorkDays +1, trustScore work_complete 적용
//   - confirmed → calculated 복귀: totalWorkDays -1, trustScore 롤백
//   - transferred는 취소 불가 경로 — decrement 제외
//   - status=NO_SHOW 신규: noShowCount +1, trustScore noshow 패널티
//   - status=NO_SHOW 해제: noShowCount -1, trustScore 패널티 복원
//   - 멱등성: before/after 비교로 실제 전환 시에만 처리
// ═══════════════════════════════════════════════════════════
export const onAttendanceWageStatusChanged = onDocumentWritten(
  {document: "attendance/{attendanceId}", region: "asia-northeast3"},
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();

    if (!after) return null; // 삭제 이벤트 무시

    const beforeWageStatus = before?.wageStatus as string | undefined;
    const afterWageStatus = after.wageStatus as string | undefined;
    const beforeStatus = before?.status as string | undefined;
    const afterStatus = after.status as string | undefined;
    const userId = after.userId as string | undefined;
    const businessId = (after.businessId ?? before?.businessId) as string | undefined;

    if (!userId || !businessId) return null;

    const userRef = db.collection("users").doc(userId);

    // ─── 1. wageStatus 변경 처리 (노쇼 문서 제외) ────────────
    // 노쇼 문서는 wageStatus=confirmed이어도 실제 근무 완료가 아님 — 별도 처리
    // [BUG-FIX] 상태값 수정: "wageConfirmed"→"confirmed", "wageTransferred"→"transferred"
    //   Dart AttendanceModel.wageConfirmed='confirmed', wageTransferred='transferred'
    const isNoshowDoc = afterStatus === "NO_SHOW" || beforeStatus === "NO_SHOW";
    const wageConfirmedOn = !isNoshowDoc &&
      afterWageStatus === "confirmed" &&
      beforeWageStatus !== "confirmed";
    const wageConfirmedOff = !isNoshowDoc &&
      beforeWageStatus === "confirmed" &&
      afterWageStatus !== "confirmed" &&
      afterWageStatus !== "transferred";

    if (wageConfirmedOn || wageConfirmedOff) {
      const rulesSnap = await db.collection("settings").doc("trust_rules").get();
      const rulesData = rulesSnap.data() ?? {};
      const maxScore = (rulesData.maxScore as number) ?? 100;
      const increaseRules = ruleArrayToMap(rulesData.increaseRules);
      const workCompletePoints = increaseRules["work_complete"] ?? 1;
      const workDayDelta = wageConfirmedOn ? 1 : -1;
      const trustChange = wageConfirmedOn ? workCompletePoints : -workCompletePoints;
      const trustReason = wageConfirmedOn ? "work_complete" : "work_complete_canceled";

      await db.runTransaction(async (tx) => {
        const userSnap = await tx.get(userRef);
        if (!userSnap.exists) return;
        const currentScore = (userSnap.data()?.trustScore ?? 50) as number;
        const newScore = Math.min(maxScore, Math.max(0, currentScore + trustChange));

        tx.update(userRef, {
          totalWorkDays: admin.firestore.FieldValue.increment(workDayDelta),
          trustScore: newScore,
        });

        const histRef = db.collection("trust_score_history").doc();
        tx.set(histRef, {
          userId,
          businessId,
          previousScore: currentScore,
          newScore,
          change: trustChange,
          reason: trustReason,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      });
      return null;
    }

    // ─── 2. status 노쇼 변경 처리 ────────────────────────────
    const noshowOn = afterStatus === "NO_SHOW" && beforeStatus !== "NO_SHOW";
    const noshowOff = beforeStatus === "NO_SHOW" && afterStatus !== "NO_SHOW";

    if (noshowOn || noshowOff) {
      const rulesSnap = await db.collection("settings").doc("trust_rules").get();
      const rulesData = rulesSnap.data() ?? {};
      const maxScore = (rulesData.maxScore as number) ?? 100;
      const decreaseRules = ruleArrayToMap(rulesData.decreaseRules);

      await db.runTransaction(async (tx) => {
        const userSnap = await tx.get(userRef);
        if (!userSnap.exists) return;
        const userData = userSnap.data()!;
        const currentScore = (userData.trustScore ?? 50) as number;
        const currentNoShowCount = (userData.noShowCount ?? 0) as number;

        let newNoShowCount: number;
        let trustChange: number;
        let trustReason: string;

        if (noshowOn) {
          newNoShowCount = currentNoShowCount + 1;
          trustChange = getNoshowPenaltyFromRules(newNoShowCount, decreaseRules);
          trustReason = "noshow";
        } else {
          const appliedPenalty = getNoshowPenaltyFromRules(currentNoShowCount, decreaseRules);
          newNoShowCount = Math.max(0, currentNoShowCount - 1);
          trustChange = -appliedPenalty; // 음수 패널티의 역수 → 양수 복원
          trustReason = "noshow_canceled";
        }

        const newScore = Math.min(maxScore, Math.max(0, currentScore + trustChange));

        tx.update(userRef, {
          noShowCount: newNoShowCount,
          trustScore: newScore,
        });

        const histRef = db.collection("trust_score_history").doc();
        tx.set(histRef, {
          userId,
          businessId,
          previousScore: currentScore,
          newScore,
          change: trustChange,
          reason: trustReason,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      });
    }

    return null;
  },
);

// ═══════════════════════════════════════════════════════════
// 출근 기록 생성 시 서버 검증 — 지각 재판정 + GPS 위치 검증
// ═══════════════════════════════════════════════════════════
// [HIGH-02] 클라이언트 로컬 시각(checkIn) → 서버 타임스탬프(checkInTime) 기준 지각 재판정
// [HIGH-03] checkInLat/Lng을 사업장 좌표와 서버에서 재비교
//   반경 초과 시 checkInSuspicious:true, checkInDistance:N 마킹 (관리자 검토용)
export const onAttendanceCreated = onDocumentCreated(
  {document: "attendance/{attendanceId}", region: "asia-northeast3"},
  async (event) => {
    const data = event.data?.data();
    if (!data || !data.checkIn) return null;

    const applicationId = data.applicationId as string | undefined;
    const businessId = data.businessId as string | undefined;
    const checkInTime = data.checkIn as Timestamp | undefined;  // Dart는 'checkIn' 키로 저장
    const checkInLat = data.checkInLat as number | undefined;
    const checkInLng = data.checkInLng as number | undefined;
    const checkInMethod = data.checkInMethod as string | undefined;
    const workDate = data.workDate as Timestamp | undefined;

    if (!applicationId || !businessId || !checkInTime) return null;

    const updates: Record<string, unknown> = {};

    // yearMonth 안전망 — Dart checkIn()이 누락했을 경우 CF에서 채움
    if (!data.yearMonth && workDate) {
      // [KST-FIX] workDate.toDate().getFullYear() = UTC 기준 → KST 날짜 1일 오차
      const KST_OFFSET_MS = 9 * 60 * 60 * 1000;
      const dKST = new Date(workDate.toDate().getTime() + KST_OFFSET_MS);
      updates.yearMonth = `${dKST.getUTCFullYear()}-${String(dKST.getUTCMonth() + 1).padStart(2, "0")}`;
    }

    // 1. Application 조회 → 예정 출근 시각
    let scheduledStart: string | undefined;
    try {
      const appDoc = await db.collection("applications").doc(applicationId).get();
      if (appDoc.exists) {
        const appData = appDoc.data()!;
        const slotId = appData.slotId as string | undefined;
        const toId = appData.toId as string | undefined;
        if (slotId && toId) {
          // flex 공고: 슬롯 workDetails[0].startTime 우선
          const slotDoc = await db.collection("tos").doc(toId)
            .collection("slots").doc(slotId).get();
          if (slotDoc.exists) {
            const wds = slotDoc.data()?.workDetails as Array<{startTime?: string}> | undefined;
            scheduledStart = wds?.[0]?.startTime;
          }
        }
        if (!scheduledStart) {
          scheduledStart = appData.startTime as string | undefined;
        }
      }
    } catch (e) {
      console.error("[onAttendanceCreated] Application 조회 실패:", e);
    }

    // 2. 지각 재판정 (서버 타임스탬프 기준)
    if (scheduledStart && workDate) {
      try {
        const checkInDate = checkInTime.toDate();
        // [KST-FIX] workDate.toMillis() = KST 자정(UTC ms). KST h:m 시각 = workDate.toMillis() + h:m ms.
        // 당일·야간교대 모두 단일 공식으로 처리 — isNextDay 분기 불필요.
        const [schedHour, schedMin] = scheduledStart.split(":").map(Number);
        const scheduledStartMs = workDate.toMillis() + (schedHour * 60 + schedMin) * 60000;
        const isLate = checkInDate.getTime() > scheduledStartMs;

        const serverStatus = isLate ? "late" : "present";
        if ((data.status as string) !== serverStatus) {
          updates.status = serverStatus;
          console.log(
            `[onAttendanceCreated] 지각 재판정: ${data.status} → ${serverStatus}` +
            ` (${event.params.attendanceId})`
          );
        }
      } catch (e) {
        console.error("[onAttendanceCreated] 지각 재판정 실패:", e);
      }
    }

    // 3. GPS 좌표 서버 검증 (gps 방식만)
    if (checkInMethod === "gps" && checkInLat != null && checkInLng != null) {
      try {
        const bizDoc = await db.collection("businesses").doc(businessId).get();
        if (bizDoc.exists) {
          const bizData = bizDoc.data()!;
          const bizLat = bizData.latitude as number | undefined;
          const bizLng = bizData.longitude as number | undefined;
          const gpsRadius = (bizData.gpsRadius as number | undefined) ?? 100;
          if (bizLat != null && bizLng != null) {
            const distM = haversineDistanceMeters(checkInLat, checkInLng, bizLat, bizLng);
            updates.checkInDistance = Math.round(distM);
            if (distM > gpsRadius * 1.5) {
              updates.checkInSuspicious = true;
              console.log(
                `[onAttendanceCreated] GPS 의심: ${Math.round(distM)}m > ` +
                `허용 ${Math.round(gpsRadius * 1.5)}m (${event.params.attendanceId})`
              );
            }
          }
        }
      } catch (e) {
        console.error("[onAttendanceCreated] 사업장 위치 조회 실패:", e);
      }
    }

    if (Object.keys(updates).length === 0) return null;
    try {
      await event.data!.ref.update(updates);
    } catch (e) {
      console.error("[onAttendanceCreated] 업데이트 실패:", e);
    }
    return null;
  }
);

// ═══════════════════════════════════════════════════════════
// 🏢 사업장 생성 시 자동 승인 처리
// ═══════════════════════════════════════════════════════════
// Trust Boundary Charter: 법적 상태 전이(isApproved) → CF 처리 필수
// settings/system.businessAutoApprove=true(기본)이면 즉시 isApproved:true
// false이면 슈퍼관리자가 수동으로 승인해야 활성화됨
export const onBusinessCreated = onDocumentCreated(
  {document: "businesses/{businessId}", region: "asia-northeast3"},
  async (event) => {
    const data = event.data?.data();
    if (!data) return null;

    // 이미 승인됐거나 비활성 상태면 처리 불필요
    if (data.isApproved === true) return null;

    try {
      const settingsDoc = await db.collection("settings").doc("system").get();
      const autoApprove = settingsDoc.exists
        ? (settingsDoc.data()?.businessAutoApprove as boolean | undefined) ?? true
        : true;  // settings/system 문서 없으면 기본값 자동승인

      if (autoApprove) {
        await event.data!.ref.update({
          isApproved: true,
          approvedAt: Timestamp.now(),
          approvedBy: "system_auto",
        });
        console.log(`[onBusinessCreated] 자동 승인 완료: ${event.params.businessId}`);
      } else {
        console.log(`[onBusinessCreated] 수동 승인 대기: ${event.params.businessId}`);
      }
    } catch (e) {
      console.error("[onBusinessCreated] 승인 처리 실패:", e);
    }

    return null;
  }
);

// Haversine 공식 — 두 좌표 간 거리 (미터)
function haversineDistanceMeters(
  lat1: number, lng1: number, lat2: number, lng2: number
): number {
  const R = 6371000;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLng = (lng2 - lng1) * Math.PI / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLng / 2) * Math.sin(dLng / 2);
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

// ═══════════════════════════════════════════════════════════
// 🏢 내 사업장 목록 조회 (adminIds arrayContains — list 권한 불필요)
// ═══════════════════════════════════════════════════════════
export const callableGetMyBusiness = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    }

    const callerUid = request.auth.uid;

    const snap = await db
      .collection("businesses")
      .where("adminIds", "array-contains", callerUid)
      .orderBy("createdAt", "desc")
      .get();

    // adminIds/ownerId 제거 — 다른 관리자 UID 노출 방지 (SEC-20)
    const SENSITIVE_FIELDS = new Set(["adminIds", "ownerId"]);

    const businesses: Array<Record<string, unknown>> = [];
    for (const doc of snap.docs) {
      const data = doc.data();
      const safeData: Record<string, unknown> = {id: doc.id};
      for (const [key, value] of Object.entries(data)) {
        if (!SENSITIVE_FIELDS.has(key)) safeData[key] = value;
      }
      businesses.push(safeData);
    }

    return {businesses};
  }
);

// ─── 노쇼 제한 만료 계산 헬퍼 ─────────────────────────────
function _noShowRestrictionUntilFromCount(count: number): Date | null {
  if (count <= 0) return null;
  const now = new Date();
  switch (count) {
    case 1: return new Date(now.getTime() + 3 * 24 * 60 * 60 * 1000);
    case 2: return new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);
    case 3: return new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000);
    default: return new Date(9999, 11, 31); // 슈퍼관리자 수동 해제 전까지 영구
  }
}

// ═══════════════════════════════════════════════════════════
// 📛 당일 취소 노쇼 패널티 — 본인 확정 취소 시 클라이언트에서 호출
//
// 설계 원칙:
//   - Firestore 규칙상 USER가 본인 noShowCount를 직접 write 불가
//   - Admin SDK로 noShowCount +1 + 단계별 restrictedUntil 설정
//   - 본인 applicationId만 처리 (userId == callerUid 검증)
// ═══════════════════════════════════════════════════════════
export const callableApplyNoShowPenalty = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;
    const {applicationId} = request.data as {applicationId: string};
    if (!applicationId) throw new HttpsError("invalid-argument", "applicationId 필수");

    const appSnap = await db.collection("applications").doc(applicationId).get();
    if (!appSnap.exists) throw new HttpsError("not-found", "지원 정보를 찾을 수 없습니다.");
    const appData = appSnap.data()!;
    const userId = appData.uid as string;

    if (userId !== callerUid) {
      throw new HttpsError("permission-denied", "본인 지원만 처리할 수 있습니다.");
    }

    // [C-4 수정] CANCELED도 허용 — Dart 호출 순서: batch.commit(status=CANCELED) 후 CF 호출
    // 따라서 CF 도달 시점에 이미 CANCELED 상태. 본인 확인(callerUid)은 위에서 완료.
    // REJECTED/AUTO_CANCELED는 관리자/시스템 처리 — 본인이 직접 취소한 게 아니므로 패널티 미적용.
    const appStatus = appData.status as string;
    if (!["CONFIRMED", "CONTRACT_PENDING", "CANCELED"].includes(appStatus)) {
      throw new HttpsError(
        "failed-precondition",
        `노쇼 패널티 적용 불가한 상태입니다 (현재: ${appStatus})`
      );
    }

    // [M-08-FIX] workDate 서버 재검증 — 클라이언트 shouldApplyPenalty 우회 차단
    //   당일 취소(24시간 이내) 여부를 서버 Firestore 데이터 기준으로 재확인
    const workDateTs = appData.workDate as admin.firestore.Timestamp | undefined;
    if (!workDateTs) {
      throw new HttpsError("failed-precondition", "근무 날짜 정보를 찾을 수 없습니다.");
    }
    const diffMs = Math.abs(Date.now() - workDateTs.toMillis());
    if (diffMs > 48 * 60 * 60 * 1000) {
      // 48시간 허용 — 자정 전후 네트워크 지연 + 야간근무(익일 종료) 케이스 포함
      throw new HttpsError("failed-precondition", "당일 취소에만 노쇼 패널티가 적용됩니다.");
    }

    const userRef = db.collection("users").doc(userId);

    // [HIGH-01] trustScore 갱신: noShowCount+1과 동시에 패널티 적용
    // [HIGH-02] ruleArrayToMap: Firestore 배열 형식 올바르게 파싱
    const rulesSnap = await db.collection("settings").doc("trust_rules").get();
    const rulesData = rulesSnap.data() ?? {};
    const maxScore = (rulesData.maxScore as number) ?? 100;
    const decreaseRules = ruleArrayToMap(rulesData.decreaseRules);
    const businessId = (appData.businessId as string | undefined) ?? "";

    await db.runTransaction(async (tx) => {
      // [HIGH] 멱등성 가드 — 네트워크 재시도로 noShowCount 중복 증가 차단
      const freshAppSnap = await tx.get(db.collection("applications").doc(applicationId));
      if (freshAppSnap.data()?.noShowPenaltyAppliedAt) return;

      const userSnap = await tx.get(userRef);
      if (!userSnap.exists) return;
      const userData = userSnap.data()!;
      const prev = (userData.noShowCount ?? 0) as number;
      const prevScore = (userData.trustScore ?? 50) as number;
      const newCount = prev + 1;
      const restrictedUntil = _noShowRestrictionUntilFromCount(newCount);

      const penaltyPoints = getNoshowPenaltyFromRules(newCount, decreaseRules);
      const newScore = Math.min(maxScore, Math.max(0, prevScore + penaltyPoints));

      const updates: Record<string, unknown> = {
        noShowCount: newCount,
        trustScore: newScore,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      if (restrictedUntil !== null) {
        updates.restrictedUntil = admin.firestore.Timestamp.fromDate(restrictedUntil);
      }
      tx.update(userRef, updates);
      // 멱등성 플래그 기록
      tx.update(db.collection("applications").doc(applicationId), {
        noShowPenaltyAppliedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      const histRef = db.collection("trust_score_history").doc();
      tx.set(histRef, {
        userId,
        businessId,
        previousScore: prevScore,
        newScore,
        change: penaltyPoints,
        reason: "noshow_same_day_cancel",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    return {success: true};
  },
);

// ═══════════════════════════════════════════════════════════
// 🔒 확정 지원 취소 — canceledBy 서버 강제, statusHistory.at CF 서버 시간
//
// 보안 목적:
//   - canceledBy를 클라이언트가 위조해 다른 관리자에게 책임 전가하는 공격 차단
//   - Timestamp.now() 클라이언트 기기 시간 조작 차단 (statusHistory.at)
//   - 확정 상태가 아닌 지원서에 대한 취소 시도 차단
//
// 호출자: 지원자 본인(USER_CANCELED/SAME_DAY_CANCEL) 또는 사업장 관리자(ADMIN_CANCELED)
// 반환값: slot decrement · 패널티 · 알림에 필요한 지원서 필드 일체
// ═══════════════════════════════════════════════════════════
export const callableCancelConfirmedApplication = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;
    const {applicationId, cancelReason, applyNoShowPenalty = false} = request.data as {
      applicationId: string;
      cancelReason?: string;
      applyNoShowPenalty?: boolean;
    };
    if (!applicationId) throw new HttpsError("invalid-argument", "applicationId 필수");

    // 1. 지원서 조회
    const appRef = db.collection("applications").doc(applicationId);
    const appSnap = await appRef.get();
    if (!appSnap.exists) throw new HttpsError("not-found", "지원서를 찾을 수 없습니다.");
    const appData = appSnap.data()!;

    // 2. 확정 상태 검증
    const currentStatus = appData.status as string;
    if (!CONFIRMED_STATUSES.includes(currentStatus)) {
      throw new HttpsError("failed-precondition", "확정된 지원만 취소할 수 있습니다.");
    }

    // 3. 호출자 권한 검증 — 지원자 본인 또는 사업장 관리자/서브관리자/SUPER_ADMIN
    const workerUid = appData.uid as string;
    const appBusinessId = appData.businessId as string | undefined;
    const isOwner = workerUid === callerUid;

    const callerSnap = await db.collection("users").doc(callerUid).get();
    const callerData = callerSnap.data();
    const callerRole = callerData?.role as string | undefined;
    const isSuperAdminCaller = callerRole === "SUPER_ADMIN";
    const callerSubAdminOf = callerData?.subAdminOf as string | undefined;
    const isSubAdminOfBiz = callerSubAdminOf === appBusinessId;

    let isAdminOfBiz = false;
    if (!isOwner && !isSuperAdminCaller && !isSubAdminOfBiz && appBusinessId) {
      const bizSnap = await db.collection("businesses").doc(appBusinessId).get();
      const bizData = bizSnap.data();
      const adminIds: string[] = Array.isArray(bizData?.adminIds) ? bizData!.adminIds as string[] : [];
      const ownerId = bizData?.ownerId as string | undefined;
      isAdminOfBiz = adminIds.includes(callerUid) || ownerId === callerUid;
    }

    if (!isOwner && !isSuperAdminCaller && !isSubAdminOfBiz && !isAdminOfBiz) {
      throw new HttpsError("permission-denied", "해당 지원서에 대한 취소 권한이 없습니다.");
    }

    // 4. 취소 유형 결정
    const isAdminCancel = !isOwner;
    const cancelReasonCode = isAdminCancel
      ? "ADMIN_CANCELED"
      : (applyNoShowPenalty ? "SAME_DAY_CANCEL" : "USER_CANCELED");
    const action = isAdminCancel ? "ADMIN_CANCEL_CONFIRMED" : "CONFIRM_CANCEL";

    // 5. application 상태 업데이트 (Admin SDK — canceledBy 서버 강제)
    const updateData: Record<string, unknown> = {
      status: "CANCELED",
      canceledAt: admin.firestore.FieldValue.serverTimestamp(),
      cancelReason: cancelReasonCode,
      statusHistory: admin.firestore.FieldValue.arrayUnion({
        status: "CANCELED",
        at: admin.firestore.Timestamp.now(), // CF 서버 시간 — 클라이언트 위조 불가
        by: callerUid,                        // 서버 강제 — 다른 관리자 UID 위조 차단
        action,
        reason: cancelReason ?? cancelReasonCode,
      }),
    };
    if (isAdminCancel && cancelReason) updateData.cancelMessage = cancelReason;
    if (isAdminCancel) updateData.canceledBy = callerUid; // 서버 강제

    await appRef.update(updateData);

    // 6. 클라이언트 후속 처리(slot decrement, 패널티, 알림)에 필요한 값 반환
    return {
      success: true,
      workerUid,
      toId: (appData.toId as string | undefined) ?? null,
      slotId: (appData.slotId as string | undefined) ?? null,
      selectedWorkType: (appData.selectedWorkType as string | undefined) ?? null,
      businessId: (appData.businessId as string | undefined) ?? null,
      businessName: (appData.businessName as string | undefined) ?? null,
      workDateMs: (appData.workDate as admin.firestore.Timestamp | undefined)?.toMillis() ?? null,
      workDetailId: (appData.workDetailId as string | undefined) ?? null,
      isAdminCancel,
      cancelReasonCode,
    };
  },
);

// ═══════════════════════════════════════════════════════════
// 🔒 슬롯 확정 인원 감소 — cancelConfirmedApplication 배치 이후 호출
//
// 설계 원칙:
//   - USER가 클라이언트에서 직접 slots.confirmedCount를 write 불가
//     (보안 취약점: 정원 초과 지원 허용 위험 — application 없이 slot만 단독 감소 가능)
//   - 대신 application UPDATE(배치) 성공 후 이 CF를 Admin SDK로 호출
//   - CF 실패 시 syncTOStats가 주기적으로 정합성 복구 → 치명적 오류 아님
//   - cancelConfirmedApplication의 _decrementTOConfirmed 역할을 서버에서 담당
//   - updateApplicationStatus(관리자 롤백)는 관리자 규칙으로 배치 처리 — 이 CF 미사용
// ═══════════════════════════════════════════════════════════
export const callableDecrementSlotConfirmed = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;
    const {applicationId, toId, slotId, workType} = request.data as {
      applicationId: string;  // 소유권/관리자 검증에 사용 — 파라미터 불일치 차단
      toId: string;
      slotId: string | null;
      workType: string | null;
    };
    if (!applicationId) throw new HttpsError("invalid-argument", "applicationId 필수");
    if (!toId) throw new HttpsError("invalid-argument", "toId 필수");

    // 1. application 문서로 소유자·TO 일치 검증
    //    — 임의 toId/slotId 전달해 타인 슬롯 confirmedCount 감소하는 공격 차단
    const appSnap = await db.collection("applications").doc(applicationId).get();
    if (!appSnap.exists) throw new HttpsError("not-found", "지원 정보를 찾을 수 없습니다.");
    const appData = appSnap.data()!;

    // 2. 상태 검증 — CANCELED 상태가 아니면 이미 취소된 것이 아님
    if (appData.status !== "CANCELED") {
      throw new HttpsError("failed-precondition", "취소된 지원서에 대해서만 호출 가능합니다.");
    }

    // 3. toId/slotId 일치 검증 — 파라미터 조작으로 다른 슬롯 감소 차단
    const appToId = appData.toId as string | undefined;
    const appSlotId = (appData.slotId as string | undefined) ?? null;
    if (appToId !== toId) {
      throw new HttpsError("permission-denied", "toId가 지원서와 일치하지 않습니다.");
    }
    if (appSlotId !== slotId) {
      throw new HttpsError("permission-denied", "slotId가 지원서와 일치하지 않습니다.");
    }

    // 4. 호출자 권한 검증 — 소유자(USER 취소) 또는 해당 사업장 관리자/서브관리자 또는 슈퍼어드민
    const callerSnap = await db.collection("users").doc(callerUid).get();
    const callerData = callerSnap.data();
    const callerRole = callerData?.role as string | undefined;
    const isOwner = appData.uid === callerUid;
    const isSuperAdminCaller = callerRole === "SUPER_ADMIN";
    const appBusinessId = appData.businessId as string | undefined;
    // SubAdmin: role="USER" + subAdminOf===businessId (firestore.rules isSubAdminOf 패턴과 동일)
    const callerSubAdminOf = callerData?.subAdminOf as string | undefined;
    const isSubAdminOfBiz = callerSubAdminOf === appBusinessId;
    let isAdminOfBiz = false;
    if (!isOwner && !isSuperAdminCaller && !isSubAdminOfBiz) {
      if (appBusinessId) {
        const bizSnap = await db.collection("businesses").doc(appBusinessId).get();
        const bizData = bizSnap.data();
        const adminIds: string[] = Array.isArray(bizData?.adminIds) ? bizData!.adminIds as string[] : [];
        const ownerId = bizData?.ownerId as string | undefined;
        isAdminOfBiz = adminIds.includes(callerUid) || ownerId === callerUid;
      }
    }
    if (!isOwner && !isSuperAdminCaller && !isSubAdminOfBiz && !isAdminOfBiz) {
      throw new HttpsError("permission-denied", "해당 지원서에 대한 권한이 없습니다.");
    }

    // workType 교차검증 — 클라이언트 제공 값 대신 appData.selectedWorkType 사용
    const appWorkType = (appData.selectedWorkType as string | undefined) ?? null;
    if (workType && appWorkType && workType !== appWorkType) {
      throw new HttpsError("permission-denied", "workType이 지원서와 일치하지 않습니다.");
    }
    const resolvedWorkType = appWorkType ?? workType;

    const toRef = db.collection("tos").doc(toId);

    // [MEDIUM-FIX] batch → transaction: 음수 방지(floor) + 멱등성 보장
    // 동일 applicationId 중복 호출 시 totalConfirmed 음수화 → 정원 초과 지원 허용 취약점 차단
    await db.runTransaction(async (tx) => {
      const freshAppRef = db.collection("applications").doc(applicationId);
      const freshAppSnap = await tx.get(freshAppRef);
      const freshAppData = freshAppSnap.data()!;
      // 멱등성: 이미 처리된 요청은 no-op
      if (freshAppData.confirmedDecrementedAt) {
        return;
      }
      // 음수 방지: totalConfirmed가 이미 0 이하이면 중단
      const toSnap = await tx.get(toRef);
      const currentConfirmed = (toSnap.data()?.totalConfirmed as number) ?? 0;
      if (currentConfirmed <= 0) {
        tx.update(freshAppRef, {confirmedDecrementedAt: admin.firestore.FieldValue.serverTimestamp()});
        return;
      }
      const toUpdate: Record<string, admin.firestore.FieldValue> = {
        totalConfirmed: admin.firestore.FieldValue.increment(-1),
      };
      if (!slotId && resolvedWorkType) {
        toUpdate[`workTypeConfirmedCounts.${resolvedWorkType}`] = admin.firestore.FieldValue.increment(-1);
      }
      tx.update(toRef, toUpdate);
      if (slotId) {
        const slotRef = toRef.collection("slots").doc(slotId);
        // [L-1] 슬롯 레벨 음수 방어 — TO 레벨 체크와 독립적으로 슬롯도 보호
        const slotSnap = await tx.get(slotRef);
        const slotConfirmedCount = (slotSnap.data()?.confirmedCount as number) ?? 0;
        if (slotConfirmedCount > 0) {
          const slotUpdate: Record<string, admin.firestore.FieldValue> = {
            confirmedCount: admin.firestore.FieldValue.increment(-1),
          };
          if (resolvedWorkType) {
            slotUpdate[`workTypeCounts.${resolvedWorkType}.confirmedCount`] = admin.firestore.FieldValue.increment(-1);
          }
          tx.update(slotRef, slotUpdate);
        }
      }
      tx.update(freshAppRef, {confirmedDecrementedAt: admin.firestore.FieldValue.serverTimestamp()});
    });
    console.log(`✅ slot confirmedCount 감소 — appId:${applicationId} toId:${toId} slotId:${slotId ?? "none"}`);
  },
);

// ═══════════════════════════════════════════════════════════
// 🔄 AUTO_CANCEL — 확정 시 타사업장 포함 충돌 지원서 자동 취소
// [SEC-FIX] Dart 클라이언트에서 uid 단독 LIST 쿼리 시 BUSINESS_ADMIN은
//   isUser()=false → LIST 규칙 불충족 → PERMISSION_DENIED → 항상 [] 반환
//   → 충돌 AUTO_CANCEL 전혀 미작동. Admin SDK로 이전해 타사업장 포함 처리.
// ═══════════════════════════════════════════════════════════

function _hasTimeOverlap(s1: string, e1: string, s2: string, e2: string): boolean {
  if (!s1 || !e1 || !s2 || !e2) return false;
  return s1 < e2 && s2 < e1;
}

const _WEEKDAY = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"] as const;

function _isConflictShortTerm(
  app: FirebaseFirestore.DocumentData,
  workDateMs: number,
  startTime: string,
  endTime: string,
): boolean {
  if (!_hasTimeOverlap(startTime, endTime, app.startTime ?? "", app.endTime ?? "")) return false;
  const appIsLong = app.applicationType === "longTerm" || (Array.isArray(app.workDays) && (app.workDays as string[]).length > 0);
  const workDate = new Date(workDateMs);
  if (appIsLong) {
    const aStart: number = (app.desiredStartDate ?? app.workDate)?.toMillis?.() ?? 0;
    const aEnd: number = (app.actualResignDate ?? app.workEndDate)?.toMillis?.() ?? Infinity;
    const ms = workDate.getTime();
    if (ms < aStart || ms > aEnd) return false;
    const days: string[] = Array.isArray(app.workDays) ? (app.workDays as string[]) : [];
    if (days.length > 0 && !days.includes(_WEEKDAY[workDate.getDay()])) return false;
    return true;
  } else {
    const aMs: number = (app.workDate as FirebaseFirestore.Timestamp | undefined)?.toMillis?.() ?? 0;
    const aDate = new Date(aMs);
    return (
      aDate.getFullYear() === workDate.getFullYear() &&
      aDate.getMonth() === workDate.getMonth() &&
      aDate.getDate() === workDate.getDate()
    );
  }
}

function _isConflictLongTerm(
  app: FirebaseFirestore.DocumentData,
  startDateMs: number,
  endDateMs: number,
  workDays: string[],
  startTime: string,
  endTime: string,
): boolean {
  if (!_hasTimeOverlap(startTime, endTime, app.startTime ?? "", app.endTime ?? "")) return false;
  const appIsLong = app.applicationType === "longTerm" || (Array.isArray(app.workDays) && (app.workDays as string[]).length > 0);
  const effectiveEnd = endDateMs >= 0 ? endDateMs : Infinity;
  if (appIsLong) {
    const aStart: number = (app.desiredStartDate ?? app.workDate)?.toMillis?.() ?? 0;
    const aEnd: number = (app.actualResignDate ?? app.workEndDate)?.toMillis?.() ?? Infinity;
    if (effectiveEnd < aStart || startDateMs > aEnd) return false;
    const aWorkDays: string[] = Array.isArray(app.workDays) ? (app.workDays as string[]) : [];
    return aWorkDays.length > 0 && workDays.some((d) => aWorkDays.includes(d));
  } else {
    const aMs: number = (app.workDate as FirebaseFirestore.Timestamp | undefined)?.toMillis?.() ?? 0;
    if (aMs < startDateMs || aMs > effectiveEnd) return false;
    const dayCode = _WEEKDAY[new Date(aMs).getDay()];
    return workDays.includes(dayCode);
  }
}

export const callableAutoConflictCancel = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;
    const {
      confirmedAppId, targetUid, businessId, businessName,
      startTime, endTime,
      workDate,
      isLongTerm,
      startDate, endDate,
      workDays,
    } = request.data as {
      confirmedAppId: string;
      targetUid: string;
      businessId: string;
      businessName: string;
      startTime: string;
      endTime: string;
      workDate?: number;
      isLongTerm?: boolean;
      startDate?: number;
      endDate?: number;
      workDays?: string[];
    };
    if (!confirmedAppId || !targetUid || !businessId) {
      throw new HttpsError("invalid-argument", "필수 파라미터 누락 (confirmedAppId, targetUid, businessId)");
    }
    // 표시용 필드 길이 제한 (Firestore 문서에 그대로 저장됨)
    if (businessName && typeof businessName === "string" && businessName.length > 100) {
      throw new HttpsError("invalid-argument", "businessName은 100자를 초과할 수 없습니다.");
    }
    if (startTime && typeof startTime === "string" && startTime.length > 10) {
      throw new HttpsError("invalid-argument", "startTime 형식이 올바르지 않습니다.");
    }
    if (endTime && typeof endTime === "string" && endTime.length > 10) {
      throw new HttpsError("invalid-argument", "endTime 형식이 올바르지 않습니다.");
    }

    // 1. 권한 검증 — SUPER_ADMIN / 사업장 adminIds/ownerId / SubAdmin(subAdminOf===businessId)
    const callerSnap = await db.collection("users").doc(callerUid).get();
    const callerData = callerSnap.data();
    const callerRole = callerData?.role as string | undefined;
    if (!callerRole) throw new HttpsError("permission-denied", "사용자 정보를 찾을 수 없습니다.");
    // SubAdmin: role="USER" + subAdminOf===businessId (firestore.rules isSubAdminOf 패턴과 동일)
    const callerSubAdminOf = callerData?.subAdminOf as string | undefined;
    const isSubAdmin = callerSubAdminOf === businessId;
    if (callerRole !== "SUPER_ADMIN" && !isSubAdmin) {
      const bizSnap = await db.collection("businesses").doc(businessId).get();
      const bizData = bizSnap.data();
      const adminIds: string[] = Array.isArray(bizData?.adminIds) ? (bizData!.adminIds as string[]) : [];
      const ownerId = bizData?.ownerId as string | undefined;
      if (!adminIds.includes(callerUid) && ownerId !== callerUid) {
        throw new HttpsError("permission-denied", "해당 사업장 관리자 권한이 필요합니다.");
      }
    }

    // 2. 확정 지원서 상태 검증
    const confirmedAppSnap = await db.collection("applications").doc(confirmedAppId).get();
    if (!confirmedAppSnap.exists) throw new HttpsError("not-found", "확정 지원서를 찾을 수 없습니다.");
    const confirmedAppData = confirmedAppSnap.data()!;
    if (confirmedAppData.uid !== targetUid) {
      throw new HttpsError("permission-denied", "targetUid가 지원서와 일치하지 않습니다.");
    }
    // 호출자의 businessId와 확정 지원서의 businessId가 일치해야 함
    if (confirmedAppData.businessId !== businessId) {
      throw new HttpsError("permission-denied", "확정 지원서가 해당 사업장에 속하지 않습니다.");
    }
    if (!["CONTRACT_PENDING", "CONFIRMED"].includes(confirmedAppData.status as string)) {
      throw new HttpsError("failed-precondition", `확정/계약 대기 상태가 아닙니다: ${confirmedAppData.status}`);
    }

    // 스케줄 정보는 confirmedAppData에서 직접 읽어 클라이언트 파라미터 우회 방지
    const confirmedIsLongTerm = (confirmedAppData.isLongTerm as boolean | undefined) ?? isLongTerm;
    const confirmedStartDate = (confirmedAppData.startDate as number | undefined) ?? startDate;
    const confirmedEndDate = (confirmedAppData.endDate as number | undefined) ?? endDate;
    const confirmedWorkDays = (confirmedAppData.workDays as string[] | undefined) ?? workDays;
    const confirmedStartTime = (confirmedAppData.startTime as string | undefined) ?? startTime;
    const confirmedEndTime = (confirmedAppData.endTime as string | undefined) ?? endTime;
    // [HIGH-01-FIX] workDate는 런타임에 Timestamp 객체 — `as number`는 타입 단언만이고 변환 없음.
    // Timestamp는 truthy이므로 ?? 폴백 미발생 → new Date(Timestamp_obj) = Invalid Date → 충돌 감지 0건.
    const confirmedWorkDate = (confirmedAppData.workDate as admin.firestore.Timestamp | undefined)?.toMillis() ?? workDate;

    // 3. uid로 충돌 가능 지원서 전체 조회 (Admin SDK — 타사업장 포함)
    const allAppsSnap = await db.collection("applications")
      .where("uid", "==", targetUid)
      .where("status", "in", ["PENDING", "CONFIRMED", "CONTRACT_PENDING"])
      .limit(500)
      .get();

    if (allAppsSnap.size >= 500) {
      console.warn(`⚠️ [W-1] 충돌 지원서 500건 한도 도달 — 일부 취소 누락 가능: uid=${targetUid}`);
    }

    // 4. 충돌 필터링 (서버측 confirmedAppData 값 우선 사용)
    const conflicting = allAppsSnap.docs.filter((d) => {
      if (d.id === confirmedAppId) return false;
      const data = d.data();
      if (confirmedIsLongTerm && confirmedStartDate !== undefined) {
        return _isConflictLongTerm(data, confirmedStartDate, confirmedEndDate ?? -1, confirmedWorkDays ?? [], confirmedStartTime, confirmedEndTime);
      } else if (confirmedWorkDate !== undefined) {
        return _isConflictShortTerm(data, confirmedWorkDate, confirmedStartTime, confirmedEndTime);
      }
      return false;
    });

    if (conflicting.length === 0) {
      return {canceledIds: []};
    }

    // 5. PENDING만 AUTO_CANCELED (CONFIRMED/CONTRACT_PENDING은 동시 확정 [186] — 수동 처리)
    const pendingConflicts = conflicting.filter((d) => d.data().status === "PENDING");
    const concurrent = conflicting.filter((d) =>
      ["CONFIRMED", "CONTRACT_PENDING"].includes(d.data().status as string));
    if (concurrent.length > 0) {
      console.warn(`⚠️ [186] 동시 확정 감지 — 수동 확인: ${concurrent.map((d) => d.id).join(", ")}`);
    }

    // [M-3] 배치 → 개별 트랜잭션: batch.commit 직전 status 재확인으로 race condition 방어
    //   race window: allAppsSnap.get() ~ commit 사이에 타 관리자가 PENDING→CONFIRMED 처리 가능
    //   트랜잭션 내 status 재확인으로 이미 바뀐 문서는 skip
    const now = admin.firestore.Timestamp.now();
    const cancelResults = await Promise.all(
      pendingConflicts.map((conflict) =>
        db.runTransaction(async (tx) => {
          const fresh = await tx.get(conflict.ref);
          if (fresh.data()?.status !== "PENDING") return null; // race window에서 이미 처리됨
          tx.update(conflict.ref, {
            status: "AUTO_CANCELED",
            canceledAt: now,
            cancelReason: "SCHEDULE_CONFLICT",
            conflictingAppId: confirmedAppId,
            conflictingBusiness: businessName,
            conflictingTime: `${confirmedStartTime}~${confirmedEndTime}`,
            statusHistory: admin.firestore.FieldValue.arrayUnion({
              status: "AUTO_CANCELED",
              at: now,
              by: "SYSTEM",
              action: "AUTO_CANCEL",
              reason: "SCHEDULE_CONFLICT",
            }),
          });
          return conflict;
        })
      )
    );
    const actualCanceled = cancelResults.filter(Boolean) as typeof pendingConflicts;

    const canceledIds = actualCanceled.map((d) => d.id);
    const canceledDetails = actualCanceled.map((d) => {
      const data = d.data();
      return {
        id: d.id,
        uid: (data.uid as string) ?? "",
        businessName: (data.businessName as string) ?? "",
        businessId: (data.businessId as string) ?? "",
        selectedWorkType: (data.selectedWorkType as string) ?? "",
        workDateMs: (data.workDate as admin.firestore.Timestamp | undefined)?.toMillis() ?? null,
      };
    });
    console.log(`✅ AUTO_CANCEL ${canceledIds.length}건 — appId:${confirmedAppId}`);
    return {canceledIds, canceledDetails};
  },
);

// ═══════════════════════════════════════════════════════════
// ⏰ 지각 신뢰도 처리 — 관리자/하위관리자 출근 처리 시 호출
//
// 설계 원칙:
//   - 호출자(관리자/하위관리자) 권한 검증
//   - mode: "late" — lateCount+1, trustScore 감소
//   - mode: "late_canceled" — lateCount-1, trustScore 복원
//   - trust_score_history 이력 기록
// ═══════════════════════════════════════════════════════════
export const callableReportLate = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;
    const {userId, businessId, mode, attendanceId} = request.data as {
      userId: string;
      businessId: string;
      mode: "late" | "late_canceled";
      attendanceId?: string;
    };

    if (!userId || !businessId || !mode) {
      throw new HttpsError("invalid-argument", "userId, businessId, mode 필수");
    }
    if (mode !== "late" && mode !== "late_canceled") {
      throw new HttpsError("invalid-argument", "mode는 late 또는 late_canceled");
    }
    // [MEDIUM] attendanceId 필수화 — null 경로에서 멱등성 체크 우회로 lateCount 중복 증가 가능
    if (!attendanceId) {
      throw new HttpsError("invalid-argument", "attendanceId 필수");
    }

    // 호출자 권한 검증 (해당 사업장 관리자/하위관리자/슈퍼어드민)
    const callerSnap = await db.collection("users").doc(callerUid).get();
    const callerRole = (callerSnap.data()?.role ?? "") as string;
    const callerSubAdminOf = (callerSnap.data()?.subAdminOf ?? "") as string;

    let authorized = callerRole === "SUPER_ADMIN";
    if (!authorized && callerRole === "BUSINESS_ADMIN") {
      const bizSnap = await db.collection("businesses").doc(businessId).get();
      const bizSnapData = bizSnap.data();
      const adminIds = (bizSnapData?.adminIds as string[]) ?? [];
      const ownerId = bizSnapData?.ownerId as string | undefined;
      authorized = adminIds.includes(callerUid) || ownerId === callerUid;
    } else if (!authorized && callerRole === "USER" && callerSubAdminOf) {
      // SEC-26: SubAdmin은 role="USER" + subAdminOf 필드로 구별
      authorized = callerSubAdminOf === businessId;
    }
    if (!authorized) throw new HttpsError("permission-denied", "해당 사업장 관리 권한이 필요합니다.");

    // [SEC-06] userId가 해당 businessId 소속 근무자인지 서버 검증
    // SUPER_ADMIN은 모든 사업장 조회 권한이 있으므로 소속 검증 면제
    if (callerRole !== "SUPER_ADMIN") {
      const memberSnap = await db.collection("applications")
        .where("uid", "==", userId)
        .where("businessId", "==", businessId)
        .where("status", "in", ["CONFIRMED", "CONTRACT_PENDING"])
        .limit(1)
        .get();
      if (memberSnap.empty) {
        throw new HttpsError("invalid-argument", "해당 사업장 소속 활성 근무자가 아닙니다.");
      }
    }

    const rulesSnap = await db.collection("settings").doc("trust_rules").get();
    const rulesData = rulesSnap.data() ?? {};
    const maxScore = (rulesData.maxScore as number) ?? 100;
    // [HIGH-02] ruleArrayToMap: Firestore 배열 형식 올바르게 파싱
    const decreaseRules = ruleArrayToMap(rulesData.decreaseRules);
    const latePoints = decreaseRules["late"] ?? -1;
    const lateRepeatPoints = decreaseRules["late_repeat"] ?? -2;
    // [HIGH-03] late_chronic: 6회 이상 지각 단계 추가 (기존 2단계 → 3단계)
    const lateChronicPoints = decreaseRules["late_chronic"] ?? -3;

    const userRef = db.collection("users").doc(userId);
    const attRef = db.collection("attendance").doc(attendanceId);

    await db.runTransaction(async (tx) => {
      // 멱등성 체크 — 같은 attendance에 중복 호출 방지
      const attSnap = await tx.get(attRef);
      if (attSnap.exists) {
        const alreadyApplied = attSnap.data()?.latePenaltyApplied;
        if (mode === "late" && alreadyApplied === true) return;
        if (mode === "late_canceled" && alreadyApplied !== true) return;
      }

      const userSnap = await tx.get(userRef);
      if (!userSnap.exists) return;
      const userData = userSnap.data()!;
      const currentScore = (userData.trustScore ?? 50) as number;
      const currentLateCount = (userData.lateCount ?? 0) as number;

      let newLateCount: number;
      let trustChange: number;
      let trustReason: string;

      if (mode === "late") {
        newLateCount = currentLateCount + 1;
        // [HIGH-03] 3단계 지각: 1~2회=late, 3~5회=late_repeat, 6회+=late_chronic
        if (newLateCount >= 6) {
          trustChange = lateChronicPoints;
        } else if (newLateCount >= 3) {
          trustChange = lateRepeatPoints;
        } else {
          trustChange = latePoints;
        }
        trustReason = "late";
      } else {
        // 취소 시 적용됐던 감점 계산 (currentLateCount 기준)
        let applied: number;
        if (currentLateCount >= 6) {
          applied = lateChronicPoints;
        } else if (currentLateCount >= 3) {
          applied = lateRepeatPoints;
        } else {
          applied = latePoints;
        }
        newLateCount = Math.max(0, currentLateCount - 1);
        trustChange = -applied;
        trustReason = "late_canceled";
      }

      const newScore = Math.min(maxScore, Math.max(0, currentScore + trustChange));

      tx.update(userRef, {lateCount: newLateCount, trustScore: newScore});

      // 멱등성 플래그 갱신 (attendanceId 항상 존재 — 위에서 필수 체크 완료)
      tx.update(attRef, {latePenaltyApplied: mode === "late"});

      const histRef = db.collection("trust_score_history").doc();
      tx.set(histRef, {
        userId, businessId,
        ...(attendanceId && {attendanceId}),
        previousScore: currentScore,
        newScore,
        change: trustChange,
        reason: trustReason,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    return {success: true};
  },
);

// ── callableConfirmWage ──────────────────────────────────────
// [Phase 1] 급여 확정 (pending → calculated) CF 경유 처리
// 클라이언트에서 계산된 wageDetail을 받아 서버에서 검증 후 원자적 저장.
// 직접 Firestore write 대비 강점:
//   - 권한·상태를 서버에서 재검증 (조작 불가)
//   - calculatedAt/calculatedBy 서버 타임스탬프 강제 주입
//   - 음수 금액 차단
// Input:  { attendanceId, wageDetailMap, yearMonth, effectiveNetWage }
// Output: { success: true }
// ═══════════════════════════════════════════════════════════
export const callableConfirmWage = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (_request) => {
    // SEC-70: callableCalculateAndConfirmWage로 대체된 레거시 함수 비활성화
    // wageDetailMap 클라이언트 신뢰 설계 위험 제거 및 불필요한 attack surface 차단
    throw new HttpsError(
      "permission-denied",
      "이 함수는 더 이상 사용되지 않습니다. callableCalculateAndConfirmWage를 사용하세요."
    );
  },
);

// ═══════════════════════════════════════════════════════════
// 📊 급여 계산 서버 헬퍼 (WageCalculator + TaxDeductionService 포팅)
// ═══════════════════════════════════════════════════════════

const SRV_MINIMUM_WAGE_BY_YEAR: Record<number, number> = {
  2026: 10320, 2025: 10030, 2024: 9860, 2023: 9620,
  2022: 9160, 2021: 8720, 2020: 8590,
};
const SRV_OVERTIME_RATE = 1.5;
const SRV_NIGHT_RATE = 0.5;
const SRV_STANDARD_WORK_MINUTES = 480;

interface SrvInsuranceRates {
  nationalPensionRate: number;
  healthInsuranceRate: number;
  ltcInsuranceRate: number;
  employmentInsuranceRate: number;
  dailyWageExemption: number;
  dailyWorkerTaxRate: number;
  localIncomeTaxRate: number;
  businessIncomeRate: number;
  businessIncomeLocalRate: number;
}
// [특이사항] 연도별 법정 보험료율 — 매년 1월 정부고시 후 Firestore 또는 여기에 업데이트 필요
// 우선순위: Firestore settings/wage_config.insuranceRates[year] > 연도별 상수 > 최신 연도 폴백
// srvGetMinimumWage()와 동일한 3단계 우선순위 패턴 적용
const SRV_INSURANCE_RATES_BY_YEAR: Record<number, SrvInsuranceRates> = {
  2025: {
    nationalPensionRate: 4.5, healthInsuranceRate: 3.545, ltcInsuranceRate: 12.95,
    employmentInsuranceRate: 0.9, dailyWageExemption: 150000, dailyWorkerTaxRate: 2.7,
    localIncomeTaxRate: 10.0, businessIncomeRate: 3.0, businessIncomeLocalRate: 0.3,
  },
  // [특이사항] 2026년 보험료율 미확정 — 정부고시 후 실제 값으로 교체 필요 (현재 2025년 값 임시 사용)
  2026: {
    nationalPensionRate: 4.5, healthInsuranceRate: 3.545, ltcInsuranceRate: 12.95,
    employmentInsuranceRate: 0.9, dailyWageExemption: 150000, dailyWorkerTaxRate: 2.7,
    localIncomeTaxRate: 10.0, businessIncomeRate: 3.0, businessIncomeLocalRate: 0.3,
  },
};

interface SrvWageResult {
  wageType: string; baseWage: number; scheduledMinutes: number; actualMinutes: number;
  breakMinutes: number; workMinutes: number; overtimeMinutes: number;
  earlyArrivalMinutes: number; nightMinutes: number; baseAmount: number;
  overtimeAmount: number; earlyArrivalAmount: number; nightAmount: number;
  additionalAmount: number; totalAmount: number; nightAllowanceApplied: boolean;
  appliedMinimumWage: number; appliedSupplementWage: number;
  taxDeductionType: string; nationalPensionDeduction: number;
  healthInsuranceDeduction: number; ltcInsuranceDeduction: number;
  employmentInsuranceDeduction: number; incomeTaxDeduction: number;
  retroactiveDeduction: number; netWage: number;
}

function srvParseTime(time: string): number | null {
  try {
    const parts = time.split(":");
    if (parts.length < 2) return null;
    const hour = parseInt(parts[0], 10);
    const minute = parseInt(parts[1].substring(0, 2), 10);
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return hour * 60 + minute;
  } catch { return null; }
}

function srvMinutesBetween(start: string, end: string): number {
  const s = srvParseTime(start); const e0 = srvParseTime(end);
  if (s === null || e0 === null) return 0;
  let e = e0; if (e < s) e += 1440;
  return e - s;
}

function srvNightMinutes(start: string, end: string): number {
  const s = srvParseTime(start); const e0 = srvParseTime(end);
  if (s === null || e0 === null) return 0;
  let e = e0; if (e < s) e += 1440;
  const ov = (a: number, b: number) => Math.max(0, Math.min(e, b) - Math.max(s, a));
  return ov(0, 360) + ov(1320, 1440) + ov(1440, 1800);
}

function srvGetMinimumWage(year: number, fs: Record<number, number>): number {
  if (fs[year] !== undefined) return fs[year];
  if (SRV_MINIMUM_WAGE_BY_YEAR[year]) return SRV_MINIMUM_WAGE_BY_YEAR[year];
  const latest = Math.max(...Object.keys(SRV_MINIMUM_WAGE_BY_YEAR).map(Number));
  return SRV_MINIMUM_WAGE_BY_YEAR[latest];
}

function srvGetRates(year: number, fs: Record<number, Partial<SrvInsuranceRates>>): SrvInsuranceRates {
  const latestYear = Math.max(...Object.keys(SRV_INSURANCE_RATES_BY_YEAR).map(Number));
  const base = SRV_INSURANCE_RATES_BY_YEAR[year] ?? SRV_INSURANCE_RATES_BY_YEAR[latestYear];
  const raw = fs[year];
  if (!raw) return base;
  return {
    nationalPensionRate: raw.nationalPensionRate ?? base.nationalPensionRate,
    healthInsuranceRate: raw.healthInsuranceRate ?? base.healthInsuranceRate,
    ltcInsuranceRate: raw.ltcInsuranceRate ?? base.ltcInsuranceRate,
    employmentInsuranceRate: raw.employmentInsuranceRate ?? base.employmentInsuranceRate,
    dailyWageExemption: raw.dailyWageExemption ?? base.dailyWageExemption,
    dailyWorkerTaxRate: raw.dailyWorkerTaxRate ?? base.dailyWorkerTaxRate,
    localIncomeTaxRate: raw.localIncomeTaxRate ?? base.localIncomeTaxRate,
    businessIncomeRate: raw.businessIncomeRate ?? base.businessIncomeRate,
    businessIncomeLocalRate: raw.businessIncomeLocalRate ?? base.businessIncomeLocalRate,
  };
}

function srvWageCalculate(p: {
  wageType: string; baseWage: number; minimumWage: number;
  scheduledStart: string; scheduledEnd: string; actualStart: string; actualEnd: string;
  breakMinutes: number; scheduledBreakMinutes: number;
  nightAllowanceApplied: boolean; nightIncluded: boolean; additionalAmount: number;
  baseHourlyWage?: number;
}): SrvWageResult {
  const schedBreak = p.scheduledBreakMinutes;
  const scheduledMinutes = srvMinutesBetween(p.scheduledStart, p.scheduledEnd);
  const actualMinutes = srvMinutesBetween(p.actualStart, p.actualEnd);
  const workMinutes = Math.max(0, actualMinutes - p.breakMinutes);

  let appliedSupplementWage: number;
  if (p.wageType === "hourly") {
    appliedSupplementWage = p.baseWage;
  } else {
    const schedWorkMins = Math.max(0, scheduledMinutes - schedBreak);
    const rawOrd = schedWorkMins > 0 ? Math.round(p.baseWage / schedWorkMins * 60) : 0;
    appliedSupplementWage = p.baseHourlyWage ?? Math.max(rawOrd, p.minimumWage);
  }

  let overtimeMinutes: number;
  if (p.wageType === "hourly") {
    overtimeMinutes = Math.max(0, workMinutes - SRV_STANDARD_WORK_MINUTES);
  } else {
    const schedWorkMins = Math.max(0, scheduledMinutes - schedBreak);
    overtimeMinutes = Math.max(0, workMinutes - schedWorkMins);
  }

  const schedStartMin = srvParseTime(p.scheduledStart) ?? 0;
  const actualStartMin = srvParseTime(p.actualStart) ?? 0;
  const earlyArrivalMinutes = Math.max(0, schedStartMin - actualStartMin);

  let nightMinutes = 0;
  if (p.nightAllowanceApplied) {
    if (p.wageType === "daily" && p.nightIncluded) {
      if (overtimeMinutes > 0) nightMinutes = srvNightMinutes(p.scheduledEnd, p.actualEnd);
    } else {
      const rawNight = srvNightMinutes(p.actualStart, p.actualEnd);
      const dayPortion = actualMinutes - rawNight;
      const breakInNight = Math.max(0, p.breakMinutes - Math.max(0, Math.min(dayPortion, actualMinutes)));
      nightMinutes = Math.max(0, rawNight - breakInNight);
    }
  }

  let baseAmount = 0; let overtimeAmount = 0; let earlyArrivalAmount = 0; let nightAmount = 0;

  if (p.wageType === "hourly") {
    const regMins = workMinutes - overtimeMinutes;
    baseAmount = Math.round(regMins * p.baseWage / 60);
    overtimeAmount = overtimeMinutes > 0
      ? Math.round(overtimeMinutes * p.baseWage * SRV_OVERTIME_RATE / 60) : 0;
    nightAmount = (p.nightAllowanceApplied && nightMinutes > 0)
      ? Math.round(nightMinutes * p.baseWage * SRV_NIGHT_RATE / 60) : 0;
  } else {
    const schedWorkMins = Math.max(0, scheduledMinutes - schedBreak);
    const rawOrdH = schedWorkMins > 0 ? Math.round(p.baseWage / schedWorkMins * 60) : 0;
    const suppW = p.baseHourlyWage ?? Math.max(rawOrdH, p.minimumWage);
    baseAmount = (schedWorkMins === 0 || workMinutes >= schedWorkMins)
      ? p.baseWage
      : Math.round(p.baseWage * workMinutes / schedWorkMins);
    const effEarly = Math.min(earlyArrivalMinutes, overtimeMinutes);
    if (overtimeMinutes > 0 && schedWorkMins > 0) {
      if (workMinutes <= SRV_STANDARD_WORK_MINUTES) {
        overtimeAmount = Math.round(overtimeMinutes * suppW / 60);
        earlyArrivalAmount = Math.round(effEarly * suppW / 60);
      } else {
        const over8 = workMinutes - SRV_STANDARD_WORK_MINUTES;
        const in8 = Math.max(0, overtimeMinutes - over8);
        overtimeAmount = Math.round(in8 * suppW / 60) +
          Math.round(Math.max(0, Math.min(over8, overtimeMinutes)) * suppW * SRV_OVERTIME_RATE / 60);
        const earlyIn8 = Math.min(effEarly, in8);
        const earlyOver8 = Math.max(0, effEarly - earlyIn8);
        earlyArrivalAmount = Math.round(earlyIn8 * suppW / 60) +
          Math.round(earlyOver8 * suppW * SRV_OVERTIME_RATE / 60);
      }
    }
    nightAmount = (p.nightAllowanceApplied && nightMinutes > 0)
      ? Math.round(nightMinutes * suppW * SRV_NIGHT_RATE / 60) : 0;
  }

  const totalAmount = baseAmount + overtimeAmount + nightAmount + p.additionalAmount;
  return {
    wageType: p.wageType, baseWage: p.baseWage, scheduledMinutes, actualMinutes,
    breakMinutes: p.breakMinutes, workMinutes, overtimeMinutes, earlyArrivalMinutes,
    nightMinutes, baseAmount, overtimeAmount, earlyArrivalAmount, nightAmount,
    additionalAmount: p.additionalAmount, totalAmount,
    nightAllowanceApplied: p.nightAllowanceApplied,
    appliedMinimumWage: p.minimumWage, appliedSupplementWage,
    taxDeductionType: "none", nationalPensionDeduction: 0, healthInsuranceDeduction: 0,
    ltcInsuranceDeduction: 0, employmentInsuranceDeduction: 0, incomeTaxDeduction: 0,
    retroactiveDeduction: 0, netWage: totalAmount,
  };
}

function srvApplyFreelancer33(base: SrvWageResult, r: SrvInsuranceRates): SrvWageResult {
  const g = Math.max(0, base.totalAmount);
  const inc = Math.round(g * r.businessIncomeRate / 100);
  const loc = Math.round(inc * r.localIncomeTaxRate / 100);
  return {...base, taxDeductionType: "freelancer_3_3", incomeTaxDeduction: inc + loc, netWage: g - inc - loc};
}

function srvApplyDailyWorker(base: SrvWageResult, r: SrvInsuranceRates): SrvWageResult {
  const g = Math.max(0, base.totalAmount);
  const tx = Math.max(0, g - r.dailyWageExemption);
  const inc = tx > 0 ? Math.round(tx * r.dailyWorkerTaxRate / 100) : 0;
  const loc = inc > 0 ? Math.round(inc * r.localIncomeTaxRate / 100) : 0;
  const emp = Math.round(g * r.employmentInsuranceRate / 100);
  return {...base, taxDeductionType: "daily_worker", employmentInsuranceDeduction: emp,
    incomeTaxDeduction: inc + loc, netWage: g - emp - inc - loc};
}

function srvApplyEmpIncomeTax(base: SrvWageResult, r: SrvInsuranceRates): SrvWageResult {
  const g = Math.max(0, base.totalAmount);
  const emp = Math.round(g * r.employmentInsuranceRate / 100);
  const tx = Math.max(0, g - r.dailyWageExemption);
  const inc = tx > 0 ? Math.round(tx * r.dailyWorkerTaxRate / 100) : 0;
  const loc = inc > 0 ? Math.round(inc * r.localIncomeTaxRate / 100) : 0;
  return {...base, taxDeductionType: "daily_auto_8", employmentInsuranceDeduction: emp,
    incomeTaxDeduction: inc + loc, netWage: g - emp - inc - loc};
}

function srvApplyFourInsurance(base: SrvWageResult, r: SrvInsuranceRates, taxType = "four_insurance_fixed"): SrvWageResult {
  const g = Math.max(0, base.totalAmount);
  const pen = Math.round(g * r.nationalPensionRate / 100);
  const hlt = Math.round(g * r.healthInsuranceRate / 100);
  const ltc = Math.round(hlt * r.ltcInsuranceRate / 100);
  const emp = Math.round(g * r.employmentInsuranceRate / 100);
  return {...base, taxDeductionType: taxType, nationalPensionDeduction: pen,
    healthInsuranceDeduction: hlt, ltcInsuranceDeduction: ltc,
    employmentInsuranceDeduction: emp, netWage: g - pen - hlt - ltc - emp};
}

function srvApplyDeduction(base: SrvWageResult, taxType: string, r: SrvInsuranceRates): SrvWageResult {
  switch (taxType) {
    case "none": return {...base, taxDeductionType: "none", netWage: Math.max(0, base.totalAmount)};
    case "freelancer_3_3": return srvApplyFreelancer33(base, r);
    case "daily_worker": return srvApplyDailyWorker(base, r);
    case "daily_auto_8": return srvApplyEmpIncomeTax(base, r);
    case "four_insurance_fixed": return srvApplyFourInsurance(base, r);
    default: return {...base, taxDeductionType: "none", netWage: Math.max(0, base.totalAmount)};
  }
}

function srvApplyDay8Retroactive(base: SrvWageResult, prevGross: number, r: SrvInsuranceRates): SrvWageResult {
  const g8 = Math.max(0, base.totalAmount);
  const prevPen = Math.round(prevGross * r.nationalPensionRate / 100);
  const prevHlt = Math.round(prevGross * r.healthInsuranceRate / 100);
  const prevLtc = Math.round(prevHlt * r.ltcInsuranceRate / 100);
  const retro = prevPen + prevHlt + prevLtc;
  const pen8 = Math.round(g8 * r.nationalPensionRate / 100);
  const hlt8 = Math.round(g8 * r.healthInsuranceRate / 100);
  const ltc8 = Math.round(hlt8 * r.ltcInsuranceRate / 100);
  const emp8 = Math.round(g8 * r.employmentInsuranceRate / 100);
  const tx8 = Math.max(0, g8 - r.dailyWageExemption);
  const inc8 = tx8 > 0 ? Math.round(tx8 * r.dailyWorkerTaxRate / 100) : 0;
  const loc8 = inc8 > 0 ? Math.round(inc8 * r.localIncomeTaxRate / 100) : 0;
  return {
    ...base, taxDeductionType: "daily_auto_8",
    nationalPensionDeduction: pen8, healthInsuranceDeduction: hlt8,
    ltcInsuranceDeduction: ltc8, employmentInsuranceDeduction: emp8,
    incomeTaxDeduction: inc8 + loc8, retroactiveDeduction: retro,
    netWage: g8 - retro - pen8 - hlt8 - ltc8 - emp8 - inc8 - loc8,
  };
}

// [M-4] 트랜잭션 내 조회 버전 — TOCTOU 방어용
async function srvGetMonthlyWorkDaysTx(
  tx: FirebaseFirestore.Transaction, userId: string, biz: string, ym: string, excl: string
): Promise<number> {
  const base = db.collection("attendance")
    .where("userId", "==", userId).where("businessId", "==", biz).where("yearMonth", "==", ym);
  const snaps = await Promise.all(
    ["calculated", "confirmed", "transferred"].map((ws) => tx.get(base.where("wageStatus", "==", ws)))
  );
  const dates = new Set<string>();
  for (const snap of snaps) {
    for (const doc of snap.docs) {
      if (doc.id === excl) continue;
      const ts = doc.data().workDate;
      if (ts && ts.toDate) dates.add((ts.toDate() as Date).toISOString().substring(0, 10));
    }
  }
  return dates.size;
}

async function srvGetPrevGrossTotalTx(
  tx: FirebaseFirestore.Transaction, userId: string, biz: string, ym: string, excl: string
): Promise<number> {
  const base = db.collection("attendance")
    .where("userId", "==", userId).where("businessId", "==", biz).where("yearMonth", "==", ym);
  const snaps = await Promise.all(
    ["calculated", "confirmed", "transferred"].map((ws) => tx.get(base.where("wageStatus", "==", ws)))
  );
  let total = 0;
  for (const snap of snaps) {
    for (const doc of snap.docs) {
      if (doc.id === excl) continue;
      const wd = doc.data().wageDetail;
      if (wd && typeof wd.totalAmount === "number") total += wd.totalAmount;
    }
  }
  return total;
}

// ── callableCalculateAndConfirmWage ──────────────────────────
// [Phase 2] 급여 계산 + 확정 (pending → calculated) 서버 사이드 처리
// [DESIGN-F-M1 재탐색 금지] actualStart/actualEnd ↔ checkIn/checkOut 교차검증 의도적 미구현.
//   이유: 반올림 처리·야간교대·기기 오류 등으로 관리자가 실제 체크인 시간과 크게 다른 값을 입력할
//   정당한 이유가 존재함. 관리자 재량 허용이 설계 결정. HH:MM 포맷 검증만 유지.
// 파라미터를 서버에서 재계산 → 8일 소급 자동 처리 → 원자적 저장
// Input:  { attendanceId, wageType, baseWage, workDate, scheduledStart, scheduledEnd,
//           actualStart, actualEnd, breakMinutes, scheduledBreakMinutes?,
//           nightAllowanceApplied, nightIncluded, additionalAmount?, baseHourlyWage?,
//           taxDeductionType, yearMonth, payScheduleType?, payScheduleDay? }
// Output: { success: true, effectiveNetWage: number }
// ═══════════════════════════════════════════════════════════
export const callableCalculateAndConfirmWage = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;

    const d = request.data as {
      attendanceId: string; wageType: string; baseWage: number; workDate: string;
      scheduledStart: string; scheduledEnd: string; actualStart: string; actualEnd: string;
      breakMinutes: number; scheduledBreakMinutes?: number;
      nightAllowanceApplied: boolean; nightIncluded: boolean;
      additionalAmount?: number; baseHourlyWage?: number;
      taxDeductionType: string; yearMonth: string;
      payScheduleType?: string; payScheduleDay?: number;
    };

    if (!d.attendanceId || !d.wageType || !d.workDate ||
        !d.scheduledStart || !d.scheduledEnd || !d.actualStart || !d.actualEnd ||
        !d.taxDeductionType || !d.yearMonth) {
      throw new HttpsError("invalid-argument", "필수 파라미터가 누락되었습니다.");
    }
    if (typeof d.baseWage !== "number" || d.baseWage <= 0 || d.baseWage > 10_000_000) {
      throw new HttpsError("invalid-argument", "baseWage는 1 이상 10,000,000 이하여야 합니다.");
    }
    // SEC-16: 입력값 형식 검증
    if (d.wageType !== "hourly" && d.wageType !== "daily") {
      throw new HttpsError("invalid-argument", "wageType은 'hourly' 또는 'daily'여야 합니다.");
    }
    const VALID_TAX_TYPES = ["none", "freelancer_3_3", "daily_worker", "daily_auto_8", "four_insurance_fixed"];
    if (!VALID_TAX_TYPES.includes(d.taxDeductionType)) {
      throw new HttpsError("invalid-argument", "유효하지 않은 taxDeductionType입니다.");
    }
    if (!/^\d{4}-(?:0[1-9]|1[0-2])-(?:0[1-9]|[12]\d|3[01])$/.test(d.workDate)) {
      throw new HttpsError("invalid-argument", "workDate는 YYYY-MM-DD 형식이어야 합니다.");
    }
    if (!/^\d{4}(?:0[1-9]|1[0-2])$/.test(d.yearMonth)) {
      throw new HttpsError("invalid-argument", "yearMonth는 YYYYMM 형식이어야 합니다.");
    }
    const _timeRegex = /^(?:[01]\d|2[0-3]):[0-5]\d$/;
    if (!_timeRegex.test(d.scheduledStart) || !_timeRegex.test(d.scheduledEnd) ||
        !_timeRegex.test(d.actualStart) || !_timeRegex.test(d.actualEnd)) {
      throw new HttpsError("invalid-argument", "시간은 HH:MM 형식(24시간)이어야 합니다.");
    }
    if (d.baseHourlyWage !== undefined &&
        (typeof d.baseHourlyWage !== "number" || d.baseHourlyWage <= 0 || d.baseHourlyWage > 10_000_000)) {
      throw new HttpsError("invalid-argument", "baseHourlyWage는 1 이상 10,000,000 이하여야 합니다.");
    }
    // SEC-39: 음수 값 차단 — additionalAmount 음수 시 totalAmount 음수 저장 가능
    if (typeof d.additionalAmount === "number" && d.additionalAmount < 0) {
      throw new HttpsError("invalid-argument", "additionalAmount는 0 이상이어야 합니다.");
    }
    if (typeof d.breakMinutes === "number" && (d.breakMinutes < 0 || d.breakMinutes > 1440)) {
      throw new HttpsError("invalid-argument", "breakMinutes는 0 이상 1440 이하여야 합니다.");
    }
    if (typeof d.scheduledBreakMinutes === "number" && (d.scheduledBreakMinutes < 0 || d.scheduledBreakMinutes > 1440)) {
      throw new HttpsError("invalid-argument", "scheduledBreakMinutes는 0 이상 1440 이하여야 합니다.");
    }

    // 1. attendance 조회 (businessId, userId 확보)
    const attRef2 = db.collection("attendance").doc(d.attendanceId);
    const attSnap2 = await attRef2.get();
    if (!attSnap2.exists) throw new HttpsError("not-found", "출근 기록을 찾을 수 없습니다.");
    const attData2 = attSnap2.data()!;
    const businessId2 = attData2.businessId as string;
    const userId2 = attData2.userId as string;
    // 2. 권한 확인
    const callerSnap2 = await db.collection("users").doc(callerUid).get();
    const callerData2 = callerSnap2.data() ?? {};
    const callerRole2 = (callerData2.role as string) ?? "";
    const callerSubAdminOf2 = (callerData2.subAdminOf as string) ?? "";
    let authorized2 = callerRole2 === "SUPER_ADMIN";
    if (!authorized2 && callerRole2 === "BUSINESS_ADMIN") {
      const bizSnap2 = await db.collection("businesses").doc(businessId2).get();
      const bizSnap2Data = bizSnap2.data();
      const adminIds2 = (bizSnap2Data?.adminIds as string[]) ?? [];
      const ownerId2 = bizSnap2Data?.ownerId as string | undefined;
      authorized2 = adminIds2.includes(callerUid) || ownerId2 === callerUid;
    } else if (!authorized2 && callerRole2 === "USER" && callerSubAdminOf2) {
      // SEC-26: SubAdmin은 role="USER" + subAdminOf 필드로 구별
      authorized2 = callerSubAdminOf2 === businessId2;
    }
    if (!authorized2) throw new HttpsError("permission-denied", "해당 사업장 관리 권한이 필요합니다.");

    // 3. 최저시급 + 보험료율 조회
    const cfgSnap = await db.collection("settings").doc("wage_config").get();
    const cfg = cfgSnap.data() ?? {};
    const fsMinWages: Record<number, number> = {};
    if (cfg.minimumWages && typeof cfg.minimumWages === "object") {
      for (const [k, v] of Object.entries(cfg.minimumWages as Record<string, unknown>)) {
        const yr = parseInt(k, 10);
        if (!isNaN(yr) && typeof v === "number") fsMinWages[yr] = v;
      }
    }
    const fsRates: Record<number, Partial<SrvInsuranceRates>> = {};
    if (cfg.insuranceRates && typeof cfg.insuranceRates === "object") {
      for (const [k, v] of Object.entries(cfg.insuranceRates as Record<string, unknown>)) {
        const yr = parseInt(k, 10);
        if (!isNaN(yr) && v && typeof v === "object") fsRates[yr] = v as Partial<SrvInsuranceRates>;
      }
    }

    // 4. 계산
    const workYear2 = parseInt(d.workDate.substring(0, 4), 10);
    const minimumWage2 = srvGetMinimumWage(workYear2, fsMinWages);
    // [WAG-02] 시급제: baseWage가 해당 연도 법적 최저임금 미만이면 차단
    if (d.wageType === "hourly" && minimumWage2 > 0 && d.baseWage < minimumWage2) {
      throw new HttpsError("invalid-argument",
        `시급(${d.baseWage}원)이 ${workYear2}년 최저임금(${minimumWage2}원) 미만입니다.`);
    }
    const rates2 = srvGetRates(workYear2, fsRates);
    const breakMins = typeof d.breakMinutes === "number" ? d.breakMinutes : 0;
    const schedBreakMins = typeof d.scheduledBreakMinutes === "number" ? d.scheduledBreakMinutes : breakMins;

    const base2 = srvWageCalculate({
      wageType: d.wageType, baseWage: d.baseWage, minimumWage: minimumWage2,
      scheduledStart: d.scheduledStart, scheduledEnd: d.scheduledEnd,
      actualStart: d.actualStart, actualEnd: d.actualEnd,
      breakMinutes: breakMins, scheduledBreakMinutes: schedBreakMins,
      nightAllowanceApplied: d.nightAllowanceApplied ?? true,
      nightIncluded: d.nightIncluded ?? false,
      additionalAmount: typeof d.additionalAmount === "number" ? d.additionalAmount : 0,
      baseHourlyWage: typeof d.baseHourlyWage === "number" ? d.baseHourlyWage : undefined,
    });

    // 5. 공제 계산 (non-daily_auto_8 케이스는 트랜잭션 외부에서 미리 계산)
    let wageResult2: SrvWageResult = d.taxDeductionType !== "daily_auto_8"
      ? srvApplyDeduction(base2, d.taxDeductionType, rates2)
      : srvApplyEmpIncomeTax(base2, rates2); // [M-4] daily_auto_8은 트랜잭션 내부에서 재계산
    let effectiveNetWage2 = 0;

    // 6. 트랜잭션: 상태 재확인 + [M-4] daily_auto_8 TOCTOU 방어 + 원자적 저장
    await db.runTransaction(async (tx) => {
      const latestSnap = await tx.get(attRef2);
      const cur = (latestSnap.data()?.wageStatus as string) ?? "pending";
      if (cur !== "pending") throw new HttpsError("failed-precondition", `이미 처리된 급여입니다 (${cur})`);

      // [M-4] daily_auto_8: prevDays/prevGross를 트랜잭션 내부에서 조회 — 동시 확정 경쟁 차단
      if (d.taxDeductionType === "daily_auto_8") {
        const prevDays = await srvGetMonthlyWorkDaysTx(tx, userId2, businessId2, d.yearMonth, d.attendanceId);
        if (prevDays + 1 === 8) {
          const prevGross = await srvGetPrevGrossTotalTx(tx, userId2, businessId2, d.yearMonth, d.attendanceId);
          wageResult2 = srvApplyDay8Retroactive(base2, prevGross, rates2);
        } else if (prevDays + 1 > 8) {
          wageResult2 = srvApplyFourInsurance(base2, rates2, "daily_auto_8");
        } else {
          wageResult2 = srvApplyEmpIncomeTax(base2, rates2);
        }
      }
      effectiveNetWage2 = Math.max(0, wageResult2.netWage);

      const wd: Record<string, unknown> = {
        wageType: wageResult2.wageType, baseWage: wageResult2.baseWage,
        scheduledMinutes: wageResult2.scheduledMinutes, actualMinutes: wageResult2.actualMinutes,
        breakMinutes: wageResult2.breakMinutes, workMinutes: wageResult2.workMinutes,
        overtimeMinutes: wageResult2.overtimeMinutes, nightMinutes: wageResult2.nightMinutes,
        baseAmount: wageResult2.baseAmount, overtimeAmount: wageResult2.overtimeAmount,
        nightAmount: wageResult2.nightAmount, additionalAmount: wageResult2.additionalAmount,
        // [L-3] deductionAmount 집계 수정 — 하드코딩 0 → 실제 공제 합계
        deductionAmount: wageResult2.nationalPensionDeduction + wageResult2.healthInsuranceDeduction +
          wageResult2.ltcInsuranceDeduction + wageResult2.employmentInsuranceDeduction +
          wageResult2.incomeTaxDeduction + wageResult2.retroactiveDeduction,
        weeklyHolidayAmount: 0,
        totalAmount: wageResult2.totalAmount,
        nightAllowanceApplied: wageResult2.nightAllowanceApplied,
        appliedMinimumWage: wageResult2.appliedMinimumWage,
        taxDeductionType: wageResult2.taxDeductionType,
        netWage: wageResult2.netWage,
        calculatedAt: admin.firestore.FieldValue.serverTimestamp(),
        calculatedBy: callerUid,
      };
      if (wageResult2.earlyArrivalMinutes) wd.earlyArrivalMinutes = wageResult2.earlyArrivalMinutes;
      wd.earlyArrivalAmount = wageResult2.earlyArrivalAmount;
      if (wageResult2.appliedSupplementWage) wd.appliedSupplementWage = wageResult2.appliedSupplementWage;
      if (wageResult2.employmentInsuranceDeduction) wd.employmentInsuranceDeduction = wageResult2.employmentInsuranceDeduction;
      if (wageResult2.nationalPensionDeduction) wd.nationalPensionDeduction = wageResult2.nationalPensionDeduction;
      if (wageResult2.healthInsuranceDeduction) wd.healthInsuranceDeduction = wageResult2.healthInsuranceDeduction;
      if (wageResult2.ltcInsuranceDeduction) wd.ltcInsuranceDeduction = wageResult2.ltcInsuranceDeduction;
      if (wageResult2.incomeTaxDeduction) wd.incomeTaxDeduction = wageResult2.incomeTaxDeduction;
      if (wageResult2.retroactiveDeduction) wd.retroactiveDeduction = wageResult2.retroactiveDeduction;
      if (d.payScheduleType != null) wd.payScheduleType = d.payScheduleType;
      if (d.payScheduleDay != null) wd.payScheduleDay = d.payScheduleDay;

      // [S3-FIX] attendance.yearMonth 필드는 YYYY-MM 형식으로 통일. d.yearMonth는 YYYYMM(입력 검증)이므로 변환.
      const yearMonthForDoc = `${d.yearMonth.substring(0, 4)}-${d.yearMonth.substring(4, 6)}`;
      tx.update(attRef2, {
        wageStatus: "calculated",
        finalWage: effectiveNetWage2,
        wageDetail: wd,
        yearMonth: yearMonthForDoc,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    return {success: true, effectiveNetWage: effectiveNetWage2};
  },
);

// ═══════════════════════════════════════════════════════════
// 🔒 공통 권한 헬퍼 — SUPER_ADMIN / adminIds / ownerId / subAdminOf
// ═══════════════════════════════════════════════════════════

async function assertBizAdmin(callerUid: string, businessId: string): Promise<void> {
  const [callerSnap, bizSnap] = await Promise.all([
    db.collection("users").doc(callerUid).get(),
    db.collection("businesses").doc(businessId).get(),
  ]);
  const isSuperAdmin = (callerSnap.data()?.role as string | undefined) === "SUPER_ADMIN";
  if (isSuperAdmin) return;
  if (!bizSnap.exists) throw new HttpsError("not-found", "사업장을 찾을 수 없습니다.");
  const adminIds = (bizSnap.data()?.adminIds as string[] | undefined) ?? [];
  const ownerId = bizSnap.data()?.ownerId as string | undefined;
  const subAdminOf = callerSnap.data()?.subAdminOf as string | undefined;
  if (!adminIds.includes(callerUid) && ownerId !== callerUid && subAdminOf !== businessId) {
    throw new HttpsError("permission-denied", "해당 사업장에 대한 권한이 없습니다.");
  }
}

// ─── 1. callableGetApplicationsByBiz ────────────────────────────────────────
export const callableGetApplicationsByBiz = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;

    const {
      businessId, toId, slotId, status, type, uid,
      resignStatus, toTitle,
      workDateGteMs, workDateLtMs, workDateEqMs,
      workEndDateGteMs, workEndDateLtMs,
      orderByAppliedAtDesc,
      limit: rawLimit,
    } = (request.data ?? {}) as {
      businessId?: string; toId?: string; slotId?: string;
      status?: string; type?: string; uid?: string;
      resignStatus?: string; toTitle?: string;
      workDateGteMs?: number; workDateLtMs?: number; workDateEqMs?: number;
      workEndDateGteMs?: number; workEndDateLtMs?: number;
      orderByAppliedAtDesc?: boolean;
      limit?: number;
    };

    if (!businessId || typeof businessId !== "string" || businessId.trim().length === 0) {
      throw new HttpsError("invalid-argument", "businessId가 필요합니다.");
    }

    await assertBizAdmin(callerUid, businessId);

    const cap = Math.min(
      typeof rawLimit === "number" && rawLimit > 0 ? rawLimit : 500,
      2000
    );

    let q: admin.firestore.Query = db
      .collection("applications")
      .where("businessId", "==", businessId);

    if (toId) q = q.where("toId", "==", toId);
    if (slotId) q = q.where("slotId", "==", slotId);
    if (status) q = q.where("status", "==", status);
    if (type) q = q.where("type", "==", type);
    if (uid) q = q.where("uid", "==", uid);
    if (resignStatus) q = q.where("resignStatus", "==", resignStatus);
    if (toTitle) q = q.where("toTitle", "==", toTitle);
    // workDate: Timestamp 기반 비교 (문자열 비교 버그 수정 2026-07-13)
    if (workDateEqMs && Number.isFinite(workDateEqMs))
      q = q.where("workDate", "==", admin.firestore.Timestamp.fromMillis(workDateEqMs));
    else {
      if (workDateGteMs && Number.isFinite(workDateGteMs))
        q = q.where("workDate", ">=", admin.firestore.Timestamp.fromMillis(workDateGteMs));
      if (workDateLtMs && Number.isFinite(workDateLtMs))
        q = q.where("workDate", "<", admin.firestore.Timestamp.fromMillis(workDateLtMs));
    }
    if (workEndDateGteMs && Number.isFinite(workEndDateGteMs))
      q = q.where("workEndDate", ">=", admin.firestore.Timestamp.fromMillis(workEndDateGteMs));
    if (workEndDateLtMs && Number.isFinite(workEndDateLtMs))
      q = q.where("workEndDate", "<", admin.firestore.Timestamp.fromMillis(workEndDateLtMs));
    if (orderByAppliedAtDesc === true)
      q = q.orderBy("appliedAt", "desc");

    q = q.limit(cap);
    const snap = await q.get();

    return {
      applications: snap.docs.map((d) => ({id: d.id, ...serializeFirestoreData(d.data())})),
    };
  }
);

// ─── 2. callableGetTOsByBiz ──────────────────────────────────────────────────
export const callableGetTOsByBiz = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;

    const {
      businessId, status, statuses,
      createdAtGteMs, orderByCreatedAtDesc,
      limit: rawLimit,
    } = (request.data ?? {}) as {
      businessId?: string; status?: string; statuses?: string[];
      createdAtGteMs?: number; orderByCreatedAtDesc?: boolean;
      limit?: number;
    };

    if (!businessId || typeof businessId !== "string" || businessId.trim().length === 0) {
      throw new HttpsError("invalid-argument", "businessId가 필요합니다.");
    }
    if (statuses !== undefined && (!Array.isArray(statuses) || statuses.length === 0 || statuses.length > 10)) {
      throw new HttpsError("invalid-argument", "statuses는 1~10개 사이여야 합니다.");
    }

    await assertBizAdmin(callerUid, businessId);

    const cap = Math.min(
      typeof rawLimit === "number" && rawLimit > 0 ? rawLimit : 200,
      1000
    );

    let q: admin.firestore.Query = db
      .collection("tos")
      .where("businessId", "==", businessId);

    if (status) {
      q = q.where("status", "==", status);
    } else if (statuses && statuses.length > 0) {
      q = q.where("status", "in", statuses);
    }
    if (createdAtGteMs && Number.isFinite(createdAtGteMs))
      q = q.where("createdAt", ">=", admin.firestore.Timestamp.fromMillis(createdAtGteMs));
    if (orderByCreatedAtDesc === true)
      q = q.orderBy("createdAt", "desc");

    q = q.limit(cap);
    const snap = await q.get();

    return {
      tos: snap.docs.map((d) => ({id: d.id, ...serializeFirestoreData(d.data())})),
    };
  }
);

// ─── 3. callableGetContractsByBiz ────────────────────────────────────────────
export const callableGetContractsByBiz = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;

    const {
      businessId, applicationId, applicationIds, terminationStatus,
      status, toId, workDetailId, workerId, isLongTerm, limit: rawLimit,
      startAfterId,
    } = (request.data ?? {}) as {
      businessId?: string; applicationId?: string; applicationIds?: string[];
      terminationStatus?: string; status?: string; toId?: string;
      workDetailId?: string; workerId?: string; isLongTerm?: boolean; limit?: number;
      startAfterId?: string;
    };

    if (!businessId || typeof businessId !== "string" || businessId.trim().length === 0) {
      throw new HttpsError("invalid-argument", "businessId가 필요합니다.");
    }
    if (applicationIds !== undefined && (!Array.isArray(applicationIds) || applicationIds.length === 0)) {
      throw new HttpsError("invalid-argument", "applicationIds가 비어있습니다.");
    }
    // [CONTRACT-DOS-FIX] applicationIds 배열 50개 초과 시 거부
    //   초과 시 병렬 Firestore 쿼리 폭발 → CF 메모리/타임아웃 소진 및 과금 급증
    if (Array.isArray(applicationIds) && applicationIds.length > 50) {
      throw new HttpsError("invalid-argument", "applicationIds는 최대 50개까지 허용됩니다.");
    }

    await assertBizAdmin(callerUid, businessId);

    const cap = Math.min(
      typeof rawLimit === "number" && rawLimit > 0 ? rawLimit : 100,
      1000
    );

    const buildBase = (): admin.firestore.Query => {
      let q: admin.firestore.Query = db
        .collection("employment_contracts")
        .where("businessId", "==", businessId);
      if (terminationStatus) q = q.where("terminationStatus", "==", terminationStatus);
      if (status) q = q.where("status", "==", status);
      if (toId) q = q.where("toId", "==", toId);
      if (workDetailId) q = q.where("workDetailId", "==", workDetailId);
      if (workerId) q = q.where("workerId", "==", workerId);
      if (isLongTerm !== undefined) q = q.where("isLongTerm", "==", isLongTerm);
      return q;
    };

    let docs: admin.firestore.QueryDocumentSnapshot[];

    if (applicationIds && applicationIds.length > 0) {
      const snaps = await Promise.all(
        applicationIds.map((aid) =>
          buildBase().where("applicationId", "==", aid).limit(cap).get()
        )
      );
      const seen = new Set<string>();
      docs = [];
      for (const snap of snaps) {
        for (const d of snap.docs) {
          if (!seen.has(d.id)) {
            seen.add(d.id);
            docs.push(d);
          }
        }
      }
    } else {
      let q = buildBase();
      if (applicationId) q = q.where("applicationId", "==", applicationId);
      if (startAfterId) {
        const cursorSnap = await db.collection("employment_contracts").doc(startAfterId).get();
        // [CONTRACT-CURSOR-FIX] 커서 문서가 요청 사업장 소속인지 검증 — 타 사업장 커서로 페이지네이션 오동작 차단
        if (cursorSnap.exists && cursorSnap.data()?.businessId === businessId) {
          q = q.startAfter(cursorSnap);
        }
      }
      q = q.limit(cap);
      const snap = await q.get();
      docs = snap.docs;
    }

    return {
      contracts: docs.map((d) => ({id: d.id, ...serializeFirestoreData(d.data())})),
    };
  }
);

// ─── 4. callableGetMonthlyReviewsByBiz ───────────────────────────────────────
export const callableGetMonthlyReviewsByBiz = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;

    const {
      businessId, reviewType, isPublished, reviewYear, reviewMonth,
      targetUserId, limit: rawLimit, startAfterId,
    } = (request.data ?? {}) as {
      businessId?: string; reviewType?: string; isPublished?: boolean;
      reviewYear?: number; reviewMonth?: number; targetUserId?: string;
      limit?: number; startAfterId?: string;
    };

    if (!businessId || typeof businessId !== "string" || businessId.trim().length === 0) {
      throw new HttpsError("invalid-argument", "businessId가 필요합니다.");
    }

    await assertBizAdmin(callerUid, businessId);

    const cap = Math.min(
      typeof rawLimit === "number" && rawLimit > 0 ? rawLimit : 100,
      1000
    );

    let q: admin.firestore.Query = db
      .collection("monthly_reviews")
      .where("businessId", "==", businessId);

    if (reviewType) q = q.where("reviewType", "==", reviewType);
    if (isPublished !== undefined) q = q.where("isPublished", "==", isPublished);
    if (reviewYear !== undefined) q = q.where("reviewYear", "==", reviewYear);
    if (reviewMonth !== undefined) q = q.where("reviewMonth", "==", reviewMonth);
    if (targetUserId) q = q.where("targetUserId", "==", targetUserId);

    if (startAfterId) {
      const cursorSnap = await db.collection("monthly_reviews").doc(startAfterId).get();
      if (cursorSnap.exists) q = q.startAfter(cursorSnap);
    }

    q = q.limit(cap);
    const snap = await q.get();

    return {
      reviews: snap.docs.map((d) => ({id: d.id, ...serializeFirestoreData(d.data())})),
    };
  }
);

// ─── 5. callableGetReviewRequestsByBiz ───────────────────────────────────────
export const callableGetReviewRequestsByBiz = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;

    const {
      businessId, adminStatus, isPublished, limit: rawLimit,
    } = (request.data ?? {}) as {
      businessId?: string; adminStatus?: string; isPublished?: boolean; limit?: number;
    };

    if (!businessId || typeof businessId !== "string" || businessId.trim().length === 0) {
      throw new HttpsError("invalid-argument", "businessId가 필요합니다.");
    }

    await assertBizAdmin(callerUid, businessId);

    const cap = Math.min(
      typeof rawLimit === "number" && rawLimit > 0 ? rawLimit : 200,
      1000
    );

    let q: admin.firestore.Query = db
      .collection("review_requests")
      .where("businessId", "==", businessId);

    if (adminStatus) q = q.where("adminStatus", "==", adminStatus);
    if (isPublished !== undefined) q = q.where("isPublished", "==", isPublished);

    q = q.limit(cap);
    const snap = await q.get();

    return {
      reviewRequests: snap.docs.map((d) => ({id: d.id, ...serializeFirestoreData(d.data())})),
    };
  }
);

// ─── 6. callableRequestTermination ───────────────────────────────────────────
export const callableRequestTermination = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;
    const data = request.data as Record<string, unknown>;
    const applicationId = data.applicationId as string | undefined;
    if (!applicationId || typeof applicationId !== "string") {
      throw new HttpsError("invalid-argument", "applicationId가 필요합니다.");
    }
    const reason = (data.reason as string | undefined) ?? null;
    // [F1] reason 길이 제한 — 과도한 텍스트 저장/알림 본문 초과 방지
    if (reason && reason.length > 500) throw new HttpsError("invalid-argument", "reason은 최대 500자까지 입력 가능합니다.");

    const appRef = db.collection("applications").doc(applicationId);
    const appSnap = await appRef.get();
    if (!appSnap.exists) throw new HttpsError("not-found", "지원서를 찾을 수 없습니다.");
    const appData = appSnap.data()!;
    // [SEC] appData에서만 businessId/uid 취득 — 클라이언트 override 차단 (타 사업장 해지 강제 방지)
    const bId = (appData.businessId as string | undefined) ?? "";
    const workerUid = (appData.uid as string | undefined) ?? "";

    if (!bId) throw new HttpsError("invalid-argument", "businessId가 필요합니다.");

    let businessName = "";
    {
      const [bizSnap, callerSnap] = await Promise.all([
        db.collection("businesses").doc(bId).get(),
        db.collection("users").doc(callerUid).get(),
      ]);
      if (!bizSnap.exists) throw new HttpsError("not-found", "사업장을 찾을 수 없습니다.");
      businessName = (bizSnap.data()?.name as string | undefined) ?? "";
      const isSuperAdmin = (callerSnap.data()?.role as string | undefined) === "SUPER_ADMIN";
      if (!isSuperAdmin) {
        const ownerId = bizSnap.data()?.ownerId as string | undefined;
        const adminIds = (bizSnap.data()?.adminIds as string[] | undefined) ?? [];
        const callerSubAdminOf = callerSnap.data()?.subAdminOf as string | undefined;
        const isAdmin =
          ownerId === callerUid ||
          adminIds.includes(callerUid) ||
          callerSubAdminOf === bId;
        if (!isAdmin) throw new HttpsError("permission-denied", "관리자 권한이 필요합니다.");
      }
    }

    let terminationDate: admin.firestore.Timestamp;
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(appRef);
      if (!snap.exists) throw new HttpsError("not-found", "지원서 없음");
      // [TERM-GUARD-FIX] null/"REJECTED" 외 상태에서 재요청 차단
      //   APPROVED/AUTO_APPROVED에서 재요청 허용 시 callableApproveTermination 재실행으로
      //   totalConfirmed 이중 감소 + revokeRefreshTokens 중복 호출 가능
      const currentTermStatus = snap.data()?.terminationStatus as string | null | undefined;
      if (currentTermStatus != null && currentTermStatus !== "REJECTED") {
        throw new HttpsError("failed-precondition", `계약해지 재요청 불가 — 현재 상태: ${currentTermStatus}`);
      }
      const workEndDate = snap.data()?.workEndDate as admin.firestore.Timestamp | undefined;
      if (workEndDate) {
        terminationDate = workEndDate;
      } else {
        const d = new Date();
        d.setDate(d.getDate() + 30);
        terminationDate = admin.firestore.Timestamp.fromDate(d);
      }
      tx.update(appRef, {
        terminationStatus: "PENDING",
        terminationRequestedAt: admin.firestore.FieldValue.serverTimestamp(),
        terminationReason: reason,
        terminationRequestedByUid: callerUid,
        terminationEffectiveDate: terminationDate,
      });
    });

    if (bId) {
      const CONTRACT_ACTIVE_STATUSES = ["pending_employer", "pending_worker", "active"];
      const cq = await db
        .collection("employment_contracts")
        .where("applicationId", "==", applicationId)
        .where("businessId", "==", bId)
        .limit(5)
        .get();
      const phase1 = cq.docs.filter((d) =>
        CONTRACT_ACTIVE_STATUSES.includes(d.data().status as string)
      );
      if (phase1.length > 0) {
        const batch = db.batch();
        for (const d of phase1) batch.update(d.ref, {terminationStatus: "PENDING"});
        await batch.commit();
      } else {
        const cq2 = await db
          .collection("employment_contracts")
          .where("applicationIds", "array-contains", applicationId)
          .where("businessId", "==", bId)
          .limit(5)
          .get();
        const phase2 = cq2.docs.filter((d) =>
          CONTRACT_ACTIVE_STATUSES.includes(d.data().status as string)
        );
        if (phase2.length > 0) {
          const batch = db.batch();
          for (const d of phase2) batch.update(d.ref, {terminationStatus: "PENDING"});
          await batch.commit();
        }
      }
    }

    if (workerUid) {
      const td = terminationDate!.toDate();
      const tdStr = `${td.getMonth() + 1}/${td.getDate()}`;
      await db.collection("users").doc(workerUid).collection("notifications").add({
        type: "terminationRequested",
        userId: workerUid,
        title: "계약해지 요청",
        body: `${businessName}에서 계약해지를 요청했습니다.\n해지 예정일: ${tdStr}`,
        data: {applicationId, businessId: bId, action: "terminationDetail"},
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    return {success: true};
  }
);

// ─── 7. callableCancelTermination ────────────────────────────────────────────
export const callableCancelTermination = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;
    const data = request.data as Record<string, unknown>;
    const applicationId = data.applicationId as string | undefined;
    if (!applicationId || typeof applicationId !== "string") {
      throw new HttpsError("invalid-argument", "applicationId가 필요합니다.");
    }

    // 트랜잭션 전 프리리드 — businessId 확보 후 권한 체크
    const appRef = db.collection("applications").doc(applicationId);
    const preSnap = await appRef.get();
    if (!preSnap.exists) throw new HttpsError("not-found", "지원서를 찾을 수 없습니다.");
    const bId = (preSnap.data()?.businessId as string | undefined) ?? "";
    if (!bId) throw new HttpsError("invalid-argument", "지원서에 businessId가 없습니다.");

    // 권한 체크 (트랜잭션 전)
    await assertBizAdmin(callerUid, bId);

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(appRef);
      if (!snap.exists) throw new HttpsError("not-found", "지원서를 찾을 수 없습니다.");
      if (snap.data()?.terminationStatus !== "PENDING") {
        throw new HttpsError(
          "failed-precondition",
          `취소 불가 — 현재 계약해지 상태: ${snap.data()?.terminationStatus}`
        );
      }
      tx.update(snap.ref, {
        terminationStatus: null,
        terminationRequestedAt: null,
        terminationReason: null,
        terminationRequestedByUid: null,
        terminationEffectiveDate: null,
      });
    });

    const cq = await db
      .collection("employment_contracts")
      .where("applicationId", "==", applicationId)
      .where("businessId", "==", bId)
      .where("terminationStatus", "==", "PENDING")
      .limit(5)
      .get();
    if (cq.docs.length > 0) {
      const batch = db.batch();
      for (const d of cq.docs) batch.update(d.ref, {terminationStatus: null});
      await batch.commit();
    } else {
      const cq2 = await db
        .collection("employment_contracts")
        .where("applicationIds", "array-contains", applicationId)
        .where("businessId", "==", bId)
        .where("terminationStatus", "==", "PENDING")
        .limit(5)
        .get();
      if (cq2.docs.length > 0) {
        const batch = db.batch();
        for (const d of cq2.docs) batch.update(d.ref, {terminationStatus: null});
        await batch.commit();
      }
    }

    return {success: true};
  }
);

// ─── 8. callableApproveTermination ───────────────────────────────────────────
export const callableApproveTermination = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;
    const {applicationId} = request.data as {applicationId: string};
    if (!applicationId) throw new HttpsError("invalid-argument", "applicationId 필수");

    const appRef = db.collection("applications").doc(applicationId);
    const preSnap = await appRef.get();
    if (!preSnap.exists) throw new HttpsError("not-found", "지원 정보를 찾을 수 없습니다.");
    const preData = preSnap.data()!;
    const businessId = preData.businessId as string;
    const workerUid = preData.uid as string;

    // 권한 확인: 근무자 본인(피해지 당사자) 또는 관리자
    const isWorker = callerUid === workerUid;
    if (!isWorker) {
      await assertBizAdmin(callerUid, businessId);
    }

    // 계약서 사전 쿼리 (트랜잭션 외부)
    const pendingContractStatuses = ["pending_employer", "pending_worker"];
    let contractRef: admin.firestore.DocumentReference | null = null;
    const cq1 = await db.collection("employment_contracts")
      .where("applicationId", "==", applicationId)
      .where("businessId", "==", businessId)
      .limit(5)
      .get();
    const cq1Match = cq1.docs.find((d) =>
      pendingContractStatuses.includes(d.data().status as string)
    );
    if (cq1Match) {
      contractRef = cq1Match.ref;
    } else {
      const cq2 = await db.collection("employment_contracts")
        .where("applicationIds", "array-contains", applicationId)
        .where("businessId", "==", businessId)
        .limit(5)
        .get();
      const cq2Match = cq2.docs.find((d) =>
        pendingContractStatuses.includes(d.data().status as string)
      );
      if (cq2Match) contractRef = cq2Match.ref;
    }

    type TerminationResolved = {
      toId: string | null;
      slotId: string | null;
      uid: string;
      businessName: string;
      terminationEffectiveDate: admin.firestore.Timestamp | null;
      terminationRequestedByUid: string | null;
      originalStatus: string;
    };
    let resolvedData: TerminationResolved | null = null;

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(appRef);
      if (!snap.exists) throw new HttpsError("not-found", "지원서 없음");
      const d = snap.data()!;
      if (d.terminationStatus !== "PENDING") {
        throw new HttpsError(
          "failed-precondition",
          `수락 불가 — 현재 계약해지 상태: ${d.terminationStatus}`
        );
      }
      const terminationEffectiveDate =
        (d.terminationEffectiveDate as admin.firestore.Timestamp | null) ?? null;
      resolvedData = {
        toId: (d.toId as string | null) ?? null,
        slotId: (d.slotId as string | null) ?? null,
        uid: d.uid as string,
        businessName: (d.businessName as string) ?? "",
        terminationEffectiveDate,
        terminationRequestedByUid:
          (d.terminationRequestedByUid as string | null) ?? null,
        originalStatus: d.status as string,
      };
      tx.update(appRef, {
        terminationStatus: "APPROVED",
        terminationRespondedAt: admin.firestore.FieldValue.serverTimestamp(),
        actualResignDate:
          terminationEffectiveDate ?? admin.firestore.FieldValue.serverTimestamp(),
        status: "CANCELED",
      });
      if (contractRef) {
        tx.update(contractRef, {
          status: "voided",
          contractVoidedAt: admin.firestore.FieldValue.serverTimestamp(),
          voidReason: "TERMINATION",
        });
      }
    });

    if (!resolvedData) throw new HttpsError("internal", "트랜잭션 결과 없음");
    const app = resolvedData as TerminationResolved;

    // TO totalConfirmed 감소
    if (app.toId && CONFIRMED_STATUSES.includes(app.originalStatus)) {
      const batch = db.batch();
      batch.update(db.collection("tos").doc(app.toId), {
        totalConfirmed: admin.firestore.FieldValue.increment(-1),
      });
      if (app.slotId) {
        batch.update(
          db.collection("tos").doc(app.toId).collection("slots").doc(app.slotId),
          {confirmedCount: admin.firestore.FieldValue.increment(-1)}
        );
      }
      await batch.commit();
    }

    // 퇴직 확정 → Auth 토큰 즉시 무효화 (수동 해지 경로 — D+3 자동 승인과 동일 패턴)
    try {
      await admin.auth().revokeRefreshTokens(workerUid);
    } catch (tokenErr) {
      console.warn(`[해지승인] revokeRefreshTokens 실패 uid=${workerUid}: ${tokenErr}`);
      await db.collection("pending_token_revocations").doc(workerUid).set({
        uid: workerUid,
        reason: "TERMINATION_MANUALLY_APPROVED",
        applicationId,
        failedAt: admin.firestore.FieldValue.serverTimestamp(),
      }).catch(() => {/* 기록 실패는 무시 */});
    }

    const terminationDateStr = app.terminationEffectiveDate
      ? (() => { const d = app.terminationEffectiveDate!.toDate(); return `${d.getMonth()+1}/${d.getDate()}`; })()
      : null;
    // [FCM-01] 상호 해지 알림 분기:
    //   관리자 요청(terminationRequestedByUid !== app.uid): 근무자 action:"terminationDetail" + 관리자 screen:"fixedWorker"
    //   근무자 요청(terminationRequestedByUid === app.uid): 근무자에게만 1건 (중복 방지)
    const adminRequested = !!app.terminationRequestedByUid &&
                           app.terminationRequestedByUid !== app.uid;
    const notifPromises: Promise<admin.firestore.DocumentReference>[] = [];
    const terminationBody = `${app.businessName}과의 계약이 해지되었습니다.${terminationDateStr ? `\n해지일: ${terminationDateStr}` : ""}`;

    // 근무자 알림 (항상 발송)
    if (app.uid && app.uid.length > 0) {
      notifPromises.push(
        db.collection("users").doc(app.uid).collection("notifications").add({
          userId: app.uid,
          type: "terminationApproved",
          title: "계약해지 완료",
          body: terminationBody,
          data: {applicationId, businessId, action: "terminationDetail"},
          isRead: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        })
      );
    }
    // 관리자 알림 (관리자가 해지 요청한 경우만 — 중복 방지)
    if (adminRequested) {
      notifPromises.push(
        db.collection("users").doc(app.terminationRequestedByUid!).collection("notifications").add({
          userId: app.terminationRequestedByUid,
          type: "terminationApproved",
          title: "계약해지 완료",
          body: terminationBody,
          // [FCM-01] screen:"fixedWorker" — FCM background에서 관리자 인력관리 화면 직접 이동
          data: {applicationId, businessId, screen: "fixedWorker"},
          isRead: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        })
      );
    }
    // 알림은 상태 커밋 후 best-effort — 실패해도 APPROVED/CANCELED 상태는 유지
    Promise.all(notifPromises).catch((e) =>
      console.error("[callableApproveTermination] 알림 전송 실패:", e)
    );

    return {success: true};
  }
);

// ─── 9. callableApproveResignation ───────────────────────────────────────────
export const callableApproveResignation = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;
    const {applicationId} = request.data as {applicationId: string};
    if (!applicationId) throw new HttpsError("invalid-argument", "applicationId 필수");

    const appRef = db.collection("applications").doc(applicationId);
    const preSnap = await appRef.get();
    if (!preSnap.exists) throw new HttpsError("not-found", "지원 정보를 찾을 수 없습니다.");
    const preData = preSnap.data()!;
    const businessId = preData.businessId as string;

    // 권한 확인: 관리자만 가능
    await assertBizAdmin(callerUid, businessId);

    // 계약서 사전 쿼리 (트랜잭션 외부)
    const pendingContractStatuses = ["pending_employer", "pending_worker"];
    let contractRef: admin.firestore.DocumentReference | null = null;
    const cq1 = await db.collection("employment_contracts")
      .where("applicationId", "==", applicationId)
      .where("businessId", "==", businessId)
      .limit(5)
      .get();
    const cq1Match = cq1.docs.find((d) =>
      pendingContractStatuses.includes(d.data().status as string)
    );
    if (cq1Match) {
      contractRef = cq1Match.ref;
    } else {
      const cq2 = await db.collection("employment_contracts")
        .where("applicationIds", "array-contains", applicationId)
        .where("businessId", "==", businessId)
        .limit(5)
        .get();
      const cq2Match = cq2.docs.find((d) =>
        pendingContractStatuses.includes(d.data().status as string)
      );
      if (cq2Match) contractRef = cq2Match.ref;
    }

    type ResignationResolved = {
      toId: string | null;
      slotId: string | null;
      uid: string;
      businessName: string;
      resignRequestDate: admin.firestore.Timestamp | null;
      originalStatus: string;
    };
    let resolvedData: ResignationResolved | null = null;

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(appRef);
      if (!snap.exists) throw new HttpsError("not-found", "지원서 없음");
      const d = snap.data()!;
      if (d.resignStatus !== "PENDING") {
        throw new HttpsError(
          "failed-precondition",
          `퇴사 요청 상태가 PENDING이 아님: ${d.resignStatus}`
        );
      }
      const resignRequestDate =
        (d.resignRequestDate as admin.firestore.Timestamp | null) ?? null;
      resolvedData = {
        toId: (d.toId as string | null) ?? null,
        slotId: (d.slotId as string | null) ?? null,
        uid: d.uid as string,
        businessName: (d.businessName as string) ?? "",
        resignRequestDate,
        originalStatus: d.status as string,
      };
      tx.update(appRef, {
        resignStatus: "APPROVED",
        resignApprovedAt: admin.firestore.FieldValue.serverTimestamp(),
        resignApprovedBy: callerUid,
        actualResignDate:
          resignRequestDate ?? admin.firestore.FieldValue.serverTimestamp(),
        status: "CANCELED",
      });
      if (contractRef) {
        tx.update(contractRef, {
          status: "voided",
          contractVoidedAt: admin.firestore.FieldValue.serverTimestamp(),
          voidReason: "RESIGNATION",
        });
      }
    });

    if (!resolvedData) throw new HttpsError("internal", "트랜잭션 결과 없음");
    const app = resolvedData as ResignationResolved;

    // TO totalConfirmed 감소
    if (app.toId && CONFIRMED_STATUSES.includes(app.originalStatus)) {
      const batch = db.batch();
      batch.update(db.collection("tos").doc(app.toId), {
        totalConfirmed: admin.firestore.FieldValue.increment(-1),
      });
      if (app.slotId) {
        batch.update(
          db.collection("tos").doc(app.toId).collection("slots").doc(app.slotId),
          {confirmedCount: admin.firestore.FieldValue.increment(-1)}
        );
      }
      await batch.commit();
    }

    // 퇴직 확정 → Auth 토큰 즉시 무효화 (수동 퇴사 승인 경로 — D+3 자동 승인과 동일 패턴)
    try {
      await admin.auth().revokeRefreshTokens(app.uid);
    } catch (tokenErr) {
      console.warn(`[퇴사승인] revokeRefreshTokens 실패 uid=${app.uid}: ${tokenErr}`);
      await db.collection("pending_token_revocations").doc(app.uid).set({
        uid: app.uid,
        reason: "RESIGNATION_MANUALLY_APPROVED",
        applicationId,
        failedAt: admin.firestore.FieldValue.serverTimestamp(),
      }).catch(() => {/* 기록 실패는 무시 */});
    }

    // 퇴사일 이후 scheduled attendance → absent 일괄 처리
    const cutoffDate = app.resignRequestDate?.toDate() ?? new Date();
    const scheduledSnap = await db.collection("attendance")
      .where("applicationId", "==", applicationId)
      .where("status", "==", "scheduled")
      .get();
    if (!scheduledSnap.empty) {
      let cancelBatch = db.batch();
      let count = 0;
      for (const doc of scheduledSnap.docs) {
        const workDate = doc.data().workDate as admin.firestore.Timestamp | null;
        if (workDate && workDate.toDate() >= cutoffDate) {
          cancelBatch.update(doc.ref, {
            status: "absent",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          count++;
          if (count >= 499) {
            await cancelBatch.commit();
            cancelBatch = db.batch();
            count = 0;
          }
        }
      }
      if (count > 0) await cancelBatch.commit();
    }

    // 근무자에게 알림 (best-effort — 실패해도 APPROVED/CANCELED 상태는 유지)
    if (app.uid && app.uid.length > 0) {
      const rd = app.resignRequestDate;
      const rdStr = rd ? (() => { const d = rd.toDate(); return `${d.getMonth()+1}/${d.getDate()}`; })() : null;
      db.collection("users").doc(app.uid).collection("notifications").add({
        type: "resignApproved",
        userId: app.uid,
        title: "퇴사 승인",
        body: `${app.businessName}에서 퇴사 요청을 승인했습니다.${rdStr ? `\n퇴사일: ${rdStr}` : ""}`,
        data: {applicationId, businessId, action: "resignDetail"},
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      }).catch((e) => console.error("[callableApproveResignation] 알림 전송 실패:", e));
    }

    return {success: true};
  }
);

// ─── 10. callableRecalculateTOStats ──────────────────────────────────────────
export const callableRecalculateTOStats = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;

    const toId = request.data.toId as string | undefined;
    if (!toId || typeof toId !== "string") {
      throw new HttpsError("invalid-argument", "toId가 필요합니다.");
    }

    const toSnap = await db.collection("tos").doc(toId).get();
    if (!toSnap.exists) throw new HttpsError("not-found", "공고를 찾을 수 없습니다.");
    const toData = toSnap.data()!;
    const businessId = toData.businessId as string;
    const isFlexType = (toData.type as string | undefined) === "flex";
    const totalRequired = (toData.totalRequired as number) ?? 0;
    const toStatus = toData.status as string;

    await assertBizAdmin(callerUid, businessId);

    const appsSnap = await db
      .collection("applications")
      .where("toId", "==", toId)
      .where("businessId", "==", businessId)
      .get();

    let totalPending = 0;
    let totalConfirmed = 0;
    for (const doc of appsSnap.docs) {
      const status = doc.data().status as string | undefined;
      if (status === "PENDING") totalPending++;
      if (status && CONFIRMED_STATUSES.includes(status)) totalConfirmed++;
    }

    const toUpdate: Record<string, unknown> = {totalPending, totalConfirmed};
    const notClosed = toStatus !== "CLOSED" && toStatus !== "EXPIRED";
    if (notClosed) {
      const shouldBeFull = totalRequired > 0 && totalConfirmed >= totalRequired;
      toUpdate.status = shouldBeFull ? "FULL" : "ACTIVE";
    }
    await db.collection("tos").doc(toId).update(toUpdate);

    if (isFlexType) {
      const slotStats: Record<string, {pending: number; confirmed: number}> = {};
      for (const doc of appsSnap.docs) {
        const d = doc.data();
        const status = d.status as string | undefined;
        const slotId = d.slotId as string | undefined;
        if (!slotId || !status) continue;
        if (!["PENDING", ...CONFIRMED_STATUSES].includes(status)) continue;
        if (!slotStats[slotId]) slotStats[slotId] = {pending: 0, confirmed: 0};
        if (status === "PENDING") slotStats[slotId].pending++;
        if (CONFIRMED_STATUSES.includes(status)) slotStats[slotId].confirmed++;
      }
      const slotsSnap = await db.collection("tos").doc(toId).collection("slots").get();
      if (!slotsSnap.empty) {
        let batch = db.batch();
        let count = 0;
        for (const slotDoc of slotsSnap.docs) {
          const stats = slotStats[slotDoc.id] ?? {pending: 0, confirmed: 0};
          batch.update(slotDoc.ref, {
            pendingCount: stats.pending,
            confirmedCount: stats.confirmed,
          });
          count++;
          if (count >= 499) {
            await batch.commit();
            batch = db.batch();
            count = 0;
          }
        }
        if (count > 0) await batch.commit();
      }
    }

    return {success: true, totalPending, totalConfirmed};
  }
);

// ─── 11. callableDeleteTO ─────────────────────────────────────────────────────
export const callableDeleteTO = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;

    const toId = request.data.toId as string | undefined;
    if (!toId || typeof toId !== "string") {
      throw new HttpsError("invalid-argument", "toId가 필요합니다.");
    }

    const toSnap = await db.collection("tos").doc(toId).get();
    if (!toSnap.exists) throw new HttpsError("not-found", "공고를 찾을 수 없습니다.");
    const toData = toSnap.data()!;
    const businessId = toData.businessId as string;
    const isFlexType = (toData.type as string | undefined) === "flex";
    const businessName = (toData.businessName as string) ?? "";
    const toTitle = (toData.title as string) ?? "";

    await assertBizAdmin(callerUid, businessId);

    const ACTIVE_STATUSES = ["PENDING", "CONFIRMED", "CONTRACT_PENDING"];
    const now = Timestamp.now();

    // 1. slots 서브컬렉션 삭제 (flex TO)
    if (isFlexType) {
      const slotsSnap = await db.collection("tos").doc(toId).collection("slots").get();
      if (!slotsSnap.empty) {
        let batch = db.batch();
        let count = 0;
        for (const slotDoc of slotsSnap.docs) {
          batch.delete(slotDoc.ref);
          count++;
          if (count >= 499) {
            await batch.commit();
            batch = db.batch();
            count = 0;
          }
        }
        if (count > 0) await batch.commit();
      }
    }

    // 2. applications 처리: 활성 → AUTO_CANCELED, 나머지 → 삭제
    const appsSnap = await db
      .collection("applications")
      .where("toId", "==", toId)
      .where("businessId", "==", businessId)
      .get();

    const notifyTargets: Array<{
      uid: string;
      status: string;
      workDate?: admin.firestore.Timestamp;
    }> = [];

    if (!appsSnap.empty) {
      let batch = db.batch();
      let count = 0;
      for (const doc of appsSnap.docs) {
        const d = doc.data();
        const status = d.status as string | undefined;
        if (status && ACTIVE_STATUSES.includes(status)) {
          batch.update(doc.ref, {
            status: "AUTO_CANCELED",
            canceledAt: now,
            cancelReason: "TO_DELETED",
          });
          const applicantUid = d.uid as string | undefined;
          if (applicantUid) {
            notifyTargets.push({
              uid: applicantUid,
              status,
              workDate: d.workDate as admin.firestore.Timestamp | undefined,
            });
          }
        } else {
          batch.delete(doc.ref);
        }
        count++;
        if (count >= 499) {
          await batch.commit();
          batch = db.batch();
          count = 0;
        }
      }
      if (count > 0) await batch.commit();
    }

    // 3. TO 문서 삭제
    await db.collection("tos").doc(toId).delete();

    // 4. 알림 발송 (fire-and-forget)
    for (const target of notifyTargets) {
      const statusText = CONFIRMED_STATUSES.includes(target.status) ? "확정된 근무" : "지원";
      let dateStr = "";
      if (target.workDate) {
        const d = target.workDate.toDate();
        dateStr = `\n근무일: ${d.getMonth() + 1}/${d.getDate()}`;
      }
      db.collection("users").doc(target.uid).collection("notifications")
        .add({
          userId: target.uid,
          type: "workCanceled",
          title: "공고 취소",
          body: `${businessName}의 "${toTitle}" 공고가 취소되어 ${statusText}이(가) 무효화되었습니다.${dateStr}`,
          data: {businessId, action: "toList", reason: "TO_DELETED"},
          isRead: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        })
        .catch((e) =>
          console.error(`[callableDeleteTO] 알림 발송 실패 (uid=${target.uid}):`, e)
        );
    }

    // 5. 고아 데이터 정리 (TO 삭제 완료 후 — 실패해도 무시)
    const allAppIds = appsSnap.docs.map((d) => d.id);
    if (allAppIds.length > 0) {
      try {
        const WAGE_DONE = ["wageTransferred", "wageConfirmed"];
        for (let i = 0; i < allAppIds.length; i += 30) {
          const chunk = allAppIds.slice(i, i + 30);

          const attSnaps = await Promise.all(
            chunk.map((appId) =>
              db.collection("attendance")
                .where("applicationId", "==", appId)
                .where("businessId", "==", businessId)
                .get()
            )
          );
          const attDocs = attSnaps.flatMap((s) => s.docs);
          if (attDocs.length > 0) {
            let batch = db.batch();
            let count = 0;
            for (const d of attDocs) {
              const wageStatus = d.data().wageStatus as string | undefined;
              if (wageStatus && WAGE_DONE.includes(wageStatus)) continue;
              batch.delete(d.ref);
              count++;
              if (count >= 499) {
                await batch.commit();
                batch = db.batch();
                count = 0;
              }
            }
            if (count > 0) await batch.commit();
          }

          const reqSnaps = await Promise.all(
            chunk.map((appId) =>
              db.collection("schedule_change_requests")
                .where("applicationId", "==", appId)
                .where("businessId", "==", businessId)
                .get()
            )
          );
          const reqDocs = reqSnaps.flatMap((s) => s.docs);
          if (reqDocs.length > 0) {
            let batch = db.batch();
            let count = 0;
            for (const d of reqDocs) {
              batch.delete(d.ref);
              count++;
              if (count >= 499) {
                await batch.commit();
                batch = db.batch();
                count = 0;
              }
            }
            if (count > 0) await batch.commit();
          }

          const contractSnaps = await Promise.all(
            chunk.map((appId) =>
              db.collection("employment_contracts")
                .where("applicationId", "==", appId)
                .where("businessId", "==", businessId)
                .get()
            )
          );
          const contractDocs1 = contractSnaps.flatMap((s) => s.docs);
          const foundDocIds = new Set(contractDocs1.map((d) => d.id));
          const allContractDocs = [...contractDocs1];

          for (let j = 0; j < chunk.length; j += 10) {
            const subChunk = chunk.slice(j, j + 10);
            const bundleSnap = await db.collection("employment_contracts")
              .where("businessId", "==", businessId)
              .where("applicationIds", "array-contains-any", subChunk)
              .get();
            for (const doc of bundleSnap.docs) {
              if (!foundDocIds.has(doc.id)) {
                foundDocIds.add(doc.id);
                allContractDocs.push(doc);
              }
            }
          }

          if (allContractDocs.length > 0) {
            let batch = db.batch();
            let count = 0;
            for (const c of allContractDocs) {
              if ((c.data().status as string | undefined) === "completed") continue;
              batch.delete(c.ref);
              count++;
              if (count >= 499) {
                await batch.commit();
                batch = db.batch();
                count = 0;
              }
            }
            if (count > 0) await batch.commit();
          }
        }
      } catch (cleanupErr) {
        console.error("[callableDeleteTO] 고아 데이터 정리 실패 (TO 삭제는 완료됨):", cleanupErr);
      }
    }

    return {success: true};
  }
);

// ─── 12. callableCloseSlots ───────────────────────────────────────────────────
export const callableCloseSlots = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;
    const {toId, slotIds, businessId} = request.data as {
      toId: string;
      slotIds: string[];
      businessId: string;
    };
    if (!toId) throw new HttpsError("invalid-argument", "toId 필수");
    if (!Array.isArray(slotIds) || slotIds.length === 0)
      throw new HttpsError("invalid-argument", "slotIds 필수");
    if (slotIds.length > 100) throw new HttpsError("invalid-argument", "slotIds는 최대 100개");
    if (!businessId) throw new HttpsError("invalid-argument", "businessId 필수");

    await assertBizAdmin(callerUid, businessId);

    // [S4-FIX] toId ↔ businessId 교차검증 — 다른 사업장 TO 슬롯 조작 차단
    const toDocSnap = await db.collection("tos").doc(toId).get();
    if (!toDocSnap.exists) throw new HttpsError("not-found", "TO를 찾을 수 없습니다.");
    if ((toDocSnap.data()?.businessId as string) !== businessId) {
      throw new HttpsError("permission-denied", "해당 TO가 요청한 사업장에 속하지 않습니다.");
    }

    const now = admin.firestore.FieldValue.serverTimestamp();

    // 1. 슬롯 closed 설정
    let batch = db.batch();
    let count = 0;
    for (const slotId of slotIds) {
      batch.update(
        db.collection("tos").doc(toId).collection("slots").doc(slotId),
        {isManualClosed: true, status: "closed", closedAt: now, closedBy: callerUid}
      );
      count++;
      if (count >= 499) {
        await batch.commit();
        batch = db.batch();
        count = 0;
      }
    }
    if (count > 0) await batch.commit();

    // 2. PENDING 지원서 조회 (slotId별 병렬)
    const pendingSnaps = await Promise.all(
      slotIds.map((slotId) =>
        db.collection("applications")
          .where("toId", "==", toId)
          .where("businessId", "==", businessId)
          .where("slotId", "==", slotId)
          .where("status", "==", "PENDING")
          .get()
      )
    );
    const pendingBySlot = new Map<string, admin.firestore.QueryDocumentSnapshot[]>();
    for (let i = 0; i < slotIds.length; i++) {
      if (pendingSnaps[i].docs.length > 0)
        pendingBySlot.set(slotIds[i], pendingSnaps[i].docs);
    }

    // 3. 슬롯별 PENDING → REJECTED + pendingCount 감소 + 알림
    let totalCanceledPending = 0;
    for (const slotId of slotIds) {
      const docs = pendingBySlot.get(slotId);
      if (!docs || docs.length === 0) continue;
      let slotCanceled = 0;
      try {
        let cancelBatch = db.batch();
        let cancelCount = 0;
        for (const doc of docs) {
          cancelBatch.update(doc.ref, {
            status: "REJECTED",
            rejectedAt: now,
            rejectMessage: "공고 슬롯이 마감되었습니다",
          });
          cancelCount++;
          slotCanceled++;
          if (cancelCount >= 499) {
            await cancelBatch.commit();
            cancelBatch = db.batch();
            cancelCount = 0;
          }
        }
        if (cancelCount > 0) await cancelBatch.commit();
        totalCanceledPending += slotCanceled;

        const wtDeltas = new Map<string, number>();
        for (const doc of docs) {
          const wt = doc.data().selectedWorkType as string | undefined;
          if (wt) wtDeltas.set(wt, (wtDeltas.get(wt) ?? 0) + 1);
        }
        const slotUpdate: Record<string, unknown> = {
          pendingCount: admin.firestore.FieldValue.increment(-slotCanceled),
        };
        for (const [wt, delta] of wtDeltas.entries()) {
          slotUpdate[`workTypeCounts.${wt}.pendingCount`] =
            admin.firestore.FieldValue.increment(-delta);
        }
        await db.collection("tos").doc(toId).collection("slots").doc(slotId).update(slotUpdate);

        // 알림: applicationRejected
        for (const doc of docs) {
          const d = doc.data();
          const applicantUid = d.uid as string | undefined;
          if (!applicantUid) continue;
          const workDate = (d.workDate as Timestamp | undefined)?.toDate() ?? new Date();
          const month = workDate.getMonth() + 1;
          const day = workDate.getDate();
          db.collection("users").doc(applicantUid).collection("notifications")
            .add({
              userId: applicantUid,
              type: "applicationRejected",
              title: "지원 거절",
              body:
                `${(d.businessName as string) ?? ""}의 ` +
                `${(d.selectedWorkType as string) ?? ""} 지원이 거절되었습니다.\n` +
                `사유: 공고 슬롯이 마감되었습니다\n근무일: ${month}/${day}`,
              data: {
                applicationId: doc.id,
                businessId: (d.businessId as string) ?? businessId,
                action: "applicationDetail",
              },
              isRead: false,
              createdAt: now,
            })
            .catch(() => {});
        }
      } catch (e) {
        console.error(`[CloseSlots] 슬롯 ${slotId} PENDING 취소 실패:`, e);
      }
    }

    // 4. TO totalPending 감소
    if (totalCanceledPending > 0) {
      await db.collection("tos").doc(toId).update({
        totalPending: admin.firestore.FieldValue.increment(-totalCanceledPending),
      });
    }

    // 5. TO status 재계산
    try {
      const allSlotsSnap = await db.collection("tos").doc(toId).collection("slots").get();
      const hasOpenSlot = allSlotsSnap.docs.some((d) => {
        const s = d.data();
        return !s.isManualClosed && (s.status === "open" || s.status === "full");
      });
      const toSnap2 = await db.collection("tos").doc(toId).get();
      const currentTOStatus = toSnap2.data()?.status as string | undefined;
      const openStates = ["ACTIVE", "FULL", "SCHEDULED"];
      if (!hasOpenSlot && openStates.includes(currentTOStatus ?? "")) {
        await db.collection("tos").doc(toId).update({status: "CLOSED", closedAt: now});
      }
    } catch (e) {
      console.error(`[CloseSlots] TO status 재계산 실패 (${toId}):`, e);
    }

    return {success: true, canceledCount: totalCanceledPending};
  }
);

// ─── 12.5. callableReopenSlots ───────────────────────────────────────────────
// 슬롯 일괄 재오픈 — reopenedBy 서버 강제, open/full 서버 원자적 판단
// TOCTOU 방지: 각 슬롯 confirmedCount/requiredCount를 트랜잭션 내에서 읽어 status 결정
// [CF-ONLY] batchReopenSlots 클라이언트 직접 쓰기에서 전환 (reopenedBy 위조 차단)
// Input : { toId, slotIds, businessId }
// Output: { success, reopenedCount }
export const callableReopenSlots = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;

    const {toId, slotIds, businessId} = request.data as {
      toId?: string;
      slotIds?: string[];
      businessId?: string;
    };
    if (!toId) throw new HttpsError("invalid-argument", "toId 필수");
    if (!Array.isArray(slotIds) || slotIds.length === 0)
      throw new HttpsError("invalid-argument", "slotIds 필수");
    if (slotIds.length > 100) throw new HttpsError("invalid-argument", "slotIds는 최대 100개");
    if (!businessId) throw new HttpsError("invalid-argument", "businessId 필수");

    await assertBizAdmin(callerUid, businessId);

    // toId ↔ businessId 교차검증 — 다른 사업장 TO 슬롯 조작 차단
    const toDocSnap = await db.collection("tos").doc(toId).get();
    if (!toDocSnap.exists) throw new HttpsError("not-found", "TO를 찾을 수 없습니다.");
    if ((toDocSnap.data()?.businessId as string) !== businessId) {
      throw new HttpsError("permission-denied", "해당 TO가 요청한 사업장에 속하지 않습니다.");
    }

    const now = admin.firestore.FieldValue.serverTimestamp();

    // 각 슬롯 트랜잭션: TOCTOU 방지 — confirmedCount 읽기 + open/full 결정 + 쓰기 원자화
    let reopenedCount = 0;
    for (const slotId of slotIds) {
      const slotRef = db.collection("tos").doc(toId).collection("slots").doc(slotId);
      try {
        // [L-1-FIX] 트랜잭션 반환값으로 실제 업데이트 여부 확인 — 미존재 슬롯 오증가 방지
        const updated = await db.runTransaction(async (tx) => {
          const slotSnap = await tx.get(slotRef);
          if (!slotSnap.exists) return false;

          const d = slotSnap.data()!;
          const confirmed = (d.confirmedCount as number | undefined) ?? 0;
          const rawWDs = (d.workDetails as Record<string, unknown>[] | undefined) ?? [];
          const required = rawWDs.reduce(
            (acc, wd) => acc + ((wd.requiredCount as number | undefined) ?? 0), 0
          );
          // 정원이 찬 슬롯은 full 유지 — open으로 강제 시 초과 지원 허용됨
          const newStatus = required > 0 && confirmed >= required ? "full" : "open";

          tx.update(slotRef, {
            isManualClosed: false,
            status: newStatus,
            reopenedAt: now,
            reopenedBy: callerUid, // 서버 강제 — 클라이언트 위조 불가
            closedAt: admin.firestore.FieldValue.delete(),
            closedBy: admin.firestore.FieldValue.delete(),
          });
          return true;
        });
        if (updated) reopenedCount++;
      } catch (e) {
        console.error(`[ReopenSlots] 슬롯 ${slotId} 재오픈 실패:`, e);
      }
    }

    // TO cascade status 동기화 — open/full 슬롯이 생기면 CLOSED → ACTIVE 복구
    try {
      const allSlotsSnap = await db.collection("tos").doc(toId).collection("slots").get();
      const hasOpenSlot = allSlotsSnap.docs.some((d) => {
        const s = d.data();
        return !s.isManualClosed && (s.status === "open" || s.status === "full");
      });
      const toSnap2 = await db.collection("tos").doc(toId).get();
      const currentTOStatus = toSnap2.data()?.status as string | undefined;
      if (hasOpenSlot && currentTOStatus === "CLOSED") {
        await db.collection("tos").doc(toId).update({
          status: "ACTIVE",
          closedAt: admin.firestore.FieldValue.delete(),
          isManualClosed: false,
        });
      }
    } catch (e) {
      console.error(`[ReopenSlots] TO cascade status 재계산 실패 (${toId}):`, e);
    }

    return {success: true, reopenedCount};
  }
);

// ─── 13. callableDeleteSlots ──────────────────────────────────────────────────
export const callableDeleteSlots = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;
    const {toId, slotIds, businessId} = request.data as {
      toId: string;
      slotIds: string[];
      businessId: string;
    };
    if (!toId) throw new HttpsError("invalid-argument", "toId 필수");
    if (!Array.isArray(slotIds) || slotIds.length === 0)
      throw new HttpsError("invalid-argument", "slotIds 필수");
    if (slotIds.length > 100) throw new HttpsError("invalid-argument", "slotIds는 최대 100개");
    if (!businessId) throw new HttpsError("invalid-argument", "businessId 필수");

    await assertBizAdmin(callerUid, businessId);

    const now = admin.firestore.FieldValue.serverTimestamp();

    // TO 정보 조회 (알림용)
    const toDoc = await db.collection("tos").doc(toId).get();
    const toData = toDoc.data() ?? {};
    const toBusinessName = (toData.businessName as string) ?? "";
    const toBusinessId = (toData.businessId as string) ?? businessId;
    const toTitle = (toData.title as string) ?? "";

    // [S4-FIX] toId ↔ businessId 교차검증 — 다른 사업장 TO 슬롯 삭제 차단
    if (toBusinessId !== businessId) {
      throw new HttpsError("permission-denied", "해당 TO가 요청한 사업장에 속하지 않습니다.");
    }

    // 슬롯 카운터 직접 읽기
    const slotSnaps = await Promise.all(
      slotIds.map((id) =>
        db.collection("tos").doc(toId).collection("slots").doc(id).get()
      )
    );
    let removedRequired = 0;
    let removedConfirmed = 0;
    let removedPending = 0;
    for (const snap of slotSnaps) {
      if (!snap.exists) continue;
      const d = snap.data()!;
      const wds = Array.isArray(d.workDetails) ? (d.workDetails as Record<string, unknown>[]) : [];
      removedRequired += wds.reduce(
        (acc, wd) => acc + (Number(wd?.requiredCount) || 0),
        0
      );
      removedConfirmed += Number(d.confirmedCount) || 0;
      removedPending += Number(d.pendingCount) || 0;
    }

    // 활성 지원서 조회 (slotId별 병렬)
    const activeStatuses = new Set(["PENDING", "CONFIRMED", "CONTRACT_PENDING"]);
    const activeSnaps = await Promise.all(
      slotIds.map((slotId) =>
        db.collection("applications")
          .where("toId", "==", toId)
          .where("businessId", "==", toBusinessId)
          .where("slotId", "==", slotId)
          .get()
      )
    );
    const allActiveDocs: admin.firestore.QueryDocumentSnapshot[] = [];
    for (const snap of activeSnaps) {
      for (const doc of snap.docs) {
        if (activeStatuses.has((doc.data().status as string) ?? ""))
          allActiveDocs.push(doc);
      }
    }

    // 활성 지원서 REJECTED 처리
    if (allActiveDocs.length > 0) {
      let cancelBatch = db.batch();
      let cancelCount = 0;
      for (const doc of allActiveDocs) {
        cancelBatch.update(doc.ref, {
          status: "REJECTED",
          rejectedAt: now,
          rejectReason: "공고 슬롯이 삭제되었습니다",
        });
        cancelCount++;
        if (cancelCount >= 499) {
          await cancelBatch.commit();
          cancelBatch = db.batch();
          cancelCount = 0;
        }
      }
      if (cancelCount > 0) await cancelBatch.commit();

      // 알림: 상태별 분기
      for (const doc of allActiveDocs) {
        const d = doc.data();
        const applicantUid = d.uid as string | undefined;
        if (!applicantUid) continue;
        const status = (d.status as string) ?? "";
        const workDate = (d.workDate as Timestamp | undefined)?.toDate() ?? new Date();
        const month = workDate.getMonth() + 1;
        const day = workDate.getDate();

        if (CONFIRMED_STATUSES.includes(status)) {
          db.collection("users").doc(applicantUid).collection("notifications")
            .add({
              userId: applicantUid,
              type: "workCanceled",
              title: "공고 취소",
              body:
                `${toBusinessName}의 "${toTitle}" 공고가 취소되어 ` +
                `확정된 근무이(가) 무효화되었습니다.\n근무일: ${month}/${day}`,
              data: {businessId: toBusinessId, action: "toList", reason: "TO_DELETED"},
              isRead: false,
              createdAt: now,
            })
            .catch(() => {});
        } else if (status === "PENDING") {
          db.collection("users").doc(applicantUid).collection("notifications")
            .add({
              userId: applicantUid,
              type: "applicationRejected",
              title: "지원 거절",
              body:
                `${(d.businessName as string) ?? toBusinessName}의 ` +
                `${(d.selectedWorkType as string) ?? ""} 지원이 거절되었습니다.\n` +
                `사유: 공고 슬롯이 삭제되었습니다\n근무일: ${month}/${day}`,
              data: {
                applicationId: doc.id,
                businessId: (d.businessId as string) ?? toBusinessId,
                action: "applicationDetail",
              },
              isRead: false,
              createdAt: now,
            })
            .catch(() => {});
        }
      }
    }

    // 슬롯 삭제 + TO 카운터 업데이트 (배치)
    let deleteBatch = db.batch();
    let deleteCount = 0;
    for (const slotId of slotIds) {
      deleteBatch.delete(db.collection("tos").doc(toId).collection("slots").doc(slotId));
      deleteCount++;
      if (deleteCount >= 498) {
        await deleteBatch.commit();
        deleteBatch = db.batch();
        deleteCount = 0;
      }
    }
    const toUpdate: Record<string, unknown> = {
      totalSlots: admin.firestore.FieldValue.increment(-slotIds.length),
    };
    if (removedRequired > 0)
      toUpdate.totalRequired = admin.firestore.FieldValue.increment(-removedRequired);
    if (removedConfirmed > 0)
      toUpdate.totalConfirmed = admin.firestore.FieldValue.increment(-removedConfirmed);
    if (removedPending > 0)
      toUpdate.totalPending = admin.firestore.FieldValue.increment(-removedPending);
    deleteBatch.update(db.collection("tos").doc(toId), toUpdate);
    await deleteBatch.commit();

    return {success: true};
  }
);

// ─── callableRejectTermination ─────────────────────────────────────────────
// 계약해지 거절: 근무자(app.uid) 또는 관리자가 PENDING 상태 해지 요청을 거절
// → terminationStatus: REJECTED + 알림은 해지 요청자(관리자)에게

type TerminationRejected = {
  businessName: string;
  terminationRequestedByUid: string | null;
};

export const callableRejectTermination = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;
    const {applicationId, rejectReason} = request.data as {
      applicationId: string;
      rejectReason?: string;
    };
    if (!applicationId) throw new HttpsError("invalid-argument", "applicationId 필수");
    // [F1] rejectReason 길이 제한 — 과도한 텍스트 저장/알림 본문 초과 방지
    if (rejectReason && rejectReason.length > 500) throw new HttpsError("invalid-argument", "rejectReason은 최대 500자까지 입력 가능합니다.");

    // 사전 조회: 권한 체크
    const appRef = db.collection("applications").doc(applicationId);
    const preSnap = await appRef.get();
    if (!preSnap.exists) throw new HttpsError("not-found", "지원서를 찾을 수 없습니다.");
    const preData = preSnap.data()!;
    const businessId = preData.businessId as string;
    const workerUid = preData.uid as string;

    // 권한: 근무자 본인 또는 관리자
    if (callerUid !== workerUid) {
      await assertBizAdmin(callerUid, businessId);
    }

    // 트랜잭션: terminationStatus=PENDING 검증 + 거절 원자화
    let resolvedData: TerminationRejected | null = null;

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(appRef);
      if (!snap.exists) throw new HttpsError("not-found", "지원서 없음");
      const data = snap.data()!;
      if (data.terminationStatus !== "PENDING") {
        throw new HttpsError(
          "failed-precondition",
          `거절 불가 — 현재 계약해지 상태: ${data.terminationStatus}`
        );
      }
      resolvedData = {
        businessName: (data.businessName as string) ?? "",
        terminationRequestedByUid: (data.terminationRequestedByUid as string | null) ?? null,
      } as TerminationRejected;
      tx.update(appRef, {
        terminationStatus: "REJECTED",
        terminationRespondedAt: admin.firestore.FieldValue.serverTimestamp(),
        terminationRejectReason: rejectReason ?? null,
      });
    });

    if (!resolvedData) throw new HttpsError("internal", "트랜잭션 결과 없음");
    const rd = resolvedData as TerminationRejected;

    // [TERM-REJECT-CONTRACT-FIX] 거절 시 contracts.terminationStatus 복원
    //   callableRequestTermination이 설정한 PENDING을 null로 롤백
    //   (callableCancelTermination과 동일 패턴)
    const cqReject = await db
      .collection("employment_contracts")
      .where("applicationId", "==", applicationId)
      .where("businessId", "==", businessId)
      .where("terminationStatus", "==", "PENDING")
      .limit(5)
      .get();
    if (cqReject.docs.length > 0) {
      const batch = db.batch();
      for (const d of cqReject.docs) batch.update(d.ref, {terminationStatus: null});
      await batch.commit();
    } else {
      const cqReject2 = await db
        .collection("employment_contracts")
        .where("applicationIds", "array-contains", applicationId)
        .where("businessId", "==", businessId)
        .where("terminationStatus", "==", "PENDING")
        .limit(5)
        .get();
      if (cqReject2.docs.length > 0) {
        const batch = db.batch();
        for (const d of cqReject2.docs) batch.update(d.ref, {terminationStatus: null});
        await batch.commit();
      }
    }

    // 알림: 해지 요청자에게 거절 통보 (GCF v2 종료 전 완료 보장)
    // [FCM-01] 관리자 요청(terminationRequestedByUid !== workerUid) → screen:"fixedWorker"
    //          근무자 요청(terminationRequestedByUid === workerUid) → action:"terminationDetail"
    if (rd.terminationRequestedByUid && rd.terminationRequestedByUid.length > 0) {
      const adminRequested = rd.terminationRequestedByUid !== workerUid;
      await db.collection("users")
        .doc(rd.terminationRequestedByUid)
        .collection("notifications")
        .add({
          userId: rd.terminationRequestedByUid,
          type: "terminationRejected",
          title: "계약해지 거절",
          body: `${rd.businessName}의 계약해지 요청이 거절되었습니다.${rejectReason ? `\n사유: ${rejectReason}` : ""}`,
          data: adminRequested
            // [FCM-01] 관리자 요청 거절 → FCM background에서 인력관리 화면 직접 이동
            ? {applicationId, businessId, screen: "fixedWorker"}
            : {applicationId, businessId, action: "terminationDetail"},
          isRead: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        })
        .catch((e) => console.error("[callableRejectTermination] 알림 전송 실패:", e));
    }

    return {success: true};
  }
);

// ─── callableRequestResignation ────────────────────────────────────────────
// 퇴사 요청: 근무자 본인만 호출 가능
// resignStatus: null 또는 REJECTED인 경우에만 PENDING으로 전환

export const callableRequestResignation = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;
    const {applicationId, resignDateIso} = request.data as {
      applicationId: string;
      resignDateIso?: string; // ISO 8601 날짜 문자열
    };
    if (!applicationId) throw new HttpsError("invalid-argument", "applicationId 필수");

    // 사전 조회
    const appRef = db.collection("applications").doc(applicationId);
    const preSnap = await appRef.get();
    if (!preSnap.exists) throw new HttpsError("not-found", "지원서를 찾을 수 없습니다.");
    const preData = preSnap.data()!;
    const businessId = preData.businessId as string;
    const workerUid = preData.uid as string;

    // 권한: 근무자 본인만 퇴사 요청 가능
    if (callerUid !== workerUid) {
      throw new HttpsError("permission-denied", "본인 퇴사 요청만 가능합니다.");
    }

    // 날짜 유효성 사전 검사 — 트랜잭션 전에 파싱 오류를 빠르게 차단
    if (resignDateIso) {
      const parsed = new Date(resignDateIso);
      if (isNaN(parsed.getTime())) throw new HttpsError("invalid-argument", "유효하지 않은 날짜");
      // [RESIGN-DATE-FIX] 과거 소급 및 극미래 날짜 차단
      //   과거 퇴사일 허용 시 callableApproveResignation이 이미 완료된 attendance를 absent로 변경
      const nowMs = Date.now();
      const thirtyDaysAgoMs = nowMs - 30 * 24 * 60 * 60 * 1000;
      const twoYearsMs = nowMs + 2 * 365 * 24 * 60 * 60 * 1000;
      if (parsed.getTime() < thirtyDaysAgoMs) {
        throw new HttpsError("invalid-argument", "퇴사일은 30일 이전으로 소급할 수 없습니다.");
      }
      if (parsed.getTime() > twoYearsMs) {
        throw new HttpsError("invalid-argument", "퇴사일은 2년 이내여야 합니다.");
      }
    }

    // 트랜잭션: 중복 퇴사 요청 방지 + effectiveDate를 트랜잭션 내에서 계산
    // workEndDate를 pre-read에서 가져오면 race condition 발생 가능 → tx 내부로 이동
    type ResignationRequested = {effectiveDate: FirebaseFirestore.Timestamp};
    let resolvedData: ResignationRequested | null = null;

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(appRef);
      if (!snap.exists) throw new HttpsError("not-found", "지원서 없음");
      const data = snap.data()!;
      const currentResignStatus = (data.resignStatus as string | null) ?? null;
      if (currentResignStatus !== null && currentResignStatus !== "REJECTED") {
        throw new HttpsError(
          "failed-precondition",
          `이미 진행 중인 퇴사 요청이 있습니다: ${currentResignStatus}`
        );
      }
      let effectiveDate: FirebaseFirestore.Timestamp;
      if (resignDateIso) {
        effectiveDate = Timestamp.fromDate(new Date(resignDateIso));
      } else {
        const workEndDate = data.workEndDate as FirebaseFirestore.Timestamp | null;
        effectiveDate = workEndDate ?? Timestamp.now();
      }
      resolvedData = {effectiveDate} as ResignationRequested;
      tx.update(appRef, {
        resignStatus: "PENDING",
        resignRequestedAt: admin.firestore.FieldValue.serverTimestamp(),
        resignRequestDate: effectiveDate,
      });
    });

    if (!resolvedData) throw new HttpsError("internal", "트랜잭션 결과 없음");
    const effectiveDate = (resolvedData as ResignationRequested).effectiveDate;

    // 관리자 UIDs 조회 (알림 발송용)
    const bizSnap = await db.collection("businesses").doc(businessId).get();
    const bizData = bizSnap.data() ?? {};
    const adminIds: string[] = Array.isArray(bizData.adminIds)
      ? (bizData.adminIds as string[])
      : [];
    if (adminIds.length === 0 && bizData.ownerId) {
      adminIds.push(bizData.ownerId as string);
    }

    // 근무자 이름 조회
    const workerSnap = await db.collection("users").doc(workerUid).get();
    const workerName = (workerSnap.data()?.name as string | undefined) ?? "근무자";

    // 퇴사 예정일 포맷
    const resignDateObj = effectiveDate.toDate();
    const month = resignDateObj.getMonth() + 1;
    const day = resignDateObj.getDate();
    const businessName = (preData.businessName as string) ?? "";

    // 관리자들에게 알림 발송 (GCF v2 종료 전 완료 보장)
    await Promise.all(adminIds.map((adminUid) =>
      db.collection("users")
        .doc(adminUid)
        .collection("notifications")
        .add({
          userId: adminUid,
          type: "resignRequested",
          title: "퇴사 요청",
          body: `${workerName}님이 퇴사를 요청했습니다.\n사업장: ${businessName}\n퇴사 예정일: ${month}/${day}`,
          data: {applicationId, businessId, action: "resignDetail"},
          isRead: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        })
        .catch((e) => console.error("[callableRequestResignation] 알림 전송 실패:", e))
    ));

    return {success: true};
  }
);

// ─── callableRejectResignation ─────────────────────────────────────────────
// 퇴사 거절: 관리자 전용
// 기존 클라이언트 직접 쓰기(resignRejectedBy=adminUID)는 위조 가능 → CF에서 callerUid 사용
export const callableRejectResignation = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;
    const {applicationId, rejectReason} = request.data as {
      applicationId: string;
      rejectReason?: string;
    };
    if (!applicationId) throw new HttpsError("invalid-argument", "applicationId 필수");
    // [F1] rejectReason 길이 제한 — 과도한 텍스트 저장/알림 본문 초과 방지
    if (rejectReason && rejectReason.length > 500) throw new HttpsError("invalid-argument", "rejectReason은 최대 500자까지 입력 가능합니다.");

    const appRef = db.collection("applications").doc(applicationId);
    const preSnap = await appRef.get();
    if (!preSnap.exists) throw new HttpsError("not-found", "지원서를 찾을 수 없습니다.");
    const preData = preSnap.data()!;
    const businessId = preData.businessId as string;

    // 권한: 관리자만 퇴사 거절 가능
    await assertBizAdmin(callerUid, businessId);

    type ResignationRejected = {
      workerUid: string;
      businessName: string;
    };
    let resolvedData: ResignationRejected | null = null;

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(appRef);
      if (!snap.exists) throw new HttpsError("not-found", "지원서 없음");
      const data = snap.data()!;
      if (data.resignStatus !== "PENDING") {
        throw new HttpsError(
          "failed-precondition",
          `거절 불가 — 현재 퇴사 요청 상태: ${data.resignStatus}`
        );
      }
      resolvedData = {
        workerUid: data.uid as string,
        businessName: (data.businessName as string) ?? "",
      } as ResignationRejected;
      tx.update(appRef, {
        resignStatus: "REJECTED",
        resignRejectedAt: admin.firestore.FieldValue.serverTimestamp(),
        resignRejectedBy: callerUid, // 서버 검증된 UID — 클라이언트 위조 불가
        resignRejectReason: rejectReason ?? null,
      });
    });

    if (!resolvedData) throw new HttpsError("internal", "트랜잭션 결과 없음");
    const rd = resolvedData as ResignationRejected;

    // 근무자에게 알림 (GCF v2 종료 전 완료 보장)
    if (rd.workerUid && rd.workerUid.length > 0) {
      await db.collection("users")
        .doc(rd.workerUid)
        .collection("notifications")
        .add({
          userId: rd.workerUid,
          type: "resignRejected",
          title: "퇴사 요청 거절",
          body: `${rd.businessName}의 퇴사 요청이 거절되었습니다.${rejectReason ? `\n사유: ${rejectReason}` : ""}`,
          data: {applicationId, businessId, action: "resignDetail"},
          isRead: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        })
        .catch((e) => console.error("[callableRejectResignation] 알림 전송 실패:", e));
    }

    return {success: true};
  }
);

// ─── callableExpireApplications ────────────────────────────────────────────
// workDate가 지난 PENDING 지원서를 AUTO_CANCELED로 일괄 처리
// 클라이언트 직접 쓰기는 Firestore rules가 AUTO_CANCELED 전환을 차단 → CF 필수
export const callableExpireApplications = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;

    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const todayTimestamp = Timestamp.fromDate(today);

    const snapshot = await db.collection("applications")
      .where("uid", "==", callerUid)
      .where("status", "==", "PENDING")
      .where("workDate", "<", todayTimestamp)
      .get();

    if (snapshot.empty) return {expired: 0};

    let batch = db.batch();
    let count = 0;
    let total = 0;
    for (const doc of snapshot.docs) {
      batch.update(doc.ref, {
        status: "AUTO_CANCELED",
        canceledAt: admin.firestore.FieldValue.serverTimestamp(),
        cancelReason: "AUTO_EXPIRED",
      });
      count++;
      total++;
      if (count >= 499) {
        await batch.commit();
        batch = db.batch();
        count = 0;
      }
    }
    if (count > 0) await batch.commit();

    console.info(`[callableExpireApplications] uid=${callerUid} 만료=${total}건`);
    return {expired: total};
  }
);

// ─── callableCancelResignRequest ───────────────────────────────────────────
// 퇴사 요청 취소: 근무자 본인 전용
// cancelTerminationRequest는 이미 CF 전용이었으나 cancelResignRequest만 클라이언트 직접 쓰기였음
// → 대칭성 확보 및 rules 클라이언트 경로 제거를 위해 CF 이전
export const callableCancelResignRequest = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;
    const {applicationId} = request.data as {applicationId: string};
    if (!applicationId) throw new HttpsError("invalid-argument", "applicationId 필수");

    const appRef = db.collection("applications").doc(applicationId);

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(appRef);
      if (!snap.exists) throw new HttpsError("not-found", "지원서를 찾을 수 없습니다.");
      const data = snap.data()!;

      // 권한: 근무자 본인만 자신의 퇴사 요청 취소 가능
      if ((data.uid as string) !== callerUid) {
        throw new HttpsError("permission-denied", "본인 퇴사 요청만 취소할 수 있습니다.");
      }

      const currentResignStatus = (data.resignStatus as string | null) ?? null;
      if (currentResignStatus !== "PENDING") {
        throw new HttpsError(
          "failed-precondition",
          `취소 불가 — 현재 퇴사 요청 상태: ${currentResignStatus}`
        );
      }

      tx.update(appRef, {
        resignStatus: null,
        resignRequestedAt: null,
        resignRequestDate: null,
      });
    });

    return {success: true};
  }
);

// ═══════════════════════════════════════════════════════════
// H-1: 출퇴근/노쇼/리셋/마감취소 CF 이전 (클라이언트 직접 쓰기 제거)
// ═══════════════════════════════════════════════════════════

interface NoShowEntry {
  applicationId: string;
  workDateMs: number;
  userId: string;
  businessName: string;
  workType: string;
  attendanceId?: string;
}

// 노쇼 배치 처리 — 관리자가 미출근 근무자를 일괄 노쇼로 표시
export const callableBatchSetNoShow = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const {businessId, entries} = request.data as {businessId: string; entries: NoShowEntry[]};
    if (!businessId || !Array.isArray(entries) || entries.length === 0) {
      throw new HttpsError("invalid-argument", "businessId와 entries가 필요합니다.");
    }
    if (entries.length > 200) {
      throw new HttpsError("invalid-argument", "한 번에 최대 200건까지 처리 가능합니다.");
    }

    const callerUid = request.auth.uid;
    // [SEC-ROLE] assertBizAdmin: businesses.adminIds 기준 검증 — role="ADMIN" 오기재 수정
    await assertBizAdmin(callerUid, businessId);

    const now = admin.firestore.FieldValue.serverTimestamp();
    const batch = db.batch();
    const skipped: string[] = [];

    // 서버 상태 사전 확인 — transferred 건 보호
    await Promise.all(entries.map(async (entry) => {
      const {applicationId, workDateMs, userId, businessName, workType, attendanceId} = entry;
      // [HIGH-02-FIX] workDateMs = Dart KST 자정 UTC ms → getFullYear()는 UTC 기준 → 전날 날짜
      // callableCheckIn/onAttendanceCreated와 동일한 KST 오프셋 패턴 적용
      const KST_OFFSET_MS = 9 * 60 * 60 * 1000;
      const dateKST = new Date(workDateMs + KST_OFFSET_MS);
      const dateStr = `${dateKST.getUTCFullYear()}${String(dateKST.getUTCMonth() + 1).padStart(2, "0")}${String(dateKST.getUTCDate()).padStart(2, "0")}`;
      const resolvedId = attendanceId ?? `${applicationId}_${dateStr}`;
      const ref = db.collection("attendance").doc(resolvedId);

      const snap = await ref.get();
      if (snap.exists && snap.data()!.wageStatus === "transferred") {
        skipped.push(resolvedId);
        return;
      }

      // [L3-FIX] 신규 노쇼 생성 시 applicationId → userId 교차검증
      //   — 악의적 관리자가 타 근로자 userId를 지정해 TrustScore 조작하는 것을 차단
      if (!attendanceId) {
        const appSnap = await db.collection("applications").doc(applicationId).get();
        if (!appSnap.exists || appSnap.data()!.uid !== userId) {
          skipped.push(resolvedId);
          return;
        }
      }

      const yearMonth = `${dateKST.getUTCFullYear()}-${String(dateKST.getUTCMonth() + 1).padStart(2, "0")}`;
      if (attendanceId) {
        batch.update(ref, {
          status: "NO_SHOW",
          yearMonth,
          wageStatus: "confirmed",
          finalWage: 0,
          updatedAt: now,
        });
      } else {
        batch.set(ref, {
          applicationId,
          userId,
          businessId,
          businessName,
          workDate: admin.firestore.Timestamp.fromMillis(workDateMs),
          yearMonth,
          workType,
          status: "NO_SHOW",
          wageStatus: "confirmed",
          finalWage: 0,
          isModified: false,
          modifyRequested: false,
          createdAt: now,
          updatedAt: now,
        }, {merge: true});
      }
    }));

    await batch.commit();
    return {success: true, processed: entries.length - skipped.length, skipped};
  }
);

// 노쇼 배치 취소 — wageTransferred 상태는 취소 불가
export const callableBatchCancelNoShow = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const {businessId, attendanceIds} = request.data as {businessId: string; attendanceIds: string[]};
    if (!businessId || !Array.isArray(attendanceIds) || attendanceIds.length === 0) {
      throw new HttpsError("invalid-argument", "businessId와 attendanceIds가 필요합니다.");
    }
    if (attendanceIds.length > 200) {
      throw new HttpsError("invalid-argument", "한 번에 최대 200건까지 처리 가능합니다.");
    }

    const callerUid = request.auth.uid;
    // [SEC-ROLE] assertBizAdmin: businesses.adminIds 기준 검증 — role="ADMIN" 오기재 수정
    await assertBizAdmin(callerUid, businessId);

    const now = admin.firestore.FieldValue.serverTimestamp();
    const batch = db.batch();
    const skipped: string[] = [];

    const snaps = await Promise.all(attendanceIds.map((id) => db.collection("attendance").doc(id).get()));
    for (const snap of snaps) {
      if (!snap.exists) continue;
      const data = snap.data()!;
      // [SEC] businessId 교차검증 — 다른 사업장 근태 조작 차단
      if (data.businessId !== businessId) { skipped.push(snap.id); continue; }
      if (data.wageStatus === "transferred") {
        skipped.push(snap.id);
        continue;
      }
      batch.update(snap.ref, {
        status: admin.firestore.FieldValue.delete(),
        wageStatus: "pending",
        wageDetail: admin.firestore.FieldValue.delete(),
        finalWage: admin.firestore.FieldValue.delete(),
        yearMonth: admin.firestore.FieldValue.delete(),
        updatedAt: now,
      });
    }

    await batch.commit();
    return {success: true, processed: attendanceIds.length - skipped.length, skipped};
  }
);

// 출퇴근 기록 배치 리셋 — wageCalculated/wageConfirmed/wageTransferred 건 서버에서 재차 제외
export const callableBatchResetAttendance = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const {businessId, attendanceIds} = request.data as {businessId: string; attendanceIds: string[]};
    if (!businessId || !Array.isArray(attendanceIds) || attendanceIds.length === 0) {
      throw new HttpsError("invalid-argument", "businessId와 attendanceIds가 필요합니다.");
    }
    if (attendanceIds.length > 200) {
      throw new HttpsError("invalid-argument", "한 번에 최대 200건까지 처리 가능합니다.");
    }

    const callerUid = request.auth.uid;
    // [SEC-ROLE] assertBizAdmin: businesses.adminIds 기준 검증 — role="ADMIN" 오기재 수정
    await assertBizAdmin(callerUid, businessId);

    const now = admin.firestore.FieldValue.serverTimestamp();
    const batch = db.batch();
    const skipped: string[] = [];

    const snaps = await Promise.all(attendanceIds.map((id) => db.collection("attendance").doc(id).get()));
    for (const snap of snaps) {
      if (!snap.exists) continue;
      const data = snap.data()!;
      // [SEC] businessId 교차검증 — 다른 사업장 근태 조작 차단
      if (data.businessId !== businessId) { skipped.push(snap.id); continue; }
      if (data.wageStatus === "calculated" ||
          data.wageStatus === "confirmed" ||
          data.wageStatus === "transferred") {
        skipped.push(snap.id);
        continue;
      }
      batch.update(snap.ref, {
        checkIn: admin.firestore.FieldValue.delete(),
        checkOut: admin.firestore.FieldValue.delete(),
        status: admin.firestore.FieldValue.delete(),
        workHours: admin.firestore.FieldValue.delete(),
        wageStatus: "pending",
        wageDetail: admin.firestore.FieldValue.delete(),
        yearMonth: admin.firestore.FieldValue.delete(),
        updatedAt: now,
      });
    }

    await batch.commit();
    return {success: true, processed: attendanceIds.length - skipped.length, skipped};
  }
);

// ─── 지급 예정일 계산 헬퍼 (PaymentDueDateCalculator Dart → TS 포팅) ─────────
function srvNextWeekday(from: Date, targetWeekday: number): Date {
  // Dart weekday: 1=월...7=일. JS getDay(): 0=일,1=월...6=토 → 1=월...7=일로 변환
  const jsDay = from.getDay() === 0 ? 7 : from.getDay();
  const diff = ((targetWeekday - jsDay) + 7) % 7;
  const d = new Date(from);
  d.setDate(d.getDate() + diff);
  return d;
}
function srvNextMonthlyDay(from: Date, targetDay: number): Date {
  const lastOfMonth = new Date(from.getFullYear(), from.getMonth() + 1, 0).getDate();
  const clampedDay = Math.min(targetDay, lastOfMonth);
  const thisMonthDue = new Date(from.getFullYear(), from.getMonth(), clampedDay);
  if (thisMonthDue >= from) return thisMonthDue;
  const nextMonth = new Date(from.getFullYear(), from.getMonth() + 1, 1);
  const lastOfNext = new Date(nextMonth.getFullYear(), nextMonth.getMonth() + 1, 0).getDate();
  return new Date(nextMonth.getFullYear(), nextMonth.getMonth(), Math.min(targetDay, lastOfNext));
}
function srvCalculatePaymentDueDate(
  payScheduleType: string | undefined,
  payScheduleDay: number | undefined,
  workDate: Date
): Date | null {
  const base = new Date(workDate.getFullYear(), workDate.getMonth(), workDate.getDate());
  switch (payScheduleType) {
    case "same_day": return base;
    case "next_day": { const d = new Date(base); d.setDate(d.getDate() + 1); return d; }
    case "weekly": return srvNextWeekday(base, Math.max(1, Math.min(7, payScheduleDay ?? 5)));
    case "monthly": return srvNextMonthlyDay(base, Math.max(1, Math.min(31, payScheduleDay ?? 25)));
    default: return null;
  }
}

// ─── callableConfirmFinalWage ─────────────────────────────────────────────────
// [V5-FIX] 급여 마감 CF 이전 — confirmedAt serverTimestamp 강제, confirmedBy 서버 강제
// 클라이언트 _closeWages 트랜잭션에서 confirmedAt: DateTime.now() 클라이언트 시계 위조 가능 차단.
// paymentDueDate 계산도 서버에서 처리 (클라이언트 시각 기반 계산 제거).
export const callableConfirmFinalWage = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const {businessId, attendanceIds} = request.data as {businessId: string; attendanceIds: string[]};
    if (!businessId || !Array.isArray(attendanceIds) || attendanceIds.length === 0) {
      throw new HttpsError("invalid-argument", "businessId와 attendanceIds가 필요합니다.");
    }
    if (attendanceIds.length > 100) {
      throw new HttpsError("invalid-argument", "한 번에 최대 100건까지 처리 가능합니다.");
    }

    const callerUid = request.auth.uid;
    // [SEC-ROLE] assertBizAdmin: businesses.adminIds 기준 검증
    await assertBizAdmin(callerUid, businessId);

    const now = admin.firestore.FieldValue.serverTimestamp();
    let successCount = 0;
    const skipped: string[] = [];

    for (const id of attendanceIds) {
      const ref = db.collection("attendance").doc(id);
      try {
        const result = await db.runTransaction(async (tx) => {
          const snap = await tx.get(ref);
          if (!snap.exists) return "skip";
          const data = snap.data()!;
          // [SEC] businessId 교차검증
          if (data.businessId !== businessId) return "skip";
          // 이미 마감됐거나 송금완료이면 멱등 skip (클라이언트와 동일 동작)
          if (data.wageStatus === "confirmed" || data.wageStatus === "transferred") return "already_closed";
          // wageCalculated 상태만 마감 가능
          if (data.wageStatus !== "calculated") return "skip";

          const existingWd = (data.wageDetail ?? {}) as Record<string, unknown>;
          const confirmedWageDetail = {
            ...existingWd,
            confirmedBy: callerUid,
            // serverTimestamp는 wageDetail 맵 내부에 사용할 수 없어 ISO 문자열로 저장
            // (Firestore: 배열·맵 내부 serverTimestamp 미지원 — D-M1 주석 참고)
            // CF 서버 시각(admin SDK)으로 고정 → 클라이언트 시계 위조 차단
            confirmedAt: admin.firestore.Timestamp.now(),
          };

          // paymentDueDate 서버 계산 (Dart PaymentDueDateCalculator 재구현)
          const workDate = (data.workDate as admin.firestore.Timestamp)?.toDate?.() ?? new Date();
          const payScheduleType = existingWd.payScheduleType as string | undefined;
          const payScheduleDay = existingWd.payScheduleDay as number | undefined;
          const paymentDueDate = srvCalculatePaymentDueDate(payScheduleType, payScheduleDay, workDate);

          const updateData: Record<string, unknown> = {
            wageStatus: "confirmed",
            finalConfirmedAt: now,
            confirmedBy: callerUid,
            wageDetail: confirmedWageDetail,
            updatedAt: now,
          };
          if (paymentDueDate !== null) {
            updateData["paymentDueDate"] = admin.firestore.Timestamp.fromDate(paymentDueDate);
          }

          tx.update(ref, updateData);
          return "ok";
        });

        if (result === "ok") {
          successCount++;
        } else {
          skipped.push(id);
        }
      } catch (e) {
        console.error(`마감 실패 (${id}):`, e);
        skipped.push(id);
      }
    }

    return {success: true, processed: successCount, skipped};
  }
);

// 마감 취소 — wageConfirmed → wageCalculated (트랜잭션으로 transferred 경합 방어)
export const callableCancelFinalConfirmation = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const {businessId, attendanceIds} = request.data as {businessId: string; attendanceIds: string[]};
    if (!businessId || !Array.isArray(attendanceIds) || attendanceIds.length === 0) {
      throw new HttpsError("invalid-argument", "businessId와 attendanceIds가 필요합니다.");
    }
    if (attendanceIds.length > 200) {
      throw new HttpsError("invalid-argument", "한 번에 최대 200건까지 처리 가능합니다.");
    }

    const callerUid = request.auth.uid;
    // [SEC-ROLE] assertBizAdmin: businesses.adminIds 기준 검증 — role="ADMIN" 오기재 수정
    await assertBizAdmin(callerUid, businessId);

    const now = admin.firestore.FieldValue.serverTimestamp();
    let successCount = 0;
    const skipped: string[] = [];

    // runTransaction: 읽기-쓰기 원자성 보장 — 동시 transferred 전환 경합 방어
    for (const id of attendanceIds) {
      const ref = db.collection("attendance").doc(id);
      try {
        const didUpdate = await db.runTransaction(async (tx) => {
          const snap = await tx.get(ref);
          if (!snap.exists) return false;
          const data = snap.data()!;
          // [SEC] businessId 교차검증 — 다른 사업장 근태 조작 차단
          if (data.businessId !== businessId) return false;
          if (data.wageStatus === "transferred" || data.wageStatus !== "confirmed") return false;

          const existingDetail = (data.wageDetail ?? {}) as Record<string, unknown>;
          const updatedDetail: Record<string, unknown> = {...existingDetail};
          delete updatedDetail.confirmedBy;
          delete updatedDetail.confirmedAt;

          tx.update(ref, {
            wageStatus: "calculated",
            wageDetail: Object.keys(updatedDetail).length > 0 ? updatedDetail : admin.firestore.FieldValue.delete(),
            finalConfirmedAt: admin.firestore.FieldValue.delete(),
            // [V3-FIX] paymentDueDate 삭제 — 클라이언트 _reverseCloseWages와 불일치 해소
            paymentDueDate: admin.firestore.FieldValue.delete(),
            updatedAt: now,
          });
          return true;
        });
        if (didUpdate) {
          successCount++;
        } else {
          skipped.push(id);
        }
      } catch (e) {
        console.error(`마감 취소 실패 (${id}):`, e);
        skipped.push(id);
      }
    }

    return {success: true, processed: successCount, skipped};
  }
);

// ─── callableWageCancel ──────────────────────────────────────────────────────
// [WAGE-CANCEL-FIX] 급여 확정 취소 CF — wageCalculated → wagePending
// 클라이언트 _processWageCancel 트랜잭션을 CF Admin SDK로 이전.
// 이전 이유:
//  1. 클라이언트 트랜잭션에 assertBizAdmin 없음 — rules만으로 사업장 교차검증
//  2. wageStatus: pending 직접 write → CF 이전으로 서버 강제 가능
export const callableWageCancel = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const {businessId, attendanceId} = request.data as {businessId: string; attendanceId: string};
    if (!businessId || !attendanceId) {
      throw new HttpsError("invalid-argument", "businessId와 attendanceId가 필요합니다.");
    }

    const callerUid = request.auth.uid;
    // [SEC-ROLE] assertBizAdmin: businesses.adminIds 기준 검증
    await assertBizAdmin(callerUid, businessId);

    const attRef = db.collection("attendance").doc(attendanceId);
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(attRef);
      if (!snap.exists) throw new HttpsError("not-found", "출근 기록을 찾을 수 없습니다.");
      const data = snap.data()!;
      // [SEC] businessId 교차검증 — 다른 사업장 근태 조작 차단
      if (data.businessId !== businessId) {
        throw new HttpsError("permission-denied", "접근 권한이 없습니다.");
      }
      // wageConfirmed/wageTransferred 상태는 취소 불가
      if (data.wageStatus === "confirmed" || data.wageStatus === "transferred") {
        throw new HttpsError("failed-precondition", "이미 마감된 급여입니다. 마감 취소 기능을 사용하세요.");
      }
      if (data.wageStatus !== "calculated") {
        throw new HttpsError("failed-precondition", `현재 상태(${data.wageStatus})에서는 취소할 수 없습니다.`);
      }

      tx.update(attRef, {
        wageStatus: "pending",
        finalWage: admin.firestore.FieldValue.delete(),
        wageDetail: admin.firestore.FieldValue.delete(),
        // yearMonth 삭제 — pending 복귀 시 _getPrevGrossTotal 집계 제외, stale 필드 방지
        yearMonth: admin.firestore.FieldValue.delete(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    return {success: true};
  }
);

// ─── callableChangeApplicationWorkType ──────────────────────────────────────
// [WORK-TYPE-CF] 파트(업무유형) 변경 CF — Trust Boundary Charter 카운터 증감 필수
// 클라이언트 changeApplicationWorkType() 교체 대상:
//  1. workTypeCounts/workTypeConfirmedCounts FieldValue.increment → CF 서버 강제
//  2. attendance wageStatus: pending 직접 write → BulkWriter로 교체
//  3. assertBizAdmin 교차검증 추가
export const callableChangeApplicationWorkType = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const {
      applicationId, businessId, newWorkType, newWage,
      newWorkDetailId, newWageType, newWorkTypeIcon, newWorkTypeColor, newWorkTypeBackgroundColor,
    } = request.data as {
      applicationId: string;
      businessId: string;
      newWorkType: string;
      newWage: number;
      newWorkDetailId?: string;
      newWageType?: string;
      newWorkTypeIcon?: string;
      newWorkTypeColor?: string;
      newWorkTypeBackgroundColor?: string;
    };

    if (!applicationId || !businessId || !newWorkType || typeof newWage !== "number") {
      throw new HttpsError("invalid-argument", "필수 파라미터가 누락됐습니다.");
    }
    if (newWage < 0 || !Number.isInteger(newWage) || newWage > 100_000_000) {
      throw new HttpsError("invalid-argument", "임금 값이 유효하지 않습니다.");
    }

    const callerUid = request.auth.uid;
    await assertBizAdmin(callerUid, businessId);

    // 1. application 조회 + businessId 교차검증
    const appRef = db.collection("applications").doc(applicationId);
    const appSnap = await appRef.get();
    if (!appSnap.exists) throw new HttpsError("not-found", "지원서를 찾을 수 없습니다.");
    const appData = appSnap.data()!;
    if (appData.businessId !== businessId) {
      throw new HttpsError("permission-denied", "해당 사업장의 지원서가 아닙니다.");
    }

    const currentWorkType = (appData.selectedWorkType as string) ?? "";
    const currentWage = (appData.wage as number) ?? 0;
    const currentStatus = (appData.status as string) ?? "";
    const toId = appData.toId as string | undefined;
    const slotId = appData.slotId as string | undefined;
    const uid = (appData.uid as string) ?? "";
    const bizName = (appData.businessName as string) ?? "";
    const workDateTs = appData.workDate as admin.firestore.Timestamp | undefined;

    if (currentWorkType === newWorkType) {
      throw new HttpsError("failed-precondition", "동일한 업무유형입니다.");
    }

    // 2. attendance 쿼리 (calculated + confirmed 병렬)
    const [calcSnap, confSnap] = await Promise.all([
      db.collection("attendance")
        .where("applicationId", "==", applicationId)
        .where("businessId", "==", businessId)
        .where("wageStatus", "==", "calculated")
        .get(),
      db.collection("attendance")
        .where("applicationId", "==", applicationId)
        .where("businessId", "==", businessId)
        .where("wageStatus", "==", "confirmed")
        .get(),
    ]);
    const attDocs = [...calcSnap.docs, ...confSnap.docs];

    // 3. employment_contracts 쿼리 (장기 직접 → 단기 번들 fallback)
    let contractSnap: admin.firestore.QueryDocumentSnapshot | null = null;
    const contractQ1 = await db.collection("employment_contracts")
      .where("applicationId", "==", applicationId)
      .where("businessId", "==", businessId)
      .limit(1)
      .get();
    if (contractQ1.docs.length > 0) {
      contractSnap = contractQ1.docs[0];
    } else {
      const contractQ2 = await db.collection("employment_contracts")
        .where("applicationIds", "array-contains", applicationId)
        .where("businessId", "==", businessId)
        .limit(1)
        .get();
      if (contractQ2.docs.length > 0) contractSnap = contractQ2.docs[0];
    }

    // 4. 1차 WriteBatch: application + slot/TO 카운터 + contract
    const batch = db.batch();

    const appUpdate: Record<string, unknown> = {
      selectedWorkType: newWorkType,
      wage: newWage,
      originalWorkType: appData.originalWorkType ?? currentWorkType,
      originalWage: appData.originalWage ?? currentWage,
      changedAt: admin.firestore.FieldValue.serverTimestamp(),
      changedBy: callerUid,
    };
    if (newWorkDetailId !== undefined) appUpdate.workDetailId = newWorkDetailId;
    if (newWageType !== undefined) appUpdate.wageType = newWageType;
    if (newWorkTypeIcon !== undefined) appUpdate.workTypeIcon = newWorkTypeIcon;
    if (newWorkTypeColor !== undefined) appUpdate.workTypeColor = newWorkTypeColor;
    if (newWorkTypeBackgroundColor !== undefined) appUpdate.workTypeBackgroundColor = newWorkTypeBackgroundColor;
    batch.update(appRef, appUpdate);

    // slot 카운터 (단기TO — slotId 있음)
    const CONFIRMED_STATUSES = new Set(["CONFIRMED", "CONTRACT_PENDING"]);
    if (toId && slotId) {
      const slotRef = db.collection("tos").doc(toId).collection("slots").doc(slotId);
      if (CONFIRMED_STATUSES.has(currentStatus)) {
        batch.update(slotRef, {
          [`workTypeCounts.${currentWorkType}.confirmedCount`]: admin.firestore.FieldValue.increment(-1),
          [`workTypeCounts.${newWorkType}.confirmedCount`]: admin.firestore.FieldValue.increment(1),
        });
      } else if (currentStatus === "PENDING") {
        batch.update(slotRef, {
          [`workTypeCounts.${currentWorkType}.pendingCount`]: admin.firestore.FieldValue.increment(-1),
          [`workTypeCounts.${newWorkType}.pendingCount`]: admin.firestore.FieldValue.increment(1),
        });
      }
    }

    // TO 카운터 (장기TO — slotId 없음, confirmed 상태)
    if (toId && !slotId && CONFIRMED_STATUSES.has(currentStatus)) {
      const toRef = db.collection("tos").doc(toId);
      batch.update(toRef, {
        [`workTypeConfirmedCounts.${currentWorkType}`]: admin.firestore.FieldValue.increment(-1),
        [`workTypeConfirmedCounts.${newWorkType}`]: admin.firestore.FieldValue.increment(1),
      });
    }

    // contract 업데이트
    if (contractSnap) {
      const contractData = contractSnap.data();
      const contractUpdate: Record<string, unknown> = {workType: newWorkType, wage: newWage};
      if (newWageType !== undefined) contractUpdate.wageType = newWageType;

      // pending_employer 상태에서만 slots 배열 내 wage/wageType 수정
      if (contractData.status === "pending_employer") {
        const rawSlots = (contractData.slots as unknown[]) ?? [];
        if (rawSlots.length > 0) {
          contractUpdate.slots = rawSlots.map((s) => {
            const slot = {...(s as Record<string, unknown>)};
            if (slot.applicationId === applicationId) {
              slot.wage = newWage;
              if (newWageType !== undefined) slot.wageType = newWageType;
            }
            return slot;
          });
        }
      }
      batch.update(contractSnap.ref, contractUpdate);
    }

    await batch.commit();

    // 5. 2차 attendance BulkWriter — wagePending 초기화 (500+건 대응)
    if (attDocs.length > 0) {
      const bw = db.bulkWriter();
      for (const attDoc of attDocs) {
        bw.update(attDoc.ref, {
          wageStatus: "pending",
          finalWage: admin.firestore.FieldValue.delete(),
          wageDetail: admin.firestore.FieldValue.delete(),
          yearMonth: admin.firestore.FieldValue.delete(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
      await bw.close();
    }

    // 6. 알림 — 지원자에게 파트 변경 알림 (비동기, 실패 허용)
    if (uid && workDateTs) {
      const workDate = workDateTs.toDate();
      const formattedWage = newWage.toString().replace(/(\d{1,3})(?=(\d{3})+(?!\d))/g, "$1,");
      const dateStr = `${workDate.getMonth() + 1}/${workDate.getDate()}`;
      db.collection("notifications").add({
        userId: uid,
        type: "workTypeChanged",
        title: "파트 변경",
        body: `${bizName}에서 귀하의 파트가 변경되었습니다.\n${currentWorkType} → ${newWorkType} (${formattedWage}원)\n근무일: ${dateStr}`,
        data: {applicationId, businessId, action: "applicationDetail"},
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        readAt: null,
      }).catch((err) => console.error("[callableChangeApplicationWorkType] 알림 실패:", err));
    }

    return {success: true, attendanceResetCount: attDocs.length};
  }
);

// ═══════════════════════════════════════════════════════════
// H-1 MEDIUM: 출근/퇴근/시간조정/adminConfirmed CF 이전
// ═══════════════════════════════════════════════════════════

const VALID_ATTENDANCE_STATUS = new Set(["present", "late", "early_leave", "absent", "noshow"]);

interface CheckInEntry {
  applicationId: string;
  workDateMs: number;
  userId: string;
  businessId: string;
  businessName: string;
  workType: string;
  status: string;
  checkInMs: number; // checkIn DateTime 밀리초
  attendanceId?: string; // 기존 레코드 업데이트 시
}

// 출근 배치 처리 — confirmed/transferred 건 서버 재검증 후 skip
export const callableBatchCheckIn = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const {businessId, entries} = request.data as {businessId: string; entries: CheckInEntry[]};
    if (!businessId || !Array.isArray(entries) || entries.length === 0) {
      throw new HttpsError("invalid-argument", "businessId와 entries가 필요합니다.");
    }
    if (entries.length > 200) {
      throw new HttpsError("invalid-argument", "한 번에 최대 200건까지 처리 가능합니다.");
    }

    const callerUid = request.auth.uid;
    // [SEC-ROLE] assertBizAdmin: businesses.adminIds 기준 검증 — role="ADMIN" 오기재 수정
    await assertBizAdmin(callerUid, businessId);

    const now = admin.firestore.FieldValue.serverTimestamp();
    let successCount = 0;

    for (const entry of entries) {
      const {applicationId, workDateMs, userId, businessName, workType, status, checkInMs, attendanceId} = entry;
      if (!VALID_ATTENDANCE_STATUS.has(status)) {
        console.error(`출근 처리 건너뜀 — 유효하지 않은 status: ${status} (${applicationId})`);
        continue;
      }
      // [HIGH-02-FIX] workDateMs = Dart KST 자정 UTC ms → getFullYear()는 UTC 기준 → 전날 날짜
      // callableCheckIn과 동일한 KST 오프셋 패턴으로 docId 날짜 통일
      const KST_OFFSET_MS = 9 * 60 * 60 * 1000;
      const workDateKST = new Date(workDateMs + KST_OFFSET_MS);
      const workDate = new Date(workDateMs);
      const checkInTs = admin.firestore.Timestamp.fromMillis(checkInMs);

      try {
        if (attendanceId) {
          // 서버 상태 확인 — confirmed/transferred 건은 출근 시간 수정 불가
          const snap = await db.collection("attendance").doc(attendanceId).get();
          if (snap.exists) {
            const snapData = snap.data()!;
            // [SEC] businessId 교차검증 — 다른 사업장 근태 조작 차단
            if (snapData.businessId !== businessId) continue;
            const ws = snapData.wageStatus as string | undefined;
            if (ws === "confirmed" || ws === "transferred") continue;
          }
          await db.collection("attendance").doc(attendanceId).update({
            checkIn: checkInTs,
            checkInMethod: "manual",
            status,
            isModified: true,
            modifiedAt: now,
            modifiedBy: callerUid,
            updatedAt: now,
          });
        } else {
          // 신규 출근 기록 — wageStatus='pending' 고정
          // [L3-FIX] applicationId → userId 교차검증 — 타 근로자 UID 지정으로 TrustScore 조작 차단
          const appVerifySnap = await db.collection("applications").doc(applicationId).get();
          if (!appVerifySnap.exists || appVerifySnap.data()!.uid !== userId) {
            console.error(`출근 처리 건너뜀 — userId 불일치 (${applicationId})`);
            continue;
          }
          const dateStr = `${workDateKST.getUTCFullYear()}${String(workDateKST.getUTCMonth() + 1).padStart(2, "0")}${String(workDateKST.getUTCDate()).padStart(2, "0")}`;
          const docId = `${applicationId}_${dateStr}`;
          await db.collection("attendance").doc(docId).set({
            applicationId,
            userId,
            businessId,
            businessName,
            workDate: admin.firestore.Timestamp.fromDate(workDate),
            workType,
            checkIn: checkInTs,
            checkInMethod: "manual",
            status,
            isModified: false,
            modifyRequested: false,
            wageStatus: "pending",
            createdAt: now,
            updatedAt: now,
          }, {merge: true});
        }
        successCount++;
      } catch (e) {
        console.error(`출근 처리 실패 (${applicationId}):`, e);
      }
    }

    return {success: true, processed: successCount, total: entries.length};
  }
);

interface CheckOutEntry {
  attendanceId: string;
  checkOutMs: number;
  workHours: number;
  status: string;
  resetWageDetail: boolean;
}

// 퇴근 배치 처리 — transferred 건 서버 재검증, resetWageDetail 시 트랜잭션으로 TOCTOU 방어
export const callableBatchCheckOut = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const {businessId, entries} = request.data as {businessId: string; entries: CheckOutEntry[]};
    if (!businessId || !Array.isArray(entries) || entries.length === 0) {
      throw new HttpsError("invalid-argument", "businessId와 entries가 필요합니다.");
    }
    if (entries.length > 200) {
      throw new HttpsError("invalid-argument", "한 번에 최대 200건까지 처리 가능합니다.");
    }

    const callerUid = request.auth.uid;
    // [SEC-ROLE] assertBizAdmin: businesses.adminIds 기준 검증 — role="ADMIN" 오기재 수정
    await assertBizAdmin(callerUid, businessId);

    const now = admin.firestore.FieldValue.serverTimestamp();
    let successCount = 0;
    const skipped: string[] = [];

    for (const entry of entries) {
      const {attendanceId, checkOutMs, workHours, status, resetWageDetail} = entry;
      // [L4-FIX] workHours 상한 검증 — 관리자가 24시간 초과 근무시간 입력으로 임금 부풀리기 차단
      if (typeof workHours === "number" && (workHours < 0 || workHours > 24)) {
        skipped.push(attendanceId);
        continue;
      }
      if (!VALID_ATTENDANCE_STATUS.has(status)) {
        console.error(`퇴근 처리 건너뜀 — 유효하지 않은 status: ${status} (${attendanceId})`);
        skipped.push(attendanceId);
        continue;
      }
      const ref = db.collection("attendance").doc(attendanceId);
      try {
        if (resetWageDetail) {
          // wageCalculated → pending 리셋 시 트랜잭션: 동시에 confirmed/transferred 전환 방어
          await db.runTransaction(async (tx) => {
            const snap = await tx.get(ref);
            if (!snap.exists) { skipped.push(attendanceId); return; }
            const snapData = snap.data()!;
            // [SEC] businessId 교차검증 — 다른 사업장 근태 조작 차단
            if (snapData.businessId !== businessId) { skipped.push(attendanceId); return; }
            const ws = snapData.wageStatus as string | undefined;
            if (ws === "confirmed" || ws === "transferred") { skipped.push(attendanceId); return; }
            tx.update(ref, {
              checkOut: admin.firestore.Timestamp.fromMillis(checkOutMs),
              checkOutMethod: "manual",
              workHours,
              status,
              wageStatus: "pending",
              wageDetail: admin.firestore.FieldValue.delete(),
              updatedAt: now,
            });
          });
        } else {
          // 단순 퇴근 기록 — transferred 건만 보호
          const snap = await ref.get();
          if (snap.exists) {
            const snapData = snap.data()!;
            // [SEC] businessId 교차검증 — 다른 사업장 근태 조작 차단
            if (snapData.businessId !== businessId) { skipped.push(attendanceId); continue; }
            if (snapData.wageStatus === "transferred") { skipped.push(attendanceId); continue; }
          }
          await ref.update({
            checkOut: admin.firestore.Timestamp.fromMillis(checkOutMs),
            checkOutMethod: "manual",
            workHours,
            status,
            updatedAt: now,
          });
        }
        if (!skipped.includes(attendanceId)) successCount++;
      } catch (e) {
        console.error(`퇴근 처리 실패 (${attendanceId}):`, e);
        skipped.push(attendanceId);
      }
    }

    return {success: true, processed: successCount, skipped};
  }
);

interface AdjustEntry {
  attendanceId: string;
  checkInMs?: number;
  checkOutMs?: number;
  workHours?: number;
  status: string;
  resetWageDetail: boolean;
}

// ── callableRejectApplication ─────────────────────────────────
// 지원서 거절 (PENDING → REJECTED) — rejectedBy 서버 강제, statusHistory.at 서버 타임스탬프
// 클라이언트가 rejectedBy에 다른 관리자 UID를 위조해 책임 전가하는 취약점 차단
// [CF-ONLY] PENDING → REJECTED 전이: callableRejectApplication(Admin SDK) 전용
// Input : { applicationId, message? }
// Output: { success, alreadyRejected? }
export const callableRejectApplication = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;

    const {applicationId, message} = request.data as {applicationId?: string; message?: string};
    if (!applicationId || typeof applicationId !== "string" || applicationId.trim() === "") {
      throw new HttpsError("invalid-argument", "applicationId가 필요합니다.");
    }

    const appRef = db.collection("applications").doc(applicationId);
    const appSnap = await appRef.get();
    if (!appSnap.exists) throw new HttpsError("not-found", "지원서를 찾을 수 없습니다.");
    const appData = appSnap.data()!;

    const businessId = appData.businessId as string | undefined;
    if (!businessId) throw new HttpsError("invalid-argument", "businessId가 없는 지원서입니다.");

    await assertBizAdmin(callerUid, businessId);

    const prevStatus = (appData.status as string | undefined) ?? "";

    // 확정 상태는 거절 불가 — 취소 처리 사용
    if (CONFIRMED_STATUSES.includes(prevStatus)) {
      throw new HttpsError("failed-precondition", "확정된 지원서는 거절할 수 없습니다. 취소 처리를 이용해주세요.");
    }
    // 이미 거절된 경우 멱등 처리
    if (prevStatus === "REJECTED") {
      return {success: true, alreadyRejected: true};
    }

    const toId = appData.toId as string | undefined;
    const slotId = appData.slotId as string | undefined;
    const uid = appData.uid as string | undefined;
    const businessName = appData.businessName as string | undefined;
    const selectedWorkType = appData.selectedWorkType as string | undefined;
    const workDateTs = appData.workDate as admin.firestore.Timestamp | undefined;

    // 트랜잭션: TOCTOU 방지 + 원자적 상태 전이 + pendingCount 보정
    await db.runTransaction(async (tx) => {
      const freshSnap = await tx.get(appRef);
      if (!freshSnap.exists) throw new HttpsError("not-found", "지원서를 찾을 수 없습니다.");
      const freshStatus = (freshSnap.data()!.status as string | undefined) ?? "";

      if (CONFIRMED_STATUSES.includes(freshStatus)) {
        throw new HttpsError("failed-precondition", "확정된 지원서는 거절할 수 없습니다. 취소 처리를 이용해주세요.");
      }
      if (freshStatus === "REJECTED") return; // 이미 처리됨 — 멱등

      const historyEntry: Record<string, unknown> = {
        status: "REJECTED",
        at: Timestamp.now(), // CF 서버 시간 — 클라이언트 기기 시간 위조 불가
        by: callerUid,       // 서버 강제 — 위조 불가
        action: "REJECT",
        ...(message ? {reason: message} : {}),
      };

      const updates: Record<string, unknown> = {
        status: "REJECTED",
        rejectedAt: admin.firestore.FieldValue.serverTimestamp(),
        rejectedBy: callerUid, // 서버 강제 — 클라이언트 위조 불가
        statusHistory: admin.firestore.FieldValue.arrayUnion(historyEntry),
        ...(message ? {rejectMessage: message} : {}),
      };
      tx.update(appRef, updates);

      // PENDING → REJECTED: pendingCount 보정
      if (freshStatus === "PENDING" && toId) {
        tx.update(db.collection("tos").doc(toId), {
          totalPending: admin.firestore.FieldValue.increment(-1),
        });
        if (slotId) {
          tx.update(db.collection("tos").doc(toId).collection("slots").doc(slotId), {
            pendingCount: admin.firestore.FieldValue.increment(-1),
          });
        }
      }
    });

    // 알림 발송 (fire-and-forget — 알림 실패가 거절 처리를 막지 않음)
    if (uid) {
      const month = workDateTs ? workDateTs.toDate().getMonth() + 1 : 0;
      const day = workDateTs ? workDateTs.toDate().getDate() : 0;
      const rejectReasonSuffix = message ? `\n사유: ${message}` : "";
      const dateSuffix = workDateTs ? `\n근무일: ${month}/${day}` : "";
      const body = `${businessName ?? ""}의 ${selectedWorkType ?? ""} 지원이 거절되었습니다.${rejectReasonSuffix}${dateSuffix}`;

      db.collection("users").doc(uid).collection("notifications").add({
        userId: uid,
        type: "applicationRejected",
        title: "지원 거절",
        body,
        data: {
          applicationId,
          businessId,
          action: "applicationDetail",
        },
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      }).catch((e) => console.error("[callableRejectApplication] 알림 발송 실패:", e));
    }

    return {success: true};
  }
);

// ── callableConfirmApplication ───────────────────────────────
// 지원서 확정 (PENDING → CONTRACT_PENDING) — 서버 사이드 원자적 처리
// [MED-3 해결] workTypeConfirmedCounts 위조 완전 차단 — 클라이언트 트랜잭션 제거
// Input : { applicationId, message? }
// Output: { success, alreadyConfirmed, capacityWarning?, workEndDate?, workDays? }
export const callableConfirmApplication = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;

    const {applicationId, message} = request.data as {applicationId: string; message?: string};
    if (!applicationId || typeof applicationId !== "string") {
      throw new HttpsError("invalid-argument", "applicationId가 필요합니다.");
    }

    const appRef = db.collection("applications").doc(applicationId);
    const appSnap = await appRef.get();
    if (!appSnap.exists) throw new HttpsError("not-found", "지원서를 찾을 수 없습니다.");
    const appDataPre = appSnap.data()!;
    const businessId = appDataPre.businessId as string;

    // [SEC-ROLE] 사업장 관리자 권한 검증
    await assertBizAdmin(callerUid, businessId);

    let alreadyConfirmed = false;

    // ── 1. 트랜잭션: 상태 체크 + CAPACITY-GUARD + CONTRACT_PENDING 선점 ──
    await db.runTransaction(async (tx) => {
      const fresh = await tx.get(appRef);
      if (!fresh.exists) throw new HttpsError("not-found", "지원서를 찾을 수 없습니다.");
      const status = fresh.data()!.status as string;

      if (status === "CONFIRMED" || status === "CONTRACT_PENDING") {
        alreadyConfirmed = true;
        return;
      }
      if (status === "CANCELED") throw new HttpsError("failed-precondition", "취소된 지원서는 확정할 수 없습니다.");
      if (status === "AUTO_CANCELED") throw new HttpsError("failed-precondition", "자동 취소된 지원서는 확정할 수 없습니다.");
      if (status === "REJECTED") throw new HttpsError("failed-precondition", "거절된 지원서는 확정할 수 없습니다.");

      const fd = fresh.data()!;
      const toIdFresh = fd.toId as string | undefined;
      const slotIdFresh = fd.slotId as string | undefined;
      const selectedWorkType = fd.selectedWorkType as string | undefined;

      // [CAPACITY-GUARD] 정원 서버 검증 + 낙관적 잠금
      if (toIdFresh && selectedWorkType) {
        if (slotIdFresh) {
          const slotRef = db.collection("tos").doc(toIdFresh).collection("slots").doc(slotIdFresh);
          const slotFresh = await tx.get(slotRef);
          if (slotFresh.exists) {
            const rawWDs = (slotFresh.data()!.workDetails as Record<string, unknown>[] | undefined) ?? [];
            for (const wd of rawWDs) {
              if (wd.workType === selectedWorkType) {
                const req = (wd.requiredCount as number | undefined) ?? 0;
                const counts = slotFresh.data()!.workTypeCounts as Record<string, Record<string, number>> | undefined;
                const conf = (counts?.[selectedWorkType]?.confirmedCount) ?? 0;
                if (req > 0 && conf >= req) {
                  throw new HttpsError("failed-precondition", `정원이 초과되었습니다. (필요: ${req}명, 현재: ${conf}명 확정)`);
                }
                break;
              }
            }
            // 낙관적 잠금 — 동시 확정 충돌 감지
            tx.update(slotRef, {[`workTypeCounts.${selectedWorkType}.confirmedCount`]: admin.firestore.FieldValue.increment(1)});
          }
        } else {
          const toRef = db.collection("tos").doc(toIdFresh);
          const toFresh = await tx.get(toRef);
          if (toFresh.exists) {
            const confCounts = toFresh.data()!.workTypeConfirmedCounts as Record<string, number> | undefined;
            const conf = (confCounts?.[selectedWorkType]) ?? 0;
            const rawWDs = (toFresh.data()!.workDetails as Record<string, unknown>[] | undefined) ?? [];
            for (const wd of rawWDs) {
              if (wd.workType === selectedWorkType) {
                const req = (wd.requiredCount as number | undefined) ?? 0;
                if (req > 0 && conf >= req) {
                  throw new HttpsError("failed-precondition", `정원이 초과되었습니다. (필요: ${req}명, 현재: ${conf}명 확정)`);
                }
                break;
              }
            }
            tx.update(toRef, {[`workTypeConfirmedCounts.${selectedWorkType}`]: admin.firestore.FieldValue.increment(1)});
          }
        }
      }

      tx.update(appRef, {
        status: "CONTRACT_PENDING",
        confirmedAt: admin.firestore.FieldValue.serverTimestamp(),
        confirmedBy: callerUid,
      });
    });

    if (alreadyConfirmed) return {success: true, alreadyConfirmed: true};

    // ── 2. 선점 후 최신 문서 재조회 ──
    const latestSnap = await appRef.get();
    if (!latestSnap.exists) throw new HttpsError("not-found", "지원서를 찾을 수 없습니다.");
    const latestData = latestSnap.data()!;

    const toId = latestData.toId as string | undefined;
    const slotId = latestData.slotId as string | undefined;
    const selectedWorkType = latestData.selectedWorkType as string | undefined;
    const uid = latestData.uid as string;
    const businessName = latestData.businessName as string;

    if (!toId) throw new HttpsError("invalid-argument", "toId가 없는 지원서입니다.");

    // ── 3. TO 로드 + workEndDate/workDays 계산 ──
    const toDoc = await db.collection("tos").doc(toId).get();
    const toData = toDoc.exists ? toDoc.data()! : undefined;

    const isLongTermApp = latestData.applicationType === "longTerm" ||
      (Array.isArray(latestData.workDays) && (latestData.workDays as string[]).length > 0);

    let computedWorkEndDate: admin.firestore.Timestamp | undefined;
    let computedWorkDays: string[] | undefined;

    if (isLongTermApp && !latestData.workEndDate && toData) {
      const startTs = (latestData.desiredStartDate ?? latestData.workDate) as admin.firestore.Timestamp;
      const periodType = toData.contractPeriodType as string | undefined;
      if (periodType && periodType !== "custom") {
        const d = new Date(startTs.toDate().getTime());
        if (periodType === "15days") d.setDate(d.getDate() + 15);
        else if (periodType === "1month") d.setMonth(d.getMonth() + 1);
        else if (periodType === "3months") d.setMonth(d.getMonth() + 3);
        else if (periodType === "6months") d.setMonth(d.getMonth() + 6);
        else if (periodType === "1year") d.setFullYear(d.getFullYear() + 1);
        computedWorkEndDate = admin.firestore.Timestamp.fromDate(d);
      } else if (toData.rangeEnd) {
        computedWorkEndDate = toData.rangeEnd as admin.firestore.Timestamp;
      }
    }
    if ((!latestData.workDays || (latestData.workDays as string[]).length === 0) &&
        Array.isArray(toData?.workDays) && (toData!.workDays as string[]).length > 0) {
      computedWorkDays = toData!.workDays as string[];
    }

    // ── 4. 슬롯 closed 체크 ──
    let capacityWarning: {workType: string; required: number; confirmed: number} | undefined;
    if (slotId) {
      const slotSnap = await db.collection("tos").doc(toId).collection("slots").doc(slotId).get();
      if (slotSnap.exists) {
        if (slotSnap.data()!.status === "closed") {
          try {
            await appRef.update({
              status: "PENDING",
              confirmedAt: admin.firestore.FieldValue.delete(),
              confirmedBy: admin.firestore.FieldValue.delete(),
            });
          } catch (_) { /* 롤백 실패 무시 */ }
          throw new HttpsError("failed-precondition", "이미 마감된 슬롯입니다. 슬롯을 재오픈 후 확정해주세요.");
        }
        if (selectedWorkType) {
          const rawWDs = (slotSnap.data()!.workDetails as Record<string, unknown>[] | undefined) ?? [];
          for (const wd of rawWDs) {
            if (wd.workType === selectedWorkType) {
              const req = (wd.requiredCount as number | undefined) ?? 0;
              const counts = slotSnap.data()!.workTypeCounts as Record<string, Record<string, number>> | undefined;
              const conf = (counts?.[selectedWorkType]?.confirmedCount) ?? 0;
              if (req > 0 && conf >= req) capacityWarning = {workType: selectedWorkType, required: req, confirmed: conf};
              break;
            }
          }
        }
      }
    } else if (toData && selectedWorkType) {
      const confCounts = toData.workTypeConfirmedCounts as Record<string, number> | undefined;
      const conf = (confCounts?.[selectedWorkType]) ?? 0;
      const rawWDs = (toData.workDetails as Record<string, unknown>[] | undefined) ?? [];
      for (const wd of rawWDs) {
        if (wd.workType === selectedWorkType) {
          const req = (wd.requiredCount as number | undefined) ?? 0;
          if (req > 0 && conf >= req) capacityWarning = {workType: selectedWorkType, required: req, confirmed: conf};
          break;
        }
      }
    }

    // ── 5. 배치: statusHistory + 카운터 업데이트 ──
    const batch2 = db.batch();

    const historyEntry: Record<string, unknown> = {
      status: "CONTRACT_PENDING",
      at: Timestamp.now(),
      by: callerUid,
      action: "CONFIRM",
    };
    const batchUpdate: Record<string, unknown> = {
      statusHistory: admin.firestore.FieldValue.arrayUnion(historyEntry),
    };
    if (message) batchUpdate.confirmMessage = message;
    if (computedWorkEndDate) batchUpdate.workEndDate = computedWorkEndDate;
    if (computedWorkDays) batchUpdate.workDays = computedWorkDays;
    batch2.update(appRef, batchUpdate);

    // TO 카운터: totalPending -1, totalConfirmed +1 (하나의 update로 합산)
    // [CRIT-02-FIX] workTypeConfirmedCounts는 트랜잭션에서 이미 처리됨 — 중복 증가 차단
    batch2.update(db.collection("tos").doc(toId), {
      totalPending: admin.firestore.FieldValue.increment(-1),
      totalConfirmed: admin.firestore.FieldValue.increment(1),
    });
    if (slotId) {
      batch2.update(db.collection("tos").doc(toId).collection("slots").doc(slotId), {
        pendingCount: admin.firestore.FieldValue.increment(-1),
        confirmedCount: admin.firestore.FieldValue.increment(1),
      });
    }

    try {
      await batch2.commit();
    } catch (batchErr) {
      try {
        await appRef.update({
          status: "PENDING",
          confirmedAt: admin.firestore.FieldValue.delete(),
          confirmedBy: admin.firestore.FieldValue.delete(),
        });
        console.warn("[confirmApplication] 배치 실패 → CONTRACT_PENDING 롤백 완료");
      } catch (rollbackErr) {
        console.error("[confirmApplication] CONTRACT_PENDING 롤백 실패 — 수동 해제 필요:", rollbackErr);
      }
      throw batchErr;
    }

    // ── 6. 슬롯 상태 재계산 (open ↔ full) ──
    if (slotId) {
      try {
        const slotRef2 = db.collection("tos").doc(toId).collection("slots").doc(slotId);
        await db.runTransaction(async (tx2) => {
          const s = await tx2.get(slotRef2);
          if (!s.exists || s.data()!.status === "closed" || s.data()!.isManualClosed === true) return;
          const confirmedNow = (s.data()!.confirmedCount as number | undefined) ?? 0;
          const wds = (s.data()!.workDetails as Record<string, unknown>[] | undefined) ?? [];
          const totalReq = wds.reduce((acc, d) => acc + ((d.requiredCount as number | undefined) ?? 0), 0);
          if (totalReq <= 0) return;
          const newStatus = confirmedNow >= totalReq ? "full" : "open";
          if (s.data()!.status !== newStatus) tx2.update(slotRef2, {status: newStatus});
        });
      } catch (e) {
        console.warn(`[confirmApplication] 슬롯 상태 재계산 실패 (${slotId}):`, e);
      }
    }

    // ── 7. 확정 알림 발송 (근무자) ──
    try {
      const workDateTs = latestData.workDate as admin.firestore.Timestamp | undefined;
      await db.collection("users").doc(uid).collection("notifications").add({
        userId: uid,
        type: "applicationConfirmed",
        title: "지원 확정",
        body: `[${businessName}] ${selectedWorkType ?? ""} 지원이 확정되었습니다.`,
        data: {
          applicationId,
          businessId,
          screen: "applicationDetail",
          ...(workDateTs ? {workDateMs: workDateTs.toMillis()} : {}),
        },
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (e) {
      console.warn("[confirmApplication] 확정 알림 발송 실패 (확정은 완료됨):", e);
    }

    const workDateTsForReturn = latestData.workDate as admin.firestore.Timestamp | undefined;
    const desiredStartTs = latestData.desiredStartDate as admin.firestore.Timestamp | undefined;
    return {
      success: true,
      alreadyConfirmed: false,
      capacityWarning: capacityWarning ?? null,
      appInfo: {
        toId,
        uid,
        businessId,
        businessName: businessName ?? "",
        startTime: (latestData.startTime as string | undefined) ?? "",
        endTime: (latestData.endTime as string | undefined) ?? "",
        workDateMs: workDateTsForReturn?.toMillis() ?? 0,
        isLongTerm: isLongTermApp,
        startDateMs: isLongTermApp
          ? ((desiredStartTs ?? workDateTsForReturn)?.toMillis() ?? 0)
          : null,
        workEndDateMs: computedWorkEndDate ? computedWorkEndDate.toMillis() : null,
        workDays: computedWorkDays ?? null,
      },
    };
  }
);

// 출퇴근 시간 일괄 조정 (트랜잭션: confirmed/transferred 건 서버 재검증 후 skip)
export const callableBatchAdjustAttendanceTime = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const {businessId, entries} = request.data as {businessId: string; entries: AdjustEntry[]};
    if (!businessId || !Array.isArray(entries) || entries.length === 0) {
      throw new HttpsError("invalid-argument", "businessId와 entries가 필요합니다.");
    }
    if (entries.length > 200) {
      throw new HttpsError("invalid-argument", "한 번에 최대 200건까지 처리 가능합니다.");
    }

    const callerUid = request.auth.uid;
    // [SEC-ROLE] assertBizAdmin: businesses.adminIds 기준 검증 — role="ADMIN" 오기재 수정
    await assertBizAdmin(callerUid, businessId);

    const now = admin.firestore.FieldValue.serverTimestamp();
    let successCount = 0;
    const skipped: string[] = [];

    for (const entry of entries) {
      const {attendanceId, checkInMs, checkOutMs, workHours, status, resetWageDetail} = entry;
      if (!VALID_ATTENDANCE_STATUS.has(status)) {
        console.error(`시간 조정 건너뜀 — 유효하지 않은 status: ${status} (${attendanceId})`);
        skipped.push(attendanceId);
        continue;
      }
      const attRef = db.collection("attendance").doc(attendanceId);
      try {
        await db.runTransaction(async (tx) => {
          const snap = await tx.get(attRef);
          if (!snap.exists) {
            skipped.push(attendanceId);
            return;
          }
          const snapData = snap.data()!;
          // [SEC] businessId 교차검증 — 다른 사업장 근태 조작 차단
          if (snapData.businessId !== businessId) {
            skipped.push(attendanceId);
            return;
          }
          const serverStatus = snapData.wageStatus as string | undefined;
          if (serverStatus === "confirmed" || serverStatus === "transferred") {
            skipped.push(attendanceId);
            return;
          }
          // [DESIGN-A-M3] 소급 수정 기간 제한: 90일 이내 기록만 수정 가능
          const recordTs = (snapData.workDate ?? snapData.checkIn) as admin.firestore.Timestamp | undefined;
          const recordDate = recordTs?.toDate();
          const ninetyDaysAgo = new Date(Date.now() - 90 * 24 * 60 * 60 * 1000);
          if (recordDate && recordDate < ninetyDaysAgo) {
            skipped.push(attendanceId);
            return;
          }
          const updates: Record<string, unknown> = {
            isModified: true,
            modifiedAt: now,
            modifiedBy: callerUid,
            updatedAt: now,
            status,
          };
          if (checkInMs != null) {
            updates["checkIn"] = admin.firestore.Timestamp.fromMillis(checkInMs);
            updates["checkInMethod"] = "manual";
          }
          if (checkOutMs != null) {
            updates["checkOut"] = admin.firestore.Timestamp.fromMillis(checkOutMs);
            updates["checkOutMethod"] = "manual";
          }
          if (workHours != null) updates["workHours"] = workHours;
          if (resetWageDetail) {
            updates["wageStatus"] = "pending";
            updates["wageDetail"] = admin.firestore.FieldValue.delete();
          }
          tx.update(attRef, updates);
        });
        // [QA-FIX] skipped 처리된 건(snap 미존재·businessId 불일치·confirmed) 제외
        if (!skipped.includes(attendanceId)) successCount++;
      } catch (e) {
        console.error(`시간 조정 실패 (${attendanceId}):`, e);
        skipped.push(attendanceId);
      }
    }

    return {success: true, processed: successCount, skipped};
  }
);

// adminConfirmed 배치 설정 — 관리자 내부 워크플로 플래그
export const callableBatchAdminConfirm = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const {businessId, attendanceIds, confirmed} = request.data as {
      businessId: string; attendanceIds: string[]; confirmed: boolean;
    };
    if (!businessId || !Array.isArray(attendanceIds) || attendanceIds.length === 0 || typeof confirmed !== "boolean") {
      throw new HttpsError("invalid-argument", "businessId, attendanceIds, confirmed가 필요합니다.");
    }
    if (attendanceIds.length > 200) {
      throw new HttpsError("invalid-argument", "한 번에 최대 200건까지 처리 가능합니다.");
    }

    const callerUid = request.auth.uid;
    // [SEC-ROLE] assertBizAdmin: businesses.adminIds 기준 검증 — role="ADMIN" 오기재 수정
    await assertBizAdmin(callerUid, businessId);

    const now = admin.firestore.FieldValue.serverTimestamp();
    const batch = db.batch();
    const skipped: string[] = [];

    // [SEC] businessId 교차검증을 위해 문서 조회 후 배치 구성
    const snaps = await Promise.all(attendanceIds.map((id) => db.collection("attendance").doc(id).get()));
    for (const snap of snaps) {
      if (!snap.exists) continue;
      // [SEC] 다른 사업장 근태에 adminConfirmed 플래그 설정 차단
      if (snap.data()!.businessId !== businessId) { skipped.push(snap.id); continue; }
      batch.update(snap.ref, {adminConfirmed: confirmed, updatedAt: now});
    }
    await batch.commit();
    return {success: true, processed: attendanceIds.length - skipped.length, skipped};
  }
);

// ═══════════════════════════════════════════════════════════
// 💸 급여 이체 완료 배치 처리 — confirmed→transferred 법적 상태 전이
// Trust Boundary Charter: 법적 상태 전이 → CF Admin SDK 필수
// 단건/복수 모두 이 CF로 처리 (attendanceIds에 단건만 전달 시 단건 처리)
// ═══════════════════════════════════════════════════════════

interface TransferNotificationPayload {
  userId: string;
  workerName: string;
  businessName: string;
  businessId: string;
  finalWage: number;
  applicationId?: string;
  // [MEDIUM-3] 실제 처리된 attendanceId에만 알림 발송 — 미전달 시 하위호환(전체 발송)
  attendanceId?: string;
}

export const callableMarkTransferredBatch = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;

    const {businessId, attendanceIds, transferNote, notifications} = request.data as {
      businessId: string;
      attendanceIds: string[];
      transferNote?: string;
      notifications?: TransferNotificationPayload[];
    };

    if (!businessId || typeof businessId !== "string") {
      throw new HttpsError("invalid-argument", "businessId가 필요합니다.");
    }
    if (!Array.isArray(attendanceIds) || attendanceIds.length === 0) {
      throw new HttpsError("invalid-argument", "attendanceIds가 필요합니다.");
    }
    if (attendanceIds.length > 200) {
      throw new HttpsError("invalid-argument", "최대 200건까지 처리 가능합니다.");
    }

    // [SEC-ROLE] assertBizAdmin: businesses.adminIds 기준 검증 — role="ADMIN" 오기재 수정
    await assertBizAdmin(callerUid, businessId);

    const now = admin.firestore.FieldValue.serverTimestamp();
    const skipped: string[] = [];
    let processed = 0;
    // [MEDIUM-3] 실제로 transferred 상태로 전환된 attendanceId 추적 — 알림 필터링용
    // 멱등 처리(already-transferred)는 포함하지 않아 중복 알림 방지
    const processedAttendanceIds = new Set<string>();

    // [E-M2] 단일 트랜잭션으로 read-then-write 원자화 — TOCTOU 방지
    // 200건 × 2 ops = 400 < Firestore 한도(500)
    await db.runTransaction(async (tx) => {
      const snaps = await Promise.all(
        attendanceIds.map(id => tx.get(db.collection("attendance").doc(id)))
      );

      for (let i = 0; i < attendanceIds.length; i++) {
        const id = attendanceIds[i];
        const snap = snaps[i];

        if (!snap.exists) {
          skipped.push(id);
          continue;
        }

        const data = snap.data()!;

        // businessId 교차 검증 — 타 사업장 기록 변조 방지
        if (data.businessId !== businessId) {
          skipped.push(id);
          continue;
        }

        const ws = data.wageStatus as string | undefined;

        // 이미 transferred: 멱등 처리 (성공으로 카운트)
        if (ws === "transferred") {
          processed++;
          continue;
        }

        // confirmed 상태만 transferred로 전환 가능
        if (ws !== "confirmed") {
          skipped.push(id);
          continue;
        }

        const updateData: Record<string, unknown> = {
          wageStatus: "transferred",
          transferDate: now,
          transferredBy: callerUid,
          updatedAt: now,
        };
        if (transferNote && transferNote.trim().length > 0) {
          updateData.transferNote = transferNote.trim();
        }

        tx.update(snap.ref, updateData);
        processedAttendanceIds.add(id); // 실제 전환된 ID 기록
        processed++;
      }
    });

    // 알림 발송 — 실패해도 메인 처리는 성공 유지
    // [MEDIUM-3] attendanceId 제공 시 실제 처리된 건만 발송, 미제공 시 전체 발송(하위호환)
    if (notifications && notifications.length > 0) {
      await Promise.allSettled(
        notifications
          .filter(n =>
            n.userId &&
            n.businessId === businessId &&
            (!n.attendanceId || processedAttendanceIds.has(n.attendanceId))
          )
          .map(n => {
            const body = `[${n.businessName ?? ""}] ${n.workerName ?? ""}님의 급여가 송금 처리되었습니다. 앱에서 확인하세요.`;
            return db.collection("users").doc(n.userId).collection("notifications").add({
              userId: n.userId,
              type: "wageTransferred",
              title: "급여 송금 완료",
              body,
              isRead: false,
              data: {
                businessId: n.businessId,
                screen: "wageTransferred",
                ...(n.applicationId ? {applicationId: n.applicationId} : {}),
              },
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          })
      );
    }

    return {success: true, processed, skipped};
  }
);

// ─── callableGetAdminTOs ──────────────────────────────────────────────────────
// tos 공고 목록 조회 — Admin SDK server-side businessId 교차검증
// [RULE-FIX-CF 2026-07-13] request.query.filters.businessId null 반환 문제를
//   CF로 근본 해결. assertBizAdmin으로 권한 검증 후 Admin SDK로 Firestore 쿼리.
// Input : businessId (단일) OR businessIds (복수), activeOnly?, closedOnly?
// Output: { items: [{id: string, ...toFields}] }
export const callableGetAdminTOs = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;
    const {businessId, businessIds: rawIds, activeOnly, closedOnly} =
      (request.data ?? {}) as {
        businessId?: string;
        businessIds?: string[];
        activeOnly?: boolean;
        closedOnly?: boolean;
      };

    // 슈퍼어드민 여부 확인
    const callerSnap = await db.collection("users").doc(callerUid).get();
    const isSuperAdmin = (callerSnap.data()?.role as string | undefined) === "SUPER_ADMIN";

    // businessId 목록 구성
    const ids: string[] = rawIds?.length
      ? rawIds
      : businessId ? [businessId] : [];

    if (!isSuperAdmin && ids.length === 0) {
      throw new HttpsError("invalid-argument", "businessId가 필요합니다.");
    }

    // 비슈퍼어드민: 각 businessId에 대해 권한 검증
    if (!isSuperAdmin) {
      await Promise.all(ids.map(id => assertBizAdmin(callerUid, id)));
    }

    const openStates   = ["ACTIVE", "FULL", "SCHEDULED"];
    const closedStates = ["CLOSED", "EXPIRED"];

    // 슈퍼어드민 + businessId 미지정 → 전체 조회
    if (isSuperAdmin && ids.length === 0) {
      let q: admin.firestore.Query = db.collection("tos").orderBy("createdAt", "desc");
      if (activeOnly) q = q.where("status", "in", openStates);
      else if (closedOnly) q = q.where("status", "in", closedStates);
      const snap = await q.get();
      return {items: snap.docs.map(d => ({id: d.id, ...serializeFirestoreData(d.data())}))};
    }

    // 사업장별 병렬 쿼리
    const snaps = await Promise.all(
      ids.map(bizId => {
        let q: admin.firestore.Query = db
          .collection("tos")
          .where("businessId", "==", bizId)
          .orderBy("createdAt", "desc");
        if (activeOnly) q = q.where("status", "in", openStates);
        else if (closedOnly) q = q.where("status", "in", closedStates);
        return q.get();
      })
    );

    const items = snaps.flatMap(s =>
      s.docs.map(d => ({id: d.id, ...serializeFirestoreData(d.data())}))
    );
    return {items};
  }
);

// ─── callableGetPayrollSummaries ──────────────────────────────────────────────
// payroll_summaries 조회 — Admin SDK server-side 권한 검증
// [RULE-FIX-CF 2026-07-13] payroll_summaries list 규칙 우회 근본 해결
// Input : businessId (필수), year? (선택 — 미지정 시 전체 연도)
// Output: { items: [{id: string, ...summaryFields}] }
export const callableGetPayrollSummaries = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;
    const {businessId, year} =
      (request.data ?? {}) as {businessId?: string; year?: number};

    if (!businessId || typeof businessId !== "string" || businessId.trim().length === 0) {
      throw new HttpsError("invalid-argument", "businessId가 필요합니다.");
    }

    await assertBizAdmin(callerUid, businessId);

    let q: admin.firestore.Query = db
      .collection("payroll_summaries")
      .where("businessId", "==", businessId);

    if (typeof year === "number" && Number.isInteger(year)) {
      q = q.where("year", "==", year);
    }

    const snap = await q.get();
    const items = snap.docs.map(d => ({id: d.id, ...serializeFirestoreData(d.data())}));
    return {items};
  }
);

// ─── callableGetScheduleChangeRequests ───────────────────────────────────────
// 스케줄 변경 요청 목록 조회 — Admin SDK server-side 권한 검증
// [RULE-FIX-CF 2026-07-13] schedule_change_requests admin list 규칙 근본 해결
// Input : businessId (필수), pendingOnly? (기본 false), limit? (기본 2000, 최대 5000)
// Output: { items: [{id: string, ...requestFields}], count: number }
export const callableGetScheduleChangeRequests = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;
    const {businessId, pendingOnly, limit: rawLimit} =
      (request.data ?? {}) as {
        businessId?: string;
        pendingOnly?: boolean;
        limit?: number;
      };

    if (!businessId || typeof businessId !== "string" || businessId.trim().length === 0) {
      throw new HttpsError("invalid-argument", "businessId가 필요합니다.");
    }

    await assertBizAdmin(callerUid, businessId);

    const cap = Math.min(
      typeof rawLimit === "number" && rawLimit > 0 ? rawLimit : 2000,
      5000
    );

    let q: admin.firestore.Query = db
      .collection("schedule_change_requests")
      .where("businessId", "==", businessId);

    if (pendingOnly === true) q = q.where("status", "==", "PENDING");

    q = q.orderBy("requestedAt", "desc").limit(cap);

    const snap = await q.get();
    const items = snap.docs.map(d => ({id: d.id, ...serializeFirestoreData(d.data())}));
    return {items, count: items.length};
  }
);

// ─── callableGetPaymentChangeRequests ────────────────────────────────────────
// 임금 변경 요청 목록 조회 — Admin SDK server-side 권한 검증
// [RULE-FIX-CF 2026-07-13] payment_change_requests admin list 규칙 근본 해결
// Input : businessId (필수), status? (기본 "PENDING"), limit? (기본 1000, 최대 2000)
// Output: { items: [{id: string, ...fields}] }
export const callableGetPaymentChangeRequests = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;
    const {businessId, status, limit: rawLimit} =
      (request.data ?? {}) as {
        businessId?: string;
        status?: string;
        limit?: number;
      };

    if (!businessId || typeof businessId !== "string" || businessId.trim().length === 0) {
      throw new HttpsError("invalid-argument", "businessId가 필요합니다.");
    }

    await assertBizAdmin(callerUid, businessId);

    const targetStatus = (typeof status === "string" && status.length > 0) ? status : "PENDING";
    const cap = Math.min(
      typeof rawLimit === "number" && rawLimit > 0 ? rawLimit : 1000,
      2000
    );

    const snap = await db
      .collection("payment_change_requests")
      .where("businessId", "==", businessId)
      .where("status", "==", targetStatus)
      .orderBy("createdAt", "desc")
      .limit(cap)
      .get();

    const items = snap.docs.map(d => ({id: d.id, ...serializeFirestoreData(d.data())}));
    return {items};
  }
);

// ─── callableGetInterimSettlements ───────────────────────────────────────────
// 중도정산 요청 목록 조회 (PENDING + APPROVED 병렬 쿼리) — Admin SDK 권한 검증
// [RULE-FIX-CF 2026-07-13] interim_settlement_requests admin list 규칙 근본 해결
// Input : businessId (필수), limit? (각 상태당 기본 500, 최대 1000)
// Output: { items: [{id: string, ...fields}] } — createdAt desc 정렬
export const callableGetInterimSettlements = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;
    const {businessId, limit: rawLimit} =
      (request.data ?? {}) as {businessId?: string; limit?: number};

    if (!businessId || typeof businessId !== "string" || businessId.trim().length === 0) {
      throw new HttpsError("invalid-argument", "businessId가 필요합니다.");
    }

    await assertBizAdmin(callerUid, businessId);

    const cap = Math.min(
      typeof rawLimit === "number" && rawLimit > 0 ? rawLimit : 500,
      1000
    );

    const baseQuery = db
      .collection("interim_settlement_requests")
      .where("businessId", "==", businessId);

    const [pendingSnap, approvedSnap] = await Promise.all([
      baseQuery.where("status", "==", "PENDING").orderBy("createdAt", "desc").limit(cap).get(),
      baseQuery.where("status", "==", "APPROVED").orderBy("createdAt", "desc").limit(cap).get(),
    ]);

    const allDocs = [
      ...pendingSnap.docs.map(d => ({id: d.id, ...serializeFirestoreData(d.data())})),
      ...approvedSnap.docs.map(d => ({id: d.id, ...serializeFirestoreData(d.data())})),
    ];

    // createdAt desc 정렬 — _seconds 필드 기준
    allDocs.sort((a, b) => {
      const aTs = ((a as Record<string, unknown>).createdAt as {_seconds?: number} | null)?._seconds ?? 0;
      const bTs = ((b as Record<string, unknown>).createdAt as {_seconds?: number} | null)?._seconds ?? 0;
      return bTs - aTs;
    });

    return {items: allDocs};
  }
);

// ─── callableGetMonthlyReviewsForUser ────────────────────────────────────────
// 특정 사용자의 월별 리뷰 목록 조회 — Admin SDK 권한 검증
// [RULE-FIX-CF 2026-07-13] monthly_reviews admin path 규칙 근본 해결
// Input : targetUserId (필수), businessId? (슈퍼어드민 아니면 필수), reviewType?,
//         publishedOnly? (기본 false), limit? (기본 5, 최대 50)
// Output: { items: [{id: string, ...fields}] }
export const callableGetMonthlyReviewsForUser = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;
    const {targetUserId, businessId, reviewType, publishedOnly, limit: rawLimit} =
      (request.data ?? {}) as {
        targetUserId?: string;
        businessId?: string;
        reviewType?: string;
        publishedOnly?: boolean;
        limit?: number;
      };

    if (!targetUserId || typeof targetUserId !== "string" || targetUserId.trim().length === 0) {
      throw new HttpsError("invalid-argument", "targetUserId가 필요합니다.");
    }

    const callerSnap = await db.collection("users").doc(callerUid).get();
    const isSuperAdmin = callerSnap.data()?.role === "SUPER_ADMIN";

    if (!isSuperAdmin) {
      if (!businessId || typeof businessId !== "string" || businessId.trim().length === 0) {
        throw new HttpsError("invalid-argument", "슈퍼어드민이 아닌 경우 businessId가 필요합니다.");
      }
      await assertBizAdmin(callerUid, businessId);
    }

    const cap = Math.min(
      typeof rawLimit === "number" && rawLimit > 0 ? rawLimit : 5,
      50
    );

    let q: admin.firestore.Query = db
      .collection("monthly_reviews")
      .where("targetUserId", "==", targetUserId);

    if (businessId) q = q.where("businessId", "==", businessId);
    if (reviewType) q = q.where("reviewType", "==", reviewType);
    if (publishedOnly === true) q = q.where("isPublished", "==", true);

    q = q.orderBy("createdAt", "desc").limit(cap);

    const snap = await q.get();
    const items = snap.docs.map(d => ({id: d.id, ...serializeFirestoreData(d.data())}));
    return {items};
  }
);

// ─── callableGetScheduleChangeRequestsForDate ────────────────────────────────
// 여러 사업장의 특정 날짜 스케줄 변경 요청 조회 (CF 이전 2026-07-13)
// 기존: Flutter에서 사업장별 isEqualTo 쿼리를 병렬 실행 → Security Rules PERMISSION_DENIED
// 수정: CF에서 Admin SDK로 쿼리 → 규칙 우회, 서버측 권한 검증
export const callableGetScheduleChangeRequestsForDate = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;

    const {businessIds, dateMs} = (request.data ?? {}) as {
      businessIds?: string[];
      dateMs?: number;
    };

    if (!Array.isArray(businessIds) || businessIds.length === 0 || businessIds.length > 20) {
      throw new HttpsError("invalid-argument", "businessIds는 1~20개 사이여야 합니다.");
    }
    if (!Number.isFinite(dateMs)) {
      throw new HttpsError("invalid-argument", "dateMs(날짜 Unix ms)가 필요합니다.");
    }

    // 권한 검증: 슈퍼어드민 OR 모든 businessId에 대한 관리 권한
    const callerSnap = await db.collection("users").doc(callerUid).get();
    const callerRole = callerSnap.data()?.role as string | undefined;
    const isSuperAdmin = callerRole === "SUPER_ADMIN";
    const callerSubAdminOf = callerSnap.data()?.subAdminOf as string | undefined;

    if (!isSuperAdmin) {
      const bizSnaps = await Promise.all(
        businessIds.map((bid) => db.collection("businesses").doc(bid).get())
      );
      for (let i = 0; i < businessIds.length; i++) {
        const biz = bizSnaps[i];
        if (!biz.exists) throw new HttpsError("not-found", `사업장 ${businessIds[i]}를 찾을 수 없습니다.`);
        const adminIds = (biz.data()?.adminIds as string[] | undefined) ?? [];
        const ownerId = biz.data()?.ownerId as string | undefined;
        const ok = adminIds.includes(callerUid) || ownerId === callerUid || callerSubAdminOf === businessIds[i];
        if (!ok) throw new HttpsError("permission-denied", `사업장 ${businessIds[i]}에 대한 권한이 없습니다.`);
      }
    }

    // 사업장별 병렬 쿼리
    const date = new Date(dateMs!);
    const snaps = await Promise.all(
      businessIds.map((bid) =>
        db.collection("schedule_change_requests")
          .where("businessId", "==", bid)
          .where("status", "==", "PENDING")
          .get()
      )
    );

    const items: Record<string, unknown>[] = [];
    for (const snap of snaps) {
      for (const doc of snap.docs) {
        const data = doc.data();
        // targetDate 날짜 매칭 (CF쪽에서 필터)
        const td = data["targetDate"] as admin.firestore.Timestamp | null | undefined;
        if (!td) continue;
        const d = td.toDate();
        if (d.getFullYear() === date.getFullYear() &&
            d.getMonth() === date.getMonth() &&
            d.getDate() === date.getDate()) {
          items.push({id: doc.id, ...serializeFirestoreData(data)});
        }
      }
    }

    return {items};
  }
);

// ─── callableCheckPendingInvitation ─────────────────────────────────────────
// 특정 사용자에게 유효한 초대(30일 이내 PENDING)가 있는지 확인 (CF 이전 2026-07-13)
// 기존: Flutter에서 다중 등호필터 쿼리 → Security Rules PERMISSION_DENIED
// 수정: CF에서 Admin SDK로 쿼리 → 규칙 우회, 서버측 권한 검증
export const callableCheckPendingInvitation = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;

    const {businessId, targetUid} = (request.data ?? {}) as {
      businessId?: string;
      targetUid?: string;
    };

    if (!businessId || typeof businessId !== "string" || businessId.trim().length === 0) {
      throw new HttpsError("invalid-argument", "businessId가 필요합니다.");
    }
    if (!targetUid || typeof targetUid !== "string" || targetUid.trim().length === 0) {
      throw new HttpsError("invalid-argument", "targetUid가 필요합니다.");
    }

    await assertBizAdmin(callerUid, businessId);

    // 30일 이내 발송된 PENDING 초대 확인
    const expiryMs = Date.now() - 30 * 24 * 60 * 60 * 1000;
    const snap = await db.collection("member_invitations")
      .where("businessId", "==", businessId)
      .where("targetUid", "==", targetUid)
      .where("status", "==", "pending")
      .where("createdAt", ">", admin.firestore.Timestamp.fromMillis(expiryMs))
      .limit(1)
      .get();

    return {hasPending: !snap.empty};
  }
);

// ─── callableUpdateWageDetail ─────────────────────────────────────────────────
// [M11-FIX] 급여 수정 CF 이전 — calculatedAt 서버 타임스탬프 강제 + wageConfirmed/transferred 차단
// 클라이언트 wage_confirm_dialog._processWageUpdate의 Firestore 직접 write를 CF Admin SDK로 이전.
// 이전 이유:
//  1. calculatedAt을 DateTime.now()로 설정 → 클라이언트 시계 조작으로 계산 시각 위조 가능
//  2. 트랜잭션 내 권한 검증 없이 businessId 기반 관리자 검증 → assertBizAdmin으로 강화
export const callableUpdateWageDetail = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;

    const {attendanceId, wageDetailMap} = request.data as {
      attendanceId: string;
      wageDetailMap: Record<string, unknown>;
    };

    if (!attendanceId) throw new HttpsError("invalid-argument", "attendanceId 필수");
    if (!wageDetailMap || typeof wageDetailMap !== "object") {
      throw new HttpsError("invalid-argument", "wageDetailMap 필수");
    }

    // 음수 additionalAmount/deductionAmount 차단 (클라이언트 유효성 검사 서버 재검증)
    const additionalAmount = Number(wageDetailMap.additionalAmount ?? 0);
    const deductionAmount = Number(wageDetailMap.deductionAmount ?? 0);
    if (additionalAmount < 0) throw new HttpsError("invalid-argument", "추가수당은 0 이상이어야 합니다.");
    if (deductionAmount < 0) throw new HttpsError("invalid-argument", "추가공제는 0 이상이어야 합니다.");
    // [V4-FIX] totalAmount/netWage 정수 범위 검증 — 클라이언트 임의 주입 방어
    const clientTotalAmount = Number(wageDetailMap.totalAmount ?? 0);
    const clientNetWage = Number(wageDetailMap.netWage ?? 0);
    if (!Number.isInteger(clientTotalAmount) || clientTotalAmount < 0 || clientTotalAmount > 999_999_999) {
      throw new HttpsError("invalid-argument", "totalAmount 값이 유효 범위(0~999,999,999)를 벗어났습니다.");
    }
    if (!Number.isInteger(clientNetWage) || clientNetWage < 0 || clientNetWage > clientTotalAmount) {
      throw new HttpsError("invalid-argument", "netWage 값이 유효 범위(0~totalAmount)를 벗어났습니다.");
    }

    // 1. attendance 사전 읽기 (businessId 추출 → assertBizAdmin)
    const attRef = db.collection("attendance").doc(attendanceId);
    const attSnap = await attRef.get();
    if (!attSnap.exists) throw new HttpsError("not-found", "출근 기록을 찾을 수 없습니다.");
    const attData = attSnap.data()!;

    // 2. 관리자 권한 검증 (트랜잭션 외부 — assertBizAdmin은 Firestore 2회 read)
    await assertBizAdmin(callerUid, attData.businessId as string);

    // 3. 트랜잭션 (wageStatus 재확인 + 업데이트 — race condition 방어)
    await db.runTransaction(async (tx) => {
      const freshSnap = await tx.get(attRef);
      if (!freshSnap.exists) throw new HttpsError("not-found", "출근 기록을 찾을 수 없습니다.");
      const freshData = freshSnap.data()!;

      const wageStatus = freshData.wageStatus as string;
      if (wageStatus === "transferred") {
        throw new HttpsError("failed-precondition", "이미 이체된 급여는 수정할 수 없습니다.");
      }
      if (wageStatus === "confirmed") {
        throw new HttpsError("failed-precondition", "이미 확정된 급여는 수정할 수 없습니다.");
      }

      // effectiveNetWage 계산 (Dart WageDetailModel.effectiveNetWage getter 재구현)
      // CF는 항상 calculatedAt=serverTimestamp 설정 → isCalculated=true → netWage 우선 사용
      // T-01 마이그레이션 폴백: netWage==0 && totalAmount>0 → 수식으로 재계산
      const totalAmount = Number(wageDetailMap.totalAmount ?? 0);
      const totalInsuranceDeduction =
        Number(wageDetailMap.employmentInsuranceDeduction ?? 0) +
        Number(wageDetailMap.nationalPensionDeduction ?? 0) +
        Number(wageDetailMap.healthInsuranceDeduction ?? 0) +
        Number(wageDetailMap.ltcInsuranceDeduction ?? 0) +
        Number(wageDetailMap.incomeTaxDeduction ?? 0) +
        Number(wageDetailMap.retroactiveDeduction ?? 0);
      const netWage = Number(wageDetailMap.netWage ?? 0);
      let finalWage: number;
      if (netWage === 0 && totalAmount > 0) {
        finalWage = Math.max(0, Math.min(totalAmount - totalInsuranceDeduction, 999999999));
      } else {
        finalWage = Math.max(0, Math.min(netWage, 999999999));
      }

      // yearMonth 추출 (YYYY-MM 형식 통일). [KST-FIX] workDate = KST 자정 UTC ms → getFullYear() UTC 오차
      const KST_OFFSET_MS = 9 * 60 * 60 * 1000;
      const wdTimestamp = freshData.workDate as admin.firestore.Timestamp | undefined;
      const wdKST = new Date((wdTimestamp?.toMillis() ?? Date.now()) + KST_OFFSET_MS);
      const yearMonth = `${wdKST.getUTCFullYear()}-${String(wdKST.getUTCMonth() + 1).padStart(2, "0")}`;

      // [V4-FIX] 민감 필드 주입 차단 — spread 전 삭제
      // confirmedBy/confirmedAt을 클라이언트가 주입해도 저장 안 됨; calculatedBy/calculatedAt은 CF가 강제 덮어씀
      const WAGE_DETAIL_DENY_FIELDS = ["calculatedBy", "calculatedAt", "confirmedBy", "confirmedAt"];
      const safeWageDetailMap: Record<string, unknown> = {...wageDetailMap};
      for (const f of WAGE_DETAIL_DENY_FIELDS) delete safeWageDetailMap[f];

      tx.update(attRef, {
        finalWage,
        wageDetail: {
          ...safeWageDetailMap,
          calculatedBy: callerUid,
          // [M11-FIX] calculatedAt 서버 타임스탬프 강제 — 클라이언트 DateTime.now() 조작 차단
          calculatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        yearMonth,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    return {success: true};
  }
);

// ─── callableIncrementSlotPending ────────────────────────────────────────────
// [A1-FIX] slot pendingCount/workTypeCounts CF 이전 — applicationId 소유권 검증
// 클라이언트가 WriteBatch로 workTypeCounts 맵 전체 교체 시 confirmedCount 조작 가능한 취약점 차단.
// 이전 이유:
//  1. rules isUser() 경로: workTypeCounts 전체 맵 교체로 confirmedCount를 임의 값으로 설정 → 정원 우회
//  2. CF Admin SDK: applicationId 소유권 검증 + dot-notation으로 pendingCount만 정밀 업데이트
// rules에서 isUser() slots update의 workTypeCounts 허용을 삭제하여 맵 전체 교체 차단 (이 CF와 동시 적용)
export const callableIncrementSlotPending = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;

    const {applicationId, toId, slotId, delta} = request.data as {
      applicationId: string;
      toId: string;
      slotId?: string;
      delta: number;
    };

    if (!applicationId) throw new HttpsError("invalid-argument", "applicationId 필수");
    if (!toId) throw new HttpsError("invalid-argument", "toId 필수");
    if (delta !== 1 && delta !== -1) throw new HttpsError("invalid-argument", "delta는 ±1만 허용됩니다.");

    // applicationId 소유권 + toId 교차검증 + workType 추출 (트랜잭션 외부 — 트랜잭션 내 read 최소화)
    const appSnap = await db.collection("applications").doc(applicationId).get();
    if (!appSnap.exists) throw new HttpsError("not-found", "지원서를 찾을 수 없습니다.");
    const appData = appSnap.data()!;

    if ((appData.uid as string) !== callerUid) {
      throw new HttpsError("permission-denied", "본인의 지원서만 처리할 수 있습니다.");
    }
    if ((appData.toId as string) !== toId) {
      throw new HttpsError("invalid-argument", "toId 불일치 — 지원서의 toId와 다릅니다.");
    }
    // [M-2] slotId 교차검증 — 동일 TO의 다른 슬롯 카운터 조작 차단
    if (slotId && (appData.slotId as string | undefined) !== slotId) {
      throw new HttpsError("invalid-argument", "slotId 불일치 — 지원서의 slotId와 다릅니다.");
    }

    const workType = appData.selectedWorkType as string | undefined;

    await db.runTransaction(async (tx) => {
      // [M-1] 멱등성 가드 — 네트워크 재시도/이중 호출 차단
      const appRef = db.collection("applications").doc(applicationId);
      const freshApp = await tx.get(appRef);
      const flagField = delta === 1 ? "pendingIncrementedAt" : "pendingDecrementedAt";
      if (freshApp.data()?.[flagField]) return;

      const toRef = db.collection("tos").doc(toId);
      // [M-1-FIX] totalPending 업데이트를 슬롯 zero-check 이후로 이동 — zero-protection 발동 시 음수 방지 보장

      if (slotId) {
        const slotRef = db.collection("tos").doc(toId).collection("slots").doc(slotId);
        const slotSnap = await tx.get(slotRef);
        if (!slotSnap.exists) throw new HttpsError("not-found", "슬롯을 찾을 수 없습니다.");

        // 음수 방지 — Firestore increment는 음수도 허용하므로 CF에서 직접 차단
        const currentPending = (slotSnap.data()?.pendingCount as number) ?? 0;
        if (delta === -1 && currentPending <= 0) {
          tx.update(appRef, {[flagField]: admin.firestore.FieldValue.serverTimestamp()});
          return;  // totalPending 미감소 — zero-check 발동 시 TO 카운터 음수 방지
        }

        const slotUpdate: Record<string, unknown> = {
          pendingCount: admin.firestore.FieldValue.increment(delta),
        };
        if (workType) {
          // dot-notation: 전체 맵 교체 없이 특정 필드만 업데이트 (confirmedCount 보호)
          slotUpdate[`workTypeCounts.${workType}.pendingCount`] = admin.firestore.FieldValue.increment(delta);
        }
        tx.update(slotRef, slotUpdate);
      }

      tx.update(toRef, {totalPending: admin.firestore.FieldValue.increment(delta)});
      tx.update(appRef, {[flagField]: admin.firestore.FieldValue.serverTimestamp()});
    });

    return {success: true};
  }
);

// ─── callableApproveScheduleChangeRequest ────────────────────────────────────
// [H3-FIX] 스케줄 변경 요청 승인/거절 CF 이전 — respondedByUid 서버 기록 + 원자적 배열 처리
// 클라이언트 approveScheduleChangeRequest/rejectScheduleChangeRequest의 Firestore 직접 write를 CF Admin SDK로 이전.
// 이전 이유:
//  1. respondedByUid를 클라이언트가 임의 설정 → 다른 관리자 UID 위조 가능 (M5 취약점)
//     CF 이전으로 callerUid를 CF가 직접 기록 → 위조 차단
//  2. 트랜잭션 내 businessId 권한 검증 없이 rules에만 의존 → CF assertBizAdmin으로 강화
// rules에서 관리자 PENDING→APPROVED/REJECTED 직접 전환 브랜치 삭제 완료
export const callableApproveScheduleChangeRequest = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;

    const {requestId, action, rejectReason} = request.data as {
      requestId: string;
      action: "APPROVED" | "REJECTED";
      rejectReason?: string;
    };

    if (!requestId) throw new HttpsError("invalid-argument", "requestId 필수");
    if (action !== "APPROVED" && action !== "REJECTED") {
      throw new HttpsError("invalid-argument", "action은 APPROVED 또는 REJECTED만 허용됩니다.");
    }

    // 1. 요청 문서 사전 읽기 (businessId·applicationId·applicantUid·requestType·targetDate 추출)
    const requestRef = db.collection("schedule_change_requests").doc(requestId);
    const requestSnap = await requestRef.get();
    if (!requestSnap.exists) throw new HttpsError("not-found", "요청을 찾을 수 없습니다.");
    const scrData = requestSnap.data()!;

    // 2. 관리자 권한 검증 (CF assertBizAdmin — businesses.adminIds 기준)
    await assertBizAdmin(callerUid, scrData.businessId as string);

    // 3. 사전 상태 확인 (트랜잭션 전 조기 차단)
    if ((scrData.status as string) !== "PENDING") {
      throw new HttpsError("failed-precondition", `이미 처리된 요청입니다 (${scrData.status as string}).`);
    }

    // 4. 트랜잭션 (상태 재확인 + 업데이트 + application 배열 처리 — race condition 방어)
    await db.runTransaction(async (tx) => {
      const freshSnap = await tx.get(requestRef);
      if (!freshSnap.exists) throw new HttpsError("not-found", "요청을 찾을 수 없습니다.");
      if ((freshSnap.data()!.status as string) !== "PENDING") {
        throw new HttpsError("failed-precondition", "이미 처리된 요청입니다 (동시 처리 충돌).");
      }

      // 요청 상태 업데이트
      const updateData: Record<string, unknown> = {
        status: action,
        // [H3-FIX] respondedByUid CF가 직접 기록 — 클라이언트 UID 위조 차단
        respondedByUid: callerUid,
        respondedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      if (action === "REJECTED" && rejectReason) {
        updateData.rejectReason = rejectReason;
      }
      tx.update(requestRef, updateData);

      // APPROVED 시 application 배열 원자적 업데이트
      // requestType별 처리 (Dart approveScheduleChangeRequest 로직 재구현):
      //   LEAVE/NO_WORK  → leaveDates 추가 (미출근 명단 등록)
      //   EXTRA_WORK     → extraWorkDates 추가 (비근무일 출근 허용)
      //   CANCEL_LEAVE   → leaveDates 제거 (출근 차단 해제, 미제거 시 근무자 출근 불가 상태 고착)
      //   CANCEL_EXTRA   → extraWorkDates 제거 (비근무일 명단 제거)
      if (action === "APPROVED") {
        const appRef = db.collection("applications").doc(scrData.applicationId as string);
        const appSnap = await tx.get(appRef);

        if (appSnap.exists) {
          const appData = appSnap.data()!;
          // [M1-FIX] applicationId 소유권 + 사업장 교차검증
          //   — 타 사업장 applicationId 지정으로 크로스-사업장 스케줄 조작 차단
          //   — 타 근로자 applicationId 지정으로 타인 스케줄 조작 차단
          if (appData.businessId !== (scrData.businessId as string)) {
            throw new HttpsError("permission-denied", "애플리케이션이 해당 사업장에 속하지 않습니다.");
          }
          if (appData.uid !== (scrData.applicantUid as string)) {
            throw new HttpsError("permission-denied", "애플리케이션 소유자가 요청자와 일치하지 않습니다.");
          }
          const targetDate = (scrData.targetDate as admin.firestore.Timestamp).toDate();

          const sameDay = (ts: admin.firestore.Timestamp): boolean => {
            const d = ts.toDate();
            return d.getFullYear() === targetDate.getFullYear() &&
                   d.getMonth() === targetDate.getMonth() &&
                   d.getDate() === targetDate.getDate();
          };

          const parseDates = (field: string): admin.firestore.Timestamp[] => {
            const arr = appData[field];
            return Array.isArray(arr) ? (arr as admin.firestore.Timestamp[]) : [];
          };

          const requestType = scrData.requestType as string;

          if (requestType === "LEAVE" || requestType === "NO_WORK") {
            const leaveDates = parseDates("leaveDates");
            if (!leaveDates.some(sameDay)) leaveDates.push(scrData.targetDate as admin.firestore.Timestamp);
            tx.update(appRef, {leaveDates});
          } else if (requestType === "EXTRA_WORK") {
            const extraWorkDates = parseDates("extraWorkDates");
            if (!extraWorkDates.some(sameDay)) extraWorkDates.push(scrData.targetDate as admin.firestore.Timestamp);
            tx.update(appRef, {extraWorkDates});
          } else if (requestType === "CANCEL_LEAVE") {
            const leaveDates = parseDates("leaveDates").filter((ts) => !sameDay(ts));
            tx.update(appRef, {leaveDates});
          } else if (requestType === "CANCEL_EXTRA") {
            const extraWorkDates = parseDates("extraWorkDates").filter((ts) => !sameDay(ts));
            tx.update(appRef, {extraWorkDates});
          }
        }
      }
    });

    // 5. 알림 전송 (트랜잭션 외부 — 알림 실패가 승인을 롤백하지 않도록)
    const applicantUid = scrData.applicantUid as string;
    const businessId = scrData.businessId as string;
    const targetDate = (scrData.targetDate as admin.firestore.Timestamp).toDate();
    const dateStr = `${targetDate.getMonth() + 1}월 ${targetDate.getDate()}일`;
    const notifTitle = action === "APPROVED" ? "스케줄 변경 승인" : "스케줄 변경 거절";
    const notifBody = action === "APPROVED"
      ? `${dateStr} 스케줄 변경 요청이 승인되었습니다.`
      : `${dateStr} 스케줄 변경 요청이 거절되었습니다.${rejectReason ? ` 사유: ${rejectReason}` : ""}`;

    db.collection("users").doc(applicantUid).collection("notifications").add({
      userId: applicantUid,
      type: action === "APPROVED" ? "scheduleChangeApproved" : "scheduleChangeRejected",
      title: notifTitle,
      body: notifBody,
      data: {requestId, businessId, action: "scheduleChangeDetail"},
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    }).catch((e: unknown) => console.error("[callableApproveScheduleChangeRequest] 알림 전송 실패:", e));

    return {success: true};
  }
);

// ─── 반올림 헬퍼 (B1-FIX 공용) ───────────────────────────────────────────────
// Dart attendance_rounding_helper.dart 의 로직을 TypeScript로 재구현.
// Dart `~/` 연산자 = zero-truncation → TypeScript Math.trunc() 로 대응.
// Math.floor() 사용 시 음수 오프셋에서 반대 방향으로 반올림되므로 반드시 Math.trunc() 사용.

interface AttendanceRulesData {
  earlyWindow?: number;      // 조출 인정 구간(분), default: 30
  earlyArrivalUnit?: number; // 조출 반올림 단위, default: 30
  lateGrace?: number;        // 지각 유예(분), default: 5
  lateUnit?: number;         // 지각 반올림 단위, default: 30
  lateWindow?: number;       // 연장 인정 구간(분), default: 30
  overtimeUnit?: number;     // 연장 반올림 단위, default: 10
  earlyLeaveUnit?: number;   // 조퇴 반올림 단위, default: 30
}


/** [MEDIUM] 클라이언트 제공 attendanceRules 극단값 클램핑 — lateGrace:9999 등으로 지각 판정 우회 차단 */
function _clampAttendanceRules(rules: AttendanceRulesData): AttendanceRulesData {
  // *Unit 필드는 반올림 제수(除數) — 0 입력 시 division-by-zero → Invalid Date 저장 방지로 하한 1 강제
  // *Window/*Grace는 비교 값만 사용되므로 0 허용
  return {
    earlyWindow:      Math.min(rules.earlyWindow ?? 30, 120),
    earlyArrivalUnit: Math.max(1, Math.min(rules.earlyArrivalUnit ?? 30, 120)),  // [M-06-FIX]
    lateGrace:        Math.min(rules.lateGrace ?? 5, 60),
    lateUnit:         Math.max(1, Math.min(rules.lateUnit ?? 30, 120)),           // [M-06-FIX]
    lateWindow:       Math.min(rules.lateWindow ?? 30, 120),
    overtimeUnit:     Math.max(1, Math.min(rules.overtimeUnit ?? 10, 60)),        // [M-06-FIX]
    earlyLeaveUnit:   Math.max(1, Math.min(rules.earlyLeaveUnit ?? 30, 60)),      // [S7-FIX]+[M-06-FIX]
  };
}

/**
 * 출근 반올림
 * - 조출(earlyWindow 이상 일찍): Math.trunc = Dart ~/ — contractStart 방향
 * - 정시(lateGrace 이내): roundedOffset=0
 * - 지각: Math.ceil — contractStart보다 더 늦게 반올림
 */
function _processCheckin(
  now: Date,
  contractStart: Date,
  rules: AttendanceRulesData
): {effectiveCheckIn: Date; isLate: boolean} {
  const earlyWindow = rules.earlyWindow ?? 30;
  const earlyArrivalUnit = rules.earlyArrivalUnit ?? 30;
  const lateGrace = rules.lateGrace ?? 5;
  const lateUnit = rules.lateUnit ?? 30;

  const offsetMinutes = Math.trunc((now.getTime() - contractStart.getTime()) / 60000);
  let roundedOffset: number;

  if (offsetMinutes < -earlyWindow) {
    // 조출: Math.trunc (= Dart ~/) — 음수 offsetMinutes를 0 방향으로 truncate
    roundedOffset = Math.trunc(offsetMinutes / earlyArrivalUnit) * earlyArrivalUnit;
  } else if (offsetMinutes <= lateGrace) {
    roundedOffset = 0;
  } else {
    // 지각: ceil
    roundedOffset = Math.ceil(offsetMinutes / lateUnit) * lateUnit;
  }

  return {
    effectiveCheckIn: new Date(contractStart.getTime() + roundedOffset * 60000),
    isLate: offsetMinutes > lateGrace,
  };
}

/**
 * 퇴근 반올림
 * - 연장(lateWindow 초과): Math.floor (= Dart ~/, 양수이므로 동일)
 * - 정시(0 이상 lateWindow 이내): roundedOffset=0
 * - 조퇴(음수): earlyDiff = -offset, ceil
 */
function _processCheckout(
  now: Date,
  contractEnd: Date,
  rules: AttendanceRulesData
): {effectiveCheckOut: Date; isEarlyLeave: boolean} {
  const lateWindow = rules.lateWindow ?? 30;
  const overtimeUnit = rules.overtimeUnit ?? 10;
  const earlyLeaveUnit = rules.earlyLeaveUnit ?? 30;

  const offsetMinutes = Math.trunc((now.getTime() - contractEnd.getTime()) / 60000);
  let roundedOffset: number;

  if (offsetMinutes > lateWindow) {
    // 연장: floor (양수 → Math.trunc와 동일)
    roundedOffset = Math.floor(offsetMinutes / overtimeUnit) * overtimeUnit;
  } else if (offsetMinutes >= 0) {
    roundedOffset = 0;
  } else {
    // 조퇴: earlyDiff = -offsetMinutes, ceil
    const earlyDiff = -offsetMinutes;
    roundedOffset = -(Math.ceil(earlyDiff / earlyLeaveUnit) * earlyLeaveUnit);
  }

  return {
    effectiveCheckOut: new Date(contractEnd.getTime() + roundedOffset * 60000),
    isEarlyLeave: offsetMinutes < 0,
  };
}

// ─── callableCheckIn ──────────────────────────────────────────────────────────
// [B1-FIX] 근무자 개별 실시간 출근 CF 이전 — 반올림·중복체크·서버 기록 강제
// 이전 이유:
//   1. 클라이언트 DateTime.now() 조작으로 출근 시각 위조 가능
//   2. 지원서 소유권·상태·휴무일 검증이 rules에만 의존 → CF에서 교차검증 강화
//   3. 반올림 계산 클라이언트에서 우회 가능 → 서버에서 강제 재계산
//   4. originalCheckIn(원본 시각) 불변 보장 — 서버에서만 기록
export const callableCheckIn = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;

    const {
      applicationId, businessId, businessName, workDateMs, workType,
      latitude, longitude, method,
      scheduledStartTime, attendanceRules,
    } = request.data as {
      applicationId: string; businessId: string; businessName: string;
      workDateMs: number; workType: string;
      latitude?: number; longitude?: number; method?: string;
      scheduledStartTime?: string;
      attendanceRules?: AttendanceRulesData;
    };

    if (!applicationId || !businessId || !businessName || !workType || !workDateMs) {
      throw new HttpsError("invalid-argument", "applicationId, businessId, businessName, workType, workDateMs가 필요합니다.");
    }
    // [M-07-FIX] scheduledStartTime HH:MM 형식 검증 — 비정상 형식으로 NaN 날짜 생성 방지
    if (scheduledStartTime !== undefined) {
      const [sh, sm] = scheduledStartTime.split(":").map(Number);
      if (!/^\d{2}:\d{2}$/.test(scheduledStartTime) || sh > 23 || sm > 59 || isNaN(sh) || isNaN(sm)) {
        throw new HttpsError("invalid-argument", "scheduledStartTime은 HH:MM 형식이어야 합니다.");
      }
    }

    // 1. 사용자 상태 확인
    const userSnap = await db.collection("users").doc(callerUid).get();
    if (!userSnap.exists) throw new HttpsError("not-found", "사용자를 찾을 수 없습니다.");
    const userData = userSnap.data()!;

    if (userData.restrictedUntil) {
      const restrictedUntil = (userData.restrictedUntil as admin.firestore.Timestamp).toDate();
      if (restrictedUntil > new Date()) {
        throw new HttpsError("permission-denied", "제재 중인 계정입니다. 제재 해제 후 이용 가능합니다.");
      }
    }
    // 외국인: foreignIdNumber 있으면 accountStatus=active 필요
    if (userData.foreignIdNumber != null && userData.accountStatus !== "active") {
      throw new HttpsError("permission-denied", "계정이 활성화되지 않았습니다.");
    }

    // 2. 지원서 검증
    const appSnap = await db.collection("applications").doc(applicationId).get();
    if (!appSnap.exists) throw new HttpsError("not-found", "지원서를 찾을 수 없습니다.");
    const appData = appSnap.data()!;

    // 소유권 + businessId 교차검증 — 타인 applicationId 주입 차단
    if (appData.uid !== callerUid) {
      throw new HttpsError("permission-denied", "본인의 지원서만 출근할 수 있습니다.");
    }
    if (appData.businessId !== businessId) {
      throw new HttpsError("permission-denied", "사업장 정보가 일치하지 않습니다.");
    }

    // 확정 상태 확인 (CONFIRMED, CONTRACT_PENDING만 허용)
    const confirmedStatuses = ["CONFIRMED", "CONTRACT_PENDING"];
    if (!confirmedStatuses.includes(appData.status as string)) {
      throw new HttpsError("permission-denied", "확정된 지원만 출근할 수 있습니다.");
    }

    // [KST-FIX] Firebase 서버는 UTC. workDateMs = Dart KST 자정 ms → new Date()는 KST 전날.
    // workDateMs + 9h 를 UTC로 해석하면 KST 날짜와 일치 → getUTC*()로 KST 날짜 구성.
    const KST_OFFSET_MS = 9 * 60 * 60 * 1000;
    const workDateKST = new Date(workDateMs + KST_OFFSET_MS);

    // 퇴직 이후 출근 차단 (actualResignDate <= workDate)
    if (appData.actualResignDate) {
      const resignDate = (appData.actualResignDate as admin.firestore.Timestamp).toDate();
      const resignDateKST = new Date(resignDate.getTime() + KST_OFFSET_MS);
      const workDateKSTDay = Date.UTC(workDateKST.getUTCFullYear(), workDateKST.getUTCMonth(), workDateKST.getUTCDate());
      const resignDateKSTDay = Date.UTC(resignDateKST.getUTCFullYear(), resignDateKST.getUTCMonth(), resignDateKST.getUTCDate());
      if (resignDateKSTDay <= workDateKSTDay) {
        throw new HttpsError("permission-denied", "퇴직 이후 출근할 수 없습니다.");
      }
    }

    // 휴무일 차단
    if (Array.isArray(appData.leaveDates)) {
      const isLeave = (appData.leaveDates as admin.firestore.Timestamp[]).some((d) => {
        const ldKST = new Date(d.toDate().getTime() + KST_OFFSET_MS);
        return ldKST.getUTCFullYear() === workDateKST.getUTCFullYear() &&
               ldKST.getUTCMonth() === workDateKST.getUTCMonth() &&
               ldKST.getUTCDate() === workDateKST.getUTCDate();
      });
      if (isLeave) throw new HttpsError("permission-denied", "휴무일에는 출근할 수 없습니다.");
    }

    // 3. docId: {applicationId}_{yyyyMMdd}
    const dateStr = `${workDateKST.getUTCFullYear()}${String(workDateKST.getUTCMonth() + 1).padStart(2, "0")}${String(workDateKST.getUTCDate()).padStart(2, "0")}`;
    const docId = `${applicationId}_${dateStr}`;
    const ref = db.collection("attendance").doc(docId);

    // 4. 트랜잭션: 중복 체크인 방지 + 반올림 계산 (now 트랜잭션 내부 — 재시도 시 갱신)
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (snap.exists) throw new HttpsError("already-exists", "오늘 이미 출근하셨습니다.");

      // [B1-FIX] now를 트랜잭션 내부에서 획득 — 재시도 시 시각 갱신
      const now = new Date();
      let effectiveCheckIn = now;
      let isLate = false;

      if (scheduledStartTime) {
        // [KST-FIX] workDateMs(KST 자정 UTC ms) + h:m ms = 해당 KST 계약 시작 시각(UTC ms)
        const [sh, sm] = scheduledStartTime.split(":").map(Number);
        const cStart = new Date(workDateMs + (sh * 60 + sm) * 60000);
        const result = _processCheckin(now, cStart, _clampAttendanceRules(attendanceRules ?? {}));
        effectiveCheckIn = result.effectiveCheckIn;
        isLate = result.isLate;
      }

      const yearMonth = `${workDateKST.getUTCFullYear()}-${String(workDateKST.getUTCMonth() + 1).padStart(2, "0")}`;
      const docData: Record<string, unknown> = {
        applicationId,
        userId: callerUid,
        businessId,
        businessName,
        workDate: admin.firestore.Timestamp.fromMillis(workDateMs),  // [KST-FIX] KST 자정 ms 그대로 저장
        yearMonth,
        workType,
        checkIn: admin.firestore.Timestamp.fromDate(effectiveCheckIn),
        originalCheckIn: admin.firestore.Timestamp.fromDate(now),
        checkInMethod: method ?? "gps",
        status: isLate ? "late" : "present",
        isModified: false,
        modifyRequested: false,
        wageStatus: "pending",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      if (latitude != null) docData.checkInLat = latitude;
      if (longitude != null) docData.checkInLng = longitude;

      tx.set(ref, docData);
    });

    return {success: true, attendanceId: docId};
  }
);

// ─── callableCheckOut ─────────────────────────────────────────────────────────
// [B1-FIX] 근무자 개별 실시간 퇴근 CF 이전 — 반올림·근무시간 계산·서버 기록 강제
// 이전 이유:
//   1. 클라이언트 DateTime.now() 조작으로 퇴근 시각 위조 가능
//   2. 근무시간(workHours) 계산이 클라이언트에서 조작 가능
//   3. wageStatus 보호(calculated/confirmed/transferred) 서버 재검증
//   4. originalCheckOut 불변 보장 — 서버에서만 최초 기록
export const callableCheckOut = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;

    const {
      attendanceId, workDateMs,
      latitude, longitude, method,
      scheduledStartTime, scheduledEndTime, attendanceRules,
    } = request.data as {
      attendanceId: string; workDateMs: number;
      latitude?: number; longitude?: number; method?: string;
      scheduledStartTime?: string; scheduledEndTime?: string;
      attendanceRules?: AttendanceRulesData;
    };

    if (!attendanceId || !workDateMs) {
      throw new HttpsError("invalid-argument", "attendanceId와 workDateMs가 필요합니다.");
    }
    // [M-07-FIX] scheduledStartTime/scheduledEndTime HH:MM 형식 검증
    const _checkTimeFormat = (t: string | undefined, label: string) => {
      if (t === undefined) return;
      const [h, m] = t.split(":").map(Number);
      if (!/^\d{2}:\d{2}$/.test(t) || h > 23 || m > 59 || isNaN(h) || isNaN(m)) {
        throw new HttpsError("invalid-argument", `${label}은 HH:MM 형식이어야 합니다.`);
      }
    };
    _checkTimeFormat(scheduledStartTime, "scheduledStartTime");
    _checkTimeFormat(scheduledEndTime, "scheduledEndTime");

    const ref = db.collection("attendance").doc(attendanceId);

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) throw new HttpsError("not-found", "출근 기록을 찾을 수 없습니다.");
      const data = snap.data()!;

      // 소유자 검증
      if (data.userId !== callerUid) {
        throw new HttpsError("permission-denied", "본인의 출근 기록만 퇴근할 수 있습니다.");
      }

      // 이미 퇴근 여부
      if (data.checkOut != null) {
        throw new HttpsError("already-exists", "이미 퇴근하셨습니다.");
      }

      // wageStatus 보호
      const ws = data.wageStatus as string | undefined;
      if (ws === "transferred" || ws === "confirmed" || ws === "calculated") {
        throw new HttpsError("permission-denied", "임금이 확정된 기록은 수정할 수 없습니다.");
      }

      // 반올림 계산 (scheduledStartTime + scheduledEndTime 모두 있을 때만)
      const now = new Date();
      let effectiveCheckOut = now;
      let isEarlyLeave = false;

      if (scheduledStartTime && scheduledEndTime) {
        // [KST-FIX] workDateMs(KST 자정 UTC ms) + h:m ms = KST 계약 시각(UTC ms). 야간교대: end < start → +24h
        const [sh, sm] = scheduledStartTime.split(":").map(Number);
        const [eh, em] = scheduledEndTime.split(":").map(Number);
        const cStartMs = workDateMs + (sh * 60 + sm) * 60000;
        let cEndMs = workDateMs + (eh * 60 + em) * 60000;
        if (cEndMs < cStartMs) cEndMs += 24 * 60 * 60 * 1000;  // 야간교대 +1일
        const cEnd = new Date(cEndMs);
        const result = _processCheckout(now, cEnd, _clampAttendanceRules(attendanceRules ?? {}));
        effectiveCheckOut = result.effectiveCheckOut;
        isEarlyLeave = result.isEarlyLeave;
      }

      // checkIn 파싱 (CF 기록은 항상 Timestamp)
      let checkInAt = now;
      if (data.checkIn) {
        checkInAt = (data.checkIn as admin.firestore.Timestamp).toDate();
      }

      const workMins = Math.max(0, Math.floor((effectiveCheckOut.getTime() - checkInAt.getTime()) / 60000));
      const workHours = workMins / 60;

      // status: 조퇴이면 early_leave, 아니면 기존 status 유지
      let status = data.status as string;
      if (isEarlyLeave) status = "early_leave";

      const update: Record<string, unknown> = {
        checkOut: admin.firestore.Timestamp.fromDate(effectiveCheckOut),
        checkOutMethod: method ?? "gps",
        workHours,
        status,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      // originalCheckOut: 기존에 없을 때만 기록 (절대 불변)
      if (data.originalCheckOut == null) {
        update.originalCheckOut = admin.firestore.Timestamp.fromDate(now);
      }

      if (latitude != null) update.checkOutLat = latitude;
      if (longitude != null) update.checkOutLng = longitude;
      if (workMins <= 0) update.isZeroWork = true;

      tx.update(ref, update);
    });

    return {success: true};
  }
);

// ─── callableCreateContractRenewal ──────────────────────────────────────────
// [M7-FIX] 계약 연장 CF 이전 — 법적 타임스탬프 서버 강제 + TOCTOU 방지
// 이전 이유:
//   1. confirmedAt/appliedAt: DateTime.now() 클라이언트 조작 → 계약일자 위변조
//   2. contractVoidedAt: DateTime.now() → 무효화 일자 위조
//   3. WriteBatch에 원본 상태 검증 없음 → 이미 연장된 계약 이중 연장 가능
export const callableCreateContractRenewal = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;

    const {
      originalApplicationId,
      newStartDateMs,
      newEndDateMs,
    } = (request.data ?? {}) as {
      originalApplicationId?: string;
      newStartDateMs?: number;
      newEndDateMs?: number;
    };

    if (!originalApplicationId || typeof originalApplicationId !== "string") {
      throw new HttpsError("invalid-argument", "originalApplicationId가 필요합니다.");
    }
    if (typeof newStartDateMs !== "number" || typeof newEndDateMs !== "number") {
      throw new HttpsError("invalid-argument", "날짜 파라미터가 누락되었습니다.");
    }
    if (newStartDateMs >= newEndDateMs) {
      throw new HttpsError("invalid-argument", "종료일이 시작일보다 이후여야 합니다.");
    }

    // 1. 원본 application 조회 (businessId 추출 목적)
    const originalRef = db.collection("applications").doc(originalApplicationId);
    const originalSnap = await originalRef.get();
    if (!originalSnap.exists) throw new HttpsError("not-found", "지원서를 찾을 수 없습니다.");
    const originalData = originalSnap.data()!;
    const businessId = originalData.businessId as string;

    // 2. 관리자 권한 검증
    await assertBizAdmin(callerUid, businessId);

    // 3. 서명 대기 계약서 사전 조회 (트랜잭션 외부)
    const pendingStatuses = ["pending_employer", "pending_worker"];
    const seenContractIds = new Set<string>();
    const pendingContractRefs: admin.firestore.DocumentReference[] = [];

    const [contractQ1, contractQ2] = await Promise.all([
      db.collection("employment_contracts")
        .where("applicationId", "==", originalApplicationId)
        .where("businessId", "==", businessId)
        .limit(5)
        .get(),
      db.collection("employment_contracts")
        .where("applicationIds", "array-contains", originalApplicationId)
        .where("businessId", "==", businessId)
        .limit(5)
        .get(),
    ]);
    for (const cDoc of [...contractQ1.docs, ...contractQ2.docs]) {
      if (!seenContractIds.has(cDoc.id) && pendingStatuses.includes(cDoc.data().status as string)) {
        seenContractIds.add(cDoc.id);
        pendingContractRefs.push(cDoc.ref);
      }
    }

    // 4. 신규 application docId 사전 생성
    const newRef = db.collection("applications").doc();
    const newApplicationId = newRef.id;

    // 5. 트랜잭션 실행
    await db.runTransaction(async (tx) => {
      // 5-1. TOCTOU 방지: 원본 상태 트랜잭션 내 재확인
      const freshSnap = await tx.get(originalRef);
      if (!freshSnap.exists) throw new HttpsError("not-found", "지원서를 찾을 수 없습니다.");
      const freshData = freshSnap.data()!;

      if (freshData.renewalDecision === "EXTEND") {
        throw new HttpsError("already-exists", "이미 연장 처리된 계약입니다.");
      }
      if (freshData.status !== "CONFIRMED") {
        throw new HttpsError("failed-precondition", "확정 상태의 계약만 연장할 수 있습니다.");
      }

      // 5-2. 서명 대기 계약서 재확인 후 voided 처리 (contractVoidedAt: serverTimestamp)
      for (const cRef of pendingContractRefs) {
        const cSnap = await tx.get(cRef);
        if (cSnap.exists && pendingStatuses.includes(cSnap.data()!.status as string)) {
          tx.update(cRef, {
            status: "voided",
            contractVoidedAt: admin.firestore.FieldValue.serverTimestamp(),
            voidReason: "RENEWAL",
          });
        }
      }

      // 5-3. 신규 application 생성 (confirmedAt/appliedAt/createdAt: serverTimestamp)
      const newData: Record<string, unknown> = {
        ...freshData,
        workDate: admin.firestore.Timestamp.fromMillis(newStartDateMs),
        workEndDate: admin.firestore.Timestamp.fromMillis(newEndDateMs),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        confirmedAt: admin.firestore.FieldValue.serverTimestamp(),
        appliedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        renewedFromApplicationId: originalApplicationId,
        status: "CONTRACT_PENDING",
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
        leaveDates: [],
        extraWorkDates: [],
        // [HIGH-2] ...freshData 스프레드로 원본 임금 집계 필드가 복사되는 것을 방지 — 새 계약은 임금 0 상태에서 시작
        wageStatus: "pending",
        finalWage: null,
        wageDetail: null,
        wageConfirmedAt: null,
        wageTransferredAt: null,
        interimSettledAmount: 0,
      };
      // yearMonth는 checkIn 기록 시 설정됨 — 원본 값 제거 (set()에서 FieldValue.delete() 불가)
      delete newData.yearMonth;
      tx.set(newRef, newData);

      // 5-4. 원본 renewalDecision=EXTEND + renewedToApplicationId 기록
      tx.update(originalRef, {
        renewalDecision: "EXTEND",
        renewedToApplicationId: newApplicationId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // [MEDIUM-3] totalConfirmed +1 제거 — 갱신은 기존 카운터 유지
      //   원본 application이 CONFIRMED 상태로 이미 totalConfirmed에 포함됨.
      //   D-0 자동 갱신(processContractRenewalChecks)도 동일하게 카운터 미조정.
      //   갱신은 계약 기간 연장이며 확정 인원 변경이 아니므로 +1 불필요.
    });

    return {success: true, newApplicationId};
  }
);

// ═══════════════════════════════════════════════════════════
// 🔒 callableCloseTOManually — TO 수동 마감 CF
// ═══════════════════════════════════════════════════════════
/**
 * Trust Boundary Charter:
 *   - closedBy: 서버에서 request.auth.uid 사용 → 클라이언트 위조 불가 [M-2]
 *   - AUTO_CANCELED 법적 상태 전이: CF Admin SDK 전용 (rules bypass) [Charter]
 *
 * Input:  { toId: string }
 * Output: { success: true }
 *   기존 지원서(CONFIRMED/PENDING/CONTRACT_PENDING)는 변경하지 않음 — 신규 지원만 차단
 */
export const callableCloseTOManually = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;

    const {toId} = request.data as {toId?: string};
    if (!toId || typeof toId !== "string" || toId.trim().length === 0) {
      throw new HttpsError("invalid-argument", "toId가 필요합니다.");
    }

    // 1. TO 조회 및 권한 검증
    const toSnap = await db.collection("tos").doc(toId).get();
    if (!toSnap.exists) throw new HttpsError("not-found", "공고를 찾을 수 없습니다.");
    const toData = toSnap.data()!;
    const businessId = toData.businessId as string | undefined;
    if (!businessId) throw new HttpsError("internal", "businessId 누락");

    await assertBizAdmin(callerUid, businessId);

    if (toData.isManualClosed === true) {
      throw new HttpsError("already-exists", "이미 수동 마감된 공고입니다.");
    }

    // 2. TO 상태 업데이트 — closedBy 서버 UID 사용 [M-2]
    await db.collection("tos").doc(toId).update({
      isManualClosed: true,
      closedAt: admin.firestore.FieldValue.serverTimestamp(),
      closedBy: callerUid,
      status: "CLOSED",
      statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 3. 기존 지원서는 변경하지 않음 — 마감은 신규 지원만 차단
    // CONFIRMED(확정) 근로자는 출퇴근 진행 중이므로 절대 취소 불가.
    // PENDING/CONTRACT_PENDING도 유지 — 관리자가 직접 처리.
    // TO.isManualClosed=true → 클라이언트에서 새 지원 버튼 비활성화로 신규 차단.

    console.log(`✅ [closeTOManually] TO ${toId} 마감 완료 (기존 지원서 유지)`);
    return {success: true};
  }
);

// ─────────────────────────────────────────────────────────
// callableCancelScheduleChangeRequest — 스케줄 변경 요청 취소 (서버 원자화)
//
// 이전 이유:
//   - applications 문서의 leaveDates/extraWorkDates 업데이트가 rules에서 명시적으로
//     보호되지 않아 관리자가 임의 배열로 덮어쓸 수 있음 (MEDIUM 위험)
//   - CF Admin SDK로 이전 후 rules에서 이 필드를 denylist에 추가 가능
//
// 호출자: 근로자(본인 PENDING 취소) 또는 관리자(APPROVED 승인 취소)
// 반환값: { success: true }
// ─────────────────────────────────────────────────────────
export const callableCancelScheduleChangeRequest = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;

    const {requestId} = request.data as {requestId?: string};
    if (!requestId || typeof requestId !== "string" || requestId.trim() === "") {
      throw new HttpsError("invalid-argument", "requestId가 필요합니다.");
    }

    // 1. 요청 문서 사전 읽기
    const requestRef = db.collection("schedule_change_requests").doc(requestId);
    const requestSnap = await requestRef.get();
    if (!requestSnap.exists) throw new HttpsError("not-found", "요청을 찾을 수 없습니다.");
    const scrData = requestSnap.data()!;
    const scrStatus = scrData.status as string;
    const requestedByUid = scrData.requestedByUid as string | undefined;
    const businessId = scrData.businessId as string | undefined;

    // 2. 권한 검증
    //    - 근로자 본인: requestedByUid == callerUid && status == PENDING만 허용
    //    - 관리자: assertBizAdmin 통과 && (PENDING 또는 APPROVED) 허용
    const isRequester = callerUid === requestedByUid;
    let isAdmin = false;
    if (businessId) {
      try {
        await assertBizAdmin(callerUid, businessId);
        isAdmin = true;
      } catch (e) {
        if (e instanceof HttpsError) {
          // permission-denied / not-found → 관리자 아님, isRequester 경로로 진행
        } else {
          throw e; // Firestore 타임아웃·네트워크 오류는 재throw
        }
      }
    }

    if (!isRequester && !isAdmin) {
      throw new HttpsError("permission-denied", "취소 권한이 없습니다.");
    }
    if (isRequester && !isAdmin) {
      // 본인은 PENDING만 취소 가능
      if (scrStatus !== "PENDING") {
        throw new HttpsError("failed-precondition", "이미 처리된 요청은 취소할 수 없습니다.");
      }
    } else {
      // 관리자는 PENDING 또는 APPROVED만 취소 가능
      if (scrStatus !== "PENDING" && scrStatus !== "APPROVED") {
        throw new HttpsError("failed-precondition", `취소 불가 상태입니다: ${scrStatus}`);
      }
    }

    const requestType = scrData.requestType as string | undefined;
    const applicationId = scrData.applicationId as string | undefined;
    const targetDateTs = scrData.targetDate as admin.firestore.Timestamp | undefined;
    const targetDate = targetDateTs?.toDate();

    // 3. 트랜잭션: 최종 상태 재확인 + applications 역산 + SCR 상태 업데이트
    await db.runTransaction(async (tx) => {
      const freshSnap = await tx.get(requestRef);
      if (!freshSnap.exists) throw new HttpsError("not-found", "요청을 찾을 수 없습니다.");
      const freshStatus = freshSnap.data()!.status as string;

      if (freshStatus !== "PENDING" && freshStatus !== "APPROVED") {
        throw new HttpsError("failed-precondition", `이미 처리된 요청입니다 (${freshStatus}).`);
      }
      if (isRequester && !isAdmin && freshStatus !== "PENDING") {
        throw new HttpsError("failed-precondition", "이미 처리된 요청은 취소할 수 없습니다.");
      }

      // APPROVED 상태 취소: applications 문서에서 날짜 역산
      if (freshStatus === "APPROVED" && applicationId && targetDate) {
        const appRef = db.collection("applications").doc(applicationId);
        const appSnap = await tx.get(appRef);

        if (appSnap.exists) {
          const appData = appSnap.data()!;
          const toDateOnly = (ts: admin.firestore.Timestamp) => {
            const d = ts.toDate();
            return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
          };
          const targetMs = new Date(
            targetDate.getFullYear(), targetDate.getMonth(), targetDate.getDate()
          ).getTime();

          if (requestType === "LEAVE" || requestType === "NO_WORK") {
            // LEAVE/NO_WORK 승인 취소 → leaveDates에서 해당 날짜 제거
            const rawLeave = (appData["leaveDates"] as admin.firestore.Timestamp[] | undefined) ?? [];
            const filtered = rawLeave.filter((ts) => toDateOnly(ts) !== targetMs);
            tx.update(appRef, {leaveDates: filtered});
          } else if (requestType === "EXTRA_WORK") {
            // EXTRA_WORK 승인 취소 → extraWorkDates에서 해당 날짜 제거
            const rawExtra = (appData["extraWorkDates"] as admin.firestore.Timestamp[] | undefined) ?? [];
            const filtered = rawExtra.filter((ts) => toDateOnly(ts) !== targetMs);
            tx.update(appRef, {extraWorkDates: filtered});
          } else if (requestType === "CANCEL_LEAVE") {
            // CANCEL_LEAVE 승인 취소 → leaveDates에 날짜 복원
            const rawLeave = (appData["leaveDates"] as admin.firestore.Timestamp[] | undefined) ?? [];
            const alreadyExists = rawLeave.some((ts) => toDateOnly(ts) === targetMs);
            if (!alreadyExists) {
              rawLeave.push(admin.firestore.Timestamp.fromDate(targetDate));
            }
            tx.update(appRef, {leaveDates: rawLeave});
          } else if (requestType === "CANCEL_EXTRA") {
            // CANCEL_EXTRA 승인 취소 → extraWorkDates에 날짜 복원
            const rawExtra = (appData["extraWorkDates"] as admin.firestore.Timestamp[] | undefined) ?? [];
            const alreadyExists = rawExtra.some((ts) => toDateOnly(ts) === targetMs);
            if (!alreadyExists) {
              rawExtra.push(admin.firestore.Timestamp.fromDate(targetDate));
            }
            tx.update(appRef, {extraWorkDates: rawExtra});
          }
        }
      }

      // SCR 상태 업데이트
      tx.update(requestRef, {
        status: "CANCELED",
        // [H3-FIX] respondedByUid CF가 직접 기록 — 클라이언트 UID 위조 차단
        respondedByUid: callerUid,
        respondedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    console.log(`✅ [cancelScheduleChangeRequest] 취소 완료: ${requestId}`);
    return {success: true};
  }
);

// ─────────────────────────────────────────────────────────
// callableApplyToTO — 공고 지원 (신규/재지원 통합, 서버 원자화)
//
// 이전 이유:
//   1. TOCTOU: 클라이언트에서 runTransaction(검증)과 batch(쓰기)가 분리되어 레이스 가능
//   2. 서류/블랙리스트/제재 검증이 클라이언트에서만 이루어져 위조 가능
//   3. 시간 충돌 체크가 클라이언트에서만 이루어져 동시 지원 시 무력화 가능
//
// 트랜잭션 내에서 최종 재검증 + 지원서 set/update + pendingCount 증감을 원자화.
// 알림 전송은 클라이언트에서 applicationId를 받아 별도 처리.
//
// 반환값: { success: true, applicationId: string, isReactivation: boolean }
// ─────────────────────────────────────────────────────────
export const callableApplyToTO = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const uid = request.auth.uid;

    const data = request.data as {
      toId?: string;
      slotId?: string | null;
      businessId?: string;
      businessName?: string;
      toTitle?: string;
      workDateMs?: number;
      selectedWorkType?: string;
      workDetailId?: string | null;
      startTime?: string;
      endTime?: string;
      wage?: number;
      wageType?: string;
      workTypeIcon?: string | null;
      workTypeColor?: string | null;
      workTypeBackgroundColor?: string | null;
      workEndDateMs?: number | null;
      workDays?: string[] | null;
      desiredStartDateMs?: number | null;
    };

    // ── 1. 입력값 검증 ──
    const toId = data.toId;
    const slotId = data.slotId ?? null;
    const businessId = data.businessId;
    const businessName = data.businessName ?? "";
    const toTitle = data.toTitle ?? "";
    const workDateMs = data.workDateMs;
    const selectedWorkType = data.selectedWorkType;
    const workDetailId = data.workDetailId ?? null;
    const startTime = data.startTime ?? "";
    const endTime = data.endTime ?? "";
    const wage = data.wage;
    const wageType = data.wageType ?? "hourly";
    const workTypeIcon = data.workTypeIcon ?? null;
    const workTypeColor = data.workTypeColor ?? null;
    const workTypeBackgroundColor = data.workTypeBackgroundColor ?? null;
    const workEndDateMs = data.workEndDateMs ?? null;
    const workDays = Array.isArray(data.workDays) ? data.workDays : null;
    const desiredStartDateMs = data.desiredStartDateMs ?? null;

    if (!toId || typeof toId !== "string" || toId.trim() === "") {
      throw new HttpsError("invalid-argument", "toId가 필요합니다.");
    }
    if (!businessId || typeof businessId !== "string") {
      throw new HttpsError("invalid-argument", "businessId가 필요합니다.");
    }
    if (!workDateMs || typeof workDateMs !== "number") {
      throw new HttpsError("invalid-argument", "workDateMs가 필요합니다.");
    }
    if (!selectedWorkType || typeof selectedWorkType !== "string") {
      throw new HttpsError("invalid-argument", "selectedWorkType이 필요합니다.");
    }
    if (!startTime || !endTime) {
      throw new HttpsError("invalid-argument", "startTime/endTime이 필요합니다.");
    }
    if (wage === undefined || typeof wage !== "number") {
      throw new HttpsError("invalid-argument", "wage가 필요합니다.");
    }

    const workDate = admin.firestore.Timestamp.fromMillis(workDateMs);
    const workEndDate = workEndDateMs ? admin.firestore.Timestamp.fromMillis(workEndDateMs) : null;
    const desiredStartDate = desiredStartDateMs ? admin.firestore.Timestamp.fromMillis(desiredStartDateMs) : null;
    // isContract: slotId 없거나 workDays 있으면 장기계약
    const isContract = !slotId || (workDays !== null && workDays.length > 0);

    // ── 2. 사용자 서류/블랙리스트/PASS/신분증/제재 체크 ──
    const userSnap = await db.collection("users").doc(uid).get();
    if (!userSnap.exists) throw new HttpsError("not-found", "사용자 정보를 찾을 수 없습니다.");
    const userData = userSnap.data()!;

    if (!userData["idCardImageUrl"]) {
      throw new HttpsError("failed-precondition", "신분증 등록이 필요합니다.");
    }
    if (!userData["bankName"] || !userData["accountNumber"]) {
      throw new HttpsError("failed-precondition", "통장 정보 등록이 필요합니다.");
    }
    if (!userData["bankbookImageUrl"]) {
      throw new HttpsError("failed-precondition", "통장사본 등록이 필요합니다.");
    }
    if (userData["isBlacklisted"] === true) {
      const reason = (userData["blacklistReason"] as string | undefined) ?? "이용 정책 위반";
      throw new HttpsError("permission-denied", `이용 제한된 계정입니다.\n사유: ${reason}`);
    }
    // [PASS-PENDING] ci/passVerifiedAt 게이트는 다날 계약 + finalizeRegistration CF 배포 후 활성화
    //   현재 모든 기존 사용자에게 필드가 없어 전면 차단됨 → project_pass_pending_issues.md ISSUE-01
    // 단기(슬롯 있는) 공고는 신분증 인증 필수
    if (slotId && userData["isIdVerified"] !== true) {
      throw new HttpsError("failed-precondition", "신분증 인증 후 지원할 수 있습니다.");
    }
    const restrictedUntilTs = userData["restrictedUntil"] as admin.firestore.Timestamp | undefined;
    if (restrictedUntilTs && restrictedUntilTs.toDate() > new Date()) {
      const remainDays = Math.ceil(
        (restrictedUntilTs.toDate().getTime() - Date.now()) / (1000 * 60 * 60 * 24)
      );
      throw new HttpsError(
        "permission-denied",
        `무단 결근 페널티로 ${remainDays}일 동안 지원이 제한됩니다.`
      );
    }

    // ── 3. TO 상태 체크 ──
    const toSnap = await db.collection("tos").doc(toId).get();
    if (!toSnap.exists) throw new HttpsError("not-found", "공고를 찾을 수 없습니다.");
    const toData = toSnap.data()!;

    if ((toData["businessId"] as string | undefined) !== businessId) {
      throw new HttpsError("invalid-argument", "businessId 불일치.");
    }
    if (toData["status"] === "DRAFT") {
      throw new HttpsError("permission-denied", "비공개 공고에는 지원할 수 없습니다.");
    }
    if (toData["status"] === "EXPIRED") {
      throw new HttpsError("permission-denied", "만료된 공고입니다.");
    }
    // [B1-FIX] isPublished=false 미게시 공고(SCHEDULED 포함) 차단 — 구 rules의 isPublished 조건 CF 재확립
    if (!toData["isPublished"]) {
      throw new HttpsError("permission-denied", "아직 공개되지 않은 공고입니다.");
    }
    if (
      toData["isManualClosed"] === true ||
      toData["status"] === "CLOSED" ||
      toData["status"] === "FULL"
    ) {
      throw new HttpsError("permission-denied", "마감된 공고입니다.");
    }
    const publishEndDateTs = toData["publishEndDate"] as admin.firestore.Timestamp | undefined;
    if (publishEndDateTs && publishEndDateTs.toDate() < new Date()) {
      throw new HttpsError("permission-denied", "게시 기간이 만료된 공고입니다.");
    }
    const toDeadlineTs = toData["applicationDeadline"] as admin.firestore.Timestamp | undefined;
    if (toDeadlineTs && toDeadlineTs.toDate() < new Date()) {
      throw new HttpsError("permission-denied", "지원 마감된 공고입니다.");
    }

    // ── 4. 슬롯 또는 TO 단위 정원 사전 체크 + 서버 임금 추출 ──
    // [V7-FIX] wage/wageType을 클라이언트 값 대신 서버 TO/슬롯 문서에서 추출 (임금 위조 차단)
    let serverWage: number | undefined;
    let serverWageType: string | undefined;
    if (slotId) {
      const slotSnap = await db
        .collection("tos").doc(toId).collection("slots").doc(slotId).get();
      if (!slotSnap.exists) throw new HttpsError("not-found", "해당 날짜 정보를 찾을 수 없습니다.");
      const sd = slotSnap.data()!;
      if (sd["isManualClosed"] === true || sd["status"] === "closed") {
        throw new HttpsError("permission-denied", "해당 날짜는 마감되었습니다.");
      }
      const rawWD = (sd["workDetails"] as unknown[]) ?? [];
      const wd = (rawWD as Record<string, unknown>[]).find(
        (d) => d["workType"] === selectedWorkType
      ) ?? {};
      serverWage = wd["wage"] as number | undefined;
      serverWageType = wd["wageType"] as string | undefined;
      const wdDeadlineTs = wd["applicationDeadline"] as admin.firestore.Timestamp | undefined;
      if (wdDeadlineTs && wdDeadlineTs.toDate() < new Date()) {
        throw new HttpsError("permission-denied", "해당 업무의 지원 마감 시간이 지났습니다.");
      }
      const req = (wd["requiredCount"] as number | undefined) ?? 0;
      const rawCounts = sd["workTypeCounts"] as Record<string, Record<string, number>> | undefined;
      const cnt = rawCounts?.[selectedWorkType]?.["confirmedCount"] ?? 0;
      if (req > 0 && cnt >= req) {
        throw new HttpsError("permission-denied", "해당 업무의 모집 인원이 마감되었습니다.");
      }
    } else {
      const confirmedCount = (toData["totalConfirmed"] as number | undefined) ?? 0;
      const totalRequired = (toData["totalRequired"] as number | undefined) ?? 0;
      if (totalRequired > 0 && confirmedCount >= totalRequired) {
        throw new HttpsError("permission-denied", "모집 인원이 마감되었습니다.");
      }
      const rawWDList = (toData["workDetails"] as unknown[]) ?? [];
      const workTypeConfirmed =
        ((toData["workTypeConfirmedCounts"] as Record<string, number> | undefined)
          ?.[selectedWorkType]) ?? 0;
      for (const wd of rawWDList as Record<string, unknown>[]) {
        if (wd["workType"] === selectedWorkType) {
          serverWage = wd["wage"] as number | undefined;
          serverWageType = wd["wageType"] as string | undefined;
          const wtr = (wd["requiredCount"] as number | undefined) ?? 0;
          if (wtr > 0 && workTypeConfirmed >= wtr) {
            throw new HttpsError("permission-denied", "해당 업무의 모집 인원이 마감되었습니다.");
          }
          break;
        }
      }
    }
    const effectiveWage = serverWage ?? wage;
    const effectiveWageType = serverWageType ?? wageType;

    // ── 5. 복합 docId 계산 + 기존 지원서 중복/재활성화 판단 ──
    const discriminator = (workDetailId && workDetailId.length > 0) ? workDetailId : selectedWorkType;
    const complexId = slotId
      ? `${toId}_${slotId}_${discriminator}_${uid}`
      : `${toId}_${discriminator}_${uid}`;

    const existingSnap = await db.collection("applications").doc(complexId).get();
    let isReactivation = false;

    if (existingSnap.exists) {
      const exData = existingSnap.data()!;
      const exStatus = (exData["status"] as string | undefined) ?? "";
      const isResignDone =
        exData["resignStatus"] === "APPROVED" || exData["resignStatus"] === "AUTO_APPROVED";
      const isTermDone =
        exData["terminationStatus"] === "APPROVED" || exData["terminationStatus"] === "AUTO_APPROVED";
      if (!isResignDone && !isTermDone) {
        const activeStates = ["CONFIRMED", "CONTRACT_PENDING", "PENDING"];
        if (activeStates.includes(exStatus)) {
          throw new HttpsError("already-exists", "이미 지원한 업무입니다.");
        }
        const inactiveStates = ["CANCELED", "AUTO_CANCELED", "REJECTED"];
        if (inactiveStates.includes(exStatus)) {
          isReactivation = true;
        }
      }
    }

    // ── 6. 시간 충돌 체크 (확정 지원서 조회) ──
    const confirmedStatuses = ["CONFIRMED", "CONTRACT_PENDING"];
    const confirmedSnaps = await Promise.all(
      confirmedStatuses.map((s) =>
        db.collection("applications")
          .where("uid", "==", uid)
          .where("status", "==", s)
          .get()
      )
    );
    const confirmedApps: Array<Record<string, unknown>> = confirmedSnaps.flatMap((snap) =>
      snap.docs.map((d) => ({id: d.id, ...(d.data() as Record<string, unknown>)}))
    );

    function hasTimeOverlap(s1: string, e1: string, s2: string, e2: string): boolean {
      if (!s1 || !e1 || !s2 || !e2) return false; // 빈문자열 오탐 방지 — _hasTimeOverlap과 동일
      return s1 < e2 && e1 > s2;
    }
    const weekdayNames = ["일", "월", "화", "수", "목", "금", "토"];

    const workDateDate = workDate.toDate();
    const newWorkDays = workDays ?? [];
    const newWorkEndDate = workEndDate ? workEndDate.toDate() : null;
    const effectiveStartDate = desiredStartDate ? desiredStartDate.toDate() : workDateDate;

    for (const app of confirmedApps) {
      const appStartTime = (app["startTime"] as string | undefined) ?? "";
      const appEndTime = (app["endTime"] as string | undefined) ?? "";
      if (!hasTimeOverlap(startTime, endTime, appStartTime, appEndTime)) continue;

      const appWorkDateTs = app["workDate"] as admin.firestore.Timestamp | undefined;
      if (!appWorkDateTs) continue;
      const appWorkDate = appWorkDateTs.toDate();

      const isLongTermApp =
        app["type"] === "long_term" ||
        (Array.isArray(app["workDays"]) && (app["workDays"] as string[]).length > 0);

      const toDateOnly = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate());

      if (isContract && newWorkEndDate && newWorkDays.length > 0) {
        // 신규 장기 지원 → 기존 확정과 충돌 체크
        const newStartOnly = toDateOnly(effectiveStartDate);
        const newEndOnly = toDateOnly(newWorkEndDate);

        if (isLongTermApp) {
          const appWorkEndDateTs = app["workEndDate"] as admin.firestore.Timestamp | undefined;
          const appActualResignDateTs = app["actualResignDate"] as admin.firestore.Timestamp | undefined;
          const sEnd = appActualResignDateTs?.toDate() ?? appWorkEndDateTs?.toDate() ?? new Date(9999, 11, 31);
          const sStartOnly = toDateOnly(appWorkDate);
          const sEndOnly = toDateOnly(sEnd);

          if (newEndOnly < sStartOnly || newStartOnly > sEndOnly) continue;

          const appWorkDays = (app["workDays"] as string[] | undefined) ?? [];
          const conflictDay = newWorkDays.find((d) => appWorkDays.includes(d));
          if (!conflictDay) continue;

          throw new HttpsError(
            "permission-denied",
            `매주 ${conflictDay}에 ${appStartTime}~${appEndTime} 확정된 근무가 있어 지원할 수 없습니다.`
          );
        } else {
          // 기존 단기 vs 신규 장기
          const sDateOnly = toDateOnly(appWorkDate);
          if (sDateOnly < newStartOnly || sDateOnly > newEndOnly) continue;
          const weekday = weekdayNames[appWorkDate.getDay()];
          if (!newWorkDays.includes(weekday)) continue;
          throw new HttpsError(
            "permission-denied",
            `${appWorkDate.getMonth() + 1}/${appWorkDate.getDate()}에 ${appStartTime}~${appEndTime} 확정된 근무가 있어 지원할 수 없습니다.`
          );
        }
      } else {
        // 신규 단기 지원 → 해당 날짜 충돌만 체크
        const workDateOnly = toDateOnly(workDateDate);
        const appDateOnly = toDateOnly(appWorkDate);

        if (isLongTermApp) {
          const appWorkEndDateTs = app["workEndDate"] as admin.firestore.Timestamp | undefined;
          const appActualResignDateTs = app["actualResignDate"] as admin.firestore.Timestamp | undefined;
          const sEnd = appActualResignDateTs?.toDate() ?? appWorkEndDateTs?.toDate() ?? new Date(9999, 11, 31);
          const sStartOnly = toDateOnly(appWorkDate);
          const sEndOnly = toDateOnly(sEnd);
          if (workDateOnly < sStartOnly || workDateOnly > sEndOnly) continue;
          const appWorkDays = (app["workDays"] as string[] | undefined) ?? [];
          const weekday = weekdayNames[workDateDate.getDay()];
          if (!appWorkDays.includes(weekday)) continue;
          throw new HttpsError(
            "permission-denied",
            `이미 ${appStartTime}~${appEndTime}에 확정된 근무가 있습니다.`
          );
        } else {
          if (appDateOnly.getTime() !== workDateOnly.getTime()) continue;
          throw new HttpsError(
            "permission-denied",
            `이미 ${appStartTime}~${appEndTime}에 확정된 근무가 있습니다.`
          );
        }
      }
    }

    // ── 7. 트랜잭션: 최종 재검증 + 지원서 set/update + 카운터 원자화 ──
    const appRef = db.collection("applications").doc(complexId);
    const toRef = db.collection("tos").doc(toId);
    const slotRef = slotId
      ? db.collection("tos").doc(toId).collection("slots").doc(slotId)
      : null;

    await db.runTransaction(async (tx) => {
      // [V3-FIX] TOCTOU: appRef 트랜잭션 내 재확인 — 동시 이중 제출 시 pendingCount +2 방지
      const existingInTx = await tx.get(appRef);
      let txIsReactivation = false;
      if (existingInTx.exists) {
        const exD = existingInTx.data()!;
        const exS = (exD["status"] as string | undefined) ?? "";
        const isResignDone = exD["resignStatus"] === "APPROVED" || exD["resignStatus"] === "AUTO_APPROVED";
        const isTermDone = exD["terminationStatus"] === "APPROVED" || exD["terminationStatus"] === "AUTO_APPROVED";
        if (!isResignDone && !isTermDone) {
          if (["CONFIRMED", "CONTRACT_PENDING", "PENDING"].includes(exS)) {
            throw new HttpsError("already-exists", "이미 지원한 업무입니다.");
          }
          if (["CANCELED", "AUTO_CANCELED", "REJECTED"].includes(exS)) {
            txIsReactivation = true;
          }
        }
      }
      isReactivation = txIsReactivation; // 트랜잭션 성공 후 반환값에 반영

      // TOCTOU 방지: 트랜잭션 내 최종 마감·정원 재검증
      if (slotRef) {
        const latestSlot = await tx.get(slotRef);
        if (!latestSlot.exists) throw new HttpsError("not-found", "해당 날짜 정보를 찾을 수 없습니다.");
        const ld = latestSlot.data()!;
        if (ld["isManualClosed"] === true || ld["status"] === "closed") {
          throw new HttpsError("permission-denied", "방금 마감된 날짜입니다.");
        }
        const rawWD = (ld["workDetails"] as unknown[]) ?? [];
        const wd = (rawWD as Record<string, unknown>[]).find(
          (x) => x["workType"] === selectedWorkType
        ) ?? {};
        const dtTs = wd["applicationDeadline"] as admin.firestore.Timestamp | undefined;
        if (dtTs && dtTs.toDate() < new Date()) {
          throw new HttpsError("permission-denied", "방금 마감된 업무입니다.");
        }
        const req = (wd["requiredCount"] as number | undefined) ?? 0;
        const rawCounts = ld["workTypeCounts"] as Record<string, Record<string, number>> | undefined;
        const cnt = rawCounts?.[selectedWorkType]?.["confirmedCount"] ?? 0;
        if (req > 0 && cnt >= req) {
          throw new HttpsError("permission-denied", "방금 마감된 업무입니다. (정원 초과)");
        }
      } else {
        const latestTO = await tx.get(toRef);
        if (!latestTO.exists) throw new HttpsError("not-found", "공고를 찾을 수 없습니다.");
        const ld = latestTO.data()!;
        if (ld["isManualClosed"] === true || ld["status"] === "CLOSED") {
          throw new HttpsError("permission-denied", "방금 마감된 공고입니다.");
        }
        const dtTs = ld["applicationDeadline"] as admin.firestore.Timestamp | undefined;
        if (dtTs && dtTs.toDate() < new Date()) {
          throw new HttpsError("permission-denied", "지원 마감 시간이 지났습니다.");
        }
        const confirmedCount = (ld["totalConfirmed"] as number | undefined) ?? 0;
        const totalRequired = (ld["totalRequired"] as number | undefined) ?? 0;
        if (totalRequired > 0 && confirmedCount >= totalRequired) {
          throw new HttpsError("permission-denied", "방금 마감된 공고입니다. (정원 초과)");
        }
        const rawWDList = (ld["workDetails"] as unknown[]) ?? [];
        const workTypeConfirmed =
          ((ld["workTypeConfirmedCounts"] as Record<string, number> | undefined)
            ?.[selectedWorkType]) ?? 0;
        for (const wd of rawWDList as Record<string, unknown>[]) {
          if (wd["workType"] === selectedWorkType) {
            const wtr = (wd["requiredCount"] as number | undefined) ?? 0;
            if (wtr > 0 && workTypeConfirmed >= wtr) {
              throw new HttpsError("permission-denied", "방금 마감된 업무입니다. (정원 초과)");
            }
            break;
          }
        }
      }

      const now = admin.firestore.Timestamp.now();
      const historyEntry = {
        status: "PENDING",
        at: now,
        by: null,
        action: txIsReactivation ? "REAPPLY" : "APPLY",
      };

      if (txIsReactivation) {
        const reactivateData: Record<string, unknown> = {
          status: "PENDING",
          type: isContract ? "long_term" : "short",
          appliedAt: admin.firestore.FieldValue.serverTimestamp(),
          workDate,
          // [V5-FIX] 재지원 시 임금·시간 갱신 — TO 임금 변경 후 재지원 시 구버전 잔류 방지
          wage: effectiveWage, wageType: effectiveWageType,
          startTime, endTime,
          statusHistory: admin.firestore.FieldValue.arrayUnion(historyEntry),
          canceledAt: null, cancelReason: null,
          rejectedAt: null, rejectedBy: null, rejectMessage: null,
          confirmedAt: null, confirmedBy: null,
          conflictingAppId: null, conflictingBusiness: null, conflictingTime: null,
          resignStatus: null, resignRequestedAt: null, resignRequestDate: null,
          actualResignDate: null,
          terminationStatus: null, terminationRequestedAt: null,
          terminationEffectiveDate: null, terminationRejectReason: null,
        };
        if (slotId) reactivateData["slotId"] = slotId;
        if (workDetailId && workDetailId.length > 0) reactivateData["workDetailId"] = workDetailId;
        if (desiredStartDate) reactivateData["desiredStartDate"] = desiredStartDate;
        if (workEndDate) reactivateData["workEndDate"] = workEndDate;
        if (workDays) reactivateData["workDays"] = workDays;
        tx.update(appRef, reactivateData);
      } else {
        const setData: Record<string, unknown> = {
          uid, businessId, businessName, toId, toTitle,
          selectedWorkType,
          // [V7-FIX] 서버 TO 문서 임금 사용 (클라이언트 제공값 폴백)
          wage: effectiveWage, wageType: effectiveWageType,
          startTime, endTime,
          status: "PENDING",
          type: isContract ? "long_term" : "short",
          appliedAt: admin.firestore.FieldValue.serverTimestamp(),
          workDate,
          statusHistory: [historyEntry],
        };
        if (slotId) setData["slotId"] = slotId;
        if (workDetailId && workDetailId.length > 0) setData["workDetailId"] = workDetailId;
        if (workTypeIcon) setData["workTypeIcon"] = workTypeIcon;
        if (workTypeColor) setData["workTypeColor"] = workTypeColor;
        if (workTypeBackgroundColor) setData["workTypeBackgroundColor"] = workTypeBackgroundColor;
        if (isContract) {
          if (workEndDate) setData["workEndDate"] = workEndDate;
          if (workDays) setData["workDays"] = workDays;
          if (desiredStartDate) setData["desiredStartDate"] = desiredStartDate;
        }
        tx.set(appRef, setData);
      }

      // totalPending / pendingCount 원자 증감 (기존 _incrementTOPending와 동일)
      tx.update(toRef, {totalPending: admin.firestore.FieldValue.increment(1)});
      if (slotRef) {
        tx.update(slotRef, {pendingCount: admin.firestore.FieldValue.increment(1)});
      }
    });

    console.log(`✅ [applyToTO] ${isReactivation ? "재지원" : "신규 지원"} 완료: ${complexId}`);
    return {success: true, applicationId: complexId, isReactivation};
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// [V9-FIX] callableManageBusiness
//   슈퍼어드민 전용 사업장 상태 관리 (승인/비활성화/재활성화)
//   Trust Boundary Charter: 법적 상태 전이(isApproved) + 감사 추적 필드(*By) CF 전용
// ─────────────────────────────────────────────────────────────────────────────
export const callableManageBusiness = onCall(
  {region: "asia-northeast3", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const callerUid = request.auth.uid;

    const {action, businessId} = request.data as {action: string; businessId: string};

    if (!businessId || typeof businessId !== "string" || businessId.trim() === "") {
      throw new HttpsError("invalid-argument", "businessId가 필요합니다.");
    }
    if (!["approve", "deactivate", "reactivate"].includes(action)) {
      throw new HttpsError("invalid-argument", "유효하지 않은 action입니다. (approve|deactivate|reactivate)");
    }

    // 슈퍼어드민 권한 검증
    const callerSnap = await db.collection("users").doc(callerUid).get();
    if (!callerSnap.exists) throw new HttpsError("not-found", "호출자 정보를 찾을 수 없습니다.");
    const callerRole = (callerSnap.data() as Record<string, unknown>)?.role as string | undefined;
    if (callerRole !== "SUPER_ADMIN") {
      throw new HttpsError("permission-denied", "슈퍼어드민만 사용할 수 있습니다.");
    }

    const bizRef = db.collection("businesses").doc(businessId);
    const bizSnap = await bizRef.get();
    if (!bizSnap.exists) throw new HttpsError("not-found", "사업장을 찾을 수 없습니다.");

    let updateData: Record<string, unknown>;
    if (action === "approve") {
      updateData = {
        isApproved: true,
        approvedAt: admin.firestore.FieldValue.serverTimestamp(),
        approvedBy: callerUid,
      };
    } else if (action === "deactivate") {
      updateData = {
        deactivatedAt: admin.firestore.FieldValue.serverTimestamp(),
        deactivatedBy: callerUid,
      };
    } else {
      // reactivate
      updateData = {
        deactivatedAt: admin.firestore.FieldValue.delete(),
        reactivatedAt: admin.firestore.FieldValue.serverTimestamp(),
        reactivatedBy: callerUid,
      };
    }

    await bizRef.update(updateData);
    console.log(`✅ [callableManageBusiness] action=${action} businessId=${businessId} by=${callerUid}`);
    return {success: true};
  }
);
