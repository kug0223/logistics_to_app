// lib/widgets/dialogs/monthly_review_dialog.dart

import 'package:flutter/material.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/text_layout.dart';
import '../../theme/app_colors.dart';
import '../../models/core/monthly_review_model.dart';
import '../../models/settings/trust_settings_model.dart';
import '../../services/monthly_review_service.dart';
import '../../services/tooltip_service.dart';
import '../../utils/toast_helper.dart';
import 'styled_dialog.dart';
import 'review_dialog_shell.dart';

/// 월별 리뷰 작성 다이얼로그 (관리자 → 지원자)
/// 
/// 정책:
/// - 월 1회만 작성 가능
/// - 작성 후 수정 불가
/// - 즉시공개(상대방 작성 시) or review_requests.deadline(요청을 만든 근무일 + 14일)이 지난 자정 처리에서 공개
class MonthlyReviewDialog extends StatefulWidget {
  /// 작성자 (관리자) UID
  final String reviewerId;
  
  /// 작성자 이름
  final String reviewerName;
  
  /// 사업장 ID
  final String businessId;
  
  /// 사업장 이름
  final String businessName;
  
  /// 리뷰 대상 사용자 UID
  final String targetUserId;
  
  /// 리뷰 대상 사용자 이름
  final String targetUserName;
  final String? targetUserGender;
  final int? targetUserAge;

  /// 리뷰 대상 년도
  final int reviewYear;
  
  /// 리뷰 대상 월
  final int reviewMonth;
  
  /// 해당 월 근무 일수
  final int workDaysInMonth;
  
  /// 해당 월 정상 출근 일수.
  ///   [REVIEW-WORKER-SUMMARY] null = **확인할 수 없음**(구 서버 요약처럼 근거가 없을 때).
  ///   숫자로 추측하지 않는다 — 화면엔 `확인 불가`, 저장값도 null 이다.
  final int? normalAttendanceDays;

  /// 해당 월 지각 횟수. null = 확인할 수 없음.
  final int? lateDays;

  /// review_requests 문서 ID (양방향 공개 연동)
  final String? requestId;

  /// 미리 로드된 태그 목록 (showMonthlyReviewDialog에서 주입)
  final ReviewTagsModel preloadedTags;

  /// [.62] 태그 설정을 읽지 못했다 — 기본 목록을 현재 설정처럼 보이지 않고 안내한다.
  final bool tagsUnavailable;

  const MonthlyReviewDialog({
    super.key,
    required this.reviewerId,
    required this.reviewerName,
    required this.businessId,
    required this.businessName,
    required this.targetUserId,
    required this.targetUserName,
    this.targetUserGender,
    this.targetUserAge,
    required this.reviewYear,
    required this.reviewMonth,
    required this.workDaysInMonth,
    this.normalAttendanceDays = 0,
    this.lateDays = 0,
    this.requestId,
    required this.preloadedTags,
    this.tagsUnavailable = false,
    this.loadLatestTags,
  });

  /// 시험용 — 제출 직전 최신 태그 읽기. production 은 null → 서비스.
  final Future<ReviewTagsModel> Function()? loadLatestTags;

  @override
  State<MonthlyReviewDialog> createState() => _MonthlyReviewDialogState();
}

class _MonthlyReviewDialogState extends State<MonthlyReviewDialog> {
  final _commentController = TextEditingController();
  final _reviewService = MonthlyReviewService();

  // 평가
  int _rating = 4;
  bool? _wouldRehire;
  List<String> _selectedPositiveTags = [];
  List<String> _selectedImprovementTags = [];
  /// 제출 직전 대조에서 빠진 선택(작성 창을 연 사이 SA 가 지운 태그).
  List<String> _droppedTags = [];

  // 근태 (H-4: 출퇴근 연동 전까지 수동 입력)
  late int? _normalDays;
  late int? _lateDays;

  bool _isSubmitting = false;

  // 태그 목록 (showMonthlyReviewDialog에서 미리 로드 후 주입)
  late ReviewTagsModel _tags;

