import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'providers/user_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/notification_provider.dart';
import 'models/core/user_model.dart';

// ⭐ 화면 import - 반드시 정확한 경로 확인!
import 'screens/auth/login_screen.dart';
import 'screens/user/user_home_screen.dart';
import 'screens/super_admin/super_admin_home_screen.dart';
import 'screens/business_admin/business_admin_home_screen.dart';
import 'screens/common/splash_screen.dart';
// PDF 폰트 프리로드
import 'utils/attendance_list_pdf.dart';



void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 🔥 타임존 디버깅 (확인 후 삭제)
  await initializeDateFormatting('ko_KR', null);
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    
    // ✅ Firestore 캐시 설정 (서버 우선!)
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,  // 캐시는 유지
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
    
    print('✅ Firebase 초기화 완료');
  } catch (e) {
    print('❌ Firebase 초기화 에러: $e');
  }
  // ✅ PDF 한글 폰트 백그라운드 프리로드 (await 없이 - 병렬 실행)
  AttendanceListPdf.preloadFonts();
  
  
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
            print('📦 UserProvider 생성 중...');
            final provider = UserProvider();
            provider.initialize();
            return provider;
          },
          update: (_, notificationProvider, userProvider) {
            userProvider?.setNotificationProvider(notificationProvider);
            return userProvider!;
          },
        ),
        ChangeNotifierProvider(
          create: (_) => ThemeProvider(),
        ),
      ],
      child: Consumer<ThemeProvider>(  // 🔥 추가!
        builder: (context, themeProvider, child) {
          return MaterialApp(
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
            theme: themeProvider.theme,  // 🔥 변경!
            home: const SplashScreen(),
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
  @override
  Widget build(BuildContext context) {
    return Consumer<UserProvider>(
      builder: (context, userProvider, _) {
        print('\n====== AuthWrapper 빌드 시작 ======');
        print('isLoading: ${userProvider.isLoading}');
        print('isLoggedIn: ${userProvider.isLoggedIn}');
        
        // 🔄 로딩 중
        if (userProvider.isLoading) {
          print('⏳ 로딩 중...');
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
          print('🚫 로그인되지 않음 → LoginScreen');
          return const LoginScreen();
        }

        // ✅ 로그인 됨 - 권한별 화면 분기
        final user = userProvider.currentUser;
        
        if (user == null) {
          print('⚠️ currentUser가 null → LoginScreen');
          return const LoginScreen();
        }
        
        // ✅ 테마 설정 (빌드 완료 후 안전하게)
        Future.microtask(() {
          if (context.mounted) {
            context.read<ThemeProvider>().setRole(user.roleString);
          }
        });

        // 🎭 사용자 정보 출력
        print('\n===== 사용자 권한 정보 =====');
        print('📧 이메일: ${user.email}');
        print('👤 이름: ${user.name}');
        print('🎭 역할: ${user.role}');
        print('🏢 사업장 ID: ${user.businessId}');
        print('\n📊 권한 체크:');
        print('  - isSuperAdmin: ${user.isSuperAdmin}');
        print('  - isBusinessAdmin: ${user.isBusinessAdmin}');
        print('  - isUser: ${user.isUser}');
        print('  - isAdmin: ${user.isAdmin}');
        print('============================\n');

        // ✅ 권한별 화면 분기 (에러 핸들링 추가)
        try {
          switch (user.role) {
            case UserRole.SUPER_ADMIN:
              print('🎯 SUPER_ADMIN → AdminHomeScreen으로 이동');
              return const AdminHomeScreen();
            
            case UserRole.BUSINESS_ADMIN:
              print('🎯 BUSINESS_ADMIN → BusinessAdminHomeScreen으로 이동');
              return const BusinessAdminHomeScreen();
            
            case UserRole.USER:
              print('🎯 USER → UserHomeScreen으로 이동');
              return const UserHomeScreen();
            
            default:
              print('⚠️ 알 수 없는 role: ${user.role} → LoginScreen');
              return const LoginScreen();
          }
        } catch (e, stackTrace) {
          print('❌ 화면 전환 중 에러 발생!');
          print('에러: $e');
          print('스택: $stackTrace');
          
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