// lib/widgets/dialogs/monthly_review_dialog.dart

import 'package:flutter/material.dart';
import '../../utils/responsive_helper.dart';
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
/// - 즉시공개(상대방 작성 시) or 14일 후 자동 공개
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
  
  /// 해당 월 정상 출근 일수
  final int normalAttendanceDays;
  
  /// 해당 월 지각 횟수
  final int lateDays;

  /// review_requests 문서 ID (양방향 공개 연동)
  final String? requestId;

  /// 미리 로드된 태그 목록 (showMonthlyReviewDialog에서 주입)
  final ReviewTagsModel preloadedTags;

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
  });

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

  // 근태 (H-4: 출퇴근 연동 전까지 수동 입력)
  late int _normalDays;
  late int _lateDays;

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

  Future<void> _submitReview() async {
    // 유효성 검사
    if (_wouldRehire == null) {
      ToastHelper.showWarning('재고용 의사를 선택해주세요.');
      return;
    }
    
    setState(() => _isSubmitting = true);

    try {
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
                '리뷰가 작성되었습니다.\n${widget.targetUserName}님도 사업장 리뷰를 작성하면\n즉시 동시에 공개됩니다.\n(미작성 시 14일 후 자동 공개)',
                style: ResponsiveHelper.bodyStyle(resultContext),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            StyledDialogButton.primary(
              text: '확인',
              onPressed: () {
                Navigator.pop(resultContext);
                if (context.mounted) Navigator.pop(context, true);
              },
            ),
          ],
        ),
      );
    } else {
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

  /// 헤더
  Widget _buildHeader(BuildContext context, ThemeData theme) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.primaryColor,
            theme.primaryColor.withValues(alpha: 0.8),
          ],
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.rate_review,
              color: Colors.white,
              size: ResponsiveHelper.iconSize(context, 28),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 16)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.reviewMonth}월 리뷰 작성',
                  style: ResponsiveHelper.titleStyle(context).copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                Text(
                  widget.targetUserName,
                  style: ResponsiveHelper.smallStyle(context, color: Colors.white.withValues(alpha: 0.7)),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.close,
              color: Colors.white,
              size: ResponsiveHelper.iconSize(context, 24),
            ),
          ),
        ],
      ),
    );
  }

  /// 근태 요약
  Widget _buildAttendanceSummary(BuildContext context) {
    final absenceDays = widget.workDaysInMonth - widget.normalAttendanceDays - widget.lateDays;
    
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.grey50,
        borderRadius: BorderRadius.circular(12),
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
                color: AppColors.grey600,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Text(
                '${widget.reviewMonth}월 근태 요약',
                style: ResponsiveHelper.subtitleStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          Row(
            children: [
              _buildStatItem(context, '근무일', '${widget.workDaysInMonth}일', AppColors.info),
              _buildStatItem(context, '정시 출근', '${widget.normalAttendanceDays}일', AppColors.success),
              _buildStatItem(context, '지각', '${widget.lateDays}회', 
                  widget.lateDays > 0 ? AppColors.warning : AppColors.grey400),
              if (absenceDays > 0)
                _buildStatItem(context, '결근', '$absenceDays일', AppColors.error),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(BuildContext context, String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
          Text(
            label,
            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
          ),
        ],
      ),
    );
  }

  /// 평점 섹션
  Widget _buildRatingSection(BuildContext context) {
    final ratingColors = [
      AppColors.error, AppColors.warningDark, AppColors.warning,
      AppColors.success, AppColors.successDark,
    ];
    final activeColor = _rating > 0
        ? ratingColors[_rating - 1]
        : AppColors.amber;

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
            return GestureDetector(
              onTap: () => setState(() => _rating = starIndex),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 6)),
                child: Icon(
                  filled ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: ResponsiveHelper.iconSize(context, 32),
                  color: filled ? AppColors.amber : AppColors.grey300,
                ),
              ),
            );
          }),
        ),
        // 평점 라벨 — 이모지 없이 색상으로 표현
        if (_rating > 0) ...[
          SizedBox(height: ResponsiveHelper.spacing(context, 6)),
          Center(
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 14),
                vertical: ResponsiveHelper.spacing(context, 4),
              ),
              decoration: BoxDecoration(
                color: activeColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _getRatingText(_rating),
                style: ResponsiveHelper.smallStyle(context,
                    color: activeColor, fontWeight: FontWeight.w600),
              ),
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

  Widget _buildDivider(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(
            vertical: ResponsiveHelper.spacing(context, 14)),
        child: const Divider(height: 1, color: AppColors.grey100),
      );

  /// 공통 섹션 라벨 — Wrap으로 좁은 화면에서 자동 줄바꿈
  Widget _buildSectionLabel(BuildContext context, String label,
      {String? badge, String? hint}) {
    return Wrap(
      spacing: ResponsiveHelper.spacing(context, 6),
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(label,
            style: ResponsiveHelper.bodyStyle(context)
                .copyWith(fontWeight: FontWeight.w700)),
        if (badge != null)
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 7),
              vertical: ResponsiveHelper.spacing(context, 2),
            ),
            decoration: BoxDecoration(
              color: AppColors.warningBg,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(badge,
                style: ResponsiveHelper.tinyStyle(context,
                    color: AppColors.warningDark)),
          ),
        if (hint != null)
          Text(hint,
              style: ResponsiveHelper.tinyStyle(context,
                  color: AppColors.grey400)),
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
        Row(
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
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 16),
          vertical: ResponsiveHelper.spacing(context, 12),
        ),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : AppColors.grey200,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [BoxShadow(
                  color: color.withValues(alpha: 0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 3))]
              : [BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 4,
                  offset: const Offset(0, 1))],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: ResponsiveHelper.iconSize(context, 18),
                color: isSelected ? Colors.white : AppColors.grey400),
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            Text(label,
                style: ResponsiveHelper.smallStyle(context,
                    color: isSelected ? Colors.white : AppColors.grey600,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal)),
          ],
        ),
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
        Row(
          children: [
            Icon(icon,
                size: ResponsiveHelper.iconSize(context, 16),
                color: iconColor),
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            Expanded(
              child: Text(title,
                  style: ResponsiveHelper.bodyStyle(context)
                      .copyWith(fontWeight: FontWeight.w700, color: iconColor)),
            ),
            Text('복수 선택',
                style: ResponsiveHelper.tinyStyle(context,
                    color: AppColors.grey400)),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 10)),
        Wrap(
          spacing: ResponsiveHelper.spacing(context, 7),
          runSpacing: ResponsiveHelper.spacing(context, 7),
          children: tags.map((tag) {
            final isSelected = selectedTags.contains(tag);
            return GestureDetector(
              onTap: () {
                final newTags = List<String>.from(selectedTags);
                isSelected ? newTags.remove(tag) : newTags.add(tag);
                onChanged(newTags);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 12),
                  vertical: ResponsiveHelper.spacing(context, 7),
                ),
                decoration: BoxDecoration(
                  color: isSelected ? iconColor : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? iconColor : AppColors.grey200,
                  ),
                ),
                child: Text(
                  tag,
                  style: ResponsiveHelper.smallStyle(context,
                      color: isSelected ? Colors.white : AppColors.grey600,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal),
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
            hintText: '채용 시 참고할 내용을 작성해주세요.',
            hintStyle: ResponsiveHelper.smallStyle(context, color: AppColors.grey400),
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
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
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
                  '작성 후 수정이 불가합니다.',
                  style: ResponsiveHelper.smallStyle(context, color: AppColors.infoDark).copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                Text(
                  '신중하게 작성해주세요. 상대방도 리뷰를 작성하면 즉시 공개되며, 미작성 시 14일 후 자동 공개됩니다.',
                  style: ResponsiveHelper.smallStyle(context, color: AppColors.infoDark),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 버튼
  Widget _buildActions(BuildContext context, ThemeData theme) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: const BoxDecoration(
        color: AppColors.grey50,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(AppDialogSize.borderRadius),
          bottomRight: Radius.circular(AppDialogSize.borderRadius),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: StyledDialogButton.cancel(
              onPressed: _isSubmitting ? null : () => Navigator.pop(context),
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
      ),
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
    builder: (ctx) => _MonthlyReviewViewDialog(review: review),
  );
}

class _MonthlyReviewViewDialog extends StatelessWidget {
  final MonthlyReviewModel review;
  const _MonthlyReviewViewDialog({required this.review});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: AppDialogSize.insetV,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * AppDialogSize.maxHeightRatio,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context, theme),
            Flexible(
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
                    if (review.comment != null &&
                        review.comment!.isNotEmpty) ...[
                      SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                      _buildCommentRow(context),
                    ],
                    SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                    _buildPublishStatus(context),
                  ],
                ),
              ),
            ),
            _buildActions(context, theme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ThemeData theme) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          theme.primaryColor,
          theme.primaryColor.withValues(alpha: 0.8),
        ]),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.rate_review, color: Colors.white,
                size: ResponsiveHelper.iconSize(context, 28)),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 16)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${review.reviewYear}년 ${review.reviewMonth}월 리뷰',
                  style: ResponsiveHelper.titleStyle(context)
                      .copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                Text(review.targetUserName ?? '',
                    style: ResponsiveHelper.smallStyle(context, color: Colors.white70)),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.close, color: Colors.white,
                size: ResponsiveHelper.iconSize(context, 24)),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingRow(BuildContext context) {
    return Row(
      children: [
        ...List.generate(5, (i) => Icon(
          i < review.rating ? Icons.star : Icons.star_border,
          size: ResponsiveHelper.iconSize(context, 28),
          color: AppColors.amber,
        )),
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        Text(review.ratingText,
            style: ResponsiveHelper.bodyStyle(context)
                .copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildRehireRow(BuildContext context) {
    final rehire = review.wouldRehire;
    if (rehire == null) return const SizedBox.shrink();
    return Row(
      children: [
        Icon(
          rehire ? Icons.thumb_up : Icons.thumb_down,
          size: ResponsiveHelper.iconSize(context, 18),
          color: rehire ? AppColors.success : AppColors.error,
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 6)),
        Text(
          rehire ? '재고용 의사 있음' : '재고용 의사 없음',
          style: ResponsiveHelper.smallStyle(context,
              color: rehire ? AppColors.success : AppColors.error),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        Container(
          padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 6),
              vertical: ResponsiveHelper.spacing(context, 2)),
          decoration: BoxDecoration(
            color: AppColors.warningBg,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text('관리자 전용',
              style: ResponsiveHelper.tinyStyle(context,
                  color: AppColors.warningDark)),
        ),
      ],
    );
  }

  Widget _buildTagRow(BuildContext context, String title, List<String> tags,
      Color color, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: ResponsiveHelper.iconSize(context, 16), color: color),
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            Text(title,
                style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600)
                    .copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        Wrap(
          spacing: ResponsiveHelper.spacing(context, 6),
          runSpacing: ResponsiveHelper.spacing(context, 6),
          children: tags
              .map((tag) => Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 10),
                        vertical: ResponsiveHelper.spacing(context, 6)),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: color.withValues(alpha: 0.5)),
                    ),
                    child: Text(tag,
                        style: ResponsiveHelper.smallStyle(context, color: color)),
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
        Row(
          children: [
            Icon(Icons.edit_note,
                size: ResponsiveHelper.iconSize(context, 16),
                color: AppColors.grey600),
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            Text('상세 코멘트',
                style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600)
                    .copyWith(fontWeight: FontWeight.bold)),
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            Container(
              padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 6),
                  vertical: ResponsiveHelper.spacing(context, 2)),
              decoration: BoxDecoration(
                color: AppColors.warningBg,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('관리자 전용',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.warningDark)),
            ),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        Container(
          width: double.infinity,
          padding: ResponsiveHelper.cardPadding(context),
          decoration: BoxDecoration(
            color: AppColors.grey50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.grey200),
          ),
          child: Text(review.comment!,
              style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey700)),
        ),
      ],
    );
  }

  Widget _buildPublishStatus(BuildContext context) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule,
              size: ResponsiveHelper.iconSize(context, 18),
              color: AppColors.infoDark),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Text(
            review.isPublished
                ? '공개된 리뷰입니다.'
                : '${review.publishStatusText} — 상대방 작성 완료 시 즉시 공개',
            style: ResponsiveHelper.smallStyle(context, color: AppColors.infoDark),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context, ThemeData theme) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: const BoxDecoration(
        color: AppColors.grey50,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(AppDialogSize.borderRadius),
          bottomRight: Radius.circular(AppDialogSize.borderRadius),
        ),
      ),
      child: StyledDialogButton.primary(
        text: '닫기',
        onPressed: () => Navigator.pop(context),
      ),
    );
  }
}

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
  int normalAttendanceDays = 0,
  int lateDays = 0,
  String? requestId,
}) async {
  // 다이얼로그 열기 전 태그 미리 로드 — 빈 폼 플래시 방지
  ReviewTagsModel tags;
  try {
    tags = await MonthlyReviewService().getReviewTags();
  } catch (_) {
    tags = ReviewTagsModel.defaults();
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
    ),
  );
}
