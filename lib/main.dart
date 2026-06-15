import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_colors.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
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
import 'models/core/user_model.dart';
import 'screens/auth/login_screen.dart';
import 'screens/user/user_home_screen.dart';
import 'screens/super_admin/super_admin_home_screen.dart';
import 'screens/business_admin/business_admin_home_screen.dart';
import 'screens/common/splash_screen.dart';
import 'screens/common/onboarding_screen.dart';
import 'screens/common/settings_screen.dart';
import 'utils/attendance_list_pdf.dart';
import 'utils/wage_calculator.dart';
import 'services/fcm_service.dart';
import 'services/insurance_rate_service.dart';
import 'services/analytics_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/common/network_banner.dart';

/// 앱이 완전히 종료된 상태에서 FCM 메시지 수신 시 호출되는 최상위 핸들러
/// (반드시 main() 바깥 최상위 함수여야 함 — Flutter 요구사항)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('🔔 [백그라운드] FCM 수신: ${message.notification?.title}');
}

/// 🔔 전역 Navigator Key (FCM 알림 클릭 시 화면 이동용)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// 전역 ScaffoldMessenger Key (어디서든 SnackBar 표시용)
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
    await AppVersionService.init();

    // Firebase App Check — API 키 무단 사용 방지
    // 릴리즈: Play Integrity(Android) / DeviceCheck(iOS) 사용
    // 디버그: DebugProvider (Firebase 콘솔에서 디버그 토큰 등록 필요)
    await FirebaseAppCheck.instance.activate(
      androidProvider: kDebugMode
          ? AndroidProvider.debug
          : AndroidProvider.playIntegrity,
      appleProvider: kDebugMode
          ? AppleProvider.debug
          : AppleProvider.deviceCheck,
    );

    // Firestore 캐시 설정 (서버 우선)
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: 100 * 1024 * 1024, // 100MB 상한 (무제한 → 저장공간 보호)
    );

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

    debugPrint('✅ Firebase 초기화 완료');
  } catch (e) {
    debugPrint('❌ Firebase 초기화 에러: $e');
  }
  // ✅ PDF 한글 폰트 백그라운드 프리로드 (await 없이 - 병렬 실행)
  AttendanceListPdf.preloadFonts();

  // 최저시급·보험료율 캐시 로드 (병렬, 실패해도 로컬 백업 사용)
  WageCalculator.loadMinimumWages();
  InsuranceRateService.loadRates();

  // 🔔 FCM에 Navigator Key 전달
  FCMService().setNavigatorKey(navigatorKey);
  
  runApp(const MyApp());
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
            navigatorObservers: [AnalyticsService.observer],
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
  bool _emailBannerShown = false;
  bool _checkingOnboarding = false;

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
      final roleKey = user?.roleString ?? 'unknown';
      final prefs = await SharedPreferences.getInstance();
      final completed = prefs.getBool('onboarding_completed_$roleKey') ?? false;
      if (mounted) setState(() => _isOnboardingCompleted = completed);
    } finally {
      _checkingOnboarding = false;
    }
  }

  Future<void> _completeOnboarding() async {
    // await 전 즉시 설정 — notifyListeners() rebuild 시 OnboardingScreen 재표시 방지
    if (mounted) setState(() => _isOnboardingCompleted = true);
    final user = context.read<UserProvider>().currentUser;
    final roleKey = user?.roleString ?? 'unknown';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed_$roleKey', true);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UserProvider>(
      builder: (context, userProvider, _) {
        if (kDebugMode) {
          debugPrint('\n====== AuthWrapper 빌드 시작 ======');
          debugPrint('isLoading: ${userProvider.isLoading}');
          debugPrint('isLoggedIn: ${userProvider.isLoggedIn}');
        }
        
        // 🔄 로딩 중
        if (userProvider.isLoading) {
          if (kDebugMode) debugPrint('⏳ 로딩 중...');
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('로딩 중...'),
                ],
              ),
            ),
          );
        }

        // 🚫 로그인 안됨
        if (!userProvider.isLoggedIn) {
          if (kDebugMode) debugPrint('🚫 로그인되지 않음 → LoginScreen');
          // 로그아웃 시 온보딩 상태·가드 리셋 (다음 로그인 때 다시 체크)
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
          return const LoginScreen();
        }

        // ✅ 로그인 됨 - 권한별 화면 분기
        final user = userProvider.currentUser;
        
        if (user == null) {
          if (kDebugMode) debugPrint('⚠️ currentUser가 null → LoginScreen');
          return const LoginScreen();
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
        if (_isOnboardingCompleted == null) {
          // 로그아웃 후 재로그인 시 SharedPreferences 재확인
          // _checkingOnboarding 가드: notifyListeners() 중복 발화 시 중복 스케줄 방지
          if (!_checkingOnboarding) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _checkOnboarding();
            });
          }
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (_isOnboardingCompleted == false) {
          debugPrint('📚 온보딩 미완료 → OnboardingScreen');
          return OnboardingScreen(
            role: user.roleString,
            onComplete: _completeOnboarding,
          );
        }

        // 이메일 미인증 배너 (로그인 후 최초 1회)
        if (!user.isEmailVerified && !_emailBannerShown) {
          _emailBannerShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            scaffoldMessengerKey.currentState?.showMaterialBanner(
              MaterialBanner(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                leading: const Icon(Icons.mail_outline,
                    color: AppColors.warning),
                backgroundColor: AppColors.warningBg,
                content: const Text(
                  '이메일 인증을 완료하면 더 많은 기능을 이용할 수 있어요',
                  style: TextStyle(fontSize: 13),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      scaffoldMessengerKey.currentState
                          ?.hideCurrentMaterialBanner();
                    },
                    child: const Text('나중에',
                        style: TextStyle(color: AppColors.grey500)),
                  ),
                  TextButton(
                    onPressed: () {
                      scaffoldMessengerKey.currentState
                          ?.hideCurrentMaterialBanner();
                      navigatorKey.currentState?.push(
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                    },
                    child: const Text('인증하기',
                        style: TextStyle(
                            color: AppColors.warning,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            );
          });
        }
        if (user.isEmailVerified && _emailBannerShown) {
          _emailBannerShown = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            scaffoldMessengerKey.currentState?.hideCurrentMaterialBanner();
          });
        }

        // ✅ 권한별 화면 분기 (에러 핸들링 추가)
        try {
          switch (user.role) {
            case UserRole.SUPER_ADMIN:
              debugPrint('🎯 SUPER_ADMIN → AdminHomeScreen으로 이동');
              return const AdminHomeScreen();
            
            case UserRole.BUSINESS_ADMIN:
              debugPrint('🎯 BUSINESS_ADMIN → BusinessAdminHomeScreen으로 이동');
              return const BusinessAdminHomeScreen();
            
            case UserRole.USER:
              // 하위 관리자이고 관리자 모드인 경우 → 관리자 홈
              if (user.isSubAdmin && userProvider.isAdminMode) {
                debugPrint('🎯 SUB_ADMIN(관리자 모드) → BusinessAdminHomeScreen으로 이동');
                return const BusinessAdminHomeScreen();
              }
              debugPrint('🎯 USER → UserHomeScreen으로 이동');
              return const UserHomeScreen();
          }
        } catch (e, stackTrace) {
          debugPrint('❌ 화면 전환 중 에러 발생!');
          debugPrint('에러: $e');
          debugPrint('스택: $stackTrace');
          
          // 에러 화면 표시
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 64,
                    color: AppColors.error,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '화면을 불러오는 중 오류가 발생했습니다',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    e.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.error),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () async {
                      await userProvider.signOut();
                    },
                    child: const Text('로그아웃하고 다시 시도'),
                  ),
                ],
              ),
            ),
          );
        }
      },
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
              const Icon(Icons.error_outline, size: 64, color: AppColors.error),
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
                style: TextStyle(color: AppColors.grey500),
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
                    backgroundColor: AppColors.info,
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