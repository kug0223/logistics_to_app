import 'dart:math' as math;
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../main.dart' show AuthWrapper;
import '../../services/app_version_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _entryController;
  late AnimationController _pulseController;
  late Animation<double> _logoFade;
  late Animation<Offset> _logoSlide;
  late Animation<double> _taglineFade;

  // 애니메이션과 버전 체크를 병렬 실행 — 둘 다 끝나면 바로 이동
  late final Future<bool> _versionFuture;

  @override
  void initState() {
    super.initState();
    // 네이티브 스플래시 해제 — SplashScreen 위젯이 렌더링될 준비가 됐을 때 호출
    // main()의 FlutterNativeSplash.preserve()와 쌍을 이루며,
    // 두 화면이 동일한 파란 배경이므로 시각적 점프 없이 자연스럽게 전환됨
    FlutterNativeSplash.remove();

    _entryController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    )..repeat();

    _logoFade = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.0, 0.65, curve: Curves.easeOut),
    );
    _logoSlide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.0, 0.65, curve: Curves.easeOutCubic),
    ));
    _taglineFade = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.4, 1.0, curve: Curves.easeOut),
    );

    // 버전 체크: 애니메이션(750ms)과 동시에 시작
    // 네트워크가 느릴 경우 최대 1초만 추가 대기 후 통과 처리
    _versionFuture = _checkVersion().timeout(
      const Duration(milliseconds: 500),
      onTimeout: () => true,
    );

    _entryController.forward().whenComplete(() {
      // 애니메이션 완료 후 버전 체크 결과 대기 (이미 끝났으면 즉시)
      _versionFuture.then((canProceed) {
        if (mounted && canProceed) _navigateToHome();
      }).catchError((e) {
        debugPrint('⚠️ [Splash] 버전 체크 실패, 홈으로 진행: $e');
        if (mounted) _navigateToHome();
      });
    });
  }

  Future<bool> _checkVersion() async {
    final result = await AppVersionService.check();
    if (!mounted) return false;

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
        transitionDuration: const Duration(milliseconds: 250),
      ),
    );
  }

  @override
  void dispose() {
    _entryController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _SplashBody(
        child: Column(
          children: [
            const Spacer(flex: 5),
            SlideTransition(
              position: _logoSlide,
              child: FadeTransition(
                opacity: _logoFade,
                child: const _SplashLogo(),
              ),
            ),
            const SizedBox(height: 20),
            FadeTransition(
              opacity: _taglineFade,
              child: const _SplashTagline(),
            ),
            const Spacer(flex: 4),
            // SizedBox(height: 22) 고정 — SplashLoadingScreen 스피너와 높이 통일
            // 높이 차이가 있으면 Spacer가 재계산되어 콘텐츠가 위로 밀림
            SizedBox(
              height: 22,
              child: Center(
                child: FadeTransition(
                  opacity: _taglineFade,
                  child: _PulseDots(controller: _pulseController),
                ),
              ),
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}

/// AuthWrapper 초기 로딩 중 흰 화면 깜빡임 방지 — SplashScreen과 동일 배경
class SplashLoadingScreen extends StatelessWidget {
  const SplashLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: _SplashBody(
        child: Column(
          children: [
            Spacer(flex: 5),
            _SplashLogo(),
            SizedBox(height: 20),
            _SplashTagline(),
            Spacer(flex: 4),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                color: Color(0x99FFFFFF),
                strokeWidth: 2,
              ),
            ),
            SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}

// ── 공유 하위 위젯 ─────────────────────────────────────────────────────────────

class _SplashBody extends StatelessWidget {
  final Widget child;
  const _SplashBody({required this.child});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [theme.primaryColor, theme.colorScheme.secondary],
        ),
      ),
      child: Stack(
        children: [
          // 상단 우측 빛번짐
          Positioned(
            top: -size.height * 0.12,
            right: -size.width * 0.15,
            child: Container(
              width: size.width * 0.75,
              height: size.width * 0.75,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.07),
              ),
            ),
          ),
          // 하단 좌측 빛번짐
          Positioned(
            bottom: -size.height * 0.08,
            left: -size.width * 0.2,
            child: Container(
              width: size.width * 0.65,
              height: size.width * 0.65,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),
          // 콘텐츠: Positioned.fill로 Column이 전체 영역을 채워 수직·수평 중앙정렬
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _SplashLogo extends StatelessWidget {
  const _SplashLogo();

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        const Text(
          'ALfit',
          style: TextStyle(
            fontSize: 58,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 4,
            height: 1,
          ),
        ),
        // 홈 헤더와 동일한 브랜드 점
        Positioned(
          right: -12,
          top: 5,
          child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
        ),
      ],
    );
  }
}

class _SplashTagline extends StatelessWidget {
  const _SplashTagline();

  @override
  Widget build(BuildContext context) {
    return Text(
      '나에게 딱 맞는 알바 매칭',
      style: TextStyle(
        fontSize: 14,
        color: Colors.white.withValues(alpha: 0.75),
        fontWeight: FontWeight.w400,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _PulseDots extends StatelessWidget {
  final AnimationController controller;
  const _PulseDots({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final phase = (controller.value - i * 0.25) % 1.0;
          final opacity = math.sin(phase * math.pi).clamp(0.0, 1.0);
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.2 + opacity * 0.6),
            ),
          );
        }),
      ),
    );
  }
}
