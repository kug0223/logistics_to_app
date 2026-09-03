import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/core/user_model.dart';
import '../models/core/user_region.dart';
import '../utils/toast_helper.dart';
import '../utils/encryption_helper.dart';
import 'fcm_service.dart';
import 'firestore_service.dart';

/// [C안 F-01-3] 외국인 가입 중 약관 동의 CF 기록 실패 → 재로그인 시 복구 흐름
/// Auth 세션을 유지한 채 throw — signOut 없이 복구 화면으로 라우팅한다.
class IncompleteRegistrationException implements Exception {
  final String message;
  const IncompleteRegistrationException({
    this.message = '가입이 완전히 완료되지 않았습니다.',
  });
  @override
  String toString() => 'IncompleteRegistrationException: $message';
}

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 현재 사용자 스트림
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // 현재 사용자
  User? get currentUser => _auth.currentUser;

  // 로그인 (아이디 기반)
  Future<UserModel?> signIn(String username, String password) async {
    // 로그인 화면은 항상 로그아웃 상태에서 도달하므로 사전 signOut() 불필요.
    // 과거에 있던 signOut() 호출은 authStateChanges(null) 이벤트를 발생시켜
    // UserProvider의 _isLoading을 리셋하는 부작용이 있었음 → 제거.
    try {
      // Firebase Auth는 이메일 기반이지만, 이 앱은 사용자에게 이메일을 노출하지 않는다.
      // 회원가입 시 signUp()이 '$username@ALfit-system.com' 패턴으로 가상 이메일을 생성하므로
      // 로그인 시 CF 호출 없이 동일 패턴으로 직접 계산 가능 → cold-start 1-3초 제거.
      // (기존 callableGetEmailByUsername CF는 이 값을 Firestore에서 조회해 반환하던 것과 동일)
      final email = '$username@ALfit-system.com';

      // 1. Firebase Auth 로그인
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
          if (status == 'registration_pending') {
            // [V3] Document-First 가입 미완료 — Auth 세션 유지 + resume 흐름
            // ForeignRegisterScreen.resume()으로 라우팅하여 남은 단계 재개
            throw IncompleteRegistrationException(
              message: '가입 절차를 이어서 완료해주세요.',
            );
          }
          if (status == 'pending') {
            // 레거시 외국인 pending — V3 resume 흐름으로 흡수
            // termsConsentAt 유무와 무관하게 IncompleteRegistrationException 사용
            // callableRecordTermsConsent → active 전환 로직이 조건 확인 후 처리
            throw IncompleteRegistrationException(
              message: '가입 절차를 이어서 완료해주세요.',
            );
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
                    '(최근 90일 3회 이상 노쇼 시 1일 제한)\n고객센터: 문의하기 메뉴 이용';
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
          // [F-01-1 FIX] Auth 세션이 열린 채로 throw하면 앱이 인증된 고아 세션 상태로 남음
          //   → signOut()으로 Auth 세션 정리 후 예외 발생
          await _auth.signOut();
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
      // Firestore 예외 (블랙리스트·상태 조회 중 발생 가능)
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
    // 전화번호 시스템
    String? authPhone,
    String? phoneVerificationLevel,
    // 주소 기반 필드
    String? address,
    String? detailAddress,
    // 추천 지역 (USER 가입 시 필수, BUSINESS_ADMIN은 null)
    UserRegion? homeRegion,
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
          // 전화번호 시스템
          authPhone: authPhone,
          phoneVerificationLevel: phoneVerificationLevel,
          // ⭐ 주소 추가!
          address: address,
          detailAddress: detailAddress,
          // 추천 지역
          homeRegion: homeRegion,
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
  //
  // [showToast] 사용자가 의도적으로 로그아웃한 경우에만 true (기본값).
  // 고아 Auth 세션 정리(_loadUserData orphan path), 임시 세션 정리(비밀번호 재설정) 등
  // 내부 정리 목적 호출 시 false를 전달해 토스트를 억제한다.
  Future<void> signOut({bool showToast = true}) async {
    try {
      final uid = _auth.currentUser?.uid;
      final fs = FirestoreService();
      fs.invalidateGlobalTOLimitCache();
      if (uid != null) fs.invalidateAdminTOLimitCache(uid);
      await _auth.signOut();
      if (showToast) ToastHelper.showInfo('로그아웃되었습니다.');
    } catch (e) {
      throw Exception('로그아웃 중 오류가 발생했습니다.');
    }
  }

  // 사용자 정보 가져오기
  // [F-01-1 restore path] doc.exists==false → null 반환 (호출자가 고아 세션 처리)
  // 네트워크·파싱 예외는 rethrow → _loadUserData catch가 처리 (null과 구별 가능)
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
      return null; // users 문서 없음 — 고아 Auth session 가능성
    } catch (e) {
      debugPrint('사용자 정보 가져오기 실패: $e');
      rethrow; // 네트워크·파싱 오류는 호출자(_loadUserData)에서 처리
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
      } on FirebaseFunctionsException catch (e) {
        // [BUG-SEC FIX] CF 의도적 실패(code='internal'): 블랙리스트 deleted_accounts 기록 실패
        //   → rethrow로 탈퇴 전체 중단 — 블랙리스트 사용자가 ciHash/phoneHash 없이 재가입 가능해지는 보안 우회 차단
        //   네트워크 오류(unavailable/deadline-exceeded)는 best-effort로 계속 진행 (사전정리는 비필수)
        if (e.code == 'internal') rethrow;
        debugPrint('⚠️ 계정 삭제: 개인정보 사전정리 네트워크 오류 (계속 진행): $e');
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
        await deleteAppsCallable.call<Map<String, dynamic>>({});
        // [CF-MERGED 2026-08-10] pendingToIds·confirmedApps 카운터 감소:
        //   CF 내부(Admin SDK)로 통합 — 기존 N+1 CF 호출 제거
        //   전체 deleteAccountWithPassword: CF 4→3건 최적화
      } on FirebaseFunctionsException catch (e) {
        // [L-2 FIX] CF 오류 구분 로깅 — 카운터 오염 여부 사후 추적 가능
        // internal: counterBatch 실패 등 CF 내부 오류 (앱 취소 완료 + 카운터 미감소 가능)
        // deadline-exceeded: 타임아웃 → 부분 청크 반영 후 중단 가능성
        // 계속 진행은 유지 — Applications 실패로 Auth 삭제 차단 시 영구 탈퇴 불가 위험
        debugPrint('⚠️ 계정 삭제: applications CF 오류 [${e.code}] (계속 진행): $e');
      } catch (e) {
        debugPrint('⚠️ 계정 삭제: applications/attendance 정리 실패 (계속 진행): $e');
      }

      // [CF-MIGRATED 2026-08-10] callableDeleteAccountFinal:
      //   users 문서 삭제 → Storage(users/) 정리 → notifications 정리
      //   → BUSINESS_ADMIN: adminIds array-contains 쿼리로 복수 사업장 전체 처리
      //   → Firebase Auth 삭제(Admin SDK) — 마지막에 실행해 재시도 가능
      // [M-01 fix] businessId 단수 → adminIds array-contains 쿼리 (복수 사업장 모두 처리)
      final deleteFinalCallable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableDeleteAccountFinal',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 300)));
      try {
        await deleteFinalCallable.call<Map<String, dynamic>>({});
      } on FirebaseFunctionsException catch (e) {
        // [BUG-AUTH FIX] 응답 유실(deadline-exceeded/unavailable): 서버에서 Auth 계정 삭제가
        //   완료됐을 가능성 → 로컬 세션 강제 정리 (permission-denied 루프 / 유효 JWT 방치 방지)
        // 'internal'·'failed-precondition': CF 의도적 실패 → Auth 미삭제이므로 세션 유지
        if (e.code != 'internal' && e.code != 'failed-precondition') {
          await _auth.signOut().catchError((_) {});
        }
        rethrow;
      }

      // CF에서 Firebase Auth 계정 삭제 완료 → 로컬 세션 정리
      await _auth.signOut();

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

  // [DEPRECATED] callableCheckForeignIdExists — AES random IV로 equality 쿼리 broken.
  //   신규 코드에서는 precheckForeignIdentity() + finalizeForeignIdentity() 사용.
  //   레거시 호환용으로만 유지.
  Future<bool> checkForeignIdExists(String foreignIdNumber, UserRole role) async {
    try {
      final encrypted = EncryptionHelper.encrypt(foreignIdNumber);
      if (encrypted == null) return false;
      final result = await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableCheckForeignIdExists')
          .call({'foreignIdNumber': encrypted, 'role': _roleToString(role)});
      return (result.data as Map)['exists'] == true;
    } catch (e) {
      debugPrint('❌ [DEPRECATED] 외국인등록번호 중복 체크 실패: $e');
      return false; // 구버전 broken 쿼리 — false 반환 (finalize에서 atomic 재확인)
    }
  }

  // [FOREIGN-IDENTITY-01] 외국인등록번호 사전 중복 체크 — HMAC 기반 서버 쿼리 (UX용)
  // 평문 rawForeignId(13자리 숫자)를 CF로 전송 → 서버가 HMAC 계산 → foreignIdFingerprints 조회.
  // 실제 atomic 중복 차단은 finalizeForeignIdentity에서 수행.
  // Input: rawForeignId = 13자리 숫자 (하이픈 없음), role
  Future<bool> precheckForeignIdentity(String rawForeignId, UserRole role) async {
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callablePrecheckForeignIdentity',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 10)))
          .call({'rawForeignId': rawForeignId, 'role': _roleToString(role)});
      return (result.data as Map)['exists'] == true;
    } catch (e) {
      debugPrint('⚠️ 외국인 사전 체크 실패 (무시 — finalize에서 재확인): $e');
      return false; // pre-check 실패 시 비중복으로 처리
    }
  }

  // [FOREIGN-IDENTITY-03] 외국인 identity 확정 — HMAC fingerprint 생성 + atomic 중복 체크 + Firestore 기록
  // signUp() 직후 호출 필수.
  //
  // [B.2] 오류 정책 (확정):
  //
  //   TERMINAL — 이 외국인등록번호로는 가입 불가, 서버 cleanup 후 재가입 처음부터:
  //     already-exists: 다른 계정이 동일 ID를 선점 → callableAbortForeignRegistration 호출
  //
  //   RECOVERABLE — pending 유지, 사용자가 수정하거나 서버 정상화 후 재시도:
  //     invalid-argument  : 등록번호 형식 오류 → 사용자가 번호를 수정하고 재시도 가능
  //     failed-precondition: 나이 미달 → pending 유지 (재시도 의미 없지만 orphan 생성 방지)
  //     permission-denied : 블랙리스트/30일 제한 → pending 유지 (에러 메시지만 표시)
  //     unauthenticated   : 토큰 만료 → pending 유지 (앱 재시작 후 recovery 경로 사용)
  //     not-found         : Firestore doc 누락 (signUp 실패 race) → Auth-only 삭제 (fallback)
  //     internal, unavailable, deadline-exceeded, 네트워크: 서버/망 일시 장애 → pending 유지
  //
  // 반환: null = 성공, String = 오류 메시지
  Future<String?> finalizeForeignIdentity(
    String rawForeignId, {
    String? legalName,
    String? visaType,
  }) async {
    final payload = <String, dynamic>{'rawForeignId': rawForeignId};
    if (legalName != null && legalName.isNotEmpty) payload['legalName'] = legalName;
    if (visaType != null && visaType.isNotEmpty) payload['visaType'] = visaType;
    // [DEBUG] CF 호출 직전 상태 확인
    final currentUid = _auth.currentUser?.uid;
    final idLen = rawForeignId.length;
    final maskedId = idLen >= 8 ? '${rawForeignId.substring(0, 8)}*****' : '???';
    debugPrint('🔷 [finalize] CF 호출 시작 | uid=$currentUid | idLen=$idLen | maskedId=$maskedId | legalName=$legalName | visaType=$visaType');
    try {
      await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableFinalizeForeignIdentity',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 15)))
          .call(payload);
      debugPrint('✅ [finalize] CF 성공 | uid=$currentUid');
      return null; // 성공
    } on FirebaseFunctionsException catch (e) {
      // [DEBUG] CF 에러 전체 정보 출력 — code/message/details 모두
      debugPrint('❌ [finalize] CF 오류 | code=${e.code} | message=${e.message} | details=${e.details} | plugin=${e.plugin}');
      if (e.code == 'already-exists') {
        // TERMINAL: 다른 계정이 동일 외국인등록번호를 선점 — 이 pending 가입은 완료 불가.
        // → callableAbortForeignRegistration (서버 CF)으로 Firestore·Storage·Auth 전체 정리.
        // ※ Auth-only 삭제(B.1) 대신 server-authoritative cleanup으로 교체(B.2).
        await _abortForeignRegistrationViaServer('already-exists');
        return '이미 동일 역할로 가입된 외국인등록번호입니다.';
      }
      if (e.code == 'not-found') {
        // Firestore users/{uid} 문서 없음 — signUp()과 finalize() 사이의 race condition.
        // callableAbortForeignRegistration도 문서가 없으면 Auth만 정리하므로 직접 삭제.
        await _deleteAuthAccountOnlyFallback('not-found');
        return '계정 정보를 확인할 수 없습니다. 다시 시도해주세요.';
      }
      // ── RECOVERABLE — pending 상태 유지, 에러 메시지만 반환 ─────────
      // invalid-argument: 사용자가 등록번호를 다시 입력하고 재시도 가능
      // failed-precondition(나이미달)·permission-denied(블랙리스트/30일)·unauthenticated:
      //   Auth를 삭제하면 recovery 경로(RegistrationRecoveryScreen)도 막힘 → pending 보존.
      // internal·unavailable·deadline-exceeded·기타: 서버/망 장애 → pending 보존.
      debugPrint('⚠️ [finalize] RECOVERABLE — pending 유지 | code=${e.code}');
      return switch (e.code) {
        'invalid-argument'   => '입력 정보를 확인하고 다시 시도해주세요.',
        'failed-precondition'=> '만 19세 이상만 가입할 수 있습니다.',
        'permission-denied'  => '가입이 제한된 계정입니다. 고객센터에 문의해주세요.',
        'unauthenticated'    => '인증이 만료되었습니다. 앱을 재시작해주세요.',
        _                    => '정보를 확인하는 중 문제가 발생했습니다. 잠시 후 다시 시도해주세요.',
      };
    } catch (e) {
      // 네트워크 단절 등 — RECOVERABLE: Auth·Firestore 유지
      debugPrint('❌ [finalize] non-CF 예외 | type=${e.runtimeType} | error=$e');
      return '인터넷 연결을 확인하고 다시 시도해주세요.';
    }
  }

  // [B.2/B.2.2] TERMINAL 케이스용 서버 cleanup — callableAbortForeignRegistration 호출.
  //   완전 성공: Firestore + Storage + Auth 모두 서버에서 삭제.
  //   부분 완료(partial:true): CF가 sensitive resource(Storage)를 HARD GATE로 처리.
  //     STORAGE_RETRYABLE : Storage 삭제 실패 → user doc + Auth 보존 → 재시도 가능
  //     FIRESTORE_RETRYABLE: Firestore 삭제 실패 → Auth 보존 → 재시도 가능
  //     AUTH_RETRYABLE    : Firestore+Storage 정리됨, Auth user 살아있어 재시도 가능
  //   CF exception: CF 자체 도달 실패(unauthenticated/app-check/network) → Auth-only fallback
  Future<void> _abortForeignRegistrationViaServer(String reason) async {
    debugPrint('⚠️ [finalizeForeignIdentity] 서버 cleanup 시작 (reason: $reason)');
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableAbortForeignRegistration',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 15)))
          .call({});
      // [B.2.2] partial 응답 확인 — CF는 partial 실패 시 exception 대신 JSON 반환.
      // partial=true = Auth 살아있거나 retry context 보존 → 클라이언트 Auth 삭제 금지.
      final data = result.data as Map<dynamic, dynamic>?;
      final partial = data?['partial'] == true;
      final cfReason = data?['reason'] as String? ?? '';
      if (partial) {
        // silent success 금지: partial 상태를 반드시 로그
        debugPrint('⚠️ [finalizeForeignIdentity] 서버 cleanup 부분 완료 ($cfReason) — Auth/user 보존, 재시도 가능');
        // NOT IMPLEMENTED (B.2.2): 사용자 facing retry 안내 UI
      } else {
        debugPrint('✅ [finalizeForeignIdentity] 서버 cleanup 완료 (Firestore+Storage+Auth)');
      }
      // partial 여부와 무관하게 클라이언트에서 Auth 추가 삭제 금지.
      // CF가 이미 Auth를 정리했거나(success), Auth를 보존해 retry context를 유지함(partial).
    } on FirebaseFunctionsException catch (cfErr) {
      // CF 자체 도달 실패 (unauthenticated/app-check) → CF 로직이 실행되지 않은 상태.
      // 상태 불확실 → Auth-only 삭제 last-resort fallback.
      debugPrint('❌ [finalizeForeignIdentity] 서버 cleanup CF 실패 — Auth-only fallback (${cfErr.code})');
      await _deleteAuthAccountOnlyFallback('cf-abort-failed');
    } catch (e) {
      debugPrint('❌ [finalizeForeignIdentity] 서버 cleanup 네트워크 오류 — Auth-only fallback: $e');
      await _deleteAuthAccountOnlyFallback('cf-abort-network');
    }
  }

  // [B.2] Auth-only 삭제 — callableAbortForeignRegistration 실패 시 fallback 또는 not-found 케이스.
  // ※ RECOVERABLE 오류에서는 절대 호출하지 않는다.
  Future<void> _deleteAuthAccountOnlyFallback(String reason) async {
    debugPrint('⚠️ [finalizeForeignIdentity] Auth-only fallback 삭제 (reason: $reason)');
    try {
      await _auth.currentUser?.delete();
      debugPrint('✅ [finalizeForeignIdentity] Auth-only fallback 완료');
    } catch (authErr) {
      debugPrint('❌ [finalizeForeignIdentity] Auth 삭제 실패 (orphan 가능): $authErr');
    }
  }

  // [NATIVE-IDENTITY-03] 내국인 identity 확정 — passToken 소비 + atomic sentinel + ciHash/passVerifiedAt 기록
  // signUp() 직후 호출 필수. 실패 시 FAIL-CLOSE: 계정 롤백 후 오류 메시지 반환.
  // 반환: null = 성공, String = 오류 메시지(모든 실패 케이스 포함)
  Future<String?> finalizeNativeIdentity(String passToken) async {
    try {
      await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('finalizeRegistration',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 15)))
          .call({'passToken': passToken});
      return null;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'already-exists') {
        // 동일 ciHash+role 중복 → 계정 롤백 (Firestore 먼저, Auth 나중)
        await _rollbackNativeAccount('already-exists');
        return '이미 동일 역할로 가입된 계정이 있습니다.';
      }
      // FAIL-CLOSE: network 오류, transaction 실패 등 → 계정 롤백
      await _rollbackNativeAccount(e.code);
      return '가입 정보를 확인하는 중 문제가 발생했습니다. 잠시 후 다시 시도해주세요.';
    } catch (e) {
      // FAIL-CLOSE: 네트워크 단절 등 예외 → 계정 롤백
      await _rollbackNativeAccount('unknown');
      return '가입 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.';
    }
  }

  // [NATIVE-IDENTITY-03] 내국인 가입 롤백 — Firestore 먼저 삭제 후 Auth 삭제 (CLAUDE.md Firestore 삭제 순서)
  // partial cleanup 실패 시 orphan 계정이 남을 수 있으므로 debugPrint로 기록 (silent ignore 금지)
  Future<void> _rollbackNativeAccount(String reason) async {
    debugPrint('⚠️ [finalizeNativeIdentity] 롤백 시작 (reason: $reason)');
    try {
      final uid = _auth.currentUser?.uid;
      if (uid != null) {
        // Firestore 먼저 삭제 (CLAUDE.md: Firestore 삭제 순서)
        await _firestore.collection('users').doc(uid).delete();
        debugPrint('✅ [finalizeNativeIdentity] Firestore 문서 삭제 완료');
      }
    } catch (firestoreErr) {
      // Firestore 삭제 실패 → orphan Firestore 문서 가능 (Auth 삭제는 계속 시도)
      debugPrint('❌ [finalizeNativeIdentity] Firestore 롤백 실패 (orphan 문서 가능): $firestoreErr');
    }
    try {
      await _auth.currentUser?.delete();
      debugPrint('✅ [finalizeNativeIdentity] Auth 계정 삭제 완료');
    } catch (authErr) {
      // Auth 삭제 실패 → orphan Auth 계정 가능 (관리자 수동 정리 필요)
      debugPrint('❌ [finalizeNativeIdentity] Auth 롤백 실패 (orphan 계정 가능): $authErr');
    }
  }

  // [M-3] 아이디 찾기 (이름 + 전화번호) — callableFindUsername CF 경유 (PII 노출 차단)
  // [AUTH-FIX §4] 복수 계정 지원 — 동일 이름+전화번호에 복수 계정 존재 시 전체 반환.
  // 반환: [{username, role}] — 빈 리스트 = 찾을 수 없음, 오류 시 빈 리스트
  Future<List<Map<String, String>>> findUsername({
    required String name,
    required String phone,
  }) async {
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableFindUsername')
          .call({'name': name, 'phone': phone});
      final raw = (result.data as Map)['accounts'];
      if (raw == null) return [];
      final accounts = (raw as List).whereType<Map>().map((a) => {
        'username': (a['username'] as String?) ?? '',
        'role':     (a['role']     as String?) ?? '',
      }).where((a) => a['username']!.isNotEmpty).toList();
      return accounts;
    } catch (e) {
      debugPrint('❌ 아이디 찾기 실패: $e');
      ToastHelper.showError('아이디 찾기 중 오류가 발생했습니다.');
      return [];
    }
  }

  // [AUTH-FIX §2] 외국인 USER 비밀번호 찾기 1단계: username → OTP 발송
  // 반환: 마스킹된 전화번호 (e.g. "010-****-1234"), null = 실패
  Future<String?> sendOtpForPasswordReset(String username) async {
    final result = await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
        .httpsCallable(
          'callableSendOtpForPasswordReset',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
        )
        .call({'username': username.trim()});
    return (result.data as Map)['maskedPhone'] as String?;
  }

  // [AUTH-FIX §2] 외국인 USER 비밀번호 찾기 2단계: OTP 검증 → Custom Token 발급
  // 반환: customToken, null = 실패
  // 예외를 삼키지 않음 — 호출자에서 FirebaseFunctionsException catch 필수
  Future<String?> resetPasswordWithOtp({
    required String username,
    required String code,
  }) async {
    final result = await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
        .httpsCallable(
          'callableResetPasswordWithOtp',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
        )
        .call({'username': username.trim(), 'code': code.trim()});
    return (result.data as Map)['customToken'] as String?;
  }
}
