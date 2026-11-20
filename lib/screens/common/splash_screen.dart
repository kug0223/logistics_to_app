import 'dart:async';
import 'dart:math' as math;
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../main.dart' show AuthWrapper;
import '../../utils/dialog_helper.dart';
import '../../utils/navigation_key.dart';
import '../../services/app_version_service.dart';
import 'forced_update_screen.dart';

class SplashScreen extends StatefulWidget {
  /// [VERSION-GATE] 테스트가 실제 Navigation 까지 돌릴 수 있게 판정만 주입한다.
  ///   production 은 null — `AppVersionService.evaluate()` 를 그대로 쓴다.
  final Future<VersionGateResult> Function()? versionEvaluator;

  const SplashScreen({super.key, this.versionEvaluator});

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

    // [VERSION-GATE] 버전 판정과 애니메이션을 **함께** 시작하되,
    //   판정이 끝나기 전에는 어디로도 가지 않는다.
    //
    //   예전에는 `timeout(500ms, onTimeout: () => true)` 였다. Remote Config
    //   fetch 는 콜드 스타트에서 그보다 느린 일이 흔하고, 그때마다 **확인되지
    //   않은 채 홈으로 들어갔다.** 늦게 끝난 판정은 `mounted` 가 false 라
    //   차단 화면을 띄우지도 못했다 — 게이트가 사실상 없었다.
    //
    //   이제 타임아웃은 "통과"가 아니라 **UNKNOWN** 이다. 무한 대기도 아니다.
    _entryController.forward();
    _runGate();
  }

  /// 늦게 도착한 이전 요청이 지금 상태를 덮지 않도록 세는 표.
  int _gateSeq = 0;
  bool _navigated = false;

  Future<void> _runGate() async {
    final seq = ++_gateSeq;
    final evaluate = widget.versionEvaluator ?? AppVersionService.evaluate;

    VersionGateResult result;
    try {
      result = await evaluate().timeout(
        _gateTimeout,
        onTimeout: () => const VersionGateResult(
          status: VersionGateStatus.unknown,
          source: VersionPolicySource.localDefault,
          fromCache: true,
          currentVersion: '',
          minVersion: '',
        ),
      );
    } catch (e) {
      // 예외도 "최신"이 아니다 — 모르는 것은 모른다고 말한다.
      debugPrint('⚠️ [Splash] 버전 판정 실패: $e');
      result = const VersionGateResult(
        status: VersionGateStatus.unknown,
        source: VersionPolicySource.localDefault,
        fromCache: true,
        currentVersion: '',
        minVersion: '',
      );
    }

    if (!mounted || seq != _gateSeq) return;

    // 애니메이션이 아직이면 조금 기다렸다 보낸다(시각적 점프 방지).
    if (_entryController.status != AnimationStatus.completed) {
      await _entryController.forward().orCancel.catchError((_) => 0.0);
      if (!mounted || seq != _gateSeq) return;
    }

    if (result.status == VersionGateStatus.supported) {
      if (result.recommendUpdate) await _showRecommendUpdateDialog();
      if (!mounted || seq != _gateSeq) return;
      _navigateToHome();
      return;
    }
    _showGateScreen(result);
  }

  /// Remote Config `fetchTimeout` 이 10초다 — 그보다 조금 길게 기다린 뒤
  ///   UNKNOWN 으로 넘긴다. 무기한 로딩을 만들지 않는다.
  static const Duration _gateTimeout = Duration(seconds: 12);

  /// 차단 화면으로 **라우트를 대체**한다. 다이얼로그가 아니다 —
  ///   다이얼로그는 뒤의 화면이 살아 있어 다른 push 가 그 위로 올라온다.
  void _showGateScreen(VersionGateResult result) {
    if (_navigated) return;
    _navigated = true;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ForcedUpdateScreen(
          result: result,
          // [DU313 r3] 새 판정을 차단 화면에 돌려준다 — 막힌 그대로면 화면이 그 판정(업데이트 필요 / 확인 실패)으로 바뀐다.
          //   forceFetch 는 Remote Config 설정 간격(release 1시간)을 따른다 — 바로 새 정책을 받는다고 보증하지 않는다.
          onRetry: () async {
            final again = await AppVersionService.evaluate(forceFetch: true);
            if (again.status != VersionGateStatus.supported) return again;
            if (!navigatorKey.currentState!.mounted) return again;
            navigatorKey.currentState!.pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const AuthWrapper()),
              (route) => false,
            );
            return again;
          },
        ),
      ),
    );
  }

  Future<void> _showRecommendUpdateDialog() async {
    // [DU316] 원시 AlertDialog → 공용 확인창 셸. 예전 창은 Material 기본 보라빛 면 · 24 보통 제목 · 글자 버튼 둘이라
    //   앱의 다른 확인창(흰 면 · 아이콘 머리 · brand 주 버튼)과 달랐고, 320·2.0 에서 버튼이 세로로 쌓이고
    //   '출시됐습 / 니다' 로 끊겼다. 문구 · 버튼 이름 · 동작은 그대로다(바깥 탭 · 나중에 = false → 홈).
    final update = await DialogHelper.showConfirm(
      context,
      title: '업데이트 안내',
      message: '새 버전이 출시됐습니다. 업데이트를 권장합니다.',
      confirmText: '업데이트',
      cancelText: '나중에',
      icon: Icons.system_update_alt,
    );
    if (!update || !mounted) return;
    final rawUrl = Theme.of(context).platform == TargetPlatform.iOS
        ? FirebaseRemoteConfig.instance.getString('update_url_ios')
        : FirebaseRemoteConfig.instance.getString('update_url_android');
    if (rawUrl.isEmpty) return;
    // 예전처럼 스토어 열기를 기다리지 않는다 — 창이 닫히면 _runGate 가 곧바로 홈으로 간다.
    unawaited(() async {
      final url = Uri.parse(rawUrl);
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    }());
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