  @override
  void initState() {
    super.initState();
    _normalDays = widget.normalAttendanceDays;
    _lateDays = widget.lateDays;
    _tags = widget.preloadedTags;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) TooltipContents.showFirstReview(context);
    });
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  /// [.63] 제출 직전 최신 태그 목록과 대조한다. 작성 창을 연 사이 SA 가 지운 태그를
  ///   골랐으면 **저장하지 않고** 무엇이 빠졌는지 보여 준 뒤 최신 목록으로 다시 고르게 한다
  ///   (몰래 빼고 제출하거나 다른 글자로 바꾸지 않는다). 서버 규칙 후보가 같은 대조를 한다.
  Future<bool> _tagsStillValid() async {
    if (_selectedPositiveTags.isEmpty && _selectedImprovementTags.isEmpty) return true;
    final ReviewTagsModel latest;
    try {
      latest = await (widget.loadLatestTags ?? _reviewService.getReviewTags)();
    } catch (e) {
      debugPrint('❌ 리뷰 태그 확인 실패: $e');
      if (mounted) ToastHelper.showError('태그 목록을 확인하지 못했습니다. 다시 시도해 주세요.');
      return false;
    }
    final gone = MonthlyReviewService.unavailableTags(latest,
        positive: _selectedPositiveTags,
        improvement: _selectedImprovementTags,
        business: false);
    if (gone.isEmpty) return true;
    if (mounted) {
      setState(() {
        _tags = latest;
        _selectedPositiveTags = _selectedPositiveTags.where((t) => !gone.contains(t)).toList();
        _selectedImprovementTags = _selectedImprovementTags.where((t) => !gone.contains(t)).toList();
        _droppedTags = gone;
      });
      ToastHelper.showWarning('선택한 태그가 바뀌었습니다. 확인 후 다시 작성해 주세요.');
    }
    return false;
  }

  Future<void> _submitReview() async {
    // 유효성 검사
    if (_wouldRehire == null) {
      ToastHelper.showWarning('재고용 의사를 선택해주세요.');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
    if (!await _tagsStillValid()) return;
    final result = await _reviewService.createReviewForUser(
      reviewerId: widget.reviewerId,
      reviewerName: widget.reviewerName,
      businessId: widget.businessId,
      businessName: widget.businessName,
      targetUserId: widget.targetUserId,
      targetUserName: widget.targetUserName,
      targetUserGender: widget.targetUserGender,
      targetUserAge: widget.targetUserAge,
      reviewYear: widget.reviewYear,
      reviewMonth: widget.reviewMonth,
      workDaysInMonth: widget.workDaysInMonth,
      normalAttendanceDays: _normalDays,
      lateDays: _lateDays,
      rating: _rating,
      wouldRehire: _wouldRehire!,
      positiveTags: _selectedPositiveTags,
      improvementTags: _selectedImprovementTags,
      comment: _commentController.text.trim().isEmpty
          ? null
          : _commentController.text.trim(),
      requestId: widget.requestId,
    );

    if (!mounted) return;

    if (result.reviewId != null) {
      // 성공 다이얼로그
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (resultContext) => StyledDialog(
          title: '리뷰 작성 완료',
          subtitle: null,
          icon: Icons.check_circle,
          headerColor: AppColors.success,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.schedule,
                size: ResponsiveHelper.iconSize(resultContext, 48),
                color: AppColors.info,
              ),
              SizedBox(height: ResponsiveHelper.spacing(resultContext, 16)),
              Text(
                // [.64] 공개 기산점을 실제 계약대로(요청이 온 근무일 + 14일)
                // [.82 F4] 공개는 서버 trigger 가 비동기로 한다 — 제출 응답은 공개 여부를 모른다. 규칙 문장만 쓴다.
                TextLayout.keepWords('리뷰가 등록되었습니다.\n양쪽 리뷰가 모두 등록되거나, 리뷰 요청이 온 근무일로부터 14일이 지나면 공개됩니다.'),
                style: ResponsiveHelper.bodyStyle(resultContext),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            StyledDialogButton.primary(
              text: '확인',
              onPressed: () {
                // [FC-08 FIX] 중첩 다이얼로그 확인 — pop 전 unfocus
                FocusManager.instance.primaryFocus?.unfocus();
                Navigator.pop(resultContext);
              },
            ),
          ],
        ),
      );
      // [.62] 뒤로 키로 확인 창만 닫히면 저장된 작성 창이 남아 다시 제출할 수 있어 보였다.
      //   확인 창이 어떻게 닫히든 작성 창도 닫는다.
      if (mounted) Navigator.pop(context, true);
    } else {
      // 대조와 저장 사이에 태그가 지워져 서버가 거절했을 수 있다 — 그렇다면 같은 안내를 한다.
      if (!await _tagsStillValid()) return;
      if (mounted) ToastHelper.showError(result.error ?? '리뷰 작성에 실패했습니다.');
    }
    } catch (e) {
      debugPrint('❌ 리뷰 제출 실패: $e');
      if (mounted) ToastHelper.showError('리뷰 작성에 실패했습니다.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ReviewDialogShell(
      header: _buildHeader(context, theme),
      body: [
        _buildAttendanceSummary(context),
        _buildDivider(context),
        _buildRatingSection(context),
        _buildDivider(context),
        _buildRehireSection(context, theme),
        _buildDivider(context),
        if (_droppedTags.isNotEmpty) _buildDroppedNotice(context),
        _buildTagSection(
          context,
          title: '좋았던 점',
          icon: Icons.thumb_up_outlined,
          iconColor: AppColors.success,
          tags: _tags.positiveTags,
          selectedTags: _selectedPositiveTags,
          onChanged: (tags) => setState(() => _selectedPositiveTags = tags),
        ),
        _buildDivider(context),
        _buildTagSection(
          context,
          title: '아쉬운 점',
          icon: Icons.lightbulb_outline,
          iconColor: AppColors.warning,
          tags: _tags.improvementTags,
          selectedTags: _selectedImprovementTags,
          onChanged: (tags) => setState(() => _selectedImprovementTags = tags),
        ),
        _buildDivider(context),
        _buildCommentSection(context, theme),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        _buildNotice(context),
      ],
      actions: _buildActions(context, theme),
    );
  }

  /// 헤더 — flat AppModalHeader (ALfit Modal Grammar)
  Widget _buildHeader(BuildContext context, ThemeData theme) {
    return AppModalHeader(
      title: '${widget.reviewMonth}월 리뷰 작성',
      subtitle: widget.targetUserName,
      onClose: () {
        FocusManager.instance.primaryFocus?.unfocus();
        Navigator.pop(context);
      },
    );
  }

  /// 근태 요약
  Widget _buildAttendanceSummary(BuildContext context) {
    final normal = widget.normalAttendanceDays;
    final late = widget.lateDays;
    // 정시·지각을 모르면 결근도 계산하지 않는다(근무일 전체를 결근으로 그리지 않는다).
    final absenceDays =
        (normal == null || late == null) ? 0 : widget.workDaysInMonth - normal - late;

    // [DU269] 회색 면 radius 12 → 시안 카드(흰 면·radius 16·grey200 선), 아이콘 textSecondary
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.grey200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.analytics_outlined,
                size: ResponsiveHelper.iconSize(context, 20),
                color: AppColors.textSecondary,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              // [.62] 320·1.3 / 392·2.0 에서 넘쳤다 — 줄을 바꾼다.
              Flexible(
                child: Text(
                  TextLayout.keepWords('${widget.reviewMonth}월 근태 요약'),
                  style: ResponsiveHelper.subtitleStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          // [DU269] 단순 사실(근무일·정시·지각 0)은 본문색, 지각>0 warningDark·결근 errorDark, 확인 불가 textSecondary
          //   (이전 info·success·warning·error·grey400 — 1.9~3.5, UI-1 '0·단순 사실은 중립').
          //   큰 글자에서는 두 칸씩 줄을 바꾼다(B320 '근무/일'·'12/일'). 값 글자는 원문 그대로다(시험 계약).
          LayoutBuilder(builder: (context, cons) {
            final stats = <Widget>[
              _buildStatItem(context, '근무일', '${widget.workDaysInMonth}일', AppColors.textPrimary),
              _buildStatItem(context, '정시 출근',
                  normal == null ? '확인 불가' : '$normal일',
                  normal == null ? AppColors.textSecondary : AppColors.textPrimary),
              _buildStatItem(context, '지각',
                  late == null ? '확인 불가' : '$late회',
                  late == null
                      ? AppColors.textSecondary
                      : (late > 0 ? AppColors.warningDark : AppColors.textPrimary)),
              if (absenceDays > 0)
                _buildStatItem(context, '결근', '$absenceDays일', AppColors.errorDark),
            ];
            if (MediaQuery.textScalerOf(context).scale(10) < 13) {
              return Row(children: [for (final s in stats) Expanded(child: s)]);
            }
            final gap = ResponsiveHelper.spacing(context, 12);
            final half = (cons.maxWidth - gap) / 2;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              // [DU269 r2] 칸은 최소 반 폭, 값이 길면('확인 불가') 더 넓게 — 반 폭에서 '확인 불/가' 로 끊겼다.
              //   값 글자는 시험 계약상 원문이라 낱말 묶기를 쓰지 않는다.
              children: [
                for (final s in stats)
                  ConstrainedBox(constraints: BoxConstraints(minWidth: half), child: s),
              ],
            );
          }),
        ],
      ),
    );
  }

  /// [DU269] 칸 하나 — 배치(한 줄 Expanded / 큰 글자 두 칸 Wrap)는 호출부가 정한다. 칸 이름 grey500(2.57) → textSecondary.
  Widget _buildStatItem(BuildContext context, String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          textAlign: TextAlign.center,
          style: ResponsiveHelper.subtitleStyle(context).copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 4)),
        Text(
          label,
          textAlign: TextAlign.center,
          style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  /// 평점 섹션
  Widget _buildRatingSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(context, '종합 평가'),
        SizedBox(height: ResponsiveHelper.spacing(context, 10)),
        // 별점 행
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (index) {
            final starIndex = index + 1;
            final filled = starIndex <= _rating;
            // [DU269] 터치 48×48 칸(이전 약 40×29), 빈 별 grey300(1.3) → textTertiary, '$n점' 낭독(O017·DU268 과 같음)
            return Semantics(
              label: '$starIndex점',
              button: true,
              selected: _rating == starIndex,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _rating = starIndex),
                child: SizedBox.square(
                  dimension: 48,
                  child: Center(
                    child: Icon(
                      filled ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: ResponsiveHelper.iconSize(context, 32),
                      color: filled ? AppColors.amber : AppColors.textTertiary,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        // [DU269] 점수 라벨 — 점수별 의미색 알약(보통 warning 2.2) → O017 처럼 보조색 글자
        if (_rating > 0) ...[
          SizedBox(height: ResponsiveHelper.spacing(context, 6)),
          Center(
            child: Text(
              _getRatingText(_rating),
              style: ResponsiveHelper.bodyStyle(context, color: AppColors.textSecondary),
            ),
          ),
        ],
      ],
    );
  }

  String _getRatingText(int rating) {
    switch (rating) {
      case 5: return '최고';
      case 4: return '좋음';
      case 3: return '보통';
      case 2: return '아쉬움';
      case 1: return '부족';
      default: return '';
    }
  }

  /// [DU269] 거의 보이지 않던 grey100 구분선(흰 위 약 1.1) → 섹션 간격 24(O017 과 같음). 이름은 호출부를 위해 둔다.
  Widget _buildDivider(BuildContext context) =>
      SizedBox(height: ResponsiveHelper.spacing(context, 24));

  /// 공통 섹션 라벨 — Wrap으로 좁은 화면에서 자동 줄바꿈
  Widget _buildSectionLabel(BuildContext context, String label,
      {String? badge, String? hint}) {
    // [DU269] 섹션 제목 16 bold 본문색(O017·시안과 같음, 이전 grey700 15), 배지는 공통 함수, 힌트 textSecondary(이전 grey400 1.88).
    return Wrap(
      spacing: ResponsiveHelper.spacing(context, 6),
      runSpacing: ResponsiveHelper.spacing(context, 4),
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _reviewSectionTitle(context, label),
        if (badge != null) _adminOnlyBadge(context, badge),
        if (hint != null)
          Text(TextLayout.keepWords(hint),
              semanticsLabel: hint,
              style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary)),
      ],
    );
  }

  /// 재고용 의사 섹션 — 수평 compact 버튼
  Widget _buildRehireSection(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(context, '재고용 의사',
            badge: '관리자 전용',
            hint: '다른 관리자에게만 공개'),
        SizedBox(height: ResponsiveHelper.spacing(context, 10)),
        // [DU269] 큰 글자에서 '재고용 / 안함' 만 두 줄이 되어도 두 선택지를 같은 높이로(DU268 r3)
        IntrinsicHeight(
          child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _buildRehireOption(
                context, theme,
                label: '재고용',
                icon: Icons.thumb_up_rounded,
                isSelected: _wouldRehire == true,
                color: AppColors.success,
                onTap: () => setState(() => _wouldRehire = true),
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 10)),
            Expanded(
              child: _buildRehireOption(
                context, theme,
                label: '재고용 안함',
                icon: Icons.thumb_down_rounded,
                isSelected: _wouldRehire == false,
                color: AppColors.error,
                onTap: () => setState(() => _wouldRehire = false),
              ),
            ),
          ],
        ),
        ),
      ],
    );
  }

  Widget _buildRehireOption(
    BuildContext context,
    ThemeData theme, {
    required String label,
    required IconData icon,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    // [DU269] 선택 = 대표색(UI-1, O017 과 같음) — 의미색 채움 위 흰 글자(2.78·3.68)·그림자 대신 brandSurface 면·brand 2 선·
    //   brand 굵은 글자. 미선택은 흰 면·grey300 선·본문색. 최소 48. 선택 상태를 낭독한다([color] 는 남겨 두고 쓰지 않는다).
    return Semantics(
      button: true,
      selected: isSelected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          constraints: const BoxConstraints(minHeight: 48),
          // [DU269 r1] 좌우 16 → 8(O017 과 같음) — B320 에서 '재고/용' 으로 끊겼다
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 8),
            vertical: ResponsiveHelper.spacing(context, 12),
          ),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.brandSurface : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.brand : AppColors.grey300,
              width: isSelected ? 2 : 1,
            ),
          ),
          // [DU269 r1] 큰 글자(DU256 규칙)에서는 아이콘을 글자 위로 — 글자가 칸 폭을 다 쓴다
          child: MediaQuery.textScalerOf(context).scale(10) >= 13
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon,
                        size: ResponsiveHelper.iconSize(context, 18),
                        color: isSelected ? AppColors.brand : AppColors.textSecondary),
                    SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                    Text(TextLayout.keepWords(label),
                        semanticsLabel: label,
                        textAlign: TextAlign.center,
                        style: ResponsiveHelper.bodyStyle(context,
                            color: isSelected ? AppColors.brand : AppColors.textPrimary,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal)),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon,
                        size: ResponsiveHelper.iconSize(context, 18),
                        color: isSelected ? AppColors.brand : AppColors.textSecondary),
                    SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                    Flexible(
                      child: Text(TextLayout.keepWords(label),
                          semanticsLabel: label,
                          textAlign: TextAlign.center,
                          style: ResponsiveHelper.bodyStyle(context,
                              color: isSelected ? AppColors.brand : AppColors.textPrimary,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal)),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  /// [.63] 빠진 선택 안내 — 무엇이 빠졌는지 글자로 보여 준다.
  Widget _buildDroppedNotice(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        // [DU269] 주황 8% 면·40% 선·주황 아이콘(약 2.0) → warningBg 면·warningDark 아이콘, 글자 본문색(O017 과 같음)
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline,
              size: ResponsiveHelper.iconSize(context, 18), color: AppColors.warningDark),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(
              TextLayout.keepWords('지금은 고를 수 없는 태그를 선택에서 뺐습니다: '
                  '${_droppedTags.map((t) => '"$t"').join(', ')}. '
                  '남은 선택을 확인하고 다시 작성해 주세요.'),
              style: ResponsiveHelper.smallStyle(context, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  /// 태그 섹션
  Widget _buildTagSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<String> tags,
    required List<String> selectedTags,
    required ValueChanged<List<String>> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // [DU269] 색 아이콘·의미색 제목(2.2~2.78) → 16 bold 본문색 제목, '복수 선택' textSecondary(O017 과 같음).
        //   [icon]·[iconColor] 는 남겨 두고 그리지 않는다.
        Row(
          children: [
            Expanded(child: _reviewSectionTitle(context, title)),
            Text('복수 선택',
                style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary)),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 10)),
        if (widget.tagsUnavailable || tags.isEmpty)
          Text(
            TextLayout.keepWords(widget.tagsUnavailable
                ? '태그 목록을 불러오지 못했습니다. 태그 없이 작성할 수 있습니다.'
                : '고를 수 있는 태그가 없습니다.'),
            style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary), // [DU269] grey500 2.68
          )
        else
        Wrap(
          spacing: ResponsiveHelper.spacing(context, 8),
          // [DU269] 줄 간격은 칩 겉 상하 8 여백(터치 48)이 맡는다 — 보이는 간격 16(O017 과 같음)
          runSpacing: 0,
          children: tags.map((tag) {
            final isSelected = selectedTags.contains(tag);
            // [DU269] 선택 = 대표색(의미색 채움 위 흰 2.2~2.78 대신), 미선택 본문색
            final fg = isSelected ? AppColors.brand : AppColors.textPrimary;
            // [.62] 선택을 색으로만 알렸다 — 체크 표시와 선택 상태(낭독)를 함께 준다.
            return Semantics(
              button: true,
              selected: isSelected,
              label: tag,
              excludeSemantics: true,
              child: GestureDetector(
                // [DU269] 칩 겉 보이지 않는 상하 8 여백까지 눌린다 — 터치 48 이상(이전 약 34)
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  final newTags = List<String>.from(selectedTags);
                  isSelected ? newTags.remove(tag) : newTags.add(tag);
                  onChanged(newTags);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveHelper.spacing(context, 12),
                      vertical: ResponsiveHelper.spacing(context, 8),
                    ),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.brandSurface : AppColors.background,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? AppColors.brand : AppColors.grey200,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isSelected) ...[
                          Icon(Icons.check, size: ResponsiveHelper.iconSize(context, 14), color: fg),
                          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                        ],
                        Flexible(
                          child: Text(
                            TextLayout.keepWords(tag),
                            style: ResponsiveHelper.smallStyle(context,
                                color: fg,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  /// 상세 코멘트 섹션
  Widget _buildCommentSection(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(context, '상세 코멘트',
            badge: '관리자 전용', hint: '선택 · 다른 관리자에게만 공개'),
        SizedBox(height: ResponsiveHelper.spacing(context, 10)),
        TextField(
          controller: _commentController,
          maxLines: 3,
          maxLength: 500,
          style: ResponsiveHelper.bodyStyle(context),
          decoration: InputDecoration(
            // [.64] 392·2.0 에서 '작성/해주세요' 로 끊겼다.
            hintText: TextLayout.keepWords('채용 시 참고할 내용을 작성해주세요.'),
            hintMaxLines: 3,
            hintStyle: ResponsiveHelper.smallStyle(context, color: AppColors.textTertiary), // [DU269] grey400 1.88
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.grey300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.grey300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.primaryColor, width: 2),
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: ResponsiveHelper.cardPadding(context),
          ),
        ),
      ],
    );
  }

  /// 안내 문구
  Widget _buildNotice(BuildContext context) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        // [DU269] 선 제거(O017 과 같음), 글자 infoDark(infoBg 위 4.03) → infoDeep
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: ResponsiveHelper.iconSize(context, 20),
            color: AppColors.infoDark,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // [.64] 392·2.0 에서 '불가합니/다' 로 끊겼다.
                  TextLayout.keepWords('작성 후 수정이 불가합니다.'),
                  style: ResponsiveHelper.smallStyle(context, color: AppColors.infoDeep).copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                // [.63] '공개됩니/다' 로 음절이 끊겼다.
                Text(
                  TextLayout.keepWords('신중하게 작성해주세요. 상대방도 리뷰를 작성하면 바로 함께 공개되며, 상대방이 작성하지 않으면 리뷰 요청이 온 근무일로부터 14일이 지난 뒤 공개됩니다.'),
                  style: ResponsiveHelper.smallStyle(context, color: AppColors.infoDeep),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 버튼 — ReviewDialogShell scroll 내부에 위치 (keyboard-safe)
  Widget _buildActions(BuildContext context, ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: StyledDialogButton.cancel(
            onPressed: _isSubmitting ? null : () {
              FocusManager.instance.primaryFocus?.unfocus();
              Navigator.pop(context);
            },
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
        Expanded(
          flex: 2,
          child: StyledDialogButton.primary(
            text: '리뷰 작성',
            onPressed: _isSubmitting ? null : _submitReview,
            isLoading: _isSubmitting,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 기작성 리뷰 조회 다이얼로그
// ═══════════════════════════════════════════════════════════════

Future<void> showMonthlyReviewViewDialog(
  BuildContext context, {
  required MonthlyReviewModel review,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _MonthlyReviewViewDialog(review: review),
  );
}

class _MonthlyReviewViewDialog extends StatelessWidget {
  final MonthlyReviewModel review;
  const _MonthlyReviewViewDialog({required this.review});

  @override
  Widget build(BuildContext context) {
    return AppModalShell(
      children: [
        AppModalHeader(
          title: '${review.reviewYear}년 ${review.reviewMonth}월 리뷰',
          subtitle: review.targetUserName ?? '',
          onClose: () => Navigator.pop(context),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: ResponsiveHelper.cardPadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildRatingRow(context),
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                _buildRehireRow(context),
                if (review.positiveTags.isNotEmpty) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                  _buildTagRow(context, '좋았던 점', review.positiveTags,
                      AppColors.success, Icons.thumb_up_outlined),
                ],
                if (review.improvementTags.isNotEmpty) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                  _buildTagRow(context, '아쉬운 점', review.improvementTags,
                      AppColors.warning, Icons.lightbulb_outline),
                ],
                if (review.comment != null && review.comment!.isNotEmpty) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                  _buildCommentRow(context),
                ],
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                _buildPublishStatus(context),
              ],
            ),
          ),
        ),
        AppModalFooter(
          child: SizedBox(
            width: double.infinity,
            child: StyledDialogButton.primary(
              text: '닫기',
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRatingRow(BuildContext context) {
    return Row(
      children: [
        // [DU269] 빈 별 amber(1.63) → textTertiary, 평점 글자 본문색(이전 grey700)
        ...List.generate(5, (i) => Icon(
          i < review.rating ? Icons.star : Icons.star_border,
          size: ResponsiveHelper.iconSize(context, 28),
          color: i < review.rating ? AppColors.amber : AppColors.textTertiary,
        )),
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        Text(review.ratingText,
            style: ResponsiveHelper.bodyStyle(context, color: AppColors.textPrimary)
                .copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildRehireRow(BuildContext context) {
    final rehire = review.wouldRehire;
    if (rehire == null) return const SizedBox.shrink();
    // [DU269] Row → Wrap(B320 79px 넘침). 결과는 선택이 아니라 기록이라 의미색을 진하게(success 2.78·error 3.68 → successDark·errorDark).
    final tone = rehire ? AppColors.successDark : AppColors.errorDark;
    final text = rehire ? '재고용 의사 있음' : '재고용 의사 없음';
    return Wrap(
      spacing: ResponsiveHelper.spacing(context, 8),
      runSpacing: ResponsiveHelper.spacing(context, 4),
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              rehire ? Icons.thumb_up : Icons.thumb_down,
              size: ResponsiveHelper.iconSize(context, 18),
              color: tone,
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            Flexible(
              child: Text(
                TextLayout.keepWords(text),
                semanticsLabel: text,
                style: ResponsiveHelper.smallStyle(context, color: tone, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        _adminOnlyBadge(context, '관리자 전용'),
      ],
    );
  }

  Widget _buildTagRow(BuildContext context, String title, List<String> tags,
      Color color, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // [DU269] 색 아이콘·grey600 작은 제목 → 섹션 제목(작성과 같음). [color]·[icon] 은 남겨 두고 쓰지 않는다.
        _reviewSectionTitle(context, title),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        Wrap(
          spacing: ResponsiveHelper.spacing(context, 6),
          runSpacing: ResponsiveHelper.spacing(context, 6),
          children: tags
              // [DU269] 의미색 10% 면·50% 선·의미색 글자(2.2~2.78) → 바탕색 면·grey200 선·본문색(제목이 좋았던/아쉬운을 말한다)
              .map((tag) => Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 10),
                        vertical: ResponsiveHelper.spacing(context, 6)),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.grey200),
                    ),
                    child: Text(TextLayout.keepWords(tag),
                        semanticsLabel: tag,
                        style: ResponsiveHelper.smallStyle(context, color: AppColors.textPrimary)),
                  ))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildCommentRow(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // [DU269] 색 아이콘·grey600 작은 제목 → 섹션 제목 + 배지(Wrap, B320 20px 넘침)
        Wrap(
          spacing: ResponsiveHelper.spacing(context, 6),
          runSpacing: ResponsiveHelper.spacing(context, 4),
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _reviewSectionTitle(context, '상세 코멘트'),
            _adminOnlyBadge(context, '관리자 전용'),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        Container(
          width: double.infinity,
          padding: ResponsiveHelper.cardPadding(context),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.grey200),
          ),
          child: Text(review.comment!,
              style: ResponsiveHelper.bodyStyle(context, color: AppColors.textPrimary)), // [DU269] grey700
        ),
      ],
    );
  }

  Widget _buildPublishStatus(BuildContext context) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      // [DU269] 선 제거, 글자 infoDark(4.03) → infoDeep, 좁은 칸에서 줄을 바꾼다(Expanded). 줄표는 상태 글자에 붙인다(DU266).
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.schedule,
              size: ResponsiveHelper.iconSize(context, 18),
              color: AppColors.infoDark),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(
              review.isPublished
                  ? TextLayout.keepWords('공개된 리뷰입니다.')
                  : '${TextLayout.unit('${review.publishStatusText} —')} ${TextLayout.keepWords('상대방 작성 완료 시 즉시 공개')}',
              semanticsLabel: review.isPublished
                  ? '공개된 리뷰입니다.'
                  : '${review.publishStatusText} — 상대방 작성 완료 시 즉시 공개',
              style: ResponsiveHelper.smallStyle(context, color: AppColors.infoDeep),
            ),
          ),
        ],
      ),
    );
  }

}

/// [DU269] 섹션 제목 — 작성·조회 공통 16 bold 본문색(O017·시안과 같음), 낱말 단위 줄바꿈(화면 읽기는 원문).
Widget _reviewSectionTitle(BuildContext context, String title) => Text(
      TextLayout.keepWords(title),
      semanticsLabel: title,
      style: ResponsiveHelper.subtitleStyle(context).copyWith(
          fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
    );

/// [DU269] '관리자 전용' 배지 — 작성·조회 공통. warningBg/warningDark(4.81), 13 w600·radius 8(이전 tiny 12·radius 4).
Widget _adminOnlyBadge(BuildContext context, String text) => Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 2),
      ),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: ResponsiveHelper.smallStyle(context,
              color: AppColors.warningDark, fontWeight: FontWeight.w600)),
    );

