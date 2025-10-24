import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../utils/toast_helper.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 현재 사용자 스트림
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // 현재 사용자
  User? get currentUser => _auth.currentUser;

  // 로그인
  Future<UserModel?> signIn(String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (result.user != null) {
        // Firestore에서 사용자 정보 가져오기
        DocumentSnapshot doc = await _firestore
            .collection('users')
            .doc(result.user!.uid)
            .get();

        if (doc.exists) {
          // 마지막 로그인 시간 업데이트
          await _firestore.collection('users').doc(result.user!.uid).update({
            'lastLoginAt': FieldValue.serverTimestamp(),
          });

          return UserModel.fromMap(
            doc.data() as Map<String, dynamic>,
            result.user!.uid,
          );
        }
      }
      return null;
    } on FirebaseAuthException catch (e) {
      String message = '로그인에 실패했습니다.';
      switch (e.code) {
        case 'user-not-found':
        case 'wrong-password':
          message = '이메일 또는 비밀번호가 일치하지 않습니다.';
          break;
        case 'invalid-email':
          message = '유효하지 않은 이메일 형식입니다.';
          break;
        case 'user-disabled':
          message = '비활성화된 계정입니다.';
          break;
        case 'too-many-requests':
          message = '너무 많은 로그인 시도가 있었습니다.\n잠시 후 다시 시도해주세요.';
          break;
      }
      ToastHelper.showError(message);
      throw Exception(message);
    } catch (e) {
      ToastHelper.showError('로그인 중 오류가 발생했습니다.');
      throw Exception('로그인 실패: $e');
    }
  }

  // 회원가입
  Future<UserModel?> signUp({
    required String email,
    required String password,
    required String name,
    String? phone,
    UserRole role = UserRole.USER, // ✅ 기본값은 일반 사용자
    String? businessId, // ✅ 사업장 관리자의 경우 사업장 ID
  }) async {
    try {
      // Firebase Auth 계정 생성
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (result.user != null) {
        // Firestore에 사용자 정보 저장
        UserModel newUser = UserModel(
          uid: result.user!.uid,
          name: name,
          email: email,
          phone: phone,
          role: role, // ✅ 변경
          businessId: businessId, // ✅ 추가
          createdAt: DateTime.now(),
          lastLoginAt: DateTime.now(),
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
          message = '이미 사용 중인 이메일입니다.';
          break;
        case 'invalid-email':
          message = '유효하지 않은 이메일 형식입니다.';
          break;
        case 'weak-password':
          message = '비밀번호가 너무 약합니다.\n6자 이상 입력해주세요.';
          break;
      }
      ToastHelper.showError(message);
      throw Exception(message);
    } catch (e) {
      ToastHelper.showError('회원가입 중 오류가 발생했습니다.');
      throw Exception('회원가입 실패: $e');
    }
  }

  // ✅ NEW! 사업장 관리자 회원가입 (슈퍼관리자만 호출 가능)
  Future<UserModel?> signUpBusinessAdmin({
    required String email,
    required String password,
    required String name,
    required String businessId,
  }) async {
    return signUp(
      email: email,
      password: password,
      name: name,
      role: UserRole.BUSINESS_ADMIN,
      businessId: businessId,
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

  // ✅ NEW! 사용자 권한 업데이트 (슈퍼관리자만 호출 가능)
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
}