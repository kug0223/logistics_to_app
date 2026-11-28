import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'theme/app_colors.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;
import 'providers/user_snapshot_prefetch.dart';
import 'services/app_check_ready.dart';
import 'services/app_version_service.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'providers/user_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/network_provider.dart';
import 'providers/badge_provider.dart';
import 'models/core/user_model.dart';
import 'screens/auth/auth_start_screen.dart';
import 'services/auth/kakao_auth_service.dart';
import 'screens/user/user_root_screen.dart';
import 'screens/super_admin/super_admin_home_screen.dart';
import 'screens/business_admin/business_admin_shell.dart';
import 'screens/common/splash_screen.dart';
import 'screens/common/forced_update_screen.dart';
import 'screens/common/onboarding_screen.dart';
import 'screens/common/deletion_reauth_screen.dart';
import 'utils/wage_calculator.dart';
import 'services/fcm_service.dart';
import 'services/insurance_rate_service.dart';
import 'services/analytics_service.dart';
import 'utils/app_navigator_observer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'utils/prefs_preload.dart';
import 'utils/perf_log.dart';
import 'widgets/common/network_banner.dart';
import 'utils/tour_helper.dart';
import 'utils/navigation_key.dart';
import 'utils/sensitive_cache_cleanup.dart';
import 'widgets/inputs/home_region_picker_sheet.dart';
import 'models/core/user_region.dart';
import 'services/firestore_service.dart';
import 'services/auth_service.dart';
import 'utils/toast_helper.dart';
import 'utils/responsive_helper.dart';
import 'utils/text_layout.dart';

/// 앱이 완전히 종료된 상태에서 FCM 메시지 수신 시 호출되는 최상위 핸들러
/// (반드시 main() 바깥 최상위 함수여야 함 — Flutter 요구사항)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('🔔 [백그라운드] FCM 수신: ${message.notification?.title}');
}

