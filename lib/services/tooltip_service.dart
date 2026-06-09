// lib/services/tooltip_service.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/responsive_helper.dart';
import '../theme/app_colors.dart';

/// 상황별 툴팁 서비스
/// 
/// 기능 첫 사용 시 1회만 안내 표시
class TooltipService {
  static const String _prefix = 'tooltip_shown_';

  /// 툴팁 키 목록
  static const String firstApplication = 'first_application';      // 첫 지원
  static const String firstCheckIn = 'first_check_in';            // 첫 출근
  static const String firstReview = 'first_review';               // 첫 리뷰 작성
  static const String firstToCreate = 'first_to_create';          // 첫 TO 등록
  static const String trustScoreInfo = 'trust_score_info';        // 신뢰도 설명
  static const String scheduleChange = 'schedule_change';         // 일정 변경 요청

  /// 툴팁이 이미 표시되었는지 확인
  static Future<bool> wasShown(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_prefix$key') ?? false;
  }

  /// 툴팁 표시됨으로 저장
  static Future<void> markAsShown(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefix$key', true);
  }

  /// 툴팁 초기화 (테스트용)
  static Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix));
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  /// 특정 툴팁 초기화
  static Future<void> reset(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$key');
  }

  /// 툴팁 표시 (1회만)
  /// 
  /// 사용법:
  /// ```dart
  /// await TooltipService.showOnce(
  ///   context,
  ///   key: TooltipService.firstApplication,
  ///   title: '첫 지원이시네요!',
  ///   message: '지원 후 관리자가 확정하면 알림이 와요.',
  ///   tips: ['확정 후 무단 불참(노쇼)은 신뢰도에 큰 영향을 줘요!'],
  /// );
  /// ```
  static Future<void> showOnce(
    BuildContext context, {
    required String key,
    required String title,
    required String message,
    List<String>? tips,
    IconData icon = Icons.lightbulb_outline,
    Color? iconColor,
  }) async {
    // 이미 표시된 경우 스킵
    if (await wasShown(key)) return;

    // 표시됨으로 저장
    await markAsShown(key);

    // 컨텍스트 유효성 체크
    if (!context.mounted) return;

    // 툴팁 다이얼로그 표시
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => _TooltipDialog(
        title: title,
        message: message,
        tips: tips,
        icon: icon,
        iconColor: iconColor,
      ),
    );
  }
}

/// 툴팁 다이얼로그 위젯
class _TooltipDialog extends StatelessWidget {
  final String title;
  final String message;
  final List<String>? tips;
  final IconData icon;
  final Color? iconColor;

  const _TooltipDialog({
    required this.title,
    required this.message,
    this.tips,
    this.icon = Icons.lightbulb_outline,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveIconColor = iconColor ?? theme.primaryColor;
    // 제목에서 앞쪽 이모지 제거 (디자인으로 대신 표현)
    final cleanTitle = title.replaceAll(RegExp(r'^[\u{1F300}-\u{1FAFF}⭐💡📍✅❌✨🔔]\s*', unicode: true), '');

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 헤더 — 앱 그라데이션 스타일
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 20)),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [theme.primaryColor, theme.colorScheme.secondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon,
                      color: Colors.white,
                      size: ResponsiveHelper.iconSize(context, 22)),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Expanded(
                  child: Text(
                    cleanTitle,
                    style: ResponsiveHelper.subtitleStyle(context).copyWith(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),

          // 본문
          Container(
            color: AppColors.grey50,
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 18)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 메시지
                Text(
                  message,
                  style: ResponsiveHelper.bodyStyle(context,
                      color: AppColors.grey700),
                ),

                // 팁 목록 — 아이콘 불렛
                if (tips != null && tips!.isNotEmpty) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                  Container(
                    padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 14)),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: tips!.asMap().entries.map((e) {
                        final isLast = e.key == tips!.length - 1;
                        return Column(
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  margin: EdgeInsets.only(
                                      top: ResponsiveHelper.spacing(context, 2),
                                      right: ResponsiveHelper.spacing(context, 8)),
                                  width: 5, height: 5,
                                  decoration: BoxDecoration(
                                    color: effectiveIconColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    e.value,
                                    style: ResponsiveHelper.smallStyle(context,
                                        color: AppColors.grey600),
                                  ),
                                ),
                              ],
                            ),
                            if (!isLast)
                              Divider(
                                height: ResponsiveHelper.spacing(context, 12),
                                color: AppColors.grey100,
                              ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ],

                SizedBox(height: ResponsiveHelper.spacing(context, 16)),

                // 확인 버튼
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: effectiveIconColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: EdgeInsets.symmetric(
                          vertical: ResponsiveHelper.spacing(context, 14)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(
                      '확인',
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 미리 정의된 툴팁 내용
class TooltipContents {
  /// 첫 지원 시 (지원자)
  static void showFirstApplication(BuildContext context) {
    TooltipService.showOnce(
      context,
      key: TooltipService.firstApplication,
      title: '💡 첫 지원이시네요!',
      message: '지원 후 관리자가 확정하면\n알림이 옵니다.',
      tips: [
        '확정 후 무단 불참(노쇼)은 신뢰도에 큰 영향을 줘요!',
        '불참이 예상되면 미리 연락해주세요.',
      ],
      icon: Icons.assignment_turned_in,
    );
  }

  /// 첫 출근 시 (지원자)
  static void showFirstCheckIn(BuildContext context) {
    TooltipService.showOnce(
      context,
      key: TooltipService.firstCheckIn,
      title: '📍 첫 출근이시네요!',
      message: '근무지 100m 이내에서\n출근 버튼을 눌러주세요.',
      tips: [
        'GPS 위치가 확인되어야 출근이 가능해요.',
        '시작 시간 10분 전부터 출근 가능합니다.',
      ],
      icon: Icons.location_on,
      iconColor: AppColors.success,
    );
  }

  /// 첫 리뷰 작성 시 (관리자)
  static void showFirstReview(BuildContext context) {
    TooltipService.showOnce(
      context,
      key: TooltipService.firstReview,
      title: '⭐ 첫 리뷰 작성이시네요!',
      message: '리뷰는 작성 후 3일 뒤\n지원자에게 공개됩니다.',
      tips: [
        '평점과 태그는 지원자가 볼 수 있어요.',
        '상세 코멘트는 관리자끼리만 공유됩니다.',
        '같은 지원자는 월 1회만 작성 가능해요.',
      ],
      icon: Icons.rate_review,
      iconColor: AppColors.amber,
    );
  }

  /// 첫 TO 등록 시 (관리자)
  static void showFirstToCreate(BuildContext context) {
    TooltipService.showOnce(
      context,
      key: TooltipService.firstToCreate,
      title: '📋 첫 TO 등록이시네요!',
      message: 'TO를 등록하면 지원자들이\n자동으로 모여요!',
      tips: [
        '공개 일시를 설정하면 예약 공개가 가능해요.',
        '마감일 전까지 지원을 받을 수 있습니다.',
      ],
      icon: Icons.post_add,
    );
  }

  /// 일정 변경 요청 시 (지원자)
  static void showScheduleChange(BuildContext context) {
    TooltipService.showOnce(
      context,
      key: TooltipService.scheduleChange,
      title: '📅 일정 변경 안내',
      message: '일정 변경을 요청하면\n관리자 승인이 필요합니다.',
      tips: [
        '사유를 명확히 작성하면 승인 확률이 높아요.',
        '당일 변경은 어려울 수 있습니다.',
      ],
      icon: Icons.event_note,
      iconColor: AppColors.info,
    );
  }
}