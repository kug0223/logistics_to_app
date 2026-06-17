import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/core/user_model.dart';
import '../utils/toast_helper.dart';
import 'fcm_service.dart';

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
      // 1. username으로 사용자 찾기
      final userSnapshot = await _firestore
          .collection('users')
          .where('username', isEqualTo: username)
          .limit(1)
          .get();
      
      if (userSnapshot.docs.isEmpty) {
        // throw만 — 호출부 catch에서 toast 처리
        throw Exception('존재하지 않는 아이디입니다.');
      }
      
      final userDoc = userSnapshot.docs.first;
      final userData = userDoc.data();
      final email = userData['email'] as String?;
      
      if (email == null || email.isEmpty) {
        ToastHelper.showError('계정 정보에 이메일이 없습니다.');
        throw Exception('이메일 정보 없음');
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
            ToastHelper.showError('이용 제한된 계정입니다.\n사유: $reason\n고객센터에 문의해주세요.');
            throw Exception('블랙리스트 사용자');
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
              ToastHelper.showError(message);
              throw Exception('이용 제한 사용자');
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
          ToastHelper.showError('사용자 정보를 찾을 수 없습니다.');
          throw Exception('Firestore에 사용자 정보 없음');
        }
      }
      return null;
      
    } on FirebaseAuthException catch (e) {
      String message = '로그인에 실패했습니다.';
      switch (e.code) {
        case 'user-not-found':
          message = '존재하지 않는 아이디입니다.';
          break;
        case 'wrong-password':
          message = '비밀번호가 일치하지 않습니다.';
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
          message = '아이디 또는 비밀번호가 일치하지 않습니다.';
          break;
        case 'network-request-failed':
          message = '네트워크 연결을 확인해주세요.';
          break;
      }
      ToastHelper.showError(message);
      throw Exception(message);
      
    } on FirebaseException catch (e) {
      // Firestore 예외 (FirebaseAuthException이 아닌 것) — 네트워크·권한·토큰 만료 등
      debugPrint('❌ [signIn] FirebaseException: ${e.code} / ${e.message}');
      String message;
      if (e.code == 'permission-denied' || e.code == 'unauthenticated') {
        message = '인증이 만료되었습니다. 다시 시도해주세요';
      } else if (e.code == 'unavailable' || e.code == 'network-request-failed') {
        message = '네트워크 연결을 확인해주세요';
      } else {
        message = '로그인 중 오류가 발생했습니다';
      }
      ToastHelper.showError(message);
      throw Exception(message);

    } catch (e) {
      // 그 외 예외 (Firestore 조회 실패, fromMap 파싱 오류 등)
      debugPrint('❌ [signIn] 알 수 없는 오류: $e');
      if (e.toString().contains('사용자를 찾을 수 없습니다')) {
        rethrow;
      }
      ToastHelper.showError('로그인 중 오류가 발생했습니다');
      throw Exception('로그인 실패: $e');
    }
  }

  // ⭐ 개선된 회원가입 - 주민번호 기반 + 서류 업로드 + 통장정보
  Future<UserModel?> signUp({
    required String username,
    required String password,
    required String name,
    required String userEmail,      // ⭐ 실제 이메일
    String? phone,
    UserRole role = UserRole.USER,
    String? businessId,
    // ⭐ 주민번호 기반 필드
    String? gender,
    DateTime? birthDate,
    String? residentNumber,
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
          userEmail: userEmail,       // ⭐ 실제 이메일
          phone: phone,
          role: role,
          businessId: businessId,
          createdAt: DateTime.now(),
          lastLoginAt: DateTime.now(),
          // ⭐ 주민번호 기반 정보
          gender: gender,
          birthDate: birthDate,
          residentNumber: residentNumber,
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
              .set(newUser.toMap());
        } catch (firestoreError) {
          // Firestore 저장 실패 시 Auth 계정 롤백 (고아 계정 방지)
          try {
            await result.user!.delete();
          } catch (deleteError) {
            debugPrint('⚠️ Auth 롤백 실패: $deleteError');
          }
          ToastHelper.showError('회원가입 중 오류가 발생했습니다.\n다시 시도해주세요.');
          throw Exception('Firestore 저장 실패: $firestoreError');
        }

        ToastHelper.showSuccess('회원가입이 완료되었습니다!');
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
      ToastHelper.showError(message);
      throw Exception(message);
    } catch (e) {
      ToastHelper.showError('회원가입 중 오류가 발생했습니다.');
      throw Exception('회원가입 실패: $e');
    }
  }

  // 사업장 관리자 회원가입 (슈퍼관리자만 호출 가능)
  Future<UserModel?> signUpBusinessAdmin({
    required String username,
    required String userEmail,      // ⭐ 파라미터 이름 변경
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
      userEmail: userEmail,         // ⭐ 변경
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
      await _auth.signOut();
      ToastHelper.showInfo('로그아웃되었습니다.');
    } catch (e) {
      ToastHelper.showError('로그아웃 중 오류가 발생했습니다.');
      throw Exception('로그아웃 실패: $e');
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

  // 사용자 권한 업데이트 (슈퍼관리자만 호출 가능)
  Future<void> updateUserRole({
    required String uid,
    required UserRole role,
    String? businessId,
  }) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'role': role == UserRole.SUPER_ADMIN
            ? 'SUPER_ADMIN'
            : role == UserRole.BUSINESS_ADMIN
                ? 'BUSINESS_ADMIN'
                : 'USER',
        'businessId': businessId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      ToastHelper.showSuccess('사용자 권한이 업데이트되었습니다.');
    } catch (e) {
      ToastHelper.showError('권한 업데이트에 실패했습니다.');
      throw Exception('권한 업데이트 실패: $e');
    }
  }

  // ⭐ NEW: 비밀번호 재설정 이메일 발송
  /// @deprecated 시스템 이메일 체계([username]@ALfit-system.com)와 호환되지 않음.
  /// [특이사항] 비밀번호 찾기는 Cloud Functions sendPasswordResetCode 방식으로 처리됨
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
      ToastHelper.showError(message);
      throw Exception(message);
    } catch (e) {
      ToastHelper.showError('이메일 발송 중 오류가 발생했습니다.');
      throw Exception('이메일 발송 실패: $e');
    }
  }

  // ⭐ NEW: 계정 삭제
  /// 비밀번호 재인증 후 계정 삭제
  /// returns null on success, error message string on failure
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

      // [BUG-수정] A-H-1: 탈퇴 기록을 전화번호 해시로 저장 (재가입 30일 제한용)
      // 기존 주민번호는 마스킹 저장되어 복호화 불가 → 해시 생성 불가 → 재가입 제한 비작동
      // 전화번호(phone 필드)는 평문 저장되어 있어 해시 생성 가능
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        final data = userDoc.data()!;
        final phone = data['phone'] as String?;
        if (phone != null && phone.isNotEmpty) {
          // 전화번호 해시 생성 (원본 저장 안 함)
          final phoneHash = sha256.convert(utf8.encode(phone)).toString();

          final isBlacklisted = data['isBlacklisted'] == true;
          await _firestore.collection('deleted_accounts').add({
            'phoneHash': phoneHash,
            'deletedAt': FieldValue.serverTimestamp(),
            // 블랙리스트면 슈퍼관리자가 직접 해제 전까지 차단
            'canReregisterAt': isBlacklisted
                ? null
                : Timestamp.fromDate(
                    DateTime.now().add(const Duration(days: 30))),
            'isBlacklisted': isBlacklisted,
            'noShowCount': data['noShowCount'] ?? 0,
            'role': data['role'] ?? 'USER',
          });
        }
      }

      // 3. Firestore 사용자 문서 삭제 (Storage URL 참조 제거 먼저 — broken URL 방지)
      await _firestore.collection('users').doc(user.uid).delete();

      // 4. Storage 사용자 파일 삭제 (신분증, 통장 등)
      try {
        final storageRef = FirebaseStorage.instance.ref('users/${user.uid}');
        final listResult = await storageRef.listAll();
        for (final item in listResult.items) {
          await item.delete();
        }
        for (final prefix in listResult.prefixes) {
          final sub = await prefix.listAll();
          for (final item in sub.items) {
            await item.delete();
          }
        }
      } catch (storageErr) {
        debugPrint('⚠️ Storage 파일 삭제 실패 (계속 진행): $storageErr');
      }

      // 5. 연관 컬렉션 개인정보 정리 (개인정보보호법 — 탈퇴 시 삭제 의무)
      // notifications: 본인 알림 전체 삭제 (페이지네이션)
      try {
        bool hasMoreNotifs = true;
        while (hasMoreNotifs) {
          final snap = await _firestore
              .collection('notifications')
              .where('userId', isEqualTo: user.uid)
              .limit(200)
              .get();
          if (snap.docs.isEmpty) break;
          hasMoreNotifs = snap.docs.length == 200;
          final batch = _firestore.batch();
          for (final doc in snap.docs) { batch.delete(doc.reference); }
          await batch.commit();
        }
      } catch (e) {
        // [J-003] notifications 삭제 실패 — 계정 삭제는 계속 진행
        debugPrint('⚠️ 계정 삭제: notifications 삭제 실패 (계속 진행): $e');
      }

      // worker_locations: 실시간 위치 전체 삭제 (페이지네이션)
      try {
        bool hasMoreLocs = true;
        while (hasMoreLocs) {
          final snap = await _firestore
              .collection('worker_locations')
              .where('userId', isEqualTo: user.uid)
              .limit(100)
              .get();
          if (snap.docs.isEmpty) break;
          hasMoreLocs = snap.docs.length == 100;
          final batch = _firestore.batch();
          for (final doc in snap.docs) { batch.delete(doc.reference); }
          await batch.commit();
        }
      } catch (e) {
        debugPrint('⚠️ 계정 삭제: worker_locations 삭제 실패 (계속 진행): $e');
      }

      // applications: 활성 지원서 AUTO_CANCELED 처리 전체 (페이지네이션, 이력은 보존 — 급여 처리용)
      // CONFIRMED 포함: 탈퇴 시 orphan 방지 (BUG-ADMIN-72)
      try {
        bool hasMoreApps = true;
        while (hasMoreApps) {
          final snap = await _firestore
              .collection('applications')
              .where('uid', isEqualTo: user.uid)
              .where('status', whereIn: ['PENDING', 'CONTRACT_PENDING', 'CONFIRMED'])
              .limit(100)
              .get();
          if (snap.docs.isEmpty) break;
          hasMoreApps = snap.docs.length == 100;
          final batch = _firestore.batch();
          final List<String> confirmedAppIds = [];
          for (final doc in snap.docs) {
            if (doc.data()['status'] == 'CONFIRMED') confirmedAppIds.add(doc.id);
            batch.update(doc.reference, {
              'status': 'CANCELED',
              'canceledAt': FieldValue.serverTimestamp(),
              'cancelReason': 'USER_DELETED',
            });
          }
          await batch.commit();
          // CONFIRMED 지원서의 scheduled 출근기록 → absent 처리
          for (final appId in confirmedAppIds) {
            try {
              final attSnap = await _firestore
                  .collection('attendance')
                  .where('applicationId', isEqualTo: appId)
                  .where('status', isEqualTo: 'scheduled')
                  .get();
              if (attSnap.docs.isEmpty) continue;
              final attBatch = _firestore.batch();
              for (final attDoc in attSnap.docs) {
                attBatch.update(attDoc.reference, {
                  'status': 'absent',
                  'absentReason': 'USER_DELETED',
                  'updatedAt': FieldValue.serverTimestamp(),
                });
              }
              await attBatch.commit();
            } catch (_) {}
          }
        }
      } catch (_) {}

      // 6. Firebase Auth 계정 삭제
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

  // ⭐ NEW: 이메일 인증 발송 (이메일 인증 기능용)
  Future<void> sendEmailVerification() async {
    try {
      final user = _auth.currentUser;
      if (user != null && !user.emailVerified) {
        await user.sendEmailVerification();
        ToastHelper.showSuccess('인증 이메일이 발송되었습니다.');
      }
    } catch (e) {
      ToastHelper.showError('이메일 발송에 실패했습니다.');
      throw Exception('이메일 인증 발송 실패: $e');
    }
  }

  // ⭐ NEW: 이메일 인증 상태 확인
  Future<bool> isEmailVerified() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await user.reload(); // 최신 상태로 새로고침
        return user.emailVerified;
      }
      return false;
    } catch (e) {
      debugPrint('이메일 인증 상태 확인 실패: $e');
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
      // 동일 역할 + 동일 전화번호 체크
      final snapshot = await _firestore
          .collection('users')
          .where('phone', isEqualTo: phone)
          .where('role', isEqualTo: _roleToString(role))
          .limit(1)
          .get();
      return snapshot.docs.isNotEmpty;
    } catch (e) {
      debugPrint('❌ 중복 가입 체크 실패: $e');
      return null;
    }
  }

  /// 사업자등록번호 중복 가입 체크 — 동일 번호로 BUSINESS_ADMIN 이미 존재하면 true
  Future<bool?> checkBusinessNumberDuplicate(String businessNumber) async {
    try {
      final clean = businessNumber.replaceAll('-', '');
      final snapshot = await _firestore
          .collection('users')
          .where('businessNumber', isEqualTo: clean)
          .where('role', isEqualTo: 'BUSINESS_ADMIN')
          .limit(1)
          .get();
      return snapshot.docs.isNotEmpty;
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

  // 아이디 중복 체크
  Future<bool> checkUsernameExists(String username) async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .where('username', isEqualTo: username)
          .limit(1)
          .get();
      
      return snapshot.docs.isNotEmpty;
    } catch (e) {
      debugPrint('❌ 아이디 중복 체크 실패: $e');
      return true; // 에러 시 중복으로 간주
    }
  }
  // 🔍 아이디 찾기 (이름 + 전화번호)
  Future<String?> findUsername({
    required String name,
    required String phone,
  }) async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .where('name', isEqualTo: name)
          .where('phone', isEqualTo: phone)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        ToastHelper.showError('일치하는 사용자를 찾을 수 없습니다.');
        return null;
      }

      final userData = snapshot.docs.first.data();
      return userData['username'] as String?;
    } catch (e) {
      debugPrint('❌ 아이디 찾기 실패: $e');
      ToastHelper.showError('아이디 찾기 중 오류가 발생했습니다.');
      return null;
    }
  }
}
