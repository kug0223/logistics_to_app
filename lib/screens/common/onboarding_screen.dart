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
  static const _adminPages = [
    _OnboardingPage(
      icon: Icons.admin_panel_settings_rounded,
      color: AppColors.infoDark,
      bgColor: AppColors.infoBg,
      tag: '알핏 관리자',
      title: '채용부터 급여까지\n원스톱 관리',
      description: '공고 등록 → 지원자 확정 → 계약서 → 출퇴근 → 급여까지\n모든 인력 관리를 하나의 앱에서.',
      features: [
        _Feature(Icons.flash_on_rounded, '빠른 공고 등록 & 공고 관리'),
        _Feature(Icons.description_outlined, '전자 계약서 자동 발송'),
        _Feature(Icons.account_balance_wallet_outlined, '급여 확정 & 송금 관리'),
      ],
    ),
    _OnboardingPage(
      icon: Icons.post_add_rounded,
      color: AppColors.purple,
      bgColor: AppColors.purpleBg,
      tag: '공고 등록',
      title: '공고 등록 3단계,\n지원자가 모여요',
      description: '업종·날짜·시간·인원만 입력하고 공개하면\n지원자가 자동으로 모입니다.',
      features: [
        _Feature(Icons.looks_one_rounded, '업종·날짜·시간·인원 설정'),
        _Feature(Icons.looks_two_rounded, '공고 공개 → 지원자 수신'),
        _Feature(Icons.looks_3_rounded, '지원자 확정 → 계약서 발송'),
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
        _Feature(Icons.how_to_reg_rounded, '지원자 확정 한 번에 처리'),
        _Feature(Icons.description_outlined, '전자 계약서 자동 발송'),
        _Feature(Icons.verified_outlined, '서명 완료 후 계약 확정'),
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
        _Feature(Icons.fact_check_rounded, '실시간 출퇴근 현황 모니터링'),
        _Feature(Icons.tune_rounded, '시간 조정 & 원본 기록 보존'),
        _Feature(Icons.picture_as_pdf_outlined, '당일명단 PDF 내보내기'),
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
        _Feature(Icons.receipt_long_outlined, '급여 확정 & 임금명세서 공개'),
        _Feature(Icons.download_outlined, '은행 이체용 엑셀 내보내기'),
        _Feature(Icons.star_rate_rounded, '월간 리뷰로 인재 평가'),
      ],
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
    return ScaleTransition(scale: _scaleAnim, child: child);
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

          const Spacer(),

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
