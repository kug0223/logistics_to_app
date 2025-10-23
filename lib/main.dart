import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart'; 
import 'firebase_options.dart';
import 'providers/user_provider.dart';
import 'models/user_model.dart';

// ⭐ 화면 import - 반드시 정확한 경로 확인!
import 'screens/auth/login_screen.dart';
import 'screens/user/user_home_screen.dart';
import 'screens/admin/admin_home_screen.dart';
import 'screens/admin/business_admin_home_screen.dart';



void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('✅ Firebase 초기화 완료');
  } catch (e) {
    print('❌ Firebase 초기화 에러: $e');
  }
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        print('📦 UserProvider 생성 중...');
        final provider = UserProvider();
        provider.initialize();
        return provider;
      },
      child: MaterialApp(
        title: '물류 TO 관리',
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
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
        ),
        home: const AuthWrapper(),
      ),
    );
  }
}

/// ✅ 인증 상태에 따라 화면 분기
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

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