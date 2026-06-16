import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../main.dart' show AuthWrapper;
import '../../services/app_version_service.dart';
import '../../utils/responsive_helper.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnim = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    _scaleAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    _controller.forward();

    Future.delayed(const Duration(milliseconds: 2000), () async {
      if (!mounted) return;
      final canProceed = await _checkVersion();
      if (mounted && canProceed) _navigateToHome();
    });
  }

  /// 버전 체크 후 홈으로 진행 가능 여부 반환.
  /// forceUpdate이면 false(진입 영구 차단), 그 외 true.
  Future<bool> _checkVersion() async {
    final result = await AppVersionService.check();
    if (!mounted) return true;

    if (result == VersionCheckResult.forceUpdate) {
      _showForceUpdateDialog();
      return false;
    } else if (result == VersionCheckResult.recommendUpdate) {
      await _showRecommendUpdateDialog();
    }
    return true;
  }

  void _showForceUpdateDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final rawUrl = Theme.of(ctx).platform == TargetPlatform.iOS
            ? FirebaseRemoteConfig.instance.getString('update_url_ios')
            : FirebaseRemoteConfig.instance.getString('update_url_android');
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('업데이트 필요'),
            content: const Text('앱을 최신 버전으로 업데이트해야 합니다.\n업데이트 후 다시 실행해주세요.'),
            actions: [
              TextButton(
                onPressed: rawUrl.isEmpty
                    ? null
                    : () async {
                        final url = Uri.parse(rawUrl);
                        if (await canLaunchUrl(url)) {
                          await launchUrl(url, mode: LaunchMode.externalApplication);
                        }
                      },
                child: const Text('스토어로 이동'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showRecommendUpdateDialog() async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('업데이트 안내'),
        content: const Text('새 버전이 출시됐습니다. 업데이트를 권장합니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('나중에'),
          ),
          TextButton(
            onPressed: () async {
              // rawUrl은 Navigator.pop() 이전에 ctx에서 읽어야 한다.
              // pop 이후 ctx는 unmounted 상태가 되므로 Theme.of(ctx) 호출 순서 주의.
              final rawUrl = Theme.of(ctx).platform == TargetPlatform.iOS
                  ? FirebaseRemoteConfig.instance.getString('update_url_ios')
                  : FirebaseRemoteConfig.instance.getString('update_url_android');
              Navigator.pop(ctx);
              if (rawUrl.isEmpty) return;
              final url = Uri.parse(rawUrl);
              if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
            },
            child: const Text('업데이트'),
          ),
        ],
      ),
    );
  }

  void _navigateToHome() {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const AuthWrapper(),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).primaryColor,
              Theme.of(context).colorScheme.secondary,
            ],
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: ScaleTransition(
              scale: _scaleAnim,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 앱 아이콘
                  ClipRRect(
                    borderRadius: BorderRadius.circular(26),
                    child: Image.asset(
                      'assets/icons/app_icon.png',
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // 앱 이름
                  Text(
                    'ALfit',
                    style: TextStyle(
                      fontSize: ResponsiveHelper.titleStyle(context).fontSize! * 2.2,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 1.5,
                      height: 1,
                    ),
                  ),

                  const SizedBox(height: 8),

                  // 태그라인
                  Text(
                    '나에게 딱 맞는 알바 매칭',
                    style: ResponsiveHelper.bodyStyle(
                      context,
                      color: Colors.white.withValues(alpha: 0.7),
                    ).copyWith(
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
