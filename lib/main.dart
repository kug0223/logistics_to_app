import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'providers/user_provider.dart';
import 'models/user_model.dart';

// ⭐ 화면 import - 모두 정확히 추가!
import 'screens/auth/login_screen.dart';
import 'screens/user/user_home_screen.dart';
import 'screens/admin/admin_home_screen.dart';
import 'screens/admin/business_admin_home_screen.dart';

// ⚠️ 만약 위 import에서 에러가 난다면 경로를 확인하세요!
// 예: 'screens/user/...' 대신 'screens/users/...' 일 수도 있음

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => UserProvider()..initialize(),
      child: MaterialApp(
        title: '물류 TO 관리',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
        ),
        home: const AuthWrapper(),
      ),
    );
  }
}

/// 인증 상태에 따라 화면 분기
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<UserProvider>(
      builder: (context, userProvider, _) {
        // 로딩 중
        if (userProvider.isLoading) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        // 로그인 안됨
        if (!userProvider.isLoggedIn) {
          return const LoginScreen();
        }

        // ✅ 로그인 됨 - 권한별 화면 분기
        final user = userProvider.currentUser;
        
        if (user == null) {
          return const LoginScreen();
        }

        print('🔍 [main.dart] 현재 사용자 role: ${user.role}');  // 디버그용

        // ✅ 권한별 화면 분기
        switch (user.role) {
          case UserRole.SUPER_ADMIN:
            print('✅ [main.dart] SUPER_ADMIN → AdminHomeScreen');
            return const AdminHomeScreen();
          
          case UserRole.BUSINESS_ADMIN:
            print('✅ [main.dart] BUSINESS_ADMIN → BusinessAdminHomeScreen');
            return const BusinessAdminHomeScreen();
          
          case UserRole.USER:
            print('✅ [main.dart] USER → UserHomeScreen');
            return const UserHomeScreen();
          
          default:
            // 알 수 없는 권한 → 로그인 화면으로
            print('⚠️ [main.dart] 알 수 없는 role → LoginScreen');
            return const LoginScreen();
        }
      },
    );
  }
}