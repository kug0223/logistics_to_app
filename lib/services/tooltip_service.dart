// lib/services/tooltip_service.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/responsive_helper.dart';
import '../utils/text_layout.dart';
import '../theme/app_colors.dart';
import '../widgets/common/common_widgets.dart';
import '../widgets/common/first_line_icon.dart';

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
  // [5A.2B] trustScoreInfo 제거 — trustScore 시스템 폐기
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

  // Dart는 단일 스레드이므로 이 Set 접근은 동기 구간에서 원자적.
  // wasShown→markAsShown 사이 async gap의 중복 호출을 이 Set으로 차단.
  static final Set<String> _pendingKeys = {};

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
    // 동시 호출 guard — 이미 표시 진행 중인 키는 즉시 스킵 (동기 체크이므로 race 없음)
    if (_pendingKeys.contains(key)) return;
    if (await wasShown(key)) return;

    _pendingKeys.add(key);
    try {
      await markAsShown(key);

      if (!context.mounted) return;

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
    } finally {
      _pendingKeys.remove(key);
    }
  }
}

/// 툴팁 다이얼로그 위젯
///
/// [DU433 · 시안 · Standards §12.2 DU308 선례] 넓은 그라데이션 머리 띠 · 흰 제목을 걷었다.
///   - 머리: 흰 바탕 · 작은 의미색 타일 · 진한 제목.
///   - 본문: 그림자 없는 팁 묶음.
///   - 버튼: 브랜드 주 행동(CommonWidgets.primaryButton).
///   의미색은 타일 · 점에만 남는다. 상태 배지와 같은 Bg/Dark 짝을 쓴다(같은 의미 = 같은 토큰).
///   예전 의미색 채움 버튼은 흰 글자 대비가 amber 1.6 · success 2.8 · info 3.1 로 4.5 에 못 미쳤다.
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

  /// 의미색 → (타일 바탕, 아이콘 · 점) 짝. 호출처 색(success · amber · info · 없음)은 배지 짝으로, 그 밖의 색은 α.15 타일로 둔다.
  static ({Color bg, Color fg}) _pairOf(Color? c) {
    if (c == null) return (bg: AppColors.brandSurface, fg: AppColors.brand);
    if (c == AppColors.success) return (bg: AppColors.successBg, fg: AppColors.successDark);
    if (c == AppColors.amber) return (bg: AppColors.warningBg, fg: AppColors.warningDark);
    if (c == AppColors.info) return (bg: AppColors.infoBg, fg: AppColors.infoDark);
    return (bg: c.withValues(alpha: 0.15), fg: c);
  }

  @override
  Widget build(BuildContext context) {
    final pair = _pairOf(iconColor);
    // 제목에서 앞쪽 이모지 제거 (디자인으로 대신 표현)
    final cleanTitle = title.replaceAll(RegExp(r'^[\u{1F300}-\u{1FAFF}⭐💡📍✅❌✨🔔]\s*', unicode: true), '');
    final side = ResponsiveHelper.spacing(context, 20);

    return Dialog(
      // [DU433] 창 바탕을 흰색으로 명시한다 — 미지정이면 M3 기본(surfaceContainerHigh)의 옅은 보라 기운이 깔린다(DU308 과 같다).
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 머리 — 흰 바탕 · 작은 의미색 타일 · 진한 제목(넓은 색 띠 없음)
          Padding(
            padding: EdgeInsets.fromLTRB(side, side, side, 0),
            child: LayoutBuilder(builder: (_, box) {
              final tilePad = ResponsiveHelper.spacing(context, 10);
              final tileIcon = ResponsiveHelper.iconSize(context, 22);
              final gap = ResponsiveHelper.spacing(context, 12);
              final tile = Container(
                padding: EdgeInsets.all(tilePad),
                decoration: BoxDecoration(
                  color: pair.bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: pair.fg, size: tileIcon),
              );
              final titleText = Text(
                TextLayout.keepWords(cleanTitle),
                semanticsLabel: cleanTitle,
                style: ResponsiveHelper.subtitleStyle(context),
              );
              // [DU433] 큰 글자 · 좁은 창에서는 제목 낱말이 타일 옆 칸에 안 들어간다
              //   (B 320@2.0: '작성이시네요!' 200 > 옆 칸 176) — 그때는 타일을 제목 위로 올린다(음절 끊김 없이 낱말 사이 줄바꿈).
              if (TextLayout.fits(context, box.maxWidth - tilePad * 2 - tileIcon - gap, 120)) {
                return Row(children: [tile, SizedBox(width: gap), Expanded(child: titleText)]);
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [tile, SizedBox(height: gap), titleText],
              );
            }),
          ),

          // 본문 — [.64] 320·1.3 에서 아래로 넘쳤다(고정 Column). 머리는 두고 본문만 스크롤한다.
          Flexible(
            child: SingleChildScrollView(
            child: Padding(
            padding: EdgeInsets.fromLTRB(side, ResponsiveHelper.spacing(context, 12), side, side),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 메시지 — [.64] 낱말 단위로만 줄을 바꾼다(긴 안내가 음절에서 끊기지 않게)
                Text(
                  TextLayout.keepWords(message),
                  style: ResponsiveHelper.bodyStyle(context,
                      color: AppColors.grey700),
                ),

                // 팁 목록 — 의미색 점 · 그림자 없는 묶음(화면 바탕색 면)
                if (tips != null && tips!.isNotEmpty) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                  Container(
                    padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 14)),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: tips!.asMap().entries.map((e) {
                        final isLast = e.key == tips!.length - 1;
                        return Column(
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // [DU451] 점이 위 여백 2 · 5×5 고정이라 첫 줄 가운데보다 위에 있었다(W ≈ 5 · B ≈ 14).
                                //   공용 FirstLineIcon 으로 옆 글(smallStyle)의 첫 줄 가운데에 둔다 — 크기는 그대로(DU361 규칙).
                                FirstLineIcon(Icons.circle,
                                    size: 6,
                                    color: pair.fg,
                                    textStyle: ResponsiveHelper.smallStyle(context)),
                                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                                Expanded(
                                  child: Text(
                                    TextLayout.keepWords(e.value),
                                    // [DU433] 묶음 면(background) 위 grey600 은 4.30 — 보조 글 토큰 textSecondary(5.52)로.
                                    style: ResponsiveHelper.smallStyle(context,
                                        color: AppColors.textSecondary),
                                  ),
                                ),
                              ],
                            ),
                            if (!isLast)
                              Divider(
                                height: ResponsiveHelper.spacing(context, 12),
                                color: AppColors.dividerLight,
                              ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ],

                SizedBox(height: ResponsiveHelper.spacing(context, 16)),

                // 확인 버튼 — 브랜드 주 행동(시안 · 공용 버튼)
                CommonWidgets.primaryButton(
                  context: context,
                  text: '확인',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
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
      // [.64] '작성 후 3일 뒤 공개'는 실제 계약이 아니었다. 공개는 onReviewCreated(양쪽 제출 즉시) 또는
      //   자정 만료 처리(review_requests.deadline = 요청을 만든 근무일 + 14일)다.
      message: '양쪽이 모두 작성하면 바로 함께 공개돼요.\n지원자가 작성하지 않으면 리뷰 요청이 온 근무일로부터 14일이 지난 뒤 공개돼요.',
      tips: [
        '평점과 태그는 지원자가 볼 수 있어요.',
        '상세 코멘트와 재고용 의사는 관리자끼리만 공유됩니다.',
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
      title: '📋 첫 공고 등록이시네요!',
      message: '공고를 등록하면 지원자들이\n자동으로 모여요!',
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