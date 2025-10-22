import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'firebase_options.dart';
import 'providers/user_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/user/user_home_screen.dart';
import 'screens/admin/admin_home_screen.dart';
import 'utils/constants.dart';
import 'models/user_model.dart'; // ✅ UserRole 사용을 위해 추가
import 'screens/admin/business_admin_home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Firebase 초기화
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 한국어 날짜 포맷 초기화
  await initializeDateFormatting('ko_KR', null);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => UserProvider()..initialize(),
        ),
      ],
      child: MaterialApp(
        title: '스마트 물류센터 인력 관리',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          primaryColor: const Color(AppConstants.primaryColor),
          scaffoldBackgroundColor: Colors.grey[50],
          appBarTheme: AppBarTheme(
            backgroundColor: const Color(AppConstants.primaryColor),
            elevation: 0,
            centerTitle: true,
            iconTheme: const IconThemeData(color: Colors.white),
            titleTextStyle: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(AppConstants.primaryColor),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
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

        // ✅ 로그인 됨 - 3단계 권한 분기
        final user = userProvider.currentUser;
        
        if (user == null) {
          return const LoginScreen();
        }

        // ✅ 권한별 화면 분기
        switch (user.role) {
          case UserRole.SUPER_ADMIN:
            // 슈퍼관리자 → 관리자 홈 (추후 슈퍼관리자 전용 화면 추가 가능)
            return const AdminHomeScreen();
          case UserRole.BUSINESS_ADMIN:
            return const BusinessAdminHomeScreen();  // ⭐ 사업장 관리자 (새로 추가!) 
          
          case UserRole.USER:
            // 일반 사용자 → 사용자 홈
            return const UserHomeScreen();
          
          default:
            // 알 수 없는 권한 → 로그인 화면
            return const LoginScreen();
        }
      },
    );
  }
}