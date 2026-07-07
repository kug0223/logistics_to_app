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
import '../services/firestore_service.dart';

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
    // 앱 재시작 시 Firebase Auth가 토큰을 복원하는 동안 isLoading=true 유지.
    // 이렇게 해야 AuthWrapper가 "isLoggedIn=false" 를 먼저 보여주는 flash를 방지할 수 있다.
    _isLoading = true;
    _authSubscription = _authService.authStateChanges.listen((User? firebaseUser) async {
      if (_disposed) return;
      if (firebaseUser != null) {
        await _loadUserData(firebaseUser.uid);
      } else {
        _currentUser = null;
        _isLoading = false;
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
    // signIn/signUp 경로는 호출 전에 이미 _isLoading=true를 설정하지만,
    // initialize() 의 Auth 스트림 경로는 여기서 설정한다.
    if (!_isLoading) {
      _isLoading = true;
      notifyListeners();
    }
    try {
      _currentUser = await _authService.getUserData(uid);
      if (_disposed) return; // dispose 후 결과를 반영하지 않음

      if (_currentUser != null) {
        // 스냅샷: await 이후 signOut() 경쟁조건으로 _currentUser가 null이 될 수 있음
        final user = _currentUser!;

        // 알림 Provider 초기화
        _notificationProvider?.setUser(user.uid);

        // FCM 푸시 알림 초기화
        await FCMService().initialize(user.uid, isAdmin: user.isAdmin);
        if (_disposed) return;

        // 하위 관리자이면 권한 로드
        if (user.isSubAdmin && user.subAdminOf != null) {
          _memberPermissions = await MemberService().getMemberPermissions(
            user.subAdminOf!,
            uid,
          );
          if (_disposed) return;
        } else {
          _memberPermissions = null;
          _isAdminMode = false;
        }
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      if (_disposed) return;
      debugPrint('❌ 사용자 데이터 로드 실패: $e');
      _error = e.toString();
      _isLoading = false;

      if (e.toString().contains('invalid-user-token') ||
          e.toString().contains('user-token-expired') ||
          e.toString().contains('user-not-found')) {
        debugPrint('🔄 유효하지 않은 토큰 - 자동 로그아웃');
        await signOut();
        return; // signOut()이 이미 notifyListeners() 처리함
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
    required String password,
    required String name,
    String? phone,
    required UserRole role,
    String? businessId,
    // 주민번호 기반 필드
    String? gender,
    DateTime? birthDate,
    String? residentNumber,
    // PASS 인증 필드
    String? ci,
    String? foreignIdNumber,
    String accountStatus = 'active',
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
        password: password,
        name: name,
        phone: phone,
        role: role,
        businessId: businessId,
        gender: gender,
        birthDate: birthDate,
        residentNumber: residentNumber,
        ci: ci,
        foreignIdNumber: foreignIdNumber,
        accountStatus: accountStatus,
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
      // [BUG-수정] SP-M-1: _loadUserData() 성공 시 내부에서 이미 _isLoading=false + notifyListeners() 처리됨.
      // finally가 무조건 재호출하면 불필요한 이중 rebuild 발생 — _isLoading이 아직 true일 때만 정리.
      if (_isLoading) {
        _isLoading = false;
        notifyListeners();
      }
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
        if (kDebugMode) debugPrint('✅ 로그인 성공: ${user.email}');
        return true;
      }
      
      _error = '로그인에 실패했습니다';
      return false;
    } catch (e) {
      _error = e.toString();
      debugPrint('❌ 로그인 실패: $e');
      
      // 사용자 친화적인 에러 메시지
      final errStr = e.toString();
      if (errStr.contains('invalid-credential') ||
          errStr.contains('user-not-found') ||
          errStr.contains('wrong-password') ||
          errStr.contains('아이디 또는 비밀번호')) {
        _error = '아이디 또는 비밀번호가 올바르지 않습니다';
      } else if (errStr.contains('invalid-email')) {
        _error = '유효하지 않은 이메일 형식입니다';
      } else if (errStr.contains('network-request-failed') ||
          errStr.contains('NETWORK_ERROR')) {
        _error = '네트워크 연결을 확인해주세요';
      } else if (errStr.contains('too-many-requests')) {
        _error = '로그인 시도가 너무 많습니다. 잠시 후 다시 시도해주세요';
      } else if (errStr.contains('user-disabled')) {
        _error = '비활성화된 계정입니다. 관리자에게 문의해주세요';
      }
      
      return false;
    } finally {
      // [BUG-수정] SP-M-1: _loadUserData() 성공 시 내부에서 이미 _isLoading=false + notifyListeners() 처리됨.
      // finally가 무조건 재호출하면 불필요한 이중 rebuild 발생 — _isLoading이 아직 true일 때만 정리.
      if (_isLoading) {
        _isLoading = false;
        notifyListeners();
      }
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
      _isLoading = false;

      // [특이사항] 로그아웃 시 FirestoreService 메모리 캐시 정리.
      // Firestore 오프라인 영속성 캐시(clearPersistence)는 활성 리스너와 충돌 위험이 있어
      // 호출 시점이 제한적이다 — 메모리 캐시(_userCache 등)만 정리한다.
      // 같은 기기에서 다른 계정으로 로그인 시 이전 사용자의 캐시된 사용자 정보 노출 방지.
      FirestoreService().clearCache();

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
      FirestoreService().clearCache();
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
        if (_disposed) return;
        if (doc.exists && data != null) {
          _currentUser = UserModel.fromMap(data, doc.id);
          notifyListeners();
        }
      } catch (e) {
        debugPrint('❌ 사용자 정보 새로고침 실패: $e');
      }
    }
  }

  // TO 즐겨찾기
  bool isFavoriteTo(String toId) =>
      _currentUser?.favoriteToIds.contains(toId) ?? false;

  Future<void> toggleFavoriteTo(String toId) async {
    final user = _currentUser;
    if (user == null) return;

    final wasFav = user.favoriteToIds.contains(toId);
    final updated = wasFav
        ? (List<String>.from(user.favoriteToIds)..remove(toId))
        : [...user.favoriteToIds, toId];

    _currentUser = user.copyWith(favoriteToIds: updated);
    notifyListeners();

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'favoriteToIds': wasFav
            ? FieldValue.arrayRemove([toId])
            : FieldValue.arrayUnion([toId]),
      });
    } catch (e) {
      _currentUser = user;
      notifyListeners();
      debugPrint('❌ TO 즐겨찾기 토글 실패: $e');
    }
  }
}