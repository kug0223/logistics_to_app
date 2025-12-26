// lib/screens/common/onboarding_screen.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/responsive_helper.dart';
import '../../theme/app_colors.dart';

/// 온보딩 화면
/// 
/// 최초 로그인 시 1회만 표시
/// - 지원자: 앱 소개, 신뢰도, 출퇴근
/// - 관리자: 앱 소개, TO 등록, 리뷰 시스템
class OnboardingScreen extends StatefulWidget {
  /// 사용자 역할 (USER, BUSINESS_ADMIN)
  final String role;
  
  /// 완료 후 콜백
  final VoidCallback onComplete;

  const OnboardingScreen({
    super.key,
    required this.role,
    required this.onComplete,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  List<OnboardingPage> get _pages {
    if (widget.role == 'BUSINESS_ADMIN' || widget.role == 'SUPER_ADMIN') {
      return _adminPages;
    }
    return _userPages;
  }

  /// 지원자용 온보딩 페이지
  final List<OnboardingPage> _userPages = [
    OnboardingPage(
      emoji: '👋',
      title: '알핏에 오신 걸 환영해요!',
      description: '물류센터 일자리를\n쉽고 빠르게 찾을 수 있어요.',
      highlights: [
        '원하는 날짜와 시간 선택',
        '간편한 지원과 확정',
        '다양한 물류센터 일자리',
      ],
    ),
    OnboardingPage(
      emoji: '📊',
      title: '신뢰도 점수란?',
      description: '성실하게 근무하면 점수가 올라가요.\n점수가 높을수록 채용 확률 UP!',
      highlights: [
        '정상 출근 +1점',
        '지각 -1점',
        '노쇼 -3점 이상',
      ],
      highlightColors: [
        AppColors.success,
        AppColors.warning,
        AppColors.error,
      ],
    ),
    OnboardingPage(
      emoji: '📍',
      title: '출퇴근은 이렇게!',
      description: '근무지 근처에서 앱으로 체크하세요.\nGPS로 자동 확인됩니다.',
      highlights: [
        '출근: 시작 10분 전부터 가능',
        '퇴근: 종료 시간 이후 가능',
        '위치 확인 필수!',
      ],
    ),
  ];

  /// 관리자용 온보딩 페이지
  final List<OnboardingPage> _adminPages = [
    OnboardingPage(
      emoji: '👋',
      title: '알핏 관리자님 환영합니다!',
      description: '간편하게 인력을 모집하고\n관리할 수 있어요.',
      highlights: [
        '빠른 TO 등록',
        '실시간 지원자 확인',
        '체계적인 인력 관리',
      ],
    ),
    OnboardingPage(
      emoji: '📋',
      title: 'TO 등록은 간단해요',
      description: '몇 번의 터치로 인력을 모집하세요.\n지원자가 자동으로 모여요.',
      highlights: [
        '1. 날짜/시간 선택',
        '2. 필요 인원 입력',
        '3. 공개하면 끝!',
      ],
    ),
    OnboardingPage(
      emoji: '⭐',
      title: '월간 리뷰로 관리하세요',
      description: '해당 월 중 언제든 리뷰를 작성할 수 있어요.\n작성 후 3일 뒤 지원자에게 공개됩니다.',
      highlights: [
        '점수/태그는 지원자가 볼 수 있음',
        '상세 코멘트는 관리자끼리만 공유',
        '같은 사업장+지원자는 월 1회',
      ],
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _completeOnboarding();
    }
  }

  void _skipOnboarding() {
    _completeOnboarding();
  }

  Future<void> _completeOnboarding() async {
    // 온보딩 완료 저장
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed', true);
    
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.primaryColor,
              theme.primaryColor.withOpacity(0.8),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // 상단 스킵 버튼
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
                  child: TextButton(
                    onPressed: _skipOnboarding,
                    child: Text(
                      '건너뛰기',
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                  ),
                ),
              ),
              
              // 페이지 뷰
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() => _currentPage = index);
                  },
                  itemCount: _pages.length,
                  itemBuilder: (context, index) {
                    return _buildPage(context, _pages[index]);
                  },
                ),
              ),
              
              // 하단 영역 (인디케이터 + 버튼)
              Padding(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 24)),
                child: Column(
                  children: [
                    // 페이지 인디케이터
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_pages.length, (index) {
                        return Container(
                          margin: EdgeInsets.symmetric(
                            horizontal: ResponsiveHelper.spacing(context, 4),
                          ),
                          width: _currentPage == index ? 24 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _currentPage == index
                                ? Colors.white
                                : Colors.white.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        );
                      }),
                    ),
                    
                    SizedBox(height: ResponsiveHelper.spacing(context, 32)),
                    
                    // 다음/시작하기 버튼
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _nextPage,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: theme.primaryColor,
                          padding: EdgeInsets.symmetric(
                            vertical: ResponsiveHelper.spacing(context, 16),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          _currentPage == _pages.length - 1 ? '시작하기' : '다음',
                          style: ResponsiveHelper.subtitleStyle(context).copyWith(
                            color: theme.primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPage(BuildContext context, OnboardingPage page) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 32),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 이모지
          Text(
            page.emoji,
            style: TextStyle(fontSize: ResponsiveHelper.spacing(context, 80)),
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 32)),
          
          // 제목
          Text(
            page.title,
            style: ResponsiveHelper.titleStyle(context).copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: ResponsiveHelper.spacing(context, 28),
            ),
            textAlign: TextAlign.center,
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          
          // 설명
          Text(
            page.description,
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              color: Colors.white.withOpacity(0.9),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 32)),
          
          // 하이라이트 항목들
          Container(
            padding: ResponsiveHelper.cardPadding(context),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: page.highlights.asMap().entries.map((entry) {
                final index = entry.key;
                final text = entry.value;
                final color = page.highlightColors != null && 
                              index < page.highlightColors!.length
                    ? page.highlightColors![index]
                    : Colors.white;
                
                return Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: ResponsiveHelper.spacing(context, 8),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                      Expanded(
                        child: Text(
                          text,
                          style: ResponsiveHelper.bodyStyle(context).copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

/// 온보딩 페이지 데이터
class OnboardingPage {
  final String emoji;
  final String title;
  final String description;
  final List<String> highlights;
  final List<Color>? highlightColors;

  const OnboardingPage({
    required this.emoji,
    required this.title,
    required this.description,
    required this.highlights,
    this.highlightColors,
  });
}

/// 온보딩 완료 여부 확인
Future<bool> isOnboardingCompleted() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool('onboarding_completed') ?? false;
}

/// 온보딩 상태 초기화 (테스트용)
Future<void> resetOnboarding() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('onboarding_completed');
}