void main() async {
  // [PERF] t0 — 꺼진 빌드(기본)에서는 아무것도 하지 않는다(utils/perf_log.dart).
  PerfLog.start();
  // preserve()는 ensureInitialized() 직후 가장 먼저 호출해야 함
  // Firebase.initializeApp() 동안에도 네이티브 스플래시를 유지시켜
  // SplashScreen 위젯이 준비된 후 remove()를 호출할 때까지 대기
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);

  // [PERF-P3] 로컬 저장소를 Firebase 초기화와 **겹쳐서** 미리 연다(기다리지 않는다).
  //   AuthWrapper 가 uid 확정 뒤 온보딩 여부를 같은 프레임에 읽어, 흰 스피너 프레임을 없앤다.
  unawaited(PrefsPreload.start());

  // 세로 모드 고정 — 가로 회전 레이아웃 깨짐 방지
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // 릴리즈 빌드에서 debugPrint 전체 비활성화
  if (!kDebugMode) debugPrint = (String? message, {int? wrapWidth}) {};

  // 앱 종료 상태 FCM 백그라운드 핸들러 등록 (Firebase 초기화 전에 먼저 등록)
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await initializeDateFormatting('ko_KR', null);
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Remote Config 초기화 (버전 체크용)
    PerfLog.mark('main.firebase.done');
    await AppVersionService.init();

    // Firebase App Check — API 키 무단 사용 방지
    // 릴리즈: Play Integrity(Android) / DeviceCheck(iOS) 사용
    // 디버그: DebugProvider (Firebase 콘솔에서 디버그 토큰 등록 필요)
    // activate() 후 getToken()으로 토큰을 미리 발급해 캐시에 저장:
    // 앱 시작 시 여러 CF가 동시에 호출되면 각각이 토큰을 요청하면서
    // SDK 내부 "Too many attempts" 에러가 발생하고 CF에 깨진 토큰이 전달됨.
    // 미리 토큰을 받아두면 이후 모든 CF 호출은 캐시된 토큰을 사용함.
    await FirebaseAppCheck.instance.activate(
      androidProvider: kDebugMode
          ? AndroidProvider.debug
          : AndroidProvider.playIntegrity,
      appleProvider: kDebugMode
          ? AppleProvider.debug
          : AppleProvider.deviceCheck,
    );
    // 토큰 미리 발급 (실패해도 앱 시작 차단 안 함)
    // 앱 시작 시 여러 CF가 동시에 호출되면 각각이 토큰을 요청하면서
    // SDK 내부 "Too many attempts" 에러 방지 — 캐시에 미리 저장
    // [PERF-L12] runApp 은 이 토큰을 기다리지 않는다. 첫 토큰 받기는 한 번만 출발하고(공유 future),
    //   앱 시작 직후의 첫 Firebase 요청들(사용자 문서 · 미리 읽기 · 최저시급/보험료율 · 로그인)이
    //   `AppCheckReady.wait()` 로 그 같은 future 에 합류한 뒤 나간다 — "Too many attempts" 방어는 그대로.
    unawaited(AppCheckReady.start(() => FirebaseAppCheck.instance.getToken())
        .whenComplete(() => PerfLog.mark('main.appcheck.done')));

    // Firestore 캐시 설정 (서버 우선)
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: 100 * 1024 * 1024, // 100MB 상한 (무제한 → 저장공간 보호)
    );

    // (Firestore settings 는 첫 사용 전에만 바꿀 수 있다 — 그래서 settings 바로 뒤다.)
    // [PERF-L1 안전판 · 판정289 §3] 복원된 세션이 있으면 사용자 문서 **읽기만** 버전 판정과 겹쳐 출발시킨다.
    //   부수효과 0(구독·FCM·쓰기·callable 없음). 판정 뒤 UserProvider 가 uid·시효를 보고 1회 소비하고,
    //   기존 세대 검사·계정 판정을 그대로 지난다. 실패하면 소비자가 평소처럼 다시 읽는다.
    final restoredUid = FirebaseAuth.instance.currentUser?.uid;
    if (restoredUid != null) {
      // [PERF-L12] 첫 토큰에 합류한 뒤 읽는다(토큰 요청을 겹치지 않게).
      UserSnapshotPrefetch.start(restoredUid,
          (uid) => AppCheckReady.wait().then((_) => AuthService().getUserData(uid)));
      PerfLog.mark('main.userPrefetch.start');
    }

    // Crashlytics: 웹 미지원 — 모바일/데스크톱에서만 활성화
    if (!kIsWeb) {
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    }

    // 위젯 빌드 에러 → 기본 빨간 화면 대신 사용자 친화적 UI
    ErrorWidget.builder = (FlutterErrorDetails details) {
      // 디버그 모드에서는 기본 에러 위젯 유지 (스택 추적 확인)
      if (kDebugMode) return ErrorWidget(details.exception);
      return _AppErrorWidget(details: details);
    };

    // [AUD-10 M2 · impl_70] 이전 실행이 남긴 플러그인 공유 사본(cache/share_plus · cache/share) 정리 —
    //   첫 화면과 겹치지 않게 늦게 한 번(기다리지 않는다 · 실패 무시).
    SensitiveCacheCleanup.onAppStart();

    debugPrint('✅ Firebase 초기화 완료');
  } catch (e) {
    // Firebase 초기화 실패 시에도 앱을 계속 실행한다.
    // Firestore persistenceEnabled=true 로 오프라인 캐시에서 부분 기능 제공 가능하며,
    // SplashScreen → AuthWrapper가 로딩 상태를 표시하므로 사용자 UX는 유지된다.
    debugPrint('❌ Firebase 초기화 에러: $e');
  }
  // [ALFIT-AUTH-KAKAO-ONBOARDING.1] 카카오 SDK — 네이티브 앱 키(dart-define)가 있을 때만 초기화. 없으면 '준비 중'.
  KakaoAuthService.install();

  // 최저시급·보험료율 캐시 로드 (병렬, 실패해도 로컬 백업 사용)
  // [PERF-L12] 예전에는 main 이 App Check 첫 토큰을 기다린 뒤라 이미 토큰이 있었다 — 같은 순서를 지킨다.
  unawaited(AppCheckReady.wait().then((_) {
    WageCalculator.loadMinimumWages();
    InsuranceRateService.loadRates();
  }));

  // 🔔 FCM에 Navigator Key 전달
  FCMService().setNavigatorKey(navigatorKey);
  // [.69] 이전 로그아웃이 끝내지 못한 기기 토큰 폐기를 이어서 한다(로그인 전에도). 결과는 기기 표식으로 남고,
  //   로그인은 FCMService.initialize 에서 이 폐기를 다시 기다린다 — 여기서 앱 시작을 막지 않는다.
  unawaited(FCMService().settlePendingRevoke());

  // [VERSION-GATE §6] 백그라운드 복귀 시 최소 버전 재확인.
  //   확인 주기(30분)를 지켰을 때만 실제로 받고, **차단 판정일 때만**
  //   라우트를 대체한다. 그래야 쓰던 화면으로 돌아갈 수 없다.
  AppVersionService.startResumeWatch((result) {
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => ForcedUpdateScreen(
          result: result,
          // [DU313 r3] 새 판정을 차단 화면에 돌려준다(splash 호출부와 같다) — 막힌 그대로면 화면이 그 판정으로 바뀐다.
          onRetry: () async {
            final again = await AppVersionService.evaluate(forceFetch: true);
            if (again.status != VersionGateStatus.supported) return again;
            navigatorKey.currentState?.pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const AuthWrapper()),
              (route) => false,
            );
            return again;
          },
        ),
      ),
      (route) => false,
    );
  });

  // 로그아웃 후 로그인 화면 이동 콜백 등록
  // goHome()이 (route)=>false로 AuthWrapper를 제거한 뒤 로그아웃해도
  // AuthWrapper를 새로 push해 LoginScreen이 항상 표시되도록 한다.
  setLoginRedirectCallback(() {
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthWrapper()),
      (route) => false,
    );
  });

  PerfLog.mark('main.runApp');
  runApp(const MyApp());
  PerfLog.watchFrames();
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => NotificationProvider(),
        ),
        ChangeNotifierProxyProvider<NotificationProvider, UserProvider>(
          create: (_) {
            debugPrint('📦 UserProvider 생성 중...');
            final provider = UserProvider();
            provider.initialize();
            return provider;
          },
          update: (_, notificationProvider, userProvider) {
            userProvider?.setNotificationProvider(notificationProvider);
            return userProvider!;
          },
        ),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => NetworkProvider()),
        ChangeNotifierProvider(create: (_) => BadgeProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            navigatorKey: navigatorKey,
            scaffoldMessengerKey: scaffoldMessengerKey,
            title: 'ALfit(알핏)',
            debugShowCheckedModeBanner: false,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [
              Locale('ko', 'KR'),
              Locale('en', 'US'),
            ],
            theme: themeProvider.theme,
            navigatorObservers: [
              AnalyticsService.observer,
              AppNavigatorObserver.instance, // root top route 추적 — FCM dedupe 전용
            ],
            home: const NetworkBanner(child: SplashScreen()),
          );
        },
      ),
    );
  }
}

