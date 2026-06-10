import 'package:flutter/material.dart';
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
      color: AppColors.infoDark,
      bgColor: AppColors.infoBg,
      tag: '알핏 소개',
      title: '단기·장기 일자리,\n한 번에 찾고 바로 지원',
      description: '식품·제조·서비스 등 다양한 업종의\n공고를 원하는 날짜와 시간에 맞게 찾아보세요.',
      features: [
        _Feature(Icons.calendar_month_rounded, '원하는 날짜·시간 선택', AppColors.infoDark),
        _Feature(Icons.touch_app_rounded, '지원 한 번으로 완료', AppColors.infoDark),
        _Feature(Icons.notifications_outlined, '확정 시 알림 즉시 수신', AppColors.infoDark),
      ],
    ),
    _OnboardingPage(
      icon: Icons.assignment_turned_in_rounded,
      color: AppColors.purple,
      bgColor: AppColors.purpleBg,
      tag: '지원 & 계약',
      title: '지원부터 계약까지\n앱 하나로 완결',
      description: '공고 지원 → 관리자 확정 → 계약서 서명까지\n모든 과정이 앱 안에서 이루어져요.',
      features: [
        _Feature(Icons.search_rounded, '조건에 맞는 공고 검색', AppColors.purple),
        _Feature(Icons.check_circle_outline, '관리자 확정 후 알림 수신', AppColors.purple),
        _Feature(Icons.draw_outlined, '전자 계약서 앱에서 서명', AppColors.purple),
      ],
    ),
    _OnboardingPage(
      icon: Icons.location_on_rounded,
      color: AppColors.successDark,
      bgColor: AppColors.successBg,
      tag: 'GPS 출퇴근',
      title: '근무지 근처에서\n앱으로 출퇴근 체크',
      description: 'GPS로 근무지 근처에서 버튼 하나로 출퇴근 체크!\n조출·지각·조퇴 여부가 자동으로 기록돼요.',
      features: [
        _Feature(Icons.my_location_rounded, '근무지 GPS 인증으로 간편 체크', AppColors.successDark),
        _Feature(Icons.auto_awesome_rounded, '조출·지각·조퇴 자동 감지 및 기록', AppColors.successDark),
        _Feature(Icons.edit_note_rounded, '시간이 틀리면 수정 요청 가능', AppColors.successDark),
      ],
    ),
    _OnboardingPage(
      icon: Icons.trending_up_rounded,
      color: AppColors.warningDarkest,
      bgColor: AppColors.warningBg,
      tag: '급여 & 신뢰도',
      title: '급여 명세서 확인,\n신뢰도로 기회 높이기',
      description: '임금명세서를 앱에서 바로 확인하고\n성실한 출근으로 신뢰도를 쌓으세요.',
      features: [
        _Feature(Icons.receipt_long_outlined, '임금명세서 앱에서 확인·저장', AppColors.warningDarkest),
        _Feature(Icons.check_circle_rounded, '정상 출근 +1점', AppColors.success),
        _Feature(Icons.cancel_rounded, '노쇼 -3점 (채용 기회 감소)', AppColors.error),
      ],
    ),
  ];

  static const _adminPages = [
    _OnboardingPage(
      icon: Icons.admin_panel_settings_rounded,
      color: AppColors.infoDark,
      bgColor: AppColors.infoBg,
      tag: '알핏 관리자',
      title: '채용부터 급여까지\n원스톱 관리',
      description: 'TO 등록 → 지원자 확정 → 계약서 → 출퇴근 → 급여까지\n모든 인력 관리를 하나의 앱에서.',
      features: [
        _Feature(Icons.flash_on_rounded, '빠른 TO 등록 & 공고 관리', AppColors.infoDark),
        _Feature(Icons.description_outlined, '전자 계약서 자동 발송', AppColors.infoDark),
        _Feature(Icons.account_balance_wallet_outlined, '급여 확정 & 송금 관리', AppColors.infoDark),
      ],
    ),
    _OnboardingPage(
      icon: Icons.post_add_rounded,
      color: AppColors.purple,
      bgColor: AppColors.purpleBg,
      tag: 'TO 등록',
      title: '공고 등록 3단계,\n지원자가 모여요',
      description: '업종·날짜·시간·인원만 입력하고 공개하면\n지원자가 자동으로 모입니다.',
      features: [
        _Feature(Icons.looks_one_rounded, '업종·날짜·시간·인원 설정', AppColors.purple),
        _Feature(Icons.looks_two_rounded, '공고 공개 → 지원자 수신', AppColors.purple),
        _Feature(Icons.looks_3_rounded, '지원자 확정 → 계약서 발송', AppColors.purple),
      ],
    ),
    _OnboardingPage(
      icon: Icons.people_alt_rounded,
      color: AppColors.amber,
      bgColor: AppColors.warningBg,
      tag: '지원자 & 계약서',
      title: '지원자 확정하면\n계약서 자동 발송',
      description: '원하는 지원자를 확정하면 전자 계약서가\n자동으로 발송되어 앱에서 서명을 받아요.',
      features: [
        _Feature(Icons.how_to_reg_rounded, '지원자 확정 한 번에 처리', AppColors.amber),
        _Feature(Icons.description_outlined, '전자 계약서 자동 발송', AppColors.amber),
        _Feature(Icons.verified_outlined, '서명 완료 후 계약 확정', AppColors.amber),
      ],
    ),
    _OnboardingPage(
      icon: Icons.how_to_reg_rounded,
      color: AppColors.infoDark,
      bgColor: AppColors.infoBg,
      tag: '당일 출퇴근 관리',
      title: '당일 출퇴근 현황을\n실시간으로 확인',
      description: '출퇴근 현황을 한눈에 보고 시간 조정·마감을\n손쉽게 처리할 수 있어요.',
      features: [
        _Feature(Icons.fact_check_rounded, '실시간 출퇴근 현황 모니터링', AppColors.infoDark),
        _Feature(Icons.tune_rounded, '시간 조정 & 원본 기록 보존', AppColors.infoDark),
        _Feature(Icons.picture_as_pdf_outlined, '당일명단 PDF 내보내기', AppColors.infoDark),
      ],
    ),
    _OnboardingPage(
      icon: Icons.payments_outlined,
      color: AppColors.successDark,
      bgColor: AppColors.successBg,
      tag: '급여 & 리뷰',
      title: '급여 확정부터\n송금 관리까지',
      description: '공제 설정 후 급여를 확정하면 임금명세서가\n자동으로 공개되고, 엑셀로 일괄 이체해요.',
      features: [
        _Feature(Icons.receipt_long_outlined, '급여 확정 & 임금명세서 공개', AppColors.successDark),
        _Feature(Icons.download_outlined, '은행 이체용 엑셀 내보내기', AppColors.successDark),
        _Feature(Icons.star_rate_rounded, '월간 리뷰로 인재 평가', AppColors.successDark),
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

  void _completeOnboarding() {
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
                      style: ResponsiveHelper.tinyStyle(
                        context,
                        color: page.color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _completeOnboarding,
                    child: Text(
                      '건너뛰기',
                      style: ResponsiveHelper.bodyStyle(
                        context,
                        color: AppColors.grey500,
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
              fontSize: ResponsiveHelper.titleStyle(context).fontSize! * 1.5,
              fontWeight: FontWeight.w800,
              color: AppColors.grey900,
              height: 1.25,
            ),
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 10)),

          // 설명
          Text(
            page.description,
            style: ResponsiveHelper.bodyStyle(
              context,
              color: AppColors.grey500,
            ).copyWith(height: 1.6),
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
                      style: ResponsiveHelper.bodyStyle(
                        context,
                        color: AppColors.grey800,
                        fontWeight: FontWeight.w500,
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
                        style: ResponsiveHelper.bodyStyle(context).copyWith(
                          color: Colors.white,
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
