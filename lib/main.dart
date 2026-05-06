import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import 'services/fcm_service.dart';
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

  // 앱 종료 상태 FCM 백그라운드 핸들러 등록 (Firebase 초기화 전에 먼저 등록)
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await initializeDateFormatting('ko_KR', null);
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Firestore 캐시 설정 (서버 우선)
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );

    // Crashlytics: Flutter 프레임워크 에러 자동 수집
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    // Crashlytics: Dart 비동기 에러 자동 수집
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };

    debugPrint('✅ Firebase 초기화 완료');
  } catch (e) {
    debugPrint('❌ Firebase 초기화 에러: $e');
  }
  // ✅ PDF 한글 폰트 백그라운드 프리로드 (await 없이 - 병렬 실행)
  AttendanceListPdf.preloadFonts();
  
  // 🔔 FCM에 Navigator Key 전달
  FCMService().setNavigatorKey(navigatorKey);
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(  // 🔥 변경!
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
  // TODO: 테스트 완료 후 아래 줄을 "bool? _isOnboardingCompleted;" 로 되돌리고
  //       initState에서 _checkOnboarding(); 호출 복구
  bool? _isOnboardingCompleted = false;
  bool _emailBannerShown = false;

  @override
  void initState() {
    super.initState();
    // _checkOnboarding(); // TODO: 테스트 완료 후 주석 해제
  }

  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final completed = prefs.getBool('onboarding_completed') ?? false;
    if (mounted) {
      setState(() => _isOnboardingCompleted = completed);
    }
  }

  void _completeOnboarding() {
    setState(() => _isOnboardingCompleted = true);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UserProvider>(
      builder: (context, userProvider, _) {
        debugPrint('\n====== AuthWrapper 빌드 시작 ======');
        debugPrint('isLoading: ${userProvider.isLoading}');
        debugPrint('isLoggedIn: ${userProvider.isLoggedIn}');
        
        // 🔄 로딩 중
        if (userProvider.isLoading) {
          debugPrint('⏳ 로딩 중...');
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
          debugPrint('🚫 로그인되지 않음 → LoginScreen');
          // 로그아웃 시 온보딩 상태 리셋 (다음 로그인 때 다시 보이도록)
          if (_isOnboardingCompleted != false) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _isOnboardingCompleted = false);
            });
          }
          return const LoginScreen();
        }

        // ✅ 로그인 됨 - 권한별 화면 분기
        final user = userProvider.currentUser;
        
        if (user == null) {
          debugPrint('⚠️ currentUser가 null → LoginScreen');
          return const LoginScreen();
        }
        
        // ✅ 테마 설정 (빌드 완료 후 안전하게)
        Future.microtask(() {
          if (context.mounted) {
            context.read<ThemeProvider>().setRole(user.roleString);
          }
        });

        // 🎭 사용자 정보 출력
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

        // 🆕 온보딩 체크
        debugPrint('📚 _isOnboardingCompleted = $_isOnboardingCompleted');
        if (_isOnboardingCompleted == null) {
          // 온보딩 상태 로딩 중
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
                    color: Colors.orange),
                backgroundColor: const Color(0xFFFFF8E1),
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
                        style: TextStyle(color: Colors.grey)),
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
                            color: Colors.orange,
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
                    color: Colors.red,
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
                    style: const TextStyle(color: Colors.red),
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