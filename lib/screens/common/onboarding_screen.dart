import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/responsive_helper.dart';
import '../../theme/app_colors.dart';

class OnboardingScreen extends StatefulWidget {
  final String role;
  final VoidCallback onComplete;

  const OnboardingScreen({
    super.key,
    required this.role,
    required this.onComplete,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  late AnimationController _animController;
  late Animation<double> _scaleAnim;

  List<_OnboardingPage> get _pages =>
      (widget.role == 'BUSINESS_ADMIN' || widget.role == 'SUPER_ADMIN')
          ? _adminPages
          : _userPages;

  static const _userPages = [
    _OnboardingPage(
      icon: Icons.rocket_launch_rounded,
      color: Color(0xFF1976D2),
      bgColor: Color(0xFFE3F2FD),
      tag: '알핏 소개',
      title: '물류센터 일자리,\n쉽고 빠르게',
      description: '원하는 날짜와 시간에 맞는 일자리를\n한 번에 찾고 바로 지원하세요.',
      features: [
        _Feature(Icons.calendar_month_rounded, '원하는 날짜·시간 선택', AppColors.infoDark),
        _Feature(Icons.touch_app_rounded, '간편한 지원 한 번으로 완료', AppColors.infoDark),
        _Feature(Icons.business_rounded, '다양한 물류센터 파트너사', AppColors.infoDark),
      ],
    ),
    _OnboardingPage(
      icon: Icons.trending_up_rounded,
      color: Color(0xFFE65100),
      bgColor: Color(0xFFFFF3E0),
      tag: '신뢰도 시스템',
      title: '성실함이 곧\n경쟁력이에요',
      description: '신뢰도 점수가 높을수록\n채용 확률이 높아집니다.',
      features: [
        _Feature(Icons.check_circle_rounded, '정상 출근 +1점', AppColors.success),
        _Feature(Icons.schedule_rounded, '지각 -1점', AppColors.warning),
        _Feature(Icons.cancel_rounded, '노쇼 -3점 이상', AppColors.error),
      ],
    ),
    _OnboardingPage(
      icon: Icons.location_on_rounded,
      color: Color(0xFF2E7D32),
      bgColor: Color(0xFFE8F5E9),
      tag: '출퇴근 체크',
      title: 'GPS로\n출퇴근 확인',
      description: '근무지 근처에서 앱으로 체크하면\n자동으로 기록됩니다.',
      features: [
        _Feature(Icons.login_rounded, '출근: 시작 10분 전부터 가능', AppColors.successDark),
        _Feature(Icons.logout_rounded, '퇴근: 종료 시간 이후 가능', AppColors.successDark),
        _Feature(Icons.gps_fixed_rounded, '위치 확인 필수', AppColors.successDark),
      ],
    ),
  ];

  static const _adminPages = [
    _OnboardingPage(
      icon: Icons.admin_panel_settings_rounded,
      color: Color(0xFF1976D2),
      bgColor: Color(0xFFE3F2FD),
      tag: '알핏 관리자',
      title: '인력 모집,\n이제 간편하게',
      description: '몇 번의 터치만으로 인력을 모집하고\n실시간으로 관리하세요.',
      features: [
        _Feature(Icons.flash_on_rounded, '빠른 TO 등록', AppColors.infoDark),
        _Feature(Icons.people_rounded, '실시간 지원자 확인', AppColors.infoDark),
        _Feature(Icons.dashboard_rounded, '체계적인 인력 관리', AppColors.infoDark),
      ],
    ),
    _OnboardingPage(
      icon: Icons.post_add_rounded,
      color: Color(0xFF6A1B9A),
      bgColor: Color(0xFFF3E5F5),
      tag: 'TO 등록',
      title: '3단계로\n인력 공고 완성',
      description: '날짜·시간·인원만 입력하면\n지원자가 자동으로 모여요.',
      features: [
        _Feature(Icons.looks_one_rounded, '날짜·시간 선택', AppColors.purple),
        _Feature(Icons.looks_two_rounded, '필요 인원 입력', AppColors.purple),
        _Feature(Icons.looks_3_rounded, '공개하면 끝!', AppColors.purple),
      ],
    ),
    _OnboardingPage(
      icon: Icons.star_rate_rounded,
      color: Color(0xFFF57C00),
      bgColor: Color(0xFFFFF3E0),
      tag: '리뷰 시스템',
      title: '월간 리뷰로\n인재를 평가하세요',
      description: '작성 후 3일 뒤 지원자에게 공개되며\n상세 코멘트는 관리자끼리만 공유해요.',
      features: [
        _Feature(Icons.star_rounded, '점수·태그는 지원자에게 공개', AppColors.warningDark),
        _Feature(Icons.lock_rounded, '코멘트는 관리자끼리만 공유', AppColors.warningDark),
        _Feature(Icons.event_available_rounded, '같은 지원자는 월 1회', AppColors.warningDark),
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnim = CurvedAnimation(parent: _animController, curve: Curves.elasticOut);
    _animController.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _completeOnboarding();
    }
  }

  Future<void> _completeOnboarding() async {
    // TODO: 테스트 완료 후 아래 주석 해제
    // final prefs = await SharedPreferences.getInstance();
    // await prefs.setBool('onboarding_completed', true);
    widget.onComplete();
  }

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);
    _animController.reset();
    _animController.forward();
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages[_currentPage];

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // 상단 바 (건너뛰기)
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 8),
                vertical: ResponsiveHelper.spacing(context, 4),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 페이지 태그 뱃지
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: page.bgColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      page.tag,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: page.color,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _completeOnboarding,
                    child: Text(
                      '건너뛰기',
                      style: TextStyle(
                        color: AppColors.grey500,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 일러스트 영역
            Expanded(
              flex: 5,
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                itemCount: _pages.length,
                itemBuilder: (context, index) =>
                    _buildIllustration(context, _pages[index]),
              ),
            ),

            // 콘텐츠 + 버튼 영역
            Expanded(
              flex: 6,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _buildContent(context, page),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIllustration(BuildContext context, _OnboardingPage page) {
    return ScaleTransition(
      scale: _scaleAnim,
      child: Container(
        margin: EdgeInsets.all(ResponsiveHelper.spacing(context, 24)),
        decoration: BoxDecoration(
          color: page.bgColor,
          borderRadius: BorderRadius.circular(32),
        ),
        child: Stack(
          children: [
            // 배경 장식 원 (대)
            Positioned(
              top: -30,
              right: -30,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: page.color.withValues(alpha: 0.08),
                ),
              ),
            ),
            // 배경 장식 원 (소)
            Positioned(
              bottom: 20,
              left: 20,
              child: Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: page.color.withValues(alpha: 0.06),
                ),
              ),
            ),
            // 중앙 아이콘
            Center(
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: page.color.withValues(alpha: 0.2),
                      blurRadius: 32,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Icon(
                  page.icon,
                  size: 64,
                  color: page.color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, _OnboardingPage page) {
    return Padding(
      key: ValueKey(_currentPage),
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 28),
        0,
        ResponsiveHelper.spacing(context, 28),
        ResponsiveHelper.spacing(context, 16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 제목
          Text(
            page.title,
            style: TextStyle(
              fontSize: ResponsiveHelper.spacing(context, 28),
              fontWeight: FontWeight.w800,
              color: AppColors.grey900,
              height: 1.25,
            ),
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 10)),

          // 설명
          Text(
            page.description,
            style: TextStyle(
              fontSize: 15,
              color: AppColors.grey500,
              height: 1.6,
            ),
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 20)),

          // 기능 항목
          ...page.features.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: f.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(f.icon, size: 17, color: f.color),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      f.label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.grey800,
                      ),
                    ),
                  ],
                ),
              )),

          const Spacer(),

          // 인디케이터 + 버튼
          Row(
            children: [
              // 인디케이터
              Row(
                children: List.generate(_pages.length, (i) {
                  final active = i == _currentPage;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.only(right: 6),
                    width: active ? 24 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: active ? page.color : AppColors.grey300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),

              const Spacer(),

              // 다음/시작 버튼
              GestureDetector(
                onTap: _nextPage,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 14),
                  decoration: BoxDecoration(
                    color: page.color,
                    borderRadius: BorderRadius.circular(50),
                    boxShadow: [
                      BoxShadow(
                        color: page.color.withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _currentPage == _pages.length - 1 ? '시작하기' : '다음',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 17,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        ],
      ),
    );
  }
}

class _OnboardingPage {
  final IconData icon;
  final Color color;
  final Color bgColor;
  final String tag;
  final String title;
  final String description;
  final List<_Feature> features;

  const _OnboardingPage({
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.tag,
    required this.title,
    required this.description,
    required this.features,
  });
}

class _Feature {
  final IconData icon;
  final String label;
  final Color color;

  const _Feature(this.icon, this.label, this.color);
}

Future<bool> isOnboardingCompleted() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool('onboarding_completed') ?? false;
}

Future<void> resetOnboarding() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('onboarding_completed');
}
