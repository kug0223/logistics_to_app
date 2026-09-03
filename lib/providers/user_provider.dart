import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/core/user_model.dart';
import '../models/core/user_region.dart';
import '../models/core/business_member_model.dart';
import '../models/core/employment_contract_model.dart';
import '../services/auth_service.dart';
import '../services/member_service.dart';
import '../services/contract_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'notification_provider.dart';
import '../services/fcm_service.dart';
import '../services/firestore_service.dart';
import '../utils/navigation_key.dart';

class UserProvider with ChangeNotifier {
  final AuthService _authService = AuthService();

  UserModel? _currentUser;
  bool _isLoading = false;
  // signIn/signUp 진행 중임을 표시 — auth 스트림의 null 이벤트가 _isLoading을 리셋하지 않도록 방어
  bool _isSigningIn = false;
  String? _error;
  // [C안 F-01-3] 외국인 가입 미완료(termsConsentAt 없는 pending 계정) 감지 플래그
  //   signIn() 실패 시 IncompleteRegistrationException을 잡으면 true로 설정.
  //   로그인 화면이 이 플래그를 보고 RegistrationRecoveryScreen으로 라우팅한다.
  bool _hasIncompleteRegistration = false;
  bool get hasIncompleteRegistration => _hasIncompleteRegistration;

  // 하위 관리자 모드
  bool _isAdminMode = false;
  MemberPermissions? _memberPermissions;
  // permissions 로드 완료 여부 (false = 아직 미로드/실패, true = 로드 완료)
  bool _permissionsLoaded = false;
  // 다중 사업장 하위관리자: 현재 선택된 사업장 (세션 내 유지)
  String? _selectedSubAdminBusinessId;
  Map<String, String> _subAdminBusinessNames = {};
  Map<String, String> _subAdminBusinessNamesView = const {};
  // SA-01: switchToAdminMode 경쟁조건 방지용 세대 카운터
  int _switchGeneration = 0;

  // NotificationProvider 연결용
  NotificationProvider? _notificationProvider;

  StreamSubscription? _authSubscription;
  StreamSubscription? _memberPermsSub; // members/{uid} 실시간 권한 감지
  bool _disposed = false;
  // [NEW-03] Ghost session 방지용 세대 카운터
  // signOut() 또는 새 _loadUserData 호출 시 증가 → in-flight load가 stale 여부를 확인
  int _loadGeneration = 0;

  // 미서명 계약서 목록 (USER 역할만 사용)
  List<EmploymentContractModel> _pendingContracts = [];
  // FCM contractSignRequested 콜백 참조 (등록/해제 쌍 일치를 위해 보관)
  VoidCallback? _contractFcmCallback;

  void setNotificationProvider(NotificationProvider provider) {
    _notificationProvider = provider;
  }

  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isLoggedIn => _currentUser != null;

  /// 미서명 계약서 여부 (노란 바 표시용)
  bool get hasPendingContract => _pendingContracts.isNotEmpty;
  int get pendingContractCount => _pendingContracts.length;

  /// 특정 TO에 연결된 미서명 계약서 (출근 차단 확인용)
  EmploymentContractModel? pendingContractForTo(String toId) {
    if (toId.isEmpty) return null;
    try {
      return _pendingContracts.firstWhere((c) => c.toId == toId);
    } catch (_) {
      return null;
    }
  }

  bool get isAdmin => _currentUser?.isAdmin ?? false;
  bool get isSuperAdmin => _currentUser?.isSuperAdmin ?? false;
  bool get isBusinessAdmin => _currentUser?.isBusinessAdmin ?? false;
  bool get isUser => _currentUser?.isUser ?? false;
  bool get isSubAdmin => _currentUser?.isSubAdmin ?? false;
  String? get businessId => _currentUser?.businessId;

