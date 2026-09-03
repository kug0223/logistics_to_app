// lib/screens/common/tour_screen.dart
//
// 인앱 기능 투어 화면 — 온보딩과 동일한 풀스크린 디자인
// Navigator.push로 열리며, 완료/건너뛰기 시 pop 처리

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';

/// 역할에 따라 적합한 투어 화면을 push하는 헬퍼
Future<void> pushTourScreen(BuildContext context, {required String role}) async {
  final pages = (role == 'BUSINESS_ADMIN' || role == 'SUPER_ADMIN')
      ? _adminTourPages
      : _userTourPages;
  await Navigator.push(
    context,
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => TourScreen(pages: pages),
    ),
  );
}

class TourScreen extends StatefulWidget {
  final List<TourPage> pages;

  const TourScreen({super.key, required this.pages});

  @override
  State<TourScreen> createState() => _TourScreenState();
}

class _TourScreenState extends State<TourScreen>
    with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  late AnimationController _animController;
  late Animation<double> _scaleAnim;

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

  void _nextPage() {
    if (_currentPage < widget.pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _complete();
    }
  }

  void _complete() {
    Navigator.pop(context);
  }

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);
    _animController.reset();
    _animController.forward();
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.pages[_currentPage];

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // 상단 바 (태그 + 건너뛰기)
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 8),
                vertical: ResponsiveHelper.spacing(context, 4),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: page.bgColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      page.tag,
                      style: ResponsiveHelper.tinyStyle(context,
                          color: page.color, fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    onPressed: _complete,
                    child: Text(
                      '건너뛰기',
                      style: ResponsiveHelper.bodyStyle(context,
                          color: AppColors.grey500, fontWeight: FontWeight.w500),
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
                itemCount: widget.pages.length,
                itemBuilder: (context, index) =>
                    _buildIllustration(context, widget.pages[index]),
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

  Widget _buildIllustration(BuildContext context, TourPage page) {
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
              top: -30, right: -30,
              child: Container(
                width: 140, height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: page.color.withValues(alpha: 0.08),
                ),
              ),
            ),
            // 배경 장식 원 (소)
            Positioned(
              bottom: 20, left: 20,
              child: Container(
                width: 70, height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: page.color.withValues(alpha: 0.06),
                ),
              ),
            ),
            // 중앙 아이콘
            Center(
              child: Container(
                width: 130, height: 130,
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
                child: Icon(page.icon, size: 64, color: page.color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, TourPage page) {
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
            style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey500)
                .copyWith(height: 1.6),
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 20)),

          // 기능 항목
          ...page.features.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: f.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(f.icon, size: 17, color: f.color),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        f.label,
                        style: ResponsiveHelper.bodyStyle(context,
                            color: AppColors.grey800, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              )),

          const Spacer(),

          // 인디케이터 + 버튼
          Row(
            children: [
              Row(
                children: List.generate(widget.pages.length, (i) {
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
              GestureDetector(
                onTap: _nextPage,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
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
                        _currentPage == widget.pages.length - 1 ? '확인' : '다음',
                        style: ResponsiveHelper.bodyStyle(context).copyWith(
                          color: Colors.white, fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.arrow_forward_rounded,
                          color: Colors.white, size: 17),
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

// ── 투어 페이지 데이터 클래스 ─────────────────────────────────────

class TourPage {
  final IconData icon;
  final Color color;
  final Color bgColor;
  final String tag;
  final String title;
  final String description;
  final List<TourFeature> features;

  const TourPage({
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.tag,
    required this.title,
    required this.description,
    required this.features,
  });
}

class TourFeature {
  final IconData icon;
  final String label;
  final Color color;
  const TourFeature(this.icon, this.label, this.color);
}

// ── 근무자 투어 페이지 ────────────────────────────────────────────

const _userTourPages = [
  TourPage(
    icon: Icons.rocket_launch_rounded,
    color: AppColors.infoDark,
    bgColor: AppColors.infoBg,
    tag: '공고 찾기',
    title: '원하는 공고를\n찾고 바로 지원',
    description: '날짜·업종별로 공고를 검색하고\n한 번 터치로 지원하세요.',
    features: [
      TourFeature(Icons.calendar_month_rounded, '원하는 날짜·시간 선택', AppColors.infoDark),
      TourFeature(Icons.touch_app_rounded, '지원 한 번으로 완료', AppColors.infoDark),
      TourFeature(Icons.notifications_outlined, '확정 시 알림 즉시 수신', AppColors.infoDark),
    ],
  ),
  TourPage(
    icon: Icons.assignment_turned_in_rounded,
    color: AppColors.purple,
    bgColor: AppColors.purpleBg,
    tag: '지원 & 계약',
    title: '지원부터 계약까지\n앱 하나로 완결',
    description: '공고 지원 → 관리자 확정 → 계약서 서명까지\n모든 과정이 앱 안에서 이루어져요.',
    features: [
      TourFeature(Icons.search_rounded, '조건에 맞는 공고 검색', AppColors.purple),
      TourFeature(Icons.check_circle_outline, '관리자 확정 후 알림 수신', AppColors.purple),
      TourFeature(Icons.draw_outlined, '전자 계약서 앱에서 서명', AppColors.purple),
    ],
  ),
  TourPage(
    icon: Icons.location_on_rounded,
    color: AppColors.successDark,
    bgColor: AppColors.successBg,
    tag: 'GPS 출퇴근',
    title: '근무지 근처에서\n앱으로 출퇴근 체크',
    description: 'GPS로 근무지 근처에서 버튼 하나로 출퇴근 체크!\n조출·지각·조퇴 여부가 자동으로 기록돼요.',
    features: [
      TourFeature(Icons.my_location_rounded, '근무지 GPS 인증으로 간편 체크', AppColors.successDark),
      TourFeature(Icons.auto_awesome_rounded, '조출·지각·조퇴 자동 감지 및 기록', AppColors.successDark),
      TourFeature(Icons.edit_note_rounded, '시간이 틀리면 수정 요청 가능', AppColors.successDark),
    ],
  ),
  TourPage(
    icon: Icons.trending_up_rounded,
    color: AppColors.warningDarkest,
    bgColor: AppColors.warningBg,
    tag: '급여 & 근무 이력',
    title: '급여 명세서 확인,\n노쇼 없이 더 많은 기회 얻기',
    description: '임금명세서를 앱에서 바로 확인하고\n근무 이력과 노쇼 기록이 투명하게 쌓여요.',
    features: [
      TourFeature(Icons.receipt_long_outlined, '임금명세서 앱에서 확인·저장', AppColors.warningDarkest),
      TourFeature(Icons.check_circle_rounded, '출근 기록 → 리뷰·평점 누적', AppColors.success),
      TourFeature(Icons.warning_amber_rounded, '노쇼 3회(90일) → 지원 제한', AppColors.error),
    ],
  ),
];

// ── 관리자 투어 페이지 ────────────────────────────────────────────

const _adminTourPages = [
  TourPage(
    icon: Icons.admin_panel_settings_rounded,
    color: AppColors.infoDark,
    bgColor: AppColors.infoBg,
    tag: '알핏 관리자',
    title: '채용부터 급여까지\n원스톱 관리',
    description: '공고 등록 → 지원자 확정 → 계약서 → 출퇴근 → 급여까지\n모든 인력 관리를 하나의 앱에서.',
    features: [
      TourFeature(Icons.flash_on_rounded, '빠른 공고 등록 & 공고 관리', AppColors.infoDark),
      TourFeature(Icons.description_outlined, '전자 계약서 자동 발송', AppColors.infoDark),
      TourFeature(Icons.account_balance_wallet_outlined, '급여 확정 & 송금 관리', AppColors.infoDark),
    ],
  ),
  TourPage(
    icon: Icons.post_add_rounded,
    color: AppColors.purple,
    bgColor: AppColors.purpleBg,
    tag: '공고 등록',
    title: '공고 등록 3단계,\n지원자가 모여요',
    description: '업종·날짜·시간·인원만 입력하고 공개하면\n지원자가 자동으로 모입니다.',
    features: [
      TourFeature(Icons.looks_one_rounded, '업종·날짜·시간·인원 설정', AppColors.purple),
      TourFeature(Icons.looks_two_rounded, '공고 공개 → 지원자 수신', AppColors.purple),
      TourFeature(Icons.looks_3_rounded, '지원자 확정 → 계약서 발송', AppColors.purple),
    ],
  ),
  TourPage(
    icon: Icons.people_alt_rounded,
    color: AppColors.amber,
    bgColor: AppColors.warningBg,
    tag: '지원자 & 계약서',
    title: '지원자 확정하면\n계약서 자동 발송',
    description: '원하는 지원자를 확정하면 전자 계약서가\n자동으로 발송되어 앱에서 서명을 받아요.',
    features: [
      TourFeature(Icons.how_to_reg_rounded, '지원자 확정 한 번에 처리', AppColors.amber),
      TourFeature(Icons.description_outlined, '전자 계약서 자동 발송', AppColors.amber),
      TourFeature(Icons.verified_outlined, '서명 완료 후 계약 확정', AppColors.amber),
    ],
  ),
  TourPage(
    icon: Icons.how_to_reg_rounded,
    color: AppColors.infoDark,
    bgColor: AppColors.infoBg,
    tag: '당일 출퇴근 관리',
    title: '당일 출퇴근 현황을\n실시간으로 확인',
    description: '출퇴근 현황을 한눈에 보고 시간 조정·마감을\n손쉽게 처리할 수 있어요.',
    features: [
      TourFeature(Icons.fact_check_rounded, '실시간 출퇴근 현황 모니터링', AppColors.infoDark),
      TourFeature(Icons.tune_rounded, '시간 조정 & 원본 기록 보존', AppColors.infoDark),
      TourFeature(Icons.picture_as_pdf_outlined, '당일명단 PDF 내보내기', AppColors.infoDark),
    ],
  ),
  TourPage(
    icon: Icons.payments_outlined,
    color: AppColors.successDark,
    bgColor: AppColors.successBg,
    tag: '급여 관리',
    title: '급여 확정부터\n송금 관리까지',
    description: '공제 설정 후 급여를 확정하면 임금명세서가\n자동으로 공개되고, 엑셀로 일괄 이체해요.',
    features: [
      TourFeature(Icons.receipt_long_outlined, '급여 확정 & 임금명세서 공개', AppColors.successDark),
      TourFeature(Icons.restaurant_outlined, '석식/야식 공제 일괄 적용', AppColors.successDark),
      TourFeature(Icons.download_outlined, '은행 이체용 엑셀 내보내기', AppColors.successDark),
    ],
  ),
];