/// ✅ 인증 상태에 따라 화면 분기
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool? _isOnboardingCompleted;
  bool _checkingOnboarding = false;
  // Firebase Auth 초기 상태 확인 완료 후 true → 이후 isLoading=true(signIn 등)에서
  // LoginScreen을 스피너로 교체하지 않기 위한 가드
  bool _seenNotLoading = false;

  @override
  void initState() {
    super.initState();
    // initState 시점엔 currentUser가 아직 null일 수 있어 roleKey='unknown'으로
    // 잘못된 prefs 키를 읽게 됨. isLoggedIn=true 확인 후 build()에서 호출.
  }

  Future<void> _checkOnboarding() async {
    if (_checkingOnboarding) return;
    _checkingOnboarding = true;
    try {
      final user = context.read<UserProvider>().currentUser;
      // UID 기반 키 사용 — 역할 기반이면 같은 기기의 다른 계정이 플래그를 공유해
      // 신규 가입자가 이전 사용자의 "완료" 상태를 물려받아 온보딩을 건너뛰게 됨
      final uid = user?.uid ?? 'unknown';
      final prefs = await SharedPreferences.getInstance();
      final completed = prefs.getBool('onboarding_completed_$uid') ?? false;
      if (mounted) setState(() => _isOnboardingCompleted = completed);
    } finally {
      _checkingOnboarding = false;
    }
  }

  Future<void> _completeOnboarding() async {
    // prefs 저장 완료 후 setState — 저장 전 리셋 시 _checkOnboarding이 false를 읽어 온보딩 재표시되는 race 방지
    final user = context.read<UserProvider>().currentUser;
    final uid = user?.uid ?? 'unknown';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed_$uid', true);
    // 온보딩 완료 시 TourScreen도 함께 완료 처리 — 내용이 동일해 중복 표시 방지
    final tourKey = (user?.isUser == true) ? TourHelper.userHome : TourHelper.adminHome;
    await TourHelper.markCompleted(tourKey);
    if (mounted) setState(() => _isOnboardingCompleted = true);
  }

  @override
  Widget build(BuildContext context) {
    // 라우팅 결정에 필요한 최소 필드만 구독 — isAdminMode 토글 등 무관한
    // notifyListeners() 호출로 인한 불필요한 AuthWrapper 전체 리빌드 방지
    return Selector<UserProvider, ({bool isLoading, bool isLoggedIn, String? uid, String? role, bool hasHomeRegion, bool isSubAdmin, bool isAdminMode})>(
      selector: (_, p) => (
        isLoading: p.isLoading,
        isLoggedIn: p.isLoggedIn,
        uid: p.currentUser?.uid,
        role: p.currentUser?.roleString,
        // REG-2F: homeRegion 변경 시 AuthWrapper 리빌드 (복구 완료 감지)
        hasHomeRegion: p.currentUser?.homeRegion != null,
        // [PD-01] 하위관리자 모드 전환·복원 시 Shell 반응형 라우팅
        isSubAdmin: p.currentUser?.isSubAdmin ?? false,
        isAdminMode: p.isAdminMode,
      ),
      // [PERF-L4] 라우팅 판정은 그대로 `_routeFor` 가 하고, 결과를 스플래시 이어받기로 감싼다.
      builder: (context, _, __) => _withSplashHandoff(_routeFor(context)),
    );
  }

  /// [PERF-L4] 첫 인증 확인 동안 스플래시(같은 배경)를 보였는가 — 다음 실제 화면이 한 번 페이드로 이어받는다.
  bool _splashHandoffArmed = false;

  /// [PERF] 라우팅 표식 — 화면 종류가 바뀔 때만 한 줄(매 build 출력 0).
  String? _perfLastRoute;

  /// [PERF-L4] 스플래시 → 첫 실제 화면을 **한 번의 페이드**로 잇는다.
  ///   예전: 스플래시(그라데이션) → 그라데이션 스피너 → 흰 스피너 → 홈 뼈대가 끊겨 바뀌었다.
  ///   흰 스피너는 P3 로 없앴고, 남은 '그라데이션 → 홈 뼈대' 끊김을 여기서 잇는다.
  ///   새 최소 대기는 없다 — 실제 화면은 즉시 만들어지고 읽기·입력도 바로 시작한다.
  ///   페이드는 첫 인증 확인 스플래시가 실제로 보였을 때 한 번뿐이고, 이후 화면 전환은 예전처럼 즉시다.
  Widget _withSplashHandoff(Widget routed) {
    if (PerfLog.enabled) {
      final kind = routed.runtimeType.toString();
      if (kind != _perfLastRoute) {
        _perfLastRoute = kind;
        PerfLog.mark('auth.route', () => {'to': kind});
      }
    }
    if (routed is SplashLoadingScreen) return routed;
    final fadeIn = _splashHandoffArmed;
    _splashHandoffArmed = false;
    return SplashHandoff(fadeIn: fadeIn, child: routed);
  }

  Widget _routeFor(BuildContext context) {
        final userProvider = context.read<UserProvider>();
        if (kDebugMode) {
          debugPrint('\n====== AuthWrapper 빌드 시작 ======');
          debugPrint('isLoading: ${userProvider.isLoading}');
          debugPrint('isLoggedIn: ${userProvider.isLoggedIn}');
        }
        
        // Firebase Auth 초기 상태 확인 완료 마킹 (빌드 중 setState 없이 플래그만 업데이트)
        if (!userProvider.isLoading) _seenNotLoading = true;

        // 🔄 초기 로딩 중 (_isOnboardingCompleted이 결정된 이후엔 로딩 스피너를 표시하지 않음)
        // isLoading이 다시 true가 되어도 OnboardingScreen/홈 화면을 유지해야 한다.
        // 그렇지 않으면 OnboardingScreen이 로딩 스피너로 교체됐다가 재생성될 때 페이지가 초기화된다.
        // _seenNotLoading: 초기 인증 확인 완료 후엔 signIn() 중 isLoading=true여도 스피너 불표시
        // (LoginScreen 언마운트 → mounted=false → toast 미표시 방지)
        if (userProvider.isLoading && _isOnboardingCompleted == null && !_seenNotLoading) {
          if (kDebugMode) debugPrint('⏳ 로딩 중...');
          _splashHandoffArmed = true;
          return const SplashLoadingScreen();
        }

        // [R7-P4.4E.11C.0C §14·§24·§25·§36] 삭제가 끝나지 않은 계정은
        //   **어떤 일반 화면보다 먼저** 재개 화면으로 간다.
        //
        //   S2(user 문서 + accountStatus=deleting)와 S3(user 문서 없음 +
        //   tombstone) 둘 다 여기로 온다. 이 분기가 role 라우팅·온보딩·
        //   LoginScreen 보다 앞에 있으므로 deep link 로 들어와도 일반
        //   화면이 먼저 뜨지 않는다.
        if (userProvider.needsDeletionRecovery) {
          if (kDebugMode) debugPrint('🧹 탈퇴 미완료 → 삭제 재개 화면');
          return const _DeletionRecoveryScreen();
        }

        // 🚫 로그인 안됨 (로딩 중이 아닌 경우에만 — 일시적 isLoading=true로 인한 오탐 방지)
        if (!userProvider.isLoggedIn && !userProvider.isLoading) {
          if (kDebugMode) debugPrint('🚫 로그인되지 않음 → AuthStartScreen');
          // 로그아웃 시 온보딩 상태·가드·배너 리셋 (다음 로그인 때 다시 체크)
          if (_isOnboardingCompleted != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _isOnboardingCompleted = null;
                  _checkingOnboarding = false;
                });
              }
            });
          }
          // 토큰 만료·자동 로그아웃 경로에서도 테마가 이전 역할로 남아있지 않도록
          // addPostFrameCallback으로 빌드 완료 후 리셋 (빌드 중 notifyListeners 방지)
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) context.read<ThemeProvider>().reset();
          });
          // [ALFIT-AUTH-KAKAO-ONBOARDING.1] 시작 화면 = 카카오로 시작하기(주) · 아이디로 로그인(보조 → LoginScreen).
          return const AuthStartScreen();
        }

        // ✅ 로그인 됨 - 권한별 화면 분기
        final user = userProvider.currentUser;
        
        if (user == null) {
          if (kDebugMode) debugPrint('⚠️ currentUser가 null → AuthStartScreen');
          return const AuthStartScreen();
        }

        // ✅ 테마 설정 (빌드 완료 후 안전하게 — context 캡처 없이 provider 직접 참조)
        final themeProvider = context.read<ThemeProvider>();
        Future.microtask(() => themeProvider.setRole(user.roleString));

        if (kDebugMode) {
          debugPrint('\n===== 사용자 권한 정보 =====');
          debugPrint('📧 이메일: ${user.email}');
          debugPrint('👤 이름: ${user.name}');
          debugPrint('🎭 역할: ${user.role}');
          debugPrint('🏢 사업장 ID: ${user.businessId}');
          debugPrint('\n📊 권한 체크:');
          debugPrint('  - isSuperAdmin: ${user.isSuperAdmin}');
          debugPrint('  - isBusinessAdmin: ${user.isBusinessAdmin}');
          debugPrint('  - isUser: ${user.isUser}');
          debugPrint('  - isAdmin: ${user.isAdmin}');
          debugPrint('============================\n');
        }

        // 🆕 온보딩 체크
        if (kDebugMode) debugPrint('📚 _isOnboardingCompleted = $_isOnboardingCompleted');
        // [PERF-P3] main 이 미리 연 저장소가 있으면 **이 프레임에** 판정한다 — uid 가 정해진
        //   지금(위 user != null) 그 uid 의 키를 읽는다. 기다릴 것이 없으니 흰 스피너도 없다.
        //   build 안 대입이지만 이 build 가 곧바로 그 값을 쓰고, 로그아웃 분기의 기존 리셋(null)은 그대로다.
        if (_isOnboardingCompleted == null && !_checkingOnboarding) {
          final prefs = PrefsPreload.instanceOrNull;
          if (prefs != null) {
            _isOnboardingCompleted =
                prefs.getBool('onboarding_completed_${user.uid}') ?? false;
          }
        }
        if (_isOnboardingCompleted == null) {
          // 로그아웃 후 재로그인 시 SharedPreferences 재확인
          // _checkingOnboarding 가드: notifyListeners() 중복 발화 시 중복 스케줄 방지
          if (!_checkingOnboarding) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _checkOnboarding();
            });
          }
          // [PERF-P3] 저장소가 아직 열리지 않은 예외 경로 — 흰 스피너 대신 스플래시와 같은 배경.
          return const SplashLoadingScreen();
        }

        if (_isOnboardingCompleted == false && !user.isSuperAdmin) {
          debugPrint('📚 온보딩 미완료 → OnboardingScreen');
          return OnboardingScreen(
            role: user.roleString,
            onComplete: _completeOnboarding,
          );
        }

        // ✅ 권한별 화면 분기 (에러 핸들링 추가)
        try {
          switch (user.role) {
            case UserRole.SUPER_ADMIN:
              debugPrint('🎯 SUPER_ADMIN → AdminHomeScreen으로 이동');
              return const AdminHomeScreen();
            
            case UserRole.BUSINESS_ADMIN:
              debugPrint('🎯 BUSINESS_ADMIN → BusinessAdminShell으로 이동');
              return const BusinessAdminShell();
            
            case UserRole.USER:
              // [ALFIT-AUTH-KAKAO-ONBOARDING.1 · 대표 결정 2026-11-25] 지역 설정 gate 를 없앴다 —
              //   지역이 없어도 홈으로 간다. 홈 상단 「시작 준비」 카드의 첫 줄이 '일할 지역 고르기'이고,
              //   그 줄이 아래 지역 설정 화면(_HomeRegionRecoveryScreen · pushed)을 연다. 일자리 목록은
              //   지역이 없으면 전체 지역을 보여 준다(일자리 탭은 원래 지역 필터 기본값 없음 · 홈 추천은 STATE 0).
              // [PD-01] 하위관리자 + 관리자 모드 저장 상태 → Shell로 복원
              if (user.isSubAdmin && userProvider.isAdminMode) {
                debugPrint('🎯 USER(SubAdmin 관리자 모드) → BusinessAdminShell으로 이동');
                return const BusinessAdminShell();
              }
              // 4탭 네비게이션 루트 — 홈/일자리/일정/MY
              debugPrint('🎯 USER → UserRootScreen으로 이동');
              return const UserRootScreen();
          }
        } catch (e, stackTrace) {
          debugPrint('❌ 화면 전환 중 에러 발생!');
          debugPrint('에러: $e');
          debugPrint('스택: $stackTrace');
          
          // 에러 화면 표시
          // [DU-S094] 예외 원문은 화면에 두지 않는다 — 위 debugPrint 가 남긴다.
          //   사용자에게는 고정 안내만 보인다. 안전 영역 · 좌우 여백 · 큰 글자 스크롤 ·
          //   낱말 단위 줄바꿈(화면 읽기는 원문). 로그아웃 버튼 문구와 동작은 그대로다.
          const routeErrorTitle = '화면을 불러오지 못했어요';
          const routeErrorBody = '일시적인 문제일 수 있어요.\n로그아웃한 뒤 다시 로그인해 주세요.';
          return Scaffold(
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 24),
                    vertical: ResponsiveHelper.spacing(context, 32),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: ResponsiveHelper.spacing(context, 80),
                          height: ResponsiveHelper.spacing(context, 80),
                          decoration: const BoxDecoration(
                            color: AppColors.errorBg,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.error_outline,
                            size: ResponsiveHelper.spacing(context, 40),
                            color: AppColors.errorDark,
                          ),
                        ),
                      ),
                      SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                      Text(
                        TextLayout.keepWords(routeErrorTitle),
                        semanticsLabel: routeErrorTitle,
                        textAlign: TextAlign.center,
                        style: ResponsiveHelper.titleStyle(context,
                            color: AppColors.textPrimary),
                      ),
                      SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                      Text(
                        TextLayout.phrases(routeErrorBody),
                        semanticsLabel: routeErrorBody,
                        textAlign: TextAlign.center,
                        style: ResponsiveHelper.bodyStyle(context,
                            color: AppColors.textSecondary),
                      ),
                      SizedBox(height: ResponsiveHelper.spacing(context, 32)),
                      ElevatedButton(
                        onPressed: () async {
                          await userProvider.signOut();
                        },
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                        // [DU424] 좁은 폭 · 큰 글자에서 '다 / 시'로 끊기지 않게 낱말 단위 줄바꿈(문구 · 화면 읽기 원문 그대로).
                        child: Text(TextLayout.keepWords('로그아웃하고 다시 시도'),
                            semanticsLabel: '로그아웃하고 다시 시도',
                            textAlign: TextAlign.center),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REG-2F: USER homeRegion 복구 화면
// homeRegion == null인 USER (기존 가입자 또는 STEP 3 미완료)에게 지역 선택을 요청.
// homeRegion은 가입 필수 조건 — 건너뛰기(우회) 없음.
// 저장 성공 → refreshCurrentUser() → AuthWrapper 리빌드 → UserRootScreen으로 이동.
// ─────────────────────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────
// [R7-P4.4E.11C.0C §14·§39·§40·§51] 탈퇴 재개 화면.
//
//   삭제가 마지막 Auth 단계에서 멈춘 계정이 들어온다. 일반 Home 을 보여
//   주지도, "계정이 없습니다"로 끝내지도, 완료로 오표시하지도 않는다.
//
//   [§10] 새 삭제 구현을 만들지 않는다 — 같은 pipeline
//   (`deleteAccountWithPassword`: 재인증 → PreData → Applications → Final)을
//   그대로 재개한다. 그래서 일반 탈퇴와 재시도가 서로 다른 cleanup 정책을
//   갖는 일이 없다.
//
//   [§40] 자동 재시도를 넣지 않았다. 이 pipeline 은 민감 작업이라 재인증
//   (비밀번호)을 요구하고(§18 기존 보안 계약 유지), 비밀번호 없이 자동으로
//   돌릴 수 없다. 명시 CTA 하나만 둔다 — 네트워크 실패에서 재시도 storm 도
//   생기지 않는다.
//
//   [§51] 서버가 명시적으로 성공을 말할 때만 완료로 처리한다.
// ─────────────────────────────────────────────────────────────────────────────
class _DeletionRecoveryScreen extends StatefulWidget {
  const _DeletionRecoveryScreen();

  @override
  State<_DeletionRecoveryScreen> createState() => _DeletionRecoveryScreenState();
}

class _DeletionRecoveryScreenState extends State<_DeletionRecoveryScreen> {
  final TextEditingController _pwCtrl = TextEditingController();
  bool _busy = false;
  String? _message;

  // [ALFIT-AUTH-KAKAO-ONBOARDING.1 · 판정280 B280-02] 재확인 방식 — 서버 reauthMethod 가 권위다.
  //   비밀번호가 없는 계정(Auth 이메일 없음 = custom token 카카오 계정)에는 처음부터 비밀번호를 묻지 않는다.
  //   서버가 'kakao_kg' 라고 하면 KG 재확인 화면으로, 'password' 면 아래 기존 비밀번호 재개 그대로.
  bool _kakaoKg = AuthService().currentUser?.email == null;

  @override
  void initState() {
    super.initState();
    AuthService().getDeletionReauthMethod().then((m) {
      if (!mounted || m == null) return;
      setState(() => _kakaoKg = m == 'kakao_kg');
    });
  }

  @override
  void dispose() {
    _pwCtrl.dispose();
    super.dispose();
  }

  Future<void> _resume() async {
    if (_busy) return;
    final pw = _pwCtrl.text;
    if (pw.isEmpty) {
      setState(() => _message = '비밀번호를 입력해주세요.');
      return;
    }
    // [키보드 포커스] Navigator 전환 전 포커스 해제.
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _message = null;
    });
    // [§10] 일반 탈퇴와 **같은** 함수다.
    final err = await AuthService().deleteAccountWithPassword(pw);
    if (!mounted) return;
    if (err == null) {
      // 서버가 명시적으로 성공을 말했다 — 세션은 이미 정리됐다.
      await context.read<UserProvider>().signOut();
      return;
    }
    setState(() {
      _busy = false;
      _message = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final unknown = context.select<UserProvider, bool>(
        (p) => p.deletionRecovery == DeletionRecoveryState.unknown);
    if (_kakaoKg) {
      // 같은 삭제 파이프라인을 KG 증명 뒤에 재개한다(users 문서 없음 · 차단+탈퇴중 포함).
      return DeletionReauthScreen(
        intent: DeletionReauthIntent.resume,
        onDone: () => context.read<UserProvider>().signOut(),
        onSignOut: () => context.read<UserProvider>().signOut(),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.cleaning_services_outlined,
                    size: 48, color: AppColors.warningDark),
                const SizedBox(height: 16),
                const Text('계정 삭제를 마무리하고 있어요',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  unknown
                      ? '이전 탈퇴 처리가 완료됐는지 확인하지 못했습니다.\n'
                          '아래에서 다시 시도해 주세요.'
                      : '이전 탈퇴 처리가 완료되지 않았습니다.\n'
                          '남은 정리를 마치려면 다시 시도해 주세요.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _pwCtrl,
                  obscureText: true,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: '비밀번호',
                    helperText: '본인 확인을 위해 한 번 더 입력합니다',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Text(_message!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.errorDark)),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _busy ? null : _resume,
                  child: _busy
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('다시 시도'),
                ),
                const SizedBox(height: 8),
                // 삭제를 포기할 수는 없지만(§14) 앱을 닫고 나중에 올 수는 있다.
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => context.read<UserProvider>().signOut(),
                  child: const Text('나중에 하기 (로그아웃)'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// [ALFIT-AUTH-KAKAO-ONBOARDING.1 · 대표 결정 2026-11-25] 홈 「시작 준비」 카드의 '일할 지역 고르기' 입구.
///   예전 AuthWrapper 강제 지역 화면을 **누르면 열리는 화면**으로 재사용한다(뒤로 가기 가능 · 저장하면 닫힘).
Future<void> openHomeRegionSetup(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const _HomeRegionRecoveryScreen(pushed: true)),
    );

class _HomeRegionRecoveryScreen extends StatefulWidget {
  const _HomeRegionRecoveryScreen({this.pushed = false});

  /// 홈에서 열었다(뒤로 가기 · 저장 뒤 닫기 · 로그아웃 줄 없음).
  final bool pushed;

  @override
  State<_HomeRegionRecoveryScreen> createState() => _HomeRegionRecoveryScreenState();
}

class _HomeRegionRecoveryScreenState extends State<_HomeRegionRecoveryScreen> {
  bool _isLoading = false;

  /// [E1-CORRECTION-1] 로그아웃 진행 중 — 연속 탭으로 signOut 을 두 번
  ///   부르지 않는다.
  bool _isSigningOut = false;
  UserRegion? _selected;

  /// [E1-CORRECTION-1] 이 화면에서 계정을 끝낼 수 있어야 한다.
  ///
  ///   이 화면은 `AuthWrapper` 가 **루트로** 반환한다 — Navigator 스택이
  ///   비어 있어 뒤로 갈 곳이 없고, AppBar·건너뛰기도 없었다. 그래서
  ///   `homeRegion` 이 없는 계정으로 로그인하면 지역을 저장하기 전까지
  ///   **그 계정에서 빠져나올 방법이 전혀 없었다**(앱 데이터 삭제 외).
  ///
  ///   지역 필수 정책은 그대로 둔다. 건너뛰기도, 기본 지역 자동 저장도
  ///   추가하지 않는다 — 더한 것은 **나가는 문 하나**뿐이다.
  ///   인증 종료는 기존 `UserProvider.signOut()` 을 그대로 쓰고, 화면
  ///   전환은 `AuthWrapper` 가 한다(여기서 라우팅 스택을 건드리지 않는다).
  Future<void> _signOut() async {
    if (_isLoading || _isSigningOut) return;
    setState(() => _isSigningOut = true);
    try {
      await context.read<UserProvider>().signOut();
      // 성공하면 AuthWrapper 가 로그인 화면으로 바꾸며 이 위젯은 사라진다.
    } catch (e) {
      debugPrint('⚠️ 지역 설정 화면 로그아웃 실패: $e');
      if (!mounted) return;
      setState(() => _isSigningOut = false);
      ToastHelper.showError('로그아웃에 실패했어요. 다시 시도해 주세요.');
    }
  }

  Future<void> _pickRegion() async {
    final result = await HomeRegionPickerSheet.show(
      context: context,
      selectedRegion: _selected,
    );
    if (result != null && mounted) {
      setState(() => _selected = result);
    }
  }

  Future<void> _save() async {
    if (_selected == null || _isLoading) return;
    setState(() => _isLoading = true);
    try {
      final up = context.read<UserProvider>();
      final uid = up.currentUser?.uid;
      if (uid != null) {
        await FirestoreService().updateUserDocument(uid, {'homeRegion': _selected!.toMap()});
        if (!mounted) return;
        // refreshCurrentUser → UserProvider notifyListeners → Selector 변화 → AuthWrapper 리빌드
        await up.refreshCurrentUser();
        // 홈에서 열었으면 저장 뒤 닫는다(홈 카드의 지역 줄이 완료로 바뀐다).
        if (widget.pushed && mounted) Navigator.of(context).maybePop();
      }
    } catch (e) {
      if (mounted) ToastHelper.showError('저장에 실패했습니다. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// [DU616b] 표시 글 [shown](TextLayout 처리 뒤)의 낱말 하나라도 [available] 폭 한 줄에 들어가지 않는가 — 화면 글과 같은 글꼴 · 글자 배율로 잰다(표시만).
  static bool _wordTooWide(BuildContext context, String shown, TextStyle style, double available) {
    for (final word in shown.split(' ')) {
      final tp = TextPainter(
        text: TextSpan(text: word, style: DefaultTextStyle.of(context).style.merge(style)),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
        maxLines: 1,
      )..layout();
      final w = tp.width;
      tp.dispose();
      if (w > available) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // [DU-S085] 표시만 바꾼다 — 지역 선택 · 저장 · 로그아웃의 호출과 활성 조건은 그대로다.
    const regionTitle = '주로 일할 지역을 알려주세요';
    const regionBody = '맞춤 일자리 추천에 활용됩니다.\n나중에 MY에서 언제든지 변경할 수 있어요.';
    return Scaffold(
      // 앱 공통 화면 바탕(이전 grey50 #FAFAFA).
      backgroundColor: AppColors.background,
      appBar: widget.pushed
          ? AppBar(
              backgroundColor: AppColors.background,
              foregroundColor: AppColors.textPrimary,
              elevation: 0,
            )
          : null,
      body: SafeArea(
        // [E1-CORRECTION-1] 로그아웃 줄이 늘어난 만큼, 작은 화면·큰 배율에서
        //   주 CTA 나 로그아웃이 잘리지 않도록 스크롤을 허용한다.
        child: SingleChildScrollView(
          // [DU609b] 좌우 여백은 공용 화면 여백(ResponsiveHelper.screenPadding — 폭 360 미만 16 · 그 밖 24)을 따른다. 좁은 화면 · 큰 글자에서 지역 이름 카드 글 칸이 넓어진다.
          padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.screenPadding(context).left, vertical: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 아이콘
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: theme.primaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(Icons.location_on_outlined,
                    color: theme.primaryColor, size: 36),
              ),
              const SizedBox(height: 24),
              // 제목 · 설명 — 낱말 단위 줄바꿈(화면 읽기는 원문). 제목 크기 22 bold 는 그대로.
              Text(
                TextLayout.keepWords(regionTitle),
                semanticsLabel: regionTitle,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                TextLayout.phrases(regionBody),
                semanticsLabel: regionBody,
                style: ResponsiveHelper.bodyStyle(context,
                    color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              // 지역 선택 카드
              // [DU-S085] 눌림 피드백(InkWell)과 버튼 의미를 명시한다. 탭하면 늘 _pickRegion 이다.
              //   안내 글자 · 아이콘은 읽히는 색으로 — 이전 grey400(#BDBDBD)은 흰 카드 위 1.9:1.
              Semantics(
                button: true,
                child: Material(
                  color: AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: _selected != null ? theme.primaryColor : AppColors.border,
                      width: _selected != null ? 1.5 : 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _pickRegion,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      // [DU616b] 큰 글자에서 지역 이름의 가장 긴 낱말이 한 줄 글 칸(지도 아이콘 · 간격 · 꺾쇠를 뺀 폭)에 들어가지 않으면
                      //   지도 아이콘을 글 위로 옮겨 글 칸을 넓힌다 — 낱말 · 전체 이름 · 글 크기 · 누름 동작은 그대로(장부 142 · 판정105 §1-3).
                      child: LayoutBuilder(builder: (context, box) {
                        final regionShown = TextLayout.identity(_selected != null
                            ? '${_selected!.province ?? ''} ${_selected!.city}'.trim()
                            : '지역 선택하기');
                        final regionStyle = ResponsiveHelper.bodyStyle(context,
                            color: _selected != null
                                ? AppColors.textPrimary
                                : AppColors.textSecondary);
                        final mapIcon = Icon(Icons.map_outlined,
                            color: _selected != null
                                ? theme.primaryColor
                                : AppColors.textSecondary);
                        final iconW = IconTheme.of(context).size ?? 24;
                        final iconAbove = _wordTooWide(
                            context, regionShown, regionStyle, box.maxWidth - iconW * 2 - 12);
                        final row = Row(
                          children: [
                            if (!iconAbove) ...[mapIcon, const SizedBox(width: 12)],
                            Expanded(
                              // [DU424] 지역 이름은 낱말 단위로 줄을 바꾸고, 긴 한 낱말은 가운데에서만 끊는다
                              //   (좁은 폭 · 큰 글자에서 '세종특별자치 / 시' 음절 끊김). 화면 읽기는 원문이다.
                              child: Text(
                                regionShown,
                                semanticsLabel: _selected != null
                                    ? '${_selected!.province ?? ''} ${_selected!.city}'.trim()
                                    : '지역 선택하기',
                                style: regionStyle,
                              ),
                            ),
                            const Icon(Icons.chevron_right,
                                color: AppColors.textTertiary),
                          ],
                        );
                        if (!iconAbove) return row;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [mapIcon, const SizedBox(height: 8), row],
                        );
                      }),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // 저장 버튼
              // [DU-S085] 높이 고정 52 대신 최소 52 — 글자를 키우면 버튼도 함께 커진다.
              //   비활성 글자색은 공용 주 버튼(CommonWidgets.primaryButton)과 같은 grey500.
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_selected == null || _isLoading) ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primaryColor,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    disabledBackgroundColor: AppColors.grey200,
                    disabledForegroundColor: AppColors.grey500,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      // [DU424] 큰 글자에서 '시작하 / 기'로 끊기지 않게 낱말 단위 줄바꿈(문구 · 화면 읽기 원문 그대로).
                      : Text(TextLayout.keepWords(widget.pushed ? '저장하기' : '저장하고 시작하기'),
                          semanticsLabel: widget.pushed ? '저장하기' : '저장하고 시작하기',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              // homeRegion은 가입 필수 조건 — 건너뛰기 없음
              //
              // [E1-CORRECTION-1] 다만 **계정을 끝낼 길**은 있어야 한다.
              //   건너뛰기가 아니라 로그아웃이다 — 지역을 저장하지 않으면
              //   이 화면으로 다시 돌아온다. 주 CTA 아래 보조 행동으로 둔다.
              if (!widget.pushed) const SizedBox(height: 12),
              if (!widget.pushed) TextButton(
                onPressed: (_isLoading || _isSigningOut) ? null : _signOut,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  // [DU-S085] 터치 최소 48(이전 44).
                  minimumSize: const Size.fromHeight(48),
                ),
                child: _isSigningOut
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('로그아웃',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 위젯 빌드 에러 발생 시 표시되는 사용자 친화적 화면 (릴리즈 모드 전용)
class _AppErrorWidget extends StatelessWidget {
  final FlutterErrorDetails details;
  const _AppErrorWidget({required this.details});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: AppColors.errorDark),
              const SizedBox(height: 16),
              const Text(
                '오류가 발생했습니다',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '잠시 후 다시 시도해주세요.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // 이전 화면으로 돌아가기
                    if (Navigator.canPop(context)) {
                      Navigator.pop(context);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('돌아가기'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}