  // 하위 관리자 모드 관련
  bool get isAdminMode => _isAdminMode;
  MemberPermissions? get memberPermissions => _memberPermissions;
  /// permissions 로드 완료 여부 — false이면 아직 로딩 중 또는 로드 실패
  bool get permissionsLoaded => _permissionsLoaded;
  String? get selectedSubAdminBusinessId => _selectedSubAdminBusinessId;
  Map<String, String> get subAdminBusinessNames => _subAdminBusinessNamesView;

  static const _kSubAdminLastBizKey = 'alfit_subadmin_last_biz_id';
  static const _kSubAdminIsAdminModeKey = 'alfit_subadmin_is_admin_mode';

  /// 관리자 모드로 전환 또는 사업장 변경 (하위 관리자 전용)
  Future<void> switchToAdminMode(String businessId) async {
    if (!isSubAdmin) return;
    // D1-17 수정: 현재 유저의 subAdminBusinessIds에 포함된 사업장만 허용
    if (_currentUser == null || !_currentUser!.subAdminBusinessIds.contains(businessId)) return;

    // SA-01: 세대 카운터 — 연속 탭 또는 toggleAdminMode 호출 시 stale 재개 방지
    final gen = ++_switchGeneration;

    _selectedSubAdminBusinessId = businessId;
    _memberPermissions = null; // SA-06: stale 권한 즉시 초기화
    _isAdminMode = true;
    _permissionsLoaded = false;
    notifyListeners(); // 로딩 상태 즉시 반영

    // 사업장 ID + isAdminMode 모두 저장 (단일/다중 사업장 구분 없이)
    final prefs = await SharedPreferences.getInstance();
    if (_switchGeneration != gen) return; // SA-01: stale-check
    await prefs.setString(_kSubAdminLastBizKey, businessId);
    await prefs.setBool(_kSubAdminIsAdminModeKey, true);

    final uid = _currentUser?.uid;
    if (uid != null) {
      try {
        final perms = await MemberService().getMemberPermissions(businessId, uid);
        // SA-02: 연속 사업장 탭 시 나중에 완료된 call이 먼저 완료된 call 결과를 덮어쓰는 것 방지
        if (_selectedSubAdminBusinessId != businessId) return;
        if (_switchGeneration != gen) return; // SA-01: stale-check
        _memberPermissions = perms;
      } catch (e) {
        debugPrint('❌ permissions 로드 실패: $e');
        _memberPermissions = null;
      }
    }
    if (_switchGeneration != gen) return; // SA-01: stale-check
    _permissionsLoaded = true;
    // permissions 완료 후 FCM 업데이트 (race condition 방지)
    FCMService().updateAdminStatus(true);
    // 사업장 변경 시 리스너도 새 사업장으로 재연결
    if (uid != null) _startMemberPermsListener(businessId, uid);
    notifyListeners();
  }

  /// businesses/{bizId}/members/{uid} 실시간 리스너 — 관리자가 권한 변경/해제 시 즉시 반영
  void _startMemberPermsListener(String businessId, String uid) {
    // BUG-7 수정: 새 리스너 연결 전에 구 리스너를 먼저 취소 → 구 사업장 이벤트가 새 권한을 덮어쓰는 경쟁조건 방지
    _memberPermsSub?.cancel();
    _memberPermsSub = FirebaseFirestore.instance
        .collection('businesses')
        .doc(businessId)
        .collection('members')
        .doc(uid)
        .snapshots()
        .listen((snap) {
      if (_disposed) return;
      try {
        final data = snap.data();
        if (data != null) {
          // 권한은 멤버 문서의 'permissions' 서브맵 안에 있음 (getMemberPermissions와 동일 구조)
          _memberPermissions = MemberPermissions.fromMap(
              (data['permissions'] as Map<String, dynamic>?) ?? {});
        } else {
          // BUG-2 수정: 멤버 문서 삭제(권한 전면 해제) 시 캐시를 null로 초기화
          _memberPermissions = null;
          // [NEW-QA-01 FIX] membership 상실 → 모든 in-flight switchToAdminMode 무효화.
          // 원칙: "membership 상실 시 모든 in-flight switch는 즉시 stale 처리된다."
          // _switchGeneration++를 _isAdminMode 조건 바깥에 배치:
          //   · switchToAdminMode는 _isAdminMode=true를 첫 번째 await 이전 동기 실행으로 보장하므로
          //     현재 코드에서 _isAdminMode==false인 in-flight switch는 없음.
          //   · 그러나 미래 코드 변경(await 추가 등)에 대한 방어적 구조와
          //     "membership 상실 = 무조건 invalidation" 원칙의 정확한 표현을 위해 외부 배치.
          _switchGeneration++;
          // [SM-05 수정] 관리자가 권한 회수(member 문서 삭제) 시 관리자 모드 즉시 강제 해제
          // toggleAdminMode()와 동일한 정리 패턴 — FCM 상태 + SharedPreferences 포함
          if (_isAdminMode) {
            _isAdminMode = false;
            _permissionsLoaded = false;
            FCMService().updateAdminStatus(false);
            SharedPreferences.getInstance().then((prefs) {
              prefs.setBool(_kSubAdminIsAdminModeKey, false);
            });
          }
        }
        notifyListeners();
      } catch (e) {
        debugPrint('⚠️ memberPerms 파싱 실패 (권한 유지): $e');
      }
    }, onError: (e) => debugPrint('⚠️ memberPerms 리스너 에러: $e'));
  }