/// 리뷰 작성 다이얼로그 표시 헬퍼
Future<bool?> showMonthlyReviewDialog(
  BuildContext context, {
  required String reviewerId,
  required String reviewerName,
  required String businessId,
  required String businessName,
  required String targetUserId,
  required String targetUserName,
  String? targetUserGender,
  int? targetUserAge,
  required int reviewYear,
  required int reviewMonth,
  required int workDaysInMonth,
  int? normalAttendanceDays = 0,
  int? lateDays = 0,
  String? requestId,
}) async {
  // 다이얼로그 열기 전 태그 미리 로드 — 빈 폼 플래시 방지
  ReviewTagsModel tags;
  var tagsUnavailable = false;
  try {
    tags = await MonthlyReviewService().getReviewTags();
  } catch (e) {
    debugPrint('❌ 리뷰 태그 조회 실패: $e');
    tags = ReviewTagsModel();
    tagsUnavailable = true;
  }
  if (!context.mounted) return null;

  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => MonthlyReviewDialog(
      reviewerId: reviewerId,
      reviewerName: reviewerName,
      businessId: businessId,
      businessName: businessName,
      targetUserId: targetUserId,
      targetUserName: targetUserName,
      targetUserGender: targetUserGender,
      targetUserAge: targetUserAge,
      reviewYear: reviewYear,
      reviewMonth: reviewMonth,
      workDaysInMonth: workDaysInMonth,
      normalAttendanceDays: normalAttendanceDays,
      lateDays: lateDays,
      requestId: requestId,
      preloadedTags: tags,
      tagsUnavailable: tagsUnavailable,
    ),
  );
}
