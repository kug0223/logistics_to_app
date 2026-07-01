import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../screens/business_admin/admin_review_list_screen.dart';
import '../screens/business_admin/workforce_management/integrated_workforce_screen.dart';
import '../screens/common/notification_screen.dart';
import '../screens/contract/contract_sign_screen.dart';
import '../screens/user/my_applications_screen.dart';
import '../screens/user/my_schedule_screen.dart';
import '../screens/user/user_contracts_screen.dart';
import 'contract_service.dart';
import '../models/core/employment_contract_model.dart';

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

  /// 전역 Navigator Key (main.dart에서 설정)
  GlobalKey<NavigatorState>? _navigatorKey;
  
  /// Navigator Key 설정
  void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
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
      _tokenRefreshSub = _messaging.onTokenRefresh.listen((newToken) async {
        await _updateToken(newToken);
      });

      // 5. 포그라운드 메시지 리스너
      _onMessageSub?.cancel();
      _onMessageSub = FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // 6. 백그라운드 메시지 클릭 리스너
      _onMessageOpenedAppSub?.cancel();
      _onMessageOpenedAppSub =
          FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

      // 7. 앱이 완전히 종료된 상태에서 알림 탭으로 시작된 경우 처리
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('🔔 종료 상태에서 알림 탭으로 앱 시작: ${initialMessage.notification?.title}');
        // 고정 500ms 대신 Navigator가 실제로 준비될 때까지 최대 5초 대기
        _navigateWhenReady();
      }

      _isInitialized = true;
      debugPrint('✅ FCM 초기화 완료: $userId');
    } catch (e) {
      debugPrint('❌ FCM 초기화 실패: $e');
      _currentUserId = null;
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
      );
    }

    // 지원/취소/계약서 서명 완료 알림 수신 시 관리자 화면 자동 갱신
    const adminRefreshTypes = {'newApplication', 'applicationCanceled', 'contractSigned'};
    final type = message.data['type'] as String? ?? '';
    if (adminRefreshTypes.contains(type)) {
      _notifyAdminRefresh();
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

  /// FCM data payload 기반 딥링크 라우팅
  void _navigateByPayload(Map<String, dynamic> data) {
    if (_navigatorKey?.currentState == null) return;
    final screen = data['screen'] as String?;
    switch (screen) {
      // 계약서 서명 요청 — contractId로 계약서 직접 로드 후 서명 화면 이동 (B안: 최단 경로)
      case 'contractSign':
        _navigateToContractSign(data); // fire-and-forget: 내부에서 await 처리
        break;
      // 근무자 서명 완료 알림 — 관리자 전용, 인력 관리 화면으로 직접 이동
      // SP-M-2 수정: initialize() 시 저장된 _currentUserIsAdmin으로 역할 가드.
      // USER(isAdmin=false)이면 관리자 전용 화면 대신 UserContractsScreen으로 폴백.
      case 'contractSigned':
        if (_currentUserIsAdmin) {
          _navigatorKey!.currentState!.push(
            MaterialPageRoute(builder: (_) => const IntegratedWorkforceScreen()),
          );
        } else {
          _navigatorKey!.currentState!.push(
            MaterialPageRoute(builder: (_) => const UserContractsScreen()),
          );
        }
        break;
      case 'userContracts': // contractVoided 알림 딥링크 (H-34)
        _navigatorKey!.currentState!.push(
          MaterialPageRoute(builder: (_) => const UserContractsScreen()),
        );
        break;
      case 'mySchedule': // contractRenewed·contractTerminating — 근무자 전용 알림
        _navigatorKey!.currentState!.push(
          MaterialPageRoute(builder: (_) => const MyScheduleScreen()),
        );
        break;
      // [M-001 수정] wageTransferred → UserContractsScreen (계약·급여 내역)
      // wageConfirmed(급여 확정)는 일정 확인 → MyScheduleScreen 유지
      // wageTransferred(실송금 완료)는 급여 내역 확인 목적 → UserContractsScreen
      case 'wageTransferred':
        _navigatorKey!.currentState!.push(
          MaterialPageRoute(builder: (_) => const UserContractsScreen()),
        );
        break;
      // [FCM-01 수정] fixedWorker screen → 인력 관리 화면 직접 이동 (관리자 퇴사 자동 승인 알림 딥링크)
      // 이전: 케이스 없음 → default → 알림 목록으로 떨어져 관리자가 추가로 탭해야 했음
      case 'fixedWorker':
        if (_currentUserIsAdmin) {
          _navigatorKey!.currentState!.push(
            MaterialPageRoute(builder: (_) => const IntegratedWorkforceScreen()),
          );
        } else {
          _navigateToNotificationScreen();
        }
        break;
      // [BUG-FCM-01 수정] 'contractRenewal'(contractExpiringReminder) — 관리자는 인력관리 화면으로 직접 이동.
      // 기존: case 없어 default → 알림 목록 경유 2탭 필요. 관리자면 바로 IntegratedWorkforceScreen으로.
      case 'contractRenewal':
        if (_currentUserIsAdmin) {
          _navigatorKey!.currentState!.push(
            MaterialPageRoute(builder: (_) => const IntegratedWorkforceScreen()),
          );
        } else {
          _navigateToNotificationScreen();
        }
        break;
      // ─── 지원 확정/거부 (근무자 전용) ──────────────────────────
      case 'applicationConfirmed':
      case 'applicationRejected':
        _navigatorKey!.currentState!.push(
          MaterialPageRoute(builder: (_) => const MyApplicationsScreen()),
        );
        break;
      // ─── 신규지원/지원취소 — 관리자:알림목록위임, 근무자:내지원내역 ───
      // WorkApplicantsDialog는 toId·context 필요 → 알림 탭에서 처리
      case 'newApplication':
      case 'applicationCanceled':
        if (_currentUserIsAdmin) {
          _navigateToNotificationScreen();
        } else {
          _navigatorKey!.currentState!.push(
            MaterialPageRoute(builder: (_) => const MyApplicationsScreen()),
          );
        }
        break;
      // ─── 근무 알림 (근무자 전용) ─────────────────────────────────
      case 'workReminder':
      case 'workCanceled':
        _navigatorKey!.currentState!.push(
          MaterialPageRoute(builder: (_) => const MyScheduleScreen()),
        );
        break;
      // ─── 스케줄 변경 ─────────────────────────────────────────────
      case 'scheduleChangeRequested':
        if (_currentUserIsAdmin) {
          _navigatorKey!.currentState!.push(
            MaterialPageRoute(builder: (_) => const IntegratedWorkforceScreen()),
          );
        } else {
          _navigateToNotificationScreen(); // MyRequestsDialog는 알림 탭에서 열림
        }
        break;
      case 'scheduleChangeApproved':
      case 'scheduleChangeRejected':
        _navigatorKey!.currentState!.push(
          MaterialPageRoute(builder: (_) => const MyScheduleScreen()),
        );
        break;
      // ─── 계약해지·퇴사 신청 ──────────────────────────────────────
      case 'terminationRequested':
      case 'resignRequested':
        if (_currentUserIsAdmin) {
          _navigatorKey!.currentState!.push(
            MaterialPageRoute(builder: (_) => const IntegratedWorkforceScreen()),
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
          _navigatorKey!.currentState!.push(
            MaterialPageRoute(builder: (_) => const IntegratedWorkforceScreen()),
          );
        } else {
          _navigatorKey!.currentState!.push(
            MaterialPageRoute(builder: (_) => const MyApplicationsScreen()),
          );
        }
        break;
      // ─── 신분증 열람 ─────────────────────────────────────────────
      case 'idCardAccessRequested':
        _navigateToNotificationScreen(); // MyRequestsDialog는 알림 탭에서 열림
        break;
      case 'idCardAccessApproved':
      case 'idCardAccessRejected':
        if (_currentUserIsAdmin) {
          _navigatorKey!.currentState!.push(
            MaterialPageRoute(builder: (_) => const IntegratedWorkforceScreen()),
          );
        } else {
          _navigateToNotificationScreen();
        }
        break;
      // ─── 리뷰 ────────────────────────────────────────────────────
      case 'reviewReceived':
        if (_currentUserIsAdmin) {
          _navigatorKey!.currentState!.push(
            MaterialPageRoute(builder: (_) => const AdminReviewListScreen()),
          );
        } else {
          _navigatorKey!.currentState!.push(
            MaterialPageRoute(builder: (_) => const MyScheduleScreen()),
          );
        }
        break;
      case 'reviewRequest':
        _navigateToNotificationScreen(); // 리뷰 다이얼로그는 context 필요 → 알림 탭에서 처리
        break;
      // ─── 급여 확정/취소/소급 공제 (근무자 전용) ─────────────────
      case 'wageConfirmed':
      case 'wageCancelConfirmed':
      case 'retroactiveDeductionAlert':
        _navigatorKey!.currentState!.push(
          MaterialPageRoute(builder: (_) => const MyScheduleScreen()),
        );
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
  Future<void> _navigateToContractSign(Map<String, dynamic> data) async {
    final contractId = data['contractId'] as String?;
    final applicationId = data['applicationId'] as String?;

    // contractId 없고 applicationId도 없으면 목록으로 폴백
    if ((contractId == null || contractId.isEmpty) &&
        (applicationId == null || applicationId.isEmpty)) {
      _navigatorKey?.currentState?.push(
        MaterialPageRoute(builder: (_) => const UserContractsScreen()),
      );
      return;
    }
    if (_currentUserId == null) {
      _navigatorKey?.currentState?.push(
        MaterialPageRoute(builder: (_) => const UserContractsScreen()),
      );
      return;
    }
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
        _navigatorKey!.currentState!.push(
          MaterialPageRoute(builder: (_) => const UserContractsScreen()),
        );
        return;
      }
      _navigatorKey!.currentState!.push(
        MaterialPageRoute(
          builder: (_) => ContractSignScreen(contract: contract!, role: 'worker'),
        ),
      );
    } catch (e) {
      debugPrint('❌ FCM contractSign 계약서 로드 실패: $e');
      _navigatorKey?.currentState?.push(
        MaterialPageRoute(builder: (_) => const UserContractsScreen()),
      );
    }
  }
  
  /// Navigator 준비될 때까지 최대 5초 대기 후 알림 화면 이동 (앱 종료 상태 복귀 처리)
  ///
  /// ⚠️ E06 설계 방침: 앱 종료 상태에서 알림 탭 시 payload의 screen 필드를 무시하고
  /// 무조건 알림 목록 화면으로 이동한다.
  ///
  /// 이유: 앱 종료 → 재시작 시 Navigator 스택이 비어 있으므로 initialMessage.data를 즉시
  /// 읽어도 HomeScreen 등 부모 스크린이 쌓이기 전에 푸시하면 '뒤로가기' 시 빈 화면이 된다.
  /// 알림 화면은 알림 목록을 표시하고, 사용자가 개별 알림을 탭하면 해당 화면으로 이동하는
  /// 간접 딥링크 방식으로 UX를 처리한다. 직접 딥링크가 필요하면 앱 부팅 완료 후
  /// WidgetsBinding.instance.addPostFrameCallback을 사용해 스택 구성 후 이동해야 한다.
  ///
  /// 백그라운드 탭(_handleMessageOpenedApp)은 스택이 살아있으므로 _navigateByPayload로
  /// 직접 딥링크가 가능하다.
  Future<void> _navigateWhenReady() async {
    const maxWait = 50;  // 100ms × 50 = 5초
    for (var i = 0; i < maxWait; i++) {
      if (_navigatorKey?.currentState != null) {
        _navigateToNotificationScreen();
        return;
      }
      await Future.delayed(const Duration(milliseconds: 100));
      if (_currentUserId == null) return;  // 로그아웃 후 루프 계속 방지
    }
    debugPrint('⚠️ Navigator 준비 타임아웃 — 알림 화면 이동 생략');
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
    }
  }
}