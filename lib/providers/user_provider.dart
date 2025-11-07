import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/core/user_model.dart';
import '../services/auth_service.dart';

class UserProvider with ChangeNotifier {
  final AuthService _authService = AuthService();
  
  UserModel? _currentUser;
  bool _isLoading = false;
  String? _error;

  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isLoggedIn => _currentUser != null;
  
  bool get isAdmin => _currentUser?.isAdmin ?? false;
  bool get isSuperAdmin => _currentUser?.isSuperAdmin ?? false;
  bool get isBusinessAdmin => _currentUser?.isBusinessAdmin ?? false;
  bool get isUser => _currentUser?.isUser ?? false;
  String? get businessId => _currentUser?.businessId;

  // ✅ 초기화 - Firebase Auth 상태 리스닝 (에러 처리 개선)
  void initialize() {
    _authService.authStateChanges.listen((User? firebaseUser) async {
      if (firebaseUser != null) {
        await _loadUserData(firebaseUser.uid);
      } else {
        _currentUser = null;
        notifyListeners();
      }
    }, onError: (error) {
      // ✅ Auth 상태 변경 중 에러 처리
      print('❌ Auth 상태 변경 에러: $error');
      if (error.toString().contains('invalid-user-token') || 
          error.toString().contains('user-token-expired')) {
        print('🔄 토큰 만료 - 자동 로그아웃');
        signOut();
      }
    });
  }

  // ✅ 사용자 데이터 로드 (에러 처리 개선)
  Future<void> _loadUserData(String uid) async {
    try {
      _currentUser = await _authService.getUserData(uid);
      
      // 테스트용 로그
      if (_currentUser != null) {
        print('📋 ===== 사용자 권한 정보 =====');
        print('📧 이메일: ${_currentUser!.email}');
        print('👤 이름: ${_currentUser!.name}');
        print('🎭 역할: ${_currentUser!.role}');
        print('🏢 사업장 ID: ${_currentUser!.businessId ?? "없음"}');
        print('');
        print('📊 권한 체크:');
        print('  - isSuperAdmin: ${_currentUser!.isSuperAdmin}');
        print('  - isBusinessAdmin: ${_currentUser!.isBusinessAdmin}');
        print('  - isUser: ${_currentUser!.isUser}');
        print('  - isAdmin: ${_currentUser!.isAdmin}');
        print('============================');
      }
      
      notifyListeners();
    } catch (e) {
      print('❌ 사용자 데이터 로드 실패: $e');
      _error = e.toString();
      
      // ✅ 특정 에러 코드 처리
      if (e.toString().contains('invalid-user-token') || 
          e.toString().contains('user-token-expired') ||
          e.toString().contains('user-not-found')) {
        print('🔄 유효하지 않은 토큰 - 자동 로그아웃');
        await signOut();
      }
      
      notifyListeners();
    }
  }

  // 사용자 데이터 새로고침
  Future<void> refreshUserData() async {
    final user = _authService.currentUser;
    if (user != null) {
      await _loadUserData(user.uid);
    }
  }

  // ✅ 회원가입 (role 파라미터 추가)
  Future<bool> signUp({
    required String email,
    required String password,
    required String name,
    String? phone,
    required UserRole role, // ✅ 역할 파라미터
  }) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final user = await _authService.signUp(
        email: email,
        password: password,
        name: name,
        phone: phone,
        role: role, // ✅ 역할 전달
      );

      if (user != null) {
        _currentUser = user;
        return true;
      }
      return false;
    } catch (e) {
      _error = e.toString();
      print('❌ 회원가입 실패: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ✅ 로그인 (에러 처리 개선)
  Future<bool> signIn(String email, String password) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final user = await _authService.signIn(email, password);
      
      if (user != null) {
        _currentUser = user;
        print('✅ 로그인 성공: ${user.email}');
        return true;
      }
      
      _error = '로그인에 실패했습니다';
      return false;
    } catch (e) {
      _error = e.toString();
      print('❌ 로그인 실패: $e');
      
      // ✅ 사용자 친화적인 에러 메시지
      if (e.toString().contains('user-not-found')) {
        _error = '등록되지 않은 이메일입니다';
      } else if (e.toString().contains('wrong-password')) {
        _error = '비밀번호가 올바르지 않습니다';
      } else if (e.toString().contains('invalid-email')) {
        _error = '유효하지 않은 이메일 형식입니다';
      } else if (e.toString().contains('network-request-failed')) {
        _error = '네트워크 연결을 확인해주세요';
      }
      
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ✅ 로그아웃 (에러 처리 개선)
  Future<void> signOut() async {
    try {
      await _authService.signOut();
      _currentUser = null;
      _error = null;
      print('✅ 로그아웃 성공');
      notifyListeners();
    } catch (e) {
      print('❌ 로그아웃 실패: $e');
      // 로그아웃 실패해도 로컬 상태는 초기화
      _currentUser = null;
      _error = null;
      notifyListeners();
    }
  }

  // 에러 초기화
  void clearError() {
    _error = null;
    notifyListeners();
  }
}