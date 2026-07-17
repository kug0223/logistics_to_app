import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/core/user_model.dart';
import '../utils/toast_helper.dart';
import '../utils/encryption_helper.dart';
import 'fcm_service.dart';
import 'firestore_service.dart';
import 'storage_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 현재 사용자 스트림
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // 현재 사용자
  User? get currentUser => _auth.currentUser;

  // 로그인 (아이디 기반)
  Future<UserModel?> signIn(String username, String password) async {
    // 기존 세션 완전 정리 — 비밀번호 재설정 후 토큰이 무효화된 경우 stale 상태 방지
    try { await _auth.signOut(); } catch (_) {}

    try {
      // 1. CF 경유: username → email 조회 (비인증 직접 쿼리 대신 CF 사용 — M-3 정책)
      final emailCallable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetEmailByUsername',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 15)));
      final emailResult = await emailCallable.call<Map<String, dynamic>>({'username': username});
      final email = emailResult.data['email'] as String?;

      if (email == null || email.isEmpty) {
        throw Exception('아이디 또는 비밀번호가 올바르지 않습니다.');
      }

      // 2. 이메일로 Firebase Auth 로그인
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (result.user != null) {
        // 3. Firestore에서 최신 사용자 정보 가져오기
        DocumentSnapshot doc = await _firestore
            .collection('users')
            .doc(result.user!.uid)
            .get();

        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>;

          // 블랙리스트 체크
          if (data['isBlacklisted'] == true) {
            final reason = data['blacklistReason'] as String? ?? '이용 정책 위반';
            await _auth.signOut();
            throw Exception('이용 제한된 계정입니다.\n사유: $reason\n고객센터에 문의해주세요.');
          }

          // 가입 승인 상태 체크
          final status = data['accountStatus'] as String? ?? 'active';
          if (status == 'pending') {
            await _auth.signOut();
            throw Exception('가입 승인 대기 중입니다.\n슈퍼관리자 승인 후 이용 가능합니다.');
          }
          if (status == 'rejected') {
            await _auth.signOut();
            final reason = data['rejectionReason'] as String?;
            final msg = reason != null
                ? '가입이 거절되었습니다.\n사유: $reason'
                : '가입이 거절되었습니다.\n고객센터에 문의해주세요.';
            throw Exception(msg);
          }

          // 제재 기간 체크
          final restrictedUntilTs = data['restrictedUntil'];
          if (restrictedUntilTs is Timestamp) {
            final restrictedDate = restrictedUntilTs.toDate().toLocal();
            if (restrictedDate.isAfter(DateTime.now())) {
              await _auth.signOut();
              // 9999년이면 사실상 영구 제한
              final isPermanent = restrictedDate.year >= 9999;
              final message = isPermanent
                  ? '노쇼 누적으로 서비스 이용이 영구 제한되었습니다.\n해제를 원하시면 고객센터에 문의해 주세요.'
                  : '노쇼로 인해 ${restrictedDate.year}년 ${restrictedDate.month}월 ${restrictedDate.day}일까지 이용이 제한됩니다.\n'
                    '(노쇼 1회=3일 · 2회=7일 · 3회=30일 제한)\n고객센터: 문의하기 메뉴 이용';
              throw Exception(message);
            }
          }

          // 4. 마지막 로그인 시간 업데이트
          await _firestore.collection('users').doc(result.user!.uid).update({
            'lastLoginAt': FieldValue.serverTimestamp(),
          });

          return UserModel.fromMap(
            data,
            result.user!.uid,
          );
        } else {
          throw Exception('사용자 정보를 찾을 수 없습니다.');
        }
      }
      return null;
      
    } on FirebaseAuthException catch (e) {
      String message = '로그인에 실패했습니다.';
      switch (e.code) {
        case 'user-not-found':
        case 'wrong-password':
          message = '아이디 또는 비밀번호가 올바르지 않습니다.';
          break;
        case 'invalid-email':
          message = '계정 정보에 문제가 있습니다.';
          break;
        case 'user-disabled':
          message = '비활성화된 계정입니다.';
          break;
        case 'too-many-requests':
          message = '너무 많은 로그인 시도가 있었습니다.\n잠시 후 다시 시도해주세요.';
          break;
        case 'invalid-credential':
          message = '아이디 또는 비밀번호가 올바르지 않습니다.';
          break;
        case 'network-request-failed':
          message = '네트워크 연결을 확인해주세요.';
          break;
      }
      throw Exception(message);

    } on FirebaseException catch (e) {
      // Firestore 예외 (FirebaseAuthException이 아닌 것) — 네트워크·권한·토큰 만료 등
      debugPrint('❌ [signIn] FirebaseException: ${e.code} / ${e.message}');
      String message;
      if (e.code == 'permission-denied' || e.code == 'unauthenticated') {
        message = '인증이 만료되었습니다. 다시 시도해주세요.';
      } else if (e.code == 'unavailable' || e.code == 'network-request-failed') {
        message = '네트워크 연결을 확인해주세요.';
      } else {
        message = '로그인 중 오류가 발생했습니다.';
      }
      throw Exception(message);

    } catch (e) {
      // 내부에서 의도적으로 throw한 Exception은 그대로 전파 (메시지가 이미 사용자 친화적)
      debugPrint('❌ [signIn] 알 수 없는 오류: $e');
      if (e is Exception) rethrow;
      throw Exception('로그인 중 오류가 발생했습니다.');
    }
  }

  // ⭐ 개선된 회원가입 - 주민번호 기반 + 서류 업로드 + 통장정보
  Future<UserModel?> signUp({
    required String username,
    required String password,
    required String name,
    String? phone,
    UserRole role = UserRole.USER,
    String? businessId,
    // ⭐ 주민번호 기반 필드
    String? gender,
    DateTime? birthDate,
    String? residentNumber,
    // PASS 인증 필드
    String? ci,
    String? foreignIdNumber,
    String accountStatus = 'active',
    // 주소 기반 필드
    String? address,
    String? detailAddress,
    // ⭐ 서류 업로드 필드
    String? idCardImageUrl,           // 신분증 앞면 (지원자)
    String? bankbookImageUrl,         // 통장 사본 (지원자)
    String? businessLicenseImageUrl,  // 사업자등록증 (사업자)
    // ✅ 사업자 정보 추가
    String? businessNumber,
    String? businessName,
    String? ceoName,
    // ✅ 통장 정보 추가
    String? bankName,
    String? accountNumber,
  }) async {
    try {
      // ⭐ 시스템 이메일 생성 (Firebase Auth용)
      final systemEmail = '$username@ALfit-system.com';
      // Firebase Auth 계정 생성
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: systemEmail,
        password: password,
      );

      if (result.user != null) {
        // Firestore에 사용자 정보 저장
        UserModel newUser = UserModel(
          uid: result.user!.uid,
          username: username,
          name: name,
          email: systemEmail,         // 시스템 이메일
          phone: phone,
          role: role,
          businessId: businessId,
          createdAt: DateTime.now(),
          lastLoginAt: DateTime.now(),
          // ⭐ 주민번호 기반 정보
          gender: gender,
          birthDate: birthDate,
          residentNumber: residentNumber,
          // PASS 인증 정보
          ci: ci,
          foreignIdNumber: foreignIdNumber,
          accountStatus: accountStatus,
          // ⭐ 주소 추가!
          address: address,
          detailAddress: detailAddress,
          // ⭐ 서류 이미지
          idCardImageUrl: idCardImageUrl,
          bankbookImageUrl: bankbookImageUrl,
          businessLicenseImageUrl: businessLicenseImageUrl,
          // ✅ 사업자 정보 추가
          businessNumber: businessNumber,
          businessName: businessName,
          ceoName: ceoName,
          // ✅ 통장 정보 추가
          bankName: bankName,
          accountNumber: accountNumber,
          accountHolder: name,  // 예금주는 본인 이름으로 자동 설정
        );

        try {
          await _firestore
              .collection('users')
              .doc(result.user!.uid)
              .set(newUser.toMap()
                ..['createdAt'] = FieldValue.serverTimestamp()
                ..['lastLoginAt'] = FieldValue.serverTimestamp());
        } catch (firestoreError) {
          // Firestore 저장 실패 시 Auth 계정 롤백 (고아 계정 방지)
          try {
            await result.user!.delete();
          } catch (deleteError) {
            debugPrint('⚠️ Auth 롤백 실패: $deleteError');
          }
          throw Exception('Firestore 저장 실패: $firestoreError');
        }

        return newUser;
      }
      return null;
    } on FirebaseAuthException catch (e) {
      String message = '회원가입에 실패했습니다.';
      switch (e.code) {
        case 'email-already-in-use':
          // 가입 도중 앱 강제종료 시 Auth 계정만 생성된 고아 상태일 수 있음
          // Firestore에 해당 uid의 users 문서가 없으면 고아 계정으로 안내
          message = '이미 사용 중인 아이디입니다.\n'
              '가입 도중 오류가 발생한 경우 로그인 후 설정에서 탈퇴 후 재가입해주세요.';
          break;
        case 'invalid-email':
          message = '유효하지 않은 이메일 형식입니다.';
          break;
        case 'weak-password':
          message = '비밀번호가 너무 약합니다.\n6자 이상 입력해주세요.';
          break;
        case 'operation-not-allowed':
          message = '이메일/비밀번호 로그인이 비활성화되어 있습니다.';
          break;
      }
      throw Exception(message);
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('회원가입 중 오류가 발생했습니다.');
    }
  }

  // 사업장 관리자 회원가입 (슈퍼관리자만 호출 가능)
  Future<UserModel?> signUpBusinessAdmin({
    required String username,
    required String password,
    required String name,
    required String businessId,
    String? phone,
    String? gender,
    DateTime? birthDate,
    String? residentNumber,
  }) async {
    return signUp(
      username: username,
      password: password,
      name: name,
      phone: phone,
      role: UserRole.BUSINESS_ADMIN,
      businessId: businessId,
      gender: gender,
      birthDate: birthDate,
      residentNumber: residentNumber,
    );
  }

  // 로그아웃
  Future<void> signOut() async {
    try {
      final uid = _auth.currentUser?.uid;
      final fs = FirestoreService();
      fs.invalidateGlobalTOLimitCache();
      if (uid != null) fs.invalidateAdminTOLimitCache(uid);
      await _auth.signOut();
      ToastHelper.showInfo('로그아웃되었습니다.');
    } catch (e) {
      throw Exception('로그아웃 중 오류가 발생했습니다.');
    }
  }

  // 사용자 정보 가져오기
  Future<UserModel?> getUserData(String uid) async {
    try {
      DocumentSnapshot doc =
          await _firestore.collection('users').doc(uid).get();

      if (doc.exists) {
        return UserModel.fromMap(
          doc.data() as Map<String, dynamic>,
          uid,
        );
      }
      return null;
    } catch (e) {
      debugPrint('사용자 정보 가져오기 실패: $e');
      return null;
    }
  }

  // ⭐ NEW: 비밀번호 재설정 이메일 발송
  /// @deprecated 시스템 이메일 체계([username]@ALfit-system.com)와 호환되지 않음.
  /// 비밀번호 찾기는 Cloud Functions sendPasswordResetCode 방식으로 처리됨
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      ToastHelper.showSuccess('비밀번호 재설정 이메일이 발송되었습니다.');
    } on FirebaseAuthException catch (e) {
      String message = '이메일 발송에 실패했습니다.';
      switch (e.code) {
        case 'invalid-email':
          message = '유효하지 않은 이메일 형식입니다.';
          break;
        case 'user-not-found':
          message = '등록되지 않은 이메일입니다.';
          break;
      }
      throw Exception(message);
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('이메일 발송 중 오류가 발생했습니다.');
    }
  }

  // ⭐ NEW: 계정 삭제
  /// 비밀번호 재인증 후 계정 삭제
  /// returns null on success, error message string on failure
  // ══════════════════════════════════════════════════════════════════
  // 탈퇴 시 개인정보 처리 법령 근거 (2024년 기준)
  //
  // [즉시 파기 의무 — 개인정보보호법 제21조]
  //   보유 목적이 달성되거나 회원이 동의를 철회(탈퇴)한 경우 지체 없이 파기.
  //   단, 아래 법령에서 별도 보존 의무를 정한 경우는 해당 기간까지 예외.
  //   대상: users 문서, Storage 파일(신분증·통장), notifications,
  //         worker_locations, idCardAccessRequests
  //
  // [3년 보존 의무 — 근로기준법 제42조 + 시행령 제22조]
  //   근로계약서, 임금대장, 임금 계산 기초 서류, 출퇴근 기록 → 3년 보존.
  //   대상: attendance(완료·결근 기록), applications(급여 데이터 포함),
  //         employment_contracts
  //
  // [5년 보존 의무 — 국세기본법 제85조의3 / 소득세법 제143조]
  //   원천징수 관련 지급명세서 → 5년 보존.
  //   대상: applications의 wageDetail(세금 공제 내역)
  //
  // [익명화 처리 — 개인정보보호법 제21조 + 업계 관행]
  //   법령 보존 의무는 없으나 서비스 연속성(리뷰 통계, 사업주 이력)을 위해
  //   삭제 대신 개인 식별자만 "탈퇴한 회원"으로 대체.
  //   카카오·당근마켓·크몽 등 동일 방식 채택.
  //   대상: monthly_reviews(targetUserName), review_requests(workerName)
  //
  // [점검 TODO]
  //   - 보존 기간(3년/5년) 경과 후 자동 파기 Cloud Scheduler 미구현.
  //     → Cloud Functions에서 createdAt 기준 만료 레코드 정기 삭제 필요.
  //   - attendance/applications 내 applicantName, phone 등 식별자는
  //     법령 보존 기간 중 마스킹 없이 유지. 기간 종료 시 파기 필요.
  // ══════════════════════════════════════════════════════════════════
  Future<String?> deleteAccountWithPassword(String password) async {
    try {
      final user = _auth.currentUser;
      if (user == null || user.email == null) return '로그인이 필요합니다';

      // 1. 재인증
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);

      // [BUG-수정] A-M-1: FCM 토큰을 Firestore users 문서 삭제 전에 제거
      // 삭제 후 clearToken() 호출 시 users 문서가 없어 update() 오류 발생하던 문제 수정
      await FCMService().clearToken();

      // 2. 탈퇴 기록 저장 (재가입 30일 제한용)
      // [AUTH-H2] deleted_accounts 직접 쓰기 → CF(Admin SDK) 경유로 전환
      //   CF가 users 문서에서 ciHash·phone을 직접 읽어 서버에서 처리하므로
      //   클라이언트 EncryptionHelper 복호화 불필요.
      try {
        await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
            .httpsCallable('recordDeletedAccount',
                options: HttpsCallableOptions(timeout: const Duration(seconds: 10)))
            .call();
      } catch (e) {
        debugPrint('⚠️ 탈퇴 기록 저장 실패 (계속 진행): $e');
        // best-effort — 기록 실패해도 계정 삭제는 진행
      }

      // [M-01 fix] 스텝 11(BUSINESS_ADMIN 사업장 정리)에서 users 문서가 필요하므로
      // 삭제 전에 role·businessId를 미리 읽어둔다.
      // 삭제 후 재조회하면 exists=false → 사업장 비활성화 로직이 실행되지 않는 버그.
      String? preDeleteRole;
      String? preDeleteBusinessId;
      try {
        final preDoc = await _firestore.collection('users').doc(user.uid).get();
        preDeleteRole = preDoc.data()?['role'] as String?;
        preDeleteBusinessId = preDoc.data()?['businessId'] as String?;
      } catch (_) {}

      // 3-pre~3-pre3/3-pre6/3-pre7: 개인정보 익명화 & 연관 문서 삭제
      // [CF-MIGRATED 2026-07-15] callableDeleteAccountPreData CF 이전 (병렬 처리)
      //   · review_requests workerId 익명화 (SEC-88)
      //   · monthly_reviews targetUserId/reviewerId 익명화 (SEC-92)
      //   · idCardAccessRequests 전체 삭제 (SEC-93)
      //   · trust_score_history userId 익명화 (WARN-AUTH-01)
      //   · member_invitations 삭제 + invitedBy 익명화 (WARN-AUTH-02)
      // Admin SDK → 각 컬렉션 LIST isSuperAdmin only 규칙 우회
      try {
        final preDataCallable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
            .httpsCallable('callableDeleteAccountPreData',
                options: HttpsCallableOptions(timeout: const Duration(seconds: 120)));
        final result = await preDataCallable.call<Map<String, dynamic>>({});
        final data = Map<String, dynamic>.from(result.data as Map? ?? {});
        final failed = List<String>.from(data['failedOps'] as List? ?? []);
        if (failed.isNotEmpty) debugPrint('⚠️ 계정 삭제: 사전정리 일부 실패 ($failed)');
      } catch (e) {
        debugPrint('⚠️ 계정 삭제: 개인정보 사전정리 실패 (계속 진행): $e');
      }

      // 3-pre4. applications 활성 상태 → CANCELED + attendance scheduled → absent
      // [CF-MIGRATED 2026-07-15] callableDeleteAccountApplications CF 이전
      //   · applications LIST는 기존 isUser() 직접 쿼리 → rules 차단됨 (isSuperAdmin only)
      //   · CONFIRMED/CONTRACT_PENDING → CANCELED는 USER update 규칙 불허 → CF Admin SDK 필요
      //   · CF가 한 번의 배치로 모두 처리 후 pendingToIds/confirmedApps 반환
      try {
        final deleteAppsCallable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
            .httpsCallable('callableDeleteAccountApplications',
                options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
        final result = await deleteAppsCallable.call<Map<String, dynamic>>({});
        final data = Map<String, dynamic>.from(result.data as Map);

        // PENDING totalPending 개별 트랜잭션 감소 (rules ±1 제한 준수 — CF Admin SDK도 rules 우회 가능하나 기존 패턴 유지)
        //   [M-5A 수정] flex TO에서 동일 TO에 다른 workType으로 PENDING 복수 지원 가능
        //   → Map<toId, count> + increment(-N) 패턴은 rules ±1 제한 위반 → 건별 트랜잭션 유지
        final pendingToIds = List<String>.from(data['pendingToIds'] as List? ?? []);
        if (pendingToIds.isNotEmpty) {
          await Future.wait(pendingToIds.map((toId) async {
            try {
              await _firestore.runTransaction((tx) async {
                tx.update(_firestore.collection('tos').doc(toId), {'totalPending': FieldValue.increment(-1)});
              });
            } catch (e) {
              debugPrint('⚠️ totalPending 감소 실패 ($toId): $e');
            }
          }));
        }

        // CONFIRMED/CONTRACT_PENDING: slot 카운터 감소 (callableDecrementSlotConfirmed CF 경유)
        final confirmedApps = (data['confirmedApps'] as List? ?? [])
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
        if (confirmedApps.isNotEmpty) {
          final decrementCallable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
              .httpsCallable('callableDecrementSlotConfirmed',
                  options: HttpsCallableOptions(timeout: const Duration(seconds: 15)));
          await Future.wait(confirmedApps.map((app) async {
            try {
              await decrementCallable.call<Map<String, dynamic>>({
                'applicationId': app['id'],
                'toId': app['toId'],
                'slotId': app['slotId'],
                'workType': app['workType'],
              });
            } catch (e) {
              debugPrint('⚠️ totalConfirmed 감소 실패 (${app['id']}): $e');
            }
          }));
        }
      } catch (e) {
        debugPrint('⚠️ 계정 삭제: applications/attendance 정리 실패 (계속 진행): $e');
      }

      // 3-pre5. worker_locations 전체 삭제 — users 문서 삭제 전 처리 필수 (SEC-94)
      // 위치정보: 개인정보보호법 제21조 (법령 보존 근거 없음 — 즉시 파기 대상)
      // [CF-MIGRATED 2026-07-15] callableDeleteWorkerLocations CF 이전
      //   · worker_locations LIST USER 직접 쿼리 제거 → Admin SDK 경유
      try {
        final deleteLocsCallable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
            .httpsCallable('callableDeleteWorkerLocations',
                options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
        await deleteLocsCallable.call<Map<String, dynamic>>({});
      } catch (e) {
        debugPrint('⚠️ 계정 삭제: worker_locations 삭제 실패 (계속 진행): $e');
      }

      // 3-pre6/3-pre7: [CF-MIGRATED 2026-07-15] callableDeleteAccountPreData에서 처리 완료
      // trust_score_history + member_invitations 모두 3-pre 단계에서 병렬 처리됨

      // 3. Firestore 사용자 문서 삭제 — 개인정보보호법 제21조
      // Storage URL 참조를 먼저 제거해야 broken URL 방지 (CLAUDE.md 삭제 순서 규칙)
      await _firestore.collection('users').doc(user.uid).delete();

      // 4. Storage 사용자 파일 삭제 — 개인정보보호법 제21조 (민감정보: 신분증·통장사본)
      try {
        final storageRef = FirebaseStorage.instance.ref('users/${user.uid}');
        final listResult = await storageRef.listAll();
        for (final item in listResult.items) { await item.delete(); }
        for (final prefix in listResult.prefixes) {
          final sub = await prefix.listAll();
          for (final item in sub.items) { await item.delete(); }
        }
      } catch (storageErr) {
        debugPrint('⚠️ Storage 파일 삭제 실패 (계속 진행): $storageErr');
      }

      // 5. notifications 서브컬렉션 전체 삭제 — 개인정보보호법 제21조
      // 경로: users/{uid}/notifications/{id}
      // [J-003] 실패 시 계정 삭제는 계속 진행
      try {
        bool hasMore = true;
        while (hasMore) {
          final snap = await _firestore
              .collection('users')
              .doc(user.uid)
              .collection('notifications')
              .limit(200)
              .get();
          if (snap.docs.isEmpty) break;
          hasMore = snap.docs.length == 200;
          final batch = _firestore.batch();
          for (final doc in snap.docs) { batch.delete(doc.reference); }
          await batch.commit();
        }
      } catch (e) {
        debugPrint('⚠️ 계정 삭제: notifications 삭제 실패 (계속 진행): $e');
      }

      // 11. BUSINESS_ADMIN 전용 사업장 데이터 정리
      // ──────────────────────────────────────────────────────────────
      // 사업주 탈퇴 시 처리 원칙:
      //
      //   [공동 관리자 있음] adminIds에서 본인 uid만 제거. 사업장은 계속 운영.
      //
      //   [단독 관리자] businesses 문서에 deactivatedAt 기록 후:
      //     - 활성 TO(ACTIVE/FULL/SCHEDULED) → CLOSED (orphan 방지)
      //     - 활성 TO 하위 PENDING 지원서 → REJECTED(BUSINESS_DEACTIVATED)
      //       (근로기준법 보존 의무 없는 미확정 지원서이므로 즉시 처리)
      //     - CONFIRMED/CONTRACT_PENDING 지원서는 이미 급여 데이터 포함 가능 →
      //       cancelReason: 'BUSINESS_DEACTIVATED'로 CANCELED 처리
      //       (근로기준법 제42조: 해당 기록은 3년 보존 — 삭제 금지)
      //   [점검] businesses Storage(로고·사진)는 개인정보가 아니므로 보존.
      //          슈퍼관리자가 비활성 사업장 일괄 정리 시 삭제 예정.
      // ──────────────────────────────────────────────────────────────
      // [M-01 fix] 스텝 3에서 users 문서를 삭제했으므로 재조회 불가.
      // 삭제 전에 미리 읽어둔 preDeleteRole·preDeleteBusinessId 사용.
      if (preDeleteRole == 'BUSINESS_ADMIN' && preDeleteBusinessId != null) {
        final businessId = preDeleteBusinessId;
        try {
            final bizRef = _firestore.collection('businesses').doc(businessId);
            final bizDoc = await bizRef.get();

            if (bizDoc.exists) {
              final adminIds = List<String>.from(bizDoc.data()?['adminIds'] ?? []);
              // adminIds가 비어있는 비정상 상태(Firestore 데이터 불일치)에서는
              // 단독 관리자로 처리하지 않음 — 자신의 uid가 목록에 포함된 경우에만 단독 판단.
              // 이전 코드: length <= 1 → 빈 배열([])도 단독 관리자로 오인하는 버그 존재.
              final isSoleAdmin = adminIds.length == 1 && adminIds.contains(user.uid);

              if (isSoleAdmin) {
                // ── 단독 관리자 → 사업장 비활성화 ────────────────────────
                // Firestore 문서에 deactivatedAt 기록.
                // sealBase64는 businesses 문서에서 제거됨 — users/{uid} 문서에만 저장.
                // users 문서의 sealBase64는 하단 계정 삭제 단계에서 파기된다.
                await bizRef.update({
                  'deactivatedAt': FieldValue.serverTimestamp(),
                });

                // [CF 위임] 활성 TO 자동 CLOSED + PENDING 지원서 REJECTED 처리는
                // onBusinessDeactivated Cloud Function(index.ts)이 담당한다.
                // deactivatedAt 필드 추가 → Firestore 트리거 → 1~5초 내 자동 실행.
                // Admin SDK 사용으로 Firestore 보안 규칙 우회 가능.

                // ── Storage 이미지 삭제 ────────────────────────────────────
                // businesses 문서에 저장된 URL 기반으로 삭제.
                // mainImageUrl: 대표 이미지 1장
                // imageUrls: 사업장 사진 최대 5장
                // 비활성 사업장 이미지는 앱에서 더 이상 표시되지 않으므로
                // Storage 비용 방지를 위해 탈퇴 시 즉시 삭제.
                // employment_contracts 내 서명 이미지는 근로기준법 3년 보존 대상 — 삭제 금지.
                //
                // 삭제 순서: Firestore URL 필드 먼저 → Storage 나중 (CLAUDE.md 규칙)
                // Firestore 업데이트 실패 시 Storage는 건드리지 않아 broken URL 잔존 방지.
                // Storage 삭제 실패는 개별 try/catch로 포획 — Firestore가 이미 정리됐으므로
                // 앱 동작에는 영향 없음 (Storage orphan은 주기적 정리로 처리 예정).
                try {
                  final bizData = bizDoc.data()!;
                  final mainImageUrl = bizData['mainImageUrl'] as String?;
                  final imageUrlsRaw = bizData['imageUrls'] as List<dynamic>?;
                  final imageUrls = imageUrlsRaw?.cast<String>() ?? [];
                  // [MEDIUM-1 수정] transportImageUrls 누락으로 교통편 사진 고아 발생
                  final transportUrlsRaw = bizData['transportImageUrls'] as List<dynamic>?;
                  final transportUrls = transportUrlsRaw?.cast<String>() ?? [];

                  final allUrls = [
                    if (mainImageUrl != null && mainImageUrl.isNotEmpty) mainImageUrl,
                    ...imageUrls.where((u) => u.isNotEmpty),
                    ...transportUrls.where((u) => u.isNotEmpty),
                  ];

                  if (allUrls.isNotEmpty) {
                    // 1단계: Firestore URL 필드 먼저 제거 (실패 시 Storage 건드리지 않음)
                    await bizRef.update({
                      'mainImageUrl': FieldValue.delete(),
                      'imageUrls': FieldValue.delete(),
                      'transportImageUrls': FieldValue.delete(),
                    });

                    // 2단계: Storage 이미지 삭제 — businesses/ 경로는 storage.rules allow delete: if false
                    // → 직접 삭제 불가. callableDeleteBusinessImage CF 경유(StorageService 내부 처리).
                    await StorageService().deleteMultipleByUrls(allUrls);
                  }
                } catch (e) {
                  debugPrint('⚠️ 사업장 Storage 정리 실패 (계속 진행): $e');
                }

                // ── TO·지원서·계약서 정리 → onBusinessDeactivated CF 위임 ─
                // [CF 이전 2026-07-13] 클라이언트 직접 쿼리 전량 제거.
                // onBusinessDeactivated 트리거(Admin SDK)가 1~5초 내 자동 처리:
                //   ACTIVE/FULL/SCHEDULED TO → CLOSED
                //   PENDING 지원서 → REJECTED
                //   CONFIRMED/CONTRACT_PENDING 지원서 → CANCELED
                //   employment_contracts (pending_*) → voided
              } else {
                // 공동 관리자 있음 → adminIds에서 본인 uid만 제거
                await bizRef.update({
                  'adminIds': FieldValue.arrayRemove([user.uid]),
                });
              }
            }
          } catch (e) {
            debugPrint('⚠️ 계정 삭제: 사업장 정리 실패 (계속 진행): $e');
          }
        }

      // 12. Firebase Auth 계정 삭제 — 개인정보보호법 제21조 (이메일·로그인 정보)
      await user.delete();

      return null; // 성공
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'wrong-password':
        case 'invalid-credential':
          return '비밀번호가 일치하지 않습니다';
        case 'too-many-requests':
          return '시도 횟수를 초과했습니다. 잠시 후 다시 시도해주세요';
        default:
          return '계정 삭제에 실패했습니다 (${e.code})';
      }
    } catch (e) {
      debugPrint('❌ 계정 삭제 실패: $e');
      return '계정 삭제 중 오류가 발생했습니다';
    }
  }
  /// ⭐ 비밀번호 변경
  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null || user.email == null) {
        ToastHelper.showError('로그인이 필요합니다');
        return false;
      }
      
      // 1. 현재 비밀번호로 재인증
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);
      
      // 2. 비밀번호 변경
      await user.updatePassword(newPassword);

      // 3. [AUTH-M1] 다른 기기 세션 무효화 — best-effort (실패해도 비밀번호 변경은 유효)
      try {
        await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
            .httpsCallable('revokeUserSession',
                options: HttpsCallableOptions(timeout: const Duration(seconds: 10)))
            .call();
      } catch (e) {
        debugPrint('⚠️ [changePassword] revokeUserSession 실패: $e');
      }

      return true;
    } on FirebaseAuthException catch (e) {
      String message = '비밀번호 변경에 실패했습니다';
      switch (e.code) {
        case 'wrong-password':
        case 'invalid-credential':
          message = '현재 비밀번호가 일치하지 않습니다';
          break;
        case 'weak-password':
          message = '새 비밀번호가 너무 약합니다';
          break;
        case 'requires-recent-login':
          message = '보안을 위해 다시 로그인해주세요';
          break;
      }
      ToastHelper.showError(message);
      return false;
    } catch (e) {
      debugPrint('❌ 비밀번호 변경 실패: $e');
      ToastHelper.showError('비밀번호 변경 중 오류가 발생했습니다');
      return false;
    }
  }

  // 동일 전화번호 + 역할 중복 가입 체크
  // 같은 사람이 같은 역할로 이미 가입했는지 확인
  /// null = 네트워크 에러 (호출부에서 경고 표시 후 진행 결정)
  /// true = 중복 존재 / false = 중복 없음
  Future<bool?> checkDuplicateRegistration({
    required String phone,
    required UserRole role,
  }) async {
    try {
      // CF 경유: 비인증 직접 쿼리 대신 CF 사용 (M-3 정책)
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableCheckPhoneDuplicate',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 15)));
      final result = await callable.call<Map<String, dynamic>>({
        'phone': phone,
        'role': _roleToString(role),
      });
      return result.data['isDuplicate'] as bool?;
    } catch (e) {
      debugPrint('❌ 중복 가입 체크 실패: $e');
      return null;
    }
  }

  /// 사업자등록번호 중복 가입 체크 — 동일 번호로 BUSINESS_ADMIN 이미 존재하면 true
  Future<bool?> checkBusinessNumberDuplicate(String businessNumber) async {
    try {
      // CF 경유: 비인증 직접 쿼리 대신 CF 사용 (M-3 정책)
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableCheckBusinessNumberDuplicate',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 15)));
      final result = await callable.call<Map<String, dynamic>>({
        'businessNumber': businessNumber,
      });
      return result.data['isDuplicate'] as bool?;
    } catch (e) {
      debugPrint('❌ 사업자등록번호 중복 체크 실패: $e');
      return null;
    }
  }

  static String _roleToString(UserRole role) {
    switch (role) {
      case UserRole.SUPER_ADMIN:
        return 'SUPER_ADMIN';
      case UserRole.BUSINESS_ADMIN:
        return 'BUSINESS_ADMIN';
      case UserRole.USER:
        return 'USER';
    }
  }

  // [M-3] 아이디 중복 체크 — callableCheckUsername CF 경유 (PII 노출 차단)
  Future<bool> checkUsernameExists(String username) async {
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableCheckUsername')
          .call({'username': username});
      return (result.data as Map)['exists'] == true;
    } catch (e) {
      debugPrint('❌ 아이디 중복 체크 실패: $e');
      return true; // 에러 시 중복으로 간주
    }
  }

  // [M-3] 외국인등록번호 중복 체크 — callableCheckForeignIdExists CF 경유 (PII 노출 차단)
  // 동일 IV + AES 고정 암호화이므로 같은 입력 → 같은 암호문 → 서버 쿼리 가능
  Future<bool> checkForeignIdExists(String foreignIdNumber, UserRole role) async {
    try {
      final encrypted = EncryptionHelper.encrypt(foreignIdNumber);
      if (encrypted == null) return false;
      final result = await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableCheckForeignIdExists')
          .call({'foreignIdNumber': encrypted, 'role': _roleToString(role)});
      return (result.data as Map)['exists'] == true;
    } catch (e) {
      debugPrint('❌ 외국인등록번호 중복 체크 실패: $e');
      return true; // 에러 시 중복으로 간주
    }
  }

  // [M-3] 아이디 찾기 (이름 + 전화번호) — callableFindUsername CF 경유 (PII 노출 차단)
  Future<String?> findUsername({
    required String name,
    required String phone,
  }) async {
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableFindUsername')
          .call({'name': name, 'phone': phone});
      final username = (result.data as Map)['username'] as String?;
      if (username == null) {
        ToastHelper.showError('일치하는 사용자를 찾을 수 없습니다.');
        return null;
      }
      return username;
    } catch (e) {
      debugPrint('❌ 아이디 찾기 실패: $e');
      ToastHelper.showError('아이디 찾기 중 오류가 발생했습니다.');
      return null;
    }
  }
}