  /// 근무자 모드로 복귀 (하위 관리자만 호출 가능)
  void toggleAdminMode() {
    if (!isSubAdmin) return;
    // BUG-001: switchToAdminMode in-flight continuation의 stale 재개 차단
    _switchGeneration++;
    _isAdminMode = false;
    _permissionsLoaded = false;
    // BUG-6 수정: 근무자 모드 복귀 시 stale 권한 캐시 + 리스너 정리
    _memberPermissions = null;
    _memberPermsSub?.cancel();
    _memberPermsSub = null;
    FCMService().updateAdminStatus(false);
    // fire-and-forget: 모드 상태 영속 (await 불필요)
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool(_kSubAdminIsAdminModeKey, false);
    });
    notifyListeners();
  }

  /// 현재 유저의 유효한 단일 businessId
  /// - USER(일반 직원): users.businessId (소속 사업장)
  /// - SUB_ADMIN: 선택된 사업장 우선, 없으면 첫 번째
  /// - BUSINESS_ADMIN: null (단일값 없음 — managedBusinessIds 리스트 사용)
  String? get effectiveBusinessId {
    final user = _currentUser;
    if (user == null) return null;
    if (user.isSubAdmin) {
      // SA-04: 제거된 사업장 ID 반환 방지 — subAdminBusinessIds 포함 여부 검증
      final selected = _selectedSubAdminBusinessId;
      if (selected != null && user.subAdminBusinessIds.contains(selected)) {
        return selected;
      }
      return user.subAdminBusinessIds.firstOrNull;
    }
    if (user.isUser) return user.businessId;
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
    _memberPermsSub?.cancel();
    if (_contractFcmCallback != null) {
      FCMService().removeUserContractRefreshListener(_contractFcmCallback!);
    }
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

    // [M-1] 외국인 계정 승인 FCM 수신 시 프로필 재로드 콜백 등록
    // pending → active 전환을 앱 재시작 없이 즉시 감지할 수 있도록 FCMService와 연결
    // UserProvider는 앱 수명 동안 유지되므로 refreshUserData는 항상 유효한 콜백
    FCMService().setUserProfileRefreshCallback(refreshUserData);
    _authSubscription = _authService.authStateChanges.listen((User? firebaseUser) async {
      if (_disposed) return;
      if (firebaseUser != null) {
        await _loadUserData(firebaseUser.uid);
      } else {
        _currentUser = null;
        // signIn/signUp 진행 중에 _auth.signOut() 또는 세션 교체로 null 이벤트가 오면
        // _isLoading 을 리셋하지 않는다 — signIn() finally 블록이 정리를 담당한다.
        if (!_isSigningIn) _isLoading = false;
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
    // [NEW-03] 세대 카운터: 이 호출이 최신임을 식별. signOut() 또는 새 호출이 오면 _loadGeneration이 증가하여
    // 이 gen과 불일치 → stale load를 조기 종료.
    final gen = ++_loadGeneration;
    // signIn/signUp 경로는 호출 전에 이미 _isLoading=true를 설정하지만,
    // initialize() 의 Auth 스트림 경로는 여기서 설정한다.
    if (!_isLoading) {
      _isLoading = true;
      notifyListeners();
    }
    try {
      _currentUser = await _authService.getUserData(uid);
      if (_disposed) return; // dispose 후 결과를 반영하지 않음
      // [NEW-03] stale request는 현재 state를 절대 변경하지 않는다.
      // "A load → B login 완료 → A stale 응답" 케이스에서 userB 상태를 훼손 방지.
      // signOut 및 authStateChanges(null)이 독립적으로 모든 logout state를 책임진다.
      if (_loadGeneration != gen) return;

      // [F-01-1 restore path FIX] Auth session 존재하지만 users/{uid} 문서 없는 고아 세션 정리.
      // signIn() 경로는 auth_service.signIn()에서 이미 signOut+throw 처리됨.
      // 앱 재시작(authStateChanges auto-restore) 또는 refreshUserData 경로에서만 이 분기 도달.
      // 네트워크 오류는 getUserData가 rethrow → 아래 catch가 처리하므로 이 분기에는 미도달.
      //
      // [BUG-FIX] showToast: false — 이 경로는 사용자가 의도한 로그아웃이 아님.
      //   특히 외국인 가입 단계 1(휴대폰 인증)에서 PhoneVerificationService가
      //   `signInWithCredential`로 임시 phone-auth 계정을 생성하면 authStateChanges가 발화하고
      //   _loadUserData가 Firestore에서 해당 uid 문서를 찾지 못해 이 경로에 진입한다.
      //   showToast: true이면 "로그아웃되었습니다" 토스트가 가입 화면 위에 오표시됨.
      if (_currentUser == null) {
        await _authService.signOut(showToast: false); // Firebase Auth 세션만 정리 (경량, 토스트 없음)
        // authStateChanges(null) 핸들러가 _currentUser=null + _isLoading=false + notifyListeners() 처리
        return;
      }

      // pending / registration_pending 계정 방어 — signIn 경로의 차단(auth_service)과 동일 처리.
      // 외국인 가입 직후 signUp→_loadUserData 경로에서도 AuthWrapper가 메인화면으로
      // 이동하지 않도록 _currentUser를 세팅하지 않고 조기 반환한다.
      // Firebase Auth 세션은 유지 — 가입 후속 작업(동의 기록·Storage 업로드)이 진행 중일 수 있음.
      final acStatus = _currentUser?.accountStatus;
      if (acStatus == 'pending' || acStatus == 'registration_pending') {
        _currentUser = null;
        // [V3] '슈퍼관리자 승인' 메시지 제거 — 자동 가입 완료 flow 사용
        _error = null; // 에러 메시지 없음 — resume 화면에서 안내
        _isLoading = false;
        notifyListeners();
        return;
      }

      if (_currentUser != null) {
        // 스냅샷: await 이후 signOut() 경쟁조건으로 _currentUser가 null이 될 수 있음
        final user = _currentUser!;

        // 알림 Provider 초기화
        _notificationProvider?.setUser(user.uid);

        // FCM 초기화 + 하위 관리자 권한 로드 병렬 실행 (서로 독립)
        if (user.isSubAdmin) {
          final prefs = await SharedPreferences.getInstance();
          if (_loadGeneration != gen) return; // [NEW-03]

          // 마지막 선택 사업장 복원 (단일/다중 모두)
          // SA-05: 재진입 시에도 포함 여부 재검증 — 제거된 사업장 ID 유지 방지
          final currentSel = _selectedSubAdminBusinessId;
          if (currentSel != null && !user.subAdminBusinessIds.contains(currentSel)) {
            _selectedSubAdminBusinessId = null;
          }
          if (_selectedSubAdminBusinessId == null) {
            final saved = prefs.getString(_kSubAdminLastBizKey);
            if (saved != null && user.subAdminBusinessIds.contains(saved)) {
              _selectedSubAdminBusinessId = saved;
            }
          }

          // 앱 재시작 후에도 관리자 모드 상태 복원
          final savedIsAdminMode = prefs.getBool(_kSubAdminIsAdminModeKey) ?? false;
          _isAdminMode = savedIsAdminMode;

          final activeBizId = _selectedSubAdminBusinessId ?? user.subAdminBusinessIds.firstOrNull;

          // FCM은 일단 false로 초기화, permissions 로드 완료 후 실제 모드 반영 (race 방지)
          final fcmFuture = FCMService().initialize(user.uid, isAdmin: false);
          final permsFuture = activeBizId != null
              ? MemberService().getMemberPermissions(activeBizId, uid)
              : Future.value(null);
          final namesFuture = user.subAdminBusinessIds.length > 1
              ? FirestoreService().getBusinessNames(user.subAdminBusinessIds)
              : Future.value(<String, String>{});

          await fcmFuture;
          if (_loadGeneration != gen) return; // [NEW-03]
          // D1-20 수정: permsFuture 예외 시 외부 catch로 빠져 _permissionsLoaded=false 잔존 방지
          try {
            _memberPermissions = await permsFuture;
          } catch (e) {
            debugPrint('⚠️ getMemberPermissions 실패: $e');
            _memberPermissions = null;
          }
          if (_loadGeneration != gen) return; // [NEW-03]
          _permissionsLoaded = true;
          _subAdminBusinessNames = await namesFuture;
          if (_loadGeneration != gen) return; // [NEW-03]
          _subAdminBusinessNamesView = Map.unmodifiable(_subAdminBusinessNames);

          // permissions 로드 완료 후 저장된 모드 상태를 FCM에 반영
          if (savedIsAdminMode) {
            FCMService().updateAdminStatus(true);
          }

          // D1-19 수정: dispose()가 _memberPermsSub?.cancel() 실행 후 이 라인에 도달하면
          // _startMemberPermsListener가 새 구독을 생성하고 어디서도 cancel()되지 않는 누수 발생.
          // _disposed 체크를 리스너 연결 전으로 이동하여 방지.
          if (_disposed || _loadGeneration != gen) return; // [NEW-03] gen 체크 병합
          if (activeBizId != null) {
            _startMemberPermsListener(activeBizId, uid);
          }
        } else {
          _memberPermissions = null;
          _isAdminMode = false;

          if (user.isUser) {
            // FCM 초기화 + 미서명 계약서 로드 + homeRegion bootstrap 병렬 실행
            if (_contractFcmCallback == null) {
              _contractFcmCallback = () => refreshPendingContracts();
              FCMService().addUserContractRefreshListener(_contractFcmCallback!);
            }
            await Future.wait([
              FCMService().initialize(user.uid, isAdmin: false),
              refreshPendingContracts(),
              _bootstrapHomeRegion(uid, user), // homeRegion 1회 보정 (오류 내부 처리)
            ]);
            if (_disposed || _loadGeneration != gen) return; // [NEW-03]
          } else {
            await FCMService().initialize(user.uid, isAdmin: user.isAdmin);
            if (_disposed || _loadGeneration != gen) return; // [NEW-03]
          }
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

      // permission-denied: 삭제된 계정의 기기 캐시일 수 있음.
      // Firebase Auth reload()로 확인 — 실패하면 stale session → 자동 로그아웃.
      if (e.toString().contains('permission-denied')) {
        try {
          await FirebaseAuth.instance.currentUser?.reload();
        } catch (_) {
          debugPrint('🔄 삭제된 계정 캐시 감지 - 자동 로그아웃');
          await signOut();
          return;
        }
      }

      notifyListeners();
    }
  }

  /// [LEGACY-REGION-FALLBACK] homeRegion bootstrap
  /// 신규 USER는 가입 시 homeRegion을 직접 입력 → homeRegion != null → 즉시 return.
  /// 가입 전 기존 사용자(address는 있지만 homeRegion=null)만 address 파싱을 시도한다.
  /// 실패(오프라인·파싱 오류)는 조용히 삼키고 다음 로그인 시 재시도.
  Future<void> _bootstrapHomeRegion(String uid, UserModel user) async {
    if (user.homeRegion != null) return; // 이미 설정됨
    final addr = user.address;
    if (addr == null || addr.isEmpty) return; // 주소 없음 → skip
    final region = parseKoreanAddress(addr);
    if (region == null) return; // 파싱 실패 → 추천 fallback 동작
    try {
      await FirestoreService().updateUserDocument(uid, {'homeRegion': region.toMap()});
      if (_disposed) return;
      // _currentUser에 즉시 반영 — 홈 화면 첫 빌드에서 추천 섹션이 이미 보이도록
      if (_currentUser?.uid == uid) {
        _currentUser = _currentUser!.copyWith(homeRegion: region);
      }
    } catch (e) {
      // 오프라인 또는 일시 네트워크 오류 — 다음 로그인 시 재시도
      debugPrint('⚠️ homeRegion bootstrap 실패 (다음 로그인 시 재시도): $e');
    }
  }

  /// 미서명 계약서 목록 갱신 — 로그인 시·서명 완료 후 호출
  Future<void> refreshPendingContracts() async {
    final uid = _currentUser?.uid;
    if (uid == null || !isUser) return;
    try {
      final result = await ContractService().getByWorkerPaged(
        uid,
        statusFilter: ContractStatus.pendingWorker,
        pageSize: 50,
      );
      if (_disposed) return;
      _pendingContracts = result.items;
      notifyListeners();
    } catch (e) {
      debugPrint('⚠️ 미서명 계약서 조회 실패: $e');
    }
  }

  // 사용자 데이터 새로고침
  Future<void> refreshUserData() async {
    final user = _authService.currentUser;
    if (user != null) {
      await _loadUserData(user.uid);
    }
  }

  /// [NEW-QA-05] 임시 Auth flow에서 in-flight _loadUserData 무효화.
  /// 비밀번호 재설정 시트처럼 signInWithCustomToken → 작업 → signOut 패턴에서
  /// _auth.signOut() 직전에 호출해 stale _loadUserData가 ghost state를 설정하지 못하도록 한다.
  /// 전체 signOut() side effect(FCM·SubAdmin·ContractListener 정리)는 발생시키지 않는다.
  void invalidatePendingUserLoads() {
    _loadGeneration++;
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
    // 전화번호 시스템
    String? authPhone,
    String? phoneVerificationLevel,
    // 주소 필드
    String? address,
    String? detailAddress,
    // 추천 지역 (USER 가입 시 필수, BUSINESS_ADMIN은 null)
    UserRegion? homeRegion,
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
        authPhone: authPhone,
        phoneVerificationLevel: phoneVerificationLevel,
        address: address,
        detailAddress: detailAddress,
        homeRegion: homeRegion,
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
      _error = e.toString().replaceFirst('Exception: ', '');
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
    _isSigningIn = true;
    try {
      _isLoading = true;
      _error = null;
      _hasIncompleteRegistration = false; // [C안] 이전 미완료 상태 리셋
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
      // [C안 F-01-3] 외국인 가입 미완료 계정 — Auth 세션 유지, 복구 화면으로 안내
      if (e is IncompleteRegistrationException) {
        _hasIncompleteRegistration = true;
        debugPrint('⚠️ [signIn] 미완료 가입 계정 감지 — 복구 흐름 필요');
        return false;
      }
      // auth_service가 이미 사용자 친화적 메시지로 throw하므로 'Exception: ' prefix만 제거
      _error = e.toString().replaceFirst('Exception: ', '');
      debugPrint('❌ 로그인 실패: $e');
      return false;
    } finally {
      _isSigningIn = false;
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
      // [NEW-03] Ghost session 방지: 진행 중인 _loadUserData가 있으면 즉시 무효화
      _loadGeneration++;
      // 알림 Provider 정리
      _notificationProvider?.clearUser();

      // FCM USER 계약서 갱신 콜백 해제
      if (_contractFcmCallback != null) {
        FCMService().removeUserContractRefreshListener(_contractFcmCallback!);
        _contractFcmCallback = null;
      }

      _memberPermsSub?.cancel();
      _memberPermsSub = null;

      // FCM 토큰 삭제
      await FCMService().clearToken();

      // D1-18 수정: 로그아웃 시 SharedPreferences 서브어드민 키 삭제
      // 미삭제 시 다른 계정이 같은 기기에서 로그인하면 이전 계정의 isAdminMode가 이월됨
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kSubAdminIsAdminModeKey);
      await prefs.remove(_kSubAdminLastBizKey);

      await _authService.signOut();
      _currentUser = null;
      _memberPermissions = null;
      _permissionsLoaded = false;
      _isAdminMode = false;
      _selectedSubAdminBusinessId = null;
      _subAdminBusinessNames = {};
      _subAdminBusinessNamesView = const {};
      _pendingContracts = [];
      _error = null;
      _isLoading = false;

      // [특이사항] 로그아웃 시 FirestoreService 메모리 캐시 정리.
      // Firestore 오프라인 영속성 캐시(clearPersistence)는 활성 리스너와 충돌 위험이 있어
      // 호출 시점이 제한적이다 — 메모리 캐시(_userCache 등)만 정리한다.
      // 같은 기기에서 다른 계정으로 로그인 시 이전 사용자의 캐시된 사용자 정보 노출 방지.
      FirestoreService().clearCache();

      debugPrint('✅ 로그아웃 성공');
      notifyListeners();
      // goHome()이 AuthWrapper를 스택에서 제거한 경우에도 로그인 화면으로
      // 이동하도록 popUntil 대신 AuthWrapper를 새로 push하는 방식 사용.
      redirectToLogin();
    } catch (e) {
      debugPrint('❌ 로그아웃 실패: $e');
      // 로그아웃 실패해도 로컬 상태는 초기화
      _notificationProvider?.clearUser();
      if (_contractFcmCallback != null) {
        FCMService().removeUserContractRefreshListener(_contractFcmCallback!);
        _contractFcmCallback = null;
      }
      _memberPermsSub?.cancel();
      _memberPermsSub = null;
      _currentUser = null;
      _memberPermissions = null;
      _permissionsLoaded = false;
      _isAdminMode = false;
      _selectedSubAdminBusinessId = null;
      _subAdminBusinessNames = {};
      _subAdminBusinessNamesView = const {};
      _pendingContracts = [];
      _error = null;
      FirestoreService().clearCache();
      notifyListeners();
      redirectToLogin();
    }
  }

  // 에러 초기화
  void clearError() {
    _error = null;
    notifyListeners();
  }
  
  Future<void> refreshCurrentUser() async {
    if (_currentUser != null) {
      final uid = _currentUser!.uid; // [NEW-03] UID 스냅샷 — Firestore 응답 도착 후 재검증
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();

        final data = doc.data();
        if (_disposed) return;
        // [NEW-03] signOut 또는 계정 전환 후 stale 응답이 _currentUser를 덮어쓰는 것 방지
        if (_authService.currentUser?.uid != uid) return;
        if (doc.exists && data != null) {
          _currentUser = UserModel.fromMap(data, doc.id);
          // SubAdmin: permissions도 함께 갱신 (서버에서 권한 변경 시 즉시 반영)
          if (_currentUser!.isSubAdmin) {
            final bizId = _selectedSubAdminBusinessId ?? _currentUser!.subAdminBusinessIds.firstOrNull;
            if (bizId != null) {
              try {
                _memberPermissions = await MemberService().getMemberPermissions(bizId, _currentUser!.uid);
              } catch (e) {
                debugPrint('⚠️ permissions 갱신 실패: $e');
              }
              if (_disposed) return;
            }
          }
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