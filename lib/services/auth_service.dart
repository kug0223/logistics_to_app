import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/core/user_model.dart';
import '../utils/toast_helper.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 현재 사용자 스트림
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // 현재 사용자
  User? get currentUser => _auth.currentUser;

  // 로그인 (아이디 기반)
  Future<UserModel?> signIn(String username, String password) async {
    try {
      // 1. username으로 사용자 찾기
      final userSnapshot = await _firestore
          .collection('users')
          .where('username', isEqualTo: username)
          .limit(1)
          .get();
      
      if (userSnapshot.docs.isEmpty) {
        ToastHelper.showError('존재하지 않는 아이디입니다.');
        throw Exception('사용자를 찾을 수 없습니다');
      }
      
      final userDoc = userSnapshot.docs.first;
      final userData = userDoc.data();
      final email = userData['email'];
      
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
          // 4. 마지막 로그인 시간 업데이트
          await _firestore.collection('users').doc(result.user!.uid).update({
            'lastLoginAt': FieldValue.serverTimestamp(),
          });

          return UserModel.fromMap(
            doc.data() as Map<String, dynamic>,
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
      
    } catch (e) {
      // Firestore 조회 실패 등 다른 에러
      if (e.toString().contains('사용자를 찾을 수 없습니다')) {
        // 이미 처리됨
        rethrow;
      }
      ToastHelper.showError('로그인 중 오류가 발생했습니다.');
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
          // ✅ 통장 정보 추가
          bankName: bankName,
          accountNumber: accountNumber,
          accountHolder: name,  // 예금주는 본인 이름으로 자동 설정
        );

        await _firestore
            .collection('users')
            .doc(result.user!.uid)
            .set(newUser.toMap());

        ToastHelper.showSuccess('회원가입이 완료되었습니다!');
        return newUser;
      }
      return null;
    } on FirebaseAuthException catch (e) {
      String message = '회원가입에 실패했습니다.';
      switch (e.code) {
        case 'email-already-in-use':
          message = '이미 사용 중인 아이디입니다.';
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
      print('사용자 정보 가져오기 실패: $e');
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
  Future<void> deleteAccount() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        // Firestore 데이터 삭제
        await _firestore.collection('users').doc(user.uid).delete();
        
        // Firebase Auth 계정 삭제
        await user.delete();
        
        ToastHelper.showSuccess('계정이 삭제되었습니다.');
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        ToastHelper.showError('보안을 위해 다시 로그인이 필요합니다.');
      } else {
        ToastHelper.showError('계정 삭제에 실패했습니다.');
      }
      throw Exception('계정 삭제 실패: $e');
    } catch (e) {
      ToastHelper.showError('계정 삭제 중 오류가 발생했습니다.');
      throw Exception('계정 삭제 실패: $e');
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
      print('❌ 비밀번호 변경 실패: $e');
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
      print('이메일 인증 상태 확인 실패: $e');
      return false;
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
      print('❌ 아이디 중복 체크 실패: $e');
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
      print('❌ 아이디 찾기 실패: $e');
      ToastHelper.showError('아이디 찾기 중 오류가 발생했습니다.');
      return null;
    }
  }
}