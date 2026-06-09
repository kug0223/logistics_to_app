import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/core/user_model.dart';
import '../models/core/business_member_model.dart';
import '../services/auth_service.dart';
import '../services/member_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'notification_provider.dart';
import '../services/fcm_service.dart';

class UserProvider with ChangeNotifier {
  final AuthService _authService = AuthService();

  UserModel? _currentUser;
  bool _isLoading = false;
  String? _error;

  // 하위 관리자 모드
  bool _isAdminMode = false;
  MemberPermissions? _memberPermissions;

  // NotificationProvider 연결용
  NotificationProvider? _notificationProvider;

  StreamSubscription? _authSubscription;
  bool _disposed = false;

  void setNotificationProvider(NotificationProvider provider) {
    _notificationProvider = provider;
  }

  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isLoggedIn => _currentUser != null;

  bool get isAdmin => _currentUser?.isAdmin ?? false;
  bool get isSuperAdmin => _currentUser?.isSuperAdmin ?? false;
  bool get isBusinessAdmin => _currentUser?.isBusinessAdmin ?? false;
  bool get isUser => _currentUser?.isUser ?? false;
  bool get isSubAdmin => _currentUser?.isSubAdmin ?? false;
  String? get businessId => _currentUser?.businessId;

  // 하위 관리자 모드 관련
  bool get isAdminMode => _isAdminMode;
  MemberPermissions? get memberPermissions => _memberPermissions;

  /// 관리자 모드 전환 (하위 관리자만 호출 가능)
  void toggleAdminMode() {
    if (!isSubAdmin) return;
    _isAdminMode = !_isAdminMode;
    notifyListeners();
  }

  /// 현재 유저의 유효한 businessId (BUSINESS_ADMIN은 자체, SUB_ADMIN은 subAdminOf)
  String? get effectiveBusinessId {
    final user = _currentUser;
    if (user == null) return null;
    if (user.isBusinessAdmin) return user.businessId;
    if (user.isSubAdmin) return user.subAdminOf;
    return null;
  }

  /// 특정 권한 체크 — BUSINESS_ADMIN은 항상 true, SUB_ADMIN은 permissions 확인
  bool can(bool Function(MemberPermissions p) check) {
    if (_currentUser?.isBusinessAdmin == true) return true;
    if (_memberPermissions != null) return check(_memberPermissions!);
    return false;
  }

  @override
  void dispose() {
    _disposed = true;
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  // 초기화 - Firebase Auth 상태 리스닝
  void initialize() {
    _authSubscription = _authService.authStateChanges.listen((User? firebaseUser) async {
      if (_disposed) return;
      if (firebaseUser != null) {
        await _loadUserData(firebaseUser.uid);
      } else {
        _currentUser = null;
        notifyListeners();
      }
    }, onError: (error) {
      if (_disposed) return;
      debugPrint('❌ Auth 상태 변경 에러: $error');
      if (error.toString().contains('invalid-user-token') ||
          error.toString().contains('user-token-expired')) {
        debugPrint('🔄 토큰 만료 - 자동 로그아웃');
        signOut();
      }
    });
  }

  // 사용자 데이터 로드
  Future<void> _loadUserData(String uid) async {
    try {
      _currentUser = await _authService.getUserData(uid);

      if (_currentUser != null) {
        // 알림 Provider 초기화
        _notificationProvider?.setUser(_currentUser!.uid);

        // FCM 푸시 알림 초기화
        await FCMService().initialize(_currentUser!.uid);

        // 하위 관리자이면 권한 로드
        if (_currentUser!.isSubAdmin && _currentUser!.subAdminOf != null) {
          _memberPermissions = await MemberService().getMemberPermissions(
            _currentUser!.subAdminOf!,
            uid,
          );
        } else {
          _memberPermissions = null;
          _isAdminMode = false;
        }
      }

      notifyListeners();
    } catch (e) {
      debugPrint('❌ 사용자 데이터 로드 실패: $e');
      _error = e.toString();
      
      if (e.toString().contains('invalid-user-token') || 
          e.toString().contains('user-token-expired') ||
          e.toString().contains('user-not-found')) {
        debugPrint('🔄 유효하지 않은 토큰 - 자동 로그아웃');
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

  // 회원가입
  Future<bool> signUp({
    required String username,
    required String userEmail,
    required String password,
    required String name,
    String? phone,
    required UserRole role,
    String? businessId,
    // 주민번호 기반 필드
    String? gender,
    DateTime? birthDate,
    String? residentNumber,
    // 주소 필드
    String? address,
    String? detailAddress,
    // 서류 업로드 필드
    String? idCardImageUrl,
    String? bankbookImageUrl,
    String? businessLicenseImageUrl,
    // 사업자 정보
    String? businessNumber,
    String? businessName,
    String? ceoName,
    String? bankName,
    String? accountNumber,
  }) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final user = await _authService.signUp(
        username: username, 
        userEmail: userEmail,
        password: password,
        name: name,
        phone: phone,
        role: role,
        businessId: businessId,
        gender: gender,
        birthDate: birthDate,
        residentNumber: residentNumber,
        address: address,
        detailAddress: detailAddress,
        idCardImageUrl: idCardImageUrl,
        bankbookImageUrl: bankbookImageUrl,
        businessLicenseImageUrl: businessLicenseImageUrl,
        businessNumber: businessNumber,
        businessName: businessName,
        ceoName: ceoName,
        bankName: bankName,
        accountNumber: accountNumber,
      );

      if (user != null) {
        await _loadUserData(user.uid);
        return true;
      }
      return false;
    } catch (e) {
      _error = e.toString();
      debugPrint('❌ 회원가입 실패: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 로그인
  Future<bool> signIn(String username, String password) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final user = await _authService.signIn(username, password);
      if (user != null) {
        // _loadUserData로 FCM·NotificationProvider·권한 초기화까지 한번에 처리
        await _loadUserData(user.uid);
        debugPrint('✅ 로그인 성공: ${user.email}');
        return true;
      }
      
      _error = '로그인에 실패했습니다';
      return false;
    } catch (e) {
      _error = e.toString();
      debugPrint('❌ 로그인 실패: $e');
      
      // 사용자 친화적인 에러 메시지
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

  // 로그아웃
  Future<void> signOut() async {
    try {
      // 알림 Provider 정리
      _notificationProvider?.clearUser();
      
      // FCM 토큰 삭제
      await FCMService().clearToken();
      
      await _authService.signOut();
      _currentUser = null;
      _memberPermissions = null;
      _isAdminMode = false;
      _error = null;
      debugPrint('✅ 로그아웃 성공');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ 로그아웃 실패: $e');
      // 로그아웃 실패해도 로컬 상태는 초기화
      _notificationProvider?.clearUser();
      _currentUser = null;
      _memberPermissions = null;
      _isAdminMode = false;
      _error = null;
      notifyListeners();
    }
  }

  // 에러 초기화
  void clearError() {
    _error = null;
    notifyListeners();
  }
  
  Future<void> refreshCurrentUser() async {
    if (_currentUser != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUser!.uid)
            .get();
        
        final data = doc.data();
        if (doc.exists && data != null) {
          _currentUser = UserModel.fromMap(data, doc.id);
          notifyListeners();
        }
      } catch (e) {
        debugPrint('❌ 사용자 정보 새로고침 실패: $e');
      }
    }
  }
}