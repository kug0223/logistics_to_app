import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../screens/business_admin/admin_review_list_screen.dart';
import '../screens/business_admin/payroll/payroll_payment_dashboard_screen.dart'; // [FCM-ROUTE-01]
import '../screens/business_admin/workforce_management/integrated_workforce_screen.dart';
import '../screens/common/notification_screen.dart';
import '../screens/contract/contract_sign_screen.dart';
import '../screens/user/my_applications_screen.dart';
import '../screens/user/my_schedule_screen.dart';
import '../screens/user/user_contracts_screen.dart';
import '../screens/user/attendance_check_screen.dart';
import '../screens/user/my_reviews_screen.dart';
import '../screens/user/all_to_list_screen.dart';          // [Phase 8.1C] toMatch fallback
import '../screens/common/job_posting_screen.dart';         // [Phase 8.1C] toMatch 공고 상세 진입
import 'contract_service.dart';
import '../models/core/employment_contract_model.dart';
import '../utils/admin_tab_switcher.dart';
import '../utils/app_navigator_observer.dart';

/// FCM 푸시 알림 서비스
class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  String? _currentUserId;
  bool _currentUserIsAdmin = false;  // 역할 가드 판단용 (contractSigned 등)
  bool _isInitialized = false;
  bool _isInitializing = false;        // 중복 초기화 방지 플래그
  String? _pendingUserId;              // [118] 초기화 진행 중 계정 전환 요청 대기
  bool _notificationScreenVisible = false; // 알림 화면 중복 스택 방지 플래그
  StreamSubscription? _tokenRefreshSub;
  StreamSubscription? _onMessageSub;
  StreamSubscription? _onMessageOpenedAppSub;

  /// [Phase 9D] cold-start pending payload
  ///
  /// FCM terminated notification tap 또는 local notification terminated tap으로 앱이 시작된 경우,
  /// initialize() 시점에 Navigator/role root가 아직 마운트되지 않았을 수 있으므로
  /// 즉시 navigate하지 않고 여기에 저장한다.
  ///
  /// 소비: role root(UserRootScreen / BusinessAdminShell / AdminHomeScreen)의
  ///   initState → addPostFrameCallback → consumePendingColdStartPayload() 에서 정확히 1회 소비.
  /// 해제: clearToken()(로그아웃) 시 null로 초기화 (cross-account replay 방지).
  Map<String, dynamic>? _pendingColdStartPayload;
  
  /// [M-1] 외국인 계정 승인 시 UserProvider 전체 프로필 재로드 콜백
  /// refreshUserData()를 가리키는 단일 콜백 — 여러 구독자가 필요 없으므로 Set 아닌 단순 필드 사용
  VoidCallback? _userProfileRefreshCallback;

  /// [M-1] 외국인 계정 승인 FCM 수신 시 호출할 콜백 설정 (UserProvider.initialize에서 등록)
  /// UserProvider는 앱 수명 동안 지속되므로 별도 해제 불필요 (refreshUserData는 currentUser 없으면 no-op)
  void setUserProfileRefreshCallback(VoidCallback? callback) {
    _userProfileRefreshCallback = callback;
  }

  /// 관리자 데이터 갱신 콜백 (포그라운드 지원/취소 알림 수신 시 호출)
  final Set<VoidCallback> _adminRefreshCallbacks = {};

  void addAdminRefreshListener(VoidCallback callback) {
    _adminRefreshCallbacks.add(callback);
  }

  void removeAdminRefreshListener(VoidCallback callback) {
    _adminRefreshCallbacks.remove(callback);
  }

  void _notifyAdminRefresh() {
    for (final cb in _adminRefreshCallbacks) {
      cb();
    }
  }

  /// USER 홈 데이터 갱신 콜백 (지원 확정/거절 등 근무자 관련 FCM 수신 시 호출)
  final Set<VoidCallback> _userDataRefreshCallbacks = {};

  void addUserDataRefreshListener(VoidCallback callback) {
    _userDataRefreshCallbacks.add(callback);
  }

  void removeUserDataRefreshListener(VoidCallback callback) {
    _userDataRefreshCallbacks.remove(callback);
  }

  void _notifyUserDataRefresh() {
    for (final cb in _userDataRefreshCallbacks) {
      cb();
    }
  }

  /// USER 미서명 계약서 갱신 콜백 (contractSignRequested FCM 수신 시 호출)
  final Set<VoidCallback> _userContractRefreshCallbacks = {};

  void addUserContractRefreshListener(VoidCallback callback) {
    _userContractRefreshCallbacks.add(callback);
  }

  void removeUserContractRefreshListener(VoidCallback callback) {
    _userContractRefreshCallbacks.remove(callback);
  }

  void _notifyUserContractRefresh() {
    for (final cb in _userContractRefreshCallbacks) {
      cb();
    }
  }

  /// 전역 Navigator Key (main.dart에서 설정)
  GlobalKey<NavigatorState>? _navigatorKey;
  
  /// Navigator Key 설정
  void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  /// 서브어드민 모드 전환 시 알람 라우팅 기준 갱신 (initialize 재호출 없이 플래그만 변경)
  void updateAdminStatus(bool isAdmin) {
    _currentUserIsAdmin = isAdmin;
  }

  /// FCM 초기화 (로그인 후 호출)
  /// [isAdmin] 관리자 여부 — contractSigned 등 역할 가드에 사용 (기본 false = USER로 간주)
  Future<void> initialize(String userId, {bool isAdmin = false}) async {
    _currentUserIsAdmin = isAdmin;
    if (_isInitialized && _currentUserId == userId) {
      debugPrint('ℹ️ FCM 이미 초기화됨: $userId');
      return;
    }
    if (_isInitializing) {
      if (_currentUserId != userId) {
        // [118] 다른 사용자로 전환 요청 — 현재 초기화 완료 후 재초기화
        _pendingUserId = userId;
        debugPrint('ℹ️ FCM 초기화 진행 중 — 계정 전환($userId) 대기 등록');
      } else {
        debugPrint('ℹ️ FCM 초기화 진행 중 — 중복 호출 무시');
      }
      return;
    }
    _pendingUserId = null;
    _isInitializing = true;

    try {
      _currentUserId = userId;

      // 1. 알림 권한 요청
      final authorized = await _requestPermission();

      // 2. 로컬 알림 초기화 (포그라운드용)
      await _initializeLocalNotifications();

      // 3. FCM 토큰 저장 — 권한 거부 시 저장하지 않음 (불필요한 FCM 발송 비용 방지)
      if (authorized) await _saveToken();

      // 4. 토큰 갱신 리스너
      _tokenRefreshSub?.cancel();
      _tokenRefreshSub = _messaging.onTokenRefresh.listen(
        (newToken) async { await _updateToken(newToken); },
        onError: (e) => debugPrint('⚠️ FCM 토큰 갱신 스트림 에러: $e'),
      );

      // 5. 포그라운드 메시지 리스너
      _onMessageSub?.cancel();
      _onMessageSub = FirebaseMessaging.onMessage.listen(
        _handleForegroundMessage,
        onError: (e) => debugPrint('⚠️ FCM 포그라운드 메시지 스트림 에러: $e'),
      );

      // 6. 백그라운드 메시지 클릭 리스너
      _onMessageOpenedAppSub?.cancel();
      _onMessageOpenedAppSub = FirebaseMessaging.onMessageOpenedApp.listen(
        _handleMessageOpenedApp,
        onError: (e) => debugPrint('⚠️ FCM 앱 열기 메시지 스트림 에러: $e'),
      );

      // 7. cold-start pending payload 감지 (Phase 9D)
      // 즉시 navigate하지 않고 저장 — role root(initState)에서 정확히 1회 소비.
      // 7a. FCM terminated notification tap
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('🔔 FCM cold-start tap: ${initialMessage.notification?.title}');
        _pendingColdStartPayload = Map<String, dynamic>.from(initialMessage.data);
        debugPrint('📌 FCM cold-start payload 저장: $_pendingColdStartPayload');
      }
      // 7b. Local notification terminated tap (포���라운드 수신 후 앱 종료, 이후 탭)
      // FCM payload가 이미 있으면 건너뜀 — 둘은 mutually exclusive이지만 방어 처리
      if (_pendingColdStartPayload == null) {
        try {
          final launchDetails = await _localNotifications.getNotificationAppLaunchDetails();
          if (launchDetails?.didNotificationLaunchApp == true) {
            final lpayload = launchDetails!.notificationResponse?.payload;
            if (lpayload != null && lpayload.isNotEmpty) {
              final data = Map<String, dynamic>.from(jsonDecode(lpayload) as Map);
              _pendingColdStartPayload = data;
              debugPrint('📌 local notification cold-start payload 저장');
            }
          }
        } catch (e) {
          debugPrint('⚠️ getNotificationAppLaunchDetails 실패 (무시): $e');
        }
      }

      _isInitialized = true;
      debugPrint('✅ FCM 초기화 완료: $userId');
    } catch (e) {
      debugPrint('❌ FCM 초기화 실패: $e');
      _currentUserId = null;
      await _tokenRefreshSub?.cancel();
      await _onMessageSub?.cancel();
      await _onMessageOpenedAppSub?.cancel();
      _tokenRefreshSub = null;
      _onMessageSub = null;
      _onMessageOpenedAppSub = null;
    } finally {
      _isInitializing = false;
      // [118] 초기화 중 계정 전환 요청이 있었으면 재초기화
      final pending = _pendingUserId;
      _pendingUserId = null;
      if (pending != null && pending != _currentUserId) {
        debugPrint('🔄 FCM 계정 전환 재초기화: $pending');
        await initialize(pending);
      }
    }
  }

  /// 알림 권한 요청 — authorized/provisional이면 true 반환
  Future<bool> _requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    debugPrint('📱 알림 권한 상태: ${settings.authorizationStatus}');
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  /// 로컬 알림 초기화
  Future<void> _initializeLocalNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Android 알림 채널 생성
    const androidChannel = AndroidNotificationChannel(
      'alfit_notifications',
      'ALfit 알림',
      description: 'ALfit 앱 알림',
      importance: Importance.high,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation
            <AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  /// FCM 토큰 저장
  Future<void> _saveToken() async {
    if (_currentUserId == null) return;

    final token = await _messaging.getToken();
    if (token != null) {
      await _updateToken(token);
    }
  }

  /// FCM 토큰 업데이트
  Future<void> _updateToken(String token) async {
    if (_currentUserId == null) return;

    try {
      // 멀티 디바이스 지원 — fcmTokens 배열에 현재 토큰 추가 (최대 5개 유지)
      final userRef = FirebaseFirestore.instance.collection('users').doc(_currentUserId);
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(userRef);
        if (!snap.exists) return;
        final tokens = List<String>.from(snap.data()?['fcmTokens'] as List? ?? []);
        if (!tokens.contains(token)) {
          tokens.add(token);
          // 최대 5개 유지 (오래된 토큰부터 제거)
          if (tokens.length > 5) tokens.removeRange(0, tokens.length - 5);
        }
        tx.update(userRef, {
          'fcmTokens': tokens,
          'fcmToken': token,             // 하위 호환용 — 마지막 토큰 단일 필드도 유지
          'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        });
      });
      debugPrint('✅ FCM 토큰 저장 완료');
    } catch (e) {
      debugPrint('❌ FCM 토큰 저장 실패: $e');
    }
  }

  /// 포그라운드 메시지 처리
  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('📩 포그라운드 메시지 수신: ${message.notification?.title}');

    final notification = message.notification;
    final title = notification?.title ?? message.data['title'] as String? ?? '';
    final body = notification?.body ?? message.data['body'] as String? ?? '';
    if (title.isNotEmpty || body.isNotEmpty) {
      _showLocalNotification(
        title: title,
        body: body,
        payload: jsonEncode(message.data),
      ).catchError((e) => debugPrint('⚠️ 로컬 알림 표시 실패: $e'));
    }

    final type = message.data['type'] as String? ?? '';

    // 지원/취소/계약서 서명 완료 알림 수신 시 관리자 화면 자동 갱신
    const adminRefreshTypes = {'newApplication', 'applicationCanceled', 'contractSigned', 'confirmationCanceled'};
    if (adminRefreshTypes.contains(type)) {
      _notifyAdminRefresh();
    }

    // 계약서 서명 요청 수신 시 USER 미서명 계약서 목록 갱신 (노란 바 즉시 표시)
    if (type == 'contractSignRequested') {
      _notifyUserContractRefresh();
    }

    // 지원 확정/거절·임금 확정 수신 시 USER 홈 데이터 갱신
    const userRefreshTypes = {'applicationConfirmed', 'applicationRejected', 'wageConfirmed'};
    if (userRefreshTypes.contains(type)) {
      _notifyUserDataRefresh();
    }

    // [M-1] 외국인 계정 승인 수신 시 UserProvider 전체 프로필 재로드
    // pending 상태의 외국인 사용자가 포그라운드에서 승인 FCM을 받으면
    // UserProvider.refreshUserData() 호출 → accountStatus active 감지 → AuthWrapper가 홈화면 전환
    if (type == 'foreignAccountApproved') {
      _userProfileRefreshCallback?.call();
    }
  }

  /// 로컬 알림 표시
  Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'alfit_notifications',
      'ALfit 알림',
      channelDescription: 'ALfit 앱 알림',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      DateTime.now().microsecondsSinceEpoch.remainder(0x7FFFFFFF),
      title,
      body,
      details,
      payload: payload,
    );
  }

  /// 알림 탭 처리
  void _onNotificationTap(NotificationResponse response) {
    debugPrint('🔔 알림 탭: ${response.payload}');
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      try {
        final data = Map<String, dynamic>.from(jsonDecode(payload) as Map);
        _navigateByPayload(data);
        return;
      // payload 파싱/네비게이션 실패 시 알림 목록으로 폴백 — 사용자 경험 보호
      } catch (_) {}
    }
    _navigateToNotificationScreen();
  }

  /// 백그라운드 메시지 클릭 처리 — payload type으로 세부 화면 이동
  void _handleMessageOpenedApp(RemoteMessage message) {
    debugPrint('📩 백그라운드 메시지 클릭: ${message.data}');
    _navigateByPayload(message.data);
  }

  /// FCM 목적지 push helper — 실제 root Navigator top route 기반 TOP dedupe 적용
  ///
  /// AppNavigatorObserver.instance.currentRouteName == 'fcm:$destinationKey' 일 때만
  /// push skip. 비-FCM route(anonymous MaterialPageRoute)가 top이면 push 허용.
  /// RouteSettings.name = 'fcm:$destinationKey' 설정 (내부 navigation metadata 용도).
  void _pushFcmScreen({
    required String destinationKey,
    required WidgetBuilder builder,
  }) {
    if (_navigatorKey?.currentState == null) return;
    final targetName = 'fcm:$destinationKey';
    // 실제 root navigator top route name과 비교 — _fcmKeyStack이 아닌 observer 기반
    if (AppNavigatorObserver.instance.currentRouteName == targetName) return;
    _navigatorKey!.currentState!.push(
      MaterialPageRoute(
        settings: RouteSettings(name: targetName),
        builder: builder,
      ),
    );
  }

  /// FCM data payload 기반 딥링크 라우팅
  void _navigateByPayload(Map<String, dynamic> data) {
    if (_navigatorKey?.currentState == null) return;
    // screen 필드 우선, 없으면 type 폴백 (일부 알림은 screen 없이 type만 포함)
    final screen = (data['screen'] as String?) ?? (data['type'] as String?);
    // BUG-5 수정: 다중 사업장 서브어드민이 알림 탭 시 올바른 사업장으로 이동하도록 businessId 추출
    final notifBusinessId = data['businessId'] as String?;
    // IntegratedWorkforceScreen dedupe key — business context 단위
    final iwKey = 'integrated_workforce:${notifBusinessId ?? 'default'}';
    switch (screen) {
      // 계약서 서명 요청 — contractId로 계약서 직접 로드 후 서명 화면 이동 (B안: 최단 경로)
      case 'contractSign':
        _navigateToContractSign(data); // fire-and-forget: 내부에서 await + _pushFcmScreen 처리
        break;
      // 근무자 서명 완료 알림 — 관리자 전용, 인력 관리 화면으로 직접 이동
      // SP-M-2 수정: initialize() 시 저장된 _currentUserIsAdmin으로 역할 가드.
      // USER(isAdmin=false)이면 관리자 전용 화면 대신 UserContractsScreen으로 폴백.
      case 'contractSigned':
        if (_currentUserIsAdmin) {
          _pushFcmScreen(
            destinationKey: iwKey,
            builder: (_) => IntegratedWorkforceScreen(initialBusinessId: notifBusinessId, notificationType: screen),
          );
        } else {
          _pushFcmScreen(
            destinationKey: 'user_contracts',
            builder: (_) => const UserContractsScreen(),
          );
        }
        break;
      case 'userContracts': // contractVoided 알림 딥링크 (H-34)
        _pushFcmScreen(
          destinationKey: 'user_contracts',
          builder: (_) => const UserContractsScreen(),
        );
        break;
      case 'mySchedule': // contractRenewed·contractTerminating·workReminder 등 일정 관련
        _pushFcmScreen(
          destinationKey: 'my_schedule',
          builder: (_) => const MyScheduleScreen(),
        );
        break;
      // wageTransferred(실송금 완료) → MyScheduleScreen (wageConfirmed와 동일 목적지로 통일)
      // UserContractsScreen은 계약서 화면이므로 급여 알림 목적지로 부적합
      case 'wageTransferred':
        _pushFcmScreen(
          destinationKey: 'my_schedule',
          builder: (_) => const MyScheduleScreen(),
        );
        break;
      // [PATCH-FCM-A1A] fixedWorker (고용 생애주기 관리자 알림)
      // WORKFORCE-SUBADMIN-BIZCTX-01 회피: notification target B ≠ effective business A 시
      // switchToTab(workforceTab)은 A context로 열려 wrong-context가 되므로 interim NotificationScreen 사용.
      // TODO(R3B): NotificationScreen canonicalization 후 target-business-aware route로 개선
      case 'fixedWorker':
        if (_currentUserIsAdmin) {
          _navigateToNotificationScreen();
        } else {
          _navigateToNotificationScreen();
        }
        break;
      // [BUG-FCM-01 수정] 'contractRenewal'(contractExpiringReminder) — 관리자는 인력관리 화면으로 직접 이동.
      // 기존: case 없어 default → 알림 목록 경유 2탭 필요. 관리자면 바로 IntegratedWorkforceScreen으로.
      case 'contractRenewal':
        if (_currentUserIsAdmin) {
          _pushFcmScreen(
            destinationKey: iwKey,
            builder: (_) => IntegratedWorkforceScreen(initialBusinessId: notifBusinessId, notificationType: screen),
          );
        } else {
          _navigateToNotificationScreen();
        }
        break;
      // ─── [Phase 8.1C] 일자리 매칭 알림 ─────────────────────────
      // toMatch: 근로자가 가능일에 새 일자리 발견 → 해당 공고 상세 직접 진입
      // toId 없는 경우(비정상 payload)에만 AllTOListScreen fallback.
      // 공고가 CLOSED/FULL/EXPIRED 상태여도 JobPostingScreen이 자체 처리
      // (_isEffectivelyClosed 게터로 안내 + 지원버튼 비활성).
      // DELETED(getTO→null)는 화면 내부에서 오류 toast 처리.
      case 'toMatch':
        {
          final toMatchToId = data['toId'] as String?;
          if (toMatchToId != null && toMatchToId.isNotEmpty) {
            _pushFcmScreen(
              destinationKey: 'job_posting_$toMatchToId',
              builder: (_) => JobPostingScreen(toId: toMatchToId),
            );
          } else {
            // toId 없는 비정상 payload → 일자리 목록 fallback
            _pushFcmScreen(
              destinationKey: 'job_list',
              builder: (_) => const AllTOListScreen(),
            );
          }
        }
        break;
      // ─── TO 초대 알림 ────────────────────────────────────────────
      // toInvite: 근무자가 초대 수신 → 내 지원내역(초대 탭)으로 이동
      case 'toInvite':
      // toInviteCanceled: 관리자가 초대 취소 → 근무자가 수신 → 내 지원내역으로
      case 'toInviteCanceled':
        _pushFcmScreen(
          destinationKey: 'my_applications',
          builder: (_) => const MyApplicationsScreen(),
        );
        break;
      // toInviteAccepted/Declined: 관리자가 수신 → Jobs 탭 (공고 관리 canonical destination)
      // [PATCH-FCM-B] ADMIN.POSTING.ROUTE-INTEGRITY-01
      // admin: Jobs tab (Shell active + visible) / NotificationScreen fallback
      // worker: MyApplicationsScreen (기존 유지)
      case 'toInviteAccepted':
      case 'toInviteDeclined':
        if (_currentUserIsAdmin) {
          if (!AdminTabSwitcher.instance.switchToTab(AdminTabSwitcher.jobsTab)) {
            _navigateToNotificationScreen();
          }
        } else {
          _pushFcmScreen(
            destinationKey: 'my_applications',
            builder: (_) => const MyApplicationsScreen(),
          );
        }
        break;
      // ─── 지원 확정/거부 (근무자 전용) ──────────────────────────
      case 'applicationConfirmed':
      case 'applicationRejected':
      // callableConfirmApplication이 screen='applicationDetail'을 포함하므로
      // data['screen']='applicationDetail' → type 폴백 없이 이 케이스로 직접 라우팅
      case 'applicationDetail':
        _pushFcmScreen(
          destinationKey: 'my_applications',
          builder: (_) => const MyApplicationsScreen(),
        );
        break;
      // ─── 파트변경 알림 (근무자 전용) ─────────────────────────
      case 'workTypeChanged':
        _pushFcmScreen(
          destinationKey: 'my_applications',
          builder: (_) => const MyApplicationsScreen(),
        );
        break;
      // ─── 확정 취소 — 관리자:알림목록위임(WorkApplicantsDialog context 필요), 근무자:내지원내역 ───
      case 'confirmationCanceled':
        if (_currentUserIsAdmin) {
          _navigateToNotificationScreen();
        } else {
          _pushFcmScreen(
            destinationKey: 'my_applications',
            builder: (_) => const MyApplicationsScreen(),
          );
        }
        break;
      // ─── 신규지원/지원취소 — 관리자:알림목록위임, 근무자:내지원내역 ───
      // WorkApplicantsDialog는 toId·context 필요 → 알림 탭에서 처리
      case 'newApplication':
      case 'applicationCanceled':
        if (_currentUserIsAdmin) {
          _navigateToNotificationScreen();
        } else {
          _pushFcmScreen(
            destinationKey: 'my_applications',
            builder: (_) => const MyApplicationsScreen(),
          );
        }
        break;
      // ─── 리컨펌 출근 확인 요청 (근무자 전용) ──────────────────────
      // AttendanceCheckScreen은 constructor param 없음 (오늘 근무 로드는 screen 내부에서 처리)
      case 'attendanceCheck':
        _pushFcmScreen(
          destinationKey: 'attendance_check',
          builder: (_) => const AttendanceCheckScreen(),
        );
        break;
      // ─── 근무 알림 (근무자 전용) ─────────────────────────────────
      case 'workReminder':
      case 'workCanceled':
        _pushFcmScreen(
          destinationKey: 'my_schedule',
          builder: (_) => const MyScheduleScreen(),
        );
        break;
      // ─── 스케줄 변경 ─────────────────────────────────────────────
      // [PATCH-FCM-A1A] scheduleChangeRequested 관리자 IWS route 제거
      // WORKFORCE-SUBADMIN-BIZCTX-01 회피: target B ≠ effective A → wrong-context
      // TODO(R3B): NotificationScreen canonicalization 후 ScheduleRequestManagementDialog 직접 연결
      case 'scheduleChangeRequested':
        if (_currentUserIsAdmin) {
          _navigateToNotificationScreen();
        } else {
          _navigateToNotificationScreen(); // MyRequestsDialog는 알림 탭에서 열림
        }
        break;
      case 'scheduleChangeApproved':
      case 'scheduleChangeRejected':
        _pushFcmScreen(
          destinationKey: 'my_schedule',
          builder: (_) => const MyScheduleScreen(),
        );
        break;
      // ─── 계약해지 신청 ────────────────────────────────────────────
      // [PATCH-FCM-A1B] terminationRequested: admin→worker 방향 — admin path DEAD LEGACY
      // producer(callableRequestTermination)는 workerUid에게만 발송; admin은 safe fallback
      case 'terminationRequested':
        if (_currentUserIsAdmin) {
          _navigateToNotificationScreen();
        } else {
          _navigateToNotificationScreen();
        }
        break;
      // ─── 퇴사 신청 ───────────────────────────────────────────────
      // [PATCH-FCM-A1B] resignRequested: worker→admin 방향 — canManageWorkers
      // WORKFORCE-SUBADMIN-BIZCTX-01 회피: interim NotificationScreen (R3B에서 개선)
      case 'resignRequested':
        if (_currentUserIsAdmin) {
          _navigateToNotificationScreen();
        } else {
          _navigateToNotificationScreen();
        }
        break;
      // ─── 계약 작성 요청 ──────────────────────────────────────────
      // contractRequested: worker→admin CONTRACT intent — canManageContract
      // [PATCH-FCM-A1B] IWS hold: ADMIN.CONTRACT-MGMT.SUBADMIN-BIZCTX-01 미확정 → PATCH-FCM-C까지 유지
      case 'contractRequested':
        if (_currentUserIsAdmin) {
          _pushFcmScreen(
            destinationKey: iwKey,
            builder: (_) => IntegratedWorkforceScreen(initialBusinessId: notifBusinessId, notificationType: screen),
          );
        } else {
          _navigateToNotificationScreen();
        }
        break;
      case 'terminationApproved':
      case 'terminationRejected':
      case 'resignApproved':
      case 'resignRejected':
        if (_currentUserIsAdmin) {
          _pushFcmScreen(
            destinationKey: iwKey,
            builder: (_) => IntegratedWorkforceScreen(initialBusinessId: notifBusinessId, notificationType: screen),
          );
        } else {
          _pushFcmScreen(
            destinationKey: 'my_applications',
            builder: (_) => const MyApplicationsScreen(),
          );
        }
        break;
      // ─── 멤버 초대 결과 — 관리자에게 발송 ──────────────────────
      // memberInvitationReceived: 다이얼로그 처리 필요 → 알림 탭에서 처리 (케이스 없음 → default)
      case 'memberInvitationAccepted':
      case 'memberInvitationRejected':
        // [PATCH-FCM-D] ADMIN.POSTING.ROUTE-INTEGRITY-01
        // admin·non-admin 모두 NotificationScreen으로 — IntegratedWorkforceScreen(IWS) 제거
        // 멤버 초대 결과는 대화 컨텍스트(알림 목록)에서 처리
        _navigateToNotificationScreen();
        break;
      // ─── 신분증 열람 ─────────────────────────────────────────────
      case 'idCardAccessRequested':
        _navigateToNotificationScreen(); // MyRequestsDialog는 알림 탭에서 열림
        break;
      case 'idCardAccessApproved':
      case 'idCardAccessRejected':
        // [PATCH-FCM-D] ADMIN.POSTING.ROUTE-INTEGRITY-01
        // admin·non-admin 모두 NotificationScreen으로 — IntegratedWorkforceScreen(IWS) 제거
        // 신분증 열람 결과는 알림 목록에서 열람 컨텍스트와 함께 처리
        _navigateToNotificationScreen();
        break;
      // ─── 리뷰 ────────────────────────────────────────────────────
      case 'reviewReceived':
        if (_currentUserIsAdmin) {
          _pushFcmScreen(
            destinationKey: 'admin_review_list',
            builder: (_) => const AdminReviewListScreen(),
          );
        } else {
          // "리뷰 받았습니다" → 내 근무 평가 화면에서 직접 확인
          _pushFcmScreen(
            destinationKey: 'my_reviews',
            builder: (_) => const MyReviewsScreen(),
          );
        }
        break;
      case 'REVIEW_REQUEST':
        _navigateToNotificationScreen(); // 리뷰 다이얼로그는 context 필요 → 알림 탭에서 처리
        break;
      // ─── 급여 확정/취소/소급 공제 (근무자 전용) ─────────────────
      case 'wageConfirmed':
      case 'wageCancelConfirmed':
      case 'retroactiveDeductionAlert':
        _pushFcmScreen(
          destinationKey: 'my_schedule',
          builder: (_) => const MyScheduleScreen(),
        );
        break;
      // ─── 중간정산 (FCM-01) ────────────────────────────────────────
      // [FCM-ROUTE-01] 중간정산 관리 canonical destination 교체:
      //   IntegratedWorkforceScreen(NO DIRECT MANAGEMENT)
      //   → PayrollPaymentDashboardScreen(FULL MANAGEMENT, tab 3)
      // SUB_ADMIN: role==USER → _currentUserIsAdmin==false → NotificationScreen 경유 permission 검증.
      // year/month: settlement tab query는 businessId 기준(month-free), DateTime.now() fallback 안전.
      case 'interimSettlementAdmin': // 관리자 수신 — 급여 중간정산 탭으로 직접 이동
        if (_currentUserIsAdmin) {
          // [FCM-ROUTE-01-NULL-GUARD] businessId 없거나 공백이면 알림함 폴백 (빈 Dashboard 방지)
          if (notifBusinessId == null || notifBusinessId.trim().isEmpty) {
            _navigateToNotificationScreen();
            break;
          }
          final now = DateTime.now();
          // Shell active → Settlement tab canonical routing (Back: Dashboard → PayrollOverview)
          if (!AdminTabSwitcher.instance.switchToTabAndPush(
            AdminTabSwitcher.payrollTab,
            MaterialPageRoute<void>(
              builder: (_) => PayrollPaymentDashboardScreen(
                businessId: notifBusinessId,
                year: now.year,
                month: now.month,
                initialTab: 3,
                showPendingSettlementOnly: true,
              ),
            ),
          )) {
            // Shell 미활성(cold-start / 앱 종료) → root navigator fallback
            _pushFcmScreen(
              destinationKey: 'payroll_settlement:$notifBusinessId',
              builder: (_) => PayrollPaymentDashboardScreen(
                businessId: notifBusinessId,
                year: now.year,
                month: now.month,
                initialTab: 3,
                showPendingSettlementOnly: true,
              ),
            );
          }
        } else {
          _navigateToNotificationScreen();
        }
        break;
      case 'interimSettlement': // 근무자 수신 — 급여/일정 확인 화면으로
        _pushFcmScreen(
          destinationKey: 'my_schedule',
          builder: (_) => const MyScheduleScreen(),
        );
        break;
      // ─── 공고 만료 임박 (관리자 전용, CF masterScheduler) ────
      case 'toDetail': // toPostingExpiringTomorrow 알림의 screen 필드 값
        if (_currentUserIsAdmin) {
          // [P2-B-FIX] IntegratedWorkforceScreen push 대신 Shell Jobs 탭 전환
          // Shell 활성 상태(포그라운드/백그라운드) → 탭 전환
          // [PATCH-FCM-E] ADMIN.POSTING.ROUTE-INTEGRITY-01
          // Shell 미활성(disposed) edge case → NotificationScreen 안전 fallback
          // 정상 cold-start(BusinessAdminShell 경유)에서는 AdminTabSwitcher가
          // initState에서 동기 등록되므로 switchToTab이 항상 true — 이 분기 미도달
          if (!AdminTabSwitcher.instance.switchToTab(AdminTabSwitcher.jobsTab)) {
            _navigateToNotificationScreen();
          }
        } else {
          _navigateToNotificationScreen();
        }
        break;
      // [M-1] 외국인 계정 승인 딥링크 — 특정 화면 이동 없이 프로필 재로드만 트리거
      // UserProvider.refreshUserData() → accountStatus active → AuthWrapper가 홈화면 자동 전환
      // 앱 종료 상태에서 탭 시에는 authStateChanges 재발화로 처리되므로 여기서는 백그라운드 복귀 전용
      case 'foreignAccountApproved':
        _userProfileRefreshCallback?.call();
        break;
      default:
        _navigateToNotificationScreen();
    }
  }

  /// 계약서 서명 화면 직접 이동 — contractId(있으면 단건 GET) 또는 applicationId 기반 조회 후
  /// ContractSignScreen 푸시. 조회 실패 시 UserContractsScreen으로 폴백.
  ///
  /// [보안] USER role은 employment_contracts 직접 list가 거부된다.
  /// FCM payload에 contractId가 있으면 getById(단건 GET)를 우선 사용하고,
  /// 없을 때만 getByApplication(workerId 경로) 폴백을 허용한다.
  ///
  /// [dedupe] entity-specific key 'contract_sign:$contractId' 사용.
  /// async 시작 전 TOP dedupe 선제 검사 — 같은 계약서는 중복 push 차단.
  Future<void> _navigateToContractSign(Map<String, dynamic> data) async {
    final contractId = data['contractId'] as String?;
    final applicationId = data['applicationId'] as String?;

    const fallbackKey = 'user_contracts';

    // contractId 없고 applicationId도 없으면 목록으로 폴백
    if ((contractId == null || contractId.isEmpty) &&
        (applicationId == null || applicationId.isEmpty)) {
      _pushFcmScreen(
        destinationKey: fallbackKey,
        builder: (_) => const UserContractsScreen(),
      );
      return;
    }
    if (_currentUserId == null) {
      _pushFcmScreen(
        destinationKey: fallbackKey,
        builder: (_) => const UserContractsScreen(),
      );
      return;
    }

    // entity key 결정 — async 시작 전 TOP dedupe 선제 검사
    final signKey = (contractId != null && contractId.isNotEmpty)
        ? 'contract_sign:$contractId'
        : fallbackKey;
    if (AppNavigatorObserver.instance.currentRouteName == 'fcm:$signKey') return;

    try {
      EmploymentContractModel? contract;

      // contractId 우선 — 단건 GET, USER role도 허용됨 (list 쿼리 PERMISSION_DENIED 회피)
      if (contractId != null && contractId.isNotEmpty) {
        contract = await ContractService().getById(contractId);
      }

      // [FCM-FIX] 폴백(applicationId 기반 list 쿼리) 제거 — USER는 employment_contracts list 불가
      // → notification_screen.dart 동일 정책: getByApplication 경로 차단, 목록 화면으로 안내
      if (_navigatorKey?.currentState == null) return;
      if (contract == null) {
        _pushFcmScreen(
          destinationKey: fallbackKey,
          builder: (_) => const UserContractsScreen(),
        );
        return;
      }
      _pushFcmScreen(
        destinationKey: signKey,
        builder: (_) => ContractSignScreen(contract: contract!, role: 'worker'),
      );
    } catch (e) {
      debugPrint('❌ FCM contractSign 계약서 로드 실패: $e');
      _pushFcmScreen(
        destinationKey: fallbackKey,
        builder: (_) => const UserContractsScreen(),
      );
    }
  }
  
  /// [Phase 9D] cold-start pending payload 소비 — role root의 initState에서 1회 호출
  ///
  /// 호출 시점: UserRootScreen / BusinessAdminShell / AdminHomeScreen의 initState →
  ///   addPostFrameCallback. 이 시점에는 role root가 실제로 마운트되어 있으므로
  ///   Navigator.push()의 back stack이 정상적으로 동작한다(Back → role root).
  ///
  /// 단일 소비 보장: payload를 null로 초기화한 후 navigate — 재진입/rebuild에서 중복 navigate 없음.
  /// Auth 안전성: initialize()는 로그인 상태에서만 호출되므로 payload는 항상 현재 인증 사용자의 것.
  ///   cross-account 방지: clearToken()(로그아웃) 시 payload 초기화 — 다른 계정 재로그인 후 replay 없음.
  void consumePendingColdStartPayload() {
    final payload = _pendingColdStartPayload;
    if (payload == null) return;
    _pendingColdStartPayload = null; // 먼저 clear — 재진입 중복 방지
    debugPrint('🔔 cold-start payload 소비: $payload');
    _navigateByPayload(payload);
  }

  /// 알림 화면으로 이동 — 이미 열려있으면 중복 push 차단
  void _navigateToNotificationScreen() {
    if (_navigatorKey?.currentState == null) {
      debugPrint('⚠️ Navigator가 아직 준비되지 않음');
      return;
    }
    if (_notificationScreenVisible) return;

    _notificationScreenVisible = true;
    _navigatorKey!.currentState!.push(
      MaterialPageRoute(builder: (_) => const NotificationScreen()),
    ).then((_) {
      _notificationScreenVisible = false;
    });
  }

  /// 근무지 이탈 경고 로컬 알림 (출퇴근 화면 전용)
  Future<void> showGeofenceAlert(String businessName) async {
    await _showLocalNotification(
      title: '근무지 이탈 감지',
      body: '$businessName 근무지에서 벗어났습니다. 복귀 또는 퇴근 처리를 확인해주세요.',
    );
  }

  /// 로그아웃 시 토큰 삭제
  Future<void> clearToken() async {
    try {
      if (_currentUserId != null) {
        final currentToken = await _messaging.getToken();
        final updates = <String, dynamic>{'fcmToken': FieldValue.delete()};
        if (currentToken != null) {
          // 현재 디바이스 토큰만 배열에서 제거 — 다른 디바이스 토큰은 유지
          updates['fcmTokens'] = FieldValue.arrayRemove([currentToken]);
        }
        await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUserId)
            .update(updates);
        debugPrint('✅ FCM 토큰 삭제 완료');
      }
    } catch (e) {
      debugPrint('❌ FCM 토큰 삭제 실패: $e');
    } finally {
      // _currentUserId null 여부와 무관하게 구독은 항상 취소
      _tokenRefreshSub?.cancel();
      _tokenRefreshSub = null;
      _onMessageSub?.cancel();
      _onMessageSub = null;
      _onMessageOpenedAppSub?.cancel();
      _onMessageOpenedAppSub = null;
      _currentUserId = null;
      _isInitialized = false;
      _isInitializing = false;
      _notificationScreenVisible = false; // 로그아웃 시 리셋 — 재로그인 후 알림 화면 진입 가능하도록
      _pendingColdStartPayload = null;    // [Phase 9D] cross-account replay 방지
      // _fcmKeyStack 제거됨 — AppNavigatorObserver가 실제 top route 추적 (NAV.3-FIX-A)
    }
  }
}