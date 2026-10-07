// lib/screens/common/onboarding_screen.dart

import 'package:flutter/material.dart';
import '../../utils/responsive_helper.dart';
import '../../theme/app_colors.dart';

/// 신규 사용자 온보딩 화면
///
/// ## 지원자 (USER / WORKER) — 3페이지
/// - Page 1: 날짜 선택 → 일자리 (캘린더 + 공고카드 미니 UI)
/// - Page 2: 지원 → 확정 → 계약 (상태 플로우 미니 UI)
/// - Page 3: 출근하기 + 급여 확인 (근무카드 미니 UI)
///
/// 지원자 온보딩 변경 사항:
/// - 4페이지 → 3페이지 (GPS 전용 페이지·신뢰도 페이지 제거)
/// - 상단 카테고리 Chip 제거, 건너뛰기만 유지
/// - CTA 색상 ALfit Blue 통일 (페이지별 색 변동 제거)
/// - 아이콘 일러스트 → ALfit UX 미니 UI 일러스트
///
/// ## 관리자 (BUSINESS_ADMIN / SUPER_ADMIN) — 5페이지
/// 기존 아이콘 방식 유지
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

  bool get _isUser =>
      widget.role != 'BUSINESS_ADMIN' && widget.role != 'SUPER_ADMIN';

  List<_OnboardingPage> get _pages => _isUser ? _userPages : _adminPages;

  // ── 지원자 온보딩 3페이지 ─────────────────────────────────────────
  static const _userPages = [
    _OnboardingPage(
      title: '일하고 싶은 날을\n직접 선택하세요',
      description: '원하는 날짜를 선택하면\n그날 지원할 수 있는 일자리를 확인할 수 있어요.',
      features: [
        _Feature(Icons.calendar_month_rounded, '날짜를 선택하고'),
        _Feature(Icons.info_outline, '근무 조건을 확인하고'),
        _Feature(Icons.send_rounded, '원하는 일자리에 지원'),
      ],
    ),
    _OnboardingPage(
      title: '지원한 일자리의\n진행 상황을 한눈에',
      description: '지원부터 근무 확정까지\n진행 상황을 앱에서 확인할 수 있어요.',
      features: [
        _Feature(Icons.description_outlined, '여러 일자리에 지원'),
        _Feature(Icons.notifications_outlined, '확정되면 바로 알림'),
        _Feature(Icons.draw_outlined, '근로계약서도 앱에서 서명'),
      ],
    ),
    _OnboardingPage(
      title: '출근부터 급여 확인까지\nALfit에서 관리하세요',
      description: '확정된 근무 일정을 확인하고\n출퇴근 기록과 급여 내역을 관리할 수 있어요.',
      features: [
        _Feature(Icons.calendar_today_outlined, '확정된 근무 일정 확인'),
        _Feature(Icons.access_time_rounded, '간편한 출퇴근 체크'),
        _Feature(Icons.receipt_long_outlined, '급여 · 임금명세서 확인'),
      ],
    ),
  ];

  // ── 관리자 온보딩 5페이지 (기존 유지) ────────────────────────────
  // ── 관리자 온보딩 3페이지 ─────────────────────────────────────────
  //
  // [R7-ONBOARDING.1] 예전에는 기능 5페이지였다 — 공고·계약서·출퇴근·급여·
  //   리뷰를 차례로 광고했다. 처음 들어온 사람이 아직 쓸 수 없는 기능까지
  //   먼저 소개했고, 정작 **이 제품이 무엇이고 지금 무엇을 해야 하는지**는
  //   한 줄도 없었다.
  //
  //   첫 화면이 할 일은 셋이다.
  //     1) 이 제품이 무엇을 맞춰 주는가
  //     2) 지원과 확정이 왜 다른 말인가 — 이 앱의 규칙 대부분이 여기서 나온다
  //     3) 그래서 첫 공고 전에 왜 준비가 필요한가
  //
  //   준비 상태 자체는 여기서 세지 않는다. 그건 홈의 canonical readiness 가
  //   한다. 온보딩이 끝났다는 말은 "봤다" 이지 "준비됐다" 가 아니다.
  static const _adminPages = [
    _OnboardingPage(
      icon: Icons.calendar_month_rounded,
      color: AppColors.infoDark,
      bgColor: AppColors.infoBg,
      tag: '알핏',
      title: '필요한 날,\n필요한 사람을 맞춥니다',
      description: '사람이 필요한 날과 일하고 싶은 날을 맞춥니다.\n'
          '확정된 근무는 계약·일정·근태·급여까지 이어집니다.',
      features: [],
    ),
    _OnboardingPage(
      icon: Icons.handshake_rounded,
      color: AppColors.purple,
      bgColor: AppColors.purpleBg,
      tag: '지원과 확정',
      title: '지원은 관심,\n확정은 약속입니다',
      description: '지원은 그 날 일하고 싶다는 관심 표현이에요.\n'
          '확정하는 순간 약속이 되고 계약서가 만들어집니다.',
      features: [
        _Feature(Icons.waving_hand_outlined, '지원 — 아직 약속이 아니에요'),
        _Feature(Icons.verified_outlined, '확정 — 계약·일정·급여로 이어져요'),
      ],
    ),
    _OnboardingPage(
      icon: Icons.checklist_rounded,
      color: AppColors.successDark,
      bgColor: AppColors.successBg,
      tag: '첫 공고',
      title: '첫 공고 전에\n기본 준비가 필요해요',
      description: '확정하면 바로 계약서가 만들어지기 때문에\n'
          '사업장·업무·계약서 양식·사업주 인감이 먼저 있어야 합니다.\n'
          '무엇이 남았는지는 홈에서 알려드려요.',
      features: [],
    ),
  ];

  // ── 생명주기 ─────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnim =
        CurvedAnimation(parent: _animController, curve: Curves.elasticOut);
    _animController.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _animController.dispose();
    super.dispose();
  }

  // ── 이벤트 ──────────────────────────────────────────────────────

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

  void _completeOnboarding() => widget.onComplete();

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);
    _animController.reset();
    _animController.forward();
  }

  // ── 빌드 ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final page = _pages[_currentPage];

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // 상단: 건너뛰기만 (카테고리 Chip 제거)
            _buildTopBar(),
            // 일러스트 영역 — PageView로 스와이프 지원
            Expanded(
              flex: 5,
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                itemCount: _pages.length,
                itemBuilder: (context, index) =>
                    _buildIllustrationForIndex(context, index),
              ),
            ),
            // 콘텐츠 + 인디케이터 + CTA
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

  // ── 상단 바 ──────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      child: Align(
        alignment: Alignment.centerRight,
        child: TextButton(
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
      ),
    );
  }

  // ── 일러스트 디스패치 ─────────────────────────────────────────────

  Widget _buildIllustrationForIndex(BuildContext context, int index) {
    final Widget child;
    if (_isUser) {
      child = switch (index) {
        0 => _buildUserIllust0(context),
        1 => _buildUserIllust1(context),
        _ => _buildUserIllust2(context),
      };
    } else {
      child = _buildAdminIllust(context, _pages[index]);
    }
    // [R7-ONBOARDING.1] 일러스트가 상자를 넘지 않게 한다.
    //
    //   지원자 일러스트는 달력·흐름도처럼 글자를 품은 구성이라 배율을 키우면
    //   그만큼 커진다. 320dp × 2.0 에서 554px 넘쳤다. 글자를 줄이거나 눌러
    //   담지 않는다 — 넘치는 만큼 **세로로 스크롤**해서 보게 한다.
    //   (PageView 는 가로로 넘기므로 세로 스크롤과 부딪히지 않는다.)
    return ScaleTransition(
      scale: _scaleAnim,
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: child,
      ),
    );
  }

  // ── 관리자 일러스트 (기존 아이콘 원형 방식) ──────────────────────

  Widget _buildAdminIllust(BuildContext context, _OnboardingPage page) {
    final color = page.color ?? AppColors.infoDark;
    final bgColor = page.bgColor ?? AppColors.infoBg;

    return Container(
      margin: EdgeInsets.all(ResponsiveHelper.spacing(context, 24)),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(32),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -30,
            right: -30,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.08),
              ),
            ),
          ),
          Positioned(
            bottom: 20,
            left: 20,
            child: Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.06),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.2),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Icon(page.icon ?? Icons.info, size: 64, color: color),
            ),
          ),
        ],
      ),
    );
  }

  // ── 지원자 일러스트 1: 캘린더 + 공고카드 ─────────────────────────

  Widget _buildUserIllust0(BuildContext context) {
    return Container(
      margin: EdgeInsets.all(ResponsiveHelper.spacing(context, 20)),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 14)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 미니 캘린더
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 월 헤더
                const Row(
                  children: [
                    Icon(Icons.calendar_today_rounded,
                        size: 11, color: AppColors.infoDark),
                    SizedBox(width: 4),
                    Text('8월',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        )),
                    SizedBox(width: 4),
                    Text('2026',
                        style:
                            TextStyle(fontSize: 9, color: AppColors.grey400)),
                  ],
                ),
                const SizedBox(height: 8),
                // 요일 레이블
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children:
                      ['일', '월', '화', '수', '목', '금', '토'].map((d) {
                    return SizedBox(
                      width: 24,
                      child: Text(
                        d,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: d == '일'
                              ? AppColors.error
                              : (d == '토'
                                  ? AppColors.infoDark
                                  : AppColors.grey400),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 4),
                // 1주차: 2~8 (8월 2026 기준 일요일=2일)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [2, 3, 4, 5, 6, 7, 8]
                      .map((d) => _calDay(d, selected: false))
                      .toList(),
                ),
                const SizedBox(height: 2),
                // 2주차: 9~15 (14일 선택)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [9, 10, 11, 12, 13, 14, 15]
                      .map((d) => _calDay(d, selected: d == 14))
                      .toList(),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // 공고 카드 (달력 → 카드 수직 구조로 관계 읽힘, 화살표 불필요)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: const Border(
                left: BorderSide(color: AppColors.infoDark, width: 3),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // 사업장 썸네일 — 이미지 플레이스홀더 느낌
                Container(
                  width: 36,
                  height: 30,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF1E88E5), Color(0xFF1565C0)],
                    ),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(
                    Icons.business_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ALfit 물류센터',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 1),
                      Text(
                        '09:00 ~ 18:00 · 8시간',
                        style:
                            TextStyle(fontSize: 9, color: AppColors.grey500),
                      ),
                    ],
                  ),
                ),
                const Text(
                  '120,000원',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.infoDark,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 캘린더 단일 날짜 셀
  Widget _calDay(int day, {required bool selected}) {
    return SizedBox(
      width: 24,
      height: 22,
      child: Center(
        child: Container(
          width: selected ? 22 : null,
          height: selected ? 22 : null,
          decoration: selected
              ? const BoxDecoration(
                  color: AppColors.infoDark,
                  shape: BoxShape.circle,
                )
              : null,
          alignment: Alignment.center,
          child: Text(
            '$day',
            style: TextStyle(
              fontSize: 10,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? Colors.white : AppColors.grey600,
            ),
          ),
        ),
      ),
    );
  }

  // ── 지원자 일러스트 2: 지원 상태 플로우 ──────────────────────────

  Widget _buildUserIllust1(BuildContext context) {
    return Container(
      margin: EdgeInsets.all(ResponsiveHelper.spacing(context, 20)),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 18),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _flowItem(
            title: '지원 완료',
            subtitle: 'ALfit 물류센터',
            dotBg: AppColors.infoDark,
            dotIconColor: Colors.white,
            badge: '검토 중',
            badgeBg: AppColors.infoBg,
            badgeColor: AppColors.infoDark,
          ),
          _flowConnector(),
          _flowItem(
            title: '근무 확정',
            subtitle: '8.14(금) 09:00~18:00',
            dotBg: AppColors.infoDark,
            dotIconColor: Colors.white,
            badge: '확정',
            badgeBg: AppColors.infoDark,
            badgeColor: Colors.white,
          ),
          _flowConnector(),
          _flowItem(
            title: '계약서 서명',
            subtitle: '근로계약서 · 앱에서 서명',
            dotBg: AppColors.successBg,
            dotIconColor: AppColors.successDark,
            badge: '서명완료',
            badgeBg: AppColors.successBg,
            badgeColor: AppColors.successDark,
          ),
        ],
      ),
    );
  }

  Widget _flowItem({
    required String title,
    required String subtitle,
    required Color dotBg,
    required Color dotIconColor,
    required String badge,
    required Color badgeBg,
    required Color badgeColor,
  }) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(color: dotBg, shape: BoxShape.circle),
          child: Icon(Icons.check_rounded, size: 13, color: dotIconColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 9,
                          color: AppColors.grey500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: badgeColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _flowConnector() {
    return Container(
      height: 14,
      width: 2,
      margin: const EdgeInsets.only(left: 13),
      color: AppColors.infoDark,
    );
  }

  // ── 지원자 일러스트 3: 오늘 근무 + 급여 카드 ─────────────────────

  Widget _buildUserIllust2(BuildContext context) {
    return Container(
      margin: EdgeInsets.all(ResponsiveHelper.spacing(context, 20)),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 오늘 근무 카드
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '오늘 근무',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.infoDark,
                      ),
                    ),
                    Text(
                      '8.14 금요일',
                      style:
                          TextStyle(fontSize: 9, color: AppColors.grey400),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'ALfit 물류센터',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  '09:00 ~ 18:00 · 일급 120,000원',
                  style: TextStyle(fontSize: 9.5, color: AppColors.grey500),
                ),
                const SizedBox(height: 8),
                // 출근하기 버튼 (터치 불가 — 일러스트 전용)
                Container(
                  width: double.infinity,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.infoDark,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.access_time_rounded,
                          size: 12, color: Colors.white),
                      SizedBox(width: 5),
                      Text(
                        '출근하기',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // 급여 카드
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.credit_card_outlined,
                            size: 11, color: AppColors.grey400),
                        SizedBox(width: 4),
                        Text(
                          '이번 달 급여',
                          style: TextStyle(
                              fontSize: 10, color: AppColors.grey500),
                        ),
                      ],
                    ),
                    Text(
                      '480,000원',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Divider(height: 1, color: AppColors.borderLight),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Row(
                      children: [
                        Icon(Icons.receipt_long_outlined,
                            size: 11, color: AppColors.grey400),
                        SizedBox(width: 4),
                        Text(
                          '임금명세서',
                          style: TextStyle(
                              fontSize: 10, color: AppColors.grey500),
                        ),
                      ],
                    ),
                    Text(
                      '확인 →',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: AppColors.infoDark,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 콘텐츠 영역 (제목·설명·기능·인디케이터·CTA) ───────────────────

  Widget _buildContent(BuildContext context, _OnboardingPage page) {
    // 지원자: ALfit Blue 통일 / 관리자: 페이지별 색상
    final ctaColor =
        _isUser ? AppColors.infoDark : (page.color ?? AppColors.infoDark);
    final featureColor =
        _isUser ? AppColors.infoDark : (page.color ?? AppColors.infoDark);
    final featureBg =
        _isUser ? AppColors.infoBg : (page.bgColor ?? AppColors.infoBg);

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
          // [R7-ONBOARDING.1] 본문은 스크롤하고 CTA 는 고정한다.
          //
          //   예전에는 제목·설명·기능 목록 뒤에 `Spacer()` 를 두고 그 아래에
          //   인디케이터와 버튼을 붙였다. 높이가 고정이라 글자 배율을 키우면
          //   본문이 상자를 넘쳤고(320dp × 2.0), 버튼이 화면 밖으로 밀렸다.
          //   글을 줄이는 대신 **읽을 자리를 스크롤로 돌려준다** — 시작하기
          //   버튼은 어떤 배율에서도 제자리에 있어야 한다.
          Expanded(
            child: SingleChildScrollView(
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
                        color: featureBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(f.icon, size: 17, color: featureColor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        f.label,
                        style: ResponsiveHelper.bodyStyle(
                          context,
                          color: AppColors.grey800,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
                ],
              ),
            ),
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 12)),

          // 페이지 인디케이터 + CTA 버튼
          Row(
            children: [
              // 인디케이터 (활성: ctaColor, 비활성: grey300)
              Row(
                children: List.generate(_pages.length, (i) {
                  final active = i == _currentPage;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.only(right: 6),
                    width: active ? 24 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: active ? ctaColor : AppColors.grey300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),

              const Spacer(),

              // 다음 / ALfit 시작하기 버튼
              GestureDetector(
                onTap: _nextPage,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 14),
                  decoration: BoxDecoration(
                    color: ctaColor,
                    borderRadius: BorderRadius.circular(50),
                    boxShadow: [
                      BoxShadow(
                        color: ctaColor.withValues(alpha: 0.12),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _currentPage == _pages.length - 1
                            ? 'ALfit 시작하기'
                            : '다음',
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

// ── 데이터 클래스 ────────────────────────────────────────────────────

class _OnboardingPage {
  final String title;
  final String description;
  final List<_Feature> features;

  /// 관리자 전용 필드 — 제네릭 아이콘 일러스트에 사용
  /// 지원자 페이지는 미니 UI 일러스트를 사용하므로 불필요
  final IconData? icon;
  final Color? color;
  final Color? bgColor;
  final String? tag;

  const _OnboardingPage({
    required this.title,
    required this.description,
    required this.features,
    this.icon,
    this.color,
    this.bgColor,
    this.tag,
  });
}

class _Feature {
  final IconData icon;
  final String label;

  const _Feature(this.icon, this.label);
}
